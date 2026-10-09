class_name ItemData
extends RefCounted
## Static definition of one item type. Loaded from res://data/items.json by ItemDB.

var id: StringName
var name: String
## weapon, ammo, armor, plate, backpack, medical, utility, objective, salvage
var type: String
## Body slot this item equips to (&"" = stow only). &"plate" means either plate slot.
var slot: StringName
var volume_l: float
var mass_kg: float
## Display grouping only; volume is what limits how many you can carry.
var stack: int = 1
## Bulky items are carried in both hands instead of going into a container.
var two_handed: bool = false
## Storage this item adds while equipped (vests, backpacks).
var capacity_l: float = 0.0
var tags: PackedStringArray
## Type-specific numbers: weapon damage and fire rate, plate material, visual size...
var stats: Dictionary


static func from_dict(d: Dictionary) -> ItemData:
	var item := ItemData.new()
	item.id = StringName(d["id"])
	item.name = d.get("name", String(item.id))
	item.type = d.get("type", "misc")
	item.slot = StringName(d.get("slot", ""))
	item.volume_l = float(d.get("volume_l", 0.0))
	item.mass_kg = float(d.get("mass_kg", 0.0))
	item.stack = int(d.get("stack", 1))
	item.two_handed = bool(d.get("two_handed", false))
	item.capacity_l = float(d.get("capacity_l", 0.0))
	item.tags = PackedStringArray(d.get("tags", []))
	item.stats = d.get("stats", {})
	return item
