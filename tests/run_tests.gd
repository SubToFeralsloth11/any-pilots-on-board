extends SceneTree
## Headless unit tests: godot --headless -s res://tests/run_tests.gd
## Exit code = number of failures.

const DT := 1.0 / 60.0

const WeatherCells := preload("res://scripts/weather/weather_cells.gd")
const VoiceCodec := preload("res://scripts/net/voice_codec.gd")
const Contracts := preload("res://scripts/airline/contracts.gd")

var _failures := 0


func _init() -> void:
	_test_trimmed_cruise_holds_altitude()
	_test_gentle_runway_landing_rolls_to_a_stop()
	_test_gear_up_touchdown_crashes()
	_test_hard_touchdown_crashes()
	_test_banked_touchdown_crashes()
	_test_flying_into_mountain_crashes()
	_test_unpiloted_plane_sinks_and_wanders()
	_test_slow_flight_stalls_and_drops_the_nose()
	_test_flaps_lower_stall_speed()
	_test_dead_engine_yaws_toward_it()
	_test_damaged_wing_drops()
	_test_pushover_makes_cabin_floaty()
	_test_state_roundtrip()
	_test_wall_spans()
	_test_takeoff_from_parked_reaches_flying()
	_test_departure_roll_never_lands()
	_test_landing_on_destination_sets_at_destination()
	_test_landing_elsewhere_is_not_destination()
	_test_scoring()
	_test_awards()
	_test_payout_all_delivered()
	_test_payout_passengers_lost()
	_test_payout_crash()
	_test_payout_diversion()
	_test_payout_damaged_cargo()
	_test_payout_empty_manifest()
	_test_payout_partial_cargo()
	_test_contracts_deterministic()
	_test_autopilot_converges_to_cruise()
	_test_autopilot_limits()
	_test_weather_cells_deterministic()
	_test_weather_intensity_falloff()
	_test_voice_codec_roundtrip()
	_test_voice_resampler_length()
	_test_voice_packet_framing()
	print("%s: %d failure(s)" % ["FAIL" if _failures else "PASS", _failures])
	quit(_failures)


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		_failures += 1
		print("  FAIL ", what)


func _sim(f: FlightModel, seconds: float) -> void:
	for i in int(seconds / DT):
		f.step(DT)


## Level cruise at 900 m and 70 m/s, trimmed, heading north (the plane now starts PARKED).
func _cruising(pos := Vector3(0, 900, 0)) -> FlightModel:
	var f := FlightModel.new()
	f.phase = FlightModel.Phase.FLYING
	f.pos = pos
	f.velocity = Vector3(0, 0, -70.0)
	f.speed = 70.0
	f.pitch = FlightModel.ALPHA_TRIM
	f.throttle = 0.57
	f.gear_down = false
	return f


## 3 m above the runway, 500 m short of its centre, descending gently on final.
func _approach(gear: bool, sink := 1.5, roll := 0.0) -> FlightModel:
	var f := FlightModel.new()
	f.phase = FlightModel.Phase.FLYING
	f.pos = FlightModel.RUNWAY_CENTER + Vector3(0, 3, 500)
	f.velocity = Vector3(0, -sink, -48)
	f.pitch = 0.04
	f.roll = roll
	f.flaps = 2
	f.throttle = 0.3
	f.gear_down = gear
	f.has_pilot = true
	return f


## Runs until landed/crashed; chops the throttle after touchdown so the brakes engage.
func _run(f: FlightModel, max_steps := 20000) -> void:
	for i in max_steps:
		if f.phase == FlightModel.Phase.LANDED or f.phase == FlightModel.Phase.CRASHED:
			return
		if f.phase == FlightModel.Phase.ROLLING:
			f.throttle_in = -1.0
		f.step(DT)


func _test_trimmed_cruise_holds_altitude() -> void:
	var f := _cruising()
	f.has_pilot = true
	_sim(f, 20.0)
	_check(absf(f.pos.y - 900.0) < 80.0 and f.speed > 55.0,
		"hands-off cruise at start throttle roughly holds altitude (%.0f m, %.0f m/s)" % [f.pos.y, f.speed])
	_check(absf(f.felt_gravity() - 1.0) < 0.15, "steady cruise feels like 1 g (%.2f g)" % f.felt_gravity())


func _test_gentle_runway_landing_rolls_to_a_stop() -> void:
	var f := _approach(true)
	_run(f)
	_check(f.phase == FlightModel.Phase.LANDED, "gentle gear-down touchdown ends LANDED (%s)" % f.touchdown)
	_check(f.touchdown.get("on_runway", false), "touchdown point is on the runway")
	_check(f.speed == 0.0, "plane rolled to a stop")


func _test_gear_up_touchdown_crashes() -> void:
	var f := _approach(false)
	_run(f)
	_check(f.phase == FlightModel.Phase.CRASHED and "wheels" in f.touchdown.reason, "gear-up landing crashes (belly)")


func _test_hard_touchdown_crashes() -> void:
	var f := _approach(true, 12.0)
	f.pos.y = 30.0
	f.velocity.z = -65.0
	f.pitch = -0.2
	f.pitch_in = -1.0   # Pilot shoving the nose down all the way.
	_run(f)
	_check(f.phase == FlightModel.Phase.CRASHED and f.touchdown.sink > FlightModel.MAX_SINK, "diving into the ground crashes (%s)" % f.touchdown)


func _test_banked_touchdown_crashes() -> void:
	var f := _approach(true, 1.0, 0.7)
	f.pos.y = 0.01
	f.roll_in = 1.0   # Holding the bank right onto the runway.
	_run(f)
	_check(f.phase == FlightModel.Phase.CRASHED and "wing" in f.touchdown.reason, "touching down in a steep bank crashes (%s)" % f.touchdown)


func _test_flying_into_mountain_crashes() -> void:
	var m: Array = FlightModel.MOUNTAINS[2]
	var f := _cruising((m[0] as Vector3) + Vector3(0, 200, 900))
	f.has_pilot = true
	_run(f, 60 * 60)
	_check(f.phase == FlightModel.Phase.CRASHED and "mountain" in f.touchdown.reason, "level flight into a mountain crashes")


func _test_unpiloted_plane_sinks_and_wanders() -> void:
	var f := _cruising()
	var start_alt := f.pos.y
	var max_bank := 0.0
	for i in int(30.0 / DT):
		f.step(DT)
		max_bank = maxf(max_bank, absf(f.roll))
	_check(f.pos.y < start_alt - 50.0, "nobody flying: plane loses altitude (%.0f m)" % (start_alt - f.pos.y))
	_check(max_bank > 0.1, "nobody flying: plane drifts into a bank (%.2f rad)" % max_bank)


func _test_slow_flight_stalls_and_drops_the_nose() -> void:
	var f := _cruising()
	f.has_pilot = true
	f.throttle = 0.0
	f.pitch_in = 1.0   # Hauling back on the yoke.
	var stalled := false
	for i in int(25.0 / DT):
		f.step(DT)
		stalled = stalled or f.stalled
	_check(stalled, "pulling up with no power eventually stalls")
	_check(f.velocity.y < -3.0, "a stalled plane sinks (vy %.1f)" % f.velocity.y)


func _test_flaps_lower_stall_speed() -> void:
	var f := FlightModel.new()
	var clean := f.stall_speed()
	f.flaps = 2
	_check(f.stall_speed() < clean - 3.0, "full flaps lower the stall speed (%.0f -> %.0f m/s)" % [clean, f.stall_speed()])


func _test_dead_engine_yaws_toward_it() -> void:
	var f := _cruising()
	f.has_pilot = true
	f.engine_power = [0.0, 1.0]   # Left engine out.
	_sim(f, 8.0)
	_check(f.yaw > 0.05, "left engine out: plane yaws left (yaw %.2f)" % f.yaw)


func _test_damaged_wing_drops() -> void:
	var f := _cruising()
	f.has_pilot = true
	f.wing_health = [1.0, 0.2]   # Right wing shredded.
	_sim(f, 3.0)
	_check(f.roll > 0.2, "damaged right wing: plane rolls right (roll %.2f)" % f.roll)


func _test_pushover_makes_cabin_floaty() -> void:
	var f := _cruising()
	f.has_pilot = true
	f.pitch_in = -1.0   # Shove the yoke forward.
	var min_g := 9.0
	for i in int(3.0 / DT):
		f.step(DT)
		min_g = minf(min_g, f.felt_gravity())
	_check(min_g < 0.5, "shoving the nose down makes the cabin floaty (min %.2f g)" % min_g)


func _test_state_roundtrip() -> void:
	var a := FlightModel.new()
	a.pos = Vector3(12, 345, -678)
	a.yaw = 0.3
	a.pitch = -0.1
	a.roll = 0.2
	a.gear_down = true
	a.flaps = 1
	a.engine_power = [0.5, 0.9]
	a.has_pilot = true
	var b := FlightModel.new()
	b.from_array(a.to_array())
	_check(b.pos.distance_to(a.pos) < 0.01 and is_equal_approx(b.roll, a.roll) and b.gear_down and b.has_pilot \
		and b.flaps == 1 and is_equal_approx(b.engine_power[0], 0.5), "flight state survives to_array/from_array")


func _test_wall_spans() -> void:
	var s := Airliner.spans(0.0, 10.0, [Vector2(2, 3), Vector2(9, 12), Vector2(-5, -1)])
	var want: Array[Vector2] = [Vector2(0, 2), Vector2(3, 9)]
	_check(s == want, "wall spans subtract gaps, clipping at the ends")


## Scripted pilot from PARKED: full throttle, wings level, rotate at Vr; stops once airborne
## (or crashed).
func _takeoff(f: FlightModel, seconds: float) -> void:
	f.has_pilot = true
	f.throttle_in = 1.0
	for i in int(seconds / DT):
		f.pitch_in = 0.6 if f.phase == FlightModel.Phase.ROLLING and f.speed >= FlightModel.VR else 0.0
		f.step(DT)
		if f.phase == FlightModel.Phase.FLYING or f.phase == FlightModel.Phase.CRASHED:
			return


func _test_takeoff_from_parked_reaches_flying() -> void:
	var f := FlightModel.new()
	_check(f.phase == FlightModel.Phase.PARKED and f.pos.y == 0.0 and f.speed == 0.0 and f.gear_down
		and FlightModel.on_runway(f.pos), "round starts PARKED on the origin runway, gear down")
	_sim(f, 3.0)
	_check(f.phase == FlightModel.Phase.PARKED and f.pos == FlightModel.START_POS, "nobody flying: parked plane stays put")
	f.parking_brake = true
	f.has_pilot = true
	f.throttle_in = 1.0
	_sim(f, 3.0)
	_check(f.phase == FlightModel.Phase.PARKED and f.pos == FlightModel.START_POS,
		"parking brake (boarding) keeps the plane put at full throttle")
	f.parking_brake = false
	f.throttle = 0.0
	_takeoff(f, 90.0)
	_check(f.phase == FlightModel.Phase.FLYING, "full throttle + rotate at Vr takes off (phase %d)" % f.phase)
	_check(f.pitch > 0.0 and f.pitch < 0.3 and f.speed >= FlightModel.VR,
		"liftoff with a sane pitch (%.2f rad) above Vr (%.1f m/s)" % [f.pitch, f.speed])
	_check(absf(f.pos.z - FlightModel.START_POS.z) < FlightModel.ORIGIN_RUNWAY_HALF.y * 2.0,
		"liftoff happens on the origin runway (%.0f m roll)" % absf(f.pos.z - FlightModel.START_POS.z))
	# Keep climbing: hold ~6 degrees nose up, wings level, gear up once clear of the ground.
	var climbed := 0.0
	for i in int(60.0 / DT):
		f.pitch_in = clampf((0.1 - f.pitch) * 4.0, -1.0, 1.0)
		f.roll_in = clampf(-f.roll * 2.0, -1.0, 1.0)
		if f.pos.y > 30.0:
			f.gear_down = false
		f.step(DT)
		climbed = maxf(climbed, f.pos.y)
	_check(f.phase == FlightModel.Phase.FLYING and climbed > 150.0,
		"after liftoff the plane climbs away (%.0f m after 60 s)" % climbed)


func _test_departure_roll_never_lands() -> void:
	# Throttle up, never rotate, then chop the throttle: must not count as a landing.
	var f := FlightModel.new()
	f.has_pilot = true
	f.throttle_in = 1.0
	_sim(f, 6.0)
	_check(f.phase == FlightModel.Phase.ROLLING and f.departure_roll and f.speed > 5.0,
		"throttle up from PARKED starts the departure roll (%.1f m/s)" % f.speed)
	f.throttle_in = -1.0
	var landed := false
	for i in int(60.0 / DT):
		f.step(DT)
		landed = landed or f.phase == FlightModel.Phase.LANDED
	_check(not landed, "an aborted departure roll never yields LANDED (phase %d)" % f.phase)


func _test_landing_on_destination_sets_at_destination() -> void:
	var f := _approach(true)
	_run(f)
	_check(f.phase == FlightModel.Phase.LANDED and f.touchdown.get("at_destination", false),
		"landing on the destination runway sets at_destination")


func _test_landing_elsewhere_is_not_destination() -> void:
	var f := _approach(true)
	f.pos.x += 400.0   # Grass beside the destination runway.
	_run(f)
	var g := _approach(true)
	g.pos = FlightModel.ORIGIN_RUNWAY_CENTER + Vector3(0, 3, 500)   # Back home on the origin runway.
	_run(g)
	_check(f.phase == FlightModel.Phase.LANDED and not f.touchdown.get("at_destination", true),
		"landing in a field is not at_destination")
	_check(g.phase == FlightModel.Phase.LANDED and not g.touchdown.get("at_destination", true),
		"landing back on the origin runway is not at_destination")


func _test_scoring() -> void:
	var stats := {"windows_broken": 0, "items_lost": 0, "passengers_lost": 0, "things_broken": 0, "players_fell": 0}
	var runway := _approach(true)
	_run(runway)
	var field := _approach(true)
	field.pos.x += 400.0
	_run(field)
	var crash := _approach(false)
	_run(crash)
	var r1 := Scoring.result(runway, stats)
	var r2 := Scoring.result(field, stats)
	var r3 := Scoring.result(crash, stats)
	_check(r1.landed and r2.landed and not r3.landed, "landed/crashed outcomes reported")
	_check(r1.score > r2.score and r3.score == 0, "runway beats a field landing; crashing scores 0")
	stats.passengers_lost = 3
	_check(Scoring.result(runway, stats).score < r1.score, "losing passengers costs points")


func _award(list: Array[Dictionary], title: String) -> Dictionary:
	for a in list:
		if a.title == title:
			return a
	return {}


func _test_awards() -> void:
	_check(Scoring.awards({}, {}).is_empty(), "awards: nobody playing, no awards")
	var solo := Scoring.awards({}, {1: "Ann"})
	_check(solo.size() == 1 and solo[0].title == "Pacifist" and solo[0].name == "Ann",
		"awards: solo player with zero stats only gets Pacifist (%s)" % [solo])
	var one := Scoring.awards({1: {"windows_broken": 3.0, "pilot_seconds": 42.4}}, {1: "Ann"})
	_check(_award(one, "Window Enthusiast").get("value") == 3.0 and _award(one, "Captain Now").get("name") == "Ann",
		"awards: single player wins the stats they have")
	_check("42 seconds" in str(_award(one, "Captain Now").get("text")), "awards: pilot time shown in whole seconds")
	_check(_award(one, "Butterfingers").is_empty(), "awards: zero stats win nothing")
	var names := {2: "Bob", 1: "Ann", 3: "Cat"}
	var stats := {
		3: {"windows_broken": 2.0, "punches_landed": 1.0},
		2: {"windows_broken": 2.0, "fumbles": 4.0},
		1: {"times_fell_out": 1.0},
	}
	var many := Scoring.awards(stats, names)
	_check(_award(many, "Window Enthusiast").get("peer") == 2, "awards: ties go to the lowest peer id")
	_check(_award(many, "Butterfingers").get("name") == "Bob", "awards: winner name comes from names")
	_check(_award(many, "Frequent Flyer (outside the plane)").get("peer") == 1,
		"awards: a player with no other stats can still win")
	_check(_award(many, "Pacifist").get("peer") == 1, "awards: Pacifist is the lowest peer that never punched")
	var calm := Scoring.awards({1: {"fumbles": 1.0}}, {1: "Ann", 2: "Bob"})
	_check(_award(calm, "Pacifist").is_empty(), "awards: no Pacifist when nobody punched in a group")


func _test_payout_all_delivered() -> void:
	var r := Scoring.payout(
		[{"id": 1, "type": "passengers", "kind": "tourists", "name": "Tourists", "count": 10, "payout": 2000, "risk": 1, "accepted": true},
		 {"id": 2, "type": "cargo", "kind": "luggage", "name": "Luggage", "count": 5, "payout": 750, "risk": 1, "accepted": true}],
		{1: {"boarded": 10, "delivered": 10, "lost": 0, "satisfaction": 1.0}},
		{2: {"units": 5, "delivered": 5, "condition": 1.0}},
		{"landed": true, "on_runway": true, "diverted": false, "crashed": false},
		{"engine0": 1.0, "engine1": 1.0, "wing0": 1.0, "wing1": 1.0, "tail": 1.0, "hull": 1.0},
		[{"peer": 1, "amount": 50, "reason": "Great service"}],
		[],
		1000
	)
	# 2000 * 1.5 (full satisfaction) = 3000 + 750 cargo + 50 tip = 3800
	_check(r.total == 3800 and r.new_bank == 4800, "payout: all delivered gives full payout + tips")


func _test_payout_passengers_lost() -> void:
	var r := Scoring.payout(
		[{"id": 1, "type": "passengers", "kind": "tourists", "name": "Tourists", "count": 10, "payout": 2000, "risk": 1, "accepted": true}],
		{1: {"boarded": 10, "delivered": 7, "lost": 3, "satisfaction": 0.7}},
		{},
		{"landed": true, "on_runway": true, "diverted": false, "crashed": false},
		{"engine0": 1.0, "engine1": 1.0, "wing0": 1.0, "wing1": 1.0, "tail": 1.0, "hull": 1.0},
		[],
		[],
		0
	)
	# 2000 * 1.2 sat_mult * 0.7 delivered = 1680 - 450 lost penalty = 1230
	_check(r.total == 1230, "payout: lost passengers reduce earnings")


func _test_payout_crash() -> void:
	_check(Scoring._test_payout_crash(), "payout: crash applies heavy penalties")


func _test_payout_diversion() -> void:
	var r := Scoring.payout(
		[{"id": 1, "type": "passengers", "kind": "tourists", "name": "Tourists", "count": 10, "payout": 2000, "risk": 1, "accepted": true}],
		{1: {"boarded": 10, "delivered": 10, "lost": 0, "satisfaction": 1.0}},
		{},
		{"landed": true, "on_runway": false, "diverted": true, "crashed": false},
		{"engine0": 1.0, "engine1": 1.0, "wing0": 1.0, "wing1": 1.0, "tail": 1.0, "hull": 1.0},
		[],
		[],
		0
	)
	# 2000 * 1.5 = 3000 - 1000 diversion = 2000
	_check(r.total == 2000, "payout: diversion penalty applied")


func _test_payout_damaged_cargo() -> void:
	_check(Scoring._test_payout_damaged_cargo(), "payout: damaged cargo pays less")


func _test_payout_empty_manifest() -> void:
	_check(Scoring._test_payout_empty_manifest(), "payout: empty manifest yields zero")


func _test_payout_partial_cargo() -> void:
	var c := [{"id": 1, "type": "cargo", "kind": "mail", "name": "Mail", "count": 4, "payout": 1000, "risk": 1, "accepted": true}]
	var r := Scoring.payout(c, {}, {1: {"units": 4, "delivered": 3, "condition": 1.0}},
		{"landed": true, "on_runway": true, "diverted": false, "crashed": false}, {}, [], [], 0)
	_check(r.total == 750, "payout: 3 of 4 cargo units delivered pays 3/4 (got %d)" % r.total)


func _test_contracts_deterministic() -> void:
	var a := Contracts.generate(7)
	var b := Contracts.generate(7)
	_check(a == b and not a.is_empty(), "contracts: same flight number -> identical contracts and order")
	var differs := false
	for n in range(1, 6):
		if Contracts.generate(n) != a:
			differs = true
	_check(differs, "contracts: other flight numbers offer something else")
	var ok := true
	for n in range(1, 40):
		var cs := Contracts.generate(n)
		var pax := cs.filter(func(c: Dictionary) -> bool: return c.type == "passengers")
		var ids := cs.map(func(c: Dictionary) -> int: return c.id)
		ids.sort()
		ok = ok and cs.size() >= 5 and cs.size() <= 7 and pax.size() >= 3 and ids == range(1, cs.size() + 1) \
			and pax.any(func(c: Dictionary) -> bool: return c.kind == "tourists")
	_check(ok, "contracts: 5-7 offers with unique ids, >=3 passenger contracts incl. tourists")


## Disturbed (banked, nose low, slow, heading away) -> level cruise toward the destination.
func _test_autopilot_converges_to_cruise() -> void:
	for start: Array in [[Vector3(2400, 550, -3000), 1.0, 0.5, -0.1, 55.0], [Vector3(1000, 900, -8000), -2.5, -0.6, 0.15, 85.0]]:
		var f := FlightModel.new()
		f.phase = FlightModel.Phase.FLYING
		f.pos = start[0]
		f.yaw = start[1]
		f.roll = start[2]
		f.pitch = start[3]
		f.velocity = f.forward() * float(start[4])
		f.throttle = 0.4
		f.gear_down = false
		_check(f.engage_autopilot() == "", "autopilot: engages in flight")
		_sim(f, 60.0)
		var to := FlightModel.runway_threshold() - f.pos
		var heading_err := wrapf(atan2(-to.x, -to.z) - f.yaw, -PI, PI)
		_check(f.autopilot and f.phase == FlightModel.Phase.FLYING and absf(f.pos.y - FlightModel.AP_CRUISE_ALT) < 25.0
			and absf(f.velocity.y) < 1.0 and absf(f.roll) < 0.05 and absf(heading_err) < 0.05
			and absf(f.speed - FlightModel.AP_CRUISE_SPEED) < 3.0,
			"autopilot: level cruise toward destination in 60 s (alt %.0f vs %.2f roll %.3f hdg %.3f spd %.1f)" % [
				f.pos.y, f.velocity.y, f.roll, heading_err, f.speed])


func _test_autopilot_limits() -> void:
	var parked := FlightModel.new()
	_check(parked.engage_autopilot() != "" and not parked.autopilot, "autopilot: refuses on the ground (no takeoff)")
	var low := _cruising(Vector3(2400, 100, -5000))
	_check(low.engage_autopilot() != "", "autopilot: refuses below %d m" % int(FlightModel.AP_MIN_ALT))
	var f := _cruising(FlightModel.runway_threshold() + Vector3(0, 600, 4400))
	var reasons: Array[String] = []
	f.autopilot_disengaged.connect(func(r: String) -> void: reasons.append(r))
	_check(f.engage_autopilot() == "", "autopilot: engages 4.4 km out")
	_sim(f, 15.0)
	_check(not f.autopilot and reasons.size() == 1, "autopilot: hands over ~4 km from the destination (no landing)")
	var unmanned := _cruising(Vector3(2400, 700, -5000))
	unmanned.engage_autopilot()
	unmanned.has_pilot = false
	_sim(unmanned, 30.0)
	_check(unmanned.autopilot and absf(unmanned.pos.y - 700.0) < 30.0, "autopilot: keeps flying with nobody in the seat")


func _test_weather_cells_deterministic() -> void:
	var o := FlightModel.ORIGIN_RUNWAY_CENTER
	var d := FlightModel.runway_threshold()
	var a := WeatherCells.generate(1234, o, d)
	var b := WeatherCells.generate(1234, o, d)
	var c := WeatherCells.generate(99, o, d)
	_check(a.size() >= WeatherCells.COUNT_MIN and a.size() <= WeatherCells.COUNT_MAX, "weather: 3-5 storm cells")
	_check(a == b, "weather: same seed gives the same cells")
	_check(a != c, "weather: another seed gives other cells")
	var on_route := false
	var length := Vector2(o.x, o.z).distance_to(Vector2(d.x, d.z))
	for cell in a:
		var p: Vector3 = cell.pos
		var t := Vector2(p.x - o.x, p.z - o.z).dot(Vector2(d.x - o.x, d.z - o.z).normalized()) / length
		if t < 0.1 or t > 0.95:
			_failures += 1
			print("  FAIL weather: cell outside the route band (t=%.2f)" % t)
		for s in 41:
			var q := o.lerp(d, s / 40.0) + Vector3(0, 900, 0)
			if WeatherCells.cell_intensity(cell, q) > 0.3:
				on_route = true
	_check(on_route, "weather: at least one storm sits on the route")


func _test_weather_intensity_falloff() -> void:
	var cell := {"pos": Vector3(1000, 0, -5000), "radius": 1200.0, "strength": 0.8, "top": 2800.0}
	var cells: Array[Dictionary] = [cell]
	var at := func(dx: float, y := 900.0) -> float: return WeatherCells.intensity(cells, Vector3(1000 + dx, y, -5000))
	_check(is_equal_approx(at.call(0.0), 0.8), "weather: full strength in the core")
	_check(at.call(0.0) >= at.call(500.0) and at.call(500.0) > at.call(900.0) and at.call(900.0) > 0.0,
		"weather: intensity falls off toward the rim")
	_check(at.call(1250.0) == 0.0, "weather: calm air outside the cell")
	_check(at.call(0.0, 3400.0) == 0.0, "weather: calm above the cloud tops")
	_check(WeatherCells.strongest(cells, Vector3(5000, 900, 0)) == -1, "weather: no cell far away")
	_check(WeatherCells.cell_ahead(cells, Vector3(1000, 900, -2800), Vector3(0, 0, -70), 20.0, 0.2) == 0,
		"weather: storm detected ~20 s ahead")
	_check(WeatherCells.cell_ahead(cells, Vector3(1000, 900, 2000), Vector3(0, 0, -70), 20.0, 0.2) == -1,
		"weather: no warning when the storm is far ahead")




func _test_voice_codec_roundtrip() -> void:
	var src := PackedFloat32Array()
	for i in 2001:
		src.append(-1.0 + i * 0.001)
	var out := VoiceCodec.mulaw_decode(VoiceCodec.mulaw_encode(src))
	var worst := 0.0
	for i in src.size():
		# μ-law: error grows with the level (4 mantissa bits per segment) plus a tiny floor near zero.
		worst = maxf(worst, absf(out[i] - src[i]) - 0.035 * absf(src[i]))
	_check(out.size() == src.size() and worst <= 0.0006,
		"voice: u-law round trip within 3.5%% + 0.0006 (excess %.5f)" % worst)
	_check(absf(VoiceCodec.mulaw_decode_sample(VoiceCodec.mulaw_encode_sample(0.0))) < 0.0005,
		"voice: silence stays silent")
	_check(VoiceCodec.mulaw_encode_sample(1.0) == VoiceCodec.mulaw_encode_sample(5.0),
		"voice: out-of-range samples clip")
	var flips := 0
	for b in 256:
		if VoiceCodec.mulaw_encode_sample(VoiceCodec.mulaw_decode_sample(b)) != b:
			flips += 1
	_check(flips <= 1, "voice: every μ-law code survives decode -> encode (%d differ, only -0)" % flips)


func _test_voice_resampler_length() -> void:
	var src := PackedFloat32Array()
	src.resize(48000)
	for i in src.size():
		src[i] = sin(i * TAU * 440.0 / 48000.0)
	var rs := VoiceCodec.Resampler.new(48000.0, 16000.0)
	var out := PackedFloat32Array()
	var at := 0
	var chunk := 1
	while at < src.size():
		var n := mini(chunk, src.size() - at)
		out.append_array(rs.push(src.slice(at, at + n)))
		at += n
		chunk = chunk * 7 % 997 + 1   # Uneven block sizes, like the audio callback.
	_check(absi(out.size() - 16000) <= 1, "voice: 1 s at 48 kHz resamples to 16000 samples (%d)" % out.size())
	var err := 0.0
	for i in out.size():
		err = maxf(err, absf(out[i] - sin(i * TAU * 440.0 / 16000.0)))
	_check(err < 0.01, "voice: chunked resampling keeps the waveform (max error %.4f)" % err)
	var rs2 := VoiceCodec.Resampler.new(44100.0, 16000.0)
	var n44 := 0
	for k in 100:
		var block := PackedFloat32Array()
		block.resize(441)
		n44 += rs2.push(block).size()
	_check(absi(n44 - 16000) <= 1, "voice: 44.1 kHz in 10 ms blocks resamples to 16000 samples (%d)" % n44)


func _test_voice_packet_framing() -> void:
	var frame := PackedFloat32Array()
	frame.resize(VoiceCodec.FRAME_SAMPLES)
	for i in frame.size():
		frame[i] = 0.5 * sin(i * 0.2)
	var pkt := VoiceCodec.encode_packet(65535, frame)
	_check(pkt.size() == VoiceCodec.HEADER_BYTES + VoiceCodec.FRAME_SAMPLES,
		"voice: a 20 ms frame is %d bytes" % pkt.size())
	var d := VoiceCodec.decode_packet(pkt)
	_check(d.get("seq") == 65535 and (d.get("samples", PackedFloat32Array()) as PackedFloat32Array).size() == frame.size(),
		"voice: packet keeps sequence and sample count")
	_check(VoiceCodec.decode_packet(pkt.slice(0, pkt.size() - 1)).is_empty(), "voice: truncated packet rejected")
	_check(VoiceCodec.decode_packet(PackedByteArray([1, 0])).is_empty(), "voice: short header rejected")
	var bad := pkt.duplicate()
	bad[0] = 99
	_check(VoiceCodec.decode_packet(bad).is_empty(), "voice: unknown version rejected")
	_check(VoiceCodec.encode_packet((65535 + 1) & 0xFFFF, frame).decode_u16(1) == 0, "voice: sequence wraps at 65536")
	_check(VoiceCodec.seq_newer(0, 65535) and not VoiceCodec.seq_newer(65535, 0) and not VoiceCodec.seq_newer(7, 7),
		"voice: sequence comparison survives wrap-around")