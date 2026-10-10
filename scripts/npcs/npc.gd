extends RigidBody3D
## A ragdoll person: passenger, flight attendant or the captain.
##
## The root body is the torso. Nine limb bodies (head, upper arms, forearms, thighs, shins)
## are top_level children returned by get_net_parts(). While seated, standing or walking the
## limbs are posed locally on every peer from the synced state and are taken out of the
## physics space entirely (a head shape on the root stands in for them), so calm people cost
## one body each. When hit, grabbed, thrown, sucked out of a seat or knocked out, the host
## puts the limbs back, joins them to the torso with Generic6DOFJoint3D and the rig goes limp;
## World then streams every limb to clients (net_parts_active() is true). Recovering people
## get up in two stages (crouch, then stand) and walk to their own seat.
## Seated people lean and sway with the felt gravity (host, replicated through the root).
## The root origin is the torso centre; the body faces -Z like the seats.

enum State { SEATED, STAND, WALK, RAGDOLL, CARRIED, OUT }
enum React { NONE, FLAIL, CLUTCH, PRAY, COVER, PHONE, BOUNCE }

const NpcLook := preload("res://scripts/npcs/npc_look.gd")

const SKIN := [Color(0.98, 0.84, 0.7), Color(0.87, 0.67, 0.5), Color(0.66, 0.46, 0.32),
	Color(0.45, 0.3, 0.2), Color(1.0, 0.75, 0.62)]
const SHIRTS := [Color(0.95, 0.3, 0.3), Color(0.3, 0.6, 1.0), Color(0.4, 0.9, 0.4), Color(1.0, 0.85, 0.2),
	Color(0.8, 0.4, 0.95), Color(1.0, 0.55, 0.15), Color(0.25, 0.9, 0.85), Color(1.0, 0.45, 0.75),
	Color(0.95, 0.95, 0.95), Color(0.55, 0.35, 0.2)]
const HAIR := [Color(0.1, 0.07, 0.05), Color(0.45, 0.25, 0.1), Color(0.95, 0.8, 0.35),
	Color(0.85, 0.3, 0.1), Color(0.85, 0.85, 0.85), Color(0.3, 0.5, 1.0), Color(1.0, 0.4, 0.7)]
const NAMES := ["Gary", "Brenda", "Kevin", "Doris", "Chad", "Linda", "Barry", "Gertrude", "Todd",
	"Karen", "Nigel", "Mildred", "Dwayne", "Agnes", "Steve", "Beryl", "Hank", "Penelope", "Duncan",
	"Shirley", "Clive", "Bernadette", "Marvin", "Dot"]

const SCREAMS := ["WE'RE ALL GONNA DIE!", "I LEFT THE OVEN ON!", "MOMMY!", "I want a REFUND!",
	"Tell my cat I love her!", "Is this covered by insurance?!", "WHO'S FLYING THIS THING?!",
	"AAAAAAAAAA", "I'm too pretty to crash!", "NOT THE FACE!", "I KNEW I should've taken the bus!",
	"Does this count as a layover?!", "I regret EVERYTHING!", "Where's the EXIT?!", "*incoherent honking*"]
const REACT_LINES := {React.PRAY: "Dear Lord, I'll never skip leg day again...",
	React.COVER: "If I can't see it, it isn't happening!", React.PHONE: "Going LIVE! Smash that like button!",
	React.CLUTCH: "I'm holding the plane up with my ARMS!", React.BOUNCE: "WHEE— no, wait— AAAA!",
	React.FLAIL: "AAAAAAAAAAAAAA"}
const SUCKED := ["NOT THE WINDOW!", "I'M BEING VACUUMED!", "My seatbelt was DECORATIVE?!"]
const GRABBED := ["PUT ME DOWN!", "This is NOT in the brochure!", "Unhand me!", "Wheee?",
	"I paid for this seat!", "Personal space! PERSONAL SPACE!"]
const THROWN := ["WAAAAAH!", "I'M FLYIIING!", "YEET—", "NOT AGAIN!"]
const OUCH := ["OW! I'm suing!", "Rude!", "My glasses!", "I'll write a review about this!", "...ow."]
const STAND_UP := ["I'm OK!", "Nothing broken! ...probably.", "Who did that?!", "*dizzy noises*",
	"Back to my seat. With DIGNITY."]
const MUMBLES := ["mmh... more fish...", "...pull up... pull... pudding...", "zzz... cleared for... nap...",
	"...mother? is that you...?", "...the cockpit is lava...", "...autopilot... auto... potato...",
	"*snore* ...landing... gear... spaghetti..."]
const CALM := ["Is the fish good?", "My ears just popped.", "Ooh, clouds.", "Are we there yet?",
	"I'm only here for the peanuts.", "*loud chewing*", "Can I recline? I'm reclining."]

## Limb indices in get_net_parts() order.
const HEAD := 0
const ARM_L := 1
const FORE_L := 2
const ARM_R := 3
const FORE_R := 4
const THIGH_L := 5
const SHIN_L := 6
const THIGH_R := 7
const SHIN_R := 8
const LIMBS := 9
## Roughly human mass fractions of a ~60 kg person (the torso root is TORSO_MASS).
const LIMB_MASS := [4.5, 2.0, 1.5, 2.0, 1.5, 6.0, 4.0, 6.0, 4.0]
const TORSO_MASS := 26.0

const FEET := 1.19            ## Feet below the torso centre (unit size).
const SEAT_LIFT := 0.33       ## Torso centre above the seat point (unit size).
const WALK_SPEED := 1.5
const MOVE_ACCEL := 6.0       ## Max self-propulsion (m/s^2); steep tilts still win.
const STRIDE := 4.3           ## Gait phase per metre walked (feet plant instead of sliding).
const RAGDOLL_TIME := 3.0
const RELEASE_TIME := 2.5
const BLEND_TIME := 0.6
const CROUCH_DROP := 0.5      ## Root drop while crouching on the way up (unit size).
const HIT_SPEED := 6.5        ## Relative speed of an incoming body that knocks someone over.
const SUCK_LIMIT := 10.0      ## Suction (m/s^2) that rips someone out of their seat.
const BUBBLE_TIME := 2.6
const THINK_EVERY := 3        ## Host AI (panic, suction) runs every Nth physics frame, staggered.
const ROW_FRONT := 0.62       ## Standing spot in front of a seat (toward the nose).
const AISLE_HALF := 0.9       ## |x| below this counts as the aisle.
const LEAN_MAX := 0.32        ## Max seated lean (rad).
const LEAN_GAIN := 0.55       ## Fraction of the felt-gravity tilt a seated body follows.


## One ragdoll limb. Forwards prompts and punches to its person.
class Part extends RigidBody3D:
	var npc: Node

	func get_prompt() -> String:
		return npc.get_prompt()

	func on_punched(peer: int, dir: Vector3) -> void:
		npc.on_punched(peer, dir)


var world: World
var role := "passenger"
var display := "Passenger"
var seat := Vector3.ZERO      ## Plane-local seat point (cushion height).
var home := Vector3.ZERO      ## Plane-local standing spot (attendant, captain while awake).
var panic := 0.0
var bravery := 1.0
var state := State.SEATED
var react := React.NONE
var scared := false

var _extra := {}
var _size := 1.0
var _width := 1.0
var _look: NpcLook
var _parts: Array[RigidBody3D] = []
var _joints: Array[Generic6DOFJoint3D] = []
var _joint_parent: Array[int] = []      ## Parent limb per joint (-1 = torso).
var _joint_child: Array[int] = []
var _joints_on := false
var _active := false                    ## Limbs simulated by physics (streamed by World).
var _limbs_physical := true             ## Limb bodies currently in the physics space.
var _unconscious := false               ## Captain after the blackout.
var _legs_shape: CollisionShape3D
var _head_shape: CollisionShape3D       ## Stands in for the head while the limbs are posed.
var _belt: Node3D
var _bubble: Label3D
var _bubble_t := 0.0
var _anim_t := 0.0
var _phase := 0.0
var _gait := 0.0
var _pose := {}
var _tgt := {}                          ## Reused target-pose buffer.
var _xf_buf: Array[Transform3D] = []    ## Reused limb-transform buffer.
var _last_pos := Vector3.ZERO
var _speed_vis := 0.0
var _timer := 0.0
var _scream_t := 0.0
var _react_t := 0.0
var _stuck_t := 0.0
var _hop_t := 0.0
var _yaw := 0.0
var _blend_t := -1.0
var _blend_getup := false               ## First (crouch) stage of getting up.
var _blend_pose := {}
var _grace := 1.5                       ## Host: ignores hits while spawned props settle.
var _blend_from: Array[Transform3D] = []
var _blend_root := Transform3D()
var _think := 0
var _think_dt := 0.0
var _lean := Vector2.ZERO               ## Seated lean: x = roll (about -Z), y = pitch (about X).
var _lean_v := Vector2.ZERO


func _init(w: World, p_role: String, extra: Dictionary) -> void:
	world = w
	role = p_role
	_extra = extra
	display = extra.get("name", "Passenger")
	seat = extra.get("seat", Vector3.ZERO)
	home = extra.get("home", Vector3.ZERO)
	bravery = extra.get("bravery", 1.0)
	state = int(extra.get("state", State.SEATED)) as State
	react = int(extra.get("react", React.NONE)) as React
	scared = extra.get("scared", false)
	_active = extra.get("active", false)
	_unconscious = extra.get("unconscious", false)
	_yaw = extra.get("yaw", 0.0)
	_size = extra.get("size", 1.0)
	_width = extra.get("width", 1.0)
	_phase = randf() * 100.0
	_think = randi() % THINK_EVERY
	_look = NpcLook.new(extra, role)
	_xf_buf.resize(LIMBS)


func _ready() -> void:
	add_to_group("npc")
	add_to_group("grabbable")
	collision_layer = Layers.NPC
	collision_mask = Layers.WORLD | Layers.PLAYER | Layers.PROP | Layers.NPC
	mass = TORSO_MASS
	angular_damp = 2.0
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.05
	physics_material_override = pm
	var s := _size
	var torso := CollisionShape3D.new()
	var tb := BoxShape3D.new()
	tb.size = Vector3(0.46 * _width, 0.74, 0.3 * _width) * s
	torso.shape = tb
	add_child(torso)
	_legs_shape = CollisionShape3D.new()
	var lc := CapsuleShape3D.new()
	lc.radius = 0.17 * s
	lc.height = (FEET - 0.25) * s
	_legs_shape.shape = lc
	_legs_shape.position.y = -(FEET + 0.25) * 0.5 * s
	add_child(_legs_shape)
	_head_shape = CollisionShape3D.new()
	var hs := SphereShape3D.new()
	hs.radius = 0.21 * s
	_head_shape.shape = hs
	_head_shape.position = _neck() + Vector3(0, 0.2 * s, 0)
	add_child(_head_shape)
	var vis := Node3D.new()
	vis.scale = Vector3.ONE * s
	add_child(vis)
	_look.build_torso(vis)
	_belt = _look.build_seatbelt(vis)
	_build_limbs()
	_build_bubble()
	_pose = _target_pose().duplicate()
	if world.is_server():
		_build_joints()
		_build_hitbox()
		_scream_t = randf_range(1.0, 4.0)
		_timer = randf_range(12.0, 25.0)
		_apply_physics()
	call_deferred("_place_limbs")


# --- Construction ------------------------------------------------------------------------

func _build_limbs() -> void:
	var s := _size
	var id: int = get_meta("net_id", 0)
	var radii := [0.0, 0.075, 0.065, 0.075, 0.065, 0.1, 0.09, 0.1, 0.09]
	var lengths := [0.0, 0.34, 0.4, 0.34, 0.4, 0.48, 0.48, 0.48, 0.48]
	for i in LIMBS:
		var p := Part.new()
		p.npc = self
		p.top_level = true
		p.collision_layer = Layers.NPC
		p.collision_mask = collision_mask
		p.mass = LIMB_MASS[i] * s * s * s
		p.angular_damp = 3.5
		p.linear_damp = 0.05
		p.continuous_cd = true
		p.physics_material_override = physics_material_override
		p.set_meta("net_id", id)
		p.add_to_group("grabbable")
		# Out of the physics space until posed (see _sync_limb_physics).
		p.process_mode = Node.PROCESS_MODE_DISABLED
		var cs := CollisionShape3D.new()
		if i == HEAD:
			var sp := SphereShape3D.new()
			sp.radius = 0.21 * s
			cs.shape = sp
		else:
			var cap := CapsuleShape3D.new()
			cap.radius = float(radii[i]) * s
			cap.height = float(lengths[i]) * s
			cs.shape = cap
			if i == FORE_L or i == FORE_R or i == SHIN_L or i == SHIN_R:
				cs.position.y = -0.04 * s
		p.add_child(cs)
		var v := Node3D.new()
		v.scale = Vector3.ONE * s
		p.add_child(v)
		match i:
			HEAD:
				_look.build_head(v)
			ARM_L, ARM_R:
				_look.build_upper_arm(v)
			FORE_L, FORE_R:
				_look.build_forearm(v, i == FORE_R)
			THIGH_L, THIGH_R:
				_look.build_thigh(v)
			_:
				_look.build_shin(v)
		add_child(p)
		_parts.append(p)
	_limbs_physical = false
	var bodies: Array[PhysicsBody3D] = [self]
	bodies.append_array(_parts)
	for a in bodies.size():
		for b in range(a + 1, bodies.size()):
			bodies[a].add_collision_exception_with(bodies[b])


func _build_bubble() -> void:
	_bubble = Label3D.new()
	_bubble.top_level = true
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.font_size = 44
	_bubble.outline_size = 14
	_bubble.pixel_size = 0.004
	_bubble.modulate = Color(1, 1, 0.85)
	_bubble.outline_modulate = Color(0.1, 0.05, 0.15)
	_bubble.width = 600.0
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.no_depth_test = true
	_bubble.visible = false
	add_child(_bubble)


## Joints sit at the rest-pose pivots (root-local). Limits are written in pose angles
## (positive x swings a limb forward) and flipped into the joint's convention. Elbows and
## knees are hinges that only bend the natural way; the neck and hips stay within comfort.
func _build_joints() -> void:
	var s := _size
	var specs := [
		[HEAD, -1, _neck(), Vector3(-0.6, -0.9, -0.4), Vector3(0.5, 0.9, 0.4)],
		[ARM_L, -1, _shoulder(-1.0), Vector3(-0.9, -0.5, -2.5), Vector3(2.8, 0.5, 0.25)],
		[FORE_L, ARM_L, _shoulder(-1.0) + Vector3(0, -0.3 * s, 0), Vector3(0, -0.15, 0), Vector3(2.4, 0.15, 0)],
		[ARM_R, -1, _shoulder(1.0), Vector3(-0.9, -0.5, -0.25), Vector3(2.8, 0.5, 2.5)],
		[FORE_R, ARM_R, _shoulder(1.0) + Vector3(0, -0.3 * s, 0), Vector3(0, -0.15, 0), Vector3(2.4, 0.15, 0)],
		[THIGH_L, -1, _hip(-1.0), Vector3(-0.5, -0.35, -0.8), Vector3(1.9, 0.35, 0.15)],
		[SHIN_L, THIGH_L, _hip(-1.0) + Vector3(0, -0.42 * s, 0), Vector3(-2.4, 0, 0), Vector3.ZERO],
		[THIGH_R, -1, _hip(1.0), Vector3(-0.5, -0.35, -0.15), Vector3(1.9, 0.35, 0.8)],
		[SHIN_R, THIGH_R, _hip(1.0) + Vector3(0, -0.42 * s, 0), Vector3(-2.4, 0, 0), Vector3.ZERO],
	]
	for spec: Array in specs:
		var j := Generic6DOFJoint3D.new()
		j.position = spec[2]
		var lo: Vector3 = spec[3]
		var hi: Vector3 = spec[4]
		for a in 3:
			var axis: String = ["x", "y", "z"][a]
			j.set("angular_limit_%s/enabled" % axis, true)
			j.set("angular_limit_%s/lower_angle" % axis, -hi[a])
			j.set("angular_limit_%s/upper_angle" % axis, -lo[a])
		add_child(j)
		_joints.append(j)
		_joint_child.append(spec[0])
		_joint_parent.append(spec[1])


func _build_hitbox() -> void:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = Layers.PROP | Layers.NPC
	area.monitorable = false
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.8 * _width, 1.9, 0.6) * _size
	cs.shape = bx
	cs.position.y = -0.3 * _size
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_hit)


# --- Skeleton ----------------------------------------------------------------------------

func _neck() -> Vector3:
	return Vector3(0, 0.36, 0) * _size


func _shoulder(sx: float) -> Vector3:
	return Vector3(sx * _look.shoulder_x(), 0.28, 0) * _size


func _hip(sx: float) -> Vector3:
	return Vector3(sx * 0.12 * _width, -0.33, 0) * _size


## Root-local transforms of every limb for a pose (written into a reused buffer).
func _limb_xforms(p: Dictionary) -> Array[Transform3D]:
	var s := _size
	var out := _xf_buf
	out[HEAD] = Transform3D(Basis.from_euler(p.head), _neck()) * Transform3D(Basis(), Vector3(0, 0.2 * s, 0))
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var k := "_l" if side == 0 else "_r"
		var sh := Transform3D(Basis.from_euler(p["sh" + k]), _shoulder(sx))
		out[ARM_L + side * 2] = sh * Transform3D(Basis(), Vector3(0, -0.15 * s, 0))
		out[FORE_L + side * 2] = sh * Transform3D(Basis(Vector3.RIGHT, p["el" + k]), Vector3(0, -0.3 * s, 0)) \
			* Transform3D(Basis(), Vector3(0, -0.17 * s, 0))
		var hip := Transform3D(Basis.from_euler(p["hip" + k]), _hip(sx))
		out[THIGH_L + side * 2] = hip * Transform3D(Basis(), Vector3(0, -0.21 * s, 0))
		out[SHIN_L + side * 2] = hip * Transform3D(Basis(Vector3.RIGHT, -float(p["kn" + k])), Vector3(0, -0.42 * s, 0)) \
			* Transform3D(Basis(), Vector3(0, -0.2 * s, 0))
	return out


static func _rest_pose(p := {}) -> Dictionary:
	p.head = Vector3.ZERO
	p.sh_l = Vector3.ZERO
	p.el_l = 0.0
	p.sh_r = Vector3.ZERO
	p.el_r = 0.0
	p.hip_l = Vector3.ZERO
	p.kn_l = 0.0
	p.hip_r = Vector3.ZERO
	p.kn_r = 0.0
	p.lift = 0.0
	return p


## Arms: raise (forward swing), out (sideways, negative = inward), elbow bend, per side.
static func _arms(p: Dictionary, rl: float, ol: float, el: float, rr: float, orr: float, er: float) -> void:
	p.sh_l = Vector3(rl, 0, -ol)
	p.el_l = el
	p.sh_r = Vector3(rr, 0, orr)
	p.el_r = er


static func _legs(p: Dictionary, hl: float, kl: float, hr: float, kr: float, spread := 0.05) -> void:
	p.hip_l = Vector3(hl, 0, -spread)
	p.kn_l = kl
	p.hip_r = Vector3(hr, 0, spread)
	p.kn_r = kr


## Squatting with hands on the knees: the first stage of getting up.
static func _crouch_pose() -> Dictionary:
	var p := _rest_pose()
	_legs(p, 1.75, 2.25, 1.75, 2.25, 0.18)
	_arms(p, 1.0, -0.15, 0.55, 1.0, -0.15, 0.55)
	p.head = Vector3(0.3, 0, 0)
	return p


## The animated pose for the current state and reaction (all peers). Returns a reused buffer.
func _target_pose() -> Dictionary:
	var t := _anim_t + _phase
	var p := _rest_pose(_tgt)
	match state:
		State.SEATED:
			# Shins angled so feet reach the floor; small people's feet dangle.
			_legs(p, PI / 2, 1.4, PI / 2, 1.5, 0.1)
			if role == "captain":
				_arms(p, 1.15, -0.1, 0.35, 1.15, -0.1, 0.35)
			else:
				_arms(p, 0.5, -0.1, 1.0, 0.5, -0.1, 1.0)
				p.head = Vector3(sin(t * 0.4) * 0.08, sin(t * 0.3) * 0.25, 0)
		State.STAND, State.WALK:
			var gait := clampf(_speed_vis / WALK_SPEED, 0.0, 1.2)
			var sw := sin(_gait) * 0.45 * gait
			var lift := absf(cos(_gait)) * gait
			_legs(p, sw, maxf(0.0, -sw) * 1.4 + 0.08 + lift * 0.15, -sw, maxf(0.0, sw) * 1.4 + 0.08 + lift * 0.15)
			if gait > 0.2:
				_arms(p, -sw * 0.9, 0.08, 0.4, sw * 0.9, 0.08, 0.4)
				p.head = Vector3(0.05, 0, sin(_gait) * 0.05)
			else:
				_arms(p, 0.45, -0.35, 1.3, 0.45, -0.35, 1.3)
				p.head = Vector3(0, sin(t * 0.5) * 0.3, 0)
	if scared and (state == State.SEATED or state == State.STAND):
		_react_pose(p, t)
	return p


func _react_pose(p: Dictionary, t: float) -> void:
	var seated := state == State.SEATED
	match react:
		React.FLAIL:
			_arms(p, 2.5 + sin(t * 14.0) * 0.5, 0.4 + sin(t * 11.0) * 0.3, 0.3,
				2.5 + cos(t * 13.0) * 0.5, 0.4 + cos(t * 10.0) * 0.3, 0.3)
			p.head = Vector3(0.2, sin(t * 10.0) * 0.4, 0)
			if seated:
				_legs(p, PI / 2 + sin(t * 12.0) * 0.35, 1.2 + sin(t * 12.0) * 0.4,
					PI / 2 - sin(t * 12.0) * 0.35, 1.2 - sin(t * 12.0) * 0.4, 0.2)
		React.CLUTCH:
			_arms(p, 0.15, 0.6, 0.5, 0.15, 0.6, 0.5)
			p.head = Vector3(-0.1 + sin(t * 30.0) * 0.04, sin(t * 27.0) * 0.05, 0)
			p.lift = sin(t * 40.0) * 0.012
		React.PRAY:
			_arms(p, 1.05, -0.5, 1.75, 1.05, -0.5, 1.75)
			p.head = Vector3(-0.35 + sin(t * 4.0) * 0.1, 0, 0)
		React.COVER:
			_arms(p, 1.4, -0.55, 2.3, 1.4, -0.55, 2.3)
			p.head = Vector3(-0.25, 0, sin(t * 6.0) * 0.15)
		React.PHONE:
			_arms(p, 0.5, -0.12, 0.95, 1.55, 0.05, 0.5)
			p.head = Vector3(-0.1, -0.1 + sin(t * 1.3) * 0.1, 0)
		React.BOUNCE:
			_arms(p, 2.7, 0.6 + sin(t * 9.0) * 0.3, 0.2, 2.7, 0.6 - sin(t * 9.0) * 0.3, 0.2)
			p.head = Vector3(0.25, 0, 0)
			if seated:
				p.lift = absf(sin(t * 9.0)) * 0.12


func _smooth_pose(dt: float) -> void:
	var target := _target_pose()
	var k := clampf(dt * 12.0, 0.0, 1.0)
	for key: String in target:
		var v: Variant = target[key]
		if v is Vector3:
			_pose[key] = (_pose.get(key, v) as Vector3).lerp(v, k)
		else:
			_pose[key] = lerpf(float(_pose.get(key, v)), v, k)


## Snaps the posed limbs onto the current pose around the root.
func _place_limbs() -> void:
	if not is_inside_tree():
		return
	if not _active:
		var xf := _limb_xforms(_pose)
		var root := global_transform
		for i in LIMBS:
			_parts[i].global_transform = root * xf[i]
	_sync_limb_physics()


## Limb bodies only take part in physics while they are simulated or streamed (_active);
## otherwise they are removed from the space and the root's head shape covers the head.
func _sync_limb_physics() -> void:
	if _limbs_physical == _active:
		return
	_limbs_physical = _active
	var mode := Node.PROCESS_MODE_INHERIT if _active else Node.PROCESS_MODE_DISABLED
	for p in _parts:
		p.process_mode = mode
	_head_shape.set_deferred("disabled", _active)


# --- Every peer: cosmetics ---------------------------------------------------------------

func _process(dt: float) -> void:
	_anim_t += dt
	var moved := global_position - _last_pos
	_last_pos = global_position
	var speed := Vector2(moved.x, moved.z).length() / maxf(dt, 0.001)
	if speed > 6.0:
		speed = 0.0   # Teleports and snapshot catch-up are not walking.
	_speed_vis = lerpf(_speed_vis, speed, clampf(dt * 8.0, 0.0, 1.0))
	_gait = fmod(_gait + _speed_vis * dt * STRIDE / maxf(_size, 0.5), TAU)
	if not world.is_server():
		if not _active:
			_smooth_pose(dt)
			_place_limbs()
		else:
			_sync_limb_physics()
	_belt.visible = state == State.SEATED and role == "passenger"
	if _bubble.visible:
		_bubble.global_position = _parts[HEAD].global_position + Vector3(0, 0.5 * _size, 0)
		_bubble_t -= dt
		if _bubble_t <= 0.0:
			_bubble.visible = false
	_look.set_face(_face(), _anim_t, dt, scared and react == React.PHONE and not _active)


func _face() -> NpcLook.Face:
	if state == State.OUT or (_unconscious and state == State.CARRIED):
		return NpcLook.Face.OUT
	if state == State.RAGDOLL:
		return NpcLook.Face.HURT
	if state == State.CARRIED:
		return NpcLook.Face.SCARED
	if scared:
		return NpcLook.Face.CLOSED if react == React.PRAY or react == React.COVER else NpcLook.Face.SCARED
	return NpcLook.Face.CALM


## Shows a speech bubble over the head (all peers).
func show_bubble(text: String) -> void:
	_bubble.text = text
	_bubble.visible = true
	_bubble.global_position = _parts[HEAD].global_position + Vector3(0, 0.5 * _size, 0)
	_bubble_t = BUBBLE_TIME + text.length() * 0.03


func on_net_event(event: String, args: Array) -> void:
	match event:
		"say":
			show_bubble(args[0])
		"state":
			state = int(args[0]) as State
			react = int(args[1]) as React
			scared = args[2]
			_active = args[3]
			_unconscious = args[4]


func get_prompt() -> String:
	if role == "captain":
		return "Grab the Captain [E]  Slap [LMB]" if _unconscious else "Grab the Captain [E]"
	if role == "attendant":
		return "Grab the flight attendant [E]  Punch [LMB]"
	return "Grab %s [E]  Punch [LMB]" % display


func get_spawn_extra() -> Dictionary:
	var e := _extra.duplicate()
	e["state"] = state
	e["react"] = react
	e["scared"] = scared
	e["active"] = _active
	e["unconscious"] = _unconscious
	e["home"] = home
	return e


## Limb bodies, same order on every peer (World syncs them while ragdolling).
func get_net_parts() -> Array[RigidBody3D]:
	return _parts


func net_parts_active() -> bool:
	return _active


# --- Host behaviour ---------------------------------------------------------------------

## Host. Says a line in a speech bubble on every peer.
func say_line(text: String) -> void:
	world.object_event(World.net_id(self), "say", [text])


## Host. Raises panic (scaled by this person's bravery).
func add_panic(amount: float) -> void:
	if role == "captain":
		return
	panic = clampf(panic + amount / bravery, 0.0, 1.5)


func _sync() -> void:
	world.object_event(World.net_id(self), "state", [state, react, scared, _active, _unconscious])


func _set_state(s: State) -> void:
	state = s
	_apply_physics()
	_sync()


## Host. Configures the bodies for the current state.
func _apply_physics() -> void:
	var limp := state == State.RAGDOLL or state == State.CARRIED or state == State.OUT
	if limp:
		_blend_t = -1.0
		_active = true
		_sync_limb_physics()
		if freeze:
			# Kinematic moves would otherwise turn into huge velocities on release.
			freeze = false
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
		lock_rotation = false
		_attach_joints()
		_legs_shape.set_deferred("disabled", true)
		return
	_detach_joints()
	for p in _parts:
		p.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		p.freeze = true
	lock_rotation = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	var was_frozen := freeze
	freeze = state == State.SEATED or _blend_t >= 0.0
	if was_frozen and not freeze:
		linear_velocity = Vector3.ZERO
	_legs_shape.set_deferred("disabled", state == State.SEATED or _blend_t >= 0.0)
	_active = _blend_t >= 0.0
	_sync_limb_physics()


## Joins the limbs to the torso with frames taken from the rest pose, then lets them go.
func _attach_joints() -> void:
	if _joints_on:
		return
	_joints_on = true
	var cur: Array[Transform3D] = []
	for p in _parts:
		cur.append(p.global_transform)
		p.freeze = false
	var rest := _limb_xforms(_rest_pose())
	var root := global_transform
	for i in LIMBS:
		_parts[i].global_transform = root * rest[i]
	for j in _joints.size():
		var parent: Node3D = self if _joint_parent[j] < 0 else _parts[_joint_parent[j]]
		_joints[j].node_a = _joints[j].get_path_to(parent)
		_joints[j].node_b = _joints[j].get_path_to(_parts[_joint_child[j]])
	for i in LIMBS:
		_parts[i].global_transform = cur[i]
		_parts[i].linear_velocity = linear_velocity
		_parts[i].angular_velocity = Vector3.ZERO


func _detach_joints() -> void:
	if not _joints_on:
		return
	_joints_on = false
	for j in _joints:
		j.node_a = NodePath()
		j.node_b = NodePath()


func _physics_process(dt: float) -> void:
	if not world.is_server():
		return
	_grace -= dt
	_think_dt += dt
	var think := (Engine.get_physics_frames() + _think) % THINK_EVERY == 0
	if _blend_t >= 0.0:
		_step_blend(dt)
		return
	match state:
		State.SEATED:
			_update_lean(dt)
			global_transform = _seat_xform()
			if think:
				_check_suction()
		State.STAND:
			_stand(dt)
			if think:
				_check_suction()
		State.WALK:
			_walk_to_seat(dt)
			if think:
				_check_suction()
		State.RAGDOLL:
			_timer -= dt
			if _timer <= 0.0 and linear_velocity.length() < 1.5:
				_recover()
		State.OUT:
			_timer -= dt
			if _timer <= 0.0:
				_timer = randf_range(12.0, 25.0)
				say_line(MUMBLES.pick_random())
	if think:
		_update_panic(_think_dt)
		_think_dt = 0.0
	if not _active:
		_smooth_pose(dt)
		_place_limbs()


func _update_panic(dt: float) -> void:
	panic = maxf(0.0, panic - 0.03 * dt)
	var calm_body := state == State.SEATED or state == State.STAND
	var now := calm_body and (panic > 0.5 or (scared and panic > 0.25))
	if now != scared:
		scared = now
		react = _pick_react() if scared else React.NONE
		_react_t = randf_range(3.0, 6.0)
		_sync()
	if not scared:
		return
	_react_t -= dt
	if _react_t <= 0.0:
		_react_t = randf_range(3.0, 6.0)
		react = _pick_react()
		_sync()
		if randf() < 0.4:
			say_line(REACT_LINES[react])
	_scream_t -= dt
	if _scream_t <= 0.0:
		_scream_t = randf_range(3.0, 7.0)
		say_line(SCREAMS.pick_random())


func _pick_react() -> React:
	var options: Array[React] = [React.FLAIL, React.PRAY, React.COVER, React.CLUTCH]
	if state == State.SEATED:
		options.append_array([React.PHONE, React.BOUNCE])
	options.erase(react)
	return options.pick_random()


## Host. Seated bodies lean with the felt gravity on a springy waist (bigger people sway
## slower), and turbulence bumps jolt them. Clients see it through the synced root.
func _update_lean(dt: float) -> void:
	var g := world.plane.global_basis.inverse() * world.flight.felt_accel
	var down := maxf(-g.y, 1.0)
	var target := Vector2(atan2(g.x, down), atan2(g.z, down)) * LEAN_GAIN
	var stiff := 38.0 / _size
	_lean_v += ((target - _lean) * stiff - _lean_v * 5.5) * dt
	var bump := absf(world.flight.bump)
	if bump > 0.05:
		_lean_v += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * bump * 6.0 * dt
	_lean = (_lean + _lean_v * dt).clamp(-Vector2.ONE * LEAN_MAX, Vector2.ONE * LEAN_MAX)


## Root transform on the seat, leaning about the hips.
func _seat_xform() -> Transform3D:
	var lift := float(_pose.get("lift", 0.0))
	var lean := Basis(Vector3.BACK, -_lean.x) * Basis(Vector3.RIGHT, _lean.y)
	var up := lean * Vector3(0, (SEAT_LIFT + lift) * _size, 0)
	return world.plane.global_transform * Transform3D(lean, seat + up)


## Host. A strong decompression pull rips people out of their seats.
func _check_suction() -> void:
	var suck := world.plane.get_suction(global_position)
	if suck.length() > SUCK_LIMIT:
		say_line(SUCKED.pick_random())
		ragdoll(suck.normalized() * mass * 3.0)


func _stand(dt: float) -> void:
	if role == "captain":
		_timer -= dt
		_steer(Vector3.ZERO, 0.0)
		if _timer <= 0.0:
			knock_out()
		return
	var local := world.plane.to_local(global_position)
	var to := Vector3(home.x - local.x, 0, home.z - local.z)
	if to.length() > 0.4:
		_steer(world.plane.global_basis * to.normalized() * WALK_SPEED * clampf(to.length() * 1.5, 0.4, 1.0), dt)
	else:
		_face_yaw(PI, dt)
		_steer(Vector3.ZERO, dt)
		_hop_t -= dt
		if scared and _hop_t <= 0.0:
			_hop_t = randf_range(0.8, 1.8)
			linear_velocity += world.plane.global_basis.y * 2.5


## Host. Back to the seat: out to the aisle, along it to the seat's row, then sideways
## along the row to stand in front of the seat, and sit down.
func _walk_to_seat(dt: float) -> void:
	var local := world.plane.to_local(global_position)
	var front := Vector3(seat.x, 0, seat.z - ROW_FRONT)
	var off := Vector2(local.x - front.x, local.z - front.z)
	if off.length() < 0.3 or _stuck_t > 6.0:
		_start_blend(State.SEATED)
		return
	var target: Vector3
	if absf(local.z - front.z) < 0.25:
		target = front
	elif absf(local.x) < AISLE_HALF:
		target = Vector3(clampf(local.x, -0.3, 0.3), 0, front.z)
	else:
		target = Vector3(0, 0, local.z)
	var to := Vector3(target.x - local.x, 0, target.z - local.z)
	var slow := clampf(to.length() * 2.0, 0.35, 1.0)
	_steer(world.plane.global_basis * to.normalized() * WALK_SPEED * slow, dt)


## Limited-force steering along the floor (tilts still win) with smoothly turning facing.
func _steer(want: Vector3, dt: float) -> void:
	var up := world.plane.global_basis.y
	var vh := linear_velocity - up * linear_velocity.dot(up)
	apply_central_force(((want - vh) * 8.0).limit_length(MOVE_ACCEL) * mass)
	if want.length() > 0.1:
		_face_yaw(atan2(-want.x, -want.z), dt)
		if vh.length() < 0.3:
			_stuck_t += dt
			if fmod(_stuck_t, 2.0) < dt:
				linear_velocity += up * 3.0
		else:
			_stuck_t = maxf(0.0, _stuck_t - dt)
	global_basis = Basis(Vector3.UP, _yaw)


func _face_yaw(target: float, dt: float) -> void:
	_yaw = lerp_angle(_yaw, target, clampf(dt * 8.0, 0.0, 1.0))


## Host. Gets up from a ragdoll where the body lies.
func _recover() -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.3,
		global_position + Vector3.DOWN * 2.5, Layers.WORLD)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		_timer = 1.0
		return
	var fwd := -global_basis.z
	if absf(fwd.y) > 0.9:
		fwd = global_basis.y
	_yaw = atan2(-fwd.x, -fwd.z)
	say_line(STAND_UP.pick_random())
	_stuck_t = 0.0
	_start_blend(State.WALK if role == "passenger" else State.STAND,
		Transform3D(Basis(Vector3.UP, _yaw), (hit.position as Vector3) + Vector3.UP * FEET * _size))


## Host. Kinematically blends root and limbs from where they are to the target state's pose.
## Getting up from the floor goes through a crouch first.
func _start_blend(target: State, root_target := Transform3D()) -> void:
	var from_floor := state == State.RAGDOLL or state == State.OUT
	_blend_capture()
	_blend_root = root_target
	_blend_t = 0.0
	state = target
	_blend_getup = from_floor and target != State.SEATED
	_speed_vis = 0.0
	_lean = Vector2.ZERO
	_lean_v = Vector2.ZERO
	_pose = (_crouch_pose() if _blend_getup else _target_pose()).duplicate()
	_blend_pose = _pose
	_apply_physics()
	_sync()


func _blend_capture() -> void:
	_blend_from.clear()
	_blend_from.append(global_transform)
	for p in _parts:
		_blend_from.append(p.global_transform)


func _blend_target() -> Transform3D:
	if state == State.SEATED:
		return _seat_xform()
	if _blend_getup:
		var crouch := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, -0.45)
		return Transform3D(crouch, _blend_root.origin + Vector3.DOWN * CROUCH_DROP * _size)
	return _blend_root


func _step_blend(dt: float) -> void:
	_blend_t += dt / BLEND_TIME
	var k := smoothstep(0.0, 1.0, minf(_blend_t, 1.0))
	var root_to := _blend_target()
	global_transform = _blend_from[0].interpolate_with(root_to, k)
	var xf := _limb_xforms(_blend_pose)
	for i in LIMBS:
		_parts[i].global_transform = _blend_from[i + 1].interpolate_with(root_to * xf[i], k)
	if _blend_t < 1.0:
		return
	if _blend_getup:
		# Second stage: push up from the crouch to standing.
		_blend_getup = false
		_blend_capture()
		_blend_t = 0.0
		_pose = _target_pose().duplicate()
		_blend_pose = _pose
		return
	_blend_t = -1.0
	_apply_physics()
	_sync()


## Host. Knocks this person over for `duration` seconds (unconscious people just get shoved).
func ragdoll(impulse: Vector3, duration := RAGDOLL_TIME) -> void:
	add_panic(0.25)
	var from_seat := state == State.SEATED
	if state != State.OUT and state != State.CARRIED:
		_set_state(State.RAGDOLL)
		_timer = duration
	if from_seat:
		_lift_out()
	apply_central_impulse(impulse)
	angular_velocity += Vector3(randf_range(-4, 4), randf_range(-2, 2), randf_range(-4, 4))


## Host. Teleports a freshly limp body (all limbs) up off the seat cushion.
func _lift_out() -> void:
	var up := world.plane.global_basis.y * 0.15
	global_position += up
	for p in _parts:
		p.global_position += up


## Host. The captain faints (from the pilot seat he slumps onto the floor beside it).
func knock_out() -> void:
	_unconscious = true
	var from_seat := state == State.SEATED
	_timer = randf_range(6.0, 12.0)
	_set_state(State.OUT)
	if from_seat:
		_lift_out()
	var side := world.plane.global_basis.x * (-1.0 if seat.x <= 0.0 else 1.0)
	apply_central_impulse((side * 2.5 + world.plane.global_basis.z * 0.5) * mass)
	angular_velocity = world.plane.global_basis.z * randf_range(2.0, 3.0)


## Host. The captain briefly gets up, says something, then faints again.
func wake_up(line: String) -> void:
	if state != State.OUT:
		return
	_unconscious = false
	_recover()
	if state == State.OUT:
		_unconscious = true
		return
	_timer = 4.5 + BLEND_TIME * 2.0
	say_line(line)


func _on_hit(body: Node3D) -> void:
	var rb := body as RigidBody3D
	if rb == null or rb == self or _parts.has(rb) or state == State.CARRIED or _grace > 0.0 or rb.freeze:
		return
	var rel := rb.linear_velocity - (Vector3.ZERO if freeze else linear_velocity)
	if rel.length() < HIT_SPEED or world.holders.values().has(World.net_id(rb)):
		return
	call_deferred("_hit_by", rel.normalized() * minf(rb.mass, 30.0) * 4.0 + Vector3(0, 40, 0))


func _hit_by(impulse: Vector3) -> void:
	say_line(OUCH.pick_random())
	ragdoll(impulse)


func can_grab(_peer: int) -> bool:
	return true


func on_grabbed(_peer: int) -> void:
	add_panic(0.3)
	say_line("...zzz..." if _unconscious else GRABBED.pick_random())
	_set_state(State.CARRIED)


func on_released() -> void:
	if state == State.CARRIED:
		_set_state(State.OUT if _unconscious else State.RAGDOLL)
		_timer = RELEASE_TIME


func on_thrown(_peer: int) -> void:
	say_line("...wheee... zzz..." if _unconscious else THROWN.pick_random())
	for p in _parts:
		p.linear_velocity = linear_velocity
	if state == State.RAGDOLL:
		_timer = RAGDOLL_TIME


func on_punched(_peer: int, dir: Vector3) -> void:
	if _unconscious:
		say_line("...five more minutes...")
		apply_central_impulse(dir * 40.0)
		return
	say_line(OUCH.pick_random())
	ragdoll(dir * 60.0 + Vector3(0, 40, 0))


func on_lost() -> void:
	match role:
		"captain":
			world.say("", "The captain has left the plane. Like, physically.", 3.0)
		"attendant":
			world.say("", "The flight attendant has exited the aircraft. Service is suspended.", 3.0)
		_:
			world.say(display, "WHEEEEEEEEEEEEEEE—", 2.5)
