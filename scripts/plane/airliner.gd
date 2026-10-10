class_name Airliner
extends AnimatableBody3D
## The airliner, a chunky cartoon twin turboprop. It sits at the world origin and only
## pitches/rolls; the outside world moves past it. Tilting it is what makes everything
## inside slide.
##
## Local axes: -Z = nose, +X = right wing, floor top at y = 0.
## Cockpit z -14..-10 | cabin -10..6 | lounge 6..12 | cargo hold 12..22 (rear ramp at TAIL_Z).
## Collision is simple invisible boxes (one compound of static shapes plus separate nodes
## for windows, doors and the ramp). Everything static is drawn from a few batched meshes
## (see plane_mesh.gd): a smooth lofted hull with real window and door openings, seats as
## one MultiMesh. Mutable state (windows, doors, ramp, engine fires, gear) changes only
## through apply_change(key, value); the host broadcasts via World.set_plane().

const MeshBatch := preload("res://scripts/plane/plane_mesh.gd")
const PlaneModels := preload("res://scripts/plane/plane_models.gd")
const OxygenMasks := preload("res://scripts/plane/oxygen_masks.gd")
const MATTE := MeshBatch.Finish.MATTE
const FABRIC := MeshBatch.Finish.FABRIC
const PAINT := MeshBatch.Finish.PAINT
const SHINY := MeshBatch.Finish.METAL
const GLOSS := MeshBatch.Finish.GLOSS
const GLOW := MeshBatch.Finish.GLOW

const LAYER_WORLD := 1
const HALF_W := 2.6          ## Inner half width of the walkable floor.
const CEIL := 3.0
const NOSE_Z := -14.0
const TAIL_Z := 22.0
const GEAR_HEIGHT := 2.2     ## Floor height above the ground when the wheels touch.
const HULL_CY := 1.3         ## Fuselage tube axis height.
const HULL_R := 3.05         ## Outer radius.
const HULL_R_IN := 2.9       ## Inner radius.
const ROW_Z := [-8.5, -7.0, -5.5, -4.0, -2.5, 2.0, 3.5, 5.0]
const LOUNGE_WINDOW_Z := [7.5, 9.0, 10.5]
## Two seats per side; the aisle between them is ~2.3 m, wide enough to walk side by side.
const SEAT_X := [-2.05, -1.45, 1.45, 2.05]
const EXIT_GAP := Vector2(-0.6, 0.6)
const WINDOW_X := 2.84
const ENGINE_POS := [Vector3(-7, -1.15, -0.8), Vector3(7, -1.15, -0.8)]
const PILOT_SEAT := Vector3(-0.75, 0.5, -12.6)
const COPILOT_SEAT := Vector3(0.75, 0.5, -12.6)
## Lounge floor area (free for furniture): x/z bounds.
const LOUNGE_MIN := Vector3(-2.5, 0.0, 6.2)
const LOUNGE_MAX := Vector3(2.5, 0.0, 11.8)
## Cargo hold floor area for crates: x/z bounds.
const CARGO_MIN := Vector3(-2.3, 0.0, 13.0)
const CARGO_MAX := Vector3(2.3, 0.0, 21.2)
const RAMP_LEVER := Vector3(2.35, 1.2, 20.5)
const DOOR_GAP_HALF := 1.2   ## Half width of the lounge and cargo doorways.
const SUCTION_BURST := 26.0
const SUCTION_STEADY := 5.0
const SUCTION_RANGE := 3.5
const DAMAGE_PARTS := ["engine0", "engine1", "wing0", "wing1", "tail", "hull"]
const MAX_SCARS := 40

const HULL := Color(0.96, 0.97, 0.99)
const TRIM := Color(0.12, 0.36, 0.85)
const ACCENT := Color(1.0, 0.74, 0.15)
const CABIN_WALL := Color(0.92, 0.93, 0.95)
const CABIN_GREY := Color(0.76, 0.78, 0.82)
const CARPET := Color(0.12, 0.16, 0.34)
const RUNNER := Color(0.18, 0.25, 0.52)
const METAL := Color(0.62, 0.64, 0.68)
const DARK := Color(0.14, 0.15, 0.18)
const DASH := Color(0.25, 0.28, 0.34)
const LEATHER := Color(0.45, 0.28, 0.18)
const GLASS := Color(0.55, 0.8, 1.0, 0.3)
const WINDSHIELD := Color(0.1, 0.16, 0.26)
const LIGHT_STRIP := Color(1.0, 0.96, 0.85)

## Hull grid: the tube's angles are split at these heights so window and door openings fall
## exactly on grid lines (both sides mirror). Segment counts per arc, bottom to top.
const HULL_FEATURE_Y := [0.0, 1.14, 1.76, 2.1]
const HULL_ARC_SEGS := [9, 4, 3, 1, 10]
## Nose stations [z, cy, half width, top, bottom, exponent], tip first. W1/W2 (indices
## 6 and 5) bound the wraparound windshield band.
const NOSE_STATIONS := [
	[-18.15, 0.24, 0.04, 0.03, 0.04, 2.0],
	[-17.85, 0.25, 0.55, 0.32, 0.5, 2.0],
	[-17.2, 0.3, 1.2, 0.48, 1.1, 2.0],
	[-16.3, 0.45, 1.9, 0.48, 1.7, 2.1],
	[-15.3, 0.7, 2.5, 0.42, 2.2, 2.3],
	[-14.4, 1.0, 2.9, 0.26, 2.62, 2.5],
	[-13.95, 1.3, 3.0, 0.98, 3.0, 2.6],
	[-13.7, 1.3, 3.03, 1.5, 3.03, 2.4],
	[-13.3, 1.3, 3.05, 2.7, 3.05, 2.1],
]
const NOSE_W2 := 5
const NOSE_W1 := 6
const TUBE_START := -12.8
const TAIL_STATIONS := [
	[22.0, 3.0, 2.55, 1.35, 0.06, 1.9],
	[23.4, 3.22, 2.05, 1.08, 0.12, 1.9],
	[24.9, 3.48, 1.4, 0.78, 0.18, 2.0],
	[26.3, 3.74, 0.7, 0.42, 0.18, 2.0],
	[27.2, 3.88, 0.08, 0.06, 0.06, 2.0],
]
const PROP_RADIUS := 0.95
const PROP_MAX_SPIN := 30.0     ## rad/s at full throttle.
const PROP_WINDMILL := 5.0      ## rad/s with a dead engine while flying.

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
var manifest_board: Interactable
var damage := {}                       ## part -> health 0..1 (1 = intact). See DAMAGE_PARTS.

var _mats := {}
var _box_meshes := {}
var _ext: MeshBatch                    ## Exterior batch (casts shadows).
var _int: MeshBatch                    ## Interior batch, flushed per section (lining, cockpit, cabin).
var _aft: MeshBatch                    ## Lounge + cargo interior batch.
var _hull_angles := PackedFloat32Array()
var _ramp_shape: CollisionShape3D
var _ramp_mesh: MeshInstance3D
var _ramp_lever: Interactable
var _gear_meshes: Array[Node3D] = []
var _fires: Array[Node3D] = []
var _smoke := {}                       ## part -> CPUParticles3D
var _flap_pivots: Array[Node3D] = []
var _flaps := -1
var _scars: Array[Node3D] = []
var _props: Array[Node3D] = []
var _prop_blur: Array[StandardMaterial3D] = []
var _status_mats := {}                 ## part -> material of its cockpit status-screen icon
var _masks: OxygenMasks
var _breached := false                 ## A window, exit door or the ramp is open.
var _quiet_until := 0                  ## Frame until which masks drop silently (late join sync).
var _blink := 0.0


func _ready() -> void:
	collision_layer = LAYER_WORLD
	collision_mask = 0
	sync_to_physics = true
	_ext = MeshBatch.new()
	_int = MeshBatch.new()
	_aft = MeshBatch.new()
	_hull_angles = _make_hull_angles()
	_build_fuselage()
	_build_walls()
	_flush(_int, false)      # Hull lining.
	_build_cockpit()
	_flush(_int, false)      # Cockpit: its own mesh so it culls when facing aft.
	_build_cabin()
	_build_lounge()
	_build_cargo()
	_build_wings()
	_build_tail()
	_build_gear()
	_build_lights()
	_build_smoke()
	_flush(_ext, true)
	_flush(_int, false)
	_flush(_aft, false)
	set_gear(false)
	set_flaps(0)


func _process(dt: float) -> void:
	_spin_props(dt)
	_blink_status(dt)
	if not _masks.deployed and airborne and _breached:
		_masks.deploy(Engine.get_process_frames() > _quiet_until)


## Bakes a batch into one MeshInstance3D.
func _flush(b: MeshBatch, shadows: bool) -> void:
	if b.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


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
	if node == null or node == self:
		return -1
	return int(node.get_meta("window", -1))


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


## True once the oxygen masks have dropped this round.
func masks_down() -> bool:
	return _masks.deployed


# --- State changes (all peers) -------------------------------------------------------

func get_state() -> Dictionary:
	var s := {"ramp": ramp_open, "gear": gear_down, "fire:0": engine_fire[0], "fire:1": engine_fire[1]}
	for i in windows.size():
		s["window:%d" % i] = windows[i].broken
	for n in doors:
		s["door:" + n] = doors[n].open
	return s


## Late-join sync. A breach that already happened drops the masks without fog or sound.
func apply_state(s: Dictionary) -> void:
	_quiet_until = Engine.get_process_frames() + 2
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
	_update_breach()


func set_door(door_name: String, open: bool) -> void:
	var d: Dictionary = doors[door_name]
	d.open = open
	d.shape.set_deferred("disabled", open)
	d.mesh.visible = not open
	d.area.prompt = ("Close" if open else "Open") + " " + d.label + " [E]"
	_update_breach()


func set_ramp(open: bool) -> void:
	ramp_open = open
	var xf := _ramp_transform(open)
	_ramp_shape.transform = xf
	_ramp_mesh.transform = xf
	_ramp_lever.prompt = ("Close" if open else "Open") + " the cargo ramp [E]"
	_update_breach()


func set_engine_fire(i: int, on: bool) -> void:
	engine_fire[i] = on
	_fires[i].visible = on
	(_fires[i].get_child(0) as CPUParticles3D).emitting = on
	if not on:
		_status_mats["engine%d" % i].albedo_color = _health_color(float(damage.get("engine%d" % i, 1.0)))


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
	_status_mats[part].albedo_color = _health_color(health)


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


## Depressurised: any window broken, an over-wing exit open or the ramp down.
func _update_breach() -> void:
	var open := ramp_open
	for w in windows:
		open = open or bool(w.broken)
	for n in ["left", "right"]:
		if doors.has(n):
			open = open or bool(doors[n].open)
	_breached = open


# --- Runtime cosmetics ---------------------------------------------------------------------

## Props spin with throttle x engine power (both replicated in the flight state).
func _spin_props(dt: float) -> void:
	var f: FlightModel = get_parent().get("flight") if get_parent() else null
	for i in _props.size():
		var power := 0.0
		if f:
			power = float(f.throttle) * float(f.engine_power[i])
		var speed := maxf(power * PROP_MAX_SPIN, PROP_WINDMILL if airborne else 0.0)
		_props[i].rotate_object_local(Vector3.BACK, speed * dt)
		var alpha := clampf((speed - 8.0) / 60.0, 0.0, 0.3)
		if not is_equal_approx(_prop_blur[i].albedo_color.a, alpha):
			_prop_blur[i].albedo_color.a = alpha


## Burning engines blink red on the status screen (set_damage/set_engine_fire set the rest).
func _blink_status(dt: float) -> void:
	_blink += dt
	var on := fmod(_blink, 0.6) < 0.3
	for i in 2:
		if engine_fire[i]:
			_status_mats["engine%d" % i].albedo_color = Color(1, 0.1, 0.05) if on else Color(0.3, 0.02, 0.0)


static func _health_color(health: float) -> Color:
	if health > 0.5:
		return Color(1.0, 0.85, 0.1).lerp(Color(0.2, 0.95, 0.35), (health - 0.5) * 2.0)
	return Color(1.0, 0.1, 0.05).lerp(Color(1.0, 0.85, 0.1), health * 2.0)


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


## Shared BoxMesh per (size, colour).
func _box_mesh(size: Vector3, color: Color) -> BoxMesh:
	var key := "%s|%s" % [size, color.to_html()]
	if not _box_meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = _mat(color)
		_box_meshes[key] = bm
	return _box_meshes[key]


## Box node (and collision node unless collide=false); the shape is in meta "shape".
## Only for parts that change at runtime or for other modules (add_fixture).
func _box(size: Vector3, center: Vector3, color: Color, collide := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size, color)
	mi.position = center
	add_child(mi)
	if collide:
		mi.set_meta("shape", _collider(size, center))
	return mi


## Collision box node, for shapes that toggle or move (windows, doors, ramp).
func _collider(size: Vector3, center: Vector3, basis := Basis.IDENTITY) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, center)
	add_child(cs)
	return cs


## Static invisible collision box added straight to the body (no node).
func _solid(size: Vector3, center: Vector3) -> void:
	var bs := BoxShape3D.new()
	bs.size = size
	var owner_id := create_shape_owner(self)
	shape_owner_add_shape(owner_id, bs)
	shape_owner_set_transform(owner_id, Transform3D(Basis.IDENTITY, center))


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
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	return l


static func _at(p: Vector3, b := Basis.IDENTITY) -> Transform3D:
	return Transform3D(b, p)


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

## Hull section angles (radians from +X toward +Y), starting at the bottom: the right side
## bottom→top, split at HULL_FEATURE_Y, then the mirrored left side back down.
static func _make_hull_angles() -> PackedFloat32Array:
	var edges: Array[float] = [-PI / 2]
	for y: float in HULL_FEATURE_Y:
		edges.append(asin((y - HULL_CY) / HULL_R))
	edges.append(PI / 2)
	var right: Array[float] = [-PI / 2]
	for k in HULL_ARC_SEGS.size():
		var n: int = HULL_ARC_SEGS[k]
		for s in range(1, n + 1):
			right.append(lerpf(edges[k], edges[k + 1], float(s) / n))
	var out := PackedFloat32Array(right)
	for m in range(right.size() - 2, 0, -1):
		out.append(PI - right[m])
	return out


## Right-side grid index of hull feature height k (HULL_FEATURE_Y[k]).
static func _feature_index(k: int) -> int:
	var i := 0
	for s in k + 1:
		i += int(HULL_ARC_SEGS[s])
	return i


## Is hull cell column i between right-side indices [m0, m1) on either side?
func _in_slot(i: int, m0: int, m1: int) -> bool:
	var mirror := _hull_angles.size() - 1 - i
	return (i >= m0 and i < m1) or (mirror >= m0 and mirror < m1)


## Openings in the tube: [z0, z1, m0, m1] (right-side slot indices, mirrored on the left).
func _hull_holes() -> Array:
	var holes := []
	var win0 := _feature_index(1)
	var win1 := _feature_index(2)
	for z: float in _window_zs():
		holes.append([z - _window_width(z) / 2, z + _window_width(z) / 2, win0, win1])
	holes.append([EXIT_GAP.x, EXIT_GAP.y, _feature_index(0), _feature_index(3)])
	return holes


func _tube_zs(holes: Array) -> Array[float]:
	var zs: Array[float] = [TUBE_START, TAIL_Z]
	for h: Array in holes:
		zs.append(h[0])
		zs.append(h[1])
	zs.sort()
	var out: Array[float] = []
	for z in zs:
		if out.is_empty():
			out.append(z)
			continue
		var last: float = out[-1]
		if z - last < 0.01:
			continue
		var steps := ceili((z - last) / 1.2)
		for s in range(1, steps + 1):
			out.append(lerpf(last, z, float(s) / steps))
	return out


## The visible hull: one smooth loft from the nose tip down the tube, outer skin plus an
## inner skin, with real window/door openings and their jambs, a wraparound windshield.
func _build_fuselage() -> void:
	var holes := _hull_holes()
	var tube_zs := _tube_zs(holes)
	var stations: Array = NOSE_STATIONS.duplicate()
	for z in tube_zs:
		stations.append([z, HULL_CY, HULL_R, HULL_R, HULL_R, 2.0])
	var n_nose := NOSE_STATIONS.size()
	var ws := _windshield_cells()
	var outer_skip := func(j: int, i: int) -> bool:
		if j == NOSE_W2 and ws.has(i):
			return true
		return j >= n_nose and _hole_cell(holes, tube_zs, j - n_nose, i)
	_ext.loft(stations, _hull_angles, HULL, PAINT, false, outer_skip)
	_build_windshield(ws)
	# Inner skin from the windshield back: nose stations inset, then the tube.
	var inner: Array = []
	var cols := PackedColorArray()
	for k in range(NOSE_W2, n_nose):
		var st: Array = NOSE_STATIONS[k]
		inner.append([st[0], st[1], st[2] - 0.13, st[3] - 0.13, st[4] - 0.13, st[5]])
		cols.append(CABIN_GREY)
	for z in tube_zs:
		inner.append([z, HULL_CY, HULL_R_IN, HULL_R_IN, HULL_R_IN, 2.0])
		cols.append(CABIN_GREY if z < -10.0 or z > CARGO_MIN.z - 1.0 else CABIN_WALL)
	var n_inner_nose := n_nose - NOSE_W2
	var inner_skip := func(j: int, i: int) -> bool:
		if j == 0 and ws.has(i):
			return true
		return j >= n_inner_nose and _hole_cell(holes, tube_zs, j - n_inner_nose, i)
	_int.loft(inner, _hull_angles, CABIN_WALL, MATTE, true, inner_skip, cols)
	for h: Array in holes:
		_hole_jambs(h)
	_build_floor_and_ceiling()
	_build_livery()


func _hole_cell(holes: Array, zs: Array[float], j: int, i: int) -> bool:
	if j >= zs.size() - 1:
		return false
	for h: Array in holes:
		if zs[j] >= h[0] - 0.001 and zs[j + 1] <= h[1] + 0.001 and _in_slot(i, h[2], h[3]):
			return true
	return false


## Hull columns of the windshield band (between W2 and W1) whose upper edge is above 1.15.
func _windshield_cells() -> Dictionary:
	var out := {}
	var w1: Array = NOSE_STATIONS[NOSE_W1]
	var n := _hull_angles.size()
	for i in n:
		var a := MeshBatch.section_point(_hull_angles[i], w1[1], w1[2], w1[3], w1[4], w1[5])
		var b := MeshBatch.section_point(_hull_angles[(i + 1) % n], w1[1], w1[2], w1[3], w1[4], w1[5])
		if a.y > 1.15 and b.y > 1.15:
			out[i] = true
	return out


## Dark wraparound glass band with white frame posts (outside); invisible from inside, so the
## pilots see out through the real panes.
func _build_windshield(cells: Dictionary) -> void:
	var w2: Array = NOSE_STATIONS[NOSE_W2]
	var w1: Array = NOSE_STATIONS[NOSE_W1]
	var n := _hull_angles.size()
	for i: int in cells:
		var corners: Array[Vector3] = []
		for st: Array in [w2, w1]:
			for a in [_hull_angles[i], _hull_angles[(i + 1) % n]]:
				var p := MeshBatch.section_point(a, st[1], st[2], st[3], st[4], st[5])
				corners.append(Vector3(p.x, p.y, st[0]))
		var mid := (corners[0] + corners[1] + corners[2] + corners[3]) / 4.0
		var out_n := (corners[1] - corners[0]).cross(corners[2] - corners[0])
		if out_n.dot(mid - Vector3(0, 1.0, -14.0)) < 0.0:
			out_n = -out_n
		_ext.quad(corners[0], corners[1], corners[3], corners[2], out_n, WINDSHIELD, GLOSS)
	# Frame posts at the centre and between the panes.
	for x: float in [0.0, -1.95, 1.95, -2.75, 2.75]:
		var a := PI / 2 - asin(clampf(x / 3.0, -1.0, 1.0))
		var p2 := MeshBatch.section_point(a, w2[1], w2[2], w2[3], w2[4], w2[5])
		var p1 := MeshBatch.section_point(a, w1[1], w1[2], w1[3], w1[4], w1[5])
		var from := Vector3(p2.x, p2.y, w2[0])
		var to := Vector3(p1.x, p1.y, w1[0])
		_ext.cylinder(from, to, 0.05, 0.05, HULL, PAINT, 8)


## Reveal faces around an opening, from the outer skin to the inner skin, on both sides.
func _hole_jambs(h: Array) -> void:
	var z0: float = h[0]
	var z1: float = h[1]
	var n := _hull_angles.size()
	for side in 2:
		var idx: Array[int] = []
		for m in range(int(h[2]), int(h[3]) + 1):
			idx.append(m if side == 0 else (n - m) % n)
		idx.sort()
		var pt := func(i: int, z: float, r: float) -> Vector3:
			var a := _hull_angles[i]
			return Vector3(r * cos(a), HULL_CY + r * sin(a), z)
		for k in idx.size() - 1:
			var ia := idx[k]
			var ib := idx[k + 1]
			for zz: float in [z0, z1]:
				var face_n := Vector3(0, 0, 1 if zz == z0 else -1)
				_int.quad(pt.call(ia, zz, HULL_R), pt.call(ib, zz, HULL_R), pt.call(ib, zz, HULL_R_IN),
					pt.call(ia, zz, HULL_R_IN), face_n, CABIN_GREY, MATTE)
		for e in [0, idx.size() - 1]:
			var i := idx[e]
			var a := _hull_angles[i]
			var tangent := Vector3(-sin(a), cos(a), 0) * (1.0 if e == 0 else -1.0)
			_int.quad(pt.call(i, z0, HULL_R), pt.call(i, z1, HULL_R), pt.call(i, z1, HULL_R_IN),
				pt.call(i, z0, HULL_R_IN), tangent, CABIN_GREY, MATTE)


## Half width of the hull tube at height y (inner surface, or outer with outer = true).
static func hull_half_width(y: float, outer := false) -> float:
	var r := HULL_R if outer else HULL_R_IN
	return sqrt(maxf(r * r - (y - HULL_CY) * (y - HULL_CY), 0.0))


## Point on the outer skin (tube part) at angle a (radians from +X toward +Y), side sx.
static func _skin(a: float, z: float, lift := 0.006, sx := 1.0) -> Vector3:
	var r := HULL_R + lift
	return Vector3(sx * r * cos(a), HULL_CY + r * sin(a), z)


## A painted band hugging the outer tube between heights y0..y1 on one side, z0..z1.
func _skin_band(sx: float, y0: float, y1: float, z0: float, z1: float, color: Color, lift := 0.006) -> void:
	var a0 := asin((y0 - HULL_CY) / HULL_R)
	var a1 := asin((y1 - HULL_CY) / HULL_R)
	var steps := maxi(1, ceili(absf(a1 - a0) / 0.1))
	for s in steps:
		var aa := lerpf(a0, a1, float(s) / steps)
		var ab := lerpf(a0, a1, float(s + 1) / steps)
		var p := [_skin(aa, z0, lift, sx), _skin(ab, z0, lift, sx), _skin(ab, z1, lift, sx), _skin(aa, z1, lift, sx)]
		var n := Vector3(cos((aa + ab) / 2) * sx, sin((aa + ab) / 2), 0)
		_ext.quad(p[0], p[1], p[2], p[3], n, color, PAINT)


## Thin outline (and handle) of a door painted on the outer skin.
func _door_outline(sx: float, z0: float, z1: float, y0: float, y1: float, with_window: bool) -> void:
	var w := 0.035
	var line := Color(0.35, 0.38, 0.45)
	_skin_band(sx, y0, y1, z0, z0 + w, line, 0.008)
	_skin_band(sx, y0, y1, z1 - w, z1, line, 0.008)
	_skin_band(sx, y0, y0 + 0.05, z0, z1, line, 0.008)
	_skin_band(sx, y1 - 0.05, y1, z0, z1, line, 0.008)
	_skin_band(sx, (y0 + y1) / 2 - 0.04, (y0 + y1) / 2 + 0.04, z1 - 0.3, z1 - 0.1, Color(0.85, 0.2, 0.15), 0.012)
	if with_window:
		var a := asin((y1 - 0.55 - HULL_CY) / HULL_R)
		var c := _skin(a, (z0 + z1) / 2, 0.01, sx)
		_ext.disc(MeshBatch.rounded_rect(0.34, 0.42, 0.14), Transform3D(_face_basis(Vector3(cos(a) * sx, sin(a), 0)), c),
			WINDSHIELD, GLOSS)


## Basis whose +Z faces along `n` with +Y kept as close to up as possible.
static func _face_basis(n: Vector3) -> Basis:
	var z := n.normalized()
	var up := Vector3.UP if absf(z.y) < 0.95 else Vector3.BACK
	var x := up.cross(z).normalized()
	return Basis(x, z.cross(x), z)


## Cheat lines, airline name, window surrounds and door outlines.
func _build_livery() -> void:
	var z0 := TUBE_START + 0.4
	for sx: float in [-1.0, 1.0]:
		for s in spans(z0, TAIL_Z - 0.3, [Vector2(EXIT_GAP.x - 0.05, EXIT_GAP.y + 0.05)]):
			_skin_band(sx, 0.86, 1.08, s.x, s.y, TRIM)
			_skin_band(sx, 0.74, 0.8, s.x, s.y, ACCENT)
		# Dark rounded surrounds around every window opening.
		for z: float in _window_zs():
			var w := _window_width(z)
			var a := asin((1.45 - HULL_CY) / HULL_R)
			var n := Vector3(cos(a) * sx, sin(a), 0)
			var c := _skin(a, z, 0.012, sx)
			var xf := Transform3D(_face_basis(n) * Basis(Vector3.BACK, PI / 2), c)
			_ext.ring(MeshBatch.rounded_rect(0.78, w + 0.16, 0.2), MeshBatch.rounded_rect(0.6, w - 0.02, 0.14),
				xf, Color(0.3, 0.34, 0.42), PAINT)
		_door_outline(sx, EXIT_GAP.x - 0.04, EXIT_GAP.y + 0.04, -0.02, 2.14, false)
		_door_outline(sx, -9.85, -8.95, 0.05, 2.0, true)
		_door_outline(sx, 11.25, 12.05, 0.05, 2.0, true)
		var name_x := hull_half_width(2.4, true) + 0.03
		_label("SKY-ISH AIRLINES", Vector3(sx * name_x, 2.4, -4.5), 130, TRIM, sx * PI / 2).outline_size = 0
		_label("probably fine™", Vector3(sx * name_x, 2.4, 4.0), 70, Color(0.4, 0.4, 0.45), sx * PI / 2).outline_size = 0
	_door_outline(1.0, 15.4, 18.2, 0.15, 2.2, false)   # Cargo door.
	# Belly fairing where the wings meet the fuselage.
	_ext.ellipsoid(Vector3(2.75, 0.75, 4.8), _at(Vector3(0, -1.2, 0.6)), HULL, PAINT, 24, 12)


func _build_floor_and_ceiling() -> void:
	var length := TAIL_Z - NOSE_Z
	var mid := (TAIL_Z + NOSE_Z) / 2.0
	var shell_w := 2.0 * (HALF_W + 0.2)
	_solid(Vector3(shell_w, 0.2, length), Vector3(0, -0.1, mid))
	_solid(Vector3(shell_w, 1.2, length), Vector3(0, -0.8, mid))
	_solid(Vector3(shell_w, 0.2, length), Vector3(0, CEIL + 0.1, mid))
	# Navy carpet with a dotted pattern and a lighter aisle runner (cockpit + cabin).
	var fz0 := NOSE_Z - 0.3
	var fz1 := LOUNGE_MIN.z - 0.2
	_int.box(Vector3(2.0 * HALF_W + 0.2, 0.2, fz1 - fz0), _at(Vector3(0, -0.1, (fz0 + fz1) / 2)), CARPET, FABRIC)
	_int.box(Vector3(1.5, 0.012, 15.6), _at(Vector3(0, 0.006, -2.0)), RUNNER, FABRIC)
	for sx: float in [-1.0, 1.0]:
		_int.box(Vector3(0.05, 0.014, 15.6), _at(Vector3(sx * 0.72, 0.007, -2.0)), ACCENT.darkened(0.2), FABRIC)
	var dot := CARPET.lightened(0.16)
	var z := -9.7
	while z < 5.9:
		for k in 13:
			var x := -2.4 + k * 0.4 + (0.2 if int((z + 10.0) / 0.4) % 2 == 1 else 0.0)
			if absf(x) > 0.8 and absf(x) < 2.5:
				var c := Vector3(x, 0.002, z)
				_int.quad(c + Vector3(-0.05, 0, 0), c + Vector3(0, 0, -0.05), c + Vector3(0.05, 0, 0), c + Vector3(0, 0, 0.05),
					Vector3.UP, dot, FABRIC)
		z += 0.4
	# Ceiling: cockpit + cabin (white with light strips), lounge and cargo in their batch.
	_int.box(Vector3(2.0 * hull_half_width(CEIL) - 0.1, 0.06, 13.3 + LOUNGE_MIN.z - 0.2),
		_at(Vector3(0, CEIL + 0.03, (-13.3 + LOUNGE_MIN.z - 0.2) / 2)), Color(0.97, 0.97, 0.98), MATTE)
	_aft.box(Vector3(2.0 * hull_half_width(CEIL) - 0.1, 0.06, TAIL_Z - LOUNGE_MIN.z + 0.2),
		_at(Vector3(0, CEIL + 0.03, (TAIL_Z + LOUNGE_MIN.z - 0.2) / 2)), Color(0.9, 0.9, 0.92), MATTE)
	for sx: float in [-1.0, 1.0]:
		_int.rounded_box(Vector3(0.1, 0.03, 15.5), _at(Vector3(sx * 1.32, CEIL - 0.005, -2.0)), LIGHT_STRIP, GLOW, 0.3, 8, 4)
		_int.rounded_box(Vector3(0.08, 0.03, 2.6), _at(Vector3(sx * 0.9, CEIL - 0.005, -11.5)), LIGHT_STRIP, GLOW, 0.3, 8, 4)
		_aft.rounded_box(Vector3(0.08, 0.03, 9.0), _at(Vector3(sx * 1.6, CEIL - 0.005, 17.0)), Color(0.85, 0.9, 1.0), GLOW, 0.3, 8, 4)


## Collision walls (invisible; the hull is the visible wall), glass panes, window bezels, exits.
func _build_walls() -> void:
	var window_zs := _window_zs()
	for sx in [-1, 1]:
		var x: float = sx * (HALF_W + 0.1)
		for s in spans(NOSE_Z, TAIL_Z, [EXIT_GAP]):
			_solid(Vector3(0.2, 1.1, s.y - s.x), Vector3(x, 0.55, (s.x + s.y) / 2))
			_solid(Vector3(0.2, 0.3, s.y - s.x), Vector3(x, 1.95, (s.x + s.y) / 2))
		_solid(Vector3(0.2, CEIL - 2.1, TAIL_Z - NOSE_Z), Vector3(x, (CEIL + 2.1) / 2.0, (TAIL_Z + NOSE_Z) / 2))
		var gaps := [EXIT_GAP]
		for wz: float in window_zs:
			gaps.append(Vector2(wz - _window_width(wz) / 2, wz + _window_width(wz) / 2))
		for s in spans(NOSE_Z, TAIL_Z, gaps):
			_solid(Vector3(0.2, 0.7, s.y - s.x), Vector3(x, 1.45, (s.x + s.y) / 2))
		for i in window_zs.size():
			var wz: float = window_zs[i]
			var w := _window_width(wz)
			# Glass sits recessed in the wall opening; its collider stays where it always was.
			_add_window(Vector3(0.05, 0.62, w), Vector3(sx * WINDOW_X, 1.45, wz),
				_at(Vector3(sx * 2.97, 1.45, wz)))
			_window_bezel(sx, wz, w, i)
		_build_exit_door(sx)
	# Front wall collision with the windshield panes (tilted back to lie under the glass band).
	var fz := NOSE_Z - 0.1
	var front_w := 2.0 * (HALF_W + 0.2)
	_solid(Vector3(front_w, 1.2, 0.2), Vector3(0, 0.6, fz))
	_solid(Vector3(front_w, CEIL - 2.0, 0.2), Vector3(0, (CEIL + 2.4) / 2.0, fz))
	for sx in [-1, 1]:
		_solid(Vector3(0.86, 1.0, 0.2), Vector3(sx * 2.37, 1.7, fz))
	_solid(Vector3(0.12, 1.0, 0.16), Vector3(0, 1.7, fz))
	var tilt := Basis(Vector3.RIGHT, 0.41)
	for px: float in [-1.0, 1.0]:
		_add_window(Vector3(1.88, 1.0, 0.05), Vector3(px, 1.7, fz), _at(Vector3(px, 1.72, -14.14), tilt))


## Big rounded window bezel on the inner wall, with a shade pulled part way down on some.
func _window_bezel(sx: int, z: float, w: float, i: int) -> void:
	var y := 1.45
	var x := sx * (hull_half_width(y) - 0.035)
	var xf := Transform3D(_face_basis(Vector3(-sx, 0, 0)) * Basis(Vector3.BACK, PI / 2), Vector3(x, y, z))
	var outer := MeshBatch.rounded_rect(0.98, w + 0.36, 0.26, 6)
	var inner := MeshBatch.rounded_rect(0.6, w - 0.03, 0.16, 6)
	var b := _int if z < LOUNGE_MIN.z else _aft
	b.ring(outer, inner, xf, Color(0.98, 0.98, 0.99), PAINT)
	# Lip from the bezel's inner edge back to the glass, and from its outer edge into the wall.
	var rows: Array[PackedVector3Array] = []
	for depth: float in [0.0, -0.14]:
		var row := PackedVector3Array()
		for p in inner:
			row.append(xf * Vector3(p.x, p.y, depth))
		rows.append(row)
	b.grid(rows, true, Color(0.9, 0.91, 0.93), PAINT, true)
	rows.clear()
	for depth: float in [0.0, -0.06]:
		var row := PackedVector3Array()
		for p in outer:
			row.append(xf * Vector3(p.x, p.y, depth))
		rows.append(row)
	b.grid(rows, true, Color(0.9, 0.91, 0.93), PAINT)
	if i % 3 == 1:
		b.box(Vector3(0.025, 0.22, w - 0.04), _at(Vector3(x + sx * 0.06, y + 0.19, z)), Color(0.93, 0.92, 0.88), MATTE)


func _add_window(size: Vector3, pos: Vector3, visual: Transform3D) -> void:
	var m := MeshInstance3D.new()
	m.mesh = _box_mesh(size, GLASS)
	m.transform = visual
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	var shape := _collider(size, pos)
	shape.set_meta("window", windows.size())
	windows.append({"mesh": m, "shape": shape, "broken": false, "pos": pos, "broke_at": -100.0})


## Over-wing emergency exit plug door: hull-white outside, cabin panel inside, window, handle.
func _build_exit_door(sx: int) -> void:
	var door_name := "left" if sx < 0 else "right"
	var center := Vector3(sx * 2.76, 1.03, 0)
	var size := Vector3(0.26, 2.05, 1.18)
	var b := MeshBatch.new()
	b.box(Vector3(0.2, 2.0, 1.12), Transform3D.IDENTITY, CABIN_GREY, MATTE)
	# Outer skin curved flush with the fuselage, so the closed door disappears into the hull.
	var rows: Array[PackedVector3Array] = []
	var a0 := asin((-0.02 - HULL_CY) / HULL_R)
	var a1 := asin((2.06 - HULL_CY) / HULL_R)
	for z: float in [-0.58, 0.58]:
		var row := PackedVector3Array()
		for s in 13:
			row.append(_skin(lerpf(a0, a1, s / 12.0), z, -0.004, sx) - center)
		rows.append(row)
	b.grid(rows, false, HULL, PAINT)
	b.rounded_box(Vector3(0.05, 1.96, 1.1), _at(Vector3(-sx * 0.11, 0, 0)), CABIN_WALL, MATTE, 0.2)
	var aw := asin((1.45 - HULL_CY) / HULL_R)
	var outer_x := _skin(aw, 0.0, 0.004, sx).x - center.x
	for side: float in [-1.0, 1.0]:
		var face := Transform3D(_face_basis(Vector3(side * sx, 0, 0)), Vector3(outer_x if side > 0 else -sx * 0.14, 0.42, 0))
		b.disc(MeshBatch.rounded_rect(0.4, 0.5, 0.16), face, WINDSHIELD, GLOSS)
	b.rounded_box(Vector3(0.06, 0.09, 0.55), _at(Vector3(-sx * 0.15, 0.17, 0)), Color(0.95, 0.25, 0.2), PAINT, 0.4)
	b.rounded_box(Vector3(0.02, 0.12, 0.3), _at(Vector3(-sx * 0.14, -0.15, 0)), ACCENT, PAINT, 0.3)
	var dm := MeshInstance3D.new()
	dm.mesh = b.commit()
	dm.position = center
	add_child(dm)
	var shape := _collider(size, center)
	var area := Interactable.make(Vector3(0.8, 2.0, 1.2), "", "door", [door_name])
	area.position = Vector3(sx * 2.35, 1.0, 0)
	add_child(area)
	doors[door_name] = {"mesh": dm, "shape": shape, "open": false, "area": area,
		"label": "the emergency exit", "pos": Vector3(sx * (HALF_W + 0.1), 1.0, 0)}
	set_door(door_name, false)
	_label("EXIT", Vector3(sx * 2.3, 2.6, 0), 56, Color(1, 0.25, 0.2), -sx * PI / 2)


## Partition across the tube at z: panel strips clipped to the inner hull (and floor..ceiling
## when trim) with rectangular holes [Rect2(x, y, w, h)], both faces plus hole jambs.
func _partition(b: MeshBatch, z: float, holes: Array[Rect2], trim: bool, front: Color, back: Color,
		r := HULL_R_IN + 0.01, thick := 0.12) -> void:
	var y_lo := 0.0 if trim else HULL_CY - r + 0.001
	var y_hi := CEIL if trim else HULL_CY + r - 0.001
	var ys: Array[float] = []
	var steps := 24
	for s in steps + 1:
		ys.append(lerpf(y_lo, y_hi, float(s) / steps))
	for h in holes:
		ys.append(clampf(h.position.y, y_lo, y_hi))
		ys.append(clampf(h.end.y, y_lo, y_hi))
	ys.sort()
	var hw := func(y: float) -> float: return sqrt(maxf(r * r - (y - HULL_CY) * (y - HULL_CY), 0.0))
	for k in ys.size() - 1:
		var ya := ys[k]
		var yb := ys[k + 1]
		if yb - ya < 0.001:
			continue
		var gaps := []
		for h in holes:
			if h.position.y <= ya + 0.0001 and h.end.y >= yb - 0.0001:
				gaps.append(Vector2(h.position.x, h.end.x))
		var wa: float = hw.call(ya)
		var wb: float = hw.call(yb)
		for s in spans(-maxf(wa, wb), maxf(wa, wb), gaps):
			var xa0 := maxf(s.x, -wa)
			var xb0 := maxf(s.x, -wb)
			var xa1 := minf(s.y, wa)
			var xb1 := minf(s.y, wb)
			for face: float in [-1.0, 1.0]:
				var zz := z + face * thick / 2
				b.quad(Vector3(xa0, ya, zz), Vector3(xa1, ya, zz), Vector3(xb1, yb, zz), Vector3(xb0, yb, zz),
					Vector3(0, 0, face), front if face < 0 else back, MATTE)
	for h in holes:
		var x0 := h.position.x
		var x1 := h.end.x
		var y0 := maxf(h.position.y, y_lo)
		var y1 := minf(h.end.y, y_hi)
		var za := z - thick / 2
		var zb := z + thick / 2
		var trim_c := Color(0.7, 0.72, 0.76)
		b.quad(Vector3(x0, y0, za), Vector3(x0, y1, za), Vector3(x0, y1, zb), Vector3(x0, y0, zb), Vector3.RIGHT, trim_c, SHINY)
		b.quad(Vector3(x1, y0, za), Vector3(x1, y1, za), Vector3(x1, y1, zb), Vector3(x1, y0, zb), Vector3.LEFT, trim_c, SHINY)
		if y1 < y_hi - 0.001:
			b.quad(Vector3(x0, y1, za), Vector3(x1, y1, za), Vector3(x1, y1, zb), Vector3(x0, y1, zb), Vector3.DOWN, trim_c, SHINY)


## Bulkhead with a centred doorway: visual partition plus invisible colliders.
func _bulkhead(b: MeshBatch, z: float, gap_half: float, gap_h: float, front: Color, back: Color) -> void:
	var holes: Array[Rect2] = [Rect2(-gap_half, -0.1, gap_half * 2, gap_h + 0.1)]
	_partition(b, z, holes, true, front, back)
	var side := HALF_W + 0.15 - gap_half
	for sx in [-1, 1]:
		_solid(Vector3(side, CEIL, 0.12), Vector3(sx * (gap_half + side / 2), CEIL / 2, z))
	_solid(Vector3(gap_half * 2, CEIL - gap_h, 0.12), Vector3(0, (CEIL + gap_h) / 2, z))


# --- Cockpit ------------------------------------------------------------------------------

func _build_cockpit() -> void:
	_bulkhead(_int, -10.0, 0.6, 2.1, Color(0.3, 0.33, 0.4), Color(0.84, 0.86, 0.9))
	_build_cockpit_door()
	_build_dashboard()
	_build_pedestal()
	_build_overhead()
	_build_status_screen()
	for p: Vector3 in [PILOT_SEAT, COPILOT_SEAT]:
		_pilot_seat(p)
		_yoke(p)
	# Side consoles under the side windows.
	for sx: float in [-1.0, 1.0]:
		_int.rounded_box(Vector3(0.28, 0.7, 2.2), _at(Vector3(sx * 2.42, 0.45, -12.4)), DASH, MATTE, 0.3)
		_int.rounded_box(Vector3(0.22, 0.04, 1.9), _at(Vector3(sx * 2.4, 0.81, -12.4)), DARK, GLOSS, 0.3, 8, 4)
		_int.cylinder(Vector3(sx * 2.4, 0.83, -12.9), Vector3(sx * 2.4, 0.9, -12.9), 0.07, 0.07, DARK, MATTE, 12)
	pilot_area = Interactable.make(Vector3(0.7, 1.2, 0.8), "Fly the plane (you totally can) [E]", "pilot_enter")
	pilot_area.position = PILOT_SEAT + Vector3(0, 0.3, 0)
	add_child(pilot_area)
	var co := Interactable.make(Vector3(0.7, 1.2, 0.8), "Sit in the co-pilot seat [E]", "sit")
	co.local_only = true
	co.set_meta("seat", COPILOT_SEAT)
	co.position = COPILOT_SEAT + Vector3(0, 0.3, 0)
	add_child(co)
	seat_areas.append(co)
	var photo := _label("CAPT. DAVE\n★ 2 STARS ★", Vector3(-2.5, 1.9, -11.2), 22, Color(0.2, 0.2, 0.2), PI / 2)
	photo.outline_size = 0


func _build_cockpit_door() -> void:
	var b := MeshBatch.new()
	b.rounded_box(Vector3(1.18, 2.08, 0.08), Transform3D.IDENTITY, Color(0.55, 0.58, 0.64), PAINT, 0.15)
	for face: float in [-1.0, 1.0]:
		b.rounded_box(Vector3(0.9, 0.7, 0.02), _at(Vector3(0, 0.45, face * 0.045)), Color(0.5, 0.53, 0.59), PAINT, 0.2)
		b.rounded_box(Vector3(0.9, 0.8, 0.02), _at(Vector3(0, -0.45, face * 0.045)), Color(0.5, 0.53, 0.59), PAINT, 0.2)
		b.cylinder(Vector3(0.42, -0.05, face * 0.04), Vector3(0.42, -0.05, face * 0.1), 0.03, 0.03, METAL, SHINY, 10)
		b.rounded_box(Vector3(0.16, 0.035, 0.035), _at(Vector3(0.36, -0.05, face * 0.11)), METAL, SHINY, 0.4, 8, 4)
	b.ellipsoid(Vector3(0.025, 0.025, 0.01), _at(Vector3(0, 0.55, 0.045)), DARK, GLOSS, 8, 4)
	b.rounded_box(Vector3(0.12, 0.18, 0.02), _at(Vector3(-0.42, 0.05, 0.05)), DARK, GLOSS, 0.3, 8, 4)
	b.box(Vector3(0.03, 0.03, 0.005), _at(Vector3(-0.42, 0.11, 0.062)), Color(0.2, 1.0, 0.4), GLOW)
	var dm := MeshInstance3D.new()
	dm.mesh = b.commit()
	dm.position = Vector3(0, 1.05, -10.0)
	add_child(dm)
	var shape := _collider(Vector3(1.2, 2.1, 0.08), Vector3(0, 1.05, -10.0))
	var area := Interactable.make(Vector3(1.2, 2.0, 1.6), "", "door", ["cockpit"])
	area.position = Vector3(0, 1.0, -10.0)
	add_child(area)
	doors["cockpit"] = {"mesh": dm, "shape": shape, "open": false, "area": area,
		"label": "the cockpit door", "pos": Vector3(0, 1.0, -10.0)}
	set_door("cockpit", false)
	_label("CREW ONLY", Vector3(0, 2.35, -9.92), 40, Color(1, 0.9, 0.3))
	_label("(seriously)", Vector3(0, 2.18, -9.92), 22, Color(1, 0.9, 0.3))


## Chunky retro dashboard: rounded body, glare shield up to the glass, round gauges.
func _build_dashboard() -> void:
	_solid(Vector3(4.6, 1.0, 0.7), Vector3(0, 0.5, -13.55))
	_int.rounded_box(Vector3(4.9, 1.05, 1.0), _at(Vector3(0, 0.5, -13.7)), DASH, MATTE, 0.25)
	_int.rounded_box(Vector3(5.0, 0.16, 1.25), _at(Vector3(0, 1.12, -13.78)), DARK, MATTE, 0.35)
	var face := Transform3D(Basis(Vector3.RIGHT, -0.32), Vector3(0, 0.78, -13.2))
	_int.rounded_box(Vector3(4.4, 0.6, 0.12), face, Color(0.19, 0.21, 0.26), MATTE, 0.25)
	# Gauge clusters in front of each pilot, engine gauges in the middle.
	for cx: float in [-0.75, 0.75]:
		_attitude_ball(face * _at(Vector3(cx, 0.04, 0.07)))
		for g in 4:
			var gx: float = cx + [-0.42, -0.24, 0.24, 0.42][g]
			_gauge(face * _at(Vector3(gx, 0.11 if g % 3 == 0 else -0.08, 0.07)), 0.075, g)
	for g in 4:
		_gauge(face * _at(Vector3(-0.18 + (g % 2) * 0.36, 0.13 - (g / 2) * 0.2, 0.07)), 0.085, g + 2)
	for gx: float in [-1.85, 1.85]:
		_gauge(face * _at(Vector3(gx, 0.0, 0.07)), 0.09, 1)
	_int.cylinder(Vector3(0, 1.2, -13.32), Vector3(0, 1.25, -13.32), 0.09, 0.09, Color(0.9, 0.12, 0.12), PAINT, 16)
	_label("DO NOT\nPRESS", Vector3(0, 1.26, -13.32), 18, Color.WHITE).rotation.x = -PI / 2
	# Rudder pedals.
	for p: Vector3 in [PILOT_SEAT, COPILOT_SEAT]:
		for dx: float in [-0.13, 0.13]:
			_int.rounded_box(Vector3(0.1, 0.2, 0.05), _at(Vector3(p.x + dx, 0.14, -13.2), Basis(Vector3.RIGHT, -0.5)), DARK, MATTE, 0.3, 8, 4)


## Round dial: chrome bezel, cream face, ticks and a needle (angle varies by index).
func _gauge(xf: Transform3D, r: float, k: int) -> void:
	_int.cylinder(xf.origin - xf.basis.z * 0.02, xf.origin + xf.basis.z * 0.025, r + 0.018, r + 0.012, METAL, SHINY, 18)
	var face := xf * _at(Vector3(0, 0, 0.026))
	var circle := PackedVector2Array()
	for s in 18:
		circle.append(Vector2(cos(TAU * s / 18), sin(TAU * s / 18)) * r)
	_int.disc(circle, face, Color(0.96, 0.94, 0.86), GLOW)
	for t in 8:
		var a := PI * 1.25 - t * PI * 1.5 / 7
		_int.box(Vector3(0.006, 0.018, 0.002), face * _at(Vector3(cos(a), sin(a), 0) * r * 0.8, Basis(Vector3.BACK, a - PI / 2)), DARK, MATTE)
	var na := PI * 1.25 - fmod(k * 1.7, 4.0)
	_int.box(Vector3(0.008, r * 0.8, 0.003), face * _at(Vector3(cos(na), sin(na), 0) * r * 0.35 + Vector3(0, 0, 0.003), Basis(Vector3.BACK, na - PI / 2)),
		Color(0.95, 0.3, 0.1), GLOW)


## Artificial horizon: blue sky over brown ground with a yellow aircraft symbol.
func _attitude_ball(xf: Transform3D) -> void:
	var r := 0.12
	_int.cylinder(xf.origin - xf.basis.z * 0.02, xf.origin + xf.basis.z * 0.03, r + 0.02, r + 0.014, METAL, SHINY, 20)
	var face := xf * _at(Vector3(0, 0, 0.031))
	var sky := PackedVector2Array([Vector2.ZERO])
	var ground := PackedVector2Array([Vector2.ZERO])
	for s in 11:
		var a := PI * s / 10
		sky.append(Vector2(cos(a), sin(a)) * r)
		ground.append(Vector2(cos(a + PI), sin(a + PI)) * r)
	_int.disc(sky, face, Color(0.25, 0.6, 1.0), GLOW)
	_int.disc(ground, face, Color(0.6, 0.38, 0.18), GLOW)
	_int.box(Vector3(r * 2, 0.006, 0.002), face * _at(Vector3(0, 0, 0.002)), Color.WHITE, GLOW)
	_int.box(Vector3(0.1, 0.012, 0.003), face * _at(Vector3(0, 0, 0.004)), ACCENT, GLOW)


## Centre throttle quadrant between the seats.
func _build_pedestal() -> void:
	_solid(Vector3(0.35, 0.25, 0.5), Vector3(0, 0.95, -12.95))
	_int.rounded_box(Vector3(0.52, 0.9, 1.0), _at(Vector3(0, 0.45, -12.9)), DASH, MATTE, 0.3)
	_int.rounded_box(Vector3(0.44, 0.22, 0.58), _at(Vector3(0, 0.95, -12.95), Basis(Vector3.RIGHT, 0.15)), Color(0.19, 0.21, 0.26), MATTE, 0.3)
	for i in 2:
		var x := -0.08 + i * 0.16
		_int.cylinder(Vector3(x, 1.02, -12.95), Vector3(x, 1.3, -13.05), 0.018, 0.018, METAL, SHINY, 8)
		_int.ellipsoid(Vector3(0.05, 0.04, 0.05), _at(Vector3(x, 1.32, -13.06)), DARK, GLOSS, 10, 6)
	_int.cylinder(Vector3(0.17, 1.02, -12.8), Vector3(0.17, 1.18, -12.82), 0.012, 0.012, METAL, SHINY, 8)
	_int.rounded_box(Vector3(0.07, 0.04, 0.05), _at(Vector3(0.17, 1.19, -12.82)), Color(0.95, 0.95, 0.95), PAINT, 0.3, 8, 4)
	_int.rounded_box(Vector3(0.3, 0.12, 0.02), _at(Vector3(0, 0.85, -12.38), Basis(Vector3.RIGHT, -0.2)), DARK, GLOSS, 0.2, 8, 4)
	_int.box(Vector3(0.26, 0.08, 0.004), _at(Vector3(0, 0.852, -12.37), Basis(Vector3.RIGHT, -0.2)), Color(0.3, 1.0, 0.45), GLOW)


## Overhead switch panel with chunky toggles and glowing annunciators.
func _build_overhead() -> void:
	var xf := Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, CEIL - 0.06, -12.4))
	_int.rounded_box(Vector3(1.6, 0.1, 1.2), xf, Color(0.3, 0.32, 0.37), MATTE, 0.25)
	var cols := [ACCENT, Color(0.2, 0.95, 0.35), Color(0.95, 0.2, 0.2), Color(0.3, 0.7, 1.0)]
	for i in 18:
		var px := -0.6 + (i % 6) * 0.24
		var pz := -0.4 + (i / 6) * 0.3
		_int.cylinder(xf * Vector3(px, -0.05, pz), xf * Vector3(px, -0.11, pz + 0.02), 0.014, 0.01, METAL, SHINY, 6)
		_int.box(Vector3(0.08, 0.008, 0.04), xf * _at(Vector3(px, -0.054, pz + 0.09)), cols[i % 4], GLOW)


## Overhead "AIRPLANE STATUS" screen: plane silhouette whose parts colour with damage.
func _build_status_screen() -> void:
	var xf := Transform3D(Basis(Vector3.RIGHT, 0.75), Vector3(0, 2.5, -13.35))
	_int.rounded_box(Vector3(1.0, 0.62, 0.08), xf, DASH, MATTE, 0.25)
	_int.rounded_box(Vector3(0.9, 0.52, 0.02), xf * _at(Vector3(0, 0, 0.04)), Color(0.03, 0.05, 0.08), GLOSS, 0.15, 8, 4)
	_int.cylinder(xf * Vector3(-0.3, 0.3, 0), Vector3(-0.3, CEIL, -13.15), 0.02, 0.02, METAL, SHINY, 6, false)
	_int.cylinder(xf * Vector3(0.3, 0.3, 0), Vector3(0.3, CEIL, -13.15), 0.02, 0.02, METAL, SHINY, 6, false)
	var lbl := _label("AIRPLANE STATUS", xf * Vector3(0, 0.21, 0.055), 20, Color(0.6, 0.85, 1.0))
	lbl.basis = xf.basis
	lbl.outline_size = 0
	var icon := xf * _at(Vector3(0, -0.03, 0.054))
	# Silhouette seen from above: nose up the screen.
	var parts := {
		"hull": [Vector3(0.09, 0.4, 0.004), Vector3(0, 0.0, 0), 0.6],
		"wing0": [Vector3(0.24, 0.06, 0.004), Vector3(-0.16, 0.03, 0), 0.4],
		"wing1": [Vector3(0.24, 0.06, 0.004), Vector3(0.16, 0.03, 0), 0.4],
		"engine0": [Vector3(0.045, 0.1, 0.006), Vector3(-0.14, 0.06, 0.003), 0.6],
		"engine1": [Vector3(0.045, 0.1, 0.006), Vector3(0.14, 0.06, 0.003), 0.6],
		"tail": [Vector3(0.18, 0.045, 0.004), Vector3(0, -0.16, 0.002), 0.4],
	}
	for part: String in parts:
		var spec: Array = parts[part]
		var b := MeshBatch.new()
		b.rounded_box(spec[0], _at(spec[1]), Color.WHITE, GLOW, spec[2], 12, 4)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = _health_color(1.0)
		var mi := MeshInstance3D.new()
		mi.mesh = b.commit()
		mi.material_override = m
		mi.transform = icon
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_status_mats[part] = m


func _pilot_seat(p: Vector3) -> void:
	_solid(Vector3(0.6, 0.45, 0.6), Vector3(p.x, 0.22, p.z))
	_solid(Vector3(0.6, 1.0, 0.14), Vector3(p.x, 0.95, p.z + 0.32))
	_int.cylinder(Vector3(p.x, 0, p.z), Vector3(p.x, 0.32, p.z), 0.12, 0.08, METAL, SHINY, 12)
	_int.rounded_box(Vector3(0.62, 0.18, 0.6), _at(Vector3(p.x, 0.41, p.z)), LEATHER, PAINT, 0.4)
	var back := Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(p.x, 0.48, p.z + 0.3))
	_int.rounded_box(Vector3(0.6, 0.98, 0.17), back * _at(Vector3(0, 0.48, 0.02)), LEATHER, PAINT, 0.4)
	_int.rounded_box(Vector3(0.44, 0.26, 0.17), back * _at(Vector3(0, 1.07, 0.03)), LEATHER.darkened(0.15), PAINT, 0.45)
	for sx: float in [-1.0, 1.0]:
		_int.rounded_box(Vector3(0.08, 0.08, 0.46), _at(Vector3(p.x + sx * 0.34, 0.72, p.z - 0.02)), LEATHER.darkened(0.2), PAINT, 0.4, 10, 6)
		_int.box(Vector3(0.07, 0.62, 0.012), back * _at(Vector3(sx * 0.14, 0.62, -0.08)), Color(0.2, 0.22, 0.26), MATTE)


func _yoke(p: Vector3) -> void:
	var c := Vector3(p.x, 1.0, p.z - 0.72)
	_int.cylinder(Vector3(p.x, 0.55, p.z - 0.95), c + Vector3(0, -0.05, 0), 0.035, 0.035, DARK, MATTE, 10)
	_int.ellipsoid(Vector3(0.06, 0.05, 0.05), _at(c), DARK, GLOSS, 10, 6)
	_int.cylinder(c + Vector3(-0.17, 0, 0), c + Vector3(0.17, 0, 0), 0.025, 0.025, DARK, MATTE, 10)
	for sx: float in [-1.0, 1.0]:
		_int.cylinder(c + Vector3(sx * 0.17, -0.03, 0), c + Vector3(sx * 0.17, 0.13, 0), 0.032, 0.032, Color(0.2, 0.2, 0.22), MATTE, 10)
		_int.ellipsoid(Vector3(0.032, 0.025, 0.032), _at(c + Vector3(sx * 0.17, 0.13, 0)), Color(0.85, 0.15, 0.12), GLOSS, 8, 4)


# --- Cabin --------------------------------------------------------------------------------

func _build_cabin() -> void:
	var seat_b := MeshBatch.new()
	PlaneModels.seat(seat_b)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = seat_b.commit()
	mm.instance_count = ROW_Z.size() * SEAT_X.size()
	var anchors := PackedVector3Array()
	var hatches: Array[Transform3D] = []
	var k := 0
	for z: float in ROW_Z:
		for x: float in SEAT_X:
			mm.set_instance_transform(k, _at(Vector3(x, 0, z)))
			k += 1
			_solid(Vector3(0.5, 0.48, 0.5), Vector3(x, 0.24, z))
			_solid(Vector3(0.5, 0.85, 0.14), Vector3(x, 0.85, z + 0.27))
			var seat := Vector3(x, 0.5, z)
			seats.append(seat)
			anchors.append(Vector3(x, 2.41, z - 0.2))
			var area := Interactable.make(Vector3(0.45, 0.5, 0.45), "Sit down [E]", "sit")
			area.local_only = true
			area.set_meta("seat", seat)
			area.position = seat + Vector3(0, 0.15, 0)
			add_child(area)
			seat_areas.append(area)
		for sx: float in [-1.0, 1.0]:
			_service_unit(sx, z)
			hatches.append(_at(Vector3(sx * 1.78, 2.425, z + 0.04), Basis(Vector3.RIGHT, -1.2)))
		_label("%d" % (ROW_Z.find(z) + 1), Vector3(-1.4, 2.62, z), 30, Color(0.25, 0.25, 0.3), PI / 2)
	var seats_mi := MultiMeshInstance3D.new()
	seats_mi.multimesh = mm
	seats_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(seats_mi)
	for i in 16:
		aisle_points.append(Vector3(0, 0.0, -9.5 + i))
	_build_bins()
	_build_galley()
	_label("PLEASE REMAIN SEATED", Vector3(0, 2.6, -9.93), 30, Color(0.9, 0.9, 0.9))
	_label("(lol)", Vector3(0, 2.45, -9.93), 20, Color(0.9, 0.9, 0.9))
	_masks = OxygenMasks.new()
	add_child(_masks)
	_masks.setup(self, anchors, hatches)


## Overhead bins: a curved shell running the cabin length, door seams and handles per row.
func _build_bins() -> void:
	var z0 := -9.75
	var z1 := 5.75
	for sx: float in [-1.0, 1.0]:
		var prof := PackedVector2Array()
		for p in [Vector2(2.3, 2.97), Vector2(1.58, 2.99), Vector2(1.47, 2.93), Vector2(1.41, 2.8),
				Vector2(1.41, 2.62), Vector2(1.46, 2.48), Vector2(1.58, 2.43), Vector2(2.62, 2.43)]:
			prof.append(Vector2(p.x * sx, p.y))
		var xfs: Array[Transform3D] = [_at(Vector3(0, 0, z0)), _at(Vector3(0, 0, z1))]
		_int.sweep(prof, xfs, Color(0.9, 0.91, 0.94), PAINT)
		# Door seams between rows, handles along the lower lip.
		var seams: Array[float] = [z0 + 0.02]
		for i in ROW_Z.size() - 1:
			seams.append((float(ROW_Z[i]) + float(ROW_Z[i + 1])) / 2.0)
		seams.append(z1 - 0.02)
		for i in seams.size():
			var z: float = seams[i]
			_int.box(Vector3(0.012, 0.5, 0.012), _at(Vector3(sx * 1.408, 2.71, z)), Color(0.55, 0.57, 0.62), MATTE)
			if i < seams.size() - 1:
				var mid := (z + seams[i + 1]) / 2.0
				_int.rounded_box(Vector3(0.03, 0.04, 0.22), _at(Vector3(sx * 1.43, 2.52, mid)), CABIN_GREY, SHINY, 0.4, 8, 4)


## Passenger service unit under the bins above a row: reading lights, gasper vents, the
## seatbelt sign and the oxygen-mask hatch outline.
func _service_unit(sx: float, z: float) -> void:
	_int.rounded_box(Vector3(1.0, 0.03, 0.42), _at(Vector3(sx * 1.98, 2.415, z - 0.1)), Color(0.88, 0.89, 0.92), PAINT, 0.2, 8, 4)
	for x: float in [1.45, 2.05]:
		_int.cylinder(Vector3(sx * x, 2.4, z - 0.02), Vector3(sx * x, 2.39, z - 0.02), 0.035, 0.03, LIGHT_STRIP, GLOW, 10)
		_int.cylinder(Vector3(sx * x + 0.1 * sx, 2.4, z + 0.04), Vector3(sx * x + 0.1 * sx, 2.37, z + 0.04), 0.022, 0.016, CABIN_GREY, SHINY, 8)
	_int.rounded_box(Vector3(0.18, 0.012, 0.07), _at(Vector3(sx * 1.75, 2.398, z + 0.06)), Color(0.15, 0.6, 1.0), GLOW, 0.3, 8, 4)
	# Mask hatch outline.
	for dz: float in [-0.26, 0.04]:
		_int.box(Vector3(0.86, 0.004, 0.008), _at(Vector3(sx * 1.78, 2.399, z + dz)), Color(0.6, 0.62, 0.66), MATTE)


## Front galley: steel cabinets with door seams, worktop, ovens and a coffee maker.
func _build_galley() -> void:
	for sx: float in [-1.0, 1.0]:
		var c := Vector3(sx * 2.05, 0.5, -9.6)
		_solid(Vector3(1.0, 1.0, 0.5), c)
		_int.rounded_box(Vector3(1.0, 0.98, 0.5), _at(c), Color(0.82, 0.84, 0.87), SHINY, 0.12)
		for dx: float in [-0.25, 0.0, 0.25]:
			_int.box(Vector3(0.01, 0.8, 0.01), _at(Vector3(c.x + dx, 0.52, -9.348)), Color(0.45, 0.47, 0.5), MATTE)
		for dx: float in [-0.37, -0.12, 0.12, 0.37]:
			_int.rounded_box(Vector3(0.1, 0.025, 0.03), _at(Vector3(c.x + dx, 0.85, -9.34)), DARK, GLOSS, 0.4, 8, 4)
		_int.rounded_box(Vector3(1.06, 0.05, 0.56), _at(Vector3(c.x, 1.02, -9.6)), Color(0.28, 0.3, 0.34), GLOSS, 0.25, 10, 4)
		# Upper unit against the bulkhead.
		_int.rounded_box(Vector3(0.96, 0.8, 0.28), _at(Vector3(c.x, 1.88, -9.8)), Color(0.9, 0.91, 0.93), PAINT, 0.15)
		_int.rounded_box(Vector3(0.36, 0.3, 0.02), _at(Vector3(c.x - 0.22 * sx, 1.98, -9.655)), DARK, GLOSS, 0.2, 8, 4)
		_int.box(Vector3(0.04, 0.02, 0.005), _at(Vector3(c.x + 0.24 * sx, 1.72, -9.638)), Color(1.0, 0.3, 0.2), GLOW)
		# Manifest board on the right galley counter (sx=1.0), facing the aisle.
		if sx == 1.0:
			var board_pos := Vector3(c.x - 0.4, 1.3, -9.55)
			var board_size := Vector3(0.6, 0.7, 0.1)
			_int.rounded_box(board_size, _at(board_pos), Color(0.15, 0.18, 0.25), MATTE, 0.08)
			# Clipboard clip
			_int.box(Vector3(0.08, 0.02, 0.01), _at(Vector3(board_pos.x, board_pos.y + 0.32, board_pos.z + 0.06)), Color(0.4, 0.4, 0.5), MATTE)
			# Paper
			_int.box(Vector3(0.45, 0.55, 0.005), _at(Vector3(board_pos.x, board_pos.y - 0.02, board_pos.z + 0.06)), Color(0.95, 0.95, 0.92), MATTE)
			# Label
			_label("MANIFEST", Vector3(board_pos.x, board_pos.y + 0.2, board_pos.z + 0.08), 18, Color(1, 0.8, 0.2))
			# Interactable area
			var area := Interactable.make(Vector3(0.7, 0.9, 0.5), "Open Manifest [E]", "", [])
			area.local_only = true
			area.position = board_pos
			area.name = "ManifestBoard"
			add_child(area)
			manifest_board = area


# --- Lounge -------------------------------------------------------------------------------

## Empty, carpeted lounge between cabin and cargo; the Fun module furnishes it.
func _build_lounge() -> void:
	_bulkhead(_aft, LOUNGE_MIN.z - 0.2, DOOR_GAP_HALF, 2.4, Color(0.86, 0.87, 0.9), Color(0.55, 0.38, 0.6))
	_label("LOUNGE", Vector3(0, 2.65, LOUNGE_MIN.z - 0.27), 46, ACCENT, PI)
	_label("LOUNGE", Vector3(0, 2.65, LOUNGE_MIN.z - 0.13), 46, ACCENT)
	var mid := (LOUNGE_MIN.z + LOUNGE_MAX.z) / 2.0
	var length := LOUNGE_MAX.z - LOUNGE_MIN.z + 0.4
	_aft.box(Vector3(2.0 * HALF_W + 0.2, 0.2, length), _at(Vector3(0, -0.1 + 0.007, mid)), Color(0.42, 0.2, 0.42), FABRIC)
	for i in 6:
		_aft.box(Vector3(2.0 * HALF_W - 0.4, 0.016, 0.06), _at(Vector3(0, 0.008, LOUNGE_MIN.z + 0.4 + i * 1.0)), ACCENT, FABRIC)
	for sx: float in [-1.0, 1.0]:
		_aft.rounded_box(Vector3(0.05, 0.08, length), _at(Vector3(sx * (hull_half_width(2.3) - 0.03), 2.3, mid)), Color(0.9, 0.5, 1.0), GLOW, 0.4, 8, 4)


# --- Cargo hold ---------------------------------------------------------------------------

func _build_cargo() -> void:
	var z0 := CARGO_MIN.z - 1.0
	_bulkhead(_aft, z0, DOOR_GAP_HALF, 2.4, Color(0.55, 0.38, 0.6), Color(0.6, 0.62, 0.64))
	_label("CARGO", Vector3(0, 2.65, z0 - 0.07), 48, ACCENT, PI)
	_label("CARGO", Vector3(0, 2.65, z0 + 0.07), 48, ACCENT)
	var mid := (z0 + TAIL_Z) / 2.0
	_aft.box(Vector3(2.0 * HALF_W + 0.2, 0.2, TAIL_Z - z0), _at(Vector3(0, -0.1 + 0.006, mid)), Color(0.32, 0.33, 0.35), MATTE)
	for i in 4:
		_aft.box(Vector3(2.0 * HALF_W - 0.2, 0.014, 0.3), _at(Vector3(0, 0.007, z0 + 1.5 + i * 2.4)), ACCENT, MATTE)
	for sx: float in [-1.0, 1.0]:
		_aft.box(Vector3(0.06, 0.03, TAIL_Z - z0), _at(Vector3(sx * 1.6, 0.015, mid)), METAL, SHINY)
	# Structural frames arching up the cargo walls.
	var fz := z0 + 0.6
	while fz < TAIL_Z - 0.3:
		for s in 10:
			var ya := lerpf(0.05, CEIL, float(s) / 10)
			var yb := lerpf(0.05, CEIL, float(s + 1) / 10)
			for sx: float in [-1.0, 1.0]:
				var a := Vector3(sx * (hull_half_width(ya) - 0.04), ya, fz)
				var b := Vector3(sx * (hull_half_width(yb) - 0.04), yb, fz)
				_aft.box(Vector3(0.08, a.distance_to(b) + 0.02, 0.1),
					_at((a + b) / 2, Basis(Vector3.BACK, atan2(-(b - a).x, (b - a).y))), Color(0.56, 0.58, 0.62), SHINY)
		fz += 1.6
	_build_ramp()
	_ramp_lever = Interactable.make(Vector3(0.5, 0.8, 0.5), "", "ramp")
	_ramp_lever.position = RAMP_LEVER
	add_child(_ramp_lever)
	_aft.rounded_box(Vector3(0.2, 0.5, 0.3), _at(RAMP_LEVER + Vector3(0.12, -0.1, 0)), Color(0.3, 0.3, 0.32), PAINT, 0.25)
	_aft.cylinder(RAMP_LEVER + Vector3(0, -0.05, 0), RAMP_LEVER + Vector3(0, 0.42, 0), 0.025, 0.025, Color(0.85, 0.1, 0.1), PAINT, 8)
	_aft.ellipsoid(Vector3(0.06, 0.06, 0.06), _at(RAMP_LEVER + Vector3(0, 0.44, 0)), Color(0.85, 0.1, 0.1), GLOSS, 10, 6)
	_label("RAMP", RAMP_LEVER + Vector3(0.18, 0.45, 0), 32, Color(1, 0.3, 0.3), -PI / 2)
	# Rear cap around the ramp opening (outside white, inside grey).
	var ramp_w := 2.0 * HALF_W + 0.2
	var hole: Array[Rect2] = [Rect2(-(ramp_w + 0.1) / 2, -0.05, ramp_w + 0.1, CEIL + 0.1)]
	_partition(_ext, TAIL_Z + 0.05, hole, false, Color(0.6, 0.62, 0.64), HULL, HULL_R + 0.005)
	_solid(Vector3(ramp_w + 0.2, 0.6, 0.12), Vector3(0, CEIL + 0.3, TAIL_Z + 0.05))
	set_ramp(false)


## Rear ramp: ribbed plate with hazard stripes along its free edge.
func _build_ramp() -> void:
	var ramp_w := 2.0 * HALF_W + 0.2
	var b := MeshBatch.new()
	b.rounded_box(Vector3(ramp_w, CEIL, 0.15), Transform3D.IDENTITY, Color(0.55, 0.57, 0.6), PAINT, 0.1)
	for i in 5:
		b.rounded_box(Vector3(ramp_w - 0.2, 0.06, 0.05), _at(Vector3(0, -1.2 + i * 0.6, -0.09)), Color(0.4, 0.42, 0.45), SHINY, 0.3, 8, 4)
	for i in 10:
		var x := -ramp_w / 2 + 0.27 + i * (ramp_w - 0.54) / 9
		b.box(Vector3(0.25, 0.16, 0.02), _at(Vector3(x, CEIL / 2 - 0.12, -0.08), Basis(Vector3.BACK, 0.5)), ACCENT if i % 2 == 0 else DARK, PAINT)
	b.box(Vector3(ramp_w * 0.92, 0.02, 0.02), _at(Vector3(0, 0, 0.085)), HULL, PAINT)
	_ramp_mesh = MeshInstance3D.new()
	_ramp_mesh.mesh = b.commit()
	add_child(_ramp_mesh)
	_ramp_shape = _collider(Vector3(ramp_w, CEIL, 0.15), Vector3.ZERO)


func _ramp_transform(open: bool) -> Transform3D:
	var hinge := Vector3(0, 0, TAIL_Z + 0.08)
	var angle := deg_to_rad(110.0) if open else 0.0
	var b := Basis(Vector3.RIGHT, angle)
	return Transform3D(b, hinge + b * Vector3(0, CEIL / 2.0, 0))


# --- Wings, engines, tail, gear -----------------------------------------------------------

## Station transform for a spanwise airfoil: profile X = chord (toward +Z), profile Y = up.
static func _wing_station(x: float, y: float, le_z: float, chord: float, thick: float) -> Transform3D:
	return Transform3D(Basis(Vector3(0, 0, chord), Vector3(0, chord * thick / 0.12, 0), Vector3(1, 0, 0)), Vector3(x, y, le_z))


func _build_wings() -> void:
	var foil := PlaneModels.airfoil(1.0, 0.12, 0.02, 10)
	for sx: float in [-1.0, 1.0]:
		_solid(Vector3(13.0, 0.3, 3.6), Vector3(sx * 8.8, -0.5, 0.7))
		# Tapered, swept leading edge; flat-ish top so standing on the wing matches the collider.
		var rows: Array[Transform3D] = []
		for st in [[2.0, -1.4, 0.34], [3.4, -1.3, 0.32], [7.5, -1.0, 0.27], [12.5, -0.6, 0.2], [15.2, -0.35, 0.16]]:
			var x: float = sx * st[0]
			var le: float = st[1]
			var chord := 2.45 - le
			var thick: float = st[2] / chord
			rows.append(_wing_station(x, -0.34 - st[2] * 0.62, le, chord, thick))
		_ext.sweep(foil, rows, HULL, PAINT)
		_ext.box(Vector3(12.0, 0.02, 0.18), _at(Vector3(sx * 9.0, -0.335, -0.55), Basis(Vector3.UP, sx * 0.07)), TRIM, PAINT)
		# Flaps (move with set_flaps) and a static aileron further out.
		var pivot := Node3D.new()
		pivot.position = Vector3(sx * 7.8, -0.55, 2.45)
		add_child(pivot)
		var flap := MeshBatch.new()
		flap.rounded_box(Vector3(9.0, 0.08, 0.9), _at(Vector3(0, 0, 0.45)), Color(0.86, 0.88, 0.9), PAINT, 0.25, 12, 6)
		var fm := MeshInstance3D.new()
		fm.mesh = flap.commit()
		pivot.add_child(fm)
		_flap_pivots.append(pivot)
		_ext.rounded_box(Vector3(2.8, 0.07, 0.85), _at(Vector3(sx * 13.75, -0.47, 2.86)), Color(0.86, 0.88, 0.9), PAINT, 0.25, 12, 6)
		# Upswept winglet.
		var wl: Array[Transform3D] = []
		for st in [[15.15, -0.42, -0.25, 2.6], [15.45, 0.25, 0.45, 1.8], [15.65, 1.0, 1.15, 1.1]]:
			var c: float = st[3]
			wl.append(Transform3D(Basis(Vector3(0, 0, c), Vector3(sx * c * 0.6, 0, 0), Vector3(0, 1, 0)),
				Vector3(sx * st[0], st[1], st[2])))
		_ext.sweep(foil, wl, TRIM, PAINT)
		_ext.ellipsoid(Vector3(0.1, 0.07, 0.14), _at(Vector3(sx * 15.25, -0.38, -0.2)),
			Color(1, 0.15, 0.1) if sx < 0 else Color(0.15, 1, 0.3), GLOW, 10, 6)
		_label("NO STEP", Vector3(sx * 5.0, -0.32, 1.8), 64, Color(0.2, 0.2, 0.2)).rotation.x = -PI / 2
		_label("(please)", Vector3(sx * 5.0, -0.32, 2.25), 36, Color(0.2, 0.2, 0.2)).rotation.x = -PI / 2
		# Grab handles to cling to.
		for hz: float in [0.2, 1.6]:
			_ext.cylinder(Vector3(sx * 3.1, -0.31, hz), Vector3(sx * 3.7, -0.31, hz), 0.035, 0.035, ACCENT, PAINT, 8)
		_build_engine(0 if sx < 0 else 1)


## Turboprop nacelle slung under the wing with a spinning four-blade propeller.
func _build_engine(i: int) -> void:
	var ep: Vector3 = ENGINE_POS[i]
	_solid(Vector3(1.44, 1.44, 3.0), ep)
	var prof := PackedVector2Array([Vector2(-1.72, 0.0), Vector2(-1.72, 0.3), Vector2(-1.62, 0.47),
		Vector2(-1.35, 0.58), Vector2(-0.8, 0.64), Vector2(0.3, 0.63), Vector2(1.1, 0.5),
		Vector2(1.7, 0.3), Vector2(1.85, 0.18), Vector2(1.85, 0.0)])
	_ext.revolve(prof, _at(ep), HULL, PAINT, 24)
	_ext.revolve(PackedVector2Array([Vector2(-1.4, 0.586), Vector2(-1.25, 0.6), Vector2(-1.1, 0.612),
		Vector2(-0.95, 0.62)]), _at(ep), TRIM, PAINT, 24)
	# Chin intake, exhaust stubs, pylon fairing up into the wing.
	_ext.ellipsoid(Vector3(0.2, 0.12, 0.42), _at(ep + Vector3(0, -0.52, -1.0)), DARK, MATTE, 12, 6)
	for sx: float in [-1.0, 1.0]:
		_ext.cylinder(ep + Vector3(sx * 0.5, 0.2, -0.1), ep + Vector3(sx * 0.66, 0.24, 0.45), 0.09, 0.08, Color(0.3, 0.3, 0.33), SHINY, 10)
	var foil := PlaneModels.airfoil(1.0, 0.12, 0.0, 8)
	var py: Array[Transform3D] = []
	for st in [[-0.62, -1.3, 3.0], [-0.42, -1.1, 3.4]]:
		var c: float = st[2]
		py.append(Transform3D(Basis(Vector3(0, 0, c), Vector3(0.25 / 0.12, 0, 0), Vector3(0, 1, 0)),
			Vector3(ep.x, st[0], st[1] + 0.3)))
	_ext.sweep(foil, py, HULL, PAINT)
	# Propeller (spins in _process) with a faint blur disc.
	var prop := Node3D.new()
	prop.position = ep + Vector3(0, 0, -1.78)
	add_child(prop)
	var pb := MeshBatch.new()
	PlaneModels.propeller(pb, PROP_RADIUS)
	var pm := MeshInstance3D.new()
	pm.mesh = pb.commit()
	prop.add_child(pm)
	_props.append(prop)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = PROP_RADIUS
	cm.bottom_radius = PROP_RADIUS
	cm.height = 0.01
	cm.radial_segments = 32
	cm.rings = 1
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.2, 0.2, 0.22, 0.0)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.material = dmat
	disc.mesh = cm
	disc.position = ep + Vector3(0, 0, -1.88)
	disc.rotation.x = PI / 2
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	_prop_blur.append(dmat)
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
	# Upswept tail cone above the ramp, swept fin and tailplanes.
	_ext.loft(TAIL_STATIONS, _hull_angles, HULL, PAINT)
	_ext.ellipsoid(Vector3(0.12, 0.1, 0.1), _at(Vector3(0, 3.88, 27.2)), DARK, MATTE, 10, 6)
	_solid(Vector3(0.35, 4.4, 3.4), Vector3(0, 6.4, TAIL_Z + 1.6))
	_solid(Vector3(9.5, 0.2, 2.2), Vector3(0, 3.6, TAIL_Z + 2.4))
	var foil := PlaneModels.airfoil(1.0, 0.12, 0.0, 10)
	var fin: Array[Transform3D] = []
	var fin_cols := PackedColorArray()
	for st in [[3.9, 20.6, 5.6, 0.42], [6.3, 22.85, 3.45, 0.3], [6.3, 22.85, 3.45, 0.3], [8.6, 24.5, 1.85, 0.17]]:
		var c: float = st[2]
		var t: float = st[3]
		fin.append(Transform3D(Basis(Vector3(0, 0, c), Vector3(t / 0.12, 0, 0), Vector3(0, 1, 0)),
			Vector3(0, st[0], st[1])))
		fin_cols.append(TRIM if fin_cols.size() >= 2 else HULL)
	_ext.sweep(foil, fin, HULL, PAINT, true, fin_cols)
	_label("S?", Vector3(0.16, 7.3, 24.9), 220, Color.WHITE, PI / 2).outline_size = 0
	_label("S?", Vector3(-0.16, 7.3, 24.9), 220, Color.WHITE, -PI / 2).outline_size = 0
	for sx: float in [-1.0, 1.0]:
		var tp: Array[Transform3D] = []
		for st in [[0.4, 3.6, 22.9, 3.4, 0.24], [4.9, 3.9, 24.6, 1.5, 0.11]]:
			var c: float = st[3]
			tp.append(_wing_station(sx * st[0], st[1], st[2], c, float(st[4]) / c))
		_ext.sweep(foil, tp, HULL, PAINT)


## Landing gear (one mesh, shown while the gear is down): struts, oleos and chunky tyres.
func _build_gear() -> void:
	var b := MeshBatch.new()
	var tyre := PackedVector2Array([Vector2(-0.11, 0.15), Vector2(-0.125, 0.22), Vector2(-0.1, 0.28),
		Vector2(-0.05, 0.3), Vector2(0.05, 0.3), Vector2(0.1, 0.28), Vector2(0.125, 0.22), Vector2(0.11, 0.15)])
	for p: Vector3 in [Vector3(0, -1.9, -11), Vector3(-2.0, -1.9, 1.5), Vector3(2.0, -1.9, 1.5)]:
		var dxs := [-0.2, 0.2] if p.x == 0.0 else [-0.25, 0.25]
		for dx: float in dxs:
			var c := p + Vector3(dx, 0, 0)
			b.revolve(tyre, MeshBatch.axis_xf(c, c + Vector3.RIGHT), Color(0.1, 0.1, 0.11), MATTE, 20)
			b.cylinder(c - Vector3(0.1, 0, 0), c + Vector3(0.1, 0, 0), 0.155, 0.155, Color(0.8, 0.82, 0.86), SHINY, 16)
		b.cylinder(p + Vector3(dxs[0], 0, 0), p + Vector3(dxs[1], 0, 0), 0.04, 0.04, METAL, SHINY, 8)
		b.cylinder(p, p + Vector3(0, 0.6, 0), 0.07, 0.07, Color(0.85, 0.87, 0.9), SHINY, 10)
		b.cylinder(p + Vector3(0, 0.55, 0), p + Vector3(0, 1.15, 0), 0.09, 0.09, METAL, SHINY, 10)
		b.cylinder(p + Vector3(0, 0.4, 0.05), p + Vector3(0, 1.0, 0.45), 0.035, 0.035, METAL, SHINY, 8)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	add_child(mi)
	_gear_meshes.append(mi)


func _build_lights() -> void:
	for z: float in [-12.0, -7.5, -3.0, 2.5, 9.0, 15.0, 19.5]:
		var l := OmniLight3D.new()
		l.position = Vector3(0, CEIL - 0.25, z)
		l.light_color = Color(1.0, 0.95, 0.85) if z < 12.0 else Color(0.85, 0.9, 1.0)
		l.light_energy = 1.3
		l.omni_range = 7.5
		add_child(l)


## One smoke trail per damage part; set_damage turns it on as health drops.
func _build_smoke() -> void:
	var spots := {"engine0": ENGINE_POS[0] + Vector3(0, 0.4, 1.0), "engine1": ENGINE_POS[1] + Vector3(0, 0.4, 1.0),
		"wing0": Vector3(-9.5, -0.3, 1.5), "wing1": Vector3(9.5, -0.3, 1.5), "tail": Vector3(0, 5.6, TAIL_Z + 2.0),
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
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
