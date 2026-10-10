extends RigidBody3D
## A blocky person: passenger, flight attendant or the captain.
##
## The host simulates behaviour (sitting, walking, panicking, ragdolling) and
## broadcasts state changes and speech bubbles through `world.object_event`.
## Every peer animates the body locally from the current state.
## Origin is at the feet; the body faces -Z like the seats.

enum State { SEATED, WALK, PANIC, RAGDOLL, CARRIED, OUT }

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
const GRABBED := ["PUT ME DOWN!", "This is NOT in the brochure!", "Unhand me!", "Wheee?",
	"I paid for this seat!", "Personal space! PERSONAL SPACE!"]
const THROWN := ["WAAAAAH!", "I'M FLYIIING!", "YEET—", "NOT AGAIN!"]
const OUCH := ["OW! I'm suing!", "Rude!", "My glasses!", "I'll write a review about this!", "...ow."]
const STAND := ["I'm OK!", "Nothing broken! ...probably.", "Who did that?!", "*dizzy noises*"]
const MUMBLES := ["mmh... more fish...", "...pull up... pull... pudding...", "zzz... cleared for... nap...",
	"...mother? is that you...?", "...the cockpit is lava...", "...autopilot... auto... potato...",
	"*snore* ...landing... gear... spaghetti..."]
const CALM := ["Is the fish good?", "My ears just popped.", "Ooh, clouds.", "Are we there yet?",
	"I'm only here for the peanuts.", "*loud chewing*", "Can I recline? I'm reclining."]

const WALK_SPEED := 1.6
const RUN_SPEED := 3.4
const MOVE_ACCEL := 6.0       ## Max self-propulsion (m/s^2); steep tilts still win.
const RAGDOLL_TIME := 3.0
const HIT_SPEED := 6.5        ## Relative speed of an incoming body that knocks someone over.
const BUBBLE_TIME := 2.6

var world: World
var role := "passenger"
var display := "Passenger"
var seat := Vector3.ZERO      ## Plane-local seat point (cushion height).
var home := Vector3.ZERO      ## Plane-local standing spot (attendant).
var panic := 0.0
var bravery := 1.0
var state := State.WALK

var _extra := {}
var _size := 1.0
var _shape: CollisionShape3D
var _vis: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _mouth: MeshInstance3D
var _bubble: Label3D
var _bubble_t := 0.0
var _anim_t := 0.0
var _last_pos := Vector3.ZERO
var _speed_vis := 0.0
var _timer := 0.0             ## Ragdoll/wake countdown (host).
var _scream_t := 0.0
var _target := Vector3.ZERO   ## Plane-local walk target (host).
var _stuck_t := 0.0
var _yaw := 0.0


func _init(w: World, p_role: String, extra: Dictionary) -> void:
	world = w
	role = p_role
	_extra = extra
	display = extra.get("name", "Passenger")
	seat = extra.get("seat", Vector3.ZERO)
	home = extra.get("home", Vector3.ZERO)
	bravery = extra.get("bravery", 1.0)
	state = int(extra.get("state", State.WALK)) as State
	_size = extra.get("size", 1.0)


func _ready() -> void:
	add_to_group("npc")
	add_to_group("grabbable")
	collision_layer = Layers.NPC
	collision_mask = Layers.WORLD | Layers.PLAYER | Layers.PROP | Layers.NPC
	mass = 60.0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	physics_material_override = pm
	angular_damp = 1.0
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5 * float(_extra.get("width", 1.0)), 1.8, 0.4) * _size
	_shape.shape = box
	_shape.position.y = 0.92 * _size
	add_child(_shape)
	_build_body()
	if world.is_server():
		_build_hitbox()
		_enter_physics(state)
		_scream_t = randf_range(1.0, 4.0)
		_timer = randf_range(8.0, 20.0)
	_last_pos = global_position


# --- Visuals -----------------------------------------------------------------------------
# Meshes and materials are cached per shape/colour and shared by every NPC.

static var _mats := {}
static var _meshes := {}


static func _mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f" % [c.to_html(), rough, metal]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]


static func _sphere(r: float) -> Mesh:
	var key := "s%.3f" % r
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 16
		m.rings = 8
		_meshes[key] = m
	return _meshes[key]


static func _capsule(r: float, h: float) -> Mesh:
	var key := "c%.3f/%.3f" % [r, h]
	if not _meshes.has(key):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = h
		m.radial_segments = 14
		m.rings = 4
		_meshes[key] = m
	return _meshes[key]


static func _cyl(top: float, bottom: float, h: float) -> Mesh:
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


static func _torus(inner: float, outer: float) -> Mesh:
	var key := "t%.3f/%.3f" % [inner, outer]
	if not _meshes.has(key):
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 16
		m.ring_segments = 8
		_meshes[key] = m
	return _meshes[key]


static func _box(size: Vector3) -> Mesh:
	var key := "b%v" % size
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func _prism(size: Vector3) -> Mesh:
	var key := "p%v" % size
	if not _meshes.has(key):
		var m := PrismMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


func _part(mesh: Mesh, pos: Vector3, c: Color, parent: Node3D, rot := Vector3.ZERO, scl := Vector3.ONE,
		rough := 0.85, metal := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c, rough, metal)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _build_body() -> void:
	var shirt: Color = _extra.get("shirt", Color.WHITE)
	var skin: Color = _extra.get("skin", SKIN[0])
	var pants: Color = _extra.get("pants", Color(0.2, 0.22, 0.3))
	var hair: Color = _extra.get("hair", HAIR[0])
	var shoes: Color = _extra.get("shoes", Color(0.12, 0.1, 0.1))
	var w: float = _extra.get("width", 1.0)
	var belly := w > 1.2
	var front := -0.17 * w - (0.06 if belly else 0.0)   ## Chest surface z.
	_vis = Node3D.new()
	_vis.scale = Vector3.ONE * _size
	add_child(_vis)
	# Torso, hips, belt, neck.
	_part(_capsule(0.25, 0.72), Vector3(0, 1.18, 0), shirt, _vis, Vector3.ZERO, Vector3(w, 1, 0.68 * w))
	if belly:
		_part(_sphere(0.5), Vector3(0, 1.04, -0.06), shirt, _vis, Vector3.ZERO, Vector3(0.42 * w, 0.4, 0.34 * w))
	_part(_sphere(0.5), Vector3(0, 0.86, 0), pants, _vis, Vector3.ZERO, Vector3(0.44 * w, 0.24, 0.3 * w))
	_part(_cyl(0.255, 0.255, 0.06), Vector3(0, 0.9, 0), Color(0.25, 0.15, 0.08), _vis, Vector3.ZERO,
		Vector3(w, 1, 0.7 * w + (0.15 if belly else 0.0)))
	_part(_box(Vector3(0.07, 0.05, 0.02)), Vector3(0, 0.9, -0.18 * w - (0.04 if belly else 0.0)),
		Color(1.0, 0.82, 0.3), _vis, Vector3.ZERO, Vector3.ONE, 0.3, 0.8)
	_part(_cyl(0.07, 0.08, 0.14), Vector3(0, 1.52, 0), skin, _vis)
	var tie: bool = _extra.get("tie", false) or role == "captain"
	if tie:
		var tc: Color = Color(0.08, 0.08, 0.1) if role == "captain" else _extra.get("tie_color", Color(0.8, 0.1, 0.15))
		_part(_sphere(0.035), Vector3(0, 1.45, front - 0.01), tc, _vis)
		_part(_prism(Vector3(0.1, 0.32, 0.02)), Vector3(0, 1.27, front - 0.01), tc, _vis, Vector3(0, 0, PI))
	elif role == "passenger":
		for i in 3:
			_part(_sphere(0.018), Vector3(0, 1.38 - i * 0.13, front - 0.005), shirt.lightened(0.5), _vis)
	if _extra.get("necklace", false):
		_part(_torus(0.085, 0.1), Vector3(0, 1.47, -0.02), Color(1.0, 0.85, 0.3), _vis, Vector3(0.35, 0, 0),
			Vector3.ONE, 0.25, 0.9)
	# Head with face.
	var head := Node3D.new()
	head.position.y = 1.74
	_vis.add_child(head)
	_part(_sphere(0.21), Vector3.ZERO, skin, head, Vector3.ZERO, Vector3(1, 1.08, 1))
	for sx in [-1.0, 1.0]:
		_part(_sphere(0.05), Vector3(sx * 0.205, 0.0, 0.01), skin, head, Vector3.ZERO, Vector3(0.6, 1, 1))
		_part(_sphere(0.045), Vector3(sx * 0.075, 0.04, -0.17), Color(0.98, 0.98, 0.98), head, Vector3.ZERO,
			Vector3.ONE, 0.3)
		_part(_sphere(0.024), Vector3(sx * 0.075, 0.04, -0.208), Color(0.05, 0.05, 0.08), head, Vector3.ZERO,
			Vector3.ONE, 0.2)
		var tilt: float = _extra.get("brow", 0.15)
		_part(_box(Vector3(0.09, 0.022, 0.02)), Vector3(sx * 0.075, 0.105, -0.19), hair.darkened(0.2), head,
			Vector3(0, 0, -sx * tilt))
	_part(_sphere(0.045), Vector3(0, -0.02, -0.21), skin.darkened(0.08), head, Vector3.ZERO, Vector3(1, 1, 1.25))
	_mouth = _part(_sphere(0.5), Vector3(0, -0.1, -0.188), Color(0.45, 0.08, 0.1), head, Vector3.ZERO,
		Vector3(0.1, 0.03, 0.03))
	if _extra.get("stache", false) or role == "captain":
		_part(_capsule(0.025, 0.15), Vector3(0, -0.062, -0.205), hair.darkened(0.15), head, Vector3(0, 0, PI / 2))
	var hat := int(_extra.get("hat", 0))
	var style := int(_extra.get("style", 0))
	if role != "passenger" or hat != 0:
		style = 5 if role == "attendant" else (7 if style == 7 else 0)
	_build_hair(head, hair, style)
	_build_hat(head, hat)
	if _extra.get("glasses", false):
		var gc: Color = _extra.get("glasses_color", Color(0.1, 0.1, 0.1))
		for sx in [-1.0, 1.0]:
			_part(_torus(0.034, 0.048), Vector3(sx * 0.075, 0.04, -0.205), gc, head, Vector3(PI / 2, 0, 0),
				Vector3.ONE, 0.3, 0.4)
			_part(_box(Vector3(0.012, 0.012, 0.2)), Vector3(sx * 0.122, 0.045, -0.105), gc, head)
		_part(_box(Vector3(0.05, 0.012, 0.012)), Vector3(0, 0.045, -0.21), gc, head)
	if _extra.get("phones", false):
		var pc := Color(0.15, 0.15, 0.18)
		_part(_box(Vector3(0.46, 0.03, 0.05)), Vector3(0, 0.25, 0.0), pc, head, Vector3.ZERO, Vector3.ONE, 0.4)
		for sx in [-1.0, 1.0]:
			_part(_box(Vector3(0.03, 0.24, 0.05)), Vector3(sx * 0.225, 0.13, 0.0), pc, head, Vector3.ZERO, Vector3.ONE, 0.4)
			_part(_cyl(0.06, 0.06, 0.05), Vector3(sx * 0.225, 0.0, 0.0), Color(0.95, 0.3, 0.3), head,
				Vector3(0, 0, PI / 2), Vector3.ONE, 0.4)
	match role:
		"captain":
			for sx in [-1.0, 1.0]:
				_part(_box(Vector3(0.13, 0.03, 0.14)), Vector3(sx * 0.22 * w, 1.5, 0), Color(0.08, 0.1, 0.25), _vis)
				for i in 3:
					_part(_box(Vector3(0.02, 0.035, 0.145)), Vector3(sx * (0.18 + i * 0.03) * w, 1.5, 0),
						Color(1.0, 0.82, 0.25), _vis, Vector3.ZERO, Vector3.ONE, 0.3, 0.8)
			_part(_box(Vector3(0.1, 0.03, 0.01)), Vector3(0.12 * w, 1.36, front + 0.02), Color(1.0, 0.82, 0.25),
				_vis, Vector3.ZERO, Vector3.ONE, 0.3, 0.8)
		"attendant":
			_part(_torus(0.07, 0.11), Vector3(0, 1.49, -0.01), Color(0.9, 0.15, 0.2), _vis, Vector3(0.25, 0, 0))
			_part(_prism(Vector3(0.12, 0.12, 0.03)), Vector3(0.05, 1.38, front - 0.01), Color(0.9, 0.15, 0.2), _vis,
				Vector3(0, 0, PI))
			_part(_box(Vector3(0.11, 0.04, 0.01)), Vector3(-0.12 * w, 1.33, front + 0.02), Color(0.98, 0.98, 0.98), _vis)
	# Legs.
	var leg_root := Node3D.new()
	leg_root.position.y = 0.82
	_vis.add_child(leg_root)
	for sx in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position.x = sx * 0.12 * w
		leg_root.add_child(leg)
		_part(_capsule(0.1 + 0.02 * (w - 1.0), 0.8), Vector3(0, -0.38, 0), pants, leg)
		_part(_capsule(0.08, 0.3), Vector3(0, -0.77, -0.05), shoes, leg, Vector3(PI / 2, 0, 0), Vector3(1.1, 1, 0.8), 0.5)
		_legs.append(leg)
	# Arms: sleeve, forearm, hand.
	for sx in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(sx * (0.25 * w + 0.07), 1.43, 0)
		_vis.add_child(arm)
		_part(_capsule(0.085, 0.38), Vector3(0, -0.15, 0), shirt, arm)
		_part(_capsule(0.065, 0.34), Vector3(0, -0.42, 0), skin, arm)
		_part(_sphere(0.072), Vector3(0, -0.6, 0), skin, arm)
		_arms.append(arm)
		if sx < 0.0 and _extra.get("bag", false):
			var bc: Color = _extra.get("bag_color", Color(0.6, 0.2, 0.4))
			_part(_box(Vector3(0.08, 0.2, 0.26)), Vector3(-0.06, -0.72, 0), bc, arm, Vector3.ZERO, Vector3.ONE, 0.5)
			_part(_torus(0.07, 0.085), Vector3(-0.06, -0.6, 0), bc.darkened(0.3), arm, Vector3(0, 0, PI / 2))
			_part(_box(Vector3(0.085, 0.03, 0.06)), Vector3(-0.06, -0.66, 0), Color(1.0, 0.82, 0.3), arm,
				Vector3.ZERO, Vector3.ONE, 0.3, 0.8)
	_bubble = Label3D.new()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.position.y = 2.3 * _size
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


func _build_hair(head: Node3D, c: Color, style: int) -> void:
	match style:
		0:  # Short crop.
			_part(_sphere(0.222), Vector3(0, 0.07, 0.02), c, head, Vector3.ZERO, Vector3(1, 0.62, 1))
		1:  # Towering bouffant.
			_part(_sphere(0.26), Vector3(0, 0.17, 0.05), c, head)
			_part(_sphere(0.17), Vector3(0, 0.38, 0.05), c, head)
		2:  # Bald with clown tufts.
			for sx in [-1.0, 1.0]:
				_part(_sphere(0.085), Vector3(sx * 0.2, 0.06, 0.05), c, head, Vector3.ZERO, Vector3(1, 0.9, 1.3))
		3:  # Mohawk.
			_part(_capsule(0.045, 0.42), Vector3(0, 0.2, 0.03), c, head, Vector3(PI / 2, 0, 0), Vector3(1, 1, 1.9))
		4:  # Bob with a fringe.
			_part(_sphere(0.23), Vector3(0, 0.09, 0.03), c, head, Vector3.ZERO, Vector3(1.05, 0.68, 1.02))
			_part(_sphere(0.21), Vector3(0, -0.02, 0.09), c, head, Vector3.ZERO, Vector3(1.06, 0.95, 0.65))
			for sx in [-1.0, 1.0]:
				_part(_capsule(0.06, 0.3), Vector3(sx * 0.19, -0.04, 0.03), c, head)
		5:  # Neat bun.
			_part(_sphere(0.222), Vector3(0, 0.07, 0.02), c, head, Vector3.ZERO, Vector3(1, 0.62, 1))
			_part(_sphere(0.09), Vector3(0, 0.2, 0.15), c, head)
		6:  # Enormous afro.
			_part(_sphere(0.29), Vector3(0, 0.16, 0.12), c, head)
		_:  # Ponytail.
			_part(_sphere(0.222), Vector3(0, 0.07, 0.02), c, head, Vector3.ZERO, Vector3(1, 0.62, 1))
			_part(_capsule(0.055, 0.32), Vector3(0, -0.02, 0.25), c, head, Vector3(0.5, 0, 0))


func _build_hat(head: Node3D, hat: int) -> void:
	var hc: Color = _extra.get("hat_color", Color(0.9, 0.2, 0.2))
	match role:
		"captain":
			var navy := Color(0.08, 0.1, 0.25)
			_part(_cyl(0.235, 0.215, 0.1), Vector3(0, 0.22, 0.01), navy, head)
			_part(_cyl(0.218, 0.218, 0.03), Vector3(0, 0.185, 0.01), Color(1.0, 0.82, 0.25), head, Vector3.ZERO,
				Vector3.ONE, 0.3, 0.8)
			_part(_cyl(0.14, 0.14, 0.02), Vector3(0, 0.165, -0.17), Color(0.03, 0.03, 0.05), head, Vector3(0.2, 0, 0),
				Vector3(1, 1, 0.7), 0.2)
			_part(_sphere(0.035), Vector3(0, 0.23, -0.225), Color(1.0, 0.82, 0.25), head, Vector3.ZERO,
				Vector3(1.3, 1, 0.5), 0.3, 0.8)
		"attendant":
			_part(_cyl(0.1, 0.1, 0.08), Vector3(0.06, 0.22, 0.0), Color(0.9, 0.15, 0.2), head, Vector3(0, 0, -0.2))
		_:
			match hat:
				1:  # Baseball cap.
					_part(_sphere(0.226), Vector3(0, 0.08, 0.01), hc, head, Vector3.ZERO, Vector3(1, 0.6, 1))
					_part(_cyl(0.13, 0.13, 0.02), Vector3(0, 0.1, -0.2), hc.darkened(0.2), head, Vector3.ZERO,
						Vector3(1, 1, 1.15))
					_part(_sphere(0.025), Vector3(0, 0.215, 0.0), hc.darkened(0.2), head)
				2:  # Top hat.
					_part(_cyl(0.15, 0.15, 0.3), Vector3(0, 0.33, 0.0), Color(0.08, 0.08, 0.08), head, Vector3.ZERO,
						Vector3.ONE, 0.4)
					_part(_cyl(0.152, 0.152, 0.05), Vector3(0, 0.22, 0.0), hc, head)
					_part(_cyl(0.26, 0.26, 0.02), Vector3(0, 0.19, 0.0), Color(0.08, 0.08, 0.08), head)
				3:  # Bobble beanie.
					_part(_sphere(0.228), Vector3(0, 0.08, 0.01), hc, head, Vector3.ZERO, Vector3(1, 0.75, 1))
					_part(_torus(0.2, 0.235), Vector3(0, 0.04, 0.01), hc.lightened(0.3), head)
					_part(_sphere(0.06), Vector3(0, 0.27, 0.01), Color(0.98, 0.98, 0.98), head)
				4:  # Floppy sun hat.
					_part(_sphere(0.226), Vector3(0, 0.08, 0.01), hc, head, Vector3.ZERO, Vector3(1, 0.65, 1))
					_part(_cyl(0.36, 0.38, 0.02), Vector3(0, 0.1, 0.01), hc, head, Vector3(0.08, 0, 0))
					_part(_cyl(0.23, 0.23, 0.04), Vector3(0, 0.13, 0.01), Color(0.3, 0.2, 0.1), head)


func _build_hitbox() -> void:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = Layers.PROP | Layers.NPC
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = (_shape.shape as BoxShape3D).size + Vector3(0.2, 0.1, 0.2)
	cs.shape = box
	cs.position = _shape.position
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_hit)


func _process(dt: float) -> void:
	_anim_t += dt
	var moved := global_position - _last_pos
	_last_pos = global_position
	_speed_vis = lerpf(_speed_vis, Vector2(moved.x, moved.z).length() / maxf(dt, 0.001), clampf(dt * 8.0, 0.0, 1.0))
	if _bubble.visible:
		_bubble_t -= dt
		if _bubble_t <= 0.0:
			_bubble.visible = false
	var k := clampf(dt * 12.0, 0.0, 1.0)
	var leg_x := 0.0
	var arm_x := 0.0
	var arm_z := 0.0
	var body_y := 0.0
	var mouth := 1.0
	match state:
		State.SEATED:
			leg_x = PI / 2
			body_y = 0.47 - 0.82 * _size
			arm_x = 0.5 if role == "captain" else 0.25
		State.PANIC:
			var t := _anim_t * 16.0
			leg_x = sin(t * 0.8) * 0.7
			arm_x = PI + sin(t) * 0.7
			arm_z = 0.4 + sin(t * 1.3) * 0.4
			mouth = 4.0
		State.RAGDOLL, State.CARRIED:
			leg_x = sin(_anim_t * 9.0) * 0.4
			arm_x = 2.4
			arm_z = 1.0 + sin(_anim_t * 11.0) * 0.5
			mouth = 3.5
		State.OUT:
			leg_x = 0.15
			arm_z = 1.3
			mouth = 2.0
		_:
			var swing := sin(_anim_t * 9.0) * clampf(_speed_vis / WALK_SPEED, 0.0, 1.0) * 0.6
			leg_x = swing
			arm_x = -swing
	for i in 2:
		var sgn := -1.0 if i == 0 else 1.0
		_legs[i].rotation.x = lerp_angle(_legs[i].rotation.x, leg_x * (sgn if state != State.SEATED else 1.0), k)
		_legs[i].rotation.z = lerp_angle(_legs[i].rotation.z, sgn * (0.35 if state == State.OUT else 0.0), k)
		var ax := arm_x * (sgn if state == State.WALK else 1.0)
		if state == State.PANIC:
			ax = PI + sin(_anim_t * 16.0 + i * 2.0) * 0.8
		_arms[i].rotation.x = lerp_angle(_arms[i].rotation.x, ax, k)
		_arms[i].rotation.z = lerp_angle(_arms[i].rotation.z, sgn * arm_z, k)
	_vis.position.y = lerpf(_vis.position.y, body_y, k)
	var talk := 1.0 + 0.4 * sin(_anim_t * 25.0) if mouth > 1.5 else 1.0
	_mouth.scale.y = lerpf(_mouth.scale.y, 0.03 * mouth * talk, k)


## Shows a speech bubble over the head (all peers).
func show_bubble(text: String) -> void:
	_bubble.text = text
	_bubble.visible = true
	_bubble_t = BUBBLE_TIME + text.length() * 0.03


func on_net_event(event: String, args: Array) -> void:
	match event:
		"say":
			show_bubble(args[0])
		"state":
			state = int(args[0]) as State


func get_prompt() -> String:
	if role == "captain":
		return "Grab the Captain [E]  Slap [LMB]" if state == State.OUT else "Grab the Captain [E]"
	if role == "attendant":
		return "Grab the flight attendant [E]  Punch [LMB]"
	return "Grab %s [E]  Punch [LMB]" % display


func get_spawn_extra() -> Dictionary:
	var e := _extra.duplicate()
	e["state"] = state
	return e


# --- Host behaviour ---------------------------------------------------------------------

## Host. Says a line in a speech bubble on every peer.
func say_line(text: String) -> void:
	world.object_event(World.net_id(self), "say", [text])


## Host. Raises panic (scaled by this person's bravery).
func add_panic(amount: float) -> void:
	if role == "captain":
		return
	panic = clampf(panic + amount / bravery, 0.0, 1.5)


func _set_state(s: State) -> void:
	if s == state:
		return
	_enter_physics(s)
	world.object_event(World.net_id(self), "state", [s])


func _enter_physics(s: State) -> void:
	state = s
	match s:
		State.SEATED:
			freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			freeze = true
			lock_rotation = true
		State.WALK, State.PANIC:
			freeze = false
			_stand_upright()
			_pick_target()
		State.RAGDOLL, State.CARRIED, State.OUT:
			freeze = false
			lock_rotation = false


func _stand_upright() -> void:
	var was_tipped := not lock_rotation
	lock_rotation = true
	angular_velocity = Vector3.ZERO
	if was_tipped:
		global_transform = Transform3D(Basis(Vector3.UP, _yaw), global_position + Vector3(0, 0.15, 0))


func _physics_process(dt: float) -> void:
	if not world.is_server():
		return
	var plane := world.plane
	match state:
		State.SEATED:
			global_transform = plane.global_transform * Transform3D(Basis(), seat - Vector3(0, 0.45, 0))
			if panic > 0.65 and role == "passenger":
				_get_up()
		State.WALK:
			if role == "captain":
				_timer -= dt
				if _timer <= 0.0:
					knock_out()
			else:
				_walk(dt, WALK_SPEED)
				if panic > 0.65:
					_set_state(State.PANIC)
		State.PANIC:
			_walk(dt, RUN_SPEED)
			_scream_t -= dt
			if _scream_t <= 0.0:
				_scream_t = randf_range(2.5, 6.0)
				say_line(SCREAMS.pick_random())
			if panic < 0.2:
				_set_state(State.WALK)
		State.RAGDOLL:
			_timer -= dt
			if _timer <= 0.0 and linear_velocity.length() < 2.0:
				say_line(STAND.pick_random())
				_set_state(State.PANIC if panic > 0.5 else State.WALK)
		State.OUT:
			_timer -= dt
			if _timer <= 0.0:
				_timer = randf_range(12.0, 25.0)
				say_line(MUMBLES.pick_random())
	panic = maxf(0.0, panic - 0.03 * dt)


func _get_up() -> void:
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), world.plane.to_global(Vector3(0, 0.1, seat.z)))
	_set_state(State.PANIC)


func _pick_target() -> void:
	_stuck_t = 0.0
	var aisle: Array[Vector3] = world.plane.aisle_points
	if state == State.PANIC:
		_target = aisle[randi() % aisle.size()]
	elif role == "passenger":
		_target = Vector3(0, 0, seat.z)
	else:
		_target = home


## Steers toward `_target` in the plane's floor frame with limited force, so tilts still slide us.
func _walk(dt: float, speed: float) -> void:
	var plane := world.plane
	var local := plane.to_local(global_position)
	var to := Vector3(_target.x - local.x, 0, _target.z - local.z)
	var dist := to.length()
	var want := Vector3.ZERO
	if dist < 0.35:
		if state == State.PANIC:
			_pick_target()
		elif role == "passenger":
			if randf() < 0.3:
				say_line(CALM.pick_random())
			_set_state(State.SEATED)
			return
		elif role == "attendant":
			_yaw = PI
	else:
		want = plane.global_basis * (to / dist * speed)
		_yaw = atan2(-want.x, -want.z)
	var up := plane.global_basis.y
	var vh := linear_velocity - up * linear_velocity.dot(up)
	apply_central_force(((want - vh) * 8.0).limit_length(MOVE_ACCEL) * mass)
	global_basis = Basis(Vector3.UP, _yaw)
	if dist >= 0.35 and vh.length() < 0.3:
		_stuck_t += dt
		if _stuck_t > 2.5:
			if state == State.PANIC:
				_pick_target()
			else:
				_stuck_t = 0.0
				apply_central_impulse(Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1)) * mass)
	else:
		_stuck_t = 0.0


## Host. Knocks this person over for a few seconds (the captain just stays down).
func ragdoll(impulse: Vector3, duration := RAGDOLL_TIME) -> void:
	add_panic(0.25)
	if state == State.OUT:
		apply_central_impulse(impulse)
		return
	if state == State.SEATED:
		global_position += world.plane.global_basis.y * 0.3
	_set_state(State.RAGDOLL)
	_timer = duration
	apply_central_impulse(impulse)
	angular_velocity = Vector3(randf_range(-5, 5), randf_range(-3, 3), randf_range(-5, 5))


## Host. The captain faints (first time: from the pilot seat onto the cockpit floor).
func knock_out() -> void:
	var was_seated := state == State.SEATED
	_timer = randf_range(6.0, 12.0)
	_set_state(State.OUT)
	if was_seated:
		global_transform = world.plane.global_transform * Transform3D(Basis(Vector3.RIGHT, PI / 2),
			Vector3(-1.4, 0.3, -13.0))
	else:
		angular_velocity = Vector3(randf_range(-1, 1), 0, randf_range(3, 4))


## Host. The captain briefly comes round, says something, then faints again.
func wake_up(line: String) -> void:
	if state != State.OUT:
		return
	_set_state(State.WALK)
	_timer = 4.5
	say_line(line)


func _on_hit(body: Node3D) -> void:
	var rb := body as RigidBody3D
	if rb == null or rb == self or state == State.CARRIED:
		return
	var rel := rb.linear_velocity - linear_velocity
	if rel.length() < HIT_SPEED or world.holders.values().has(World.net_id(rb)):
		return
	say_line(OUCH.pick_random())
	ragdoll(rel.normalized() * minf(rb.mass, 30.0) * 4.0 + Vector3(0, 60, 0))


func can_grab(_peer: int) -> bool:
	return true


func on_grabbed(_peer: int) -> void:
	add_panic(0.3)
	say_line(GRABBED.pick_random())
	if state == State.OUT:
		return
	_set_state(State.CARRIED)


func on_released() -> void:
	if state == State.CARRIED:
		_set_state(State.RAGDOLL)
		_timer = 1.5


func on_thrown(_peer: int) -> void:
	say_line(THROWN.pick_random() if role != "captain" else "...wheee... zzz...")
	if state == State.RAGDOLL:
		_timer = RAGDOLL_TIME


func on_punched(_peer: int, dir: Vector3) -> void:
	if role == "captain" and state == State.OUT:
		say_line("...five more minutes...")
		return
	say_line(OUCH.pick_random())
	ragdoll(dir * 120.0 + Vector3(0, 80, 0))


func on_lost() -> void:
	match role:
		"captain":
			world.say("", "The captain has left the plane. Like, physically.", 3.0)
		"attendant":
			world.say("", "The flight attendant has exited the aircraft. Service is suspended.", 3.0)
		_:
			world.say(display, "WHEEEEEEEEEEEEEEE—", 2.5)
