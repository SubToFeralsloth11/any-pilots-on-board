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
const AIR_ACCEL := 12.0      ## Slightly floatier air control
const MOUSE_SENS := 0.0025
const REACH := 3.0
const HOLD_DIST := 1.4
const SLIDE := 0.7            ## Share of downhill gravity that slides you on a tilted floor.
const FLOOR_FRICTION := 3.5   ## Crisper decel
const BRACE_FRICTION := 9.0
const WIND_ACCEL := 9.0       ## Outside, at cruise speed.
const FELL_DISTANCE := 70.0
const RESPAWN_TIME := 3.0
const STATE_INTERVAL := 1.0 / 30.0
const PUNCH_COOLDOWN := 0.35
const EYE_HEIGHT := 1.6
const CROUCH_EYE := 1.1       ## Crouch eye height (smoothly lerped)
const SEATED_EYE := 1.15
const PILOT_EYE := 1.5        ## High enough to see over the dashboard.
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12
const STEP_HEIGHT := 0.3      ## Step up small ledges
const LAND_DIP_SPEED := 8.0   ## Camera dip speed on landing
const MAX_DIP := 0.15         ## Max camera dip (meters)

const PlayerLook := preload("res://scripts/player/player_look.gd")

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
			_set_camera_mode(true)
		else:
			global_position = world.plane.to_global(Airliner.PILOT_SEAT + Vector3(0.6, -0.4, 0.4))
			_shape.set_deferred("disabled", false)
			_set_camera_mode(false)

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
var _capsule: CapsuleShape3D

# First-person arms
var _fp_parts: Dictionary
var _hands_parent: Node3D

# Third-person body (for local player in 3rd person, and all remote players)
var _tp_parts: Dictionary
var _third_person := false
var _cam_boom: Node3D
var _cam_target: Node3D
var _tp_camera: Camera3D

# Movement state
var _move_vel := Vector3.ZERO
var _state_t := 0.0
var _punch_t := 0.0
var _respawn_t := 0.0
var _trauma := 0.0
var _coyote_t := 0.0
var _jump_buffer_t := 0.0
var _was_on_floor := false
var _land_dip := 0.0
var _prev_vy := 0.0

# Remote
var _remote_pos := Vector3.ZERO
var _remote_yaw := 0.0
var _remote_pitch := 0.0
var _remote_flags := 0
var _has_remote := false
var _aim := {}               ## {type, ...} what the ray hits

# Settings
var _mouse_sens_mult := 1.0
var _invert_y := false
var _fov := 80.0

# Ping
var _ping_cooldown := 0.0


func _ready() -> void:
	collision_layer = Layers.PLAYER
	# Loose props are not in the mask: walking never snags on luggage or clutter. Props still
	# collide with the player's layer, so the moving capsule shoves them out of the way.
	collision_mask = Layers.WORLD | Layers.PLAYER | Layers.NPC
	floor_max_angle = deg_to_rad(55)
	floor_snap_length = STEP_HEIGHT  # Step up small ledges
	_shape = CollisionShape3D.new()
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.32
	_capsule.height = 1.7
	_shape.shape = _capsule
	_shape.position.y = 0.85
	add_child(_shape)
	
	head = Node3D.new()
	head.position.y = EYE_HEIGHT
	add_child(head)
	
	var color: Color = COLORS[peer_id % COLORS.size()]
	
	if is_local:
		# First-person camera
		camera = Camera3D.new()
		camera.fov = _fov
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
		
		# First-person crew arms (sleeves + mitten hands) in camera space
		_fp_parts = PlayerLook.build_fp_arms(color, camera)
		_hands_parent = _fp_parts.root
		
		# Third-person camera boom (initially disabled)
		_cam_boom = Node3D.new()
		_cam_boom.position = Vector3(0, 1.5, 0)  # Above head
		head.add_child(_cam_boom)
		
		_cam_target = Node3D.new()
		_cam_target.position = Vector3(0, 0, 2.5)  # Behind
		_cam_boom.add_child(_cam_target)
		
		_tp_camera = Camera3D.new()
		_tp_camera.fov = _fov
		_tp_camera.far = 30000.0
		_tp_camera.near = 0.05
		_tp_camera.current = false
		_cam_target.add_child(_tp_camera)
		
		# Crew body for the local player (only shown in 3rd person)
		_tp_parts = PlayerLook.build_tp_body(color, display_name, self)
		_tp_parts.body_vis.visible = false
		_tp_parts.label.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
		# Settings
		_mouse_sens_mult = Settings.mouse_sensitivity
		_invert_y = Settings.invert_y
		_fov = Settings.fov
		Settings.changed.connect(_on_settings_changed)
	else:
		_tp_parts = PlayerLook.build_tp_body(color, display_name, self)


func _on_settings_changed() -> void:
	if not is_local:
		return
	_mouse_sens_mult = Settings.mouse_sensitivity
	_invert_y = Settings.invert_y
	_fov = Settings.fov
	if camera:
		camera.fov = _fov
	if _tp_camera:
		_tp_camera.fov = _fov


func _set_camera_mode(first_person: bool) -> void:
	if not is_local:
		return
	_third_person = not first_person
	camera.current = first_person
	if _tp_camera:
		_tp_camera.current = not first_person
	# Show/hide FP hands and TP body
	if _hands_parent:
		_hands_parent.visible = first_person
	if _tp_parts and _tp_parts.body_vis:
		_tp_parts.body_vis.visible = not first_person
	if _tp_parts and _tp_parts.label:
		_tp_parts.label.visible = not first_person
	# Ray always from active camera
	if ray:
		ray.set_parent(camera if first_person else _tp_camera)
	ray.add_exception(self)


# --- Input -------------------------------------------------------------------------------
	var target_eye = EYE_HEIGHT - (0.5 if crouching else 0.0)
func _unhandled_input(event: InputEvent) -> void:
	if not is_local or world.input_blocked() or respawning:
		return
	
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens = MOUSE_SENS * _mouse_sens_mult
		rotate_y(-event.relative.x * sens)
		var pitch_delta = event.relative.y * sens * (1.0 if _invert_y else -1.0)
		look_pitch = clampf(look_pitch + pitch_delta, -1.5, 1.5)
		head.rotation.x = look_pitch
		# In third person, rotate the boom yaw with the player, pitch with look
		if _third_person and _cam_boom:
			_cam_boom.rotation.y = rotation.y
			_cam_boom.rotation.x = look_pitch
	
	elif event.is_action_pressed("interact"):
		_on_interact()
	elif event.is_action_pressed("throw"):
		_on_primary()
	elif event.is_action_pressed("use"):
		if held_id:
			var cam = _tp_camera if _third_person else camera
			world.request("use_item", [held_id, cam.global_position, -cam.global_basis.z])
	elif event.is_action_pressed("shout"):
		world.request("shout")
	elif event.is_action_pressed("gear") and piloting:
		world.request("gear")
	elif event.is_action_pressed("flaps") and piloting:
		world.request("flaps")
	elif event.is_action_pressed("camera"):
		_set_camera_mode(!_third_person)
	elif event.is_action_pressed("ping"):
		_try_ping()
	elif event.is_action_just_pressed("jump"):
		_jump_buffer_t = JUMP_BUFFER


func _try_ping() -> void:
	if _ping_cooldown > 0.0:
		return
	var cam = _tp_camera if _third_person else camera
	if not cam:
		return
	var origin = cam.global_position
	var dir = -cam.global_basis.z
	world.request("ping", [origin, dir])
	_ping_cooldown = 0.5


# --- Physics -----------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if not is_local:
		_remote_update(dt)
		return
	
	_trauma = maxf(0.0, _trauma - dt * 1.5)
	_ping_cooldown = maxf(0.0, _ping_cooldown - dt)
	
	if respawning:
		_respawn_t -= dt
		if _respawn_t <= 0.0:
			_finish_respawn()
		return
	
	if piloting or seated:
		_stick_to_seat(dt)
	else:
		_move(dt)
	
	# Update hold point from active camera
	var cam = _tp_camera if _third_person else camera
	hold_point = cam.global_position - cam.global_basis.z * HOLD_DIST
	
	_update_aim()
	_animate_local(dt)
	_update_camera_boom(dt)
	
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
	
	# Crouch input
	var crouch_pressed := not blocked and Input.is_action_pressed("crouch")
	
	# Coyote time and jump buffer
	var on_floor := is_on_floor()
	if on_floor:
		_coyote_t = COYOTE_TIME
	else:
		_coyote_t = maxf(0.0, _coyote_t - dt)
	
	_jump_buffer_t = maxf(0.0, _jump_buffer_t - dt)
	
	# Detect landing for camera dip
	if on_floor and not _was_on_floor:
		var fall_speed = -_prev_vy
		if fall_speed > 5.0:
			_land_dip = minf(fall_speed * 0.02, MAX_DIP)
	
	# Smooth camera dip
	if _land_dip > 0.0:
		_land_dip = maxf(0.0, _land_dip - dt * LAND_DIP_SPEED)
		head.position.y -= _land_dip
	
	crouching = crouch_pressed
	var speed := CROUCH_SPEED if crouching else (SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED)
	var want := (global_basis * Vector3(input.x, 0, input.y)).normalized() * speed
	
	# Ground accel/decel
	var accel = ACCEL if on_floor else AIR_ACCEL
	_move_vel = _move_vel.move_toward(want, accel * dt)
	
	var g := get_gravity()
	outside = plane.is_outside(global_position + Vector3(0, 1.0, 0))
	var brace := 0.25 if crouching else 1.0
	
	# Suction toward hull breach
	ext_vel += plane.get_suction(global_position + Vector3(0, 1.0, 0)) * brace * dt
	
	# Wind outside
	if outside and plane.airborne:
		var wind_scale := clampf(world.flight.speed / 70.0, 0.0, 1.5)
		ext_vel += plane.global_basis.z * WIND_ACCEL * wind_scale * (0.1 if crouching else 1.0) * dt
	
	if on_floor:
		# Slide down tilted floor
		var n := get_floor_normal()
		ext_vel += (g - n * g.dot(n)) * SLIDE * brace * dt
		# Friction
		var friction = BRACE_FRICTION if crouching else FLOOR_FRICTION
		ext_vel = ext_vel.move_toward(Vector3.ZERO, friction * dt)
	else:
		ext_vel *= 1.0 - 0.3 * dt
	
	# Jump with coyote time and buffer
	var vy := velocity.y + g.y * dt
	if on_floor and vy < 0.0:
		vy = maxf(vy, -1.0)
	
	var can_jump := (_coyote_t > 0.0 or on_floor) and _jump_buffer_t > 0.0 and not blocked
	if can_jump:
		vy = JUMP_VELOCITY * clampf(world.flight.felt_gravity(), 0.5, 1.5)
		_coyote_t = 0.0
		_jump_buffer_t = 0.0
	
	velocity = Vector3(_move_vel.x + ext_vel.x, vy + ext_vel.y, _move_vel.z + ext_vel.z)
	move_and_slide()
	
	if is_on_wall():
		ext_vel = ext_vel.slide(get_wall_normal())
	
	if is_on_floor() and ext_vel.y < 0.0:
		ext_vel.y = 0.0
	velocity.y -= ext_vel.y
	
	# Smooth crouch height change
	var target_eye = EYE_HEIGHT - (0.5 if crouching else 0.0)
	var target_height = 1.7 - (0.5 if crouching else 0.0)
	var target_shape_y = 0.85 - (0.25 if crouching else 0.0)
	
	head.position.y = move_toward(head.position.y + _land_dip, target_eye, dt * 8.0)
	_capsule.height = lerpf(_capsule.height, target_height, dt * 10.0)
	_shape.position.y = lerpf(_shape.position.y, target_shape_y, dt * 10.0)
	
	_was_on_floor = on_floor
	_prev_vy = velocity.y


func _animate_local(dt: float) -> void:
	var hv := Vector2(velocity.x, velocity.z).length()
	if _hands_parent and _hands_parent.visible:
		var punch := 1.0 - _punch_t / PUNCH_COOLDOWN if _punch_t > 0.0 else 0.0
		PlayerLook.animate_fp_arms(_fp_parts, dt, hv, held_id != 0, piloting, crouching, punch)
	_punch_t = maxf(0.0, _punch_t - dt)

	# Crew body (local player in 3rd person)
	if _third_person and _tp_parts:
		PlayerLook.animate_tp_body(_tp_parts, dt, hv, look_pitch, crouching, seated, piloting, held_id != 0)
	
	# Camera shake
	var t := _trauma * _trauma
	var cam = _tp_camera if _third_person else camera
	if cam and t > 0.01:
		cam.h_offset = randf_range(-1, 1) * 0.08 * t
		cam.v_offset = randf_range(-1, 1) * 0.08 * t
		cam.rotation.z = randf_range(-1, 1) * 0.05 * t


func _update_camera_boom(dt: float) -> void:
	if not _third_person or not _cam_boom or not _tp_camera:
		return
	
	# Desired boom length
	var target_dist = 3.0
	var target_height = 1.5
	
	# Raycast from head to camera target to avoid clipping through hull
	var space = get_world_3d().direct_space_state
	var from = head.global_position
	var to = _cam_target.global_position
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = Layers.WORLD
	query.exclude = [self.get_rid(), world.plane.get_rid()] if world.plane else [self.get_rid()]
	var result = space.intersect_ray(query)
	
	if result:
		# Hit something, pull camera in
		var hit_dist = (result.position - from).length()
		target_dist = min(target_dist, hit_dist - 0.1)
	
	# Smooth boom length
	_cam_target.position = _cam_target.position.lerp(Vector3(0, 0, target_dist), dt * 10.0)
	_cam_boom.position = _cam_boom.position.lerp(Vector3(0, target_height, 0), dt * 8.0)
	
	# Smooth boom rotation to follow player yaw and look pitch
	_cam_boom.rotation.y = lerp_angle(_cam_boom.rotation.y, rotation.y, dt * 15.0)
	_cam_boom.rotation.x = lerpf(_cam_boom.rotation.x, look_pitch, dt * 15.0)


# --- Seating -----------------------------------------------------------------------------

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
	var target_eye = PILOT_EYE if piloting else SEATED_EYE
	head.position.y = move_toward(head.position.y, target_eye, dt * 4.0)
	if seated and not piloting and not world.input_blocked():
		if Input.is_action_just_pressed("jump") or Input.get_vector("move_left", "move_right", "move_forward", "move_back") != Vector2.ZERO:
			stand()


func _send_pilot_input() -> void:
	if world.input_blocked():
		world.send_pilot_input(0, 0, 0)
		return
	world.send_pilot_input(Input.get_axis("move_forward", "move_back"),
		Input.get_axis("move_left", "move_right"), Input.get_axis("crouch", "sprint"))


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
	var cam = _tp_camera if _third_person else camera
	if not cam or not ray:
		return
	ray.global_position = cam.global_position
	ray.target_position = cam.global_position - cam.global_basis.z * REACH
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
	var cam = _tp_camera if _third_person else camera
	if not cam:
		return
	var dir: Vector3 = -cam.global_basis.z
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


# --- Remote --------------------------------------------------------------------------

func apply_remote_state(st: Array) -> void:
	_remote_pos = st[0]
	_remote_yaw = st[1]
	_remote_pitch = st[2]
	hold_point = st[3]
	_remote_flags = st[4]
	seated = (_remote_flags & 1) != 0
	crouching = (_remote_flags & 4) != 0
	piloting = (_remote_flags & 2) != 0
	held_id = (_remote_flags & 8) != 0
	if not _has_remote:
		_has_remote = true
		global_position = _remote_pos
		rotation.y = _remote_yaw
		if head:
			head.rotation.x = _remote_pitch


func _remote_update(dt: float) -> void:
	if not _has_remote:
		return
	var k := clampf(dt * 15.0, 0.0, 1.0)
	var before := global_position
	global_position = global_position.lerp(_remote_pos, k)
	rotation.y = lerp_angle(rotation.y, _remote_yaw, k)
	if head:
		head.rotation.x = _remote_pitch

	if _tp_parts and dt > 0.0:
		var moved := global_position - before
		var hv := Vector2(moved.x, moved.z).length() / dt
		PlayerLook.animate_tp_body(_tp_parts, dt, hv, _remote_pitch, crouching, seated, piloting, held_id != 0)


# --- Cleanup ---------------------------------------------------------------------------

func _exit_tree() -> void:
	if is_local and Settings:
		Settings.changed.disconnect(_on_settings_changed)