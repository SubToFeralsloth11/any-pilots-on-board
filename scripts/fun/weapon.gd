class_name FunWeapon
extends FunToy
## Slapstick toy weapons. Pick one up [E], then [RMB] to use it; all effects run on the host
## and cosmetics go out through object_event, so every peer sees the same thing.
##
## Kinds: baguette (swing), frying_pan (BONK), dart_blaster (foam darts), water_pistol (squirt),
## confetti_cannon (burst + recoil), leaf_blower (cone of wind; aim backwards to fly),
## golf_club (whack golf balls and friends), pillow_fight (fluffy flurry).
## While held, the weapon points where its holder is looking.

const SPECS := {
	"baguette": {"name": "baguette sword", "mass": 0.5, "cooldown": 0.45,
		"hint": "En garde! [RMB] swings the baguette. Knocks people over. Somewhat crumbly."},
	"frying_pan": {"name": "frying pan", "mass": 1.6, "cooldown": 0.9,
		"hint": "[RMB] to BONK. Cast iron. Comedy grade."},
	"dart_blaster": {"name": "foam dart blaster", "mass": 0.9, "cooldown": 0.3,
		"hint": "[RMB] fires foam darts. They stick to walls and boop faces."},
	"water_pistol": {"name": "super soaker", "mass": 0.7, "cooldown": 0.12,
		"hint": "[RMB] squirts water. Pushes people and things. Mostly makes them sad."},
	"confetti_cannon": {"name": "confetti cannon", "mass": 1.2, "cooldown": 1.6,
		"hint": "[RMB] CELEBRATES. Kicks like a mule. Brace yourself (or don't)."},
	"leaf_blower": {"name": "leaf blower", "mass": 2.5, "cooldown": 0.15,
		"hint": "[RMB] blows everything in front of you away. Point it behind you to fly."},
	"golf_club": {"name": "golf club", "mass": 0.8, "cooldown": 0.7,
		"hint": "[RMB] swings. Golf balls go very far. So do passengers."},
	"pillow_fight": {"name": "fight pillow", "mass": 0.5, "cooldown": 0.3,
		"hint": "[RMB] for a fluffy smack. Pillow fight rules apply (there are none)."},
}
const WATER := [Color(0.4, 0.75, 1, 0.9), Color(0.75, 0.9, 1, 0.8), Color(0.25, 0.55, 1, 0.9)]
const LEAVES := [Color(0.95, 0.55, 0.15), Color(0.85, 0.3, 0.1), Color(0.95, 0.8, 0.2), Color(0.5, 0.75, 0.25)]
const FEATHERS := [Color(1, 1, 1), Color(0.95, 0.92, 0.85), Color(1, 0.85, 0.9)]
const BONKS := ["BONK.", "*the sound of a cartoon bell*", "That's gonna leave a pan-shaped mark.",
	"Ding dong, your brain is gone.", "Cast iron diplomacy."]
const BAGUETTE_LINES := ["Touché!", "Honhonhon!", "Ze bread of justice!", "*crumbs everywhere*"]
const HOLD_TURN := 18.0

var _ready_at := 0
var _blast_t := 0.0          ## Host: remaining continuous blast time (water, leaf blower).
var _blast_dir := Vector3.FORWARD
var _push_t := 0.0
var _shots := 0


func _configure(_extra: Dictionary) -> void:
	var spec: Dictionary = SPECS[kind]
	display = spec.name
	hint = spec.hint
	mass = spec.mass
	physics_material_override = FunLooks.phys(0.45, 0.2)
	angular_damp = 1.0
	match kind:
		"baguette": _build_baguette()
		"frying_pan": _build_pan()
		"dart_blaster": _build_blaster()
		"water_pistol": _build_soaker()
		"confetti_cannon": _build_cannon()
		"leaf_blower": _build_blower()
		"golf_club": _build_club()
		"pillow_fight": _build_pillow()


func get_prompt() -> String:
	return "Pick up the %s [E]" % display


# --- Looks (every weapon points along -Z) ---------------------------------------------

func _box_shape(size: Vector3, at := Vector3.ZERO) -> void:
	var b := BoxShape3D.new()
	b.size = size
	add_shape(b, Transform3D(Basis.IDENTITY, at))


func _build_baguette() -> void:
	_box_shape(Vector3(0.09, 0.08, 0.75))
	var crust := FunLooks.mat(Color(0.82, 0.55, 0.22), 0.85)
	part(FunLooks.capsule(0.045, 0.72), crust, Vector3.ZERO, Vector3(PI / 2, 0, 0), Vector3(1, 0.85, 1))
	var score := FunLooks.mat(Color(0.97, 0.86, 0.6), 0.9)
	for i in 5:
		part(FunLooks.capsule(0.012, 0.09), score, Vector3(0, 0.036, -0.24 + i * 0.12), Vector3(PI / 2, 0.5, 0))
	# Little paper sleeve "hilt".
	part(FunLooks.cyl(0.05, 0.055, 0.14), FunLooks.mat(Color(0.95, 0.92, 0.82), 0.95), Vector3(0, 0, 0.27),
		Vector3(PI / 2, 0, 0))
	part(FunLooks.cyl(0.051, 0.051, 0.02), FunLooks.mat(Color(0.15, 0.3, 0.8)), Vector3(0, 0, 0.25), Vector3(PI / 2, 0, 0))
	part(FunLooks.cyl(0.051, 0.051, 0.02), FunLooks.mat(Color(0.9, 0.15, 0.2)), Vector3(0, 0, 0.29), Vector3(PI / 2, 0, 0))


func _build_pan() -> void:
	_box_shape(Vector3(0.3, 0.06, 0.62), Vector3(0, 0, -0.08))
	var iron := FunLooks.mat(Color(0.18, 0.18, 0.2), 0.35, 0.6)
	part(FunLooks.cyl(0.15, 0.13, 0.05, 28), iron, Vector3(0, 0, -0.2))
	part(FunLooks.cyl(0.13, 0.13, 0.008, 28), FunLooks.mat(Color(0.3, 0.3, 0.33), 0.5, 0.4), Vector3(0, 0.022, -0.2))
	part(FunLooks.torus(0.135, 0.155), iron, Vector3(0, 0.025, -0.2), Vector3.ZERO, Vector3(1, 0.5, 1))
	part(FunLooks.capsule(0.022, 0.3), FunLooks.mat(FunLooks.WOOD_DARK, 0.6), Vector3(0, 0.01, 0.1),
		Vector3(PI / 2 - 0.12, 0, 0))
	part(FunLooks.torus(0.012, 0.02), FunLooks.metal(FunLooks.CHROME), Vector3(0, 0.03, 0.24), Vector3(0, 0, PI / 2))
	# A fried egg, permanently welded on.
	part(FunLooks.sphere(0.06, 14), FunLooks.mat(Color(1, 1, 0.97), 0.5), Vector3(0.02, 0.028, -0.21), Vector3.ZERO,
		Vector3(1.2, 0.12, 1))
	part(FunLooks.sphere(0.025, 12), FunLooks.mat(Color(1, 0.75, 0.1), 0.3), Vector3(0.03, 0.035, -0.2), Vector3.ZERO,
		Vector3(1, 0.6, 1))


func _build_blaster() -> void:
	_box_shape(Vector3(0.1, 0.22, 0.42), Vector3(0, -0.03, 0))
	var orange := FunLooks.mat(Color(1, 0.5, 0.1), 0.45)
	var blue := FunLooks.mat(Color(0.15, 0.4, 0.95), 0.45)
	FunLooks.rounded_box(vis, Vector3(0.09, 0.1, 0.34), 0.03, blue, Vector3(0, 0.02, 0))
	part(FunLooks.cyl(0.03, 0.03, 0.18), orange, Vector3(0, 0.03, -0.22), Vector3(PI / 2, 0, 0))
	part(FunLooks.torus(0.025, 0.04), FunLooks.mat(Color(1, 0.85, 0.15), 0.4), Vector3(0, 0.03, -0.31), Vector3(PI / 2, 0, 0))
	part(FunLooks.cyl(0.045, 0.045, 0.08, 6), orange, Vector3(0, 0.02, 0.0), Vector3(0, 0, PI / 2))
	part(FunLooks.capsule(0.025, 0.15), blue, Vector3(0, -0.1, 0.1), Vector3(0.35, 0, 0))
	part(FunLooks.torus(0.025, 0.035), orange, Vector3(0, -0.04, 0.02), Vector3(0, 0, PI / 2))
	part(FunLooks.sphere(0.018), FunLooks.mat(Color(0.3, 1, 0.4), 0.3, 0.0, 1.5), Vector3(0, 0.08, 0.1))


func _build_soaker() -> void:
	_box_shape(Vector3(0.1, 0.24, 0.44), Vector3(0, 0, 0))
	var green := FunLooks.mat(Color(0.2, 0.85, 0.35), 0.35)
	var purple := FunLooks.mat(Color(0.6, 0.25, 0.9), 0.35)
	part(FunLooks.capsule(0.04, 0.36), green, Vector3(0, 0, -0.02), Vector3(PI / 2, 0, 0))
	part(FunLooks.cyl(0.015, 0.02, 0.12), purple, Vector3(0, 0.01, -0.25), Vector3(PI / 2, 0, 0))
	part(FunLooks.sphere(0.075, 18), FunLooks.mat(Color(0.35, 0.7, 1, 0.65), 0.1), Vector3(0, 0.1, 0.05))
	part(FunLooks.cyl(0.02, 0.02, 0.05), purple, Vector3(0, 0.17, 0.05))
	part(FunLooks.capsule(0.025, 0.14), purple, Vector3(0, -0.1, 0.1), Vector3(0.3, 0, 0))
	part(FunLooks.capsule(0.02, 0.1), purple, Vector3(0, -0.06, -0.1), Vector3(0, 0, 0))


func _build_cannon() -> void:
	_box_shape(Vector3(0.16, 0.16, 0.5))
	var gold := FunLooks.metal(FunLooks.BRASS)
	part(FunLooks.cyl(0.08, 0.06, 0.42, 20), FunLooks.mat(Color(0.9, 0.2, 0.55), 0.4), Vector3.ZERO, Vector3(-PI / 2, 0, 0))
	for i in 3:
		part(FunLooks.torus(0.062 + i * 0.006, 0.075 + i * 0.006), gold, Vector3(0, 0, 0.12 - i * 0.12), Vector3(PI / 2, 0, 0))
	part(FunLooks.sphere(0.065), gold, Vector3(0, 0, 0.23))
	for i in 6:
		var a := i * TAU / 6
		part(FunLooks.sphere(0.014, 6), FunLooks.mat(FunLooks.CONFETTI[i]), Vector3(cos(a) * 0.06, sin(a) * 0.06, -0.21))
	part(FunLooks.capsule(0.025, 0.12), FunLooks.mat(FunLooks.WOOD_DARK), Vector3(0, -0.1, 0.06))


func _build_blower() -> void:
	_box_shape(Vector3(0.24, 0.3, 0.7), Vector3(0, 0, 0.05))
	var orange := FunLooks.mat(Color(1, 0.45, 0.08), 0.5)
	var dark := FunLooks.mat(Color(0.2, 0.2, 0.22), 0.6)
	FunLooks.rounded_box(vis, Vector3(0.22, 0.22, 0.24), 0.07, orange, Vector3(0, 0, 0.22))
	part(FunLooks.cyl(0.1, 0.1, 0.06, 20), dark, Vector3(0.12, 0, 0.22), Vector3(0, 0, PI / 2))
	part(FunLooks.cyl(0.05, 0.065, 0.55, 16), FunLooks.mat(Color(0.95, 0.95, 0.9), 0.4), Vector3(0, -0.02, -0.18),
		Vector3(-PI / 2, 0, 0))
	part(FunLooks.torus(0.045, 0.06), dark, Vector3(0, -0.02, -0.45), Vector3(PI / 2, 0, 0))
	part(FunLooks.torus(0.04, 0.055), dark, Vector3(0, 0.13, 0.22), Vector3(0, 0, PI / 2), Vector3(1, 1, 1.5))
	part(FunLooks.cyl(0.01, 0.01, 0.05), FunLooks.mat(Color(0.9, 0.1, 0.1)), Vector3(0, 0.1, 0.3), Vector3(0, 0, PI / 2))


func _build_club() -> void:
	_box_shape(Vector3(0.08, 0.1, 0.95), Vector3(0, 0, -0.05))
	part(FunLooks.cyl(0.01, 0.014, 0.85), FunLooks.metal(FunLooks.CHROME), Vector3(0, 0, -0.05), Vector3(-PI / 2, 0, 0))
	part(FunLooks.capsule(0.022, 0.22), FunLooks.mat(Color(0.12, 0.12, 0.14), 0.9), Vector3(0, 0, 0.32), Vector3(PI / 2, 0, 0))
	FunLooks.rounded_box(vis, Vector3(0.12, 0.05, 0.05), 0.02, FunLooks.metal(Color(0.6, 0.62, 0.68)), Vector3(0.04, -0.02, -0.48))
	part(FunLooks.box(Vector3(0.002, 0.04, 0.04)), FunLooks.mat(Color(0.2, 0.2, 0.25)), Vector3(0.1, -0.02, -0.48))


func _build_pillow() -> void:
	_box_shape(Vector3(0.45, 0.14, 0.32))
	var cloth := FunLooks.mat(Color(0.95, 0.6, 0.8), 0.95)
	part(FunLooks.sphere(0.2, 18), cloth, Vector3.ZERO, Vector3.ZERO, Vector3(1.15, 0.35, 0.8))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			part(FunLooks.sphere(0.05, 8), cloth, Vector3(sx * 0.19, 0, sz * 0.12), Vector3.ZERO, Vector3(1, 0.5, 1))
	part(FunLooks.torus(0.03, 0.045), FunLooks.mat(Color(1, 1, 1)), Vector3(0, 0.07, 0), Vector3.ZERO, Vector3(1, 0.4, 1))
	FunLooks.label(vis, "ZZZ", Vector3(0, 0.075, 0.05), 40, Color(0.5, 0.2, 0.6), Vector3(-PI / 2, 0, 0))


# --- Host behaviour --------------------------------------------------------------------

func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
	if holder == 0 or not world.is_server():
		return
	var p: Player = world.players.get(holder)
	if p == null:
		return
	var want := p.head.global_basis.get_rotation_quaternion()
	var have := st.transform.basis.get_rotation_quaternion()
	var diff := want * have.inverse()
	var axis := diff.get_axis()
	var angle := diff.get_angle()
	if angle > PI:
		angle -= TAU
	st.angular_velocity = axis.normalized() * angle * HOLD_TURN if axis.length() > 0.001 else Vector3.ZERO


## Host. Right-click while holding: cooldown and origin sanity, then the kind's _fire().
func use(peer: int, origin: Vector3, dir: Vector3) -> void:
	var now := Time.get_ticks_msec()
	if now < _ready_at:
		return
	_ready_at = now + int(cooldown() * 1000.0)
	var p: Player = world.players.get(peer)
	if p == null:
		return
	var eye := p.global_position + world.plane.global_basis.y * 1.5
	if origin.distance_to(eye) > 1.5:
		origin = eye
	last_peer = peer
	_fire(peer, origin, dir)


func cooldown() -> float:
	return SPECS[kind].cooldown


## Host. The weapon's actual effect.
func _fire(peer: int, origin: Vector3, dir: Vector3) -> void:
	var id := World.net_id(self)
	match kind:
		"baguette":
			world.object_event(id, "swing", [0.9])
			if _melee(peer, origin, dir, 2.2, 0.55, 6.0, 3.0, 30.0) > 0 and randf() < 0.5:
				world.say(world.display_name(peer), BAGUETTE_LINES.pick_random(), 2.0)
			world.object_event(id, "fx", ["crumbs", _muzzle(), dir])
		"frying_pan":
			world.object_event(id, "swing", [1.3])
			var hits := _melee(peer, origin, dir, 2.0, 0.6, 11.0, 5.0, 70.0)
			world.object_event(id, "fx", ["bonk" if hits > 0 else "whiff", _muzzle(), dir])
			if hits > 0:
				world.say(world.display_name(peer), BONKS.pick_random(), 2.0)
		"dart_blaster":
			_shots += 1
			var muzzle := _muzzle()
			var dart := world.spawn_object("dart", Transform3D(Basis.looking_at(dir, _up_for(dir)), muzzle),
				{"foam": true, "color": _shots}) as FunToy
			if dart:
				dart.last_peer = peer
				dart.linear_velocity = dir * 22.0 + linear_velocity
			world.object_event(id, "fx", ["pew", muzzle, dir])
		"water_pistol":
			_blast(dir, 0.25)
			world.object_event(id, "fx", ["water", _muzzle(), dir])
		"confetti_cannon":
			world.object_event(id, "fx", ["confetti", _muzzle(), dir])
			_cone_push(peer, origin, dir, 4.0, 0.5, 9.0, 3.0)
			world.push_player(peer, -dir * 9.0 + Vector3(0, 2.0, 0))
			world.shake_all(0.15)
			world.say(world.display_name(peer), "SURPRISE!!!" if randf() < 0.5 else "*celebrates violently*", 2.0)
		"leaf_blower":
			_blast(dir, 0.35)
			world.object_event(id, "fx", ["leaves", _muzzle(), dir])
		"golf_club":
			world.object_event(id, "swing", [1.1])
			var hits := _melee(peer, origin, dir, 2.0, 0.6, 7.0, 4.0, 45.0, 45.0)
			world.object_event(id, "fx", ["fore" if hits > 0 else "whiff", _muzzle(), dir])
		"pillow_fight":
			world.object_event(id, "swing", [0.7])
			var hits := _melee(peer, origin, dir, 2.0, 0.5, 4.5, 3.5, 10.0)
			world.object_event(id, "fx", ["feathers" if hits > 0 else "whiff", _muzzle(), dir])


## Muzzle/business end in world space.
func _muzzle() -> Vector3:
	var z := {"baguette": -0.4, "frying_pan": -0.2, "dart_blaster": -0.36, "water_pistol": -0.32,
		"confetti_cannon": -0.25, "leaf_blower": -0.48, "golf_club": -0.48, "pillow_fight": 0.0}
	return global_transform * Vector3(0, 0, z[kind])


func _up_for(dir: Vector3) -> Vector3:
	return Vector3.UP if absf(dir.y) < 0.95 else Vector3.BACK


func _blast(dir: Vector3, duration: float) -> void:
	_blast_dir = dir
	_blast_t = maxf(_blast_t, duration)


func _physics_process(dt: float) -> void:
	if not world.is_server() or _blast_t <= 0.0:
		return
	_blast_t -= dt
	if holder == 0:
		_blast_t = 0.0
		return
	var p: Player = world.players.get(holder)
	if p == null:
		return
	var dir := -p.head.global_basis.z
	var origin := p.head.global_position
	var blower := kind == "leaf_blower"
	_push_t -= dt
	var tick := _push_t <= 0.0
	if tick:
		_push_t = 0.1
	# Continuous force on bodies; players get a nudge every 0.1 s (reliable RPC budget).
	var reach := 5.0 if blower else 6.0
	var cone := 0.75 if blower else 0.93
	var accel := 28.0 if blower else 14.0
	for o: Node3D in world.objects.values():
		var body := o as RigidBody3D
		if body == null or body == self or body.freeze:
			continue
		var to := body.global_position - origin
		if to.length() < reach and to.normalized().dot(dir) > cone:
			body.apply_central_force(dir * accel * minf(body.mass, 6.0) * (1.0 - to.length() / reach * 0.5))
	if tick:
		for peer: int in world.players:
			if peer == holder:
				continue
			var to: Vector3 = (world.players[peer] as Player).global_position + Vector3(0, 1.0, 0) - origin
			if to.length() < reach and to.normalized().dot(dir) > cone:
				world.push_player(peer, dir * (2.2 if blower else 1.3))
		if blower:
			# Newton says the blower pushes back. Aimed behind you, that's a jetpack.
			world.push_player(holder, -dir * 2.4 + Vector3(0, maxf(0.0, -dir.y) * 3.0, 0))


## Pushes everything in a cone once (confetti). Returns the number of things hit.
func _cone_push(peer: int, origin: Vector3, dir: Vector3, reach: float, cone: float, player_speed: float,
		body_impulse: float) -> int:
	var hits := 0
	for other: int in world.players:
		if other == peer:
			continue
		var to: Vector3 = (world.players[other] as Player).global_position + Vector3(0, 1.0, 0) - origin
		if to.length() < reach and to.normalized().dot(dir) > cone:
			world.push_player(other, dir * player_speed + Vector3(0, 2.5, 0))
			hits += 1
	for o: Node3D in world.objects.values():
		var body := o as RigidBody3D
		if body == null or body == self or body.freeze:
			continue
		var to := body.global_position - origin
		if to.length() < reach and to.normalized().dot(dir) > cone:
			body.apply_central_impulse((dir + Vector3(0, 0.3, 0)) * body_impulse * clampf(body.mass, 0.3, 8.0))
			hits += 1
	return hits


## Swing hit-test: everything within `reach` of the eye, inside the cone, gets knocked.
## Players get `player_speed` + `lift` velocity; NPCs on_punched; bodies an impulse
## (golf balls get `ball_speed` straight out). Returns the number of hits.
func _melee(peer: int, origin: Vector3, dir: Vector3, reach: float, cone: float, player_speed: float,
		lift: float, npc_force: float, ball_speed := 0.0) -> int:
	var hits := 0
	for other: int in world.players:
		if other == peer:
			continue
		var tp: Player = world.players[other]
		var to := tp.global_position + Vector3(0, 1.0, 0) - origin
		if to.length() < reach and to.normalized().dot(dir) > cone:
			world.push_player(other, (dir * Vector3(1, 0, 1)).normalized() * player_speed + Vector3(0, lift, 0))
			world.object_event(World.net_id(self), "hit", [tp.global_position + Vector3(0, 1.4, 0)])
			hits += 1
	for o: Node3D in world.objects.values():
		var body := o as RigidBody3D
		if body == null or body == self or body.freeze:
			continue
		var to := body.global_position - origin
		if to.length() > reach or to.normalized().dot(dir) < cone:
			continue
		hits += 1
		if body.is_in_group("npc"):
			body.apply_central_impulse((dir + Vector3(0, 0.4, 0)) * npc_force)
			if body.has_method("on_punched"):
				body.on_punched(peer, dir)
		else:
			var toy := body as FunToy
			if toy and toy.kind == "golf_ball" and ball_speed > 0.0:
				body.linear_velocity = (dir + Vector3(0, 0.25, 0)).normalized() * ball_speed
				toy.last_peer = peer
				world.say(world.display_name(peer), "FORE!!", 1.5)
			else:
				body.apply_central_impulse((dir + Vector3(0, 0.35, 0)) * clampf(body.mass * player_speed * 0.8, 1.0, 120.0))
				if body.has_method("on_punched"):
					body.on_punched(peer, dir)
				if kind == "frying_pan" and body.has_method("smash"):
					body.call("smash", peer)
		world.object_event(World.net_id(self), "hit", [body.global_position + Vector3(0, 0.2, 0)])
	return hits


# --- Cosmetics (every peer) --------------------------------------------------------------

func on_net_event(event: String, args: Array) -> void:
	match event:
		"swing":
			var amount: float = args[0]
			var tw := vis.create_tween()
			tw.tween_property(vis, "rotation", Vector3(-0.9 * amount, 0.6 * amount, 0), 0.06)
			tw.tween_property(vis, "rotation", Vector3(0.7 * amount, -0.5 * amount, 0), 0.1)
			tw.tween_property(vis, "rotation", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_BACK)
		"hit":
			var word: String = {"baguette": "THWAP!", "frying_pan": "BONK!!", "golf_club": "THOCK!",
				"pillow_fight": "FWUMP!"}.get(kind, "POW!")
			FunFx.popup(world, args[0], word, Color(1, 0.85, 0.2), 90 if kind == "frying_pan" else 70)
		"fx":
			_fx(args[0], args[1], args[2])


func _fx(what: String, at: Vector3, dir: Vector3) -> void:
	match what:
		"crumbs":
			FunFx.burst(world, at, [Color(0.85, 0.6, 0.25), Color(0.97, 0.86, 0.6)], 14, 2.0, 0.025, dir, 60.0)
		"bonk":
			FunFx.burst(world, at, [Color(1, 1, 0.5), Color(1, 1, 1)], 16, 5.0, 0.04, dir, 70.0, 0.4, Vector3.ZERO)
		"whiff":
			FunFx.popup(world, at, "whoosh", Color(0.85, 0.9, 1, 0.8), 40)
		"pew":
			FunFx.burst(world, at, [Color(1, 0.6, 0.1), Color(1, 1, 0.6)], 8, 2.0, 0.03, dir, 30.0, 0.3, Vector3.ZERO)
			FunFx.popup(world, at, "pew!", Color(1, 0.7, 0.3), 36)
		"water":
			FunFx.spray(world, at, dir, WATER, 0.25, 10.0, 0.035, 6.0)
		"leaves":
			FunFx.spray(world, at, dir, LEAVES, 0.35, 12.0, 0.05, 22.0, Vector3(0, -1.5, 0))
			FunFx.burst(world, at, [Color(0.9, 0.95, 1, 0.5)], 10, 8.0, 0.08, dir, 25.0, 0.4, Vector3.ZERO)
		"confetti":
			FunFx.burst(world, at, FunLooks.CONFETTI, 90, 11.0, 0.06, dir, 28.0, 2.5, Vector3(0, -2.5, 0), true)
			FunFx.burst(world, at, [Color(1, 1, 0.8)], 10, 3.0, 0.12, dir, 40.0, 0.25, Vector3.ZERO)
			FunFx.popup(world, at + dir * 0.6, "SURPRISE!!", FunLooks.CONFETTI.pick_random(), 90)
		"fore":
			FunFx.burst(world, at, [Color(0.4, 0.8, 0.3), Color(0.55, 0.4, 0.25)], 10, 3.0, 0.03, dir, 40.0)
		"feathers":
			FunFx.burst(world, at, FEATHERS, 30, 2.5, 0.05, Vector3.UP, 180.0, 2.5, Vector3(0, -0.6, 0), true)
