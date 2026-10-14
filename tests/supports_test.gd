extends Node
## Wave 5b V3, helicopter supports: the Black Hawk's resupply, transport, extraction and
## insertion (HeliSupports, HeliCall, Helicopter, LandingZone). Two processes over real ENet,
## like the vehicles suite:
##   <exe> --headless --path . res://tests/supports_test.tscn -- --supports-host
##   <exe> --headless --path . res://tests/supports_test.tscn -- --supports-join 127.0.0.1
## The host hosts a small hot zone (tests/supports_zone.gd: its weather can ground aircraft)
## and runs its checks with new connections refused: data and the menu, landing safety (a wall,
## a slope, a vehicle, people, nowhere within 100 m), refusals (outside a hot zone, grounded,
## no marker, a bad grid, nothing to extract from), payment (the support budget then cash,
## refused when unaffordable, cooldowns), each call by grid and by smoke of each allowed colour
## (a wrong colour ignored, the first call takes green), the loiter, an unsafe spot landed off,
## the pallet's load, transport pickup and drop-off of the player and AI, extraction with an HVT
## and deposited items ending the deployment with the right report, the helicopter insertion,
## shot down with passengers and cargo aboard (lost, and gone for the op), the state dump. Then
## it leaves a helicopter in the air and lets the client in: the late joiner sees it flying,
## then calls a resupply itself and sees it fly in, land and leave.
## Flights run at Helicopter.pace PACE and start START_M out, so the suite fits its time.
## Without arguments only the host's checks run. Each process prints SUPPORTS TEST
## PASSED/FAILED and exits with its failure count; the host exits when the client leaves.

const DEF := {"id": "supports_test", "name": "Supports test", "kind": "hot", "size_m": 1280, "seed": 11, "relief_m": 2.0,
	"modules": [], "insertion": [[0.0, 250.0]], "extraction": [[0.0, -420.0]]}
## Where the host's player stands; the wall, the ramp and the slab for the landing checks.
const HOME := Vector3(0, 0, 250)
const WALL_AT := Vector3(170, 0, 250)
const RAMP_AT := Vector3(-230, 0, 200)
const SLAB_AT := Vector3(-330, 0, -330)
const GENTLE_AT := Vector3(-420, 0, 40)
const PACE := 2.0
const START_M := 450.0
const FLY_S := 90.0

var failures := 0
var main: Node
var level: ZoneLevel
var player: Soldier
var sup: HeliSupports
var layer: VehicleLayer
var mates: Array[Soldier] = []
var _client_left := false
var _host_digest := {}
var _saw_client_call := false
var _structures: Node3D


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_supports" + tag  # never touch a real save
	Campaign.campaign_id = "test_supports_campaign" + tag
	CompoundLevel.spawn_ai = false
	PeopleLayer.contract_people = false
	Contracts.auto_show_debrief = false
	Vehicle.fire_rolls = false  # no chance fires: only what the tests start
	Vehicle.local_input = false
	Helicopter.pace = PACE
	HeliSupports.start_m = START_M
	HeliSupports.free_calls = 1
	HeliCall.board_direct_s = 6.0
	var args := OS.get_cmdline_user_args()
	if "--supports-join" in args:
		Contracts.autosave = false
		var i := args.find("--supports-join")
		await _run_client(args[i + 1] if i + 1 < args.size() else "127.0.0.1")
	else:
		GameState.delete_save()
		Campaign.reset_campaign()
		await _run_host("--supports-host" in args)


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


func _finish() -> void:
	if Net.is_hosting() or multiplayer.is_server():
		GameState.delete_save()
	print("SUPPORTS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	Net.leave()
	get_tree().quit(failures)


## While iterating: CONTRACTOR_SUPPORTS_ONLY="landing,grid" runs only those host checks.
static func _want(part: String) -> bool:
	var only := OS.get_environment("CONTRACTOR_SUPPORTS_ONLY")
	if only == "":
		return true
	for p in only.split(","):
		if part.begins_with(p):
			return true
	return false


# --- Helpers --------------------------------------------------------------------------------------

func _ground(at: Vector3) -> Vector3:
	return level.ground_point(Vector3(at.x, 0.0, at.z))


## The host's player calls a support (the path Soldier._server_squad_command takes).
func _call(cmd: String, point := Vector3.INF) -> String:
	var p := point if point != Vector3.INF else player.global_position
	return Supports.server_command(player, cmd, p, PackedStringArray())


## The host's player puts a point marker on the map at (x, z).
func _marker(at: Vector2) -> int:
	return MapNodes.markers(level).server_add({"kind": "point", "points": PackedVector2Array([at]), "text": "LZ", "colour": "black",
		"channel": "field", "author": 1})


## The last round's smoke goes (it would still be out for half a minute).
func _clear_smoke() -> void:
	for cloud in SmokeCloud.active.duplicate():
		if is_instance_valid(cloud):
			cloud.queue_free()
	await get_tree().process_frame


func _smoke(at: Vector3, colour: String) -> void:
	level.spawn_smoke.rpc(_ground(at), colour)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _helicopters() -> Array[Helicopter]:
	var out: Array[Helicopter] = []
	for v in layer.vehicles():
		if v is Helicopter:
			out.append(v as Helicopter)
	return out


func _landed(c: HeliCall) -> bool:
	return c != null and is_instance_valid(c.heli) and c.heli.is_landed()


func _aboard(s: Soldier, c: HeliCall) -> bool:
	return c != null and is_instance_valid(c.heli) and is_instance_valid(s) and Vehicle.ride_of(s) == c.heli


func _mate(callsign: String, slot: int, at: Vector3) -> Soldier:
	return level.spawn_soldier({"name": callsign, "faction": "friendly", "variant": "multicam", "pos": _ground(at), "loadout": ["m4a1"],
		"role": "rifleman", "team": 0, "slot": slot, "combat": 0.5, "discipline": 0.6, "guard": false})


## The person (civilian or HVT) called `node_name`, or null.
func _person_named(node_name: String) -> Soldier:
	for s in level.people.people():
		if is_instance_valid(s) and not s.is_queued_for_deletion() and String(s.name) == node_name:
			return s
	return null


## Everyone aboard `c` but the player and the squadmates is taken out and freed (a test-only
## dismiss drops occupants from the air, and only the squad is regrouped after).
func _clear_passengers(c: HeliCall) -> void:
	if c == null or not is_instance_valid(c.heli):
		return
	for s: Soldier in c.heli.occupants():
		if s != player and s not in mates:
			c.heli.server_exit(s)
			s.queue_free()


## One line on a squadmate, for a check that fails: up, down or dead; what it rides; how far
## from the helicopter; what its AI is doing (and for whom).
func _mate_state(m: Soldier, heli: Node3D) -> String:
	if not is_instance_valid(m):
		return "gone"
	var v := m.vitals
	var life := "dead" if v.is_dead() else ("down" if v.downed else ("up" if v.is_up() else "not up"))
	var ride := Vehicle.ride_of(m)
	var far := _flat(m.global_position, heli.global_position) if is_instance_valid(heli) else -1.0
	var ai := SquadAI.of(m)
	var doing := "no AI"
	if ai:
		doing = "%s, intent %s" % [ai.status_text(), SquadAI.Intent.keys()[ai.intent]]
		if is_instance_valid(ai.casualty):
			doing += ", casualty %s at %.0f m" % [ai.casualty.name, _flat(ai.casualty.global_position, m.global_position)]
	return "%s: %s, riding %s, %.0f m from the helicopter, %s" % [m.name, life, ride.name if ride else "nothing", far, doing]


func _mates_state(heli: Node3D) -> String:
	return "; ".join(mates.map(func(m: Soldier) -> String: return _mate_state(m, heli)))


## The player and the living squadmates back by HOME.
func _regroup() -> void:
	player.global_position = _ground(HOME)
	var i := 0
	for m in mates:
		if is_instance_valid(m) and not m.vitals.is_dead() and Vehicle.ride_of(m) == null:
			m.global_position = _ground(HOME + Vector3(-4.0 + 8.0 * i, 0, 6))
			m.velocity = Vector3.ZERO
		i += 1


func _wall(centre: Vector3, size: Vector3, rot_x_deg := 0.0, ground := false) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	if ground:
		level.add_child(body)  # a direct child of the level counts as the ground (LandingZone.is_ground)
	else:
		_structures.add_child(body)  # under a node of its own: a structure
	body.global_transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(rot_x_deg)), centre)
	return body


# --- Host -------------------------------------------------------------------------------------------

## Hosts the suite's zone: a ZoneLevel with weather the test sets (tests/supports_zone.gd), in
## place of main's compound, as LevelSwitch.load_level does.
func _host_zone() -> ZoneLevel:
	var current: CompoundLevel = null
	for child in main.get_children():
		if child is CompoundLevel and child.is_in_group(&"level"):
			current = child
	var lvl := (load(LevelSwitch.scene_for({"level": "zone"})) as PackedScene).instantiate()
	lvl.set_script(load("res://tests/supports_zone.gd"))
	(lvl as ZoneLevel).configure(DEF)
	var index := 0
	if current:
		index = current.get_index()
		LevelSwitch._retire(current)
	main.add_child(lvl)
	main.move_child(lvl, index)
	return lvl as ZoneLevel


func _run_host(wait_for_client: bool) -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	level = _host_zone()
	main.menu.host()
	check(level != null and Net.is_hosting() and Supports.is_hot_zone(level), "hosting the suite's hot zone on port %d" % Net.port())
	if level == null or not Net.is_hosting():
		_finish()
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 10.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # the tests move it
	player.inventory.take(&"m4a1")
	sup = HeliSupports.of(level)
	layer = VehicleLayer.of(level)
	_structures = Node3D.new()
	_structures.name = "TestStructures"
	level.add_child(_structures)
	VehicleHull.prewarm(HeliSupports.MODEL)
	await _wait_for(func() -> bool: return VehicleHull.is_ready(HeliSupports.MODEL), 20.0)
	mates = [_mate("Alpha", 1, HOME + Vector3(-4, 0, 6)), _mate("Bravo", 2, HOME + Vector3(4, 0, 6))]
	_regroup()
	await _seconds(0.5)
	_test_data()
	if _want("landing"):
		await _test_landing_zone()
	if _want("refusals"):
		_test_refusals()
	if _want("payment"):
		_test_payment()
	if _want("grid"):
		await _test_grid_calls()
	if _want("smoke"):
		await _test_smoke_calls()
	if _want("green"):
		await _test_first_takes_green()
	if _want("extraction"):
		await _test_extraction()
	if _want("extraction"):
		await _test_extraction_home()
	if _want("insertion"):
		await _test_insertion()
	if _want("shot_down"):
		await _test_shot_down()
	if not wait_for_client:
		_finish()
		return
	await _stage_for_client()
	print("[host] waiting for the client")
	Net.peer_left.connect(func(_id: int) -> void: _client_left = true)
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = false
	await _wait_for(func() -> bool:
		if sup.active("resupply") != null:
			_saw_client_call = true
		return _client_left, 400.0)
	check(_client_left, "the client finished and left")
	check(_saw_client_call, "the client's resupply call came to the host and flew")
	_finish()


func _test_data() -> void:
	print("Data, the menu and the briefing")
	check(Helicopter.flies("uh60") and not Helicopter.flies("matv"), "the UH-60 is flown as a Helicopter, an M-ATV isn't")
	check(KindsRegistered.all(), "resupply, transport and extraction are registered with Supports")
	check(HeliSupports.smoke_colours("resupply") == ["green", "yellow"] and HeliSupports.smoke_colours("transport") == ["green", "blue"]
		and HeliSupports.smoke_colours("extraction") == ["purple"], "smoke colours: resupply green or yellow, transport green or blue, extraction purple (Captain)")
	var support: Dictionary = (CommandMenu.MENU.items as Array).filter(func(e: Dictionary) -> bool: return e.key == "0")[0]
	var cmds := []
	for entry: Dictionary in support.items:
		for sub: Dictionary in entry.get("items", []):
			cmds.append(String(sub.get("cmd", "")))
	check("support:resupply:marker" in cmds and "support:transport:smoke" in cmds and "support:transport:dest" in cmds and "support:extraction:here" in cmds
		and "support:aav_call" in cmds, "the Support menu has the helicopter calls (marker, there, smoke, destination, home) beside the AAV's")
	var hot := Briefing.with_heli_insertion({"kind": "hot", "insertion_points": [{"id": "a", "name": "A", "pos": [0.0, 0.0], "method": "foot"}]})
	var cold := Briefing.with_heli_insertion({"kind": "contract", "insertion_points": [{"id": "a", "name": "A", "pos": [0.0, 0.0], "method": "foot"}]})
	check((hot.insertion_points as Array).size() == 2 and hot.insertion_points[1].method == Briefing.HELI and (cold.insertion_points as Array).size() == 1,
		"a hot zone's briefing offers each insertion point by helicopter too; a contract zone's doesn't")
	var load := HeliCall.new(sup, "resupply", player, {}).resupply_load()
	var ids := load.map(func(e: Array) -> String: return String(e[0]))
	check("mag_556" in ids and "rounds_556" in ids and "ifak" in ids and "frag_grenade" in ids and "smoke_green" in ids,
		"the pallet's load: the squad's magazines and rounds, medical, grenades, smoke (%s)" % [ids])


class KindsRegistered:
	static func all() -> bool:
		for kind: String in HeliSupports.KINDS:
			if not Supports._handlers.has(kind):
				return false
		return true


func _test_landing_zone() -> void:
	print("Landing safety")
	var open := LandingZone.check(level, _ground(HOME + Vector3(0, 0, -70)))
	check(open.ok, "open, level ground takes a landing (%s, %.1f°)" % [open.why, open.slope_deg])
	_wall(_ground(WALL_AT) + Vector3(0, 2.0, 0), Vector3(14, 4, 0.6))
	await get_tree().physics_frame
	var by_wall := _ground(WALL_AT + Vector3(0, 0, 4))
	var c := LandingZone.check(level, by_wall)
	check(not c.ok, "4 m from a wall: no landing (%s)" % c.why)
	var f := LandingZone.find(level, by_wall)
	check(f.ok and float(f.moved_m) >= 5.0 and float(f.moved_m) <= 100.0 and LandingZone.check(level, f.spot).ok,
		"the nearest safe spot is %.0f m off, within 100 m" % float(f.moved_m))
	var ramp_top := _ground(RAMP_AT) + Vector3.UP * (17.0 * sin(deg_to_rad(22.0)))  # its low edge at the ground
	_wall(ramp_top, Vector3(34, 2, 34), 22.0, true)
	await get_tree().physics_frame
	var steep := LandingZone.check(level, RAMP_AT)
	check(not steep.ok and String(steep.why).contains("steep"), "a 22° slope is too steep (%s)" % steep.why)
	var off_ramp := LandingZone.find(level, RAMP_AT)
	check(off_ramp.ok and float(off_ramp.moved_m) <= 100.0 and float(off_ramp.moved_m) >= 15.0,
		"off the slope: landing %.0f m away" % float(off_ramp.moved_m))
	var gentle_top := _ground(GENTLE_AT) + Vector3.UP * (17.0 * sin(deg_to_rad(12.0)))
	var gentle := _wall(gentle_top, Vector3(34, 2, 34), 12.0, true)
	await get_tree().physics_frame
	var on_gentle := LandingZone.check(level, GENTLE_AT)
	check(on_gentle.ok and float(on_gentle.slope_deg) > 9.0, "a 12° slope takes a landing: Captain's limit is 15° (%s, %.1f°)" % [on_gentle.why, float(on_gentle.slope_deg)])
	gentle.queue_free()
	var truck_at := _ground(HOME + Vector3(-120, 0, -150))
	var truck := layer.server_spawn("matv", Transform3D(Basis(), truck_at), "", &"player", "test_truck")
	await _seconds(0.5)
	var by_truck := LandingZone.check(level, truck_at + Vector3(3, 0, 0))
	check(not by_truck.ok, "beside a parked M-ATV: no (%s)" % by_truck.why)
	if truck:
		truck.queue_free()
	var person_at := _ground(HOME + Vector3(80, 0, -150))
	var bravo := mates[1]
	bravo.global_position = person_at + Vector3(1.5, 0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var by_person := LandingZone.check(level, person_at)
	check(not by_person.ok and String(by_person.why).contains("people"), "someone standing there: no (%s)" % by_person.why)
	_regroup()
	_wall(_ground(SLAB_AT) + Vector3(0, 0.6, 0), Vector3(240, 1.2, 240))
	await get_tree().physics_frame
	var nowhere := LandingZone.find(level, _ground(SLAB_AT))
	check(not nowhere.ok, "in the middle of a 240 m built-up slab there's nowhere within 100 m (%s)" % nowhere.why)


func _test_refusals() -> void:
	print("Refusals")
	var before := _helicopters().size()
	level.def["kind"] = "contract"
	HeliSupports.free_calls = 0  # not a dev session (dev sessions fly transport anywhere)
	var why := _call("support:transport:here", _ground(HOME + Vector3(0, 0, -60)))
	check(why.contains("hot zones only"), "transport outside a hot zone: refused (%s)" % why)
	HeliSupports.free_calls = 1
	level.def["kind"] = "hot"
	(level as Object).set(&"storm", true)
	why = _call("support:resupply:here", _ground(HOME + Vector3(0, 0, -60)))
	check(not Supports.can_fly(level) and why.contains("grounded"), "a storm (Supports.can_fly false): refused (%s)" % why)
	(level as Object).set(&"storm", false)
	why = _call("support:resupply:marker")
	check(why.contains("marker"), "at my marker with no marker: refused (%s)" % why)
	why = _call("support:resupply:grid:12x4")
	check(why.contains("grid reference"), "a bad grid reference: refused (%s)" % why)
	why = _call("support:transport:dest")
	check(why.contains("transport first"), "a destination with no transport out: refused (%s)" % why)
	HeliSupports.free_calls = 0
	why = _call("support:extraction:here", _ground(HOME + Vector3(0, 0, -60)))
	check(why.contains("No deployment"), "extraction with no deployment to end: refused (%s)" % why)
	HeliSupports.free_calls = 1
	check(_helicopters().size() == before and sup.calls.is_empty(), "no helicopter went up for any of them")


func _test_payment() -> void:
	print("Paying for supports")
	Contracts.autosave = false
	Contracts.new_full_campaign(77, 20000)
	var cid := String(Contracts.board()[0].cid)
	var terms := ContractGen.default_terms()
	terms.support_points = 2
	check(Contracts.server_accept(cid, terms) == "", "a contract with a support budget accepted")
	var budget := int(Contracts.contract(cid).get("support_left", 0))
	check(Contracts.server_start_deployment([cid]) == "" and Contracts.is_deployed(), "deployed on it (support budget $%d)" % budget)
	HeliSupports.free_calls = -1  # the default: paid in a deployment, dev tools or not
	var cash := Economy.cash()
	var price := Economy.support_price("resupply")
	var why := _call("support:resupply:here", _ground(HOME + Vector3(0, 0, -70)))
	var from_budget := mini(budget, price)
	check(why == "" and int(Contracts.contract(cid).get("support_left", 0)) == budget - from_budget and Economy.cash() == cash - (price - from_budget),
		"a $%d resupply: $%d from the support budget, $%d from cash (%s)" % [price, from_budget, price - from_budget, why])
	sup.server_dismiss_all()
	cash = Economy.cash()
	why = _call("support:resupply:here", _ground(HOME + Vector3(0, 0, -70)))
	check(why.contains("available again") and Economy.cash() == cash and sup.calls.is_empty(), "called again at once: its cooldown refuses it, nothing paid (%s)" % why)
	sup.server_reset_limits()
	cash = Economy.cash()
	budget = int(Contracts.contract(cid).get("support_left", 0))
	HeliSupports.launch_fails = true
	why = _call("support:resupply:here", _ground(HOME + Vector3(0, 0, -70)))
	HeliSupports.launch_fails = false
	check(why.contains("could take off") and Economy.cash() == cash and int(Contracts.contract(cid).get("support_left", 0)) == budget and sup.calls.is_empty(),
		"no helicopter could take off: the budget and cash are given back (%s)" % why)
	sup.server_reset_limits()
	Contracts.server_draw_support(cid, 1000000)
	Economy.spend(Economy.cash() - 100, "test: broke")
	why = _call("support:transport:here", _ground(HOME + Vector3(0, 0, -70)))
	check(why.contains("Can't pay") and Economy.cash() == 100 and sup.calls.is_empty(), "with $100 and no budget left: refused, nothing flies (%s)" % why)
	Contracts.server_end_deployment({})
	Contracts.server_finish_debrief()
	sup.server_reset_limits()
	HeliSupports.free_calls = 1


func _test_grid_calls() -> void:
	print("Called by grid: resupply at a marker by a wall, transport there")
	_regroup()
	var mark := Vector2(WALL_AT.x, WALL_AT.z + 4.0)
	_marker(mark)
	var why := _call("support:resupply:marker")
	var r := sup.active("resupply")
	check(why == "" and r != null and is_instance_valid(r.heli) and r.heli.is_flying(), "resupply at my map marker: a UH-60 is on its way (%s)" % why)
	var pickup := _ground(HOME + Vector3(30, 0, -20))
	why = _call("support:transport:here", pickup)
	var t := sup.active("transport")
	check(why == "" and t != null, "transport, pick up there: on its way too (%s)" % why)
	if r == null or t == null:
		return
	check(sup.heard_line("Inbound to grid") and sup.heard_line("No LZ at the mark"), "the radio: inbound to the grid, landing off the mark")
	await _wait_for(func() -> bool: return _landed(r), FLY_S)
	var mark3 := Vector3(mark.x, 0, mark.y)
	check(_landed(r) and r.heli.height_agl() < 0.6, "the resupply landed (agl %.2f m)" % (r.heli.height_agl() if is_instance_valid(r.heli) else -1.0))
	if _landed(r):
		var off := _flat(r.heli.global_position, mark3)
		check(off >= 5.0 and off <= 100.0, "by the wall it landed %.0f m off the marker, within 100 m" % off)
		await _seconds(1.0)
		var near := {}
		for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
			var item := node as WorldItem
			if item and item.global_position.distance_to(r.heli.global_position) < 15.0:
				near[String(item.item_id)] = int(near.get(String(item.item_id), 0)) + item.count
		check(near.has("supply_pallet") and int(near.get("mag_556", 0)) >= 6 and int(near.get("rounds_556", 0)) >= 120 and near.has("ifak")
			and near.has("frag_grenade") and near.has("smoke_grenade"), "a supply pallet with the load beside it (%s)" % [near])
		check(sup.heard_line("Pallet's down"), "the radio: pallet's down")
	await _wait_for(func() -> bool: return r.is_over(), FLY_S)
	check(r.phase == HeliCall.Phase.GONE and not is_instance_valid(r.heli), "then it lifted off and left the map")
	# Transport: pick up the player and the AI, fly them there, put them down.
	await _wait_for(func() -> bool: return _landed(t), FLY_S)
	check(_landed(t) and _flat(t.heli.global_position, pickup) <= 100.0, "the transport landed at the pickup (%.0f m off)" % (_flat(t.heli.global_position, pickup) if is_instance_valid(t.heli) else -1.0))
	if not _landed(t):
		sup.server_dismiss_all()
		return
	check(t.heli.server_enter(player), "the player gets in (a passenger seat)")
	check(not t.heli.server_enter(mates[0], 0), "nobody takes a pilot's seat: the crew is the helicopter's own")
	await _wait_for(func() -> bool: return mates.all(func(m: Soldier) -> bool: return _aboard(m, t)), 40.0)
	check(mates.all(func(m: Soldier) -> bool: return _aboard(m, t)), "the AI squadmates were ordered in and got in")
	var dest := Vector2(-60.0, -120.0)
	_marker(dest)
	why = _call("support:transport:dest")
	check(why == "" and sup.heard_line("taking you to"), "fly to my map marker: the destination (%s)" % why)
	await _wait_for(func() -> bool: return t.phase == HeliCall.Phase.CARRY and t.heli.height_agl() > 15.0, 30.0)
	check(t.phase == HeliCall.Phase.CARRY and t.heli.occupants().size() == 3, "airborne with the player and two AI aboard")
	check(player.global_position.distance_to(t.heli.global_position) < 8.0, "the player rides along in their seat")
	var on_board := player.global_position
	t.heli.server_exit(player)
	check(Vehicle.ride_of(player) == t.heli and player.global_position.distance_to(on_board) < 5.0, "nobody gets out in the air")
	await _wait_for(func() -> bool: return _landed(t) and t.stage == "drop", FLY_S)
	var dest3 := Vector3(dest.x, 0, dest.y)
	check(_landed(t) and _flat(t.heli.global_position, dest3) <= 100.0, "landed at the destination (%.0f m off)" % (_flat(t.heli.global_position, dest3) if is_instance_valid(t.heli) else -1.0))
	await _wait_for(func() -> bool: return mates.all(func(m: Soldier) -> bool: return Vehicle.ride_of(m) == null), 10.0)
	check(mates.all(func(m: Soldier) -> bool: return Vehicle.ride_of(m) == null and _flat(m.global_position, dest3) < 120.0),
		"the AI got out on landing, there")
	check(Vehicle.ride_of(player) == t.heli, "it waits for the player to get out")
	if is_instance_valid(t.heli):
		t.heli.server_exit(player)
	check(Vehicle.ride_of(player) == null and _flat(player.global_position, dest3) < 120.0, "the player gets out at the destination")
	await _wait_for(func() -> bool: return t.is_over(), FLY_S)
	check(t.phase == HeliCall.Phase.GONE, "then the transport left")
	_regroup()


func _test_smoke_calls() -> void:
	print("Called on smoke: each loiters, then lands on its own colour")
	sup.server_reset_limits()
	_regroup()
	check(_call("support:resupply:smoke") == "" and _call("support:transport:smoke") == "" and _call("support:extraction:smoke") == "",
		"resupply, transport and extraction called on smoke")
	var r := sup.active("resupply")
	var t := sup.active("transport")
	var e := sup.active("extraction")
	if r == null or t == null or e == null:
		sup.server_dismiss_all()
		return
	await _wait_for(func() -> bool: return [r, t, e].all(func(c: HeliCall) -> bool: return c.phase == HeliCall.Phase.LOITER), FLY_S)
	check([r, t, e].all(func(c: HeliCall) -> bool: return c.phase == HeliCall.Phase.LOITER and c.heli.is_flying() and c.mark.is_empty()),
		"all three loiter near the players, waiting for smoke")
	check(sup.heard_line("Pop green or yellow smoke") and sup.heard_line("Pop purple smoke"), "the radio asks for their colours")
	var blue := Vector3(160, 0, 120)
	_smoke(blue, "blue")
	await _wait_for(func() -> bool: return t.mark.has("pos"), 20.0)
	check(t.mark.has("pos") and _flat(t.lz, blue) <= 100.0 and sup.heard_line("I see blue. Coming in"), "the transport saw the blue smoke and comes in to it")
	check(r.mark.is_empty() and e.mark.is_empty() and sup.heard_line("I see blue. Not my smoke"), "resupply and extraction ignore blue: not their colour")
	var yellow := Vector3(-160, 0, 120)
	var purple := Vector3(0, 0, 40)
	_smoke(yellow, "yellow")
	_smoke(purple, "purple")
	await _wait_for(func() -> bool: return r.mark.has("pos") and e.mark.has("pos"), 20.0)
	check(r.mark.has("pos") and _flat(r.lz, yellow) <= 100.0, "the resupply comes in to the yellow smoke")
	check(e.mark.has("pos") and _flat(e.lz, purple) <= 100.0, "the extraction comes in to the purple smoke")
	var ext := MapNodes.extraction(level)
	var point := ext.point_by_id(e.point_id) if ext else {}
	check(not point.is_empty() and (point.pos as Vector2).distance_to(Vector2(e.lz.x, e.lz.z)) < 1.0 and point.source == "smoke",
		"the extraction point is where it lands (%s)" % [point])
	check(_called_points(ext) == 1, "one extraction point: the purple smoke's, moved to the LZ (%d)" % _called_points(ext))
	await _wait_for(func() -> bool: return _landed(r) and _landed(t) and _landed(e), FLY_S)
	check(_landed(r) and _flat(r.heli.global_position, yellow) <= 100.0, "resupply landed by the yellow smoke")
	check(_landed(t) and _flat(t.heli.global_position, blue) <= 100.0, "transport landed by the blue smoke")
	check(_landed(e) and _flat(e.heli.global_position, purple) <= 100.0, "extraction landed by the purple smoke")
	check(HeliSupports.readout(level).contains("resupply") and SessionLog.state_text("test").contains("Helicopter supports:"),
		"the state dump lists the supports")
	sup.server_dismiss_all()


func _test_first_takes_green() -> void:
	print("Green smoke: the first call takes it")
	await _clear_smoke()
	sup.server_reset_limits()
	_regroup()
	check(_call("support:resupply:smoke") == "" and _call("support:transport:smoke") == "", "resupply, then transport, on smoke")
	var r := sup.active("resupply")
	var t := sup.active("transport")
	if r == null or t == null:
		sup.server_dismiss_all()
		return
	await _wait_for(func() -> bool: return r.phase == HeliCall.Phase.LOITER and t.phase == HeliCall.Phase.LOITER, FLY_S)
	var first := Vector3(120, 0, 60)
	_smoke(first, "green")
	await _wait_for(func() -> bool: return r.mark.has("pos") or t.mark.has("pos"), 20.0)
	check(r.mark.has("pos") and _flat(r.lz, first) <= 100.0 and t.mark.is_empty(), "the resupply (called first) takes the green smoke; the transport keeps looking")
	var second := Vector3(-120, 0, 60)
	_smoke(second, "green")
	await _wait_for(func() -> bool: return t.mark.has("pos"), 20.0)
	check(t.mark.has("pos") and _flat(t.lz, second) <= 100.0, "a second green smoke: the transport takes that one")
	await _wait_for(func() -> bool: return _landed(r) and _landed(t), FLY_S)
	check(_landed(r) and _landed(t), "both landed on green")
	sup.server_dismiss_all()


func _test_extraction() -> void:
	print("Extraction: the squad, an HVT and deposited items lifted out")
	sup.server_reset_limits()
	_regroup()
	var ext := MapNodes.extraction(level)
	ext.server_begin({})
	var lzp := _ground(HOME + Vector3(0, 0, -45))
	var hvt := level.people.server_spawn_person({"name": "HvtTest", "kind": "hvt", "side": "friendly", "pos": _ground(lzp + Vector3(12, 0, 4)),
		"label": "HVT (test)", "hvt_id": "hvt_test"})
	level.server_spawn_dropped(&"intel_laptop", 1, _ground(lzp + Vector3(7, 0, 9)) + Vector3.UP * 0.4)
	level.server_spawn_dropped(&"electronics_salvage", 1, _ground(lzp + Vector3(-7, 0, 9)) + Vector3.UP * 0.4)
	var why := _call("support:extraction:here", lzp)
	var e := sup.active("extraction")
	check(why == "" and e != null and ext.points.any(func(p: Dictionary) -> bool: return p.source == "grid" and (p.pos as Vector2).distance_to(Vector2(lzp.x, lzp.z)) < 100.0),
		"extraction there: an extraction point at the spot (%s)" % why)
	if e == null:
		return
	await _wait_for(func() -> bool: return _landed(e), FLY_S)
	check(_landed(e) and _flat(e.heli.global_position, lzp) <= 100.0, "landed at the extraction point")
	if not _landed(e):
		sup.server_dismiss_all()
		return
	check(_called_points(ext) == 1 and not ext.point_by_id(e.point_id).is_empty(), "one extraction point, the helicopter's, after the LZ recheck (%d)" % _called_points(ext))
	await _wait_for(func() -> bool:
		var hold := e.heli.cargo_hold.entries().map(func(x: Dictionary) -> String: return String(x.id))
		return "intel_laptop" in hold and "electronics_salvage" in hold and _aboard(hvt, e), 15.0)
	var hold_ids := e.heli.cargo_hold.entries().map(func(x: Dictionary) -> String: return String(x.id))
	check("intel_laptop" in hold_ids and "electronics_salvage" in hold_ids, "the items set down in the point are loaded aboard (%s)" % [hold_ids])
	check(_aboard(hvt, e), "the friendly HVT boards")
	var ended := [false]
	ext.deployment_ended.connect(func(_r: Dictionary) -> void: ended[0] = true, CONNECT_ONE_SHOT)
	await _seconds(1.0)
	check(not ended[0] and ext.state == Extraction.State.ACTIVE, "it waits for the squad")
	e.heli.server_enter(player)
	await _wait_for(func() -> bool: return ended[0], 40.0)
	check(ended[0] and ext.state == Extraction.State.ENDED, "everyone aboard: lifting off ends the deployment")
	var report := ext.last_report
	var squad_names: Array = (report.get("squad", []) as Array).map(func(s: Dictionary) -> String: return String(s.name))
	var deposited: Array = (report.get("deposited", []) as Array).map(func(d: Dictionary) -> String: return String(d.id))
	check((report.get("players", []) as Array).size() == 1 and "Alpha" in squad_names and "Bravo" in squad_names and (report.get("left_behind", []) as Array).is_empty(),
		"the report: the player and both AI out, nobody left (%s)" % [squad_names])
	check((report.get("hvts", []) as Array).any(func(h: Dictionary) -> bool: return String(h.get("hvt", "")) == "hvt_test"), "the report: the HVT out")
	check("intel_laptop" in deposited and "electronics_salvage" in deposited, "the report: the deposited items lifted (%s)" % [deposited])
	# No campaign to go home to here: it puts them back down and leaves.
	await _wait_for(func() -> bool: return _landed(e) and e.stage == "drop" and mates.all(func(m: Soldier) -> bool: return Vehicle.ride_of(m) == null), FLY_S)
	check(e.stage == "drop" and mates.all(func(m: Soldier) -> bool: return Vehicle.ride_of(m) == null), "with no campaign to switch to, it lands them back")
	if is_instance_valid(e.heli):
		e.heli.server_exit(player)
		e.heli.server_exit(hvt)
	await _wait_for(func() -> bool: return e.is_over(), FLY_S)
	check(e.phase == HeliCall.Phase.GONE, "then it left")
	# The test HVT goes now. Left in the level, the next extraction loaded it (HVT_REACH_M)
	# and the dismiss dropped it from the air; when it lived through the fall, wounded, a mate
	# went to treat it and missed the shot-down transport ("two AI aboard", CI flake).
	if is_instance_valid(hvt):
		hvt.queue_free()
	await get_tree().process_frame
	check(not is_instance_valid(hvt) and _person_named("HvtTest") == null, "the test HVT is cleared")
	_regroup()


## Extraction points that aren't the zone's presets.
func _called_points(ext: Extraction) -> int:
	return ext.points.filter(func(p: Dictionary) -> bool: return p.source != "zone").size() if ext else -1


## Stands in for BaseHub with a campaign running (the extraction helicopter flies the squad
## home rather than putting them back down).
class FakeHub extends Node:
	var campaign_running := true

	func end_deployment(_report: Dictionary) -> void:
		pass


func _test_extraction_home() -> void:
	print("Extraction in a campaign: it flies them home; items left in the point stay out of the report")
	await _clear_smoke()
	sup.server_reset_limits()
	_regroup()
	var hub := FakeHub.new()
	hub.add_to_group(Extraction.END_GROUP)
	add_child(hub)
	var ext := MapNodes.extraction(level)
	ext.server_begin({})
	var lzp := _ground(HOME + Vector3(0, 0, -45))
	check(_call("support:extraction:here", lzp) == "", "extraction called (with a campaign running)")
	var e := sup.active("extraction")
	await _wait_for(func() -> bool: return _landed(e), FLY_S)
	if not _landed(e):
		check(false, "landed for the campaign extraction")
		sup.server_dismiss_all()
		hub.queue_free()
		return
	for s: Soldier in [player] + mates:
		e.heli.server_enter(s)
	await _wait_for(func() -> bool: return e.phase == HeliCall.Phase.LIFTING, 15.0)
	level.server_spawn_dropped(&"intel_documents", 1, _ground(e.lz + Vector3(6, 0, 6)) + Vector3.UP * 0.4)
	check(e.phase == HeliCall.Phase.LIFTING, "lifting, and an item dropped in the point too late to load")
	sup.heard.clear()
	await _wait_for(func() -> bool: return e.phase == HeliCall.Phase.ENDED, 15.0)
	var deposited: Array = (ext.last_report.get("deposited", []) as Array).map(func(d: Dictionary) -> String: return String(d.id))
	check(e.rode_out and e.going_home and "intel_documents" not in deposited,
		"the deployment ended; the item left on the ground isn't in the report (%s)" % [deposited])
	await _seconds(HeliCall.DEV_DROP_S + 3.0)
	check(e.phase == HeliCall.Phase.ENDED and is_instance_valid(e.heli) and e.heli.is_flying() and not sup.heard_line("putting you back down")
		and _aboard(player, e), "with a campaign running it stays up with the squad aboard, waiting for the base")
	_clear_passengers(e)
	sup.server_dismiss_all()
	hub.queue_free()
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if (node as WorldItem).item_id == &"intel_documents":
			node.queue_free()
	_regroup()


func _test_insertion() -> void:
	print("Helicopter insertion (hot zone briefing)")
	sup.server_reset_limits()
	_regroup()
	var briefing := MapNodes.briefing(level)
	var at := Vector2(-200.0, -100.0)
	var zone := {"id": "supports_test", "name": "Test", "kind": "hot",
		"insertion_points": [{"id": "west", "name": "West", "pos": [at.x, at.y], "method": "foot"}]}
	briefing.server_open({"id": "test_c", "title": "Test", "reinforcements": {"first_wave_s": 3600.0}}, zone)
	check(briefing.insertion_points().size() == 2 and briefing.server_set_insertion("west_heli"), "the briefing offers West by helicopter, and it's picked")
	check(briefing.server_start(true), "the deployment starts")
	var c := sup.active("insertion")
	check(c != null and _aboard(player, c) and mates.all(func(m: Soldier) -> bool: return _aboard(m, c)) and c.heli.is_flying(),
		"the squad starts aboard a UH-60 in the air")
	if c == null:
		return
	await _wait_for(func() -> bool: return _landed(c), FLY_S)
	var at3 := Vector3(at.x, 0, at.y)
	check(_landed(c) and _flat(c.heli.global_position, at3) <= 100.0, "it lands at the insertion point (%.0f m off)" % (_flat(c.heli.global_position, at3) if is_instance_valid(c.heli) else -1.0))
	await _wait_for(func() -> bool: return mates.all(func(m: Soldier) -> bool: return Vehicle.ride_of(m) == null), 10.0)
	check(mates.all(func(m: Soldier) -> bool: return Vehicle.ride_of(m) == null and _flat(m.global_position, at3) < 120.0), "the AI get out there")
	if is_instance_valid(c.heli):
		c.heli.server_exit(player)
	check(_flat(player.global_position, at3) < 120.0, "the player gets out there")
	await _wait_for(func() -> bool: return c.is_over(), FLY_S)
	check(c.phase == HeliCall.Phase.GONE, "then it left")
	_regroup()


func _test_shot_down() -> void:
	print("Shot down with passengers and cargo aboard")
	sup.server_reset_limits()
	_regroup()
	check(mates.all(func(m: Soldier) -> bool: return is_instance_valid(m) and m.vitals.is_up() and Vehicle.ride_of(m) == null
		and _flat(m.global_position, HOME) <= 15.0), "both AI up, on foot and by HOME before the transport (%s)" % _mates_state(null))
	var pickup := _ground(HOME + Vector3(0, 0, -35))
	check(_call("support:transport:here", pickup) == "", "a transport called")
	var t := sup.active("transport")
	if t == null:
		return
	await _wait_for(func() -> bool: return _landed(t), FLY_S)
	check(_landed(t), "the transport lands at the pickup")
	await _wait_for(func() -> bool: return mates.all(func(m: Soldier) -> bool: return _aboard(m, t)), 40.0)
	check(mates.all(func(m: Soldier) -> bool: return _aboard(m, t)), "two AI aboard (%s)" % _mates_state(t.heli if t else null))
	t.heli.cargo_hold.take(&"frag_grenade", 3)
	player.global_position = _ground(HOME + Vector3(0, 0, 100))  # stays behind: it goes once everyone near is in
	_marker(Vector2(-300.0, -200.0))
	check(_call("support:transport:dest") == "", "off to a destination")
	await _wait_for(func() -> bool: return t.phase == HeliCall.Phase.CARRY and t.heli.height_agl() > 25.0, 40.0)
	var h := t.heli
	if not is_instance_valid(h) or h.height_agl() < 20.0:
		check(false, "airborne for the shooting")
		sup.server_dismiss_all()
		return
	var side := h.global_basis.x
	var boom := Vector3(1.2, 1.95, 3.0)  # the tail boom's side
	var small := h.server_take_hit({"kind": Vehicle.KINETIC, "round": "556_m855", "energy_j": 1700.0, "position": h.to_global(boom),
		"direction": -side, "probe_m": 1.5, "shooter": null})
	check(not bool(small.penetrated) and not bool(small.missed), "5.56 glances off it (zone %s)" % small.zone)
	var hull_before := h.zone_health(Vehicle.ZONE_HULL)
	var full := h.server_take_hit({"kind": Vehicle.KINETIC, "round": "762x54r_lps", "energy_j": 3600.0, "position": h.to_global(boom),
		"direction": -side, "probe_m": 1.5, "shooter": null})
	check(bool(full.penetrated) and h.zone_health(Vehicle.ZONE_HULL) < hull_before, "7.62x54R goes through (Captain), zone %s" % full.zone)
	for i in 4:
		if h.is_down():
			break
		h.server_take_hit({"kind": Vehicle.HEAT, "penetration_mm": 400.0, "blast_kg": 0.5, "position": h.to_global(Vector3(0.0, 4.6, -2.75)),
			"direction": -h.global_basis.y, "probe_m": 3.0, "shooter": null})
	check(h.is_down() and h.zone_health(Vehicle.ZONE_ROTOR) <= 0.0, "a rocket kills the rotor: it goes down")
	await _wait_for(func() -> bool: return h.flight_mode() == Helicopter.Mode.CRASHED, 40.0)
	check(h.flight_mode() == Helicopter.Mode.CRASHED and h.is_burning() and h.height_agl() < 3.0, "it crashes and burns")
	check(mates.all(func(m: Soldier) -> bool: return m.vitals.is_dead()) and h.cargo_hold.entries().is_empty(),
		"everyone aboard is dead and the cargo lost (Captain) (%s)" % _mates_state(h))
	check(sup.is_lost("transport") and sup.heard_line("Mayday"), "the transport is lost: mayday")
	var why := _call("support:transport:here", _ground(HOME + Vector3(0, 0, -60)))
	check(why.contains("lost"), "and gone for the rest of the op (%s)" % why)
	sup.server_reset_limits()


# --- The client's part (host side) -------------------------------------------------------------

func _stage_for_client() -> void:
	await _clear_smoke()
	sup.server_reset_limits()
	_regroup()
	MapNodes.extraction(level).server_begin({})
	_call("support:extraction:smoke")
	var e := sup.active("extraction")
	await _wait_for(func() -> bool: return e != null and is_instance_valid(e.heli) and e.heli.height_agl() > 30.0 and e.heli.is_flying(), 30.0)
	check(e != null and is_instance_valid(e.heli) and e.heli.is_flying(), "a helicopter in the air for the late joiner")
	sup.server_reset_limits()


## Client asks: what helicopters does the host have?
@rpc("any_peer", "reliable")
func _ask_digest() -> void:
	_reply_digest.rpc_id(multiplayer.get_remote_sender_id(), _digest())


@rpc("authority", "reliable")
func _reply_digest(digest: Dictionary) -> void:
	_host_digest = digest


func _digest() -> Dictionary:
	var out := {}
	for h in _helicopters():
		out[h.vehicle_id] = {"pos": h.global_position, "mode": int(h.flight_mode()), "call": h.support}
	return out


# --- Client -------------------------------------------------------------------------------------------

func _run_client(address: String) -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var joined := [false]
	Net.joined.connect(func() -> void: joined[0] = true)
	var deadline := Time.get_ticks_msec() + 420000
	while not joined[0] and Time.get_ticks_msec() < deadline:
		var peer := multiplayer.multiplayer_peer
		if not (peer is ENetMultiplayerPeer) or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			Net.join(address)
		await get_tree().create_timer(2.0).timeout
	print("Client joining the supports zone late")
	check(joined[0], "joined the host's session")
	level = CompoundLevel.current(self) as ZoneLevel
	check(level != null and Supports.is_hot_zone(level), "the host's hot zone replaced the compound on joining")
	if level == null:
		_finish()
		return
	layer = VehicleLayer.of(level)
	sup = HeliSupports.of(level)
	var me_id := str(multiplayer.get_unique_id())
	await _wait_for(func() -> bool: return level.players.get_node_or_null(me_id) != null, 20.0)
	player = level.players.get_node_or_null(me_id)
	if player:
		player.set_physics_process(false)
	await _wait_for(func() -> bool: return not _helicopters().is_empty(), 20.0)
	await _seconds(1.0)
	_ask_digest.rpc_id(1)
	await _wait_for(func() -> bool: return not _host_digest.is_empty(), 10.0)
	var flying: Helicopter = null
	for h in _helicopters():
		if h.is_flying():
			flying = h
	check(flying != null, "the late joiner sees a helicopter in flight (%d here)" % _helicopters().size())
	if flying:
		var host_h: Dictionary = _host_digest.get(flying.vehicle_id, {})
		var gap := flying.global_position.distance_to(host_h.get("pos", Vector3.INF)) if not host_h.is_empty() else INF
		check(gap < 60.0 and flying.height_agl() > 20.0 and float(flying.net_flight.get("rpm", 0.0)) > 200.0,
			"where the host has it (%.0f m apart), high up, rotors turning" % gap)
		var start := flying.global_position
		await _seconds(2.0)
		check(is_instance_valid(flying) and flying.global_position.distance_to(start) > 20.0, "and moving smoothly on the client")
	if player == null:
		_finish()
		return
	var spot := level.ground_point(player.global_position + Vector3(45, 0, -30))
	player._server_squad_command.rpc_id(1, "support:resupply:here", spot, PackedStringArray())
	var mine: Array = [null]
	await _wait_for(func() -> bool:
		for h in _helicopters():
			if String(h.net_flight.get("call", "")) == "resupply":
				mine[0] = h
		return mine[0] != null, 20.0)
	var heli := mine[0] as Helicopter
	check(heli != null, "the client called a resupply: its helicopter appears")
	if heli == null:
		_finish()
		return
	var first := heli.global_position
	await _wait_for(func() -> bool: return not is_instance_valid(mine[0]) or (mine[0] as Helicopter).is_landed(), FLY_S)
	check(is_instance_valid(heli) and heli.is_landed() and heli.global_position.distance_to(first) > 100.0, "it flew in and landed (seen on the client)")
	if is_instance_valid(heli):
		check(_flat(heli.global_position, spot) <= 100.0 and heli.height_agl() < 1.0, "at the spot the client picked (%.0f m off)" % _flat(heli.global_position, spot))
	await _wait_for(func() -> bool: return sup.heard_line("Pallet's down"), 10.0)
	check(sup.heard_line("Mule 1-1: Inbound") and sup.heard_line("Pallet's down"), "the client heard the radio: inbound, pallet's down")
	await _wait_for(func() -> bool: return not is_instance_valid(mine[0]) or (mine[0] as Node).is_queued_for_deletion(), FLY_S)  # (an Array: a freed capture is an error)
	check(not is_instance_valid(mine[0]), "and it left: gone on the client too")
	_finish()
