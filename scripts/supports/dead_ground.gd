class_name DeadGround
extends RefCounted
## Dead ground for a helicopter landing (host): a landing zone the enemy can't see. Used by the
## helicopter insertion on a contract zone (an LZ 200-450 m from the objective, out of sight of
## every garrison post: design doc "Missions", staged insertion) and by the extraction
## helicopter's "near us" call and its wave-off from a hot LZ (dead ground near the squad).
##
## A spot is dead ground when no watcher sees a man standing there: eye to eye at EYE_M over
## the terrain's heights (the ground is the only cover counted: buildings and trees are not, so
## it errs on the side of being seen), for every watcher within WATCH_M. Watchers are every
## zone module's garrison posts (ZoneModules.GARRISON, whether or not the garrison is out yet;
## a site whose garrison is all down no longer watches) and every hostile soldier up. A spot
## must also take a landing (LandingZone.check: level enough, nothing in the rotor's way).
##
## A hot LZ (hot_watcher) is one an enemy soldier close by actually sees: up, not captive,
## within HOT_CLOSE_M, eye to eye over the terrain and through the world's colliders (walls do
## hide).
##
## lifted from tests/coop_soak.gd's dead-ground search (test/coop-soak), made a shared part.
## Numbers are Proposed.

## Eye height of a man standing (m), both ends of a sight line.
const EYE_M := 1.7
## Watchers farther than this (m) don't count (hostiles pick targets out to 200 m: SquadAI).
const WATCH_M := 600.0
## A sight line is sampled every this many metres over the terrain.
const STEP_M := 6.0
## Insertion: the ring round the objective an LZ is looked for in (m, Captain's design).
const OBJECTIVE_RING_M := Vector2(200.0, 450.0)
## Extraction near the squad: the ring round the squad (m).
const SQUAD_RING_M := Vector2(30.0, 300.0)
const RING_STEP_M := 25.0
## Candidates round each ring: at least this many, else one every SPACING_M.
const RING_POINTS := 16
const SPACING_M := 30.0
## A spot keeps this far inside the zone's edge (m) and this far from any watcher.
const EDGE_KEEP_M := 80.0
const POST_KEEP_M := 150.0
## Sight lines are worked out for at most this many candidates (the search's time cap).
const MAX_SIGHT_CHECKS := 260
## Hot LZ: an enemy soldier this close (m) who sees it. Captain, 2026-10-14 ("not landing": one
## sentry 200-320 m off kept every LZ hot): real danger only, close by (was 450 m). Proposed.
const HOT_CLOSE_M := 150.0


## Where the enemy watches from in `level`: the garrison posts of every zone module (whose
## garrison isn't all down) and every hostile soldier up.
static func watchers(level: Node) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if level == null or not level.is_inside_tree():
		return out
	if level.has_method(&"modules"):
		for m: Variant in level.call(&"modules"):
			var module := m as ZoneModule
			if module == null or not module.is_inside_tree():
				continue
			if level.has_method(&"garrison_spawned") and bool(level.call(&"garrison_spawned", module.module_id)) \
					and int(level.call(&"garrison_alive", module.module_id)) == 0 and int(level.call(&"garrison_pending", module.module_id)) == 0:
				continue  # cleared: nobody left there to watch
			for spot: Vector3 in ZoneModules.GARRISON.get(module.type, []):
				out.append(module.to_global(spot))
	for s: Soldier in hostiles(level):
		out.append(s.global_position)
	return out


## Hostile soldiers up in `level` (not captive).
static func hostiles(level: Node) -> Array[Soldier]:
	var out: Array[Soldier] = []
	for node in level.get_tree().get_nodes_in_group(&"combatants"):
		var s := node as Soldier
		if s and s.faction == &"hostile" and s.vitals.is_up() and not s.is_queued_for_deletion() and not Person.is_captive(s) \
				and s.is_inside_tree():
			out.append(s)
	return out


## Whether a man at `b` sees a man at `a` over the terrain (eye to eye at EYE_M); with
## `world`, the level's colliders (walls, rocks, trunks) can hide them too.
static func sees(level: Node3D, a: Vector3, b: Vector3, world := false) -> bool:
	var eye_a := Vector3(a.x, LandingZone.terrain_y(level, a) + EYE_M, a.z)
	var eye_b := Vector3(b.x, maxf(b.y, LandingZone.terrain_y(level, b)) + EYE_M, b.z)
	var dist := Vector2(a.x - b.x, a.z - b.z).length()
	var steps := clampi(int(dist / STEP_M), 2, 200)
	for i in range(1, steps):
		var p := eye_a.lerp(eye_b, float(i) / steps)
		if LandingZone.terrain_y(level, p) > p.y:
			return false
	if world and level.is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(eye_a, eye_b, 1)
		if not level.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			return false
	return true


## How many of `posts` within WATCH_M see `at` (stopping at `stop_at`).
static func seen_by(level: Node3D, at: Vector3, posts: Array[Vector3], stop_at := 1 << 30) -> int:
	var n := 0
	for q in posts:
		if Vector2(at.x - q.x, at.z - q.z).length() <= WATCH_M and sees(level, at, q):
			n += 1
			if n >= stop_at:
				break
	return n


## The best dead-ground LZ in a ring round `centre` (Vector2 `ring`, m), host side:
## nearest `prefer` first (a Vector3: the side the approach comes from, the squad) or the ring's
## inside, never within `avoid_m` of a spot in `avoid` (waved-off LZs). `posts`: the watchers
## (watchers(level) when empty). Returns {"ok", "spot" (on the ground), "hidden" (true: seen by
## none), "seen_by", "dist" (from centre), "checked"}; with no hidden spot that takes a landing,
## the LZ-safe spot seen by fewest ("hidden" false); not ok when there's no safe spot at all.
## `never_seen_by`: watchers no spot may be seen by, not even the fallback (2026-10-14:
## a wave-off never picks another LZ the enemy who made the last one hot can see).
static func find(level: Node3D, centre: Vector3, ring := OBJECTIVE_RING_M, prefer: Variant = null, avoid: Array[Vector3] = [],
		avoid_m := 150.0, posts: Array[Vector3] = [], ignore: Array[RID] = [], never_seen_by: Array[Vector3] = []) -> Dictionary:
	if level == null or not level.is_inside_tree():
		return {"ok": false}
	var watch := posts if not posts.is_empty() else watchers(level)
	var inside := Rect2(-1e6, -1e6, 2e6, 2e6)
	if level.has_method(&"map_area"):
		inside = (level.call(&"map_area") as Rect2).grow(-EDGE_KEEP_M)
	var cands: Array = []
	var r := ring.x
	while r <= ring.y + 0.01:
		var n := maxi(RING_POINTS, roundi(TAU * r / SPACING_M))
		for k in n:
			var a := TAU * float(k) / float(n) + r * 0.013
			var at := centre + Vector3(cos(a), 0.0, sin(a)) * r
			if not inside.has_point(Vector2(at.x, at.z)):
				continue
			if avoid.any(func(v: Vector3) -> bool: return Vector2(at.x - v.x, at.z - v.z).length() < avoid_m):
				continue
			var near_post := false
			for q in watch:
				if Vector2(at.x - q.x, at.z - q.z).length() < POST_KEEP_M:
					near_post = true
					break
			if near_post:
				continue
			var cost := r
			if prefer is Vector3:
				var pv: Vector3 = prefer
				cost = Vector2(at.x - pv.x, at.z - pv.z).length() + absf(r - (ring.x + ring.y) * 0.5) * 0.25
			cands.append([cost, at, r])
		r += RING_STEP_M
	cands.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var fallback := {}
	var checked := 0
	for c: Array in cands:
		if checked >= MAX_SIGHT_CHECKS:
			break
		var at: Vector3 = c[1]
		if seen_by(level, at, never_seen_by, 1) > 0:
			continue  # (one sight line each: not counted against the cap)
		checked += 1
		var seen := seen_by(level, at, watch, int(fallback.get("seen_by", 1 << 30)) if not fallback.is_empty() else 1 << 30)
		if seen > 0 and not fallback.is_empty() and seen >= int(fallback.seen_by):
			continue
		var lz := LandingZone.check(level, at, ignore)
		if not lz.ok:
			continue
		var out := {"ok": true, "spot": lz.spot, "hidden": seen == 0, "seen_by": seen, "dist": float(c[2]), "checked": checked,
			"watchers": watch.size()}
		if seen == 0:
			return out
		fallback = out
	if not fallback.is_empty():
		fallback.checked = checked
		return fallback
	return {"ok": false, "checked": checked, "watchers": watch.size()}


## An enemy soldier who sees `lz` now (up, not captive, within `within` m, over the terrain and
## past the world's colliders), or null: the LZ is hot.
static func hot_watcher(level: Node3D, lz: Vector3, within := HOT_CLOSE_M) -> Soldier:
	if level == null or not level.is_inside_tree():
		return null
	for s in hostiles(level):
		if Vehicle.ride_of(s) == null and Vector2(s.global_position.x - lz.x, s.global_position.z - lz.z).length() <= within \
				and sees(level, lz, s.global_position, true):
			return s
	return null
