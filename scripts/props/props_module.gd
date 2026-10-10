extends Node
## Loose objects, cargo crates and items.
##
## setup() (all peers) registers a factory for every kind in Looks.SPECS and the "search" host
## action. populate() (host) scatters ~44 pieces of cabin clutter, a drinks cart and 10 cargo
## crates. The module also keeps debris under a cap and estimates player velocities (host) for
## crate pushing and banana-peel slips. Per-object behaviour lives in prop.gd.

const Prop := preload("res://scripts/props/prop.gd")
const Looks := preload("res://scripts/props/prop_looks.gd")
const Items := preload("res://scripts/props/items.gd")

const MAX_DEBRIS := 40
const SEARCH_REACH := 3.2
## Seats players get on joining (World uses (n * 9 + 3) % 32); keep them clear of clutter.
const PLAYER_SEATS := [3, 12, 21, 30, 7, 16, 25, 2]

var world: World
var _debris: Array[int] = []
var _player_pos := {}      ## Host: peer -> last position.
var _player_vel := {}      ## Host: peer -> smoothed velocity.


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
		var pos: Vector3 = (world.players[peer] as Player).global_position
		var last: Vector3 = _player_pos.get(peer, pos)
		var v := (pos - last) / dt
		_player_vel[peer] = (_player_vel.get(peer, Vector3.ZERO) as Vector3).lerp(v, 0.3)
		_player_pos[peer] = pos
	for peer in _player_pos.keys():
		if not world.players.has(peer):
			_player_pos.erase(peer)
			_player_vel.erase(peer)


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
	_populate_cargo()


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
	_spawn("suitcase", Vector3(1.2, 0.13, zf), 0.1)
	_spawn("suitcase", Vector3(1.2, 0.38, zf), -0.2)
	_spawn("bag", Vector3(1.2, 0.66, zf), 0.3)
	_spawn("suitcase", Vector3(-1.15, 0.13, zf), PI / 2)
	_spawn("bag", Vector3(-1.2, 0.16, zb), 0.2)
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
		_spawn("can", Vector3(1.1 + (i % 2) * 0.11, top + 0.075, gz - 0.15 + (i >> 1) * 0.13), 0.0)
	_spawn("banana", Vector3(1.2, top + 0.05, gz + 0.16), 0.0)
	_spawn("snack", Vector3(1.45, top + 0.13, gz - 0.1), 0.0)
	_spawn("snack", Vector3(1.62, top + 0.13, gz - 0.1), 0.15)
	_spawn("duct_tape", Vector3(1.72, top + 0.035, gz + 0.12), 0.0)
	_spawn("laptop", Vector3(-1.68, top + 0.055, gz), 0.0)
	_spawn("megaphone", Vector3(-1.22, top + 0.14, gz), 0.0)
	_spawn("extinguisher", Vector3(-1.6, 0.26, gz + 0.55), 0.0)
	# Loose odds and ends near the exits.
	_spawn("wrench", Vector3(0.9, 0.03, zb + 0.3), 0.8)
	_spawn("can", Vector3(-0.3, 0.07, zf + 0.4), 0.0)
	_spawn("can", Vector3(0.4, 0.07, zb - 0.2), 0.0)


func _populate_cargo() -> void:
	var lo := Airliner.CARGO_MIN
	var hi := Airliner.CARGO_MAX
	var cols := [lo.x + 0.5, hi.x - 0.5]
	var zs: Array[float] = []
	for i in 5:
		zs.append(lo.z + 0.8 + i * minf(1.4, (hi.z - lo.z - 1.6) / 4.0))
	# [column, z slot, level]
	var layout := [[0, 0, 0], [0, 1, 0], [0, 2, 0], [0, 3, 0], [0, 1, 1], [0, 2, 1],
		[1, 0, 0], [1, 1, 0], [1, 3, 0], [1, 0, 1]]
	var labels: Array = Looks.CRATE_LABELS.duplicate()
	labels.shuffle()
	for i in layout.size():
		var c: Array = layout[i]
		var pos := Vector3(cols[c[0]] + randf_range(-0.05, 0.05), 0.45 + int(c[2]) * 0.87, zs[c[1]])
		_spawn("crate", pos, randf_range(-0.12, 0.12),
			{"label": labels[i % labels.size()], "tint": randf_range(0.0, 0.22)})
