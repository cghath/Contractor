class_name BaseEconomy
extends RefCounted
## What the base needs from the economy (wave 4: the economy workstream owns money, prices,
## the shop's transactions and the contract board). Every call goes to the Economy
## autoload when it is there and has the method; until then a stand-in keeps a plain cash
## balance in the "base" section ("stub_funds") so the base works and tests on its own.
##
## The calls the base makes (the economy side should provide these on its autoload):
##   Economy.funds() -> int
##   Economy.try_spend(amount: int, reason: String) -> bool   # false (and nothing spent) if short
##   Economy.credit(amount: int, reason: String) -> void
##   Economy.item_price(id: StringName) -> int                 # the shop's price for one
##   Economy.shop_catalog() -> Array                           # [{"id": String, "price": int}]
##   Economy.pay_wages(amount: int, days: int) -> void         # the roster's wage bill
##   Economy.charge(amount: int, reason: String) -> void       # spent even into debt
##   Economy.request_recovery_contract(info: Dictionary) -> void
##       info: {"mid", "name", "callsign", "role", "zone_id", "day", "pos": [x, y, z]}
##   Economy.respawn_price() -> int                            # a respawn past the free ones
## All host only.

const ECONOMY_PATH := ^"/root/Economy"
## Stand-in values (proposed) until the economy is in.
const STUB_START_FUNDS := 5000
const STUB_RESPAWN_PRICE := 1000
## Stand-in shop prices, by item type, and for a few items by id (per unit).
const STUB_PRICE_BY_TYPE := {"weapon": 1500, "plate": 650, "armor": 700, "backpack": 300, "ammo": 40, "medical": 60,
	"utility": 120, "objective": 0}
const STUB_PRICE_BY_ID := {"rounds_556": 1, "rounds_762": 2, "rounds_9mm": 1, "frag_grenade": 150, "flashbang": 120,
	"smoke_grenade": 60, "helmet": 450, "helmet_bump": 250, "helmet_heavy": 800, "defibrillator": 900, "surgery_kit": 400}


static func _economy(method: StringName) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var node := tree.root.get_node_or_null(ECONOMY_PATH) if tree else null
	return node if node and node.has_method(method) else null


static func _stub() -> Dictionary:
	var base := Campaign.section(&"base")
	if not base.has("stub_funds"):
		base["stub_funds"] = STUB_START_FUNDS
	return base


## Whether the real economy is answering (false: the stand-in).
static func is_stub() -> bool:
	return _economy(&"funds") == null


static func funds() -> int:
	var e := _economy(&"funds")
	return int(e.call(&"funds")) if e else int(_stub().stub_funds)


## Spends `amount` if the company has it. Returns whether it did.
static func try_spend(amount: int, reason: String) -> bool:
	if amount <= 0:
		return true
	var e := _economy(&"try_spend")
	if e:
		return bool(e.call(&"try_spend", amount, reason))
	var base := _stub()
	if int(base.stub_funds) < amount:
		return false
	base["stub_funds"] = int(base.stub_funds) - amount
	_note(reason, -amount)
	return true


static func credit(amount: int, reason: String) -> void:
	var e := _economy(&"credit")
	if e:
		e.call(&"credit", amount, reason)
		return
	var base := _stub()
	base["stub_funds"] = int(base.stub_funds) + amount
	_note(reason, amount)


## The wage bill: always paid, even into debt (the economy decides what debt does).
static func pay_wages(amount: int, days: int) -> void:
	var e := _economy(&"pay_wages")
	if e:
		e.call(&"pay_wages", amount, days)
		return
	charge(amount, "Wages, %d days" % days)


## A cost that goes through even into debt (a respawn the company couldn't afford).
static func charge(amount: int, reason: String) -> void:
	var e := _economy(&"charge")
	if e:
		e.call(&"charge", amount, reason)
		return
	var base := _stub()
	base["stub_funds"] = int(base.stub_funds) - amount
	_note(reason, -amount)


static func item_price(id: StringName) -> int:
	var e := _economy(&"item_price")
	if e:
		return int(e.call(&"item_price", id))
	if STUB_PRICE_BY_ID.has(String(id)):
		return int(STUB_PRICE_BY_ID[String(id)])
	var item := ItemDB.get_item(id)
	return int(STUB_PRICE_BY_TYPE.get(item.type, 100)) if item else 0


## What the shop terminal sells: [{"id", "price"}].
static func shop_catalog() -> Array:
	var e := _economy(&"shop_catalog")
	if e:
		return e.call(&"shop_catalog")
	var out: Array = []
	var all := ItemDB.all_ids()
	all.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for id: StringName in all:
		var price := item_price(id)
		if price > 0:
			out.append({"id": String(id), "price": price})
	return out


static func respawn_price() -> int:
	var e := _economy(&"respawn_price")
	return int(e.call(&"respawn_price")) if e else STUB_RESPAWN_PRICE


## An AI squadmate was left behind alive: ask the contract board for a recovery contract.
## The stand-in lists the request in the "base" section ("recovery_requests").
static func request_recovery_contract(info: Dictionary) -> void:
	var e := _economy(&"request_recovery_contract")
	if e:
		e.call(&"request_recovery_contract", info)
		return
	var base := Campaign.section(&"base")
	var list: Array = base.get("recovery_requests", [])
	list.append(info)
	base["recovery_requests"] = list


static func _note(reason: String, amount: int) -> void:
	var base := Campaign.section(&"base")
	var ledger: Array = base.get("stub_ledger", [])
	ledger.append({"day": int(base.get("day", 1)), "amount": amount, "reason": reason})
	if ledger.size() > 50:
		ledger = ledger.slice(ledger.size() - 50)
	base["stub_ledger"] = ledger
