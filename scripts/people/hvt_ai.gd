class_name HvtAI
extends CivilianAI
## Host-only brain for an HVT (wave 4, W11; design doc "Missions": friendly HVTs cooperate,
## hostile HVTs try to expose the squad, run and resist until zip-cuffed).
##
## A friendly HVT behaves like a civilian (hides from gunfire) until told what to do from the
## interaction menu: Follow me, Stop, Get in cover (CivilianAI's orders).
##
## A hostile HVT, until he gives up or is cuffed:
## - Spots the players' side by sight (SPOT_M, within his view cone) or hears gunfire.
## - Exposes the squad: shouts (a subtitle for players near him), and every hostile within
##   EXPOSE_M learns where the squad is (their Soldier.threat_pos and threat_time, so their
##   SquadAI goes into contact), again every SHOUT_GAP_S while he still sees them.
## - Runs to the nearest hostile soldier still up and stays close behind him, away from the
##   threat; with nobody left, runs and hides like a civilian.
## - Resists: he can only be cuffed from behind (Person.cuff_problem), and steps away from
##   anyone who gets close in front of him.
## - Gives up when cornered (someone from the squad within CORNERED_M for CORNERED_S with no
##   hostile up within ISOLATED_M) or badly hurt and alone: he surrenders
##   (PeopleLayer.server_surrender) and can be cuffed from any side.
## Once cuffed he comes along when led, and can be carried.
##
## Zip cuffs are a base-shop buy, but a capture can be done without them (Captain,
## 2026-10-11): a hostile HVT who gave up (or was downed and carried) comes along when led and
## counts when brought in, uncuffed. An uncuffed one needs babysitting: nobody from the squad
## up and not pinned within WATCH_M (watched) for BOLT_GRACE_S, and every BOLT_CHECK_S he
## may take his surrender back and bolt, the odds climbing to BOLT_MAX over BOLT_RAMP_S
## alone. Even watched, a fight around him (gunfire heard) gives him a small chance
## (BOLT_CHAOS). The more it hurts the less he tries (bolt_will); badly hurt, he stays put.
## Then he has to be cornered again. A cuffed HVT never bolts.

## Proposed: how far, and how wide (half-angle), a hostile HVT spots the squad.
const SPOT_M := 30.0
const VIEW_HALF_DEG := 70.0
## Hostiles within this far hear him shout.
const EXPOSE_M := 45.0
const SHOUT_GAP_S := 8.0
## Proposed: once alarmed he keeps running and shouting this long after the last sighting.
const ALARM_S := 45.0
## He stays this close to the hostile he runs to, on the side away from the threat.
const JOIN_M := 2.5
## Too close in front: he steps away.
const RESIST_M := 2.5
## Cornered: someone from the squad this close for this long, with no hostile up within ISOLATED_M.
const CORNERED_M := 4.0
const CORNERED_S := 3.0
const ISOLATED_M := 20.0
const SHOUTS: Array[String] = ["They're here! Over here!", "Contractors! Here!", "Help! They're coming!"]
## Proposed: babysitting an uncuffed captive HVT (see above).
const WATCH_M := 6.0
const BOLT_CHECK_S := 2.0
const BOLT_GRACE_S := 4.0
const BOLT_RAMP_S := 12.0
const BOLT_MAX := 0.6
const BOLT_CHAOS := 0.04

## The squad member he last saw, where, and when.
var spotted: Soldier
var spotted_pos := Vector3.ZERO
var spotted_at := -1000.0
## Host: what he has shouted (tests read it).
var shouts := 0
var _shout_at := -1000.0
var _cornered_since := -1.0
## Host: how often he took his surrender back and bolted (tests read it).
var bolts := 0
## Scales his odds of bolting (tests raise it to make him bolt at the next check).
var bolt_scale := 1.0
var _unwatched_since := -1.0
var _bolt_check := 0.0


func hostile() -> bool:
	return side == Person.HOSTILE


func status_text() -> String:
	if hostile() and not Person.is_captive(body) and _alarmed():
		return "Running to his men" if _refuge() else "Running"
	return super.status_text()


func _alarmed() -> bool:
	return Soldier._now() - spotted_at < ALARM_S or (threatened() and spotted_at > -999.0)


func _decide() -> void:
	if hostile() and _check_bolt():
		_think_cd = 0.0
	super._decide()


## A hostile HVT who gave up but isn't cuffed (and isn't delivered): he needs watching.
func uncuffed_captive() -> bool:
	var st := Person.state(body)
	return bool(st.get("surrendered", false)) and not bool(st.get("cuffed", false)) and not bool(st.get("delivered", false)) \
		and body.vitals.is_up() and not is_instance_valid(body.carried_by) and String(st.get("seated_in", "")) == ""


## Someone from the squad up within WATCH_M who isn't pinned down.
func watched() -> bool:
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.faction == &"friendly" and not s.is_queued_for_deletion() and s.vitals.is_up() \
				and s.suppression < SquadAI.PINNED and s.global_position.distance_to(body.global_position) <= WATCH_M:
			return true
	return false


## How willing he is to run (0..1): the more it hurts the less; badly hurt (the surrender
## thresholds), not at all.
func bolt_will() -> float:
	var v := body.vitals
	if v.pain() >= PeopleLayer.SURRENDER_PAIN or v.blood_fraction() <= PeopleLayer.SURRENDER_BLOOD or v.injury() >= PeopleLayer.SURRENDER_INJURY:
		return 0.0
	return clampf(1.0 - v.pain() - v.injury(), 0.2, 1.0)


## Every BOLT_CHECK_S an uncuffed captive may take his surrender back and run. True if he did.
func _check_bolt() -> bool:
	if not uncuffed_captive():
		_unwatched_since = -1.0
		return false
	var now := Soldier._now()
	var is_watched := watched()
	if is_watched:
		_unwatched_since = -1.0
	elif _unwatched_since < 0.0:
		_unwatched_since = now
	if now < _bolt_check:
		return false
	_bolt_check = now + BOLT_CHECK_S
	var chance := BOLT_CHAOS if threatened() else 0.0
	if not is_watched:
		chance = maxf(chance, BOLT_MAX * clampf((now - _unwatched_since - BOLT_GRACE_S) / BOLT_RAMP_S, 0.0, 1.0))
	chance = minf(chance * bolt_will() * bolt_scale, 1.0)
	if chance <= 0.0 or _rng.randf() >= chance:
		return false
	var layer := PeopleLayer.find(body)
	if layer == null:
		return false
	layer.server_take_back_surrender(body)
	bolts += 1
	_cornered_since = -1.0
	# He knows where they are: the nearest of the squad.
	var nearest: Soldier = null
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.faction == &"friendly" and s.vitals.is_up() and not s.is_queued_for_deletion() \
				and (nearest == null or s.global_position.distance_to(body.global_position) < nearest.global_position.distance_to(body.global_position)):
			nearest = s
	spotted = nearest
	spotted_pos = nearest.global_position if nearest else body.global_position - body.global_basis.z * 5.0
	spotted_at = now
	return true


func _decide_free() -> void:
	if not hostile():
		super._decide_free()
		return
	_look()
	if _check_give_up():
		return
	if not _alarmed():
		if threatened():
			super._decide_free()  # gunfire, nobody seen yet: hide
			return
		mode = Mode.ROUTINE
		return
	_shout_if_due()
	var refuge := _refuge()
	if refuge:
		var away := refuge.global_position - _threat_point()
		away.y = 0.0
		var spot := refuge.global_position + (away.normalized() if away.length() > 0.1 else Vector3.ZERO) * JOIN_M
		_hide = NavigationServer3D.map_get_closest_point(body.get_world_3d().navigation_map, spot)
		_has_hide = true
		mode = Mode.FLEE if _flat(_hide) > ARRIVE + 0.6 else Mode.COWER
		return
	# Nobody left to run to: get away from them and hide.
	threat_pos = _threat_point()
	threat_at = maxf(threat_at, spotted_at)
	if not _has_hide or not _hides_from(_hide, threat_pos):
		_find_hide()
	mode = Mode.FLEE if _flat(_hide) > ARRIVE + 0.3 else Mode.COWER


func _act() -> void:
	super._act()
	if hostile() and not Person.is_captive(body) and mode in [Mode.FLEE, Mode.COWER, Mode.ROUTINE]:
		_resist()


## Looks for the squad: anyone on the players' side, up, within SPOT_M, inside his view cone
## and in sight (or right next to him).
func _look() -> void:
	var eyes := body.camera.global_position
	var forward := -body.global_basis.z
	forward.y = 0.0
	var best: Soldier = null
	var best_d := SPOT_M
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s.faction != &"friendly" or s.is_queued_for_deletion() or not s.vitals.is_up():
			continue
		var to := s.global_position - body.global_position
		var d := to.length()
		if d > best_d:
			continue
		to.y = 0.0
		var in_view := d < 1.5 or rad_to_deg(forward.normalized().angle_to(to.normalized())) <= VIEW_HALF_DEG
		if in_view and Throwables.clear_line(body.get_world_3d(), eyes, s.aim_point()):
			best = s
			best_d = d
	if best:
		spotted = best
		spotted_pos = best.global_position
		spotted_at = Soldier._now()


## Where the threat is as far as he knows: where he last saw the squad, else the last shot.
func _threat_point() -> Vector3:
	if spotted_at > threat_at and Soldier._now() - spotted_at < ALARM_S:
		return spotted_pos
	return threat_pos


## Shouts and gives the squad away to every hostile within EXPOSE_M.
func _shout_if_due() -> void:
	if Soldier._now() - _shout_at < SHOUT_GAP_S or Soldier._now() - spotted_at > SHOUT_GAP_S:
		return  # only while he still sees them
	_shout_at = Soldier._now()
	shouts += 1
	var layer := PeopleLayer.find(body)
	if layer:
		layer.server_say(body, SHOUTS[_rng.randi() % SHOUTS.size()])
		layer.server_expose(body, _threat_point(), EXPOSE_M)


## The nearest hostile soldier still up (not a captive), or null.
func _refuge() -> Soldier:
	var best: Soldier = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s == body or s.faction != Person.HOSTILE or s.is_queued_for_deletion() or not s.vitals.is_up() or Person.is_captive(s):
			continue
		var d := s.global_position.distance_to(body.global_position)
		if d < best_d:
			best = s
			best_d = d
	return best


## Steps away from anyone from the squad right in front of him.
func _resist() -> void:
	if not is_instance_valid(spotted) or Soldier._now() - spotted_at > 1.0:
		return
	var to := spotted.global_position - body.global_position
	to.y = 0.0
	if to.length() > RESIST_M:
		return
	var away := -to.normalized()
	var spot := NavigationServer3D.map_get_closest_point(body.get_world_3d().navigation_map, body.global_position + away * 3.0)
	_go(spot, true)


## Cornered or badly hurt and alone: he gives up. True if he did.
func _check_give_up() -> bool:
	var friend_close := false
	var alone := true
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s == body or s.is_queued_for_deletion() or not s.vitals.is_up():
			continue
		var d := s.global_position.distance_to(body.global_position)
		if s.faction == &"friendly" and d <= CORNERED_M:
			friend_close = true
		elif s.faction == Person.HOSTILE and not Person.is_captive(s) and d <= ISOLATED_M:
			alone = false
	if not (friend_close and alone):
		_cornered_since = -1.0
		return false
	if _cornered_since < 0.0:
		_cornered_since = Soldier._now()
	var hurt := body.vitals.pain() >= PeopleLayer.SURRENDER_PAIN or body.vitals.blood_fraction() <= PeopleLayer.SURRENDER_BLOOD
	if not hurt and Soldier._now() - _cornered_since < CORNERED_S:
		return false
	var layer := PeopleLayer.find(body)
	if layer:
		layer.server_surrender(body, "cornered")
	mode = Mode.HOLD
	_hold = body.global_position  # he stops where he gave up
	return true
