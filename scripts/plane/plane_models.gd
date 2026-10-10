extends RefCounted
## Reusable chunky-cartoon models for the airliner, built into a MeshBatch batch:
## passenger seat (instanced with a MultiMesh), oxygen mask, propeller and airfoils.

const MeshBatch := preload("res://scripts/plane/plane_mesh.gd")
const MATTE := MeshBatch.Finish.MATTE
const FABRIC := MeshBatch.Finish.FABRIC
const PAINT := MeshBatch.Finish.PAINT
const METAL := MeshBatch.Finish.METAL
const GLOSS := MeshBatch.Finish.GLOSS
const GLOW := MeshBatch.Finish.GLOW

const SEAT_BLUE := Color(0.16, 0.42, 0.92)
const SEAT_BLUE_DARK := Color(0.1, 0.27, 0.66)
const SHELL := Color(0.95, 0.96, 0.98)
const STRAP := Color(0.36, 0.38, 0.42)
const STEEL := Color(0.7, 0.72, 0.76)
const SCREEN := Color(0.05, 0.06, 0.08)
const MASK_YELLOW := Color(1.0, 0.82, 0.1)


static func _at(p: Vector3, b := Basis.IDENTITY) -> Transform3D:
	return Transform3D(b, p)


## Passenger seat facing -Z; origin on the floor under the seat centre. Cushion top ~y 0.5.
## Blue cushions in a white shell, lap belt, armrests, seat-back screen, tray and pocket.
static func seat(b: MeshBatch) -> void:
	# Legs and cross bar.
	for lx: float in [-0.17, 0.17]:
		b.cylinder(Vector3(lx, 0, -0.16), Vector3(lx, 0.34, -0.06), 0.022, 0.022, STEEL, METAL, 8, false)
		b.cylinder(Vector3(lx, 0, 0.2), Vector3(lx, 0.34, 0.1), 0.022, 0.022, STEEL, METAL, 8, false)
	b.cylinder(Vector3(-0.24, 0.33, 0.0), Vector3(0.24, 0.33, 0.0), 0.025, 0.025, STEEL, METAL, 8)
	# Seat pan: white shell under a blue cushion.
	b.rounded_box(Vector3(0.52, 0.09, 0.5), _at(Vector3(0, 0.36, -0.01)), SHELL, PAINT, 0.25)
	b.rounded_box(Vector3(0.47, 0.14, 0.47), _at(Vector3(0, 0.43, -0.03)), SEAT_BLUE, FABRIC, 0.4)
	# Lap belt lying across the cushion, buckle in the middle.
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(0.19, 0.012, 0.055), _at(Vector3(sx * 0.12, 0.502, -0.08)), STRAP, MATTE)
		b.box(Vector3(0.012, 0.12, 0.055), _at(Vector3(sx * 0.236, 0.45, -0.08)), STRAP, MATTE)
	b.rounded_box(Vector3(0.08, 0.02, 0.06), _at(Vector3(0, 0.508, -0.08)), STEEL, METAL, 0.3, 8, 4)
	# Backrest, leaning back a little: shell, sculpted cushion, headrest with a white cover.
	var back := Transform3D(Basis(Vector3.RIGHT, 0.14), Vector3(0, 0.4, 0.27))
	b.rounded_box(Vector3(0.52, 0.88, 0.12), back * _at(Vector3(0, 0.45, 0.03)), SHELL, PAINT, 0.3)
	b.rounded_box(Vector3(0.45, 0.62, 0.11), back * _at(Vector3(0, 0.36, -0.035)), SEAT_BLUE, FABRIC, 0.45)
	b.rounded_box(Vector3(0.34, 0.24, 0.06), back * _at(Vector3(0, 0.22, -0.085)), SEAT_BLUE, FABRIC, 0.6, 8, 4)
	b.rounded_box(Vector3(0.42, 0.21, 0.13), back * _at(Vector3(0, 0.78, -0.04)), SEAT_BLUE_DARK, FABRIC, 0.45)
	b.rounded_box(Vector3(0.34, 0.13, 0.025), back * _at(Vector3(0, 0.79, -0.11)), SHELL, FABRIC, 0.3, 8, 4)
	# Seat back (seen by the row behind): screen, folded tray with latch, pocket.
	b.rounded_box(Vector3(0.24, 0.16, 0.025), back * _at(Vector3(0, 0.66, 0.095)), SCREEN, GLOSS, 0.25, 8, 4)
	b.box(Vector3(0.2, 0.12, 0.004), back * _at(Vector3(0, 0.66, 0.109)), Color(0.25, 0.6, 1.0), GLOW)
	b.rounded_box(Vector3(0.38, 0.27, 0.025), back * _at(Vector3(0, 0.38, 0.095)), Color(0.78, 0.8, 0.84), PAINT, 0.2, 8, 4)
	b.rounded_box(Vector3(0.06, 0.025, 0.02), back * _at(Vector3(0, 0.53, 0.11)), STEEL, METAL, 0.3, 8, 4)
	b.rounded_box(Vector3(0.36, 0.15, 0.035), back * _at(Vector3(0, 0.15, 0.095)), SEAT_BLUE_DARK, FABRIC, 0.3, 8, 4)
	# Armrests on posts.
	for sx: float in [-1.0, 1.0]:
		b.rounded_box(Vector3(0.065, 0.065, 0.44), _at(Vector3(sx * 0.27, 0.65, 0.0)), SHELL, PAINT, 0.4, 8, 4)
		b.rounded_box(Vector3(0.04, 0.27, 0.05), _at(Vector3(sx * 0.27, 0.49, 0.16)), Color(0.75, 0.77, 0.8), PAINT, 0.4, 8, 4)


## Oxygen mask hanging from its tube end at the origin: yellow cup below, opening toward +Z,
## clear reservoir bag under it.
static func oxygen_mask(b: MeshBatch) -> void:
	var cup := _at(Vector3(0, -0.07, 0))
	b.revolve(PackedVector2Array([Vector2(-0.05, 0.0), Vector2(-0.05, 0.022), Vector2(-0.02, 0.048),
		Vector2(0.02, 0.058), Vector2(0.03, 0.06)]), cup, MASK_YELLOW, GLOSS, 14)
	b.revolve(PackedVector2Array([Vector2(0.03, 0.054), Vector2(0.0, 0.048), Vector2(-0.04, 0.0)]),
		cup, MASK_YELLOW.darkened(0.25), GLOSS, 14, true)
	b.cylinder(Vector3(0, 0, 0), Vector3(0, -0.04, -0.03), 0.012, 0.016, Color(0.95, 0.95, 0.9), GLOSS, 8)
	b.ellipsoid(Vector3(0.045, 0.08, 0.03), _at(Vector3(0, -0.2, -0.01)), Color(0.82, 0.92, 0.85), GLOSS, 10, 6)
	# Elastic band looping behind the cup.
	b.box(Vector3(0.13, 0.008, 0.008), _at(Vector3(0, -0.07, 0.035)), Color(0.9, 0.85, 0.7), MATTE)


## Thin unit tube from y 0 to y 1 (scaled to length at runtime).
static func mask_tube(b: MeshBatch) -> void:
	b.cylinder(Vector3.ZERO, Vector3.UP, 0.006, 0.006, Color(0.92, 0.94, 0.95), GLOSS, 6, false)


## Four-blade propeller with spinner; spins about local Z, front toward -Z.
static func propeller(b: MeshBatch, radius: float) -> void:
	b.revolve(PackedVector2Array([Vector2(0.05, 0.0), Vector2(0.05, 0.25), Vector2(-0.12, 0.24),
		Vector2(-0.3, 0.17), Vector2(-0.42, 0.07), Vector2(-0.46, 0.0)]), Transform3D.IDENTITY,
		Color(0.97, 0.97, 0.98), PAINT, 18)
	var blade := airfoil(1.0, 0.12, 0.04, 6)
	for i in blade.size():
		blade[i] = blade[i] - Vector2(0.4, 0.0)   # Pivot near the quarter chord.
	# [span radius, chord, twist]; the duplicated station gives a crisp yellow tip band.
	var stations := [[0.16, 0.2, 0.55], [0.45, 0.22, 0.35], [radius - 0.16, 0.16, 0.18],
		[radius - 0.16, 0.16, 0.18], [radius, 0.1, 0.1]]
	for k in 4:
		var rot := Basis(Vector3.BACK, TAU * k / 4.0)
		var rows: Array[Transform3D] = []
		var cols := PackedColorArray()
		for i in stations.size():
			var st: Array = stations[i]
			var c: float = st[1]
			# Blade-local: chord along X, thickness along Z, span along Y; twisted about Y.
			var basis := rot * Basis(Vector3.UP, float(st[2])) * Basis.from_scale(Vector3(c, 1.0, c)) \
				* Basis(Vector3.RIGHT, PI / 2)
			rows.append(Transform3D(basis, rot * Vector3(0, st[0], -0.1)))
			cols.append(Color(1.0, 0.8, 0.1) if i >= 3 else Color(0.16, 0.17, 0.2))
		b.sweep(blade, rows, Color(0.16, 0.17, 0.2), MATTE, true, cols)


## Closed airfoil outline (chord along +X from 0 to `chord`, thickness along Y), starting at
## the trailing edge, over the top to the leading edge and back underneath.
static func airfoil(chord: float, thickness: float, camber: float, per_side := 9) -> PackedVector2Array:
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for k in per_side + 1:
		var u := pow(float(k) / per_side, 1.6)   # Denser near the rounded leading edge.
		var yt := 5.0 * thickness * (0.2969 * sqrt(u) - 0.126 * u - 0.3516 * u * u + 0.2843 * u * u * u - 0.1036 * u * u * u * u)
		var yc := camber * 4.0 * u * (1.0 - u)
		top.append(Vector2(u * chord, yc + yt))
		bottom.append(Vector2(u * chord, yc - yt))
	var out := PackedVector2Array()
	for k in range(per_side, -1, -1):
		out.append(top[k])
	for k in range(1, per_side):
		out.append(bottom[k])
	return out
