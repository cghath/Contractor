class_name HeliCall
extends RefCounted
## One helicopter support under way (wave 5b V3), on the host: what the Black Hawk does from
## the call to leaving the map (or going down). HeliSupports makes and steps them.
##
## Kinds and what happens on the ground:
## - "resupply": lands, sets down a supply pallet with its load (HeliSupports' data: magazines
##   and rounds for the weapons the squad carries, medical items, grenades, smoke), lifts off.
## - "transport" (hot zones): lands at the pickup, the squad gets in (players through the Left
##   Ctrl seats, AI squadmates ordered in: VehicleLayer.server_order_mount; the downed and the
##   carried are loaded), the caller gives the destination (a map marker or a spot; a smoke of
##   its colours near there on arrival takes over), it flies there, lands, the AI get out and it
##   waits for the players to get out, then leaves.
## - "extraction": Extraction's ride. Its landing spot is the extraction point (added or moved
##   there); the squad boards (players, the AI the players chose to bring, the downed and the
##   carried, cuffed or friendly HVTs), items set down inside the point are loaded aboard, and
##   lifting off with everyone aboard ends the deployment (Extraction.server_ride_out). In a
##   campaign it then circles overhead, flying them home, until the level switches to the
##   base; with no campaign to go home to (a dev session) it puts them back down and leaves.
## - "insertion": the squad starts aboard (HeliSupports.server_insert), it flies them to the
##   insertion point, they get out, it leaves.
## On the way: a mark (a grid) sends it straight in; without one it loiters near the players,
## keeping away from where it took fire, until it sees a smoke of its colours (in range and in
## its line of sight). Before landing the spot is tested (LandingZone) and if it can't take a
## landing the nearest safe spot within 100 m is used (Captain); enemy fire never moves the
## landing, but heavy damage on the way in with nobody aboard makes it abort (Proposed).
## Lost (shot down): everyone and everything aboard is lost with it (Helicopter), and that
## support is gone for the rest of the op (HeliSupports.server_lost).
##
## Numbers are Proposed.

enum Phase { INBOUND, LOITER, GROUND, TAKEOFF, CARRY, LIFTING, ENDED, LEAVING, GONE, LOST }

## Helicopters out at once start this far apart (m), and loiter this much wider and higher
## each (by kind: LANE), so they keep out of each other's way.
const SPAWN_SPACING_M := 70.0
const LANE := {"resupply": 0, "transport": 1, "insertion": 1, "extraction": 2}
const LANE_RADIUS_M := 45.0
const LANE_AGL_M := 15.0
## Smoke: seen this far away (m), in the helicopter's line of sight; looked for this often.
const SMOKE_SEE_M := 1500.0
const SMOKE_CHECK_S := 0.5
## Loitering: radius and height of its orbit round the players (m), moved this often, and
## kept AVOID_SHIFT_M further away from where it took fire, for AVOID_S.
const LOITER_RADIUS_M := 400.0
const LOITER_AGL_M := 110.0
const LOITER_UPDATE_S := 2.0
const AVOID_SHIFT_M := 350.0
const AVOID_S := 60.0
## The landing spot is tested again (structures load as people come near) inside this range.
const RECHECK_LZ_M := 450.0
## Abort: hull or a vital zone below these with nobody aboard, on the way in.
const ABORT_HULL := 0.5
const ABORT_ZONE := 0.5
const ABORT_WITHIN_M := 800.0
## Resupply: on the ground this long (s) once the pallet's down.
const UNLOAD_S := 4.0
## Pickup (transport): it waits this long for anyone to board before going home; AI squadmates
## this close to it are ordered in (again every BOARD_ORDER_S); once the destination's given it
## goes with whoever is aboard after BOARD_WAIT_S, or as soon as everyone near is in.
const PICKUP_WAIT_S := 300.0
## Medevac: it lifts this long after the last casualty is aboard (time for the next to be carried up).
const MEDEVAC_LIFT_S := 20.0
## A heli shot down: its crew turn up hurt by the wreck CRASH_SETTLE_S later.
const CRASH_SETTLE_S := 4.0
const CREW_SURVIVORS := 2
## Cargo run: it takes what lies within CARGO_REACH_M of it and lifts after CARGO_WAIT_S.
const CARGO_REACH_M := 15.0
const CARGO_WAIT_S := 150.0
const BOARD_RADIUS_M := 150.0
const BOARD_ORDER_S := 10.0
const BOARD_WAIT_S := 60.0
const PLAYER_NEAR_M := 80.0
## AI ordered in but not aboard after board_direct_s, within BOARD_DIRECT_M, get in at once.
const BOARD_DIRECT_M := 40.0
## Drop-off: the players get out themselves; after DROP_WAIT_S anyone left is put out. It
## leaves DROP_GRACE_S after the last one is out.
const DROP_WAIT_S := 60.0
const DROP_GRACE_S := 2.0
## Loading bodies and the carried (from a door, m), HVTs (from the helicopter) and items.
const LOAD_REACH_M := 4.0
const HVT_REACH_M := 25.0
const LOAD_CHECK_S := 1.0
## Transport: a smoke of its colours this close to the destination takes over the landing.
const DEST_SMOKE_M := 300.0
## Extraction: the deployment ends once it's this high (m) or after LIFT_S.
const LIFT_AGL_M := 6.0
const LIFT_S := 4.0
## A dev extraction (no campaign to switch to) lands them back after this long. In a campaign
## it circles this wide and high over the LZ until the level switches to the base.
const DEV_DROP_S := 5.0
const HOME_ORBIT_M := 600.0
const HOME_ORBIT_AGL_M := 150.0
## If the level still hasn't switched after this long (s), it puts them back down after all.
const HOME_WAIT_S := 120.0
## It's gone this close to its exit (m), after hovering up for TAKEOFF_S.
const EXIT_M := 150.0
## Leaving: at least this long in the air before it is gone (it spawns at its exit, so a heli sent
## home at once would otherwise vanish within a second and a recall find nothing to turn back).
const LEAVE_MIN_S := 8.0
var _leave_at := 0.0
const TAKEOFF_S := 3.0
const TAKEOFF_AGL_M := 8.0
## "Taking fire" goes out at most this often.
const UNDER_FIRE_RADIO_S := 20.0
## Insertion with a route (a contract zone): it flies the legs this low over the terrain (m)
## and counts a waypoint passed within ROUTE_PASS_M. (Captain, 2026-10-14: no higher than 10 m
## on the way in: Helicopter's contour height, as every leg in and out.)
const ROUTE_AGL_M := Helicopter.CRUISE_AGL_M
const ROUTE_PASS_M := 90.0
## Insertion: the players get out themselves; after this long (s) anyone left is put out.
const INSERT_DROP_WAIT_S := 20.0
## Hot LZ (insertion and extraction): within this far of the LZ (m) it looks every HOT_CHECK_S
## for an enemy close by who sees the LZ (DeadGround.hot_watcher, DeadGround.HOT_CLOSE_M), or
## one shooting at it there, and waves off; a new LZ keeps WAVE_OFF_AVOID_M from every LZ
## waved off.
const HOT_CHECK_M := 700.0
const HOT_CHECK_S := 1.0
const WAVE_OFF_AVOID_M := 150.0
## Captain, 2026-10-14 ("not landing": the P0947 insertion waved off LZ after LZ, each seen by one
## sentry 200-320 m off, and landed 550 m from the insertion marker). Proposed: it waves off at
## most WAVE_OFF_MAX times, then puts down at the best LZ it has ("Putting you down, best we've
## got"); an insertion's new LZ stays within INSERT_WAVE_OFF_M of the briefing's insertion point
## (dead ground near it first), INSERT_AVOID_M from the LZs waved off.
const WAVE_OFF_MAX := 2
const INSERT_WAVE_OFF_M := 150.0
const INSERT_AVOID_M := 60.0
## Shot at within this long (s) and this far from the LZ (m): the LZ is hot.
const HOT_FIRE_S := 10.0
const HOT_FIRE_M := 450.0
## A threat known this close to the LZ (m) turns the landing: the doors away from it.
const DOORS_AWAY_M := 800.0
## Extraction wave-off with no other LZ round the squad (DeadGround.SQUAD_RING_M): it looks
## out to this far from them (m) before asking for smoke or a grid (2026-10-14: the loop test's wave-off found none within 300 m).
const WAVE_OFF_WIDE_M := 500.0

## Tests: AI ordered in get in directly after this long (s).
static var board_direct_s := 45.0
## Extraction: on the ground it waits this long (s) for everyone to board; then it lifts with
## whoever is aboard if every player is, else it leaves without them (call it again).
static var extract_wait_s := 180.0

var sup: HeliSupports
var kind := ""
var caller: Soldier
## Where it's going: {"source": "grid", "pos": Vector3} or {} (looking for smoke).
var mark := {}
## Transport: where the squad wants to go ({} until given), and its landing spot.
var dest := {}
var dest_lz := Vector3.ZERO
## "pickup" (resupply, transport and extraction on their way), "carry" (transport with the
## squad aboard), "drop" (putting everyone out: transport, insertion, a dev extraction),
## "leave".
var stage := "pickup"
var phase := Phase.INBOUND
var heli: Helicopter
## The landing spot, and how far it is from the mark (the search moved it).
var lz := Vector3.ZERO
var lz_moved_m := 0.0
## Where it came from and leaves by.
var exit := Vector3.ZERO
## Extraction: its point (Extraction.points id).
var point_id := 0
## Extraction: the deployment ended with it (server_ride_out).
var rode_out := false
## Extraction: a campaign was running when it lifted off (it flies the squad home, not back down).
var going_home := false
## Insertion (a contract zone): points (x, z) it flies by, low, before going in to land.
var route: Array[Vector3] = []
## Insertion and extraction on a zone: where on its edge it comes in (HeliRoute.entry; the
## briefing's plan for an insertion), Vector3.INF until launched without one.
var entry := Vector3.INF
## Insertion: the objective its dead-ground LZ was planned round (Vector3.INF: none).
var objective := Vector3.INF
## LZs it waved off (hot), newest last.
var waved_off: Array[Vector3] = []
## Insertion: the briefing's insertion point (its LZ as planned): wave-offs stay near it.
var planned := Vector3.INF
## Wave-offs so far; past WAVE_OFF_MAX it lands whatever it sees.
var wave_offs := 0

var _t := 0.0
var _check := 0.0
var _last_load := 0.0  # medevac: when the last casualty came aboard (_t)
var _rechecked := false
var _orbit_next := 0.0
var _threat := Vector3.ZERO
var _threat_until := -1.0
var _fire_radio_at := -100.0
var _wrong_seen := {}
var _ordered := {}         # AI instance id -> [first ordered, last ordered]
var _dest_at := -1.0
var _no_room := {}
var _empty_since := -1.0
var _smoke_failed := {}
## What the radio last said it's doing (_say): the same state isn't said twice in a row.
var _radio_state := ""
var _hot_check := 0.0
var _wait_told := false
var _late_seen := {}
var _shooter: Soldier = null
var _hot_seen := Vector3.INF  # where the last enemy who made an LZ hot was
var _music_at := -1  # insertion: Time.get_ticks_msec() when the infil music started (-1: not yet)


func _init(p_sup: HeliSupports, p_kind: String, p_caller: Soldier, p_mark: Dictionary) -> void:
	sup = p_sup
	kind = p_kind
	caller = p_caller
	mark = p_mark if p_mark.has("pos") else {}
	if kind == "insertion":
		stage = "drop"


func level() -> CompoundLevel:
	return sup.level()


## Over: gone, lost or finished; HeliSupports drops it.
func is_over() -> bool:
	return phase == Phase.GONE or phase == Phase.LOST


func is_finished() -> bool:
	return is_over()


## Transport: landed at the pickup (or carrying) and waiting to be told where to.
func wants_destination() -> bool:
	return kind == "transport" and ((stage == "pickup" and phase == Phase.GROUND) or stage == "carry")


# --- Launch ------------------------------------------------------------------------------------

## Spawns the helicopter on its way in (from the LHD, the FOB or the map edge nearest where it
## goes: Supports.origin_for; an insertion or extraction on a zone: from the edge nearest its
## LZ, HeliRoute). Returns whether it's up.
func server_launch() -> bool:
	var lvl := level()
	var layer := VehicleLayer.of(lvl)
	if lvl == null or layer == null:
		return false
	if lvl is ZoneLevel and (kind == "insertion" or kind == "extraction"):
		return _launch_from_edge(lvl as ZoneLevel, layer)
	var toward: Vector3 = route[0] if not route.is_empty() else (mark.pos if mark.has("pos") else _players_centre())
	var origin := Supports.origin_for(lvl, &"heli", toward, 0.0).origin
	var away := Vector3(origin.x - toward.x, 0.0, origin.z - toward.z)
	var dist := away.length()
	var dir := away / dist if dist > 1.0 else Vector3(0, 0, 1)
	var on_edge := _on_edge(lvl, origin)
	if HeliSupports.start_m > 0.0:
		dist = HeliSupports.start_m
	elif kind == "insertion":
		dist = minf(maxf(dist - HeliSupports.SPAWN_INSET_M, 200.0), HeliSupports.INSERT_START_M)
	elif on_edge and lvl is ZoneLevel:
		dist = maxf(dist - HeliSupports.SPAWN_INSET_M, 200.0)
	elif on_edge:
		dist = maxf(dist, HeliSupports.MIN_INBOUND_M)
	var start := toward + dir * dist + Vector3(-dir.z, 0.0, dir.x) * SPAWN_SPACING_M * float(sup.calls.size())
	if lvl is ZoneLevel:  # inside the zone's edge (its invisible wall)
		var area: Rect2 = lvl.map_area().grow(-HeliSupports.SPAWN_INSET_M)
		start.x = clampf(start.x, area.position.x, area.end.x)
		start.z = clampf(start.z, area.position.y, area.end.y)
	return _spawn(lvl, layer, start, -dir)


## Captain, 2026-10-14 ("came in from wrong side of the map", "it turned around"): an insertion
## or extraction on a zone comes in from the edge nearest its LZ whose way in isn't watched
## (HeliRoute.entry, or the briefing's planned `entry`), straight at the LZ, by a point on the
## way (HeliRoute.waypoints: the planned insertion point only when it's on the way), never
## from the support origin's side across the map and back.
func _launch_from_edge(lvl: ZoneLevel, layer: VehicleLayer) -> bool:
	var goal: Vector3 = mark.pos if mark.has("pos") else _players_centre()
	var via: Variant = route[0] if not route.is_empty() else null
	if entry == Vector3.INF:
		entry = HeliRoute.entry(lvl, goal).at
	var away := Vector3(entry.x - goal.x, 0.0, entry.z - goal.z)
	var run := away.length()
	var dir := away / run if run > 1.0 else Vector3(0, 0, 1)
	var dist := run
	if HeliSupports.start_m > 0.0:
		dist = HeliSupports.start_m
	elif kind == "insertion":
		dist = minf(run, HeliSupports.INSERT_START_M)
	var start := goal + dir * dist + Vector3(-dir.z, 0.0, dir.x) * SPAWN_SPACING_M * float(sup.calls.size())
	var area := HeliRoute.inside(lvl)
	start.x = clampf(start.x, area.position.x, area.end.x)
	start.z = clampf(start.z, area.position.y, area.end.y)
	var by: Array[Vector3] = []
	if kind == "insertion":
		by = HeliRoute.waypoints(start, goal, via)
	route = by
	var first: Vector3 = route[0] if not route.is_empty() else goal
	var face := Vector3(first.x - start.x, 0.0, first.z - start.z)
	if not _spawn(lvl, layer, start, face.normalized() if face.length() > 1.0 else -dir):
		return false
	var briefing := MapNodes.briefing(sup) if kind == "insertion" else null
	if briefing and briefing.is_deployed():  # the maps draw the way it actually flies in
		var line: Array[Vector3] = [start]
		line.append_array(route)
		briefing.server_set_insertion_route(HeliRoute.to_xz(line))
	return true


## Up at `start` (on the ground: its contour height added), nose along `facing`; the squad
## aboard for an insertion; then on its way in (_go_in).
func _spawn(lvl: Node, layer: VehicleLayer, start: Vector3, facing: Vector3) -> bool:
	start.y = LandingZone.terrain_y(lvl, start) + Helicopter.CRUISE_AGL_M
	exit = Vector3(start.x, start.y, start.z)
	heli = layer.server_spawn(HeliSupports.MODEL, Transform3D(Basis.looking_at(facing, Vector3.UP), start), "", &"player") as Helicopter
	if heli == null:
		return false
	heli.server_rearm()  # Captain, 2026-10-15: its M240H door guns go up loaded
	heli.support = kind
	if kind == "insertion" and mark.has("pos"):
		planned = mark.pos
	heli.server_start_airborne()
	heli.went_down.connect(_on_down)
	heli.damaged.connect(_on_hit)
	if kind == "insertion":
		for p: Soldier in MapNodes.players(lvl):
			if p.vitals.is_up():
				heli.server_enter(p)
		for a: Soldier in MapNodes.squad_ai(lvl):
			if a.vitals.is_up():
				heli.server_enter(a)
		_music_start()
	_go_in()
	return true


## Heads for the mark (choosing the landing spot), or for the players to look for smoke. One
## radio line says what happens next (P0331: "No safe LZ", "Inbound" and "On station" went out
## in the same second); `why` (no LZ where it was sent) leads it.
func _go_in(why := "") -> void:
	phase = Phase.INBOUND
	_t = 0.0
	_rechecked = false
	if mark.has("pos"):
		if _choose_lz(mark.pos):
			var hot := _hot_at_lz()
			if hot and _pick_other_lz(hot):
				why = "LZ at %s is hot" % _grid(waved_off[-1])
			_fly_in()
			# The ETA flies the J-hook (Captain, 2026-10-14), low by the route's point first.
			var eta := heli.landing_eta_s()
			if not route.is_empty():
				eta = _flat(heli.global_position, route[0]) / (Helicopter.CRUISE_KMH / 3.6 * Helicopter.pace) + Helicopter.eta_land_s(route[0], lz)
			var text := "%s to %s, ETA %d s" % [_inbound_words(eta), _grid(lz), ceili(eta)]
			if not route.is_empty():
				text += ", coming in low by %s" % _grid(route[0])
			if bool(mark.get("near", false)):
				text += ". LZ %d m from you%s" % [roundi(_flat(lz, _players_centre())), ", in dead ground" if bool(mark.get("hidden", false)) else ""]
			elif lz_moved_m > 5.0:
				text += ". No LZ at the mark: landing %d m off" % roundi(lz_moved_m)
			if why != "":
				text = "%s, enemy in sight of it. New LZ: %s" % [why, text]
			_say("landing %s" % _grid(lz), text)
			return
		why = "No safe LZ within %d m of %s" % [roundi(LandingZone.SEARCH_M), _grid(mark.pos)]
		mark = {}
	_orbit_next = 0.0
	_update_orbit()
	var ask := "Pop %s smoke or give me %s grid" % [" or ".join(HeliSupports.smoke_colours(_smoke_kind())), "another" if why != "" else "a"]
	var lead := why + ". " if why != "" else ""
	if _near_station():  # already there: it says so, not "inbound" first
		phase = Phase.LOITER
		_say("on station " + why, lead + "On station, orbiting. " + ask)
	else:
		_say("looking " + why, lead + "Inbound. " + ask)


## "Inbound"; an insertion's pilot calls the time out ("Thirty seconds out, inbound", "Two
## minutes out, inbound") from its ETA (s).
func _inbound_words(eta: float) -> String:
	if kind != "insertion":
		return "Inbound"
	if eta <= 45.0:
		return "Thirty seconds out, inbound"
	if eta <= 75.0:
		return "One minute out, inbound"
	return "%s minutes out, inbound" % ["Two", "Three", "Four", "Five"][clampi(roundi(eta / 60.0) - 2, 0, 3)] if eta < 330.0 else "Inbound"


## Whether it's close enough to the players to be on station (orbiting, looking for smoke).
func _near_station() -> bool:
	return _flat(heli.global_position, _loiter_centre()) < LOITER_RADIUS_M * 1.6


## A radio line for the state it's in (`state`): said once, not again while the state's the
## same; a new order from the caller (server_redirect) always gets an answer.
func _say(state: String, text: String) -> void:
	if state == _radio_state:
		return
	_radio_state = state
	sup.server_radio(kind, text)


## Picks the landing spot for `at` (LandingZone: the nearest safe spot within 100 m). An
## extraction's point moves there. Returns false when there's none.
func _choose_lz(at: Vector3) -> bool:
	var found := LandingZone.find(level(), at, _ignore(), LandingZone.SEARCH_M, LandingZone.clear_for(HeliSupports.MODEL))
	if not found.ok:
		return false
	lz = found.spot
	lz_moved_m = float(found.moved_m)
	if kind == "extraction" and stage == "pickup":
		_place_point()
	return true


## Extraction: its one extraction point at the landing spot (added once, moved after: a
## recheck or a redirect doesn't leave the old one behind).
func _place_point() -> void:
	var extraction := MapNodes.extraction(sup)
	if extraction and extraction.is_active():
		var id := extraction.server_place_point(point_id, Vector2(lz.x, lz.z), "smoke" if String(mark.get("from", "")) == "smoke" else "grid",
			"Helicopter LZ")
		if id > 0:
			point_id = id


# --- Orders from the caller (host) -------------------------------------------------------------

## A new mark while it's on its way or loitering: it goes there instead. Returns "" or why not.
func server_redirect(new_mark: Dictionary) -> String:
	if can_turn_back():
		# Captain, 2026-10-15: sent home (or done waiting) and still in the air on its way out,
		# empty: a new call turns it back, free, rather than "already on its way out" until it
		# has flown off the map (and then the call's cooldown on top).
		stage = "pickup"
		sup.server_radio(kind, "Copy, turning back")
	elif phase != Phase.INBOUND and phase != Phase.LOITER:
		return "%s is already %s" % [HeliSupports.callsign(kind), "down" if phase == Phase.GROUND else "on its way out"]
	_radio_state = ""  # a new order: it answers
	if not new_mark.has("pos"):
		mark = {}
		_go_in()
		return ""
	mark = new_mark
	_go_in()
	return ""


## Whether a new call turns this one back (server_redirect): a transport or extraction sent home
## (or leaving after it waited) without people aboard, taking off or on its way out.
func can_turn_back() -> bool:
	if kind != "transport" and kind != "extraction":
		return false
	if stage != "leave" or rode_out or not is_instance_valid(heli) or heli.is_down():
		return false
	return (phase == Phase.LEAVING or phase == Phase.TAKEOFF) and heli.occupants().is_empty()


## Transport: where to take the squad. Returns "" or why not.
func server_set_destination(where: Dictionary) -> String:
	if not where.has("pos"):
		return "Give me a grid for the drop-off: a marker on the map"
	var found := LandingZone.find(level(), where.pos, _ignore(), LandingZone.SEARCH_M, LandingZone.clear_for(HeliSupports.MODEL))
	if not found.ok:
		return "No safe LZ within %d m of %s: pick another" % [roundi(LandingZone.SEARCH_M), _grid(where.pos)]
	dest = where
	dest_lz = found.spot
	_dest_at = Soldier._now()
	sup.server_radio(kind, "Copy, taking you to %s%s" % [_grid(dest_lz), "" if float(found.moved_m) < 5.0 else " (%d m off the mark: no LZ at it)" % roundi(float(found.moved_m))])
	if stage == "carry" and phase == Phase.CARRY:
		lz = dest_lz
		_land()
	return ""


## Sends it home. Returns "" or why not.
func server_cancel() -> String:
	if not heli.occupants().is_empty() and heli.is_airborne():
		return "Not with people aboard: give it a destination"
	sup.server_radio(kind, "Copy, returning to base")
	sup.server_clear_cooldown(kind)  # sent home: it can be called again at once (Captain, 2026-10-15)
	if phase == Phase.GROUND:
		_depart()
	else:
		_leave()
	return ""


## Tests: gone at once, its helicopter with it.
func server_dismiss() -> void:
	if is_instance_valid(heli) and not heli.is_down():
		heli.forced_exits = true
		for s: Soldier in heli.occupants():
			heli.server_exit(s)
		heli.queue_free()
	phase = Phase.GONE
	if kind == "insertion":
		sup.server_music_stop()  # Captain, 2026-10-14 (temporary): the infil music stops with it


# --- Each step (host) ----------------------------------------------------------------------------

func step(delta: float) -> void:
	if is_over():
		return
	if not is_instance_valid(heli) or heli.is_queued_for_deletion():
		phase = Phase.GONE
		return
	if heli.is_down():
		_on_down(heli)
		return
	_t += delta
	_check -= delta
	_orbit_next -= delta
	_hot_check -= delta
	if kind == "insertion" and stage == "drop" and (phase == Phase.INBOUND or phase == Phase.LOITER) and heli.is_airborne():
		_board_late_players()
	match phase:
		Phase.INBOUND, Phase.LOITER:
			_step_inbound()
		Phase.GROUND:
			_step_ground()
		Phase.TAKEOFF:
			if heli.height_agl() > TAKEOFF_AGL_M or _t > TAKEOFF_S / Helicopter.pace + 2.0:
				_t = 0.0
				if stage == "carry":
					lz = dest_lz
					_land()
					phase = Phase.CARRY
				else:
					_leave()
		Phase.CARRY:
			_step_carry()
		Phase.LIFTING:
			if heli.height_agl() > LIFT_AGL_M or _t > LIFT_S / Helicopter.pace:
				var extraction := MapNodes.extraction(sup)
				going_home = HeliCall.campaign_running(sup)
				if extraction and extraction.point_by_id(point_id).is_empty():
					_place_point()  # (another call or smoke replaced it meanwhile)
				rode_out = extraction != null and extraction.server_ride_out(point_id, heli)
				sup.server_radio(kind, "We're out. Good work" if rode_out else "Lifting with what we've got")
				phase = Phase.ENDED
				_t = 0.0
				if rode_out and going_home:  # the base takes over: circle until the level switches
					heli.server_orbit(lz, HOME_ORBIT_M, HOME_ORBIT_AGL_M, Helicopter.CRUISE_KMH)
		Phase.ENDED:
			if _t > (HOME_WAIT_S if rode_out and going_home else DEV_DROP_S):
				sup.server_radio(kind, "Nowhere to take you: putting you back down")
				stage = "drop"
				mark = {"pos": lz}
				_land()
				phase = Phase.INBOUND
				_rechecked = true
		Phase.LEAVING:
			var area: Rect2 = level().map_area()
			var at_wall := level() is ZoneLevel and not area.grow(-40.0).has_point(Vector2(heli.global_position.x, heli.global_position.z))
			if (_flat(heli.global_position, exit) < EXIT_M or at_wall) and Soldier._now() - _leave_at > LEAVE_MIN_S:  # (a zone's edge is a wall; a small map's isn't)
				if kind == "medevac":
					_evacuate()
				elif kind == "cargo":
					_bank_cargo()
				heli.queue_free()
				phase = Phase.GONE


func _step_inbound() -> void:
	if heli.is_landed():
		_on_landed()
		return
	if mark.has("pos"):
		if not route.is_empty():  # flying in low by the insertion point first
			if _flat(heli.global_position, route[0]) < ROUTE_PASS_M:
				route.pop_front()
				_fly_in()
			return
		if (kind == "insertion" or kind == "extraction") and _hot_check <= 0.0 and _flat(heli.global_position, lz) < HOT_CHECK_M:
			_hot_check = HOT_CHECK_S
			var hot := _hot_at_lz()
			if hot:
				_wave_off(hot)
				return
		if not _rechecked and _flat(heli.global_position, lz) < RECHECK_LZ_M and stage == "pickup":
			_rechecked = true
			var before := lz
			if not _choose_lz(mark.pos):
				var why := "Can't land at %s: no LZ within %d m" % [_grid(mark.pos), roundi(LandingZone.SEARCH_M)]
				mark = {}
				_go_in(why)
				return
			if lz.distance_to(before) > 1.0:
				_land()
		if _should_abort():
			sup.server_radio(kind, "Taking heavy fire, aborting!")
			_leave()
		return
	if _check <= 0.0:
		_check = SMOKE_CHECK_S
		var cloud := _seen_smoke(HeliSupports.smoke_colours(_smoke_kind()))
		if cloud:
			_land_on_smoke(cloud)
			return
	if _orbit_next <= 0.0:
		_update_orbit()
	if phase == Phase.INBOUND and _near_station():
		phase = Phase.LOITER
		_say("on station", "On station, orbiting. Pop %s smoke or give me a grid" % " or ".join(HeliSupports.smoke_colours(_smoke_kind())))


func _land_on_smoke(cloud: SmokeCloud) -> void:
	var at := level().ground_point(cloud.global_position)
	mark = {"pos": at, "from": "smoke"}
	var extraction := MapNodes.extraction(sup) if kind == "extraction" and stage == "pickup" else null
	if extraction:  # the point Extraction set at this purple smoke becomes the helicopter's
		var smoke_point := extraction.server_take_smoke(cloud)
		if smoke_point > 0 and extraction.point_by_id(point_id).is_empty():
			point_id = smoke_point
	if not _choose_lz(at):
		sup.server_radio(kind, "I see %s, but there's no LZ within %d m of it" % [cloud.colour, roundi(LandingZone.SEARCH_M)])
		_smoke_failed[cloud.get_instance_id()] = true
		mark = {}
		return
	sup.claimed[cloud.get_instance_id()] = self
	_rechecked = false
	phase = Phase.INBOUND
	_land()
	sup.server_radio(kind, "I see %s. Coming in%s" % [cloud.colour, "" if lz_moved_m < 5.0 else ", landing %d m off it" % roundi(lz_moved_m)])


func _step_carry() -> void:
	if heli.is_landed():
		stage = "drop"
		_on_landed()
		return
	if _check <= 0.0 and _flat(heli.global_position, dest_lz) < DEST_SMOKE_M + SMOKE_SEE_M * 0.5:
		_check = SMOKE_CHECK_S
		var cloud := _seen_smoke(HeliSupports.smoke_colours("transport"), dest.get("pos", dest_lz), DEST_SMOKE_M)
		if cloud:
			var at := level().ground_point(cloud.global_position)
			sup.claimed[cloud.get_instance_id()] = self
			var found := LandingZone.find(level(), at, _ignore(), LandingZone.SEARCH_M, LandingZone.clear_for(HeliSupports.MODEL))
			if found.ok:
				dest_lz = found.spot
				lz = dest_lz
				_land()
				sup.server_radio(kind, "I see %s, setting down there" % cloud.colour)


## On the ground: what this support does there.
func _on_landed() -> void:
	phase = Phase.GROUND
	_t = 0.0
	_check = 0.0
	_empty_since = -1.0
	if stage == "drop":
		_moved_insertion()
		var briefing := MapNodes.briefing(sup) if kind == "insertion" else null
		if briefing and briefing.is_deployed():
			briefing.server_set_insertion_route([])  # down: the maps stop drawing its way in
		_unload(false)
		sup.server_radio(kind, "On the ground at %s. Out, out, out!" % _grid(heli.global_position))
		if kind == "insertion":
			sup.server_music_stop()
		return
	match kind:
		"resupply":
			_drop_pallet()
			sup.server_radio(kind, "Pallet's down at %s. Lifting in a moment" % _grid(heli.global_position))
		"transport":
			sup.server_radio(kind, "On the ground. Get in and give me a destination (Support > Helicopter transport > Fly to my map marker)")
		"extraction":
			_wait_told = false
			sup.server_radio(kind, "On the ground at %s. Get everyone aboard: we wait %d s" % [_grid(heli.global_position), roundi(extract_wait_s)])
		"cargo":
			sup.server_radio(kind, "Packhorse down at %s. Drop the loot within %d m of us: we lift in %d s, or when you send us home" % [_grid(heli.global_position), roundi(CARGO_REACH_M), roundi(CARGO_WAIT_S)])
		"medevac":
			_last_load = 0.0
			sup.server_radio(kind, "Dustoff on the ground at %s. Bring the wounded to the doors" % _grid(heli.global_position))


func _step_ground() -> void:
	if stage == "drop":
		if _players_aboard() == 0:
			if _empty_since < 0.0:
				_empty_since = _t
			if _t - _empty_since >= DROP_GRACE_S:
				_depart()
		elif _t > (INSERT_DROP_WAIT_S if kind == "insertion" else DROP_WAIT_S):
			_unload(true)
		return
	match kind:
		"resupply":
			if _t > UNLOAD_S:
				_depart()
		"transport":
			if _check <= 0.0:
				_check = LOAD_CHECK_S
				_load_people(false)
				_board(_transport_ai())
			if dest.is_empty():
				if _t > PICKUP_WAIT_S and heli.occupants().is_empty():
					sup.server_radio(kind, "Nobody's coming. Heading home")
					_depart()
				return
			if _everyone_near_aboard() or Soldier._now() - _dest_at > BOARD_WAIT_S:
				sup.server_radio(kind, "Lifting off, %d aboard" % heli.occupants().size())
				stage = "carry"
				_take_off()
		"cargo":
			if _check <= 0.0:
				_check = LOAD_CHECK_S
				_load_items_near(heli.global_position, CARGO_REACH_M)
			if _t > CARGO_WAIT_S:
				var loads := heli.cargo_hold.entries().size() if heli.cargo_hold else 0
				sup.server_radio(kind, "Packhorse lifting with %d loads aboard" % loads)
				stage = "leave"
				_take_off()
		"medevac":
			# Captain, 2026-10-16 ("medevacs are now a concern", "massive neck damage depends on medevac"):
			# loads the downed and carried by its doors; MEDEVAC_LIFT_S after the last one is aboard
			# it lifts, and once it's off the map they're out of the fight alive (_evacuate).
			if _check <= 0.0:
				_check = LOAD_CHECK_S
				var before := _casualties_aboard()
				_load_people(false)
				if _casualties_aboard() > before:
					_last_load = _t
			var aboard := _casualties_aboard()
			if aboard > 0 and _t - _last_load > MEDEVAC_LIFT_S:
				sup.server_radio(kind, "%d casualt%s aboard. Dustoff lifting" % [aboard, "y" if aboard == 1 else "ies"])
				stage = "leave"
				_take_off()
			elif aboard == 0 and _t > PICKUP_WAIT_S:
				sup.server_radio(kind, "No casualties brought to us. Heading home")
				_depart()
		"extraction":
			if _check <= 0.0:
				_check = LOAD_CHECK_S
				_load_items()
				_load_people(true)
				var extraction := MapNodes.extraction(sup)
				_board(extraction.required().ai if extraction else [])
				if _all_required_aboard():
					sup.server_radio(kind, "Everyone's aboard. Lifting off")
					_lift_out()
				elif _t > extract_wait_s:
					_stop_waiting()
				elif not _wait_told and extract_wait_s >= 90.0 and _t > extract_wait_s - 60.0:
					_wait_told = true
					sup.server_radio(kind, "One minute on the ground, then we lift")


# --- On the ground (host) ------------------------------------------------------------------------

## The supply pallet and its load beside the cabin door (HeliSupports' data).
func _drop_pallet() -> void:
	var lvl := level()
	var side := heli.global_basis.x
	var at := heli.global_transform * Vector3(0.0, 0.0, -2.4) + side * (VehicleArt.size_m(heli.model).x * 0.5 + 3.0)
	at = lvl.ground_point(at)
	var data: Dictionary = HeliSupports.data().get("resupply", {})
	var pallet := String(data.get("pallet", ""))
	if pallet != "" and ItemDB.get_item(StringName(pallet)):
		lvl.server_spawn_dropped(StringName(pallet), 1, at + Vector3.UP * 0.2)
	var i := 0
	for entry: Array in resupply_load():
		var off := Vector3((i % 4 - 1.5) * 0.28, 0.45 + floorf(i / 8.0) * 0.25, (floori(i / 4.0) % 2 - 0.5) * 0.4)
		lvl.server_spawn_dropped(StringName(String(entry[0])), int(entry[1]), at + off)
		i += 1


## The pallet's load: [[item id, count], ...] (Captain, 2026-10-16: "it needs to bring supplies for
## the squads roles and it needs to be enough for everyone"): for EACH soldier of the squad
## (players and squad AI) magazines and loose rounds for every weapon they carry ("per_weapon"),
## their share of medical kit and grenades ("per_head") and their role's extras ("per_role": a
## medic's trauma kit, fluids and seals...), then the "fixed" list once.
func resupply_load() -> Array:
	var data: Dictionary = HeliSupports.data().get("resupply", {})
	var per: Dictionary = data.get("per_weapon", {})
	var lvl := level()
	var counts := {}
	var order: Array = []
	var add := func(id: String, n: int) -> void:
		if n <= 0 or ItemDB.get_item(StringName(id)) == null:
			return
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] += n
	var squad: Array = MapNodes.players(lvl) + MapNodes.squad_ai(lvl)
	var roles: Dictionary = data.get("per_role", {})
	for s: Soldier in squad:
		for slot: String in per:
			var weapon_id: StringName = s.inventory.slots.get(StringName(slot), &"")
			var weapon := ItemDB.get_item(weapon_id) if weapon_id != &"" else null
			if weapon == null:
				continue
			var mag := String(weapon.stats.get("ammo", ""))
			var amounts: Array = per[slot]
			if mag != "":
				add.call(mag, int(amounts[0]))
				var loose := HeliCall.loose_rounds_for(StringName(mag))
				if loose != "":
					add.call(loose, int(amounts[1]))
		for entry: Array in data.get("per_head", []):
			add.call(String(entry[0]), int(entry[1]))
		for entry: Array in roles.get(String(s.role), []):
			add.call(String(entry[0]), int(entry[1]))
	for entry: Array in data.get("fixed", []):
		add.call(String(entry[0]), int(entry[1]))
	var out: Array = []
	for id: String in order:
		out.append([id, int(counts[id])])
	return out


## The loose rounds of a magazine's calibre ("" for none).
static func loose_rounds_for(mag_id: StringName) -> String:
	var mag := ItemDB.get_item(mag_id)
	if mag == null:
		return ""
	var calibre := String(mag.stats.get("calibre", ""))
	if calibre == "":
		return ""
	for id: Variant in ItemDB.all_ids():
		var item := ItemDB.get_item(StringName(String(id)))
		if item and item.type == "ammo" and bool(item.stats.get("loose", false)) and String(item.stats.get("calibre", "")) == calibre:
			return String(item.id)
	return ""


## AI squadmates in `list` not aboard get ordered in (VehicleLayer.server_order_mount: they walk
## to a door), again every BOARD_ORDER_S; any still out after board_direct_s close by get in.
func _board(list: Array) -> void:
	var now := Soldier._now()
	var send := PackedStringArray()
	for s: Soldier in list:
		if not is_instance_valid(s) or Vehicle.ride_of(s) == heli or not s.vitals.is_up():
			continue
		var key := s.get_instance_id()
		var times: Array = _ordered.get(key, [])
		if times.is_empty() or now - float(times[1]) > BOARD_ORDER_S:
			send.append(String(s.name))
			_ordered[key] = [float(times[0]) if not times.is_empty() else now, now]
		elif now - float(times[0]) > board_direct_s and s.global_position.distance_to(heli.global_position) < BOARD_DIRECT_M:
			heli.server_enter(s)
	var from := _commander()
	var layer := VehicleLayer.of(level())
	if not send.is_empty() and from and layer:
		layer.server_order_mount(from, heli.global_position, send)


## The downed, the dead and the carried by the doors are loaded (bodies ride in passenger
## seats); with `hvts`, cuffed or friendly HVTs inside the extraction point or by the
## helicopter get in too.
func _load_people(hvts: bool) -> void:
	var lvl := level()
	var point: Dictionary = {}
	var extraction := MapNodes.extraction(sup)
	if hvts and extraction:
		point = extraction.point_by_id(point_id)
	var everyone: Array = []
	for parent: Node in [lvl.players, lvl.ai, lvl.bodies]:
		everyone.append_array(parent.get_children())
	if lvl.people:
		everyone.append_array(lvl.people.people())  # civilians and HVTs live under People
	if hvts:  # extraction: the enemy dead brought to it come out too (what's on them is loot)
		for n: Node in sup.get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
			if n not in everyone:
				everyone.append(n)
	var spare := _spare_seats(extraction) if hvts else 99
	for n: Node in everyone:
		var s := n as Soldier
		if s == null or s.is_queued_for_deletion() or Vehicle.ride_of(s) != null:
			continue
		var hvt := Person.is_hvt(s)
		if not hvt and s.faction != &"friendly":
			# Extraction: an enemy body carried to a door, or set down by one, while the seats
			# the squad still needs stay free.
			if hvts and s.vitals.is_dead() and spare > 0 and not s.has_meta(&"vehicle_crew"):
				var by: Vector3 = s.carried_by.global_position if is_instance_valid(s.carried_by) and s.carried_by.faction == &"friendly" else s.body_point()
				if _by_door(by, LOAD_REACH_M + (1.0 if is_instance_valid(s.carried_by) else 0.0)) and heli.server_enter(s):
					spare -= 1
			continue
		if hvts and s.vitals.is_up() and s.has_meta(&"recovery") and s.global_position.distance_to(heli.global_position) <= HVT_REACH_M:
			heli.server_enter(s)  # a recovery contract's squadmate, found: out with us
			continue
		if is_instance_valid(s.carried_by):
			if _by_door(s.carried_by.global_position, LOAD_REACH_M + 1.0):
				heli.server_enter(s)
			continue
		if not s.vitals.is_up():
			if _by_door(s.body_point(), LOAD_REACH_M):
				heli.server_enter(s)
			continue
		if hvt and hvts and not s.vitals.is_dead() and (Person.leadable(s) or Person.is_cuffed(s)):
			var near := s.global_position.distance_to(heli.global_position) <= HVT_REACH_M
			if near or (not point.is_empty() and Extraction.inside(point, s.global_position)):
				heli.server_enter(s)


## Extraction: passenger seats free beyond those the squad still out needs (players and the AI
## they bring).
func _spare_seats(extraction: Extraction) -> int:
	var free := 0
	for i in heli.seat_count():
		if heli.occupant(i) == null and heli.seat_kind(i) == Vehicle.PASSENGER:
			free += 1
	if extraction:
		var need := extraction.required()
		for s: Soldier in need.players + need.ai:
			if Vehicle.ride_of(s) != heli:
				free -= 1
	return free


## Extraction: items set down inside the point go into the hold (whole stacks that fit).
func _load_items() -> void:
	var extraction := MapNodes.extraction(sup)
	var point: Dictionary = extraction.point_by_id(point_id) if extraction else {}
	if point.is_empty() or heli.cargo() == null:
		return
	for node in sup.get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := node as WorldItem
		if item == null or item.is_queued_for_deletion() or not Extraction.inside(point, item.global_position):
			continue
		var data := ItemDB.get_item(item.item_id)
		if data == null:
			continue
		if heli.cargo_hold.room_for(VehicleCargo.HOLD, data, item.state) >= item.count:
			heli.cargo_hold.take(item.item_id, item.count, item.state)
			if item.uid != "":
				GameState.item_taken(item.uid)
			item.queue_free()
		elif not _no_room.has(item.uid):
			_no_room[item.uid] = true
			sup.server_radio(kind, "No room aboard for the %s" % data.name)


## Everyone out but the players (with `players`, them too), the AI falling in on the commander.
func _unload(players: bool) -> void:
	var out := PackedStringArray()
	for s: Soldier in heli.occupants():
		if s.is_ai() or not s.vitals.is_up() or players:
			heli.server_exit(s)
			if s.is_ai() and s.vitals.is_up() and s.squad_slot >= 0:
				out.append(String(s.name))
	var from := _commander()
	var squad := level().squad_for(&"friendly")
	if from and squad and not out.is_empty():
		squad.give_order(from, Squad.Order.FOLLOW, from.global_position, out)


## Everyone out (it's leaving), then off the ground and away.
## Cargo run: items lying within `reach` of `at` go into the hold while there's room.
func _load_items_near(at: Vector3, reach: float) -> void:
	if heli.cargo() == null:
		return
	for node in sup.get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := node as WorldItem
		if item == null or item.is_queued_for_deletion() or item.global_position.distance_to(at) > reach:
			continue
		var data := ItemDB.get_item(item.item_id)
		if data == null:
			continue
		if heli.cargo_hold.room_for(VehicleCargo.HOLD, data, item.state) >= item.count:
			heli.cargo_hold.take(item.item_id, item.count, item.state)
			if item.uid != "":
				GameState.item_taken(item.uid)
			item.queue_free()
		elif not _no_room.has(item.uid):
			_no_room[item.uid] = true
			sup.server_radio(kind, "No room aboard for the %s" % data.name)


## Cargo run off the map: what's aboard goes into the base stash (BaseHub.server_add_to_stash).
func _bank_cargo() -> void:
	if heli.cargo_hold == null:
		return
	var n := 0
	for e: Dictionary in heli.cargo_hold.clear_all():
		BaseHub.server_add_to_stash(StringName(e.id), int(e.count), e.get("state", {}))
		n += 1
	sup.server_radio(kind, "Packhorse is home: %d loads in the stash" % n)

## Medevac: the downed, dead and carried aboard.
func _casualties_aboard() -> int:
	var n := 0
	for s: Variant in heli.occupants():
		if s is Soldier and not (s as Soldier).vitals.is_up():
			n += 1
	return n


## Medevac off the map: everyone aboard is out of the fight. A squadmate alive goes home to
## recover (BaseHub.server_squadmate_leaving: gear kept, injuries, Recovering in the roster); a
## body is brought home; a player is back in the fight, respawned in his own kit, patched up.
func _evacuate() -> void:
	var lvl := level() as CompoundLevel
	for occupant: Variant in heli.occupants():
		var s := occupant as Soldier
		if s == null or not is_instance_valid(s):
			continue
		heli.server_exit(s)
		if not s.is_ai():
			s.vitals.server_reset_health()
			if lvl:
				s._server_respawn_now(lvl)
			continue
		if s.vitals.is_dead():
			s.remove_from_group(Soldier.DEAD_GROUP)
		else:
			BaseHub.server_squadmate_leaving(s)
		s.queue_free()

func _depart() -> void:
	_unload(true)
	stage = "leave"
	sup.server_radio(kind, "Lifting off")
	_take_off()


func _take_off() -> void:
	heli.server_take_off()
	phase = Phase.TAKEOFF
	_t = 0.0


## Extraction: off the ground with the squad; the deployment ends once it's up (LIFTING).
func _lift_out() -> void:
	stage = "leave"
	heli.server_take_off()
	phase = Phase.LIFTING
	_t = 0.0


## Extraction: it waited extract_wait_s on the ground. With every player aboard it lifts with
## who's aboard (AI squadmates still out are left behind: Extraction reports them); otherwise
## it puts everyone back out (and what it had loaded), and leaves: they call it again.
func _stop_waiting() -> void:
	var extraction := MapNodes.extraction(sup)
	var need: Dictionary = extraction.required() if extraction else {"players": [], "ai": []}
	var players: Array = need.players
	if not players.is_empty() and players.all(func(p: Soldier) -> bool: return Vehicle.ride_of(p) == heli):
		var left := PackedStringArray()
		for s: Soldier in need.ai:
			if Vehicle.ride_of(s) != heli:
				extraction.server_set_bring(String(s.name), false)
				left.append(s.display_name())
		sup.server_radio(kind, "Can't hold the LZ any longer. Lifting with who's aboard%s" % (": %s stay%s behind" % [", ".join(left), "s" if left.size() == 1 else ""] if not left.is_empty() else ""))
		_lift_out()
		return
	sup.server_radio(kind, "Can't hold the LZ any longer. Lifting off: call us again when you're ready")
	sup.server_clear_cooldown(kind)  # "call us again": and it can be, at once
	_put_down_hold()
	_depart()


## Everything in the hold set down beside the cabin door (a call that leaves without the squad
## doesn't fly off with their loot).
func _put_down_hold() -> void:
	if heli.cargo_hold == null:
		return
	var lvl := level()
	var at := heli.global_transform * Vector3(-(VehicleArt.size_m(heli.model).x * 0.5 + 2.0), 0.0, -2.4)
	var i := 0
	for e: Dictionary in heli.cargo_hold.clear_all():
		lvl.server_spawn_dropped(StringName(String(e.id)), int(e.get("count", 1)), lvl.ground_point(at + Vector3(0.0, 0.0, 0.5 * i)) + Vector3.UP * 0.3,
			e.get("state", {}))
		i += 1


## Insertion: heads in, by the next point of its route (low and fast) or straight in to land.
func _fly_in() -> void:
	if not route.is_empty():
		heli.server_fly_to(route[0], ROUTE_AGL_M, Helicopter.CRUISE_KMH, false)
	else:
		_land()


## Lands at the LZ by the J-hook (Helicopter.server_land_at). Captain, 2026-10-14: the squad's
## doors face away from the last known threat: with one known near the LZ (it shot at the
## helicopter, or made an LZ hot) the hook ends with the threat abeam, the fuselage between it
## and the door everyone gets out of (Vehicle.exit_spot's "exit_away"); else it hooks back the
## way it came.
func _land() -> void:
	var threat := _known_threat()
	if threat == Vector3.INF:
		heli.server_land_at(lz)
		heli.remove_meta(&"exit_away")
		return
	var t := Vector2(threat.x - lz.x, threat.z - lz.z).normalized()
	var natural := Vector2(heli.global_position.x - lz.x, heli.global_position.z - lz.z).normalized()
	var right := Vector2(t.y, -t.x)  # its nose this way: the threat on its right
	var left := -right
	var f := right if right.dot(natural) >= left.dot(natural) else left
	heli.server_land_at(lz, atan2(-f.x, -f.y))
	heli.set_meta(&"exit_away", threat)


## Where the last known threat to the landing is (Vector3.INF: none known): who shot at it
## lately, else who made an LZ hot; within DOORS_AWAY_M of the LZ.
func _known_threat() -> Vector3:
	var out := Vector3.INF
	if Soldier._now() < _threat_until:
		out = _threat
	elif _hot_seen != Vector3.INF:
		out = _hot_seen
	if out != Vector3.INF and _flat(out, lz) > DOORS_AWAY_M:
		return Vector3.INF
	return out


## An enemy endangering the LZ now (insertion and extraction), or null: one close by who sees
## it (DeadGround.hot_watcher), or one who shot at the helicopter lately from near it. Captain,
## 2026-10-14: one far sentry with a sight line isn't a hot LZ.
func _hot_at_lz() -> Soldier:
	if kind != "insertion" and kind != "extraction":
		return null
	var close := DeadGround.hot_watcher(level(), lz)
	if close:
		return close
	if is_instance_valid(_shooter) and _shooter.vitals.is_up() and Soldier._now() - (_threat_until - AVOID_S) < HOT_FIRE_S \
			and _flat(_shooter.global_position, lz) <= HOT_FIRE_M:
		return _shooter
	return null


## The LZ is hot (`hot` sees it): another in dead ground, away from every LZ waved off: round
## the objective for an insertion planned on one, else round the squad (a hot zone's insertion:
## round the old LZ). The extraction point moves there. Returns whether there was one.
func _pick_other_lz(hot: Soldier) -> bool:
	waved_off.append(lz)
	var lvl := level()
	var posts := DeadGround.watchers(lvl)
	# Whoever made an LZ hot must not see the next one (over the terrain: walls aside).
	var spotters: Array[Vector3] = []
	if is_instance_valid(hot):
		spotters.append(hot.global_position)
		if hot.global_position not in posts:
			posts.append(hot.global_position)
	var centre := _players_centre()
	var rings: Array[Vector2] = [DeadGround.SQUAD_RING_M, Vector2(DeadGround.SQUAD_RING_M.x, WAVE_OFF_WIDE_M)]
	var prefer: Variant = centre
	var avoid_m := WAVE_OFF_AVOID_M
	if kind == "insertion":
		# Captain, 2026-10-14: near the insertion point the squad planned on, not drifting away.
		centre = planned if planned != Vector3.INF else lz
		rings = [Vector2(0.0, INSERT_WAVE_OFF_M)]
		prefer = centre
		avoid_m = INSERT_AVOID_M
	for ring in rings:
		for attempt in 3:
			var found := DeadGround.find(lvl, centre, ring, prefer, waved_off, avoid_m, posts, _ignore(), spotters)
			if not found.get("ok", false):
				_log("%s helicopter: no other LZ round (%.0f, %.0f), %.0f-%.0f m (%d checked, %d watchers)" % [kind, centre.x, centre.z,
					ring.x, ring.y, int(found.get("checked", 0)), int(found.get("watchers", 0))])
				break
			var spot: Vector3 = found.spot
			var also := DeadGround.hot_watcher(lvl, spot)
			_log("%s helicopter: other LZ (%.0f, %.0f) %s, seen by %d post(s)%s" % [kind, spot.x, spot.z,
				"hidden" if found.hidden else "not hidden", int(found.get("seen_by", 0)), ", hot: %s sees it" % also.display_name() if also else ""])
			if also:
				waved_off.append(spot)
				if also.global_position not in spotters:
					spotters.append(also.global_position)
				continue
			lz = spot
			lz_moved_m = 0.0
			mark = {"source": "grid", "pos": spot, "from": "wave_off", "hidden": bool(found.hidden), "near": kind == "extraction"}
			_rechecked = true
			if kind == "extraction" and stage == "pickup":
				_place_point()
			return true
	return false


## On the way in, the LZ turned hot (`hot` sees it): it waves off for another (the radio says
## where), or, with none, loiters and asks for smoke or a grid.
func _wave_off(hot: Soldier) -> void:
	var old := lz
	_radio_state = ""
	_hot_seen = hot.global_position
	_log("%s helicopter: LZ (%.0f, %.0f) hot: %s %s from %.0f m" % [kind, old.x, old.z, hot.display_name(),
		"shot at us" if hot == _shooter else "sees it", _flat(hot.global_position, old)])
	if wave_offs >= WAVE_OFF_MAX:
		_put_down_anyway()
		return
	wave_offs += 1
	if _pick_other_lz(hot):
		_moved_insertion()
		_fly_in()
		var dir := Vector2(lz.x - old.x, lz.z - old.z)
		_say("landing %s" % _grid(lz), "LZ %s is hot, enemy in sight of it. Waving off: new LZ %s, %d m %s%s" % [_grid(old), _grid(lz),
			roundi(dir.length()), _compass(dir),
			" of it" if kind == "insertion" else ", %d m from you" % roundi(_flat(lz, _players_centre()))])
		return
	if kind == "insertion":  # an insertion always ends: there's nowhere else to take them
		_put_down_anyway()
		return
	mark = {}
	_go_in("LZ %s is hot and there's no other near" % _grid(old))


## Waved off enough (WAVE_OFF_MAX) or nowhere else for an insertion: it lands at the best LZ
## it has (the one whose nearest enemy in sight of it is farthest) and stops looking.
func _put_down_anyway() -> void:
	var best := lz
	var best_d := -1.0
	var options: Array[Vector3] = waved_off.duplicate()
	options.append(lz)
	for at in options:
		var d := INF
		for s in DeadGround.hostiles(level()):
			var f := _flat(s.global_position, at)
			if f < d and DeadGround.sees(level(), at, s.global_position, true):
				d = f
		if d > best_d:
			best_d = d
			best = at
	var done := wave_offs
	lz = best
	lz_moved_m = 0.0
	mark = {"source": "grid", "pos": lz, "from": "wave_off", "near": kind == "extraction"}
	_rechecked = true
	_hot_check = INF
	wave_offs = WAVE_OFF_MAX + 1
	if kind == "extraction" and stage == "pickup":
		_place_point()
	_moved_insertion()
	_land()
	_log("%s helicopter: putting down at (%.0f, %.0f) after %d wave-off(s)" % [kind, lz.x, lz.z, done])
	_say("landing %s" % _grid(lz), "Putting you down, best we've got: LZ %s" % _grid(lz))


## Insertion: the briefing's INSERT marker moves to where it lands now (the map shows it).
func _moved_insertion() -> void:
	if kind != "insertion":
		return
	var briefing := MapNodes.briefing(sup)
	if briefing and briefing.is_deployed():
		briefing.server_move_insertion(Vector2(lz.x, lz.z))


## A line for the session log and the console (the wave-off's reasoning, for playtests and tests).
static func _log(text: String) -> void:
	print("[heli] " + text)
	SessionLog.note(text)


## Insertion: a player who joined while it flies in (up, on foot) gets a seat aboard.
func _board_late_players() -> void:
	for p: Soldier in MapNodes.players(sup):
		if p.vitals.is_up() and Vehicle.ride_of(p) == null and not p.is_queued_for_deletion() and not _late_seen.has(p.get_instance_id()):
			_late_seen[p.get_instance_id()] = true
			if heli.server_enter(p):
				sup.server_radio(kind, "%s is aboard" % p.display_name())
				_music_start()


## Captain, 2026-10-14 ("can we add Ride of the Valkyries to the infils temporarily lol";
## temporary): the infil music, armed on every peer once players are aboard the insertion
## (InfilMusic), with how far into the track it is (a late boarder joins it there).
func _music_start() -> void:
	if _music_at < 0:
		if _players_aboard() == 0:
			return
		_music_at = Time.get_ticks_msec()
	sup.server_music_start(heli, float(Time.get_ticks_msec() - _music_at) / 1000.0)


## "north", "south-west"... for a flat direction (x, z: -z is north).
static func _compass(dir: Vector2) -> String:
	if dir.length() < 0.01:
		return "here"
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	var a := fposmod(rad_to_deg(atan2(dir.x, -dir.y)), 360.0)
	return names[roundi(a / 45.0) % 8]


## Away to where it came from; gone there (step). An insertion or extraction on a zone leaves by
## the nearest edge whose way out isn't watched (Captain, 2026-10-14: not back across the map
## to where it came in: HeliRoute.exit_for).
func _leave() -> void:
	stage = "leave"
	_leave_at = Soldier._now()
	phase = Phase.LEAVING
	var lvl := level()
	if lvl is ZoneLevel and (kind == "insertion" or kind == "extraction"):
		var out := HeliRoute.exit_for(lvl, heli.global_position)
		exit = Vector3(out.x, LandingZone.terrain_y(lvl, out) + Helicopter.CRUISE_AGL_M, out.z)
	heli.server_fly_to(exit, Helicopter.CRUISE_AGL_M, Helicopter.CRUISE_KMH, false)


## Whether a campaign deployment is running (BaseHub will switch to the base when it ends):
## a contract deployed, or a deployment-end handler (BaseHub) running its campaign.
static func campaign_running(from: Node) -> bool:
	if Contracts.is_deployed():
		return true
	for n: Node in from.get_tree().get_nodes_in_group(Extraction.END_GROUP):
		var running: Variant = n.get(&"campaign_running")
		if running is bool and running:
			return true
	return false


# --- Checks -----------------------------------------------------------------------------------------

func _should_abort() -> bool:
	if heli.occupants().size() > 0 or _flat(heli.global_position, lz) > ABORT_WITHIN_M:
		return false
	if heli.zone_health(Vehicle.ZONE_HULL) < ABORT_HULL:
		return true
	for z in Helicopter.FATAL_ZONES:
		if heli.zone_health(z) < ABORT_ZONE:
			return true
	return false


## Transport: the squad's AI within BOARD_RADIUS_M of the helicopter, up.
func _transport_ai() -> Array:
	return MapNodes.squad_ai(sup).filter(func(s: Soldier) -> bool:
		return s.vitals.is_up() and s.global_position.distance_to(heli.global_position) <= BOARD_RADIUS_M)


## Transport: every conscious player within PLAYER_NEAR_M and every AI ordered in is aboard.
func _everyone_near_aboard() -> bool:
	for p: Soldier in MapNodes.players(sup):
		if p.vitals.is_up() and Vehicle.ride_of(p) != heli and p.global_position.distance_to(heli.global_position) <= PLAYER_NEAR_M:
			return false
	for s: Soldier in _transport_ai():
		if Vehicle.ride_of(s) != heli and _ordered.has(s.get_instance_id()):
			return false
	return not heli.occupants().is_empty()


## Extraction: every player and every AI squadmate the players chose to bring is aboard.
func _all_required_aboard() -> bool:
	var extraction := MapNodes.extraction(sup)
	if extraction == null:
		return false
	var need := extraction.required()
	var all: Array = need.players + need.ai
	if all.is_empty():
		return false
	for s: Soldier in all:
		if Vehicle.ride_of(s) != heli:
			return false
	return true


func _players_aboard() -> int:
	var n := 0
	for s: Soldier in heli.occupants():
		if not s.is_ai():
			n += 1
	return n


## A smoke of `colours` the helicopter can see (in range, in its line of sight, nobody else's;
## near `near` within `within` when given), or null. Seeing a smoke of another colour, it says so.
func _seen_smoke(colours: Array, near: Variant = null, within := INF) -> SmokeCloud:
	var from := heli.global_position
	for cloud: SmokeCloud in SmokeCloud.active:
		if not is_instance_valid(cloud) or cloud.is_queued_for_deletion() or not cloud.is_inside_tree():
			continue
		var id := cloud.get_instance_id()
		var mine := cloud.colour in colours
		if (mine and (sup.claimed.has(id) or _smoke_failed.has(id))) or (not mine and (cloud.colour == "white" or _wrong_seen.has(id))):
			continue
		var at := cloud.global_position
		if from.distance_to(at) > SMOKE_SEE_M or (near != null and _flat(at, near as Vector3) > within) or not _sees(at):
			continue
		if not mine:
			_wrong_seen[id] = true
			sup.server_radio(kind, "I see %s. Not my smoke: I land on %s" % [cloud.colour, " or ".join(colours)])
		elif near != null or not _earlier_wants(cloud.colour):
			return cloud
	return null


## Whether a call made before this one is still looking for a smoke of `colour` (the first
## call takes a smoke both want: Captain's "first call takes green").
func _earlier_wants(colour: String) -> bool:
	for c in sup.calls:
		if c == self:
			return false
		if not c.is_over() and c.mark.is_empty() and (c.phase == Phase.INBOUND or c.phase == Phase.LOITER) \
				and colour in HeliSupports.smoke_colours(c._smoke_kind()) and is_instance_valid(c.heli) and c._sees_any(colour):
			return true
	return false


## Whether this helicopter can see an unclaimed smoke of `colour` now.
func _sees_any(colour: String) -> bool:
	for cloud: SmokeCloud in SmokeCloud.clouds_of(colour):
		var id := cloud.get_instance_id()
		if not sup.claimed.has(id) and not _smoke_failed.has(id) and heli.global_position.distance_to(cloud.global_position) <= SMOKE_SEE_M \
				and _sees(cloud.global_position):
			return true
	return false


func _sees(at: Vector3) -> bool:
	var space := heli.get_world_3d().direct_space_state
	var exclude: Array[RID] = [heli.get_rid()]
	var q := PhysicsRayQueryParameters3D.create(heli.global_position + Vector3.UP * 1.5, at + Vector3.UP * 3.0, 1, exclude)
	return space.intersect_ray(q).is_empty()


## Whether `pos` is within `reach` of one of the helicopter's doors.
func _by_door(pos: Vector3, reach: float) -> bool:
	for p in heli.get_children():
		if p is VehicleActionPoint and (p as VehicleActionPoint).kind == VehicleActionPoint.DOOR:
			if pos.distance_to((p as Node3D).global_position) <= reach + 1.5:
				return true
	return false


# --- Loitering ------------------------------------------------------------------------------------

func _update_orbit() -> void:
	_orbit_next = LOITER_UPDATE_S
	var lane := float(LANE.get(kind, 0))
	heli.server_orbit(_loiter_centre(), LOITER_RADIUS_M + lane * LANE_RADIUS_M, LOITER_AGL_M + lane * LANE_AGL_M, Helicopter.LOITER_KMH)


## Round the players, kept away from where it took fire lately, inside the map.
func _loiter_centre() -> Vector3:
	var c := _players_centre()
	if Soldier._now() < _threat_until:
		var away := Vector3(c.x - _threat.x, 0.0, c.z - _threat.z)
		if away.length() < 1.0:
			away = Vector3(1, 0, 0)
		c += away.normalized() * AVOID_SHIFT_M
	var area: Rect2 = level().map_area().grow(-(LOITER_RADIUS_M * 0.5))
	if area.has_area():
		c.x = clampf(c.x, area.position.x, area.end.x)
		c.z = clampf(c.z, area.position.y, area.end.y)
	return c


func _players_centre() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for p: Soldier in MapNodes.players(sup):
		if not p.vitals.is_dead():
			sum += p.global_position
			n += 1
	if n == 0:
		return caller.global_position if is_instance_valid(caller) else Vector3.ZERO
	return sum / n


# --- Events ------------------------------------------------------------------------------------------

func _on_hit(_zone: StringName, hit: Dictionary) -> void:
	var shooter: Variant = hit.get("shooter")
	var pos: Vector3 = hit.get("position", heli.global_position)
	var dir: Vector3 = hit.get("direction", Vector3.ZERO)
	_threat = (shooter as Node3D).global_position if is_instance_valid(shooter) and shooter is Node3D else pos - dir.normalized() * 150.0
	_threat_until = Soldier._now() + AVOID_S
	if is_instance_valid(shooter) and shooter is Soldier and (shooter as Soldier).faction == &"hostile":
		_shooter = shooter
	if Soldier._now() - _fire_radio_at > UNDER_FIRE_RADIO_S and not heli.is_down():
		_fire_radio_at = Soldier._now()
		sup.server_radio(kind, "Taking fire!")


func _on_down(_h: Helicopter) -> void:
	if phase == Phase.LOST:
		return
	phase = Phase.LOST
	sup.server_lost(kind)
	sup.server_radio(kind, "Mayday, mayday, %s going down!" % HeliSupports.callsign(kind))
	# Captain, 2026-10-16 ("if they get hot down we have to do a rescue"): the crew live through
	# it, hurt, by the wreck, for the squad to reach, treat, carry or Dustoff out.
	var tree := sup.get_tree()
	if tree and is_instance_valid(heli):
		tree.create_timer(CRASH_SETTLE_S).timeout.connect(_crew_survive.bind(heli.global_position))


## The downed heli's crew, CREW_SURVIVORS of them, by `at` (where it came down): friendly, hurt, one down.
func _crew_survive(at: Vector3) -> void:
	var lvl := level() as CompoundLevel
	if lvl == null or not lvl.is_inside_tree():
		return
	var callsign := String(HeliSupports.callsign(kind)).replace(" ", "")
	var placed := 0
	for i in CREW_SURVIVORS:
		var spot := lvl.ground_point(at + Vector3(randf_range(-5.0, 5.0), 0.0, randf_range(-5.0, 5.0)))
		var crew := lvl.spawn_soldier({"name": ("%s_Crew%d" % [callsign, i + 1]).validate_node_name(), "faction": "friendly",
			"variant": "tan", "pos": spot, "loadout": ["helmet", "m17", "mag_9mm"], "combat": 0.3, "discipline": 0.6,
			"guard": true, "mode": "aware"})
		if crew == null:
			continue
		placed += 1
		crew.vitals.server_hit(Vitals.THIGH_L if i == 0 else Vitals.UPPER_ARM_R, {"round_class": Vitals.FRAGMENT})
		if i == 0:
			crew.vitals.server_damage(60.0)  # the pilot took the worst of it
	if placed > 0:
		sup.server_radio(kind, "%s crew are alive at %s: %d hurt. Get to them" % [HeliSupports.callsign(kind), _grid(at), placed])


# --- Helpers --------------------------------------------------------------------------------------

func _commander() -> Soldier:
	if is_instance_valid(caller) and not caller.is_queued_for_deletion():
		return caller
	var players := MapNodes.players(sup)
	return players[0] if not players.is_empty() else null


func _smoke_kind() -> String:
	return "transport" if kind == "insertion" else kind


func _ignore() -> Array[RID]:
	var out: Array[RID] = []
	if is_instance_valid(heli):
		out.append(heli.get_rid())
	return out


func _grid(at: Vector3) -> String:
	return "grid %s" % MapGrid.grid_ref_3d(at, MapNodes.area_of(sup))


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Whether `at` lies on the map's edge (Supports.origin_for's fallback), not a registered origin.
static func _on_edge(lvl: Node, at: Vector3) -> bool:
	if not lvl.has_method(&"map_area"):
		return true
	var area: Rect2 = lvl.call(&"map_area")
	var p := Vector2(at.x, at.z)
	return absf(p.x - area.position.x) < 1.0 or absf(p.x - area.end.x) < 1.0 or absf(p.y - area.position.y) < 1.0 or absf(p.y - area.end.y) < 1.0


## One line for the state dumps.
func describe() -> String:
	var aboard := PackedStringArray()
	if is_instance_valid(heli):
		for s: Soldier in heli.occupants():
			aboard.append(s.display_name())
	var target := "%s (%.0f, %.0f)" % [String(mark.get("from", "grid")), lz.x, lz.z] if mark.has("pos") else "looking for smoke"
	return "%s (%s): %s, %s; target %s; aboard %d%s; %s" % [kind, HeliSupports.callsign(kind), Phase.keys()[phase], stage, target,
		aboard.size(), " (%s)" % ", ".join(aboard) if not aboard.is_empty() else "", heli.describe() if is_instance_valid(heli) else "no helicopter"]
