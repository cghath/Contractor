class_name LauncherAI
extends RefCounted
## When AI soldiers use the launcher they carry (wave 5, V2), host only. SquadAI asks think()
## each frame before its own shooting; while it returns true the launcher has the soldier
## (bringing it up, loading, aiming, the backblast call, firing) and the rifle waits.
##
## The rules (proposed):
## - Anyone with a launcher fires it at an enemy vehicle in sight, between MIN_RANGE_M and
##   the launcher's reach (VEHICLE_RANGE_M; a Javelin's lock range), leading a moving one and
##   aiming over the round's drop. Never closer than MIN_RANGE_M (or the round's arming
##   distance and a little, a Javelin's 25 m) when it comes to the shot.
## - Hostiles also fire at a group behind cover: at least GROUP_MIN enemies within GROUP_M of
##   the one they're fighting, at least half of them behind something solid within COVER_NEAR_M
##   in front of them (the rocket goes into the cover). Never at a single soldier, and never
##   at soldiers in the open.
## - Squadmates fire when ordered (the command menu's Action > Fire launcher there: order_squad)
##   at the vehicle near that point, or the point itself.
## - Never with a friend (or a civilian) within FRIEND_CLEAR_M of the target, up or down, nor
##   with one in the rocket's path (SquadAI._friendly_in_line, over the launcher's spread), nor
##   with a friend or civilian in the backblast, standing, prone or down (queue 17 part 5):
##   they wait and call "Clear the backblast!", and call "Backblast clear!" before they fire.
##   Nor with a wall right behind them (the backblast would come back), nor with something
##   solid between them and the target (they may have moved since choosing).
## - Out of rounds, a soldier keeps the launcher (it's loot) but stops trying.

const SCAN_S := 0.5
const MIN_RANGE_M := 20.0
const VEHICLE_RANGE_M := 300.0
const GROUP_RANGE_M := 150.0
const GROUP_M := 4.0
const GROUP_MIN := 2
const COVER_NEAR_M := 3.0
const FRIEND_CLEAR_M := 10.0
## Bringing the tube up and settling before the first shot, the longest an engagement runs,
## and the pause before the next one.
const SHOULDER_S := 1.5
const ENGAGE_MAX_S := 20.0
const COOLDOWN_S := 10.0
const AIM_TOLERANCE_DEG := 1.5
## The line to the target counts as clear when the first wall on it is at most this short of
## the target (the cover a group hides behind is the target).
const LINE_SLACK_M := 1.0
## "Backblast clear!" comes this long before the shot.
const CALL_LEAD_S := 0.6
## Hostile insurgents carrying an RPG-7 (catalogue plan: insurgent bodies): every RPG_EVERY-th
## hostile on the standard kit spawned in a level (the compound's first four carry none), so
## every run is the same.
const RPG_EVERY := 5
const INSURGENT_KIT: Array[StringName] = [&"rpg7", &"pg7v_round", &"pg7v_round", &"og7v_round"]
const META := &"launcher_ai"
const KIT_META := &"launcher_ai_kits"


## What one soldier is doing with their launcher.
class State extends RefCounted:
	var next_scan := 0.0
	var cooldown_until := 0.0
	var engaged := false
	var kind := ""  # "vehicle", "group" or "order"
	var target: Node3D
	var point := Vector3.ZERO
	var since := 0.0
	var called_at := -1.0
	var warned := false
	var order_point: Variant = null  # Vector3 when ordered
	var order_target: Node3D
	var out_of_rounds := false
	## What it is doing or why it isn't (status, tests).
	var why := ""


## Host: the launcher kit the next hostile on the standard kit spawned in `level` gets (most
## get none; every RPG_EVERY-th an RPG-7 and rounds). Counted on the level.
static func insurgent_kit(level: Node) -> Array[StringName]:
	var n := int(level.get_meta(KIT_META, 0)) + 1
	level.set_meta(KIT_META, n)
	if n % RPG_EVERY == 0:
		return INSURGENT_KIT
	return []


## What `s` is doing with their launcher (or why not), for status lines and tests.
static func status(s: Soldier) -> String:
	return _state(s).why if s and s.has_meta(META) else ""


static func _state(s: Soldier) -> State:
	if not s.has_meta(META):
		s.set_meta(META, State.new())
	return s.get_meta(META) as State


## Host only. Squadmates among `names` (all if empty) carrying a launcher: the nearest one
## able fires at the vehicle near `point` (seen from `from`'s eye), or at `point`. Returns the
## name of who will, or "".
static func order_squad(squad: Squad, from: Soldier, point: Vector3, names := PackedStringArray()) -> String:
	var units := squad.pick(names)
	units.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.global_position.distance_to(point) < b.global_position.distance_to(point))
	var target := vehicle_near_line(from.get_tree(), from.camera.global_position, point, 6.0)
	for s in units:
		if s.vitals.is_up() and Launchers.launcher_of(s) != null and (Launchers.loaded_of(s) != &"" or not Launchers.carried_rounds(s).is_empty()):
			var st := _state(s)
			st.order_point = point
			st.order_target = target
			st.cooldown_until = 0.0
			st.next_scan = 0.0
			return String(s.name)
	return ""


## The vehicle (not a wreck) whose middle is nearest the segment `from`-`to`, within `reach`.
static func vehicle_near_line(tree: SceneTree, from: Vector3, to: Vector3, reach: float) -> Vehicle:
	var best: Vehicle = null
	var best_d := reach
	for n in tree.get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if v == null or v.wrecked:
			continue
		var c := Launchers.hull_box(v).get_center()
		var d := Geometry3D.get_closest_point_to_segment(c, from, to + (to - from).normalized() * 5.0).distance_to(c)
		if d < best_d:
			best = v
			best_d = d
	return best


## A vehicle still worth a rocket: there, not a wreck, not already burning (lost).
static func worth_a_rocket(v: Variant) -> bool:  # untyped: it may have been freed
	if not is_instance_valid(v) or not v is Vehicle:
		return false
	var vehicle := v as Vehicle
	return not vehicle.is_queued_for_deletion() and not vehicle.wrecked and not vehicle.is_burning()


## Which side a faction is on: the player's vehicles ("player") are the friendly side.
static func side_of(faction: StringName) -> StringName:
	return &"friendly" if faction == &"player" else faction


## Host only, each physics frame from SquadAI._shoot. True while the launcher has the soldier.
static func think(ai: SquadAI) -> bool:
	var body := ai.body
	if body == null or body.inventory.slots.get(Launchers.SLOT, &"") == &"":
		return false
	var st := _state(body)
	var now := Soldier._now()
	if is_instance_valid(body.vehicle):
		st.why = "riding in a vehicle"  # out first (Launchers.server_fire refuses from a seat)
		return _stand_down(body, st)
	if body.carrying != null or body.stunned_s > 0.0 or body.suppression >= SquadAI.PINNED or not ai.weapons_free() \
			or ai.intent in [SquadAI.Intent.CASUALTY, SquadAI.Intent.HEAL, SquadAI.Intent.SCAVENGE, SquadAI.Intent.RELOAD]:
		st.why = "busy, pinned or holding fire (intent %d)" % ai.intent
		return _stand_down(body, st)
	var launchers := Launchers.of(body)
	var item := Launchers.launcher_of(body)
	if launchers == null or item == null:
		return false
	if not st.engaged:
		if body.active_slot == Launchers.SLOT and not body.is_reloading:
			_stand_down(body, st)  # done with it (or a reload just finished): back to the rifle
		if now < st.next_scan or now < st.cooldown_until or (st.out_of_rounds and st.order_point == null):
			return false
		st.next_scan = now + SCAN_S
		var pick := choose(ai, item, st)
		if pick.is_empty():
			st.why = "nothing worth a rocket"
			return false
		st.engaged = true
		st.kind = pick.kind
		st.target = pick.get("target")
		st.point = pick.point
		st.since = now
		st.called_at = -1.0
		st.warned = false
		body.select_weapon(Launchers.SLOT)
	if now - st.since > ENGAGE_MAX_S or (st.kind == "vehicle" and not worth_a_rocket(st.target)):
		st.cooldown_until = now + COOLDOWN_S * 0.5
		return _stand_down(body, st)
	var aim := _aim_point(body, st)
	ai._aim_at(aim)
	body.want_aim = true
	body.move_input = Vector2.ZERO  # stop to shoulder it (SquadAI steers before it shoots)
	body.want_sprint = false
	# Loaded? A reload is timed on the host (Launchers.server_reload).
	var w := Launchers.loaded_of(body)
	st.why = "engaging a %s" % st.kind
	if w == &"":
		st.why = "loading"
		if now >= body._server_busy_until:
			var choice := _round_for(body, st.kind)
			if choice == &"" or launchers.server_reload(body, choice) < 0.0:
				st.out_of_rounds = true
				st.order_point = null
				return _stand_down(body, st)
			body._busy_until = body._server_busy_until
			body.is_reloading = true
		return true
	if now - st.since < SHOULDER_S or now < body._server_busy_until:
		return true
	var eye := body.camera.global_position
	if (-body.camera.global_basis.z).angle_to((aim - eye).normalized()) > deg_to_rad(AIM_TOLERANCE_DEG):
		st.why = "aiming"
		return true
	# Too close now (they moved up since choosing)? It wouldn't arm, and the blast is theirs.
	if eye.distance_to(_target_point(st)) < maxf(MIN_RANGE_M, float(Warheads.data(w).get("arming_m", 0.0)) + 2.0):
		st.cooldown_until = now + COOLDOWN_S * 0.3
		st.why = "too close for a rocket"
		if st.kind == "order":
			st.order_point = null
		return _stand_down(body, st)
	# Still a clear line? The soldier may have moved (into cover) since choosing: never put a
	# rocket into the wall in front of them.
	if not _line_clear(body, eye, _target_point(st)):
		if st.kind == "group":
			var again := group_behind_cover(ai)
			if again.is_empty():
				st.cooldown_until = now + COOLDOWN_S * 0.3
				st.why = "lost the line to the group"
				return _stand_down(body, st)
			st.point = again.point
		st.why = "no clear line"
		return true
	if ai._friendly_in_line(_target_point(st), spread_rad(ai)):
		st.why = "a friend in the line of fire"
		return true
	if friend_in_backblast(body, item):
		st.why = "a friend in the backblast"
		if not st.warned:
			st.warned = true
			_say(body, &"backblast_warn", "Clear the backblast!")
		return true
	if wall_behind(body, item):
		st.why = "a wall right behind"  # it would throw the backblast back at them
		return true
	if st.called_at < 0.0:
		st.called_at = now
		_say(body, &"backblast", "Backblast clear!")
		return true
	if now - st.called_at < CALL_LEAD_S:
		return true
	var spread := spread_rad(ai)
	var dir := ((aim - eye).normalized() + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * tan(spread) * 0.5).normalized()
	var guided_target: Node3D = st.target if st.kind != "group" else null
	var why := launchers.server_fire(body, eye, dir, "", guided_target)
	st.why = "fired" if why == "" else "held fire: %s" % why
	if why != "":
		print("[launcher ai] %s held fire: %s" % [body.display_name(), why])
	st.cooldown_until = now + COOLDOWN_S
	if st.kind == "order":
		st.order_point = null
	return _stand_down(body, st)


## How far (radians) `ai`'s rocket may stray from the aim: less skill and suppression widen it.
static func spread_rad(ai: SquadAI) -> float:
	return deg_to_rad((1.0 - ai.combat) * 1.2 + ai.body.suppression * 3.0)


## Puts the launcher away (back to the rifle or pistol). Always false (the rifle has them).
static func _stand_down(body: Soldier, st: State) -> bool:
	if st.engaged:
		st.engaged = false
		st.target = null
	if body.active_slot == Launchers.SLOT and not body.is_reloading:
		for slot: StringName in [&"primary", &"sidearm"]:
			if body.inventory.slots.get(slot, &"") != &"":
				body.select_weapon(slot)
				break
	return false


## What this soldier should fire at now: {"kind", "target"?, "point"} or {}.
static func choose(ai: SquadAI, item: ItemData, st: State) -> Dictionary:
	var body := ai.body
	var eye := body.camera.global_position
	if st.order_point != null:
		if is_instance_valid(st.order_target):
			return {"kind": "vehicle", "target": st.order_target, "point": Launchers.hull_box(st.order_target).get_center()}
		return {"kind": "order", "point": st.order_point}
	var reach := float(item.stats.get("lock_range_m", VEHICLE_RANGE_M)) if item.stats.has("lock_range_m") else VEHICLE_RANGE_M
	var best: Vehicle = null
	var best_d := reach
	for n in body.get_tree().get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if not worth_a_rocket(v) or side_of(v.faction) == side_of(body.faction):
			continue
		var c := Launchers.hull_box(v).get_center()
		var d := eye.distance_to(c)
		if d < MIN_RANGE_M or d >= best_d or not _in_sight(body, c, v) or _friend_near(body, c):
			continue
		best = v
		best_d = d
	if best:
		return {"kind": "vehicle", "target": best, "point": Launchers.hull_box(best).get_center()}
	if body.faction == &"hostile" and ai.in_contact():
		var group := group_behind_cover(ai)
		if not group.is_empty():
			return group
	return {}


## Hostiles: the cover in front of a group of enemies (GROUP_MIN or more within GROUP_M of
## the one this soldier fights, half or more of them behind something solid close in front),
## as {"kind": "group", "point"}; {} for a single soldier, soldiers in the open, or friends
## near.
static func group_behind_cover(ai: SquadAI) -> Dictionary:
	var body := ai.body
	var anchor: Vector3
	if ai.target != null and is_instance_valid(ai.target) and ai.target.vitals.is_up():
		anchor = ai.target.global_position
	elif ai.in_contact():
		anchor = body.threat_pos
	else:
		return {}
	var eye := body.camera.global_position
	if eye.distance_to(anchor) < MIN_RANGE_M or eye.distance_to(anchor) > GROUP_RANGE_M:
		return {}
	var space := body.get_world_3d().direct_space_state
	var members := 0
	var covered := 0
	var cover_point: Variant = null
	for n in body.get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s.faction == body.faction or not s.vitals.is_up() or Person.is_noncombatant(s):
			continue
		if s.global_position.distance_to(anchor) > GROUP_M:
			continue
		members += 1
		var chest := s.aim_point()
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, chest, 1, [body.get_rid()]))
		if not hit.is_empty() and (hit.position as Vector3).distance_to(chest) <= COVER_NEAR_M:
			covered += 1
			if cover_point == null or eye.distance_to(hit.position) < eye.distance_to(cover_point):
				cover_point = hit.position
	if members < GROUP_MIN or covered * 2 < members or cover_point == null or eye.distance_to(cover_point) < MIN_RANGE_M \
			or _friend_near(body, cover_point):
		return {}
	return {"kind": "group", "point": cover_point}


## A friend (own side) or a civilian within FRIEND_CLEAR_M of `point`, up or down (where a
## downed one's ragdoll lies: Soldier.body_point).
static func _friend_near(body: Soldier, point: Vector3) -> bool:
	for n in body.get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if _shields(body, s) and s.body_point().distance_to(point) < FRIEND_CLEAR_M:
			return true
	return false


## Someone `body` must not hurt: alive, not itself, on its side, or a civilian, HVT or captive.
static func _shields(body: Soldier, s: Soldier) -> bool:
	return s != null and s != body and not s.is_queued_for_deletion() and not s.vitals.is_dead() \
		and (s.faction == body.faction or Person.is_noncombatant(s))


## A line of sight from `body`'s eye to `point` on vehicle `v` (nothing of the world first).
static func _in_sight(body: Soldier, point: Vector3, _v: Node3D) -> bool:
	var eye := body.camera.global_position
	var hit := body.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, point, 1, [body.get_rid()]))
	return hit.is_empty() or eye.distance_to(hit.position) >= eye.distance_to(point) * 0.95


## What the round is meant to reach: a vehicle's middle, the cover in front of a group or
## the ordered point (before lead and drop).
static func _target_point(st: State) -> Vector3:
	if st.kind == "vehicle" and is_instance_valid(st.target):
		return Launchers.hull_box(st.target).get_center()
	return st.point


## Nothing of the world between `body`'s eye and `point` (up to LINE_SLACK_M short of it).
static func _line_clear(body: Soldier, eye: Vector3, point: Vector3) -> bool:
	var hit := body.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, point, 1, [body.get_rid()]))
	return hit.is_empty() or eye.distance_to(hit.position) >= eye.distance_to(point) - LINE_SLACK_M


## A friend or a civilian in the backblast of `body`'s launcher (its stats' backblast cone and
## injury reach): standing, crouched, prone or down (queue 17 part 5: a body lying behind the
## shooter is checked where it lies, someone upright anywhere from shins to head).
static func friend_in_backblast(body: Soldier, item: ItemData) -> bool:
	var blast: Dictionary = item.stats.get("backblast", {})
	var reach := float(blast.get("injury_m", 10.0))
	var cone := cos(deg_to_rad(float(blast.get("cone_deg", 45.0))))
	var back := body.camera.global_basis.z
	var rear := body.camera.global_position + back * 0.6
	for n in body.get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if not _shields(body, s):
			continue
		var points: Array = [s.aim_point()] if SquadAI._lying(s) \
			else [s.global_position + Vector3.UP * 0.4, s.global_position + Vector3.UP, s.global_position + Vector3.UP * 1.6]
		for p: Vector3 in points:
			var to := p - rear
			if to.length() < reach and to.normalized().dot(back) >= cone and Throwables.clear_line(body.get_world_3d(), rear, p):
				return true
	return false


## A wall within the launcher's reflect_m behind the back of the tube on `body`'s shoulder (as
## Launchers.server_fire places it): firing would throw the backblast back at them.
static func wall_behind(body: Soldier, item: ItemData) -> bool:
	var reflect_m := float((item.stats.get("backblast", {}) as Dictionary).get("reflect_m", 0.0))
	if reflect_m <= 0.0:
		return false  # a soft launch (Javelin, NLAW)
	var back := body.camera.global_basis.z
	var length := float((item.stats.get("size_m", [0, 0, 1.0]) as Array)[2])
	var rear := body.camera.global_position + back * (length * 0.5 + 0.05)
	var query := PhysicsRayQueryParameters3D.create(rear, rear + back * reflect_m, 1 | Vehicle.LAYER, [body.get_rid()])  # a wall or a hull
	return not body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Where to aim: a vehicle's middle where it will be when the round gets there, a group's
## cover or the ordered point; raised for the loaded round's drop.
static func _aim_point(body: Soldier, st: State) -> Vector3:
	var point := st.point
	var w := Launchers.loaded_of(body)
	var eye := body.camera.global_position
	if st.kind == "vehicle" and is_instance_valid(st.target):
		point = Launchers.hull_box(st.target).get_center()
		var flight := float(LauncherProjectile.drop_at(w, eye.distance_to(point)).time) if w != &"" else 0.0
		var v := st.target as Vehicle
		if v:
			point += v.linear_velocity * flight
	elif st.kind == "order" and st.order_point != null:
		point = st.order_point
	if w != &"":
		point += Vector3.UP * float(LauncherProjectile.drop_at(w, eye.distance_to(point)).drop)
	return point


## The round to load for a target of `kind`: HEAT (tandem first) at vehicles, HE or
## thermobaric at people, whatever there is otherwise.
static func _round_for(body: Soldier, kind: String) -> StringName:
	var carried := Launchers.carried_rounds(body)
	if carried.is_empty():
		return &""
	var want: Array = [Vehicle.TANDEM_HEAT, Vehicle.HEAT, Vehicle.HEDP] if kind == "vehicle" else [Vehicle.HE, Vehicle.THERMOBARIC, Vehicle.HEDP]
	for k: StringName in want:
		for id in carried:
			if Warheads.kind_of(ItemDB.get_item(id).stats.get("warhead", "")) == k:
				return id
	return carried[0]


static func _say(body: Soldier, id: StringName, text: String) -> void:
	var callouts := Callouts.of(body)
	if callouts:
		callouts.say(body, id, text)
