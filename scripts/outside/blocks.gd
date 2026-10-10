extends RefCounted
## Bakes vertex-coloured cartoon geometry (flat boxes, roofs, cones, smooth ellipsoids and
## tapered cylinders) into one ArrayMesh. One baked mesh + one shared material = one draw call.

const AXES := [
	[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.BACK, Vector3.UP],
	[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
	[Vector3.BACK, Vector3.RIGHT, Vector3.UP], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
]

var _st := SurfaceTool.new()
var _count := 0


func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


## Shared opaque material that takes its colour from the vertices (and MultiMesh tints).
static func vertex_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	return m


## Bright unlit material for lights; fog never dims it so it reads from far away.
static func glow_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.disable_fog = true
	return m


func is_empty() -> bool:
	return _count == 0


## Triangle; `outward` picks the visible side so callers never think about winding.
func tri(a: Vector3, b: Vector3, c: Vector3, color: Color, outward: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(outward) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	_st.set_color(color)
	_st.set_normal(n)
	# Godot treats clockwise triangles as front-facing.
	for v in [a, c, b]:
		_st.add_vertex(v)
	_count += 1


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, outward: Vector3) -> void:
	tri(a, b, c, color, outward)
	tri(a, c, d, color, outward)


## Axis-aligned (in `xf` space) box. `bottom` = false skips the never-seen underside.
func box(size: Vector3, center: Vector3, color: Color, xf := Transform3D.IDENTITY, bottom := false) -> void:
	var h := size * 0.5
	for ax in AXES:
		var n: Vector3 = ax[0]
		if n == Vector3.DOWN and not bottom:
			continue
		var u: Vector3 = ax[1] * h
		var v: Vector3 = ax[2] * h
		var c := center + n * h
		var shade := color.darkened(0.12) if n.y == 0.0 and absf(n.x) > 0.0 else color
		quad(xf * (c - u - v), xf * (c + u - v), xf * (c + u + v), xf * (c - u + v), shade, xf.basis * n)


## Flat rectangle on the ground at height y (x/z extents, optional rotation about Y).
func flat(size: Vector2, center: Vector3, color: Color, yaw := 0.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	var u := b * Vector3(size.x * 0.5, 0, 0)
	var v := b * Vector3(0, 0, size.y * 0.5)
	quad(center - u - v, center + u - v, center + u + v, center - u + v, color, Vector3.UP)


## Gable roof (triangular prism) sitting on top of a box of `size` footprint, ridge along X.
func roof(size: Vector3, base_center: Vector3, color: Color, xf := Transform3D.IDENTITY) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var c := base_center
	var y1 := c.y + size.y
	var a1 := xf * (c + Vector3(-hx, 0, hz))
	var a2 := xf * (c + Vector3(hx, 0, hz))
	var b1 := xf * (c + Vector3(-hx, 0, -hz))
	var b2 := xf * (c + Vector3(hx, 0, -hz))
	var r1 := xf * Vector3(c.x - hx, y1, c.z)
	var r2 := xf * Vector3(c.x + hx, y1, c.z)
	quad(a1, a2, r2, r1, color, xf.basis * Vector3(0, 1, 1))
	quad(b1, b2, r2, r1, color.darkened(0.15), xf.basis * Vector3(0, 1, -1))
	tri(a1, b1, r1, color.darkened(0.25), xf.basis * Vector3.LEFT)
	tri(a2, b2, r2, color.darkened(0.25), xf.basis * Vector3.RIGHT)


## Band of a cone between two heights (frustum side only). Cone base at `base` with `radius`
## at height 0 and apex at `height`.
func cone_band(base: Vector3, radius: float, height: float, from_h: float, to_h: float,
		segments: int, color: Color) -> void:
	var r0 := radius * (1.0 - from_h / height)
	var r1 := radius * (1.0 - to_h / height)
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var out := (d0 + d1).normalized() + Vector3(0, 0.3, 0)
		var shade := color.darkened(0.18 * (0.5 + 0.5 * sin(a0 * 3.0)))
		var p0 := base + d0 * r0 + Vector3(0, from_h, 0)
		var p1 := base + d1 * r0 + Vector3(0, from_h, 0)
		if r1 <= 0.01:
			tri(p0, p1, base + Vector3(0, to_h, 0), shade, out)
		else:
			quad(p0, p1, base + d1 * r1 + Vector3(0, to_h, 0), base + d0 * r1 + Vector3(0, to_h, 0), shade, out)


## Flat irregular polygon (lakes, ponds) on the ground.
func blob(center: Vector3, radii: PackedFloat32Array, color: Color) -> void:
	var n := radii.size()
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		tri(center, center + Vector3(cos(a0), 0, sin(a0)) * radii[i],
			center + Vector3(cos(a1), 0, sin(a1)) * radii[(i + 1) % n], color, Vector3.UP)


## Smooth-shaded triangle with per-vertex normals (winding picked from the normals).
func tri_smooth(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, color: Color) -> void:
	if (b - a).cross(c - a).dot(na + nb + nc) < 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	_st.set_color(color)
	_st.set_normal(na)
	_st.add_vertex(a)
	_st.set_normal(nc)
	_st.add_vertex(c)
	_st.set_normal(nb)
	_st.add_vertex(b)
	_count += 1


## Smooth ellipsoid (rounded canopies, bodies, heads, balloons).
func ellipsoid(center: Vector3, radii: Vector3, color: Color, xf := Transform3D.IDENTITY,
		segs := 10, rings := 6) -> void:
	var nm := xf.basis.inverse().transposed()
	var pts: Array[Vector3] = []
	var nrm: Array[Vector3] = []
	for r in rings + 1:
		var t := PI * r / rings
		for s in segs + 1:
			var a := TAU * s / segs
			var u := Vector3(sin(t) * cos(a), cos(t), sin(t) * sin(a))
			pts.append(xf * (center + u * radii))
			nrm.append((nm * (u / radii)).normalized())
	var w := segs + 1
	for r in rings:
		for s in segs:
			var i00 := r * w + s
			var i01 := i00 + 1
			var i10 := i00 + w
			var i11 := i10 + 1
			if r > 0:
				tri_smooth(pts[i00], pts[i01], pts[i11], nrm[i00], nrm[i01], nrm[i11], color)
			if r < rings - 1:
				tri_smooth(pts[i00], pts[i11], pts[i10], nrm[i00], nrm[i11], nrm[i10], color)


## Smooth tapered cylinder / cone along local +Y from `base` (r1 = 0 makes a cone).
func cylinder(base: Vector3, r0: float, r1: float, h: float, color: Color, xf := Transform3D.IDENTITY,
		segs := 10, cap := true) -> void:
	var nm := xf.basis.inverse().transposed()
	var slope := (r0 - r1) / h
	var top := base + Vector3(0, h, 0)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n0 := (nm * (d0 + Vector3(0, slope, 0))).normalized()
		var n1 := (nm * (d1 + Vector3(0, slope, 0))).normalized()
		var b0 := xf * (base + d0 * r0)
		var b1 := xf * (base + d1 * r0)
		if r1 <= 0.001:
			tri_smooth(b0, b1, xf * top, n0, n1, (n0 + n1).normalized(), color)
			continue
		var t0 := xf * (top + d0 * r1)
		var t1 := xf * (top + d1 * r1)
		tri_smooth(b0, b1, t1, n0, n1, n1, color)
		tri_smooth(b0, t1, t0, n0, n1, n0, color)
		if cap:
			tri(xf * top, t0, t1, color.lightened(0.05), xf.basis * Vector3.UP)


## Transform whose local +Y points along `dir` from `origin` (for cylinders on any axis).
static func axis_xf(origin: Vector3, dir: Vector3) -> Transform3D:
	var up := dir.normalized()
	var side := Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD
	var z := side.cross(up).normalized()
	return Transform3D(Basis(up.cross(z).normalized(), up, z), origin)


## Thin double-sided triangle (sails, flags).
func sheet(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var n := (b - a).cross(c - a)
	tri(a, b, c, color, n)
	tri(a, b, c, color.darkened(0.1), -n)


func commit() -> ArrayMesh:
	return _st.commit()
