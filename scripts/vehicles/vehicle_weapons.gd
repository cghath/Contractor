class_name VehicleWeapons
extends Node
## What an armoured vehicle's crew fights with (combined arms A3, cg_brief queue item 2.2;
## docs/combined_arms.md 2.5 and 2.7): the mounts in data/vehicle_weapons.json, each fired from
## its seat and reading its own modules (A2: a destroyed one puts it out, all its sights gone put
## it out, a bent barrel scatters it, a damaged gun jams). The "Weapons" child of a Vehicle whose
## model has "weapons" (the Abrams, the Bradley).
##
## - The Abrams' M256 120 mm (kind cannon): one round in the breech. The loader pulls the next
##   from the bustle (its blast doors open while he does: a bustle hit then can't vent, 2.10.2,
##   VehicleModules._detonation_roll), rams it, closes and arms: an AI loader in 5-6 s by skill; a
##   player works the three steps on the reload key with a window on the ram (4.5 s in it, 6.5 s
##   outside). With no loader the commander, else the gunner, loads: 15 s, off his sight. A
##   damaged breech makes every load x1.5. The gunner picks what's loaded next (sabot, HEAT-MP,
##   AMP); the round in the breech stays until fired or unloaded (8 s). The loader restocks the
##   bustle from the hull rack (12 s a round, the turret within 15 degrees of the front) on his own
##   when it's below 10 and nothing's happened for QUIET_S, or when told.
## - The Bradley's M242 25 mm (autocannon), dual feed: AP (M791, or M919 with the ammo package)
##   and HE (M792) ready boxes, switched in 1.5 s; single shot, low rate (100) or high rate
##   (200). Both boxes are refilled from the hull's stowage in 120 s, stopped and quiet, by the
##   gunner and a dismount.
## - The TOW-2A launcher (atgm): raised in 4 s at a halt (moving lowers it), fired with the
##   gunner holding the crosshair on the target to impact: the missile flies to the sight line
##   0.3 s behind it (LauncherProjectile "saclos", saclos_line here) and the wire breaks on a fast
##   traverse, smoke on the line, the launcher coming down, out of wire. Two on the launcher; a
##   dismount reloads it from the hull's five, launcher down, 45 s a missile, out of the roof hatch.
## - The coax (the vehicle's own "gun", fired through Vehicle.server_fire_gun as before, now by its
##   own sights, not the main gun's breech), the commander's M2 and the loader's M240 (cupola and
##   pintle: turn with the turret, aimed where their man looks).
## - The commander can fire the main gun and the TOW from his seat (2.5.1's override).
##
## Shells fly through ShellFlight; missiles through Launchers. Which rounds a rack holds lives here
## (`racks`: {rack module id: {shell id: rounds}}); VehicleModules' rack count stays their total
## (losses to hits come back here: _reconcile_racks). Phase A8 makes the rounds items: its hook is
## server_stow and rack_contents. AI crews using the guns are phase A9: every action is a
## server_* call any brain can make, and can_fire says why one can't.
##
## Gunnery (A4, VehicleGunnery): the main gun is laid off its sight by the fire control (the
## turret's lay); a shell carries the stabiliser's jitter and the vehicle's measured speed and takes
## its fuze from the gunner (the AMP's airburst at the lased range); the TOW's wire follows the
## sight's line (sight_line); a gun worked from a hatch fires only turned out (VehicleHatches).
##
## Host authoritative: the state lives on the host, net_state (in the vehicle's StateSync) gives
## every peer and late joiner what's loaded, the racks, the feeds and the launcher, and the zone
## save keeps it (to_save). Every number is Proposed.

const PATH := "res://data/vehicle_weapons.json"
const CANNON := "cannon"
const AUTOCANNON := "autocannon"
const ATGM := "atgm"
const MG := "mg"

## The loader's cycle (2.7.3): pull (the doors open), ram, close and arm.
const PULL_S := 2.0
const RAM_S := 1.5
const CLOSE_S := 1.0
## A player loader: the ram in its window (RAM_WINDOW_S after the pull) gives the fast load, else the slow one.
const PLAYER_FAST_S := 4.5
const PLAYER_SLOW_S := 6.5
const RAM_WINDOW_S := 0.7
## An AI loader's whole load, from an unskilled man to a skilled one (SquadAI combat 0 to 1).
const AI_LOAD_S := Vector2(6.0, 5.0)
## Short-crewed: the commander or gunner loads (2.5.1).
const SHORT_LOAD_S := 15.0
const UNLOAD_S := 8.0
## Restocking the bustle from the hull rack: a round, below what, the turret within this of the front.
const RESTOCK_S := 12.0
const RESTOCK_BELOW := 10
const RESTOCK_FRONT_DEG := 15.0
## "Out of contact": nothing hit the vehicle and it fired nothing for this long.
const QUIET_S := 30.0
## A damaged breech: loads (and the 25 mm's feed switch) take this much longer (2.2.2).
const BREECH_SLOW := 1.5
const FEED_SWITCH_S := 1.5
const REFILL_S := 120.0
## Stopped: slower than this (m/s).
const STOPPED_MPS := 0.5
const TOW_RAISE_S := 4.0
const TOW_MOVE_MPS := 1.0
const TOW_RELOAD_S := 45.0
## SACLOS: the missile follows the sight line as it was this long ago; the turret turning faster
## than WIRE_BREAK_DPS snaps the wire.
const WIRE_LAG_S := 0.3
const WIRE_BREAK_DPS := 25.0
const SIGHT_KEEP_S := 1.0
## The turret on its batteries this long after the engine dies, then by hand (2.2.2).
const BATTERY_TURRET_S := 600.0
## A damaged gun jams every JAM_EVERY rounds for JAM_S (A2's rule), a damaged barrel scatters x3.
const JAM_EVERY := VehicleModules.JAM_EVERY
const JAM_S := VehicleModules.JAM_S
const BARREL_SPREAD := VehicleModules.BARREL_SPREAD
## A NATO mil in radians.
const MIL := TAU / 6400.0
## A cupola or pintle gun fires within these pitches (degrees, the vehicle's frame).
const CUPOLA_PITCH := Vector2(-10.0, 60.0)
## Short names on the readout, by shell kind.
const SHORT := {"apfsds": "SABOT", "apds": "AP", "heat": "HEAT", "amp": "HE", "hei": "HE", "he": "HE", "tandem_heat": "TOW"}

static var _data: Dictionary = {}

var vehicle: Vehicle
## The mounts (layout()): each {"id", "gun", "g" (the gun's data), "kind", "seat", "turret",
## "muzzle", "modules", "sights", "legacy", "racks", "stowage", "ready", "loader_seat",
## "commander_seat", "battlecarry"}.
var mounts: Array = []
## Which rounds each rack holds: {rack module id: {shell id: rounds}} (host; clients from net_state).
var racks: Dictionary = {}
## The live state of each mount by id (host): cannon {"l" loaded, "n" next, "cy" cycle ("",
## "load", "short", "unload", "restock"), "by" the seat doing it, "t0", "end", "pull" (the doors
## shut at), "w0", "w1" (a player's ram window), "pl" a player's cycle, "ok" rammed in the window,
## "am" the round in his hands, "fz" fuze mode, "ab" airburst range, "rs" restocks told};
## autocannon {"f" feed, "r" rate, "sw" switching until, "rf" refill until, "rb" the dismount's
## seat}; atgm {"p" "down"/"raising"/"up", "u" up at, "rd" ready, "g" missile it guides, "rl"
## reload until, "rb" the reloader's seat}.
var state: Dictionary = {}
## The mount each seat's fire key fires: {seat: mount id}.
var selected: Dictionary = {}
## Replicated (host -> every peer): {"m": {mount id: its view}, "r": racks, "s": selected, "bat":
## the turret by hand}. Times in a view are seconds left when it was published.
var net_state: Dictionary = {}:
	set(value):
		net_state = value
		_net_at = Soldier._now()
		if not _is_host():
			_apply_net()
var _net_at := 0.0
var _jams := {}            # host: mount id -> rounds since its last jam
var _next := {}            # host: mount id -> when it may fire next
var _local_next := 0.0     # the local player: when his held trigger sends the next shot
var _last_contact := -INF  # host: the last hit taken or round fired
var _sight: Array = []     # host: [[time, origin, dir]] the gunner's sight line, the last SIGHT_KEEP_S
var _yaw_prev := NAN
var _yaw_dps := 0.0
var _engine_out_s := 0.0
var _manual := false
var _dirty := false
var _shot_n := 0


func _init(p_vehicle: Vehicle = null) -> void:
	name = "Weapons"
	vehicle = p_vehicle
	if vehicle == null:
		return
	mounts = layout(vehicle.spec)
	server_reset_racks()
	for m: Dictionary in mounts:
		match String(m.kind):
			CANNON:
				state[m.id] = {"l": String(m.battlecarry), "n": String(m.battlecarry), "cy": "", "by": -1, "t0": 0.0, "end": 0.0, "pull": 0.0,
					"w0": 0.0, "w1": 0.0, "pl": false, "ok": false, "am": "", "fz": "", "ab": 0.0, "rs": 0}
				if String(m.battlecarry) != "":
					_take(m, String(m.battlecarry))  # battlecarry: the first round is in the breech
			AUTOCANNON:
				state[m.id] = {"f": "ap", "r": "low", "sw": 0.0, "rf": 0.0, "rb": -1}
			ATGM:
				state[m.id] = {"p": "down", "u": 0.0, "rd": int(m.ready), "g": 0, "rl": 0.0, "rb": -1}
			_:
				state[m.id] = {}
		if not selected.has(int(m.seat)) and not bool(m.legacy):
			selected[int(m.seat)] = String(m.id)
	_publish()


func _ready() -> void:
	set_physics_process(_is_host())
	if _is_host() and vehicle:
		vehicle.damaged.connect(func(_z: StringName, _h: Dictionary) -> void: _last_contact = Soldier._now())
	elif not net_state.is_empty():
		_apply_net()


func _is_host() -> bool:
	return not is_inside_tree() or multiplayer.multiplayer_peer == null or multiplayer.is_server()


# --- Layout (pure) ------------------------------------------------------------------------------

static func _file() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_data = parsed if parsed is Dictionary else {"models": {}}
	return _data


## The mounts of a merged vehicle spec (its "weapons"), each with its gun's data.
static func layout(spec: Dictionary) -> Array:
	var out: Array = []
	for w: Dictionary in spec.get("weapons", []):
		var g := VehicleSpecs.gun(String(w.get("gun", "")))
		var legacy := bool(w.get("legacy", false))
		out.append({"id": String(w.get("id", "mount_%d" % out.size())), "gun": String(w.get("gun", "")), "g": g,
			"kind": MG if legacy else String(g.get("kind", MG)), "seat": int(w.get("seat", -1)), "turret": String(w.get("turret", "main")),
			"muzzle": VehicleSpecs.vec(w.get("muzzle"), Vector3.ZERO), "modules": w.get("modules", []), "sights": w.get("sights", []),
			"legacy": legacy, "racks": w.get("racks", []), "stowage": w.get("stowage", []), "ready": w.get("ready", 0),
			"loader_seat": int(w.get("loader_seat", -1)), "commander_seat": int(w.get("commander_seat", -1)),
			"battlecarry": String(w.get("battlecarry", "")), "hatch": String(w.get("hatch", "")), "remote": String(w.get("remote_package", ""))})
	return out


## The default load-out of a model's racks ({rack id: {shell id: rounds}}, a copy, whole numbers).
static func default_racks(spec: Dictionary) -> Dictionary:
	var out := {}
	var racks_in: Dictionary = spec.get("racks", {})
	for rack: Variant in racks_in:
		var c := {}
		for sid: Variant in racks_in[rack]:
			c[String(sid)] = int(racks_in[rack][sid])
		out[String(rack)] = c
	return out


## The short name of shell `id` on the readout (SABOT, HEAT, HE, AP; the M919 by its name).
static func short_name(id: String) -> String:
	if id == "":
		return "-"
	if id == "m919":
		return "AP (M919)"
	return String(SHORT.get(String(Shells.shell(id).get("kind", "")), id.to_upper()))


# --- Queries (every peer) -----------------------------------------------------------------------

## Mount `id` ({} for none).
func mount(id: String) -> Dictionary:
	for m: Dictionary in mounts:
		if String(m.id) == id:
			return m
	return {}


## The mounts fired from seat `seat` (the legacy coax included), in data order.
func mounts_for(seat: int) -> Array:
	return mounts.filter(func(m: Dictionary) -> bool: return int(m.seat) == seat)


## Whether mount `id` can fire for its modules (every peer): none of its modules destroyed, not
## every one of its sights.
func mount_ok(id: String) -> bool:
	var m := mount(id)
	if m.is_empty() or vehicle == null or vehicle.wrecked:
		return false
	var mods := vehicle.modules
	for mod_id: Variant in m.modules:
		if mods.health_of(String(mod_id)) <= 0.0001:
			return false
	var sights: Array = m.sights
	if sights.is_empty():
		return true
	return sights.any(func(sid: Variant) -> bool: return mods.health_of(String(sid)) > 0.0001)


func _module_damaged(m: Dictionary, kind: String) -> bool:
	var mods := vehicle.modules
	for mod_id: Variant in m.modules:
		var i := mods.index_of(String(mod_id))
		if i >= 0 and String(mods.mods[i].kind) == kind and VehicleModules.state_of(mods.health[i]) == VehicleModules.DAMAGED:
			return true
	return false


## The rounds in rack `rack_id` by shell ({shell id: rounds}, a copy; every peer). A8's hook.
func rack_contents(rack_id: String) -> Dictionary:
	return (racks.get(rack_id, {}) as Dictionary).duplicate()


func rack_total(rack_id: String) -> int:
	var n := 0
	for sid: String in racks.get(rack_id, {}):
		n += int(racks[rack_id][sid])
	return n


## Every rack's rounds of `shell_id` that mount `m` can reach (its racks, or its ready box).
func ready_of(m: Dictionary, shell_id: String) -> int:
	var n := 0
	for r: Variant in _ready_racks(m):
		n += int((racks.get(String(r), {}) as Dictionary).get(shell_id, 0))
	return n


func _ready_racks(m: Dictionary) -> Array:
	if String(m.kind) == AUTOCANNON:
		return [String(m.ready)]
	return m.racks


## The round in mount `id`'s breech ("" none; a cannon's).
func loaded(id: String) -> String:
	if _is_host():
		return String((state.get(id, {}) as Dictionary).get("l", ""))
	return String((net_state.get("m", {}).get(id, {}) as Dictionary).get("l", ""))


## Whether rack `rack_id`'s blast doors are open now (the loader pulling a round from it: A3's
## hook in VehicleModules._detonation_roll; host).
func doors_open(rack_id: String) -> bool:
	var now := Soldier._now()
	for m: Dictionary in mounts:
		if String(m.kind) != CANNON or not rack_id in m.racks:
			continue
		var st: Dictionary = state[m.id]
		if String(st.cy) in ["load", "short"] and now < float(st.pull) and String(st.get("rk", "")) == rack_id:
			return true
	return false


## Whether `s` is busy loading the main gun (short-crewed: off his sight; host).
func busy_loading(s: Node) -> bool:
	var seat := vehicle.seat_of(s)
	if seat < 0:
		return false
	for m: Dictionary in mounts:
		if String(m.kind) == CANNON:
			var st: Dictionary = state[m.id]
			if String(st.cy) in ["load", "short", "unload", "restock"] and int(st.by) == seat and seat != int(m.loader_seat):
				return true
	return false


## How long a load by `seat` takes on mount `m` now (s): an AI loader's by skill, a player's slow
## one, short-crewed 15; a damaged breech x1.5.
func load_time(m: Dictionary, seat: int, s: Soldier) -> float:
	var slow := BREECH_SLOW if _module_damaged(m, "breech") else 1.0
	if seat != int(m.loader_seat):
		return SHORT_LOAD_S * slow
	if s and not s.is_ai():
		return PLAYER_SLOW_S * slow
	var brain := SquadAI.of(s) if s else null
	var skill := clampf(float(brain.combat) if brain else 0.5, 0.0, 1.0)
	return lerpf(AI_LOAD_S.x, AI_LOAD_S.y, skill) * slow


## Why `shooter` can't fire mount `id` now ("" if he can; host). A9's AI asks before firing.
func can_fire(shooter: Soldier, id: String) -> String:
	var m := mount(id)
	if m.is_empty():
		return "No such weapon"
	if not _at_job(shooter, m):
		return "Not at that weapon"
	if not mount_ok(id):
		return "%s is out" % String(m.g.get("name", id))
	if vehicle.hatches:
		var hatch := vehicle.hatches.mount_why(vehicle.seat_of(shooter), m)  # A4: a gun worked from the hatch
		if hatch != "":
			return hatch
	var st: Dictionary = state[id]
	var now := Soldier._now()
	match String(m.kind):
		CANNON:
			if String(st.l) == "":
				return "Loading" if String(st.cy) in ["load", "short"] else "Not loaded"
			if busy_loading(shooter):
				return "Loading"
		AUTOCANNON:
			if now < float(st.sw):
				return "Switching feed"
			if now < float(st.rf):
				return "Refilling the ready boxes"
			if _feed_shell(m, String(st.f)) == "" or ready_of(m, _feed_shell(m, String(st.f))) <= 0:
				return "%s box empty" % String(st.f).to_upper()
		ATGM:
			if String(st.p) != "up":
				return "Launcher down" if String(st.p) == "down" else "Raising the launcher"
			if int(st.rd) <= 0:
				return "Launcher empty"
			if int(st.g) != 0:
				return "Guiding a missile"
		MG:
			if not bool(m.legacy) and vehicle.cargo_hold and vehicle.cargo_hold.feed_rounds(StringName(m.g.get("feed", ""))) <= 0:
				return "No ammunition"
	return ""


## Whether `s` works mount `m` from where he sits: its seat, or the commander's override on the
## turret's guns (2.5.1); up, able and not moving seats.
func _at_job(s: Soldier, m: Dictionary) -> bool:
	if s == null or not VehicleModules.able(s) or vehicle.moving_seat(s):
		return false
	var seat := vehicle.seat_of(s)
	if seat < 0:
		return false
	return seat == int(m.seat) or (seat == int(m.commander_seat) and String(m.turret) in ["main", "ring"])


func _able_at(seat: int) -> Soldier:
	var s := vehicle.occupant(seat) if seat >= 0 else null
	return s if VehicleModules.able(s) and not vehicle.moving_seat(s) else null


# --- The coax's hooks (Vehicle.server_fire_gun) ---------------------------------------------------

func _legacy_of(seat: int) -> Dictionary:
	for m: Dictionary in mounts:
		if bool(m.legacy) and int(m.seat) == seat:
			return m
	return {}


## Host: whether the vehicle's own gun at `seat` may fire for `shooter`: its own sights (not the
## main gun's breech, F-237), its man at his job and not loading.
func legacy_ok(seat: int, shooter: Soldier) -> bool:
	var m := _legacy_of(seat)
	if m.is_empty():
		return vehicle.modules.gun_ok(seat)
	if not mount_ok(String(m.id)):
		return false
	return shooter == null or not (vehicle.moving_seat(shooter) or busy_loading(shooter))


func legacy_jam_s(seat: int) -> float:
	var m := _legacy_of(seat)
	return _jam(m) if not m.is_empty() else vehicle.modules.gun_jam_s(seat)


func legacy_spread_mult(seat: int) -> float:
	var m := _legacy_of(seat)
	return BARREL_SPREAD if not m.is_empty() and _module_damaged(m, "barrel") else (1.0 if not m.is_empty() else vehicle.modules.gun_spread_mult(seat))


## Host: after mount `m` fired, the wait a damaged gun module of it adds (a jam every JAM_EVERY).
func _jam(m: Dictionary) -> float:
	var damaged := false
	for kind: String in ["breech", "ext_gun", "ugws", "launcher"]:
		damaged = damaged or _module_damaged(m, kind)
	if not damaged:
		return 0.0
	_jams[m.id] = int(_jams.get(m.id, 0)) + 1
	if int(_jams[m.id]) >= JAM_EVERY:
		_jams[m.id] = 0
		return JAM_S
	return 0.0


# --- Where the guns are (every peer) -------------------------------------------------------------

## Mount `id`'s muzzle in the world now: on the gun (main), on the turret (ring, cupola, pintle).
func muzzle(id: String) -> Vector3:
	var m := mount(id)
	var t := vehicle.turret
	var rest: Vector3 = m.get("muzzle", Vector3.ZERO)
	if bool(m.get("legacy", false)):
		return vehicle.gun_origin(int(m.seat))
	if t == null:
		return vehicle.global_transform * rest
	return vehicle.global_transform * (t.on_gun(rest) if String(m.turret) == "main" else t.carry(rest))


## The main gun's line in the world (the crosshair's: the gunner lays the turret on it).
func barrel() -> Vector3:
	return vehicle.barrel_direction()


## The gunner's sight's line in the world (A4: the sight's, apart from the gun by the solution's
## lay; the barrel's on a model with no sights).
func sight_line() -> Vector3:
	var g := vehicle.gunnery
	return g.sight_dir(g.gunner_seat()) if g and g.gunner_seat() >= 0 else barrel()


## The gunner's sight in the world: its glass (A4: VehicleGunnery, the sight in use), else the
## gunner_sight module's middle, turning with the turret (his eye if it has none).
func sight_origin() -> Vector3:
	var g := vehicle.gunnery
	if g and not g.sight_for(g.gunner_seat()).is_empty():
		return g.sight_from(g.gunner_seat())
	var i := vehicle.modules.index_of("gunner_sight")
	var box: Variant = vehicle.modules.mods[i].box if i >= 0 else null
	if box is AABB and vehicle.turret:
		return vehicle.global_transform * vehicle.turret.carry((box as AABB).get_center())
	return vehicle.seat_eye_point(maxi(vehicle.gun_seats()[0] if not vehicle.gun_seats().is_empty() else 0, 0))


# --- Host: every tick -----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if vehicle == null or not _is_host() or vehicle.wrecked:
		return
	var now := Soldier._now()
	_track(delta, now)
	_reconcile_racks()
	_battery(delta)
	for m: Dictionary in mounts:
		match String(m.kind):
			CANNON:
				_cannon_step(m, now)
			AUTOCANNON:
				_autocannon_step(m, now)
			ATGM:
				_atgm_step(m, now)
	if _dirty:
		_publish()


## The turret's slew rate (the TOW's wire) and the sight line's last second (SACLOS's lag).
func _track(delta: float, now: float) -> void:
	var t := vehicle.turret
	if t == null:
		return
	if not is_nan(_yaw_prev) and delta > 0.0:
		_yaw_dps = rad_to_deg(absf(wrapf(t.yaw - _yaw_prev, -PI, PI))) / delta
	_yaw_prev = t.yaw
	if mounts.any(func(m: Dictionary) -> bool: return String(m.kind) == ATGM and int(state[m.id].g) != 0):
		_sight.append([now, sight_origin(), sight_line()])
		while not _sight.is_empty() and now - float(_sight[0][0]) > SIGHT_KEEP_S:
			_sight.pop_front()
	elif not _sight.is_empty():
		_sight.clear()


## The turret on batteries, then by hand, after the engine dies (BATTERY_TURRET_S).
func _battery(delta: float) -> void:
	var engine_out := vehicle.modules.authored and vehicle.modules.state("engine") == VehicleModules.DESTROYED
	_engine_out_s = _engine_out_s + delta if engine_out else 0.0
	var manual := _engine_out_s > BATTERY_TURRET_S
	if manual != _manual:
		_manual = manual
		vehicle.modules.set_turret_manual(manual)
		_dirty = true


func _quiet(now: float) -> bool:
	return now - _last_contact >= QUIET_S


func _stopped() -> bool:
	return vehicle.linear_velocity.length() < STOPPED_MPS


func _cannon_step(m: Dictionary, now: float) -> void:
	var st: Dictionary = state[m.id]
	var cy := String(st.cy)
	if cy != "":
		var who := _able_at(int(st.by))
		if who == null or (cy == "restock" and not _turret_front()) or (cy in ["load", "short"] and _breech_out(m)):
			_abort(m, st)
			return
		if now >= float(st.end):
			_finish(m, st)
		return
	if String(st.l) == "" and not _breech_out(m) and _pick_ammo(m, String(st.n)) != "":
		var loader := _able_at(int(m.loader_seat))
		if loader:
			if loader.is_ai():
				_start_load(m, st, int(m.loader_seat), loader, now)
			return  # a player loader starts it on his key (server_load_press)
		for seat: int in [int(m.commander_seat), int(m.seat)]:
			var s := _able_at(seat)
			if s:
				_start_load(m, st, seat, s, now)  # short-crewed (2.5.1)
				return
		return
	# Between fights, the loader restocks the bustle from the hull (or when told, or the gun's
	# empty with nothing left in the bustle).
	var ai_loader := _able_at(int(m.loader_seat))
	var bustle := String((m.racks as Array)[0]) if not (m.racks as Array).is_empty() else ""
	var dry := String(st.l) == "" and bustle != "" and rack_total(bustle) == 0
	if ai_loader and (int(st.rs) > 0 or (ai_loader.is_ai() and (_quiet(now) or dry))) and _turret_front():
		if bustle != "" and (int(st.rs) > 0 or rack_total(bustle) < RESTOCK_BELOW) and rack_total(bustle) < _capacity(bustle):
			var sid := _restock_pick(m, bustle)
			if sid != "":
				_take_from(String(_stowage_rack(m, sid)), sid)
				st.cy = "restock"
				st.by = int(m.loader_seat)
				st.am = sid
				st.t0 = now
				st.end = now + RESTOCK_S
				st.rs = maxi(int(st.rs) - 1, 0)
				_dirty = true


func _breech_out(m: Dictionary) -> bool:
	return vehicle.modules.authored and vehicle.modules.health_of("breech") <= 0.0001 and "breech" in m.modules


func _turret_front() -> bool:
	return vehicle.turret == null or absf(rad_to_deg(wrapf(vehicle.turret.yaw, -PI, PI))) <= RESTOCK_FRONT_DEG


## Starts a load of mount `m` by seat `seat` (`s` in it): the next round it can reach, pulled out
## of its rack now (the doors open until the pull's done).
func _start_load(m: Dictionary, st: Dictionary, seat: int, s: Soldier, now: float) -> bool:
	var sid := _pick_ammo(m, String(st.n))
	if sid == "":
		return false
	var rack := _take(m, sid, true)
	var slow := BREECH_SLOW if _module_damaged(m, "breech") else 1.0
	var total := load_time(m, seat, s)
	st.cy = "load" if seat == int(m.loader_seat) else "short"
	st.by = seat
	st.am = sid
	st.rk = rack
	st.t0 = now
	st.pull = now + PULL_S * slow
	st.end = now + total
	st.pl = not s.is_ai() and seat == int(m.loader_seat)
	st.ok = false
	st.w0 = float(st.pull)
	st.w1 = float(st.pull) + RAM_WINDOW_S * slow
	_dirty = true
	return true


func _finish(m: Dictionary, st: Dictionary) -> void:
	match String(st.cy):
		"load", "short":
			st.l = String(st.am)
		"unload":
			_put(m, String(st.l))
			st.l = ""
		"restock":
			_put(m, String(st.am))
	st.cy = ""
	st.am = ""
	st.by = -1
	_dirty = true


## A cycle stopped part-way (the man who was doing it went down or left, the turret moved off the
## front, the breech went): the round in his hands goes back.
func _abort(m: Dictionary, st: Dictionary) -> void:
	match String(st.cy):
		"load", "short":
			_put(m, String(st.am))
		"restock":
			_put_stowage(m, String(st.am))
	st.cy = ""
	st.am = ""
	st.by = -1
	_dirty = true


## The round mount `m` loads next: `want` if a rack it reaches has one, else the first of its
## gun's rounds that's there ("" none).
func _pick_ammo(m: Dictionary, want: String) -> String:
	if want != "" and ready_of(m, want) > 0:
		return want
	for sid: Variant in m.g.get("ammo", []):
		if ready_of(m, String(sid)) > 0:
			return String(sid)
	return ""


## Takes a round of `sid` out of the first of `m`'s racks that has one; its rack id. `publish`:
## the module's total follows at once.
func _take(m: Dictionary, sid: String, publish := true) -> String:
	for r: Variant in _ready_racks(m):
		if int((racks.get(String(r), {}) as Dictionary).get(sid, 0)) > 0:
			_take_from(String(r), sid, publish)
			return String(r)
	return ""


func _take_from(rack: String, sid: String, publish := true) -> void:
	var c: Dictionary = racks.get(rack, {})
	c[sid] = maxi(int(c.get(sid, 0)) - 1, 0)
	racks[rack] = c
	if publish:
		_sync_rack(rack)
	_dirty = true


## A round of `sid` back into `m`'s first rack with room (or its first).
func _put(m: Dictionary, sid: String) -> void:
	if sid == "":
		return
	var list := _ready_racks(m)
	if list.is_empty():
		return
	var to := String(list[0])
	for r: Variant in list:
		if rack_total(String(r)) < _capacity(String(r)):
			to = String(r)
			break
	var c: Dictionary = racks.get(to, {})
	c[sid] = int(c.get(sid, 0)) + 1
	racks[to] = c
	_sync_rack(to)
	_dirty = true


func _put_stowage(m: Dictionary, sid: String) -> void:
	if sid == "" or (m.stowage as Array).is_empty():
		return
	var to := String(m.stowage[0])
	var c: Dictionary = racks.get(to, {})
	c[sid] = int(c.get(sid, 0)) + 1
	racks[to] = c
	_sync_rack(to)
	_dirty = true


## A rack's room: its module's full count (data/vehicle_modules.json "rounds").
func _capacity(rack: String) -> int:
	var i := vehicle.modules.index_of(rack)
	return int(vehicle.modules.mods[i].rounds) if i >= 0 else 0


## The stowage rack holding a round of `sid` for mount `m` ("" none).
func _stowage_rack(m: Dictionary, sid: String) -> String:
	for r: Variant in m.stowage:
		if int((racks.get(String(r), {}) as Dictionary).get(sid, 0)) > 0:
			return String(r)
	return ""


## Which round to bring up from the hull into `bustle`: the kind furthest below its share of the
## default load-out that the stowage has.
func _restock_pick(m: Dictionary, bustle: String) -> String:
	var want: Dictionary = default_racks(vehicle.spec).get(bustle, {})
	var best := ""
	var gap := -INF
	for sid: Variant in m.g.get("ammo", []):
		if _stowage_rack(m, String(sid)) == "":
			continue
		var g := float(want.get(String(sid), 0)) - float((racks.get(bustle, {}) as Dictionary).get(String(sid), 0))
		if g > gap:
			gap = g
			best = String(sid)
	return best


func _autocannon_step(m: Dictionary, now: float) -> void:
	var st: Dictionary = state[m.id]
	if float(st.rf) > 0.0:
		var ok := _stopped() and _able_at(int(m.seat)) != null and _able_at(int(st.rb)) != null and _last_contact <= float(st.rf) - REFILL_S
		if not ok:
			st.rf = 0.0
			st.rb = -1
			_dirty = true
		elif now >= float(st.rf):
			_refill_boxes(m)
			st.rf = 0.0
			st.rb = -1
			_dirty = true
		return
	# Out of a box: the gunner and a dismount refill both from the stowage, stopped and quiet.
	var empty := false
	for feed: String in ["ap", "he"]:
		var sid := _feed_shell(m, feed)
		if sid != "" and ready_of(m, sid) <= 0 and _stowage_rack(m, sid) != "":
			empty = true
	if empty and _quiet(now):
		server_refill(null)


## The shell feed `feed` ("ap", "he") of the M242 takes: of its rounds (the M919 only with its
## ammo package fitted), the first in the ready box, else the first stowed, else the first.
func _feed_shell(m: Dictionary, feed: String) -> String:
	var packages: Array = vehicle.get_meta(ArmourModel.META_PACKAGES, [])
	var list: Array = ((m.g.get("feeds", {}) as Dictionary).get(feed, []) as Array).filter(
		func(sid: Variant) -> bool: return String(sid) != "m919" or "m919" in packages)
	for sid: Variant in list:
		if ready_of(m, String(sid)) > 0:
			return String(sid)
	for sid: Variant in list:
		if _stowage_rack(m, String(sid)) != "":
			return String(sid)
	return String(list[0]) if not list.is_empty() else ""


func _refill_boxes(m: Dictionary) -> void:
	var box: Dictionary = m.g.get("box", {})
	var ready := String(m.ready)
	for feed: String in ["ap", "he"]:
		var sid := _feed_shell(m, feed)
		if sid == "":
			continue
		var cap := int(box.get(feed, 0))
		while ready_of(m, sid) < cap:
			var from := _stowage_rack(m, sid)
			if from == "":
				break
			_take_from(from, sid)
			var c: Dictionary = racks.get(ready, {})
			c[sid] = int(c.get(sid, 0)) + 1
			racks[ready] = c
	_sync_rack(ready)


func _atgm_step(m: Dictionary, now: float) -> void:
	var st: Dictionary = state[m.id]
	var moving := vehicle.linear_velocity.length() > TOW_MOVE_MPS
	if String(st.p) != "down" and moving:
		st.p = "down"  # moving lowers it (2.7.3)
		_dirty = true
	if String(st.p) == "raising" and now >= float(st.u):
		st.p = "up"
		_dirty = true
	if int(st.g) != 0:
		var launchers := Launchers.of(vehicle)
		if launchers == null or not launchers.projectiles.has(int(st.g)):
			st.g = 0
			_dirty = true
	if float(st.rl) > 0.0:
		var who := _able_at(int(st.rb))
		if who == null or String(st.p) != "down" or moving:
			_put_stowage(m, String(m.g.get("missile", "")))
			st.rl = 0.0
			st.rb = -1
			_dirty = true
		elif now >= float(st.rl):
			st.rd = int(st.rd) + 1
			st.rl = 0.0
			_dirty = true
			if int(st.rd) < int(m.g.get("ready_max", 2)):
				_start_tow_reload(m, st, who, now)  # the next one
			else:
				st.rb = -1
		return
	# A dismount reloads it on his own when it's down and quiet.
	if int(st.rd) < int(m.g.get("ready_max", 2)) and String(st.p) == "down" and not moving and _quiet(now):
		for i in vehicle.seat_count():
			var s := _able_at(i)
			if s and s.is_ai() and vehicle.is_rider(i):
				_start_tow_reload(m, st, s, now)
				break


func _start_tow_reload(m: Dictionary, st: Dictionary, s: Soldier, now: float) -> bool:
	var sid := String(m.g.get("missile", ""))
	var from := _stowage_rack(m, sid)
	if from == "":
		return false
	_take_from(from, sid)
	st.rl = now + TOW_RELOAD_S
	st.rb = vehicle.seat_of(s)
	_dirty = true
	return true


# --- Host: the racks' rounds against the modules' totals --------------------------------------------

## The modules' rack counts are the truth for how many (hits lose rounds there: A2, a vent empties
## the bustle); which kinds go first follows: the most numerous kind loses one at a time. A count
## that grew (a reset, a save without kinds) fills by the default mix.
func _reconcile_racks() -> void:
	var mods := vehicle.modules
	for rack: String in racks:
		var i := mods.index_of(rack)
		if i < 0 or not mods.rounds.has(i):
			continue
		var want := int(mods.rounds[i])
		var have := rack_total(rack)
		if want == have:
			continue
		var c: Dictionary = racks[rack]
		var def: Dictionary = default_racks(vehicle.spec).get(rack, {})
		while have > want:
			var most := ""
			for sid: String in c:
				if int(c[sid]) > 0 and (most == "" or int(c[sid]) > int(c[most]) or (int(c[sid]) == int(c[most]) and sid < most)):
					most = sid
			if most == "":
				break
			c[most] = int(c[most]) - 1
			have -= 1
		while have < want and not def.is_empty():
			var short := ""
			var gap := -INF
			for sid: String in def:
				var g := float(def[sid]) / maxf(float(_sum(def)), 1.0) * float(want) - float(c.get(sid, 0))
				if g > gap:
					gap = g
					short = sid
			c[short] = int(c.get(short, 0)) + 1
			have += 1
		racks[rack] = c
		_dirty = true


static func _sum(d: Dictionary) -> int:
	var n := 0
	for k: Variant in d:
		n += int(d[k])
	return n


## The module's total follows the rack's rounds.
func _sync_rack(rack: String) -> void:
	vehicle.modules.server_set_rounds(rack, rack_total(rack))


# --- Host: actions (players' requests, A9's AI, tests) ----------------------------------------------

## Host: every rack back to its default load-out, the modules' totals with them.
func server_reset_racks() -> void:
	racks = default_racks(vehicle.spec)
	for rack: String in racks:
		_sync_rack(rack)
	_dirty = true


## Host (A8's hook): `n` rounds of `shell_id` stowed in rack `rack_id`, up to its room. How many went in.
func server_stow(rack_id: String, shell_id: String, n: int) -> int:
	var put := clampi(_capacity(rack_id) - rack_total(rack_id), 0, maxi(n, 0))
	if put > 0:
		var c: Dictionary = racks.get(rack_id, {})
		c[shell_id] = int(c.get(shell_id, 0)) + put
		racks[rack_id] = c
		_sync_rack(rack_id)
		_dirty = true
	return put


## Host (Vehicle.server_rearm; the motor pool): racks full, the TOW's launcher full, the main
## gun loaded. Returns the cupola and pintle guns' feeds to top up in the hold: [[feed, load]].
func server_rearm() -> Array:
	server_reset_racks()
	var out: Array = []
	for m: Dictionary in mounts:
		var st: Dictionary = state[m.id]
		match String(m.kind):
			CANNON:
				if String(st.l) == "" and String(st.cy) == "" and String(m.battlecarry) != "":
					st.l = String(m.battlecarry)
				if String(st.l) != "":
					_take(m, String(st.l))  # the round in the breech is one of the load-out's
			ATGM:
				st.rd = int(m.g.get("ready_max", 2))
			MG:
				if not bool(m.legacy) and m.g.has("feed"):
					out.append([StringName(m.g.feed), int(m.g.get("load", 0))])
	_dirty = true
	_publish()
	return out


## Host: `shooter` fires mount `id` ("" his seat's selected one), along `direction` (a cupola or
## pintle gun: where he aims; the turret's guns fire along their barrel). Returns {"ok", "why",
## "shell" or "missile" (ids), "result" (an MG round's Ballistics result)}.
func server_fire(shooter: Soldier, id := "", direction := Vector3.ZERO) -> Dictionary:
	if id == "":
		id = String(selected.get(vehicle.seat_of(shooter), ""))
	var why := can_fire(shooter, id)
	if why != "":
		return {"ok": false, "why": why}
	var m := mount(id)
	var st: Dictionary = state[id]
	var now := Soldier._now()
	if now < float(_next.get(id, 0.0)):
		return {"ok": false, "why": "Cycling"}
	shooter.server_end_spawn_protection()  # firing ends spawn protection (Soldier)
	_last_contact = now
	match String(m.kind):
		CANNON:
			return _fire_shell(m, shooter, String(st.l), now, true)
		AUTOCANNON:
			var sid := _feed_shell(m, String(st.f))
			var rpm := float((m.g.get("rates_rpm", {}) as Dictionary).get(String(st.r), 100.0))
			_next[id] = now + (60.0 / rpm if rpm > 0.0 else 0.25) + _jam(m)
			return _fire_shell(m, shooter, sid, now, false)
		ATGM:
			return _fire_missile(m, shooter, st)
		MG:
			if bool(m.legacy):
				var res := vehicle.server_fire_gun(shooter, direction)
				return {"ok": not res.is_empty(), "why": "" if not res.is_empty() else "Can't fire", "result": res}
			return _fire_mg(m, shooter, direction, now)
	return {"ok": false, "why": "Can't fire"}


func _fire_shell(m: Dictionary, shooter: Soldier, sid: String, now: float, breech: bool) -> Dictionary:
	var row := Shells.shell(sid)
	var flight := ShellFlight.of(vehicle)
	if row.is_empty() or flight == null:
		return {"ok": false, "why": "Can't fire"}
	var st: Dictionary = state[m.id]
	if breech:
		st.l = ""
	else:
		_take(m, sid)
	_shot_n += 1
	var seed := hash([String(vehicle.name), _shot_n])
	var origin := muzzle(String(m.id))
	var g := vehicle.gunnery
	var spread := float(m.g.get("spread_mil", 0.3)) * (BARREL_SPREAD if _module_damaged(m, "barrel") else 1.0)
	if g:
		spread = sqrt(spread * spread + pow(g.jitter_mil(), 2.0))  # A4: the stabiliser's jitter (or firing unstabilised on the move)
	var dir := _scatter(barrel(), spread * MIL, seed)
	var vel := dir * float(row.get("muzzle_mps", 1000.0)) + (g.own_velocity() if g else vehicle.linear_velocity)
	var opts := {"vehicle": vehicle, "shot_id": seed}
	if String(st.get("fz", "")) != "":
		opts["fuze_mode"] = String(st.fz)
	if float(st.get("ab", 0.0)) > 0.0:
		opts["airburst_m"] = float(st.ab)
	if g:
		opts.merge(g.fuze_for(sid), true)  # A4: the fuze set for this round, airburst at the lased range
	var id := flight.server_fire(StringName(sid), origin, vel, shooter, opts)
	Sfx.server_shot(origin, origin + dir * 800.0, String(m.g.get("sound", "hmg")))
	PeopleLayer.server_noise(shooter, origin, PeopleLayer.BLAST_HEARD_M)
	_dirty = true
	return {"ok": id != 0, "why": "" if id != 0 else "Can't fire", "shell": id, "round": sid}


## `dir` scattered within a cone of `spread` radians by `seed` (the same on a replay).
static func _scatter(dir: Vector3, spread: float, seed: int) -> Vector3:
	if spread <= 0.0:
		return dir.normalized()
	var a := ArmourModel.roll(seed, 41) * TAU
	var r := sqrt(ArmourModel.roll(seed, 42)) * spread
	var side := dir.cross(Vector3.UP).normalized() if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT
	var lift := side.cross(dir).normalized()
	return (dir.normalized() + (side * cos(a) + lift * sin(a)) * tan(r)).normalized()


func _fire_missile(m: Dictionary, shooter: Soldier, st: Dictionary) -> Dictionary:
	var launchers := Launchers.of(vehicle)
	var w := StringName(m.g.get("missile", ""))
	var d := Warheads.data(w)
	if launchers == null or d.is_empty():
		return {"ok": false, "why": "Can't fire"}
	var origin := muzzle(String(m.id))
	var dir := barrel()
	var p := launchers.server_launch(shooter, w, origin, dir * float(d.get("speed_mps", 70.0)), "saclos")
	if p == null:
		return {"ok": false, "why": "Can't fire"}
	p.guide = self
	p.launch_pos = origin
	p.exclude.append(vehicle.get_rid())
	for s: Soldier in vehicle.occupants():
		p.exclude.append_array(Launchers._rids_of(s))
	st.rd = int(st.rd) - 1
	st.g = launchers.last_id
	_sight.clear()
	_sight.append([Soldier._now(), sight_origin(), sight_line()])
	PeopleLayer.server_noise(shooter, origin, PeopleLayer.BLAST_HEARD_M)
	_dirty = true
	print("[weapons] %s fired a %s from the %s" % [shooter.display_name(), Launchers.warhead_name(w), vehicle.display_name()])
	return {"ok": true, "why": "", "missile": launchers.last_id}


func _fire_mg(m: Dictionary, shooter: Soldier, direction: Vector3, now: float) -> Dictionary:
	var g: Dictionary = m.g
	var item := VehicleSpecs.gun_item(String(m.gun))
	if item == null or vehicle.cargo_hold == null:
		return {"ok": false, "why": "Can't fire"}
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else barrel()
	var local := vehicle.global_basis.inverse() * dir
	var pitch := rad_to_deg(asin(clampf(local.y, -1.0, 1.0)))
	if pitch < CUPOLA_PITCH.x or pitch > CUPOLA_PITCH.y:
		return {"ok": false, "why": "Out of its arc"}
	if not vehicle.cargo_hold.take_feed(StringName(g.get("feed", ""))):
		return {"ok": false, "why": "No ammunition"}
	_next[m.id] = now + 60.0 / float(g.get("rpm", 600.0)) + _jam(m)
	var res := vehicle.fire_mg_round(shooter, item, String(g.get("sound", "rifle")), muzzle(String(m.id)), dir,
		deg_to_rad(float(g.get("spread_deg", 0.3))) * (BARREL_SPREAD if _module_damaged(m, "barrel") else 1.0))
	return {"ok": true, "why": "", "result": res}


## Host: what seat `seat` fires with its fire key.
func server_select(seat: int, id: String) -> bool:
	var m := mount(id)
	if m.is_empty() or int(m.seat) != seat and not (seat == int(m.commander_seat) and String(m.turret) in ["main", "ring"]):
		return false
	selected[seat] = id
	_dirty = true
	_publish()
	return true


## Host: the main gun's next round to load (`shell_id`, one of its gun's).
func server_select_ammo(id: String, shell_id: String) -> bool:
	var m := mount(id)
	if m.is_empty() or String(m.kind) != CANNON or not shell_id in (m.g.get("ammo", []) as Array):
		return false
	state[id].n = shell_id
	_dirty = true
	_publish()
	return true


## Host: the next of the main gun's rounds after its present choice (a key cycles them).
func server_cycle_ammo(id: String) -> String:
	var m := mount(id)
	var list: Array = m.get("g", {}).get("ammo", [])
	if list.is_empty():
		return ""
	var at := list.find(String(state[id].n))
	var next := String(list[(at + 1) % list.size()])
	server_select_ammo(id, next)
	return next


## Host: the main gun's fuze mode (M830A1 "air", M1147 "delay" / "airburst"; "" its default) and
## an airburst's range (m). A4's fire control sets the range from the laser.
func server_set_fuze(id: String, mode: String, airburst_m := 0.0) -> void:
	if state.has(id):
		state[id].fz = mode
		state[id].ab = maxf(airburst_m, 0.0)
		_dirty = true


## Host: a player loader's key on mount `id`: the first press starts the cycle (pull, the doors
## open), the second in the ram window gives the fast load. Returns what happened: "started",
## "rammed", "early", "late", "" (nothing to do).
func server_load_press(s: Soldier, id := "main") -> String:
	var m := mount(id)
	if m.is_empty() or String(m.kind) != CANNON or vehicle.seat_of(s) != int(m.loader_seat) or not _at_job(s, {"seat": m.loader_seat, "commander_seat": -1, "turret": ""}):
		return ""
	var st: Dictionary = state[id]
	var now := Soldier._now()
	if String(st.cy) == "" and String(st.l) == "" and not _breech_out(m):
		return "started" if _start_load(m, st, int(m.loader_seat), s, now) else ""
	if String(st.cy) != "load" or not bool(st.pl) or bool(st.ok):
		return ""
	if now < float(st.w0):
		st.pl = false  # too early: the slow ram
		_dirty = true
		return "early"
	if now <= float(st.w1):
		st.ok = true
		var slow := BREECH_SLOW if _module_damaged(m, "breech") else 1.0
		st.end = float(st.t0) + PLAYER_FAST_S * slow
		_dirty = true
		return "rammed"
	return "late"


## Host: the round in the breech comes out and goes back to the bustle (8 s), so the next choice
## loads (the loader, or short-crewed the commander or gunner: `s`).
func server_unload(s: Soldier, id := "main") -> bool:
	var m := mount(id)
	if m.is_empty() or String(m.kind) != CANNON:
		return false
	var st: Dictionary = state[id]
	var seat := vehicle.seat_of(s)
	if String(st.l) == "" or String(st.cy) != "" or _able_at(seat) == null or not seat in [int(m.loader_seat), int(m.commander_seat), int(m.seat)]:
		return false
	if seat != int(m.loader_seat) and _able_at(int(m.loader_seat)):
		seat = int(m.loader_seat)  # the loader does it
	st.cy = "unload"
	st.by = seat
	st.t0 = Soldier._now()
	st.end = st.t0 + UNLOAD_S
	_dirty = true
	return true


## Host: the loader brings `n` rounds up from the hull into the bustle (12 s each, the turret
## within RESTOCK_FRONT_DEG of the front).
func server_restock(n := 1, id := "main") -> void:
	if state.has(id):
		state[id].rs = int(state[id].rs) + maxi(n, 0)


## Host: the M242's other feed (AP, HE): 1.5 s (x1.5 with a damaged breech) with no fire.
func server_switch_feed(id := "main") -> String:
	var m := mount(id)
	if m.is_empty() or String(m.kind) != AUTOCANNON:
		return ""
	var st: Dictionary = state[id]
	st.f = "he" if String(st.f) == "ap" else "ap"
	st.sw = Soldier._now() + FEED_SWITCH_S * (BREECH_SLOW if _module_damaged(m, "breech") else 1.0)
	_dirty = true
	_publish()
	return String(st.f)


## Host: the M242's rate: "single", "low" or "high" ("" the next one).
func server_set_rate(rate := "", id := "main") -> String:
	var m := mount(id)
	if m.is_empty() or String(m.kind) != AUTOCANNON:
		return ""
	var rates: Array = (m.g.get("rates_rpm", {}) as Dictionary).keys()
	var st: Dictionary = state[id]
	st.r = rate if rate in rates else String(rates[(rates.find(String(st.r)) + 1) % rates.size()])
	_dirty = true
	_publish()
	return String(st.r)


## Host: the gunner and a dismount refill the ready boxes from the hull (REFILL_S), stopped and
## quiet. `s`: who asked (any of the two), or null (the crew on its own). Why not ("" started).
func server_refill(s: Soldier, id := "main") -> String:
	var m := mount(id)
	if m.is_empty() or String(m.kind) != AUTOCANNON:
		return "No ready boxes"
	var st: Dictionary = state[id]
	if float(st.rf) > 0.0:
		return "Refilling"
	if not _stopped():
		return "Stop first"
	if not _quiet(Soldier._now()) and s == null:
		return "In contact"
	if _able_at(int(m.seat)) == null:
		return "Nobody on the gun"
	var helper := -1
	for i in vehicle.seat_count():
		if vehicle.is_rider(i) and _able_at(i) != null:
			helper = i
			break
	if helper < 0:
		return "No dismount to help"
	st.rf = Soldier._now() + REFILL_S
	st.rb = helper
	_dirty = true
	return ""


## Host: the TOW's launcher up (TOW_RAISE_S, at a halt) or down (at once).
func server_raise(up: bool, id := "tow") -> String:
	var m := mount(id)
	if m.is_empty() or String(m.kind) != ATGM:
		return "No launcher"
	var st: Dictionary = state[id]
	if not up:
		st.p = "down"
	elif String(st.p) == "down":
		if vehicle.linear_velocity.length() > TOW_MOVE_MPS:
			return "Stop first"
		if not mount_ok(id):
			return "The launcher is out"
		st.p = "raising"
		st.u = Soldier._now() + TOW_RAISE_S
	_dirty = true
	_publish()
	return ""


## Host: `s` (a dismount, or the commander) reloads the TOW from the hull: the launcher down, the
## vehicle stopped, 45 s a missile out of the roof hatch. Why not ("" started).
func server_reload_tow(s: Soldier, id := "tow") -> String:
	var m := mount(id)
	if m.is_empty() or String(m.kind) != ATGM:
		return "No launcher"
	var st: Dictionary = state[id]
	var seat := vehicle.seat_of(s)
	if _able_at(seat) == null or not (vehicle.is_rider(seat) or seat == int(m.commander_seat)):
		return "From the troop compartment"
	if float(st.rl) > 0.0:
		return "Reloading"
	if String(st.p) != "down":
		return "Lower the launcher first"
	if vehicle.linear_velocity.length() > TOW_MOVE_MPS:
		return "Stop first"
	if int(st.rd) >= int(m.g.get("ready_max", 2)):
		return "The launcher's full"
	return "" if _start_tow_reload(m, st, s, Soldier._now()) else "No missiles stowed"


## Host (LauncherProjectile's SACLOS guide): the line the missile `missile_id` at `pos`, `flown`
## metres out, flies to: {"ok", "from", "dir"} (the gunner's sight line WIRE_LAG_S ago), or
## {"ok": false, "why"} when the wire breaks.
func saclos_line(missile_id: int, pos: Vector3, flown: float) -> Dictionary:
	var m := {}
	for x: Dictionary in mounts:
		if String(x.kind) == ATGM and int(state[x.id].g) == missile_id:
			m = x
	if m.is_empty() or vehicle.wrecked:
		return {"ok": false, "why": "the launcher's gone"}
	var st: Dictionary = state[m.id]
	var why := ""
	if String(st.p) != "up":
		why = "the launcher came down"
	elif not mount_ok(String(m.id)):
		why = "the launcher was hit"
	elif _able_at(int(m.seat)) == null and _able_at(int(m.commander_seat)) == null:
		why = "nobody on the sight"
	elif flown > float(Warheads.data(StringName(m.g.get("missile", ""))).get("wire_m", 3750.0)):
		why = "out of wire"
	elif _yaw_dps > WIRE_BREAK_DPS:
		why = "the turret slewed too fast"
	var sample: Array = _sight.front() if not _sight.is_empty() else [Soldier._now(), sight_origin(), sight_line()]
	var now := Soldier._now()
	for x: Array in _sight:
		if now - float(x[0]) >= WIRE_LAG_S:
			sample = x
	if why == "" and SmokeCloud.blocks(sample[1], pos):
		why = "smoke on the line"
	if why != "":
		st.g = 0
		_dirty = true
		return {"ok": false, "why": why}
	return {"ok": true, "from": sample[1], "dir": sample[2]}


# --- The local player's keys (every peer) ---------------------------------------------------------

## The local player `me` in seat `seat` (`free`: the mouse is his): his seat's mounts take the
## keys (weapon 1-3 pick one, fire, fire mode cycles the round or the rate, reload: the loader's
## key, the feed switch, the launcher up or down, a dismount's TOW reload). True when the fire
## key is theirs (the vehicle's own gun then doesn't fire).
func local_controls(me: Soldier, seat: int, free: bool) -> bool:
	var mine := mounts_for(seat)
	var commander := mounts.filter(func(m: Dictionary) -> bool: return int(m.commander_seat) == seat and String(m.turret) in ["main", "ring"])
	var tow := mounts.filter(func(m: Dictionary) -> bool: return String(m.kind) == ATGM)
	var loader := mounts.filter(func(m: Dictionary) -> bool: return int(m.loader_seat) == seat)
	if mine.is_empty() and commander.is_empty() and loader.is_empty() and (tow.is_empty() or not vehicle.is_rider(seat)):
		return false
	var sel := String((net_state.get("s", {}) as Dictionary).get(seat, (net_state.get("s", {}) as Dictionary).get(str(seat), "")))
	var m := mount(sel)
	if free:
		var picks := mine.filter(func(x: Dictionary) -> bool: return not bool(x.legacy)) + commander
		if Input.is_action_just_pressed(&"weapon_primary") and not picks.is_empty():
			request.rpc_id(1, "select", String(picks[0].id))
		elif Input.is_action_just_pressed(&"weapon_sidearm"):
			var coax := mine.filter(func(x: Dictionary) -> bool: return bool(x.legacy))
			if not coax.is_empty():
				request.rpc_id(1, "select", String(coax[0].id))
		elif Input.is_action_just_pressed(&"weapon_launcher"):
			var atgm := picks.filter(func(x: Dictionary) -> bool: return String(x.kind) == ATGM)
			if not atgm.is_empty():
				request.rpc_id(1, "select", String(atgm[0].id))
		if Input.is_action_just_pressed(&"fire_mode") and not m.is_empty():
			request.rpc_id(1, "mode", sel)
		if Input.is_action_just_pressed(&"reload"):
			if not loader.is_empty():
				request.rpc_id(1, "load", String(loader[0].id))
			elif vehicle.is_rider(seat) and not tow.is_empty():
				request.rpc_id(1, "tow_reload", String(tow[0].id))
			elif not m.is_empty():
				request.rpc_id(1, "reload", sel)
	if m.is_empty() or bool(m.legacy):
		return not loader.is_empty() or vehicle.is_rider(seat)  # a loader's or a rider's keys are all here; the gunner's coax is the vehicle's
	if free and Input.is_action_pressed(&"fire"):
		var auto := String(m.kind) == MG or (String(m.kind) == AUTOCANNON and String(_view(sel).get("r", "low")) != "single")
		if (auto or Input.is_action_just_pressed(&"fire")) and Soldier._now() >= _local_next:
			var rpm := float(m.g.get("rpm", 600.0)) if String(m.kind) == MG else float((m.g.get("rates_rpm", {}) as Dictionary).get(String(_view(sel).get("r", "low")), 100.0))
			_local_next = Soldier._now() + (60.0 / rpm if auto and rpm > 0.0 else 0.2)
			request_fire.rpc_id(1, sel, vehicle.gun_direction(me))
	return true


## A player's action on this vehicle's mounts: "select", "mode" (the next round or rate),
## "reload" (the feed switch, the launcher up or down, unload), "load" (the loader's key),
## "tow_reload", "unload", "refill".
@rpc("any_peer", "call_local", "reliable")
func request(action: String, id: String) -> void:
	if not multiplayer.is_server():
		return
	var s := vehicle._sender()
	var seat := vehicle.seat_of(s)
	if s == null or seat < 0 or not s.vitals.is_up():
		return
	var m := mount(id)
	match action:
		"select":
			server_select(seat, id)
		"mode":
			if String(m.get("kind", "")) == CANNON:
				var next := server_cycle_ammo(id)
				vehicle._tell(s, "Next round: %s" % short_name(next))
			elif String(m.get("kind", "")) == AUTOCANNON:
				vehicle._tell(s, "Rate: %s" % server_set_rate("", id))
		"reload":
			match String(m.get("kind", "")):
				AUTOCANNON:
					if seat == int(m.seat) or seat == int(m.commander_seat):
						vehicle._tell(s, "Feed: %s" % server_switch_feed(id).to_upper())
				ATGM:
					var why := server_raise(String(state[id].p) == "down", id)
					if why != "":
						vehicle._tell(s, why)
				CANNON:
					if not server_unload(s, id):
						vehicle._tell(s, "Nothing to unload")
		"load":
			var how := server_load_press(s, id)
			if how in ["early", "late"]:
				vehicle._tell(s, "Rammed %s: slow load" % how)
		"tow_reload":
			var why := server_reload_tow(s, id)
			if why != "":
				vehicle._tell(s, why)
		"unload":
			server_unload(s, id)
		"refill":
			var why := server_refill(s, id)
			if why != "":
				vehicle._tell(s, why)
	_publish()


## A player's shot with mount `id` along `direction` (a cupola or pintle gun's aim).
@rpc("any_peer", "call_local", "reliable")
func request_fire(id: String, direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var s := vehicle._sender()
	if s and s.vitals.is_up() and Soldier.usable_direction(direction):
		var r := server_fire(s, id, direction)
		if not bool(r.ok) and String(r.why) not in ["Cycling", ""]:
			vehicle._tell(s, String(r.why))


# --- Readout (every peer) -----------------------------------------------------------------------

## Mount `id`'s published view ({} for none; every peer).
func _view(id: String) -> Dictionary:
	return (net_state.get("m", {}) as Dictionary).get(id, {})


## Seconds left of a published countdown `t` (now, on this peer).
func _left(t: Variant) -> float:
	return maxf(float(t) - (Soldier._now() - _net_at), 0.0)


## The HUD readout's parts for seat `seat` (Vehicle.readout_parts): the mounts it works, what's
## loaded and coming, the racks, the feed and rate, the launcher; a loader's cycle; a seat move.
func readout_parts(seat: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var me := vehicle.occupant(seat)
	var mv := vehicle.move_of(me) if me and _is_host() else Vector2(-1, 0)
	if int(mv.x) >= 0:
		out.append({"text": "Moving to the %s's seat (%d s)" % [vehicle.seat_name(int(mv.x)).to_lower(), ceili(mv.y)], "style": &"warn"})
	var sel := String((net_state.get("s", {}) as Dictionary).get(seat, (net_state.get("s", {}) as Dictionary).get(str(seat), "")))
	for m: Dictionary in mounts:
		var mine := int(m.seat) == seat or (int(m.commander_seat) == seat and String(m.turret) in ["main", "ring"])
		var v := _view(String(m.id))
		var name_ := String(m.g.get("name", m.id))
		var tag := "> " if String(m.id) == sel else ""
		match String(m.kind):
			CANNON:
				if mine:
					var line := "%s%s: %s" % [tag, name_, ("%s up" % short_name(String(v.get("l", "")))) if String(v.get("l", "")) != "" else ("loading %s" % short_name(String(v.get("am", "")))
						if String(v.get("cy", "")) in ["load", "short"] else "empty")]
					out.append({"text": line + ", next %s" % short_name(String(v.get("n", ""))), "style": &"warn" if String(v.get("l", "")) == "" else &""})
					out.append({"text": _rack_line(m), "style": &""})
				if int(m.loader_seat) == seat:
					out.append(_loader_part(m, v))
			AUTOCANNON:
				if mine:
					var ap := _feed_shell(m, "ap")
					var he := _feed_shell(m, "he")
					out.append({"text": "%s%s: %s %d, HE %d, %s feed, %s%s" % [tag, name_, short_name(ap), _ready_net(m, ap), _ready_net(m, he),
						String(v.get("f", "ap")).to_upper(), String(v.get("r", "low")), " (switching)" if _left(v.get("sw", 0.0)) > 0.0 else
						(" (refilling %d s)" % ceili(_left(v.get("rf", 0.0))) if _left(v.get("rf", 0.0)) > 0.0 else "")], "style": &""})
			ATGM:
				if mine:
					out.append({"text": "%sTOW: %d ready, launcher %s%s" % [tag, int(v.get("rd", 0)), String(v.get("p", "down")),
						", guiding" if int(v.get("g", 0)) != 0 else ""], "style": &""})
				if vehicle.is_rider(seat) or mine:
					if _left(v.get("rl", 0.0)) > 0.0:
						out.append({"text": "Reloading the TOW (%d s)" % ceili(_left(v.get("rl", 0.0))), "style": &"warn"})
			MG:
				if int(m.seat) == seat and not bool(m.legacy):
					out.append({"text": "%s%s: %d rounds" % [tag, name_, vehicle.cargo_hold.feed_rounds(StringName(m.g.get("feed", ""))) if vehicle.cargo_hold else 0], "style": &""})
	return out


func _ready_net(m: Dictionary, sid: String) -> int:
	var n := 0
	for r: Variant in _ready_racks(m):
		n += int(((net_state.get("r", {}) as Dictionary).get(String(r), {}) as Dictionary).get(sid, 0))
	return n


func _rack_line(m: Dictionary) -> String:
	var parts: PackedStringArray = []
	for r: Variant in (m.racks as Array) + (m.stowage as Array):
		var c: Dictionary = (net_state.get("r", {}) as Dictionary).get(String(r), {})
		var each: PackedStringArray = []
		for sid: Variant in m.g.get("ammo", []):
			each.append("%d %s" % [int(c.get(String(sid), 0)), short_name(String(sid))])
		parts.append("%s %s" % ["bustle" if String(r).contains("bustle") else ("hull" if String(r).contains("hull") else String(r)), ", ".join(each)])
	return "; ".join(parts)


func _loader_part(m: Dictionary, v: Dictionary) -> Dictionary:
	var key := OS.get_keycode_string(GameSettings.key_for(&"reload"))
	match String(v.get("cy", "")):
		"load":
			if _left(v.get("dp", 0.0)) > 0.0:
				return {"text": "Pulling %s (doors open)" % short_name(String(v.get("am", ""))), "style": &"warn"}
			if bool(v.get("pl", false)) and not bool(v.get("ok", false)) and _left(v.get("w1", 0.0)) > 0.0:
				return {"text": "RAM NOW [%s]" % key, "style": &"warn"}
			return {"text": "Ramming, closing (%.1f s)" % _left(v.get("e", 0.0)), "style": &""}
		"unload":
			return {"text": "Unloading (%d s)" % ceili(_left(v.get("e", 0.0))), "style": &""}
		"restock":
			return {"text": "Restocking from the hull (%d s)" % ceili(_left(v.get("e", 0.0))), "style": &""}
	if String(v.get("l", "")) == "":
		return {"text": "Gun empty: [%s] load %s" % [key, short_name(String(v.get("n", "")))], "style": &"warn"}
	return {"text": "Loaded: %s" % short_name(String(v.get("l", ""))), "style": &""}


# --- Net, saving ----------------------------------------------------------------------------------

func _publish() -> void:
	if not _is_host():
		return
	_dirty = false
	var now := Soldier._now()
	var views := {}
	for m: Dictionary in mounts:
		var st: Dictionary = state[m.id]
		match String(m.kind):
			CANNON:
				views[m.id] = {"l": String(st.l), "n": String(st.n), "cy": String(st.cy), "am": String(st.am), "by": int(st.by),
					"e": snappedf(maxf(float(st.end) - now, 0.0), 0.05) if String(st.cy) != "" else 0.0,
					"dp": snappedf(maxf(float(st.pull) - now, 0.0), 0.05) if String(st.cy) in ["load", "short"] else 0.0,
					"w1": snappedf(maxf(float(st.w1) - now, 0.0), 0.05) if String(st.cy) == "load" else 0.0,
					"pl": bool(st.pl), "ok": bool(st.ok), "fz": String(st.fz)}
			AUTOCANNON:
				views[m.id] = {"f": String(st.f), "r": String(st.r), "sw": snappedf(maxf(float(st.sw) - now, 0.0), 0.05),
					"rf": snappedf(maxf(float(st.rf) - now, 0.0), 0.5) if float(st.rf) > 0.0 else 0.0}
			ATGM:
				views[m.id] = {"p": String(st.p), "rd": int(st.rd), "g": int(st.g),
					"rl": snappedf(maxf(float(st.rl) - now, 0.0), 0.5) if float(st.rl) > 0.0 else 0.0}
	var sel := {}
	for seat: int in selected:
		sel[str(seat)] = String(selected[seat])
	net_state = {"m": views, "r": racks.duplicate(true), "s": sel, "bat": _manual}


## Clients: the published state applied (the racks for readouts; the turret by hand).
func _apply_net() -> void:
	racks = (net_state.get("r", {}) as Dictionary).duplicate(true)
	if vehicle and vehicle.modules:
		vehicle.modules.set_turret_manual(bool(net_state.get("bat", false)))


## JSON-safe state for the zone save: the racks, what's loaded and next, the feeds, the launcher.
func to_save() -> Dictionary:
	var mounts_out := {}
	for m: Dictionary in mounts:
		var st: Dictionary = state[m.id]
		match String(m.kind):
			CANNON:
				mounts_out[m.id] = {"loaded": String(st.l), "next": String(st.n),
					"in_hand": String(st.am) if String(st.cy) in ["load", "short", "restock"] else ""}
			AUTOCANNON:
				mounts_out[m.id] = {"feed": String(st.f), "rate": String(st.r)}
			ATGM:
				mounts_out[m.id] = {"ready": int(st.rd)}
	var sel := {}
	for seat: int in selected:
		sel[str(seat)] = String(selected[seat])
	return {"racks": racks.duplicate(true), "mounts": mounts_out, "selected": sel}


## Puts a to_save() back (an older save without one: the racks by their modules' totals, the
## default mix; battlecarry loaded).
func from_save(data: Dictionary) -> void:
	if data.has("racks") and data.racks is Dictionary:
		racks = default_racks(vehicle.spec)
		for rack: Variant in data.racks:
			if racks.has(String(rack)) and data.racks[rack] is Dictionary:
				var c := {}
				for sid: Variant in data.racks[rack]:
					c[String(sid)] = maxi(int(data.racks[rack][sid]), 0)
				racks[String(rack)] = c
	var mounts_in: Dictionary = data.get("mounts", {}) if data.get("mounts") is Dictionary else {}
	for m: Dictionary in mounts:
		var st: Dictionary = state[m.id]
		var saved: Dictionary = mounts_in.get(String(m.id), {}) if mounts_in.get(String(m.id)) is Dictionary else {}
		if saved.is_empty():
			continue
		match String(m.kind):
			CANNON:
				st.l = String(saved.get("loaded", ""))
				st.n = String(saved.get("next", st.n))
				st.cy = ""
				st.am = ""
				if String(saved.get("in_hand", "")) != "":
					_put(m, String(saved.in_hand))  # a round in the loader's hands goes back to the rack
			AUTOCANNON:
				st.f = String(saved.get("feed", "ap"))
				st.r = String(saved.get("rate", "low"))
			ATGM:
				st.rd = clampi(int(saved.get("ready", st.rd)), 0, int(m.g.get("ready_max", 2)))
	var sel: Dictionary = data.get("selected", {}) if data.get("selected") is Dictionary else {}
	for k: Variant in sel:
		if String(k).is_valid_int() and not mount(String(sel[k])).is_empty():
			selected[int(String(k))] = String(sel[k])
	for rack: String in racks:
		var i := vehicle.modules.index_of(rack)
		if i >= 0 and vehicle.modules.rounds.has(i) and not data.has("racks"):
			continue  # (an older save: _reconcile_racks fits the default mix to the module's count)
		_sync_rack(rack)
	_dirty = true
	_publish()
