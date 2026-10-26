class_name ModKit
extends RefCounted
## The mod kit for Contractor: Fallen (docs/fallen_modding.md; call 127). Static.
##
## - Mods are folders: res://mods/<name>/ (shipped with the game) and user://mods/<name>/ (the
##   player's), each with a mod.json manifest ({"name", "version", "files": ["items.json", ...],
##   "load_order" (lower first, default 100), "description", "author"}) and its data files, each
##   named for the kind it changes (data/fallen_mod_schema.json "kinds": items, zombies, perks,
##   backgrounds, survival_recipes, survival_regions, survival_fauna, survival_flora, survival_lines,
##   arche_trail, bunkers, loot_tables, survival_events).
## - activate() (a survival world starting or continuing, and every peer's SurvivalLevel) loads them
##   in load order (then by name) and merges each file over the game's own by id: dictionaries merge
##   key by key (null removes a key), lists of records with an "id" merge by id (a record with
##   "remove": true goes), other lists of records add to the end, anything else is replaced. A mod
##   with a problem (validate) is skipped and its problems kept in `errors`. Items go into ItemDB
##   (put back by deactivate); the loaders read the rest through overlay() (their caches emptied on
##   activate), and the code's tables (the dead's kinds, perks, backgrounds and flaws) through
##   merged().
## - World cards: a world's seed and options as a small JSON (world_card, export_card, import_card;
##   New world's Import button), with the mods it was made with.

const DIRS: Array[String] = ["res://mods", "user://mods"]
const MANIFEST := "mod.json"
const SCHEMA_PATH := "res://data/fallen_mod_schema.json"
const DEFAULT_ORDER := 100
const CARD_DIR := "user://world_cards"
const CARD_KIND := "fallen_world_card"
const CARD_VERSION := 1

## Whether a survival world's mods are on (overlay passes data through untouched when not).
static var active := false
## Tests and tools: folders to read instead of DIRS (empty: DIRS).
static var dirs_override: Array = []
## The mods loaded, in order: [{"name", "version", "dir", "files", "load_order"}].
static var mods: Array = []
## The mods skipped, and why: [{"dir", "problems": [lines]}].
static var errors: Array = []
static var _overlays := {}  # kind -> [data, ...] in load order
static var _merged := {}  # kind -> merged table (merged())
static var _items_before := {}  # item id -> the ItemData a mod replaced (null: it was new)
static var _signature := ""
static var _schema := {}
static var _base_items := {}


# --- Loading -------------------------------------------------------------------------------------

## Loads the mods (once per set of folders' contents) and turns them on: items into ItemDB, the
## loaders' caches emptied so they read through overlay(). Returns how many mods are on.
static func activate() -> int:
	var found := scan()
	var sig := JSON.stringify(found.map(func(m: Dictionary) -> String: return "%s@%s:%s" % [m.name, m.version, m.dir]))
	if active and sig == _signature:
		return mods.size()
	if active:
		deactivate()
	_signature = sig
	mods = found
	_overlays = {}
	_merged = {}
	for m: Dictionary in mods:
		for f: String in m.files:
			var data: Variant = _read_json("%s/%s" % [m.dir, f])
			if data is Dictionary:
				var kind := f.get_basename()
				if not _overlays.has(kind):
					_overlays[kind] = []
				(_overlays[kind] as Array).append(data)
	active = true
	_apply_items()
	_reset_caches()
	if not mods.is_empty():
		print("[modkit] %d mod(s) on: %s" % [mods.size(), ", ".join(PackedStringArray(mods.map(func(m: Dictionary) -> String: return "%s %s" % [m.name, m.version])))])
	for e: Dictionary in errors:
		push_warning("ModKit: skipped %s: %s" % [String(e.dir), "; ".join(PackedStringArray(e.problems))])
	return mods.size()


## The mods off again: replaced items put back, the loaders' caches emptied.
static func deactivate() -> void:
	for id: StringName in _items_before:
		var before: Variant = _items_before[id]
		if before == null:
			ItemDB._items.erase(id)
		else:
			ItemDB._items[id] = before
	_items_before = {}
	active = false
	_overlays = {}
	_merged = {}
	_signature = ""
	_reset_caches()


## The mods in the folders (dirs_override, else DIRS), checked, in load order. Fills `errors`.
static func scan() -> Array:
	errors = []
	var out: Array = []
	var roots: Array = dirs_override if not dirs_override.is_empty() else DIRS
	for root: String in roots:
		var d := DirAccess.open(root)
		if d == null:
			continue
		var subs := Array(d.get_directories())
		subs.sort()
		for sub: String in subs:
			var dir := "%s/%s" % [root, sub]
			if not FileAccess.file_exists("%s/%s" % [dir, MANIFEST]):
				continue
			var problems := validate(dir)
			if not problems.is_empty():
				errors.append({"dir": dir, "problems": problems})
				continue
			var man: Dictionary = _read_json("%s/%s" % [dir, MANIFEST])
			out.append({"name": String(man.name), "version": String(man.version), "dir": dir, "files": Array(man.files).map(func(f: Variant) -> String: return String(f)),
				"load_order": int(man.get("load_order", DEFAULT_ORDER))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.load_order) < int(b.load_order) or (int(a.load_order) == int(b.load_order) and String(a.name) < String(b.name)))
	return out


static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


## Every loader's cache emptied (they read again through overlay on next use).
static func _reset_caches() -> void:
	Crafting._recipes = {}
	WorldRegions._data = {}
	Nature._fauna = {}
	Nature._flora = {}
	TalkMenu._lines = {}
	ArcheTrail._data = {}
	Bunkers._data = {}
	WorldValuables._data = {}
	WorldEvents._data = {}


# --- Merging -----------------------------------------------------------------------------------------

## A loader's data with the mods of `kind` merged over it (untouched when no mod changes it or the
## kit is off). `data` is what the loader parsed (a Dictionary, else returned as it is).
static func overlay(kind: String, data: Variant) -> Variant:
	if not active or not data is Dictionary or not _overlays.has(kind):
		return data
	var out: Variant = (data as Dictionary).duplicate(true)
	for o: Variant in _overlays[kind]:
		out = merge(out, o)
	return out


## A code table (the dead's kinds, perks, ...) as {collection: table} with the mods of `kind` over
## it; cached until the mods change.
static func merged(kind: String, base: Dictionary) -> Dictionary:
	if not active or not _overlays.has(kind):
		return base
	if not _merged.has(kind):
		_merged[kind] = overlay(kind, base)
	return _merged[kind]


## `over` merged onto `base` (see the class doc).
static func merge(base: Variant, over: Variant) -> Variant:
	if base is Dictionary and over is Dictionary:
		var out: Dictionary = (base as Dictionary).duplicate(true)
		for k: Variant in over:
			var v: Variant = over[k]
			if v == null:
				out.erase(k)
			elif out.has(k):
				out[k] = merge(out[k], v)
			else:
				out[k] = v.duplicate(true) if (v is Dictionary or v is Array) else v
		return out
	if base is Array and over is Array:
		var b: Array = base
		var o: Array = over
		var records := not o.is_empty() and o.all(func(e: Variant) -> bool: return e is Dictionary)
		if records and o.all(func(e: Variant) -> bool: return (e as Dictionary).has("id")) and b.all(func(e: Variant) -> bool: return e is Dictionary and (e as Dictionary).has("id")):
			var out: Array = b.duplicate(true)
			for e: Dictionary in o:
				var at := -1
				for i in out.size():
					if String((out[i] as Dictionary).id) == String(e.id):
						at = i
						break
				if bool(e.get("remove", false)):
					if at >= 0:
						out.remove_at(at)
				elif at >= 0:
					out[at] = merge(out[at], e)
				else:
					out.append(e.duplicate(true))
			return out
		if records and b.all(func(e: Variant) -> bool: return e is Dictionary):
			return b.duplicate(true) + o.duplicate(true)
		return o.duplicate(true)
	return over.duplicate(true) if (over is Dictionary or over is Array) else over


# --- Items -------------------------------------------------------------------------------------------

## The mods' items into ItemDB: a known id patched field by field over its items.json entry, a new
## one added; the replaced ones remembered for deactivate.
static func _apply_items() -> void:
	if not _overlays.has("items"):
		return
	for o: Dictionary in _overlays["items"]:
		for e: Variant in o.get("items", []):
			if not e is Dictionary or String((e as Dictionary).get("id", "")) == "":
				continue
			var id := StringName(String(e.id))
			var base: Dictionary = base_item(String(id))
			var cur: Variant = ItemDB._items.get(id)
			if not _items_before.has(id):
				_items_before[id] = cur
			if cur != null and _items_patched.has(id):
				base = _items_patched[id]
			var entry: Dictionary = merge(base, e) if not base.is_empty() else (e as Dictionary).duplicate(true)
			_items_patched[id] = entry
			ItemDB._items[id] = ItemData.from_dict(entry)
	_items_patched = {}


static var _items_patched := {}


## The game's own entry for item `id` in data/items.json ({} for none).
static func base_item(id: String) -> Dictionary:
	if _base_items.is_empty():
		var data: Variant = _read_json(ItemDB.PATH)
		if data is Dictionary:
			for e: Variant in (data as Dictionary).get("items", []):
				if e is Dictionary:
					_base_items[String((e as Dictionary).get("id", ""))] = e
	return (_base_items.get(id, {}) as Dictionary).duplicate(true)


# --- The code's tables -------------------------------------------------------------------------------

## The dead's kinds (ZombieAI.KINDS with the mods' "zombies" over it): id -> {walk, chase, sprint,
## pool, scream, low, trip, armoured, share}.
static func zombie_kinds() -> Dictionary:
	return merged("zombies", {"kinds": ZombieAI.KINDS}).get("kinds", ZombieAI.KINDS)


static func zombie_kind(kind: String) -> Dictionary:
	var all := zombie_kinds()
	return all.get(kind, all.get("walker", ZombieAI.KINDS.walker))


## The mods' own kinds of the dead with a spawn "share" ({kind: share}), for Survival.roll_kind.
static func extra_zombie_shares() -> Dictionary:
	var out := {}
	if not active or not _overlays.has("zombies"):
		return out
	var all := zombie_kinds()
	for k: String in all:
		if not ZombieAI.KINDS.has(k) and float((all[k] as Dictionary).get("share", 0.0)) > 0.0:
			out[k] = float(all[k].share)
	return out


static func perks() -> Dictionary:
	return merged("perks", {"perks": Perks.ALL}).get("perks", Perks.ALL)


static func backgrounds() -> Dictionary:
	return merged("backgrounds", {"backgrounds": Backgrounds.ALL, "flaws": Backgrounds.FLAWS}).get("backgrounds", Backgrounds.ALL)


static func flaws() -> Dictionary:
	return merged("backgrounds", {"backgrounds": Backgrounds.ALL, "flaws": Backgrounds.FLAWS}).get("flaws", Backgrounds.FLAWS)


# --- Checking a mod ----------------------------------------------------------------------------------

static func schema() -> Dictionary:
	if _schema.is_empty():
		var s: Variant = _read_json(SCHEMA_PATH)
		_schema = s if s is Dictionary else {"manifest": {}, "kinds": {}, "records": {}}
	return _schema


## The problems of the mod in `dir` (its manifest and every file it lists against the schema; items
## named by recipes, forage and loot must exist in the game or the mod): [] when it's good.
static func validate(dir: String) -> Array:
	var out: Array = []
	var man: Variant = _read_json("%s/%s" % [dir, MANIFEST])
	if not man is Dictionary:
		return ["mod.json: missing or not valid JSON"]
	_check_fields("mod.json", man, schema().manifest, false, out, {})
	var files: Array = (man as Dictionary).get("files", []) if (man as Dictionary).get("files") is Array else []
	var datas: Array = []
	var items := {}
	for f: Variant in files:
		var name := String(f)
		if not f is String or not name.ends_with(".json") or name.contains("/") or name.contains("\\") or name == MANIFEST:
			out.append("mod.json: files: '%s' should be a data file's name (<kind>.json, beside mod.json)" % name)
			continue
		var data: Variant = _read_json("%s/%s" % [dir, name])
		if data == null:
			out.append("mod.json: files: '%s' is missing or not valid JSON" % name)
			continue
		datas.append([name.get_basename(), data, name])
		if name.get_basename() == "items" and data is Dictionary and (data as Dictionary).get("items") is Array:
			for e: Variant in (data as Dictionary).items:
				if e is Dictionary:
					items[String((e as Dictionary).get("id", ""))] = true
	for d: Array in datas:
		check_file(String(d[0]), d[1], String(d[2]), out, items)
	return out


## `data` (a file of `kind`) against the schema; problems appended to `out`.
static func check_file(kind: String, data: Variant, label: String, out: Array, mod_items := {}) -> void:
	var spec: Dictionary = (schema().kinds as Dictionary).get(kind, {})
	if spec.is_empty():
		out.append("%s: no data file of kind '%s'" % [label, kind])
		return
	if not data is Dictionary:
		out.append("%s: the file should hold an object" % label)
		return
	var colls: Dictionary = spec.collections
	for coll: String in colls:
		if not (data as Dictionary).has(coll):
			continue
		var v: Variant = data[coll]
		var c: Dictionary = colls[coll]
		var ids := _base_ids(kind, coll)
		if String(c.as) == "list":
			if not v is Array:
				out.append("%s: '%s' should be a list" % [label, coll])
				continue
			for i in (v as Array).size():
				var rec: Variant = v[i]
				var rid := String((rec as Dictionary).get("id", "")) if rec is Dictionary else ""
				if rid == "":
					out.append("%s: %s[%d] has no 'id'" % [label, coll, i])
					continue
				_check_record("%s: %s '%s'" % [label, coll, rid], rec, String(c.record), ids.has(rid), out, mod_items)
		else:
			if not v is Dictionary:
				out.append("%s: '%s' should be an object of id -> record" % [label, coll])
				continue
			for rid: Variant in v:
				if String(rid).begins_with("_") or v[rid] == null:
					continue
				_check_record("%s: %s '%s'" % [label, coll, String(rid)], v[rid], String(c.record), ids.has(String(rid)), out, mod_items)


static func _check_record(where: String, rec: Variant, rule_name: String, patch: bool, out: Array, mod_items: Dictionary) -> void:
	var rule: Dictionary = (schema().records as Dictionary).get(rule_name, {})
	if rule.has("list_of"):
		if not rec is Array:
			out.append("%s: should be a list" % where)
			return
		for i in (rec as Array).size():
			_check_fields("%s[%d]" % [where, i], rec[i], rule.list_of, false, out, mod_items)
		return
	_check_fields(where, rec, rule, patch, out, mod_items)


static func _check_fields(where: String, rec: Variant, rule: Dictionary, patch: bool, out: Array, mod_items: Dictionary) -> void:
	if not rec is Dictionary:
		out.append("%s: should be an object" % where)
		return
	var r: Dictionary = rec
	var req: Dictionary = rule.get("required", {})
	var opt: Dictionary = rule.get("optional", {})
	for k: String in req:
		if not r.has(k):
			if not patch:
				out.append("%s: missing '%s' (%s)" % [where, k, String(req[k])])
		elif r[k] != null and not type_ok(r[k], String(req[k])):
			out.append("%s: '%s' should be %s" % [where, k, String(req[k])])
	for k: Variant in r:
		if opt.has(k) and r[k] != null and not type_ok(r[k], String(opt[k])):
			out.append("%s: '%s' should be %s" % [where, String(k), String(opt[k])])
	var refs: Dictionary = rule.get("refs", {})
	for k: String in refs:
		if r.has(k) and r[k] != null:
			for iid: String in _ref_ids(r[k], String(refs[k])):
				if not ItemDB.has_item(StringName(iid)) and not mod_items.has(iid):
					out.append("%s: '%s' names an unknown item '%s'" % [where, k, iid])


static func _ref_ids(v: Variant, how: String) -> Array:
	var out: Array = []
	var bad := false
	match how:
		"id":
			out.append(v)
		"pair":
			if v is Array and not (v as Array).is_empty():
				out.append(v[0])
		"pairs", "rows":
			for row: Variant in (v if v is Array else []):
				if row is Array and not (row as Array).is_empty():
					out.append(row[0])
				else:
					bad = true
		"bundles":
			for bundle: Variant in (v if v is Array else []):
				for row: Variant in (bundle if bundle is Array else []):
					if row is Array and not (row as Array).is_empty():
						out.append(row[0])
					else:
						bad = true
	var ids: Array = []
	for x: Variant in out:
		if x is String:
			ids.append(x)
		else:
			bad = true
	if bad:
		ids.append("<malformed>")
	return ids


static func type_ok(v: Variant, t: String) -> bool:
	match t:
		"any":
			return true
		"string":
			return v is String or v is StringName
		"int":
			return v is int or (v is float and is_equal_approx(float(v), roundf(float(v))))
		"number":
			return v is int or v is float
		"bool":
			return v is bool
		"array":
			return v is Array
		"dict":
			return v is Dictionary
	return false


## The ids the game's own data has in `kind`'s collection `coll` (a mod's record with one of them is
## a patch: only the fields it gives are checked).
static func _base_ids(kind: String, coll: String) -> Dictionary:
	var out := {}
	match kind:
		"items":
			for id: StringName in ItemDB.all_ids():
				out[String(id)] = true
			return out
		"zombies":
			for k: String in ZombieAI.KINDS:
				out[k] = true
			return out
		"perks":
			for k: String in Perks.ALL:
				out[k] = true
			return out
		"backgrounds":
			for k: String in (Backgrounds.ALL if coll == "backgrounds" else Backgrounds.FLAWS):
				out[k] = true
			return out
	var base := String(((schema().kinds as Dictionary).get(kind, {}) as Dictionary).get("base", ""))
	if base.begins_with("res://"):
		var data: Variant = _read_json(base)
		if data is Dictionary:
			var v: Variant = (data as Dictionary).get(coll)
			if v is Dictionary:
				for k: Variant in v:
					out[String(k)] = true
			elif v is Array:
				for e: Variant in v:
					if e is Dictionary:
						out[String((e as Dictionary).get("id", ""))] = true
	return out


# --- World cards -------------------------------------------------------------------------------------

## The world being played as a card: {"card", "version", "name", "seed", "options" (the New world
## options, no survivor), "mods": [names]}.
static func world_card() -> Dictionary:
	var st := Survival.state()
	var opts: Dictionary = (st.get("options", {}) as Dictionary).duplicate(true)
	opts.erase("survivor")
	return {"card": CARD_KIND, "version": CARD_VERSION, "name": String(st.get("name", Survival.world)), "seed": int(st.get("seed", 0)),
		"options": opts, "mods": mods.map(func(m: Dictionary) -> String: return "%s %s" % [m.name, m.version])}


## Writes the card (world_card, or `card`) to CARD_DIR/<name>.json. Returns the path ("" failed).
static func export_card(card := {}, dir := CARD_DIR) -> String:
	var c := card if not card.is_empty() else world_card()
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s.json" % [dir, String(c.get("name", "world")).validate_filename()]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(c, "\t"))
	return path


## A card's text read back: {"name", "seed", "options", "mods", "missing_mods": [names not on]} or
## {"error": why}. Options outside New world's levels are dropped.
static func import_card(text: String) -> Dictionary:
	var c: Variant = JSON.parse_string(text)
	if not c is Dictionary or String((c as Dictionary).get("card", "")) != CARD_KIND:
		return {"error": "Not a Fallen world card"}
	if int(c.get("version", 0)) > CARD_VERSION:
		return {"error": "A newer card than this game reads"}
	if not (c.get("seed") is float or c.get("seed") is int):
		return {"error": "The card has no seed"}
	var opts := {}
	var levels := ["low", "normal", "high"]
	for k: Variant in (c.get("options", {}) as Dictionary):
		var v := String(c.options[k])
		match String(k):
			"goal":
				if v in ["evac", "sandbox", "clear"]:
					opts.goal = v
			"season":
				if v in ["spring", "summer", "autumn", "winter"]:
					opts.season = v
			"join":
				if v in ["farm", "host"]:
					opts.join = v
			_:
				if v in levels:
					opts[String(k)] = v
	var on := mods.map(func(m: Dictionary) -> String: return "%s %s" % [m.name, m.version])
	var missing: Array = (c.get("mods", []) as Array).filter(func(n: Variant) -> bool: return not String(n) in on)
	return {"name": String(c.get("name", "world")), "seed": int(c.seed), "options": opts, "mods": c.get("mods", []), "missing_mods": missing}


## The newest card in CARD_DIR as text ("" none).
static func newest_card_text(dir := CARD_DIR) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	var best := ""
	var best_t := -1
	for f: String in d.get_files():
		if f.ends_with(".json"):
			var t := FileAccess.get_modified_time("%s/%s" % [dir, f])
			if t > best_t:
				best_t = t
				best = "%s/%s" % [dir, f]
	if best == "":
		return ""
	var file := FileAccess.open(best, FileAccess.READ)
	return file.get_as_text() if file else ""
