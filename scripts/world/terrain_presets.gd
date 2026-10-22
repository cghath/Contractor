class_name TerrainPresets
extends RefCounted
## Terrain presets (data/terrain_presets.json): the land shape, ground colours, sea and scatter
## a zone is generated with. choose() works out a zone def's preset, so the choice sits in the
## def the host sends (same world on every peer). See docs/terrain_presets.md.

const PATH := "res://data/terrain_presets.json"

static var _data := {}
static var _mixed := {}  # "mix#<seed>" -> its blended preset

## Procedural terrains (Captain, 2026-10-17: "maybe extra procedural terrains too"): "mix#<seed>"
## blends two presets of MIX_FROM, picked by the seed, at MIX_T [min, max] of the way from the
## first to the second: numbers and colours in "land", "palette", "ground" and "scatter" lerp,
## a key only one has comes from it; "sea", "wadi" and "water" come whole from the nearer of the two. A
## zone def with "terrain": "procedural" gets "mix#<its seed>" (choose).
const MIX := "mix#"
const PROCEDURAL := "procedural"
const MIX_FROM: Array[String] = ["temperate", "coastal_lowland", "amphibious_coast", "salt_flats", "desert_wadi", "rocky_ridge",
	"scrubland", "highland_moor", "river_valley", "badlands"]
const MIX_T := Vector2(0.25, 0.75)


static func _load() -> void:
	if not _data.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed
	else:
		push_error("TerrainPresets: cannot read %s" % PATH)
		_data = {"presets": {"plain": {}}, "default": "plain"}


static func ids() -> Array:
	_load()
	return (_data.presets as Dictionary).keys()


static func has(id: String) -> bool:
	_load()
	return (_data.presets as Dictionary).has(id) or (id.begins_with(MIX) and id.substr(MIX.length()).is_valid_int())


## The preset `id` (an unknown id gives the default one).
static func get_preset(id: String) -> Dictionary:
	_load()
	var presets: Dictionary = _data.presets
	if id.begins_with(MIX) and has(id):
		return _mix(id)
	return presets.get(id, presets.get(String(_data.get("default", "plain")), {}))


static func _mix(id: String) -> Dictionary:
	if _mixed.has(id):
		return _mixed[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(id.substr(MIX.length()))
	var from: Array = MIX_FROM.filter(func(k: String) -> bool: return (_data.presets as Dictionary).has(k))
	var a: Dictionary = _data.presets[from[rng.randi() % from.size()]]
	var b: Dictionary = _data.presets[from[rng.randi() % from.size()]]
	var t := rng.randf_range(MIX_T.x, MIX_T.y)
	var out := {"name": "%s / %s" % [a.get("name", "?"), b.get("name", "?")]}
	for key: String in ["land", "palette", "ground", "scatter"]:
		if a.has(key) or b.has(key):
			out[key] = _blend(a.get(key, {}), b.get(key, {}), t)
	var near: Dictionary = a if t < 0.5 else b
	for key: String in ["sea", "wadi", "water"]:
		if near.has(key):
			out[key] = (near[key] as Dictionary).duplicate(true)
	_mixed[id] = out
	return out


## `x` and `y` blended at `t`: numbers and "rrggbb" colours lerp, dictionaries and same-length
## arrays blend by key/element, anything else (or a key one lacks) comes from the one that has it.
static func _blend(x: Variant, y: Variant, t: float) -> Variant:
	if (typeof(x) == TYPE_FLOAT or typeof(x) == TYPE_INT) and (typeof(y) == TYPE_FLOAT or typeof(y) == TYPE_INT):
		return lerpf(float(x), float(y), t)
	if typeof(x) == TYPE_STRING and typeof(y) == TYPE_STRING and String(x).is_valid_html_color() and String(y).is_valid_html_color() 			and String(x).length() == 6 and String(y).length() == 6:
		return Color(String(x)).lerp(Color(String(y)), t).to_html(false)
	if typeof(x) == TYPE_DICTIONARY and typeof(y) == TYPE_DICTIONARY:
		var out := {}
		for k in (x as Dictionary).keys() + (y as Dictionary).keys():
			if out.has(k):
				continue
			if (x as Dictionary).has(k) and (y as Dictionary).has(k):
				out[k] = _blend(x[k], y[k], t)
			else:
				out[k] = (x as Dictionary).get(k, (y as Dictionary).get(k))
		return out
	if typeof(x) == TYPE_ARRAY and typeof(y) == TYPE_ARRAY and (x as Array).size() == (y as Array).size():
		var out: Array = []
		for i in (x as Array).size():
			out.append(_blend(x[i], y[i], t))
		return out
	return x if t < 0.5 else y


## The preset a zone def uses: its "terrain" if that names one, else a word of its name
## ("Salt flats", "Black Ridge hills"), else its region's default, else the default preset.
static func choose(def: Dictionary) -> String:
	_load()
	var named := String(def.get("terrain", ""))
	if named == PROCEDURAL:
		return "%s%d" % [MIX, int(def.get("seed", 0))]
	if named != "" and has(named):
		return named
	var zone_name := String(def.get("name", "")).to_lower()
	for hint: Array in _data.get("name_hints", []):
		if zone_name.contains(String(hint[0])):
			return String(hint[1])
	var by_region: Dictionary = _data.get("region_defaults", {})
	var region := String(def.get("region", ""))
	if by_region.has(region):
		return String(by_region[region])
	return String(_data.get("default", "plain"))
