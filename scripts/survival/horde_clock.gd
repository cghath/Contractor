class_name HordeClock
extends RefCounted
## Hordes on their own clock (docs/survival_world.md section 5, "Hordes on their own clock"): towns
## and nests send the dead out on a schedule, whatever the noise. The rules are pure and run inside
## WorldModel's far tick, so they're deterministic with the world seed and travel with the world
## section (saved, far from the players, and through the catch-up):
##
## - Every zone has a due tick (zd.clock_due), rolled from its rate: rate() is how much it has to
##   send (its towns and villages, its nests while they stand), its type's density, how many of its
##   dead are left, the season and the "living world" option. A zone with nothing to send has none.
## - When it falls due and the zone has no horde (and the first night is over: FirstHour's
##   softness) a horde sets out in zd.horde with "clock": true, so it's the same record the noise's
##   far hordes keep: Holding, enclave convoys and WorldFights read it unchanged, it just doesn't
##   need the zone to be loud. It walks link to link (HOPS, WALK_TICKS a hop, the louder neighbour
##   and the players' zone likelier); out of hops it drops the clock and the noise's rule thins it.
## - Near a played zone it's real: walking at the hosted zone, or rising in it, the host warns first
##   (action "horde_warn": a journal line, a message, distant groans on every peer, WARN_TICKS
##   ahead), then "horde_enter" (or "horde_rise" in the zone) makes ZoneDead's horde: server_march
##   puts it down at the crossing or its source, at least START_MIN_M from anyone, and walks it at
##   the settlement or the players. A marching head doesn't thin until it has got there.
## Saving: everything is in the world section; a horde on the ground when the world is saved is
## counted into zd.horde_out and walks again on Continue (with a warning, as a horde that was never
## seen does). Every number here is Proposed.

## A place's draw, by its base type (per place), and a nest's, per NEST_FULL heads of it.
const SOURCE_X := {"town": 2.0, "village": 1.0}
const NEST_X := 0.6
const NEST_FULL := 10.0
## Hordes a world day at one unit of source and a density-1 zone, before the season and the option.
const BASE_PER_DAY := 0.08
## A zone sends at most this many a day, however big.
const MAX_PER_DAY := 1.0
const SEASON_X := {"spring": 1.2, "summer": 1.0, "autumn": 1.1, "winter": 0.5}
## The first one rolls this share of a gap (so the map doesn't send them all at once); later gaps
## this spread of the rate's own.
const FIRST_ROLL := Vector2(0.3, 1.0)
const GAP_ROLL := Vector2(0.7, 1.3)
## A zone with nothing to send looks again this often (days).
const RECHECK_DAYS := 2.0
## How many walk out, before the zone's density and the "dead" option; smaller than the noise's.
const N := Vector2i(20, 45)
const MIN_N := 8
## Hops it walks (zones), far ticks a hop (WorldModel.TICK_MIN each: three world hours), and how long
## the warning runs before it arrives (two world hours; 4 minutes real at DAY_MIN 48).
const HOPS := Vector2i(1, 3)
const WALK_TICKS := 12
const WARN_TICKS := 8
## Neighbours: the weight per 25 of its pressure, and the players' zone's extra.
const PRESSURE_PULL := 25.0
const HOSTED_PULL := 1.0
## Where it's put down: at least this far from anyone; heads within SPREAD_M of it.
const START_MIN_M := 300.0
const SPREAD_M := 30.0
## A horde on the ground at save, walked again on Continue if the save is no older than this (days).
const OUT_KEEP_DAYS := 1.0
const SOFT_END_DAY := 2.0 + FirstHour.FIRST_NIGHT_END_H / 24.0


## The main thread's snapshot of the options for WorldModel.clock: {"world_x", "size_x", "soft"}.
## (An empty clock turns the rules off: the suites that build a bare WorldModel.)
static func options() -> Dictionary:
	return {"world_x": Survival.option_mult("world"), "size_x": Survival.option_mult("dead"), "soft": FirstHour.softened()}


# --- The rules (WorldModel's far tick) ------------------------------------------------------------

## What `zd` (a zone record) has to send: its towns and villages, and its nests while they stand.
static func sources(zd: Dictionary) -> float:
	var sum := 0.0
	var nests := 0.0
	for p: Dictionary in zd.get("places", []):
		var base := String(p.get("type", ""))
		sum += float(SOURCE_X.get(base, 0.0))
		if DeadNests.NEST_SITES.has(base):
			nests += float(DeadNests.NEST_SITES[base]) / NEST_FULL
	return sum + nests * NEST_X * clampf(float(zd.get("nests_left", 1.0)), 0.0, 1.0)


## Hordes a world day from `zd` in `season` at `world_x`: its sources x its type's density x how many
## of its dead are left x the season x the option, capped at MAX_PER_DAY. 0 where it has no source.
static func rate(zd: Dictionary, season: String, world_x: float) -> float:
	var s := sources(zd)
	if s <= 0.0:
		return 0.0
	var type_x := float(WorldRegions.type_def(String(zd.get("type", ""))).get("dead", 0.5))
	var left := clampf(float(zd.get("dead", 1.0)), 0.0, 1.0)
	return minf(BASE_PER_DAY * s * type_x * left * float(SEASON_X.get(season, 1.0)) * world_x, MAX_PER_DAY)


## Whether the clock may send one now: the first night's softness (FirstHour.horde_allowed), from
## `m`'s own time so a worker reads nothing live.
static func allowed(m: WorldModel) -> bool:
	if not bool(m.clock.get("soft", true)):
		return true
	return m.now >= SOFT_END_DAY


## One far tick of zone `z`'s clock (WorldModel._zone_tick, before it skips the hosted zone): the
## schedule, a horde setting out, and a horde in the hosted zone going live (warned, then risen).
static func tick(m: WorldModel, z: String) -> void:
	if m.clock.is_empty():
		return
	var zd: Dictionary = m.zones()[z]
	if not zd.has("clock_due"):
		_schedule(m, z, zd, true)
	elif m.tick() >= int(zd.clock_due):
		_schedule(m, z, zd, false)
		if (zd.get("horde", {}) as Dictionary).is_empty() and allowed(m):
			_form(m, z, zd)
	var horde: Dictionary = zd.get("horde", {})
	if z == m.hosted and bool(horde.get("clock", false)):
		_hosted(m, z, zd, horde)


static func _schedule(m: WorldModel, z: String, zd: Dictionary, first: bool) -> void:
	var rng := m.rng_for(z, "clock_gap")
	var r := rate(zd, m.season(), float(m.clock.get("world_x", 1.0)))
	var days := RECHECK_DAYS
	if r > 0.0:
		days = 1.0 / r * (rng.randf_range(FIRST_ROLL.x, FIRST_ROLL.y) if first else rng.randf_range(GAP_ROLL.x, GAP_ROLL.y))
	var ticks := maxi(1, roundi(days * WorldModel.TICKS_PER_DAY))
	if first and bool(m.clock.get("soft", true)):
		ticks += maxi(0, ceili((SOFT_END_DAY - m.now) * WorldModel.TICKS_PER_DAY))
	zd["clock_due"] = m.tick() + ticks


static func _form(m: WorldModel, z: String, zd: Dictionary) -> void:
	var r := rate(zd, m.season(), float(m.clock.get("world_x", 1.0)))
	if r <= 0.0:
		return
	var rng := m.rng_for(z, "clock")
	var place := _pick_source(zd, rng)
	var n := maxi(MIN_N, roundi(rng.randi_range(N.x, N.y) * float(m.clock.get("size_x", 1.0)) * clampf(float(zd.get("dead", 1.0)), 0.3, 1.0)))
	zd.horde = {"n": n, "since": m.tick(), "clock": true, "hops": rng.randi_range(HOPS.x, HOPS.y), "to": "", "arrive": 0, "warned": false, "place": String(place.get("id", ""))}
	var where := WorldModel._place_name(place) if not place.is_empty() else String(zd.get("name", z))
	if z == m.hosted:
		m.event(z, "horde_stir", [], "the dead are gathering at %s" % where, String(place.get("id", "")))  # (the warning's line tells it here)
	else:
		m.event(z, "horde", [], "the dead are walking out of %s" % where, String(place.get("id", "")))


## A source place of `zd`, weighted by what it sends ({} when none).
static func _pick_source(zd: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	var picks: Array = []
	for p: Dictionary in zd.get("places", []):
		var base := String(p.get("type", ""))
		var w := float(SOURCE_X.get(base, 0.0))
		if DeadNests.NEST_SITES.has(base):
			w += float(DeadNests.NEST_SITES[base]) / NEST_FULL * NEST_X
		if w > 0.0:
			picks.append([p, w])
			total += w
	var roll := rng.randf() * total
	for pick: Array in picks:
		roll -= float(pick[1])
		if roll <= 0.0:
			return pick[0]
	return picks[-1][0] if not picks.is_empty() else {}


## A clock horde in the hosted zone (one that set out here, or was walking through when the players
## came): warned once, then risen WARN_TICKS later as ZoneDead's.
static func _hosted(m: WorldModel, z: String, zd: Dictionary, horde: Dictionary) -> void:
	if not bool(horde.get("warned", false)):
		horde.warned = true
		horde.arrive = m.tick() + WARN_TICKS
		m.actions.append({"kind": "horde_warn", "zone": z, "from": "", "place": String(horde.get("place", "")), "n": int(horde.n)})
		return
	if m.tick() < int(horde.get("arrive", 0)):
		return
	zd.horde = {}
	m.actions.append({"kind": "horde_rise", "zone": z, "from": "", "place": String(horde.get("place", "")), "n": int(horde.n)})


## One far tick of a clock horde in a far zone (WorldModel._zone_tick): where it's bound, the
## warning when that's the hosted zone, arriving; out of hops it drops the clock (the noise's rule
## thins it).
static func walk(m: WorldModel, z: String, horde: Dictionary) -> void:
	var zd: Dictionary = m.zones()[z]
	var to := String(horde.get("to", ""))
	if to == "":
		if int(horde.get("hops", 0)) <= 0:
			horde.erase("clock")
			return
		to = _next_zone(m, z, zd)
		if to == "":
			horde.hops = 0
			return
		horde.to = to
		horde.arrive = m.tick() + WALK_TICKS
		horde.hops = int(horde.hops) - 1
		horde.warned = false
	if to == m.hosted and not bool(horde.get("warned", false)):
		horde.warned = true
		horde.arrive = maxi(int(horde.arrive), m.tick() + WARN_TICKS)
		m.actions.append({"kind": "horde_warn", "zone": to, "from": z, "place": "", "n": int(horde.n)})
	if m.tick() < int(horde.get("arrive", 0)):
		return
	var nd := m.zone(to)
	zd.horde = {}
	if to == m.hosted:
		m.actions.append({"kind": "horde_enter", "zone": to, "from": z, "n": int(horde.n), "clock": true})
	else:
		var there: Dictionary = nd.get("horde", {})
		if there.is_empty():
			nd.horde = {"n": int(horde.n), "since": m.tick(), "clock": true, "hops": int(horde.hops), "to": "", "arrive": 0, "warned": false, "place": ""}
		else:
			there.n = int(there.n) + int(horde.n)
	m.event(to, "horde_moved", [], "a horde walked over from %s into %s" % [String(zd.get("name", z)), String(nd.get("name", to))])


## The neighbour a clock horde walks to: open crossings to a zone with no horde, weighted by its
## pressure and for the players' zone ("" when none).
static func _next_zone(m: WorldModel, z: String, zd: Dictionary) -> String:
	var rng := m.rng_for(z, "clock_way")
	var total := 0.0
	var picks: Array = []
	for nb: String in zd.get("links", []):
		if not m.crossing_open(z, nb) or not (m.zone(nb).get("horde", {}) as Dictionary).is_empty():
			continue
		var w := 1.0 + m.pressure_of(nb) / PRESSURE_PULL + (HOSTED_PULL if nb == m.hosted else 0.0)
		picks.append([nb, w])
		total += w
	var roll := rng.randf() * total
	for pick: Array in picks:
		roll -= float(pick[1])
		if roll <= 0.0:
			return String(pick[0])
	return String(picks[-1][0]) if not picks.is_empty() else ""


# --- The host's side (WorldSim's actions, the level, the save) ------------------------------------

## Host: a horde is coming (action "horde_warn"): the journal, a message to every player, and the
## distant groans on every peer (ZoneDead.server_warn).
static func server_warn(level: SurvivalLevel, a: Dictionary) -> void:
	var text := ""
	if String(a.get("from", "")) != "":
		text = "Groans on the wind from %s: the dead are walking this way" % RegionMap.zone_name(String(a.from))
	else:
		text = "Something has stirred the dead at %s: they're walking out" % _place_words(level, String(a.get("place", "")))
	Survival._journal_line(text + ".")
	for p: Soldier in MapNodes.players(level):
		Survival._tell(p, text)
	var crowd := ZoneDead.of(level)
	if crowd:
		crowd.server_warn(_start_point(level, a), float(WARN_TICKS) * WorldModel.TICK_MIN / 1440.0 * Survival.DAY_MIN * 60.0)
	SessionLog.note("survival world: warned of a horde of %d (%s)" % [int(a.get("n", 0)), text])


## Host: a clock horde goes live (actions "horde_enter" with "clock", "horde_rise"): `a.n` of the
## crowd put down at its source and walked at where the people are. Returns the heads made.
static func server_rise(level: SurvivalLevel, a: Dictionary) -> int:
	var crowd := ZoneDead.of(level)
	if crowd == null:
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([WorldSim.world_seed(), String(a.zone), WorldSim.world_now(), "horde_rise"])
	var from := level.ground_point(_start_point(level, a))
	var to := _march_point(level, rng)
	var made := crowd.server_march(from, to, int(a.get("n", 0)))
	SessionLog.note("survival world: a horde of %d on the clock walks at (%.0f, %.0f) from (%.0f, %.0f)" % [made, to.x, to.z, from.x, from.z])
	return made


## Where a clock horde is put down: its source place or the crossing it comes by, else the site
## farthest from the players; never within START_MIN_M of one if anywhere is farther.
static func _start_point(level: ZoneLevel, a: Dictionary) -> Vector3:
	var picks: Array[Vector3] = []
	var from := String(a.get("from", ""))
	if from != "":
		for c: Dictionary in RegionMap.crossings(String(a.zone), level.def):
			if String(c.to) == from:
				picks.append(Vector3(float(c.pos[0]), 0.0, float(c.pos[1])))
	var place := String(a.get("place", ""))
	for m: ZoneModule in level.modules():
		if m.module_id == place:
			picks.push_front(m.global_position)
		else:
			picks.append(m.global_position)
	if picks.is_empty():
		return Vector3.ZERO
	var players := MapNodes.players(level).filter(func(p: Soldier) -> bool: return p.vitals.is_up())
	var best := picks[0]
	var best_d := -1.0
	for at: Vector3 in picks:
		var d := INF
		for p: Soldier in players:
			d = minf(d, Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length())
		if d >= START_MIN_M:
			return at
		if d > best_d:
			best_d = d
			best = at
	return best


## Where the horde walks: the settlement if this zone has it, else a player, a little off him.
static func _march_point(level: SurvivalLevel, rng: RandomNumberGenerator) -> Vector3:
	var st := Settlement.find(level)
	if st != null and st.hosted():
		return Settlement.pos()
	var players := MapNodes.players(level).filter(func(p: Soldier) -> bool: return p.vitals.is_up())
	if players.is_empty():
		return Vector3.ZERO
	var p: Soldier = players[rng.randi_range(0, players.size() - 1)]
	return p.global_position + Vector3(rng.randf_range(-30.0, 30.0), 0.0, rng.randf_range(-30.0, 30.0))


static func _place_words(level: ZoneLevel, place: String) -> String:
	for m: ZoneModule in level.modules():
		if m.module_id == place:
			return "the " + ZoneModules.base(String(m.type)).replace("_", " ")
	return "the far side of the zone"


## Host, each far tick's main-thread end (WorldSim._after_step): how much of the hosted zone's
## nests still stands, for its rate (a cleared one sends nothing until it refills).
static func server_after_step(m: WorldModel) -> void:
	if m.clock.is_empty() or m.hosted == "":
		return
	var cap := 0
	var standing := 0
	for rec: Dictionary in DeadNests.all().values():
		cap += int(rec.get("cap", 0))
		if not (bool(rec.get("cleared", false)) and int(rec.get("n", 0)) <= 0 and int(rec.get("inside", 0)) <= 0):
			standing += int(rec.get("cap", 0))
	var zd: Dictionary = (WorldSim.section().get("zones", {}) as Dictionary).get(m.hosted, {})
	if cap > 0 and not zd.is_empty():
		zd["nests_left"] = snappedf(float(standing) / cap, 0.01)


## Host, on every save (Survival.server_save): the marching heads on the ground, as a record: a
## save and Continue doesn't lose them (server_level_ready walks them again).
static func server_note_out(level: SurvivalLevel) -> void:
	var zone := WorldSim.hosted_zone()
	var zd: Dictionary = (WorldSim.section().get("zones", {}) as Dictionary).get(zone, {})
	var crowd := ZoneDead.of(level)
	if zd.is_empty() or crowd == null:
		return
	var n := crowd.dead.filter(func(d: Dictionary) -> bool: return bool(d.alive) and d.has("march")).size()
	if n > 0:
		zd["horde_out"] = {"n": n, "day": WorldSim.world_now()}
	else:
		zd.erase("horde_out")


## Host, the level up (Survival.server_level_ready, after the world's set up): a horde saved on the
## ground walks again, warned.
static func server_level_ready(level: SurvivalLevel) -> void:
	var zone := WorldSim.hosted_zone()
	var zd: Dictionary = (WorldSim.section().get("zones", {}) as Dictionary).get(zone, {})
	var out: Dictionary = zd.get("horde_out", {})
	if out.is_empty():
		return
	zd.erase("horde_out")
	if WorldSim.world_now() - float(out.get("day", 0.0)) > OUT_KEEP_DAYS or not (zd.get("horde", {}) as Dictionary).is_empty():
		return
	zd.horde = {"n": int(out.get("n", 0)), "since": int(WorldSim.section().get("tick", 0)), "clock": true, "hops": 1, "to": "", "arrive": 0, "warned": false, "place": ""}
	SessionLog.note("survival world: a saved horde of %d walks again in %s" % [int(out.get("n", 0)), level.def.get("id", "")])
