class_name ProgressWatch
extends RefCounted
## Is a mover getting anywhere? (docs/high_command.md section 9 lift 2 and 4.3: nothing fails
## silently, S0758.) Pure apart from the clock it's fed: the co-op soak's stuck note and the
## stuck-bots wedge tracking (_stuck_note, _track_wedge) as one rule. Feed it the position, the
## goal and the time every tick; read `state` and take a detour bearing when it offers one.
##
## States: "ok" (making headway), "wedged" (no headway for wedged_s: try `detour`), "held_up"
## (none for held_up_s: report it, keep trying detours), "unable" (none for unable_s: give up).
## Contact, a halt or a jump (a ride, a respawn) start the watch over (reset()).

const OK := "ok"
const WEDGED := "wedged"
const HELD_UP := "held_up"
const UNABLE := "unable"
## The soak's wedge rule: 1 m of headway toward the goal clears it; WEDGED_S without it, a
## detour; each detour lasts DETOUR_S, a different side each time (the stuck-bots lesson).
const HEADWAY_M := 1.0
const WEDGED_S := 4.0
const DETOUR_S := 1.5
const DETOUR_DEG: Array[float] = [75.0, -75.0, 135.0, -135.0, 180.0]
## high_command.md 4.3 (Proposed): held up after 30 s, unable after 90 s.
const HELD_UP_S := 30.0
const UNABLE_S := 90.0
## A move between ticks longer than this is a jump (respawn, ride, warp): start over.
const JUMP_M := 5.0
## Within this of the goal it's arrived: no watch.
const ARRIVE_M := 2.0

var wedged_s := WEDGED_S
var held_up_s := HELD_UP_S
var unable_s := UNABLE_S
var state := OK
## The bearing to walk while a detour lasts (flat unit vector), ZERO for none.
var detour := Vector3.ZERO
var detours := 0
## What the last state change was about, for a log line ("[hc] ...").
var note := ""

var _last := Vector3.INF
var _gain := 0.0
var _since := 0.0
var _detour_until := -INF


## Starts over at `now` (contact, a halt, a new goal).
func reset(now: float) -> void:
	_last = Vector3.INF
	_gain = 0.0
	_since = now
	_detour_until = -INF
	detours = 0
	detour = Vector3.ZERO
	state = OK


## One tick: the mover at `pos`, heading for `goal`, at `now`. Returns the state.
func feed(pos: Vector3, goal: Vector3, now: float) -> String:
	var last := _last
	_last = pos
	if last == Vector3.INF or flat(last, pos) > JUMP_M or flat(pos, goal) <= ARRIVE_M:
		_gain = 0.0
		_since = now
		detours = 0
		detour = Vector3.ZERO
		state = OK
		return state
	var ahead := Vector3(goal.x - pos.x, 0.0, goal.z - pos.z)
	if ahead.length() > 0.01:
		_gain += Vector3(pos.x - last.x, 0.0, pos.z - last.z).dot(ahead.normalized())
	if _gain >= HEADWAY_M:
		_gain = 0.0
		_since = now
		detours = 0
		if now >= _detour_until:
			detour = Vector3.ZERO
		if state != OK:
			note = "moving again"
		state = OK
		return state
	var stuck := now - _since
	var was := state
	if stuck >= unable_s:
		state = UNABLE
	elif stuck >= held_up_s:
		state = HELD_UP
	elif stuck >= wedged_s:
		state = WEDGED
	if state != OK and now >= _detour_until:
		var angle := deg_to_rad(DETOUR_DEG[detours % DETOUR_DEG.size()])
		detours += 1
		detour = ahead.normalized().rotated(Vector3.UP, angle) if ahead.length() > 0.01 else Vector3.ZERO
		_detour_until = now + DETOUR_S
	elif now >= _detour_until:
		detour = Vector3.ZERO
	if state != was:
		note = "%s %.0f s at (%.0f, %.0f), %.0f m short" % [state.replace("_", " "), stuck, pos.x, pos.z, flat(pos, goal)]
	return state


## Seconds without headway.
func stuck_for(now: float) -> float:
	return now - _since


## Where to walk now: along the detour while one lasts, else straight for the goal.
func steer(pos: Vector3, goal: Vector3, step_m := 6.0) -> Vector3:
	if detour == Vector3.ZERO:
		return goal
	return pos + detour * step_m


static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
