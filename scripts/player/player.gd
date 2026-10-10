class_name Player
extends CharacterBody3D
## First-person passenger. The local one reads input and moves itself; remote ones
## just follow streamed state. Origin is at the feet.
##
## Gravity is real: when the plane banks or pitches, the floor tilts and you slide
## (crouch/[Ctrl] to brace). Outside the hull the wind shoves you toward the tail.

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.5
const CROUCH_SPEED := 2.0
const JUMP_VELOCITY := 4.8
const ACCEL := 40.0
const AIR_ACCEL := 6.0
const MOUSE_SENS := 0.0025
const REACH := 3.0
const HOLD_DIST := 1.4
const SLIDE := 0.7            ## Share of downhill gravity that slides you on a tilted floor.
const FLOOR_FRICTION := 2.5
const BRACE_FRICTION := 7.0
const WIND_ACCEL := 9.0       ## Outside, at cruise speed.
const FELL_DISTANCE := 70.0
const RESPAWN_TIME := 3.0
const STATE_INTERVAL := 1.0 / 30.0
const PUNCH_COOLDOWN := 0.35
const EYE_HEIGHT := 1.6
const SEATED_EYE := 1.15
const HAND_REST := Vector3(0.2, -0.22, -0.42)   ## Right arm rest pose in camera space.
const PILOT_EYE := 1.5      ## High enough to see over the dashboard.

const COLORS := [Color(0.95, 0.35, 0.3), Color(0.3, 0.6, 0.95), Color(0.35, 0.85, 0.4),
	Color(0.95, 0.8, 0.25), Color(0.75, 0.4, 0.9), Color(0.95, 0.55, 0.2), Color(0.3, 0.85, 0.85),
	Color(0.9, 0.45, 0.7)]

var peer_id := 1
var display_name := "Passenger"
var world: World
var is_local := false
var look_pitch := 0.0
var held_id := 0
## Set by World on every peer. Entering faces the windshield; leaving drops you beside the seat.
var piloting := false:
	set(value):
		if value == piloting:
			return
		piloting = value
		if not is_local or not is_inside_tree():
			return
		seated = false
		if value:
			rotation.y = 0.0
			look_pitch = 0.0
			head.rotation.x = 0.0
		else:
			global_position = world.plane.to_global(Airliner.PILOT_SEAT + Vector3(0.6, -0.4, 0.4))
			_shape.set_deferred("disabled", false)

var seated := false
var seat_local := Vector3.ZERO
var crouching := false
var outside := false
var hold_point := Vector3.ZERO
var ext_vel := Vector3.ZERO   ## Non-input velocity: slides, wind, knockback, suction.
var aim_prompt := ""          ## What [E]/[LMB] would do right now (HUD reads it).
var respawning := false

var head: Node3D
var camera: Camera3D
var ray: RayCast3D
var _shape: CollisionShape3D
var _hands: Node3D
var _hand_l: MeshInstance3D
var _hand_r: MeshInstance3D
var _body_vis: Node3D
var _legs: Node3D
var _arms_vis: Node3D
var _label: Label3D
var _move_vel := Vector3.ZERO
var _state_t := 0.0
var _bob_t := 0.0
var _punch_t := 0.0
var _respawn_t := 0.0
var _trauma := 0.0
var _remote_pos := Vector3.ZERO
var _remote_yaw := 0.0
var _remote_pitch := 0.0
var _remote_flags := 0
var _has_remote := false
var _aim := {}               ## {type, ...} what the ray hits


func _ready() -> void:
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.PLAYER | Layers.PROP | Layers.NPC
	floor_max_angle = deg_to_rad(55)
	floor_snap_length = 0.3
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.7
	_shape.shape = cap
	_shape.position.y = 0.85
	add_child(_shape)
	head = Node3D.new()
	head.position.y = EYE_HEIGHT
	add_child(head)
	var color: Color = COLORS[peer_id % COLORS.size()]
	if is_local:
		camera = Camera3D.new()
		camera.fov = 80
		camera.far = 30000.0
		camera.near = 0.05
		head.add_child(camera)
		camera.current = true
		ray = RayCast3D.new()
		ray.target_position = Vector3(0, 0, -REACH)
		ray.collision_mask = Layers.WORLD | Layers.PLAYER | Layers.PROP | Layers.NPC | Layers.INTERACT
		ray.collide_with_areas = true
		ray.add_exception(self)
		camera.add_child(ray)
		_build_hands(color)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_build_body(color)


# --- Visuals ---------------------------------------------------------------------------

func _block(size: Vector3, pos: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_hands(color: Color) -> void:
	_hands = Node3D.new()
	camera.add_child(_hands)
	var skin := Color(0.96, 0.8, 0.65)
	_hand_l = _block(Vector3(0.07, 0.07, 0.3), Vector3(-HAND_REST.x, HAND_REST.y, HAND_REST.z), color, _hands)
	_hand_r = _block(Vector3(0.07, 0.07, 0.3), HAND_REST, color, _hands)
	for h in [_hand_l, _hand_r]:
		_block(Vector3(0.085, 0.085, 0.085), Vector3(0, 0, -0.18), skin, h)
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_body(color: Color) -> void:
	var skin := Color(0.96, 0.8, 0.65)
	_body_vis = Node3D.new()
	add_child(_body_vis)
	_block(Vector3(0.55, 0.65, 0.3), Vector3(0, 1.15, 0), color, _body_vis)
	_block(Vector3(0.38, 0.38, 0.38), Vector3(0, 1.68, 0), skin, _body_vis)
	_block(Vector3(0.3, 0.08, 0.05), Vector3(0, 1.72, -0.2), Color(0.1, 0.1, 0.1), _body_vis)
	_legs = Node3D.new()
	_legs.position.y = 0.82
	_body_vis.add_child(_legs)
	_block(Vector3(0.22, 0.8, 0.24), Vector3(-0.14, -0.4, 0), Color(0.2, 0.22, 0.3), _legs)
	_block(Vector3(0.22, 0.8, 0.24), Vector3(0.14, -0.4, 0), Color(0.2, 0.22, 0.3), _legs)
	_arms_vis = Node3D.new()
	_arms_vis.position.y = 1.4
	_body_vis.add_child(_arms_vis)
	_block(Vector3(0.16, 0.6, 0.16), Vector3(-0.37, -0.25, 0), color, _arms_vis)
	_block(Vector3(0.16, 0.6, 0.16), Vector3(0.37, -0.25, 0), color, _arms_vis)
	_label = Label3D.new()
	_label.text = display_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.15
	_label.font_size = 48
	_label.outline_size = 10
	_label.pixel_size = 0.004
	add_child(_label)


# --- Local control -----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_local or world.input_blocked() or respawning:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		look_pitch = clampf(look_pitch - event.relative.y * MOUSE_SENS, -1.5, 1.5)
		head.rotation.x = look_pitch
	elif event.is_action_pressed("interact"):
		_on_interact()
	elif event.is_action_pressed("throw"):
		_on_primary()
	elif event.is_action_pressed("use"):
		if held_id:
			world.request("use_item", [held_id, camera.global_position, -camera.global_basis.z])
	elif event.is_action_pressed("shout"):
		world.request("shout")
	elif event.is_action_pressed("gear") and piloting:
		world.request("gear")


func _physics_process(dt: float) -> void:
	if not is_local:
		_remote_update(dt)
		return
	_trauma = maxf(0.0, _trauma - dt * 1.5)
	if respawning:
		_respawn_t -= dt
		if _respawn_t <= 0.0:
			_finish_respawn()
		return
	if piloting or seated:
		_stick_to_seat(dt)
	else:
		_move(dt)
	hold_point = camera.global_position - camera.global_basis.z * HOLD_DIST
	_update_aim()
	_animate_hands(dt)
	_state_t += dt
	if _state_t >= STATE_INTERVAL:
		_state_t = 0.0
		world.send_player_state([global_position, rotation.y, look_pitch, hold_point, _flags()])
		if piloting:
			_send_pilot_input()
	# Airborne: drifting away means you fell out. On the ground you may walk off freely.
	if (world.plane.airborne and global_position.length() > FELL_DISTANCE) or global_position.y < -60.0:
		_start_respawn()


func _move(dt: float) -> void:
	var plane := world.plane
	var blocked := world.input_blocked()
	var input := Vector2.ZERO if blocked else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	crouching = not blocked and Input.is_action_pressed("crouch")
	var speed := CROUCH_SPEED if crouching else (SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED)
	var want := (global_basis * Vector3(input.x, 0, input.y)).normalized() * speed
	var on_floor := is_on_floor()
	_move_vel = _move_vel.move_toward(want, (ACCEL if on_floor else AIR_ACCEL) * dt)

	var g := get_gravity()
	outside = plane.is_outside(global_position + Vector3(0, 1.0, 0))
	var brace := 0.25 if crouching else 1.0
	ext_vel += plane.get_suction(global_position + Vector3(0, 1.0, 0)) * brace * dt
	if outside and plane.airborne:
		var wind_scale := clampf(world.flight.speed / 70.0, 0.0, 1.5)
		ext_vel += plane.global_basis.z * WIND_ACCEL * wind_scale * (0.1 if crouching else 1.0) * dt
	if on_floor:
		var n := get_floor_normal()
		ext_vel += (g - n * g.dot(n)) * SLIDE * brace * dt
		ext_vel = ext_vel.move_toward(Vector3.ZERO, (BRACE_FRICTION if crouching else FLOOR_FRICTION) * dt)
	else:
		ext_vel *= 1.0 - 0.3 * dt
	var vy := velocity.y + g.y * dt
	if on_floor and vy < 0.0:
		vy = maxf(vy, -1.0)
	if on_floor and not blocked and Input.is_action_just_pressed("jump"):
		vy = JUMP_VELOCITY * clampf(world.flight.felt_gravity(), 0.5, 1.5)
	velocity = Vector3(_move_vel.x + ext_vel.x, vy + ext_vel.y, _move_vel.z + ext_vel.z)
	move_and_slide()
	if is_on_wall():
		ext_vel = ext_vel.slide(get_wall_normal())
	if is_on_floor() and ext_vel.y < 0.0:
		ext_vel.y = 0.0
	velocity.y -= ext_vel.y
	head.position.y = move_toward(head.position.y, EYE_HEIGHT - (0.5 if crouching else 0.0), dt * 4.0)


## Sit in a passenger seat (plane-local point at cushion height).
func sit(seat: Vector3) -> void:
	seated = true
	seat_local = seat
	_shape.set_deferred("disabled", true)
	rotation.y = 0.0
	ext_vel = Vector3.ZERO
	_move_vel = Vector3.ZERO


func stand() -> void:
	if seated:
		global_position = world.plane.to_global(seat_local + Vector3(0, 0.05, 0))
	seated = false
	_shape.set_deferred("disabled", false)


func _stick_to_seat(dt: float) -> void:
	var local := Airliner.PILOT_SEAT if piloting else seat_local
	_shape.disabled = true
	global_position = world.plane.to_global(local - Vector3(0, 0.45, 0))
	velocity = Vector3.ZERO
	head.position.y = move_toward(head.position.y, PILOT_EYE if piloting else SEATED_EYE, dt * 4.0)
	if seated and not piloting and not world.input_blocked():
		if Input.is_action_just_pressed("jump") or Input.get_vector("move_left", "move_right", "move_forward", "move_back") != Vector2.ZERO:
			stand()


func _send_pilot_input() -> void:
	if world.input_blocked():
		world.send_pilot_input(0, 0, 0)
		return
	# Yoke style: W pushes the nose down, S pulls it up.
	world.send_pilot_input(Input.get_axis("move_forward", "move_back"),
		Input.get_axis("move_left", "move_right"), Input.get_axis("crouch", "sprint"))


## Velocity kick from the host (shoves, extinguisher thrust, turbulence).
func apply_push(vel: Vector3) -> void:
	if seated or piloting:
		shake(0.4)
		return
	ext_vel += Vector3(vel.x, 0, vel.z)
	velocity.y = maxf(velocity.y, vel.y)
	if vel.y > 0.0:
		ext_vel.y = 0.0
		global_position.y += 0.05
	shake(0.3)


func shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func _flags() -> int:
	return (1 if seated else 0) | (2 if piloting else 0) | (4 if crouching else 0) | (8 if held_id else 0)


func _start_respawn() -> void:
	respawning = true
	_respawn_t = RESPAWN_TIME
	_shape.disabled = true
	velocity = Vector3.ZERO
	ext_vel = Vector3.ZERO
	_move_vel = Vector3.ZERO
	world.request("fell_out")
	world.toast.emit("YOU FELL OUT OF THE PLANE")


func _finish_respawn() -> void:
	respawning = false
	var aisle: Array[Vector3] = world.plane.aisle_points
	global_position = world.plane.to_global(aisle[randi() % aisle.size()] + Vector3(0, 0.1, 0))
	_shape.disabled = false
	world.toast.emit("Somehow you climbed back in.")


# --- Aiming & actions -----------------------------------------------------------------

func _update_aim() -> void:
	_aim = {}
	aim_prompt = ""
	if piloting:
		aim_prompt = "Leave the seat [E]   Gear [G]"
		return
	ray.force_raycast_update()
	if not ray.is_colliding():
		aim_prompt = "Drop [E]  Throw [LMB]  Use [RMB]" if held_id else ""
		return
	var c := ray.get_collider()
	if c is Interactable:
		_aim = {"type": "area", "node": c}
		aim_prompt = (c as Interactable).get_prompt()
	elif c is Player:
		_aim = {"type": "player", "peer": (c as Player).peer_id}
		aim_prompt = "Shove %s [LMB]" % (c as Player).display_name
	elif c is Airliner:
		var w := (c as Airliner).window_for_shape(ray.get_collider_shape())
		if w >= 0:
			_aim = {"type": "window", "index": w}
			aim_prompt = "Punch the window [LMB]"
	elif World.net_id(c) != 0:
		_aim = {"type": "object", "id": World.net_id(c), "node": c}
		if c.has_method("get_prompt"):
			aim_prompt = c.get_prompt()
		elif c.is_in_group("grabbable"):
			aim_prompt = "Pick up [E]"
	if held_id:
		aim_prompt = "Drop [E]  Throw [LMB]  Use [RMB]"


func _on_interact() -> void:
	if piloting:
		world.request("pilot_exit")
		return
	if held_id:
		world.request("drop")
		return
	match _aim.get("type", ""):
		"area":
			var a: Interactable = _aim.node
			if not a.enabled:
				return
			if a.local_only:
				if a.action == "sit" and a.has_meta("seat"):
					sit(a.get_meta("seat"))
				a.used.emit(self)
			else:
				world.request(a.action, a.args)
		"object":
			var obj: Node = _aim.node
			if obj.has_meta("action"):
				world.request(obj.get_meta("action"), [_aim.id])
			elif obj.is_in_group("grabbable"):
				world.request("grab", [_aim.id])


func _on_primary() -> void:
	if piloting:
		return
	var dir := -camera.global_basis.z
	if held_id:
		world.request("throw", [held_id, dir])
		return
	if _punch_t > 0.0:
		return
	_punch_t = PUNCH_COOLDOWN
	match _aim.get("type", ""):
		"object":
			world.request("punch", [_aim.id, dir])
		"window":
			world.request("break_window", [_aim.index])
		"player":
			world.request("punch_player", [_aim.peer, dir])


func _animate_hands(dt: float) -> void:
	_punch_t = maxf(0.0, _punch_t - dt)
	var hv := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hv > 0.5 and not seated and not piloting:
		_bob_t += dt * hv * 2.2
	var bob := Vector3(cos(_bob_t * 0.5) * 0.025, -absf(sin(_bob_t * 0.5)) * 0.04, 0)
	var hold := held_id != 0
	var punch := sin(_punch_t / PUNCH_COOLDOWN * PI) * 0.25
	var reach := Vector3(-0.06, 0.08, -0.1) if hold else Vector3.ZERO
	_hand_l.position = _hand_l.position.lerp(Vector3(-HAND_REST.x - reach.x, HAND_REST.y + reach.y, HAND_REST.z + reach.z) + bob, dt * 14)
	_hand_r.position = _hand_r.position.lerp(HAND_REST + reach + Vector3(0, 0, -punch) - bob, dt * 14)
	if piloting:
		_hand_l.position = _hand_l.position.lerp(Vector3(-0.15, -0.26, -0.45), dt * 10)
		_hand_r.position = _hand_r.position.lerp(Vector3(0.15, -0.26, -0.45), dt * 10)
	var t := _trauma * _trauma
	camera.h_offset = randf_range(-1, 1) * 0.08 * t
	camera.v_offset = randf_range(-1, 1) * 0.08 * t
	camera.rotation.z = randf_range(-1, 1) * 0.05 * t


# --- Remote --------------------------------------------------------------------------

func apply_remote_state(st: Array) -> void:
	_remote_pos = st[0]
	_remote_yaw = st[1]
	_remote_pitch = st[2]
	hold_point = st[3]
	_remote_flags = st[4]
	seated = (_remote_flags & 1) != 0
	crouching = (_remote_flags & 4) != 0
	if not _has_remote:
		_has_remote = true
		global_position = _remote_pos


func _remote_update(dt: float) -> void:
	if not _has_remote:
		return
	var k := clampf(dt * 15.0, 0.0, 1.0)
	global_position = global_position.lerp(_remote_pos, k)
	rotation.y = lerp_angle(rotation.y, _remote_yaw, k)
	head.rotation.x = _remote_pitch
	if _body_vis:
		var sitting := (_remote_flags & 3) != 0
		_legs.rotation.x = lerpf(_legs.rotation.x, PI / 2 if sitting else 0.0, k)
		_body_vis.position.y = lerpf(_body_vis.position.y, -0.35 if sitting else (-0.3 if crouching else 0.0), k)
		_arms_vis.rotation.x = lerpf(_arms_vis.rotation.x, PI / 2 if (_remote_flags & 8) or piloting else 0.0, k)
