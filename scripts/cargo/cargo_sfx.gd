extends RefCounted
## Tiny synthesized sounds for the cargo hold (clucks, wing flaps, crocodile snaps and hisses,
## explosions, the mystery crate's hum, shattering porcelain and ratchet straps). Generated once
## per name and cached; pure cosmetics, safe on every peer from on_net_event.

const MIX_RATE := 22050
const DURATIONS := {"cluck": 0.22, "bawk": 0.5, "flap": 0.35, "snap": 0.25, "hiss": 0.8, "boom": 1.4,
	"hum": 1.6, "warble": 1.0, "shatter": 0.7, "ratchet": 0.45, "unstrap": 0.25, "creak": 0.5}

static var _sounds := {}


## Plays `sound_name` at a global position. `pitch` scales the (slightly randomised) pitch.
static func play(parent: Node, at: Vector3, sound_name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _sounds.has(sound_name):
		_sounds[sound_name] = _synth(sound_name)
	var p := AudioStreamPlayer3D.new()
	p.stream = _sounds[sound_name]
	p.volume_db = volume_db
	p.unit_size = 5.0 if sound_name == "boom" else 3.5
	p.pitch_scale = pitch * randf_range(0.93, 1.07)
	parent.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()


static func _synth(sound_name: String) -> AudioStreamWAV:
	var dur: float = DURATIONS.get(sound_name, 0.3)
	var n := int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var phase2 := 0.0
	var low := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var k := t / dur
		var v := 0.0
		match sound_name:
			"cluck":
				# Two quick throaty pulses with a falling pitch.
				var pulse := fmod(t, 0.11) / 0.11
				phase += (520.0 - 260.0 * pulse) / MIX_RATE
				v = (fposmod(phase, 1.0) * 2.0 - 1.0) * 0.4 * sin(pulse * PI) * (1.0 - k * 0.5)
			"bawk":
				# "Buk-buk-BAWK": two short clucks then a long rising squawk.
				if t < 0.18:
					var pulse := fmod(t, 0.09) / 0.09
					phase += (500.0 - 200.0 * pulse) / MIX_RATE
					v = (fposmod(phase, 1.0) * 2.0 - 1.0) * 0.35 * sin(pulse * PI)
				else:
					var q := (t - 0.18) / (dur - 0.18)
					phase += (700.0 + 500.0 * sin(q * PI) + 40.0 * sin(t * 90.0)) / MIX_RATE
					v = (fposmod(phase, 1.0) * 2.0 - 1.0) * 0.4 * sin(q * PI)
			"flap":
				# Feathery noise bursts at wingbeat rate.
				v = randf_range(-1, 1) * 0.35 * maxf(0.0, sin(t * 22.0 * TAU)) * (1.0 - k)
			"snap":
				# Jaws: a hard wooden clack plus a low thump.
				v = randf_range(-1, 1) * 0.7 * exp(-t * 55.0) + sin(t * 110.0 * TAU) * 0.6 * exp(-t * 18.0)
			"hiss":
				low = lerpf(low, randf_range(-1, 1), 0.6)
				v = (randf_range(-1, 1) - low) * 0.4 * sin(k * PI) * (0.7 + 0.3 * sin(t * 13.0 * TAU))
			"boom":
				low = lerpf(low, randf_range(-1, 1), 0.08)
				v = low * 2.4 * exp(-t * 3.0) + sin(t * (55.0 - 20.0 * k) * TAU) * 0.6 * exp(-t * 4.0) \
					+ randf_range(-1, 1) * 0.5 * exp(-t * 14.0)
			"hum":
				phase += (110.0 + 6.0 * sin(t * 5.0 * TAU)) / MIX_RATE
				phase2 += (165.5 + 9.0 * sin(t * 3.0 * TAU)) / MIX_RATE
				v = (sin(phase * TAU) + 0.6 * sin(phase2 * TAU)) * 0.28 * sin(k * PI)
			"warble":
				phase += (600.0 + 450.0 * sin(t * 9.0 * TAU) + 400.0 * k) / MIX_RATE
				v = sin(phase * TAU) * 0.3 * sin(k * PI)
			"shatter":
				# Porcelain: bright random pings over a crunchy burst.
				var ping := sin(t * (2600.0 + 900.0 * sin(float(i / 900) * 12.9898)) * TAU) * exp(-fmod(t, 0.08) * 40.0)
				v = randf_range(-1, 1) * 0.55 * exp(-t * 12.0) + ping * 0.25 * (1.0 - k)
			"ratchet":
				# Strap ratchet: a train of clicks.
				var c := fmod(t, 0.075)
				v = randf_range(-1, 1) * 0.5 * exp(-c * 160.0) + sin(t * 1900.0 * TAU) * 0.15 * exp(-c * 90.0)
			"unstrap":
				v = randf_range(-1, 1) * 0.45 * (1.0 - k) * (0.5 + 0.5 * signf(sin(t * 140.0 * TAU)))
			"creak":
				phase += (90.0 + 40.0 * sin(t * 4.0 * TAU)) / MIX_RATE
				v = (fposmod(phase, 1.0) * 2.0 - 1.0) * 0.25 * sin(k * PI) * (0.6 + 0.4 * randf())
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.data = data
	return w
