class_name BigZoneStreaming
extends Node
## What makes an 8 km operation zone run (docs/combined_arms.md 6.2.2-6.2.3, phase D2). A child
## of a ZoneLevel whose terrain is on_demand (zones of data/operation_zones.json "streaming"
## "from_size_m" or more; ZoneLevel adds it), on every peer:
## - Ground collision near the action: every "tick_s" the terrain's collision chunks within
##   "collision_in_m" of any player, "vehicle_in_m" of a vehicle and "soldier_in_m" of any other
##   living soldier (the ground under him and the cover round him) are built (nearest first, at most
##   "chunks_per_tick") and those past "collision_out_m" of all
##   of them freed, about 250 of the zone's 4,096 live round one player; the scatter's cover (rocks, trunks, ruins) the same by its cells. A
##   soldier with no ground under him is held by SoldierMovement until it's there; a vehicle's
##   ground is built at once when it appears (ensure).
## - Draw distances: soldiers drawn to "soldier_draw_m"; vehicles to "vehicle_draw_m", their own
##   meshes to "vehicle_proxy_m" and a box of their size and colour beyond (a far proxy).
## - Live caps: live_soldiers and live_vehicles counted each tick, so the Virtualizer holds
##   profiles back at the caps (at_cap).
## The same zones on every peer stream the same way: collision follows every player (a client
## sees the host's fights near other players too), so shots and ricochets agree.
## All numbers in data/operation_zones.json "streaming", Proposed.

const NODE_NAME := "BigZoneStreaming"

var level: ZoneLevel
## Counted every tick: living soldiers in the zone (players and AI) and vehicles.
var live_soldiers := 0
var live_vehicles := 0
## How long the last tick's ground streaming took (ms), and the most chunks built in one.
var last_ms := 0.0
var _spec := {}
var _next := 0.0
var _next_draw := 0.0
var _proxy_material: StandardMaterial3D
var _reach := PackedFloat32Array()  # focus()'s points' own reach (a vehicle's is shorter)


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
	_stream(start, -1)
	get_tree().node_added.connect(_on_node_added)


func _physics_process(delta: float) -> void:
	_next -= delta
	if _next > 0.0:
		return
	_next = float(_spec.get("tick_s", 0.25))
	_stream(focus(), int(_spec.get("chunks_per_tick", 24)))
	_next_draw -= float(_spec.get("tick_s", 0.25))
	if _next_draw <= 0.0:
		_next_draw = float(_spec.get("draw_scan_s", 2.0))
		_apply_draw()


## Where the ground must be solid: every player, every vehicle and every living soldier.
func focus() -> Array[Vector3]:
	var out: Array[Vector3] = []
	_reach.clear()
	var player_m := float(_spec.get("collision_in_m", 1000.0))
	var soldier_m := float(_spec.get("soldier_in_m", 150.0))
	var vehicle_m := float(_spec.get("vehicle_in_m", 300.0))
	var soldiers := 0
	for holder: Node in [level.players, level.ai]:
		for n in holder.get_children():
			var s := n as Soldier
			if s and not s.is_queued_for_deletion() and not s.vitals.is_dead():
				out.append(s.global_position)
				_reach.append(player_m if holder == level.players else soldier_m)
				soldiers += 1
	var vehicles := 0
	for v: Node in get_tree().get_nodes_in_group(Vehicle.GROUP):
		if v is Node3D and level.is_ancestor_of(v) and not v.is_queued_for_deletion():
			out.append((v as Node3D).global_position)
			_reach.append(vehicle_m)
			vehicles += 1
	live_soldiers = soldiers
	live_vehicles = vehicles
	return out


func _stream(points: Array[Vector3], budget: int) -> void:
	var started := Time.get_ticks_usec()
	if points.is_empty():
		return
	var reach := _reach if _reach.size() == points.size() else PackedFloat32Array()
	var cover := PackedFloat32Array()
	var scale := float(_spec.get("scatter_in_m", 1200.0)) / float(_spec.get("collision_in_m", 1000.0))
	for r in reach:
		cover.append(r * scale)
	level.terrain.stream_collision(points, float(_spec.get("collision_in_m", 1000.0)), float(_spec.get("collision_out_m", 1300.0)), budget, reach)
	level.scatter.stream_collision(points, float(_spec.get("scatter_in_m", 1200.0)), float(_spec.get("scatter_out_m", 1500.0)),
		int(_spec.get("cells_per_tick", 3)) if budget >= 0 else -1, cover)
	last_ms = (Time.get_ticks_usec() - started) / 1000.0


## The ground (and cover) round `pos` now, whatever the budget: a vehicle that appears far from
## everyone (a QRF's technical, a column) never drops through.
func ensure(pos: Vector3, radius := 200.0) -> void:
	var at: Array[Vector3] = [pos]
	level.terrain.stream_collision(at, radius, INF, -1)
	level.scatter.stream_collision(at, radius, INF, -1)


func _on_node_added(n: Node) -> void:
	if n is Vehicle and level.is_ancestor_of(n):
		(func() -> void:
			if is_instance_valid(n) and n.is_inside_tree():
				ensure((n as Node3D).global_position)
				_draw_vehicle(n as Node3D)).call_deferred()


# --- Far drawing ------------------------------------------------------------------------------

func _apply_draw() -> void:
	var soldier_m := float(_spec.get("soldier_draw_m", 1500.0))
	for holder: Node in [level.players, level.ai]:
		for n in holder.get_children():
			if n is Soldier:
				_limit(n, soldier_m)
	for v: Node in get_tree().get_nodes_in_group(Vehicle.GROUP):
		if v is Node3D and level.is_ancestor_of(v):
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
