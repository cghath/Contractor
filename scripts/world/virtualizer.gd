class_name Virtualizer
extends Node
## AI virtualization (docs/virtualization.md; Captain, 2026-10-18: "instead of dynamic sim lets
## take a page out of the ALIVE mods book and actually virtualize"). Inspired by ALiVE's profile
## system, built our own way for Contractor's zones.
##
## A group nobody is near is despawned into a PROFILE: a few lines of data (where it is, who is in
## it, each man's kit, wounds, skill and orders, and what the group is doing). The profile keeps
## moving and doing its job on the map at almost no cost, and when a player comes near it is
## spawned back as real soldiers, where the profile had got to, with the same men, kit and wounds.
##
## Host only; one node per zone ("Virtualizer", ZoneLevel). Every TICK_S:
## - Live -> virtual: a tracked group (track(): EnemyResponse's patrols, hunters and HQ pairs, the
##   QRF waves, EnemyCommand's task forces and probes, a faction skirmish team) goes virtual once,
##   for HOLD_S on end, every man of it is further than DESPAWN_M from every player and squadmate
##   (and AI_DESPAWN_M from any live enemy of its side), no player has a line to any of them, and
##   none is in contact, down, busy, carrying, carried, in a vehicle or crewing a static weapon. A
##   group just sent out (track's `fresh`) goes at the first tick it qualifies.
## - Garrisons go virtual at their posts once their module has streamed out (ZoneLevel streams it
##   out past STREAM_OUT_M), on the same calm, unseen rules at GARRISON_DESPAWN_M, and come back with
##   their module (ZoneLevel._spawn_garrison -> server_wake_garrison).
## - Virtual -> live: a profile comes back when a player or squadmate is within SPAWN_M (below
##   DESPAWN_M: nothing flickers) or a live enemy of its side within AI_SPAWN_M, and only once no
##   player has a line to where its men would stand; at FORCE_M it comes back regardless. Men come
##   out a few a frame (SPAWN_BUDGET_MS), in order, each with exactly what he had.
## - Moving: a profile walks its squad's patrol (the route its owner set: EnemyResponse and the rest
##   keep setting squad.patrol as they always have), straight from point to point at its combat
##   mode's pace, faster on roads, slower up slopes; a one-point route is walked to and held.
## - Fighting: two profiles of sides at war within CONTACT_M fight off-screen in ROUND_S rounds: each
##   man hits with a chance by his skill (a garrison behind its walls is harder to hit), a hit kills
##   KILL_SHARE of the time and wounds otherwise; a side cut to BREAK_SHARE breaks off. The dead
##   become real bodies with their kit (CompoundLevel.server_spawn_body), so the squad finds the
##   aftermath. The player's squad is never virtual: its fights are always real.
## - Saves: to_save() (GameState.save_zone) keeps every profile and every tracked group still live
##   (snapshotted where it stands); server_restore() puts them back as profiles on load.
## Clients never hear of a profile: nothing replicates until its men are real soldiers again
## (spawned through the level's AISpawner, so late joiners get them like any AI).
## - Rides (phase 3): a group whose every man is aboard vehicles that are on their way somewhere (a
##   VehicleQrf technical driving a QRF or a patrol in, a mission's convoy rolling down its route: the
##   record's "v_owner" vouches for it, virtual_ride) goes virtual with its vehicles: each one's
##   Vehicle.to_save (damage, fuel, cargo, its id) and who sits in which seat. The profile drives the
##   ride's route at the ride's speed (RIDE_OFFROAD_MULT of it off a road, slower up hills); a QRF ride
##   that gets to where its men get out leaves its technical parked there and goes on on foot. Back in
##   the world the same vehicles come out on its way, the men in their seats, and the owner drives on
##   (VehicleQrf.server_resume, the owner's virtual_ride_back). A group half aboard, half walking
##   stays real.
## DynamicSim stays as the layer for the AI this doesn't take (crews of vehicles that aren't rides,
## bombers, the rival PMC team, scenario waves, gun teams out of a garrison): it sleeps them in place.
## All numbers Proposed.

const NODE_NAME := "Virtualizer"
const TICK_S := 1.0
const DESPAWN_M := 700.0
const SPAWN_M := 550.0
const FORCE_M := 300.0
## A garrison goes virtual once its module is streamed out (ZoneLevel.STREAM_OUT_M).
const GARRISON_DESPAWN_M := 340.0
## Live enemy AI near a group: it stays real within AI_DESPAWN_M, and a profile comes back within
## AI_SPAWN_M (a skirmish team reaching a patrol).
const AI_DESPAWN_M := 300.0
const AI_SPAWN_M := 220.0
## How long a group must be calm and unseen before it goes virtual.
const HOLD_S := 15.0
## Players further than this can't see a group (the zone's haze), and their lines aren't checked.
const SIGHT_M := 1500.0
const EYE_UP_M := 1.6
const BODY_UP_M := 1.2
## Virtual pace (m/s) by combat mode (Squad.CombatMode: SAFE, AWARE, COMBAT, STEALTH).
const PACE_MPS: Array[float] = [1.3, 1.5, 2.2, 1.0]
const ROAD_MULT := 1.3
## Up a slope the pace falls to SLOPE_MIN at the steepest (1 - normal.y of SLOPE_STEEP).
const SLOPE_MIN := 0.45
const SLOPE_STEEP := 0.35
const ARRIVE_M := 3.0
const SPACING_M := 1.6
## Spawn points inside an unstreamed module's footprint go out to its edge plus this.
const GATE_M := 8.0
## Off-screen fights.
const CONTACT_M := 150.0
const ROUND_S := 10.0
const HIT_CHANCE := 0.18
const COVER_MULT := 0.5
const KILL_SHARE := 0.5
const WOUND_BLOOD := 0.2
const DEAD_BLOOD := 0.55
const BREAK_SHARE := 0.34
const BREAK_S := 180.0
## Rides: off a road a vehicle makes this share of its speed, up the steepest slope RIDE_SLOPE_MIN of
## it; a profile's vehicles come back RIDE_SPACING_M apart along its way; a ride is at a point of its
## route within RIDE_ARRIVE_M.
const RIDE_OFFROAD_MULT := 0.6
const RIDE_SLOPE_MIN := 0.6
const RIDE_SPACING_M := 14.0
const RIDE_ARRIVE_M := 15.0
## At most this long spawning a frame (PeopleLayer's budget); at least one man a frame.
const SPAWN_BUDGET_MS := 4.0
## Metas that aren't the man's own (the brain's, the sleep's).
const DROP_META: Array[StringName] = [&"start_gear", &"start_states", &"sim_settle", &"sim_brain_off"]
const SIDE_KINDS: Array[String] = ["patrol", "roam", "hunters", "pair", "qrf", "task_force", "probe", "skirmish", "garrison", "withdraw", "allied"]

## Tests: false and nothing goes virtual or comes back by itself (server_virtualize, server_wake
## and the rest still work when called).
static var enabled := true

## Tracked groups (their owners' own records: "squad", "soldiers", ...), live or virtual. A virtual
## one holds its profile under "virtual"; "v_kind" is its kind, "v_ok_since" when it last became
## fit to go virtual (-1: not now), "v_fresh" just sent out.
var groups: Array[Dictionary] = []
## Virtual garrisons: module id -> a record like the others ({"squad", "soldiers", "virtual",
## "module_id"}); live garrisons are the level's.
var garrisons := {}
## Men killed while virtual: name -> the time (EnemyCommand's losses, officers).
var deaths := {}
## What it has done this session (the perf line, tests).
var stats := {"virtualized": 0, "woken": 0, "fights": 0, "killed": 0, "wounded": 0}
## Live soldiers that stood near a virtual garrison of their enemies this tick (ZoneLevel.stream_focus
## streams the module in for them, so the garrison comes back to fight them).
var focus: Array[Vector3] = []

var _queue: Array[Dictionary] = []  # records whose men are coming back, front first
var _garrison_count := {}  # garrison_up's answers this frame (module id -> men)
var _garrison_count_tick := -1
var _fights := {}  # "idA|idB" -> {"next": time, "start_a": int, "start_b": int}
var _garrison_ok := {}  # module id -> since when it has been fit to go virtual
var _tick := 0.0
var _clock := 0.0  # the virtual world's own time (server_tick's dt summed): fights run on it
var _next_id := 0
var _rng := RandomNumberGenerator.new()
var _restored := false


func _init() -> void:
	name = NODE_NAME
	add_to_group(&"virtualizer")  # GameState.save_zone finds it


func _ready() -> void:
	_rng.seed = hash([get_parent().name if get_parent() else "", Time.get_ticks_usec()])


static func of(from: Node) -> Virtualizer:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NODE_NAME) as Virtualizer if lvl else null


static func _now() -> float:
	return Soldier._now()


# --- Groups (any record with "squad" and "soldiers") ----------------------------------------------

## Host: `record` ({"squad", "soldiers", ...}, its owner's own) may go virtual from now on, as a
## `kind` (SIDE_KINDS). `fresh`: just sent out, so it goes at the first tick it may (no HOLD_S).
func track(record: Dictionary, kind: String, fresh := true) -> void:
	if not multiplayer.is_server() or _has(groups, record):
		return
	record["v_kind"] = kind
	record["v_ok_since"] = -1.0
	record["v_fresh"] = fresh
	groups.append(record)


## Whether `record` is a profile now (its men not in the world).
static func is_virtual(record: Dictionary) -> bool:
	return record.has("virtual")


## `record`'s men standing: the live ones up (not down, not a body) and the virtual ones.
static func up(record: Dictionary) -> int:
	return live_up(record.get("soldiers", [])).size() + virtual_men(record).size()


## The virtual men of `record` (none when it's live).
static func virtual_men(record: Dictionary) -> Array:
	return (record.virtual as Dictionary).members if record.has("virtual") else []


## Those of `soldiers` still standing (the same test as EnemyResponse._living).
static func live_up(soldiers: Array) -> Array:
	return soldiers.filter(func(s: Variant) -> bool:
		return is_instance_valid(s) and not (s as Soldier).is_queued_for_deletion() and (s as Soldier).vitals.is_up() \
			and not (s as Soldier).is_in_group(Soldier.DEAD_GROUP))


## Where `record` is: its first man up, or its profile's position; Vector3.INF with nobody left.
static func lead(record: Dictionary) -> Vector3:
	var live := live_up(record.get("soldiers", []))
	if not live.is_empty():
		return (live[0] as Soldier).global_position
	if record.has("virtual") and not virtual_men(record).is_empty():
		return record.virtual.pos
	return Vector3.INF


## Where each of `record`'s men up stands (live ones where they are, virtual ones where they'd
## come back).
static func points(record: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for s: Variant in live_up(record.get("soldiers", [])):
		out.append((s as Soldier).global_position)
	if record.has("virtual"):
		var p: Dictionary = record.virtual
		for m: Dictionary in p.members:
			out.append((p.pos as Vector3) + (_v3(m.offset) if not p.get("moved", false) else Vector3.ZERO))
	return out


## Every virtual group now (tracked ones and garrisons).
func virtual_records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in groups:
		if r.has("virtual"):
			out.append(r)
	for r: Dictionary in garrisons.values():
		out.append(r)
	return out


## Every profile now.
func profiles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in virtual_records():
		out.append(r.virtual)
	return out


## How many men are virtual now.
func virtual_count() -> int:
	var n := 0
	for r in virtual_records():
		n += virtual_men(r).size()
	return n


## The virtual man named `who` ({} if there's none): EnemyCommand's officers, who aren't in the
## world while their garrison is a profile.
func member(who: String) -> Dictionary:
	for r in virtual_records():
		for m: Dictionary in virtual_men(r):
			if String(m.name) == who:
				return m
	return {}


## Virtual men of module `module_id`'s garrison (by callsign, or EnemyCommand's "garrison_of"; not
## those who left their post): ZoneLevel.garrison_alive counts them.
func garrison_up(module_id: String) -> int:
	if _garrison_count_tick == Engine.get_process_frames() and _garrison_count.has(module_id):
		return int(_garrison_count[module_id])  # asked by every site check, many times a tick
	if _garrison_count_tick != Engine.get_process_frames():
		_garrison_count.clear()
		_garrison_count_tick = Engine.get_process_frames()
	var prefix := ("%s_H" % module_id).validate_node_name()
	var n := 0
	for r in virtual_records():
		for m: Dictionary in virtual_men(r):
			var meta: Dictionary = m.get("meta", {})
			if (String(m.name).begins_with(prefix) or String(meta.get("garrison_of", "")) == module_id) and not bool(meta.get("left_post", false)):
				n += 1
	_garrison_count[module_id] = n
	return n


## Virtual men of `faction` standing inside `rect` (world x, z): Objectives' clear-area count.
func count_in(rect: Rect2, faction: StringName) -> int:
	var n := 0
	for r in virtual_records():
		var p: Dictionary = r.virtual
		for m: Dictionary in p.members:
			var at: Vector3 = _member_pos(p, m)
			if StringName(m.faction) == faction and rect.has_point(Vector2(at.x, at.z)):
				n += 1
	return n


# --- The tick ---------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if not _queue.is_empty():
		_spawn_queued()
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK_S
	server_tick(TICK_S)


## Host: one tick: groups go virtual or come back, profiles move and fight. `dt`: how much time it
## covers (server_advance runs it in steps).
func server_tick(dt := TICK_S) -> void:
	var lvl := CompoundLevel.current(self)
	if lvl == null:
		return
	_clock += dt
	var eyes := _eyes(lvl)
	var tracked := {}
	groups = groups.filter(func(r: Dictionary) -> bool: return _keep(r))
	for r in groups:
		for s: Variant in r.soldiers:
			if is_instance_valid(s):
				tracked[(s as Object).get_instance_id()] = true
	focus.clear()
	for r in groups:
		if r.has("virtual"):
			continue
		if enabled and _fit(r, eyes):
			server_virtualize(r, true)
	for r in virtual_records():
		if _has(_queue, r):
			continue
		_move(lvl, r, dt)
	_fight_all(lvl, dt)
	for r in virtual_records():
		if _has(_queue, r) or not r.has("virtual"):
			continue
		if r.get("v_kind", "") == "garrison":
			_garrison_focus(lvl, r)
		elif enabled and _wake_due(r, eyes):
			server_wake(r)
	if enabled and lvl is ZoneLevel:
		_garrisons_tick(lvl as ZoneLevel, eyes, tracked)


## Host: runs `seconds` of the virtual world at once, in TICK_S steps (tests).
func server_advance(seconds: float) -> void:
	while seconds > 0.0:
		var step := minf(seconds, TICK_S)
		seconds -= step
		server_tick(step)


## A record stays tracked while its owner may still want it: a profile, or live men left.
func _keep(r: Dictionary) -> bool:
	return r.has("virtual") or _has(_queue, r) or not live_up(r.get("soldiers", [])).is_empty() \
		or (r.get("soldiers", []) as Array).any(func(s: Variant) -> bool: return is_instance_valid(s) and not (s as Soldier).vitals.is_dead())


## Who decides what's near and seen: {"players": [Soldier], "squad": [Soldier], "ai": {faction: [Soldier]}
## (every live AI up that isn't the squad's), "pos": [Vector3] (players and squad)}.
func _eyes(lvl: CompoundLevel) -> Dictionary:
	var players := MapNodes.players(lvl)
	var squad := MapNodes.squad_ai(lvl)
	var pos: Array[Vector3] = []
	for s: Soldier in players:
		pos.append(s.global_position)
	for s: Soldier in squad:
		pos.append(s.global_position)
	var others := {}  # faction -> [Soldier]
	for n in lvl.ai.get_children():
		var s := n as Soldier
		if s and s.squad_slot < 0 and not s.is_queued_for_deletion() and s.vitals.is_up() and s.faction != &"civilian":
			if not others.has(s.faction):
				others[s.faction] = []
			(others[s.faction] as Array).append(s)
	return {"players": players, "squad": squad, "ai": others, "pos": pos}


## Live AI (the squad's aside) at war with `side`: `eyes`'s, by faction.
static func _enemies(eyes: Dictionary, side: StringName) -> Array:
	var out: Array = []
	for f: StringName in eyes.ai:
		if at_war(f, side):
			out.append_array(eyes.ai[f])
	return out


## Whether sides `a` and `b` (factions) fight each other (SquadAI fights any other faction but
## civilians).
static func at_war(a: StringName, b: StringName) -> bool:
	return a != b and a != &"civilian" and b != &"civilian"


## Live group `r` may go virtual now (its HOLD_S kept by "v_ok_since"; a fresh one at once).
func _fit(r: Dictionary, eyes: Dictionary) -> bool:
	var men: Array = (r.soldiers as Array).filter(func(s: Variant) -> bool: return is_instance_valid(s) and not (s as Soldier).vitals.is_dead() \
		and not (s as Soldier).is_in_group(Soldier.DEAD_GROUP) and not (s as Soldier).is_queued_for_deletion())
	if men.is_empty() or not is_instance_valid(r.get("squad")) or not can_virtualize(men, eyes, DESPAWN_M, false, _rides_ok(r, men)):
		r.v_ok_since = -1.0
		r.v_fresh = false
		return false
	var now := _now()
	if r.v_fresh:
		return true
	if float(r.v_ok_since) < 0.0:
		r.v_ok_since = now
	return now - float(r.v_ok_since) >= HOLD_S


## Whether `men` (live soldiers of one group) may go virtual: calm, out of `range_m` of every player
## and squadmate (AI_DESPAWN_M of live enemy AI) and out of every player's sight.
func can_virtualize(men: Array, eyes: Dictionary, range_m: float, teams := false, rides := false) -> bool:
	if men.is_empty():
		return false
	var foes := _enemies(eyes, (men[0] as Soldier).faction)
	for v: Variant in men:
		var s := v as Soldier
		if not calm(s, teams, rides):
			return false
		var at := s.global_position
		for p: Vector3 in eyes.pos:
			if _flat(p, at) < range_m:
				return false
		for o: Soldier in foes:
			if _flat(o.global_position, at) < AI_DESPAWN_M:
				return false
	return not _seen(men, eyes)


## `s` is calm: up, not in contact or fighting, not busy, carrying, carried, in a vehicle or on a
## static weapon team (`teams`: a garrison's packed team goes with its garrison; `rides`: his group is
## aboard rides a profile can take, _rides_ok).
static func calm(s: Soldier, teams := false, rides := false) -> bool:
	if s == null or not s.vitals.is_up() or (is_instance_valid(s.vehicle) and not rides) or s.carry_mode != &"" or is_instance_valid(s.carried_by) \
			or s._is_busy() or (s.has_meta(&"gun_team") and not teams) or s.has_meta(&"vehicle_crew"):
		return false
	var brain := SquadAI.of(s)
	return brain == null or not (brain.in_contact() or brain.fighting())


## A player within SIGHT_M has a clear line to one of `men`.
func _seen(men: Array, eyes: Dictionary) -> bool:
	var world := get_viewport().find_world_3d() if is_inside_tree() else null
	if world == null:
		return false
	for p: Soldier in eyes.players:
		var eye := p.global_position + Vector3.UP * EYE_UP_M
		for v: Variant in men:
			var at := (v as Soldier).global_position
			if eye.distance_to(at) <= SIGHT_M and Throwables.clear_line(world, eye, at + Vector3.UP * BODY_UP_M):
				return true
	return false


## Whether a player within SIGHT_M has a clear line to any of `spots`.
func spots_seen(spots: Array[Vector3], players: Array) -> bool:
	var world := get_viewport().find_world_3d() if is_inside_tree() else null
	if world == null:
		return false
	for p: Variant in players:
		var eye: Vector3 = ((p as Soldier).global_position if p is Soldier else (p as Vector3)) + Vector3.UP * EYE_UP_M
		for at in spots:
			if eye.distance_to(at) <= SIGHT_M and Throwables.clear_line(world, eye, at + Vector3.UP * BODY_UP_M):
				return true
	return false


## Virtual `r` should come back now: a player or squadmate within SPAWN_M where none can see its
## men come out (FORCE_M: regardless), or a live enemy of its side within AI_SPAWN_M.
func _wake_due(r: Dictionary, eyes: Dictionary) -> bool:
	var p: Dictionary = r.virtual
	if (p.members as Array).is_empty():
		return false
	var at: Vector3 = p.pos
	var near := INF
	for e: Vector3 in eyes.pos:
		near = minf(near, _flat(e, at))
	if near <= FORCE_M:
		return true
	if BigZoneStreaming.at_cap(get_parent(), not (p.get("rides", []) as Array).is_empty()):
		return false  # an 8 km zone at its live cap: the profile waits (docs/combined_arms.md 6.2.3)
	for o: Soldier in _enemies(eyes, StringName(p.side)):
		if _flat(o.global_position, at) < AI_SPAWN_M:
			return true
	if near > SPAWN_M:
		return false
	return not spots_seen(spawn_spots(r), eyes.players)


## Whether `list` holds `r` itself (Array.has compares dictionaries by value: two groups alike in
## every field would read as one).
static func _has(list: Array, r: Dictionary) -> bool:
	for x: Variant in list:
		if is_same(x, r):
			return true
	return false


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _v3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


# --- Live -> virtual ---------------------------------------------------------------------------------

## Host: `record`'s men become a profile and leave the world (`force`: whatever the rules say;
## tests, saves). False if it had nobody to virtualize.
func server_virtualize(record: Dictionary, force := false) -> bool:
	if record.has("virtual") or not multiplayer.is_server():
		return false
	var men: Array = (record.get("soldiers", []) as Array).filter(func(s: Variant) -> bool: return is_instance_valid(s) and not (s as Soldier).vitals.is_dead() \
		and not (s as Soldier).is_in_group(Soldier.DEAD_GROUP) and not (s as Soldier).is_queued_for_deletion())
	var rides := _rides_ok(record, men)
	if men.is_empty() or (not rides and men.any(func(s: Variant) -> bool: return is_instance_valid((s as Soldier).vehicle))) \
			or (not force and not men.all(func(s: Variant) -> bool: return calm(s as Soldier, false, rides))):
		return false  # (aboard something that isn't a ride a profile can take: never, forced or not)
	var profile := snapshot(record, men)
	var vehicles := _vehicles_of(men)
	var qrf := VehicleQrf.of(self)
	for v in vehicles:
		if qrf:
			qrf.server_release(v)  # the profile drives it on
	for s: Variant in men:
		_remove(s as Soldier)
	for v in vehicles:
		_remove_vehicle(v)
	(record.soldiers as Array).clear()
	record["virtual"] = profile
	_garrison_count.clear()
	if is_instance_valid(record.get("squad")) and not record.get("v_keep_squad", false):
		(record.squad as Node).process_mode = Node.PROCESS_MODE_DISABLED  # nobody to think for
	stats.virtualized += 1
	return true


## The profile of `record` from its live `men` (left in the world: saves snapshot live groups).
func snapshot(record: Dictionary, men: Array) -> Dictionary:
	_next_id += 1
	var lead_s := men[0] as Soldier
	var centre := lead_s.global_position
	var squad := record.get("squad") as Squad if is_instance_valid(record.get("squad")) else null
	var brain := SquadAI.of(lead_s)
	var members: Array = []
	for s: Variant in men:
		members.append(snap_man(s as Soldier, centre))
	var heading := lead_s.rotation.y
	if lead_s.velocity.length() > 0.3:
		heading = atan2(-lead_s.velocity.x, -lead_s.velocity.z)
	var rides: Array = []
	if _rides_ok(record, men):
		for v in _vehicles_of(men):
			rides.append(_snap_ride(record, v, men))
		var lead_v := Vehicle.ride_of(lead_s)
		centre = lead_v.global_position
		var fwd := -lead_v.global_basis.z
		heading = atan2(-fwd.x, -fwd.z)
	return {"id": "%s_%d" % [String(squad.name) if squad else "group", _next_id], "kind": String(record.get("v_kind", "patrol")),
		"side": String(lead_s.faction), "squad": String(squad.name) if squad else "", "pos": centre, "heading": heading,
		"route_i": brain._patrol_index if brain else 0, "route_ref": squad.patrol if squad else [], "members": members,
		"since": _now(), "moved": not rides.is_empty(), "rides": rides, "ride_i": 0}


# --- Rides -----------------------------------------------------------------------------------------

## The vehicles `men` sit in, each once, in the order their men come.
static func _vehicles_of(men: Array) -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	for s: Variant in men:
		var v := Vehicle.ride_of(s as Soldier) if is_instance_valid(s) else null
		if v and not out.has(v):
			out.append(v)
	return out


## Whether every one of `men` is aboard a ride a profile can take: none walking beside it, nobody else
## aboard, nothing wrecked or burning, nobody's own vehicle, and each a known ride still on its way
## (_ride_info).
func _rides_ok(record: Dictionary, men: Array) -> bool:
	if men.is_empty() or not men.all(func(s: Variant) -> bool: return is_instance_valid(s) and Vehicle.ride_of(s as Soldier) != null):
		return false
	for v in _vehicles_of(men):
		if v.wrecked or v.is_burning() or v.faction == &"player" or v.faction == &"friendly":
			return false
		for o: Variant in v.occupants():
			if not men.has(o) or not (o as Soldier).vitals.is_up():
				return false
		if _ride_info(record, v).is_empty():
			return false
	return true


## Where ride `v` is going, or {}: a VehicleQrf technical on its way in ({"kind": "qrf", "dest", "aim",
## "speed_kmh"}), or one the record's owner vouches for ("v_owner".virtual_ride(v): {"key", "path",
## "speed_kmh"}, "kind": "owner").
func _ride_info(record: Dictionary, v: Vehicle) -> Dictionary:
	var qrf := VehicleQrf.of(self)
	var c: Dictionary = qrf.convoy_of(v) if qrf else {}
	if not c.is_empty():
		return {"kind": "qrf", "dest": c.dismount, "aim": c.aim, "speed_kmh": qrf.speed_kmh(), "path": []}
	var owner: Variant = record.get("v_owner")
	if is_instance_valid(owner) and (owner as Object).has_method(&"virtual_ride"):
		var info: Dictionary = (owner as Object).call(&"virtual_ride", v)
		if not info.is_empty():
			info["kind"] = "owner"
			return info
	return {}


## Ride `v` (of `record`, with `men` aboard) as data: its save (Vehicle.to_save: its id, damage, fuel,
## cargo), who sits where, where it's going and how fast, and its metas.
func _snap_ride(record: Dictionary, v: Vehicle, men: Array) -> Dictionary:
	var info := _ride_info(record, v)
	var seats := {}
	for s: Variant in men:
		if Vehicle.ride_of(s as Soldier) == v:
			seats[String((s as Node).name)] = v.seat_of(s)
	var path: Array[Vector3] = []
	path.assign(info.get("path", []))
	var meta := {}
	for key: StringName in v.get_meta_list():
		var m: Variant = v.get_meta(key)
		if typeof(m) in [TYPE_STRING, TYPE_STRING_NAME, TYPE_BOOL, TYPE_INT, TYPE_FLOAT]:
			meta[String(key)] = String(m) if m is StringName else m
	return {"save": v.to_save(), "seats": seats, "kind": String(info.get("kind", "")), "key": String(info.get("key", "")),
		"dest": info.get("dest", Vector3.INF), "aim": info.get("aim", Vector3.INF), "path": path,
		"speed_kmh": float(info.get("speed_kmh", 40.0)), "meta": meta}


## `v` leaves the world (out of the tree now: the VehicleLayer's spawner despawns it on every client).
static func _remove_vehicle(v: Vehicle) -> void:
	if is_instance_valid(v.ai):
		v.ai.process_mode = Node.PROCESS_MODE_DISABLED
	if v.get_parent():
		v.get_parent().remove_child(v)
	v.queue_free()


## Ride `ride` back in the world at `at`, facing `fwd`, as it was saved. Null if it couldn't come.
func _spawn_ride(lvl: CompoundLevel, ride: Dictionary, at: Vector3, fwd: Vector3) -> Vehicle:
	var layer := lvl.get_node_or_null(^"Vehicles") as VehicleLayer
	var rec: Dictionary = (ride.save as Dictionary).duplicate(true)
	if layer == null or not VehicleSpecs.has_model(String(rec.get("model", ""))):
		return null
	if layer.find(String(rec.get("id", ""))) != null:
		push_warning("Virtualizer: vehicle %s is already in the world" % rec.id)
		return null
	fwd.y = 0.0
	var q := Basis.looking_at(fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD, Vector3.UP).get_rotation_quaternion()
	rec["pos"] = [at.x, at.y + 0.3, at.z]
	rec["rot"] = [q.x, q.y, q.z, q.w]
	var v := layer.server_spawn(String(rec.model), Transform3D.IDENTITY, String(rec.get("scheme", "")), StringName(String(rec.get("faction", "hostile"))),
		String(rec.get("id", "")), rec)
	if v:
		for key: String in (ride.get("meta", {}) as Dictionary):
			v.set_meta(StringName(key), ride.meta[key])
	return v


## The way profile `p` is heading, flat.
static func _fwd(p: Dictionary) -> Vector3:
	var h := float(p.heading)
	return Vector3(-sin(h), 0.0, -cos(h))


## Where profile `p`'s rides come back: the first at its position, the rest RIDE_SPACING_M apart back
## along its way.
func _ride_spots(lvl: CompoundLevel, p: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var fwd := _fwd(p)
	for k in (p.rides as Array).size():
		out.append(lvl.ground_point((p.pos as Vector3) - fwd * RIDE_SPACING_M * k))
	return out


## The route profile `p`'s first ride drives: its path, else the one point it's going to.
static func _ride_route(p: Dictionary) -> Array:
	var ride: Dictionary = p.rides[0]
	if not (ride.get("path", []) as Array).is_empty():
		return ride.path
	var dest := _v3(ride.get("dest", Vector3.INF)) if ride.get("dest") != null else Vector3.INF
	return [dest] if dest.is_finite() else []


## How fast profile `p`'s rides go here (m/s): their speed on a road, RIDE_OFFROAD_MULT of it off one,
## slower up a slope.
static func ride_pace(lvl: CompoundLevel, p: Dictionary) -> float:
	var v := float((p.rides[0] as Dictionary).get("speed_kmh", 40.0)) / 3.6
	var terrain: ZoneTerrain = lvl.get(&"terrain") as ZoneTerrain if lvl is ZoneLevel else null
	if terrain:
		var at: Vector3 = p.pos
		v *= lerpf(RIDE_OFFROAD_MULT, 1.0, terrain.road_weight(at.x, at.z))
		var steep := clampf((1.0 - terrain.normal_at(at.x, at.z).y) / SLOPE_STEEP, 0.0, 1.0)
		v *= lerpf(1.0, RIDE_SLOPE_MIN, steep)
	return v


## Virtual `r` drives its rides' route for `dt` seconds; at its end a QRF ride parks and its men go on
## on foot (_park_rides); another owner's ride holds there (the owner decides: a convoy got away).
func _drive(lvl: CompoundLevel, r: Dictionary, p: Dictionary, dt: float) -> void:
	var route := _ride_route(p)
	if route.is_empty() or p.get("ride_done", false):
		return
	var left := ride_pace(lvl, p) * dt
	for step in 6:
		var i := mini(int(p.get("ride_i", 0)), route.size() - 1)
		var target: Vector3 = route[i]
		var at: Vector3 = p.pos
		var d := _flat(at, target)
		if d <= RIDE_ARRIVE_M:
			if i >= route.size() - 1:
				if String((p.rides[0] as Dictionary).get("kind", "")) == "qrf":
					_park_rides(lvl, r, p)
				else:
					p["ride_done"] = true
				return
			p.ride_i = i + 1
			continue
		var go := minf(left, d)
		var dir := Vector3(target.x - at.x, 0.0, target.z - at.z).normalized()
		var to := at + dir * go
		p.pos = lvl.ground_point(Vector3(to.x, 0.0, to.z))
		p.heading = atan2(-dir.x, -dir.z)
		left -= go
		if left <= 0.01:
			break


## A QRF ride got to where its men get out, off-screen: its vehicles stay there, parked and empty, as
## real ones (as VehicleQrf leaves them), and the men go on on foot along their squad's route.
func _park_rides(lvl: CompoundLevel, r: Dictionary, p: Dictionary) -> void:
	var spots := _ride_spots(lvl, p)
	for k in (p.rides as Array).size():
		var ride: Dictionary = p.rides[k]
		ride.meta["qrf"] = "dismounted"
		var v := _spawn_ride(lvl, ride, spots[k], _fwd(p))
		if v:
			v.server_stop()
	p.rides = []
	p.moved = true
	print("[virtual] %s gets out of its ride off-screen at (%.0f, %.0f)" % [p.id, p.pos.x, p.pos.z])


## One man as data: who he is, his kit (Inventory.net_state), his wounds (Vitals.server_snapshot),
## his brain's skill and orders, his metas and where he stands relative to `centre`.
static func snap_man(s: Soldier, centre: Vector3) -> Dictionary:
	var brain := SquadAI.of(s)
	var meta := {}
	for key: StringName in s.get_meta_list():
		if key in DROP_META:
			continue
		var v: Variant = s.get_meta(key)
		match typeof(v):
			TYPE_STRING_NAME:
				meta[String(key)] = String(v)
			TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
				meta[String(key)] = v
	return {"name": String(s.name), "spawn_id": s.spawn_id, "faction": String(s.faction), "variant": s.variant, "body": s.body,
		"person_name": s.person_name, "nation": s.nation, "role": String(s.role), "team": s.fire_team, "iff": String(s.iff),
		"left": s.left_handed, "slot": String(s.active_slot), "yaw": s.rotation.y, "offset": s.global_position - centre,
		"hold": brain._hold_point if brain and brain._ready_done else s.global_position,
		"combat": brain.combat if brain else 0.5, "discipline": brain.discipline if brain else 0.5, "guard": brain.guard if brain else false,
		"mode": int(brain.combat_mode) if brain else int(Squad.CombatMode.AWARE), "patrol_i": brain._patrol_index if brain else 0,
		"gear": s.inventory.net_state.duplicate(true), "vitals": s.vitals.server_snapshot(), "meta": meta,
		"buddy": String(s.buddy.name) if is_instance_valid(s.buddy) else ""}


## `s` leaves the world (out of the tree now: AISpawner despawns it on every client).
static func _remove(s: Soldier) -> void:
	var brain := SquadAI.of(s)
	if brain:
		brain.process_mode = Node.PROCESS_MODE_DISABLED
	if s.get_parent():
		s.get_parent().remove_child(s)
	s.queue_free()


# --- Virtual -> live ---------------------------------------------------------------------------------

## Host: `record`'s men come back (a few a frame, front first).
func server_wake(record: Dictionary) -> void:
	if not record.has("virtual") or _has(_queue, record):
		return
	var p: Dictionary = record.virtual
	p["spots"] = spawn_spots(record)
	if is_instance_valid(record.get("squad")):
		(record.squad as Node).process_mode = Node.PROCESS_MODE_INHERIT
	_queue.append(record)
	stats.woken += 1


## Host: every queued man comes back now (tests, a save wanting the world as it is).
func server_flush() -> void:
	while not _queue.is_empty():
		_spawn_queued(true)


func _spawn_queued(all := false) -> void:
	var until := Time.get_ticks_usec() + int(SPAWN_BUDGET_MS * 1000.0)
	var lvl := CompoundLevel.current(self)
	if lvl == null:
		return
	while not _queue.is_empty():
		var r: Dictionary = _queue[0]
		var p: Dictionary = r.get("virtual", {})
		var men: Array = p.get("members", [])
		if men.is_empty():
			_queue.pop_front()
			_woke(lvl, r)
			continue
		if not (p.get("rides", []) as Array).is_empty() and not p.has("ride_nodes"):
			var nodes: Array = []
			var ride_at := _ride_spots(lvl, p)
			for k in (p.rides as Array).size():
				nodes.append(_spawn_ride(lvl, p.rides[k], ride_at[k], _fwd(p)))
			p["ride_nodes"] = nodes  # the vehicles first, then their men into their seats
		var m: Dictionary = men.pop_front()
		_garrison_count.clear()
		var spots: Array = p.get("spots", [])
		var at: Vector3 = spots.pop_front() if not spots.is_empty() else lvl.ground_point(p.pos)
		var s := spawn_man(lvl, m, at, r.get("squad") as Squad if is_instance_valid(r.get("squad")) else null)
		if s:
			(r.soldiers as Array).append(s)
			for k in (p.get("ride_nodes", []) as Array).size():
				var seat: Variant = (p.rides[k].seats as Dictionary).get(String(m.name))
				var v: Variant = p.ride_nodes[k]
				if seat != null and is_instance_valid(v):
					(v as Vehicle).server_enter(s, int(seat))
			if not r.has("v_gear"):
				r["v_gear"] = {}
			r.v_gear[String(m.name)] = m.gear  # put on again once its owner has had it back (_woke)
		if not all and Time.get_ticks_usec() >= until:
			return


## `r`'s last man is out: buddies paired again, the owner told (a garrison's level).
func _woke(lvl: CompoundLevel, r: Dictionary) -> void:
	var p: Dictionary = r.get("virtual", {})
	_rides_back(lvl, r, p)
	r.erase("virtual")
	r["v_ok_since"] = -1.0
	r["v_fresh"] = false
	var by_name := {}
	for s: Variant in r.soldiers:
		if is_instance_valid(s):
			by_name[String((s as Node).name)] = s
	# Every man back on the group's leg of its route (the profile's, from its lead), as a moving
	# profile already gives them (_move): whichever man thinks first becomes the patrol's lead
	# (Squad.patrol_lead: the first one patrolling) and the rest take his leg (SquadAI._patrol), so
	# a man left on another leg could take the group back along its route.
	for s: Variant in r.soldiers:
		var brain := SquadAI.of(s) if is_instance_valid(s) else null
		if brain and p.has("route_i"):
			brain._patrol_index = int(p.route_i)
	for s: Variant in r.soldiers:
		if not is_instance_valid(s):
			continue
		var b := String((s as Soldier).get_meta(&"v_buddy", ""))
		(s as Soldier).remove_meta(&"v_buddy")
		var buddy: Variant = null
		if by_name.has(b):
			buddy = by_name[b]
		elif b != "":
			buddy = lvl.ai.get_node_or_null(NodePath(b))
		if buddy is Soldier and (buddy as Soldier).vitals.is_up():
			(s as Soldier).buddy = buddy
	if String(r.get("v_kind", "")) == "garrison":
		garrisons.erase(String(r.module_id))
		_relink_teams(r, by_name)
		if lvl.has_method(&"server_garrison_back"):
			lvl.call(&"server_garrison_back", String(r.module_id), r.soldiers)  # a live garrison is its level's again
	# Whatever the owner did on the way back (a garrison's team formed after a reload hands out its
	# loads and belts), each man ends with exactly the kit he had.
	var gear: Dictionary = r.get("v_gear", {})
	for s: Variant in r.soldiers:
		if is_instance_valid(s) and gear.has(String((s as Node).name)):
			(s as Soldier).inventory.net_state = (gear[String((s as Node).name)] as Dictionary).duplicate(true)
	r.erase("v_gear")


## `r`'s rides are back in the world with their men aboard: each driven on by its owner (a QRF's by
## VehicleQrf, another's by the record's "v_owner".virtual_ride_back) along what's left of its route.
func _rides_back(lvl: CompoundLevel, r: Dictionary, p: Dictionary) -> void:
	var nodes: Array = p.get("ride_nodes", [])
	for k in nodes.size():
		var v := nodes[k] as Vehicle if is_instance_valid(nodes[k]) else null
		if v == null:
			continue
		var ride: Dictionary = p.rides[k]
		var riders: Array = v.occupants()
		if String(ride.kind) == "qrf":
			VehicleQrf.server_resume(lvl, v, riders, _v3(ride.aim), _v3(ride.dest))
		else:
			var left: Array[Vector3] = []
			var path: Array = ride.get("path", [])
			for i in range(mini(int(p.get("ride_i", 0)), path.size()), path.size()):
				left.append(_v3(path[i]))
			var owner: Variant = r.get("v_owner")
			if is_instance_valid(owner) and (owner as Object).has_method(&"virtual_ride_back"):
				(owner as Object).call(&"virtual_ride_back", String(ride.key), v, riders, left, float(ride.speed_kmh))
			elif not left.is_empty():
				v.server_follow_path(PackedVector3Array(left), float(ride.speed_kmh))
	p.erase("ride_nodes")


## Host: `record` is gone for good (a convoy that got away): its profile and its men with it.
func server_forget(record: Dictionary) -> void:
	record.erase("virtual")
	_queue = _queue.filter(func(q: Dictionary) -> bool: return not is_same(q, record))
	groups = groups.filter(func(g: Dictionary) -> bool: return not is_same(g, record))
	_garrison_count.clear()


## A garrison's paused gun and mortar teams get their men back (by name) and run again; each man in
## his team's own squad.
static func _relink_teams(r: Dictionary, by_name: Dictionary) -> void:
	for t: Dictionary in r.get("teams", []):
		var team: Variant = t.node
		if not is_instance_valid(team):
			continue
		var who := func(n: String) -> Soldier: return by_name.get(n) as Soldier if by_name.has(n) else null
		if team is GunTeam:
			(team as GunTeam).gunner = who.call(String(t.gunner))
			(team as GunTeam).assistant = who.call(String(t.assistant))
		elif team is MortarTeam:
			var crew: Array[Soldier] = []
			for n: String in t.crew:
				var s: Soldier = who.call(n)
				if s:
					crew.append(s)
			(team as MortarTeam).crew = crew
		var squad: Squad = team.get(&"squad")
		for s: Variant in by_name.values():
			if String((s as Soldier).get_meta(&"gun_team", "")) == String((team as Node).name) and squad:
				var brain := SquadAI.of(s)
				if brain:
					brain.squad = squad
		(team as Node).process_mode = Node.PROCESS_MODE_INHERIT


## Host: man `m` (snap_man's) back in the world at `at`, as he was: same name, kit, wounds, skill,
## orders, metas; in `squad` (null: his side's), walking it from where the profile had got to.
func spawn_man(lvl: CompoundLevel, m: Dictionary, at: Vector3, squad: Squad) -> Soldier:
	var mode := int(m.get("mode", Squad.CombatMode.AWARE))
	var alert := lvl.get_node_or_null(^"Alert") as Alert
	if alert and mode != Squad.CombatMode.STEALTH:
		mode = maxi(mode, int(Squad.COMBAT_MODES[alert.mode_at(at)]))  # the net may have stood to meanwhile
	var mode_name := "aware"
	for k: String in Squad.COMBAT_MODES:
		if int(Squad.COMBAT_MODES[k]) == mode:
			mode_name = k
	var data := {"name": String(m.name), "spawn_id": String(m.get("spawn_id", m.name)), "faction": String(m.faction), "variant": String(m.get("variant", "")),
		"body": String(m.get("body", "")), "person_name": String(m.get("person_name", "")), "nation": String(m.get("nation", "")),
		"pos": at, "loadout": [], "role": String(m.get("role", "")), "team": int(m.get("team", -1)), "iff": String(m.get("iff", "")),
		"left": bool(m.get("left", false)), "combat": float(m.get("combat", 0.5)), "discipline": float(m.get("discipline", 0.5)),
		"guard": bool(m.get("guard", false)), "mode": mode_name}
	if lvl.ai.get_node_or_null(NodePath(String(m.name))) != null:
		push_warning("Virtualizer: %s is already in the world; not spawned twice" % m.name)
		return null
	var s := lvl.ai_spawner.spawn(data) as Soldier  # (not spawn_soldier: who he is is settled already)
	if s == null:
		return null
	s.inventory.net_state = (m.gear as Dictionary).duplicate(true)  # exactly what he had: rounds, plates, the lot
	var vitals: Variant = m.get("vitals", {})
	if vitals is String:
		vitals = str_to_var(vitals)
	if vitals is Dictionary and not (vitals as Dictionary).is_empty():
		s.vitals.server_restore(vitals)
	s.active_slot = StringName(m.get("slot", "primary"))
	s.rotation.y = float(m.get("yaw", 0.0))
	for key: String in (m.get("meta", {}) as Dictionary):
		s.set_meta(StringName(key), m.meta[key])
	if String(m.get("buddy", "")) != "":
		s.set_meta(&"v_buddy", String(m.buddy))
	var brain := SquadAI.of(s)
	if brain:
		if squad:
			brain.squad = squad
		if not brain._ready_done:
			brain._setup()
		brain._patrol_index = int(m.get("patrol_i", 0))
		if brain.guard:
			brain._hold_point = _v3(m.get("hold", at))  # back at his post
	return s


## Where `record`'s men come back: where they stood (a garrison, or a group that hasn't moved),
## else in a line across its heading round the profile's position; on the ground, outside any
## unstreamed module.
func spawn_spots(record: Dictionary) -> Array[Vector3]:
	var lvl := CompoundLevel.current(self)
	var p: Dictionary = record.virtual
	var out: Array[Vector3] = []
	var men: Array = p.members
	var at: Vector3 = p.pos
	var across := Vector3(cos(float(p.heading)), 0.0, -sin(float(p.heading)))  # the heading's right
	if lvl and not (p.get("rides", []) as Array).is_empty():
		var ride_at := _ride_spots(lvl, p)
		for m: Dictionary in men:
			var spot := ride_at[0]
			for k in (p.rides as Array).size():
				if (p.rides[k].seats as Dictionary).has(String(m.name)):
					spot = ride_at[k]
			out.append(spot)  # (they go straight to their seats)
		return out
	for i in men.size():
		var m: Dictionary = men[i]
		var spot: Vector3
		if String(record.get("v_kind", "")) == "garrison":
			spot = _v3(m.get("hold", m.offset)) if bool(m.get("guard", false)) else at + _v3(m.offset)
			out.append(spot)  # inside its own (streamed) module, on its floors
			continue
		if not p.get("moved", false):
			spot = at + _v3(m.offset)
		else:
			spot = at + across * SPACING_M * (i - (men.size() - 1) / 2.0)
		if lvl:
			spot = _outside_modules(lvl, lvl.ground_point(spot))
		out.append(spot)
	return out


## `p` moved out of any module whose footprint holds it and that isn't streamed in (its walls
## would come in round him later): GATE_M out past its edge, away from its middle.
static func _outside_modules(lvl: CompoundLevel, p: Vector3) -> Vector3:
	if not lvl.has_method(&"module_at"):
		return p
	var m := lvl.call(&"module_at", p) as ZoneModule
	if m == null or m.is_streamed():
		return p
	var half: Vector2 = ZoneModules.HALF.get(m.type, Vector2(20, 20))
	var dir := Vector3(p.x - m.global_position.x, 0.0, p.z - m.global_position.z)
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	return lvl.ground_point(m.global_position + dir * (half.length() + GATE_M))


func _member_pos(p: Dictionary, m: Dictionary) -> Vector3:
	return (p.pos as Vector3) + (Vector3.ZERO if p.get("moved", false) else _v3(m.offset))


# --- Moving --------------------------------------------------------------------------------------------

## Virtual `r` walks its squad's patrol for `dt` seconds (a route changed by its owner starts over,
## as SquadAI's _patrol_index does); guards and an empty route hold.
func _move(lvl: CompoundLevel, r: Dictionary, dt: float) -> void:
	var p: Dictionary = r.virtual
	if not (p.get("rides", []) as Array).is_empty():
		_drive(lvl, r, p, dt)  # aboard: the ride's route, not the squad's
		return
	var squad := r.get("squad") as Squad if is_instance_valid(r.get("squad")) else null
	var route: Array = squad.patrol if squad else p.get("route", [])
	if squad and not is_same(squad.patrol, p.get("route_ref")):
		p.route_ref = squad.patrol
		p.route_i = 0
	if route.is_empty() or (p.members as Array).is_empty() or (p.members as Array).all(func(m: Dictionary) -> bool: return bool(m.get("guard", false))):
		return
	var left := pace(lvl, p) * dt
	for step in 4:
		var target: Vector3 = route[int(p.route_i) % route.size()]
		var at: Vector3 = p.pos
		var d := _flat(at, target)
		if d <= ARRIVE_M:
			if route.size() == 1:
				return  # there: holds
			p.route_i = int(p.route_i) + 1
			continue
		var go := minf(left, d)
		var dir := Vector3(target.x - at.x, 0.0, target.z - at.z).normalized()
		var to := at + dir * go
		p.pos = lvl.ground_point(Vector3(to.x, 0.0, to.z))
		p.heading = atan2(-dir.x, -dir.z)
		p.moved = true
		left -= go
		if left <= 0.01:
			break
	for m: Dictionary in p.members:
		m["patrol_i"] = int(p.route_i)


## How fast profile `p` goes here (m/s): its mode's pace, faster on a road, slower up a slope.
static func pace(lvl: CompoundLevel, p: Dictionary) -> float:
	var mode := int(Squad.CombatMode.AWARE)
	if not (p.members as Array).is_empty():
		mode = int((p.members[0] as Dictionary).get("mode", mode))
	var v := PACE_MPS[clampi(mode, 0, PACE_MPS.size() - 1)]
	var terrain: ZoneTerrain = lvl.get(&"terrain") as ZoneTerrain if lvl is ZoneLevel else null
	if terrain:
		var at: Vector3 = p.pos
		v *= lerpf(1.0, ROAD_MULT, terrain.road_weight(at.x, at.z))
		var steep := clampf((1.0 - terrain.normal_at(at.x, at.z).y) / SLOPE_STEEP, 0.0, 1.0)
		v *= lerpf(1.0, SLOPE_MIN, steep)
	return v


# --- Off-screen fights -------------------------------------------------------------------------------------

## Every pair of profiles at war within CONTACT_M fights a round every ROUND_S.
func _fight_all(lvl: CompoundLevel, _dt: float) -> void:
	var recs := virtual_records().filter(func(r: Dictionary) -> bool: return not _has(_queue, r) and not virtual_men(r).is_empty())
	var now := _clock
	var live_keys := {}
	for i in recs.size():
		for j in range(i + 1, recs.size()):
			var a: Dictionary = recs[i]
			var b: Dictionary = recs[j]
			var pa: Dictionary = a.virtual
			var pb: Dictionary = b.virtual
			if not at_war(StringName(pa.side), StringName(pb.side)) or _flat(pa.pos, pb.pos) > CONTACT_M:
				continue
			if now < float(pa.get("broke_until", -INF)) or now < float(pb.get("broke_until", -INF)):
				continue
			var key := "%s|%s" % [pa.id, pb.id]
			live_keys[key] = true
			if not _fights.has(key):
				_fights[key] = {"next": now + ROUND_S, "start_a": (pa.members as Array).size(), "start_b": (pb.members as Array).size()}
				stats.fights += 1
				print("[virtual] %s (%d) and %s (%d) meet off-screen at (%.0f, %.0f)" % [pa.id, (pa.members as Array).size(), pb.id, (pb.members as Array).size(), pa.pos.x, pa.pos.z])
				continue
			var f: Dictionary = _fights[key]
			while now >= float(f.next):
				f.next = float(f.next) + ROUND_S
				fight_round(lvl, a, b)
				if virtual_men(a).is_empty() or virtual_men(b).is_empty():
					break
				_maybe_break(a, int(f.start_a))
				_maybe_break(b, int(f.start_b))
	for key: String in _fights.keys():
		if not live_keys.has(key):
			_fights.erase(key)
	for r in recs:
		if r.has("virtual") and virtual_men(r).is_empty():
			_wiped(r)


## One round between profiles `a` and `b`: every man of each fires (HIT_CHANCE by his skill; a
## garrison is behind walls: COVER_MULT); each hit kills (KILL_SHARE) or wounds a random man of the
## other. Simultaneous: the shots are worked out before anyone falls.
func fight_round(lvl: CompoundLevel, a: Dictionary, b: Dictionary) -> void:
	var hits_on_b := _armour_hits(_hits(a.virtual, b), a, b)
	var hits_on_a := _armour_hits(_hits(b.virtual, a), b, a)
	for k in hits_on_b:
		_hit(lvl, b)
	for k in hits_on_a:
		_hit(lvl, a)


## combined_arms 3.8's armour table: a group a SideCommand tasks carries its kind ("vf_kind");
## hits scale by SideCommand.fight_factor (a tank shrugs off rifles, an AT team hurts it). Groups
## without a kind fight as before.
func _armour_hits(hits: int, attacker: Dictionary, target: Dictionary) -> int:
	if not attacker.has("vf_kind") and not target.has("vf_kind"):
		return hits
	var f := SideCommand.fight_factor(String(attacker.get("vf_kind", "rifle_squad")), String(target.get("vf_kind", "rifle_squad")),
		bool(attacker.get("vf_at", false)))
	var scaled := hits * f
	return floori(scaled) + (1 if _rng.randf() < scaled - floorf(scaled) else 0)


func _hits(p: Dictionary, target: Dictionary) -> int:
	var cover := COVER_MULT if String(target.get("v_kind", "")) == "garrison" else 1.0
	var n := 0
	for m: Dictionary in p.members:
		var hurt := clampf(_blood(m), 0.3, 1.0)
		if _rng.randf() < HIT_CHANCE * (0.5 + float(m.get("combat", 0.5))) * hurt * cover:
			n += 1
	return n


## A hit on a random man of `r`: killed, or wounded (blood lost; killed once too little is left).
func _hit(lvl: CompoundLevel, r: Dictionary) -> void:
	var men: Array = r.virtual.members
	if men.is_empty():
		return
	var i := _rng.randi() % men.size()
	var m: Dictionary = men[i]
	if _rng.randf() < KILL_SHARE or _blood(m) - WOUND_BLOOD < DEAD_BLOOD:
		men.remove_at(i)
		_kill(lvl, r.virtual, m)
	else:
		_set_blood(m, _blood(m) - WOUND_BLOOD)
		stats.wounded += 1


static func _vitals_of(m: Dictionary) -> Dictionary:
	var v: Variant = m.get("vitals", {})
	if v is String:
		v = str_to_var(v)
		m["vitals"] = v
	return v if v is Dictionary else {}


static func _blood(m: Dictionary) -> float:
	return float((_vitals_of(m).get("model", {}) as Dictionary).get("blood", 1.0))


static func _set_blood(m: Dictionary, blood: float) -> void:
	var v := _vitals_of(m)
	if not v.has("model"):
		v["model"] = {}
	v.model["blood"] = blood
	m["vitals"] = v


## Man `m` of profile `p` killed off-screen: a real body with his kit where he fell, his death on
## record (deaths; GameState.post_fell through the body, as a man killed in the world).
func _kill(lvl: CompoundLevel, p: Dictionary, m: Dictionary) -> void:
	deaths[String(m.name)] = _now()
	stats.killed += 1
	_garrison_count.clear()
	var at := lvl.ground_point(_member_pos(p, m) + Vector3(_rng.randf_range(-2.0, 2.0), 0.0, _rng.randf_range(-2.0, 2.0)))
	lvl.server_spawn_body({"spawn_id": String(m.get("spawn_id", m.name)), "label": String(m.person_name) if String(m.get("person_name", "")) != "" else String(m.name),
		"faction": String(m.faction), "variant": String(m.get("variant", "")), "body": String(m.get("body", "")),
		"person_name": String(m.get("person_name", "")), "nation": String(m.get("nation", "")), "left": bool(m.get("left", false)),
		"role": String(m.get("role", "")), "pos": [at.x, at.y, at.z], "rot_y": _rng.randf() * TAU, "age_s": 0.0,
		"gear": (m.gear as Dictionary).duplicate(true)})


## A side cut to BREAK_SHARE of what it started the fight with breaks off for BREAK_S (a garrison
## holds its walls).
func _maybe_break(r: Dictionary, start: int) -> void:
	if String(r.get("v_kind", "")) == "garrison" or start <= 0:
		return
	if float(virtual_men(r).size()) <= start * BREAK_SHARE:
		r.virtual["broke_until"] = _clock + BREAK_S
		print("[virtual] %s breaks off (%d of %d left)" % [r.virtual.id, virtual_men(r).size(), start])


## Profile `r` has nobody left: it's gone (its owner sees the group lost: up() is 0).
func _wiped(r: Dictionary) -> void:
	r.erase("virtual")
	if String(r.get("v_kind", "")) == "garrison":
		garrisons.erase(String(r.get("module_id", "")))
	groups = groups.filter(func(g: Dictionary) -> bool: return not is_same(g, r))


# --- Garrisons ---------------------------------------------------------------------------------------

## Garrisons whose module streamed out go virtual at their posts once calm and unseen for HOLD_S.
func _garrisons_tick(lvl: ZoneLevel, eyes: Dictionary, tracked: Dictionary) -> void:
	var had := lvl._garrisoned
	for module_id: String in had:
		if garrisons.has(module_id) or int(lvl.garrison_pending(module_id)) > 0:
			continue
		var m := lvl.get_module(module_id)
		if m == null or m.is_streamed():
			_garrison_ok.erase(module_id)
			continue
		var men := garrison_men(lvl, module_id, tracked)
		if men.is_empty() or not _teams_packed(lvl, module_id) or not can_virtualize(men, eyes, GARRISON_DESPAWN_M, true):
			_garrison_ok.erase(module_id)
			continue
		var since := float(_garrison_ok.get(module_id, _now()))
		_garrison_ok[module_id] = since
		if _now() - since >= HOLD_S:
			server_virtualize_garrison(lvl, module_id, men)


## Module `module_id`'s garrison men in the world (by callsign, or "garrison_of"; not those who left
## it, nor any a tracked group holds: `tracked`, instance ids).
static func garrison_men(lvl: ZoneLevel, module_id: String, tracked := {}) -> Array:
	var prefix := ("%s_H" % module_id).validate_node_name()
	var out: Array = []
	for n in lvl.ai.get_children():
		var s := n as Soldier
		if s == null or s.is_queued_for_deletion() or s.vitals.is_dead() or s.is_in_group(Soldier.DEAD_GROUP) or tracked.has(s.get_instance_id()):
			continue
		if (String(s.name).begins_with(prefix) or String(s.get_meta(&"garrison_of", "")) == module_id) and not s.get_meta(&"left_post", false):
			out.append(s)
	return out


## The garrison's gun and mortar teams are packed up (a manned gun keeps its site real).
static func _teams_packed(lvl: ZoneLevel, module_id: String) -> bool:
	var post := lvl.post_of(module_id)
	for n in lvl.get_children():
		if (n is GunTeam or n is MortarTeam) and n.get(&"post") == post and post != null and int(n.get(&"state")) != 0:
			return false
	return true


## Host: module `module_id`'s garrison (`men`, else every man of it in the world) becomes a profile at
## its posts. Its post keeps its state; its gun and mortar teams wait, paused, for their men (they
## aren't formed again: that would hand out their loads and belts a second time).
func server_virtualize_garrison(lvl: ZoneLevel, module_id: String, men: Array = []) -> bool:
	if garrisons.has(module_id):
		return false
	if men.is_empty():
		men = garrison_men(lvl, module_id)
	if men.is_empty():
		return false
	var record := {"squad": lvl.site_squad(module_id), "soldiers": men.duplicate(), "v_kind": "garrison", "module_id": module_id, "teams": []}
	var post := lvl.post_of(module_id)
	for n in lvl.get_children():
		if post == null or n.get(&"post") != post:
			continue
		if n is GunTeam:
			var gt := n as GunTeam
			record.teams.append({"node": gt, "gunner": String(gt.gunner.name) if is_instance_valid(gt.gunner) else "",
				"assistant": String(gt.assistant.name) if is_instance_valid(gt.assistant) else ""})
		elif n is MortarTeam:
			var mt := n as MortarTeam
			record.teams.append({"node": mt, "crew": mt.crew.map(func(s: Variant) -> String: return String((s as Node).name) if is_instance_valid(s) else "")})
		else:
			continue
		(n as Node).process_mode = Node.PROCESS_MODE_DISABLED  # its men are a profile: nothing to run
	if not server_virtualize(record, true):
		for t: Dictionary in record.teams:
			(t.node as Node).process_mode = Node.PROCESS_MODE_INHERIT
		return false
	if post:
		post.members.clear()
	garrisons[module_id] = record
	_garrison_ok.erase(module_id)
	print("[virtual] %s's garrison (%d) goes virtual at its posts" % [module_id, virtual_men(record).size()])
	return true


## Whether module `module_id`'s garrison is a profile now.
func has_garrison(module_id: String) -> bool:
	return garrisons.has(module_id)


## Host (ZoneLevel._spawn_garrison, its module streamed in): the garrison comes back at its posts.
func server_wake_garrison(module_id: String) -> void:
	if garrisons.has(module_id):
		server_wake(garrisons[module_id])


## Host (EnemyCommand._abandon_outposts): virtual garrison `module_id` leaves its post as a group of
## `squad` (walking where its squad's patrol sends it). The new group's record ({} with none).
func server_detach_garrison(module_id: String, squad: Squad) -> Dictionary:
	var r: Dictionary = garrisons.get(module_id, {})
	if r.is_empty() or _has(_queue, r):
		return {}
	garrisons.erase(module_id)
	_garrison_count.clear()
	if is_instance_valid(r.get("squad")):
		(r.squad as Node).process_mode = Node.PROCESS_MODE_INHERIT  # the site's squad: nobody of it is a profile now
	var p: Dictionary = r.virtual
	for m: Dictionary in p.members:
		var meta: Dictionary = m.get("meta", {})
		meta["left_post"] = true
		meta.erase("garrison_of")
		m["meta"] = meta
		m["guard"] = false
	p.kind = "withdraw"
	p.moved = true
	var out := {"squad": squad, "soldiers": [], "virtual": p}
	track(out, "withdraw", false)
	return out


## A virtual garrison's enemies close by (live AI at war with it, within ZoneLevel.STREAM_IN_M of
## its module): ZoneLevel.stream_focus streams the module in for them, and the garrison comes back.
func _garrison_focus(lvl: CompoundLevel, r: Dictionary) -> void:
	var m := lvl.call(&"get_module", String(r.module_id)) as ZoneModule if lvl.has_method(&"get_module") else null
	if m == null:
		return
	var side := StringName(r.virtual.side)
	for n in lvl.ai.get_children():
		var s := n as Soldier
		if s and s.squad_slot < 0 and s.vitals.is_up() and at_war(s.faction, side) and m.distance_to(s.global_position) <= ZoneLevel.STREAM_IN_M:
			focus.append(s.global_position)
			return


# --- Saves ---------------------------------------------------------------------------------------------------

## Every group as a saved profile (JSON-ready): the virtual ones, and the tracked groups and garrisons
## still live (snapshotted where they stand, left in the world).
func to_save() -> Array:
	server_flush()  # nobody half out of a profile
	var out: Array = []
	var lvl := CompoundLevel.current(self)
	for r in virtual_records():
		if not r.get("v_nosave", false):
			out.append(_save_record(r, r.virtual))
	for r in groups:
		if r.has("virtual") or _has(_queue, r) or r.get("v_nosave", false):  # (a mission's convoy is its scenario's to save)
			continue
		var men: Array = (r.soldiers as Array).filter(func(s: Variant) -> bool: return is_instance_valid(s) and (s as Soldier).vitals.is_up() \
			and not (s as Soldier).is_in_group(Soldier.DEAD_GROUP))
		if not men.is_empty():
			out.append(_save_record(r, snapshot(r, men)))
	if lvl is ZoneLevel:
		var tracked := {}
		for r in groups:
			for s: Variant in r.soldiers:
				if is_instance_valid(s):
					tracked[(s as Object).get_instance_id()] = true
		for module_id: String in (lvl as ZoneLevel)._garrisoned:
			if garrisons.has(module_id):
				continue
			var men := garrison_men(lvl as ZoneLevel, module_id, tracked).filter(func(s: Variant) -> bool: return (s as Soldier).vitals.is_up())
			if not men.is_empty():
				var rec := {"squad": (lvl as ZoneLevel).site_squad(module_id), "v_kind": "garrison", "module_id": module_id}
				out.append(_save_record(rec, snapshot(rec, men)))
	return out


## `p` (of record `r`) as JSON-ready data: vectors as arrays, wounds as text (var_to_str: typed).
func _save_record(r: Dictionary, p: Dictionary) -> Dictionary:
	var squad := r.get("squad") as Squad if is_instance_valid(r.get("squad")) else null
	var route: Array = []
	for v: Variant in (squad.patrol if squad else p.get("route", [])):
		route.append(_arr(_v3(v)))
	var men: Array = []
	for m: Dictionary in p.members:
		var out := m.duplicate(true)
		out.offset = _arr(_v3(m.offset))
		out.hold = _arr(_v3(m.get("hold", Vector3.ZERO)))
		out.vitals = var_to_str(_vitals_of(m.duplicate(true)))
		men.append(out)
	var owner := {}
	for key: String in ["k", "j", "second", "module_id", "at", "to", "index", "kind", "target_id", "state"]:
		if r.has(key):
			var v: Variant = r[key]
			owner[key] = _arr(v) if v is Vector3 else v
	var rides: Array = []
	for ride: Dictionary in p.get("rides", []):
		var out := ride.duplicate(true)
		for key: String in ["dest", "aim"]:
			var v3 := _v3(ride.get(key)) if ride.get(key) != null else Vector3.INF
			out[key] = _arr(v3) if v3.is_finite() else null
		out.path = (ride.get("path", []) as Array).map(func(v: Variant) -> Array: return _arr(_v3(v)))
		rides.append(out)
	return {"id": String(p.id), "kind": String(r.get("v_kind", p.kind)), "side": String(p.side), "squad": String(squad.name) if squad else String(p.get("squad", "")),
		"pos": _arr(p.pos), "heading": float(p.heading), "route": route, "route_i": int(p.route_i), "moved": bool(p.get("moved", false)),
		"members": men, "owner": owner, "rides": rides, "ride_i": int(p.get("ride_i", 0))}


static func _arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


## Whether `p` reads as a saved profile (GameState.read_save keeps only these).
static func save_ok(p: Variant) -> bool:
	if typeof(p) != TYPE_DICTIONARY or typeof(p.get("members")) != TYPE_ARRAY or typeof(p.get("kind")) != TYPE_STRING \
			or typeof(p.get("route", [])) != TYPE_ARRAY or not GameState._finite_pos(p.get("pos")):
		return false
	for m: Variant in p.members:
		if typeof(m) != TYPE_DICTIONARY or typeof(m.get("name")) != TYPE_STRING or typeof(m.get("gear")) != TYPE_DICTIONARY:
			return false
	return true


## Saved data back to a profile (vectors, item ids, typed wounds).
static func from_save(data: Dictionary) -> Dictionary:
	var members: Array = []
	for m: Dictionary in data.members:
		var out := m.duplicate(true)
		out.offset = _v3(m.get("offset", []))
		out.hold = _v3(m.get("hold", []))
		out.gear = GameState.from_json(m.gear)
		out.vitals = str_to_var(String(m.get("vitals", ""))) if m.get("vitals") is String else m.get("vitals", {})
		out.team = int(m.get("team", -1))
		out.mode = int(m.get("mode", Squad.CombatMode.AWARE))
		out.patrol_i = int(m.get("patrol_i", 0))
		(out.get("meta", {}) as Dictionary).erase("gun_team")  # that team was this session's: one forms again (_woke keeps the kit)
		members.append(out)
	var route: Array[Vector3] = []
	for v: Variant in data.get("route", []):
		route.append(_v3(v))
	var rides: Array = []
	for ride: Variant in data.get("rides", []):
		if typeof(ride) != TYPE_DICTIONARY or typeof(ride.get("save")) != TYPE_DICTIONARY or typeof(ride.get("seats")) != TYPE_DICTIONARY:
			continue
		var out: Dictionary = (ride as Dictionary).duplicate(true)
		out.dest = _v3(ride.dest) if ride.get("dest") is Array else Vector3.INF
		out.aim = _v3(ride.aim) if ride.get("aim") is Array else Vector3.INF
		var path: Array[Vector3] = []
		for v: Variant in ride.get("path", []):
			path.append(_v3(v))
		out.path = path
		var seats := {}
		for n: Variant in ride.seats:
			seats[String(n)] = int(ride.seats[n])
		out.seats = seats
		rides.append(out)
	return {"id": String(data.get("id", "")), "kind": String(data.kind), "side": String(data.get("side", "hostile")), "squad": String(data.get("squad", "")),
		"pos": _v3(data.pos), "heading": float(data.get("heading", 0.0)), "route": route, "route_i": int(data.get("route_i", 0)),
		"route_ref": null, "moved": bool(data.get("moved", false)), "members": members, "since": _now(), "owner": data.get("owner", {}),
		"rides": rides, "ride_i": int(data.get("ride_i", 0))}


## Host, as the zone loads (ZoneLevel._on_hosted, after the bodies): the saved profiles back
## (GameState.profiles). Garrisons wait for their modules; patrols for EnemyResponse.server_start
## (take_patrol); hunters, HQ pairs and QRF waves go back on their owners' lists; the rest (task
## forces, skirmishers) are tracked with no owner, walking their saved routes.
func server_restore() -> void:
	if _restored or not multiplayer.is_server():
		return
	_restored = true
	var lvl := CompoundLevel.current(self)
	var response := EnemyResponse.of(self)
	for data: Variant in GameState.profiles:
		if not save_ok(data):
			continue
		var p := from_save(data)
		if (p.members as Array).is_empty():
			continue
		var owner: Dictionary = p.owner
		match String(p.kind):
			"garrison":
				var module_id := String(owner.get("module_id", ""))
				if lvl is ZoneLevel and (lvl as ZoneLevel).get_module(module_id) != null:
					var zl := lvl as ZoneLevel
					zl._garrisoned[module_id] = maxi(int(zl._garrisoned.get(module_id, 0)), zl.garrison_size(module_id))
					garrisons[module_id] = {"squad": zl.site_squad(module_id), "soldiers": [], "v_kind": "garrison", "module_id": module_id, "virtual": p}
			"patrol", "roam":
				_saved_routes.append(p)  # EnemyResponse.server_start takes them back by route (take_saved)
			_:
				var squad: Squad = response._new_squad(_fresh_name(response, String(p.squad))) if response else null
				if squad:
					squad.patrol = p.route
					squad.process_mode = Node.PROCESS_MODE_DISABLED
				p.route_ref = squad.patrol if squad else null
				var r := {"squad": squad, "soldiers": [], "virtual": p}
				for key: String in owner:
					r[key] = owner[key]
				if response and String(p.kind) == "hunters":
					r.merge({"k": response.hunters.size() + 1, "at": response.now(), "retarget_at": response.now(), "smoked": false}, true)
					response.hunters.append(r)
					track(r, "hunters", false)
				elif response and String(p.kind) == "pair" and owner.has("to"):
					r.merge({"k": response.reinforcement_pairs.size() + 1, "at": response.now()}, true)
					response.reinforcement_pairs.append(r)
					track(r, "pair", false)
				elif response and response.reinforcements and String(p.kind) == "qrf":
					r.merge({"index": response.reinforcements.waves.size(), "at_s": 0.0, "sent_at": response.reinforcements._now(), "size": (p.members as Array).size(),
						"edge": p.pos, "target": Vector3.INF}, true)
					response.reinforcements.waves.append(r)
					track(r, "qrf", false)
				else:
					track(r, String(p.kind), false)  # no owner took it back: it walks its saved route
	GameState.profiles = []


var _saved_routes: Array[Dictionary] = []


## Host (EnemyResponse.server_start): the saved profile of `kind` ("patrol", "roam") whose owner
## matches every key of `match` (a patrol's "k" and "second", a roaming team's "k" and "j"), taken
## (so it's given once); {} if there's none.
func take_saved(kind: String, match: Dictionary) -> Dictionary:
	for p: Dictionary in _saved_routes:
		if String(p.kind) != kind:
			continue
		var owner: Dictionary = p.owner
		var all := true
		for key: String in match:
			var want: Variant = match[key]
			var have: Variant = owner.get(key)
			all = all and have != null and (bool(have) == bool(want) if want is bool else int(have) == int(want))
		if all:
			_saved_routes.erase(p)
			return p
	return {}


## Host: `record` takes saved profile `p` (EnemyResponse's patrol): virtual from the start.
func adopt(record: Dictionary, p: Dictionary, kind: String) -> void:
	var squad := record.get("squad") as Squad if is_instance_valid(record.get("squad")) else null
	if squad:
		squad.process_mode = Node.PROCESS_MODE_DISABLED
	p.route_ref = squad.patrol if squad else null
	(record.soldiers as Array).clear()
	record["virtual"] = p
	track(record, kind, false)


## `want` if no node under `response` has it, else with a number on.
static func _fresh_name(response: Node, want: String) -> String:
	var base := want.validate_node_name() if want != "" else "Restored"
	var name := base
	var k := 2
	while response and response.get_node_or_null(NodePath(name)) != null:
		name = "%s_%d" % [base, k]
		k += 1
	return name
