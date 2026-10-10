extends RefCounted
## Pure helpers for proximity voice chat (no scene access, unit-tested in tests/run_tests.gd).
## Audio on the wire: 16 kHz mono, 20 ms frames (320 samples), G.711 μ-law (1 byte per sample).
## Packet layout (PackedByteArray, little endian):
##   [0]    u8  VERSION
##   [1..2] u16 sequence number (wraps at 65536)
##   [3..4] u16 sample count N
##   [5..]  N μ-law bytes
## A 20 ms frame is 325 bytes, so one talker costs ~16 kB/s up and the host relays the same to each peer.

const VERSION := 1
const SAMPLE_RATE := 16000
const FRAME_SAMPLES := 320            ## 20 ms at 16 kHz.
const HEADER_BYTES := 5
const MAX_SAMPLES := FRAME_SAMPLES * 4
const _BIAS := 0x84
const _CLIP := 32635

static var _decode_table := PackedFloat32Array()


## Encodes one float sample (-1..1) as a G.711 μ-law byte.
static func mulaw_encode_sample(x: float) -> int:
	var s := int(clampf(x, -1.0, 1.0) * 32767.0)
	var sign := 0
	if s < 0:
		sign = 0x80
		s = -s
	s = mini(s, _CLIP) + _BIAS
	var exponent := 7
	var mask := 0x4000
	while exponent > 0 and (s & mask) == 0:
		exponent -= 1
		mask >>= 1
	var mantissa := (s >> (exponent + 3)) & 0x0F
	return ~(sign | (exponent << 4) | mantissa) & 0xFF


## Decodes one μ-law byte back to a float sample (-1..1).
static func mulaw_decode_sample(b: int) -> float:
	var u := ~b & 0xFF
	var exponent := (u >> 4) & 0x07
	var s := (((u & 0x0F) << 3) + _BIAS) << exponent
	s -= _BIAS
	return float(-s if u & 0x80 else s) / 32768.0


static func mulaw_encode(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size())
	for i in samples.size():
		out[i] = mulaw_encode_sample(samples[i])
	return out


static func mulaw_decode(data: PackedByteArray) -> PackedFloat32Array:
	if _decode_table.is_empty():
		_decode_table.resize(256)
		for b in 256:
			_decode_table[b] = mulaw_decode_sample(b)
	var out := PackedFloat32Array()
	out.resize(data.size())
	for i in data.size():
		out[i] = _decode_table[data[i]]
	return out


## Streaming linear resampler (keeps its fractional position between blocks, so chunked input
## produces the same output as one big block: n_in * to_rate / from_rate samples, within 1).
class Resampler:
	var step := 1.0
	var _pos := 0.0
	var _pending := PackedFloat32Array()

	func _init(from_rate: float, to_rate: float) -> void:
		step = from_rate / to_rate

	func push(samples: PackedFloat32Array) -> PackedFloat32Array:
		_pending.append_array(samples)
		var out := PackedFloat32Array()
		var last := _pending.size() - 1
		while int(_pos) < last:
			var i0 := int(_pos)
			out.append(lerpf(_pending[i0], _pending[i0 + 1], _pos - i0))
			_pos += step
		var drop := mini(int(_pos), _pending.size())
		_pending = _pending.slice(drop)
		_pos -= drop
		return out


## Builds one network packet from 16 kHz mono samples (at most MAX_SAMPLES).
static func encode_packet(seq: int, samples: PackedFloat32Array) -> PackedByteArray:
	var n := mini(samples.size(), MAX_SAMPLES)
	var pkt := PackedByteArray()
	pkt.resize(HEADER_BYTES)
	pkt[0] = VERSION
	pkt.encode_u16(1, seq & 0xFFFF)
	pkt.encode_u16(3, n)
	pkt.append_array(mulaw_encode(samples.slice(0, n)))
	return pkt


## Parses a packet. Returns {seq: int, samples: PackedFloat32Array}, or {} if it is malformed.
static func decode_packet(pkt: PackedByteArray) -> Dictionary:
	if pkt.size() < HEADER_BYTES or pkt[0] != VERSION:
		return {}
	var n := pkt.decode_u16(3)
	if n == 0 or n > MAX_SAMPLES or pkt.size() != HEADER_BYTES + n:
		return {}
	return {"seq": pkt.decode_u16(1), "samples": mulaw_decode(pkt.slice(HEADER_BYTES))}


## True if sequence `a` is newer than `b` (with 16-bit wrap-around).
static func seq_newer(a: int, b: int) -> bool:
	var d := (a - b) & 0xFFFF
	return d != 0 and d < 0x8000


## Root-mean-square level of a block (voice activation).
static func rms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var acc := 0.0
	for s in samples:
		acc += s * s
	return sqrt(acc / samples.size())
