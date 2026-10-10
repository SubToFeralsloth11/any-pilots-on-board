extends RefCounted
## Chunky cartoon models for the cargo hold: the seven cargo kinds (luggage pallet, mail sacks,
## fragile vase crate, chicken coop, crocodile crate, explosive barrels, mystery crate), the
## escaped chickens and crocodile, and the yellow ratchet straps. Built from FunLooks primitives,
## then merged into one cached mesh per look (PropLooks.merge_static). Named nodes in `parts`
## (lids, doors, jaws, wings, glows) stay separate so they can animate.
##
## Every cargo model is centred on its body origin with its label side facing local +Z.

const PropLooks := preload("res://scripts/props/prop_looks.gd")

## Per kind: display name, collision size (m), mass (kg), friction, impact sound (fx.gd name).
const SPECS := {
	"luggage": {"name": "pallet of luggage", "size": Vector3(1.0, 1.0, 1.0), "mass": 80.0, "friction": 0.8, "sound": "thud"},
	"mail": {"name": "mail sacks", "size": Vector3(0.95, 0.8, 0.95), "mass": 35.0, "friction": 0.9, "sound": "thud"},
	"fragile": {"name": "crate of antique vases", "size": Vector3(0.9, 0.8, 0.9), "mass": 45.0, "friction": 0.6, "sound": "knock"},
	"chickens": {"name": "chicken coop", "size": Vector3(0.95, 0.75, 0.85), "mass": 25.0, "friction": 0.6, "sound": "knock"},
	"crocodile": {"name": "crocodile crate", "size": Vector3(1.0, 0.8, 1.15), "mass": 120.0, "friction": 0.7, "sound": "knock"},
	"explosive": {"name": "explosive barrels", "size": Vector3(0.95, 1.0, 0.95), "mass": 70.0, "friction": 0.5, "sound": "clank"},
	"mystery": {"name": "mystery crate", "size": Vector3(0.85, 0.85, 0.85), "mass": 40.0, "friction": 0.6, "sound": "knock"},
}
const KINDS := ["luggage", "mail", "fragile", "chickens", "crocodile", "explosive", "mystery"]

const WOOD := Color(0.78, 0.56, 0.32)
const PALLET := Color(0.7, 0.5, 0.3)
const STEEL := Color(0.72, 0.74, 0.78)
const INK := Color(0.1, 0.1, 0.12)
const STRAP := Color(1.0, 0.72, 0.08)
const CASES := [Color(0.9, 0.25, 0.25), Color(0.2, 0.55, 0.95), Color(0.25, 0.75, 0.35), Color(0.95, 0.75, 0.15),
	Color(0.6, 0.35, 0.85), Color(0.95, 0.5, 0.7), Color(0.3, 0.3, 0.35)]
const VASE_BLUE := Color(0.18, 0.32, 0.8)
const PORCELAIN := Color(0.97, 0.96, 0.92)
const GOLD := Color(0.95, 0.75, 0.25)
const HEN := Color(0.98, 0.96, 0.9)
const HEN_BROWN := Color(0.82, 0.48, 0.2)
const COMB := Color(0.95, 0.12, 0.12)
const BEAK := Color(1.0, 0.62, 0.1)
const CROC := Color(0.3, 0.62, 0.26)
const CROC_DARK := Color(0.18, 0.42, 0.17)
const CROC_BELLY := Color(0.88, 0.86, 0.58)
const BARREL := Color(0.88, 0.16, 0.12)
const HAZARD := Color(1.0, 0.82, 0.08)
const MYSTERY := Color(0.24, 0.12, 0.34)
const MYSTERY_GLOW := Color(0.75, 0.35, 1.0)


static func m(c: Color, rough := 0.65) -> StandardMaterial3D:
	return FunLooks.mat(c, rough)


static func shiny(c: Color) -> StandardMaterial3D:
	return FunLooks.mat(c, 0.3)


static func metal(c: Color) -> StandardMaterial3D:
	return FunLooks.metal(c)


## Builds the model of cargo `kind` under `vis`. `extra` holds cosmetic state (open, hens...).
static func build(vis: Node3D, kind: String, extra: Dictionary, parts: Dictionary) -> void:
	match kind:
		"luggage":
			_luggage(vis, int(extra.get("v", 0)))
		"mail":
			_mail(vis)
		"fragile":
			_fragile(vis)
		"chickens":
			_coop(vis, parts)
		"crocodile":
			_croc_crate(vis, parts)
		"explosive":
			_barrels(vis)
		"mystery":
			_mystery(vis, parts)
	var size: Vector3 = SPECS[kind].size
	var strap := Node3D.new()
	strap.name = "Strap"
	vis.add_child(strap)
	_straps(strap, size)
	parts.strap = strap
	strap.visible = bool(extra.get("strapped", false))
	finish(vis, parts, "cargo/%s/%d" % [kind, int(extra.get("v", 0)) % CASES.size() if kind == "luggage" else 0])


## Merges the static pieces of `vis` (each named part separately) into cached meshes.
static func finish(vis: Node3D, parts: Dictionary, key: String) -> void:
	var keep: Array = parts.values()
	for part_name: String in parts:
		var n: Node3D = parts[part_name]
		if not (n is MeshInstance3D or n is Label3D or n is Light3D):
			PropLooks.merge_static(n, [], "%s/%s" % [key, part_name])
	PropLooks.merge_static(vis, keep, key)


# --- Shared bits ---------------------------------------------------------------------------

## Wooden pallet whose top surface sits at `top` (local y), `w` wide and `d` deep.
static func _pallet(b: Node3D, w: float, d: float, top: float) -> void:
	var wood := m(PALLET)
	var dark := m(PALLET.darkened(0.25))
	for sx: float in [-1.0, 0.0, 1.0]:
		FunLooks.part(b, FunLooks.box(Vector3(0.1, 0.09, d)), dark, Vector3(sx * (w * 0.5 - 0.06), top - 0.075, 0))
	var n := 5
	for i in n:
		var z := -d * 0.5 + d / n * (i + 0.5)
		FunLooks.part(b, FunLooks.box(Vector3(w, 0.03, d / n - 0.025)), wood, Vector3(0, top - 0.015, z))


## Slatted crate body (sides, corner posts, steel corner caps), open on top.
static func _crate_shell(b: Node3D, size: Vector3, wood_c: Color, slats := 4) -> void:
	var wood := m(wood_c)
	var frame := m(wood_c.darkened(0.3))
	var gap := m(wood_c.darkened(0.65))
	var h := size * 0.5
	FunLooks.part(b, FunLooks.box(size - Vector3(0.06, 0.04, 0.06)), gap, Vector3.ZERO)
	for side in 4:
		var yaw := side * PI / 2
		var n := Vector3(sin(yaw), 0, cos(yaw))
		var half_depth := h.z if side % 2 == 0 else h.x
		var width := size.x if side % 2 == 0 else size.z
		for i in slats:
			var y := -h.y + size.y / slats * (i + 0.5)
			var shade := wood_c.lightened(0.05 * ((i + side) % 2)).darkened(0.04 * (i % 3))
			FunLooks.part(b, FunLooks.box(Vector3(width - 0.06, size.y / slats - 0.02, 0.025)), m(shade),
				n * (half_depth - 0.01) + Vector3(0, y, 0), Vector3(0, yaw, 0))
		var brace := FunLooks.part(b, FunLooks.box(Vector3(sqrt(width * width + size.y * size.y) * 0.92, 0.06, 0.024)),
			frame, n * half_depth, Vector3(0, yaw, 0))
		brace.rotate_object_local(Vector3.FORWARD, atan2(size.y, width) * (1.0 if side % 2 == 0 else -1.0))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			FunLooks.part(b, FunLooks.box(Vector3(0.07, size.y + 0.02, 0.07)), frame, Vector3(sx * (h.x - 0.02), 0, sz * (h.z - 0.02)))
			for sy: float in [-1.0, 1.0]:
				FunLooks.part(b, FunLooks.box(Vector3(0.1, 0.07, 0.1)), metal(STEEL), Vector3(sx * (h.x - 0.02), sy * (h.y - 0.02), sz * (h.z - 0.02)))
	FunLooks.part(b, FunLooks.box(Vector3(size.x * 0.98, 0.07, size.z * 0.98)), wood, Vector3(0, -h.y + 0.035, 0))


## Solid lid of planks for a crate of `size`, as its own node (it flies off when the crate opens).
static func _lid(b: Node3D, size: Vector3, wood_c: Color) -> Node3D:
	var lid := Node3D.new()
	lid.position = Vector3(0, size.y * 0.5, 0)
	b.add_child(lid)
	var n := 5
	for i in n:
		FunLooks.part(lid, FunLooks.box(Vector3(size.x + 0.04, 0.05, size.z / n - 0.01)), m(wood_c.lightened(0.06 + 0.04 * (i % 2))),
			Vector3(0, 0.0, -size.z * 0.5 + size.z / n * (i + 0.5)))
	for sx: float in [-1.0, 1.0]:
		FunLooks.part(lid, FunLooks.box(Vector3(0.07, 0.03, size.z + 0.04)), m(wood_c.darkened(0.3)), Vector3(sx * size.x * 0.3, 0.035, 0))
	return lid


## A stencil label on the +Z face (or rotated by `yaw` around the crate).
static func _stencil(b: Node3D, text: String, size: Vector3, y: float, color: Color, font := 40, yaw := 0.0) -> Label3D:
	var depth := size.z * 0.5 if is_zero_approx(fmod(yaw, PI)) else size.x * 0.5
	var l := FunLooks.label(b, text, Vector3(sin(yaw), 0, cos(yaw)) * (depth + 0.02) + Vector3(0, y, 0), font, color,
		Vector3(0, yaw, 0), 0.0028)
	l.outline_size = 0
	return l


## Yellow ratchet straps over a box of `size`: two bands across X, a buckle and floor rings.
static func _straps(b: Node3D, size: Vector3) -> void:
	var strap := m(STRAP, 0.5)
	var h := size * 0.5
	for sz: float in [-0.28, 0.28]:
		var z := sz * size.z
		FunLooks.part(b, FunLooks.box(Vector3(size.x + 0.04, 0.02, 0.08)), strap, Vector3(0, h.y + 0.01, z))
		for sx: float in [-1.0, 1.0]:
			FunLooks.part(b, FunLooks.box(Vector3(0.02, size.y + 0.02, 0.08)), strap, Vector3(sx * (h.x + 0.02), 0.0, z))
			FunLooks.part(b, FunLooks.torus(0.025, 0.05), metal(STEEL), Vector3(sx * (h.x + 0.06), -h.y + 0.01, z))
		FunLooks.part(b, FunLooks.box(Vector3(0.05, 0.1, 0.12)), metal(STEEL), Vector3(h.x + 0.045, 0.05, z))
		FunLooks.part(b, FunLooks.box(Vector3(0.025, 0.02, 0.16)), m(INK), Vector3(h.x + 0.075, 0.1, z), Vector3(0.5, 0, 0))


# --- Cargo kinds ---------------------------------------------------------------------------

## Pallet stacked with suitcases, a duffel bag and a hat box.
static func _luggage(b: Node3D, v: int) -> void:
	_pallet(b, 1.0, 1.0, -0.38)
	var cases := [
		[Vector3(0.46, 0.26, 0.92), Vector3(-0.25, -0.24, 0), 0.0],
		[Vector3(0.46, 0.26, 0.92), Vector3(0.25, -0.24, 0), 0.0],
		[Vector3(0.9, 0.24, 0.44), Vector3(0, 0.01, -0.23), 0.0],
		[Vector3(0.86, 0.24, 0.42), Vector3(0.02, 0.01, 0.23), 0.04],
		[Vector3(0.4, 0.22, 0.32), Vector3(0.18, 0.24, -0.2), 0.2],
	]
	for i in cases.size():
		var c: Array = cases[i]
		var col: Color = CASES[(v + i * 3) % CASES.size()]
		var sz: Vector3 = c[0]
		var node := FunLooks.rounded_box(b, sz, 0.05, shiny(col), c[1], Vector3(0, c[2], 0))
		# Darker band round the middle, chrome corner studs and an end handle.
		FunLooks.part(node, FunLooks.box(Vector3(sz.x + 0.01, sz.y * 0.18, sz.z + 0.01)), m(col.darkened(0.35)), Vector3.ZERO)
		var long_z := sz.z > sz.x
		var end := Vector3(0, 0, sz.z * 0.5 + 0.01) if long_z else Vector3(sz.x * 0.5 + 0.01, 0, 0)
		FunLooks.part(node, FunLooks.torus(0.03, 0.05), m(INK), end + Vector3(0, sz.y * 0.1, 0),
			Vector3(PI / 2, 0, 0) if long_z else Vector3(0, 0, PI / 2), Vector3(1.4, 1, 0.7))
		FunLooks.part(node, FunLooks.box(Vector3(0.1, 0.06, 0.005)), m(Color(0.98, 0.95, 0.85)),
			end + Vector3(0.1, -0.02, 0.003) if long_z else end + Vector3(0.003, -0.02, 0.1), Vector3(0, 0 if long_z else PI / 2, 0))
	FunLooks.part(b, FunLooks.capsule(0.14, 0.72), m(CASES[(v + 5) % CASES.size()].darkened(0.1)), Vector3(-0.1, 0.27, 0.2), Vector3(0, 0, PI / 2))
	FunLooks.part(b, FunLooks.torus(0.1, 0.13), m(INK), Vector3(-0.1, 0.38, 0.2), Vector3(PI / 2, 0, 0), Vector3(1, 1, 0.5))
	FunLooks.part(b, FunLooks.cyl(0.14, 0.14, 0.16), m(Color(0.95, 0.85, 0.7)), Vector3(0.3, 0.42, 0.25))
	FunLooks.part(b, FunLooks.cyl(0.145, 0.145, 0.03), m(Color(0.75, 0.2, 0.3)), Vector3(0.3, 0.49, 0.25))
	_stencil(b, "PAX BAGS", Vector3(1.0, 1.0, 1.0), -0.445, Color(0.98, 0.95, 0.85), 30)


## Four plump canvas sacks on a small pallet, tied at the neck, with AIR MAIL stripes.
static func _mail(b: Node3D) -> void:
	_pallet(b, 0.95, 0.95, -0.3)
	var sacks := [Vector3(-0.22, -0.08, -0.2), Vector3(0.22, -0.08, -0.22), Vector3(-0.2, -0.08, 0.22),
		Vector3(0.23, -0.08, 0.2), Vector3(0.0, 0.17, 0.0)]
	for i in sacks.size():
		var p: Vector3 = sacks[i]
		var col := Color(0.86, 0.78, 0.6) if i % 2 == 0 else Color(0.62, 0.68, 0.8)
		var tilt := Vector3(0.15 * (i % 3 - 1), i * 1.3, 0.12 * ((i + 1) % 3 - 1))
		FunLooks.part(b, FunLooks.sphere(0.5, 14), m(col), p, tilt, Vector3(0.44, 0.4, 0.44))
		FunLooks.part(b, FunLooks.sphere(0.5, 14), m(Color(0.85, 0.15, 0.15) if i % 2 == 0 else Color(0.15, 0.3, 0.8)),
			p, tilt, Vector3(0.448, 0.08, 0.448))
		var neck := p + Vector3(0, 0.2, 0)
		FunLooks.part(b, FunLooks.cyl(0.03, 0.06, 0.08), m(col.darkened(0.15)), neck)
		FunLooks.part(b, FunLooks.torus(0.025, 0.045), m(Color(0.55, 0.4, 0.25)), neck + Vector3(0, 0.01, 0))
		FunLooks.part(b, FunLooks.sphere(0.055, 10), m(col.darkened(0.1)), neck + Vector3(0, 0.07, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	_stencil(b, "AIR MAIL", Vector3(0.95, 0.8, 0.95), -0.36, Color(0.98, 0.95, 0.85), 28)


## Open slatted crate full of straw with blue-and-white antique vases poking out.
static func _fragile(b: Node3D) -> void:
	var size: Vector3 = SPECS.fragile.size
	_crate_shell(b, size, WOOD.lightened(0.05), 4)
	FunLooks.part(b, FunLooks.box(Vector3(size.x - 0.08, 0.04, size.z - 0.08)), m(Color(0.95, 0.82, 0.35)), Vector3(0, size.y * 0.5 - 0.06, 0))
	for i in 9:
		var a := i * 2.4
		FunLooks.part(b, FunLooks.box(Vector3(0.18, 0.012, 0.02)), m(Color(1.0, 0.88, 0.45)),
			Vector3(cos(a) * 0.3, size.y * 0.5 - 0.035, sin(a) * 0.3), Vector3(0.3, a, 0.2))
	var vases := [Vector3(-0.2, 0, -0.2), Vector3(0.2, 0, -0.18), Vector3(-0.18, 0, 0.2), Vector3(0.21, 0, 0.2)]
	for i in vases.size():
		var p: Vector3 = vases[i] + Vector3(0, size.y * 0.5 - 0.04, 0)
		var body := VASE_BLUE if i % 2 == 0 else PORCELAIN
		var trim := PORCELAIN if i % 2 == 0 else VASE_BLUE
		# Round belly half out of the straw, slim neck, flared gold lip and a painted band.
		FunLooks.part(b, FunLooks.sphere(0.12, 16), shiny(body), p + Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1, 0.9, 1))
		FunLooks.part(b, FunLooks.torus(0.11, 0.125), shiny(trim), p + Vector3(0, 0.07, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
		FunLooks.part(b, FunLooks.cyl(0.04, 0.055, 0.12, 14), shiny(body), p + Vector3(0, 0.19, 0))
		FunLooks.part(b, FunLooks.cyl(0.065, 0.04, 0.04, 14), shiny(trim), p + Vector3(0, 0.26, 0))
		FunLooks.part(b, FunLooks.torus(0.05, 0.07), shiny(GOLD), p + Vector3(0, 0.28, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	_stencil(b, "FRAGILE", size, 0.05, Color(0.85, 0.08, 0.06), 64)
	_stencil(b, "!! ANTIQUE VASES !!\nHANDLE WITH CARE", size, -0.17, Color(0.2, 0.12, 0.05), 22)
	_stencil(b, "FRAGILE", size, 0.05, Color(0.85, 0.08, 0.06), 64, PI / 2)
	_stencil(b, "FRAGILE", size, 0.05, Color(0.85, 0.08, 0.06), 64, -PI / 2)


## Wire coop: wooden frame, straw floor, chicken-wire sides, peaked roof and a drop-down door
## on the +Z face. The hens inside are their own merged node so the count can change.
static func _coop(b: Node3D, parts: Dictionary) -> void:
	var size: Vector3 = SPECS.chickens.size
	var h := size * 0.5
	var wood := m(WOOD.darkened(0.1))
	var wire := metal(Color(0.75, 0.77, 0.8))
	FunLooks.part(b, FunLooks.box(Vector3(size.x, 0.06, size.z)), wood, Vector3(0, -h.y + 0.03, 0))
	FunLooks.part(b, FunLooks.box(Vector3(size.x - 0.06, 0.03, size.z - 0.06)), m(Color(0.95, 0.82, 0.35)), Vector3(0, -h.y + 0.07, 0))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			FunLooks.part(b, FunLooks.box(Vector3(0.06, size.y - 0.12, 0.06)), wood, Vector3(sx * (h.x - 0.03), -0.06, sz * (h.z - 0.03)))
	for y: float in [-h.y + 0.08, h.y - 0.16]:
		for sz: float in [-1.0, 1.0]:
			FunLooks.part(b, FunLooks.box(Vector3(size.x, 0.05, 0.05)), wood, Vector3(0, y, sz * (h.z - 0.03)))
		for sx: float in [-1.0, 1.0]:
			FunLooks.part(b, FunLooks.box(Vector3(0.05, 0.05, size.z)), wood, Vector3(sx * (h.x - 0.03), y, 0))
	var bar_h := size.y - 0.28
	var bar_y := -0.04
	for i in 11:
		var x := -h.x + 0.06 + (size.x - 0.12) / 10.0 * i
		FunLooks.part(b, FunLooks.cyl(0.006, 0.006, bar_h, 6), wire, Vector3(x, bar_y, -h.z + 0.03))
	for i in 9:
		var z := -h.z + 0.06 + (size.z - 0.12) / 8.0 * i
		for sx: float in [-1.0, 1.0]:
			FunLooks.part(b, FunLooks.cyl(0.006, 0.006, bar_h, 6), wire, Vector3(sx * (h.x - 0.03), bar_y, z))
	# Peaked roof (two planks) with a ridge.
	for sx: float in [-1.0, 1.0]:
		FunLooks.part(b, FunLooks.box(Vector3(size.x * 0.56, 0.04, size.z + 0.08)), m(Color(0.75, 0.25, 0.18)),
			Vector3(sx * size.x * 0.24, h.y - 0.06, 0), Vector3(0, 0, -sx * 0.32))
	FunLooks.part(b, FunLooks.cyl(0.03, 0.03, size.z + 0.1), wood, Vector3(0, h.y + 0.02, 0), Vector3(PI / 2, 0, 0))
	# Door: hinged along its bottom edge on the +Z face.
	var door := Node3D.new()
	door.name = "Door"
	door.position = Vector3(0, -h.y + 0.1, h.z - 0.02)
	b.add_child(door)
	var dh := size.y - 0.3
	for sx: float in [-1.0, 1.0]:
		FunLooks.part(door, FunLooks.box(Vector3(0.04, dh, 0.04)), wood, Vector3(sx * (h.x - 0.06), dh * 0.5, 0))
	for y: float in [0.02, dh - 0.02]:
		FunLooks.part(door, FunLooks.box(Vector3(size.x - 0.1, 0.04, 0.04)), wood, Vector3(0, y, 0))
	for i in 9:
		FunLooks.part(door, FunLooks.cyl(0.006, 0.006, dh, 6), wire, Vector3(-h.x + 0.12 + (size.x - 0.24) / 8.0 * i, dh * 0.5, 0))
	FunLooks.part(door, FunLooks.box(Vector3(0.08, 0.05, 0.03)), metal(STEEL), Vector3(0, dh - 0.03, 0.03))
	parts.door = door
	var hens := Node3D.new()
	hens.name = "Hens"
	b.add_child(hens)
	parts.hens = hens
	_stencil(b, "LIVE POULTRY\nTHIS SIDE UP", size, -h.y + 0.08, Color(0.25, 0.15, 0.05), 22, PI / 2)


## Rebuilds the visible hens in a coop (`count` sitting in the straw), merged per count.
static func set_hens(hens: Node3D, count: int) -> void:
	for c in hens.get_children():
		hens.remove_child(c)
		c.free()
	var size: Vector3 = SPECS.chickens.size
	var spots := [Vector3(-0.22, 0, -0.15), Vector3(0.2, 0, -0.18), Vector3(0.0, 0, 0.1), Vector3(-0.25, 0, 0.18),
		Vector3(0.24, 0, 0.16)]
	for i in mini(count, spots.size()):
		var hen := Node3D.new()
		hen.position = spots[i] + Vector3(0, -size.y * 0.5 + 0.2, 0)
		hen.rotation.y = i * 1.9
		hens.add_child(hen)
		hen_body(hen, i % 3 == 2)
		for sx: float in [-1.0, 1.0]:
			FunLooks.part(hen, FunLooks.sphere(0.5, 10), m(HEN.darkened(0.06) if i % 3 != 2 else HEN_BROWN.darkened(0.1)),
				Vector3(sx * 0.1, 0.0, 0.02), Vector3.ZERO, Vector3(0.05, 0.12, 0.2))
	PropLooks.merge_static(hens, [], "cargo/hens/%d" % count)


## Hen body with head, comb, beak, wattle, googly eyes, tail and legs (no wings). Faces -Z;
## its belly bottom sits ~0.08 below the origin, feet at about -0.17.
static func hen_body(b: Node3D, brown := false) -> void:
	var feathers := HEN_BROWN if brown else HEN
	FunLooks.part(b, FunLooks.sphere(0.5, 14), m(feathers), Vector3(0, 0.0, 0.02), Vector3.ZERO, Vector3(0.2, 0.18, 0.26))
	FunLooks.part(b, FunLooks.sphere(0.5, 12), m(feathers.darkened(0.05)), Vector3(0, 0.07, 0.15), Vector3(0.6, 0, 0), Vector3(0.12, 0.16, 0.08))
	FunLooks.part(b, FunLooks.sphere(0.075, 12), m(feathers), Vector3(0, 0.15, -0.1))
	FunLooks.part(b, FunLooks.cyl(0.0, 0.03, 0.07, 8), m(BEAK), Vector3(0, 0.14, -0.19), Vector3(-PI / 2, 0, 0))
	for i in 3:
		FunLooks.part(b, FunLooks.sphere(0.022, 8), m(COMB), Vector3(0, 0.23, -0.14 + i * 0.03))
	FunLooks.part(b, FunLooks.sphere(0.02, 8), m(COMB), Vector3(0, 0.1, -0.16), Vector3.ZERO, Vector3(0.8, 1.4, 0.8))
	for sx: float in [-1.0, 1.0]:
		FunLooks.part(b, FunLooks.sphere(0.03, 10), m(Color.WHITE, 0.3), Vector3(sx * 0.045, 0.18, -0.15))
		FunLooks.part(b, FunLooks.sphere(0.014, 8), m(INK, 0.3), Vector3(sx * 0.052, 0.18, -0.175))
		FunLooks.part(b, FunLooks.cyl(0.008, 0.008, 0.1, 6), m(BEAK), Vector3(sx * 0.04, -0.12, 0.02))
		FunLooks.part(b, FunLooks.box(Vector3(0.05, 0.01, 0.06)), m(BEAK), Vector3(sx * 0.04, -0.17, -0.0))


## One flappable wing for an escaped chicken (pivot at the shoulder, wing hangs along -Y/+Z).
static func hen_wing(parent: Node3D, sx: float, brown := false) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(sx * 0.09, 0.05, 0.0)
	parent.add_child(pivot)
	FunLooks.part(pivot, FunLooks.sphere(0.5, 10), m((HEN_BROWN if brown else HEN).darkened(0.08)), Vector3(sx * 0.02, -0.04, 0.04),
		Vector3.ZERO, Vector3(0.05, 0.12, 0.2))
	return pivot


## Heavy dark crate with air holes, a peep slot with glowing eyes, padlock and warnings.
static func _croc_crate(b: Node3D, parts: Dictionary) -> void:
	var size: Vector3 = SPECS.crocodile.size
	var wood_c := Color(0.45, 0.36, 0.22)
	_crate_shell(b, size, wood_c, 5)
	var h := size * 0.5
	for side: float in [-1.0, 1.0]:
		for i in 4:
			for j in 2:
				FunLooks.part(b, FunLooks.cyl(0.025, 0.025, 0.02, 10), m(INK), Vector3(side * (h.x + 0.005), 0.1 + j * 0.14, -0.33 + i * 0.22),
					Vector3(0, 0, PI / 2))
	FunLooks.part(b, FunLooks.box(Vector3(0.5, 0.08, 0.02)), m(INK), Vector3(0, 0.2, h.z + 0.01))
	var eyes := Node3D.new()
	eyes.name = "Eyes"
	eyes.position = Vector3(0, 0.2, h.z + 0.015)
	b.add_child(eyes)
	for sx: float in [-1.0, 1.0]:
		FunLooks.part(eyes, FunLooks.sphere(0.028, 10), FunLooks.mat(Color(1.0, 0.85, 0.1), 0.4, 0.0, 2.5), Vector3(sx * 0.09, 0, 0),
			Vector3.ZERO, Vector3(1, 0.7, 0.5))
	parts.eyes = eyes
	FunLooks.part(b, FunLooks.box(Vector3(0.12, 0.14, 0.05)), metal(Color(0.85, 0.7, 0.25)), Vector3(0, -0.12, h.z + 0.03))
	FunLooks.part(b, FunLooks.torus(0.03, 0.045), metal(STEEL), Vector3(0, -0.04, h.z + 0.03), Vector3(PI / 2, 0, 0))
	parts.lid = _lid(b, size, wood_c)
	var hole := FunLooks.part(b, FunLooks.box(Vector3(size.x - 0.12, 0.01, size.z - 0.12)), m(Color(0.08, 0.05, 0.03)), Vector3(0, h.y - 0.02, 0))
	hole.name = "Hole"
	parts.hole = hole
	_stencil(b, "LIVE REPTILE", size, 0.05 - 0.27, Color(0.95, 0.85, 0.2), 36)
	_stencil(b, "DO NOT OPEN\nDO NOT FEED\nDO NOT MAKE EYE CONTACT", size, -0.21, Color(0.95, 0.85, 0.2), 16, PI / 2)
	_stencil(b, "BITES", size, 0.15, Color(0.9, 0.1, 0.08), 70, -PI / 2)


## Three red drums on a pallet with yellow/black hazard bands, caps and a warning plate.
static func _barrels(b: Node3D) -> void:
	_pallet(b, 0.95, 0.95, -0.42)
	var spots := [Vector3(-0.22, 0, -0.2), Vector3(0.23, 0, -0.18), Vector3(0.0, 0, 0.22)]
	for i in spots.size():
		var base: Vector3 = spots[i] + Vector3(0, -0.42 + 0.44, 0)
		var col := BARREL if i != 1 else Color(0.95, 0.45, 0.1)
		FunLooks.part(b, FunLooks.cyl(0.2, 0.2, 0.84, 20), shiny(col), base)
		for y: float in [-0.3, 0.3]:
			FunLooks.part(b, FunLooks.torus(0.19, 0.215), shiny(col.darkened(0.25)), base + Vector3(0, y, 0))
		FunLooks.part(b, FunLooks.cyl(0.204, 0.204, 0.16, 20), shiny(HAZARD), base + Vector3(0, 0.08, 0))
		for k in 10:
			var a := k * TAU / 10.0
			FunLooks.part(b, FunLooks.box(Vector3(0.05, 0.2, 0.012)), shiny(INK), base + Vector3(sin(a) * 0.206, 0.08, cos(a) * 0.206),
				Vector3(0, a, 0.7))
		FunLooks.part(b, FunLooks.cyl(0.19, 0.19, 0.02, 20), metal(STEEL), base + Vector3(0, 0.425, 0))
		FunLooks.part(b, FunLooks.cyl(0.035, 0.035, 0.03, 10), metal(Color(0.4, 0.4, 0.42)), base + Vector3(0.09, 0.44, 0.05))
	# Warning diamond on the front drum.
	FunLooks.part(b, FunLooks.box(Vector3(0.2, 0.2, 0.01)), m(Color(1.0, 0.5, 0.08)), Vector3(0, 0.25, 0.42), Vector3(0, 0, PI / 4))
	FunLooks.label(b, "BOOM CO.", Vector3(0, -0.05, 0.43), 28, Color(1, 1, 0.85), Vector3.ZERO, 0.0028)
	FunLooks.label(b, "!", Vector3(0, 0.25, 0.43), 64, INK, Vector3.ZERO, 0.0028).outline_size = 0


## Dark crate with steel corners whose seams leak purple light; a "?" on every side.
static func _mystery(b: Node3D, parts: Dictionary) -> void:
	var size: Vector3 = SPECS.mystery.size
	var h := size * 0.5
	var glow := Node3D.new()
	glow.name = "Glow"
	b.add_child(glow)
	FunLooks.part(glow, FunLooks.box(size - Vector3(0.05, 0.05, 0.05)), FunLooks.mat(MYSTERY_GLOW, 0.4, 0.0, 3.0), Vector3.ZERO)
	parts.glow = glow
	var wood := m(MYSTERY)
	var band := 3
	for side in 6:
		var n: Vector3 = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD][side]
		for i in band:
			var off := -0.5 + (i + 0.5) / band
			var pos := n * (h.x - 0.005)
			var sz := Vector3.ONE * (size.x / band - 0.04)
			if absf(n.x) > 0.5:
				pos += Vector3(0, 0, off * size.z)
				sz = Vector3(0.03, size.y - 0.08, size.z / band - 0.035)
			elif absf(n.y) > 0.5:
				pos += Vector3(off * size.x, 0, 0)
				sz = Vector3(size.x / band - 0.035, 0.03, size.z - 0.08)
			else:
				pos += Vector3(0, off * size.y, 0)
				sz = Vector3(size.x - 0.08, size.y / band - 0.035, 0.03)
			FunLooks.part(b, FunLooks.box(sz), wood, pos)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				FunLooks.part(b, FunLooks.sphere(0.07, 10), metal(Color(0.55, 0.5, 0.65)), Vector3(sx * h.x, sy * h.y, sz * h.z))
	for yaw: float in [0.0, PI / 2, PI, -PI / 2]:
		var l := FunLooks.label(b, "?", Vector3(sin(yaw), 0, cos(yaw)) * (h.x + 0.025), 120, Color(0.95, 0.8, 1.0),
			Vector3(0, yaw, 0), 0.003)
		l.outline_modulate = Color(0.3, 0.0, 0.5)
	var light := OmniLight3D.new()
	light.light_color = MYSTERY_GLOW
	light.light_energy = 0.8
	light.omni_range = 2.2
	light.position = Vector3(0, h.y + 0.2, 0)
	b.add_child(light)
	parts.light = light


# --- Creatures -----------------------------------------------------------------------------

## Escaped chicken: body plus two wing pivots (parts.wing_l / wing_r) for flapping.
static func chicken(vis: Node3D, parts: Dictionary, brown: bool) -> void:
	hen_body(vis, brown)
	parts.wing_l = hen_wing(vis, -1.0, brown)
	parts.wing_r = hen_wing(vis, 1.0, brown)
	finish(vis, parts, "cargo/chicken/%s" % brown)


## Cartoon crocodile facing -Z: lumpy body, googly eyes on bumps, a toothy jaw that snaps
## (parts.jaw), a wagging tail (parts.tail) and four stubby legs (parts.legs, waddle).
static func crocodile(vis: Node3D, parts: Dictionary) -> void:
	var skin := m(CROC, 0.55)
	var dark := m(CROC_DARK, 0.55)
	var belly := m(CROC_BELLY)
	var tooth := m(Color(0.98, 0.98, 0.94), 0.3)
	FunLooks.part(vis, FunLooks.sphere(0.5, 18), skin, Vector3(0, 0.0, 0.0), Vector3.ZERO, Vector3(0.5, 0.3, 1.05))
	FunLooks.part(vis, FunLooks.sphere(0.5, 16), belly, Vector3(0, -0.04, 0.0), Vector3.ZERO, Vector3(0.44, 0.24, 0.95))
	for i in 7:
		var z := -0.36 + i * 0.12
		for sx: float in [-1.0, 1.0]:
			FunLooks.part(vis, FunLooks.cyl(0.0, 0.04, 0.07, 8), dark, Vector3(sx * 0.07, 0.15 - absf(z) * 0.06, z))
	# Upper head (static) with nostrils and eye bumps.
	FunLooks.part(vis, FunLooks.sphere(0.5, 16), skin, Vector3(0, 0.03, -0.62), Vector3.ZERO, Vector3(0.34, 0.16, 0.6))
	for sx: float in [-1.0, 1.0]:
		FunLooks.part(vis, FunLooks.sphere(0.07, 12), skin, Vector3(sx * 0.08, 0.1, -0.48))
		FunLooks.part(vis, FunLooks.sphere(0.055, 12), m(Color.WHITE, 0.3), Vector3(sx * 0.085, 0.14, -0.51))
		FunLooks.part(vis, FunLooks.sphere(0.025, 10), m(INK, 0.3), Vector3(sx * 0.09, 0.15, -0.555))
		FunLooks.part(vis, FunLooks.sphere(0.02, 8), dark, Vector3(sx * 0.04, 0.09, -0.9))
		for i in 6:
			FunLooks.part(vis, FunLooks.cyl(0.0, 0.016, 0.05, 6), tooth, Vector3(sx * 0.13, -0.04, -0.6 - i * 0.055),
				Vector3(PI, 0, 0))
	# Lower jaw: hinged at the back of the head.
	var jaw := Node3D.new()
	jaw.name = "Jaw"
	jaw.position = Vector3(0, -0.03, -0.42)
	vis.add_child(jaw)
	FunLooks.part(jaw, FunLooks.sphere(0.5, 14), skin, Vector3(0, -0.04, -0.22), Vector3.ZERO, Vector3(0.3, 0.09, 0.52))
	FunLooks.part(jaw, FunLooks.box(Vector3(0.2, 0.02, 0.38)), m(Color(0.95, 0.45, 0.5)), Vector3(0, -0.005, -0.2))
	for sx: float in [-1.0, 1.0]:
		for i in 5:
			FunLooks.part(jaw, FunLooks.cyl(0.0, 0.015, 0.045, 6), tooth, Vector3(sx * 0.11, 0.01, -0.1 - i * 0.06))
	parts.jaw = jaw
	# Tail: tapering segments from a pivot at the rump.
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0, -0.02, 0.45)
	vis.add_child(tail)
	for i in 4:
		var r := 0.13 - i * 0.028
		FunLooks.part(tail, FunLooks.sphere(0.5, 12), skin, Vector3(0, -i * 0.01, 0.14 + i * 0.2), Vector3.ZERO, Vector3(r * 2.0, r * 1.4, 0.32))
		FunLooks.part(tail, FunLooks.cyl(0.0, 0.03, 0.06, 6), dark, Vector3(0, r * 0.7, 0.14 + i * 0.2))
	parts.tail = tail
	var legs := Node3D.new()
	legs.name = "Legs"
	vis.add_child(legs)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(sx * 0.24, -0.1, sz * 0.28)
			FunLooks.part(legs, FunLooks.capsule(0.055, 0.2), skin, p, Vector3(0, 0, sx * 0.9))
			FunLooks.part(legs, FunLooks.sphere(0.5, 10), dark, p + Vector3(sx * 0.08, -0.06, -0.03), Vector3.ZERO, Vector3(0.12, 0.05, 0.14))
	parts.legs = legs
	finish(vis, parts, "cargo/croc")
