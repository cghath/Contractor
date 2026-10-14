extends Node
## Screenshots of "Restock last loadout" and refusals (playtest S2; needs a real window, not
## --headless):
##   <voxel godot exe> --path . --resolution 1600x900 res://tests/restock_shots.tscn -- <output folder>
## A campaign at the base hub: the player's rifleman kit and a squadmate's are written down as
## their loadouts, the player's goes onto the armory floor (four magazines short), then the
## inventory screen before and after "Restock last loadout", a refused magazine (the IFAK pouch
## doesn't take it) with the pouches that do lit up, and the base screen's squad page after
## "Restock squad". Keep the output as an S run (docs/debugging.md).

var out := "res://screenshots/restock"
var level: BaseLevel
var player: Soldier
var _shots := 0


func _ready() -> void:
	preload("res://tests/shot_window.gd").stay_out_of_the_way(self)  # no focus, no cursor capture
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		print("[shots] deadline passed, quitting")
		get_tree().quit(2))  # never idle forever (docs/debugging.md)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	GameState.zone_id = "test_restock_shots"
	Campaign.campaign_id = "test_restock_shots"  # never touch a real save (test_: BaseHub.delete_test_campaign_files)
	BaseHub.delete_test_campaign_files()  # last run's, set aside by new_campaign otherwise
	CompoundLevel.spawn_ai = true
	Roles.local_choice = Roles.RIFLEMAN
	BaseHub.local_profile = "shots"
	BaseHub.new_campaign(77)
	for i in 2:
		var pool := Hiring.pool(BaseHub.hiring(), 1)
		print("[shots] hire: %s" % BaseHub.server_hire(String(pool[0].cid)))
	Campaign.save_campaign()  # prepare_session loads it
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	BaseHub.prepare_session()
	$Main/Menu.host()
	level = CompoundLevel.current(self) as BaseLevel
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	var mids := Roster.ids(BaseHub.roster())
	while mids.any(func(m: String) -> bool: return level.muster_soldier(m) == null):
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.global_position = Vector3(-11.6, 0.1, -9.5)  # in the armory doorway
	# What they deployed in last time: the player a rifleman's kit with a holo, the squad theirs.
	var inv := player.inventory
	inv.net_state = GameState.from_json(Roster.gear_for_kit(Roles.kit(Roles.RIFLEMAN)))
	inv.set_slot_state(&"primary", Optics.with_optic(ItemDB.get_item(&"m4a1"), inv.state_of(&"primary"), &"optic_holo"))
	var main := Roster.main_character(BaseHub.roster(), BaseHub.player_key(1))
	Roster.record_loadout(main, Roster.json_safe(inv.net_state))
	for mid in mids:
		Roster.record_loadout(BaseHub.member(mid), BaseHub.member(mid).get("gear", {}))
		BaseHub.server_pick(mid, true)
	# The player's kit goes onto the armory floor, four magazines short; the squad's into a pile.
	for e: Dictionary in inv.strip():
		var state: Dictionary = e.get("state", {}).duplicate(true)
		for loose: Dictionary in Restock.unpack(state):
			if StringName(String(loose.id)) == &"mag_556":
				loose["count"] = maxi(int(loose.count) - 2, 0)
			if int(loose.count) > 0:
				level.server_spawn_dropped(StringName(String(loose.id)), int(loose.count), _floor(), loose.get("state", {}))
		level.server_spawn_dropped(StringName(e.id), int(e.count), _floor(), state)
	for mid in mids:
		var s := level.muster_soldier(mid)
		for e: Dictionary in s.inventory.strip():
			level.server_spawn_dropped(StringName(e.id), int(e.count), _floor(), e.get("state", {}))
	await _seconds(1.0)
	for n: Node in level.items.get_children():  # the armory is out of 5.56 magazines
		if n is WorldItem and (n as WorldItem).item_id == &"mag_556":
			GameState.item_taken((n as WorldItem).uid)
			n.queue_free()
	await _seconds(0.3)
	var screen: InventoryScreen = player._hud.inventory_screen
	screen.visible = true
	await _seconds(0.5)
	await _grab("inventory_before_restock")
	var in_carriers := 0  # S0590: the six magazines restock found came out of a squadmate's carrier on the floor
	for n: Node in level.items.get_children():
		if n is WorldItem and not n.is_queued_for_deletion():
			in_carriers += int(BaseArmory.contents_counts([{"id": (n as WorldItem).item_id, "count": (n as WorldItem).count, "state": (n as WorldItem).state}]).get("mag_556", 0))
	print("[shots] 5.56 magazines inside carriers' pouches on the floor before the restock: %d" % in_carriers)
	BaseHub.request("restock")
	await _seconds(0.6)
	print("[shots] the player has %d after it" % inv.count_of(&"mag_556"))
	await _grab("inventory_after_restock")
	# A magazine dragged into the IFAK pouch.
	inv.insert_entry(&"pockets", {"id": &"mag_556", "count": 1})
	await _seconds(0.2)
	var ifak := &""
	for p: Dictionary in inv.attach_points():
		if inv.attachment(StringName(p.id)).get("id", &"") == &"pouch_ifak":
			ifak = StringName(p.id)
	var index := -1
	for i in inv.containers[&"pockets"].size():
		if inv.containers[&"pockets"][i].id == &"mag_556":
			index = i
	player._server_inventory_action.rpc_id(1, "move_entry", &"pockets", index, &"", Inventory.pouch_container(ifak))
	await _seconds(0.4)
	await _grab("refused_into_ifak_pouch")
	screen._set_view(InventoryScreen.View.MOLLE)
	inv.insert_entry(&"pockets", {"id": &"pouch_mag_single", "count": 1})
	await _seconds(0.2)
	for i in inv.containers[&"pockets"].size():
		if inv.containers[&"pockets"][i].id == &"pouch_mag_single":
			index = i
	player._server_inventory_action.rpc_id(1, "attach", &"pockets", index, &"", &"mag_1")
	await _seconds(0.4)
	await _grab("refused_point_molle_view")
	screen.visible = false
	BaseHub.open_ui("squad")
	BaseHub.request("restock_squad")
	await _seconds(0.6)
	await _grab("base_screen_restock_squad")
	print("[shots] done (%d)" % _shots)
	BaseHub.delete_test_campaign_files()
	get_tree().quit(0)


func _floor() -> Vector3:
	return Vector3(randf_range(-14.5, -7.5), 0.4, randf_range(-14.5, -9.5))


func _grab(label: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shots += 1
	var path := "%s/%02d_%s.png" % [out, _shots, label]
	get_viewport().get_texture().get_image().save_png(path)
	print("[shots] saved %s" % path)


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
