class_name FireMission
extends RefCounted
## The sums of a fire mission (FireSupport; data/fire_support.json), pure: the observer's
## corrections ("add 50, left 25"), where the guns stand off the map, how long a round flies, where
## it lands, and danger close. FireSupport (the node) keeps the state; this keeps the numbers.
##
## Corrections are the observer's, along his line to the target (the OT line, as forward observers
## call it): "add" is further from him, "drop" nearer, "left" and "right" across the line as he
## looks at the target. They move where the guns aim by that much, so a correction read off a burst
## ("the round fell 50 short and 25 right: add 50, left 25") brings the next one onto the target.
## Learning from how real call-for-fire works (and how Arma's artillery computer is used), not a copy
## of either.

const DATA_PATH := "res://data/fire_support.json"
const G := 9.81
## Words a correction may use, and the way each moves the aim (x: right, y: add).
const WORDS := {"add": Vector2(0, 1), "drop": Vector2(0, -1), "left": Vector2(-1, 0), "right": Vector2(1, 0),
	"a": Vector2(0, 1), "d": Vector2(0, -1), "l": Vector2(-1, 0), "r": Vector2(1, 0)}
## The biggest single correction taken (m): more is a new mission.
const MAX_CORRECTION_M := 1000.0

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {}
		if _data.is_empty():
			push_error("FireMission: cannot read %s" % DATA_PATH)
	return _data


## The firing units (mortar, artillery).
static func units() -> Array:
	return (data().get("units", {}) as Dictionary).keys()


static func unit(id: String) -> Dictionary:
	return (data().get("units", {}) as Dictionary).get(id, {})


static func uav() -> Dictionary:
	return data().get("uav", {})


## "add 50, left 25" (any order, commas or not; "add50", "l 25" too) as {"move": Vector2 (x right,
## y add, metres)} or {"why": what's wrong}. Empty or "repeat": no move.
static func parse(text: String) -> Dictionary:
	var words := text.to_lower().replace(",", " ").replace(";", " ").strip_edges()
	var move := Vector2.ZERO
	if words == "" or words == "repeat":
		return {"move": move}
	# Split "add50" into "add 50".
	var spaced := ""
	for i in words.length():
		var ch := words[i]
		if i > 0 and ch.is_valid_int() != words[i - 1].is_valid_int() and words[i - 1] != " " and ch != " ":
			spaced += " "
		spaced += ch
	var tokens := Array(spaced.split(" ", false))
	tokens.erase("repeat")
	if tokens.size() % 2 != 0:
		return {"why": "Say a direction and metres: \"add 50, left 25\""}
	var said := {}
	for i in range(0, tokens.size(), 2):
		var w := String(tokens[i])
		var n := String(tokens[i + 1])
		if not WORDS.has(w) or not n.is_valid_int():
			return {"why": "\"%s %s\" isn't a correction (add, drop, left, right and metres)" % [w, n]}
		var axis := "range" if WORDS[w].x == 0.0 else "line"
		if said.has(axis):
			return {"why": "One range and one line correction at a time"}
		said[axis] = true
		var m := float(n.to_int())
		if m > MAX_CORRECTION_M:
			return {"why": "More than %d m: call a new mission" % int(MAX_CORRECTION_M)}
		move += (WORDS[w] as Vector2) * m
	return {"move": move}


## The correction `move` (x right, y add) applied to `aim`, along the line from `observer`.
static func corrected(aim: Vector3, observer: Vector3, move: Vector2) -> Vector3:
	var ot := ot_dir(observer, aim)
	var right := Vector3(-ot.z, 0.0, ot.x)
	return aim + ot * move.y + right * move.x


## The flat way from `observer` to `target` (north if they're on top of each other).
static func ot_dir(observer: Vector3, target: Vector3) -> Vector3:
	var d := Vector3(target.x - observer.x, 0.0, target.z - observer.z)
	return d.normalized() if d.length() > 0.5 else Vector3.FORWARD


## The OT line's bearing (degrees from north, the map's up: -z).
static func bearing(observer: Vector3, target: Vector3) -> float:
	var d := ot_dir(observer, target)
	return fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)


## Where unit `u` fires on `target` from: `off_m` past the edge of `area` (x, z), along the way from
## `target` toward `toward` (the side the supports come from), so the guns are off the map.
static func gun_point(area: Rect2, target: Vector3, toward: Vector3, off_m: float) -> Vector3:
	var dir := Vector2(toward.x - target.x, toward.z - target.z)
	if dir.length() < 1.0:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var p := Vector2(target.x, target.z)
	var t := INF  # to the area's edge along dir
	if absf(dir.x) > 0.0001:
		t = minf(t, ((area.end.x if dir.x > 0.0 else area.position.x) - p.x) / dir.x)
	if absf(dir.y) > 0.0001:
		t = minf(t, ((area.end.y if dir.y > 0.0 else area.position.y) - p.y) / dir.y)
	var out := p + dir * (maxf(t, 0.0) + off_m)
	return Vector3(out.x, 0.0, out.y)


## Flat distance (m).
static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## A round's time of flight (s) over `range_m` at `mils` elevation (6400 to the circle), no drag.
static func flight_s(range_m: float, mils: float) -> float:
	var theta := mils / 6400.0 * TAU
	var s2 := sin(2.0 * theta)
	if s2 <= 0.001 or range_m <= 0.0:
		return 0.0
	return 2.0 * sin(theta) * sqrt(range_m / (G * s2))


## The radius (m) unit `u`'s rounds land in round its aim at `range_m`.
static func dispersion_m(u: Dictionary, range_m: float) -> float:
	return float(u.get("dispersion_m", 10.0)) + float(u.get("dispersion_per_km", 4.0)) * range_m / 1000.0


## A point uniformly in a disc of `radius` round `centre` (flat).
static func in_disc(rng: RandomNumberGenerator, centre: Vector3, radius: float) -> Vector3:
	var a := rng.randf() * TAU
	var r := radius * sqrt(rng.randf())
	return centre + Vector3(cos(a), 0.0, sin(a)) * r


## A mission's starting error: `lo` to `hi` metres any way, `mult` of it.
static func bias(rng: RandomNumberGenerator, lo: float, hi: float, mult := 1.0) -> Vector3:
	var a := rng.randf() * TAU
	return Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(lo, hi) * mult


## The friendlies (`people`: positions) within `radius` of `aim`.
static func danger_close(aim: Vector3, people: Array, radius: float) -> int:
	var n := 0
	for p: Vector3 in people:
		if flat(p, aim) <= radius:
			n += 1
	return n


## A grid reference for `p` on `area` (the map's own, MapGrid).
static func grid(p: Vector3, area: Rect2) -> String:
	return MapGrid.grid_ref(Vector2(p.x, p.z), area)
