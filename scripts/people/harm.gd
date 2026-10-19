class_name Harm
extends RefCounted
## Who hurt whom (host only, wave 4, W11). Ballistics and grenade fragments note the attacker
## of every hit that gets through to a body (note_hit), so the people code can tell a civilian
## hit by the players' side, a casualty that counts against the contract, from one hit by
## hostiles, which doesn't (design doc "Missions").
##
## A grenade carries its thrower (Grenade.thrower); while it goes off, blast_source names
## them, so its fragments are noted against whoever threw it.

## Meta on the hurt body: the latest attacker (info_of) with "at" (Soldier._now()).
const META := &"last_harm"

## The thrower of the grenade going off right now (Grenade sets it around the detonation),
## or null.
static var blast_source: Node = null


## Host only. `attacker` hurt `victim` (a body: the Soldier or dummy that owns the Vitals).
## Records it on the victim and tells the people ledger (People.server_harmed), which counts
## civilians hurt by the players' side. A null attacker (a fall, an unknown blast) is noted
## as nobody.
static func note_hit(victim: Node, attacker: Node) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	var info := info_of(attacker)
	info["at"] = Soldier._now()
	victim.set_meta(META, info)
	var hurt := victim as Soldier
	if hurt and hurt.vitals and not hurt.vitals.is_dead():  # a cry when hit, a scream now and then (Callouts.server_vocal)
		var callouts := Callouts.of(hurt)
		if callouts:
			callouts.server_vocal(hurt, &"scream" if randf() < 0.3 or not hurt.vitals.is_up() else &"hit")
	var people := victim.get_node_or_null(^"/root/People")
	if people:
		people.server_harmed(victim, info)


## Who `attacker` is, as the ledger records it: {"name", "faction", "player" (a human),
## "company" (is_company), "peer" (their peer id, 0 for AI), "path"}. Empty name and faction for
## nobody.
static func info_of(attacker: Node) -> Dictionary:
	if attacker == null or not is_instance_valid(attacker):
		return {"name": "", "faction": "", "player": false, "company": false, "peer": 0, "path": ""}
	var s := attacker as Soldier
	if s == null:
		return {"name": String(attacker.name), "faction": "", "player": false, "company": false, "peer": 0, "path": str(attacker.get_path())}
	return {"name": s.display_name(), "faction": String(s.faction), "player": not s.is_ai(), "company": is_company(s),
		"peer": 0 if s.is_ai() else s.owner_peer(), "path": str(s.get_path())}


## Whether `s` is the company's own (Captain, 2026-10-19: "casualties caused by rebels and enemies
## dont affect the company, only ones we injure"): a player, or one of ours in the company's own
## marks (squadmates, company squads, the company's support crews). Allied elements, friendly
## factions' teams and rebels (their own marks: "allied", "rebel") and every enemy are not.
static func is_company(s: Soldier) -> bool:
	return s != null and s.faction == &"friendly" and (not s.is_ai() or s.iff == &"")


## Whether a hit recorded as `info` (info_of) is the company's doing (an older record without
## "company": a player's).
static func by_company(info: Dictionary) -> bool:
	return bool(info.get("company", info.get("player", false)))


## The latest attacker noted on `victim` ({} if none).
static func last(victim: Node) -> Dictionary:
	return victim.get_meta(META, {}) if victim and is_instance_valid(victim) else {}
