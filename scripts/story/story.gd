extends Node
## Host-driven story for the crew of the world's worst airline: DISPATCH and TOWER flavour per
## round phase (world.airline.phase), takeoff/cruise/landing coaching for the pilot, the
## seatbelt-sign tips, the objective text, and non-weather chaos events (bird strikes, engine
## fires, bins, trolley, sputter, ramp) while the plane is flying. Turbulence, air pockets and
## lightning belong to the Weather module.
##
## Lives at /root/Main/World/Story on every peer. Only the host runs the beats; clients receive
## subtitles via world.say and the objective via _rpc_objective / apply_sync.

const CHAOS_FIRST := Vector2(35.0, 55.0)   ## Seconds after liftoff before the first chaos event.
const CHAOS_GAP := Vector2(30.0, 55.0)
const COACH_GAP := 8.0          ## Minimum seconds between any two TOWER tips.
const TIP_REPEAT := 25.0        ## Minimum seconds before the same tip again.
const SHOUT_COOLDOWN := 1.2
const PITCH_UP_KEY := "S"       ## Flight-sim style, matches Player._send_pilot_input.
const PITCH_DOWN_KEY := "W"
const CRUISE_ALT := 700.0       ## Metres; the climb tips stop above this.
const APPROACH_DIST := 9000.0   ## Metres to the destination threshold where the approach starts.
const CHAOS := ["bird", "fire", "bins", "ramp", "trolley", "sputter", "bird_engine"]

const SHOUTS := ["WHO PACKED THE SNAKES?!", "I'M A DOCTOR! ...of philosophy.", "Does anyone have gum?",
	"STAY CALM! (I'm not calm.)", "This is fine.", "AAAAAAAAAH!", "I'd like to speak to the manager of the sky!",
	"Is it too late to ask for the vegetarian meal?", "Everybody lean LEFT!", "I believe I can fly!",
	"Has anyone seen my shoe?", "WHEEEEEE!", "Coffee, tea, or panic?", "Totally under control!"]
const BOARDING := ["Mind the ramp, it bites.", "Please keep your chickens in their coop at all times.",
	"Seats are first come, first served. And second come, also served. We overbooked.",
	"Welcome aboard! Our safety record is... a record.",
	"Carry-on limit: one bag, one dream, zero refunds."]
const BIRD := ["*THWACK* A goose just came through the window. It looks furious.",
	"BIRD STRIKE! A seagull is now technically a passenger.",
	"*SPLAT* A pigeon has entered the cabin and is demanding peanuts."]
const CRASH := ["...Flight %d? Hello? ...I'll just write 'arrived'.",
	"Tower to Flight %d: that's... technically a landing.",
	"Dispatch to Flight %d: the insurance people would like a word.",
	"Flight %d, we'll... send the bus."]

var world: World
var objective := ""             ## Current goal text (synced to every peer; the HUD shows it).

var _lines: Array[Dictionary] = []   ## Host: queued subtitles {speaker, text, dur}.
var _line_t := 1.0
var _chaos_t := 0.0
var _last_chaos := ""
var _time := 0.0
var _coach_t := 0.0
var _check_t := 0.0
var _tips := {}                 ## tip key -> time it was last said.
var _shouted := {}              ## peer -> time of the last shout.
var _airline_phase := ""        ## Host: last airline phase handled.
var _flight_phase := FlightModel.Phase.PARKED
var _was_departing := false
var _airborne_once := false
var _boarding_t := 0.0
var _liftoff_time := 0.0        ## Host: _time at the first liftoff.


func setup(w: World) -> void:
	world = w
	world.register_action("shout", _on_shout)
	world.pilot_changed.connect(_on_pilot_changed)
	if world.airline != null and world.airline.has_signal("phase_changed"):
		world.airline.phase_changed.connect(_on_airline_phase)
		# The plane stays parked (passengers walking up the ramp) until the flight phase.
		world.flight.parking_brake = true


func populate() -> void:
	_flight_phase = world.flight.phase
	if world.airline != null:
		_on_airline_phase(String(world.airline.get("phase")))


## Host. Players are the crew: the pilot seat is free from the start.
func can_pilot(_peer: int) -> bool:
	return true


func get_sync() -> Dictionary:
	return {"objective": objective}


func apply_sync(d: Dictionary) -> void:
	objective = d.get("objective", "")


# --- Objective -------------------------------------------------------------------------

func _set_objective(text: String) -> void:
	if text == objective:
		return
	objective = text
	for p in world._ready_peers:
		_rpc_objective.rpc_id(p, text)


@rpc("authority", "call_remote", "reliable")
func _rpc_objective(text: String) -> void:
	objective = text


# --- Line queue (host) -----------------------------------------------------------------

func _queue(speaker: String, text: String, dur := 3.5) -> void:
	_lines.append({"speaker": speaker, "text": text, "dur": dur})


## Drops anything still queued and says the new lines right away.
func _say_now(lines: Array) -> void:
	_lines.clear()
	_line_t = 0.0
	for l: Array in lines:
		_queue(l[0], l[1], l[2] if l.size() > 2 else 3.5)


func _run_lines(dt: float) -> void:
	_line_t -= dt
	if _line_t > 0.0 or _lines.is_empty():
		return
	var l: Dictionary = _lines.pop_front()
	_line_t = float(l.dur) + 0.4
	world.say(l.speaker, l.text, l.dur)


func _flight_no() -> int:
	return int(world.airline.get("flight_no")) if world.airline != null else 404


func _panic(amount: float) -> void:
	if world.npcs != null and world.npcs.has_method("panic_all"):
		world.npcs.panic_all(amount)


# --- Round phases (host) ---------------------------------------------------------------

func _on_airline_phase(phase: String) -> void:
	if not world.is_server() or phase == _airline_phase:
		return
	_airline_phase = phase
	world.flight.parking_brake = phase != "flight"
	print("[story] airline phase: " + phase)
	var no := _flight_no()
	match phase:
		"manifest":
			_set_objective("Pick contracts on the manifest board (front galley). Host starts boarding.")
			_say_now([["DISPATCH", "Morning, crew of Flight %d! Welcome to the worst airline in the sky." % no, 4.0],
				["DISPATCH", "Manifest board's in the front galley. More passengers, more cargo, more money...", 4.0],
				["DISPATCH", "...more risk. Crocodiles do NOT count as hand luggage.", 3.5],
				["DISPATCH", "Someone grab the pilot seat up front. The rest of you: cabin crew. Good luck.", 4.0]])
		"boarding":
			_boarding_t = 6.0
			_set_objective("Boarding! Passengers come up the rear ramp. Get the cabin ready.")
			_say_now([["DISPATCH", "Boarding's open. Ramp's down at the back. Smile, they can smell fear.", 4.0]])
		"flight":
			_set_objective("Pilot: throttle up [Shift] and roll down runway 36. Crew: keep the cabin calm.")
			_say_now([["TOWER", "Flight %d, Tower. Runway 36, cleared for takeoff. Wind... is a thing." % no, 4.0],
				["TOWER", "Throttle up with [Shift]. At %d knots pull back with [%s] to rotate." \
					% [roundi(FlightModel.VR * 1.94384), PITCH_UP_KEY], 4.5],
				["TOWER", "Seatbelt sign on with [B] for takeoff. Gear up [G] once you're climbing.", 4.0]])
		"report":
			_lines.clear()


# --- Simulation (host) -----------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if not world.is_server():
		return
	_time += dt
	_run_lines(dt)
	var f := world.flight
	if f.phase != _flight_phase:
		_on_flight_phase(_flight_phase, f.phase)
		_flight_phase = f.phase
	if _airline_phase == "boarding":
		_boarding_t -= dt
		if _boarding_t <= 0.0:
			_boarding_t = randf_range(9.0, 15.0)
			if _lines.is_empty():
				world.say("CREW", BOARDING.pick_random(), 3.5)
	if _airline_phase != "flight":
		return
	if f.phase == FlightModel.Phase.FLYING:
		_chaos_t -= dt
		if _chaos_t <= 0.0:
			_chaos_t = randf_range(CHAOS_GAP.x, CHAOS_GAP.y)
			_chaos()
	if world.pilot_peer != 0:
		_check_t -= dt
		if _check_t <= 0.0:
			_check_t = 1.0
			_coach()


func _on_flight_phase(from: FlightModel.Phase, to: FlightModel.Phase) -> void:
	var f := world.flight
	var no := _flight_no()
	match to:
		FlightModel.Phase.ROLLING:
			if f.departure_roll:
				print("[story] takeoff roll")
				_set_objective("Takeoff roll! Keep it straight [A]/[D]. Rotate [%s] at Vr." % PITCH_UP_KEY)
				return
			print("[story] touchdown")
			if f.touchdown.get("at_destination", false):
				_say_now([["TOWER", "TOUCHDOWN! Welcome in, Flight %d. Throttle back [Ctrl], brakes do the rest." % no, 4.0]])
			else:
				_say_now([["TOWER", "Flight %d... that is NOT our runway. Diverting counts. Sort of." % no, 4.0]])
			_set_objective("Throttle to idle [Ctrl] and roll to a stop.")
		FlightModel.Phase.FLYING:
			if from == FlightModel.Phase.ROLLING and not _airborne_once:
				print("[story] airborne")
				_airborne_once = true
				_liftoff_time = _time
				_chaos_t = randf_range(CHAOS_FIRST.x, CHAOS_FIRST.y)
				_say_now([["TOWER", "Positive rate! You're FLYING. Gear up [G], climb to about %d metres." \
					% roundi(CRUISE_ALT), 4.0]])
				_set_objective("Gear up [G]. Climb, then follow the HUD marker to the destination.")
		FlightModel.Phase.LANDED:
			print("[story] landed")
			_lines.clear()
			if f.touchdown.get("at_destination", false):
				world.say("DISPATCH", "Flight %d is at the destination. Passengers alive-ish. Payout incoming." % no, 4.0)
			else:
				world.say("DISPATCH", "Flight %d, you landed... somewhere. Diversion fees apply." % no, 4.0)
		FlightModel.Phase.CRASHED:
			print("[story] crashed: %s" % f.touchdown.get("reason", "unknown"))
			_lines.clear()
			world.say("TOWER", (CRASH.pick_random() as String) % no, 4.0)
			_set_objective("Well... that happened.")


# --- Chaos events (host, FLYING only) --------------------------------------------------

func _chaos() -> void:
	var options: Array = CHAOS.filter(func(k: String) -> bool: return k != _last_chaos and _chaos_ok(k))
	if options.is_empty():
		return
	var k: String = options.pick_random()
	_last_chaos = k
	print("[story] chaos: " + k)
	var plane := world.plane
	match k:
		"bird":
			var intact: Array[int] = []
			for i in plane.windows.size():
				if not plane.windows[i].broken:
					intact.append(i)
			world.break_window(intact.pick_random())
			world.shake_all(0.4)
			_panic(0.2)
			world.say("", BIRD.pick_random(), 3.5)
		"fire":
			var i := 0 if not plane.engine_fire[0] else 1
			if not plane.engine_fire[0] and not plane.engine_fire[1]:
				i = randi() % 2
			world.set_plane("fire:%d" % i, true)
			world.shake_all(0.5)
			_panic(0.3)
			world.say("CREW", "The %s engine is ON FIRE! Someone get out on the wing with an extinguisher!"
				% ["left", "right"][i], 4.0)
		"bins":
			for n in randi_range(3, 5):
				var sx := -1.0 if randf() < 0.5 else 1.0
				var local := Vector3(sx * 1.45, 2.25, randf_range(-8.5, 5.0))
				var xf := Transform3D(plane.global_basis * Basis.from_euler(Vector3(randf(), randf(), randf()) * TAU),
					plane.to_global(local))
				var obj := world.spawn_object("suitcase" if randf() < 0.5 else "bag", xf, {}) as RigidBody3D
				if obj:
					obj.linear_velocity = plane.global_basis * Vector3(-sx * randf_range(1.0, 3.0), -1.0, 0)
			_panic(0.2)
			world.say("", "*CLUNK* The overhead bins have given up. LUGGAGE INCOMING!", 3.0)
		"ramp":
			world.set_plane("ramp", true)
			world.say("CREW", "The cargo ramp just opened BY ITSELF! Close it! Lever's in the back!", 4.0)
		"trolley":
			var cart: RigidBody3D = null
			for id in world.objects:
				var o: Node3D = world.objects[id]
				if o.get_meta("kind", "") == "cart":
					cart = o as RigidBody3D
					break
			if cart == null:
				cart = world.spawn_object("cart", Transform3D(plane.global_basis, plane.to_global(Vector3(0, 0.4, -9.3))),
					{}) as RigidBody3D
			if cart:
				cart.linear_velocity = plane.global_basis * Vector3(0, 0, 7.0)
			world.say("CREW", "The drinks trolley has ESCAPED! It's coming down the aisle! Protect your knees!", 3.5)
		"sputter":
			var e := randi() % 2
			world.damage_plane("engine%d" % e, 0.3)
			world.shake_all(0.4)
			_panic(0.2)
			world.say("", "*cough* *cough* *BANG* The %s engine is making noises engines shouldn't make."
				% ["left", "right"][e], 3.5)
		"bird_engine":
			var e := randi() % 2
			world.damage_plane("engine%d" % e, 0.35)
			world.shake_all(0.6)
			world.say("", "*FWUMP* A goose flew into the %s engine. The goose did not win. Neither did the engine."
				% ["left", "right"][e], 3.5)
			if randf() < 0.5 and not plane.engine_fire[e]:
				world.set_plane("fire:%d" % e, true)
				_queue("CREW", "And now it's ON FIRE. Extinguisher! Wing! Somebody! GO!", 3.5)


## Health of a plane part (1 = intact, 0 = destroyed).
func _health(part: String) -> float:
	return float(world.plane.damage.get(part, 1.0))


func _chaos_ok(k: String) -> bool:
	var plane := world.plane
	match k:
		"bird":
			return plane.windows.any(func(w: Dictionary) -> bool: return not w.broken)
		"fire":
			return not (plane.engine_fire[0] and plane.engine_fire[1])
		"ramp":
			return not plane.ramp_open
	return true


# --- TOWER coaching (host) -------------------------------------------------------------

## Picks the most urgent tip for the current flight state (rate-limited) and keeps the
## objective in step with the stage of the flight.
func _coach() -> void:
	var f := world.flight
	match f.phase:
		FlightModel.Phase.PARKED:
			_tip("throttle", "Flight %d, you're cleared. Throttle UP. Hold [Shift]." % _flight_no())
			return
		FlightModel.Phase.ROLLING:
			if f.departure_roll:
				if f.speed >= FlightModel.VR:
					_tip("rotate", "ROTATE! Pull back [%s] NOW!" % PITCH_UP_KEY, 6.0, true)
				elif absf(wrapf(f.yaw, -PI, PI)) > 0.05:
					_tip("straight", "Keep it on the centreline! [A]/[D] to steer!")
			return
		FlightModel.Phase.FLYING:
			pass
		_:
			return
	var thr := FlightModel.runway_threshold()
	var to := Vector2(thr.x - f.pos.x, thr.z - f.pos.z)
	var dist := to.length()
	var alt := f.altitude()
	var heading_off := absf(wrapf(f.yaw, -PI, PI))
	var engine: float = (f.engine_power[0] + f.engine_power[1]) * 0.5
	var lined := absf(f.pos.x - FlightModel.RUNWAY_CENTER.x) < 120.0 and heading_off < 0.3 and f.pos.z > thr.z
	var approach := dist < APPROACH_DIST
	if approach:
		_set_objective("Approach: descend, line up with runway 36, gear down [G], land gently.")
	elif alt > CRUISE_ALT * 0.8:
		_set_objective("Cruise to the destination (HUD marker). Crew: serve, calm, protect the cargo.")
	if _time < _coach_t or not _lines.is_empty():
		return
	if f.stalled or (f.speed < f.stall_speed() + 5.0 and _time - _liftoff_time > 10.0):
		_tip("stall", "STALL WARNING! Nose down, full throttle! [%s] + [Shift]!" % PITCH_DOWN_KEY)
	elif alt < 120.0 and dist > 2500.0 and _time - _liftoff_time > 20.0:
		_tip("pull_up", "PULL UP! [%s]! The ground is NOT the airport!" % PITCH_UP_KEY)
	elif not approach and f.gear_down and alt > 150.0:
		_tip("gear_up", "Gear up [G], Flight %d. You're dragging the wheels through the sky." % _flight_no())
	elif approach and alt < 400.0 and not f.gear_down:
		_tip("gear", "Gear! Press [G]! Wheels are not optional!")
	elif f.pitch < -0.3:
		_tip("dive", "That's a LOT of nose-down. Ease up! [%s]" % PITCH_UP_KEY)
	elif absf(f.roll) > 0.6:
		_tip("bank", "Wings level! You're scaring the cows.")
	elif not approach and alt < CRUISE_ALT * 0.6 and f.velocity.y < 1.0:
		_tip("climb", "Keep climbing to about %d metres. Nose up a touch [%s], throttle [Shift]." \
			% [roundi(CRUISE_ALT), PITCH_UP_KEY])
	elif not approach and alt > CRUISE_ALT * 0.8 and world.seatbelt_sign:
		_tip("belts_off", "Nice and smooth up here. Seatbelt sign off [B] so the crew can serve.", 90.0)
	elif approach and not world.seatbelt_sign:
		_tip("belts_on", "Starting the approach. Seatbelt sign ON [B], crew to your seats!", 40.0)
	elif approach and f.pos.y > dist * 0.0524 + 150.0:
		_tip("high", "You're too high! Throttle back [Ctrl] and nose down a bit [%s]." % PITCH_DOWN_KEY)
	elif approach and f.speed > 78.0:
		_tip("fast", "Way too fast! Throttle down with [Ctrl]. This isn't a race.")
	elif approach and not lined:
		_tip("line_up", "You're not lined up! Runway 36 points north. Use [A]/[D] to line up.")
	elif _health("engine0") < 0.35 or _health("engine1") < 0.35:
		_tip("engine_out", "You've lost an engine! Bank gently the other way and keep the speed up!")
	elif _health("wing0") < 0.4 or _health("wing1") < 0.4:
		_tip("wing", "Your wing looks... lighter than it should. Small turns. TINY turns.")
	elif _health("hull") < 0.4 or _health("tail") < 0.4:
		_tip("hull", "Flight %d, your plane is held together by hope and duct tape. Land SOON." % _flight_no())
	elif engine < 0.5:
		_tip("engine", "Your engines sound... crunchy. Maybe deal with that fire?")
	elif dist < 3000.0 and lined and f.gear_down:
		_tip("good", "Lined up, gear down... that's actually... good? Keep it gentle!")
	else:
		_tip("where", "Destination is %.1f km away, %s. Follow the HUD marker." % [dist / 1000.0, _side(to)], 45.0)


func _tip(key: String, text: String, repeat := TIP_REPEAT, urgent := false) -> void:
	if _time - float(_tips.get(key, -1000.0)) < repeat:
		return
	if not urgent and _time < _coach_t:
		return
	_tips[key] = _time
	_coach_t = _time + COACH_GAP
	world.say("TOWER", text, 3.5)


## "dead ahead", "to your left" or "to your right", relative to the plane's heading.
func _side(to: Vector2) -> String:
	var yaw := world.flight.yaw
	var right := Vector2(cos(yaw), -sin(yaw))
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var d := to.normalized()
	if d.dot(fwd) > 0.9:
		return "dead ahead"
	if d.dot(fwd) < -0.3:
		return "BEHIND you"
	return "to your right" if d.dot(right) > 0.0 else "to your left"


# --- Players (host) --------------------------------------------------------------------

func _on_shout(peer: int, _args: Array) -> void:
	if _time - float(_shouted.get(peer, -10.0)) < SHOUT_COOLDOWN:
		return
	_shouted[peer] = _time
	world.say(world.display_name(peer), SHOUTS.pick_random(), 2.5)
	_panic(0.04)


func _on_pilot_changed(peer: int) -> void:
	if not world.is_server():
		return
	var f := world.flight
	if peer == 0:
		if f.phase == FlightModel.Phase.FLYING:
			world.say("TOWER", "Flight %d, your pilot seat looks... empty? Please tell me it's not empty." % _flight_no(), 3.5)
		return
	print("[story] pilot: %s" % world.display_name(peer))
	world.notify(peer, "You're the captain now. [%s]/[%s] pitch, [A]/[D] bank/steer, [Shift]/[Ctrl] throttle, [B] belts."
		% [PITCH_DOWN_KEY, PITCH_UP_KEY])
	if _airline_phase != "flight" and f.phase == FlightModel.Phase.PARKED:
		world.say("DISPATCH", "%s has the controls. Hold your horses until boarding's done." % world.display_name(peer), 3.5)
