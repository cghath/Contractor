class_name HighCommand
extends Node
## High command (docs/high_command.md, adopted by docs/combined_arms.md section 5): hero-led
## squads beside the player squad, each a Squad of its own with an hc_id.
##
## Phase 0 (C1): the spawn every later phase uses (server_spawn_squad), on which the groundwork
## (G1-G12) is proven. The registry, orders, net and RPCs come with Phase 1 (C2).

const NODE_NAME := "HighCommand"
## A hero squad's men stand this far apart when they spawn.
const SPAWN_SPACING_M := 2.5
## A hero squad of four (high_command.md 8, Phase 1): leader, autorifleman, medic, rifleman.
const TEAM_ROLES: Array[StringName] = [&"team_leader", &"autorifleman", &"medic", &"rifleman"]


## Host: a friendly Squad `def.id` (hc_id) with `def.callsign`, its men spawned round `at` and
## its first man its hero and leader. def: {"id": "hawk2", "callsign": "Hawk 2", "size": 4,
## "members": [{spawn data overrides per man}] (optional), "combat", "discipline"}. Returns the
## Squad, or null off a level that can spawn.
static func server_spawn_squad(level: Node, def: Dictionary, at: Vector3) -> Squad:
	if level == null or not level.has_method(&"spawn_soldier"):
		return null
	var id := StringName(def.get("id", "hc"))
	var sq := Squad.new()
	sq.name = "HC_%s" % String(id)
	sq.faction = &"friendly"
	sq.hc_id = id
	sq.callsign = String(def.get("callsign", String(id).capitalize()))
	level.add_child(sq)
	var members: Array = def.get("members", [])
	var size := int(def.get("size", maxi(members.size(), TEAM_ROLES.size())))
	var across := Vector3.RIGHT
	for i in size:
		var pos: Vector3 = at + across * SPAWN_SPACING_M * (i - (size - 1) / 2.0)
		if level.has_method(&"ground_point"):
			pos = level.call(&"ground_point", pos)
		var data := {"name": "%s_%d" % [String(id).to_upper(), i + 1], "faction": "friendly", "hc_id": String(id),
			"variant": Soldier.COMPANY_VARIANT, "pos": pos, "loadout": [], "role": String(TEAM_ROLES[i % TEAM_ROLES.size()]),
			"team": 0, "slot": -1, "combat": float(def.get("combat", 0.6)), "discipline": float(def.get("discipline", 0.65)),
			"guard": false, "mode": "aware"}
		if i < members.size():
			data.merge(members[i], true)
		var s: Soldier = level.call(&"spawn_soldier", data)
		if s == null:
			continue
		var brain := SquadAI.of(s)
		if brain:
			brain.squad = sq  # G7: on its own squad (_make_soldier already did, by hc_id)
	var men := sq.members()
	if not men.is_empty():
		sq.hero = men[0]
		sq.leader = men[0]
	for i in men.size():  # buddies in pairs
		men[i].buddy = men[i ^ 1] if (i ^ 1) < men.size() else null
	return sq
