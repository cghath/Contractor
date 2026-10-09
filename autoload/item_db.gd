extends Node
## Item definitions, loaded once from res://data/items.json.

const PATH := "res://data/items.json"

var _items: Dictionary = {}  # StringName -> ItemData


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
	return _items.get(id)


func has_item(id: StringName) -> bool:
	return _items.has(id)


func all_ids() -> Array:
	return _items.keys()
