extends Node
## Persistent state of the current zone, owned by the host and saved to user://saves/.
## Anything that must survive a reload (looted items, dropped items, voxel damage, and later
## cleared outposts and wrecks) is recorded here under a stable uid.

const SAVE_DIR := "user://saves"
const SAVE_VERSION := 1

var zone_id := "compound_01"
## Level-placed items that have been picked up (uid -> true).
var looted: Dictionary = {}
## Items players dropped (uid -> {"id", "count", "pos": [x, y, z], "state"}).
var dropped: Dictionary = {}
## Ordered voxel edit log. Replayed on load and sent to late joiners.
var voxel_edits: Array = []
## Dead bodies lying in the zone with everything on them (Soldier.body_record), restored by
## CompoundLevel on load. Rebuilt from the live bodies (Soldier.DEAD_GROUP) on every save.
var bodies: Array = []


func new_uid() -> String:
	return "%s_d%d_%d" % [zone_id, Time.get_ticks_usec(), randi() % 100000]


func is_looted(uid: String) -> bool:
	return looted.has(uid)


func item_taken(uid: String) -> void:
	if not dropped.erase(uid):
		looted[uid] = true


func item_dropped(uid: String, id: StringName, count: int, pos: Vector3, state := {}) -> void:
	dropped[uid] = {"id": String(id), "count": count, "pos": [pos.x, pos.y, pos.z], "state": state}


func save_path() -> String:
	return "%s/%s.json" % [SAVE_DIR, zone_id]


func save_zone() -> void:
	# Dropped items may have rolled since they were dropped.
	for node in get_tree().get_nodes_in_group(&"world_items"):
		if dropped.has(node.uid):
			var p: Vector3 = node.global_position
			dropped[node.uid]["pos"] = [p.x, p.y, p.z]
			dropped[node.uid]["count"] = node.count
	# Bodies as they are now: moved, carried off or looted since they fell.
	bodies = []
	for node in get_tree().get_nodes_in_group(&"dead_bodies"):
		if node.has_method(&"body_record") and not node.is_queued_for_deletion():
			bodies.append(node.body_record())
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file := FileAccess.open(save_path(), FileAccess.WRITE)
	if file == null:
		push_error("GameState: cannot write %s" % save_path())
		return
	file.store_string(JSON.stringify({
		"version": SAVE_VERSION,
		"looted": looted.keys(),
		"dropped": dropped,
		"voxel_edits": voxel_edits,
		"bodies": bodies,
	}, "", true, true))  # full precision: item state (plate and helmet integrity) comes back exactly
	print("Saved zone '%s' (%d looted, %d dropped, %d voxel edits, %d bodies)" % [zone_id, looted.size(), dropped.size(), voxel_edits.size(), bodies.size()])


func load_zone() -> void:
	looted.clear()
	dropped.clear()
	voxel_edits.clear()
	bodies.clear()
	if not FileAccess.file_exists(save_path()):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path()))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("GameState: ignoring incompatible save %s" % save_path())
		return
	for uid: String in data["looted"]:
		looted[uid] = true
	dropped = data["dropped"]
	voxel_edits = data["voxel_edits"]
	bodies = data.get("bodies", [])  # saves from before bodies were kept have none


## A value read back from JSON as the game wrote it: whole numbers back to ints (JSON keeps
## only floats, and item state compares and stacks by value) and item ids back to StringNames.
## Anything else is returned as it is (a deep copy).
static func from_json(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var f: float = value
			return int(f) if f == floorf(f) and absf(f) < 1e15 else f
		TYPE_ARRAY:
			return (value as Array).map(func(v: Variant) -> Variant: return from_json(v))
		TYPE_DICTIONARY:
			var out := {}
			for key: Variant in value:
				var v: Variant = from_json(value[key])
				out[key] = StringName(v) if key == "id" and typeof(v) == TYPE_STRING else v
			return out
	return value


func delete_save() -> void:
	if FileAccess.file_exists(save_path()):
		DirAccess.remove_absolute(save_path())
