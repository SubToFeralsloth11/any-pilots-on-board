class_name FunFx
extends RefCounted
## Cosmetic one-shot effects for the fun module: particle bursts, spray streams and pop-up words.
## Pure visuals in world space; call them from on_net_event on every peer.

static var _vertex_mat: StandardMaterial3D


## Particle burst at a global point. Colours are picked per particle from `colors`.
static func burst(parent: Node, at: Vector3, colors: Array, amount := 20, speed := 4.0, size := 0.05,
		dir := Vector3.UP, spread := 180.0, lifetime := 1.0, gravity := Vector3(0, -9.8, 0),
		flat := false) -> void:
	var p := _emitter(colors, size, flat)
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = lifetime
	p.direction = dir
	p.spread = spread
	p.gravity = gravity
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.damping_min = 1.0
	p.damping_max = 3.0
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


## A spray that keeps emitting for `duration` seconds along `dir` (water, wind, leaves).
static func spray(parent: Node, at: Vector3, dir: Vector3, colors: Array, duration := 0.3, speed := 9.0,
		size := 0.04, spread := 8.0, gravity := Vector3(0, -6, 0)) -> void:
	var p := _emitter(colors, size, false)
	p.amount = 40
	p.lifetime = 0.6
	p.direction = dir
	p.spread = spread
	p.gravity = gravity
	p.initial_velocity_min = speed * 0.7
	p.initial_velocity_max = speed
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_callback(func() -> void: p.emitting = false).set_delay(duration)
	tw.tween_callback(p.queue_free).set_delay(0.7)


## A word that pops up, floats and fades ("BONK!", "+60").
static func popup(parent: Node, at: Vector3, text: String, color := Color.WHITE, size := 72) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.outline_size = 14
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	parent.add_child(l)
	l.global_position = at
	l.scale = Vector3.ONE * 0.3
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(true)
	tw.tween_property(l, "global_position", at + Vector3(0, 0.6, 0), 1.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


static func _emitter(colors: Array, size: float, flat: bool) -> CPUParticles3D:
	if _vertex_mat == null:
		_vertex_mat = StandardMaterial3D.new()
		_vertex_mat.vertex_color_use_as_albedo = true
		_vertex_mat.roughness = 0.6
	var p := CPUParticles3D.new()
	var m: Mesh
	if flat:
		m = FunLooks.box(Vector3(size, size * 0.15, size * 0.7))
	else:
		m = FunLooks.sphere(size * 0.5, 6)
	p.mesh = m
	p.material_override = _vertex_mat
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	for i in colors.size():
		offs.append(float(i) / colors.size())
	g.offsets = offs
	g.colors = PackedColorArray(colors)
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	p.color_initial_ramp = g
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.particle_flag_rotate_y = flat
	return p
