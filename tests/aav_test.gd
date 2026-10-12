extends Node
## Wave 5b V4: the AAV support, the LHD, the motor pool and enemy vehicle QRFs. Two processes
## over real ENet, like the vehicles suite:
##   <exe> --headless --path . res://tests/aav_test.tscn -- --aav-host
##   <exe> --headless --path . res://tests/aav_test.tscn -- --aav-join 127.0.0.1
## The host first plays an inland hot zone (ridge_hot) with new connections refused: no LHD,
## the FOB's side registered; an AAV refused when the company can't pay, in mountains and on
## ground too steep, then paid for and driving in from the FOB's edge to the caller, and going
## home; a QRF from a base riding in a technical, driving in and dismounting. Then the coastal
## test zone ("coast"): the sea and the LHD offshore as the registered origin; the motor pool
## (a damaged vehicle's state across a deployment and a save, brought, taken back, repaired for
## money and days; the briefing's entries); an AAV called from the LHD, launched astern into the
## water, swimming, climbing the beach and reaching the caller, at which point the client is let
## in (a late joiner: it sees the LHD and the AAV swimming); the commands with AI squadmates and
## the host's player (mount, move, hold, dismount, follow), then the client's player gets in
## and out; return (it heads to sea and is gone at the LHD); the gunner firing at an enemy; and
## an AAV destroyed with passengers and cargo aboard: they're lost and no other comes.
## Without arguments only the host's checks run. Each process prints AAV TEST PASSED/FAILED and
## exits with its failure count. CONTRACTOR_AAV_ONLY="pool,swim" runs only those host parts
## (the coastal call is needed by the commands).

const HOT_ZONE := "ridge_hot"
const COAST_ZONE := "coast"

var failures := 0
var main: Node
var level: ZoneLevel
var player: Soldier
var support: AavSupport
var _made := 0
var _tag := ""
var _client_id := 0
var _client_left := false
var _client_ready := false
var _client_seated := -1
var _client_done := false
var _your_turn := false
var _host_digest := {}


func _ready() -> void:
	_tag = OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_aav_hot" + _tag  # never touch a real save
	Campaign.campaign_id = "test_aav" + _tag
	CompoundLevel.spawn_ai = false
	Vehicle.local_input = false
	Vehicle.fire_rolls = false
	var args := OS.get_cmdline_user_args()
	if "--aav-join" in args:
		var i := args.find("--aav-join")
		await _run_client(args[i + 1] if i + 1 < args.size() else "127.0.0.1")
	else:
		_delete_saves()
		Campaign.reset_campaign()
		await _run_host("--aav-host" in args)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	return condition.call()


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _delete_saves() -> void:
	var was := GameState.zone_id
	for z: String in ["test_aav_hot" + _tag, "test_aav_coast" + _tag]:
		GameState.zone_id = z
		GameState.delete_save()
	GameState.zone_id = was


func _finish() -> void:
	VehicleQrf.share_override = -1.0
	if Net.is_hosting() or multiplayer.is_server():
		_delete_saves()
		Campaign.reset_campaign()
	print("AAV TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	Net.leave()
	get_tree().quit(failures)


static func _want(part: String) -> bool:
	var only := OS.get_environment("CONTRACTOR_AAV_ONLY")
	if only == "":
		return true
	for p in only.split(","):
		if part.begins_with(p):
			return true
	return false


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Host: a friendly AI squadmate at `pos` (its brain runs: it walks where it's ordered).
func _mate(pos: Vector3) -> Soldier:
	_made += 1
	return level.spawn_soldier({"name": "Mate%d" % _made, "faction": "friendly", "variant": "multicam", "pos": level.ground_point(pos),
		"loadout": ["plate_carrier", "m4a1"], "slot": _made - 1, "team": 0, "combat": 0.5, "discipline": 0.6, "guard": false})


## Host: a soldier whose brain doesn't run (a target, a passenger).
func _dummy(faction: String, pos: Vector3) -> Soldier:
	_made += 1
	var s := level.spawn_soldier({"name": "Dummy%d" % _made, "faction": faction, "variant": "urban", "pos": level.ground_point(pos),
		"loadout": ["m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
	var brain := SquadAI.of(s)
	if brain:
		brain._setup()
		brain.process_mode = Node.PROCESS_MODE_DISABLED
	return s


func _put_player(pos: Vector3) -> void:
	player.global_position = level.ground_point(pos)
	player.velocity = Vector3.ZERO


# --- Host ---------------------------------------------------------------------------------------

func _run_host(wait_for_client: bool) -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(MissionRegistry.zone_def(HOT_ZONE))
	level = CompoundLevel.current(self) as ZoneLevel
	check(level != null and Net.is_hosting(), "hosting the inland hot zone %s on port %d" % [HOT_ZONE, Net.port()])
	if level == null or not Net.is_hosting():
		_finish()
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 10.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # the tests move it
	await _frames(10)
	if _want("fob"):
		await _test_inland()
	if _want("qrf"):
		await _test_vehicle_qrf()
	await _to_coast()
	if level == null:
		_finish()
		return
	_test_lhd()
	if _want("pool"):
		await _test_motor_pool()
	if _want("swim"):
		await _test_call_and_swim(wait_for_client)
		if _want("commands"):
			await _test_commands()
		if wait_for_client:
			await _client_turn()
		if _want("return"):
			await _test_return()
	if _want("gunner"):
		await _test_gunner()
	if _want("destroyed"):
		await _test_destroyed()
	if wait_for_client:
		if _client_id == 0:
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = false
		await _wait_for(func() -> bool: return _client_left, 240.0)
		check(_client_left, "the client finished and left")
	_finish()


## Host: the coastal test zone replaces the hot zone, hosted as BaseHub switches levels.
func _to_coast() -> void:
	print("To the coast")
	GameState.zone_id = "test_aav_coast" + _tag
	var fresh := LevelSwitch.load_level(main, {"level": "zone", "def": ZoneDef.normalize(ZoneDef.get_def(COAST_ZONE))}, true) as ZoneLevel
	if fresh == null:
		check(false, "the coastal zone loads")
		level = null
		return
	fresh._on_hosted()
	level = fresh
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 10.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	await _frames(10)
	support = AavSupport.of(level)
	check(level.terrain.has_coast() and support != null, "the coastal zone (%s) hosts, with its AAV support" % COAST_ZONE)


# --- Inland: the FOB's side ----------------------------------------------------------------------

func _test_inland() -> void:
	print("Inland: the FOB's side of the map")
	support = AavSupport.of(level)
	var origin := Lhd.of(level)
	check(origin != null and not origin.is_ship() and origin.get_node_or_null(^"LHD") == null,
		"an inland zone has no LHD: its support origin is the FOB's side (%s)" % (origin.side if origin else "none"))
	var registered := Supports.origin_for(level, &"lhd")
	check(origin != null and registered.origin.is_equal_approx(origin.global_position), "the FOB's marker is the registered origin (asked for the LHD, it answers)")
	var ins := level.insertion_points()[0]
	_put_player(ins)
	# Refused: an inland contract zone, no money, mountains, too steep.
	level.def["kind"] = "contract"
	var inland_contract := support.server_call(player)
	level.def["kind"] = "hot"
	check(inland_contract.begins_with("AAVs support hot zones") and support.current() == null, "refused in an inland contract zone: %s" % inland_contract)
	var cash := Economy.cash()
	Economy.spend(cash - 100, "test: broke")
	var why := support.server_call(player)
	check(why.begins_with("Can't afford") and support.current() == null and Economy.cash() == 100, "refused when the company can't pay: %s" % why)
	Economy.add_cash(cash - 100, "test: solvent again")
	level.def["terrain"] = "mountain"
	why = support.server_call(player)
	level.def.erase("terrain")
	check(why.contains("mountains") and support.current() == null and Economy.cash() == cash, "refused in mountains (the zone's terrain): %s" % why)
	var saved := level.terrain.heights.duplicate()
	_steepen(player.global_position)
	why = support.server_call(player)
	level.terrain.heights = saved
	check(why.begins_with("Too steep") and support.current() == null and Economy.cash() == cash, "refused on a steep slope on its way: %s" % why)
	check(support.route_slope_deg(player.global_position, player.global_position + Vector3(30, 0, 0)) < 31.0, "the ground there is fine again")
	# Paid, from the FOB's edge.
	why = support.server_call(player)
	var v := support.current()
	check(why == "" and v != null and Economy.cash() == cash - Prices.support_price("aav"),
		"called: paid $%s (cash %d -> %d)" % [Prices.support_price("aav"), cash, Economy.cash()])
	if v == null:
		return
	check(_flat(v.global_position, origin.edge_point(player.global_position)) < 6.0, "it comes in from the FOB's edge level with the caller")
	check(v.driver() != null and v.driver().has_meta(&"vehicle_crew") and v.gunner() != null and v.gunner().has_meta(&"vehicle_crew") and v.faction == &"player",
		"with its AI crew: a driver and a gunner")
	check(not level.squad_for(&"friendly").members().has(v.driver()), "the crew takes no squad orders")
	for i in 4:
		await _seconds(1.0)
		print("    %s" % _vstate(v))
	var arrived := await _wait_for(func() -> bool: return support.order == AavSupport.HOLD, 60.0)
	check(arrived and _flat(v.global_position, player.global_position) < float(AavSupport.data().aav.arrive_m) + 8.0,
		"it drives to the caller and holds there (%.1f m away; %s)" % [_flat(v.global_position, player.global_position), support.last_message])
	check(support.server_call(player).begins_with("The AAV is already out"), "one at a time")
	var crew := v.occupants()
	why = support.server_return(player)
	var gone := await _wait_for(func() -> bool: return support.current() == null and support.order == "", 60.0)
	check(why == "" and gone and crew.all(func(s: Variant) -> bool: return not is_instance_valid(s) or (s as Node).is_queued_for_deletion()),
		"return: it drives back to the FOB's edge and is gone, crew and all")


## Host, debugging: how a vehicle is driving.
func _vstate(v: Vehicle) -> String:
	if not is_instance_valid(v):
		return "(gone)"
	var ai := v.ai
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = VehicleArt.size_m(v.model) * Vector3(1.0, 0.8, 1.0)
	q.shape = box
	q.transform = Transform3D(v.global_basis, v.global_transform * Vector3(0, box.size.y * 0.5 + 0.35, -0.6))
	q.collision_mask = 0xFFFF
	q.exclude = [v.get_rid()]
	var touching: Array[String] = []
	for h: Dictionary in v.get_world_3d().direct_space_state.intersect_shape(q, 8):
		touching.append(String((h.collider as Node).name) if h.collider is Node else "?")
	var pitch := rad_to_deg(asin(clampf(-v.global_basis.z.y, -1.0, 1.0)))
	return "pitch %.1f° ahead hits %s | " % [pitch, touching] + "at (%.1f, %.2f, %.1f) v %.2f m/s | ai %s %s path %d/%d left %.0f | input %s | drive %s sleep %s freeze %s | driver %s | depth %.2f" % [
		v.global_position.x, v.global_position.y, v.global_position.z, v.linear_velocity.length(),
		ai.status if ai else "-", "on" if ai and ai.active else "off", ai.index if ai else 0, ai.path.size() if ai else 0, ai.remaining() if ai else 0.0,
		v._current_input(), v.can_drive(), v.sleeping, v.freeze, v.driver().name if v.driver() else "none", AavWater.depth(v)]


## Host: the ground round `at` made a 45° ramp (the heights only; collision is left alone).
func _steepen(at: Vector3) -> void:
	var t := level.terrain
	var g := t._grid_index(Vector2(at.x, at.z))
	for j in range(g.y - 5, g.y + 6):
		for i in range(g.x - 5, g.x + 6):
			if i >= 0 and j >= 0 and i < t.points and j < t.points:
				t.heights[i + j * t.points] = float(i - g.x) * ZoneTerrain.CELL_M


# --- Hot zone: a QRF in a technical --------------------------------------------------------------

func _test_vehicle_qrf() -> void:
	print("A QRF in a technical")
	var er := EnemyResponse.of(level)
	var alert := Alert.of(level)
	var bases := level.modules().filter(func(m: ZoneModule) -> bool: return m.type == "qrf_base")
	check(er != null and alert != null and not bases.is_empty(), "the hot zone has an enemy response and a QRF base")
	if er == null or alert == null or bases.is_empty():
		return
	var base: ZoneModule = bases[0]
	var spot := _open_spot(base.global_position, 330.0)
	_put_player(spot)
	VehicleQrf.share_override = 1.0
	_calm(alert)
	er._last_qrf = -INF
	er._qrf_due = INF
	er._turnout = false
	alert.zone_state = Alert.State.ALERTED
	er._zone_was = Alert.State.ALERTED
	var n := er.qrf_launches.size()
	var lk := level.ground_point(spot + (base.global_position - spot).normalized() * 10.0)
	alert._receive({"kind": &"contact", "pos": lk, "area": alert.area_of(lk), "by": ""})
	var vq := VehicleQrf.of(level)
	check(er.qrf_launches.size() == n + 1 and vq != null and not vq.convoys.is_empty(),
		"engaged: the QRF launches from %s and rides in a technical" % (er.qrf_launches.back().get("from", "?") if er.qrf_launches.size() > n else "nowhere"))
	if vq == null or vq.convoys.is_empty():
		VehicleQrf.share_override = -1.0
		return
	var c: Dictionary = vq.convoys[0]
	var tech: Vehicle = c.vehicle
	var riders: Array = c.soldiers
	var wave: Array = er.qrf_launches.back().soldiers
	for s: Variant in wave:
		if is_instance_valid(s) and SquadAI.of(s as Soldier):
			SquadAI.of(s as Soldier).hold_fire = true  # the test's player stays alive
	tech.cargo_hold.clear_all()  # and the DShK dry
	check(tech.faction == &"hostile" and tech.model.begins_with("technical") and tech.driver() != null and tech.gunner() != null and riders.size() >= 2,
		"an enemy %s with the wave aboard: driver, gunner, %d in all" % [tech.model, riders.size()])
	var start := tech.global_position
	var out := await _wait_for(func() -> bool: return bool(c.out) or not is_instance_valid(tech), 70.0)
	var off := riders.filter(func(s: Variant) -> bool: return is_instance_valid(s) and Vehicle.ride_of(s as Soldier) == null and (s as Soldier).vitals.is_up())
	check(out and is_instance_valid(tech) and _flat(tech.global_position, start) > 40.0 and _flat(tech.global_position, c.dismount) < 45.0,
		"it drives in toward the contact (%.0f m) and stops short" % (_flat(tech.global_position, start) if is_instance_valid(tech) else 0.0))
	check(off.size() == riders.size(), "the men get out there and go on foot (%d of %d)" % [off.size(), riders.size()])
	var waves := MapNodes.reinforcements(level).waves
	var squad := waves.back().get("squad") as Squad if not waves.is_empty() else null
	check(squad != null and squad.patrol.any(func(p: Vector3) -> bool: return _flat(p, lk) < 3.0), "as their wave, headed for the last known position")
	# Too short a drive: on foot.
	var near := base.global_position + (spot - base.global_position).normalized() * 40.0
	check(not VehicleQrf.server_mount(level, base, base.global_position, near, [player]), "not worth driving under %d m: the wave walks" % int(AavSupport.data().vehicle_qrf.min_drive_m))
	VehicleQrf.share_override = 0.0
	n = vq.convoys.size()
	check(not VehicleQrf.server_mount(level, base, base.global_position, spot, wave), "with the share at 0 no technical")
	VehicleQrf.share_override = -1.0
	for s: Variant in wave:
		if is_instance_valid(s):
			(s as Node).queue_free()
	if is_instance_valid(tech):
		tech.queue_free()
	vq.convoys.clear()
	await _frames(5)


## A point `dist` from `from` in the direction with the most room from every module, inside the zone.
func _open_spot(from: Vector3, dist: float) -> Vector3:
	var best := from
	var best_room := -1.0
	var keep := level.terrain.size_m * 0.5 - 150.0
	for k in 16:
		var p := from + Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 16.0) * dist
		if absf(p.x) > keep or absf(p.z) > keep:
			continue
		var room := INF
		for m: ZoneModule in level.modules():
			room = minf(room, _flat(m.global_position, p))
		if room > best_room:
			best_room = room
			best = p
	return best


func _calm(alert: Alert) -> void:
	alert.areas = {}
	alert.zone_state = Alert.State.NORMAL
	alert.lkp = {}
	alert._pending.clear()
	alert._overdue.clear()
	alert.comms_down = false
	for m: ZoneModule in level.modules():
		alert._check_ins[m.module_id] = INF


# --- The coast: the LHD --------------------------------------------------------------------------

func _test_lhd() -> void:
	print("The LHD offshore")
	var t := level.terrain
	var lhd := Lhd.of(level)
	check(lhd != null and lhd.is_ship() and lhd.get_node_or_null(^"LHD") != null, "a coastal zone has the company's LHD")
	if lhd == null or not lhd.is_ship():
		return
	var p := lhd.global_position
	check(t.shore_distance(p.x, p.z) < -80.0 and t.water_height(p.x, p.z) > t.height_at(p.x, p.z) + 6.0,
		"offshore, in deep water (%.0f m out, %.0f m deep)" % [-t.shore_distance(p.x, p.z), t.water_height(p.x, p.z) - t.height_at(p.x, p.z)])
	var ins := level.insertion_points()[0]
	check(t.water_height(ins.x, ins.z) == -INF and t.shore_distance(ins.x, ins.z) > 50.0, "the insertion point is dry land, %.0f m inland" % t.shore_distance(ins.x, ins.z))
	var beach := t.shore_point(ins, 0.0)
	check(absf(t.height_at(beach.x, beach.z) - ZoneTerrain.SEA_LEVEL_M) < 0.6 and t.height_at(beach.x, beach.z + 80.0 * t.seaward().z) < -3.0,
		"a beach at the waterline, the seabed falling away beyond it")
	var deck := lhd.deck()
	check(Supports.origin_for(level, &"lhd").origin.is_equal_approx(deck.global_position) and Supports.origin_for(level).origin.is_equal_approx(deck.global_position),
		"the LHD's flight deck is the registered origin for every support")
	var hit := level.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(deck.global_position + Vector3.UP * 30.0, deck.global_position + Vector3.DOWN * 5.0, 1))
	check(not hit.is_empty() and absf((hit.position as Vector3).y - LhdArt.DECK_M) < 0.5, "its flight deck is solid, %.0f m above the water" % LhdArt.DECK_M)
	var nav := level.terrain.triangles_in(Rect2(beach.x - 30.0, beach.z - 200.0, 60.0, 400.0))
	var under := 0
	for v in nav:
		if v.y < ZoneTerrain.SEA_LEVEL_M - 2.0:
			under += 1
	check(under == 0 and nav.size() > 0, "nobody walks on the seabed: the navigation leaves it out")


# --- The motor pool ------------------------------------------------------------------------------

func _test_motor_pool() -> void:
	print("The motor pool")
	Campaign.section(MotorPool.SECTION).clear()
	var start := MotorPool.list()
	check(start.size() == 1 and String(start[0].model) == "matv", "a new campaign's pool: one M-ATV")
	var extra := MotorPool.add("maxxpro")
	check(MotorPool.list().size() == 2 and MotorPool.remove(extra) and MotorPool.list().size() == 1, "vehicles join and leave it")
	var id := String(start[0].id)
	var at := level.insertion_points()[0] + Vector3(30, 0, -40)
	var v := MotorPool.server_bring(id, level, Transform3D(Basis(), level.ground_point(at)))
	check(v != null and v.vehicle_id == "pool_" + id and MotorPool.problem(id) == "Out on a deployment" and MotorPool.server_bring(id, level, Transform3D()) == null,
		"brought on a deployment (and not twice)")
	if v == null:
		return
	await _seconds(1.0)
	v.server_set_zone(Vehicle.ZONE_ENGINE, 0.4)
	v.server_set_zone(Vehicle.ZONE_WHEELS, 0.7)
	v.server_set_fuel(100.0)
	v.server_set_battery(false)
	v._add_carves([[0.0, 1.5, -1.0, 0.1, VehicleHull.HOLE]])
	v.cargo_hold.take(&"jerrycan", 1)
	check(GameState.vehicles.is_empty() and level.get_node(^"Vehicles").records().all(func(r: Dictionary) -> bool: return String(r.id) != v.vehicle_id),
		"out with the squad it isn't saved with the zone")
	var node := MotorPoolNode.of(level)
	node.server_settle([v.global_position])
	await _frames(2)
	var e := MotorPool.entry(id)
	var zones: Dictionary = e.record.get("zones", {})
	check(not is_instance_valid(v) or v.is_queued_for_deletion(), "extracted with the squad: it leaves the zone")
	check(String(e.out) == "" and absf(float(zones.engine) - 0.4) < 0.01 and absf(float(zones.wheels) - 0.7) < 0.01 and absf(float(e.record.fuel) - 100.0) < 1.0
		and not bool(e.record.battery) and (e.record.carves as Array).size() == 1,
		"home, with its damage, fuel, dead battery and hull holes kept")
	Campaign.save_campaign()
	Campaign.load_campaign()
	e = MotorPool.entry(id)
	check(not e.is_empty() and absf(float(e.record.zones.engine) - 0.4) < 0.01 and absf(float(e.record.fuel) - 100.0) < 1.0, "and across a save and a reload")
	var again := MotorPool.server_bring(id, level, Transform3D(Basis(), level.ground_point(at)))
	await _frames(3)
	check(again != null and absf(again.zone_health(Vehicle.ZONE_ENGINE) - 0.4) < 0.01 and absf(again.fuel_litres() - 100.0) < 1.0 and not again.battery_ok
		and again.cargo_hold.count_of(&"jerrycan") == 1 and again.net_carves.size() == 1,
		"brought again as it was: engine 40%, 100 L, its jerrycan, its hole")
	# Left behind: gone from the pool, the zone keeps it.
	node.server_settle([at + Vector3(500, 0, 0)])
	check(MotorPool.entry(id).is_empty() and is_instance_valid(again) and not again.is_queued_for_deletion() and not again.has_meta(&"no_save"),
		"left behind: out of the pool, it stays in the zone")
	if is_instance_valid(again):
		again.queue_free()
	# The workshop.
	var hurt := MotorPool.add("matv", "", {"zones": {"hull": 0.5, "engine": 0.2, "wheels": 1.0, "fuel": 1.0}, "fuel": 50.0, "battery": true})
	var quote := MotorPool.repair_quote(hurt)
	var cash := Economy.cash()
	var day := Economy.day()
	var why := MotorPool.server_repair(hurt)
	var fixed := MotorPool.entry(hurt)
	check(int(quote.cost) > 0 and int(quote.days) >= 1 and why == "" and Economy.cash() == cash - int(quote.cost),
		"serviced for $%d and %d days" % [int(quote.cost), int(quote.days)])
	check(float(fixed.record.zones.engine) == 1.0 and float(fixed.record.zones.hull) == 1.0 and float(fixed.record.fuel) == 300.0
		and MotorPool.problem(hurt).begins_with("In the workshop"), "whole and fuelled, in the workshop until day %d" % int(fixed.ready_day))
	Economy.advance_days(int(quote.days))
	check(MotorPool.problem(hurt) == "" and Economy.day() == day + int(quote.days), "ready again %d days later" % int(quote.days))
	check(MotorPool.server_repair(hurt) == "Nothing to repair", "nothing more to fix")
	Economy.spend(Economy.cash() - 10, "test: broke")
	MotorPool.entry(hurt)
	var hurt2 := MotorPool.add("matv", "", {"zones": {"hull": 0.1}, "fuel": 300.0})
	check(MotorPool.server_repair(hurt2).begins_with("Can't afford"), "not without the money")
	Economy.add_cash(200000, "test: solvent again")
	MotorPool.remove(hurt2)
	# The briefing offers it; starting brings it to the insertion; extraction takes it home.
	var briefing := MapNodes.briefing(level)
	briefing.auto_flow = false
	var zone := {"id": COAST_ZONE, "name": "Coast", "kind": "contract", "insertion_points": [{"id": "beach", "name": "Beach", "pos": [level.insertion_points()[0].x, level.insertion_points()[0].z], "method": "foot"}]}
	briefing.server_open({"id": "test", "title": "Test job"}, zone)
	var ids := briefing.available_supports()
	check(ids.has(Briefing.POOL_PREFIX + hurt) and briefing.support_name(Briefing.POOL_PREFIX + hurt).contains("M-ATV") and ids.has("aav") and not ids.has("transport"),
		"the briefing offers the pool's M-ATV, and AAVs on a coastal contract zone (%s)" % [ids])
	check(briefing.server_set_support(Briefing.POOL_PREFIX + hurt, true) and briefing.server_start(true), "picked; the deployment starts")
	await _frames(3)
	var brought := level.get_node(^"Vehicles").find("pool_" + hurt) as Vehicle
	check(brought != null and _flat(brought.global_position, level.insertion_points()[0]) < 25.0, "the M-ATV waits at the insertion point")
	if brought:
		brought.server_set_zone(Vehicle.ZONE_HULL, 0.8)
	var ext := MapNodes.extraction(level)
	var lz := level.insertion_points()[0]
	ext.deployment_ended.emit({"point": {"name": "LZ", "pos": [lz.x, lz.z]}})
	await _frames(2)
	check(MotorPool.entry(hurt).out == "" and absf(float(MotorPool.entry(hurt).record.zones.hull) - 0.8) < 0.01, "extracting beside it takes it home with its damage")
	briefing.server_close()
	MotorPool.remove(hurt)


# --- The coast: an AAV from the LHD --------------------------------------------------------------

func _test_call_and_swim(open_for_client: bool) -> void:
	print("An AAV from the LHD")
	var t := level.terrain
	var ins := level.insertion_points()[0]
	_put_player(t.shore_point(ins, 45.0))
	var cash := Economy.cash()
	var why := support.server_call(player)
	var v := support.current()
	check(why == "" and v != null and Economy.cash() == cash - Prices.support_price("aav"), "called on a coastal contract zone: paid $%d" % Prices.support_price("aav"))
	if v == null:
		return
	var lhd := Lhd.of(level)
	var stern := (lhd.get_node(^"LHD/Stern") as Node3D).global_position
	check(_flat(v.global_position, stern) < 35.0 and t.water_height(v.global_position.x, v.global_position.z) > t.height_at(v.global_position.x, v.global_position.z),
		"launched from the LHD's stern into the water (%.0f m astern)" % _flat(v.global_position, stern))
	if open_for_client:
		print("[host] letting the client in")
		Net.peer_joined.connect(func(id: int) -> void: _client_id = id)
		Net.peer_left.connect(func(_id: int) -> void: _client_left = true)
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = false
	await _seconds(6.0)
	var afloat := AavWater.afloat(v)
	var y := v.global_position.y
	var tilt := rad_to_deg(acos(clampf(v.global_basis.y.y, -1.0, 1.0)))
	check(afloat and y > -2.0 and y < 0.2 and tilt < 12.0, "it floats level (origin %.2f m, tilted %.0f°)" % [y, tilt])
	var top := [0.0]  # (lambdas capture by value: a box)
	var started := v.global_position
	var next_note := [Time.get_ticks_msec()]
	var swam := await _wait_for(func() -> bool:
		if AavWater.afloat(v):
			top[0] = maxf(float(top[0]), Vector2(v.linear_velocity.x, v.linear_velocity.z).length())
		if Time.get_ticks_msec() >= int(next_note[0]):
			next_note[0] = Time.get_ticks_msec() + 8000
			print("    %s" % _vstate(v))
		return AavWater.depth(v) <= 0.0 and t.shore_distance(v.global_position.x, v.global_position.z) > 2.0, 120.0)
	print("    (swim: top %.2f m/s, at (%.0f, %.1f, %.0f), %s, %s)" % [float(top[0]), v.global_position.x, v.global_position.y, v.global_position.z, support.order, support.last_message])
	check(swam and float(top[0]) > 2.0 and float(top[0]) < 13.0 / 3.6 + 0.8, "it swims in at up to %.1f km/h and climbs out onto the beach" % (float(top[0]) * 3.6))
	check(_flat(v.global_position, started) > 60.0 and t.water_height(v.global_position.x, v.global_position.z) < t.height_at(v.global_position.x, v.global_position.z) + 0.5,
		"and it's on the land now (%.0f m inland)" % t.shore_distance(v.global_position.x, v.global_position.z))
	var arrived := await _wait_for(func() -> bool: return support.order == AavSupport.HOLD, 60.0)
	check(arrived and _flat(v.global_position, player.global_position) < float(AavSupport.data().aav.arrive_m) + 8.0,
		"it drives on to the caller and holds (%.1f m away)" % _flat(v.global_position, player.global_position))


func _test_commands() -> void:
	print("Commands with squadmates and a player")
	var v := support.current()
	if v == null:
		check(false, "an AAV is there to command")
		return
	var mates: Array[Soldier] = []
	for i in 3:
		mates.append(_mate(player.global_position + Vector3(-3.0 + 3.0 * i, 0, 4.0)))
	await _seconds(1.0)
	var why := support.server_mount(player, PackedStringArray())
	var boarded := await _wait_for(func() -> bool: return mates.all(func(s: Soldier) -> bool: return Vehicle.ride_of(s) == v), 70.0)
	check(why == "" and boarded and mates.all(func(s: Soldier) -> bool: return v.seat_of(s) > 2),
		"mount: the squadmates walk to the ramp and get in the back (%d of 3)" % mates.filter(func(s: Soldier) -> bool: return Vehicle.ride_of(s) == v).size())
	var ramp := support.ramp()
	player.global_position = ramp + _flat_dir(ramp - v.global_position) * 1.0
	await _frames(2)
	v.request_enter(-1)  # the host's own player, through the ramp (Left Ctrl's request)
	check(Vehicle.ride_of(player) == v and v.seat_kind(v.seat_of(player)) == Vehicle.PASSENGER, "the player gets in at the ramp")
	# Move.
	var to := level.ground_point(v.global_position + _inland() * 55.0 + Vector3(25, 0, 0))
	why = support.server_move(player, to)
	var moved := await _wait_for(func() -> bool: return support.order == AavSupport.HOLD, 45.0)
	check(why == "" and moved and _flat(v.global_position, to) < 8.0 and v.occupants().size() == 6, "move: it drives there with everyone aboard and holds (%.1f m off)" % _flat(v.global_position, to))
	# Hold.
	why = support.server_move(player, level.ground_point(v.global_position + Vector3(-160, 0, 0)))
	await _seconds(4.0)
	var going := Vector2(v.linear_velocity.x, v.linear_velocity.z).length()
	why = support.server_hold(player)
	var held := await _wait_for(func() -> bool: return Vector2(v.linear_velocity.x, v.linear_velocity.z).length() < 0.4, 10.0)
	check(going > 2.0 and held and support.order == AavSupport.HOLD and not v.ai.active, "hold: under way at %.1f m/s, it stops" % going)
	# Dismount.
	why = support.server_dismount(player)
	await _frames(3)
	var aboard := v.occupants()
	check(why == "" and aboard.size() == 2 and aboard.all(func(s: Soldier) -> bool: return s.has_meta(&"vehicle_crew")) and Vehicle.ride_of(player) == null,
		"dismount: everyone in the back gets out, the crew stays")
	check(mates.all(func(s: Soldier) -> bool: return SquadAI.of(s).order == Squad.Order.FOLLOW), "and the squadmates fall in on the player")
	check(support.server_dismount(player) == "Nobody in the back", "nobody left to get out")
	# Follow.
	_put_player(v.global_position + _inland() * 70.0)
	why = support.server_follow(player)
	var followed := await _wait_for(func() -> bool: return _flat(v.global_position, player.global_position) <= float(AavSupport.data().aav.follow_m) and not v.ai.active, 50.0)
	check(why == "" and followed and support.order == AavSupport.FOLLOW, "follow: it closes up on the player (%.1f m)" % _flat(v.global_position, player.global_position))
	for s in mates:
		s.queue_free()
	await _frames(2)


func _flat_dir(d: Vector3) -> Vector3:
	return Vector3(d.x, 0.0, d.z).normalized()


## Inland, away from the sea.
func _inland() -> Vector3:
	return -level.terrain.seaward()


## Host: the client's player gets in the AAV and out again.
func _client_turn() -> void:
	print("The client gets in")
	var v := support.current()
	var ready := await _wait_for(func() -> bool: return _client_ready, 150.0)
	check(ready and _client_id != 0, "the client joined and saw the AAV")
	if not ready or v == null:
		return
	support.server_hold(player)
	_your_turn_rpc.rpc_id(_client_id)
	var sat := await _wait_for(func() -> bool:
		var p := level.players.get_node_or_null(str(_client_id)) as Soldier
		return p != null and v.seat_of(p) >= 0, 40.0)
	check(sat, "the host sees the client's player seated in the AAV")
	var done := await _wait_for(func() -> bool: return _client_done, 40.0)
	var p := level.players.get_node_or_null(str(_client_id)) as Soldier
	check(done and p != null and v.seat_of(p) < 0, "and out again")


func _test_return() -> void:
	print("Return to the LHD")
	var v := support.current()
	if v == null:
		check(false, "an AAV is there to send home")
		return
	_put_player(v.global_position + _inland() * 20.0)
	var lhd := Lhd.of(level)
	var why := support.server_return(player)
	check(why == "" and support.order == AavSupport.RETURN, "sent home")
	var wet := await _wait_for(func() -> bool: return AavWater.depth(v) > 0.5, 70.0)
	var before := _flat(v.global_position, lhd.dock_point(v.global_position))
	await _seconds(4.0)
	check(wet and _flat(v.global_position, lhd.dock_point(v.global_position)) < before - 3.0, "it takes to the water and swims for the LHD")
	# Most of the way there (the swim is long): it's gone at the stern.
	var dock := lhd.dock_point(v.global_position)
	v.global_transform = Transform3D(v.global_basis, Vector3(dock.x, v.global_position.y, dock.z) - _flat_dir(dock - v.global_position) * 10.0 + _inland() * 15.0)
	v.linear_velocity = Vector3.ZERO
	var gone := await _wait_for(func() -> bool: return support.current() == null, 30.0)
	check(gone and support.order == "" and not support.lost, "back at the stern it's gone (aboard the LHD)")


func _test_gunner() -> void:
	print("The AAV's gunner")
	var why := support.server_call(player, true)  # dev: free
	var v := support.current()
	check(why == "" and v != null, "a dev call: free, anywhere")
	if v == null:
		return
	var spot := level.ground_point(player.global_position + _inland() * 12.0)
	v.global_transform = Transform3D(Basis.looking_at(_inland(), Vector3.UP), spot + Vector3.UP * 0.4)
	v.linear_velocity = Vector3.ZERO
	support.server_hold(player)
	_put_player(spot - _inland() * 20.0 + Vector3(15, 0, 0))
	var foe := _dummy("hostile", spot + _inland() * 60.0)
	var g := v.get_node_or_null(NodePath(AavGunner.NODE_NAME)) as AavGunner
	var fired := await _wait_for(func() -> bool: return g != null and g.fired >= 3, 20.0)
	check(fired and g.target == foe or (fired and not foe.vitals.is_up()), "the gunner fires the M2 at an enemy in sight (%d rounds)" % (g.fired if g else 0))
	await _wait_for(func() -> bool: return not foe.vitals.is_up(), 10.0)
	foe.queue_free()


func _test_destroyed() -> void:
	print("Destroyed with passengers aboard")
	var v := support.current()
	if v == null:
		support.server_call(player, true)
		v = support.current()
		if v:
			var spot := level.ground_point(player.global_position + _inland() * 12.0)
			v.global_transform = Transform3D(Basis.looking_at(_inland(), Vector3.UP), spot + Vector3.UP * 0.4)
			support.server_hold(player)
	if v == null:
		check(false, "an AAV to lose")
		return
	await _seconds(1.0)
	var riders: Array[Soldier] = []
	for i in 2:
		var s := _dummy("friendly", v.global_position + Vector3(4, 0, i * 2.0))
		check(v.server_enter(s, 3 + i), "a squadmate rides in the back")
		riders.append(s)
	v.cargo_hold.take(&"jerrycan", 1)
	var crew := v.occupants().filter(func(s: Soldier) -> bool: return s.has_meta(&"vehicle_crew"))
	var cash := Economy.cash()
	v.server_start_fire(2.0)
	check(support.lost and support.order == AavSupport.LOST, "on fire it counts as lost")
	var wrecked := await _wait_for(func() -> bool: return v.wrecked, 10.0)
	check(wrecked and riders.all(func(s: Soldier) -> bool: return s.vitals.is_dead()) and crew.all(func(s: Soldier) -> bool: return s.vitals.is_dead()),
		"burned out: the passengers and the crew are dead")
	check(v.cargo_hold.count_of(&"jerrycan") == 0 and v.cargo_hold.count_of(&"belt_50bmg") == 0, "and the cargo is gone")
	check(support.server_call(player).contains("lost") and support.server_call(player, true).contains("lost") and Economy.cash() == cash,
		"no other AAV for the rest of the op, and nothing refunded or charged")
	check(level.get_node(^"Vehicles").records().any(func(r: Dictionary) -> bool: return String(r.id) == v.vehicle_id), "its wreck stays with the zone")
	var dump := AavSupport.state_text(level)
	check(dump.contains("AAV support: lost (LOST)") and dump.contains(v.vehicle_id) and dump.contains("WRECK"), "the session log's state dump lists it")


# --- Host <-> client -----------------------------------------------------------------------------

@rpc("any_peer", "reliable")
func _ask_digest() -> void:
	var lhd := Lhd.of(level)
	var v := support.current() if support else null
	_reply_digest.rpc_id(multiplayer.get_remote_sender_id(), {"lhd": lhd.global_position if lhd else Vector3.INF,
		"aav": v.vehicle_id if v else "", "order": support.order if support else ""})


@rpc("authority", "reliable")
func _reply_digest(digest: Dictionary) -> void:
	_host_digest = digest


@rpc("any_peer", "reliable")
func _client_saw() -> void:
	_client_ready = true


@rpc("authority", "reliable")
func _your_turn_rpc() -> void:
	_your_turn = true


@rpc("any_peer", "reliable")
func _client_out() -> void:
	_client_done = true


# --- Client --------------------------------------------------------------------------------------

func _run_client(address: String) -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var joined := [false]
	Net.joined.connect(func() -> void: joined[0] = true)
	var deadline := Time.get_ticks_msec() + 400000
	while not joined[0] and Time.get_ticks_msec() < deadline:
		var peer := multiplayer.multiplayer_peer
		if not (peer is ENetMultiplayerPeer) or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			Net.join(address)
		await get_tree().create_timer(2.0).timeout
	print("Client joining the coast late")
	check(joined[0], "joined the host's session")
	await _wait_for(func() -> bool: return CompoundLevel.current(self) is ZoneLevel and String((CompoundLevel.current(self) as ZoneLevel).def.get("id", "")) == COAST_ZONE, 20.0)
	level = CompoundLevel.current(self) as ZoneLevel
	check(level != null and String(level.def.get("id", "")) == COAST_ZONE, "the host's coastal zone loaded here")
	if level == null:
		_finish()
		return
	var me_id := str(multiplayer.get_unique_id())
	await _wait_for(func() -> bool: return level.players.get_node_or_null(me_id) != null, 15.0)
	player = level.players.get_node_or_null(me_id)
	support = AavSupport.of(level)
	_ask_digest.rpc_id(1)
	await _wait_for(func() -> bool: return not _host_digest.is_empty(), 10.0)
	var lhd := Lhd.of(level)
	check(lhd != null and lhd.is_ship() and lhd.get_node_or_null(^"LHD") != null and lhd.global_position.distance_to(_host_digest.get("lhd", Vector3.INF)) < 0.01,
		"the LHD lies offshore here too, where the host has it")
	await _wait_for(func() -> bool: return support != null and support.current() != null, 15.0)
	var v := support.current() if support else null
	check(v != null and v.vehicle_id == String(_host_digest.get("aav", "")) and support.order != "", "the AAV the host called is here, %s" % (support.order_text() if support else "?"))
	if v == null or player == null:
		_client_saw.rpc_id(1)
		_finish()
		return
	var p0 := v.global_position
	await _seconds(2.0)
	var wet := AavWater.depth(v) > 0.0
	check(wet and v.global_position.distance_to(p0) > 2.0 and v.global_position.y < 0.5,
		"the late joiner sees it swim (%.1f m in 2 s, depth %.1f m)" % [v.global_position.distance_to(p0), AavWater.depth(v)])
	_client_saw.rpc_id(1)
	await _wait_for(func() -> bool: return _your_turn, 300.0)
	check(_your_turn, "the host gave the client its turn")
	if not _your_turn:
		_finish()
		return
	await _seconds(1.0)
	var ramp := support.ramp()
	player.set_physics_process(false)
	player.global_position = ramp + _flat_dir(ramp - v.global_position) * 1.0
	var sat := false
	for attempt in 10:
		await _seconds(0.6)
		v.request_enter.rpc_id(1, -1)
		sat = await _wait_for(func() -> bool: return Vehicle.ride_of(player) == v, 2.0)
		if sat:
			break
	check(sat and v.seat_kind(v.seat_of(player)) == Vehicle.PASSENGER, "the client's player gets in at the ramp (Left Ctrl)")
	await _seconds(1.0)
	v.request_exit.rpc_id(1)
	var out := await _wait_for(func() -> bool: return Vehicle.ride_of(player) == null, 10.0)
	check(out, "and gets out again")
	_client_out.rpc_id(1)
	await _seconds(1.0)
	_finish()
