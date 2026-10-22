class_name AiLod
extends RefCounted
## AI level of detail (perf pass, Captain 2026-10-22: "we definitely need more performance
## fixes"; docs/performance.md): an AI soldier far from every player and out of the fight thinks,
## scans for enemies and re-plans its path less often. Near a player (FULL_M), in contact, with a
## target, or busy with a casualty it runs at the full rate, so nothing a player is near changes.
## Between FULL_M and DynamicSim's sleep (DynamicSim.SLEEP_M) it steps down by TIERS: a patrol
## 400 m off notices the squad within a second or so of when it would have (awareness still builds
## per second of sight, SquadAI._scan_dt), walks the same route and keeps its formation.
##
## SquadAI asks for its tier every REFRESH_S (mult); the player positions are gathered once per
## physics frame for all of them. All numbers Proposed.

## Full rate within this of a player (m).
const FULL_M := 120.0
## [past this distance (m), the rate is divided by this]; the last that fits wins.
const TIERS := [[120.0, 2], [250.0, 3], [400.0, 4]]
## How often a soldier's tier is looked at again (s).
const REFRESH_S := 1.0

## Off: every AI at the full rate (tests that time the AI's reactions to the frame).
static var enabled := true

static var _frame := -1
static var _players := PackedVector3Array()
static var _tree_id := 0


## The rate divider for `body` (1: full rate) by its distance to the nearest player.
static func mult(body: Node3D) -> int:
	if not enabled or body == null or not body.is_inside_tree():
		return 1
	var d := nearest_player_m(body)
	var m := 1
	for t: Array in TIERS:
		if d > float(t[0]):
			m = int(t[1])
	return m


## Metres from `body` to the nearest player (INF with none).
static func nearest_player_m(body: Node3D) -> float:
	_gather(body)
	var p := body.global_position
	var best := INF
	for q in _players:
		best = minf(best, p.distance_squared_to(q))
	return sqrt(best) if best < INF else INF


## The players' positions, once a physics frame (per tree).
static func _gather(from: Node) -> void:
	var tree := from.get_tree()
	var frame := Engine.get_physics_frames()
	if frame == _frame and tree.get_instance_id() == _tree_id:
		return
	_frame = frame
	_tree_id = tree.get_instance_id()
	_players.clear()
	var level := CompoundLevel.current(from)
	if level == null or level.players == null:
		return
	for n in level.players.get_children():
		var s := n as Node3D
		if s and not s.is_queued_for_deletion():
			_players.append(s.global_position)
