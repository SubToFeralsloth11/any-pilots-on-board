extends RigidBody3D
## An escaped hen (kind "chicken"): a small NPC-lite rigid body that scurries around the plane,
## flaps into the air and clucks. Grab it [E] and drop or throw it into its coop to return it.
## extra: {coop: net_id of its coop, contract: id, brown: bool}.
##
## Host: wandering/fleeing, flapping, staying upright, homing check. All peers: wing and bob
## animation (clients from snapshot motion), cluck/flap cosmetics via on_net_event.

const CargoLooks := preload("res://scripts/cargo/cargo_looks.gd")
const Sfx := preload("res://scripts/cargo/cargo_sfx.gd")
const Fx := preload("res://scripts/props/fx.gd")

const RADIUS := 0.14
const WALK_SPEED := 1.6
const FLEE_SPEED := 3.4
const FLEE_RADIUS := 2.2
const STEER := 7.0              ## Velocity steering gain (1/s) while on the floor.
const UPRIGHT := 6.0            ## Uprighting torque gain.
const FLAP_CHANCE := 0.12       ## Per second while calm (more when fleeing).
const FLAP_UP := 3.2
const CLUCK_CHANCE := 0.12
const HOME_REACH := 0.75        ## Distance to the coop centre that counts as "back in".
const HOME_WINDOW := 2.5        ## Seconds after a drop/throw during which it can go home.
const LINES := ["BAWK!", "*indignant clucking*", "BUK BUK BUKAAAW!", "*flaps menacingly*"]

var module: Node
var world: World
var coop_id := 0
var brown := false
var parts := {}

var _vis: Node3D
var _wander := Vector3.ZERO
var _wander_t := 0.0
var _carried := false
var _home_t := 0.0
var _age := 0.0
var _last_pos := Vector3.ZERO
var _speed_vis := 0.0
var _anim_t := 0.0
var _flap_vis := 0.0


func setup(m: Node, w: World, extra: Dictionary) -> void:
	module = m
	world = w
	coop_id = int(extra.get("coop", 0))
	brown = bool(extra.get("brown", false))
	mass = 1.3
	physics_material_override = FunLooks.phys(0.4, 0.2)
	linear_damp = 0.3
	angular_damp = 3.0
	can_sleep = false
	collision_layer = Layers.PROP
	collision_mask = Layers.WORLD | Layers.PLAYER | Layers.PROP | Layers.NPC
	add_to_group("grabbable")
	set_meta("contract", int(extra.get("contract", -1)))
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = RADIUS
	cs.shape = sh
	cs.position = Vector3(0, -0.03, 0)
	add_child(cs)


func _ready() -> void:
	_vis = Node3D.new()
	add_child(_vis)
	CargoLooks.chicken(_vis, parts, brown)
	_last_pos = global_position
	var host := world.is_server()
	set_physics_process(host)
	if host:
		contact_monitor = true
		max_contacts_reported = 2


func get_prompt() -> String:
	return "Escaped chicken!   Grab it [E], then drop it in its coop"


func on_grabbed(peer: int) -> void:
	_carried = true
	world.object_event(World.net_id(self), "cluck", [true])
	world.notify(peer, "Got one! Drop it [E] or throw it into its coop.")


func on_released() -> void:
	_carried = false
	_home_t = HOME_WINDOW
	_try_home()


func on_thrown(_peer: int) -> void:
	_home_t = HOME_WINDOW


func on_lost() -> void:
	var coop := world.get_object(coop_id)
	if coop and coop.has_method("hen_lost"):
		coop.hen_lost(World.net_id(self))
	world.say("", "A chicken has left the aircraft. It was not a strong flier.", 3.0)


# --- Host -----------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	_age += dt
	if _home_t > 0.0:
		_home_t -= dt
		if _try_home():
			return
	var up := world.plane.global_basis.y
	# Stay upright (ignoring yaw) unless carried.
	if not _carried:
		var tilt := global_basis.y.cross(up)
		apply_torque((tilt * UPRIGHT - angular_velocity * 0.6 + up * up.dot(angular_velocity) * 0.6) * mass * 0.05)
	if _carried:
		if randf() < dt * 0.8:
			world.object_event(World.net_id(self), "flap")
		return
	var grounded := get_contact_count() > 0
	_wander_t -= dt
	var flee := _threat(up)
	if _wander_t <= 0.0:
		_wander_t = randf_range(0.8, 2.5)
		var a := randf() * TAU
		_wander = (world.plane.global_basis.x * cos(a) + world.plane.global_basis.z * sin(a)) * (WALK_SPEED if randf() < 0.75 else 0.0)
	var want := _wander
	if flee != Vector3.ZERO:
		want = flee * FLEE_SPEED
	# Keep away from the open ramp edge a little (it's still a chicken, not a lemming).
	var local := world.plane.to_local(global_position)
	if local.z > Airliner.TAIL_Z - 1.0 and want.dot(world.plane.global_basis.z) > 0.0:
		want -= world.plane.global_basis.z * want.dot(world.plane.global_basis.z) * 2.0
	if grounded:
		var v := linear_velocity
		var flat := v - up * v.dot(up)
		apply_central_force((want - flat) * STEER * mass)
		if randf() < dt * (FLAP_CHANCE * (3.0 if flee != Vector3.ZERO else 1.0)):
			apply_central_impulse((up * FLAP_UP + want.normalized() * 1.2) * mass)
			world.object_event(World.net_id(self), "flap")
	if want.length() > 0.2:
		var fwd := -global_basis.z
		fwd -= up * fwd.dot(up)
		var turn := fwd.normalized().cross(want.normalized()).dot(up)
		apply_torque(up * turn * mass * 0.06)
	if randf() < dt * CLUCK_CHANCE:
		world.object_event(World.net_id(self), "cluck", [false])


## Direction away from the nearest player closer than FLEE_RADIUS (zero if none).
func _threat(up: Vector3) -> Vector3:
	var best := FLEE_RADIUS
	var away := Vector3.ZERO
	for peer in world.players:
		var pl: Player = world.players[peer]
		var d := global_position - pl.global_position
		d -= up * d.dot(up)
		if d.length() < best:
			best = d.length()
			away = d.normalized()
	return away


func _try_home() -> bool:
	if _carried:
		return false
	var coop := world.get_object(coop_id)
	if coop == null or global_position.distance_to(coop.global_position) > HOME_REACH:
		return false
	return module.return_chicken(self)


# --- Cosmetics (all peers) ------------------------------------------------------------------

func _process(dt: float) -> void:
	_anim_t += dt
	var moved := global_position.distance_to(_last_pos) / maxf(dt, 0.0001)
	_last_pos = global_position
	_speed_vis = lerpf(_speed_vis, minf(moved, 5.0), clampf(dt * 8.0, 0.0, 1.0))
	_flap_vis = maxf(0.0, _flap_vis - dt)
	var bob := absf(sin(_anim_t * 18.0)) * 0.04 * clampf(_speed_vis / 2.0, 0.0, 1.0)
	_vis.position.y = bob
	_vis.rotation.x = -0.25 * clampf(_speed_vis / 3.0, 0.0, 1.0)
	var wing := 0.15
	if _flap_vis > 0.0 or _speed_vis > 3.0:
		wing = 0.6 + 0.6 * sin(_anim_t * 40.0)
	(parts.wing_l as Node3D).rotation.z = -wing
	(parts.wing_r as Node3D).rotation.z = wing


func on_net_event(event: String, args: Array) -> void:
	var fxroot := get_parent()
	var at := global_position
	match event:
		"cluck":
			Sfx.play(fxroot, at, "bawk" if bool(args[0]) else "cluck", -4.0, 1.0 if not brown else 0.85)
			if bool(args[0]) or randf() < 0.3:
				Fx.popup(fxroot, at + Vector3(0, 0.35, 0), LINES.pick_random() if bool(args[0]) else "cluck", Color(1, 0.95, 0.5), 40)
		"flap":
			_flap_vis = 0.6
			Sfx.play(fxroot, at, "flap", -6.0)
			Fx.burst(fxroot, at, CargoLooks.HEN_BROWN if brown else CargoLooks.HEN, 5, 1.5, 0.035, Vector3(0, -1.5, 0), 1.5)
		"home":
			Fx.burst(fxroot, at, CargoLooks.HEN, 10, 1.5, 0.035, Vector3(0, -1.5, 0), 1.2)
			Fx.popup(fxroot, at + Vector3(0, 0.4, 0), "HOME!", Color(0.6, 1, 0.5), 52)
			Sfx.play(fxroot, at, "cluck", -2.0, 1.2)
