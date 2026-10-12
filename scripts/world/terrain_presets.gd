class_name TerrainPresets
extends RefCounted
## Terrain presets (data/terrain_presets.json): the land shape, ground colours, sea and scatter
## a zone is generated with. choose() works out a zone def's preset, so the choice sits in the
## def the host sends (same world on every peer). See docs/terrain_presets.md.

const PATH := "res://data/terrain_presets.json"

static var _data := {}


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
	return (_data.presets as Dictionary).has(id)


## The preset `id` (an unknown id gives the default one).
static func get_preset(id: String) -> Dictionary:
	_load()
	var presets: Dictionary = _data.presets
	return presets.get(id, presets.get(String(_data.get("default", "plain")), {}))


## The preset a zone def uses: its "terrain" if that names one, else a word of its name
## ("Salt flats", "Black Ridge hills"), else its region's default, else the default preset.
static func choose(def: Dictionary) -> String:
	_load()
	var named := String(def.get("terrain", ""))
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
