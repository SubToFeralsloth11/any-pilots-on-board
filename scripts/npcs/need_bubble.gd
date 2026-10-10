class_name NeedBubble
extends Node3D
## Chunky request bubble over a passenger's head (every peer): a white disc with a patience
## ring that drains clockwise from green to red, and a 3D model of what they want in front.
## The disc and ring are one quad drawn by a shared shader (per-instance `fill`), the icons
## are cached merged meshes, so a bubble costs two or three draw calls and only while shown.

const ServiceLooks := preload("res://scripts/service/service_looks.gd")

const SIZE := 0.46
const SHADER := "shader_type spatial;
render_mode unshaded, cull_disabled;
instance uniform float fill = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float r = length(p);
	float a = fract(atan(p.x, p.y) / 6.2831853 + 1.0);
	bool tail = p.y < -0.6 && p.y > -1.0 && abs(p.x + 0.25) < (p.y + 1.0) * 0.45;
	vec3 ring = mix(vec3(0.95, 0.15, 0.1), vec3(0.25, 0.85, 0.3), smoothstep(0.15, 0.6, fill));
	vec3 col;
	if (r < 0.7) {
		col = vec3(1.0);
	} else if (r < 0.75) {
		col = vec3(0.15, 0.12, 0.2);
	} else if (r < 0.96) {
		col = a < fill ? ring : vec3(0.3, 0.3, 0.35);
	} else if (r < 1.0 || tail) {
		col = tail && r >= 0.96 ? vec3(1.0) : vec3(0.15, 0.12, 0.2);
	} else {
		discard;
	}
	ALBEDO = col;
}"

static var _mat: ShaderMaterial
static var _quad: QuadMesh

var need := ""
var _total := 1.0
var _left := 0.0
var _disc: MeshInstance3D
var _icons := {}
var _bob := 0.0


func _ready() -> void:
	top_level = true
	visible = false
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_quad = QuadMesh.new()
		_quad.size = Vector2(SIZE, SIZE)
	_disc = MeshInstance3D.new()
	_disc.mesh = _quad
	_disc.material_override = _mat
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)


## Shows `kind` with `left` of `total` seconds of patience ("" hides the bubble).
func show_need(kind: String, total: float, left: float) -> void:
	need = kind
	_total = maxf(total, 0.01)
	_left = left
	visible = kind != ""
	for k: String in _icons:
		(_icons[k] as Node3D).visible = k == kind
	if kind != "" and not _icons.has(kind):
		var icon := Node3D.new()
		icon.position = Vector3(0, 0.01, 0.08)
		icon.rotation = Vector3(0.9, 0.5, 0)
		icon.scale = Vector3.ONE * {"meal": 0.62, "blanket": 0.72}.get(kind, 1.35)
		add_child(icon)
		ServiceLooks.build(icon, kind)
		_icons[kind] = icon


## Follows the head and faces the camera; drains the ring.
func tick(dt: float, at: Vector3) -> void:
	if not visible:
		return
	_left = maxf(_left - dt, 0.0)
	_bob += dt
	_disc.set_instance_shader_parameter("fill", _left / _total)
	var cam := get_viewport().get_camera_3d()
	var b := cam.global_basis if cam else Basis()
	var urgent := _left / _total < 0.25
	var s := 1.0 + (sin(_bob * 14.0) * 0.06 if urgent else 0.0)
	global_transform = Transform3D(b.scaled(Vector3.ONE * s), at + Vector3(0, sin(_bob * 2.5) * 0.02, 0))
