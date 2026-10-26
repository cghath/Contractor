class_name FallenAudio
extends Node
## Contractor: Fallen's audio (calls 63, 76, 142; docs/survival_audio.md): one per survival level
## on every peer (Survival._process installs it), for this peer's own survivor. Every TICK_S it
## takes a snapshot of what's around you (`gather`) and runs the three parts on it (`step`):
## - the soundscape (Soundscape: wind, rain, the crowd's groans from its bearing, the
##   settlement's hum, your breathing and shivering, birds that go quiet) on the World bus;
## - the tension layer (Tension: a drone and a heartbeat by the stealth model) on the Tension bus;
## - music moments (MusicMoments: the settlement's radio or guitar, a few stingers) on Music.
## The radio's broadcasts play a burst of static and their voiced line on the Radio bus (into
## Voice; `on_flash`, from the HUD). People's lines are voiced by VoiceLines (Callouts._show).
##
## Buses: Master > World, Tension, Voice (> Radio, Intercom), Music, and Sfx's own (SFX, SFX_Room,
## Interior). Settings (SETTINGS_PATH, `setting`/`set_setting`): the World and Tension levels, the
## tension toggle (call 142), voice clips on or off (subtitles are always shown). The Music, Voice
## and Master sliders are the game's own (GameSettings "audio"); World follows its "effects" too.
## Headless (tests, a dedicated host): the same logic runs; the players play into the dummy driver.

const NODE_NAME := "FallenAudio"
const TICK_S := 0.25
const BUSES: Array[StringName] = [&"World", &"Tension", &"Voice", &"Music"]
const SETTINGS_PATH := "user://fallen_audio.cfg"
## Proposed: the defaults, and the tension bed's level under everything (near-subliminal).
const DEFAULTS := {"world": 1.0, "tension": 0.7, "tension_on": true, "voice_files": true}
const TENSION_DB := -10.0
const WORLD_LAYERS: Array[String] = ["wind", "rain", "hum", "breath", "shiver", "birds"]
const GROAN_GAP_S := Vector2(2.0, 7.0)  # between groans at full chorus .. faint
const GROAN_PLACE_M := 25.0  # a groan is played this far off along the crowd's bearing (at most its distance)
const CUES_KEPT := 60

## The local tension level (VoiceLines.quiet_now: companions keep quiet when it's alert or worse).
static var tension_now := 0
static var _settings := {}
static var _loaded := false

var soundscape := Soundscape.new()
var tension := Tension.new()
var music: MusicMoments
var mix := {}
var cues: Array[String] = []  # what fired, newest last: "moment:first_night", "radio", "groan", "loop:loop_radio_warm"
var level: Node
var _players := {}  # layer -> AudioStreamPlayer
var _tick := 0.0
var _groan_in := 0.0
var _bpm := 0
var _loop_cue := ""


func _init() -> void:
	name = NODE_NAME
	music = MusicMoments.new(_moments_store())


## Adds the audio to `p_level` once (any peer); returns it.
static func install(p_level: Node) -> FallenAudio:
	if p_level == null:
		return null
	var have := p_level.get_node_or_null(NODE_NAME) as FallenAudio
	if have:
		return have
	var fa := FallenAudio.new()
	fa.level = p_level
	p_level.add_child(fa)
	return fa


static func of(from: Node) -> FallenAudio:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NODE_NAME) as FallenAudio if lvl else null


func _ready() -> void:
	if level == null:
		level = get_parent()
	ensure_buses()
	apply_settings()
	tension.set_enabled(bool(setting("tension_on")))


func _exit_tree() -> void:
	tension_now = 0


# --- Buses and settings ---------------------------------------------------------------------

## Master > World, Tension, Voice, Music (Sfx makes Voice and Music too; this makes sure).
static func ensure_buses() -> void:
	for bus: StringName in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, &"Master")


static func setting(key: String) -> Variant:
	_load()
	return _settings.get(key, DEFAULTS.get(key))


static func set_setting(key: String, value: Variant) -> void:
	_load()
	_settings[key] = value
	var cfg := ConfigFile.new()
	for k: String in _settings:
		cfg.set_value("fallen_audio", k, _settings[k])
	cfg.save(SETTINGS_PATH)
	apply_settings()
	var fa := _live()
	if fa and key == "tension_on":
		fa.tension.set_enabled(bool(value))


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for k: String in cfg.get_section_keys("fallen_audio") if cfg.has_section("fallen_audio") else PackedStringArray():
			_settings[k] = cfg.get_value("fallen_audio", k)


## Sets the World and Tension buses from the settings (World follows the game's effects slider).
static func apply_settings() -> void:
	ensure_buses()
	var effects := float(GameSettings.get_value("audio", "effects"))
	_bus_level(&"World", float(setting("world")) * effects)
	var on := bool(setting("tension_on"))
	_bus_level(&"Tension", float(setting("tension")) if on else 0.0, TENSION_DB)


static func _bus_level(bus: StringName, level_linear: float, offset_db := 0.0) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, level_linear <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(level_linear, 0.001)) + offset_db)


static func _live() -> FallenAudio:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var lvl := CompoundLevel.current(tree.root)
	return lvl.get_node_or_null(NODE_NAME) as FallenAudio if lvl else null


## The once-moments already heard in this world (kept in the save on the host).
func _moments_store() -> Dictionary:
	if Survival.running and Survival.multiplayer.has_multiplayer_peer() and Survival.multiplayer.is_server():
		var st := Survival.state()
		if not (st.get("audio_moments") is Dictionary):
			st["audio_moments"] = {}
		return st["audio_moments"]
	return {}


# --- The tick -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_tick += delta
	if _tick < TICK_S:
		return
	var dt := _tick
	_tick = 0.0
	var ctx := gather()
	if bool(ctx.get("none", false)):
		_silence()
		return
	step(ctx, dt)


## One step on `ctx` (`gather`'s keys): the mix, the tension, the music; then the players.
## Returns {"mix", "tension" (level), "moments" (fired now), "loop"}.
func step(ctx: Dictionary, dt: float, play := true) -> Dictionary:
	var now := float(ctx.get("now", Soldier._now()))
	mix = soundscape.update(ctx, now)
	var lvl := tension.update(ctx, dt)
	tension_now = lvl
	ctx["tension_level"] = lvl
	var fired := music.update(ctx, now)
	for m: String in fired:
		_cue("moment:" + m)
	if music.loop != _loop_cue:
		_loop_cue = music.loop
		if _loop_cue != "":
			_cue("loop:" + _loop_cue)
	if play:
		_apply(ctx, dt, fired)
	return {"mix": mix, "tension": lvl, "moments": fired, "loop": music.loop}


func _cue(c: String) -> void:
	cues.append(c)
	if cues.size() > CUES_KEPT:
		cues.pop_front()


## What's around this peer's survivor now (see Soundscape, Tension, MusicMoments for the keys).
func gather() -> Dictionary:
	var ctx := {"now": Soldier._now()}
	var me := MapNodes.local_player(self)
	if me == null or not me.is_inside_tree():
		ctx["none"] = true
		return ctx
	var pos := me.global_position
	var me2 := Vector2(pos.x, pos.z)
	ctx["me"] = me2
	ctx["dead"] = me.vitals.is_dead()
	var dn := DayNight.current()
	var weather := dn.weather if dn else DayNight.DEFAULT_WEATHER
	ctx["weather"] = weather
	ctx["hour"] = dn.hour if dn else Survival.hour()
	ctx["wind_mps"] = float((DayNight.WEATHER.get(weather, {}) as Dictionary).get("wind_mps", 3.0))
	ctx["indoors"] = Throwables.indoors(me.get_world_3d(), pos + Vector3.UP * 1.2)
	var zone := String(Survival.state().get("zone", ""))
	ctx["region"] = WorldSim.region_of(zone) if zone != "" else "plains"
	ctx["day"] = Survival.day()
	ctx["season"] = Survival.season()
	# The crowd's heads and the live dead.
	var heads: Array[Vector2] = []
	var horde_m := INF
	var crowd := ZoneDead.of(level)
	if crowd:
		for d: Dictionary in crowd.dead:
			if not bool(d.get("alive", true)):
				continue
			var p: Vector2 = d.pos
			var dist := p.distance_to(me2)
			if dist <= Soundscape.GROAN_M:
				heads.append(p)
			if bool(d.get("horde", false)):
				horde_m = minf(horde_m, dist)
		ctx["horde"] = crowd.horde_count() > 0
	ctx["crowd"] = heads
	ctx["horde_m"] = horde_m
	var now := float(ctx.now)
	var zs: Array[Dictionary] = []
	for z: Soldier in Survival.zombies(level):
		var d := z.global_position.distance_to(pos)
		if d > Tension.NEAR_M * 2.0:
			continue
		var brain := ZombieAI.of(z)
		var screamed := now - float(z.get_meta(&"zombie_scream", -1000.0))
		zs.append({"d": d, "mode": int(brain.mode) if brain else -1, "awareness": brain.awareness if brain else 0.0, "screamed_s": screamed})
	ctx["zombies"] = zs
	# Living strangers near (not players, not the dead).
	var living: Array[float] = []
	for n: Node in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s == me or not s.is_ai() or s.faction == ZombieAI.INFECTED or not s.vitals.is_up():
			continue
		if CompanionAI.of(s) != null:
			continue
		var d := s.global_position.distance_to(pos)
		if d <= Soundscape.BIRD_QUIET_M:
			living.append(d)
	ctx["living"] = living
	# Your body.
	var body: Dictionary = Survival.my_body if not Survival.my_body.is_empty() else Survival.needs_of(me)
	ctx["stamina"] = me.movement.stamina if me.movement else 1.0
	ctx["sleep"] = float(body.get("sleep", 100.0))
	ctx["warmth"] = float(body.get("warmth", Needs.NORMAL_C))
	ctx["delirium"] = BiteFever.stage_name(body) if not body.is_empty() else ""
	# The settlement (host data: a client hears its music when it hosts).
	var sg := Sieges.siege()
	ctx["raid"] = not sg.is_empty() and not bool(sg.get("over", false))
	if Settlement.exists() and String(Survival.state().get("zone", "")) == Settlement.zone():
		var inside := Settlement.pos().distance_to(pos) <= Settlement.radius()
		ctx["at_settlement"] = inside
		ctx["powered"] = inside and Infrastructure.powered_here()
		var st := Settlement.find(level)
		ctx["morale"] = st.morale() if st else 50.0
		var radio := Settlement.count(String(FallenRadio.ITEM)) > 0 or FallenRadio.is_on()
		ctx["music_source"] = MusicMoments.source_at_settlement(Settlement.settlers(), radio)
	var goal := WorldSim.goal_state() if Survival.running else {}
	ctx["evac"] = bool(goal.get("won", false)) or (bool(goal.get("evac", false)) and zone != "" and zone == String(goal.get("evac_zone", "")))
	return ctx


# --- Playing --------------------------------------------------------------------------------

func _player(layer: String, bus: StringName, stream_name: String) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = _players.get(layer)
	if p == null:
		p = AudioStreamPlayer.new()
		p.name = "Layer_" + layer
		p.bus = bus
		add_child(p)
		_players[layer] = p
	if stream_name != "" and p.get_meta(&"stream_name", "") != stream_name:
		p.set_meta(&"stream_name", stream_name)
		p.stream = FallenSynth.get_stream(stream_name)
		p.play()
	return p


func _set_volume(p: AudioStreamPlayer, v: float) -> void:
	if v <= 0.005:
		if p.playing:
			p.stop()
		return
	p.volume_db = linear_to_db(v)
	if not p.playing:
		p.play()


func _apply(ctx: Dictionary, dt: float, fired: Array[String]) -> void:
	for layer: String in WORLD_LAYERS:
		var v := float(mix.get(layer, 0.0))
		if v <= 0.005 and not _players.has(layer):
			continue  # never made: nothing to stop (and no buffer built for it)
		_set_volume(_player(layer, &"World", layer), v)
	_groans(ctx, dt)
	if tension.drone > 0.005 or _players.has("drone"):
		_set_volume(_player("drone", &"Tension", "drone"), tension.drone)
	if tension.heart > 0.005 or _players.has("heart"):
		var bpm := tension.bpm()
		_set_volume(_player("heart", &"Tension", "heartbeat_%d" % bpm), tension.heart)
	for m: String in fired:
		var p := _player("stinger", &"Music", "")
		p.stream = MusicMoments.stream_for("stinger_" + m)
		p.volume_db = 0.0
		p.play()
	if music.loop != "":
		var lp := _player("loop", &"Music", "")
		if lp.get_meta(&"stream_name", "") != music.loop:
			lp.set_meta(&"stream_name", music.loop)
			lp.stream = MusicMoments.stream_for(music.loop)
			lp.volume_db = -6.0
			lp.play()
	elif _players.has("loop"):
		(_players["loop"] as AudioStreamPlayer).stop()
		(_players["loop"] as AudioStreamPlayer).set_meta(&"stream_name", "")


## Now and then a groan from the crowd's bearing, more often the more of them.
func _groans(ctx: Dictionary, dt: float) -> void:
	var v := float(mix.get("groans", 0.0))
	if v <= 0.01:
		return
	_groan_in -= dt
	if _groan_in > 0.0:
		return
	_groan_in = lerpf(GROAN_GAP_S.y, GROAN_GAP_S.x, v) * randf_range(0.7, 1.3)
	_cue("groan")
	var dir: Vector2 = mix.get("groan_dir", Vector2.ZERO)
	var me := MapNodes.local_player(self)
	if me == null or dir == Vector2.ZERO:
		return
	var off := dir * minf(float(mix.get("groan_m", GROAN_PLACE_M)), GROAN_PLACE_M)
	var g := AudioStreamPlayer3D.new()
	g.stream = FallenSynth.get_stream("groan")
	g.bus = &"World"
	g.volume_db = linear_to_db(v)
	g.pitch_scale = randf_range(0.85, 1.15)
	g.max_distance = 120.0
	add_child(g)
	g.global_position = me.global_position + Vector3(off.x, 1.4, off.y)
	g.finished.connect(g.queue_free)
	g.play()


func _silence() -> void:
	for p: AudioStreamPlayer in _players.values():
		if p.playing:
			p.stop()


# --- The radio ------------------------------------------------------------------------------

## A HUD flash (Hud.flash): a radio broadcast ("Radio: ...") plays a burst of static and its
## voiced line when it has one, on the Radio bus (into Voice). The text stays on screen as it was.
static func on_flash(from: Node, text: String) -> void:
	if not text.begins_with("Radio: "):
		return
	var fa := of(from)
	if fa:
		fa.radio(text.trim_prefix("Radio: "))


## Plays broadcast `text`: the static, then the voice ("" none). Returns the clip path played.
func radio(text: String) -> String:
	_cue("radio")
	var st := _player("radio_static", &"Radio", "")
	st.stream = FallenSynth.get_stream("static")
	st.volume_db = -8.0
	st.play()
	var line := VoiceLines.resolve(text)
	var path := ""
	if not line.is_empty() and bool(line.voiceable) and bool(setting("voice_files")):
		path = VoiceLines.radio_path(String(line.voice))
	VoiceLines.played.append({"text": text, "voice": String(line.get("voice", "")), "path": path})
	if path != "":
		var v := _player("radio_voice", &"Radio", "")
		v.stream = load(path) as AudioStream
		v.volume_db = Callouts.RADIO_DB
		v.play()
	return path
