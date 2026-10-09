extends Node
## Persistent state of the current zone, owned by the host and saved to user://saves/.
## Anything that must survive a reload (looted items, dropped items, voxel damage, and later
## cleared outposts and wrecks) is recorded here under a stable uid.

const SAVE_DIR := "user://saves"
const SAVE_VERSION := 1

var zone_id := "compound_01"
## Level-placed items that have been picked up (uid -> true).
var looted: Dictionary = {}
## Items players dropped (uid -> {"id", "count", "pos": [x, y, z]}).
var dropped: Dictionary = {}
## Ordered voxel edit log. Replayed on load and sent to late joiners.
var voxel_edits: Array = []


func new_uid() -> String:
	return "%s_d%d_%d" % [zone_id, Time.get_ticks_usec(), randi() % 100000]


func is_looted(uid: String) -> bool:
	return looted.has(uid)


func item_taken(uid: String) -> void:
	if not dropped.erase(uid):
		looted[uid] = true


func item_dropped(uid: String, id: StringName, count: int, pos: Vector3) -> void:
	dropped[uid] = {"id": String(id), "count": count, "pos": [pos.x, pos.y, pos.z]}


func save_path() -> String:
	return "%s/%s.json" % [SAVE_DIR, zone_id]


func save_zone() -> void:
	# Dropped items may have rolled since they were dropped.
	for node in get_tree().get_nodes_in_group(&"world_items"):
		if dropped.has(node.uid):
			var p: Vector3 = node.global_position
			dropped[node.uid]["pos"] = [p.x, p.y, p.z]
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
	}))
	print("Saved zone '%s' (%d looted, %d dropped, %d voxel edits)" % [zone_id, looted.size(), dropped.size(), voxel_edits.size()])


func load_zone() -> void:
	looted.clear()
	dropped.clear()
	voxel_edits.clear()
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


func delete_save() -> void:
	if FileAccess.file_exists(save_path()):
		DirAccess.remove_absolute(save_path())
