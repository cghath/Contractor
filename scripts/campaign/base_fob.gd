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
## Defences the company can buy for the FOB (docs/linked_zones.md 1b / LZ-6, "bought at the ops
## desk ... placed at set slots"): id -> {"name", "price", "slot": [x, z] FOB space (on the zones'
## 12 m grid), "half": the module's half footprint}. Each is a small module of its own in the base
## zone (ZoneModules type "fob_<id>": defence_boxes). Proposed prices.
const DEFENCES := {
	"tower_ne": {"name": "Watchtower (north-east corner)", "price": 12000, "slot": [24, -24], "half": [3, 3], "tier": 2},
	"tower_sw": {"name": "Watchtower (south-west corner)", "price": 12000, "slot": [-24, 24], "half": [3, 3], "tier": 2},
	"mg_pit": {"name": "MG pit covering the gate", "price": 6000, "slot": [12, 24], "half": [3, 3], "tier": 1},
	"chicane": {"name": "HESCO chicane before the gate", "price": 4000, "slot": [0, 36], "half": [8, 3], "tier": 1},
	"bunker": {"name": "Concrete bunker", "price": 15000, "slot": [-24, -24], "half": [4, 4], "tier": 2},
	# (docs/linked_zones.md 1b: "MG and mortar pits, sensors"; "cover": how much it counts for when
	# the wire holds without the squad, BaseAssault; 1 if not given. Sensors watch: sensor_report.)
	"mortar_pit": {"name": "Mortar pit", "price": 18000, "slot": [0, -36], "half": [3, 3], "tier": 2, "cover": 2},
	"sensor": {"name": "Ground sensors on the approaches", "price": 5000, "slot": [36, 36], "half": [1, 1], "tier": 1, "cover": 0},
}
## Sensors (a "sensor" defence): hostiles this close to the FOB are reported on the radio, at most
## every SENSOR_GAP_S. Proposed.
const SENSOR_M := 300.0
const SENSOR_GAP_S := 60.0
## FOB tiers (docs/linked_zones.md 1b: "FOB tiers (bigger wire, more defence slots, more squads)
## unlock hot zones, better supports and the player-built faction"): tier -> {"price" to reach it,
## "guards" the most it keeps, "squads" hired company squads (LZ-6's next part)}. The company
## starts at 1. Proposed.
const TIERS := {
	1: {"price": 0, "guards": 4, "squads": 0},
	2: {"price": 40000, "guards": 8, "squads": 1},
	3: {"price": 120000, "guards": 8, "squads": 2},
}


## Placing defences yourself (DefencePlacer, LZ-6): within BUILD_HALF of the FOB's centre (its
## module sits at the zone's origin, so FOB and zone metres agree), on the zones' grid, at most
## MAX_PLACED of each kind besides its slot. Proposed.
const BUILD_HALF := 96.0
const MAX_PLACED := 3


## The base's defences as {"id", "pos": [x, z]} (BaseHub base "defences": an id is built at its
## slot, a {"id", "pos"} where it was placed).
static func defence_places(defences: Array) -> Array:
	var out: Array = []
	for e: Variant in defences:
		if e is String and DEFENCES.has(e):
			out.append({"id": e, "pos": DEFENCES[e].slot, "placed": false})
		elif e is Dictionary and DEFENCES.has(String(e.get("id", ""))):
			out.append({"id": String(e.id), "pos": e.pos, "placed": true})
	return out


## Why defence `id` can't stand at `at` (zone metres, its centre) among `defences` (as BaseHub
## keeps them), or "": inside the build area, clear of the helipad, the vehicle park, the range
## and every other defence, and not more than MAX_PLACED of a kind placed.
static func placement_problem(id: String, at: Vector2, defences: Array) -> String:
	if not DEFENCES.has(id):
		return "No such defence"
	var half := Vector2(float(DEFENCES[id].half[0]), float(DEFENCES[id].half[1]))
	var rect := Rect2(at - half, half * 2.0)
	if absf(at.x) + half.x > BUILD_HALF or absf(at.y) + half.y > BUILD_HALF:
		return "outside the base's build area"
	var range_rect := Rect2(RANGE_END_X, -8.0, RANGE_LINE_X - RANGE_END_X, 16.0)
	for keep: Array in [[HELIPAD, "the helipad"], [VEHICLE_PARK, "the vehicle park"], [range_rect, "the range"]]:
		if rect.grow(-0.01).intersects(keep[0]):
			return "that's %s" % keep[1]
	var placed := 0
	for e: Variant in defences:
		if e is Dictionary and String(e.get("id", "")) == id:
			placed += 1
	if placed >= MAX_PLACED:
		return "%d placed already" % MAX_PLACED
	for d: Dictionary in defence_places(defences):
		var dh := Vector2(float(DEFENCES[d.id].half[0]), float(DEFENCES[d.id].half[1]))
		var other := Rect2(Vector2(float(d.pos[0]), float(d.pos[1])) - dh, dh * 2.0)
		if rect.grow(-0.01).intersects(other):
			return "another defence stands there"
	return ""


## How much `defences` (BaseHub base "defences") count for holding the wire (each its "cover").
static func defence_cover(defences: Array) -> int:
	var n := 0
	for d: Dictionary in defence_places(defences):
		n += int(DEFENCES[d.id].get("cover", 1))
	return n


## Whether any sensor is built.
static func has_sensors(defences: Array) -> bool:
	return defence_places(defences).any(func(d: Dictionary) -> bool: return String(d.id) == "sensor")


## The sensors' line for hostiles at `contacts` (positions) around a FOB at `centre`, or "".
static func sensor_report(centre: Vector3, contacts: Array) -> String:
	var near := contacts.filter(func(p: Vector3) -> bool: return Vector2(p.x - centre.x, p.z - centre.z).length() <= SENSOR_M)
	if near.is_empty():
		return ""
	var mid := Vector3.ZERO
	for p: Vector3 in near:
		mid += p
	mid /= near.size()
	return "Sensors: %d contact%s %s of the wire, %d m out" % [near.size(), "" if near.size() == 1 else "s",
		_compass(Vector2(mid.x - centre.x, mid.z - centre.z)),
		roundi(Vector2(mid.x - centre.x, mid.z - centre.z).length())]


static func _compass(d: Vector2) -> String:
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	var a := fposmod(atan2(d.x, -d.y), TAU)  # 0 = north (-z), clockwise
	return names[int(round(a / (TAU / 8.0))) % 8]


## Defences with a front (Captain, 2026-10-20: "the mg pit places backwards at the base"): drawn
## facing north (their front at -z), each placed one is turned to face out of the base, away from
## its centre (facing_for: the nearest of n, e, s, w), its open side or way in toward the wire.
## The MG pit "covering the gate" stood with its back wall to the base and its open side to the
## gate, south.
const DIRECTIONAL: Array[String] = ["mg_pit", "bunker", "mortar_pit"]


## The way a defence at `pos` (FOB space, metres from its centre; +z south) faces: out of the base.
static func facing_for(pos: Vector2) -> String:
	if pos.length() < 0.5:
		return "n"
	if absf(pos.x) > absf(pos.y):
		return "e" if pos.x > 0.0 else "w"
	return "s" if pos.y > 0.0 else "n"


## The module type of defence `id` placed at `pos`: "fob_<id>", with "@<facing>" for one with a
## front (DIRECTIONAL).
static func defence_type(id: String, pos: Vector2) -> String:
	return "fob_%s@%s" % [id, facing_for(pos)] if id in DIRECTIONAL else "fob_" + id


## A defence's voxel boxes, metres from its own origin, turned to `facing` (n, e, s, w; drawn n).
static func defence_boxes(id: String, facing := "n") -> Array:
	var out := _defence_boxes_north(id)
	if facing == "n":
		return out
	var turned: Array = []
	for b: Array in out:
		var a := _turn(b[0] as Vector3, facing)
		var z := _turn(b[1] as Vector3, facing)
		turned.append([a.min(z), a.max(z)] + b.slice(2))
	return turned


static func _turn(p: Vector3, facing: String) -> Vector3:
	match facing:
		"s":
			return Vector3(-p.x, p.y, -p.z)
		"e":
			return Vector3(-p.z, p.y, p.x)  # the front (-z) to +x
		"w":
			return Vector3(p.z, p.y, -p.x)  # the front (-z) to -x
	return p


static func _defence_boxes_north(id: String) -> Array:
	var out: Array = []
	var M := VoxelWorld.Mat
	match id:
		"tower_ne", "tower_sw":
			ZoneModules._tower(out, Vector2(-1.3, -1.3), ["n", "s", "e", "w"])
		"mg_pit":
			out.append([Vector3(-1.6, 0, -1.6), Vector3(1.6, 0.9, -1.2), M.SANDBAG])
			out.append([Vector3(-1.6, 0, -1.2), Vector3(-1.2, 0.9, 1.6), M.SANDBAG])
			out.append([Vector3(1.2, 0, -1.2), Vector3(1.6, 0.9, 1.6), M.SANDBAG])  # open to the south: the way in
		"chicane":
			out.append([Vector3(-7.0, 0, -0.5), Vector3(-1.5, 2.2, 0.5), M.HESCO])
			out.append([Vector3(1.5, 0, -2.5), Vector3(7.0, 2.2, -1.5), M.HESCO])
		"mortar_pit":
			out.append([Vector3(-2.6, 0, -2.6), Vector3(2.6, 0.8, -2.2), M.SANDBAG])
			out.append([Vector3(-2.6, 0, 2.2), Vector3(-0.6, 0.8, 2.6), M.SANDBAG])
			out.append([Vector3(0.6, 0, 2.2), Vector3(2.6, 0.8, 2.6), M.SANDBAG])  # the way in, south
			out.append([Vector3(-2.6, 0, -2.2), Vector3(-2.2, 0.8, 2.2), M.SANDBAG])
			out.append([Vector3(2.2, 0, -2.2), Vector3(2.6, 0.8, 2.2), M.SANDBAG])
			out.append([Vector3(-0.3, 0, -0.3), Vector3(0.3, 0.9, 0.3), M.CONCRETE])  # the tube's base plate
		"sensor":
			out.append([Vector3(-0.15, 0, -0.15), Vector3(0.15, 1.4, 0.15), M.CONCRETE])  # the mast
		"bunker":
			out.append([Vector3(-3.0, 0, -3.0), Vector3(3.0, 2.2, -2.6), M.CONCRETE])
			out.append([Vector3(-3.0, 0, -2.6), Vector3(-2.6, 2.2, 3.0), M.CONCRETE])
			out.append([Vector3(2.6, 0, -2.6), Vector3(3.0, 2.2, 3.0), M.CONCRETE])
			out.append([Vector3(-2.6, 0, 2.6), Vector3(-0.6, 2.2, 3.0), M.CONCRETE])
			out.append([Vector3(0.6, 0, 2.6), Vector3(2.6, 2.2, 3.0), M.CONCRETE])
			out.append([Vector3(-3.0, 1.3, -3.0), Vector3(3.0, 1.5, -2.6), M.EMPTY])  # firing slit, north
			out.append([Vector3(-3.0, 2.2, -3.0), Vector3(3.0, 2.5, 3.0), M.CONCRETE])
	return out


## The module's half footprint (ZoneModules.HALF["fob"]): the wire and all of that.
const MODULE_HALF := Vector2(60.0, 50.0)

## The level it stands in (items, spawning).
var level: CompoundLevel
## Only items inside the wire are stash (the base zone); false: anything in the level (BaseLevel).
var wire_only := false
## Host: member id -> the Soldier standing for them at the muster line.
var _muster := {}
## Where things stand, if not the FOB's own (make's `p_layout`; the LHD's: LhdLayout.fob_layout),
## all in this node's space: "terminals" (as TERMINALS), "spawns" (as BASE_SPAWNS), "muster_origin",
## "muster_step", "muster_rows", "muster_per_row", "muster_max", "muster_facing" (y, radians: which
## way the line faces), and "holds" (a Rect2 on x, z: what counts as inside; the wire's square if not
## given). The armory floor (BaseArmory's slots) is the same everywhere.
var layout := {}


## Puts a FOB into `p_level` at `origin` (its terminals with it), laid out as `p_layout` says
## (layout; {}: the FOB's own). Every peer.
static func make(p_level: CompoundLevel, origin: Vector3, p_wire_only: bool, p_layout := {}) -> BaseFob:
	var fob := BaseFob.new()
	fob.name = "Fob"
	fob.level = p_level
	fob.wire_only = p_wire_only
	fob.layout = p_layout
	fob.position = origin
	p_level.add_child(fob)
	for t: Array in fob.lay("terminals", TERMINALS):
		var terminal := BaseTerminal.new(t[0])
		terminal.position = t[1]
		terminal.rotation_degrees.y = t[2]
		fob.add_child(terminal)
	return fob


## The layout's `key` (layout), else `fallback` (the FOB's own).
func lay(key: String, fallback: Variant) -> Variant:
	return layout.get(key, fallback)


## The i-th spawn point inside the gate (level space).
func spawn_point(i: int) -> Vector3:
	var spawns: Array = lay("spawns", BASE_SPAWNS)
	return to_global(spawns[i % spawns.size()])


## Whether `p` (level space) is inside the wire (or the layout's "holds").
func holds(p: Vector3) -> bool:
	var q := to_local(p)
	if layout.has("holds"):
		return (layout.holds as Rect2).has_point(Vector2(q.x, q.z))
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
	var per_row := int(lay("muster_per_row", MUSTER_PER_ROW))
	for i in mini(wanted.size(), int(lay("muster_max", MUSTER_MAX))):
		var mid: String = wanted[i]
		if _muster.has(mid):
			continue
		var member := BaseHub.member(mid)
		var pos: Vector3 = to_global(lay("muster_origin", MUSTER_ORIGIN) + lay("muster_step", MUSTER_STEP) * (i % per_row) + lay("muster_rows", MUSTER_ROWS) * (i / per_row))
		var stats := Roster.ai_stats(member)
		var s := level.spawn_soldier({"name": String(member.callsign), "faction": "friendly", "variant": Soldier.COMPANY_VARIANT, "pos": pos,
			"loadout": [], "combat": stats.combat, "discipline": stats.discipline, "guard": false, "mode": "safe"})
		s.role = StringName(member.role)
		s.set_meta(&"roster_id", mid)
		s.inventory.net_state = GameState.from_json(member.get("gear", {}))
		s.rotation.y = float(lay("muster_facing", PI)) + rotation.y  # facing the yard
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
