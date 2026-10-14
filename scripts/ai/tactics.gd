class_name SquadTactics
extends RefCounted
## The squad's tactical evaluator (Captain, P0164 queue 17 core: reactions must feel natural,
## the situation decides). Host only: Squad thinks with it every THINK_S, on both sides.
##
## It reads the situation (assess): the squad's picture of the enemy (Squad.known: where each
## enemy was last seen or heard and how long ago, in clusters), the range to the densest
## cluster, a building the enemy holds and one by the squad (Buildings), how pinned the squad
## is, how much of it is in cover, its casualties, ammunition and morale, and its units'
## orders. Then it scores the options (score) and keeps the best, with hysteresis: another
## option has to beat the current one by HYSTERESIS, and nothing changes within MIN_KEEP_S
## unless the current option stops applying. Every change prints a "[tactics]" line: the
## squad, the option, the top scores and why.
##
## The options, and what the units do for each (SquadAI.task):
## - Hold and improve cover: everyone fights from the best cover near their order's anchor
##   and moves to better cover when it turns up (bounding with the buddy); the autorifleman
##   suppresses the densest known cluster.
## - Suppress and flank, the contact drill: the base of fire (the fire team nearer the enemy,
##   with the autorifleman whatever his team) suppresses the densest cluster while the
##   maneuver element (the other fire team, or the other buddy pairs) works round through
##   cover on the side the enemy can see least of (flank_route).
## - Assault: the base keeps their heads down while the rest bound onto the position.
## - Clear the building the enemy holds: the base suppresses it until the entry team goes in;
##   the entry team stacks beside the entrance, then goes in one after the other, pair by
##   pair, room by room (clear_op).
## - Defend a building: take its window and door positions, those facing the threat first,
##   the rest inside (garrison_tasks).
## - Break contact: bound back by pairs, smoke over open ground, to a point away from the enemy
##   (friendlies following their lead: behind the lead).
## - Casualty care: everyone not looking after the casualty holds and suppresses the threat;
##   SquadAI's casualty care does the rest.
## - Search last known (positions known but stale): hostile pairs search round where the enemy
##   was last seen; friendlies watch that way. After SEARCH_S with nothing found the squad
##   forgets them.
## Orders always win, executed sensibly: a unit on Hold reacts only within its hold leash (cover
## and suppression, never a flank or an assault), a unit on Move keeps moving, a squad
## following its lead keeps every move within FOLLOW_LEASH_M of him, and a squad on hold fire
## doesn't start a flank, an assault or a clearance. A unit with a command-menu tactic order
## (SquadAI.ordered) keeps to that. Hostile squads use it too, with their own doctrine
## (DOCTRINES), and a hot zone's enemy coordination (EnemyResponse.coordination) makes them
## flank less. Every number is proposed, for Captain's playtests.

enum Option { NONE, HOLD, SUPPRESS_FLANK, ASSAULT, CLEAR, DEFEND, BREAK_CONTACT, CASUALTY, SEARCH }

const OPTION_NAMES := {
	Option.NONE: "carry on", Option.HOLD: "hold and improve cover", Option.SUPPRESS_FLANK: "suppress and flank",
	Option.ASSAULT: "assault", Option.CLEAR: "clear the building", Option.DEFEND: "defend the building",
	Option.BREAK_CONTACT: "break contact", Option.CASUALTY: "casualty care", Option.SEARCH: "search last known",
}
## What the squad leader calls out when the squad takes up an option (the friendly side hears it).
const CALLS := {
	Option.HOLD: "Get in cover, hold here!", Option.SUPPRESS_FLANK: "Base of fire, suppress! %s, flank %s!",
	Option.ASSAULT: "Assault through!", Option.CLEAR: "Stack up on that building!", Option.DEFEND: "Into the building, take the windows!",
	Option.BREAK_CONTACT: "Break contact! Fall back!", Option.CASUALTY: "Cover the casualty!",
}

const THINK_S := 1.0
const HYSTERESIS := 0.1
const MIN_KEEP_S := 3.0
## The contact drill wants this many up and the enemy between FLANK_MIN_M and FLANK_MAX_M.
const FLANK_MIN_UP := 3
const FLANK_MIN_M := 20.0
const FLANK_MAX_M := 250.0
## The flank: round to FLANK_ANGLE_DEG off the line from the enemy to the squad, FLANK_RANGE
## times the range from him (FLANK_NEAR_M to FLANK_FAR_M), by way of a point FLANK_MID_DEG
## round at the range the squad is at now.
const FLANK_ANGLE_DEG := 75.0
const FLANK_MID_DEG := 35.0
const FLANK_RANGE := 0.7
const FLANK_NEAR_M := 15.0
const FLANK_FAR_M := 45.0
## A planned point counts when the navmesh is within PLAN_SNAP_M of it and a path reaches it.
const PLAN_SNAP_M := 4.0
## Following its lead, the squad's tactical moves stay this close to him.
const FOLLOW_LEASH_M := 30.0
## The plan is drawn again when the cluster it's against has moved this far.
const REPLAN_M := 8.0
const ASSAULT_M := 35.0
const ASSAULT_RATIO := 2.0
const CLEAR_M := 60.0
const CLEAR_RATIO := 1.5
## A building this close to the squad's middle can be defended.
const DEFEND_M := 20.0
## Breaking contact: to BREAK_M from the enemy, or (friendlies following their lead)
## BREAK_BEHIND_LEAD_M behind the lead; pairs BREAK_SPREAD_M apart.
const BREAK_M := 35.0
const BREAK_BEHIND_LEAD_M := 10.0
const BREAK_SPREAD_M := 2.5
## Morale under MORALE_LOW and ammunition under AMMO_LOW (a share of AMMO_FULL_MAGS magazines)
## count against fighting on.
const MORALE_LOW := 0.45
const AMMO_LOW := 0.3
const AMMO_FULL_MAGS := 5.0
## The stack beside an entrance: STACK_OUT_M out from the doorway, the first man STACK_FIRST_M
## along the wall from its middle and the rest STACK_GAP_M apart; once all are within
## STACK_READY_M of their places (or STACK_WAIT_S after the first got there) they go in one
## after the other, ENTRY_GAP_S apart.
const STACK_OUT_M := 0.6
const STACK_FIRST_M := 1.1
const STACK_GAP_M := 0.9
const STACK_READY_M := 1.0
const STACK_WAIT_S := 8.0
const ENTRY_GAP_S := 1.2
## The entry team: at most this many (two pairs); the rest stay outside with the base.
const ENTRY_MAX := 4
## Floor by floor (F-01): a floor's done once every man is at his corner on it, or
## FLOOR_WAIT_S after the first got to his; then they go up the stair one after the other,
## ENTRY_GAP_S apart (a stair is a chokepoint).
const FLOOR_WAIT_S := 8.0
## Garrisoning: a port above the ground floor scores HIGH_PORT_BONUS more (it sees further), a
## roof's parapet ROOF_PORT_BONUS (overwatch); with GARRISON_DOOR_MIN or more men, one of the
## first two takes a door.
const HIGH_PORT_BONUS := 0.25
const ROOF_PORT_BONUS := 0.35
const GARRISON_DOOR_MIN := 3
## Searching: pairs go SEARCH_RING_M round the last known position.
const SEARCH_RING_M := 8.0
const SEARCH_S := 45.0
## A squad's way of fighting (Doctrine ids: the squad's, else its side's): added to the option
## scores. Contractors fight the drill and look after their own; regulars flank readily;
## insurgents rush, hole up and melt away, and leave their wounded.
const DOCTRINES := {
	Doctrine.PMC: {"flank": 0.05, "assault": 0.0, "clear": 0.0, "defend": 0.0, "break": 0.0, "casualty": 0.05, "search": 0.0},
	Doctrine.REGULAR: {"flank": 0.08, "assault": 0.03, "clear": 0.03, "defend": 0.03, "break": -0.03, "casualty": 0.0, "search": 0.05},
	Doctrine.INSURGENT: {"flank": -0.1, "assault": 0.08, "clear": -0.05, "defend": 0.1, "break": 0.05, "casualty": -0.15, "search": 0.1},
}
## Hostile squads in a hot zone flank this much less at no coordination (EnemyResponse).
const UNCOORDINATED_FLANK := 0.3

var squad: Squad
var option := Option.NONE
var option_score := 0.0
## When the current option was taken up (Soldier._now()).
var since := -1000.0
## The last assessment and scores (tests and the logs read them).
var situation := {}
var scores := {}
## The current option's plan: who is in which element, the flank route, the clearance.
var plan := {}


func _init(p_squad: Squad) -> void:
	squad = p_squad


## One think: assess, score, keep or change the option (logging the change), and hand out tasks.
func think(now: float) -> void:
	situation = assess()
	var result := score(situation, doctrine())
	scores = result.scores
	var best := option
	var best_score := -1.0
	for o: Option in scores:
		if float(scores[o]) > best_score:
			best = o
			best_score = scores[o]
	var current: float = scores.get(option, -1.0)
	if best != option and (current < 0.0 or (best_score >= current + HYSTERESIS and now - since >= MIN_KEEP_S)):
		var was := option
		option = best
		since = now
		plan = {}
		_log(was, String(result.why.get(best, "")))
		_call_option()
	option_score = scores.get(option, 0.0)
	_carry_out(now)


## This squad's doctrine (DOCTRINES), with a hot zone's enemy coordination taken into
## account for hostile squads.
func doctrine() -> Dictionary:
	var name := squad.doctrine
	if name == &"":
		name = Doctrine.default_for(squad.faction)
	var d: Dictionary = DOCTRINES.get(name, DOCTRINES[Doctrine.PMC]).duplicate()
	if squad.faction != &"friendly" and squad.is_inside_tree():
		var response := EnemyResponse.of(squad)
		if response:
			d.flank = float(d.flank) - UNCOORDINATED_FLANK * (1.0 - response.coordination())
	return d


# --- Assessing ----------------------------------------------------------------------------

## The situation as score() reads it: "up" and "down" (the squad's AI, and for the friendly
## squad its players in slots), "contact", "known" (enemies known within Squad.STALE_S),
## "fresh" (one seen within Squad.FRESH_S), "stale" (known, none fresh), "cluster" (the densest,
## see Squad.clusters) and "range" to it, "enemy_building" (the building it's in), "home_building"
## (one by the squad) and "in_home", averages of "suppression", "morale" and "ammo", "cover"
## (the share in cover), the units' "order" (most of them; -1 for a hostile squad),
## "weapons_free", "centre" and "lead" (friendlies: the squad leader, or null).
func assess() -> Dictionary:
	var sit := {"up": 0, "down": 0, "contact": false, "known": 0, "fresh": false, "stale": false, "cluster": {}, "range": INF,
		"enemy_building": {}, "home_building": {}, "in_home": false, "suppression": 0.0, "morale": 1.0, "ammo": 1.0, "cover": 0.0,
		"order": -1, "weapons_free": true, "centre": Vector3.ZERO, "lead": null, "age": INF}
	var up: Array[SquadAI] = []
	var orders := {}
	var free := 0
	for ai in squad.brains():
		if not ai.body.vitals.is_up():
			sit.down += 1
			continue
		up.append(ai)
		orders[ai.order] = int(orders.get(ai.order, 0)) + 1
		if ai.weapons_free():
			free += 1
	if squad.faction == &"friendly" and squad.is_inside_tree():
		for n in squad.get_tree().get_nodes_in_group(&"combatants"):
			var p := n as Soldier
			if p and not p.is_ai() and p.faction == squad.faction and p.squad_slot >= 0 and not p.is_queued_for_deletion() and not p.vitals.is_dead():
				if p.vitals.is_up():
					sit.up += 1
				else:
					sit.down += 1
		var lead := squad.leader
		sit.lead = lead if is_instance_valid(lead) and lead.vitals.is_up() else null
	if up.is_empty():
		return sit
	sit.up += up.size()
	var centre := Vector3.ZERO
	var cover := 0
	for ai in up:
		centre += ai.body.global_position
		sit.suppression += ai.body.suppression / up.size()
		if ai.in_contact():
			sit.contact = true
		if ai._at_cover():
			cover += 1
	sit.morale = up.reduce(func(acc: float, ai: SquadAI) -> float: return acc + ai.morale, 0.0) / up.size()
	sit.ammo = up.reduce(func(acc: float, ai: SquadAI) -> float: return acc + ai.ammo_share(AMMO_FULL_MAGS), 0.0) / up.size()
	sit.cover = float(cover) / up.size()
	sit.centre = centre / up.size()
	sit.weapons_free = free * 2 >= up.size()
	if squad.faction == &"friendly":
		var most := 0
		for o: int in orders:
			if int(orders[o]) > most:
				most = orders[o]
				sit.order = o
	var found := squad.clusters()
	for c in found:
		if float(c.age) < Squad.STALE_S:
			sit.known += int(c.count)
	if not found.is_empty():
		var c: Dictionary = found[0]
		sit.cluster = c
		sit.age = c.age
		sit.fresh = float(c.age) < Squad.FRESH_S
		sit.stale = not sit.fresh
		var to := (c.centre as Vector3) - (sit.centre as Vector3)
		sit.range = Vector2(to.x, to.z).length()
	if (sit.contact or sit.fresh) and not found.is_empty():
		var from := up[0].body
		if float(sit.range) <= CLEAR_M:
			sit.enemy_building = Buildings.at(from, sit.cluster.centre)
		var home := Buildings.nearest(from, sit.centre, DEFEND_M)
		if not home.is_empty() and (sit.enemy_building.is_empty() or (home.centre as Vector3).distance_to(sit.enemy_building.centre) > 1.0):
			sit.home_building = home
			sit.in_home = up.filter(func(ai: SquadAI) -> bool: return Buildings.contains(home, ai.body.global_position)).size() * 2 >= up.size()
	return sit


# --- Scoring ------------------------------------------------------------------------------

## Scores the options for situation `sit` (assess) under doctrine `d` (DOCTRINES): {"scores":
## {Option: 0..1}, "why": {Option: String}}. Options that don't apply aren't in it. Pure, so
## the tests can stage any situation.
static func score(sit: Dictionary, d: Dictionary) -> Dictionary:
	var s := {}
	var why := {}
	var up: int = sit.up
	if up <= 0:
		return {"scores": {Option.NONE: 1.0}, "why": {Option.NONE: "nobody up"}}
	var range: float = sit.range
	if not sit.contact and not sit.fresh:
		s[Option.NONE] = 0.5
		why[Option.NONE] = "no contact"
		if sit.stale and not (sit.cluster as Dictionary).is_empty():
			s[Option.SEARCH] = 0.56 + float(d.get("search", 0.0))
			why[Option.SEARCH] = "lost them %.0f s ago %.0f m off: search where they were last seen" % [float(sit.age), range]
		return {"scores": s, "why": why}
	var order: int = sit.order
	var free: bool = order != Squad.Order.HOLD and order != Squad.Order.MOVE  # following the lead, or a hostile squad
	var known := maxi(int(sit.known), 1)
	var ratio := float(up) / known
	var outnumbered := clampf(float(known - up) / up, 0.0, 1.0)
	var supp: float = sit.suppression
	var cover: float = sit.cover
	var shaken := clampf((MORALE_LOW - float(sit.morale)) / MORALE_LOW, 0.0, 1.0)
	var short := clampf((AMMO_LOW - float(sit.ammo)) / AMMO_LOW, 0.0, 1.0)
	var down: int = sit.down
	var losses := float(down) / (up + down)
	var weapons: bool = sit.weapons_free
	var odds := "%d known%s, %d of us up" % [int(sit.known), (" %.0f m off" % range) if range < INF else "", up]
	s[Option.HOLD] = 0.45 + 0.2 * supp + 0.1 * (1.0 - cover)
	why[Option.HOLD] = "%s; suppression %.2f, %.0f%% in cover" % [odds, supp, cover * 100.0]
	if sit.fresh and free and weapons and up >= FLANK_MIN_UP and range >= FLANK_MIN_M and range <= FLANK_MAX_M:
		s[Option.SUPPRESS_FLANK] = 0.55 + 0.1 * clampf(ratio - 1.0, 0.0, 2.0) + 0.1 * cover - 0.3 * supp - 0.2 * shaken \
			- 0.3 * short - 0.2 * losses + float(d.flank)
		why[Option.SUPPRESS_FLANK] = "%s: fix them and go round" % odds
	if sit.fresh and free and weapons and range <= ASSAULT_M and ratio >= ASSAULT_RATIO:
		s[Option.ASSAULT] = 0.5 + 0.1 * clampf(ratio - ASSAULT_RATIO, 0.0, 2.0) + 0.15 * (1.0 - range / ASSAULT_M) - 0.4 * supp \
			- 0.2 * shaken - 0.3 * short + float(d.assault)
		why[Option.ASSAULT] = "%s: close and outnumbered, take the position" % odds
	if free and weapons and not (sit.enemy_building as Dictionary).is_empty() and range <= CLEAR_M and ratio >= CLEAR_RATIO and up >= FLANK_MIN_UP:
		s[Option.CLEAR] = 0.6 + 0.1 * clampf(ratio - CLEAR_RATIO, 0.0, 2.0) - 0.3 * supp - 0.2 * shaken - 0.3 * short + float(d.clear)
		why[Option.CLEAR] = "%s, holding a building: clear it" % odds
	if not (sit.home_building as Dictionary).is_empty() and (free or sit.in_home):
		s[Option.DEFEND] = 0.35 + 0.3 * outnumbered + 0.15 * supp + (0.15 if sit.in_home else 0.0) + float(d.defend)
		why[Option.DEFEND] = "%s, a building at hand: take its windows and doors" % odds
	if free:
		s[Option.BREAK_CONTACT] = 0.25 + 0.35 * outnumbered + 0.4 * shaken + 0.3 * short + 0.3 * clampf((losses - 0.25) / 0.75, 0.0, 1.0) + float(d.break)
		why[Option.BREAK_CONTACT] = "%s, morale %.2f, ammunition %.0f%%, %d down: get out" % [odds, float(sit.morale), float(sit.ammo) * 100.0, down]
	if down > 0:
		s[Option.CASUALTY] = 0.6 + 0.1 * mini(down, 3) + float(d.casualty)
		why[Option.CASUALTY] = "%d down: cover them while they're seen to" % down
	return {"scores": s, "why": why}


# --- Carrying it out ----------------------------------------------------------------------

## Hands each unit its task for the current option (units with a tactic order keep theirs).
func _carry_out(now: float) -> void:
	var units: Array[SquadAI] = []
	for ai in squad.brains():
		if ai.body.vitals.is_up() and ai.ordered.is_empty():
			units.append(ai)
	if units.is_empty():
		return
	var sit := situation
	var cluster: Dictionary = sit.cluster
	var enemy: Vector3 = cluster.centre if not cluster.is_empty() else Vector3.INF
	var aim := enemy + Vector3.UP if enemy.is_finite() else Vector3.INF
	var id := "%s@%.1f" % [OPTION_NAMES[option], since]
	match option:
		Option.HOLD:
			for ai in units:
				ai.set_task({"kind": &"base", "aim": aim, "id": id} if ai.body.role == Roles.AUTORIFLEMAN and aim.is_finite() else {})
		Option.SUPPRESS_FLANK:
			_flank(units, enemy, aim, id)
		Option.ASSAULT:
			_assault(units, enemy, aim, id)
		Option.CLEAR:
			_clear(units, aim, id, now)
		Option.DEFEND:
			if plan.is_empty():
				plan = {"tasks": garrison_tasks(sit.home_building, units, enemy if enemy.is_finite() else sit.centre)}
			for ai in units:
				var t: Dictionary = plan.tasks.get(ai, {})
				ai.set_task(t.merged({"id": id}) if not t.is_empty() else {"kind": &"base", "aim": aim, "id": id})
		Option.BREAK_CONTACT:
			var lead: Soldier = sit.lead
			for i in units.size():
				var from: Soldier = lead if lead != null and units[i].order == Squad.Order.FOLLOW else null
				var p := fall_back_point(from, enemy if enemy.is_finite() else units[i].body.threat_pos, i, units.size(), units[i].body)
				units[i].set_task({"kind": &"break", "point": p, "id": id})
		Option.CASUALTY:
			for ai in units:
				ai.set_task({"kind": &"base", "aim": aim, "id": id} if aim.is_finite() else {})
		Option.SEARCH:
			_search(units, enemy, id, now)
		_:
			for ai in units:
				ai.set_task({})


## The contact drill: the base of fire suppresses `aim` while the maneuver element works round
## the flank (flank_route). Drawn once per contact (again if the enemy moves REPLAN_M or the
## squad changes); units on Hold or Move, or with no flank to take, join the base.
func _flank(units: Array[SquadAI], enemy: Vector3, aim: Vector3, id: String) -> void:
	var names := units.map(func(ai: SquadAI) -> String: return String(ai.body.name))
	if plan.is_empty() or (plan.enemy as Vector3).distance_to(enemy) > REPLAN_M or plan.names != names:
		var split := elements(units, enemy)
		var base: Array = split[0]
		var moving: Array = split[1].filter(func(ai: SquadAI) -> bool: return ai.order == Squad.Order.FOLLOW or not ai._friendly())
		base.append_array(split[1].filter(func(ai: SquadAI) -> bool: return ai not in moving))
		var lead: Soldier = situation.lead
		var route := {} if moving.is_empty() else flank_route(moving[0].body, _middle(moving), enemy, lead, _other_clusters())
		if route.is_empty():
			base.append_array(moving)
			moving = []
		plan = {"enemy": enemy, "names": names, "base": base, "moving": moving, "route": route.get("route", []), "side": route.get("side", "")}
		print("[tactics] %s: base of fire %s on (%.0f, %.0f)%s" % [squad.name, _names(base), enemy.x, enemy.z,
			(", %s flank %s by %s" % [_names(moving), plan.side, _points(plan.route)]) if not moving.is_empty() else ", no flank to take"])
	for ai in units:
		if ai in plan.moving:
			ai.set_task({"kind": &"maneuver", "route": plan.route, "aim": aim, "id": id})
		else:
			ai.set_task({"kind": &"base", "aim": aim, "id": id})


## Assault: the autorifleman and his buddy (else the pair nearest the enemy) keep their heads
## down, the rest bound onto the position. Units on Hold or Move stay in the base.
func _assault(units: Array[SquadAI], enemy: Vector3, aim: Vector3, id: String) -> void:
	if plan.is_empty() or (plan.enemy as Vector3).distance_to(enemy) > REPLAN_M:
		var base := _gunners_and_buddies(units, enemy)
		plan = {"enemy": enemy, "base": base}
	var map := units[0].body.get_world_3d().navigation_map
	var point := NavigationServer3D.map_get_closest_point(map, enemy)
	for ai in units:
		if ai in plan.base or (ai._friendly() and ai.order != Squad.Order.FOLLOW):
			ai.set_task({"kind": &"base", "aim": aim, "id": id})
		else:
			ai.set_task({"kind": &"assault", "point": point, "id": id})


## Clearing the building the enemy holds: the base (the autorifleman and his buddy) suppresses
## it until the stack starts going in, the entry team (up to ENTRY_MAX) stacks and clears
## (clear_op), and anyone else holds outside. Once every room's corner is reached the team
## calls it clear.
func _clear(units: Array[SquadAI], aim: Vector3, id: String, now: float) -> void:
	var b: Dictionary = situation.enemy_building
	if plan.is_empty():
		var base := _gunners_and_buddies(units, b.centre)
		var entry: Array[SquadAI] = []
		for ai in units:
			if ai not in base and entry.size() < ENTRY_MAX and (not ai._friendly() or ai.order == Squad.Order.FOLLOW):
				entry.append(ai)
		var op := clear_op(b, entry) if not entry.is_empty() else {}
		plan = {"base": base, "entry": entry, "op": op}
		if not op.is_empty():
			print("[tactics] %s: %s stack at (%.0f, %.0f) to clear %d room(s), %s cover" % [squad.name, _names(entry),
				op.entrance.door.x, op.entrance.door.z, b.rooms.size(), _names(base)])
	var op: Dictionary = plan.op
	var going := not op.is_empty() and is_finite(float(op.go_at))
	for ai in units:
		var slot: int = plan.entry.find(ai)
		if slot >= 0 and not op.is_empty():
			ai.set_task({"kind": &"clear", "op": op, "slot": slot, "id": id})
		elif not going and ai in plan.base and aim.is_finite():
			ai.set_task({"kind": &"base", "aim": aim, "id": id})
		else:
			ai.set_task({})  # the stack is going in: no more rounds into the building
	if not op.is_empty() and not bool(op.get("called", false)) and op.done.size() >= plan.entry.size():
		op.called = true
		var first: SquadAI = plan.entry[0]
		if is_instance_valid(first.body):
			first._callout(&"tactic", "Clear!")
		print("[tactics] %s: building clear" % squad.name)


## Searching where the enemy was last seen: hostile pairs to points round it, friendlies watch
## it. After SEARCH_S the squad forgets the stale positions.
func _search(units: Array[SquadAI], enemy: Vector3, id: String, now: float) -> void:
	if now - since >= SEARCH_S:
		squad.forget_stale()
		return
	var pairs := _pairs(units)
	var map := units[0].body.get_world_3d().navigation_map
	for k in pairs.size():
		var a := TAU * k / maxf(pairs.size(), 1.0)
		var p := NavigationServer3D.map_get_closest_point(map, enemy + Vector3(cos(a), 0.0, sin(a)) * (SEARCH_RING_M if k > 0 else 0.0))
		for ai: SquadAI in pairs[k]:
			ai.set_task({"kind": &"watch" if ai._friendly() else &"search", "point": p, "id": id})


# --- Plans (also used by the command menu's tactic orders) -------------------------------

## Splits `units` into a base of fire and a maneuver element: by fire team when two teams have
## AI in them (the team nearer `enemy` is the base), else by buddy pairs (the pair nearest
## `enemy` is the base). The autorifleman stays with the base whatever his team. Returns
## [base, maneuver]; with nobody to spare the maneuver element is empty.
static func elements(units: Array, enemy: Vector3) -> Array:
	var teams := {}
	var loose: Array = []
	for ai: SquadAI in units:
		if ai.body.fire_team >= 0:
			if not teams.has(ai.body.fire_team):
				teams[ai.body.fire_team] = []
			teams[ai.body.fire_team].append(ai)
		else:
			loose.append(ai)
	var base: Array = []
	var moving: Array = []
	if teams.size() >= 2:
		var keys := teams.keys()
		keys.sort_custom(func(a: int, b: int) -> bool: return _mean_distance(teams[a], enemy) < _mean_distance(teams[b], enemy))
		base.append_array(teams[keys[0]])
		for k in keys.slice(1):
			moving.append_array(teams[k])
		base.append_array(loose)
	else:
		var pairs := _pairs(units)
		pairs.sort_custom(func(a: Array, b: Array) -> bool: return _mean_distance(a, enemy) < _mean_distance(b, enemy))
		if not pairs.is_empty():
			base.append_array(pairs[0])
		for p in pairs.slice(1):
			moving.append_array(p)
	for ai: SquadAI in moving.duplicate():
		if ai.body.role == Roles.AUTORIFLEMAN:
			moving.erase(ai)
			base.append(ai)
	return [base, moving]


## The way round for a maneuver element at `from` against an enemy at `enemy`: on each side a
## point FLANK_MID_DEG round at today's range, then FLANK_ANGLE_DEG round at FLANK_RANGE of it,
## kept within FOLLOW_LEASH_M of `lead` (when following one), on the navmesh and reachable. The
## side whose points the enemy sees least of wins (then the side away from `others`, other
## enemy positions). {"side": "left" or "right" (as the squad faces the enemy), "route":
## [Vector3, Vector3]}, or {} if neither side works.
static func flank_route(node: Node3D, from: Vector3, enemy: Vector3, lead: Soldier, others: Array) -> Dictionary:
	var world := node.get_world_3d()
	var map := world.navigation_map
	var u := Vector3(from.x - enemy.x, 0.0, from.z - enemy.z)
	var range := u.length()
	if range < 1.0:
		return {}
	u /= range
	var r := clampf(range * FLANK_RANGE, FLANK_NEAR_M, FLANK_FAR_M)
	var right := (-u).cross(Vector3.UP)
	var best := {}
	var best_cost := INF
	for sign_v: float in [1.0, -1.0]:
		var mid := enemy + u.rotated(Vector3.UP, deg_to_rad(FLANK_MID_DEG) * sign_v) * range
		var end := enemy + u.rotated(Vector3.UP, deg_to_rad(FLANK_ANGLE_DEG) * sign_v) * r
		var route: Array[Vector3] = []
		var cost := 0.0
		for p: Vector3 in [mid, end]:
			if lead != null:
				p = _leashed(p, lead.global_position, FOLLOW_LEASH_M)
			var q := NavigationServer3D.map_get_closest_point(map, p)
			if Vector2(q.x - p.x, q.z - p.z).length() > PLAN_SNAP_M:
				break
			var path := NavigationServer3D.map_get_path(map, from, q, true)
			if path.is_empty() or path[path.size() - 1].distance_to(q) > 1.5:
				break
			if Throwables.clear_line(world, enemy + Vector3.UP * 1.5, q + Vector3.UP):
				cost += 1.0  # the enemy sees that spot
			route.append(q)
		if route.size() < 2:
			continue
		for e: Vector3 in others:
			if e.distance_to(route[1]) < r:
				cost += 0.5  # someone else over there
		if cost < best_cost:
			best_cost = cost
			best = {"side": "right" if (route[1] - enemy).dot(right) > 0.0 else "left", "route": route}
	return best


## Garrisoning building `b` against a threat at `threat`: its ports facing the threat first
## (windows, a roof's parapet and doors, every floor; ports up high score a little more, and
## with a few men one of the first two takes a door), each to the nearest unit still free, and
## the rest inside, away from the walls the threat faces. {SquadAI: {"kind": "garrison",
## "spot", "face", "port"}}.
static func garrison_tasks(b: Dictionary, units: Array, threat: Vector3) -> Dictionary:
	var ports: Array = b.ports.duplicate()
	var floors: Array = b.get("floors", [])
	var score := func(p: Dictionary) -> float:
		var fi := int(p.get("floor", 0))
		var bonus := 0.0
		if fi > 0:
			bonus = ROOF_PORT_BONUS if fi < floors.size() and bool(floors[fi].get("roof", false)) else HIGH_PORT_BONUS
		return _facing(p, threat) + bonus
	ports.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return score.call(a) > score.call(c))
	if units.size() >= GARRISON_DOOR_MIN and ports.size() > 2 and not ports.slice(0, 2).any(func(p: Dictionary) -> bool: return p.kind == "door"):
		for i in range(2, ports.size()):
			if ports[i].kind == "door" and _facing(ports[i], threat) > -0.3:
				ports.insert(1, ports.pop_at(i))
				break
	var free: Array = units.duplicate()
	var out := {}
	for port: Dictionary in ports:
		if free.is_empty():
			break
		var nearest: SquadAI = free[0]
		for ai: SquadAI in free:
			if ai.body.global_position.distance_to(port.point) < nearest.body.global_position.distance_to(port.point):
				nearest = ai
		free.erase(nearest)
		out[nearest] = {"kind": &"garrison", "spot": port.point, "face": port.dir, "port": port.kind}
	if free.is_empty():
		return out
	var inside: Array = b.spots.duplicate()
	inside.sort_custom(func(a: Vector3, c: Vector3) -> bool: return a.distance_to(threat) > c.distance_to(threat))
	var taken: Array[Vector3] = []
	for t: Dictionary in out.values():
		taken.append(t.spot)
	for s: Vector3 in inside:
		if free.is_empty():
			break
		if taken.any(func(p: Vector3) -> bool: return p.distance_to(s) < 1.5):
			continue
		var ai: SquadAI = free.pop_front()
		taken.append(s)
		var face := Vector3(threat.x - s.x, 0.0, threat.z - s.z)
		out[ai] = {"kind": &"garrison", "spot": s, "face": face.normalized() if face.length() > 0.1 else Vector3.FORWARD, "port": "inside"}
	return out


## A clearance of building `b` by `units` (the entry team, in entry order): their places in the
## stack beside the entrance nearest them, on the side of the doorway they come from, and the
## room corner each goes to on each floor, floor by floor from the ground up the stairs (the
## first pair the floor's first room's corners, the next pair the next room). Shared by the
## units' tasks, which mark "ready" (in the stack), "go_at" (when the first goes in), each
## floor's "floor_done" (at their corner there; "floor_go" when the next floor's turn comes),
## and "done" (at their corner on the last floor). "rooms": the first floor's corners. {} if
## the building has no way in.
static func clear_op(b: Dictionary, units: Array) -> Dictionary:
	if units.is_empty() or b.get("rooms", []).is_empty():
		return {}
	var from := Vector3.ZERO
	for ai: SquadAI in units:
		from += ai.body.global_position
	from /= units.size()
	var e := Buildings.entrance_near(b, from)
	if e.is_empty():
		return {}
	var normal: Vector3 = e.normal
	var along := normal.cross(Vector3.UP)
	var side := 1.0 if (from - (e.door as Vector3)).dot(along) >= 0.0 else -1.0
	var map := (units[0] as SquadAI).body.get_world_3d().navigation_map
	var stack: Array[Vector3] = []
	for i in units.size():
		var p: Vector3 = e.door + normal * STACK_OUT_M + along * side * (STACK_FIRST_M + STACK_GAP_M * i)
		stack.append(NavigationServer3D.map_get_closest_point(map, p))
	# Each floor's rooms (a building scanned before floors were kept is all one floor).
	var per_floor: Array = []
	for f: Dictionary in b.get("floors", []):
		if not (f.rooms as Array).is_empty():
			per_floor.append(f.rooms)
	if per_floor.is_empty():
		per_floor.append(range(b.rooms.size()))
	var floors: Array = []
	for list: Array in per_floor:
		var corners: Array[Vector3] = []
		for i in units.size():
			var room: Dictionary = b.rooms[list[(i >> 1) % list.size()]]
			var at: Array = room.corners
			corners.append(at[i % at.size()] if not at.is_empty() else room.centre)
		floors.append(corners)
	var floor_done: Array = []
	var floor_go: Array = []
	for f in floors:
		floor_done.append({})
		floor_go.append(INF)
	return {"building": b, "entrance": e, "stack": stack, "rooms": floors[0], "floors": floors, "units": units.size(),
		"ready": {}, "first_ready_at": INF, "go_at": INF, "done": {}, "floor_of": {}, "floor_done": floor_done,
		"floor_first": floor_go.duplicate(), "floor_go": floor_go}


## Where unit `index` of `count` falls back to from a threat at `threat`: BREAK_BEHIND_LEAD_M
## behind `lead` (away from the threat) when following one, else BREAK_M from the threat past
## `unit` (or the lead); spread across the way back BREAK_SPREAD_M apart, on the navmesh.
static func fall_back_point(lead: Soldier, threat: Vector3, index: int, count: int, unit: Soldier = null) -> Vector3:
	var at: Soldier = lead if lead != null else unit
	var base := at.global_position
	var away := Vector3(base.x - threat.x, 0.0, base.z - threat.z)
	away = away.normalized() if away.length() > 0.1 else -at.global_basis.z
	var p := base + away * (BREAK_BEHIND_LEAD_M if lead != null else maxf(BREAK_M - Vector2(base.x - threat.x, base.z - threat.z).length(), BREAK_SPREAD_M * 2.0))
	p += away.cross(Vector3.UP) * (index - (count - 1) / 2.0) * BREAK_SPREAD_M
	return NavigationServer3D.map_get_closest_point(at.get_world_3d().navigation_map, p)


# --- Helpers ------------------------------------------------------------------------------

## Buddy pairs among `units` (a unit whose buddy isn't among them is a pair of its own).
static func _pairs(units: Array) -> Array:
	var out: Array = []
	var placed := {}
	for ai: SquadAI in units:
		if placed.has(ai):
			continue
		var pair: Array = [ai]
		placed[ai] = true
		var mate := SquadAI.of(ai.buddy) if is_instance_valid(ai.buddy) else null
		if mate and mate in units and not placed.has(mate):
			pair.append(mate)
			placed[mate] = true
		out.append(pair)
	return out


## The autorifleman (any) and his buddy among `units`; with none, the pair nearest `enemy`.
static func _gunners_and_buddies(units: Array, enemy: Vector3) -> Array:
	var out: Array = []
	for pair: Array in _pairs(units):
		if pair.any(func(ai: SquadAI) -> bool: return ai.body.role == Roles.AUTORIFLEMAN):
			out.append_array(pair)
	if out.is_empty():
		var pairs := _pairs(units)
		pairs.sort_custom(func(a: Array, b: Array) -> bool: return _mean_distance(a, enemy) < _mean_distance(b, enemy))
		if not pairs.is_empty() and units.size() > pairs[0].size():
			out.append_array(pairs[0])
	return out


static func _mean_distance(units: Array, point: Vector3) -> float:
	var sum := 0.0
	for ai: SquadAI in units:
		sum += ai.body.global_position.distance_to(point)
	return sum / maxf(units.size(), 1.0)


static func _middle(units: Array) -> Vector3:
	var sum := Vector3.ZERO
	for ai: SquadAI in units:
		sum += ai.body.global_position
	return sum / maxf(units.size(), 1.0)


## How squarely port `port` faces `threat` (1 straight at it).
static func _facing(port: Dictionary, threat: Vector3) -> float:
	var to := threat - (port.point as Vector3)
	to.y = 0.0
	return (port.dir as Vector3).dot(to.normalized()) if to.length() > 0.1 else 0.0


## `p` pulled in to within `leash` of `centre` (flat).
static func _leashed(p: Vector3, centre: Vector3, leash: float) -> Vector3:
	var off := Vector3(p.x - centre.x, 0.0, p.z - centre.z)
	if off.length() <= leash:
		return p
	return centre + off.normalized() * leash + Vector3.UP * (p.y - centre.y)


## Centres of the known clusters other than the densest.
func _other_clusters() -> Array:
	var found := squad.clusters()
	return found.slice(1).map(func(c: Dictionary) -> Vector3: return c.centre)


static func _names(units: Array) -> String:
	return ", ".join(PackedStringArray(units.map(func(ai: SquadAI) -> String: return String(ai.body.name)))) if not units.is_empty() else "nobody"


static func _points(points: Array) -> String:
	return " > ".join(PackedStringArray(points.map(func(p: Vector3) -> String: return "(%.0f, %.0f)" % [p.x, p.z])))


func _log(was: Option, why: String) -> void:
	var order := scores.keys()
	order.sort_custom(func(a: Option, b: Option) -> bool: return float(scores[a]) > float(scores[b]))
	var top := PackedStringArray()
	for o: Option in order.slice(0, 3):
		top.append("%s %.2f" % [OPTION_NAMES[o], float(scores[o])])
	print("[tactics] %s: %s (was %s; %s) - %s" % [squad.name, OPTION_NAMES[option], OPTION_NAMES[was], ", ".join(top), why])


## The squad leader (its team leader if one is AI, else its first unit) calls the new option.
func _call_option() -> void:
	if not CALLS.has(option):
		return
	var units := squad.brains().filter(func(ai: SquadAI) -> bool: return ai.body.vitals.is_up())
	if units.is_empty():
		return
	var speaker: SquadAI = units[0]
	for ai: SquadAI in units:
		if ai.body.role == Roles.TEAM_LEADER:
			speaker = ai
			break
	var text: String = CALLS[option]
	if option == Option.SUPPRESS_FLANK:
		var split := elements(units, situation.cluster.centre)
		var team := "Team %s" % Roles.TEAMS[split[1][0].body.fire_team] if not split[1].is_empty() and split[1][0].body.fire_team >= 0 else "Second pair"
		var side := String(flank_route(speaker.body, situation.centre, situation.cluster.centre, situation.lead, []).get("side", "wide"))
		text = text % [team, side]
	speaker._callout(&"tactic", text)
