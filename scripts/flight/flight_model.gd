class_name FlightModel
extends RefCounted
## Force-based flight model (lift, drag, thrust, gravity) with arcade-friendly rotation.
## The host simulates it; clients mirror it via to_array()/from_array().
##
## World axes: -Z is north (start heading), +Y is up, ground is y = 0.
## yaw: heading about +Y (positive turns left). pitch: nose up positive. roll: right wing down positive.
## Damage (0..1 health per part, set by World from Airliner.damage) shapes the handling:
## dead engines yaw/roll you toward them, a hurt wing drops, a hurt tail wobbles and
## loses elevator authority, hull damage adds drag.

enum Phase { FLYING, ROLLING, LANDED, CRASHED }

const GRAVITY := 9.8
## Aero coefficients (accelerations per unit mass): a = K * V^2 * C.
const AERO_K := 0.0052
const CL0 := 0.25
const CL_ALPHA := 4.5
const ALPHA_STALL := 0.24
const CL_MAX := 1.35
const CD0 := 0.115
const CD_INDUCED := 0.045
const GEAR_CD := 0.03
const HULL_CD := 0.08            ## Extra drag at zero hull health.
const FLAP_CL := [0.0, 0.35, 0.6]
const FLAP_CD := [0.0, 0.025, 0.06]
const THRUST_PER_ENGINE := 2.75  ## m/s^2 at full throttle.
const THROTTLE_RATE := 0.4
## Rotation.
const PITCH_RATE := 0.45
const ROLL_RATE := 1.0
const PITCH_RESPONSE := 2.5
const ROLL_RESPONSE := 3.0
const PITCH_STABILITY := 1.6     ## Nose weathervanes toward the flight path.
const ALPHA_TRIM := 0.03
const MAX_PITCH := 1.2
const MAX_ROLL := 1.4
const SIDESLIP_DAMP := 1.2
## How much of the plane's own acceleration passengers feel (1 = fully coordinated turns,
## lower keeps things sliding around in banks, which is the fun part).
const FELT_COUPLING := 0.6
## Ground.
const ROLL_FRICTION := 0.4
const BRAKE_DECEL := 4.5
const STEER_RATE := 0.35

## Touchdown limits.
const MAX_SINK := 5.0
const MAX_TOUCHDOWN_ROLL := 0.26
const MIN_TOUCHDOWN_PITCH := -0.1

const START_POS := Vector3(0, 900, 0)
const START_SPEED := 70.0
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
var velocity := Vector3(0, 0, -START_SPEED)
var speed := START_SPEED          ## |velocity| (airspeed; no wind).
var yaw := 0.0
var pitch := ALPHA_TRIM
var roll := 0.0
var pitch_rate := 0.0
var roll_rate := 0.0
var alpha := 0.0                  ## Angle of attack.
var stalled := false
var throttle := 0.57
var gear_down := false
var flaps := 0                    ## 0, 1, 2 notches.
var engine_power := [1.0, 1.0]    ## 0..1 per engine; World derives from damage and fire.
var wing_health := [1.0, 1.0]
var tail_health := 1.0
var hull_health := 1.0
var bump := 0.0                   ## Turbulence: extra felt g (negative = floaty). Decays.
var felt_accel := Vector3(0, -GRAVITY, 0)   ## Apparent gravity inside the cabin (scene frame).
var felt_g := 1.0                 ## felt_accel along the cabin floor normal, in g.

## Inputs (host sets these from the pilot, or the drift when nobody flies).
var has_pilot := false
var pitch_in := 0.0
var roll_in := 0.0
var throttle_in := 0.0

var touchdown := {}               ## Filled on touchdown: sink, on_runway, speed, reason.
var _drift_t := 0.0
var _wobble_t := 0.0


func basis() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, -roll))


func forward() -> Vector3:
	return -basis().z


func step(dt: float) -> void:
	match phase:
		Phase.FLYING:
			_fly(dt)
		Phase.ROLLING:
			_roll_out(dt)
		_:
			felt_accel = Vector3(0, -GRAVITY, 0)
			felt_g = 1.0
	bump = move_toward(bump, 0.0, dt * 1.5)


## Lift coefficient for an angle of attack (with flaps), including the post-stall drop.
func lift_coefficient(a: float) -> float:
	var cl_max: float = CL_MAX + FLAP_CL[flaps]
	var cl: float = CL0 + FLAP_CL[flaps] + CL_ALPHA * a
	if a > ALPHA_STALL:
		cl = lerpf(cl_max, cl_max * 0.45, clampf((a - ALPHA_STALL) / 0.2, 0.0, 1.0))
	elif a < -ALPHA_STALL:
		cl = -0.6
	return minf(cl, cl_max)


func stall_speed() -> float:
	return sqrt(GRAVITY / (AERO_K * (CL_MAX + FLAP_CL[flaps])))


func _fly(dt: float) -> void:
	throttle = clampf(throttle + throttle_in * THROTTLE_RATE * dt, 0.0, 1.0)
	var b := basis()
	var fwd := -b.z
	var up := b.y
	speed = velocity.length()
	var vdir := velocity / maxf(speed, 0.1)
	var vb := b.inverse() * velocity
	alpha = atan2(-vb.y, maxf(-vb.z, 0.1))
	stalled = alpha > ALPHA_STALL

	# --- Rotation: commanded rates, stability, damage moments.
	var authority := clampf(speed / 55.0, 0.15, 1.2)
	var p_cmd := 0.0
	var r_cmd := 0.0
	if has_pilot:
		p_cmd = pitch_in * PITCH_RATE
		r_cmd = roll_in * ROLL_RATE
	else:
		_drift_t += dt
		p_cmd = -0.03 if pitch > -0.12 else 0.0
		r_cmd = (sin(_drift_t * 0.21) * 0.35 - roll) * 0.4
	p_cmd *= authority * lerpf(0.25, 1.0, tail_health)
	r_cmd *= authority * lerpf(0.3, 1.0, (wing_health[0] + wing_health[1]) * 0.5)
	if not stalled:
		p_cmd -= (alpha - ALPHA_TRIM) * PITCH_STABILITY
	else:
		p_cmd -= 0.35   # Stall: the nose drops.
	_wobble_t += dt
	p_cmd += sin(_wobble_t * 3.1) * (1.0 - tail_health) * 0.25
	# Asymmetric lift/thrust from damage.
	var wing_l := lerpf(0.4, 1.0, wing_health[0])
	var wing_r := lerpf(0.4, 1.0, wing_health[1])
	r_cmd += (wing_l - wing_r) * 0.5 * authority   # The weaker wing drops.
	var t_l: float = throttle * engine_power[0]
	var t_r: float = throttle * engine_power[1]
	r_cmd += (t_l - t_r) * 0.12
	if is_zero_approx(roll_in) and has_pilot:
		r_cmd -= roll * 0.15   # Gentle dihedral.
	pitch_rate = move_toward(pitch_rate, p_cmd, PITCH_RESPONSE * dt)
	roll_rate = move_toward(roll_rate, r_cmd, ROLL_RESPONSE * dt)
	pitch = clampf(pitch + pitch_rate * dt, -MAX_PITCH, MAX_PITCH)
	roll = clampf(roll + roll_rate * dt, -MAX_ROLL, MAX_ROLL)
	# Banked turn plus yaw from engine asymmetry (dead left engine yaws you left).
	yaw -= GRAVITY * tan(clampf(roll, -1.3, 1.3)) / maxf(speed, 25.0) * cos(pitch) * dt
	yaw += (t_r - t_l) * 0.06 * dt

	# --- Forces.
	var cl := lift_coefficient(alpha) * (wing_l + wing_r) * 0.5
	var lift_dir := (up - vdir * up.dot(vdir)).normalized()
	var q := AERO_K * speed * speed
	var cd: float = CD0 + CD_INDUCED * cl * cl + (GEAR_CD if gear_down else 0.0) + FLAP_CD[flaps] \
		+ HULL_CD * (1.0 - hull_health) + (0.08 if stalled else 0.0)
	var side := b.x * -vb.x * SIDESLIP_DAMP
	var accel := lift_dir * q * cl - vdir * q * cd + fwd * (t_l + t_r) * THRUST_PER_ENGINE + side
	accel.y -= GRAVITY + bump * GRAVITY * 0.3
	velocity += accel * dt
	speed = velocity.length()
	pos += velocity * dt
	_update_felt(accel, b)

	if pos.y <= 0.0:
		_touch_down()
	elif mountain_height(pos) > pos.y:
		_crash("flew into a mountain")


## Apparent gravity in the cabin: real gravity minus (part of) the plane's acceleration.
func _update_felt(accel: Vector3, b: Basis) -> void:
	var world_felt := Vector3(0, -GRAVITY, 0) - accel * FELT_COUPLING   # accel already includes gravity.
	world_felt.y -= bump * GRAVITY
	felt_accel = Basis(Vector3.UP, -yaw) * world_felt
	felt_g = world_felt.dot(-b.y) / GRAVITY


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
	roll = 0.0
	roll_rate = 0.0
	pitch_rate = 0.0
	velocity.y = 0.0


func _roll_out(dt: float) -> void:
	throttle = clampf(throttle + throttle_in * THROTTLE_RATE * dt, 0.0, 1.0)
	pos.y = 0.0
	pitch = move_toward(pitch, 0.0, 0.3 * dt)
	roll = 0.0
	speed = Vector2(velocity.x, velocity.z).length()
	if has_pilot:
		yaw -= roll_in * STEER_RATE * clampf(speed / 10.0, 0.0, 1.0) * dt
	var thrust: float = throttle * (engine_power[0] + engine_power[1]) * THRUST_PER_ENGINE
	var decel := ROLL_FRICTION + AERO_K * speed * speed * CD0 + (BRAKE_DECEL if throttle < 0.05 else 0.0)
	speed = maxf(0.0, speed + (thrust - decel) * dt)
	velocity = Basis(Vector3.UP, yaw) * Vector3.FORWARD * speed
	pos += velocity * dt
	felt_accel = Vector3(0, -GRAVITY, 0) + Basis(Vector3.UP, -yaw) * Vector3.FORWARD * (decel - thrust) * FELT_COUPLING
	felt_g = 1.0
	# Enough lift with the nose up: you're flying again (touch-and-go).
	if has_pilot and pitch_in > 0.3 and speed > stall_speed() * 1.1:
		phase = Phase.FLYING
		pitch = 0.08
		pos.y = 0.05
		return
	if mountain_height(pos) > 2.0:
		_crash("rolled into a mountain")
	elif speed <= 0.5 and throttle < 0.1:
		speed = 0.0
		velocity = Vector3.ZERO
		phase = Phase.LANDED


func _crash(reason: String) -> void:
	phase = Phase.CRASHED
	speed = 0.0
	velocity = Vector3.ZERO
	felt_accel = Vector3(0, -GRAVITY, 0)
	felt_g = 1.0
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


## Felt gravity along the cabin floor normal, in g (HUD readout, jump height).
func felt_gravity() -> float:
	return felt_g


func to_array() -> PackedFloat32Array:
	return PackedFloat32Array([pos.x, pos.y, pos.z, yaw, pitch, roll, speed, throttle,
		1.0 if gear_down else 0.0, phase, felt_accel.x, felt_accel.y, felt_accel.z, felt_g,
		engine_power[0], engine_power[1], velocity.x, velocity.y, velocity.z,
		1.0 if has_pilot else 0.0, flaps, alpha, 1.0 if stalled else 0.0])


func from_array(a: PackedFloat32Array) -> void:
	pos = Vector3(a[0], a[1], a[2])
	yaw = a[3]
	pitch = a[4]
	roll = a[5]
	speed = a[6]
	throttle = a[7]
	gear_down = a[8] > 0.5
	phase = int(a[9]) as Phase
	felt_accel = Vector3(a[10], a[11], a[12])
	felt_g = a[13]
	engine_power = [a[14], a[15]]
	velocity = Vector3(a[16], a[17], a[18])
	has_pilot = a[19] > 0.5
	flaps = int(a[20])
	alpha = a[21]
	stalled = a[22] > 0.5
