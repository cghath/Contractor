extends Node
## Sound (Captain, 2026-10-12: our side owns all sound; generated in code, stylised to fit our
## world rather than photo-real; real recordings may override any sound later). Every sound
## has an id (data/sounds.json). Its stream is res://audio/sfx/<id>.ogg (or <id>_1.ogg,
## <id>_2.ogg ... for variants) when such a file exists, else a placeholder generated here
## (on worker threads at boot, _start_prebuild): layered noise and tones, a few variants per
## sound so repeats don't sound identical.
##
## Each peer hears from its own listener (the current camera): a shot plays its near or far
## variant by distance and arrives late at the speed of sound; a round passing close to the
## listener adds a crack; footsteps are worked out on every peer from how soldiers move (no
## network). The host sends shots (server_shot), reloads and other one-offs (server_play) to
## every peer; impacts, explosions and flashbangs ride the level's existing effect RPCs
## (CompoundLevel.show_impact / show_explosion / show_flash call play_at). Audible ranges
## follow what the AI hears (SquadAI.HEAR_SHOT_M, HEAR_SUPPRESSED_M).
##
## Vehicles (cghath's side) call play_at / play_loop with their own ids: add them to
## data/sounds.json (a "synth" recipe or real files). Combined arms A7 adds the crew's intercom
## and the own vehicle heard from inside (voice_route, play_intercom, the Interior bus).

const PATH := "res://data/sounds.json"
const AUDIO_DIR := "res://audio/sfx/"
const MIX_RATE := 22050
const SPEED_OF_SOUND := 343.0
## Players kept for one-off sounds; the oldest is reused when all are busy.
const POOL_SIZE := 40
## Footsteps: heard within this range of the listener; one step per this many metres moved
## (scaled by stance in _stride).
const STEP_RANGE_M := 40.0
const STRIDE_M := 0.8
## Proposed (Captain's playtest P0164: a squad's steps sounded like a crowd, or physics
## glitching): no steps under this speed (m/s; a soldier standing still jitters a little every
## frame, and that used to add up to steps; measured over STEP_WINDOW_S, or STEP_FRAME_M in one
## frame); of everyone but you, only the STEP_VOICES nearest walking are heard, this much
## quieter than your own.
const STEP_MIN_SPEED := 0.5
const STEP_WINDOW_S := 0.25
const STEP_FRAME_M := 0.03
## Proposed: another player's body rising or falling faster than this (m/s) is in the air.
const STEP_AIR_SPEED := 2.0
const STEP_VOICES := 3
const STEP_OTHERS_DB := -3.0
## A round passing within this distance of the listener cracks (when fired from further
## than CRACK_MIN_SHOOTER_M, so you don't hear your own rounds crack).
const CRACK_PASS_M := 10.0
const CRACK_MIN_SHOOTER_M := 8.0
## Placeholder variants per sound.
const SYNTH_VARIANTS := 3
## The last sounds played on this peer (id, pos, variant), for tests and the session log.
const HISTORY_SIZE := 64

var defs := {}
var history: Array[Dictionary] = []
## Tests: hear from here instead of the camera (a Vector3), or null.
var listener_override: Variant = null
## Off in a headless run's dummy audio? Sounds still go through the pool (so tests see them).
var enabled := true

var _streams := {}  # id -> Array[AudioStream]
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _steps := {}  # soldier instance id -> {"pos": Vector3, "walked": float}
var _engines := {}  # vehicle instance id -> {"player", "pos", "speed", "id"}
var _heard := 0  # sounds played so far (history "n")
## The boot prebuild (_start_prebuild): the sounds' ids and recipes, the group task (-1 once
## taken in), and what the workers have built so far (under the mutex).
var _prebuild_ids: Array[String] = []
var _prebuild_recipes: Array[Dictionary] = []
var _prebuild_task := -1
var _prebuilt := {}
var _prebuild_mutex := Mutex.new()
var _prebuild_started := 0
## How long the boot prebuild took, start to taken in (ms); 0 until then.
var prebuild_ms := 0.0

## A sound under a roof this close above it plays through the room bus (reverb).
const ROOF_M := 8.0
## Buttoned up inside armour (combined arms A5, cg_brief queue item 2.4; docs/combined_arms.md
## 2.6, 2.10.5): outside sounds -12 dB and low-passed, on the effects buses (SFX, SFX_Room), while
## set_muffled is on (VehicleHud: the local player in a closed seat). Proposed.
const MUFFLE_DB := -12.0
const MUFFLE_CUTOFF_HZ := 900.0
const MUFFLE_BUSES: Array[StringName] = [&"SFX", &"SFX_Room"]
## Whether outside sounds are muffled now (this machine's listener inside a closed vehicle).
var muffled := false
## Engines: heard within their sound's range_m; pitch rises with speed (m/s) up to this.
const ENGINE_TOP_SPEED := 20.0
## Combined arms A7 (cg_brief queue item 2.5; docs/combined_arms.md 2.10.5, 2.5.2; F-260), Proposed:
## - the crew's intercom: a crewman's voice to the others in crew seats of the same vehicle (CVC
##   helmets: buttoned up or turned out) comes in your ear on the Intercom bus, band-limited
##   (INTERCOM_BAND_HZ) and a little crunchy, never muffled (voice_route, play_intercom);
## - your own vehicle from inside: buttoned up, its engine and tracks play on the Interior bus (a
##   louder, duller drone: INTERIOR_DB, INTERIOR_CUTOFF_HZ) instead of muffled with the outside;
##   turned out, as anyone outside hears them;
## - tracks (data/vehicle_fx.json "sounds"): a clatter loop under a tracked vehicle's engine, up
##   from silent at a halt to its full level at TRACKS_FULL_MPS.
const INTERCOM_BAND_HZ := Vector2(300.0, 3400.0)
const INTERCOM_DB := 0.0
const INTERIOR_DB := 4.0
const INTERIOR_CUTOFF_HZ := 500.0
const TRACKS_FULL_MPS := 8.0
const TRACKS_QUIET_DB := -30.0
var _local: Soldier  # this peer's own soldier (seen in _process)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_defs()
	_ensure_bus(&"SFX")
	_ensure_bus(&"Voice")
	_ensure_bus(&"SFX_Room")
	_ensure_bus(&"Music")  # the infil music (InfilMusic; Captain, 2026-10-14: temporary)
	_ensure_bus(&"Radio")  # far squadmates over the net (Callouts.play): into Voice, filtered like a handset
	var radio := AudioServer.get_bus_index(&"Radio")
	AudioServer.set_bus_send(radio, &"Voice")
	if AudioServer.get_bus_effect_count(radio) == 0:
		var hp := AudioEffectHighPassFilter.new()
		hp.cutoff_hz = 350.0
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 3200.0
		var crunch := AudioEffectDistortion.new()
		crunch.mode = AudioEffectDistortion.MODE_OVERDRIVE
		crunch.drive = 0.35
		crunch.post_gain = -4.0
		for fx: AudioEffect in [hp, lp, crunch]:
			AudioServer.add_bus_effect(radio, fx)
	GameSettings.apply_audio()  # the player's volumes on the buses
	var room := AudioServer.get_bus_index(&"SFX_Room")
	if AudioServer.get_bus_effect_count(room) == 0:
		var reverb := AudioEffectReverb.new()  # indoors: a small hard room
		reverb.room_size = 0.35
		reverb.damping = 0.4
		reverb.wet = 0.3
		reverb.dry = 0.85
		AudioServer.add_bus_effect(room, reverb)
	_add_muffle()
	_add_crew_buses()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool.append(p)
	_start_prebuild()


func _load_defs() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		defs = parsed.get("sounds", {})


## The muffle's low-pass and gain on each effects bus, off until set_muffled.
func _add_muffle() -> void:
	for bus: StringName in MUFFLE_BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i < 0 or _muffle_at(i) >= 0:
			continue
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = MUFFLE_CUTOFF_HZ
		lp.resource_name = "muffle_lp"
		var gain := AudioEffectAmplify.new()
		gain.volume_db = MUFFLE_DB
		gain.resource_name = "muffle_gain"
		AudioServer.add_bus_effect(i, lp)
		AudioServer.add_bus_effect(i, gain)
		AudioServer.set_bus_effect_enabled(i, AudioServer.get_bus_effect_count(i) - 2, false)
		AudioServer.set_bus_effect_enabled(i, AudioServer.get_bus_effect_count(i) - 1, false)


## A7: the Intercom bus (into Voice: band-limited, a little crunch) and the Interior bus (your
## own vehicle from inside: duller, never muffled; into Master, at the effects' volume).
func _add_crew_buses() -> void:
	_ensure_bus(&"Intercom")
	var ic := AudioServer.get_bus_index(&"Intercom")
	AudioServer.set_bus_send(ic, &"Voice")
	if AudioServer.get_bus_effect_count(ic) == 0:
		var hp := AudioEffectHighPassFilter.new()
		hp.cutoff_hz = INTERCOM_BAND_HZ.x
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = INTERCOM_BAND_HZ.y
		var crunch := AudioEffectDistortion.new()
		crunch.mode = AudioEffectDistortion.MODE_CLIP
		crunch.drive = 0.2
		crunch.post_gain = -2.0
		for fx: AudioEffect in [hp, lp, crunch]:
			AudioServer.add_bus_effect(ic, fx)
	_ensure_bus(&"Interior")
	var inside := AudioServer.get_bus_index(&"Interior")
	if AudioServer.get_bus_effect_count(inside) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = INTERIOR_CUTOFF_HZ
		AudioServer.add_bus_effect(inside, lp)


## The Intercom bus's band ([high-pass, low-pass] Hz; tests: the bus effects themselves).
func intercom_band() -> Vector2:
	var i := AudioServer.get_bus_index(&"Intercom")
	var out := Vector2.ZERO
	for e in (AudioServer.get_bus_effect_count(i) if i >= 0 else 0):
		var fx := AudioServer.get_bus_effect(i, e)
		if fx is AudioEffectHighPassFilter:
			out.x = (fx as AudioEffectHighPassFilter).cutoff_hz
		elif fx is AudioEffectLowPassFilter:
			out.y = (fx as AudioEffectLowPassFilter).cutoff_hz
	return out


## This peer's own soldier's vehicle (null: on foot, or none yet).
func local_vehicle() -> Vehicle:
	return Vehicle.ride_of(_local) if is_instance_valid(_local) else null


## Whether this peer's soldier sits closed in `v` (buttoned up: its own engine on the Interior bus).
func inside_closed(v: Vehicle) -> bool:
	if v == null or not is_instance_valid(_local) or Vehicle.ride_of(_local) != v:
		return false
	var seat := v.seat_of(_local)
	return seat >= 0 and not v.seat_open(seat) and v.kind != Vehicle.HELICOPTER


## How `speaker`'s voice reaches this peer's soldier (A7, 2.5.2): &"intercom" (both in crew seats
## of one vehicle with an intercom: an armoured one), &"open" otherwise (Callouts' own rule: near
## by air, far by radio). `listener` stands in for this peer's soldier (tests).
func voice_route(speaker: Node, listener: Soldier = null) -> StringName:
	var me := listener if listener else _local
	var s := speaker as Soldier
	if s == null or me == null or not is_instance_valid(me) or s == me:
		return &"open"
	var v := Vehicle.ride_of(s)
	if v == null or v != Vehicle.ride_of(me) or not VehicleHud.applies(v):
		return &"open"
	var a := v.seat_of(s)
	var b := v.seat_of(me)
	if a < 0 or b < 0 or v.is_rider(a) or v.is_rider(b):
		return &"open"
	return &"intercom"


## Plays `stream` from `speaker` on the intercom (in your ear, band-limited). The player, or null.
func play_intercom(stream: AudioStream, speaker: Node) -> AudioStreamPlayer:
	if stream == null or speaker == null or not is_instance_valid(speaker):
		return null
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = &"Intercom"
	p.volume_db = INTERCOM_DB
	speaker.add_child(p)
	p.finished.connect(p.queue_free)
	if enabled:
		p.play()
	_remember(&"intercom", (speaker as Node3D).global_position if speaker is Node3D else Vector3.ZERO)
	return p


## The index of the muffle's low-pass on bus `i` (-1 none); its gain is the next one.
static func _muffle_at(i: int) -> int:
	for e in AudioServer.get_bus_effect_count(i):
		if AudioServer.get_bus_effect(i, e).resource_name == "muffle_lp":
			return e
	return -1


## Outside sounds muffled (buttoned up) or not (out in the open, turned out).
func set_muffled(on: bool) -> void:
	if on == muffled:
		return
	muffled = on
	for bus: StringName in MUFFLE_BUSES:
		var i := AudioServer.get_bus_index(bus)
		var e := _muffle_at(i) if i >= 0 else -1
		if e >= 0:
			AudioServer.set_bus_effect_enabled(i, e, on)
			AudioServer.set_bus_effect_enabled(i, e + 1, on)


## Whether the effects buses are muffled now (tests: the bus effects themselves).
func muffle_active() -> bool:
	var i := AudioServer.get_bus_index(&"SFX")
	var e := _muffle_at(i) if i >= 0 else -1
	return e >= 0 and AudioServer.is_bus_effect_enabled(i, e) and AudioServer.is_bus_effect_enabled(i, e + 1)


static func _ensure_bus(bus: StringName) -> void:
	if AudioServer.get_bus_index(bus) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus)
	AudioServer.set_bus_send(i, &"Master")


# --- Playing ----------------------------------------------------------------------------------

## Where this peer hears from: the test override, else the current camera, else null.
func listener() -> Variant:
	if listener_override != null:
		return listener_override
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position if cam else null


## Plays sound `id` at `pos` on this peer only: its far variant (`<id>_far` if defined) past
## the sound's "near_m", after the time sound takes to travel to the listener. Returns the
## variant id played, or &"" (unknown id, or out of range).
func play_at(id: StringName, pos: Vector3, volume_db := 0.0) -> StringName:
	if not defs.has(String(id)) or not pos.is_finite():
		return &""
	var def: Dictionary = defs[String(id)]
	var ear: Variant = listener()
	var d: float = (ear as Vector3).distance_to(pos) if ear != null else 0.0
	if d > float(def.get("range_m", 100.0)):
		return &""
	var play_id := id
	if d > float(def.get("near_m", INF)) and defs.has(String(id) + "_far"):
		play_id = StringName(String(id) + "_far")
		def = defs[String(play_id)]
	var delay := d / SPEED_OF_SOUND if bool(def.get("travels", false)) else 0.0
	_remember(play_id, pos)
	if delay > 0.02:
		get_tree().create_timer(delay).timeout.connect(_start.bind(play_id, pos, volume_db))
	else:
		_start(play_id, pos, volume_db)
	return play_id


## Host only: plays `id` at `pos` on every peer (each from its own listener).
func server_play(id: StringName, pos: Vector3) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_play_everywhere.rpc(id, pos)
	else:
		play_at(id, pos)


@rpc("authority", "call_local", "unreliable_ordered")
func _play_everywhere(id: StringName, pos: Vector3) -> void:
	play_at(id, pos)


## Host only: a shot from `origin` whose round ended at `end`, of kind "rifle", "pistol",
## "suppressed" or "hmg" (a vehicle's heavy machine gun: Vehicle.server_fire_gun), on every peer: the shot (near or far) and, for a listener the round passed
## close to, a crack.
func server_shot(origin: Vector3, end: Vector3, kind: String) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_shot_everywhere.rpc(origin, end, kind)
	else:
		hear_shot(origin, end, kind)


@rpc("authority", "call_local", "unreliable_ordered")
func _shot_everywhere(origin: Vector3, end: Vector3, kind: String) -> void:
	hear_shot(origin, end, kind)


## This peer hears a shot (see server_shot).
func hear_shot(origin: Vector3, end: Vector3, kind: String) -> void:
	var id := "shot_" + kind
	if not defs.has(id):
		id = "shot_pistol" if kind == "pistol" else ("shot_hmg" if kind in ["m2", "dshk"] else "shot_rifle")  # a family with no sound of its own yet
	play_at(StringName(id), origin)
	var ear: Variant = listener()
	if ear == null or kind == "suppressed_subsonic":
		return
	var e: Vector3 = ear
	if e.distance_to(origin) < CRACK_MIN_SHOOTER_M:
		return
	var close := Geometry3D.get_closest_point_to_segment(e, origin, end)
	var miss := close.distance_to(e)
	if miss <= CRACK_PASS_M and close.distance_to(origin) > 2.0:
		play_at(&"crack", close, lerpf(3.0, -6.0, miss / CRACK_PASS_M))  # Captain, 2026-10-16: "i dont hear snaps when they snap past"


func _start(id: StringName, pos: Vector3, volume_db: float) -> void:
	if not enabled or not is_inside_tree():
		return
	var def: Dictionary = defs.get(String(id), {})
	var options := streams(id)
	if options.is_empty():
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stop()
	p.stream = options[randi() % options.size()]
	p.global_position = pos
	p.bus = &"SFX_Room" if under_roof(pos) else &"SFX"
	p.unit_size = float(def.get("unit_size", 10.0))
	p.max_distance = float(def.get("range_m", 100.0))
	p.volume_db = float(def.get("volume_db", 0.0)) + volume_db
	var spread := float(def.get("pitch_spread", 0.06))
	p.pitch_scale = 1.0 + randf_range(-spread, spread)
	p.play()


func _remember(id: StringName, pos: Vector3) -> void:
	_heard += 1
	history.append({"id": id, "pos": pos, "time": Time.get_ticks_msec() / 1000.0, "n": _heard})
	if history.size() > HISTORY_SIZE:
		history.pop_front()


## How many sounds this peer has played so far (tests: heard_after).
func heard_count() -> int:
	return _heard


## The ids heard after the `count`th sound (heard_count), for tests: exact, unlike times.
func heard_after(count: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for h in history:
		if int(h.n) > count:
			out.append(h.id)
	return out


## The ids heard since `since` (seconds, Time ticks), for tests.
func heard_since(since: float) -> Array[StringName]:
	var out: Array[StringName] = []
	for h in history:
		if float(h.time) >= since:
			out.append(h.id)
	return out


# --- Footsteps (every peer, no network) -------------------------------------------------------

func _process(delta: float) -> void:
	if _prebuild_task >= 0 and WorkerThreadPool.is_group_task_completed(_prebuild_task):
		_finish_prebuild()
	var ear: Variant = listener()
	if ear == null:
		return
	var walking: Array = []  # [distance, soldier, stepped now]: everyone else walking
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or not s.is_inside_tree():
			continue
		var key := s.get_instance_id()
		var pos := s.global_position
		if s.is_local():
			_local = s  # (A7: the intercom and your own vehicle's sound from inside)
		# (A random start in the stride, so a squad setting off together doesn't step in unison.)
		var e: Variant = _steps.get(key)  # (perf pass: no default dictionary made per soldier per frame)
		if e == null:
			e = {"pos": pos, "walked": randf() * _stride(s), "anchor": pos, "since": 0.0, "walking": false}
		var moved := Vector2(pos.x - e.pos.x, pos.z - e.pos.z).length()
		var rise := absf(pos.y - float((e.pos as Vector3).y))
		e.pos = pos
		var airborne := _airborne(s, rise, delta)
		# Walking or not: the ground covered over STEP_WINDOW_S (whatever the frame rate; standing
		# jitter goes back and forth and covers none), or a big move in one frame.
		e.since = float(e.since) + delta
		if e.since >= STEP_WINDOW_S:
			var a: Vector3 = e.anchor
			e.walking = Vector2(pos.x - a.x, pos.z - a.z).length() / float(e.since) >= STEP_MIN_SPEED
			e.anchor = pos
			e.since = 0.0
		var dist: float = pos.distance_to(ear)
		if moved > 2.0 or not s.vitals.is_up() or is_instance_valid(s.carried_by) or is_instance_valid(s.vehicle) \
				or dist > STEP_RANGE_M:
			e.walked = 0.0  # a teleport, down, carried, riding or too far: no step
		elif airborne:
			pass  # jumping or falling: no steps in the air (Captain's playtest); the stride holds
		elif e.walking or moved >= STEP_FRAME_M:
			e.walked = float(e.walked) + moved
			var stride := _stride(s)
			var stepped := float(e.walked) >= stride
			if stepped:
				e.walked = float(e.walked) - stride
			if s.is_local():
				if stepped:
					_step(s, 0.0)  # your own: always
			else:
				walking.append([dist, s, stepped])
		_steps[key] = e
	# Of everyone else walking, only the STEP_VOICES nearest are heard (a squad walking around
	# you sounds like a few men near you, not a crowd).
	walking.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(walking.size(), STEP_VOICES):
		if walking[i][2]:
			_step(walking[i][1], STEP_OTHERS_DB)
	_update_engines(ear, delta)
	if _steps.size() > 256:
		_steps.clear()


## Whether `s` is off the ground this frame: the physics' own floor contact for a body this
## peer moves (you, and the AI on the host), else rising or falling faster than
## STEP_AIR_SPEED (`rise` metres this frame; another player's body only has its synced position).
func _airborne(s: Soldier, rise: float, delta: float) -> bool:
	if s.is_physics_processing() and (s.is_local() or (s.is_ai() and multiplayer.is_server())):
		return not s.is_on_floor()
	return delta > 0.0 and rise / delta > STEP_AIR_SPEED


## Footsteps by pace (Captain, 2026-10-20: "running, walking, slow walking, crouching sounds"):
## "step_<pace>" on the ground, "step_hard_<pace>" on anything built, each its own sound and
## level. The pace comes from the drawn gait (the same on every peer); a walk under SLOW_STEP_MPS
## is a slow walk.
const SLOW_STEP_MPS := 1.1


## The footstep pace of `s`: &"sprint", &"jog", &"walk", &"slow" or &"crouch".
static func step_pace(s: Soldier) -> StringName:
	var gait: StringName = s.model.gait() if is_instance_valid(s.model) else CharacterModel.JOG
	if s.is_crouching() or gait == CharacterModel.CROUCH_WALK:
		return &"crouch"
	match gait:
		CharacterModel.SPRINT:
			return &"sprint"
		CharacterModel.WALK:
			return &"slow" if s.model.gait_speed() < SLOW_STEP_MPS else &"walk"
	return &"jog"


## Whether sound `id` is a footstep (any pace, any ground).
static func is_step(id: StringName) -> bool:
	return String(id).begins_with("step_")


func _step(s: Soldier, volume_db: float) -> void:
	var pace := step_pace(s)
	var id := StringName("%s_%s" % ["step_hard" if hard_ground(s) else "step", pace])
	play_at(id, s.global_position, volume_db)
	var kit := kit_rattle_db(s, pace)
	if kit > -INF:
		play_at(&"kit_rattle", s.global_position + Vector3.UP * 1.1, volume_db + kit)


## The kit's rattle with a step (Captain, 2026-10-26: footsteps that sound real, recordings plus
## a generated layer): mags, buckles and plates knocking in a carrier and pack, louder the more
## he carries (KIT_RATTLE_KG: none under the first, full at the second) and the faster he goes
## (KIT_RATTLE_PACE dB by pace; none crouched or slow). -INF: none (no carrier or pack).
const KIT_RATTLE_KG := Vector2(6.0, 30.0)
const KIT_RATTLE_PACE := {&"sprint": 0.0, &"jog": -4.0, &"walk": -10.0}


static func kit_rattle_db(s: Soldier, pace: StringName) -> float:
	if not KIT_RATTLE_PACE.has(pace) or s.inventory == null:
		return -INF
	if s.inventory.slots.get(&"vest", &"") == &"" and s.inventory.slots.get(&"backpack", &"") == &"":
		return -INF
	var carried := clampf(inverse_lerp(KIT_RATTLE_KG.x, KIT_RATTLE_KG.y, s.inventory.total_mass()), 0.0, 1.0)
	if carried <= 0.0:
		return -INF
	return float(KIT_RATTLE_PACE[pace]) + linear_to_db(lerpf(0.35, 1.0, carried))


## Whether `pos` is under a roof (world geometry within ROOF_M above): indoors, with reverb.
func under_roof(pos: Vector3) -> bool:
	var space := _space()
	if space == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.6, pos + Vector3.UP * ROOF_M, SoldierMovement.WORLD_MASK)
	return not space.intersect_ray(q).is_empty()


## Whether `s` stands on something built (a voxel structure, a module, a vehicle, a paved road): a hard step.
func hard_ground(s: Soldier) -> bool:
	var space := _space()
	if space == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(s.global_position + Vector3.UP * 0.3, s.global_position + Vector3.DOWN * 0.5, SoldierMovement.WORLD_MASK)
	q.exclude = [s.get_rid()]
	var hit := space.intersect_ray(q)
	var node: Node = hit.get("collider") as Node
	while node:
		if node.has_meta(&"hard_ground"):  # a road's body (ZoneRoads): asphalt and concrete hard, dirt not
			return bool(node.get_meta(&"hard_ground"))
		if node is VoxelWorld or node is ZoneModule or node is Vehicle:
			return true
		if node is ZoneTerrain:
			return false
		node = node.get_parent()
	return false


func _space() -> PhysicsDirectSpaceState3D:
	var world := get_viewport().find_world_3d() if is_inside_tree() else null
	return world.direct_space_state if world else null


## The engine sound for vehicle `v`: engine_<class> (data/vehicles.json "class"), else by kind.
func engine_id(v: Vehicle) -> StringName:
	var id := "engine_" + String(v.spec.get("class", ""))
	if defs.has(id):
		return StringName(id)
	return &"engine_ifv" if v.kind == Vehicle.TRACKED else &"engine_mrap"


## Engines run while someone drives and the vehicle isn't wrecked, within the sound's range of
## the listener; pitch and volume rise with speed, measured from movement (every peer).
func _update_engines(ear: Vector3, delta: float) -> void:
	var alive := {}
	for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if v == null or not v.is_inside_tree():
			continue
		var key := v.get_instance_id()
		var id := engine_id(v)
		var def: Dictionary = defs.get(String(id), {})
		var running := not v.wrecked and v.engine_running() and v.global_position.distance_to(ear) <= float(def.get("range_m", 200.0))
		if not running:
			continue
		var e: Dictionary = _engines.get(key, {})
		if e.is_empty():
			var options := streams(id)
			if options.is_empty():
				continue
			var p := AudioStreamPlayer3D.new()
			p.stream = options[0]
			p.bus = &"SFX"
			p.unit_size = float(def.get("unit_size", 12.0))
			p.max_distance = float(def.get("range_m", 200.0))
			p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			add_child(p)
			p.global_position = v.global_position
			if enabled:
				p.play()
			_remember(id, v.global_position)
			e = {"player": p, "pos": v.global_position, "speed": 0.0, "id": id, "tracks": _tracks_player(v)}
			_engines[key] = e
		var pos := v.global_position
		e.speed = lerpf(float(e.speed), pos.distance_to(e.pos) / maxf(delta, 0.001), 0.1)
		e.pos = pos
		var effort := clampf(float(e.speed) / ENGINE_TOP_SPEED, 0.0, 1.0)
		var player: AudioStreamPlayer3D = e.player
		player.global_position = pos
		if def.get("engine_flat", false):  # a rotor: near-constant, whatever the speed (a heli is always past ENGINE_TOP_SPEED)
			player.pitch_scale = 0.95 + effort * 0.1
			player.volume_db = float(def.get("volume_db", 0.0))
		else:
			player.pitch_scale = 0.8 + effort * 0.8
			player.volume_db = float(def.get("volume_db", 0.0)) + effort * 5.0
		# A7 (F-260): your own vehicle buttoned up: its engine and tracks from inside (Interior),
		# louder and duller rather than muffled with the outside.
		var inside := inside_closed(v)
		var bus := &"Interior" if inside else &"SFX"
		if player.bus != bus:
			player.bus = bus
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Interior"), AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"SFX")))
		if inside:
			player.volume_db += INTERIOR_DB
		e["inside"] = inside
		var tracks := e.get("tracks") as AudioStreamPlayer3D
		if tracks and is_instance_valid(tracks):
			var tdef: Dictionary = defs.get(String(tracks.get_meta(&"id", "")), {})
			var roll := clampf(float(e.speed) / TRACKS_FULL_MPS, 0.0, 1.0)
			tracks.global_position = pos
			tracks.bus = bus
			tracks.volume_db = lerpf(TRACKS_QUIET_DB, float(tdef.get("volume_db", 0.0)), roll) + (INTERIOR_DB if inside else 0.0)
			tracks.pitch_scale = 0.7 + roll * 0.6
		alive[key] = true
	for key in _engines.keys():
		if not alive.has(key):
			(_engines[key].player as Node).queue_free()
			if is_instance_valid(_engines[key].get("tracks")):
				(_engines[key].tracks as Node).queue_free()
			_engines.erase(key)


## A7: the clatter of `v`'s tracks (its fx block's "tracks" sound, tracked vehicles), playing
## along with its engine; null for none.
func _tracks_player(v: Vehicle) -> AudioStreamPlayer3D:
	if v.kind != Vehicle.TRACKED:
		return null
	var id := String(((v.spec.get("fx", {}) as Dictionary).get("sounds", {}) as Dictionary).get("tracks", "tracks_heavy"))
	var def: Dictionary = defs.get(id, {})
	var options := streams(StringName(id)) if not def.is_empty() else []
	if options.is_empty():
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = options[0]
	p.bus = &"SFX"
	p.unit_size = float(def.get("unit_size", 10.0))
	p.max_distance = float(def.get("range_m", 200.0))
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.volume_db = TRACKS_QUIET_DB
	p.set_meta(&"id", id)
	add_child(p)
	p.global_position = v.global_position
	if enabled:
		p.play()
	return p


## The engine sound playing for `v` (tests), or {}.
func engine_of(v: Vehicle) -> Dictionary:
	return _engines.get(v.get_instance_id(), {})


static func _stride(s: Soldier) -> float:
	return STRIDE_M * (0.7 if s.is_crouching() else 1.0)


# --- Streams: files first, else generated ---------------------------------------------------

## The name of `id`'s recordings in AUDIO_DIR: its "recording" (sounds sharing one set: every
## footstep pace plays the same steps at its own level, Captain 2026-10-26), else its own id.
static func recording_of(id: StringName) -> String:
	var def: Dictionary = Sfx.defs.get(String(id), {}) if Sfx else {}
	return String(def.get("recording", id))


## The streams for `id`: res://audio/sfx/<id>.ogg or <id>_1.ogg ... if present, else the
## generated placeholders from its "synth" recipe (built on worker threads at boot:
## _start_prebuild).
func streams(id: StringName) -> Array:
	if _streams.has(id):
		return _streams[id]
	var started := Time.get_ticks_usec()
	if _prebuild_task >= 0 and _prebuild_ids.has(String(id)):
		_finish_prebuild()  # asked for before the workers are done (right at boot): wait for them
		if _streams.has(id):
			FrameCost.spent(&"sfx", started)
			return _streams[id]
	var out: Array = []
	var files := recording_of(id)
	for ext: String in [".ogg", ".wav"]:  # recordings (audio/sfx/CREDITS.md) over the generated placeholder
		var single := AUDIO_DIR + files + ext
		if ResourceLoader.exists(single):
			out.append(load(single))
		var i := 1
		while ResourceLoader.exists("%s%s_%d%s" % [AUDIO_DIR, files, i, ext]):
			out.append(load("%s%s_%d%s" % [AUDIO_DIR, files, i, ext]))
			i += 1
	if out.is_empty():
		var recipe: Dictionary = defs.get(String(id), {}).get("synth", {})
		if not recipe.is_empty():
			out = _synth_variants(String(id), recipe)
	_streams[id] = out
	FrameCost.spent(&"sfx", started)
	return out


static func _synth_variants(id: String, recipe: Dictionary) -> Array:
	var out: Array = []
	for v in int(recipe.get("variants", SYNTH_VARIANTS)):
		out.append(synth(recipe, hash(id) + v * 7919))
	return out


## Synthesising a sound takes 60-250 ms (an explosion about 200, a rifle shot about 80), which
## used to land on the main thread the first time it played, mid-fight (research 2026-10-13,
## B2.1: over a second in all). So every sound with a recipe and no recording is built at boot,
## on worker threads (one task a sound) while the main menu is up, and taken in once they're all
## done (_process); streams() waits for them only if asked before then.
func _start_prebuild() -> void:
	for id: String in defs:
		var recipe: Dictionary = (defs[id] as Dictionary).get("synth", {})
		var files := recording_of(StringName(id))  # (recorded: no placeholder built)
		if recipe.is_empty() or ResourceLoader.exists(AUDIO_DIR + files + ".ogg") or ResourceLoader.exists("%s%s_1.ogg" % [AUDIO_DIR, files]):
			continue
		_prebuild_ids.append(id)
		_prebuild_recipes.append(recipe.duplicate(true))  # the workers' own copy
	if _prebuild_ids.is_empty():
		return
	_prebuild_started = Time.get_ticks_usec()
	_prebuild_task = WorkerThreadPool.add_group_task(_prebuild_one, _prebuild_ids.size(), -1, false, "Sfx prebuild")


## On a worker thread: sound `i` of _prebuild_ids.
func _prebuild_one(i: int) -> void:
	var built := _synth_variants(_prebuild_ids[i], _prebuild_recipes[i])
	_prebuild_mutex.lock()
	_prebuilt[_prebuild_ids[i]] = built
	_prebuild_mutex.unlock()


## Waits for the prebuild (no wait once it's done) and takes its sounds in.
func _finish_prebuild() -> void:
	if _prebuild_task < 0:
		return
	WorkerThreadPool.wait_for_group_task_completion(_prebuild_task)
	_prebuild_task = -1
	_prebuild_mutex.lock()
	for id: String in _prebuilt:
		if not _streams.has(StringName(id)):
			_streams[StringName(id)] = _prebuilt[id]
	_prebuilt.clear()
	_prebuild_mutex.unlock()
	prebuild_ms = (Time.get_ticks_usec() - _prebuild_started) / 1000.0
	print("[sfx] %d sounds built on worker threads in %.0f ms" % [_prebuild_ids.size(), prebuild_ms])


## Whether the sounds built at boot are all taken in.
func is_prebuilt() -> bool:
	return _prebuild_task < 0


func _exit_tree() -> void:
	if _prebuild_task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_prebuild_task)  # a group task must be waited on
		_prebuild_task = -1


## A placeholder sound from a recipe (SfxSynth.make).
static func synth(recipe: Dictionary, seed_value: int) -> AudioStreamWAV:
	return SfxSynth.make(recipe, seed_value)
