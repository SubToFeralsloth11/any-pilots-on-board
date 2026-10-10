class_name Airliner
extends AnimatableBody3D
## The airliner. It sits at the world origin and only pitches/rolls; the outside world
## moves past it. Tilting it is what makes everything inside slide.
##
## Local axes: -Z = nose, +X = right wing, floor top at y = 0.
## Cockpit z -14..-10 | cabin -10..6 | lounge 6..12 | cargo hold 12..22 (rear ramp at TAIL_Z).
## Collision is simple invisible boxes; the visible fuselage is a CSG tube with real
## window and door cut-outs. Mutable state (windows, doors, ramp, engine fires, gear)
## changes only through apply_change(key, value); the host broadcasts via World.set_plane().

const LAYER_WORLD := 1
const HALF_W := 2.0          ## Inner half width of the walkable floor.
const CEIL := 2.8
const NOSE_Z := -14.0
const TAIL_Z := 22.0
const GEAR_HEIGHT := 1.5     ## Floor height above the ground when the wheels touch.
const HULL_CY := 1.15        ## Fuselage tube axis height.
const HULL_R := 2.35         ## Outer radius.
const HULL_R_IN := 2.22      ## Inner radius.
const ROW_Z := [-8.5, -7.0, -5.5, -4.0, -2.5, 2.0, 3.5, 5.0]
const LOUNGE_WINDOW_Z := [7.5, 9.0, 10.5]
const SEAT_X := [-1.45, -0.85, 0.85, 1.45]
const EXIT_GAP := Vector2(-0.6, 0.6)
const WINDOW_X := 2.2
const ENGINE_POS := [Vector3(-6, -1.0, -0.8), Vector3(6, -1.0, -0.8)]
const PILOT_SEAT := Vector3(-0.6, 0.5, -12.6)
const COPILOT_SEAT := Vector3(0.6, 0.5, -12.6)
## Lounge floor area (free for furniture): x/z bounds.
const LOUNGE_MIN := Vector3(-1.9, 0.0, 6.2)
const LOUNGE_MAX := Vector3(1.9, 0.0, 11.8)
## Cargo hold floor area for crates: x/z bounds.
const CARGO_MIN := Vector3(-1.7, 0.0, 13.0)
const CARGO_MAX := Vector3(1.7, 0.0, 21.2)
const RAMP_LEVER := Vector3(1.75, 1.2, 20.5)
const SUCTION_BURST := 26.0
const SUCTION_STEADY := 5.0
const SUCTION_RANGE := 3.5
const DAMAGE_PARTS := ["engine0", "engine1", "wing0", "wing1", "tail", "hull"]
const MAX_SCARS := 40

const HULL := Color(0.95, 0.96, 0.98)
const TRIM := Color(0.12, 0.33, 0.78)
const ACCENT := Color(1.0, 0.72, 0.15)
const CABIN_WALL := Color(0.93, 0.9, 0.84)
const CARPET := Color(0.2, 0.24, 0.42)
const RUNNER := Color(0.62, 0.16, 0.2)
const SEAT := Color(0.18, 0.38, 0.85)
const SEAT_DARK := Color(0.12, 0.25, 0.58)
const PLASTIC := Color(0.82, 0.82, 0.8)
const METAL := Color(0.62, 0.64, 0.68)
const DARK := Color(0.14, 0.14, 0.16)
const GLASS := Color(0.55, 0.8, 1.0, 0.3)

var windows: Array[Dictionary] = []   ## {mesh, shape, broken, pos, broke_at}
var doors := {}                        ## name -> {mesh, shape, open, area, label, pos}
var ramp_open := false
var engine_fire := [false, false]
var gear_down := false
var airborne := true                   ## World sets this; suction only while flying.
var seats: Array[Vector3] = []         ## Passenger seat points (local, sitting height).
var seat_areas: Array[Interactable] = []
var aisle_points: Array[Vector3] = []  ## Walkable points down the aisle (local).
var pilot_area: Interactable

var _mats := {}
var _box_meshes := {}
var _ramp_shape: CollisionShape3D
var _ramp_mesh: MeshInstance3D
var _ramp_lever: Interactable
var _gear_meshes: Array[Node3D] = []
var _fires: Array[Node3D] = []
var _hull_csg: CSGCombiner3D
var damage := {}                       ## part -> health 0..1 (1 = intact). See DAMAGE_PARTS.
var _smoke := {}                       ## part -> CPUParticles3D
var _flap_pivots: Array[Node3D] = []
var _flaps := -1
var _scars: Array[Node3D] = []


func _ready() -> void:
	collision_layer = LAYER_WORLD
	collision_mask = 0
	sync_to_physics = true
	_build_fuselage()
	_build_walls()
	_build_cockpit()
	_build_cabin()
	_build_lounge()
	_build_cargo()
	_build_wings()
	_build_tail()
	_build_gear()
	_build_lights()
	_build_smoke()
	set_gear(false)
	set_flaps(0)


# --- Public: fixtures for other modules ------------------------------------------------

## Adds a box to the plane (moves and tilts with it). Collides unless collide=false.
func add_fixture(size: Vector3, center: Vector3, color: Color, collide := true) -> MeshInstance3D:
	return _box(size, center, color, collide)


## Adds a visual-only mesh to the plane.
func add_mesh(mesh: Mesh, xform: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xform
	add_child(mi)
	return mi


func add_area(area: Interactable) -> void:
	add_child(area)


# --- Public queries ---------------------------------------------------------------

func is_outside(global_p: Vector3) -> bool:
	var p := to_local(global_p)
	return absf(p.x) > HALF_W + 0.1 or p.y < -0.6 or p.y > CEIL + 0.1 or p.z < NOSE_Z or p.z > TAIL_Z + 0.2


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
		if engine_fire_point(i).distance_to(global_p) <= reach:
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
		w.mesh.material_override = _mat(Color(0.75, 0.74, 0.68))   # Duct-taped over.


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


## Flap notch 0..2: trailing-edge panels droop.
func set_flaps(notch: int) -> void:
	if notch == _flaps:
		return
	_flaps = notch
	for p in _flap_pivots:
		p.rotation.x = notch * 0.3


## Health 0..1 for a damage part (all peers). Smoke thickens as it drops.
func set_damage(part: String, health: float) -> void:
	damage[part] = health
	var s: CPUParticles3D = _smoke[part]
	s.emitting = health < 0.7
	s.scale_amount_max = lerpf(4.0, 1.5, health)
	s.color = Color(0.12, 0.12, 0.12, 0.8) if health < 0.35 else Color(0.55, 0.55, 0.55, 0.6)


## Which damage part a world point belongs to.
func part_at(global_p: Vector3) -> String:
	var p := to_local(global_p)
	var e := engine_near(global_p, 2.2)
	if e >= 0:
		return "engine%d" % e
	if absf(p.x) > HULL_R + 0.1 and p.y < 1.0:
		return "wing0" if p.x < 0.0 else "wing1"
	if p.z > TAIL_Z - 1.0 and p.y > CEIL:
		return "tail"
	return "hull"


## Cosmetic scorch/dent where something hit the plane (plane-local point).
func add_scar(local: Vector3) -> void:
	var s := _sphere(randf_range(0.12, 0.22), local, Color(0.1, 0.09, 0.08), Vector3(1, 1, 1) * randf_range(0.8, 1.2))
	s.scale.y *= 0.35
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scars.append(s)
	if _scars.size() > MAX_SCARS:
		_scars.pop_front().queue_free()


# --- Construction helpers ----------------------------------------------------------------

func _mat(c: Color, metallic := 0.0, rough := 0.75) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f" % [c.to_html(), metallic, rough]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = metallic
		m.roughness = rough
		if c.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
			m.metallic_specular = 1.0
		_mats[key] = m
	return _mats[key]


## Shared BoxMesh per (size, colour) so repeated seats cost one mesh resource each.
func _box_mesh(size: Vector3, color: Color) -> BoxMesh:
	var key := "%s|%s" % [size, color.to_html()]
	if not _box_meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = _mat(color)
		_box_meshes[key] = bm
	return _box_meshes[key]


## Adds a box mesh (and collision unless collide=false). Returns the mesh; the shape is in meta "shape".
func _box(size: Vector3, center: Vector3, color: Color, collide := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size, color)
	mi.position = center
	add_child(mi)
	if collide:
		mi.set_meta("shape", _collider(size, center))
	return mi


## Invisible collision box.
func _collider(size: Vector3, center: Vector3, basis := Basis.IDENTITY) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, center)
	add_child(cs)
	return cs


## Cylinder (or cone with r_top != r_bottom) along an axis (UP, FORWARD or RIGHT).
func _cyl(r_bottom: float, length: float, center: Vector3, axis: Vector3, color: Color,
		r_top := -1.0, metallic := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r_bottom
	cm.top_radius = r_bottom if r_top < 0.0 else r_top
	cm.height = length
	cm.radial_segments = 20
	cm.rings = 1
	cm.material = _mat(color, metallic, 0.35 if metallic > 0.0 else 0.75)
	mi.mesh = cm
	mi.position = center
	if axis == Vector3.FORWARD:
		mi.rotation.x = -PI / 2   # Mesh +Y (top) points to -Z (nose).
	elif axis == Vector3.BACK:
		mi.rotation.x = PI / 2
	elif axis == Vector3.RIGHT:
		mi.rotation.z = -PI / 2
	add_child(mi)
	return mi


func _sphere(radius: float, center: Vector3, color: Color, scale_v := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 20
	sm.rings = 10
	sm.material = _mat(color)
	mi.mesh = sm
	mi.position = center
	mi.scale = scale_v
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


func _window_zs() -> Array:
	var zs: Array = ROW_Z.duplicate()
	zs.append_array(LOUNGE_WINDOW_Z)
	zs.append(-12.2)   # Cockpit side windows.
	return zs


static func _window_width(z: float) -> float:
	return 1.1 if z < -10.0 else 0.6


# --- Fuselage -----------------------------------------------------------------------------

## The visible tube: outer cylinder minus inner cylinder, windows, doors and windshield.
func _build_fuselage() -> void:
	var length := TAIL_Z - NOSE_Z
	var mid := (TAIL_Z + NOSE_Z) / 2.0
	_hull_csg = CSGCombiner3D.new()
	add_child(_hull_csg)
	var outer := _csg_cyl(HULL_R, length, Vector3(0, HULL_CY, mid), _mat(HULL, 0.1, 0.4))
	_hull_csg.add_child(outer)
	var inner := _csg_cyl(HULL_R_IN, length + 0.4, Vector3(0, HULL_CY, mid + 0.25), _mat(CABIN_WALL))
	inner.operation = CSGShape3D.OPERATION_SUBTRACTION
	_hull_csg.add_child(inner)
	for sx in [-1, 1]:
		for z: float in _window_zs():
			_csg_hole(Vector3(0.8, 0.62, _window_width(z)), Vector3(sx * 2.25, 1.45, z))
		_csg_hole(Vector3(0.8, 2.1, 1.2), Vector3(sx * 2.25, 1.05, 0))
	_csg_hole(Vector3(3.2, 1.0, 0.6), Vector3(0, 1.7, NOSE_Z))   # Windshield.
	# Nose dome below the windshield.
	var nose := CSGSphere3D.new()
	nose.radius = 1.0
	nose.radial_segments = 24
	nose.rings = 12
	nose.material = _mat(HULL, 0.1, 0.4)
	nose.scale = Vector3(HULL_R, 1.35, 3.0)
	nose.position = Vector3(0, 0.0, NOSE_Z)
	var nose_cut := CSGBox3D.new()
	nose_cut.size = Vector3(2, 2, 2)   # In the sphere's scaled space: removes the rear half.
	nose_cut.position = Vector3(0, 0, 1.0)
	nose_cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	nose.add_child(nose_cut)
	add_child(nose)
	_sphere(0.35, Vector3(0, -0.2, NOSE_Z - 2.95), DARK, Vector3(1, 0.7, 0.3))   # Radar tip.
	# Floors and ceiling (visible) plus the hidden collision shell.
	_box(Vector3(3.9, 0.2, length), Vector3(0, -0.1, mid), CARPET, false)
	_box(Vector3(0.7, 0.012, 16.0), Vector3(0, 0.006, -2.0), RUNNER, false)
	_box(Vector3(2.85, 0.06, length), Vector3(0, CEIL + 0.03, mid), Color(0.97, 0.96, 0.93), false)
	_collider(Vector3(4.4, 0.2, length), Vector3(0, -0.1, mid))
	_collider(Vector3(4.4, 1.2, length), Vector3(0, -0.8, mid))
	_collider(Vector3(4.4, 0.2, length), Vector3(0, CEIL + 0.1, mid))
	# Livery: belly stripe, cheat line, airline name.
	for sx in [-1, 1]:
		_box(Vector3(0.02, 0.22, length - 1.0), Vector3(sx * 2.335, 0.75, mid), TRIM, false)
		_box(Vector3(0.02, 0.07, length - 1.0), Vector3(sx * 2.33, 0.55, mid), ACCENT, false)
		_label("SKY-ISH AIRLINES", Vector3(sx * 2.21, 2.05, -4.5), 110, TRIM, sx * PI / 2).outline_size = 0
		_label("probably fine™", Vector3(sx * 2.21, 2.05, 4.0), 60, Color(0.4, 0.4, 0.45), sx * PI / 2).outline_size = 0


func _csg_cyl(r: float, length: float, center: Vector3, mat: Material) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.radius = r
	c.height = length
	c.sides = 32
	c.material = mat
	c.rotation.x = PI / 2
	c.position = center
	return c


func _csg_hole(size: Vector3, center: Vector3) -> void:
	var b := CSGBox3D.new()
	b.size = size
	b.position = center
	b.material = _mat(PLASTIC)
	b.operation = CSGShape3D.OPERATION_SUBTRACTION
	_hull_csg.add_child(b)


## Collision walls (invisible; the CSG tube is the visible wall) and glass panes.
func _build_walls() -> void:
	var window_zs := _window_zs()
	for sx in [-1, 1]:
		var x: float = sx * (HALF_W + 0.1)
		for s in spans(NOSE_Z, TAIL_Z, [EXIT_GAP]):
			_collider(Vector3(0.2, 1.1, s.y - s.x), Vector3(x, 0.55, (s.x + s.y) / 2))
			_collider(Vector3(0.2, 0.3, s.y - s.x), Vector3(x, 1.95, (s.x + s.y) / 2))
		_collider(Vector3(0.2, 0.7, TAIL_Z - NOSE_Z), Vector3(x, 2.45, (TAIL_Z + NOSE_Z) / 2))
		var gaps := [EXIT_GAP]
		for wz: float in window_zs:
			gaps.append(Vector2(wz - _window_width(wz) / 2, wz + _window_width(wz) / 2))
		for s in spans(NOSE_Z, TAIL_Z, gaps):
			_collider(Vector3(0.2, 0.7, s.y - s.x), Vector3(x, 1.45, (s.x + s.y) / 2))
		for wz: float in window_zs:
			_add_window(Vector3(0.05, 0.62, _window_width(wz)), Vector3(sx * WINDOW_X, 1.45, wz))
			# Window shade and frame trim inside.
			_box(Vector3(0.03, 0.08, _window_width(wz) + 0.12), Vector3(sx * 2.12, 1.8, wz), PLASTIC, false)
		# Over-wing emergency exit door.
		var door_name := "left" if sx < 0 else "right"
		var dm := _box(Vector3(0.12, 2.05, 1.18), Vector3(sx * 2.18, 1.03, 0), Color(0.88, 0.3, 0.25))
		_box(Vector3(0.05, 0.08, 0.5), Vector3(sx * 2.1, 1.2, 0), Color(0.95, 0.85, 0.2), false).reparent(dm)
		var area := Interactable.make(Vector3(0.8, 2.0, 1.2), "", "door", [door_name])
		area.position = Vector3(sx * 1.75, 1.0, 0)
		add_child(area)
		doors[door_name] = {"mesh": dm, "shape": dm.get_meta("shape"), "open": false, "area": area,
			"label": "the emergency exit", "pos": Vector3(x, 1.0, 0)}
		set_door(door_name, false)
		_label("EXIT", Vector3(sx * 1.6, 2.6, 0), 56, Color(1, 0.25, 0.2), -sx * PI / 2)
	# Front wall collision with windshield panes.
	var fz := NOSE_Z - 0.1
	_collider(Vector3(4.4, 1.2, 0.2), Vector3(0, 0.6, fz))
	_collider(Vector3(4.4, 0.6, 0.2), Vector3(0, 2.5, fz))
	for px in [-1.85, 1.85]:
		_collider(Vector3(0.5, 1.0, 0.2), Vector3(px, 1.7, fz))
	_box(Vector3(0.12, 1.0, 0.16), Vector3(0, 1.7, fz), DARK)
	for px in [-0.82, 0.82]:
		_add_window(Vector3(1.52, 1.0, 0.05), Vector3(px, 1.7, fz))


func _add_window(size: Vector3, pos: Vector3) -> void:
	var m := _box(size, pos, GLASS)
	var shape: CollisionShape3D = m.get_meta("shape")
	shape.set_meta("window", windows.size())
	windows.append({"mesh": m, "shape": shape, "broken": false, "pos": pos, "broke_at": -100.0})


## Partition wall across the tube with a doorway: a CSG disc cut to the hull, floor and
## ceiling, plus invisible box colliders.
func _bulkhead(z: float, gap_half: float, gap_h: float, color: Color) -> void:
	_partition(z, Vector3(gap_half * 2, gap_h, 0.4), gap_h / 2, color, true)
	var side := HALF_W + 0.15 - gap_half
	for sx in [-1, 1]:
		_collider(Vector3(side, CEIL, 0.12), Vector3(sx * (gap_half + side / 2), CEIL / 2, z))
		_box(Vector3(0.08, gap_h, 0.16), Vector3(sx * (gap_half + 0.04), gap_h / 2, z), METAL, false)
	_collider(Vector3(gap_half * 2, CEIL - gap_h, 0.12), Vector3(0, (CEIL + gap_h) / 2, z))


## Visual disc across the tube at z with a rectangular hole; optionally trimmed to floor..ceiling.
func _partition(z: float, hole: Vector3, hole_y: float, color: Color, trim: bool) -> void:
	var c := CSGCombiner3D.new()
	add_child(c)
	var disc := _csg_cyl(HULL_R_IN + 0.01, 0.12, Vector3(0, HULL_CY, z), _mat(color))
	c.add_child(disc)
	var cuts := [[hole, Vector3(0, hole_y, z)]]
	if trim:
		cuts.append([Vector3(5, 2, 0.4), Vector3(0, -1.0, z)])
		cuts.append([Vector3(5, 2, 0.4), Vector3(0, CEIL + 1.0, z)])
	for cut in cuts:
		var b := CSGBox3D.new()
		b.size = cut[0]
		b.position = cut[1]
		b.operation = CSGShape3D.OPERATION_SUBTRACTION
		c.add_child(b)


# --- Cockpit ------------------------------------------------------------------------------

func _build_cockpit() -> void:
	_bulkhead(-10.0, 0.55, 2.1, Color(0.82, 0.8, 0.74))
	var dm := _box(Vector3(1.1, 2.1, 0.08), Vector3(0, 1.05, -10.0), Color(0.5, 0.46, 0.42))
	_sphere(0.05, Vector3(0.4, 1.0, -9.94), METAL).reparent(dm)
	var area := Interactable.make(Vector3(1.1, 2.0, 1.6), "", "door", ["cockpit"])
	area.position = Vector3(0, 1.0, -10.0)
	add_child(area)
	doors["cockpit"] = {"mesh": dm, "shape": dm.get_meta("shape"), "open": false, "area": area,
		"label": "the cockpit door", "pos": Vector3(0, 1.0, -10.0)}
	set_door("cockpit", false)
	_label("CREW ONLY", Vector3(0, 2.35, -9.92), 40, Color(1, 0.9, 0.3))
	_label("(seriously)", Vector3(0, 2.18, -9.92), 22, Color(1, 0.9, 0.3))
	# Dashboard: body, glare shield, screens, dials, throttle quadrant.
	_box(Vector3(3.4, 1.0, 0.7), Vector3(0, 0.5, -13.55), Color(0.2, 0.2, 0.23))
	_box(Vector3(3.4, 0.18, 0.45), Vector3(0, 1.09, -13.65), DARK)
	for i in 4:
		var sx := -1.2 + i * 0.8
		_box(Vector3(0.55, 0.38, 0.02), Vector3(sx, 0.78, -13.19), Color(0.05, 0.08, 0.1), false)
		_box(Vector3(0.5, 0.16, 0.021), Vector3(sx, 0.86, -13.185), Color(0.25, 0.55, 0.95), false)
		_box(Vector3(0.5, 0.16, 0.021), Vector3(sx, 0.7, -13.185), Color(0.55, 0.38, 0.2), false)
	for i in 8:
		_cyl(0.06, 0.03, Vector3(-1.4 + i * 0.4, 0.42, -13.19), Vector3.BACK, Color(0.9, 0.9, 0.85))
	_box(Vector3(0.35, 0.25, 0.5), Vector3(0, 0.95, -12.95), Color(0.25, 0.25, 0.28))
	for i in 2:
		_box(Vector3(0.04, 0.22, 0.04), Vector3(-0.06 + i * 0.12, 1.15, -12.95), METAL, false)
		_sphere(0.04, Vector3(-0.06 + i * 0.12, 1.27, -12.95), DARK)
	_cyl(0.09, 0.05, Vector3(0, 1.21, -13.32), Vector3.UP, Color(0.85, 0.12, 0.12))
	_label("DO NOT\nPRESS", Vector3(0, 1.24, -13.33), 18, Color.WHITE).rotation.x = -PI / 2
	# Overhead switch panel.
	_box(Vector3(1.6, 0.08, 1.0), Vector3(0, CEIL - 0.04, -12.8), Color(0.3, 0.3, 0.33), false)
	for i in 12:
		_box(Vector3(0.05, 0.04, 0.08), Vector3(-0.6 + (i % 6) * 0.24, CEIL - 0.1, -13.05 + (i / 6) * 0.4),
			[ACCENT, Color(0.2, 0.9, 0.3), Color(0.9, 0.2, 0.2)][i % 3], false)
	# Seats and yokes.
	for p: Vector3 in [PILOT_SEAT, COPILOT_SEAT]:
		_box(Vector3(0.6, 0.45, 0.6), Vector3(p.x, 0.22, p.z), Color(0.32, 0.24, 0.18))
		_box(Vector3(0.6, 1.0, 0.14), Vector3(p.x, 0.95, p.z + 0.32), Color(0.32, 0.24, 0.18))
		_sphere(0.2, Vector3(p.x, 1.48, p.z + 0.34), Color(0.32, 0.24, 0.18), Vector3(1.3, 0.8, 0.5))
		_cyl(0.035, 0.45, Vector3(p.x, 0.75, p.z - 0.72), Vector3.UP, DARK)
		var yoke := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.13
		tm.outer_radius = 0.17
		tm.material = _mat(DARK)
		yoke.mesh = tm
		yoke.position = Vector3(p.x, 1.0, p.z - 0.72)
		yoke.rotation.x = PI / 2
		add_child(yoke)
	pilot_area = Interactable.make(Vector3(0.7, 1.2, 0.8), "Fly the plane (you totally can) [E]", "pilot_enter")
	pilot_area.position = PILOT_SEAT + Vector3(0, 0.3, 0)
	add_child(pilot_area)
	var co := Interactable.make(Vector3(0.7, 1.2, 0.8), "Sit in the co-pilot seat [E]", "sit")
	co.local_only = true
	co.set_meta("seat", COPILOT_SEAT)
	co.position = COPILOT_SEAT + Vector3(0, 0.3, 0)
	add_child(co)
	seat_areas.append(co)
	var photo := _label("CAPT. DAVE\n★ 2 STARS ★", Vector3(-1.95, 1.9, -11.2), 22, Color(0.2, 0.2, 0.2), PI / 2)
	photo.outline_size = 0


# --- Cabin --------------------------------------------------------------------------------

func _build_cabin() -> void:
	for z: float in ROW_Z:
		for x: float in SEAT_X:
			_build_seat(Vector3(x, 0, z))
			var seat := Vector3(x, 0.5, z)
			seats.append(seat)
			var area := Interactable.make(Vector3(0.45, 0.5, 0.45), "Sit down [E]", "sit")
			area.local_only = true
			area.set_meta("seat", seat)
			area.position = seat + Vector3(0, 0.15, 0)
			add_child(area)
			seat_areas.append(area)
		_label("%d" % (ROW_Z.find(z) + 1), Vector3(-1.38, 2.2, z), 30, Color(0.25, 0.25, 0.3), PI / 2)
	for i in 16:
		aisle_points.append(Vector3(0, 0.0, -9.5 + i))
	# Rounded overhead bins with latches and reading lights.
	for sx in [-1, 1]:
		_box(Vector3(0.5, 0.42, 15.4), Vector3(sx * 1.38, 2.48, -2.0), PLASTIC, false)
		_cyl(0.21, 15.4, Vector3(sx * 1.13, 2.48, -2.0), Vector3.FORWARD, PLASTIC)
		for z: float in ROW_Z:
			_box(Vector3(0.02, 0.06, 0.18), Vector3(sx * 0.92, 2.45, z), Color(0.55, 0.55, 0.55), false)
			_cyl(0.03, 0.02, Vector3(sx * 1.2, 2.26, z + 0.2), Vector3.UP, Color(1, 0.95, 0.7))
	_label("PLEASE REMAIN SEATED", Vector3(0, 2.4, -9.93), 30, Color(0.9, 0.9, 0.9))
	_label("(lol)", Vector3(0, 2.25, -9.93), 20, Color(0.9, 0.9, 0.9))
	# Galley counter at the front of the cabin.
	for sx in [-1, 1]:
		_box(Vector3(0.9, 1.0, 0.5), Vector3(sx * 1.45, 0.5, -9.6), METAL)
		_box(Vector3(0.95, 0.04, 0.55), Vector3(sx * 1.45, 1.02, -9.6), Color(0.3, 0.3, 0.32), false)


## One passenger seat: cushion, backrest, headrest, armrests, tray table.
func _build_seat(base: Vector3) -> void:
	var x := base.x
	var z := base.z
	_box(Vector3(0.48, 0.12, 0.48), Vector3(x, 0.42, z - 0.02), SEAT)
	_box(Vector3(0.44, 0.36, 0.4), Vector3(x, 0.18, z), DARK)
	_collider(Vector3(0.5, 0.48, 0.5), Vector3(x, 0.24, z))
	_box(Vector3(0.48, 0.72, 0.12), Vector3(x, 0.84, z + 0.27), SEAT)
	_collider(Vector3(0.5, 0.85, 0.14), Vector3(x, 0.85, z + 0.27))
	_box(Vector3(0.4, 0.2, 0.14), Vector3(x, 1.27, z + 0.28), SEAT_DARK, false)
	_box(Vector3(0.38, 0.1, 0.02), Vector3(x, 1.27, z + 0.2), Color(0.95, 0.95, 0.95), false)
	for ax in [-0.25, 0.25]:
		_box(Vector3(0.05, 0.05, 0.42), Vector3(x + ax, 0.66, z), PLASTIC, false)
	_box(Vector3(0.36, 0.03, 0.22), Vector3(x, 0.9, z + 0.345), Color(0.35, 0.35, 0.38), false)
	_box(Vector3(0.3, 0.18, 0.02), Vector3(x, 0.55, z + 0.34), SEAT_DARK, false)


# --- Lounge -------------------------------------------------------------------------------

## Empty, carpeted lounge between cabin and cargo; the Fun module furnishes it.
func _build_lounge() -> void:
	_bulkhead(LOUNGE_MIN.z - 0.2, 0.8, 2.3, Color(0.55, 0.38, 0.6))
	_label("LOUNGE", Vector3(0, 2.5, LOUNGE_MIN.z - 0.27), 46, ACCENT, PI)
	_label("LOUNGE", Vector3(0, 2.5, LOUNGE_MIN.z - 0.13), 46, ACCENT)
	var mid := (LOUNGE_MIN.z + LOUNGE_MAX.z) / 2.0
	var length := LOUNGE_MAX.z - LOUNGE_MIN.z + 0.4
	_box(Vector3(3.8, 0.014, length), Vector3(0, 0.007, mid), Color(0.42, 0.2, 0.42), false)
	for i in 6:
		_box(Vector3(3.6, 0.016, 0.06), Vector3(0, 0.008, LOUNGE_MIN.z + 0.4 + i * 1.0), ACCENT, false)
	for sx in [-1, 1]:
		_box(Vector3(0.04, 0.1, length), Vector3(sx * 1.95, 2.1, mid), Color(0.9, 0.5, 1.0), false)


# --- Cargo hold ---------------------------------------------------------------------------

func _build_cargo() -> void:
	var z0 := CARGO_MIN.z - 1.0
	_bulkhead(z0, 0.8, 2.3, Color(0.45, 0.45, 0.42))
	_label("CARGO", Vector3(0, 2.5, z0 - 0.07), 48, ACCENT, PI)
	_label("CARGO", Vector3(0, 2.5, z0 + 0.07), 48, ACCENT)
	var mid := (z0 + TAIL_Z) / 2.0
	_box(Vector3(3.9, 0.012, TAIL_Z - z0), Vector3(0, 0.006, mid), Color(0.32, 0.33, 0.35), false)
	for i in 4:
		_box(Vector3(3.8, 0.014, 0.3), Vector3(0, 0.007, z0 + 1.5 + i * 2.4), ACCENT, false)
	# Tie-down rails along the floor.
	for sx in [-1, 1]:
		_box(Vector3(0.06, 0.03, TAIL_Z - z0), Vector3(sx * 1.2, 0.015, mid), METAL, false)
	# Rear ramp.
	_ramp_mesh = _box(Vector3(4.2, 2.8, 0.15), Vector3.ZERO, Color(0.55, 0.57, 0.6))
	_ramp_shape = _ramp_mesh.get_meta("shape")
	for i in 5:
		_box(Vector3(4.0, 0.06, 0.04), Vector3(0, -1.1 + i * 0.55, -0.09), Color(0.4, 0.42, 0.45), false).reparent(_ramp_mesh, false)
	_ramp_lever = Interactable.make(Vector3(0.5, 0.8, 0.5), "", "ramp")
	_ramp_lever.position = RAMP_LEVER
	add_child(_ramp_lever)
	_box(Vector3(0.2, 0.5, 0.3), RAMP_LEVER + Vector3(0.12, -0.1, 0), Color(0.3, 0.3, 0.32), false)
	_cyl(0.025, 0.45, RAMP_LEVER + Vector3(0, 0.2, 0), Vector3.UP, Color(0.85, 0.1, 0.1))
	_sphere(0.06, RAMP_LEVER + Vector3(0, 0.44, 0), Color(0.85, 0.1, 0.1))
	_label("RAMP", RAMP_LEVER + Vector3(0.18, 0.45, 0), 32, Color(1, 0.3, 0.3), -PI / 2)
	# Rear cap around the ramp opening.
	_partition(TAIL_Z + 0.05, Vector3(4.3, 2.85, 0.4), 1.42, HULL, false)
	_collider(Vector3(4.4, 0.6, 0.12), Vector3(0, CEIL + 0.3, TAIL_Z + 0.05))
	set_ramp(false)


func _ramp_transform(open: bool) -> Transform3D:
	var hinge := Vector3(0, 0, TAIL_Z + 0.08)
	var angle := deg_to_rad(110.0) if open else 0.0
	var b := Basis(Vector3.RIGHT, angle)
	return Transform3D(b, hinge + b * Vector3(0, 1.4, 0))


# --- Wings, engines, tail, gear -----------------------------------------------------------

func _build_wings() -> void:
	for sx in [-1, 1]:
		_box(Vector3(11.9, 0.3, 3.6), Vector3(sx * 8.05, -0.25, 0.7), HULL)
		_cyl(0.15, 11.9, Vector3(sx * 8.05, -0.25, -1.1), Vector3.RIGHT, HULL)
		var pivot := Node3D.new()
		pivot.position = Vector3(sx * 7.0, -0.3, 2.45)
		add_child(pivot)
		_box(Vector3(9.0, 0.08, 0.9), Vector3.ZERO, Color(0.85, 0.86, 0.88), false).reparent(pivot, false)
		pivot.get_child(0).position = Vector3(0, 0, 0.45)
		_flap_pivots.append(pivot)
		_box(Vector3(11.9, 0.02, 0.2), Vector3(sx * 8.05, -0.09, -0.9), TRIM, false)
		# Winglet.
		var wl := _box(Vector3(0.2, 1.4, 1.4), Vector3(sx * 14.2, 0.4, 1.4), TRIM, false)
		wl.rotation.z = -sx * 0.25
		_sphere(0.14, Vector3(sx * 14.1, -0.15, 0.0), Color(1, 0.1, 0.1) if sx < 0 else Color(0.1, 1, 0.2))
		_label("NO STEP", Vector3(sx * 4.5, -0.08, 1.8), 64, Color(0.2, 0.2, 0.2)).rotation.x = -PI / 2
		_label("(please)", Vector3(sx * 4.5, -0.08, 2.25), 36, Color(0.2, 0.2, 0.2)).rotation.x = -PI / 2
		# Grab handles to cling to.
		for hz in [0.2, 1.6]:
			_cyl(0.035, 0.6, Vector3(sx * 3.0, 0.02, hz), Vector3.RIGHT, ACCENT)
		_build_engine(0 if sx < 0 else 1)


func _build_engine(i: int) -> void:
	var ep: Vector3 = ENGINE_POS[i]
	_cyl(0.72, 3.0, ep, Vector3.FORWARD, Color(0.82, 0.83, 0.87), -1.0, 0.4)
	_cyl(0.55, 0.6, ep + Vector3(0, 0, 1.75), Vector3.BACK, METAL, 0.3, 0.6)   # Exhaust cone.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.6
	tm.outer_radius = 0.78
	tm.material = _mat(Color(0.7, 0.72, 0.76), 0.5, 0.3)
	ring.mesh = tm
	ring.position = ep + Vector3(0, 0, -1.5)
	ring.rotation.x = PI / 2
	add_child(ring)
	_cyl(0.6, 0.05, ep + Vector3(0, 0, -1.35), Vector3.FORWARD, DARK)
	_sphere(0.2, ep + Vector3(0, 0, -1.42), Color(0.9, 0.9, 0.9), Vector3(1, 1, 1.4))   # Spinner.
	_box(Vector3(0.25, 0.7, 2.0), ep + Vector3(0, 0.6, 0.3), HULL, false)   # Pylon.
	_collider(Vector3(1.44, 1.44, 3.0), ep)
	_fires.append(_make_fire(ep + Vector3(0, 0.9, 0)))


func _make_fire(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	var p := CPUParticles3D.new()
	var qm := SphereMesh.new()
	qm.radius = 0.2
	qm.height = 0.4
	qm.radial_segments = 8
	qm.rings = 4
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
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
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


func _build_tail() -> void:
	# Upswept tail cone above the ramp, fin and stabilisers.
	_cyl(1.5, 3.6, Vector3(0, 2.75, TAIL_Z + 1.6), Vector3.BACK, HULL, 0.35)
	_box(Vector3(0.3, 4.0, 3.2), Vector3(0, 5.2, TAIL_Z + 1.2), HULL)
	_cyl(0.15, 4.0, Vector3(0, 5.2, TAIL_Z - 0.4), Vector3.UP, HULL)
	_box(Vector3(0.32, 1.6, 2.4), Vector3(0, 5.8, TAIL_Z + 1.4), TRIM, false)
	_label("S?", Vector3(0.17, 5.8, TAIL_Z + 1.4), 220, Color.WHITE, PI / 2).outline_size = 0
	_label("S?", Vector3(-0.17, 5.8, TAIL_Z + 1.4), 220, Color.WHITE, -PI / 2).outline_size = 0
	_box(Vector3(8.0, 0.18, 2.0), Vector3(0, 3.3, TAIL_Z + 2.0), HULL)
	_cyl(0.09, 8.0, Vector3(0, 3.3, TAIL_Z + 1.0), Vector3.RIGHT, HULL)


func _build_gear() -> void:
	for p: Vector3 in [Vector3(0, -1.2, -11), Vector3(-1.6, -1.2, 1.5), Vector3(1.6, -1.2, 1.5)]:
		for dx in ([-0.2, 0.2] if p.x == 0.0 else [-0.25, 0.25]):
			_gear_meshes.append(_cyl(0.3, 0.22, p + Vector3(dx, 0, 0), Vector3.RIGHT, Color(0.08, 0.08, 0.08)))
			_gear_meshes.append(_cyl(0.14, 0.24, p + Vector3(dx, 0, 0), Vector3.RIGHT, METAL, -1.0, 0.6))
		_gear_meshes.append(_cyl(0.06, 0.6, p + Vector3(0, 0.35, 0), Vector3.UP, METAL, -1.0, 0.6))


func _build_lights() -> void:
	for z in [-12.0, -7.5, -3.0, 2.5, 9.0, 15.0, 19.5]:
		var l := OmniLight3D.new()
		l.position = Vector3(0, 2.5, z)
		l.light_color = Color(1.0, 0.95, 0.85) if z < 12.0 else Color(0.85, 0.9, 1.0)
		l.light_energy = 1.2
		l.omni_range = 6.0
		add_child(l)


## One smoke trail per damage part; set_damage turns it on as health drops.
func _build_smoke() -> void:
	var spots := {"engine0": ENGINE_POS[0] + Vector3(0, 0.4, 1.0), "engine1": ENGINE_POS[1] + Vector3(0, 0.4, 1.0),
		"wing0": Vector3(-9, 0, 1.5), "wing1": Vector3(9, 0, 1.5), "tail": Vector3(0, 4.5, TAIL_Z + 2.0),
		"hull": Vector3(0, HULL_CY + HULL_R, 2.0)}
	var puff := SphereMesh.new()
	puff.radius = 0.3
	puff.height = 0.6
	puff.radial_segments = 8
	puff.rings = 4
	var pm := StandardMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = pm
	for part: String in spots:
		var s := CPUParticles3D.new()
		s.mesh = puff
		s.amount = 30
		s.lifetime = 2.0
		s.local_coords = false
		s.position = spots[part]
		s.direction = Vector3(0, 0.3, 1)
		s.spread = 15.0
		s.gravity = Vector3(0, 0.5, 14)   # Streams back in the slipstream.
		s.initial_velocity_min = 2.0
		s.initial_velocity_max = 4.0
		s.scale_amount_min = 0.8
		var fade := Curve.new()
		fade.add_point(Vector2(0, 0.5))
		fade.add_point(Vector2(1, 1.0))
		s.scale_amount_curve = fade
		s.emitting = false
		add_child(s)
		_smoke[part] = s
		damage[part] = 1.0


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
