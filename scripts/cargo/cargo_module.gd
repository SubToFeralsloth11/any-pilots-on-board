extends Node
## Cargo module: the cargo contracts' freight in the hold, and its trouble.
##
## setup() (all peers) registers the cargo kinds (CargoLooks.KINDS), the escaped "chicken" and
## "croc" creatures and the "strap" host action. populate() (host) waits for the Airline's
## "boarding" phase and then spawns every accepted cargo contract's pieces in the hold (two
## columns either side of the clear centre walkway, away from the ramp lever). The host also
## keeps a fire-point list for the pieces, runs explosions, and builds cargo_report() for the
## payout. Per-piece behaviour lives in cargo_piece.gd, chicken.gd and croc.gd.

const CargoPiece := preload("res://scripts/cargo/cargo_piece.gd")
const CargoLooks := preload("res://scripts/cargo/cargo_looks.gd")
const Chicken := preload("res://scripts/cargo/chicken.gd")
const Croc := preload("res://scripts/cargo/croc.gd")

const STRAP_REACH := 3.5
const COLUMN_X := 1.65          ## Piece centres sit at x = ±COLUMN_X (walkway |x| < 1.0 stays clear).
const SLOT_Z := [14.0, 15.25, 16.5, 17.75, 19.0, 20.25]
const RIGHT_SLOTS := 5          ## The last right-hand slot would block the ramp lever.
const FIRE_REFRESH := 0.25
const BLAST_RADIUS := 5.0
const BLAST_FIRE_TIME := 0.8    ## A blast counts as fire (for neighbouring cargo) this long.
const BLAST_DAMAGE := 0.12
const BLAST_WINDOW_REACH := 3.5
const BLAST_PLAYER_SPEED := 13.0
const CROC_OUT := ["CROCODILE LOOSE IN THE CARGO HOLD! Everybody stay calm and DON'T RUN. Or run. Run.",
	"Uh, crew? The 'live reptile' is no longer in its crate.", "Good news: the crocodile is awake. Bad news: same."]
const CHICKENS_OUT := ["The chickens have escaped! Repeat: THE CHICKENS HAVE ESCAPED!",
	"There are chickens in the hold. Loose ones. Please put the chickens back.", "BAWK. (That was the coop door.)"]

var world: World
var _spawned := false
var _units := {}                ## Host: contract id -> pieces spawned.
var _pieces := {}               ## Host: contract id -> Array[int] net ids.
var _fire_points: Array[Vector3] = []
var _fire_t := 0.0
var _blasts: Array = []         ## Host: [position, time] of recent explosions.
var _time := 0.0


func setup(w: World) -> void:
	world = w
	for kind: String in CargoLooks.KINDS:
		world.register_kind(kind, _make_piece.bind(kind))
	world.register_kind("chicken", _make_chicken)
	world.register_kind("croc", _make_croc)
	world.register_action("strap", _act_strap)
	set_physics_process(world.is_server())


func _make_piece(extra: Dictionary, kind: String) -> Node3D:
	var p := CargoPiece.new()
	p.setup(self, world, kind, extra)
	return p


func _make_chicken(extra: Dictionary) -> Node3D:
	var c := Chicken.new()
	c.setup(self, world, extra)
	return c


func _make_croc(extra: Dictionary) -> Node3D:
	var c := Croc.new()
	c.setup(self, world, extra)
	return c


# --- Round setup (host) -----------------------------------------------------------------------

func populate() -> void:
	var airline: Node = world.get("airline")
	if airline == null:
		return
	airline.phase_changed.connect(_on_phase)
	if String(airline.get("phase")) == "boarding":
		_on_phase("boarding")


func _on_phase(phase: String) -> void:
	if phase == "boarding" and not _spawned:
		spawn_contracts(world.airline.accepted("cargo"))


## Host: spawns `count` pieces per cargo contract into the hold slots (stacking on top of the
## first row once both columns are full).
func spawn_contracts(contracts: Array) -> void:
	_spawned = true
	var slots: Array[Vector3] = []
	for i in SLOT_Z.size():
		slots.append(Vector3(-COLUMN_X, 0.0, SLOT_Z[i]))
		if i < RIGHT_SLOTS:
			slots.append(Vector3(COLUMN_X, 0.0, SLOT_Z[i]))
	var floor_kind: Array[String] = []
	var n := 0
	for c: Dictionary in contracts:
		if String(c.get("type", "cargo")) != "cargo" or not CargoLooks.SPECS.has(String(c.get("kind", ""))):
			continue
		var kind := String(c.kind)
		var id := int(c.id)
		_units[id] = 0
		_pieces[id] = []
		for u in maxi(int(c.get("count", 1)), 1):
			var size: Vector3 = CargoLooks.SPECS[kind].size
			var slot: Vector3
			var y := size.y * 0.5 + 0.03
			if n < slots.size():
				slot = slots[n]
				floor_kind.append(kind)
			elif n < slots.size() * 2:
				slot = slots[n - slots.size()]
				y += (CargoLooks.SPECS[floor_kind[n - slots.size()]].size as Vector3).y + 0.02
			else:
				push_warning("Cargo hold full: contract %d piece %d not loaded" % [id, u])
				continue
			n += 1
			var yaw := (PI / 2 if slot.x < 0.0 else -PI / 2) + randf_range(-0.06, 0.06)
			var extra := {"contract": id, "v": randi() % 1000}
			if kind == "chickens":
				extra.hens = randi_range(3, 5)
			var local := Vector3(slot.x, y, slot.z)
			var xf := Transform3D(world.plane.global_basis * Basis(Vector3.UP, yaw), world.plane.to_global(local))
			var obj := world.spawn_object(kind, xf, extra)
			if obj:
				_units[id] += 1
				(_pieces[id] as Array).append(World.net_id(obj))


## Host: per cargo contract id -> {units, delivered, condition}. A piece is delivered when it
## still exists, isn't destroyed and is inside the plane (croc back in or at least on board,
## some hens left); condition is the mean of the delivered pieces' conditions.
func cargo_report() -> Dictionary:
	var out := {}
	for cid: int in _units:
		var delivered := 0
		var total := 0.0
		for id: int in _pieces[cid]:
			var p := world.get_object(id) as CargoPiece
			if p == null:
				continue
			var c := p.delivered_condition()
			if c < 0.0:
				continue
			delivered += 1
			total += c
		out[cid] = {"units": int(_units[cid]), "delivered": delivered,
			"condition": total / delivered if delivered > 0 else 0.0}
	return out


# --- Strapping ---------------------------------------------------------------------------------

## [E] on a cargo piece: unstrap if strapped; strap if it rests in the hold; otherwise (or while
## crouching) pick it up like any other object.
func _act_strap(peer: int, args: Array) -> void:
	if args.is_empty():
		return
	var piece := world.get_object(int(args[0])) as CargoPiece
	var pl: Player = world.players.get(peer)
	if piece == null or pl == null or pl.global_position.distance_to(piece.global_position) > STRAP_REACH:
		return
	if bool(piece.state.strapped):
		piece.set_strapped(false)
	elif not pl.crouching and piece.can_strap():
		piece.set_strapped(true)
		world.notify(peer, "Strapped down. It won't slide around now.")
	else:
		# Same path as the core "grab" request ([E] on a plain grabbable).
		world._handle(peer, "grab", args)


# --- Host hooks used by the pieces -------------------------------------------------------------

func _physics_process(dt: float) -> void:
	_time += dt
	_fire_t -= dt
	if _fire_t > 0.0:
		return
	_fire_t = FIRE_REFRESH
	_fire_points.clear()
	for i in 2:
		if world.plane.engine_fire[i]:
			_fire_points.append(world.plane.engine_fire_point(i))
	for id in world.objects:
		var o: Node3D = world.objects[id]
		if o.get_meta("kind", "") == "flare":
			_fire_points.append(o.global_position)
	while not _blasts.is_empty() and _time - float(_blasts[0][1]) > BLAST_FIRE_TIME:
		_blasts.pop_front()
	for b: Array in _blasts:
		_fire_points.append(b[0])


## Is there fire (burning engine, flare, fresh explosion) within `reach` of a global point?
func near_fire(at: Vector3, reach: float) -> bool:
	for p in _fire_points:
		if p.distance_to(at) <= reach:
			return true
	return false


## Current turbulence felt in the cabin (|extra g|), only while flying.
func turbulence() -> float:
	if world.flight.phase != FlightModel.Phase.FLYING:
		return 0.0
	return absf(world.flight.bump)


## Host: blows up an explosive piece: blast impulse on everything nearby (passengers ragdoll,
## players get knocked back, other cargo reacts in on_blast), hull damage and broken windows.
func explode(piece: CargoPiece) -> void:
	if piece == null or not is_instance_valid(piece) or piece.destroyed:
		return
	piece.destroyed = true
	piece.state.condition = 0.0
	var at := piece.global_position
	var id := World.net_id(piece)
	var plane := world.plane
	var up := plane.global_basis.y
	world.object_event(id, "boom")
	world.add_stat("things_broken")
	world.shake_all(0.9)
	_blasts.append([at, _time])
	_fire_points.append(at)
	var w := plane.window_near(at, BLAST_WINDOW_REACH)
	var hit: Vector3
	if w >= 0:
		hit = plane.to_global(plane.windows[w].pos)
	else:
		var local := plane.to_local(at)
		var side := 1.0 if local.x >= 0.0 else -1.0
		hit = plane.to_global(Vector3(side * (Airliner.HALF_W + 0.1), clampf(local.y + 0.5, 0.4, Airliner.CEIL - 0.3), local.z))
	world.damage_plane_at(hit, BLAST_DAMAGE)
	for oid in world.objects.keys():
		var obj: Node3D = world.objects.get(oid)
		if obj == null or obj == piece:
			continue
		var d := obj.global_position.distance_to(at)
		if d > BLAST_RADIUS:
			continue
		var s := 1.0 - d / BLAST_RADIUS
		var dir := (obj.global_position - at).normalized()
		if obj.has_method("on_blast"):
			obj.call("on_blast", s, at)
		elif obj.is_in_group("npc") and obj.has_method("ragdoll"):
			obj.call("ragdoll", (dir * 140.0 + up * 90.0) * s)
		elif obj is RigidBody3D and not (obj as RigidBody3D).freeze:
			var rb := obj as RigidBody3D
			rb.apply_central_impulse((dir + up * 0.5) * rb.mass * minf(16.0 * s / sqrt(maxf(rb.mass, 1.0) / 4.0), 14.0))
	for peer in world.players:
		var pl: Player = world.players[peer]
		var d := pl.global_position.distance_to(at)
		if d < BLAST_RADIUS:
			var s := 1.0 - d / BLAST_RADIUS
			world.push_player(peer, ((pl.global_position - at).normalized() * BLAST_PLAYER_SPEED + up * 6.0) * s)
	world.say("", ["KA-BOOM! That was the explosive cargo.", "Cargo hold status: on fire, briefly. Barrels: gone.",
		"Well, that's one less contract to worry about."].pick_random(), 3.0)
	world.despawn_object(id)


## Host: chain reactions go off a moment after the blast that triggered them.
func explode_later(piece: CargoPiece, delay: float) -> void:
	get_tree().create_timer(delay, false, true).timeout.connect(func() -> void:
		if is_instance_valid(piece):
			explode(piece))


## Host: porcelain/wood shards (Props "debris" kind, they fade on their own).
func spawn_shards(at: Vector3, vel: Vector3, colors: Array) -> void:
	for c: Color in colors:
		var size := Vector3(randf_range(0.07, 0.14), 0.03, randf_range(0.06, 0.12))
		var rot := Basis.from_euler(Vector3(randf(), randf(), randf()) * TAU)
		var o := world.spawn_object("debris", Transform3D(rot, at + Vector3(randf_range(-0.2, 0.2), 0.2, randf_range(-0.2, 0.2))),
			{"color": c, "size": size, "shape": "shard"}) as RigidBody3D
		if o:
			o.linear_velocity = vel * 0.3 + Vector3(randf_range(-3, 3), randf_range(1.5, 4.0), randf_range(-3, 3))
			o.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))


## Host: the crocodile leaps out of its burst crate.
func release_croc(crate: CargoPiece) -> void:
	var up := world.plane.global_basis.y
	var xf := Transform3D(world.plane.global_basis * Basis(Vector3.UP, randf() * TAU), crate.global_position + up * 0.95)
	var croc := world.spawn_object("croc", xf, {"crate": World.net_id(crate), "contract": crate.get_meta("contract")}) as RigidBody3D
	if croc == null:
		return
	croc.linear_velocity = up * 3.0 + world.plane.global_basis.x * randf_range(-1.5, 1.5)
	crate.state.croc = World.net_id(croc)
	world.shake_all(0.3)
	world.say("ATTENDANT", CROC_OUT.pick_random(), 4.0)


## Host: drops the crocodile back into its crate.
func return_croc(croc: Node3D) -> bool:
	var crate := world.get_object(int(croc.get("crate_id"))) as CargoPiece
	if crate == null or crate.destroyed:
		return false
	var id := World.net_id(croc)
	world.object_event(id, "home")
	world.despawn_object(id)
	crate.croc_returned()
	world.say("ATTENDANT", "Crocodile back in its crate. Somebody sit on the lid.", 3.0)
	return true


## Host: `n` hens burst out of a coop and scatter.
func release_hens(coop: CargoPiece, n: int) -> void:
	var plane := world.plane
	var up := plane.global_basis.y
	for i in n:
		var a := randf() * TAU
		var out := plane.global_basis.x * cos(a) + plane.global_basis.z * sin(a)
		var xf := Transform3D(plane.global_basis * Basis(Vector3.UP, a), coop.global_position + up * 0.55 + out * 0.2)
		var hen := world.spawn_object("chicken", xf, {"coop": World.net_id(coop), "contract": coop.get_meta("contract"),
			"brown": i % 3 == 2}) as RigidBody3D
		if hen:
			hen.linear_velocity = out * randf_range(1.5, 3.5) + up * randf_range(2.5, 4.5)
			(coop.state.loose as Array).append(World.net_id(hen))
	world.say("ATTENDANT", CHICKENS_OUT.pick_random(), 3.5)


## Host: a hen dropped back into its coop.
func return_chicken(hen: Node3D) -> bool:
	var coop := world.get_object(int(hen.get("coop_id"))) as CargoPiece
	if coop == null or coop.destroyed:
		return false
	var id := World.net_id(hen)
	world.object_event(id, "home")
	world.despawn_object(id)
	coop.hen_returned(id)
	return true


## Host (every physics frame of a mystery "gravity" effect): bodies within `radius` fall up;
## players inside get a floaty shove every `tick`.
func invert_gravity_around(source: Node3D, radius: float, tick: bool) -> void:
	var felt := world.flight.felt_accel
	var at := source.global_position
	for oid in world.objects:
		var rb := world.objects[oid] as RigidBody3D
		if rb == null or rb.freeze or rb.global_position.distance_to(at) > radius:
			continue
		rb.sleeping = false
		rb.apply_central_force(-felt * rb.mass * 2.0)
	if tick:
		var up := world.plane.global_basis.y
		for peer in world.players:
			var pl: Player = world.players[peer]
			if pl.global_position.distance_to(at) < radius:
				world.push_player(peer, up * 3.5)


## Host: small random kicks to loose bodies near a humming mystery crate.
func jiggle_around(at: Vector3, radius: float) -> void:
	for oid in world.objects:
		var rb := world.objects[oid] as RigidBody3D
		if rb == null or rb.freeze or rb.global_position.distance_to(at) > radius:
			continue
		rb.sleeping = false
		rb.apply_central_impulse(Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)) * rb.mass * 1.2)
