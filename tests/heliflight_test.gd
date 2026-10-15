extends Node
## Headless check of the insertion UH-60's flight over real zones' ground (Captain, 2026-10-14,
## v0.4.0: "the heli bumped into the ground on infil so maybe 10 is just a tiny bit too low",
## then "lets do 12 or 13 m"):
##   <voxel godot exe> --headless --path . res://tests/heliflight_test.tscn
## For each zone (FLIGHTS: wadi_farm and harbour_yard, contract zones with their LZs in dead
## ground near an objective; ridge_hot and coast_hot, hot zones whose LZs lie by the zone's edge,
## so the J-hook swings out past it), the briefing's helicopter insertion is flown in and landed,
## and checked: on the way in about Helicopter.CRUISE_AGL_M over the ground (8-16 m, more only
## to climb over what stands taller or ground rising ahead), the airframe (fuselage and rotor
## tips) at least Helicopter.MIN_CLEAR_M clear of the ground and what stands on it until the
## last Helicopter.FINAL_LOW_M of the final, nothing touched before touchdown, and down at the
## LZ. Every flight also prints, leg by leg ("cruise", "hook" until the last FINAL_LOW_M, "final"
## to the hover over the spot, "settle" straight down), where it came lowest: the probe for
## the next bump. Flights run at PACE (Helicopter.pace).
## While iterating: -- --zones=ridge_hot:0,1;coast_hot:2 --pace=1 (zone:insertion points).
## Exits with the number of failures.

const PACE := 2.0
## Zone -> the insertion points (indices into its def's "insertion") flown in.
const FLIGHTS := {"wadi_farm": [0], "harbour_yard": [1], "ridge_hot": [0, 1], "coast_hot": [1]}
const FLY_S := 150.0
## The way in, for the height checks: until this many metres of the J-hook are left (then it
## glides down to the LZ).
const INBOUND_LEFT_M := 120.0
const HeliFlight := preload("res://tests/heli_flight_check.gd")

var failures := 0
var main: Node
var level: ZoneLevel
var player: Soldier
var sup: HeliSupports


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_heliflight" + tag  # never touch a real save
	Campaign.campaign_id = "test_heliflight_campaign" + tag
	GameSettings.use_file(OS.get_user_data_dir().path_join("test_heliflight_settings%s.cfg" % tag))  # never the player's
	CompoundLevel.spawn_ai = false
	PeopleLayer.contract_people = false
	Contracts.auto_show_debrief = false
	Vehicle.fire_rolls = false
	Vehicle.local_input = false
	Helicopter.pace = PACE
	HeliSupports.free_calls = 99
	var plan := FLIGHTS.duplicate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pace="):
			Helicopter.pace = float(a.trim_prefix("--pace="))
		elif a.begins_with("--zones="):
			plan = {}
			for part in a.trim_prefix("--zones=").split(";"):
				var bits := part.split(":")
				plan[bits[0]] = Array(bits[1].split(",")).map(func(i: String) -> int: return int(i)) if bits.size() > 1 else [0]
	var count := 0
	for z: String in plan:
		count += (plan[z] as Array).size()
	get_tree().create_timer(60.0 + count * 100.0 / Helicopter.pace).timeout.connect(func() -> void:
		print("HELIFLIGHT TEST FAILED (timed out)")
		get_tree().quit(99))
	GameState.delete_save()
	Campaign.reset_campaign()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var first := true
	for zone_id: String in plan:
		await _zone(zone_id, plan[zone_id], first)
		first = false
	GameState.delete_save()
	print("HELIFLIGHT TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


## Hosts `zone_id` (the first, as the menu's test buttons do; the rest by a level switch) and
## flies an insertion to each of its insertion points `indices`.
func _zone(zone_id: String, indices: Array, first: bool) -> void:
	print("%s" % zone_id)
	var def := MissionRegistry.zone_def(zone_id)
	if def.is_empty():
		check(false, "%s: its zone definition" % zone_id)
		return
	if first:
		main.host_zone(def)
	else:
		LevelSwitch.load_level(main, {"level": "zone", "def": ZoneDef.normalize(def)})
	level = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		var lvl := CompoundLevel.current(main) as ZoneLevel
		if lvl and String(lvl.def.get("id", "")) == zone_id and lvl.players and lvl.players.get_node_or_null(^"1") != null:
			level = lvl
			break
	check(level != null, "%s hosted" % zone_id)
	if level == null:
		return
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # the test moves it
	sup = HeliSupports.of(level)
	VehicleHull.prewarm(HeliSupports.MODEL)
	t0 = Time.get_ticks_msec()
	while not VehicleHull.is_ready(HeliSupports.MODEL) and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	var hot := String(def.get("kind", "")) == "hot"
	var points: Array = def.get("insertion", [])
	var modules: Array = def.get("modules", [])
	for k: int in indices:
		if k >= points.size():
			check(false, "%s has insertion point %d" % [zone_id, k])
			continue
		await _fly(zone_id, k, points[k], hot, modules)


## The briefing's helicopter insertion to insertion point `k` (at `p`) of the zone, flown in
## and watched.
func _fly(zone_id: String, k: int, p: Array, hot: bool, modules: Array) -> void:
	var label := "%s insertion %d" % [zone_id, k]
	var zone := {"id": zone_id, "name": zone_id, "kind": "hot" if hot else "contract",
		"insertion_points": [{"id": "p%d" % k, "name": "P%d" % k, "pos": [float(p[0]), float(p[1])], "method": "foot"}]}
	var contract := {"id": "heliflight_%d" % k, "title": "Heli flight", "reinforcements": {"first_wave_s": 3600.0}}
	if not hot and not modules.is_empty():
		contract["objectives"] = [{"pos": (modules[k % modules.size()] as Dictionary).pos}]  # the LZ: in dead ground near it
	sup.server_reset_limits()
	player.global_position = level.ground_point(Vector3(float(p[0]), 0.0, float(p[1])))
	var briefing := MapNodes.briefing(level)
	if briefing.phase != Briefing.Phase.IDLE:
		briefing.server_close()
	briefing.server_open(contract, zone)
	var heli_id := ""
	for ip: Dictionary in briefing.insertion_points():
		if String(ip.get("method", "")) == Briefing.HELI:
			heli_id = String(ip.id)
	var started := heli_id != "" and briefing.server_set_insertion(heli_id) and briefing.server_start(true)
	var c := sup.active("insertion") if started else null
	check(c != null and is_instance_valid(c.heli) and c.heli.is_flying(), "%s: the helicopter is in the air" % label)
	if c == null or not is_instance_valid(c.heli):
		return
	print("  %s: from (%.0f, %.0f) to the LZ (%.0f, %.0f, %.0f), %.0f m" % [label, c.heli.global_position.x, c.heli.global_position.z,
		c.lz.x, c.lz.y, c.lz.z, Vector2(c.heli.global_position.x - c.lz.x, c.heli.global_position.z - c.lz.z).length()])
	var f := await _watch(label, c)
	check(int(f.frames) > 30 and float(f.min_agl) >= 8.0 and float(f.max_over) <= 16.0,
		"%s: in low, %.1f-%.1f m over the ground on the way in (8-16 m; more only to climb over what stands taller or ground rising ahead)" % [
		label, float(f.min_agl), float(f.max_over)])
	check(float(f.min_clear) >= Helicopter.MIN_CLEAR_M, "%s: the airframe at least %.0f m clear until the final, %.1f m at the least (at %s)" % [
		label, Helicopter.MIN_CLEAR_M, float(f.min_clear), f.clear_at])
	check((f.contacts as Array).is_empty(), "%s: it touched nothing before touchdown (%s)" % [
		label, "; ".join(PackedStringArray(f.contacts)) if not (f.contacts as Array).is_empty() else "nothing"])
	var off := Vector2(c.heli.global_position.x - c.lz.x, c.heli.global_position.z - c.lz.z).length() if is_instance_valid(c.heli) else INF
	check(is_instance_valid(c.heli) and c.heli.is_landed() and off <= LandingZone.ROTOR_CLEAR_M, "%s: down on the LZ (%.1f m off)" % [label, off])
	if is_instance_valid(c.heli):
		c.heli.server_exit(player)
	var t := Time.get_ticks_msec()
	while not c.is_over() and Time.get_ticks_msec() - t < 40000:
		await get_tree().physics_frame
	briefing.server_close()


func _new_leg() -> Dictionary:
	return {"frames": 0, "agl": INF, "agl_at": "", "clear": INF, "clear_at": "", "max_agl": -INF}


## Watches `c`'s flight until it lands (or FLY_S).
func _watch(label: String, c: HeliCall) -> Dictionary:
	var out := {"frames": 0, "min_agl": INF, "max_over": -INF, "min_clear": INF, "clear_at": "", "contacts": []}
	var legs := {"cruise": _new_leg(), "hook": _new_leg(), "final": _new_leg(), "settle": _new_leg()}
	var t := 0.0
	while t < FLY_S and is_instance_valid(c.heli) and not c.heli.is_landed() and not c.heli.is_down():
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var h := c.heli
		if not is_instance_valid(h) or not h.is_flying():
			continue
		var pos := h.global_position
		var vel := Vector3(h.linear_velocity.x, 0.0, h.linear_velocity.z)
		var left := h.path_left_m()
		var landing := h.has_meta(&"landing")
		var where := "(%.0f, %.1f, %.0f) %.0f m to go, %.0f km/h" % [pos.x, pos.y, pos.z, left, h.linear_velocity.length() * 3.6 / Helicopter.pace]
		var leg := "cruise"
		if h.flight_mode() == Helicopter.Mode.LANDING:
			leg = "settle"
		elif landing:
			leg = "hook" if left > Helicopter.FINAL_LOW_M else "final"
		var clear := HeliFlight.airframe_clearance(h)
		var agl := h.height_agl()
		var L: Dictionary = legs[leg]
		L.frames += 1
		if agl < float(L.agl):
			L.agl = agl
			L.agl_at = where
		if clear < float(L.clear):
			L.clear = clear
			L.clear_at = where
		L.max_agl = maxf(float(L.max_agl), pos.y - h.terrain_y(pos))
		if agl > Helicopter.TOUCH_M + 0.3:
			for body in HeliFlight.touching(h):
				if (out.contacts as Array).size() < 4:
					(out.contacts as Array).append("%s at %s" % [body.name, where])
		if leg == "cruise" or leg == "hook":
			if clear < float(out.min_clear):
				out.min_clear = clear
				out.clear_at = where
		if leg == "cruise" or (leg == "hook" and left > INBOUND_LEFT_M):
			out.frames += 1
			var over := pos.y - h.terrain_y(pos)
			out.min_agl = minf(out.min_agl, over)
			out.max_over = maxf(out.max_over, over - HeliFlight.climb_allowance(h, pos, vel))
	for leg: String in ["cruise", "hook", "final", "settle"]:
		var L: Dictionary = legs[leg]
		if int(L.frames) > 0:
			print("  [info] %s %s: lowest %.1f m over the ground at %s; airframe clearance %.1f m at the least at %s; highest %.1f m" % [
				label, leg, float(L.agl), L.agl_at, float(L.clear), L.clear_at, float(L.max_agl)])
	return out
