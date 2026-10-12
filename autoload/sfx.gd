extends Node
## Sound (Captain, 2026-10-12: our side owns all sound; generated in code, stylised to fit our
## world rather than photo-real; real recordings may override any sound later). Every sound
## has an id (data/sounds.json). Its stream is res://audio/sfx/<id>.ogg (or <id>_1.ogg,
## <id>_2.ogg ... for variants) when such a file exists, else a placeholder generated here
## once and cached (_synth): layered noise and tones, a few variants per sound so repeats
## don't sound identical.
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
## data/sounds.json (a "synth" recipe or real files).

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
## A round passing within this distance of the listener cracks (when fired from further
## than CRACK_MIN_SHOOTER_M, so you don't hear your own rounds crack).
const CRACK_PASS_M := 6.0
const CRACK_MIN_SHOOTER_M := 25.0
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

## A sound under a roof this close above it plays through the room bus (reverb).
const ROOF_M := 8.0
## Engines: heard within their sound's range_m; pitch rises with speed (m/s) up to this.
const ENGINE_TOP_SPEED := 20.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_defs()
	_ensure_bus(&"SFX")
	_ensure_bus(&"Voice")
	_ensure_bus(&"SFX_Room")
	var room := AudioServer.get_bus_index(&"SFX_Room")
	if AudioServer.get_bus_effect_count(room) == 0:
		var reverb := AudioEffectReverb.new()  # indoors: a small hard room
		reverb.room_size = 0.35
		reverb.damping = 0.4
		reverb.wet = 0.3
		reverb.dry = 0.85
		AudioServer.add_bus_effect(room, reverb)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool.append(p)


func _load_defs() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		defs = parsed.get("sounds", {})


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


## Host only: a shot from `origin` whose round ended at `end`, of kind "rifle", "pistol" or
## "suppressed", on every peer: the shot (near or far) and, for a listener the round passed
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
	play_at(StringName("shot_" + kind), origin)
	var ear: Variant = listener()
	if ear == null or kind == "suppressed_subsonic":
		return
	var e: Vector3 = ear
	if e.distance_to(origin) < CRACK_MIN_SHOOTER_M:
		return
	var close := Geometry3D.get_closest_point_to_segment(e, origin, end)
	if close.distance_to(e) <= CRACK_PASS_M and close.distance_to(origin) > 2.0:
		play_at(&"crack", close)


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
	var ear: Variant = listener()
	if ear == null:
		return
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or not s.is_inside_tree():
			continue
		var key := s.get_instance_id()
		var pos := s.global_position
		var e: Dictionary = _steps.get(key, {"pos": pos, "walked": 0.0})
		var moved := Vector2(pos.x - e.pos.x, pos.z - e.pos.z).length()
		e.pos = pos
		if moved > 2.0 or not s.vitals.is_up() or is_instance_valid(s.carried_by) or is_instance_valid(s.vehicle) \
				or pos.distance_to(ear) > STEP_RANGE_M:
			e.walked = 0.0  # a teleport, down, carried, riding or too far: no step
		else:
			e.walked = float(e.walked) + moved
			var stride := _stride(s)
			if e.walked >= stride:
				e.walked = float(e.walked) - stride
				play_at(&"step_hard" if hard_ground(s) else &"step", pos, -8.0 if s.is_crouching() else 0.0)
		_steps[key] = e
	_update_engines(ear, delta)
	if _steps.size() > 256:
		_steps.clear()


## Whether `pos` is under a roof (world geometry within ROOF_M above): indoors, with reverb.
func under_roof(pos: Vector3) -> bool:
	var space := _space()
	if space == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.6, pos + Vector3.UP * ROOF_M, SoldierMovement.WORLD_MASK)
	return not space.intersect_ray(q).is_empty()


## Whether `s` stands on something built (a voxel structure, a module, a vehicle): a hard step.
func hard_ground(s: Soldier) -> bool:
	var space := _space()
	if space == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(s.global_position + Vector3.UP * 0.3, s.global_position + Vector3.DOWN * 0.5, SoldierMovement.WORLD_MASK)
	q.exclude = [s.get_rid()]
	var hit := space.intersect_ray(q)
	var node: Node = hit.get("collider") as Node
	while node:
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
		var running := not v.wrecked and v.driver() != null and v.global_position.distance_to(ear) <= float(def.get("range_m", 200.0))
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
			e = {"player": p, "pos": v.global_position, "speed": 0.0, "id": id}
			_engines[key] = e
		var pos := v.global_position
		e.speed = lerpf(float(e.speed), pos.distance_to(e.pos) / maxf(delta, 0.001), 0.1)
		e.pos = pos
		var effort := clampf(float(e.speed) / ENGINE_TOP_SPEED, 0.0, 1.0)
		var player: AudioStreamPlayer3D = e.player
		player.global_position = pos
		player.pitch_scale = 0.8 + effort * 0.8
		player.volume_db = float(def.get("volume_db", 0.0)) + effort * 5.0
		alive[key] = true
	for key in _engines.keys():
		if not alive.has(key):
			(_engines[key].player as Node).queue_free()
			_engines.erase(key)


## The engine sound playing for `v` (tests), or {}.
func engine_of(v: Vehicle) -> Dictionary:
	return _engines.get(v.get_instance_id(), {})


static func _stride(s: Soldier) -> float:
	return STRIDE_M * (0.7 if s.is_crouching() else 1.0)


# --- Streams: files first, else generated ---------------------------------------------------

## The streams for `id`: res://audio/sfx/<id>.ogg or <id>_1.ogg ... if present, else the
## generated placeholders from its "synth" recipe.
func streams(id: StringName) -> Array:
	if _streams.has(id):
		return _streams[id]
	var out: Array = []
	var single := AUDIO_DIR + String(id) + ".ogg"
	if ResourceLoader.exists(single):
		out.append(load(single))
	var i := 1
	while ResourceLoader.exists("%s%s_%d.ogg" % [AUDIO_DIR, id, i]):
		out.append(load("%s%s_%d.ogg" % [AUDIO_DIR, id, i]))
		i += 1
	if out.is_empty():
		var recipe: Dictionary = defs.get(String(id), {}).get("synth", {})
		if not recipe.is_empty():
			for v in SYNTH_VARIANTS:
				out.append(synth(recipe, hash(String(id)) + v * 7919))
	_streams[id] = out
	return out


## A placeholder sound from a recipe (SfxSynth.make).
static func synth(recipe: Dictionary, seed_value: int) -> AudioStreamWAV:
	return SfxSynth.make(recipe, seed_value)
