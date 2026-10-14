class_name Squad
extends Node
## Host-side command state for one faction's AI. Friendly squadmates follow a lead player
## (the host by default). Any player can give orders from the command menu, which also makes
## them the lead; orders go to the units they selected. Hostile squads use the same node for
## their patrol route.
##
## The friendly squad is two fire teams of four (Roles); CompoundLevel.rebalance_squad sets
## each soldier's role, fire team and slot. Commands here: movement orders, hold/open fire,
## throws, formation, Target (focus fire), Combat mode and Team (colour teams), and the tactic
## orders (order_suppress, order_bound, order_garrison, order_clear, order_take_cover,
## order_fall_back; also as command() strings, see TACTIC_COMMANDS).
##
## Squad tactics (Captain, P0164 queue 17 core), host only, both sides: the squad keeps one
## picture of the enemy (known: where each enemy was last seen or heard, and when, from its
## members' eyes and ears), grouped in clusters, and its tactical evaluator (SquadTactics)
## decides every SquadTactics.THINK_S how the squad fights.

enum Order { FOLLOW, HOLD, MOVE }
## Arma 3's behaviour modes (command menu > Combat mode): how AI moves, fires and holds
## stance. See SquadAI for what each one does. COMBAT is the default.
enum CombatMode { SAFE, AWARE, COMBAT, STEALTH }

## Command names for the combat modes ("mode:<name>").
const COMBAT_MODES := {"safe": CombatMode.SAFE, "aware": CombatMode.AWARE, "combat": CombatMode.COMBAT, "stealth": CombatMode.STEALTH}
## Arma 3 colour teams ("team:<colour>"); white means no team.
const COLOR_TEAMS: Array[String] = ["red", "green", "blue", "yellow", "white"]
## Proposed: how far away a Target order can name an enemy.
const TARGET_RANGE := 300.0
## Proposed: "Scavenge that body" picks the body within this of the spot under the crosshair.
const ORDER_BODY_M := 3.0
## Proposed: "Garrison" and "Clear" take the building within this of the spot under the crosshair.
const ORDER_BUILDING_M := 4.0
## Heights on a soldier (m above their feet) checked for a line of sight to them.
const SIGHT_HEIGHTS: Array[float] = [1.7, 1.4, 1.0, 0.5]
## Proposed: once any member is fired upon, the whole squad counts as engaged this long
## (units in Safe or Stealth hold fire until then).
const ENGAGED_S := 20.0
## The enemy picture (proposed): a known position is fresh this long after it was seen or
## reported, stale from STALE_S (searched for, not fought), and forgotten after FORGET_S. A
## position heard doesn't replace one seen within HEARD_KEEP_S. Known enemies within CLUSTER_M
## of each other make one cluster.
const FRESH_S := 6.0
const STALE_S := 20.0
const FORGET_S := 90.0
const HEARD_KEEP_S := 4.0
const CLUSTER_M := 10.0
## Tactic orders by command string (command()): "<name>" acts on the point under the
## crosshair ("suppress:known" suppresses the densest known cluster instead).
const TACTIC_COMMANDS: Array[String] = ["suppress", "bound", "garrison", "clear", "take_cover", "fall_back"]

## Follow positions in the leader's space (x right, +z behind), per formation.
const FORMATIONS := {
	"wedge": [Vector3(-1.8, 0, 2.2), Vector3(1.8, 0, 2.6), Vector3(-3.4, 0, 4.4), Vector3(3.4, 0, 4.8),
		Vector3(-5.0, 0, 6.6), Vector3(5.0, 0, 7.0), Vector3(0, 0, 6.0)],
	"file": [Vector3(0, 0, 2.5), Vector3(0, 0, 5.0), Vector3(0, 0, 7.5), Vector3(0, 0, 10.0),
		Vector3(0, 0, 12.5), Vector3(0, 0, 15.0), Vector3(0, 0, 17.5)],
	"line": [Vector3(-2.5, 0, 0.5), Vector3(2.5, 0, 0.5), Vector3(-5.0, 0, 0.5), Vector3(5.0, 0, 0.5),
		Vector3(-7.5, 0, 0.5), Vector3(7.5, 0, 0.5), Vector3(-10.0, 0, 0.5)],
	"staggered column": [Vector3(-1.5, 0, 2.5), Vector3(1.5, 0, 5.0), Vector3(-1.5, 0, 7.5), Vector3(1.5, 0, 10.0),
		Vector3(-1.5, 0, 12.5), Vector3(1.5, 0, 15.0), Vector3(-1.5, 0, 17.5)],
}

@export var faction := &"friendly"

var leader: Soldier
var formation := "wedge"
## Hostile squads: points to walk between when nothing is happening.
var patrol: Array[Vector3] = []
## When a member was last fired upon (Soldier._now() seconds).
var engaged_at := -1000.0
## The squad's last frag: when (Soldier._now()) and where it went, so the rest don't throw at
## the same spot at once (SquadAI._maybe_frag).
var frag_at := -1000.0
var frag_point := Vector3.ZERO
## Host: the squad's picture of the enemy, by enemy instance id: {"who": Soldier, "pos":
## Vector3, "at": Soldier._now() when seen or heard there, "heard": true if only heard}.
var known := {}
## Host: the squad's tactical evaluator (made on its first think).
var tactics: SquadTactics
## How this squad fights (SquadTactics.DOCTRINES); empty: by its side (the friendly squad's
## drills, or the insurgents').
var doctrine: StringName = &""
## "Bring casualties here" (order_ccp): where the squad's carriers lay their casualties, a
## point or a soldier to bring them to (the ordering player, wherever he goes); null for none.
var ccp: Variant = null
## The squad's last screening smoke (SquadAI._screened): when and where it went up.
var screen_at := -1000.0
var screen_point := Vector3.ZERO
var _tactics_cd := 0.0


## Host: the tactical evaluator thinks every SquadTactics.THINK_S.
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_tactics_cd -= delta
	if _tactics_cd > 0.0:
		return
	_tactics_cd = SquadTactics.THINK_S
	if tactics == null:
		tactics = SquadTactics.new(self)
	tactics.think(Soldier._now())


## The AI brains of this squad's living soldiers, in members() order. Only those whose
## SquadAI.squad is this one: a hot zone has many hostile squads on one side.
func brains() -> Array[SquadAI]:
	var out: Array[SquadAI] = []
	for s in members():
		var ai := SquadAI.of(s)
		if ai and ai.squad == self and ai._ready_done:
			out.append(ai)
	return out


## Host: a member saw `who` at `pos` (or, `heard`, heard him there: a rougher fix).
func note_enemy(who: Soldier, pos: Vector3, heard := false) -> void:
	if who == null or not is_instance_valid(who):
		return
	var id := who.get_instance_id()
	var now := Soldier._now()
	var was: Dictionary = known.get(id, {})
	if heard and not was.is_empty() and not bool(was.heard) and now - float(was.at) < HEARD_KEEP_S:
		return  # seen there a moment ago: a heard bearing is worse
	known[id] = {"who": who, "pos": pos, "at": now, "heard": heard}


## The enemy picture now: every known enemy still up and not forgotten, each entry with its
## "age" in seconds. The dead, the downed, those who gave up and the forgotten drop out.
func enemy_picture() -> Array[Dictionary]:
	var now := Soldier._now()
	var out: Array[Dictionary] = []
	for id: int in known.keys():
		var e: Dictionary = known[id]
		var who: Soldier = e.who as Soldier if is_instance_valid(e.who) else null
		if who == null or who.is_queued_for_deletion() or not who.vitals.is_up() or Person.is_noncombatant(who) \
				or now - float(e.at) > FORGET_S:
			known.erase(id)
			continue
		var entry := e.duplicate()
		entry.age = now - float(e.at)
		out.append(entry)
	return out


## Known enemies (enemy_picture) grouped within CLUSTER_M of each other: [{"centre", "count",
## "age" (the freshest), "who": Array}], those with a fresh member (FRESH_S) first, then the
## most enemies, then the freshest.
func clusters() -> Array[Dictionary]:
	var picture := enemy_picture()
	picture.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.age) < float(b.age))
	var out: Array[Dictionary] = []
	for e in picture:
		var joined := false
		for c in out:
			if (c.centre as Vector3).distance_to(e.pos) <= CLUSTER_M:
				c.sum += e.pos
				c.count += 1
				c.centre = c.sum / c.count
				c.who.append(e.who)
				joined = true
				break
		if not joined:
			out.append({"centre": e.pos, "sum": e.pos, "count": 1, "age": e.age, "who": [e.who]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var fa := float(a.age) < FRESH_S
		var fb := float(b.age) < FRESH_S
		if fa != fb:
			return fa
		if a.count != b.count:
			return a.count > b.count
		return float(a.age) < float(b.age))
	return out


## Forgets every known position older than FRESH_S (a search that found nothing).
func forget_stale() -> void:
	var now := Soldier._now()
	for id: int in known.keys():
		if now - float(known[id].at) >= FRESH_S:
			known.erase(id)


## The squad's living AI soldiers, in squad-slot order (then by name). Dead bodies keep no
## formation slot and take no orders.
func members() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.is_ai() and s.faction == faction and not s.is_queued_for_deletion() and not s.vitals.is_dead():
			if s.has_meta(&"vehicle_crew"):
				continue  # wave 5b: a support vehicle's AI crew (AavSupport) takes no squad orders
			out.append(s)
	out.sort_custom(func(a: Soldier, b: Soldier) -> bool:
		if a.squad_slot != b.squad_slot:
			return (a.squad_slot if a.squad_slot >= 0 else 99) < (b.squad_slot if b.squad_slot >= 0 else 99)
		return String(a.name) < String(b.name))
	return out


## Members by name, or all of them for an empty list.
func pick(names: PackedStringArray) -> Array[Soldier]:
	var out: Array[Soldier] = []
	for s in members():
		if names.is_empty() or String(s.name) in names:
			out.append(s)
	return out


## A movement order (follow, hold, move to `point`) for the named units.
func give_order(from: Soldier, order: Order, point: Vector3, names := PackedStringArray()) -> void:
	leader = from
	var units := pick(names)
	for i in units.size():
		var ai := SquadAI.of(units[i])
		if ai:
			ai.on_order(order, point, i, units.size())


## Command menu: hold fire / open fire for the named units.
func set_hold_fire(from: Soldier, hold: bool, names := PackedStringArray()) -> void:
	leader = from
	for s in pick(names):
		var ai := SquadAI.of(s)
		if ai:
			ai.hold_fire = hold


## Command menu "Scavenge freely" / "Don't scavenge" for the named units.
func set_scavenge(from: Soldier, allowed: bool, names := PackedStringArray()) -> void:
	leader = from
	for s in pick(names):
		var ai := SquadAI.of(s)
		if ai:
			ai.scavenge_allowed = allowed
			if not allowed:
				ai.scavenge_order = null


## Command menu "Scavenge that body": the nearest named AI goes through the dead body within
## ORDER_BODY_M of `point` for what it needs. Returns why nobody could ("" if someone went).
## Measured to where the body lies (Soldier.body_point: its ragdoll can rest metres from the
## capsule), so the body the player looks at is the one found.
func order_scavenge(from: Soldier, point: Vector3, names := PackedStringArray()) -> String:
	leader = from
	var dead: Soldier = null
	var best := ORDER_BODY_M
	for n in from.get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
		var s := n as Soldier
		if s and not s.is_queued_for_deletion() and s.body_point().distance_to(point) < best:
			dead = s
			best = s.body_point().distance_to(point)
	if dead == null:
		return "Look at a body"
	if dead.has_gear_marker:
		return "That's a player's gear: leave it for them"
	if not dead.has_gear():
		return "Nothing left on that body"
	var units := pick(names).filter(func(s: Soldier) -> bool: return SquadAI.of(s) != null and s.vitals.is_up())
	if units.is_empty():
		return "Nobody selected can"
	units.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.global_position.distance_to(point) < b.global_position.distance_to(point))
	var ai := SquadAI.of(units[0])
	ai.scavenge_order = dead
	ai._think_cd = 0.0
	return ""


## Command menu: the first named unit that has one throws a grenade at `point`.
## Returns the thrower's name, or "" if nobody could.
func order_throw(from: Soldier, id: StringName, point: Vector3, names := PackedStringArray()) -> String:
	leader = from
	var units := pick(names)
	units.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.global_position.distance_to(point) < b.global_position.distance_to(point))
	for s in units:
		var ai := SquadAI.of(s)
		if ai and s.inventory.count_of(id) > 0 and ai.order_throw(id, point):
			return String(s.name)
	return ""


# --- Tactic orders (queue 17 core) -------------------------------------------------------
# For the command menu to call as thin wrappers (stable API). Each gives the named units (all
# for an empty list) a tactic order (SquadAI.ordered) that wins over the squad's own tactics
# for them until it's done or a movement order replaces it, and returns "" when given, else
# why not (to show the ordering player). Done, a unit holds where it ended up (Hold order).

## "Suppress": the named units put suppressive fire on `point` (Vector3.INF: the squad's
## densest known enemy cluster) for SquadAI.SUPPRESS_ORDER_S, keeping their movement orders.
func order_suppress(from: Soldier, point: Vector3, names := PackedStringArray()) -> String:
	leader = from
	if not point.is_finite():
		var found := clusters()
		if found.is_empty():
			return "No known enemy to suppress"
		point = found[0].centre
	var units := _able(names)
	if units.is_empty():
		return "Nobody selected can"
	for ai in units:
		ai.give_tactic({"kind": &"suppress", "aim": point + Vector3.UP, "until": Soldier._now() + SquadAI.SUPPRESS_ORDER_S})
	return ""


## "Bound to": the named units move to `point` by bounding overwatch (buddy pairs take turns,
## one moving cover to cover while the other covers, smoke before open ground under fire),
## spread across it as a move order spreads them, and hold there.
func order_bound(from: Soldier, point: Vector3, names := PackedStringArray()) -> String:
	leader = from
	var units := _able(names)
	if units.is_empty():
		return "Nobody selected can"
	var side := from.global_basis.x
	for i in units.size():
		units[i].give_tactic({"kind": &"bound", "point": point + side * (i - (units.size() - 1) / 2.0) * 1.5})
	return ""


## "Garrison that building": the named units take the building at `point`, its window and door
## positions facing the threat first (the squad's densest known cluster, else away from the
## ordering player), the rest inside, and hold it.
func order_garrison(from: Soldier, point: Vector3, names := PackedStringArray()) -> String:
	leader = from
	var b := Buildings.nearest(from, point, ORDER_BUILDING_M)
	if b.is_empty():
		return "Look at a building"
	var units := _able(names)
	if units.is_empty():
		return "Nobody selected can"
	var found := clusters()
	var threat: Vector3 = found[0].centre if not found.is_empty() else point + (point - from.global_position)
	var tasks := SquadTactics.garrison_tasks(b, units, threat)
	for ai: SquadAI in tasks:
		ai.give_tactic(tasks[ai])
	return ""


## "Clear that building": the named units stack beside the building's entrance nearest them,
## then go in one after the other, pair by pair, room by room (SquadTactics.clear_op), and
## hold inside once it's clear.
func order_clear(from: Soldier, point: Vector3, names := PackedStringArray()) -> String:
	leader = from
	var b := Buildings.nearest(from, point, ORDER_BUILDING_M)
	if b.is_empty():
		return "Look at a building"
	var units := _able(names)
	if units.is_empty():
		return "Nobody selected can"
	var op := SquadTactics.clear_op(b, units)
	if op.is_empty():
		return "No way in found"
	for i in units.size():
		units[i].give_tactic({"kind": &"clear", "op": op, "slot": i})
	return ""


## "Take cover": each named unit takes the best cover near it from its last known threat and
## holds there.
func order_take_cover(from: Soldier, names := PackedStringArray()) -> String:
	leader = from
	var units := _able(names)
	if units.is_empty():
		return "Nobody selected can"
	for ai in units:
		ai.give_tactic({"kind": &"cover"})
	return ""


## "Fall back": the named units break contact, bounding back by pairs with smoke over open
## ground, to `point` (Vector3.INF: SquadTactics.BREAK_BEHIND_LEAD_M behind the ordering
## player, away from the threat), and hold there.
func order_fall_back(from: Soldier, point: Vector3, names := PackedStringArray()) -> String:
	leader = from
	var units := _able(names)
	if units.is_empty():
		return "Nobody selected can"
	var found := clusters()
	for i in units.size():
		var ai := units[i]
		var p := point
		if not p.is_finite():
			var threat: Vector3 = found[0].centre if not found.is_empty() else ai.body.threat_pos
			p = SquadTactics.fall_back_point(from, threat, i, units.size())
		ai.give_tactic({"kind": &"break", "point": p})
	return ""


## The command menu's orders (Captain, P0164 queue 12; thin wrappers over the tactics and the
## units' own skills), by command string. Returns "" when given, why not otherwise, or "?"
## for a command that isn't one of these (command() handles the rest).
##  suppress, suppress:known, bound, garrison, clear, take_cover, fall_back: the tactic orders.
##  watch: face the sector at `point` and engage there. stance:<up|crouch|prone|auto>.
##  heal: patch yourselves up now. give_ammo: the nearest selected with your ammunition brings
##  you magazines. launcher_out: shoulder launchers and look for targets for them.
##  treat:<name>: the selected (a medic first) treats that casualty. ccp: bring casualties to
##  `point`; ccp_me: to me; ccp_off: stop. drop_packs: packs off where they stand (lighter,
##  faster); pick_packs: each goes back for his own.
func order_command(from: Soldier, cmd: String, point: Vector3, names := PackedStringArray()) -> String:
	var parts := cmd.split(":", true, 1)
	var arg := parts[1] if parts.size() > 1 else ""
	match parts[0]:
		"suppress":
			return order_suppress(from, Vector3.INF if arg == "known" else point, names)
		"bound":
			return order_bound(from, point, names)
		"garrison":
			return order_garrison(from, point, names)
		"clear":
			return order_clear(from, point, names)
		"take_cover":
			return order_take_cover(from, names)
		"fall_back":
			return order_fall_back(from, Vector3.INF, names)
		"watch":
			leader = from
			var units := _able(names)
			for ai in units:
				ai.give_tactic({"kind": &"watch", "point": point})
			return "" if not units.is_empty() else "Nobody selected can"
		"stance":
			if not SquadAI.STANCE_ORDERS.has(arg):
				return "?"
			var units := _able(names)
			for ai in units:
				ai.stance_order = SquadAI.STANCE_ORDERS[arg]
				ai.body.want_stance = ai.stance_order  # (auto: back to their own choice at once)
			return "" if not units.is_empty() else "Nobody selected can"
		"heal":
			var hurt := _able(names).filter(func(ai: SquadAI) -> bool: return not ai._self_task().is_empty())
			for ai: SquadAI in hurt:
				ai.order_heal()
			return "" if not hurt.is_empty() else "Nobody selected has wounds they can treat"
		"give_ammo":
			return order_give_ammo(from, names)
		"launcher_out":
			var ready := _able(names).filter(func(ai: SquadAI) -> bool: return LauncherAI.order_ready(ai.body))
			return "" if not ready.is_empty() else "Nobody selected has a launcher"
		"treat":
			return order_treat(from, arg, names)
		"drop_packs":
			var dropped := _able(names).filter(func(ai: SquadAI) -> bool: return ai.drop_pack())
			return "" if not dropped.is_empty() else "Nobody selected wears a pack"
		"pick_packs":
			var going := _able(names).filter(func(ai: SquadAI) -> bool: return not ai.dropped_pack.is_empty())
			for ai: SquadAI in going:
				ai.give_tactic({"kind": &"pick_pack"})
			return "" if not going.is_empty() else "Nobody selected dropped a pack"
		"ccp":
			ccp = point
			return ""
		"ccp_me":
			ccp = from
			return ""
		"ccp_off":
			ccp = null
			return ""
	return "?"


## "Give me ammo": the nearest selected unit carrying magazines of `from`'s weapon (one not
## busy with a casualty or his own wounds, if there is one) brings him some.
func order_give_ammo(from: Soldier, names: PackedStringArray) -> String:
	var weapon := from.active_weapon()
	if weapon == null or weapon.type != "weapon":
		return "Have a rifle in your hands"
	var ammo := Soldier._ammo_of(weapon)
	var best: SquadAI = null
	var cost := func(ai: SquadAI) -> float:  # the nearest, and one not busy patching someone (or himself) up first
		var busy := ai.care != SquadAI.Care.NONE or ai.intent in [SquadAI.Intent.HEAL, SquadAI.Intent.CASUALTY] or not ai._self_task().is_empty()
		return ai.body.global_position.distance_to(from.global_position) + (1000.0 if busy else 0.0)
	for ai in _able(names):
		if ai.body.inventory.spare_rounds(ammo) > 0 and (best == null or cost.call(ai) < cost.call(best)):  # (spares: what _take_out finds)
			best = ai
	if best == null:
		return "Nobody selected carries %s" % ItemDB.get_item(ammo).name if ItemDB.has_item(ammo) else "Nobody selected has any"
	best.give_tactic({"kind": &"give_ammo", "who": from, "ammo": ammo})
	return ""


## "Treat that casualty": the selected unit best fit for it (a medic first, else the nearest)
## takes over casualty `callsign`.
func order_treat(from: Soldier, callsign: String, names: PackedStringArray) -> String:
	var c: Soldier = null
	for s in get_tree().get_nodes_in_group(&"combatants"):
		if s is Soldier and String(s.name) == callsign:
			c = s
	if c == null or c.vitals.is_dead() or c.faction != from.faction:
		return "Look at a wounded squadmate"
	if not SquadAI.needs_help(c):
		return "%s doesn't need treatment" % c.display_name()
	var best: SquadAI = null
	for ai in _able(names):
		if ai.body == c:
			continue
		var medic: bool = ai.body.role == Roles.MEDIC
		var d := ai.body.global_position.distance_to(c.global_position)
		if best == null or (medic and best.body.role != Roles.MEDIC) or (medic == (best.body.role == Roles.MEDIC) and d < best.body.global_position.distance_to(c.global_position)):
			best = ai
	if best == null:
		return "Nobody selected can"
	best._take_casualty(c)
	best._think_cd = 0.0
	return ""


## Where the squad's carriers lay their casualties now (ccp), or null.
func ccp_point() -> Variant:
	if ccp is Vector3:
		return ccp
	if ccp != null and is_instance_valid(ccp) and (ccp as Soldier).vitals.is_up():
		return (ccp as Soldier).global_position
	return null


## The named units' brains that can take a tactic order: AI, up.
func _able(names: PackedStringArray) -> Array[SquadAI]:
	var out: Array[SquadAI] = []
	for s in pick(names):
		var ai := SquadAI.of(s)
		if ai and ai._ready_done and s.vitals.is_up():
			out.append(ai)
	return out


## The command-menu commands with an argument: "formation:<name>", "target:<enemy name>"
## ("target:" clears it), "mode:<combat mode>" and "team:<colour>", and the tactic orders
## (TACTIC_COMMANDS) on `point`. False if the command or its argument isn't valid, or the
## order couldn't be given.
func command(from: Soldier, cmd: String, point: Vector3, names := PackedStringArray()) -> bool:
	var parts := cmd.split(":", true, 1)
	var arg := parts[1] if parts.size() > 1 else ""
	match parts[0]:
		"formation":
			if not FORMATIONS.has(arg):
				return false
			leader = from
			formation = arg
			return true
		"target":
			return set_target(from, arg, names)
		"escort":
			return order_escort(from, arg, names)
		"mode":
			return COMBAT_MODES.has(arg) and set_combat_mode(from, COMBAT_MODES[arg], names)
		"team":
			return assign_color(from, arg, names)
	return false


## Command menu "Escort that HVT" (Captain, 2026-10-11): the named units nearest HVT
## `hvt_name` escort him (SquadAI escort), at most SquadAI.ESCORTS_MAX with whoever escorts
## him already; "" takes the named units off escort. The ordering player must see him within
## TARGET_RANGE. False if nobody took it on.
func order_escort(from: Soldier, hvt_name: String, names := PackedStringArray()) -> bool:
	leader = from
	var units := pick(names)
	if hvt_name == "":
		for s in units:
			var ai := SquadAI.of(s)
			if ai:
				ai.set_escort(null)
		return true
	var hvt := find_soldier(hvt_name)
	if hvt == null or not Person.is_hvt(hvt) or hvt.vitals.is_dead() or hvt.global_position.distance_to(from.global_position) > TARGET_RANGE or not sees(from, hvt):
		return false
	var current := SquadAI.escorts_of(hvt)
	units.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.global_position.distance_to(hvt.global_position) < b.global_position.distance_to(hvt.global_position))
	var next := 0 if current.is_empty() else current[current.size() - 1].escort_order + 1
	var given := 0
	for s in units:
		var ai := SquadAI.of(s)
		if ai == null or not s.vitals.is_up() or ai in current:
			continue
		if current.size() + given >= SquadAI.ESCORTS_MAX:
			break
		ai.set_escort(hvt, next + given)
		given += 1
	return given > 0 or not current.is_empty()


## Command menu "Target": the named units focus fire on the enemy called `enemy_name`
## (they still need to see it), or pick their own targets again for "". The ordering player
## must have a clear line to the enemy (the host checks, so a client can't name any hostile).
func set_target(from: Soldier, enemy_name: String, names := PackedStringArray()) -> bool:
	var enemy: Soldier = null
	if enemy_name != "":
		enemy = find_soldier(enemy_name)
		if enemy == null or enemy.faction == faction or not enemy.vitals.is_up() \
				or enemy.global_position.distance_to(from.global_position) > TARGET_RANGE or not sees(from, enemy):
			return false
	leader = from
	for s in pick(names):
		var ai := SquadAI.of(s)
		if ai:
			ai.focus = enemy
	return true


## True if nothing solid stands between `viewer`'s eyes and some part of `other` (feet to
## head), as when the viewer puts the crosshair on them. Smoke doesn't count here.
static func sees(viewer: Soldier, other: Soldier) -> bool:
	var eyes := viewer.camera.global_position
	for height: float in SIGHT_HEIGHTS:
		if Throwables.clear_line(viewer.get_world_3d(), eyes, other.global_position + Vector3.UP * height):
			return true
	return false


## Command menu "Combat mode" for the named units.
func set_combat_mode(from: Soldier, mode: CombatMode, names := PackedStringArray()) -> bool:
	leader = from
	for s in pick(names):
		var ai := SquadAI.of(s)
		if ai:
			ai.combat_mode = mode
	return true


## Command menu "Team": puts the named units in a colour team (white: none).
func assign_color(from: Soldier, colour: String, names := PackedStringArray()) -> bool:
	if colour not in COLOR_TEAMS:
		return false
	leader = from
	for s in pick(names):
		s.color_team = "" if colour == "white" else colour
	return true


## Host: a member was fired upon (the squad is engaged for ENGAGED_S).
func note_fired_on() -> void:
	engaged_at = Soldier._now()


func is_engaged() -> bool:
	return Soldier._now() - engaged_at < ENGAGED_S


## A soldier (any side) by node name, or null.
func find_soldier(soldier_name: String) -> Soldier:
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and String(s.name) == soldier_name and not s.is_queued_for_deletion():
			return s
	return null


## Where `member` stands when following: its slot in the formation behind the leader.
func follow_point(member: Soldier) -> Vector3:
	if leader == null or not is_instance_valid(leader):
		return member.global_position
	var slots: Array = FORMATIONS.get(formation, FORMATIONS["wedge"])
	var i := members().find(member)
	return leader.global_transform * (slots[maxi(i, 0) % slots.size()] as Vector3)
