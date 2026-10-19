class_name WorldCache
extends StaticBody3D
## A lootable cache, crate or wreck-with-kit out in the open terrain (ZoneScatter's VALUABLE
## sites, WorldValuables): opens through the same two-pane LootWindow a vehicle's hold does
## (Vehicle, LootWindow, docs/loot_window.md — "crates other than vehicle holds don't exist as
## lootable nodes yet" was the gap; this closes it). Held in a VehicleCargo hold, the same class
## a vehicle's cargo is, so it drops into the existing loot flow rather than a parallel one:
## LootWindow and Soldier's loot RPCs treat it exactly like a vehicle's hold (Soldier._loot_target,
## _server_loot_move/_put/_take_class), and Prices/IntelReveal see whatever comes out of it the
## same as any other loot.
##
## Spawned through the zone's CacheSpawner (ZoneLevel._make_cache), so every peer (late joiners
## included) gets it the same way a vehicle does; the host seeds its contents once right after
## (server_seed), and Cargo:net_state keeps it in sync from there same as a vehicle's hold.
##
## Not saved across a zone reload (Proposed, kept simple): its contents are rolled fresh each
## time the zone hosts, like the rest of the scatter it comes from. A session that reloads the
## same zone sees the cache restocked, not as it was left.

const SIZE := Vector3(0.7, 0.45, 0.7)
const USE_REACH_M := 3.0
const CAPACITY_L := 150.0
const CAPACITY_KG := 300.0

var cargo_hold: VehicleCargo
var wrecked := false  # never true: a cache doesn't burn or get wrecked; kept for the loot interface
var uid := ""
var _label := "Cache"
## Wave 6 (keys): the item that opens it ("" for none: an open box). A locked box (an HQ's
## strongbox) opens for whoever carries its key; once opened it stays open (`unlocked`,
## replicated with the hold).
var key_id: StringName = &""
var unlocked := false


func _init(label := "Cache", key := &"") -> void:
	_label = label
	key_id = key
	name = "WorldCache"
	collision_layer = 1
	collision_mask = 0


func _ready() -> void:
	add_to_group(InteractionMenu.INTERACTABLES)
	cargo_hold = VehicleCargo.new(CAPACITY_L, CAPACITY_KG)
	cargo_hold.name = "Cargo"
	add_child(cargo_hold)
	var config := SceneReplicationConfig.new()
	config.add_property(^"Cargo:net_state")
	config.property_set_replication_mode(^"Cargo:net_state", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	config.add_property(^".:unlocked")
	config.property_set_replication_mode(^".:unlocked", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = config
	add_child(sync)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	shape.shape = box
	shape.position.y = SIZE.y * 0.5
	add_child(shape)
	add_child(_visual())


## A plain low-poly crate (placeholder, like SupplyPallet's make_visual): nothing fancy yet.
static func _visual() -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("5a4a34")
	box.material = material
	mesh.mesh = box
	mesh.position.y = SIZE.y * 0.5
	root.add_child(mesh)
	return root


func cargo() -> Node:
	return cargo_hold


func in_reach(actor: Node3D) -> bool:
	return actor != null and actor.global_position.distance_to(global_position) <= USE_REACH_M


func display_name() -> String:
	return _label


func action_point() -> Vector3:
	return global_position + Vector3.UP * (SIZE.y + 0.3)


func interaction_actions(actor: Node) -> Array[Dictionary]:
	var me := self
	var why := lock_problem(actor as Soldier)
	return [{"id": &"loot", "label": "Unlock and loot" if is_locked() and why == "" else "Loot", "disabled": why, "target": self,
		"call": func() -> void: (actor as Soldier)._hud.open_loot(me)}]


func is_locked() -> bool:
	return key_id != &"" and not unlocked


## Why `actor` can't get into it ("" when they can: it's open, or they carry its key).
func lock_problem(actor: Soldier) -> String:
	if not is_locked() or actor == null:
		return ""
	if actor.inventory.count_of(key_id) > 0 or actor.inventory.slots.values().has(key_id) or actor.inventory.hands == key_id:
		return ""
	return "Locked: it needs the %s" % (ItemDB.get_item(key_id).name if ItemDB.has_item(key_id) else String(key_id))


## Host: `actor` gets into it: opens it with its key if it's locked. Returns why not ("" when in).
func server_open_for(actor: Soldier) -> String:
	var why := lock_problem(actor)
	if why == "" and is_locked():
		unlocked = true
		print("[cache] %s opens %s with the %s" % [actor.display_name(), display_name(), key_id])
	return why


## Host only (WorldValuables, right after the spawner places it): stows `items`
## ([{"id", "count"}]) into the hold, as much as fits (sparse flavour loot, never expected to
## overflow its small capacity).
func server_seed(items: Array) -> void:
	for entry: Dictionary in items:
		cargo_hold.take(StringName(entry.id), int(entry.get("count", 1)))


## Host: moves one of `actor`'s entries into the hold (as Vehicle.server_load). Returns what to
## tell them.
func server_load(actor: Soldier, container: StringName, index: int, id: StringName) -> String:
	var inv := actor.inventory
	if container == &"":
		if inv.hands != id or id == &"":
			return ""
		if cargo_hold.take(id) <= 0:
			return "No room in the %s" % display_name()
		inv.release_hands()
		return "Loaded %s" % ItemDB.get_item(id).name
	var list: Array = inv.containers.get(container, [])
	if index < 0 or index >= list.size() or list[index].id != id:
		return ""
	var entry: Dictionary = list[index]
	var item := ItemDB.get_item(id)
	var n := mini(cargo_hold.room_for(VehicleCargo.HOLD, item, entry.get("state", {})), int(entry.count))
	if n <= 0:
		return "No room in the %s (%.0f of %.0f L, %.0f of %.0f kg)" % [display_name(), cargo_hold.used_litres(), cargo_hold.capacity_l, cargo_hold.total_mass(), cargo_hold.max_kg]
	var moved := inv.remove_entry(container, index, n)
	cargo_hold.take(moved.id, int(moved.count), moved.get("state", {}))
	return "Loaded %s%s" % [item.name, " x%d" % n if n > 1 else ""]


## Host: moves a hold entry to `actor` (as Vehicle.server_unload). Returns what to tell them.
func server_unload(actor: Soldier, index: int, id: StringName) -> String:
	var list := cargo_hold.entries()
	if index < 0 or index >= list.size() or list[index].id != id:
		return ""
	var entry: Dictionary = list[index]
	var item := ItemDB.get_item(id)
	var taken := 0
	if item.two_handed:
		taken = actor.inventory.take(id, 1, entry.get("state", {}))
	else:
		taken = actor.inventory.take(id, int(entry.count), entry.get("state", {}))
	if taken > 0:
		cargo_hold.remove_entry(VehicleCargo.HOLD, index, taken)
		return "Took %s%s" % [item.name, " x%d" % taken if taken > 1 else ""]
	var out := cargo_hold.remove_entry(VehicleCargo.HOLD, index, int(entry.count))
	var level := CompoundLevel.current(self)
	if level:
		level.server_spawn_dropped(out.id, int(out.count), global_position + Vector3.UP * (SIZE.y + 0.2), out.get("state", {}))
	return "No room on you: %s put down by the cache" % item.name
