extends RigidBody3D
## One networked loose object from the Props module: luggage, cans, laptops, the drinks cart,
## cargo crates, items and debris. Visuals come from prop_looks.gd, [RMB] behaviour from items.gd.
##
## Host only: impact detection (breakage, window smashing, thrown-wrench hits), can fizzing,
## crate pushing, banana-peel slipping and debris expiry. Every visible result is broadcast
## with world.object_event and handled in on_net_event on all peers.

const Looks := preload("res://scripts/props/prop_looks.gd")
const Items := preload("res://scripts/props/items.gd")
const Fx := preload("res://scripts/props/fx.gd")

const BREAK_SPEED := 7.0       ## Velocity change in one contact that breaks a breakable.
const GLASS_SPEED := 6.0       ## Impact speed that smashes a window.
const WRENCH_SMASH_SPEED := 4.0
const SPAWN_GRACE := 1.5       ## No breakage while freshly spawned objects settle.
const DEBRIS_LIFE := 10.0
const FIZZ_TIME := 2.5
const FIZZ_THRUST := 32.0
const THROWN_TIME := 2.0
const SLIP_RADIUS := 0.45
const SLIP_COOLDOWN := 2.0
const CRATE_PUSH_RANGE := 0.95

const SLIP_LINES := ["WHOA-OA-OAAA!", "*slips on a banana peel like a cartoon*", "MY SPINE!",
	"Who left a banana peel on a PLANE?!", "*does a full backflip, accidentally*"]
const NO_CCD := ["crate", "cart", "debris"]

static var _physics_mats := {}

var world: World
var spawn_debris: Callable   ## Module hook: (kind, extra, at, vel) -> void (host).
var player_velocity: Callable  ## Module hook: (peer) -> Vector3 (host).
var kind := ""
var state := {}               ## Cosmetic/gameplay state; doubles as the late-join spawn extra.
var parts := {}               ## Named visual nodes from Looks.build().
var cooldown := 0.0           ## Host: seconds until use() works again.

var _age := 0.0
var _prev_vel := Vector3.ZERO
var _thrown_t := 0.0
var _thrower := 0
var _fizz_t := 0.0
var _broken := false
var _pending: Array[Callable] = []   ## Host reactions deferred out of physics callbacks.
var _slip_until := {}                ## Body/peer key -> time it can slip again.


## Called by the factory before the body enters the tree.
func setup(w: World, p_kind: String, extra: Dictionary, debris_hook: Callable, velocity_hook: Callable) -> void:
	world = w
	spawn_debris = debris_hook
	player_velocity = velocity_hook
	kind = p_kind
	state = extra.duplicate()
	var spec: Dictionary = Looks.SPECS[kind]
	mass = spec.mass
	physics_material_override = _physics_mat(spec.friction)
	collision_layer = Layers.PROP
	collision_mask = Layers.WORLD if kind == "debris" else Layers.WORLD | Layers.PLAYER | Layers.PROP | Layers.NPC
	continuous_cd = not NO_CCD.has(kind)
	if spec.grab:
		add_to_group("grabbable")
	if kind == "cart":
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		center_of_mass = Vector3(0, -0.3, 0)
	if kind == "crate" and not state.get("searched", false):
		set_meta("action", "search")


func _ready() -> void:
	Looks.fill_defaults(kind, state, World.net_id(self))
	Looks.build(self, kind, state, parts)
	if kind == "banana" and state.get("peeled", false):
		Looks.show_peel(parts)
	var host := world.is_server()
	set_physics_process(host)
	if host:
		contact_monitor = true
		max_contacts_reported = 4
		body_shape_entered.connect(_on_body_shape_entered)


func get_prompt() -> String:
	if kind == "crate" and not has_meta("action"):
		return "An empty crate (you looted it)"
	if kind == "banana" and state.get("peeled", false):
		return Looks.prompt("peel")
	return Looks.prompt(kind)


func get_spawn_extra() -> Dictionary:
	return state


func on_grabbed(peer: int) -> void:
	var key := "peel" if kind == "banana" and state.get("peeled", false) else kind
	if Looks.HINTS.has(key):
		world.notify(peer, Looks.HINTS[key])


func on_thrown(peer: int) -> void:
	_thrown_t = THROWN_TIME
	_thrower = peer


## [RMB] with this object in hand (host; World already checked the holder).
func use(peer: int, origin: Vector3, dir: Vector3) -> void:
	if cooldown <= 0.0 and not _broken:
		Items.use(self, peer, origin, dir)


## Breaks this object if it is breakable (wrench whacks, hard hits). Returns true if it reacted.
func smash(_peer := 0) -> bool:
	if _broken or not Looks.BREAKABLE.has(kind):
		return false
	match kind:
		"can":
			if _fizz_t <= 0.0:
				_start_fizz()
			else:
				_break()
		"laptop":
			if state.get("bsod", false):
				_break()
			else:
				state.bsod = true
				world.object_event(World.net_id(self), "bsod")
		_:
			_break()
	return true


## Host: spawns this crate's loot burst. Returns false if it was already searched.
func open_crate() -> bool:
	if kind != "crate" or state.get("searched", false):
		return false
	state.searched = true
	world.object_event(World.net_id(self), "burst")
	return true


# --- Host simulation ------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	_age += dt
	cooldown = maxf(0.0, cooldown - dt)
	_thrown_t = maxf(0.0, _thrown_t - dt)
	var queued := _pending
	_pending = []
	for c in queued:
		c.call()
	if _broken:
		return
	match kind:
		"debris":
			if _age > DEBRIS_LIFE:
				_broken = true
				world.despawn_object(World.net_id(self))
				return
		"can":
			if _fizz_t > 0.0:
				_fizz_step(dt)
		"crate":
			_crate_push()
		"peel":
			_slip_check()
		"banana":
			if state.get("peeled", false):
				_slip_check()
	_prev_vel = linear_velocity


func _held() -> bool:
	return world.holders.values().has(World.net_id(self))


func _on_body_shape_entered(_rid: RID, body: Node, body_shape_index: int, _local_shape: int) -> void:
	if _broken or _age < SPAWN_GRACE or _held() or body == null:
		return
	var approach := _prev_vel.length()
	var jolt := (_prev_vel - linear_velocity).length()
	if body is Airliner and approach > GLASS_SPEED:
		var w := (body as Airliner).window_for_shape(body_shape_index)
		if w >= 0:
			_pending.append(world.break_window.bind(w))
	if kind == "wrench" and _thrown_t > 0.0 and approach > WRENCH_SMASH_SPEED and body.has_method("smash"):
		_pending.append(_wrench_hit.bind(body))
	if jolt > BREAK_SPEED and Looks.BREAKABLE.has(kind):
		_pending.append(smash.bind(0))


func _wrench_hit(body: Node) -> void:
	if is_instance_valid(body) and body.call("smash", _thrower):
		world.object_event(World.net_id(self), "clang")


func _break() -> void:
	if _broken:
		return
	_broken = true
	var id := World.net_id(self)
	world.add_stat("things_broken")
	world.object_event(id, "break")
	spawn_debris.call(kind, state, global_position, linear_velocity)
	world.despawn_object(id)


func _start_fizz() -> void:
	_fizz_t = FIZZ_TIME
	world.object_event(World.net_id(self), "fizz")


## A burst can turns into a tiny spinning rocket, then gives up.
func _fizz_step(dt: float) -> void:
	_fizz_t -= dt
	if _fizz_t <= 0.0:
		_break()
		return
	apply_central_force(global_basis.y * mass * FIZZ_THRUST)
	apply_torque(Vector3(randf_range(-1, 1), 4.0, randf_range(-1, 1)) * 0.004)


## Heavy crates scoot along when a player walks into them.
func _crate_push() -> void:
	var up := world.plane.global_basis.y
	for peer in world.players:
		var pl: Player = world.players[peer]
		var d := global_position - pl.global_position
		var height := d.dot(up)
		d -= up * height
		if d.length() > CRATE_PUSH_RANGE or height > 0.9 or height < -0.2:
			continue
		var n := d.normalized()
		var mv: Vector3 = player_velocity.call(peer)
		var along := mv.dot(n)
		if along > 0.3:
			var cur := linear_velocity.dot(n)
			apply_central_force(n * mass * clampf((along * 0.8 - cur) * 10.0, 0.0, 22.0))


## Players and passengers who walk over a peel on the floor go flying.
func _slip_check() -> void:
	if _held():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var up := world.plane.global_basis.y
	for peer in world.players:
		var pl: Player = world.players[peer]
		var mv: Vector3 = player_velocity.call(peer)
		if pl.seated or now < float(_slip_until.get(peer, 0.0)) or mv.length() < 1.2:
			continue
		if pl.global_position.distance_to(global_position) > SLIP_RADIUS:
			continue
		_slip_until[peer] = now + SLIP_COOLDOWN
		var fwd := (mv - up * mv.dot(up)).normalized()
		world.push_player(peer, fwd * 6.5 + up * 5.0)
		world.say(world.display_name(peer), SLIP_LINES.pick_random(), 2.5)
		_slipped(-fwd)
	for npc in get_tree().get_nodes_in_group("npc"):
		var body := npc as RigidBody3D
		if body == null or now < float(_slip_until.get(body.get_instance_id(), 0.0)):
			continue
		if body.linear_velocity.length() < 1.0 or body.global_position.distance_to(global_position) > SLIP_RADIUS + 0.3:
			continue
		_slip_until[body.get_instance_id()] = now + SLIP_COOLDOWN
		var dir := body.linear_velocity.normalized()
		body.apply_central_impulse((dir * 3.0 + up * 4.0) * body.mass)
		if body.has_method("on_punched"):
			body.on_punched(0, dir)
		_slipped(-dir)


func _slipped(kick: Vector3) -> void:
	world.object_event(World.net_id(self), "slip")
	apply_central_impulse((kick + world.plane.global_basis.y * 0.6) * mass * 3.0)


static func _physics_mat(friction: float) -> PhysicsMaterial:
	if not _physics_mats.has(friction):
		var m := PhysicsMaterial.new()
		m.friction = friction
		m.bounce = 0.08
		_physics_mats[friction] = m
	return _physics_mats[friction]


# --- Cosmetics (all peers) -------------------------------------------------------------

func on_net_event(event: String, args: Array) -> void:
	var fxroot := get_parent()
	var at := global_position
	match event:
		"break":
			match kind:
				"suitcase":
					for c: Color in Looks.CLOTHES.slice(0, 4):
						Fx.burst(fxroot, at, c, 6, 4.5, 0.12, Vector3(0, -6, 0), 1.6)
					Fx.popup(fxroot, at, "POOF!", Color(1, 0.8, 0.9))
				"laptop":
					Fx.burst(fxroot, at, Color(1, 0.9, 0.3), 30, 5.0, 0.03, Vector3(0, -9.8, 0), 0.8, Vector3.UP, 180.0, 4.0)
					Fx.popup(fxroot, at, "BZZZT!", Color(0.5, 0.8, 1))
				"can":
					Fx.burst(fxroot, at, Color(0.8, 0.6, 0.3, 0.8), 30, 4.0, 0.04, Vector3(0, -9.8, 0), 0.9)
					Fx.popup(fxroot, at, "PSSSHH!", Color(1, 1, 1))
			Fx.sound(fxroot, at, "crash")
		"bsod":
			Looks.show_bsod(parts)
			Fx.burst(fxroot, at, Color(0.6, 0.8, 1), 14, 3.0, 0.025, Vector3(0, -9.8, 0), 0.6, Vector3.UP, 60.0, 4.0)
			Fx.popup(fxroot, at, "BZZT", Color(0.5, 0.7, 1))
			Fx.sound(fxroot, at, "spark")
		"fizz":
			var s := Fx.stream(Color(0.85, 0.7, 0.4, 0.8), 0.035, 3.0, Vector3.DOWN, 20.0)
			s.position = Vector3(0, -0.06, 0)
			add_child(s)
			s.emitting = true
			Fx.popup(fxroot, at, "PSSSSHHHH!", Color(1, 1, 1))
			Fx.sound(fxroot, at, "fizz")
		"burst":
			_burst_crate(fxroot, at)
		"spray":
			var dir: Vector3 = args[0]
			var nozzle: Node3D = parts.get("nozzle", self)
			Fx.burst(fxroot, nozzle.global_position, Color(0.95, 0.97, 1, 0.75), 28, 9.0, 0.12,
				Vector3(0, 0.5, 0), 0.7, dir, 10.0)
			Fx.sound(fxroot, at, "spray", -6.0)
		"clang":
			Fx.burst(fxroot, at, Color(1, 0.85, 0.3), 12, 3.5, 0.025, Vector3(0, -9.8, 0), 0.5, Vector3.UP, 90.0, 4.0)
			Fx.popup(fxroot, at, "CLANG!", Color(1, 0.9, 0.4))
			Fx.sound(fxroot, at, "clang")
		"squeak":
			var sq: Node3D = parts.get("squash", self)
			var tw := sq.create_tween()
			tw.tween_property(sq, "scale", Vector3(1.25, 0.7, 1.25), 0.07)
			tw.tween_property(sq, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_ELASTIC)
			Fx.popup(fxroot, at, "SQUEAK!", Color(1, 0.95, 0.3))
			Fx.sound(fxroot, at, "squeak")
		"eat", "chomp":
			Fx.burst(fxroot, at, Color(0.95, 0.85, 0.5), 10, 2.0, 0.03, Vector3(0, -9.8, 0), 0.6)
			Fx.popup(fxroot, at, "CHOMP" if event == "eat" else "GLUG", Color(1, 1, 1), 48)
			Fx.sound(fxroot, at, "chomp")
		"peeled":
			state.peeled = true
			Looks.show_peel(parts)
		"tape":
			Fx.popup(fxroot, at, "RRRRIP!", Color(0.85, 0.87, 0.9))
			Fx.sound(fxroot, at, "rip")
		"horn":
			Fx.popup(fxroot, at, "!!!", Color(1, 0.3, 0.2), 80)
			Fx.sound(fxroot, at, "horn")
		"slip":
			Fx.popup(fxroot, at, "WHOOPS!", Color(1, 0.9, 0.2), 72)
			Fx.sound(fxroot, at, "squeak", -4.0)


## Lid flies off spinning, splinters everywhere, the crate stays open.
func _burst_crate(fxroot: Node, at: Vector3) -> void:
	remove_meta("action")
	state.searched = true
	var lid: Node3D = parts.lid
	var tw := lid.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lid, "position", lid.position + Vector3(randf_range(-0.6, 0.6), 1.4, randf_range(-0.6, 0.6)), 0.5)
	tw.tween_property(lid, "rotation", Vector3(randf_range(2, 5), randf_range(-3, 3), randf_range(-3, 3)), 0.5)
	tw.chain().tween_callback(Looks.show_open_crate.bind(parts))
	Fx.burst(fxroot, at + global_basis.y * 0.45, Looks.WOOD, 24, 5.0, 0.06, Vector3(0, -9.8, 0), 1.2)
	Fx.burst(fxroot, at + global_basis.y * 0.45, Color(0.97, 0.95, 0.85), 30, 3.0, 0.05, Vector3(0, -3, 0), 2.0)
	Fx.popup(fxroot, at + global_basis.y * 0.6, "!", Color(1, 0.9, 0.2), 96)
	Fx.sound(fxroot, at, "crash")
