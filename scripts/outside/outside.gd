extends Node3D
## Scenery in world coordinates (ground y = 0, north = -Z). World moves this node past the plane.
##
## Patchwork farmland, roads, lakes, forests, villages, the FlightModel mountains (same cones you
## crash into), boxy clouds and the airport. Everything is seeded, so every peer sees the same
## landscape. Static scenery is baked into a handful of vertex-coloured meshes and MultiMeshes,
## all sharing one material. Also plays the crash explosion when a round ends badly.

const Blocks := preload("res://scripts/outside/blocks.gd")
const Airport := preload("res://scripts/outside/airport.gd")
const CrashFx := preload("res://scripts/outside/crash_fx.gd")

const SEED := 7031
const GROUND_SIZE := 120000.0
const AREA_MIN := Vector2(-9000, -22000)   ## Detailed scenery region (x, z).
const AREA_MAX := Vector2(11000, 7000)
const CELL := 420.0                          ## Farm field grid.
## Lakes: [center, radius].
const LAKES := [
	[Vector3(-1800, 0, -1500), 520.0],
	[Vector3(3600, 0, -9200), 620.0],
	[Vector3(-4200, 0, -10200), 800.0],
	[Vector3(6500, 0, -14500), 450.0],
]
## Roads as polylines of (x, z) points.
const ROADS := [
	[Vector2(-300, 6000), Vector2(-300, -3000), Vector2(300, -8000), Vector2(3150, -11300), Vector2(3150, -12300)],
	[Vector2(-9000, -2600), Vector2(11000, -2600)],
	[Vector2(-9000, -8250), Vector2(11000, -8250)],
	[Vector2(8200, 6000), Vector2(8200, -21000)],
	[Vector2(-5500, 6000), Vector2(-5500, -21000)],
	[Vector2(-5500, -18500), Vector2(8200, -18500)],
]
const FIELD_COLORS := [
	Color(0.93, 0.82, 0.32), Color(0.55, 0.8, 0.3), Color(0.36, 0.66, 0.26), Color(0.62, 0.44, 0.27),
	Color(0.78, 0.86, 0.38), Color(0.98, 0.66, 0.25), Color(0.7, 0.55, 0.85), Color(0.45, 0.75, 0.5),
]
const GRASS := Color(0.42, 0.7, 0.3)
const ROAD := Color(0.36, 0.36, 0.4)
const WATER := Color(0.25, 0.6, 0.95)
const SAND := Color(0.93, 0.86, 0.6)
const HOUSE_WALLS := [Color(0.98, 0.95, 0.85), Color(0.98, 0.85, 0.7), Color(0.8, 0.9, 1.0),
	Color(1.0, 0.78, 0.8), Color(0.85, 0.95, 0.75)]
const ROOFS := [Color(0.85, 0.25, 0.2), Color(0.6, 0.3, 0.2), Color(0.25, 0.4, 0.75), Color(0.3, 0.3, 0.35)]

var world: World
var _rng := RandomNumberGenerator.new()
var _mat: StandardMaterial3D
var _time := 0.0
var _cars: Array[Dictionary] = []          ## {start: Vector2, dir: Vector2, len: float, d: float, speed: float}
var _car_mm: MultiMesh
var _rotor_base: Array[Transform3D] = []   ## Windmill hub transforms; rotors spin about local X.
var _rotor_mm: MultiMesh
var _boats: Array[Dictionary] = []         ## {center: Vector3, radius: float, angle: float, speed: float}
var _boat_mm: MultiMesh
var _balloon_pos: Array[Vector3] = []
var _balloon_mm: MultiMesh


func _ready() -> void:
	world = get_parent() as World
	_rng.seed = SEED
	_mat = Blocks.vertex_material()
	_build_environment()
	_build_ground()
	_build_mountains()
	_build_forests()
	_build_villages()
	_build_clouds()
	_build_life()
	var airport := Airport.new()
	airport.name = "Airport"
	airport.position = FlightModel.RUNWAY_CENTER
	add_child(airport)
	_build_collision()
	if world:
		world.round_ended.connect(_on_round_ended)


## Moves the living details: cars, windmill rotors, boats and hot-air balloons.
func _process(dt: float) -> void:
	_time += dt
	for i in _cars.size():
		var car: Dictionary = _cars[i]
		var d: float = fposmod(float(car.d) + float(car.speed) * dt, float(car.len))
		car.d = d
		var dir: Vector2 = car.dir
		var p: Vector2 = (car.start as Vector2) + dir * d + Vector2(-dir.y, dir.x) * 3.5
		# Cars "go under" lakes and mountains where the road is not drawn.
		var s := 1.0 if _on_land(p.x, p.y) else 0.001
		_car_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)).scaled(Vector3.ONE * s),
			Vector3(p.x, 0.15, p.y)))
	for i in _rotor_base.size():
		_rotor_mm.set_instance_transform(i, _rotor_base[i] * Transform3D(Basis(Vector3.RIGHT, _time * 1.2 + i), Vector3.ZERO))
	for i in _boats.size():
		var boat: Dictionary = _boats[i]
		var a: float = float(boat.angle) + _time * float(boat.speed)
		var c: Vector3 = boat.center
		var r: float = boat.radius
		var yaw := PI - a if float(boat.speed) > 0.0 else -a
		_boat_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), c + Vector3(cos(a) * r, 0.2, sin(a) * r)))
	for i in _balloon_pos.size():
		var bob := Vector3(sin(_time * 0.2 + i) * 6.0, sin(_time * 0.5 + i * 2.0) * 5.0, cos(_time * 0.15 + i) * 6.0)
		_balloon_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, _balloon_pos[i] + bob))


# --- Sky and light --------------------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.5, 0.95)
	sky_mat.sky_horizon_color = Color(0.68, 0.85, 1.0)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.68, 0.85, 1.0)
	sky_mat.ground_bottom_color = Color(0.55, 0.6, 0.6)
	sky_mat.sun_angle_max = 20.0
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	# Neutral warm-white ambient so down-facing cabin surfaces don't pick up a green tint.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.78, 0.82)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.72, 0.84, 0.97)
	env.fog_density = 0.00002
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.35
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(35), 0)
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 220.0
	add_child(sun)


# --- Ground -------------------------------------------------------------------------------

## True where farmland/trees/houses must not go (airport grounds, lakes, steep mountain).
func _blocked(x: float, z: float, margin: float) -> bool:
	var c := FlightModel.RUNWAY_CENTER
	if x > c.x - 650 - margin and x < c.x + 1150 + margin and z > c.z - 1250 - margin and z < c.z + 1950 + margin:
		return true
	for lake in LAKES:
		var p: Vector3 = lake[0]
		if Vector2(x - p.x, z - p.z).length() < float(lake[1]) * 1.25 + margin:
			return true
	return false


func _build_ground() -> void:
	var b := Blocks.new()
	b.flat(Vector2(GROUND_SIZE, GROUND_SIZE), Vector3.ZERO, GRASS)
	_build_fields(b)
	for lake in LAKES:
		_add_lake(b, lake[0], lake[1])
	for road in ROADS:
		_add_road(b, road)
	_add_static_mesh(b, "Ground")


func _build_fields(b: Blocks) -> void:
	var nx := int((AREA_MAX.x - AREA_MIN.x) / CELL)
	var nz := int((AREA_MAX.y - AREA_MIN.y) / CELL)
	for ix in nx:
		for iz in nz:
			var x0 := AREA_MIN.x + ix * CELL
			var z0 := AREA_MIN.y + iz * CELL
			var cx := x0 + CELL * 0.5
			var cz := z0 + CELL * 0.5
			if _blocked(cx, cz, CELL * 0.5) or FlightModel.mountain_height(Vector3(cx, 0, cz)) > 10.0:
				continue
			# Split each cell into 1-3 strips with hedge gaps between them.
			var parts := _rng.randi_range(1, 3)
			var along_x := _rng.randf() < 0.5
			for i in parts:
				var w := CELL / parts
				var center := Vector3(cx, 0.06, cz)
				var size := Vector2(CELL - 10, w - 10)
				if along_x:
					center.z = z0 + w * (i + 0.5)
				else:
					center.x = x0 + w * (i + 0.5)
					size = Vector2(w - 10, CELL - 10)
				if _rng.randf() < 0.12:
					continue
				var col: Color = FIELD_COLORS[_rng.randi() % FIELD_COLORS.size()]
				col = col.lightened(_rng.randf_range(-0.05, 0.08))
				b.flat(size, center, col)
				if _rng.randf() < 0.35:
					_add_crop_rows(b, size, center, col.darkened(0.15))


func _add_crop_rows(b: Blocks, size: Vector2, center: Vector3, col: Color) -> void:
	var rows := 5
	var long_x := size.x > size.y
	for r in rows:
		var t := (r + 0.5) / rows - 0.5
		if long_x:
			b.flat(Vector2(size.x - 8, size.y * 0.06), center + Vector3(0, 0.03, t * size.y), col)
		else:
			b.flat(Vector2(size.x * 0.06, size.y - 8), center + Vector3(t * size.x, 0.03, 0), col)


func _add_lake(b: Blocks, center: Vector3, radius: float) -> void:
	var radii := PackedFloat32Array()
	var sand := PackedFloat32Array()
	for i in 14:
		var r := radius * _rng.randf_range(0.8, 1.15)
		radii.append(r)
		sand.append(r + 25.0)
	b.blob(center + Vector3(0, 0.05, 0), sand, SAND)
	b.blob(center + Vector3(0, 0.09, 0), radii, WATER)


## Roads are drawn in 200 m pieces so they skip lakes, mountains and the airport fence.
func _add_road(b: Blocks, pts: Array) -> void:
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var c: Vector2 = pts[i + 1]
		var d := c - a
		var pieces := maxi(1, int(d.length() / 200.0))
		var yaw := atan2(d.x, d.y)
		for k in pieces:
			var m := a + d * ((k + 0.5) / pieces)
			var is_last_leg := i == pts.size() - 2 and pts.size() > 2
			if (_blocked(m.x, m.y, 0.0) and not is_last_leg) or FlightModel.mountain_height(Vector3(m.x, 0, m.y)) > 0.0:
				continue
			b.flat(Vector2(14, d.length() / pieces + 14), Vector3(m.x, 0.1, m.y), ROAD, yaw)


func _add_static_mesh(b: Blocks, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = b.commit()
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# --- Mountains ------------------------------------------------------------------------------

## Cones that exactly match FlightModel.MOUNTAINS (radius nudged so the faceted mesh sits
## halfway between the inscribed and circumscribed circle of the true cone).
func _build_mountains() -> void:
	var b := Blocks.new()
	var seg := 20
	var fudge := (1.0 + 1.0 / cos(PI / seg)) * 0.5
	for m in FlightModel.MOUNTAINS:
		var c: Vector3 = m[0]
		c.y = 0.0
		var r: float = m[1] * fudge
		var h: float = m[2]
		b.cone_band(c, r, h, 0.0, h * 0.3, seg, Color(0.35, 0.58, 0.3))
		b.cone_band(c, r, h, h * 0.3, h * 0.68, seg, Color(0.55, 0.5, 0.48))
		b.cone_band(c, r, h, h * 0.68, h, seg, Color(0.97, 0.98, 1.0))
	_add_static_mesh(b, "Mountains")


# --- Trees and houses ------------------------------------------------------------------------

## Cartoon trees: a puffy round tree (blobby canopy) or a pine (stacked cones).
func _tree_mesh(pine: bool) -> ArrayMesh:
	var b := Blocks.new()
	var trunk := Color(0.5, 0.33, 0.2)
	if pine:
		b.cylinder(Vector3.ZERO, 0.8, 0.5, 3.0, trunk, Transform3D.IDENTITY, 6, false)
		var g := Color(0.18, 0.46, 0.3)
		b.cylinder(Vector3(0, 2.2, 0), 4.2, 0.0, 5.0, g, Transform3D.IDENTITY, 8)
		b.cylinder(Vector3(0, 4.8, 0), 3.3, 0.0, 4.4, g.lightened(0.06), Transform3D.IDENTITY, 8)
		b.cylinder(Vector3(0, 7.2, 0), 2.3, 0.0, 4.0, g.lightened(0.12), Transform3D.IDENTITY, 8)
	else:
		b.cylinder(Vector3.ZERO, 0.9, 0.6, 5.5, trunk, Transform3D.IDENTITY, 6, false)
		var g := Color(0.33, 0.7, 0.28)
		b.ellipsoid(Vector3(0, 8.0, 0), Vector3(4.2, 3.6, 4.2), g, Transform3D.IDENTITY, 8, 5)
		b.ellipsoid(Vector3(1.6, 10.2, 0.8), Vector3(2.6, 2.3, 2.6), g.lightened(0.1), Transform3D.IDENTITY, 7, 4)
		b.ellipsoid(Vector3(-1.8, 9.4, -1.0), Vector3(2.4, 2.1, 2.4), g.darkened(0.06), Transform3D.IDENTITY, 7, 4)
	return b.commit()


func _build_forests() -> void:
	var round_xf: Array[Transform3D] = []
	var pine_xf: Array[Transform3D] = []
	var round_col: Array[Color] = []
	var pine_col: Array[Color] = []
	# Forest clumps across the farmland.
	for i in 70:
		var cx := _rng.randf_range(AREA_MIN.x, AREA_MAX.x)
		var cz := _rng.randf_range(AREA_MIN.y, AREA_MAX.y)
		var radius := _rng.randf_range(120, 380)
		var pine_bias := _rng.randf()
		for k in _rng.randi_range(50, 160):
			var a := _rng.randf() * TAU
			var d := sqrt(_rng.randf()) * radius
			var x := cx + cos(a) * d
			var z := cz + sin(a) * d
			if _blocked(x, z, 20.0) or FlightModel.mountain_height(Vector3(x, 0, z)) > 0.0:
				continue
			var pine := _rng.randf() < pine_bias
			_push_tree(pine_xf if pine else round_xf, pine_col if pine else round_col, Vector3(x, 0, z))
	# Pine forests on the lower mountain slopes.
	for m in FlightModel.MOUNTAINS:
		var c: Vector3 = m[0]
		for k in 260:
			var a := _rng.randf() * TAU
			var d := float(m[1]) * _rng.randf_range(0.72, 1.05)
			var p := Vector3(c.x + cos(a) * d, 0, c.z + sin(a) * d)
			if _blocked(p.x, p.z, 20.0):
				continue
			p.y = FlightModel.mountain_height(p) - 1.0
			_push_tree(pine_xf, pine_col, p)
	_add_multimesh("RoundTrees", _tree_mesh(false), round_xf, round_col)
	_add_multimesh("PineTrees", _tree_mesh(true), pine_xf, pine_col)


func _push_tree(xfs: Array[Transform3D], cols: Array[Color], p: Vector3) -> void:
	var s := _rng.randf_range(1.6, 2.7)
	xfs.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.85, 1.2), s)), p))
	var v := _rng.randf_range(0.85, 1.1)
	cols.append(Color(v, v * _rng.randf_range(0.95, 1.05), v))


func _add_multimesh(node_name: String, mesh: Mesh, xfs: Array, cols: Array, shadows := false) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if mm.use_colors:
			mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = _mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


## House with a gable roof, framed windows, a door with a step, and a chimney.
func _add_house(b: Blocks, xf: Transform3D, big: bool) -> void:
	var size := Vector3(_rng.randf_range(9, 14), _rng.randf_range(6, 8), _rng.randf_range(8, 11))
	if big:
		size *= Vector3(1.6, 1.3, 1.4)
	var wall: Color = HOUSE_WALLS[_rng.randi() % HOUSE_WALLS.size()]
	var roof_col: Color = ROOFS[_rng.randi() % ROOFS.size()]
	var glass := Color(0.45, 0.7, 0.95)
	var frame := Color(0.98, 0.98, 0.98)
	var front := size.z * 0.5
	b.box(size, Vector3(0, size.y * 0.5, 0), wall, xf)
	b.box(Vector3(size.x + 0.4, 0.8, size.z + 0.4), Vector3(0, 0.4, 0), wall.darkened(0.3), xf)
	b.roof(Vector3(size.x + 1.6, size.z * 0.45, size.z + 1.6), Vector3(0, size.y, 0), roof_col, xf)
	b.box(Vector3(1.4, 4.0, 1.4), Vector3(size.x * 0.3, size.y + 2.4, -size.z * 0.15), Color(0.6, 0.35, 0.28), xf)
	b.box(Vector3(2.2, 3.6, 0.3), Vector3(0, 1.8, front + 0.1), Color(0.5, 0.28, 0.18), xf)
	b.box(Vector3(3.2, 0.4, 1.4), Vector3(0, 0.2, front + 0.7), Color(0.7, 0.7, 0.7), xf)
	for side in [-1.0, 1.0]:
		for z in [front, -front]:
			var c := Vector3(side * size.x * 0.28, size.y * 0.55, z)
			var out := 0.12 if z > 0.0 else -0.12
			b.box(Vector3(2.6, 2.6, 0.2), c + Vector3(0, 0, out), frame, xf)
			b.box(Vector3(2.0, 2.0, 0.2), c + Vector3(0, 0, out * 2.0), glass, xf)
	for z in [-0.2, 0.2]:
		var c := Vector3(size.x * 0.5, size.y * 0.55, z * size.z)
		b.box(Vector3(0.2, 2.4, 2.4), c + Vector3(0.12, 0, 0), frame, xf)
		b.box(Vector3(0.2, 1.8, 1.8), c + Vector3(0.24, 0, 0), glass, xf)


## White chapel with a pointed spire and a round window.
func _add_church(b: Blocks, xf: Transform3D) -> void:
	var white := Color(0.95, 0.93, 0.88)
	b.box(Vector3(14, 12, 24), Vector3(0, 6, 0), white, xf)
	b.roof(Vector3(25, 7, 15), Vector3(0, 12, 0), Color(0.5, 0.3, 0.25), xf * Transform3D(Basis(Vector3.UP, PI / 2), Vector3.ZERO))
	b.box(Vector3(7, 26, 7), Vector3(0, 13, -14), white, xf)
	b.box(Vector3(7.6, 1, 7.6), Vector3(0, 26.5, -14), Color(0.35, 0.45, 0.6), xf)
	b.cylinder(Vector3(0, 27, -14), 4.6, 0.0, 14.0, Color(0.35, 0.45, 0.6), xf, 8)
	b.cylinder(Vector3.ZERO, 2.0, 2.0, 0.3, Color(0.95, 0.75, 0.3), xf * Blocks.axis_xf(Vector3(0, 8, 12), Vector3.BACK), 10)
	for z in [-6.0, 0.0, 6.0]:
		b.box(Vector3(0.3, 4, 2), Vector3(7.1, 6, z), Color(0.5, 0.7, 0.95), xf)
		b.box(Vector3(0.3, 4, 2), Vector3(-7.1, 6, z), Color(0.5, 0.7, 0.95), xf)


## Red barn with white trim, cross-braced doors and a round silo with a dome.
func _add_barn(b: Blocks, xf: Transform3D) -> void:
	var red := Color(0.8, 0.2, 0.18)
	var trim := Color(0.98, 0.95, 0.9)
	b.box(Vector3(16, 10, 22), Vector3(0, 5, 0), red, xf)
	b.roof(Vector3(23, 6, 17), Vector3(0, 10, 0), Color(0.35, 0.33, 0.35), xf * Transform3D(Basis(Vector3.UP, PI / 2), Vector3.ZERO))
	b.box(Vector3(7, 7.4, 0.3), Vector3(0, 3.7, 11.1), trim, xf)
	b.box(Vector3(6, 6.4, 0.3), Vector3(0, 3.5, 11.2), red.darkened(0.15), xf)
	for tilt in [0.75, -0.75]:
		b.box(Vector3(0.6, 8.6, 0.3), Vector3.ZERO, trim, xf * Transform3D(Basis(Vector3.BACK, tilt), Vector3(0, 3.5, 11.35)))
	b.box(Vector3(2.4, 2.4, 0.3), Vector3(0, 11.5, 11.1), trim, xf)
	b.cylinder(Vector3(13, 0, 0), 2.8, 2.8, 15, Color(0.75, 0.78, 0.82), xf, 10, false)
	b.ellipsoid(Vector3(13, 15, 0), Vector3(2.9, 2.4, 2.9), Color(0.55, 0.6, 0.68), xf, 10, 5)


func _build_villages() -> void:
	var b := Blocks.new()
	var made := 0
	while made < 16:
		var cx := _rng.randf_range(AREA_MIN.x + 500, AREA_MAX.x - 500)
		var cz := _rng.randf_range(AREA_MIN.y + 500, AREA_MAX.y - 500)
		if _blocked(cx, cz, 300.0) or FlightModel.mountain_height(Vector3(cx, 0, cz)) > 0.0:
			continue
		made += 1
		var yaw := _rng.randf() * TAU
		var base := Transform3D(Basis(Vector3.UP, yaw), Vector3(cx, 0, cz))
		if _rng.randf() < 0.6:
			_add_church(b, base)
		for k in _rng.randi_range(10, 26):
			var lx := snappedf(_rng.randf_range(-170, 170), 30.0)
			var lz := snappedf(_rng.randf_range(-170, 170), 30.0)
			if absf(lx) < 25 and absf(lz) < 35:
				continue
			var turn := PI if _rng.randf() < 0.5 else 0.0
			_add_house(b, base * Transform3D(Basis(Vector3.UP, turn), Vector3(lx, 0, lz)), false)
		b.flat(Vector2(16, 420), Vector3(cx, 0.1, cz), ROAD, yaw)
	# Lonely farms between the villages.
	var farms := 0
	while farms < 90:
		var x := _rng.randf_range(AREA_MIN.x, AREA_MAX.x)
		var z := _rng.randf_range(AREA_MIN.y, AREA_MAX.y)
		if _blocked(x, z, 60.0) or FlightModel.mountain_height(Vector3(x, 0, z)) > 0.0:
			continue
		farms += 1
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(x, 0, z))
		_add_house(b, xf, _rng.randf() < 0.3)
		if _rng.randf() < 0.7:
			_add_barn(b, xf * Transform3D(Basis.IDENTITY, Vector3(30, 0, 6)))
	var mi := _add_static_mesh(b, "Villages")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# --- Clouds ---------------------------------------------------------------------------------

func _cloud_mesh() -> ArrayMesh:
	var b := Blocks.new()
	var white := Color(1, 1, 1)
	var shade := Color(0.86, 0.9, 0.97)
	b.ellipsoid(Vector3(0, 10, 0), Vector3(34, 11, 20), shade, Transform3D.IDENTITY, 10, 5)
	b.ellipsoid(Vector3(-16, 20, 2), Vector3(18, 14, 15), white, Transform3D.IDENTITY, 9, 5)
	b.ellipsoid(Vector3(12, 23, -3), Vector3(17, 17, 16), white, Transform3D.IDENTITY, 9, 5)
	b.ellipsoid(Vector3(32, 13, 5), Vector3(13, 9, 12), white, Transform3D.IDENTITY, 8, 4)
	b.ellipsoid(Vector3(-34, 11, -4), Vector3(13, 8, 12), white, Transform3D.IDENTITY, 8, 4)
	return b.commit()


func _build_clouds() -> void:
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	for layer in [[520.0, 110], [1150.0, 90], [1900.0, 70]]:
		for i in int(layer[1]):
			var p := Vector3(_rng.randf_range(AREA_MIN.x - 4000, AREA_MAX.x + 4000),
				float(layer[0]) + _rng.randf_range(-60, 60), _rng.randf_range(AREA_MIN.y - 4000, AREA_MAX.y + 4000))
			var s := _rng.randf_range(1.0, 3.2)
			xfs.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * 0.8, s)), p))
			var v := _rng.randf_range(0.93, 1.0)
			cols.append(Color(v, v, v * 1.02))
	_add_multimesh("Clouds", _cloud_mesh(), xfs, cols)


# --- Living details --------------------------------------------------------------------------

## True where the ground is flat dry land (no lake, no mountain).
func _on_land(x: float, z: float) -> bool:
	if FlightModel.mountain_height(Vector3(x, 0, z)) > 0.0:
		return false
	for lake in LAKES:
		var p: Vector3 = lake[0]
		if Vector2(x - p.x, z - p.z).length() < float(lake[1]) * 1.2:
			return false
	return true


func _build_life() -> void:
	_build_cars()
	_build_windmills()
	_build_cows()
	_build_boats()
	_build_balloons()


## Little rounded car, nose toward local -Z. White body is tinted by the instance colour.
func _car_mesh() -> ArrayMesh:
	var b := Blocks.new()
	var dark := Color(0.12, 0.12, 0.14)
	b.box(Vector3(2.0, 0.9, 4.2), Vector3(0, 0.85, 0), Color.WHITE)
	b.ellipsoid(Vector3(0, 1.4, 0.3), Vector3(0.95, 0.75, 1.3), Color(0.92, 0.95, 1.0), Transform3D.IDENTITY, 8, 4)
	b.box(Vector3(1.7, 0.5, 0.1), Vector3(0, 1.55, -0.85), Color(0.25, 0.4, 0.6))
	for x in [-1.0, 1.0]:
		for z in [-1.35, 1.35]:
			b.cylinder(Vector3.ZERO, 0.45, 0.45, 0.4, dark, Blocks.axis_xf(Vector3(x * 0.82, 0.45, z), Vector3(x, 0, 0)), 8)
		b.box(Vector3(0.4, 0.25, 0.1), Vector3(x * 0.65, 0.95, -2.12), Color(1, 1, 0.8))
		b.box(Vector3(0.4, 0.25, 0.1), Vector3(x * 0.65, 0.95, 2.12), Color(1, 0.2, 0.15))
	return b.commit()


func _build_cars() -> void:
	var palette := [Color(0.95, 0.25, 0.2), Color(0.2, 0.5, 0.95), Color(1, 0.8, 0.15), Color(0.3, 0.8, 0.4),
		Color(0.95, 0.95, 0.95), Color(0.95, 0.5, 0.75), Color(0.35, 0.35, 0.4)]
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	for road in ROADS:
		for i in road.size() - 1:
			var a: Vector2 = road[i]
			var c: Vector2 = road[i + 1]
			var length := a.distance_to(c)
			for k in int(length / 900.0) + 1:
				var forward := _rng.randf() < 0.5
				var start := a if forward else c
				var dir := (c - a).normalized() * (1.0 if forward else -1.0)
				_cars.append({"start": start, "dir": dir, "len": length,
					"d": _rng.randf() * length, "speed": _rng.randf_range(14.0, 26.0)})
				xfs.append(Transform3D.IDENTITY)
				cols.append(palette[_rng.randi() % palette.size()])
	_car_mm = _add_multimesh("Cars", _car_mesh(), xfs, cols, true)


## Classic windmills: tapered tower and cap are static; the four sails are a spinning MultiMesh.
func _build_windmills() -> void:
	var b := Blocks.new()
	var xfs: Array[Transform3D] = []
	while _rotor_base.size() < 14:
		var x := _rng.randf_range(AREA_MIN.x, AREA_MAX.x)
		var z := _rng.randf_range(AREA_MIN.y, AREA_MAX.y)
		if _blocked(x, z, 40.0) or not _on_land(x, z):
			continue
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(x, 0, z))
		b.cylinder(Vector3.ZERO, 6.0, 3.6, 22.0, Color(0.95, 0.9, 0.8), xf, 10, false)
		b.cylinder(Vector3(0, 22, 0), 4.4, 0.0, 6.0, Color(0.55, 0.3, 0.22), xf, 10)
		b.box(Vector3(2.2, 3.4, 0.3), Vector3(0, 1.7, 5.9), Color(0.45, 0.28, 0.18), xf)
		b.box(Vector3(1.6, 1.6, 0.3), Vector3(0, 12, 4.9), Color(0.4, 0.65, 0.95), xf)
		b.cylinder(Vector3.ZERO, 0.6, 0.6, 3.0, Color(0.3, 0.3, 0.3), xf * Blocks.axis_xf(Vector3(0, 22, 0), Vector3.RIGHT), 6)
		var hub := xf * Transform3D(Basis.IDENTITY, Vector3(5.2, 22, 0))
		_rotor_base.append(hub)
		xfs.append(hub)
	var mi := _add_static_mesh(b, "Windmills")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var r := Blocks.new()
	var wood := Color(0.5, 0.33, 0.2)
	var sail := Color(0.98, 0.96, 0.9)
	for k in 4:
		var xf := Transform3D(Basis(Vector3.RIGHT, k * PI / 2), Vector3.ZERO)
		r.box(Vector3(0.5, 15, 0.6), Vector3(0, 7.8, 0), wood, xf, true)
		r.box(Vector3(0.3, 11, 3.2), Vector3(0, 9.5, 1.8), sail, xf, true)
	r.ellipsoid(Vector3.ZERO, Vector3(1, 1, 1), wood, Transform3D.IDENTITY, 6, 4)
	_rotor_mm = _add_multimesh("WindmillSails", r.commit(), xfs, [], true)


## Spotty cartoon cow grazing in herds.
func _cow_mesh() -> ArrayMesh:
	var b := Blocks.new()
	var white := Color(0.97, 0.97, 0.95)
	var black := Color(0.1, 0.1, 0.12)
	b.ellipsoid(Vector3(0, 1.35, 0), Vector3(0.75, 0.65, 1.25), white, Transform3D.IDENTITY, 8, 5)
	b.ellipsoid(Vector3(0.45, 1.6, 0.3), Vector3(0.38, 0.35, 0.45), black, Transform3D.IDENTITY, 6, 4)
	b.ellipsoid(Vector3(-0.4, 1.3, -0.4), Vector3(0.4, 0.4, 0.4), black, Transform3D.IDENTITY, 6, 4)
	b.box(Vector3(0.6, 0.6, 0.8), Vector3(0, 1.7, -1.4), white)
	b.box(Vector3(0.62, 0.35, 0.3), Vector3(0, 1.5, -1.85), Color(1, 0.65, 0.7))
	for x in [-0.3, 0.3]:
		b.box(Vector3(0.12, 0.25, 0.12), Vector3(x, 2.1, -1.3), Color(0.95, 0.9, 0.7))
		for z in [-0.75, 0.75]:
			b.cylinder(Vector3(x * 1.4, 0, z), 0.13, 0.15, 0.95, white.darkened(0.1), Transform3D.IDENTITY, 5, false)
	return b.commit()


func _build_cows() -> void:
	var xfs: Array[Transform3D] = []
	var herds := 0
	while herds < 60:
		var x := _rng.randf_range(AREA_MIN.x, AREA_MAX.x)
		var z := _rng.randf_range(AREA_MIN.y, AREA_MAX.y)
		# Some herds hug the airport fence so they're visible after landing.
		if herds < 8:
			var c := FlightModel.RUNWAY_CENTER
			x = c.x + _rng.randf_range(-900, -700)
			z = c.z + _rng.randf_range(-1000, 1800)
		elif _blocked(x, z, 40.0):
			continue
		if not _on_land(x, z):
			continue
		herds += 1
		for k in _rng.randi_range(5, 12):
			var s := _rng.randf_range(1.3, 1.7)
			var p := Vector3(x + _rng.randf_range(-40, 40), 0, z + _rng.randf_range(-40, 40))
			xfs.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), p))
	_add_multimesh("Cows", _cow_mesh(), xfs, [])


## Sailboat; the hull is tinted per instance, sails stay white.
func _boat_mesh() -> ArrayMesh:
	var b := Blocks.new()
	b.ellipsoid(Vector3(0, 0.4, 0), Vector3(1.8, 0.9, 5.0), Color.WHITE, Transform3D.IDENTITY, 8, 4)
	b.box(Vector3(2.6, 0.3, 7.0), Vector3(0, 1.0, 0), Color(0.75, 0.55, 0.35))
	b.cylinder(Vector3(0, 1, -0.5), 0.15, 0.1, 9.0, Color(0.5, 0.33, 0.2), Transform3D.IDENTITY, 5, false)
	b.sheet(Vector3(0, 1.6, -0.3), Vector3(0, 9.6, -0.3), Vector3(0, 1.6, 4.0), Color(0.98, 0.98, 0.96))
	b.sheet(Vector3(0, 2.0, -0.8), Vector3(0, 8.5, -0.8), Vector3(0, 2.0, -4.0), Color(0.98, 0.9, 0.85))
	return b.commit()


func _build_boats() -> void:
	var palette := [Color(0.95, 0.3, 0.25), Color(0.2, 0.45, 0.9), Color(1, 0.8, 0.2), Color(0.95, 0.95, 0.95)]
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	for lake in LAKES:
		for k in 3:
			var dir := 1.0 if _rng.randf() < 0.5 else -1.0
			_boats.append({"center": lake[0], "radius": float(lake[1]) * _rng.randf_range(0.3, 0.65),
				"angle": _rng.randf() * TAU, "speed": dir * _rng.randf_range(0.015, 0.03)})
			xfs.append(Transform3D.IDENTITY)
			cols.append(palette[_rng.randi() % palette.size()])
	_boat_mm = _add_multimesh("Boats", _boat_mesh(), xfs, cols, true)


## Striped hot-air balloon with a wicker basket on ropes.
func _balloon_mesh() -> ArrayMesh:
	var b := Blocks.new()
	var stripes := [Color.WHITE, Color(1, 0.95, 0.4)]
	# Envelope as vertical slices of an ellipsoid, alternating stripe colours.
	for k in 8:
		var xf := Transform3D(Basis(Vector3.UP, k * TAU / 8.0), Vector3.ZERO)
		b.ellipsoid(Vector3(0, 22, 0), Vector3(12.5 - (k % 2) * 0.3, 14, 4.6), stripes[k % 2], xf, 10, 6)
	b.cylinder(Vector3(0, 6, 0), 3.0, 6.5, 6.0, Color.WHITE, Transform3D.IDENTITY, 10, false)
	b.box(Vector3(3, 2.4, 3), Vector3(0, 1.2, 0), Color(0.6, 0.42, 0.22), Transform3D.IDENTITY, true)
	for x in [-1.4, 1.4]:
		for z in [-1.4, 1.4]:
			b.box(Vector3(0.15, 4.0, 0.15), Vector3(x, 4.2, z), Color(0.35, 0.3, 0.25))
	return b.commit()


func _build_balloons() -> void:
	var palette := [Color(1, 0.3, 0.3), Color(0.3, 0.6, 1), Color(0.5, 1, 0.5), Color(1, 0.6, 0.2), Color(0.8, 0.5, 1)]
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	for k in 10:
		var t := (k + 0.5) / 10.0
		var along := FlightModel.START_POS.lerp(FlightModel.runway_threshold(), t)
		var p := Vector3(along.x + _rng.randf_range(-900, 900), _rng.randf_range(250, 900), along.z + _rng.randf_range(-400, 400))
		p.y = maxf(p.y, FlightModel.mountain_height(p) + 150.0)
		_balloon_pos.append(p)
		xfs.append(Transform3D(Basis.IDENTITY, p))
		cols.append(palette[k % palette.size()])
	_balloon_mm = _add_multimesh("Balloons", _balloon_mesh(), xfs, cols, true)


# --- Collision ------------------------------------------------------------------------------

## A big flat box so players can walk out onto the ground after landing.
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60000, 20, 60000)
	shape.shape = box
	shape.position = Vector3(1000, -10, -8000)
	body.add_child(shape)
	add_child(body)


# --- Crash ----------------------------------------------------------------------------------

func _on_round_ended(result: Dictionary) -> void:
	if result.get("landed", false):
		return
	var fx := CrashFx.new()
	fx.name = "CrashFx"
	world.add_child(fx)
	fx.play(world)
