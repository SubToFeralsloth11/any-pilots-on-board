extends RefCounted
## Chunky cartoon models of the four cabin-service items (meal tray, drink, coffee mug,
## blanket), shared by the grabbable items, the passengers' request bubbles and the snack in
## a passenger's hand. Origin = item centre; the top faces +Y.

const PropLooks := preload("res://scripts/props/prop_looks.gd")

const KINDS := ["meal", "drink", "coffee", "blanket"]
const NAMES := {"meal": "meal tray", "drink": "orange juice", "coffee": "coffee", "blanket": "blanket"}
const TRAY := Color(0.86, 0.87, 0.9)
const FOIL := Color(0.8, 0.82, 0.86)
const JUICE := Color(1.0, 0.6, 0.1)
const CUP := Color(0.96, 0.97, 1.0)
const COFFEE := Color(0.3, 0.17, 0.08)
const MUG := Color(0.95, 0.3, 0.25)
const BLANKET := Color(0.2, 0.42, 0.85)
const BLANKET_STRIPE := Color(0.95, 0.8, 0.25)


## Builds the item under `root` and merges it into one cached mesh (one draw call per finish).
static func build(root: Node3D, kind: String) -> void:
	build_parts(root, kind)
	PropLooks.merge_static(root, [], "service/" + kind)


## Builds the item's separate parts under `root` (for callers that merge a bigger model).
static func build_parts(root: Node3D, kind: String) -> void:
	match kind:
		"meal":
			_meal(root)
		"drink":
			_drink(root)
		"coffee":
			_coffee(root)
		"blanket":
			_blanket(root)


## Collision shape matching build(kind).
static func shape(kind: String) -> Shape3D:
	match kind:
		"meal":
			var b := BoxShape3D.new()
			b.size = Vector3(0.36, 0.08, 0.26)
			return b
		"blanket":
			var b := BoxShape3D.new()
			b.size = Vector3(0.3, 0.1, 0.22)
			return b
	var c := CylinderShape3D.new()
	c.radius = 0.05
	c.height = 0.13 if kind == "drink" else 0.1
	return c


static func mass(kind: String) -> float:
	return {"meal": 0.7, "drink": 0.3, "coffee": 0.35, "blanket": 0.5}.get(kind, 0.4)


## Tray with a foil-lidded hot dish, a salad bowl, a bread roll, a pudding cup and cutlery.
static func _meal(r: Node3D) -> void:
	FunLooks.rounded_box(r, Vector3(0.36, 0.025, 0.26), 0.012, FunLooks.mat(TRAY, 0.5), Vector3(0, -0.025, 0))
	FunLooks.part(r, FunLooks.box(Vector3(0.36, 0.03, 0.012)), FunLooks.mat(TRAY.darkened(0.15), 0.5), Vector3(0, -0.01, 0.125))
	FunLooks.part(r, FunLooks.box(Vector3(0.36, 0.03, 0.012)), FunLooks.mat(TRAY.darkened(0.15), 0.5), Vector3(0, -0.01, -0.125))
	# Hot dish under a puffy foil lid.
	FunLooks.rounded_box(r, Vector3(0.17, 0.045, 0.12), 0.02, FunLooks.metal(FOIL), Vector3(-0.07, 0.012, 0.04))
	FunLooks.part(r, FunLooks.sphere(0.5, 12), FunLooks.metal(FOIL.lightened(0.1)), Vector3(-0.07, 0.035, 0.04),
		Vector3.ZERO, Vector3(0.15, 0.03, 0.1))
	# Salad bowl with green and red bits.
	FunLooks.part(r, FunLooks.cyl(0.045, 0.032, 0.035, 14), FunLooks.mat(CUP, 0.3), Vector3(0.1, 0.005, 0.05))
	for i in 5:
		var a := i * 1.3
		var c := Color(0.35, 0.8, 0.3) if i % 2 == 0 else Color(0.95, 0.25, 0.2)
		FunLooks.part(r, FunLooks.sphere(0.017, 8), FunLooks.mat(c, 0.6), Vector3(0.1 + cos(a) * 0.022, 0.024, 0.05 + sin(a) * 0.022))
	# Bread roll and a pudding cup.
	FunLooks.part(r, FunLooks.sphere(0.5, 12), FunLooks.mat(Color(0.85, 0.6, 0.3), 0.7), Vector3(-0.08, 0.01, -0.07),
		Vector3.ZERO, Vector3(0.09, 0.05, 0.06))
	FunLooks.part(r, FunLooks.cyl(0.03, 0.025, 0.04, 12), FunLooks.mat(Color(0.98, 0.85, 0.9), 0.4), Vector3(0.06, 0.008, -0.07))
	FunLooks.part(r, FunLooks.sphere(0.024, 10), FunLooks.mat(Color(0.95, 0.25, 0.35), 0.3), Vector3(0.06, 0.03, -0.07))
	# Plastic cutlery.
	for dx: float in [0.13, 0.15]:
		FunLooks.part(r, FunLooks.box(Vector3(0.008, 0.006, 0.15)), FunLooks.mat(CUP, 0.4), Vector3(dx, -0.008, -0.04))


## Paper cup of orange juice with a lid and a striped straw.
static func _drink(r: Node3D) -> void:
	FunLooks.part(r, FunLooks.cyl(0.046, 0.034, 0.12, 16), FunLooks.mat(CUP, 0.45), Vector3.ZERO)
	FunLooks.part(r, FunLooks.cyl(0.047, 0.044, 0.04, 16), FunLooks.mat(JUICE, 0.5), Vector3(0, 0.0, 0))
	FunLooks.part(r, FunLooks.cyl(0.049, 0.049, 0.012, 16), FunLooks.mat(Color(0.95, 0.95, 0.97), 0.3), Vector3(0, 0.062, 0))
	FunLooks.part(r, FunLooks.cyl(0.007, 0.007, 0.12, 8), FunLooks.mat(Color(0.95, 0.2, 0.25), 0.4), Vector3(0.012, 0.11, 0),
		Vector3(0, 0, -0.25))
	FunLooks.part(r, FunLooks.sphere(0.5, 10), FunLooks.mat(JUICE.lightened(0.2), 0.5), Vector3(-0.02, 0.0, -0.047),
		Vector3.ZERO, Vector3(0.045, 0.045, 0.01))


## Chunky red mug of steaming coffee.
static func _coffee(r: Node3D) -> void:
	FunLooks.part(r, FunLooks.cyl(0.046, 0.042, 0.1, 16), FunLooks.mat(MUG, 0.3), Vector3.ZERO)
	FunLooks.part(r, FunLooks.cyl(0.04, 0.04, 0.01, 16), FunLooks.mat(COFFEE, 0.2), Vector3(0, 0.046, 0))
	FunLooks.part(r, FunLooks.torus(0.018, 0.034), FunLooks.mat(MUG, 0.3), Vector3(0.05, 0.0, 0), Vector3(PI / 2, 0, 0))
	FunLooks.part(r, FunLooks.cyl(0.047, 0.047, 0.016, 16), FunLooks.mat(Color(1, 1, 1), 0.3), Vector3(0, 0.02, 0))
	for i in 3:
		FunLooks.part(r, FunLooks.sphere(0.016 - i * 0.003, 8), FunLooks.mat(Color(1, 1, 1, 1), 0.9),
			Vector3(sin(i * 2.0) * 0.012, 0.07 + i * 0.03, 0))


## Folded fleece blanket with a stripe and a tag.
static func _blanket(r: Node3D) -> void:
	FunLooks.rounded_box(r, Vector3(0.3, 0.09, 0.22), 0.035, FunLooks.mat(BLANKET, 0.9))
	FunLooks.part(r, FunLooks.box(Vector3(0.302, 0.03, 0.04)), FunLooks.mat(BLANKET_STRIPE, 0.9), Vector3(0, 0, 0.06))
	FunLooks.part(r, FunLooks.box(Vector3(0.302, 0.03, 0.02)), FunLooks.mat(BLANKET_STRIPE, 0.9), Vector3(0, 0, -0.06))
	FunLooks.part(r, FunLooks.capsule(0.03, 0.3), FunLooks.mat(BLANKET.lightened(0.15), 0.9), Vector3(0, 0.028, -0.095),
		Vector3(0, 0, PI / 2))
	FunLooks.part(r, FunLooks.box(Vector3(0.05, 0.004, 0.03)), FunLooks.mat(Color(1, 1, 1), 0.6), Vector3(0.1, 0.047, 0.07))
