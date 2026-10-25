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
const STARTER_KIT: Array = [["knife", 1], ["water_bottle", 1], ["canned_meat", 1], ["chemlight_green", 2], ["pressure_bandage", 2]]
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

var _tick := 0.0
var _send := 0.0
var _save := 0.0
var _clock_s := 0.0  # host: real seconds into the world's current hour


## The world's saved state ("seed", "day", "hour", "zone" (where it's played), "start_zone").
func state() -> Dictionary:
	return Campaign.section(SECTION)


## Host: a new world called `name` from `world_seed`, hosted at its start zone under `main`
## (the session's Main: the menu's parent).
func server_new_world(main: Node, name: String, world_seed: int) -> bool:
	var id := _world_id(name)
	Campaign.campaign_id = PREFIX + id
	Campaign.reset_campaign()
	world = id
	var start := start_zone()
	state().merge({"seed": world_seed, "day": 1, "hour": START_HOUR, "zone": start, "start_zone": start, "name": name}, true)
	return _host_zone(main, start)


## Host: carries on the world `name` (or the newest), where it was left, under `main`.
func server_continue(main: Node, name := "") -> bool:
	var id := _world_id(name) if name != "" else newest_world()
	if id == "":
		return false
	Campaign.campaign_id = PREFIX + id
	if not Campaign.load_campaign():
		return false
	world = id
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


## Host: the world is saved: the world's sections and the zone being played.
func server_save() -> void:
	if not running:
		return
	var level := CompoundLevel.current(self)
	if level is SurvivalLevel:
		for s: Soldier in MapNodes.players(level):
			_store_survivor(s)
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
		s.set_meta(&"needs", {"hunger": 100.0, "thirst": 100.0})
	return s.get_meta(&"needs")


## Stamina recovery's share from these needs (1 fed and watered, less when low).
static func stamina_mult_for(hunger: float, thirst: float) -> float:
	var worst := minf(hunger, thirst)
	if worst >= LOW:
		return 1.0
	return lerpf(EMPTY_STAMINA_MULT, LOW_STAMINA_MULT, worst / LOW)


## Host: `seconds` of a survivor's life: thirst and hunger go down (faster sprinting or heavy),
## and an empty one costs blood.
func server_drain(s: Soldier, seconds: float) -> void:
	var n := needs_of(s)
	var world_days := seconds / (DAY_MIN * 60.0)
	var mult := SPRINT_DRAIN_MULT if s.want_sprint and s.velocity.length() > 3.0 else 1.0
	n.thirst = maxf(0.0, float(n.thirst) - 100.0 * world_days / THIRST_DAYS * mult)
	n.hunger = maxf(0.0, float(n.hunger) - 100.0 * world_days / HUNGER_DAYS * mult)
	s.needs_stamina = stamina_mult_for(float(n.hunger), float(n.thirst))
	var hurt := (EMPTY_DAMAGE * 2.0 if float(n.thirst) <= 0.0 else 0.0) + (EMPTY_DAMAGE if float(n.hunger) <= 0.0 else 0.0)
	if hurt > 0.0 and s.vitals.is_up():
		s.vitals.server_damage(hurt * seconds)


## Host: `s` ate or drank (Consumables): a "water" dose fills thirst, a "ration" hunger. Returns
## whether it counted (survival only).
func server_feed(s: Soldier, drug: StringName, doses: float) -> bool:
	if not running:
		return false
	var n := needs_of(s)
	if drug == &"water":
		n.thirst = minf(100.0, float(n.thirst) + WATER_PER_DOSE * doses)
	elif drug == &"ration":
		n.hunger = minf(100.0, float(n.hunger) + FOOD_PER_DOSE * doses)
	else:
		return false
	s.needs_stamina = stamina_mult_for(float(n.hunger), float(n.thirst))
	_send_needs(s)
	return true


func _send_needs(s: Soldier) -> void:
	if s.is_ai():
		return
	var n := needs_of(s)
	var peer := s.owner_peer()
	if peer == multiplayer.get_unique_id():
		_client_needs(float(n.hunger), float(n.thirst), s.needs_stamina)
	elif peer in multiplayer.get_peers():
		_client_needs.rpc_id(peer, float(n.hunger), float(n.thirst), s.needs_stamina)


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
		_advance_clock(dt)
		for s: Soldier in MapNodes.players(level):
			if s.vitals.is_up() and s.respawn_state != Soldier.RESPAWN_WAITING:
				server_drain(s, dt)
	_pop += delta
	if _pop >= POP_TICK_S:
		_pop = 0.0
		_populate(level as SurvivalLevel)
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
	server_give_starter_kit(s)
	var n := needs_of(s)
	n.hunger = RESPAWN_NEEDS
	n.thirst = RESPAWN_NEEDS
	s.needs_stamina = 1.0
	_send_needs(s)
	SessionLog.note("survival: %s died at (%.0f, %.0f); %d things left there; back with the starter kit" % [s.log_name(), at.x, at.z, entries.size()])


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
	all[profile_of(s)] = {"zone": String(state().get("zone", "")), "pos": [p.x, p.y, p.z], "needs": needs_of(s).duplicate(), "kit": entries}


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
	if saved.is_empty():
		server_give_starter_kit(s)
	else:
		for e: Dictionary in saved.get("kit", []):
			s.inventory.take(StringName(e.id), int(e.get("count", 1)), GameState.from_json(e.get("state", {})))
		var n := needs_of(s)
		n.hunger = float((saved.get("needs", {}) as Dictionary).get("hunger", 100.0))
		n.thirst = float((saved.get("needs", {}) as Dictionary).get("thirst", 100.0))
	s.needs_stamina = stamina_mult_for(float(needs_of(s).hunger), float(needs_of(s).thirst))
	_send_needs(s)


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
	var n := float(DEAD_NEAR.get(base, DEAD_NEAR.get("", 2)))
	return roundi(n * (1.0 - thinned(pos)))


## How much of a cell's dead the survivors have killed off (0 untouched .. 1 cleared), healed by
## the days since.
func thinned(pos: Vector3) -> float:
	var cells: Dictionary = (state().get("thinned", {}) as Dictionary).get(String(state().get("zone", "")), {})
	var c: Variant = cells.get(_cell_key(pos))
	if not c is Dictionary:
		return 0.0
	var days := (day() + hour() / 24.0) - float(c.at)
	return clampf(float(c.v) - days / REFILL_DAYS, 0.0, 1.0)


func _cell_key(pos: Vector3) -> String:
	return "%d,%d" % [floori(pos.x / CELL_M), floori(pos.z / CELL_M)]


## Host: one of the dead fell at `pos`: its cell thins.
func _on_zombie_died(s: Soldier) -> void:
	var zone := String(state().get("zone", ""))
	var all: Dictionary = state().get("thinned", {})
	var cells: Dictionary = all.get(zone, {})
	var now := day() + hour() / 24.0
	cells[_cell_key(s.global_position)] = {"v": minf(1.0, thinned(s.global_position) + KILL_THIN), "at": now}
	all[zone] = cells
	state()["thinned"] = all
	state()["kills"] = int(state().get("kills", 0)) + 1


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
			var z := server_spawn_zombie(level, at, "runner" if randf() < RUNNER_SHARE else "walker")
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


## Host: a noise at `pos` (a shot, a door, a car: Soldier's shots) heard by the dead within
## `radius`.
func server_noise(source: Node, pos: Vector3, radius: float) -> void:
	if not running or source == null:
		return
	var level := CompoundLevel.current(source)
	if not level is SurvivalLevel:
		return
	for z: Soldier in zombies(level):
		if z.global_position.distance_to(pos) <= radius:
			var brain := ZombieAI.of(z)
			if brain:
				brain.hear(pos)
