class_name Reinforcements
extends Node
## The reinforcement timer (repo, locked): it runs from the start of each contract, and the
## hostile response escalates the longer the squad stays. Waves of hostile fire teams walk
## in from beyond the map's edges, out of sight of the players, and hunt toward where the
## players are; each wave comes sooner than the last and is bigger, up to a cap. There is no
## timer on screen: players read it from the activity.
##
## Host only (the soldiers it spawns replicate like any AI). The waves use the level's own
## spawning (spawn_soldier, the hostile loadout and SquadAI); each wave is a hostile Squad of
## its own whose patrol route leads to the players.
##
## Tuning (all proposed), overridable per contract (Briefing contract "reinforcements"):
##   "first_wave_s": the first wave arrives this long after the start;
##   "first_gap_s", "gap_shrink", "min_gap_s": the next waves come gap_k = first_gap_s *
##   gap_shrink^k apart, never closer than min_gap_s;
##   "first_pairs", "pairs_every", "max_pairs": a wave is first_pairs buddy pairs, one more
##   pair every pairs_every waves, at most max_pairs;
##   "max_alive": no wave grows living hostiles past this (a wave that would is cut down);
##   "offmap_m": how far beyond the map's edge they appear (a level with its own
##   reinforcement_edge(players) picks the spot instead: a world-scale zone has no ground
##   beyond its edge);
##   "combat", "combat_step", "combat_max": the waves' skill, rising by a step a wave (a
##   contract sets it from its true quality: Contracts.reinforcement_tuning).
##
## Hot zones (4B part 3): `driven`, the timer sends nothing; the zone's EnemyResponse launches
## each wave from a QRF base (server_send) when the alert reaches ENGAGED, and the waves head
## for `aim` (the enemy's last known position), not for where the players really are.
## max_alive then counts only the waves' own living soldiers (a hot zone's garrisons and
## patrols are many).

## Host: a wave arrived (`index` from 0, the soldiers spawned).
signal wave_spawned(index: int, soldiers: Array)

const DEFAULTS := {
	"first_wave_s": 300.0,
	"first_gap_s": 240.0,
	"gap_shrink": 0.8,
	"min_gap_s": 90.0,
	"first_pairs": 1,
	"pairs_every": 2,
	"max_pairs": 4,
	"max_alive": 20,
	"offmap_m": 15.0,
	"combat": 0.4,
	"combat_step": 0.03,
	"combat_max": 0.65,
}
## Hostile kit when the level has none of its own (CompoundLevel.HOSTILE_LOADOUT).
const LOADOUT := ["plate_carrier_light", "plate_pe_l3", "helmet_bump", "assault_pack", "akm",
	"mag_762x39", "mag_762x39", "mag_762x39", "mag_762x39", "ifak", "frag_grenade"]
## Which hostile faction this zone's reinforcement waves field (CLAUDE.md squad-roles-pmc
## bundle): the level's own hostile mix by default, or CompoundLevel.PMC_FACTION for the
## Vantage Group rival PMC. Mirrors EnemyResponse.enemy_faction for the same reason (a hot
## zone's QRF waves go through EnemyResponse instead of here; a contract zone's through this).
var enemy_faction: StringName = &"black_ridge"
## See EnemyResponse.difficulty: the live contract's true_rating, for Vantage's exo gear.
var difficulty: int = 1
## How many spots along the map's edges are tried for a wave; the one furthest from every
## player wins.
const EDGE_TRIES := 24
## Each wave's route is pointed at the players again this often (seconds).
const RETARGET_S := 30.0
const PAIR_SPACING_M := 1.6
## A spawn or route point this close to the navigation mesh is moved onto it.
const NAV_SNAP_M := 2.0

var running := false
## Seconds since the timer started (the contract's clock).
var elapsed := 0.0
## Waves sent so far.
var waves_sent := 0
var params: Dictionary = DEFAULTS.duplicate()
## Every wave: {"index", "at_s", "size", "edge" (Vector3 where it came in), "squad", "soldiers"}.
var waves: Array[Dictionary] = []
## Hot zones: waves come only from server_send, never on the timer.
var driven := false
## Where waves head (returns a Vector3, or Vector3.INF for "stay put"); unset: the players.
var aim := Callable()
## Driven waves: how long after it set out (by `clock`) a wave keeps being pointed at `aim`;
## after that it keeps its last route (holds round the last spot it was sent to). INF: always.
var hunt_s := INF
## The clock hunt_s runs on (returns seconds); unset: `elapsed`.
var clock := Callable()

var _next_at := 0.0
var _retarget := 0.0


func _init() -> void:
	name = "Reinforcements"


## Host only. Starts the timer from zero with `tuning` over DEFAULTS.
func server_start(tuning: Dictionary = {}) -> void:
	if not multiplayer.is_server():
		return
	server_stop()
	params = DEFAULTS.duplicate()
	params.merge(tuning, true)
	running = true
	elapsed = 0.0
	waves_sent = 0
	waves = []
	_next_at = wave_time(0, params)


## Host only. Stops the timer (extraction, contract over). Soldiers already in stay.
func server_stop() -> void:
	running = false


## When wave `index` (from 0) arrives, in seconds from the start, for `p` (DEFAULTS plus overrides).
static func wave_time(index: int, p: Dictionary = DEFAULTS) -> float:
	var t := float(p.get("first_wave_s", DEFAULTS.first_wave_s))
	for k in index:
		t += gap_after(k, p)
	return t


## Seconds between wave `index` and the next.
static func gap_after(index: int, p: Dictionary = DEFAULTS) -> float:
	var first := float(p.get("first_gap_s", DEFAULTS.first_gap_s))
	var shrink := float(p.get("gap_shrink", DEFAULTS.gap_shrink))
	return maxf(float(p.get("min_gap_s", DEFAULTS.min_gap_s)), first * pow(shrink, index))


## Soldiers in wave `index` before the max_alive cap: buddy pairs, growing.
static func wave_size(index: int, p: Dictionary = DEFAULTS) -> int:
	var pairs := int(p.get("first_pairs", DEFAULTS.first_pairs)) + floori(index / float(maxi(int(p.get("pairs_every", DEFAULTS.pairs_every)), 1)))
	return 2 * mini(pairs, int(p.get("max_pairs", DEFAULTS.max_pairs)))


func _physics_process(delta: float) -> void:
	if (running or driven) and multiplayer.is_server():
		server_advance(delta)


## Host only. Runs the clock forward `seconds` (every physics frame; tests jump it), sending
## each wave that falls due (not when `driven`) and pointing the waves at their aim now and then.
func server_advance(seconds: float) -> void:
	if not running and not driven:
		return
	if running:
		elapsed += seconds
	while running and not driven and elapsed >= _next_at:
		_send_wave(waves_sent)
		waves_sent += 1
		_next_at = wave_time(waves_sent, params)
	_retarget -= seconds
	if _retarget <= 0.0:
		_retarget = RETARGET_S
		_retarget_waves()


## Living hostile soldiers in the session.
func hostiles_alive() -> int:
	var count := 0
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.faction == &"hostile" and not s.is_queued_for_deletion() and not s.vitals.is_dead():
			count += 1
	return count


## Living soldiers the max_alive cap counts: every hostile, or (driven) the waves' own.
func capped_alive() -> int:
	if not driven:
		return hostiles_alive()
	var count := 0
	for wave: Dictionary in waves:
		for s: Variant in wave.soldiers:
			if is_instance_valid(s) and not (s as Soldier).vitals.is_dead():
				count += 1
	return count


## Host only (hot zones: EnemyResponse). Sends the next wave now from `origin` (a QRF base's
## gate), `extra_pairs` buddy pairs bigger than its turn; returns its soldiers.
## `target`: an objective the wave assaults whatever `aim` says (MissionScenario's hold-the-line
## and rescue waves; Captain, 2026-10-17: "enemies dont attack on hold compound objs": EnemyResponse
## drives every zone's waves at the last known position, none before the squad is reported).
func server_send(origin: Vector3, extra_pairs := 0, cap := -1, target := Vector3.INF) -> Array:
	if not multiplayer.is_server():
		return []
	var index := waves_sent
	waves_sent += 1
	_send_wave(index, origin, extra_pairs, cap, target)
	return waves.back().soldiers if not waves.is_empty() and int(waves.back().index) == index else []


func _send_wave(index: int, origin := Vector3.INF, extra_pairs := 0, cap := -1, target := Vector3.INF) -> void:
	var level := MapNodes.level_of(self)
	if level == null or not level.has_method(&"spawn_soldier"):
		return
	var size := mini(wave_size(index, params) + 2 * extra_pairs, maxi(int(params.max_alive) - capped_alive(), 0))
	if cap >= 0:
		size = mini(size, cap)  # the caller's budget (EnemyResponse.SPAWN_BUDGET)
	size -= size % 2  # whole buddy pairs
	var edge := origin if origin.is_finite() else edge_point(level)
	var record := {"index": index, "at_s": elapsed, "sent_at": _now(), "size": size, "edge": edge, "squad": null, "soldiers": [], "target": target}
	waves.append(record)
	if size <= 0:
		wave_spawned.emit(index, [])
		return
	var squad := Squad.new()
	squad.name = "Wave%d" % (index + 1)
	squad.faction = &"hostile"
	add_child(squad)
	record.squad = squad
	var loadout: Variant = level.get(&"HOSTILE_LOADOUT")
	var soldiers: Array = []
	var across := (Vector3(edge.x, 0, edge.z) - _players_centre(level)).normalized().cross(Vector3.UP)
	for i in size:
		var offset := across * PAIR_SPACING_M * (i - (size - 1) / 2.0)
		var pmc := enemy_faction == CompoundLevel.PMC_FACTION
		var kit: Array = (CompoundLevel.rival_pmc_loadout(index + i, difficulty) if pmc else CompoundLevel.hostile_loadout(index + i)) if loadout is Array and loadout == CompoundLevel.HOSTILE_LOADOUT else (loadout if loadout is Array else LOADOUT)
		var s: Soldier = level.call(&"spawn_soldier", {"name": "R%d_%d" % [index + 1, i + 1], "faction": "hostile",
			"variant": "black" if pmc else "urban", "pos": _on_ground(edge + offset), "loadout": kit,
			"combat": minf(float(params.combat) + float(params.combat_step) * index, float(params.combat_max)), "discipline": 0.5, "guard": false, "mode": "aware",
			"role": CompoundLevel.rival_pmc_role(index + i) if pmc else CompoundLevel.hostile_role(index + i),
			"exo": CompoundLevel.rival_pmc_exo_at(index + i, difficulty) if pmc else ""})
		if s == null:
			continue
		var brain := SquadAI.of(s)
		if brain:
			brain.squad = squad
		soldiers.append(s)
	for i in range(0, soldiers.size() - 1, 2):
		soldiers[i].buddy = soldiers[i + 1]
		soldiers[i + 1].buddy = soldiers[i]
	record.soldiers = soldiers
	_route(squad, level, edge, target)
	print("[reinforcements] wave %d: %d hostiles from (%.0f, %.0f) at %.0f s" % [index + 1, soldiers.size(), edge.x, edge.z, elapsed])
	wave_spawned.emit(index, soldiers)


## A spot beyond the map's edge (offmap_m out), out of the players' way: of EDGE_TRIES spots
## around the edge, the one furthest from the nearest player.
func edge_point(level: Node) -> Vector3:
	if level.has_method(&"reinforcement_edge"):
		var at: Array[Vector2] = []
		for p: Soldier in MapNodes.players(self):
			at.append(Vector2(p.global_position.x, p.global_position.z))
		return _on_ground(level.call(&"reinforcement_edge", at))
	var area: Rect2 = level.call(&"map_area")
	var out := float(params.get("offmap_m", DEFAULTS.offmap_m))
	var grown := area.grow(out)
	var players: Array[Vector2] = []
	for p: Soldier in MapNodes.players(self):
		players.append(Vector2(p.global_position.x, p.global_position.z))
	var best := Vector2.ZERO
	var best_d := -1.0
	for i in EDGE_TRIES:
		var spot := _perimeter_point(grown, (float(i) + randf()) / EDGE_TRIES)
		var d := INF
		for p in players:
			d = minf(d, spot.distance_to(p))
		if d > best_d:
			best_d = d
			best = spot
	return _on_ground(Vector3(best.x, 0.0, best.y))


## The point a share `t` (0..1) of the way round a rectangle's edge.
static func _perimeter_point(rect: Rect2, t: float) -> Vector2:
	var perimeter := 2.0 * (rect.size.x + rect.size.y)
	var d := fposmod(t, 1.0) * perimeter
	if d < rect.size.x:
		return Vector2(rect.position.x + d, rect.position.y)
	d -= rect.size.x
	if d < rect.size.y:
		return Vector2(rect.end.x, rect.position.y + d)
	d -= rect.size.y
	if d < rect.size.x:
		return Vector2(rect.end.x - d, rect.end.y)
	d -= rect.size.x
	return Vector2(rect.position.x, rect.end.y - d)


## A wave's patrol leads from where it came in to its aim (the players, or in a hot zone the
## last known position) and round it.
func _route(squad: Squad, level: Node, from: Vector3, target := Vector3.INF) -> void:
	var centre := _players_centre(level)
	if target.is_finite():
		centre = target  # an objective's wave: it goes for the objective
	elif aim.is_valid():
		centre = aim.call()
		if not centre.is_finite():
			return  # nothing to go on: they keep the route they have
	var route: Array[Vector3] = []
	var half := centre.lerp(from, 0.5)
	route.append(_on_ground(half))
	route.append(_on_ground(centre))
	for k in 3:
		var a := TAU * (k / 3.0) + randf() * 0.5
		route.append(_on_ground(centre + Vector3(cos(a), 0.0, sin(a)) * 12.0))
	squad.patrol = route


## Host: `wave` waits at `point` (a push's rally point, EnemyResponse) instead of heading in;
## its retargeting stops until server_release.
func server_hold_at(wave: Dictionary, point: Vector3) -> void:
	wave["rally"] = point
	var squad := wave.squad as Squad
	if is_instance_valid(squad):
		var route: Array[Vector3] = [_on_ground(point)]
		squad.patrol = route


## Host: a wave held at a rally point goes in (to where it would have been sent now).
func server_release(wave: Dictionary) -> void:
	if not wave.has("rally"):
		return
	var at: Vector3 = wave.rally
	wave.erase("rally")
	var level := MapNodes.level_of(self)
	var squad := wave.squad as Squad
	if level and is_instance_valid(squad):
		_route(squad, level, at, wave.get("target", Vector3.INF))


func _retarget_waves() -> void:
	var level := MapNodes.level_of(self)
	if level == null:
		return
	var t := _now()
	for wave: Dictionary in waves:
		var squad := wave.squad as Squad
		var target: Vector3 = wave.get("target", Vector3.INF)
		if target.is_finite():
			continue  # an objective's wave keeps going for it
		if wave.has("rally"):
			continue  # waiting at a rally point for the rest of a push (EnemyResponse, server_release)
		if t - float(wave.get("sent_at", t)) > hunt_s:
			continue  # done hunting: holds round the last spot it was sent to
		var living: Array = wave.soldiers.filter(func(s: Variant) -> bool:
			return is_instance_valid(s) and not (s as Soldier).vitals.is_dead())
		if is_instance_valid(squad) and not living.is_empty():
			_route(squad, level, (living[0] as Soldier).global_position)


func _players_centre(level: Node) -> Vector3:
	var players := MapNodes.players(self)
	if players.is_empty():
		var area: Rect2 = level.call(&"map_area")
		return Vector3(area.get_center().x, 0.0, area.get_center().y)
	var sum := Vector3.ZERO
	for p in players:
		sum += p.global_position
	return sum / players.size()


## On the ground at `pos`, moved onto the navigation mesh if it's right by it. Beyond the
## mesh (off the map's edge, where waves come in) it stays put: the AI's path starts at the
## nearest point of the mesh and they walk onto it.
func _on_ground(pos: Vector3) -> Vector3:
	var at := Briefing.ground_point(self, Vector2(pos.x, pos.z))
	var nav_map := get_viewport().find_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(nav_map) > 0:
		var snapped := NavigationServer3D.map_get_closest_point(nav_map, at)
		if Vector2(snapped.x - at.x, snapped.z - at.z).length() < NAV_SNAP_M:
			return snapped + Vector3.UP * 0.1
	return at


## The clock hunt_s runs on: `clock` if set (a hot zone's Alert clock), else `elapsed`.
func _now() -> float:
	return float(clock.call()) if clock.is_valid() else elapsed
