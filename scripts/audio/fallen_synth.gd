class_name FallenSynth
extends RefCounted
## Short procedural buffers for Contractor: Fallen's soundscape, tension bed and music moments
## (docs/survival_audio.md; call 63). Placeholders in the house style of SfxSynth: mono, 16 bit,
## MIX_RATE; a loop's ends are cross-faded so it meets itself at the seam. Every stream is built
## once and kept (`get_stream`). No game dependencies but MusicMoments' tunes.

const MIX_RATE := 22050
const FADE_S := 0.25  # a loop's cross-fade at the seam

static var _cache := {}


## The stream called `name` (see `build`), built the first time it's asked for.
static func get_stream(name: String) -> AudioStreamWAV:
	if not _cache.has(name):
		_cache[name] = build(name)
	return _cache[name]


## Builds one named sound: "wind", "rain", "birds", "hum", "breath", "shiver", "groan",
## "drone", "heartbeat_<bpm>", "static", or a music cue ("stinger_<moment>", "loop_<source>_<mood>").
static func build(name: String) -> AudioStreamWAV:
	match name:
		"wind":
			return wind(6.0, 11)
		"rain":
			return rain(4.0, 12)
		"birds":
			return birds(6.0, 13)
		"hum":
			return hum(50)
		"breath":
			return breath(3.2, false, 14)
		"shiver":
			return breath(2.4, true, 15)
		"groan":
			return groan(16)
		"drone":
			return drone(41)
		"static":
			return radio_static(0.6, 17)
	if name.begins_with("heartbeat_"):
		return heartbeat(int(name.trim_prefix("heartbeat_")))
	if name.begins_with("stinger_") or name.begins_with("loop_"):
		return MusicMoments.placeholder(name)
	return radio_static(0.1, 1)


# --- The beds -------------------------------------------------------------------------------

## Wind: low-passed noise that swells and drops (gusts) over the loop.
static func wind(seconds: float, seed_value: int) -> AudioStreamWAV:
	var rng := _rng(seed_value)
	var n := int(seconds * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var gust := 0.55 + 0.3 * sin(TAU * t / seconds) + 0.15 * sin(TAU * 3.0 * t / seconds + 1.3)
		lp += 0.03 * gust * (rng.randf_range(-1.0, 1.0) - lp)
		lp2 += 0.08 * (lp - lp2)
		s[i] = lp2 * gust
	return _wav(s, true, 0.7)


## Rain: high-passed hiss with drops on top.
static func rain(seconds: float, seed_value: int) -> AudioStreamWAV:
	var rng := _rng(seed_value)
	var n := int(seconds * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	var drop := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		low += 0.15 * (w - low)
		if rng.randf() < 0.0015:
			drop = rng.randf_range(0.4, 1.0)
		drop *= 0.985
		s[i] = (w - low) * 0.35 + rng.randf_range(-1.0, 1.0) * drop * 0.6
	return _wav(s, true, 0.55)


## Birds: a few chirps (quick rising and falling whistles) scattered over the loop.
static func birds(seconds: float, seed_value: int) -> AudioStreamWAV:
	var rng := _rng(seed_value)
	var n := int(seconds * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var chirps: Array[Array] = []
	var at := 0.2
	while at < seconds - 0.4:
		var count := rng.randi_range(1, 4)
		var hz := rng.randf_range(2400.0, 4200.0)
		for k in count:
			chirps.append([at + k * 0.11, hz * rng.randf_range(0.95, 1.08), rng.randf_range(0.05, 0.09)])
		at += rng.randf_range(0.6, 1.6)
	for c: Array in chirps:
		var start := int(float(c[0]) * MIX_RATE)
		var length := int(float(c[2]) * MIX_RATE)
		var phase := 0.0
		for j in length:
			if start + j >= n:
				break
			var u := float(j) / length
			var hz := float(c[1]) * (1.0 + 0.35 * sin(PI * u))
			phase += TAU * hz / MIX_RATE
			s[start + j] += sin(phase) * sin(PI * u) * 0.8
	return _wav(s, true, 0.5)


## A generator's or the lights' hum: a whole-number hz with its harmonics, a one-second loop.
static func hum(hz: int) -> AudioStreamWAV:
	var n := MIX_RATE
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		s[i] = sin(TAU * hz * t) * 0.6 + sin(TAU * hz * 2 * t) * 0.3 + sin(TAU * hz * 3 * t) * 0.15 + sin(TAU * 25 * t) * 0.1
	return _wav(s, true, 0.6, false)


## Your own breathing: band-limited noise swelling in and out; `shiver` adds a tremor and the teeth.
static func breath(seconds: float, shiver: bool, seed_value: int) -> AudioStreamWAV:
	var rng := _rng(seed_value)
	var n := int(seconds * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var hp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var u := t / seconds
		var env := pow(sin(PI * clampf(u / 0.45, 0.0, 1.0)), 2.0) * 0.9 + pow(sin(PI * clampf((u - 0.5) / 0.45, 0.0, 1.0)), 2.0) * 0.7
		if shiver:
			env *= 0.7 + 0.3 * sin(TAU * 9.0 * t)
		var w := rng.randf_range(-1.0, 1.0)
		lp += 0.25 * (w - lp)
		hp += 0.02 * (lp - hp)
		var v := (lp - hp) * env
		if shiver and fmod(t, 0.09) < 0.004:
			v += rng.randf_range(-0.5, 0.5)
		s[i] = v
	return _wav(s, true, 0.5)


## One of the dead's groans: a falling, wavering voice with breath in it.
static func groan(seed_value: int) -> AudioStreamWAV:
	var rng := _rng(seed_value)
	var seconds := 1.8
	var n := int(seconds * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var u := t / seconds
		var hz := lerpf(118.0, 72.0, u) * (1.0 + 0.04 * sin(TAU * 5.5 * t))
		phase += TAU * hz / MIX_RATE
		var env := minf(t / 0.15, 1.0) * (1.0 - u)
		lp += 0.1 * (rng.randf_range(-1.0, 1.0) - lp)
		s[i] = (sin(phase) * 0.6 + sin(phase * 2.0) * 0.3 + sin(phase * 3.0) * 0.2 + lp * 0.8) * env
	return _wav(s, false, 0.8)


## The tension bed's drone: a low note and a soured fifth, slowly beating (4 s loop).
static func drone(hz: int) -> AudioStreamWAV:
	var seconds := 4
	var n := seconds * MIX_RATE
	var s := PackedFloat32Array()
	s.resize(n)
	var fifth := hz * 3 / 2 - 1
	for i in n:
		var t := float(i) / MIX_RATE
		s[i] = sin(TAU * hz * t) * 0.6 + sin(TAU * fifth * t) * 0.25 + sin(TAU * hz * 2 * t) * 0.1 * (0.5 + 0.5 * sin(TAU * 0.25 * t))
	return _wav(s, true, 0.6, false)


## A heartbeat at `bpm`: lub-dub, one beat long, looped.
static func heartbeat(bpm: int) -> AudioStreamWAV:
	var beat := 60.0 / float(clampi(bpm, 40, 180))
	var n := int(beat * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var v := 0.0
		for hit: Array in [[0.0, 1.0], [0.16, 0.7]]:
			var dt := t - float(hit[0])
			if dt >= 0.0:
				v += sin(TAU * 52.0 * dt) * float(hit[1]) * minf(dt / 0.004, 1.0) * exp(-dt * 22.0)
		s[i] = v
	return _wav(s, true, 0.8, false)


## The radio between stations: band-limited crackle.
static func radio_static(seconds: float, seed_value: int) -> AudioStreamWAV:
	var rng := _rng(seed_value)
	var n := int(seconds * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		lp += 0.4 * (rng.randf_range(-1.0, 1.0) - lp)
		s[i] = lp * (1.0 if rng.randf() > 0.002 else 3.0)
	return _wav(s, false, 0.5)


# --- Music ----------------------------------------------------------------------------------

## A tune: `notes` MIDI numbers (0 a rest), each `beat_s` long, in a `timbre` ("pluck": a guitar's
## string, "box": a music box, "pad": a soft organ-ish swell), `loop` or a one-shot stinger.
static func melody(notes: Array, beat_s: float, timbre: String, loop: bool) -> AudioStreamWAV:
	var n := int(notes.size() * beat_s * MIX_RATE) + (0 if loop else int(1.2 * MIX_RATE))
	var s := PackedFloat32Array()
	s.resize(n)
	for k in notes.size():
		var midi := int(notes[k])
		if midi <= 0:
			continue
		var hz := 440.0 * pow(2.0, (midi - 69) / 12.0)
		var start := int(k * beat_s * MIX_RATE)
		var length := mini(int((beat_s * (3.0 if timbre == "pad" else 2.5)) * MIX_RATE), n - start if not loop else n)
		for j in length:
			var t := float(j) / MIX_RATE
			var v := 0.0
			match timbre:
				"pluck":
					v = (sin(TAU * hz * t) + 0.5 * sin(TAU * hz * 2.0 * t) + 0.25 * sin(TAU * hz * 3.0 * t)) * exp(-t * 3.5)
				"box":
					v = (sin(TAU * hz * 2.0 * t) + 0.3 * sin(TAU * hz * 5.0 * t)) * exp(-t * 5.0)
				_:
					v = (sin(TAU * hz * t) + 0.4 * sin(TAU * hz * 2.0 * t)) * minf(t / 0.3, 1.0) * exp(-t * 1.2)
			var idx := (start + j) % n if loop else start + j
			if idx < n:
				s[idx] += v * 0.4
	return _wav(s, loop, 0.7)


# --- Helpers --------------------------------------------------------------------------------

static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Normalised to `peak`, the seam of a loop cross-faded (`blend`), as a 16-bit WAV.
static func _wav(s: PackedFloat32Array, loop: bool, peak: float, blend := true) -> AudioStreamWAV:
	var n := s.size()
	if loop and blend:
		var f := mini(int(FADE_S * MIX_RATE), n / 4)
		for j in f:  # the tail fades into the head, so the loop's end runs on into its start
			var w := float(j) / f
			s[n - f + j] = s[n - f + j] * (1.0 - w) + s[j] * w
	var top := 0.0001
	for i in n:
		top = maxf(top, absf(s[i]))
	var gain := peak / top
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v := s[i] * gain
		if not loop and i > n - 200:
			v *= float(n - i) / 200.0
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav
