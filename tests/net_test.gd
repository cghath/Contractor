extends Node
## Two-process co-op check over real ENet: one instance hosts, one joins, and the client
## drives its player through RPCs and checks what replicates back.
##   <exe> --headless --path . res://tests/net_test.tscn -- --host
##   <exe> --headless --path . res://tests/net_test.tscn -- --join 127.0.0.1
## The client prints NET TEST PASSED/FAILED and exits with the failure count; the host
## exits when the client leaves.

const KIT: Array[StringName] = [&"plate_carrier", &"plate_ceramic_l4", &"m4a1", &"helmet", &"assault_pack"]
## A dead player's body in the zone save the host loads (as Soldier.body_record writes it), so
## the client, joining late, finds it there with its gear.
const SAVED_BODY := {"uid": "test_net_body_1", "label": "Player 9", "faction": "friendly", "variant": "desert", "role": "",
	"pos": [0.0, 0.1, 26.5], "rot_y": 0.0, "age_s": 30.0, "marker": true,
	"gear": {"slots": {"primary": "m4a1", "vest": "plate_carrier", "helmet": "helmet"}, "slot_state": {"primary": {"rounds": 21}},
		"containers": {"vest": [{"id": "mag_556", "count": 3}], "pockets": [], "backpack": []}, "hands": ""}}
## Voxel edits in the same save: an impact mark on the main building's concrete and a bullet
## hole in the shed's plank wall (voxel coordinates), which the late joiner gets in the log.
const SAVED_EDITS := [{"op": "mark", "p": [-29.5, 13.5, -40.0], "n": [0.0, 0.0, 1.0], "m": 2},
	{"op": "holes", "v": [175, 13, -71]}]
## Where the host marks the perimeter wall's inner face once the client is in (live, by RPC).
const LIVE_MARK := Vector3(6.0, 1.2, 19.7)

## Two AI the host stages before the client joins: one dragging the other (_stage_drag).
const DRAGGER := "Dragger"
const DRAGGED := "Dragged"

var failures := 0
var level: CompoundLevel


func _ready() -> void:
	GameState.zone_id = "test_net" + OS.get_environment("CONTRACTOR_TEST_TAG")
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	if "--join" in OS.get_cmdline_user_args():
		Roles.local_choice = Roles.MARKSMAN  # the client's pick in the main menu, sent on join
	else:
		_write_save_with_body()
	add_child(load("res://scenes/main.tscn").instantiate())  # main reads --host/--join
	await get_tree().process_frame
	level = CompoundLevel.current(self)
	if Net.is_hosting():
		Net.peer_joined.connect(_give_kit)
		Net.peer_left.connect(_on_client_left)
		get_tree().create_timer(60.0).timeout.connect(func() -> void: get_tree().quit(1))
		_stage_drag()
	else:
		_run_client()


## Host: the client left while down (it knocks itself out first), so its body stays behind
## with its gear. The host's exit code says whether it did (run_tests.sh checks it).
func _on_client_left(id: int) -> void:
	await get_tree().process_frame
	var left := level.bodies.get_children().filter(func(b: Node) -> bool:
		return b is Soldier and (b as Soldier).display_name() == "Player %d" % id and (b as Soldier).vitals.is_dead() \
			and (b as Soldier).inventory.slots[&"primary"] == &"m4a1")
	print("[host] peer %d left while down: %s" % [id, "its body stayed, gear and all" if left.size() == 1 else "NO BODY"])
	get_tree().quit(0 if left.size() == 1 else 1)


## Host: a zone save holding one body (SAVED_BODY), loaded when hosting starts.
func _write_save_with_body() -> void:
	DirAccess.make_dir_recursive_absolute(GameState.SAVE_DIR)
	var file := FileAccess.open(GameState.save_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": GameState.SAVE_VERSION, "looted": [], "dropped": {}, "voxel_edits": SAVED_EDITS, "bodies": [SAVED_BODY]}))
	file.close()


## Host, before anyone joins: an AI drags a downed one (DRAGGER, DRAGGED), so the late
## joiner has to see the drag from the replicated state alone.
func _stage_drag() -> void:
	while not level.voxel_world.is_built():
		await get_tree().process_frame
	var make := func(callsign: String, pos: Vector3) -> Soldier:
		var s := level.spawn_soldier({"name": callsign, "faction": "hostile", "variant": "woodland", "pos": pos,
			"loadout": ["plate_carrier", "m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
		return s
	var dragger: Soldier = make.call(DRAGGER, Vector3(12, 0.1, 30))
	var dragged: Soldier = make.call(DRAGGED, Vector3(12, 0.1, 31.1))
	await get_tree().create_timer(0.3).timeout
	dragged.vitals.server_damage(500.0)
	print("[host] staged a drag: %s" % dragger.server_pick_up_body(dragged, Soldier.DRAG, INF))


func _give_kit(id: int) -> void:
	await get_tree().create_timer(0.5).timeout  # let the player spawn
	var player: Soldier = level.players.get_node_or_null(str(id))
	for item in KIT:
		player.inventory.take(item)
	player.inventory.take(&"mag_556", 2)
	player.inventory.take(&"ifak")
	player.inventory.take(&"morphine")
	player.vitals.server_damage(40.0)
	# A small fragment wound in the left forearm to treat (and maybe a fracture).
	player.vitals.server_hit(Vitals.FOREARM_L, {"round_class": Vitals.FRAGMENT, "superficial": true})
	level.voxel_world.server_mark(LIVE_MARK, Vector3.FORWARD, VoxelWorld.Mat.CONCRETE)
	print("[host] gave peer %d a kit" % id)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _run_client() -> void:
	var deadline := Time.get_ticks_msec() + 20000
	var me: Soldier
	while Time.get_ticks_msec() < deadline:
		me = level.players.get_node_or_null(str(multiplayer.get_unique_id()))
		if me and me.inventory.slots[&"primary"] == &"m4a1":
			break
		await get_tree().process_frame
	print("Client over ENet")
	check(me != null and me.inventory.slots[&"primary"] == &"m4a1", "kit given by the host replicated to the client")
	if me == null:
		_finish()
		return
	me.set_physics_process(false)
	await _wait_for(func() -> bool: return me.role == Roles.MARKSMAN, 3.0)
	check(me.role == Roles.MARKSMAN and me.fire_team == 1, "the role picked before joining reached the host: marksman, team B (%s, %d)" % [me.role, me.fire_team])
	await _check_late_drag()
	var gear: GearRig = me.get_node(^"Gear")
	check(gear.armor_integrity(&"plate_front") == 1.0 and gear.armor_integrity(&"helmet") == 1.0, "client built the worn voxel armor")
	for i in 3:
		me._server_fire.rpc_id(1, me.head.global_position, -me.global_basis.z, &"primary")
		await get_tree().create_timer(0.15).timeout
	await _wait_for(func() -> bool: return me.inventory.rounds_in(&"primary") == 27, 3.0)
	check(me.inventory.rounds_in(&"primary") == 27, "3 shots: host's ammo count replicated back (27)")
	me._server_reload.rpc_id(1, &"primary")
	await _wait_for(func() -> bool: return me.inventory.rounds_in(&"primary") == 30, 5.0)
	check(me.inventory.rounds_in(&"primary") == 30 and me.inventory.spare_rounds(&"mag_556") == 57, "reload over the network (30 loaded, 57 spare)")
	# The host's K-style trauma (40): 24% of blood lost and 0.4 pain, plus a fragment wound in
	# the left forearm, replicated in net_state.
	await _wait_for(func() -> bool: return me.vitals.pain() > 0.45, 3.0)
	var wounds := me.vitals.wound_list()
	check(absf(me.vitals.blood_fraction() - 0.76) < 0.02 and me.vitals.pain() > 0.45 and me.vitals.is_up() and me.vitals.condition_text() == "Bleeding"
		and not wounds.is_empty() and wounds[0].part == Vitals.FOREARM_L and wounds[0].kind == "muscle" and wounds[0].bleeding,
		"wound-model state replicated to the client (blood %.0f%%, pain %.2f, %s, %s)" % [me.vitals.blood_fraction() * 100.0, me.vitals.pain(), me.vitals.condition_text(), wounds])
	var tasks := me.vitals.care_needed()
	check(not tasks.is_empty() and tasks[0].item == &"pressure_bandage" and me.inventory.medical_count(&"pressure_bandage") == 2,
		"the client reads what it needs (%s) and that its IFAK holds 2 bandages" % [tasks])
	if not tasks.is_empty():
		me._server_treat.rpc_id(1, me.get_path(), tasks[0].item, tasks[0].part)  # rushed left at its default
		await _wait_for(func() -> bool: return me.vitals.is_healing(), 2.0)
		check(me.vitals.is_healing(), "the host started the treatment (replicated)")
		check(me.model.action_shown() == CharacterModel.TREAT, "and its animation: hands at the wound (replicated action_net)")
		await _wait_for(func() -> bool: return me.vitals.wound_list()[0].treated, 8.0)
		check(me.vitals.wound_list()[0].treated and not me.vitals.wound_list()[0].bleeding and not me.vitals.is_healing(), "a remote treatment through the host: bandaged after 5 s")
		await _wait_for(func() -> bool: return me.inventory.medical_count(&"pressure_bandage") == 1, 2.0)
		check(me.inventory.medical_count(&"pressure_bandage") == 1 and me.inventory.count_of(&"ifak") == 1, "drawn from the IFAK, which stays with one bandage left")
	# The medical model's hidden values reach the client too, so its checks and cues match.
	me._server_treat.rpc_id(1, me.get_path(), &"morphine", Vitals.TORSO)
	await _wait_for(func() -> bool: return me.vitals.morphine_level() > 0.2, 12.0)
	check(me.vitals.morphine_level() > 0.2 and me.inventory.count_of(&"morphine") == 0, "a morphine dose: the level in the blood replicates (%.2f)" % me.vitals.morphine_level())
	check(me.vitals.spo2() < WoundModel.SPO2_NORMAL and me.vitals.spo2() > WoundModel.SPO2_LABOURED and me.vitals.trauma_level() > 0.0 and me.vitals.why_unconscious().is_empty(),
		"SpO2 (%.1f%%, down a little with 24%% lost) and trauma (%.2f) replicate" % [me.vitals.spo2(), me.vitals.trauma_level()])
	me._server_inventory_action.rpc_id(1, "drop_slot", &"", -1, &"helmet", &"")
	await _wait_for(func() -> bool: return me.inventory.slots[&"helmet"] == &"", 3.0)
	await _wait_for(func() -> bool: return _dropped_helmet() != null, 3.0)
	check(_dropped_helmet() != null, "dropped helmet spawned on the client")
	await _shoot_dropped_helmet(me)
	await _check_saved_body(me)
	await _check_world_edits()
	# Knocked out, then gone: the host keeps this player's body (see _on_client_left).
	me._server_debug_hurt.rpc_id(1, 140.0)
	await _wait_for(func() -> bool: return me.vitals.downed, 3.0)
	check(me.vitals.downed, "knocked out before leaving (%s)" % me.vitals.condition_text())
	_finish()


## The body from the host's zone save, seen by this late joiner, and looted over the network.
func _check_saved_body(me: Soldier) -> void:
	await _wait_for(func() -> bool: return level.bodies.get_child_count() > 0 and (level.bodies.get_child(0) as Soldier).inventory.slots[&"vest"] != &"", 3.0)
	var body: Soldier = level.bodies.get_child(0) if level.bodies.get_child_count() > 0 else null
	check(body != null and body.display_name() == "Player 9" and body.vitals.is_dead() and body.inventory.slots[&"vest"] == &"plate_carrier"
		and body.inventory.rounds_in(&"primary") == 21 and body.inventory.count_of(&"mag_556") == 3,
		"a body in the zone save is there for a late joiner, dead, with its gear (%s)" % [body.inventory.net_state if body else "none"])
	if body == null:
		return
	var marker := body.get_children().filter(func(n: Node) -> bool: return n is GearMarker)
	check(body.collision_layer == 0 and body.global_position.distance_to(Vector3(0, 0.1, 26.5)) < 0.5 and marker.size() == 1,
		"lying where it was saved, with its gear marker")
	me.global_position = body.global_position + Vector3(1.0, 0.0, 0.0)
	await get_tree().create_timer(0.4).timeout  # the host sees us there
	var mags := me.inventory.count_of(&"mag_556")
	me._server_loot_item.rpc_id(1, body.get_path(), &"vest", 0, &"mag_556")
	await _wait_for(func() -> bool: return body.inventory.count_of(&"mag_556") == 0, 3.0)
	check(body.inventory.count_of(&"mag_556") == 0 and me.inventory.count_of(&"mag_556") == mags + 3,
		"looting its magazines over the network moves them onto the looter (%d -> %d)" % [mags, me.inventory.count_of(&"mag_556")])


## Armor on the ground is a target: a round the host resolves against the dropped helmet
## damages it, and the damage reaches this client's copy.
func _shoot_dropped_helmet(me: Soldier) -> void:
	var helmet := _dropped_helmet()
	if helmet == null:
		return
	await get_tree().create_timer(1.0).timeout  # settled on the host, synced here
	for attempt in 3:
		var eye := me.head.global_position
		me._server_fire.rpc_id(1, eye, (helmet.global_position - eye).normalized(), &"primary")
		await _wait_for(func() -> bool: return not helmet.state.get("chips", []).is_empty(), 1.0)
		if not helmet.state.get("chips", []).is_empty():
			break
	var piece: VoxelArmor = helmet.find_children("*", "VoxelArmor", false, false).front()
	check(helmet.state.get("chips", []).size() == 1 and piece and piece.voxels_removed() > 0,
		"a round into the dropped helmet damages it, and the client sees it (%d voxels)" % (piece.voxels_removed() if piece else -1))


## Impact marks and bullet holes reach the client: the saved ones in the edit log sent on
## join, the live one by RPC.
func _check_world_edits() -> void:
	var world := level.voxel_world
	var saved := Vector3(-2.95, 1.35, -4.0)
	await _wait_for(func() -> bool: return world.is_built() and world.marks_near(saved, 0.05) >= 1 and world.marks_near(LIVE_MARK, 0.05) >= 1, 10.0)
	# (The three shots fired earlier marked the perimeter wall too.)
	check(world.marks_near(saved, 0.05) == 1 and world.marks_near(LIVE_MARK, 0.05) == 1,
		"impact marks replicate: the saved one on the building and the host's live one (%d marks in all)" % world.mark_count())
	check(world.material_at(Vector3(17.55, 1.35, -7.05)) == VoxelWorld.Mat.EMPTY and world.material_at(Vector3(17.65, 1.35, -7.05)) == VoxelWorld.Mat.WOOD,
		"and the saved bullet hole in the shed wall")


## The drag the host staged before this client joined shows here: both poses from the
## replicated carry_net (the host-only carried_by and carrying never reach a client).
func _check_late_drag() -> void:
	var find := func(callsign: String) -> Soldier:
		for node in get_tree().get_nodes_in_group(&"combatants"):
			if node is Soldier and String(node.name) == callsign:
				return node
		return null
	await _wait_for(func() -> bool:
		var d: Soldier = find.call(DRAGGED)
		return d != null and d.model.carry_shown().get("mode") == CharacterModel.DRAGGED, 3.0)
	var dragger: Soldier = find.call(DRAGGER)
	var dragged: Soldier = find.call(DRAGGED)
	check(dragger != null and dragged != null and dragger.model.carry_net.get("mode") == CharacterModel.DRAG
		and dragged.model.carry_shown().get("mode") == CharacterModel.DRAGGED and dragged.carried_by == null,
		"a late joiner sees a drag that started before it joined, from replicated state alone")
	if dragger == null or dragged == null:
		return
	await get_tree().create_timer(0.6).timeout
	var strap := dragged.model.torso.to_global(CharacterModel.STRAP_POINTS[0])
	check(dragger.model.hand_position(true).distance_to(strap) < 0.08 and dragged.model.torso.global_basis.z.dot(Vector3.UP) < -0.6,
		"drawn on the client: the casualty on its back, the dragger's hands on its straps")


func _dropped_helmet() -> WorldItem:
	for node in get_tree().get_nodes_in_group(&"world_items"):
		if node.item_id == &"helmet" and node.uid.begins_with("test_net"):
			return node
	return null


func _wait_for(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _finish() -> void:
	print("NET TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	Net.leave()
	get_tree().quit(failures)
