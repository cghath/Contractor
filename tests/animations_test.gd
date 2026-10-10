extends Node
## Headless checks for the action animations (CharacterModel "Actions", GearRig draws):
## poses come from replicated state (carry_net, action_net) and nothing host-only; hands
## reach their targets (items, mounts, straps, wounds, bodies); a casualty is draped over the
## carrier's shoulders or dragged on its back, head first, and its hitboxes follow; the
## carrier's camera stays clear of it; the first-person view model lowers; AI bodies and
## dummies keep working.
##   <voxel godot exe> --headless --path . res://tests/animations_test.tscn
## Exits with the number of failures.

const SPOT := Vector3(0, 0.1, 20)
## How close a palm must get to its target (metres).
const HAND_TOLERANCE := 0.06

var failures := 0
var level: CompoundLevel
var player: Soldier
var alpha: Soldier    # friendly AI: the casualty
var bravo: Soldier    # friendly AI: carries
var hostile: Soldier  # becomes a dead body to loot


func _ready() -> void:
	GameState.zone_id = "test_animations" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		print("ANIMATIONS TEST FAILED (timed out)")
		get_tree().quit(99))
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we place the player by hand
	_place_player()
	player.inventory.strip()
	for id: StringName in [&"plate_carrier", &"assault_pack", &"m4a1", &"m17"]:
		player.inventory.take(id)
	player.inventory.take(&"mag_556", 2)
	player.inventory.take(&"pressure_bandage", 3)
	alpha = _spawn_ai("Alpha", &"friendly", SPOT + Vector3(0, 0, -1.5), ["plate_carrier", "plate_steel_l3", "m4a1", "assault_pack"])
	bravo = _spawn_ai("Bravo", &"friendly", SPOT + Vector3(3.0, 0, 0), ["plate_carrier", "m4a1"])
	hostile = _spawn_ai("Hostile", &"hostile", SPOT + Vector3(-3.0, 0, 1.0), ["plate_carrier", "m4a1", "mag_556"])
	await _frames(10)
	_test_replication_config()
	await _test_carry()
	await _test_drag()
	await _test_put_down()
	await _test_from_replicated_state()
	await _test_human_casualty()
	await _test_ai_carry()
	await _test_pick_up()
	await _test_equip_and_draw()
	await _test_treat()
	await _test_loot()
	await _test_dummy()
	GameState.delete_save()
	print("ANIMATIONS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _test_replication_config() -> void:
	print("Replication")
	var soldier: Node = load("res://scenes/soldier.tscn").instantiate()
	var config: SceneReplicationConfig = soldier.get_node(^"ServerSync").replication_config
	for prop: NodePath in [^"Model:carry_net", ^"Model:action_net"]:
		check(config.has_property(prop) and config.property_get_spawn(prop)
			and config.property_get_replication_mode(prop) == SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE,
			"%s replicates from the host on change, and to late joiners on spawn" % prop)
	soldier.free()


# --- Carry and drag -------------------------------------------------------------------------

func _test_carry() -> void:
	print("Fireman's carry")
	_down(alpha)
	alpha.global_position = SPOT + Vector3(0, 0, -1.5)
	await _frames(2)
	player._server_carry_body.rpc_id(1, alpha.get_path())
	check(player.carrying == alpha and player.model.carry_net.get("mode") == CharacterModel.CARRY
		and player.model.carry_net.get("with") == String(alpha.get_path()), "the carrier's carry_net: carrying Alpha")
	check(alpha.model.carry_net.get("mode") == CharacterModel.CARRIED and alpha.model.carry_net.get("with") == String(player.get_path()),
		"the casualty's carry_net: carried by the player")
	await _seconds(0.7)
	check(alpha.model.carry_shown().get("mode") == CharacterModel.CARRIED and player.model.carry_shown().get("mode") == CharacterModel.CARRY,
		"both models show the carry")
	var hips := player.model.torso.to_global(CharacterModel.CARRY_HIPS)
	check(alpha.model.torso.global_position.distance_to(hips) < 0.05,
		"the casualty's hips rest across the carrier's shoulders (%.2f m off)" % alpha.model.torso.global_position.distance_to(hips))
	var pelvis := _part(alpha, Vitals.PELVIS)
	var head := _part(alpha, Vitals.HEAD)
	var shin := _part(alpha, Vitals.SHIN_R)
	check(pelvis.y > player.global_position.y + 1.35, "carried high, over the shoulders (pelvis %.2f m up)" % (pelvis.y - player.global_position.y))
	check(head.y < pelvis.y - 0.25 and shin.y < pelvis.y - 0.25,
		"limp and draped, not a plank: head %.2f m and shins %.2f m below the hips" % [pelvis.y - head.y, pelvis.y - shin.y])
	var side_head := player.to_local(head).x
	var side_shin := player.to_local(shin).x
	check(side_head < -0.2 and side_shin > 0.2, "head and arms down the carrier's left, legs down the right (%.2f, %.2f)" % [side_head, side_shin])
	for i in 2:
		var target := player.model.torso.to_global(CharacterModel.CARRY_HANDS[i])
		var off := player.model.hand_position(i == 0).distance_to(target)
		check(off < HAND_TOLERANCE, "carrier's %s hand holds the casualty (%.1f cm off)" % ["right" if i == 0 else "left", off * 100.0])
	check(alpha.model.hand_position(true).y < _part(alpha, Vitals.UPPER_ARM_R).y - 0.2, "the casualty's arms hang down")
	check(player.model.hand_error() < 0.0 and player.model.hands_busy(), "the rifle is slung: both hands are on the casualty")
	check(is_equal_approx(player.model.view_lower(), 1.0), "first person: the view model is lowered")
	_check_camera_clear(player, alpha, "carrying")


func _test_drag() -> void:
	print("Drag")
	player._server_drag_body.rpc_id(1, alpha.get_path())
	check(player.model.carry_net.get("mode") == CharacterModel.DRAG and alpha.model.carry_net.get("mode") == CharacterModel.DRAGGED,
		"switching to a drag updates both sides")
	player.global_position += Vector3(0, 0, -1.0)
	await _seconds(0.7)
	var back := alpha.model.torso.global_basis.z  # the casualty's back
	check(back.dot(Vector3.UP) < -0.6, "the casualty lies on its back (back faces %.2f up)" % back.dot(Vector3.UP))
	var head := _part(alpha, Vitals.HEAD)
	var pelvis := _part(alpha, Vitals.PELVIS)
	check(_flat(head, player.global_position) < _flat(pelvis, player.global_position) - 0.3, "head first, towards the dragger")
	var behind := player.to_local(pelvis).z
	check(behind > 0.8, "the casualty is behind the dragger's direction of travel (%.2f m)" % behind)
	check(pelvis.y - player.global_position.y < 0.4 and head.y > pelvis.y, "the hips on the ground, the shoulders lifted by the collar")
	for i in 2:
		var hand := alpha.model.hand_position(i == 0)
		var shoulder := _part(alpha, Vitals.UPPER_ARM_R if i == 0 else Vitals.UPPER_ARM_L)
		check(_flat(hand, player.global_position) > _flat(shoulder, player.global_position) and hand.y < shoulder.y,
			"its %s arm trails along the ground" % ["right" if i == 0 else "left"])
	var dragger_head := player.to_local(_part(player, Vitals.HEAD))
	check(dragger_head.z > 0.2 and dragger_head.y < 1.3, "the dragger is bent at the hips towards the casualty, facing it (head at %s)" % dragger_head)
	for i in 2:
		var strap := alpha.model.torso.to_global(CharacterModel.STRAP_POINTS[i])
		var off := player.model.hand_position(i == 0).distance_to(strap)
		check(off < HAND_TOLERANCE, "dragger's %s hand on the casualty's shoulder strap (%.1f cm off)" % ["right" if i == 0 else "left", off * 100.0])
	_check_camera_clear(player, alpha, "dragging")


func _test_put_down() -> void:
	print("Put down")
	player._server_release_body.rpc_id(1)
	check(player.model.carry_net.is_empty() and alpha.model.carry_net.is_empty(), "letting go clears both sides")
	await _seconds(0.6)
	check(alpha.model.transform.is_equal_approx(Transform3D.IDENTITY) and alpha.model.carry_shown().is_empty() and alpha.model.downed,
		"the casualty lies where its own body is again")
	check(not player.model.hands_busy() and is_equal_approx(player.model.view_lower(), 0.0), "the carrier's hands are free")
	await _seconds(0.5)
	check(player.model.hand_error() >= 0.0 and player.model.hand_error() < 0.02, "and the rifle is drawn again (%.3f)" % player.model.hand_error())


## A peer only has the replicated state (no carried_by, carrying or carry_mode, which are
## host-only): the poses must follow carry_net alone.
func _test_from_replicated_state() -> void:
	print("Poses from replicated state only")
	_down(hostile)
	hostile.global_position = bravo.global_position + Vector3(0, 0, 1.1)
	await _frames(2)
	check(hostile.carried_by == null and bravo.carrying == null and bravo.carry_mode == &"", "no host-side carry at all")
	bravo.model.carry_net = {"mode": CharacterModel.DRAG, "with": String(hostile.get_path())}
	hostile.model.carry_net = {"mode": CharacterModel.DRAGGED, "with": String(bravo.get_path())}
	await _seconds(0.7)
	var strap := hostile.model.torso.to_global(CharacterModel.STRAP_POINTS[0])
	check(hostile.model.carry_shown().get("mode") == CharacterModel.DRAGGED and bravo.model.hand_position(true).distance_to(strap) < HAND_TOLERANCE,
		"as a late joiner gets it: the drag shows from carry_net alone")
	check(_flat(_part(hostile, Vitals.HEAD), bravo.global_position) < _flat(_part(hostile, Vitals.PELVIS), bravo.global_position),
		"with the casualty head first to the dragger")
	hostile.model.carry_net = {}
	bravo.model.carry_net = {}
	hostile.vitals.server_reset_health()
	await _seconds(0.5)
	check(hostile.model.transform.is_equal_approx(Transform3D.IDENTITY) and not hostile.model.downed, "cleared, both stand again")


func _test_human_casualty() -> void:
	print("Human casualty")
	_down(player)
	bravo.global_position = player.global_position + Vector3(1.5, 0, 0)
	await _frames(2)
	bravo._server_carry_body.rpc_id(1, player.get_path())
	check(player.model.carry_net.get("mode") == CharacterModel.CARRIED and bravo.model.carry_net.get("mode") == CharacterModel.CARRY,
		"a downed player carried by an AI squadmate")
	await _seconds(0.7)
	# The player's own body isn't moved here (their machine does that): the drawn body
	# still rides on Bravo, because it follows the carrier, not its own replicated transform.
	var hips := bravo.model.torso.to_global(CharacterModel.CARRY_HIPS)
	check(player.model.torso.global_position.distance_to(hips) < 0.05, "drawn over Bravo's shoulders wherever its own body is")
	bravo._server_drag_body.rpc_id(1, player.get_path())
	await _seconds(0.7)
	var strap := player.model.torso.to_global(CharacterModel.STRAP_POINTS[1])
	check(bravo.model.hand_position(false).distance_to(strap) < HAND_TOLERANCE, "and dragged by the strap")
	bravo._server_release_body.rpc_id(1)
	player.vitals.server_reset_health()
	player.carried_by_pos = null
	_place_player()
	await _seconds(0.5)
	check(player.model.carry_net.is_empty() and player.model.transform.is_equal_approx(Transform3D.IDENTITY), "put down, and up again")


func _test_ai_carry() -> void:
	print("AI casualty care")
	alpha.global_position = bravo.global_position + Vector3(0.0, 0, -1.0)
	await _frames(2)
	check(bravo.server_pick_up_body(alpha, Soldier.CARRY) and bravo.model.carry_net.get("mode") == CharacterModel.CARRY
		and alpha.model.carry_net.get("mode") == CharacterModel.CARRIED, "AI care (server_pick_up_body) sets the same state")
	bravo._set_carry_mode(Soldier.DRAG)
	check(bravo.model.carry_net.get("mode") == CharacterModel.DRAG and alpha.model.carry_net.get("mode") == CharacterModel.DRAGGED,
		"switching to a drag the way squad AI does")
	bravo.global_position += Vector3(0, 0, -0.5)
	await _seconds(0.7)
	check(bravo.model.hand_position(true).distance_to(alpha.model.torso.to_global(CharacterModel.STRAP_POINTS[0])) < HAND_TOLERANCE,
		"the AI drags by the strap too")
	alpha.vitals.server_reset_health()
	await _frames(3)
	check(bravo.carrying == null and bravo.model.carry_net.is_empty() and alpha.model.carry_net.is_empty(),
		"a casualty who comes round is let go, and both poses clear")
	_place(alpha, SPOT + Vector3(0, 0, -1.5))
	_place(bravo, SPOT + Vector3(3.0, 0, 0))


# --- Hands ----------------------------------------------------------------------------------

func _test_pick_up() -> void:
	print("Pick up")
	_place_player()
	await _seconds(0.6)
	var item := await _spawn_item(&"mag_556", player.global_position + Vector3(0.1, 0.3, -0.5))
	await _seconds(0.5)  # settles on the ground
	check(item != null, "a magazine on the ground in front")
	if item == null:
		return
	var rest_low := player.model.torso.global_position.y
	player._server_interact.rpc_id(1, item.get_path())
	var at: Vector3 = player.model.action_net.get("at", Vector3.INF)
	check(player.model.action_net.get("id") == CharacterModel.PICK_UP and player.model.action_net.get("to") == &"pouch",
		"the host starts a pickup that ends in a pouch")
	check(at.distance_to(player.to_local(item.global_position)) < 0.05, "aimed at the item (%s)" % at)
	var seen := {"best": INF, "low": rest_low, "lower": 0.0, "view": player.view_model.position.y}
	await _watch(CharacterModel.PICK_UP_S, func() -> void:
		seen.best = minf(seen.best, player.model.hand_position(true).distance_to(player.to_global(at)))
		seen.low = minf(seen.low, player.model.torso.global_position.y)
		seen.lower = maxf(seen.lower, player.model.view_lower())
		seen.view = minf(seen.view, player.view_model.position.y))
	check(seen.best < HAND_TOLERANCE, "the hand reaches the item (%.1f cm)" % (seen.best * 100.0))
	check(rest_low - seen.low > 0.25, "bending or kneeling to reach it (hips %.2f m lower)" % (rest_low - seen.low))
	check(seen.lower > 0.8 and seen.view < PlayerInput.HIP_VIEW.y - 0.08, "first person: the view model ducks (%.2f)" % seen.view)
	await _seconds(0.6)
	check(player.model.action_net.is_empty() and player.model.action_shown() == &"", "the host clears the finished clip (nothing for late joiners to replay)")
	check(absf(player.model.torso.global_position.y - rest_low) < 0.03, "and stands back up")


func _test_equip_and_draw() -> void:
	print("Equip, stow and draw")
	var gear: GearRig = player.gear
	await _seconds(0.5)
	player._server_inventory_action.rpc_id(1, "stow_slot", &"", -1, &"sidearm", &"")
	check(player.model.action_net.get("id") == CharacterModel.EQUIP and player.model.action_net.get("from") == &"holster",
		"stowing the pistol: from the holster (%s)" % player.model.action_net)
	await _check_mount_path(player.model.action_net.get("from"), player.model.action_net.get("to"))
	var where := _entry_of(player, &"m17")
	check(not where.is_empty(), "the pistol went into %s" % where.get("container", "nothing"))
	if where.is_empty():
		return
	await _seconds(0.4)
	player._server_inventory_action.rpc_id(1, "equip_entry", where.container, where.index, &"", &"")
	check(player.model.action_net.get("from") == CharacterModel.CONTAINER_MOUNTS[where.container] and player.model.action_net.get("to") == &"holster",
		"equipping it: from the %s to the holster" % where.container)
	await _check_mount_path(player.model.action_net.get("from"), player.model.action_net.get("to"))
	await _seconds(0.5)
	check(player.inventory.slots[&"sidearm"] == &"m17", "the pistol is back in its holster")
	# Switching weapons (replicated active_slot): the hand fetches the pistol first.
	var grip := player.model.torso.to_global(gear._rest_grip(&"sidearm"))
	player.select_weapon(&"sidearm")
	var seen := {"best": INF, "drawing": false}
	await _watch(CharacterModel.DRAW_S, func() -> void:
		seen.drawing = seen.drawing or gear.drawing()
		seen.best = minf(seen.best, player.model.hand_position(true).distance_to(player.model.torso.to_global(gear._rest_grip(&"sidearm")))))
	check(seen.drawing and seen.best < HAND_TOLERANCE, "drawing the pistol: the hand goes to the holster first (%.1f cm)" % (seen.best * 100.0))
	await _seconds(0.3)
	var error := player.model.hand_error()
	check(error >= 0.0 and error < 0.015 and grip.distance_to(player.model.hand_position(true)) > 0.1, "then holds it up (%.1f cm)" % (error * 100.0))
	player.select_weapon(&"primary")
	await _seconds(0.6)


func _test_treat() -> void:
	print("Treating")
	_down(alpha)
	alpha.vitals.server_hit(Vitals.FOREARM_L, {"round_class": Vitals.FRAGMENT, "superficial": true})
	_place(alpha, SPOT + Vector3(0, 0, -1.5))
	_place_player()
	await _seconds(0.3)
	var task := _task_with(alpha, &"pressure_bandage")
	if not task.is_empty():
		_beside(CharacterModel.part_position(alpha, task.part))  # kneel within reach of the wound
	await _seconds(0.5)
	check(not task.is_empty() and not alpha.vitals.is_dead(), "Alpha is down with a wound to bandage (%s)" % [alpha.vitals.care_needed()])
	if task.is_empty():
		return
	var rest_y := player.model.torso.global_position.y
	player._server_treat.rpc_id(1, alpha.get_path(), &"pressure_bandage", task.part)
	check(player.model.action_net.get("id") == CharacterModel.TREAT and player.model.action_net.get("kneel") == true, "treating another: kneeling (replicated)")
	await _seconds(0.8)
	var wound := CharacterModel.part_position(alpha, task.part)
	var at: Vector3 = player.to_global(player.model.action_net.get("at", Vector3.ZERO))
	var hands := (player.model.hand_position(true) + player.model.hand_position(false)) * 0.5
	check(player.model.action_shown() == CharacterModel.TREAT and rest_y - player.model.torso.global_position.y > 0.25,
		"kneeling beside the casualty (hips %.2f m lower)" % (rest_y - player.model.torso.global_position.y))
	check(hands.distance_to(at) < 0.08 and at.distance_to(wound) < 0.35, "hands working at the wound (%.1f cm from the target, %.1f cm from the wound)"
		% [hands.distance_to(at) * 100.0, at.distance_to(wound) * 100.0])
	check(player.model.hand_error() < 0.0, "the rifle slung meanwhile")
	var done := await _wait(func() -> bool: return player.model.action_net.is_empty(), 8.0)
	check(done and not player.model.hands_busy(), "the clip ends with the treatment")
	# Yourself, standing: no kneel, hands at your own wound.
	player.vitals.server_hit(Vitals.FOREARM_L, {"round_class": Vitals.FRAGMENT, "superficial": true})
	await _seconds(0.3)
	player._server_use_medical.rpc_id(1)
	check(player.model.action_net.get("id") == CharacterModel.TREAT and player.model.action_net.get("kneel") == false, "treating yourself (no kneel)")
	await _seconds(0.8)
	var own := CharacterModel.part_position(player, Vitals.FOREARM_L)
	var own_at: Vector3 = player.to_global(player.model.action_net.get("at", Vector3.ZERO))
	hands = (player.model.hand_position(true) + player.model.hand_position(false)) * 0.5
	check(hands.distance_to(own_at) < 0.1 and own_at.distance_to(own) < 0.3, "hands at your own wound (%.1f cm)" % (hands.distance_to(own_at) * 100.0))
	player.global_position += Vector3(0, 0, 2.0)  # moving interrupts it
	var stopped := await _wait(func() -> bool: return player.model.action_net.is_empty(), 1.0)
	check(stopped, "an interrupted treatment stops the clip")
	_place_player()
	player.vitals.server_reset_health()
	alpha.vitals.server_reset_health()


func _test_loot() -> void:
	print("Looting")
	hostile.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.INTERMEDIATE})
	await _frames(3)
	check(hostile.vitals.is_dead(), "a dead body with gear")
	_place(hostile, SPOT + Vector3(-1.0, 0, -0.8))
	_place_player()
	await _seconds(0.3)
	_beside(hostile.aim_point())
	await _seconds(0.5)
	var rest_y := player.model.torso.global_position.y
	var index := _entry_of(hostile, &"mag_556")
	player._server_loot_item.rpc_id(1, hostile.get_path(), index.get("container", &"vest"), int(index.get("index", 0)), &"mag_556")
	check(player.model.action_net.get("id") == CharacterModel.LOOT and player.model.action_net.get("kneel") == true, "looting: kneeling at the body")
	var at: Vector3 = player.to_global(player.model.action_net.get("at", Vector3.ZERO))
	var seen := {"best": INF, "low": rest_y}
	await _watch(CharacterModel.LOOT_S * CharacterModel.LOOT_WORK_END, func() -> void:
		seen.best = minf(seen.best, ((player.model.hand_position(true) + player.model.hand_position(false)) * 0.5).distance_to(at))
		seen.low = minf(seen.low, player.model.torso.global_position.y))
	check(seen.best < 0.08 and rest_y - seen.low > 0.25, "hands at the body (%.1f cm), knelt down (%.2f m)" % [seen.best * 100.0, rest_y - seen.low])
	check(at.distance_to(hostile.aim_point()) < 0.3, "at the body's chest (%.1f cm)" % (at.distance_to(hostile.aim_point()) * 100.0))
	await _seconds(1.0)
	check(player.model.action_net.is_empty(), "the clip ends")
	player._server_loot_body.rpc_id(1, hostile.get_path())
	check(player.model.action_net.get("id") == CharacterModel.LOOT and is_equal_approx(float(player.model.action_net.get("s")), CharacterModel.LOOT_ALL_S),
		"Loot all: a longer clip")
	await _seconds(2.0)


func _test_dummy() -> void:
	print("Dummies")
	var dummy: TargetDummy = level.get_node(^"Dummies/LightDummy")
	check(dummy.model.carry_net.is_empty() and dummy.model.action_shown() == &"" and not dummy.model.hands_busy(), "a dummy has no carry or action")
	dummy.vitals.server_damage(500.0)
	await _frames(3)
	check(dummy.model.downed and dummy.model.transform.is_equal_approx(Transform3D.IDENTITY), "and still lies down where it stands")
	dummy.vitals.server_reset_health()


# --- Helpers --------------------------------------------------------------------------------

## The carrier's camera isn't inside any of the casualty's meshes (body parts and gear).
func _check_camera_clear(carrier: Soldier, casualty: Soldier, what: String) -> void:
	var eye := carrier.camera.global_position
	var inside := []
	for node in casualty.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if not visual.is_visible_in_tree():
			continue
		var local := visual.global_transform.affine_inverse() * eye
		var box := visual.get_aabb()
		if box.grow(0.05).has_point(local):
			inside.append(visual.name)
	check(inside.is_empty(), "%s: the camera stays clear of the casualty (inside %s)" % [what, inside])


## The right hand passes through MOUNT_POINTS[from] and then [to] during an equip clip.
func _check_mount_path(from: StringName, to: StringName) -> void:
	var seen := {"from": INF, "to": INF}
	await _watch(CharacterModel.EQUIP_S, func() -> void:
		var hand := player.model.hand_position(true)
		seen.from = minf(seen.from, hand.distance_to(player.model.torso.to_global(CharacterModel.MOUNT_POINTS[from])))
		seen.to = minf(seen.to, hand.distance_to(player.model.torso.to_global(CharacterModel.MOUNT_POINTS[to]))))
	check(seen.from < HAND_TOLERANCE and seen.to < HAND_TOLERANCE,
		"the hand goes to the %s (%.1f cm) and then the %s (%.1f cm)" % [from, seen.from * 100.0, to, seen.to * 100.0])


func _down(s: Soldier) -> void:
	s.vitals.server_damage(500.0)


## Where a body part's hitbox is now.
func _part(s: Soldier, part: StringName) -> Vector3:
	return CharacterModel.part_position(s, part)


func _task_with(s: Soldier, item: StringName) -> Dictionary:
	for task in s.vitals.care_needed():
		if task.item == item:
			return task
	return {}


func _entry_of(s: Soldier, id: StringName) -> Dictionary:
	for container in Inventory.CONTAINERS:
		var list: Array = s.inventory.containers[container]
		for i in list.size():
			if list[i].id == id:
				return {"container": container, "index": i}
	return {}


func _spawn_ai(callsign: String, faction: StringName, pos: Vector3, loadout: Array) -> Soldier:
	var s := level.spawn_soldier({"name": callsign, "faction": String(faction), "variant": "multicam", "pos": pos,
		"loadout": loadout, "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED  # we stage everything by hand
	return s


func _spawn_item(id: StringName, pos: Vector3) -> WorldItem:
	level.server_spawn_dropped(id, 1, pos)
	await _frames(2)
	var best: WorldItem = null
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := node as WorldItem
		if item.item_id == id and not item.is_queued_for_deletion() and (best == null or item.global_position.distance_to(pos) < best.global_position.distance_to(pos)):
			best = item
	return best


func _place_player() -> void:
	_place(player, SPOT)
	player.head.rotation = Vector3.ZERO


## Stands the player half a metre to the side of `point`, facing along the casualty.
func _beside(point: Vector3) -> void:
	_place(player, Vector3(point.x + 0.5, SPOT.y, point.z))


func _place(s: Soldier, pos: Vector3) -> void:
	s.global_position = pos
	s.rotation = Vector3.ZERO
	s.velocity = Vector3.ZERO


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Calls `probe` every frame for `seconds`.
func _watch(seconds: float, probe: Callable) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		probe.call()
		await get_tree().process_frame


func _wait(condition: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() >= end:
			return false
		await get_tree().process_frame
	return true


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
