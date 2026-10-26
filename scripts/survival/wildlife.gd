class_name Wildlife
extends RefCounted
## The wild animals of Contractor: Fallen (docs/survival_nature.md; calls 42, 100, 103): deer,
## boar, rabbits, flocks of birds, wolf and feral dog packs in the hills, a bear in deep woods,
## raccoons at the stores (data/survival_fauna.json). Host only, static: the hosted zone's animals
## are records (`animals`), laid out when the zone comes up (server_populate: by habitat and the
## season's range, Migration) and walked here every Nature.TICK_S; Nature draws them on every peer
## and gives each a hit box.
##
## - **Fear** (call 100): prey keeps fear_living_m from the living (half for a crouched, slow man)
##   and fear_dead_m from the dead and runs from both, and from a noise (server_noise: Survival's
##   shots, doors, engines) inside its radius; a herd runs together, and a running herd or a lifted
##   flock is a tell: a companion near says so, else the nearest player within TELL_M is told
##   (`last_tell`).
## - **The dead hunt animals** (ZombieAI calls zombie_hunt when it sees nobody): one goes after a
##   live animal it sees within PREY_SEE_M, bites it down in reach, and walks to a carcass or blood
##   it smells (smell_sources: every carcass and butchering's blood); the crowd's heads within
##   CROWD_SMELL_M of one drift to it (server_slow).
## - **Hunting**: a round kills (server_shot; a bear takes more); a quiet kill (a suppressed rifle or
##   a bow when bows come) only scares what hears it (the shot's own noise radius). Snares
##   (server_set_snare, the "snare" item) catch rabbits over the world's hours (server_snare_hours:
##   fieldcraft helps); tracking (fieldcraft 3: tracks_for) gives the nearest animal's trail;
##   butchering (server_butcher, a blade) gives raw meat and hide and leaves blood the dead smell.
## - **Predators** (Predators) and **infected animals** (InfectedAnimals) walk in the same records.
## - **The hunter's calendar** (calendar: fieldcraft 2, a field guide; fish from fieldcraft 4).
## Every number here is Proposed.

const CAP := 64
const KEEP_M := 150.0
const HOME_R := 30.0
const WAIT_S := Vector2(2.0, 8.0)
const FLEE_M := 70.0
const FLEE_S := 12.0
## A crouched or prone man moving slowly is noticed this much closer.
const STEALTH_X := 0.5
const SLOW_MPS := 1.6
const TELL_M := 200.0
const TELL_GAP_S := 45.0
const COMPANION_TELL_M := 60.0
## The dead and their prey.
const PREY_SEE_M := 20.0
const PREY_NIGHT_M := 12.0
const BITE_M := 1.6
const SMELL_M := 40.0
const CROWD_SMELL_M := 60.0
## Tracks: a mark every TRAIL_STEP_M, the last TRAIL_N, seen from TRACK_M.
const TRAIL_STEP_M := 8.0
const TRAIL_N := 10
const TRACK_M := 250.0
## Butchering and the carcass (world hours).
const BUTCHER_M := 2.5
const BLOOD_H := 6.0
const CARCASS_H := 72.0
## Snares: a catch's chance a world hour (rabbits about), up FIELDCRAFT_X a fieldcraft level.
const SNARE_CHANCE_H := 0.06
const SNARE_FIELDCRAFT_X := 0.15
const SNARE_M := 3.0
## Tests: a roll to use instead of the rng (-1: roll for real).
static var force_roll := -1.0

## Host: the hosted zone's animals: {"id", "sp", "pos" (Vector2), "y", "face", "home" (Vector2),
## "herd" (int), "state" ("idle", "walk", "flee", "hunt", "dead"), "target" (Vector2), "wait",
## "alive", "hp", "infected", "until" (real s), "trail" (Array of Vector2), "dead_h" (world h),
## "meat", "hide" (left on it), "prey" (what it hunts: Node or a ZoneAnimals index)}.
static var animals: Array[Dictionary] = []
static var zone_id := ""
## Host: blood where something was butchered: {"pos": Vector3, "until_h"}.
static var blood: Array[Dictionary] = []
## The last tell: {"pos", "sp", "line", "at"} (tests and the companion's line).
static var last_tell := {}
static var _told := {}  # herd -> real s
static var _next_id := 1
static var _rng := RandomNumberGenerator.new()


static func data() -> Dictionary:
	return Nature.fauna().get("species", {})


static func spec(sp: String) -> Dictionary:
	return data().get(sp, {})


static func kind_of(a: Dictionary) -> String:
	return String(spec(String(a.sp)).get("kind", "prey"))


static func size_of(a: Dictionary) -> Vector3:
	var s: Array = spec(String(a.sp)).get("size", [0.8, 0.5, 0.3])
	var v := Vector3(float(s[0]), float(s[1]), float(s[2]))
	if bool(a.get("infected", false)):
		v.y = minf(v.y, InfectedAnimals.height_m(String(a.sp)))
	return v


static func forget() -> void:
	animals.clear()
	blood.clear()
	zone_id = ""
	_told.clear()


static func _roll() -> float:
	return force_roll if force_roll >= 0.0 else _rng.randf()


# --- Laying them out -----------------------------------------------------------------------------

## Host: the zone's animals laid out for the season (Migration.where): each species' groups on its
## habitat's ground (woods: by the trees; deep woods: thick of them; open; hills: the high ground;
## valleys: the low; stores: by the settlement or a town's props). Some predator packs carry one
## that's turned (InfectedAnimals.CHANCE).
static func server_populate(level: Node) -> int:
	forget()
	zone_id = Nature.zone()
	var zl := level as ZoneLevel
	if zl == null or zl.terrain == null:
		return 0
	_rng.seed = hash([int(Survival.state().get("seed", 0)), zone_id, Seasons.current(), Seasons.year()])
	var season := Seasons.current()
	var spots := _candidates(zl)
	var keep: Array[Vector2] = []
	for s: Soldier in MapNodes.players(level):
		keep.append(Vector2(s.global_position.x, s.global_position.z))
	for sp: String in data():
		var where := Migration.where(sp, season)
		if not Migration.present(sp, season):
			continue
		var d: Dictionary = data()[sp]
		for g in int(d.get("groups", 1)):
			var at: Variant = _pick(spots, where, keep)
			if not at is Vector2:
				continue
			var herd: Array = d.get("herd", [1, 1])
			var n := _rng.randi_range(int(herd[0]), int(herd[1]))
			var gid := _next_id
			var turned := -1
			if bool(d.get("turns", false)) and _rng.randf() < InfectedAnimals.chance(sp):
				turned = _rng.randi_range(0, n - 1)
			for k in n:
				if animals.size() >= CAP:
					break
				var p: Vector2 = (at as Vector2) + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-6.0, 6.0))
				var a := add(level, sp, Vector3(p.x, 0.0, p.y), {"herd": gid, "home": at})
				if k == turned:
					InfectedAnimals.turn(a)
	return animals.size()


## Spots across the zone by habitat ({"woods", "deep_woods", "open", "hills", "valleys", "stores"}
## -> Array of Vector2).
static func _candidates(zl: ZoneLevel) -> Dictionary:
	var out := {"woods": [], "deep_woods": [], "open": [], "hills": [], "valleys": [], "stores": []}
	var half := zl.terrain.size_m * 0.5 - 40.0
	var heights: Array = []
	for i in 160:
		var p := Vector2(_rng.randf_range(-half, half), _rng.randf_range(-half, half))
		if zl.terrain.sea_side >= 0 and zl.terrain.height_at(p.x, p.y) < zl.terrain.sea_level + 1.0:
			continue
		heights.append([zl.terrain.height_at(p.x, p.y), p])
	heights.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var q := maxi(heights.size() / 4, 1)
	for i in heights.size():
		var p: Vector2 = heights[i][1]
		if i < q:
			(out.valleys as Array).append(p)
		elif i >= heights.size() - q:
			(out.hills as Array).append(p)
		else:
			(out.open as Array).append(p)
	var sc := zl.scatter
	if sc:
		var trees: Array = []
		for item: Dictionary in sc.items:
			if int(item.kind) == ZoneScatter.Kind.TREE:
				trees.append(item)
		for k in mini(trees.size(), 120):
			var item: Dictionary = trees[_rng.randi() % trees.size()]
			var p := Vector2((item.pos as Vector3).x, (item.pos as Vector3).z)
			(out.woods as Array).append(p)
			var near := 0
			for k2 in 24:
				var o: Dictionary = trees[_rng.randi() % trees.size()]
				if Vector2((o.pos as Vector3).x, (o.pos as Vector3).z).distance_to(p) < 40.0:
					near += 1
			if near >= 2:
				(out.deep_woods as Array).append(p)
		for item: Dictionary in sc.items:
			if int(item.kind) == ZoneScatter.Kind.PROP and item.has("shape") and (out.stores as Array).size() < 30 and _rng.randf() < 0.2:
				(out.stores as Array).append(Vector2((item.pos as Vector3).x, (item.pos as Vector3).z))
	if Settlement.exists() and Settlement.zone() == zone_id:
		var sp := Settlement.pos()
		for k in 4:
			(out.stores as Array).append(Vector2(sp.x, sp.z) + Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-30, 30)))
	return out


## A spot of habitat `where` (or the next best) KEEP_M from every player (`keep`): nothing walks
## up on a survivor the moment a zone comes up.
static func _pick(spots: Dictionary, where: String, keep: Array[Vector2] = []) -> Variant:
	var order := [where, "woods", "open", "valleys", "hills"]
	if where == "deep_woods":
		order = ["deep_woods", "woods", "hills"]
	for w: String in order:
		var list: Array = spots.get(w, [])
		for k in mini(list.size(), 8):
			var p: Vector2 = list[_rng.randi() % list.size()]
			if keep.all(func(q: Vector2) -> bool: return q.distance_to(p) >= KEEP_M):
				return p
	return null


## Host: one more animal of `sp` at `pos` (tests, the snares, the layout). opts: "herd", "home",
## "alive" (false: a carcass), "infected".
static func add(level: Node, sp: String, pos: Vector3, opts := {}) -> Dictionary:
	var d := spec(sp)
	var p := Vector2(pos.x, pos.z)
	var a := {"id": _next_id, "sp": sp, "pos": p, "y": _ground(level, p), "face": _rng.randf() * TAU, "home": opts.get("home", p),
		"herd": int(opts.get("herd", _next_id)), "state": "idle", "target": p, "wait": _rng.randf_range(0.0, WAIT_S.y), "alive": true,
		"hp": float(d.get("hp", 1.0)), "infected": false, "until": 0.0, "trail": [p], "dead_h": -1.0,
		"meat": int(d.get("meat", 1)), "hide": int(d.get("hide", 0))}
	_next_id += 1
	animals.append(a)
	if not bool(opts.get("alive", true)):
		_died(level, a, String(opts.get("cause", "found")))
	if bool(opts.get("infected", false)):
		InfectedAnimals.turn(a)
	if zone_id == "":
		zone_id = Nature.zone()
	return a


static func _ground(level: Node, p: Vector2) -> float:
	var zl := level as ZoneLevel
	return zl.ground_height(p.x, p.y) if zl else 0.0


# --- The tick ------------------------------------------------------------------------------------------

## Host: every Nature.TICK_S: each animal looks about and moves.
static func server_tick(level: Node, dt: float) -> void:
	if animals.is_empty():
		return
	var ctx := context(level)
	for a: Dictionary in animals:
		if not bool(a.alive):
			continue
		if bool(a.get("infected", false)):
			InfectedAnimals.step(level, a, dt, ctx)
		else:
			match kind_of(a):
				"predator":
					Predators.step(level, a, dt, ctx)
				_:
					_prey_step(level, a, dt, ctx)
		_move(level, a, dt)


## What the animals see this tick: the living ({"s", "p" (Vector2), "sneak"}), the dead's spots (a
## grid of Vector2 by GRID_M cell), the dark.
static func context(level: Node) -> Dictionary:
	var living: Array = []
	var dead := {}
	var tree: SceneTree = level.get_tree() if level and level.is_inside_tree() else null
	if tree:
		for n in tree.get_nodes_in_group(&"combatants"):
			var s := n as Soldier
			if s == null or s.is_queued_for_deletion() or not s.is_inside_tree() or not s.vitals.is_up():
				continue
			var p := Vector2(s.global_position.x, s.global_position.z)
			if s.faction == ZombieAI.INFECTED:
				_grid_add(dead, p)
			else:
				var slow := Vector2(s.velocity.x, s.velocity.z).length() <= SLOW_MPS
				var low := s.movement != null and (s.movement.is_crouched() or s.movement.is_prone())
				living.append({"s": s, "p": p, "sneak": slow and low})
	var crowd := ZoneDead.of(level)
	if crowd:
		for d: Dictionary in crowd.dead:
			if bool(d.alive):
				_grid_add(dead, d.pos)
	return {"living": living, "dead": dead, "dark": DayNight.darkness_at(Vector3.ZERO)}


const GRID_M := 32.0


static func _grid_add(grid: Dictionary, p: Vector2) -> void:
	var c := Vector2i(floori(p.x / GRID_M), floori(p.y / GRID_M))
	if not grid.has(c):
		grid[c] = []
	(grid[c] as Array).append(p)


## The nearest of the dead to `p` within `r` (Vector2), or Vector2.INF.
static func nearest_dead(ctx: Dictionary, p: Vector2, r: float) -> Vector2:
	var grid: Dictionary = ctx.dead
	var best := Vector2.INF
	var best_d := r
	var c := Vector2i(floori(p.x / GRID_M), floori(p.y / GRID_M))
	var span := ceili(r / GRID_M)
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			for q: Vector2 in grid.get(c + Vector2i(dx, dz), []):
				var d := q.distance_to(p)
				if d <= best_d:
					best_d = d
					best = q
	return best


## The nearest living one to `p` within `r` (its row in ctx.living), or {}. Stealth: a sneaking
## man counts STEALTH_X as far.
static func nearest_living(ctx: Dictionary, p: Vector2, r: float, sneak := true) -> Dictionary:
	var best := {}
	var best_d := r
	for row: Dictionary in ctx.living:
		var d := (row.p as Vector2).distance_to(p)
		if sneak and bool(row.sneak):
			d /= STEALTH_X
		if d <= best_d:
			best_d = d
			best = row
	return best


static func _prey_step(level: Node, a: Dictionary, dt: float, ctx: Dictionary) -> void:
	var d := spec(String(a.sp))
	var p: Vector2 = a.pos
	var now := Soldier._now()
	var threat := Vector2.INF
	var living := nearest_living(ctx, p, float(d.get("fear_living_m", 0.0)))
	if not living.is_empty():
		threat = living.p
	var dead := nearest_dead(ctx, p, float(d.get("fear_dead_m", 0.0)))
	if dead != Vector2.INF and (threat == Vector2.INF or dead.distance_to(p) < threat.distance_to(p)):
		threat = dead
	if threat != Vector2.INF:
		server_flee(level, a, threat)
		return
	if String(a.state) == "flee" and now < float(a.until):
		return
	if String(a.state) == "flee":
		a.state = "idle"
		a.home = a.pos  # (it settles where it ran to)
		a.wait = _rng.randf_range(WAIT_S.x, WAIT_S.y)
	_wander(a, dt)


static func _wander(a: Dictionary, dt: float) -> void:
	if float(a.wait) > 0.0:
		a.wait = float(a.wait) - dt
		if float(a.wait) <= 0.0:
			var ang := _rng.randf() * TAU
			a.target = (a.home as Vector2) + Vector2(cos(ang), sin(ang)) * _rng.randf_range(2.0, HOME_R)
			a.state = "walk"
		return
	if (a.target as Vector2).distance_to(a.pos) < 0.5:
		a.state = "idle"
		a.wait = _rng.randf_range(WAIT_S.x, WAIT_S.y)


## Host: `a` and its herd run from `from` (FLEE_M away, FLEE_S at least). A running herd is a tell.
static func server_flee(level: Node, a: Dictionary, from: Vector2) -> void:
	var started := false
	for o: Dictionary in animals:
		if not bool(o.alive) or (o != a and int(o.herd) != int(a.herd)) or bool(o.get("infected", false)):
			continue
		var away: Vector2 = (o.pos as Vector2) - from
		if away.length() < 0.1:
			away = Vector2(1, 0).rotated(_rng.randf() * TAU)
		if String(o.state) != "flee":
			started = true
		o.state = "flee"
		o.until = Soldier._now() + FLEE_S
		o.target = (o.pos as Vector2) + away.normalized().rotated(_rng.randf_range(-0.4, 0.4)) * FLEE_M
		o.wait = 0.0
	if started:
		_tell(level, a)


## Host: a noise at `pos` heard `radius` out (Survival.server_noise): every animal inside it but a
## predator on the hunt runs (a bear or a pack only from a shot).
static func server_noise(level: Node, pos: Vector3, radius: float, loud: float) -> int:
	var n := 0
	var at := Vector2(pos.x, pos.z)
	for a: Dictionary in animals:
		if not bool(a.alive) or bool(a.get("infected", false)) or (a.pos as Vector2).distance_to(at) > radius:
			continue
		var k := kind_of(a)
		if k == "predator" and (loud < 0.9 or String(a.state) == "hunt"):
			continue
		if String(a.state) != "flee":
			n += 1
		server_flee(level, a, at)
	return n


static func _move(level: Node, a: Dictionary, dt: float) -> void:
	var st := String(a.state)
	if st in ["idle", "dead"]:
		return
	var d := spec(String(a.sp))
	var speed := float(d.get("run", 6.0)) if st in ["flee", "hunt"] else float(d.get("speed", 1.0))
	if bool(a.get("infected", false)):
		speed = InfectedAnimals.speed(String(a.sp)) if st == "hunt" else float(d.get("speed", 1.0)) * 1.5
	var to: Vector2 = (a.target as Vector2) - (a.pos as Vector2)
	var step := speed * dt
	var zl := level as ZoneLevel
	if to.length() <= step:
		a.pos = a.target
	else:
		a.pos = (a.pos as Vector2) + to.normalized() * step
		a.face = atan2(-to.y, to.x)
	if zl and zl.terrain:
		var half := zl.terrain.size_m * 0.5 - 5.0
		a.pos = Vector2(clampf((a.pos as Vector2).x, -half, half), clampf((a.pos as Vector2).y, -half, half))
	a.y = _ground(level, a.pos)
	var trail: Array = a.trail
	if trail.is_empty() or (trail[trail.size() - 1] as Vector2).distance_to(a.pos) >= TRAIL_STEP_M:
		trail.append(a.pos)
		if trail.size() > TRAIL_N:
			trail.pop_front()


## A running herd or a lifted flock: a companion near says it, else the nearest player hears.
static func _tell(level: Node, a: Dictionary) -> void:
	var now := Soldier._now()
	if now - float(_told.get(int(a.herd), -1000.0)) < TELL_GAP_S:
		return
	_told[int(a.herd)] = now
	var d := spec(String(a.sp))
	var p: Vector2 = a.pos
	var line := ("%s lift out of there all at once: something's moving." if kind_of(a) == "flock" else "%s running hard out of there: something spooked them.") % String(d.get("name", a.sp)).capitalize()
	last_tell = {"pos": Vector3(p.x, float(a.get("y", 0.0)), p.y), "sp": String(a.sp), "line": line, "at": now}
	if level == null or not level.is_inside_tree():
		return
	var layer := level.get_node_or_null(^"Survivors") as SurvivorsLayer
	for p_s: Soldier in MapNodes.players(level):
		if Vector2(p_s.global_position.x, p_s.global_position.z).distance_to(p) > TELL_M:
			continue
		if layer:
			for n in level.get_tree().get_nodes_in_group(&"combatants"):
				var c := n as Soldier
				if c and c.has_meta(&"survivor_id") and c.vitals.is_up() and c.global_position.distance_to(p_s.global_position) <= COMPANION_TELL_M:
					layer.say(c, line + " " + _bearing(c.global_position, p))
					return
		Survival._tell(p_s, line + " " + _bearing(p_s.global_position, p))
		return


static func _bearing(from: Vector3, to: Vector2) -> String:
	var v := to - Vector2(from.x, from.z)
	var names := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	return "(%s)" % names[posmod(roundi(atan2(v.y, v.x) / (TAU / 8.0)), 8)]


# --- The dead and their prey ----------------------------------------------------------------------------------

## Host (ZombieAI._decide, when it sees nobody): one of the dead after an animal it sees, biting it
## down in reach, else to a carcass or blood it smells. Returns what it went for ("prey", "smell", "").
static func zombie_hunt(brain: ZombieAI) -> String:
	if animals.is_empty() and blood.is_empty():
		return ""
	var body := brain.body
	var p := Vector2(body.global_position.x, body.global_position.z)
	var reach := lerpf(PREY_SEE_M, PREY_NIGHT_M, clampf(DayNight.darkness_at(body.global_position), 0.0, 1.0))
	var best: Dictionary = {}
	var best_d := reach
	for a: Dictionary in animals:
		if not bool(a.alive) or bool(a.get("infected", false)) or String(a.sp) == "bear":
			continue
		var d := (a.pos as Vector2).distance_to(p)
		if d <= best_d:
			best_d = d
			best = a
	if not best.is_empty():
		var at := Vector3((best.pos as Vector2).x, float(best.get("y", body.global_position.y)), (best.pos as Vector2).y)
		if brain.mode != ZombieAI.Mode.INVESTIGATE or brain.goal == Vector3.INF or brain.goal.distance_to(at) > 2.0:
			brain.mode = ZombieAI.Mode.INVESTIGATE
			brain._set_goal(at)
		if best_d <= BITE_M:
			server_kill(CompoundLevel.current(body), best, "the dead")
		return "prey"
	if brain.mode in [ZombieAI.Mode.IDLE, ZombieAI.Mode.SEARCH]:
		var wind := DayNight.wind()
		for src: Dictionary in smell_sources():
			var at: Vector3 = src.pos
			var to_me := Vector2(p.x - at.x, p.y - at.z)
			var dist := to_me.length()
			if dist > SMELL_M * float(src.strength) or dist < 1.5:
				continue
			if wind.length() >= ZombieAI.CALM_MPS and Vector2(wind.x, wind.z).normalized().dot(to_me.normalized()) < 0.3 and dist > ZombieAI.SMELL_CALM_M:
				continue  # (not downwind of it)
			brain.mode = ZombieAI.Mode.INVESTIGATE
			brain._set_goal(at)
			return "smell"
	return ""


## Every smell the dead can follow: carcasses (fresh 1, falling over CARCASS_H, a butchered one
## less) and butchering's blood: [{"pos": Vector3, "strength", "what"}].
static func smell_sources() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var now_h := Moods.now_h()
	for a: Dictionary in animals:
		if bool(a.alive) or float(a.dead_h) < 0.0:
			continue
		var age := now_h - float(a.dead_h)
		if age > CARCASS_H:
			continue
		var s := clampf(1.0 - age / CARCASS_H, 0.2, 1.0) * (0.6 if bool(a.get("butchered", false)) else 1.0)
		out.append({"pos": Vector3((a.pos as Vector2).x, float(a.get("y", 0.0)), (a.pos as Vector2).y), "strength": s, "what": "carcass:" + String(a.sp)})
	for b: Dictionary in blood:
		if float(b.until_h) > now_h:
			out.append({"pos": b.pos, "strength": 0.8, "what": "blood"})
	return out


## Host, every Nature.SLOW_S: the crowd's heads near a carcass or blood drift to it; old blood and
## carcasses go.
static func server_slow(level: Node) -> void:
	var now_h := Moods.now_h()
	blood.assign(blood.filter(func(b: Dictionary) -> bool: return float(b.until_h) > now_h))
	var crowd := ZoneDead.of(level)
	if crowd == null:
		return
	for src: Dictionary in smell_sources():
		var at: Vector3 = src.pos
		var to := Vector2(at.x, at.z)
		for d: Dictionary in crowd.dead:
			if bool(d.alive) and not bool(d.get("horde", false)) and (d.pos as Vector2).distance_to(to) <= CROWD_SMELL_M * float(src.strength):
				d["target"] = to + Vector2(_rng.randf_range(-2, 2), _rng.randf_range(-2, 2))
				d["wait"] = 0.0


# --- Hunting --------------------------------------------------------------------------------------------------------

## Host: a round hit animal `index` (its hit box's "on_bullet"): it loses a hit (a bear takes
## several); dead, it lies there; hurt, it runs (a predator turns on the shooter).
static func server_shot(_at: Vector3, shooter: Node, index: int) -> void:
	if index < 0 or index >= animals.size() or not bool(animals[index].alive):
		return
	var a := animals[index]
	a.hp = float(a.hp) - 1.0
	var level: Node = CompoundLevel.current(shooter) if shooter and shooter.is_inside_tree() else null
	if float(a.hp) <= 0.0:
		server_kill(level, a, "shot", shooter)
		return
	if kind_of(a) == "predator" and shooter is Soldier:
		Predators.server_attack(a, shooter as Soldier)
	elif shooter is Node3D:
		var sp := (shooter as Node3D).global_position
		server_flee(level, a, Vector2(sp.x, sp.z))


## Host: `a` dies (shot, bitten down by the dead, a predator's kill, a snare's): a carcass the dead
## smell and the crows find.
static func server_kill(level: Node, a: Dictionary, cause: String, by: Node = null) -> void:
	if not bool(a.alive):
		return
	_died(level, a, cause)
	if by is Soldier and not (by as Soldier).is_ai():
		Rpg.xp(by as Soldier, "fieldcraft", 4.0)
	SessionLog.note("survival: a %s is down (%s)" % [String(a.sp), cause])


static func _died(_level: Node, a: Dictionary, cause: String) -> void:
	a.alive = false
	a.state = "dead"
	a.dead_h = Moods.now_h()
	a["cause"] = cause


## Why `s` can't butcher carcass `a` now ("" he can).
static func butcher_problem(s: Soldier, a: Dictionary) -> String:
	if s == null or a.is_empty() or bool(a.alive):
		return "Nothing to butcher there"
	var p: Vector2 = a.pos
	if Vector2(s.global_position.x, s.global_position.z).distance_to(p) > BUTCHER_M:
		return "Too far"
	if bool(a.get("butchered", false)) or bool(a.get("butchering", false)):
		return "There's nothing left on it worth taking"
	if not Crafting.has_tool(s, ["tag:blade", "tag:knife"]):
		return "You need a knife or a blade"
	return ""


## Host: `s` butchers carcass `a` with a blade: its meat as raw meat (x`yield_x`: Fieldwork's
## fieldcraft), its hide, bones and fat (the species' data), blood on the ground the dead smell for
## BLOOD_H. "" or why not. (Fieldwork.server_butcher is the timed job in front of it.)
static func server_butcher(s: Soldier, a: Dictionary, yield_x := 1.0) -> String:
	a.erase("butchering")
	var why := butcher_problem(s, a)
	if why != "":
		return "?" if why == "Nothing to butcher there" else why
	var p: Vector2 = a.pos
	var meat := roundi(int(a.get("meat", 0)) * yield_x)
	var hide := int(a.get("hide", 0))
	var d := spec(String(a.sp))
	a["butchered"] = true
	a.meat = 0
	a.hide = 0
	_give(s, &"raw_meat", meat)
	_give(s, &"hide", hide)
	_give(s, &"bone", int(d.get("bone", 0)))  # (the hands lane: docs/survival_hands.md)
	_give(s, &"animal_fat", int(d.get("fat", 0)))
	var at := Vector3(p.x, float(a.get("y", s.global_position.y)), p.y)
	blood.append({"pos": at, "until_h": Moods.now_h() + BLOOD_H})
	Rpg.xp(s, "fieldcraft", 6.0)
	Survival._tell(s, "You butcher the %s: %d cuts of meat%s. The blood will carry." % [String(spec(String(a.sp)).get("name", a.sp)), meat, ", a hide" if hide > 0 else ""])
	return ""


## Whether `s` carries item `id` anywhere (worn, in hand, stowed).
static func carries(s: Soldier, id: String) -> bool:
	for e: Dictionary in Survival.kit_of(s.inventory):
		if String(e.get("id", "")) == id:
			return true
	return false


## Items into `s`'s kit, the rest at his feet (an entry with a state goes in one by one; food
## that spoils is stamped fresh: Spoilage).
static func _give(s: Soldier, id: StringName, n: int, state := {}) -> int:
	if n <= 0:
		return 0
	state = Spoilage.made_state(id, state)
	if not state.is_empty() and Spoilage.perishable(ItemDB.get_item(id)):
		var got_all := s.inventory.take(id, n, state)  # (perishables with the same stamp stack)
		if got_all < n:
			var lvl := CompoundLevel.current(s)
			if lvl:
				lvl.server_spawn_dropped(id, n - got_all, s.global_position + Vector3.UP * 0.4, state)
		return n
	var got := 0
	if state.is_empty():
		got = s.inventory.take(id, n)
	else:
		for i in n:
			if s.inventory.take(id, 1, state) != 1:
				break
			got += 1
	if got < n:
		var level := CompoundLevel.current(s)
		if level:
			level.server_spawn_dropped(id, n - got, s.global_position + Vector3.UP * 0.4, state)
	return n


## The nearest carcass to `pos` within `r` ({} none).
static func carcass_near(pos: Vector3, r := BUTCHER_M) -> Dictionary:
	var best := {}
	var best_d := r
	for a: Dictionary in animals:
		if bool(a.alive):
			continue
		var d := (a.pos as Vector2).distance_to(Vector2(pos.x, pos.z))
		if d <= best_d:
			best_d = d
			best = a
	return best


# --- Snares ------------------------------------------------------------------------------------------------------------

static func snares() -> Array:
	var r := Nature.rec()
	if not r.get("snares") is Array:
		r["snares"] = []
	return r["snares"]


## Host: `s` sets a snare where he stands (one "snare" from his kit). "" or why not.
static func server_set_snare(s: Soldier) -> String:
	if s == null or s.inventory.count_of(&"snare") <= 0:
		return "You have no snare"
	s.inventory.remove_one(&"snare")
	var p := s.global_position
	snares().append({"zone": Nature.zone(), "x": p.x, "y": p.y, "z": p.z, "set_h": Moods.now_h(), "caught": "", "lvl": Rpg.level(s, "fieldcraft")})
	Survival._tell(s, "Snare set on the run. Check it in the morning.")
	return ""


## Host: `hours` of the world pass for the zone's snares: each may catch an animal by the species'
## "snare_h" chance an hour (a rabbit SNARE_CHANCE_H, a raccoon now and then; where they're about this
## season), lying dead in it.
static func server_snare_hours(level: Node, hours: float) -> int:
	var caught := 0
	var kinds: Array[String] = []
	for sp: String in data():
		if float(spec(sp).get("snare_h", SNARE_CHANCE_H if sp == "rabbit" else 0.0)) > 0.0 and Migration.present(sp, Seasons.current()):
			kinds.append(sp)
	if kinds.is_empty():
		return 0
	for sn: Dictionary in snares():
		if String(sn.zone) != Nature.zone() or String(sn.caught) != "":
			continue
		for sp: String in kinds:
			var per_h := float(spec(sp).get("snare_h", SNARE_CHANCE_H))
			var chance := 1.0 - pow(1.0 - per_h * (1.0 + SNARE_FIELDCRAFT_X * float(sn.get("lvl", 0))), hours)
			if _roll() < chance:
				sn.caught = sp
				add(level, sp, Vector3(float(sn.x), float(sn.y), float(sn.z)), {"alive": false, "cause": "snare"})
				caught += 1
				break
	return caught


## Host: `s` checks the snare nearest him: the catch lies there to butcher, the snare stays set.
## Returns what was in it ("" nothing, "?" no snare near).
static func server_check_snare(s: Soldier) -> String:
	for sn: Dictionary in snares():
		if String(sn.zone) != Nature.zone():
			continue
		if Vector3(float(sn.x), float(sn.y), float(sn.z)).distance_to(s.global_position) > SNARE_M:
			continue
		var what := String(sn.caught)
		sn.caught = ""
		sn.set_h = Moods.now_h()
		Survival._tell(s, "A %s in the snare." % what if what != "" else "Nothing in it yet.")
		return what
	return "?"


# --- Tracking and the calendar --------------------------------------------------------------------------------------

## Host: the trail of the nearest animal within TRACK_M (fieldcraft 3): its marks, oldest first,
## on the ground, the last where it is. [] without the skill or with nothing near.
static func tracks_for(s: Soldier) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if s == null or not Rpg.can(s, "tracking"):
		return out
	var p := Vector2(s.global_position.x, s.global_position.z)
	var best: Dictionary = {}
	var best_d := TRACK_M
	for a: Dictionary in animals:
		if not bool(a.alive):
			continue
		var d := (a.pos as Vector2).distance_to(p)
		if d < best_d:
			best_d = d
			best = a
	if best.is_empty():
		return out
	var level := CompoundLevel.current(s)
	for q: Vector2 in best.trail:
		out.append(Vector3(q.x, _ground(level, q), q.y))
	return out


## The hunter's calendar (call 103): {season: {species: where}} and, from fieldcraft 4, "fish":
## {season: {water: rate}}. Fieldcraft 2 or a field guide reads the game; less: {} with a "note".
static func calendar(s: Soldier) -> Dictionary:
	var lvl := Rpg.level(s, "fieldcraft") if s else 0
	var guide := s != null and s.inventory.count_of(&"field_guide") > 0
	if lvl < 2 and not guide:
		return {"note": "You don't know the game's habits yet (fieldcraft 2, or a field guide)"}
	var out := {}
	for season: String in Seasons.ALL:
		var row := {}
		for sp: String in data():
			row[sp] = Migration.where(sp, season)
		out[season] = row
	if lvl >= 4 or (guide and lvl >= 2):
		var fish := {}
		for season: String in Seasons.ALL:
			var row := {}
			for body: String in Migration.BODIES:
				row[body] = Migration.fish_rate(body, season)
			fish[season] = row
		out["fish"] = fish
	return out


# --- The peers' copy ------------------------------------------------------------------------------------------------------

## [species index, x, y, z, face, alive] for each animal (Nature's packet).
static func packed() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var names: Array = data().keys()
	for a: Dictionary in animals:
		var p: Vector2 = a.pos
		out.append_array(PackedFloat32Array([float(names.find(String(a.sp))), p.x, float(a.get("y", 0.0)), p.y, float(a.face), 1.0 if bool(a.alive) else 0.0]))
	return out


static func shown_rows() -> Array:
	var out: Array = []
	var names: Array = data().keys()
	for a: Dictionary in animals:
		var p: Vector2 = a.pos
		out.append([names.find(String(a.sp)), p.x, float(a.get("y", 0.0)), p.y, float(a.face), bool(a.alive)])
	return out


## How many are alive (of `sp`, or all).
static func alive_count(sp := "") -> int:
	return animals.filter(func(a: Dictionary) -> bool: return bool(a.alive) and (sp == "" or String(a.sp) == sp)).size()
