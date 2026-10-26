class_name WorldTrade
extends RefCounted
## Trade's value scale and traders' prices (docs/survival_world.md section 8, call 26).
## - value(item_id): what one of an item is worth (dollars): data/prices.json where it prices the
##   item, else its tags (TAG_VALUE), else its type's default; then the survival weights: ammo,
##   meds, food and fuel weigh most (CATEGORY_FLOOR lifts the base shop's cheap tins, WEIGHT
##   multiplies), the season's and the region's multipliers (hooks: SEASON_MULT, REGION_MULT;
##   constants for now). Cash (SurvivorPerson.CASH_VALUE) is worth its face, drifting by the seed.
## - A trader's offer (buy_price / sell_price): the value moved by the trader's group's need (its
##   supplies record: what it lacks pays and costs more, its surplus less) and its relation to the
##   players (friends pay more and ask less). Cash is cash: no markup either way.
## - The far tick swaps group supplies (WorldGroup.SUPPLY_KEYS) at SUPPLY_VALUE, moved by need: a
##   group gives what it has days of and takes what it lacks (swap).
## Barter (the players' swap) and TradeScreen read this.

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


## Proposed: the survival weights (call 26: ammo, meds, food, fuel weigh most), by
## Settlement.category_of; a category's floor lifts the base shop's cheap prices (a tin is $3
## there) before the weight.
const WEIGHT := {"ammo": 2.0, "meds": 2.0, "food": 2.0, "fuel": 2.0, "water": 1.5, "parts": 1.2}
const CATEGORY_FLOOR := {"ammo": 10.0, "meds": 20.0, "food": 15.0, "water": 10.0, "fuel": 30.0, "parts": 15.0}
## Proposed hooks (constants for now): a season's and a region's multipliers by category.
const SEASON_MULT := {"winter": {"fuel": 1.5, "food": 1.25}, "summer": {"water": 1.25}}
const REGION_MULT := {"desert": {"water": 1.6, "fuel": 1.2}, "city": {"food": 1.2}, "coast": {"fuel": 0.9}}
## Proposed: how far cash's value drifts by the world's seed (+-).
const CASH_DRIFT := 0.15
## Proposed: a trader's need moves a price (lacks it: x NEED_HIGH; has it spare: x NEED_LOW), and
## its relation: at 0 it pays BUY_AT and asks SELL_AT of the value; each 100 standing moves both
## by REL_X in your favour.
const NEED_HIGH := 1.5
const NEED_LOW := 0.75
const BUY_AT := 0.85
const SELL_AT := 1.15
const REL_X := 0.2
## A category -> the group supply it feeds.
const CAT_SUPPLY := {"food": "food", "water": "water", "fuel": "fuel", "ammo": "ammo", "meds": "meds", "parts": "scrap", "wood": "wood", "scrap": "scrap"}

## The season now ("" none yet: the seasons are phase D's; a hook).
static var season := ""


## What one `item_id` is worth on the value scale (dollars), in `region` ("" none). Main thread
## (ItemDB).
static func value(item_id: String, region := "") -> float:
	if is_cash(item_id):
		return cash_value(item_id)
	var cat := Settlement.category_of(item_id)
	var v := base_value(item_id)
	v = maxf(v, float(CATEGORY_FLOOR.get(cat, 0.0))) * float(WEIGHT.get(cat, 1.0))
	v *= float((SEASON_MULT.get(season, {}) as Dictionary).get(cat, 1.0))
	v *= float((REGION_MULT.get(region, {}) as Dictionary).get(cat, 1.0))
	return snappedf(v, 0.01)


## The base shop's worth of `item_id`: prices.json's item price, else its tags', else its type's.
static func base_value(item_id: String) -> float:
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


static func is_cash(item_id: String) -> bool:
	return SurvivorPerson.CASH_VALUE.has(item_id)


## Cash's worth: its face (SurvivorPerson.CASH_VALUE), drifted by the world's seed (+-CASH_DRIFT).
static func cash_value(item_id: String) -> float:
	var face := float(SurvivorPerson.CASH_VALUE.get(item_id, 0))
	return snappedf(face * cash_drift(), 0.01)


static func cash_drift() -> float:
	var r := float(absi(hash([int(Survival.state().get("seed", 0)), "cash_drift"])) % 1000) / 1000.0
	return 1.0 - CASH_DRIFT + r * CASH_DRIFT * 2.0


## How `g`'s need moves the price of `item_id`: NEED_HIGH when the group lacks its supply,
## NEED_LOW when it has it spare, 1 else (and for cash or a group of nobody).
static func need_mult(g: Dictionary, item_id: String) -> float:
	if g.is_empty() or is_cash(item_id):
		return 1.0
	var key := String(CAT_SUPPLY.get(Settlement.category_of(item_id), ""))
	if key == "":
		return 1.0
	if lack(g).has(key):
		return NEED_HIGH
	if surplus(g).has(key):
		return NEED_LOW
	return 1.0


## `g`'s standing with the players (-100..100; 0 for nobody).
static func relation_of(g: Dictionary) -> float:
	return WorldGroup.relation(g, "player") if not g.is_empty() else 0.0


## What `g`'s trader pays for one of yours (dollars).
static func buy_price(g: Dictionary, item_id: String, region := "") -> float:
	if is_cash(item_id):
		return value(item_id)
	var rel := clampf(relation_of(g), -100.0, 100.0) / 100.0
	return snappedf(value(item_id, region) * need_mult(g, item_id) * maxf(0.2, BUY_AT + REL_X * rel), 0.01)


## What `g`'s trader asks for one of theirs (dollars).
static func sell_price(g: Dictionary, item_id: String, region := "") -> float:
	if is_cash(item_id):
		return value(item_id)
	var rel := clampf(relation_of(g), -100.0, 100.0) / 100.0
	return snappedf(value(item_id, region) * need_mult(g, item_id) * maxf(0.5, SELL_AT - REL_X * rel), 0.01)


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
