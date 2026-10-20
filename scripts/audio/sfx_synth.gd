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
##   "thumps": [[time, amp, hz, decay], ...] short low impacts: a boot's heel, then its toe
##                                          rolling down (footsteps; times and pitch vary a little),
##   "grains": {"amp", "count", "from", "to", "decay", "lowpass"}  tiny random clicks scattered
##                                          between two times, softened: grit, gravel, grass crunch,
##   "rustle": {"amp", "from", "to", "lowpass"}  a soft swell of noise between two times: cloth
##                                          and kit moving with a step,
##   "variants" (Sfx): how many of it to build, for sounds heard over and over (footsteps),
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
	# Footstep layers (Captain, 2026-10-20: the steps were "terrible", a puff of noise): each
	# variant's thumps land a little earlier or later and higher or lower, its grains fall at
	# their own times.
	var thumps: Array = []
	for th: Array in recipe.get("thumps", []):
		thumps.append([float(th[0]) + rng.randf_range(-0.008, 0.008), float(th[1]) * rng.randf_range(0.8, 1.1),
			float(th[2]) * rng.randf_range(0.88, 1.12), float(th[3])])
	var grains: Dictionary = recipe.get("grains", {})
	var grain_at := PackedFloat32Array()
	var grain_amp := PackedFloat32Array()
	if not grains.is_empty():
		for g in int(grains.get("count", 0)):
			grain_at.append(rng.randf_range(float(grains.get("from", 0.0)), float(grains.get("to", 0.1))))
			grain_amp.append(rng.randf_range(0.3, 1.0))
	var grain_k := float(grains.get("lowpass", 0.5))
	var grain_lp := 0.0
	var rustle: Dictionary = recipe.get("rustle", {})
	var rustle_k := float(rustle.get("lowpass", 0.2)) * rng.randf_range(0.8, 1.2)
	var rustle_lp := 0.0
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
		for th: Array in thumps:
			var dt := t - float(th[0])
			if dt >= 0.0:
				var env := minf(dt / 0.002, 1.0) * exp(-dt * float(th[3]))
				v += (sin(TAU * float(th[2]) * dt) * 0.85 + rng.randf_range(-1.0, 1.0) * 0.15) * float(th[1]) * env
		if not grain_at.is_empty():
			var g := 0.0
			for k in grain_at.size():
				var dt := t - grain_at[k]
				if dt >= 0.0 and dt < 0.012:
					g += rng.randf_range(-1.0, 1.0) * grain_amp[k] * exp(-dt * float(grains.get("decay", 800.0)))
			grain_lp += grain_k * (g - grain_lp)
			v += grain_lp * float(grains.amp) * 2.0
		if not rustle.is_empty():
			var a := float(rustle.get("from", 0.0))
			var b := float(rustle.get("to", length))
			rustle_lp += rustle_k * (rng.randf_range(-1.0, 1.0) - rustle_lp)
			if t >= a and t < b:
				v += rustle_lp * 3.0 * float(rustle.amp) * sin(PI * (t - a) / maxf(b - a, 0.001))
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
