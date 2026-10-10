extends FunToy
## A dart (kind "dart"). extra {"foam": true} makes a foam blaster dart that despawns after a while.
## In flight it points along its velocity; on hitting the plane fast enough it sticks (tip first)
## and rides along with the hull. Stuck in the dartboard, it scores for whoever threw or shot it.
## Hitting a player boops them; hitting a passenger knocks them over.

const COLORS := [Color(0.95, 0.2, 0.25), Color(0.2, 0.5, 1.0), Color(0.3, 0.85, 0.35), Color(1, 0.8, 0.15)]
const STICK_SPEED := 5.0
const FOAM_LIFE := 14.0

var foam := false
var _stuck := false
var _stuck_local := Transform3D.IDENTITY
var _last_vel := Vector3.ZERO
var _age := 0.0


func _configure(extra: Dictionary) -> void:
	foam = bool(extra.get("foam", false))
	var color: Color = COLORS[int(extra.get("color", 0)) % COLORS.size()]
	display = "foam dart" if foam else "dart"
	hint = "Throw it [LMB] at the dartboard on the cargo-hold bulkhead." if not foam else ""
	mass = 0.03 if foam else 0.05
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	physics_material_override = FunLooks.phys(0.5, 0.3)
	var cap := CapsuleShape3D.new()
	cap.radius = 0.02
	cap.height = 0.17
	add_shape(cap, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO))
	var fwd := Vector3(-PI / 2, 0, 0)    # Mesh +Y -> -Z (the tip).
	if foam:
		part(FunLooks.cyl(0.017, 0.017, 0.1), FunLooks.mat(Color(1, 0.55, 0.1), 0.9), Vector3(0, 0, 0.01), fwd)
		part(FunLooks.cyl(0.028, 0.016, 0.022), FunLooks.mat(Color(0.9, 0.15, 0.15), 0.4), Vector3(0, 0, -0.05), fwd)
		part(FunLooks.torus(0.014, 0.02), FunLooks.mat(Color(0.2, 0.45, 1.0), 0.6), Vector3(0, 0, 0.05),
			Vector3(PI / 2, 0, 0))
	else:
		part(FunLooks.cyl(0.0006, 0.0045, 0.05), FunLooks.metal(FunLooks.CHROME), Vector3(0, 0, -0.075), fwd)
		part(FunLooks.cyl(0.009, 0.006, 0.055), FunLooks.metal(FunLooks.BRASS), Vector3(0, 0, -0.025), fwd)
		part(FunLooks.cyl(0.0045, 0.0045, 0.05), FunLooks.mat(color, 0.4), Vector3(0, 0, 0.025), fwd)
		var flight := FunLooks.prism(Vector3(0.05, 0.05, 0.002))
		for i in 2:
			part(flight, FunLooks.mat(color, 0.5), Vector3(0, 0, 0.065), Vector3(-PI / 2, 0, i * PI / 2))


func _ready() -> void:
	if world.is_server():
		body_entered.connect(_on_hit)


func get_prompt() -> String:
	return "Pull out the %s [E]" % display if _stuck else super()


func on_grabbed(peer: int) -> void:
	super(peer)
	_age = 0.0
	if _stuck:
		_stuck = false
		freeze = false


func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
	if _stuck or holder != 0 or not world.is_server():
		return
	var v := st.linear_velocity
	if v.length() > 3.0:
		var up := Vector3.UP if absf(v.normalized().y) < 0.95 else Vector3.BACK
		st.transform = Transform3D(Basis.looking_at(v, up), st.transform.origin)
		st.angular_velocity = Vector3.ZERO


func _physics_process(dt: float) -> void:
	if not world.is_server():
		return
	if _stuck:
		global_transform = world.plane.global_transform * _stuck_local
	else:
		_last_vel = linear_velocity
	if foam and holder == 0:
		_age += dt
		if _age > FOAM_LIFE:
			world.despawn_object(World.net_id(self))


func _on_hit(body: Node) -> void:
	if _stuck or holder != 0:
		return
	var speed := _last_vel.length()
	var dir := _last_vel.normalized()
	if body is Airliner and speed > STICK_SPEED and dir.dot(-global_basis.z) > 0.5:
		_stick.call_deferred()
	elif body is Player and speed > 4.0:
		world.push_player((body as Player).peer_id, dir * (2.5 if foam else 1.5) + Vector3(0, 1.5, 0))
		world.object_event(World.net_id(self), "boop", [global_position])
	elif body is RigidBody3D and (body as Node).is_in_group("npc") and speed > 4.0:
		if body.has_method("on_punched"):
			body.on_punched(last_peer, dir)
		world.object_event(World.net_id(self), "boop", [global_position])


func _stick() -> void:
	if _stuck or holder != 0:
		return
	_stuck = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	linear_velocity = Vector3.ZERO
	global_position += -global_basis.z * 0.025
	_stuck_local = world.plane.global_transform.affine_inverse() * global_transform
	var tip := global_position - global_basis.z * 0.09
	world.object_event(World.net_id(self), "thwack", [tip])
	var board := (world.fun as FunGames).stations.get("dartboard") as FunDartboard
	if board:
		board.score_hit(tip, last_peer)


func on_net_event(event: String, args: Array) -> void:
	match event:
		"thwack":
			FunFx.burst(world, args[0], [Color(0.9, 0.85, 0.7)], 6, 1.2, 0.02)
			FunFx.popup(world, args[0], "thwop!" if foam else "THUNK", Color(1, 0.8, 0.5), 40)
		"boop":
			FunFx.popup(world, args[0], "BOOP!", Color(1, 0.6, 0.2), 56)
