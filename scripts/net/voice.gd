extends Node
## Proximity voice chat (World module "Voice", runs on every peer).
##
## Capture: an AudioStreamMicrophone plays into the muted "VoiceMic" bus, whose AudioEffectCapture we
## drain every frame. The stereo mix-rate signal is downmixed to mono, scaled by Settings.mic_gain,
## resampled to 16 kHz and cut into 20 ms μ-law frames (VoiceCodec). Settings.voice_mode picks
## "push" (hold [T], action `talk`), "open" (voice activation by level) or "off".
## Transport: client -> host `_rpc_voice_up` (unreliable_ordered, own channel); the host relays to
## every other ready peer within earshot (`_rpc_voice_down`), the same pattern as player state.
## Playback: each remote talker gets an AudioStreamGenerator on an AudioStreamPlayer3D on their head
## (positional, MAX_DISTANCE). A small jitter buffer (JITTER_FRAMES) primes each talk spurt.
## Visuals: a billboard speaker icon over a talking player's name label, and a TALKING badge on
## your own HUD (own CanvasLayer).
## No microphone / permission denied / headless: logs once and stays receive-only.
## Dev flag (after `--`): --voice-test-tone sends a 440 Hz tone instead of the mic, always on.

const VoiceCodec := preload("res://scripts/net/voice_codec.gd")

const BUS_NAME := "VoiceMic"
const MAX_DISTANCE := 25.0
const RELAY_DISTANCE := MAX_DISTANCE + 5.0  ## Host skips relaying to peers farther than this.
const JITTER_FRAMES := 4                    ## 80 ms queued before a talk spurt starts playing.
const MAX_QUEUE_FRAMES := 12                ## Oldest frames dropped beyond 240 ms of backlog.
const TARGET_BUFFERED := VoiceCodec.FRAME_SAMPLES * 3  ## Samples kept inside the generator.
const TALK_HOLD := 0.3                      ## Icon stays this long after the last packet.
const VAD_THRESHOLD := 0.02                 ## RMS level that opens voice activation.
const VAD_HANGOVER := 0.4
const MIC_TIMEOUT := 2.5                    ## No captured audio after this long: receive-only.
const STATS_INTERVAL := 2.0
const TONE_HZ := 440.0
const ICON_SIZE := 64
const ICON_PIXEL := 0.0065
const ICON_ABOVE_LABEL := 0.3

var world: World
var talking := false   ## The local player is transmitting right now.
var mic_ok := false    ## Captured audio has arrived from the microphone.

var _test_tone := false
var _mic_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _resampler: VoiceCodec.Resampler
var _pcm := PackedFloat32Array()   ## 16 kHz mono waiting to be cut into frames.
var _seq := 0
var _mic_wait := 0.0
var _mic_warned := false
var _vad_hold := 0.0
var _tone_phase := 0.0
var _tone_acc := 0.0
var _sent := 0
var _recv := 0
var _stats_t := 0.0
var _logged := Vector2i(-1, -1)
var _speakers := {}                ## peer_id -> Speaker
var _hud_badge: PanelContainer
var _hud_text: Label

static var _icon_tex: ImageTexture


## Playback state for one remote talker.
class Speaker:
	var player: Player
	var audio: AudioStreamPlayer3D
	var playback: AudioStreamGeneratorPlayback
	var icon: Sprite3D
	var capacity := 0
	var queue: Array[PackedFloat32Array] = []
	var last_seq := -1
	var last_heard := -100.0
	var primed := false


func setup(p_world: World) -> void:
	world = p_world
	_test_tone = OS.get_cmdline_user_args().has("--voice-test-tone")
	if _test_tone:
		print("[voice %d] test tone enabled (--voice-test-tone)" % multiplayer.get_unique_id())
	_build_hud()
	Settings.changed.connect(_apply_settings)
	_apply_settings()


func _exit_tree() -> void:
	if Settings.changed.is_connected(_apply_settings):
		Settings.changed.disconnect(_apply_settings)


func _apply_settings() -> void:
	if Settings.voice_mode == "off":
		_stop_mic()
	else:
		_start_mic()
	var db := linear_to_db(maxf(Settings.voice_volume, 0.0001))
	for sp: Speaker in _speakers.values():
		if is_instance_valid(sp.audio):
			sp.audio.volume_db = db


# --- Capture --------------------------------------------------------------------------------

func _start_mic() -> void:
	if _mic_player != null or _test_tone:
		return
	if DisplayServer.get_name() == "headless":
		return
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		_warn_no_mic("audio input is disabled in the project settings")
		return
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS_NAME)
		# Muted so you never hear yourself; effects still run before the mute is applied.
		AudioServer.set_bus_mute(idx, true)
		AudioServer.add_bus_effect(idx, AudioEffectCapture.new())
	_capture = AudioServer.get_bus_effect(idx, 0) as AudioEffectCapture
	_capture.clear_buffer()
	_resampler = VoiceCodec.Resampler.new(AudioServer.get_mix_rate(), VoiceCodec.SAMPLE_RATE)
	_mic_player = AudioStreamPlayer.new()
	_mic_player.name = "Mic"
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = BUS_NAME
	add_child(_mic_player)
	_mic_player.play()
	_mic_wait = 0.0
	mic_ok = false


func _stop_mic() -> void:
	if _mic_player:
		_mic_player.queue_free()
	_mic_player = null
	_capture = null
	mic_ok = false
	talking = false
	_pcm.clear()


func _warn_no_mic(why: String) -> void:
	if _mic_warned:
		return
	_mic_warned = true
	print("[voice %d] no microphone (%s); voice chat is receive-only" % [multiplayer.get_unique_id(), why])


func _process(dt: float) -> void:
	_update_capture(dt)
	_update_speakers()
	_update_hud()
	_stats_t += dt
	if _stats_t >= STATS_INTERVAL:
		_stats_t = 0.0
		if _logged != Vector2i(_sent, _recv):
			_logged = Vector2i(_sent, _recv)
			print("[voice %d] frames sent=%d received=%d" % [multiplayer.get_unique_id(), _sent, _recv])


func _update_capture(dt: float) -> void:
	talking = false
	if Settings.voice_mode == "off":
		return
	if _test_tone:
		talking = true
		_tone_acc += dt * VoiceCodec.SAMPLE_RATE
		var n := int(_tone_acc)
		_tone_acc -= n
		var block := PackedFloat32Array()
		block.resize(n)
		for i in n:
			block[i] = sin(_tone_phase) * 0.3
			_tone_phase = fmod(_tone_phase + TAU * TONE_HZ / VoiceCodec.SAMPLE_RATE, TAU)
		_pcm.append_array(block)
	elif _capture:
		var avail := _capture.get_frames_available()
		if avail > 0:
			mic_ok = true
		elif not mic_ok:
			_mic_wait += dt
			if _mic_wait > MIC_TIMEOUT:
				_warn_no_mic("no input device or microphone permission denied")
			return
		var stereo := _capture.get_buffer(avail)
		var mono := PackedFloat32Array()
		mono.resize(stereo.size())
		var gain := 0.5 * Settings.mic_gain
		for i in stereo.size():
			mono[i] = (stereo[i].x + stereo[i].y) * gain
		var pcm16 := _resampler.push(mono)
		var want := false
		if Settings.voice_mode == "push":
			want = Input.is_action_pressed("talk") and not world.input_blocked()
		else:
			_vad_hold = VAD_HANGOVER if VoiceCodec.rms(pcm16) > VAD_THRESHOLD else _vad_hold - dt
			want = _vad_hold > 0.0
		if not want:
			_pcm.clear()
			return
		talking = true
		_pcm.append_array(pcm16)
	else:
		return
	while _pcm.size() >= VoiceCodec.FRAME_SAMPLES:
		_send(_pcm.slice(0, VoiceCodec.FRAME_SAMPLES))
		_pcm = _pcm.slice(VoiceCodec.FRAME_SAMPLES)


func _send(frame: PackedFloat32Array) -> void:
	var pkt := VoiceCodec.encode_packet(_seq, frame)
	_seq = (_seq + 1) & 0xFFFF
	_sent += 1
	if world.is_server():
		_relay(1, pkt)
	else:
		_rpc_voice_up.rpc_id(1, pkt)


# --- Transport (host relays) ----------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _rpc_voice_up(pkt: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if world.is_server() and world._ready_peers.has(sender) \
			and pkt.size() <= VoiceCodec.HEADER_BYTES + VoiceCodec.MAX_SAMPLES:
		_relay(sender, pkt)


## Host: forwards a talker's packet to every other ready peer within earshot, and plays it here.
func _relay(sender: int, pkt: PackedByteArray) -> void:
	var src: Player = world.players.get(sender)
	if src == null:
		return
	for p: int in world._ready_peers:
		var dst: Player = world.players.get(p)
		if p != sender and dst and dst.global_position.distance_to(src.global_position) <= RELAY_DISTANCE:
			_rpc_voice_down.rpc_id(p, sender, pkt)
	if sender != multiplayer.get_unique_id():
		_receive(sender, pkt)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _rpc_voice_down(peer: int, pkt: PackedByteArray) -> void:
	_receive(peer, pkt)


func _receive(peer: int, pkt: PackedByteArray) -> void:
	if peer == multiplayer.get_unique_id():
		return
	var d := VoiceCodec.decode_packet(pkt)
	if d.is_empty():
		return
	var sp := _speaker(peer)
	if sp == null:
		return
	var seq: int = d.seq
	if sp.last_seq >= 0 and not VoiceCodec.seq_newer(seq, sp.last_seq):
		return
	_recv += 1
	sp.last_seq = seq
	sp.last_heard = Time.get_ticks_msec() * 0.001
	sp.queue.append(d.samples)
	while sp.queue.size() > MAX_QUEUE_FRAMES:
		sp.queue.pop_front()


# --- Playback -------------------------------------------------------------------------------

func _speaker(peer: int) -> Speaker:
	var sp: Speaker = _speakers.get(peer)
	if sp and is_instance_valid(sp.player):
		return sp
	var p: Player = world.players.get(peer)
	if p == null or p.head == null:
		return null
	sp = Speaker.new()
	sp.player = p
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = VoiceCodec.SAMPLE_RATE
	gen.buffer_length = 0.3
	sp.audio = AudioStreamPlayer3D.new()
	sp.audio.name = "Voice"
	sp.audio.stream = gen
	sp.audio.max_distance = MAX_DISTANCE
	sp.audio.unit_size = 4.0
	sp.audio.attenuation_filter_cutoff_hz = 6000.0
	sp.audio.volume_db = linear_to_db(maxf(Settings.voice_volume, 0.0001))
	p.head.add_child(sp.audio)
	sp.audio.play()
	sp.playback = sp.audio.get_stream_playback() as AudioStreamGeneratorPlayback
	sp.capacity = sp.playback.get_frames_available() if sp.playback else 0
	sp.icon = Sprite3D.new()
	sp.icon.name = "SpeakerIcon"
	sp.icon.texture = speaker_icon_texture()
	sp.icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.icon.pixel_size = ICON_PIXEL
	sp.icon.position.y = _label_height(p) + ICON_ABOVE_LABEL
	sp.icon.visible = false
	p.add_child(sp.icon)
	_speakers[peer] = sp
	return sp


func _label_height(p: Player) -> float:
	var parts: Dictionary = p.get("_tp_parts")
	var label: Node3D = parts.get("label") if parts else null
	return label.position.y if label else 2.2


func _update_speakers() -> void:
	var now := Time.get_ticks_msec() * 0.001
	for peer: int in _speakers.keys():
		var sp: Speaker = _speakers[peer]
		if not is_instance_valid(sp.player) or not is_instance_valid(sp.audio):
			_speakers.erase(peer)
			continue
		var on := now - sp.last_heard < TALK_HOLD
		sp.icon.visible = on
		if on:
			var s := 1.0 + 0.12 * sin(now * 14.0)
			sp.icon.scale = Vector3(s, s, s)
		if sp.playback == null:
			sp.queue.clear()
			continue
		if not sp.primed and sp.queue.size() >= JITTER_FRAMES:
			sp.primed = true
		if not sp.primed:
			continue
		var buffered := sp.capacity - sp.playback.get_frames_available()
		while not sp.queue.is_empty() and buffered < TARGET_BUFFERED:
			var frame: PackedFloat32Array = sp.queue.pop_front()
			var st := PackedVector2Array()
			st.resize(frame.size())
			for i in frame.size():
				st[i] = Vector2(frame[i], frame[i])
			sp.playback.push_buffer(st)
			buffered += frame.size()
		if sp.queue.is_empty() and buffered < VoiceCodec.FRAME_SAMPLES / 2:
			sp.primed = false   # Talk spurt over (or a gap): re-prime the jitter buffer next time.


## True while `peer` is heard talking (remote peers) or transmitting (local peer).
func is_talking(peer: int) -> bool:
	if peer == multiplayer.get_unique_id():
		return talking
	var sp: Speaker = _speakers.get(peer)
	return sp != null and Time.get_ticks_msec() * 0.001 - sp.last_heard < TALK_HOLD


# --- Visuals --------------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "VoiceHud"
	layer.layer = 6
	add_child(layer)
	_hud_badge = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.11, 0.26, 0.85)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(1, 0.84, 0.2)
	sb.set_border_width_all(3)
	sb.content_margin_left = 12
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_hud_badge.add_theme_stylebox_override("panel", sb)
	_hud_badge.anchor_left = 0.0
	_hud_badge.anchor_top = 1.0
	_hud_badge.anchor_bottom = 1.0
	_hud_badge.offset_left = 24
	_hud_badge.offset_top = -170
	_hud_badge.offset_bottom = -130
	_hud_badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hud_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_badge.visible = false
	layer.add_child(_hud_badge)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_hud_badge.add_child(row)
	var icon := TextureRect.new()
	icon.texture = speaker_icon_texture()
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	_hud_text = Label.new()
	_hud_text.add_theme_font_size_override("font_size", 20)
	_hud_text.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.1))
	_hud_text.add_theme_constant_override("outline_size", 6)
	_hud_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_hud_text)


func _update_hud() -> void:
	var trying := Settings.voice_mode == "push" and not _test_tone and Input.is_action_pressed("talk") \
		and not world.input_blocked()
	if talking:
		_hud_text.text = "TALKING"
		_hud_text.add_theme_color_override("font_color", Color(1, 0.84, 0.2))
		_hud_badge.modulate.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.012)
	elif trying:
		_hud_text.text = "NO MIC"
		_hud_text.add_theme_color_override("font_color", Color(0.7, 0.72, 0.8))
		_hud_badge.modulate.a = 1.0
	_hud_badge.visible = talking or trying


## Cartoon speaker glyph (white with a navy outline), built once and shared.
static func speaker_icon_texture() -> ImageTexture:
	if _icon_tex:
		return _icon_tex
	var n := ICON_SIZE
	var fill := PackedFloat32Array()
	fill.resize(n * n)
	for y in n:
		for x in n:
			var c := 0.0
			for sy in 2:
				for sx in 2:
					if _icon_inside(x + 0.25 + sx * 0.5, y + 0.25 + sy * 0.5):
						c += 0.25
			fill[y * n + x] = c
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var outline := Color(0.07, 0.11, 0.26)
	for y in n:
		for x in n:
			var edge := 0.0
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var xx := x + dx
					var yy := y + dy
					if dx * dx + dy * dy <= 10 and xx >= 0 and yy >= 0 and xx < n and yy < n:
						edge = maxf(edge, fill[yy * n + xx])
			var f := fill[y * n + x]
			var col := outline.lerp(Color.WHITE, f)
			col.a = maxf(edge, f)
			img.set_pixel(x, y, col)
	_icon_tex = ImageTexture.create_from_image(img)
	return _icon_tex


## Speaker shape in a 64x64 box: magnet block, flared cone, and two sound arcs.
static func _icon_inside(x: float, y: float) -> bool:
	var cy := 32.0
	if x >= 7.0 and x <= 18.0 and absf(y - cy) <= 7.0:
		return true
	if x >= 18.0 and x <= 31.0 and absf(y - cy) <= 7.0 + (x - 18.0) * 1.05:
		return true
	var d := Vector2(x - 31.0, y - cy)
	var r := d.length()
	if d.x > 0.0 and absf(atan2(d.y, d.x)) < 0.85:
		if (r >= 9.0 and r <= 13.5) or (r >= 18.5 and r <= 23.0):
			return true
	return false
