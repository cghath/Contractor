class_name WorldTrade
extends RefCounted
## Trade's value scale (docs/survival_world.md section 8, call 26): the first form the world sim
## needs, for the trade lane to extend. value(item_id) is what one of an item is worth (dollars):
## data/prices.json where it prices the item or its type, else by type and tags. The far tick
## swaps group supplies (WorldGroup.SUPPLY_KEYS) at SUPPLY_VALUE, moved by need: a group gives
## what it has days of and takes what it lacks (swap). Season and region moving prices, cash
## drifting and traders' markups by relation are the trade lane's.

## Proposed: what a unit of each group supply is worth (dollars; food and water a person-day).
const SUPPLY_VALUE := {"food": 30.0, "water": 20.0, "fuel": 40.0, "ammo": 25.0, "meds": 80.0, "wood": 5.0, "scrap": 10.0}
## Proposed: what an item is worth by tag when prices.json has nothing for it.
const TAG_VALUE := {"food": 25, "water": 15, "medical": 60, "fuel": 40, "ammo": 20, "melee": 60, "tool": 40}
const DEFAULT_VALUE := 20
## A group keeps this many days of a supply before it'll trade it away (Proposed).
const KEEP_DAYS := 3.0

static var _prices := {}


static func prices() -> Dictionary:
	if _prices.is_empty():
		var f := FileAccess.open("res://data/prices.json", FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text()) if f else null
		_prices = parsed if parsed is Dictionary else {"_": true}
	return _prices


## What one `item_id` is worth on the value scale (dollars). Main thread (ItemDB).
static func value(item_id: String) -> float:
	var p := prices()
	var items: Dictionary = p.get("items", {})
	if items.has(item_id) and (items[item_id] is float or items[item_id] is int):
		return float(items[item_id])
	var item := ItemDB.get_item(StringName(item_id))
	if item == null:
		return float(DEFAULT_VALUE)
	for tag: String in TAG_VALUE:
		if tag in item.tags:
			return float(TAG_VALUE[tag])
	var by_type: Dictionary = p.get("default_by_type", {})
	return float(by_type.get(String(item.type), DEFAULT_VALUE))


## The value of a supplies dictionary.
static func supplies_value(s: Dictionary) -> float:
	var v := 0.0
	for k: String in s:
		v += float(s[k]) * float(SUPPLY_VALUE.get(k, 0.0))
	return v


## What `g` would give: each supply beyond KEEP_DAYS per member (food and water) or half its
## other stocks. {key: amount}.
static func surplus(g: Dictionary) -> Dictionary:
	var n := maxf(1.0, float(WorldGroup.size(g)))
	var out := {}
	for k: String in WorldGroup.SUPPLY_KEYS:
		var have := WorldGroup.supply(g, k)
		var keep := KEEP_DAYS * n if k in ["food", "water"] else have * 0.5
		if have - keep > 0.05:
			out[k] = have - keep
	return out


## What `g` lacks: food and water under KEEP_DAYS per member, ammo under 2 a member, meds under
## half a member. {key: amount}.
static func lack(g: Dictionary) -> Dictionary:
	var n := maxf(1.0, float(WorldGroup.size(g)))
	var want := {"food": KEEP_DAYS * n, "water": KEEP_DAYS * n, "ammo": 2.0 * n, "meds": 0.5 * n, "fuel": 1.0}
	var out := {}
	for k: String in want:
		var short := float(want[k]) - WorldGroup.supply(g, k)
		if short > 0.05:
			out[k] = short
	return out


## How much a trade between `a` and `b` would help both (0-1+): what each lacks that the other
## has spare, by value.
static func gain(a: Dictionary, b: Dictionary) -> float:
	var v := 0.0
	var sa := surplus(a)
	var sb := surplus(b)
	var la := lack(a)
	var lb := lack(b)
	for k: String in la:
		v += minf(float(la[k]), float(sb.get(k, 0.0))) * float(SUPPLY_VALUE.get(k, 0.0))
	for k: String in lb:
		v += minf(float(lb[k]), float(sa.get(k, 0.0))) * float(SUPPLY_VALUE.get(k, 0.0))
	return v / 400.0


## A swap at value-scale prices: each side gets what it lacks from the other's surplus, paid for
## with its own surplus of equal value. Returns the value that changed hands.
static func swap(a: Dictionary, b: Dictionary) -> float:
	var moved := 0.0
	for pair: Array in [[a, b], [b, a]]:
		var taker: Dictionary = pair[0]
		var giver: Dictionary = pair[1]
		var giver_spare := surplus(giver)
		var taker_spare := surplus(taker)
		for k: String in lack(taker):
			var amount := minf(float(lack(taker).get(k, 0.0)), float(giver_spare.get(k, 0.0)))
			if amount <= 0.0:
				continue
			var cost := amount * float(SUPPLY_VALUE.get(k, 0.0))
			var paid := 0.0
			for pk: String in taker_spare.keys():  # paid in the taker's own spare stock
				if pk == k or paid >= cost:
					continue
				var unit := float(SUPPLY_VALUE.get(pk, 1.0))
				var give := minf(float(taker_spare[pk]), (cost - paid) / unit)
				WorldGroup.add_supply(taker, pk, -give)
				WorldGroup.add_supply(giver, pk, give)
				taker_spare[pk] = float(taker_spare[pk]) - give
				paid += give * unit
			var got := amount * minf(1.0, paid / maxf(cost, 0.01))
			WorldGroup.add_supply(giver, k, -got)
			WorldGroup.add_supply(taker, k, got)
			giver_spare[k] = float(giver_spare.get(k, 0.0)) - got
			moved += got * float(SUPPLY_VALUE.get(k, 0.0))
	return moved
