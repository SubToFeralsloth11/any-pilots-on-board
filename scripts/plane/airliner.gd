class_name Airliner
extends AnimatableBody3D
## The airliner, built from boxes. It sits at the world origin and only pitches/rolls;
## the outside world moves past it. Tilting it is what makes everything inside slide.
##
## Local axes: -Z = nose, +X = right wing, floor top at y = 0.
## Cockpit z -14..-10 | cabin z -10..6 | cargo hold z 6..16 (rear ramp at z = 16).
## Mutable state (windows, doors, ramp, engine fires, gear) changes only through
## apply_change(key, value); the host broadcasts keys via World.set_plane().

const LAYER_WORLD := 1
const HALF_W := 2.0          ## Inner half width.
const CEIL := 2.8
const NOSE_Z := -14.0
const TAIL_Z := 16.0
const GEAR_HEIGHT := 1.5     ## Floor height above the ground when the wheels touch.
const ROW_Z := [-8.5, -7.0, -5.5, -4.0, -2.5, 2.0, 3.5, 5.0]
const SEAT_X := [-1.45, -0.85, 0.85, 1.45]
const EXIT_GAP := Vector2(-0.6, 0.6)
const ENGINE_POS := [Vector3(-6, -1.0, -0.8), Vector3(6, -1.0, -0.8)]
const PILOT_SEAT := Vector3(-0.6, 0.5, -12.6)
const COPILOT_SEAT := Vector3(0.6, 0.5, -12.6)
## Cargo hold floor area for crates: x/z bounds.
const CARGO_MIN := Vector3(-1.7, 0.0, 7.0)
const CARGO_MAX := Vector3(1.7, 0.0, 15.2)
const SUCTION_BURST := 26.0
const SUCTION_STEADY := 5.0
const SUCTION_RANGE := 3.5

var windows: Array[Dictionary] = []   ## {mesh, shape, broken, pos, broke_at}
var doors := {}                        ## name -> {mesh, shape, open, area, closed_xf}
var ramp_open := false
var engine_fire := [false, false]
var gear_down := false
var airborne := true                   ## World sets this; suction only while flying.
var seats: Array[Vector3] = []         ## Passenger seat points (local, sitting height).
var seat_areas: Array[Interactable] = []
var aisle_points: Array[Vector3] = []  ## Walkable points down the aisle (local).
var pilot_area: Interactable

var _mats := {}
var _ramp_shape: CollisionShape3D
var _ramp_mesh: MeshInstance3D
var _ramp_lever: Interactable
var _gear_meshes: Array[MeshInstance3D] = []
var _fires: Array[Node3D] = []


func _ready() -> void:
	collision_layer = LAYER_WORLD
	collision_mask = 0
	sync_to_physics = true
	_build_hull()
	_build_walls()
	_build_cockpit()
	_build_cabin()
	_build_cargo()
	_build_wings()
	_build_tail_and_gear()
	_build_lights()
	set_gear(false)


# --- Public queries ---------------------------------------------------------------

func is_outside(global_p: Vector3) -> bool:
	var p := to_local(global_p)
	return absf(p.x) > HALF_W + 0.05 or p.y < -0.6 or p.y > CEIL + 0.1 or p.z < NOSE_Z or p.z > TAIL_Z + 0.2


## Acceleration pulling things toward broken windows / open doors while airborne.
func get_suction(global_p: Vector3) -> Vector3:
	if not airborne:
		return Vector3.ZERO
	var total := Vector3.ZERO
	var now := Time.get_ticks_msec() / 1000.0
	for w in windows:
		if w.broken:
			var strength := SUCTION_BURST if now - float(w.broke_at) < 3.0 else SUCTION_STEADY
			total += _pull(global_p, to_global(w.pos), strength, SUCTION_RANGE)
	for door_name in ["left", "right"]:
		if doors[door_name].open:
			total += _pull(global_p, to_global(doors[door_name].pos), SUCTION_STEADY * 1.4, SUCTION_RANGE)
	if ramp_open:
		total += _pull(global_p, to_global(Vector3(0, 1.0, TAIL_Z + 1.0)), SUCTION_STEADY, 6.0)
	return total


func _pull(from: Vector3, to: Vector3, strength: float, reach: float) -> Vector3:
	var d := to - from
	var dist := d.length()
	if dist > reach or dist < 0.01:
		return Vector3.ZERO
	return d / dist * strength * (1.0 - dist / reach)


## Window index for a collision shape index on this body (from raycasts/contacts), or -1.
func window_for_shape(shape_index: int) -> int:
	var owner_id := shape_find_owner(shape_index)
	var node := shape_owner_get_owner(owner_id) as Node
	return int(node.get_meta("window", -1)) if node else -1


func engine_near(global_p: Vector3, reach := 3.0) -> int:
	for i in 2:
		if to_global(ENGINE_POS[i] + Vector3(0, 0.9, 0)).distance_to(global_p) <= reach:
			return i
	return -1


func engine_fire_point(i: int) -> Vector3:
	return to_global(ENGINE_POS[i] + Vector3(0, 0.9, 0))


func window_near(global_p: Vector3, reach := 1.6) -> int:
	var best := -1
	var best_d := reach
	for i in windows.size():
		var d := to_global(windows[i].pos).distance_to(global_p)
		if d < best_d:
			best_d = d
			best = i
	return best


# --- State changes (all peers) -------------------------------------------------------

func get_state() -> Dictionary:
	var s := {"ramp": ramp_open, "gear": gear_down, "fire:0": engine_fire[0], "fire:1": engine_fire[1]}
	for i in windows.size():
		s["window:%d" % i] = windows[i].broken
	for n in doors:
		s["door:" + n] = doors[n].open
	return s


func apply_state(s: Dictionary) -> void:
	for k in s:
		apply_change(k, s[k])


func apply_change(key: String, value: bool) -> void:
	var parts := key.split(":")
	match parts[0]:
		"window":
			set_window_broken(int(parts[1]), value)
		"door":
			set_door(parts[1], value)
		"ramp":
			set_ramp(value)
		"fire":
			set_engine_fire(int(parts[1]), value)
		"gear":
			set_gear(value)


func set_window_broken(i: int, broken: bool) -> void:
	var w: Dictionary = windows[i]
	if w.broken == broken:
		return
	w.broken = broken
	w.broke_at = Time.get_ticks_msec() / 1000.0
	w.shape.set_deferred("disabled", broken)
	w.mesh.visible = not broken
	if broken:
		_burst(to_global(w.pos), Color(0.7, 0.9, 1.0, 0.8))
	else:
		w.mesh.material_override = _mat(Color(0.82, 0.8, 0.7))   # Duct-taped over.


func set_door(door_name: String, open: bool) -> void:
	var d: Dictionary = doors[door_name]
	d.open = open
	d.shape.set_deferred("disabled", open)
	d.mesh.visible = not open
	d.area.prompt = ("Close" if open else "Open") + " " + d.label + " [E]"


func set_ramp(open: bool) -> void:
	ramp_open = open
	var xf := _ramp_transform(open)
	_ramp_shape.transform = xf
	_ramp_mesh.transform = xf
	_ramp_lever.prompt = ("Close" if open else "Open") + " the cargo ramp [E]"


func set_engine_fire(i: int, on: bool) -> void:
	engine_fire[i] = on
	_fires[i].visible = on
	(_fires[i].get_child(0) as CPUParticles3D).emitting = on


func set_gear(down: bool) -> void:
	gear_down = down
	for m in _gear_meshes:
		m.visible = down


func set_attitude(pitch: float, roll: float) -> void:
	transform = Transform3D(Basis.from_euler(Vector3(pitch, 0.0, -roll)), Vector3.ZERO)


# --- Construction --------------------------------------------------------------------

func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.8
		if c.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.1
		_mats[key] = m
	return _mats[key]


## Adds a box mesh (and collision unless collide=false). Returns the mesh; the shape is in meta "shape".
func _box(size: Vector3, center: Vector3, color: Color, collide := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(color)
	mi.mesh = bm
	mi.position = center
	add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = center
		add_child(cs)
		mi.set_meta("shape", cs)
	return mi


func _cyl(radius: float, length: float, center: Vector3, axis: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.material = _mat(color)
	mi.mesh = cm
	mi.position = center
	if axis == Vector3.FORWARD:
		mi.rotation.x = PI / 2
	elif axis == Vector3.RIGHT:
		mi.rotation.z = PI / 2
	add_child(mi)
	return mi


func _label(text: String, pos: Vector3, size := 48, color := Color.WHITE, yaw := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 8
	l.position = pos
	l.rotation.y = yaw
	add_child(l)
	return l


## Splits [a, b] by removing gap intervals.
static func spans(a: float, b: float, gaps: Array) -> Array[Vector2]:
	var out: Array[Vector2] = [Vector2(a, b)]
	for g: Vector2 in gaps:
		var next: Array[Vector2] = []
		for s in out:
			if g.y <= s.x or g.x >= s.y:
				next.append(s)
				continue
			if g.x > s.x:
				next.append(Vector2(s.x, g.x))
			if g.y < s.y:
				next.append(Vector2(g.y, s.y))
		out = next
	return out


const HULL := Color(0.93, 0.94, 0.96)
const TRIM := Color(0.15, 0.35, 0.75)
const CARPET := Color(0.22, 0.25, 0.42)
const SEAT := Color(0.2, 0.4, 0.85)
const GLASS := Color(0.55, 0.8, 1.0, 0.35)


func _build_hull() -> void:
	var length := TAIL_Z - NOSE_Z
	var mid := (TAIL_Z + NOSE_Z) / 2.0
	_box(Vector3(4.2, 0.2, length), Vector3(0, -0.1, mid), CARPET)
	_box(Vector3(4.4, 1.2, length), Vector3(0, -0.8, mid), HULL)
	_box(Vector3(4.4, 0.2, length), Vector3(0, CEIL + 0.1, mid), HULL)
	_box(Vector3(3.4, 0.35, length - 1.0), Vector3(0, CEIL + 0.37, mid - 0.5), HULL, false)
	# Blue stripe along both sides.
	for sx in [-1, 1]:
		_box(Vector3(0.02, 0.25, length), Vector3(sx * 2.21, 0.9, mid), TRIM, false)
	# Nose cone.
	_box(Vector3(3.8, 2.6, 1.6), Vector3(0, 0.6, NOSE_Z - 0.9), HULL)
	_box(Vector3(2.6, 1.8, 1.0), Vector3(0, 0.3, NOSE_Z - 2.0), HULL)
	_box(Vector3(1.4, 1.0, 0.6), Vector3(0, 0.1, NOSE_Z - 2.7), Color(0.2, 0.2, 0.22), false)


func _build_walls() -> void:
	var window_zs: Array = ROW_Z.duplicate()
	window_zs.append(-12.2)   # Cockpit side windows.
	for sx in [-1, 1]:
		var x: float = sx * (HALF_W + 0.1)
		var door_gap := [EXIT_GAP]
		for s in spans(NOSE_Z, TAIL_Z, door_gap):
			_box(Vector3(0.2, 1.1, s.y - s.x), Vector3(x, 0.55, (s.x + s.y) / 2), HULL)
			_box(Vector3(0.2, 0.3, s.y - s.x), Vector3(x, 1.95, (s.x + s.y) / 2), HULL)
		_box(Vector3(0.2, 0.7, TAIL_Z - NOSE_Z), Vector3(x, 2.45, (TAIL_Z + NOSE_Z) / 2), HULL)
		# Window band y 1.1..1.8 with glass panes.
		var gaps := [EXIT_GAP]
		for wz: float in window_zs:
			var half := 0.6 if wz < -10.0 else 0.35
			gaps.append(Vector2(wz - half, wz + half))
		for s in spans(NOSE_Z, TAIL_Z, gaps):
			_box(Vector3(0.2, 0.7, s.y - s.x), Vector3(x, 1.45, (s.x + s.y) / 2), HULL)
		for wz: float in window_zs:
			var w := 1.2 if wz < -10.0 else 0.7
			_add_window(Vector3(0.08, 0.7, w), Vector3(x, 1.45, wz))
		# Over-wing emergency exit door.
		var door_name := "left" if sx < 0 else "right"
		var dm := _box(Vector3(0.16, 2.1, 1.2), Vector3(x, 1.05, 0), Color(0.85, 0.3, 0.25))
		var area := Interactable.make(Vector3(0.8, 2.0, 1.2), "", "door", [door_name])
		area.position = Vector3(sx * 1.75, 1.0, 0)
		add_child(area)
		doors[door_name] = {"mesh": dm, "shape": dm.get_meta("shape"), "open": false, "area": area,
			"label": "the emergency exit", "pos": Vector3(x, 1.0, 0)}
		set_door(door_name, false)
		_label("EXIT", Vector3(sx * 1.95, 2.35, 0), 64, Color(1, 0.25, 0.2), -sx * PI / 2)
	# Front wall with windshield.
	var fz := NOSE_Z - 0.1
	_box(Vector3(4.4, 1.2, 0.2), Vector3(0, 0.6, fz), HULL)
	_box(Vector3(4.4, 0.6, 0.2), Vector3(0, 2.5, fz), HULL)
	for px in [-1.85, 1.85]:
		_box(Vector3(0.5, 1.0, 0.2), Vector3(px, 1.7, fz), HULL)
	_box(Vector3(0.16, 1.0, 0.2), Vector3(0, 1.7, fz), HULL)
	for px in [-0.84, 0.84]:
		_add_window(Vector3(1.52, 1.0, 0.08), Vector3(px, 1.7, fz))


func _add_window(size: Vector3, pos: Vector3) -> void:
	var m := _box(size, pos, GLASS)
	var shape: CollisionShape3D = m.get_meta("shape")
	shape.set_meta("window", windows.size())
	windows.append({"mesh": m, "shape": shape, "broken": false, "pos": pos, "broke_at": -100.0})


func _bulkhead(z: float, gap_half: float, gap_h: float, color: Color) -> void:
	var side := HALF_W - gap_half
	for sx in [-1, 1]:
		_box(Vector3(side, CEIL, 0.15), Vector3(sx * (gap_half + side / 2), CEIL / 2, z), color)
	_box(Vector3(gap_half * 2, CEIL - gap_h, 0.15), Vector3(0, (CEIL + gap_h) / 2, z), color)


func _build_cockpit() -> void:
	_bulkhead(-10.0, 0.55, 2.1, Color(0.8, 0.78, 0.72))
	var dm := _box(Vector3(1.1, 2.1, 0.1), Vector3(0, 1.05, -10.0), Color(0.55, 0.5, 0.45))
	var area := Interactable.make(Vector3(1.1, 2.0, 1.6), "", "door", ["cockpit"])
	area.position = Vector3(0, 1.0, -10.0)
	add_child(area)
	doors["cockpit"] = {"mesh": dm, "shape": dm.get_meta("shape"), "open": false, "area": area,
		"label": "the cockpit door", "pos": Vector3(0, 1.0, -10.0)}
	set_door("cockpit", false)
	_label("CREW ONLY", Vector3(0, 2.3, -9.9), 40, Color(1, 0.9, 0.3), 0.0)
	# Dashboard with blinking-looking screens.
	_box(Vector3(3.6, 1.0, 0.7), Vector3(0, 0.5, -13.55), Color(0.18, 0.18, 0.2))
	_box(Vector3(3.6, 0.25, 0.5), Vector3(0, 1.1, -13.7), Color(0.12, 0.12, 0.14))
	for i in 5:
		var sx := -1.4 + i * 0.7
		_box(Vector3(0.5, 0.3, 0.02), Vector3(sx, 0.85, -13.19), Color(0.1, 0.6 + 0.08 * i, 0.3), false)
	_box(Vector3(0.6, 0.12, 0.25), Vector3(0, 1.0, -13.3), Color(0.8, 0.2, 0.2), false)
	_label("DO NOT\nPRESS", Vector3(0, 1.08, -13.17), 22, Color.WHITE)
	# Seats + yokes.
	for p: Vector3 in [PILOT_SEAT, COPILOT_SEAT]:
		_box(Vector3(0.6, 0.5, 0.6), Vector3(p.x, 0.25, p.z), Color(0.3, 0.25, 0.2))
		_box(Vector3(0.6, 1.0, 0.12), Vector3(p.x, 0.95, p.z + 0.32), Color(0.3, 0.25, 0.2))
		_box(Vector3(0.4, 0.06, 0.06), Vector3(p.x, 0.95, p.z - 0.7), Color(0.1, 0.1, 0.1), false)
		_box(Vector3(0.06, 0.4, 0.06), Vector3(p.x, 0.75, p.z - 0.75), Color(0.1, 0.1, 0.1), false)
	pilot_area = Interactable.make(Vector3(0.7, 1.2, 0.8), "Fly the plane (you totally can) [E]", "pilot_enter")
	pilot_area.position = PILOT_SEAT + Vector3(0, 0.3, 0)
	add_child(pilot_area)
	var co := Interactable.make(Vector3(0.7, 1.2, 0.8), "Sit in the co-pilot seat [E]", "sit")
	co.local_only = true
	co.set_meta("seat", COPILOT_SEAT)
	co.position = COPILOT_SEAT + Vector3(0, 0.3, 0)
	add_child(co)
	seat_areas.append(co)


func _build_cabin() -> void:
	for z: float in ROW_Z:
		for x: float in SEAT_X:
			_box(Vector3(0.5, 0.45, 0.5), Vector3(x, 0.225, z), SEAT)
			_box(Vector3(0.5, 0.85, 0.12), Vector3(x, 0.85, z + 0.27), SEAT)
			_box(Vector3(0.44, 0.2, 0.08), Vector3(x, 1.18, z + 0.25), Color(0.9, 0.9, 0.9), false)
			var seat := Vector3(x, 0.5, z)
			seats.append(seat)
			var area := Interactable.make(Vector3(0.45, 0.5, 0.45), "Sit down [E]", "sit")
			area.local_only = true
			area.set_meta("seat", seat)
			area.position = seat + Vector3(0, 0.15, 0)
			add_child(area)
			seat_areas.append(area)
		_label(str(ROW_Z.find(z) + 1), Vector3(-1.98, 2.15, z), 32, Color(0.2, 0.2, 0.2), PI / 2)
	for i in 16:
		aisle_points.append(Vector3(0, 0.0, -9.5 + i))
	# Overhead bins (visual).
	for sx in [-1, 1]:
		_box(Vector3(0.6, 0.45, 15.5), Vector3(sx * 1.7, 2.55, -2.0), Color(0.88, 0.88, 0.86), false)
	_label("PLEASE REMAIN SEATED", Vector3(0, 2.4, -9.92), 30, Color(0.9, 0.9, 0.9))


func _build_cargo() -> void:
	_bulkhead(6.0, 0.8, 2.3, Color(0.45, 0.45, 0.42))
	_label("CARGO", Vector3(0, 2.5, 5.92), 48, Color(1, 0.85, 0.2), PI)
	_label("CARGO", Vector3(0, 2.5, 6.08), 48, Color(1, 0.85, 0.2))
	# Hold floor stripes.
	for i in 4:
		_box(Vector3(4.0, 0.01, 0.3), Vector3(0, 0.005, 7.5 + i * 2.5), Color(0.9, 0.75, 0.1), false)
	# Rear ramp.
	_ramp_mesh = _box(Vector3(4.2, 2.8, 0.15), Vector3.ZERO, Color(0.55, 0.57, 0.6))
	_ramp_shape = _ramp_mesh.get_meta("shape")
	_ramp_lever = Interactable.make(Vector3(0.5, 0.8, 0.5), "", "ramp")
	_ramp_lever.position = Vector3(1.75, 1.2, 14.5)
	add_child(_ramp_lever)
	_box(Vector3(0.12, 0.6, 0.12), Vector3(1.9, 1.2, 14.5), Color(0.8, 0.1, 0.1), false)
	_label("RAMP", Vector3(1.97, 1.7, 14.5), 32, Color(1, 0.3, 0.3), -PI / 2)
	set_ramp(false)


func _ramp_transform(open: bool) -> Transform3D:
	var hinge := Vector3(0, 0, TAIL_Z + 0.08)
	var angle := deg_to_rad(110.0) if open else 0.0
	var b := Basis(Vector3.RIGHT, angle)
	return Transform3D(b, hinge + b * Vector3(0, 1.4, 0))


func _build_wings() -> void:
	for sx in [-1, 1]:
		_box(Vector3(11.9, 0.3, 4.0), Vector3(sx * 8.05, -0.25, 0.5), HULL)
		_box(Vector3(11.9, 0.04, 0.25), Vector3(sx * 8.05, -0.08, -1.4), TRIM, false)
		_box(Vector3(0.4, 0.35, 0.5), Vector3(sx * 14.0, -0.1, 0.5), Color(1, 0.1, 0.1) if sx < 0 else Color(0.1, 1, 0.2), false)
		_label("NO STEP", Vector3(sx * 4.5, -0.08, 1.8), 64, Color(0.2, 0.2, 0.2))
		var i := 0 if sx < 0 else 1
		var ep: Vector3 = ENGINE_POS[i]
		_cyl(0.7, 3.2, ep, Vector3.FORWARD, Color(0.75, 0.76, 0.8))
		_cyl(0.55, 0.05, ep + Vector3(0, 0, -1.62), Vector3.FORWARD, Color(0.1, 0.1, 0.12))
		_box(Vector3(1.4, 1.4, 3.2), ep, HULL, false).visible = false
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.4, 1.4, 3.2)
		cs.shape = bs
		cs.position = ep
		add_child(cs)
		_box(Vector3(0.3, 0.5, 1.2), ep + Vector3(0, 0.7, 0.3), HULL, false)
		_fires.append(_make_fire(ep + Vector3(0, 0.9, 0)))
		# Handles to hang on to on the wing.
		_box(Vector3(0.08, 0.08, 0.6), Vector3(sx * 3.0, 0.05, 1.5), Color(0.9, 0.8, 0.1), false)


func _make_fire(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	var p := CPUParticles3D.new()
	var qm := BoxMesh.new()
	qm.size = Vector3(0.35, 0.35, 0.35)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1.0, 0.45, 0.05)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.35, 0.0)
	fm.emission_energy_multiplier = 3.0
	fm.vertex_color_use_as_albedo = true
	qm.material = fm
	p.mesh = qm
	p.amount = 40
	p.lifetime = 0.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	p.direction = Vector3(0, 1, 0.6)
	p.spread = 25.0
	p.gravity = Vector3(0, 2, 6)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.9, 0.3))
	grad.set_color(1, Color(0.25, 0.22, 0.2, 0.0))
	p.color_ramp = grad
	p.emitting = false
	root.add_child(p)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.5, 0.1)
	light.light_energy = 3.0
	light.omni_range = 6.0
	root.add_child(light)
	root.visible = false
	add_child(root)
	return root


func _build_tail_and_gear() -> void:
	_box(Vector3(0.25, 3.4, 3.0), Vector3(0, 4.5, 14.4), HULL)
	_box(Vector3(0.27, 1.0, 1.6), Vector3(0, 5.2, 14.9), TRIM, false)
	_box(Vector3(8.0, 0.2, 2.0), Vector3(0, 3.2, 15.0), HULL)
	for p: Vector3 in [Vector3(0, -1.2, -11), Vector3(-1.6, -1.2, 1.5), Vector3(1.6, -1.2, 1.5)]:
		var wheel := _cyl(0.3, 0.35, p, Vector3.RIGHT, Color(0.08, 0.08, 0.08))
		_gear_meshes.append(wheel)
		var strut := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.12, 0.4, 0.12)
		sm.material = _mat(Color(0.6, 0.6, 0.6))
		strut.mesh = sm
		strut.position = p + Vector3(0, 0.3, 0)
		add_child(strut)
		_gear_meshes.append(strut)


func _build_lights() -> void:
	for z in [-12.0, -7.0, -1.0, 4.0, 10.0, 14.0]:
		var l := OmniLight3D.new()
		l.position = Vector3(0, 2.5, z)
		l.light_color = Color(1.0, 0.95, 0.85)
		l.light_energy = 1.2
		l.omni_range = 6.0
		add_child(l)


## Cosmetic shard burst (all peers).
func _burst(at: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.06, 0.06, 0.02)
	m.material = _mat(color)
	p.mesh = m
	p.one_shot = true
	p.amount = 24
	p.lifetime = 1.2
	p.explosiveness = 1.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.spread = 180.0
	p.gravity = Vector3(0, -9.8, 4)
	get_parent().add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
