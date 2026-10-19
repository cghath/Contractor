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
## Original hostile posts that fell, retained after their bodies leave the zone.
var fallen_posts: Dictionary = {}
## Vehicles in the zone, wrecks included (Vehicle.to_save), put back by VehicleLayer on load
## (wave 5). Rebuilt from the live vehicles (group "vehicles") on every save.
var vehicles: Array = []
## The ground as dug and blasted (Digging.to_save: {"cuts", "berms"}), put back by Digging on
## load ({} for a zone never saved). Rebuilt from the level's Digging on every save.
var ground: Dictionary = {}


func post_fell(spawn_id: String) -> void:
	if spawn_id != "":
		fallen_posts[spawn_id] = true


func post_is_fallen(spawn_id: String) -> bool:
	if fallen_posts.has(spawn_id):
		return true
	# Also accept in-memory legacy records (load_zone migrates these to the ledger).
	return bodies.any(func(b: Dictionary) -> bool:
		return b.get("faction", "") == "hostile" and String(b.get("spawn_id", b.get("label", ""))) == spawn_id)
## The zone's time of day and weather (DayNight.to_save: {"hour", "weather"}; wave 7). Empty:
## the zone definition's.
var sky: Dictionary = {}
## Host, set before a zone loads (BaseHub._fade_zone_save, LZ-2's zone memory): its save is old
## enough that the bodies and the gear lying about have gone; the rest (damage, sites) stays.
var fade_loose := false


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


## Writes the zone's save (write_safely). Returns whether it was written.
func save_zone() -> bool:
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
	var digging := get_tree().get_first_node_in_group(&"digging")
	ground = digging.to_save() if digging and digging.has_method(&"to_save") else {}
	var text := JSON.stringify({
		"version": SAVE_VERSION,
		"looted": looted.keys(),
		"dropped": dropped,
		"voxel_edits": voxel_edits,
		"bodies": bodies,
		"fallen_posts": fallen_posts.keys(),
		"vehicles": vehicles,
		"ground": ground,
		"sky": sky,
		"left_day": BaseHub.day() if BaseHub.campaign_running else -1,  # zone memory (LZ-2): it fades from here
	}, "", true, true)  # full precision: item state (plate and helmet integrity) comes back exactly
	if not write_safely(save_path(), text):
		return false
	print("Saved zone '%s' (%d looted, %d dropped, %d voxel edits, %d bodies, %d vehicles)" % [zone_id, looted.size(), dropped.size(), voxel_edits.size(), bodies.size(), vehicles.size()])
	return true


## Loads the zone's save: the save itself, else an interrupted write of it, else its backup
## (save_candidates, audit A1-02). A file that can't be read is moved aside, never deleted
## (set_aside, audit A1-01), so the next save doesn't push a good backup out for it.
func load_zone() -> void:
	looted.clear()
	dropped.clear()
	voxel_edits.clear()
	bodies.clear()
	fallen_posts.clear()
	vehicles.clear()
	ground = {}
	sky = {}
	var zone := {}
	for path: String in save_candidates(save_path()):
		if not FileAccess.file_exists(path):
			continue
		zone = read_save(path)
		if not zone.is_empty():
			if path != save_path():
				push_warning("GameState: zone %s: the save was missing or unreadable; loaded %s" % [zone_id, path.get_file()])
			break
		push_warning("GameState: zone %s: %s couldn't be read; kept as %s" % [zone_id, path.get_file(), set_aside(path, "unreadable").get_file()])
	if zone.is_empty():
		return
	looted = zone.looted
	dropped = zone.dropped
	voxel_edits = zone.voxel_edits
	bodies = zone.bodies
	fallen_posts = zone.fallen_posts
	vehicles = zone.get("vehicles", [])
	ground = zone.get("ground", {})
	sky = zone.get("sky", {})
	if fade_loose:
		bodies.clear()  # gone in the days since (zone memory, LZ-2)
		dropped.clear()
	fade_loose = false


## The previous good save, kept beside `path` by write_safely.
static func backup_path(path: String) -> String:
	return path + ".bak"


## Where the save at `path` may be, in the order to try them (audit A1-02): the save itself; a
## complete new one write_safely was interrupted before putting in place (one cut off mid-write
## doesn't read back, and is set aside like any unreadable file); the previous save, its backup.
static func save_candidates(path: String) -> Array[String]:
	return [path, path + ".tmp", backup_path(path)]


## Whether there's anything to load for the save at `path` (save_candidates).
static func has_save(path: String) -> bool:
	return save_candidates(path).any(func(p: String) -> bool: return FileAccess.file_exists(p))


## Moves the file at `path` aside, beside it, as "<path>.<why>-<date>-<time>" (audit A1-01): a
## save the game can't use is kept for whoever can mend it, never deleted, and nothing loads or
## deletes it after. Returns the new path, or "" when it couldn't be moved (it stays as it is).
static func set_aside(path: String, why: String) -> String:
	var t := Time.get_datetime_dict_from_system()
	var stem := "%s.%s-%04d%02d%02d-%02d%02d%02d" % [path, why, t.year, t.month, t.day, t.hour, t.minute, t.second]
	var to := stem
	var n := 1
	while FileAccess.file_exists(to):
		n += 1
		to = "%s-%d" % [stem, n]
	if DirAccess.rename_absolute(path, to) != OK:
		push_error("GameState: cannot move %s aside; it stays where it is" % path)
		return ""
	return to


## The files set_aside kept of the save at `path` (file names, in its folder).
static func kept_copies(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(path.get_base_dir()):
		return out
	var prefix := path.get_file() + "."
	for file in DirAccess.get_files_at(path.get_base_dir()):
		if file.begins_with(prefix) and file != prefix + "bak" and file != prefix + "tmp":
			out.append(file)
	return out


## Writes `text` to `path` without risking the save already there (audit L1-05): to a temporary
## file first, read back and checked, then the old save becomes the backup and the new one takes
## its place. Every step is checked (audit A1-04): until the new save is in place the last good
## one stays on disk (as the save, or as the backup with the new one whole in the temporary
## file, which load_campaign and load_zone also look at). Returns whether the new save is in
## place; on failure it says why (push_error) and the save already there is untouched.
static func write_safely(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("GameState: cannot write %s (%s); the old save is kept" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(text)
	file.close()
	if FileAccess.get_file_as_string(tmp) != text:
		push_error("GameState: %s didn't write back intact; the old save is kept" % tmp)
		DirAccess.remove_absolute(tmp)
		return false
	if FileAccess.file_exists(path):
		var bak := backup_path(path)
		if FileAccess.file_exists(bak) and DirAccess.remove_absolute(bak) != OK:
			push_error("GameState: cannot replace the backup %s; the old save is kept" % bak)
			DirAccess.remove_absolute(tmp)
			return false
		if DirAccess.rename_absolute(path, bak) != OK:
			push_error("GameState: cannot move %s to its backup; the old save is kept" % path)
			DirAccess.remove_absolute(tmp)
			return false
	if DirAccess.rename_absolute(tmp, path) != OK:
		push_error("GameState: cannot put the new save in place at %s; the previous one is %s" % [path, backup_path(path)])
		return false
	return true


## What the game reads from a saved record, by field (the form of Campaign.SHAPES; a field the
## record doesn't have is fine): a dropped item's, a body's (Soldier.body_record, read back by
## CompoundLevel.server_spawn_body) and a vehicle's (Vehicle.to_save, read back by from_save).
const DROPPED_FIELDS := {"id": TYPE_STRING, "count": TYPE_FLOAT, "state": TYPE_DICTIONARY}
const BODY_FIELDS := {"spawn_id": TYPE_STRING, "label": TYPE_STRING, "faction": TYPE_STRING, "variant": TYPE_STRING, "body": TYPE_STRING,
	"person_name": TYPE_STRING, "nation": TYPE_STRING, "left": TYPE_BOOL, "role": TYPE_STRING, "rot_y": TYPE_FLOAT,
	"age_s": TYPE_FLOAT, "marker": TYPE_BOOL, "gear": TYPE_DICTIONARY, "ragdoll": [TYPE_ARRAY, TYPE_FLOAT]}
const VEHICLE_FIELDS := {"scheme": TYPE_STRING, "faction": TYPE_STRING, "wrecked": TYPE_BOOL, "rot": [TYPE_ARRAY, TYPE_FLOAT],
	"zones": [TYPE_DICTIONARY, TYPE_FLOAT], "fuel": TYPE_FLOAT, "burning": TYPE_FLOAT, "battery": TYPE_BOOL,
	"salvaged": TYPE_BOOL, "leak": TYPE_FLOAT, "carves": TYPE_ARRAY, "cargo": TYPE_DICTIONARY, "bodies": TYPE_DICTIONARY}
## What each kind of voxel edit needs (VoxelWorld._apply reads them as they are): "pos" three
## finite numbers, "size" a finite number above 0, "cells" whole numbers, three per voxel. The
## optional "d" (calibre), "m" (material) and "w" (a zone module) are checked with EDIT_FIELDS.
const EDIT_NEEDS := {"carve": {"c": "pos", "r": "size"}, "blast": {"c": "pos", "r": "size"}, "holes": {"v": "cells"},
	"shot": {"a": "pos", "an": "pos", "b": "pos", "bn": "pos", "v": "cells"}, "mark": {"p": "pos", "n": "pos"}}
const EDIT_FIELDS := {"d": TYPE_FLOAT, "m": TYPE_FLOAT, "w": TYPE_STRING}


## A zone save at `path`, checked (audit L1-05, A1-03): {"looted", "dropped", "voxel_edits",
## "bodies", "vehicles"} ready to use, or {} when it's missing, unreadable, the wrong version or
## the wrong shape. Single records that make no sense (an unknown item, a position that isn't
## three finite numbers, a count below 1, a field of the wrong type, a voxel edit replay can't
## use) are dropped with a warning; the rest of the zone still loads.
static func read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or not is_number(data.get("version")) or int(data.version) != SAVE_VERSION:
		push_warning("GameState: ignoring unreadable or incompatible save %s" % path)
		return {}
	var looted_in: Variant = data.get("looted", [])
	var dropped_in: Variant = data.get("dropped", {})
	var edits_in: Variant = data.get("voxel_edits", [])
	var bodies_in: Variant = data.get("bodies", [])  # saves from before bodies were kept have none
	var vehicles_in: Variant = data.get("vehicles", [])  # nor vehicles before wave 5
	var fallen_in: Variant = data.get("fallen_posts", [])
	if typeof(looted_in) != TYPE_ARRAY or typeof(dropped_in) != TYPE_DICTIONARY or typeof(edits_in) != TYPE_ARRAY \
			or typeof(bodies_in) != TYPE_ARRAY or typeof(vehicles_in) != TYPE_ARRAY or typeof(fallen_in) != TYPE_ARRAY:
		push_warning("GameState: ignoring save %s: a section has the wrong type" % path)
		return {}
	var out := {"looted": {}, "dropped": {}, "voxel_edits": [], "bodies": [], "vehicles": [], "fallen_posts": {}}
	for post: Variant in fallen_in:
		if typeof(post) == TYPE_STRING and post != "":
			out.fallen_posts[post] = true
	for uid: Variant in looted_in:
		if typeof(uid) == TYPE_STRING:
			out.looted[uid] = true
	for uid: Variant in dropped_in:
		var d: Variant = dropped_in[uid]
		if typeof(d) == TYPE_DICTIONARY and fields_ok(d, DROPPED_FIELDS) and ItemDB.has_item(StringName(String(d.get("id", "")))) \
				and _finite_pos(d.get("pos")) and float(d.get("count", 0)) >= 1.0:
			out.dropped[uid] = d
		else:
			push_warning("GameState: %s: skipping a bad dropped item (%s)" % [path, uid])
	for e: Variant in edits_in:
		if _edit_ok(e):
			out.voxel_edits.append(e)
		else:
			push_warning("GameState: %s: skipping a bad voxel edit (%s)" % [path, str(e).left(80)])
	for b: Variant in bodies_in:
		if typeof(b) == TYPE_DICTIONARY and _finite_pos(b.get("pos")) and typeof(b.get("uid")) == TYPE_STRING and fields_ok(b, BODY_FIELDS):
			out.bodies.append(b)
			if b.get("faction", "") == "hostile":
				# Older saves used callsigns as labels. New saves keep the post independently
				# of the generated display name and the restored body's node name.
				var post := String(b.get("spawn_id", b.get("label", "")))
				if post != "":
					out.fallen_posts[post] = true
		else:
			push_warning("GameState: %s: skipping a bad body record" % path)
	for v: Variant in vehicles_in:
		if typeof(v) == TYPE_DICTIONARY and _finite_pos(v.get("pos")) and typeof(v.get("id")) == TYPE_STRING \
				and typeof(v.get("model")) == TYPE_STRING and VehicleSpecs.has_model(v.model) and fields_ok(v, VEHICLE_FIELDS):
			out.vehicles.append(v)
		else:
			push_warning("GameState: %s: skipping a bad vehicle record" % path)
	var sky_in: Variant = data.get("sky", {})  # saves from before wave 7 have none
	if typeof(sky_in) == TYPE_DICTIONARY and is_number(sky_in.get("hour")) and is_finite(float(sky_in.hour)) \
			and typeof(sky_in.get("weather")) == TYPE_STRING:  # an unknown weather reads as clear (DayNight)
		out["sky"] = {"hour": float(sky_in.hour), "weather": String(sky_in.weather)}
	return out


## Whether `e` is a voxel edit replay can apply (EDIT_NEEDS, EDIT_FIELDS).
static func _edit_ok(e: Variant) -> bool:
	if typeof(e) != TYPE_DICTIONARY or typeof(e.get("op")) != TYPE_STRING or not EDIT_NEEDS.has(e.op) or not fields_ok(e, EDIT_FIELDS):
		return false
	var needs: Dictionary = EDIT_NEEDS[e.op]
	for key: String in needs:
		var v: Variant = e.get(key)
		match needs[key]:
			"pos":
				if not _finite_pos(v):
					return false
			"size":
				if not is_number(v) or float(v) <= 0.0:
					return false
			"cells":
				if typeof(v) != TYPE_ARRAY or (v as Array).size() % 3 != 0 \
						or not (v as Array).all(func(n: Variant) -> bool: return is_number(n) and float(n) == floorf(float(n))):
					return false
	return true


## Whether `v` is a finite number (JSON reads every number back as a float; the game's own
## records hold ints too).
static func is_number(v: Variant) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))


## Whether each field of `record` that `shape` names is what it says: a TYPE_* (TYPE_FLOAT
## for any finite number), or [TYPE_ARRAY or TYPE_DICTIONARY, the type of every element].
## Fields `record` doesn't have are fine (older saves; the reader gives a default).
static func fields_ok(record: Dictionary, shape: Dictionary) -> bool:
	for key: Variant in shape:
		if record.has(key) and not _is_shape(record[key], shape[key]):
			return false
	return true


static func _is_shape(v: Variant, want: Variant) -> bool:
	if typeof(want) == TYPE_ARRAY:
		if typeof(v) != want[0]:
			return false
		var elements: Array = (v as Dictionary).values() if typeof(v) == TYPE_DICTIONARY else v
		return elements.all(func(e: Variant) -> bool: return _is_shape(e, want[1]))
	if want == TYPE_FLOAT:
		return is_number(v)
	return typeof(v) == want


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


## Deletes the zone's save, its backup and any interrupted write (not the copies set_aside kept).
func delete_save() -> void:
	for path: String in save_candidates(save_path()):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
