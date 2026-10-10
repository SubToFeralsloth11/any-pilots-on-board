extends RefCounted
## Static lounge furniture and decor, plus the galley's emergency shelves (identical on every
## peer, built in setup()).
## Layout (plane-local, the lounge spans x -2.5..2.5, z 6.2..11.8; |x| < 1.2 stays clear):
##   left wall:  booth A (z 6.5..8.1), booth B (z 8.5..10.1), lavatory (z 10.4..11.85)
##   right wall: weapons rack on the cabin bulkhead, bar (z 6.8..8.3), tall plant, vending,
##               slot machine and jukebox (stations), cargo-side corner
##   bulkheads:  TV (cabin side, left), hoop + dartboard face into the cargo hold.

const BOOTHS := [7.3, 9.3]          ## Table centre z for booth A and B.
const TABLE := Vector3(-1.98, 0.72, 0.0)
const TABLE_SIZE := Vector2(0.95, 0.72)
const BAR_Z := Vector2(6.85, 8.3)
const BAR_X := 2.15
const BAR_TOP := 1.05
const STOOL_X := 1.68
const RACK_X := 2.0
const RACK_Z := 6.1
const RACK_SHELVES := [0.62, 1.12, 1.62]
const VELVET := Color(0.55, 0.12, 0.2)
const VELVET_DARK := Color(0.38, 0.07, 0.13)


static func build(plane: Airliner) -> void:
	var root := Node3D.new()
	root.name = "FunLounge"
	plane.add_child(root)
	for z: float in BOOTHS:
		_booth(plane, root, z)
	_bar(plane, root)
	_rack(plane, root)
	_plant(plane, root, Vector3(2.22, 0, 8.6), 1.0)
	_plant(plane, root, Vector3(2.26, BAR_TOP, 6.98), 0.45)
	_hanging_plant(root, Vector3(-2.1, 2.62, 8.3))
	_hanging_plant(root, Vector3(2.1, 2.62, 10.0))
	_decor(root)
	_lights(root)
	_rug(root)
	_galley_shelves(plane, root)


static func _booth(plane: Airliner, root: Node3D, z: float) -> void:
	var velvet := FunLooks.mat(VELVET, 0.9)
	var velvet_dark := FunLooks.mat(VELVET_DARK, 0.9)
	var wood := FunLooks.mat(FunLooks.WOOD, 0.45)
	var brass := FunLooks.metal(FunLooks.BRASS)
	var x0 := TABLE.x
	# Table: rounded wood top with a brass edge on a pedestal.
	FunLooks.rounded_box(root, Vector3(TABLE_SIZE.x, 0.05, TABLE_SIZE.y), 0.025, wood, Vector3(x0, TABLE.y - 0.025, z))
	FunLooks.part(root, FunLooks.box(Vector3(TABLE_SIZE.x - 0.04, 0.012, 0.012)), brass, Vector3(x0, TABLE.y - 0.03, z + TABLE_SIZE.y / 2))
	FunLooks.part(root, FunLooks.cyl(0.05, 0.06, TABLE.y - 0.05), FunLooks.metal(FunLooks.CHROME), Vector3(x0, (TABLE.y - 0.05) / 2, z))
	FunLooks.part(root, FunLooks.cyl(0.22, 0.25, 0.03), FunLooks.metal(FunLooks.CHROME), Vector3(x0, 0.015, z))
	FunLooks.collider(plane, Vector3(TABLE_SIZE.x, 0.05, TABLE_SIZE.y), Transform3D(Basis.IDENTITY, Vector3(x0, TABLE.y - 0.025, z)))
	FunLooks.collider(plane, Vector3(0.12, TABLE.y, 0.12), Transform3D(Basis.IDENTITY, Vector3(x0, TABLE.y / 2, z)))
	# Two tufted benches facing each other across the table.
	for s in [-1.0, 1.0]:
		var bz: float = z + s * 0.72
		FunLooks.rounded_box(root, Vector3(1.0, 0.42, 0.5), 0.05, velvet_dark, Vector3(x0, 0.21, bz))
		FunLooks.rounded_box(root, Vector3(0.98, 0.12, 0.48), 0.05, velvet, Vector3(x0, 0.47, bz - s * 0.01))
		FunLooks.rounded_box(root, Vector3(1.0, 0.75, 0.14), 0.06, velvet, Vector3(x0, 0.82, bz + s * 0.22), Vector3(s * -0.1, 0, 0))
		for i in 3:
			FunLooks.part(root, FunLooks.sphere(0.022, 8), brass, Vector3(x0 - 0.3 + i * 0.3, 0.88, bz + s * 0.145))
		FunLooks.rounded_box(root, Vector3(1.02, 0.06, 0.18), 0.03, wood, Vector3(x0, 1.2, bz + s * 0.24))
		FunLooks.collider(plane, Vector3(1.0, 0.5, 0.5), Transform3D(Basis.IDENTITY, Vector3(x0, 0.25, bz)))
		FunLooks.collider(plane, Vector3(1.0, 1.0, 0.14), Transform3D(Basis.IDENTITY, Vector3(x0, 0.7, bz + s * 0.22)))
		for sx in [-0.25, 0.25]:
			var seat := Interactable.make(Vector3(0.4, 0.4, 0.4), "Sit in the booth [E]", "sit")
			seat.local_only = true
			seat.set_meta("seat", Vector3(x0 + sx + 0.1, 0.5, bz))
			seat.set_meta("seat_yaw", 0.0 if s > 0.0 else PI)   # Each bench faces the table.
			seat.position = Vector3(x0 + sx + 0.1, 0.62, bz)
			plane.add_area(seat)
	# Little table lamp with a fringed shade.
	var lamp := Vector3(TABLE.x - 0.37, TABLE.y, z + 0.22)
	FunLooks.part(root, FunLooks.cyl(0.035, 0.05, 0.03), brass, lamp + Vector3(0, 0.015, 0))
	FunLooks.part(root, FunLooks.cyl(0.008, 0.008, 0.2), brass, lamp + Vector3(0, 0.12, 0))
	FunLooks.part(root, FunLooks.cyl(0.04, 0.08, 0.09), FunLooks.mat(Color(1, 0.85, 0.55), 0.8, 0.0, 0.8), lamp + Vector3(0, 0.25, 0))
	var light := OmniLight3D.new()
	light.position = lamp + Vector3(0, 0.25, 0)
	light.light_color = Color(1, 0.8, 0.5)
	light.light_energy = 0.6
	light.omni_range = 1.6
	root.add_child(light)


static func _bar(plane: Airliner, root: Node3D) -> void:
	var zmid := (BAR_Z.x + BAR_Z.y) / 2
	var length := BAR_Z.y - BAR_Z.x
	var wood := FunLooks.mat(FunLooks.WOOD_DARK, 0.4)
	var top := FunLooks.mat(Color(0.12, 0.12, 0.14), 0.15, 0.3)
	var brass := FunLooks.metal(FunLooks.BRASS)
	FunLooks.rounded_box(root, Vector3(0.5, BAR_TOP - 0.05, length), 0.04, wood, Vector3(BAR_X, (BAR_TOP - 0.05) / 2, zmid))
	for i in 5:
		FunLooks.part(root, FunLooks.box(Vector3(0.01, 0.75, 0.08)), FunLooks.mat(FunLooks.WOOD, 0.5),
			Vector3(BAR_X - 0.255, 0.48, BAR_Z.x + 0.2 + i * (length - 0.4) / 4))
	FunLooks.rounded_box(root, Vector3(0.62, 0.05, length + 0.08), 0.025, top, Vector3(BAR_X - 0.04, BAR_TOP - 0.025, zmid))
	FunLooks.part(root, FunLooks.cyl(0.018, 0.018, length), brass, Vector3(BAR_X - 0.32, 0.22, zmid), Vector3(PI / 2, 0, 0))
	FunLooks.collider(plane, Vector3(0.6, BAR_TOP, length), Transform3D(Basis.IDENTITY, Vector3(BAR_X - 0.04, BAR_TOP / 2, zmid)))
	FunLooks.label(root, "THE MILE-HIGH BAR", Vector3(BAR_X - 0.27, 0.8, zmid), 30, Color(1, 0.8, 0.4), Vector3(0, -PI / 2, 0))
	# Bottle shelf on the wall behind the bar.
	for h in [1.45, 1.8]:
		FunLooks.part(root, FunLooks.box(Vector3(0.14, 0.025, length - 0.2)), FunLooks.mat(FunLooks.WOOD, 0.5),
			Vector3(2.68, h, zmid))
		for i in 7:
			var c: Color = [Color(0.2, 0.6, 0.3, 0.8), Color(0.6, 0.3, 0.15, 0.8), Color(0.9, 0.9, 0.95, 0.6),
				Color(0.3, 0.3, 0.8, 0.8)][(i + int(h * 10)) % 4]
			var bz: float = BAR_Z.x + 0.25 + i * (length - 0.5) / 6
			if absf(bz - 7.5) < 0.38:
				continue   # Leave the window clear.
			var bh := 0.16 + 0.05 * float((i * 7) % 3)
			FunLooks.part(root, FunLooks.cyl(0.03, 0.035, bh, 10), FunLooks.mat(c, 0.1), Vector3(2.68, h + 0.0125 + bh / 2, bz))
			FunLooks.part(root, FunLooks.cyl(0.012, 0.025, 0.06, 8), FunLooks.mat(c, 0.1), Vector3(2.68, h + bh + 0.04, bz))
			FunLooks.part(root, FunLooks.cyl(0.013, 0.013, 0.02, 8), FunLooks.mat(Color(0.8, 0.15, 0.1)), Vector3(2.68, h + bh + 0.08, bz))
	# Bar stools: chrome stem, footrest ring, padded round seat.
	for i in 3:
		var sz: float = BAR_Z.x + 0.28 + i * 0.5
		var base := Vector3(STOOL_X, 0, sz)
		FunLooks.part(root, FunLooks.cyl(0.16, 0.18, 0.03), FunLooks.metal(FunLooks.CHROME), base + Vector3(0, 0.015, 0))
		FunLooks.part(root, FunLooks.cyl(0.03, 0.035, 0.66), FunLooks.metal(FunLooks.CHROME), base + Vector3(0, 0.34, 0))
		FunLooks.part(root, FunLooks.torus(0.11, 0.13), FunLooks.metal(FunLooks.CHROME), base + Vector3(0, 0.3, 0))
		FunLooks.part(root, FunLooks.cyl(0.17, 0.16, 0.08, 20), FunLooks.mat(Color(0.85, 0.15, 0.2), 0.5), base + Vector3(0, 0.71, 0))
		FunLooks.part(root, FunLooks.torus(0.15, 0.175), FunLooks.mat(Color(0.6, 0.08, 0.12), 0.5), base + Vector3(0, 0.73, 0),
			Vector3.ZERO, Vector3(1, 0.5, 1))
		FunLooks.collider(plane, Vector3(0.3, 0.75, 0.3), Transform3D(Basis.IDENTITY, base + Vector3(0, 0.375, 0)))
		var seat := Interactable.make(Vector3(0.34, 0.3, 0.34), "Sit at the bar [E]", "sit")
		seat.local_only = true
		seat.set_meta("seat", base + Vector3(0, 0.78, 0))
		seat.set_meta("seat_yaw", -PI / 2)   # Facing the bar counter (+X).
		seat.position = base + Vector3(0, 0.85, 0)
		plane.add_area(seat)
	# Countertop clutter: a cocktail with an umbrella and a tip jar.
	var glass := FunLooks.mat(Color(0.8, 0.95, 1, 0.45), 0.05)
	var c0 := Vector3(BAR_X, BAR_TOP, 8.05)
	FunLooks.part(root, FunLooks.cyl(0.04, 0.008, 0.07, 12), glass, c0 + Vector3(0, 0.12, 0))
	FunLooks.part(root, FunLooks.cyl(0.006, 0.006, 0.08, 6), glass, c0 + Vector3(0, 0.045, 0))
	FunLooks.part(root, FunLooks.cyl(0.03, 0.03, 0.006, 12), glass, c0 + Vector3(0, 0.005, 0))
	FunLooks.part(root, FunLooks.cyl(0.035, 0.035, 0.03, 12), FunLooks.mat(Color(1, 0.5, 0.3, 0.8), 0.1), c0 + Vector3(0, 0.135, 0))
	FunLooks.part(root, FunLooks.cyl(0.0, 0.06, 0.03, 10), FunLooks.mat(Color(0.2, 0.8, 0.9)), c0 + Vector3(0.03, 0.22, 0), Vector3(0, 0, -0.4))
	FunLooks.part(root, FunLooks.cyl(0.003, 0.003, 0.1, 4), FunLooks.mat(FunLooks.WOOD_LIGHT), c0 + Vector3(0.015, 0.17, 0), Vector3(0, 0, -0.4))
	var jar := Vector3(BAR_X + 0.05, BAR_TOP, 7.38)
	FunLooks.part(root, FunLooks.cyl(0.05, 0.05, 0.12, 14), glass, jar + Vector3(0, 0.06, 0))
	FunLooks.part(root, FunLooks.sphere(0.035, 8), FunLooks.mat(Color(0.4, 0.75, 0.35)), jar + Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
	FunLooks.label(root, "TIPS\n(please)", jar + Vector3(-0.055, 0.07, 0), 14, Color(1, 1, 1), Vector3(0, -PI / 2, 0))


## Wall-mounted weapons rack on the cabin bulkhead, lounge side, right of the doorway.
static func _rack(plane: Airliner, root: Node3D) -> void:
	var wood := FunLooks.mat(FunLooks.WOOD, 0.5)
	var red := FunLooks.mat(Color(0.8, 0.12, 0.12), 0.4)
	FunLooks.rounded_box(root, Vector3(1.0, 1.55, 0.04), 0.03, FunLooks.mat(Color(0.2, 0.22, 0.26), 0.6), Vector3(RACK_X, 1.2, RACK_Z))
	for h: float in RACK_SHELVES:
		FunLooks.rounded_box(root, Vector3(1.0, 0.035, 0.3), 0.015, wood, Vector3(RACK_X, h - 0.0175, RACK_Z + 0.15))
		FunLooks.part(root, FunLooks.box(Vector3(1.0, 0.05, 0.015)), red, Vector3(RACK_X, h + 0.025, RACK_Z + 0.3))
		FunLooks.collider(plane, Vector3(1.0, 0.035, 0.3), Transform3D(Basis.IDENTITY, Vector3(RACK_X, h - 0.0175, RACK_Z + 0.15)))
		FunLooks.collider(plane, Vector3(1.0, 0.06, 0.02), Transform3D(Basis.IDENTITY, Vector3(RACK_X, h + 0.03, RACK_Z + 0.3)))
		for sx in [-0.48, 0.48]:
			FunLooks.part(root, FunLooks.prism(Vector3(0.02, 0.12, 0.28)), wood, Vector3(RACK_X + sx, h - 0.075, RACK_Z + 0.14),
				Vector3(0, 0, PI))
	FunLooks.label(root, "IN CASE OF BOREDOM\nBREAK GLASS", Vector3(RACK_X, 2.08, RACK_Z + 0.03), 26, Color(1, 0.35, 0.3))


static func _plant(plane: Airliner, root: Node3D, at: Vector3, height: float) -> void:
	var pot := FunLooks.mat(FunLooks.POT, 0.8)
	FunLooks.part(root, FunLooks.cyl(0.17, 0.12, 0.3, 16), pot, at + Vector3(0, 0.15, 0))
	FunLooks.part(root, FunLooks.torus(0.15, 0.19), pot, at + Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	FunLooks.part(root, FunLooks.cyl(0.15, 0.15, 0.02, 14), FunLooks.mat(Color(0.3, 0.2, 0.12), 1.0), at + Vector3(0, 0.29, 0))
	FunLooks.part(root, FunLooks.cyl(0.015, 0.02, height * 0.7, 6), FunLooks.mat(Color(0.4, 0.3, 0.15)), at + Vector3(0, 0.3 + height * 0.35, 0))
	var leaf := FunLooks.mat(FunLooks.LEAF, 0.7)
	var leaf_dark := FunLooks.mat(FunLooks.LEAF_DARK, 0.7)
	for i in 9:
		var a := i * 2.4
		var y := 0.35 + height * (0.3 + 0.07 * i)
		var tilt := 0.6 + 0.08 * (i % 3)
		var l := FunLooks.part(root, FunLooks.sphere(0.13, 10), leaf if i % 2 == 0 else leaf_dark,
			at + Vector3(cos(a) * 0.12, y, sin(a) * 0.12), Vector3(0, -a, tilt), Vector3(1.6, 0.18, 0.55))
		l.position += Vector3(cos(a), 0, sin(a)) * 0.08
	FunLooks.collider(plane, Vector3(0.34, 0.6, 0.34), Transform3D(Basis.IDENTITY, at + Vector3(0, 0.3, 0)))


static func _hanging_plant(root: Node3D, at: Vector3) -> void:
	var cord := FunLooks.mat(Color(0.85, 0.8, 0.7), 0.9)
	for i in 3:
		var a := i * TAU / 3
		FunLooks.part(root, FunLooks.cyl(0.004, 0.004, 0.32, 4), cord, at + Vector3(cos(a) * 0.05, 0.16, sin(a) * 0.05))
	FunLooks.part(root, FunLooks.sphere(0.12, 14), FunLooks.mat(Color(0.95, 0.95, 0.92), 0.4), at, Vector3.ZERO, Vector3(1, 0.7, 1))
	for i in 8:
		var a := i * TAU / 8
		var length := 0.3 + 0.12 * (i % 3)
		var out := Vector3(cos(a), 0, sin(a))
		var leaf := FunLooks.mat(FunLooks.LEAF if i % 2 else FunLooks.LEAF_DARK, 0.7)
		# Vines droop from the pot rim, tipped slightly outward, with leaves along them.
		FunLooks.part(root, FunLooks.cyl(0.008, 0.008, length, 5), leaf, at + out * 0.13 + Vector3(0, -length / 2, 0),
			Vector3(sin(a) * 0.2, 0, -cos(a) * 0.2))
		for k in 3:
			FunLooks.part(root, FunLooks.sphere(0.035, 8), leaf, at + out * (0.14 + 0.03 * k) + Vector3(0, -0.06 - k * length / 3, 0),
				Vector3(0, -a, 0.5), Vector3(1.4, 0.3, 0.8))


## Framed pictures between the windows, a clock, and a "fasten seatbelt" sign that lies.
static func _decor(root: Node3D) -> void:
	var frame := FunLooks.metal(FunLooks.BRASS)
	var arts := [["Sky\nat\nNight", Color(0.12, 0.15, 0.4)], ["Cloud\n#47", Color(0.55, 0.75, 0.95)],
		["Dog\nFlying\nPlane", Color(0.95, 0.75, 0.4)], ["Not a\nWindow", Color(0.3, 0.7, 0.45)]]
	var spots := [[-1.0, 8.25], [-1.0, 9.75], [1.0, 9.75], [1.0, 11.3]]
	for i in spots.size():
		var sx: float = spots[i][0]
		var z: float = spots[i][1]
		var x := sx * 2.74
		var rot := Vector3(0, -sx * PI / 2, 0)
		FunLooks.rounded_box(root, Vector3(0.04, 0.5, 0.42), 0.015, frame, Vector3(x, 1.75, z))
		FunLooks.part(root, FunLooks.box(Vector3(0.01, 0.42, 0.34)), FunLooks.mat(arts[i][1], 0.9), Vector3(x - sx * 0.022, 1.75, z))
		FunLooks.label(root, arts[i][0], Vector3(x - sx * 0.03, 1.75, z), 22, Color(1, 1, 1, 0.9), rot)
	# Wall clock on the cargo bulkhead (it's always five o'clock somewhere).
	var clock_at := Vector3(1.95, 2.3, 11.9)
	FunLooks.part(root, FunLooks.cyl(0.16, 0.16, 0.04, 24), FunLooks.mat(FunLooks.CREAM, 0.5), clock_at, Vector3(PI / 2, 0, 0))
	FunLooks.part(root, FunLooks.torus(0.155, 0.18), frame, clock_at, Vector3(PI / 2, 0, 0))
	FunLooks.part(root, FunLooks.box(Vector3(0.012, 0.11, 0.005)), FunLooks.mat(FunLooks.INK), clock_at + Vector3(0, 0.05, -0.025))
	FunLooks.part(root, FunLooks.box(Vector3(0.08, 0.012, 0.005)), FunLooks.mat(FunLooks.INK), clock_at + Vector3(0.04, 0, -0.025))
	FunLooks.label(root, "5 O'CLOCK\nSOMEWHERE", clock_at + Vector3(0, -0.25, -0.03), 18, Color(1, 0.85, 0.5), Vector3(0, PI, 0))
	FunLooks.label(root, "FASTEN SEATBELT\n(optional)", Vector3(0, 2.8, 11.7), 20, Color(1, 0.85, 0.3), Vector3(0, PI, 0))


## Warm ceiling pendant lamps over the walkway.
static func _lights(root: Node3D) -> void:
	for z in [7.3, 9.3, 11.0]:
		var at := Vector3(0, 2.82, z)
		FunLooks.part(root, FunLooks.cyl(0.004, 0.004, 0.18, 4), FunLooks.mat(FunLooks.INK), at + Vector3(0, 0.09, 0))
		FunLooks.part(root, FunLooks.cyl(0.04, 0.14, 0.1, 18), FunLooks.metal(FunLooks.BRASS), at - Vector3(0, 0.02, 0))
		FunLooks.part(root, FunLooks.sphere(0.045, 10), FunLooks.mat(Color(1, 0.9, 0.6), 0.3, 0.0, 3.0), at - Vector3(0, 0.07, 0))
		var l := OmniLight3D.new()
		l.position = at - Vector3(0, 0.15, 0)
		l.light_color = Color(1, 0.82, 0.6)
		l.light_energy = 0.7
		l.omni_range = 3.0
		root.add_child(l)


## A round patterned rug in the walkway.
static func _rug(root: Node3D) -> void:
	var z := 9.3
	FunLooks.part(root, FunLooks.cyl(0.75, 0.75, 0.006, 32), FunLooks.mat(Color(0.85, 0.65, 0.3), 1.0), Vector3(0, 0.018, z))
	FunLooks.part(root, FunLooks.cyl(0.6, 0.6, 0.007, 32), FunLooks.mat(Color(0.6, 0.15, 0.25), 1.0), Vector3(0, 0.019, z))
	FunLooks.part(root, FunLooks.cyl(0.3, 0.3, 0.008, 24), FunLooks.mat(Color(0.95, 0.85, 0.6), 1.0), Vector3(0, 0.02, z))
	FunLooks.part(root, FunLooks.torus(0.42, 0.46), FunLooks.mat(Color(0.95, 0.85, 0.6), 1.0), Vector3(0, 0.02, z),
		Vector3.ZERO, Vector3(1, 0.05, 1))


## Two "IN CASE OF EMERGENCY" shelves on the cockpit bulkhead above the galley counters,
## out of reach of the trolley and the crew (the frying pan and fire axe start here).
static func _galley_shelves(plane: Airliner, root: Node3D) -> void:
	var wood := FunLooks.mat(FunLooks.WOOD, 0.5)
	var red := FunLooks.mat(Color(0.85, 0.12, 0.12), 0.4)
	for sx in [-1.0, 1.0]:
		var at := Vector3(sx * 2.05, 1.55, -9.78)
		FunLooks.rounded_box(root, Vector3(0.95, 0.035, 0.36), 0.015, wood, at)
		FunLooks.part(root, FunLooks.box(Vector3(0.95, 0.06, 0.015)), red, at + Vector3(0, 0.03, 0.18))
		for bx in [-0.4, 0.4]:
			FunLooks.part(root, FunLooks.prism(Vector3(0.02, 0.12, 0.34)), wood, at + Vector3(bx, -0.075, 0), Vector3(0, 0, PI))
		FunLooks.collider(plane, Vector3(0.95, 0.035, 0.36), Transform3D(Basis.IDENTITY, at))
		FunLooks.collider(plane, Vector3(0.95, 0.07, 0.02), Transform3D(Basis.IDENTITY, at + Vector3(0, 0.035, 0.18)))
		FunLooks.label(root, "IN CASE OF\nEMERGENCY", at + Vector3(0, 0.42, -0.1), 22, Color(1, 0.35, 0.3))
