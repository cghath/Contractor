class_name AlliedTroops
extends Node
## Wave 6e: allied troops (design doc "mission_brainstorm.md"; wave6_groundwork.md calls #1-#3).
## Friendly elements the squad calls in through the support menu ("support:allied_call:<kind>")
## and the host commands as a high command (Captain, 2026-10-18: "for the host/1st player to be
## able to order these squads to do general things, and map orders"): general orders from the
## support menu, aimed at every element ("all"), and map orders from the map's right-click menu
## aimed at one ("support:allied_<order>:<element id>"). Each element fights as its own group on
## the squad AI the player's own squad already uses (its own Squad instance, faction "friendly":
## Squad.members()/brains() are scoped to SquadAI.squad == self, so no element answers for the
## player's squad, another element, or the other way round).
##
## Element kinds (KINDS): an 8-man rifle squad, and a 4-man weapons team (an M240B, its ammo
## bearer and two AT4s), each in the kit of the deployment employer that vouches for it
## (factions.json allied kits: US M4s, UK L85A2s, Canadian C8s; Kits "mixes" for the team).
## How many can be out at once goes by the best standing with a deployment employer
## (MAX_BY_TIER: Trusted one, Allied two, call #1); each slot has its own COOLDOWN_S after its
## element is released or lost (call #3). Paid from the support budget like the helis.
## The MRAP-mounted section isn't in this slice.
##
## Host authoritative: the soldiers replicate like any AI, Squad and SquadAI do the fighting.
## Every peer keeps `shown` (the host's summary of what's out, re-sent on change and every
## SHOW_EVERY_S) so the map can draw and label the elements and offer their orders. One node,
## "AlliedTroops", in every level (install(), CompoundLevel._ready).

const NODE_NAME := "AlliedTroops"
const PRICE_KIND := "allied_troops"
## 20 minutes (Proposed, wave6_groundwork.md call #3), per slot.
const COOLDOWN_S := 1200.0
## Element kinds: size, the kit mix (Kits.mix; "" = the kit's own), and what it's called.
const KINDS := {
	"rifle": {"size": 8, "mix": "", "label": "rifle squad"},
	"weapons": {"size": 4, "mix": "weapons_team", "label": "weapons team"},
}
## The rifle squad's size (the element the MVP had).
const SIZE := 8
## Elements out at once, by the best standing tier (factions.json "reputation_tiers" id) with a
## deployment employer; a tier not listed lends none.
const MAX_BY_TIER := {"trusted": 1, "allied": 2}
const MAX_ELEMENTS := 2
## An employer whose own troops these can't be (Meridian, a company) lends the US kit.
const DEFAULT_KIT := "allied_us"
const SPACING_M := 2.5
## The high command's orders (server_order()).
const ORDERS := ["move", "hold", "defend", "assault", "flank", "follow", "regroup", "fall_back", "mount", "drive", "dismount"]
## How often the host re-sends `shown` with fresh order points for the map, in seconds.
const SHOW_EVERY_S := 2.0

## Host: what's out, by slot: {"id": slot + 1, "kind", "squad": Squad, "kit", "employer",
## "order", "point": Vector3}. null for an empty slot.
var elements: Array = []
## Host: when each slot's element was last released or lost (Soldier._now(), engine uptime);
## COOLDOWN_S must pass before that slot lends another. -INF: never yet (COOLDOWN_S is long
## enough that uptime-since-launch alone could still be under it).
var released_at: Array[float] = []
var caller: Soldier
var calls := 0
## Host: the last thing it told its caller (tests, the session log).
var last_message := ""
## Every peer: what's out, from the host: [{"id", "kind", "label", "order", "point": Vector2
## (INF for none), "names": PackedStringArray, "employer"}].
var shown: Array = []
var _show_left := 0.0

## The first element's squad (null with none out): the MVP's single-element view.
var squad: Squad:
	get:
		for e: Variant in elements:
			if e != null and _alive(e):
				return e.squad
		return null


func _init() -> void:
	elements.resize(MAX_ELEMENTS)
	for i in MAX_ELEMENTS:
		released_at.append(-INF)


## Every peer, from the level's _ready: this node and its support commands, once.
static func install(level: Node3D) -> void:
	if level.get_node_or_null(NODE_NAME) != null:
		return
	var n := AlliedTroops.new()
	n.name = NODE_NAME
	level.add_child(n)
	Supports.register("allied_call", n._cmd_call)
	Supports.register("allied_release", n._cmd_release)
	for order: String in ORDERS:
		Supports.register("allied_" + order, n._cmd_order.bind(order))


static func current(from: Node) -> AlliedTroops:
	var level := CompoundLevel.current(from)
	return level.get_node_or_null(NODE_NAME) as AlliedTroops if level else null


func _cmd_call(who: Node, arg: String, _point: Vector3, _names: PackedStringArray) -> String:
	if arg == "company":
		return server_call(who as Soldier, false, "rifle", true)
	return server_call(who as Soldier, false, arg if arg != "" else "rifle")


func _cmd_release(who: Node, arg: String, _point: Vector3, _names: PackedStringArray) -> String:
	return server_release(who as Soldier, arg)


func _cmd_order(who: Node, arg: String, point: Vector3, _names: PackedStringArray, order: String) -> String:
	return server_order(who as Soldier, order, point, arg)


## Whether any element is out and at least one of it is still up.
func is_out() -> bool:
	return not out().is_empty()


## Host (BaseHub, the squad crossing on): the elements out follow it (call 19: they're within a
## link); each one's kind, whether it's the company's, and how many are still up.
func server_take_followers() -> Array:
	var out_now: Array = []
	for e: Dictionary in out():
		var up := (e.squad as Squad).members().filter(func(s: Soldier) -> bool: return s.vitals.is_up()).size()
		out_now.append({"kind": String(e.kind), "company": bool(e.get("company", false)), "up": up})
	return out_now


## Host, the squad's new zone: elements that followed come in at `at` (where the squad arrived),
## free, as many as were still up, following `by`.
func server_follow_in(followers: Array, by: Soldier, at: Vector3) -> void:
	for f: Dictionary in followers:
		var before := out().size()
		if server_call(by, true, String(f.kind), bool(f.company), at) != "" or out().size() == before:
			continue
		var e: Dictionary = out().back()
		var members := (e.squad as Squad).members()
		for i in range(int(f.up), members.size()):
			(members[i] as Soldier).queue_free()  # (only those still up came along)
		(e.squad as Squad).give_order(by, Squad.Order.FOLLOW, by.global_position)
		e["order"] = "follow"
		last_message = "Element %d followed you over" % int(e.id)


## The elements out now (host), lowest id first.
func out() -> Array:
	return elements.filter(func(e: Variant) -> bool: return e != null and _alive(e))


## Whether an element still has someone up (a wiped element stops counting at once).
static func _alive(e: Dictionary) -> bool:
	var sq: Squad = e.squad
	if sq == null or not is_instance_valid(sq):
		return false
	for s: Soldier in sq.members():
		if s.vitals.is_up():
			return true
	return false


## The best standing with one of the deployment's employers: {"tier", "tier_id", "employer"}.
func _best_standing() -> Dictionary:
	var best := {"tier": -1, "tier_id": "", "employer": ""}
	var cids: Array = Contracts.deployment().get("cids", [])
	for c: Dictionary in Contracts.held():
		if not String(c.get("cid", "")) in cids:
			continue
		var employer := String(c.get("employer", ""))
		var rep := Economy.reputation(employer)
		if MissionRegistry.tier_index(rep) > int(best.tier):
			best = {"tier": MissionRegistry.tier_index(rep), "tier_id": MissionRegistry.tier_id(rep), "employer": employer}
	return best


## How many elements the squad's standing lends at once (MAX_BY_TIER).
func max_out() -> int:
	return int(MAX_BY_TIER.get(String(_best_standing().tier_id), 0))


## The first slot below `limit` that's empty and off cooldown, or -1.
func _free_slot(limit: int) -> int:
	for i in mini(limit, MAX_ELEMENTS):
		if (elements[i] == null or not _alive(elements[i])) and Soldier._now() - released_at[i] >= COOLDOWN_S:
			return i
	return -1


## Why an element can't be called right now, or "" when it can.
func _call_problem() -> String:
	var limit := max_out()
	if limit <= 0:
		return "No ally trusts us enough yet to lend us one"
	if out().size() >= limit:
		return "Every element our standing allows is out (%d)" % limit
	if _free_slot(limit) < 0:
		var wait := INF
		for i in mini(limit, MAX_ELEMENTS):
			wait = minf(wait, COOLDOWN_S - (Soldier._now() - released_at[i]))
		return "No element available for %d more minutes" % ceili(wait / 60.0)
	return ""


## The kit an element lent by `employer` wears: that employer's own (an allied kit), else the US.
static func kit_for(employer: String) -> String:
	var kit := Kits.kit_of(employer, "none")
	return kit if String(Kits.data(kit).get("side", "")) == "friendly" else DEFAULT_KIT


## Host: `by` calls in an element of `kind` (KINDS). `dev`: free, ignores standing/cooldown and
## takes any empty slot (dev tools, tests). Returns "" when it's on its way, else why not.
## `company` (docs/linked_zones.md 1b / LZ-6, "hired player-faction squads you command"): one of
## the company's own hired squads (BaseHub.company_squads), in its own kit and marks, paid by its
## wages (no call price, no standing needed), under the same high command.
##
## `at_point` (a Vector3): they come in there instead of from the support origin (following the
## squad across a crossing, BaseHub: they arrive where it did).
##
## `rebel` (RebelCalls: the locals' fighters): free, in local kit (AKs, the woodland look) and
## the rebels' own marks ("rebel": never the company's for its casualties, Harm.is_company).
func server_call(by: Soldier, dev := false, kind := "rifle", company := false, at_point: Variant = null, rebel := false) -> String:
	if not multiplayer.is_server() or by == null:
		return ""
	if not KINDS.has(kind):
		return "No such element"
	var slot := -1
	if company:
		var hired := BaseHub.company_squads()
		var out_now := out().filter(func(e: Dictionary) -> bool: return e.get("company", false)).size()
		if hired <= 0:
			return "The company has no squads of its own yet (hire them at the ops desk)"
		if out_now >= hired:
			return "Every company squad is out (%d)" % hired
		for i in MAX_ELEMENTS:
			if elements[i] == null or not _alive(elements[i]):
				slot = i
				break
		if slot < 0:
			return "Every element is out"
	elif dev:
		for i in MAX_ELEMENTS:
			if elements[i] == null or not _alive(elements[i]):
				slot = i
				break
		if slot < 0:
			return "Every element is out"
	else:
		var why := _call_problem()
		if why != "":
			return why
		slot = _free_slot(max_out())
	var level := CompoundLevel.current(self)
	if level == null:
		return "No ally nearby"
	if not dev and not company and not Economy.server_pay_support(PRICE_KIND, _contract_id()):
		return "Can't afford an allied element ($%s)" % DebriefCalc.money(Prices.support_price(PRICE_KIND))
	if elements[slot] != null:
		_drop(slot, false)  # a wiped element still on the books
	var employer := String(_best_standing().employer)
	var kit := kit_for(employer) if not company else DEFAULT_KIT
	var spec: Dictionary = KINDS[kind]
	var size := int(spec.size)
	var k := Kits.data(kit)
	var origin := Supports.origin_for(level, &"allied", by.global_position, 1.0)  # on foot: ground level, not a helicopter's altitude
	if at_point is Vector3:
		origin = Transform3D(Basis.IDENTITY, at_point)
	var at := origin.origin
	var across := origin.basis.x
	var sq := Squad.new()
	sq.name = "AlliedSquad%d" % (slot + 1)
	sq.faction = &"friendly"
	level.add_child(sq)
	for i in size:
		var pos: Vector3 = level.call(&"ground_point", at + across * SPACING_M * (i - (size - 1) / 2.0))
		var s: Soldier = level.call(&"spawn_soldier", {"name": "A%d_%d" % [slot + 1, i + 1], "faction": "friendly", "iff": "rebel" if rebel else ("" if company else "allied"),
			"variant": "woodland" if rebel else ("tan" if company else Kits.variant(kit)),
			"pos": pos, "loadout": CompoundLevel.hostile_loadout(i) if rebel else Kits.loadout(kit, i, 1, String(spec.mix)), "role": Kits.role(kit, i, String(spec.mix)),
			"combat": float(k.get("combat", 0.6)), "discipline": float(k.get("discipline", 0.65)), "guard": false, "mode": "aware"})
		if s == null:
			continue
		var brain := SquadAI.of(s)
		if brain:
			brain.squad = sq
	var members := sq.members()
	if kind == "weapons" and not rebel and members.size() >= 2:
		StaticWeapons.arm_gun_team(level, members[0], members[1], "tripod_m2", sq)  # the weapons team brings an M2 (G-25)
	elements[slot] = {"id": slot + 1, "kind": kind, "squad": sq, "kit": kit, "employer": "rebels" if rebel else ("company" if company else employer), "order": "move",
		"point": by.global_position, "company": company}
	caller = by
	calls += 1
	sq.give_order(by, Squad.Order.MOVE, by.global_position)
	last_message = "%s %s inbound (element %d, %d men)" % ["Company" if company else "Allied", spec.label, slot + 1, sq.members().size()]
	print("[allied] %s calls in element %d, a %s (%d men, %s) at (%.0f, %.0f)%s" % [by.name, slot + 1, spec.label, sq.members().size(), kit, at.x, at.z, " (dev)" if dev else ""])
	_show_left = 0.0
	return ""


## Host: the high command's `order` (ORDERS) to element `target` ("1", "2"; "" or "all": every
## element out) at `point`. Only the host player gives these (the Captain's high command: the
## host/1st player). Returns "" when given, else why not.
##  move: go there and hold. defend: the same move, there to hold the ground (an arrived Move is
##  a real Hold, SquadAI._choose_intent). hold: stop and fight where it stands. assault / flank:
##  the attack drills the player's own squad uses (Squad.order_assault / order_flank) on the
##  enemy at `point`. follow: follow the host. regroup: come to the host and hold there.
##  fall_back: break contact back to `point` (Squad.order_fall_back). mount: take the vehicle
##  near `point` (one at the wheel, the rest aboard); drive: its vehicles go to `point`, by road
##  when that's better; dismount: out and holding there (SquadDrivers, the squad's drivers' tools).
func server_order(by: Soldier, order: String, point: Vector3, target := "") -> String:
	var why := _commandable(by)
	if why != "":
		return why
	var picked := _targets(target)
	if picked.is_empty():
		return "No element out" if target in ["", "all"] else "No element %s out" % target
	var level := CompoundLevel.current(self)
	if point.is_finite() and level and level.has_method(&"ground_point"):
		point = level.call(&"ground_point", point)  # a map order comes at y 0
	var problems := PackedStringArray()
	for e: Dictionary in picked:
		var sq: Squad = e.squad
		var at := point
		var r := ""
		match order:
			"move", "defend":
				sq.give_order(by, Squad.Order.MOVE, at)
			"hold":
				at = _centre(sq)
				sq.give_order(by, Squad.Order.HOLD, at)
			"regroup":
				at = by.global_position
				sq.give_order(by, Squad.Order.MOVE, at)
			"follow":
				at = by.global_position
				sq.give_order(by, Squad.Order.FOLLOW, at)
			"assault":
				r = sq.order_assault(by, at)
			"flank":
				r = sq.order_flank(by, at)
			"fall_back":
				r = sq.order_fall_back(by, at)
			"mount", "drive", "dismount":
				var drivers := SquadDrivers.of(self)
				if drivers == null:
					r = "no vehicles here"
				elif order == "mount":
					r = drivers.server_squad_mount(by, sq, at)
				elif order == "drive":
					r = drivers.server_squad_drive(by, sq, at)
				else:
					r = drivers.server_squad_dismount(by, sq)
			_:
				r = "Order not given"
		if r != "":
			problems.append("Element %d: %s" % [e.id, r])
		else:
			e.order = order
			e.point = at
	_show_left = 0.0
	return "; ".join(problems)


## The MVP's orders, kept for its callers: every element.
func server_move(by: Soldier, point: Vector3) -> String:
	return server_order(by, "move", point)


func server_hold(by: Soldier) -> String:
	return server_order(by, "hold", Vector3.INF)


func server_assault(by: Soldier, point: Vector3) -> String:
	return server_order(by, "assault", point)


## Host: sends element `target` ("" or "all": every one) home (freed, not left standing about)
## and starts its slot's cooldown.
func server_release(by: Soldier, target := "") -> String:
	var why := _commandable(by)
	if why != "":
		return why
	var picked := _targets(target)
	if picked.is_empty():
		return "No element out" if target in ["", "all"] else "No element %s out" % target
	for e: Dictionary in picked:
		_drop(int(e.id) - 1)
	last_message = "Allied element%s released" % ("s" if picked.size() > 1 else "")
	return ""


## Host: frees slot `slot`'s element; `cooldown` starts that slot's COOLDOWN_S.
func _drop(slot: int, cooldown := true) -> void:
	var e: Variant = elements[slot]
	if e == null:
		return
	var sq: Squad = e.squad
	if sq != null and is_instance_valid(sq):
		for s: Soldier in sq.members():
			s.queue_free()
		sq.queue_free()
	elements[slot] = null
	if cooldown:
		released_at[slot] = Soldier._now()
	_show_left = 0.0


## The elements `target` names: "1"/"2" one, "" or "all" every one out.
func _targets(target: String) -> Array:
	if target in ["", "all"]:
		return out()
	var i := target.to_int() - 1
	if i < 0 or i >= MAX_ELEMENTS or elements[i] == null or not _alive(elements[i]):
		return []
	return [elements[i]]


## Why `by` can't command the elements right now, or "": the host player only (the high command).
func _commandable(by: Soldier) -> String:
	if not multiplayer.is_server() or by == null:
		return "no"
	if by.is_ai() or by.owner_peer() != 1:
		return "Only the host commands the allied elements"
	if not is_out():
		return "No element out"
	return ""


## Whether the local player is the one who commands the elements (the map offers their orders).
func local_commands() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.get_unique_id() == 1


static func _centre(sq: Squad) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for s: Soldier in sq.members():
		if s.vitals.is_up():
			sum += s.global_position
			n += 1
	return sum / n if n > 0 else Vector3.ZERO


static func _contract_id() -> String:
	var cids: Array = Contracts.deployment().get("cids", [])
	return String(cids[0]) if not cids.is_empty() else ""


# --- What every peer's map shows -------------------------------------------------------------

## Host: what's out, for the map (`shown`).
func summary() -> Array:
	var list: Array = []
	for e: Dictionary in out():
		var names := PackedStringArray()
		for s: Soldier in (e.squad as Squad).members():
			names.append(String(s.name))
		var p: Vector3 = e.point
		list.append({"id": int(e.id), "kind": String(e.kind), "label": "Allied %d, %s" % [e.id, KINDS[e.kind].label],
			"order": String(e.order), "point": Vector2(p.x, p.z) if p.is_finite() else Vector2.INF, "names": names,
			"employer": MissionRegistry.faction_name(String(e.employer))})
	return list


@rpc("authority", "call_local", "reliable")
func _client_show(list: Array) -> void:
	shown = list


## Host: an element's own death (every member down) frees its slot and starts its cooldown the
## same as a release; and every SHOW_EVERY_S, or right after a change, every peer gets `shown`.
func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	for i in MAX_ELEMENTS:
		if elements[i] != null and not _alive(elements[i]):
			print("[allied] element %d lost" % (i + 1))
			_drop(i)
	_show_left -= delta
	if _show_left <= 0.0:
		_show_left = SHOW_EVERY_S
		var list := summary()
		if list != shown:
			_client_show.rpc(list)
