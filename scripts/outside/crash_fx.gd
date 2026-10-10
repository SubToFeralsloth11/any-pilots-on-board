extends Node3D
## Cartoon crash: a chain of fireballs, flashes, smoke and flying debris around the plane,
## a "KA-BOOM!" sign and camera shake. Cosmetic only; runs on every peer.

## Plane-local blast points with delays: [position, delay seconds, size]. Outer wings sit
## between the engines (x ±7) and the wingtips (±15.3); the belly blast is at the hull bottom.
const BLASTS := [
	[Vector3(0, 0.5, Airliner.NOSE_Z + 1.0), 0.0, 1.4],
	[Airliner.ENGINE_POS[0], 0.25, 1.1],
	[Airliner.ENGINE_POS[1], 0.45, 1.1],
	[Vector3(-12, -0.5, 0.7), 0.75, 0.8],
	[Vector3(12, -0.5, 0.7), 0.9, 0.8],
	[Vector3(0, 1.5, Airliner.TAIL_Z - 1.0), 1.2, 1.0],
	[Vector3(0, Airliner.HULL_CY - Airliner.HULL_R, 4.0), 1.6, 1.3],
]
const DEBRIS_COLORS := [Color(0.93, 0.94, 0.96), Color(0.15, 0.35, 0.75), Color(0.25, 0.25, 0.28)]

var _world: World


## Starts the sequence. The FX parent must be the World (plane at its origin).
func play(world: World) -> void:
	_world = world
	for b in BLASTS:
		_blast_later(world.plane.to_global(b[0]), b[1], b[2])
	_boom_sign(world.plane.to_global(Vector3(0, Airliner.HULL_CY + Airliner.HULL_R + 4.5, -4)))
	# Smoke drifting through the cabin for those inside.
	_smoke(world.plane.to_global(Vector3(0, 1.5, -2)), 0.6, 40, 6.0)


func _blast_later(at: Vector3, delay: float, size: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_inside_tree():
		return
	_fireball(at, size)
	_flash(at, size)
	_debris(at, size)
	_smoke(at, size, 30, 9.0)
	_burning(at, size)
	if _world.local_player:
		_world.local_player.shake(0.5 * size)


func _box_mesh(size: float, mat: StandardMaterial3D) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3.ONE * size
	m.material = mat
	return m


func _particle_mat(transparent: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _emitter(at: Vector3, mesh: Mesh, amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


func _fireball(at: Vector3, size: float) -> void:
	var p := _emitter(at, _box_mesh(1.6 * size, _particle_mat(true)), 46, 1.1)
	p.spread = 180.0
	p.initial_velocity_min = 4.0 * size
	p.initial_velocity_max = 13.0 * size
	p.damping_min = 8.0
	p.damping_max = 12.0
	p.gravity = Vector3(0, 6, 0)
	p.angular_velocity_min = -300.0
	p.angular_velocity_max = 300.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.6
	p.scale_amount_curve = _curve([Vector2(0, 0.3), Vector2(0.2, 1.0), Vector2(1, 0.2)])
	p.color_ramp = _gradient([Color(1, 1, 0.7), Color(1, 0.75, 0.1), Color(1, 0.3, 0.05), Color(0.3, 0.1, 0.05, 0)])


func _flash(at: Vector3, size: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1, 0.7, 0.3)
	l.light_energy = 14.0 * size
	l.omni_range = 45.0 * size
	add_child(l)
	l.global_position = at
	var t := create_tween()
	t.tween_property(l, "light_energy", 0.0, 0.8).set_ease(Tween.EASE_OUT)
	t.tween_callback(l.queue_free)


func _debris(at: Vector3, size: float) -> void:
	for c in DEBRIS_COLORS:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		var p := _emitter(at, _box_mesh(0.7 * size, m), 10, 3.5)
		p.spread = 70.0
		p.direction = Vector3.UP
		p.initial_velocity_min = 10.0
		p.initial_velocity_max = 24.0
		p.gravity = Vector3(0, -14, 0)
		p.angular_velocity_min = -720.0
		p.angular_velocity_max = 720.0
		p.scale_amount_min = 0.4
		p.scale_amount_max = 1.6


func _smoke(at: Vector3, size: float, amount: int, life: float) -> void:
	var p := _emitter(at, _box_mesh(2.2 * size, _particle_mat(true)), amount, life)
	p.explosiveness = 0.6
	p.spread = 60.0
	p.direction = Vector3.UP
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0.5, 2.5, 1.5)
	p.damping_min = 0.5
	p.damping_max = 1.0
	p.angular_velocity_min = -60.0
	p.angular_velocity_max = 60.0
	p.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(1, 2.4)])
	p.color_ramp = _gradient([Color(0.25, 0.22, 0.2, 0.9), Color(0.35, 0.35, 0.37, 0.6), Color(0.5, 0.5, 0.52, 0)])


## Fire that keeps licking up from a blast point until the round is rebuilt.
func _burning(at: Vector3, size: float) -> void:
	var p := CPUParticles3D.new()
	p.mesh = _box_mesh(0.9 * size, _particle_mat(true))
	p.amount = 18
	p.lifetime = 0.9
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, 3, 0)
	p.scale_amount_curve = _curve([Vector2(0, 1.0), Vector2(1, 0.1)])
	p.color_ramp = _gradient([Color(1, 0.9, 0.3), Color(1, 0.4, 0.05), Color(0.3, 0.1, 0.05, 0)])
	add_child(p)
	p.global_position = at
	_smoke(at + Vector3(0, 2, 0), size * 0.8, 24, 7.0)


func _boom_sign(at: Vector3) -> void:
	var l := Label3D.new()
	l.text = "KA-BOOM!"
	l.font_size = 160
	l.outline_size = 40
	l.pixel_size = 0.03
	l.modulate = Color(1, 0.85, 0.15)
	l.outline_modulate = Color(0.75, 0.1, 0.05)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.scale = Vector3.ONE * 0.1
	add_child(l)
	l.global_position = at
	var t := create_tween()
	t.tween_property(l, "scale", Vector3.ONE * 1.3, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "scale", Vector3.ONE, 0.2)
	t.tween_interval(1.6)
	t.tween_property(l, "modulate:a", 0.0, 0.6)
	t.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)


func _curve(points: Array) -> Curve:
	var c := Curve.new()
	c.max_value = 3.0
	for pt in points:
		c.add_point(pt)
	return c


func _gradient(colors: Array) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / (colors.size() - 1))
		cols.append(colors[i])
	g.offsets = offsets
	g.colors = cols
	return g
