class_name Charges
extends Node
## Placed explosive charges (breaching charges), placed like Arma Reforger's (Captain,
## 2026-10-11): with the charge picked (Shift+G) G shows a ghost of it on whatever surface the
## player looks at within PLACE_REACH_M, lined up with that surface, and Fire commits it there
## (G or Aim puts it away). It sticks to whatever it was placed on: the voxel world or terrain
## stays put, while a person (a hitbox) or anything that moves (a physics body that isn't
## static: vehicles from wave 5) carries it along. That is the hook for suicide bombers on
## foot and in vehicles later (an AI behaviour, not built here).
##
## One node per level, "Charges", on every peer (CompoundLevel._ready). The host decides:
## server_place_at() places one (a player's request, an objective's helper, later the AI); its
## fuse runs from then ("charge_fuse_s"), and it goes off where it is by then: a frag blast
## (Throwables) and a wider breaching carve of the voxels ("charge_radius_m"), the objectives
## hear of it (Objectives.server_charge_blast: a cache or AA site destroyed), and whatever it
## rides gets server_explosion(pos, kind) if it has one (vehicles). Every peer and late joiner
## builds the same charge under the same node (records, _client_add).

## Proposed: how far from the eye a charge can be placed.
## Proposed: a placed charge's filling for the gore it does to bodies (BlastGore), kg of TNT: a
## breaching charge's half kilo of plastic explosive, more than a grenade's.
const CHARGE_TNT_KG := 0.5
const PLACE_REACH_M := 2.5
## Placed this far off the surface (half the block's thickness and a little).
const SURFACE_OFFSET_M := 0.03
## What a charge can go on: world (voxels, terrain), hitboxes (people), movers (bodies), armor,
## vehicles (wave 5: it rides the hull and calls Vehicle.server_explosion).
const PLACE_MASK := (1 << 0) | (1 << 1) | (1 << 3) | (1 << 4) | Vehicle.LAYER
const ITEM := &"breaching_charge"
## The block's size (m): a 2 kg demolition block.
const SIZE := Vector3(0.22, 0.06, 0.14)
## A charge on a wall (its surface facing within WALL_NORMAL_Y of level; Captain, 2026-10-20:
## "breaching charges need to stop leaving big craters in the ground with a small line of
## unbroken fence or wall that cannot be walked past or over by AI"): it cuts a doorway through
## the wall, BREACH_W_M wide, from the ground or floor at the wall's foot up BREACH_H_M, up to
## BREACH_DEPTH_M deep (VoxelWorld.server_breach); its blast rounds the edges off above that
## floor only, and the ground isn't cratered. One set higher than BREACH_HIGH_M over the floor
## cuts the hole round itself instead. On the ground (or anything else) its crater is CRATER_M.
##
## The hole's size (Captain's list 2026-10-14, item 3: "breaching charges make holes too small";
## F-317): sized from the soldier who goes through it, not picked by eye. His capsule
## (scenes/soldier.tscn: SOLDIER_R round, SOLDIER_H tall) plus his kit (KIT_M each side at the
## shoulders: a plate carrier's pouches, a ruck's sides, a rifle held low; HEAD_KIT_M over the
## helmet: its NVG mount), plus SNAG_M of ragged voxel edge and walking off the middle on every
## side but the floor: 1.5 m wide and 2.25 m high (it was 1.3 x 2.2). It's cut from the lower of
## the floors either side of the wall up to the higher one plus that height (a building's floor
## stands above the street, or a slope runs under the wall: floor_y, hole_floors), so it's as
## high from the floor inside as from the ground outside. All Proposed.
const WALL_NORMAL_Y := 0.5
const SOLDIER_R := 0.3
const SOLDIER_H := 1.8
const KIT_M := 0.2
const HEAD_KIT_M := 0.2
const SNAG_M := 0.25
const BREACH_W_M := 2.0 * (SOLDIER_R + KIT_M + SNAG_M)
const BREACH_H_M := SOLDIER_H + HEAD_KIT_M + SNAG_M
const BREACH_DEPTH_M := 1.2
const BREACH_HIGH_M := 1.9
const CRATER_M := 0.4
## Host: the last few charges that went off ({"pos", "at", "by": the placer's instance id, or 0}),
## newest last: a squad stacked on a human breacher goes in on his (SquadAI, clearing).
const RECENT_MAX := 8
var recent: Array[Dictionary] = []

## Every peer: id -> {"id", "path" (the node it rides, from the level; "" for the level),
## "xform" (its transform in that node, as an Array), "world" (its world transform when
## placed), "fuse_s" (left when sent), "by" (who placed it)}.
var records: Dictionary = {}

var level: Node3D
var _next_id := 1
var _due := {}  # host: id -> Time (s) it goes off
var _last_pos := {}  # host: id -> where it was last seen (what it rode may be gone)
var _placer := {}  # host: id -> who placed it (instance id, 0 for nobody)


func _init() -> void:
	name = "Charges"


func _ready() -> void:
	level = get_parent() as Node3D
	Net.peer_joined.connect(_on_peer_joined)


## The charges node of the level `from` is in (or null).
static func of(from: Node) -> Charges:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(^"Charges") as Charges if lvl else null


# --- Where a charge can go (every peer: the ghost; the host: the check) ---------------------

## Where `actor` can put a charge looking from `from` along `dir`: {"ok", "pos", "normal",
## "target" (the node it would ride, or null for the world), "why"}. Their own body doesn't
## count as a surface.
static func placement(actor: Soldier, from: Vector3, dir: Vector3) -> Dictionary:
	var out := {"ok": false, "pos": from + dir * PLACE_REACH_M, "normal": Vector3.UP, "target": null, "why": "Nothing to place it on"}
	if actor == null or not actor.is_inside_tree() or not Soldier.usable_direction(dir):
		return out
	var space := actor.get_world_3d().direct_space_state
	var exclude: Array[RID] = [actor.get_rid()]
	for child in actor.get_children():
		if child is CollisionObject3D:
			exclude.append((child as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * PLACE_REACH_M, PLACE_MASK, exclude)
	query.collide_with_areas = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return out
	var collider := hit.collider as Node
	out.pos = hit.position
	out.normal = (hit.normal as Vector3).normalized() if (hit.normal as Vector3).length() > 0.1 else Vector3.UP
	out.target = rider_of(collider)
	out.ok = true
	out.why = ""
	return out


## The node a charge stuck on `collider` rides: a person's hitbox (it follows that part),
## anything that moves (a body that isn't static, or its own node), or null for the world.
static func rider_of(collider: Node) -> Node3D:
	var n := collider
	while n != null:
		if n is Area3D and n.get_parent() is Soldier:
			return n as Node3D
		if n is Soldier or n is RigidBody3D or n is AnimatableBody3D or n is VehicleBody3D or (n is CharacterBody3D):
			return n as Node3D
		if n is StaticBody3D or n is CompoundLevel:
			return null
		n = n.get_parent()
	return null


## A charge's transform at `pos` on a surface with `normal`: its flat face against it, its long
## side across `look` (the placer's view).
static func surface_transform(pos: Vector3, normal: Vector3, look: Vector3) -> Transform3D:
	var up := normal.normalized()
	var forward := (look - up * look.dot(up))
	if forward.length() < 0.05:
		forward = up.cross(Vector3.RIGHT) if absf(up.dot(Vector3.RIGHT)) < 0.9 else up.cross(Vector3.FORWARD)
	forward = forward.normalized()
	var right := up.cross(forward).normalized()
	return Transform3D(Basis(right, up, -forward), pos + up * SURFACE_OFFSET_M)


# --- Host ------------------------------------------------------------------------------

## A player asks to place a charge looking from `from` along `dir` (the ghost's spot). The
## host checks it again from their body and places it. Any peer calls it (rpc_id 1).
@rpc("any_peer", "call_local", "reliable")
func request_place(from: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var lvl := level as CompoundLevel
	var sender := multiplayer.get_remote_sender_id()
	var actor := lvl.players.get_node_or_null(str(sender if sender != 0 else 1)) as Soldier if lvl else null
	if actor == null or not actor.vitals.is_up() or actor.inventory.count_of(ITEM) <= 0 or actor.carry_mode != &"":
		return
	if not Soldier.usable_point(from) or from.distance_to(actor.camera.global_position) > 1.0:
		from = actor.camera.global_position  # don't trust a far-off eye
	var spot := placement(actor, from, dir)
	if not spot.ok:
		return
	server_place_at(actor, surface_transform(spot.pos, spot.normal, dir), spot.target)


## Host only. Puts one of `by`'s charges (taken from their kit; with `by` null nobody's) at
## `xform` (world), riding `target` (null: the world). Returns its id, or "" if `by` has none.
func server_place_at(by: Soldier, xform: Transform3D, target: Node3D = null) -> String:
	if not multiplayer.is_server():
		return ""
	if by and not by.inventory.remove_one(ITEM):
		return ""
	var id := "C%d" % _next_id
	_next_id += 1
	var path := ""
	var local := xform
	if target and is_instance_valid(target) and level.is_ancestor_of(target):
		path = str(level.get_path_to(target))
		local = target.global_transform.affine_inverse() * xform
	var fuse := MissionRegistry.setting_f("charge_fuse_s", 10.0)
	var rec := {"id": id, "path": path, "xform": _pack(local), "world": _pack(xform), "fuse_s": fuse, "by": by.display_name() if by else ""}
	_due[id] = _now() + fuse
	_placer[id] = by.get_instance_id() if by else 0
	print("[charges] %s placed by %s on %s (fuse %.0f s)" % [id, rec.by, path if path != "" else "the world", fuse])
	_client_add.rpc(rec)
	if by and not by.is_ai():
		by._client_message.rpc_id(by.owner_peer(), "Charge set: %d s" % roundi(fuse))
	return id


## Host only. Where charge `id` is now (it may have moved with what it rides).
func position_of(id: String) -> Vector3:
	var node := get_charge_node(id)
	if node:
		return node.global_position
	if _last_pos.has(id):
		return _last_pos[id]
	var w: Array = records.get(id, {}).get("world", [])
	return _unpack(w).origin if w.size() == 12 else Vector3.ZERO


func _process(_delta: float) -> void:
	if _due.is_empty() or not multiplayer.is_server():
		return
	var now := _now()
	for id: String in _due.keys():
		var node := get_charge_node(id)
		if node:
			_last_pos[id] = node.global_position
		if now >= float(_due[id]):
			_detonate(id)


func _detonate(id: String) -> void:
	_due.erase(id)
	var pos := position_of(id)
	_last_pos.erase(id)
	var node := get_charge_node(id)
	var rides: Node = node.get_parent() if node else null
	var wall := wall_normal(records.get(id, {}), rides == null or rides == level)
	_client_remove.rpc(id)
	var by := int(_placer.get(id, 0))
	_placer.erase(id)
	var lvl := level as CompoundLevel
	if lvl == null:
		return
	recent.append({"pos": pos, "at": _now(), "by": by})
	if recent.size() > RECENT_MAX:
		recent.pop_front()
	print("[charges] %s went off at (%.1f, %.1f, %.1f)%s" % [id, pos.x, pos.y, pos.z, " on a wall" if wall != Vector3.ZERO else ""])
	Throwables.server_detonate(lvl, "frag", pos, &"", CHARGE_TNT_KG, false, wall)
	var radius := MissionRegistry.setting_f("charge_radius_m", 1.6)
	if wall != Vector3.ZERO:
		var floors := hole_floors(lvl, pos, wall)
		var floor_y: float = floors.x
		var high := BREACH_H_M + (floors.y - floors.x)  # as high over the higher floor as over the lower
		if pos.y - floor_y > BREACH_HIGH_M:
			floor_y = pos.y - BREACH_H_M * 0.5
			high = BREACH_H_M
		lvl.server_breach(pos, wall, floor_y, BREACH_W_M, high, BREACH_DEPTH_M)
		lvl.server_blast(pos, minf(radius, maxf(pos.y - floor_y, 0.2)), 0.0)  # ragged edges, nothing below the floor, no crater
	else:
		lvl.server_blast(pos, radius, CRATER_M)
	PeopleLayer.server_noise(lvl, pos, PeopleLayer.BLAST_HEARD_M)
	Alert.server_noise(lvl, pos, Alert.BLAST)
	if rides and rides != level and is_instance_valid(rides):
		var owner_body: Node = rides.get_parent() if rides is Area3D else rides
		if owner_body.has_method(&"server_explosion"):
			owner_body.call(&"server_explosion", pos, "breaching_charge")
	Contracts.objectives.server_charge_blast(pos)


## The outward normal of the wall charge record `rec` was set on (level), or Vector3.ZERO if it
## wasn't set on a wall of the world (`on_world`): on the ground, a crate, a person, a vehicle.
## A charge's surface faces along its basis' y (surface_transform).
static func wall_normal(rec: Dictionary, on_world: bool) -> Vector3:
	var w: Array = rec.get("world", [])
	if not on_world or w.size() != 12:
		return Vector3.ZERO
	var n := _unpack(w).basis.y.normalized()
	if absf(n.y) >= WALL_NORMAL_Y:
		return Vector3.ZERO
	return Vector3(n.x, 0.0, n.z).normalized()


## The ground or floor at the foot of the wall a charge at `pos` sits on (`normal` its outer
## face): straight down from just outside it (the world's layer), never above the charge.
static func floor_under(lvl: Node3D, pos: Vector3, normal: Vector3) -> float:
	var from := pos + normal * 0.35 + Vector3.UP * 0.1
	var hit := lvl.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0, 1))
	if hit.is_empty():
		return pos.y - 1.0
	return minf((hit.position as Vector3).y, pos.y - 0.1)


## The floors either side of the wall a charge at `pos` sits on (`normal` its outer face), as
## Vector2(lower, higher): the ground at its foot outside (floor_under) and the floor behind it,
## straight down from just past the wall's inner face (wall_depth); with no inner face found
## within BREACH_DEPTH_M (a wall thicker than that, or the far side solid), the outside one twice.
## Never above the charge.
static func hole_floors(lvl: Node3D, pos: Vector3, normal: Vector3) -> Vector2:
	var outside := floor_under(lvl, pos, normal)
	var depth := wall_depth(lvl, pos, normal)
	if depth < 0.0:
		return Vector2(outside, outside)
	var from := pos - normal * (depth + 0.35) + Vector3.UP * 0.1
	var hit := lvl.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0, 1))
	if hit.is_empty():
		return Vector2(outside, outside)
	var inside := minf((hit.position as Vector3).y, pos.y - 0.1)
	return Vector2(minf(outside, inside), maxf(outside, inside))


## How thick the wall a charge at `pos` sits on is (`normal` its outer face): from the charge to
## its inner face, found from behind it (a level ray back out from BREACH_DEPTH_M in); -1 when no
## inner face is found that close (a ray that starts inside something solid finds nothing).
static func wall_depth(lvl: Node3D, pos: Vector3, normal: Vector3) -> float:
	var n := Vector3(normal.x, 0.0, normal.z).normalized()
	var from := pos - n * (BREACH_DEPTH_M + 0.1)
	var query := PhysicsRayQueryParameters3D.create(from, pos + n * 0.02, 1)
	query.hit_back_faces = false
	var hit := lvl.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit.normal as Vector3).dot(n) > -0.5:
		return -1.0
	return maxf((pos - (hit.position as Vector3)).dot(n), 0.0)


## Host: where a charge went off within `radius_m` of `point` (flat) since `since`, placed by the
## soldier with instance id `by` (anyone's if 0); Vector3.INF if none did.
func blast_near(point: Vector3, radius_m: float, since: float, by := 0) -> Vector3:
	for i in range(recent.size() - 1, -1, -1):
		var r: Dictionary = recent[i]
		var at: Vector3 = r.pos
		if float(r.at) >= since and (by == 0 or int(r.by) == by) and Vector2(at.x - point.x, at.z - point.z).length() <= radius_m:
			return at
	return Vector3.INF


# --- Every peer ---------------------------------------------------------------------------

## The charge's node on this peer (or null).
func get_charge_node(id: String) -> Node3D:
	var rec: Dictionary = records.get(id, {})
	if rec.is_empty():
		return null
	var parent := level.get_node_or_null(NodePath(String(rec.path))) if String(rec.path) != "" else level
	var node := parent.get_node_or_null(NodePath("Charge_" + id)) if parent else null
	if node == null:
		node = level.get_node_or_null(NodePath("Charge_" + id))
	return node as Node3D


@rpc("authority", "call_local", "reliable")
func _client_add(rec: Dictionary) -> void:
	records[rec.id] = rec
	var parent: Node3D = level
	var xform := _unpack(rec.world)
	if String(rec.path) != "":
		var target := level.get_node_or_null(NodePath(String(rec.path))) as Node3D
		if target:
			parent = target
			xform = _unpack(rec.xform)
	var node := make_visual()
	node.name = "Charge_" + String(rec.id)
	parent.add_child(node)
	node.transform = xform


@rpc("authority", "call_local", "reliable")
func _client_remove(id: String) -> void:
	var node := get_charge_node(id)
	if node:
		node.queue_free()
	records.erase(id)


func _on_peer_joined(id: int) -> void:
	if not multiplayer.is_server():
		return
	for rec: Dictionary in records.values():
		var r := rec.duplicate()
		r.fuse_s = maxf(float(_due.get(rec.id, _now())) - _now(), 0.0)
		r.world = _pack(get_charge_node(rec.id).global_transform) if get_charge_node(rec.id) else rec.world
		_client_add.rpc_id(id, r)


## The charge's look (placeholder: an olive block with a red light); the ghost uses it too.
static func make_visual(ghost := false) -> Node3D:
	var root := Node3D.new()
	var block := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = SIZE
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.38, 0.26)
	if ghost:
		m.albedo_color = Color(0.4, 1.0, 0.4, 0.45)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = m
	block.mesh = box
	block.name = "Block"
	root.add_child(block)
	var light := MeshInstance3D.new()
	var dot := BoxMesh.new()
	dot.size = Vector3(0.02, 0.02, 0.02)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(1, 0.1, 0.05)
	lm.emission_enabled = true
	lm.emission = Color(1, 0.1, 0.05)
	dot.material = lm
	light.mesh = dot
	light.position = Vector3(0.07, SIZE.y * 0.5 + 0.01, 0.0)
	root.add_child(light)
	return root


static func _pack(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]


static func _unpack(a: Array) -> Transform3D:
	if a.size() != 12:
		return Transform3D.IDENTITY
	return Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])), Vector3(a[9], a[10], a[11]))


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
