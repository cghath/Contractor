extends Node
## Contractor: Fallen's audio (docs/survival_audio.md; calls 63, 76, 142), headless (the dummy
## driver: the logic, not the sound): the bus layout; the soundscape's wind and rain by the
## weather, the crowd's groans from its bearing, birds that go quiet when one of the dead comes
## near; the tension layer following the stealth model (calm, alert, danger, the cooldown) and
## its toggle; a music moment firing once; every line with a voice key and a speaker; a line
## with no clip falling back to its subtitle; the renderer's dry-run manifest covering the lines.

var failures := 0


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("FALLENAUDIO TEST FAILED (timed out)")
		get_tree().quit(99))
	await get_tree().process_frame
	_test_buses()
	_test_soundscape()
	_test_birds()
	_test_tension()
	_test_toggle()
	_test_music()
	_test_node_step()
	_test_lines()
	_test_fallback()
	_test_talkativeness()
	_test_manifest()
	_test_synth()
	print("FALLENAUDIO TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(ok: bool, what: String) -> void:
	if ok:
		print("  [ok] " + what)
	else:
		failures += 1
		print("  [FAIL] " + what)


func _test_buses() -> void:
	print("buses")
	FallenAudio.ensure_buses()
	for bus: StringName in [&"World", &"Tension", &"Voice", &"Music"]:
		var i := AudioServer.get_bus_index(bus)
		check(i >= 0 and AudioServer.get_bus_send(i) == &"Master", "%s exists and goes to Master" % bus)
	var radio := AudioServer.get_bus_index(&"Radio")
	check(radio >= 0 and AudioServer.get_bus_send(radio) == &"Voice", "the radio goes through Voice")


func _ctx(extra := {}) -> Dictionary:
	var c := {"me": Vector2.ZERO, "weather": "clear", "wind_mps": 3.0, "hour": 12.0, "region": "plains", "crowd": [], "zombies": [], "living": [],
		"stamina": 1.0, "sleep": 90.0, "warmth": Needs.NORMAL_C, "day": 1, "season": "spring"}
	c.merge(extra, true)
	return c


func _test_soundscape() -> void:
	print("soundscape")
	var s := Soundscape.new()
	var clear := s.update(_ctx(), 0.0)
	check(float(clear.wind) > 0.0 and float(clear.wind) < 0.4 and float(clear.rain) == 0.0, "clear: a light wind, no rain (%.2f)" % float(clear.wind))
	var storm := s.update(_ctx({"weather": "storm", "wind_mps": 14.0}), 1.0)
	check(float(storm.rain) >= 0.99 and float(storm.wind) > float(clear.wind), "a storm: full rain, more wind")
	var rain_in := s.update(_ctx({"weather": "rain", "wind_mps": 7.0, "indoors": true}), 2.0)
	check(float(rain_in.rain) > 0.0 and float(rain_in.rain) < 0.6 and float(rain_in.wind) < 0.3, "indoors: the rain on the roof, the wind through the walls")
	check(float(clear.groans) == 0.0, "no crowd: no groans")
	var heads: Array[Vector2] = []
	for i in 25:
		heads.append(Vector2(60.0 + i, float(i % 5) - 2.0))
	var east := s.update(_ctx({"crowd": heads}), 3.0)
	var dir: Vector2 = east.groan_dir
	check(float(east.groans) > 0.1 and dir.x > 0.95, "a crowd to the east: groans from the east (%.2f, %s)" % [float(east.groans), dir])
	var few: Array[Vector2] = [Vector2(0.0, -200.0)]
	var north := s.update(_ctx({"crowd": few}), 4.0)
	check(float(north.groans) < float(east.groans) and (north.groan_dir as Vector2).y < -0.95, "one far off to the north: fainter, from the north")
	var tired := s.update(_ctx({"stamina": 0.1, "warmth": 35.5}), 5.0)
	check(float(tired.breath) > 0.3 and float(tired.shiver) > 0.0, "spent and cold: you hear yourself breathe and shiver")
	check(float(s.update(_ctx({"powered": true}), 6.0).hum) > 0.0 and float(clear.hum) == 0.0, "the settlement's power hums")


func _test_birds() -> void:
	print("birds")
	var s := Soundscape.new()
	check(float(s.update(_ctx(), 0.0).birds) > 0.0, "a quiet clear day: birds")
	var near := s.update(_ctx({"zombies": [{"d": 20.0, "mode": ZombieAI.Mode.IDLE, "awareness": 0.0}]}), 1.0)
	check(float(near.birds) == 0.0 and bool(near.birds_quiet), "one of the dead 20 m off: the birds go quiet")
	check(float(s.update(_ctx(), 11.0).birds) == 0.0, "and stay quiet a while after it's gone")
	check(float(s.update(_ctx(), 1.0 + Soundscape.BIRD_RETURN_S + 1.0).birds) > 0.0, "then come back")
	var heads: Array[Vector2] = [Vector2(10.0, 5.0)]
	check(float(s.update(_ctx({"crowd": heads}), 100.0).birds) == 0.0, "a crowd head near quiets them too")
	check(float(s.update(_ctx({"living": [15.0]}), 200.0).birds) == 0.0, "and a living stranger")
	check(float(Soundscape.new().update(_ctx({"hour": 23.0}), 0.0).birds) == 0.0, "no birds at night")
	check(float(Soundscape.new().update(_ctx({"weather": "rain"}), 0.0).birds) == 0.0, "none in the rain")


func _z(d: float, mode: int, aware := 0.0) -> Dictionary:
	return {"d": d, "mode": mode, "awareness": aware}


func _test_tension() -> void:
	print("tension")
	var t := Tension.new()
	check(t.update(_ctx(), 0.25) == Tension.Level.CALM, "nobody about: calm")
	check(t.update(_ctx({"zombies": [_z(30.0, ZombieAI.Mode.INVESTIGATE, 0.2)]}), 0.25) == Tension.Level.UNEASE, "a suspicious one near: unease")
	check(t.update(_ctx({"zombies": [_z(30.0, ZombieAI.Mode.ALERT, 0.5)]}), 0.25) == Tension.Level.ALERT, "an ALERT one within 60 m: alert")
	check(Tension.target_for(_ctx({"zombies": [_z(90.0, ZombieAI.Mode.ALERT, 0.5)]})) == Tension.Level.CALM, "an alert one 90 m off doesn't count")
	var chase := _ctx({"zombies": [_z(25.0, ZombieAI.Mode.CHASE, 1.0)]})
	check(t.update(chase, 0.25) == Tension.Level.DANGER, "a chase: danger")
	for i in 20:
		t.update(chase, 0.25)
	check(t.heart > 0.4 and t.drone > 0.4 and t.bpm() > 100, "the heartbeat and drone rise (%.2f, %.2f, %d bpm)" % [t.heart, t.drone, t.bpm()])
	t.update(_ctx(), 1.0)
	check(t.level == Tension.Level.DANGER, "it got away: still danger at first (the cooldown)")
	for i in int(Tension.COOLDOWN_S):
		t.update(_ctx(), 1.0)
	check(t.level == Tension.Level.ALERT, "after the cooldown it steps down one level (%s)" % t.level_name())
	for i in int(Tension.COOLDOWN_S * 3.0):
		t.update(_ctx(), 1.0)
	check(t.level == Tension.Level.CALM and t.heart < 0.05, "and in time back to calm")
	check(Tension.target_for(_ctx({"raid": true})) == Tension.Level.DANGER, "a raid: danger")
	check(Tension.target_for(_ctx({"delirium": "delirium"})) == Tension.Level.ALERT, "the bite's delirium: alert")
	check(Tension.target_for(_ctx({"zombies": [_z(40.0, ZombieAI.Mode.IDLE), _z(45.0, ZombieAI.Mode.IDLE), _z(50.0, ZombieAI.Mode.IDLE)]})) == Tension.Level.UNEASE,
		"three unaware close by: unease")


func _test_toggle() -> void:
	print("toggle")
	var was := bool(FallenAudio.setting("tension_on"))
	var t := Tension.new()
	var chase := _ctx({"zombies": [_z(25.0, ZombieAI.Mode.CHASE, 1.0)]})
	for i in 10:
		t.update(chase, 0.5)
	t.set_enabled(false)
	t.update(chase, 0.5)
	check(t.drone == 0.0 and t.heart == 0.0 and t.level == Tension.Level.DANGER, "the toggle off: silent (the level still tracked)")
	FallenAudio.set_setting("tension_on", false)
	var i := AudioServer.get_bus_index(&"Tension")
	check(AudioServer.is_bus_mute(i), "and the Tension bus muted")
	FallenAudio.set_setting("tension_on", true)
	check(not AudioServer.is_bus_mute(i) and AudioServer.get_bus_volume_db(i) < -5.0, "back on: under everything (%.1f dB)" % AudioServer.get_bus_volume_db(i))
	FallenAudio.set_setting("tension_on", was)


func _test_music() -> void:
	print("music")
	var m := MusicMoments.new({})
	check(m.update(_ctx({"day": 1, "hour": 22.0}), 0.0).is_empty(), "the first evening: nothing")
	var fired := m.update(_ctx({"day": 2, "hour": 6.5}), 10.0)
	check(fired == (["first_night"] as Array[String]), "dawn of day 2: the first night survived (%s)" % [fired])
	check(m.update(_ctx({"day": 2, "hour": 7.0}), 20.0).is_empty() and m.update(_ctx({"day": 3, "hour": 7.0}), 30.0).is_empty(), "once only")
	check(m.update(_ctx({"day": 3, "dead": true}), 40.0) == (["death"] as Array[String]), "a death")
	check(m.update(_ctx({"day": 3, "dead": true}), 41.0).is_empty(), "once per death")
	m.update(_ctx({"day": 3, "season": "winter"}), 50.0)
	check(m.update(_ctx({"day": 3, "season": "spring"}), 51.0) == (["thaw"] as Array[String]), "winter into spring: the thaw")
	check(m.update(_ctx({"day": 4, "evac": true}), 60.0) == (["evac"] as Array[String]), "the evac reached")
	check(m.loop == "", "no music out in the world")
	m.update(_ctx({"day": 4, "at_settlement": true, "music_source": "radio", "morale": 70.0}), 70.0)
	check(m.loop == "loop_radio_warm", "at the settlement with a radio, in good spirits: a warm loop (%s)" % m.loop)
	m.update(_ctx({"day": 4, "at_settlement": true, "music_source": "guitar", "morale": 20.0}), 71.0)
	check(m.loop == "loop_guitar_low", "a guitar, low spirits (%s)" % m.loop)
	m.update(_ctx({"day": 4, "at_settlement": true, "music_source": "radio", "morale": 70.0, "tension_level": Tension.Level.ALERT}), 72.0)
	check(m.loop == "", "no combat music: it stops when it gets tense")
	check(MusicMoments.source_at_settlement([{"traits": ["guitar"]}], false) == "guitar" and MusicMoments.source_at_settlement([{"kit": [["guitar", 1]]}], false) == "guitar"
		and MusicMoments.source_at_settlement([], true) == "radio" and MusicMoments.source_at_settlement([], false) == "", "what plays at the settlement")
	check(MusicMoments.file_for("stinger_first_night") == "" and MusicMoments.stream_for("stinger_first_night") is AudioStreamWAV, "no file yet: the placeholder tune")


func _test_node_step() -> void:
	print("the node")
	var fa := FallenAudio.new()
	fa.music = MusicMoments.new({})
	add_child(fa)
	fa.step(_ctx({"day": 2, "hour": 7.0, "weather": "rain", "wind_mps": 7.0}), 0.25)
	fa.step(_ctx({"day": 2, "hour": 8.0, "weather": "rain", "wind_mps": 7.0}), 0.25)
	check(fa.cues.count("moment:first_night") == 1, "the first night's stinger fires once through the node")
	var rain: AudioStreamPlayer = fa._players.get("rain")
	check(rain != null and rain.bus == &"World" and rain.stream is AudioStreamWAV, "the rain plays on the World bus")
	check(not fa._players.has("birds"), "no birds in the rain (never even built)")
	var r := fa.step(_ctx({"zombies": [_z(25.0, ZombieAI.Mode.CHASE, 1.0)]}), 0.25)
	check(int(r.tension) == Tension.Level.DANGER and FallenAudio.tension_now == Tension.Level.DANGER and VoiceLines.quiet_now(), "the tension is shared: companions keep quiet")
	fa.step(_ctx({"zombies": [_z(25.0, ZombieAI.Mode.CHASE, 1.0)]}), 2.0)
	var heart: AudioStreamPlayer = fa._players.get("heart")
	check(heart != null and heart.bus == &"Tension", "the heartbeat plays on the Tension bus")
	var numbers := String(FallenRadio.NUMBERS_CANNED[1])
	var played := fa.radio(numbers)
	check(played == "" and fa.cues.has("radio") and String(VoiceLines.played[-1].voice) == "radio_02", "a numbers broadcast: static, its line known (radio_02), no clip yet")
	fa.queue_free()
	FallenAudio.tension_now = 0


func _test_lines() -> void:
	print("lines")
	var keys := {}
	var bad: Array[String] = []
	var n := 0
	var topics := TalkMenu.lines()
	for topic: String in topics:
		for line: Dictionary in topics[topic]:
			n += 1
			var sp: Variant = line.get("speaker")
			var voice := String(line.get("voice", ""))
			if voice == "" or keys.has(voice) or not (sp is Dictionary) or not (sp as Dictionary).has_all(["kind", "sex", "age"]) \
					or not String((sp as Dictionary).kind) in VoiceLines.SPEAKER_KINDS:
				bad.append("%s: %s" % [topic, line.get("text", "")])
			keys[voice] = true
	check(n > 100 and bad.is_empty(), "all %d lines have a unique voice key and a speaker (%s)" % [n, bad])
	check(topics.has("radio") and topics.has("raider_warn") and topics.has("enclave_halt"), "the radio, raiders and the enclave have lines")
	var r := VoiceLines.resolve("Name's Kim. I was a nurse, before.")
	check(String(r.get("voice", "")) == "greet_02" and not bool(r.voiceable), "a filled line is found (greet_02); a name in it: subtitle only")
	check(String(VoiceLines.resolve("Got canned meat.").get("voice", "")) == "took_item_01", "an {item} line found (took_item_01)")
	check(VoiceLines.resolve("Something nobody wrote.").is_empty(), "an unknown line: none")
	var vs := VoiceLines.voice_set("f", 70, "abc")
	check(vs == "f_old_1" and VoiceLines.voice_set("m", 30, "abc").begins_with("m_adult_"), "voice sets by sex and age (%s)" % vs)


func _test_fallback() -> void:
	print("fallback")
	check(VoiceLines.path_for("greet_03", "m_adult_1") == "", "no clip rendered for greet_03")
	var path := VoiceLines.play_people("Stay back. Please. I don't want any trouble.", null)
	var last: Dictionary = VoiceLines.played[-1]
	check(path == "" and String(last.voice) == "greet_03" and String(last.path) == "", "a line with no clip: no sound, the subtitle alone (Callouts shows it either way)")


func _test_talkativeness() -> void:
	print("talkativeness")
	var timid := {"traits": ["timid", "lazy"]}
	var loud := {"traits": ["hot_headed", "brave", "drinker"]}
	check(VoiceLines.talkativeness(timid) < VoiceLines.talkativeness(loud), "the timid talk less than the hot-headed")
	check(VoiceLines.talkativeness({"talkativeness": 0.9}) == 0.9, "a set talkativeness wins")
	check(VoiceLines.should_say(timid, "plan_idle", false, 0.1) and not VoiceLines.should_say(timid, "plan_idle", false, 0.6), "chatter by talkativeness")
	check(not VoiceLines.should_say(loud, "plan_idle", true, 0.0), "quiet when it's tense: no chatter")
	check(VoiceLines.should_say(timid, "spotted_dead", true, 0.99), "but the urgent calls still come")


func _test_manifest() -> void:
	print("manifest")
	var text := FileAccess.get_file_as_string("res://tools/voices/survival_manifest.json")
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	if not (parsed is Dictionary):
		check(false, "the renderer's dry-run manifest is there")
		return
	var m: Dictionary = parsed
	var by_key := {}
	for it: Dictionary in m.get("items", []):
		by_key[String(it.key)] = (by_key.get(String(it.key), []) as Array) + [String(it.voice)]
	var missing: Array[String] = []
	var topics := TalkMenu.lines()
	for topic: String in topics:
		for line: Dictionary in topics[topic]:
			var sets: Array = by_key.get(String(line.voice), [])
			if sets.is_empty():
				missing.append(String(line.voice))
			elif topic == "radio" and not sets.all(func(v: String) -> bool: return v.begins_with("radio_")):
				missing.append(String(line.voice) + " (not a radio voice)")
	check(missing.is_empty(), "the dry run lists every line in the voices that say it (%d clips; %s)" % [int(m.get("clips", 0)), missing])
	check(String(m.get("engine", "")) == "piper", "Piper is the default engine")
	var cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/voices/survival_tts.json"))
	var ok := cfg is Dictionary
	if ok:
		for key: String in VoiceLines.VOICE_SETS:
			for k in int(VoiceLines.VOICE_SETS[key]):
				ok = ok and ((cfg as Dictionary).voices as Dictionary).has("%s_%d" % [key, k + 1])
		ok = ok and ((cfg as Dictionary).engines as Dictionary).has_all(["piper", "kokoro", "xtts"])
	check(ok, "the TTS config names every voice set and the three engines")


func _test_synth() -> void:
	print("synth")
	var wind := FallenSynth.get_stream("wind")
	check(wind.loop_mode == AudioStreamWAV.LOOP_FORWARD and wind.data.size() > 1000, "the wind is a loop")
	check(FallenSynth.get_stream("heartbeat_120").data.size() == int(0.5 * FallenSynth.MIX_RATE) * 2, "a heartbeat at 120 bpm is one beat long")
	check(FallenSynth.get_stream("groan").loop_mode == AudioStreamWAV.LOOP_DISABLED, "a groan plays once")
