extends RefCounted
## Builds the cartoon visuals of one NPC onto its ragdoll bodies and drives the face.
##
## All coordinates are for a 1.0-sized person and are placed under per-body `vis` nodes
## scaled by the person's size. Parts are not separate nodes: `part()` records them per
## visual node and `_bake()` merges each node's parts into one vertex-coloured mesh, so a
## whole limb costs one draw call. Colour (sRGB) is in the vertex RGB and the finish in the
## vertex alpha (roughness, or 0 for gold/metal), read by one shared shader material.
## Primitive meshes and their tinted copies are static caches shared by every NPC. Parts
## smaller than FINE_SIZE go into a second mesh that casts no shadow and is hidden beyond
## FINE_RANGE. Animated face pieces live in their own holder nodes (lids, pupils, brows,
## mouths) and are baked separately.

enum Face { CALM, SCARED, CLOSED, OUT, HURT }
const SHADER := "shader_type spatial;
void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92), lessThan(c, vec3(0.04045)));
	float metal = 1.0 - step(0.05, COLOR.a);
	METALLIC = metal * 0.85;
	ROUGHNESS = mix(COLOR.a, 0.28, metal);
}
"
## Passenger clothing (spawn extra "outfit").
enum Outfit { SHIRT, HOODIE, HAWAIIAN, SWEATER, DRESS }

const SOLE := Color(0.95, 0.93, 0.88)
const GOLD := Color(1.0, 0.8, 0.25)
const NAVY := Color(0.08, 0.1, 0.25)
const CREW_RED := Color(0.88, 0.12, 0.18)
const SHIRT_WHITE := Color(0.97, 0.97, 1.0)
const BELT_STRAP := Color(0.32, 0.36, 0.45)
const MIN_ROUGH := 0.12
const FINE_SIZE := 0.07       ## Parts whose largest extent is below this are "fine detail".
const FINE_RANGE := 12.0      ## Fine detail is hidden beyond this camera distance (m).
const SKIN_ROUGH := 0.55
const HAIR_STYLES := 14
const EYE_R := 0.07           ## Googly eyeball radius.
const PUPIL_R := 0.026
const BROW_Y := 0.15
const OUTFITS := 5

static var _mats := {}
static var _meshes := {}
static var _tinted := {}

var extra: Dictionary
var role: String
var w := 1.0                  ## Body width factor.
var belly := false

var _skin: Color
var _top: Color               ## Outer layer: shirt or uniform jacket.
var _hair: Color
var _pending := {}            ## Visual node -> Array of [Mesh, Transform3D, Color (alpha = finish), scale].
var _lids: Array[Node3D] = []
var _pupils: Array[Node3D] = []
var _xeyes: Array[Node3D] = []
var _brows: Array[Node3D] = []
var _mouth_shut: Node3D
var _mouth_open: Node3D
var _phone: Node3D
var _blink_t := 3.0
var _brow_tilt := 0.0
var _gaze := Vector2.ZERO
var _outfit := Outfit.SHIRT
var _wobble := Vector2.ZERO           ## Googly pupil offset (eye-local x/y).
var _wobble_v := Vector2.ZERO
var _eye_prev := Vector3.ZERO
var _eye_vel := Vector3.ZERO


func _init(p_extra: Dictionary, p_role: String) -> void:
	extra = p_extra
	role = p_role
	w = extra.get("width", 1.0)
	belly = w > 1.25
	_skin = extra.get("skin", Color(0.98, 0.84, 0.7))
	_hair = extra.get("hair", Color(0.1, 0.07, 0.05))
	_brow_tilt = extra.get("brow", 0.0)
	_top = NAVY if role != "passenger" else extra.get("shirt", Color.WHITE)
	if role == "passenger":
		_outfit = int(extra.get("outfit", Outfit.SHIRT)) % OUTFITS as Outfit


# --- Shared resources --------------------------------------------------------------------

## Shared emissive material (phone screen, record light).
static func glow_mat(c: Color, energy: float) -> StandardMaterial3D:
	var key := "g%s/%.1f" % [c.to_html(), energy]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.2
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
		_mats[key] = m
	return _mats[key]


## Sphere; `seg` radial segments (0 = by radius).
static func sphere(r: float, hemi := false, seg := 0) -> Mesh:
	if seg <= 0:
		seg = 14 if r >= 0.15 else (10 if r >= 0.05 else 6)
	var key := "s%.3f%s%d" % [r, hemi, seg]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * (1.0 if hemi else 2.0)
		m.is_hemisphere = hemi
		m.radial_segments = seg
		m.rings = maxi(seg / 2, 3)
		_meshes[key] = m
	return _meshes[key]


static func capsule(r: float, h: float) -> Mesh:
	var key := "c%.3f/%.3f" % [r, h]
	if not _meshes.has(key):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = maxf(h, r * 2.0)
		m.radial_segments = 10 if r >= 0.05 else 6
		m.rings = 2 if r >= 0.05 else 1
		_meshes[key] = m
	return _meshes[key]


static func cyl(top: float, bottom: float, h: float) -> Mesh:
	var key := "y%.3f/%.3f/%.3f" % [top, bottom, h]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = h
		m.radial_segments = 12 if maxf(top, bottom) >= 0.1 else 8
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func torus(inner: float, outer: float) -> Mesh:
	var key := "t%.3f/%.3f" % [inner, outer]
	if not _meshes.has(key):
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 14 if outer >= 0.08 else 12
		m.ring_segments = 5 if outer - inner < 0.03 else 6
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


## A copy of `mesh` with vertex colour `c` (alpha = finish) and the non-uniform scale baked
## in (with correctly transformed normals), ready to be appended with a rigid transform.
static func _tint(mesh: Mesh, c: Color, scl: Vector3) -> ArrayMesh:
	var key := "%d/%s/%v" % [mesh.get_instance_id(), c.to_html(), scl]
	if _tinted.has(key):
		return _tinted[key]
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	arrays[Mesh.ARRAY_TANGENT] = null
	if scl != Vector3.ONE:
		arrays[Mesh.ARRAY_VERTEX] = Transform3D(Basis.from_scale(scl), Vector3.ZERO) * verts
		var normals: PackedVector3Array = Transform3D(Basis.from_scale(Vector3.ONE / scl), Vector3.ZERO) \
			* (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)
		for i in normals.size():
			normals[i] = normals[i].normalized()
		arrays[Mesh.ARRAY_NORMAL] = normals
	var cols := PackedColorArray()
	cols.resize(verts.size())
	cols.fill(c)
	arrays[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_tinted[key] = am
	return am


## Records a part on `parent` (baked later). `rough`/`metal` set the finish.
func part(mesh: Mesh, pos: Vector3, c: Color, parent: Node3D, rot := Vector3.ZERO, scl := Vector3.ONE,
		rough := 0.8, metal := 0.0) -> void:
	if not _pending.has(parent):
		_pending[parent] = []
	var tinted := Color(c, 0.0 if metal > 0.3 else maxf(rough, MIN_ROUGH))
	(_pending[parent] as Array).append([mesh, Transform3D(Basis.from_euler(rot), pos), tinted, scl])


func _skin_part(mesh: Mesh, pos: Vector3, parent: Node3D, rot := Vector3.ZERO, scl := Vector3.ONE,
		c: Color = _skin) -> void:
	part(mesh, pos, c, parent, rot, scl, SKIN_ROUGH)


func _gold(mesh: Mesh, pos: Vector3, parent: Node3D, rot := Vector3.ZERO, scl := Vector3.ONE) -> void:
	part(mesh, pos, GOLD, parent, rot, scl, 0.25, 0.9)


## An empty node for animated or optional pieces (face, phone, seatbelt); its parts are
## baked onto it and cast no shadow (they sit on or inside a body that already does).
static func holder(parent: Node3D, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation = rot
	n.scale = scl
	n.set_meta("no_shadow", true)
	parent.add_child(n)
	return n


## The one material every NPC mesh uses.
static func _vc_mat() -> ShaderMaterial:
	if not _mats.has("vc"):
		var sh := Shader.new()
		sh.code = SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		_mats["vc"] = m
	return _mats["vc"]


## Merges every recorded part into one mesh per node (plus one for fine detail).
func _bake() -> void:
	for node: Node3D in _pending:
		var tools: Array[SurfaceTool] = [null, null]
		for e: Array in _pending[node]:
			var mesh: Mesh = e[0]
			var scl: Vector3 = e[3]
			var size := mesh.get_aabb().size * scl.abs()
			var fine := 1 if size[size.max_axis_index()] < FINE_SIZE else 0
			if tools[fine] == null:
				tools[fine] = SurfaceTool.new()
				tools[fine].begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[fine].append_from(_tint(mesh, e[2], scl), 0, e[1])
		for fine in 2:
			if tools[fine] != null:
				var am := tools[fine].commit()
				am.surface_set_material(0, _vc_mat())
				_instance(node, am, fine == 1)
	_pending.clear()


static func _instance(node: Node3D, mesh: ArrayMesh, fine: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if fine or node.has_meta("no_shadow"):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if fine:
		mi.visibility_range_end = FINE_RANGE
		mi.visibility_range_end_margin = 1.0
	node.add_child(mi)


# --- Torso (root body) -------------------------------------------------------------------

## Shoulder pivot x for this body width (unit size).
func shoulder_x() -> float:
	return 0.23 * w + 0.07


func build_torso(v: Node3D) -> void:
	var pants: Color = extra.get("pants", Color(0.2, 0.22, 0.3))
	var fz := -0.15 * w
	var crew := role != "passenger"
	# Rib cage, tapering waist, shoulder slope.
	part(capsule(0.24, 0.74), Vector3(0, 0.02, 0), _top, v, Vector3.ZERO, Vector3(w, 1, 0.62 * w))
	part(sphere(0.5, false, 14), Vector3(0, 0.12, -0.005), _top, v, Vector3.ZERO, Vector3(0.5 * w, 0.46, 0.33 * w))
	part(capsule(0.085, shoulder_x() * 2.0), Vector3(0, 0.29, 0.005), _top, v, Vector3(0, 0, PI / 2),
		Vector3(1, 1, 0.9))
	if belly:
		part(sphere(0.5), Vector3(0, -0.08, -0.06), _top, v, Vector3.ZERO, Vector3(0.44 * w, 0.42, 0.36 * w))
	var dress := _outfit == Outfit.DRESS
	part(sphere(0.5), Vector3(0, -0.27, 0), _top if role == "attendant" or dress else pants, v, Vector3.ZERO,
		Vector3(0.46 * w, 0.28, 0.32 * w))
	if not crew and (_outfit == Outfit.SHIRT or _outfit == Outfit.HAWAIIAN):
		var belt_z := 0.64 * w + (0.1 if belly else 0.0)
		part(cyl(0.25, 0.25, 0.05), Vector3(0, -0.17, 0), Color(0.22, 0.13, 0.07), v, Vector3.ZERO,
			Vector3(w, 1, belt_z), 0.5)
		_gold(box(Vector3(0.07, 0.05, 0.02)), Vector3(0, -0.17, -0.16 * w - (0.04 if belly else 0.0)), v)
		_gold(box(Vector3(0.012, 0.035, 0.022)), Vector3(0.012, -0.17, -0.162 * w - (0.04 if belly else 0.0)), v)
	_skin_part(cyl(0.07, 0.082, 0.17), Vector3(0, 0.36, 0), v)
	for sx in [-1.0, 1.0]:
		part(sphere(0.092), Vector3(sx * shoulder_x(), 0.28, 0), _top, v)
	match role:
		"captain":
			_captain_torso(v, fz)
		"attendant":
			_attendant_torso(v, fz)
		_:
			_passenger_torso(v, fz)
	_bake()


func _captain_torso(v: Node3D, fz: float) -> void:
	_shirt_front(v, fz, SHIRT_WHITE, Color(0.05, 0.05, 0.08))
	_jacket_skirt(v, Color(0.06, 0.08, 0.2))
	for row in 3:
		for sx in [-1.0, 1.0]:
			_gold(sphere(0.019), Vector3(sx * 0.07 * w, 0.06 - row * 0.12, fz - 0.012), v)
	# Epaulettes with four captain's stripes.
	for sx in [-1.0, 1.0]:
		part(box(Vector3(0.15, 0.03, 0.17)), Vector3(sx * 0.2 * w, 0.335, 0), NAVY.darkened(0.3), v,
			Vector3(0, 0, -sx * 0.25))
		for i in 4:
			_gold(box(Vector3(0.016, 0.034, 0.175)), Vector3(sx * (0.14 + i * 0.03) * w, 0.335 - i * 0.008 * w, 0), v,
				Vector3(0, 0, -sx * 0.25))
	# Pilot wings and a pocket square.
	_gold(box(Vector3(0.12, 0.022, 0.01)), Vector3(-0.11 * w, 0.17, fz - 0.012), v)
	for sx in [-1.0, 1.0]:
		_gold(prism(Vector3(0.06, 0.03, 0.01)), Vector3(-0.11 * w + sx * 0.07, 0.175, fz - 0.012), v,
			Vector3(0, 0, sx * 1.2))
	part(prism(Vector3(0.06, 0.04, 0.012)), Vector3(0.11 * w, 0.17, fz - 0.008), SHIRT_WHITE, v)


func _attendant_torso(v: Node3D, fz: float) -> void:
	_shirt_front(v, fz, SHIRT_WHITE, Color(0, 0, 0, 0))
	# Neck scarf with a knot and two tails.
	part(torus(0.07, 0.105), Vector3(0, 0.33, -0.01), CREW_RED, v, Vector3(0.25, 0, 0))
	part(sphere(0.035), Vector3(0.05, 0.29, fz - 0.03), CREW_RED, v, Vector3.ZERO, Vector3(1, 0.8, 0.7))
	for i in 2:
		part(prism(Vector3(0.07, 0.13, 0.02)), Vector3(0.07 + i * 0.035, 0.22, fz - 0.025), CREW_RED, v,
			Vector3(0, 0, PI + 0.25 + i * 0.35))
	# Name badge, wings pin, buttons, belt line and the skirt.
	part(box(Vector3(0.11, 0.04, 0.01)), Vector3(-0.1 * w, 0.16, fz - 0.006), Color(0.98, 0.98, 0.98), v)
	part(box(Vector3(0.11, 0.012, 0.012)), Vector3(-0.1 * w, 0.14, fz - 0.007), CREW_RED, v)
	_gold(box(Vector3(0.08, 0.016, 0.008)), Vector3(-0.1 * w, 0.205, fz - 0.008), v)
	for row in 2:
		_gold(sphere(0.017), Vector3(0, -0.02 - row * 0.1, fz - 0.012), v)
	part(cyl(0.243, 0.243, 0.03), Vector3(0, -0.17, 0), CREW_RED, v, Vector3.ZERO, Vector3(w, 1, 0.66 * w))
	part(cyl(0.25 * w, 0.3 * w, 0.46), Vector3(0, -0.42, 0), _top, v, Vector3.ZERO, Vector3(1, 1, 0.75))
	part(cyl(0.302 * w, 0.302 * w, 0.025), Vector3(0, -0.64, 0), CREW_RED, v, Vector3.ZERO, Vector3(1, 1, 0.75))


func _passenger_torso(v: Node3D, fz: float) -> void:
	match _outfit:
		Outfit.HOODIE:
			_hoodie(v, fz)
		Outfit.HAWAIIAN:
			_hawaiian(v, fz)
		Outfit.SWEATER:
			_sweater(v, fz)
		Outfit.DRESS:
			_dress(v, fz)
		_:
			_shirt(v, fz)
	if extra.get("necklace", false):
		_gold(torus(0.085, 0.1), Vector3(0, 0.32, -0.02), v, Vector3(0.35, 0, 0))
	if extra.get("pillow", false):
		part(torus(0.1, 0.18), Vector3(0, 0.36, 0.03), extra.get("hat_color", Color(0.4, 0.6, 1.0)), v,
			Vector3(0.15, 0, 0), Vector3(1, 1.6, 1))
	if extra.get("backpack", false):
		var bc: Color = extra.get("bag_color", Color(0.3, 0.5, 0.3))
		part(box(Vector3(0.36 * w, 0.42, 0.16)), Vector3(0, 0.02, 0.2 * w), bc, v, Vector3.ZERO, Vector3.ONE, 0.6)
		part(box(Vector3(0.3 * w, 0.14, 0.06)), Vector3(0, -0.1, 0.3 * w), bc.darkened(0.2), v)
		for sx in [-1.0, 1.0]:
			part(box(Vector3(0.04, 0.4, 0.02)), Vector3(sx * 0.12 * w, 0.06, 0.12 * w), bc.darkened(0.3), v)


## Button-up shirt: collar band and points, placket (or tie), pocket and side seams.
func _shirt(v: Node3D, fz: float) -> void:
	var collar: Color = _top.lightened(0.35)
	var seam := _top.darkened(0.12)
	part(torus(0.068, 0.098), Vector3(0, 0.315, 0), collar, v, Vector3(0.12, 0, 0))
	for sx in [-1.0, 1.0]:
		part(prism(Vector3(0.09, 0.1, 0.03)), Vector3(sx * 0.05, 0.3, fz + 0.01), collar, v,
			Vector3(0, 0, PI - sx * 0.6))
		part(box(Vector3(0.012, 0.42, 0.04)), Vector3(sx * 0.235 * w, 0.03, 0), seam, v)
	if extra.get("tie", false):
		_tie(v, fz, extra.get("tie_color", Color(0.8, 0.1, 0.15)))
	else:
		part(box(Vector3(0.035, 0.4, 0.008)), Vector3(0, 0.06, fz - 0.003), seam, v)
		for i in 4:
			part(sphere(0.014), Vector3(0, 0.22 - i * 0.1, fz - 0.008), collar, v)
	part(box(Vector3(0.09, 0.1, 0.012)), Vector3(0.1 * w, 0.14, fz + 0.004), seam, v)
	part(box(Vector3(0.092, 0.014, 0.014)), Vector3(0.1 * w, 0.19, fz + 0.002), seam.darkened(0.1), v)


## Hoodie: hood bunched behind the neck, drawstrings, kangaroo pocket, ribbed hem.
func _hoodie(v: Node3D, fz: float) -> void:
	var dark := _top.darkened(0.18)
	part(torus(0.075, 0.13), Vector3(0, 0.33, 0.04), _top, v, Vector3(0.35, 0, 0), Vector3(1, 1.6, 1))
	part(sphere(0.5, false, 12), Vector3(0, 0.3, 0.15), _top, v, Vector3(0.4, 0, 0), Vector3(0.3, 0.22, 0.14))
	for sx in [-1.0, 1.0]:
		part(capsule(0.009, 0.14), Vector3(sx * 0.04, 0.22, fz - 0.012), SHIRT_WHITE, v)
	part(box(Vector3(0.3 * w, 0.13, 0.03)), Vector3(0, -0.05, fz - 0.005), dark, v)
	part(box(Vector3(0.012, 0.36, 0.03)), Vector3(0, 0.1, fz - 0.002), dark, v)
	part(cyl(0.245, 0.245, 0.06), Vector3(0, -0.16, 0), dark, v, Vector3.ZERO,
		Vector3(w, 1, 0.66 * w + (0.1 if belly else 0.0)))


## Hawaiian shirt: wide open collar and big flowers all round (front, back, sides).
func _hawaiian(v: Node3D, fz: float) -> void:
	var collar: Color = _top.lightened(0.25)
	var flower: Color = (extra.get("hat_color", Color(1.0, 0.5, 0.2)) as Color).lightened(0.35)
	part(prism(Vector3(0.16, 0.2, 0.02)), Vector3(0, 0.25, fz - 0.002), _skin, v, Vector3(0, 0, PI), Vector3.ONE,
		SKIN_ROUGH)
	for sx in [-1.0, 1.0]:
		part(prism(Vector3(0.13, 0.15, 0.03)), Vector3(sx * 0.08, 0.27, fz + 0.002), collar, v,
			Vector3(0, 0, PI - sx * 0.8))
	for i in 12:
		var a := i * TAU / 12.0 + 0.3
		var y := 0.2 - (i % 3) * 0.15
		var pos := Vector3(cos(a) * 0.245 * w, y, sin(a) * 0.155 * w)
		var rot := Vector3(0, atan2(cos(a), sin(a)), 0)
		var c := flower if i % 2 == 0 else Color(0.98, 0.98, 0.92)
		part(sphere(0.045), pos, c, v, rot, Vector3(1, 1, 0.3))
		part(sphere(0.016), pos + Vector3(cos(a), 0, sin(a)) * 0.01, Color(1.0, 0.85, 0.2), v)


## Chunky sweater: ribbed neck, chest stripe, ribbed hem; a shirt collar peeks out.
func _sweater(v: Node3D, fz: float) -> void:
	var rib := _top.darkened(0.15)
	var stripe: Color = extra.get("hat_color", Color(0.95, 0.95, 0.95))
	part(torus(0.07, 0.105), Vector3(0, 0.315, 0), rib, v, Vector3(0.12, 0, 0))
	for sx in [-1.0, 1.0]:
		part(prism(Vector3(0.07, 0.08, 0.025)), Vector3(sx * 0.045, 0.3, fz + 0.005), SHIRT_WHITE, v,
			Vector3(0, 0, PI - sx * 0.6))
	part(cyl(0.252, 0.252, 0.07), Vector3(0, 0.1, -0.005), stripe, v, Vector3.ZERO, Vector3(w, 1, 0.68 * w))
	part(cyl(0.252, 0.252, 0.025), Vector3(0, 0.03, -0.005), stripe.darkened(0.2), v, Vector3.ZERO,
		Vector3(w, 1, 0.68 * w))
	part(cyl(0.245, 0.245, 0.07), Vector3(0, -0.16, 0), rib, v, Vector3.ZERO,
		Vector3(w, 1, 0.66 * w + (0.1 if belly else 0.0)))


## Dress: scooped neckline trim, sash, and a flared skirt to the knee.
func _dress(v: Node3D, _fz: float) -> void:
	var trim := _top.lightened(0.4)
	part(torus(0.075, 0.095), Vector3(0, 0.3, -0.01), trim, v, Vector3(0.3, 0, 0))
	part(cyl(0.247, 0.247, 0.05), Vector3(0, -0.14, 0), trim, v, Vector3.ZERO, Vector3(w, 1, 0.66 * w + (0.1 if belly else 0.0)))
	part(cyl(0.25, 0.32, 0.3), Vector3(0, -0.31, 0), _top, v, Vector3.ZERO, Vector3(w, 1, 0.72 * w))
	part(cyl(0.322, 0.322, 0.025), Vector3(0, -0.455, 0), trim, v, Vector3.ZERO, Vector3(w, 1, 0.72 * w))


## Lap belt for the seated pose (root-local, unit size). Returns the node to show/hide.
func build_seatbelt(v: Node3D) -> Node3D:
	var belt := holder(v, Vector3.ZERO)
	var half := 0.12 * w + 0.13
	var z := -0.1 - (0.05 if belly else 0.0)
	part(box(Vector3(half * 2.0, 0.03, 0.075)), Vector3(0, -0.215, z), BELT_STRAP, belt, Vector3(0.15, 0, 0))
	part(box(Vector3(0.09, 0.045, 0.06)), Vector3(0, -0.205, z - 0.01), Color(0.75, 0.77, 0.8), belt,
		Vector3(0.15, 0, 0), Vector3.ONE, 0.3, 0.8)
	part(box(Vector3(0.05, 0.02, 0.035)), Vector3(0, -0.18, z - 0.02), Color(0.9, 0.2, 0.2), belt)
	for sx in [-1.0, 1.0]:
		part(box(Vector3(0.03, 0.14, 0.07)), Vector3(sx * half, -0.28, z + 0.04), BELT_STRAP, belt, Vector3(0.35, 0, 0))
	_bake()
	belt.visible = false
	return belt


## The lower part of a uniform jacket, covering the belt and hips.
func _jacket_skirt(v: Node3D, hem: Color) -> void:
	part(cyl(0.24, 0.255, 0.2), Vector3(0, -0.24, 0), _top, v, Vector3.ZERO, Vector3(w, 1, 0.68 * w))
	part(cyl(0.257, 0.257, 0.02), Vector3(0, -0.345, 0), hem, v, Vector3.ZERO, Vector3(w, 1, 0.68 * w))


## White shirt V with lapels and an optional tie under a jacket.
func _shirt_front(v: Node3D, fz: float, shirt: Color, tie: Color) -> void:
	part(prism(Vector3(0.18, 0.24, 0.02)), Vector3(0, 0.22, fz - 0.002), shirt, v, Vector3(0, 0, PI))
	for sx in [-1.0, 1.0]:
		part(prism(Vector3(0.1, 0.26, 0.02)), Vector3(sx * 0.1, 0.19, fz - 0.008), _top.lightened(0.14), v,
			Vector3(0, 0, PI + sx * 0.25))
		part(box(Vector3(0.012, 0.3, 0.012)), Vector3(sx * 0.02, -0.12, fz - 0.004), _top.darkened(0.3), v)
	if tie.a > 0.0:
		_tie(v, fz - 0.008, tie)


func _tie(v: Node3D, fz: float, c: Color) -> void:
	part(sphere(0.033), Vector3(0, 0.29, fz - 0.012), c, v, Vector3.ZERO, Vector3(1, 0.8, 0.6), 0.5)
	part(prism(Vector3(0.09, 0.3, 0.018)), Vector3(0, 0.12, fz - 0.014), c, v, Vector3(0, 0, PI), Vector3.ONE, 0.5)
	part(box(Vector3(0.09, 0.012, 0.02)), Vector3(0, 0.17, fz - 0.016), c.lightened(0.3), v)


# --- Head ------------------------------------------------------------------------------

func build_head(v: Node3D) -> void:
	_skin_part(sphere(0.2), Vector3.ZERO, v, Vector3.ZERO, Vector3(1, 1.08, 1))
	_skin_part(sphere(0.5, false, 12), Vector3(0, -0.085, -0.03), v, Vector3.ZERO, Vector3(0.34, 0.2, 0.33))
	_skin_part(sphere(0.05), Vector3(0, -0.16, -0.12), v, Vector3.ZERO, Vector3(1.2, 0.7, 0.9))
	for sx in [-1.0, 1.0]:
		# Ears with an inner fold; cheeks.
		_skin_part(sphere(0.05), Vector3(sx * 0.205, -0.005, 0.01), v, Vector3(0, 0, -sx * 0.15), Vector3(0.5, 1, 0.8))
		_skin_part(sphere(0.025), Vector3(sx * 0.222, -0.005, 0.0), v, Vector3.ZERO, Vector3(0.5, 1.2, 0.8),
			_skin.darkened(0.18))
		_skin_part(sphere(0.04), Vector3(sx * 0.125, -0.075, -0.155), v, Vector3.ZERO, Vector3(1, 0.6, 0.35),
			_skin.lerp(Color(1, 0.3, 0.35), 0.3))
		_build_eye(v, sx)
		var brow := holder(v, Vector3(sx * 0.085, BROW_Y, -0.178), Vector3(0, 0, PI / 2))
		part(capsule(0.015, 0.1), Vector3.ZERO, _hair.darkened(0.25), brow, Vector3.ZERO, Vector3(1, 1, 0.8))
		_brows.append(brow)
	var nose: float = extra.get("nose", 1.0)
	_skin_part(sphere(0.04 * nose), Vector3(0, -0.05, -0.205), v, Vector3.ZERO, Vector3(1.1, 1.0, 1.15),
		_skin.darkened(0.06))
	for sx in [-1.0, 1.0]:
		_skin_part(sphere(0.019 * nose), Vector3(sx * 0.028 * nose, -0.065, -0.198), v, Vector3.ZERO, Vector3.ONE,
			_skin.darkened(0.08))
	_build_mouth(v)
	if extra.get("stache", false) or role == "captain":
		var stache := _hair.darkened(0.15)
		for sx in [-1.0, 1.0]:
			part(capsule(0.024, 0.1), Vector3(sx * 0.038, -0.092, -0.2), stache, v, Vector3(0, 0, PI / 2 + sx * 0.25),
				Vector3.ONE, 0.6)
	if extra.get("beard", false):
		part(sphere(0.5, false, 12), Vector3(0, -0.13, -0.08), _hair, v, Vector3.ZERO, Vector3(0.36, 0.2, 0.28), 0.6)
		for sx in [-1.0, 1.0]:
			part(capsule(0.03, 0.14), Vector3(sx * 0.17, -0.06, -0.06), _hair, v, Vector3(0.3, 0, -sx * 0.2), Vector3.ONE, 0.6)
	var hat := int(extra.get("hat", 0))
	var style := int(extra.get("style", 0)) % HAIR_STYLES
	if role == "attendant":
		style = 5
	elif role == "captain" or hat == 2 or hat == 4:
		style = 2 if style == 2 or style == 13 else 0
	_build_hair(v, style)
	_build_hat(v, hat)
	_build_head_extras(v)
	_bake()


## A big googly eye: glossy white ball, small black pupil that wobbles (see set_face), lid.
func _build_eye(v: Node3D, sx: float) -> void:
	var eye := holder(v, Vector3(sx * 0.08, 0.05, -0.16), Vector3(0, -sx * 0.12, 0), Vector3(1, 1.08, 0.85))
	part(sphere(EYE_R, false, 14), eye.position, Color(0.99, 0.99, 0.99), v, eye.rotation, eye.scale, 0.2)
	var pupil := holder(eye, Vector3(0, -0.01, -EYE_R))
	part(sphere(PUPIL_R, false, 10), Vector3.ZERO, Color(0.03, 0.03, 0.05), pupil, Vector3.ZERO, Vector3(1, 1, 0.45), 0.15)
	part(sphere(0.007), Vector3(0.009, 0.01, -0.008), Color(1, 1, 1), pupil, Vector3.ZERO, Vector3.ONE, 0.15)
	_pupils.append(pupil)
	var lid := holder(eye, Vector3.ZERO)
	part(sphere(EYE_R + 0.006, true, 14), Vector3.ZERO, _skin.darkened(0.06), lid, Vector3.ZERO, Vector3.ONE, SKIN_ROUGH)
	if role == "attendant" or extra.get("earrings", false):
		part(box(Vector3(0.1, 0.01, 0.022)), Vector3(sx * 0.01, 0.006, -EYE_R - 0.004), Color(0.05, 0.04, 0.05), lid,
			Vector3(-0.5, 0, sx * 0.15))
	_lids.append(lid)
	var x := holder(v, Vector3(sx * 0.08, 0.05, -0.235))
	x.visible = false
	for r in [0.785, -0.785]:
		part(box(Vector3(0.11, 0.022, 0.012)), Vector3.ZERO, Color(0.05, 0.05, 0.05), x, Vector3(0, 0, r))
	_xeyes.append(x)


func _build_mouth(v: Node3D) -> void:
	var lip := Color(0.75, 0.08, 0.15) if role == "attendant" else _skin.lerp(Color(0.5, 0.12, 0.14), 0.75)
	_mouth_shut = holder(v, Vector3(0, -0.122, -0.183))
	part(capsule(0.012, 0.09), Vector3.ZERO, lip, _mouth_shut, Vector3(0, 0, PI / 2), Vector3.ONE, 0.4)
	for sx in [-1.0, 1.0]:
		part(capsule(0.011, 0.04), Vector3(sx * 0.05, 0.01, 0.002), lip, _mouth_shut, Vector3(0, 0, sx * 0.9),
			Vector3.ONE, 0.4)
	_mouth_open = holder(v, Vector3(0, -0.13, -0.175))
	_mouth_open.visible = false
	part(sphere(0.06), Vector3.ZERO, Color(0.22, 0.03, 0.05), _mouth_open, Vector3.ZERO, Vector3(1, 1.2, 0.5))
	part(torus(0.05, 0.064), Vector3(0, 0, -0.012), lip, _mouth_open, Vector3(PI / 2, 0, 0), Vector3(1, 1, 1.2), 0.4)
	part(box(Vector3(0.075, 0.018, 0.02)), Vector3(0, 0.05, -0.018), Color(1, 1, 0.97), _mouth_open)
	part(sphere(0.03), Vector3(0, -0.04, -0.016), Color(0.95, 0.4, 0.45), _mouth_open, Vector3.ZERO, Vector3(1.4, 0.6, 1))


## The skull cap of hair, the back down to the nape, and short sideburns.
func _hair_base(v: Node3D, c: Color, sideburns := true) -> void:
	part(sphere(0.222), Vector3(0, 0.07, 0.02), c, v, Vector3.ZERO, Vector3(1, 0.62, 1), 0.6)
	part(sphere(0.5, false, 12), Vector3(0, -0.01, 0.075), c, v, Vector3.ZERO, Vector3(0.43, 0.42, 0.3), 0.6)
	if sideburns:
		for sx in [-1.0, 1.0]:
			part(box(Vector3(0.02, 0.08, 0.035)), Vector3(sx * 0.192, 0.0, -0.035), c, v, Vector3(0, 0, sx * 0.1))


func _build_hair(v: Node3D, style: int) -> void:
	var c := _hair
	match style:
		0:  # Short crop with a side-parted fringe.
			_hair_base(v, c)
			part(sphere(0.5, false, 10), Vector3(0.03, 0.17, -0.14), c, v, Vector3(0.3, 0, -0.25), Vector3(0.3, 0.09, 0.14), 0.6)
		1:  # Towering bouffant.
			_hair_base(v, c, false)
			part(sphere(0.26), Vector3(0, 0.17, 0.05), c, v, Vector3.ZERO, Vector3.ONE, 0.6)
			part(sphere(0.17), Vector3(0, 0.38, 0.05), c, v, Vector3.ZERO, Vector3.ONE, 0.6)
		2:  # Bald with clown tufts.
			for sx in [-1.0, 1.0]:
				part(sphere(0.085), Vector3(sx * 0.2, 0.06, 0.05), c, v, Vector3.ZERO, Vector3(1, 0.9, 1.3), 0.6)
		3:  # Mohawk over shaved sides.
			part(sphere(0.215), Vector3(0, 0.05, 0.02), _skin.darkened(0.12), v, Vector3.ZERO, Vector3(1, 0.6, 1))
			part(capsule(0.045, 0.42), Vector3(0, 0.2, 0.03), c, v, Vector3(PI / 2, 0, 0), Vector3(1, 1, 1.9), 0.6)
		4:  # Bob with a fringe.
			part(sphere(0.23), Vector3(0, 0.09, 0.03), c, v, Vector3.ZERO, Vector3(1.05, 0.68, 1.02), 0.6)
			part(sphere(0.21), Vector3(0, -0.02, 0.09), c, v, Vector3.ZERO, Vector3(1.06, 0.95, 0.65), 0.6)
			for sx in [-1.0, 1.0]:
				part(capsule(0.06, 0.3), Vector3(sx * 0.19, -0.04, 0.03), c, v, Vector3.ZERO, Vector3.ONE, 0.6)
		5:  # Neat bun.
			_hair_base(v, c, false)
			part(sphere(0.09), Vector3(0, 0.15, 0.19), c, v, Vector3.ZERO, Vector3.ONE, 0.6)
			part(torus(0.07, 0.09), Vector3(0, 0.12, 0.15), c.darkened(0.2), v, Vector3(1.0, 0, 0))
		6:  # Enormous afro.
			part(sphere(0.3), Vector3(0, 0.16, 0.1), c, v, Vector3.ZERO, Vector3.ONE, 0.8)
		7:  # Ponytail.
			_hair_base(v, c)
			part(capsule(0.055, 0.32), Vector3(0, -0.02, 0.25), c, v, Vector3(0.5, 0, 0), Vector3.ONE, 0.6)
			part(torus(0.04, 0.06), Vector3(0, 0.1, 0.2), Color(0.95, 0.3, 0.5), v, Vector3(1.1, 0, 0))
		8:  # Spiky.
			_hair_base(v, c)
			for i in 7:
				var a := i * TAU / 7.0
				part(prism(Vector3(0.09, 0.16, 0.09)), Vector3(cos(a) * 0.11, 0.2, sin(a) * 0.11), c, v,
					Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5))
		9:  # Pigtails.
			_hair_base(v, c)
			for sx in [-1.0, 1.0]:
				part(sphere(0.03), Vector3(sx * 0.2, 0.05, 0.06), Color(1, 0.3, 0.5), v)
				part(capsule(0.05, 0.24), Vector3(sx * 0.25, -0.04, 0.07), c, v, Vector3(0, 0, sx * 0.4), Vector3.ONE, 0.6)
		10:  # Long and straight, down past the shoulders.
			_hair_base(v, c, false)
			part(box(Vector3(0.36, 0.42, 0.08)), Vector3(0, -0.12, 0.15), c, v, Vector3(0.12, 0, 0), Vector3.ONE, 0.6)
			for sx in [-1.0, 1.0]:
				part(capsule(0.05, 0.4), Vector3(sx * 0.18, -0.1, 0.04), c, v, Vector3(0, 0, sx * 0.08), Vector3.ONE, 0.6)
		11:  # Curls all round.
			_hair_base(v, c, false)
			for i in 9:
				var a := i * TAU / 9.0
				part(sphere(0.07), Vector3(cos(a) * 0.17, 0.12 + 0.03 * sin(a * 2.0), sin(a) * 0.16 + 0.02), c, v,
					Vector3.ZERO, Vector3.ONE, 0.8)
			part(sphere(0.08), Vector3(0, 0.22, 0.02), c, v, Vector3.ZERO, Vector3.ONE, 0.8)
		12:  # Quiff.
			_hair_base(v, c)
			part(capsule(0.07, 0.26), Vector3(0, 0.2, -0.08), c, v, Vector3(0, 0, PI / 2), Vector3(1, 1, 1.4), 0.4)
			part(sphere(0.08), Vector3(0, 0.23, -0.15), c, v, Vector3.ZERO, Vector3(1.3, 0.8, 1), 0.4)
		_:  # Comb-over on a bald patch.
			part(sphere(0.5, false, 12), Vector3(0, -0.01, 0.075), c, v, Vector3.ZERO, Vector3(0.43, 0.38, 0.3), 0.6)
			for i in 3:
				part(capsule(0.012, 0.3), Vector3(0, 0.205 - i * 0.012, -0.04 + i * 0.05), c, v,
					Vector3(0, 0, PI / 2 + 0.15), Vector3(1, 1, 0.6))


func _build_hat(v: Node3D, hat: int) -> void:
	var hc: Color = extra.get("hat_color", Color(0.9, 0.2, 0.2))
	match role:
		"captain":
			part(cyl(0.24, 0.215, 0.11), Vector3(0, 0.225, 0.01), NAVY, v)
			part(cyl(0.245, 0.245, 0.02), Vector3(0, 0.285, 0.01), Color(0.98, 0.98, 1.0), v)
			_gold(cyl(0.218, 0.218, 0.03), Vector3(0, 0.185, 0.01), v)
			part(cyl(0.14, 0.14, 0.02), Vector3(0, 0.165, -0.17), Color(0.03, 0.03, 0.05), v, Vector3(0.2, 0, 0),
				Vector3(1, 1, 0.7), 0.2)
			_gold(sphere(0.035), Vector3(0, 0.235, -0.225), v)
			for sx in [-1.0, 1.0]:
				_gold(prism(Vector3(0.07, 0.03, 0.01)), Vector3(sx * 0.055, 0.24, -0.226), v, Vector3(0, 0, sx * 1.3))
		"attendant":
			part(cyl(0.1, 0.11, 0.08), Vector3(0.06, 0.225, 0.0), CREW_RED, v, Vector3(0, 0, -0.2))
			part(cyl(0.112, 0.112, 0.015), Vector3(0.055, 0.195, 0.0), NAVY, v, Vector3(0, 0, -0.2))
			_gold(box(Vector3(0.05, 0.02, 0.01)), Vector3(0.05, 0.225, -0.105), v, Vector3(0, 0, -0.2))
		_:
			match hat:
				1:  # Baseball cap.
					part(sphere(0.226), Vector3(0, 0.1, 0.01), hc, v, Vector3.ZERO, Vector3(1, 0.6, 1))
					part(cyl(0.13, 0.13, 0.02), Vector3(0, 0.15, -0.2), hc.darkened(0.2), v, Vector3(0.12, 0, 0),
						Vector3(1, 1, 1.15))
					part(sphere(0.025), Vector3(0, 0.215, 0.0), hc.darkened(0.2), v)
				2:  # Top hat.
					part(cyl(0.15, 0.15, 0.3), Vector3(0, 0.33, 0.0), Color(0.08, 0.08, 0.08), v, Vector3.ZERO,
						Vector3.ONE, 0.4)
					part(cyl(0.152, 0.152, 0.05), Vector3(0, 0.22, 0.0), hc, v)
					part(cyl(0.26, 0.26, 0.02), Vector3(0, 0.19, 0.0), Color(0.08, 0.08, 0.08), v)
				3:  # Bobble beanie.
					part(sphere(0.228), Vector3(0, 0.1, 0.01), hc, v, Vector3.ZERO, Vector3(1, 0.75, 1))
					part(torus(0.2, 0.235), Vector3(0, 0.12, 0.02), hc.lightened(0.3), v, Vector3(-0.15, 0, 0))
					part(sphere(0.06), Vector3(0, 0.27, 0.01), Color(0.98, 0.98, 0.98), v)
				4:  # Floppy sun hat.
					part(sphere(0.226), Vector3(0, 0.1, 0.01), hc, v, Vector3.ZERO, Vector3(1, 0.65, 1))
					part(cyl(0.36, 0.38, 0.02), Vector3(0, 0.15, 0.02), hc, v, Vector3(-0.12, 0, 0))
					part(cyl(0.23, 0.23, 0.04), Vector3(0, 0.17, 0.01), Color(0.3, 0.2, 0.1), v)


func _build_head_extras(v: Node3D) -> void:
	var glasses := int(extra.get("glasses", 0))
	if glasses > 0:
		var gc: Color = extra.get("glasses_color", Color(0.1, 0.1, 0.1))
		for sx in [-1.0, 1.0]:
			if glasses == 2:
				part(sphere(0.08), Vector3(sx * 0.08, 0.05, -0.235), Color(0.05, 0.05, 0.08), v, Vector3.ZERO,
					Vector3(1.05, 0.9, 0.3), 0.1, 0.5)
			else:
				part(torus(0.07, 0.082), Vector3(sx * 0.08, 0.05, -0.24), gc, v, Vector3(PI / 2, 0, 0), Vector3.ONE,
					0.3, 0.4)
			part(box(Vector3(0.012, 0.012, 0.24)), Vector3(sx * 0.175, 0.06, -0.12), gc, v)
	if extra.get("phones", false):
		var pc := Color(0.15, 0.15, 0.18)
		part(box(Vector3(0.46, 0.03, 0.05)), Vector3(0, 0.25, 0.0), pc, v, Vector3.ZERO, Vector3.ONE, 0.4)
		for sx in [-1.0, 1.0]:
			part(box(Vector3(0.03, 0.24, 0.05)), Vector3(sx * 0.225, 0.13, 0.0), pc, v, Vector3.ZERO, Vector3.ONE, 0.4)
			part(cyl(0.06, 0.06, 0.05), Vector3(sx * 0.225, 0.0, 0.0), Color(0.95, 0.3, 0.3), v,
				Vector3(0, 0, PI / 2), Vector3.ONE, 0.4)
	if extra.get("earrings", false):
		for sx in [-1.0, 1.0]:
			_gold(torus(0.015, 0.028), Vector3(sx * 0.21, -0.07, 0.0), v, Vector3(0, PI / 2, PI / 2))
	if extra.get("mask", false):
		var mc: Color = extra.get("hat_color", Color(0.4, 0.3, 0.8))
		part(torus(0.2, 0.215), Vector3(0, 0.15, 0.0), mc, v, Vector3(0.15, 0, 0))
		for sx in [-1.0, 1.0]:
			part(sphere(0.06), Vector3(sx * 0.075, 0.19, -0.165), mc, v, Vector3(-0.4, 0, 0), Vector3(1.2, 0.8, 0.4))


# --- Limbs -----------------------------------------------------------------------------

## Bare forearms: Hawaiian shirts always, shirts and dresses when short-sleeved.
func _bare_arms() -> bool:
	if role != "passenger":
		return false
	if _outfit == Outfit.HAWAIIAN:
		return true
	return (_outfit == Outfit.SHIRT or _outfit == Outfit.DRESS) and extra.get("short_sleeves", false)


func build_upper_arm(v: Node3D) -> void:
	if _bare_arms():
		part(capsule(0.08, 0.2), Vector3(0, 0.07, 0), _top, v)
		part(torus(0.064, 0.084), Vector3(0, 0.0, 0), _top.darkened(0.12), v)
		_skin_part(capsule(0.064, 0.26), Vector3(0, -0.03, 0), v)
		if _outfit == Outfit.HAWAIIAN:
			var flower: Color = (extra.get("hat_color", Color(1.0, 0.5, 0.2)) as Color).lightened(0.35)
			part(sphere(0.04), Vector3(0, 0.1, -0.075), flower, v, Vector3.ZERO, Vector3(1, 1, 0.3))
			part(sphere(0.04), Vector3(0.075, 0.04, 0), Color(0.98, 0.98, 0.92), v, Vector3(0, PI / 2, 0), Vector3(1, 1, 0.3))
	else:
		part(capsule(0.077, 0.34), Vector3.ZERO, _top, v, Vector3.ZERO, Vector3(1, 1, 0.95))
	part(torus(0.07, 0.088), Vector3(0, 0.12, 0), _top.darkened(0.12), v)
	_bake()


func build_forearm(v: Node3D, right: bool) -> void:
	var bare := _bare_arms()
	if bare:
		_skin_part(capsule(0.06, 0.3), Vector3(0, 0.02, 0), v)
	else:
		part(capsule(0.066, 0.26), Vector3(0, 0.04, 0), _top, v)
		var knit := _outfit == Outfit.HOODIE or _outfit == Outfit.SWEATER
		var cuff := SHIRT_WHITE if role != "passenger" else (_top.darkened(0.18) if knit else _top.lightened(0.3))
		part(cyl(0.058, 0.062, 0.04), Vector3(0, -0.1, 0), cuff, v)
		if role == "captain":
			for i in 4:
				_gold(torus(0.064, 0.071), Vector3(0, -0.065 + i * 0.022, 0), v)
		elif role == "attendant":
			_gold(torus(0.064, 0.071), Vector3(0, -0.06, 0), v)
	_build_hand(v, right)
	if not right and extra.get("watch", false):
		part(torus(0.05, 0.066), Vector3(0, -0.11 if bare else -0.125, 0), Color(0.15, 0.15, 0.15), v)
		_gold(cyl(0.028, 0.028, 0.02), Vector3(0, -0.11 if bare else -0.125, -0.06), v, Vector3(PI / 2, 0, 0))
	if right:
		_build_phone(v)
	elif extra.get("bag", false):
		var bc: Color = extra.get("bag_color", Color(0.6, 0.2, 0.4))
		part(box(Vector3(0.09, 0.2, 0.26)), Vector3(-0.06, -0.33, 0), bc, v, Vector3.ZERO, Vector3.ONE, 0.5)
		part(box(Vector3(0.092, 0.06, 0.262)), Vector3(-0.06, -0.26, 0), bc.darkened(0.15), v, Vector3.ZERO, Vector3.ONE, 0.5)
		part(torus(0.07, 0.085), Vector3(-0.06, -0.2, 0), bc.darkened(0.3), v, Vector3(0, 0, PI / 2))
		_gold(box(Vector3(0.095, 0.03, 0.06)), Vector3(-0.06, -0.26, 0), v)
	_bake()


## Wrist, palm, four curled fingers and a thumb on the inner side. Palm faces -z/+z.
func _build_hand(v: Node3D, right: bool) -> void:
	var inward := -1.0 if right else 1.0
	_skin_part(cyl(0.04, 0.045, 0.05), Vector3(0, -0.13, 0), v)
	_skin_part(sphere(0.5, false, 10), Vector3(0, -0.18, -0.005), v, Vector3.ZERO, Vector3(0.11, 0.12, 0.06))
	var lengths := [0.055, 0.065, 0.062, 0.05]
	for i in 4:
		var fx := (-0.039 + i * 0.026) * inward
		var len: float = lengths[i] if inward > 0.0 else lengths[3 - i]
		_skin_part(capsule(0.014, len), Vector3(fx, -0.24 - len * 0.2, -0.012), v, Vector3(0.35, 0, 0))
	_skin_part(capsule(0.017, 0.07), Vector3(inward * 0.05, -0.17, -0.03), v, Vector3(0.5, 0, inward * 0.5))


func _build_phone(v: Node3D) -> void:
	_phone = holder(v, Vector3(0, -0.21, -0.06), Vector3(-0.3, 0, 0))
	_phone.visible = false
	part(box(Vector3(0.085, 0.16, 0.014)), Vector3.ZERO, Color(0.1, 0.1, 0.12), _phone, Vector3.ZERO, Vector3.ONE, 0.3)
	var screen := MeshInstance3D.new()
	screen.mesh = box(Vector3(0.07, 0.13, 0.004))
	screen.material_override = glow_mat(Color(0.4, 0.75, 1.0), 1.2)
	screen.position = Vector3(0, 0, 0.009)
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_phone.add_child(screen)
	var rec := MeshInstance3D.new()
	rec.mesh = sphere(0.008)
	rec.material_override = glow_mat(Color(1, 0.1, 0.1), 3.0)
	rec.position = Vector3(0.025, 0.05, 0.012)
	rec.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_phone.add_child(rec)


func build_thigh(v: Node3D) -> void:
	var dress := _outfit == Outfit.DRESS
	var c := _top if dress else _leg_color()
	part(capsule(0.097, 0.48), Vector3.ZERO, c, v, Vector3.ZERO, Vector3(1, 1, 1.05), 0.7 if role == "attendant" else 0.8)
	if role == "passenger" and not dress:
		part(box(Vector3(0.01, 0.36, 0.012)), Vector3(0.096, 0.0, 0), c.darkened(0.15), v)
	_bake()


func build_shin(v: Node3D) -> void:
	var dress := _outfit == Outfit.DRESS
	var leg := _skin if dress else _leg_color()
	part(capsule(0.085, 0.36), Vector3(0, 0.03, 0), leg, v, Vector3.ZERO, Vector3.ONE,
		SKIN_ROUGH if dress else (0.7 if role == "attendant" else 0.8))
	if role == "attendant":
		_pump(v)
	else:
		if not dress:
			part(cyl(0.092, 0.097, 0.035), Vector3(0, -0.11, 0), leg.darkened(0.12), v)
			part(cyl(0.07, 0.072, 0.05), Vector3(0, -0.145, 0), extra.get("socks", Color(0.95, 0.95, 0.95)), v)
		_shoe(v)
	_bake()


## Rounded lace-up shoe: upper, toe cap, sole, heel and laces. Crew wear polished black.
func _shoe(v: Node3D) -> void:
	var shiny := role == "captain"
	var shoe: Color = Color(0.06, 0.06, 0.07) if shiny else extra.get("shoes", Color(0.12, 0.1, 0.1))
	var rough := 0.2 if shiny else 0.7
	var sole := Color(0.1, 0.1, 0.1) if shiny else SOLE
	part(capsule(0.072, 0.27), Vector3(0, -0.19, -0.045), shoe, v, Vector3(PI / 2, 0, 0), Vector3(1, 1, 0.66), rough)
	part(sphere(0.07), Vector3(0, -0.2, -0.13), shoe, v, Vector3.ZERO, Vector3(1.02, 0.62, 1), rough)
	part(box(Vector3(0.15, 0.028, 0.29)), Vector3(0, -0.236, -0.05), sole, v, Vector3.ZERO, Vector3.ONE, 0.8)
	part(box(Vector3(0.14, 0.035, 0.07)), Vector3(0, -0.22, 0.06), sole.darkened(0.15), v)
	if not shiny:
		for i in 3:
			part(box(Vector3(0.06, 0.01, 0.014)), Vector3(0, -0.148 - i * 0.012, -0.06 - i * 0.03),
				Color(0.98, 0.98, 0.98), v, Vector3(-0.35, 0, 0))
	else:
		part(box(Vector3(0.09, 0.01, 0.06)), Vector3(0, -0.153, -0.06), shoe.lightened(0.05), v, Vector3(-0.3, 0, 0), Vector3.ONE, 0.2)


## Navy court shoe with a heel, worn over tights.
func _pump(v: Node3D) -> void:
	var c := Color(0.05, 0.06, 0.12)
	part(capsule(0.06, 0.24), Vector3(0, -0.2, -0.06), c, v, Vector3(PI / 2 - 0.15, 0, 0), Vector3(1, 1, 0.58), 0.2)
	part(box(Vector3(0.12, 0.02, 0.2)), Vector3(0, -0.24, -0.09), c.darkened(0.3), v)
	part(box(Vector3(0.035, 0.08, 0.035)), Vector3(0, -0.225, 0.05), c, v, Vector3.ZERO, Vector3.ONE, 0.2)


func _leg_color() -> Color:
	if role == "attendant":
		return _skin.darkened(0.15).lerp(Color(0.3, 0.25, 0.25), 0.25)
	if role == "captain":
		return NAVY
	return extra.get("pants", Color(0.2, 0.22, 0.3))


# --- Face ------------------------------------------------------------------------------

## Updates the expression. `t` is a running clock for blinking and screaming wobble.
func set_face(face: Face, t: float, dt: float, phone: bool) -> void:
	_phone.visible = phone
	var out := face == Face.OUT
	for x in _xeyes:
		x.visible = out
	_blink_t -= dt
	if _blink_t < -0.12:
		_blink_t = randf_range(2.0, 5.0)
		_gaze = Vector2(randf_range(-0.025, 0.025), randf_range(-0.01, 0.012)) if randf() < 0.6 else Vector2.ZERO
	var k := clampf(dt * 20.0, 0.0, 1.0)
	_update_wobble(dt)
	var jitter := Vector2(sin(t * 31.0), cos(t * 27.0)) * 0.01 if face == Face.SCARED else Vector2.ZERO
	var look := (_gaze + _wobble + jitter).limit_length(EYE_R - PUPIL_R - 0.006)
	var pupil_z := -sqrt(EYE_R * EYE_R - look.length_squared()) - 0.001
	for p in _pupils:
		p.visible = not out
		p.scale = Vector3.ONE * (0.75 if face == Face.SCARED else 1.0)
		p.position = Vector3(look.x, look.y, pupil_z)
	var lid := -PI / 2 if face == Face.CLOSED or out or _blink_t < 0.0 else \
		(PI / 2 if face == Face.SCARED or face == Face.HURT else 1.0)
	for l in _lids:
		l.visible = not out
		l.rotation.x = lerp_angle(l.rotation.x, lid, k)
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
		b.position.y = BROW_Y + (0.03 if face == Face.SCARED else (-0.01 if face == Face.HURT else 0.0))


## Googly pupils: a wobbly spring pulled toward the felt "down" of the eye, so they droop,
## slosh when the head moves and rattle when the person is thrown (purely cosmetic).
func _update_wobble(dt: float) -> void:
	var eye := _pupils[0].get_parent() as Node3D
	if dt <= 0.0 or not eye.is_inside_tree():
		return
	var gp := eye.global_position
	var vel := (gp - _eye_prev) / dt
	var acc := ((vel - _eye_vel) / dt).limit_length(80.0)
	if _eye_prev == Vector3.ZERO:
		acc = Vector3.ZERO
		vel = Vector3.ZERO
	_eye_prev = gp
	_eye_vel = vel
	var felt := eye.global_basis.orthonormalized().inverse() * (Vector3.DOWN * 9.8 - acc)
	var pull := Vector2(felt.x, felt.y) * 0.0005
	_wobble_v += ((pull - _wobble) * 60.0 - _wobble_v * 5.0) * dt
	_wobble = (_wobble + _wobble_v * dt).limit_length(0.04)
