extends Node
## Survival (docs/survival.md), the autoload: a survival world's own state, host-authoritative,
## kept in Campaign sections under its own campaign id ("survival_<world>"), never the
## campaign's. The world is the campaign's zones on RegionMap's grid, overrun; each zone plays as
## a SurvivalLevel and keeps its own save ("surv_<world>_<zone>"). This node keeps:
## - the world clock (a day is DAY_MIN real minutes while the world is hosted), driving DayNight;
## - each survivor's needs, hunger and thirst (100 full, 0 empty): drained on the host, sent to
##   their owner, eaten and drunk back up through Consumables ("water" and "ration" doses), with
##   slower stamina when low and blood loss when empty (Soldier.needs_stamina);
## - death: a survivor drops everything where he fell (it stays: ZoneCleanup keeps drops in
##   survival) and comes back at the safehouse with STARTER_KIT;
## - the survivors' kit, needs and zone in the save, by profile (BaseHub.profile()).
## Clients know they're in survival by the level (SurvivalLevel.of); `running` is the host's.

signal needs_changed(hunger: float, thirst: float)  # this peer's own survivor
signal body_changed  # this peer's own survivor's body (my_body)

const PREFIX := "survival_"
const SECTION := &"survival"
const SURVIVORS := &"survivors"
## Proposed: a world day in real minutes, and when a new world's first day starts.
const DAY_MIN := 48.0
const START_HOUR := 8.0
## Proposed (world days to empty): thirst, then hunger; running and a heavy load drain faster.
const THIRST_DAYS := 1.5
const HUNGER_DAYS := 3.0
const SPRINT_DRAIN_MULT := 2.0
## Below LOW stamina comes back at LOW_STAMINA_MULT (scaled down to EMPTY_STAMINA_MULT at 0); at 0
## a survivor loses EMPTY_DAMAGE a second until he eats or drinks (thirst twice as fast).
const LOW := 25.0
const LOW_STAMINA_MULT := 0.6
const EMPTY_STAMINA_MULT := 0.3
const EMPTY_DAMAGE := 0.01
## A water dose and a ration dose (Consumables' "water" and "ration" drugs) fill this much.
const WATER_PER_DOSE := 35.0
const FOOD_PER_DOSE := 25.0
## What a new survivor has (docs/survival.md S1: a knife, water, a tin, light (chem lights until
## there's a torch), bandages). Proposed.
const STARTER_KIT: Array = [["combat_knife", 1], ["knife", 1], ["water_bottle", 1], ["canned_meat", 1], ["chemlight_green", 2], ["pressure_bandage", 2]]
const RESPAWN_NEEDS := 70.0
const TICK_S := 1.0
const SEND_S := 2.0
const SAVE_MIN := 5.0

## Host: whether a survival world is hosted, and which.
var running := false
var world := ""
## This peer's own needs (the host sends them to their owner).
var my_hunger := 100.0
var my_thirst := 100.0
## This peer's own survivor's body, every store (Needs; the host sends it to its owner).
var my_body := {}

var _tick := 0.0
var _send := 0.0
var _save := 0.0
var _clock_s := 0.0  # host: real seconds into the world's current hour


## The world's saved state ("seed", "day", "hour", "zone" (where it's played), "start_zone").
func _ready() -> void:
	add_child(Rpg.new())  # the RPG layer's RPCs and tick (Rpg)
	add_child(WorldSim.new())  # the living world's far tick (WorldSim, survival_world.md)
	add_child(Intel.new())  # the intel layer: rumours, reports, the radio, trade's RPCs (Intel)


func state() -> Dictionary:
	return Campaign.section(SECTION)


## Host: a new world called `name` from `world_seed`, hosted at its start zone under `main`
## (the session's Main: the menu's parent).
func server_new_world(main: Node, name: String, world_seed: int, options := {}) -> bool:
	var id := _world_id(name)
	Campaign.campaign_id = PREFIX + id
	Campaign.reset_campaign()
	world = id
	var start := start_zone()
	var opts := DEFAULT_OPTIONS.duplicate()
	opts.merge(options, true)
	state().merge({"seed": world_seed, "day": 1, "hour": START_HOUR, "zone": start, "start_zone": start, "name": name, "options": opts}, true)
	return _host_zone(main, start)


## The world's goal and options (NewWorldScreen; calls 7, 49): "goal" evac | sandbox | clear;
## "dead", "loot", "needs", "world" each low | normal | high. option_mult turns a level into the
## multiplier the systems use (the dead's density and night speed, the needs' rates, ...).
const DEFAULT_OPTIONS := {"goal": "evac", "dead": "normal", "loot": "normal", "needs": "normal", "world": "normal", "season": "spring"}
const OPTION_MULTS := {"low": 0.6, "normal": 1.0, "high": 1.5}
const SPEED_MULTS := {"low": 0.85, "normal": 1.0, "high": 1.15}


func option(key: String) -> String:
	return String((state().get("options", {}) as Dictionary).get(key, DEFAULT_OPTIONS.get(key, "normal")))


func option_mult(key: String) -> float:
	return float(OPTION_MULTS.get(option(key), 1.0))


## The season now: "spring", "summer", "autumn" or "winter" (Seasons: ~10 world days each from the
## New world option "season"; the body lane reads it, and Seasons' flags: thirst_mult, spoil_mult,
## water_frozen, temperature_c).
func season() -> String:
	return Seasons.current()


## The dead's pace multiplier from the "dead" option (ZombieAI).
func dead_speed_mult() -> float:
	return float(SPEED_MULTS.get(option("dead"), 1.0))


## Host: the options changed mid-world (tests, a dev key); the next spawns and ticks use them.
func server_set_options(options: Dictionary) -> void:
	var opts: Dictionary = state().get("options", DEFAULT_OPTIONS.duplicate())
	opts.merge(options, true)
	state()["options"] = opts


## Host: carries on the world `name` (or the newest), where it was left, under `main`.
func server_continue(main: Node, name := "") -> bool:
	var id := _world_id(name) if name != "" else newest_world()
	if id == "":
		return false
	Campaign.campaign_id = PREFIX + id
	if not Campaign.load_campaign():
		return false
	world = id
	_world_continue()  # the world's catch-up for the time it sat unhosted (WorldSim)
	return _host_zone(main, String(state().get("zone", start_zone())))


## The newest saved world's id, or "".
func newest_world() -> String:
	var best := ""
	var best_t := -1
	var dir := DirAccess.open(Campaign.SAVE_DIR)
	if dir == null:
		return ""
	for f: String in dir.get_files():
		if f.begins_with(PREFIX) and f.ends_with(".json"):
			var t := FileAccess.get_modified_time("%s/%s" % [Campaign.SAVE_DIR, f])
			if t > best_t:
				best_t = t
				best = f.trim_prefix(PREFIX).trim_suffix(".json")
	return best


## The zone a new world starts in: the first inland zone of the region map (the countryside by
## the old FOB: farms and a village, quieter than the towns).
func start_zone() -> String:
	for z: Dictionary in MissionRegistry.data().get("zones", []):
		if String(z.get("region", "")) == RegionMap.BASE_REGION and String((z.get("def", {}) as Dictionary).get("layout", "") if z.get("def") is Dictionary else "") != "hot":
			return String(z.zone_id)
	var all: Array = MissionRegistry.data().get("zones", [])
	return String(all[0].zone_id) if not all.is_empty() else "test"


func _world_id(name: String) -> String:
	var clean := name.strip_edges().to_lower().replace(" ", "_").validate_filename()
	return clean if clean != "" else "world"


## Host: hosts `zone_id` of this world for the session.
func _host_zone(main: Node, zone_id: String) -> bool:
	var def := MissionRegistry.zone_def(zone_id) if zone_id != "test" else ZoneDef.get_def("test")
	if def.is_empty():
		return false
	if main == null or not main.has_method(&"host_zone"):
		return false
	BaseHub.cancel_session()  # never a leftover campaign
	running = true
	state()["zone"] = zone_id
	GameState.zone_id = zone_save(zone_id)
	main.host_zone(def.duplicate(true), "survival")
	return true


## A zone's save id in this world.
func zone_save(zone_id: String) -> String:
	return "surv_%s_%s" % [world, zone_id]


## Host: the level is up (SurvivalLevel._ready): the clock and the sky.
func server_level_ready(level: SurvivalLevel) -> void:
	running = true
	_apply_sky(level)
	_seed_crowd(level)
	ColdOpen.server_begin(level)  # a new world's first hour (once)
	Settlement.install(level)  # the settlement's work and council (Settlement, survival_building.md 5-7)
	_world_level_ready(level)  # the world sim set up, its live groups (WorldSim, WorldLive)
	Mounts.install(level)  # horses, bicycles, carts (Mounts, docs/survival_mounts.md)
	Sieges.install(level)  # raids and sieges on the builds, traps, lures, the bodies (phase D: docs/survival_seasons.md)
	Seasons.server_update(level)  # the season's weather and the dead's frost


## Host: the world is saved: the world's sections and the zone being played.
func server_save() -> void:
	if not running:
		return
	var level := CompoundLevel.current(self)
	if level is SurvivalLevel:
		for s: Soldier in MapNodes.players(level):
			_store_survivor(s)
		_store_people(level)
		GameState.save_zone()
	Campaign.save_campaign()


## Host: the world stops being hosted (back to the menu).
func server_stop() -> void:
	server_save()
	running = false
	world = ""


# --- The clock ---------------------------------------------------------------------------

## The world's hour (0-24) and day.
func hour() -> float:
	return float(state().get("hour", START_HOUR))


func day() -> int:
	return int(state().get("day", 1))


func _advance_clock(seconds: float) -> void:
	var hours := seconds / (DAY_MIN * 60.0) * 24.0
	var h := hour() + hours
	while h >= 24.0:
		h -= 24.0
		state()["day"] = day() + 1
	state()["hour"] = h


func _apply_sky(level: Node) -> void:
	var dn := DayNight.current()
	if dn and dn.is_inside_tree() and dn.multiplayer.is_server():
		dn.server_set(hour(), dn.weather)


# --- Needs -------------------------------------------------------------------------------

## A survivor's needs, {"hunger", "thirst"} (host: the truth, kept on the body).
static func needs_of(s: Soldier) -> Dictionary:
	if not s.has_meta(&"needs"):
		s.set_meta(&"needs", Needs.fresh())
	return Needs.ensure(s.get_meta(&"needs"))


## Stamina recovery's share from these needs (1 fed and watered, less when low).
static func stamina_mult_for(hunger: float, thirst: float) -> float:
	return Needs.food_stamina_mult(hunger, thirst)


## Host: `seconds` of a survivor's life: the metabolism steps (Needs: calories, water, macros,
## vitamins, sleep, warmth, hygiene; faster sprinting or heavy, asleep at SurvivalSleep.SPEED),
## its effects go on the body (stamina, sway, blood when empty) and a sickness that shows is told.
func server_drain(s: Soldier, seconds: float) -> void:
	var n := needs_of(s)
	Needs.server_step(s, n, seconds)
	_after_body_step(s, n, seconds)


## Host: `s` ate or drank (Consumables): a "water" dose fills thirst, a "ration" hunger. Returns
## whether it counted (survival only).
func server_feed(s: Soldier, drug: StringName, doses: float) -> bool:
	if not running:
		return false
	var n := needs_of(s)
	if not Needs.feed_dose(n, drug, doses):
		return false
	Needs.apply(s, n)
	_send_needs(s)
	return true


func _send_needs(s: Soldier) -> void:
	if s.is_ai():
		return
	var n := needs_of(s)
	var peer := s.owner_peer()
	if peer == multiplayer.get_unique_id():
		_client_needs(float(n.hunger), float(n.thirst), s.needs_stamina)
		_client_body(n)
	elif peer in multiplayer.get_peers():
		_client_needs.rpc_id(peer, float(n.hunger), float(n.thirst), s.needs_stamina)
		_client_body.rpc_id(peer, n)


## Owner: his survivor's needs (and the stamina share they leave him: movement runs here).
@rpc("authority", "call_remote", "reliable")
func _client_needs(hunger: float, thirst: float, stamina: float) -> void:
	my_hunger = hunger
	my_thirst = thirst
	var level := CompoundLevel.current(self)
	if level:
		var me := level.players.get_node_or_null(str(multiplayer.get_unique_id())) as Soldier
		if me:
			me.needs_stamina = stamina
	needs_changed.emit(hunger, thirst)


func _process(delta: float) -> void:
	if not running or not multiplayer.is_server():
		return
	var level := CompoundLevel.current(self)
	if not level is SurvivalLevel:
		return
	_tick += delta
	_send += delta
	_save += delta
	if _tick >= TICK_S:
		var dt := _tick
		_tick = 0.0
		server_tick_survivors(level, dt)
		ColdOpen.server_tick(level as SurvivalLevel)
	_pop += delta
	if _pop >= POP_TICK_S:
		_pop = 0.0
		_populate(level as SurvivalLevel)
	_steps += delta
	if _steps >= STEP_NOISE_S:
		_steps = 0.0
		_footsteps(level as SurvivalLevel)
	if _tick == 0.0:  # (a clock tick just ran: dt real seconds)
		pass
	_pressure_tick(level as SurvivalLevel, delta)
	Seasons.server_tick(level, delta)  # the year: weather, frost, the thaw (phase D)
	if _send >= SEND_S:
		_send = 0.0
		for s: Soldier in MapNodes.players(level):
			_send_needs(s)
		_apply_sky(level)
	if _save >= SAVE_MIN * 60.0:
		_save = 0.0
		server_save()


# --- Death and the safehouse --------------------------------------------------------------

## Host: a survivor died (Soldier._on_died): everything he had drops where he fell and stays,
## and he comes back with STARTER_KIT and RESPAWN_NEEDS.
func server_player_died(s: Soldier) -> void:
	var level := CompoundLevel.current(s)
	if level == null:
		return
	var at := s.global_position
	var entries := s.inventory.strip()
	for i in entries.size():
		var e: Dictionary = entries[i]
		var angle := i * 2.4
		var pos := at + Vector3(cos(angle), 0.0, sin(angle)) * (0.4 + 0.08 * i) + Vector3.UP * 0.5
		level.server_spawn_dropped(StringName(e.id), int(e.count), pos, e.get("state", {}))
	var graves: Array = state().get("graves", [])
	graves.append({"profile": profile_of(s), "zone": String(state().get("zone", "")), "pos": [at.x, at.y, at.z], "day": day(), "items": entries.size()})
	state()["graves"] = graves.slice(-20)
	# Permadeath (calls 13, 51): the survivor is gone; the player wakes as a new one, from zero
	# (the skills and perks of the RPG layer die with the old one, phase B), at the safehouse.
	var old_name := survivor_name(s)
	var fresh := _new_survivor(s)  # (the new record has no "rpg": lines, perks and flaws die with him)
	Rpg.server_sync(s)
	server_give_starter_kit(s)
	var n := needs_of(s)
	Needs.respawn(n, RESPAWN_NEEDS)
	Needs.apply(s, n)
	_send_needs(s)
	_journal_line("%s died. %s came to the farm." % [old_name, String(fresh.name)])
	if not s.is_ai():
		s._client_message.rpc_id(s.owner_peer(), "%s is dead. You are %s now." % [old_name, String(fresh.name)])
	SessionLog.note("survival: %s died at (%.0f, %.0f); %d things left there; %s takes his place (generation %d)" % [old_name, at.x, at.z, entries.size(), String(fresh.name), int(fresh.generation)])
	_people_on_death(s, old_name)


## Host: the people's live bodies into their records (SurvivorsLayer, survival_people.md).
func _store_people(level: Node) -> void:
	var layer := level.get_node_or_null(^"Survivors") as SurvivorsLayer
	if layer:
		layer.server_store_all()


## Host: a player's survivor died: his companions grieve; the newcomer is a stranger (SurvivorsLayer).
func _people_on_death(s: Soldier, old_name: String) -> void:
	var layer := SurvivorsLayer.find(s)
	if layer:
		layer.server_on_player_died(s, old_name)


## The survivor record of `s` in the save ("survivors"[profile]): name, generation, born_day.
func survivor_of(s: Soldier) -> Dictionary:
	var all: Dictionary = Campaign.section(SURVIVORS)
	var rec: Dictionary = all.get(profile_of(s), {})
	if not rec.has("name"):
		rec = _new_survivor(s, rec)
	return rec


func survivor_name(s: Soldier) -> String:
	return String(survivor_of(s).get("name", s.log_name()))


## Host: a new survivor for `s`'s profile: a name, the next generation, born today; the old
## record's zone, pos and kit are replaced on the next store.
func _new_survivor(s: Soldier, keep := {}) -> Dictionary:
	var all: Dictionary = Campaign.section(SURVIVORS)
	var old: Dictionary = all.get(profile_of(s), {})
	var gen := int(old.get("generation", 0)) + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([profile_of(s), gen, int(state().get("seed", 0))])
	var who := Names.person(rng, &"friendly", &"rifleman")
	var rec := keep.duplicate()
	rec.merge({"name": "%s %s" % [String(who.get("first", "Sam")), String(who.get("surname", "Reed"))], "generation": gen, "born_day": day()}, true)
	all[profile_of(s)] = rec
	s.set_meta(&"survivor_name", String(rec.name))
	return rec


func _journal_line(line: String) -> void:
	var j: Array = state().get("journal", [])
	j.append({"day": day(), "hour": snappedf(hour(), 0.1), "text": line})
	state()["journal"] = j.slice(-200)


## Host: a fresh survivor's kit (STARTER_KIT), whatever he had.
func server_give_starter_kit(s: Soldier) -> void:
	for e: Array in STARTER_KIT:
		if ItemDB.get_item(StringName(e[0])) != null:
			s.inventory.take(StringName(e[0]), int(e[1]))


## Host: where a survivor comes back in `level`: the safehouse (the start zone's insertion
## point) when it's the start zone, else null (the zone's own respawn).
func respawn_at(level: SurvivalLevel, _player: Soldier) -> Variant:
	if String(state().get("zone", "")) != String(state().get("start_zone", "")):
		return null
	var points := level.insertion_points()
	return level.ground_point(points[0]) if not points.is_empty() else null


## Who `s` is in the world's save: the host's profile for peer 1, else the peer's (a joiner's
## own profile key comes with S5).
func profile_of(s: Soldier) -> String:
	var peer := s.owner_peer()
	return BaseHub.profile() if peer == 1 else "peer_%d" % peer


## Host: a survivor's kit, needs and place into the save.
func _store_survivor(s: Soldier) -> void:
	var all: Dictionary = Campaign.section(SURVIVORS)
	var entries := kit_of(s.inventory)
	var p := s.global_position
	var rec: Dictionary = survivor_of(s).duplicate()
	rec.merge({"zone": String(state().get("zone", "")), "pos": [p.x, p.y, p.z], "needs": needs_of(s).duplicate(), "kit": entries}, true)
	all[profile_of(s)] = rec


## What `inv` holds, as Inventory.strip() lists it, without taking it off.
static func kit_of(inv: Inventory) -> Array:
	var all: Array = []
	for slot: StringName in Inventory.SLOTS:
		if inv.slots.get(slot, &"") != &"":
			var entry := {"id": String(inv.slots[slot]), "count": 1}
			if not (inv.slot_state.get(slot, {}) as Dictionary).is_empty():
				entry.state = (inv.slot_state[slot] as Dictionary).duplicate(true)
			all.append(entry)
	for container: StringName in Inventory.CONTAINERS:
		for entry: Dictionary in inv.containers.get(container, []):
			all.append(entry.duplicate(true))
	if inv.hands != &"":
		all.append({"id": String(inv.hands), "count": 1})
	return all


## Host: a survivor comes into the world (SurvivalLevel): his saved kit and needs, or a fresh
## survivor's.
func server_survivor_joined(s: Soldier) -> void:
	var saved: Dictionary = (Campaign.section(SURVIVORS) as Dictionary).get(profile_of(s), {})
	s.inventory.strip()
	var rec := survivor_of(s)  # (names a fresh survivor on his first join)
	s.set_meta(&"survivor_name", String(rec.get("name", "")))
	if saved.is_empty() or not saved.has("kit"):
		server_give_starter_kit(s)
	else:
		for e: Dictionary in saved.get("kit", []):
			s.inventory.take(StringName(e.id), int(e.get("count", 1)), GameState.from_json(e.get("state", {})))
		Needs.restore(needs_of(s), saved.get("needs", {}))
	SurvivalSleep.wake(needs_of(s))
	Needs.apply(s, needs_of(s))
	_send_needs(s)
	Rpg.server_joined(s)  # his lines and perks (a first survivor's creation applied)


# --- The dead (S2) ------------------------------------------------------------------------

## Proposed: how many of the dead are about a survivor (within SPAWN_MAX_M) by where he is: the
## open country, or a site of a ZoneModule type (by its base type, ZoneModules.base).
const DEAD_NEAR := {"": 2, "village": 8, "town": 12, "city": 12, "compound": 6, "outpost": 4, "checkpoint": 4, "hq": 6, "qrf_base": 6, "farm": 4}
const LIVE_CAP := 40
const SPAWN_MIN_M := 45.0
const SPAWN_MAX_M := 75.0
const DESPAWN_M := 110.0
const POP_TICK_S := 2.0
const RUNNER_SHARE := 0.15
## A cell's dead (CELL_M square) thin with every kill there, by KILL_THIN of its own; it refills
## over REFILL_DAYS world days.
const CELL_M := 64.0
const KILL_THIN := 0.08
const REFILL_DAYS := 2.0

var _pop := 0.0
var _zombie_n := 0


## Host: how many of the dead belong about `pos` in `level`, by its site and how many have been
## killed in its cell.
func dead_near(level: ZoneLevel, pos: Vector3) -> int:
	var m := level.module_at(pos)
	var base := ZoneModules.base(String(m.type)) if m else ""
	var n := float(DEAD_NEAR.get(base, DEAD_NEAR.get("", 2))) * option_mult("dead") * WorldSim.dead_mult()
	return roundi(n * (1.0 - thinned(pos)))


## How much of a cell's dead the survivors have killed off (0 untouched .. 1 cleared), healed by
## the days since.
func thinned(pos: Vector3) -> float:
	var cells: Dictionary = (state().get("thinned", {}) as Dictionary).get(String(state().get("zone", "")), {})
	var c: Variant = cells.get(_cell_key(pos))
	if not c is Dictionary:
		return 0.0
	var days := (day() + hour() / 24.0) - float(c.at)
	return clampf(float(c.v) - days * WorldSim.refill_mult() / REFILL_DAYS, 0.0, 1.0)


func _cell_key(pos: Vector3) -> String:
	return "%d,%d" % [floori(pos.x / CELL_M), floori(pos.z / CELL_M)]


## Host: one of the dead fell at `pos`: its cell thins; a bloater bursts (a noise, pressure, and
## the taint on anyone within BURST_M: survival_medical.md's hygiene, later).
const BURST_M := 4.0
const BURST_HEARD_M := 60.0


func _on_zombie_died(s: Soldier) -> void:
	if String(s.get_meta(&"zombie", "walker")) == "bloater":
		server_noise(s, s.global_position, BURST_HEARD_M, ZombieAI.HEAR_RUN)
		_raise_pressure(CompoundLevel.current(s), s.global_position, 10.0)
		for n in s.get_tree().get_nodes_in_group(&"combatants"):
			var other := n as Soldier
			if other and other != s and other.faction != ZombieAI.INFECTED and other.global_position.distance_to(s.global_position) <= BURST_M:
				other.set_meta(&"tainted_at", day() + hour() / 24.0)
				if not other.is_ai():
					other._client_message.rpc_id(other.owner_peer(), "It burst over you")
	var zone := String(state().get("zone", ""))
	var all: Dictionary = state().get("thinned", {})
	var cells: Dictionary = all.get(zone, {})
	var now := day() + hour() / 24.0
	cells[_cell_key(s.global_position)] = {"v": minf(1.0, thinned(s.global_position) + KILL_THIN), "at": now}
	all[zone] = cells
	state()["thinned"] = all
	state()["kills"] = int(state().get("kills", 0)) + 1
	_world_dead_down(s)


## The living dead in `level`.
static func zombies(level: Node) -> Array:
	var ai: Node = level.get(&"ai") if level else null
	if ai == null:
		return []
	return ai.get_children().filter(func(s: Node) -> bool: return s is Soldier and s.faction == ZombieAI.INFECTED and not s.is_queued_for_deletion() and not (s as Soldier).vitals.is_dead())


## Host: the dead about the survivors kept to dead_near: new ones out of sight SPAWN_MIN_M to
## SPAWN_MAX_M off, those past DESPAWN_M of everyone and after nobody gone (back into the zone).
func _populate(level: SurvivalLevel) -> void:
	var live := zombies(level)
	var players := MapNodes.players(level).filter(func(p: Soldier) -> bool: return p.vitals.is_up() and p.respawn_state != Soldier.RESPAWN_WAITING)
	for z: Soldier in live:
		var brain := ZombieAI.of(z)
		if brain and brain.mode == ZombieAI.Mode.CHASE:
			continue
		var far := players.all(func(p: Soldier) -> bool: return p.global_position.distance_to(z.global_position) > DESPAWN_M)
		if far:
			var crowd := ZoneDead.of(level)
			if crowd:
				crowd.server_add(z.global_position, String(z.get_meta(&"zombie", "walker")))  # back into the far tier where it stood
			z.queue_free()
			live.erase(z)
	if live.size() >= LIVE_CAP:
		return
	for p: Soldier in players:
		var near := live.filter(func(z: Soldier) -> bool: return z.global_position.distance_to(p.global_position) <= SPAWN_MAX_M).size()
		if near >= dead_near(level, p.global_position) or live.size() >= LIVE_CAP:
			continue
		var at: Variant = _spawn_spot(level, p, players)
		if at is Vector3:
			var z := server_spawn_zombie(level, at, roll_kind(level, at))
			if z:
				live.append(z)


## A navmesh spot SPAWN_MIN_M to SPAWN_MAX_M from `p`, at least SPAWN_MIN_M from every survivor
## and out of their sight (behind them, or something in the way); or null.
func _spawn_spot(level: SurvivalLevel, p: Soldier, players: Array) -> Variant:
	var map := level.get_world_3d().navigation_map
	for i in 6:
		var a := randf() * TAU
		var r := randf_range(SPAWN_MIN_M, SPAWN_MAX_M)
		var want := p.global_position + Vector3(cos(a), 0.0, sin(a)) * r
		var at := NavigationServer3D.map_get_closest_point(map, want)
		if at.distance_to(want) > 8.0:
			continue
		var ok := true
		for q: Soldier in players:
			if q.global_position.distance_to(at) < SPAWN_MIN_M or (_in_view(q, at) and Throwables.clear_line(level.get_world_3d(), q.global_position + Vector3.UP * 1.6, at + Vector3.UP * 1.4)):
				ok = false
				break
		if ok:
			return at
	return null


## Whether `at` is in front of `p`, where he'd see it come in (within VIEW_DOT of his facing).
const VIEW_DOT := 0.2


static func _in_view(p: Soldier, at: Vector3) -> bool:
	var to := at - p.global_position
	to.y = 0.0
	var fwd := -p.global_basis.z
	fwd.y = 0.0
	return to.length() > 0.1 and fwd.normalized().dot(to.normalized()) > VIEW_DOT


## Host: one of the dead at `at`.
func server_spawn_zombie(level: CompoundLevel, at: Vector3, kind := "walker") -> Soldier:
	_zombie_n += 1
	var s := level.ai_spawner.spawn({"zombie": true, "kind": kind, "name": "Z%d_%d" % [Time.get_ticks_msec() % 100000, _zombie_n], "pos": at}) as Soldier
	if s:
		s.died_for_good.connect(_on_zombie_died)
	return s


## Host: a noise at `pos` (a shot, a door, a car, a running man: Soldier's shots, _footsteps)
## heard by the dead within `radius`, `loud` 0..1 what it does to their awareness (ZombieAI.hear;
## a shot 1). A player's own noise shows on his HUD as the ring (Soldier.server_noise_made).
func server_noise(source: Node, pos: Vector3, radius: float, loud := ZombieAI.HEAR_SHOT) -> void:
	if not running or source == null:
		return
	var level := CompoundLevel.current(source)
	if not level is SurvivalLevel:
		return
	if source is Soldier and not (source as Soldier).is_ai():
		(source as Soldier).server_noise_made(radius)
	_raise_pressure(level, pos, loud * clampf(radius / ZombieAI.SHOT_HEARD_M, 0.1, 1.0) * PRESSURE_PER_SHOT)
	Mounts.on_noise(level, source, pos, radius, loud)  # a shot spooks the horses near it
	for z: Soldier in zombies(level):
		if z.global_position.distance_to(pos) <= radius:
			var brain := ZombieAI.of(z)
			if brain:
				brain.hear(pos, loud)


## Footsteps (the stealth model, call 29): every STEP_NOISE_S a man on the move is heard by the
## dead STEP_M away by his pace and stance (a sprint 25 m, a jog 14, a walk 6, crouched 3, prone
## 1), rain covering some of it (DayNight.hearing_x).
const STEP_NOISE_S := 0.6
const STEP_M := {"sprint": 25.0, "jog": 14.0, "brisk": 10.0, "walk": 6.0, "slow": 4.0, "crouch": 3.0, "prone": 1.0}
var _steps := 0.0


func _footsteps(level: SurvivalLevel) -> void:
	for s: Soldier in MapNodes.players(level):
		if not s.vitals.is_up() or s.movement == null or s.move_speed_now() < 0.3 or is_instance_valid(s.vehicle):
			continue
		var m := s.movement
		var key: String = "prone" if m.is_prone() else ("crouch" if m.is_crouched() else ("sprint" if m.is_sprinting else String(["slow", "walk", "brisk", "jog"][clampi(m.pace, 0, 3)])))
		var radius := float(STEP_M[key]) * DayNight.hearing_x() * Rpg.step_noise_mult(s)  # stealth, perks, flaws
		var loud := ZombieAI.HEAR_RUN if key in ["sprint", "jog"] else ZombieAI.HEAR_STEP
		server_noise(s, s.global_position, radius, loud)


# --- Pressure, hordes, the crowd, the specials (S3; survival_world.md section 5, calls 19, 22) ----

## A zone's pressure (0-100): shots, fights, running feet, generators and lights raise it, time
## lowers it (a half-life of PRESSURE_HALF_H world hours). The local dead drift toward the loudest
## recent noise (the pressure point) from DRIFT_AT; at HORDE_AT a horde forms from the zone's own
## dead and walks at it; under HORDE_DISPERSE_AT the horde thins. Proposed numbers.
const PRESSURE_PER_SHOT := 6.0
const PRESSURE_HALF_H := 6.0
const DRIFT_AT := 20.0
const HORDE_AT := 80.0
const HORDE_DISPERSE_AT := 30.0
const HORDE_COOLDOWN_S := 900.0
## The crowd a zone starts with, by its site types (dead_near's table scaled), and the specials'
## shares of the dead by base type (call 19: the city and the lab most; none in the open).
const CROWD_SEED := 6  # per site, Proposed
const SPECIALS := {
	"city": {"screamer": 0.04, "crawler": 0.04, "bloater": 0.02, "hazmat": 0.01},
	"town": {"screamer": 0.03, "crawler": 0.03, "bloater": 0.015, "hazmat": 0.005},
	"village": {"screamer": 0.015, "crawler": 0.02, "bloater": 0.0, "hazmat": 0.0},
	"hq": {"screamer": 0.02, "crawler": 0.02, "bloater": 0.01, "hazmat": 0.02},
	"compound": {"screamer": 0.02, "crawler": 0.02, "bloater": 0.01, "hazmat": 0.0},
}
var _pressure_sum := 0.0
var _horde_at := -10000.0


## The zone's pressure now (0-100; decayed since it was last raised).
func pressure(level: Node) -> float:
	var p: Dictionary = _pressure_rec(level)
	if p.is_empty():
		return 0.0
	var hours := ((day() + hour() / 24.0) - float(p.at)) * 24.0
	return float(p.v) * pow(0.5, maxf(hours, 0.0) / PRESSURE_HALF_H)


## Where the zone's loudest recent noise was (Vector3), or null.
func pressure_point(level: Node) -> Variant:
	var p: Dictionary = _pressure_rec(level)
	if p.is_empty() or not p.has("x"):
		return null
	return Vector3(float(p.x), float(p.get("y", 0.0)), float(p.z))


func _pressure_rec(level: Node) -> Dictionary:
	var zone := String(state().get("zone", ""))
	if level == null or zone == "":
		return {}
	var all: Dictionary = state().get("pressure", {})
	return all.get(zone, {})


func _raise_pressure(level: Node, pos: Vector3, amount: float) -> void:
	if amount <= 0.0:
		return
	var zone := String(state().get("zone", ""))
	if zone == "":
		return
	var all: Dictionary = state().get("pressure", {})
	var p: Dictionary = all.get(zone, {})
	var now := day() + hour() / 24.0
	var v := pressure(level)
	# The point moves toward the new noise by its share of what's there.
	var share := clampf(amount / maxf(v + amount, 0.01), 0.0, 1.0)
	var x := lerpf(float(p.get("x", pos.x)), pos.x, share)
	var z := lerpf(float(p.get("z", pos.z)), pos.z, share)
	all[zone] = {"v": clampf(v + amount, 0.0, 100.0), "at": now, "x": x, "y": pos.y, "z": z}
	state()["pressure"] = all


## Host, every frame: a horde when the pressure peaks (once a HORDE_COOLDOWN_S).
func _pressure_tick(level: SurvivalLevel, _delta: float) -> void:
	if level == null:
		return
	var crowd := ZoneDead.of(level)
	if crowd == null:
		return
	var v := pressure(level)
	if v >= HORDE_AT and Soldier._now() - _horde_at >= HORDE_COOLDOWN_S:
		var point: Variant = pressure_point(level)
		if point is Vector3:
			_horde_at = Soldier._now()
			var n := randi_range(ZoneDead.HORDE_N.x, ZoneDead.HORDE_N.y)
			var made := crowd.server_horde(point, n)
			SessionLog.note("survival: a horde of %d forms at pressure %.0f, %.0f m from (%.0f, %.0f)" % [made, v, ZoneDead.HORDE_FROM_M, point.x, point.z])
			state()["hordes"] = int(state().get("hordes", 0)) + 1


## Host: the crowd a zone starts with: CROWD_SEED about each site (its base type's dead_near
## share), scattered 20-60 m round it; the open country has none (they come with the noise).
func _seed_crowd(level: SurvivalLevel) -> void:
	var crowd := ZoneDead.of(level)
	if crowd == null or crowd.count() > 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(state().get("zone", "")) + "|crowd")
	for m: ZoneModule in level.modules():
		var base := ZoneModules.base(String(m.type))
		var n := roundi(float(DEAD_NEAR.get(base, 0)) / 4.0 * CROWD_SEED / 2.0)
		for i in n:
			var a := rng.randf() * TAU
			var r := rng.randf_range(20.0, 60.0)
			var at := m.global_position + Vector3(cos(a), 0.0, sin(a)) * r
			crowd.server_add(level.ground_point(at), roll_kind(level, at, rng))


## The kind of one of the dead spawned at `at`: a runner RUNNER_SHARE of the time, a special by
## the site's SPECIALS shares, else a walker.
func roll_kind(level: ZoneLevel, at: Vector3, rng: RandomNumberGenerator = null) -> String:
	var r := rng.randf() if rng else randf()
	var m := level.module_at(at) if level else null
	var base := ZoneModules.base(String(m.type)) if m else ""
	var shares: Dictionary = SPECIALS.get(base, {})
	var acc := 0.0
	for kind: String in shares:
		acc += float(shares[kind])
		if r < acc:
			return kind
	return "runner" if r < acc + RUNNER_SHARE else "walker"


# --- The metabolism and sleep (phase A step 5; Needs, SurvivalSleep) -----------------------

## Host: one survival tick of `dt` real seconds in `level`: the clock (at SurvivalSleep.SPEED
## while everyone is asleep), every survivor's body (a sleeper's at SPEED), and who wakes.
func server_tick_survivors(level: Node, dt: float) -> void:
	var players := MapNodes.players(level)
	_advance_clock(dt * SurvivalSleep.clock_mult(players))
	for s: Soldier in players:
		if s.vitals.is_up() and s.respawn_state != Soldier.RESPAWN_WAITING:
			server_drain(s, dt * SurvivalSleep.body_mult(s))
	var sleepers := players.filter(func(p: Soldier) -> bool: return SurvivalSleep.is_asleep(needs_of(p)))
	if not sleepers.is_empty() and SurvivalSleep.chased(level, players):
		for p: Soldier in sleepers:
			_wake(p, "dead")


## Host: after a body's step: the sleeper's hours, a sickness that began showing.
func _after_body_step(s: Soldier, n: Dictionary, seconds: float) -> void:
	var why := SurvivalSleep.after_step(s, n, seconds / (DAY_MIN * 60.0) * 24.0)
	if why != "":
		_wake(s, why)
	if n.has("_announce"):
		_tell(s, String(n._announce))
		n.erase("_announce")


## Host: `s` lies down to sleep for `hours` world hours on `where` ("bed", "bedroll" or
## "ground"; the bed and bedroll pieces are phase B: a dev call or a test says which for now).
## "" or why not (he's told either way).
func server_sleep(s: Soldier, hours: float, where := "ground") -> String:
	var level := CompoundLevel.current(s)
	var problem := SurvivalSleep.start(s, needs_of(s), hours, where, level != null and SurvivalSleep.chased(level, MapNodes.players(level)))
	_tell(s, problem if problem != "" else "You lie down to sleep (moving wakes you)")
	_send_needs(s)
	return problem


## Host: `s` waits at a safe spot (call 136): `mode` "hour", "dusk" or "dawn"; the world runs at
## SurvivalSleep.SPEED while every survivor sleeps or waits, without sleep's restore. "" or why
## not (he's told either way).
func server_wait(s: Soldier, mode: String) -> String:
	var n := needs_of(s)
	var problem := SurvivalSleep.start_wait(s, n, SurvivalSleep.wait_hours(mode, hour()), CompoundLevel.current(s))
	_tell(s, problem if problem != "" else "You wait (moving stops it)")
	_send_needs(s)
	return problem


func _wake(s: Soldier, why: String) -> void:
	SurvivalSleep.wake(needs_of(s))
	var text := SurvivalSleep.wake_text(why)
	if text != "":
		_tell(s, text)
	_send_needs(s)


## Host: `s` ate or drank one `item` (Consumables, after its drug went in; `state` its entry's):
## its food values into his body (Needs.eat), else S1's dose of `drug`. Returns whether it counted.
func server_eat(s: Soldier, item: ItemData, state: Dictionary, drug: StringName, doses: float) -> bool:
	if not running:
		return false
	if not Needs.has_values(item):
		return server_feed(s, drug, doses)
	var n := needs_of(s)
	Needs.eat(n, item, state)
	Needs.apply(s, n)
	_send_needs(s)
	return true


## The body screen (BodyScreen, phase D): someone else's body as last read from the host
## ({target path: the body's Dictionary}).
var read_bodies := {}


## Owner -> host: a body screen action (Body.server_action) on the body at `path` (himself, or
## someone within reach); "read" sends that body's Dictionary back (_client_read_body).
@rpc("any_peer", "call_local", "reliable")
func _server_body_action(path: NodePath, action: String, part: String, arg: String) -> void:
	if not multiplayer.is_server() or not running:
		return
	var level := CompoundLevel.current(self)
	if level == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var actor := level.players.get_node_or_null(str(sender)) as Soldier
	var target := get_node_or_null(path) as Soldier
	if actor == null or target == null or not actor.vitals.is_up():
		return
	if target != actor and actor.global_position.distance_to(target.global_position) > BODY_REACH_M:
		_tell(actor, "Too far away")
		return
	if action == "read":
		var body := needs_of(target).duplicate(true)
		if sender == multiplayer.get_unique_id():
			_client_read_body(path, body)
		elif sender in multiplayer.get_peers():
			_client_read_body.rpc_id(sender, path, body)
		return
	_tell(actor, Body.server_action(actor, target, action, part, arg))
	_send_needs(target)


const BODY_REACH_M := 3.0


@rpc("authority", "call_remote", "reliable")
func _client_read_body(path: NodePath, body: Dictionary) -> void:
	read_bodies[path] = body
	body_changed.emit()


## Host: a line for `s`'s owner (Soldier._client_message: the flash).
func _tell(s: Soldier, text: String) -> void:
	if s.is_ai() or text == "" or not s.is_inside_tree():
		return
	var peer := s.owner_peer()
	if peer == multiplayer.get_unique_id() or peer in multiplayer.get_peers():
		s._client_message.rpc_id(peer, text)


## Owner: his survivor's whole body (Needs), for the HUD's signs and the body readout, and the
## aim sway it leaves him (aiming runs here).
@rpc("authority", "call_remote", "reliable")
func _client_body(body: Dictionary) -> void:
	my_body = body.duplicate(true)
	var level := CompoundLevel.current(self)
	if level:
		var me := level.players.get_node_or_null(str(multiplayer.get_unique_id())) as Soldier
		if me and me.vitals:
			me.vitals.needs_sway = Needs.sway_mult(my_body)
	body_changed.emit()


# --- The living world's hooks (WorldSim, docs/survival_world.md) --------------------------------

## Host: Continue: the far ticks for the time the world sat unhosted (up to 2 world days, call 67).
func _world_continue() -> void:
	WorldSim.server_on_continue()


## Host: a zone is up: the world set up (a new world's groups), its live layer, and the world's own
## lone survivors in this zone put on its ground.
func _world_level_ready(level: SurvivalLevel) -> void:
	WorldSim.server_setup()
	if level.get_node_or_null(NodePath(WorldLive.NODE_NAME)) == null:
		level.add_child(WorldLive.new())
	var zone := String(state().get("zone", ""))
	for rec: Dictionary in (state().get("people", {}) as Dictionary).values():
		if bool(rec.get("y_unset", false)) and String(rec.get("zone", "")) == zone:
			var p := SurvivorPerson.pos_of(rec)
			SurvivorPerson.set_pos(rec, level.ground_point(p))
			SurvivorPerson.set_pos(rec, level.ground_point(p), "home")
			rec.erase("y_unset")


## Host: one of the dead fell (the zone's density for the world, help a group saw).
func _world_dead_down(s: Soldier) -> void:
	var sim := WorldSim.get_sim()
	if sim:
		sim.server_dead_down(s)
