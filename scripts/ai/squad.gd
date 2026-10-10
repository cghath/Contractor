class_name Squad
extends Node
## Host-side command state for one faction's AI. Friendly squadmates follow a lead player
## (the host by default). Any player can give orders from the command menu, which also makes
## them the lead; orders go to the units they selected. Hostile squads use the same node for
## their patrol route.
##
## The friendly squad is two fire teams of four (Roles); CompoundLevel.rebalance_squad sets
## each soldier's role, fire team and slot. Commands here: movement orders, hold/open fire,
## throws, formation, Target (focus fire), Combat mode and Team (colour teams).

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
## Heights on a soldier (m above their feet) checked for a line of sight to them.
const SIGHT_HEIGHTS: Array[float] = [1.7, 1.4, 1.0, 0.5]
## Proposed: once any member is fired upon, the whole squad counts as engaged this long
## (units in Safe or Stealth hold fire until then).
const ENGAGED_S := 20.0

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


## The squad's AI soldiers, in squad-slot order (then by name).
func members() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.is_ai() and s.faction == faction and not s.is_queued_for_deletion():
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


## The command-menu commands with an argument: "formation:<name>", "target:<enemy name>"
## ("target:" clears it), "mode:<combat mode>" and "team:<colour>". False if the command
## or its argument isn't valid.
func command(from: Soldier, cmd: String, _point: Vector3, names := PackedStringArray()) -> bool:
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
		"mode":
			return COMBAT_MODES.has(arg) and set_combat_mode(from, COMBAT_MODES[arg], names)
		"team":
			return assign_color(from, arg, names)
	return false


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
