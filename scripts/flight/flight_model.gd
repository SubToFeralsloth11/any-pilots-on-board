class_name FlightModel
extends RefCounted
## Arcade flight model. The host simulates it; clients mirror it via to_array()/from_array().
## World axes: -Z is north (start heading), +Y is up, ground is y = 0.
## yaw: heading about +Y (positive turns left). pitch: nose up positive. roll: right wing down positive.

enum Phase { FLYING, ROLLING, LANDED, CRASHED }

const GRAVITY := 9.8
const MAX_PITCH := 0.45
const MAX_ROLL := 0.8
const PITCH_RATE := 0.55
const ROLL_RATE := 0.9
const ROLL_SETTLE := 0.25
const TURN_RATE := 0.45
const THRUST := 14.0
const DRAG := 0.0025
const GEAR_DRAG := 0.0012
const STALL_SPEED := 38.0
const THROTTLE_RATE := 0.4
const BRAKE_DECEL := 7.0

## Touchdown limits.
const MAX_SINK := 5.0
const MAX_TOUCHDOWN_ROLL := 0.26
const MIN_TOUCHDOWN_PITCH := -0.12

const START_POS := Vector3(0, 900, 0)
const START_SPEED := 68.0
## Runway runs along Z; land heading north (-Z). Threshold is the south (+Z) end.
const RUNWAY_CENTER := Vector3(2400, 0, -12000)
const RUNWAY_HALF := Vector2(35, 800)
## Cone mountains: [center (y ignored), radius, height].
const MOUNTAINS := [
	[Vector3(-2600, 0, -5200), 1500.0, 1150.0],
	[Vector3(5200, 0, -6200), 1800.0, 1300.0],
	[Vector3(1300, 0, -4300), 650.0, 760.0],
	[Vector3(-900, 0, -15500), 2200.0, 1600.0],
]

var phase := Phase.FLYING
var pos := START_POS
var velocity := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var roll := 0.0
var speed := START_SPEED
var throttle := 0.6
var gear_down := false
var engine_power := [1.0, 1.0]   ## 0..1 per engine; fires lower it.
var g_factor := 1.0              ## Felt gravity multiplier inside the cabin.
var bump := 0.0                  ## Turbulence added to g_factor; decays.

## Inputs (host sets these from the pilot, or the drift when nobody flies).
var has_pilot := false
var pitch_in := 0.0
var roll_in := 0.0
var throttle_in := 0.0

var touchdown := {}              ## Filled on touchdown: sink, on_runway, reason.
var _drift_t := 0.0


func forward() -> Vector3:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD


func step(dt: float) -> void:
	match phase:
		Phase.FLYING:
			_fly(dt)
		Phase.ROLLING:
			_roll_out(dt)
		_:
			g_factor = 1.0
	bump = move_toward(bump, 0.0, dt * 1.5)


func _fly(dt: float) -> void:
	throttle = clampf(throttle + throttle_in * THROTTLE_RATE * dt, 0.0, 1.0)
	if has_pilot:
		pitch += pitch_in * PITCH_RATE * dt
		roll += roll_in * ROLL_RATE * dt
		if is_zero_approx(roll_in):
			roll = move_toward(roll, 0.0, ROLL_SETTLE * dt)
	else:
		# Nobody at the controls: the nose sags and the plane wanders.
		_drift_t += dt
		pitch = move_toward(pitch, -0.07, 0.05 * dt)
		roll = move_toward(roll, sin(_drift_t * 0.21) * 0.35, 0.1 * dt)
	if speed < STALL_SPEED:
		pitch -= (STALL_SPEED - speed) * 0.02 * dt
	pitch = clampf(pitch, -MAX_PITCH, MAX_PITCH)
	roll = clampf(roll, -MAX_ROLL, MAX_ROLL)
	yaw -= sin(roll) * TURN_RATE * clampf(speed / 70.0, 0.0, 1.5) * dt

	var engine: float = (engine_power[0] + engine_power[1]) * 0.5
	var drag := DRAG + (GEAR_DRAG if gear_down else 0.0)
	speed += (throttle * engine * THRUST - drag * speed * speed - GRAVITY * sin(pitch)) * dt
	speed = maxf(speed, 0.0)

	var prev_vy := velocity.y
	velocity = forward() * speed
	if speed < STALL_SPEED:
		velocity.y -= (STALL_SPEED - speed) * 0.5
	var vert_accel := (velocity.y - prev_vy) / dt
	var target_g := clampf(1.0 - vert_accel / GRAVITY, -0.4, 2.2)
	g_factor = lerpf(g_factor, target_g, clampf(dt * 6.0, 0.0, 1.0))
	pos += velocity * dt

	if pos.y <= 0.0:
		_touch_down()
	elif mountain_height(pos) > pos.y:
		_crash("flew into a mountain")


func _touch_down() -> void:
	var sink := -velocity.y
	pos.y = 0.0
	touchdown = {"sink": sink, "on_runway": on_runway(pos), "speed": speed}
	var reason := ""
	if not gear_down:
		reason = "landed with the wheels still up"
	elif sink > MAX_SINK:
		reason = "hit the ground way too hard"
	elif absf(roll) > MAX_TOUCHDOWN_ROLL:
		reason = "dragged a wing into the ground"
	elif pitch < MIN_TOUCHDOWN_PITCH:
		reason = "landed nose-first"
	if reason != "":
		_crash(reason)
		return
	phase = Phase.ROLLING
	pitch = 0.0
	roll = 0.0
	velocity.y = 0.0


func _roll_out(dt: float) -> void:
	g_factor = 1.0
	pos.y = 0.0
	var flat := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	speed = move_toward(speed, 0.0, BRAKE_DECEL * dt)
	velocity = flat * speed
	pos += velocity * dt
	if mountain_height(pos) > 2.0:
		_crash("rolled into a mountain")
	elif speed <= 0.5:
		speed = 0.0
		velocity = Vector3.ZERO
		phase = Phase.LANDED


func _crash(reason: String) -> void:
	phase = Phase.CRASHED
	speed = 0.0
	velocity = Vector3.ZERO
	g_factor = 1.0
	touchdown["reason"] = reason


static func on_runway(p: Vector3) -> bool:
	return absf(p.x - RUNWAY_CENTER.x) <= RUNWAY_HALF.x and absf(p.z - RUNWAY_CENTER.z) <= RUNWAY_HALF.y


static func runway_threshold() -> Vector3:
	return RUNWAY_CENTER + Vector3(0, 0, RUNWAY_HALF.y)


static func mountain_height(p: Vector3) -> float:
	var best := 0.0
	for m in MOUNTAINS:
		var c: Vector3 = m[0]
		var d := Vector2(p.x - c.x, p.z - c.z).length()
		if d < m[1]:
			best = maxf(best, m[2] * (1.0 - d / m[1]))
	return best


## Altitude above the terrain directly below.
func altitude() -> float:
	return pos.y - mountain_height(pos)


func to_array() -> PackedFloat32Array:
	return PackedFloat32Array([pos.x, pos.y, pos.z, yaw, pitch, roll, speed, throttle,
		1.0 if gear_down else 0.0, phase, g_factor + bump, engine_power[0], engine_power[1],
		velocity.y, 1.0 if has_pilot else 0.0])


func from_array(a: PackedFloat32Array) -> void:
	pos = Vector3(a[0], a[1], a[2])
	yaw = a[3]
	pitch = a[4]
	roll = a[5]
	speed = a[6]
	throttle = a[7]
	gear_down = a[8] > 0.5
	phase = int(a[9]) as Phase
	g_factor = a[10]
	bump = 0.0
	engine_power = [a[11], a[12]]
	velocity = forward() * speed
	velocity.y = a[13]
	has_pilot = a[14] > 0.5


## Gravity multiplier felt in the cabin, including turbulence.
func felt_gravity() -> float:
	return g_factor + bump
