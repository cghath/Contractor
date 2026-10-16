class_name BaseEconomy
extends RefCounted
## What the base spends and earns, on the one bank: the Economy autoload (wave 4B, seam 1).
## The base's calls keep their names; each goes straight to Economy (cash and the ledger),
## Prices (the shop's prices and the respawn price) or Contracts (a recovery contract). The
## roster's wages are part of Economy's weekly bill (BaseHub sets Economy.wages_provider) and
## the shop's purchases land in the armory stash (Economy.purchase_sink). All host only.


static func funds() -> int:
	return Economy.cash()


## Spends `amount` if the company has it. Returns whether it did.
static func try_spend(amount: int, reason: String) -> bool:
	return amount <= 0 or Economy.spend(amount, reason)


static func credit(amount: int, reason: String) -> void:
	Economy.add_cash(amount, reason)


## A cost that goes through even into debt (a respawn the company couldn't afford).
static func charge(amount: int, reason: String) -> void:
	Economy.charge_run(amount, reason)


## The shop's price for one (0: not sold).
static func item_price(id: StringName) -> int:
	return Prices.price_of(id) if Prices.for_sale(id) else 0


## What the shop terminal sells: [{"id", "price"}].
static func shop_catalog() -> Array:
	var out: Array = []
	for id: StringName in Prices.shop_items():
		var price := item_price(id)
		if price > 0:
			out.append({"id": String(id), "price": price})
	return out


static func respawn_price() -> int:
	return Prices.respawn_price()


## An AI squadmate was left behind alive: a recovery contract goes on the board.
## info: {"mid", "name", "callsign", "role", "zone_id", "day", "pos": [x, y, z]}.
static func request_recovery_contract(info: Dictionary) -> void:
	Contracts.server_add_recovery(info)
