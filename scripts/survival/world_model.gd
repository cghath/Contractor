class_name WorldModel
extends RefCounted
## The far world of Contractor: Fallen (docs/survival_world.md sections 2-5, 9; calls 20-24, 52,
## 67): pure data and rules, no scene tree, so one step runs on a worker thread (WorldSim) and two
## models from one seed agree (determinism: every roll from the world seed + group id + tick).
##
## Holds `w` (Survival.state()["world"]: "groups", "zones" (WorldRegions' table: region, type,
## links, places with their holder, the dead's density, traces, a far horde), "events", "goal",
## "demands", "tick", ...), `people` (the Person records the sim may touch: SurvivorPerson's, by
## id) and `pressure` (Survival.state()["pressure"]: {zone: {"v", "at", "x", "z"}}, the same
## record the hosted zone's live system keeps; the sim writes only zones not hosted).
## step() is one far tick (TICK_MIN world minutes): every group not live takes one decision step
## (WorldGoals), journeys advance, supplies are eaten, far fights resolve (WorldFights), the dead
## refill and far hordes form, walk the pressure gradient and break up, groups form, split, die
## and new lone survivors trickle in at the map's edges. Main-thread work it needs (a demand to
## the players, a horde walking into the hosted zone, the hosted zone's pressure) goes out in
## `actions`; new events in `new_events`.

## One far tick: 15 world minutes (30 s real at Survival.DAY_MIN 48; WorldSim scales it).
const TICK_MIN := 15.0
const TICKS_PER_DAY := 96
## Proposed: a zone crossing on foot takes TRAVEL_TICKS (2 world hours); a vehicle halves it.
const TRAVEL_TICKS := 8.0
## Proposed: a group with a goal under way weighs its options again every RETHINK_TICKS (an hour);
## an idle one every tick.
const RETHINK_TICKS := 4
const EVENTS_CAP := 300
## What a group remembers of the event pool (its intel: the rumours it can tell).
const INTEL_CAP := 80
const TRACES_CAP := 20
## Proposed: the pressure numbers match Survival's (S3): a horde at HORDE_AT, gone under DISPERSE_AT.
const HORDE_AT := 80.0
const DISPERSE_AT := 30.0
const HALF_LIFE_H := 6.0
const HORDE_N := Vector2i(30, 60)
## Proposed: a zone holds about DEAD_PER_ZONE x its base density of the dead (the clear-the-map
## count); refills over REFILL_DAYS.
const DEAD_PER_ZONE := 300.0
const REFILL_DAYS := 2.0
## Proposed: lone survivors walking in at the map's edges a world day, and groups at a new world.
const TRICKLE_PER_DAY := 0.6
const GROUPS_PER_ZONE := Vector2i(0, 2)
const LONE_PER_ZONE := Vector2i(0, 2)
## Proposed: per tick chances of forming and splitting.
const MERGE_CHANCE := 0.05
const SPLIT_CHANCE := 0.03
const SPLIT_MORALE := 0.2
## Proposed: starvation: a day at full hunger costs a member.
const STARVE_TICKS := 96
## World events (call 124): the share of days that roll one.
const WORLD_EVENT_CHANCE := 0.35
const SEASON_DAYS := 10
const SEASONS: Array[String] = ["spring", "summer", "autumn", "winter"]
const SEASON_YIELD := {"spring": 1.0, "summer": 1.2, "autumn": 1.1, "winter": 0.4}
const OUTSIDE_RUMOURS: Array[String] = ["They say the cities up north burned clean, nothing walking.", "There's a ship off the coast that takes anyone who can swim to it.",
	"I heard the army's holding a line past the mountains.", "Some say the islands never got it.", "A man I walked with swore there's a whole town fenced in down south, with lights."]

var w: Dictionary
var people: Dictionary
var pressure: Dictionary
var world_seed := 0
## The world's time (day + hour / 24) and the zone hosted ("" when none).
var now := 1.0
var hosted := ""
## The players: {"zone" (their settlement's zone), "place", "strength", "stocks_value", "zones"
## (zones with players), "safe" (catch-up: the settlement can't be attacked)}.
var player := {}
## Out to the main thread: [{"kind", ...}] and the events this step added.
var actions: Array = []
var new_events: Array = []
## Tests: a Dictionary to sum where the step's time goes (usec by phase), else null.
var profile: Variant = null
## Clear-the-map and evac multipliers (WorldSim.goal_state): the dead's refill speed.
var refill_mult := 1.0


func _init(p_w: Dictionary, p_people: Dictionary, p_pressure: Dictionary, p_seed: int) -> void:
	w = p_w
	people = p_people
	pressure = p_pressure
	world_seed = p_seed
	for key: String in ["groups", "zones", "demands", "fallen"]:
		if not w.get(key) is Dictionary:
			w[key] = {}
	if not w.get("events") is Array:
		w["events"] = []
	for key: String in ["tick", "next_group", "next_person", "next_event"]:
		if not w.has(key):
			w[key] = 0


func tick() -> int:
	return int(w.get("tick", 0))


func groups() -> Dictionary:
	return w.groups


func zones() -> Dictionary:
	return w.zones


## The living groups (sorted by id), and by zone: an index rebuilt when the tick or the number of
## groups changes (a tick's decisions read where groups were at its start).
var _index := {}
var _index_all: Array = []
var _index_key := []


func _ensure_index() -> void:
	var key := [tick(), (w.groups as Dictionary).size()]
	if key == _index_key:
		return
	_index_key = key
	_index = {}
	_index_all = []
	for gid: String in _sorted(w.groups.keys()):
		var g: Dictionary = w.groups[gid]
		if not bool(g.get("alive", false)):
			continue
		_index_all.append(g)
		var z := String(g.zone)
		if not _index.has(z):
			_index[z] = []
		(_index[z] as Array).append(g)


func alive_groups() -> Array:
	_ensure_index()
	return _index_all


func groups_in_zone(z: String) -> Array:
	_ensure_index()
	return _index.get(z, [])


## The living groups in any of `zone_ids`, sorted by id.
func groups_near(zone_ids: Array) -> Array:
	_ensure_index()
	if zone_ids.size() == 1:
		return _index.get(zone_ids[0], [])
	var out: Array = []
	for z: String in zone_ids:
		out.append_array(_index.get(z, []))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.id) < String(b.id))
	return out


func group(id: String) -> Dictionary:
	return (w.groups as Dictionary).get(id, {})


func zone(id: String) -> Dictionary:
	return (w.zones as Dictionary).get(id, {})


## A roll for `who` this tick: the world seed + who + the tick + why.
func rng_for(who: String, why := "") -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([world_seed, who, tick(), why])
	return r


func day() -> int:
	return int(floor(now))


func season() -> String:
	return Seasons.of_day(day(), String(w.get("season_start", Seasons.START)))  # (the New world option: Seasons)


## The crossing between two zones' key, and whether it's open (a blown bridge closes it:
## Infrastructure.server_set_crossing; goals, journeys and far hordes go round).
static func crossing_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


func crossing_open(a: String, b: String) -> bool:
	return not (w.get("crossings", {}) as Dictionary).has(crossing_key(a, b))


## A group made of people who already exist (a settlement's faction walking out, the settlement
## passing to a challenger: Politics): `pids` its members led by `leader_id`, `home` its home if
## any. Once per id (a mutate re-runs it on the worker's result). Returns the group.
func group_from_people(gid: String, kind: String, zone_id: String, pos: Vector2, pids: Array, leader_id: String, why: String, home := {}) -> Dictionary:
	if (w.groups as Dictionary).has(gid):
		return w.groups[gid]
	var g := WorldGroup.make(gid, kind, rng_for(gid, "made"), zone_id, pos)
	g.born_tick = tick()
	for pid: Variant in pids:
		var rec: Dictionary = people.get(String(pid), {})
		if rec.is_empty():
			continue
		(g.members as Array).append(String(pid))
		rec["status"] = WorldGroup.GROUPED
		rec["world_group"] = gid
		rec["zone"] = zone_id
	if leader_id in (g.members as Array):
		g.leader = leader_id
		g.personality = WorldGroup.personality_of(people.get(leader_id, {}), rng_for(gid, "leader"))
	else:
		_new_leader(g)
	g.relations["player"] = -20.0 if home.is_empty() else -10.0
	g.grudge = "player" if home.is_empty() else ""
	for k: String in WorldGroup.SUPPLY_KEYS:
		g.supplies[k] = 2.0 * (g.members as Array).size() if k in ["food", "water"] else 0.0
	if not home.is_empty():
		g.home = home.duplicate(true)
		g.defence = 0.5
	w.groups[gid] = g
	event(zone_id, "split", [gid], why)
	return g


# --- Setup ---------------------------------------------------------------------------------------

## A new world's groups and lone survivors in `zone_table` (WorldRegions.build_zone's, made on the
## main thread), by the seed and the region's tendencies; `start_zone` (the safehouse farm at the
## quiet edge, call 41) gets none: its first neighbours are the people lane's lone survivors and
## the cold open's (Proposed), and no group walks into it on day one (WorldGoals.reach).
func setup(zone_table: Dictionary, start_zone: String, world_mult := 1.0) -> void:
	w.zones = zone_table
	for z: String in _sorted(zone_table.keys()):
		var zd: Dictionary = zone_table[z]
		zd.dead = 1.0
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([world_seed, z, "groups"])
		var reg := WorldRegions.region_def(String(zd.region))
		var n := roundi(rng.randi_range(GROUPS_PER_ZONE.x, GROUPS_PER_ZONE.y) * world_mult)
		if String(zd.type) in ["village", "town", "farmland", "coast"]:
			n += 1
		if z == start_zone:
			n = 0
		for i in n:
			var kind := _roll_kind(reg.get("kinds", {}), rng)
			var place: Dictionary = (zd.places as Array)[rng.randi_range(0, (zd.places as Array).size() - 1)]
			var g := new_group(kind, z, _place_pos(place, rng, 30.0), rng)
			if kind in ["settlers", "raiders", "cultists"] and String(place.holder) == "":
				set_home(g, z, place)
		var lone := rng.randi_range(LONE_PER_ZONE.x, LONE_PER_ZONE.y)
		if z == start_zone:
			lone = 0  # (SurvivorsLayer places the start zone's own)
		for i in lone:
			var place: Dictionary = (zd.places as Array)[rng.randi_range(0, (zd.places as Array).size() - 1)]
			new_lone(z, _place_pos(place, rng, 40.0), rng, "holed up near %s" % _place_name(place))
	w["start_zone"] = start_zone


func _roll_kind(kinds: Dictionary, rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	for k: String in _sorted(kinds.keys()):
		r -= float(kinds[k])
		if r <= 0.0:
			return k
	return "settlers"


## A new group of `kind` at `pos` in `zone`: a leader leaning to the kind and members, Person
## records (status grouped), its personality from the leader, supplies by kind.
func new_group(kind: String, zone_id: String, pos: Vector2, rng: RandomNumberGenerator, n := -1) -> Dictionary:
	var gid := "g%d" % (int(w.next_group) + 1)
	w.next_group = int(w.next_group) + 1
	var g := WorldGroup.make(gid, kind, rng, zone_id, pos)
	g.born_tick = tick()
	var size_range: Vector2i = WorldGroup.SIZE.get(kind, Vector2i(2, 5))
	var count := n if n > 0 else rng.randi_range(size_range.x, size_range.y)
	for i in count:
		var opts := {}
		if i == 0 and not (WorldGroup.LEADER_TRAITS.get(kind, []) as Array).is_empty():
			opts["traits"] = (WorldGroup.LEADER_TRAITS[kind] as Array).duplicate()
		var rec := new_person(rng, zone_id, pos, opts)
		rec.status = WorldGroup.GROUPED
		rec["world_group"] = gid
		(g.members as Array).append(String(rec.id))
	g.leader = String(g.members[0]) if not (g.members as Array).is_empty() else ""
	g.personality = WorldGroup.personality_of(people.get(g.leader, {}), rng)
	var per: Dictionary = WorldGroup.START_SUPPLIES.get(kind, {})
	for k: String in per:
		g.supplies[k] = snappedf(float(per[k]) * count * rng.randf_range(0.7, 1.3), 0.01)
	g.relations["player"] = {"settlers": 10.0, "scavengers": 0.0, "raiders": -30.0, "cultists": -40.0, "enclave": 0.0}.get(kind, 0.0)
	w.groups[gid] = g
	return g


## A new Person (SurvivorPerson.make) with an id of the world's ("w<n>"), in `zone_id` at `pos`
## (y to be set on the ground when the zone is hosted: "y_unset").
func new_person(rng: RandomNumberGenerator, zone_id: String, pos: Vector2, opts := {}) -> Dictionary:
	var pid := "w%d" % (int(w.next_person) + 1)
	w.next_person = int(w.next_person) + 1
	var rec := SurvivorPerson.make(rng, pid, opts)
	rec.zone = zone_id
	rec.pos = [snappedf(pos.x, 0.01), 0.0, snappedf(pos.y, 0.01)]
	rec.home = rec.pos.duplicate()
	rec["y_unset"] = true
	rec["world_made"] = true
	people[pid] = rec
	return rec


## A lone survivor out there (status out_there: the companion pool SurvivorsLayer shows when the
## zone is hosted), and their group of one.
func new_lone(zone_id: String, pos: Vector2, rng: RandomNumberGenerator, how: String) -> Dictionary:
	var rec := new_person(rng, zone_id, pos)
	rec.status = "out_there"
	note(rec, how)
	return lone_group(rec)


## The group of one for the lone survivor `rec` (made once; id "lone_<person id>").
func lone_group(rec: Dictionary) -> Dictionary:
	var gid := "lone_" + String(rec.id)
	if w.groups.has(gid):
		return w.groups[gid]
	var rng := rng_for(gid, "lone")
	var p: Array = rec.get("pos", [0.0, 0.0, 0.0])
	var g := WorldGroup.make(gid, "lone", rng, String(rec.get("zone", "")), Vector2(float(p[0]), float(p[2])))
	g.name = String(rec.get("name", "a survivor"))
	g.leader = String(rec.id)
	g.members = [String(rec.id)]
	g.personality = WorldGroup.personality_of(rec, rng)
	for k: String in WorldGroup.START_SUPPLIES.lone:
		g.supplies[k] = float(WorldGroup.START_SUPPLIES.lone[k])
	g.relations["player"] = 0.0
	w.groups[gid] = g
	return g


## Lone survivors SurvivorsLayer placed (status out_there) become groups of one; groups of one
## whose person isn't out there any more (hired, dead) are gone. Read, never moved.
func sync_lone() -> void:
	for pid: String in _sorted(people.keys()):
		var rec: Dictionary = people[pid]
		if String(rec.get("status", "")) == "out_there" and not w.groups.has("lone_" + pid):
			lone_group(rec)
	for gid: String in _sorted(w.groups.keys()):
		var g: Dictionary = w.groups[gid]
		if String(g.kind) != "lone" or not bool(g.alive):
			continue
		var rec: Dictionary = people.get(String(g.leader), {})
		if String(rec.get("status", "")) != "out_there":
			g.alive = false
			g.members = []
		else:
			g.zone = String(rec.get("zone", g.zone))
			var p: Array = rec.get("pos", [0.0, 0.0, 0.0])
			g.pos = [float(p[0]), float(p[2])]


func set_home(g: Dictionary, zone_id: String, place: Dictionary) -> void:
	clear_home(g)
	g.home = {"zone": zone_id, "place": String(place.id), "pos": (place.pos as Array).duplicate()}
	place.holder = String(g.id)
	g.zone = zone_id


func clear_home(g: Dictionary) -> void:
	var h: Dictionary = g.get("home", {})
	if h.is_empty():
		return
	var pl := WorldRegions.place(zone(String(h.zone)), String(h.place))
	if not pl.is_empty() and String(pl.holder) == String(g.id):
		pl.holder = ""
	g.home = {}


# --- The tick ------------------------------------------------------------------------------------

## One far tick at world time `at` (day + hour / 24).
func step(at: float) -> void:
	now = at
	w.tick = tick() + 1
	actions = []
	new_events = []
	var t0 := Time.get_ticks_usec()
	sync_lone()
	for z: String in _sorted(w.zones.keys()):
		_zone_tick(z)
	Holding.sim_tick(self)  # the dead at far households' doors: held, or left (call 143)
	var t1 := Time.get_ticks_usec()
	var t_decide := 0
	for gid: String in _sorted(w.groups.keys()):
		var g: Dictionary = w.groups.get(gid, {})
		if g.is_empty() or not bool(g.alive) or bool(g.get("live", false)):
			continue
		if String(g.kind) == "lone":
			_lone_tick(g)
			continue
		_eat(g)
		if not bool(g.alive):
			continue
		_mood(g)
		_kind_change(g)
		if (g.goal as Dictionary).is_empty() or (tick() + absi(hash(gid))) % RETHINK_TICKS == 0:  # (busy groups rethink hourly, staggered)
			var td := Time.get_ticks_usec()
			WorldGoals.decide(self, g)
			t_decide += Time.get_ticks_usec() - td
		WorldGoals.act(self, g)
	var t2 := Time.get_ticks_usec()
	_form_and_split()
	_trickle()
	WorldEvents.tick(self)  # (world events' windows: docs/survival_events.md)
	if tick() % TICKS_PER_DAY == 0:
		_world_event()
		_prune()
	if profile is Dictionary:  # (tests: where a tick's time goes, usec)
		for pair: Array in [["zones", t1 - t0], ["decide", t_decide], ["act", t2 - t1 - t_decide], ["form", Time.get_ticks_usec() - t2]]:
			profile[pair[0]] = int(profile.get(pair[0], 0)) + int(pair[1])


## `n` ticks from `from` (the catch-up and tests), each TICK_MIN on.
func run(n: int, from: float) -> void:
	for i in n:
		step(from + (i + 1) * TICK_MIN / 1440.0)


func _lone_tick(g: Dictionary) -> void:
	pass  # (the person is SurvivorsLayer's: read, not moved; others recruit or take them)


## Food and water eaten (desert water goes faster), hunger when out, a member lost to it now and then.
func _eat(g: Dictionary) -> void:
	var n := float(WorldGroup.size(g))
	if n <= 0.0:
		_group_dies(g, "nobody left")
		return
	var water_x := 1.3 if String(zone(String(g.zone)).get("region", "")) == "desert" else 1.0
	var short := WorldGroup.supply(g, "food") < n / TICKS_PER_DAY or WorldGroup.supply(g, "water") < n * water_x / TICKS_PER_DAY
	WorldGroup.add_supply(g, "food", -n / TICKS_PER_DAY)
	WorldGroup.add_supply(g, "water", -n * water_x / TICKS_PER_DAY)
	var mood: Dictionary = g.mood
	if short:
		mood.hunger = minf(1.0, float(mood.hunger) + 2.0 / TICKS_PER_DAY)
		g["starving"] = int(g.get("starving", 0)) + 1
		if int(g.starving) >= STARVE_TICKS:
			g.starving = 0
			var rng := rng_for(String(g.id), "starve")
			var victim := String(g.members[rng.randi_range(0, (g.members as Array).size() - 1)])
			if rng.randf() < 0.5:
				person_dies(victim, g, "starved", false)
			else:
				_desert(g, victim)
	else:
		mood.hunger = maxf(0.0, float(mood.hunger) - 1.0 / TICKS_PER_DAY)
		g.starving = 0


## Fear from the zone's pressure and a horde; morale from hunger, fear and supplies.
func _mood(g: Dictionary) -> void:
	var mood: Dictionary = g.mood
	var p := pressure_of(String(g.zone)) / 100.0
	var horde := not (zone(String(g.zone)).get("horde", {}) as Dictionary).is_empty()
	var fear_to := clampf(p + (0.4 if horde else 0.0), 0.0, 1.0)
	mood.fear = snappedf(lerpf(float(mood.fear), fear_to, 0.1), 0.001)
	var morale_to := clampf(0.8 - float(mood.hunger) * 0.6 - float(mood.fear) * 0.3 + minf(WorldGroup.days_of_food(g), 5.0) * 0.04, 0.0, 1.0)
	mood.morale = snappedf(lerpf(float(mood.morale), morale_to, 0.05), 0.001)


## Kind changes (4.1): settlers who lost everything under a cruel leader turn raider; raiders who
## lost their leader and fear the dead more than they hate people settle.
func _kind_change(g: Dictionary) -> void:
	var p: Dictionary = g.personality
	if String(g.kind) == "settlers" and (g.home as Dictionary).is_empty() and WorldGroup.days_of_food(g) < 0.5 and float(p.get("cruelty", 0.0)) >= 0.45:
		g.kind = "raiders"
		event(String(g.zone), "turned", [String(g.id)], "%s have turned to raiding" % String(g.name))
	elif String(g.kind) == "raiders" and bool(g.get("leader_lost", false)) and float((g.mood as Dictionary).fear) > 0.6 and float(p.get("cruelty", 0.0)) < 0.4:
		g.kind = "settlers"
		g.erase("leader_lost")
		event(String(g.zone), "turned", [String(g.id)], "%s have put down their guns to settle" % String(g.name))


# --- People --------------------------------------------------------------------------------------

func note(rec: Dictionary, text: String) -> void:
	var h: Array = rec.get("history", [])
	h.append({"day": day(), "text": text})
	rec["history"] = h.slice(-30)


## `pid` of `g` dies (`how`): their record dead where the group is, out of the group; a new leader
## when it was theirs.
func person_dies(pid: String, g: Dictionary, how: String, by_dead: bool, place := {}) -> void:
	var rec: Dictionary = people.get(pid, {})
	(g.members as Array).erase(pid)
	if not rec.is_empty():
		rec.status = "dead"
		rec["died_day"] = day()
		rec["killed_by_dead"] = by_dead
		rec["buried"] = false
		rec["world_dead"] = how
		rec.zone = String(g.zone)
		var at: Array = place.get("pos", g.pos) if not place.is_empty() else g.pos
		rec["body_pos"] = [float(at[0]), 0.0, float(at[1])]
		note(rec, "died: %s" % how)
	if pid == String(g.leader):
		_new_leader(g)


## The member with the most loyalty-earning traits leads (4.6); the personality follows them.
func _new_leader(g: Dictionary) -> void:
	var best := ""
	var best_v := -INF
	for pid: String in g.members:
		var rec: Dictionary = people.get(pid, {})
		var t: Array = rec.get("traits", [])
		var v := float(rec.get("loyalty", 40.0)) / 50.0
		for good: String in ["brave", "kind", "loyal", "calm", "hard_worker", "optimist"]:
			if good in t:
				v += 1.0
		if v > best_v or (v == best_v and pid < best):
			best_v = v
			best = pid
	g.leader = best
	if best != "":
		g.personality = WorldGroup.personality_of(people.get(best, {}), rng_for(String(g.id), "leader"))
		g["leader_lost"] = true


## A member walks off alone: a lone survivor again (the companion pool).
func _desert(g: Dictionary, pid: String) -> void:
	var rec: Dictionary = people.get(pid, {})
	(g.members as Array).erase(pid)
	if rec.is_empty():
		return
	rec.status = "out_there"
	rec.erase("world_group")
	rec.zone = String(g.zone)
	rec.pos = [float(g.pos[0]) + 20.0, 0.0, float(g.pos[1])]
	rec["y_unset"] = true
	rec["grudge_group"] = String(g.id)
	note(rec, "left %s" % String(g.name))
	lone_group(rec)
	if pid == String(g.leader):
		_new_leader(g)


func _group_dies(g: Dictionary, why: String) -> void:
	if not bool(g.alive):
		return
	g.alive = false
	g["died_tick"] = tick()
	var h: Dictionary = g.get("home", {})
	if not h.is_empty():
		add_trace(String(h.zone), String(h.place), "an empty camp, %s's" % String(g.name), [])
	clear_home(g)
	for pid: String in (g.captives as Array).duplicate():
		var rec: Dictionary = people.get(pid, {})
		if String(rec.get("status", "")) == "captive":
			rec.status = "out_there"
			rec.zone = String(g.zone)
			rec.pos = [float(g.pos[0]), 0.0, float(g.pos[1])]
			rec["y_unset"] = true
			lone_group(rec)
	g.captives = []
	if String(g.kind) != "lone":
		event(String(g.zone), "group_gone", [String(g.id)], "%s are gone (%s)" % [String(g.name), why])


func add_trace(zone_id: String, place_id: String, text: String, dead_names: Array) -> void:
	var zd := zone(zone_id)
	if zd.is_empty():
		return
	var t: Array = zd.traces
	t.append({"place": place_id, "day": day(), "text": text, "dead": dead_names})
	if t.size() > TRACES_CAP:
		zd.traces = t.slice(-TRACES_CAP)


# --- Pressure and the dead across the map (section 5) ------------------------------------------

## A zone's pressure now (0-100), decayed from when it was last raised (Survival's record).
func pressure_of(zone_id: String) -> float:
	var p: Dictionary = pressure.get(zone_id, {})
	if p.is_empty():
		return 0.0
	var hours := (now - float(p.get("at", now))) * 24.0
	return float(p.get("v", 0.0)) * pow(0.5, maxf(hours, 0.0) / HALF_LIFE_H)


## Raises a zone's pressure: written here for a far zone; for the hosted one an action for the
## main thread (Survival's live pressure).
func raise_pressure(zone_id: String, amount: float, at := Vector2.ZERO) -> void:
	if amount <= 0.0 or zone_id == "":
		return
	if zone_id == hosted:
		actions.append({"kind": "pressure", "zone": zone_id, "amount": amount, "pos": [at.x, at.y]})
		return
	var v := clampf(pressure_of(zone_id) + amount, 0.0, 100.0)
	pressure[zone_id] = {"v": snappedf(v, 0.01), "at": now, "x": at.x, "y": 0.0, "z": at.y}


## The zone's dead: refill toward full (not in zones held by the players' standing presence in
## clear-the-map), a far horde at HORDE_AT that walks the gradient (crossing only into a zone
## louder than its own) and breaks up under DISPERSE_AT.
func _zone_tick(z: String) -> void:
	var zd: Dictionary = w.zones[z]
	if not bool(zd.get("held_by_player", false)):
		zd.dead = snappedf(minf(1.0, float(zd.get("dead", 1.0)) + refill_mult / (REFILL_DAYS * TICKS_PER_DAY)), 0.0001)
	if z == hosted:
		return  # (the hosted zone's hordes are Survival's and ZoneDead's)
	var p := pressure_of(z)
	var horde: Dictionary = zd.get("horde", {})
	if horde.is_empty():
		if p >= HORDE_AT:
			var rng := rng_for(z, "horde")
			var n := roundi(rng.randi_range(HORDE_N.x, HORDE_N.y) * clampf(float(zd.dead), 0.3, 1.0))
			zd.horde = {"n": n, "since": tick()}
			event(z, "horde", [], "a horde of the dead is gathering in %s" % String(zd.get("name", z)))
		return
	if p < DISPERSE_AT:
		horde.n = int(horde.n) - maxi(1, int(horde.n) / 5)
		if int(horde.n) < 5:
			zd.horde = {}
			event(z, "horde_gone", [], "the horde in %s has broken up" % String(zd.get("name", z)))
		return
	var best := ""
	var best_p := p
	for nb: String in zd.get("links", []):
		if not crossing_open(z, nb):
			continue  # (a blown bridge: the horde goes round)
		var np := pressure_of(nb)
		if np > best_p:
			best_p = np
			best = nb
	if best != "" and (tick() - int(horde.get("since", 0))) >= 4:
		var nd := zone(best)
		zd.horde = {}
		if best == hosted:
			actions.append({"kind": "horde_enter", "zone": best, "from": z, "n": int(horde.n)})
		else:
			var there: Dictionary = nd.get("horde", {})
			nd.horde = {"n": int(horde.n) + int(there.get("n", 0)), "since": tick()}
		event(best, "horde_moved", [], "a horde came over from %s into %s" % [String(zd.get("name", z)), String(nd.get("name", best))])
		return
	WorldFights.horde_on_groups(self, z)


# --- Forming, splitting, the trickle (4.6) -----------------------------------------------------

func _form_and_split() -> void:
	var by_zone := {}
	for gid: String in _sorted(w.groups.keys()):
		var g: Dictionary = w.groups[gid]
		if not bool(g.alive) or bool(g.get("live", false)) or String(g.zone) == hosted:
			continue
		if not by_zone.has(String(g.zone)):
			by_zone[String(g.zone)] = []
		(by_zone[String(g.zone)] as Array).append(g)
	for z: String in _sorted(by_zone.keys()):
		var here: Array = by_zone[z]
		var small := here.filter(func(g: Dictionary) -> bool: return String(g.kind) == "lone" or (WorldGroup.size(g) <= 2 and String(g.kind) != "enclave"))
		if small.size() >= 2 and rng_for(z, "merge").randf() < MERGE_CHANCE:
			_merge(small[0], small[1])
	for gid: String in _sorted(w.groups.keys()):
		var g: Dictionary = w.groups[gid]
		if not bool(g.alive) or String(g.kind) in ["lone", "enclave"] or bool(g.get("live", false)):
			continue
		if float((g.mood as Dictionary).morale) < SPLIT_MORALE and WorldGroup.size(g) >= 4 and rng_for(gid, "split").randf() < SPLIT_CHANCE:
			split(g)


## Two small groups (or lone survivors) near shelter and food become one; the leader is the one
## with the most loyalty-earning traits, the kind from them.
func _merge(a: Dictionary, b: Dictionary) -> void:
	if WorldGroup.relation(a, String(b.id)) < -10.0 or WorldGroup.relation(b, String(a.id)) < -10.0:
		return
	var base := a if String(a.kind) != "lone" else (b if String(b.kind) != "lone" else {})
	var rng := rng_for(String(a.id) + String(b.id), "form")
	var g: Dictionary
	if base.is_empty():
		g = WorldGroup.make("g%d" % (int(w.next_group) + 1), "settlers", rng, String(a.zone), WorldGroup.pos2(a))
		w.next_group = int(w.next_group) + 1
		g.born_tick = tick()
		g.relations["player"] = 0.0
		w.groups[String(g.id)] = g
	else:
		g = base
	for other: Dictionary in [a, b]:
		if is_same(other, g):
			continue
		for pid: String in other.members:
			var rec: Dictionary = people.get(pid, {})
			if rec.is_empty():
				continue
			rec.status = WorldGroup.GROUPED
			rec["world_group"] = String(g.id)
			if not pid in (g.members as Array):
				(g.members as Array).append(pid)
		for k: String in WorldGroup.SUPPLY_KEYS:
			WorldGroup.add_supply(g, k, WorldGroup.supply(other, k))
		other.alive = false
		other.members = []
	_new_leader(g)
	g.erase("leader_lost")
	if String(g.kind) != "enclave":
		g.kind = WorldGroup.kind_for(g.personality)
	event(String(g.zone), "formed", [String(g.id)], "survivors banded together as %s" % String(g.name))


## Morale broke (or two leaders disagree): a share of the people and supplies walk off with a
## grudge. Returns the new group.
func split(g: Dictionary) -> Dictionary:
	var rng := rng_for(String(g.id), "split_who")
	var leaving: Array = []
	for pid: String in g.members:
		if pid != String(g.leader) and rng.randf() < 0.45:
			leaving.append(pid)
	if leaving.is_empty() and WorldGroup.size(g) >= 2:
		leaving.append(String(g.members[-1]) if String(g.members[-1]) != String(g.leader) else String(g.members[0]))
	var ng := WorldGroup.make("g%d" % (int(w.next_group) + 1), "settlers", rng, String(g.zone), WorldGroup.pos2(g) + Vector2(60.0, 0.0))
	w.next_group = int(w.next_group) + 1
	ng.born_tick = tick()
	var share := float(leaving.size()) / maxf(1.0, float(WorldGroup.size(g)))
	for pid: String in leaving:
		(g.members as Array).erase(pid)
		(ng.members as Array).append(pid)
		(people.get(pid, {}) as Dictionary)["world_group"] = String(ng.id)
	for k: String in WorldGroup.SUPPLY_KEYS:
		var amount := WorldGroup.supply(g, k) * share
		WorldGroup.add_supply(g, k, -amount)
		WorldGroup.add_supply(ng, k, amount)
	w.groups[String(ng.id)] = ng
	_new_leader(ng)
	ng.erase("leader_lost")
	ng.kind = WorldGroup.kind_for(ng.personality)
	ng.relations[String(g.id)] = -30.0
	ng.relations["player"] = WorldGroup.relation(g, "player")
	g.relations[String(ng.id)] = -30.0
	event(String(g.zone), "split", [String(g.id), String(ng.id)], "%s split; %s went their own way" % [String(g.name), String(ng.name)])
	return ng


## New lone survivors walk in at the map's edges (zones with fewer than 4 links) at TRICKLE_PER_DAY,
## bringing rumours of outside that never resolve.
func _trickle() -> void:
	var rng := rng_for("world", "trickle")
	if rng.randf() >= TRICKLE_PER_DAY / TICKS_PER_DAY:
		return
	var edges: Array = []
	for z: String in _sorted(w.zones.keys()):
		if (zone(z).get("links", []) as Array).size() < 4 and z != hosted and z != String(w.get("start_zone", "")):
			edges.append(z)
	if edges.is_empty():
		return
	var z := String(edges[rng.randi_range(0, edges.size() - 1)])
	var half := float(zone(z).get("size_m", 1920.0)) * 0.5 - 120.0
	var side := rng.randi_range(0, 3)
	var along := rng.randf_range(-half, half)
	var pos := [Vector2(along, -half), Vector2(along, half), Vector2(-half, along), Vector2(half, along)][side] as Vector2
	var g := new_lone(z, pos, rng, "walked in from outside")
	var rec: Dictionary = people.get(String(g.leader), {})
	rec["outside_rumour"] = OUTSIDE_RUMOURS[rng.randi_range(0, OUTSIDE_RUMOURS.size() - 1)]
	event(z, "arrived", [String(g.id)], "a stranger walked into %s from outside" % String(zone(z).get("name", z)))


## A world event a day at most (call 124): WorldEvents (data/survival_events.json): an enclave
## supply drop every group races for, a convoy on the MSR, a downed helicopter, a bell rung as a
## lure, a town burning on the horizon, a storm that takes a bridge out.
func _world_event() -> void:
	WorldEvents.roll(self)


## Dead groups and old demands forgotten after 10 world days.
func _prune() -> void:
	for gid: String in _sorted(w.groups.keys()):
		var g: Dictionary = w.groups[gid]
		if not bool(g.alive) and tick() - int(g.get("died_tick", tick())) > 10 * TICKS_PER_DAY:
			w.fallen[gid] = {"name": String(g.name), "kind": String(g.kind), "died_tick": int(g.get("died_tick", 0))}
			w.groups.erase(gid)
		elif not bool(g.alive) and not g.has("died_tick"):
			g["died_tick"] = tick()


# --- Events (section 10's inputs) ----------------------------------------------------------------

## An event in the pool: {"id", "day", "hour", "t", "zone", "kind", "groups", "text", "place"};
## every group in it and every group in the zone know it (intel "seen").
func event(zone_id: String, kind: String, gids: Array, text: String, place := "") -> Dictionary:
	var id := int(w.next_event) + 1
	w.next_event = id
	var e := {"id": id, "day": day(), "hour": snappedf(fmod(now, 1.0) * 24.0, 0.1), "t": snappedf(now, 0.001), "zone": zone_id,
		"kind": kind, "groups": gids.duplicate(), "text": text, "place": place}
	var ev: Array = w.events
	ev.append(e)
	if ev.size() > EVENTS_CAP:
		w.events = ev.slice(-EVENTS_CAP)
	new_events.append(e)
	for g: Dictionary in alive_groups():
		if bool(g.alive) and (String(g.id) in gids or String(g.zone) == zone_id):
			learn(g, id, "seen")
	return e


## `g` knows event `id` (how: "seen", "scout", "told"); the better source wins.
func learn(g: Dictionary, id: int, how: String) -> void:
	if not g.get("intel") is Dictionary:
		g["intel"] = {}
	var intel: Dictionary = g.intel
	var key := str(id)
	var rank := {"told": 0, "seen": 1, "scout": 2}
	if not intel.has(key) or int(rank.get(how, 0)) > int(rank.get(String(intel[key]), 0)):
		intel[key] = how
	if intel.size() > INTEL_CAP + 40:  # (trimmed in batches: the oldest go)
		var keys := intel.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return a.to_int() < b.to_int())
		for k: String in keys.slice(0, intel.size() - INTEL_CAP):
			intel.erase(k)


func event_by_id(id: int) -> Dictionary:
	for e: Dictionary in w.events:
		if int(e.id) == id:
			return e
	return {}


# --- Helpers -------------------------------------------------------------------------------------

static func _sorted(keys: Array) -> Array:
	var out := keys.duplicate()
	out.sort()
	return out


func _place_pos(place: Dictionary, rng: RandomNumberGenerator, spread: float) -> Vector2:
	var p: Array = place.get("pos", [0.0, 0.0])
	var a := rng.randf() * TAU
	return Vector2(float(p[0]), float(p[1])) + Vector2(cos(a), sin(a)) * rng.randf_range(spread * 0.3, spread)


static func _place_v(place: Dictionary) -> Vector2:
	var p: Array = place.get("pos", [0.0, 0.0])
	return Vector2(float(p[0]), float(p[1]))


static func _place_name(place: Dictionary) -> String:
	var t := String(place.get("type", ""))
	return "the %s" % (t if t != "" else "crossroads")


func place_name(zone_id: String, place_id: String) -> String:
	var pl := WorldRegions.place(zone(zone_id), place_id)
	return "%s in %s" % [_place_name(pl), String(zone(zone_id).get("name", zone_id))]
