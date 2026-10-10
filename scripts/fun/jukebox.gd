extends FunStation
## A neon jukebox. [E] skips to the next "song"; every peer synthesises the tune locally from
## the shared song index (a little square-wave melody over a bass line, no audio assets).
## Local frame: the front faces +Z, the origin is on the floor.

const MIX := 22050.0
const SONGS := [
	{"name": "(silence)", "bpm": 0, "notes": [], "bass": []},
	{"name": "Fly Me To The Moon\n(But Not Like This)", "bpm": 120,
		"notes": [72, 71, 69, 67, 65, 67, 69, 72, 71, 69, 67, 65, 64, -1, -1, -1], "bass": [48, 43, 45, 41]},
	{"name": "Highway To The Danger Zone\n(Altitude Remix)", "bpm": 150,
		"notes": [64, 64, 67, 64, 69, 67, 64, 62, 64, 64, 67, 69, 71, 69, 67, -1], "bass": [40, 40, 43, 45]},
	{"name": "Leaving On A Jet Plane\n(Feet First)", "bpm": 100,
		"notes": [67, 69, 71, 71, 71, 69, 67, 64, 62, 64, 67, 67, -1, 67, 69, 71], "bass": [43, 48, 43, 50]},
	{"name": "Elevator Music\n(Wrong Vehicle)", "bpm": 90,
		"notes": [76, 72, 74, 67, -1, 67, 74, 76, 72, -1, 76, 74, 72, 74, 76, -1], "bass": [48, 45, 41, 43]},
	{"name": "Free Fallin'\n(Literally)", "bpm": 110,
		"notes": [79, 77, 76, 74, 72, 71, 69, 67, 65, 64, 62, 60, 59, 57, 55, -1], "bass": [43, 41, 40, 38]},
]

var _title: Label3D
var _lights: Array[MeshInstance3D] = []
var _player: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _t := 0.0
var _ph := 0.0
var _ph_b := 0.0
var _glow := 0.0


func default_state() -> Dictionary:
	return {"song": 1}


func _build() -> void:
	var wood := FunLooks.mat(Color(0.45, 0.2, 0.1), 0.35)
	var chrome := FunLooks.metal(FunLooks.CHROME)
	FunLooks.rounded_box(rig, Vector3(0.7, 1.05, 0.5), 0.06, wood, Vector3(0, 0.525, 0))
	part(FunLooks.cyl(0.35, 0.35, 0.5, 24), wood, Vector3(0, 1.05, 0), Vector3(PI / 2, 0, 0), Vector3(1, 1, 1))
	part(FunLooks.torus(0.3, 0.36), chrome, Vector3(0, 1.05, 0.25), Vector3(PI / 2, 0, 0), Vector3(1, 0.4, 1))
	for i in 8:
		var a := PI * (i + 0.5) / 8.0
		var m := part(FunLooks.sphere(0.035, 8), FunLooks.mat(FunLooks.CONFETTI[i % FunLooks.CONFETTI.size()], 0.3, 0.0, 2.0),
			Vector3(cos(a) * 0.33, 1.05 + sin(a) * 0.33, 0.26))
		_lights.append(m)
	part(FunLooks.box(Vector3(0.5, 0.25, 0.01)), FunLooks.mat(Color(0.95, 0.9, 0.7, 0.85), 0.1, 0.0, 0.6), Vector3(0, 1.08, 0.252))
	_title = label("", Vector3(0, 1.08, 0.26), 22, Color(0.2, 0.1, 0.05))
	_title.outline_size = 0
	for i in 6:
		part(FunLooks.cyl(0.012, 0.012, 0.5, 8), chrome, Vector3(-0.25 + i * 0.1, 0.45, 0.26), Vector3.ZERO)
	part(FunLooks.box(Vector3(0.56, 0.06, 0.04)), chrome, Vector3(0, 0.75, 0.25))
	part(FunLooks.capsule(0.03, 0.14), FunLooks.mat(Color(0.9, 0.15, 0.15), 0.3), Vector3(0.22, 0.82, 0.27), Vector3(0, 0, PI / 2))
	collider(Vector3(0.7, 1.35, 0.5), Vector3(0, 0.675, 0))
	area(Vector3(0.75, 1.4, 0.4), Vector3(0, 0.7, 0.3), "Next song on the jukebox [E]", "next")
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX
	gen.buffer_length = 0.2
	_player = AudioStreamPlayer3D.new()
	_player.stream = gen
	_player.unit_size = 3.0
	_player.volume_db = -14.0
	_player.max_distance = 14.0
	_player.position = Vector3(0, 0.8, 0.2)
	rig.add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


func _refresh(_fx: String) -> void:
	_title.text = String(SONGS[int(state.song)].name)
	_t = 0.0


func _play(fx: String, _args: Array) -> void:
	if fx == "clunk":
		FunFx.popup(world, global_point(Vector3(0, 1.5, 0.3)), "~ la la la ~", Color(1, 0.5, 0.9), 80)


func act(peer: int, verb: String, _args: Array) -> void:
	if verb == "next":
		state.song = (int(state.song) + 1) % SONGS.size()
		push_state("clunk")
		if int(state.song) != 0:
			world.say(world.display_name(peer), "*puts on \"%s\"*" % String(SONGS[int(state.song)].name).split("\n")[0], 2.5)


func _process(dt: float) -> void:
	var song: Dictionary = SONGS[int(state.song)]
	var bpm: int = song.bpm
	_glow += dt * (bpm / 30.0 if bpm > 0 else 0.5)
	for i in _lights.size():
		_lights[i].scale = Vector3.ONE * (1.0 + 0.35 * maxf(0.0, sin(_glow * PI + i)))
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(frames)
	var notes: Array = song.notes
	var bass: Array = song.bass
	var step := 60.0 / maxf(1.0, bpm) / 2.0
	for f in frames:
		var s := 0.0
		if bpm > 0:
			var idx := int(_t / step)
			var in_note := fmod(_t, step) / step
			var n: int = notes[idx % notes.size()]
			if n >= 0:
				_ph = fmod(_ph + _freq(n) / MIX, 1.0)
				s += (0.18 if _ph < 0.5 else -0.18) * (1.0 - in_note * 0.7)
			var b: int = bass[(idx / 4) % bass.size()]
			_ph_b = fmod(_ph_b + _freq(b) / MIX, 1.0)
			s += (absf(_ph_b * 4.0 - 2.0) - 1.0) * 0.22
			_t += 1.0 / MIX
		buf[f] = Vector2(s, s)
	_playback.push_buffer(buf)


static func _freq(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)
