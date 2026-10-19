class_name Quartermaster
extends RefCounted
## Allied quartermasters (wave 6, call #1 "what each tier unlocks", Captain 2026-10-18: Trusted
## buys "their military kit", Allied "their best kit, armour"). Each allied employer's
## factions.json "quartermaster" lists, by tier id, a discount and the items it sells the squad
## at that standing or better: its own kit cheaper from Trusted, more off and its armour from
## Allied. prices.json "allied_only" items aren't in the base shop at all: only a quartermaster
## the squad stands high enough with sells them.
##
## One price for anything the company can buy (price(), sells()): the base shop's, or the best
## quartermaster deal at today's standing, whichever is lower. Economy.server_buy and the base
## terminal (BaseEconomy.item_price) both go through it, so the shop UI and the terminal agree.
## Standing is read through Economy.reputation, so it works on every peer.
## MRAPs (also Trusted in call #1) need vehicles the company owns, which aren't built: not here.


## factions.json "quartermaster" of `faction` ({} for none).
static func of(faction: String) -> Dictionary:
	return MissionRegistry.faction(faction).get("quartermaster", {})


## The best deal on `item_id` from an allied quartermaster at today's standing:
## {"faction", "tier_id", "discount", "price"}, or {} when none sells it to the squad.
static func best_deal(item_id: StringName) -> Dictionary:
	var best := {}
	var base := Prices.price_of(item_id)
	if base <= 0:
		return best
	for f: String in MissionRegistry.faction_ids():
		var qm := of(f)
		if qm.is_empty():
			continue
		var tier := MissionRegistry.tier_index(Economy.reputation(f))
		var tiers := MissionRegistry.reputation_tiers()
		for i in tiers.size():
			var entry: Dictionary = qm.get(String(tiers[i].id), {})
			if entry.is_empty() or i > tier or not String(item_id) in (entry.get("items", []) as Array):
				continue
			var discount := float(entry.get("discount", 0.0))
			var price := maxi(1, roundi(base * (1.0 - discount)))
			if best.is_empty() or price < int(best.price):
				best = {"faction": f, "tier_id": String(tiers[i].id), "discount": discount, "price": price}
	return best


## Whether the base shop holds `item_id` back for the allied quartermasters (prices.json "allied_only").
static func allied_only(item_id: StringName) -> bool:
	return String(item_id) in (Prices.data().get("allied_only", []) as Array)


## Whether the company can buy `item_id` today: the base shop, or a quartermaster.
static func sells(item_id: StringName) -> bool:
	return Prices.for_sale(item_id) or not best_deal(item_id).is_empty()


## What one `item_id` costs the company today (0: nobody sells it to us).
static func price(item_id: StringName) -> int:
	var deal := best_deal(item_id)
	var base := Prices.price_of(item_id) if Prices.for_sale(item_id) else 0
	if deal.is_empty():
		return base
	return int(deal.price) if base <= 0 else mini(base, int(deal.price))


## Who sells `item_id` at price() when it isn't the base shop at its list price: "US Forces,
## Trusted -15%", or "" for the base shop.
static func seller_text(item_id: StringName) -> String:
	var deal := best_deal(item_id)
	if deal.is_empty() or (Prices.for_sale(item_id) and int(deal.price) >= Prices.price_of(item_id)):
		return ""
	var tier_name := String(MissionRegistry.reputation_tiers().filter(func(t: Dictionary) -> bool: return String(t.id) == String(deal.tier_id)).front().get("name", deal.tier_id))
	return "%s, %s -%d%%" % [MissionRegistry.faction_name(String(deal.faction)), tier_name, roundi(float(deal.discount) * 100.0)]


## Everything the company can buy today (the base shop plus what quartermasters add), sorted
## like Prices.shop_items().
static func catalog() -> Array[StringName]:
	var out := Prices.shop_items()
	for id: StringName in ItemDB.all_ids():
		if not id in out and allied_only(id) and not best_deal(id).is_empty():
			out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ia := ItemDB.get_item(a)
		var ib := ItemDB.get_item(b)
		return ia.name < ib.name if ia.type == ib.type else ia.type < ib.type)
	return out
