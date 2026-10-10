extends Node
## Generated ambience (no assets): an engine drone whose pitch and loudness follow throttle and
## engine power (idling on the ground, spooling up on the takeoff roll), wind noise only while
## flying (louder when the local player is outside or the hull is open), and a low boom on crashes.

const MIX_RATE := 22050.0
const VOLUME_DB := -8.0

var world: World

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _freq := 55.0
var _engine := 0.0
var _wind := 0.0
var _rough := 0.0
var _ph := [0.0, 0.0, 0.0]
var _wind_l := 0.0
var _wind_r := 0.0
var _wind_l2 := 0.0
var _wind_r2 := 0.0
var _rumble := 0.0
var _boom := 0.0
var _boom_lp := 0.0
var _gust_t := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.15
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.volume_db = VOLUME_DB
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


## Big low thump for crashes.
func boom() -> void:
	_boom = 1.0


func _process(dt: float) -> void:
	if _playback == null or world == null:
		return
	var f := world.flight
	var running := f.phase != FlightModel.Phase.CRASHED and f.phase != FlightModel.Phase.LANDED
	var power: float = (f.engine_power[0] + f.engine_power[1]) * 0.5
	var spool := f.throttle * (0.55 + 0.45 * power)
	var target_freq := 42.0 + spool * 38.0 if running else 24.0
	var target_engine := (0.03 + 0.08 * f.throttle) * (0.3 + 0.7 * power) if running else 0.0
	var fire := 1.0 if world.plane.engine_fire[0] or world.plane.engine_fire[1] else 0.0
	var k := clampf(dt * 1.5, 0.0, 1.0)
	_freq = lerpf(_freq, target_freq, k)
	_engine = lerpf(_engine, target_engine, k)
	_rough = lerpf(_rough, fire, k)
	_wind = lerpf(_wind, _wind_target(f), clampf(dt * 3.0, 0.0, 1.0))
	_fill(dt)


## Wind loudness: only while flying. A hint indoors, louder with open windows/doors, loudest outside.
func _wind_target(f: FlightModel) -> float:
	if f.phase != FlightModel.Phase.FLYING:
		return 0.0
	var airflow := clampf(f.speed / 70.0, 0.0, 1.4)
	var level := 0.025
	var plane := world.plane
	var open := plane.ramp_open
	for w in plane.windows:
		open = open or bool(w.broken)
	for d in plane.doors:
		open = open or bool(plane.doors[d].open)
	if open:
		level += 0.09
	if world.local_player and world.local_player.outside:
		level += 0.22
	return level * airflow


func _fill(dt: float) -> void:
	var n := _playback.get_frames_available()
	if n <= 0:
		return
	_gust_t += dt
	var gust := 0.75 + 0.25 * sin(_gust_t * 0.7) * sin(_gust_t * 0.23 + 1.0)
	var buf := PackedVector2Array()
	buf.resize(n)
	var step := TAU * _freq / MIX_RATE
	var cut := 0.04 + 0.05 * gust
	var p0: float = _ph[0]
	var p1: float = _ph[1]
	var p2: float = _ph[2]
	for i in n:
		p0 = fmod(p0 + step, TAU)
		p1 = fmod(p1 + step * 1.007, TAU)
		p2 = fmod(p2 + step * 0.5, TAU)
		_rumble += (randf_range(-1.0, 1.0) - _rumble) * 0.02
		var drone := (sin(p0) * 0.5 + sin(p0 * 2.0) * 0.2 + sin(p1) * 0.4 + sin(p2) * 0.3) * _engine
		drone += _rumble * (_engine * 1.5 + _rough * 0.08)
		_wind_l += (randf_range(-1.0, 1.0) - _wind_l) * cut
		_wind_r += (randf_range(-1.0, 1.0) - _wind_r) * cut
		_wind_l2 += (_wind_l - _wind_l2) * cut
		_wind_r2 += (_wind_r - _wind_r2) * cut
		var thump := 0.0
		if _boom > 0.001:
			_boom_lp += (randf_range(-1.0, 1.0) - _boom_lp) * 0.03
			thump = (_boom_lp * 3.0 + sin(p2 * 0.7) * 0.4) * _boom
			_boom *= 0.99985
		var w := _wind * gust * 3.0
		buf[i] = Vector2(drone + _wind_l2 * w + thump, drone + _wind_r2 * w + thump).limit_length(1.2)
	_ph[0] = p0
	_ph[1] = p1
	_ph[2] = p2
	_playback.push_buffer(buf)
