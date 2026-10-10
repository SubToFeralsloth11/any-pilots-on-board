extends SceneTree
## Headless unit tests: godot --headless -s res://tests/run_tests.gd
## Exit code = number of failures.

const DT := 1.0 / 60.0

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
	_test_scoring()
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


## 3 m above the runway, 500 m short of its centre, descending gently on final.
func _approach(gear: bool, sink := 1.5, roll := 0.0) -> FlightModel:
	var f := FlightModel.new()
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
	var f := FlightModel.new()
	f.has_pilot = true
	_sim(f, 20.0)
	_check(absf(f.pos.y - FlightModel.START_POS.y) < 80.0 and f.speed > 55.0,
		"hands-off cruise at start throttle roughly holds altitude (%.0f m, %.0f m/s)" % [f.pos.y, f.speed])


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
	var f := _approach(true, 1.0, 0.4)
	f.pos.y = 0.01
	f.roll_in = 1.0   # Holding the bank right onto the runway.
	_run(f)
	_check(f.phase == FlightModel.Phase.CRASHED and "wing" in f.touchdown.reason, "touching down in a steep bank crashes (%s)" % f.touchdown)


func _test_flying_into_mountain_crashes() -> void:
	var m: Array = FlightModel.MOUNTAINS[2]
	var f := FlightModel.new()
	f.has_pilot = true
	f.pos = (m[0] as Vector3) + Vector3(0, 200, 900)
	_run(f, 60 * 60)
	_check(f.phase == FlightModel.Phase.CRASHED and "mountain" in f.touchdown.reason, "level flight into a mountain crashes")


func _test_unpiloted_plane_sinks_and_wanders() -> void:
	var f := FlightModel.new()
	var start_alt := f.pos.y
	var max_bank := 0.0
	for i in int(30.0 / DT):
		f.step(DT)
		max_bank = maxf(max_bank, absf(f.roll))
	_check(f.pos.y < start_alt - 50.0, "nobody flying: plane loses altitude (%.0f m)" % (start_alt - f.pos.y))
	_check(max_bank > 0.1, "nobody flying: plane drifts into a bank (%.2f rad)" % max_bank)


func _test_slow_flight_stalls_and_drops_the_nose() -> void:
	var f := FlightModel.new()
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
	var f := FlightModel.new()
	f.has_pilot = true
	f.engine_power = [0.0, 1.0]   # Left engine out.
	_sim(f, 8.0)
	_check(f.yaw > 0.05, "left engine out: plane yaws left (yaw %.2f)" % f.yaw)


func _test_damaged_wing_drops() -> void:
	var f := FlightModel.new()
	f.has_pilot = true
	f.wing_health = [1.0, 0.2]   # Right wing shredded.
	_sim(f, 3.0)
	_check(f.roll > 0.2, "damaged right wing: plane rolls right (roll %.2f)" % f.roll)


func _test_pushover_makes_cabin_floaty() -> void:
	var f := FlightModel.new()
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
