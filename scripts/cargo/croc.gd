extends RigidBody3D
## The escaped crocodile (kind "croc"): a heavy physics creature that crawls toward the nearest
## person (player or passenger) and snaps at them (players get knocked back, passengers
## ragdoll). Grab it by the tail [E] (heavy, it thrashes and may bite the carrier), then drop it
## into its open crate to return it, or throw it out of the ramp (lost).
## extra: {crate: net_id of its crate, contract: id}.

const CargoLooks := preload("res://scripts/cargo/cargo_looks.gd")
const Sfx := preload("res://scripts/cargo/cargo_sfx.gd")
const Fx := preload("res://scripts/props/fx.gd")

const MASS := 35.0
const CRAWL_SPEED := 1.6
const LUNGE_SPEED := 4.5
const AGGRO_RADIUS := 14.0
const BITE_REACH := 0.85        ## Snout to target (flat distance) that lands a bite.
const LUNGE_RANGE := 2.4
const BITE_COOLDOWN := 2.2
const THINK := 0.3
const STEER := 5.0
const TURN := 7.0
const UPRIGHT := 10.0
const CARRY_BITE_GAP := 3.0     ## Seconds between chances to bite whoever carries it.
const CARRY_BITE_CHANCE := 0.35
const HOME_REACH := 1.1
const HOME_WINDOW := 2.5
const SNOUT := Vector3(0, 0, -1.0)
const BITE_LINES := ["OW! IT BIT ME!", "MY LEG! IT HAS MY LEG!", "BAD CROCODILE! BAD!", "WHO PACKED THIS?!",
	"It's fine. I have another butt."]
const CARRY_LINES := ["It's trying to eat my face!", "IT'S WRIGGLING!", "This was NOT in the job description!"]
const NPC_LINES := ["AAAH! A CROCODILE!", "IT'S EATING MY SHOE!", "Is this the in-flight entertainment?!",
	"I want a REFUND!"]

var module: Node
var world: World
var crate_id := 0
var parts := {}

var _vis: Node3D
var _target: Node3D
var _think_t := 0.0
var _bite_t := 1.0
var _carry_bite_t := CARRY_BITE_GAP
var _carried := false
var _holder := 0
var _home_t := 0.0
var _lunge_t := 0.0
var _last_pos := Vector3.ZERO
var _speed_vis := 0.0
var _anim_t := 0.0
var _snap_vis := 0.0


func setup(m: Node, w: World, extra: Dictionary) -> void:
	module = m
	world = w
	crate_id = int(extra.get("crate", 0))
	mass = MASS
	physics_material_override = FunLooks.phys(0.25, 0.05)
	linear_damp = 0.4
	angular_damp = 2.5
	can_sleep = false
	collision_layer = Layers.PROP
	collision_mask = Layers.WORLD | Layers.PLAYER | Layers.PROP | Layers.NPC
	add_to_group("grabbable")
	set_meta("contract", int(extra.get("contract", -1)))
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.52, 0.3, 1.5)
	cs.shape = bs
	cs.position = Vector3(0, -0.02, -0.05)
	add_child(cs)
	var tail := CollisionShape3D.new()
	var ts := BoxShape3D.new()
	ts.size = Vector3(0.22, 0.16, 0.6)
	tail.shape = ts
	tail.position = Vector3(0, -0.06, 0.95)
	add_child(tail)


func _ready() -> void:
	_vis = Node3D.new()
	add_child(_vis)
	CargoLooks.crocodile(_vis, parts)
	_last_pos = global_position
	var host := world.is_server()
	set_physics_process(host)
	if host:
		contact_monitor = true
		max_contacts_reported = 3


func get_prompt() -> String:
	return "THE CROCODILE!   Grab it by the tail [E] (heavy!)"


func on_grabbed(peer: int) -> void:
	_carried = true
	_holder = peer
	_carry_bite_t = CARRY_BITE_GAP
	world.notify(peer, "You've got it by the tail! Drop it in its crate [E] or throw it out the ramp [LMB].")
	world.object_event(World.net_id(self), "hiss")


func on_released() -> void:
	_carried = false
	_holder = 0
	_home_t = HOME_WINDOW
	_bite_t = maxf(_bite_t, 1.0)
	_try_home()


func on_thrown(_peer: int) -> void:
	_home_t = HOME_WINDOW


func on_lost() -> void:
	var crate := world.get_object(crate_id)
	if crate and crate.get("state") is Dictionary:
		crate.state.croc_lost = true
	world.say("", "The crocodile has left the aircraft. Somewhere below, a farmer is having a very strange day.", 4.0)


# --- Host -----------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	_bite_t -= dt
	_lunge_t -= dt
	if _home_t > 0.0:
		_home_t -= dt
		if _try_home():
			return
	var plane := world.plane
	var up := plane.global_basis.y
	if _carried:
		# Thrash: random twists, and now and then a bite at whoever is holding it.
		if randf() < dt * 3.0:
			apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * mass * 0.35)
		_carry_bite_t -= dt
		if _carry_bite_t <= 0.0:
			_carry_bite_t = CARRY_BITE_GAP
			if randf() < CARRY_BITE_CHANCE and world.players.has(_holder):
				var pl: Player = world.players[_holder]
				_bite_player(_holder, pl, up)
				world.say(world.display_name(_holder), CARRY_LINES.pick_random(), 2.5)
		return
	var tilt := global_basis.y.cross(up)
	apply_torque((tilt * UPRIGHT - (angular_velocity - up * up.dot(angular_velocity)) * 1.5) * mass * 0.08)
	_think_t -= dt
	if _think_t <= 0.0:
		_think_t = THINK
		_target = _find_target(up)
	if _target == null or not is_instance_valid(_target):
		_target = null
		return
	var snout := global_transform * SNOUT
	var to := _target.global_position - global_position
	to -= up * to.dot(up)
	var to_snout := _target.global_position - snout
	to_snout -= up * to_snout.dot(up)
	var dir := to.normalized()
	var grounded := get_contact_count() > 0
	if grounded:
		var speed := LUNGE_SPEED if _lunge_t > 0.0 else CRAWL_SPEED
		var flat := linear_velocity - up * linear_velocity.dot(up)
		apply_central_force((dir * speed - flat) * STEER * mass)
		if to.length() < LUNGE_RANGE and _bite_t <= 0.4 and _lunge_t <= -0.6:
			_lunge_t = 0.45
	var fwd := -global_basis.z
	fwd -= up * fwd.dot(up)
	var turn := fwd.normalized().cross(dir).dot(up)
	if fwd.normalized().dot(dir) < 0.0:
		turn = 1.0 if turn >= 0.0 else -1.0
	apply_torque(up * turn * TURN * mass * 0.12)
	if to_snout.length() < BITE_REACH and _bite_t <= 0.0:
		_bite(_target, up)


## Nearest player or passenger inside the plane within AGGRO_RADIUS.
func _find_target(up: Vector3) -> Node3D:
	var plane := world.plane
	var best: Node3D = null
	var best_d := AGGRO_RADIUS
	for peer in world.players:
		var pl: Player = world.players[peer]
		if plane.is_outside(pl.global_position):
			continue
		var d := (pl.global_position - global_position)
		d -= up * d.dot(up)
		if d.length() < best_d:
			best_d = d.length()
			best = pl
	for npc in get_tree().get_nodes_in_group("npc"):
		var n := npc as Node3D
		if n == null or plane.is_outside(n.global_position):
			continue
		var d := (n.global_position - global_position)
		d -= up * d.dot(up)
		if d.length() < best_d:
			best_d = d.length()
			best = n
	return best


func _bite(target: Node3D, up: Vector3) -> void:
	_bite_t = BITE_COOLDOWN
	if target is Player:
		var pl := target as Player
		_bite_player(pl.peer_id, pl, up)
		world.say(world.display_name(pl.peer_id), BITE_LINES.pick_random(), 2.5)
	else:
		var dir := (target.global_position - global_position)
		dir = (dir - up * dir.dot(up)).normalized()
		world.object_event(World.net_id(self), "snap")
		if target.has_method("ragdoll"):
			target.call("ragdoll", dir * 120.0 + up * 80.0)
		if target.has_method("say_line"):
			target.call("say_line", NPC_LINES.pick_random())
	apply_central_impulse(-global_basis.z * mass * 1.0)


func _bite_player(peer: int, pl: Player, up: Vector3) -> void:
	var dir := pl.global_position - global_position
	dir = (dir - up * dir.dot(up)).normalized()
	world.object_event(World.net_id(self), "snap")
	world.push_player(peer, dir * 9.0 + up * 4.5)
	world.shake_all(0.15)


func _try_home() -> bool:
	if _carried:
		return false
	var crate := world.get_object(crate_id)
	if crate == null or not bool(crate.get("state").get("open", false)):
		return false
	if global_position.distance_to(crate.global_position) > HOME_REACH:
		return false
	return module.return_croc(self)


# --- Cosmetics (all peers) ------------------------------------------------------------------

func _process(dt: float) -> void:
	_anim_t += dt
	var moved := global_position.distance_to(_last_pos) / maxf(dt, 0.0001)
	_last_pos = global_position
	_speed_vis = lerpf(_speed_vis, minf(moved, 6.0), clampf(dt * 6.0, 0.0, 1.0))
	var pace := clampf(_speed_vis / 2.0, 0.0, 1.0)
	(parts.tail as Node3D).rotation.y = sin(_anim_t * (4.0 + 6.0 * pace)) * (0.25 + 0.25 * pace)
	(parts.legs as Node3D).rotation.y = sin(_anim_t * 14.0) * 0.12 * pace
	_vis.rotation.z = sin(_anim_t * 14.0) * 0.06 * pace
	_snap_vis = maxf(0.0, _snap_vis - dt)
	var open := 0.15 + 0.08 * sin(_anim_t * 2.0)
	if _snap_vis > 0.0:
		open = 0.7 * absf(sin(_snap_vis / 0.35 * PI))
	(parts.jaw as Node3D).rotation.x = -open


func on_net_event(event: String, _args: Array) -> void:
	var fxroot := get_parent()
	var at := global_transform * SNOUT
	match event:
		"snap":
			_snap_vis = 0.35
			Sfx.play(fxroot, at, "snap", 2.0)
			Fx.popup(fxroot, at + Vector3(0, 0.4, 0), "CHOMP!", Color(0.5, 1, 0.3), 80)
		"hiss":
			Sfx.play(fxroot, global_position, "hiss", -2.0)
			_snap_vis = 0.35
		"home":
			Fx.popup(fxroot, global_position + Vector3(0, 0.5, 0), "IN YOU GO!", Color(0.5, 1, 0.3), 64)
