class_name AlliedTroops
extends Node
## Wave 6e: allied troops (design doc "mission_brainstorm.md"; wave6_groundwork.md calls #2/#3,
## Proposed answers). A friendly rifle element the squad can call in through the support menu
## but not command in detail: "move to", "hold" and "assault" only ("support:allied_move/
## allied_hold/allied_assault"), the same seam as the AAV and heli supports (Supports.register,
## "support:<name>" from the command menu's Support entry). It fights as its own group, on the
## squad AI the player's own squad already uses (its own Squad instance, faction "friendly":
## Squad.members()/brains() are scoped to SquadAI.squad == self, so this never answers for the
## player's own squad or vice versa).
##
## One at a time (Proposed), drawn from the support budget like the helis
## (Economy.server_pay_support), COOLDOWN_S after it's released or lost, and only once the
## squad has Trusted standing or better with at least one of the deployment's employers (the
## tier unlock table's "one element per deployment"; a second, Allied-tier element and the
## MRAP-mounted section are not in this slice).
##
## Host authoritative (the soldiers it spawns replicate like any AI, Squad and SquadAI do the
## fighting and the ordered moves). One node, "AlliedTroops", in every level (install(),
## CompoundLevel._ready).

const NODE_NAME := "AlliedTroops"
const PRICE_KIND := "allied_troops"
## 20 minutes (Proposed, wave6_groundwork.md call #3).
const COOLDOWN_S := 1200.0
const SIZE := 8
## A basic rifleman's kit (ground_supports.json's AAV crew loadout, the established minimal
## friendly kit): plates, helmet, an M4, two spare mags, a medical pouch.
const LOADOUT := ["plate_carrier", "plate_ceramic_l4", "plate_ceramic_l4", "helmet", "m4a1", "mag_556", "mag_556", "mag_556", "ifak"]
## The tier (factions.json "reputation_tiers" id) the squad needs with at least one of the
## deployment's employers before an element is available at all.
const MIN_TIER_ID := "trusted"
const SPACING_M := 2.5
const COMBAT := 0.6
const DISCIPLINE := 0.65

## The element out now (host; clients resolve it by name: current()). null with none out.
var squad: Squad
## Host: who called it, and how many times this op.
var caller: Soldier
var calls := 0
## Host: when it was last released or lost (Soldier._now(), engine uptime); COOLDOWN_S must
## pass before another. -INF (never yet) rather than a large negative number: COOLDOWN_S is
## 20 minutes, long enough that engine-uptime-since-launch alone could still be under it.
var released_at := -INF
## Host: the last thing it told its caller (tests, the session log).
var last_message := ""


## Every peer, from the level's _ready: this node and its support commands, once.
static func install(level: Node3D) -> void:
	if level.get_node_or_null(NODE_NAME) != null:
		return
	var n := AlliedTroops.new()
	n.name = NODE_NAME
	level.add_child(n)
	Supports.register("allied_call", n._cmd_call)
	Supports.register("allied_move", n._cmd_move)
	Supports.register("allied_hold", n._cmd_hold)
	Supports.register("allied_assault", n._cmd_assault)
	Supports.register("allied_release", n._cmd_release)


static func current(from: Node) -> AlliedTroops:
	var level := CompoundLevel.current(from)
	return level.get_node_or_null(NODE_NAME) as AlliedTroops if level else null


func _cmd_call(who: Node, _arg: String, _point: Vector3, _names: PackedStringArray) -> String:
	return server_call(who as Soldier)


func _cmd_move(who: Node, _arg: String, point: Vector3, _names: PackedStringArray) -> String:
	return server_move(who as Soldier, point)


func _cmd_hold(who: Node, _arg: String, _point: Vector3, _names: PackedStringArray) -> String:
	return server_hold(who as Soldier)


func _cmd_assault(who: Node, _arg: String, point: Vector3, _names: PackedStringArray) -> String:
	return server_assault(who as Soldier, point)


func _cmd_release(who: Node, _arg: String, _point: Vector3, _names: PackedStringArray) -> String:
	return server_release(who as Soldier)


## Whether an element is out and at least one of it is still up (a wiped element stops
## counting at once: the next call only waits out the cooldown, not a corpse on the map).
func is_out() -> bool:
	if squad == null or not is_instance_valid(squad):
		return false
	for s: Soldier in squad.members():
		if s.vitals.is_up():
			return true
	return false


## Why an element can't be called right now, or "" when it can.
func _call_problem() -> String:
	if is_out():
		return "The element is already out"
	if Soldier._now() - released_at < COOLDOWN_S:
		return "No element available for %d more minutes" % ceili((COOLDOWN_S - (Soldier._now() - released_at)) / 60.0)
	if not _standing_high_enough():
		return "No ally trusts us enough yet to lend us one"
	return ""


## Trusted standing (MIN_TIER_ID) or better with at least one of the deployment's employers.
func _standing_high_enough() -> bool:
	var want := -1
	for t: Dictionary in MissionRegistry.reputation_tiers():
		want += 1
		if String(t.id) == MIN_TIER_ID:
			break
	var cids: Array = Contracts.deployment().get("cids", [])
	for c: Dictionary in Contracts.held():
		if String(c.get("cid", "")) in cids and MissionRegistry.tier_index(Economy.reputation(String(c.get("employer", "")))) >= want:
			return true
	return false


## Host: `by` calls an element in. `dev`: free and ignores standing/cooldown (dev tools, tests).
## Returns "" when it's on its way, else why not.
func server_call(by: Soldier, dev := false) -> String:
	if not multiplayer.is_server() or by == null:
		return ""
	if not dev:
		var why := _call_problem()
		if why != "":
			return why
	var level := CompoundLevel.current(self)
	if level == null:
		return "No ally nearby"
	if not dev and not Economy.server_pay_support(PRICE_KIND, _contract_id()):
		return "Can't afford an allied element ($%s)" % DebriefCalc.money(Prices.support_price(PRICE_KIND))
	var origin := Supports.origin_for(level, &"allied", by.global_position, 1.0)  # on foot: ground level, not a helicopter's altitude
	var at := origin.origin
	var across := origin.basis.x
	squad = Squad.new()
	squad.name = "AlliedSquad"
	squad.faction = &"friendly"
	level.add_child(squad)
	for i in SIZE:
		var pos: Vector3 = level.call(&"ground_point", at + across * SPACING_M * (i - (SIZE - 1) / 2.0))
		var s: Soldier = level.call(&"spawn_soldier", {"name": "Ally_%d" % (i + 1), "faction": "friendly", "variant": "multicam",
			"pos": pos, "loadout": LOADOUT.duplicate(), "combat": COMBAT, "discipline": DISCIPLINE, "guard": false, "mode": "aware"})
		if s == null:
			continue
		var brain := SquadAI.of(s)
		if brain:
			brain.squad = squad
	caller = by
	calls += 1
	squad.give_order(by, Squad.Order.MOVE, by.global_position)
	last_message = "Allied element inbound, %d men" % squad.members().size()
	print("[allied] %s calls in an element (%d men) at (%.0f, %.0f)%s" % [by.name, squad.members().size(), at.x, at.z, " (dev)" if dev else ""])
	return ""


## Host: the element moves to `point` and holds there (SquadAI._choose_intent: an arrived Move
## becomes a real Hold, so it stays put once it's there - the same fix the friendly squad's own
## Move/Hold orders got).
func server_move(by: Soldier, point: Vector3) -> String:
	var why := _commandable(by)
	if why != "":
		return why
	squad.give_order(by, Squad.Order.MOVE, point)
	return ""


## Host: the element holds and fights from where it stands now.
func server_hold(by: Soldier) -> String:
	var why := _commandable(by)
	if why != "":
		return why
	squad.give_order(by, Squad.Order.HOLD, by.global_position)
	return ""


## Host: the element assaults the enemy at `point` (Vector3.INF: the densest known cluster),
## the same drill the player's own squad's Attack > Assault uses (Squad.order_assault).
func server_assault(by: Soldier, point: Vector3) -> String:
	var why := _commandable(by)
	if why != "":
		return why
	return squad.order_assault(by, point)


## Host: sends the element home (freed, not left standing about) and starts its cooldown.
func server_release(by: Soldier) -> String:
	if not multiplayer.is_server() or by == null:
		return ""
	if squad == null or not is_instance_valid(squad):
		return "No element out"
	for s: Soldier in squad.members():
		s.queue_free()
	squad.queue_free()
	squad = null
	released_at = Soldier._now()
	last_message = "Allied element released"
	return ""


## Why `by` can't give the element an order right now, or "" when it can.
func _commandable(by: Soldier) -> String:
	if not multiplayer.is_server() or by == null:
		return "no"
	if not is_out():
		return "No element out"
	return ""


static func _contract_id() -> String:
	var cids: Array = Contracts.deployment().get("cids", [])
	return String(cids[0]) if not cids.is_empty() else ""


## Host: the element's own death (every member down) starts the cooldown the same as a release.
## Cheap (is_out() is at most SIZE lookups) and only does anything once, right after squad is
## cleared to null.
func _process(_delta: float) -> void:
	if multiplayer.is_server() and squad != null and is_instance_valid(squad) and not is_out():
		released_at = Soldier._now()
		squad.queue_free()
		squad = null
