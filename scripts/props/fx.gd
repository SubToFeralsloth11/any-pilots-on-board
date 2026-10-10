extends RefCounted
## Cosmetic one-shot effects built from code (particle bursts, sprays, pop-up words) and
## tiny synthesized sound effects. Pure cosmetics: safe to call on every peer from on_net_event.

const MIX_RATE := 22050

static var _mats := {}
static var _sounds := {}


## Plays a synthesized sound at a global position: squeak, clang, crash, fizz, chomp, spray,
## spark, rip, horn, and the impact sounds thud (soft), knock (hard/wood) and clank (metal).
## Each sound is generated once and cached. `pitch` scales the (slightly randomised) pitch.
static func sound(parent: Node, at: Vector3, sound_name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _sounds.has(sound_name):
		_sounds[sound_name] = _synth(sound_name)
	var p := AudioStreamPlayer3D.new()
	p.stream = _sounds[sound_name]
	p.volume_db = volume_db
	p.unit_size = 4.0
	p.pitch_scale = pitch * randf_range(0.92, 1.08)
	parent.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()


static func _synth(sound_name: String) -> AudioStreamWAV:
	var dur: float = {"squeak": 0.32, "clang": 0.7, "crash": 0.45, "fizz": 1.2, "chomp": 0.22,
		"spray": 0.35, "spark": 0.5, "rip": 0.3, "horn": 0.6, "thud": 0.25, "knock": 0.2,
		"clank": 0.35}.get(sound_name, 0.3)
	var n := int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var k := t / dur
		var v := 0.0
		match sound_name:
			"squeak":
				var f := 900.0 + 900.0 * sin(k * PI) + 60.0 * sin(t * 60.0)
				phase += f / MIX_RATE
				v = signf(sin(phase * TAU)) * 0.35 * sin(k * PI)
			"clang":
				v = (sin(t * 523.0 * TAU) + 0.6 * sin(t * 1347.0 * TAU) + 0.4 * sin(t * 2211.0 * TAU)) \
					* 0.3 * exp(-t * 7.0)
			"crash":
				v = randf_range(-1, 1) * 0.6 * exp(-t * 9.0) + sin(t * 90.0 * TAU) * 0.4 * exp(-t * 14.0)
			"fizz":
				v = randf_range(-1, 1) * 0.18 * (1.0 - k) * (0.6 + 0.4 * sin(t * 40.0))
			"chomp":
				var second := exp(-(t - 0.11) * 40.0) if t > 0.11 else 0.0
				v = randf_range(-1, 1) * 0.5 * (exp(-t * 40.0) + second)
			"spray":
				v = randf_range(-1, 1) * 0.3 * sin(k * PI)
			"spark":
				v = randf_range(-1, 1) * 0.7 * (1.0 - k) if randf() < 0.08 else 0.0
			"rip":
				v = randf_range(-1, 1) * 0.45 * (0.5 + 0.5 * signf(sin(t * 180.0 * TAU))) * (1.0 - k)
			"horn":
				phase += (220.0 + 8.0 * sin(t * 30.0)) / MIX_RATE
				v = (fposmod(phase, 1.0) * 2.0 - 1.0) * 0.3 * minf(1.0, (1.0 - k) * 6.0)
			"thud":
				v = sin(t * 75.0 * TAU) * 0.6 * exp(-t * 22.0) + randf_range(-1, 1) * 0.25 * exp(-t * 60.0)
			"knock":
				v = (sin(t * 210.0 * TAU) + 0.5 * sin(t * 470.0 * TAU)) * 0.4 * exp(-t * 35.0) \
					+ randf_range(-1, 1) * 0.3 * exp(-t * 90.0)
			"clank":
				v = (sin(t * 740.0 * TAU) + 0.7 * sin(t * 1630.0 * TAU) + 0.4 * sin(t * 2890.0 * TAU)) \
					* 0.25 * exp(-t * 16.0) + randf_range(-1, 1) * 0.3 * exp(-t * 80.0)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.data = data
	return w


## Shared material for a colour (cached per colour/emission/metalness).
static func mat(c: Color, glow := 0.0, metal := 0.0) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f" % [c.to_html(), glow, metal]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.35 if metal > 0.0 else 0.65
		m.metallic = metal
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = glow
		if c.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[key] = m
	return _mats[key]


## Particle burst at a global position. `dir` + `spread` shape the cone; returns the emitter.
static func burst(parent: Node, at: Vector3, color: Color, amount := 16, speed := 4.0, size := 0.08,
		gravity := Vector3(0, -9.8, 0), lifetime := 1.0, dir := Vector3.UP, spread := 180.0,
		glow := 0.0) -> CPUParticles3D:
	var p := _emitter(color, size, glow)
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = lifetime
	p.direction = dir
	p.spread = spread
	p.gravity = gravity
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## Continuous emitter (for fizzing cans etc.). The caller owns and frees it.
static func stream(color: Color, size: float, speed: float, dir: Vector3, spread: float) -> CPUParticles3D:
	var p := _emitter(color, size, 0.0)
	p.amount = 30
	p.lifetime = 0.5
	p.direction = dir
	p.spread = spread
	p.gravity = Vector3(0, -6, 0)
	p.initial_velocity_min = speed * 0.6
	p.initial_velocity_max = speed
	p.local_coords = false
	return p


## A word that pops up, floats and fades ("SQUEAK!", "CLANG!").
static func popup(parent: Node, at: Vector3, text: String, color := Color.WHITE, size := 64) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.outline_size = 12
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	parent.add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position", at + Vector3(0, 0.7, 0), 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


static func _emitter(color: Color, size: float, glow: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(size, size, size)
	m.material = mat(color, glow)
	p.mesh = m
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	return p
