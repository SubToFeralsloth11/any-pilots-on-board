extends Node
## Loose objects, cargo crates and items.
##
## setup() (all peers) registers a factory for every kind in Looks.SPECS and the "search" host
## action. populate() (host) scatters ~44 pieces of cabin clutter and a drinks cart (the cargo
## hold is filled by the Cargo module). The module also keeps debris under a cap, estimates
## player velocities (host) for banana-peel slips, and shoves loose props out of a walking
## player's way. Per-object behaviour lives in prop.gd.

const Prop := preload("res://scripts/props/prop.gd")
const Looks := preload("res://scripts/props/prop_looks.gd")
const Items := preload("res://scripts/props/items.gd")

const MAX_DEBRIS := 40
const SEARCH_REACH := 3.2
## Seats players get on joining (World uses (n * 9 + 3) % 32); keep them clear of clutter.
const PLAYER_SEATS := [3, 12, 21, 30, 7, 16, 25, 2]
## Shoving: players walk through props (they are not in the player's mask). Anything loose that
## overlaps a moving player's capsule is nudged along at up to the player's speed, capped by
## mass (Prop.PUSH_*): a can skitters off, a crate scoots, nothing launches.
const SHOVE_RADIUS := 0.38
const SHOVE_HEIGHT := 1.6
const SHOVE_MIN_SPEED := 0.3
const SHOVE_FOLLOW := 1.1       ## Prop speed relative to the player's approach speed.
const SHOVE_MAX_HITS := 8

var world: World
var _debris: Array[int] = []
var _player_pos := {}      ## Host: peer -> last position.
var _player_vel := {}      ## Host: peer -> smoothed velocity.
var _shove_query: PhysicsShapeQueryParameters3D


func setup(w: World) -> void:
	world = w
	for kind: String in Looks.SPECS:
		world.register_kind(kind, _make.bind(kind))
	world.register_action("search", _act_search)
	set_physics_process(world.is_server())


func _make(extra: Dictionary, kind: String) -> Node3D:
	var p := Prop.new()
	p.setup(world, kind, extra, spawn_debris, player_velocity)
	return p


## Host: estimated velocity of a player (remote players only stream positions).
func player_velocity(peer: int) -> Vector3:
	return _player_vel.get(peer, Vector3.ZERO)


func _physics_process(dt: float) -> void:
	for peer in world.players:
		var pl := world.players[peer] as Player
		var pos: Vector3 = pl.global_position
		var last: Vector3 = _player_pos.get(peer, pos)
		var v := (pos - last) / dt
		_player_vel[peer] = (_player_vel.get(peer, Vector3.ZERO) as Vector3).lerp(v, 0.3)
		_player_pos[peer] = pos
		if not pl.seated:
			_shove_from(pl, _player_vel[peer])
	for peer in _player_pos.keys():
		if not world.players.has(peer):
			_player_pos.erase(peer)
			_player_vel.erase(peer)


## Host: nudges loose props overlapping a moving player's capsule (wakes sleeping ones too).
func _shove_from(pl: Player, vel: Vector3) -> void:
	var up := world.plane.global_basis.y
	var flat := vel - up * vel.dot(up)
	if flat.length() < SHOVE_MIN_SPEED:
		return
	if _shove_query == null:
		var cap := CapsuleShape3D.new()
		cap.radius = SHOVE_RADIUS
		cap.height = SHOVE_HEIGHT
		_shove_query = PhysicsShapeQueryParameters3D.new()
		_shove_query.shape = cap
		_shove_query.collision_mask = Layers.PROP
	_shove_query.transform = Transform3D(world.plane.global_basis, pl.global_position + up * (SHOVE_HEIGHT * 0.5 + 0.05))
	var held: Array = world.holders.values()
	for hit in pl.get_world_3d().direct_space_state.intersect_shape(_shove_query, SHOVE_MAX_HITS):
		var body := hit.collider as RigidBody3D
		if body == null or body.freeze or held.has(World.net_id(body)):
			continue
		if body.has_method("note_shoved"):
			body.note_shoved()
		var d := body.global_position - pl.global_position
		d -= up * d.dot(up)
		var n := d.normalized() if d.length() > 0.05 else flat.normalized()
		var along := flat.dot(n)
		if along <= SHOVE_MIN_SPEED:
			continue
		var cap_speed := clampf(Prop.PUSH_SPEED / sqrt(body.mass), Prop.PUSH_MIN, Prop.PUSH_MAX)
		var want := minf(along * SHOVE_FOLLOW, cap_speed)
		var cur := body.linear_velocity.dot(n)
		if cur < want:
			body.sleeping = false
			body.apply_central_impulse(n * (want - cur) * body.mass)


## Host: a broken prop bursts into 3-5 small pieces that fade after a while.
func spawn_debris(kind: String, extra: Dictionary, at: Vector3, vel: Vector3) -> void:
	var alive: Array[int] = []
	for i in _debris:
		if world.objects.has(i):
			alive.append(i)
	_debris = alive
	for d in Looks.debris_for(kind, extra):
		var rot := Basis.from_euler(Vector3(randf(), randf(), randf()) * TAU)
		var offset := Vector3(randf_range(-0.12, 0.12), randf_range(0.0, 0.1), randf_range(-0.12, 0.12))
		var o := world.spawn_object("debris", Transform3D(rot, at + offset), d) as RigidBody3D
		if o == null:
			continue
		o.linear_velocity = vel * 0.3 + Vector3(randf_range(-2.5, 2.5), randf_range(1.0, 3.5), randf_range(-2.5, 2.5))
		o.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
		_debris.append(World.net_id(o))
	while _debris.size() > MAX_DEBRIS:
		world.despawn_object(_debris.pop_front())


# --- Crates ------------------------------------------------------------------------------

func _act_search(peer: int, args: Array) -> void:
	if args.is_empty():
		return
	var crate := world.get_object(int(args[0])) as Prop
	var pl: Player = world.players.get(peer)
	if crate == null or pl == null:
		return
	if pl.global_position.distance_to(crate.global_position) > SEARCH_REACH or not crate.open_crate():
		return
	world.add_stat("things_broken")
	var item := Items.roll()
	var up := world.plane.global_basis.y
	var xf := Transform3D(world.plane.global_basis, crate.global_position + up * 0.75)
	var obj := world.spawn_object(item, xf, {}) as RigidBody3D
	if obj:
		var toward := pl.global_position - crate.global_position
		toward -= up * toward.dot(up)
		obj.linear_velocity = up * 3.2 + toward.normalized() * 1.2
		obj.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	world.notify(peer, Items.FOUND[item].pick_random())


# --- Round setup (host) ------------------------------------------------------------------

func populate() -> void:
	_populate_cabin()


func _spawn(kind: String, local: Vector3, yaw := 0.0, extra := {}) -> RigidBody3D:
	var plane := world.plane
	var xf := Transform3D(plane.global_basis * Basis(Vector3.UP, yaw), plane.to_global(local))
	return world.spawn_object(kind, xf, extra) as RigidBody3D


func _populate_cabin() -> void:
	var rows: Array = Airliner.ROW_Z
	var cols: Array = Airliner.SEAT_X
	# Legroom slots: the floor in front of every seat except the front row (galley there).
	var slots: Array[Vector3] = []
	for r in range(1, rows.size()):
		for x: float in cols:
			slots.append(Vector3(x, 0.0, float(rows[r]) - 0.72))
	slots.shuffle()
	for i in 9:
		var kind := "suitcase" if i % 3 != 2 else "bag"
		_spawn(kind, slots[i] + Vector3(0, 0.15, 0), PI / 2 + randf_range(-0.25, 0.25))
	# Stuff abandoned in the aisle (row gaps only).
	for i in 3:
		var r: float = rows[[1, 3, 6][i]]
		_spawn(["bag", "suitcase", "laptop"][i], Vector3(randf_range(-0.12, 0.12), 0.16, r - 0.75),
			randf_range(0, TAU))
	# A luggage pile by the over-wing exits (clear of the doors themselves).
	var gap_front: float = rows[4]
	var gap_back: float = rows[5]
	var zf := gap_front - 1.15
	var zb := gap_back - 0.85
	_spawn("suitcase", Vector3(1.8, 0.13, zf), 0.1)
	_spawn("suitcase", Vector3(1.8, 0.38, zf), -0.2)
	_spawn("bag", Vector3(1.8, 0.66, zf), 0.3)
	_spawn("suitcase", Vector3(-1.75, 0.13, zf), PI / 2)
	_spawn("bag", Vector3(-1.8, 0.16, zb), 0.2)
	# Seats: pillows, laptops, a can and the rubber chicken, avoiding player spawn seats.
	var seat_ids: Array[int] = []
	for i in world.plane.seats.size():
		if not PLAYER_SEATS.has(i):
			seat_ids.append(i)
	seat_ids.shuffle()
	var on_seats := ["pillow", "pillow", "pillow", "pillow", "pillow", "pillow", "laptop", "laptop",
		"can", "can", "rubber_chicken"]
	for i in on_seats.size():
		var seat: Vector3 = world.plane.seats[seat_ids[i]]
		_spawn(on_seats[i], seat + Vector3(0, 0.14, 0), randf_range(0, TAU))
	# Galley: cart in the aisle, drinks and goodies on the counters (top at y 1.0, 0.5 deep),
	# extinguisher on the floor beside them.
	var gz := float(rows[0]) - 1.1
	_spawn("cart", Vector3(0, 0.48, gz + 0.3), 0.0)
	var top := 1.0
	for i in 4:
		_spawn("can", Vector3(1.7 + (i % 2) * 0.11, top + 0.075, gz - 0.15 + (i >> 1) * 0.13), 0.0)
	_spawn("banana", Vector3(1.8, top + 0.05, gz + 0.16), 0.0)
	_spawn("snack", Vector3(2.05, top + 0.13, gz - 0.1), 0.0)
	_spawn("snack", Vector3(2.22, top + 0.13, gz - 0.1), 0.15)
	_spawn("duct_tape", Vector3(2.32, top + 0.035, gz + 0.12), 0.0)
	_spawn("laptop", Vector3(-2.28, top + 0.055, gz), 0.0)
	_spawn("megaphone", Vector3(-1.82, top + 0.14, gz), 0.0)
	_spawn("extinguisher", Vector3(-2.2, 0.26, gz + 0.55), 0.0)
	# Loose odds and ends near the exits.
	_spawn("wrench", Vector3(0.9, 0.03, zb + 0.3), 0.8)
	_spawn("can", Vector3(-0.3, 0.07, zf + 0.4), 0.0)
	_spawn("can", Vector3(0.4, 0.07, zb - 0.2), 0.0)
