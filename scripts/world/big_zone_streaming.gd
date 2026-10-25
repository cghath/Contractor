class_name BigZoneStreaming
extends Node
## What makes an 8 km operation zone run (docs/combined_arms.md 6.2.2-6.2.3, phases D1/D2; cg_brief
## queue item 3.1). A child of a ZoneLevel whose terrain is on_demand (zones of
## data/operation_zones.json "streaming" "from_size_m" or more; ZoneLevel adds it), on every peer.
## Hot and contract zones never have one: they build their ground up front as before.
##
## The ground's collision near the action, every "tick_s":
## - the terrain's 128 m collision chunks within reach of a point (nearest first, at most
##   "chunks_per_tick" a tick) are built, and those past reach x collision_out_m / collision_in_m of
##   every point freed; the scatter's cover (rocks, trunks, props) the same by its 128 m cells, at
##   most "cells_per_tick" a tick;
## - the points and their reach: every player "collision_in_m" (their rounds and sight reach that
##   far; the cover "scatter_in_m"), every vehicle "vehicle_in_m", every other living soldier
##   "soldier_in_m" (the ground under him and the cover round him), and on the host one whose squad
##   is in a fight "engaged_in_m" (an AI firefight far from the players still has the hills
##   between the two sides). Points sharing a cell count once, with the longest reach (plan);
## - the perf pass's rule for a helicopter going fast or high (ZoneNav.RIDE_FAST_MS, RIDE_AGL_M:
##   it wants no navigation): a player aboard keeps his ground but his cover reaches only
##   "vehicle_in_m" (trunks and rocks a kilometre off don't matter to a door gunner going past);
## - a chunk or cell with something lying in it (a ragdoll, a dropped item, a vehicle: held) is
##   kept until it's gone, so nothing falls through the world when everyone walks off;
## - the ground round a player or vehicle that appears (a late joiner anywhere on the map, a
##   respawn, a vehicle spawned far from everyone) is built at once (ensure). SoldierMovement holds
##   a soldier with nothing under him until it's there (no_ground_below).
## Draw distances (every "draw_scan_s", each node once): soldiers to "soldier_draw_m"; vehicles their
## own meshes to "vehicle_proxy_m" and a box of their size and colour beyond to "vehicle_draw_m".
## Live caps: live soldiers and vehicles counted every tick, so the Virtualizer holds profiles back
## past its FORCE_M at the caps (at_cap).
## The terrain's and the scatter's visuals stream too, on their own (ZoneTerrain.far tiles and
## the LOD rings, ZoneScatter's cells freed past FREE_M): see their notes.
## All numbers in data/operation_zones.json "streaming", Proposed.

const NODE_NAME := "BigZoneStreaming"
## Physics layers whose bodies hold the ground they lie on (WorldItem 1 << 2, Ragdoll.LAYER,
## Vehicle.LAYER) and how often a held chunk is looked at again (s).
const HOLD_MASK := (1 << 2) | Ragdoll.LAYER | Vehicle.LAYER
const HOLD_RECHECK_S := 5.0
## At most this many chunks and cells looked at a plan before they're freed (held): a teleport
## leaves hundreds behind at once; the rest wait for the next plans. Proposed.
const FREE_PER_PLAN := 24
static var _looks_left := FREE_PER_PLAN
static var _limit_looks := false  # (only in a plan of _stream's; a test's or ensure's looks at them all)

var level: ZoneLevel
## Counted every tick: living soldiers in the zone (players and AI) and vehicles.
var live_soldiers := 0
var live_vehicles := 0
## How long the last tick's ground streaming took (ms), the worst so far, and how many chunks and
## cells it built (tests and the invasion suite).
var last_ms := 0.0
var worst_ms := 0.0
var built_chunks := 0
var built_cells := 0
## The worst frame's split: [terrain ms, scatter ms]; the last plan's cost.
var worst_split := [0.0, 0.0]
var last_plan_ms := 0.0
var _spec := {}
var _next := 0.0
var _next_draw := 0.0
var _proxy_material: StandardMaterial3D
var _reach := PackedFloat32Array()  # focus()'s points' own reach
var _cover_reach := PackedFloat32Array()  # and their cover's


static func spec() -> Dictionary:
	return (OperationGen.data().get("streaming", {}) as Dictionary)


## Whether a zone `size_m` across streams its ground (an operation zone; hot and contract zones
## build it all up front as before).
static func streams(size_m: float) -> bool:
	return size_m >= float(spec().get("from_size_m", 4224.0))


## How much a zone `size_m` across scales the scatter's caps: its area over a hot zone's.
static func scatter_scale(size_m: float) -> float:
	return maxf(1.0, size_m * size_m / 1.0e6 / float(spec().get("scatter_area_km2", 16.78)))


## Whether level `lvl`'s live soldiers (or, for a ride, its vehicles) are at the zone's cap:
## false in a zone that doesn't stream.
static func at_cap(lvl: Node, ride: bool) -> bool:
	var s := lvl.get_node_or_null(NODE_NAME) as BigZoneStreaming if lvl else null
	if s == null:
		return false
	if ride and s.live_vehicles >= int(s._spec.get("live_vehicles", 16)):
		return true
	return s.live_soldiers >= int(s._spec.get("live_soldiers", 80))


## Which cells of a `cells` x `cells` grid of `cell_m` squares (a zone `half` m from centre to edge)
## the points `focus` want: [wanted (cell -> distance to the nearest point, within its reach:
## `reach[k]`, else `in_m`), keep (cell -> true within reach x out_m / in_m)]. Points sharing a
## cell count once, with the longest reach: hundreds of soldiers cost what a few dozen cells do.
static func plan(focus: Array[Vector3], reach: PackedFloat32Array, in_m: float, out_m: float, cell_m: float, cells: int, half: float) -> Array:
	var ratio := out_m / maxf(in_m, 1.0)
	var points := {}  # the point's cell -> [point, reach]
	for k in focus.size():
		var p := focus[k]
		var r := reach[k] if k < reach.size() else in_m
		var key := Vector2i(floori((p.x + half) / cell_m), floori((p.z + half) / cell_m))
		if not points.has(key) or r > float(points[key][1]):
			points[key] = [p, r]
	var wanted := {}
	var keep := {}
	for key: Vector2i in points:
		var p: Vector3 = points[key][0]
		var r: float = points[key][1]
		var o := r * ratio
		var lo := Vector2i(clampi(floori((p.x - o + half) / cell_m), 0, cells - 1), clampi(floori((p.z - o + half) / cell_m), 0, cells - 1))
		var hi := Vector2i(clampi(floori((p.x + o + half) / cell_m), 0, cells - 1), clampi(floori((p.z + o + half) / cell_m), 0, cells - 1))
		for cz in range(lo.y, hi.y + 1):
			for cx in range(lo.x, hi.x + 1):
				var c := Vector2i(cx, cz)
				var d := Vector2(-half + (cx + 0.5) * cell_m - p.x, -half + (cz + 0.5) * cell_m - p.z).length()
				if d <= o:
					keep[c] = true
					if d <= r and (not wanted.has(c) or d < float(wanted[c])):
						wanted[c] = d
	return [wanted, keep]


## Whether anything that rests on the ground (HOLD_MASK: an item, a ragdoll, a vehicle) is in
## `rect` (x, z) of `owner`'s world, from just under its lowest ground to a little over its highest
## (`terrain`'s heights): its ground and cover aren't freed under it. Each `key` of `owner` is looked
## at again only every HOLD_RECHECK_S once held.
static func held(owner: Node3D, key: Variant, rect: Rect2, terrain: ZoneTerrain) -> bool:
	if not owner.is_inside_tree():
		return false
	var memo: Dictionary = owner.get_meta(&"held_until", {})
	var now := Time.get_ticks_msec() / 1000.0
	if float(memo.get(key, -1.0)) > now:
		return true
	if _limit_looks:
		if _looks_left <= 0:
			return true  # (looked at in a later plan: FREE_PER_PLAN)
		_looks_left -= 1
	var range_y := Vector2(terrain.min_height - 4.0, terrain.max_height + 6.0) if terrain else Vector2(-50.0, 300.0)  # (the zone's: no per-cell scan)
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, range_y.y - range_y.x + 6.0, rect.size.y)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(Basis.IDENTITY, Vector3(rect.get_center().x, (range_y.x + range_y.y) * 0.5 + 1.0, rect.get_center().y))
	q.collision_mask = HOLD_MASK
	q.collide_with_areas = false
	var hit := not owner.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()
	if hit:
		memo[key] = now + HOLD_RECHECK_S
	else:
		memo.erase(key)
	owner.set_meta(&"held_until", memo)
	return hit


## A soldier aboard a helicopter going fast or high: the perf pass's rule (ZoneNav._riding_past).
static func riding_past(s: Soldier) -> bool:
	if s.vehicle == null or not is_instance_valid(s.vehicle):
		return false
	var heli := s.vehicle as Helicopter
	if heli == null or not heli.is_airborne():
		return false
	var v := heli.linear_velocity
	return Vector2(v.x, v.z).length() > ZoneNav.RIDE_FAST_MS or heli.height_agl() > ZoneNav.RIDE_AGL_M


func _ready() -> void:
	name = NODE_NAME
	level = get_parent() as ZoneLevel
	_spec = spec()
	_proxy_material = StandardMaterial3D.new()
	_proxy_material.albedo_color = Color("4d4f45")
	_proxy_material.roughness = 1.0
	# The ground round every way in, before anyone's there.
	var start: Array[Vector3] = []
	for p in level.insertion_points():
		start.append(p)
	_reach.clear()
	_cover_reach.clear()
	_stream(start, -1)
	get_tree().node_added.connect(_on_node_added)


## Every "tick_s" the wanted chunks and cells are planned again (_stream: what's past reach freed);
## every physics frame the queues are built from, nearest first, for "frame_ms" (at least one each):
## the building spread over the frames, not a spike every tick.
func _physics_process(delta: float) -> void:
	_next -= delta
	if _next <= 0.0:
		_next = float(_spec.get("tick_s", 0.25))
		_stream(focus(), 0)
		_next_draw -= float(_spec.get("tick_s", 0.25))
		if _next_draw <= 0.0:
			_next_draw = float(_spec.get("draw_scan_s", 2.0))
			_apply_draw()
	if not _chunk_queue.is_empty() or not _cell_queue.is_empty():
		var started := Time.get_ticks_usec()
		var until := started + int(float(_spec.get("frame_ms", 0.75)) * 1000.0)
		built_chunks += level.terrain.build_chunks(_chunk_queue, until)
		var mid := Time.get_ticks_usec()
		if not _cell_queue.is_empty() and (mid < until or _chunk_queue.is_empty()):
			built_cells += level.scatter.build_cells(_cell_queue, maxi(until, mid + 1))
		_spent(started, mid)


## Where the ground must be solid: every player, every vehicle and every living soldier, each with
## its reach (_reach, _cover_reach).
func focus() -> Array[Vector3]:
	var out: Array[Vector3] = []
	_reach.clear()
	_cover_reach.clear()
	var player_m := float(_spec.get("collision_in_m", 1000.0))
	var cover_m := float(_spec.get("scatter_in_m", 1200.0))
	var soldier_m := float(_spec.get("soldier_in_m", 150.0))
	var engaged_m := float(_spec.get("engaged_in_m", 450.0))
	var vehicle_m := float(_spec.get("vehicle_in_m", 300.0))
	var host := multiplayer.is_server()
	var soldiers := 0
	var engaged := {}  # Squad -> whether it's in a fight (asked once a tick each)
	for holder: Node in [level.players, level.ai]:
		for n in holder.get_children():
			var s := n as Soldier
			if s == null or s.is_queued_for_deletion() or s.vitals.is_dead():
				continue
			soldiers += 1
			out.append(s.global_position)
			if holder == level.players:
				_reach.append(player_m)
				_cover_reach.append(vehicle_m if riding_past(s) else cover_m)
				continue
			var r := soldier_m
			if host:
				var sq := level.squad_of(s)
				if sq:
					if not engaged.has(sq):
						engaged[sq] = sq.is_engaged()
					if engaged[sq]:
						r = engaged_m
			_reach.append(r)
			_cover_reach.append(r)
	var vehicles := 0
	for v: Node in get_tree().get_nodes_in_group(Vehicle.GROUP):
		if v is Node3D and level.is_ancestor_of(v) and not v.is_queued_for_deletion():
			out.append((v as Node3D).global_position)
			_reach.append(vehicle_m)
			_cover_reach.append(vehicle_m)
			vehicles += 1
	live_soldiers = soldiers
	live_vehicles = vehicles
	return out


var _chunk_queue: Array = []  # the terrain chunks to build, nearest first (the last plan's)
var _cell_queue: Array = []  # the scatter's cover cells


## Plans the chunks and cells `points` want (freeing what's past reach) into the queues; with
## `all`, builds every one of them now (the first round, before anyone's there).
func _stream(points: Array[Vector3], all: int) -> void:
	if points.is_empty():
		return
	var started := Time.get_ticks_usec()
	var reach := _reach if _reach.size() == points.size() else PackedFloat32Array()
	var cover := _cover_reach if _cover_reach.size() == points.size() else PackedFloat32Array()
	_looks_left = FREE_PER_PLAN
	_limit_looks = true
	_chunk_queue = level.terrain.stream_plan(points, float(_spec.get("collision_in_m", 1000.0)), float(_spec.get("collision_out_m", 1300.0)), reach)
	var mid := Time.get_ticks_usec()
	_cell_queue = level.scatter.stream_plan(points, float(_spec.get("scatter_in_m", 1200.0)), float(_spec.get("scatter_out_m", 1500.0)), cover)
	_limit_looks = false
	if all < 0:
		built_chunks += level.terrain.build_chunks(_chunk_queue)
		built_cells += level.scatter.build_cells(_cell_queue)
	_spent(started, mid)
	last_plan_ms = (Time.get_ticks_usec() - started) / 1000.0


## The frame's streaming cost: kept as last_ms and the worst (with its split, terrain against
## scatter), and FrameCost's "stream_ground".
func _spent(started: int, mid: int) -> void:
	var now := Time.get_ticks_usec()
	last_ms = (now - started) / 1000.0
	if last_ms > worst_ms:
		worst_ms = last_ms
		worst_split = [(mid - started) / 1000.0, (now - mid) / 1000.0]
	FrameCost.spent(&"stream_ground", started)


## The ground (and cover) round `pos` now, whatever the budget: a vehicle that appears far from
## everyone (a QRF's technical, a column) never drops through, nor does a late joiner.
func ensure(pos: Vector3, radius := -1.0) -> void:
	var r := radius if radius > 0.0 else float(_spec.get("ensure_m", 200.0))
	var at: Array[Vector3] = [pos]
	var started := Time.get_ticks_usec()
	built_chunks += level.terrain.stream_collision(at, r, INF, -1)
	built_cells += level.scatter.stream_collision(at, minf(r, ZoneScatter.CELL_M * 0.75), INF, -1)  # (the cover under it; the rest by the ticks)
	FrameCost.spent(&"stream_ground", started)


## How many of the terrain's collision chunks within `radius_m` of `pos` aren't built (the invasion
## suite's catch-up: 0 once the ground round a moving player is all there).
func missing_near(pos: Vector3, radius_m: float) -> int:
	var t := level.terrain
	var chunk_m := ZoneTerrain.CHUNK_CELLS * ZoneTerrain.CELL_M
	var half := t.size_m * 0.5
	var n := t.chunk_count()
	var missing := 0
	for cz in range(maxi(floori((pos.z - radius_m + half) / chunk_m), 0), mini(floori((pos.z + radius_m + half) / chunk_m), n - 1) + 1):
		for cx in range(maxi(floori((pos.x - radius_m + half) / chunk_m), 0), mini(floori((pos.x + radius_m + half) / chunk_m), n - 1) + 1):
			var centre := Vector2(-half + (cx + 0.5) * chunk_m, -half + (cz + 0.5) * chunk_m)
			if centre.distance_to(Vector2(pos.x, pos.z)) <= radius_m and not t.has_collision(Vector2i(cx, cz)):
				missing += 1
	return missing


func _on_node_added(n: Node) -> void:
	if not level.is_ancestor_of(n):
		return
	if n is Vehicle or (n is Soldier and n.get_parent() == level.players):
		(func() -> void:
			if is_instance_valid(n) and n.is_inside_tree():
				ensure((n as Node3D).global_position)
				if n is Vehicle:
					_draw_vehicle(n as Node3D)).call_deferred()


# --- Far drawing ------------------------------------------------------------------------------

## Soldiers new to the zone first, then each again every DRAW_AGAIN_S (gear and stand-ins come and
## go), at most DRAW_PER_SCAN a scan; every vehicle without its far box.
const DRAW_AGAIN_S := 10.0
const DRAW_PER_SCAN := 12


func _apply_draw() -> void:
	var soldier_m := float(_spec.get("soldier_draw_m", 1500.0))
	var now := Time.get_ticks_msec() / 1000.0
	var done := 0
	for holder: Node in [level.players, level.ai]:
		for n in holder.get_children():
			if done >= DRAW_PER_SCAN:
				break
			if n is Soldier and float(n.get_meta(&"far_drawn", -INF)) < now - DRAW_AGAIN_S:
				_limit(n, soldier_m)
				n.set_meta(&"far_drawn", now)
				done += 1
	for v: Node in get_tree().get_nodes_in_group(Vehicle.GROUP):
		if v is Node3D and level.is_ancestor_of(v) and not v.has_node(^"FarProxy"):
			_draw_vehicle(v as Node3D)


## Every mesh under `n` drawn to `range_m` at most (its own nearer range kept: small gear, IFF
## marks), the far proxy left alone.
static func _limit(n: Node, range_m: float) -> void:
	for g: Node in n.find_children("*", "GeometryInstance3D", true, false):
		var geo := g as GeometryInstance3D
		if geo.has_meta(&"far_proxy"):
			continue
		if geo.visibility_range_end <= 0.0 or geo.visibility_range_end > range_m:
			geo.visibility_range_end = range_m


## A vehicle: its meshes to vehicle_proxy_m, a box of its size beyond to vehicle_draw_m.
func _draw_vehicle(v: Node3D) -> void:
	var near_m := float(_spec.get("vehicle_proxy_m", 1200.0))
	_limit(v, near_m)
	if v.has_node(^"FarProxy"):
		return
	var box := AABB()
	var first := true
	var inv := v.global_transform.affine_inverse()
	for g: Node in v.find_children("*", "VisualInstance3D", true, false):
		var vi := g as VisualInstance3D
		if not vi.is_visible_in_tree():
			continue
		var b := (inv * vi.global_transform) * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first or box.size.length() < 0.5:
		return
	var proxy := MeshInstance3D.new()
	proxy.name = "FarProxy"
	proxy.set_meta(&"far_proxy", true)
	var mesh := BoxMesh.new()
	mesh.size = box.size
	proxy.mesh = mesh
	proxy.material_override = _proxy_material
	proxy.position = box.get_center()
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	proxy.visibility_range_begin = near_m
	proxy.visibility_range_end = float(_spec.get("vehicle_draw_m", 3000.0))
	v.add_child(proxy)
