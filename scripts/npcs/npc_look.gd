extends RefCounted
## Builds the cartoon visuals of one NPC onto its ragdoll bodies and drives the face.
##
## All coordinates are for a 1.0-sized person and are placed under per-body `vis` nodes
## scaled by the person's size. Meshes and materials are cached and shared by everyone.

enum Face { CALM, SCARED, CLOSED, OUT, HURT }

const SOLE := Color(0.95, 0.93, 0.88)

static var _mats := {}
static var _meshes := {}

var extra: Dictionary
var role: String
var w := 1.0                  ## Body width factor.
var belly := false

var _skin: Color
var _top: Color               ## Outer layer: shirt or uniform jacket.
var _hair: Color
var _lids: Array[Node3D] = []
var _pupils: Array[Node3D] = []
var _xeyes: Array[Node3D] = []
var _brows: Array[Node3D] = []
var _mouth_shut: Node3D
var _mouth_open: Node3D
var _phone: Node3D
var _blink_t := 3.0
var _brow_tilt := 0.0


func _init(p_extra: Dictionary, p_role: String) -> void:
	extra = p_extra
	role = p_role
	w = extra.get("width", 1.0)
	belly = w > 1.25
	_skin = extra.get("skin", Color(0.98, 0.84, 0.7))
	_hair = extra.get("hair", Color(0.1, 0.07, 0.05))
	_brow_tilt = extra.get("brow", 0.0)
	_top = Color(0.1, 0.13, 0.3) if role != "passenger" else extra.get("shirt", Color.WHITE)


# --- Shared resources --------------------------------------------------------------------

static func mat(c: Color, rough := 0.8, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f/%.2f" % [c.to_html(), rough, metal, glow]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = glow
		_mats[key] = m
	return _mats[key]


static func sphere(r: float, hemi := false) -> Mesh:
	var key := "s%.3f%s" % [r, hemi]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * (1.0 if hemi else 2.0)
		m.is_hemisphere = hemi
		m.radial_segments = 16
		m.rings = 8
		_meshes[key] = m
	return _meshes[key]


static func capsule(r: float, h: float) -> Mesh:
	var key := "c%.3f/%.3f" % [r, h]
	if not _meshes.has(key):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = maxf(h, r * 2.0)
		m.radial_segments = 14
		m.rings = 4
		_meshes[key] = m
	return _meshes[key]


static func cyl(top: float, bottom: float, h: float) -> Mesh:
	var key := "y%.3f/%.3f/%.3f" % [top, bottom, h]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = h
		m.radial_segments = 16
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func torus(inner: float, outer: float) -> Mesh:
	var key := "t%.3f/%.3f" % [inner, outer]
	if not _meshes.has(key):
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 18
		m.ring_segments = 8
		_meshes[key] = m
	return _meshes[key]


static func box(size: Vector3) -> Mesh:
	var key := "b%v" % size
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func prism(size: Vector3) -> Mesh:
	var key := "p%v" % size
	if not _meshes.has(key):
		var m := PrismMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


## Adds a mesh to `parent`. `rough`/`metal` tune the shared material.
static func part(mesh: Mesh, pos: Vector3, c: Color, parent: Node3D, rot := Vector3.ZERO, scl := Vector3.ONE,
		rough := 0.8, metal := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(c, rough, metal)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _gold(mesh: Mesh, pos: Vector3, parent: Node3D, rot := Vector3.ZERO) -> MeshInstance3D:
	return part(mesh, pos, Color(1.0, 0.8, 0.25), parent, rot, Vector3.ONE, 0.25, 0.9)


# --- Torso (root body) -------------------------------------------------------------------

## Shoulder pivot x for this body width (unit size).
func shoulder_x() -> float:
	return 0.23 * w + 0.07


func build_torso(v: Node3D) -> void:
	var pants: Color = extra.get("pants", Color(0.2, 0.22, 0.3))
	var shirt: Color = extra.get("shirt", Color.WHITE)
	var fz := -0.15 * w
	part(capsule(0.24, 0.74), Vector3(0, 0.02, 0), _top, v, Vector3.ZERO, Vector3(w, 1, 0.62 * w))
	if belly:
		part(sphere(0.5), Vector3(0, -0.08, -0.06), _top, v, Vector3.ZERO, Vector3(0.44 * w, 0.42, 0.36 * w))
	part(sphere(0.5), Vector3(0, -0.27, 0), pants, v, Vector3.ZERO, Vector3(0.46 * w, 0.28, 0.32 * w))
	part(cyl(0.25, 0.25, 0.05), Vector3(0, -0.17, 0), Color(0.22, 0.13, 0.07), v, Vector3.ZERO,
		Vector3(w, 1, 0.64 * w + (0.1 if belly else 0.0)), 0.5)
	_gold(box(Vector3(0.07, 0.05, 0.02)), Vector3(0, -0.17, -0.16 * w - (0.04 if belly else 0.0)), v)
	part(cyl(0.072, 0.085, 0.16), Vector3(0, 0.36, 0), _skin, v)
	for sx in [-1.0, 1.0]:
		part(sphere(0.09), Vector3(sx * shoulder_x(), 0.28, 0), _top, v)
	match role:
		"captain":
			_shirt_front(v, fz, Color(0.97, 0.97, 1.0), Color(0.05, 0.05, 0.08))
			for row in 3:
				for sx in [-1.0, 1.0]:
					_gold(sphere(0.018), Vector3(sx * 0.07 * w, 0.08 - row * 0.12, fz - 0.012), v)
			for sx in [-1.0, 1.0]:
				part(box(Vector3(0.15, 0.03, 0.17)), Vector3(sx * 0.2 * w, 0.33, 0), _top, v)
				for i in 3:
					_gold(box(Vector3(0.022, 0.034, 0.175)), Vector3(sx * (0.15 + i * 0.035) * w, 0.33, 0), v)
			_gold(box(Vector3(0.12, 0.025, 0.01)), Vector3(0.11 * w, 0.18, fz - 0.01), v)
			for sx in [-1.0, 1.0]:
				_gold(prism(Vector3(0.06, 0.03, 0.01)), Vector3(0.11 * w + sx * 0.07, 0.185, fz - 0.01), v,
					Vector3(0, 0, sx * 1.2))
		"attendant":
			_shirt_front(v, fz, Color(0.97, 0.97, 1.0), Color(0, 0, 0, 0))
			var red := Color(0.88, 0.12, 0.18)
			part(torus(0.07, 0.11), Vector3(0, 0.33, -0.01), red, v, Vector3(0.25, 0, 0))
			part(prism(Vector3(0.14, 0.14, 0.03)), Vector3(0.06, 0.24, fz - 0.02), red, v, Vector3(0, 0, PI + 0.3))
			part(box(Vector3(0.11, 0.04, 0.01)), Vector3(-0.1 * w, 0.16, fz - 0.005), Color(0.98, 0.98, 0.98), v)
			part(box(Vector3(0.11, 0.012, 0.012)), Vector3(-0.1 * w, 0.14, fz - 0.006), red, v)
			for row in 2:
				_gold(sphere(0.016), Vector3(0, -0.02 - row * 0.1, fz - 0.012), v)
			part(cyl(0.25 * w, 0.31 * w, 0.46), Vector3(0, -0.45, 0), _top, v, Vector3.ZERO, Vector3(1, 1, 0.75))
		_:
			var collar: Color = shirt.lightened(0.35)
			for sx in [-1.0, 1.0]:
				part(prism(Vector3(0.09, 0.1, 0.03)), Vector3(sx * 0.05, 0.3, fz + 0.01), collar, v,
					Vector3(0, 0, PI - sx * 0.6))
			if extra.get("tie", false):
				_tie(v, fz, extra.get("tie_color", Color(0.8, 0.1, 0.15)))
			else:
				for i in 3:
					part(sphere(0.016), Vector3(0, 0.2 - i * 0.12, fz - 0.004), collar, v)
			part(box(Vector3(0.09, 0.1, 0.012)), Vector3(0.1 * w, 0.14, fz + 0.004), shirt.darkened(0.15), v)
			if extra.get("necklace", false):
				_gold(torus(0.085, 0.1), Vector3(0, 0.32, -0.02), v, Vector3(0.35, 0, 0))
			if extra.get("pillow", false):
				part(torus(0.1, 0.18), Vector3(0, 0.36, 0.03), extra.get("hat_color", Color(0.4, 0.6, 1.0)), v,
					Vector3(0.15, 0, 0), Vector3(1, 1.6, 1))
			if extra.get("backpack", false):
				var bc: Color = extra.get("bag_color", Color(0.3, 0.5, 0.3))
				part(box(Vector3(0.36 * w, 0.42, 0.16)), Vector3(0, 0.02, 0.2 * w), bc, v, Vector3.ZERO, Vector3.ONE, 0.6)
				part(box(Vector3(0.3 * w, 0.14, 0.06)), Vector3(0, -0.1, 0.3 * w), bc.darkened(0.2), v)


## White shirt V and an optional tie under a jacket.
func _shirt_front(v: Node3D, fz: float, shirt: Color, tie: Color) -> void:
	part(prism(Vector3(0.18, 0.24, 0.02)), Vector3(0, 0.22, fz - 0.002), shirt, v, Vector3(0, 0, PI))
	for sx in [-1.0, 1.0]:
		part(prism(Vector3(0.1, 0.24, 0.02)), Vector3(sx * 0.1, 0.2, fz - 0.006), _top.lightened(0.12), v,
			Vector3(0, 0, PI + sx * 0.25))
	if tie.a > 0.0:
		_tie(v, fz - 0.008, tie)


func _tie(v: Node3D, fz: float, c: Color) -> void:
	part(sphere(0.033), Vector3(0, 0.29, fz - 0.012), c, v, Vector3.ZERO, Vector3(1, 0.8, 0.6))
	part(prism(Vector3(0.09, 0.3, 0.018)), Vector3(0, 0.12, fz - 0.014), c, v, Vector3(0, 0, PI))
	part(box(Vector3(0.09, 0.012, 0.02)), Vector3(0, 0.17, fz - 0.016), c.lightened(0.3), v)


# --- Head ------------------------------------------------------------------------------

func build_head(v: Node3D) -> void:
	part(sphere(0.2), Vector3.ZERO, _skin, v, Vector3.ZERO, Vector3(1, 1.08, 1))
	part(sphere(0.5), Vector3(0, -0.085, -0.03), _skin, v, Vector3.ZERO, Vector3(0.34, 0.2, 0.33))
	for sx in [-1.0, 1.0]:
		part(sphere(0.05), Vector3(sx * 0.2, -0.005, 0.01), _skin, v, Vector3.ZERO, Vector3(0.5, 1, 0.8))
		part(sphere(0.04), Vector3(sx * 0.115, -0.055, -0.165), _skin.lerp(Color(1, 0.3, 0.35), 0.3), v,
			Vector3.ZERO, Vector3(1, 0.6, 0.35))
		var eye := Node3D.new()
		eye.position = Vector3(sx * 0.075, 0.04, -0.168)
		eye.scale = Vector3(1, 1.15, 0.75)
		v.add_child(eye)
		part(sphere(0.048), Vector3.ZERO, Color(0.98, 0.98, 0.98), eye, Vector3.ZERO, Vector3.ONE, 0.25)
		var pupil := part(sphere(0.024), Vector3(0, 0, -0.04), Color(0.05, 0.05, 0.08), eye, Vector3.ZERO,
			Vector3.ONE, 0.15)
		part(sphere(0.008), Vector3(0.008, 0.01, -0.02), Color(1, 1, 1), pupil)
		_pupils.append(pupil)
		var lid := part(sphere(0.054, true), Vector3.ZERO, _skin.darkened(0.04), eye)
		_lids.append(lid)
		var x := Node3D.new()
		x.position = Vector3(sx * 0.075, 0.04, -0.21)
		x.visible = false
		v.add_child(x)
		for r in [0.785, -0.785]:
			part(box(Vector3(0.085, 0.018, 0.012)), Vector3.ZERO, Color(0.05, 0.05, 0.05), x, Vector3(0, 0, r))
		_xeyes.append(x)
		var brow := part(capsule(0.014, 0.1), Vector3(sx * 0.075, 0.118, -0.182), _hair.darkened(0.25), v,
			Vector3(0, 0, PI / 2))
		_brows.append(brow)
	var nose: float = extra.get("nose", 1.0)
	part(sphere(0.042 * nose), Vector3(0, -0.01, -0.205), _skin.darkened(0.07), v, Vector3.ZERO, Vector3(1, 1.1, 1.2))
	_mouth_shut = Node3D.new()
	_mouth_shut.position = Vector3(0, -0.105, -0.188)
	v.add_child(_mouth_shut)
	var lip := Color(0.5, 0.12, 0.14)
	part(capsule(0.012, 0.09), Vector3.ZERO, lip, _mouth_shut, Vector3(0, 0, PI / 2))
	for sx in [-1.0, 1.0]:
		part(capsule(0.011, 0.04), Vector3(sx * 0.05, 0.01, 0.002), lip, _mouth_shut, Vector3(0, 0, sx * 0.9))
	_mouth_open = Node3D.new()
	_mouth_open.position = Vector3(0, -0.11, -0.18)
	_mouth_open.visible = false
	v.add_child(_mouth_open)
	part(sphere(0.06), Vector3.ZERO, Color(0.22, 0.03, 0.05), _mouth_open, Vector3.ZERO, Vector3(1, 1.2, 0.5))
	part(box(Vector3(0.075, 0.018, 0.02)), Vector3(0, 0.05, -0.018), Color(1, 1, 0.97), _mouth_open)
	part(sphere(0.03), Vector3(0, -0.04, -0.016), Color(0.95, 0.4, 0.45), _mouth_open, Vector3.ZERO, Vector3(1.4, 0.6, 1))
	if extra.get("stache", false) or role == "captain":
		part(capsule(0.024, 0.15), Vector3(0, -0.062, -0.206), _hair.darkened(0.15), v, Vector3(0, 0, PI / 2))
	if extra.get("beard", false):
		part(sphere(0.5), Vector3(0, -0.13, -0.08), _hair, v, Vector3.ZERO, Vector3(0.36, 0.2, 0.28))
	var hat := int(extra.get("hat", 0))
	var style := int(extra.get("style", 0))
	if role == "attendant":
		style = 5
	elif role == "captain" or hat == 2 or hat == 4:
		style = 0 if style != 2 else 2
	_build_hair(v, style)
	_build_hat(v, hat)
	_build_head_extras(v)


func _build_hair(v: Node3D, style: int) -> void:
	var c := _hair
	match style:
		0:  # Short crop.
			part(sphere(0.222), Vector3(0, 0.07, 0.02), c, v, Vector3.ZERO, Vector3(1, 0.62, 1))
		1:  # Towering bouffant.
			part(sphere(0.26), Vector3(0, 0.17, 0.05), c, v)
			part(sphere(0.17), Vector3(0, 0.38, 0.05), c, v)
		2:  # Bald with clown tufts.
			for sx in [-1.0, 1.0]:
				part(sphere(0.085), Vector3(sx * 0.2, 0.06, 0.05), c, v, Vector3.ZERO, Vector3(1, 0.9, 1.3))
		3:  # Mohawk.
			part(capsule(0.045, 0.42), Vector3(0, 0.2, 0.03), c, v, Vector3(PI / 2, 0, 0), Vector3(1, 1, 1.9))
		4:  # Bob with a fringe.
			part(sphere(0.23), Vector3(0, 0.09, 0.03), c, v, Vector3.ZERO, Vector3(1.05, 0.68, 1.02))
			part(sphere(0.21), Vector3(0, -0.02, 0.09), c, v, Vector3.ZERO, Vector3(1.06, 0.95, 0.65))
			for sx in [-1.0, 1.0]:
				part(capsule(0.06, 0.3), Vector3(sx * 0.19, -0.04, 0.03), c, v)
		5:  # Neat bun.
			part(sphere(0.222), Vector3(0, 0.07, 0.02), c, v, Vector3.ZERO, Vector3(1, 0.62, 1))
			part(sphere(0.09), Vector3(0, 0.17, 0.17), c, v)
		6:  # Enormous afro.
			part(sphere(0.3), Vector3(0, 0.16, 0.1), c, v)
		7:  # Ponytail.
			part(sphere(0.222), Vector3(0, 0.07, 0.02), c, v, Vector3.ZERO, Vector3(1, 0.62, 1))
			part(capsule(0.055, 0.32), Vector3(0, -0.02, 0.25), c, v, Vector3(0.5, 0, 0))
		8:  # Spiky.
			part(sphere(0.215), Vector3(0, 0.07, 0.02), c, v, Vector3.ZERO, Vector3(1, 0.6, 1))
			for i in 7:
				var a := i * TAU / 7.0
				part(prism(Vector3(0.09, 0.16, 0.09)), Vector3(cos(a) * 0.11, 0.2, sin(a) * 0.11), c, v,
					Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5))
		_:  # Pigtails.
			part(sphere(0.222), Vector3(0, 0.07, 0.02), c, v, Vector3.ZERO, Vector3(1, 0.62, 1))
			for sx in [-1.0, 1.0]:
				part(sphere(0.03), Vector3(sx * 0.2, 0.05, 0.06), Color(1, 0.3, 0.5), v)
				part(capsule(0.05, 0.24), Vector3(sx * 0.25, -0.04, 0.07), c, v, Vector3(0, 0, sx * 0.4))


func _build_hat(v: Node3D, hat: int) -> void:
	var hc: Color = extra.get("hat_color", Color(0.9, 0.2, 0.2))
	match role:
		"captain":
			var navy := Color(0.08, 0.1, 0.25)
			part(cyl(0.24, 0.215, 0.11), Vector3(0, 0.225, 0.01), navy, v)
			part(cyl(0.245, 0.245, 0.02), Vector3(0, 0.285, 0.01), Color(0.98, 0.98, 1.0), v)
			_gold(cyl(0.218, 0.218, 0.03), Vector3(0, 0.185, 0.01), v)
			part(cyl(0.14, 0.14, 0.02), Vector3(0, 0.165, -0.17), Color(0.03, 0.03, 0.05), v, Vector3(0.2, 0, 0),
				Vector3(1, 1, 0.7), 0.2)
			_gold(sphere(0.035), Vector3(0, 0.235, -0.225), v)
			for sx in [-1.0, 1.0]:
				_gold(prism(Vector3(0.07, 0.03, 0.01)), Vector3(sx * 0.055, 0.24, -0.226), v, Vector3(0, 0, sx * 1.3))
		"attendant":
			var red := Color(0.88, 0.12, 0.18)
			part(cyl(0.1, 0.11, 0.08), Vector3(0.06, 0.225, 0.0), red, v, Vector3(0, 0, -0.2))
			_gold(box(Vector3(0.05, 0.02, 0.01)), Vector3(0.05, 0.225, -0.105), v, Vector3(0, 0, -0.2))
		_:
			match hat:
				1:  # Baseball cap.
					part(sphere(0.226), Vector3(0, 0.08, 0.01), hc, v, Vector3.ZERO, Vector3(1, 0.6, 1))
					part(cyl(0.13, 0.13, 0.02), Vector3(0, 0.1, -0.2), hc.darkened(0.2), v, Vector3.ZERO, Vector3(1, 1, 1.15))
					part(sphere(0.025), Vector3(0, 0.215, 0.0), hc.darkened(0.2), v)
				2:  # Top hat.
					part(cyl(0.15, 0.15, 0.3), Vector3(0, 0.33, 0.0), Color(0.08, 0.08, 0.08), v, Vector3.ZERO,
						Vector3.ONE, 0.4)
					part(cyl(0.152, 0.152, 0.05), Vector3(0, 0.22, 0.0), hc, v)
					part(cyl(0.26, 0.26, 0.02), Vector3(0, 0.19, 0.0), Color(0.08, 0.08, 0.08), v)
				3:  # Bobble beanie.
					part(sphere(0.228), Vector3(0, 0.08, 0.01), hc, v, Vector3.ZERO, Vector3(1, 0.75, 1))
					part(torus(0.2, 0.235), Vector3(0, 0.04, 0.01), hc.lightened(0.3), v)
					part(sphere(0.06), Vector3(0, 0.27, 0.01), Color(0.98, 0.98, 0.98), v)
				4:  # Floppy sun hat.
					part(sphere(0.226), Vector3(0, 0.08, 0.01), hc, v, Vector3.ZERO, Vector3(1, 0.65, 1))
					part(cyl(0.36, 0.38, 0.02), Vector3(0, 0.1, 0.01), hc, v, Vector3(0.08, 0, 0))
					part(cyl(0.23, 0.23, 0.04), Vector3(0, 0.13, 0.01), Color(0.3, 0.2, 0.1), v)


func _build_head_extras(v: Node3D) -> void:
	var glasses := int(extra.get("glasses", 0))
	if glasses > 0:
		var gc: Color = extra.get("glasses_color", Color(0.1, 0.1, 0.1))
		for sx in [-1.0, 1.0]:
			if glasses == 2:
				part(sphere(0.055), Vector3(sx * 0.075, 0.04, -0.2), Color(0.05, 0.05, 0.08), v, Vector3.ZERO,
					Vector3(1.2, 0.9, 0.3), 0.1, 0.5)
			else:
				part(torus(0.036, 0.05), Vector3(sx * 0.075, 0.04, -0.207), gc, v, Vector3(PI / 2, 0, 0), Vector3.ONE,
					0.3, 0.4)
			part(box(Vector3(0.012, 0.012, 0.2)), Vector3(sx * 0.13, 0.045, -0.105), gc, v)
		part(box(Vector3(0.05, 0.012, 0.012)), Vector3(0, 0.045, -0.212), gc, v)
	if extra.get("phones", false):
		var pc := Color(0.15, 0.15, 0.18)
		part(box(Vector3(0.46, 0.03, 0.05)), Vector3(0, 0.25, 0.0), pc, v, Vector3.ZERO, Vector3.ONE, 0.4)
		for sx in [-1.0, 1.0]:
			part(box(Vector3(0.03, 0.24, 0.05)), Vector3(sx * 0.225, 0.13, 0.0), pc, v, Vector3.ZERO, Vector3.ONE, 0.4)
			part(cyl(0.06, 0.06, 0.05), Vector3(sx * 0.225, 0.0, 0.0), Color(0.95, 0.3, 0.3), v,
				Vector3(0, 0, PI / 2), Vector3.ONE, 0.4)
	if extra.get("earrings", false):
		for sx in [-1.0, 1.0]:
			_gold(torus(0.015, 0.028), Vector3(sx * 0.205, -0.07, 0.0), v, Vector3(0, PI / 2, PI / 2))
	if extra.get("mask", false):
		var mc: Color = extra.get("hat_color", Color(0.4, 0.3, 0.8))
		part(torus(0.2, 0.215), Vector3(0, 0.12, 0.0), mc, v, Vector3(0.15, 0, 0))
		for sx in [-1.0, 1.0]:
			part(sphere(0.06), Vector3(sx * 0.07, 0.15, -0.185), mc, v, Vector3.ZERO, Vector3(1.2, 0.8, 0.4))


# --- Limbs -----------------------------------------------------------------------------

func build_upper_arm(v: Node3D) -> void:
	if extra.get("short_sleeves", false) and role == "passenger":
		part(capsule(0.078, 0.2), Vector3(0, 0.07, 0), _top, v)
		part(capsule(0.064, 0.26), Vector3(0, -0.03, 0), _skin, v)
	else:
		part(capsule(0.075, 0.34), Vector3.ZERO, _top, v)


func build_forearm(v: Node3D, right: bool) -> void:
	var bare: bool = extra.get("short_sleeves", false) and role == "passenger"
	part(capsule(0.062, 0.3), Vector3(0, 0.02, 0), _skin if bare else _top, v)
	if not bare:
		var cuff := Color(0.97, 0.97, 1.0) if role != "passenger" else _top.lightened(0.3)
		part(torus(0.045, 0.07), Vector3(0, -0.105, 0), cuff, v)
		if role == "captain":
			for i in 3:
				_gold(torus(0.06, 0.068), Vector3(0, -0.07 + i * 0.025, 0), v)
	part(sphere(0.5), Vector3(0, -0.17, -0.005), _skin, v, Vector3.ZERO, Vector3(0.11, 0.13, 0.07))
	part(capsule(0.022, 0.08), Vector3(0, -0.15, -0.045), _skin, v, Vector3(0.7, 0, 0))
	for i in 3:
		part(capsule(0.016, 0.06), Vector3(-0.03 + i * 0.03, -0.235, -0.005), _skin, v)
	if not right and extra.get("watch", false):
		part(torus(0.05, 0.068), Vector3(0, -0.085, 0), Color(0.15, 0.15, 0.15), v)
		_gold(cyl(0.03, 0.03, 0.02), Vector3(0, -0.085, -0.06), v, Vector3(PI / 2, 0, 0))
	if right:
		_phone = Node3D.new()
		_phone.position = Vector3(0, -0.21, -0.06)
		_phone.rotation = Vector3(-0.3, 0, 0)
		_phone.visible = false
		v.add_child(_phone)
		part(box(Vector3(0.085, 0.16, 0.014)), Vector3.ZERO, Color(0.1, 0.1, 0.12), _phone, Vector3.ZERO, Vector3.ONE, 0.3)
		var screen := MeshInstance3D.new()
		screen.mesh = box(Vector3(0.07, 0.13, 0.004))
		screen.material_override = mat(Color(0.4, 0.75, 1.0), 0.2, 0.0, 1.2)
		screen.position = Vector3(0, 0, 0.009)
		_phone.add_child(screen)
		var rec := MeshInstance3D.new()
		rec.mesh = sphere(0.008)
		rec.material_override = mat(Color(1, 0.1, 0.1), 0.2, 0.0, 3.0)
		rec.position = Vector3(0.025, 0.05, 0.012)
		_phone.add_child(rec)
	elif extra.get("bag", false):
		var bc: Color = extra.get("bag_color", Color(0.6, 0.2, 0.4))
		part(box(Vector3(0.09, 0.2, 0.26)), Vector3(-0.06, -0.33, 0), bc, v, Vector3.ZERO, Vector3.ONE, 0.5)
		part(torus(0.07, 0.085), Vector3(-0.06, -0.2, 0), bc.darkened(0.3), v, Vector3(0, 0, PI / 2))
		_gold(box(Vector3(0.095, 0.03, 0.06)), Vector3(-0.06, -0.26, 0), v)


func build_thigh(v: Node3D) -> void:
	part(capsule(0.095, 0.48), Vector3.ZERO, _leg_color(), v)


func build_shin(v: Node3D) -> void:
	var shoe: Color = extra.get("shoes", Color(0.12, 0.1, 0.1))
	var shiny := role != "passenger"
	if shiny:
		shoe = Color(0.06, 0.06, 0.07)
	part(capsule(0.085, 0.36), Vector3(0, 0.03, 0), _leg_color(), v)
	if role != "attendant":
		part(cyl(0.078, 0.078, 0.05), Vector3(0, -0.145, 0), extra.get("socks", Color(0.95, 0.95, 0.95)), v)
	part(box(Vector3(0.14, 0.09, 0.22)), Vector3(0, -0.18, -0.035), shoe, v, Vector3.ZERO, Vector3.ONE,
		0.25 if shiny else 0.7)
	part(sphere(0.072), Vector3(0, -0.19, -0.14), shoe, v, Vector3.ZERO, Vector3(1, 0.65, 1), 0.25 if shiny else 0.7)
	part(box(Vector3(0.15, 0.03, 0.28)), Vector3(0, -0.225, -0.055), Color(0.1, 0.1, 0.1) if shiny else SOLE, v)
	if role == "attendant":
		part(box(Vector3(0.05, 0.06, 0.05)), Vector3(0, -0.255, 0.06), Color(0.1, 0.1, 0.1), v)
	elif not shiny:
		part(box(Vector3(0.06, 0.012, 0.1)), Vector3(0, -0.13, -0.08), Color(0.98, 0.98, 0.98), v)


func _leg_color() -> Color:
	if role == "attendant":
		return _skin.darkened(0.12)
	if role == "captain":
		return Color(0.08, 0.1, 0.25)
	return extra.get("pants", Color(0.2, 0.22, 0.3))


# --- Face ------------------------------------------------------------------------------

## Updates the expression. `t` is a running clock for blinking and screaming wobble.
func set_face(face: Face, t: float, dt: float, phone: bool) -> void:
	_phone.visible = phone
	var out := face == Face.OUT
	for x in _xeyes:
		x.visible = out
	for p in _pupils:
		p.visible = not out
		p.scale = Vector3.ONE * (0.7 if face == Face.SCARED else 1.0)
	_blink_t -= dt
	if _blink_t < -0.12:
		_blink_t = randf_range(2.0, 5.0)
	var lid := -PI / 2 if face == Face.CLOSED or out or _blink_t < 0.0 else \
		(PI / 2 if face == Face.SCARED or face == Face.HURT else 0.25)
	for l in _lids:
		l.visible = not out
		l.rotation.x = lerp_angle(l.rotation.x, lid, clampf(dt * 20.0, 0.0, 1.0))
	var screaming := face == Face.SCARED or face == Face.HURT
	_mouth_open.visible = screaming
	_mouth_shut.visible = not screaming
	if screaming:
		var s := 1.0 + 0.35 * sin(t * 24.0)
		_mouth_open.scale = Vector3(1.0, s, 1.0)
	_mouth_shut.rotation.z = 0.25 * sin(t * 3.0) if out else 0.0
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		var b := _brows[i]
		var worried := face == Face.SCARED or face == Face.CLOSED
		var tilt := sx * -0.45 if worried else (sx * 0.35 if face == Face.HURT else sx * -_brow_tilt)
		b.rotation.z = PI / 2 + tilt
		b.position.y = 0.118 + (0.03 if face == Face.SCARED else (-0.01 if face == Face.HURT else 0.0))
