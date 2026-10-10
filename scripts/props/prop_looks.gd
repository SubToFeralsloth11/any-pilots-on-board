extends RefCounted
## Data and visuals for every Props kind: physics specs, names, prompts, use hints, the
## builders that model each prop from rounded primitives, and its collision shapes.
##
## Builders place primitive MeshInstance3Ds under a visual root; build() then merges every
## opaque, non-glowing piece into one cached ArrayMesh (vertex colours, one matte and one metal
## surface), so a detailed suitcase costs one or two draw calls. Animated pieces listed in
## `parts` (crate lid, banana/peel, chicken squash root) are merged separately and stay movable;
## glowing/translucent pieces and Label3Ds are left as they are.

const Fx := preload("res://scripts/props/fx.gd")

## Physics/handling per kind. `mass` in kg, `friction`/`bounce` feed the PhysicsMaterial,
## `surface` picks damping and the impact sound (see SURFACES). Friction ~0.3 lets a ~20° bank
## start things sliding.
const SPECS := {
	"suitcase": {"name": "suitcase", "mass": 11.0, "friction": 0.32, "bounce": 0.12, "surface": "hard", "grab": true},
	"bag": {"name": "duffel bag", "mass": 6.0, "friction": 0.55, "bounce": 0.0, "surface": "fabric", "grab": true},
	"pillow": {"name": "neck pillow", "mass": 0.35, "friction": 0.6, "bounce": 0.05, "surface": "fabric", "grab": true},
	"can": {"name": "soda can", "mass": 0.37, "friction": 0.3, "bounce": 0.25, "surface": "tin", "grab": true},
	"laptop": {"name": "laptop", "mass": 1.8, "friction": 0.3, "bounce": 0.08, "surface": "hard", "grab": true},
	"cart": {"name": "drinks cart", "mass": 38.0, "friction": 0.04, "bounce": 0.05, "surface": "metal", "grab": true},
	"crate": {"name": "crate", "mass": 55.0, "friction": 0.55, "bounce": 0.02, "surface": "wood", "grab": false},
	"debris": {"name": "broken bits", "mass": 0.15, "friction": 0.6, "bounce": 0.1, "surface": "light", "grab": false},
	"peel": {"name": "banana peel", "mass": 0.05, "friction": 0.6, "bounce": 0.0, "surface": "light", "grab": true},
	"extinguisher": {"name": "fire extinguisher", "mass": 4.5, "friction": 0.35, "bounce": 0.15, "surface": "metal", "grab": true},
	"duct_tape": {"name": "duct tape", "mass": 0.3, "friction": 0.6, "bounce": 0.3, "surface": "light", "grab": true},
	"wrench": {"name": "wrench", "mass": 0.9, "friction": 0.35, "bounce": 0.2, "surface": "metal", "grab": true},
	"banana": {"name": "banana", "mass": 0.15, "friction": 0.5, "bounce": 0.05, "surface": "light", "grab": true},
	"rubber_chicken": {"name": "rubber chicken", "mass": 0.3, "friction": 0.8, "bounce": 0.65, "surface": "rubber", "grab": true},
	"megaphone": {"name": "megaphone", "mass": 0.9, "friction": 0.35, "bounce": 0.2, "surface": "hard", "grab": true},
	"parachute": {"name": "parachute", "mass": 7.0, "friction": 0.6, "bounce": 0.0, "surface": "fabric", "grab": true},
	"snack": {"name": "bag of snacks", "mass": 0.1, "friction": 0.5, "bounce": 0.05, "surface": "light", "grab": true},
}

## Per surface: linear/angular damping and the impact sound + pitch it makes.
## Fabric is dead and tumbles little, metal rings, light stuff flutters (air drag).
const SURFACES := {
	"fabric": {"lin": 0.25, "ang": 3.0, "sound": "thud", "pitch": 0.8},
	"hard": {"lin": 0.08, "ang": 1.2, "sound": "knock", "pitch": 1.0},
	"wood": {"lin": 0.1, "ang": 1.5, "sound": "knock", "pitch": 0.6},
	"metal": {"lin": 0.05, "ang": 0.8, "sound": "clank", "pitch": 1.0},
	"tin": {"lin": 0.1, "ang": 0.6, "sound": "clank", "pitch": 1.7},
	"rubber": {"lin": 0.1, "ang": 0.5, "sound": "squeak", "pitch": 1.3},
	"light": {"lin": 0.6, "ang": 2.0, "sound": "thud", "pitch": 1.8},
}

## Small kinds that can tunnel through thin walls when thrown (CCD while airborne only).
const SMALL := ["can", "wrench", "duct_tape", "banana", "peel", "snack", "rubber_chicken", "megaphone",
	"pillow", "laptop", "debris"]

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
const RUBBER := Color(0.08, 0.08, 0.09)
const ALU := Color(0.86, 0.87, 0.9)

static var _meshes := {}        ## Primitive meshes by shape key.
static var _merged := {}        ## Merged ArrayMesh by look key.
static var _vc_mats := {}       ## Vertex-colour materials: "matte" / "metal".
static var _phys_mats := {}     ## PhysicsMaterial by friction/bounce.


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


## Shared PhysicsMaterial for a kind (friction + bounce from SPECS).
static func physics_material(kind: String) -> PhysicsMaterial:
	var spec: Dictionary = SPECS[kind]
	var key := "%.2f/%.2f" % [spec.friction, spec.bounce]
	if not _phys_mats.has(key):
		var m := PhysicsMaterial.new()
		m.friction = spec.friction
		m.bounce = spec.bounce
		m.rough = spec.surface == "fabric"
		_phys_mats[key] = m
	return _phys_mats[key]


## Damping/sound row for a kind.
static func surface(kind: String) -> Dictionary:
	return SURFACES[SPECS[kind].surface]


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
	var vis := Node3D.new()
	vis.name = "Vis"
	body.add_child(vis)
	match kind:
		"suitcase":
			_suitcase(vis, extra.color)
		"bag":
			_bag(vis, extra.color)
		"pillow":
			_pillow(vis, extra.color)
		"can":
			_can(vis, int(extra.v))
		"laptop":
			_laptop(vis, extra, parts)
		"cart":
			_cart(vis)
		"crate":
			_crate(vis, extra, parts)
		"debris":
			_debris(vis, extra)
		"extinguisher":
			_extinguisher(vis, parts)
		"duct_tape":
			_duct_tape(vis)
		"wrench":
			_wrench(vis)
		"banana":
			parts.banana = Node3D.new()
			parts.peel = Node3D.new()
			vis.add_child(parts.banana)
			vis.add_child(parts.peel)
			_banana(parts.banana)
			_peel(parts.peel)
			parts.peel.visible = false
		"peel":
			_peel(vis)
		"rubber_chicken":
			_chicken(vis, parts)
		"megaphone":
			_megaphone(vis)
		"parachute":
			_parachute(vis)
		"snack":
			_snack(vis, int(extra.v))
	var key := _look_key(kind, extra)
	var keep: Array = parts.values()
	for part_name: String in parts:
		var n: Node3D = parts[part_name]
		if not (n is MeshInstance3D or n is Label3D):
			merge_static(n, [], "%s/%s" % [key, part_name])
	merge_static(vis, keep, key)
	_collide(body, kind, extra)


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


# --- Collision ---------------------------------------------------------------------------

## Shapes that roughly follow each model: cylinders for cans/rolls/tanks, capsules for soft
## or long things, boxes for luggage and crates.
static func _collide(b: RigidBody3D, kind: String, extra: Dictionary) -> void:
	match kind:
		"suitcase":
			_shape(b, Vector3(0.64, 0.25, 0.43))
		"bag":
			_capsule_shape(b, 0.14, 0.6, Vector3.ZERO, Vector3(0, 0, PI / 2))
		"pillow":
			_cyl_shape(b, 0.2, 0.12, Vector3.ZERO)
		"can":
			_cyl_shape(b, 0.034, 0.124, Vector3.ZERO)
		"laptop":
			_shape(b, Vector3(0.34, 0.03, 0.24), Vector3(0, -0.03, 0))
			var lid := Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, -0.02, -0.115))
			var cs := _shape(b, Vector3(0.34, 0.24, 0.02))
			cs.transform = lid * Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0))
		"cart":
			_shape(b, Vector3(0.44, 0.94, 0.8))
		"crate":
			_shape(b, Vector3(0.9, 0.86, 0.9))
		"debris":
			_shape(b, extra.get("size", Vector3(0.08, 0.05, 0.08)))
		"extinguisher":
			_cyl_shape(b, 0.08, 0.5, Vector3(0, 0.035, 0))
		"duct_tape":
			_cyl_shape(b, 0.085, 0.05, Vector3.ZERO)
		"wrench":
			_shape(b, Vector3(0.1, 0.03, 0.44))
		"banana":
			_capsule_shape(b, 0.035, 0.3, Vector3(0, 0.01, 0), Vector3(0, 0, PI / 2))
		"peel":
			_shape(b, Vector3(0.26, 0.03, 0.26))
		"rubber_chicken":
			_capsule_shape(b, 0.06, 0.34, Vector3(0, 0.02, 0.0), Vector3(PI / 2, 0, 0))
		"megaphone":
			_cyl_shape(b, 0.115, 0.36, Vector3(0, 0, 0.0), Vector3(PI / 2, 0, 0))
		"parachute":
			_shape(b, Vector3(0.42, 0.34, 0.2), Vector3(0, 0, -0.01))
		"snack":
			_shape(b, Vector3(0.16, 0.24, 0.06))


static func _shape(body: RigidBody3D, size: Vector3, pos := Vector3.ZERO) -> CollisionShape3D:
	var bs := BoxShape3D.new()
	bs.size = size
	return _add_shape(body, bs, pos, Vector3.ZERO)


static func _cyl_shape(body: RigidBody3D, r: float, h: float, pos: Vector3, rot := Vector3.ZERO) -> CollisionShape3D:
	var cs := CylinderShape3D.new()
	cs.radius = r
	cs.height = h
	return _add_shape(body, cs, pos, rot)


static func _capsule_shape(body: RigidBody3D, r: float, h: float, pos: Vector3, rot := Vector3.ZERO) -> CollisionShape3D:
	var cs := CapsuleShape3D.new()
	cs.radius = r
	cs.height = h
	return _add_shape(body, cs, pos, rot)


static func _add_shape(body: RigidBody3D, shape: Shape3D, pos: Vector3, rot: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	cs.rotation = rot
	body.add_child(cs)
	return cs


# --- Kinds -----------------------------------------------------------------------------

## Hard-shell spinner suitcase lying on its back: ribbed shell, zip seam with two pulls,
## corner guards, four spinner wheels, telescoping handle, side handle, tag and stickers.
static func _suitcase(b: Node3D, c: Color) -> void:
	var shell := c
	var trim := c.darkened(0.45)
	_rbox(b, Vector3(0.62, 0.24, 0.42), 0.06, Vector3.ZERO, shell)
	# Raised ribs along both shells.
	for sy in [-1, 1]:
		for i in 4:
			_box(b, Vector3(0.5, 0.012, 0.03), Vector3(0.0, sy * 0.122, -0.135 + i * 0.09), c.lightened(0.12))
	# Zip seam all round with two pulls.
	_box(b, Vector3(0.63, 0.024, 0.43), Vector3.ZERO, trim)
	_box(b, Vector3(0.6, 0.006, 0.434), Vector3.ZERO, Color(0.25, 0.25, 0.27))
	for px in [0.08, 0.15]:
		_box(b, Vector3(0.018, 0.034, 0.012), Vector3(px, 0.0, 0.222), STEEL, Vector3.ZERO, 0.0, 0.8)
		_box(b, Vector3(0.014, 0.05, 0.006), Vector3(px, -0.032, 0.226), DARK)
	# Corner guards.
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				_sphere(b, 0.035, Vector3(sx * 0.282, sy * 0.092, sz * 0.182), DARK, Vector3(1, 0.9, 1))
	# Spinner wheels on the -X end (bottom when stood up).
	for sy in [-1, 1]:
		for sz in [-1, 1]:
			var at := Vector3(-0.322, sy * 0.075, sz * 0.15)
			_box(b, Vector3(0.03, 0.05, 0.05), at, DARK)
			_cyl(b, 0.026, 0.026, 0.022, at + Vector3(-0.03, 0, 0), RUBBER, Vector3(PI / 2, 0, 0))
			_cyl(b, 0.012, 0.012, 0.024, at + Vector3(-0.03, 0, 0), STEEL, Vector3(PI / 2, 0, 0), 0.8)
	# Telescoping handle on the +X end: two tubes into a housing and a grip bar.
	_rbox(b, Vector3(0.03, 0.06, 0.26), 0.012, Vector3(0.318, 0.0, 0.0), DARK)
	for sz in [-1, 1]:
		_cyl(b, 0.009, 0.009, 0.06, Vector3(0.345, 0.0, sz * 0.1), ALU, Vector3(0, 0, PI / 2), 0.8)
	_capsule(b, 0.016, 0.24, Vector3(0.375, 0.0, 0.0), DARK, Vector3(PI / 2, 0, 0))
	# Side carry handle, half sunk into the shell.
	_box(b, Vector3(0.16, 0.05, 0.012), Vector3(0, 0, 0.216), DARK)
	_capsule(b, 0.013, 0.14, Vector3(0, 0, 0.238), DARK, Vector3(0, 0, PI / 2))
	# Luggage tag and stickers.
	_box(b, Vector3(0.07, 0.1, 0.006), Vector3(-0.07, -0.05, 0.25), Color(1, 0.95, 0.8))
	_cyl(b, 0.004, 0.004, 0.06, Vector3(-0.06, 0.01, 0.235), DARK)
	for i in 3:
		var s: Color = STICKERS[(i + int(c.r * 10.0)) % STICKERS.size()]
		_cyl(b, 0.055 - i * 0.008, 0.055 - i * 0.008, 0.004, Vector3(-0.18 + i * 0.16, 0.13, -0.05 + (i % 2) * 0.1), s)
	_label(b, "HAWAII?", Vector3(0.18, 0.133, -0.1), 0.0, 18, DARK, -PI / 2)


## Soft duffel: tapered barrel body, piped ends, top zip, two grab handles, shoulder strap,
## webbing bands, end pocket and a brand patch.
static func _bag(b: Node3D, c: Color) -> void:
	var dark := c.darkened(0.35)
	_capsule(b, 0.14, 0.6, Vector3.ZERO, c, Vector3(0, 0, PI / 2), 0.0, Vector3(1, 1, 0.95))
	_sphere(b, 0.5, Vector3(0, -0.07, 0), c.darkened(0.12), Vector3(0.5, 0.12, 0.26))     # Sagging base.
	for sx in [-1, 1]:
		_cyl(b, 0.125, 0.125, 0.02, Vector3(sx * 0.215, 0, 0), dark, Vector3(0, 0, PI / 2))
		_torus(b, 0.122, 0.138, Vector3(sx * 0.225, 0, 0), DARK, Vector3(0, 0, PI / 2))
		# Webbing bands that become the handles.
		_torus(b, 0.138, 0.15, Vector3(sx * 0.1, 0, 0), DARK, Vector3(0, 0, PI / 2), Vector3(1, 1, 0.95))
	# Top zip with a pull.
	_box(b, Vector3(0.38, 0.01, 0.024), Vector3(0, 0.138, 0), Color(0.2, 0.2, 0.22))
	_box(b, Vector3(0.025, 0.006, 0.04), Vector3(0.17, 0.142, 0.02), STEEL, Vector3.ZERO, 0.0, 0.8)
	# Two grab handles arching over the zip.
	for sx in [-1, 1]:
		_torus(b, 0.06, 0.075, Vector3(sx * 0.1, 0.15, 0), DARK, Vector3(PI / 2, 0, PI / 2), Vector3(1, 1, 0.5))
	# Shoulder strap lying across, clipped to the ends.
	_box(b, Vector3(0.5, 0.008, 0.04), Vector3(0, 0.149, -0.07), DARK, Vector3(0, 0.08, 0))
	for sx in [-1, 1]:
		_box(b, Vector3(0.03, 0.025, 0.02), Vector3(sx * 0.235, 0.09, -0.06), STEEL, Vector3.ZERO, 0.0, 0.8)
	# End pocket and brand patch.
	_rbox(b, Vector3(0.03, 0.12, 0.16), 0.02, Vector3(0.235, -0.01, 0), c.lightened(0.1))
	_box(b, Vector3(0.1, 0.05, 0.008), Vector3(0, 0.04, 0.135), Color(0.95, 0.95, 0.9), Vector3(-0.3, 0, 0))
	_label(b, "GYM?", Vector3(0, 0.04, 0.14), 0.0, 16, dark, -0.3)


## U-shaped travel neck pillow: plump segments around an open arc, snap strap and logo.
static func _pillow(b: Node3D, c: Color) -> void:
	for i in 11:
		var a := lerpf(-2.3, 2.3, i / 10.0)
		_sphere(b, 0.068, Vector3(sin(a) * 0.13, 0, -cos(a) * 0.13), c, Vector3(1, 0.85, 1))
	# Seam piping on top.
	for i in 10:
		var a := lerpf(-2.1, 2.1, i / 9.0)
		_sphere(b, 0.012, Vector3(sin(a) * 0.13, 0.055, -cos(a) * 0.13), c.darkened(0.15))
	# Snap strap across the opening.
	_box(b, Vector3(0.15, 0.012, 0.022), Vector3(0, 0, 0.105), c.darkened(0.3))
	_cyl(b, 0.012, 0.012, 0.016, Vector3(0.05, 0.0, 0.105), STEEL, Vector3.ZERO, 0.8)
	_label(b, "zzz", Vector3(0, 0.06, -0.13), 0.0, 22, c.darkened(0.5), -PI / 2)


## Soda can: printed body with a band, tapered shoulder and base, rim, lid and ring pull.
static func _can(b: Node3D, v: int) -> void:
	var brand: Array = CAN_BRANDS[v % CAN_BRANDS.size()]
	var col: Color = brand[1]
	_cyl(b, 0.034, 0.034, 0.096, Vector3.ZERO, col)
	_cyl(b, 0.0345, 0.0345, 0.026, Vector3(0, 0.006, 0), Color(0.97, 0.97, 0.97))
	_cyl(b, 0.0345, 0.0345, 0.006, Vector3(0, -0.012, 0), col.lightened(0.35))
	_cyl(b, 0.027, 0.034, 0.014, Vector3(0, 0.055, 0), STEEL, Vector3.ZERO, 0.8)
	_cyl(b, 0.034, 0.024, 0.012, Vector3(0, -0.054, 0), STEEL, Vector3.ZERO, 0.8)
	_cyl(b, 0.025, 0.025, 0.003, Vector3(0, 0.0615, 0), Color(0.7, 0.72, 0.75), Vector3.ZERO, 0.8)
	_torus(b, 0.024, 0.029, Vector3(0, 0.063, 0), STEEL)
	_box(b, Vector3(0.012, 0.003, 0.024), Vector3(0, 0.065, 0.006), STEEL, Vector3.ZERO, 0.0, 0.9)
	_torus(b, 0.004, 0.007, Vector3(0, 0.066, 0.016), STEEL)
	for yaw in [0.0, PI]:
		_label(b, brand[0], Vector3(sin(yaw) * 0.0355, 0.006, cos(yaw) * 0.0355), yaw, 14, col.darkened(0.3))


## Laptop: aluminium deck with a real key grid, trackpad, hinge, feet, and a lid with a bezel,
## glowing screen (swapped on BSOD), webcam and a logo on the back.
static func _laptop(b: Node3D, extra: Dictionary, parts: Dictionary) -> void:
	var v := int(extra.get("v", 0))
	var shell: Color = [ALU, Color(0.25, 0.25, 0.28), Color(0.95, 0.75, 0.8)][v % 3]
	var metal := 0.6 if v % 3 == 0 else 0.0
	_rbox(b, Vector3(0.34, 0.022, 0.24), 0.01, Vector3(0, -0.03, 0), shell, Vector3(0, PI / 2, 0), metal)
	_box(b, Vector3(0.3, 0.003, 0.11), Vector3(0, -0.0185, -0.025), Color(0.16, 0.16, 0.18))
	for row in 4:
		for k in 11:
			_box(b, Vector3(0.021, 0.004, 0.019), Vector3(-0.125 + k * 0.025, -0.0165, -0.067 + row * 0.024), DARK)
	_box(b, Vector3(0.13, 0.004, 0.019), Vector3(0, -0.0165, 0.029), DARK)          # Space bar.
	_box(b, Vector3(0.11, 0.002, 0.065), Vector3(0, -0.0185, 0.077), shell.darkened(0.12))
	_cyl(b, 0.007, 0.007, 0.3, Vector3(0, -0.02, -0.117), shell.darkened(0.25), Vector3(0, 0, PI / 2), metal)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_cyl(b, 0.008, 0.008, 0.004, Vector3(sx * 0.14, -0.043, sz * 0.09), RUBBER)
	var lid := Node3D.new()
	lid.position = Vector3(0, -0.02, -0.115)
	lid.rotation.x = -0.25
	b.add_child(lid)
	_rbox(lid, Vector3(0.34, 0.24, 0.012), 0.006, Vector3(0, 0.12, 0), shell, Vector3(0, PI / 2, 0), metal)
	_box(lid, Vector3(0.325, 0.225, 0.002), Vector3(0, 0.12, 0.0065), RUBBER)                 # Bezel.
	parts.screen = _box(lid, Vector3(0.3, 0.19, 0.002), Vector3(0, 0.125, 0.008), Color(0.88, 0.96, 0.9),
		Vector3.ZERO, 0.6)
	var file: String = LAPTOP_FILES[v % LAPTOP_FILES.size()]
	parts.screen_label = _label(lid, file, Vector3(0, 0.125, 0.0095), 0.0, 14, Color(0.1, 0.35, 0.15))
	_sphere(lid, 0.003, Vector3(0, 0.226, 0.007), Color(0.05, 0.05, 0.05))
	# Back of the lid: a logo and two stickers.
	_cyl(lid, 0.022, 0.022, 0.002, Vector3(0, 0.13, -0.0065), shell.lightened(0.3), Vector3(PI / 2, 0, 0))
	_cyl(lid, 0.03, 0.03, 0.002, Vector3(0.09, 0.06, -0.0065), Color(1, 0.85, 0.1), Vector3(PI / 2, 0, 0))
	_cyl(lid, 0.022, 0.022, 0.002, Vector3(-0.1, 0.18, -0.0065), Color(0.3, 0.8, 1), Vector3(PI / 2, 0, 0))
	if extra.get("bsod", false):
		show_bsod(parts)


## Airline trolley: brushed body with recessed end doors (handles, latches, hinges), red
## stripe, rubber bumper, a lipped tray top with drinks, four casters and a brake pedal.
static func _cart(b: Node3D) -> void:
	var red := Color(0.8, 0.12, 0.14)
	var navy := Color(0.15, 0.22, 0.5)
	_rbox(b, Vector3(0.42, 0.8, 0.78), 0.035, Vector3(0, 0.03, 0), ALU, Vector3(0, PI / 2, 0), 0.6)
	# Side panels: livery stripes, rivets, logo.
	for sx in [-1, 1]:
		_box(b, Vector3(0.004, 0.06, 0.72), Vector3(sx * 0.211, 0.3, 0), red)
		_box(b, Vector3(0.004, 0.016, 0.72), Vector3(sx * 0.211, 0.25, 0), navy)
		for i in 6:
			_sphere(b, 0.006, Vector3(sx * 0.211, 0.4, -0.3 + i * 0.12), STEEL)
			_sphere(b, 0.006, Vector3(sx * 0.211, -0.32, -0.3 + i * 0.12), STEEL)
		_label(b, "DRINKS\n& REGRETS", Vector3(sx * 0.214, 0.04, 0), sx * PI / 2, 34, navy)
	# End doors (both ends): inset panel, vertical bar handle, latch, hinges, a drawer at the top.
	for sz in [-1, 1]:
		var face: float = sz * 0.39
		_box(b, Vector3(0.36, 0.56, 0.006), Vector3(0, -0.04, face), ALU.darkened(0.08), Vector3.ZERO, 0.0, 0.6)
		_box(b, Vector3(0.36, 0.006, 0.008), Vector3(0, 0.245, face), DARK)
		_box(b, Vector3(0.36, 0.13, 0.006), Vector3(0, 0.32, face), ALU.darkened(0.04), Vector3.ZERO, 0.0, 0.6)
		_capsule(b, 0.007, 0.1, Vector3(0, 0.32, face + sz * 0.012), DARK, Vector3(0, 0, PI / 2))
		_capsule(b, 0.01, 0.3, Vector3(0.13, -0.04, face + sz * 0.02), DARK)
		for hy in [0.12, -0.2]:
			_box(b, Vector3(0.02, 0.02, 0.025), Vector3(0.13, hy, face + sz * 0.01), DARK)
			_cyl(b, 0.008, 0.008, 0.05, Vector3(-0.175, hy, face + sz * 0.004), STEEL, Vector3.ZERO, 0.8)
		_box(b, Vector3(0.04, 0.04, 0.01), Vector3(0.0, 0.18, face + sz * 0.006), red)
		# Push handle rail along the top of each end.
		_cyl(b, 0.012, 0.012, 0.38, Vector3(0, 0.42, face + sz * 0.035), DARK, Vector3(0, 0, PI / 2))
		for sx in [-1, 1]:
			_box(b, Vector3(0.02, 0.02, 0.04), Vector3(sx * 0.17, 0.42, face + sz * 0.018), DARK)
	# Rubber bumper round the base.
	_rbox(b, Vector3(0.44, 0.04, 0.8), 0.018, Vector3(0, -0.36, 0), RUBBER, Vector3(0, PI / 2, 0))
	# Tray top with a raised lip.
	_rbox(b, Vector3(0.44, 0.025, 0.8), 0.01, Vector3(0, 0.44, 0), Color(0.3, 0.31, 0.35), Vector3(0, PI / 2, 0))
	for sx in [-1, 1]:
		_box(b, Vector3(0.012, 0.025, 0.78), Vector3(sx * 0.214, 0.465, 0), DARK)
	for sz in [-1, 1]:
		_box(b, Vector3(0.44, 0.025, 0.012), Vector3(0, 0.465, sz * 0.394), DARK)
	# Casters: fork, wheel, hub. Brake pedal on one end.
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var at := Vector3(sx * 0.15, -0.415, sz * 0.31)
			_box(b, Vector3(0.05, 0.03, 0.05), at + Vector3(0, 0.025, 0), DARK)
			_box(b, Vector3(0.006, 0.05, 0.03), at + Vector3(0.022, 0, 0), STEEL, Vector3.ZERO, 0.0, 0.8)
			_box(b, Vector3(0.006, 0.05, 0.03), at + Vector3(-0.022, 0, 0), STEEL, Vector3.ZERO, 0.0, 0.8)
			_cyl(b, 0.042, 0.042, 0.03, at + Vector3(0, -0.012, 0), RUBBER, Vector3(0, 0, PI / 2))
			_cyl(b, 0.018, 0.018, 0.034, at + Vector3(0, -0.012, 0), STEEL, Vector3(0, 0, PI / 2), 0.8)
	_box(b, Vector3(0.1, 0.012, 0.05), Vector3(0, -0.38, 0.42), red)
	# Tray load: cans, a coffee pot, a stack of cups, napkins.
	for i in 3:
		var brand: Array = CAN_BRANDS[i]
		_cyl(b, 0.034, 0.034, 0.12, Vector3(-0.12 + i * 0.08, 0.513, -0.24), brand[1])
		_cyl(b, 0.027, 0.034, 0.012, Vector3(-0.12 + i * 0.08, 0.578, -0.24), STEEL, Vector3.ZERO, 0.8)
	_cyl(b, 0.06, 0.07, 0.14, Vector3(0.08, 0.523, 0.05), STEEL, Vector3.ZERO, 0.8)
	_cyl(b, 0.02, 0.055, 0.05, Vector3(0.08, 0.618, 0.05), DARK)
	_torus(b, 0.03, 0.045, Vector3(0.15, 0.53, 0.05), DARK, Vector3(PI / 2, 0, PI / 2))
	for i in 5:
		_cyl(b, 0.035, 0.026, 0.07, Vector3(-0.1, 0.488 + i * 0.016, 0.17), Color(0.97, 0.97, 0.97))
	_box(b, Vector3(0.1, 0.03, 0.1), Vector3(0.1, 0.468, 0.26), Color(0.95, 0.95, 0.92))


## Wooden cargo crate: framed planks with gaps, diagonal braces, steel corner caps and a strap,
## nails, rope handles, stencils and a shipping tag. The lid lifts off when searched.
static func _crate(b: Node3D, extra: Dictionary, parts: Dictionary) -> void:
	var wood := WOOD.darkened(snappedf(float(extra.get("tint", 0.0)), 0.05))
	var frame := wood.darkened(0.3)
	var gap := wood.darkened(0.6)
	_box(b, Vector3(0.84, 0.8, 0.84), Vector3.ZERO, gap)
	# Four sides: four planks with dark gaps, a frame and a diagonal brace.
	for side in 4:
		var yaw := side * PI / 2
		var n := Vector3(sin(yaw), 0, cos(yaw))
		var t := Vector3(cos(yaw), 0, -sin(yaw))
		for i in 4:
			var shade := wood.lightened(0.05 * ((i + side) % 2)).darkened(0.04 * (i % 3))
			_box(b, Vector3(0.8, 0.185, 0.02), n * 0.425 + Vector3(0, -0.29 + i * 0.193, 0), shade, Vector3(0, yaw, 0))
		for sy in [-1, 1]:
			_box(b, Vector3(0.84, 0.07, 0.025), n * 0.442 + Vector3(0, sy * 0.37, 0), frame, Vector3(0, yaw, 0))
		var brace := 1.0 if side % 2 == 0 else -1.0
		var mi := _box(b, Vector3(0.96, 0.07, 0.022), n * 0.444, frame.lightened(0.05), Vector3(0, yaw, 0))
		mi.rotate_object_local(Vector3.FORWARD, brace * 0.78)
		# Nails at the ends of every plank.
		for sx in [-1, 1]:
			for i in 4:
				_sphere(b, 0.008, n * 0.437 + t * sx * 0.36 + Vector3(0, -0.29 + i * 0.193, 0), Color(0.35, 0.35, 0.38))
	# Corner posts and steel corner caps (top and bottom).
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(b, Vector3(0.07, 0.86, 0.07), Vector3(sx * 0.425, 0, sz * 0.425), frame)
			for sy in [-1, 1]:
				_box(b, Vector3(0.1, 0.07, 0.1), Vector3(sx * 0.425, sy * 0.4, sz * 0.425), STEEL, Vector3.ZERO, 0.0, 0.7)
				_sphere(b, 0.01, Vector3(sx * 0.476, sy * 0.4, sz * 0.4), DARK)
				_sphere(b, 0.01, Vector3(sx * 0.4, sy * 0.4, sz * 0.476), DARK)
	# Steel strap round the middle.
	for side in 4:
		var yaw := side * PI / 2
		var n := Vector3(sin(yaw), 0, cos(yaw))
		_box(b, Vector3(0.88, 0.035, 0.006), n * 0.457 + Vector3(0, 0.1, 0), Color(0.32, 0.34, 0.38), Vector3(0, yaw, 0), 0.0, 0.7)
	# Rope handles on the X sides.
	for sx in [-1, 1]:
		_torus(b, 0.012, 0.026, Vector3(sx * 0.465, 0.27, -0.09), Color(0.45, 0.45, 0.48), Vector3(0, 0, PI / 2))
		_torus(b, 0.012, 0.026, Vector3(sx * 0.465, 0.27, 0.09), Color(0.45, 0.45, 0.48), Vector3(0, 0, PI / 2))
		_capsule(b, 0.016, 0.22, Vector3(sx * 0.48, 0.24, 0), Color(0.85, 0.75, 0.5), Vector3(PI / 2, 0, 0))
	var lid := Node3D.new()
	lid.position = Vector3(0, 0.42, 0)
	b.add_child(lid)
	for i in 5:
		_box(lid, Vector3(0.9, 0.05, 0.172), Vector3(0, 0, -0.36 + i * 0.18), wood.lightened(0.08 + 0.04 * (i % 2)))
	for sz in [-1, 1]:
		_box(lid, Vector3(0.07, 0.03, 0.9), Vector3(sz * 0.3, 0.04, 0), frame)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_sphere(lid, 0.012, Vector3(sx * 0.3, 0.056, sz * 0.36), STEEL)
	parts.lid = lid
	parts.hole = _box(b, Vector3(0.78, 0.01, 0.78), Vector3(0, 0.4, 0), Color(0.1, 0.06, 0.04))
	parts.hole.visible = false
	var text: String = extra.get("label", "MISC.")
	for yaw in [0.0, PI]:
		_label(b, text, Vector3(sin(yaw) * 0.448, 0.02, cos(yaw) * 0.448), yaw, 46, Color(0.55, 0.08, 0.05))
		var tag := Vector3(sin(yaw) * 0.446, -0.25, cos(yaw) * 0.446) + Vector3(cos(yaw), 0, -sin(yaw)) * 0.2
		_box(b, Vector3(0.18, 0.1, 0.004), tag, Color(0.97, 0.97, 0.95), Vector3(0, yaw, 0))
		_label(b, "||| || |||\nTO: ???", tag + Vector3(sin(yaw), 0, cos(yaw)) * 0.004, yaw, 16, DARK)
	for sx in [-1, 1]:
		var up := _label(b, "THIS WAY UP ->", Vector3(sx * 0.448, -0.12, 0), sx * PI / 2, 30, DARK)
		up.rotation.z = PI / 2
	if extra.get("searched", false):
		show_open_crate(parts)


static func _debris(b: Node3D, extra: Dictionary) -> void:
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


## Fire extinguisher: domed tank with a label band, base ring, valve, gauge, lever handle,
## safety pin and a hose with the nozzle pointing forward (-Z, like the camera).
static func _extinguisher(b: Node3D, parts: Dictionary) -> void:
	var red := Color(0.85, 0.07, 0.07)
	_cyl(b, 0.075, 0.075, 0.32, Vector3(0, -0.05, 0), red)
	_sphere(b, 0.075, Vector3(0, 0.11, 0), red, Vector3(1, 0.8, 1))
	_cyl(b, 0.072, 0.07, 0.02, Vector3(0, -0.215, 0), RUBBER)
	_torus(b, 0.068, 0.08, Vector3(0, -0.2, 0), DARK)
	_cyl(b, 0.0765, 0.0765, 0.1, Vector3(0, -0.06, 0), Color(0.97, 0.97, 0.95))
	_cyl(b, 0.077, 0.077, 0.01, Vector3(0, -0.01, 0), Color(0.15, 0.15, 0.17))
	_label(b, "FIRE\nGO AWAY", Vector3(0, -0.065, 0.078), 0.0, 16, red)
	_cyl(b, 0.025, 0.03, 0.05, Vector3(0, 0.19, 0), Color(0.6, 0.6, 0.62), Vector3.ZERO, 0.8)
	_box(b, Vector3(0.05, 0.04, 0.06), Vector3(0, 0.235, 0), STEEL, Vector3.ZERO, 0.0, 0.9)
	_box(b, Vector3(0.026, 0.012, 0.15), Vector3(0, 0.27, 0.05), DARK, Vector3(0.25, 0, 0))
	_box(b, Vector3(0.026, 0.012, 0.13), Vector3(0, 0.245, 0.06), DARK, Vector3(-0.1, 0, 0))
	_torus(b, 0.01, 0.016, Vector3(0.03, 0.25, 0.0), Color(0.95, 0.85, 0.1), Vector3(0, 0, PI / 2))
	_cyl(b, 0.02, 0.02, 0.012, Vector3(0.03, 0.23, 0.03), Color(0.97, 0.97, 0.97), Vector3(PI / 2, 0, 0))
	_torus(b, 0.019, 0.023, Vector3(0.03, 0.23, 0.037), STEEL, Vector3(PI / 2, 0, 0))
	_box(b, Vector3(0.002, 0.014, 0.002), Vector3(0.03, 0.233, 0.038), red, Vector3(0, 0, 0.7))
	_capsule(b, 0.012, 0.1, Vector3(0, 0.225, -0.06), DARK, Vector3(PI / 2, 0, 0))
	_capsule(b, 0.012, 0.22, Vector3(0, 0.135, -0.11), DARK)
	_cyl(b, 0.012, 0.03, 0.08, Vector3(0, 0.05, -0.15), DARK, Vector3(-PI / 2, 0, 0))
	var nozzle := Node3D.new()
	nozzle.position = Vector3(0, 0.05, -0.2)
	b.add_child(nozzle)
	parts.nozzle = nozzle


static func _duct_tape(b: Node3D) -> void:
	_torus(b, 0.04, 0.085, Vector3.ZERO, Color(0.66, 0.68, 0.7), Vector3.ZERO, Vector3(1, 1.15, 1))
	_torus(b, 0.083, 0.086, Vector3(0, 0.024, 0), Color(0.55, 0.57, 0.6))
	_cyl(b, 0.042, 0.042, 0.05, Vector3.ZERO, Color(0.6, 0.45, 0.3))
	_cyl(b, 0.036, 0.036, 0.052, Vector3.ZERO, Color(0.2, 0.15, 0.1))
	_box(b, Vector3(0.05, 0.004, 0.09), Vector3(0.0, -0.01, 0.1), Color(0.6, 0.62, 0.65), Vector3(-0.7, 0, 0))


## Combination spanner: flat chrome shank, rubber grip, open jaw at the front, ring at the back.
static func _wrench(b: Node3D) -> void:
	_box(b, Vector3(0.028, 0.012, 0.3), Vector3.ZERO, STEEL, Vector3.ZERO, 0.0, 0.85)
	_capsule(b, 0.019, 0.13, Vector3(0, 0, 0.06), Color(0.85, 0.15, 0.1), Vector3(PI / 2, 0, 0), 0.0, Vector3(1.2, 1, 0.7))
	# Open jaw: a disc with a dark slot, the two prongs either side.
	_cyl(b, 0.04, 0.04, 0.014, Vector3(0, 0, -0.17), STEEL, Vector3.ZERO, 0.85)
	for sx in [-1, 1]:
		_box(b, Vector3(0.022, 0.014, 0.05), Vector3(sx * 0.026, 0, -0.205), STEEL, Vector3(0, sx * 0.25, 0), 0.0, 0.85)
	_box(b, Vector3(0.03, 0.016, 0.05), Vector3(0, 0, -0.19), Color(0.06, 0.06, 0.07))
	_label(b, "13", Vector3(0, 0.008, -0.13), 0.0, 14, DARK, -PI / 2)
	# Ring end with a hex inside.
	_torus(b, 0.018, 0.034, Vector3(0, 0, 0.17), STEEL, Vector3.ZERO, Vector3(1, 0.5, 1))
	_cyl(b, 0.018, 0.018, 0.013, Vector3(0, 0, 0.17), Color(0.06, 0.06, 0.07))


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


static func _chicken(b: Node3D, parts: Dictionary) -> void:
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


## Megaphone: white horn with a red rim and dark grille, grey body, pistol grip with trigger,
## carry strap and battery cap.
static func _megaphone(b: Node3D) -> void:
	var red := Color(0.9, 0.15, 0.15)
	_cyl(b, 0.035, 0.11, 0.26, Vector3(0, 0, -0.04), Color(0.97, 0.97, 0.95), Vector3(-PI / 2, 0, 0))
	_torus(b, 0.1, 0.125, Vector3(0, 0, -0.17), red, Vector3(PI / 2, 0, 0))
	_cyl(b, 0.09, 0.09, 0.005, Vector3(0, 0, -0.165), DARK, Vector3(PI / 2, 0, 0))
	_torus(b, 0.035, 0.045, Vector3(0, 0, -0.163), Color(0.25, 0.25, 0.28), Vector3(PI / 2, 0, 0))
	_cyl(b, 0.038, 0.038, 0.09, Vector3(0, 0, 0.13), Color(0.35, 0.36, 0.4), Vector3(PI / 2, 0, 0))
	_cyl(b, 0.04, 0.04, 0.012, Vector3(0, 0, 0.18), red, Vector3(PI / 2, 0, 0))
	_capsule(b, 0.018, 0.12, Vector3(0, -0.08, 0.1), DARK, Vector3(-0.2, 0, 0))
	_box(b, Vector3(0.012, 0.03, 0.02), Vector3(0, -0.05, 0.075), red)
	_torus(b, 0.05, 0.06, Vector3(0, 0.03, 0.08), DARK, Vector3(0, 0, PI / 2), Vector3(1, 0.6, 1))
	_label(b, "LOUD", Vector3(0, 0.07, -0.03), 0.0, 20, red, -PI / 2 + 0.33)


## Parachute rig: olive container with a top flap and stitching, shoulder straps with steel
## buckles, chest strap, red ripcord handle and a stencil.
static func _parachute(b: Node3D) -> void:
	var g := Color(0.38, 0.45, 0.24)
	var strap := g.darkened(0.45)
	_rbox(b, Vector3(0.34, 0.42, 0.14), 0.04, Vector3.ZERO, g, Vector3(0, 0, PI / 2))
	_rbox(b, Vector3(0.3, 0.12, 0.15), 0.03, Vector3(0, 0.15, 0.005), g.darkened(0.15), Vector3(0, 0, PI / 2))
	for i in 9:
		_box(b, Vector3(0.012, 0.003, 0.003), Vector3(-0.16 + i * 0.04, 0.09, 0.077), g.lightened(0.25))
	for sx in [-1, 1]:
		_capsule(b, 0.018, 0.46, Vector3(sx * 0.1, -0.01, -0.08), strap, Vector3.ZERO, 0.0, Vector3(1.6, 1, 0.6))
		_box(b, Vector3(0.05, 0.035, 0.012), Vector3(sx * 0.1, -0.05, -0.1), STEEL, Vector3.ZERO, 0.0, 0.8)
		_box(b, Vector3(0.05, 0.035, 0.012), Vector3(sx * 0.1, 0.12, -0.1), STEEL, Vector3.ZERO, 0.0, 0.8)
	_box(b, Vector3(0.24, 0.025, 0.01), Vector3(0, 0.04, -0.1), strap)
	_box(b, Vector3(0.03, 0.03, 0.014), Vector3(0, 0.04, -0.105), STEEL, Vector3.ZERO, 0.0, 0.8)
	_torus(b, 0.018, 0.034, Vector3(0.15, 0.02, 0.08), Color(0.95, 0.1, 0.1), Vector3(PI / 2, 0, 0))
	_capsule(b, 0.006, 0.12, Vector3(0.15, 0.09, 0.075), Color(0.6, 0.6, 0.62))
	_label(b, "PARACHUTE\n(probably)", Vector3(0, -0.08, 0.072), 0.0, 22, Color(1, 1, 0.82))


static func _snack(b: Node3D, v: int) -> void:
	var s: Array = SNACKS[v % SNACKS.size()]
	_sphere(b, 0.5, Vector3.ZERO, s[1], Vector3(0.16, 0.2, 0.06))
	for sy in [-1, 1]:
		_box(b, Vector3(0.15, 0.03, 0.014), Vector3(0, sy * 0.1, 0), s[1].lightened(0.3))
		for i in 5:
			_box(b, Vector3(0.006, 0.03, 0.016), Vector3(-0.06 + i * 0.03, sy * 0.1, 0), s[1].darkened(0.2))
	for yaw in [0.0, PI]:
		_label(b, s[0], Vector3(0, 0.01, cos(yaw) * 0.031), yaw, 22, Color.WHITE)


# --- Mesh merging --------------------------------------------------------------------------

## Cache key for everything that changes a kind's merged mesh.
static func _look_key(kind: String, extra: Dictionary) -> String:
	match kind:
		"suitcase", "bag", "pillow":
			return "%s/%s" % [kind, (extra.color as Color).to_html()]
		"can", "laptop", "snack":
			return "%s/%d" % [kind, int(extra.v) % 60]   # 60 = lcm of the 3/4/5 variant counts.
		"crate":
			return "crate/%.2f" % snappedf(float(extra.get("tint", 0.0)), 0.05)
		"debris":
			return "debris/%s/%s/%s" % [extra.get("shape", ""), extra.get("size", Vector3.ZERO),
				(extra.get("color", Color.GRAY) as Color).to_html()]
	return kind


## Replaces every opaque, non-glowing MeshInstance3D under `root` (except `keep` subtrees) with
## one MeshInstance3D holding a merged mesh cached under `key` (one surface per matte / gloss /
## metal group, albedo in vertex colours), then drops the emptied helper nodes. Used by the Fun
## module's toys and weapons too; `key` must identify everything that changes the look.
static func merge_static(root: Node3D, keep: Array, key: String) -> void:
	var cached: ArrayMesh = _merged.get(key)
	var groups := {}
	_gather(root, Transform3D.IDENTITY, keep, groups, cached == null)
	if cached == null:
		cached = _commit(groups)
		_merged[key] = cached
	if cached.get_surface_count() > 0:
		var mi := MeshInstance3D.new()
		mi.mesh = cached
		root.add_child(mi)
		root.move_child(mi, 0)
	_prune(root, keep)


static func _gather(node: Node3D, xf: Transform3D, keep: Array, groups: Dictionary, collect: bool) -> void:
	for child in node.get_children():
		if keep.has(child) or child is Label3D or not child is Node3D:
			continue
		var c3 := child as Node3D
		var local := xf * c3.transform
		var mi := child as MeshInstance3D
		if mi:
			var m := mi.material_override as StandardMaterial3D
			if m == null or m.emission_enabled or m.albedo_color.a < 1.0:
				continue
			if collect:
				_append(groups, _group_of(m), mi.mesh, local, m.albedo_color)
			node.remove_child(mi)
			mi.free()
			continue
		_gather(c3, local, keep, groups, collect)


static func _append(groups: Dictionary, group: String, mesh: Mesh, xf: Transform3D, color: Color) -> void:
	if not groups.has(group):
		groups[group] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(),
			"i": PackedInt32Array()}
	var g: Dictionary = groups[group]
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var nb := xf.basis.inverse().transposed()
	# Take the arrays out of the dictionary so appending doesn't copy-on-write them.
	var gv: PackedVector3Array = g.v
	var gn: PackedVector3Array = g.n
	var gc: PackedColorArray = g.c
	var gi: PackedInt32Array = g.i
	g.v = PackedVector3Array()
	g.n = PackedVector3Array()
	g.c = PackedColorArray()
	g.i = PackedInt32Array()
	var base := gv.size()
	for k in verts.size():
		gv.append(xf * verts[k])
		gn.append((nb * norms[k]).normalized())
		gc.append(color)
	if idx.is_empty():
		for k in verts.size():
			gi.append(base + k)
	else:
		for j in idx:
			gi.append(base + j)
	g.v = gv
	g.n = gn
	g.c = gc
	g.i = gi


static func _group_of(m: StandardMaterial3D) -> String:
	if m.metallic > 0.0:
		return "metal"
	return "gloss" if m.roughness < 0.5 else "matte"


static func _commit(groups: Dictionary) -> ArrayMesh:
	var out := ArrayMesh.new()
	for group: String in ["matte", "gloss", "metal"]:
		if not groups.has(group):
			continue
		var g: Dictionary = groups[group]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.v
		arrays[Mesh.ARRAY_NORMAL] = g.n
		arrays[Mesh.ARRAY_COLOR] = g.c
		arrays[Mesh.ARRAY_INDEX] = g.i
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, _vc_mat(group))
	return out


## Shared material that takes its albedo from vertex colours ("matte", "gloss" or "metal").
static func _vc_mat(group: String) -> StandardMaterial3D:
	if not _vc_mats.has(group):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = {"matte": 0.7, "gloss": 0.35, "metal": 0.3}[group]
		m.metallic = 0.75 if group == "metal" else 0.0
		_vc_mats[group] = m
	return _vc_mats[group]


## Frees plain Node3D helpers left empty after merging (keeps `keep` and anything visible).
static func _prune(node: Node3D, keep: Array) -> void:
	for child in node.get_children():
		if keep.has(child) or child.get_class() != "Node3D":
			continue
		_prune(child as Node3D, keep)
		if child.get_child_count() == 0:
			node.remove_child(child)
			child.free()


# --- Primitives (shared meshes; materials only matter for unmerged pieces) ------------------

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
	var mesh := _cached("c%.4f/%.4f/%.4f" % [top, bottom, height], func() -> Mesh:
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = height
		m.radial_segments = 16
		m.rings = 1
		return m)
	return _inst(parent, mesh, pos, color, rot, 0.0, metal)


static func _sphere(parent: Node3D, r: float, pos: Vector3, color: Color, scl := Vector3.ONE) -> MeshInstance3D:
	var mesh := _cached("s%.4f" % r, func() -> Mesh:
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 10 if r < 0.02 else 16
		m.rings = 5 if r < 0.02 else 8
		return m)
	return _inst(parent, mesh, pos, color, Vector3.ZERO, 0.0, 0.0, scl)


static func _capsule(parent: Node3D, r: float, h: float, pos: Vector3, color: Color, rot := Vector3.ZERO,
		metal := 0.0, scl := Vector3.ONE) -> MeshInstance3D:
	var mesh := _cached("p%.4f/%.4f" % [r, h], func() -> Mesh:
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = maxf(h, r * 2.0)
		m.radial_segments = 12
		m.rings = 3
		return m)
	return _inst(parent, mesh, pos, color, rot, 0.0, metal, scl)


static func _torus(parent: Node3D, inner: float, outer: float, pos: Vector3, color: Color, rot := Vector3.ZERO,
		scl := Vector3.ONE) -> MeshInstance3D:
	var mesh := _cached("t%.4f/%.4f" % [inner, outer], func() -> Mesh:
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
