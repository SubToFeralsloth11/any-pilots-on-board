extends FunStation
## The SNAX-O-TRON 3000 vending machine. [E] buys a random item (free, the card reader is
## broken); the host spawns it in the tray and pops it out toward the buyer. A few rare slots
## hold silly things. At most MAX_ALIVE vended items exist at once.
## Local frame: the front faces +Z, the origin is on the floor.

const COOLDOWN_MS := 1500
const MAX_ALIVE := 10
## [kind, extra, weight, announcement]
const STOCK := [
	["snack", {}, 5, "a bag of snacks"],
	["can", {}, 5, "a soda (shaken, obviously)"],
	["banana", {}, 3, "a banana"],
	["rubber_chicken", {}, 2, "a RUBBER CHICKEN"],
	["dice", {}, 2, "a die"],
	["golf_ball", {}, 2, "a golf ball"],
	["dart", {"color": 2}, 2, "a dart"],
	["water_pistol", {}, 1, "a SUPER SOAKER"],
	["pillow_fight", {}, 1, "a fight pillow"],
]
const ROW_COLORS := [Color(1, 0.55, 0.1), Color(0.2, 0.45, 0.95), Color(0.9, 0.2, 0.2), Color(0.6, 0.25, 0.85),
	Color(0.3, 0.8, 0.3)]

var _next_ms := 0
var _vended: Array[int] = []
var _coil_root: Node3D


func default_state() -> Dictionary:
	return {"sold": 0}


func _build() -> void:
	var red := FunLooks.mat(Color(0.85, 0.12, 0.15), 0.35)
	var dark := FunLooks.mat(Color(0.1, 0.1, 0.12), 0.5)
	FunLooks.rounded_box(rig, Vector3(0.75, 1.85, 0.5), 0.05, red, Vector3(0, 0.925, 0))
	part(FunLooks.box(Vector3(0.48, 1.15, 0.02)), FunLooks.mat(Color(0.75, 0.9, 1, 0.35), 0.05), Vector3(-0.1, 1.15, 0.255))
	part(FunLooks.box(Vector3(0.5, 1.2, 0.01)), dark, Vector3(-0.1, 1.15, 0.24))
	_coil_root = Node3D.new()
	rig.add_child(_coil_root)
	for r in 5:
		var y := 0.68 + r * 0.22
		part(FunLooks.box(Vector3(0.48, 0.012, 0.2)), FunLooks.metal(FunLooks.CHROME), Vector3(-0.1, y - 0.03, 0.14))
		for c in 4:
			var x := -0.28 + c * 0.12
			part(FunLooks.torus(0.025, 0.032), FunLooks.metal(FunLooks.CHROME), Vector3(x, y + 0.02, 0.15),
				Vector3(PI / 2, 0, 0), Vector3(1, 3, 1), _coil_root)
			var col: Color = ROW_COLORS[(r + c) % ROW_COLORS.size()]
			FunLooks.rounded_box(rig, Vector3(0.08, 0.13, 0.04), 0.015, FunLooks.mat(col, 0.6), Vector3(x, y + 0.045, 0.2))
	# Keypad, coin slot, tray, logo.
	part(FunLooks.box(Vector3(0.16, 0.5, 0.02)), dark, Vector3(0.26, 1.2, 0.255))
	for i in 9:
		part(FunLooks.cyl(0.014, 0.014, 0.01, 8), FunLooks.metal(FunLooks.CHROME),
			Vector3(0.22 + (i % 3) * 0.04, 1.3 - (i / 3) * 0.05, 0.268), Vector3(PI / 2, 0, 0))
	part(FunLooks.box(Vector3(0.1, 0.06, 0.01)), FunLooks.mat(Color(0.3, 1, 0.4), 0.3, 0.0, 1.5), Vector3(0.26, 1.4, 0.268))
	part(FunLooks.box(Vector3(0.012, 0.05, 0.012)), FunLooks.mat(FunLooks.INK), Vector3(0.26, 1.1, 0.268))
	label("CARD READER\nOUT OF ORDER\n(it's free)", Vector3(0.26, 1.0, 0.268), 12, Color(1, 1, 0.6))
	part(FunLooks.box(Vector3(0.55, 0.2, 0.02)), dark, Vector3(-0.05, 0.3, 0.255))
	part(FunLooks.box(Vector3(0.5, 0.15, 0.02)), FunLooks.mat(Color(0.75, 0.9, 1, 0.4), 0.05), Vector3(-0.05, 0.3, 0.27), Vector3(0.2, 0, 0))
	label("SNAX-O-TRON\n3000", Vector3(-0.05, 1.67, 0.256), 34, Color(1, 0.95, 0.5))
	label("PUSH", Vector3(-0.05, 0.43, 0.27), 16, Color(1, 1, 1))
	collider(Vector3(0.75, 1.85, 0.5), Vector3(0, 0.925, 0))
	area(Vector3(0.8, 1.6, 0.35), Vector3(0, 0.9, 0.38), "Buy a random snack (free!) [E]", "buy")


func _play(fx: String, _args: Array) -> void:
	if fx == "vend":
		var tw := _coil_root.create_tween()
		tw.tween_property(_coil_root, "position:z", 0.03, 0.25)
		tw.tween_property(_coil_root, "position:z", 0.0, 0.2)
		FunFx.popup(world, global_point(Vector3(0, 0.6, 0.4)), "*KA-CHUNK*", Color(1, 0.9, 0.5), 50)


func act(peer: int, verb: String, _args: Array) -> void:
	if verb != "buy":
		return
	var now := Time.get_ticks_msec()
	if now < _next_ms:
		return
	_next_ms = now + COOLDOWN_MS
	var alive: Array[int] = []
	for id in _vended:
		if world.objects.has(id):
			alive.append(id)
	_vended = alive
	if _vended.size() >= MAX_ALIVE:
		world.notify(peer, "SOLD OUT. Eat what's already on the floor.")
		return
	var total := 0
	for s: Array in STOCK:
		total += int(s[2])
	var roll := randi() % total
	var pick: Array = STOCK[0]
	for s: Array in STOCK:
		roll -= int(s[2])
		if roll < 0:
			pick = s
			break
	var at := global_point(Vector3(-0.05, 0.35, 0.3))
	var obj := world.spawn_object(pick[0], Transform3D(world.plane.global_basis, at), pick[1])
	if obj == null:
		return
	_vended.append(World.net_id(obj))
	if obj is RigidBody3D:
		(obj as RigidBody3D).linear_velocity = world.plane.global_basis * (local_xform().basis * Vector3(0, 1.2, 2.0))
	state.sold = int(state.sold) + 1
	push_state("vend")
	world.notify(peer, "The machine dispenses %s." % pick[3])
