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
## included) gets it the same way a vehicle does; the host fills it once right after
## (server_fill), and Cargo:net_state keeps it in sync from there same as a vehicle's hold.
##
## Saved with the zone (compound loot, 2026-10-19): GameState.save_zone keeps what's in every
## cache (to_save, in GameState.caches by uid) and server_fill puts that back instead of a fresh
## roll, so a box looted (or used as a stash) stays as it was left after a reload.

const SIZE := Vector3(0.7, 0.45, 0.7)
## Every live cache (GameState.save_zone reads them).
const GROUP := &"world_caches"
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
## Fallen's loot states (LootStates, docs/survival_events.md; call 125): searched once opened (the
## box looks picked over: lid up, its colour dulled; replicated, kept by the zone save), the world
## day it was searched (the refill reads it), how often it refilled, whether a crowbar opened it,
## and a hidden cache's buried look (its label).
var searched := false:
	set(v):
		searched = v
		_apply_look()
var searched_day := 0.0
var refills := 0
var pried := false
var hidden := false


func _init(label := "Cache", key := &"") -> void:
	_label = label
	key_id = key
	hidden = label == LootStates.HIDDEN_LABEL
	name = "WorldCache"
	collision_layer = 1
	collision_mask = 0


func _ready() -> void:
	add_to_group(InteractionMenu.INTERACTABLES)
	add_to_group(GROUP)
	cargo_hold = VehicleCargo.new(CAPACITY_L, CAPACITY_KG)
	cargo_hold.name = "Cargo"
	add_child(cargo_hold)
	var config := SceneReplicationConfig.new()
	config.add_property(^"Cargo:net_state")
	config.property_set_replication_mode(^"Cargo:net_state", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	config.add_property(^".:unlocked")
	config.property_set_replication_mode(^".:unlocked", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	for prop: NodePath in [^".:searched", ^".:key_id"]:  # (Fallen's loot states: the picked-over look, a box locked after it spawned)
		config.add_property(prop)
		config.property_set_replication_mode(prop, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
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
	_apply_look()


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


## The picked-over look (a searched box: lid tipped up, the wood dulled) and a hidden cache's (low,
## dark, half in the ground). A colour and a lid: placeholders like the crate itself.
func _apply_look() -> void:
	var root := get_node_or_null(^"Visual") as Node3D
	if root == null:
		return
	var mesh: MeshInstance3D = root.get_child(0) as MeshInstance3D if root.get_child_count() > 0 else null
	if mesh and mesh.mesh is BoxMesh:
		var mat := (mesh.mesh as BoxMesh).material as StandardMaterial3D
		if mat:
			mat = mat.duplicate() as StandardMaterial3D
			mat.albedo_color = Color("2f2a22") if hidden else (Color("3e352a") if searched else Color("5a4a34"))
			(mesh.mesh as BoxMesh).material = mat
		root.position.y = -SIZE.y * 0.45 if hidden else 0.0
	var lid := root.get_node_or_null(^"Lid") as MeshInstance3D
	if searched and lid == null:
		lid = MeshInstance3D.new()
		lid.name = "Lid"
		var box := BoxMesh.new()
		box.size = Vector3(SIZE.x, 0.04, SIZE.z)
		lid.mesh = box
		lid.position = Vector3(0.0, SIZE.y + SIZE.z * 0.45, -SIZE.z * 0.5)
		lid.rotation.x = deg_to_rad(-70.0)
		root.add_child(lid)
	elif not searched and lid != null:
		lid.queue_free()


## The look's state for tests and the HUD: "hidden", "searched" or "fresh".
func look() -> String:
	return "searched" if searched else ("hidden" if hidden else "fresh")


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
	var out: Array[Dictionary] = [{"id": &"loot", "label": "Unlock and loot" if is_locked() and why == "" else "Loot", "disabled": why, "target": self,
		"call": func() -> void: (actor as Soldier)._hud.open_loot(me)}]
	if is_locked() and why != "" and actor is Soldier and LootStates.has_pry_tool(actor as Soldier):
		out.append({"id": &"pry", "label": "Pry it open (slow and loud)", "disabled": "", "target": self, "call": func() -> void: me.request_pry()})
	return out


## Any peer: pry the locked box open with a crowbar (LootStates: PRY_S, noise).
func request_pry() -> void:
	if multiplayer.is_server():
		_server_pry(multiplayer.get_unique_id())
	else:
		_rpc_pry.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_pry() -> void:
	if multiplayer.is_server():
		_server_pry(multiplayer.get_remote_sender_id())


func _server_pry(peer: int) -> void:
	var level := CompoundLevel.current(self)
	var actor: Soldier = level.players.get_node_or_null(str(peer)) as Soldier if level else null
	if actor:
		LootStates.server_start_pry(self, actor)


func is_locked() -> bool:
	return key_id != &"" and not unlocked


## Why `actor` can't get into it ("" when they can: it's open, or they carry its key).
func lock_problem(actor: Soldier) -> String:
	if not is_locked() or actor == null:
		return ""
	if key_id == LootStates.KEY_ITEM:  # (Fallen: the key made for this box, or a crowbar's pry)
		return "" if LootStates.has_key_for(actor, self) else "Locked: it needs its key, or a crowbar to pry it"
	if actor.inventory.count_of(key_id) > 0 or actor.inventory.slots.values().has(key_id) or actor.inventory.hands == key_id:
		return ""
	return "Locked: it needs the %s" % (ItemDB.get_item(key_id).name if ItemDB.has_item(key_id) else String(key_id))


## Host: `actor` gets into it: opens it with its key if it's locked. Returns why not ("" when in).
func server_open_for(actor: Soldier) -> String:
	var why := lock_problem(actor)
	if why == "" and is_locked():
		unlocked = true
		print("[cache] %s opens %s with the %s" % [actor.display_name(), display_name(), key_id])
	if why == "" and not searched:
		LootStates.server_on_open(self, actor)  # (Fallen: picked over from now on, a live event's claim)
	return why


## Host only (WorldValuables, right after the spawner places it): stows `items`
## ([{"id", "count"}]) into the hold, as much as fits (sparse flavour loot, never expected to
## overflow its small capacity).
func server_seed(items: Array) -> void:
	for entry: Dictionary in AmmoCondition.weather_loot(items, self):  # survival: found ammo's condition by where it lay (call 121)
		cargo_hold.take(StringName(entry.id), int(entry.get("count", 1)), entry.get("state", {}))


## Host only (WorldValuables, right after the spawner places it): what the zone save kept in this
## cache (GameState.caches: its contents as they were left, empty if it was emptied, and whether
## it was unlocked), else `items`, its first roll (server_seed).
func server_fill(items: Array) -> void:
	var saved: Variant = GameState.caches.get(uid)
	if not saved is Dictionary:
		server_seed(FoundLoot.first_roll(items, self))  # survival: the early loot curve (guns taken near the farm, a found condition)
		return
	server_seed(GameState.from_json((saved as Dictionary).get("items", [])))
	unlocked = bool((saved as Dictionary).get("unlocked", false)) and key_id != &""
	searched = bool((saved as Dictionary).get("searched", false))
	searched_day = float((saved as Dictionary).get("searched_day", 0.0))
	refills = int((saved as Dictionary).get("refills", 0))
	pried = bool((saved as Dictionary).get("pried", false))


## For the zone save (GameState.save_zone): what's in it and whether it's been unlocked.
func to_save() -> Dictionary:
	var items: Array = []
	for entry: Dictionary in cargo_hold.entries():
		var e := {"id": String(entry.id), "count": int(entry.count)}
		if not (entry.get("state", {}) as Dictionary).is_empty():
			e["state"] = (entry.state as Dictionary).duplicate(true)
		items.append(e)
	var out := {"items": items, "unlocked": unlocked}
	if searched or refills > 0 or pried:  # (Fallen's loot states)
		out.merge({"searched": searched, "searched_day": searched_day, "refills": refills, "pried": pried})
	return out


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
