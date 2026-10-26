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
## What the survivors built (Builder.to_save: {"blocks", "pieces", "logs"}), put back by
## ZoneLevel._restore_builds on load ({} for none). Rebuilt from the level's Builder on every save.
var builds: Dictionary = {}
## Lootable caches and site boxes (WorldCache.to_save, by uid: {"items": [{"id", "count",
## "state"?}], "unlocked"}): what's in each as it was left, put back instead of a fresh roll
## (WorldCache.server_fill), so a looted box stays looted. Updated from the live caches on every
## save; a cache not in the zone just then keeps its record.
var caches: Dictionary = {}
## The zone's groups as profiles (Virtualizer.to_save: virtual ones, and live ones snapshotted where
## they stood), put back by the zone's Virtualizer on load, so a squad that leaves and comes back
## meets the same men (docs/virtualization.md). Rebuilt from the level's Virtualizer on every save.
var profiles: Array = []
## What players placed and left in the zone (Demolitions.to_save: demo blocks, thermite, claymores,
## mines, chem lights, with their clocks), put back by the level's Demolitions on load. Rebuilt
## from the level's Demolitions on every save.
var demolitions: Array = []
## The zone's bridges (ZoneBridges.to_save: {"hp": bridge id -> every span's health}), put back by
## the level on load: a dropped span stays down. Rebuilt from the level's bridges on every save.
var bridges: Dictionary = {}


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
	var scenario := MissionScenario.of(self)
	if scenario:
		scenario.server_checkpoint()
	# Dropped items may have rolled since they were dropped.
	for node in get_tree().get_nodes_in_group(&"world_items"):
		if dropped.has(node.uid):
			var p: Vector3 = node.global_position
			dropped[node.uid]["pos"] = [p.x, p.y, p.z]
			dropped[node.uid]["count"] = node.count
	Spoilage.stamp_dropped(dropped)  # survival: food lying here ages from now when the zone loads again
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
	_save_builds()
	var virtualizer := get_tree().get_first_node_in_group(&"virtualizer")
	profiles = virtualizer.to_save() if virtualizer and virtualizer.has_method(&"to_save") else []
	var placed := get_tree().get_first_node_in_group(&"demolitions")
	demolitions = placed.to_save() if placed and placed.has_method(&"to_save") else []
	var spans := get_tree().get_first_node_in_group(&"zone_bridges")
	bridges = spans.to_save() if spans and spans.has_method(&"to_save") else {}
	# Caches and site boxes as they are now: looted, or used as a stash (compound loot).
	for node in get_tree().get_nodes_in_group(&"world_caches"):
		if node.has_method(&"to_save") and not node.is_queued_for_deletion() and String(node.get(&"uid")) != "":
			caches[String(node.get(&"uid"))] = node.to_save()
	var text := JSON.stringify({
		"version": SAVE_VERSION,
		"looted": looted.keys(),
		"dropped": dropped,
		"voxel_edits": voxel_edits,
		"bodies": bodies,
		"fallen_posts": fallen_posts.keys(),
		"vehicles": vehicles,
		"ground": ground,
		"builds": builds,
		"caches": caches,
		"profiles": profiles,
		"demolitions": demolitions,
		"bridges": bridges,
		"sky": sky,
		"left_day": BaseHub.day() if BaseHub.campaign_running else -1,  # zone memory (LZ-2): it fades from here
	}, "", true, true)  # full precision: item state (plate and helmet integrity) comes back exactly
	if not write_safely(save_path(), text):
		return false
	print("Saved zone '%s' (%d looted, %d dropped, %d voxel edits, %d bodies, %d vehicles, %d caches, %d profiles)" % [zone_id, looted.size(), dropped.size(), voxel_edits.size(), bodies.size(), vehicles.size(), caches.size(), profiles.size()])
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
	builds = {}
	sky = {}
	caches = {}
	profiles = []
	demolitions = []
	bridges = {}
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
	builds = zone.get("builds", {})
	sky = zone.get("sky", {})
	caches = zone.get("caches", {})  # boxes stay as they were left even when the loose gear fades
	profiles = zone.get("profiles", [])
	demolitions = zone.get("demolitions", [])
	bridges = zone.get("bridges", {})
	if fade_loose:
		bodies.clear()  # gone in the days since (zone memory, LZ-2)
		dropped.clear()
		profiles.clear()  # moved on in the days since: the zone's enemy is fresh
		demolitions = demolitions.filter(func(r: Dictionary) -> bool: return Demolitions.kind_of(StringName(String(r.item))) != Demolitions.CHEMLIGHT)  # the chem lights are out; mines and charges stay
	fade_loose = false
	Spoilage.age_dropped(dropped)  # survival: the food lying about went off while the zone sat unloaded


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
	var caches_in: Variant = data.get("caches", {})  # nor caches before compound loot
	out["caches"] = {}
	if typeof(caches_in) == TYPE_DICTIONARY:
		for uid: Variant in caches_in:
			var c: Variant = caches_in[uid]
			if typeof(uid) == TYPE_STRING and _cache_ok(c):
				var kept := {"items": c.get("items", []), "unlocked": bool(c.get("unlocked", false))}
				for k: String in ["searched", "searched_day", "refills", "pried", "aged_h"]:  # (Fallen's loot states: LootStates; the food's age: Spoilage)
					if (c as Dictionary).has(k):
						kept[k] = (c as Dictionary)[k]
				out.caches[uid] = kept
			else:
				push_warning("GameState: %s: skipping a bad cache record (%s)" % [path, uid])
	else:
		push_warning("GameState: %s: the caches section has the wrong type; boxes roll afresh" % path)
	var profiles_in: Variant = data.get("profiles", [])  # nor profiles before virtualization
	out["profiles"] = []
	if typeof(profiles_in) == TYPE_ARRAY:
		for p: Variant in profiles_in:
			if Virtualizer.save_ok(p):
				out.profiles.append(p)
			else:
				push_warning("GameState: %s: skipping a bad profile" % path)
	var placed_in: Variant = data.get("demolitions", [])  # nor demolitions before they were built
	out["demolitions"] = []
	if typeof(placed_in) == TYPE_ARRAY:
		for r: Variant in placed_in:
			if Demolitions.save_ok(r):
				out.demolitions.append(r)
			else:
				push_warning("GameState: %s: skipping a bad placed item" % path)
	var bridges_in: Variant = data.get("bridges", {})  # nor bridges before the water (queue item 1.1)
	out["bridges"] = {}
	if typeof(bridges_in) == TYPE_DICTIONARY and typeof(bridges_in.get("hp", {})) == TYPE_DICTIONARY:
		var hp := {}
		for id: Variant in bridges_in.get("hp", {}):
			var spans: Variant = bridges_in.hp[id]
			if typeof(id) == TYPE_STRING and typeof(spans) == TYPE_ARRAY and (spans as Array).all(func(v: Variant) -> bool: return is_number(v) and is_finite(float(v))):
				hp[id] = spans
			else:
				push_warning("GameState: %s: skipping a bad bridge record (%s)" % [path, id])
		out.bridges = {"hp": hp}
	var ground_in: Variant = data.get("ground", {})  # nor dug ground before the e-tool (F-176: it was dropped here)
	out["ground"] = {}
	if typeof(ground_in) == TYPE_DICTIONARY and typeof(ground_in.get("cuts", [])) == TYPE_ARRAY and typeof(ground_in.get("berms", [])) == TYPE_ARRAY:
		var cuts: Array = []
		var berms: Array = []
		for op: Variant in ground_in.get("cuts", []):
			if Digging.cut_ok(op):
				cuts.append(op)
			else:
				push_warning("GameState: %s: skipping a bad ground cut (%s)" % [path, str(op).left(80)])
		for b: Variant in ground_in.get("berms", []):
			if Digging.berm_ok(b):
				berms.append(b)
			else:
				push_warning("GameState: %s: skipping a bad berm" % path)
		if ground_in.has("cuts"):
			out.ground = {"cuts": cuts, "berms": berms}
	elif typeof(ground_in) != TYPE_DICTIONARY or not (ground_in as Dictionary).is_empty():
		push_warning("GameState: %s: the ground section has the wrong type; the zone is dug afresh" % path)
	_read_builds(data, out, path)
	var sky_in: Variant = data.get("sky", {})  # saves from before wave 7 have none
	if typeof(sky_in) == TYPE_DICTIONARY and is_number(sky_in.get("hour")) and is_finite(float(sky_in.hour)) \
			and typeof(sky_in.get("weather")) == TYPE_STRING:  # an unknown weather reads as clear (DayNight)
		out["sky"] = {"hour": float(sky_in.hour), "weather": String(sky_in.weather)}
	return out


## The level's builds (Builder) into `builds` for the save; a zone with none keeps what it had.
func _save_builds() -> void:
	var builder := get_tree().get_first_node_in_group(&"builder")
	if builder and builder.has_method(&"to_save"):
		builds = builder.to_save()


## A save's builds section (Builder.save_ok) into `out` ({} when it's missing or the wrong shape).
static func _read_builds(data: Dictionary, out: Dictionary, path: String) -> void:
	var builds_in: Variant = data.get("builds", {})  # saves from before building have none
	out["builds"] = builds_in if Builder.save_ok(builds_in) else {}
	if not Builder.save_ok(builds_in):
		push_warning("GameState: %s: the builds section has the wrong shape; nothing built comes back" % path)


## Whether `c` is a saved cache (WorldCache.to_save): its items known ones, each a count of 1 or
## more, shaped like a dropped item's (DROPPED_FIELDS), and "unlocked" a bool.
static func _cache_ok(c: Variant) -> bool:
	if typeof(c) != TYPE_DICTIONARY or typeof(c.get("items", [])) != TYPE_ARRAY or typeof(c.get("unlocked", false)) != TYPE_BOOL:
		return false
	return (c.get("items", []) as Array).all(func(e: Variant) -> bool:
		return typeof(e) == TYPE_DICTIONARY and fields_ok(e, DROPPED_FIELDS) and ItemDB.has_item(StringName(String(e.get("id", "")))) \
			and float(e.get("count", 0)) >= 1.0)


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


## At quit, while the scripts are still loaded: waits for the worker tasks that run GDScript
## (VoxelArt's warm-up and faces, BodyVolume's warm-up, VehicleHull's canvases; Sfx waits for its
## own). Tests that quit seconds after a level loads (nvg, exo on the range) hang in the engine's
## shutdown on CI's Linux runners, and tasks like these still running then are the likely cause:
## the line printed says when there were any.
func _exit_tree() -> void:
	var pending := VoxelArt.pending_tasks() + (1 if not BodyVolume.is_warm() else 0) + VehicleHull.finish_tasks()
	VoxelArt.finish_warm()
	BodyVolume.finish_warm()
	if pending > 0:
		print("[exit] waited for %d worker task(s) still running" % pending)
