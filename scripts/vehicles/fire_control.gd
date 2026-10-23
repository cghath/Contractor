class_name FireControl
extends RefCounted
## The fire control computer's sums (combined arms A4, cg_brief queue item 2.3;
## docs/combined_arms.md 2.7.4), pure and static: VehicleGunnery calls them on a lase, tests call
## them straight.
##
## - The ballistic table: one flight per round, flown level from the muzzle with ShellFlight's own
##   steps (ShellFlight.flight_to's integrator), time of flight and drop kept every TABLE_STEP_M,
##   built the first time a round is asked for and kept.
## - The solution: the lased range along the sight's line, the lead (the sight's turn rate in the
##   world over the last LEAD_TRACK_S, times the time of flight; tracked for less, the lead's
##   error grows linearly), the point that makes, and the gun's line from the muzzle to it held
##   over for the drop. The sight and the muzzle aren't in one place, so the parallax comes out
##   of the same sum. No wind, temperature or cant (2.7.4; call 22).
## - Errors, each from the lase's seed (the same on a replay): the laser's +-lrf_err_m, the
##   solution's err_mil (x3 with the fire control damaged), the lead's share.
## - The aux sight's stadia: how many mils over the target to hold for a range.
## Every number is Proposed.

## The table's spacing (m) and how far it goes.
const TABLE_STEP_M := 50.0
const TABLE_MAX_M := 8000.0
const TABLE_DT := 1.0 / 60.0
## Lead: tracked this long (s) or more, the lead's error is LEAD_ERR of it; at none, LEAD_ERR +
## LEAD_ERR_SHORT (2.7.4's LEAD_TRACK_S: "tracking for under 1 s scales the lead error up linearly").
const LEAD_TRACK_S := 1.0
const LEAD_ERR := 0.05
const LEAD_ERR_SHORT := 0.6
## A NATO mil in radians.
const MIL := TAU / 6400.0
## The stadia marks on the aux sight (m).
const STADIA_M: Array[float] = [500.0, 1000.0, 1500.0, 2000.0, 2500.0, 3000.0]

static var _tables := {}  # shell id -> PackedFloat32Array [time, drop] per TABLE_STEP_M (index 0 at 0 m)


## The time of flight (s) and drop (m below the bore's line, fired level) of round `shell_id` at
## `range_m`, from its table: {"time", "drop"}.
static func at(shell_id: StringName, range_m: float) -> Dictionary:
	var t := table(shell_id)
	var n := t.size() / 2
	if n < 2:
		return {"time": 0.0, "drop": 0.0}
	var f := clampf(range_m, 0.0, TABLE_STEP_M * float(n - 1)) / TABLE_STEP_M
	var i := mini(floori(f), n - 2)
	var w := f - float(i)
	return {"time": lerpf(t[i * 2], t[i * 2 + 2], w), "drop": lerpf(t[i * 2 + 1], t[i * 2 + 3], w)}


## Round `shell_id`'s table (built once): [time, drop] every TABLE_STEP_M out to where it falls
## below its speed or TABLE_MAX_M (2.7.4: "ShellFlight builds a drop and time-of-flight table per
## round when data loads": here on first use, the same flight).
static func table(shell_id: StringName) -> PackedFloat32Array:
	if _tables.has(shell_id):
		return _tables[shell_id]
	var row := Shells.shell(shell_id)
	var out := PackedFloat32Array([0.0, 0.0])
	if not row.is_empty():
		var k := float(row.get("drag", 0.0))
		var vel := Vector3.FORWARD * float(row.get("muzzle_mps", 1000.0))
		var pos := Vector3.ZERO
		var t := 0.0
		var next := TABLE_STEP_M
		while next <= TABLE_MAX_M and t < ShellFlight.MAX_S:
			var v1 := vel + (ShellFlight.GRAVITY - vel * vel.length() * k) * TABLE_DT
			var to := pos + (vel + v1) * 0.5 * TABLE_DT
			while -to.z >= next and next <= TABLE_MAX_M:
				var f := (next + pos.z) / maxf(pos.z - to.z, 0.0001)
				out.append(t + TABLE_DT * f)
				out.append(-lerpf(pos.y, to.y, f))
				next += TABLE_STEP_M
			pos = to
			vel = v1
			t += TABLE_DT
	_tables[shell_id] = out
	return out


## The furthest range round `shell_id`'s table reaches (m).
static func reach_m(shell_id: StringName) -> float:
	return TABLE_STEP_M * float(table(shell_id).size() / 2 - 1)


## The gun's line (world) for a round of `shell_id` from `muzzle` to land on what the sight at
## `sight_from` looking along `sight_dir` (world) sees at `range_m`, leading it by `rate` (the
## sight's turn in the world, rad/s: x yaw left positive, y pitch up positive) times the time of
## flight. `own_velocity`: the firing vehicle's (the round carries it). Returns {"dir", "point" (the
## aimed-at point before the hold-over), "time", "drop", "lead" (Vector2 rad)}.
static func solve(shell_id: StringName, sight_from: Vector3, sight_dir: Vector3, range_m: float, rate: Vector2, muzzle: Vector3,
		own_velocity := Vector3.ZERO) -> Dictionary:
	var d := sight_dir.normalized()
	var first := at(shell_id, range_m)
	var lead := rate * float(first.time)
	var led := turn(d, lead)
	var point := sight_from + led * range_m
	# The round carries the vehicle's speed; the tracked rate already holds the vehicle's own
	# motion (the target drifts across the sight as the tank drives), so only the part along the
	# line is left: it shortens or lengthens the flight a little.
	var to := point - muzzle
	var dist := to.length()
	var along := own_velocity.dot(to / maxf(dist, 0.001))
	var shell_v := float(Shells.shell(shell_id).get("muzzle_mps", 1000.0))
	var eff := dist * shell_v / maxf(shell_v + along, 1.0)
	var fl := at(shell_id, eff)
	var aim := point + Vector3.UP * float(fl.drop)
	return {"dir": (aim - muzzle).normalized(), "point": point, "time": float(fl.time), "drop": float(fl.drop), "lead": lead}


## `dir` turned by `angles` (yaw about the world's up, left positive; then pitch, up positive).
static func turn(dir: Vector3, angles: Vector2) -> Vector3:
	var yaw := atan2(-dir.x, -dir.z) + angles.x
	var pitch := asin(clampf(dir.y, -1.0, 1.0)) + angles.y
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD


## The world (yaw, pitch) of a direction (yaw left positive, as VehicleTurret.angles).
static func angles_of(dir: Vector3) -> Vector2:
	return VehicleTurret.angles(dir)


## The lead's error share for `tracked_s` seconds of tracking.
static func lead_error(tracked_s: float) -> float:
	return LEAD_ERR + LEAD_ERR_SHORT * clampf(1.0 - tracked_s / LEAD_TRACK_S, 0.0, 1.0)


## A uniform roll in -1..1 from `seed` and `salt` (ArmourModel.roll's hash: deterministic).
static func roll(seed: int, salt: int) -> float:
	return ArmourModel.roll(seed, salt) * 2.0 - 1.0


## The aux sight's hold-over for round `shell_id` at `range_m` (mils over the target): its drop
## over the range, the sight bore-sighted to the gun.
static func stadia_mil(shell_id: StringName, range_m: float) -> float:
	if range_m <= 0.0:
		return 0.0
	return atan(float(at(shell_id, range_m).drop) / range_m) / MIL
