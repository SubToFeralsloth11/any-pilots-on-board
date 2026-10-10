extends Node3D
## Yellow oxygen masks that drop from the ceiling service panels when the cabin loses
## pressure in flight, plus a one-off condensation fog burst and whoosh. The Airliner
## decides when (from replicated plane state), so every peer drops them together.
##
## Each mask is a cheap pendulum swinging with the felt gravity (the physics-space gravity
## the World writes each frame) and fluttering toward breaches. No physics bodies: cups,
## tubes and the opened hatches are three MultiMeshes.

const MeshBatch := preload("res://scripts/plane/plane_mesh.gd")
const PlaneModels := preload("res://scripts/plane/plane_models.gd")
const TUBE_LENGTH := 0.8
const DAMPING := 1.8
const FLUTTER := 0.9
const SUCTION_PULL := 0.12
const MIX_RATE := 22050
const CUP_SCALE := 1.5      ## Chunky cartoon proportions.

var deployed := false

var _plane: Airliner
var _anchors := PackedVector3Array()
var _tips := PackedVector3Array()    ## Tube end relative to its anchor (plane-local).
var _vels := PackedVector3Array()
var _phases := PackedFloat32Array()
var _age := 0.0
var _cups: MultiMeshInstance3D
var _tubes: MultiMeshInstance3D
var _hatches: MultiMeshInstance3D


## anchors: one per seat (plane-local); hatches: one open-hatch transform per service panel.
func setup(plane: Airliner, anchors: PackedVector3Array, hatches: Array[Transform3D]) -> void:
	_plane = plane
	_anchors = anchors
	_tips.resize(anchors.size())
	_vels.resize(anchors.size())
	_phases.resize(anchors.size())
	for k in anchors.size():
		_phases[k] = k * 2.399   # Golden-angle spread: no two masks flutter in step.
	var b := MeshBatch.new()
	PlaneModels.oxygen_mask(b)
	_cups = _multi(b.commit(), anchors.size())
	PlaneModels.mask_tube(b)
	_tubes = _multi(b.commit(), anchors.size())
	b.rounded_box(Vector3(0.86, 0.016, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.15)),
		Color(0.93, 0.94, 0.95), MeshBatch.Finish.PAINT, 0.2, 8, 4)
	_hatches = _multi(b.commit(), hatches.size())
	for k in hatches.size():
		_hatches.multimesh.set_instance_transform(k, hatches[k])
	set_process(false)


func _multi(mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	add_child(mmi)
	return mmi


## Drops the masks. animate = false (late joiners) puts them straight down, silently.
func deploy(animate: bool) -> void:
	if deployed:
		return
	deployed = true
	_age = 0.0 if animate else 10.0
	for k in _anchors.size():
		_tips[k] = Vector3(0, -0.02 if animate else -TUBE_LENGTH, 0)
		_vels[k] = Vector3.ZERO
	for m in [_cups, _tubes, _hatches]:
		m.visible = true
	set_process(true)
	if animate:
		_fog_burst()
		_whoosh()


func _process(dt: float) -> void:
	_age += dt
	var length := _drop_length(_age)
	var space := get_world_3d().space
	var g_world: Vector3 = PhysicsServer3D.area_get_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR) \
		* float(PhysicsServer3D.area_get_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY))
	var to_local_b := global_basis.inverse()
	var g := to_local_b * g_world
	var damp := exp(-DAMPING * dt)
	for k in _anchors.size():
		var ph := _phases[k]
		var acc := g + Vector3(sin(_age * 3.1 + ph), 0.0, cos(_age * 2.3 + ph * 1.7)) * FLUTTER
		acc += to_local_b * _plane.get_suction(to_global(_anchors[k])) * SUCTION_PULL
		var v := (_vels[k] + acc * dt) * damp
		var tip := _tips[k] + v * dt
		var dir := tip.normalized() if tip.length_squared() > 1e-8 else Vector3.DOWN
		tip = dir * length
		v -= dir * v.dot(dir)   # The tube is taut: only swinging motion survives.
		_tips[k] = tip
		_vels[k] = v
		_place(k, _anchors[k], tip)


## Tube length while dropping: falls out, overshoots and bounces on the elastic tube.
static func _drop_length(t: float) -> float:
	return maxf(TUBE_LENGTH * (1.0 - exp(-5.0 * t) * cos(7.0 * t)), 0.02)


func _place(k: int, anchor: Vector3, tip: Vector3) -> void:
	var y := -tip.normalized()
	var x := (Vector3.RIGHT - y * y.x).normalized()
	var z := x.cross(y)
	_cups.multimesh.set_instance_transform(k, Transform3D(Basis(x, y, z) * CUP_SCALE, anchor + tip))
	_tubes.multimesh.set_instance_transform(k, Transform3D(Basis(x, -tip, z), anchor + tip))


## White condensation fog filling the cabin for a couple of seconds.
func _fog_burst() -> void:
	var p := CPUParticles3D.new()
	var puff := SphereMesh.new()
	puff.radius = 0.35
	puff.height = 0.7
	puff.radial_segments = 8
	puff.rings = 4
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	puff.material = m
	p.mesh = puff
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = 110
	p.lifetime = 2.6
	p.position = Vector3(0, 1.6, -2.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(2.2, 1.0, 8.0)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.4
	p.gravity = Vector3.ZERO
	p.damping_min = 0.6
	p.damping_max = 1.2
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.6
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.55))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = fade
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## Rushing-air whoosh: low-passed noise with a sharp attack and a long tail.
func _whoosh() -> void:
	var dur := 1.6
	var n := int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var env := minf(t * 40.0, 1.0) * exp(-t * 2.2)
		lp += (randf_range(-1.0, 1.0) - lp) * lerpf(0.5, 0.08, t / dur)
		data.encode_s16(i * 2, int(clampf(lp * env * 1.6, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.data = data
	var p := AudioStreamPlayer3D.new()
	p.stream = w
	p.unit_size = 12.0
	p.volume_db = 2.0
	p.position = Vector3(0, 1.6, -2.0)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
