class_name Barter
extends RefCounted
## The players' trade with the world's people (docs/survival_world.md section 8, call 26): who
## trades (trader_problem), what a trader has (stock: their own kit, their group's spare supplies
## as items, their group's cash), the deal the barter screen shows (deal: both sides priced by
## WorldTrade.buy_price / sell_price), the swap itself (server_trade: refused when it doesn't
## favour them or come out even; items through the inventories, the group's supplies and cash,
## standing up by WorldSim.server_player_trade, an event) and cheating (server_cheated: a theft
## seen costs standing with the group and with everyone who hears). Static; host for server_*.
##
## Traders (Proposed): a settlement's leader or anyone with the "trader" role; scavengers on the
## road; lone survivors (from their own kit); the enclave's quartermaster (rec "role"
## "quartermaster", or the enclave lane's node answering is_quartermaster(rec)). Raiders and
## cultists don't trade; a group that hates the players (standing <= HOSTILE) won't either.

## Proposed: a group's supply as the item a trader hands over, and how many items one unit is.
const SUPPLY_ITEM := {"food": "canned_meat", "water": "water_bottle", "fuel": "jerrycan", "ammo": "rounds_9mm", "meds": "pressure_bandage",
	"scrap": "scrap_sheet", "wood": "planks"}
const ITEMS_PER := {"food": 2.0, "water": 2.0, "fuel": 1.0, "ammo": 10.0, "meds": 2.0, "scrap": 1.0, "wood": 2.0}
## Proposed: at most this many of each supply item on offer at once.
const STOCK_CAP := 8
## Proposed: a group's cash before it has traded (dollars, by kind).
const CASH_START := {"settlers": 400.0, "scavengers": 600.0, "enclave": 3000.0, "raiders": 200.0, "cultists": 0.0, "lone": 0.0}
## Proposed: a group that's this far down on the players won't trade.
const HOSTILE := -40.0
## Proposed: what cheating costs: with the cheated group, and with each group that hears.
const CHEAT_RELATION := -30.0
const CHEAT_HEARD := -10.0
## Proposed: a lone survivor's opinion of you after a fair trade.
const TRADE_OPINION := 3.0


# --- Who trades ----------------------------------------------------------------------------------

## The group `rec` speaks for (Rumours.group_of: their world group, else their group of one).
static func group_of(rec: Dictionary) -> Dictionary:
	return Rumours.group_of(WorldSim.section(), rec, String(rec.get("id", "")))


## Why `rec` won't trade with the players ("" they will).
static func trader_problem(rec: Dictionary) -> String:
	if rec.is_empty() or String(rec.get("status", "")) in ["dead", "captive", "companion", "settler", "player"]:
		return "They've nothing to trade with you"
	var g := group_of(rec)
	var kind := String(g.get("kind", "lone"))
	if kind in ["raiders", "cultists"]:
		return "They won't trade"
	if not g.is_empty() and WorldTrade.relation_of(g) <= HOSTILE:
		return "They won't deal with you"
	if rec.has("min_standing") and not g.is_empty() and WorldTrade.relation_of(g) < float(rec.min_standing):
		return "They only deal with friends of the enclave"  # (a live enclave convoy: FallenConvoy)
	match kind:
		"settlers":
			if String(g.get("leader", "")) == String(rec.get("id", "")) or String(rec.get("role", "")) == "trader":
				return ""
			var leader: Dictionary = WorldSim.people().get(String(g.get("leader", "")), {})
			return "Talk to %s: they do the trading" % String(leader.get("first", leader.get("name", "their leader")))
		"enclave":
			var enc := Survival.get_node_or_null(^"Enclave")
			if enc and enc.has_method(&"is_quartermaster"):
				return "" if bool(enc.call(&"is_quartermaster", rec)) else "Talk to the quartermaster"
			return "" if String(rec.get("role", "")) == "quartermaster" else "Talk to the quartermaster"
	return ""


static func is_trader(rec: Dictionary) -> bool:
	return trader_problem(rec) == ""


# --- What's on the table ---------------------------------------------------------------------------

## A group's cash (dollars).
static func cash_of(g: Dictionary) -> float:
	return float(g.get("cash", CASH_START.get(String(g.get("kind", "lone")), 0.0)))


## What `rec`'s side offers: [{"id", "count", "src"}], src "kit" (their own), a supply key (the
## group's spare), "cash" (the group's).
static func stock(rec: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	for e: Dictionary in rec.get("kit", []):
		var id := String(e.get("id", ""))
		if id == "" or not ItemDB.has_item(StringName(id)):
			continue
		if seen.has(id):
			var known: Dictionary = seen[id]
			known.count = int(known.count) + int(e.get("count", 1))
			continue
		var row := {"id": id, "count": int(e.get("count", 1)), "src": "kit"}
		seen[id] = row
		out.append(row)
	var g := group_of(rec)
	if g.is_empty():
		return out
	if String(g.get("kind", "")) != "lone":
		var spare := WorldTrade.surplus(g)
		for key: String in WorldGroup.SUPPLY_KEYS:
			var id := String(SUPPLY_ITEM.get(key, ""))
			var n := mini(STOCK_CAP, floori(float(spare.get(key, 0.0)) * float(ITEMS_PER.get(key, 1.0))))
			if n > 0 and id != "" and ItemDB.has_item(StringName(id)) and not seen.has(id):
				out.append({"id": id, "count": n, "src": key})
	var cash := cash_of(g)
	for id: String in ["cash_bundle", "cash_roll"]:
		var face := float(SurvivorPerson.CASH_VALUE[id])
		var n := floori(cash / face)
		if n > 0 and ItemDB.has_item(StringName(id)):
			out.append({"id": id, "count": n, "src": "cash"})
			cash -= n * face
	return out


## What `actor` can offer: his stowed items, [{"id", "count"}] by id.
static func goods_of(actor: Soldier) -> Array:
	var out: Array = []
	var seen := {}
	for c: StringName in actor.inventory.search_containers():
		for e: Dictionary in actor.inventory.containers.get(c, []):
			var id := String(e.id)
			if seen.has(id):
				var known: Dictionary = seen[id]
				known.count = int(known.count) + int(e.get("count", 1))
				continue
			var row := {"id": id, "count": int(e.get("count", 1))}
			seen[id] = row
			out.append(row)
	return out


static func _name(id: String) -> String:
	var item := ItemDB.get_item(StringName(id))
	return item.name if item else id


## The barter screen's deal between `actor` and the trader `rec`: {"trader", "name", "group",
## "group_name", "why" (trader_problem), "theirs": [{"id", "name", "count", "price"}], "yours":
## [...]} with prices per one (theirs at sell_price, yours at buy_price).
static func deal(actor: Soldier, rec: Dictionary) -> Dictionary:
	var g := group_of(rec)
	var region := WorldSim.region_of(String(Survival.state().get("zone", ""))) if WorldSim.is_set_up() else ""
	var theirs: Array = []
	for row: Dictionary in stock(rec):
		theirs.append({"id": String(row.id), "name": _name(String(row.id)), "count": int(row.count), "price": WorldTrade.sell_price(g, String(row.id), region)})
	var yours: Array = []
	if actor:
		for row: Dictionary in goods_of(actor):
			yours.append({"id": String(row.id), "name": _name(String(row.id)), "count": int(row.count), "price": WorldTrade.buy_price(g, String(row.id), region)})
	return {"trader": String(rec.get("id", "")), "name": String(rec.get("name", "")), "group": String(g.get("id", "")),
		"group_name": String(g.get("name", "")), "why": trader_problem(rec), "theirs": theirs, "yours": yours}


## The balance of an offer on `deal`: what you give (at their buying price) less what you take (at
## their selling price). >= 0: they'll take it.
static func balance(d: Dictionary, give: Dictionary, take: Dictionary) -> float:
	var v := 0.0
	for row: Dictionary in d.get("yours", []):
		v += float(row.price) * int(give.get(String(row.id), 0))
	for row: Dictionary in d.get("theirs", []):
		v -= float(row.price) * int(take.get(String(row.id), 0))
	return v


# --- The swap (host) -------------------------------------------------------------------------------

## Host: `actor` gives `give` ({item id: n}) for `take` ({item id: n}) of the trader `rec`'s.
## Refused ("why") when they won't trade, the goods aren't there, or it doesn't favour them or come
## out even ("unfair"). Else the items move (yours into their group's supplies, cash or their kit;
## theirs into your inventory, the rest at your feet), their standing goes up
## (WorldSim.server_player_trade), an event and a journal line. {"ok", "why", "value", "said"}.
static func server_trade(actor: Soldier, rec: Dictionary, give: Dictionary, take: Dictionary) -> Dictionary:
	var why := trader_problem(rec)
	if why != "":
		return {"ok": false, "why": why, "value": 0.0, "said": why + "."}
	var d := deal(actor, rec)
	var have := {}
	for row: Dictionary in d.yours:
		have[String(row.id)] = int(row.count)
	var stocked := {}
	var src := {}
	for row: Dictionary in stock(rec):
		stocked[String(row.id)] = int(row.count)
		src[String(row.id)] = String(row.src)
	var n_items := 0
	for id: String in give:
		if int(give[id]) < 0 or int(give[id]) > int(have.get(id, 0)):
			return {"ok": false, "why": "missing", "value": 0.0, "said": "You don't have that."}
		n_items += int(give[id])
	for id: String in take:
		if int(take[id]) < 0 or int(take[id]) > int(stocked.get(id, 0)):
			return {"ok": false, "why": "missing", "value": 0.0, "said": "I don't have that much."}
		n_items += int(take[id])
	if n_items == 0:
		return {"ok": false, "why": "nothing", "value": 0.0, "said": ""}
	var bal := balance(d, give, take)
	if bal < -0.01:
		var line := TalkMenu.line_for(rec, "trade_unfair")
		return {"ok": false, "why": "unfair", "value": bal, "said": line if line != "" else "That's not a fair trade."}
	var give_v := balance(d, give, {})
	var gid := String(d.group)
	var profile := Survival.profile_of(actor)
	# Yours to them.
	var to_group := {}  # supply key -> units
	var cash_in := 0.0
	for id: String in give:
		for i in int(give[id]):
			if not actor.inventory.remove_one(StringName(id)):
				break
			if WorldTrade.is_cash(id):
				cash_in += float(SurvivorPerson.CASH_VALUE[id])
				continue
			var key := String(WorldTrade.CAT_SUPPLY.get(Settlement.category_of(id), ""))
			if key != "" and not gid.begins_with("lone_") and gid != "":
				to_group[key] = float(to_group.get(key, 0.0)) + 1.0 / float(ITEMS_PER.get(key, 1.0))
			else:
				TalkMenu._to_kit(rec, id, {})
	# Theirs to you.
	var cash_out := 0.0
	var level := CompoundLevel.current(actor)
	for id: String in take:
		var n := int(take[id])
		if n <= 0:
			continue
		match String(src.get(id, "kit")):
			"kit":
				_take_from_kit(rec, id, n)
			"cash":
				cash_out += float(SurvivorPerson.CASH_VALUE[id]) * n
			_:
				var key := String(src[id])
				to_group[key] = float(to_group.get(key, 0.0)) - float(n) / float(ITEMS_PER.get(key, 1.0))
		var got := actor.inventory.take(StringName(id), n)
		if got < n and level:
			level.server_spawn_dropped(StringName(id), n - got, actor.global_position + Vector3.UP * 0.4)
	if gid != "" and (not to_group.is_empty() or cash_in != cash_out):
		var start := cash_of(WorldSim.group(gid))
		var apply := func(w: Dictionary) -> void:
			var g: Dictionary = (w.get("groups", {}) as Dictionary).get(gid, {})
			if g.is_empty():
				return
			for key: String in to_group:
				WorldGroup.add_supply(g, key, float(to_group[key]))
			g["cash"] = maxf(0.0, start + cash_in - cash_out)
		var sim := WorldSim.get_sim()
		if sim:
			sim.mutate(apply)
		else:
			apply.call(WorldSim.section())
	var sim2 := WorldSim.get_sim()
	if sim2 and gid != "":
		sim2.server_player_trade(gid, give_v)
	SurvivorPerson.change_opinion(rec, profile, TRADE_OPINION)
	var zone := String(Survival.state().get("zone", rec.get("zone", "")))
	var who := String(d.group_name) if String(d.group_name) != "" else String(rec.get("name", "a survivor"))
	if gid != "":
		Intel.server_event(zone, "trade", [gid, "player"], "%s traded with the farm's people ($%d of goods)" % [who, roundi(give_v)])
	Intel.journal("Traded with %s: gave %s; got %s." % [String(rec.get("name", who)), _list(give), _list(take)], "trade", String(rec.get("name", "")))
	var said := TalkMenu.line_for(rec, "trade_done")
	return {"ok": true, "why": "", "value": give_v, "said": said}


static func _take_from_kit(rec: Dictionary, id: String, n: int) -> void:
	var kit: Array = rec.get("kit", [])
	var i := kit.size() - 1
	while i >= 0 and n > 0:
		var e: Dictionary = kit[i]
		if String(e.get("id", "")) == id:
			var c := int(e.get("count", 1))
			var took := mini(c, n)
			n -= took
			if c - took <= 0:
				kit.remove_at(i)
			else:
				e.count = c - took
		i -= 1


static func _list(items: Dictionary) -> String:
	var parts := PackedStringArray()
	for id: String in items:
		if int(items[id]) > 0:
			parts.append("%d %s" % [int(items[id]), _name(id)])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


# --- Cheating (call 26: "costs relations with everyone who hears") -------------------------------

## Host: the players cheated `gid` (a theft seen, a deal gone back on): their standing with it drops
## CHEAT_RELATION, and every group that hears (in its zone or the next, or that knows of it) drops
## CHEAT_HEARD; an event in the pool (the rumour layer spreads it). Returns the ids that heard.
## The loot and steal actions call this when a theft is seen (no steal action yet: the hook).
static func server_cheated(gid: String, zone_id := "") -> Array:
	var g := WorldSim.group(gid)
	if g.is_empty():
		return []
	var zone := zone_id if zone_id != "" else String(g.get("zone", ""))
	var zones: Dictionary = WorldSim.section().get("zones", {})
	var near: Array = [zone]
	near.append_array((zones.get(zone, {}) as Dictionary).get("links", []))
	var heard: Array = []
	for other: Dictionary in (WorldSim.section().get("groups", {}) as Dictionary).values():
		if String(other.id) == gid or not bool(other.get("alive", true)) or String(other.kind) == "lone":
			continue
		if String(other.zone) in near or (other.get("knows", {}) as Dictionary).has(gid):
			heard.append(String(other.id))
	var sim := WorldSim.get_sim()
	if sim:
		sim.server_change_relation(gid, CHEAT_RELATION, "cheated")
		for h: String in heard:
			sim.server_change_relation(h, CHEAT_HEARD, "heard the farm cheats")
	else:
		WorldGroup.change_relation(g, "player", CHEAT_RELATION)
		for h: String in heard:
			WorldGroup.change_relation(WorldSim.group(h), "player", CHEAT_HEARD)
	Intel.server_event(zone, "cheated", [gid, "player"], "the farm's people cheated %s" % String(g.get("name", "a trader")))
	Intel.journal("Word will get round that we cheated %s." % String(g.get("name", "them")), "trade")
	return heard
