class_name WorldSim
extends Node
## The living world of Contractor: Fallen (docs/survival_world.md sections 2-5, 9, 11-13; calls
## 20-24, 36, 44, 52, 67): host-authoritative, a child of the Survival autoload ("WorldSim").
##
## - The world's state is Survival.state()["world"] (WorldModel's: groups, zones with their
##   places, holders, traces and far hordes, events, demands, the goal mode); the people are
##   SurvivorPerson records in Survival.state()["people"]; the pressure is Survival's own per-zone
##   record (this writes only zones not hosted).
## - The far tick: every WorldModel.TICK_MIN world minutes (30 s real at DAY_MIN 48; sleep speeds
##   it with the clock) one WorldModel.step runs on a WorkerThreadPool task over a snapshot, and
##   its result is applied here on the main thread (`threaded`; tests run it inline). Main-thread
##   changes made while a step is out (mutate) are replayed onto the result.
## - Live groups (4.4) are WorldLive's (a child of the hosted SurvivalLevel).
## - The catch-up (section 9, calls 25, 67): on Continue, the frozen real time since the last far
##   tick as world time, up to CATCH_UP_DAYS: far ticks with the players' farm and companions
##   safe, the clock moved on, and a "while you were away" report.
## - Events near the players go to the journal; demands to the players as a journal line and a
##   message; a far horde walking in becomes ZoneDead's horde at the crossing.
## - The goal modes (section 11, call 44): goal_state(); the win and the loss in the journal.
## Public API for the next lanes: region_of, holder_of, region_holders, groups_in, group,
## rumours_for, server_pay_demand, server_player_trade, server_set_evac_paid, goal_state,
## dead_mult, refill_mult, events_near; the `event_added` signal.

signal event_added(e: Dictionary)
signal goal_changed(state: Dictionary)

const NODE_NAME := "WorldSim"
const KEY := "world"
## Proposed: the catch-up's bound (call 67), and how far from the players an event is "near".
const CATCH_UP_DAYS := 2.0
const NEAR_LINKS := 1
## Proposed: the goal modes' numbers (call 44): evac's refill speeds up 10% and the dead thicken
## 5% each SEASON_STEP_DAYS; clear-the-map refills twice as fast; a zone is quiet under CLEAR_QUIET
## of its dead; a group at FRIEND_HOLD with the players holds its zone for them.
const SEASON_STEP_DAYS := 10
const EVAC_REFILL_STEP := 0.1
const EVAC_DEAD_STEP := 0.05
const CLEAR_REFILL := 2.0
const CLEAR_QUIET := 0.15
const FRIEND_HOLD := 50.0
## Proposed: what the players' side is worth in a fight, a head.
const PLAYER_X := 3.0
const COMPANION_X := 2.0
const SETTLER_X := 1.5
## Proposed: the stores' value the raiders hear of before there's a settlement, and what its
## defence value (Settlement.defence: walls, gates, lookouts, guards) adds to its fighting strength.
const RUMOURED_STOCKS := 1500.0
const DEFENCE_X := 0.1
const JOURNAL_KINDS: Array[String] = ["fight", "raid", "demand", "horde", "horde_moved", "horde_attack", "capture", "fed", "settled", "group_gone",
	"supply_drop", "burning", "bell", "broadcast", "hunt", "rescue", "turned", "split", "formed", "death", "arrived"]

## Run the far step on a worker thread (false: inline; tests).
var threaded := true
var enabled := true

var _task := -1
var _job: WorldModel = null
var _job_status := {}  # person id -> status at the snapshot
var _pending: Array[Callable] = []
var _report_sent := false


static func get_sim() -> WorldSim:
	return Survival.get_node_or_null(NodePath(NODE_NAME)) as WorldSim


func _init() -> void:
	name = NODE_NAME


## The world section (Survival.state()["world"]).
static func section() -> Dictionary:
	var st := Survival.state()
	if not st.get(KEY) is Dictionary:
		st[KEY] = {}
	return st[KEY]


static func people() -> Dictionary:
	var st := Survival.state()
	if not st.get("people") is Dictionary:
		st["people"] = {}
	return st["people"]


static func pressure_section() -> Dictionary:
	var st := Survival.state()
	if not st.get("pressure") is Dictionary:
		st["pressure"] = {}
	return st["pressure"]


static func world_seed() -> int:
	return int(Survival.state().get("seed", 0))


static func world_now() -> float:
	return Survival.day() + Survival.hour() / 24.0


static func hosted_zone() -> String:
	return String(Survival.state().get("zone", "")) if Survival.running else ""


## A model bound to the live state (main thread).
static func model() -> WorldModel:
	var m := WorldModel.new(section(), people(), pressure_section(), world_seed())
	m.now = world_now()
	m.hosted = hosted_zone()
	m.player = player_info()
	m.refill_mult = refill_mult()
	return m


static func is_set_up() -> bool:
	return not (section().get("zones", {}) as Dictionary).is_empty()


# --- Setup ---------------------------------------------------------------------------------------

## Host: a new world's regions, groups and goal mode (once a world; main thread).
static func server_setup() -> void:
	if is_set_up():
		return
	var t0 := Time.get_ticks_msec()
	var table := {}
	var cells := {}
	var layout := RegionMap.layout()
	for z: String in WorldRegions.zone_ids():
		table[z] = WorldRegions.build_zone(z, world_seed())
		if layout.has(z):
			var c: Vector2i = layout[z]
			cells[z] = [c.x, c.y]
	for z: String in table:  # (links only to the world's zones: the campaign's base zone isn't one)
		var zd: Dictionary = table[z]
		zd.links = (zd.links as Array).filter(func(l: String) -> bool: return table.has(l))
	SurvivorPerson.make(RandomNumberGenerator.new(), "warm")  # (its tables, before a worker uses them)
	var m := model()
	m.w["cells"] = cells
	m.w["t"] = world_now()
	m.w["wall"] = Time.get_unix_time_from_system()
	var start := String(Survival.state().get("start_zone", Survival.start_zone()))
	m.setup(table, start, Survival.option_mult("world"))
	_setup_goal(m, start)
	SessionLog.note("survival world: %d zones, %d groups, %d people at setup (%d ms)" % [table.size(), m.groups().size(), people().size(), Time.get_ticks_msec() - t0])


## The goal mode's setup (call 44): evac and sandbox have the enclave (a placeholder group for the
## enclave lane) at the evac place farthest from the start (the port or the base); evac
## broadcasts it.
static func _setup_goal(m: WorldModel, start: String) -> void:
	var mode := Survival.option("goal")
	var g := {"mode": mode, "evac_zone": "", "evac_group": "", "won": false, "lost": false, "day": Survival.day()}
	if mode in ["evac", "sandbox"]:
		var best := ""
		var best_d := -1
		for z: String in WorldModel._sorted(m.zones().keys()):
			if bool(WorldRegions.type_def(String(m.zone(z).get("type", ""))).get("evac", false)):
				var d := WorldRegions.distance(m.zones(), start, z)
				if d > best_d:
					best_d = d
					best = z
		if best != "":
			var zd := m.zone(best)
			var places: Array = (zd.places as Array).duplicate()
			places.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.defence) > float(b.defence) or (float(a.defence) == float(b.defence) and String(a.id) < String(b.id)))
			var rng := m.rng_for("enclave", "setup")
			var e := m.new_group("enclave", best, WorldModel._place_v(places[0]), rng)
			m.set_home(e, best, places[0])
			e.defence = 0.8
			g.evac_zone = best
			g.evac_group = String(e.id)
			if mode == "evac":
				m.event(best, "broadcast", [String(e.id)], "a broadcast on the emergency band: an evacuation at %s, rationed, for those who can pay" % String(zd.get("name", best)))
	m.w["goal"] = g


# --- The far tick --------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not enabled or not Survival.running or not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if not CompoundLevel.current(self) is SurvivalLevel or not is_set_up():
		return
	if _task >= 0:
		if WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
			_apply_job()
		return
	var w := section()
	var step_d := WorldModel.TICK_MIN / 1440.0
	var last := float(w.get("t", world_now()))
	if world_now() - last >= step_d:
		server_far_tick(last + step_d)


## Host: one far tick at world time `at` (on a worker when `threaded`).
func server_far_tick(at: float) -> void:
	if not threaded:
		var m := model()
		m.step(at)
		section()["t"] = at
		section()["wall"] = Time.get_unix_time_from_system()
		_after_step(m)
		return
	var snap_people := {}
	_job_status = {}
	for id: String in people():
		var rec: Dictionary = people()[id]
		var st := String(rec.get("status", ""))
		if st in [WorldGroup.GROUPED, "captive", "out_there"]:
			snap_people[id] = rec.duplicate(true)
			_job_status[id] = st
	_job = WorldModel.new(section().duplicate(true), snap_people, pressure_section().duplicate(true), world_seed())
	_job.now = at
	_job.hosted = hosted_zone()
	_job.player = player_info()
	_job.refill_mult = refill_mult()
	_job.w["t"] = at
	_job.w["wall"] = Time.get_unix_time_from_system()
	_pending.clear()
	_task = WorkerThreadPool.add_task(_job.step.bind(at), false, "world far tick")


## Main thread: the worker's step lands: the world section, the sim's people (merged into the
## same records, never replacing ones the people lane changed meanwhile), the far zones'
## pressure; then what changed here while it ran.
func _apply_job() -> void:
	var m := _job
	_job = null
	if m == null:
		return
	Survival.state()[KEY] = m.w
	var live_people := people()
	for id: String in m.people:
		var rec: Dictionary = m.people[id]
		var main: Dictionary = live_people.get(id, {})
		if main.is_empty():
			live_people[id] = rec
			continue
		var snap := String(_job_status.get(id, ""))
		if String(main.get("status", "")) != snap:
			continue  # (changed here while the step ran: the people lane's)
		if snap == "out_there" and String(main.get("zone", "")) == hosted_zone() and String(rec.get("status", "")) == snap:
			continue  # (the hosted zone's lone survivors are SurvivorsLayer's)
		for key: String in rec:
			if key != "needs":
				main[key] = rec[key]
	var pr := pressure_section()
	for z: String in m.pressure:
		if z != hosted_zone():
			pr[z] = m.pressure[z]
	m.people = live_people
	m.pressure = pr
	m.w = Survival.state()[KEY]
	for fn: Callable in _pending:
		fn.call(section())
	_pending.clear()
	_after_step(m)


## Host: `fn` (taking the world section) changes the world now, and again on the step's result
## if one is out on the worker (so a change made here isn't lost).
func mutate(fn: Callable) -> void:
	fn.call(section())
	if _task >= 0:
		_pending.append(fn)


## Main thread, after each step: its actions, its events near the players, the goal's state.
func _after_step(m: WorldModel) -> void:
	for a: Dictionary in m.actions:
		_do_action(a)
	for e: Dictionary in m.new_events:
		event_added.emit(e)
		if is_near(e) and String(e.kind) in JOURNAL_KINDS and not bool(section().get("catching_up", false)):
			Survival._journal_line(_cap(String(e.text)) + ".")
	_update_held()
	_check_goal()


func _do_action(a: Dictionary) -> void:
	var level := CompoundLevel.current(self) as SurvivalLevel
	match String(a.kind):
		"demand":
			_put_demand(a)
		"pressure":
			if level and String(a.zone) == hosted_zone():
				var p: Array = a.get("pos", [0.0, 0.0])
				Survival._raise_pressure(level, Vector3(float(p[0]), 0.0, float(p[1])), float(a.amount))
		"horde_enter":
			if level and String(a.zone) == hosted_zone():
				var at := Vector3.ZERO
				for c: Dictionary in RegionMap.crossings(String(a.zone), level.def):
					if String(c.to) == String(a.from):
						at = Vector3(float(c.pos[0]), 0.0, float(c.pos[1]))
				var crowd := ZoneDead.of(level)
				if crowd:
					var made := crowd.server_horde(level.ground_point(at), int(a.n))
					SessionLog.note("survival world: a horde of %d walks in from %s" % [made, String(a.from)])
				Survival._journal_line("A horde is coming over from %s." % RegionMap.zone_name(String(a.from)))
				_tell_all("A horde is coming over from %s" % RegionMap.zone_name(String(a.from)))
		"take_stock":
			var share := float(a.get("share", 0.3))
			var taken := 0
			for e: Dictionary in _store_entries():
				taken += Settlement.taken_count(Settlement.server_take(String(e.id), ceili(int(e.get("count", 1)) * share)))
			Survival._journal_line("%s took %d things from the stores." % [String(group(String(a.get("group", ""))).get("name", "Raiders")), taken])


## A demand on the players' settlement (call 55): the council's question (Council.server_put, the
## goods to pay listed from the stores up to the demand's value), else a journal line and a
## message. Paying (the council's yes) answers it (server_pay_demand); refusing leaves the raid due.
func _put_demand(a: Dictionary) -> void:
	var gid := String(a.group)
	var text := "%s want $%d of goods from the farm within %d hours, or they'll take it" % [String(a.name), int(a.want), roundi(WorldGoals.DEMAND_DAYS * 24.0)]
	if Settlement.exists():
		var pay: Array = []
		var value := 0.0
		for e: Dictionary in _store_entries():
			if value >= float(a.want):
				break
			var unit := maxf(1.0, WorldTrade.value(String(e.id)))
			var n := mini(int(e.get("count", 1)), ceili((float(a.want) - value) / unit))
			pay.append([String(e.id), n])
			value += unit * n
		var id := Council.server_put({"kind": "demand", "text": text, "pay": pay, "from": gid}, ["pay", "refuse"], func(result: String) -> void:
			if result == "pay":
				server_pay_demand(gid))
		if id >= 0:
			return
	Survival._journal_line(text + ".")
	_tell_all(text)


## The settlement's store entries ([{id, count}], all its stashes and the yard), food, meds and
## ammo first (what raiders want).
static func _store_entries() -> Array:
	var out: Array = []
	if not Settlement.exists():
		return out
	var stores := Settlement.stores()
	for key: String in stores:
		if stores[key] is Array:
			for e: Variant in stores[key]:
				if e is Dictionary:
					out.append(e)
	var rank := func(e: Dictionary) -> int:
		return int({"food": 0, "meds": 1, "ammo": 2, "water": 3, "fuel": 4}.get(Settlement.category_of(String(e.id)), 9))
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return rank.call(x) < rank.call(y))
	return out


func _tell_all(text: String) -> void:
	var level := CompoundLevel.current(self)
	if level == null:
		return
	for p: Soldier in MapNodes.players(level):
		Survival._tell(p, text)


# --- The players as the sim sees them ------------------------------------------------------------

## {"zone", "place", "place_pos", "strength", "home_strength", "stocks_value", "can_take",
## "hunt_zone", "safe"}: the players' farm (the start zone's safehouse), their numbers (players,
## companions, settlers), their stores (the settlement lane's, when it exposes them).
static func player_info() -> Dictionary:
	var zone := Settlement.zone() if Settlement.exists() else String(Survival.state().get("start_zone", ""))
	var companions := 0
	var settlers := 0
	for id: String in people():
		match String((people()[id] as Dictionary).get("status", "")):
			"companion":
				companions += 1
			"settler":
				settlers += 1
	var players := maxi(1, (Campaign.section(Survival.SURVIVORS) as Dictionary).size())
	var safe := SurvivalMap.safehouse()
	var pos := SurvivalMap.mark_pos(safe) if not safe.is_empty() else Vector2.ZERO
	if Settlement.exists():
		pos = Vector2(Settlement.pos().x, Settlement.pos().z)
	var strength := players * PLAYER_X + companions * COMPANION_X + settlers * SETTLER_X
	var at_home := hosted_zone() == zone
	var stocks_value := RUMOURED_STOCKS
	var defence := 0.0
	if Settlement.exists():
		stocks_value = 0.0
		for e: Dictionary in _store_entries():
			stocks_value += WorldTrade.value(String(e.id)) * int(e.get("count", 1))
		var node := Settlement.find(Survival)
		defence = node.defence() if node else float(Settlement.data().get("defence_builds", 0.0))
	var home := (strength if at_home else settlers * SETTLER_X) + defence * DEFENCE_X
	return {"zone": zone, "place": "safehouse", "place_pos": [pos.x, pos.y], "strength": strength + defence * DEFENCE_X,
		"home_strength": home, "stocks_value": stocks_value, "defence": defence,
		"can_take": Settlement.exists(), "hunt_zone": hosted_zone() if hosted_zone() != "" else zone,
		"safe": bool(section().get("catching_up", false))}


# --- The catch-up (section 9) --------------------------------------------------------------------

## Host, on Continue (Survival.server_continue): the real time the world sat unhosted since its
## last far tick, as world time (DAY_MIN), up to CATCH_UP_DAYS, run now. Returns the hours run.
static func server_on_continue() -> float:
	if not is_set_up():
		return 0.0
	var wall := float(section().get("wall", Time.get_unix_time_from_system()))
	var away_s := maxf(0.0, Time.get_unix_time_from_system() - wall)
	var hours := away_s / (Survival.DAY_MIN * 60.0) * 24.0
	return server_catch_up(hours)


## Host: `hours` (capped at CATCH_UP_DAYS) of far ticks at once: the farm can't be attacked
## (raids become a demand waiting on return), companions aren't in the sim; the clock moves on
## (Proposed: the world's time passes with it). The report goes to the journal and to the first
## player in (WorldLive). Returns the hours run.
static func server_catch_up(hours: float) -> float:
	hours = clampf(hours, 0.0, CATCH_UP_DAYS * 24.0)
	var ticks := floori(hours * 60.0 / WorldModel.TICK_MIN)
	if ticks <= 0 or not is_set_up():
		return 0.0
	var w := section()
	w["catching_up"] = true
	var m := model()
	m.hosted = ""  # (nothing is hosted while it runs)
	m.player.safe = true
	var from := float(w.get("t", world_now()))
	var first_event := int(w.get("next_event", 0))
	m.run(ticks, from)
	w["t"] = from + ticks * WorldModel.TICK_MIN / 1440.0
	w["wall"] = Time.get_unix_time_from_system()
	w.erase("catching_up")
	var t_now := world_now() + ticks * WorldModel.TICK_MIN / 1440.0
	Survival.state()["day"] = int(floor(t_now))
	Survival.state()["hour"] = fmod(t_now, 1.0) * 24.0
	for d: Dictionary in (w.get("demands", {}) as Dictionary).values():  # deferred raids: a demand waiting on return
		if bool(d.get("deferred", false)):
			d.deferred = false
			d.due = t_now + WorldGoals.DEMAND_DAYS
	var lines: Array = []
	for e: Dictionary in w.get("events", []):
		if int(e.id) > first_event and is_near(e) and String(e.kind) in JOURNAL_KINDS:
			lines.append(_cap(String(e.text)))
	w["away_report"] = {"hours": snappedf(ticks * WorldModel.TICK_MIN / 60.0, 0.1), "lines": lines.slice(-12), "told": false}
	Survival._journal_line("While you were away (%d hours): %s" % [roundi(ticks * WorldModel.TICK_MIN / 60.0), "; ".join(lines.slice(-12)) if not lines.is_empty() else "nothing near the farm changed"])
	SessionLog.note("survival world: catch-up of %d ticks, %d events near the players" % [ticks, lines.size()])
	return ticks * WorldModel.TICK_MIN / 60.0


# --- What's near the players ---------------------------------------------------------------------

## Whether event `e` is near the players: in or next to the hosted zone or the farm's, or about them.
static func is_near(e: Dictionary) -> bool:
	if "player" in (e.get("groups", []) as Array):
		return true
	var zones: Dictionary = section().get("zones", {})
	var z := String(e.get("zone", ""))
	for home: String in [hosted_zone(), String(Survival.state().get("start_zone", ""))]:
		if home == "":
			continue
		if z == home or z in ((zones.get(home, {}) as Dictionary).get("links", []) as Array):
			return true
	return false


## The events near the players since world day `since_day`.
static func events_near(since_day := 0) -> Array:
	return (section().get("events", []) as Array).filter(func(e: Dictionary) -> bool: return int(e.day) >= since_day and is_near(e))


# --- Regions as territories ----------------------------------------------------------------------

## The region a zone belongs to ("plains", "hills", "desert", "coast", "city").
static func region_of(zone_id: String) -> String:
	var zd: Dictionary = (section().get("zones", {}) as Dictionary).get(zone_id, {})
	return String(zd.get("region", WorldRegions.zone_info(zone_id, world_seed()).get("region", "")))


## The group holding a place (a zone's site id), "" for nobody; "player" for the farm.
static func holder_of(zone_id: String, place_id: String) -> String:
	if zone_id == String(Survival.state().get("start_zone", "")) and place_id == "safehouse":
		return "player"
	var zd: Dictionary = (section().get("zones", {}) as Dictionary).get(zone_id, {})
	return String(WorldRegions.place(zd, place_id).get("holder", ""))


## A region's political shape: {group id: places held} (the map's faint colour, section 10).
static func region_holders(region_id: String) -> Dictionary:
	var out := {}
	for zd: Dictionary in (section().get("zones", {}) as Dictionary).values():
		if String(zd.get("region", "")) != region_id:
			continue
		for p: Dictionary in zd.get("places", []):
			if String(p.holder) != "":
				out[String(p.holder)] = int(out.get(String(p.holder), 0)) + 1
	return out


static func group(gid: String) -> Dictionary:
	return (section().get("groups", {}) as Dictionary).get(gid, {})


## The living groups in a zone (lone survivors included).
static func groups_in(zone_id: String) -> Array:
	var out: Array = []
	for gid: String in WorldModel._sorted((section().get("groups", {}) as Dictionary).keys()):
		var g: Dictionary = section().groups[gid]
		if bool(g.alive) and String(g.zone) == zone_id:
			out.append(g)
	return out


## What `person_id` can tell (Rumours): their group's events, true, half-true or a lie by teller.
static func rumours_for(person_id: String, limit := Rumours.MAX) -> Array:
	return Rumours.for_person(section(), people(), person_id, world_seed(), limit)


# --- What the players do -------------------------------------------------------------------------

## Host: the players paid `gid`'s demand (the trade or talk lane takes the goods).
func server_pay_demand(gid: String) -> bool:
	if not (section().get("demands", {}) as Dictionary).has(gid):
		return false
	mutate(func(w: Dictionary) -> void:
		var d: Dictionary = (w.get("demands", {}) as Dictionary).get(gid, {})
		if not d.is_empty():
			d.paid = true)
	Survival._journal_line("We paid %s off." % String(group(gid).get("name", "them")))
	return true


## Host: the players traded `value` dollars of goods with `gid` (the trade lane): standing up.
func server_player_trade(gid: String, value: float) -> void:
	server_change_relation(gid, clampf(value / 50.0, 1.0, 15.0), "traded")


## Host: `gid`'s standing with the players moves by `by` (what they saw: shots, help, trade).
func server_change_relation(gid: String, by: float, why := "") -> void:
	mutate(func(w: Dictionary) -> void:
		var g: Dictionary = (w.get("groups", {}) as Dictionary).get(gid, {})
		if g.is_empty():
			return
		WorldGroup.change_relation(g, "player", by)
		if by <= -40.0:
			g.grudge = "player"
		if why != "":
			WorldGroup.remember(g, world_now(), "player", why, "player"))


## Host: the enclave's price is paid (the enclave lane): the evac can be won.
func server_set_evac_paid(paid := true) -> void:
	mutate(func(w: Dictionary) -> void:
		var g: Dictionary = w.get("goal", {})
		g["price_paid"] = paid)


## Host: one of the dead fell in the hosted zone (Survival._on_zombie_died): its density thins; a
## kill by a player near a live group's people is help they saw.
func server_dead_down(z: Soldier) -> void:
	var zone := hosted_zone()
	mutate(func(w: Dictionary) -> void:
		var zd: Dictionary = (w.get("zones", {}) as Dictionary).get(zone, {})
		if not zd.is_empty():
			zd.dead = maxf(0.0, float(zd.get("dead", 1.0)) - 1.0 / maxf(1.0, WorldModel.DEAD_PER_ZONE * WorldRegions.dead_base(zd))))
	var live := WorldLive.of(z)
	if live:
		live.server_dead_down(z)


# --- The goal modes (section 11) -----------------------------------------------------------------

## The goal mode's state: {"mode" (evac | sandbox | clear), "evac_zone", "evac_group", "evac"
## (whether there is one now), "refill_mult", "dead_mult", "quiet" (zones quiet), "zones",
## "held" (zones held by the players' presence), "won", "lost", "text"}.
static func goal_state() -> Dictionary:
	var g: Dictionary = section().get("goal", {})
	var mode := String(g.get("mode", Survival.option("goal")))
	var zones: Dictionary = section().get("zones", {})
	var quiet := 0
	var held: Array = []
	for z: String in WorldModel._sorted(zones.keys()):
		var zd: Dictionary = zones[z]
		if float(zd.get("dead", 1.0)) <= CLEAR_QUIET:
			quiet += 1
		if bool(zd.get("held_by_player", false)):
			held.append(z)
	var enclave := group(String(g.get("evac_group", "")))
	var evac := mode == "evac" and not enclave.is_empty() and bool(enclave.get("alive", false))
	var text := ""
	match mode:
		"evac":
			text = ("Reach the evac at %s" % RegionMap.zone_name(String(g.get("evac_zone", "")))) if evac else "The evac is gone"
		"clear":
			text = "Clear the map: %d of %d zones quiet" % [quiet, zones.size()]
		_:
			text = "Sandbox: day %d" % Survival.day()
	return {"mode": mode, "evac_zone": String(g.get("evac_zone", "")), "evac_group": String(g.get("evac_group", "")), "evac": evac,
		"refill_mult": refill_mult(), "dead_mult": dead_mult(), "quiet": quiet, "zones": zones.size(), "held": held,
		"won": bool(g.get("won", false)), "lost": bool(g.get("lost", false)), "price_paid": bool(g.get("price_paid", false)), "text": text}


static func _steps() -> int:
	return maxi(0, int((Survival.day() - 1) / SEASON_STEP_DAYS))


## How fast the dead refill (thinned cells and far zones; 1 normal): evac speeds up each season
## step, clear-the-map doubles it.
static func refill_mult() -> float:
	match String((section().get("goal", {}) as Dictionary).get("mode", Survival.option("goal"))):
		"evac":
			return 1.0 + EVAC_REFILL_STEP * _steps()
		"clear":
			return CLEAR_REFILL
	return 1.0


## The dead's density multiplier (Survival.dead_near): evac's slow rise over the season.
static func dead_mult() -> float:
	if String((section().get("goal", {}) as Dictionary).get("mode", Survival.option("goal"))) == "evac":
		return 1.0 + EVAC_DEAD_STEP * _steps()
	return 1.0


## Zones held by the players' standing presence (clear-the-map): the farm's, and any zone where a
## group friendly to them (FRIEND_HOLD) holds a place.
func _update_held() -> void:
	var zones: Dictionary = section().get("zones", {})
	var home := String(Survival.state().get("start_zone", ""))
	for z: String in zones:
		var zd: Dictionary = zones[z]
		var held := z == home
		if not held:
			for p: Dictionary in zd.get("places", []):
				var g := group(String(p.holder))
				if not g.is_empty() and WorldGroup.relation(g, "player") >= FRIEND_HOLD:
					held = true
					break
		zd.held_by_player = held


## The win and the loss (call 44), told once in the journal and to every player.
func _check_goal() -> void:
	var g: Dictionary = section().get("goal", {})
	if g.is_empty() or bool(g.get("won", false)) or bool(g.get("lost", false)):
		return
	var st := goal_state()
	var won := false
	var lost := false
	var text := ""
	match String(st.mode):
		"evac":
			if not bool(st.evac):
				lost = true
				text = "The enclave is gone, and the evac with it."
			elif hosted_zone() == String(st.evac_zone) and bool(st.price_paid):
				won = true
				text = "You reached the evac with the price paid. You're out."
		"clear":
			if int(st.quiet) >= int(st.zones) and int(st.zones) > 0:
				won = true
				text = "Every zone is quiet. The map is clear."
	if won or lost:
		g.won = won
		g.lost = lost
		Survival._journal_line(text)
		_tell_all(text)
		goal_changed.emit(goal_state())


static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s
