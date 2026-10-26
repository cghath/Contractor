class_name ZombieAI
extends Node
## Host-only brain for one of the dead (docs/survival.md S2; the stealth model, calls 29 and 33).
## Like CivilianAI it only writes the body's intent fields (move_input, want_sprint, rotation);
## the body is a Soldier in faction INFECTED with Vitals.undead (the head kills, anything else
## wears the pool down).
##
## Three senses feed one **awareness** (0..1) with a visible state:
## - **sight** (SIGHT_M by day, NIGHT_SIGHT_M at night and between by the darkness; half as far
##   for a crouched or prone man; the weather's sight_m caps it and its spot_x slows it; a line
##   of sight is needed): awareness rises by how well it sees him, faster up close;
## - **sound** (Survival.server_noise -> hear): a shot, a kicked door, a running man; how loud
##   sets how much awareness it adds, and it goes to where it was;
## - **smell** (SMELL_M downwind of a bleeding man, or any way round in calm air; blood and gore
##   on him: Soldier.smell_strength): a slow rise, and it drifts upwind to the source.
## States (Mode): IDLE shuffling about; INVESTIGATE walking to a sound or a smell and searching
## round it; **ALERT** (awareness past ALERT_AT): it stops, faces him, groans, and watches,
## awareness still rising while it sees him; **CHASE** (awareness 1): after him, a walker at its
## shamble, a runner flat out, the dead within GROUP_M joining; a bite or a blow every ATTACK_S
## in reach (Melee.server_strike); **SEARCH** where it lost him. Awareness falls when nothing
## feeds it. A player it's ALERT to or chasing is told he's watched (Soldier.server_watched: the
## HUD's eye). Thinks every THINK_S, steers every physics frame.
##
## The dead over time (docs/survival_deadtime.md): its **decay** (DeadDecay: a fresh one faster
## and harder-hitting, an old one slower); **dormant** in a nest by day (DeadNests: idle, its sight
## and hearing dulled, a loud noise or one of them seeing him wakes the whole nest); and the
## **climbing rules** (call 140): none of the dead climb ladders or walls (can_climb), a runner
## vaults waist-high (VAULT_M), a crawler squeezes under a gap of CRAWL_GAP_M up to STAND_GAP_M,
## everyone steps up STEP_UP_M; its paths keep to NAV_LAYERS (never a ladder's or climb link's
## layer), and one after a man up out of its reach stops under him and piles (ledge_blocked).

const INFECTED := &"infected"
## The kinds (data/zombies.json in time; Proposed): a walker's shamble (share of the run), a
## runner's sprint, at night a walker's a little faster.
const KINDS := {
	"walker": {"walk": 0.3, "chase": 0.38, "sprint": false, "pool": 12.0},
	"runner": {"walk": 0.32, "chase": 1.0, "sprint": true, "pool": 9.0},
	# The specials (call 19): a screamer calls the zone (a scream heard SCREAM_M, pressure up) when
	# it turns alert; a crawler keeps low (half as easy to see, a bite that trips him); a bloater
	# is slow and bursts when it dies (Survival._on_zombie_died); a hazmat one takes a quarter of
	# body damage (Vitals), the head as any other.
	"screamer": {"walk": 0.3, "chase": 0.5, "sprint": false, "pool": 8.0, "scream": true},
	"crawler": {"walk": 0.25, "chase": 0.6, "sprint": false, "pool": 9.0, "low": true, "trip": true},
	"bloater": {"walk": 0.22, "chase": 0.28, "sprint": false, "pool": 20.0},
	"hazmat": {"walk": 0.3, "chase": 0.4, "sprint": false, "pool": 40.0, "armoured": true},
}
const SCREAM_M := 120.0
const SCREAM_PRESSURE := 25.0
var screamed := false
## The climbing rules (call 140; Sieges does the walls built in the way).
const STEP_UP_M := 0.45
const VAULT_M := 1.0
const CRAWL_GAP_M := 0.25
const STAND_GAP_M := 1.5
const REACH_UP_M := 1.7
const LEDGE_M := 3.0
## The navigation layers the dead's paths use: the walk layer only (CLIMB_LAYER: ladders, climb
## and jump links a navmesh may carry, left out).
const NAV_LAYERS := 1
const CLIMB_LAYER := 2
## Dormant in a nest (DeadNests): its sight this share, a sound's awareness this share, and a
## sound this loud (a shot, a scream) wakes the nest.
const DORMANT_SIGHT := 0.35
const DORMANT_HEAR := 0.3
const WAKE_LOUD := 0.9
const NIGHT_WALK_MULT := 1.25
const SIGHT_M := 40.0
const NIGHT_SIGHT_M := 15.0
const LOW_SIGHT_MULT := 0.5
const SHOT_HEARD_M := 180.0
const SUPPRESSED_HEARD_M := 40.0
const SMELL_M := 30.0
const SMELL_CALM_M := 10.0   # in calm air, from any side
const CALM_MPS := 0.6
const GROUP_M := 12.0
const ATTACK_M := 1.5
const ATTACK_S := 1.3
const LOSE_S := 6.0
const THINK_S := 0.4
const SEARCH_S := 12.0
const ARRIVE_M := 1.5
const WANDER_M := 8.0
const TURN_RATE := 6.0
## Awareness: ALERT past this, CHASE at 1. Sight raises it SIGHT_RISE a second at a full view
## (a man close, standing, by day), less by the view's share; a sound adds its loudness (a shot
## 1: straight to the chase); smell SMELL_RISE a second; it falls FALL a second with nothing.
const ALERT_AT := 0.35
const SIGHT_RISE := 1.4
const SMELL_RISE := 0.25
const FALL := 0.15
const HEAR_SHOT := 1.0
const HEAR_RUN := 0.3
const HEAR_STEP := 0.12
const WATCH_S := 0.7  # how long one think's "watched" holds on the player's HUD
## Sight is a cone: within SEE_DOT of its facing (about 100 degrees each side; behind it, nothing:
## the silent kill's "from behind"). Something it's after or alert to it keeps in the corner of
## its eye a little wider.
const SEE_DOT := -0.2

enum Mode { IDLE, INVESTIGATE, ALERT, CHASE, SEARCH }
const MODE_NAMES := ["idle", "suspicious", "alert", "chasing", "searching"]

var body: Soldier
var kind := "walker"
var decay := 0.0  # (DeadDecay: 0 fresh .. 1 old)
var dormant := false  # (DeadNests: lying up in a nest by day)
var nest_id := ""
var under_ledge := false  # stopped under a man up out of its reach (piling)
var mode := Mode.IDLE
var target: Soldier
var goal := Vector3.INF
var awareness := 0.0
var aware_of: Soldier  # who it's becoming aware of (ALERT), or null
var groaned_at := -100.0
var _path := PackedVector3Array()
var _path_index := 0
var _think := 0.0
var _attack_at := 0.0
var _seen_at := -100.0
var _search_until := 0.0
var _idle_next := 0.0
var _before_alert := Mode.IDLE
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	body = get_parent() as Soldier
	if bool((KINDS.get(kind, KINDS.walker) as Dictionary).get("low", false)):
		body.want_stance = SoldierMovement.Stance.PRONE  # a crawler
	_rng.seed = hash(String(body.name))
	_think = _rng.randf() * THINK_S  # (not every one on the same frame)
	_idle_next = Soldier._now() + _rng.randf_range(1.0, 6.0)


## The brain on `s`, or null.
static func of(s: Node) -> ZombieAI:
	return s.get_node_or_null(^"ZombieAI") as ZombieAI if s else null


## The state's name, for the HUD and the logs ("idle", "suspicious", "alert", "chasing", "searching").
func state_name() -> String:
	return MODE_NAMES[mode]


# --- The climbing rules (call 140) -----------------------------------------------------------------

## Whether one of `kind` climbs (ladders, walls, roofs): none of the dead do. Platforms, ladders
## and roofs are safe from them; a pile at a wall (Sieges) is the only way up.
static func can_climb(_kind: String) -> bool:
	return false


## Whether one of `kind` gets up a ledge or over an obstacle `height_m` high: a step for all, a
## vault to waist height for a runner.
static func can_get_up(kind: String, height_m: float) -> bool:
	return height_m <= STEP_UP_M + 0.01 or (kind == "runner" and height_m <= VAULT_M + 0.01)


## Whether one of `kind` gets through an opening `gap_m` high: standing room for all, a crawler
## under a low gap.
static func can_pass_gap(kind: String, gap_m: float) -> bool:
	return gap_m >= STAND_GAP_M or (kind == "crawler" and gap_m >= CRAWL_GAP_M)


## Whether the man at `at` is up out of this one's reach (on a platform, a roof, a ladder): it
## can't get up there and can't bite him.
func ledge_blocked(at: Vector3) -> bool:
	var dy := at.y - body.global_position.y
	return dy > REACH_UP_M - 0.2 and not can_get_up(kind, dy) and not can_climb(kind)


## The pace it walks (or chases) at now, a share of the run (the kind's, by night, the season,
## the world's "dead" option, its decay).
func pace() -> float:
	var k: Dictionary = KINDS.get(kind, KINDS.walker)
	var night := DayNight.darkness_at(body.global_position) > 0.5 if body else false
	var p := float(k.chase) if mode == Mode.CHASE else float(k.walk)
	if not bool(k.sprint) or mode != Mode.CHASE:
		p *= (NIGHT_WALK_MULT if night else 1.0) * Survival.dead_speed_mult()  # (the "dead" world option)
	return p * Seasons.dead_pace_mult() * DeadDecay.pace_mult(decay)  # (phase D: the seasons; the dead over time: its age)


## Whether this one has no idea anyone's there (the silent kill's "unaware": idle, or looking
## into a sound or a smell, not watching him).
func unaware() -> bool:
	return mode in [Mode.IDLE, Mode.INVESTIGATE, Mode.SEARCH]


## Host: a sound at `pos` this one can hear, `loud` 0..1 (a shot 1, a running man HEAR_RUN, a
## step HEAR_STEP): awareness up by it; unless it's after someone, it goes to look.
func hear(pos: Vector3, loud := HEAR_SHOT) -> void:
	if dormant:
		if loud >= WAKE_LOUD:
			DeadNests.wake(CompoundLevel.current(body), nest_id, pos)  # a shot or a scream: the whole nest
		else:
			awareness = clampf(awareness + loud * DORMANT_HEAR, 0.0, 1.0)
		return
	awareness = clampf(awareness + loud, 0.0, 1.0)
	if mode == Mode.CHASE:
		return
	if mode != Mode.ALERT:
		mode = Mode.INVESTIGATE
	_set_goal(pos)


func _physics_process(delta: float) -> void:
	if body == null or not body.vitals.is_up() or Traps.holds(body):  # (phase D: frozen solid, held by wire or a trap, stunned)
		if body:
			body.move_input = Vector2.ZERO
			body.want_sprint = false
		return
	_think -= delta
	if _think <= 0.0:
		_think = THINK_S
		_decide()
	_steer(delta)


func _decide() -> void:
	var now := Soldier._now()
	var seen := _spot()  # {"who", "score"} or {}
	var who: Soldier = seen.get("who") if not seen.is_empty() else null
	var fed := false
	if who != null:
		awareness = clampf(awareness + float(seen.score) * SIGHT_RISE * THINK_S / maxf(DayNight.spot_x(body.global_position), 0.1), 0.0, 1.0)
		aware_of = who
		fed = true
	if dormant:
		# Lying up in a nest: nothing but the waking (DeadNests.wake: the whole nest at once).
		if awareness >= ALERT_AT and who != null:
			DeadNests.wake(CompoundLevel.current(body), nest_id, who.global_position)
		elif not fed:
			awareness = maxf(awareness - FALL * THINK_S, 0.0)
		if dormant:
			return
	var smelt := _smell()
	if smelt != null and mode != Mode.CHASE:
		awareness = clampf(awareness + SMELL_RISE * THINK_S, 0.0, 1.0)
		if mode in [Mode.IDLE, Mode.SEARCH]:
			mode = Mode.INVESTIGATE
			_set_goal(smelt.global_position)
		fed = true
	if not fed and mode != Mode.CHASE:
		awareness = maxf(awareness - FALL * THINK_S, 0.0)
	if who == null and mode != Mode.CHASE and mode != Mode.ALERT:
		Wildlife.zombie_hunt(self)  # (fauna: animals as prey, carcasses and blood by smell)
	# The states.
	if awareness >= 1.0 and (who != null or is_instance_valid(target)):
		var chase := who if who != null else target
		if target != chase:
			_rally(chase)
		target = chase
		if mode != Mode.CHASE:
			_groan(now)
		mode = Mode.CHASE
		_seen_at = now
		_set_goal(chase.global_position)
	elif mode == Mode.CHASE:
		if not is_instance_valid(target) or not target.vitals.is_up() or now - _seen_at > LOSE_S:
			mode = Mode.SEARCH
			_search_until = now + SEARCH_S
			target = null
			awareness = ALERT_AT
		elif who == target:
			_seen_at = now
	elif awareness >= ALERT_AT and who != null:
		if mode != Mode.ALERT:
			_before_alert = mode
			_groan(now)
		mode = Mode.ALERT
		goal = Vector3.INF  # it stops and watches him
	elif mode == Mode.ALERT:
		if awareness < ALERT_AT or who == null:
			# Lost the sight of him: goes to look where he was.
			mode = Mode.INVESTIGATE
			if is_instance_valid(aware_of):
				_set_goal(aware_of.global_position)
			_search_until = now + SEARCH_S
	# What each state does.
	under_ledge = false
	if mode == Mode.CHASE and is_instance_valid(target):
		_set_goal(target.global_position)
		under_ledge = ledge_blocked(target.global_position) and _flat(target.global_position) <= LEDGE_M
		if under_ledge:
			body.set_meta(&"under_ledge", now)  # (call 140: it can't get up to him: it stops and piles under him)
		if _flat(target.global_position) <= ATTACK_M and now >= _attack_at and absf(target.global_position.y - body.global_position.y) <= REACH_UP_M:
			_attack_at = now + ATTACK_S
			if bool((KINDS.get(kind, KINDS.walker) as Dictionary).get("trip", false)):
				Melee.server_trip(body, target)  # a crawler grabs his legs
			else:
				Melee.server_strike(body, target)
	elif mode in [Mode.INVESTIGATE, Mode.SEARCH]:
		if goal == Vector3.INF or _flat(goal) <= ARRIVE_M:
			if mode == Mode.INVESTIGATE:
				mode = Mode.SEARCH
				_search_until = now + SEARCH_S
			elif now >= _search_until:
				mode = Mode.IDLE
				goal = Vector3.INF
			else:
				_wander()
	elif mode == Mode.IDLE and now >= _idle_next:
		_idle_next = now + _rng.randf_range(4.0, 12.0)
		_wander()
	if mode != Mode.ALERT:
		Sieges.server_at_wall(self)  # (phase D: stuck at a build: chew, pile, climb, vault, squeeze; call 140)
	# The man it's alert to or after knows he's watched (the HUD's eye).
	var watched: Soldier = target if mode == Mode.CHASE else (aware_of if mode == Mode.ALERT else null)
	if is_instance_valid(watched) and not watched.is_ai():
		watched.server_watched(WATCH_S)


## The living non-infected this one sees best now: {"who", "score" 0..1 (how well: distance,
## stance, light, weather)}, or {} for nobody.
func _spot() -> Dictionary:
	var dark := DayNight.darkness_at(body.global_position)
	var reach := minf(lerpf(SIGHT_M, NIGHT_SIGHT_M, clampf(dark, 0.0, 1.0)), DayNight.sight_m(body.global_position))
	var eye := body.global_position + Vector3.UP * 1.6
	var best: Soldier = null
	var best_score := 0.0
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s.faction == INFECTED or not s.vitals.is_up() or s.is_queued_for_deletion():
			continue
		if dormant:
		reach *= DORMANT_SIGHT
	var r := reach * (LOW_SIGHT_MULT if s.movement and (s.movement.is_crouched() or s.movement.is_prone()) else 1.0) * Masking.sight_x(s, dark)
		if is_instance_valid(target) and s == target:
			r *= 1.5  # (one it's after is easier to keep in sight)
		var d := body.global_position.distance_to(s.global_position)
		if d > r:
			continue
		var to := s.global_position - body.global_position
		to.y = 0.0
		var fwd := -body.global_basis.z
		fwd.y = 0.0
		if d > 0.3 and fwd.normalized().dot(to.normalized()) < (SEE_DOT - 0.3 if (s == target or s == aware_of) else SEE_DOT):
			continue  # behind it
		# How well: full within the near third, down to nothing at the edge of its reach.
		var score := clampf(1.0 - (d - r * 0.33) / (r * 0.67), 0.0, 1.0) if d > r * 0.33 else 1.0
		if score <= best_score:
			continue
		if d > ATTACK_M * 2.0 and not Throwables.clear_line(body.get_world_3d(), eye, s.global_position + Vector3.UP * 1.4):
			continue
		best = s
		best_score = score
	return {"who": best, "score": best_score} if best != null else {}


## Someone this one smells now (bleeding, or blood and gore on him: Soldier.smell_strength):
## downwind within SMELL_M, or any way round within SMELL_CALM_M in calm air. Null for nobody.
func _smell() -> Soldier:
	var wind := DayNight.wind()
	var calm := wind.length() < CALM_MPS
	var best: Soldier = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s.faction == INFECTED or not s.vitals.is_up() or s.is_queued_for_deletion():
			continue
		var strength := s.smell_strength() * Masking.smell_x(s)  # (phase D: gore smeared on hides it)
		if strength <= 0.0:
			continue
		var to_me := body.global_position - s.global_position
		to_me.y = 0.0
		var d := to_me.length()
		if calm:
			if d > SMELL_CALM_M * strength:
				continue
		elif d > SMELL_M * strength or wind.normalized().dot(to_me.normalized()) < 0.5:
			continue  # not downwind of him
		if d < best_d:
			best = s
			best_d = d
	return best


## The groan when it turns alert or starts the chase (the audio layer's cue; once in a while).
## A screamer's first is the scream: the zone hears it (SCREAM_M) and the pressure jumps.
func _groan(now: float) -> void:
	if now - groaned_at < 2.0:
		return
	groaned_at = now
	body.set_meta(&"zombie_groan", now)
	var k: Dictionary = KINDS.get(kind, KINDS.walker)
	if bool(k.get("scream", false)) and not screamed:
		screamed = true
		body.set_meta(&"zombie_scream", now)
		Survival.server_noise(body, body.global_position, SCREAM_M, HEAR_SHOT)
		Survival._raise_pressure(CompoundLevel.current(body), body.global_position, SCREAM_PRESSURE)
		SessionLog.note("survival: %s screams" % body.log_name())


## The dead about this one join the chase.
func _rally(who: Soldier) -> void:
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s == body or s.faction != INFECTED or s.global_position.distance_to(body.global_position) > GROUP_M:
			continue
		var other := ZombieAI.of(s)
		if other and other.mode != Mode.CHASE:
			other.target = who
			other.mode = Mode.CHASE
			other.awareness = 1.0
			other._seen_at = Soldier._now()
			other._set_goal(who.global_position)


func _wander() -> void:
	var a := _rng.randf() * TAU
	_set_goal(body.global_position + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(2.0, WANDER_M))


func _set_goal(at: Vector3) -> void:
	if goal != Vector3.INF and goal.distance_to(at) < 1.0 and not _path.is_empty():
		goal = at
		return
	goal = at
	var map := body.get_world_3d().navigation_map
	_path = NavigationServer3D.map_get_path(map, body.global_position, at, true, NAV_LAYERS)  # (never a climb link: call 140)
	_path_index = 0


func _steer(delta: float) -> void:
	if dormant or under_ledge:
		body.move_input = Vector2.ZERO
		body.want_sprint = false
		if under_ledge and is_instance_valid(target):
			_face(target.global_position, delta)
		return
	if mode == Mode.ALERT:
		body.move_input = Vector2.ZERO
		body.want_sprint = false
		if is_instance_valid(aware_of):
			_face(aware_of.global_position, delta)  # the head turns to him: the tell
		return
	if goal == Vector3.INF or _flat(goal) <= (ATTACK_M * 0.8 if mode == Mode.CHASE else ARRIVE_M):
		body.move_input = Vector2.ZERO
		body.want_sprint = false
		if mode == Mode.CHASE and is_instance_valid(target):
			_face(target.global_position, delta)
		return
	while _path_index < _path.size() and _flat(_path[_path_index]) < 0.8:
		_path_index += 1
	var next := _path[_path_index] if _path_index < _path.size() else goal
	var dir := next - body.global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		body.move_input = Vector2.ZERO
		return
	dir = dir.normalized()
	var k: Dictionary = KINDS.get(kind, KINDS.walker)
	_face(body.global_position + dir, delta)
	var local := body.global_basis.inverse() * dir
	body.move_input = Vector2(local.x, local.z) * clampf(pace(), 0.0, 1.0)
	body.want_sprint = bool(k.sprint) and mode == Mode.CHASE and not Seasons.hard_frost()


func _face(at: Vector3, delta: float) -> void:
	var to := at - body.global_position
	if Vector2(to.x, to.z).length() < 0.05:
		return
	body.rotation.y = lerp_angle(body.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-TURN_RATE * delta))


func _flat(p: Vector3) -> float:
	return Vector2(p.x - body.global_position.x, p.z - body.global_position.z).length()
