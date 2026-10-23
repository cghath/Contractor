class_name VehicleGunnery
extends Node
## Gunnery (combined arms A4, cg_brief queue item 2.3; docs/combined_arms.md 2.7.4): the sights,
## the laser rangefinder, the fire control computer, the stabiliser and the commander's
## independent viewer with its hand-off. The "Gunnery" child of a Vehicle whose model has
## "optics" (data/vehicle_weapons.json: the Abrams' GPS, GAS and CITV; the Bradley's IBAS, its
## aux sight and the CIV).
##
## - Sights: each seat's sight in use reads its module (2.2.2): the gunner's primary (day and
##   thermal channels, magnification steps, the laser) loses thermal and the laser when damaged
##   and falls back to the aux sight when destroyed (day only, no laser, no solution: stadia per
##   round, FireControl.stadia_mil); the commander's viewer loses thermal when damaged (its
##   lowest power left as a day picture) and is gone when destroyed (periscopes only, no
##   hand-off). What a local player sees through them is VehicleSight and VehicleSightOverlay.
## - The laser (`lase`): a ray from the sight's glass along its line to the first solid thing
##   (terrain, a building, a vehicle, a man) within its ranges, plus its error. Smoke on the line
##   gives a first return where it starts; a dense screen stops the laser there. First or last
##   return picks which goes to the computer; MULTIPLE RETURNS when they differ by MULTI_M.
## - The fire control solution (FireControl.solve): the lased range (or battlesight: 1,200 m for
##   sabot, 900 for HEAT and HE) with the selected round's ballistic table, the lead (the sight's
##   turn rate in the world over the last second of tracking times the time of flight) and the
##   parallax, laid as the turret's `lay`: the reticle stays on the target, the gun moves. It holds
##   until the next lase; a new round in the breech or a feed switch re-solves at the same range.
##   Errors per lase from its seed: the laser's, the computer's err_mil (x3 with the fire control
##   damaged), the lead's (more for under a second's tracking). The fire control destroyed, or
##   the aux sight in use: no solution. AI gunners get a solution only once they lase (A9's
##   CrewGunner: lase, lay_on, hand_off, solution, F-242): until then they fire as before.
## - The stabiliser: the turret holds a world aim (each step the aim is turned back into the
##   vehicle's frame) while its sight is stabilised, the fire control isn't destroyed, the
##   traverse and elevation drives are whole and the hull is under stab max_kmh; its jitter
##   (base_mil + k_mil x speed x roughness) widens each round. Off, the gun turns with the hull and
##   firing on the move scatters UNSTAB_MIL a m/s. It runs where the turret is laid from (the
##   host, or a player gunner's own peer).
## - The commander's viewer looks wherever he looks, all round, apart from the gun. `designate`
##   (the hunter-killer hand-off) slews the turret onto his line at full speed for a gunner to take
##   ("Gunner, sabot, tank!"; a lase from his viewer comes with it); with no gunner he lays the gun
##   himself, holding designate, at COMMANDER_LAY of the drives' speed (2.5.1's 1.5x lay time).
## - Fuzes: the M1147 AMP's PD, delay and airburst, the M830A1's PD and air; airburst bursts at
##   the lased range (ShellFlight's set-range fuze).
## Host authoritative: lases, the solution and hand-offs on the host; net_state gives every peer
## and late joiner the lase, the solution's lay, the stabiliser and the fuzes; the zone save keeps
## the lase and the fuzes. Every number is Proposed.

const MIL := FireControl.MIL
## Two returns this far apart read MULTIPLE RETURNS.
const MULTI_M := 20.0
## The laser's mask: the world, vehicles, men (their capsules).
const LRF_MASK := 1 | Vehicle.LAYER | Soldier.BODY_LAYER
## Smoke this thick on the line echoes (optical depth; SmokeCloud.BLOCK_DEPTH stops the beam).
const SMOKE_ECHO := 1.0
## A slew faster than this (deg/s, the sight's line in the world) starts the track again.
const TRACK_BREAK_DPS := 20.0
const HISTORY_S := 1.5
## A hand-off's slew: done once the sight is this close to the commander's line, or given up.
const HANDOFF_ON_DEG := 0.5
const HANDOFF_MAX_S := 6.0
## The commander laying the gun himself: the drives at this share (2.5.1: 1.5x the lay time).
const COMMANDER_LAY := 1.0 / 1.5
## The stabiliser reads DEGRADED past this x its base jitter.
const STAB_DEGRADED_X := 2.0
## Unstabilised, firing on the move scatters this many mils a m/s (2.7.4: "fire at the halt").
const UNSTAB_MIL := 1.0
## Holding the lase key this long flips first and last return.
const RETURN_HOLD_S := 0.6
const VIEW_SEND_S := 0.1
const PUBLISH_S := 0.1
## A new round, feed, sight or fire control state is looked for this often (s): the gun re-lays
## within it.
const RESOLVE_S := 0.1
const FUZE_NAMES := {"": "PD", "delay": "DELAY", "airburst": "AIRBURST", "air": "AIR"}

var vehicle: Vehicle
## The model's sights (data "optics"), each with its numbers.
var optics: Array = []
var fc: Dictionary = {}
var stab: Dictionary = {}
## Host: the last lase {"ok", "why", "r" (the range the computer took), "first", "last", "multi",
## "seat", "at", "rate" (Vector2, rad/s), "trk" (s tracked), "seed"}.
var lase_data: Dictionary = {}
## First (false) or last (true) return.
var ret_last := true
## Host: the solution {"on", "bs" (battlesight), "sid", "mount", "r", "lay" (Vector2), "lead" (Vector2 rad), "trk"}.
var sol: Dictionary = {}
## Fuze mode by shell id ("" its default).
var fuze: Dictionary = {}
## Host: the commander's viewer's line (world) by seat.
var cv: Dictionary = {}
## Host: the hand-off in hand {"n", "seat", "aim" (Vector2, the sight's target), "until", "kind", "r", "full"}.
var hk: Dictionary = {}
## Replicated (host -> every peer).
var net_state: Dictionary = {}:
	set(value):
		net_state = value
		_net_at = Soldier._now()
		if not _is_host():
			_apply_net()
var _net_at := 0.0
var _hist := {}          # host: seat -> [[time, world dir]]
var _track_from := {}    # host: seat -> when the steady track began
var _pos_prev := Vector3.INF
var _basis_prev := Basis()
var _vel := Vector3.ZERO
var _speed := 0.0
var _rough := 0.0
var _stab_world := Vector3.ZERO
var _stab_set := Vector2(NAN, NAN)
var _lases := 0
var _hk_n := 0
var _sol_key: Array = []
var _dirty := false
var _publish_left := 0.0
var _lay_hold := {}      # host: seat -> until (a commander laying the gun himself)
var _view_left := 0.0    # the local commander: next view sent
var _lase_down := -1.0   # the local player: when he pressed lase
var _hk_seen := 0        # the local gunner's peer: the last hand-off taken
var _stab_on := false
var _jitter := 0.0
var _cache_frame := -1
var _sights := {}        # this physics step's sight_for, by seat
var _ctl: Soldier
var _ctl_cached := false
var _gseat := -2
var _cseat := -2
var _mod_i := {}         # module id -> its index in the vehicle's modules
var _resolve_left := 0.0


func _init(p_vehicle: Vehicle = null) -> void:
	name = "Gunnery"
	vehicle = p_vehicle
	if vehicle == null:
		return
	for o: Dictionary in vehicle.spec.get("optics", []):
		optics.append({"id": String(o.get("id", "")), "name": String(o.get("name", "")), "seat": int(o.get("seat", -1)),
			"role": String(o.get("role", "primary")), "module": String(o.get("module", "")), "head": VehicleSpecs.vec(o.get("head"), Vector3(0, 2.5, -1)),
			"day": o.get("day", []), "thermal": o.get("thermal", []), "lrf": o.get("lrf_m", []), "lrf_err": float(o.get("lrf_err_m", 5.0)),
			"stab": bool(o.get("stab", false)), "stadia": bool(o.get("stadia", false))})
	fc = vehicle.spec.get("fire_control", {})
	stab = vehicle.spec.get("stab", {})
	_publish()


func _ready() -> void:
	if not _is_host() and not net_state.is_empty():
		_apply_net()


func _is_host() -> bool:
	return not is_inside_tree() or multiplayer.multiplayer_peer == null or multiplayer.is_server()


# --- Sights (every peer) ---------------------------------------------------------------------------

func optic(id: String) -> Dictionary:
	for o: Dictionary in optics:
		if String(o.id) == id:
			return o
	return {}


func _role(seat: int, role: String) -> Dictionary:
	for o: Dictionary in optics:
		if int(o.seat) == seat and String(o.role) == role:
			return o
	return {}


## The gunner's seat (the primary sight's), or -1.
func gunner_seat() -> int:
	if _gseat == -2:
		_gseat = int(_role_any("primary").get("seat", -1))
	return _gseat


## The commander's seat (his viewer's), or -1.
func commander_seat() -> int:
	if _cseat == -2:
		_cseat = int(_role_any("commander").get("seat", -1))
	return _cseat


func _role_any(role: String) -> Dictionary:
	for o: Dictionary in optics:
		if String(o.role) == role:
			return o
	return {}


func _mod_state(o: Dictionary) -> int:
	return _state(String(o.module))


## Module `id`'s state (WORKING for none), its index found once (the layout never changes).
func _state(id: String) -> int:
	if id == "":
		return VehicleModules.WORKING
	var i: int = _mod_i.get(id, -2)
	if i == -2:
		i = vehicle.modules.index_of(id)
		_mod_i[id] = i
	var h := vehicle.modules.health
	return VehicleModules.state_of(h[i]) if i >= 0 and i < h.size() else VehicleModules.WORKING


## The sight seat `seat` looks through now, as its modules leave it ({} none): {"o" (the
## optic), "day", "thermal" (magnifications), "lrf" (has a working laser), "fallback" (the aux
## sight in the primary's place), "blur" (a damaged aux sight)}. Worked out once a physics step.
func sight_for(seat: int) -> Dictionary:
	var f := Engine.get_physics_frames()
	if f != _cache_frame:
		_cache_frame = f
		_sights.clear()
		_ctl_cached = false
	if not _sights.has(seat):
		_sights[seat] = _sight_now(seat)
	return _sights[seat]


func _sight_now(seat: int) -> Dictionary:
	var prim := _role(seat, "primary")
	if not prim.is_empty() and _mod_state(prim) != VehicleModules.DESTROYED:
		var damaged := _mod_state(prim) == VehicleModules.DAMAGED
		var day: Array = prim.day
		if day.is_empty():
			day = prim.thermal
		return {"o": prim, "day": day if damaged else prim.day, "thermal": [] if damaged else prim.thermal,
			"lrf": not damaged and not (prim.lrf as Array).is_empty(), "fallback": false, "blur": false}
	var aux := _role(seat, "aux")
	if not aux.is_empty() and _mod_state(aux) != VehicleModules.DESTROYED:
		return {"o": aux, "day": aux.day, "thermal": [], "lrf": false, "fallback": not prim.is_empty(),
			"blur": _mod_state(aux) == VehicleModules.DAMAGED}
	var cmd := _role(seat, "commander")
	if not cmd.is_empty() and _mod_state(cmd) != VehicleModules.DESTROYED:
		var hurt := _mod_state(cmd) == VehicleModules.DAMAGED
		var lowest: Array = [(cmd.thermal as Array).min()] if hurt and not (cmd.thermal as Array).is_empty() else []
		return {"o": cmd, "day": (cmd.day as Array) + lowest if hurt else cmd.day, "thermal": [] if hurt else cmd.thermal,
			"lrf": not (cmd.lrf as Array).is_empty() and not hurt, "fallback": false, "blur": false}
	return {}


## The fire control module's state (WORKING when the model has none).
func fc_state() -> int:
	return _state(String(fc.get("module", "")))


## Where seat `seat`'s sight glass is now (world).
func sight_from(seat: int) -> Vector3:
	var s := sight_for(seat)
	if s.is_empty():
		return vehicle.seat_eye_point(maxi(seat, 0))
	var head: Vector3 = (s.o as Dictionary).head
	return vehicle.global_transform * (vehicle.turret.carry(head) if vehicle.turret else head)


## Where seat `seat`'s sight looks now (world): the gunner's along the turret's sight line, the
## commander's along his viewer's.
func sight_dir(seat: int) -> Vector3:
	if seat == commander_seat() and seat >= 0:
		var occupant := vehicle.occupant(seat)
		if occupant and occupant.is_local() and not occupant.is_ai() and VehicleSight.up_for(occupant):
			return -occupant.camera.global_basis.z
		if cv.has(seat):
			return cv[seat]
	if vehicle.turret == null:
		return -vehicle.global_basis.z
	return (vehicle.global_basis * vehicle.turret.sight_local()).normalized()


## Who lays the turret now: the gunner if he's at it, else the commander (his override), else
## nobody. Worked out once a physics step.
func controller() -> Soldier:
	sight_for(-1)  # (starts this step's cache)
	if _ctl_cached:
		return _ctl if is_instance_valid(_ctl) else null
	_ctl_cached = true
	_ctl = null
	for seat: int in [gunner_seat(), commander_seat()]:
		var s := vehicle.occupant(seat) if seat >= 0 else null
		if s and VehicleModules.able(s) and not vehicle.moving_seat(s) and not (vehicle.weapons and vehicle.weapons.busy_loading(s)):
			_ctl = s
			break
	return _ctl


## Whether a hand-off is slewing the turret now (the gunner's aim waits; every peer).
func slewing() -> bool:
	if _is_host():
		return not hk.is_empty() and Soldier._now() < float(hk.get("until", 0.0))
	return float((net_state.get("hk", {}) as Dictionary).get("left", 0.0)) - (Soldier._now() - _net_at) > 0.0


## Whether the commander in `seat` looks all round (Vehicle._place_occupants: no seat clamp while
## his viewer is up; the local player's peer).
func free_look(seat: int) -> bool:
	if seat != commander_seat() or seat < 0:
		return false
	var s := vehicle.occupant(seat)
	return s != null and s.is_local() and VehicleSight.up_for(s)


# --- The stabiliser (every peer that lays the turret) ----------------------------------------------

## Whether the stabiliser holds the gun now.
func stab_on() -> bool:
	if stab.is_empty() or vehicle.turret == null:
		return false
	var s := sight_for(gunner_seat())
	if s.is_empty() or not bool((s.o as Dictionary).stab) or bool(s.fallback):
		return false
	if fc_state() == VehicleModules.DESTROYED:
		return false
	for id: String in ["traverse", "elevation"]:
		if _state(id) != VehicleModules.WORKING:
			return false
	return _speed * 3.6 <= float(stab.get("max_kmh", 40.0))


## The aim jitter now (mils): the stabiliser's by speed and ground, or firing unstabilised on the move.
func jitter_mil() -> float:
	if _is_host() or net_state.is_empty():
		return _jitter
	return float(net_state.get("j", 0.0))


## "ON", "DEGRADED" or "OFF".
func stab_text() -> String:
	if not _is_host():
		return String(net_state.get("st", "OFF"))
	if not _stab_on:
		return "OFF"
	if fc_state() == VehicleModules.DAMAGED or _jitter > float(stab.get("base_mil", 0.1)) * STAB_DEGRADED_X:
		return "DEGRADED"
	return "ON"


## The vehicle's own velocity (world, m/s), measured from where it was (a rig moved by hand too).
func own_velocity() -> Vector3:
	return _vel


func _measure(delta: float) -> void:
	var p := vehicle.global_position
	var b := vehicle.global_basis
	if _pos_prev.is_finite() and delta > 0.0:
		var v := (p - _pos_prev) / delta
		_vel = v if v.length() < 120.0 else _vel  # (a teleport isn't a speed)
		var turn := (_basis_prev.inverse() * b).get_rotation_quaternion().get_angle() / delta
		var rough := clampf(turn / maxf(float(stab.get("rough_rads", 0.35)), 0.01), 0.0, 1.0)
		_rough = lerpf(_rough, rough, 1.0 - exp(-4.0 * delta))
	_pos_prev = p
	_basis_prev = b
	_speed = _vel.length()
	_stab_on = stab_on()
	if _stab_on:
		_jitter = float(stab.get("base_mil", 0.1)) + float(stab.get("k_mil", 0.05)) * _speed * _rough
	else:
		_jitter = UNSTAB_MIL * _speed if _speed > 0.5 else 0.0


## Where the turret is laid from (here): a player gunner's own peer (it lays his turret ahead of
## the host: Vehicle._client_turret), else the host (an AI, nobody, or the commander laying it
## through his viewer's line).
func _controls_here() -> bool:
	var c := controller()
	if c != null and not c.is_ai() and vehicle.seat_of(c) == gunner_seat():
		return c.is_local()
	return _is_host()


func _stab_step() -> void:
	var t := vehicle.turret
	if t == null:
		return
	if not _stab_on or slewing():
		_stab_set = Vector2(NAN, NAN)
		return
	var cur := Vector2(t.target_yaw, t.target_pitch)
	var moved := is_nan(_stab_set.x) or absf(wrapf(cur.x - _stab_set.x, -PI, PI)) > 0.00001 or absf(cur.y - _stab_set.y) > 0.00001
	if moved:
		_stab_world = vehicle.global_basis * (Basis(Vector3.UP, cur.x) * Basis(Vector3.RIGHT, cur.y) * Vector3.FORWARD)  # the new aim, held in the world
	else:
		var local := VehicleTurret.angles(vehicle.global_basis.inverse() * _stab_world)
		t.aim(local.x, local.y)
	_stab_set = Vector2(t.target_yaw, t.target_pitch)


# --- Every step ------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if vehicle == null or vehicle.wrecked or not vehicle.is_inside_tree():
		return
	_measure(delta)
	if _is_host():
		var now := Soldier._now()
		_record(now)
		_hand_off_step(now)
		_commander_lay(now)
		_resolve_left -= delta
		if _resolve_left <= 0.0:
			_resolve_left = RESOLVE_S
			_resolve_if_changed()
	if _controls_here():
		_stab_step()
	if _is_host():
		_publish_left -= delta
		if _dirty and _publish_left <= 0.0:
			_publish()


## The sight lines' last HISTORY_S (the lead's tracking), and when each steady track began.
func _record(now: float) -> void:
	for seat: int in [gunner_seat(), commander_seat()]:
		if seat < 0 or vehicle.occupant(seat) == null or (seat == commander_seat() and not cv.has(seat)):
			continue  # (nobody there; the commander's line only once his viewer has one)
		var h: Array = _hist.get(seat, [])
		var d := sight_dir(seat)
		if not h.is_empty():
			var last: Array = h[-1]
			var dt := now - float(last[0])
			if dt > 0.0 and rad_to_deg((last[1] as Vector3).angle_to(d)) / dt > TRACK_BREAK_DPS:
				_track_from[seat] = now
		else:
			_track_from[seat] = now
		h.append([now, d])
		while h.size() > 2 and now - float(h[0][0]) > HISTORY_S:
			h.pop_front()
		_hist[seat] = h


## Seat `seat`'s sight's turn rate in the world over its track's last LEAD_TRACK_S (rad/s: yaw
## left, pitch up) and how long it has tracked: {"rate", "trk"}.
func track_of(seat: int) -> Dictionary:
	var h: Array = _hist.get(seat, [])
	if h.size() < 2:
		return {"rate": Vector2.ZERO, "trk": 0.0}
	var now := float(h[-1][0])
	var began := float(_track_from.get(seat, now))
	var from := maxf(began, now - FireControl.LEAD_TRACK_S)
	var first: Array = h[-1]
	for x: Array in h:
		if float(x[0]) >= from:
			first = x
			break
	var dt := now - float(first[0])
	if dt < 0.05:
		return {"rate": Vector2.ZERO, "trk": now - began}
	var a := VehicleTurret.angles(first[1])
	var b := VehicleTurret.angles(h[-1][1])
	return {"rate": Vector2(wrapf(b.x - a.x, -PI, PI) / dt, (b.y - a.y) / dt), "trk": now - began}


# --- The laser and the computer (host) -------------------------------------------------------------

## Host: seat `seat` lases ("lase" key; A9's AI). The result is lase_data's.
func server_lase(seat: int) -> Dictionary:
	var s := sight_for(seat)
	var now := Soldier._now()
	_lases += 1
	var seed := hash([String(vehicle.name), _lases])
	if s.is_empty() or not bool(s.lrf):
		return _lase_failed(seat, "FAULT" if not s.is_empty() and not ((s.o as Dictionary).lrf as Array).is_empty() else "NO LASER", now)
	var o: Dictionary = s.o
	var ranges := range_along(sight_from(seat), sight_dir(seat), o.lrf)
	var first := float(ranges.first)
	var last := float(ranges.last)
	var pick := last if ret_last else first
	if pick <= 0.0:
		pick = first if ret_last else last
	if pick <= 0.0:
		return _lase_failed(seat, "NO RETURN", now)
	var tr := track_of(seat)
	pick = maxf(pick + FireControl.roll(seed, 1) * float(o.lrf_err), 1.0)
	lase_data = {"ok": true, "fault": false, "why": "", "r": pick, "first": first, "last": last, "multi": first > 0.0 and last > 0.0 and absf(last - first) > MULTI_M,
		"seat": seat, "at": now, "rate": tr.rate, "trk": float(tr.trk), "seed": seed}
	_solve()
	_publish()
	return lase_data


## A lase that gave nothing: the computer keeps the last good range (if any); the sight says why.
func _lase_failed(seat: int, why: String, now: float) -> Dictionary:
	if bool(lase_data.get("ok", false)):
		lase_data["fault"] = true
		lase_data["why"] = why
	else:
		lase_data = {"ok": false, "fault": true, "why": why, "r": 0.0, "first": 0.0, "last": 0.0, "multi": false, "seat": seat, "at": now, "seed": 0}
	_publish()
	return {"ok": false, "why": why}


## The laser's returns from `from` along `dir` within `lrf` ([min, max] m): {"first", "last"} (0:
## none). The first solid thing it meets is the last return; smoke before it the first (a screen
## dense enough stops the beam: no last return).
func range_along(from: Vector3, dir: Vector3, lrf: Array) -> Dictionary:
	var lo := float(lrf[0]) if lrf.size() > 0 else 0.0
	var hi := float(lrf[1]) if lrf.size() > 1 else 4000.0
	var space := vehicle.get_world_3d().direct_space_state
	var to := from + dir.normalized() * hi
	var ex: Array[RID] = [vehicle.get_rid()]
	for s: Soldier in vehicle.occupants():
		ex.append(s.get_rid())
		ex.append_array(Launchers._rids_of(s))
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, LRF_MASK, ex))
	var end: Vector3 = hit.position if not hit.is_empty() else to
	var solid := from.distance_to(end) if not hit.is_empty() else 0.0
	var smoke := 0.0
	if SmokeCloud.depth_between(from, end, SMOKE_ECHO) >= SMOKE_ECHO:
		smoke = _smoke_entry(from, end)
		if SmokeCloud.blocks(from, end):
			solid = 0.0
	var first := smoke if smoke > 0.0 else solid
	var last := solid if solid > 0.0 else smoke
	return {"first": first if first >= lo else 0.0, "last": last if last >= lo else 0.0}


## How far along `from`->`to` the smoke first gets SMOKE_ECHO thick (m; bisected).
func _smoke_entry(from: Vector3, to: Vector3) -> float:
	var a := 0.0
	var b := 1.0
	for i in 12:
		var mid := (a + b) * 0.5
		if SmokeCloud.depth_between(from, from.lerp(to, mid), SMOKE_ECHO) >= SMOKE_ECHO:
			b = mid
		else:
			a = mid
	return from.distance_to(to) * b


## The gunner's seat's selected mount (VehicleWeapons), or {}.
func fc_mount() -> Dictionary:
	var w := vehicle.weapons
	if w == null:
		return {}
	var sel := String(w.selected.get(gunner_seat(), ""))
	return w.mount(sel)


## The round mount `m` fires next: a cannon's loaded one (or the next to load), an autocannon's
## feed; "" for the rest (a missile flies on the sight's line, an MG has no table).
func round_of(m: Dictionary) -> String:
	if m.is_empty() or vehicle.weapons == null:
		return ""
	var st: Dictionary = vehicle.weapons.state.get(String(m.id), {})
	match String(m.kind):
		VehicleWeapons.CANNON:
			return String(st.l) if String(st.get("l", "")) != "" else String(st.get("n", ""))
		VehicleWeapons.AUTOCANNON:
			return vehicle.weapons._feed_shell(m, String(st.get("f", "ap")))
	return ""


## The range the computer assumes with no lase for round `sid` (m).
func battlesight(sid: String) -> float:
	var kind := String(Shells.shell(sid).get("kind", ""))
	return float((fc.get("battlesight_m", {}) as Dictionary).get(kind, 1000.0))


## Whether the computer gives the gunner a solution now: a round with a table, the fire control
## not destroyed, the primary sight in use, and a lase made (or a player at the gun: battlesight).
func _solution_on(sid: String) -> bool:
	if sid == "" or fc.is_empty() or fc_state() == VehicleModules.DESTROYED:
		return false
	var s := sight_for(gunner_seat())
	if s.is_empty() or String((s.o as Dictionary).role) != "primary":
		return false
	var c := controller()
	return bool(lase_data.get("ok", false)) or (c != null and not c.is_ai())


## Host: the solution worked out again for the round and sight now, at the last lase's range.
func _solve() -> void:
	var t := vehicle.turret
	if t == null or vehicle.weapons == null:
		return
	var m := fc_mount()
	var sid := round_of(m)
	_sol_key = _key(m, sid)
	if not _solution_on(sid):
		_set_lay(Vector2.ZERO, {"on": false, "sid": sid, "mount": String(m.get("id", ""))})
		return
	var g := gunner_seat()
	var bs := not bool(lase_data.get("ok", false))
	var r := battlesight(sid) if bs else float(lase_data.r)
	var rate := Vector2.ZERO
	var trk := 0.0
	if not bs and int(lase_data.get("seat", -1)) == g:
		rate = lase_data.get("rate", Vector2.ZERO)
		trk = float(lase_data.get("trk", 0.0))
	var seed := int(lase_data.get("seed", 0))
	rate *= 1.0 + FireControl.roll(seed, 2) * FireControl.lead_error(trk)
	var from := sight_from(g)
	var sdir := sight_dir(g)
	var res := FireControl.solve(StringName(sid), from, sdir, r, rate, vehicle.weapons.muzzle(String(m.id)), _vel)
	var gdir: Vector3 = res.dir
	var err := float(fc.get("err_mil", 0.1)) * MIL * (float(fc.get("damaged_x", 3.0)) if fc_state() == VehicleModules.DAMAGED else 1.0)
	if err > 0.0:
		gdir = VehicleWeapons._scatter(gdir, err, seed + 7)
	var inv := vehicle.global_basis.inverse()
	var ga := VehicleTurret.angles(inv * gdir)
	var sa := VehicleTurret.angles(inv * sdir)
	var lay := Vector2(wrapf(ga.x - sa.x, -PI, PI), ga.y - sa.y)
	_set_lay(lay, {"on": true, "bs": bs, "sid": sid, "mount": String(m.id), "r": r, "lead": res.lead, "trk": trk, "tof": float(res.time)})


func _set_lay(lay: Vector2, data: Dictionary) -> void:
	var t := vehicle.turret
	if t and t.lay != lay:
		if t.lay == Vector2.ZERO:
			t.sight_yaw = t.yaw  # the sight starts where the gun is
			t.sight_pitch = t.pitch
		t.lay = lay
	data["lay"] = lay
	sol = data
	_dirty = true


func _key(m: Dictionary, sid: String) -> Array:
	var s := sight_for(gunner_seat())
	var c := controller()
	return [m.get("id", ""), sid, (s.get("o", {}) as Dictionary).get("id", ""), fc_state(), c != null and not c.is_ai(), lase_data.get("ok", false)]


## Host: a new round in the breech, a feed switch, another mount, a sight or the fire control
## changing state: the solution again at the same range.
func _resolve_if_changed() -> void:
	var m := fc_mount()
	if _key(m, round_of(m)) != _sol_key:
		_solve()


## The solution now (A9's CrewGunner; tests): {"on", "bs", "r", "lay", "lead", "trk", "sid", "mount"}.
func solution() -> Dictionary:
	if _is_host():
		return sol.duplicate()
	return net_state.get("sol", {})


## The lase now (every peer): {"ok", "why", "r", "first", "last", "multi", "seat"}.
func lase_view() -> Dictionary:
	if _is_host():
		return lase_data
	return net_state.get("l", {})


## Host: first (false) or last (true) return.
func server_set_return(last: bool) -> void:
	ret_last = last
	_dirty = true


# --- The commander (host) --------------------------------------------------------------------------

## Host: the commander in seat `seat` looks along `dir` (world) through his viewer (his peer
## sends it; A9's AI sets it). `lay`: he lays the gun himself on it (no gunner, designate held).
func server_view(seat: int, dir: Vector3, lay := false) -> void:
	if seat != commander_seat() or not dir.is_finite() or dir.length_squared() < 0.0001:
		return
	cv[seat] = dir.normalized()
	if lay:
		_lay_hold[seat] = Soldier._now() + 0.3


## Host: the commander in seat `seat` hands his line `dir` (world) to the gun (the hunter-killer
## override): the turret slews onto it at full speed for a gunner (at COMMANDER_LAY for himself),
## the gunner is told what and with what, and a range he lased goes with it. Why not ("" done).
func server_hand_off(seat: int, dir: Vector3, range_m := 0.0) -> String:
	var s := vehicle.occupant(seat) if seat >= 0 else null
	if seat != commander_seat() or s == null or not VehicleModules.able(s):
		return "Not the commander"
	if vehicle.turret == null:
		return "No turret"
	var sight := sight_for(seat)
	if sight.is_empty():
		return "Periscopes only: no hand-off"
	if vehicle.hatches and vehicle.hatches.is_out(seat):
		return "Button up to use the %s" % String(_role(seat, "commander").get("name", "viewer"))
	if not dir.is_finite() or dir.length_squared() < 0.0001:
		return "No line"
	dir = dir.normalized()
	cv[seat] = dir
	var t := vehicle.turret
	# The gun's sight goes onto his line, seen from the gunner's sight's glass (the same point far off).
	var far := sight_from(seat) + dir * maxf(range_m, 1500.0)
	var from := sight_from(gunner_seat())
	t.aim_local(vehicle.global_basis.inverse() * (far - from))
	var gunner := vehicle.occupant(gunner_seat())
	var full := gunner != null and VehicleModules.able(gunner) and not vehicle.moving_seat(gunner)
	t.rate_mult = 1.0 if full else COMMANDER_LAY
	_hk_n += 1
	var kind := target_kind(sight_from(seat), dir)
	hk = {"n": _hk_n, "seat": seat, "aim": Vector2(t.target_yaw, t.target_pitch), "until": Soldier._now() + HANDOFF_MAX_S, "kind": kind,
		"r": range_m, "full": full}
	_stab_set = Vector2(NAN, NAN)
	if range_m > 0.0:
		_lases += 1
		lase_data = {"ok": true, "why": "", "r": range_m, "first": range_m, "last": range_m, "multi": false, "seat": seat, "at": Soldier._now(),
			"rate": Vector2.ZERO, "trk": 0.0, "seed": hash([String(vehicle.name), _lases])}
	var call := "Gunner, %s, %s!" % [_ammo_word(), kind]
	if full and gunner and not gunner.is_ai():
		vehicle._tell(gunner, call)
	if not s.is_ai():
		vehicle._tell(s, "%s (the turret's coming round)" % call if full else "Laying the gun myself")
	print("[gunnery] %s %s: %s" % [vehicle.display_name(), s.display_name(), call])
	_publish()
	return ""


## What's on the line from `from` along `dir`: "tank", "PC", "truck", "troops" or "target".
func target_kind(from: Vector3, dir: Vector3) -> String:
	var space := vehicle.get_world_3d().direct_space_state
	var ex: Array[RID] = [vehicle.get_rid()]
	for s: Soldier in vehicle.occupants():
		ex.append(s.get_rid())
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 4000.0, LRF_MASK, ex))
	if hit.is_empty():
		return "target"
	var v := Vehicle.find_on(hit.collider)
	if v:
		if v.kind == Vehicle.TRACKED:
			return "tank" if float(v.spec.get("mass_kg", 0.0)) >= 40000.0 else "PC"
		return "truck"
	if hit.collider is Soldier:
		return "troops"
	return "target"


func _ammo_word() -> String:
	var m := fc_mount()
	if String(m.get("kind", "")) == VehicleWeapons.ATGM:
		return "missile"
	var sid := round_of(m)
	return VehicleWeapons.short_name(sid).to_lower() if sid != "" else "gun"


func _hand_off_step(now: float) -> void:
	if hk.is_empty() or float(hk.get("until", 0.0)) <= 0.0:
		return
	var aim: Vector2 = hk.aim
	var now_at := VehicleTurret.angles(vehicle.turret.sight_local())
	var on := absf(rad_to_deg(wrapf(now_at.x - aim.x, -PI, PI))) <= HANDOFF_ON_DEG and absf(rad_to_deg(now_at.y - aim.y)) <= HANDOFF_ON_DEG
	if on or now >= float(hk.until):
		hk.until = 0.0
		hk["done"] = on
		_solve()
		_dirty = true


## Host: the commander lays the gun himself when there's no gunner (holding designate: his
## view's line), at COMMANDER_LAY; the gunner's drives at full speed.
func _commander_lay(now: float) -> void:
	var t := vehicle.turret
	if t == null:
		return
	var c := controller()
	var cs := commander_seat()
	var commander_lays := c != null and cs >= 0 and vehicle.seat_of(c) == cs
	if slewing():
		return
	t.rate_mult = COMMANDER_LAY if commander_lays else 1.0
	if commander_lays and float(_lay_hold.get(cs, 0.0)) > now and cv.has(cs):
		var far := sight_from(cs) + (cv[cs] as Vector3) * 1500.0
		t.aim_local(vehicle.global_basis.inverse() * (far - sight_from(gunner_seat())))


# --- Fuzes ----------------------------------------------------------------------------------------

## Round `sid`'s fuze modes ("" its default first).
static func fuze_modes(sid: String) -> Array:
	var out: Array = [""]
	var f: Dictionary = Shells.shell(sid).get("fuze", {})
	for mode: Variant in (f.get("modes", {}) as Dictionary):
		out.append(String(mode))
	return out


## Host: round `sid` set to fuze mode `mode` ("" its default).
func server_set_fuze(sid: String, mode: String) -> bool:
	if not mode in fuze_modes(sid):
		return false
	if mode == "":
		fuze.erase(sid)
	else:
		fuze[sid] = mode
	_dirty = true
	_publish()
	return true


## Host: the main gun's next round's fuze to its next mode; its name.
func server_cycle_fuze() -> String:
	var m := fc_mount()
	var sid := round_of(m)
	if sid == "":
		return ""
	var modes := fuze_modes(sid)
	if modes.size() < 2:
		return ""
	var next := String(modes[(modes.find(String(fuze.get(sid, ""))) + 1) % modes.size()])
	server_set_fuze(sid, next)
	return "%s fuze: %s" % [VehicleWeapons.short_name(sid), FUZE_NAMES.get(next, next.to_upper())]


## Host (VehicleWeapons._fire_shell): round `sid`'s fuze as set here ({} for its default):
## {"fuze_mode", "airburst_m" (the lased range; battlesight with no lase)}.
func fuze_for(sid: String) -> Dictionary:
	if not fuze.has(sid):
		return {}
	var mode := String(fuze[sid])
	var out := {"fuze_mode": mode}
	if mode == "airburst":
		out["airburst_m"] = float(lase_data.r) if bool(lase_data.get("ok", false)) else battlesight(sid)
	return out


# --- A9's AI (host) ---------------------------------------------------------------------------------

## Host: the gunner's sight onto `point` (world). The gun goes there plus the solution's lay.
func lay_on(point: Vector3) -> void:
	if vehicle.turret and not slewing():
		vehicle.turret.aim_local(vehicle.global_basis.inverse() * (point - sight_from(gunner_seat())))


## Host: the commander hands `point` (world) to the gun, with a range lased if `lased` (A9).
func hand_off(point: Vector3, lased := true) -> String:
	var cs := commander_seat()
	var from := sight_from(cs)
	return server_hand_off(cs, point - from, from.distance_to(point) if lased else 0.0)


## Whether the gun is on its laid line (the aim plus the solution's lay), within `deg`.
func laid(deg := 0.3) -> bool:
	var t := vehicle.turret
	if t == null:
		return true
	var g := t.gun_target()
	return absf(rad_to_deg(wrapf(t.yaw - g.x, -PI, PI))) <= deg and absf(rad_to_deg(t.pitch - g.y)) <= deg


# --- The local player (every peer) --------------------------------------------------------------------

## The local player `me` in seat `seat` (`free`: the mouse is his): the sight (aim), its power
## (zoom), channel (sight channel), the laser (lase; held: first or last return), the hand-off
## (designate), the fuze (the underbarrel key). Nothing here takes the fire key.
func local_controls(me: Soldier, seat: int, free: bool) -> void:
	var sight := VehicleSight.of(me)
	var s := sight_for(seat)
	var hatch_out := vehicle.hatches != null and vehicle.hatches.is_out(seat)
	var can_sight := not s.is_empty() and not hatch_out
	if sight and sight.up and (not can_sight or sight.vehicle != vehicle or sight.seat != seat):
		sight.close()
	if not free:
		return
	if Input.is_action_just_pressed(&"aim"):
		if sight and sight.up:
			sight.close()
		elif can_sight:
			VehicleSight.open_for(me, self, seat)
		elif hatch_out and not _role(seat, "commander").is_empty():
			me.player_input.hud.flash("Button up to use the sight")
	sight = VehicleSight.of(me)
	var up := sight != null and sight.up
	if up:
		if Input.is_action_just_pressed(&"zoom_in"):
			sight.step_mag(1)
		elif Input.is_action_just_pressed(&"zoom_out"):
			sight.step_mag(-1)
		if Input.is_action_just_pressed(&"sight_channel"):
			me.player_input.hud.flash(sight.cycle_channel())
	var now := Soldier._now()
	if not s.is_empty() and Input.is_action_just_pressed(&"lase"):
		_lase_down = now
		request.rpc_id(1, "lase", "")
	if _lase_down >= 0.0:
		if not Input.is_action_pressed(&"lase"):
			_lase_down = -1.0
		elif now - _lase_down >= RETURN_HOLD_S:
			_lase_down = -1.0
			request.rpc_id(1, "return", "")
			me.player_input.hud.flash("LRF: %s return" % ("first" if bool(net_state.get("rl", true)) else "last"))
	if seat == commander_seat():
		var dir := sight_dir(seat)
		var hold := Input.is_action_pressed(&"designate") and up
		_view_left -= get_process_delta_time()
		if up and (_view_left <= 0.0 or hold):
			_view_left = VIEW_SEND_S
			request_view.rpc_id(1, dir, hold)
		if Input.is_action_just_pressed(&"designate"):
			if up:
				request_hand_off.rpc_id(1, dir)
			else:
				me.player_input.hud.flash("Designate from the %s (%s)" % [String(_role(seat, "commander").get("name", "viewer")),
					OS.get_keycode_string(GameSettings.key_for(&"aim")) if GameSettings.key_for(&"aim") != 0 else "right mouse"])
	if (seat == gunner_seat() or seat == commander_seat()) and Input.is_action_just_pressed(&"weapon_underbarrel"):
		request.rpc_id(1, "fuze", "")


## A player's action: "lase", "return" (first / last), "fuze" (the next round's fuze).
@rpc("any_peer", "call_local", "reliable")
func request(action: String, _arg: String) -> void:
	if not multiplayer.is_server():
		return
	var s := vehicle._sender()
	var seat := vehicle.seat_of(s)
	if s == null or seat < 0 or not s.vitals.is_up():
		return
	match action:
		"lase":
			if seat in [gunner_seat(), commander_seat()]:
				var r := server_lase(seat)
				if not bool(r.ok):
					vehicle._tell(s, "LRF: %s" % String(r.why))
		"return":
			server_set_return(not ret_last)
			_publish()
		"fuze":
			var told := server_cycle_fuze()
			if told != "":
				vehicle._tell(s, told)


## The commander's peer: his viewer's line, and whether he's laying the gun on it.
@rpc("any_peer", "call_local", "unreliable_ordered")
func request_view(dir: Vector3, lay: bool) -> void:
	if not multiplayer.is_server():
		return
	var s := vehicle._sender()
	if s and s.vitals.is_up():
		server_view(vehicle.seat_of(s), dir, lay)


@rpc("any_peer", "call_local", "reliable")
func request_hand_off(dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var s := vehicle._sender()
	if s == null or not s.vitals.is_up():
		return
	var range_m := 0.0
	var seat := vehicle.seat_of(s)
	var l := lase_data
	if bool(l.get("ok", false)) and int(l.get("seat", -1)) == seat and Soldier._now() - float(l.get("at", 0.0)) < 10.0:
		range_m = float(l.r)
	var why := server_hand_off(seat, dir, range_m)
	if why != "":
		vehicle._tell(s, why)


# --- Net, readout, saving --------------------------------------------------------------------------------

func _publish() -> void:
	if not _is_host():
		return
	_dirty = false
	_publish_left = PUBLISH_S
	var now := Soldier._now()
	var l := lase_data
	var lv := {}
	if not l.is_empty():
		lv = {"ok": bool(l.get("ok", false)), "fault": bool(l.get("fault", false)), "why": String(l.get("why", "")), "r": snappedf(float(l.get("r", 0.0)), 0.1),
			"first": snappedf(float(l.get("first", 0.0)), 0.1), "last": snappedf(float(l.get("last", 0.0)), 0.1), "multi": bool(l.get("multi", false)),
			"seat": int(l.get("seat", -1)), "trk": snappedf(float(l.get("trk", 0.0)), 0.05)}
	var sv := {}
	if not sol.is_empty():
		var lay: Vector2 = sol.get("lay", Vector2.ZERO)
		var lead: Vector2 = sol.get("lead", Vector2.ZERO)
		sv = {"on": bool(sol.get("on", false)), "bs": bool(sol.get("bs", false)), "sid": String(sol.get("sid", "")), "r": snappedf(float(sol.get("r", 0.0)), 0.1),
			"lay": [lay.x, lay.y], "lead": snappedf(lead.length() / MIL, 0.01), "trk": snappedf(float(sol.get("trk", 0.0)), 0.05)}
	var hv := {}
	if not hk.is_empty():
		hv = {"n": int(hk.n), "aim": [float((hk.aim as Vector2).x), float((hk.aim as Vector2).y)], "kind": String(hk.kind),
			"left": snappedf(maxf(float(hk.until) - now, 0.0), 0.05), "full": bool(hk.full), "seat": int(hk.seat)}
	net_state = {"l": lv, "rl": ret_last, "sol": sv, "st": stab_text(), "j": snappedf(_jitter, 0.01), "fz": fuze.duplicate(), "hk": hv}


## Clients: the published state applied: the local gunner's own turret takes the solution's lay
## and a new hand-off's aim (his peer lays it ahead of the host).
func _apply_net() -> void:
	if vehicle == null or vehicle.turret == null:
		return
	var c := controller()
	if c == null or not c.is_local() or c.is_ai() or vehicle.seat_of(c) != gunner_seat():
		return
	var sv: Dictionary = net_state.get("sol", {})
	var lay: Array = sv.get("lay", [0.0, 0.0])
	var want := Vector2(float(lay[0]), float(lay[1])) if bool(sv.get("on", false)) else Vector2.ZERO
	var t := vehicle.turret
	if t.lay != want:
		if t.lay == Vector2.ZERO:
			t.sight_yaw = t.yaw
			t.sight_pitch = t.pitch
		t.lay = want
	var hv: Dictionary = net_state.get("hk", {})
	if int(hv.get("n", 0)) > _hk_seen:
		_hk_seen = int(hv.n)
		if float(hv.get("left", 0.0)) > 0.0:
			var aim: Array = hv.aim
			t.aim(float(aim[0]), float(aim[1]))
			_stab_set = Vector2(NAN, NAN)


## The HUD's parts for seat `seat` (Vehicle.readout_parts): the lase, the stabiliser, the sight's fallback.
func readout_parts(seat: int) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	if seat != gunner_seat() and seat != commander_seat():
		return parts
	var s := sight_for(seat)
	if s.is_empty():
		parts.append({"text": "No sight: periscopes only" if seat == commander_seat() else "No sight", "style": &"warn"})
		return parts
	if bool(s.fallback):
		parts.append({"text": "%s out: on the %s" % [String(_role(seat, "primary").name), String((s.o as Dictionary).name)], "style": &"warn"})
	var l := lase_view()
	if not l.is_empty():
		var bad := bool(l.get("fault", false)) or not bool(l.get("ok", false))
		parts.append({"text": "LRF %s" % (String(l.get("why", "")) if bad else "%d m" % roundi(float(l.get("r", 0.0)))), "style": &"warn" if bad else &""})
	if seat == gunner_seat():
		parts.append({"text": "STAB %s" % stab_text(), "style": &"" if stab_text() == "ON" else &"warn"})
	return parts


## What a sight's overlay shows (VehicleSightOverlay; every peer): the sight, the lase, the
## solution, the stabiliser, the rounds and fuze, the headings, the hand-off.
func sight_info(seat: int) -> Dictionary:
	var s := sight_for(seat)
	var o: Dictionary = s.get("o", {})
	var l := lase_view()
	var sv := solution()
	var w := vehicle.weapons
	var info := {"name": String(o.get("name", "")), "role": String(o.get("role", "")), "lrf": bool(s.get("lrf", false)), "blur": bool(s.get("blur", false)),
		"fallback": bool(s.get("fallback", false)), "stab": stab_text(), "ret": "last" if (bool(net_state.get("rl", true)) if not _is_host() else ret_last) else "first",
		"lase": l, "sol": sv, "stadia": bool(o.get("stadia", false)), "commander": seat == commander_seat()}
	var lrf_state := "READY"
	if not bool(s.get("lrf", false)):
		lrf_state = "FAULT" if not (o.get("lrf", []) as Array).is_empty() else ""
	elif bool(l.get("fault", false)):
		lrf_state = String(l.get("why", "FAULT"))
	elif bool(l.get("multi", false)):
		lrf_state = "MULTIPLE RETURNS"
	info["lrf_state"] = lrf_state
	info["lead_mil"] = (sv.get("lead", Vector2.ZERO) as Vector2).length() / MIL if sv.get("lead") is Vector2 else float(sv.get("lead", 0.0))
	var m := fc_mount()
	var sid := round_of(m) if _is_host() else ""
	if w and not m.is_empty():
		var v := w._view(String(m.id))
		match String(m.kind):
			VehicleWeapons.CANNON:
				sid = String(v.get("l", "")) if String(v.get("l", "")) != "" else String(v.get("n", ""))
				info["loaded"] = VehicleWeapons.short_name(String(v.get("l", ""))) if String(v.get("l", "")) != "" else "-"
				info["next"] = VehicleWeapons.short_name(String(v.get("n", "")))
				var counts: PackedStringArray = []
				for a: Variant in m.g.get("ammo", []):
					counts.append("%s %d" % [VehicleWeapons.short_name(String(a)), w._ready_net(m, String(a))])
				info["rounds"] = "   ".join(counts)
			VehicleWeapons.AUTOCANNON:
				sid = w._feed_shell(m, String(v.get("f", "ap")))
				info["loaded"] = "%s (%s)" % [String(v.get("f", "ap")).to_upper(), String(v.get("r", "low"))]
				info["next"] = ""
				info["rounds"] = "AP %d   HE %d" % [w._ready_net(m, w._feed_shell(m, "ap")), w._ready_net(m, w._feed_shell(m, "he"))]
			VehicleWeapons.ATGM:
				info["loaded"] = "TOW"
				info["next"] = ""
				info["rounds"] = "%d on the launcher, %s" % [int(v.get("rd", 0)), String(v.get("p", "down"))]
	info["sid"] = sid
	var fz: Dictionary = fuze if _is_host() else net_state.get("fz", {})
	var mode := String(fz.get(sid, ""))
	info["fuze"] = ("%s %s" % [FUZE_NAMES.get(mode, mode.to_upper()), ("%d m" % roundi(float(l.get("r", 0.0)))) if mode == "airburst" and bool(l.get("ok", false)) else ""]).strip_edges() \
		if fuze_modes(sid).size() > 1 else ""
	var t := vehicle.turret
	var hull_yaw := vehicle.global_basis.get_euler().y
	info["hull_deg"] = wrapi(roundi(-rad_to_deg(hull_yaw)), 0, 360)
	info["turret_deg"] = wrapi(roundi(-rad_to_deg(hull_yaw + (t.yaw if t else 0.0))), 0, 360)
	var dir := sight_dir(seat)
	var barrel := vehicle.barrel_direction()
	var rel := wrapf(VehicleTurret.angles(barrel).x - VehicleTurret.angles(dir).x, -PI, PI)
	info["gun_rel_deg"] = -rad_to_deg(rel)
	if bool(o.get("stadia", false)) and sid != "":
		var marks: Array = []
		for r: float in FireControl.STADIA_M:
			if r <= FireControl.reach_m(StringName(sid)):
				marks.append([r, FireControl.stadia_mil(StringName(sid), r)])
		info["marks"] = marks
	return info


## JSON-safe: the fuzes, first or last return, the last lase's range (the solution holds).
func to_save() -> Dictionary:
	var l := {}
	if bool(lase_data.get("ok", false)):
		l = {"r": float(lase_data.r), "seat": int(lase_data.get("seat", -1))}
	return {"fuze": fuze.duplicate(), "ret_last": ret_last, "lase": l}


func from_save(data: Dictionary) -> void:
	fuze.clear()
	var fz: Variant = data.get("fuze", {})
	if fz is Dictionary:
		for sid: Variant in fz:
			if String(fz[sid]) in fuze_modes(String(sid)):
				fuze[String(sid)] = String(fz[sid])
	ret_last = bool(data.get("ret_last", true))
	var l: Variant = data.get("lase", {})
	if l is Dictionary and float((l as Dictionary).get("r", 0.0)) > 0.0:
		lase_data = {"ok": true, "why": "", "r": float(l.r), "first": float(l.r), "last": float(l.r), "multi": false, "seat": int(l.get("seat", -1)),
			"at": Soldier._now(), "rate": Vector2.ZERO, "trk": 0.0, "seed": hash([String(vehicle.name), 0])}
	_sol_key = []
	_dirty = true
	_publish()
