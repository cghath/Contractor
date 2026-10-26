class_name WorldEvents
extends RefCounted
## World events of Contractor: Fallen (docs/survival_events.md; call 124): things that happen to the
## whole map, rolled by the world sim (WorldModel calls roll() once a world day and tick() every far
## tick; both worker-safe: pure data, no scene) and told by the rumour layer and the radio (they are
## ordinary events in the pool: groups in the zone learn them, the radio's chatter and enclave
## channel read them, the journal gets the near ones).
##
## Kinds (data/survival_events.json; every number Proposed):
## - supply_drop: the enclave drops a crate at a place; every group in reach races for it (a forage
##   goal at that place); the place is rich until it's taken; the enclave broadcasts it; a cache
##   ("Supply drop") when its zone is hosted; whoever loots it first claims it (a group: an event; a
##   player: the enclave's standing drops a little, it was theirs).
## - convoy: an enclave or trader column moving along the road through a zone with 3+ links (the
##   MSR) toward the next; at the window's end raiders in reach may ambush it (their supplies up,
##   the enclave's grudge), else it passes and the settlers it passed traded with it; hosted, the
##   column's wagon stands at the place (a cache: robbing it is an event, the column's people turn).
## - heli_down: a wreck at a place (a cache when hosted) and its crew as lone survivors beside it;
##   the enclave asks for them back (a broadcast); at the window's end the enclave recovers the crew
##   still out there, else they're lost to it.
## - bell: cultists ring a bell to call the dead (pressure in the zone, a lure ringing in the live
##   zone); a player rings one too (FallenBell: server_ring).
## - burning: a town burns on the horizon: the zone's pressure up, its places poorer, a glow in the
##   sky of zones within glow_links (DayNight's "glow" meta), the zone's fire lit if it's hosted
##   while it burns (Wildfire).
## - storm: takes a bridge out: the crossing between two zones closed (WorldModel.crossing_open;
##   Infrastructure's bridge_repair project opens it again).
## Records live in the world section's "fallen_events" ({id: {"id", "kind", "zone", "place", "t",
## "until", "state" (open | done), "outcome", ...}}); the event in the pool carries the same id.
## Frequency: chance_per_day x the "world" option (world_mult), kept in the section as event_mult.

const PATH := "res://data/survival_events.json"
const KEY := "fallen_events"
const KINDS: Array[String] = ["supply_drop", "convoy", "heli_down", "bell", "burning", "storm"]
## The outcomes' event kinds (journal and radio read them too).
const OUTCOME_KINDS: Array[String] = ["supply_taken", "supply_lapsed", "convoy_ambushed", "convoy_passed", "convoy_robbed", "heli_recovered", "heli_lost", "fire_out", "storm_passed"]
## A live event's cache is "fev_<id>" (its contents kept by the zone save like any cache).
const CACHE_PREFIX := "fev_"
## Done records are forgotten after this many world days.
const FORGET_DAYS := 10.0
## The glow's colour reaches DayNight through its "glow" meta (0-1).
const GLOW_META := &"glow"
const BELL_LURE := "bell"

static var _data := {}
## Host: per level instance, the live pieces already put out ({level id: {event id: true}}).
static var _live := {}


## The events' data (data/survival_events.json, mods merged in: ModKit).
static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text()) if f else null
		parsed = ModKit.overlay("survival_events", parsed)
		_data = parsed if parsed is Dictionary else {"chance_per_day": 0.0, "kinds": {}}
	return _data


static func kind_def(kind: String) -> Dictionary:
	return (data().get("kinds", {}) as Dictionary).get(kind, {})


## The records ({id string: record}) in world section `w`.
static func records(w: Dictionary) -> Dictionary:
	if not w.get(KEY) is Dictionary:
		w[KEY] = {}
	return w[KEY]


## The open records of `kind` ("" any) in `w`.
static func open(w: Dictionary, kind := "") -> Array:
	var out: Array = []
	var recs := records(w)
	for k: String in WorldModel._sorted(recs.keys()):
		var r: Dictionary = recs[k]
		if String(r.get("state", "")) == "open" and (kind == "" or String(r.kind) == kind):
			out.append(r)
	return out


static func record(w: Dictionary, id: int) -> Dictionary:
	return records(w).get(str(id), {})


# --- The roll (worker-safe) ----------------------------------------------------------------------

## Once a world day (WorldModel._world_event): chance_per_day x event_mult, then a kind by weight and
## a zone that fits it. Returns the new record ({} none).
static func roll(m: WorldModel) -> Dictionary:
	var rng := m.rng_for("world", "event")
	var d := data()
	var chance := float(d.get("chance_per_day", 0.35)) * float(m.w.get("event_mult", 1.0))
	if rng.randf() >= chance:
		return {}
	var kinds: Dictionary = d.get("kinds", {})
	var total := 0.0
	var names := WorldModel._sorted(kinds.keys())
	for k: String in names:
		total += maxf(0.0, float((kinds[k] as Dictionary).get("weight", 0.0)))
	if total <= 0.0:
		return {}
	var r := rng.randf() * total
	var kind := ""
	for k: String in names:
		r -= maxf(0.0, float((kinds[k] as Dictionary).get("weight", 0.0)))
		if r <= 0.0:
			kind = k
			break
	if kind == "":
		kind = String(names[names.size() - 1])
	var z := pick_zone(m, kind, rng)
	return begin(m, kind, z, {}, rng) if z != "" else {}


## A zone for `kind`: never the hosted one (but a bell may ring there), a convoy's on the road (3+
## links), a storm's with a crossing still open, a cultist's bell where the cult is.
static func pick_zone(m: WorldModel, kind: String, rng: RandomNumberGenerator) -> String:
	var zs: Array = []
	for z: String in WorldModel._sorted(m.zones().keys()):
		var zd := m.zone(z)
		if (zd.get("places", []) as Array).is_empty():
			continue
		if z == m.hosted and kind != "bell":
			continue
		match kind:
			"convoy":
				if (zd.get("links", []) as Array).size() < 3:
					continue
			"storm":
				if not (zd.get("links", []) as Array).any(func(l: String) -> bool: return m.zones().has(l) and m.crossing_open(z, l)):
					continue
			"bell":
				if not m.groups_in_zone(z).any(func(g: Dictionary) -> bool: return String(g.kind) == "cultists"):
					continue
		zs.append(z)
	if zs.is_empty() and kind == "bell":
		for z: String in WorldModel._sorted(m.zones().keys()):
			if z != m.hosted and not (m.zone(z).get("places", []) as Array).is_empty():
				zs.append(z)
	if zs.is_empty():
		return ""
	return String(zs[rng.randi_range(0, zs.size() - 1)])


## Starts an event of `kind` in zone `z` (opts: "place" (a place id), "to" (a storm's or convoy's
## other zone), "by_player" (a bell rung by a player: "who" names him), "column"). Returns the record.
static func begin(m: WorldModel, kind: String, z: String, opts := {}, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = m.rng_for("world", "event_%s_%s" % [kind, z])
	var def := kind_def(kind)
	var zd := m.zone(z)
	if zd.is_empty() or def.is_empty():
		return {}
	var places: Array = zd.get("places", [])
	var place: Dictionary = {}
	if opts.has("place"):
		place = WorldRegions.place(zd, String(opts.place))
	if place.is_empty() and not places.is_empty():
		place = places[rng.randi_range(0, places.size() - 1)]
	var pv := WorldModel._place_v(place)
	var rec := {"kind": kind, "zone": z, "place": String(place.get("id", "")), "t": snappedf(m.now, 0.0001),
		"until": snappedf(m.now + float(def.get("window_h", 12.0)) / 24.0, 0.0001), "state": "open", "outcome": "", "spawned": false}
	var fill := {"place": WorldModel._place_name(place), "zone": String(zd.get("name", z)), "to": "", "group": "", "column": "", "who": String(opts.get("who", "someone"))}
	var gids: Array = []
	var text := String(def.get("text", kind))
	var pressure := float(def.get("pressure", 0.0))
	match kind:
		"supply_drop":
			place["richness"] = float(def.get("richness", 3.0))
			place["looted"] = -100.0
			rec["racers"] = []
		"convoy":
			var links: Array = (zd.get("links", []) as Array).filter(func(l: String) -> bool: return m.zones().has(l))
			var to := String(opts.get("to", ""))
			if to == "" and not links.is_empty():
				to = String(links[rng.randi_range(0, links.size() - 1)])
			var enclave := m.group(String((m.w.get("goal", {}) as Dictionary).get("evac_group", "")))
			var column := String(opts.get("column", ""))
			if column == "":
				column = "enclave" if not enclave.is_empty() and bool(enclave.get("alive", false)) and rng.randf() < 0.5 else "trader"
			rec["to"] = to
			rec["column"] = column
			rec["group"] = String(enclave.get("id", "")) if column == "enclave" else ""
			fill.to = String(m.zone(to).get("name", to))
			fill.column = column
		"heli_down":
			rec["crew"] = []
			for i in int(def.get("crew", 2)):
				var g := m.new_lone(z, m._place_pos(place, rng, 15.0), rng, "crew of a helicopter down by %s" % WorldModel._place_name(place))
				var pid := String(g.get("leader", ""))
				if m.people.has(pid):
					(m.people[pid] as Dictionary)["heli_crew"] = true
				(rec.crew as Array).append(pid)
		"bell":
			if bool(opts.get("by_player", false)):
				text = String(def.get("player_text", text))
				gids.append("player")
				pressure = 0.0  # (the live zone's: server_ring raises it where the bell is)
			else:
				for g: Dictionary in m.groups_in_zone(z):
					if String(g.kind) == "cultists":
						gids.append(String(g.id))
						fill.group = String(g.name)
						text = String(def.get("cult_text", text))
						break
		"burning":
			place["richness"] = snappedf(float(place.get("richness", 1.0)) * float(def.get("richness_mult", 0.5)), 0.01)
		"storm":
			var to := String(opts.get("to", ""))
			if to == "":
				for l: String in zd.get("links", []):
					if m.zones().has(l) and m.crossing_open(z, l):
						to = l
						break
			if to == "":
				return {}
			var cr: Dictionary = m.w.get("crossings", {})
			cr[WorldModel.crossing_key(z, to)] = "storm"
			m.w["crossings"] = cr
			rec["to"] = to
			rec["crossing"] = WorldModel.crossing_key(z, to)
			fill.to = String(m.zone(to).get("name", to))
	if pressure > 0.0:
		m.raise_pressure(z, pressure, pv)
	var e := m.event(z, kind, gids, text.format(fill), String(rec.place))
	rec["id"] = int(e.id)
	if bool(opts.get("by_player", false)):
		e["actor"] = String(opts.get("profile", ""))
	records(m.w)[str(rec.id)] = rec
	match kind:
		"supply_drop":
			_race(m, rec)
			_broadcast(m, rec, String(def.get("broadcast", "")), fill)
		"heli_down":
			_broadcast(m, rec, String(def.get("broadcast", "")), fill)
	return rec


## Every group in reach of a supply drop (not the enclave's, not lone survivors or live ones) races
## for it: a forage goal at its place.
static func _race(m: WorldModel, rec: Dictionary) -> void:
	for g: Dictionary in m.alive_groups():
		if String(g.kind) in ["lone", "enclave"] or bool(g.get("live", false)):
			continue
		if not String(rec.zone) in WorldGoals.reach(m, g):
			continue
		g.goal = {"kind": "forage", "zone": String(rec.zone), "place": String(rec.place), "target": "", "gain": 1.2, "need": 1.0, "loss": 0.0,
			"noise": 0.0, "rel": 0.0, "bias": 0.3, "score": 1.5, "since": m.tick(), "phase": "go", "work": 0, "event": int(rec.id)}
		g.journey = {}
		(rec.racers as Array).append(String(g.id))


## The enclave's broadcast about `rec` (an event of kind "broadcast": the radio's enclave channel).
static func _broadcast(m: WorldModel, rec: Dictionary, text: String, fill: Dictionary) -> void:
	if text == "":
		return
	var gid := String((m.w.get("goal", {}) as Dictionary).get("evac_group", ""))
	var enclave := m.group(gid)
	if enclave.is_empty() or not bool(enclave.get("alive", false)):
		return
	m.event(String(rec.zone), "broadcast", [gid], text.format(fill), String(rec.place))


# --- The window (worker-safe) ---------------------------------------------------------------------

## Every far tick (WorldModel.step): open events resolve: a drop taken or lapsed, a convoy ambushed
## or through, a crew recovered or lost, a fire out, a storm passed; old records forgotten.
static func tick(m: WorldModel) -> void:
	var recs := records(m.w)
	if recs.is_empty():
		return
	for k: String in WorldModel._sorted(recs.keys()):
		var r: Dictionary = recs[k]
		if String(r.get("state", "")) != "open":
			if m.now - float(r.get("until", m.now)) > FORGET_DAYS:
				recs.erase(k)
			continue
		var def := kind_def(String(r.kind))
		var zd := m.zone(String(r.zone))
		var fill := {"zone": String(zd.get("name", r.zone)), "to": String(m.zone(String(r.get("to", ""))).get("name", r.get("to", ""))),
			"column": String(r.get("column", "")), "group": "", "place": m.place_name(String(r.zone), String(r.place))}
		var place := WorldRegions.place(zd, String(r.place))
		match String(r.kind):
			"supply_drop":
				if not place.is_empty() and float(place.get("looted", -100.0)) > float(r.t):
					var who := _group_at(m, String(r.zone), place)
					fill.group = String(who.get("name", "Someone"))
					_end(m, r, "taken", "supply_taken", String(def.get("taken", "")).format(fill), [String(who.get("id", ""))] if not who.is_empty() else [])
					place["richness"] = 1.0
				elif m.now >= float(r.until):
					_end(m, r, "lapsed", "supply_lapsed", String(def.get("lapsed", "")).format(fill), [])
					if not place.is_empty():
						place["richness"] = 1.0
			"convoy":
				if m.now >= float(r.until):
					_resolve_convoy(m, r, def, fill)
			"heli_down":
				if m.now >= float(r.until):
					var out_there := (r.get("crew", []) as Array).filter(func(pid: String) -> bool: return String((m.people.get(pid, {}) as Dictionary).get("status", "")) == "out_there")
					if not out_there.is_empty():
						_end(m, r, "recovered", "heli_recovered", String(def.get("recovered", "")).format(fill), [])
					else:
						_end(m, r, "lost", "heli_lost", String(def.get("lost", "")).format(fill), [])
			"burning":
				if m.now >= float(r.until):
					_end(m, r, "out", "fire_out", String(def.get("out", "")).format(fill), [])
			"storm":
				if m.now >= float(r.until):
					_end(m, r, "passed", "storm_passed", String(def.get("passing", "")).format(fill), [])
			_:
				if m.now >= float(r.until):
					r.state = "done"
					r.outcome = "over"


static func _end(m: WorldModel, r: Dictionary, outcome: String, kind: String, text: String, gids: Array) -> void:
	r.state = "done"
	r.outcome = outcome
	if text != "":
		m.event(String(r.zone), kind, gids.filter(func(g: String) -> bool: return g != ""), text, String(r.place))


## The group standing at `place` in zone `z` (the one that foraged it), else {}.
static func _group_at(m: WorldModel, z: String, place: Dictionary) -> Dictionary:
	var pv := WorldModel._place_v(place)
	for g: Dictionary in m.groups_in_zone(z):
		var p: Array = g.get("pos", [0.0, 0.0])
		if Vector2(float(p[0]), float(p[1])).distance_to(pv) < 5.0 and String(g.kind) != "lone":
			return g
	return {}


## A convoy's window ends: raiders in reach ambush it (ambush_chance), else it passes and the
## settlers it passed traded with it (trade_share of a day's food and water).
static func _resolve_convoy(m: WorldModel, r: Dictionary, def: Dictionary, fill: Dictionary) -> void:
	var rng := m.rng_for("convoy%d" % int(r.id), "ambush")
	var near: Array = [String(r.zone)] + (m.zone(String(r.zone)).get("links", []) as Array)
	var raiders: Array = m.groups_near(near).filter(func(g: Dictionary) -> bool: return String(g.kind) == "raiders" and not bool(g.get("live", false)))
	if not raiders.is_empty() and rng.randf() < float(def.get("ambush_chance", 0.35)):
		var g: Dictionary = raiders[rng.randi_range(0, raiders.size() - 1)]
		fill.group = String(g.name)
		for k: String in ["food", "ammo", "fuel"]:
			if k in WorldGroup.SUPPLY_KEYS:
				WorldGroup.add_supply(g, k, 4.0)
		var col := m.group(String(r.get("group", "")))
		if not col.is_empty():
			(col.relations as Dictionary)[String(g.id)] = float((col.relations as Dictionary).get(String(g.id), 0.0)) - 30.0
		_end(m, r, "ambushed", "convoy_ambushed", String(def.get("ambushed", "")).format(fill), [String(g.id)])
		return
	for g: Dictionary in m.groups_in_zone(String(r.zone)):
		if String(g.kind) in ["settlers", "scavengers"]:
			for k: String in ["food", "water"]:
				if k in WorldGroup.SUPPLY_KEYS:
					WorldGroup.add_supply(g, k, float(def.get("trade_share", 0.5)) * WorldGroup.size(g))
	_end(m, r, "passed", "convoy_passed", String(def.get("passed", "")).format(fill), [])


# --- The main thread: the live zone ---------------------------------------------------------------

## Host, a zone is up (Survival._world_level_ready): the data warmed for the worker (the live pieces
## come once the zone's save is loaded: SurvivalLevel._on_hosted calls server_live).
static func server_level_ready(_level: Node) -> void:
	data()


## Host, after every far step (WorldSim._after_step): the world option's frequency, the live pieces,
## the sky's glow.
static func server_after_step(_m: WorldModel = null) -> void:
	WorldSim.section()["event_mult"] = float((data().get("world_mult", {}) as Dictionary).get(Survival.option("world"), 1.0))
	var level := CompoundLevel.current(Survival)
	if level is SurvivalLevel:
		server_live(level)
		apply_glow(level)


## Host: the live pieces of the open (or once spawned) events in the hosted zone: a cache for a drop,
## a wreck or a convoy's wagon; the bell ringing (a lure); the fire lit. Each once a level.
static func server_live(level: Node) -> void:
	if not level is SurvivalLevel or not level.multiplayer.is_server() or not level.has_meta(&"fallen_hosted"):
		return
	var zone := WorldSim.hosted_zone()
	var done: Dictionary = _live.get(level.get_instance_id(), {})
	_live[level.get_instance_id()] = done
	for r: Dictionary in records(WorldSim.section()).values():
		if String(r.zone) != zone or done.has(int(r.id)):
			continue
		var is_open := String(r.state) == "open"
		if not is_open and not bool(r.get("spawned", false)):
			continue
		done[int(r.id)] = true
		var at := _place_pos3(level as SurvivalLevel, r)
		match String(r.kind):
			"supply_drop", "heli_down", "convoy":
				if is_open or bool(r.get("spawned", false)):
					_spawn_cache(level as SurvivalLevel, r, at)
			"bell":
				if is_open:
					ring_lure(at, float(kind_def("bell").get("ring_s", 90.0)) * clampf((float(r.until) - WorldSim.world_now()) * 24.0, 0.1, 1.0), int(r.id))
			"burning":
				if is_open:
					Wildfire.server_ignite(level, at, "a town burning")


## Where a record's place is on the live ground.
static func _place_pos3(level: SurvivalLevel, r: Dictionary) -> Vector3:
	var zd: Dictionary = (WorldSim.section().get("zones", {}) as Dictionary).get(String(r.zone), {})
	var pv := WorldModel._place_v(WorldRegions.place(zd, String(r.place)))
	var off := Vector3(3.0, 0.0, 2.0)  # (beside the place's middle, not on its door)
	return level.ground_point(Vector3(pv.x, 0.0, pv.y) + off)


static func cache_uid(id: int) -> String:
	return "%s%d" % [CACHE_PREFIX, id]


## The live cache of event `r` at `at` (its loot rolled from the event's id; the zone save keeps it).
static func _spawn_cache(level: SurvivalLevel, r: Dictionary, at: Vector3) -> WorldCache:
	if level.cache_spawner == null:
		return null
	var uid := cache_uid(int(r.id))
	for c: Node in level.get_tree().get_nodes_in_group(WorldCache.GROUP):
		if String(c.get(&"uid")) == uid:
			return c as WorldCache
	var def := kind_def(String(r.kind))
	var cache := level.cache_spawner.spawn({"uid": uid, "pos": at, "yaw": 0.0, "label": String(def.get("label", "Cache"))}) as WorldCache
	if cache:
		cache.set_meta(&"fallen_event", int(r.id))
		cache.server_fill(loot_for(r))
		r["spawned"] = true
	return cache


## Event `r`'s loot: `rolls` picks of its kind's loot rows, counts rolled; the same every time.
static func loot_for(r: Dictionary) -> Array:
	var def := kind_def(String(r.kind))
	var rows: Array = def.get("loot", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([WorldSim.world_seed(), int(r.get("id", 0)), "loot"])
	var got := {}
	for i in int(def.get("rolls", 0)):
		if rows.is_empty():
			break
		var row: Array = rows[rng.randi_range(0, rows.size() - 1)]
		if not ItemDB.has_item(StringName(String(row[0]))):
			continue
		got[String(row[0])] = int(got.get(String(row[0]), 0)) + rng.randi_range(int(row[1]), int(row[2]) if row.size() > 2 else int(row[1]))
	var out: Array = []
	for id: String in WorldModel._sorted(got.keys()):
		out.append({"id": id, "count": int(got[id])})
	return out


## Host: a lure ringing at `at` for `seconds` (Lures' lasting noises; the bell's numbers).
static func ring_lure(at: Vector3, seconds: float, event_id := 0) -> void:
	var def := kind_def("bell")
	var now := Soldier._now()
	Lures.active.append({"kind": BELL_LURE, "at": at, "until": now + seconds, "every": float(def.get("ring_every_s", 6.0)), "next": now,
		"radius": float(def.get("ring_m", 220.0)), "loud": 0.8, "pressure": 1.5, "piece": -1, "event": event_id})


## Host: `actor` rings a bell at `at` (FallenBell): the dead hear it far (a lure for ring_s), the
## zone's pressure up, an event with the actor's profile ("bell", the player's), a journal line,
## the companions' memory of who did it. Returns the line.
static func server_ring(level: Node, actor: Soldier, at: Vector3, place_name := "the church") -> String:
	var def := kind_def("bell")
	ring_lure(at, float(def.get("ring_s", 90.0)))
	if level is ZoneLevel:
		Survival._raise_pressure(level, at, float(def.get("player_pressure", 18.0)))
	var who := Survival.survivor_name(actor) if actor else "Someone"
	var profile := Survival.profile_of(actor) if actor else ""
	var zone := WorldSim.hosted_zone()
	var out := {}
	var fn := func(w: Dictionary) -> void:
		var m := WorldModel.new(w, WorldSim.people(), WorldSim.pressure_section(), WorldSim.world_seed())
		m.now = WorldSim.world_now()
		m.hosted = zone
		out.clear()
		out.merge(begin(m, "bell", zone, {"by_player": true, "who": who, "profile": profile, "place": _nearest_place(zone, at)}), true)
	var sim := WorldSim.get_sim()
	if sim and zone != "":
		sim.mutate(fn)
	elif zone != "":
		fn.call(WorldSim.section())
	var text := String(def.get("player_text", "{who} rang the bell")).format({"who": who, "place": place_name, "zone": RegionMap.zone_name(zone) if zone != "" else ""})
	Intel.journal(_cap(text) + ".", "event", who)
	if actor:
		CoopFallen.server_deed(actor, "rang the bell and called the dead", -3.0)
	if not out.is_empty():
		var e := Intel.event_by_id(int(out.get("id", 0)))
		if not e.is_empty():
			e["actor"] = profile
			if sim:
				sim.event_added.emit(e)
	return text


static func _nearest_place(zone: String, at: Vector3) -> String:
	var zd: Dictionary = (WorldSim.section().get("zones", {}) as Dictionary).get(zone, {})
	var best := ""
	var best_d := INF
	for p: Dictionary in zd.get("places", []):
		var d := WorldModel._place_v(p).distance_to(Vector2(at.x, at.z))
		if d < best_d:
			best_d = d
			best = String(p.id)
	return best


## Host: a live event cache was opened by `actor` for the first time (LootStates): a drop claimed
## by the players (the enclave's standing -5: it was theirs), a convoy's wagon robbed (its column's
## group -30 and an event with the actor), the crew's wreck searched.
static func server_cache_opened(cache: WorldCache, actor: Soldier) -> void:
	var id := int(cache.get_meta(&"fallen_event", String(cache.uid).trim_prefix(CACHE_PREFIX).to_int()))
	var r := record(WorldSim.section(), id)
	if r.is_empty() or String(r.state) != "open":
		return
	var sim := WorldSim.get_sim()
	var profile := Survival.profile_of(actor) if actor else ""
	match String(r.kind):
		"supply_drop":
			r.state = "done"
			r.outcome = "players"
			r["by"] = profile
			var gid := String((WorldSim.section().get("goal", {}) as Dictionary).get("evac_group", ""))
			if sim and gid != "":
				sim.server_change_relation(gid, -5.0, "took the supply drop")
			Intel.journal("We got to the supply drop first.", "event")
			if actor:
				CoopFallen.server_deed(actor, "got us the supply drop", 3.0)
		"convoy":
			r.state = "done"
			r.outcome = "robbed"
			r["by"] = profile
			var gid := String(r.get("group", ""))
			if sim and gid != "":
				sim.server_change_relation(gid, -30.0, "robbed the convoy")
			var def := kind_def("convoy")
			var e := Intel.server_event(String(r.zone), "convoy_robbed", ["player"] + ([gid] if gid != "" else []),
				String(def.get("robbed", "")).format({"column": String(r.get("column", "")), "zone": RegionMap.zone_name(String(r.zone))}), String(r.place))
			var stored := Intel.event_by_id(int(e.get("id", 0)))
			if not stored.is_empty():
				stored["actor"] = profile
			if actor:
				CoopFallen.server_deed(actor, "robbed a convoy", -4.0)


# --- The sky's glow (a far town burning) -----------------------------------------------------------

## How bright the glow of the open burning events is from `zone` (0-1): 1 / (1 + links away), within
## glow_links.
static func glow(zone: String) -> float:
	var zones: Dictionary = WorldSim.section().get("zones", {})
	var best := 0.0
	var reach := int(kind_def("burning").get("glow_links", 2))
	for r: Dictionary in open(WorldSim.section(), "burning"):
		var d := WorldRegions.distance(zones, zone, String(r.zone)) if zone != "" else -1
		if d >= 0 and d <= reach:
			best = maxf(best, 1.0 / (1.0 + d))
	return best


## Host: the glow onto DayNight (its "glow" meta: the horizon leans orange that much, at night most).
static func apply_glow(_level: Node) -> float:
	var g := glow(WorldSim.hosted_zone())
	Survival.state()["sky_glow"] = snappedf(g, 0.01)
	var dn := DayNight.current()
	if dn:
		dn.set_meta(GLOW_META, g * (0.25 + 0.75 * DayNight.night_of(Survival.hour())))
	return g


static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s
