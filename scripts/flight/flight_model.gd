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

## Host: emitted when the autopilot lets go on its own (near the destination, too low, ...).
signal autopilot_disengaged(reason: String)

enum Phase { PARKED, FLYING, ROLLING, LANDED, CRASHED }

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

## Touchdown limits (forgiving: this is a party game, not a sim).
const MAX_SINK := 7.5
const MAX_TOUCHDOWN_ROLL := 0.45
const MIN_TOUCHDOWN_PITCH := -0.25
## Landing assist: below FLARE_ALT with the gear down, ground effect bleeds off sink rate toward
## FLARE_SINK and levels the wings when the pilot isn't banking.
const FLARE_ALT := 15.0
const FLARE_SINK := 2.0
const FLARE_DECEL := 3.0          ## m/s^2 of sink removed at most.
const FLARE_LEVEL := 0.8          ## rad/s of roll levelling.

## Takeoff: the departure roll starts once the throttle passes TAKEOFF_THROTTLE; pulling up at
## VR or faster lifts off at ROTATE_PITCH. Leaving the runway faster than RUNWAY_EXCURSION_SPEED
## on the roll is a crash. A touchdown before climbing TAKEOFF_BOUNCE metres on the origin runway
## just continues the departure roll.
const VR := 38.0
const TAKEOFF_THROTTLE := 0.3
const ROTATE_PITCH := 0.12
const RUNWAY_EXCURSION_SPEED := 12.0
const TAKEOFF_BOUNCE := 30.0

## ORIGIN airport, where every round starts parked. Runway along Z; take off heading north (-Z)
## from the south (+Z) end.
const ORIGIN_RUNWAY_CENTER := Vector3(2400, 0, -700)
const ORIGIN_RUNWAY_HALF := Vector2(55, 800)

## DESTINATION airport, ~26 km due north (6-8 minutes of flying). Land heading north (-Z);
## the threshold is the south (+Z) end.
const RUNWAY_CENTER := Vector3(2400, 0, -26000)
const RUNWAY_HALF := Vector2(55, 800)

## Parked on the origin runway centreline just inside the south threshold, nose north.
const START_POS := ORIGIN_RUNWAY_CENTER + Vector3(0, 0, ORIGIN_RUNWAY_HALF.y - 40.0)
## Cone mountains: [center (y ignored), radius, height]. All sit beside the direct route (x = 2400).
const MOUNTAINS := [
	[Vector3(-2600, 0, -5200), 1500.0, 1150.0],
	[Vector3(5200, 0, -6200), 1800.0, 1300.0],
	[Vector3(1300, 0, -15000), 650.0, 760.0],
	[Vector3(-900, 0, -15500), 2200.0, 1600.0],
	[Vector3(6600, 0, -20500), 1600.0, 1250.0],
	[Vector3(-2600, 0, -24500), 1800.0, 1450.0],
]

## Autopilot: cruise and navigation only. It never takes off or lands: it can be engaged only
## while FLYING above AP_MIN_ALT and further than AP_HANDOFF_DIST from the destination
## threshold, and lets go on its own when either limit is crossed.
const AP_CRUISE_ALT := 700.0
const AP_CRUISE_SPEED := 70.0
const AP_MIN_ALT := 150.0
const AP_HANDOFF_DIST := 4000.0
const AP_MAX_BANK := 0.35
const AP_MAX_CLIMB := 7.0         ## m/s.

var phase := Phase.PARKED
var pos := START_POS
var velocity := Vector3(0, 0, 0)
var speed := 0.0          ## |velocity| (airspeed; no wind).
var yaw := 0.0
var pitch := 0.0
var roll := 0.0
var pitch_rate := 0.0
var roll_rate := 0.0
var alpha := 0.0                  ## Angle of attack.
var stalled := false
var throttle := 0.0
var gear_down := true
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
var autopilot := false            ## Host-authoritative; synced in to_array().

var touchdown := {}               ## Filled on touchdown: sink, on_runway, speed, reason, at_destination.
var departure_roll := false       ## True on the takeoff roll (ROLLING that started from PARKED).
var parking_brake := false        ## Host: while true a PARKED plane ignores the throttle (Story sets it until the flight phase).
var _climb_peak := 1.0e9         ## Highest altitude since the takeoff roll started (huge until then).
var _drift_t := 0.0
var _wobble_t := 0.0


func basis() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, -roll))


func forward() -> Vector3:
	return -basis().z


func step(dt: float) -> void:
	match phase:
		Phase.PARKED:
			_parked(dt)
		Phase.FLYING:
			if autopilot:
				_autopilot_inputs()
			_fly(dt)
		Phase.ROLLING:
			_roll_out(dt)
		_:
			felt_accel = Vector3(0, -GRAVITY, 0)
			felt_g = 1.0
	if autopilot and phase != Phase.FLYING:
		autopilot = false
		autopilot_disengaged.emit("wheels on the ground" if phase != Phase.CRASHED else "we crashed")
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


## Why the autopilot can't be engaged right now ("" = it can, and now is).
func engage_autopilot() -> String:
	if phase != Phase.FLYING:
		return "we need to be airborne first"
	if altitude() < AP_MIN_ALT:
		return "climb above %d m first" % int(AP_MIN_ALT)
	if _to_destination().length() < AP_HANDOFF_DIST:
		return "too close to the destination, land it yourself"
	autopilot = true
	return ""


## Horizontal vector from the plane to the destination runway threshold.
func _to_destination() -> Vector2:
	var t := runway_threshold()
	return Vector2(t.x - pos.x, t.z - pos.z)


## Writes pitch/roll/throttle inputs that bank gently toward the destination threshold, climb or
## descend to AP_CRUISE_ALT and hold AP_CRUISE_SPEED. Disengages near the destination or when low.
func _autopilot_inputs() -> void:
	var to := _to_destination()
	if to.length() < AP_HANDOFF_DIST:
		autopilot = false
		autopilot_disengaged.emit("%.0f km out, cleared to land" % (to.length() / 1000.0))
		return
	if altitude() < AP_MIN_ALT:
		autopilot = false
		autopilot_disengaged.emit("below %d m" % int(AP_MIN_ALT))
		return
	# Heading: yaw grows to the left; forward = (-sin yaw, -cos yaw). Bank right (+roll) turns right.
	var heading_err := wrapf(atan2(-to.x, -to.y) - yaw, -PI, PI)
	var want_roll := clampf(-heading_err * 1.2, -AP_MAX_BANK, AP_MAX_BANK)
	roll_in = clampf((want_roll - roll) * 2.5 - roll_rate * 0.8, -1.0, 1.0)
	# Altitude -> climb rate -> flight path angle -> pitch attitude (plus the trim angle of attack).
	var want_vs := clampf((AP_CRUISE_ALT - pos.y) * 0.08, -AP_MAX_CLIMB, AP_MAX_CLIMB)
	var gamma := asin(clampf(want_vs / maxf(speed, 30.0), -0.5, 0.5))
	var vs_err := want_vs - velocity.y
	var want_pitch := clampf(gamma + alpha + vs_err * 0.01, -0.2, 0.3)
	pitch_in = clampf((want_pitch - pitch) * 3.0 - pitch_rate * 1.0, -1.0, 1.0)
	throttle_in = clampf((AP_CRUISE_SPEED - speed) * 0.25, -1.0, 1.0)


## On the ground before takeoff: engines idle, no movement. Throttle is still live so the pilot
## can spool up; once it passes TAKEOFF_THROTTLE (and the parking brake is off) the departure
## roll starts.
func _parked(dt: float) -> void:
	throttle = clampf(throttle + throttle_in * THROTTLE_RATE * dt, 0.0, 1.0)
	pos.y = 0.0
	pitch = 0.0
	roll = 0.0
	pitch_rate = 0.0
	roll_rate = 0.0
	speed = 0.0
	velocity = Vector3.ZERO
	felt_accel = Vector3(0, -GRAVITY, 0)
	felt_g = 1.0
	if has_pilot and not parking_brake and throttle > TAKEOFF_THROTTLE:
		departure_roll = true
		_climb_peak = 0.0
		phase = Phase.ROLLING


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
	if has_pilot or autopilot:
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
	if gear_down and has_pilot and pos.y < FLARE_ALT and velocity.y < -FLARE_SINK:
		velocity.y = minf(velocity.y + FLARE_DECEL * dt, -FLARE_SINK)
	if gear_down and has_pilot and pos.y < FLARE_ALT and is_zero_approx(roll_in):
		roll = move_toward(roll, 0.0, FLARE_LEVEL * dt)
	speed = velocity.length()
	pos += velocity * dt
	_update_felt(accel, b)
	_climb_peak = maxf(_climb_peak, pos.y)

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
	var at_dest := on_destination_runway(pos)
	touchdown = {"sink": sink, "on_runway": on_runway(pos), "speed": speed, "at_destination": at_dest}
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
	# Settled back onto the origin runway right after liftoff: still the takeoff roll.
	departure_roll = _climb_peak < TAKEOFF_BOUNCE and on_origin_runway(pos)
	if departure_roll:
		touchdown = {}
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
	if departure_roll:
		# Departure roll: accelerate down the runway; chopping the throttle brakes.
		var decel := ROLL_FRICTION + AERO_K * speed * speed * CD0 + (BRAKE_DECEL if throttle < 0.05 else 0.0)
		speed = maxf(0.0, speed + (thrust - decel) * dt)
		velocity = Basis(Vector3.UP, yaw) * Vector3.FORWARD * speed
		pos += velocity * dt
		felt_accel = Vector3(0, -GRAVITY, 0) + Basis(Vector3.UP, -yaw) * Vector3.FORWARD * (decel - thrust) * FELT_COUPLING
		felt_g = 1.0
		if has_pilot and pitch_in > 0.3 and speed >= VR:
			phase = Phase.FLYING
			pitch = ROTATE_PITCH
			pos.y = 0.05
			velocity.y = speed * 0.04
			return
		if not on_runway(pos) and speed > RUNWAY_EXCURSION_SPEED:
			_crash("ran off the runway on the takeoff roll")
		elif mountain_height(pos) > 2.0:
			_crash("rolled into a mountain")
		elif speed <= 0.5 and throttle < 0.1:
			# Rejected takeoff: back to parked, try again.
			speed = 0.0
			velocity = Vector3.ZERO
			departure_roll = false
			phase = Phase.PARKED
		return
	else:
		# Arrival roll: decelerate to a stop.
		var decel := ROLL_FRICTION + AERO_K * speed * speed * CD0 + (BRAKE_DECEL if throttle < 0.05 else 0.0)
		speed = maxf(0.0, speed + (thrust - decel) * dt)
		velocity = Basis(Vector3.UP, yaw) * Vector3.FORWARD * speed
		pos += velocity * dt
		felt_accel = Vector3(0, -GRAVITY, 0) + Basis(Vector3.UP, -yaw) * Vector3.FORWARD * (decel - thrust) * FELT_COUPLING
		felt_g = 1.0
		# Touch-and-go.
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


## On either runway (origin or destination).
static func on_runway(p: Vector3) -> bool:
	return on_destination_runway(p) or on_origin_runway(p)


static func on_destination_runway(p: Vector3) -> bool:
	return absf(p.x - RUNWAY_CENTER.x) <= RUNWAY_HALF.x and absf(p.z - RUNWAY_CENTER.z) <= RUNWAY_HALF.y


static func on_origin_runway(p: Vector3) -> bool:
	return absf(p.x - ORIGIN_RUNWAY_CENTER.x) <= ORIGIN_RUNWAY_HALF.x \
		and absf(p.z - ORIGIN_RUNWAY_CENTER.z) <= ORIGIN_RUNWAY_HALF.y


## DESTINATION runway threshold (south end, +Z): land heading north.
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
		1.0 if has_pilot else 0.0, flaps, alpha, 1.0 if stalled else 0.0,
		1.0 if departure_roll else 0.0, 1.0 if autopilot else 0.0])

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
	departure_roll = a[23] > 0.5
	autopilot = a[24] > 0.5
