extends Node
## The tutorial (TutorialGuide) as the main menu starts it: the compound with the squad's AI, the
## guide opened before the walls are up. Its setup (the kit, the compound's patrol gone, the squad
## holding fire, the target in the open, the M-ATV, the villager, a static gun's loads when the
## game has them), then every step from the medical section on, driven through the requests the
## real controls send (the self-treatment, the command menu's keys, the vehicle's Left Ctrl
## requests, the villager's menu, picking up and setting up the gun). Each step is checked to stay
## put until its thing is done, and to tick off once it is.
##   <godot> --headless --path . res://tests/tutorial_test.tscn

var failures := 0
var level: CompoundLevel
var player: Soldier
var guide: TutorialGuide
var _done_at := 0  # the guide's done count when the step under test was last seen standing (_stays)


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_tutorial" + tag  # never touch a real save
	Campaign.campaign_id = "test_tutorial" + tag
	Vehicle.local_input = false  # driving goes by request, as the driver's peer sends it
	Vehicle.fire_rolls = false
	ControlOptions._get_out = false  # the seat's Get out, whatever this machine's settings say (never saved)
	ControlOptions._loaded = true
	get_tree().create_timer(440.0).timeout.connect(func() -> void:
		print("TUTORIAL TEST FAILED (timed out at step %d)" % (guide.step if is_instance_valid(guide) else -1))
		get_tree().quit(99))
	GameState.delete_save()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 10.0)
	player = level.players.get_node_or_null(^"1")
	if player == null:
		check(false, "the host's player is in")
		_finish()
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	guide = TutorialGuide.start(level)  # as the menu does, before the compound's walls are up
	check(guide != null and TutorialGuide.of(level) == guide, "the tutorial opens in the compound")
	await _wait_for(func() -> bool: return level.voxel_world.is_built() and level.ai.get_node_or_null(NodePath(TutorialGuide.TARGET)) != null, 90.0)
	await _seconds(1.0)
	_test_setup()
	await _test_medical()
	await _test_tagging()
	await _test_vehicles()
	await _test_rebels()
	await _test_static_guns()
	check(guide.step == guide.steps.size() and guide._title.text.begins_with("Tutorial: done"),
		"the end: done, %d of %d steps done by doing them" % [guide.done, guide.steps.size()])
	_finish()


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _finish() -> void:
	GameState.delete_save()
	print("TUTORIAL TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	Net.leave()
	get_tree().quit(failures)


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	return condition.call()


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


## Page Down (the guide's own skip) until the step checked by `check` is the current one.
func _skip_to(check_name: String) -> bool:
	var at := guide.index_of(check_name)
	if at < 0:
		return false
	var skip := InputEventKey.new()
	skip.physical_keycode = TutorialGuide.SKIP_KEY
	skip.pressed = true
	while guide.step < at:
		guide._input(skip)
	return guide.step == at


## The current step stays put for `seconds` while nothing is done.
func _stays(what: String, seconds := 1.0) -> void:
	var at := guide.step
	await _seconds(seconds)
	check(guide.step == at, "%s: not done yet, the step stays (%s)" % [what, guide._title.text])
	_done_at = guide.done


## The step checked by `check_name` ticks off (within `seconds`), counted done (since _stays).
func _ticks(check_name: String, what: String, seconds: float) -> void:
	var at := guide.index_of(check_name)
	var ok := await _wait_for(func() -> bool: return guide.step > at, seconds)
	check(ok and guide.done == _done_at + 1, "%s ticks the step off (now %d: %s)" % [what, guide.step, guide._title.text])


## A key pressed in the command menu (the HUD's, as the player's keys reach it).
func _menu_keys(keys: Array) -> void:
	var menu: CommandMenu = player._hud.command_menu
	for k: Key in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.pressed = true
		menu.handle_input(e)
	await get_tree().physics_frame


# --- Setup ---------------------------------------------------------------------------------------

func _test_setup() -> void:
	print("Setup")
	var left := 0
	for h: Dictionary in CompoundLevel.HOSTILES:
		var foe := level.ai.get_node_or_null(NodePath(String(h.name)))
		if foe and not foe.is_queued_for_deletion():
			left += 1
	check(left == 0, "the compound's own patrol is gone: nobody fights while you learn (%d left)" % left)
	var target := level.ai.get_node_or_null(NodePath(TutorialGuide.TARGET)) as Soldier
	check(target != null and target.faction == &"hostile" and SquadAI.of(target).process_mode == Node.PROCESS_MODE_DISABLED,
		"a stand-in enemy stands in the yard, not moving or shooting")
	var squad := level.squad_for(&"friendly")
	var mates: Array = squad.members() if squad else []
	check(mates.size() >= 2 and mates.all(func(s: Soldier) -> bool: return SquadAI.of(s).hold_fire),
		"the squad is there (%d) and holds fire" % mates.size())
	check(player.inventory.count_of(&"radio") > 0 and player.inventory.count_of(&"pressure_bandage") >= 2 and player.inventory.count_of(&"ifak") > 0,
		"the kit: a radio, loose bandages, an IFAK (%s)" % [TutorialGuide.KIT.keys().map(func(id: StringName) -> String: return "%s %d" % [id, player.inventory.count_of(id)])])
	var v := VehicleLayer.of(level).find(TutorialGuide.VEHICLE_ID)
	check(v != null and v.model == TutorialGuide.VEHICLE_MODEL and v.occupants().is_empty() and v.global_position.distance_to(TutorialGuide.VEHICLE_AT) < 3.0,
		"an empty M-ATV is parked south-west of the gate")
	var villager := _villager()
	check(villager != null and Person.is_civilian(villager) and String(Person.state(villager).get("order", "")) == "stop",
		"a villager waits by the gate")
	var has_guns := TutorialGuide.STATIC_LOADS.all(func(id: StringName) -> bool: return ItemDB.has_item(id))
	var loads := _loads_on_ground()
	check(loads.size() == (2 if has_guns else 0), "the static gun's loads lie out (%d; this build has static guns: %s)" % [loads.size(), has_guns])
	check(guide.step == 0 and guide._title.text.contains("Moving"), "it starts at the first section (%s)" % guide._title.text)


func _villager() -> Soldier:
	var people := PeopleLayer.find(level)
	for p in people.people() if people else []:
		if String(p.name) == TutorialGuide.VILLAGER:
			return p
	return null


func _loads_on_ground() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var w := n as WorldItem
		if w and w.item_id in TutorialGuide.STATIC_LOADS and not w.is_queued_for_deletion():
			out.append(w)
	return out


# --- Medical -------------------------------------------------------------------------------------

func _test_medical() -> void:
	print("Medical")
	check(_skip_to("_self_treated") and guide._title.text.contains("Medical"), "Page Down to the medical section (%s)" % guide._title.text)
	var grazes := player.vitals.care_needed().filter(func(t: Dictionary) -> bool: return String(t.kind) == "graze")
	check(grazes.size() == 1 and grazes[0].part == &"forearm_l", "the step grazes your arm (%s)" % [grazes])
	await _stays("treating yourself")
	var bandages := player.inventory.medical_count(&"pressure_bandage")
	if not grazes.is_empty():
		player._server_treat.rpc_id(1, player.get_path(), &"pressure_bandage", grazes[0].part)
	await _ticks("_self_treated", "a pressure bandage on your own arm", 20.0)
	check(player.inventory.medical_count(&"pressure_bandage") == bandages - 1, "it used one of your bandages (%d -> %d)" % [bandages, player.inventory.medical_count(&"pressure_bandage")])
	var leg := player.vitals.care_needed().filter(func(t: Dictionary) -> bool: return String(t.kind) == "graze")
	check(leg.size() == 1 and leg[0].part == &"shin_r", "the next step grazes your leg (%s)" % [leg])
	await _stays("calling a medic")
	await _menu_keys([KEY_QUOTELEFT, KEY_5, KEY_3])  # ` (everyone), 5 Status, 3 Medic!
	await _ticks("_medic_called", "the command menu's Medic!", 3.0)
	check(Soldier._now() - player.medic_asked_at < 5.0, "the host has his call")
	await _stays("waiting for the medic", 0.5)
	await _ticks("_patched_up", "a squadmate bandaging your leg", 90.0)
	check(not TutorialGuide._bleeding(player), "nothing bleeds now")


# --- Tagging -------------------------------------------------------------------------------------

func _test_tagging() -> void:
	print("Tagging")
	check(_skip_to("_tagged") and guide._title.text.contains("Tagging"), "the tagging section (%s)" % guide._title.text)
	var target := level.ai.get_node_or_null(NodePath(TutorialGuide.TARGET)) as Soldier
	player.global_position = level.above_ground(Vector3(0, 0.1, 17))  # just inside the gate: the yard in front
	await _stays("tagging")
	if target:
		player._server_tag_enemy.rpc_id(1, String(target.name))  # the Tag key's request
	await _ticks("_tagged", "tagging the target from the gate (Y, by radio)", 3.0)


# --- Vehicles ------------------------------------------------------------------------------------

func _test_vehicles() -> void:
	print("Vehicles")
	check(_skip_to("_driving") and guide._title.text.contains("Vehicles"), "the vehicles section (%s)" % guide._title.text)
	var v := VehicleLayer.of(level).find(TutorialGuide.VEHICLE_ID)
	if v == null:
		check(false, "the M-ATV is there")
		return
	player.global_position = _door_for(v, v.driver_seat())
	await get_tree().physics_frame
	v.request_enter(1)  # the commander's seat (Left Ctrl > Get in)
	await _stays("in the commander's seat")
	check(v.seat_of(player) == 1, "sitting as a passenger doesn't count")
	v.request_switch(v.driver_seat())
	await _ticks("_driving", "the driver's seat", 3.0)
	await _stays("at the wheel, standing still")
	var start := v.global_position
	var deadline := Time.get_ticks_msec() + 12000
	while guide.step == guide.index_of("_driven") and Time.get_ticks_msec() < deadline:
		v.request_drive(1.0, 0.0, false)  # throttle (W), as the driver's peer sends it
		await get_tree().physics_frame
	check(guide.step > guide.index_of("_driven"), "driving %.0f m ticks the drive step off" % start.distance_to(v.global_position))
	for i in 60:
		v.request_drive(0.0, 0.0, true)
		await get_tree().physics_frame
	await _stays("at the wheel")
	var gun_seat := int(v.gun_info().get("seat", -1))
	v.request_switch(gun_seat)  # Left Ctrl inside > Move to > Gunner
	await _ticks("_on_gun", "the gunner's seat", 3.0)
	await _stays("the squad still outside")
	player.server_squad_command("mount", v.global_position, PackedStringArray())  # Mount > Get in that vehicle, aimed at it
	await _ticks("_squad_aboard", "the squad ordered in, a squadmate climbing in", 75.0)
	await _stays("everyone still aboard", 0.5)
	v.request_exit()  # the seat's Get out
	await _menu_keys([KEY_QUOTELEFT, KEY_4, KEY_2])  # ` (everyone), 4 Mount, 2 Get out
	await _ticks("_all_out", "getting out and ordering the squad out", 30.0)
	check(v.occupants().is_empty(), "the M-ATV is empty")


## Where to stand to reach `v`'s door serving `seat` (its Left Ctrl point).
func _door_for(v: Vehicle, seat: int) -> Vector3:
	for p in v.get_children():
		var point := p as VehicleActionPoint
		if point and point.kind == VehicleActionPoint.DOOR and seat in point.seat_list:
			return level.above_ground(Vector3(point.global_position.x, 0.1, point.global_position.z))
	return v.global_position + v.global_basis.x * -2.0


# --- Rebel support -------------------------------------------------------------------------------

func _test_rebels() -> void:
	print("Rebel support")
	check(_skip_to("_asked_for_work") and guide._title.text.contains("Rebel"), "the rebel support section (%s)" % guide._title.text)
	var villager := _villager()
	if villager == null:
		check(false, "the villager is there")
		return
	player.global_position = villager.global_position + Vector3(0, 0, 1.5)
	await get_tree().physics_frame
	var ids := InteractionMenu.actions_for(player, villager).map(func(a: Dictionary) -> StringName: return a.id)
	check(&"ask_locals" in ids and &"give_locals" in ids, "his Left Ctrl menu offers Ask if they need help and Give supplies (%s)" % [ids])
	await _stays("asking the villager")
	player._server_ask_locals.rpc_id(1, villager.get_path())
	await _ticks("_asked_for_work", "asking him for work", 3.0)
	await _stays("giving supplies")
	var where := _medical_entry()  # a loose bandage if one's left (the medic may have used yours), else the IFAK
	var given: StringName = player.inventory.containers[where[0]][where[1]].id if not where.is_empty() else &""
	var before := player.inventory.count_of(given)
	if not where.is_empty():
		player._server_give_locals.rpc_id(1, villager.get_path(), where[0], where[1])
	await _ticks("_gave_supplies", "giving him the %s" % given, 3.0)
	check(given != &"" and player.inventory.count_of(given) == before - 1, "it's his now (%s)" % given)
	check(Supports.server_command(player, "support:rebel_fighters", player.global_position, PackedStringArray()) != "",
		"in the tutorial the rebels' other call-ins say no")
	await _stays("calling the rebels")
	await _menu_keys([KEY_QUOTELEFT, KEY_0, KEY_9, KEY_1])  # ` (everyone), 0 Support, 9 Rebels, 1 Lookouts
	await _ticks("_lookouts_out", "Support > Rebels > Lookouts", 3.0)
	check(RebelCalls.of(level).lookouts_for(player), "the lookouts watch for you")


## [container, index] of a stowed pressure bandage in the player's gear, else of an IFAK, or [].
func _medical_entry() -> Array:
	for id: StringName in [&"pressure_bandage", &"ifak"]:
		for c: StringName in player.inventory.search_containers():
			var list: Array = player.inventory.containers[c]
			for i in list.size():
				if StringName(String((list[i] as Dictionary).get("id", ""))) == id:
					return [c, i]
	return []


# --- Static guns ---------------------------------------------------------------------------------

func _test_static_guns() -> void:
	print("Static guns")
	if not TutorialGuide.STATIC_LOADS.all(func(id: StringName) -> bool: return ItemDB.has_item(id)):
		check(guide.index_of("_holding_load") < 0 and guide.index_of("_gun_up") < 0 and guide.index_of("_gun_packed") < 0,
			"no static guns in this build: the section is left out")
		return
	check(_skip_to("_holding_load") and guide._title.text.contains("Static"), "the static guns section (%s)" % guide._title.text)
	var tripod: WorldItem = null
	for n in _loads_on_ground():
		if (n as WorldItem).item_id == TutorialGuide.STATIC_LOADS[1]:
			tripod = n
	if tripod == null:
		check(false, "the tripod lies there")
		return
	player.global_position = level.above_ground(Vector3(tripod.global_position.x, 0.1, tripod.global_position.z + 1.0))
	await get_tree().physics_frame
	await _stays("the loads still on the ground")
	player._server_interact.rpc_id(1, tripod.get_path())  # Left Ctrl > Pick up
	await _ticks("_holding_load", "picking up the tripod (both hands)", 3.0)
	await _stays("carrying it")
	player.rpc_id(1, &"_server_set_up_static")  # Left Ctrl + Left Alt > Set up the gun (StaticWeapons)
	await _ticks("_gun_up", "setting the gun up, the gun's load beside you", 40.0)
	check(player.inventory.hands == &"", "the loads went into the gun")
	await _stays("the gun still up")
	var gun: Vehicle = null
	for v in VehicleLayer.of(level).vehicles():
		if v.kind == Vehicle.STATIC and v.global_position.distance_to(player.global_position) < TutorialGuide.GUN_NEAR_M:
			gun = v
	if gun:
		gun.rpc_id(1, &"request_pack")  # its Left Ctrl point > Pack up the gun
	await _ticks("_gun_packed", "packing it up again", 40.0)
	check(player.inventory.hands in TutorialGuide.STATIC_LOADS, "a load is back in your hands (%s)" % player.inventory.hands)
