extends RefCounted
## Batches static, vertex-coloured geometry into one ArrayMesh with one surface per finish
## (matte, fabric, paint, metal, gloss, glow). A whole group of plane parts then costs a
## handful of draw calls instead of one per box. Also provides the parametric shapes the
## plane is modelled from: smooth grids, lofts, revolves, sweeps and rounded boxes.
##
## Winding is handled internally: callers only say which way a surface faces.

enum Finish { MATTE, FABRIC, PAINT, METAL, GLOSS, GLOW }

static var _materials := {}

var _surfaces := {}   ## Finish -> _Surface


## Raw vertex/index arrays for one finish.
class _Surface:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	func add(p: Vector3, n: Vector3, c: Color) -> int:
		verts.append(p)
		norms.append(n)
		cols.append(c)
		return verts.size() - 1

	func index(a: int, b: int, c: int) -> void:
		idx.append(a)
		idx.append(b)
		idx.append(c)


## Shared material for a finish; colour comes from the vertices.
static func material(finish: int) -> StandardMaterial3D:
	if not _materials.has(finish):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		match finish:
			Finish.MATTE:
				m.roughness = 0.75
			Finish.FABRIC:
				m.roughness = 1.0
				m.rim_enabled = true
				m.rim = 0.35
				m.rim_tint = 0.6
			Finish.PAINT:
				m.roughness = 0.32
				m.metallic = 0.08
			Finish.METAL:
				m.roughness = 0.3
				m.metallic = 0.75
			Finish.GLOSS:
				m.roughness = 0.12
				m.metallic_specular = 0.8
			Finish.GLOW:
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials[finish] = m
	return _materials[finish]


func is_empty() -> bool:
	return _surfaces.is_empty()


func _surf(finish: int) -> _Surface:
	if not _surfaces.has(finish):
		_surfaces[finish] = _Surface.new()
	return _surfaces[finish]


## Triangle whose visible side faces along `n` (vertex normals all n).
func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, color: Color, finish: int) -> void:
	var s := _surf(finish)
	n = n.normalized()
	var ia := s.add(a, n, color)
	var ib := s.add(b, n, color)
	var ic := s.add(c, n, color)
	# Godot treats clockwise triangles (seen from the front) as front-facing.
	if (b - a).cross(c - a).dot(n) > 0.0:
		s.index(ia, ic, ib)
	else:
		s.index(ia, ib, ic)


## Flat quad a-b-c-d (in order around the edge) facing along `n`.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, color: Color, finish: int) -> void:
	tri(a, b, c, n, color, finish)
	tri(a, c, d, n, color, finish)


## Flat-shaded box of `size` centred on xf's origin, aligned with xf's axes.
func box(size: Vector3, xf: Transform3D, color: Color, finish: int) -> void:
	var h := size * 0.5
	for axis in 3:
		for sgn: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			var u := Vector3.ZERO
			var v := Vector3.ZERO
			u[(axis + 1) % 3] = h[(axis + 1) % 3]
			v[(axis + 2) % 3] = h[(axis + 2) % 3]
			var c := n * h[axis]
			quad(xf * (c - u - v), xf * (c + u - v), xf * (c + u + v), xf * (c - u + v),
				xf.basis * n, color, finish)


## Smooth surface through rows of points (rows[j][i]); `closed` wraps each row around.
## Normals point away from each row's centroid (flip = true for inward-facing skins).
## skip.call(j, i) -> true leaves the cell between rows j..j+1 and points i..i+1 open.
## row_colors (one per row) overrides `color`.
func grid(rows: Array[PackedVector3Array], closed: bool, color: Color, finish: int,
		flip := false, skip := Callable(), row_colors := PackedColorArray()) -> void:
	var nr := rows.size()
	var nc := rows[0].size()
	var normals: Array[PackedVector3Array] = []
	var facing := 0.0
	for j in nr:
		var row := rows[j]
		var prev := rows[maxi(j - 1, 0)]
		var next := rows[mini(j + 1, nr - 1)]
		var cen := Vector3.ZERO
		for p in row:
			cen += p
		cen /= nc
		var out := PackedVector3Array()
		out.resize(nc)
		for i in nc:
			var ip := (i + 1) % nc if closed else mini(i + 1, nc - 1)
			var im := (i - 1 + nc) % nc if closed else maxi(i - 1, 0)
			var n := (row[ip] - row[im]).cross(next[i] - prev[i])
			out[i] = n
			facing += n.normalized().dot(row[i] - cen)
		normals.append(out)
	var sgn := -1.0 if (facing < 0.0) != flip else 1.0
	for j in nr:
		var row_n := normals[j]
		for i in nc:
			row_n[i] = row_n[i].normalized() * sgn
		normals[j] = row_n
	# Degenerate rows (cone tips) borrow the average normal of the neighbouring row.
	for j in nr:
		var row_n := normals[j]
		if row_n[0].length_squared() > 0.5:
			continue
		var nb := normals[j - 1] if j > 0 else normals[mini(j + 1, nr - 1)]
		var avg := Vector3.ZERO
		for n in nb:
			avg += n
		avg = avg.normalized()
		for i in nc:
			if row_n[i].length_squared() < 0.5:
				row_n[i] = avg
		normals[j] = row_n
	var s := _surf(finish)
	var base := s.verts.size()
	for j in nr:
		var c := row_colors[j] if row_colors.size() > j else color
		for i in nc:
			s.add(rows[j][i], normals[j][i], c)
	var cells := nc if closed else nc - 1
	for j in nr - 1:
		for i in cells:
			if skip.is_valid() and skip.call(j, i):
				continue
			var i1 := (i + 1) % nc
			var a := base + j * nc + i
			var b := base + j * nc + i1
			var c := base + (j + 1) * nc + i1
			var d := base + (j + 1) * nc + i
			var n := normals[j][i] + normals[j][i1] + normals[j + 1][i] + normals[j + 1][i1]
			var diag := (rows[j + 1][i1] - rows[j][i]).cross(rows[j + 1][i] - rows[j][i1])
			if diag.dot(n) > 0.0:
				s.index(a, c, b)
				s.index(a, d, c)
			else:
				s.index(a, b, c)
				s.index(a, c, d)


## Point on a superellipse section: half width w, top/bottom heights ht/hb from cy,
## exponent n (2 = ellipse, higher = boxier).
static func section_point(a: float, cy: float, w: float, ht: float, hb: float, n: float) -> Vector2:
	var c := cos(a)
	var s := sin(a)
	var e := 2.0 / n
	return Vector2(w * signf(c) * pow(absf(c), e),
		cy + (ht if s > 0.0 else hb) * signf(s) * pow(absf(s), e))


## Loft along z through superellipse stations [z, cy, w, ht, hb, n] at the given angles.
func loft(stations: Array, angles: PackedFloat32Array, color: Color, finish: int,
		flip := false, skip := Callable(), row_colors := PackedColorArray(),
		xf := Transform3D.IDENTITY) -> void:
	var rows: Array[PackedVector3Array] = []
	for st: Array in stations:
		var row := PackedVector3Array()
		for a in angles:
			var p := section_point(a, st[1], st[2], st[3], st[4], st[5])
			row.append(xf * Vector3(p.x, p.y, st[0]))
		rows.append(row)
	grid(rows, true, color, finish, flip, skip, row_colors)


## Surface of revolution about xf's local +Z through profile points (axial, radius).
func revolve(profile: PackedVector2Array, xf: Transform3D, color: Color, finish: int,
		segs := 20, flip := false, row_colors := PackedColorArray()) -> void:
	var rows: Array[PackedVector3Array] = []
	for pr in profile:
		var row := PackedVector3Array()
		for i in segs:
			var a := TAU * i / segs
			row.append(xf * Vector3(pr.y * cos(a), pr.y * sin(a), pr.x))
		rows.append(row)
	grid(rows, true, color, finish, flip, Callable(), row_colors)


## Closed 2D profile (xf-local XY) swept through a list of transforms; optional end caps.
func sweep(profile: PackedVector2Array, xforms: Array[Transform3D], color: Color, finish: int,
		caps := true, row_colors := PackedColorArray()) -> void:
	var rows: Array[PackedVector3Array] = []
	for xf in xforms:
		var row := PackedVector3Array()
		for p in profile:
			row.append(xf * Vector3(p.x, p.y, 0.0))
		rows.append(row)
	grid(rows, true, color, finish, false, Callable(), row_colors)
	if not caps:
		return
	for k in [0, rows.size() - 1]:
		var row: PackedVector3Array = rows[k]
		var cen := Vector3.ZERO
		for p in row:
			cen += p
		cen /= row.size()
		var other: Vector3 = rows[1 if k == 0 else rows.size() - 2][0]
		var n := (row[0] - other).normalized()
		var cap_col := row_colors[k] if row_colors.size() > k else color
		for i in row.size():
			tri(cen, row[i], row[(i + 1) % row.size()], n, cap_col, finish)


## Rounded box (superellipsoid). roundness 0.1 = nearly sharp, 1 = ellipsoid.
func rounded_box(size: Vector3, xf: Transform3D, color: Color, finish: int,
		roundness := 0.35, segs := 12, rings := 6) -> void:
	var h := size * 0.5
	var rows: Array[PackedVector3Array] = []
	for r in rings + 1:
		var v := -PI / 2 + PI * r / rings
		var cv := signf(cos(v)) * pow(absf(cos(v)), roundness)
		var sv := signf(sin(v)) * pow(absf(sin(v)), roundness)
		var row := PackedVector3Array()
		for i in segs:
			var u := TAU * i / segs
			var cu := signf(cos(u)) * pow(absf(cos(u)), roundness)
			var su := signf(sin(u)) * pow(absf(sin(u)), roundness)
			row.append(xf * Vector3(h.x * cv * cu, h.y * sv, h.z * cv * su))
		rows.append(row)
	grid(rows, true, color, finish)


func ellipsoid(radii: Vector3, xf: Transform3D, color: Color, finish: int, segs := 12, rings := 8) -> void:
	rounded_box(radii * 2.0, xf, color, finish, 1.0, segs, rings)


## Capped cylinder / cone from `from` to `to` (radius r0 at from, r1 at to).
func cylinder(from: Vector3, to: Vector3, r0: float, r1: float, color: Color, finish: int,
		segs := 12, caps := true) -> void:
	var h := from.distance_to(to)
	var prof := PackedVector2Array()
	if caps:
		prof.append(Vector2(0, 0))
		prof.append(Vector2(0, r0))
	prof.append(Vector2(0, r0))
	prof.append(Vector2(h, r1))
	if caps:
		prof.append(Vector2(h, r1))
		prof.append(Vector2(h, 0))
	revolve(prof, axis_xf(from, to), color, finish, segs)


## Flat ring between two equal-length loops (xf-local XY), facing xf's +Z.
func ring(outer: PackedVector2Array, inner: PackedVector2Array, xf: Transform3D, color: Color, finish: int) -> void:
	var n := xf.basis.z
	for i in outer.size():
		var k := (i + 1) % outer.size()
		quad(xf * Vector3(outer[i].x, outer[i].y, 0), xf * Vector3(outer[k].x, outer[k].y, 0),
			xf * Vector3(inner[k].x, inner[k].y, 0), xf * Vector3(inner[i].x, inner[i].y, 0), n, color, finish)


## Flat filled convex loop (xf-local XY), facing xf's +Z.
func disc(loop: PackedVector2Array, xf: Transform3D, color: Color, finish: int) -> void:
	var cen := Vector2.ZERO
	for p in loop:
		cen += p
	cen /= loop.size()
	var c3 := xf * Vector3(cen.x, cen.y, 0)
	for i in loop.size():
		var k := (i + 1) % loop.size()
		tri(c3, xf * Vector3(loop[i].x, loop[i].y, 0), xf * Vector3(loop[k].x, loop[k].y, 0),
			xf.basis.z, color, finish)


## Rounded rectangle outline centred on the origin (corner radius r, `per` points per corner).
static func rounded_rect(w: float, h: float, r: float, per := 5) -> PackedVector2Array:
	var out := PackedVector2Array()
	r = minf(r, minf(w, h) * 0.5 - 0.001)
	var cx := w * 0.5 - r
	var cy := h * 0.5 - r
	var centers := [Vector2(cx, cy), Vector2(-cx, cy), Vector2(-cx, -cy), Vector2(cx, -cy)]
	for k in 4:
		for i in per:
			var a := PI * 0.5 * k + PI * 0.5 * i / (per - 1)
			out.append(centers[k] + Vector2(cos(a), sin(a)) * r)
	return out


## Transform whose local +Z points from `from` to `to`.
static func axis_xf(from: Vector3, to: Vector3) -> Transform3D:
	var z := (to - from).normalized()
	var side := Vector3.UP if absf(z.y) < 0.9 else Vector3.RIGHT
	var x := side.cross(z).normalized()
	return Transform3D(Basis(x, z.cross(x), z), from)


## Bakes everything into one ArrayMesh (one surface per finish) and resets the batch.
func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var keys := _surfaces.keys()
	keys.sort()
	for f: int in keys:
		var s: _Surface = _surfaces[f]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.verts
		arrays[Mesh.ARRAY_NORMAL] = s.norms
		arrays[Mesh.ARRAY_COLOR] = s.cols
		arrays[Mesh.ARRAY_INDEX] = s.idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material(f))
	_surfaces.clear()
	return mesh
