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
	var people := victim.get_node_or_null(^"/root/People")
	if people:
		people.server_harmed(victim, info)


## Who `attacker` is, as the ledger records it: {"name", "faction", "player" (a human),
## "peer" (their peer id, 0 for AI), "path"}. Empty name and faction for nobody.
static func info_of(attacker: Node) -> Dictionary:
	if attacker == null or not is_instance_valid(attacker):
		return {"name": "", "faction": "", "player": false, "peer": 0, "path": ""}
	var s := attacker as Soldier
	if s == null:
		return {"name": String(attacker.name), "faction": "", "player": false, "peer": 0, "path": str(attacker.get_path())}
	return {"name": s.display_name(), "faction": String(s.faction), "player": not s.is_ai(),
		"peer": 0 if s.is_ai() else s.owner_peer(), "path": str(s.get_path())}


## The latest attacker noted on `victim` ({} if none).
static func last(victim: Node) -> Dictionary:
	return victim.get_meta(META, {}) if victim and is_instance_valid(victim) else {}
