class_name Prices
extends RefCounted
## What things cost, from res://data/prices.json (wave 4, W10): shop prices, what salvage is
## worth, sell-back value, repairs, support calls, base upkeep and the stand-in wage bill.
## Every number is Proposed. An item with no price of its own uses its type's default.

const PATH := "res://data/prices.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Prices: cannot read %s" % PATH)
			return {}
		_data = parsed
	return _data


static func reload() -> void:
	_data = {}


## The shop price of one `item_id` (0 for an unknown item).
static func price_of(item_id: StringName) -> int:
	var items: Dictionary = data().get("items", {})
	if items.has(String(item_id)):
		return int(items[String(item_id)])
	var item := ItemDB.get_item(item_id)
	if item == null:
		return 0
	return int((data().get("default_by_type", {}) as Dictionary).get(item.type, 0))


## Whether the base shop sells `item_id` (objective items and loot-only items it doesn't).
static func for_sale(item_id: StringName) -> bool:
	return ItemDB.has_item(item_id) and not String(item_id) in data().get("not_for_sale", []) and price_of(item_id) > 0


## Every item the shop sells, grouped by type then by name.
static func shop_items() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in ItemDB.all_ids():
		if for_sale(id):
			out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ia := ItemDB.get_item(a)
		var ib := ItemDB.get_item(b)
		return ia.name < ib.name if ia.type == ib.type else ia.type < ib.type)
	return out


## Condition 0..1 of an item from its state: a ceramic plate's integrity, less a little per
## chip on armor (1 when undamaged or stateless).
static func condition_of(state: Dictionary) -> float:
	var condition := float(state.get("integrity", 1.0))
	condition -= 0.02 * (state.get("chips", []) as Array).size()
	return clampf(condition, 0.1, 1.0)


## What `count` of `item_id` are worth (salvage picks and the value of what's left in the
## field), by their condition.
static func value_of(item_id: StringName, count := 1, state := {}) -> int:
	var item: ItemData = ItemDB.get_item(item_id) if ItemDB.has_item(item_id) else null
	var each := price_of(item_id) + Optics.extra_price(item, state) + Suppressors.extra_price(item, state) if item else price_of(item_id)  # a gun's optic/suppressor
	return roundi(each * count * condition_of(state))


## What the shop pays for them.
static func sell_price(item_id: StringName, count := 1, state := {}) -> int:
	return floori(value_of(item_id, count, state) * float(data().get("sell_ratio", 0.4)))


## What it costs to bring a damaged item back to new (0 if it isn't damaged): a share of its
## price for lost integrity plus a fee per chip, capped at "max_share" of the price.
static func repair_cost(item_id: StringName, state: Dictionary) -> int:
	var rules: Dictionary = data().get("repair", {})
	var price := price_of(item_id)
	var lost := 1.0 - float(state.get("integrity", 1.0))
	var chips := (state.get("chips", []) as Array).size()
	var cost := price * lost * float(rules.get("share_per_integrity", 0.8)) + chips * float(rules.get("per_chip", 12))
	return mini(ceili(cost), ceili(price * float(rules.get("max_share", 0.8))))


## The cost of one support call ("resupply", "transport", "aav", "extraction").
static func support_price(kind: String) -> int:
	return int((data().get("supports", {}) as Dictionary).get(kind, 0))


static func support_kinds() -> Array:
	return (data().get("supports", {}) as Dictionary).keys()


## What a helicopter support lost this op costs to replace (0 for a kind with no helicopter).
static func lost_support_price(kind: String) -> int:
	return int((data().get("lost_supports", {}) as Dictionary).get(kind, 0))


## A deployment's running costs (data/prices.json "operations"): per_head_day, kia_benefit, wounded_care.
static func operations(key: String) -> int:
	return int((data().get("operations", {}) as Dictionary).get(key, 0))


static func weekly_upkeep() -> int:
	return int(data().get("weekly_upkeep", 0))


## The stand-in weekly wage bill, used until the base agent's roster supplies the real one
## (Economy.wages_provider).
static func default_wage_bill() -> int:
	return int(data().get("default_wage_bill", 0))


## A player respawn past the deployment's free ones (RosterDeployment.FREE_RESPAWNS).
static func respawn_price() -> int:
	return int(data().get("respawn", 1000))


## How much more each further bought respawn costs, as a share of respawn_price.
static func respawn_rise() -> float:
	return float(data().get("respawn_rise", 0.0))
