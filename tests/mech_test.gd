extends Node
## The heavy exo, the HX-1 Assault Frame (ExoMech; Captain 2026-10-16: real ArmorRules plates
## on the suit, entry and exit animations, re-enter a damaged suit left on the ground). On the
## vehicle range, where one stands open with its WG-50 on it, the host's player:
## - can't pick it up or put it on from the inventory, nor carry its gun outside one;
## - climbs in from behind (Climb in): he hits the manual release and the standing suit's back
##   unzips (down the legs too); then he's in it, put where it stood, facing its way, seen inside
##   until it zips shut round him, standing still meanwhile; its gun in his hands, his rifle on its rack;
## - in it: the suit carries 260 kg, he never sprints, jumps, climbs or goes prone, walks at
##   three quarters pace, and holds the gun low and ready at the hip; no vehicle seat takes him;
## - its plates are real AR500 steel armour (Captain, 2026-10-17): an M855 and an AP (RF3) round
##   stop on the RF3 chest plate, an M855 goes through the RF1 belly plate, an M855 stops on the
##   RF2 shin plate while AP and .50 BMG go through it into the leg; each hit is in the
##   suit's own state;
## - climbs out (Climb out): its back opens, the suit is left standing (open) where he was with
##   its damage and its gun, his rifle back in his hands, him a step behind it;
## - the suit left standing still takes rounds on its plates (into its state), and climbing
##   back in brings every chip with it; a disabled suit can be climbed into too;
## - a dead pilot's suit: wearing an LX-3, he can't climb into it (nothing is lost, A2-09);
##   with the frame off, he does, the dead man out of it.
##   <godot> --headless --path . res://tests/mech_test.tscn

var failures := 0
var level: VehicleRange
var main: Node
var player: Soldier
var shooter: StaticBody3D


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_mech" + tag
	Campaign.campaign_id = "test_mech" + tag
	CompoundLevel.spawn_ai = false
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		print("MECH TEST FAILED (timed out)")
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
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 5.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	await _frame()
	ExoFrame.roll_override = NAN
	shooter = StaticBody3D.new()
	add_child(shooter)
	await _run()
	_finish()


func _run() -> void:
	var inv := player.inventory
	var suit_item := ItemDB.get_item(&"exo_mech_heavy")
	var gun := ItemDB.get_item(&"wg50_walker")
	check(suit_item != null and suit_item.name == "HX-1 Assault Frame" and suit_item.slot == ExoMech.SLOT and ExoMech.is_mech(suit_item), "the HX-1 Assault Frame is an exo-slot item")
	check(gun != null and ExoMech.mech_only(gun) and String(gun.stats.ammo) == "belt_50bmg", "its WG-50 is a mech-only .50 cal")
	check(not Prices.for_sale(&"exo_mech_heavy") and not Prices.for_sale(&"wg50_walker"), "neither is sold yet (no price: Captain's call)")
	var suit := _suit()
	check(suit != null, "one stands open on the range")
	if suit == null:
		return
	var pieces := suit.find_children("MechPad_*", "VoxelArmor", true, false)
	check(pieces.size() == ExoFrame.pad_items(suit_item).size() and pieces.size() >= 14, "its plates are real armour pieces (%d)" % pieces.size())
	check(pieces.all(func(p: VoxelArmor) -> bool: return p.camo == "multicam"), "painted in camo")
	check(suit.freeze and absf(angle_difference(suit.global_rotation.y, PI)) < 0.01, "standing, facing the spawn (yaw %.2f)" % suit.global_rotation.y)
	# Not an inventory item.
	inv.take(&"m4a1")
	await _frames(2)
	check(inv.take(&"exo_mech_heavy") == 0 and inv.slots[ExoMech.SLOT] == &"", "it can't be taken into the inventory or put on there")
	inv.unequip(&"primary")
	check(inv.take(&"wg50_walker") == 0 and inv.slots[&"primary"] == &"", "nor its gun carried outside a suit")
	inv.take(&"m4a1")
	await _frames(2)
	# The menu.
	player.global_position = suit.global_position - suit.global_basis.y * ExoMech.PARKED_SIZE.y * 0.5 + suit.global_basis.z * 1.3  # behind it, at the release
	await _frames(2)
	var actions := InteractionMenu.actions_for(player, suit)
	var ids := actions.map(func(a: Dictionary) -> StringName: return a.id)
	check(&"enter_mech" in ids and not &"pick_up" in ids, "the menu offers Climb in, not Pick up (%s)" % [ids])
	check(ExoMech.enter_problem(player, suit) == "", "in reach of it")
	# Climb in.
	var feet := suit.global_position - suit.global_basis.y * ExoMech.PARKED_SIZE.y * 0.5
	var yaw := suit.global_rotation.y
	var parked_shin: VoxelArmor = suit.find_children("MechPad_shin_back_l", "VoxelArmor", true, false)[0]
	var parked_shin_at := parked_shin.transform
	player._server_enter_mech.rpc_id(1, suit.get_path())
	await _frames(3)
	check(player.model.action_shown() == CharacterModel.MECH_RELEASE and ExoMech.transitioning(player) and inv.slots[ExoMech.SLOT] == &"",
		"from behind, he hits the manual release (%s)" % player.model.action_shown())
	check(bool(suit.state.get("open", false)), "and the standing suit's back unzips")
	await _seconds(ExoMech.RELEASE_S * 0.8)
	check(not parked_shin.transform.is_equal_approx(parked_shin_at), "down the legs too")
	await _seconds(ExoMech.RELEASE_S * 0.2 + 0.15)
	check(inv.slots[ExoMech.SLOT] == &"exo_mech_heavy" and _suit() == null, "he climbs in: the suit is worn, gone from the ground")
	check(inv.slots[&"primary"] == &"wg50_walker" and String(inv.state_of(ExoMech.SLOT).get("rack", {}).get("id", "")) == "m4a1",
		"its gun in his hands, his M4 on its rack (%s)" % inv.slots[&"primary"])
	check(player.global_position.distance_to(feet) < 0.05 and absf(angle_difference(player.global_rotation.y, yaw)) < 0.01, "put where it stood, facing its way")
	check(player.model.action_shown() == CharacterModel.MECH_IN and ExoMech.transitioning(player), "climbing in (%s)" % player.model.action_shown())
	var gear := player.get_node(^"Gear") as GearRig
	# The back is the hatch (ExoMech.HATCH): open round him, the legs' backs too, then it zips shut.
	var back: VoxelArmor = gear.pads().get("back_r")
	var shin_back: VoxelArmor = gear.pads().get("shin_back_l")
	var back_at: Transform3D = ExoFrame.pad_items(suit_item).filter(func(p: Dictionary) -> bool: return p.id == "back_r")[0].at
	var shin_back_at: Transform3D = ExoFrame.pad_items(suit_item).filter(func(p: Dictionary) -> bool: return p.id == "shin_back_l")[0].at
	await _frames(2)
	check(back != null and not back.transform.is_equal_approx(back_at) and not shin_back.transform.is_equal_approx(shin_back_at), "its back open round him, down the legs")
	check((player.model.part_node(Vitals.CHEST).get_child(0) as Node3D).visible, "him inside it, seen through the open back")
	check(player._is_busy(), "busy meanwhile")
	await _seconds(ExoMech.ENTER_S + 0.4)
	check(not ExoMech.transitioning(player) and back.transform.is_equal_approx(back_at) and shin_back.transform.is_equal_approx(shin_back_at), "and zipped shut round him once in")
	check(not (player.model.part_node(Vitals.CHEST).get_child(0) as Node3D).visible, "him hidden in it then")
	check(gear.pads().size() == pieces.size() and (gear.pads().values() as Array).all(func(p: VoxelArmor) -> bool: return p.camo == player.model.variant),
		"its %d plates on his body, in his side's camo (%s)" % [gear.pads().size(), player.model.variant])
	check(player.model.find_children(ExoMech.PART_NAME + "*", "", true, false).size() >= 50, "the chassis on his body: pack, actuators, boots, head unit")
	_test_movement()
	await _test_low_ready()
	await _test_plates()
	_test_no_seat()
	var chips_in := inv.chips_in(ExoMech.SLOT, "chest").size()
	# Climb out.
	var self_ids := InteractionMenu.actions_for(player, player).map(func(a: Dictionary) -> StringName: return a.id)
	check(&"exit_mech" in self_ids, "on himself, the menu offers Climb out")
	player._server_inventory_action.rpc_id(1, "stow_slot", &"", -1, ExoMech.SLOT, &"")
	await _frames(2)
	check(inv.slots[ExoMech.SLOT] == &"exo_mech_heavy", "the inventory can't take it off him")
	var at := player.global_position
	var facing := player.global_rotation.y
	player._server_exit_mech.rpc_id(1)
	await _frames(3)
	check(player.model.action_shown() == CharacterModel.MECH_OPEN, "climbing out: the hatch opens")
	await _seconds(ExoMech.OPEN_S * 0.7)
	check(not back.transform.is_equal_approx(back_at), "(its back open)")
	await _seconds(ExoMech.OPEN_S * 0.3 + 0.2)
	suit = _suit()
	check(inv.slots[ExoMech.SLOT] == &"" and suit != null, "out: the suit stands on the ground")
	if suit == null:
		return
	var left_feet := suit.global_position - suit.global_basis.y * ExoMech.PARKED_SIZE.y * 0.5
	check(left_feet.distance_to(at) < 0.05 and absf(angle_difference(suit.global_rotation.y, facing)) < 0.01, "where he stood, facing his way")
	check(inv.slots[&"primary"] == &"m4a1" and String(suit.state.get("gun", {}).get("id", "")) == "wg50_walker", "its gun on it, his M4 back in his hands")
	check(player.global_position.distance_to(at) > ExoMech.STEP_OUT_M - 0.1 and player.model.action_shown() == CharacterModel.MECH_OUT, "he steps down in front of it")
	check((suit.state.get("pads", {}).get("chest", {}).get("chips", []) as Array).size() == chips_in and chips_in >= 2, "its plates keep their damage (%d chips in the chest)" % chips_in)
	await _seconds(ExoMech.OUT_S + 0.3)
	# Shot standing empty.
	var parked_back: VoxelArmor = suit.find_children("MechPad_back_r", "VoxelArmor", true, false)[0]
	var m855 := _m855()
	var back_before := (suit.state.get("pads", {}).get("back_r", {}).get("chips", []) as Array).size()  # (the belly round went on out through it)
	var r := Ballistics.fire(shooter, parked_back.to_global(Vector3(0.03, 0.05, -0.8)), parked_back.global_basis.z, m855)
	await _frames(2)
	check(r.result == "plate" and (suit.state.pads.get("back_r", {}).get("chips", []) as Array).size() == back_before + 1, "standing empty, its plates still stop rounds, into its state (%s, %s)" % [r.result, (suit.state.pads as Dictionary).keys().map(func(k: String) -> String: return "%s:%d" % [k, (suit.state.pads[k].get("chips", []) as Array).size()])])
	# Back in: every chip comes with it.
	player.global_position = left_feet + suit.global_basis.z * 1.2
	await _frames(2)
	player._server_enter_mech.rpc_id(1, suit.get_path())
	await _seconds(ExoMech.RELEASE_S + ExoMech.ENTER_S + 0.4)
	check(inv.slots[ExoMech.SLOT] == &"exo_mech_heavy" and inv.chips_in(ExoMech.SLOT, "chest").size() == chips_in and inv.chips_in(ExoMech.SLOT, "back_r").size() == back_before + 1,
		"climbing back into the damaged suit brings every chip with it")
	# Disabled: climb out, and in again.
	ExoFrame.server_damage(player, 10000.0)
	await _frames(2)
	check(not ExoFrame.working(inv) and absf(player.load_kg - inv.total_mass()) < 0.01, "its actuators shot out, he carries all of it (%.0f kg)" % player.load_kg)
	player._server_exit_mech.rpc_id(1)
	await _seconds(ExoMech.OPEN_S + ExoMech.OUT_S + 0.4)
	suit = _suit()
	check(suit != null and bool(suit.state.get("disabled", false)) and suit.describe().contains("DISABLED"), "left standing disabled (%s)" % (suit.describe() if suit else "none"))
	if suit:
		player.global_position = suit.global_position - suit.global_basis.y * ExoMech.PARKED_SIZE.y * 0.5 + suit.global_basis.z * 1.2
		await _frames(2)
		player._server_enter_mech.rpc_id(1, suit.get_path())
		await _seconds(ExoMech.RELEASE_S + 0.3)
		check(inv.slots[ExoMech.SLOT] == &"exo_mech_heavy", "and a disabled suit can be climbed into too")
	await _seconds(ExoMech.ENTER_S + 0.4)
	await _test_lying()


## Punched out (the manual release on a downed pilot's back): the suit left lying face down, open;
## lying down into it, it zips shut and pushes itself up (Captain, 2026-10-17, AW's punch-out scene).
func _test_lying() -> void:
	var inv := player.inventory
	check(ExoMech.punch_out_problem(player, player).begins_with("Only a downed"), "a pilot who's up isn't punched out")
	var feet := player.global_position
	var yaw := player.global_rotation.y
	ExoMech.server_leave_lying(player)
	await _frames(3)
	var lying: WorldItem = null
	for n: Node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if n is WorldItem and (n as WorldItem).item_id == &"exo_mech_heavy" and bool((n as WorldItem).state.get("prone", false)) 				and ExoMech.parked_feet(n).distance_to(feet) < 0.1:
			lying = n
	check(lying != null and inv.slots[ExoMech.SLOT] == &"" and String(lying.state.get("gun", {}).get("id", "")) == "wg50_walker",
		"punched out: the suit lies where he was, its gun on it, him out of it")
	if lying == null:
		return
	var bones := lying.get_node(^"ParkedSuit/Bones") as Node3D
	check(bones.global_basis.y.normalized().dot(Vector3.UP) < 0.1 and bones.global_basis.z.normalized().dot(Vector3.UP) > 0.9,
		"lying on its front, its back (and the release) up")
	check(ExoMech.parked_point(lying).y < 1.2 and absf(angle_difference(lying.global_rotation.y, yaw)) < 0.01, "the release within reach, low down (%.2f m)" % ExoMech.parked_point(lying).y)
	check(player.global_position.distance_to(feet) > 0.8, "he's beside it")
	# Lie down into it.
	player.global_position = ExoMech.parked_point(lying) - Vector3.UP * ExoMech.parked_point(lying).y + Basis(Vector3.UP, yaw).x * 0.9
	await _frames(2)
	check(ExoMech.enter_problem(player, lying) == "", "beside it, in reach of the release")
	player._server_enter_mech.rpc_id(1, lying.get_path())
	await _frames(3)
	check(player.model.action_shown() == CharacterModel.MECH_RELEASE and bool(player.model.action_net.get("kneel", false)), "down on a knee at the release")
	await _seconds(ExoMech.RELEASE_S + 0.15)
	check(inv.slots[ExoMech.SLOT] == &"exo_mech_heavy" and player.global_position.distance_to(feet) < 0.05, "he's in it, lying where it lay")
	check(player.model.action_shown() == CharacterModel.MECH_RISE and player.model.transform.basis.y.normalized().dot(Vector3.UP) < 0.2,
		"lying face down in it (%s)" % player.model.action_shown())
	await _seconds(ExoMech.RISE_S * 0.7)
	check(player.model.transform.basis.y.normalized().dot(Vector3.UP) > 0.2, "pushing itself up")
	await _seconds(ExoMech.RISE_S * 0.3 + 0.4)
	check(not ExoMech.transitioning(player) and player.model.transform.basis.y.normalized().dot(Vector3.UP) > 0.99, "and up on its feet, shut")
	check(inv.slots[&"primary"] == &"wg50_walker", "its gun back in his hands")
	await _test_take_over()


## A2-09: climbing into a dead pilot's suit while wearing an LX-3 is refused (as climbing into
## a parked one is: take the frame off first) and nothing is lost; with the frame off, he
## climbs in and the suit is his, the dead man out of it.
func _test_take_over() -> void:
	var inv := player.inventory
	var pilot := level.spawn_soldier({"name": "MechPilot", "person_name": "MechPilot", "faction": String(player.faction), "variant": "multicam",
		"pos": level.ground_point(player.global_position + Vector3(5, 0, 0)), "loadout": [], "combat": 0.5, "discipline": 0.5, "guard": true})
	var brain := SquadAI.of(pilot)
	if brain:
		brain.process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(2)
	# The suit off him (its gun with it, his M4 back in his hands) and onto the other man.
	var state := ExoMech._suit_off(player)
	var gun: Dictionary = state.get("gun", {})
	for key: String in ["gun", "yaw", "camo", "open", "prone"]:
		state.erase(key)
	pilot.inventory.put_on(ExoMech.SLOT, &"exo_mech_heavy", state)
	pilot.inventory.put_on(&"primary", StringName(gun.get("id", "wg50_walker")), gun.get("state", {}))
	check(ExoMech.piloting(pilot.inventory) and not ExoMech.piloting(inv) and inv.slots[&"primary"] == &"m4a1", "another man in the suit, him out of it with his M4")
	var suits := _suits_anywhere()
	pilot.vitals.server_kill()
	await _seconds(1.5)  # (his ragdoll settles: reach is to where it lies, Soldier.body_point)
	check(inv.take(&"exo_frame_light") == 1 and inv.slots[ExoMech.SLOT] == &"exo_frame_light", "he puts on an LX-3")
	var at := pilot.body_point()
	player.global_position = Vector3(at.x, player.global_position.y, at.z) + Basis(Vector3.UP, pilot.global_rotation.y).x * -1.2
	await _frames(2)
	check(ExoMech.punch_out_problem(player, pilot) == "", "beside the dead pilot, in reach of the release")
	check(ExoMech.climb_in_body_problem(player, pilot) == "Take off your exo frame first", "wearing the LX-3 he can't climb into the dead man's suit (%s)" % ExoMech.climb_in_body_problem(player, pilot))
	check(InteractionMenu._check(&"mech_pilot_in", player, pilot) == "Take off your exo frame first" and InteractionMenu._check(&"mech_pilot", player, pilot) == "",
		"the menu's Climb in says why; Punch out is still offered")
	player._server_climb_in_body.rpc_id(1, pilot.get_path())
	await _seconds(ExoMech.RELEASE_S + 0.4)
	check(_suits_anywhere() == suits and ExoMech.piloting(pilot.inventory) and inv.slots[ExoMech.SLOT] == &"exo_frame_light",
		"asked anyway, nothing happens: the suit still on the dead man, the LX-3 on him (%d suit(s), was %d)" % [_suits_anywhere(), suits])
	# The frame off, he climbs in.
	var frame := inv.unequip(ExoMech.SLOT)
	check(String(frame.get("id", "")) == "exo_frame_light" and ExoMech.climb_in_body_problem(player, pilot) == "", "the LX-3 off, he can")
	player._server_climb_in_body.rpc_id(1, pilot.get_path())
	await _seconds(ExoMech.RELEASE_S + 0.3)
	check(_suits_anywhere() == suits and ExoMech.piloting(inv) and not ExoMech.piloting(pilot.inventory), "he's in the suit, the dead man out of it (%d suit(s))" % _suits_anywhere())
	check(inv.slots[&"primary"] == &"wg50_walker" and String(inv.state_of(ExoMech.SLOT).get("rack", {}).get("id", "")) == "m4a1",
		"its gun in his hands, his M4 on its rack")
	await _seconds(ExoMech.RISE_S + 0.4)


## How many HX-1s there are: worn by anyone, or left on the ground.
func _suits_anywhere() -> int:
	var n := 0
	for s: Node in get_tree().get_nodes_in_group(&"combatants"):
		if s is Soldier and (s as Soldier).inventory.slots.get(ExoMech.SLOT, &"") == &"exo_mech_heavy":
			n += 1
	for w: Node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if w is WorldItem and (w as WorldItem).item_id == &"exo_mech_heavy" and not w.is_queued_for_deletion():
			n += 1
	return n


func _test_movement() -> void:
	var inv := player.inventory
	var mv := player.movement
	check(absf(inv.total_mass() - player.load_kg - 260.0) < 0.01 or player.load_kg == 0.0, "the suit carries 260 kg of the %.0f kg (legs feel %.1f)" % [inv.total_mass(), player.load_kg])
	check(not mv.can_sprint() and not mv.can_jump() and mv.mantle_reach() == 0.0, "no sprint, jump or climb")
	check(not mv.set_stance(SoldierMovement.Stance.PRONE) and mv.stance != SoldierMovement.Stance.PRONE, "no going prone")
	var bare := SoldierMovement.STANCE_SPEED[mv.stance] * MovementRules.direction_mult(Vector2(0, -1), player.load_kg) * player.load_mult * player.vitals.speed_mult()
	check(absf(mv.top_speed(false, false) / bare - 0.75) < 0.01, "walks at three quarters pace (%.2f of %.2f m/s)" % [mv.top_speed(false, false), bare])


## The gun low and ready at the hip, and up at the shoulder aiming.
func _test_low_ready() -> void:
	await _frames(40)
	var art := VoxelArt.model_for(ItemDB.get_item(&"wg50_walker"))
	var rifle := VoxelArt.model_for(ItemDB.get_item(&"m4a1"))
	var low := GearRig.held_transform(art, false, false)
	var up := GearRig.held_transform(art, true, false)
	var ready := GearRig.held_transform(rifle, false, false)
	var butt := low * VoxelArt.butt_point(art)
	check(art.contains(":walker") and butt.y < (ready * VoxelArt.butt_point(rifle)).y - 0.25, "at the ready the WG-50 rides low at the hip (butt %.2f m below the shoulder)" % -butt.y)
	check((up * VoxelArt.butt_point(art)).y > butt.y + 0.25, "aiming, it comes up to the shoulder")
	var hands := VoxelArt.hand_points(art)
	check(not hands.is_empty() and (hands.grip as Vector3).distance_to(hands.support) > 0.2, "two hands on it: pistol grip and foregrip")


## The plates (AR500 steel): RF3 chest, RF1 belly, RF2 shins, rounds into the pilot through them.
func _test_plates() -> void:
	var inv := player.inventory
	var gear := player.get_node(^"Gear") as GearRig
	var chest: VoxelArmor = gear.pads().get("chest")
	var shin: VoxelArmor = gear.pads().get("shin_r")
	var belly: VoxelArmor = gear.pads().get("abdomen")
	check(ArmorRules.rating(chest.item) == &"RF3" and ArmorRules.material(chest.item) == ArmorRules.STEEL and String(chest.item.stats.get("grade", "")) == "AR500", "chest plate: AR500 steel RF3")
	check(ArmorRules.rating(belly.item) == &"RF1" and ArmorRules.material(belly.item) == ArmorRules.STEEL, "belly plate: steel RF1")
	check(ArmorRules.rating(shin.item) == &"RF2" and ArmorRules.material(shin.item) == ArmorRules.STEEL, "shin plate: steel RF2")
	check((gear.pads().values() as Array).all(func(p: VoxelArmor) -> bool: return p.get_rid() in gear.armor_rids()), "the pilot's own shots skip them")
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.vitals.server_reset_health()
	var m855 := _m855()
	var ap := ItemData.from_dict({"id": "test_mech_ap", "type": "weapon", "stats": {"threat": "RF3", "round_class": String(Vitals.INTERMEDIATE), "damage": 30}})
	var bmg := ItemData.from_dict({"id": "test_mech_bmg", "type": "weapon", "stats": {"round": "50bmg_m33", "damage": 110}})
	var front := Ballistics.fire(shooter, chest.to_global(Vector3(0.06, 0.03, -0.8)), chest.global_basis.z, m855)
	await _frames(2)
	check(front.result == "plate" and inv.chips_in(ExoMech.SLOT, "chest").size() == 1, "an M855 stops on the chest plate (%s)" % front.result)
	var ap_front := Ballistics.fire(shooter, chest.to_global(Vector3(-0.09, -0.04, -0.8)), chest.global_basis.z, ap)
	await _frames(2)
	check(ap_front.result == "plate" and inv.chips_in(ExoMech.SLOT, "chest").size() == 2, "and an AP (RF3) round (%s)" % ap_front.result)
	# (A stop at point blank can still crack a rib, WoundModel.add_impact: blunt trauma, not a hole.)
	check(not player.vitals.wound_list().any(func(w: Dictionary) -> bool: return w.part == Vitals.CHEST and w.get("kind", "") != "rib"), "no wound in the chest behind it")
	var low := Ballistics.fire(shooter, belly.to_global(Vector3(0.04, 0.0, -0.075)), belly.global_basis.z, m855)  # (from just in front: his arms hold the gun across it)
	await _frames(2)
	check(low.result == "body" and inv.chips_in(ExoMech.SLOT, "abdomen").size() == 1, "an M855 (RF2) goes through the RF1 belly plate (%s)" % low.result)
	player.vitals.server_reset_health()
	var side := Ballistics.fire(shooter, shin.to_global(Vector3(0.8, 0.04, 0.0)), -shin.global_basis.x, m855)
	await _frames(2)
	check(side.result == "plate" and inv.chips_in(ExoMech.SLOT, "shin_r").size() == 1, "an M855 stops on the shin plate (%s)" % side.result)
	var through := Ballistics.fire(shooter, shin.to_global(Vector3(0.8, -0.08, 0.0)), -shin.global_basis.x, ap)
	await _frames(2)
	check(through.result == "body" and player.vitals.wound_list().any(func(w: Dictionary) -> bool: return w.part == Vitals.SHIN_R), "an AP round goes through the steel into his leg (%s)" % through.result)
	player.vitals.server_reset_health()
	var fifty := Ballistics.fire(shooter, shin.to_global(Vector3(0.8, 0.1, 0.0)), -shin.global_basis.x, bmg)
	await _frames(2)
	check(fifty.result == "body", ".50 BMG goes through any of it (%s)" % fifty.result)
	check(gear.armor_summary().begins_with("Frame"), "the armour readout leads with the suit (%s)" % gear.armor_summary())
	player.vitals.server_reset_health()


func _m855() -> ItemData:
	return ItemData.from_dict({"id": "test_mech_m855", "type": "weapon", "stats": {"round": "556_m855", "damage": 30}})


func _test_no_seat() -> void:
	var vehicles := get_tree().get_nodes_in_group(&"vehicles")
	check(not vehicles.is_empty() and not (vehicles[0] as Vehicle).server_enter(player), "no vehicle seat takes a heavy exo")


func _suit() -> WorldItem:
	for n: Node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if n is WorldItem and (n as WorldItem).item_id == &"exo_mech_heavy" and not n.is_queued_for_deletion() 				and not bool((n as WorldItem).state.get("prone", false)):  # (the standing one: another lies face down)
			return n
	return null


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _finish() -> void:
	ExoFrame.roll_override = NAN
	GameState.delete_save()
	print("MECH TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	Net.leave()
	get_tree().quit(failures)


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	return condition.call()


func _frame() -> void:
	await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
