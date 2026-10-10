extends Node
## Weather module (`world.weather`): deterministic storm cells along the route, seeded per flight
## (Airline's flight_no), so every peer knows the cells without any sync. `current` is the
## intensity at the plane on every peer (from the synced flight position).
##
## Host effects while FLYING: turbulence jolts on `world.flight.bump` with pitch/roll nudges and
## kicks to loose props and players, air pockets (2-4 s of near zero g, then a slam), gusts,
## lightning (flash + thunder on every peer, hull damage and window cracks on a hit) and a TOWER
## warning ~20 s before the plane enters a cell. Weather pauses entirely outside FLYING.
## Visuals live in WeatherFx, the pilot's radar in WeatherRadar.

signal jolt(strength: float)          ## Host: a turbulence jolt (strength 0..~1.5).
signal air_pocket(active: bool)       ## Host: an air pocket started / ended.
signal strike(hit: bool)              ## Every peer: lightning (hit = it struck the plane).

const Cells := preload("res://scripts/weather/weather_cells.gd")
const WeatherFx := preload("res://scripts/weather/weather_fx.gd")
const WeatherRadar := preload("res://scripts/weather/weather_radar.gd")

const DEFAULT_SEED := 4242
const WARN_TIME := 20.0               ## Seconds of look-ahead for the turbulence warning.
const WARN_THRESHOLD := 0.2
const JOLT_RATE := Vector2(0.5, 3.2)  ## Jolts per second at intensity 0+ / 1.
const JOLT_BUMP := 1.1                ## Bump of a full-strength jolt.
const JOLT_PITCH := 0.12              ## rad/s pitch-rate kick at full strength.
const JOLT_ROLL := 0.3                ## rad/s roll-rate kick at full strength.
const KICK_DV := 2.2                  ## Upward velocity kick of loose props on a full jolt.
const PUSH_DV := 3.0                  ## Same for standing players.
const POCKET_CHANCE := 0.035          ## Per second at intensity 1 (needs intensity > 0.3).
const POCKET_BUMP := -1.05            ## ~0 g in the cabin: everything floats.
const POCKET_SINK := 5.0              ## m/s^2 the plane drops during a pocket.
const POCKET_SLAM := 1.4              ## Bump when the pocket ends (things crash back down).
const GUST_EVERY := Vector2(9.0, 3.0) ## Seconds between gusts at intensity 0+ / 1.
const GUST_ROLL := 0.35
const GUST_YAW := 0.04
const BOLT_EVERY := Vector2(16.0, 5.0)   ## Seconds between strikes at intensity 0.35 / 1.
const BOLT_MIN_INTENSITY := 0.35
const HIT_CHANCE := 0.3
const HIT_DAMAGE := Vector2(0.03, 0.07)
const CRACK_CHANCE := 0.4             ## On a hit; a cracked window that is hit again breaks.

var world: World
var cells: Array[Dictionary] = []
var current := 0.0                    ## Intensity 0..1 at the plane (every peer; 0 unless FLYING).
var ahead := -1                       ## Cell entered within WARN_TIME (every peer), or -1.
var cracked := {}                     ## Window index -> true (every peer).
var seed_used := -1

var _fx: Node
var _radar: Control
var _rng := RandomNumberGenerator.new()
var _pocket_t := 0.0
var _gust_t := 0.0
var _bolt_t := 0.0
var _warned := {}                     ## Host: cell index -> true once TOWER warned.


func setup(w: World) -> void:
	world = w
	_rng.randomize()
	_fx = WeatherFx.new()
	_fx.name = "Fx"
	_fx.set("weather", self)
	add_child(_fx)
	var layer := CanvasLayer.new()
	layer.name = "RadarLayer"
	layer.layer = 5
	add_child(layer)
	_radar = WeatherRadar.new()
	_radar.set("weather", self)
	_radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar.anchor_left = 1.0
	_radar.anchor_right = 1.0
	_radar.anchor_top = 1.0
	_radar.anchor_bottom = 1.0
	_radar.offset_left = -222.0
	_radar.offset_right = -12.0
	_radar.offset_top = -486.0
	_radar.offset_bottom = -244.0
	layer.add_child(_radar)
	world.plane_changed.connect(_on_plane_changed)
	_refresh_cells()


func populate() -> void:
	pass


## Storm intensity 0..1 at a world position (flight coordinates).
func intensity_at(pos: Vector3) -> float:
	return Cells.intensity(cells, pos)


func flying() -> bool:
	return world.flight.phase == FlightModel.Phase.FLYING


## Seed from the flight number (Airline syncs it; it may arrive after this module is built).
func _flight_seed() -> int:
	var airline: Node = world.get("airline")
	if airline == null:
		return DEFAULT_SEED
	var n: Variant = airline.get("flight_no")
	return DEFAULT_SEED if n == null else int(n) * 7919 + 17


func _refresh_cells() -> void:
	var s := _flight_seed()
	if s == seed_used:
		return
	seed_used = s
	cells = Cells.generate(s, FlightModel.ORIGIN_RUNWAY_CENTER, FlightModel.runway_threshold())
	_warned.clear()
	_fx.call("build_clouds")


func _physics_process(dt: float) -> void:
	_refresh_cells()
	var f := world.flight
	if not flying():
		current = 0.0
		ahead = -1
		_pocket_t = 0.0
		return
	current = Cells.intensity(cells, f.pos)
	ahead = Cells.cell_ahead(cells, f.pos, f.velocity, WARN_TIME, WARN_THRESHOLD) if current < WARN_THRESHOLD else -1
	if not world.is_server() or world.round_over:
		return
	_warn()
	_turbulence(dt)
	_pocket(dt)
	_gusts(dt)
	_lightning(dt)


func _warn() -> void:
	if ahead < 0 or _warned.has(ahead):
		return
	_warned[ahead] = true
	var heavy := float(cells[ahead].strength) > 0.75
	world.say("TOWER", "Heavy storm cell twenty seconds ahead of you. Seatbelt sign ON, crew sit down!" if heavy
		else "Turbulence ahead in about twenty seconds. Might want that seatbelt sign on.", 4.0)


func _turbulence(dt: float) -> void:
	if current <= 0.01 or _pocket_t > 0.0:
		return
	if _rng.randf() >= lerpf(JOLT_RATE.x, JOLT_RATE.y, current) * dt:
		return
	var f := world.flight
	var s := current * _rng.randf_range(0.4, 1.3)
	f.bump = s * JOLT_BUMP * (1.0 if _rng.randf() < 0.6 else -0.8)
	f.pitch_rate += _rng.randf_range(-1.0, 1.0) * JOLT_PITCH * s
	f.roll_rate += _rng.randf_range(-1.0, 1.0) * JOLT_ROLL * s
	_kick(s)
	if s > 0.45:
		world.shake_all(s * 0.5)
	jolt.emit(s)


## A random share of the loose props hop (stronger jolts move more of them) and standing
## players get bounced (seated ones just shake).
func _kick(s: float) -> void:
	var up := world.plane.global_basis.y
	var held := world.holders.values()
	for id in world.objects:
		var body := world.objects[id] as RigidBody3D
		if body == null or body.freeze or body.is_in_group("npc") or held.has(id) or _rng.randf() > s:
			continue
		var side := Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(-0.3, 0.3))
		body.apply_central_impulse((up + side) * body.mass * KICK_DV * s * _rng.randf_range(0.6, 1.2))
	if s < 0.35:
		return
	for peer in world.players:
		if peer != world.pilot_peer:
			world.push_player(peer, up * PUSH_DV * s + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * s)


func _pocket(dt: float) -> void:
	var f := world.flight
	if _pocket_t > 0.0:
		_pocket_t -= dt
		f.bump = POCKET_BUMP
		f.velocity.y -= POCKET_SINK * dt
		if _pocket_t <= 0.0:
			f.bump = POCKET_SLAM
			world.shake_all(0.8)
			air_pocket.emit(false)
		return
	if current > 0.3 and _rng.randf() < POCKET_CHANCE * current * dt:
		_pocket_t = _rng.randf_range(2.0, 4.0)
		world.shake_all(0.6)
		air_pocket.emit(true)


func _gusts(dt: float) -> void:
	_gust_t -= dt
	if current <= 0.05 or _gust_t > 0.0:
		return
	_gust_t = lerpf(GUST_EVERY.x, GUST_EVERY.y, current) * _rng.randf_range(0.7, 1.3)
	var dir := 1.0 if _rng.randf() < 0.5 else -1.0
	world.flight.roll_rate += dir * GUST_ROLL * current
	world.flight.yaw += dir * GUST_YAW * current


func _lightning(dt: float) -> void:
	_bolt_t -= dt
	if current < BOLT_MIN_INTENSITY or _bolt_t > 0.0:
		return
	_bolt_t = lerpf(BOLT_EVERY.x, BOLT_EVERY.y, inverse_lerp(BOLT_MIN_INTENSITY, 1.0, current)) * _rng.randf_range(0.6, 1.4)
	var f := world.flight
	var c: Dictionary = cells[Cells.strongest(cells, f.pos)]
	var hit := _rng.randf() < HIT_CHANCE
	var cp: Vector3 = c.pos
	var top := Vector3(lerpf(f.pos.x, cp.x, 0.3), maxf(f.pos.y + 500.0, float(c.top) * 0.75), lerpf(f.pos.z, cp.z, 0.3))
	top += Vector3(_rng.randf_range(-400, 400), 0, _rng.randf_range(-400, 400))
	var end := f.pos
	if not hit:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(250.0, 1100.0)
		end = Vector3(f.pos.x + cos(a) * r, FlightModel.mountain_height(f.pos), f.pos.z + sin(a) * r)
	var bolt_seed := _rng.randi()
	for p in world._ready_peers:
		_rpc_strike.rpc_id(p, top, end, hit, bolt_seed)
	_rpc_strike(top, end, hit, bolt_seed)
	if not hit:
		return
	world.damage_plane("hull", _rng.randf_range(HIT_DAMAGE.x, HIT_DAMAGE.y))
	world.add_stat("lightning_hits")
	world.shake_all(0.9)
	if _rng.randf() < CRACK_CHANCE:
		_crack_random_window()


func _crack_random_window() -> void:
	var intact: Array[int] = []
	for i in world.plane.windows.size():
		if not world.plane.windows[i].broken:
			intact.append(i)
	if intact.is_empty():
		return
	var i: int = intact[_rng.randi() % intact.size()]
	if cracked.has(i):
		world.break_window(i)
		world.say("TOWER", "Was that a window? Lightning took out a window!", 3.0)
		return
	for p in world._ready_peers:
		_rpc_crack.rpc_id(p, i)
	_rpc_crack(i)


## Every peer: bolt from `from` to `to` (flight coordinates), flash, thunder.
@rpc("authority", "call_remote", "reliable")
func _rpc_strike(from: Vector3, to: Vector3, hit: bool, bolt_seed: int) -> void:
	_fx.call("strike", from, to, hit, bolt_seed)
	strike.emit(hit)


@rpc("authority", "call_remote", "reliable")
func _rpc_crack(i: int) -> void:
	cracked[i] = true
	_fx.call("crack_window", i)


func _on_plane_changed(key: String, value: bool) -> void:
	if value and key.begins_with("window:"):
		var i := int(key.get_slice(":", 1))
		cracked.erase(i)
		_fx.call("clear_crack", i)
