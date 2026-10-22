class_name RoadAmbush
extends GarrisonPost
## A team lying in wait by a road for vehicles (F-140, the overwatch mission's ambushers; LAMBS's
## ambush and VCOM's roadside teams learn the same drill). Host only. A GarrisonPost, so what a
## garrison does holds here too: the ambush's ground (the line and LEASH_M round it) is its
## footprint, nobody's weapon is free until it's sprung (SquadAI.weapons_free), and cut down and
## outgunned it breaks and runs (GarrisonPost's flight). Laid by server_lay (the mission's hook).
##
## - Holding: each man has his own spot on a line along the road through the ambush point,
##   LINE_SPACING_M apart, in cover against the road (SquadAI.find_cover, low cover he can fire
##   over first), down and facing the kill zone. No patrolling, no going to look at a sound.
## - Springing, at the right moment: when the first crewed enemy vehicle comes level with the
##   ambush (its closest pass, within KILL_M), or anything comes within CLOSE_M. Sooner when it's
##   given away: one of them fired on or down, or an enemy on foot one of them sees within
##   FOOT_SPRING_M (he has been found).
## - Sprung: every man opens up at once. They go for the vehicles first: the gunner on a mounted
##   gun, then the crews (target_bonus), the launchers at the lead vehicle (to block the road),
##   then the one at the back (priority_vehicle). Whoever fires on them from the high ground is
##   a target like any other once he's seen. They fight from their ground (the leash) and don't
##   chase the convoy or assault the hill.
## Numbers Proposed.

const KILL_M := 160.0
const CLOSE_M := 35.0
const FOOT_SPRING_M := 30.0
## The closest pass: a vehicle no nearer than PASS_SLACK_M of its last distance (it has stopped
## closing) counts as level with the ambush.
const PASS_SLACK_M := 0.5
const LEASH_M := 18.0
const LINE_SPACING_M := 5.0
const POSITION_COVER_M := 6.0
## Sprung, a crewed enemy vehicle's gunner is worth this many metres of range as a target, its
## other crew TARGET_CREW_M (SquadAI.target_score subtracts it).
const TARGET_GUNNER_M := 90.0
const TARGET_CREW_M := 60.0

## Where the ambush is (its middle) and the way the road runs past it (flat, unit; ZERO when
## not known: the line then runs across the way to the road's nearest point).
var at := Vector3.ZERO
var road_dir := Vector3.ZERO
## The road's nearest point to the ambush: the kill zone's middle (at itself with no road given).
var kill_point := Vector3.ZERO
## What sprung it, and the vehicle that did (the convoy's lead), for the log and the tests.
var why := ""
var lead: Vehicle
var _positions := {}  # soldier instance id -> his spot (Vector3)
var _passes := {}  # vehicle instance id -> its distance at the last check
var _settled := {}  # soldier instance id -> true once his spot's cover is picked (settle)


## Host: soldiers `men` lie in wait at `point` by the road `road` (its points, any number; empty:
## no road known). Each gets the post; their squad stops patrolling. Returns the ambush.
static func server_lay(men: Array, point: Vector3, road := PackedVector3Array(), id := "") -> RoadAmbush:
	var amb := RoadAmbush.new(id if id != "" else "ambush@%d,%d" % [roundi(point.x), roundi(point.z)], point, road)
	var squads := {}
	for m: Variant in men:
		var s := m as Soldier if is_instance_valid(m) else null
		var ai := SquadAI.of(s)
		if ai == null:
			continue
		amb.add(s)
		ai.post = amb
		ai.guard = true
		if ai.squad:
			squads[ai.squad] = true
	for sq: Squad in squads:
		sq.patrol.clear()  # (they hold their spots: _patrol with no route stays put)
	amb._place()
	print("[ambush] %s: %d men lying in wait, kill zone at (%.0f, %.0f)" % [amb.id, amb.members.size(), amb.kill_point.x, amb.kill_point.z])
	return amb


func _init(p_id: String, point: Vector3, road := PackedVector3Array()) -> void:
	at = point
	kill_point = point
	if road.size() >= 2:
		var best := INF
		for i in road.size() - 1:
			var q := _closest_on(road[i], road[i + 1], point)
			var d := Vector2(q.x - point.x, q.z - point.z).length()
			if d < best:
				best = d
				kill_point = q
				road_dir = Vector3(road[i + 1].x - road[i].x, 0.0, road[i + 1].z - road[i].z).normalized()
	var half := Vector2(LEASH_M, LEASH_M) + Vector2.ONE * GarrisonPost.MARGIN_M
	super(p_id, Rect2(Vector2(point.x, point.z) - half, half * 2.0))


## His own spot (null: not one of them).
func position_of(s: Soldier) -> Variant:
	return _positions.get(s.get_instance_id())


## Which way they face while they wait: the kill zone.
func facing_point() -> Vector3:
	return kill_point if kill_point.distance_to(at) > 1.0 else at + (road_dir.cross(Vector3.UP) if road_dir != Vector3.ZERO else Vector3.FORWARD) * 20.0


## Every man's spot: along the road through `at`, LINE_SPACING_M apart, then the best cover
## near that against the kill zone.
func _place() -> void:
	var along := road_dir
	if along == Vector3.ZERO:
		var to_road := Vector3(kill_point.x - at.x, 0.0, kill_point.z - at.z)
		along = to_road.normalized().cross(Vector3.UP) if to_road.length() > 1.0 else Vector3.RIGHT
	var n := members.size()
	for i in n:
		var s := members[i]
		var ai := SquadAI.of(s)
		var slot := at + along * LINE_SPACING_M * (i - (n - 1) / 2.0)
		var q := NavigationServer3D.map_get_closest_point(s.get_world_3d().navigation_map, slot)
		if q.distance_to(slot) > 3.0 or not q.is_finite():
			q = slot
		_positions[s.get_instance_id()] = q
		ai._hold_point = q


## His spot's cover, picked once his brain is up (SquadAI._hold_ambush asks): the best near his
## slot against the kill zone (SquadAI.find_cover: low cover he can fire over first).
func settle(ai: SquadAI) -> void:
	var id := ai.body.get_instance_id()
	if _settled.has(id) or not _positions.has(id):
		return
	_settled[id] = true
	var keep := ai.body.threat_pos
	ai.body.threat_pos = facing_point()  # (cover against the road, not the last thing he heard)
	var spot: Variant = ai.find_cover(_positions[id], POSITION_COVER_M)
	ai.body.threat_pos = keep
	if spot is Vector3:
		_positions[id] = spot
		ai._hold_point = spot


## Every CHECK_S (any member's tick calls it): springs the ambush at the right moment; once
## sprung, GarrisonPost's flight.
func update(now: float) -> void:
	if sprung or fleeing:
		super(now)
		return
	if now - _checked_at < CHECK_S:
		return
	_checked_at = now
	var up := alive()
	if up.is_empty():
		return
	if up.size() < members.filter(func(s: Variant) -> bool: return is_instance_valid(s)).size():
		_spring_now("a man down", null)
		return
	for s in up:
		var ai := SquadAI.of(s)
		if ai and now - ai._fired_on_at < SquadAI.CONTACT_MEMORY_S:
			_spring_now("%s fired on" % s.name, null)
			return
		if ai and ai.target and is_instance_valid(ai.target) and ai.target.vitals.is_up() and Vehicle.ride_of(ai.target) == null \
				and ai.target.global_position.distance_to(s.global_position) <= FOOT_SPRING_M:
			_spring_now("found by %s at %d m" % [ai.target.name, roundi(ai.target.global_position.distance_to(s.global_position))], null)
			return
	var faction := up[0].faction
	for n in up[0].get_tree().get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if v == null or v.wrecked or not crewed_by_enemy(v, faction):
			continue
		var d := Vector2(v.global_position.x - at.x, v.global_position.z - at.z).length()
		var key := v.get_instance_id()
		var before := float(_passes.get(key, INF))
		_passes[key] = d
		if d <= CLOSE_M:
			_spring_now("%s within %d m" % [v.display_name(), int(CLOSE_M)], v)
			return
		if d <= KILL_M and before < INF and d >= before - PASS_SLACK_M:
			_spring_now("%s level with the ambush at %d m" % [v.display_name(), roundi(d)], v)
			return


func _spring_now(p_why: String, v: Vehicle) -> void:
	why = p_why
	lead = v
	_spring(p_why)
	for s in alive():
		var ai := SquadAI.of(s)
		if ai:
			ai._callout(&"tactic", "Ambush! Open fire!" if v else "Contact! Open fire!")
			break


## Whether `v` has an enemy of `faction` aboard, up (a soldier, not a civilian or a captive).
static func crewed_by_enemy(v: Vehicle, faction: StringName) -> bool:
	for s: Variant in v.occupants():
		if is_instance_valid(s) and (s as Soldier).vitals.is_up() and (s as Soldier).faction != faction \
				and (s as Soldier).faction != &"civilian" and not Person.is_noncombatant(s as Soldier):
			return true
	return false


## Sprung: how much more `s` is worth as a target (metres off his range; see TARGET_*): the
## gunner of a crewed enemy vehicle, then its crew.
func target_bonus(s: Soldier) -> float:
	if not sprung:
		return 0.0
	var v := Vehicle.ride_of(s)
	if v == null or v.wrecked:
		return 0.0
	return TARGET_GUNNER_M if v.gunner() == s else TARGET_CREW_M


## The vehicle the launchers go for first: the lead that sprung it while it still moves (block
## the road), then the crewed enemy vehicle furthest back near the kill zone (trap the rest);
## null when none is in reach (LauncherAI then picks its own).
func priority_vehicle(faction: StringName, tree: SceneTree) -> Vehicle:
	if not sprung:
		return null
	if is_instance_valid(lead) and LauncherAI.worth_a_rocket(lead) and lead.can_drive() and crewed_by_enemy(lead, faction):
		return lead
	var best: Vehicle = null
	var best_d := -1.0
	var ahead := road_dir
	if is_instance_valid(lead) and lead.linear_velocity.length() > 1.0:
		ahead = Vector3(lead.linear_velocity.x, 0.0, lead.linear_velocity.z).normalized()
	for n in tree.get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if v == null or not LauncherAI.worth_a_rocket(v) or not crewed_by_enemy(v, faction) \
				or v.global_position.distance_to(kill_point) > KILL_M:
			continue
		var back := -(v.global_position - kill_point).dot(ahead) if ahead != Vector3.ZERO else v.global_position.distance_to(kill_point)
		if back > best_d:
			best = v
			best_d = back
	return best


static func _closest_on(a: Vector3, b: Vector3, p: Vector3) -> Vector3:
	var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return a
	var t := clampf(Vector3(p.x - a.x, 0.0, p.z - a.z).dot(ab) / len2, 0.0, 1.0)
	return a.lerp(b, t)
