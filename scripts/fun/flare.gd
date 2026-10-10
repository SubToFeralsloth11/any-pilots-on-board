extends FunToy
## A burning flare (kind "flare") fired by the flare gun. Too hot to hold. It bounces around,
## scorches the hull where it hits, ignites an engine it gets close to, and burns out.

const LIFE := 7.0
const IGNITE_REACH := 1.8

var _age := 0.0
var _light: OmniLight3D


func _configure(_extra: Dictionary) -> void:
	remove_from_group("grabbable")
	display = "burning flare"
	mass = 0.15
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	gravity_scale = 0.5
	physics_material_override = FunLooks.phys(0.3, 0.6)
	var s := SphereShape3D.new()
	s.radius = 0.04
	add_shape(s)
	part(FunLooks.capsule(0.035, 0.12), FunLooks.mat(Color(0.9, 0.15, 0.1), 0.5), Vector3.ZERO, Vector3(PI / 2, 0, 0))
	part(FunLooks.sphere(0.06, 12), FunLooks.mat(Color(1, 0.6, 0.2, 0.85), 0.2, 0.0, 4.0), Vector3(0, 0, -0.06))
	_light = OmniLight3D.new()
	_light.light_color = Color(1, 0.35, 0.15)
	_light.light_energy = 2.5
	_light.omni_range = 4.0
	add_child(_light)
	var trail := CPUParticles3D.new()
	trail.mesh = FunLooks.sphere(0.03, 6)
	trail.material_override = FunLooks.mat(Color(1, 0.5, 0.15), 0.5, 0.0, 3.0)
	trail.amount = 24
	trail.lifetime = 0.5
	trail.local_coords = false
	trail.gravity = Vector3(0, 1.0, 0)
	trail.spread = 180.0
	trail.initial_velocity_max = 0.5
	trail.scale_amount_min = 0.4
	trail.scale_amount_max = 1.2
	add_child(trail)


func get_prompt() -> String:
	return "A burning flare. Ow. Don't touch it."


func _ready() -> void:
	if world.is_server():
		body_entered.connect(_on_hit)


func _process(_dt: float) -> void:
	_light.light_energy = 2.0 + randf() * 1.2


func _physics_process(dt: float) -> void:
	if not world.is_server():
		return
	_age += dt
	for i in 2:
		if global_position.distance_to(world.plane.engine_fire_point(i)) < IGNITE_REACH:
			if not world.plane.engine_fire[i]:
				world.set_plane("fire:%d" % i, true)
				world.say(world.display_name(last_peer) if last_peer else "Flare",
					"...the %s engine is on fire. I did that." % ["left", "right"][i], 3.0)
			_burn_out()
			return
	if _age > LIFE:
		_burn_out()


func _on_hit(body: Node) -> void:
	if body is Airliner and linear_velocity.length() > 4.0:
		world.damage_plane_at(global_position, 0.02)
	elif body is Player:
		world.push_player((body as Player).peer_id, linear_velocity.normalized() * 3.0 + Vector3(0, 2, 0))
		world.notify((body as Player).peer_id, "OW OW HOT HOT HOT")
	elif body.is_in_group("npc") and body.has_method("on_punched"):
		body.on_punched(last_peer, linear_velocity.normalized())


func _burn_out() -> void:
	world.object_event(World.net_id(self), "fizzle", [global_position])
	world.despawn_object(World.net_id(self))


func on_net_event(event: String, args: Array) -> void:
	if event == "fizzle":
		FunFx.burst(world, args[0], [Color(1, 0.5, 0.1), Color(0.4, 0.4, 0.4)], 20, 2.0, 0.06, Vector3.UP, 90.0, 1.0,
			Vector3(0, 1, 0))
