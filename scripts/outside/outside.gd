extends Node3D
## Scenery in world coordinates (ground y = 0, north = -Z). World moves this node past the plane.
##
## Patchwork farmland, roads, lakes, forests, villages, the FlightModel mountains (same cones you
## crash into), boxy clouds and the airport. Everything is seeded, so every peer sees the same
## landscape. Static scenery is baked into a handful of vertex-coloured meshes and MultiMeshes,
## all sharing one material. Also plays the crash explosion when a round ends badly.
##
## Level of detail: trees, cows and village details are bucketed into TILE-sized chunks that fade
## out with distance (Blocks.fade_out, scaled by Settings.quality). Trees and buildings also have
## a tiny far version, baked into the single landscape mesh, that always draws and sits *inside*
## the detailed one, so nothing pops or z-fights; haze (fog + aerial perspective) hides the swap.

const Blocks := preload("res://scripts/outside/blocks.gd")
const Airport := preload("res://scripts/outside/airport.gd")
const CrashFx := preload("res://scripts/outside/crash_fx.gd")

const SEED := 7031
const GROUND_SIZE := 120000.0
const GROUND_CELL := 4000.0                  ## Far patchwork cells outside the detailed region.
const AREA_MIN := Vector2(-9000, -30000)   ## Detailed scenery region (x, z): covers both airports.
const AREA_MAX := Vector2(11000, 7000)
const CELL := 420.0                          ## Farm field grid.
const TILE := 600.0                          ## LOD chunk size for near-detail scenery.
## Near-detail fade distances (metres, at quality High).
const TREE_NEAR := 1500.0
const COW_NEAR := 800.0
const VILLAGE_NEAR := 2600.0
## Sun shadow distance and atlas size per Settings.quality (Low has no shadows).
const SHADOW_DIST := [0.0, 90.0, 150.0]
const SHADOW_ATLAS := [1024, 2048, 4096]
## Lakes: [center, radius].
const LAKES := [
	[Vector3(-1800, 0, -1500), 520.0],
	[Vector3(3600, 0, -9200), 620.0],
	[Vector3(-4200, 0, -10200), 800.0],
	[Vector3(6500, 0, -14500), 450.0],
]
## Roads as polylines of (x, z) points. The last leg of a road may enter an airport's grounds.
const ROADS := [
	[Vector2(-300, 6000), Vector2(-300, -3000), Vector2(300, -8000), Vector2(2100, -12000), Vector2(2100, -21000),
		Vector2(3150, -25300), Vector2(3150, -26300)],
	[Vector2(3150, -2600), Vector2(3150, -2000), Vector2(3150, -1100)],
	[Vector2(-9000, -2600), Vector2(11000, -2600)],
	[Vector2(-9000, -8250), Vector2(11000, -8250)],
	[Vector2(8200, 6000), Vector2(8200, -29000)],
	[Vector2(-5500, 6000), Vector2(-5500, -29000)],
	[Vector2(-5500, -18500), Vector2(8200, -18500)],
	[Vector2(-9000, -28700), Vector2(11000, -28700)],
]
const FIELD_COLORS := [
	Color(0.93, 0.82, 0.32), Color(0.55, 0.8, 0.3), Color(0.36, 0.66, 0.26), Color(0.62, 0.44, 0.27),
	Color(0.78, 0.86, 0.38), Color(0.98, 0.66, 0.25), Color(0.7, 0.55, 0.85), Color(0.45, 0.75, 0.5),
]
const GRASS := Color(0.42, 0.7, 0.3)
## Far-away countryside tints, mixed into the grass patchwork beyond the detailed region.
const FAR_TINTS := [Color(0.42, 0.7, 0.3), Color(0.5, 0.74, 0.32), Color(0.36, 0.62, 0.28),
	Color(0.62, 0.72, 0.36), Color(0.46, 0.66, 0.36), Color(0.7, 0.7, 0.4)]
const ROAD := Color(0.36, 0.36, 0.4)
const WATER := Color(0.25, 0.6, 0.95)
const SAND := Color(0.93, 0.86, 0.6)
const HOUSE_WALLS := [Color(0.98, 0.95, 0.85), Color(0.98, 0.85, 0.7), Color(0.8, 0.9, 1.0),
	Color(1.0, 0.78, 0.8), Color(0.85, 0.95, 0.75)]
const ROOFS := [Color(0.85, 0.25, 0.2), Color(0.6, 0.3, 0.2), Color(0.25, 0.4, 0.75), Color(0.3, 0.3, 0.35)]
const HAZE := Color(0.7, 0.83, 0.97)

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
var _env: Environment
var _sun: DirectionalLight3D
var _lod: Array[Dictionary] = []                    ## {node: GeometryInstance3D, range: float}
var _shadow_casters: Array[GeometryInstance3D] = []  ## Cast shadows only when Settings.shadows().


func _ready() -> void:
	world = get_parent() as World
	_rng.seed = SEED
	_mat = Blocks.vertex_material()
	_build_environment()
	# Ground, mountains, far trees and far buildings share one mesh and one draw call.
	var land := Blocks.new()
	_build_ground(land)
	_build_mountains(land)
	_build_forests(land)
	_build_villages(land)
	_add_static_mesh(land, "Landscape")
	_build_clouds()
	_build_life()
	for dest: bool in [true, false]:
		var airport := Airport.new()
		airport.name = "DestinationAirport" if dest else "OriginAirport"
		airport.is_destination = dest
		airport.position = FlightModel.RUNWAY_CENTER if dest else FlightModel.ORIGIN_RUNWAY_CENTER
		add_child(airport)
	_build_collision()
	if world:
		world.round_ended.connect(_on_round_ended)
	Settings.changed.connect(_apply_quality)
	_apply_quality()


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


## Scales detail distances, shadows and post effects to the quality setting.
func _apply_quality() -> void:
	for e in _lod:
		Blocks.fade_out(e.node, e.range)
	var shadows := Settings.shadows()
	for gi in _shadow_casters:
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sun.shadow_enabled = shadows
	# One orthogonal split: the cabin is all that's close, so a second cascade only doubles the
	# shadow pass draw calls.
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = SHADOW_DIST[Settings.quality]
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[Settings.quality], true)
	_env.glow_enabled = Settings.quality >= 1
	(_env.sky.sky_material as ProceduralSkyMaterial).sky_cover_modulate.a = 0.55 if Settings.quality >= 1 else 0.0


# --- Sky and light --------------------------------------------------------------------

## Wispy high cirrus painted into the sky dome (additive, so it only brightens the blue).
func _cirrus() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.006
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.55, 0.8])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0.9)])
	var tex := NoiseTexture2D.new()
	tex.width = 1024
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	return tex


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.17, 0.45, 0.92)
	sky_mat.sky_horizon_color = HAZE
	sky_mat.sky_curve = 0.1
	sky_mat.ground_horizon_color = HAZE
	sky_mat.ground_bottom_color = Color(0.5, 0.62, 0.55)
	sky_mat.ground_curve = 0.04
	sky_mat.sun_angle_max = 20.0
	sky_mat.sun_curve = 0.08
	sky_mat.sky_cover = _cirrus()
	sky_mat.sky_cover_modulate = Color(1, 1, 1, 0.55)
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = Sky.new()
	_env.sky.sky_material = sky_mat
	_env.sky.radiance_size = Sky.RADIANCE_SIZE_64
	# Neutral warm-white ambient so down-facing cabin surfaces don't pick up a green tint.
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.78, 0.78, 0.82)
	_env.ambient_light_energy = 0.45
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 0.95
	# Atmospheric haze: distant ground fades into the horizon colour and hides LOD swaps.
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_env.fog_light_color = HAZE
	_env.fog_sun_scatter = 0.15
	_env.fog_density = 0.00006
	_env.fog_aerial_perspective = 0.35
	_env.fog_sky_affect = 0.0
	_env.glow_intensity = 0.4
	_env.glow_hdr_threshold = 1.3
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.35
	_env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(35), 0)
	_sun.light_color = Color(1.0, 0.97, 0.9)
	_sun.light_energy = 1.0
	_sun.directional_shadow_fade_start = 0.75
	add_child(_sun)


# --- Ground -------------------------------------------------------------------------------

## True where farmland/trees/houses must not go (both airports' grounds, lakes).
func _blocked(x: float, z: float, margin: float) -> bool:
	for c: Vector3 in [FlightModel.RUNWAY_CENTER, FlightModel.ORIGIN_RUNWAY_CENTER]:
		if x > c.x - 650 - margin and x < c.x + 1150 + margin and z > c.z - 1250 - margin and z < c.z + 1950 + margin:
			return true
	for lake in LAKES:
		var p: Vector3 = lake[0]
		if Vector2(x - p.x, z - p.z).length() < float(lake[1]) * 1.25 + margin:
			return true
	return false


func _build_ground(b: Blocks) -> void:
	_build_far_ground(b)
	_build_fields(b)
	for lake in LAKES:
		_add_lake(b, lake[0], lake[1])
	for road in ROADS:
		_add_road(b, road)


## Ground plane as a grid of big grass patches; outside the detailed farmland they get
## slightly different tints so the far countryside isn't one flat green.
func _build_far_ground(b: Blocks) -> void:
	var n := int(GROUND_SIZE / GROUND_CELL)
	var origin := Vector2(AREA_MIN + AREA_MAX) * 0.5 - Vector2.ONE * GROUND_SIZE * 0.5
	for ix in n:
		for iz in n:
			var lo := origin + Vector2(ix, iz) * GROUND_CELL
			var hi := lo + Vector2.ONE * GROUND_CELL
			var inside := hi.x > AREA_MIN.x and lo.x < AREA_MAX.x and hi.y > AREA_MIN.y and lo.y < AREA_MAX.y
			var col: Color = GRASS if inside else FAR_TINTS[_rng.randi() % FAR_TINTS.size()]
			var mid := (lo + hi) * 0.5
			b.flat(Vector2.ONE * GROUND_CELL, Vector3(mid.x, 0, mid.y), col)


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


func _add_static_mesh(b: Blocks, node_name: String, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = b.commit()
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Registers a near-detail node that fades out beyond `distance` (scaled by quality).
func _add_lod(gi: GeometryInstance3D, distance: float) -> void:
	_lod.append({"node": gi, "range": distance})


func _tile_key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.z / TILE))


# --- Mountains ------------------------------------------------------------------------------

## Cones that exactly match FlightModel.MOUNTAINS (radius nudged so the faceted mesh sits
## halfway between the inscribed and circumscribed circle of the true cone).
func _build_mountains(b: Blocks) -> void:
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
		b.ellipsoid(Vector3(1.6, 10.2, 0.8), Vector3(2.6, 2.3, 2.6), g.lightened(0.1), Transform3D.IDENTITY, 6, 4)
		b.ellipsoid(Vector3(-1.8, 9.4, -1.0), Vector3(2.4, 2.1, 2.4), g.darkened(0.06), Transform3D.IDENTITY, 6, 4)
	return b.commit()


## Far stand-in for a tree (4-11 triangles). Its vertices line up with the detailed mesh's
## facets and sit just inside it, so both can draw at once without poking through.
func _far_tree_mesh(pine: bool) -> ArrayMesh:
	var b := Blocks.new()
	if pine:
		b.cylinder(Vector3(0, 2.4, 0), 2.6, 0.0, 8.8, Color(0.2, 0.5, 0.33), Transform3D.IDENTITY, 4)
	else:
		b.cylinder(Vector3.ZERO, 0.8, 0.0, 5.5, Color(0.5, 0.33, 0.2), Transform3D.IDENTITY, 3)
		b.ellipsoid(Vector3(0, 8.0, 0), Vector3(3.9, 3.4, 3.9), Color(0.35, 0.71, 0.29), Transform3D.IDENTITY, 4, 2)
	return b.commit()


func _build_forests(land: Blocks) -> void:
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
	_add_tiled_multimesh("RoundTrees", _tree_mesh(false), round_xf, round_col, TREE_NEAR)
	_add_tiled_multimesh("PineTrees", _tree_mesh(true), pine_xf, pine_col, TREE_NEAR)
	_bake_far_trees(land, _far_tree_mesh(false), round_xf, round_col)
	_bake_far_trees(land, _far_tree_mesh(true), pine_xf, pine_col)


## Far trees are baked straight into the landscape mesh: no extra draw calls at all.
func _bake_far_trees(land: Blocks, mesh: ArrayMesh, xfs: Array[Transform3D], cols: Array[Color]) -> void:
	var arrays := mesh.surface_get_arrays(0)
	for i in xfs.size():
		land.instance(arrays, xfs[i], cols[i])


func _push_tree(xfs: Array[Transform3D], cols: Array[Color], p: Vector3) -> void:
	var s := _rng.randf_range(1.6, 2.7)
	xfs.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.85, 1.2), s)), p))
	var v := _rng.randf_range(0.85, 1.1)
	cols.append(Color(v, v * _rng.randf_range(0.95, 1.05), v))


func _make_multimesh(mesh: Mesh, xfs: Array, cols: Array) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if mm.use_colors:
			mm.set_instance_color(i, cols[i])
	return mm


## One MultiMesh for every instance. `shadows` = may cast shadows (when the quality allows).
func _add_multimesh(node_name: String, mesh: Mesh, xfs: Array, cols: Array, shadows := false,
		parent: Node = self) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = _make_multimesh(mesh, xfs, cols)
	mmi.material_override = _mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if shadows:
		_shadow_casters.append(mmi)
	parent.add_child(mmi)
	return mmi


## Splits instances into TILE chunks, each its own MultiMesh that fades out beyond `near`.
func _add_tiled_multimesh(node_name: String, mesh: Mesh, xfs: Array, cols: Array, near: float) -> void:
	var buckets := {}
	for i in xfs.size():
		var key := _tile_key((xfs[i] as Transform3D).origin)
		if not buckets.has(key):
			buckets[key] = [[], []]
		buckets[key][0].append(xfs[i])
		if not cols.is_empty():
			buckets[key][1].append(cols[i])
	var root := Node3D.new()
	root.name = node_name
	add_child(root)
	for key: Vector2i in buckets:
		var mmi := _add_multimesh("%d_%d" % [key.x, key.y], mesh, buckets[key][0], buckets[key][1], false, root)
		_add_lod(mmi, near)


## Detailed-geometry builder for the LOD tile containing `p`.
func _tile_blocks(tiles: Dictionary, p: Vector3) -> Blocks:
	var key := _tile_key(p)
	if not tiles.has(key):
		tiles[key] = Blocks.new()
	return tiles[key]


## House with a gable roof, framed windows, a door with a step, and a chimney. The far version
## is just walls and roof, a hair smaller so the detailed house hides it up close.
func _add_house(near: Blocks, far: Blocks, xf: Transform3D, big: bool) -> void:
	var size := Vector3(_rng.randf_range(9, 14), _rng.randf_range(6, 8), _rng.randf_range(8, 11))
	if big:
		size *= Vector3(1.6, 1.3, 1.4)
	var wall: Color = HOUSE_WALLS[_rng.randi() % HOUSE_WALLS.size()]
	var roof_col: Color = ROOFS[_rng.randi() % ROOFS.size()]
	var glass := Color(0.45, 0.7, 0.95)
	var frame := Color(0.98, 0.98, 0.98)
	var front := size.z * 0.5
	far.box(size - Vector3(0.3, 0.2, 0.3), Vector3(0, size.y * 0.5 - 0.1, 0), wall, xf)
	far.roof(Vector3(size.x + 1.2, size.z * 0.45, size.z + 1.4), Vector3(0, size.y - 0.25, 0), roof_col, xf)
	near.box(size, Vector3(0, size.y * 0.5, 0), wall, xf)
	near.box(Vector3(size.x + 0.4, 0.8, size.z + 0.4), Vector3(0, 0.4, 0), wall.darkened(0.3), xf)
	near.roof(Vector3(size.x + 1.6, size.z * 0.45, size.z + 1.6), Vector3(0, size.y, 0), roof_col, xf)
	near.box(Vector3(1.4, 4.0, 1.4), Vector3(size.x * 0.3, size.y + 2.4, -size.z * 0.15), Color(0.6, 0.35, 0.28), xf)
	near.box(Vector3(2.2, 3.6, 0.3), Vector3(0, 1.8, front + 0.1), Color(0.5, 0.28, 0.18), xf)
	near.box(Vector3(3.2, 0.4, 1.4), Vector3(0, 0.2, front + 0.7), Color(0.7, 0.7, 0.7), xf)
	for side in [-1.0, 1.0]:
		for z in [front, -front]:
			var c := Vector3(side * size.x * 0.28, size.y * 0.55, z)
			var out := 0.12 if z > 0.0 else -0.12
			near.box(Vector3(2.6, 2.6, 0.2), c + Vector3(0, 0, out), frame, xf)
			near.box(Vector3(2.0, 2.0, 0.2), c + Vector3(0, 0, out * 2.0), glass, xf)
	for z in [-0.2, 0.2]:
		var c := Vector3(size.x * 0.5, size.y * 0.55, z * size.z)
		near.box(Vector3(0.2, 2.4, 2.4), c + Vector3(0.12, 0, 0), frame, xf)
		near.box(Vector3(0.2, 1.8, 1.8), c + Vector3(0.24, 0, 0), glass, xf)


## White chapel with a pointed spire and a round window.
func _add_church(near: Blocks, far: Blocks, xf: Transform3D) -> void:
	var white := Color(0.95, 0.93, 0.88)
	var slate := Color(0.35, 0.45, 0.6)
	var turn := xf * Transform3D(Basis(Vector3.UP, PI / 2), Vector3.ZERO)
	far.box(Vector3(13.6, 11.8, 23.6), Vector3(0, 5.9, 0), white, xf)
	far.roof(Vector3(24.6, 7, 14.6), Vector3(0, 11.75, 0), Color(0.5, 0.3, 0.25), turn)
	far.box(Vector3(6.6, 25.8, 6.6), Vector3(0, 12.9, -14), white, xf)
	far.cylinder(Vector3(0, 27.1, -14), 4.2, 0.0, 13.5, slate, xf, 4)
	near.box(Vector3(14, 12, 24), Vector3(0, 6, 0), white, xf)
	near.roof(Vector3(25, 7, 15), Vector3(0, 12, 0), Color(0.5, 0.3, 0.25), turn)
	near.box(Vector3(7, 26, 7), Vector3(0, 13, -14), white, xf)
	near.box(Vector3(7.6, 1, 7.6), Vector3(0, 26.5, -14), slate, xf)
	near.cylinder(Vector3(0, 27, -14), 4.6, 0.0, 14.0, slate, xf, 8)
	near.cylinder(Vector3.ZERO, 2.0, 2.0, 0.3, Color(0.95, 0.75, 0.3), xf * Blocks.axis_xf(Vector3(0, 8, 12), Vector3.BACK), 10)
	for z in [-6.0, 0.0, 6.0]:
		near.box(Vector3(0.3, 4, 2), Vector3(7.1, 6, z), Color(0.5, 0.7, 0.95), xf)
		near.box(Vector3(0.3, 4, 2), Vector3(-7.1, 6, z), Color(0.5, 0.7, 0.95), xf)


## Red barn with white trim, cross-braced doors and a round silo with a dome.
func _add_barn(near: Blocks, far: Blocks, xf: Transform3D) -> void:
	var red := Color(0.8, 0.2, 0.18)
	var trim := Color(0.98, 0.95, 0.9)
	var turn := xf * Transform3D(Basis(Vector3.UP, PI / 2), Vector3.ZERO)
	var silo := Color(0.75, 0.78, 0.82)
	far.box(Vector3(15.6, 9.8, 21.6), Vector3(0, 4.9, 0), red, xf)
	far.roof(Vector3(22.6, 6, 16.6), Vector3(0, 9.75, 0), Color(0.35, 0.33, 0.35), turn)
	far.cylinder(Vector3(13, 0, 0), 2.7, 2.7, 14.8, silo, xf, 5)
	near.box(Vector3(16, 10, 22), Vector3(0, 5, 0), red, xf)
	near.roof(Vector3(23, 6, 17), Vector3(0, 10, 0), Color(0.35, 0.33, 0.35), turn)
	near.box(Vector3(7, 7.4, 0.3), Vector3(0, 3.7, 11.1), trim, xf)
	near.box(Vector3(6, 6.4, 0.3), Vector3(0, 3.5, 11.2), red.darkened(0.15), xf)
	for tilt in [0.75, -0.75]:
		near.box(Vector3(0.6, 8.6, 0.3), Vector3.ZERO, trim, xf * Transform3D(Basis(Vector3.BACK, tilt), Vector3(0, 3.5, 11.35)))
	near.box(Vector3(2.4, 2.4, 0.3), Vector3(0, 11.5, 11.1), trim, xf)
	near.cylinder(Vector3(13, 0, 0), 2.8, 2.8, 15, silo, xf, 10, false)
	near.ellipsoid(Vector3(13, 15, 0), Vector3(2.9, 2.4, 2.9), Color(0.55, 0.6, 0.68), xf, 10, 5)


func _build_villages(far: Blocks) -> void:
	var tiles := {}
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
			_add_church(_tile_blocks(tiles, base.origin), far, base)
		for k in _rng.randi_range(10, 26):
			var lx := snappedf(_rng.randf_range(-170, 170), 30.0)
			var lz := snappedf(_rng.randf_range(-170, 170), 30.0)
			if absf(lx) < 25 and absf(lz) < 35:
				continue
			var turn := PI if _rng.randf() < 0.5 else 0.0
			var xf := base * Transform3D(Basis(Vector3.UP, turn), Vector3(lx, 0, lz))
			_add_house(_tile_blocks(tiles, xf.origin), far, xf, false)
		far.flat(Vector2(16, 420), Vector3(cx, 0.1, cz), ROAD, yaw)
	# Lonely farms between the villages.
	var farms := 0
	while farms < 90:
		var x := _rng.randf_range(AREA_MIN.x, AREA_MAX.x)
		var z := _rng.randf_range(AREA_MIN.y, AREA_MAX.y)
		if _blocked(x, z, 60.0) or FlightModel.mountain_height(Vector3(x, 0, z)) > 0.0:
			continue
		farms += 1
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(x, 0, z))
		var near := _tile_blocks(tiles, xf.origin)
		_add_house(near, far, xf, _rng.randf() < 0.3)
		if _rng.randf() < 0.7:
			_add_barn(near, far, xf * Transform3D(Basis.IDENTITY, Vector3(30, 0, 6)))
	var root := Node3D.new()
	root.name = "Villages"
	add_child(root)
	for key: Vector2i in tiles:
		var mi := _add_static_mesh(tiles[key], "%d_%d" % [key.x, key.y], root)
		_shadow_casters.append(mi)
		_add_lod(mi, VILLAGE_NEAR)


# --- Clouds ---------------------------------------------------------------------------------

## Puffy cumulus: bright domed tops over a flatter, blue-grey shaded base.
func _cloud_mesh() -> ArrayMesh:
	var b := Blocks.new()
	var white := Color(1, 1, 1)
	var shade := Color(0.82, 0.87, 0.95)
	b.ellipsoid(Vector3(0, 8, 0), Vector3(36, 8, 21), shade, Transform3D.IDENTITY, 8, 4)
	b.ellipsoid(Vector3(-16, 20, 2), Vector3(18, 14, 15), white, Transform3D.IDENTITY, 7, 4)
	b.ellipsoid(Vector3(12, 23, -3), Vector3(17, 17, 16), white, Transform3D.IDENTITY, 7, 4)
	b.ellipsoid(Vector3(32, 13, 5), Vector3(13, 9, 12), white, Transform3D.IDENTITY, 6, 3)
	b.ellipsoid(Vector3(-34, 11, -4), Vector3(13, 8, 12), white, Transform3D.IDENTITY, 6, 3)
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
	b.ellipsoid(Vector3(0, 1.4, 0.3), Vector3(0.95, 0.75, 1.3), Color(0.92, 0.95, 1.0), Transform3D.IDENTITY, 6, 3)
	b.box(Vector3(1.7, 0.5, 0.1), Vector3(0, 1.55, -0.85), Color(0.25, 0.4, 0.6))
	for x in [-1.0, 1.0]:
		for z in [-1.35, 1.35]:
			b.cylinder(Vector3.ZERO, 0.45, 0.45, 0.4, dark, Blocks.axis_xf(Vector3(x * 0.82, 0.45, z), Vector3(x, 0, 0)), 6)
		var lx: float = x * 0.65
		b.quad(Vector3(lx - 0.2, 0.83, -2.11), Vector3(lx + 0.2, 0.83, -2.11), Vector3(lx + 0.2, 1.07, -2.11),
			Vector3(lx - 0.2, 1.07, -2.11), Color(1, 1, 0.8), Vector3.FORWARD)
		b.quad(Vector3(lx - 0.2, 0.83, 2.11), Vector3(lx + 0.2, 0.83, 2.11), Vector3(lx + 0.2, 1.07, 2.11),
			Vector3(lx - 0.2, 1.07, 2.11), Color(1, 0.2, 0.15), Vector3.BACK)
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
	_car_mm = _add_multimesh("Cars", _car_mesh(), xfs, cols).multimesh


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
	_shadow_casters.append(_add_static_mesh(b, "Windmills"))
	var r := Blocks.new()
	var wood := Color(0.5, 0.33, 0.2)
	var sail := Color(0.98, 0.96, 0.9)
	for k in 4:
		var xf := Transform3D(Basis(Vector3.RIGHT, k * PI / 2), Vector3.ZERO)
		r.box(Vector3(0.5, 15, 0.6), Vector3(0, 7.8, 0), wood, xf, true)
		r.box(Vector3(0.3, 11, 3.2), Vector3(0, 9.5, 1.8), sail, xf, true)
	r.ellipsoid(Vector3.ZERO, Vector3(1, 1, 1), wood, Transform3D.IDENTITY, 6, 4)
	_rotor_mm = _add_multimesh("WindmillSails", r.commit(), xfs, [], true).multimesh


## Spotty cartoon cow grazing in herds.
func _cow_mesh() -> ArrayMesh:
	var b := Blocks.new()
	var white := Color(0.97, 0.97, 0.95)
	var black := Color(0.1, 0.1, 0.12)
	b.ellipsoid(Vector3(0, 1.35, 0), Vector3(0.75, 0.65, 1.25), white, Transform3D.IDENTITY, 8, 4)
	b.ellipsoid(Vector3(0.45, 1.6, 0.3), Vector3(0.38, 0.35, 0.45), black, Transform3D.IDENTITY, 5, 3)
	b.ellipsoid(Vector3(-0.4, 1.3, -0.4), Vector3(0.4, 0.4, 0.4), black, Transform3D.IDENTITY, 5, 3)
	b.box(Vector3(0.6, 0.6, 0.8), Vector3(0, 1.7, -1.4), white)
	b.box(Vector3(0.62, 0.35, 0.3), Vector3(0, 1.5, -1.85), Color(1, 0.65, 0.7))
	for x in [-0.3, 0.3]:
		b.box(Vector3(0.12, 0.25, 0.12), Vector3(x, 2.1, -1.3), Color(0.95, 0.9, 0.7))
		for z in [-0.75, 0.75]:
			b.cylinder(Vector3(x * 1.4, 0, z), 0.13, 0.15, 0.95, white.darkened(0.1), Transform3D.IDENTITY, 4, false)
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
	_add_tiled_multimesh("Cows", _cow_mesh(), xfs, [], COW_NEAR)


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
	_boat_mm = _add_multimesh("Boats", _boat_mesh(), xfs, cols).multimesh


## Striped hot-air balloon with a wicker basket on ropes.
func _balloon_mesh() -> ArrayMesh:
	var b := Blocks.new()
	var stripes := [Color.WHITE, Color(1, 0.95, 0.4)]
	# Envelope as vertical slices of an ellipsoid, alternating stripe colours.
	for k in 8:
		var xf := Transform3D(Basis(Vector3.UP, k * TAU / 8.0), Vector3.ZERO)
		b.ellipsoid(Vector3(0, 22, 0), Vector3(12.5 - (k % 2) * 0.3, 14, 4.6), stripes[k % 2], xf, 8, 6)
	b.cylinder(Vector3(0, 6, 0), 3.0, 6.5, 6.0, Color.WHITE, Transform3D.IDENTITY, 8, false)
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
	_balloon_mm = _add_multimesh("Balloons", _balloon_mesh(), xfs, cols).multimesh


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
