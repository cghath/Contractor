class_name SfxSynth
extends RefCounted
## Generated placeholder sounds for Sfx (autoload/sfx.gd), stylised rather than photo-real
## (Captain, 2026-10-12). No game dependencies, so tools can use it (tools/export_sounds.gd).

const MIX_RATE := 22050


## A placeholder sound from a recipe: up to four layers, each optional, mixed and
## normalised, then gently saturated so it sounds punchy rather than clipped:
##   "length" (s), "peak" (0-1),
##   "crack": {"amp", "decay"}             a white-noise transient (the attack),
##   "body": {"amp", "from_hz", "to_hz", "decay"}  a falling tone (the weight, a thump),
##   "tail": {"amp", "decay", "lowpass", "attack"}  low-passed noise (the boom, the rumble),
##   "ring": {"amp", "hz", "decay"}         a metallic ping (plates, brass),
##   "clicks": [[time, amp], ...]           short high clicks (mechanisms),
##   "highpass" (0-1): thins the whole sound (cracks, footsteps on hard ground).
static func make(recipe: Dictionary, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var looped := bool(recipe.get("loop", false))  # an engine: exactly "length" s, loops seamlessly
	var length := float(recipe.get("length", 0.5)) * (1.0 if looped else rng.randf_range(0.92, 1.08))
	var hum: Dictionary = recipe.get("hum", {})  # {"hz", "harmonics": [amp, ...], "amp", "wobble"}: a steady engine note
	var hum_hz := float(hum.get("hz", 0.0))
	var n := int(length * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var crack: Dictionary = recipe.get("crack", {})
	var body: Dictionary = recipe.get("body", {})
	var tail: Dictionary = recipe.get("tail", {})
	var ring: Dictionary = recipe.get("ring", {})
	var clicks: Array = recipe.get("clicks", [])
	var lp := 0.0
	var lp_k := float(tail.get("lowpass", 0.08)) * rng.randf_range(0.85, 1.15)
	var phase := 0.0
	var ring_hz := float(ring.get("hz", 0.0)) * rng.randf_range(0.95, 1.05)
	for i in n:
		var t := float(i) / MIX_RATE
		var v := 0.0
		if not crack.is_empty():
			v += rng.randf_range(-1.0, 1.0) * float(crack.amp) * exp(-t * float(crack.decay))
		if not body.is_empty():
			var hz := lerpf(float(body.from_hz), float(body.to_hz), clampf(t / length, 0.0, 1.0))
			phase += TAU * hz / MIX_RATE
			v += sin(phase) * float(body.amp) * exp(-t * float(body.decay))
		if not tail.is_empty():
			lp += lp_k * (rng.randf_range(-1.0, 1.0) - lp)
			var attack := float(tail.get("attack", 0.0))
			var rise := clampf(t / attack, 0.0, 1.0) if attack > 0.0 else 1.0
			v += lp * 3.0 * float(tail.amp) * rise * exp(-t * float(tail.decay))
		if ring_hz > 0.0:
			v += sin(TAU * ring_hz * t) * float(ring.amp) * exp(-t * float(ring.decay))
		if hum_hz > 0.0:  # whole-number hz over a whole-second loop: the waveform meets itself at the seam
			var harmonics: Array = hum.get("harmonics", [1.0])
			var wobble := 1.0 + float(hum.get("wobble", 0.0)) * sin(TAU * float(hum.get("wobble_hz", 4.0)) * t)  # cylinder beat, rotor thump
			for k in harmonics.size():
				v += sin(TAU * hum_hz * (k + 1) * t) * float(harmonics[k]) * float(hum.get("amp", 1.0)) * wobble
		for c: Array in clicks:
			var dt := t - float(c[0])
			if dt >= 0.0 and dt < 0.02:
				v += rng.randf_range(-1.0, 1.0) * float(c[1]) * exp(-dt * 400.0)
		samples[i] = v
	var hp := float(recipe.get("highpass", 0.0))
	if hp > 0.0:
		var prev := 0.0
		var low := 0.0
		for i in n:
			low += (1.0 - hp) * 0.2 * (samples[i] - low)
			prev = samples[i]
			samples[i] = prev - low
	var peak := 0.0001
	for i in n:
		peak = maxf(peak, absf(samples[i]))
	var gain := float(recipe.get("peak", 0.9)) / peak
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var s := tanh(samples[i] * gain * 1.4) / tanh(1.4)  # soft saturation: punch without clipping
		if i > n - 200 and not looped:
			s *= float(n - i) / 200.0  # no click at the end
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav
