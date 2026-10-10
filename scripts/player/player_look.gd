extends RefCounted
## Builds detailed first-person arms (with sleeves, proper hands) and third-person character body
## for local and remote players. Meshes/materials cached and shared.

const SOLE := Color(0.15, 0.12, 0.1)

static var _mats := {}
static var _meshes := {}

# --- Shared resources --------------------------------------------------------------------

static func mat(c: Color, rough := 0.8, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f/%.2f" % [c.to_html(), rough, metal, glow]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = glow
		_mats[key] = m
	return _mats[key]


static func sphere(r: float, hemi := false) -> Mesh:
	var key := "s%.3f%s" % [r, hemi]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * (1.0 if hemi else 2.0)
		m.is_hemisphere = hemi
		m.radial_segments = 16
		m.rings = 8
		_meshes[key] = m
	return _meshes[key]


static func capsule(r: float, h: float) -> Mesh:
	var key := "c%.3f/%.3f" % [r, h]
	if not _meshes.has(key):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = maxf(h, r * 2.0)
		m.radial_segments = 14
		m.rings = 4
		_meshes[key] = m
	return _meshes[key]


static func cyl(top: float, bottom: float, h: float) -> Mesh:
	var key := "y%.3f/%.3f/%.3f" % [top, bottom, h]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = h
		m.radial_segments = 16
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func box(size: Vector3) -> Mesh:
	var key := "b%v" % size
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


# --- First-person arms -------------------------------------------------------------------

## Builds detailed FP arms with sleeves and articulated hands onto `parent` (camera child).
## Returns {hand_l, hand_r, wrist_l, wrist_r, forearm_l, forearm_r, upper_arm_l, upper_arm_r}
## All joints are Node3D pivots for animation.
static func build_fp_arms(color: Color, skin: Color, parent: Node3D) -> Dictionary:
	var parts := {}
	
	# Shoulder pivots (in camera space, roughly at shoulder level)
	var shoulder_l = Node3D.new()
	shoulder_l.position = Vector3(-0.22, -0.15, -0.1)
	parent.add_child(shoulder_l)
	parts.shoulder_l = shoulder_l
	
	var shoulder_r = Node3D.new()
	shoulder_r.position = Vector3(0.22, -0.15, -0.1)
	parent.add_child(shoulder_r)
	parts.shoulder_r = shoulder_r
	
	# Upper arms
	var upper_arm_l = _part(capsule(0.045, 0.28), Vector3(0, -0.14, 0), color, shoulder_l)
	upper_arm_l.rotation.x = PI / 2
	parts.upper_arm_l = upper_arm_l
	
	var upper_arm_r = _part(capsule(0.045, 0.28), Vector3(0, -0.14, 0), color, shoulder_r)
	upper_arm_r.rotation.x = PI / 2
	parts.upper_arm_r = upper_arm_r
	
	# Elbow pivots
	var elbow_l = Node3D.new()
	elbow_l.position = Vector3(0, -0.28, 0)
	upper_arm_l.add_child(elbow_l)
	parts.elbow_l = elbow_l
	
	var elbow_r = Node3D.new()
	elbow_r.position = Vector3(0, -0.28, 0)
	upper_arm_r.add_child(elbow_r)
	parts.elbow_r = elbow_r
	
	# Forearms (with sleeve cuffs)
	var forearm_l = _part(capsule(0.04, 0.26), Vector3(0, -0.13, 0), color, elbow_l)
	forearm_l.rotation.x = PI / 2
	parts.forearm_l = forearm_l
	
	var forearm_r = _part(capsule(0.04, 0.26), Vector3(0, -0.13, 0), color, elbow_r)
	forearm_r.rotation.x = PI / 2
	parts.forearm_r = forearm_r
	
	# Cuffs at wrist
	_part(capsule(0.045, 0.06), Vector3(0, -0.26, 0), Color(0.95, 0.95, 0.9), forearm_l)
	_part(capsule(0.045, 0.06), Vector3(0, -0.26, 0), Color(0.95, 0.95, 0.9), forearm_r)
	
	# Wrist pivots
	var wrist_l = Node3D.new()
	wrist_l.position = Vector3(0, -0.26, 0)
	forearm_l.add_child(wrist_l)
	parts.wrist_l = wrist_l
	
	var wrist_r = Node3D.new()
	wrist_r.position = Vector3(0, -0.26, 0)
	forearm_r.add_child(wrist_r)
	parts.wrist_r = wrist_r
	
	# Hands (palm + fingers/thumb)
	parts.hand_l = _build_hand(skin, wrist_l, true)
	parts.hand_r = _build_hand(skin, wrist_r, false)
	
	# Hide shadows for FP arms
	for p in parts:
		if parts[p] is MeshInstance3D:
			parts[p].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	return parts


static func _build_hand(skin: Color, wrist: Node3D, is_left: bool) -> Node3D:
	var hand = Node3D.new()
	wrist.add_child(hand)
	
	# Palm (slightly flattened sphere)
	var palm = _part(sphere(0.045, true), Vector3(0, 0, -0.02), skin, hand)
	palm.scale = Vector3(1.0, 0.7, 0.6)
	palm.rotation.x = PI / 2
	
	# Finger data: (name, base_pos, base_rot, segments)
	# segments: array of [length, radius]
	var finger_data := [
		["index",  Vector3(-0.035, 0, 0.025), Vector3(0.1, 0, 0), [[0.055, 0.015], [0.04, 0.012], [0.03, 0.01]]],
		["middle", Vector3(0.0,     0, 0.03),  Vector3(0.1, 0, 0), [[0.06, 0.016], [0.045, 0.013], [0.035, 0.011]]],
		["ring",   Vector3(0.035,   0, 0.025), Vector3(0.1, 0, 0), [[0.05, 0.014], [0.038, 0.011], [0.028, 0.01]]],
		["pinky",  Vector3(0.065,   0, 0.015), Vector3(0.1, 0, 0), [[0.04, 0.012], [0.03, 0.01], [0.02, 0.009]]],
	]
	
	for finger in finger_data:
		var fname = finger[0]
		var fpos = finger[1]
		var frot = finger[2]
		var segments = finger[3]
		var prev = hand
		var prev_pos = fpos
		for seg_data in segments:
			var seg_len = seg_data[0]
			var seg_rad = seg_data[1]
			var joint = Node3D.new()
			joint.position = prev_pos
			joint.rotation = frot
			prev.add_child(joint)
			
			var seg = _part(capsule(seg_rad, seg_len), Vector3(0, -seg_len * 0.5, 0), skin, joint)
			seg.rotation.x = PI / 2
			
			prev = joint
			prev_pos = Vector3(0, -seg_len, 0)
	
	# Thumb (2 segments, different angle)
	var thumb_base = Node3D.new()
	thumb_base.position = Vector3(0.055 if is_left else -0.055, 0, -0.015)
	thumb_base.rotation = Vector3(-0.5, 0, 0.8 if is_left else -0.8)
	hand.add_child(thumb_base)
	
	var thumb1 = _part(capsule(0.016, 0.04), Vector3(0, -0.02, 0), skin, thumb_base)
	thumb1.rotation.x = PI / 2
	
	var thumb_tip = Node3D.new()
	thumb_tip.position = Vector3(0, -0.04, 0)
	thumb_base.add_child(thumb_tip)
	var thumb2 = _part(capsule(0.014, 0.03), Vector3(0, -0.015, 0), skin, thumb_tip)
	thumb2.rotation.x = PI / 2
	
	return hand


# --- Third-person character body ---------------------------------------------------------

## Builds a detailed character body (torso, head with face, hair, arms with hands, legs with shoes)
## onto `parent` (the Player root). Returns {head, neck, body, legs, arms_vis, label, pivots...}
## `color` = clothing color, `skin` = skin tone, `hair` = hair color, `name` = display name.
static func build_tp_body(color: Color, skin: Color, hair: Color, name: String, parent: Node3D) -> Dictionary:
	var parts := {}
	var body_vis = Node3D.new()
	parent.add_child(body_vis)
	parts.body_vis = body_vis
	
	# Torso (capsule, slightly flattened front-back)
	var torso = _part(capsule(0.27, 0.78), Vector3(0, 1.15, 0), color, body_vis, Vector3.ZERO, Vector3(1, 1, 0.75))
	parts.torso = torso
	
	# Zip/seam line
	_part(capsule(0.06, 0.3), Vector3(0, 1.3, -0.2), color.darkened(0.25), body_vis)
	
	# Neck
	var neck = Node3D.new()
	neck.position = Vector3(0, 1.55, 0)
	body_vis.add_child(neck)
	parts.neck = neck
	
	# Head
	var head = Node3D.new()
	head.position = Vector3(0, 0.17, 0)
	neck.add_child(head)
	parts.head = head
	
	# Skull
	_part(sphere(0.21), Vector3.ZERO, skin, head)
	# Hair cap
	_part(sphere(0.22), Vector3(0, 0.07, 0.03), hair, head, Vector3.ZERO, Vector3(1, 0.75, 1))
	# Ears
	for ex in [-0.075, 0.075]:
		_part(sphere(0.045), Vector3(ex, 0.02, -0.18), Color.WHITE, head)
		_part(sphere(0.022), Vector3(ex, 0.02, -0.215), Color(0.08, 0.08, 0.1), head)
	# Nose
	_part(capsule(0.018, 0.1), Vector3(0, -0.09, -0.19), Color(0.5, 0.15, 0.15), head, Vector3(0, 0, PI / 2))
	_part(sphere(0.03), Vector3(0, -0.02, -0.21), skin.darkened(0.1), head)
	
	# Eyes (white + pupil) - billboarded later by NPC look logic
	for ex in [-0.065, 0.065]:
		var eye_white = _part(sphere(0.045, true), Vector3(ex, 0.03, -0.18), Color.WHITE, head)
		eye_white.rotation.x = PI / 2
		_part(sphere(0.022), Vector3(ex, 0.03, -0.215), Color(0.08, 0.08, 0.1), head)
	
	# Eyebrows
	for ex in [-0.065, 0.065]:
		_part(box(Vector3(0.05, 0.01, 0.005)), Vector3(ex, 0.08, -0.17), Color(0.1, 0.08, 0.05), head)
	
	# Mouth
	var mouth = _part(capsule(0.018, 0.07), Vector3(0, -0.06, -0.2), Color(0.4, 0.15, 0.15), head, Vector3(PI / 2, 0, 0))
	parts.mouth = mouth
	
	# Legs
	var legs = Node3D.new()
	legs.position.y = 0.82
	body_vis.add_child(legs)
	parts.legs = legs
	
	for lx in [-0.13, 0.13]:
		# Thigh
		_part(capsule(0.1, 0.45), Vector3(lx, -0.225, 0), color.darkened(0.15), legs)
		# Knee joint
		_part(sphere(0.055), Vector3(lx, -0.45, -0.02), color.darkened(0.1), legs)
		# Shin
		_part(capsule(0.085, 0.4), Vector3(lx, -0.65, 0), color.darkened(0.1), legs)
		# Ankle
		_part(sphere(0.045), Vector3(lx, -0.85, -0.02), color.darkened(0.05), legs)
		# Foot / shoe
		var foot = Node3D.new()
		foot.position = Vector3(lx, -0.88, 0.05)
		legs.add_child(foot)
		parts["foot_%s" % ("l" if lx < 0 else "r")] = foot
		_part(box(Vector3(0.12, 0.06, 0.28)), Vector3(0, 0.03, 0.1), SOLE, foot)
		_part(box(Vector3(0.11, 0.07, 0.22)), Vector3(0, 0.1, 0.05), color.darkened(0.3), foot)
		_part(box(Vector3(0.09, 0.06, 0.1)), Vector3(0, 0.13, -0.11), color.darkened(0.4), foot) # heel
	
	# Arms (visible in 3rd person)
	var arms_vis = Node3D.new()
	arms_vis.position.y = 1.42
	body_vis.add_child(arms_vis)
	parts.arms_vis = arms_vis
	
	for ax in [-0.36, 0.36]:
		var upper = _part(capsule(0.075, 0.3), Vector3(ax, -0.15, 0), color, arms_vis)
		upper.rotation.x = PI / 2
		# Elbow
		_part(sphere(0.045), Vector3(ax, -0.3, 0), color.darkened(0.1), arms_vis)
		# Forearm
		var forearm = _part(capsule(0.065, 0.28), Vector3(ax, -0.44, 0), color, arms_vis)
		forearm.rotation.x = PI / 2
		# Wrist
		_part(sphere(0.04), Vector3(ax, -0.58, 0), color.darkened(0.05), arms_vis)
		# Hand (simpler than FP)
		var hand = Node3D.new()
		hand.position = Vector3(ax, -0.58, 0)
		arms_vis.add_child(hand)
		parts["hand_%s" % ("l" if ax < 0 else "r")] = hand
		_part(sphere(0.05, true), Vector3(0, 0, 0), skin, hand, Vector3(PI / 2, 0, 0))
	
	# Name label
	var label = Label3D.new()
	label.text = name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.2
	label.font_size = 48
	label.outline_size = 10
	label.pixel_size = 0.004
	parent.add_child(label)
	parts.label = label
	
	return parts


# --- Animation helpers -------------------------------------------------------------------

## Updates FP arm positions for walking/running/idle/holding/piloting.
## `parts` from build_fp_arms, `hv` = horizontal speed, `dt`, `held`, `piloting`, `punch_t`, `bob_t` (ref), `trauma`.
static func animate_fp_arms(parts: Dictionary, hv: float, dt: float, held: bool, piloting: bool,
		punch_t: float, bob_t: float, trauma: float) -> float:
	# Bob when moving on ground
	var new_bob_t = bob_t
	if hv > 0.5 and not held and not piloting:
		new_bob_t += dt * hv * 2.2
	
	var bob = Vector3(cos(new_bob_t * 0.5) * 0.025, -absf(sin(new_bob_t * 0.5)) * 0.04, 0)
	var sway = Vector3(sin(new_bob_t * 0.3) * 0.015, 0, cos(new_bob_t * 0.3) * 0.01)
	
	var punch := sin(punch_t / 0.35 * PI) * 0.25 if punch_t > 0.0 else 0.0
	var hold_offset = Vector3(-0.06, 0.08, -0.1) if held else Vector3.ZERO
	
	# Rest positions (relative to shoulder)
	var rest_l = Vector3(-0.22, -0.41, -0.52) + hold_offset
	var rest_r = Vector3(0.22, -0.41, -0.52) + Vector3(0.06, 0.08, -0.1) if held else Vector3(0.22, -0.41, -0.52)
	
	if piloting:
		# Hands on yoke
		parts.shoulder_l.position = parts.shoulder_l.position.lerp(Vector3(-0.2, -0.12, -0.15), dt * 10)
		parts.shoulder_r.position = parts.shoulder_r.position.lerp(Vector3(0.2, -0.12, -0.15), dt * 10)
		parts.upper_arm_l.rotation = parts.upper_arm_l.rotation.lerp(Vector3(0.6, 0, -0.3), dt * 10)
		parts.upper_arm_r.rotation = parts.upper_arm_r.rotation.lerp(Vector3(0.6, 0, 0.3), dt * 10)
		parts.forearm_l.rotation = parts.forearm_l.rotation.lerp(Vector3(-0.4, 0, 0), dt * 10)
		parts.forearm_r.rotation = parts.forearm_r.rotation.lerp(Vector3(-0.4, 0, 0), dt * 10)
		parts.wrist_l.rotation = parts.wrist_l.rotation.lerp(Vector3(0, 0, 0.2), dt * 10)
		parts.wrist_r.rotation = parts.wrist_r.rotation.lerp(Vector3(0, 0, -0.2), dt * 10)
	else:
		# Natural arm swing while walking
		var swing = sin(new_bob_t * 2.0) * 0.4 if hv > 0.5 else 0.0
		var swing_l = swing
		var swing_r = -swing
		
		parts.shoulder_l.position = parts.shoulder_l.position.lerp(Vector3(-0.22 + sway.x, -0.15 + sway.y, -0.1), dt * 8)
		parts.shoulder_r.position = parts.shoulder_r.position.lerp(Vector3(0.22 - sway.x, -0.15 + sway.y, -0.1), dt * 8)
		
		parts.upper_arm_l.rotation = parts.upper_arm_l.rotation.lerp(Vector3(PI/2 + swing_l * 0.5, 0, -0.15), dt * 8)
		parts.upper_arm_r.rotation = parts.upper_arm_r.rotation.lerp(Vector3(PI/2 + swing_r * 0.5, 0, 0.15), dt * 8)
		
		parts.forearm_l.rotation = parts.forearm_l.rotation.lerp(Vector3(PI/2 - swing_l * 0.3, 0, 0.1), dt * 8)
		parts.forearm_r.rotation = parts.forearm_r.rotation.lerp(Vector3(PI/2 - swing_r * 0.3, 0, -0.1), dt * 8)
		
		parts.wrist_l.rotation = parts.wrist_l.rotation.lerp(Vector3(0, 0, 0), dt * 8)
		parts.wrist_r.rotation = parts.wrist_r.rotation.lerp(Vector3(0, 0, 0), dt * 8)
		
		# Hold pose overrides
		if held:
			parts.wrist_l.rotation = parts.wrist_l.rotation.lerp(Vector3(-0.3, 0, 0.2), dt * 14)
			parts.wrist_r.rotation = parts.wrist_r.rotation.lerp(Vector3(-0.3, 0, -0.2), dt * 14)
			parts.forearm_l.rotation = parts.forearm_l.rotation.lerp(Vector3(PI/2 + 0.4, 0, 0), dt * 14)
			parts.forearm_r.rotation = parts.forearm_r.rotation.lerp(Vector3(PI/2 + 0.4, 0, 0), dt * 14)
	
	# Punch animation on right arm
	if punch_t > 0.0:
		parts.upper_arm_r.rotation = parts.upper_arm_r.rotation.lerp(Vector3(PI/2 - 1.2, 0, 0.2), dt * 20)
		parts.forearm_r.rotation = parts.forearm_r.rotation.lerp(Vector3(PI/2 + 0.8, 0, 0), dt * 20)
		parts.wrist_r.position = parts.wrist_r.position.lerp(Vector3(0, -0.26, -punch * 0.1), dt * 20)
	
	# Apply bob to shoulders
	parts.shoulder_l.position += bob * 0.5 + Vector3(-sway.x * 0.5, 0, -sway.z * 0.5)
	parts.shoulder_r.position += bob * 0.5 + Vector3(sway.x * 0.5, 0, -sway.z * 0.5)
	
	# Camera shake from trauma
	var t := trauma * trauma
	if t > 0.01:
		parts.shoulder_l.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.02 * t
		parts.shoulder_r.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.02 * t
	
	return new_bob_t


## Updates TP body for walk cycle, crouch, seated, holding.
## `parts` from build_tp_body, `hv` = horizontal speed, `dt`, `crouching`, `seated`, `piloting`, `held`, `flags` (remote flags), `k` = lerp factor.
static func animate_tp_body(parts: Dictionary, hv: float, dt: float, crouching: bool, seated: bool, piloting: bool,
		held: bool, k: float) -> void:
	
	var sitting := seated or piloting
	
	# Body height for crouch/seated
	var target_y = -0.35 if sitting else (-0.3 if crouching else 0.0)
	parts.body_vis.position.y = lerpf(parts.body_vis.position.y, target_y, k)
	
	# Legs rotation for seated
	var leg_rot_target = PI / 2 if sitting else 0.0
	parts.legs.rotation.x = lerpf(parts.legs.rotation.x, leg_rot_target, k)
	
	# Walk cycle
	if hv > 0.3 and not sitting:
		var t = Time.get_ticks_msec() * 0.001 * hv * 3.0
		var swing = sin(t) * 0.8
		
		# Legs
		var foot_l = parts.foot_l
		var foot_r = parts.foot_r
		if foot_l and foot_r:
			foot_l.position = foot_l.position.lerp(Vector3(-0.13, -0.88 + abs(sin(t)) * 0.08, sin(t) * 0.15), k * 0.5)
			foot_r.position = foot_r.position.lerp(Vector3(0.13, -0.88 + abs(sin(t + PI)) * 0.08, sin(t + PI) * 0.15), k * 0.5)
		
		# Arms swing opposite to legs
		var hand_l = parts.hand_l
		var hand_r = parts.hand_r
		if hand_l and hand_r:
			hand_l.position = hand_l.position.lerp(Vector3(-0.36, -0.58 + sin(t) * 0.05, sin(t) * 0.12), k * 0.5)
			hand_r.position = hand_r.position.lerp(Vector3(0.36, -0.58 + sin(t + PI) * 0.05, sin(t + PI) * 0.12), k * 0.5)
	else:
		# Idle arm positions
		var hand_l = parts.hand_l
		var hand_r = parts.hand_r
		if hand_l and hand_r:
			hand_l.position = hand_l.position.lerp(Vector3(-0.36, -0.58, 0), k)
			hand_r.position = hand_r.position.lerp(Vector3(0.36, -0.58, 0), k)
	
	# Arms up when holding
	if held:
		var hand_l = parts.hand_l
		var hand_r = parts.hand_r
		if hand_l:
			hand_l.position = hand_l.position.lerp(Vector3(-0.3, -0.3, -0.2), k)
		if hand_r:
			hand_r.position = hand_r.position.lerp(Vector3(0.3, -0.3, -0.2), k)
	
	# Pilot pose
	if piloting:
		var hand_l = parts.hand_l
		var hand_r = parts.hand_r
		if hand_l:
			hand_l.position = hand_l.position.lerp(Vector3(-0.25, -0.35, -0.3), k)
		if hand_r:
			hand_r.position = hand_r.position.lerp(Vector3(0.25, -0.35, -0.3), k)
	
	# Head follows look pitch (handled by remote update or local)


# --- Helper ------------------------------------------------------------------------------

static func _part(mesh: Mesh, pos: Vector3, color: Color, parent: Node3D, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.material_override = mat(color)
	parent.add_child(mi)
	return mi