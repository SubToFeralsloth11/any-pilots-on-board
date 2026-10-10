extends SceneTree
## Headless unit tests: godot --headless -s res://tests/run_tests.gd
## Exit code = number of failures.

var _failures := 0


func _init() -> void:
	_test_gentle_runway_landing_rolls_to_a_stop()
	_test_gear_up_touchdown_crashes()
	_test_hard_touchdown_crashes()
	_test_banked_touchdown_crashes()
	_test_flying_into_mountain_crashes()
	_test_unpiloted_plane_sinks_and_wanders()
	_test_stall_drops_the_nose()
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


func _approach(sink_pitch: float, gear: bool, roll := 0.0) -> FlightModel:
	var f := FlightModel.new()
	f.pos = FlightModel.RUNWAY_CENTER + Vector3(0, 3, 500)
	f.speed = 50.0
	f.throttle = 0.35
	f.pitch = sink_pitch
	f.roll = roll
	f.gear_down = gear
	f.has_pilot = true
	return f


func _run(f: FlightModel, max_steps := 20000) -> void:
	for i in max_steps:
		if f.phase == FlightModel.Phase.LANDED or f.phase == FlightModel.Phase.CRASHED:
			return
		f.step(1.0 / 60.0)


func _test_gentle_runway_landing_rolls_to_a_stop() -> void:
	var f := _approach(-0.04, true)
	_run(f)
	_check(f.phase == FlightModel.Phase.LANDED, "gentle gear-down touchdown ends LANDED")
	_check(f.touchdown.get("on_runway", false), "touchdown point is on the runway")
	_check(f.speed == 0.0, "plane rolled to a stop")


func _test_gear_up_touchdown_crashes() -> void:
	var f := _approach(-0.04, false)
	_run(f)
	_check(f.phase == FlightModel.Phase.CRASHED and "wheels" in f.touchdown.reason, "gear-up landing crashes (belly)")


func _test_hard_touchdown_crashes() -> void:
	var f := _approach(-0.3, true)
	f.pos.y = 40.0
	f.speed = 70.0
	_run(f)
	_check(f.phase == FlightModel.Phase.CRASHED and f.touchdown.sink > FlightModel.MAX_SINK, "steep dive into ground crashes")


func _test_banked_touchdown_crashes() -> void:
	var f := _approach(-0.04, true, 0.5)
	f.roll_in = 1.0   # Holding the bank, so it doesn't self-level.
	_run(f)
	_check(f.phase == FlightModel.Phase.CRASHED and "wing" in f.touchdown.reason, "touching down in a steep bank crashes")


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
	for i in 60 * 30:
		f.step(1.0 / 60.0)
		max_bank = maxf(max_bank, absf(f.roll))
	_check(f.pos.y < start_alt - 50.0, "nobody flying: plane loses altitude (%.0f m)" % (start_alt - f.pos.y))
	_check(max_bank > 0.1, "nobody flying: plane drifts into a bank (%.2f rad)" % max_bank)


func _test_stall_drops_the_nose() -> void:
	var f := FlightModel.new()
	f.has_pilot = true
	f.speed = 20.0
	f.throttle = 0.0
	var before := f.pitch
	for i in 60:
		f.step(1.0 / 60.0)
	_check(f.pitch < before and f.velocity.y < -5.0, "stalling drops the nose and sinks")


func _test_state_roundtrip() -> void:
	var a := FlightModel.new()
	a.pos = Vector3(12, 345, -678)
	a.yaw = 0.3
	a.pitch = -0.1
	a.roll = 0.2
	a.gear_down = true
	a.engine_power = [0.5, 0.9]
	a.has_pilot = true
	var b := FlightModel.new()
	b.from_array(a.to_array())
	_check(b.pos.distance_to(a.pos) < 0.01 and is_equal_approx(b.roll, a.roll) and b.gear_down and b.has_pilot \
		and is_equal_approx(b.engine_power[0], 0.5), "flight state survives to_array/from_array")


func _test_wall_spans() -> void:
	var s := Airliner.spans(0.0, 10.0, [Vector2(2, 3), Vector2(9, 12), Vector2(-5, -1)])
	var want: Array[Vector2] = [Vector2(0, 2), Vector2(3, 9)]
	_check(s == want, "wall spans subtract gaps, clipping at the ends")


func _test_scoring() -> void:
	var stats := {"windows_broken": 0, "items_lost": 0, "passengers_lost": 0, "things_broken": 0, "players_fell": 0}
	var runway := _approach(-0.04, true)
	_run(runway)
	var field := _approach(-0.04, true)
	field.pos.x += 400.0
	_run(field)
	var crash := _approach(-0.04, false)
	_run(crash)
	var r1 := Scoring.result(runway, stats)
	var r2 := Scoring.result(field, stats)
	var r3 := Scoring.result(crash, stats)
	_check(r1.landed and r2.landed and not r3.landed, "landed/crashed outcomes reported")
	_check(r1.score > r2.score and r3.score == 0, "runway beats a field landing; crashing scores 0")
	stats.passengers_lost = 3
	_check(Scoring.result(runway, stats).score < r1.score, "losing passengers costs points")
