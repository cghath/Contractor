extends Node
## Town fight physics (Captain, 2026-10-14, P1104 ~0:23-0:25 on ridge_hot: module town_12
## streamed in, a fight with up to 41 AI, several hostiles downed and treated, reinforcements
## coming; engine physics went 5.9 -> 22.5 -> 451.7 ms worst, frames 48.5 ms on average, 21 fps).
## Headless: hosts ridge_hot, streams in its generated town, puts a garrison on the town's posts
## (upper floors and roofs among them) and a squad-sized force 50 m out, downs and kills some of
## the garrison where they stand (bodies on floors, stairs and roofs), and lets the fight run.
## Every physics tick it times the scripts' part (first to last _physics_process) apart from the
## engine's own part (physics step, sync and state callbacks), and counts ragdolls, ragdolls
## still simulating and the zone's navigation rebakes. Never touches a real save.
## What it found (R1127-R1136): the engine's own step averaged 2-3 ms; the "engine physics" the
## session log shows is the whole tick, scripts and all, and the ticks went on the squads' building
## scans (Buildings.near, from SquadTactics and Squad's context once a second): 150-960 ms a scan
## in the town, nearly every one a cache miss as the squads moved. TOWNPERF_PROFILE=1 times every
## script's _physics_process (by script) and names each tick over 50 ms.

## Proposed: the budgets. A tick has 16.7 ms at 60 ticks/s; past that the engine runs several a
## frame and the frame rate falls away (the 451.7 ms frames). Locally (R1127, before): ticks 27-29
## ms on average, 95th percentile 37-41 ms, building scans ~400 ms a second; after (R1143): 10.7
## ms, 17 ms, under 30 ms a second. Room left for CI's slower runners.
const TICK_AVG_MS := 20.0
const TICK_P95_MS := 40.0
const ENGINE_AVG_MS := 6.0
const SCANS_MS_PER_S := 120.0
## A body lies on what's under it: its torso no further than this over the first thing below.
const LIE_GAP_M := 1.05  # (the pivot is the pelvis: a body slumped over a stair or a sill sits it up to ~0.65 m, R1147; a different enemy gun changes who dies where, and CI saw a body on a stair edge at 0.91-0.94 m; a body left in the air is metres up)
## Proposed: once the fight's bodies have had SETTLE_FRAMES, at most this many still simulate.
const AWAKE_RAGDOLLS_MAX := 4
const HOSTILES := 22
const FRIENDLIES := 20
const DOWNED := 10
const FRAMES := 900
const SETTLE_FRAMES := 600

var level: ZoneLevel
var failures := 0
var _first: Node
var _last: Node
var _tick_start := 0
var _scripts_end := 0
var _pending := false  # a tick's scripts done, its engine part not timed yet
var _measuring := false
var _scripts_ms: Array[float] = []
var _engine_ms: Array[float] = []
var _tick_ms: Array[float] = []
var _frame_physics_ms: Array[float] = []
var _rebakes := 0
## TOWNPERF_PROFILE=1: every script's _physics_process is run (and timed) from here, by script.
var _profile := OS.get_environment("TOWNPERF_PROFILE") == "1"
var _profiled: Array[Node] = []
var _by_script := {}  # script file -> usec
var _profile_ticks := 0


class TickEdge extends Node:
	var on_tick: Callable
	var on_frame: Callable

	func _physics_process(_delta: float) -> void:
		on_tick.call()

	func _process(_delta: float) -> void:
		if on_frame.is_valid():
			on_frame.call()


func _ready() -> void:
	GameState.zone_id = "test_townperf" + OS.get_environment("CONTRACTOR_TEST_TAG")
	Campaign.campaign_id = "test_townperf_campaign" + OS.get_environment("CONTRACTOR_TEST_TAG")
	CompoundLevel.spawn_ai = false
	Contracts.auto_show_debrief = false
	GameState.delete_save()
	Campaign.reset_campaign()
	get_tree().create_timer(420.0, true, false, true).timeout.connect(func() -> void:
		print("TOWNPERF TEST FAILED (timed out)")
		get_tree().quit(99))
	_first = TickEdge.new()
	_first.process_physics_priority = -1000000
	_first.on_tick = _on_first
	_first.on_frame = _on_frame
	_first.process_priority = -1000000
	add_child(_first)
	_last = TickEdge.new()
	_last.process_physics_priority = 1000000
	_last.on_tick = _on_last
	add_child(_last)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(MissionRegistry.zone_def("ridge_hot"))
	level = CompoundLevel.current(self) as ZoneLevel
	while level == null or level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
		level = CompoundLevel.current(self) as ZoneLevel
	var player := level.players.get_node(^"1") as Soldier
	var town: ZoneModule = null
	for m in level.modules():
		if ZoneModules.base(m.type) == "town" and (town == null or ZoneModules.boxes(m.type).size() > ZoneModules.boxes(town.type).size()):
			town = m
	check(town != null, "ridge_hot has a generated town")
	if town == null:
		_finish()
		return
	var edge := town.footprint()
	var outside := level.ground_point(Vector3(edge.get_center().x, 0, edge.end.y + 30.0))
	player.global_position = outside
	player.set_physics_process(false)  # out of the fight: it only streams the town in
	player.vitals.process_mode = Node.PROCESS_MODE_DISABLED
	var nav := level.get_node_or_null(^"Navigation") as ZoneNav
	if nav:
		nav.rebaked.connect(func(_c: Vector2i) -> void: _rebakes += 1)
	for i in 1800:
		await get_tree().physics_frame
		if town.is_ready() and nav and nav.is_settled():
			break
	check(town.is_ready(), "the town (%s, %d boxes) streamed in" % [town.type, ZoneModules.boxes(town.type).size()])
	_check_chunk_connections(nav, town)
	# The garrison on the town's posts, the attackers 50 m out past the player.
	var posts: Array = ZoneModules.GARRISON.get(town.type, [])
	var hostiles: Array[Soldier] = []
	for i in HOSTILES:
		var local: Vector3 = posts[i % posts.size()] if not posts.is_empty() else Vector3((i % 6) * 4.0 - 10.0, 0.0, (i / 6) * 4.0 - 6.0)
		var at := town.global_transform * local + Vector3(0, 0.15, 0)
		if i >= posts.size():
			at += Vector3(0.8 * (i / maxi(posts.size(), 1)), 0, 0.6)
		hostiles.append(level.spawn_soldier({"name": "TownH%d" % i, "faction": "hostile", "variant": "urban", "pos": at,
			"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.45, "discipline": 0.5, "mode": "aware", "guard": true}))
	for i in FRIENDLIES:
		level.spawn_soldier({"name": "TownF%d" % i, "faction": "friendly", "variant": "multicam",
			"pos": level.ground_point(outside + Vector3(-19.0 + (i % 10) * 4.0, 0, 20.0 + (i / 10) * 4.0)),
			"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.5, "discipline": 0.6, "guard": false})
	for i in 30:
		await get_tree().physics_frame
	var posts_high := 0
	for s in hostiles:
		if s.global_position.y > level.ground_height(s.global_position.x, s.global_position.z) + 1.5:
			posts_high += 1
	print("townperf: %d hostiles on %d posts (%d above the ground floor), %d friendlies" % [hostiles.size(), posts.size(), posts_high, FRIENDLIES])
	# Bodies where they stand: half dead, half downed (as the fight's casualties lie).
	for i in DOWNED:
		var s := hostiles[i * 2 % hostiles.size()]
		if i % 2 == 0:
			s.vitals.server_kill()
		else:
			s.vitals.server_hit(Vitals.CHEST, {"round_class": Vitals.INTERMEDIATE})
			s.vitals.server_hit(Vitals.THIGH_R, {"round_class": Vitals.INTERMEDIATE})
	_rebakes = 0
	FrameCost.on = _profile
	var scans_before := Buildings.spent_usec
	_measuring = true
	for i in FRAMES:
		await get_tree().physics_frame
		if i == SETTLE_FRAMES:
			_report_ragdolls("after %d ticks" % SETTLE_FRAMES)
	_measuring = false
	var scans_ms := (Buildings.spent_usec - scans_before) / 1000.0
	var fight_s := FRAMES / float(Engine.physics_ticks_per_second)
	_report_profile()
	_report("tick (scripts + engine)", _tick_ms)
	_report("scripts", _scripts_ms)
	_report("engine step", _engine_ms)
	_report("engine physics monitor per frame", _frame_physics_ms)
	var awake := _report_ragdolls("at the end")
	print("townperf: %d nav rebakes over %d ticks (%.0f a minute); building scans %.0f ms in all" % [_rebakes, FRAMES, _rebakes * 3600.0 / FRAMES, scans_ms])
	check(scans_ms / fight_s <= SCANS_MS_PER_S, "the squads' building scans take %.0f ms a second of fight (Proposed budget %.0f)" % [scans_ms / fight_s, SCANS_MS_PER_S])
	check(_avg(_tick_ms) <= TICK_AVG_MS, "a physics tick averages %.2f ms (Proposed budget %.1f)" % [_avg(_tick_ms), TICK_AVG_MS])
	check(_pct(_tick_ms, 0.95) <= TICK_P95_MS, "95th percentile tick %.2f ms (Proposed budget %.1f)" % [_pct(_tick_ms, 0.95), TICK_P95_MS])
	check(_avg(_engine_ms) <= ENGINE_AVG_MS, "the engine's step averages %.2f ms (Proposed budget %.1f)" % [_avg(_engine_ms), ENGINE_AVG_MS])
	check(awake <= AWAKE_RAGDOLLS_MAX, "%d ragdolls still simulating at the end (at most %d)" % [awake, AWAKE_RAGDOLLS_MAX])
	_check_bodies_lie()
	if nav:
		await _check_breach_and_proxy_seams(nav, town)
	_finish()


## The bodies on the town's floors, stairs and roofs lie on something: every settled one has
## support under its torso, and none is left in the air.
func _check_bodies_lie() -> void:
	var bodies := 0
	var high := 0
	var bad: Array[String] = []
	var space := level.get_world_3d().direct_space_state
	for n in level.ai.get_children():
		var s := n as Soldier
		if s == null or not is_instance_valid(s.ragdoll) or not s.ragdoll.simulated:
			continue
		var torso := s.ragdoll.parts.get("torso") as Node3D
		if torso == null:
			continue
		bodies += 1
		if torso.global_position.y > level.ground_height(torso.global_position.x, torso.global_position.z) + 1.5:
			high += 1
		var exclude: Array[RID] = [s.get_rid()]
		for p: PhysicsBody3D in s.ragdoll.parts.values():
			exclude.append(p.get_rid())
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(torso.global_position, torso.global_position + Vector3.DOWN * 20.0, Ragdoll.MASK, exclude))
		var gap := torso.global_position.y - (hit.position as Vector3).y if not hit.is_empty() else INF
		if gap > LIE_GAP_M or (s.ragdoll.frozen and not s.ragdoll.has_support()):
			bad.append("%s %.2f m up%s" % [s.name, gap, " (frozen, no support)" if s.ragdoll.frozen and not s.ragdoll.has_support() else ""])
	check(bodies >= DOWNED / 2 and high >= 1 and bad.is_empty(),
		"%d bodies (%d up on floors or roofs) all lie on something %s" % [bodies, high, bad])


## Chunk seams (review of the executive audit, 2026-10-18). ZoneNav's chunks join only where
## their border vertices match (no proximity edge connections), so every seam between two
## baked chunks in `area` is sampled every SEAM_STEP_M along it, on every floor over it (the
## ground, upper floors, roofs): where the navmesh is open SEAM_REACH_M either side (both ends
## on it, level, nothing between at knee and chest height), the path from one side to the other
## must cross right there, no longer than SEAM_DETOUR times the straight line (a detour round
## through the next stretch of seam is SEAM_STEP_M further each way). `around` (chunk -> true):
## only the seams of those chunks. Returns {"tested", "broken": [text], "blocked": [samples with
## a wall between their ends], "proxy": chunks in `area` baked from a proxy, "chunks"}.
const SEAM_STEP_M := 1.5
const SEAM_REACH_M := 0.75
const SEAM_DETOUR := 1.3


func _seam_paths(nav: ZoneNav, area: Rect2, around := {}) -> Dictionary:
	var space := level.get_world_3d().direct_space_state
	var out := {"tested": 0, "broken": [], "blocked": [], "proxy": 0, "chunks": 0}
	for chunk: Vector2i in nav._regions:
		var rect := nav._rect_of(chunk)
		if not rect.intersects(area) or not _baked(nav, chunk):
			continue
		out.chunks += 1
		if nav.baked_from_proxy(chunk):
			out.proxy += 1
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var other := chunk + dir
			if (not around.is_empty() and not around.has(chunk) and not around.has(other)) or not _baked(nav, other):
				continue
			var normal := Vector3(dir.x, 0, dir.y)
			var along := Vector3(dir.y, 0, dir.x)
			var corner := Vector3(rect.end.x if dir.x == 1 else rect.position.x, 0, rect.end.y if dir.y == 1 else rect.position.y)
			for k in int(ZoneNav.ZONE_CHUNK_M / SEAM_STEP_M):
				var s := corner + along * (k + 0.5) * SEAM_STEP_M
				var ground := level.ground_height(s.x, s.z)
				for y: float in Buildings._surfaces(space, Vector3(s.x, ground + ZoneNav.HEADROOM_M, s.z), ground - 1.0, 12):
					var r := _seam_sample(nav, Vector3(s.x, y, s.z), normal, chunk, other)
					if r.is_empty():
						continue
					if r.has("blocked"):
						(out.blocked as Array).append(r)
						continue
					out.tested += 1
					if not r.ok:
						(out.broken as Array).append("%s %s|%s (%s|%s): %s" % [str(Vector3(s.x, y, s.z)).replace(" ", ""), chunk, other,
							"proxy" if nav.baked_from_proxy(chunk) else "voxels", "proxy" if nav.baked_from_proxy(other) else "voxels", r.why])
	return out


## One seam sample (see _seam_paths) at `s` (the seam, on a surface): {} where the navmesh isn't
## open both sides, {"blocked", "a", "b", "s", "normal"} where a wall stands between, else
## {"ok", "why", "a", "b"}.
func _seam_sample(nav: ZoneNav, s: Vector3, normal: Vector3, chunk: Vector2i, other: Vector2i) -> Dictionary:
	var world := level.get_world_3d()
	var map := world.navigation_map
	var pa := s - normal * SEAM_REACH_M
	var pb := s + normal * SEAM_REACH_M
	var a := NavigationServer3D.map_get_closest_point(map, pa + Vector3.UP * 0.1)
	var b := NavigationServer3D.map_get_closest_point(map, pb + Vector3.UP * 0.1)
	for p: Array in [[a, pa], [b, pb]]:
		var q: Vector3 = p[0]
		var want: Vector3 = p[1]
		if Vector2(q.x - want.x, q.z - want.z).length() > 0.2 or q.y - want.y > 0.7 or want.y - q.y > 0.3:
			return {}  # no navmesh here (a wall, a corner, a drop)
	if absf(a.y - b.y) > 0.3 or nav._chunk_of(a) != chunk or nav._chunk_of(b) != other:
		return {}
	for h: float in [0.4, 1.2]:
		if not Throwables.clear_line(world, a + Vector3.UP * h, b + Vector3.UP * h):
			return {"blocked": true, "a": a, "b": b, "s": s, "normal": normal, "chunk": chunk, "other": other}
	var path := NavigationServer3D.map_get_path(map, a, b, true)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	if path.is_empty():
		return {"ok": false, "why": "no path", "a": a, "b": b}
	var end: Vector3 = path[-1]
	if Vector2(end.x - b.x, end.z - b.z).length() > 0.15 or absf(end.y - b.y) > 0.3:
		return {"ok": false, "why": "ends %.2f m short" % end.distance_to(b), "a": a, "b": b}
	if length > SEAM_DETOUR * a.distance_to(b) + 0.1:
		return {"ok": false, "why": "%.1f m round for %.1f m" % [length, a.distance_to(b)], "a": a, "b": b}
	return {"ok": true, "why": "", "a": a, "b": b}


func _baked(nav: ZoneNav, chunk: Vector2i) -> bool:
	return nav.region_of(chunk) != null and nav.region_of(chunk).navigation_mesh != null


## The town's seams once it and its navigation have settled (see _seam_paths).
func _check_chunk_connections(nav: ZoneNav, town: ZoneModule) -> void:
	var r := _seam_paths(nav, town.footprint().grow(ZoneNav.ZONE_CHUNK_M))
	check(int(r.tested) >= 40 and (r.broken as Array).is_empty(),
		"navigation crosses every chunk seam round the town where it's open, every %.1f m on every floor (%d samples, %d chunks, %d baked from a proxy; broken: %s)"
		% [SEAM_STEP_M, r.tested, r.chunks, r.proxy, (r.broken as Array).slice(0, 8)])


## After the fight: a breach blown in a wall standing along a chunk seam in the town, its
## chunks rebaked; then the town streamed out, a chunk by the breach and one well away from it
## baked again from the proxy (their neighbours keep their voxel bakes), and the town streamed
## back in: once its voxels are built, both are baked from them again and every seam round
## them joins, through the breach too.
func _check_breach_and_proxy_seams(nav: ZoneNav, town: ZoneModule) -> void:
	var area := town.footprint()
	var space := level.get_world_3d().direct_space_state
	var walls: Array = (_seam_paths(nav, area).blocked as Array).filter(func(w: Dictionary) -> bool:
		var s: Vector3 = w.s
		if not area.grow(-2.0).has_point(Vector2(s.x, s.z)) or s.y - level.ground_height(s.x, s.z) > 1.0:
			return false  # the ground floor, inside the town
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(w.a + Vector3.UP, w.b + Vector3.UP, Throwables.WORLD_MASK))
		return not hit.is_empty() and absf((hit.normal as Vector3).dot(w.normal)) > 0.9)
	if walls.is_empty():
		check(false, "a wall standing along a chunk seam in the town to breach")
		return
	var w: Dictionary = walls[walls.size() / 2]
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(w.a + Vector3.UP, w.b + Vector3.UP, Throwables.WORLD_MASK))
	var at: Vector3 = hit.position
	var rebakes := {}  # chunk -> rebakes since the breach
	var built_rebakes := {}  # chunk -> rebakes once the town's voxels were built again
	var count := func(c: Vector2i) -> void:
		rebakes[c] = int(rebakes.get(c, 0)) + 1
		if town.voxel_world and town.voxel_world.is_built():
			built_rebakes[c] = int(built_rebakes.get(c, 0)) + 1
	nav.rebaked.connect(count)
	# A man-sized hole (a soldier needs 1.75 m of headroom and 0.5 m of width): three carves one
	# over another, in the middle of the wall's thickness.
	var middle := at - (hit.normal as Vector3) * 0.15
	for up: float in [0.7, 1.3, 1.9]:
		town.voxel_world.server_carve(Vector3(middle.x, (w.s as Vector3).y + up, middle.z), 0.8)
	# (The voxels' collision comes in a few frames after the carve, maybe after the rebakes.)
	for i in 600:
		await get_tree().physics_frame
		if rebakes.has(w.chunk) and rebakes.has(w.other) and nav.is_settled() and not _seam_sample(nav, w.s, w.normal, w.chunk, w.other).has("blocked"):
			break
	var through := _seam_sample(nav, w.s, w.normal, w.chunk, w.other)
	var around := {w.chunk: true, w.other: true}
	var after := _seam_paths(nav, area.grow(ZoneNav.ZONE_CHUNK_M), around)
	check(rebakes.has(w.chunk) and rebakes.has(w.other) and through.get("ok", false) and (after.broken as Array).is_empty(),
		"a breach blown at %s in a wall along the seam %s|%s: both rebaked (%d, %d), the path goes through it (%s), and their seams join (%d samples; broken: %s)"
		% [str(at).replace(" ", ""), w.chunk, w.other, rebakes.get(w.chunk, 0), rebakes.get(w.other, 0),
			"blocked" if through.has("blocked") else through.get("why", "no navmesh") if not through.get("ok", false) else "ok", after.tested, after.broken])
	# The town streamed out: a chunk by the breach and one well away from it baked from the
	# proxy (with the breach as its coarse cells), next to neighbours baked from the voxels.
	var far := Vector2i(w.chunk)
	for c: Vector2i in nav._regions:
		if _baked(nav, c) and area.encloses(nav._rect_of(c)) and absi(c.x - w.chunk.x) + absi(c.y - w.chunk.y) > absi(far.x - w.chunk.x) + absi(far.y - w.chunk.y) \
				and [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)].all(func(d: Vector2i) -> bool: return _baked(nav, c + d)):
			far = c
	var proxied: Array = [w.chunk, far] if far != w.chunk else [w.chunk]
	print("townperf: breach by %s; the chunk away from it %s (%d chunks off)" % [w.chunk, far, absi(far.x - w.chunk.x) + absi(far.y - w.chunk.y)])
	rebakes.clear()
	built_rebakes.clear()
	town.stream_out()
	for c in proxied:
		nav._request_rebake(c)
	for i in 300:
		await get_tree().physics_frame
		if proxied.all(func(c: Vector2i) -> bool: return rebakes.has(c)):
			break
	var mixed := _seam_paths(nav, area.grow(ZoneNav.ZONE_CHUNK_M), {w.chunk: true, far: true})
	var mixed_through := _seam_sample(nav, w.s, w.normal, w.chunk, w.other)
	var hole := town.to_local(middle + Vector3.UP * ((w.s as Vector3).y + 1.3 - middle.y))
	print("townperf: town streamed out, %s baked from its proxy (%s; town built: %s; the proxy's cells %s the breach): their seams %d samples, broken %s; through the breach: %s" % [
		proxied, proxied.map(func(c: Vector2i) -> bool: return nav.baked_from_proxy(c)), town.is_ready(),
		"fill" if town.proxy_boxes().any(func(bx: AABB) -> bool: return bx.has_point(hole)) else "keep open", mixed.tested, mixed.broken,
		"blocked" if mixed_through.has("blocked") else mixed_through.get("why", "no navmesh") if not mixed_through.get("ok", false) else "ok"])
	check(proxied.all(func(c: Vector2i) -> bool: return rebakes.has(c) and nav.baked_from_proxy(c)),
		"streamed out, %s baked again from the town's proxy (%s)" % [proxied, rebakes])
	# Back in (the zone streams it in round the player; if not yet, as it would).
	for i in 120:
		await get_tree().physics_frame
		if town.is_streamed():
			break
	if not town.is_streamed():
		level._stream_in(town)
	var settled := false
	for i in 1800:
		await get_tree().physics_frame
		if town.is_ready() and nav.is_settled() and proxied.all(func(c: Vector2i) -> bool: return not nav.baked_from_proxy(c)):
			settled = true
			break
	var back := _seam_paths(nav, area.grow(ZoneNav.ZONE_CHUNK_M), {w.chunk: true, far: true})
	var back_through := _seam_sample(nav, w.s, w.normal, w.chunk, w.other)
	nav.rebaked.disconnect(count)
	check(settled and proxied.all(func(c: Vector2i) -> bool: return int(built_rebakes.get(c, 0)) >= 1),
		"streamed back in, once its voxels are built the chunks baked from its proxy are baked from them again (%s: %s rebakes since; proxy now %s)"
		% [proxied, proxied.map(func(c: Vector2i) -> int: return int(built_rebakes.get(c, 0))), proxied.map(func(c: Vector2i) -> bool: return nav.baked_from_proxy(c))])
	check(back_through.get("ok", false) and (back.broken as Array).is_empty() and int(back.tested) >= 10,
		"and their seams join again, through the breach too (%s; %d samples; broken: %s)" % [
			"blocked" if back_through.has("blocked") else back_through.get("why", "no navmesh") if not back_through.get("ok", false) else "ok", back.tested, back.broken])


func _finish() -> void:
	Campaign.reset_campaign()
	GameState.delete_save()
	print("TOWNPERF TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


## The engine's part of a tick: from its last script to the next tick's first, or to the
## frame's first _process when it was the frame's last tick.
func _engine_part() -> void:
	if not _pending:
		return
	_pending = false
	if _measuring and not _scripts_ms.is_empty():
		_engine_ms.append((Time.get_ticks_usec() - _scripts_end) / 1000.0)
		_tick_ms.append(_scripts_ms[-1] + _engine_ms[-1])


func _on_first() -> void:
	_engine_part()
	if _measuring and _profile and Engine.get_physics_frames() % 30 == 0:
		_gather_profiled()
	_tick_start = Time.get_ticks_usec()
	if _measuring and _profile:
		_profile_ticks += 1
		var delta := 1.0 / Engine.physics_ticks_per_second
		var top := 0
		var top_name := ""
		var t_all := Time.get_ticks_usec()
		for n in _profiled:
			if is_instance_valid(n) and n.is_inside_tree() and n.can_process():
				var t := Time.get_ticks_usec()
				n._physics_process(delta)
				var key := (n.get_script() as Script).resource_path.get_file()
				var spent := Time.get_ticks_usec() - t
				_by_script[key] = int(_by_script.get(key, 0)) + spent
				if spent > top:
					top = spent
					var brain := n as SquadAI
					top_name = "%s/%s %.1f ms%s" % [n.get_parent().name, n.name, spent / 1000.0, (" (%s)" % brain.body.ai_status) if brain and brain.body else ""]
		if Time.get_ticks_usec() - t_all > 50000:
			print("townperf: spike tick %d: scripts %.1f ms, slowest %s; FrameCost %s" % [Engine.get_physics_frames(),
				(Time.get_ticks_usec() - t_all) / 1000.0, top_name, SessionLog.costs_text(FrameCost.take(), {})])


func _gather_profiled() -> void:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n == _first or n == _last or n == self or n.get_script() == null or not n.is_physics_processing():
			continue
		if n.has_method(&"_physics_process"):
			n.set_physics_process(false)
			_profiled.append(n)


func _report_profile() -> void:
	if not _profile or _profile_ticks == 0:
		return
	var keys := _by_script.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(_by_script[a]) > int(_by_script[b]))
	for k: String in keys.slice(0, 15):
		print("townperf: profile %s %.3f ms a tick" % [k, int(_by_script[k]) / 1000.0 / _profile_ticks])


func _on_frame() -> void:
	_engine_part()


func _on_last() -> void:
	_scripts_end = Time.get_ticks_usec()
	_pending = true
	if _measuring:
		_scripts_ms.append((_scripts_end - _tick_start) / 1000.0)


func _process(_delta: float) -> void:
	if _measuring:
		_frame_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)


func _report_ragdolls(when: String) -> int:
	var total := 0
	var awake := 0
	var on_floors := 0
	for n in level.ai.get_children():
		var s := n as Soldier
		if s and is_instance_valid(s.ragdoll) and s.ragdoll.simulated:
			total += 1
			if not s.ragdoll.frozen:
				awake += 1
			var torso := s.ragdoll.parts.get("torso") as Node3D
			if torso and torso.global_position.y > level.ground_height(torso.global_position.x, torso.global_position.z) + 1.5:
				on_floors += 1
	print("townperf: ragdolls %s: %d, %d still simulating, %d above the ground floor; active bodies %d, collision pairs %d" % [
		when, total, awake, on_floors, Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)])
	return awake


func _avg(ms: Array[float]) -> float:
	if ms.is_empty():
		return 0.0
	var sum := 0.0
	for v in ms:
		sum += v
	return sum / ms.size()


func _pct(ms: Array[float], q: float) -> float:
	if ms.is_empty():
		return 0.0
	var sorted := ms.duplicate()
	sorted.sort()
	return sorted[mini(int(sorted.size() * q), sorted.size() - 1)]


func _report(what: String, ms: Array[float]) -> void:
	if ms.is_empty():
		print("townperf: %s: no samples" % what)
		return
	var sorted := ms.duplicate()
	sorted.sort()
	print("townperf: %s: worst %.2f ms, 99th %.2f, 95th %.2f, average %.3f ms (%d samples)" % [
		what, sorted[-1], _pct(ms, 0.99), _pct(ms, 0.95), _avg(ms), ms.size()])
