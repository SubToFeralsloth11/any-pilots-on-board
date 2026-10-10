extends RefCounted
## Crew look for players, in the "Dear Passengers" cartoon style.
##
## First person: chunky white shirt sleeves with a cuff and big rounded mitten hands in the
## player's colour, parented to the camera. Each arm is one pivot at the shoulder whose -Z
## points down the forearm; the hand is a child pivot at the wrist, so the hand can never
## come loose from the sleeve.
##
## Third person (remote players, and yourself with [V]): a rounded bean creature in the
## player's colour with big googly eyes, wearing an airline uniform (white short-sleeve
## shirt, dark tie, navy trousers, gold epaulettes, navy pilot cap with a gold badge).
##
## All static geometry is baked with MeshBatch into one mesh per limb and cached per colour,
## so every player of the same colour shares the same meshes and materials.

const MeshBatch := preload("res://scripts/plane/plane_mesh.gd")
const MATTE := MeshBatch.Finish.MATTE
const FABRIC := MeshBatch.Finish.FABRIC
const PAINT := MeshBatch.Finish.PAINT
const METAL := MeshBatch.Finish.METAL
const GLOSS := MeshBatch.Finish.GLOSS

const SHIRT := Color(0.97, 0.97, 0.95)
const CUFF := Color(0.9, 0.91, 0.93)
const NAVY := Color(0.1, 0.13, 0.3)
const TIE := Color(0.08, 0.09, 0.16)
const GOLD := Color(0.98, 0.76, 0.22)
const SHOE := Color(0.07, 0.07, 0.08)
const EYE_WHITE := Color(1, 1, 1)
const PUPIL := Color(0.03, 0.03, 0.05)

## First-person forearm length, shoulder pivot to wrist pivot (camera-space metres).
const FP_ARM_LEN := 0.46

## Third-person body proportions (player-local, feet at y = 0, facing -Z).
const BODY_Y := 1.12        ## Centre of the bean-shaped body.
const BODY_RY := 0.6        ## Half height of the body.
const BODY_R := 0.34        ## Half width of the body.
const BODY_DEPTH := 0.9     ## Depth / width ratio of every body cross-section.
const HIP_Y := 0.42         ## Leg pivots.
const SHOULDER := Vector3(0.37, 1.2, 0.0)
const SEATED_DROP := 0.02   ## Body offset while seated (hips on the seat cushion).
const CROUCH_DROP := -0.22
const LABEL_Y := 2.12       ## Name label height; leave room above it for a speaker icon.
const EYE_R := 0.1
const PUPIL_R := 0.046

static var _cache := {}     ## Key -> baked ArrayMesh.


# --- First-person arms -------------------------------------------------------------------

## Builds both first-person arms under `camera`. Returns the parts dictionary that
## animate_fp_arms() expects: {root, arm_l, arm_r, hand_l, hand_r, ...animation state}.
static func build_fp_arms(color: Color, camera: Node3D) -> Dictionary:
	var root := Node3D.new()
	root.name = "FPArms"
	camera.add_child(root)
	var parts := {"root": root, "t": 0.0, "phase": 0.0}
	for side: int in [-1, 1]:
		var s := "l" if side < 0 else "r"
		var arm := _mesh_node(root, _fp_sleeve_mesh(), false)
		var hand := _mesh_node(arm, _fp_hand_mesh(color, side), false)
		hand.position = Vector3(0, 0, -FP_ARM_LEN)
		parts["arm_" + s] = arm
		parts["hand_" + s] = hand
		var pose := _fp_rest(side)
		parts["h_" + s] = pose.h
		parts["d_" + s] = pose.d
		parts["q_" + s] = pose.q
		_fp_place(arm, hand, pose.h, pose.d, pose.q)
	return parts


## Rest pose of one hand: wrist point h, forearm direction d (shoulder -> wrist), wrist rotation q.
static func _fp_rest(side: int) -> Dictionary:
	var sx := float(side)
	return {"h": Vector3(0.22 * sx, -0.25, -0.44), "d": Vector3(-0.22 * sx, 0.5, -1.0).normalized(),
		"q": _wrist(0.18 * sx, -0.08)}


## Wrist rotation: roll about the forearm (positive = back of the hand turns to -X), then bend.
static func _wrist(roll: float, bend: float) -> Quaternion:
	return Quaternion(Vector3(0, 0, 1), roll) * Quaternion(Vector3(1, 0, 0), bend)


static func _fp_place(arm: Node3D, hand: Node3D, h: Vector3, d: Vector3, q: Quaternion) -> void:
	arm.basis = Basis.looking_at(d, Vector3.UP)
	arm.position = h - d * FP_ARM_LEN
	hand.quaternion = q


## Animates the FP arms: idle sway, walk bob/arm swing, crouch, reach-forward hold pose,
## pilot pose (hands forward on the yoke) and a right-hand jab. `punch` is the jab progress
## 0..1 (0 = not punching). State lives in `parts`.
static func animate_fp_arms(parts: Dictionary, dt: float, hv: float, held: bool, piloting: bool,
		crouching: bool, punch: float) -> void:
	var amp := clampf(hv / 7.0, 0.0, 1.0) if not piloting else 0.0
	parts.t += dt
	parts.phase += dt * (2.0 + hv * 1.7) if amp > 0.05 else 0.0
	var t: float = parts.t
	var ph: float = parts.phase
	var k := 1.0 - exp(-dt * 14.0)
	for side: int in [-1, 1]:
		var s := "l" if side < 0 else "r"
		var sx := float(side)
		var pose := _fp_rest(side)
		var h: Vector3 = pose.h
		var d: Vector3 = pose.d
		var q: Quaternion = pose.q
		if piloting:
			h = Vector3(0.16 * sx, -0.19, -0.5)
			d = Vector3(-0.3 * sx, 0.3, -1.0).normalized()
			q = _wrist(1.3 * sx, 0.1)
		elif held:
			h = Vector3(0.17 * sx, -0.16, -0.56)
			d = Vector3(-0.32 * sx, 0.25, -1.0).normalized()
			q = _wrist(1.0 * sx, 0.2)
		if crouching and not piloting:
			h += Vector3(0.0, -0.03, 0.03)
		# Idle breathing sway, then the walk bob: hands dip on each step and swing fore/aft.
		h += Vector3(sin(t * 0.9 + sx) * 0.004, sin(t * 1.7) * 0.006, 0.0)
		h += Vector3(cos(ph) * 0.016, -absf(sin(ph)) * 0.035, sin(ph) * 0.05 * sx) * amp
		parts["h_" + s] = (parts["h_" + s] as Vector3).lerp(h, k)
		parts["d_" + s] = (parts["d_" + s] as Vector3).slerp(d, k).normalized()
		parts["q_" + s] = (parts["q_" + s] as Quaternion).slerp(q, k)
		var hh: Vector3 = parts["h_" + s]
		var dd: Vector3 = parts["d_" + s]
		var qq: Quaternion = parts["q_" + s]
		if punch > 0.0 and not held and not piloting:
			# Fast snap out (first 30%), slower return. Left hand tucks back as a guard.
			var e := punch / 0.3 if punch < 0.3 else 1.0 - (punch - 0.3) / 0.7
			e = e * e * (3.0 - 2.0 * e)
			if side > 0:
				hh = hh.lerp(Vector3(0.06, -0.12, -0.74), e)
				dd = dd.slerp(Vector3(-0.12, 0.15, -1.0).normalized(), e)
				qq = qq.slerp(_wrist(0.5, 0.0), e)
			else:
				hh = hh.lerp(hh + Vector3(0.03, 0.04, 0.06), e)
		_fp_place(parts["arm_" + s], parts["hand_" + s], hh, dd, qq)


## Sleeve (shoulder pivot at the origin, wrist at -Z FP_ARM_LEN): white shirt sleeve and a
## rolled cuff with a gold cufflink. Shared by both arms.
static func _fp_sleeve_mesh() -> ArrayMesh:
	if _cache.has("fp_sleeve"):
		return _cache.fp_sleeve
	var b := MeshBatch.new()
	var z := -FP_ARM_LEN
	b.revolve(PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.12, 0.068), Vector2(z + 0.06, 0.062),
		Vector2(z + 0.06, 0.0)]), Transform3D.IDENTITY, SHIRT, FABRIC, 20)
	b.revolve(PackedVector2Array([Vector2(z + 0.085, 0.0), Vector2(z + 0.085, 0.066), Vector2(z + 0.075, 0.072),
		Vector2(z + 0.008, 0.072), Vector2(z - 0.002, 0.065), Vector2(z - 0.002, 0.048),
		Vector2(z + 0.01, 0.0)]), Transform3D.IDENTITY, CUFF, FABRIC, 20)
	# Navy cuff stripe with a thin gold line: reads as uniform even at a glance.
	b.revolve(PackedVector2Array([Vector2(z + 0.05, 0.0727), Vector2(z + 0.03, 0.0727)]),
		Transform3D.IDENTITY, NAVY, FABRIC, 20)
	b.revolve(PackedVector2Array([Vector2(z + 0.026, 0.0728), Vector2(z + 0.02, 0.0728)]),
		Transform3D.IDENTITY, GOLD, METAL, 20)
	b.ellipsoid(Vector3(0.012, 0.008, 0.012), Transform3D(Basis.IDENTITY, Vector3(0, 0.073, z + 0.065)),
		GOLD, METAL, 10, 6)
	_cache.fp_sleeve = b.commit()
	return _cache.fp_sleeve


## Mitten hand (wrist pivot at the origin, fingers toward -Z, back of the hand +Y): wrist stub,
## smooth palm blob, four finger bumps and a separate thumb on the inner side.
static func _fp_hand_mesh(color: Color, side: int) -> ArrayMesh:
	var key := "fp_hand/%s/%d" % [color.to_html(), side]
	if _cache.has(key):
		return _cache[key]
	var b := MeshBatch.new()
	var sx := float(side)
	var sc := 1.3
	var big := Transform3D(Basis.from_scale(Vector3.ONE * sc), Vector3.ZERO)
	b.cylinder(Vector3(0, 0, 0.04), Vector3(0, 0, -0.05 * sc), 0.045, 0.048 * sc, color, PAINT, 16)
	b.ellipsoid(Vector3(0.066, 0.04, 0.072), big * _xf(Vector3(0, 0.002, -0.085)), color, PAINT, 20, 12)
	for i in 4:
		var fx := (-0.042 + 0.028 * i) * sx
		var flen := 0.042 if i == 1 or i == 2 else 0.036
		b.ellipsoid(Vector3(0.018, 0.026, flen), big * _xf(Vector3(fx, -0.006, -0.15 + absf(fx) * 0.25),
			Vector3(0.25, fx * 2.0, 0)), color, PAINT, 12, 8)
	# Thumb: on the inside (toward the other hand), angled forward and slightly down.
	b.ellipsoid(Vector3(0.024, 0.026, 0.05), big * _xf(Vector3(-0.062 * sx, -0.012, -0.082),
		Vector3(0.15, 0.55 * sx, 0.3 * sx)), color.darkened(0.04), PAINT, 14, 8)
	_cache[key] = b.commit()
	return _cache[key]


# --- Third-person crew body --------------------------------------------------------------

## Builds the crew body under `parent` (the Player root). Returns the parts dictionary that
## animate_tp_body() expects: {body_vis, torso, pupils, arm_l, arm_r, leg_l, leg_r, label, ...}.
static func build_tp_body(color: Color, display_name: String, parent: Node3D) -> Dictionary:
	var body_vis := Node3D.new()
	body_vis.name = "CrewBody"
	parent.add_child(body_vis)
	var parts := {"body_vis": body_vis, "phase": 0.0, "walk": 0.0}
	parts.torso = _mesh_node(body_vis, _tp_torso_mesh(color), true)
	var pupils := _mesh_node(body_vis, _tp_pupils_mesh(), false)
	parts.pupils = pupils
	for side: int in [-1, 1]:
		var s := "l" if side < 0 else "r"
		var arm := _mesh_node(body_vis, _tp_arm_mesh(color, side), true)
		arm.position = Vector3(SHOULDER.x * side, SHOULDER.y, SHOULDER.z)
		parts["arm_" + s] = arm
		var leg := _mesh_node(body_vis, _tp_leg_mesh(), true)
		leg.position = Vector3(0.14 * side, HIP_Y, 0.0)
		parts["leg_" + s] = leg

	var label := Label3D.new()
	label.text = display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = LABEL_Y
	label.font_size = 48
	label.outline_size = 12
	label.pixel_size = 0.004
	label.no_depth_test = false
	parent.add_child(label)
	parts.label = label
	return parts


## Animates the crew body: procedural walk cycle (legs and arms swing with speed, a little
## waddle), crouch, seated / piloting pose, holding pose and pupils that follow `pitch`.
static func animate_tp_body(parts: Dictionary, dt: float, hv: float, pitch: float, crouching: bool,
		seated: bool, piloting: bool, held: bool) -> void:
	var sitting := seated or piloting
	var k := 1.0 - exp(-dt * 12.0)
	var walk := 0.0 if sitting else clampf(hv / 4.5, 0.0, 1.4)
	parts.walk = lerpf(parts.walk, walk, k)
	var w: float = parts.walk
	parts.phase = fmod(parts.phase + dt * (3.0 + hv * 1.6) * (1.0 if w > 0.05 else 0.0), TAU)
	var ph: float = parts.phase
	var swing := sin(ph) * 0.7 * w

	var body: Node3D = parts.body_vis
	var y := SEATED_DROP if sitting else (CROUCH_DROP if crouching else 0.0)
	y += absf(cos(ph)) * 0.05 * w
	body.position.y = lerpf(body.position.y, y, k)
	body.rotation.z = lerpf(body.rotation.z, sin(ph) * 0.06 * w, k)
	body.rotation.x = lerpf(body.rotation.x, -0.12 if crouching and not sitting else -0.05 * w, k)

	for side: int in [-1, 1]:
		var s := "l" if side < 0 else "r"
		var sx := float(side)
		var leg: Node3D = parts["leg_" + s]
		var leg_x := PI / 2 if sitting else (0.75 if crouching else swing * sx)
		leg.rotation.x = lerp_angle(leg.rotation.x, leg_x, k)
		var arm: Node3D = parts["arm_" + s]
		var arm_x := -swing * sx * 0.9
		var arm_z := 0.12 * sx
		if piloting:
			arm_x = 1.25
			arm_z = -0.12 * sx
		elif held:
			arm_x = 1.45
			arm_z = -0.18 * sx
		elif sitting:
			arm_x = 0.45
			arm_z = 0.05 * sx
		arm.rotation.x = lerp_angle(arm.rotation.x, arm_x, k)
		arm.rotation.z = lerp_angle(arm.rotation.z, arm_z, k)

	var pupils: Node3D = parts.pupils
	pupils.position.y = lerpf(pupils.position.y, clampf(pitch, -0.8, 0.8) * 0.045, k)


## Body radius at height y (ellipse profile of the bean).
static func _body_r(y: float) -> float:
	var u := clampf((y - BODY_Y) / BODY_RY, -1.0, 1.0)
	return BODY_R * sqrt(1.0 - u * u)


## Transform that revolves MeshBatch profiles about +Y with the body's depth squash.
static func _upright() -> Transform3D:
	return Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, BODY_DEPTH), Vector3(0, 1, 0)), Vector3.ZERO)


## Point on the front of a body-hugging surface at (x, y), pushed `out` metres outward.
static func _front(x: float, y: float, scale := 1.0, out := 0.0) -> Vector3:
	var rx := _body_r(y) * scale
	var u := clampf(x / maxf(rx, 0.001), -1.0, 1.0)
	return Vector3(x, y, -rx * BODY_DEPTH * sqrt(1.0 - u * u) - out)


## Torso: colour bean (head and body in one), shirt with collar, tie and wings badge, navy
## trousers, googly eye whites, navy pilot cap with black band, visor and gold badge.
static func _tp_torso_mesh(color: Color) -> ArrayMesh:
	var key := "tp_torso/%s" % color.to_html()
	if _cache.has(key):
		return _cache[key]
	var b := MeshBatch.new()
	var up := _upright()
	# Bean body.
	var prof := PackedVector2Array()
	for i in 17:
		var a := -PI / 2 + PI * i / 16.0
		prof.append(Vector2(BODY_Y + sin(a) * BODY_RY, cos(a) * BODY_R))
	b.revolve(prof, up, color, PAINT, 24)
	# Shirt: hugs the body from the trousers up to the collar line.
	var shirt := PackedVector2Array([Vector2(0.62, 0.0)])
	for i in 9:
		var y := lerpf(0.62, 1.24, i / 8.0)
		shirt.append(Vector2(y, _body_r(y) * 1.04 + 0.004))
	shirt.append(Vector2(1.25, _body_r(1.25) * 0.99))
	b.revolve(shirt, up, SHIRT, FABRIC, 24)
	# Collar points and the tie (knot + blade following the shirt front).
	for side: int in [-1, 1]:
		var p := _front(0.06 * side, 1.22, 1.04, 0.008)
		b.rounded_box(Vector3(0.1, 0.07, 0.02), _xf(p, Vector3(-0.35, -0.5 * side, 0.85 * side)), CUFF, FABRIC, 0.5, 10, 5)
	var knot := _front(0.0, 1.2, 1.04, 0.016)
	b.ellipsoid(Vector3(0.034, 0.03, 0.02), _xf(knot), TIE, FABRIC, 10, 6)
	var top := _front(0.0, 1.17, 1.04, 0.012)
	var bottom := _front(0.0, 0.86, 1.04, 0.012)
	var blade := Transform3D(Basis.looking_at(Vector3(0, 0, -1), (top - bottom).normalized()), (top + bottom) * 0.5)
	b.rounded_box(Vector3(0.066, top.distance_to(bottom), 0.02), blade, TIE, FABRIC, 0.45, 10, 5)
	b.rounded_box(Vector3(0.05, 0.05, 0.02), _xf(bottom + Vector3(0, -0.005, 0.002), Vector3(0, 0, PI / 4)), TIE, FABRIC, 0.45, 8, 4)
	# Gold wings on the left chest.
	var wings := _front(-0.15, 1.1, 1.04, 0.006)
	b.rounded_box(Vector3(0.1, 0.022, 0.01), _xf(wings, Vector3(0, 0.45, 0)), GOLD, METAL, 0.5, 10, 4)
	b.ellipsoid(Vector3(0.018, 0.018, 0.008), _xf(wings + Vector3(0, 0, -0.003)), GOLD, METAL, 8, 5)
	# Trousers (hips) with a black belt and gold buckle.
	b.ellipsoid(Vector3(0.31, 0.2, 0.28), _xf(Vector3(0, 0.56, 0)), NAVY, FABRIC, 20, 10)
	var belt := PackedVector2Array([Vector2(0.64, 0.0), Vector2(0.64, _body_r(0.64) * 1.06 + 0.01),
		Vector2(0.69, _body_r(0.69) * 1.06 + 0.01), Vector2(0.69, 0.0)])
	b.revolve(belt, up, SHOE, MATTE, 24)
	b.rounded_box(Vector3(0.06, 0.05, 0.015), _xf(_front(0.0, 0.665, 1.06, 0.018)), GOLD, METAL, 0.4, 8, 4)
	# Googly eye whites.
	for side: int in [-1, 1]:
		var e := _front(0.105 * side, 1.47, 1.0, -0.035)
		b.ellipsoid(Vector3(EYE_R, EYE_R * 1.08, EYE_R * 0.85), _xf(e, Vector3(0, -0.2 * side, 0)), EYE_WHITE, GLOSS, 16, 10)
	# Pilot cap: band, crown flaring out to a flat top, visor and badge.
	var band_y := 1.62
	var cap := PackedVector2Array([Vector2(band_y - 0.01, 0.0), Vector2(band_y - 0.01, 0.205),
		Vector2(band_y + 0.07, 0.212), Vector2(band_y + 0.16, 0.255), Vector2(band_y + 0.19, 0.258),
		Vector2(band_y + 0.205, 0.235), Vector2(band_y + 0.21, 0.0)])
	var cap_xf := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 0.95), Vector3(0, 1, 0)), Vector3.ZERO)
	b.revolve(cap, cap_xf, NAVY, FABRIC, 24)
	var band := PackedVector2Array([Vector2(band_y - 0.012, 0.0), Vector2(band_y - 0.012, 0.209),
		Vector2(band_y + 0.05, 0.215), Vector2(band_y + 0.05, 0.0)])
	b.revolve(band, cap_xf, SHOE, GLOSS, 24)
	b.ellipsoid(Vector3(0.17, 0.018, 0.11), _xf(Vector3(0, band_y + 0.005, -0.2), Vector3(-0.22, 0, 0)), SHOE, GLOSS, 18, 6)
	b.rounded_box(Vector3(0.045, 0.024, 0.014), _xf(Vector3(0, band_y + 0.02, -0.215)), GOLD, METAL, 0.4, 8, 4)
	b.ellipsoid(Vector3(0.042, 0.038, 0.012), _xf(Vector3(0, band_y + 0.11, -0.232), Vector3(-0.35, 0, 0)), GOLD, METAL, 12, 6)
	_cache[key] = b.commit()
	return _cache[key]


## Black pupils, one mesh for both eyes (moved as a whole to follow the look pitch).
static func _tp_pupils_mesh() -> ArrayMesh:
	if _cache.has("tp_pupils"):
		return _cache.tp_pupils
	var b := MeshBatch.new()
	for side: int in [-1, 1]:
		var e := _front(0.105 * side, 1.47, 1.0, -0.035)
		var p := e + Vector3(0.012 * side, -0.012, -EYE_R * 0.85 + 0.004)
		b.ellipsoid(Vector3(PUPIL_R, PUPIL_R * 1.05, PUPIL_R * 0.4), _xf(p, Vector3(0, -0.2 * side, 0)), PUPIL, GLOSS, 14, 8)
		b.ellipsoid(Vector3(0.012, 0.012, 0.006), _xf(p + Vector3(0.016, 0.018, -0.016)), EYE_WHITE, GLOSS, 8, 4)
	_cache.tp_pupils = b.commit()
	return _cache.tp_pupils


## Arm (pivot at the shoulder, hanging along -Y): puffy short white sleeve with a gold
## epaulette, arm and a mitten hand in the player's colour.
static func _tp_arm_mesh(color: Color, side: int) -> ArrayMesh:
	var key := "tp_arm/%s/%d" % [color.to_html(), side]
	if _cache.has(key):
		return _cache[key]
	var b := MeshBatch.new()
	var sx := float(side)
	b.ellipsoid(Vector3(0.1, 0.13, 0.1), _xf(Vector3(0.0, -0.06, 0)), SHIRT, FABRIC, 16, 10)
	b.rounded_box(Vector3(0.11, 0.028, 0.14), _xf(Vector3(0.012 * sx, 0.05, 0), Vector3(0, 0, -0.35 * sx)), GOLD, METAL, 0.45, 10, 5)
	b.rounded_box(Vector3(0.112, 0.03, 0.03), _xf(Vector3(0.012 * sx, 0.052, 0), Vector3(0, 0, -0.35 * sx)), NAVY, FABRIC, 0.45, 8, 4)
	b.cylinder(Vector3(0, -0.12, 0), Vector3(0, -0.4, 0), 0.058, 0.052, color, PAINT, 14)
	b.ellipsoid(Vector3(0.068, 0.082, 0.062), _xf(Vector3(0, -0.45, -0.005)), color, PAINT, 16, 10)
	b.ellipsoid(Vector3(0.026, 0.042, 0.026), _xf(Vector3(-0.045 * sx, -0.43, -0.04), Vector3(0.3, 0, 0.5 * sx)), color.darkened(0.04), PAINT, 10, 6)
	_cache[key] = b.commit()
	return _cache[key]


## Leg (pivot at the hip, hanging along -Y): navy trouser leg and a shiny black shoe.
static func _tp_leg_mesh() -> ArrayMesh:
	if _cache.has("tp_leg"):
		return _cache.tp_leg
	var b := MeshBatch.new()
	b.cylinder(Vector3(0, 0.05, 0), Vector3(0, -0.34, 0), 0.095, 0.085, NAVY, FABRIC, 14)
	b.ellipsoid(Vector3(0.1, 0.065, 0.15), _xf(Vector3(0, -0.36, -0.045)), SHOE, GLOSS, 16, 8)
	_cache.tp_leg = b.commit()
	return _cache.tp_leg


# --- Helpers -----------------------------------------------------------------------------

static func _xf(pos: Vector3, rot := Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot), pos)


static func _mesh_node(parent: Node3D, mesh: Mesh, shadows: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
