class_name SquadTrail
extends Node
## The trail the player's side leaves on the ground, for enemy trackers (Captain, 2026-10-18:
## competent AI, and "check out the module thats included in sog prarie fire ... about hunting
## players": inspired by S.O.G. Prairie Fire's trackers, who pick up a team's trail, fire signal
## shots when they find it and follow it until they're dealt with). Host only; one per zone
## ("SquadTrail", ZoneLevel).
##
## Every TICK_S each player and squadmate on foot who has moved STEP_M since their last mark
## leaves one: {"pos", "t", "broken"}. A mark on a road or in water is "broken" (no prints to
## read): a tracker following the trail loses it there. Marks older than KEEP_S go.
## lead(): from a mark, the freshest one within LEAD_M ahead in time, so a tracker follows the
## path the squad walked, turn by turn: a dog-leg (turn hard off the line, loop back beside your
## own trail and watch it) brings the trackers past the squad, as it does for real.
## turn_at(): how hard the trail turns at a mark (degrees), for trackers to go careful there.

const TICK_S := 0.5
const STEP_M := 8.0
const KEEP_S := 900.0
const LEAD_M := 30.0
const ROAD_M := 4.0

## Host: the marks, oldest first.
var marks: Array[Dictionary] = []
var _last := {}  # soldier instance id -> where it last left a mark
var _tick := 0.0


func _init() -> void:
	name = "SquadTrail"


static func of(from: Node) -> SquadTrail:
	var lvl := CompoundLevel.current(from)
	return lvl.get_node_or_null(^"SquadTrail") as SquadTrail if lvl else null


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK_S
	var lvl := get_parent() as CompoundLevel
	if lvl == null:
		return
	var walkers: Array[Soldier] = MapNodes.players(self)
	walkers.append_array(MapNodes.squad_ai(self))
	for s in walkers:
		if s == null or not is_instance_valid(s) or not s.vitals.is_up() or is_instance_valid(s.vehicle):
			continue
		var id := s.get_instance_id()
		var last: Variant = _last.get(id)
		if last is Vector3 and Vector2(s.global_position.x - last.x, s.global_position.z - last.z).length() < STEP_M:
			continue
		_last[id] = s.global_position
		server_mark(s.global_position)
	var cut := Soldier._now() - KEEP_S
	while not marks.is_empty() and float(marks[0].t) < cut:
		marks.pop_front()


## Host: a mark at `pos` now (broken on a road or in water).
func server_mark(pos: Vector3) -> void:
	marks.append({"pos": pos, "t": Soldier._now(), "broken": _no_prints(pos)})


## Whether ground at `pos` holds no prints: a road, or water.
func _no_prints(pos: Vector3) -> bool:
	var lvl := get_parent()
	var terrain: Variant = lvl.get(&"terrain") if lvl else null
	if terrain is ZoneTerrain:
		var t := terrain as ZoneTerrain
		if t.sea_side >= 0 and t.height_at(pos.x, pos.z) < t.sea_level + 0.2:
			return true
	var def: Variant = lvl.get(&"def") if lvl else null
	if def is Dictionary:
		var p := Vector2(pos.x, pos.z)
		for road: Array in (def as Dictionary).get("roads", []):
			var a := Vector2(float(road[0][0]), float(road[0][1]))
			var b := Vector2(float(road[1][0]), float(road[1][1]))
			if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= ROAD_M:
				return true
	return false


## The index of the freshest unbroken mark within `radius` of `pos` no older than `max_age`
## seconds, or -1: where a tracker picks the trail up.
func nearest(pos: Vector3, radius: float, max_age: float) -> int:
	var best := -1
	var cut := Soldier._now() - max_age
	for i in range(marks.size() - 1, -1, -1):
		var m: Dictionary = marks[i]
		if float(m.t) < cut:
			break
		if not bool(m.broken) and Vector2(pos.x - m.pos.x, pos.z - m.pos.z).length() <= radius:
			if best < 0 or float(m.t) > float(marks[best].t):
				best = i
	return best


## From mark `i`, the freshest later mark within LEAD_M of it: the next step along the trail;
## -1 at its end. A broken mark is returned like any other (the tracker loses the trail there).
func lead(i: int) -> int:
	if i < 0 or i >= marks.size():
		return -1
	var from: Vector3 = marks[i].pos
	var best := -1
	for j in range(i + 1, marks.size()):
		var m: Dictionary = marks[j]
		if Vector2(from.x - m.pos.x, from.z - m.pos.z).length() <= LEAD_M:
			best = j
	return best


## How hard the trail turns at mark `i` (degrees, 0 straight on): the way in from the mark before
## it (lead's reverse) against the way out (lead).
func turn_at(i: int) -> float:
	var out_i := lead(i)
	var in_i := -1
	for j in range(i - 1, -1, -1):
		if Vector2(marks[j].pos.x - marks[i].pos.x, marks[j].pos.z - marks[i].pos.z).length() <= LEAD_M:
			in_i = j
			break
	if out_i < 0 or in_i < 0:
		return 0.0
	var a := Vector2(marks[i].pos.x - marks[in_i].pos.x, marks[i].pos.z - marks[in_i].pos.z)
	var b := Vector2(marks[out_i].pos.x - marks[i].pos.x, marks[out_i].pos.z - marks[i].pos.z)
	if a.length() < 0.5 or b.length() < 0.5:
		return 0.0
	return rad_to_deg(absf(a.angle_to(b)))
