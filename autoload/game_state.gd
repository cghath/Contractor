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
## Vehicles in the zone, wrecks included (Vehicle.to_save), put back by VehicleLayer on load
## (wave 5). Rebuilt from the live vehicles (group "vehicles") on every save.
var vehicles: Array = []


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
	# Vehicles as they are now: where they stopped, their damage and cargo, wrecks (wave 5).
	vehicles = []
	for node in get_tree().get_nodes_in_group(&"vehicles"):
		if node.has_method(&"to_save") and not node.is_queued_for_deletion():
			vehicles.append(node.to_save())
	var text := JSON.stringify({
		"version": SAVE_VERSION,
		"looted": looted.keys(),
		"dropped": dropped,
		"voxel_edits": voxel_edits,
		"bodies": bodies,
		"vehicles": vehicles,
	}, "", true, true)  # full precision: item state (plate and helmet integrity) comes back exactly
	if not write_safely(save_path(), text):
		return
	print("Saved zone '%s' (%d looted, %d dropped, %d voxel edits, %d bodies, %d vehicles)" % [zone_id, looted.size(), dropped.size(), voxel_edits.size(), bodies.size(), vehicles.size()])


func load_zone() -> void:
	looted.clear()
	dropped.clear()
	voxel_edits.clear()
	bodies.clear()
	vehicles.clear()
	var zone := read_save(save_path())
	if zone.is_empty() and FileAccess.file_exists(save_path()) and FileAccess.file_exists(backup_path(save_path())):
		zone = read_save(backup_path(save_path()))
		if not zone.is_empty():
			push_warning("GameState: %s was unreadable; loaded its backup" % save_path())
	if zone.is_empty():
		return
	looted = zone.looted
	dropped = zone.dropped
	voxel_edits = zone.voxel_edits
	bodies = zone.bodies
	vehicles = zone.get("vehicles", [])


## The previous good save, kept beside `path` by write_safely.
static func backup_path(path: String) -> String:
	return path + ".bak"


## Writes `text` to `path` without risking the save already there (audit L1-05): to a temporary
## file first, read back and checked, then the old save becomes the backup and the new one takes
## its place. Returns whether it worked; on failure the old save is untouched.
static func write_safely(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("GameState: cannot write %s" % tmp)
		return false
	file.store_string(text)
	file.close()
	if FileAccess.get_file_as_string(tmp) != text:
		push_error("GameState: %s didn't write back intact; the old save is kept" % tmp)
		DirAccess.remove_absolute(tmp)
		return false
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup_path(path)):
			DirAccess.remove_absolute(backup_path(path))
		DirAccess.rename_absolute(path, backup_path(path))
	if DirAccess.rename_absolute(tmp, path) != OK:
		push_error("GameState: cannot replace %s; the previous save is %s" % [path, backup_path(path)])
		return false
	return true


## A zone save at `path`, checked (audit L1-05): {"looted", "dropped", "voxel_edits", "bodies",
## "vehicles"} ready to use, or {} when it's missing, unreadable, the wrong version or the wrong shape.
## Single records that make no sense (an unknown item, a position that isn't three finite
## numbers, a count below 1) are dropped with a warning; the rest of the zone still loads.
static func read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("GameState: ignoring unreadable or incompatible save %s" % path)
		return {}
	var looted_in: Variant = data.get("looted", [])
	var dropped_in: Variant = data.get("dropped", {})
	var edits_in: Variant = data.get("voxel_edits", [])
	var bodies_in: Variant = data.get("bodies", [])  # saves from before bodies were kept have none
	var vehicles_in: Variant = data.get("vehicles", [])  # nor vehicles before wave 5
	if typeof(looted_in) != TYPE_ARRAY or typeof(dropped_in) != TYPE_DICTIONARY or typeof(edits_in) != TYPE_ARRAY \
			or typeof(bodies_in) != TYPE_ARRAY or typeof(vehicles_in) != TYPE_ARRAY:
		push_warning("GameState: ignoring save %s: a section has the wrong type" % path)
		return {}
	var out := {"looted": {}, "dropped": {}, "voxel_edits": edits_in, "bodies": [], "vehicles": []}
	for uid: Variant in looted_in:
		if typeof(uid) == TYPE_STRING:
			out.looted[uid] = true
	for uid: Variant in dropped_in:
		var d: Variant = dropped_in[uid]
		if typeof(d) == TYPE_DICTIONARY and ItemDB.has_item(StringName(String(d.get("id", "")))) \
				and _finite_pos(d.get("pos")) and float(d.get("count", 0)) >= 1.0:
			out.dropped[uid] = d
		else:
			push_warning("GameState: %s: skipping a bad dropped item (%s)" % [path, uid])
	for b: Variant in bodies_in:
		if typeof(b) == TYPE_DICTIONARY and _finite_pos(b.get("pos")) and typeof(b.get("uid")) == TYPE_STRING:
			out.bodies.append(b)
		else:
			push_warning("GameState: %s: skipping a bad body record" % path)
	for v: Variant in vehicles_in:
		if typeof(v) == TYPE_DICTIONARY and _finite_pos(v.get("pos")) and typeof(v.get("id")) == TYPE_STRING \
				and VehicleSpecs.has_model(String(v.get("model", ""))):
			out.vehicles.append(v)
		else:
			push_warning("GameState: %s: skipping a bad vehicle record" % path)
	return out


## Whether `p` is a saved position: [x, y, z], all finite numbers.
static func _finite_pos(p: Variant) -> bool:
	if typeof(p) != TYPE_ARRAY or (p as Array).size() != 3:
		return false
	for v: Variant in p:
		if (typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT) or not is_finite(float(v)):
			return false
	return true


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
	for path: String in [save_path(), backup_path(save_path()), save_path() + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
