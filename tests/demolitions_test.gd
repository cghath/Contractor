extends Node
## The player's demolitions (Demolitions; Captain's list 2026-10-20: mines and claymores, demo
## blocks, det cord, thermite, chem lights). On the vehicle range, the host's player:
## - the items are data: their kinds, arming modes, prices (Proposed) and the shop and loadout;
## - places a demo block on a wall (a fuel store's side), not a mine (it wants flat ground), not on himself;
## - arms one on a timer on a sabotage target: it goes off and the objective is done;
## - corded blocks go as one: a clacker out of its wire's reach fires nothing, in reach the whole
##   chain; somebody else's block stays;
## - a block set on an MRAP takes a big share of its hull;
## - thermite on a technical lights, burns (a light on every peer), and burns its engine out and
##   sets it on fire;
## - a claymore's fragments hit the target dummy in front, not those behind or beside it;
## - a tripwire claymore and a pressure mine wait until they're live, then a hostile walking in
##   sets them off (the mine wrecks his leg); a vehicle over a mine sets it off; our mines are on
##   the map and in hazards();
## - a placed item can be picked up again from close by;
## - chem lights: thrown, one comes to rest and glows; 30 minutes' life, gone when it's out;
##   much brighter through night vision, an IR one seen only through it;
## - what's placed is saved with the zone and put back;
## - then a second process joins (late) and sees the placed block, claymore and its tripwire,
##   chem light and burning thermite, and the block going off.
##   <godot> --headless --path . res://tests/demolitions_test.tscn
## The host starts the client itself (same scene, "-- --demolitions-join"). Exits with the
## number of failures.

var failures := 0
var level: VehicleRange
var main: Node
var player: Soldier
var dem: Demolitions
## Host -> client, on join: what to check.
var expect: Dictionary = {}
var _client_lines := PackedStringArray()
var _client_failures := -1
var _client_ready := false
var _asked := false


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_dem" + tag
	Campaign.campaign_id = "test_dem" + tag
	CompoundLevel.spawn_ai = false
	PeopleLayer.populate = false
	Vehicle.fire_rolls = false
	if "--demolitions-join" in OS.get_cmdline_user_args():
		_run_client()
		return
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("DEMOLITIONS TEST FAILED (timed out)")
		get_tree().quit(99))
	GameState.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	level = LevelSwitch.load_level(main, {"level": "range"}) as VehicleRange
	main.menu.host()
	check(level != null and Net.is_hosting(), "hosting the vehicle range")
	if level == null or not Net.is_hosting():
		_finish()
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	var anchor := VoxelViewer.new()  # keep the range's concrete loaded wherever the player is put
	anchor.view_distance = VoxelWorld.VIEW_DISTANCE
	anchor.requires_visuals = false
	anchor.requires_collisions = true
	level.add_child(anchor)
	anchor.global_position = Vector3(-7, 0, -29)
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null and level.voxel_world.is_built(), 10.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # placed by hand
	# A clean kit with room for everything the tests hand him: a carrier, a large ruck, a helmet.
	player.inventory.strip()
	for id: StringName in [&"plate_carrier", &"pack_ruck_70", &"helmet"]:
		player.inventory.take(id)
	dem = Demolitions.of(level)
	check(dem != null, "the level has its Demolitions node")
	await _wait_for(func() -> bool: return _vehicle("range_technical") != null and _vehicle("range_maxxpro") != null, 10.0)
	await _frames(10)
	_test_data()
	await _test_place_and_sabotage()
	await _test_chain()
	await _test_vehicle_block()
	await _test_thermite()
	await _test_claymore_cone()
	await _test_triggers()
	await _test_pickup()
	await _test_chem_lights()
	await _test_save()
	await _test_client()
	_finish()


# --- Data ----------------------------------------------------------------------------------

func _test_data() -> void:
	print("The items")
	check(Demolitions.kind_of(&"demo_block") == Demolitions.DEMO and Demolitions.kind_of(&"thermite") == Demolitions.THERMITE
		and Demolitions.kind_of(&"claymore") == Demolitions.CLAYMORE and Demolitions.kind_of(&"ap_mine") == Demolitions.MINE
		and Demolitions.kind_of(&"chemlight_ir") == Demolitions.CHEMLIGHT and Demolitions.kind_of(&"frag_grenade") == "",
		"each item's kind comes from its data")
	check(Demolitions.arm_modes(&"demo_block") == ["timer:10", "timer:30", "timer:60", "remote", "cord"]
		and Demolitions.arm_modes(&"claymore") == ["remote", "trip", "cord"] and Demolitions.arm_modes(&"ap_mine") == ["pressure"]
		and Demolitions.arm_modes(&"thermite") == [""], "arming modes: block timer/detonator/det cord, claymore detonator/tripwire/cord, mine pressure")
	check(Demolitions.is_detonator(&"clacker") and Demolitions.is_detonator(&"remote_detonator") and Demolitions.detonator_range(&"clacker") < Demolitions.detonator_range(&"remote_detonator"),
		"a clacker on a short wire, a radio remote further")
	var prices := {&"demo_block": 500, &"thermite": 250, &"claymore": 450, &"ap_mine": 200, &"det_cord": 60, &"clacker": 150, &"remote_detonator": 600, &"chemlight_green": 40, &"chemlight_ir": 60}
	var ok := true
	for id: StringName in prices:
		ok = ok and Prices.price_of(id) == int(prices[id]) and Prices.for_sale(id) and Prices.shop_items().has(id)
	check(ok, "Proposed prices in the shop (demo block 500, thermite 250, claymore 450, mine 200...)")
	check(Loadouts.group_of(ItemDB.get_item(&"claymore")) == "grenades" and Loadouts.group_of(ItemDB.get_item(&"chemlight_green")) == "grenades"
		and Loadouts.group_of(ItemDB.get_item(&"clacker")) == "grenades", "in the loadout menu with the grenades")
	check(PlayerInput.THROWABLES.has(&"demo_block") and PlayerInput.THROWABLES.has(&"chemlight_red") and PlayerInput.THROWABLES.has(&"clacker"),
		"in the Shift+G cycle")
	check(Demolitions.in_cone(Vector3.FORWARD, Vector3(0.3, 0.2, -10), 60.0, 20.0) and not Demolitions.in_cone(Vector3.FORWARD, Vector3(0, 0, 10), 60.0, 20.0)
		and not Demolitions.in_cone(Vector3.FORWARD, Vector3(10, 0, -1), 60.0, 20.0) and not Demolitions.in_cone(Vector3.FORWARD, Vector3(0, 8, -10), 60.0, 20.0),
		"a claymore's fan: ahead yes; behind, beside and steeply up no")


# --- Placing, a timer, a sabotage target ---------------------------------------------------

func _test_place_and_sabotage() -> void:
	print("Placing, a timer, a sabotage target")
	# A sabotage target: a box standing in for a fuel store (the range's concrete blocks lie outside
	# its voxel world's edit area, so they aren't there to set a charge on).
	var depot := StaticBody3D.new()
	depot.name = "TestFuelStore"
	depot.collision_layer = 1
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = Vector3(2, 1.2, 1)
	shape.shape = cube
	depot.add_child(shape)
	level.add_child(depot)
	depot.global_position = Vector3(-7, 0.6, -10)
	_put(player, Vector3(-7, 0.1, -8))
	await get_tree().physics_frame
	await _frames(2)
	var eye := player.camera.global_position
	var at_wall := (Vector3(-7, 0.6, -9.5) - eye).normalized()
	var spot := Demolitions.placement(player, eye, at_wall, &"demo_block")
	check(spot.ok and spot.target == null and (spot.normal as Vector3).z > 0.7, "a demo block goes on the store's face (%s)" % [spot.normal])
	check(not Demolitions.placement(player, eye, at_wall, &"ap_mine").ok, "a mine doesn't: it wants flat ground (%s)" % Demolitions.placement(player, eye, at_wall, &"ap_mine").why)
	check(Demolitions.placement(player, eye, (Vector3(-7, 0, -9.2) - eye).normalized(), &"ap_mine").ok, "on the ground in front it does")
	var up := Demolitions.placement(player, eye, Vector3.UP, &"demo_block")
	check(not up.ok, "not on himself (looking up: his own helmet) (%s)" % up.why)
	Contracts.ensure_campaign()  # (a campaign started later would clear the objectives)
	Contracts.objectives.server_add([{"oid": "test_dem_target", "cid": "", "kind": "destroy_cache", "text": "Sabotage: the test fuel store", "state": "active",
		"optional": true, "bonus_share": 0.0, "progress": "", "params": {"box": [[-8, 0, -10.5], [-6, 1.2, -9.5]], "cache": "test_dem_store"}, "pos": [-7, 0.6, -10]}])
	player.inventory.take(&"demo_block", 6)
	var blocks := player.inventory.count_of(&"demo_block")
	# Through the player's own request, as the placing key sends it.
	dem.request_place("demo_block", eye, at_wall, "timer:10")
	await _frames(2)
	var id := _newest(Demolitions.DEMO)
	check(id != "" and player.inventory.count_of(&"demo_block") == blocks - 1 and dem._due.has(id) and absf(float(dem._due[id]) - Demolitions._now() - 10.0) < 0.5,
		"placed on its 10 s timer, one block from his kit (%s)" % id)
	var node := dem.get_node_of(id)
	check(node != null and node.find_child("Light", true, false) != null, "it's in the level with its timer light")
	var fired_before := dem.fired.size()
	dem._due[id] = Demolitions._now() + 0.3
	_put(player, Vector3(-7, 0.1, 15))
	await _seconds(1.0)
	check(dem.fired.size() == fired_before + 1 and not dem.records.has(id), "the timer ran out: it went off")
	check(Contracts.objectives.get_objective("test_dem_target").get("state", "") == "done", "the sabotage target it was on is destroyed (%s; %d objectives)"
		% [Contracts.objectives.get_objective("test_dem_target").get("state", "gone"), Contracts.objectives.list.size()])
	depot.queue_free()


# --- Det cord, a clacker -------------------------------------------------------------------

func _test_chain() -> void:
	print("Det cord and the clacker")
	player.inventory.take(&"clacker")
	player.inventory.take(&"det_cord", 3)
	var a := dem.server_place(player, &"demo_block", _ground(Vector3(20, 0, -20)), null, Demolitions.REMOTE)
	check(dem.place_problem(player, &"demo_block", Vector3(60, 0, -20), Demolitions.CORD) != "", "det cord needs one of his charges within %d m" % roundi(Demolitions.link_m()))
	var cords := player.inventory.count_of(&"det_cord")
	var b := dem.server_place(player, &"demo_block", _ground(Vector3(25, 0, -20)), null, Demolitions.CORD)
	var c := dem.server_place(player, &"demo_block", _ground(Vector3(30, 0, -20)), null, Demolitions.CORD)
	var other := dem.server_place(null, &"demo_block", _ground(Vector3(22, 0, -24)), null, Demolitions.REMOTE)
	await _frames(2)
	check(a != "" and b != "" and c != "" and String(dem.records[b].link) == a and String(dem.records[c].link) == b,
		"corded: each tied to his nearest charge (%s <- %s <- %s)" % [a, b, c])
	check(player.inventory.count_of(&"det_cord") == cords - 2 and dem.chain(a).size() == 3 and dem.chain(c).size() == 3, "a coil each; one chain of three")
	check(dem.get_node_of(b) != null and dem.get_node_of(b).get_node_or_null(^"DetCord") != null, "the cord is drawn")
	_put(player, Vector3(25, 0.1, 50))
	check(dem.server_fire_remote(player, &"clacker") == 0 and dem.records.has(a), "the clacker out of its wire's reach (70 m): nothing goes")
	_put(player, Vector3(25, 0.1, 10))
	var before := dem.fired.size()
	check(dem.server_fire_remote(player, &"clacker") == 3, "in reach: the clacker fires the block and both corded to it")
	check(dem.fired.size() == before + 3 and not dem.records.has(a) and not dem.records.has(b) and not dem.records.has(c), "all three went off")
	check(dem.records.has(other), "somebody else's block on a detonator stays")
	dem.server_remove(other)
	check(dem.server_fire_remote(player, &"remote_detonator") == -1, "nor without the device: he carries no radio remote")
	await _frames(2)


# --- A block on a vehicle ------------------------------------------------------------------

func _test_vehicle_block() -> void:
	print("A block on an MRAP")
	var mrap := _vehicle("range_maxxpro")
	if mrap == null:
		check(false, "the range's MaxxPro is there")
		return
	var hull := mrap.zone_health(Vehicle.ZONE_HULL)
	var on := Transform3D(Basis.IDENTITY, mrap.to_global(Vector3(0.0, VehicleArt.size_m(mrap.model).y + 0.03, 0.5)))
	var id := dem.server_place(player, &"demo_block", on, mrap, "timer:0.2")
	await _frames(2)
	check(id != "" and String(dem.records[id].path) != "" and dem.get_node_of(id).get_parent() == mrap, "a block set on the MaxxPro rides it")
	await _seconds(0.8)
	var after := mrap.zone_health(Vehicle.ZONE_HULL)
	check(not dem.records.has(id) and after <= hull - 0.15, "it went off on the hull: in contact, a big share of an MRAP's hull (%.2f -> %.2f)" % [hull, after])


# --- Thermite ------------------------------------------------------------------------------

func _test_thermite() -> void:
	print("Thermite on a technical")
	var tech := _vehicle("range_technical")
	if tech == null:
		check(false, "the range's technical is there")
		return
	player.inventory.take(&"thermite", 2)
	check(tech.zone_health(Vehicle.ZONE_ENGINE) > 0.5 and not tech.is_burning(), "the technical's engine is whole")
	var hood := Transform3D(Basis.IDENTITY, tech.to_global(Vector3(0.0, 1.2, -2.0)))
	var id := dem.server_place(player, &"thermite", hood, tech)
	await _frames(2)
	check(id != "" and dem._due.has(id) and absf(float(dem._due[id]) - Demolitions._now() - 3.0) < 0.3, "set on the hood, lights in 3 s")
	dem._due[id] = Demolitions._now()
	await _frames(3)
	var node := dem.get_node_of(id)
	check(bool(dem.records[id].burning) and dem._burn_end.has(id) and node and node.get_node_or_null(^"Fire") is OmniLight3D, "it lights: burning, a white-hot light")
	check(dem.server_pickup(player, id) != "Picked up the %s" % ItemDB.get_item(&"thermite").name and dem.records.has(id), "nobody picks up lit thermite")
	dem._burn_end[id] = Demolitions._now()
	await _frames(3)
	check(not dem.records.has(id) and tech.zone_health(Vehicle.ZONE_ENGINE) <= 0.0 and not tech.can_drive() and tech.is_burning(),
		"burnt through: the engine's gone, it can't drive, it's on fire")


# --- A claymore's fan ----------------------------------------------------------------------

func _test_claymore_cone() -> void:
	print("A claymore's fan")
	player.inventory.take(&"claymore", 2)
	var at := Vector3(30, 0, -50)
	var front := _dummy(at + Vector3(0, 0, -10))
	var back := _dummy(at + Vector3(0, 0, 10))
	var side := _dummy(at + Vector3(10, 0, 0))
	await _frames(4)
	var look := Vector3.FORWARD
	var spot := {"pos": at, "normal": Vector3.UP}
	var id := dem.server_place(player, &"claymore", Demolitions.place_transform(&"claymore", spot, look), null, Demolitions.REMOTE)
	await _frames(2)
	check(id != "" and (-dem.transform_of(id).basis.z).dot(Vector3.FORWARD) > 0.99, "set facing where he looks")
	_put(player, at + Vector3(0, 0.1, 25))
	await _frames(2)
	check(dem.server_fire_remote(player, &"clacker") == 1, "fired by the clacker 25 m behind it")
	await _frames(3)
	var hits := func(d: TargetDummy) -> int: return d.vitals.wound_list().size()
	check(hits.call(front) > 0, "the dummy 10 m in front is hit (%d wounds)" % hits.call(front))
	check(hits.call(back) == 0 and hits.call(side) == 0, "the ones 10 m behind and beside it aren't (%d, %d)" % [hits.call(back), hits.call(side)])
	check(player.vitals.wound_list().is_empty(), "nor he, behind it")
	for d in [front, back, side]:
		d.queue_free()


# --- Tripwires, mines ----------------------------------------------------------------------

func _test_triggers() -> void:
	print("A tripwire and a mine")
	var markers := MapNodes.markers(level)
	var hostile := _soldier("Mover", &"hostile", Vector3(70, 0.1, -60))
	await _frames(4)
	# The tripwire: 2 m out, 4 m across.
	var at := Vector3(60, 0, -40)
	var trip := dem.server_place(player, &"claymore", Demolitions.place_transform(&"claymore", {"pos": at, "normal": Vector3.UP}, Vector3.FORWARD), null, Demolitions.TRIP)
	await _frames(2)
	var node := dem.get_node_of(trip)
	check(trip != "" and node and node.find_child("Tripwire", true, false) != null, "a claymore on a tripwire, the wire drawn")
	check(markers and markers.list("field").any(func(m: Dictionary) -> bool: return String(m.text) == "Our claymore"), "our claymore is on the map")
	check(dem.hazards(&"friendly").any(func(h: Dictionary) -> bool: return h.id == trip) and dem.hazards(&"hostile").is_empty(), "and in our side's hazards for the AI")
	_put(hostile, at + Vector3(0.5, 0.1, -2.05))
	await _seconds(0.4)
	check(dem.records.has(trip) and not dem.is_live(trip), "not live yet (it arms after 10 s): walking through does nothing")
	dem._arms_at[trip] = Demolitions._now()
	await _seconds(0.4)
	check(not dem.records.has(trip) and dem.fired.any(func(f: Dictionary) -> bool: return f.id == trip), "live: he walks into the wire and sets it off")
	check(not markers.list("field").any(func(m: Dictionary) -> bool: return String(m.text) == "Our claymore"), "its map marker goes with it")
	# A pressure mine.
	player.inventory.take(&"ap_mine", 4)
	var hostile2 := _soldier("Stepper", &"hostile", Vector3(-30, 0.1, -55))
	await _frames(4)
	_put(player, Vector3(-40, 0.1, -38))
	await _frames(2)
	var eye := player.camera.global_position
	var down := (Vector3(-40, 0, -39.6) - eye).normalized()
	var spot := Demolitions.placement(player, eye, down, &"ap_mine")
	var mine := dem.server_place(player, &"ap_mine", Demolitions.place_transform(&"ap_mine", spot, down), spot.target, Demolitions.PRESSURE)
	await _frames(2)
	check(mine != "" and absf(dem.transform_of(mine).origin.y) < 0.05, "a mine buried flush with the ground in front of him")
	_put(player, Vector3(-40, 0.1, -20))
	var mine_pos := dem.position_of(mine)
	_put(hostile2, mine_pos + Vector3(0.1, 0.1, 0.0))
	await _seconds(0.4)
	check(dem.records.has(mine), "not live yet: stepping on it does nothing")
	dem._arms_at[mine] = Demolitions._now()
	await _seconds(0.4)
	check(not dem.records.has(mine), "live: he steps on it and it goes")
	check(hostile2.vitals.wound_list().any(func(w: Dictionary) -> bool: return w.part in [Vitals.SHIN_L, Vitals.SHIN_R]), "his leg takes it")
	check(not hostile2.vitals.gore_list().is_empty(), "and the blast's gore is on him (BlastGore: %d entries)" % hostile2.vitals.gore_list().size())
	# A vehicle over one.
	var matv := _vehicle("range_matv")
	if matv:
		var under := dem.server_place(player, &"ap_mine", Transform3D(Basis.IDENTITY, Vector3(matv.global_position.x, 0.0, matv.global_position.z)), null, Demolitions.PRESSURE)
		dem._arms_at[under] = Demolitions._now()
		await _seconds(0.4)
		check(under != "" and not dem.records.has(under), "a mine under a vehicle's wheels goes off")
	hostile.queue_free()
	hostile2.queue_free()


# --- Picking up ----------------------------------------------------------------------------

func _test_pickup() -> void:
	print("Picking it up again")
	_put(player, Vector3(-20, 0.1, -10))
	await _frames(2)
	var id := dem.server_place(player, &"ap_mine", _ground(Vector3(-20, 0, -11.5)), null, Demolitions.PRESSURE)
	var mines := player.inventory.count_of(&"ap_mine")
	var node := dem.get_node_of(id)
	check(node and node.is_in_group(InteractionMenu.INTERACTABLES) and not node.interaction_actions(player).is_empty(), "the interaction menu offers to pick it up")
	_put(player, Vector3(-20, 0.1, -2))
	check(dem.server_pickup(player, id) == "Too far away" and dem.records.has(id), "not from 9 m off")
	_put(player, Vector3(-20, 0.1, -10))
	check(dem.server_pickup(player, id).begins_with("Picked up") and not dem.records.has(id) and player.inventory.count_of(&"ap_mine") == mines + 1, "from beside it: back in his kit")
	await _frames(2)


# --- Chem lights ---------------------------------------------------------------------------

func _test_chem_lights() -> void:
	print("Chem lights")
	_put(player, Vector3(-30, 0.1, 30))
	await _frames(2)
	player.inventory.take(&"chemlight_red", 2)
	var count := player.inventory.count_of(&"chemlight_red")
	var lights := _ids_of(Demolitions.CHEMLIGHT).size()
	player._server_busy_until = 0.0
	player._server_throw.rpc_id(1, player.camera.global_position, Vector3(0, -0.3, -1).normalized(), &"chemlight_red", 0.45)
	await _wait_for(func() -> bool: return _ids_of(Demolitions.CHEMLIGHT).size() > lights, 8.0)
	var thrown := _newest(Demolitions.CHEMLIGHT)
	check(player.inventory.count_of(&"chemlight_red") == count - 1 and thrown != "" and String(dem.records[thrown].item) == "chemlight_red",
		"a red chem light lobbed comes to rest as a placed light")
	check(thrown != "" and absf(dem.position_of(thrown).y) < 0.3, "on the ground (y %.2f)" % (dem.position_of(thrown).y if thrown != "" else -1.0))
	var green := dem.server_add_chemlight(&"chemlight_green", Vector3(-28, 0, 26))
	var ir := dem.server_add_chemlight(&"chemlight_ir", Vector3(-27, 0, 26))
	await _seconds(0.4)
	check(absf(float(dem.records[green].life_s) - 1800.0) < 1.0 and absf(float(dem._expire[green]) - Demolitions._now() - 1800.0) < 2.0, "it glows for 30 minutes")
	var glow_of := func(id: String) -> OmniLight3D: return dem.get_node_of(id).find_child("Glow", true, false) as OmniLight3D
	var bare: float = glow_of.call(green).light_energy
	check(glow_of.call(green).visible and is_equal_approx(bare, Demolitions.GLOW_ENERGY), "a soft green light to the eye (%.2f)" % bare)
	check(not glow_of.call(ir).visible, "the IR one shows no light to the eye")
	# Night vision.
	var inv := player.inventory
	if inv.slots.get(&"helmet", &"") == &"":
		inv.take(&"helmet")
	inv.take(&"nvg_gen2")
	player.server_toggle_nvg()
	await _seconds(0.5)
	check(Nvg.is_on(player), "his NVG is down")
	var through: float = glow_of.call(green).light_energy
	check(through > bare * 3.0 and glow_of.call(green).omni_range > Demolitions.GLOW_RANGE_M, "through it the green one is far brighter (%.2f) and reaches further" % through)
	check(glow_of.call(ir).visible, "and the IR one shows")
	var g := Demolitions.glow(&"chemlight_blue", true)
	check(is_equal_approx(float(g.energy), Demolitions.GLOW_ENERGY * Demolitions.NVG_GAIN) and Demolitions.glow(&"chemlight_blue", false, 10.0).energy < Demolitions.GLOW_ENERGY,
		"glow(): NVG gain, dimming in its last minute")
	player.server_toggle_nvg()
	# Going out.
	dem._expire[green] = Demolitions._now() + 0.2
	await _seconds(0.6)
	check(not dem.records.has(green) and dem.get_node_of(green) == null, "when its time is up it's out and gone")
	dem.server_remove(ir)
	dem.server_remove(thrown)
	await _frames(2)


# --- The zone save -------------------------------------------------------------------------

func _test_save() -> void:
	print("Saved with the zone")
	var block := dem.server_place(player, &"demo_block", _ground(Vector3(-50, 0, 30)), null, Demolitions.REMOTE)
	var mine := dem.server_place(player, &"ap_mine", _ground(Vector3(-52, 0, 30)), null, Demolitions.PRESSURE)
	var light := dem.server_add_chemlight(&"chemlight_blue", Vector3(-54, 0, 30))
	await _frames(2)
	check(GameState.save_zone(), "the zone saves")
	var saved: Array = GameState.read_save(GameState.save_path()).get("demolitions", [])
	var ids := saved.map(func(r: Dictionary) -> String: return String(r.id))
	check(block in ids and mine in ids and light in ids, "the block, the mine and the chem light are in the save (%d placed)" % saved.size())
	for id in [block, mine, light]:
		dem.server_remove(id)
	await _frames(2)
	check(not dem.records.has(block) and not dem.records.has(mine), "taken away")
	var back := dem.server_restore(saved)
	await _frames(2)
	check(back >= 3 and dem.records.has(block) and String(dem.records[block].arm) == Demolitions.REMOTE and dem.records.has(mine) and dem._arms_at.has(mine)
		and dem.records.has(light) and dem._expire.has(light) and dem.get_node_of(block) != null,
		"put back from the save: the block on its detonator, the mine with its clock, the light glowing (%d)" % back)
	check(dem._markers.has(mine), "our mine marked on the map again")
	for id in [block, mine, light]:
		dem.server_remove(id)


# --- A client joins ------------------------------------------------------------------------

func _test_client() -> void:
	print("Replication (a client joins)")
	_put(player, Vector3(0, 0.1, 10))
	player.inventory.take(&"claymore")
	player.inventory.take(&"demo_block")
	var block := dem.server_place(player, &"demo_block", _ground(Vector3(-10, 0, 30)), null, Demolitions.REMOTE)
	var trip := dem.server_place(player, &"claymore", Demolitions.place_transform(&"claymore", {"pos": Vector3(-14, 0, 30), "normal": Vector3.UP}, Vector3.FORWARD), null, Demolitions.TRIP)
	var light := dem.server_add_chemlight(&"chemlight_green", Vector3(-16, 0, 30))
	player.inventory.take(&"thermite")
	var therm := dem.server_place(player, &"thermite", _ground(Vector3(-18, 0, 30)))
	dem._due[therm] = Demolitions._now()
	await _frames(3)
	if dem._burn_end.has(therm):
		dem._burn_end[therm] = Demolitions._now() + 120.0  # still burning when the client comes
	expect = {"block": block, "trip": trip, "light": light, "thermite": therm}
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = false
	var log_path := OS.get_user_data_dir().path_join("demolitions_client%s.log" % OS.get_environment("CONTRACTOR_TEST_TAG"))
	DirAccess.remove_absolute(log_path)
	var args := ["--headless", "--log-file", log_path, "--path", ProjectSettings.globalize_path("res://"), "res://tests/demolitions_test.tscn",
		"--", "--demolitions-join"]
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "started the client process")
	await _wait_until(func() -> bool: return _client_ready, 150.0)
	check(_client_ready, "the client saw what was placed before it joined")
	if _client_ready:
		dem.server_fire_remote(player, &"clacker")
		_fired.rpc()
	await _wait_until(func() -> bool: return _client_failures >= 0, 45.0)
	for line in _client_lines:
		print("    client: %s" % line)
	check(_client_failures == 0, "everything replicated to the client (%d client failures)" % _client_failures)
	if pid > 0:
		await _wait_until(func() -> bool: return not OS.is_process_running(pid), 10.0)
		if OS.is_process_running(pid):
			OS.kill(pid)
	var errors := PackedStringArray()
	if FileAccess.file_exists(log_path):
		for line in FileAccess.get_file_as_string(log_path).split("\n"):
			if line.contains("SCRIPT ERROR"):
				errors.append(line)
	for line in errors:
		print("    client: %s" % line)
	check(FileAccess.file_exists(log_path) and errors.is_empty(), "no script errors in the client's log (%d)" % errors.size())


@rpc("any_peer", "call_remote", "reliable")
func _expect(data: Dictionary) -> void:
	expect = data


@rpc("any_peer", "call_remote", "reliable")
func _ask_expect() -> void:
	if multiplayer.is_server() and not _asked:
		_asked = true
		print("[test] the client asked for its checks at %.1f s" % (Time.get_ticks_msec() / 1000.0))
	if multiplayer.is_server() and not expect.is_empty():
		_expect.rpc_id(multiplayer.get_remote_sender_id(), expect)


@rpc("any_peer", "call_remote", "reliable")
func _ready_for_live() -> void:
	_client_ready = true


@rpc("authority", "call_remote", "reliable")
func _fired() -> void:
	expect["fired"] = true


@rpc("any_peer", "call_remote", "reliable")
func _client_report(count: int, lines: PackedStringArray) -> void:
	_client_lines = lines
	_client_failures = count


## Both processes: a frame that held the main thread long enough to time a link out is printed
## (a dropped join is then explained in the log).
func _process(delta: float) -> void:
	if delta > 2.0:
		print("[test] a %.1f s frame at %.1f s" % [delta, Time.get_ticks_msec() / 1000.0])


func _run_client() -> void:
	get_tree().create_timer(200.0).timeout.connect(func() -> void: get_tree().quit(99))
	Net.peer_left.connect(func(id: int) -> void: print("[test] peer %d left at %.1f s" % [id, Time.get_ticks_msec() / 1000.0]))
	Net.joined.connect(func() -> void: print("[test] joined at %.1f s" % (Time.get_ticks_msec() / 1000.0)))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	if Net.session_ended.is_connected(Callable(main, &"_on_session_ended")):
		Net.session_ended.disconnect(Callable(main, &"_on_session_ended"))
	await get_tree().process_frame
	var lines := PackedStringArray()
	var note := func(ok: bool, what: String) -> void:
		lines.append("[%s] %s" % ["ok" if ok else "FAIL", what])
		if not ok:
			failures += 1
	# The sounds build at boot: join once that's done, so a busy start doesn't time the link out.
	await _wait_until(func() -> bool: return Sfx.is_prebuilt(), 60.0)
	var joined := await _join_host("127.0.0.1", 90.0)
	var asked_until := Time.get_ticks_msec() + 90000
	var asks := 0
	while expect.is_empty() and Time.get_ticks_msec() < asked_until:
		var link := multiplayer.multiplayer_peer
		if not (link is ENetMultiplayerPeer) or link.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			print("[test] not connected at %.1f s: joining again" % (Time.get_ticks_msec() / 1000.0))
			joined = await _join_host("127.0.0.1", 30.0)  # dropped: join again
			continue
		if link.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			asks += 1
			if asks == 1 or asks % 5 == 0:
				print("[test] asking the host (%d) at %.1f s; peers %s" % [asks, Time.get_ticks_msec() / 1000.0, multiplayer.get_peers()])
			_ask_expect.rpc_id(1)
		await _wait_until(func() -> bool: return not expect.is_empty(), 3.0)
	var lvl := CompoundLevel.current(self)
	var d := Demolitions.of(lvl) if lvl else null
	if d == null or expect.is_empty():
		note.call(false, "joined and got the host's expectations")
	else:
		var have := func() -> bool: return d.records.has(String(expect.block)) and d.records.has(String(expect.trip)) \
			and d.records.has(String(expect.light)) and d.records.has(String(expect.thermite))
		await _wait_until(have, 20.0)
		note.call(have.call(), "the block, the claymore, the chem light and the thermite placed before we joined are here (expected %s; have %s)" % [expect, d.records.keys()])
		var trip := d.get_node_of(String(expect.trip))
		note.call(trip != null and trip.find_child("Tripwire", true, false) != null, "the claymore with its tripwire")
		var light := d.get_node_of(String(expect.light))
		var glow := light.find_child("Glow", true, false) as OmniLight3D if light else null
		note.call(glow != null and glow.visible and glow.light_energy > 0.0, "the chem light glowing")
		var therm := d.get_node_of(String(expect.thermite))
		note.call(therm != null and therm.get_node_or_null(^"Fire") is OmniLight3D and bool(d.records[String(expect.thermite)].get("burning", false)), "the thermite burning")
		var block := d.get_node_of(String(expect.block))
		note.call(block != null and block.global_position.distance_to(Vector3(-10, 0, 30)) < 0.2, "the block where it was set")
		_ready_for_live.rpc_id(1)
		await _wait_until(func() -> bool: return expect.has("fired") and not d.records.has(String(expect.block)), 20.0)
		note.call(not d.records.has(String(expect.block)) and d.get_node_of(String(expect.block)) == null, "the host's clacker: the block went off here too")
	_client_report.rpc_id(1, failures, lines)
	await get_tree().create_timer(1.0).timeout
	Net.leave()
	get_tree().quit(failures)


# --- Helpers -------------------------------------------------------------------------------

func _vehicle(id: String) -> Vehicle:
	for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
		if n is Vehicle and (n as Vehicle).vehicle_id == id:
			return n as Vehicle
	return null


## A transform on the ground at `p`, facing -z.
func _ground(p: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.z) + Vector3.UP * Charges.SURFACE_OFFSET_M)


## The newest record of `kind`.
func _newest(kind: String) -> String:
	var ids := _ids_of(kind)
	ids.sort_custom(func(a: String, b: String) -> bool: return a.trim_prefix("D").to_int() < b.trim_prefix("D").to_int())
	return ids.back() if not ids.is_empty() else ""


func _ids_of(kind: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in dem.records:
		if String(dem.records[id].kind) == kind:
			out.append(id)
	return out


func _dummy(pos: Vector3) -> TargetDummy:
	var dummy: TargetDummy = load("res://scenes/target_dummy.tscn").instantiate()
	dummy.loadout = PackedStringArray()
	dummy.respawn_seconds = 999.0
	level.add_child(dummy)
	dummy.global_position = pos
	return dummy


func _soldier(callsign: String, faction: StringName, pos: Vector3) -> Soldier:
	var s := level.spawn_soldier({"name": callsign, "person_name": callsign, "faction": String(faction), "variant": "woodland", "pos": pos,
		"loadout": [], "combat": 0.9, "discipline": 0.6, "guard": true})
	var ai := SquadAI.of(s)
	if ai:
		ai.process_mode = Node.PROCESS_MODE_DISABLED
	return s


func _put(s: Node3D, pos: Vector3) -> void:
	s.global_position = pos
	if s is CharacterBody3D:
		(s as CharacterBody3D).velocity = Vector3.ZERO


func _join_host(address: String, seconds: float) -> bool:
	var joined := [false]
	Net.joined.connect(func() -> void: joined[0] = true)
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not (joined[0] or 1 in multiplayer.get_peers()) and Time.get_ticks_msec() < deadline:
		var peer := multiplayer.multiplayer_peer
		if not (peer is ENetMultiplayerPeer) or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			Net.join(address)
		await get_tree().create_timer(2.0).timeout
	return joined[0] or 1 in multiplayer.get_peers()


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _finish() -> void:
	GameState.delete_save()
	print("DEMOLITIONS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	Net.leave()
	get_tree().quit(failures)


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	return condition.call()


func _wait_until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return cond.call()


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
