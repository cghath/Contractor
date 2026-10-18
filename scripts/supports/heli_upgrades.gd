class_name HeliUpgrades
extends RefCounted
## The company's air wing upgrades (Captain, 2026-10-17: "the upgrade system for the
## helicopters"; docs/near_future_hardware.md 1.2: the Razorback is a later unlock that carries
## more troops, bought through the existing money path rather than a new unlock system). One-time
## campaign purchases, data/supports.json "upgrades" (an ordered list), owned company-wide in the
## campaign save's economy section ("heli_upgrades": the ids bought), so every peer sees them
## through Economy.state(). Each one is a plain number on a system that already exists:
## - "model" + "kinds": those support calls (HeliCall.kind) fly that airframe instead of
##   HeliSupports.MODEL (the Razorback: transport, extraction and insertion; the rest stay on the
##   Petrel), and a lost one costs "lost_mult" times the usual replacement;
## - "damage_mult": hits on a support helicopter do that much damage (Vehicle.damage_mult);
## - "cooldown_mult": every support's cooldown (HeliSupports.cooldown_s) is that much.
## Bought from the base's Motor pool page (BaseUI._build_air_wing) through Economy.buy_heli_upgrade.
## Outside a campaign (the vehicle range, tests) nothing is owned: the stock air wing flies.

const KEY := "heli_upgrades"


## Every upgrade's entry, in the order the page lists them.
static func defs() -> Array:
	return HeliSupports.data().get("upgrades", [])


## Upgrade `id`'s entry, or {}.
static func def(id: String) -> Dictionary:
	for d: Dictionary in defs():
		if String(d.get("id", "")) == id:
			return d
	return {}


## The ids the company owns (every peer).
static func owned_ids() -> Array:
	return Economy.state().get(KEY, [])


static func owned(id: String) -> bool:
	return owned_ids().has(id)


## Why upgrade `id` can't be bought now ("" if it can): unknown, owned, an upgrade it needs
## ("needs") not owned yet, or the cash short.
static func problem(id: String) -> String:
	var d := def(id)
	if d.is_empty():
		return "No such upgrade"
	if owned(id):
		return "Already owned"
	var needs := String(d.get("needs", ""))
	if needs != "" and not owned(needs):
		return "Needs the %s first" % String(def(needs).get("name", needs))
	if Economy.cash() < int(d.get("cost", 0)):
		return "Can't afford it"
	return ""


## Host: buys upgrade `id` (Economy.server_buy_heli_upgrade does the paying). "" when bought, or why not.
static func server_buy(id: String) -> String:
	return Economy.server_buy_heli_upgrade(id)


## The airframe a support call of `kind` flies: the owned upgrade's "model" whose "kinds" list it,
## else HeliSupports.MODEL.
static func model_for(kind: String) -> String:
	for d: Dictionary in defs():
		if d.has("model") and (d.get("kinds", []) as Array).has(kind) and owned(String(d.id)):
			return String(d.model)
	return HeliSupports.MODEL


## What a lost support helicopter of `kind` costs to replace, times the usual price.
static func lost_mult(kind: String) -> float:
	for d: Dictionary in defs():
		if d.has("model") and (d.get("kinds", []) as Array).has(kind) and owned(String(d.id)):
			return float(d.get("lost_mult", 1.0))
	return 1.0


## Damage a support helicopter takes, times (owned "damage_mult" upgrades multiply).
static func damage_mult() -> float:
	return _product("damage_mult")


## Support cooldowns, times (owned "cooldown_mult" upgrades multiply).
static func cooldown_mult() -> float:
	return _product("cooldown_mult")


static func _product(key: String) -> float:
	var out := 1.0
	for d: Dictionary in defs():
		if d.has(key) and owned(String(d.id)):
			out *= float(d[key])
	return out
