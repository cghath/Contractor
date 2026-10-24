class_name VehicleHatches
extends Node
## Hatches: turned out or buttoned up (combined arms A4, cg_brief queue item 2.3;
## docs/combined_arms.md 2.6). The "Hatches" child of a Vehicle whose model has "hatches"
## (data/vehicle_weapons.json: the Abrams' driver, commander and loader, the Bradley's driver and
## commander).
##
## - Turned out, the man stands in his hatch, head and shoulders out (the hatch's "out" seat: its
##   own spot and stance, drawn: Vehicle._seat_at, _place_occupants). His real hitboxes are above
##   the hull, so rounds reach them through Ballistics as anyone's, and a blast or its fragments
##   outside take him as in the open (Vehicle.seat_open: Warheads.vehicle_occupants). He sees all
##   round (Spotting x1). Buttoned up he's inside: only his vision blocks' cones (`vision`), and
##   2.5x as long to spot through them (SPOT_BUTTONED: Spotting.spot_seconds' hook, spot_x).
## - Guns that need it (a mount's "hatch": "out"): the loader's M240 fires only turned out; the
##   commander's M2 too, unless a remote mount is fitted (its "remote_package": CROWS, an A8
##   package). The TOW's reloader stands out of the roof hatch while he works ("roof_hatch"),
##   exposed the same way (VehicleWeapons' reload).
## - A player turns out or in on the hatch key in HATCH_S. AI crewmen ride turned out while it's
##   quiet (OUT_AFTER_S with no contact) and button up at once when it isn't: a hit on the
##   vehicle or a round it fires (VehicleWeapons' contact), or one of them shot at or near-missed
##   (Soldier.threat_time). A9 (Claude's AI crews) can take this over (`auto_ai` false) and add
##   the SAFE/AWARE/COMBAT states, artillery and towns (F-251).
## Host authoritative; net_state gives every peer and late joiner who's out; the zone save keeps
## it. Every number is Proposed.

const HATCH_S := 1.5
const OUT_AFTER_S := 60.0
const SPOT_BUTTONED := 2.5
const AUTO_HZ := 2.0
## Contact for the AI's rule: a crewman shot at within this long.
const THREAT_S := 60.0

var vehicle: Vehicle
## {seat: {"out": {"at", "stance"}, "vision": [[yaw_deg, width_deg], ...]}}
var defs: Dictionary = {}
## The TOW reloader's spot out of the roof hatch ({} none).
var roof: Dictionary = {}
## Host: seat -> turned out.
var out: Dictionary = {}
## Host: seat -> [turning out (bool), done at].
var moving: Dictionary = {}
var auto_ai := true
## Replicated: {"o": [seats out], "x": [seats exposed for a job (the TOW's roof hatch)], "mv": {seat: [to, seconds left]}}.
var net_state: Dictionary = {}:
	set(value):
		net_state = value
		_net_at = Soldier._now()
var _net_at := 0.0
var _auto_left := 0.0
var _dirty := false
var _locals := {}  # seat -> [stance, Transform3D] (the out spot's body origin, vehicle frame)
var _born := 0.0


func _init(p_vehicle: Vehicle = null) -> void:
	name = "Hatches"
	vehicle = p_vehicle
	if vehicle == null:
		return
	var h: Dictionary = vehicle.spec.get("hatches", {})
	for k: Variant in h:
		if String(k).is_valid_int():
			defs[int(String(k))] = h[k]
			out[int(String(k))] = false
	roof = vehicle.spec.get("roof_hatch", {})
	_publish()


func _ready() -> void:
	set_physics_process(_is_host())
	_born = Soldier._now()


func _is_host() -> bool:
	return not is_inside_tree() or multiplayer.multiplayer_peer == null or multiplayer.is_server()


# --- Queries (every peer) -----------------------------------------------------------------------

func has_hatch(seat: int) -> bool:
	return defs.has(seat)


## Whether seat `seat` is turned out now (its hatch open with a man in it; the hatch stays as it
## was left, so the next man in is where the last one was).
func is_out(seat: int) -> bool:
	if vehicle.occupant(seat) == null:
		return false
	if _is_host():
		return bool(out.get(seat, false))
	return seat in (net_state.get("o", []) as Array)


## Whether the man in seat `seat` is out of the hull now: turned out, or out of the roof hatch
## reloading the TOW.
func exposed(seat: int) -> bool:
	return is_out(seat) or _roof_job(seat)


func _roof_job(seat: int) -> bool:
	if roof.is_empty():
		return false
	if not _is_host():
		return seat in (net_state.get("x", []) as Array)
	var w := vehicle.weapons
	if w == null:
		return false
	for m: Dictionary in w.mounts:
		if String(m.kind) == VehicleWeapons.ATGM:
			var st: Dictionary = w.state[m.id]
			if float(st.rl) > 0.0 and int(st.rb) == seat:
				return true
	return false


## The seat's definition as it is now: turned out (or on the roof), its "out" spot's "at" and
## "stance", and "open" (Vehicle._place_occupants draws him); else `base` itself.
func seat_def(seat: int, base: Dictionary) -> Dictionary:
	var o := _spot(seat)
	if o.is_empty():
		return base
	var d := base.duplicate()
	d["at"] = o.get("at", base.get("at"))
	d["stance"] = String(o.get("stance", "stand"))
	d["open"] = true
	return d


func _spot(seat: int) -> Dictionary:
	if is_out(seat):
		return (defs.get(seat, {}) as Dictionary).get("out", {})
	if _roof_job(seat):
		return roof
	return {}


## Whether seat `seat` is drawn at another spot now (turned out, on the roof).
func overrides(seat: int) -> bool:
	return not _spot(seat).is_empty()


## The body's origin for seat `seat` at its spot now (vehicle frame, the turret at rest), or
## `base` when it's in its seat.
func seat_local(seat: int, base: Transform3D) -> Transform3D:
	var o := _spot(seat)
	if o.is_empty():
		return base
	var stance := String(o.get("stance", "stand"))
	var key := [stance, o.get("at")]
	var cached: Array = _locals.get(seat, [])
	if cached.size() == 2 and cached[0] == key:
		return cached[1]
	var t := Transform3D(Basis(), VehicleSpecs.vec(o.get("at")) - Vector3(0, Vehicle.seat_eye(stance), 0))
	_locals[seat] = [key, t]
	return t


## The eye of seat `seat` at its spot now ("at", vehicle frame, the turret at rest; null in its seat).
func eye_local(seat: int) -> Variant:
	var o := _spot(seat)
	return VehicleSpecs.vec(o.get("at")) if not o.is_empty() else null


## Why mount `m` (VehicleWeapons.layout's) can't be fired from seat `seat` now ("" it can): a gun
## worked from the hatch needs its man turned out, unless its remote mount is fitted.
func mount_why(seat: int, m: Dictionary) -> String:
	if String(m.get("hatch", "")) != "out" or is_out(seat):
		return ""
	var remote := String(m.get("remote", ""))
	if remote != "" and remote in ArmourModel.fitted_packages(vehicle.spec, vehicle.get_meta(ArmourModel.META_PACKAGES, [])):  # (A8: TUSK II includes CROWS)
		return ""
	return "Turn out first"


## Seconds until seat `seat`'s hatch move is done (0 none).
func move_left(seat: int) -> float:
	if _is_host():
		var mv: Array = moving.get(seat, [])
		return maxf(float(mv[1]) - Soldier._now(), 0.0) if mv.size() == 2 else 0.0
	var v: Array = (net_state.get("mv", {}) as Dictionary).get(str(seat), [])
	return maxf(float(v[1]) - (Soldier._now() - _net_at), 0.0) if v.size() == 2 else 0.0


## How much longer `observer` takes to spot something at `at` from where he sits (Spotting's hook):
## 1 out of a vehicle, in a seat with no hatch, or turned out; SPOT_BUTTONED inside one of his
## vision blocks' cones buttoned up; INF outside them.
static func spot_x(observer: Soldier, at: Vector3) -> float:
	var v := observer.vehicle if observer else null
	if v == null or not is_instance_valid(v) or v.hatches == null:
		return 1.0
	var h := v.hatches
	var seat := v.seat_of(observer)
	if not h.defs.has(seat) or h.exposed(seat):
		return 1.0
	var vision: Array = (h.defs[seat] as Dictionary).get("vision", [])
	if vision.is_empty():
		return INF
	var basis := v.global_basis
	if v.turns_with_turret(seat):
		basis = basis * Basis(Vector3.UP, v.turret.yaw)
	var local := basis.inverse() * (at - v.seat_eye_point(seat))
	if local.length_squared() < 0.0001:
		return SPOT_BUTTONED
	var yaw := rad_to_deg(atan2(-local.x, -local.z)) - float(v.spec.seats[seat].get("face", 0.0))
	for b: Variant in vision:
		if absf(wrapf(yaw - float(b[0]), -180.0, 180.0)) <= float(b[1]) * 0.5:
			return SPOT_BUTTONED
	return INF


# --- Host -----------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if vehicle == null or not _is_host():
		return
	var now := Soldier._now()
	for seat: int in moving.keys():
		var mv: Array = moving[seat]
		var s := vehicle.occupant(seat)
		if s == null or not VehicleModules.able(s):
			moving.erase(seat)  # (he went down or left: the move stops)
			_dirty = true
		elif now >= float(mv[1]):
			out[seat] = bool(mv[0])
			moving.erase(seat)
			_dirty = true
	_auto_left -= delta
	if auto_ai and _auto_left <= 0.0:
		_auto_left = 1.0 / AUTO_HZ
		_auto(now)
	var roof_now := _roof_seats()
	if roof_now != net_state.get("x", []):
		_dirty = true
	if _dirty:
		_publish()


## AI crewmen out while it's quiet, in at the first contact.
func _auto(now: float) -> void:
	var quiet := _quiet_for(now)
	for seat: int in defs:
		var s := vehicle.occupant(seat)
		if s == null or not s.is_ai() or not VehicleModules.able(s) or vehicle.moving_seat(s):
			continue
		var want := quiet >= OUT_AFTER_S
		if want != bool(out.get(seat, false)) and not moving.has(seat):
			if want:
				server_set(seat, true)
			else:
				out[seat] = false  # buttoning up under fire is at once
				_dirty = true


## Seconds since the last contact: a hit, a round fired (VehicleWeapons), a crewman shot at (or
## since the vehicle came into the level: a new crew settles in buttoned up first).
func _quiet_for(now: float) -> float:
	var last := _born
	if vehicle.weapons:
		last = maxf(last, vehicle.weapons._last_contact)
	for s: Soldier in vehicle.occupants():
		if s and is_instance_valid(s):
			last = maxf(last, s.threat_time if now - s.threat_time <= THREAT_S else -INF)
	return now - last


## Host: seat `seat` turns out (`want_out`) or buttons up, taking HATCH_S (`now`: at once). Why
## not ("" started).
func server_set(seat: int, want_out: bool, now := false) -> String:
	if not defs.has(seat):
		return "No hatch"
	var s := vehicle.occupant(seat)
	if s == null or not VehicleModules.able(s) or vehicle.moving_seat(s):
		return "Nobody to do it"
	if bool(out.get(seat, false)) == want_out and not moving.has(seat):
		return ""
	if now:
		out[seat] = want_out
		moving.erase(seat)
	else:
		moving[seat] = [want_out, Soldier._now() + HATCH_S]
	_dirty = true
	_publish()
	return ""


## A player's hatch key: turn out or in.
@rpc("any_peer", "call_local", "reliable")
func request_toggle() -> void:
	if not multiplayer.is_server():
		return
	var s := vehicle._sender()
	var seat := vehicle.seat_of(s)
	if s == null or seat < 0:
		return
	var want := not bool(out.get(seat, false))
	if moving.has(seat):
		want = not bool(moving[seat][0])
	var why := server_set(seat, want)
	if why != "":
		vehicle._tell(s, why)
	else:
		vehicle._tell(s, "Turning out" if want else "Buttoning up")


func _roof_seats() -> Array:
	var outs: Array = []
	if roof.is_empty():
		return outs
	for i in vehicle.seat_count():
		if _roof_job(i):
			outs.append(i)
	return outs


func _publish() -> void:
	if not _is_host():
		return
	_dirty = false
	var o: Array = []
	for seat: int in out:
		if bool(out[seat]):
			o.append(seat)
	o.sort()
	var mv := {}
	var now := Soldier._now()
	for seat: int in moving:
		mv[str(seat)] = [bool(moving[seat][0]), snappedf(maxf(float(moving[seat][1]) - now, 0.0), 0.05)]
	net_state = {"o": o, "x": _roof_seats() if vehicle else [], "mv": mv}


# --- Readout, saving -----------------------------------------------------------------------------

## The HUD's part for seat `seat` (Vehicle.readout_parts): out or in, and the key.
func readout_parts(seat: int) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	if not defs.has(seat):
		return parts
	var key := OS.get_keycode_string(GameSettings.key_for(&"hatch"))
	var left := move_left(seat)
	if left > 0.0:
		parts.append({"text": "Hatch (%.1f s)" % left, "style": &"warn"})
	else:
		parts.append({"text": "%s [%s]" % ["Turned out" if is_out(seat) else "Buttoned up", key], "style": &"warn" if is_out(seat) else &""})
	return parts


## JSON-safe: who's turned out.
func to_save() -> Dictionary:
	var o: Array = []
	for seat: int in out:
		if bool(out[seat]):
			o.append(seat)
	return {"out": o}


func from_save(data: Dictionary) -> void:
	for seat: int in out:
		out[seat] = false
	for k: Variant in data.get("out", []):
		if defs.has(int(k)):
			out[int(k)] = true
	moving.clear()
	_publish()
