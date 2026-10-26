class_name Wildfire
extends RefCounted
## Fire that spreads (docs/survival_nature.md; call 107; the summer wildfire Seasons rolled is real
## now). Host, static: the hosted zone's fire is a grid of CELL_M cells (`cells`: Vector2i ->
## {"s": "burning" or "burnt", "t": seconds burning}), ticked every Nature.FIRE_TICK_S:
## - **Spreading**: each burning cell heats its eight neighbours by SPREAD a second times the
##   dryness (dryness: summer 1, autumn 0.5, spring 0.3, winter and any rain or snow 0), the
##   neighbour's fuel (fuel_at: grass 1 on open ground, more with the scatter's trees, scrub and
##   thickets, nothing on water, roads, fields, the sea or a firebreak) and the wind (DayNight.wind:
##   downwind up to WIND_X more, upwind down to UPWIND_MIN); a neighbour at CATCH_AT heat catches. A
##   cell burns BURN_S a unit of fuel, then it's burnt (never again this fire).
## - **Stopping**: rain or snow puts every burning cell out (dryness 0); a firebreak (server_clear:
##   cleared ground) never catches.
## - **What burns**: wood blocks of the builds in a burning cell lose BLOCK_HP_S a second
##   (Builder.server_damage); the living in one take BURN_DAMAGE_S trauma; the dead catch fire
##   (set_alight) and keep walking, their pool burning down BURN_POOL_S a second till they drop.
## - **Smoke** draws the dead and the groups: every SMOKE_S the zone's pressure rises at the fire
##   (SMOKE_PRESSURE by its size), and the world sim hears of it once a fire (an event, pressure).
## - **Starting**: server_ignite (a molotov when one comes, a campfire's spark: campfire_risk), and
##   Seasons' summer roll lights one (server_natural) away from the players.
## Every number here is Proposed.

const CELL_M := 8.0
const SPREAD := 0.12
const CATCH_AT := 1.0
const WIND_X := 1.6
const UPWIND_MIN := 0.1
const BURN_S := 40.0
const TREE_FUEL := 0.25
const SCRUB_FUEL := 0.1
const FUEL_MAX := 3.0
const CAP := 600
const BLOCK_HP_S := 0.05
const BURN_DAMAGE_S := 2.0
const BURN_POOL_S := 0.5
const BURN_S_ON_BODY := 40.0
const SMOKE_S := 30.0
const SMOKE_PRESSURE := 4.0
const SMOKE_EVENT_PRESSURE := 20.0
const NATURAL_M := Vector2(150.0, 400.0)
const CAMPFIRE_CHANCE_H := 0.02

## Host: the hosted zone's fire.
static var cells := {}
static var heat := {}
static var breaks := {}
## Tests: the wind and the dryness to use (Vector3.INF / -1: the weather's and the season's).
static var force_wind := Vector3.INF
static var force_dry := -1.0
static var _smoke := 0.0
static var _event_told := false
static var _fuel_cache := {}


static func forget() -> void:
	cells.clear()
	heat.clear()
	breaks.clear()
	_fuel_cache.clear()
	_event_told = false


static func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_M), floori(pos.z / CELL_M))


static func centre_of(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL_M, (c.y + 0.5) * CELL_M)


## How dry the land is now (0 nothing burns .. 1 tinder).
static func dryness() -> float:
	if force_dry >= 0.0:
		return force_dry
	var dn := DayNight.current()
	if dn and dn.weather in ["rain", "storm"]:
		return 0.0
	if Seasons.snow():
		return 0.0
	match Seasons.current():
		"summer":
			return 1.0 if Seasons.heat() else 0.8
		"autumn":
			return 0.5
		"spring":
			return 0.3
	return 0.0


static func wind() -> Vector3:
	return force_wind if force_wind != Vector3.INF else DayNight.wind()


## The fuel in cell `c` (0 none: water, a road, a field, the sea, a firebreak).
static func fuel_at(level: Node, c: Vector2i) -> float:
	if breaks.has(c):
		return 0.0
	if _fuel_cache.has(c):
		return float(_fuel_cache[c])
	var f := 0.0
	var zl := level as ZoneLevel
	var p := centre_of(c)
	if zl and zl.terrain:
		var t := zl.terrain
		var half := t.size_m * 0.5
		var none: Array[Rect2] = []
		if absf(p.x) < half and absf(p.y) < half and not (t.sea_side >= 0 and t.height_at(p.x, p.y) < t.sea_level + 0.3) \
				and not (zl.scatter and zl.scatter._cover_blocked(p.x, p.y, none)):
			f = 1.0
			if zl.scatter:
				var sc := zl.scatter
				for i: int in sc._cells.get(sc._cell_of(p.x, p.y), []):
					var item: Dictionary = sc.items[i]
					var q: Vector3 = item.pos
					if cell_of(q) != c:
						continue
					match int(item.kind):
						ZoneScatter.Kind.TREE:
							f += TREE_FUEL * (0.3 if item.has("felled") else 1.0)
						ZoneScatter.Kind.SCRUB, ZoneScatter.Kind.THICKET:
							f += SCRUB_FUEL
	elif level != null:
		f = 1.0
	f = minf(f, FUEL_MAX)
	_fuel_cache[c] = f
	return f


static func burning(c: Vector2i) -> bool:
	return String((cells.get(c, {}) as Dictionary).get("s", "")) == "burning"


static func burnt(c: Vector2i) -> bool:
	return String((cells.get(c, {}) as Dictionary).get("s", "")) == "burnt"


static func burning_count() -> int:
	var n := 0
	for c: Vector2i in cells:
		if String(cells[c].s) == "burning":
			n += 1
	return n


## Host: cell `c` (or the cell at a position) cleared: a firebreak.
static func server_clear(c: Vector2i) -> void:
	breaks[c] = true
	_fuel_cache.erase(c)


## Host: fire at `pos` (`cause`: "molotov", "campfire", "lightning", ...). Whether it caught.
static func server_ignite(level: Node, pos: Vector3, cause := "fire") -> bool:
	var c := cell_of(pos)
	if burning(c) or burnt(c) or fuel_at(level, c) <= 0.0 or cells.size() >= CAP:
		return false
	if dryness() <= 0.0 and cause != "molotov":
		return false
	cells[c] = {"s": "burning", "t": 0.0}
	if cells.size() == 1:
		_event_told = false
		_smoke = SMOKE_S  # (the first smoke at once)
	SessionLog.note("survival: fire at (%.0f, %.0f) from %s" % [pos.x, pos.z, cause])
	return true


## Host: a lit campfire's hour at `pos`: in dry weather its sparks may catch the grass. Whether it did.
static func campfire_risk(level: Node, pos: Vector3, roll := -1.0) -> bool:
	var r := roll if roll >= 0.0 else randf()
	if r < CAMPFIRE_CHANCE_H * dryness():
		return server_ignite(level, pos + Vector3(CELL_M, 0, 0), "campfire")
	return false


## Host (Seasons' summer roll): a fire lit away from the players (lightning, a glass in the sun).
static func server_natural(pick: int) -> bool:
	var level := CompoundLevel.current(Survival)
	if not level is SurvivalLevel:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = pick
	var ps := MapNodes.players(level)
	var from := (ps[0] as Soldier).global_position if not ps.is_empty() else Vector3.ZERO
	var a := rng.randf() * TAU
	var at := from + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(NATURAL_M.x, NATURAL_M.y)
	return server_ignite(level, at, "the summer")


## Host: a body of the dead set alight: it burns BURN_S_ON_BODY and keeps walking.
static func set_alight(z: Soldier) -> void:
	if z and z.vitals and z.vitals.is_up():
		z.set_meta(&"burning_until", Soldier._now() + BURN_S_ON_BODY)


static func alight(z: Node) -> bool:
	return z != null and float(z.get_meta(&"burning_until", -1.0)) > Soldier._now()


## Host, every Nature.FIRE_TICK_S: the fire spreads, burns out, burns what's in it; the burning dead burn.
static func server_tick(level: Node, dt: float) -> void:
	_burn_bodies(level, dt)
	if cells.is_empty():
		return
	var dry := dryness()
	if dry <= 0.0:
		var out := 0
		for c: Vector2i in cells:
			if String(cells[c].s) == "burning":
				cells[c].s = "burnt"
				out += 1
		if out > 0:
			Survival._journal_line("The rain puts the fire out.")
		return
	var w := wind()
	var wdir := Vector2(w.x, w.z)
	var wspeed := wdir.length()
	wdir = wdir.normalized() if wspeed > 0.01 else Vector2.ZERO
	var lit: Array[Vector2i] = []
	var any := false
	for c: Vector2i in cells.keys():
		var rec: Dictionary = cells[c]
		if String(rec.s) != "burning":
			continue
		any = true
		rec.t = float(rec.t) + dt
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var n := c + Vector2i(dx, dz)
				if cells.has(n):
					continue
				var f := fuel_at(level, n)
				if f <= 0.0:
					continue
				var dir := Vector2(dx, dz).normalized()
				var wf := clampf(1.0 + WIND_X * dir.dot(wdir) * minf(wspeed / 5.0, 1.5), UPWIND_MIN, 3.0)
				var h := float(heat.get(n, 0.0)) + SPREAD * dt * dry * f * wf / (1.414 if dx != 0 and dz != 0 else 1.0)
				heat[n] = h
				if h >= CATCH_AT and not n in lit:
					lit.append(n)
		if float(rec.t) >= BURN_S * maxf(fuel_at(level, c), 0.5):
			rec.s = "burnt"
	for n: Vector2i in lit:
		if cells.size() < CAP:
			cells[n] = {"s": "burning", "t": 0.0}
			heat.erase(n)
	if not any:
		return
	_burn_things(level, dt)
	_smoke += dt
	if _smoke >= SMOKE_S:
		_smoke = 0.0
		_smoke_draws(level)


## Every burning cell's middle on the ground [x, y, z] (Nature's packet).
static func packed() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var level := CompoundLevel.current(Survival)
	for c: Vector2i in cells:
		if String(cells[c].s) != "burning":
			continue
		var p := centre_of(c)
		var y := (level as ZoneLevel).ground_height(p.x, p.y) if level is ZoneLevel else 0.0
		out.append_array(PackedFloat32Array([p.x, y, p.y]))
	return out


static func _burn_things(level: Node, dt: float) -> void:
	var b: Builder = Builder.find(level) if level else null
	if b:
		for c: Vector3i in b.blocks.keys():
			var rec: Dictionary = b.blocks[c]
			if String(rec.get("m", "")) != "wood" or not b.is_built(c):
				continue
			if burning(cell_of(BuildPieces.cell_centre(c))):
				b.server_damage(c, BLOCK_HP_S * dt)
	if level == null or not level.is_inside_tree():
		return
	for n in level.get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or not s.vitals.is_up() or not burning(cell_of(s.global_position)):
			continue
		if s.faction == ZombieAI.INFECTED:
			set_alight(s)
		else:
			s.vitals.server_damage(BURN_DAMAGE_S * dt)


## The dead alight burn down (they keep walking: nothing here touches their brain).
static func _burn_bodies(level: Node, dt: float) -> void:
	if level == null or not level.is_inside_tree():
		return
	for z: Soldier in Survival.zombies(level):
		if not alight(z) or not z.vitals.is_up():
			continue
		burn_step(z, dt)


static func burn_step(z: Soldier, dt: float) -> void:
	z.vitals.undead_pool -= BURN_POOL_S * dt
	if z.vitals.undead_pool <= 0.0:
		z.vitals.last_cause = {"cause": "burnt"}
		z.vitals.server_kill()


## Smoke over the fire: the zone's pressure there, and once a fire the world sim's event.
static func _smoke_draws(level: Node) -> void:
	var n := 0
	var sum := Vector2.ZERO
	for c: Vector2i in cells:
		if String(cells[c].s) == "burning":
			n += 1
			sum += centre_of(c)
	if n == 0:
		return
	var mid := sum / n
	var at := Vector3(mid.x, (level as ZoneLevel).ground_height(mid.x, mid.y) if level is ZoneLevel else 0.0, mid.y)
	if level is ZoneLevel:
		Survival._raise_pressure(level, at, SMOKE_PRESSURE * clampf(n / 10.0, 0.5, 3.0))
	if _event_told:
		return
	_event_told = true
	Survival._journal_line("Smoke over the trees: a fire's burning. Everything for miles will see it.")
	var zone := Nature.zone()
	var sim := WorldSim.get_sim()
	if sim and zone != "":
		sim.mutate(func(w: Dictionary) -> void:
			var m := WorldModel.new(w, WorldSim.people(), WorldSim.pressure_section(), WorldSim.world_seed())
			m.now = WorldSim.world_now()
			if m.zones().has(zone):
				m.raise_pressure(zone, SMOKE_EVENT_PRESSURE)
				m.event(zone, "wildfire", [], "smoke over %s: a fire is burning" % String(m.zone(zone).get("name", zone))))
