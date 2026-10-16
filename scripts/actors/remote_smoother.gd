class_name RemoteSmoother
extends RefCounted
## Smooths another player's body between the position updates their machine sends. Each
## update (the Sync synchronizer's) is a snapshot stamped with when it arrived; the model is
## drawn a short delay behind the newest, between the two snapshots around that time, so a
## sender whose updates come in bursts (a slow machine, a lossy or relayed link such as a
## ZeroTier relay) walks instead of teleporting from one update to the next (Captain,
## 2026-10-15, v0.4.10 over ZeroTier: "when my buddy walks around on my end he teleports").
##
## The delay follows how far apart the updates arrive: about two intervals plus their jitter,
## never under MIN_DELAY_S or over MAX_DELAY_S. Past the newest snapshot it carries on along
## the last velocity for up to EXTRAPOLATE_S, then holds. A jump over SNAP_M (a respawn, a
## seat, a level switch) starts afresh at the new spot instead of sliding there.

const MIN_DELAY_S := 0.03
const MAX_DELAY_S := 0.25
const EXTRAPOLATE_S := 0.1
const SNAP_M := 3.0
## Snapshots kept (enough to cover MAX_DELAY_S at the slowest useful rate).
const KEEP := 16
## How quickly the interval and jitter averages follow new updates (0..1 per update).
const EMA := 0.15

## Each: {t (seconds), pos (Vector3), yaw (radians)}, oldest first.
var _snaps: Array[Dictionary] = []
var _interval := 1.0 / 30.0
var _jitter := 0.0


## Forgets every snapshot: the next push starts afresh.
func reset() -> void:
	_snaps.clear()


func has_data() -> bool:
	return not _snaps.is_empty()


## When the newest snapshot arrived (seconds), or -INF with none.
func newest_time() -> float:
	return float(_snaps.back().t) if not _snaps.is_empty() else -INF


## The render delay now (seconds behind the newest snapshot's arrival).
func delay() -> float:
	return clampf(2.0 * _interval + 2.0 * _jitter, MIN_DELAY_S, MAX_DELAY_S)


## An update arrived at `now`: the body at `pos`, facing `yaw`.
func push(pos: Vector3, yaw: float, now: float) -> void:
	if not _snaps.is_empty():
		var last: Dictionary = _snaps.back()
		if (pos - (last.pos as Vector3)).length() > SNAP_M:
			_snaps.clear()
		else:
			var gap := now - float(last.t)
			if gap <= 0.0:
				_snaps[-1] = {"t": last.t, "pos": pos, "yaw": yaw}  # same frame: the newer wins
				return
			_jitter = lerpf(_jitter, absf(gap - _interval), EMA)
			_interval = lerpf(_interval, gap, EMA)
	_snaps.append({"t": now, "pos": pos, "yaw": yaw})
	while _snaps.size() > KEEP:
		_snaps.pop_front()


## Where to draw the body at `now`: {pos, yaw}. Call has_data first.
func sample(now: float) -> Dictionary:
	var at := now - delay()
	var first: Dictionary = _snaps[0]
	if at <= float(first.t) or _snaps.size() == 1:
		return {"pos": first.pos, "yaw": first.yaw}
	for i in range(_snaps.size() - 1, 0, -1):
		var a: Dictionary = _snaps[i - 1]
		var b: Dictionary = _snaps[i]
		if at >= float(a.t) and at <= float(b.t):
			var w := (at - float(a.t)) / maxf(float(b.t) - float(a.t), 0.0001)
			return {"pos": (a.pos as Vector3).lerp(b.pos, w), "yaw": lerp_angle(float(a.yaw), float(b.yaw), w)}
	return _extrapolate(at)


## Past the newest snapshot: along the last velocity for up to EXTRAPOLATE_S, then held.
func _extrapolate(at: float) -> Dictionary:
	var b: Dictionary = _snaps.back()
	if _snaps.size() < 2:
		return {"pos": b.pos, "yaw": b.yaw}
	var a: Dictionary = _snaps[-2]
	var span := maxf(float(b.t) - float(a.t), 0.0001)
	var ahead := clampf(at - float(b.t), 0.0, EXTRAPOLATE_S)
	var velocity := ((b.pos as Vector3) - (a.pos as Vector3)) / span
	return {"pos": (b.pos as Vector3) + velocity * ahead, "yaw": b.yaw}
