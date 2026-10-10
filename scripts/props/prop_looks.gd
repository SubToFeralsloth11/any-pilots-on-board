extends RefCounted
## Data and cartoon visuals for every Props kind: physics specs, names, prompts, use hints,
## and the builders that add meshes and collision shapes to a body. Everything is built from
## rounded primitives (capsules, spheres, tapered cylinders, tori, prisms) with shared meshes
## and materials so dozens of props stay cheap to draw.

const Fx := preload("res://scripts/props/fx.gd")

## Physics/handling per kind. Friction ~0.3 lets a ~20° bank start things sliding.
const SPECS := {
	"suitcase": {"name": "suitcase", "mass": 8.0, "friction": 0.3, "grab": true},
	"bag": {"name": "duffel bag", "mass": 4.0, "friction": 0.32, "grab": true},
	"pillow": {"name": "neck pillow", "mass": 0.6, "friction": 0.34, "grab": true},
	"can": {"name": "soda can", "mass": 0.35, "friction": 0.28, "grab": true},
	"laptop": {"name": "laptop", "mass": 2.0, "friction": 0.26, "grab": true},
	"cart": {"name": "drinks cart", "mass": 25.0, "friction": 0.03, "grab": true},
	"crate": {"name": "crate", "mass": 60.0, "friction": 0.45, "grab": false},
	"debris": {"name": "broken bits", "mass": 0.3, "friction": 0.5, "grab": false},
	"peel": {"name": "banana peel", "mass": 0.1, "friction": 0.6, "grab": true},
	"extinguisher": {"name": "fire extinguisher", "mass": 3.0, "friction": 0.3, "grab": true},
	"duct_tape": {"name": "duct tape", "mass": 0.4, "friction": 0.4, "grab": true},
	"wrench": {"name": "wrench", "mass": 1.5, "friction": 0.3, "grab": true},
	"banana": {"name": "banana", "mass": 0.2, "friction": 0.4, "grab": true},
	"rubber_chicken": {"name": "rubber chicken", "mass": 0.4, "friction": 0.5, "grab": true},
	"megaphone": {"name": "megaphone", "mass": 1.0, "friction": 0.3, "grab": true},
	"parachute": {"name": "parachute", "mass": 3.0, "friction": 0.4, "grab": true},
	"snack": {"name": "bag of snacks", "mass": 0.2, "friction": 0.4, "grab": true},
}

## Kinds that shatter into debris on a hard hit.
const BREAKABLE := ["suitcase", "laptop", "can"]

## Toasted to whoever picks the item up: what [RMB] does.
const HINTS := {
	"extinguisher": "Spray [RMB] near a burning engine. Also works as a jetpack, apparently.",
	"duct_tape": "Patch a broken window [RMB] (stand next to it). 3 strips left.",
	"wrench": "Whack an engine to fix it [RMB]. Throw it [LMB] to smash stuff.",
	"banana": "Eat it [RMB]. Keep the peel.",
	"peel": "Drop it [E] where someone will step on it. Then wait.",
	"rubber_chicken": "Squeak [RMB]. That's it. That's the item.",
	"megaphone": "Make an important announcement [RMB].",
	"parachute": "Hold it in case you fall out. Or jump. Your call.",
	"snack": "Eat it [RMB].",
}

const ITEMS := ["extinguisher", "duct_tape", "wrench", "banana", "rubber_chicken", "megaphone",
	"parachute", "snack"]

const LUGGAGE_COLORS := [Color(0.9, 0.25, 0.25), Color(0.2, 0.55, 0.95), Color(0.25, 0.75, 0.35),
	Color(0.95, 0.75, 0.15), Color(0.6, 0.3, 0.8), Color(0.95, 0.5, 0.75), Color(0.2, 0.2, 0.24),
	Color(0.95, 0.55, 0.15), Color(0.3, 0.8, 0.8)]
const PILLOW_COLORS := [Color(0.75, 0.85, 1.0), Color(1.0, 0.75, 0.8), Color(0.8, 1.0, 0.75),
	Color(1.0, 0.92, 0.6), Color(0.85, 0.75, 1.0)]
const CAN_BRANDS := [["FIZZ", Color(0.85, 0.1, 0.12)], ["LIME-O", Color(0.15, 0.65, 0.2)],
	["ORNJ", Color(0.95, 0.55, 0.1)], ["BLU", Color(0.2, 0.35, 0.85)], ["GRAPE?", Color(0.55, 0.2, 0.7)]]
const CLOTHES := [Color(1, 0.5, 0.75), Color(0.95, 0.95, 0.95), Color(0.6, 1, 0.3), Color(0.3, 0.9, 1),
	Color(1, 0.9, 0.2), Color(0.9, 0.2, 0.9), Color(1, 0.4, 0.2)]
const STICKERS := [Color(1, 0.85, 0.1), Color(0.2, 0.9, 0.5), Color(1, 0.3, 0.5), Color(0.3, 0.6, 1),
	Color(1, 1, 1)]
const CRATE_LABELS := ["FRAGILE-ISH", "NOT SNAKES", "GRANDMA'S\nSTUFF", "MISC.", "LIVE EELS\n(PROBABLY)",
	"DO NOT\nOPEN", "SPARE\nPLANE PARTS", "PROPERTY OF\nNOBODY", "100% LEGAL", "SURPRISE!"]
const SNACKS := [["CRUNCHOS", Color(1, 0.55, 0.1)], ["PRETZLZ", Color(0.2, 0.45, 0.95)],
	["PEANUTS*", Color(0.9, 0.2, 0.2)], ["MYSTERY\nNUTS", Color(0.6, 0.25, 0.85)]]
const LAPTOP_FILES := ["Q3_FINAL_v7\n(real).xls", "wedding_speech\nDRAFT 14.doc", "how to fly\na plane - Search",
	"cat_pics\n(4,812)", "screenplay.txt\nFADE IN:"]
const WOOD := Color(0.78, 0.56, 0.32)
const STEEL := Color(0.78, 0.8, 0.84)
const DARK := Color(0.12, 0.12, 0.14)

static var _meshes := {}


static func display_name(kind: String) -> String:
	return SPECS[kind].name if SPECS.has(kind) else kind


## [E] prompt shown while aiming at an object of this kind.
static func prompt(kind: String) -> String:
	match kind:
		"cart":
			return "Grab the drinks cart [E]  Shove [LMB]"
		"debris":
			return "Some broken bits"
		"crate":
			return "Search the crate [E]"
	return "Pick up the %s [E]" % display_name(kind)


## Colours, sizes and shapes of the 3-5 debris pieces a broken prop leaves behind.
static func debris_for(kind: String, extra: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var base: Color = extra.get("color", LUGGAGE_COLORS[0])
	for i in randi_range(3, 5):
		match kind:
			"suitcase":
				if i == 0:
					out.append({"color": base, "size": Vector3(0.32, 0.05, 0.22), "shape": "shard"})
				else:
					out.append({"color": CLOTHES.pick_random(), "size": Vector3(0.24, 0.04, 0.2), "shape": "cloth"})
			"laptop":
				var c: Color = [STEEL, Color(0.1, 0.55, 0.2), DARK, Color(0.2, 0.3, 1.0)].pick_random()
				out.append({"color": c, "size": Vector3(0.12, 0.02, 0.1), "shape": "shard"})
			"can":
				var brand: Array = CAN_BRANDS[int(extra.get("v", 0)) % CAN_BRANDS.size()]
				out.append({"color": brand[1] if i % 2 == 0 else STEEL, "size": Vector3(0.05, 0.04, 0.05),
					"shape": "tin"})
			_:
				out.append({"color": Color(0.55, 0.55, 0.55), "size": Vector3(0.08, 0.05, 0.08), "shape": "shard"})
	return out


## Fills missing cosmetic choices (colour, variant, crate label) from `key` (the net_id), so a
## kind spawned with an empty extra looks identical on every peer.
static func fill_defaults(kind: String, extra: Dictionary, key: int) -> void:
	match kind:
		"suitcase", "bag":
			if not extra.has("color"):
				extra.color = LUGGAGE_COLORS[key % LUGGAGE_COLORS.size()]
		"pillow":
			if not extra.has("color"):
				extra.color = PILLOW_COLORS[key % PILLOW_COLORS.size()]
		"crate":
			if not extra.has("label"):
				extra.label = CRATE_LABELS[key % CRATE_LABELS.size()]
			if not extra.has("tint"):
				extra.tint = float(key % 4) * 0.07
		"can", "laptop", "snack":
			if not extra.has("v"):
				extra.v = key


## Adds meshes and collision shapes for `kind` to `body`. Named nodes go into `parts`.
## Expects `extra` to have been through fill_defaults().
static func build(body: RigidBody3D, kind: String, extra: Dictionary, parts: Dictionary) -> void:
	match kind:
		"suitcase":
			_suitcase(body, extra.color)
		"bag":
			_bag(body, extra.color)
		"pillow":
			_pillow(body, extra.color)
		"can":
			_can(body, int(extra.v))
		"laptop":
			_laptop(body, extra, parts)
		"cart":
			_cart(body)
		"crate":
			_crate(body, extra, parts)
		"debris":
			_debris(body, extra)
		"extinguisher":
			_extinguisher(body, parts)
		"duct_tape":
			_duct_tape(body)
		"wrench":
			_wrench(body)
		"banana":
			parts.banana = Node3D.new()
			parts.peel = Node3D.new()
			body.add_child(parts.banana)
			body.add_child(parts.peel)
			_banana(parts.banana)
			_peel(parts.peel)
			parts.peel.visible = false
			_shape(body, Vector3(0.28, 0.08, 0.08))
		"peel":
			_peel(body)
			_shape(body, Vector3(0.26, 0.03, 0.26))
		"rubber_chicken":
			_chicken(body, parts)
		"megaphone":
			_megaphone(body)
		"parachute":
			_parachute(body)
		"snack":
			_snack(body, int(extra.v))


## Swaps a banana's visuals to its peel (all peers).
static func show_peel(parts: Dictionary) -> void:
	(parts.banana as Node3D).visible = false
	(parts.peel as Node3D).visible = true


## Laptop crash screen.
static func show_bsod(parts: Dictionary) -> void:
	(parts.screen as MeshInstance3D).material_override = Fx.mat(Color(0.1, 0.3, 0.95), 1.2)
	var l: Label3D = parts.screen_label
	l.text = ":(\nYour laptop ran into\na plane problem."
	l.modulate = Color.WHITE


## Crate after it has been searched: lid gone, dark inside showing.
static func show_open_crate(parts: Dictionary) -> void:
	(parts.lid as Node3D).visible = false
	(parts.hole as Node3D).visible = true


# --- Kinds -----------------------------------------------------------------------------

static func _suitcase(b: RigidBody3D, c: Color) -> void:
	_rbox(b, Vector3(0.62, 0.24, 0.42), 0.06, Vector3.ZERO, c)
	_box(b, Vector3(0.625, 0.022, 0.425), Vector3.ZERO, c.darkened(0.45))   # Zip seam.
	_box(b, Vector3(0.04, 0.03, 0.02), Vector3(0.12, 0.0, 0.215), Color(0.85, 0.85, 0.8), Vector3.ZERO, 0.0, 0.8)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_sphere(b, 0.04, Vector3(sx * 0.28, -0.085, sz * 0.18), DARK)
	# Carry handle on the long side, half sunk into the shell.
	_torus(b, 0.06, 0.085, Vector3(0, 0, 0.21), DARK, Vector3(PI / 2, 0, 0), Vector3(1, 0.55, 1))
	# Luggage tag and stickers.
	_box(b, Vector3(0.07, 0.1, 0.006), Vector3(-0.07, -0.05, 0.25), Color(1, 0.95, 0.8))
	_cyl(b, 0.004, 0.004, 0.06, Vector3(-0.06, 0.01, 0.235), DARK)
	for i in 3:
		var s: Color = STICKERS[(i + int(c.r * 10.0)) % STICKERS.size()]
		_cyl(b, 0.055 - i * 0.008, 0.055 - i * 0.008, 0.004, Vector3(-0.18 + i * 0.16, 0.121, -0.05 + (i % 2) * 0.1), s)
	_label(b, "HAWAII?", Vector3(0.18, 0.124, -0.1), 0.0, 18, DARK, -PI / 2)
	_shape(b, Vector3(0.62, 0.24, 0.42))


static func _bag(b: RigidBody3D, c: Color) -> void:
	_capsule(b, 0.14, 0.58, Vector3.ZERO, c, Vector3(0, 0, PI / 2))
	for sx in [-1, 1]:
		_cyl(b, 0.13, 0.13, 0.02, Vector3(sx * 0.2, 0, 0), c.darkened(0.35), Vector3(0, 0, PI / 2))
		_torus(b, 0.135, 0.155, Vector3(sx * 0.1, 0, 0), DARK, Vector3(0, 0, PI / 2))
	_torus(b, 0.11, 0.13, Vector3(0, 0.13, 0), DARK, Vector3(PI / 2, 0, 0), Vector3(1, 0.8, 1))
	_box(b, Vector3(0.36, 0.012, 0.02), Vector3(0, 0.14, 0.03), c.lightened(0.4))
	_sphere(b, 0.5, Vector3(0, -0.01, 0.12), c.lightened(0.15), Vector3(0.22, 0.14, 0.06))
	_box(b, Vector3(0.12, 0.008, 0.01), Vector3(0, 0.05, 0.15), DARK)
	_shape(b, Vector3(0.58, 0.28, 0.28))


static func _pillow(b: RigidBody3D, c: Color) -> void:
	# Plump travel neck pillow with a snap strap and a sleepy logo.
	_torus(b, 0.06, 0.2, Vector3.ZERO, c, Vector3.ZERO, Vector3(1, 1.4, 1))
	_capsule(b, 0.022, 0.1, Vector3(0, 0, 0.13), c.darkened(0.3), Vector3(0, 0, PI / 2))
	_sphere(b, 0.014, Vector3(0, 0, 0.152), STEEL)
	_label(b, "zzz", Vector3(0, 0.072, -0.13), 0.0, 22, c.darkened(0.5), -PI / 2)
	_shape(b, Vector3(0.4, 0.14, 0.4))


static func _can(b: RigidBody3D, v: int) -> void:
	var brand: Array = CAN_BRANDS[v % CAN_BRANDS.size()]
	_cyl(b, 0.034, 0.034, 0.1, Vector3.ZERO, brand[1])
	_cyl(b, 0.035, 0.035, 0.028, Vector3(0, 0.005, 0), Color(0.97, 0.97, 0.97))
	_cyl(b, 0.027, 0.034, 0.014, Vector3(0, 0.057, 0), STEEL, Vector3.ZERO, 0.8)
	_cyl(b, 0.034, 0.026, 0.012, Vector3(0, -0.056, 0), STEEL, Vector3.ZERO, 0.8)
	_torus(b, 0.022, 0.028, Vector3(0, 0.064, 0), STEEL)
	_box(b, Vector3(0.012, 0.003, 0.022), Vector3(0, 0.066, 0.006), STEEL, Vector3.ZERO, 0.0, 0.9)
	for yaw in [0.0, PI]:
		_label(b, brand[0], Vector3(sin(yaw) * 0.036, 0.005, cos(yaw) * 0.036), yaw, 14, brand[1].darkened(0.3))
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.035
	cyl.height = 0.13
	cs.shape = cyl
	b.add_child(cs)


static func _laptop(b: RigidBody3D, extra: Dictionary, parts: Dictionary) -> void:
	var shell: Color = [STEEL, Color(0.25, 0.25, 0.28), Color(0.95, 0.75, 0.8)][int(extra.get("v", 0)) % 3]
	_rbox(b, Vector3(0.34, 0.024, 0.24), 0.01, Vector3(0, -0.03, 0), shell, Vector3(0, PI / 2, 0))
	_box(b, Vector3(0.3, 0.004, 0.11), Vector3(0, -0.017, -0.02), DARK)
	for row in 4:
		_box(b, Vector3(0.28, 0.003, 0.018), Vector3(0, -0.0145, -0.065 + row * 0.028), Color(0.32, 0.32, 0.36))
	_box(b, Vector3(0.1, 0.002, 0.06), Vector3(0, -0.017, 0.075), shell.darkened(0.15))
	var lid := Node3D.new()
	lid.position = Vector3(0, -0.02, -0.115)
	lid.rotation.x = -0.25
	b.add_child(lid)
	_rbox(lid, Vector3(0.34, 0.24, 0.014), 0.007, Vector3(0, 0.12, 0), shell, Vector3(0, PI / 2, 0))
	parts.screen = _box(lid, Vector3(0.31, 0.21, 0.004), Vector3(0, 0.12, 0.008), Color(0.88, 0.96, 0.9), Vector3.ZERO, 0.6)
	var file: String = LAPTOP_FILES[int(extra.get("v", 0)) % LAPTOP_FILES.size()]
	parts.screen_label = _label(lid, file, Vector3(0, 0.12, 0.011), 0.0, 14, Color(0.1, 0.35, 0.15))
	_cyl(lid, 0.035, 0.035, 0.003, Vector3(0.05, 0.13, -0.009), Color(1, 0.85, 0.1), Vector3(PI / 2, 0, 0))
	_cyl(lid, 0.025, 0.025, 0.003, Vector3(-0.08, 0.08, -0.009), Color(0.3, 0.8, 1), Vector3(PI / 2, 0, 0))
	if extra.get("bsod", false):
		show_bsod(parts)
	_shape(b, Vector3(0.34, 0.03, 0.24), Vector3(0, -0.03, 0))
	var ls := _shape(b, Vector3(0.34, 0.24, 0.02), Vector3(0, 0.12, 0))
	ls.transform = lid.transform * ls.transform


static func _cart(b: RigidBody3D) -> void:
	_rbox(b, Vector3(0.42, 0.82, 0.78), 0.04, Vector3(0, 0.04, 0), STEEL, Vector3(0, PI / 2, 0), 0.6)
	_rbox(b, Vector3(0.44, 0.03, 0.8), 0.012, Vector3(0, 0.46, 0), Color(0.3, 0.31, 0.35), Vector3(0, PI / 2, 0))
	for sx in [-1, 1]:
		_box(b, Vector3(0.006, 0.08, 0.7), Vector3(sx * 0.212, 0.3, 0), Color(0.85, 0.15, 0.15))
		_box(b, Vector3(0.006, 0.02, 0.7), Vector3(sx * 0.212, -0.25, 0), Color(0.15, 0.25, 0.6))
		_label(b, "DRINKS\n& REGRETS", Vector3(sx * 0.216, 0.04, 0), sx * PI / 2, 34, Color(0.15, 0.25, 0.6))
	for sz in [-1, 1]:
		# Drawer fronts with little handles on both ends.
		for i in 3:
			_box(b, Vector3(0.36, 0.005, 0.006), Vector3(0, -0.22 + i * 0.22, sz * 0.392), DARK)
			_capsule(b, 0.008, 0.08, Vector3(0, -0.13 + i * 0.22, sz * 0.4), DARK, Vector3(0, 0, PI / 2))
		for sx in [-1, 1]:
			_box(b, Vector3(0.03, 0.06, 0.04), Vector3(sx * 0.15, -0.38, sz * 0.32), DARK)
			_cyl(b, 0.05, 0.05, 0.035, Vector3(sx * 0.15, -0.42, sz * 0.32), DARK, Vector3(0, 0, PI / 2))
			_cyl(b, 0.022, 0.022, 0.04, Vector3(sx * 0.15, -0.42, sz * 0.32), STEEL, Vector3(0, 0, PI / 2), 0.8)
	# Push bar at the back.
	_cyl(b, 0.015, 0.015, 0.42, Vector3(0, 0.36, 0.45), DARK, Vector3(0, 0, PI / 2))
	for sx in [-1, 1]:
		_box(b, Vector3(0.02, 0.02, 0.07), Vector3(sx * 0.18, 0.36, 0.415), DARK)
	# Tray top: cans, a coffee pot, a stack of cups.
	for i in 3:
		var brand: Array = CAN_BRANDS[i]
		_cyl(b, 0.034, 0.034, 0.12, Vector3(-0.12 + i * 0.08, 0.535, -0.24), brand[1])
	_cyl(b, 0.06, 0.07, 0.14, Vector3(0.08, 0.545, 0.05), STEEL, Vector3.ZERO, 0.8)
	_cyl(b, 0.02, 0.055, 0.05, Vector3(0.08, 0.64, 0.05), DARK)
	_torus(b, 0.03, 0.045, Vector3(0.15, 0.55, 0.05), DARK, Vector3(PI / 2, 0, PI / 2))
	for i in 4:
		_cyl(b, 0.035, 0.026, 0.07, Vector3(-0.1, 0.51 + i * 0.022, 0.15), Color(0.97, 0.97, 0.97))
	_shape(b, Vector3(0.44, 0.94, 0.8))


static func _crate(b: RigidBody3D, extra: Dictionary, parts: Dictionary) -> void:
	var wood := WOOD.darkened(float(extra.get("tint", 0.0)))
	_box(b, Vector3(0.86, 0.78, 0.86), Vector3.ZERO, wood)
	for i in 3:
		# Horizontal planks on all four sides (slightly proud of the core).
		var y := -0.26 + i * 0.26
		_box(b, Vector3(0.9, 0.2, 0.9), Vector3(0, y, 0), wood.lightened(0.06 * (i % 2)))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(b, Vector3(0.1, 0.82, 0.1), Vector3(sx * 0.42, 0, sz * 0.42), wood.darkened(0.35))
			_box(b, Vector3(0.11, 0.1, 0.11), Vector3(sx * 0.42, -0.37, sz * 0.42), STEEL, Vector3.ZERO, 0.0, 0.7)
	for sx in [-1, 1]:
		_torus(b, 0.05, 0.075, Vector3(sx * 0.46, 0.15, 0), Color(0.85, 0.75, 0.5), Vector3(0, 0, PI / 2),
			Vector3(1, 1, 1.6))
	var lid := Node3D.new()
	lid.position = Vector3(0, 0.42, 0)
	b.add_child(lid)
	_box(lid, Vector3(0.94, 0.06, 0.94), Vector3.ZERO, wood.lightened(0.1))
	for i in 3:
		_box(lid, Vector3(0.94, 0.012, 0.008), Vector3(0, 0.031, -0.31 + i * 0.31), wood.darkened(0.4))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_sphere(lid, 0.016, Vector3(sx * 0.4, 0.03, sz * 0.4), STEEL)
	parts.lid = lid
	parts.hole = _box(b, Vector3(0.78, 0.01, 0.78), Vector3(0, 0.4, 0), Color(0.1, 0.06, 0.04))
	parts.hole.visible = false
	var text: String = extra.get("label", "MISC.")
	for yaw in [0.0, PI]:
		_label(b, text, Vector3(sin(yaw) * 0.456, 0.02, cos(yaw) * 0.456), yaw, 46, Color(0.6, 0.08, 0.05))
		var tag := Vector3(sin(yaw) * 0.455, -0.26, cos(yaw) * 0.455) + Vector3(cos(yaw), 0, -sin(yaw)) * 0.24
		_box(b, Vector3(0.18, 0.1, 0.004), tag, Color(0.97, 0.97, 0.95), Vector3(0, yaw, 0))
		_label(b, "||| || |||\nTO: ???", tag + Vector3(sin(yaw), 0, cos(yaw)) * 0.004, yaw, 16, DARK)
	for sx in [-1, 1]:
		var up := _label(b, "THIS WAY UP ->", Vector3(sx * 0.462, -0.12, 0), sx * PI / 2, 30, DARK)
		up.rotation.z = PI / 2
	if extra.get("searched", false):
		show_open_crate(parts)
	_shape(b, Vector3(0.9, 0.86, 0.9))


static func _debris(b: RigidBody3D, extra: Dictionary) -> void:
	var size: Vector3 = extra.get("size", Vector3(0.08, 0.05, 0.08))
	var c: Color = extra.get("color", Color(0.55, 0.55, 0.55))
	match String(extra.get("shape", "shard")):
		"cloth":
			_sphere(b, 0.5, Vector3.ZERO, c, size)
			_box(b, size * Vector3(0.5, 1.05, 0.12), Vector3(0, 0, size.z * 0.2), c.darkened(0.3))
		"tin":
			_cyl(b, size.x * 0.5, size.x * 0.4, size.y, Vector3.ZERO, c, Vector3(0.6, 0, 0.3), 0.6)
		_:
			_box(b, size, Vector3.ZERO, c, Vector3(0, 0.4, 0))
	_shape(b, size)


static func _extinguisher(b: RigidBody3D, parts: Dictionary) -> void:
	var red := Color(0.9, 0.08, 0.08)
	_cyl(b, 0.075, 0.075, 0.32, Vector3(0, -0.05, 0), red)
	_sphere(b, 0.075, Vector3(0, 0.11, 0), red)
	_torus(b, 0.065, 0.082, Vector3(0, -0.205, 0), DARK)
	_cyl(b, 0.077, 0.077, 0.1, Vector3(0, -0.06, 0), Color(0.97, 0.97, 0.95))
	_label(b, "FIRE\nGO AWAY", Vector3(0, -0.06, 0.079), 0.0, 16, red)
	_cyl(b, 0.025, 0.03, 0.05, Vector3(0, 0.2, 0), DARK)
	_box(b, Vector3(0.05, 0.04, 0.06), Vector3(0, 0.24, 0), STEEL, Vector3.ZERO, 0.0, 0.9)
	_box(b, Vector3(0.025, 0.012, 0.14), Vector3(0, 0.275, 0.05), DARK, Vector3(0.25, 0, 0))
	_box(b, Vector3(0.025, 0.012, 0.12), Vector3(0, 0.25, 0.06), DARK, Vector3(-0.1, 0, 0))
	_cyl(b, 0.02, 0.02, 0.01, Vector3(0.03, 0.235, 0.03), Color(0.97, 0.97, 0.97), Vector3(PI / 2, 0, 0))
	_box(b, Vector3(0.002, 0.014, 0.002), Vector3(0.03, 0.238, 0.036), red, Vector3(0, 0, 0.7))
	# Hose: out of the valve, down the side, nozzle pointing forward (-Z, like the camera).
	_capsule(b, 0.012, 0.1, Vector3(0, 0.23, -0.06), DARK, Vector3(PI / 2, 0, 0))
	_capsule(b, 0.012, 0.22, Vector3(0, 0.14, -0.11), DARK)
	_cyl(b, 0.012, 0.03, 0.08, Vector3(0, 0.05, -0.15), DARK, Vector3(-PI / 2, 0, 0))
	var nozzle := Node3D.new()
	nozzle.position = Vector3(0, 0.05, -0.2)
	b.add_child(nozzle)
	parts.nozzle = nozzle
	_shape(b, Vector3(0.17, 0.5, 0.17))


static func _duct_tape(b: RigidBody3D) -> void:
	_torus(b, 0.04, 0.085, Vector3.ZERO, Color(0.66, 0.68, 0.7), Vector3.ZERO, Vector3(1, 1.15, 1))
	_cyl(b, 0.042, 0.042, 0.05, Vector3.ZERO, Color(0.6, 0.45, 0.3))
	_cyl(b, 0.036, 0.036, 0.052, Vector3.ZERO, Color(0.2, 0.15, 0.1))
	_box(b, Vector3(0.05, 0.004, 0.09), Vector3(0.0, -0.01, 0.1), Color(0.6, 0.62, 0.65), Vector3(-0.7, 0, 0))
	_shape(b, Vector3(0.17, 0.05, 0.17))


static func _wrench(b: RigidBody3D) -> void:
	_capsule(b, 0.016, 0.3, Vector3.ZERO, STEEL, Vector3(PI / 2, 0, 0), 0.85)
	_capsule(b, 0.021, 0.13, Vector3(0, 0, 0.06), Color(0.85, 0.15, 0.1), Vector3(PI / 2, 0, 0))
	# Open jaw at the front, ring spanner at the back.
	_cyl(b, 0.055, 0.055, 0.024, Vector3(0, 0, -0.17), STEEL, Vector3.ZERO, 0.85)
	_box(b, Vector3(0.05, 0.03, 0.06), Vector3(0, 0, -0.205), Color(0.12, 0.12, 0.13))
	_cyl(b, 0.012, 0.012, 0.05, Vector3(0, 0, -0.13), Color(0.55, 0.55, 0.58), Vector3(0, 0, PI / 2), 0.9)
	_torus(b, 0.022, 0.042, Vector3(0, 0, 0.17), STEEL, Vector3.ZERO, Vector3(1, 1.2, 1))
	_shape(b, Vector3(0.11, 0.04, 0.44))


static func _banana(p: Node3D) -> void:
	var y := Color(1, 0.88, 0.15)
	for i in 4:
		var a := -0.5 + i * 0.33
		_capsule(p, 0.024, 0.09, Vector3(-0.1 + i * 0.066, 0.03 * absf(a) * 2.0 - 0.02, 0), y, Vector3(0, 0, PI / 2 + a))
	_cyl(p, 0.008, 0.012, 0.035, Vector3(-0.14, 0.035, 0), Color(0.45, 0.33, 0.12), Vector3(0, 0, 0.9))
	_sphere(p, 0.01, Vector3(0.135, 0.03, 0), Color(0.25, 0.18, 0.08))
	_box(p, Vector3(0.05, 0.002, 0.02), Vector3(0.02, -0.003, 0.022), Color(0.3, 0.55, 1.0))   # Brand sticker.


static func _peel(p: Node3D) -> void:
	var y := Color(1, 0.86, 0.2)
	_sphere(p, 0.028, Vector3(0, 0.0, 0), Color(0.95, 0.85, 0.35))
	_cyl(p, 0.008, 0.012, 0.035, Vector3(0, 0.03, 0), Color(0.45, 0.33, 0.12))
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.y = i * PI / 2 + 0.3
		p.add_child(arm)
		_capsule(arm, 0.025, 0.14, Vector3(0, -0.006, 0.07), y, Vector3(PI / 2 - 0.12, 0, 0), 0.0, Vector3(1, 1, 0.3))
		_sphere(arm, 0.01, Vector3(0, -0.005, 0.14), Color(0.35, 0.25, 0.1))


static func _chicken(b: RigidBody3D, parts: Dictionary) -> void:
	var y := Color(1, 0.88, 0.2)
	var o := Color(1, 0.55, 0.1)
	var root := Node3D.new()
	b.add_child(root)
	parts.squash = root
	_capsule(root, 0.055, 0.2, Vector3(0, 0, 0.04), y, Vector3(PI / 2, 0, 0))
	_capsule(root, 0.025, 0.14, Vector3(0, 0.06, -0.08), y, Vector3(-0.6, 0, 0))
	_sphere(root, 0.042, Vector3(0, 0.12, -0.12), y)
	_cyl(root, 0.0, 0.02, 0.055, Vector3(0, 0.115, -0.175), o, Vector3(-PI / 2, 0, 0))
	for i in 3:
		_sphere(root, 0.014, Vector3(0, 0.165, -0.135 + i * 0.016), Color(0.95, 0.1, 0.1))
	_sphere(root, 0.012, Vector3(0, 0.085, -0.15), Color(0.95, 0.1, 0.1))
	for sx in [-1, 1]:
		_sphere(root, 0.011, Vector3(sx * 0.032, 0.13, -0.14), Color.WHITE)
		_sphere(root, 0.006, Vector3(sx * 0.04, 0.132, -0.146), Color.BLACK)
		_sphere(root, 0.5, Vector3(sx * 0.055, 0.005, 0.04), y.darkened(0.08), Vector3(0.025, 0.06, 0.12))
		_capsule(root, 0.008, 0.11, Vector3(sx * 0.025, -0.08, 0.07), o)
		_box(root, Vector3(0.035, 0.006, 0.04), Vector3(sx * 0.025, -0.135, 0.055), o)
	_capsule(root, 0.02, 0.07, Vector3(0, 0.04, 0.15), y, Vector3(0.7, 0, 0))
	_shape(b, Vector3(0.12, 0.2, 0.36), Vector3(0, 0.03, 0.0))


static func _megaphone(b: RigidBody3D) -> void:
	_cyl(b, 0.035, 0.11, 0.26, Vector3(0, 0, -0.04), Color(0.97, 0.97, 0.95), Vector3(-PI / 2, 0, 0))
	_torus(b, 0.1, 0.125, Vector3(0, 0, -0.17), Color(0.9, 0.15, 0.15), Vector3(PI / 2, 0, 0))
	_cyl(b, 0.09, 0.09, 0.005, Vector3(0, 0, -0.165), DARK, Vector3(PI / 2, 0, 0))
	_cyl(b, 0.038, 0.038, 0.09, Vector3(0, 0, 0.13), Color(0.35, 0.36, 0.4), Vector3(PI / 2, 0, 0))
	_cyl(b, 0.04, 0.04, 0.01, Vector3(0, 0, 0.175), Color(0.9, 0.15, 0.15), Vector3(PI / 2, 0, 0))
	_capsule(b, 0.018, 0.12, Vector3(0, -0.08, 0.1), DARK, Vector3(-0.2, 0, 0))
	_box(b, Vector3(0.012, 0.03, 0.02), Vector3(0, -0.05, 0.075), Color(0.9, 0.15, 0.15))
	_label(b, "LOUD", Vector3(0, 0.07, -0.03), 0.0, 20, Color(0.9, 0.15, 0.15), -PI / 2 + 0.33)
	_shape(b, Vector3(0.24, 0.26, 0.36))


static func _parachute(b: RigidBody3D) -> void:
	var g := Color(0.38, 0.45, 0.24)
	_rbox(b, Vector3(0.34, 0.42, 0.14), 0.04, Vector3.ZERO, g, Vector3(0, 0, PI / 2))
	_rbox(b, Vector3(0.3, 0.12, 0.15), 0.03, Vector3(0, 0.16, 0.01), g.darkened(0.15), Vector3(0, 0, PI / 2))
	for sx in [-1, 1]:
		_capsule(b, 0.018, 0.46, Vector3(sx * 0.1, -0.01, -0.08), g.darkened(0.45))
		_box(b, Vector3(0.05, 0.035, 0.012), Vector3(sx * 0.1, -0.05, -0.1), STEEL, Vector3.ZERO, 0.0, 0.8)
	_torus(b, 0.02, 0.035, Vector3(0.13, 0.02, 0.08), Color(0.95, 0.1, 0.1), Vector3(PI / 2, 0, 0))
	_label(b, "PARACHUTE\n(probably)", Vector3(0, -0.08, 0.072), 0.0, 22, Color(1, 1, 0.82))
	_shape(b, Vector3(0.34, 0.42, 0.18))


static func _snack(b: RigidBody3D, v: int) -> void:
	var s: Array = SNACKS[v % SNACKS.size()]
	_sphere(b, 0.5, Vector3.ZERO, s[1], Vector3(0.16, 0.2, 0.06))
	for sy in [-1, 1]:
		_box(b, Vector3(0.15, 0.03, 0.014), Vector3(0, sy * 0.1, 0), s[1].lightened(0.3))
		for i in 5:
			_box(b, Vector3(0.006, 0.03, 0.016), Vector3(-0.06 + i * 0.03, sy * 0.1, 0), s[1].darkened(0.2))
	for yaw in [0.0, PI]:
		_label(b, s[0], Vector3(0, 0.01, cos(yaw) * 0.031), yaw, 22, Color.WHITE)
	_shape(b, Vector3(0.16, 0.24, 0.06))


# --- Primitives (shared meshes, shared materials) -----------------------------------------

static func _cached(key: String, make: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = make.call()
	return _meshes[key]


static func _inst(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, rot: Vector3, glow := 0.0,
		metal := 0.0, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Fx.mat(color, glow, metal)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO,
		glow := 0.0, metal := 0.0) -> MeshInstance3D:
	var mesh := _cached("b%s" % size, func() -> Mesh:
		var m := BoxMesh.new()
		m.size = size
		return m)
	return _inst(parent, mesh, pos, color, rot, glow, metal)


## Box with its four edges along X rounded (two slabs + four cylinders). `rot` turns the whole thing.
static func _rbox(parent: Node3D, size: Vector3, r: float, pos: Vector3, color: Color, rot := Vector3.ZERO,
		metal := 0.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation = rot
	parent.add_child(n)
	_box(n, Vector3(size.x, size.y - r * 2.0, size.z), Vector3.ZERO, color, Vector3.ZERO, 0.0, metal)
	_box(n, Vector3(size.x, size.y, size.z - r * 2.0), Vector3.ZERO, color, Vector3.ZERO, 0.0, metal)
	for sy in [-1, 1]:
		for sz in [-1, 1]:
			_cyl(n, r, r, size.x, Vector3(0, sy * (size.y * 0.5 - r), sz * (size.z * 0.5 - r)), color,
				Vector3(0, 0, PI / 2), metal)
	return n


static func _cyl(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3, color: Color,
		rot := Vector3.ZERO, metal := 0.0) -> MeshInstance3D:
	var mesh := _cached("c%.3f/%.3f/%.3f" % [top, bottom, height], func() -> Mesh:
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = height
		m.radial_segments = 14
		m.rings = 1
		return m)
	return _inst(parent, mesh, pos, color, rot, 0.0, metal)


static func _sphere(parent: Node3D, r: float, pos: Vector3, color: Color, scl := Vector3.ONE) -> MeshInstance3D:
	var mesh := _cached("s%.3f" % r, func() -> Mesh:
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 14
		m.rings = 7
		return m)
	return _inst(parent, mesh, pos, color, Vector3.ZERO, 0.0, 0.0, scl)


static func _capsule(parent: Node3D, r: float, h: float, pos: Vector3, color: Color, rot := Vector3.ZERO,
		metal := 0.0, scl := Vector3.ONE) -> MeshInstance3D:
	var mesh := _cached("p%.3f/%.3f" % [r, h], func() -> Mesh:
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = maxf(h, r * 2.0)
		m.radial_segments = 12
		m.rings = 3
		return m)
	return _inst(parent, mesh, pos, color, rot, 0.0, metal, scl)


static func _torus(parent: Node3D, inner: float, outer: float, pos: Vector3, color: Color, rot := Vector3.ZERO,
		scl := Vector3.ONE) -> MeshInstance3D:
	var mesh := _cached("t%.3f/%.3f" % [inner, outer], func() -> Mesh:
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 18
		m.ring_segments = 8
		return m)
	return _inst(parent, mesh, pos, color, rot, 0.0, 0.0, scl)


static func _label(parent: Node3D, text: String, pos: Vector3, yaw: float, size: int, color: Color,
		pitch := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.002
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	l.rotation = Vector3(pitch, yaw, 0)
	parent.add_child(l)
	return l


static func _shape(body: RigidBody3D, size: Vector3, pos := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)
	return cs
