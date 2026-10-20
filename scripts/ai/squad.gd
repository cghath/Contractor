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
## "Climb into the HX-1" looks for a parked suit this far from each unit (m).
const EXO_FIND_M := 80.0
const TACTIC_COMMANDS: Array[String] = ["suppress", "bound", "garrison", "clear", "clear_town", "take_cover", "fall_back", "climb", "flank", "assault"]

## Spawn positions in the leader's space (x right, +z behind), per formation (the squad's
## first places; following uses formation slots, follow_point).
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

## Formation and spacing (Captain, 2026-10-14, playtesting v0.3.1: "ai are bunching up after a
## while in mission"; then "that sounds fantastic so long as I can set them to be dynamic").
## Each fire team keeps its own formation slots (follow_point): the lead's team round the lead,
## the other team round its own team leader, placed its spacing's "team" metres off. The
## command menu sets a formation and a spacing for the squad or a fire team (set_formation);
## DYNAMIC (the default) picks them from where the squad is (_update_context): a town tighter,
## open ground wider, under fire wider still, low visibility a step tighter; a column on a
## road, a staggered column in a town, a line in contact in the open, else a wedge.
const DYNAMIC := "dynamic"
## The formations a fire team can take (team_shape; "column" is two files side by side).
const FORMATION_NAMES: Array[String] = ["wedge", "line", "column", "file", "staggered column"]
## Proposed (Captain, 2026-10-14): metres between men in a fire team ("man"), and between the
## fire teams ("team": centre to centre in a wedge; twice the gap behind the lead team in a
## column). Open ground 6-12 m between men and 15-30 m between fire teams, a town 3-5 m.
const SPACINGS := {
	"tight": {"man": 4.0, "team": 12.0},
	"normal": {"man": 8.0, "team": 20.0},
	"wide": {"man": 12.0, "team": 28.0},
}
const SPACING_ORDER: Array[String] = ["tight", "normal", "wide"]
## Dynamic (proposed): how often the squad looks at where it is; buildings within TOWN_M of
## the lead make it a town (looked up on a TOWN_GRID_M grid, so a walk doesn't rescan every
## step); road under the lead from ROAD_WEIGHT (ZoneTerrain.road_weight).
const CONTEXT_S := 1.0
const TOWN_M := 18.0
const TOWN_GRID_M := 8.0
const ROAD_WEIGHT := 0.5
## The squad's heading (which way its formation faces) follows the lead's travel, not where
## he looks: updated each time he has gone HEADING_STEP_M, by HEADING_BLEND of the new way.
## A lead turning to look round no longer swings every slot through the squad. Proposed.
const HEADING_STEP_M := 2.0
## A slot behind a wall from where its team forms comes this far back off the wall (_this_side).
const WALL_CLEAR_M := 1.0
const SIDE_HOLD_S := 2.0
## A slot across a wall from where its team forms, on the lead, or on another slot is picked
## again on open ground (_refit): the other side, else back along the lead's trail. Captain,
## 2026-10-15 (v0.4.3, harbour_yard): beside a long wall every wall-side slot was pulled back
## along one diagonal to the same spot, so the squad piled into a line on the wall and one man
## stood in the player. A re-picked slot keeps SLOT_APART_MULT of the gap (at least
## SLOT_APART_MIN_M) from every other slot and LEAD_CLEAR_M from the lead and the players.
const SLOT_APART_MIN_M := 2.0
const SLOT_APART_MULT := 0.75
const LEAD_CLEAR_M := 2.0
## Two kept slots closer than this: the later one is picked again.
const SLOT_STACK_M := 1.5
## The lead's trail (where he walked, so ground a man can stand on, on this side of every
## wall): a point each TRAIL_STEP_M, the last TRAIL_MAX of them; a jump of more than
## TRAIL_JUMP_M (a respawn, a ride, a new lead) starts it over.
const TRAIL_STEP_M := 1.0
const TRAIL_MAX := 90
const TRAIL_JUMP_M := 6.0
const HEADING_BLEND := 0.5

@export var faction := &"friendly"

var leader: Soldier
## The squad's formation and spacing orders (DYNAMIC: chosen by context, the default), and
## per fire team orders over them: {team: {"formation": String, "spacing": String}}.
var formation := DYNAMIC
var spacing := DYNAMIC
var team_orders := {}
## What DYNAMIC resolves to now (host, _update_context): {"formation", "spacing", "why"}.
var context := {"formation": "wedge", "spacing": "normal", "why": "open ground"}
## Flat unit direction the formation faces (see HEADING_STEP_M).
var heading := Vector3.ZERO
var _heading_from := Vector3.INF
var _context_cd := 0.0
var _slots := {}  # Soldier -> its formation slot, worked out once a physics frame
var _slots_frame := -1
var _sides := {}  # slot key -> {"pulled", "since"} (_blocked)
var _trail := PackedVector3Array()  # the lead's trail, oldest first (_update_trail)
var _refits := {}  # soldier instance id -> his last re-pick {"kind": "mirror"/"trail", "s": metres back}
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
## "Stop bringing casualties" (ccp_off) as a standing order (Captain, 2026-10-14: it did
## nothing visible): carriers lay their casualty or body down where they are and treat or
## watch over them there, and nobody lifts a casualty or body on their own until "Bring
## casualties there/to me" or a move order. Contact drags to cover and an HVT's carry still
## happen under it (SquadAI._care_carry).
var hold_casualties := false
## The squad's last screening smoke (SquadAI._screened): when and where it went up.
var screen_at := -1000.0
var screen_point := Vector3.ZERO
## A rescuer went down going to / treating a casualty here, then (SquadAI._rescue_hot).
var rescuer_down_at := -1000.0
var rescuer_down_point := Vector3.ZERO
var _tactics_cd := 0.0


## Host: the tactical evaluator thinks every SquadTactics.THINK_S.
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_update_heading()
	_update_trail()
	_tick_town()
	_context_cd -= delta
	if _context_cd <= 0.0:
		_context_cd = CONTEXT_S
		_update_context()
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


## A lost enemy is placed where his last heading and speed would take him, for up to this long
## (G-22). Proposed.
const LEAD_S := 4.0


## Host: a member saw `who` at `pos` (or, `heard`, heard him there: a rougher fix).
func note_enemy(who: Soldier, pos: Vector3, heard := false) -> void:
	if who == null or not is_instance_valid(who):
		return
	var id := who.get_instance_id()
	var now := Soldier._now()
	var was: Dictionary = known.get(id, {})
	if heard and not was.is_empty() and not bool(was.heard) and now - float(was.at) < HEARD_KEEP_S:
		return  # seen there a moment ago: a heard bearing is worse
	var vel := Vector3.ZERO if heard else Vector3(who.velocity.x, 0.0, who.velocity.z)  # where he was going (G-22)
	known[id] = {"who": who, "pos": pos, "at": now, "heard": heard, "vel": vel}


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
		if not bool(e.heard) and float(entry.age) > 1.0:
			# Out of sight a while: he's looked for where he was going, not where he was (G-22;
			# Arma leads a lost target by its last heading and speed), up to LEAD_S of it.
			entry.pos = (e.pos as Vector3) + (e.get("vel", Vector3.ZERO) as Vector3) * minf(float(entry.age), LEAD_S)
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
## formation slot and take no orders. Scoped to this Squad instance (SquadAI.squad == self,
## the same scoping brains() already uses) so a second same-faction squad (wave 6e's allied
## troops, their own Squad beside the player's) doesn't answer for each other's.
func members() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.is_ai() and s.faction == faction and not s.is_queued_for_deletion() and not s.vitals.is_dead():
			if s.has_meta(&"vehicle_crew"):
				continue  # wave 5b: a support vehicle's AI crew (AavSupport) takes no squad orders
			var ai := SquadAI.of(s)
			if ai and ai.squad != self:
				continue
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


## The fire team `p` leads as a human who is not the squad lead's team's leader (the first man
## up in a team other than the lead's, by squad slot), or -1. His orders apply to his own team
## and don't hand the squad's lead to him (Soldier._server_squad_command); his team forms on
## him (_work_out_slots).
func human_team_lead_of(p: Soldier) -> int:
	if p == null or p.is_ai() or leader == null or not is_instance_valid(leader) or p == leader or p.fire_team < 0:
		return -1
	var lead_team := leader.fire_team if leader.fire_team >= 0 else 0
	if p.fire_team == lead_team:
		return -1
	var mine := p.squad_slot if p.squad_slot >= 0 else 99
	for m in members():
		if m.fire_team == p.fire_team and m.vitals.is_up() and (m.squad_slot if m.squad_slot >= 0 else 99) < mine:
			return -1
	return p.fire_team


## The units of fire team `t` among `names` (all of the team if `names` is empty), as names.
func team_names(t: int, names := PackedStringArray()) -> PackedStringArray:
	var out := PackedStringArray()
	for s in members():
		if s.fire_team == t and (names.is_empty() or String(s.name) in names):
			out.append(String(s.name))
	return out


## A movement order (follow, hold, move to `point`) for the named units.
func give_order(from: Soldier, order: Order, point: Vector3, names := PackedStringArray()) -> void:
	leader = from
	if order == Order.MOVE:
		hold_casualties = false  # a move takes the casualties along (SquadAI._care_carry)
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


## "Climb up there" (Captain, 2026-10-16: "jumping walls or on top of buildings to clear from
## the top down or to avoid funneling in through the door of compounds"): the named units go to
## `point` (a wall top or a roof), climbing the ledges in their way (SoldierMovement's mantle;
## an exo frame reaches higher), and hold up there.
func order_climb(from: Soldier, point: Vector3, names := PackedStringArray()) -> String:
	leader = from
	var units := _able(names)
	if units.is_empty():
		return "Nobody selected can"
	var side := from.global_basis.x
	side.y = 0.0
	for i in units.size():
		units[i].give_tactic({"kind": &"climb", "point": point + side.normalized() * (i - (units.size() - 1) / 2.0) * 1.0})
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
func order_clear(from: Soldier, point: Vector3, names := PackedStringArray(), breach := "") -> String:
	leader = from
	var b := Buildings.nearest(from, point, ORDER_BUILDING_M)
	if b.is_empty():
		return "Look at a building"
	var units := _able(names)
	if units.is_empty():
		return "Nobody selected can"
	return _start_clear(b, units, breach)


## The stack on building `b` (SquadTactics.clear_op) with `breach` ("", "flash", "frag",
## "charge": SquadAI._breach).
func _start_clear(b: Dictionary, units: Array[SquadAI], breach: String) -> String:
	var op := SquadTactics.clear_op(b, units)
	if op.is_empty():
		return "No way in found"
	op["breach"] = breach
	if breach == "charge":
		stand_off(op)
	for i in units.size():
		units[i].give_tactic({"kind": &"clear", "op": op, "slot": i})
	_town_op = op
	_town_units = units.size()
	return ""


## A charge's stack stands CHARGE_STANDOFF_M further along the wall, clear of the blast.
static func stand_off(op: Dictionary) -> void:
	var door: Vector3 = op.entrance.door
	for i in (op.stack as Array).size():
		var away := Vector3((op.stack[i] as Vector3).x - door.x, 0.0, (op.stack[i] as Vector3).z - door.z)
		if away.length() > 0.05:
			op.stack[i] = (op.stack[i] as Vector3) + away.normalized() * CHARGE_STANDOFF_M


## Clearing a town (Captain, 2026-10-16: "an order for clearing towns so they move building by
## building down the street"): the buildings within TOWN_RADIUS_M of the point, nearest-next
## from the squad, cleared one after another the same way (stack, breach, in); the next starts
## once every man of the last is at his corner. Another clear order ends it.
const TOWN_RADIUS_M := 40.0
const CHARGE_STANDOFF_M := 3.0
var _town: Array = []        # buildings still to clear
var _town_names := PackedStringArray()
var _town_breach := ""
var _town_op: Dictionary = {}
var _town_units := 0


func order_clear_town(from: Soldier, point: Vector3, names: PackedStringArray, breach: String) -> String:
	leader = from
	# Buildings are found on the baked navmesh, which reaches ~48 m round the player (ZoneNav):
	# scan TOWN_RADIUS_M round a point at most that far toward where he points.
	var centre := from.global_position + (point - from.global_position).limit_length(TOWN_RADIUS_M)
	var found: Array = Buildings.near(from, centre, TOWN_RADIUS_M)
	if found.is_empty():
		var one := Buildings.nearest(from, point, 30.0)
		if not one.is_empty():
			found = [one]
	if found.is_empty():
		return "No buildings there: move closer to the town"
	var ordered: Array = []
	var at := from.global_position
	while not found.is_empty():
		found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Buildings.distance_to(a, at) < Buildings.distance_to(b, at))
		var next: Dictionary = found.pop_front()
		ordered.append(next)
		at = next.centre
	_town = ordered
	_town_names = names
	_town_breach = breach
	_town_op = {}
	return _next_town_building()


func _next_town_building() -> String:
	while not _town.is_empty():
		var b: Dictionary = _town.pop_front()
		var units := _able(_town_names)
		if units.is_empty():
			_town.clear()
			return "Nobody selected can"
		if _start_clear(b, units, _town_breach) == "":
			return ""
	_town_op = {}
	return "No way into any building there"


func _tick_town() -> void:
	if _town_op.is_empty() or _town.is_empty():
		return
	if (_town_op.get("done", {}) as Dictionary).size() >= mini(_town_units, _able(_town_names).size()):  # one down mid-clear doesn't stall it
		_town_op = {}
		_next_town_building()


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


## Captain, 2026-10-17 ("add orders for those things"): a squad a player leads no longer flanks
## or assaults by itself (SquadTactics.score), so he orders them. Their base of fire suppresses
## for this long while the rest go.
const ATTACK_BASE_S := 45.0
## Assaulters spread this far apart across the position (not all onto one point).
const ASSAULT_GAP_M := 3.0


## Who an attack order is on: the known enemy cluster nearest `point` (within
## ORDER_ENEMY_M of it), else `point` itself; Vector3.INF for the densest known cluster.
const ORDER_ENEMY_M := 25.0


func _order_enemy(point: Vector3) -> Vector3:
	var found := clusters()
	if not point.is_finite():
		return found[0].centre if not found.is_empty() else Vector3.INF
	for c: Dictionary in found:
		if (c.centre as Vector3).distance_to(point) <= ORDER_ENEMY_M:
			return c.centre
	return point


## The named units split for an attack on `enemy`: [base, moving]. With nobody named, the
## squad's own split (SquadTactics.elements_ai: a fire team or buddy pairs go, the rest and the
## autorifleman stay as the base); with some named (or nobody to spare), the named all go.
func _attack_split(units: Array[SquadAI], enemy: Vector3, named: bool) -> Array:
	if named:
		return [[], units]
	var split := SquadTactics.elements_ai(units, enemy)
	if (split[1] as Array).is_empty():
		return [[], units]
	return split


## "Flank": the base of fire suppresses the enemy at `point` (Vector3.INF: the densest known
## cluster) while the rest work round it through cover on the side it sees least of
## (SquadTactics.flank_route), each in his own lane, and fight from there.
func order_flank(from: Soldier, point: Vector3, names := PackedStringArray()) -> String:
	leader = from
	var enemy := _order_enemy(point)
	if not enemy.is_finite():
		return "No known enemy to flank"
	var units := _able(names)
	if units.is_empty():
		return "Nobody selected can"
	var split := _attack_split(units, enemy, not names.is_empty())
	var moving: Array = split[1]
	var route := SquadTactics.flank_route(moving[0].body, SquadTactics._middle(moving), enemy, null, [])
	if route.is_empty():
		return "No way round found"
	var lanes := SquadTactics.lanes(moving, route.route)
	var aim := enemy + Vector3.UP
	for ai: SquadAI in moving:
		ai.give_tactic({"kind": &"maneuver", "route": lanes.get(ai, route.route), "aim": aim})
	for ai: SquadAI in split[0]:
		ai.give_tactic({"kind": &"base", "aim": aim, "until": Soldier._now() + ATTACK_BASE_S})
	return ""


## "Assault": the base of fire (the autorifleman and his buddy) keeps their heads down while the
## rest bound onto the enemy at `point` (Vector3.INF: the densest known cluster), spread across it.
func order_assault(from: Soldier, point: Vector3, names := PackedStringArray()) -> String:
	leader = from
	var enemy := _order_enemy(point)
	if not enemy.is_finite():
		return "No known enemy to assault"
	var units := _able(names)
	if units.is_empty():
		return "Nobody selected can"
	var base: Array = [] if not names.is_empty() else SquadTactics._gunners_and_buddies(units, enemy)
	var going: Array = units.filter(func(ai: SquadAI) -> bool: return ai not in base)
	if going.is_empty():
		going = units
		base = []
	var map := from.get_world_3d().navigation_map
	var across := Vector3(enemy.x - from.global_position.x, 0.0, enemy.z - from.global_position.z).normalized().cross(Vector3.UP)
	var aim := enemy + Vector3.UP
	for i in going.size():
		var p := NavigationServer3D.map_get_closest_point(map, enemy + across * (i - (going.size() - 1) / 2.0) * ASSAULT_GAP_M)
		(going[i] as SquadAI).give_tactic({"kind": &"assault", "point": p})
	for ai: SquadAI in base:
		ai.give_tactic({"kind": &"base", "aim": aim, "until": Soldier._now() + ATTACK_BASE_S})
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
##  faster); pick_packs: each goes back for his own. exo_in: each selected walks to the nearest
##  free HX-1 standing or lying within EXO_FIND_M (one each) and climbs in (ExoMech: certified
##  only, on a campaign); exo_out: those piloting one climb out.
func order_command(from: Soldier, cmd: String, point: Vector3, names := PackedStringArray()) -> String:
	var parts := cmd.split(":", true, 1)
	var arg := parts[1] if parts.size() > 1 else ""
	match parts[0]:
		"suppress":
			return order_suppress(from, Vector3.INF if arg == "known" else point, names)
		"bound":
			return order_bound(from, point, names)
		"flank":
			return order_flank(from, Vector3.INF if arg == "known" else point, names)
		"assault":
			return order_assault(from, Vector3.INF if arg == "known" else point, names)
		"climb":
			return order_climb(from, point, names)
		"garrison":
			return order_garrison(from, point, names)
		"clear":
			_town.clear()
			return order_clear(from, point, names, arg)
		"clear_town":
			return order_clear_town(from, point, names, arg)
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
		"exo_in":
			return order_exo_in(from, names)
		"exo_out":
			var piloting := _able(names).filter(func(ai: SquadAI) -> bool: return ExoMech.exit_problem(ai.body) == "")
			for ai: SquadAI in piloting:
				ExoMech.server_exit(ai.body)
			return "" if not piloting.is_empty() else "Nobody selected is in a suit"
		"ccp":
			ccp = point
			hold_casualties = false
			return ""
		"ccp_me":
			ccp = from
			hold_casualties = false
			return ""
		"ccp_off":
			ccp = null
			hold_casualties = true
			for s in members():
				var ai := SquadAI.of(s)
				if ai:
					ai._think_cd = 0.0  # carriers put them down now, not at their next think
			return ""
	return "?"


## "Climb into the HX-1" (Captain, 2026-10-17/18: AI pilots for the heavy exo): each selected
## unit that could climb into one (ExoMech.enter_problem, distance aside: certified on a
## campaign, hands free, not in a suit or vehicle) takes the nearest free HX-1 parked within
## EXO_FIND_M, one suit each, walks to it and climbs in (SquadAI "exo_in").
func order_exo_in(from: Soldier, names: PackedStringArray) -> String:
	leader = from
	var suits: Array[WorldItem] = []
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var w := node as WorldItem
		if w and not w.is_queued_for_deletion() and ExoMech.is_mech(ItemDB.get_item(w.item_id)):
			suits.append(w)
	var why := "No HX-1 within %d m" % int(EXO_FIND_M)
	var sent := 0
	for ai: SquadAI in _able(names):
		var best: WorldItem = null
		for w in suits:
			var d := ExoMech.parked_point(w).distance_to(ai.body.global_position)
			if d <= EXO_FIND_M and (best == null or d < ExoMech.parked_point(best).distance_to(ai.body.global_position)):
				best = w
		if best == null:
			continue
		var problem := ExoMech.enter_problem(ai.body, best, false)
		if problem != "":
			why = "%s: %s" % [ai.body.display_name(), problem]
			continue
		suits.erase(best)
		ai.give_tactic({"kind": &"exo_in", "uid": best.uid})
		sent += 1
	return "" if sent > 0 else why


## "Give me ammo": the nearest selected unit carrying magazines of `from`'s weapon (one not
## busy with a casualty or his own wounds, if there is one) brings him some.
func order_give_ammo(from: Soldier, names: PackedStringArray) -> String:
	## Down, he can't take them: before, the order went out and the bringer dropped it on
	## arrival (_tactic_give_ammo ends for a casualty), with no word why.
	if not from.vitals.is_up():
		return "Not while you're down"
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


## The command-menu commands with an argument: "formation:<name>" and "spacing:<level>" (each
## also "dynamic"), "target:<enemy name>"
## ("target:" clears it), "mode:<combat mode>" and "team:<colour>", and the tactic orders
## (TACTIC_COMMANDS) on `point`. False if the command or its argument isn't valid, or the
## order couldn't be given.
func command(from: Soldier, cmd: String, point: Vector3, names := PackedStringArray()) -> bool:
	var parts := cmd.split(":", true, 1)
	var arg := parts[1] if parts.size() > 1 else ""
	match parts[0]:
		"formation":
			return set_formation(from, "formation", arg, names)
		"spacing":
			return set_formation(from, "spacing", arg, names)
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


# --- Formation and spacing ----------------------------------------------------------------

## Command menu "Formation" / "Spacing" (Captain, 2026-10-14: "so long as I can set them to be
## dynamic"): `kind` "formation" (FORMATION_NAMES) or "spacing" (SPACINGS), each also DYNAMIC.
## The named units' fire teams take it; the whole squad (or nobody named) sets the squad's own
## and clears the fire teams' orders. It stands until changed. The named squadmate nearest the
## one ordering acknowledges it ("Copy, wedge, wide"). False for a value that isn't one.
func set_formation(from: Soldier, kind: String, value: String, names := PackedStringArray()) -> bool:
	var allowed: Array = FORMATION_NAMES if kind == "formation" else (SPACINGS.keys() if kind == "spacing" else [])
	if allowed.is_empty() or (value != DYNAMIC and value not in allowed):
		return false
	leader = from
	var units := pick(names)
	var teams := {}
	for s in units:
		teams[s.fire_team if s.fire_team >= 0 else 0] = true
	var all_teams := {}
	for s in members():
		all_teams[s.fire_team if s.fire_team >= 0 else 0] = true
	if names.is_empty() or teams.size() >= all_teams.size():
		set(kind, value)
		for t: int in team_orders.keys():
			(team_orders[t] as Dictionary).erase(kind)
	else:
		for t: int in teams:
			if not team_orders.has(t):
				team_orders[t] = {}
			team_orders[t][kind] = value
	_slots_frame = -1
	if not units.is_empty():
		units.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.global_position.distance_to(from.global_position) < b.global_position.distance_to(from.global_position))
		var who := units[0]
		var callouts := Callouts.of(who)
		var line := acknowledgement(who.fire_team)
		if callouts:
			callouts.say(who, &"tactic", line, "formation:" + line)
	return true


## The formation and spacing ordered for fire team `team` (its own order, else the squad's;
## either may be DYNAMIC).
func ordered_formation(team: int) -> String:
	return String((team_orders.get(team, {}) as Dictionary).get("formation", formation))


func ordered_spacing(team: int) -> String:
	return String((team_orders.get(team, {}) as Dictionary).get("spacing", spacing))


## What fire team `team` keeps now: {"formation", "spacing", "man", "team", "dynamic": bool}.
func resolved(team: int) -> Dictionary:
	var f := ordered_formation(team)
	var sp := ordered_spacing(team)
	var dynamic := f == DYNAMIC or sp == DYNAMIC
	if f == DYNAMIC:
		f = String(context.formation)
	if sp == DYNAMIC:
		sp = String(context.spacing)
	var gaps: Dictionary = SPACINGS.get(sp, SPACINGS["normal"])
	return {"formation": f, "spacing": sp, "man": float(gaps.man), "team": float(gaps.team), "dynamic": dynamic}


## "Copy, wedge, wide"; a dynamic choice says so: "Copy, dynamic (wedge), wide".
func acknowledgement(team: int) -> String:
	var r := resolved(team)
	var f := ordered_formation(team)
	var sp := ordered_spacing(team)
	return "Copy, %s, %s" % ["dynamic (%s)" % r.formation if f == DYNAMIC else f, "dynamic (%s)" % r.spacing if sp == DYNAMIC else sp]


## The squad HUD's word on a following squadmate's formation: "wedge, wide", or "dynamic:
## wedge, normal" when the squad picks either.
func formation_text(team: int) -> String:
	var r := resolved(team)
	return "%s%s, %s" % ["dynamic: " if r.dynamic else "", r.formation, r.spacing]


## The heading follows the lead's travel (HEADING_STEP_M); _update_context turns it to face the
## enemy in contact.
func _update_heading() -> void:
	if leader == null or not is_instance_valid(leader) or not leader.is_inside_tree():
		return
	var at := leader.global_position
	if heading == Vector3.ZERO or not _heading_from.is_finite():
		var f := -leader.global_basis.z
		f.y = 0.0
		heading = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
		_heading_from = at
		return
	var moved := Vector3(at.x - _heading_from.x, 0.0, at.z - _heading_from.z)
	if moved.length() >= HEADING_STEP_M:
		var blended := heading.lerp(moved.normalized(), HEADING_BLEND)
		heading = blended.normalized() if blended.length() > 0.3 else moved.normalized()  # (turned right round)
		_heading_from = at


## Dynamic: what the squad keeps where it is now (context). Spacing tight in a town, normal in
## the open, wide in the open in contact, a step tighter in low visibility; a staggered column
## in a town, a column on a road, a line in contact in the open, else a wedge. In contact the
## formation faces the enemy.
func _update_context() -> void:
	if leader == null or not is_instance_valid(leader) or not leader.is_inside_tree():
		return
	var at := leader.global_position
	var grid := Vector3(snappedf(at.x, TOWN_GRID_M), at.y, snappedf(at.z, TOWN_GRID_M))
	var town := Buildings.has_near(leader, grid, TOWN_M)
	var road := false
	var level := CompoundLevel.current(leader)
	var terrain: Variant = level.get(&"terrain") if level and &"terrain" in level else null
	if terrain is Object and is_instance_valid(terrain) and (terrain as Object).has_method(&"road_weight"):
		road = float(terrain.road_weight(at.x, at.z)) >= ROAD_WEIGHT
	var contact := is_engaged()
	var threat := Vector3.INF
	for ai in brains():
		if ai.in_contact():
			contact = true
			threat = ai.body.threat_pos
			break
	if contact:
		var found := clusters()
		if not found.is_empty():
			threat = found[0].centre
	var dark := _low_visibility()
	var step := 0 if town else (2 if contact else 1)
	if dark:
		step = maxi(step - 1, 0)
	var why := PackedStringArray(["town" if town else "open ground"])
	if road and not town:
		why.append("road")
	if contact:
		why.append("contact")
	if dark:
		why.append("low visibility")
	_slots_frame = -1  # the slots change with it
	context = {"formation": "staggered column" if town else ("line" if contact else ("column" if road else "wedge")),
		"spacing": SPACING_ORDER[step], "why": ", ".join(why)}
	if contact and threat.is_finite():
		var to := Vector3(threat.x - at.x, 0.0, threat.z - at.z)
		if to.length() > 1.0:
			heading = to.normalized()
			_heading_from = at


## Low visibility (night, thick weather) closes the spacing up a step. The zones have no night
## yet (day and night come with wave 7): a level with `low_visibility` set true gets it.
func _low_visibility() -> bool:
	var level := CompoundLevel.current(leader) if leader and leader.is_inside_tree() else null
	if level == null or not &"low_visibility" in level:
		return false
	return bool(level.get(&"low_visibility"))


## A fire team's formation in its own space (x right, +z behind, metres): man `k` (0, the team
## leader, at the origin) with `gap` metres between men. Each man stands at least `gap` from
## the others (Captain, 2026-10-14: they bunched up).
static func team_shape(kind: String, k: int, gap: float) -> Vector3:
	var side := -1.0 if k % 2 == 1 else 1.0  # odd to the left, even to the right
	var depth := floorf((k + 1) / 2.0)
	match kind:
		"line":
			return Vector3(side * depth * gap, 0.0, 0.0)
		"file":
			return Vector3(0.0, 0.0, k * gap)
		"staggered column":
			return Vector3((0.0 if k % 2 == 0 else -0.7) * gap, 0.0, k * 0.75 * gap)
		"column":
			return Vector3((0.0 if k % 2 == 0 else -1.0) * gap, 0.0, floorf(k / 2.0) * gap)
	return Vector3(side * depth * 0.7 * gap, 0.0, depth * 0.7 * gap)  # wedge


## Where the second fire team's leader stands in the lead's space, for formation `kind` with
## `gap` between men and `team_gap` between the teams, `lead_count` men in the lead's team. A
## wedge puts it back and to the right, a line beside it (its men out to the right), the
## columns and files behind.
static func team_offset(kind: String, gap: float, team_gap: float, lead_count: int) -> Vector3:
	match kind:
		"line":
			return Vector3(2.0 * gap + maxf(team_gap * 0.5, gap), 0.0, 0.0)
		"file", "staggered column", "column":
			return Vector3(0.0, 0.0, team_shape(kind, maxi(lead_count - 1, 0), gap).z + maxf(team_gap * 0.5, gap))
	return Vector3(0.6 * team_gap, 0.0, 0.8 * team_gap)


## Where `member` stands when following: its own formation slot in its fire team (Captain,
## 2026-10-14: they bunched up; before, all seven took one tight wedge within 7 m of the lead,
## 2.5 m apart). The lead's team forms on the lead; the other team on its team leader (its
## first man up, while he follows), who keeps his place off the lead (team_offset). Slots go by
## squad slot, so a man keeps his place when another goes down, and lie on the navmesh.
func follow_point(member: Soldier) -> Vector3:
	if leader == null or not is_instance_valid(leader):
		return member.global_position
	var frame := Engine.get_physics_frames()
	if frame != _slots_frame or not _slots.has(member):
		_slots = _work_out_slots()
		_slots_frame = frame
	return _slots.get(member, member.global_position)


## The squad as it stands this frame, the lead and players too (who squadmates keep apart from,
## SquadAI._apart).
func neighbours() -> Array:
	if leader == null or not is_instance_valid(leader):
		return members()
	if Engine.get_physics_frames() != _slots_frame:
		_slots = _work_out_slots()
		_slots_frame = Engine.get_physics_frames()
	return _slots.keys() + [leader]


## Every member's formation slot now: {Soldier: Vector3}.
func _work_out_slots() -> Dictionary:
	var out := {}
	if heading == Vector3.ZERO:
		_update_heading()
	var fwd := heading if heading != Vector3.ZERO else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	var lead_team := leader.fire_team if leader.fire_team >= 0 else 0
	var everyone: Array[Soldier] = members()
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var p := n as Soldier
		if p and not p.is_ai() and p.faction == faction and p.squad_slot >= 0 and not p.is_queued_for_deletion() and not p.vitals.is_dead():
			everyone.append(p)
	if leader not in everyone:
		everyone.append(leader)
	var teams := {}  # team -> [Soldier], by squad slot (the lead first in his)
	for s in everyone:
		var t := s.fire_team if s.fire_team >= 0 else lead_team
		if s == leader:
			t = lead_team
		if not teams.has(t):
			teams[t] = []
		(teams[t] as Array).append(s)
	for t: int in teams:
		var list: Array = teams[t]
		list.sort_custom(func(a: Soldier, b: Soldier) -> bool:
			if a.squad_slot != b.squad_slot:
				return (a.squad_slot if a.squad_slot >= 0 else 99) < (b.squad_slot if b.squad_slot >= 0 else 99)
			return String(a.name) < String(b.name))
	(teams[lead_team] as Array).erase(leader)
	(teams[lead_team] as Array).push_front(leader)
	var lead_count: int = (teams[lead_team] as Array).size()
	var map := leader.get_world_3d().navigation_map
	var lead_r := resolved(lead_team)
	var others: Array = teams.keys().filter(func(t: int) -> bool: return t != lead_team)
	var slots: Array[Dictionary] = []  # every man's wanted slot, in team and squad-slot order
	others.sort()
	for t: int in [lead_team] + others:
		var list: Array = teams[t]
		var r := lead_r if t == lead_team else resolved(t)
		var gap: float = r.man
		var mirror := 1.0
		var origin := leader.global_position
		var guide: Soldier = null
		if t != lead_team:
			var place := team_offset(String(lead_r.formation), float(lead_r.man), float(lead_r.team), lead_count)
			place.z += others.find(t) * float(lead_r.team) * 0.8  # a third team (more players' AI) further back
			origin = leader.global_position + right * place.x - fwd * place.z
			if String(lead_r.formation) == "line":
				mirror = -1.0  # the second team's men out to the right, away from the lead's
			if place.x != 0.0 and map.is_valid() and _flat(NavigationServer3D.map_get_closest_point(map, origin), origin) > gap:
				# No ground there (the sea, a cliff, the map's edge): the other side, rather than
				# the whole team on the one spot nearest it.
				var other := leader.global_position - right * place.x - fwd * place.z
				if _flat(NavigationServer3D.map_get_closest_point(map, other), other) < _flat(NavigationServer3D.map_get_closest_point(map, origin), origin):
					origin = other
					mirror = -mirror
			if _blocked(leader.global_position, origin, "team%d" % t):
				# Its place is across a wall: the other side if that's clear, else back on the
				# lead's trail about as far as the place is behind him.
				var flip := leader.global_position - right * place.x - fwd * place.z
				if place.x != 0.0 and not _wall_between(leader.global_position, flip):
					origin = flip
					mirror = -mirror
				else:
					var back: Variant = _trail_point(maxf(place.z, place.length() * 0.5))
					origin = back if back != null else _pulled(leader.global_position, origin)
		if t != lead_team:
			for s: Soldier in list:
				if s.vitals.is_up():
					guide = s
					break
		var t_right := right
		var t_fwd := fwd
		if guide != null and t != lead_team and not guide.is_ai():
			# A human team leader anchors his own team: it forms on him, headed the way he
			# moves (or faces), wherever the squad lead is.
			origin = guide.global_position
			mirror = 1.0
			t_fwd = _human_heading(guide, fwd)
			t_right = t_fwd.cross(Vector3.UP).normalized()
		elif guide != null and t != lead_team:
			# The lead ordered this team's AI leader somewhere (Captain, 2026-10-16: "make sure i can
			# command the tl for b team and b team follows"): the team goes with him and forms on
			# him there, the way it forms on a human team leader, not back on the squad lead.
			var ordered := SquadAI.of(guide)
			if ordered and ordered.intent in [SquadAI.Intent.MOVE_TO, SquadAI.Intent.HOLD]:
				origin = guide.global_position
				mirror = 1.0
				t_fwd = _human_heading(guide, fwd)
				t_right = t_fwd.cross(Vector3.UP).normalized()
		var guide_k := list.find(guide)
		var guide_ai := SquadAI.of(guide) if guide and guide.is_ai() else null
		# The team forms on its own leader while he's with it (following, off his place by more
		# than a man's gap but within the team's): it keeps with him when he's held up or
		# pushed round; at his place (or his halt spot by it) the slots stay put.
		var guide_off := _flat(guide.global_position, origin) if guide else 0.0
		var on_guide := guide_ai != null and guide_ai.intent == SquadAI.Intent.FOLLOW and guide_off > gap and guide_off < float(r.team)
		var g_local := Vector3.ZERO
		if guide != null:
			g_local = team_shape(String(r.formation), guide_k, gap)
			g_local.x *= mirror
		for k in list.size():
			var s: Soldier = list[k]
			if s == leader:
				continue
			var local := team_shape(String(r.formation), k, gap)
			local.x *= mirror
			var base := origin
			if guide != null:
				local -= g_local
				base = guide.global_position if on_guide and k != guide_k else origin
			var want := base + t_right * local.x - t_fwd * local.z
			slots.append({"who": s, "base": base, "want": want, "gap": gap, "blocked": _blocked(base, want, s),
				"right": t_right, "fwd": t_fwd})
	# The lead and the players stand where they stand: nobody's slot on them.
	var people: Array[Vector3] = [leader.global_position]
	for s in everyone:
		if s != leader and not s.is_ai():
			people.append(s.global_position)
	var taken: Array[Vector3] = []
	var refit: Array[Dictionary] = []
	for e: Dictionary in slots:
		var p: Vector3 = e.want
		if e.blocked or _near_any(p, people, LEAD_CLEAR_M) or _near_any(p, taken, SLOT_STACK_M):
			refit.append(e)
			continue
		_refits.erase((e.who as Soldier).get_instance_id())
		taken.append(p)
		out[e.who] = p
	for e: Dictionary in refit:
		var p := _refit(e, e.right, e.fwd, people, taken)
		taken.append(p)
		out[e.who] = p
	for s: Soldier in out:
		var p: Vector3 = out[s]
		out[s] = NavigationServer3D.map_get_closest_point(map, p) if map.is_valid() else p
	out.erase(leader)
	return out


## The way a human team leader is heading: his horizontal velocity when he's moving, else the
## way he faces, else `fallback`.
func _human_heading(who: Soldier, fallback: Vector3) -> Vector3:
	var v := Vector3(who.velocity.x, 0.0, who.velocity.z) if "velocity" in who else Vector3.ZERO
	if v.length() > 1.0:
		return v.normalized()
	var f := -who.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.1 else fallback


## A slot picked again on open ground (SLOT_APART_MIN_M above): its mirror across the team's
## line if nothing stands between it and where the team forms (`e.base`), else the first point
## back along the lead's trail from about as far back as the slot was, clear of the lead, the
## players and the other slots. Each man keeps his last pick while it still does, so a slot
## doesn't hop between the two. Past the trail's end (the lead has only just set off): the near
## side of the wall, as before, but never on the lead.
func _refit(e: Dictionary, right: Vector3, fwd: Vector3, people: Array[Vector3], taken: Array[Vector3]) -> Vector3:
	var who: Soldier = e.who
	var base: Vector3 = e.base
	var want: Vector3 = e.want
	var apart := maxf(SLOT_APART_MIN_M, SLOT_APART_MULT * float(e.gap))
	var id := who.get_instance_id()
	var was: Dictionary = _refits.get(id, {})
	var ok := func(p: Vector3) -> bool:
		return not _near_any(p, people, LEAD_CLEAR_M) and not _near_any(p, taken, apart)
	var side := (want - base).dot(right)
	var mirrored := want - right * (2.0 * side)
	var mirror_ok := bool(e.blocked) and absf(side) > 0.5
	if String(was.get("kind", "")) == "trail":
		var held: Variant = _trail_point(float(was.s))
		if held != null and ok.call(held):
			return held
	if mirror_ok and ok.call(mirrored) and not _wall_between(base, mirrored):
		_refits[id] = {"kind": "mirror"}
		return mirrored
	var from := maxf(_flat(leader.global_position, want), apart)
	var step := 0.0
	while step < 40.0:
		var p: Variant = _trail_point(from + step)
		if p == null:
			break
		if ok.call(p):
			_refits[id] = {"kind": "trail", "s": from + step}
			return p
		step += TRAIL_STEP_M
	_refits.erase(id)
	var pulled := _pulled(base, want) if bool(e.blocked) else want
	if _near_any(pulled, people, LEAD_CLEAR_M):
		pulled = leader.global_position - fwd * maxf(apart, LEAD_CLEAR_M)  # never on the lead
	return pulled


static func _near_any(p: Vector3, points: Array[Vector3], within: float) -> bool:
	for q in points:
		if _flat(p, q) < within:
			return true
	return false


## The lead's trail: where he has walked, a point each TRAIL_STEP_M (the last TRAIL_MAX).
func _update_trail() -> void:
	if leader == null or not is_instance_valid(leader) or not leader.is_inside_tree():
		return
	var at := leader.global_position
	if not _trail.is_empty():
		var last := _trail[_trail.size() - 1]
		var d := _flat(last, at)
		if d > TRAIL_JUMP_M or absf(last.y - at.y) > TRAIL_JUMP_M:
			_trail.clear()
		elif d < TRAIL_STEP_M:
			return
	_trail.append(at)
	if _trail.size() > TRAIL_MAX:
		_trail.remove_at(0)


## The point `metres` back along the lead's trail from where he stands now, or null past its end.
func _trail_point(metres: float) -> Variant:
	if leader == null or not is_instance_valid(leader):
		return null
	var at := leader.global_position
	var left := metres
	for i in range(_trail.size() - 1, -1, -1):
		var p := _trail[i]
		var seg := _flat(at, p)
		if seg >= left and seg > 0.001:
			return at.lerp(p, left / seg)
		left -= seg
		at = p
	return null


## Whether a wall or building stands between `from` (where a team forms) and `to` (a slot): a
## slot is never across a wall from the lead (Captain, 2026-10-14: with wider spacing, slots
## fell inside compounds the lead walked past, and men went round for them). Each slot (`key`)
## keeps its answer for SIDE_HOLD_S: walking past a doorway, the line through it opens and
## shuts, and a slot flipping between the room and this side of its wall had a man running in
## and out (casualty soak, Charlie in the compound's building). But a clear answer is never
## held for a slot that has gone behind a wall from the lead himself: the lead turning the
## corner by the compound's back wall put the second team's place outside it, and then Golf's
## slot, each held there for SIDE_HOLD_S in turn, and Golf set off round by the gate (casualty
## soak "stuck" on CI; at the soak's 3x time scale the real-time hold is 6 s of game time).
func _blocked(from: Vector3, to: Vector3, key: Variant) -> bool:
	var now := Soldier._now()
	var blocked := _wall_between(from, to)
	var was: Dictionary = _sides.get(key, {})
	if was.is_empty() or bool(was.pulled) == blocked or now - float(was.since) >= SIDE_HOLD_S \
			or (blocked and _wall_between(leader.global_position, to)):
		if was.is_empty() or bool(was.pulled) != blocked:
			_sides[key] = {"pulled": blocked, "since": now}
		return blocked
	return bool(was.pulled)  # held to the side it was on


func _wall_between(from: Vector3, to: Vector3) -> bool:
	if from.distance_to(to) < 0.5:
		return false
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP, to + Vector3.UP, SquadAI.WORLD_MASK)
	return not leader.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## The near side of whatever stands between `from` and `to`, WALL_CLEAR_M off it (or `to`).
func _pulled(from: Vector3, to: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP, to + Vector3.UP, SquadAI.WORLD_MASK)
	var hit := leader.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	var back := Vector3(from.x - to.x, 0.0, from.z - to.z).normalized()
	var at: Vector3 = hit.position
	return Vector3(at.x, to.y, at.z) + back * WALL_CLEAR_M


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
