class_name MortarTeam
extends Node
## An AI mortar team (G-25 part c, docs/static_weapons.md; the Captain, 2026-10-19: "mortars sent
## to reposition for targets to be in range", real ranges). Host only. Two or three men, the
## mortar's loads in their hands (StaticWeapons.KITS), their own Squad. Every THINK_S:
##   PACKED   a target (an enemy its squad or the one it works with knows of, or for the enemy
##            Alert's last known position while its uncertainty is under TARGET_MAX_UNCERTAIN_M)
##            and it picks a firing spot: in the mortar's range band (MIN_SHARE of its minimum on,
##            MAX_SHARE of its maximum), out of the target's sight, the walk short (a garrison's
##            inside its site); carries the loads there;
##   MOVING   at the spot, sets it up (StaticWeapons);
##   READY    fire missions: ranging rounds every RANGING_GAP_S, off by the target's uncertainty;
##            each round seen by one of its own side (within OBSERVER_M, a line on the target; the
##            enemy's needs its comms up) halves the error; once it's under FFE_ERROR_M (or after
##            BLIND_RANGING rounds nobody saw), FFE_ROUNDS for effect FFE_GAP_S apart, then
##            MISSION_GAP_S before the next. Never with its own side within DANGER_CLOSE_M of the
##            aim. A target out of its range band: it packs up and moves (PACKING, then PACKED).
## Rounds: ROUNDS a team (its loads carry the bipod and plate; the rounds are its bags). A
## garrison's team (`post`) sets up inside its site once the site is alerted. Numbers Proposed.

enum State { PACKED, MOVING, SETTING, READY, PACKING }
const GROUP := &"mortar_teams"
## Illumination on call (G-24, illum_for): one round at most every ILLUM_GAP_S a team, never its
## last ILLUM_KEEP rounds (kept for fire missions). Proposed.
const ILLUM_GAP_S := 40.0
const ILLUM_KEEP := 6
const STATE_NAMES: Array[String] = ["packed", "moving", "setting up", "ready", "packing"]
const THINK_S := 1.0
const TARGET_MAX_UNCERTAIN_M := 150.0
const MIN_SHARE := 1.4
const MAX_SHARE := 0.85
const SPOT_RINGS: Array[float] = [0.0, 20.0, 45.0, 80.0, 120.0]
const AT_SPOT_M := 2.0
const SETUP_RETRY_S := 25.0
const RANGING_GAP_S := 8.0
const OBSERVER_M := 450.0
const FFE_ERROR_M := 30.0
const BLIND_RANGING := 3
const FFE_ROUNDS := Vector2i(4, 6)
const FFE_GAP_S := 2.5
const MISSION_GAP_S := 60.0
const DANGER_CLOSE_M := 50.0
const ROUNDS := 24
const BASE_ERROR_M := 40.0  # a known position's error before any correction: one ranging round at least

var _illum_at := -1000.0  # when this team last fired illumination (illum_for)
var kit := "mortar_2b14"
var squad: Squad
var works_with: Squad
var post: GarrisonPost
var crew: Array[Soldier] = []
var state := State.PACKED
var gun: Vehicle
var spot := Vector3.INF
var target := Vector3.INF
var rounds := ROUNDS
var _error := INF          # this mission's aim error now (INF: no mission)
var _ranging := 0          # ranging rounds fired this mission
var _ffe_left := 0         # rounds for effect still to fire
var _next_round := 0.0
var _mission_gap_until := 0.0
var _since := 0.0
var _think := 0.0
## Ordered (part d): stays in the squad it was ordered from; `ordered_target` a fire mission's
## point (INF: none); packing up on an order ends it.
var ordered := false
var ordered_target := Vector3.INF
var dissolve_on_pack := false
static var _count := 0


## Host: `men` (2 or 3) become a mortar team for `p_kit`, its loads shared out among them.
static func form(level: Node, men: Array[Soldier], p_kit := "mortar_2b14", with: Squad = null, p_post: GarrisonPost = null, keep_squad := false) -> MortarTeam:
	if not StaticWeapons.KITS.has(p_kit) or men.is_empty():
		return null
	var loads: Array = StaticWeapons.KITS[p_kit].loads
	if men.size() < loads.size():
		return null
	_count += 1
	var team := MortarTeam.new()
	team.name = "MortarTeam%d" % _count
	team.kit = p_kit
	team.works_with = with
	team.post = p_post
	team.add_to_group(GROUP)
	level.add_child(team)
	var sq: Squad = with if keep_squad and with else Squad.new()
	if sq != with:
		sq.name = "MortarTeam%dSquad" % _count
		sq.faction = men[0].faction
		sq.patrol = []
		team.add_child(sq)
	team.squad = sq
	team.ordered = keep_squad
	for i in men.size():
		var s := men[i]
		var ai := SquadAI.of(s)
		if ai and not keep_squad:
			ai.squad = sq
		if i < loads.size() and not keep_squad:
			s.inventory.release_hands()
			s.inventory.take(loads[i])
		s.set_meta(&"gun_team", team.name)
		team.crew.append(s)
	return team


func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	_think -= delta
	if state == State.READY:
		_fire_step()
	if _think > 0.0:
		return
	_think = THINK_S
	var up := _up_crew()
	if up.is_empty():
		queue_free()
		return
	var now := Soldier._now()
	var t := _target()
	if t.is_finite():
		if not target.is_finite() or t.distance_to(target) > FFE_ERROR_M * 2.0:
			_error = INF  # a new target: a new mission
		target = t
	match state:
		State.PACKED:
			if dissolve_on_pack:
				_dissolve()
				return
			if target.is_finite() and _ready_to_go():
				var found: Variant = _pick_spot(target)
				if found is Vector3:
					spot = found
					_go_to_spot()
					_to(State.MOVING)
		State.MOVING:
			var lead := up[0]
			if lead.global_position.distance_to(spot) <= AT_SPOT_M:
				_face(lead, target)
				var sw := StaticWeapons.of(self)
				var why := sw.server_start_setup(lead) if sw else "no node"
				if why == "":
					_to(State.SETTING)
				elif now - _since > SETUP_RETRY_S:
					_to(State.PACKED)
			elif now - _since > SETUP_RETRY_S * 4.0:
				_to(State.PACKED)
		State.SETTING:
			var g := _gun_at(spot)
			if g:
				gun = g
				for s in up:
					var ai := SquadAI.of(s)
					if ai:
						ai.give_tactic({"kind": &"garrison", "spot": s.global_position, "face": Vector3.FORWARD, "port": "mortar", "id": name})
				_to(State.READY)
			elif now - _since > StaticWeapons.KITS[kit].set_s + 5.0:
				_to(State.PACKED)
		State.READY:
			if not is_instance_valid(gun) or gun.wrecked:
				gun = null
				_to(State.PACKED)
			elif target.is_finite() and not MortarFire.in_range(gun, target) and _ffe_left <= 0:
				_pack()
		State.PACKING:
			if not is_instance_valid(gun) or gun.is_queued_for_deletion():
				gun = null
				_to(State.PACKED)
			elif now - _since > StaticWeapons.KITS[kit].pack_s + 5.0:
				_to(State.READY)


## The fire mission, every frame while READY (rounds go out on their own clock).
func _fire_step() -> void:
	var now := Soldier._now()
	if not is_instance_valid(gun) or not target.is_finite() or rounds <= 0 or now < _next_round or now < _mission_gap_until:
		return
	if not MortarFire.in_range(gun, target) or _own_side_near(target):
		return
	var mf := MortarFire.of(self)
	if mf == null:
		return
	if _error == INF:
		_error = BASE_ERROR_M + _uncertainty()
		_ranging = 0
		_ffe_left = 0
	if _ffe_left <= 0 and (_error <= FFE_ERROR_M or _ranging >= BLIND_RANGING):
		_ffe_left = randi_range(FFE_ROUNDS.x, FFE_ROUNDS.y)
		print("[mortar] %s: fire for effect, %d rounds (error %.0f m)" % [name, _ffe_left, _error])
	var by: Soldier = _up_crew()[0] if not _up_crew().is_empty() else null
	if mf.server_fire(gun, target, _error, by) < 0.0:
		return
	rounds -= 1
	if _ffe_left > 0:
		_ffe_left -= 1
		_next_round = now + FFE_GAP_S
		if _ffe_left == 0:
			_mission_gap_until = now + MISSION_GAP_S
			_error = INF  # the next mission ranges again
	else:
		_ranging += 1
		_next_round = now + RANGING_GAP_S
		if _observed(target):
			_error *= 0.5  # someone saw it land: the correction comes over the radio


## Host (G-24): a team of `asker`'s side, set up and in range, puts an illumination round over
## `at`. Returns whether one fired.
static func illum_for(asker: Soldier, at: Vector3) -> bool:
	var now := Soldier._now()
	for n in asker.get_tree().get_nodes_in_group(GROUP):
		var team := n as MortarTeam
		if team == null or team.state != State.READY or not is_instance_valid(team.gun) or team.rounds <= ILLUM_KEEP \
				or now - team._illum_at < ILLUM_GAP_S or team._up_crew().is_empty() or team._up_crew()[0].faction != asker.faction:
			continue
		var mf := MortarFire.of(team)
		if mf == null or not MortarFire.in_range(team.gun, at):
			continue
		if mf.server_fire_illum(team.gun, at, team._up_crew()[0]) >= 0.0:
			team.rounds -= 1
			team._illum_at = now
			print("[mortar] %s: illumination over (%.0f, %.0f) for %s" % [team.name, at.x, at.z, asker.name])
			return true
	return false


func _to(s: State) -> void:
	if s != state:
		print("[mortar] %s: %s -> %s" % [name, STATE_NAMES[state], STATE_NAMES[s]])
	state = s
	_since = Soldier._now()


static func _up(s: Variant) -> bool:  # (untyped: a typed parameter errors on a freed man)
	return is_instance_valid(s) and not (s as Soldier).is_queued_for_deletion() and (s as Soldier).vitals.is_up()


func _up_crew() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for s: Variant in crew:
		if _up(s):
			out.append(s)
	return out


## Every load still in the crew's hands, and a garrison's site alerted.
func _ready_to_go() -> bool:
	if post and not post.sprung and not _site_alerted():
		return false
	var have := 0
	for s in _up_crew():
		if StaticWeapons.kit_of_load(s.inventory.hands) == kit:
			have += 1
	return have == (StaticWeapons.KITS[kit].loads as Array).size()


func _site_alerted() -> bool:
	var alert := Alert.of(self)
	var c := _up_crew()
	return alert != null and not c.is_empty() and alert.state_at(c[0].global_position) >= Alert.State.ALERTED


## Where to fire: the nearest enemy its squad (or the squad it works with) knows of; for the enemy,
## else Alert's last known position while it's still a fix (TARGET_MAX_UNCERTAIN_M). INF for none.
func _target() -> Vector3:
	var c := _up_crew()
	if c.is_empty():
		return Vector3.INF
	if ordered:
		return ordered_target  # the company's mortar fires where it's told
	var from := c[0].global_position
	var best := Vector3.INF
	for sq: Squad in [squad, works_with]:
		if sq == null or not is_instance_valid(sq):
			continue
		for e: Dictionary in sq.enemy_picture():
			var p: Vector3 = e.pos
			if not best.is_finite() or p.distance_to(from) < best.distance_to(from):
				best = p
	if best.is_finite():
		return best
	if c[0].faction == &"hostile":
		var alert := Alert.of(self)
		var lk: Dictionary = alert.last_known() if alert else {}
		if not lk.is_empty() and float(lk.radius) <= TARGET_MAX_UNCERTAIN_M:
			return lk.pos
	return Vector3.INF


## How unsure the target is: Alert's radius for the enemy's last known position, else 0.
func _uncertainty() -> float:
	var alert := Alert.of(self)
	var lk: Dictionary = alert.last_known() if alert else {}
	if not lk.is_empty() and (lk.pos as Vector3).distance_to(target) < 5.0:
		return float(lk.radius)
	return 0.0


## A firing spot round the crew for `at`: in the range band, out of its sight, the walk short.
func _pick_spot(at: Vector3) -> Variant:
	var c := _up_crew()
	var world := c[0].get_world_3d()
	var map := world.navigation_map
	var from := c[0].global_position
	var m: Dictionary = StaticWeapons.KITS[kit].mortar
	var lo := float(m.min_m) * MIN_SHARE
	var hi := float(m.max_m) * MAX_SHARE
	var best: Variant = null
	var best_score := INF
	for ring in SPOT_RINGS:
		for k in (1 if ring == 0.0 else 12):
			var a := TAU * k / 12.0 + ring
			var q := NavigationServer3D.map_get_closest_point(map, from + Vector3(cos(a), 0.0, sin(a)) * ring)
			if post and not post.holds(q):
				continue
			var d := Vector2(q.x - at.x, q.z - at.z).length()
			if d < lo or d > hi:
				continue
			var s := q.distance_to(from)
			if Throwables.clear_line(world, at + Vector3.UP * 1.5, q + Vector3.UP * 1.0):
				s += 200.0  # he can see it: only if there's nowhere else
			if s < best_score:
				best = q
				best_score = s
	return best


func _go_to_spot() -> void:
	var c := _up_crew()
	for i in c.size():
		var ai := SquadAI.of(c[i])
		if ai:
			var off := Vector3(cos(i * 2.1), 0.0, sin(i * 2.1)) * (0.0 if i == 0 else 1.5)
			ai.give_tactic({"kind": &"garrison", "spot": spot + off, "face": Vector3.FORWARD, "port": "mortar", "id": name})


static func _face(s: Soldier, at: Vector3) -> void:
	var way := Vector3(at.x - s.global_position.x, 0.0, at.z - s.global_position.z)
	if way.length() > 0.5:
		s.rotation.y = atan2(-way.x, -way.z)


func _gun_at(p: Vector3) -> Vehicle:
	var layer := VehicleLayer.of(self)
	if layer == null:
		return null
	for v: Vehicle in layer.vehicles():
		if v.model == kit and not v.wrecked and not v.is_queued_for_deletion() and v.global_position.distance_to(p) < StaticWeapons.PLACE_OUT_M + 1.5:
			return v
	return null


## Whether one of its own side up within OBSERVER_M of `at` has a line on it (the enemy: with its
## comms up). Corrections come from what someone sees.
func _observed(at: Vector3) -> bool:
	var c := _up_crew()
	if c.is_empty():
		return false
	var side := c[0].faction
	if side == &"hostile":
		var alert := Alert.of(self)
		if alert and alert.comms_down:
			return false
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.faction == side and s.vitals.is_up() and s.global_position.distance_to(at) <= OBSERVER_M \
				and Throwables.clear_line(s.get_world_3d(), s.camera.global_position, at + Vector3.UP * 1.0):
			return true
	return false


func _own_side_near(at: Vector3) -> bool:
	var c := _up_crew()
	if c.is_empty():
		return true
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.faction == c[0].faction and s.vitals.is_up() and Vector2(s.global_position.x - at.x, s.global_position.z - at.z).length() < DANGER_CLOSE_M:
			return true
	return false


## Host (the command menu): pack up now, then back to the squad.
func server_pack_up() -> void:
	dissolve_on_pack = true
	if state == State.READY and is_instance_valid(gun):
		_pack()
	elif state != State.PACKING:
		_dissolve()


func _dissolve() -> void:
	for s in _up_crew():
		s.remove_meta(&"gun_team")
		var ai := SquadAI.of(s)
		if ai:
			ai.give_tactic({})
	queue_free()


func _pack() -> void:
	var c := _up_crew()
	if c.is_empty() or not is_instance_valid(gun):
		return
	for s in c:
		var ai := SquadAI.of(s)
		if ai:
			ai.give_tactic({"kind": &"garrison", "spot": s.global_position, "face": Vector3.FORWARD, "port": "mortar", "id": name})  # still while it's packed
	var sw := StaticWeapons.of(self)
	if sw and sw.server_start_pack(c[0], gun) == "":
		_to(State.PACKING)
