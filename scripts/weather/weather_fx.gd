extends Node
## Weather visuals on every peer (cosmetic only, driven by `weather.current`):
## - storm clouds: one merged cumulonimbus mesh for all cells plus one translucent rain-shaft
##   mesh, children of world.outside so they ride the scenery frame (2 draw calls);
## - rain streaks around the plane: one CPUParticles3D in plane space, emitting only in a storm;
## - rain on the glass: one MultiMesh of streak quads over every side window and the windshield
##   (shared shader, 1 draw call, hidden in calm air);
## - darker sky, sun and fog inside storms; lightning bolt mesh, screen flash and thunder;
## - cracks on windows hit by lightning.

const Blocks := preload("res://scripts/outside/blocks.gd")

const RAIN_AMOUNT := 700
const RAIN_LIFETIME := 1.1
const TINT_RATE := 0.5                ## Sky tint follows the intensity at this rate (1/s).
const STORM_SKY_TOP := Color(0.2, 0.23, 0.3)
const STORM_HORIZON := Color(0.36, 0.38, 0.43)
const STORM_FOG := Color(0.3, 0.32, 0.36)
const STORM_FOG_DENSITY := 0.0028
const STORM_SUN := 0.25
const CLOUD_DARK := Color(0.2, 0.21, 0.26)
const CLOUD_MID := Color(0.34, 0.36, 0.42)
const CLOUD_TOP := Color(0.62, 0.64, 0.7)
const SHAFT := Color(0.32, 0.34, 0.4, 0.38)
const BOLT := Color(0.88, 0.92, 1.0)
const BOLT_TIME := 0.32
const FLASH_TIME := 0.45
const SPEED_OF_SOUND := 340.0
const WINDSHIELD := Vector3(0.0, 1.77, -14.08)   ## Plane-local centre of the windshield glass band.

const GLASS_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;
uniform float intensity = 0.0;
varying vec4 v_custom;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { v_custom = INSTANCE_CUSTOM; }
void fragment() {
	vec2 flow = normalize(v_custom.xy);
	vec2 perp = vec2(-flow.y, flow.x);
	float a = 0.0;
	for (int l = 0; l < 3; l++) {
		float fl = float(l);
		vec2 q = UV * v_custom.zw * (7.0 + fl * 4.0) - flow * TIME * (2.5 + fl * 1.7) + fl * 13.1;
		vec2 cell = floor(q);
		vec2 f = fract(q) - 0.5;
		if (hash(cell + fl * 7.3) > intensity * 0.85) { continue; }
		vec2 d = f - (vec2(hash(cell + 3.1), hash(cell + 9.7)) - 0.5) * 0.5;
		float along = dot(d, flow);
		float side = dot(d, perp);
		float head = smoothstep(0.1, 0.04, length(d));
		float tail = smoothstep(0.035, 0.0, abs(side)) * smoothstep(-0.45, 0.0, along) * step(along, 0.0);
		a = max(a, max(head, tail * 0.65));
	}
	ALBEDO = vec3(0.82, 0.88, 0.97);
	ALPHA = clamp(a * 0.75 + 0.06, 0.0, 1.0) * clamp(intensity * 2.5, 0.0, 1.0);
}
"""

var weather: Node
var _world: World
var _clouds: MeshInstance3D
var _shafts: MeshInstance3D
var _rain: CPUParticles3D
var _rain_mat: StandardMaterial3D
var _glass: MultiMeshInstance3D
var _glass_mat: ShaderMaterial
var _bolt: MeshInstance3D
var _bolt_mat: StandardMaterial3D
var _bolt_t := 0.0
var _flash: ColorRect
var _flash_t := 0.0
var _flash_peak := 0.0
var _cracks := {}                     ## Window index -> MeshInstance3D.
var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _base := {}                       ## Calm-air values of everything the tint touches.
var _tint := 0.0
var _tint_applied := -1.0
static var _thunder: AudioStreamWAV


func _ready() -> void:
	_world = weather.world
	_build_rain()
	_build_glass()
	_bolt_mat = Blocks.glow_material(BOLT)
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(0.92, 0.95, 1.0, 0.0)
	_flash.visible = false
	layer.add_child(_flash)
	for c in _world.outside.get_children():
		if c is WorldEnvironment:
			_env = (c as WorldEnvironment).environment
		elif c is DirectionalLight3D and _sun == null:
			_sun = c
	if _env and _env.sky:
		_sky = _env.sky.sky_material as ProceduralSkyMaterial
	if _env and _sky and _sun:
		_base = {"top": _sky.sky_top_color, "horizon": _sky.sky_horizon_color,
			"ground": _sky.ground_horizon_color, "fog": _env.fog_light_color, "density": _env.fog_density,
			"sun": _sun.light_energy, "ambient": _env.ambient_light_energy, "sat": _env.adjustment_saturation}


# --- Storm clouds ---------------------------------------------------------------------------

## (Re)builds the cloud and rain-shaft meshes for weather.cells (called when the seed changes).
func build_clouds() -> void:
	if _world == null:
		_world = weather.world
	for n in [_clouds, _shafts]:
		if n:
			n.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(weather.seed_used)
	var body := Blocks.new()
	var shafts := Blocks.new()
	for c in weather.cells:
		_add_storm(body, shafts, c, rng)
	_clouds = MeshInstance3D.new()
	_clouds.name = "StormClouds"
	_clouds.mesh = body.commit()
	_clouds.material_override = Blocks.vertex_material()
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.outside.add_child(_clouds)
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.vertex_color_is_srgb = true
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shafts = MeshInstance3D.new()
	_shafts.name = "RainShafts"
	_shafts.mesh = shafts.commit()
	_shafts.material_override = sm
	_shafts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.outside.add_child(_shafts)


## A chunky cumulonimbus tower with a flat anvil, plus a rain curtain down to the ground.
func _add_storm(body: Blocks, shafts: Blocks, c: Dictionary, rng: RandomNumberGenerator) -> void:
	var p: Vector3 = c.pos
	var r: float = c.radius
	var top: float = c.top
	var dark := CLOUD_DARK.lerp(CLOUD_MID, 1.0 - float(c.strength))
	var base := 420.0
	body.ellipsoid(p + Vector3(0, base + 120, 0), Vector3(r * 0.95, 220, r * 0.95), dark, Transform3D.IDENTITY, 14, 5)
	var tiers := 4
	for i in tiers:
		var k := float(i) / (tiers - 1)
		var y := lerpf(base + 380.0, top - 450.0, k)
		var rr := lerpf(0.85, 0.55, k) * r
		body.ellipsoid(p + Vector3(rng.randf_range(-0.1, 0.1) * r, y, rng.randf_range(-0.1, 0.1) * r),
			Vector3(rr, (top - base) / tiers * 0.85, rr), dark.lerp(CLOUD_TOP, k * 0.7), Transform3D.IDENTITY, 12, 6)
	for i in 7:
		var a := rng.randf() * TAU
		var y := rng.randf_range(base + 300.0, top * 0.75)
		var d := rng.randf_range(0.45, 0.75) * r
		var s := rng.randf_range(0.25, 0.4) * r
		var col := dark.lerp(CLOUD_TOP, inverse_lerp(base, top, y) * 0.8)
		body.ellipsoid(p + Vector3(cos(a) * d, y, sin(a) * d), Vector3(s, s * 0.8, s), col, Transform3D.IDENTITY, 9, 5)
	var anvil := Basis(Vector3.UP, rng.randf() * TAU)
	body.ellipsoid(Vector3.ZERO, Vector3(r * 1.45, 200, r * 1.1), CLOUD_TOP,
		Transform3D(anvil, p + Vector3(0, top - 120.0, 0)), 14, 5)
	shafts.cylinder(p, r * 0.7, r * 0.8, base + 60.0, SHAFT, Transform3D.IDENTITY, 16, false)


# --- Rain around the plane and on the glass -------------------------------------------------

func _build_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = RAIN_AMOUNT
	_rain.lifetime = RAIN_LIFETIME
	_rain.emitting = false
	_rain.local_coords = true
	_rain.particle_flag_align_y = true
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(16, 7, 8)
	_rain.position = Vector3(0, 1.5, -48)
	_rain.direction = Vector3(0, -0.12, 1)
	_rain.spread = 2.0
	_rain.gravity = Vector3.ZERO
	_rain.initial_velocity_min = 70.0
	_rain.initial_velocity_max = 80.0
	_rain.visibility_aabb = AABB(Vector3(-20, -10, -10), Vector3(40, 20, 110))
	var m := BoxMesh.new()
	m.size = Vector3(0.025, 1.6, 0.025)
	_rain_mat = StandardMaterial3D.new()
	_rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_mat.albedo_color = Color(0.8, 0.86, 0.95, 0.0)
	m.material = _rain_mat
	_rain.mesh = m
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.plane.add_child(_rain)


## One streak quad per side window (flow toward the tail) plus one on the windshield (flow up).
func _build_glass() -> void:
	var plane := _world.plane
	var xfs: Array[Transform3D] = []
	var custom: Array[Color] = []
	var inv := plane.global_transform.affine_inverse()
	for w in plane.windows:
		var mi: MeshInstance3D = w.mesh
		var xf: Transform3D = inv * mi.global_transform
		var size := mi.mesh.get_aabb().size
		var inward := -signf(xf.origin.x) * 0.04
		# QuadMesh faces +Z; its X runs along the cabin (toward the tail), Y up.
		var b := Basis(Vector3(0, 0, size.z), Vector3(0, size.y, 0), Vector3(-1, 0, 0))
		xfs.append(xf * Transform3D(b, Vector3(inward, 0, 0)))
		custom.append(Color(1.0, 0.18, size.z, size.y))
	var up := Vector3(0, 1.0, 0.45).normalized()
	var ws := Basis(Vector3(3.4, 0, 0), up * 1.05, Vector3.RIGHT.cross(up))
	xfs.append(Transform3D(ws, WINDSHIELD))
	custom.append(Color(0.0, -1.0, 3.4, 1.05))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = QuadMesh.new()
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_custom_data(i, custom[i])
	var sh := Shader.new()
	sh.code = GLASS_SHADER
	_glass_mat = ShaderMaterial.new()
	_glass_mat.shader = sh
	_glass = MultiMeshInstance3D.new()
	_glass.name = "GlassRain"
	_glass.multimesh = mm
	_glass.material_override = _glass_mat
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glass.visible = false
	plane.add_child(_glass)


# --- Frame update ---------------------------------------------------------------------------

func _process(dt: float) -> void:
	var cur: float = weather.current
	_rain.emitting = cur > 0.05
	if _rain.emitting:
		_rain_mat.albedo_color.a = lerpf(0.25, 0.6, cur)
		var v := maxf(_world.flight.speed, 40.0)
		_rain.initial_velocity_min = v
		_rain.initial_velocity_max = v + 10.0
	_glass.visible = cur > 0.03
	if _glass.visible:
		_glass_mat.set_shader_parameter("intensity", cur)
	_tint = move_toward(_tint, cur, TINT_RATE * dt)
	_apply_tint()
	if _bolt_t > 0.0:
		_bolt_t -= dt
		_bolt.visible = _bolt_t > 0.0 and int(_bolt_t * 30.0) % 3 != 0
	if _flash_t > 0.0:
		_flash_t -= dt
		_flash.color.a = clampf(_flash_t / FLASH_TIME, 0.0, 1.0) * _flash_peak * (0.6 + 0.4 * float(int(_flash_t * 24.0) % 2))
		_flash.visible = _flash_t > 0.0


func _apply_tint() -> void:
	if _base.is_empty():
		return
	var flash := clampf(_flash_t / FLASH_TIME, 0.0, 1.0) * _flash_peak
	if absf(_tint - _tint_applied) < 0.002 and flash <= 0.0 and _tint_applied >= 0.0:
		return
	# A flash forces a re-apply next frame too, so the light settles back after it.
	_tint_applied = -1.0 if flash > 0.0 else _tint
	var t := smoothstep(0.0, 0.7, _tint)
	_sky.sky_top_color = (_base.top as Color).lerp(STORM_SKY_TOP, t)
	_sky.sky_horizon_color = (_base.horizon as Color).lerp(STORM_HORIZON, t)
	_sky.ground_horizon_color = (_base.ground as Color).lerp(STORM_HORIZON, t)
	_env.fog_light_color = (_base.fog as Color).lerp(STORM_FOG, t)
	_env.fog_density = lerpf(_base.density, STORM_FOG_DENSITY, t * t)
	_env.ambient_light_energy = lerpf(_base.ambient, _base.ambient * 0.7, t) + flash * 1.5
	_env.adjustment_saturation = lerpf(_base.sat, 0.95, t)
	_sun.light_energy = lerpf(_base.sun, STORM_SUN, t) + flash * 2.0


# --- Lightning ------------------------------------------------------------------------------

## Bolt from `from` to `to` (flight coordinates), a screen flash and delayed thunder.
func strike(from: Vector3, to: Vector3, hit: bool, bolt_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = bolt_seed
	var b := Blocks.new()
	_bolt_path(b, from, to, 12, 70.0, 3.2, rng)
	for i in 2:
		var k := rng.randf_range(0.25, 0.6)
		var start := from.lerp(to, k)
		var end := start + Vector3(rng.randf_range(-300, 300), -rng.randf_range(150, 350), rng.randf_range(-300, 300))
		_bolt_path(b, start, end, 5, 40.0, 1.8, rng)
	if _bolt:
		_bolt.queue_free()
	_bolt = MeshInstance3D.new()
	_bolt.name = "Bolt"
	_bolt.mesh = b.commit()
	_bolt.material_override = _bolt_mat
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.outside.add_child(_bolt)
	_bolt_t = BOLT_TIME
	var dist := _world.flight.pos.distance_to(to)
	_flash_peak = 0.85 if hit else clampf(0.7 - dist / 3000.0, 0.25, 0.6)
	_flash_t = FLASH_TIME
	_flash.visible = true
	_thunder_after(0.05 if hit else minf(dist / SPEED_OF_SOUND, 3.0), 0.0 if hit else clampf(-dist / 300.0, -10.0, -2.0))


func _bolt_path(b: Blocks, from: Vector3, to: Vector3, segs: int, jag: float, width: float,
		rng: RandomNumberGenerator) -> void:
	var prev := from
	for i in range(1, segs + 1):
		var p := from.lerp(to, float(i) / segs)
		if i < segs:
			p += Vector3(rng.randf_range(-jag, jag), rng.randf_range(-jag, jag) * 0.3, rng.randf_range(-jag, jag))
		var d := p - prev
		b.cylinder(Vector3.ZERO, width, width, d.length(), BOLT, Blocks.axis_xf(prev, d), 4, false)
		prev = p


func _thunder_after(delay: float, volume_db: float) -> void:
	if _thunder == null:
		_thunder = _synth_thunder()
	await get_tree().create_timer(delay).timeout
	if not is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = _thunder
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.85, 1.1)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Sharp crack followed by a long low rumble (brown noise with slow swells).
static func _synth_thunder() -> AudioStreamWAV:
	var rate := 22050
	var dur := 3.6
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	var brown := 0.0
	for i in n:
		var t := float(i) / rate
		brown = clampf(brown * 0.995 + rng.randf_range(-1.0, 1.0) * 0.06, -1.0, 1.0)
		var swell := 0.6 + 0.4 * sin(t * 5.3) * sin(t * 2.1 + 1.0)
		var v := brown * 2.2 * swell * exp(-t * 0.9) * minf(t * 20.0, 1.0)
		if t < 0.18:
			v += rng.randf_range(-1.0, 1.0) * (1.0 - t / 0.18) * 0.8
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


# --- Window cracks --------------------------------------------------------------------------

## Spider-web crack on the inside of window `i`.
func crack_window(i: int) -> void:
	var plane := _world.plane
	if _cracks.has(i) or i < 0 or i >= plane.windows.size():
		return
	var mi: MeshInstance3D = plane.windows[i].mesh
	var size := mi.mesh.get_aabb().size
	var b := Blocks.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = i * 31 + 5
	var hub := Vector3(0, rng.randf_range(-0.12, 0.12), rng.randf_range(-0.15, 0.15) * size.z)
	for k in 9:
		var a := TAU * k / 9.0 + rng.randf_range(-0.2, 0.2)
		var len := rng.randf_range(0.18, 0.4)
		var mid := hub + Vector3(0, sin(a), cos(a)) * len * 0.5 + Vector3(0, rng.randf_range(-0.03, 0.03), 0)
		var tip := hub + Vector3(0, sin(a), cos(a)) * len
		for seg in [[hub, mid], [mid, tip]]:
			var d: Vector3 = seg[1] - seg[0]
			b.cylinder(Vector3.ZERO, 0.006, 0.004, d.length(), Color(0.95, 0.97, 1.0), Blocks.axis_xf(seg[0], d), 3, false)
	var crack := MeshInstance3D.new()
	crack.mesh = b.commit()
	crack.material_override = Blocks.glow_material(Color(0.92, 0.95, 1.0))
	crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var xf := plane.global_transform.affine_inverse() * mi.global_transform
	crack.transform = xf * Transform3D(Basis.IDENTITY, Vector3(-signf(xf.origin.x) * 0.035, 0, 0))
	plane.add_child(crack)
	_cracks[i] = crack


func clear_crack(i: int) -> void:
	var c: Node = _cracks.get(i)
	if c:
		c.queue_free()
	_cracks.erase(i)
