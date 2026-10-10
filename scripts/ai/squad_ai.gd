class_name SquadAI
extends Node
## Host-only brain for an AI Soldier. It drives the body only through the body's intent
## fields and the same host-validated requests a player sends (fire, reload, heal, revive),
## so AI follows the same rules for ammo, reload time and revive time.
##
## Every THINK_S each intent scores itself 0..1 and the best one wins, with hysteresis so
## close scores don't flip back and forth. Fighting is one intent with fire-team tactics
## inside it:
## - Take cover that blocks the threat, crouch when not shooting, stand up to fire bursts.
## - Rounds landing close suppress; a pinned soldier stays down and doesn't shoot.
## - Battle buddies never move at the same time: while one bounds to new cover, the other
##   holds and puts covering fire on the last known threat (bounding overwatch).
## - A frag goes to an enemy who stays hidden behind cover.
## Command menu orders shape this: movement orders, hold fire, Target (focus fire on one
## enemy) and Combat mode (Squad.CombatMode):
## - Safe: walk with the weapon lowered and don't start a fight; return fire once the squad
##   is fired upon.
## - Aware: upright and alert; fight from cover on contact.
## - Combat (default): as Aware, and crouch whenever halted.
## - Stealth: always crouched, never sprint; open fire only when fired upon or an enemy is
##   very close.
## Squadmates call out what they do (Callouts): contact, reloading, grenades, bounding.
##
## Casualty care on the wound model (design doc "Downed friendlies", "Medics" and "Fits the
## squad decisions"), for both sides and for players like anyone else. It uses only the
## treatment interface: Vitals.care_needed(), wound_list(), is_unconscious(), and the host
## requests Soldier._server_treat (one item on one body part) and _server_revive (stopgap).
## - Who answers: the casualty's fire-team medic, otherwise their battle buddy, otherwise
##   the other medic (when the team's medic is down, busy or far), otherwise the nearest free
##   squadmate (responder_for). They say "Moving to Charlie", then "Treating Charlie".
## - Under fire: smoke between the casualty and the threat, drag them to cover, tourniquet
##   for massive bleeding only, then guard them. Once safe: massive bleeding, airway (NPA),
##   chest seal, bandages and gauze, splint, then morphine for a conscious casualty in heavy
##   pain (plan_care), re-checking care_needed() between items until nothing is left.
## - A casualty still unconscious once their bleeding is controlled gets the stopgap revive
##   from a medic with a trauma kit (until IV in wave 3). Anyone else who can do no more asks
##   for a medic ("Need a medic on Charlie") and carries the casualty after the squad leader;
##   a free medic with what's missing takes over (medic_for).
## - Self-care: a conscious wounded unit tourniquets its own arterial bleed at once, even
##   under fire, and does the rest (bandages, seals, splints, morphine) out of contact or in
##   cover. What it can't fix itself, it calls "Medic!" for.
## - Dead friendlies stay where they fell; out of contact a squadmate (their buddy first)
##   carries the body after the squad leader.
## - Unconscious foes are ignored, except for a dead-check while clearing or assaulting
##   through a position (DEAD_CHECK_M).

enum Intent { FOLLOW, HOLD, MOVE_TO, PATROL, INVESTIGATE, FIGHT, CASUALTY, RELOAD, HEAL }
## Casualty care: NONE, the living-casualty steps (REACH to GUARD and CARRY), or carrying a
## dead friendly's BODY.
enum Care { NONE, REACH, DRAG, TREAT, GUARD, CARRY, BODY }

const THINK_S := 0.5
const SCAN_S := 0.3
const CONTACT_MEMORY_S := 8.0
const INVESTIGATE_MEMORY_S := 25.0
const SIGHT_RANGE := 60.0
const SUPPRESSED := 0.5
const PINNED := 0.85
const HYSTERESIS := 0.1
const ARRIVE := 0.7
const RUN_DISTANCE := 5.0
const WAYPOINT_REACH := 0.45
const REPATH_S := 1.0
const COVER_RINGS: Array[float] = [2.0, 4.0, 6.0, 8.0, 10.0]
const COVER_SEARCH_S := 1.0
const ADVANCE_AFTER_S := 6.0
const ADVANCE_STEP := 8.0
const WORLD_MASK := 1
const TURN_RATE := 7.0
const GRENADE_COOLDOWN_S := 15.0
## Points checked along a frag's arc before throwing it (_lob_clear).
const LOB_CHECKS := 10
const CASUALTY_REACH := 1.6
## The kits Soldier._server_revive (the stopgap revive) can use.
const REVIVE_KITS: Array[StringName] = [&"trauma_kit", &"ifak"]
## AI uses the stopgap revive only as a medic with this kit (until IV in wave 3).
const MEDIC_REVIVE_KIT := &"trauma_kit"
## Proposed: a fire team's medic further than this from a casualty counts as far, so the
## buddy or the other medic answers instead.
const MEDIC_FAR_M := 40.0
## Proposed: under fire, smoke goes between a casualty in the open and the threat from this
## close to them.
const SMOKE_RANGE_M := 25.0
## Under fire only massive bleeding is treated (a tourniquet); the rest waits for cover.
const UNDER_FIRE_KINDS: Array[String] = ["arterial"]
## The care order once safe, by care_needed() kind: massive bleeding, airway, chest, the
## other bleeding, fractures, pain. Kinds not listed go just before pain.
const CARE_RANK: Array[String] = ["arterial", "airway", "chest", "junctional", "venous", "internal", "muscle", "graze", "fracture", "pain"]
## care_needed() kinds that are bleeding (the stopgap revive waits until none are left).
const BLEED_KINDS: Array[String] = ["arterial", "junctional", "venous", "internal", "muscle", "graze", "chest"]
## Proposed: seconds past an item's time before checking whether it worked.
const TREAT_MARGIN_S := 0.4
## Proposed: tries at one task (same body, part and kind) that change nothing before giving up on it.
const TREAT_TRIES := 2
## Proposed: an unconscious casualty whose bleeding is controlled gets this long to wake on
## their own before the medic uses the stopgap revive.
const REVIVE_WAIT_S := 6.0
## Proposed: morphine only for a conscious casualty in at least this much pain.
const MORPHINE_PAIN := 0.5
## Proposed: a wounded unit calls "Medic!" at most this often, and counts as asking for that long.
const MEDIC_CALL_S := 20.0
## Proposed: how close a carer must be for a conscious casualty to stop and be treated.
const BEING_TREATED_M := 6.0
## Proposed: out of contact, squadmates recover friendly bodies within this range.
const BODY_RECOVER_M := 60.0
## Proposed: how much recovering a fallen friendly's body scores out of contact. Above
## following, holding and moving (0.5) plus HYSTERESIS, so a squadmate who is following
## switches to it; below fighting (0.7), a low-magazine reload (0.65) and casualty care.
const BODY_RECOVER_SCORE := 0.63
## Proposed: a responder whose distance to the casualty hasn't closed by REACH_PROGRESS_M in
## REACH_STUCK_S (something the navmesh doesn't know about is in the way, such as a player)
## sidesteps DETOUR_M for DETOUR_S, alternating sides. After REACH_GIVE_UP_S without getting
## closer it hands the casualty on and leaves them to others for REACH_SKIP_S.
const REACH_PROGRESS_M := 0.5
const REACH_STUCK_S := 1.5
const DETOUR_M := 1.8
const DETOUR_S := 1.2
const REACH_GIVE_UP_S := 12.0
const REACH_SKIP_S := 20.0
## Proposed: while clearing or assaulting through a position, unconscious foes this close get
## dead-checked (shot); otherwise targeting skips them.
const DEAD_CHECK_M := 8.0
## Proposed: in Stealth, open fire unprovoked only at an enemy this close.
const STEALTH_ENGAGE_M := 15.0
## Proposed: in Safe, only run to catch up from this far behind.
const SAFE_CATCH_UP_M := 15.0
## Suppression or injury rising this much in one frame means this unit was fired upon.
const FIRED_ON_SUPPRESSION := 0.001
const FIRED_ON_INJURY := 0.02
## Proposed: don't shoot when a friendly is this close (metres) to the line of fire.
const FRIENDLY_CLEARANCE := 0.7

## 0..1: aim error and reaction speed.
@export var combat := 0.6
## 0..1: how firmly orders are kept under fire.
@export var discipline := 0.6
## Hostiles: stay at the post instead of walking the patrol route.
@export var guard := false

var body: Soldier
var squad: Squad
## Battle buddy (lives on the body, so players have one too).
var buddy: Soldier:
	get:
		var s := get_parent() as Soldier
		return s.buddy if s else null
var intent := Intent.FOLLOW
var target: Soldier
## This unit's standing order (friendlies), set from the command menu.
var order := Squad.Order.FOLLOW
## Command menu "Hold fire": don't shoot at all until told to open fire.
var hold_fire := false
## Command menu "Combat mode": how this unit moves, fires and holds stance.
var combat_mode := Squad.CombatMode.COMBAT
## Command menu "Target": the enemy to focus fire on while it can be seen (null: free choice).
var focus: Soldier
var care := Care.NONE
## Who this unit looks after (a living casualty, or a dead friendly's body for Care.BODY).
var casualty: Soldier
## Looking after a casualty and unable to do more: asks for a medic who has `wanted`.
var wants_medic := false
## Items (and MEDIC_REVIVE_KIT for the stopgap revive) this unit lacks for its casualty, or
## for itself when it calls "Medic!".
var wanted: Array[StringName] = []
## True while moving to new cover in contact (the buddy holds and covers meanwhile).
var bounding := false

var _path := PackedVector3Array()
var _path_index := 0
var _path_target := Vector3.INF
var _repath_cd := 0.0
var _destination := Vector3.ZERO
var _has_destination := false
var _run := false
var _cover_point := Vector3.ZERO
var _has_cover := false
var _hold_point := Vector3.ZERO
var _move_point := Vector3.ZERO
var _patrol_index := 0
var _think_cd := 0.0
var _scan_cd := 0.0
var _cover_cd := 0.0
var _grenade_cd := GRENADE_COOLDOWN_S * 0.4
var _last_contact := -1000.0
var _no_los_s := 0.0
var _burst_left := 0
var _pause_until := 0.0
var _next_shot := 0.0
var _advance_anchor := Vector3.ZERO
var _advancing := false
var _smoke_used := false
var _candidate: Soldier  # a casualty this unit should answer (refreshed each think)
var _treat_until := -1.0  # an item or a revive in progress until then
var _treat_target: Soldier
var _treat_key := ""
var _treat_before := 0
var _reviving := false
var _failures := {}  # task key -> treatments that changed nothing
var _controlled_at := -1.0  # when the casualty's bleeding was first seen controlled
var _asked_medic := false
var _answered := false
var _medic_called_at := -1000.0
var _reach_best := INF  # closest this unit got to its casualty on the way (Care.REACH)
var _reach_progress_at := 0.0  # when it last got REACH_PROGRESS_M closer
var _detour := Vector3.ZERO  # a sidestep around something in the way
var _detour_until := -1.0
var _detour_next := -1.0  # no new sidestep before then (try the direct way in between)
var _detour_side := 1.0
var _skip := {}  # casualty instance id -> Soldier._now() until which this unit leaves them to others
var _dead_check: Soldier  # an unconscious foe being dead-checked, kept until dead or out of range
var _score := 0.0
var _ready_done := false
var _was_bounding := false
var _fired_on_at := -1000.0
var _last_suppression := 0.0
var _last_injury := 0.0


static func of(s: Node) -> SquadAI:
	return s.get_node_or_null(^"SquadAI") as SquadAI if s else null


func _physics_process(delta: float) -> void:
	if not _ready_done:
		_setup()
		return
	var now := Soldier._now()
	if _treat_until >= 0.0 and now >= _treat_until:
		_finish_treatment()
	if not body.vitals.is_up():
		_stop()
		if care != Care.NONE:
			_end_care()
		body.ai_status = body.vitals.condition_text()
		return
	_grenade_cd -= delta
	_cover_cd -= delta
	_notice_fire(now)
	if body.threat_time > _last_contact:
		_last_contact = body.threat_time
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_S
		var previous := target
		target = _find_target()
		if target != null and target != previous and target.vitals.is_up():
			_next_shot = maxf(_next_shot, now + lerpf(0.9, 0.25, combat))  # reaction time
			var callouts := Callouts.of(body)
			if callouts:
				callouts.contact(body, target)
	if target != null and target.vitals.is_up():
		_last_contact = now
		body.threat_pos = target.global_position
		body.threat_time = now
		_no_los_s = 0.0
	else:
		_no_los_s += delta  # a body being dead-checked is no contact
	_think_cd -= delta
	if _think_cd <= 0.0:
		_think_cd = THINK_S
		_choose_intent()
	_act()
	_steer(delta)
	_shoot()
	body.ai_status = status_text()


func in_contact() -> bool:
	return Soldier._now() - _last_contact < CONTACT_MEMORY_S


## In contact and willing to fight: Safe units leave a contact alone until fired upon.
func fighting() -> bool:
	return in_contact() and (combat_mode != Squad.CombatMode.SAFE or engaged())


## This unit, or its squad, was fired upon recently.
func engaged() -> bool:
	return Soldier._now() - _fired_on_at < CONTACT_MEMORY_S or (squad != null and squad.is_engaged())


## Whether the orders and combat mode let this unit shoot at what it sees now.
func weapons_free() -> bool:
	if hold_fire:
		return false
	match combat_mode:
		Squad.CombatMode.SAFE:
			return engaged()
		Squad.CombatMode.STEALTH:
			return engaged() or (target != null and body.global_position.distance_to(target.global_position) <= STEALTH_ENGAGE_M)
	return true


## An order from the command menu. `slot` and `count` spread a group of units around the
## point so they don't all head for the same spot.
func on_order(new_order: Squad.Order, point: Vector3, slot := 0, count := 1) -> void:
	order = new_order
	_hold_point = body.global_position
	var side := squad.leader.global_basis.x if squad and is_instance_valid(squad.leader) else body.global_basis.x
	_move_point = point + side * (slot - (count - 1) / 2.0) * 1.5
	_has_cover = false
	_think_cd = 0.0


## Command menu action: throw a grenade at a point. False if this unit can't.
func order_throw(id: StringName, point: Vector3) -> bool:
	if not body.vitals.is_up() or body.carrying != null:
		return false
	_aim_at(point)
	return _throw(id, point)


func status_text() -> String:
	var who := _name_of(casualty)
	match intent:
		Intent.CASUALTY:
			match care:
				Care.REACH:
					return "Going to %s" % who
				Care.DRAG:
					return "Dragging %s to cover" % who
				Care.TREAT:
					if _reviving:
						return "Reviving %s" % who
					return "Treating %s" % who
				Care.GUARD:
					return "Guarding %s" % who
				Care.CARRY:
					return "Carrying %s" % who
				Care.BODY:
					return "Carrying %s's body" % who if body.carrying == casualty else "Recovering %s's body" % who
		Intent.FIGHT:
			if body.stunned_s > 0.0:
				return "Blinded"
			if body.suppression >= PINNED:
				return "Pinned down"
			if bounding:
				return "Bounding"
			return "Engaging" if target else ("In cover" if _at_cover() else "In contact")
		Intent.RELOAD:
			return "Reloading"
		Intent.HEAL:
			if _being_treated():
				return "Being treated"
			return "Treating self" if _treat_target == body and _treat_until >= 0.0 else "Patching up"
		Intent.HOLD:
			return "Holding"
		Intent.MOVE_TO:
			return "Moving" if body.global_position.distance_to(_move_point) > ARRIVE + 0.5 else "In position"
		Intent.PATROL:
			return "Patrolling"
		Intent.INVESTIGATE:
			return "Searching"
	return "Following"


# --- Setup ----------------------------------------------------------------

func _setup() -> void:
	body = get_parent() as Soldier
	if body == null or not body.is_node_ready():
		return
	_hold_point = body.global_position
	_move_point = body.global_position
	_ready_done = true
	_pass_through_squadmates()


## AI on the same side moves through each other (host only, where AI moves): squadmates
## crowding a doorway or a casualty no longer wedge each other in. Players still bump into
## AI and AI into players.
func _pass_through_squadmates() -> void:
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var other := n as Soldier
		if other and other != body and other.is_ai() and other.faction == body.faction:
			body.add_collision_exception_with(other)
			other.add_collision_exception_with(body)


# --- Intent selection -----------------------------------------------------

func _choose_intent() -> void:
	var scores := {}
	var contact := in_contact()
	var weapon := body.active_weapon()
	var rounds := body.inventory.rounds_in(body.active_slot) if weapon else 0
	var full := _mag_size(weapon)
	var spare := body.inventory.spare_rounds(Soldier._ammo_of(weapon)) if weapon else 0

	if body.faction == &"friendly":
		match order:
			Squad.Order.FOLLOW:
				scores[Intent.FOLLOW] = 0.5
			Squad.Order.HOLD:
				scores[Intent.HOLD] = 0.5
			Squad.Order.MOVE:
				# Disciplined soldiers keep moving under fire a little longer.
				scores[Intent.MOVE_TO] = 0.5 + (0.25 * discipline if contact else 0.0)
	else:
		scores[Intent.PATROL] = 0.3
		if Soldier._now() - _last_contact < INVESTIGATE_MEMORY_S:
			scores[Intent.INVESTIGATE] = 0.55
	# Casualty care, both sides: a living casualty comes before almost anything; a fallen
	# friendly's body is carried only out of contact.
	_candidate = _find_casualty() if care == Care.NONE or care == Care.BODY else null
	if (care != Care.NONE and care != Care.BODY) or _candidate != null:
		scores[Intent.CASUALTY] = 0.9
	elif not contact and (care == Care.BODY or _find_body() != null):
		scores[Intent.CASUALTY] = BODY_RECOVER_SCORE
	_maybe_call_medic()
	if fighting():
		scores[Intent.FIGHT] = 0.7
	if weapon and rounds == 0 and spare > 0:
		scores[Intent.RELOAD] = 0.95
	elif weapon and rounds < full * 0.35 and spare > 0 and target == null:
		scores[Intent.RELOAD] = 0.65
	var heal := _self_care_score()
	if heal > 0.0:
		scores[Intent.HEAL] = heal

	var best: Intent = intent
	var best_score := -1.0
	for key: Intent in scores:
		if scores[key] > best_score:
			best = key
			best_score = scores[key]
	var current: float = scores.get(intent, -1.0)
	if best != intent and best_score < current + HYSTERESIS:
		return
	if best != intent:
		if intent == Intent.CASUALTY and care != Care.NONE and care != Care.BODY and best_score < 0.95:
			return  # don't abandon a casualty for anything short of an empty magazine or your own bleed
		intent = best
		_score = best_score
		if intent != Intent.CASUALTY and care == Care.BODY:
			_end_care()  # put the body down to fight


# --- Acting ---------------------------------------------------------------

func _act() -> void:
	body.want_crouch = false
	_was_bounding = bounding
	bounding = false  # only _fight moves to cover
	body.want_aim = target != null
	match intent:
		Intent.FOLLOW:
			if fighting():
				_fight(squad.leader.global_position if squad and is_instance_valid(squad.leader) else body.global_position, 8.0)
			else:
				_go(squad.follow_point(body) if squad else body.global_position)
		Intent.HOLD:
			if fighting():
				_fight(_hold_point, 4.0)
			else:
				_go(_hold_point, false)
		Intent.MOVE_TO:
			_go(_move_point, true)
			if body.global_position.distance_to(_move_point) <= ARRIVE + 0.5:
				_hold_point = _move_point
		Intent.PATROL:
			_patrol()
		Intent.INVESTIGATE:
			_go(body.threat_pos, false)
		Intent.FIGHT:
			_fight_from_context()
		Intent.RELOAD:
			_do_reload()
		Intent.HEAL:
			_do_self_care()
		Intent.CASUALTY:
			_do_care()
	_apply_combat_mode()


## Combat mode stance and weapon carry for the movement and fighting intents (reloading,
## healing and casualty care keep their own stance).
func _apply_combat_mode() -> void:
	if intent in [Intent.RELOAD, Intent.HEAL, Intent.CASUALTY]:
		return
	var fight := intent == Intent.FIGHT or fighting()
	match combat_mode:
		Squad.CombatMode.SAFE:
			if not fight:
				body.want_aim = false  # weapon lowered
				body.want_crouch = false
		Squad.CombatMode.COMBAT:
			if not fight and _halted():
				body.want_crouch = true
		Squad.CombatMode.STEALTH:
			body.want_crouch = true


## Standing still: no destination, or already there.
func _halted() -> bool:
	return not _has_destination or _flat_distance(_destination) <= ARRIVE + 0.3


## Notices incoming fire (suppression or a wound) and tells the squad.
func _notice_fire(now: float) -> void:
	var injury := body.vitals.injury()
	if body.suppression > _last_suppression + FIRED_ON_SUPPRESSION or injury > _last_injury + FIRED_ON_INJURY:
		_fired_on_at = now
		if squad:
			squad.note_fired_on()
	_last_suppression = body.suppression
	_last_injury = injury


func _fight_from_context() -> void:
	if body.faction != &"friendly":
		if target == null and _no_los_s > ADVANCE_AFTER_S and not _buddy_bounding() and not _advancing:
			# Push one bound toward where the enemy was last seen.
			_advancing = true
			_advance_anchor = body.global_position.move_toward(body.threat_pos, ADVANCE_STEP)
			_has_cover = false
			_no_los_s = 0.0
		if target != null and target.vitals.is_up():
			_advancing = false  # a dead-check doesn't end the push through the position
		_fight(_advance_anchor if _advancing else (_cover_point if _has_cover else body.global_position), 6.0)
		if _advancing and _at_cover():
			_advancing = false
		return
	match order:
		Squad.Order.HOLD:
			_fight(_hold_point, 4.0)
		Squad.Order.MOVE:
			_fight(_move_point, 5.0)
		_:
			_fight(squad.leader.global_position if squad and is_instance_valid(squad.leader) else body.global_position, 8.0)


## Fight from cover near `anchor`, within `leash` metres of it. Buddies take turns moving.
func _fight(anchor: Vector3, leash: float) -> void:
	var cover_ok := _has_cover and _cover_point.distance_to(anchor) <= leash + 1.0 and _cover_protects(_cover_point)
	if not cover_ok and _cover_cd <= 0.0 and not _buddy_bounding() and body.suppression < PINNED and body.stunned_s <= 0.0:
		_cover_cd = COVER_SEARCH_S
		var spot: Variant = find_cover(anchor, leash)
		if spot != null:
			_cover_point = spot
			_has_cover = true
	# Hold and cover while the buddy bounds, unless this unit was already moving.
	if _has_cover and body.suppression < PINNED and body.stunned_s <= 0.0 and (_was_bounding or not _buddy_bounding()):
		_go(_cover_point, true)
	else:
		_has_destination = false
	bounding = _has_destination and not _at_cover()
	if bounding and not _was_bounding and in_contact():
		_call_bound()
	# Keep your head down unless you're shooting.
	var shooting := target != null and Soldier._now() >= _pause_until
	body.want_crouch = body.suppression >= PINNED or body.stunned_s > 0.0 or (_at_cover() and not shooting)


func _patrol() -> void:
	if guard or squad == null or squad.patrol.is_empty():
		_go(_hold_point, false)
		return
	var point := squad.patrol[_patrol_index % squad.patrol.size()]
	_go(point, false)
	if _flat_distance(point) <= ARRIVE + 0.3:
		_patrol_index += 1


func _do_reload() -> void:
	if in_contact() and _has_cover and not _at_cover():
		_go(_cover_point, true)
		return
	_has_destination = false
	body.want_crouch = in_contact()
	var weapon := body.active_weapon()
	if weapon == null or Soldier._now() < body._busy_until:
		return
	if body.inventory.rounds_in(body.active_slot) >= _mag_size(weapon):
		_think_cd = 0.0
		return
	body._busy_until = Soldier._now() + body.reload_seconds(weapon)
	body.is_reloading = true
	body._server_reload.rpc_id(1, body.active_slot)
	_think_cd = body.reload_seconds(weapon)
	_callout(&"reloading")


# --- Casualty care --------------------------------------------------------

## Whether `s` needs someone else's help: unconscious (downed, players too), or conscious
## and calling for a medic. The dead are bodies, not casualties.
static func needs_help(s: Soldier) -> bool:
	if s == null or not is_instance_valid(s) or s.is_queued_for_deletion() or s.vitals.is_dead():
		return false
	if s.vitals.downed:
		return true
	var ai := SquadAI.of(s)
	return ai != null and ai.asking_for_medic()


## This unit called "Medic!" within the last MEDIC_CALL_S and still needs care.
func asking_for_medic() -> bool:
	return Soldier._now() - _medic_called_at < MEDIC_CALL_S and body != null and body.vitals.is_up() \
		and not body.vitals.care_needed().is_empty()


## The casualty-care order applied to Vitals.care_needed() tasks (Dictionaries with "part",
## "kind" and "item"): under fire only massive bleeding (a tourniquet); once safe, massive
## bleeding, airway, chest, the other bleeding, fractures, then pain (CARE_RANK). Morphine is
## only for a conscious casualty. Tasks of the same rank keep their order.
static func plan_care(tasks: Array[Dictionary], under_fire: bool, conscious: bool) -> Array[Dictionary]:
	var ranked: Array = []
	for i in tasks.size():
		var kind := String(tasks[i].kind)
		if under_fire and kind not in UNDER_FIRE_KINDS:
			continue
		if kind == "pain" and not conscious:
			continue
		var rank := CARE_RANK.find(kind)
		if rank < 0:
			rank = CARE_RANK.size() - 1  # unknown kinds: just before pain
			ranked.append([rank * 2, i])
		else:
			ranked.append([rank * 2 + (1 if kind == "pain" else 0), i])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out: Array[Dictionary] = []
	for r: Array in ranked:
		out.append(tasks[r[1]])
	return out


## Who answers casualty `c` (design doc "Medics"): the medic of c's fire team when free and
## not far (MEDIC_FAR_M), otherwise c's battle buddy, otherwise another free medic,
## otherwise the nearest free squadmate. Only AI on c's side that is up and not already
## looking after someone else counts (carrying a body doesn't count). With `wanted` items
## (a conscious casualty's call), only units carrying one of them count. Null if nobody.
static func responder_for(c: Soldier, wanted: Array[StringName] = []) -> Soldier:
	var team_medic: SquadAI = null
	var other_medic: SquadAI = null
	var nearest: SquadAI = null
	var other_d := INF
	var near_d := INF
	for n in c.get_tree().get_nodes_in_group(&"combatants"):
		var ai := SquadAI.of(n)
		if ai == null or not ai._free_for(c) or ai.body.faction != c.faction or not ai._carries_any(wanted):
			continue
		var d := ai.body.global_position.distance_to(c.global_position)
		if ai.body.role == Roles.MEDIC:
			if c.fire_team >= 0 and ai.body.fire_team == c.fire_team and d <= MEDIC_FAR_M:
				team_medic = ai
			elif d < other_d:
				other_medic = ai
				other_d = d
		if d < near_d:
			nearest = ai
			near_d = d
	if team_medic:
		return team_medic.body
	var mate := SquadAI.of(c.buddy) if is_instance_valid(c.buddy) else null
	if mate and mate._free_for(c) and mate._carries_any(wanted):
		return mate.body
	if other_medic:
		return other_medic.body
	return nearest.body if nearest else null


## The medic who takes over casualty `c` from a carer who asked for one: a free medic on c's
## side carrying something in `wanted`, c's fire team's first unless it is far and the other
## one isn't. Null if none.
static func medic_for(c: Soldier, wanted: Array[StringName]) -> Soldier:
	var team: SquadAI = null
	var team_d := INF
	var other: SquadAI = null
	var other_d := INF
	for n in c.get_tree().get_nodes_in_group(&"combatants"):
		var ai := SquadAI.of(n)
		if ai == null or ai.body.role != Roles.MEDIC or ai.body.faction != c.faction or not ai._free_for(c) \
				or c.care_by == ai.body or wanted.is_empty() or not ai._carries_any(wanted):
			continue
		var d := ai.body.global_position.distance_to(c.global_position)
		if c.fire_team >= 0 and ai.body.fire_team == c.fire_team:
			team = ai
			team_d = d
		elif d < other_d:
			other = ai
			other_d = d
	if team and (team_d <= MEDIC_FAR_M or other == null):
		return team.body
	return other.body if other else (team.body if team else null)


## Up, set up, and not looking after anyone but `c` (a body being carried can be put down),
## and not leaving `c` to others after failing to reach them (_give_up_casualty).
func _free_for(c: Soldier) -> bool:
	return _ready_done and body != null and body != c and body.vitals.is_up() and not body.is_queued_for_deletion() \
		and (care == Care.NONE or care == Care.BODY or casualty == c) and not _skipping(c)


## This unit couldn't reach `c` lately and leaves them to others for now.
func _skipping(c: Soldier) -> bool:
	return c != null and Soldier._now() < float(_skip.get(c.get_instance_id(), -1.0))


## Carries at least one of `ids` (true for none asked).
func _carries_any(ids: Array[StringName]) -> bool:
	if ids.is_empty():
		return true
	for id in ids:
		if body.inventory.count_of(id) > 0:
			return true
	return false


## The casualty this unit should answer now, or null: one it is the responder for, or (a
## medic) one whose carer asked for a medic with something this medic carries. A medic
## prefers casualties in its own fire team.
func _find_casualty() -> Soldier:
	var best: Soldier = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s == body or s.faction != body.faction or not needs_help(s):
			continue
		var carer := _carer_of(s)
		if carer == body:
			return s
		if carer != null:
			var carer_ai := SquadAI.of(carer)
			if carer_ai == null or not carer_ai.wants_medic or medic_for(s, carer_ai.wanted) != body:
				continue  # someone is on it
		else:
			var ai := SquadAI.of(s)
			var asked: Array[StringName] = ai.wanted if ai and not s.vitals.downed else ([] as Array[StringName])
			if responder_for(s, asked) != body:
				continue
		var d := body.global_position.distance_to(s.global_position)
		if body.role == Roles.MEDIC and s.fire_team == body.fire_team:
			d *= 0.5
		if d < best_d:
			best = s
			best_d = d
	return best


## Who is really looking after `s`: a player who took hold of them, or an AI whose casualty
## they are. Null for nobody (or a stale claim).
static func _carer_of(s: Soldier) -> Soldier:
	var carer := s.care_by
	if not is_instance_valid(carer) or carer.is_queued_for_deletion() or not carer.vitals.is_up():
		return null
	var ai := SquadAI.of(carer)
	if ai == null:
		return carer if carer.carrying == s else null  # a player
	return carer if ai.casualty == s else null


## A friendly's dead body this unit should carry after the squad leader (out of contact):
## the body's battle buddy goes first, otherwise the nearest free non-medic.
func _find_body() -> Soldier:
	if body.faction != &"friendly" or squad == null or not is_instance_valid(squad.leader) or body.carrying != null:
		return null
	var best: Soldier = null
	var best_d := BODY_RECOVER_M
	for n in get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
		var s := n as Soldier
		if s == null or s.is_queued_for_deletion() or s.faction != body.faction or is_instance_valid(s.carried_by) \
				or _carer_of(s) != null:
			continue
		var d := body.global_position.distance_to(s.global_position)
		if d < best_d and _bearer_for(s) == body:
			best = s
			best_d = d
	return best


func _bearer_for(dead: Soldier) -> Soldier:
	var mate := SquadAI.of(dead.buddy) if is_instance_valid(dead.buddy) else null
	if mate and mate._can_bear(dead):
		return mate.body
	var best: Soldier = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var ai := SquadAI.of(n)
		if ai == null or ai.body == null or ai.body.faction != dead.faction or not ai._can_bear(dead):
			continue
		var d := ai.body.global_position.distance_to(dead.global_position) * (1.0 if ai.body.role != Roles.MEDIC else 3.0)
		if d < best_d:
			best = ai.body
			best_d = d
	return best


## Free to carry a body: not looking after anyone, not carrying, out of contact and not busy
## with its own wounds.
func _can_bear(dead: Soldier) -> bool:
	return care == Care.NONE and _free_for(dead) and body.carrying == null and not in_contact() \
		and _self_care_score() <= 0.0 and not asking_for_medic()


func _do_care() -> void:
	if _candidate != null and (care == Care.NONE or care == Care.BODY) and _may_take(_candidate):
		_take_casualty(_candidate)
	_candidate = null
	if care == Care.NONE:
		var dead := _find_body() if not in_contact() else null
		if dead == null:
			_think_cd = 0.0
			return
		casualty = dead
		casualty.care_by = body
		care = Care.BODY
	if care == Care.BODY:
		_carry_body()
		return
	if not is_instance_valid(casualty) or casualty.is_queued_for_deletion() or casualty.vitals.is_dead() or casualty.care_by != body:
		_end_care()  # gone, dead, or a medic took over
		_think_cd = 0.0
		return
	var contact := in_contact()
	match care:
		Care.REACH:
			_care_reach(contact)
		Care.DRAG:
			if body.carrying != casualty:
				care = Care.TREAT
			elif _has_cover and not _at_cover():
				_go(_cover_point, false)
			else:
				_has_destination = false
				body.release_carried()
				care = Care.TREAT
		Care.TREAT:
			_care_treat(contact)
		Care.GUARD:
			if not contact or not _next_task(casualty, true).is_empty():
				care = Care.TREAT
			else:
				_fight(casualty.global_position, 3.0)
		Care.CARRY:
			_care_carry(contact)


## `c` still needs help and is still free for this unit to take (nobody else got there first,
## or its carer asked for a medic and this unit is the one).
func _may_take(c: Soldier) -> bool:
	if not needs_help(c):
		return false
	var carer := _carer_of(c)
	if carer == null or carer == body:
		return true
	var carer_ai := SquadAI.of(carer)
	return carer_ai != null and carer_ai.wants_medic and medic_for(c, carer_ai.wanted) == body


## Takes `c` on (from nobody, or from a carer who asked for a medic).
func _take_casualty(c: Soldier) -> void:
	if care != Care.NONE:
		_end_care()
	casualty = c
	c.care_by = body
	_start_reach()
	_smoke_used = false
	_has_cover = false
	_controlled_at = -1.0
	_asked_medic = false
	_answered = false
	wants_medic = false
	wanted.clear()
	_failures.clear()
	var callouts := Callouts.of(body)
	if callouts:
		callouts.answer_casualty(body, c, false)


## Sets off toward the casualty (Care.REACH), watching for progress from here.
func _start_reach() -> void:
	care = Care.REACH
	_reach_best = INF
	_reach_progress_at = Soldier._now()
	_detour_until = -1.0
	_detour_next = -1.0


func _care_reach(contact: bool) -> void:
	var d := _flat_distance(casualty.global_position)
	if body.carrying == casualty:
		care = Care.CARRY
		return
	if not _reach_progress(d):
		return  # gave up: the next responder takes them
	_go(_detour if Soldier._now() < _detour_until else casualty.global_position, true)
	if contact and not _smoke_used and d <= SMOKE_RANGE_M and casualty.vitals.downed and not _sheltered(casualty):
		_smoke_used = true
		if body.inventory.count_of(&"smoke_grenade") > 0:
			var screen := casualty.global_position + (body.threat_pos - casualty.global_position).normalized() * 4.0
			_throw(&"smoke_grenade", screen)
	if d > CASUALTY_REACH:
		return
	_has_destination = false
	if contact and casualty.vitals.downed and not _sheltered(casualty) and not is_instance_valid(casualty.carried_by):
		var spot: Variant = find_cover(body.global_position, 10.0)
		if spot != null and body.server_pick_up_body(casualty, Soldier.DRAG):
			_cover_point = spot
			_has_cover = true
			care = Care.DRAG
			return
	care = Care.TREAT


## Watches the approach to the casualty `d` metres away. No closer for REACH_STUCK_S
## (something the navmesh doesn't know about is in the way, such as a player) means a
## sidestep, alternating sides, with a try at the direct way in between; no closer for
## REACH_GIVE_UP_S means handing the casualty on. False once this unit gave up.
func _reach_progress(d: float) -> bool:
	var now := Soldier._now()
	if d < _reach_best - REACH_PROGRESS_M or d <= CASUALTY_REACH:
		_reach_best = d
		_reach_progress_at = now
		return true
	if now - _reach_progress_at >= REACH_GIVE_UP_S:
		_give_up_casualty()
		return false
	if now - _reach_progress_at >= REACH_STUCK_S and now >= _detour_next:
		_detour_side = -_detour_side
		_detour_until = now + DETOUR_S
		_detour_next = now + DETOUR_S * 2.5
		var to := casualty.global_position - body.global_position
		to.y = 0.0
		var side := Vector3(-to.z, 0.0, to.x).normalized() * _detour_side
		var map := body.get_world_3d().navigation_map
		_detour = NavigationServer3D.map_get_closest_point(map, body.global_position + side * DETOUR_M + to.normalized() * 0.3)
	return true


## Couldn't get to the casualty: lets go of them so the next responder (responder_for)
## takes them, and leaves them to others for REACH_SKIP_S.
func _give_up_casualty() -> void:
	var now := Soldier._now()
	for id: int in _skip.keys():
		if float(_skip[id]) <= now:
			_skip.erase(id)
	if is_instance_valid(casualty):
		_skip[casualty.get_instance_id()] = now + REACH_SKIP_S
	_end_care()
	_has_destination = false
	_think_cd = 0.0


func _care_treat(contact: bool) -> void:
	if body.carrying == casualty:
		body.release_carried()
	if _flat_distance(casualty.global_position) > CASUALTY_REACH + 1.0:
		_start_reach()  # a conscious casualty moved, or the body slid
		return
	_has_destination = false
	body.want_crouch = true
	_face(casualty.global_position)
	var now := Soldier._now()
	if _treat_until >= 0.0 or now < body._busy_until:
		return  # an item (or the revive) is going on
	var task := _next_task(casualty, contact)
	if not task.is_empty():
		_start_treatment(casualty, task)
		return
	# Nothing more this unit can do for them now.
	if not casualty.vitals.downed:
		if contact and not _next_task(casualty, false).is_empty():
			care = Care.GUARD  # the rest once it's quiet
		else:
			_end_care()  # conscious and patched up as far as this unit can
		return
	if contact:
		care = Care.GUARD
		return
	if _bleeding_controlled(casualty):
		if _controlled_at < 0.0:
			_controlled_at = now
	else:
		_controlled_at = -1.0
	if _can_revive() and _controlled_at >= 0.0:
		# The stopgap revive (until IV): only once the bleeding is controlled and they
		# still haven't woken. Bleeding this unit can't stop waits for someone who can.
		if now - _controlled_at >= REVIVE_WAIT_S:
			_start_revive()
		return
	_want_medic()
	if _controlled_at >= 0.0 and now - _controlled_at < REVIVE_WAIT_S:
		return  # give them a moment to come round before moving them
	care = Care.CARRY


func _care_carry(contact: bool) -> void:
	if contact:
		if body.carrying == casualty:
			body._set_carry_mode(Soldier.DRAG)
			var spot: Variant = find_cover(body.global_position, 10.0)
			_has_cover = spot != null
			if spot != null:
				_cover_point = spot
			care = Care.DRAG
		else:
			care = Care.GUARD
		return
	if not casualty.vitals.downed or not _next_task(casualty, false).is_empty() \
			or (_can_revive() and _bleeding_controlled(casualty)):
		care = Care.TREAT  # woke up, or there's something new to do (an item handed over)
		return
	var leader: Soldier = squad.leader if squad and is_instance_valid(squad.leader) else null
	if leader == null or casualty == leader or body.faction != &"friendly":
		# No one to follow (or the lead is down): keep them safe where they are.
		if body.carrying == casualty:
			body.release_carried()
		_has_destination = false
		body.want_crouch = true
		return
	if body.carrying != casualty:
		if _flat_distance(casualty.global_position) <= CASUALTY_REACH and body.server_pick_up_body(casualty, Soldier.CARRY):
			_callouts_carrying(false)
		else:
			_go(casualty.global_position, true)
		return
	_go(squad.follow_point(body))


## Out of contact: picks up a fallen friendly's body and carries it after the squad leader.
func _carry_body() -> void:
	if in_contact() or not is_instance_valid(casualty) or casualty.is_queued_for_deletion() \
			or (is_instance_valid(casualty.carried_by) and casualty.carried_by != body) or squad == null or not is_instance_valid(squad.leader):
		_end_care()
		return
	if body.carrying != casualty:
		if _flat_distance(casualty.global_position) <= CASUALTY_REACH and body.server_pick_up_body(casualty, Soldier.CARRY):
			_callouts_carrying(true)
		else:
			_go(casualty.global_position, true)
		return
	_go(squad.follow_point(body))


func _callouts_carrying(dead: bool) -> void:
	var callouts := Callouts.of(body)
	if callouts:
		callouts.carrying(body, casualty, dead)


func _end_care() -> void:
	if is_instance_valid(casualty):
		if body.carrying == casualty:
			body.release_carried()
		if casualty.care_by == body:
			casualty.care_by = null
		var their := SquadAI.of(casualty)
		if their and casualty.vitals.is_up():
			their._medic_called_at = -1000.0  # answered; they call again if they still need it
	elif body.carrying != null and not is_instance_valid(body.carrying):
		body.release_carried()
	casualty = null
	care = Care.NONE
	_has_cover = false
	wants_medic = false
	wanted.clear()
	_reviving = false


## The next treatment this unit can give `c` now, in the care order (under fire: massive
## bleeding only), with an item it carries and that hasn't failed TREAT_TRIES times, and not
## one the casualty is doing on themselves right now; {} for none.
func _next_task(c: Soldier, under_fire: bool) -> Dictionary:
	var conscious := c.vitals.is_up()
	var their := SquadAI.of(c) if c != body else null
	for task in plan_care(c.vitals.care_needed(), under_fire, conscious):
		if their and their._treat_until >= 0.0 and their._treat_key == _task_key(c, task):
			continue
		if String(task.kind) == "pain" and c.vitals.pain() < MORPHINE_PAIN:
			continue
		if body.inventory.count_of(StringName(task.item)) <= 0:
			continue
		if int(_failures.get(_task_key(c, task), 0)) >= TREAT_TRIES:
			continue
		return task
	return {}


## Items this unit lacks for what `c` still needs once safe.
func _missing_items(c: Soldier) -> Array[StringName]:
	var out: Array[StringName] = []
	for task in plan_care(c.vitals.care_needed(), false, c.vitals.is_up()):
		var item := StringName(task.item)
		if body.inventory.count_of(item) <= 0 and item not in out:
			out.append(item)
	return out


## Nothing more this unit can do for its unconscious casualty: asks for a medic who has
## what's missing (or the trauma kit for the stopgap revive).
func _want_medic() -> void:
	wanted = _missing_items(casualty)
	if not _can_revive() and MEDIC_REVIVE_KIT not in wanted:
		wanted.append(MEDIC_REVIVE_KIT)
	wants_medic = not wanted.is_empty()  # a medic who lacks nothing has nobody to call
	if wants_medic and not _asked_medic:
		_asked_medic = true
		var callouts := Callouts.of(body)
		if callouts:
			callouts.need_medic(body, casualty)


## No bleeding left in what care_needed() lists.
static func _bleeding_controlled(c: Soldier) -> bool:
	for task in c.vitals.care_needed():
		if String(task.kind) in BLEED_KINDS:
			return false
	return true


## The stopgap revive is the medic's, with a trauma kit.
func _can_revive() -> bool:
	return body.role == Roles.MEDIC and body.inventory.count_of(MEDIC_REVIVE_KIT) > 0


static func _task_key(c: Soldier, task: Dictionary) -> String:
	return "%s|%s|%s" % [c.name, task.part, task.kind]


static func _count_tasks(c: Soldier, key: String) -> int:
	var n := 0
	for task in c.vitals.care_needed():
		if _task_key(c, task) == key:
			n += 1
	return n


## Treats `target` (a casualty or this body) with one item through Soldier._server_treat,
## the host request players use too.
func _start_treatment(target: Soldier, task: Dictionary) -> void:
	var item := ItemDB.get_item(StringName(task.item))
	var seconds := float(item.stats.get("treat_s", 4.0)) if item else 4.0
	if target == body and item:
		seconds *= float(item.stats.get("self_mult", 1.0))
	_treat_target = target
	_treat_key = _task_key(target, task)
	_treat_before = _count_tasks(target, _treat_key)
	_treat_until = Soldier._now() + seconds + TREAT_MARGIN_S
	_reviving = false
	body._server_treat.rpc_id(1, target.get_path(), StringName(task.item), StringName(task.part))
	if target != body and not _answered:
		_answered = true
		var callouts := Callouts.of(body)
		if callouts:
			callouts.answer_casualty(body, target, true)


func _start_revive() -> void:
	var kit := body._best_revive_kit()
	_treat_target = casualty
	_treat_key = ""
	_treat_until = Soldier._now() + (float(kit.stats.revive_s) if kit else 3.0) + TREAT_MARGIN_S
	_reviving = true
	body._server_revive.rpc_id(1, casualty.get_path())


## A treatment's time is up: if the task is still there as often as before, it failed.
func _finish_treatment() -> void:
	if _treat_key != "" and is_instance_valid(_treat_target) and _count_tasks(_treat_target, _treat_key) >= _treat_before:
		_failures[_treat_key] = int(_failures.get(_treat_key, 0)) + 1
	_treat_until = -1.0
	_treat_key = ""
	_reviving = false
	_think_cd = 0.0


## Under cover from the last known threat, lying down.
func _sheltered(c: Soldier) -> bool:
	return not Throwables.clear_line(body.get_world_3d(), body.threat_pos + Vector3.UP * 1.5, c.global_position + Vector3.UP * 0.4)


func _face(point: Vector3) -> void:
	var d := point - body.global_position
	if Vector2(d.x, d.z).length() > 0.2:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-d.x, -d.z), 0.2)


# --- Self-care ------------------------------------------------------------

## How much this unit wants to look after itself (0 for not at all): its own arterial bleed
## at once (even under fire), the rest out of contact or in cover; staying still while a
## squadmate treats it; or the stopgap kit (IFAK) when it has no item for the job.
func _self_care_score() -> float:
	if _treat_until >= 0.0 and _treat_target == body:
		return 0.98  # finish what you started
	if _being_treated():
		return 0.92
	var task := _self_task()
	if not task.is_empty():
		if String(task.kind) in UNDER_FIRE_KINDS:
			return 0.97
		return 0.75 if in_contact() else 0.62
	if _has_heal() and not body.vitals.is_healing() and body.vitals.needs_treatment():
		if _massive_bleeding(body):
			return 0.96
		if body.vitals.injury() > 0.45 and (not in_contact() or _at_cover()):
			return 0.6 + 0.3 * body.vitals.injury()
	return 0.0


## What this unit can do for itself right now (see _self_care_score), or {}.
func _self_task() -> Dictionary:
	if not body.vitals.is_up():
		return {}
	return _next_task(body, in_contact() and not _at_cover())


func _do_self_care() -> void:
	_has_destination = false
	body.want_crouch = true
	if _being_treated() or _treat_until >= 0.0 or Soldier._now() < body._busy_until:
		return
	var task := _self_task()
	if not task.is_empty():
		_start_treatment(body, task)
		return
	if _has_heal() and not body.vitals.is_healing() and body.vitals.needs_treatment():
		body._server_use_medical.rpc_id(1)  # stopgap kit
	_think_cd = 0.0


## A squadmate is with this conscious unit to treat it: hold still.
func _being_treated() -> bool:
	var carer := body.care_by
	if not is_instance_valid(carer) or not carer.vitals.is_up():
		return false
	var ai := SquadAI.of(carer)
	return ai != null and ai.casualty == body and ai.care in [Care.REACH, Care.TREAT] \
		and _flat_distance(carer.global_position) <= BEING_TREATED_M


static func _massive_bleeding(c: Soldier) -> bool:
	for task in c.vitals.care_needed():
		if String(task.kind) in UNDER_FIRE_KINDS:
			return true
	return false


## A conscious wounded unit that needs what it doesn't carry calls "Medic!" (at most every
## MEDIC_CALL_S) and lists what it needs in `wanted`.
func _maybe_call_medic() -> void:
	if care != Care.NONE and care != Care.BODY:
		return
	var now := Soldier._now()
	if now - _medic_called_at < MEDIC_CALL_S or _being_treated() or not body.vitals.is_up():
		return
	var missing := _missing_items(body)
	if missing.is_empty():
		return
	if _has_heal() and missing.all(func(id: StringName) -> bool: return id in [&"pressure_bandage", &"hemostatic_gauze", &"chest_seal", &"tourniquet"]):
		return  # the stopgap kit stops bleeding; no need to call anyone
	if responder_for(body, missing) == null:
		return  # nobody free carries any of it: no use shouting yet
	wanted = missing
	_medic_called_at = now
	var callouts := Callouts.of(body)
	if callouts:
		callouts.medic_call(body)


## Carries a stopgap kit (an item with "heal") for _server_use_medical. A medic's trauma kit
## doesn't count: it is kept for the stopgap revive.
func _has_heal() -> bool:
	for container in Inventory.CONTAINERS:
		for entry: Dictionary in body.inventory.containers[container]:
			if body.role == Roles.MEDIC and entry.id == MEDIC_REVIVE_KIT:
				continue
			if ItemDB.get_item(entry.id).stats.has("heal"):
				return true
	return false


# --- Perception -----------------------------------------------------------

func _find_target() -> Soldier:
	if body.stunned_s > 0.0:
		return null
	if focus != null and (not is_instance_valid(focus) or focus.is_queued_for_deletion() or not focus.vitals.is_up()):
		focus = null  # the target is down: pick freely again
	if focus != null and focus.faction != body.faction and body.global_position.distance_to(focus.global_position) <= Squad.TARGET_RANGE \
			and can_see(focus):
		return focus
	var best: Soldier = null
	var best_dist := SIGHT_RANGE
	var check: Soldier = null
	var check_dist := DEAD_CHECK_M
	var clearing := _clearing()
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s.faction == body.faction or s.vitals.is_dead() or s.is_queued_for_deletion():
			continue
		var d := body.global_position.distance_to(s.global_position)
		if not s.vitals.is_up():
			# Unconscious foes are left alone, except for a dead-check while clearing.
			if clearing and d < check_dist and can_see(s):
				check = s
				check_dist = d
			continue
		if d < best_dist and can_see(s):
			best = s
			best_dist = d
	# A dead-check, once started, goes on until the body is dead, out of range or out of
	# sight, even after the advance ends; only new ones need clearing.
	if check != null:
		_dead_check = check
	elif _dead_check != null and not _dead_check_valid(_dead_check):
		_dead_check = null
	return best if best != null else _dead_check


## Still worth dead-checking: unconscious (not dead), within DEAD_CHECK_M and in sight.
func _dead_check_valid(s: Soldier) -> bool:
	return is_instance_valid(s) and not s.is_queued_for_deletion() and not s.vitals.is_dead() and not s.vitals.is_up() \
		and body.global_position.distance_to(s.global_position) <= DEAD_CHECK_M and can_see(s)


## Clearing or assaulting through a position (pushing toward the enemy, searching, or moving
## on an order while in contact): when unconscious foes nearby get dead-checked.
func _clearing() -> bool:
	return _advancing or intent == Intent.INVESTIGATE or (intent == Intent.MOVE_TO and in_contact())


func can_see(other: Soldier) -> bool:
	var from := body.camera.global_position
	var to := other.aim_point()  # follows stance: crouched and prone targets sit lower
	if SmokeCloud.blocks(from, to):
		return false
	return Throwables.clear_line(body.get_world_3d(), from, to)


# --- Cover ----------------------------------------------------------------

## Best spot on the navmesh near `anchor` that the threat can't hit, preferring spots you
## can shoot back from.
func find_cover(anchor: Vector3, leash: float) -> Variant:
	var map := body.get_world_3d().navigation_map
	var world := body.get_world_3d()
	var best: Variant = null
	var best_score := INF
	for ring in COVER_RINGS:
		if ring > leash + 0.1:
			break
		for k in 12:
			var angle := TAU * k / 12.0 + ring
			var p := anchor + Vector3(cos(angle), 0.0, sin(angle)) * ring
			var q := NavigationServer3D.map_get_closest_point(map, p)
			if Vector2(q.x - p.x, q.z - p.z).length() > 0.6 or not _cover_protects(q) or _cover_taken(q):
				continue
			var score := _flat_distance(q) + q.distance_to(anchor) * 0.5
			if Throwables.clear_line(world, q + Vector3.UP * 1.6, body.threat_pos + Vector3.UP * 1.2):
				score -= 3.0  # low cover: you can stand up and return fire
			score += maxf(0.0, 6.0 - q.distance_to(body.threat_pos)) * 2.0
			if score < best_score:
				best = q
				best_score = score
	return best


func _cover_protects(point: Vector3) -> bool:
	return not Throwables.clear_line(body.get_world_3d(), body.threat_pos + Vector3.UP * 1.5, point + Vector3.UP * 0.9)


func _cover_taken(point: Vector3) -> bool:
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var other := SquadAI.of(n)
		if other and other != self and other._has_cover and other._cover_point.distance_to(point) < 1.2:
			return true
	return false


func _at_cover() -> bool:
	return _has_cover and _flat_distance(_cover_point) <= ARRIVE + 0.4


func _buddy_bounding() -> bool:
	var ai := SquadAI.of(buddy) if is_instance_valid(buddy) and buddy.vitals.is_up() else null
	return ai != null and ai.bounding


# --- Shooting -------------------------------------------------------------

func _shoot() -> void:
	var now := Soldier._now()
	var weapon := body.active_weapon()
	if weapon == null or weapon.type != "weapon" or body.carrying != null or body.is_reloading \
			or body.stunned_s > 0.0 or body.suppression >= PINNED or care == Care.TREAT or not weapons_free():
		return
	var aim_at: Variant = null
	if target != null:
		aim_at = target.aim_point()
	elif _buddy_bounding() and in_contact() and now - _last_contact < 5.0:
		aim_at = body.threat_pos + Vector3.UP * 1.0  # covering fire while the buddy moves
	elif intent == Intent.FIGHT:
		_maybe_frag()
	if aim_at == null:
		return
	var error := _aim_at(aim_at)
	if body.want_crouch and _at_cover() and target != null:
		body.want_crouch = false  # stand up to shoot over cover
		return
	if error > deg_to_rad(6.0) or now < _next_shot or now < _pause_until or now < body._busy_until:
		return
	if body.inventory.rounds_in(body.active_slot) <= 0 or _friendly_in_line(aim_at):
		return
	var auto: bool = weapon.stats.get("auto", false)
	_next_shot = now + 60.0 / float(weapon.stats.get("rpm", 600)) * (1.0 if auto else 1.6)
	if _burst_left <= 0:
		_burst_left = randi_range(3, 5) if auto else randi_range(2, 3)
	_burst_left -= 1
	if _burst_left <= 0:
		_pause_until = now + randf_range(0.5, 1.1) / lerpf(0.7, 1.3, combat)
	var dir := body._spread_direction(weapon)
	var extra := deg_to_rad((1.0 - combat) * 2.0 + body.suppression * 4.0 + (0.0 if target else 3.0))
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * tan(extra) * 0.6).normalized()
	body._server_fire.rpc_id(1, body.camera.global_position, dir, body.active_slot)


## Turns the body and head toward a point; returns the remaining angle in radians.
func _aim_at(point: Vector3) -> float:
	var from := body.camera.global_position
	var d := point - from
	var flat := Vector2(d.x, d.z)
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, flat.length())
	var step := 1.0 - exp(-TURN_RATE * lerpf(0.6, 1.4, combat) * get_physics_process_delta_time())
	body.rotation.y = lerp_angle(body.rotation.y, yaw, step)
	body.head.rotation.x = lerpf(body.head.rotation.x, clampf(pitch, -1.4, 1.4), step)
	return (-body.camera.global_basis.z).angle_to(d.normalized())


## Fire discipline: true if someone on this unit's side (standing or down) is in the line
## of fire to `point`, closer than it.
func _friendly_in_line(point: Vector3) -> bool:
	var from := body.camera.global_position
	var reach := from.distance_to(point)
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s == body or s.faction != body.faction or s.is_queued_for_deletion():
			continue
		var chest := s.global_position + Vector3.UP * (1.1 if s.vitals.is_up() else 0.3)
		if from.distance_to(chest) < reach and Geometry3D.get_closest_point_to_segment(chest, from, point).distance_to(chest) < FRIENDLY_CLEARANCE:
			return true
	return false


func _maybe_frag() -> void:
	if _grenade_cd > 0.0 or _no_los_s < 4.0 or not in_contact():
		return
	var d := body.global_position.distance_to(body.threat_pos)
	if d < 8.0 or d > 25.0:
		return
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s != body and s.faction == body.faction and s.global_position.distance_to(body.threat_pos) < Throwables.FRAG_RADIUS + 1.0:
			return  # friendlies too close to the blast
	if not _lob_clear(body.camera.global_position + Vector3.UP * 0.2, body.threat_pos):
		return  # it would hit a wall or roof on the way and bounce back
	_grenade_cd = GRENADE_COOLDOWN_S
	_throw(&"frag_grenade", body.threat_pos)


## Whether a grenade lobbed from `from` (Throwables.lob_velocity) flies to `at` without
## hitting anything on the way: a frag that clips a wall or a roof lands among your own.
func _lob_clear(from: Vector3, at: Vector3) -> bool:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var velocity := Throwables.lob_velocity(from, at)
	var flight := clampf(from.distance_to(at) / 12.0, 0.6, 1.6)  # as lob_velocity times it
	var world := body.get_world_3d()
	var previous := from
	for i in range(1, LOB_CHECKS + 1):
		var t := flight * 0.9 * i / LOB_CHECKS  # the last tenth comes down onto the target
		var point := from + velocity * t + Vector3.DOWN * 0.5 * gravity * t * t
		if not Throwables.clear_line(world, previous, point):
			return false
		previous = point
	return true


func _throw(id: StringName, at: Vector3) -> bool:
	if Soldier._now() < body._busy_until or not body.inventory.remove_one(id):
		return false
	body._busy_until = Soldier._now() + Soldier.THROW_BUSY_S
	var from := body.camera.global_position + Vector3.UP * 0.2
	CompoundLevel.current(body).server_throw(id, from, Throwables.lob_velocity(from, at))
	if Callouts.THROW_IDS.has(id):
		_callout(Callouts.THROW_IDS[id])
	return true


# --- Callouts -------------------------------------------------------------

func _callout(id: StringName, text := "") -> void:
	var callouts := Callouts.of(body)
	if callouts:
		callouts.say(body, id, text)


## Bounding in contact: "Moving!", and the battle buddy answers "Covering!".
func _call_bound() -> void:
	_callout(&"moving")
	var mate := buddy
	var mate_ai := SquadAI.of(mate) if is_instance_valid(mate) and mate.vitals.is_up() else null
	if mate_ai and not mate_ai.bounding:
		mate_ai._callout(&"covering")


# --- Steering -------------------------------------------------------------

func _go(point: Vector3, run := false) -> void:
	_destination = point
	_has_destination = true
	_run = run or _flat_distance(point) > RUN_DISTANCE


## Follows a navmesh path to the destination, judging waypoints by flat distance (the
## baked mesh sits a little above the ground, so 3D distances never quite close).
func _steer(delta: float) -> void:
	var dir := Vector3.ZERO
	_repath_cd -= delta
	if _has_destination and _flat_distance(_destination) > ARRIVE and body.stunned_s <= 0.0:
		if _repath_cd <= 0.0 or _path_target.distance_to(_destination) > 0.5:
			_repath_cd = REPATH_S
			_path_target = _destination
			_path = NavigationServer3D.map_get_path(body.get_world_3d().navigation_map, body.global_position, _destination, true)
			_path_index = 0
		while _path_index < _path.size() and _flat_distance(_path[_path_index]) < WAYPOINT_REACH:
			_path_index += 1
		var next := _path[_path_index] if _path_index < _path.size() else _destination
		dir = next - body.global_position
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.05 else Vector3.ZERO
	var local := body.global_basis.inverse() * dir
	body.move_input = Vector2(local.x, local.z)
	body.want_sprint = _run and not body.want_crouch and target == null and _may_sprint()
	if target == null and dir != Vector3.ZERO and body.carrying == null:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-TURN_RATE * get_physics_process_delta_time()))
		body.head.rotation.x = lerpf(body.head.rotation.x, 0.0, 0.1)
	elif target == null and dir == Vector3.ZERO and in_contact():
		_aim_at(body.threat_pos + Vector3.UP * 1.2)


## Safe units only run to catch up from far behind; Stealth units never sprint.
func _may_sprint() -> bool:
	match combat_mode:
		Squad.CombatMode.SAFE:
			return fighting() or _flat_distance(_destination) > SAFE_CATCH_UP_M
		Squad.CombatMode.STEALTH:
			return false
	return true


func _stop() -> void:
	_has_destination = false
	body.move_input = Vector2.ZERO
	body.want_sprint = false
	body.want_aim = false


# --- Helpers --------------------------------------------------------------

func _flat_distance(point: Vector3) -> float:
	return Vector2(body.global_position.x - point.x, body.global_position.z - point.z).length()



static func _mag_size(weapon: ItemData) -> int:
	if weapon == null:
		return 0
	var ammo := Soldier._ammo_of(weapon)
	return ItemDB.get_item(ammo).magazine_rounds() if ItemDB.has_item(ammo) else 0


func _name_of(s: Soldier) -> String:
	if s == null or not is_instance_valid(s):
		return "them"
	return "the lead" if squad and s == squad.leader else String(s.name)
