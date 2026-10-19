class_name BaseFob
extends Node3D
## The company's FOB (wave 4's base hub), wherever it stands: in BaseLevel (its own little level,
## at the origin) or in the base zone (BaseZoneLevel: the "fob" module of a full zone, docs/
## linked_zones.md LZ-1). Its node sits at the FOB's origin, so everything here is in FOB space:
## - the terminals (BaseTerminal: armory, shop, medbay, hiring, ops, motor pool, stores);
## - the armory: the company stash (BaseArmory) laid out on its floor as world items, to pick up
##   and drop back; what lies inside the wire counts as stash (in BaseLevel, anything in the hub);
## - the shop counter (DELIVERY), where bought items appear;
## - the muster line: the company's available people standing in their own gear, so players can
##   hand them kit before deploying.
## Campaign state is BaseHub's; this node only shows it and reads it back. The voxels it's built
## of are structure_boxes() (BaseLevel adds them to its voxel world; the zone's "fob" module
## builds module_boxes(): the same, and the helipad, vehicle park and firing range outside the wire).

## Where players appear: inside the gate.
const BASE_SPAWNS: Array[Vector3] = [Vector3(-3, 0.1, 15), Vector3(-1, 0.1, 15), Vector3(1, 0.1, 15), Vector3(3, 0.1, 15)]
## The muster line: where the available roster stands (in hiring order), and how many.
const MUSTER_ORIGIN := Vector3(-5.6, 0.1, 1.0)
const MUSTER_STEP := Vector3(1.4, 0.0, 0.0)
const MUSTER_ROWS := Vector3(0.0, 0.0, 1.8)
const MUSTER_PER_ROW := 9
const MUSTER_MAX := 18
## Where bought items are delivered (the shop counter, by the armory door).
const DELIVERY := Vector3(-9.4, 0.4, -6.3)
## The terminals: kind, position (feet), facing (y degrees).
const TERMINALS := [
	[&"armory", Vector3(-14.0, 0, -6.6), 0.0],
	[&"shop", Vector3(-7.0, 0, -6.6), 0.0],
	[&"medbay", Vector3(13.6, 0, -6.6), 0.0],
	[&"hiring", Vector3(-6.0, 0, 6.0), 90.0],
	[&"ops", Vector3(-6.0, 0, 8.2), 90.0],
	[&"motor_pool", Vector3(5.0, 0, 8.0), -90.0],
	[&"stores", Vector3(3.0, 0, -6.6), 0.0],
]
const PERIMETER_HALF := 19.5
const GATE_HALF := 3.0
## Outside the wire (the base zone's "fob" module only; LZ-1): the helipad east of the wire, the
## vehicle park south of the gate, the firing range west. Proposed.
const HELIPAD := Rect2(30.0, -8.0, 16.0, 16.0)
const VEHICLE_PARK := Rect2(-12.0, 27.0, 24.0, 18.0)
const RANGE_LINE_X := -26.0
const RANGE_END_X := -57.0
## The module's half footprint (ZoneModules.HALF["fob"]): the wire and all of that.
const MODULE_HALF := Vector2(60.0, 50.0)

## The level it stands in (items, spawning).
var level: CompoundLevel
## Only items inside the wire are stash (the base zone); false: anything in the level (BaseLevel).
var wire_only := false
## Host: member id -> the Soldier standing for them at the muster line.
var _muster := {}


## Puts a FOB into `p_level` at `origin` (its terminals with it). Every peer.
static func make(p_level: CompoundLevel, origin: Vector3, p_wire_only: bool) -> BaseFob:
	var fob := BaseFob.new()
	fob.name = "Fob"
	fob.level = p_level
	fob.wire_only = p_wire_only
	fob.position = origin
	p_level.add_child(fob)
	for t: Array in TERMINALS:
		var terminal := BaseTerminal.new(t[0])
		terminal.position = t[1]
		terminal.rotation_degrees.y = t[2]
		fob.add_child(terminal)
	return fob


## The i-th spawn point inside the gate (level space).
func spawn_point(i: int) -> Vector3:
	return to_global(BASE_SPAWNS[i % BASE_SPAWNS.size()])


## Whether `p` (level space) is inside the wire.
func holds(p: Vector3) -> bool:
	var q := to_local(p)
	return absf(q.x) < PERIMETER_HALF and absf(q.z) < PERIMETER_HALF


# --- The stash ----------------------------------------------------------------------------

## Host: lays the stash out as world items (armory floor first).
func server_spawn_stash(stash: Array) -> void:
	var slots := BaseArmory.layout(stash)
	for i in stash.size():
		var entry: Dictionary = stash[i]
		level.spawn_item(StringName(entry.id), int(entry.count), to_global(BaseArmory.slot_position(slots[i])), "stash_%d_%d" % [i, Time.get_ticks_usec()],
			GameState.from_json(entry.get("state", {})))


## Host: everything lying in the hub (or inside the wire) now, as stash entries.
func server_collect_stash() -> Array:
	var kept: Array = level.items.get_children()
	if wire_only:
		kept = kept.filter(func(n: Node) -> bool: return n is Node3D and holds((n as Node3D).global_position))
	return BaseArmory.from_world_items(kept)


## Host: puts a new item into the stash where it can be seen (a delivery from the shop, an
## item back from a loadout change): onto an existing pile of the very same item if one lies
## in the armory, else into the next free slot of its category's band (BaseArmory.BANDS), then
## the overflow rows. Never on top of something else.
func server_deliver(id: StringName, count: int, state := {}) -> void:
	var key := Restock.stash_key(id, state)
	var occupied := {}
	for node: Node in level.items.get_children():
		var w := node as WorldItem
		if w == null or w.is_queued_for_deletion():
			continue
		var slot := BaseArmory.slot_at(to_local(w.global_position))
		if slot < 0:
			continue
		if Restock.stash_key(w.item_id, w.state) == key and (state.is_empty() or ItemDB.get_item(id).type == "ammo"):
			w.count += count
			return
		occupied[slot] = true
	level.spawn_item(id, count, to_global(BaseArmory.slot_position(BaseArmory.free_slot(id, occupied))), "stash_d_%d" % Time.get_ticks_usec(), state)


# --- The muster line ----------------------------------------------------------------------

## Host: the company's available people stand at the muster line in their own gear, holding
## (in hiring order, up to MUSTER_MAX); anyone no longer available leaves it. Their gear is
## read back with server_read_muster_gear.
func server_show_roster() -> void:
	var wanted := BaseHub.muster_ids()
	for mid: String in _muster.keys():
		if mid not in wanted or not is_instance_valid(_muster[mid]):
			var s: Soldier = _muster[mid]
			if is_instance_valid(s):
				BaseHub.server_store_member_gear(mid, s.inventory.net_state)
				s.queue_free()
			_muster.erase(mid)
	for i in mini(wanted.size(), MUSTER_MAX):
		var mid: String = wanted[i]
		if _muster.has(mid):
			continue
		var member := BaseHub.member(mid)
		var pos := to_global(MUSTER_ORIGIN + MUSTER_STEP * (i % MUSTER_PER_ROW) + MUSTER_ROWS * (i / MUSTER_PER_ROW))
		var stats := Roster.ai_stats(member)
		var s := level.spawn_soldier({"name": String(member.callsign), "faction": "friendly", "variant": "tan", "pos": pos,
			"loadout": [], "combat": stats.combat, "discipline": stats.discipline, "guard": false, "mode": "safe"})
		s.role = StringName(member.role)
		s.set_meta(&"roster_id", mid)
		s.inventory.net_state = GameState.from_json(member.get("gear", {}))
		s.rotation.y = PI + rotation.y  # facing the yard
		var brain := SquadAI.of(s)
		if brain:
			brain.order = Squad.Order.HOLD  # where they stand (SquadAI holds at its spawn point)
		_muster[mid] = s


## Host: the gear each person at the muster line has on them now (member id -> net_state).
func server_read_muster_gear() -> Dictionary:
	var out := {}
	for mid: String in _muster:
		var s: Soldier = _muster[mid]
		if is_instance_valid(s) and not s.is_queued_for_deletion():
			out[mid] = s.inventory.net_state.duplicate(true)
	return out


func muster_soldier(mid: String) -> Soldier:
	var s: Soldier = _muster.get(mid)
	return s if is_instance_valid(s) else null


# --- The voxels ---------------------------------------------------------------------------

## The FOB in voxel boxes ([from, to, VoxelWorld.Mat], metres from its origin): a HESCO perimeter
## with a gate to the south, the armory (cinder block, a roof, a doorway to the yard) in the
## north-west, the medbay (plaster) in the north-east, the motor pool's open shelter in the
## south-east and an ops hut by the yard. Doorways stay clear of NavBuilder's chunk edges
## (x and z = ±6, ±18).
static func structure_boxes() -> Array:
	var out: Array = []
	var M := VoxelWorld.Mat
	var h := PERIMETER_HALF
	out.append([Vector3(-h, 0, -h), Vector3(h, 2.2, -h + 1.0), M.HESCO])
	out.append([Vector3(-h, 0, -h), Vector3(-h + 1.0, 2.2, h), M.HESCO])
	out.append([Vector3(h - 1.0, 0, -h), Vector3(h, 2.2, h), M.HESCO])
	out.append([Vector3(-h, 0, h - 1.0), Vector3(-GATE_HALF, 2.2, h), M.HESCO])
	out.append([Vector3(GATE_HALF, 0, h - 1.0), Vector3(h, 2.2, h), M.HESCO])
	# Armory: 10 x 8.4 m, doorway (1.6 m) in the south wall at x -12.4..-10.8.
	_hut(out, Vector2(-16.2, -16.2), Vector2(-5.8, -7.4), -12.4, -10.8, M.CINDER_BLOCK)
	# Medbay: 10 x 8.4 m, doorway at x 10.2..11.8.
	_hut(out, Vector2(5.8, -16.2), Vector2(16.2, -7.4), 10.2, 11.8, M.PLASTER)
	# Ops hut by the yard: 4 x 5 m, open towards the yard (east).
	out.append([Vector3(-11.0, 0, 4.0), Vector3(-7.0, 2.6, 4.2), M.WOOD])
	out.append([Vector3(-11.0, 0, 9.8), Vector3(-7.0, 2.6, 10.0), M.WOOD])
	out.append([Vector3(-11.0, 0, 4.0), Vector3(-10.8, 2.6, 10.0), M.WOOD])
	out.append([Vector3(-11.0, 2.6, 4.0), Vector3(-7.0, 2.7, 10.0), M.CORRUGATED_IRON])
	# Motor pool: a corrugated-iron roof on four posts, open on every side (wave 5 parks here).
	for corner: Vector2 in [Vector2(7.0, 3.0), Vector2(16.6, 3.0), Vector2(7.0, 13.6), Vector2(16.6, 13.6)]:
		out.append([Vector3(corner.x, 0, corner.y), Vector3(corner.x + 0.3, 3.4, corner.y + 0.3), M.STEEL])
	out.append([Vector3(7.0, 3.4, 3.0), Vector3(16.9, 3.5, 13.9), M.CORRUGATED_IRON])
	# Sandbagged gate guard post.
	out.append([Vector3(4.0, 0, 15.6), Vector3(6.4, 1.2, 16.0), M.SANDBAG])
	return out


## The base zone's "fob" module: the FOB, and outside the wire the helipad (a concrete pad with
## its H), the vehicle park (a hardstand with a shelter and a row of barriers) and the firing
## range (a sandbagged firing line, wooden targets at 15 and 25 m, a HESCO backstop).
static func module_boxes() -> Array:
	var out := structure_boxes()
	var M := VoxelWorld.Mat
	var pad := HELIPAD
	out.append([Vector3(pad.position.x, 0, pad.position.y), Vector3(pad.end.x, 0.1, pad.end.y), M.CONCRETE])
	var c := pad.get_center()
	out.append([Vector3(c.x - 2.5, 0.1, c.y - 3.0), Vector3(c.x - 1.7, 0.12, c.y + 3.0), M.PLASTER])  # the H
	out.append([Vector3(c.x + 1.7, 0.1, c.y - 3.0), Vector3(c.x + 2.5, 0.12, c.y + 3.0), M.PLASTER])
	out.append([Vector3(c.x - 1.7, 0.1, c.y - 0.4), Vector3(c.x + 1.7, 0.12, c.y + 0.4), M.PLASTER])
	var park := VEHICLE_PARK
	out.append([Vector3(park.position.x, 0, park.position.y), Vector3(park.end.x, 0.1, park.end.y), M.CONCRETE])
	for x: float in [park.position.x + 1.0, park.position.x + 11.0]:
		for z: float in [park.position.y + 9.0, park.end.y - 1.0]:
			out.append([Vector3(x, 0.1, z), Vector3(x + 0.3, 3.6, z + 0.3), M.STEEL])
	out.append([Vector3(park.position.x + 1.0, 3.6, park.position.y + 9.0), Vector3(park.position.x + 11.3, 3.7, park.end.y - 0.7), M.CORRUGATED_IRON])
	for k in 5:
		var x := park.position.x + 13.0 + k * 2.0
		out.append([Vector3(x, 0.1, park.end.y - 1.0), Vector3(x + 1.6, 0.9, park.end.y - 0.6), M.CONCRETE])  # barriers
	# The range: firing line west of the wire, lanes out to the backstop.
	out.append([Vector3(RANGE_LINE_X - 0.6, 0, -8.0), Vector3(RANGE_LINE_X, 0.9, 8.0), M.SANDBAG])
	for z: float in [-6.0, -2.0, 2.0, 6.0]:
		for dist: float in [15.0, 25.0]:
			var x := RANGE_LINE_X - dist
			out.append([Vector3(x, 0, z - 0.05), Vector3(x + 0.1, 1.0, z + 0.05), M.WOOD])  # post
			out.append([Vector3(x, 1.0, z - 0.3), Vector3(x + 0.05, 1.8, z + 0.3), M.WOOD])  # the target
	out.append([Vector3(RANGE_END_X - 1.0, 0, -10.0), Vector3(RANGE_END_X, 2.2, 10.0), M.HESCO])
	return out


## A walled, roofed hut from `a` to `b` (x, z) with a doorway in its south wall between x
## `door_from` and `door_to`.
static func _hut(out: Array, a: Vector2, b: Vector2, door_from: float, door_to: float, mat: int) -> void:
	var t := 0.3
	var top := 3.0
	out.append([Vector3(a.x, 0, a.y), Vector3(b.x, top, a.y + t), mat])
	out.append([Vector3(a.x, 0, a.y), Vector3(a.x + t, top, b.y), mat])
	out.append([Vector3(b.x - t, 0, a.y), Vector3(b.x, top, b.y), mat])
	out.append([Vector3(a.x, 0, b.y - t), Vector3(door_from, top, b.y), mat])
	out.append([Vector3(door_to, 0, b.y - t), Vector3(b.x, top, b.y), mat])
	out.append([Vector3(door_from, 2.2, b.y - t), Vector3(door_to, top, b.y), mat])
	out.append([Vector3(a.x, top, a.y), Vector3(b.x, top + 0.2, b.y), VoxelWorld.Mat.CONCRETE])
