class_name Fixers
extends RefCounted
## Wave 6 (item catalogue: "Contraband ... not in the shop. Shady fixers pay well; lawful factions
## lose reputation"): contraband (items tagged "contraband": cigarettes, captagon, counterfeit
## dollars, unregistered weapons) is found in the field, never bought. A fixer whose contracts.json
## entry "buys" contraband (Mama Rook) pays "buy_mult" of its price from the company stash and
## thinks better of the company ("buy_rep" with the fixer's faction a lot), as long as that
## faction will deal with it (not Hostile or Distrusted). Sold at the base instead it fetches the
## usual sell-back share, and every lawful faction (factions.json "lawful") thinks less of the
## company (LAWFUL_HIT a lot). Numbers Proposed.

const TAG := "contraband"
const LAWFUL_HIT := -1


static func is_contraband(item_id: StringName) -> bool:
	return ItemDB.has_item(item_id) and TAG in ItemDB.get_item(item_id).tags


## The fixer who buys contraband from the company now ({} for none): the first with "buys"
## "contraband" whose faction stands at Neutral or better with it.
static func buyer() -> Dictionary:
	for f: Dictionary in MissionRegistry.fixers():
		if String(f.get("buys", "")) == TAG and Economy.tier(String(f.get("faction", ""))) >= MissionRegistry.neutral_tier():
			return f
	return {}


## What `buyer()` pays for `count` of `item_id` (0: nobody buys it).
static func offer(item_id: StringName, count := 1) -> int:
	var f := buyer()
	if f.is_empty() or not is_contraband(item_id):
		return 0
	return roundi(Prices.price_of(item_id) * float(f.get("buy_mult", 1.0))) * count


## Host: sells `count` of contraband `item_id` from the stash to the fixer. Returns what it
## fetched (0: none in the stash, not contraband, or no fixer buying).
static func server_sell(item_id: StringName, count := 1) -> int:
	var f := buyer()
	if f.is_empty() or not is_contraband(item_id):
		return 0
	var took := BaseHub.server_take_from_stash(item_id, count)
	if took <= 0:
		return 0
	var got := offer(item_id, took)
	Economy.add_cash(got, "Sold %d x %s to %s" % [took, ItemDB.get_item(item_id).name, String(f.fixer)])
	Economy.change_reputation(String(f.faction), int(f.get("buy_rep", 1)), "contraband sold to %s" % String(f.fixer))
	return got


## Host: contraband just sold at the base: every lawful faction thinks less of the company.
static func server_sold_at_base(item_id: StringName) -> void:
	if not is_contraband(item_id):
		return
	for fid: String in MissionRegistry.faction_ids():
		if bool(MissionRegistry.faction(fid).get("lawful", false)):
			Economy.change_reputation(fid, LAWFUL_HIT, "contraband sold openly", false)
