extends Node
## Item definitions, loaded once from res://data/items.json.

const PATH := "res://data/items.json"

var _items: Dictionary = {}  # StringName -> ItemData
## Ids that went, and what an old save's item is now (one 12-gauge system, 2026-10-21: the loose
## rounds_12g and the slugs are Standard buck; cghath's M870 is the Remington 870).
const ALIASES := {&"rounds_12g": &"shells_12g_buck", &"shells_12g_slug": &"shells_12g_buck", &"m870": &"rem870"}


func _ready() -> void:
	load_items()


func load_items() -> void:
	_items.clear()
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("ItemDB: cannot open %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("items"):
		push_error("ItemDB: %s is not a valid item file" % PATH)
		return
	for entry: Dictionary in parsed["items"]:
		var item := ItemData.from_dict(entry)
		if _items.has(item.id):
			push_warning("ItemDB: duplicate item id '%s'" % item.id)
		_items[item.id] = item


func get_item(id: StringName) -> ItemData:
	return _items.get(id, _items.get(ALIASES.get(id, &""))) if not _items.has(id) else _items[id]


func has_item(id: StringName) -> bool:
	return _items.has(id) or _items.has(ALIASES.get(id, &""))


func all_ids() -> Array:
	return _items.keys()


## Everything a player is told about item `id` (Captain, 2026-10-14: "item descriptions plus
## uses also needed"): {"name", "desc", "uses": [lines], "stats": {...}} where stats holds only
## what applies, in plain units: "type", "slot", "weight" (kg), "volume" (L), "stack", "value"
## ($, Prices), "two_handed", "capacity" (L), "ammo" (the magazine's name), "rounds",
## "calibre", "magnification" (and "magnification_max"), "rating", "material", "fits",
## "treats" (wound kinds), "treat_s", "contents" (a kit's: name -> count), "fuse_s",
## "reload_s". {} for an unknown id. ItemInfo turns it into tooltips and the inspect panel.
func describe(id: StringName) -> Dictionary:
	var item := get_item(id)
	if item == null:
		return {}
	var s := item.stats
	var stats := {"type": item.type, "weight": item.mass_kg, "volume": item.volume_l, "value": Prices.price_of(id)}
	if item.slot != &"":
		stats["slot"] = String(item.slot)
	if item.stack > 1:
		stats["stack"] = item.stack
	if item.two_handed:
		stats["two_handed"] = true
	if item.capacity_l > 0.0:
		stats["capacity"] = item.capacity_l
	elif s.has("capacity_l"):  # a pouch counted in litres
		stats["capacity"] = float(s.capacity_l)
	if s.has("ammo") and has_item(StringName(s.ammo)):
		stats["ammo"] = get_item(StringName(s.ammo)).name
	if item.magazine_rounds() > 0:
		stats["rounds"] = item.magazine_rounds()
	for key: String in ["calibre", "rating", "material", "fuse_s", "reload_s", "treat_s"]:
		if s.has(key):
			stats[key] = s[key]
	if s.has("magnification"):
		stats["magnification"] = float(s.magnification)
		if s.has("magnification_max"):
			stats["magnification_max"] = float(s.magnification_max)
	if s.has("fits"):
		stats["fits"] = PackedStringArray(s.fits)
	if s.has("treats"):
		stats["treats"] = PackedStringArray(s.treats)
	if s.has("contents"):
		var inside := {}
		for kit_id: String in s.contents:
			var kit_item := get_item(StringName(kit_id))
			inside[kit_item.name if kit_item else kit_id] = int(s.contents[kit_id])
		stats["contents"] = inside
	return {"name": item.name, "desc": item.desc, "uses": Array(item.uses), "stats": stats}
