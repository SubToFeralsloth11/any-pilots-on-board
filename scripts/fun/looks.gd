class_name FunLooks
extends RefCounted
## Shared cartoon building blocks for everything in scripts/fun: cached materials and primitive
## meshes (spheres, capsules, tapered cylinders, tori, prisms) plus small builders that place
## them. Caches are static, so 24 checkers cost one mesh and one material.

const WOOD := Color(0.55, 0.34, 0.2)
const WOOD_LIGHT := Color(0.8, 0.58, 0.34)
const WOOD_DARK := Color(0.32, 0.2, 0.13)
const BRASS := Color(0.9, 0.68, 0.28)
const CHROME := Color(0.82, 0.84, 0.88)
const INK := Color(0.1, 0.1, 0.12)
const CREAM := Color(0.97, 0.93, 0.84)
const LEATHER := Color(0.72, 0.17, 0.22)
const TEAL := Color(0.1, 0.55, 0.58)
const LEAF := Color(0.24, 0.62, 0.3)
const LEAF_DARK := Color(0.12, 0.42, 0.2)
const POT := Color(0.82, 0.43, 0.26)
const CONFETTI := [Color(1, 0.3, 0.35), Color(1, 0.85, 0.2), Color(0.3, 0.8, 1), Color(0.5, 1, 0.4),
	Color(0.85, 0.45, 1), Color(1, 0.6, 0.2)]

static var _mats := {}
static var _meshes := {}
static var _phys := {}


## Material per (colour, roughness, metallic, glow). Translucent colours get alpha blending.
static func mat(c: Color, rough := 0.65, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f/%.2f" % [c.to_html(), rough, metal, glow]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = Color(c.r, c.g, c.b)
			m.emission_energy_multiplier = glow
		if c.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[key] = m
	return _mats[key]


## Shiny metal shorthand.
static func metal(c: Color) -> StandardMaterial3D:
	return mat(c, 0.25, 0.85)


## Physics material per (friction, bounce).
static func phys(friction: float, bounce := 0.0) -> PhysicsMaterial:
	var key := "%.2f/%.2f" % [friction, bounce]
	if not _phys.has(key):
		var p := PhysicsMaterial.new()
		p.friction = friction
		p.bounce = bounce
		_phys[key] = p
	return _phys[key]


static func sphere(r: float, segments := 18) -> SphereMesh:
	var key := "s%.3f/%d" % [r, segments]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = segments
		m.rings = maxi(4, segments / 2)
		_meshes[key] = m
	return _meshes[key]


## Capsule along local Y.
static func capsule(r: float, h: float) -> CapsuleMesh:
	var key := "c%.3f/%.3f" % [r, h]
	if not _meshes.has(key):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = maxf(h, r * 2.0)
		m.radial_segments = 16
		m.rings = 6
		_meshes[key] = m
	return _meshes[key]


## Cylinder (or cone/taper) along local Y.
static func cyl(r_top: float, r_bottom: float, h: float, segments := 18) -> CylinderMesh:
	var key := "y%.3f/%.3f/%.3f/%d" % [r_top, r_bottom, h, segments]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = r_top
		m.bottom_radius = r_bottom
		m.height = h
		m.radial_segments = segments
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


## Ring lying in the local XZ plane.
static func torus(inner: float, outer: float) -> TorusMesh:
	var key := "t%.3f/%.3f" % [inner, outer]
	if not _meshes.has(key):
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 20
		m.ring_segments = 8
		_meshes[key] = m
	return _meshes[key]


static func prism(size: Vector3) -> PrismMesh:
	var key := "p%s" % size
	if not _meshes.has(key):
		var m := PrismMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func box(size: Vector3) -> BoxMesh:
	var key := "b%s" % size
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


## Places a mesh under `parent` with a shared material. `rot` is Euler radians (YXZ).
static func part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot := Vector3.ZERO,
		scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


## A box with rounded edges and corners: three crossed slabs, 8 corner spheres, 12 edge capsules.
static func rounded_box(parent: Node3D, size: Vector3, radius: float, material: Material,
		pos := Vector3.ZERO, rot := Vector3.ZERO) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation = rot
	parent.add_child(root)
	var r := minf(radius, minf(size.x, minf(size.y, size.z)) * 0.45)
	var inner := size - Vector3.ONE * r * 2.0
	part(root, box(Vector3(size.x, inner.y, inner.z)), material, Vector3.ZERO)
	part(root, box(Vector3(inner.x, size.y, inner.z)), material, Vector3.ZERO)
	part(root, box(Vector3(inner.x, inner.y, size.z)), material, Vector3.ZERO)
	var h := inner * 0.5
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				part(root, sphere(r, 10), material, Vector3(sx * h.x, sy * h.y, sz * h.z))
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			part(root, cyl(r, r, inner.y, 10), material, Vector3(a * h.x, 0, b * h.z))
			part(root, cyl(r, r, inner.x, 10), material, Vector3(0, a * h.y, b * h.z), Vector3(0, 0, PI / 2))
			part(root, cyl(r, r, inner.z, 10), material, Vector3(a * h.x, b * h.y, 0), Vector3(PI / 2, 0, 0))
	return root


static func label(parent: Node3D, text: String, pos: Vector3, size := 32, color := Color.WHITE,
		rot := Vector3.ZERO, pixel := 0.003) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = maxi(4, size / 6)
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.position = pos
	l.rotation = rot
	parent.add_child(l)
	return l


## Collision box bolted to the plane (shapes must be direct children of the plane body).
static func collider(plane: Airliner, size: Vector3, xform: Transform3D) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xform
	plane.add_child(cs)
	return cs
