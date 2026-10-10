extends Node
## Passengers, crew and the captain.
##
## Registers the `passenger`, `attendant` and `captain` kinds. On the host it seats
## the passengers, turns scary flight moments into panic and lets someone chat now and then.

const Npc := preload("res://scripts/npcs/npc.gd")
const PASSENGERS := 12
const PLAYER_SEAT_SLOTS := 8      ## World._add_player uses seats[(n * 9 + 3) % size], n < 8.
const ATTENDANT_HOME := Vector3(1.25, 0.05, -9.4)

var world: World
var people: Array[Node] = []      ## Every NPC on this peer.
var attendant: Npc
var captain: Npc

var _chat_t := 12.0


func setup(w: World) -> void:
	world = w
	for role in ["passenger", "attendant", "captain"]:
		world.register_kind(role, _factory.bind(role))
	world.plane_changed.connect(_on_plane_changed)


func _factory(extra: Dictionary, role: String) -> Node3D:
	var n := Npc.new(world, role, extra)
	people.append(n)
	n.tree_exited.connect(func() -> void: people.erase(n))
	if role == "attendant":
		attendant = n
	elif role == "captain":
		captain = n
	return n


func populate() -> void:
	var plane := world.plane
	var reserved := {}
	for n in PLAYER_SEAT_SLOTS:
		reserved[(n * 9 + 3) % plane.seats.size()] = true
	var open_seats: Array[Vector3] = []
	for i in plane.seats.size():
		if not reserved.has(i):
			open_seats.append(plane.seats[i])
	open_seats.shuffle()
	var names: Array = Npc.NAMES.duplicate()
	names.shuffle()
	for i in mini(PASSENGERS, open_seats.size()):
		var e := _look()
		e["name"] = names[i % names.size()]
		e["seat"] = open_seats[i]
		e["state"] = Npc.State.SEATED
		_spawn("passenger", open_seats[i] + Vector3(0, Npc.SEAT_LIFT * float(e.size), 0), e)
	var a := _look()
	a["name"] = "Flight Attendant"
	a["size"] = 1.0
	a["width"] = 1.0
	a["bravery"] = 1.5
	a["home"] = ATTENDANT_HOME
	a["yaw"] = PI
	a["state"] = Npc.State.STAND
	a["stache"] = false
	var c := _look()
	c["name"] = "Captain"
	c["style"] = 0
	c["hair"] = Color(0.75, 0.75, 0.78)
	c["seat"] = Airliner.PILOT_SEAT
	c["state"] = Npc.State.SEATED
	for crew in [a, c]:
		for k in ["bag", "phones", "necklace", "tie", "pillow", "backpack", "mask", "short_sleeves", "beard"]:
			crew[k] = false
		crew["hat"] = 0
		crew["glasses"] = 0
	_spawn("attendant", ATTENDANT_HOME + Vector3(0, Npc.FEET, 0), a, PI)
	_spawn("captain", Airliner.PILOT_SEAT + Vector3(0, Npc.SEAT_LIFT * float(c.size), 0), c)


## Random appearance shared by every peer through the spawn extra.
func _look() -> Dictionary:
	var accent: Color = Npc.SHIRTS.pick_random()
	return {"shirt": Npc.SHIRTS.pick_random(), "skin": Npc.SKIN.pick_random(), "hair": Npc.HAIR.pick_random(),
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


func _spawn(kind: String, local: Vector3, extra: Dictionary, yaw := 0.0) -> void:
	var plane := world.plane
	world.spawn_object(kind, Transform3D(plane.global_basis * Basis(Vector3.UP, yaw), plane.to_global(local)), extra)


## Host. Raises everyone's panic.
func panic_all(amount: float) -> void:
	for n in people:
		(n as Npc).add_panic(amount * randf_range(0.7, 1.3))


## Host. The captain faints out of the pilot seat.
func captain_blackout() -> void:
	if is_instance_valid(captain):
		captain.knock_out()


## Host. The captain comes round long enough to say `line`. False if he is gone or awake.
func captain_wake(line: String) -> bool:
	if not is_instance_valid(captain) or captain.state != Npc.State.OUT:
		return false
	captain.wake_up(line)
	return true


## Host. Speech bubble over the attendant (if she is still aboard).
func attendant_say(line: String) -> void:
	if is_instance_valid(attendant):
		attendant.say_line(line)


func _physics_process(dt: float) -> void:
	if not world.is_server() or people.is_empty():
		return
	var f := world.flight
	if f.phase == FlightModel.Phase.FLYING:
		var fear := maxf(absf(f.roll) - 0.35, 0.0) * 0.6 + maxf(absf(f.pitch) - 0.22, 0.0) * 0.9 \
			+ maxf(0.5 - f.felt_gravity(), 0.0) + maxf(f.bump, 0.0) * 0.3
		if fear > 0.0:
			panic_all(fear * dt)
	_chat_t -= dt
	if _chat_t <= 0.0:
		_chat_t = randf_range(14.0, 26.0)
		var calm: Array = people.filter(func(n: Node) -> bool:
			return (n as Npc).role == "passenger" and (n as Npc).state == Npc.State.SEATED and not (n as Npc).scared)
		if not calm.is_empty():
			(calm.pick_random() as Npc).say_line(Npc.CALM.pick_random())


func _on_plane_changed(key: String, value: bool) -> void:
	if not world.is_server() or not value:
		return
	if key.begins_with("window:"):
		panic_all(0.35)
	elif key.begins_with("fire:"):
		panic_all(0.3)
	elif key == "ramp" or key == "door:left" or key == "door:right":
		panic_all(0.25)
