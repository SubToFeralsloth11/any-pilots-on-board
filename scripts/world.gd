class_name World
extends Node3D
## One round of the game. Exists on every peer at /root/Main/World.
##
## Authority: the host (peer 1) simulates flight, loose objects, NPCs and the story.
## Each peer simulates only its own Player and streams it to the host, which relays it.
## Clients receive: snapshots (flight + object transforms, 30 Hz), spawn/despawn,
## plane changes, object events, subtitles. See docs/ARCHITECTURE.md for the module contract.

signal subtitle(speaker: String, text: String, duration: float)   ## All peers.
signal toast(text: String)                                         ## This peer only.
signal round_ended(result: Dictionary)                             ## All peers.
signal pilot_changed(peer_id: int)                                 ## All peers.
signal player_fell(peer_id: int)                                   ## Host only.
signal plane_changed(key: String, value: bool)                     ## All peers.

const SNAPSHOT_INTERVAL := 1.0 / 30.0
const FULL_SNAPSHOT_INTERVAL := 2.0
const LOSE_DISTANCE := 90.0        ## Objects this far from the plane are gone forever.
const WIND_ACCEL := 9.0            ## Rearward push outside the hull at cruise speed.
const GRAB_REACH := 4.5
const HOLD_GAIN := 14.0
const HOLD_SNAP := 3.5             ## Held object torn away beyond this distance.
const THROW_SPEED := 15.0
const HEAVY_MASS := 30.0
const WINDOW_PUNCHES := 3
const PART_SLOTS := 16             ## Snapshot key = net_id * PART_SLOTS + part index (0 = root).

const PropsModule := preload("res://scripts/props/props_module.gd")
const NpcModule := preload("res://scripts/npcs/npc_module.gd")
const StoryModule := preload("res://scripts/story/story.gd")
const FunModule := preload("res://scripts/fun/fun_module.gd")
const OutsideScene := preload("res://scripts/outside/outside.gd")
const HudScript := preload("res://scripts/ui/hud.gd")

var flight := FlightModel.new()
var plane: Airliner
var outside: Node3D
var hud: CanvasLayer
var props: Node
var npcs: Node
var story: Node
var fun: Node
var objects_root: Node3D
var players_root: Node3D

var objects := {}          ## net_id -> Node3D
var players := {}          ## peer_id -> Player
var names := {}            ## peer_id -> display name
var holders := {}          ## peer_id -> held net_id (host)
var local_player: Player
var pilot_peer := 0
var locked_doors := {"cockpit": true}
var round_over := false
var result := {}
var stats := {"windows_broken": 0, "items_lost": 0, "passengers_lost": 0, "things_broken": 0,
	"players_fell": 0, "fires_put_out": 0}

var _kinds := {}           ## kind -> Callable(extra: Dictionary) -> Node3D
var _actions := {}         ## action -> Callable(peer_id: int, args: Array)
var _ready_peers := {}     ## Clients that finished loading this round (host).
var _next_id := 1
var _snap_t := 0.0
var _full_t := 0.0
var _last_sent := {}       ## net_id -> Transform3D
var _targets := {}         ## net_id -> Transform3D (clients: interpolation targets)
var _target_att := Vector2.ZERO   ## Clients: (pitch, roll) from the last snapshot.
var _att := Vector2.ZERO          ## Clients: smoothed (pitch, roll) applied to the plane.
var _window_hits := {}


func _ready() -> void:
	plane = Airliner.new()
	plane.name = "Plane"
	add_child(plane)
	outside = OutsideScene.new()
	outside.name = "Outside"
	add_child(outside)
	objects_root = Node3D.new()
	objects_root.name = "Objects"
	add_child(objects_root)
	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)
	_register_core_actions()
	props = _add_module(PropsModule, "Props")
	npcs = _add_module(NpcModule, "Npcs")
	story = _add_module(StoryModule, "Story")
	fun = _add_module(FunModule, "Fun")
	hud = HudScript.new()
	hud.name = "Hud"
	hud.set("world", self)
	add_child(hud)
	_apply_outside_transform()
	# Take the flight attitude before anything spawns, so loose objects start where the plane is.
	plane.set_attitude(flight.pitch, flight.roll)
	if is_server():
		multiplayer.peer_disconnected.connect(_on_peer_left)
		_add_player(1, Net.local_name)
		for m in [props, npcs, story, fun]:
			m.populate()
	else:
		_rpc_client_ready.rpc_id(1, Net.local_name)


func _add_module(script: GDScript, node_name: String) -> Node:
	var m: Node = script.new()
	m.name = node_name
	add_child(m)
	m.setup(self)
	return m


func is_server() -> bool:
	return multiplayer.is_server()


## True while menus/results should swallow gameplay input.
func input_blocked() -> bool:
	return hud != null and hud.has_method("blocking_input") and hud.blocking_input()


# --- Registration (call from module setup(), on every peer) ----------------------------

func register_kind(kind: String, factory: Callable) -> void:
	_kinds[kind] = factory


func register_action(action: String, handler: Callable) -> void:
	_actions[action] = handler


# --- Requests: any peer -> host ----------------------------------------------------------

func request(action: String, args: Array = []) -> void:
	if is_server():
		_handle(1, action, args)
	else:
		_rpc_request.rpc_id(1, action, args)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request(action: String, args: Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if _ready_peers.has(sender):
		_handle(sender, action, args)


func _handle(peer: int, action: String, args: Array) -> void:
	if round_over and action != "shout":
		return
	if _actions.has(action) and players.has(peer):
		_actions[action].call(peer, args)


# --- Objects ---------------------------------------------------------------------------

## Host only. Creates a networked object on every peer.
func spawn_object(kind: String, xform: Transform3D, extra := {}) -> Node3D:
	var id := _next_id
	_next_id += 1
	for p in _ready_peers:
		_rpc_spawn.rpc_id(p, id, kind, xform, extra)
	return _create_object(id, kind, xform, extra)


## Host only.
func despawn_object(id: int) -> void:
	if not objects.has(id):
		return
	for p in _ready_peers:
		_rpc_despawn.rpc_id(p, id)
	_remove_object(id)


## Host only. Runs obj.on_net_event(event, args) on every peer (cosmetics, sounds).
func object_event(id: int, event: String, args: Array = []) -> void:
	for p in _ready_peers:
		_rpc_object_event.rpc_id(p, id, event, args)
	_rpc_object_event(id, event, args)


func get_object(id: int) -> Node3D:
	return objects.get(id)


static func net_id(obj: Object) -> int:
	return int(obj.get_meta("net_id", 0)) if obj else 0


@rpc("authority", "call_remote", "reliable")
func _rpc_spawn(id: int, kind: String, xform: Transform3D, extra: Dictionary) -> void:
	_create_object(id, kind, xform, extra)


@rpc("authority", "call_remote", "reliable")
func _rpc_despawn(id: int) -> void:
	_remove_object(id)


@rpc("authority", "call_remote", "reliable")
func _rpc_object_event(id: int, event: String, args: Array) -> void:
	var obj: Node3D = objects.get(id)
	if obj and obj.has_method("on_net_event"):
		obj.on_net_event(event, args)


func _create_object(id: int, kind: String, xform: Transform3D, extra: Dictionary) -> Node3D:
	if not _kinds.has(kind):
		push_error("Unknown object kind: " + kind)
		return null
	var obj: Node3D = _kinds[kind].call(extra)
	obj.name = "o%d" % id
	obj.set_meta("net_id", id)
	obj.set_meta("kind", kind)
	obj.set_meta("extra", extra)
	objects_root.add_child(obj)
	obj.global_transform = xform
	objects[id] = obj
	_targets[id * PART_SLOTS] = xform
	if not is_server():
		for node in _net_nodes(obj):
			if node is RigidBody3D:
				node.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				node.freeze = true
	return obj


func _remove_object(id: int) -> void:
	var obj: Node3D = objects.get(id)
	objects.erase(id)
	for i in PART_SLOTS:
		_targets.erase(id * PART_SLOTS + i)
		_last_sent.erase(id * PART_SLOTS + i)
	for peer in holders.keys():
		if holders[peer] == id:
			_set_held(peer, 0)
	if obj:
		obj.queue_free()


# --- Plane, chat, stats ----------------------------------------------------------------

## Host only. Broadcasts a plane state change (see Airliner.apply_change keys).
func set_plane(key: String, value: bool) -> void:
	for p in _ready_peers:
		_rpc_plane.rpc_id(p, key, value)
	_rpc_plane(key, value)


@rpc("authority", "call_remote", "reliable")
func _rpc_plane(key: String, value: bool) -> void:
	plane.apply_change(key, value)
	if key == "gear":
		flight.gear_down = value
	plane_changed.emit(key, value)


## Host only. Breaks window i (counts it once).
func break_window(i: int) -> void:
	if i < 0 or i >= plane.windows.size() or plane.windows[i].broken:
		return
	stats.windows_broken += 1
	set_plane("window:%d" % i, true)


## Host only. Subtitle line on every screen.
func say(speaker: String, text: String, duration := 3.5) -> void:
	for p in _ready_peers:
		_rpc_say.rpc_id(p, speaker, text, duration)
	_rpc_say(speaker, text, duration)


@rpc("authority", "call_remote", "reliable")
func _rpc_say(speaker: String, text: String, duration: float) -> void:
	subtitle.emit(speaker, text, duration)


## Host only. Small message for one player.
func notify(peer: int, text: String) -> void:
	if peer == multiplayer.get_unique_id():
		toast.emit(text)
	elif _ready_peers.has(peer):
		_rpc_toast.rpc_id(peer, text)


@rpc("authority", "call_remote", "reliable")
func _rpc_toast(text: String) -> void:
	toast.emit(text)


func add_stat(key: String, amount := 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount


## Host only. Adds velocity to a player (knockbacks, extinguisher thrust, turbulence).
func push_player(peer: int, vel: Vector3) -> void:
	if peer == multiplayer.get_unique_id():
		_rpc_push(vel)
	elif _ready_peers.has(peer):
		_rpc_push.rpc_id(peer, vel)


@rpc("authority", "call_remote", "reliable")
func _rpc_push(vel: Vector3) -> void:
	if local_player:
		local_player.apply_push(vel)


## Host only. Camera shake on every screen.
func shake_all(amount: float) -> void:
	for p in _ready_peers:
		_rpc_shake.rpc_id(p, amount)
	_rpc_shake(amount)


@rpc("authority", "call_remote", "reliable")
func _rpc_shake(amount: float) -> void:
	if local_player:
		local_player.shake(amount)


func display_name(peer: int) -> String:
	return names.get(peer, "Passenger %d" % peer)


# --- Players ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_ready(player_name: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if _ready_peers.has(sender):
		return
	var objs := []
	for id in objects:
		var o: Node3D = objects[id]
		var extra: Dictionary = o.get_spawn_extra() if o.has_method("get_spawn_extra") else o.get_meta("extra")
		objs.append([id, o.get_meta("kind"), o.global_transform, extra])
	var sync := {"names": names, "objects": objs, "plane": plane.get_state(), "damage": plane.damage,
		"flight": flight.to_array(),
		"pilot": pilot_peer, "locked": locked_doors, "holders": holders, "round_over": round_over,
		"result": result, "story": story.get_sync() if story.has_method("get_sync") else {}}
	_rpc_sync.rpc_id(sender, sync)
	player_name = player_name.strip_edges().left(20)
	if player_name == "":
		player_name = "Passenger %d" % sender
	for p in _ready_peers:
		_rpc_add_player.rpc_id(p, sender, player_name)
	_ready_peers[sender] = true
	_rpc_add_player.rpc_id(sender, sender, player_name)
	_add_player(sender, player_name)


@rpc("authority", "call_remote", "reliable")
func _rpc_sync(s: Dictionary) -> void:
	for peer in s.names:
		_add_player(peer, s.names[peer])
	for o in s.objects:
		_create_object(o[0], o[1], o[2], o[3])
	plane.apply_state(s.plane)
	for part in s.damage:
		plane.set_damage(part, s.damage[part])
	flight.from_array(s.flight)
	locked_doors = s.locked
	_set_pilot(s.pilot)
	for peer in s.holders:
		_set_held(peer, s.holders[peer])
	if story.has_method("apply_sync"):
		story.apply_sync(s.story)
	if s.round_over:
		_rpc_round_end(s.result)


@rpc("authority", "call_remote", "reliable")
func _rpc_add_player(peer: int, player_name: String) -> void:
	_add_player(peer, player_name)


@rpc("authority", "call_remote", "reliable")
func _rpc_remove_player(peer: int) -> void:
	_remove_player(peer)


func _add_player(peer: int, player_name: String) -> void:
	if players.has(peer):
		return
	names[peer] = player_name
	print("[world %d] player %d joined: %s" % [multiplayer.get_unique_id(), peer, player_name])
	var p := Player.new()
	p.name = str(peer)
	p.peer_id = peer
	p.display_name = player_name
	p.world = self
	p.is_local = peer == multiplayer.get_unique_id()
	players_root.add_child(p)
	var seat: Vector3 = plane.seats[(players.size() * 9 + 3) % plane.seats.size()]
	p.global_position = plane.to_global(seat)
	players[peer] = p
	if p.is_local:
		local_player = p
		p.sit(seat)


func _remove_player(peer: int) -> void:
	var p: Player = players.get(peer)
	players.erase(peer)
	names.erase(peer)
	if p:
		p.queue_free()


func _on_peer_left(peer: int) -> void:
	_ready_peers.erase(peer)
	if holders.has(peer):
		_release(peer)
	if pilot_peer == peer:
		_broadcast_pilot(0)
	_remove_player(peer)
	for p in _ready_peers:
		_rpc_remove_player.rpc_id(p, peer)


## Called by the local Player ~30 Hz.
func send_player_state(st: Array) -> void:
	if is_server():
		_relay_state(1, st)
	else:
		_rpc_pstate_up.rpc_id(1, st)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_pstate_up(st: Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if _ready_peers.has(sender) and players.has(sender):
		players[sender].apply_remote_state(st)
		_relay_state(sender, st)


func _relay_state(peer: int, st: Array) -> void:
	for p in _ready_peers:
		if p != peer:
			_rpc_pstate_down.rpc_id(p, peer, st)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_pstate_down(peer: int, st: Array) -> void:
	if players.has(peer) and peer != multiplayer.get_unique_id():
		players[peer].apply_remote_state(st)


# --- Core actions ------------------------------------------------------------------------

func _register_core_actions() -> void:
	register_action("grab", _act_grab)
	register_action("drop", func(peer: int, _a: Array) -> void: _release(peer))
	register_action("throw", _act_throw)
	register_action("punch", _act_punch)
	register_action("punch_player", _act_punch_player)
	register_action("break_window", _act_break_window)
	register_action("door", _act_door)
	register_action("ramp", _act_ramp)
	register_action("pilot_enter", _act_pilot_enter)
	register_action("pilot_exit", func(peer: int, _a: Array) -> void:
		if pilot_peer == peer:
			_broadcast_pilot(0))
	register_action("gear", _act_gear)
	register_action("fell_out", _act_fell_out)
	register_action("use_item", _act_use_item)
	register_action("flaps", func(peer: int, _a: Array) -> void:
		if peer == pilot_peer:
			flight.flaps = (flight.flaps + 1) % 3
			notify(peer, "Flaps %s" % ["UP", "HALF", "FULL"][flight.flaps]))


func _player_near(peer: int, global_p: Vector3, reach: float) -> bool:
	var p: Player = players.get(peer)
	return p != null and p.global_position.distance_to(global_p) <= reach + 1.5


func _act_grab(peer: int, args: Array) -> void:
	var obj := objects.get(int(args[0])) as RigidBody3D
	if obj == null or not obj.is_in_group("grabbable") or holders.has(peer) or pilot_peer == peer:
		return
	if holders.values().has(net_id(obj)):
		return
	if not _player_near(peer, obj.global_position, GRAB_REACH):
		return
	if obj.has_method("can_grab") and not obj.can_grab(peer):
		return
	_set_held(peer, net_id(obj))
	if obj.has_method("on_grabbed"):
		obj.on_grabbed(peer)


func _release(peer: int) -> RigidBody3D:
	var obj := objects.get(int(holders.get(peer, 0))) as RigidBody3D
	_set_held(peer, 0)
	if obj and obj.has_method("on_released"):
		obj.on_released()
	return obj


func _act_throw(peer: int, args: Array) -> void:
	var dir: Vector3 = (args[1] as Vector3).normalized()
	if int(holders.get(peer, 0)) != int(args[0]):
		return
	var obj := _release(peer)
	if obj == null:
		return
	var speed := THROW_SPEED if obj.mass < HEAVY_MASS else THROW_SPEED * 0.5
	obj.linear_velocity = dir * speed + Vector3(0, 1.5, 0)
	obj.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	if obj.has_method("on_thrown"):
		obj.on_thrown(peer)


func _act_punch(peer: int, args: Array) -> void:
	var obj := objects.get(int(args[0])) as RigidBody3D
	if obj == null or not _player_near(peer, obj.global_position, 3.0):
		return
	var dir: Vector3 = (args[1] as Vector3).normalized()
	obj.apply_central_impulse((dir + Vector3(0, 0.3, 0)) * clampf(obj.mass * 4.0, 2.0, 120.0))
	if obj.has_method("on_punched"):
		obj.on_punched(peer, dir)


func _act_punch_player(peer: int, args: Array) -> void:
	var target := int(args[0])
	var tp: Player = players.get(target)
	if tp == null or target == peer or not _player_near(peer, tp.global_position, 3.0):
		return
	var dir: Vector3 = (args[1] as Vector3).normalized()
	push_player(target, dir * 7.0 + Vector3(0, 3.0, 0))


func _act_break_window(peer: int, args: Array) -> void:
	var i := int(args[0])
	if i < 0 or i >= plane.windows.size() or plane.windows[i].broken:
		return
	if not _player_near(peer, plane.to_global(plane.windows[i].pos), 3.0):
		return
	_window_hits[i] = int(_window_hits.get(i, 0)) + 1
	if _window_hits[i] >= WINDOW_PUNCHES:
		_window_hits.erase(i)
		break_window(i)
		say(display_name(peer), "...oops.", 2.0)
	else:
		notify(peer, "*CRACK* The window is cracking (%d/%d)" % [_window_hits[i], WINDOW_PUNCHES])


func _act_door(peer: int, args: Array) -> void:
	var door: String = args[0]
	if not plane.doors.has(door) or not _player_near(peer, plane.to_global(plane.doors[door].pos), 3.0):
		return
	if locked_doors.has(door):
		notify(peer, "It's locked.")
		return
	set_plane("door:" + door, not plane.doors[door].open)


func _act_ramp(peer: int, _args: Array) -> void:
	if _player_near(peer, plane.to_global(Airliner.RAMP_LEVER), 3.0):
		set_plane("ramp", not plane.ramp_open)


func _act_pilot_enter(peer: int, _args: Array) -> void:
	if pilot_peer != 0 or not _player_near(peer, plane.to_global(Airliner.PILOT_SEAT), 2.5):
		return
	if story.has_method("can_pilot") and not story.can_pilot(peer):
		return
	if holders.has(peer):
		_release(peer)
	_broadcast_pilot(peer)


func _act_gear(peer: int, _args: Array) -> void:
	if peer == pilot_peer and flight.phase == FlightModel.Phase.FLYING:
		set_plane("gear", not flight.gear_down)


## Right-click with something in hand: the held object's own use(peer, origin, dir) runs on the host.
func _act_use_item(peer: int, args: Array) -> void:
	var id := int(args[0])
	var obj: Node3D = objects.get(id)
	if obj == null or int(holders.get(peer, 0)) != id or not obj.has_method("use"):
		return
	obj.use(peer, args[1] as Vector3, (args[2] as Vector3).normalized())


func _act_fell_out(peer: int, _args: Array) -> void:
	add_stat("players_fell")
	var held: Node3D = objects.get(int(holders.get(peer, 0)))
	if held and held.get_meta("kind") == "parachute":
		say(display_name(peer), "*floats gently past the window with a parachute*", 3.0)
	else:
		say(display_name(peer), "AAAAAAAAAAAAAAAAAA", 2.5)
	if holders.has(peer):
		_release(peer)
	player_fell.emit(peer)


func _broadcast_pilot(peer: int) -> void:
	for p in _ready_peers:
		_rpc_pilot.rpc_id(p, peer)
	_rpc_pilot(peer)


@rpc("authority", "call_remote", "reliable")
func _rpc_pilot(peer: int) -> void:
	_set_pilot(peer)


func _set_pilot(peer: int) -> void:
	pilot_peer = peer
	flight.has_pilot = peer != 0
	if peer == 0:
		flight.pitch_in = 0.0
		flight.roll_in = 0.0
		flight.throttle_in = 0.0
	for id in players:
		players[id].piloting = id == peer
	pilot_changed.emit(peer)


## Called by the piloting local Player ~30 Hz.
func send_pilot_input(pitch_in: float, roll_in: float, throttle_in: float) -> void:
	if is_server():
		_apply_pilot_input(1, pitch_in, roll_in, throttle_in)
	else:
		_rpc_pilot_input.rpc_id(1, pitch_in, roll_in, throttle_in)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_pilot_input(pitch_in: float, roll_in: float, throttle_in: float) -> void:
	_apply_pilot_input(multiplayer.get_remote_sender_id(), pitch_in, roll_in, throttle_in)


func _apply_pilot_input(peer: int, pitch_in: float, roll_in: float, throttle_in: float) -> void:
	if peer != pilot_peer:
		return
	flight.pitch_in = clampf(pitch_in, -1, 1)
	flight.roll_in = clampf(roll_in, -1, 1)
	flight.throttle_in = clampf(throttle_in, -1, 1)


func _set_held(peer: int, id: int) -> void:
	if id == 0:
		holders.erase(peer)
	else:
		holders[peer] = id
	if is_server():
		for p in _ready_peers:
			_rpc_held.rpc_id(p, peer, id)
	if players.has(peer):
		players[peer].held_id = id


@rpc("authority", "call_remote", "reliable")
func _rpc_held(peer: int, id: int) -> void:
	_set_held(peer, id)


# --- Simulation --------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if is_server():
		_update_damage(dt)
		flight.step(dt)
		plane.set_attitude(flight.pitch, flight.roll)
		_update_objects()
		_send_snapshots(dt)
		_check_round_end()
	else:
		# Smooth toward the last snapshot; extrapolate position between packets.
		var k := clampf(dt * 15.0, 0.0, 1.0)
		_att = _att.lerp(_target_att, k)
		plane.set_attitude(_att.x, _att.y)
		if flight.phase == FlightModel.Phase.FLYING or flight.phase == FlightModel.Phase.ROLLING:
			flight.pos += flight.velocity * dt
		for key in _targets:
			var node := _net_node(key)
			if node:
				node.global_transform = node.global_transform.interpolate_with(_targets[key], k)
	plane.airborne = flight.phase == FlightModel.Phase.FLYING
	plane.set_flaps(flight.flaps)
	var felt := flight.felt_accel
	var space := get_world_3d().space
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, felt.length())
	if felt.length_squared() > 0.0001:
		PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, felt.normalized())
	_apply_outside_transform()


func _apply_outside_transform() -> void:
	var view := Transform3D(Basis(Vector3.UP, flight.yaw), flight.pos + Vector3(0, Airliner.GEAR_HEIGHT, 0))
	outside.transform = view.affine_inverse()


# --- Plane damage (host) --------------------------------------------------------------------

const BURN_ENGINE := 0.025         ## Engine health lost per second while burning.
const BURN_WING := 0.008
const AUTO_FIRE_HEALTH := 0.3      ## Engines this hurt may catch fire on their own.
const AUTO_FIRE_CHANCE := 0.02     ## Per second.
const DAMAGE_SYNC_STEP := 0.02     ## Health change that triggers a network update.

var _damage_sent := {}


## Host only. Positive amount damages, negative repairs. Parts: Airliner.DAMAGE_PARTS.
func damage_plane(part: String, amount: float) -> void:
	if not plane.damage.has(part):
		return
	var h := clampf(float(plane.damage[part]) - amount, 0.0, 1.0)
	plane.set_damage(part, h)
	var sent := float(_damage_sent.get(part, 1.0))
	if absf(h - sent) >= DAMAGE_SYNC_STEP or ((h == 0.0 or h == 1.0) and h != sent):
		_damage_sent[part] = h
		for p in _ready_peers:
			_rpc_damage.rpc_id(p, part, h)


## Host only. Damages whatever part of the plane is at a world point (breaking a window
## if one is right there) and leaves a scorch mark. Returns the part name.
func damage_plane_at(global_p: Vector3, amount: float) -> String:
	var w := plane.window_near(global_p, 0.8)
	if w >= 0 and not plane.windows[w].broken:
		break_window(w)
	var part := plane.part_at(global_p)
	damage_plane(part, amount)
	var local := plane.to_local(global_p)
	for p in _ready_peers:
		_rpc_scar.rpc_id(p, local)
	_rpc_scar(local)
	return part


@rpc("authority", "call_remote", "reliable")
func _rpc_damage(part: String, health: float) -> void:
	plane.set_damage(part, health)


@rpc("authority", "call_remote", "reliable")
func _rpc_scar(local: Vector3) -> void:
	plane.add_scar(local)


## Fires burn engines and wings down; wrecked engines flame out or catch fire.
func _update_damage(dt: float) -> void:
	for i in 2:
		var engine := "engine%d" % i
		var burning: bool = plane.engine_fire[i]
		if burning:
			damage_plane(engine, BURN_ENGINE * dt)
			damage_plane("wing%d" % i, BURN_WING * dt)
		elif plane.damage[engine] < AUTO_FIRE_HEALTH and plane.damage[engine] > 0.0 \
				and flight.phase == FlightModel.Phase.FLYING and randf() < AUTO_FIRE_CHANCE * dt:
			set_plane("fire:%d" % i, true)
			say("TOWER", "Your %s engine is ON FIRE. That's... not ideal." % ["left", "right"][i], 3.5)
		var health := float(plane.damage[engine])
		flight.engine_power[i] = 0.0 if health < 0.15 else clampf(health * 1.25, 0.0, 1.0) * (0.6 if burning else 1.0)
	flight.wing_health = [plane.damage.wing0, plane.damage.wing1]
	flight.tail_health = plane.damage.tail
	flight.hull_health = plane.damage.hull


func _update_objects() -> void:
	var wind := plane.global_basis.z * WIND_ACCEL * clampf(flight.speed / 70.0, 0.0, 1.5)
	var flying := flight.phase == FlightModel.Phase.FLYING
	for id in objects.keys():
		var obj := objects[id] as RigidBody3D
		if obj == null:
			continue
		var p := obj.global_position
		if (flying and p.length() > LOSE_DISTANCE) or p.y < -60.0:
			add_stat("passengers_lost" if obj.is_in_group("npc") else "items_lost")
			if obj.has_method("on_lost"):
				obj.on_lost()
			despawn_object(id)
			continue
		var accel := plane.get_suction(p)
		if flying and plane.is_outside(p):
			accel += wind
		if accel != Vector3.ZERO:
			obj.apply_central_force(accel * obj.mass)
	for peer in holders.keys():
		var obj := objects.get(int(holders[peer])) as RigidBody3D
		var pl: Player = players.get(peer)
		if obj == null or pl == null:
			_set_held(peer, 0)
			continue
		var to := pl.hold_point - obj.global_position
		if to.length() > HOLD_SNAP:
			_release(peer)
			notify(peer, "It slipped out of your hands!")
			continue
		obj.linear_velocity = (to * HOLD_GAIN).limit_length(20.0)
		obj.angular_velocity *= 0.85


func _send_snapshots(dt: float) -> void:
	_snap_t += dt
	_full_t += dt
	if _snap_t < SNAPSHOT_INTERVAL or _ready_peers.is_empty():
		return
	_snap_t = 0.0
	var full := _full_t >= FULL_SNAPSHOT_INTERVAL
	if full:
		_full_t = 0.0
	var keys := PackedInt32Array()
	var xf := PackedFloat32Array()
	for id in objects:
		var nodes := _net_nodes(objects[id], true)
		for i in nodes.size():
			var key: int = id * PART_SLOTS + i
			var t := nodes[i].global_transform
			var last: Variant = _last_sent.get(key)
			if not full and last != null and (last as Transform3D).origin.distance_squared_to(t.origin) < 0.0001 \
					and (last as Transform3D).basis.get_rotation_quaternion().angle_to(t.basis.get_rotation_quaternion()) < 0.01:
				continue
			_last_sent[key] = t
			var q := t.basis.get_rotation_quaternion()
			keys.append(key)
			xf.append_array([t.origin.x, t.origin.y, t.origin.z, q.x, q.y, q.z, q.w])
	var f := flight.to_array()
	for p in _ready_peers:
		_rpc_snapshot.rpc_id(p, f, keys, xf)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(f: PackedFloat32Array, keys: PackedInt32Array, xf: PackedFloat32Array) -> void:
	flight.from_array(f)
	_target_att = Vector2(flight.pitch, flight.roll)
	for i in keys.size():
		var o := i * 7
		var q := Quaternion(xf[o + 3], xf[o + 4], xf[o + 5], xf[o + 6])
		_targets[keys[i]] = Transform3D(Basis(q), Vector3(xf[o], xf[o + 1], xf[o + 2]))


## Root body plus ragdoll parts (get_net_parts). With active_only, parts are skipped
## while the object reports net_parts_active() == false (e.g. an NPC sitting calmly).
func _net_nodes(obj: Node3D, active_only := false) -> Array[Node3D]:
	var out: Array[Node3D] = [obj]
	if obj.has_method("get_net_parts"):
		if active_only and obj.has_method("net_parts_active") and not obj.net_parts_active():
			return out
		for part in obj.get_net_parts():
			if out.size() < PART_SLOTS:
				out.append(part)
	return out


## Snapshot key -> node (root when key % PART_SLOTS == 0, else that ragdoll part).
func _net_node(key: int) -> Node3D:
	var obj: Node3D = objects.get(key / PART_SLOTS)
	if obj == null:
		return null
	var i := key % PART_SLOTS
	if i == 0:
		return obj
	var nodes := _net_nodes(obj, true)
	return nodes[i] if i < nodes.size() else null


func _check_round_end() -> void:
	if round_over:
		return
	if flight.phase != FlightModel.Phase.LANDED and flight.phase != FlightModel.Phase.CRASHED:
		return
	var r := Scoring.result(flight, stats)
	for p in _ready_peers:
		_rpc_round_end.rpc_id(p, r)
	_rpc_round_end(r)


@rpc("authority", "call_remote", "reliable")
func _rpc_round_end(r: Dictionary) -> void:
	round_over = true
	result = r
	round_ended.emit(r)
