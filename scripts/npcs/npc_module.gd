extends Node
## Contract passengers.
##
## Registers the `passenger` kind. On the host, when the Airline enters "boarding", every
## accepted passenger contract steps aboard at the top of the rear ramp (one every BOARD_GAP s)
## and walks through the hold and lounge to an assigned seat (families sit together). Each
## passenger's wants and mood live in a PassengerMind (see npc.gd). The module also turns scary
## flying, weather jolts and air pockets into panic or ragdolls (unless the seatbelt sign keeps
## them buckled), and reports who arrived for the payout.

const Npc := preload("res://scripts/npcs/npc.gd")
const BOARD_GAP := 0.9            ## Seconds between passengers stepping aboard.
## Plane-local floor point at the top of the rear ramp where passengers step aboard.
const BOARD_AT := Vector3(0.0, 0.0, Airliner.TAIL_Z - 1.6)
const SPAWN_CLEAR := 0.7          ## Nobody within this of the boarding point before the next one.
const BIN_DROPS := ["bag", "suitcase", "pillow"]

var world: World
var people: Array[Node] = []      ## Every passenger on this peer.

var _queue: Array[Dictionary] = []   ## Host: spawn extras still waiting to board.
var _board_t := 0.0
var _boarding := false
var _side := 1.0
var _report := {}                    ## Host: contract id -> {boarded, lost}.
var _chat_t := 12.0


func setup(w: World) -> void:
	world = w
	world.register_kind("passenger", _factory)
	world.plane_changed.connect(_on_plane_changed)


func _factory(extra: Dictionary) -> Node3D:
	var n := Npc.new(world, "passenger", extra)
	people.append(n)
	n.tree_exited.connect(func() -> void: people.erase(n))
	return n


## Host, once per round (after every module's setup).
func populate() -> void:
	world.airline.phase_changed.connect(_on_phase)
	if world.weather != null:
		world.weather.jolt.connect(_on_jolt)
		world.weather.air_pocket.connect(_on_air_pocket)
	if world.airline.phase == "boarding":
		_on_phase("boarding")


func _on_phase(phase: String) -> void:
	if phase == "boarding" and not _boarding and _report.is_empty():
		_start_boarding()


## Host. Queues every accepted passenger with a seat, a look and their contract's temperament.
func _start_boarding() -> void:
	var order := _seat_order()
	var names: Array = Npc.NAMES.duplicate()
	names.shuffle()
	var n := 0
	for c: Dictionary in world.airline.accepted("passengers"):
		_report[int(c.id)] = {"boarded": 0, "lost": 0}
		for k in int(c.count):
			if n >= order.size():
				world.say("DISPATCH", "We're out of seats. The rest of '%s' will have to wait for the next flight." % c.name, 3.5)
				break
			var e := _look(String(c.kind), k)
			e["name"] = ("VIP " if c.kind == "vip" else "") + String(names[n % names.size()])
			e["seat"] = order[n]
			e["kind"] = c.kind
			e["contract"] = int(c.id)
			e["state"] = Npc.State.WALK
			_queue.append(e)
			n += 1
	_boarding = true
	_board_t = 0.0


## Host. Free passenger seats (not taken by a seated player), starting at a random row so
## contracts spread around the cabin; consecutive entries are side by side, so groups sit together.
func _seat_order() -> Array[Vector3]:
	var seats: Array[Vector3] = world.plane.seats
	var start := (randi() % Airliner.ROW_Z.size()) * Airliner.SEAT_X.size()
	var out: Array[Vector3] = []
	for i in seats.size():
		var s: Vector3 = seats[(start + i) % seats.size()]
		if not _player_in(s):
			out.append(s)
	return out


## Appearance shared by every peer through the spawn extra; the contract kind dresses it.
func _look(kind: String, index: int) -> Dictionary:
	var accent: Color = Npc.SHIRTS.pick_random()
	var e := {"shirt": Npc.SHIRTS.pick_random(), "skin": Npc.SKIN.pick_random(), "hair": Npc.HAIR.pick_random(),
		"pants": Color(randf_range(0.1, 0.4), randf_range(0.1, 0.3), randf_range(0.15, 0.45)),
		"shoes": [Color(0.12, 0.1, 0.1), Color(0.95, 0.95, 0.95), Color(0.5, 0.3, 0.15), Color(0.9, 0.2, 0.3)].pick_random(),
		"socks": [Color(0.95, 0.95, 0.95), Color(0.15, 0.15, 0.15), Color(0.9, 0.3, 0.3), Color(0.3, 0.8, 0.4)].pick_random(),
		"style": randi() % Npc.NpcLook.HAIR_STYLES, "outfit": randi() % Npc.NpcLook.OUTFITS,
		"size": randf_range(0.88, 1.12), "width": randf_range(0.9, 1.35),
		"bravery": randf_range(0.6, 1.4), "brow": randf_range(-0.3, 0.35), "nose": randf_range(0.8, 1.6),
		"hat": randi() % 5 if randf() < 0.4 else 0, "hat_color": accent,
		"glasses": [0, 0, 0, 1, 1, 2].pick_random(),
		"glasses_color": [Color(0.1, 0.1, 0.1), Color(0.85, 0.2, 0.25), Color(0.9, 0.75, 0.3)].pick_random(),
		"stache": randf() < 0.2, "beard": randf() < 0.15, "tie": randf() < 0.25, "tie_color": accent.darkened(0.2),
		"bag": randf() < 0.3, "bag_color": accent.darkened(0.1), "phones": randf() < 0.12,
		"necklace": randf() < 0.2, "earrings": randf() < 0.25, "pillow": randf() < 0.15,
		"backpack": randf() < 0.12, "mask": randf() < 0.1, "watch": randf() < 0.4, "short_sleeves": randf() < 0.4}
	match kind:
		"business":
			e["outfit"] = Npc.NpcLook.Outfit.SHIRT
			e["tie"] = true
			e["short_sleeves"] = false
			e["shirt"] = [Color(0.92, 0.94, 0.98), Color(0.75, 0.82, 0.95)].pick_random()
			e["pants"] = Color(0.12, 0.14, 0.2)
			e["glasses"] = [0, 1].pick_random()
		"party":
			e["outfit"] = [Npc.NpcLook.Outfit.HAWAIIAN, Npc.NpcLook.Outfit.HAWAIIAN, Npc.NpcLook.Outfit.SHIRT].pick_random()
			e["glasses"] = 2
		"nervous":
			e["outfit"] = [Npc.NpcLook.Outfit.SWEATER, Npc.NpcLook.Outfit.HOODIE].pick_random()
			e["mask"] = randf() < 0.4
			e["bravery"] = randf_range(0.4, 0.7)
		"tourists":
			e["outfit"] = [Npc.NpcLook.Outfit.HAWAIIAN, Npc.NpcLook.Outfit.SHIRT, Npc.NpcLook.Outfit.DRESS].pick_random()
			e["hat"] = 1 + randi() % 4 if randf() < 0.6 else 0
		"vip":
			e["outfit"] = [Npc.NpcLook.Outfit.SHIRT, Npc.NpcLook.Outfit.DRESS].pick_random()
			e["necklace"] = true
			e["watch"] = true
			e["glasses"] = 2
			e["shirt"] = Color(0.12, 0.1, 0.12)
		"family":
			if index % 3 == 2:
				e["child"] = true
				e["size"] = 0.62
				e["width"] = 0.95
				e["tie"] = false
				e["beard"] = false
				e["stache"] = false
				e["glasses"] = 0
	return e


# --- Queries (all peers) ------------------------------------------------------------------

## True when a passenger is seated in, or assigned to, the plane-local seat point.
func is_seat_taken(seat_local: Vector3) -> bool:
	for n: Npc in people:
		if n.seat.distance_to(seat_local) < 0.1:
			return true
	return false


## Nearest seat to `local` that no passenger is assigned to and no player sits in, within
## `reach` metres; Vector3.INF when there is none.
func free_seat_near(local: Vector3, reach := INF) -> Vector3:
	var best := Vector3.INF
	var best_d := reach
	for s: Vector3 in world.plane.seats:
		var d := Vector2(s.x - local.x, s.z - local.z).length()
		if d < best_d and not is_seat_taken(s) and not _player_in(s):
			best_d = d
			best = s
	return best


func _player_in(seat_local: Vector3) -> bool:
	for id in world.players:
		var p: Player = world.players[id]
		if p.seated and p.seat_local.distance_to(seat_local) < 0.1:
			return true
	return false


## Host. Per contract: {boarded, delivered (still aboard), lost, satisfaction (avg of those aboard)}.
func passenger_report() -> Dictionary:
	var out := {}
	for id: int in _report:
		var r: Dictionary = _report[id]
		var aboard := 0
		var mood := 0.0
		for n: Npc in people:
			if n.contract == id and not world.plane.is_outside(n.global_position):
				aboard += 1
				mood += n.mind.satisfaction if n.mind else 0.5
		out[id] = {"boarded": int(r.boarded), "delivered": aboard, "lost": int(r.lost),
			"satisfaction": mood / aboard if aboard > 0 else 0.0}
	return out


## Host. A passenger left the plane for good (World calls on_lost before despawning them).
func note_lost(n: Npc) -> void:
	if _report.has(n.contract):
		_report[n.contract].lost += 1


# --- Host simulation ----------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if not world.is_server():
		return
	if _boarding:
		_board(dt)
	if people.is_empty():
		return
	var f := world.flight
	if f.phase == FlightModel.Phase.FLYING:
		var fear := maxf(absf(f.roll) - 0.35, 0.0) * 0.6 + maxf(absf(f.pitch) - 0.22, 0.0) * 0.9 \
			+ maxf(0.5 - f.felt_gravity(), 0.0)
		if fear > 0.0:
			panic_all(fear * dt)
	_chat_t -= dt
	if _chat_t <= 0.0:
		_chat_t = randf_range(14.0, 26.0)
		var calm: Array = people.filter(func(n: Node) -> bool:
			return (n as Npc).state == Npc.State.SEATED and not (n as Npc).scared and (n as Npc).mind.need == "")
		if not calm.is_empty():
			(calm.pick_random() as Npc).say_line(Npc.CALM.pick_random())


func _board(dt: float) -> void:
	_board_t -= dt
	if not _queue.is_empty():
		if _board_t > 0.0 or not _spawn_clear():
			return
		_board_t = BOARD_GAP
		var e: Dictionary = _queue.pop_front()
		_side = -_side
		var at := BOARD_AT + Vector3(_side * 0.35, Npc.FEET * float(e.size), 0)
		world.spawn_object("passenger", world.plane.global_transform * Transform3D(Basis.IDENTITY, at), e)
		_report[int(e.contract)].boarded += 1
		return
	for n: Npc in people:
		if n.state != Npc.State.SEATED:
			return
	_boarding = false
	if world.airline.phase == "boarding" and world.airline.has_method("end_boarding"):
		world.say("CREW", "All passengers seated. Closing the ramp!", 3.0)
		world.airline.end_boarding()


func _spawn_clear() -> bool:
	var at := world.plane.to_global(BOARD_AT)
	for n: Npc in people:
		if n.global_position.distance_to(at) < SPAWN_CLEAR + 0.6:
			return false
	return true


## Host. Raises everyone's panic.
func panic_all(amount: float) -> void:
	for n: Npc in people:
		n.add_panic(amount * randf_range(0.7, 1.3))


## Host. Panic spreads to the people around `source` (rowdy singing, screaming).
func panic_near(source: Npc, amount: float, reach := 3.0) -> void:
	for n: Npc in people:
		if n != source and n.global_position.distance_to(source.global_position) < reach:
			n.add_panic(amount)


## Host. A rowdy passenger yanks open the overhead bin above them and luggage rains down.
func open_bin(n: Npc) -> void:
	var local := world.plane.to_local(n.global_position)
	var side := -1.0 if local.x < 0.0 else 1.0
	for i in randi_range(1, 2):
		var at := Vector3(side * randf_range(1.5, 2.1), 2.5, local.z + randf_range(-0.3, 0.3))
		var xf := world.plane.global_transform * Transform3D(Basis(Vector3.UP, randf() * TAU), at)
		var o := world.spawn_object(BIN_DROPS.pick_random(), xf, {}) as RigidBody3D
		if o:
			o.linear_velocity = world.plane.global_basis * Vector3(-side * 1.5, -1.0, 0)
	world.shake_all(0.1)


## Host. Weather jolt: moods drop; with the seatbelt sign off, unbuckled people go flying.
func _on_jolt(strength: float) -> void:
	var up := world.plane.global_basis.y
	for n: Npc in people:
		n.mind.jolt(strength)
		var loose := n.state == Npc.State.STAND or n.state == Npc.State.WALK
		var unbelted := n.state == Npc.State.SEATED and not world.seatbelt_sign
		if (loose and randf() < 0.6 * strength) or (unbelted and strength > 0.6 and randf() < 0.3 * strength):
			n.ragdoll((up * randf_range(2.0, 3.5) + world.plane.global_basis.x * randf_range(-1.5, 1.5)) * n.mass * strength)


## Host. Air pocket: anyone not belted in floats up out of their seat (the felt gravity does the rest).
func _on_air_pocket(active: bool) -> void:
	if not active:
		return
	var up := world.plane.global_basis.y
	for n: Npc in people:
		n.mind.pocket()
		if n.state != Npc.State.SEATED or not world.seatbelt_sign:
			n.ragdoll(up * n.mass * 2.0, 5.0)


func _on_plane_changed(key: String, value: bool) -> void:
	if not world.is_server() or not value:
		return
	if key.begins_with("window:"):
		panic_all(0.35)
	elif key.begins_with("fire:"):
		panic_all(0.3)
	elif key == "door:left" or key == "door:right" or (key == "ramp" and world.airline.phase == "flight"):
		panic_all(0.25)
