class_name EngineNoise
extends RefCounted
## Engines are heard (Captain, 2026-10-31, F-365: "engines are heard"): a vehicle's or a
## helicopter's running engine, crewed by players or AI, is a noise to the other side, so a
## helicopter infil or a vehicle coming up can be heard.
##
## - Reach by kind and state (REACH_M): idle (a driver in, standing; rotors turning on the ground)
##   or under way (driving faster than MOVING_MS; flying). A helicopter crashing (autorotating or
##   falling, Helicopter.is_airborne) counts as flying while its rotors still turn; a wreck is
##   silent. Through a wall, a building's shell or a hill (no clear line from the engine to his
##   ears) half as far, as a shot (SquadAI.WALL_SHOT_MULT, G-29).
## - Who hears it: the AI of the other side (a hostile hears the squad's engines, the squad's AI a
##   hostile's; nobody hears his own side's, nor a civilian's). Each listener suspects something
##   over there and goes to look (SquadAI.hear_sound, ERROR_PER_100M off): no awareness of anyone,
##   no squad picture, nothing about who rides in it. A hostile also stands his area to and radios
##   it in (Alert.server_engine: an "engine" report, rough as a shot's).
## - Cheap: engines run on and on, so each vehicle sounds every EMIT_S (Vehicle._server_step, on
##   its own clock so they spread out), never every frame. A listener within the muffled reach
##   needs no ray; one beyond it, one ray. One who heard an engine is left alone by that engine
##   for REHEAR_S, one with a wall in the way of it for RECHECK_S (each gap is his and that
##   vehicle's: a helicopter he can't hear through a hill doesn't keep him from hearing a truck
##   idling beside him), and no emission casts more than MAX_RAYS (the rest get their turn next
##   time).
## Host only. All numbers Proposed.

const EMIT_S := 1.0
const REHEAR_S := 4.0
const RECHECK_S := 3.0
const MAX_RAYS := 24
## Faster than this (m/s) a ground vehicle is under way, not idling.
const MOVING_MS := 1.5
## Where it's placed by ear: this many metres off for every 100 m away (an engine's drone carries
## and echoes: rougher than a shot's SquadAI.HEARD_ERROR_PER_100M).
const ERROR_PER_100M := 10.0
## Reach (m) by Vehicle kind: x idle, y under way.
const REACH_M := {
	"wheeled": Vector2(40.0, 150.0),
	"tracked": Vector2(100.0, 300.0),
	"helicopter": Vector2(300.0, 600.0),
}
## The engine sounds from this high on the vehicle (the ray's start).
const SOURCE_UP_M := 1.0

## Vehicle instance id -> {listener instance id -> until when that vehicle doesn't check him
## again}. Emptied when a new level comes up (_level_id).
static var _quiet_until := {}
## The level the gaps are for (its instance id): another level's start drops them all.
static var _level_id := 0


## How far `kind`'s engine carries, idle or `under_way`.
static func reach(kind: String, under_way: bool) -> float:
	var r: Vector2 = REACH_M.get(kind, Vector2.ZERO)
	return r.y if under_way else r.x


## How far `v`'s engine carries now; 0 when it isn't running (nobody driving, no fuel, the engine
## dead, a wreck, a crew-served gun).
static func reach_of(v: Vehicle) -> float:
	if v == null or v.wrecked or not REACH_M.has(v.kind):
		return 0.0
	var heli := v as Helicopter
	if heli:
		return reach(v.kind, heli.is_airborne()) if heli.engine_running() else 0.0
	var driven := v.driver() != null or (is_instance_valid(v.ai) and v.ai.active)
	if not driven or v.zone_health(Vehicle.ZONE_ENGINE) <= 0.0 or v.fuel_litres() <= 0.0:
		return 0.0
	return reach(v.kind, v.linear_velocity.length() > MOVING_MS)


## The side `v` is on for hearing: &"hostile", &"friendly" (players, the squad, allies) or &"" (a
## civilian's, or nobody's: nobody minds it). Its driver's side if it has one, else its own.
static func side_of(v: Vehicle) -> StringName:
	var d := v.driver()
	var f: StringName = d.faction if d else v.faction
	if f == &"hostile":
		return &"hostile"
	return &"" if f == &"civilian" else &"friendly"


## Host: `v`'s engine sounds once (Vehicle._server_step every EMIT_S; tests call it). Returns the
## listeners who heard it.
static func server_emit(v: Vehicle) -> Array[Soldier]:
	var out: Array[Soldier] = []
	if v == null or not v.is_inside_tree() or not v.multiplayer.is_server():
		return out
	var r := reach_of(v)
	var side := side_of(v) if r > 0.0 else &""
	if side == &"":
		return out
	var src := v.global_position + Vector3.UP * SOURCE_UP_M
	var under := src  # where to go and look: on the ground under it
	var heli := v as Helicopter
	if heli and heli.is_airborne():
		under = Vector3(src.x, heli.ground_y(src), src.z)
	var world := v.get_world_3d()
	var alert := Alert.of(v) if side == &"friendly" else null
	var now := Soldier._now()
	var lvl := CompoundLevel.current(v)
	var lvl_id := lvl.get_instance_id() if lvl else 0
	if lvl_id != _level_id:
		_quiet_until.clear()  # a new level: the last one's gaps mean nothing here
		_level_id = lvl_id
	var vid := v.get_instance_id()
	if not _quiet_until.has(vid):
		_quiet_until[vid] = {}
	var quiet: Dictionary = _quiet_until[vid]
	var rays := 0
	for n in v.get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or not s.is_ai() or not s.vitals.is_up() or s.faction == &"civilian" \
				or (s.faction == &"hostile") == (side == &"hostile") or Vehicle.ride_of(s) == v:
			continue
		var d := s.global_position.distance_to(src)
		if d > r:
			continue
		var id := s.get_instance_id()
		if now < float(quiet.get(id, -INF)):
			continue
		var ai := SquadAI.of(s)
		if ai == null:
			continue
		if d > r * SquadAI.WALL_SHOT_MULT:
			if rays >= MAX_RAYS:
				continue  # next time
			rays += 1
			if not Throwables.clear_line(world, src, s.camera.global_position):
				quiet[id] = now + RECHECK_S
				continue  # through a wall it carries half as far, as a shot (G-29)
		quiet[id] = now + REHEAR_S
		var error := ERROR_PER_100M * d / 100.0
		var angle := randf() * TAU
		var heard_at := under + Vector3(cos(angle), 0.0, sin(angle)) * error * sqrt(randf())  # a disc
		ai.hear_sound(heard_at)
		if alert and s.faction == &"hostile":
			Alert.server_engine(s, heard_at)
		out.append(s)
	if quiet.size() > 256:
		for k: int in quiet.keys():
			if float(quiet[k]) < now:
				quiet.erase(k)
	if _quiet_until.size() > 64:
		for k: int in _quiet_until.keys():
			if not is_instance_id_valid(k):
				_quiet_until.erase(k)  # vehicles gone (wrecks cleared, a support flown off)
	return out
