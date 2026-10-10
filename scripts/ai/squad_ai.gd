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
## Friendlies also look after downed friendlies, the player included, buddy first:
## - In a fight: pop smoke between the casualty and the threat, drag them into cover, then
##   revive them with a kit, or guard them if there's no kit.
## - Out of a fight: revive them, or pick them up, carry them and follow the squad leader.

enum Intent { FOLLOW, HOLD, MOVE_TO, PATROL, INVESTIGATE, FIGHT, CASUALTY, RELOAD, HEAL }
enum Care { NONE, REACH, DRAG, TREAT, GUARD, CARRY }

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
const CASUALTY_REACH := 1.6
const REVIVE_KITS: Array[StringName] = [&"trauma_kit", &"ifak"]
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
var casualty: Soldier
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
var _treat_started := -1.0
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
		if target != null and target != previous:
			_next_shot = maxf(_next_shot, now + lerpf(0.9, 0.25, combat))  # reaction time
			var callouts := Callouts.of(body)
			if callouts:
				callouts.contact(body, target)
	if target != null:
		_last_contact = now
		body.threat_pos = target.global_position
		body.threat_time = now
		_no_los_s = 0.0
	else:
		_no_los_s += delta
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
					return "Reviving %s" % who
				Care.GUARD:
					return "Guarding %s" % who
				Care.CARRY:
					return "Carrying %s" % who
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
			return "Patching up"
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
		if care != Care.NONE or _find_casualty() != null:
			scores[Intent.CASUALTY] = 0.9
	else:
		scores[Intent.PATROL] = 0.3
		if Soldier._now() - _last_contact < INVESTIGATE_MEMORY_S:
			scores[Intent.INVESTIGATE] = 0.55
	if fighting():
		scores[Intent.FIGHT] = 0.7
	if weapon and rounds == 0 and spare > 0:
		scores[Intent.RELOAD] = 0.95
	elif weapon and rounds < full * 0.35 and spare > 0 and target == null:
		scores[Intent.RELOAD] = 0.65
	if body.vitals.injury() > 0.45 and _has_heal() and not body.vitals.is_healing() and (not contact or _at_cover()):
		scores[Intent.HEAL] = 0.6 + 0.3 * body.vitals.injury()

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
		if intent == Intent.CASUALTY and care != Care.NONE and best_score < 0.95:
			return  # don't abandon a casualty for anything short of an empty magazine
		intent = best
		_score = best_score


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
			_has_destination = false
			body.want_crouch = true
			if Soldier._now() >= body._busy_until:
				body._server_use_medical.rpc_id(1)
				_think_cd = 0.0
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
		if target != null:
			_advancing = false
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

func _find_casualty() -> Soldier:
	if body.faction != &"friendly" or care != Care.NONE:
		return casualty
	var best: Soldier = null
	var best_dist := INF
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s == body or s.faction != body.faction or not s.vitals.downed:
			continue
		if is_instance_valid(s.care_by) and s.care_by != body and s.care_by.vitals.is_up():
			continue
		var d := body.global_position.distance_to(s.global_position)
		if s == buddy:
			d *= 0.25  # your battle buddy comes first
		if d < best_dist:
			best = s
			best_dist = d
	if best == null:
		return null
	# Their own battle buddy goes for them if it can.
	if best != buddy:
		var their_ai := SquadAI.of(best.buddy) if is_instance_valid(best.buddy) else null
		if their_ai and their_ai != self and best.buddy.vitals.is_up() and their_ai.care == Care.NONE:
			return null
	# Otherwise leave it to a closer squadmate who's free.
	if best != buddy:
		for n in get_tree().get_nodes_in_group(&"combatants"):
			var other := SquadAI.of(n)
			if other and other != self and other.body and other.body.faction == body.faction and other.body.vitals.is_up() \
					and other.care == Care.NONE and other.buddy != best \
					and other.body.global_position.distance_to(best.global_position) < best_dist * 0.7:
				return null
	return best


func _do_care() -> void:
	if care == Care.NONE:
		casualty = _find_casualty()
		if casualty == null:
			_think_cd = 0.0
			return
		casualty.care_by = body
		care = Care.REACH
		_smoke_used = false
		_treat_started = -1.0
	if not is_instance_valid(casualty) or not casualty.vitals.downed:
		_end_care()
		_think_cd = 0.0
		return
	var contact := in_contact()
	match care:
		Care.REACH:
			_go(casualty.global_position, true)
			if contact and not _smoke_used:
				_smoke_used = true
				var screen := casualty.global_position + (body.threat_pos - casualty.global_position).normalized() * 4.0
				_throw(&"smoke_grenade", screen)
			if _flat_distance(casualty.global_position) <= CASUALTY_REACH:
				if contact:
					if body.server_pick_up_body(casualty):
						_has_cover = false
						var spot: Variant = find_cover(body.global_position, 10.0)
						if spot != null:
							_cover_point = spot
							_has_cover = true
						care = Care.DRAG
				elif _revive_kit() != &"":
					care = Care.TREAT
				elif body.server_pick_up_body(casualty):
					care = Care.CARRY
		Care.DRAG:
			if _has_cover and not _at_cover():
				_go(_cover_point, false)
			else:
				_has_destination = false
				if _revive_kit() != &"":
					care = Care.TREAT
				else:
					body.release_carried()
					care = Care.GUARD
		Care.TREAT:
			_has_destination = false
			body.want_crouch = true
			if _treat_started < 0.0 and Soldier._now() >= body._busy_until:
				_treat_started = Soldier._now()
				body._server_revive.rpc_id(1, casualty.get_path())
			elif _treat_started >= 0.0 and Soldier._now() - _treat_started > 6.0:
				_treat_started = -1.0  # interrupted; try again
		Care.GUARD:
			if contact:
				_fight(casualty.global_position, 3.0)
			elif body.server_pick_up_body(casualty) or casualty.carried_by == body:
				care = Care.CARRY
			else:
				_go(casualty.global_position, true)
		Care.CARRY:
			if contact:
				var spot: Variant = find_cover(body.global_position, 10.0)
				if spot != null:
					_cover_point = spot
					_has_cover = true
				care = Care.DRAG
			elif _revive_kit() != &"":
				care = Care.TREAT  # found a kit (or was handed one): patch them up now
			elif squad and casualty == squad.leader:
				_has_destination = false  # keep the leader safe where they fell
			else:
				_go(squad.follow_point(body) if squad else body.global_position)


func _end_care() -> void:
	if body.carrying == casualty:
		body.release_carried()
	if is_instance_valid(casualty) and casualty.care_by == body:
		casualty.care_by = null
	casualty = null
	care = Care.NONE
	_has_cover = false


func _revive_kit() -> StringName:
	for id in REVIVE_KITS:
		if body.inventory.count_of(id) > 0:
			return id
	return &""


func _has_heal() -> bool:
	for container in Inventory.CONTAINERS:
		for entry: Dictionary in body.inventory.containers[container]:
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
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s.faction == body.faction or not s.vitals.is_up():
			continue
		var d := body.global_position.distance_to(s.global_position)
		if d < best_dist and can_see(s):
			best = s
			best_dist = d
	return best


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
	_grenade_cd = GRENADE_COOLDOWN_S
	_throw(&"frag_grenade", body.threat_pos)


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
