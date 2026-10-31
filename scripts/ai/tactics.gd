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
## option has to beat the current one by HYSTERESIS, and a chosen option is held MIN_KEEP_S
## unless it stops applying or the situation changes a lot (someone else goes down, or another
## option beats it by URGENT_MARGIN) (P0362: the squad re-called its drill every second and sat
## still). Every change prints a "[tactics]" line: the squad, the option, the top scores and why.
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
##   (friendlies following their lead: behind the lead). With no flank to take (the drill found
##   no route round, or nobody free to go) the squad remembers it (NO_FLANK_S), drops the drill,
##   and when it's being out-shot (suppressed, outnumbered or taking losses) it bounds back to
##   cover rather than holding where it is (NO_FLANK_BREAK).
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
##
## The tactics reels (docs/ai_tactics.md, 2026-10-22), team and squad level, for every side:
## - Near ambush (T1): fired on from within NEAR_AMBUSH_M while moving, a squad doesn't look for
##   cover in the kill zone: the gun and his buddy fire, the rest throw frags and CHARGE_DELAY_S
##   later charge through the enemy line THROUGH_M past it, then consolidate facing back.
## - Break contact as Battle Drill 3 (T2): the grenadier's smoke, then the man furthest back goes
##   first, "Moving!", to the rally point, "Set!", then the next, each covered by those still firing;
##   all set at the rally point, a perimeter facing the enemy.
## - Rally points (T3): moving with no contact, a rally point every RALLY_EVERY_M, RALLY_BACK_M back
##   along the way, in cover (Squad meta "rally"): where break contact goes.
## - Fire superiority first (T4): the flank's movers wait until the base of fire is firing (or
##   BASE_SET_TIMEOUT_S), then "Base is set, move!".
## - Sectors of fire (T5): the base's men spread their fire across the enemy and past both flanks
##   (SECTOR_EXTRA_M), never all on one point; it shifts beyond the objective with the movers within
##   SHIFT_M and lifts within LIFT_M.
## - Lanes and the limit of advance (T6): the assault goes through in lanes LANE_W apart, to
##   THROUGH_M past the enemy at most; then consolidation, all-round, CONSOLIDATE_S.
## - Doctrine by faction (T10): a squad's men's own doctrine (jihadist, guerrilla, cartel), not only
##   its side's, sets its option biases.

enum Option { NONE, HOLD, SUPPRESS_FLANK, ASSAULT, CLEAR, DEFEND, BREAK_CONTACT, CASUALTY, SEARCH, NEAR_AMBUSH }

const OPTION_NAMES := {
	Option.NONE: "carry on", Option.HOLD: "hold and improve cover", Option.SUPPRESS_FLANK: "suppress and flank",
	Option.ASSAULT: "assault", Option.CLEAR: "clear the building", Option.DEFEND: "defend the building",
	Option.BREAK_CONTACT: "break contact", Option.CASUALTY: "casualty care", Option.SEARCH: "search last known",
	Option.NEAR_AMBUSH: "near ambush: assault through",
}
## What the squad leader calls out when the squad takes up an option (the friendly side hears it).
const CALLS := {
	Option.HOLD: "Get in cover, hold here!", Option.SUPPRESS_FLANK: "Base of fire, suppress! %s, flank %s!",
	Option.ASSAULT: "Assault through!", Option.CLEAR: "Stack up on that building!", Option.DEFEND: "Into the building, take the windows!",
	Option.BREAK_CONTACT: "Break contact! Fall back!", Option.CASUALTY: "Cover the casualty!",
	Option.NEAR_AMBUSH: "Ambush! Frags, then through them!",
}
## The reels (docs/ai_tactics.md), Proposed.
const NEAR_AMBUSH_M := 35.0
const NEAR_WINDOW_S := 12.0
const NEAR_MOVING_M := 2.0
const CHARGE_DELAY_S := 2.5
const THROUGH_M := 15.0
const LANE_W := 6.0
const CONSOLIDATE_S := 20.0
const CONSOLIDATE_R := 8.0
const RALLY_EVERY_M := 150.0
const RALLY_BACK_M := 45.0
const BD3_BACK_M := 60.0
const BD3_MOVER_S := 15.0
const BD3_SPREAD_M := 6.0
const BASE_SET_TIMEOUT_S := 30.0
const SECTOR_EXTRA_M := 10.0
const SHIFT_M := 50.0
const LIFT_M := 25.0

const THINK_S := 1.0
const HYSTERESIS := 0.1
const MIN_KEEP_S := 8.0
## Within MIN_KEEP_S another option takes over only when it beats the current one by this much
## (or someone else went down since it was chosen).
const URGENT_MARGIN := 0.25
## The contact drill's plan is drawn again for an enemy that moved REPLAN_M at most this often
## (s), and its "[tactics]" line printed only when who does what changes, or after PLAN_LOG_S.
const REPLAN_MIN_S := 4.0
const PLAN_LOG_S := 20.0
## No flank to take: remembered this long (s), or until the enemy has moved NO_FLANK_MOVED_M.
const NO_FLANK_S := 30.0
const NO_FLANK_MOVED_M := 25.0
## Out-shot (0..1): suppression at OUTSHOT_SUPPRESSION counts fully, as does being outnumbered
## and losses of a third. With no flank, breaking contact gains NO_FLANK_BREAK times that.
const OUTSHOT_SUPPRESSION := 0.3
const NO_FLANK_BREAK := 0.5
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
## Overwatch (AI bar G-17: LAMBS and VCOM score hills for it): the base of fire looks round its
## middle on OVERWATCH_RINGS for a spot with a line on the enemy, scoring height over him
## (OVERWATCH_HEIGHT_W a metre, to OVERWATCH_HEIGHT_MAX_M), the walk (OVERWATCH_WALK_W a metre)
## and being in sight of another known group (OVERWATCH_EXPOSED within OVERWATCH_OTHERS_M); it
## moves only for one OVERWATCH_GAIN better than where it is, and never into the enemy's lap
## (nearer him than OVERWATCH_NEAREST of the range). A flank's end point likes height too
## (FLANK_HEIGHT_W a metre, to FLANK_HEIGHT_MAX). Proposed.
const OVERWATCH_RINGS: Array[float] = [12.0, 24.0, 36.0]
const OVERWATCH_HEIGHT_W := 0.8
const OVERWATCH_HEIGHT_MAX_M := 12.0
const OVERWATCH_WALK_W := 0.08
const OVERWATCH_EXPOSED := 1.5
const OVERWATCH_OTHERS_M := 250.0
const OVERWATCH_GAIN := 2.0
const OVERWATCH_NEAREST := 0.6
const FLANK_HEIGHT_W := 0.05
const FLANK_HEIGHT_MAX := 0.5
## Variety (AI bar G-21; VCOM doesn't repeat an attack on the same group within 120 s): the side
## a flank took against a group (FLANK_MEMORY_CELL_M cells) is remembered FLANK_MEMORY_S and the
## next leans the other way (FLANK_SAME_SIDE_COST); a squad not tied to a lead goes wide
## (FLANK_WIDE_M out) at WIDE_CHANCE when the enemy is WIDE_MIN_RANGE_M or more off. Proposed.
const FLANK_MEMORY_S := 120.0
const FLANK_MEMORY_CELL_M := 50.0
const FLANK_SAME_SIDE_COST := 0.6
const FLANK_WIDE_M := 150.0
const WIDE_CHANCE := 0.3
const WIDE_MIN_RANGE_M := 80.0
## Proposed (Captain, 2026-10-14: they bunched up): the maneuver element's men each take their
## own lane round the flank, this far apart side by side, instead of all running to one point.
const LANE_GAP_M := 5.0
## The plan is drawn again when the cluster it's against has moved this far.
const REPLAN_M := 8.0
const ASSAULT_M := 35.0
const ASSAULT_RATIO := 2.0
const CLEAR_M := 60.0
## A clearance under way is finished (AI bar G-08: LAMBS keeps a building's rooms until each is
## seen): while its op has rooms nobody has reached, CLEAR holds at CLEAR_KEEP at least, so quiet
## doesn't end it; a new casualty, being out-shot (break contact scores higher) or an order still
## do. Proposed.
const CLEAR_KEEP := 0.62
const CLEAR_RATIO := 1.5
## A building this close to the squad's middle can be defended.
const DEFEND_M := 20.0
## Breaking contact: to BREAK_M from the enemy, or (friendlies following their lead)
## BREAK_BEHIND_LEAD_M behind the lead; pairs BREAK_SPREAD_M apart.
const BREAK_M := 35.0
const BREAK_BEHIND_LEAD_M := 10.0
const BREAK_SPREAD_M := 5.0  # (was 2.5; Captain, 2026-10-14: they bunched up)
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
## Stacking outside, never in (Captain, 2026-10-20: on a clear order "stacking ... inside instead of
## outside"): a stack spot along the wall is tried STACK_OUT_M out, then each of these further out,
## then on the door's other side, then in a column straight out from it; it's kept only if the
## navmesh's nearest point is within STACK_SNAP_M of it (not through a wall), outside the building
## and on the door's outer side. The nearest-point snap used to pull a spot by a corner or an
## uneven wall in through the wall, into the rooms.
const STACK_OUT_TRIES: Array[float] = [0.6, 1.2, 2.0]
const STACK_SNAP_M := 0.6
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
	# Terror groups (docs/terror_groups.md, ai_tactics.md 7.3): jihadists press and stay; guerrillas
	# hit and run; cartels hold what they guard. Proposed.
	&"jihadist": {"flank": 0.0, "assault": 0.15, "clear": 0.0, "defend": 0.05, "break": -0.15, "casualty": -0.2, "search": 0.1},
	&"guerrilla": {"flank": 0.05, "assault": -0.05, "clear": -0.1, "defend": -0.05, "break": 0.2, "casualty": -0.1, "search": 0.0},
	&"cartel": {"flank": -0.1, "assault": 0.0, "clear": -0.1, "defend": 0.15, "break": 0.05, "casualty": -0.1, "search": 0.05},
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
## The fewest down since the current option was chosen: one more down is a big change.
var _down_at_pick := 0
## The last drill that found no flank to take: {"enemy": Vector3, "at": seconds}, or {}.
var _no_flank := {}
## When the drill's plan was drawn, and its last "[tactics]" line: {"key", "at"}.
var _plan_at := -1000.0
var _plan_logged := {"key": "", "at": -1000.0}
var _flank_sides := {}  # Vector2i cell of the enemy -> {"side", "at"} (G-21)
var _contact_was := false
var _contact_began := -1000.0
var _contact_range := INF
var _moving_at_contact := false
var _centres: Array = []  # [{"at", "pos"}]: the squad's centre the last few seconds (moving?)
var _rally_from := Vector3.INF
var _consolidate_until := -1000.0
var _consolidate_at := Vector3.INF


func _init(p_squad: Squad) -> void:
	squad = p_squad


## One think: assess, score, keep or change the option (logging the change), and hand out tasks.
func think(now: float) -> void:
	situation = assess()
	situation["no_flank"] = _no_flank_now(now)
	_track_contact(now)
	_rally_points(now)
	var result := score(situation, doctrine())
	var best := _best(result.scores)
	var urgent := int(situation.down) > _down_at_pick
	if keeps_clear(option, plan, urgent):
		result.scores[Option.CLEAR] = maxf(float(result.scores.get(Option.CLEAR, -1.0)), CLEAR_KEEP)
		if not (result.why as Dictionary).has(Option.CLEAR):
			result.why[Option.CLEAR] = "rooms still to clear"
		best = _best(result.scores)
	var drill := {}
	if best == Option.SUPPRESS_FLANK and best != option and switches(result.scores.get(option, -1.0), result.scores[best], now - since, urgent):
		# Draw the drill before calling it: with no flank to take it's a base of fire sitting still.
		drill = _drill_plan(now)
		if drill.is_empty() or (drill.moving as Array).is_empty():
			situation.no_flank = true
			result = score(situation, doctrine())
			best = _best(result.scores)
			drill = {}
	scores = result.scores
	if best != option and switches(scores.get(option, -1.0), scores[best], now - since, urgent):
		var was := option
		if was in [Option.ASSAULT, Option.NEAR_AMBUSH] and not bool(situation.fresh):
			_consolidate_until = now + CONSOLIDATE_S  # the position taken: all-round security (T6)
			_consolidate_at = situation.centre
			if not squad.brains().is_empty():
				squad.brains()[0]._callout(&"tactic", "Consolidate! All-round security, ammo check!")
		option = best
		since = now
		plan = drill if best == Option.SUPPRESS_FLANK else {}
		_down_at_pick = int(situation.down)
		_log(was, String(result.why.get(best, "")))
		_call_option()
		if not plan.is_empty():
			_log_plan(now)
	_down_at_pick = mini(_down_at_pick, int(situation.down))
	option_score = scores.get(option, 0.0)
	_carry_out(now)


## Whether a clearance under way carries on (G-08): CLEAR chosen, its op drawn, rooms still to
## reach (it hasn't called "Clear!"), and nobody newly down.
static func keeps_clear(current: Option, the_plan: Dictionary, urgent: bool) -> bool:
	if current != Option.CLEAR or urgent:
		return false
	var op: Dictionary = the_plan.get("op", {})
	return not op.is_empty() and not bool(op.get("called", false))


## Whether the option scoring `current` (-1: it no longer applies) gives way to one scoring
## `best`, after holding it `held_s`; `urgent`: someone else went down since it was chosen.
static func switches(current: float, best: float, held_s: float, urgent: bool) -> bool:
	if current < 0.0:
		return true
	if best < current + HYSTERESIS:
		return false
	return held_s >= MIN_KEEP_S or urgent or best >= current + URGENT_MARGIN


static func _best(option_scores: Dictionary) -> Option:
	var best := Option.NONE
	var best_score := -INF
	for o: Option in option_scores:
		if float(option_scores[o]) > best_score:
			best = o
			best_score = option_scores[o]
	return best


## Whether the drill lately found no flank to take against (about) the enemy the squad has now.
func _no_flank_now(now: float) -> bool:
	if _no_flank.is_empty():
		return false
	var cluster: Dictionary = situation.get("cluster", {})
	if now - float(_no_flank.at) > NO_FLANK_S or cluster.is_empty() \
			or (cluster.centre as Vector3).distance_to(_no_flank.enemy) > NO_FLANK_MOVED_M:
		_no_flank = {}
		return false
	return true


## The drill's plan against the enemy the squad has now (see _flank), drawn for the units free
## to take a task; {} with no enemy or nobody. With no maneuver element it's remembered as no
## flank to take.
func _drill_plan(now: float) -> Dictionary:
	var units := _free_units()
	var cluster: Dictionary = situation.cluster
	if units.is_empty() or cluster.is_empty():
		return {}
	return _draw_flank(units, cluster.centre, now)


## This squad's doctrine (DOCTRINES), with a hot zone's enemy coordination taken into
## account for hostile squads.
func doctrine() -> Dictionary:
	var name := squad.doctrine
	if name == &"":
		var men := squad.brains()
		name = men[0]._doctrine_id() if not men.is_empty() else Doctrine.default_for(squad.faction)  # its men's own (T10)
	var d: Dictionary = DOCTRINES.get(name, DOCTRINES[Doctrine.PMC]).duplicate()
	var men2 := squad.brains()
	if squad.faction == &"hostile" and not men2.is_empty() and FactionForce.hit_and_run(String(men2[0].body.get_meta(&"faction_id", ""))):
		d.break = float(d.break) + 0.25  # a small terror group: a heavy volley, then gone before it's fixed (ai_tactics.md 7.3)
		d.assault = float(d.assault) - 0.1
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
		for n in (squad.get_tree().get_nodes_in_group(&"combatants") if squad.is_player_squad() else []):  # G4: the humans are the player squad's men only
			var p := n as Soldier
			if p and not p.is_ai() and p.faction == squad.faction and p.squad_slot >= 0 and not p.is_queued_for_deletion() and not p.vitals.is_dead():
				if p.vitals.is_up():
					sit.up += 1
				else:
					sit.down += 1
		var lead := squad.leader
		sit.lead = lead if is_instance_valid(lead) and lead.vitals.is_up() else null
		sit.human_lead = sit.lead != null and not (sit.lead as Soldier).is_ai()
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
	# Following the lead, or a hostile squad. Captain, 2026-10-17 ("ai are bunching up in
	# engagements and aren't following me/my orders"): a squad a player leads doesn't flank,
	# assault, clear, defend or break contact by itself (break contact packed them onto points
	# behind where he'd been, held there while he moved on). It fights from its formation slots
	# round him, so it moves with him, and takes those moves when he orders them (command menu).
	var free: bool = order != Squad.Order.HOLD and order != Squad.Order.MOVE and not bool(sit.get("human_lead", false))
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
	var no_flank: bool = sit.get("no_flank", false)
	var outshot := clampf(maxf(supp / OUTSHOT_SUPPRESSION, maxf(outnumbered, losses * 3.0)), 0.0, 1.0)
	var odds := "%d known%s, %d of us up" % [int(sit.known), (" %.0f m off" % range) if range < INF else "", up]
	s[Option.HOLD] = 0.45 + 0.2 * supp + 0.1 * (1.0 - cover)
	why[Option.HOLD] = "%s; suppression %.2f, %.0f%% in cover" % [odds, supp, cover * 100.0]
	if sit.fresh and free and weapons and up >= FLANK_MIN_UP and range >= FLANK_MIN_M and range <= FLANK_MAX_M and not no_flank:
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
		if no_flank and outshot > 0.0:
			s[Option.BREAK_CONTACT] += NO_FLANK_BREAK * outshot
			why[Option.BREAK_CONTACT] = "%s, no flank to take and out-shot (suppression %.2f, %d down): bound back to cover" % [odds, supp, down]
	if bool(sit.get("near_ambush", false)) and free and weapons and sit.fresh and range <= NEAR_AMBUSH_M and float(sit.cover) < 0.5:
		s[Option.NEAR_AMBUSH] = 0.9 + float(d.assault) - 0.3 * shaken - 0.2 * short
		why[Option.NEAR_AMBUSH] = "%s, ambushed at %.0f m in the open: no cover in a kill zone, fire, frags and through them" % [odds, range]
	if down > 0:
		s[Option.CASUALTY] = 0.6 + 0.1 * mini(down, 3) + float(d.casualty)
		why[Option.CASUALTY] = "%d down: cover them while they're seen to" % down
	return {"scores": s, "why": why}


# --- Carrying it out ----------------------------------------------------------------------

## The units up and without a command-menu tactic order (they take the option's tasks).
func _free_units() -> Array[SquadAI]:
	var units: Array[SquadAI] = []
	for ai in squad.brains():
		if ai.body.vitals.is_up() and ai.ordered.is_empty():
			units.append(ai)
	return units


## Hands each unit its task for the current option (units with a tactic order keep theirs).
func _carry_out(now: float) -> void:
	var units := _free_units()
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
			_flank(units, enemy, aim, id, now)
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
			_break_contact(units, enemy, aim, id, now)
		Option.NEAR_AMBUSH:
			_near_ambush(units, enemy, aim, id, now)
		Option.CASUALTY:
			for ai in units:
				ai.set_task({"kind": &"base", "aim": aim, "id": id} if aim.is_finite() else {})
		Option.SEARCH:
			_search(units, enemy, id, now)
		_:
			if now < _consolidate_until and _consolidate_at.is_finite():
				_consolidate(units, now)
				return
			for ai in units:
				ai.set_task({})


## The contact drill: the base of fire suppresses `aim` while the maneuver element works round
## the flank (flank_route). Drawn once per contact (again if the squad changes, or if the enemy
## moves REPLAN_M, at most every REPLAN_MIN_S); units on Hold or Move, or with no flank to take,
## join the base. A plan with nobody to flank is remembered (_no_flank): the next think drops
## the drill for something that does something.
func _flank(units: Array[SquadAI], enemy: Vector3, aim: Vector3, id: String, now: float) -> void:
	var names := units.map(func(ai: SquadAI) -> String: return String(ai.body.name))
	if plan.is_empty() or plan.names != names or ((plan.enemy as Vector3).distance_to(enemy) > REPLAN_M and now - _plan_at >= REPLAN_MIN_S):
		plan = _draw_flank(units, enemy, now)
		_log_plan(now)
	if not plan.has("set_at") and (_base_firing(plan.base, float(plan.get("drawn_at", now))) or now - float(plan.get("drawn_at", now)) >= BASE_SET_TIMEOUT_S):
		plan["set_at"] = now  # fire superiority first (T4): the movers go once the base is firing
		if not (plan.moving as Array).is_empty() and not (plan.base as Array).is_empty():
			(plan.base[0] as SquadAI)._callout(&"tactic", "Base is set, move!")
	var going := plan.has("set_at")
	var aims := sector_aims(plan.base, enemy, _base_shift(plan.moving, enemy, plan.base))
	var lifted := _lifted(plan.moving, enemy)
	for ai in units:
		if ai in plan.moving and going:
			ai.set_task({"kind": &"maneuver", "route": (plan.get("lanes", {}) as Dictionary).get(ai, plan.route), "aim": aim, "id": id})
		elif ai in plan.moving:
			ai.set_task({"kind": &"base", "aim": aim, "id": id + ":wait"})  # in cover, firing, until the base is set
		elif lifted:
			ai.set_task({})  # lifted: the movers are on them; eyes on the flanks
		else:
			ai.set_task({"kind": &"base", "aim": aims.get(ai, aim), "id": id, "spot": plan.get("base_spot")})


## The drill's plan for `units` against `enemy`: {"enemy", "names", "base", "moving", "route",
## "side"}. With no maneuver element, no flank to take is remembered.
func _draw_flank(units: Array[SquadAI], enemy: Vector3, now: float) -> Dictionary:
	var names := units.map(func(ai: SquadAI) -> String: return String(ai.body.name))
	var split := elements(units, enemy)
	var base: Array = split[0]
	var moving: Array = split[1].filter(func(ai: SquadAI) -> bool: return ai.order == Squad.Order.FOLLOW or not ai._friendly())
	base.append_array(split[1].filter(func(ai: SquadAI) -> bool: return ai not in moving))
	var lead: Soldier = situation.lead
	var others := _other_clusters()
	var cell := Vector2i(floori(enemy.x / FLANK_MEMORY_CELL_M), floori(enemy.z / FLANK_MEMORY_CELL_M))
	var last: Dictionary = _flank_sides.get(cell, {})
	var avoid := String(last.side) if not last.is_empty() and now - float(last.at) < FLANK_MEMORY_S else ""
	var wide := lead == null and not moving.is_empty() and _middle(moving).distance_to(enemy) >= WIDE_MIN_RANGE_M and randf() < WIDE_CHANCE
	var route := {} if moving.is_empty() else flank_route(moving[0].body, _middle(moving), enemy, lead, others, avoid, wide)
	if not route.is_empty():
		_flank_sides[cell] = {"side": route.side, "at": now}
	if route.is_empty():
		base.append_array(moving)
		moving = []
		_no_flank = {"enemy": enemy, "at": now}
	_plan_at = now
	var drawn_at := now
	var path: Array = route.get("route", [])
	var base_spot: Variant = overwatch_spot(base[0].body, _middle(base), enemy, others, lead) if not base.is_empty() else null
	return {"enemy": enemy, "names": names, "base": base, "moving": moving, "route": path, "side": route.get("side", ""),
		"lanes": lanes(moving, path), "base_spot": base_spot, "drawn_at": drawn_at}


## Each of `units` its own lane along `route`: the route moved sideways (across its start to end)
## LANE_GAP_M apart, man by man, kept on the navmesh. {SquadAI: Array[Vector3]}.
static func lanes(units: Array, route: Array) -> Dictionary:
	var out := {}
	if units.is_empty() or route.size() < 2:
		return out
	var along: Vector3 = route[route.size() - 1] - route[0]
	along.y = 0.0
	if along.length() < 0.5:
		return out
	var across := along.normalized().cross(Vector3.UP)
	var map := (units[0] as SquadAI).body.get_world_3d().navigation_map
	for i in units.size():
		var shift := across * (i - (units.size() - 1) / 2.0) * LANE_GAP_M
		var lane: Array[Vector3] = []
		for p: Vector3 in route:
			lane.append(NavigationServer3D.map_get_closest_point(map, p + shift))
		out[units[i]] = lane
	return out


## The drill's "[tactics]" line, when who does what changed since the last one (or PLAN_LOG_S on).
func _log_plan(now: float) -> void:
	var moving: Array = plan.moving
	var key := "%s|%s|%s" % [_names(plan.base), _names(moving), plan.side]
	if key == _plan_logged.key and now - float(_plan_logged.at) < PLAN_LOG_S:
		return
	_plan_logged = {"key": key, "at": now}
	var enemy: Vector3 = plan.enemy
	print("[tactics] %s: base of fire %s on (%.0f, %.0f)%s" % [squad.name, _names(plan.base), enemy.x, enemy.z,
		(", %s flank %s by %s" % [_names(moving), plan.side, _points(plan.route)]) if not moving.is_empty() else ", no flank to take"])


## Assault: the autorifleman and his buddy (else the pair nearest the enemy) keep their heads
## down, the rest bound onto the position. Units on Hold or Move stay in the base.
func _assault(units: Array[SquadAI], enemy: Vector3, aim: Vector3, id: String) -> void:
	if plan.is_empty() or (plan.enemy as Vector3).distance_to(enemy) > REPLAN_M:
		var base := _gunners_and_buddies(units, enemy)
		plan = {"enemy": enemy, "base": base}
	var map := units[0].body.get_world_3d().navigation_map
	var going: Array = units.filter(func(ai: SquadAI) -> bool: return not (ai in plan.base or (ai._friendly() and ai.order != Squad.Order.FOLLOW)))
	var points := assault_lanes(going, enemy, situation.get("centre", enemy))  # lanes, through to the limit of advance (T6)
	for ai in units:
		if not (ai in going):
			ai.set_task({"kind": &"base", "aim": aim, "id": id})
		else:
			ai.set_task({"kind": &"assault", "point": NavigationServer3D.map_get_closest_point(map, points.get(ai, enemy)), "id": id})


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
		entry = Squad.breacher_first(entry)  # a breacher first at the door, and he makes the way in
		var op := clear_op(b, entry) if not entry.is_empty() else {}
		var through_wall := wall_breach_for(b, entry, op)
		if not through_wall.is_empty():
			op = through_wall  # their own way in, through the wall facing them (entry reordered: the charge's setter first)
			print("[tactics] %s: %s blow a way in through the wall at (%.0f, %.0f)" % [squad.name, _names(entry), op.entrance.door.x, op.entrance.door.z])
		elif not op.is_empty():
			op["breach"] = SquadAI.preferred_breach(entry)
			var bp := squad.breach_plan(b, entry, "auto")
			if not bp.is_empty():
				Squad.apply_plan(op, bp)
			elif op.breach == "charge":
				Squad.stand_off(op)
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
			mark_cleared(first, op.entrance.door)
		print("[tactics] %s: building clear" % squad.name)


## An AI team's own breach and clear (F-318; Squad.order_breach_clear is the order): against the
## held building, with a breaching charge among the entry team, out of Stealth and with nobody
## inside who mustn't be hurt, when the nearest door (`door_op`'s, from clear_op) is round the
## far side, WALL_BREACH_DETOUR_M or more further from the team than the wall facing them, they
## blow their own way in through that wall instead of walking round under the defenders' guns.
## Returns that op (breach_op, its plan on it; `entry` reordered with the charge's setter first),
## {} otherwise. Proposed.
const WALL_BREACH_DETOUR_M := 6.0


func wall_breach_for(b: Dictionary, entry: Array[SquadAI], door_op: Dictionary) -> Dictionary:
	if entry.is_empty() or bool(b.get("yard", false)):
		return {}
	var team := Squad.charge_first(entry)
	if team.is_empty() or team.any(func(ai: SquadAI) -> bool: return ai.combat_mode == Squad.CombatMode.STEALTH) or squad.noncombatant_inside(b):
		return {}
	var from := Vector3.ZERO
	for ai: SquadAI in team:
		from += ai.body.global_position
	from /= team.size()
	var wall := wall_toward(team[0].body.get_world_3d(), b, from)
	if wall.is_empty():
		return {}
	var door_d := INF
	if not door_op.is_empty():
		var outside: Vector3 = door_op.entrance.outside
		door_d = Vector2(outside.x - from.x, outside.z - from.z).length()
	var wall_d := Vector2((wall.at as Vector3).x - from.x, (wall.at as Vector3).z - from.z).length()
	if door_d - wall_d < WALL_BREACH_DETOUR_M:
		return {}
	var op := breach_op(b, team, wall)
	if op.is_empty():
		return {}
	squad.plan_wall_breach(op, b, team)
	entry.assign(team)
	return op


# --- The reels' drills (docs/ai_tactics.md) ------------------------------------------------------

## Contact's start: how close, and whether the squad was moving (a near ambush hits a moving squad
## from close; a squad lying in wait that springs its own ambush isn't ambushed).
func _track_contact(now: float) -> void:
	var c: Vector3 = situation.centre
	_centres.append({"at": now, "pos": c})
	while _centres.size() > 0 and now - float(_centres[0].at) > 3.0:
		_centres.pop_front()
	var engaged := bool(situation.contact)
	if engaged and not _contact_was:
		_contact_began = now
		_contact_range = float(situation.range)
		_moving_at_contact = not _centres.is_empty() and (c as Vector3).distance_to(_centres[0].pos) >= NEAR_MOVING_M
	_contact_was = engaged
	situation["near_ambush"] = engaged and _moving_at_contact and now - _contact_began <= NEAR_WINDOW_S and _contact_range <= NEAR_AMBUSH_M


## T3: moving with no contact, a rally point every RALLY_EVERY_M, RALLY_BACK_M back along the way,
## in cover where there is some (Squad meta "rally").
func _rally_points(now: float) -> void:
	if bool(situation.contact) or int(situation.up) <= 0:
		return
	var c: Vector3 = situation.centre
	if not _rally_from.is_finite():
		_rally_from = c
		return
	if c.distance_to(_rally_from) < RALLY_EVERY_M:
		return
	var back := c + (_rally_from - c).normalized() * RALLY_BACK_M
	var men := squad.brains()
	var spot: Variant = men[0].find_cover(back, 15.0) if not men.is_empty() else null
	squad.set_meta(&"rally", spot if spot != null else back)
	squad.set_meta(&"rally_at", now)
	_rally_from = c
	if squad.faction == &"friendly" and not men.is_empty() and situation.get("lead") != null and (situation.lead as Soldier).is_ai():
		men[0]._callout(&"tactic", "Rally point, %d metres back." % roundi(RALLY_BACK_M))


## Whether any of `base` fired since `since` (its next shot is timed from its last).
static func _base_firing(base: Array, since: float) -> bool:
	for ai: SquadAI in base:
		if is_instance_valid(ai) and ai._next_shot > since + 0.05:
			return true
	return false


## T5: each of the base's men an aim across the enemy and out past both its flanks (SECTOR_EXTRA_M),
## moved `shift` (the far side, when the movers are close). {SquadAI: Vector3}.
static func sector_aims(base: Array, enemy: Vector3, shift := Vector3.ZERO) -> Dictionary:
	var out := {}
	if base.is_empty() or not enemy.is_finite():
		return out
	var c := _middle(base)
	var at := enemy - c
	at.y = 0.0
	var across := at.normalized().cross(Vector3.UP) if at.length() > 0.5 else Vector3.RIGHT
	var width := SECTOR_EXTRA_M * 2.0 + 4.0 * maxi(base.size() - 1, 0)
	for i in base.size():
		var k := 0.0 if base.size() == 1 else float(i) / (base.size() - 1) - 0.5
		out[base[i]] = enemy + shift + across * k * width + Vector3.UP
	return out


## T5's shift: with a mover within SHIFT_M of the enemy, the base fires beyond it (the far side).
func _base_shift(moving: Array, enemy: Vector3, base: Array) -> Vector3:
	if moving.is_empty() or base.is_empty() or not enemy.is_finite():
		return Vector3.ZERO
	var near := moving.any(func(ai: SquadAI) -> bool: return is_instance_valid(ai) and ai.body.global_position.distance_to(enemy) <= SHIFT_M)
	if not near:
		return Vector3.ZERO
	var d := enemy - _middle(base)
	d.y = 0.0
	return d.normalized() * 15.0


## T5's lift: a mover within LIFT_M of the enemy, the base stops suppressing.
static func _lifted(moving: Array, enemy: Vector3) -> bool:
	return enemy.is_finite() and moving.any(func(ai: SquadAI) -> bool: return is_instance_valid(ai) and ai.body.global_position.distance_to(enemy) <= LIFT_M)


## T6: each assaulter a lane LANE_W wide across the enemy, through to THROUGH_M past it (the limit
## of advance), from the squad's side `from`. {SquadAI: Vector3}.
static func assault_lanes(units: Array, enemy: Vector3, from: Vector3) -> Dictionary:
	var out := {}
	if units.is_empty() or not enemy.is_finite():
		return out
	var dir := enemy - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.5 else Vector3.FORWARD
	var across := dir.cross(Vector3.UP)
	var order := units.duplicate()
	order.sort_custom(func(a: SquadAI, b: SquadAI) -> bool: return a.body.global_position.dot(across) < b.body.global_position.dot(across))
	for i in order.size():
		out[order[i]] = enemy + dir * THROUGH_M * 0.6 + across * (i - (order.size() - 1) / 2.0) * LANE_W
	return out


## T1: the gun and his buddy fire; the rest throw frags and CHARGE_DELAY_S later go through the
## enemy line THROUGH_M past it; once they're all through, consolidation facing back.
func _near_ambush(units: Array[SquadAI], enemy: Vector3, aim: Vector3, id: String, now: float) -> void:
	if plan.is_empty() or not plan.has("through"):
		var base := _gunners_and_buddies(units, enemy).slice(0, 2)
		if base.size() == 1 and units.size() > 2:  # the gun and the man nearest him
			var gun: SquadAI = base[0]
			var near: SquadAI = null
			for ai in units:
				if ai != gun and (near == null or ai.body.global_position.distance_to(gun.body.global_position) < near.body.global_position.distance_to(gun.body.global_position)):
					near = ai
			base.append(near)
		var c: Vector3 = situation.centre
		var dir := enemy - c
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.5 else Vector3.FORWARD
		var through := enemy + dir * THROUGH_M
		var going: Array = units.filter(func(ai: SquadAI) -> bool: return not (ai in base))
		plan = {"enemy": enemy, "base": base, "through": through, "lanes": assault_lanes(going, enemy + dir * (THROUGH_M * 0.4), c),
			"go_at": now + CHARGE_DELAY_S}
		print("[tactics] %s: near ambush at %.0f m: %s fire, %s frags and through" % [squad.name, float(situation.range), _names(base), _names(going)])
	for ai in units:
		if ai in plan.base:
			ai.set_task({"kind": &"base", "aim": aim, "id": id})
		else:
			ai.set_task({"kind": &"near_ambush", "enemy": plan.enemy, "point": (plan.lanes as Dictionary).get(ai, plan.through), "go_at": plan.go_at, "id": id})


## T2: Battle Drill 3. The grenadier's smoke, then the man furthest back first, one at a time,
## "Moving!" to his spot at the rally point, "Set!", then the next; those not yet gone keep firing;
## those set hold the perimeter facing the enemy.
func _break_contact(units: Array[SquadAI], enemy: Vector3, aim: Vector3, id: String, now: float) -> void:
	var threat := enemy if enemy.is_finite() else units[0].body.threat_pos
	if plan.is_empty() or not plan.has("order"):
		var order := units.duplicate()
		order.sort_custom(func(a: SquadAI, b: SquadAI) -> bool: return a.body.global_position.distance_to(threat) > b.body.global_position.distance_to(threat))
		var rally := _break_rally(threat)
		var away := rally - threat
		away.y = 0.0
		var across := away.normalized().cross(Vector3.UP) if away.length() > 0.5 else Vector3.RIGHT
		var spots := {}
		for i in order.size():
			spots[order[i]] = rally + across * (i - (order.size() - 1) / 2.0) * BD3_SPREAD_M
		var smoker: SquadAI = null
		for ai in order:
			if ai.body.role == Roles.GRENADIER:
				smoker = ai
		if smoker == null:
			for ai in order:
				if ai.body.inventory.count_of(&"smoke_grenade") > 0:
					smoker = ai
					break
		if smoker:
			smoker._screen_toward_threat(threat)
		plan = {"order": order, "idx": 0, "spots": spots, "rally": rally, "mover_at": now}
		print("[tactics] %s: break contact to (%.0f, %.0f), %s first" % [squad.name, rally.x, rally.z, _names([order[0]])])
		if not order.is_empty():
			(order[0] as SquadAI)._callout(&"tactic", "Moving!")
	var order: Array = plan.order
	var idx: int = plan.idx
	while idx < order.size() and (not is_instance_valid(order[idx]) or not (order[idx] in units)):
		idx += 1
	if idx < order.size():
		var mover: SquadAI = order[idx]
		var spot: Vector3 = plan.spots[mover]
		if mover.body.global_position.distance_to(spot) <= 3.0 or now - float(plan.mover_at) >= BD3_MOVER_S:
			mover._callout(&"tactic", "Set!")
			idx += 1
			plan.mover_at = now
			if idx < order.size() and is_instance_valid(order[idx]):
				(order[idx] as SquadAI)._callout(&"tactic", "Moving!")
	plan.idx = idx
	for i in order.size():
		var ai = order[i]
		if not is_instance_valid(ai) or not (ai in units):
			continue
		var spot: Vector3 = plan.spots[ai]
		if i < idx:
			ai.set_task({"kind": &"garrison", "spot": spot, "face": (threat - spot).normalized(), "id": id + ":set"})
		elif i == idx:
			ai.set_task({"kind": &"break", "point": spot, "id": id + ":move", "smoked": true})
		else:
			ai.set_task({"kind": &"base", "aim": aim if aim.is_finite() else threat + Vector3.UP, "id": id})


## Where break contact goes: the squad's last rally point if it's further from the threat than the
## squad and within 200 m, else BD3_BACK_M straight back.
func _break_rally(threat: Vector3) -> Vector3:
	var c: Vector3 = situation.centre
	var rally: Variant = squad.get_meta(&"rally", null)
	if rally is Vector3 and (rally as Vector3).distance_to(threat) > c.distance_to(threat) + 10.0 and (rally as Vector3).distance_to(c) <= 200.0:
		return rally
	var away := c - threat
	away.y = 0.0
	away = away.normalized() if away.length() > 0.5 else Vector3.BACK
	return c + away * BD3_BACK_M


## T6's end state: all-round security round where the position was taken, each man facing out on
## his own bearing.
func _consolidate(units: Array[SquadAI], now: float) -> void:
	var id := "consolidate@%.0f" % _consolidate_until
	for i in units.size():
		var a := TAU * i / units.size()
		var face := Vector3(sin(a), 0.0, cos(a))
		units[i].set_task({"kind": &"garrison", "spot": _consolidate_at + face * CONSOLIDATE_R, "face": face, "id": id})


## T9 (R06): a cleared building is marked: a chem light at its door, from whoever carries one.
const MARK_LIGHTS: Array[StringName] = [&"chemlight_green", &"chemlight_blue", &"chemlight_red"]
static func mark_cleared(ai: SquadAI, door: Vector3) -> bool:
	for id in MARK_LIGHTS:
		if ai.body.inventory.count_of(id) > 0:
			return ai.order_throw(id, door)
	return false


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
	# A fire team a player leads is his to move (Captain, 2026-10-15: the AI sent a human-led B
	# team to flank while he held): its AI stay with the base of fire, by him; only all-AI teams
	# (or pairs) maneuver.
	var human_teams := {}
	if not units.is_empty():
		for p: Soldier in MapNodes.players((units[0] as SquadAI).body):
			if p.faction == (units[0] as SquadAI).body.faction and p.fire_team >= 0:
				human_teams[p.fire_team] = true
	var held: Array = []
	var free_units: Array = []
	for ai: SquadAI in units:
		if human_teams.has(ai.body.fire_team):
			held.append(ai)
		else:
			free_units.append(ai)
	if not held.is_empty():
		var split := elements_ai(free_units, enemy)
		(split[0] as Array).append_array(held)
		return split
	return elements_ai(units, enemy)


## elements for units no player leads.
static func elements_ai(units: Array, enemy: Vector3) -> Array:
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
static func flank_route(node: Node3D, from: Vector3, enemy: Vector3, lead: Soldier, others: Array, avoid_side := "", wide := false) -> Dictionary:
	var world := node.get_world_3d()
	var map := world.navigation_map
	var u := Vector3(from.x - enemy.x, 0.0, from.z - enemy.z)
	var range := u.length()
	if range < 1.0:
		return {}
	u /= range
	var r := FLANK_WIDE_M if wide else clampf(range * FLANK_RANGE, FLANK_NEAR_M, FLANK_FAR_M)
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
		if route.size() == 2:
			cost -= clampf((route[1].y - enemy.y) * FLANK_HEIGHT_W, 0.0, FLANK_HEIGHT_MAX)  # the high side (G-17)
		if route.size() < 2:
			continue
		for e: Vector3 in others:
			if e.distance_to(route[1]) < r:
				cost += 0.5  # someone else over there
		var side := "right" if (route[1] - enemy).dot(right) > 0.0 else "left"
		if side == avoid_side:
			cost += FLANK_SAME_SIDE_COST  # went that way at him last time: the other side now (G-21)
		if cost < best_cost:
			best_cost = cost
			best = {"side": side, "route": route, "wide": wide}
	return best


## A base of fire's spot round `from` against `enemy` (see OVERWATCH_RINGS): high ground with a
## line on him, a short walk, out of other groups' sight; null to stay where it is.
static func overwatch_spot(node: Node3D, from: Vector3, enemy: Vector3, others: Array, lead: Soldier = null) -> Variant:
	var world := node.get_world_3d()
	var map := world.navigation_map
	var here := NavigationServer3D.map_get_closest_point(map, from)
	var range := Vector2(from.x - enemy.x, from.z - enemy.z).length()
	var best: Variant = null
	var best_score := overwatch_score(world, here, from, enemy, others) - OVERWATCH_GAIN
	for ring in OVERWATCH_RINGS:
		for k in 12:
			var angle := TAU * k / 12.0 + ring
			var p := from + Vector3(cos(angle), 0.0, sin(angle)) * ring
			if lead != null:
				p = _leashed(p, lead.global_position, FOLLOW_LEASH_M)
			var q := NavigationServer3D.map_get_closest_point(map, p)
			if Vector2(q.x - p.x, q.z - p.z).length() > PLAN_SNAP_M * 0.5 or Vector2(q.x - enemy.x, q.z - enemy.z).length() < range * OVERWATCH_NEAREST:
				continue
			var s := overwatch_score(world, q, from, enemy, others)
			if s < best_score:
				best = q
				best_score = s
	return best


## How good `q` is to fire on `enemy` from (lower is better; INF with no line on him).
static func overwatch_score(world: World3D, q: Vector3, from: Vector3, enemy: Vector3, others: Array) -> float:
	if not Throwables.clear_line(world, q + Vector3.UP * 1.6, enemy + Vector3.UP * 1.2):
		return INF
	var s := Vector2(q.x - from.x, q.z - from.z).length() * OVERWATCH_WALK_W - clampf(q.y - enemy.y, 0.0, OVERWATCH_HEIGHT_MAX_M) * OVERWATCH_HEIGHT_W
	for e: Vector3 in others:
		if e.distance_to(q) < OVERWATCH_OTHERS_M and Throwables.clear_line(world, q + Vector3.UP * 1.6, e + Vector3.UP * 1.2):
			s += OVERWATCH_EXPOSED
	return s


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
## `entrance` (a breach and clear's hole to be: breach_op) stands in for the building's own nearest
## entrance; with `first_near` finite, the ground floor's rooms are taken nearest it first.
static func clear_op(b: Dictionary, units: Array, entrance := {}, first_near := Vector3.INF) -> Dictionary:
	if units.is_empty() or b.get("rooms", []).is_empty():
		return {}
	var from := Vector3.ZERO
	for ai: SquadAI in units:
		from += ai.body.global_position
	from /= units.size()
	var e := Buildings.entrance_near(b, from) if entrance.is_empty() else entrance
	if e.is_empty():
		return {}
	var normal: Vector3 = e.normal
	var along := normal.cross(Vector3.UP)
	var side := 1.0 if (from - (e.door as Vector3)).dot(along) >= 0.0 else -1.0
	var map := (units[0] as SquadAI).body.get_world_3d().navigation_map
	var stack: Array[Vector3] = []
	for i in units.size():
		stack.append(stack_spot(b, e, map, side, i, stack))
	# Each floor's rooms (a building scanned before floors were kept is all one floor).
	var per_floor: Array = []
	for f: Dictionary in b.get("floors", []):
		if not (f.rooms as Array).is_empty():
			per_floor.append(f.rooms)
	if per_floor.is_empty():
		per_floor.append(range(b.rooms.size()))
	if first_near.is_finite():
		var nearest_first: Array = (per_floor[0] as Array).duplicate()
		nearest_first.sort_custom(func(i: int, j: int) -> bool:
			return (b.rooms[i].centre as Vector3).distance_to(first_near) < (b.rooms[j].centre as Vector3).distance_to(first_near))
		per_floor[0] = nearest_first
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


## Breach and clear (Captain's list 2026-10-14, item 3: "add a 'Breach and clear' team order
## through walls"; F-318): a clearance (clear_op) whose way in is a hole the team blows in a wall,
## `wall` ({"at": a point on the wall's outer face, "face": its outward normal}; wall_at,
## wall_toward). Its entrance is the wall's foot there ("door" just off the face, "normal" the
## face, "inside" past the wall), so the stack forms along that wall (stack_spot; then stood off
## from the charge: Squad.stand_off) and the rooms nearest the hole are taken first. The op
## carries "wall": true, "charge_spot" (the charge goes where he pointed: SquadAI._work_door) and
## "step_m", how far in from the hole each man steps before his corner (the wall's thickness and
## a stride, not a doorway's DOORWAY_STEP_M). `b` may be a yard (yard_beyond). {} with no rooms.
## Proposed.
const BREACH_STEP_PAST_M := 0.7
const WALL_DEPTH_GUESS_M := 0.4


static func breach_op(b: Dictionary, units: Array, wall: Dictionary) -> Dictionary:
	if units.is_empty() or wall.is_empty():
		return {}
	var body := (units[0] as SquadAI).body
	var at: Vector3 = wall.at
	var face: Vector3 = wall.face
	var lvl := CompoundLevel.current(body) as Node3D
	var depth := Charges.wall_depth(lvl, at, face) if lvl else -1.0
	if depth < 0.0:
		depth = WALL_DEPTH_GUESS_M
	var map := body.get_world_3d().navigation_map
	var foot := NavigationServer3D.map_get_closest_point(map, at + face * 0.6)
	var door := Vector3(at.x, foot.y, at.z) + face * 0.3
	var e := {"door": door, "inside": door - face * (0.3 + depth + BREACH_STEP_PAST_M), "outside": door + face * Buildings.OUTSIDE_M,
		"normal": face, "wall": true}
	var op := clear_op(b, units, e, at - face * (depth + 1.0))
	if op.is_empty():
		return {}
	op["wall"] = true
	op["charge_spot"] = {"at": at, "face": face}
	op["step_m"] = 0.3 + depth + BREACH_STEP_PAST_M
	op["stages"] = []
	note_stage(op, "stacking")
	return op


## The wall a leader points at: `point` (on the voxels, from his crosshair) on a wall's face seen
## from `from` ({"at", "face"}: the face's outward normal, level), or {} if it isn't on a wall
## (the ground, a roof, a doorway's open air). The charge goes on BREACH_CHARGE_Y over the
## ground at the wall's foot wherever on the wall he points (a charge set by hand sits about
## there). Proposed.
const BREACH_CHARGE_Y := 1.0


static func wall_at(from: Soldier, point: Vector3) -> Dictionary:
	if from == null or not from.is_inside_tree() or not point.is_finite():
		return {}
	var space := from.get_world_3d().direct_space_state
	var eye := from.camera.global_position if from.camera else from.global_position + Vector3.UP * 1.6
	var dir := point - eye
	if dir.length() < 0.05:
		return {}
	dir = dir.normalized()
	var query := PhysicsRayQueryParameters3D.create(point - dir * 0.5, point + dir * 0.5, 1)
	query.hit_back_faces = false
	var hit := space.intersect_ray(query)
	if hit.is_empty() or absf((hit.normal as Vector3).y) >= Charges.WALL_NORMAL_Y:
		return {}
	var face := Vector3((hit.normal as Vector3).x, 0.0, (hit.normal as Vector3).z).normalized()
	return _wall_spot(space, hit.position, face)


## The wall of building `b` facing `from` (a point outside it: the team): the outer face where a
## level ray from `from`'s side meets the wall in front of `b`'s ground-floor spot nearest `from`
## ({"at", "face"}), {} if none is found within WALL_PROBE_M (another wall, or open ground).
const WALL_PROBE_M := 5.0


static func wall_toward(world: World3D, b: Dictionary, from: Vector3) -> Dictionary:
	var best := Vector3.INF
	var floors: Array = b.get("floors", [])
	var spots: Array = (floors[0].spots as Array) if not floors.is_empty() else b.get("spots", [])
	for s: Vector3 in spots:
		if not best.is_finite() or Vector2(s.x - from.x, s.z - from.z).length() < Vector2(best.x - from.x, best.z - from.z).length():
			best = s
	if not best.is_finite():
		return {}
	var dir := Vector3(best.x - from.x, 0.0, best.z - from.z)
	if dir.length() < 0.5:
		return {}
	dir = dir.normalized()
	var to := best + Vector3.UP * BREACH_CHARGE_Y
	var space := world.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(to - dir * WALL_PROBE_M, to, 1)
	query.hit_back_faces = false
	var hit := space.intersect_ray(query)
	if hit.is_empty() or absf((hit.normal as Vector3).y) >= Charges.WALL_NORMAL_Y or (hit.normal as Vector3).dot(dir) > -0.5:
		return {}
	return _wall_spot(space, hit.position, Vector3((hit.normal as Vector3).x, 0.0, (hit.normal as Vector3).z).normalized())


## A charge's spot on the wall face at `p` (`face` outward): BREACH_CHARGE_Y over the ground at
## its foot (as Charges.floor_under finds it).
static func _wall_spot(space: PhysicsDirectSpaceState3D, p: Vector3, face: Vector3) -> Dictionary:
	var from := p + face * 0.35 + Vector3.UP * 0.1
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0, 1))
	var ground := (down.position as Vector3).y if not down.is_empty() else p.y - BREACH_CHARGE_Y
	return {"at": Vector3(p.x, ground + BREACH_CHARGE_Y, p.z), "face": face}


## A wall with no building behind it (a compound's perimeter, a yard wall): what's past it, as a
## building of one "room" for breach_op: YARD_IN_M in past the wall, its corners fanned
## YARD_SPREAD_M either side and two further in, on the navmesh (the far side is baked though
## nobody can reach it through the wall yet). {} if the navmesh has nothing there, or if it's
## a building's inside by Buildings' own test (_indoors: an inside has navmesh too, so a
## building lookup that missed it mustn't make it a yard). Proposed.
const YARD_IN_M := 2.0
const YARD_SPREAD_M := 1.6


static func yard_beyond(world: World3D, wall: Dictionary) -> Dictionary:
	var at: Vector3 = wall.at
	var face: Vector3 = wall.face
	var along := face.cross(Vector3.UP)
	var map := world.navigation_map
	var c := at - face * (WALL_DEPTH_GUESS_M + YARD_IN_M)
	var corners: Array[Vector3] = []
	for off: Vector3 in [along * YARD_SPREAD_M, -along * YARD_SPREAD_M, along * YARD_SPREAD_M * 0.5 - face * 1.5, -along * YARD_SPREAD_M * 0.5 - face * 1.5]:
		var want := c + off
		var p := NavigationServer3D.map_get_closest_point(map, want)
		if Vector2(p.x - want.x, p.z - want.z).length() > 0.8 or (p - at).dot(face) > -0.2:
			return {}
		corners.append(p)
	var mid := NavigationServer3D.map_get_closest_point(map, c)
	var five: Array[Vector3] = [mid]
	five.append_array(corners)
	if _indoors(world, five) >= INDOORS_MIN:
		return {}
	return {"centre": mid, "spots": corners.duplicate(), "rooms": [{"spots": corners.duplicate(), "centre": mid, "corners": corners, "floor": 0}],
		"floors": [], "entrances": [], "ports": [], "stairs": [], "yard": true}


## Whether what's past `wall` is a building's inside, whether or not Buildings found one there
## (F-322; review of 7b6d7576): INDOORS_MIN or more of the five spots yard_beyond takes (its
## middle and corners, on the navmesh where it has them) pass Buildings.inside, the test its
## scans make every inside spot pass (walls round it, or a hall's roof and walls further off).
## A compound's yard is open along the wall both ways; the compound's main building has no
## roof, so a roof alone can't tell. Proposed.
const INDOORS_MIN := 3


static func building_beyond(world: World3D, wall: Dictionary) -> bool:
	var at: Vector3 = wall.at
	var face: Vector3 = wall.face
	var along := face.cross(Vector3.UP)
	var c := at - face * (WALL_DEPTH_GUESS_M + YARD_IN_M)
	var map := world.navigation_map
	var five: Array[Vector3] = []
	for off: Vector3 in [Vector3.ZERO, along * YARD_SPREAD_M, -along * YARD_SPREAD_M, along * YARD_SPREAD_M * 0.5 - face * 1.5, -along * YARD_SPREAD_M * 0.5 - face * 1.5]:
		var want := c + off
		var p := NavigationServer3D.map_get_closest_point(map, want)
		five.append(p if Vector2(p.x - want.x, p.z - want.z).length() <= 0.8 else want + Vector3.DOWN * BREACH_CHARGE_Y)
	return _indoors(world, five) >= INDOORS_MIN


## How many of `spots` (on the navmesh, which floats a little over the floor) are inside a
## building by Buildings.inside, probed from the floor under each as its scans probe theirs.
static func _indoors(world: World3D, spots: Array[Vector3]) -> int:
	var space := world.direct_space_state
	var count := 0
	for p: Vector3 in spots:
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.3, p + Vector3.DOWN * 1.0, 1))
		if Buildings.inside(world, (down.position as Vector3) if not down.is_empty() else p):
			count += 1
	return count


## Breach and clear's stages, in the order they happen ("stacking", "stacked", "charge_set",
## "backed_off", "blown", "hole_open", "through", "clear"): each noted once on the op ("stages",
## with when), and in the session log. Only on a breach and clear's op (one with "stages").
static func note_stage(op: Dictionary, stage: String) -> void:
	if not op.has("stages"):
		return
	var stages: Array = op.stages
	for s: Dictionary in stages:
		if s.name == stage:
			return
	stages.append({"name": stage, "at": Soldier._now()})
	SessionLog.note("breach and clear: %s" % stage)


## Stack spot `i` beside entrance `e` of building `b` (STACK_OUT_TRIES): outside it, on the
## door's outer side, the `side` of the door the team came from first; clear of the spots `taken`.
static func stack_spot(b: Dictionary, e: Dictionary, map: RID, side: float, i: int, taken: Array[Vector3] = []) -> Vector3:
	var door: Vector3 = e.door
	var normal: Vector3 = e.normal
	var along := normal.cross(Vector3.UP)
	for s: float in [side, -side]:
		for out_m: float in STACK_OUT_TRIES:
			var want := door + normal * out_m + along * s * (STACK_FIRST_M + STACK_GAP_M * i)
			var got := NavigationServer3D.map_get_closest_point(map, want)
			if stack_spot_ok(b, door, normal, want, got) and not taken.any(func(p: Vector3) -> bool: return p.distance_to(got) < STACK_GAP_M * 0.6):
				return got
	return NavigationServer3D.map_get_closest_point(map, door + normal * (STACK_FIRST_M + STACK_GAP_M * i + 0.5))  # a column, straight out


## Whether a stack spot the navmesh gave (`got`, asked for `want`) is a good one: not pulled
## through a wall, outside building `b`, on the door's outer side.
static func stack_spot_ok(b: Dictionary, door: Vector3, normal: Vector3, want: Vector3, got: Vector3) -> bool:
	return Vector2(got.x - want.x, got.z - want.z).length() <= STACK_SNAP_M and not Buildings.contains(b, got) \
		and Vector3(got.x - door.x, 0.0, got.z - door.z).dot(normal) > 0.2


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
