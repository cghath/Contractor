class_name Seasons
extends RefCounted
## The year of Contractor: Fallen (docs/survival_seasons.md; calls 30, 34, 113, 137): four seasons
## of SEASON_DAYS world days on the world clock (Survival.day()), from the New world option
## "season" (spring by default). Static: the state lives in Survival.state()["seasons"] (the last
## season seen, the weather slot rolled, the snow flag, the zones with frozen dead).
##
## - The weather: rolled every WEATHER_SLOT_H world hours from the season's odds (WEATHER) into
##   DayNight from day two (day one's is the cold open's) (winter snow is DayNight's "overcast" with the snow flag; summer's clear afternoons
##   are the heat).
## - Winter: crops stop (farm_yield_x), water freezes (water_frozen, the body lane's flag), the
##   dead slow (dead_pace_mult); under a hard frost (hard_frost: winter nights and the deep middle
##   of it) the dead left outdoors freeze solid: the crowd's heads stand still ("frozen"), live ones
##   can't move or bite and the first hit shatters them (their pool set to nothing, Traps.holds).
## - The spring thaw (call 113): the first spring day every frozen one wakes at once: the hosted
##   zone's frozen heads become a horde walking at the settlement (or the noise), every far zone
##   that froze gets a "thaw" event and its pressure to the horde line (the sim's far horde).
## - Summer: thirst_mult 1.5, spoil_mult 0.5 (food keeps half as long), a wildfire now and then
##   (a world event stub with pressure), the dead a little faster.
## - Planting and harvest (call 34): farm beds are planted in the planting window (spring, the
##   first PLANT_SUMMER_DAYS of summer) with seed packets from the stores, grow, and yield only in
##   the harvest window (summer after that, autumn); a settlement that misses the window has no
##   harvest that year and its stocks only fall through the winter.
## - The groups (bias_options, the world sim's goal scoring): settlers stock up in autumn (forage
##   and work up), raiders strike hardest in autumn, scavengers make for the cities in spring,
##   the enclave patrols more in summer and less in winter; a lit settlement draws raiders.
## Every number here is Proposed.

const ALL: Array[String] = ["spring", "summer", "autumn", "winter"]
const SEASON_DAYS := 10
const START := "spring"
const KEY := "seasons"
## The weather's odds by season ("snow" is DayNight's overcast with the snow flag on).
const WEATHER := {
	"spring": {"clear": 0.35, "overcast": 0.25, "rain": 0.3, "fog": 0.1},
	"summer": {"clear": 0.6, "overcast": 0.2, "rain": 0.1, "storm": 0.1},
	"autumn": {"clear": 0.2, "overcast": 0.3, "rain": 0.35, "fog": 0.1, "storm": 0.05},
	"winter": {"clear": 0.3, "overcast": 0.3, "snow": 0.3, "fog": 0.1},
}
const WEATHER_SLOT_H := 6
## The air (degrees C) by season by day; nights NIGHT_DROP_C colder, snow and heat on top.
const TEMP_C := {"spring": 12.0, "summer": 26.0, "autumn": 10.0, "winter": -4.0}
const NIGHT_DROP_C := 8.0
## The dead's pace: winter's cold, hard frost's crawl, summer's heat.
const WINTER_PACE := 0.75
const FROST_PACE := 0.5
const SUMMER_PACE := 1.1
## Hard frost: winter nights (darkness over FROST_DARK) and the middle of winter all day.
const FROST_DARK := 0.5
const DEEP_WINTER := Vector2i(3, 8)
## The body lane's flags.
const SUMMER_THIRST := 1.5
const SUMMER_SPOIL := 0.5
const WINTER_SPOIL := 2.0
## Farming: the first days of summer still plant; a seed packet plants this many beds.
const PLANT_SUMMER_DAYS := 3
const BEDS_PER_SEED := 2
const SEED_ITEM := "seed_packet"
## A wildfire's chance on a summer day (a world event stub) and its pressure.
const WILDFIRE_CHANCE := 0.15
const WILDFIRE_PRESSURE := 25.0
## The thaw's pressure in a zone that froze (to the horde line).
const THAW_PRESSURE := 85.0
const UPDATE_S := 2.0

## Tests: -1 by the rules, 0 no hard frost, 1 a hard frost now.
static var force_frost := -1
static var _left := 0.0


# --- The calendar --------------------------------------------------------------------------

## The season on world day `day` for a world that woke in `start`.
static func of_day(day: int, start := START) -> String:
	return ALL[posmod(_index(day, start), ALL.size())]


## How many seasons in from the first spring (spring of year 0 is 0).
static func _index(day: int, start: String) -> int:
	var s := ALL.find(start)
	return floori(float(maxi(day, 1) - 1) / SEASON_DAYS) + (s if s >= 0 else 0)


## The season now (Survival.season()).
static func current() -> String:
	return of_day(Survival.day(), start())


## The season the world woke in (the New world option "season").
static func start() -> String:
	var s := Survival.option("season")
	return s if s in ALL else START


## The day of the season (1..SEASON_DAYS).
static func day_in_season() -> int:
	return posmod(maxi(Survival.day(), 1) - 1, SEASON_DAYS) + 1


## The farming year (each spring starts one).
static func year() -> int:
	return floori(float(_index(Survival.day(), start())) / ALL.size())


static func rec() -> Dictionary:
	var st := Survival.state()
	if not st.get(KEY) is Dictionary:
		st[KEY] = {}
	return st[KEY]


# --- What the season does --------------------------------------------------------------------

## Whether a hard frost holds now: winter nights and deep winter.
static func hard_frost() -> bool:
	if force_frost >= 0:
		return force_frost == 1
	if current() != "winter":
		return false
	var d := day_in_season()
	if d >= DEEP_WINTER.x and d <= DEEP_WINTER.y:
		return true
	return DayNight.night_of(Survival.hour()) > FROST_DARK


## The water out of doors is frozen (wells, streams, barrels: the body lane melts snow).
static func water_frozen() -> bool:
	return current() == "winter" and (hard_frost() or day_in_season() >= 2)


## Snow falling or lying (the weather row's flag; winter).
static func snow() -> bool:
	return current() == "winter" and bool(rec().get("snow", false))


## A summer afternoon in the sun.
static func heat() -> bool:
	var dn := DayNight.current()
	return current() == "summer" and Survival.hour() >= 11.0 and Survival.hour() <= 17.0 and (dn == null or dn.weather == "clear")


## The air now (degrees C) for the body lane: the season's, colder by night, snow and heat.
static func temperature_c() -> float:
	var t := float(TEMP_C.get(current(), 12.0)) - NIGHT_DROP_C * DayNight.night_of(Survival.hour())
	if snow():
		t -= 3.0
	if heat():
		t += 6.0
	if hard_frost():
		t = minf(t, -10.0)
	return t


## Thirst's rate (the body lane's Needs): summer 1.5.
static func thirst_mult() -> float:
	return SUMMER_THIRST if current() == "summer" else 1.0


## How long food keeps (the body lane's spoilage): summer 0.5 (half as long), winter 2.
static func spoil_mult() -> float:
	match current():
		"summer":
			return SUMMER_SPOIL
		"winter":
			return WINTER_SPOIL
	return 1.0


## The dead's pace (ZombieAI, ZoneDead): slower in winter, a crawl in a hard frost, quicker in summer.
static func dead_pace_mult() -> float:
	match current():
		"winter":
			return FROST_PACE if hard_frost() else WINTER_PACE
		"summer":
			return SUMMER_PACE
	return 1.0


static func planting_window() -> bool:
	var s := current()
	return s == "spring" or (s == "summer" and day_in_season() <= PLANT_SUMMER_DAYS)


static func harvest_window() -> bool:
	var s := current()
	return (s == "summer" and day_in_season() > PLANT_SUMMER_DAYS) or s == "autumn"


## Host, SettlementJobs.farm: an hour at `beds` farm beds. -1 nothing to do (winter, or nothing
## planted this year, or no seed to plant), 0 the hour went on planting or tending, else the
## yield's multiplier. Planting takes a seed packet from the stores per BEDS_PER_SEED beds.
static func farm_yield_x(_st: Settlement, beds: int) -> float:
	if beds <= 0 or current() == "winter":
		return -1.0
	var d := Settlement.data()
	var crop: Dictionary = d.get("crop", {})
	var planted := int(crop.get("year", -999)) == year() and int(crop.get("beds", 0)) > 0
	if planting_window():
		var want := ceili(float(beds) / BEDS_PER_SEED)
		var have := int(crop.get("beds", 0)) if planted else 0
		if have >= beds:
			return 0.0  # (tending what's in)
		if Settlement.count(SEED_ITEM) <= 0:
			return 0.0 if planted else -1.0
		var seeds := mini(Settlement.count(SEED_ITEM), want - ceili(float(have) / BEDS_PER_SEED))
		Settlement.server_take(SEED_ITEM, maxi(seeds, 1))
		d["crop"] = {"year": year(), "beds": mini(beds, have + maxi(seeds, 1) * BEDS_PER_SEED), "planted_day": Survival.day()}
		return 0.0
	if harvest_window() and planted:
		return float(mini(int(crop.beds), beds)) / float(beds)
	return -1.0


## The world sim's goal scoring (WorldGoals.options, on the worker: reads `m` only): the
## season's biases on `g`'s options `out` (each option's "bias"), and a lit settlement drawing
## the raiders' eye (the players' footprint).
static func bias_options(m: WorldModel, g: Dictionary, out: Array) -> void:
	var s := m.season()
	var kind := String(g.get("kind", ""))
	var lit := float(m.player.get("footprint", 0.0))
	for o: Dictionary in out:
		var k := String(o.get("kind", ""))
		var b := 0.0
		match s:
			"autumn":
				if kind == "settlers" and k in ["forage", "work"]:
					b += 0.25  # stocking up before the winter
				if k == "raid" and kind == "raiders":
					b += 0.35  # they strike hardest before the winter
			"winter":
				if k == "raid":
					b -= 0.1
				if k in ["rest", "defend"]:
					b += 0.1
			"spring":
				if kind == "scavengers" and k == "forage" and String(m.zone(String(o.get("zone", ""))).get("type", "")) in ["city", "town"]:
					b += 0.3  # to the cities with the thaw
			"summer":
				pass
		if kind == "enclave" and k == "patrol":
			b += float({"summer": 0.2, "winter": -0.2}.get(s, 0.0))
		if k == "raid" and String(o.get("target", "")) == "player" and lit > 0.0:
			o["gain"] = float(o.get("gain", 0.0)) * (1.0 + lit / 120.0)
		if b != 0.0:
			o["bias"] = float(o.get("bias", 0.0)) + b


# --- The host's tick ------------------------------------------------------------------------

## Host, every frame from Survival._process: every UPDATE_S the season's work (server_update).
static func server_tick(level: Node, delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = UPDATE_S
	server_update(level)


## Host: the weather slot, a new season (the thaw), the frost on the dead, the far zones that froze.
static func server_update(level: Node) -> void:
	var r := rec()
	var now := current()
	var last := String(r.get("last", ""))
	if last != now:
		r["last"] = now
		if last == "winter" and now == "spring":
			server_thaw(level)
		_world_season(now)
		if last != "":
			Survival._journal_line(String({"spring": "The snow's going: spring.", "summer": "Summer: the days are long and hot.",
				"autumn": "Autumn: the leaves are turning and the nights drawing in.", "winter": "Winter's here."}.get(now, "")))
	var slot := Survival.day() * (24 / WEATHER_SLOT_H) + floori(Survival.hour() / WEATHER_SLOT_H)
	if not r.has("slot") or Survival.day() <= 1:
		r["slot"] = slot  # (day one's weather is the cold open's: ColdOpen)
	elif int(r.get("slot", -1)) != slot:
		r["slot"] = slot
		_roll_weather(slot)
		if Survival.hour() < WEATHER_SLOT_H and now == "summer":
			_wildfire_roll()
	if now == "winter":
		var zones: Dictionary = r.get("frozen_zones", {})
		if hard_frost() and not bool(zones.get("_all", false)):
			for z: String in (WorldSim.section().get("zones", {}) as Dictionary):
				if float(((WorldSim.section().zones as Dictionary)[z] as Dictionary).get("dead", 1.0)) > 0.2:
					zones[z] = true
			zones["_all"] = true
			r["frozen_zones"] = zones
		if hard_frost() and level != null:
			server_freeze(level)


static func _world_season(s: String) -> void:
	WorldTrade.season = s  # (trade's prices by season: the intel lane's hook)
	var sim := WorldSim.get_sim()
	var st := start()
	if sim:
		sim.mutate(func(w: Dictionary) -> void: w["season_start"] = st)
	else:
		WorldSim.section()["season_start"] = st


static func _roll_weather(slot: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(Survival.state().get("seed", 0)), "weather", slot])
	var odds: Dictionary = WEATHER.get(current(), WEATHER.spring)
	var roll := rng.randf()
	var acc := 0.0
	var pick := "clear"
	for w: String in odds:
		acc += float(odds[w])
		if roll < acc:
			pick = w
			break
	server_set_weather(pick)


## Host: the weather now ("snow" is overcast with the snow flag).
static func server_set_weather(w: String) -> void:
	rec()["snow"] = w == "snow"
	rec()["weather"] = w
	var dn := DayNight.current()
	if dn and dn.is_inside_tree() and dn.multiplayer.has_multiplayer_peer() and dn.multiplayer.is_server():
		dn.server_set(Survival.hour(), "overcast" if w == "snow" else w)


static func _wildfire_roll() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(Survival.state().get("seed", 0)), "wildfire", Survival.day()])
	if rng.randf() >= WILDFIRE_CHANCE:
		return
	server_wildfire(rng.randi())


## Host: a wildfire somewhere the players aren't (a world event: smoke on the horizon, pressure up).
static func server_wildfire(pick: int) -> String:
	var zones: Array = WorldModel._sorted((WorldSim.section().get("zones", {}) as Dictionary).keys()).filter(func(z: String) -> bool: return z != WorldSim.hosted_zone())
	if zones.is_empty():
		return ""
	var z := String(zones[posmod(pick, zones.size())])
	var sim := WorldSim.get_sim()
	if sim:
		sim.mutate(func(w: Dictionary) -> void:
			var m := WorldModel.new(w, WorldSim.people(), WorldSim.pressure_section(), WorldSim.world_seed())
			m.now = WorldSim.world_now()
			m.raise_pressure(z, WILDFIRE_PRESSURE)
			m.event(z, "wildfire", [], "a wildfire is burning in %s: smoke for miles" % String(m.zone(z).get("name", z))))
	return z


# --- Frozen dead and the thaw ------------------------------------------------------------------

## Host: under a hard frost the dead out of doors freeze solid: the crowd's heads, and live ones
## outdoors that aren't after anyone. Returns how many froze now.
static func server_freeze(level: Node) -> int:
	var n := 0
	var crowd := ZoneDead.of(level)
	if crowd:
		for d: Dictionary in crowd.dead:
			if bool(d.alive) and not bool(d.get("frozen", false)):
				d["frozen"] = true
				n += 1
	for z: Soldier in Survival.zombies(level):
		var brain := ZombieAI.of(z)
		if z.has_meta(&"frozen") or (brain and brain.mode == ZombieAI.Mode.CHASE):
			continue
		if Throwables.indoors(z.get_world_3d(), z.global_position):
			continue
		freeze(z)
		n += 1
	return n


## One of the dead frozen solid: it stands, and the first hit shatters it.
static func freeze(z: Soldier) -> void:
	z.set_meta(&"frozen", true)
	z.set_meta(&"thaw_pool", z.vitals.undead_pool)
	z.vitals.undead_pool = 0.001  # (any hit takes the rest: shattered)
	z.move_input = Vector2.ZERO


static func thaw(z: Soldier) -> void:
	if not z.has_meta(&"frozen"):
		return
	z.remove_meta(&"frozen")
	z.vitals.undead_pool = float(z.get_meta(&"thaw_pool", Vitals.UNDEAD_POOL))
	z.remove_meta(&"thaw_pool")


## Host: the spring thaw (call 113): every frozen one wakes at once. The hosted zone's frozen heads
## become a horde walking at the settlement (or the zone's noise, or the players); every far zone
## that froze gets the thaw as an event and its pressure to the horde line. Returns the heads woken here.
static func server_thaw(level: Node) -> int:
	var woken := 0
	var target: Variant = null
	if level:
		if Settlement.exists() and Settlement.zone() == String(Survival.state().get("zone", "")):
			target = Settlement.pos()
		else:
			target = Survival.pressure_point(level)
		if target == null:
			var ps := MapNodes.players(level)
			if not ps.is_empty():
				target = (ps[0] as Soldier).global_position
		var crowd := ZoneDead.of(level)
		if crowd:
			for d: Dictionary in crowd.dead:
				if bool(d.get("frozen", false)):
					d.erase("frozen")
					woken += 1
					if target is Vector3:
						d["horde"] = true
						d["target"] = Vector2((target as Vector3).x, (target as Vector3).z)
						d["wait"] = 0.0
			if woken > 0:
				crowd.horde_until = Soldier._now() + 600.0
		for z: Soldier in Survival.zombies(level):
			if z.has_meta(&"frozen"):
				thaw(z)
				woken += 1
				var brain := ZombieAI.of(z)
				if brain and target is Vector3:
					brain.hear(target, ZombieAI.HEAR_RUN)
		if woken > 0 and target is Vector3 and level is ZoneLevel:
			Survival._raise_pressure(level, target, THAW_PRESSURE)
			Survival._journal_line("The thaw: the frozen dead are walking again, %d of them at once." % woken)
			SessionLog.note("survival: the thaw wakes %d of the dead" % woken)
	var r := rec()
	var zones: Dictionary = r.get("frozen_zones", {})
	var here := WorldSim.hosted_zone()
	var far: Array = []
	for z: String in zones:
		if z != "_all" and z != here:
			far.append(z)
	r["frozen_zones"] = {}
	var sim := WorldSim.get_sim()
	if sim and not far.is_empty():
		sim.mutate(func(w: Dictionary) -> void:
			var m := WorldModel.new(w, WorldSim.people(), WorldSim.pressure_section(), WorldSim.world_seed())
			m.now = WorldSim.world_now()
			m.hosted = WorldSim.hosted_zone()
			for z: String in far:
				if m.zones().has(z):
					m.raise_pressure(z, THAW_PRESSURE)
					m.event(z, "thaw", [], "the thaw in %s: the frozen dead are walking" % String(m.zone(z).get("name", z))))
	return woken


## Whether `z` (one of the dead) is frozen solid.
static func frozen(z: Node) -> bool:
	return z != null and z.has_meta(&"frozen")
