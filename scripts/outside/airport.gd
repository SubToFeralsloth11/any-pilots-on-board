extends Node3D
## The airport, built in runway-local coordinates (origin = FlightModel.RUNWAY_CENTER).
## Runway along Z, threshold (landing end) at +Z, buildings on the +X (east) side.
## A tall beacon beam and "rabbit" approach strobes make it findable from the start position.

const Blocks := preload("res://scripts/outside/blocks.gd")

const HALF := FlightModel.RUNWAY_HALF
const ASPHALT := Color(0.24, 0.25, 0.28)
const CONCRETE := Color(0.62, 0.62, 0.6)
const PAINT := Color(0.97, 0.97, 0.95)
const AIRFIELD_GRASS := Color(0.5, 0.78, 0.36)
const APPROACH_LEN := 900.0
const APPROACH_STEP := 30.0
const BEAM_HEIGHT := 2500.0
const MAST_HEIGHT := 140.0
const MAST_POS := Vector3(380, 0, 560)
## 7-segment digits for runway numbers: segments a..g.
const DIGITS := {"1": "bc", "3": "abcdg", "6": "acdefg", "8": "abcdefg"}

var _rabbit: MeshInstance3D
var _beacon: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	var b := Blocks.new()
	var glow := Blocks.new()
	_build_surfaces(b)
	_build_markings(b)
	_build_lights(b, glow)
	_build_buildings(b)
	_build_planes(b)
	_build_mast(b)
	var mi := MeshInstance3D.new()
	mi.name = "AirportMesh"
	mi.mesh = b.commit()
	mi.material_override = Blocks.vertex_material()
	add_child(mi)
	var lights := MeshInstance3D.new()
	lights.name = "AirportLights"
	lights.mesh = glow.commit()
	var lm := Blocks.glow_material(Color.WHITE)
	lm.vertex_color_use_as_albedo = true
	lm.vertex_color_is_srgb = true
	lights.material_override = lm
	lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lights)
	_build_beacon()
	_build_signs()
	_build_collision()


func _process(dt: float) -> void:
	_t += dt
	# Rabbit strobe runs toward the threshold twice a second.
	var k := fmod(_t * 2.0, 1.0)
	_rabbit.position = Vector3(0, 3, HALF.y + APPROACH_LEN * (1.0 - k))
	_beacon.visible = fmod(_t, 1.2) < 0.7
	_beam_mat.albedo_color.a = 0.16 + 0.06 * sin(_t * 3.0)


# --- Ground surfaces ---------------------------------------------------------------------

func _build_surfaces(b: Blocks) -> void:
	b.flat(Vector2(1700, 3100), Vector3(250, 0.04, 350), AIRFIELD_GRASS)
	b.flat(Vector2(HALF.x * 2 + 10, HALF.y * 2 + 60), Vector3(0, 0.1, 0), Color(0.45, 0.45, 0.45))
	b.flat(Vector2(HALF.x * 2, HALF.y * 2), Vector3(0, 0.14, 0), ASPHALT)
	# Taxiway, connectors and apron.
	b.flat(Vector2(24, 1560), Vector3(170, 0.1, 0), ASPHALT.lightened(0.08))
	for z in [-760.0, 0.0, 760.0]:
		b.flat(Vector2(140, 24), Vector3(105, 0.11, z), ASPHALT.lightened(0.08))
	b.flat(Vector2(300, 720), Vector3(332, 0.1, 0), CONCRETE)
	b.flat(Vector2(150, 380), Vector3(320, 0.1, -600), CONCRETE)
	for z in range(-340, 360, 60):
		b.flat(Vector2(80, 1.2), Vector3(300, 0.16, z), Color(0.98, 0.85, 0.2))
	b.flat(Vector2(1.2, 1540), Vector3(170, 0.16, 0), Color(0.98, 0.85, 0.2))


func _build_markings(b: Blocks) -> void:
	var y := 0.2
	# Edge lines and centreline dashes.
	for sx in [-1.0, 1.0]:
		b.flat(Vector2(1.5, HALF.y * 2 - 4), Vector3(sx * (HALF.x - 2), y, 0), PAINT)
	var z := HALF.y - 110.0
	while z > -HALF.y + 110.0:
		b.flat(Vector2(2, 30), Vector3(0, y, z - 15), PAINT)
		z -= 50.0
	for end in [1.0, -1.0]:
		var zt: float = end * HALF.y
		# Threshold bar and piano-key stripes.
		b.flat(Vector2(HALF.x * 2 - 2, 3), Vector3(0, y, zt - end * 4), PAINT)
		for i in 4:
			for sx in [-1.0, 1.0]:
				b.flat(Vector2(3.5, 40), Vector3(sx * (6 + 7 * i), y, zt - end * 30), PAINT)
		# Touchdown zone and aiming point blocks.
		for sx in [-1.0, 1.0]:
			b.flat(Vector2(10, 45), Vector3(sx * 15, y, zt - end * 300), PAINT)
			for j in 3:
				b.flat(Vector2(2, 22), Vector3(sx * (10 + j * 4), y, zt - end * 160), PAINT)
	# "36" read when landing north, "18" read when landing south.
	_number(b, "36", Vector3(0, y, HALF.y - 82), Vector3.RIGHT, Vector3.FORWARD)
	_number(b, "18", Vector3(0, y, -HALF.y + 82), Vector3.LEFT, Vector3.BACK)


## Paints a blocky 7-segment number on the runway. `right`/`up` are the page axes on the ground.
func _number(b: Blocks, text: String, center: Vector3, right: Vector3, up: Vector3) -> void:
	var w := 18.0
	var h := 36.0
	var t := 4.0
	var segs := {
		"a": [Vector2(0, h / 2 - t / 2), Vector2(w, t)], "d": [Vector2(0, -h / 2 + t / 2), Vector2(w, t)],
		"g": [Vector2(0, 0), Vector2(w, t)],
		"b": [Vector2(w / 2 - t / 2, h / 4), Vector2(t, h / 2)], "c": [Vector2(w / 2 - t / 2, -h / 4), Vector2(t, h / 2)],
		"e": [Vector2(-w / 2 + t / 2, -h / 4), Vector2(t, h / 2)], "f": [Vector2(-w / 2 + t / 2, h / 4), Vector2(t, h / 2)],
	}
	for i in text.length():
		var origin := center + right * (i - (text.length() - 1) * 0.5) * (w + 8.0)
		for s in (DIGITS[text[i]] as String):
			var seg: Array = segs[s]
			var off: Vector2 = seg[0]
			var size: Vector2 = seg[1]
			# Page x runs along `right` (world X), page y along `up` (world Z).
			b.flat(Vector2(size.x, size.y), origin + right * off.x + up * off.y, PAINT)


# --- Lights ------------------------------------------------------------------------------

func _build_lights(b: Blocks, glow: Blocks) -> void:
	var white := Color(1.0, 0.98, 0.85)
	var z := -HALF.y
	while z <= HALF.y:
		for sx in [-1.0, 1.0]:
			glow.box(Vector3(1.2, 1.0, 1.2), Vector3(sx * (HALF.x + 2), 0.6, z), white)
		z += 60.0
	for x in range(-34, 35, 5):
		glow.box(Vector3(1.4, 1.0, 1.4), Vector3(x, 0.6, HALF.y + 3), Color(0.2, 1.0, 0.3))
		glow.box(Vector3(1.4, 1.0, 1.4), Vector3(x, 0.6, -HALF.y - 3), Color(1.0, 0.2, 0.15))
	# Approach light bars on poles, with a crossbar 300 m out.
	var d := APPROACH_STEP
	while d <= APPROACH_LEN:
		var zz: float = HALF.y + d
		b.box(Vector3(0.6, 2.5, 0.6), Vector3(0, 1.25, zz), Color(0.3, 0.3, 0.32))
		for k in range(-2, 3):
			glow.box(Vector3(1.6, 1.2, 1.6), Vector3(k * 3.5, 2.8, zz), white)
		if is_equal_approx(d, 300.0):
			for k in range(-10, 11):
				if absi(k) > 2:
					glow.box(Vector3(1.6, 1.2, 1.6), Vector3(k * 3.5, 2.8, zz), white)
		d += APPROACH_STEP
	_rabbit = MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(4, 4, 4)
	rm.material = Blocks.glow_material(Color(1.5, 1.5, 1.8))
	_rabbit.mesh = rm
	_rabbit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rabbit)


# --- Buildings ---------------------------------------------------------------------------

func _build_buildings(b: Blocks) -> void:
	_build_terminal(b)
	# Control tower: round shaft, flared glass cab, roof cap, antenna and radar.
	var white := Color(0.93, 0.93, 0.95)
	b.cylinder(Vector3(300, 0, 470), 8.0, 5.5, 54.0, white, Transform3D.IDENTITY, 14, false)
	for y in [14.0, 28.0, 42.0]:
		b.cylinder(Vector3(300, y, 470), 6.6, 6.6, 1.2, Color(0.95, 0.5, 0.2), Transform3D.IDENTITY, 14)
	b.cylinder(Vector3(300, 54, 470), 8.5, 12.0, 3.0, white, Transform3D.IDENTITY, 14)
	b.cylinder(Vector3(300, 57, 470), 11.5, 12.5, 7.5, Color(0.3, 0.75, 0.8), Transform3D.IDENTITY, 14)
	b.cylinder(Vector3(300, 64.5, 470), 13.5, 9.0, 2.5, Color(0.95, 0.5, 0.2), Transform3D.IDENTITY, 14)
	b.cylinder(Vector3(300, 67, 470), 0.5, 0.2, 12.0, Color(0.3, 0.3, 0.32), Transform3D.IDENTITY, 5)
	b.ellipsoid(Vector3(300, 79.5, 470), Vector3(0.8, 0.8, 0.8), Color(1, 0.2, 0.15), Transform3D.IDENTITY, 6, 4)
	b.box(Vector3(1.4, 4, 1.4), Vector3(306, 69, 470), Color(0.4, 0.4, 0.42))
	b.box(Vector3(1, 3, 9), Vector3(306, 72.5, 470), white, Transform3D.IDENTITY, true)
	# Hangars with curved roofs and big striped doors.
	for i in 3:
		var hz := -480.0 - i * 110.0
		var col: Color = [Color(0.75, 0.8, 0.88), Color(0.85, 0.78, 0.6), Color(0.7, 0.82, 0.7)][i]
		b.box(Vector3(70, 20, 90), Vector3(330, 10, hz), col)
		# Squashed half-cylinder roof: 45 m wide arch, 14 m above the walls.
		b.cylinder(Vector3.ZERO, 45.0, 45.0, 70.0, col.darkened(0.2),
			Blocks.axis_xf(Vector3(295, 11.5, hz), Vector3.RIGHT).scaled_local(Vector3(1, 1, 0.5)), 18)
		for k in 6:
			b.box(Vector3(0.6, 18, 10), Vector3(294.8, 9, hz - 27.5 + k * 11), Color(0.3, 0.32, 0.36) if k % 2 == 0 else Color(0.4, 0.42, 0.46))
		b.box(Vector3(0.8, 3, 40), Vector3(294.6, 22, hz), Color(0.95, 0.5, 0.2))
	# Fuel farm.
	for k in 3:
		b.cylinder(Vector3(470, 0, -820 + k * 32), 12, 12, 14, Color(0.96, 0.96, 0.96), Transform3D.IDENTITY, 14)
		b.ellipsoid(Vector3(470, 14, -820 + k * 32), Vector3(12, 3, 12), Color(0.85, 0.85, 0.88), Transform3D.IDENTITY, 14, 4)
	# Windsock on a striped pole.
	b.cylinder(Vector3(-90, 0, 620), 0.35, 0.25, 12, Color(0.9, 0.9, 0.9), Transform3D.IDENTITY, 6)
	for k in 4:
		var r := 1.3 - k * 0.22
		b.cylinder(Vector3.ZERO, r, r - 0.2, 2.6, Color(1.0, 0.45, 0.1) if k % 2 == 0 else Color(1, 1, 1),
			Blocks.axis_xf(Vector3(-90, 11, 620.3 + k * 2.6), Vector3.BACK), 8, false)
	_build_vehicles(b)


## Terminal: glass curtain wall with mullions, orange roof trim, rooftop units and jet bridges.
func _build_terminal(b: Blocks) -> void:
	var wall := Color(0.9, 0.9, 0.92)
	var glass := Color(0.35, 0.65, 0.92)
	b.box(Vector3(60, 26, 420), Vector3(570, 13, 0), wall)
	b.box(Vector3(0.6, 18, 410), Vector3(539.8, 13, 0), glass)
	var z := -200.0
	while z <= 200.0:
		b.box(Vector3(0.8, 18, 0.8), Vector3(539.4, 13, z), wall)
		z += 10.0
	b.box(Vector3(0.8, 0.8, 410), Vector3(539.4, 13, 0), wall)
	b.box(Vector3(64, 2, 424), Vector3(570, 27, 0), Color(0.95, 0.5, 0.2))
	b.cylinder(Vector3.ZERO, 30.0, 30.0, 400.0, Color(0.82, 0.85, 0.9),
		Blocks.axis_xf(Vector3(570, 24, -200), Vector3.BACK).scaled_local(Vector3(1, 1, 0.3)), 16)
	for gz: float in [-240.0, -90.0, 60.0, 210.0]:
		var gate := gz + 30.0
		b.box(Vector3(46, 4.5, 5), Vector3(517, 6.5, gate), Color(0.82, 0.82, 0.85))
		b.box(Vector3(46.2, 1.2, 5.2), Vector3(517, 7.5, gate), glass)
		b.cylinder(Vector3(494, 0, gate), 0.6, 0.6, 4.3, Color(0.4, 0.4, 0.42))
		b.cylinder(Vector3(494, 4.3, gate), 3.4, 3.4, 4.6, Color(0.82, 0.82, 0.85), Transform3D.IDENTITY, 10)
		# Gate sign.
		b.box(Vector3(0.4, 4, 8), Vector3(539.2, 23, gate), Color(1, 0.85, 0.2))


## Tugs, fuel trucks and baggage-cart trains around the apron.
func _build_vehicles(b: Blocks) -> void:
	var dark := Color(0.12, 0.12, 0.14)
	for k in 4:
		var z := -240.0 + k * 150.0
		# Fuel truck.
		var t := Transform3D(Basis.IDENTITY, Vector3(300, 0, z + 50))
		b.box(Vector3(3, 3, 3), Vector3(0, 2.0, -5), Color(1, 0.85, 0.2), t)
		b.box(Vector3(2.6, 1, 0.2), Vector3(0, 2.6, -6.55), Color(0.3, 0.45, 0.65), t)
		b.cylinder(Vector3.ZERO, 1.6, 1.6, 8, Color(0.95, 0.95, 0.95), t * Blocks.axis_xf(Vector3(0, 2.3, -3), Vector3.BACK), 10)
		for wz in [-5.0, -1.0, 3.0]:
			for wx in [-1.4, 1.4]:
				b.cylinder(Vector3.ZERO, 0.6, 0.6, 0.5, dark, t * Blocks.axis_xf(Vector3(wx - 0.25 * signf(wx), 0.6, wz), Vector3(signf(wx), 0, 0)), 8)
		# Baggage tug and carts.
		var c := Transform3D(Basis.IDENTITY, Vector3(320, 0, z + 20))
		b.box(Vector3(2, 1.4, 3), Vector3(0, 1.0, 0), Color(0.95, 0.5, 0.2), c)
		b.box(Vector3(1.8, 1.2, 0.2), Vector3(0, 2.2, 0.8), Color(0.3, 0.45, 0.65), c)
		for n in 3:
			var cz := 3.8 + n * 3.4
			b.box(Vector3(2, 0.3, 2.8), Vector3(0, 0.8, cz), Color(0.4, 0.4, 0.45), c)
			b.box(Vector3(1.6, 1.0, 2.2), Vector3(0, 1.45, cz), [Color(0.2, 0.4, 0.9), Color(0.9, 0.25, 0.25), Color(0.3, 0.75, 0.35)][n], c)
			for wx in [-0.9, 0.9]:
				b.cylinder(Vector3.ZERO, 0.35, 0.35, 0.3, dark, c * Blocks.axis_xf(Vector3(wx, 0.35, cz), Vector3.RIGHT), 6)


func _build_planes(b: Blocks) -> void:
	var liveries := [Color(0.9, 0.2, 0.25), Color(0.2, 0.5, 0.95), Color(0.3, 0.8, 0.4), Color(1.0, 0.7, 0.1)]
	var spots := [Vector3(250, 0, -270), Vector3(250, 0, -120), Vector3(250, 0, 30), Vector3(250, 0, 180)]
	for i in spots.size():
		_parked_plane(b, Transform3D(Basis.IDENTITY, spots[i]), liveries[i])


## Rounded cartoon airliner pointing west (-X), toward the taxiway.
func _parked_plane(b: Blocks, xf: Transform3D, livery: Color) -> void:
	var hull := Color(0.96, 0.96, 0.97)
	var dark := Color(0.15, 0.15, 0.17)
	var nose := xf * Blocks.axis_xf(Vector3(-16, 4.5, 0), Vector3.LEFT)
	var tail := xf * Blocks.axis_xf(Vector3(16, 4.5, 0), Vector3.RIGHT)
	b.cylinder(Vector3.ZERO, 2.4, 2.4, 32, hull, xf * Blocks.axis_xf(Vector3(-16, 4.5, 0), Vector3.RIGHT), 14, false)
	b.ellipsoid(Vector3.ZERO, Vector3(2.4, 4.0, 2.4), hull, nose, 12, 6)
	b.cylinder(Vector3.ZERO, 2.4, 0.7, 7.0, hull, tail, 12)
	b.cylinder(Vector3.ZERO, 2.45, 2.45, 30, livery, xf * Blocks.axis_xf(Vector3(-15, 3.4, 0), Vector3.RIGHT), 14, false)
	b.box(Vector3(1.6, 0.8, 3.0), Vector3(-18.6, 5.6, 0), Color(0.15, 0.22, 0.35), xf)
	var wx := -12.0
	while wx < 12.0:
		for s in [-1.0, 1.0]:
			b.box(Vector3(0.7, 0.8, 0.2), Vector3(wx, 5.3, s * 2.35), Color(0.15, 0.22, 0.35), xf)
		wx += 2.2
	for s in [-1.0, 1.0]:
		b.quad(xf * Vector3(-2, 3.2, s * 2), xf * Vector3(4, 3.2, s * 2), xf * Vector3(8, 3.4, s * 17), xf * Vector3(5, 3.4, s * 17), hull, xf.basis * Vector3.UP)
		b.quad(xf * Vector3(-2, 3.0, s * 2), xf * Vector3(4, 3.0, s * 2), xf * Vector3(8, 3.2, s * 17), xf * Vector3(5, 3.2, s * 17), hull.darkened(0.2), xf.basis * Vector3.DOWN)
		b.cylinder(Vector3.ZERO, 1.2, 1.0, 4.0, livery, xf * Blocks.axis_xf(Vector3(-1.5, 2.0, s * 7), Vector3.RIGHT), 10)
		b.cylinder(Vector3.ZERO, 0.8, 0.8, 0.2, dark, xf * Blocks.axis_xf(Vector3(-1.6, 2.0, s * 7), Vector3.RIGHT), 10)
		b.box(Vector3(2.5, 0.3, 5), Vector3(19, 6.2, s * 3.5), hull, xf)
	b.sheet(xf * Vector3(14, 5.5, 0), xf * Vector3(22, 14, 0), xf * Vector3(23, 5.5, 0), livery)
	for g in [Vector3(-13, 0, 0), Vector3(1, 0, -2.2), Vector3(1, 0, 2.2)]:
		b.cylinder(Vector3.ZERO, 0.2, 0.2, 2.2, Color(0.6, 0.6, 0.62), xf * Transform3D(Basis.IDENTITY, g + Vector3(0, 0.8, 0)))
		b.cylinder(Vector3.ZERO, 0.75, 0.75, 0.6, dark, xf * Blocks.axis_xf(g + Vector3(0, 0.75, -0.3), Vector3.BACK), 10)


## Red/white striped radio mast that carries the beacon.
func _build_mast(b: Blocks) -> void:
	var seg := 14.0
	var n := int(MAST_HEIGHT / seg)
	for i in n:
		var r0 := lerpf(4.0, 1.8, float(i) / n)
		var r1 := lerpf(4.0, 1.8, float(i + 1) / n)
		b.cylinder(MAST_POS + Vector3(0, seg * i, 0), r0, r1, seg,
			Color(0.95, 0.2, 0.15) if i % 2 == 0 else Color(1, 1, 1), Transform3D.IDENTITY, 8, i == n - 1)


func _build_beacon() -> void:
	_beacon = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(12, 12, 12)
	bm.material = Blocks.glow_material(Color(2.0, 1.6, 0.4))
	_beacon.mesh = bm
	_beacon.position = MAST_POS + Vector3(0, MAST_HEIGHT + 6, 0)
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beacon)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 24.0
	cm.bottom_radius = 14.0
	cm.height = BEAM_HEIGHT
	cm.radial_segments = 8
	cm.cap_top = false
	cm.cap_bottom = false
	_beam_mat = Blocks.glow_material(Color(1.0, 0.9, 0.35, 0.18))
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.material = _beam_mat
	beam.mesh = cm
	beam.position = MAST_POS + Vector3(0, MAST_HEIGHT + BEAM_HEIGHT * 0.5, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)


func _build_signs() -> void:
	var sign := _label("SOMEWHERE INTERNATIONAL", 0.12, Color(1, 1, 1))
	sign.position = Vector3(539, 33, 0)
	sign.rotation.y = -PI / 2
	var top := _label("AIRPORT", 0.6, Color(1.0, 0.85, 0.2))
	top.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	top.position = MAST_POS + Vector3(0, MAST_HEIGHT + 60, 0)


func _label(text: String, pixel: float, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 128
	l.outline_size = 32
	l.pixel_size = pixel
	l.modulate = color
	l.outline_modulate = Color(0.1, 0.15, 0.35)
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	return l


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var boxes := [[Vector3(60, 28, 420), Vector3(570, 14, 0)], [Vector3(12, 66, 12), Vector3(300, 33, 470)],
		[Vector3(6, MAST_HEIGHT, 6), MAST_POS + Vector3(0, MAST_HEIGHT * 0.5, 0)]]
	for i in 3:
		boxes.append([Vector3(70, 26, 90), Vector3(330, 13, -480.0 - i * 110.0)])
	for bx in boxes:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = bx[0]
		cs.shape = shape
		cs.position = bx[1]
		body.add_child(cs)
	add_child(body)
