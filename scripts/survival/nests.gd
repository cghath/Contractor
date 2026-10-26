class_name DeadNests
extends RefCounted
## Nests and roosts (docs/survival_deadtime.md; survival.md call 115). Static; the state lives in
## Survival.state()["nests"][zone][id], ticked by the host from ZoneDead (TICK_S).
##
## The dead gather in dark places by day: one nest a site of a NEST_SITES base type (a church, a
## factory, a garage, an office, a school, the military's barracks; in a generated town its
## warehouse when it has one, else its middle), holding NEST_N heads (the "dead" option scales it).
## - **By day** the heads are inside, a count and nothing drawn: the site's dead about it outside
##   are fewer (outside_mult: Survival.dead_near). A quiet town by day is a trap at night.
## - **At dusk** (DUSK_H) they pour out: ZoneDead heads put down at the nest's door, a few at a
##   time (POUR_S apart), walking out POUR_M round it; tagged with the nest.
## - **At dawn** (DAWN_H) the tagged heads walk back in and are counted in again (any still out
##   BACK_H later go in at once).
## - **Entering a nest by day** (a player within ENTER_M of its door) finds them dormant: bodies
##   packed about the door (PACK_M), idle, their sight and hearing dulled (ZombieAI.dormant): a
##   silent kill is possible; a loud noise (a shot, a scream: the screamer special) or one of them
##   seeing him wakes them all at once (wake()).
## - **Clearing a nest** (every head of it dead) marks it cleared with the payoff: its loot
##   untouched (the "bonus" flag: loot_bonus(), a loot pass reads it), a journal line; it refills
##   slowly (REFILL_PER_DAY a world day, slower where the zone's cells are thinned).
## Every number here is Proposed.

const KEY := "nests"
const TICK_S := 2.0
## Sites that hold a nest, and how many heads.
const NEST_SITES := {"church": 14, "mosque": 12, "factory": 12, "school": 10, "garage": 8, "office": 8, "warehouse": 12,
	"town": 10, "hq": 10, "qrf_base": 8, "fuel_depot": 6, "harbour": 8, "airfield": 8}
const DAWN_H := 6.0
const DUSK_H := 19.5
const BACK_H := 2.0
const POUR_S := 0.4
const POUR_M := Vector2(12.0, 35.0)
const ABSORB_M := 3.0
const ENTER_M := 15.0
const PACK_M := 3.0
const REFILL_PER_DAY := 2.0
const OUTSIDE_BY_DAY := 0.5

## Tests: an hour to use instead of the clock's (-1 the clock).
static var force_hour := -1.0
static var _left := 0.0


static func all() -> Dictionary:
	var st := Survival.state()
	if not st.get(KEY) is Dictionary:
		st[KEY] = {}
	var zone := String(st.get("zone", ""))
	var by_zone: Dictionary = st[KEY]
	if not by_zone.get(zone) is Dictionary:
		by_zone[zone] = {}
	return by_zone[zone]


static func get_nest(id: String) -> Dictionary:
	return all().get(id, {})


static func hour() -> float:
	return force_hour if force_hour >= 0.0 else Survival.hour()


## Whether the dead keep to their nests now (by day).
static func by_day() -> bool:
	var h := hour()
	return h >= DAWN_H and h < DUSK_H


static func door(rec: Dictionary) -> Vector3:
	return Vector3(float(rec.x), float(rec.get("y", 0.0)), float(rec.z))


# --- Seeding --------------------------------------------------------------------------------------

## Host: the zone's nests, one per NEST_SITES module (kept once made). Returns how many there are.
static func server_seed(level: Node) -> int:
	var zl := level as ZoneLevel
	if zl == null:
		return 0
	var nests := all()
	for m: ZoneModule in zl.modules():
		var id := "nest_" + m.module_id
		if nests.has(id):
			continue
		var base := ZoneModules.base(String(m.type))
		var at := m.global_position
		var site := base
		if base == "town":
			var lots: Array = (ZoneModules._towns.get(String(m.type), {}) as Dictionary).get("lots", [])
			for lot: Array in lots:
				if String(lot[0]) == "warehouse":
					at = m.global_position + (lot[1] as Vector3)
					site = "warehouse"
					break
		if not NEST_SITES.has(site):
			continue
		var cap := maxi(1, roundi(float(NEST_SITES[site]) * Survival.option_mult("dead")))
		var g := zl.ground_point(at)
		nests[id] = {"x": g.x, "y": g.y, "z": g.z, "site": site, "module": m.module_id, "cap": cap, "n": cap, "out": false,
			"inside": 0, "cleared": false, "bonus": false, "day": Survival.day()}
	return nests.size()


## Host: a nest at `at` by hand (tests, a story beat): `n` heads. Returns its id.
static func server_add(level: Node, id: String, at: Vector3, n: int, site := "warehouse") -> String:
	var g := (level as ZoneLevel).ground_point(at) if level is ZoneLevel else at
	all()[id] = {"x": g.x, "y": g.y, "z": g.z, "site": site, "module": "", "cap": n, "n": n, "out": false, "inside": 0,
		"cleared": false, "bonus": false, "day": Survival.day()}
	return id


# --- The tick ------------------------------------------------------------------------------------

## Host, ZoneDead every physics frame: the nests every TICK_S.
static func server_process(level: Node, delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = TICK_S
	server_tick(level)


static func server_tick(level: Node) -> void:
	if not Survival.running or not level is ZoneLevel:
		return
	var nests := all()
	if not bool(Survival.state().get("nests_seeded_" + String(Survival.state().get("zone", "")), false)):
		server_seed(level)
		Survival.state()["nests_seeded_" + String(Survival.state().get("zone", ""))] = true
	var day := by_day()
	var players := MapNodes.players(level).filter(func(p: Soldier) -> bool: return p.vitals.is_up())
	for id: String in nests:
		var rec: Dictionary = nests[id]
		_refill(rec)
		if not day:
			if not bool(rec.out):
				server_pour(level, id)
			continue
		if bool(rec.out):
			_recall(level, id, rec)
			continue
		if int(rec.n) > 0:
			var at := door(rec)
			if players.any(func(p: Soldier) -> bool: return p.global_position.distance_to(at) <= ENTER_M):
				server_enter(level, id)


## Host: dusk (or a nest woken): the heads inside pour out at its door, a few at a time, walking
## out round it; the dormant bodies wake. Returns the heads put out.
static func server_pour(level: Node, id: String, toward: Variant = null) -> int:
	var rec := get_nest(id)
	var crowd := ZoneDead.of(level)
	if rec.is_empty() or crowd == null:
		return 0
	rec.out = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([id, Survival.day(), "pour"])
	var at := door(rec)
	var put := 0
	for i in int(rec.n):
		var a := rng.randf() * TAU
		var kind := Survival.roll_kind(level as ZoneLevel, at, rng)
		if not crowd.server_add(at + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.5, 2.0), kind, false, {"nest": id}):
			break
		var d: Dictionary = crowd.dead[crowd.dead.size() - 1]
		var r := rng.randf_range(POUR_M.x, POUR_M.y)
		var out := Vector2(at.x, at.z) + Vector2(cos(a), sin(a)) * r
		if toward is Vector3:
			out = Vector2((toward as Vector3).x, (toward as Vector3).z)
		d.to = out
		d.wait = i * POUR_S + 0.01
		put += 1
	rec.n = int(rec.n) - put
	for z: Soldier in bodies(level, id):
		var brain := ZombieAI.of(z)
		if brain and brain.dormant:
			brain.dormant = false
	if put > 0:
		SessionLog.note("survival: %d of the dead pour out of %s (%s)" % [put, id, String(rec.site)])
	return put


## Host: dawn: the nest's heads walk back to the door and are counted in.
static func _recall(level: Node, id: String, rec: Dictionary) -> void:
	var crowd := ZoneDead.of(level)
	var at := door(rec)
	var flat := Vector2(at.x, at.z)
	var all_in := hour() >= DAWN_H + BACK_H
	var left := 0
	if crowd:
		var i := 0
		while i < crowd.dead.size():
			var d: Dictionary = crowd.dead[i]
			if String(d.get("nest", "")) != id or not bool(d.alive):
				i += 1
				continue
			if all_in or (d.pos as Vector2).distance_to(flat) <= ABSORB_M:
				crowd.dead.remove_at(i)
				rec.n = int(rec.n) + 1
				continue
			d.erase("to")
			d.target = flat
			d.wait = 0.0
			d.horde = true  # (walks back at a horde's pace)
			left += 1
			i += 1
	if left == 0:
		rec.out = false


## Host: a player came in by day: the heads inside as bodies, packed by the door, dormant (as
## many as LIVE_CAP leaves room for). Returns the bodies made.
static func server_enter(level: Node, id: String) -> int:
	var rec := get_nest(id)
	if rec.is_empty() or int(rec.n) <= 0:
		return 0
	var room := Survival.LIVE_CAP - Survival.zombies(level).size()
	var n := mini(int(rec.n), room)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([id, Survival.day(), "enter"])
	var at := door(rec)
	var made := 0
	for i in n:
		var a := rng.randf() * TAU
		var p := at + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.3, PACK_M)
		var kind := Survival.roll_kind(level as ZoneLevel, p, rng)
		var z := Survival.server_spawn_zombie(level as CompoundLevel, p, kind, {"nest": id, "dormant": true})
		if z:
			z.rotation.y = rng.randf() * TAU
			made += 1
	rec.n = int(rec.n) - made
	rec.inside = int(rec.inside) + made
	if made > 0:
		SessionLog.note("survival: %d of the dead lie dormant in %s" % [made, id])
	return made


## The living bodies of nest `id`.
static func bodies(level: Node, id: String) -> Array:
	return Survival.zombies(level).filter(func(z: Soldier) -> bool: return String(z.get_meta(&"dead_nest", "")) == id)


## Host: a dormant one of nest `id` saw or heard enough: they all wake, toward `at` (Vector3 or
## null); the heads still inside pour out after them.
static func wake(level: Node, id: String, at: Variant) -> int:
	var woken := 0
	for z: Soldier in bodies(level, id):
		var brain := ZombieAI.of(z)
		if brain == null or not brain.dormant:
			continue
		brain.dormant = false
		woken += 1
		if at is Vector3:
			brain.hear(at as Vector3, ZombieAI.HEAR_SHOT)
	var rec := get_nest(id)
	if not rec.is_empty() and int(rec.n) > 0:
		server_pour(level, id, at)
	if woken > 0:
		SessionLog.note("survival: nest %s wakes (%d)" % [id, woken])
	return woken


## How many of nest `id` are about: inside, out in the crowd, and as bodies.
static func alive(level: Node, id: String) -> int:
	var rec := get_nest(id)
	var n := int(rec.get("n", 0)) + bodies(level, id).size()
	var crowd := ZoneDead.of(level)
	if crowd:
		for d: Dictionary in crowd.dead:
			if bool(d.alive) and String(d.get("nest", "")) == id:
				n += 1
	return n


## Host (Survival._on_zombie_died): one of a nest down; the last of it clears the nest.
static func on_died(s: Soldier) -> void:
	var id := String(s.get_meta(&"dead_nest", ""))
	if id == "":
		return
	var rec := get_nest(id)
	if rec.is_empty():
		return
	if s.has_meta(&"nest_inside"):
		rec.inside = maxi(int(rec.inside) - 1, 0)
	var level := CompoundLevel.current(s)
	if level == null or bool(rec.cleared):
		return
	var left := alive(level, id) - (1 if Survival.zombies(level).has(s) else 0)
	if left <= 0:
		rec.cleared = true
		rec.bonus = true
		rec.n = 0
		rec.cleared_day = Survival.day()
		rec.day = Survival.day()
		Survival._journal_line("We cleared the nest at the %s. Whatever they sat on in there is still there." % String(rec.site).replace("_", " "))
		SessionLog.note("survival: nest %s cleared" % id)


## Host (Survival._populate): a body of a nest gone far from everyone by day goes back in.
## False when it isn't one (or it's night: it goes back into the crowd).
static func server_back(z: Soldier) -> bool:
	var id := String(z.get_meta(&"dead_nest", ""))
	if id == "" or not by_day():
		return false
	var rec := get_nest(id)
	if rec.is_empty():
		return false
	rec.n = int(rec.n) + 1
	if z.has_meta(&"nest_inside"):
		z.remove_meta(&"nest_inside")
		rec.inside = maxi(int(rec.inside) - 1, 0)
	return true


## A day's refill (slower where the zone's cells round it are thinned: Survival.thinned).
static func _refill(rec: Dictionary) -> void:
	var today := Survival.day()
	var days := today - int(rec.get("day", today))
	if days <= 0:
		return
	rec.day = today
	var room := int(rec.cap) - int(rec.n) - int(rec.inside)
	if room <= 0 or bool(rec.out):
		return
	var add := mini(room, floori(days * REFILL_PER_DAY * (1.0 - Survival.thinned(door(rec)) * 0.75) + 0.5))
	rec.n = int(rec.n) + add


# --- What other systems read ---------------------------------------------------------------------

## The cleared nest's payoff: its loot untouched (a loot pass doubles it: Proposed) until taken.
static func loot_bonus(id: String) -> bool:
	return bool(get_nest(id).get("bonus", false))


static func take_bonus(id: String) -> bool:
	var rec := get_nest(id)
	if not bool(rec.get("bonus", false)):
		return false
	rec.bonus = false
	return true


## Survival.dead_near: by day the dead about a site with a full nest sit inside (fewer outside).
static func outside_mult(m: ZoneModule) -> float:
	if m == null or not by_day():
		return 1.0
	var rec := get_nest("nest_" + m.module_id)
	return OUTSIDE_BY_DAY if not rec.is_empty() and int(rec.n) + int(rec.inside) > 0 else 1.0
