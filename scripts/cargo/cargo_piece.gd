extends RigidBody3D
## One networked piece of cargo (kinds in CargoLooks.SPECS) spawned for an accepted cargo
## contract. Meta `contract` = contract id; meta `action` = "strap" so [E] straps it down.
##
## Host only: impact damage (condition 1..0), strapping (frozen and carried along with the plane),
## and per kind trouble: fragile vases crack and shatter, the chicken coop door pops and hens
## escape, the crocodile crate breaks open, explosive barrels go off, the mystery crate does
## weird things. Every visible result is broadcast with world.object_event and drawn in
## on_net_event on all peers. `state` doubles as the late-join spawn extra.

const CargoLooks := preload("res://scripts/cargo/cargo_looks.gd")
const Sfx := preload("res://scripts/cargo/cargo_sfx.gd")
const Fx := preload("res://scripts/props/fx.gd")

const SPAWN_GRACE := 1.5        ## Seconds without impact damage while freshly spawned cargo settles.
const DAMAGE_SPEED := 3.5       ## Velocity change (m/s) in one contact that starts to hurt.
const IMPACT_SOUND := 1.6       ## Velocity change that makes an impact sound.
const IMPACT_GAP := 0.3
## Condition lost per m/s of velocity change above DAMAGE_SPEED.
const FRAGILITY := {"luggage": 0.015, "mail": 0.01, "fragile": 0.12, "chickens": 0.04, "crocodile": 0.02,
	"explosive": 0.03, "mystery": 0.03}
const CRACK_STEP := 0.05        ## Condition loss that shows a "CRACK!".
const BLAST_SPEED := 7.5        ## Velocity change that sets explosive barrels off at once.
const FUSE_TIME := 1.6          ## Barrels near fire hiss this long, then blow.
const FIRE_REACH := 2.0
const FIRE_CHECK := 0.25
const STRAP_REACH := 0.3        ## Bottom this close to the floor counts as "on the floor".
const STRAP_MAX_SPEED := 2.0
const ANGER_IMPACT := 0.12      ## Croc/coop anger per m/s of impact above 3 m/s.
const ANGER_THROWN := 0.35
const ANGER_PUNCHED := 0.15
const ANGER_TURBULENCE := 0.3   ## Per second per g of turbulence above TURBULENCE_FLOOR.
const TURBULENCE_FLOOR := 0.3
const MYSTERY_GAP := Vector2(14.0, 28.0)
const MYSTERY_TIME := 5.0
const MYSTERY_RADIUS := 3.0
const HELD_LINES := {
	"luggage": "Somebody's whole holiday. Heavy.", "mail": "Neither rain nor sleet nor YOU, apparently.",
	"fragile": "Antique vases. Carry it like it's worth more than you. It is.",
	"chickens": "The coop clucks disapprovingly.", "crocodile": "Something inside is breathing on your hands.",
	"explosive": "Gently. GENTLY.", "mystery": "It's warm. It's humming. You feel... observed.",
}

var module: Node                ## The Cargo module (host hooks).
var world: World
var kind := ""
var state := {}
var parts := {}
var destroyed := false          ## Host: shattered/exploded (despawn pending).

var _vis: Node3D
var _age := 0.0
var _prev_vel := Vector3.ZERO
var _pending: Array[Callable] = []
var _carried := false
var _strap_local := Transform3D.IDENTITY
var _last_impact := -10.0
var _crack_acc := 0.0
var _anger := 0.0
var _anger_warned := 0
var _fire_t := 0.0
var _fuse_t := 0.0
var _mystery_t := 0.0
var _effect := ""
var _effect_t := 0.0
var _effect_tick := 0.0


func setup(m: Node, w: World, p_kind: String, extra: Dictionary) -> void:
	module = m
	world = w
	kind = p_kind
	state = extra.duplicate()
	state.get_or_add("condition", 1.0)
	state.get_or_add("strapped", false)
	var spec: Dictionary = CargoLooks.SPECS[kind]
	mass = spec.mass
	physics_material_override = FunLooks.phys(spec.friction, 0.05)
	linear_damp = 0.1
	angular_damp = 0.8
	can_sleep = true
	collision_layer = Layers.PROP
	collision_mask = Layers.WORLD | Layers.PLAYER | Layers.PROP | Layers.NPC
	add_to_group("grabbable")
	add_to_group("cargo")
	set_meta("action", "strap")
	set_meta("contract", int(state.get("contract", -1)))
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = spec.size
	cs.shape = bs
	add_child(cs)
	match kind:
		"chickens":
			state.get_or_add("hens", 4)
			state.get_or_add("inside", int(state.hens))
			state.get_or_add("door", false)
			state.get_or_add("loose", [])
		"crocodile":
			state.get_or_add("open", false)
			state.get_or_add("croc", 0)
			state.get_or_add("croc_lost", false)
	_mystery_t = randf_range(MYSTERY_GAP.x, MYSTERY_GAP.y)


func _ready() -> void:
	_vis = Node3D.new()
	_vis.name = "Vis"
	add_child(_vis)
	CargoLooks.build(_vis, kind, state, parts)
	match kind:
		"chickens":
			CargoLooks.set_hens(parts.hens, int(state.inside))
			_show_door(bool(state.door), false)
		"crocodile":
			_show_open(bool(state.open), false)
	var host := world.is_server()
	set_physics_process(host)
	if host:
		contact_monitor = true
		max_contacts_reported = 4
		body_shape_entered.connect(_on_body_shape_entered)
		if bool(state.strapped):
			_apply_strap(true)


func display_name() -> String:
	return CargoLooks.SPECS[kind].name


func get_prompt() -> String:
	var n := display_name()
	if bool(state.get("strapped", false)):
		return "%s (strapped down)   Unstrap [E]" % n.capitalize()
	if in_hold():
		return "%s   Strap down [E]   Crouch + [E] to lift" % n.capitalize()
	return "%s   Pick up [E]" % n.capitalize()


func get_spawn_extra() -> Dictionary:
	return state


func can_grab(_peer: int) -> bool:
	return not bool(state.strapped) and not destroyed


func on_grabbed(peer: int) -> void:
	_carried = true
	world.notify(peer, HELD_LINES.get(kind, ""))


func on_released() -> void:
	_carried = false


func on_thrown(_peer: int) -> void:
	_add_anger(ANGER_THROWN)


func on_punched(_peer: int, _dir: Vector3) -> void:
	_add_anger(ANGER_PUNCHED)


## True (any peer) when the piece is inside the cargo hold with its bottom near the floor.
func in_hold() -> bool:
	var plane := world.plane
	var p := plane.to_local(global_position)
	var half: float = (CargoLooks.SPECS[kind].size as Vector3).y * 0.5
	return p.z > Airliner.CARGO_MIN.z - 1.0 and p.z < Airliner.TAIL_Z - 0.2 and absf(p.x) < Airliner.HALF_W \
		and p.y > -0.2 and p.y < half + STRAP_REACH + 0.2


## Host: can it be strapped right now (resting in the hold, not carried)?
func can_strap() -> bool:
	return not destroyed and not _carried and not freeze and in_hold() and linear_velocity.length() < STRAP_MAX_SPEED


## Host: straps the piece down (upright, on the floor, frozen to the plane) or releases it.
func set_strapped(on: bool) -> void:
	if on == bool(state.strapped) or destroyed:
		return
	state.strapped = on
	_apply_strap(on)
	world.object_event(World.net_id(self), "strap", [on])


func _apply_strap(on: bool) -> void:
	if on:
		var plane := world.plane
		var local := plane.global_transform.affine_inverse() * global_transform
		var fwd := local.basis.z
		fwd.y = 0.0
		if fwd.length() < 0.1:
			fwd = Vector3.BACK
		var yaw := atan2(fwd.x, fwd.z)
		var half: float = (CargoLooks.SPECS[kind].size as Vector3).y * 0.5
		_strap_local = Transform3D(Basis(Vector3.UP, yaw), Vector3(local.origin.x, half + 0.005, local.origin.z))
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		global_transform = plane.global_transform * _strap_local
	else:
		freeze = false
		sleeping = false


## Host: an explosion went off `dist` metres away (strength 0..1 at this distance).
func on_blast(strength: float, from: Vector3) -> void:
	if destroyed:
		return
	if bool(state.strapped) and strength > 0.45:
		set_strapped(false)
	if not freeze:
		var dir := (global_position - from).normalized()
		apply_central_impulse((dir + world.plane.global_basis.y * 0.6) * mass * clampf(14.0 * strength / sqrt(mass / 10.0), 0.0, 10.0))
	_damage(strength * 0.8)
	match kind:
		"explosive":
			if strength > 0.25:
				module.explode_later(self, randf_range(0.12, 0.3))
		"crocodile", "chickens":
			if strength > 0.2:
				_add_anger(1.0)


## Host: condition this piece counts as delivered with, or -1 if it isn't delivered (gone,
## outside the plane, its crocodile lost, every hen gone).
func delivered_condition() -> float:
	if destroyed or world.plane.is_outside(global_position):
		return -1.0
	var c := clampf(float(state.condition), 0.0, 1.0)
	match kind:
		"crocodile":
			if bool(state.open):
				var croc: Node3D = world.get_object(int(state.croc))
				if croc == null or world.plane.is_outside(croc.global_position):
					return -1.0
				return c * 0.5
		"chickens":
			var loose := 0
			for id: int in state.loose:
				var hen: Node3D = world.get_object(id)
				if hen and not world.plane.is_outside(hen.global_position):
					loose += 1
			var inside := int(state.inside)
			if inside + loose == 0:
				return -1.0
			return c * (inside + 0.5 * loose) / maxf(float(state.hens), 1.0)
	return c


# --- Host simulation ------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	_age += dt
	if not _pending.is_empty():
		var queued := _pending
		_pending = []
		for c in queued:
			c.call()
	if destroyed:
		return
	if bool(state.strapped):
		global_transform = world.plane.global_transform * _strap_local
	_fire_t -= dt
	if _fire_t <= 0.0:
		_fire_t = FIRE_CHECK
		if module.near_fire(global_position, FIRE_REACH):
			_on_fire()
	var turb: float = module.turbulence()
	if turb > TURBULENCE_FLOOR and not bool(state.strapped):
		_add_anger((turb - TURBULENCE_FLOOR) * ANGER_TURBULENCE * dt)
	match kind:
		"explosive":
			if _fuse_t > 0.0:
				_fuse_t -= dt
				if _fuse_t <= 0.0:
					module.explode(self)
					return
		"mystery":
			_mystery_step(dt)
	_prev_vel = Vector3.ZERO if sleeping or freeze else linear_velocity


func _on_body_shape_entered(_rid: RID, body: Node, _body_shape_index: int, _local_shape: int) -> void:
	if destroyed or _age < SPAWN_GRACE or _carried or freeze or body == null or body is Player:
		return
	var jolt := (_prev_vel - linear_velocity).length()
	if jolt < IMPACT_SOUND:
		return
	_pending.append(_impact.bind(jolt))


func _impact(jolt: float) -> void:
	if destroyed:
		return
	var now := _age
	if now - _last_impact > IMPACT_GAP:
		_last_impact = now
		world.object_event(World.net_id(self), "impact", [snappedf(jolt, 0.1)])
	if kind == "explosive" and jolt > BLAST_SPEED:
		module.explode(self)
		return
	if jolt > 3.0:
		_add_anger((jolt - 3.0) * ANGER_IMPACT)
	if jolt > DAMAGE_SPEED:
		_damage((jolt - DAMAGE_SPEED) * float(FRAGILITY[kind]))


## Host: lowers the condition; fragile cargo cracks audibly and shatters below zero.
func _damage(amount: float) -> void:
	if amount <= 0.0 or destroyed:
		return
	state.condition = float(state.condition) - amount
	_crack_acc += amount
	if kind == "fragile":
		if float(state.condition) < 0.0:
			_shatter()
			return
		if _crack_acc >= CRACK_STEP:
			_crack_acc = 0.0
			world.object_event(World.net_id(self), "crack", [snappedf(maxf(float(state.condition), 0.0), 0.01)])
	elif kind == "explosive" and float(state.condition) <= 0.0:
		module.explode(self)
	state.condition = maxf(float(state.condition), 0.0)


func _shatter() -> void:
	destroyed = true
	state.condition = 0.0
	var id := World.net_id(self)
	world.add_stat("things_broken")
	world.object_event(id, "shatter")
	module.spawn_shards(global_position, linear_velocity, [CargoLooks.VASE_BLUE, CargoLooks.PORCELAIN,
		CargoLooks.GOLD, CargoLooks.WOOD, CargoLooks.PORCELAIN, CargoLooks.VASE_BLUE])
	world.despawn_object(id)


func _on_fire() -> void:
	match kind:
		"explosive":
			if _fuse_t <= 0.0:
				_fuse_t = FUSE_TIME
				world.object_event(World.net_id(self), "fuse")
		"crocodile", "chickens":
			_add_anger(1.0)
		"fragile", "mail", "luggage", "mystery":
			_damage(0.15)


## Host: rough handling builds up until the croc crate bursts or the coop door pops.
## Strapped crates ignore turbulence (the caller skips it) but not fire, blasts or hits.
func _add_anger(amount: float) -> void:
	if destroyed or (kind != "crocodile" and kind != "chickens"):
		return
	if kind == "crocodile" and bool(state.open):
		return
	if kind == "chickens" and (bool(state.door) or int(state.inside) == 0):
		return
	_anger += amount
	var level := 2 if _anger >= 0.7 else (1 if _anger >= 0.4 else 0)
	if level > _anger_warned:
		_anger_warned = level
		world.object_event(World.net_id(self), "rattle", [level])
	if _anger >= 1.0:
		_anger = 0.0
		_anger_warned = 0
		if kind == "crocodile":
			_burst_open()
		else:
			_pop_door()


func _burst_open() -> void:
	state.open = true
	world.object_event(World.net_id(self), "open")
	module.release_croc(self)


## Host: the crocodile went back into its crate.
func croc_returned() -> void:
	state.open = false
	state.croc = 0
	_anger = 0.0
	world.object_event(World.net_id(self), "close")


func _pop_door() -> void:
	state.door = true
	world.object_event(World.net_id(self), "door", [true])
	module.release_hens(self, int(state.inside))
	state.inside = 0
	world.object_event(World.net_id(self), "hens", [0])


## Host: a hen was popped back into the coop. The door latches once they're all home.
func hen_returned(hen_id: int) -> void:
	(state.loose as Array).erase(hen_id)
	state.inside = int(state.inside) + 1
	world.object_event(World.net_id(self), "hens", [int(state.inside)])
	if (state.loose as Array).is_empty() and bool(state.door):
		state.door = false
		_anger = 0.0
		world.object_event(World.net_id(self), "door", [false])


## Host: a loose hen left the plane for good (it still counts against the coop's condition).
func hen_lost(hen_id: int) -> void:
	(state.loose as Array).erase(hen_id)
	if (state.loose as Array).is_empty() and bool(state.door):
		state.door = false
		world.object_event(World.net_id(self), "door", [false])


# --- Mystery crate --------------------------------------------------------------------------

func _mystery_step(dt: float) -> void:
	if _effect != "":
		_effect_t -= dt
		_effect_tick -= dt
		match _effect:
			"float":
				if not freeze:
					apply_central_force(-world.flight.felt_accel * mass * 1.25)
			"gravity":
				module.invert_gravity_around(self, MYSTERY_RADIUS, _effect_tick <= 0.0)
		if _effect_tick <= 0.0:
			_effect_tick = 0.6
		if _effect_t <= 0.0:
			_effect = ""
			world.object_event(World.net_id(self), "calm")
		return
	if world.flight.phase != FlightModel.Phase.FLYING:
		return
	_mystery_t -= dt
	if _mystery_t > 0.0:
		return
	_mystery_t = randf_range(MYSTERY_GAP.x, MYSTERY_GAP.y)
	var options := ["hum", "gravity"]
	if not bool(state.strapped) and not _carried:
		options.append_array(["float", "teleport"])
	var pick: String = options.pick_random()
	var id := World.net_id(self)
	match pick:
		"hum":
			world.object_event(id, "hum")
			module.jiggle_around(global_position, MYSTERY_RADIUS)
		"teleport":
			var old := global_position
			var spot := Vector3(randf_range(-0.7, 0.7), 0.6, randf_range(-8.0, Airliner.CARGO_MAX.z - 1.0))
			global_position = world.plane.to_global(spot)
			linear_velocity = Vector3.ZERO
			world.object_event(id, "poof", [old])
		_:
			_effect = pick
			_effect_t = MYSTERY_TIME
			_effect_tick = 0.0
			sleeping = false
			world.object_event(id, pick)


# --- Cosmetics (all peers) ------------------------------------------------------------------

func on_net_event(event: String, args: Array) -> void:
	var fxroot := get_parent()
	var at := global_position
	var up := global_basis.y
	match event:
		"strap":
			var on: bool = args[0]
			state.strapped = on
			(parts.strap as Node3D).visible = on
			Sfx.play(fxroot, at, "ratchet" if on else "unstrap")
			Fx.popup(fxroot, at + up * 0.7, "STRAPPED!" if on else "UNSTRAPPED", Color(1, 0.8, 0.2) if on else Color(0.8, 0.85, 1), 48)
		"impact":
			var loud := clampf(float(args[0]) / 8.0, 0.1, 1.0)
			Fx.sound(fxroot, at, CargoLooks.SPECS[kind].sound, linear_to_db(loud) - 2.0, 0.7)
		"crack":
			Fx.popup(fxroot, at + up * 0.6, "CRACK! (%d%%)" % roundi(float(args[0]) * 100.0), Color(1, 0.4, 0.3), 56)
			Sfx.play(fxroot, at, "shatter", -10.0, 1.4)
			Fx.burst(fxroot, at + up * 0.4, CargoLooks.PORCELAIN, 8, 2.5, 0.04, Vector3(0, -9.8, 0), 0.7)
		"shatter":
			Fx.burst(fxroot, at, CargoLooks.VASE_BLUE, 24, 5.0, 0.06, Vector3(0, -9.8, 0), 1.2)
			Fx.burst(fxroot, at, CargoLooks.PORCELAIN, 24, 5.0, 0.05, Vector3(0, -9.8, 0), 1.2)
			Fx.burst(fxroot, at, Color(1, 0.88, 0.45), 20, 3.0, 0.05, Vector3(0, -3, 0), 1.8)
			Fx.popup(fxroot, at + up * 0.6, "SMASH!!", Color(1, 0.35, 0.3), 90)
			Sfx.play(fxroot, at, "shatter", 2.0)
		"rattle":
			_shake_vis(0.06 if int(args[0]) == 1 else 0.12)
			if kind == "crocodile":
				Sfx.play(fxroot, at, "hiss", -2.0 if int(args[0]) == 2 else -6.0)
				Fx.popup(fxroot, at + up * 0.7, "*THUMP*" if int(args[0]) == 1 else "*GRRRRR*", Color(0.6, 1, 0.4), 52)
			else:
				Sfx.play(fxroot, at, "bawk", -3.0)
				Fx.popup(fxroot, at + up * 0.6, "BAWK?!", Color(1, 0.95, 0.5), 52)
		"open":
			_show_open(true, true)
			Fx.burst(fxroot, at + up * 0.45, CargoLooks.WOOD, 30, 6.0, 0.07, Vector3(0, -9.8, 0), 1.3)
			Fx.popup(fxroot, at + up * 0.8, "IT'S OUT!!", Color(0.5, 1, 0.3), 96)
			Fx.sound(fxroot, at, "crash")
			Sfx.play(fxroot, at, "hiss", 2.0, 0.8)
		"close":
			_show_open(false, true)
			Fx.popup(fxroot, at + up * 0.8, "BACK IN THE BOX!", Color(0.5, 1, 0.3), 64)
			Fx.sound(fxroot, at, "knock")
		"door":
			_show_door(bool(args[0]), true)
			if bool(args[0]):
				Fx.burst(fxroot, at + up * 0.2, CargoLooks.HEN, 30, 3.5, 0.05, Vector3(0, -2, 0), 2.0)
				Fx.popup(fxroot, at + up * 0.7, "THE CHICKENS ARE OUT!", Color(1, 0.95, 0.5), 64)
				Sfx.play(fxroot, at, "bawk", 2.0)
		"hens":
			state.inside = int(args[0])
			CargoLooks.set_hens(parts.hens, int(args[0]))
		"fuse":
			var s := Fx.stream(Color(1, 0.75, 0.2), 0.03, 2.5, Vector3.UP, 40.0)
			s.position = Vector3(0, 0.55, 0)
			add_child(s)
			s.emitting = true
			Fx.popup(fxroot, at + up * 0.8, "*HISSSSS*", Color(1, 0.6, 0.2), 64)
			Fx.sound(fxroot, at, "fizz", 2.0)
		"boom":
			_boom_fx(fxroot, at)
		"hum":
			Sfx.play(fxroot, at, "hum", 0.0)
			_shake_vis(0.05)
			_pulse_glow(2.0)
			Fx.popup(fxroot, at + up * 0.7, "hmmmmmmm", Color(0.85, 0.6, 1), 48)
		"float":
			Sfx.play(fxroot, at, "warble")
			_pulse_glow(MYSTERY_TIME)
			Fx.popup(fxroot, at + up * 0.7, "~ floating ~", Color(0.85, 0.6, 1), 56)
		"gravity":
			Sfx.play(fxroot, at, "warble", 2.0, 0.6)
			_pulse_glow(MYSTERY_TIME)
			Fx.burst(fxroot, at, CargoLooks.MYSTERY_GLOW, 40, 3.0, 0.06, Vector3(0, 3, 0), 2.0, Vector3.UP, 180.0, 3.0)
			Fx.popup(fxroot, at + up * 0.7, "GRAVITY? NEVER HEARD OF IT", Color(0.85, 0.6, 1), 52)
		"poof":
			var old: Vector3 = args[0]
			for p: Vector3 in [old, at]:
				Fx.burst(fxroot, p, CargoLooks.MYSTERY_GLOW, 30, 4.0, 0.06, Vector3.ZERO, 0.8, Vector3.UP, 180.0, 3.0)
			Fx.popup(fxroot, at + up * 0.7, "*POOF*", Color(0.85, 0.6, 1), 64)
			Sfx.play(fxroot, at, "warble", 0.0, 1.6)
		"calm":
			_pulse_glow(0.0)


func _show_open(open: bool, animate: bool) -> void:
	var lid: Node3D = parts.lid
	(parts.hole as Node3D).visible = open
	(parts.eyes as Node3D).visible = not open
	if not open:
		lid.visible = true
		lid.position = Vector3(0, (CargoLooks.SPECS.crocodile.size as Vector3).y * 0.5, 0)
		lid.rotation = Vector3.ZERO
	elif animate:
		var tw := lid.create_tween()
		tw.set_parallel(true)
		tw.tween_property(lid, "position", lid.position + Vector3(randf_range(-0.6, 0.6), 1.6, randf_range(-0.6, 0.6)), 0.5)
		tw.tween_property(lid, "rotation", Vector3(randf_range(2, 5), randf_range(-3, 3), randf_range(-3, 3)), 0.5)
		tw.chain().tween_callback(lid.hide)
	else:
		lid.visible = false


func _show_door(open: bool, animate: bool) -> void:
	var door: Node3D = parts.door
	var target := 1.45 if open else 0.0
	if animate:
		door.create_tween().tween_property(door, "rotation:x", target, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	else:
		door.rotation.x = target


func _shake_vis(amount: float) -> void:
	var tw := _vis.create_tween()
	for i in 6:
		tw.tween_property(_vis, "position", Vector3(randf_range(-1, 1), randf_range(0, 0.5), randf_range(-1, 1)) * amount, 0.04)
	tw.tween_property(_vis, "position", Vector3.ZERO, 0.05)


## Mystery crate: glow and light pulse for `seconds` (0 = back to normal).
func _pulse_glow(seconds: float) -> void:
	var light := parts.get("light") as OmniLight3D
	var glow := parts.get("glow") as Node3D
	if light == null or glow == null:
		return
	var tw := light.create_tween()
	if seconds <= 0.0:
		tw.tween_property(light, "light_energy", 0.8, 0.4)
		glow.create_tween().tween_property(glow, "scale", Vector3.ONE, 0.4)
		return
	var beats := maxi(1, int(seconds / 0.5))
	for i in beats:
		tw.tween_property(light, "light_energy", 3.0, 0.25)
		tw.tween_property(light, "light_energy", 1.2, 0.25)
	tw.tween_property(light, "light_energy", 0.8, 0.3)
	var gt := glow.create_tween()
	for i in beats:
		gt.tween_property(glow, "scale", Vector3.ONE * 1.04, 0.25)
		gt.tween_property(glow, "scale", Vector3.ONE, 0.25)


func _boom_fx(fxroot: Node, at: Vector3) -> void:
	Fx.burst(fxroot, at, Color(1, 0.85, 0.3), 50, 9.0, 0.22, Vector3(0, 2, 0), 0.6, Vector3.UP, 180.0, 4.0)
	Fx.burst(fxroot, at, Color(1, 0.4, 0.1), 40, 7.0, 0.28, Vector3(0, 1, 0), 0.9, Vector3.UP, 180.0, 3.0)
	Fx.burst(fxroot, at, Color(0.25, 0.22, 0.22), 30, 3.0, 0.4, Vector3(0, 1.5, 0), 2.2)
	Fx.burst(fxroot, at, CargoLooks.BARREL, 16, 8.0, 0.1, Vector3(0, -9.8, 0), 1.5)
	Fx.popup(fxroot, at + Vector3(0, 1.0, 0), "KA-BOOM!!", Color(1, 0.6, 0.15), 140)
	Sfx.play(fxroot, at, "boom", 6.0)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1, 0.7, 0.3)
	flash.light_energy = 8.0
	flash.omni_range = 9.0
	fxroot.add_child(flash)
	flash.global_position = at
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.5)
	tw.tween_callback(flash.queue_free)
