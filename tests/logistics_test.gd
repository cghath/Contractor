extends Node
## Headless checks for ammunition, smokes and navigation (wave 2, W8): loose rounds,
## loading magazines, empty magazines kept after a reload, the respawn kit, coloured smokes,
## and the navmesh reacting to a breached wall but not to bullet holes.
##   <voxel godot exe> --headless --path . res://tests/logistics_test.tscn
## It hosts a session, and at the end starts a second copy of itself that joins over ENet
## (`-- --join`) to check that loading and smoke colours replicate; the client reports its
## checks back to the host. Exits with the number of failures.

var failures := 0
var level: CompoundLevel
var player: Soldier
var _client_ready := false
var _client_done := false


func _ready() -> void:
	var joining := "--join" in OS.get_cmdline_user_args()
	GameState.zone_id = "test_logistics" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	CompoundLevel.spawn_ai = false  # squad AI has its own test
	if not joining:
		GameState.delete_save()
	add_child(load("res://scenes/main.tscn").instantiate())  # main joins on --join
	await get_tree().process_frame
	if joining:
		await _run_client()
		return
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we drive it
	await _frames(30)
	_test_loose_rounds()
	_test_empty_mags_kept()
	await _test_loading()
	_test_molle_rules()
	await _test_molle_host()
	await _test_respawn_kit()
	await _test_smoke_colours()
	await _test_breach_navigation()
	await _test_over_network()
	GameState.delete_save()
	print("LOGISTICS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- Loose rounds and magazines -----------------------------------------------------------

func _test_loose_rounds() -> void:
	print("Loose rounds")
	var inv := Inventory.new()
	inv.take(&"plate_carrier")
	check(inv.take(&"rounds_556", 90) == 90 and _entries(inv, &"rounds_556").size() == 1, "90 loose 5.56 rounds stack in one entry")
	inv.take(&"rounds_556", 30)
	var counts := _entries(inv, &"rounds_556").map(func(e: Dictionary) -> int: return e.count)
	check(inv.count_of(&"rounds_556") == 120 and counts == [100, 20], "120 rounds: a stack of 100 and one of 20 (%s)" % [counts])
	check(absf(inv.used(&"vest") - 120 * 0.006) < 0.001, "each round takes its own volume (120 rounds: %.2f L)" % inv.used(&"vest"))
	check(absf(inv.total_mass() - (2.0 + 120 * 0.0123)) < 0.01, "and its own mass (%.2f kg with the carrier)" % inv.total_mass())
	for c: Array in [[&"rounds_556", &"mag_556", "5.56"], [&"rounds_762", &"mag_762", "7.62"], [&"rounds_9mm", &"mag_9mm", "9mm"]]:
		var loose := ItemDB.get_item(c[0])
		var mag := ItemDB.get_item(c[1])
		check(Inventory.is_loose_rounds(loose) and not Inventory.is_loose_rounds(mag) and Inventory.calibre_of(loose) == c[2] and Inventory.calibre_of(mag) == c[2]
			and loose.stats.round == mag.stats.round, "%s loose rounds go in the %s" % [c[2], mag.name])
	var bigger := [ItemDB.get_item(&"rounds_9mm").volume_l, ItemDB.get_item(&"rounds_556").volume_l, ItemDB.get_item(&"rounds_762").volume_l]
	check(bigger[0] < bigger[1] and bigger[1] < bigger[2] and ItemDB.get_item(&"rounds_762").mass_kg > ItemDB.get_item(&"rounds_556").mass_kg,
		"a 7.62x51 round is bigger and heavier than a 5.56, a 9mm smaller")
	var empty := Inventory.entry_mass({"id": &"mag_556", "count": 1, "state": {"rounds": 0}})
	var half := Inventory.entry_mass({"id": &"mag_556", "count": 1, "state": {"rounds": 15}})
	var full := Inventory.entry_mass({"id": &"mag_556", "count": 1})
	check(absf(empty - 0.13) < 0.001 and absf(full - 0.5) < 0.001 and half > empty and half < full, "a magazine weighs its rounds (empty %.2f, 15 rds %.2f, full %.2f kg)" % [empty, half, full])
	inv.free()


func _test_empty_mags_kept() -> void:
	print("Empty magazines")
	var inv := Inventory.new()
	for id: StringName in [&"plate_carrier", &"m4a1"]:
		inv.take(id)
	inv.take(&"mag_556", 2)
	for i in 30:
		inv.consume_round(&"primary")
	check(inv.reload(&"primary") == 30, "reload from the pouch")
	check(_rounds_of(inv, &"mag_556") == [0, 30], "the empty magazine went back in the pouch (%s)" % [_rounds_of(inv, &"mag_556")])
	for i in 30:
		inv.consume_round(&"primary")
	inv.reload(&"primary")
	var empties := _entries(inv, &"mag_556")
	check(empties.size() == 1 and empties[0].count == 2 and int(empties[0].state.rounds) == 0, "two empties stack in one entry (%s)" % [empties])
	for i in 30:
		inv.consume_round(&"primary")
	check(inv.reload(&"primary") == -1, "an empty magazine is never loaded into the weapon")
	inv.take(&"rounds_556", 40)
	check(inv.load_rounds(&"rounds_556", 40) == 40 and _rounds_of(inv, &"mag_556") == [10, 30], "loose rounds fill one magazine, then start the next (%s)" % [_rounds_of(inv, &"mag_556")])
	check(inv.count_of(&"rounds_556") == 0 and inv.load_rounds(&"rounds_556", 5) == 0, "nothing left to load")
	inv.free()


func _test_loading() -> void:
	print("Loading magazines (timed host action)")
	var inv := player.inventory
	inv.strip()
	player.global_position = Vector3(0, 0.1, 18)
	for id: StringName in [&"plate_carrier", &"m4a1", &"m17"]:
		inv.take(id)
	inv.take(&"mag_556", 1)
	for i in 30:
		inv.consume_round(&"primary")
	player._server_busy_until = 0.0
	player._server_reload.rpc_id(1, &"primary")
	await _seconds(2.7)
	check(inv.rounds_in(&"primary") == 30 and _rounds_of(inv, &"mag_556") == [0], "a reload through the host keeps the empty magazine (%s)" % [_rounds_of(inv, &"mag_556")])
	inv.take(&"mag_556", 1, {"rounds": 12})
	inv.take(&"mag_556", 1, {"rounds": 0})
	inv.take(&"mag_9mm", 1, {"rounds": 5})
	inv.take(&"rounds_556", 25)
	inv.take(&"rounds_762", 20)
	check(inv.loadable_rounds(&"rounds_556") == 25 and inv.loadable_rounds(&"rounds_762") == 0, "25 rounds fit the 5.56 magazines; no 7.62 magazines to load")
	player._server_load_mags.rpc_id(1, &"rounds_762")
	check(not player.loading_mags, "loading 7.62 without a 7.62 magazine does nothing")

	var screen: InventoryScreen = player._hud.inventory_screen
	screen.visible = true
	await _frames(2)
	var button := _find_button(screen, "Load magazines")
	check(button != null, "the inventory screen offers Load magazines on the loose rounds")
	if button == null:
		screen.visible = false
		return
	button.pressed.emit()
	screen.visible = false
	check(player.loading_mags, "loading started")
	await _seconds(1.1)
	var loaded := 25 - inv.count_of(&"rounds_556")
	check(loaded >= 4 and loaded <= 6, "about 5 rounds a second (%d after 1.1 s)" % loaded)
	check(_rounds_of(inv, &"mag_556") == [0, 0, 12 + loaded], "fullest first: they went into the 12-round magazine (%s)" % [_rounds_of(inv, &"mag_556")])
	check(_rounds_of(inv, &"mag_9mm") == [5], "the 9mm magazine is left alone")

	player.global_position += Vector3(1.0, 0.0, 0.0)  # walking off
	await _seconds(0.5)
	var after_move := inv.count_of(&"rounds_556")
	await _seconds(0.6)
	check(not player.loading_mags and inv.count_of(&"rounds_556") == after_move, "moving off stops loading (%d loose left)" % after_move)
	check("moved" in player._hud._message.text, "and says so (\"%s\")" % player._hud._message.text)
	check(_spare_and_loose(inv) == 12 + 25, "what went in stays in")

	player._server_load_mags.rpc_id(1, &"rounds_556")
	await _seconds(0.5)
	player._server_next_shot = 0.0
	player._server_busy_until = 0.0
	player._server_fire.rpc_id(1, player.head.global_position, -player.global_basis.z, &"primary")
	var after_fire := inv.count_of(&"rounds_556")
	await _seconds(0.6)
	check(inv.rounds_in(&"primary") == 29 and not player.loading_mags and inv.count_of(&"rounds_556") == after_fire, "firing stops loading (%d loose left)" % after_fire)

	player._server_load_mags.rpc_id(1, &"rounds_556")
	var left := inv.count_of(&"rounds_556")
	var started := Time.get_ticks_msec()
	await _wait_for(func() -> bool: return not player.loading_mags, 8.0)
	var took := (Time.get_ticks_msec() - started) / 1000.0
	check(inv.count_of(&"rounds_556") == 0 and _rounds_of(inv, &"mag_556") == [0, 7, 30], "all 25 loaded: one magazine topped up, 7 in the next (%s)" % [_rounds_of(inv, &"mag_556")])
	check(absf(took - left * Soldier.LOAD_ROUND_S) < 0.35, "%d rounds took %.1f s (%.1f s a round)" % [left, took, Soldier.LOAD_ROUND_S])
	check("Loaded" in player._hud._message.text, "done: \"%s\"" % player._hud._message.text)


# --- MOLLE attachments --------------------------------------------------------------------

func _test_molle_rules() -> void:
	print("MOLLE attach points and pouches")
	var light := ItemDB.get_item(&"plate_carrier_light")
	var medium := ItemDB.get_item(&"plate_carrier")
	var heavy := ItemDB.get_item(&"plate_carrier_heavy")
	check(light.stats.molle.size() < medium.stats.molle.size() and medium.stats.molle.size() < heavy.stats.molle.size(),
		"heavier carriers have more attach points (%d, %d, %d)" % [light.stats.molle.size(), medium.stats.molle.size(), heavy.stats.molle.size()])
	for id: StringName in [&"pouch_mag_single", &"pouch_mag_double", &"pouch_pistol_mag", &"pouch_radio", &"pouch_binos", &"pouch_utility", &"pouch_sustainment", &"pouch_ifak", &"pouch_grenade", &"knife", &"radio", &"binoculars"]:
		check(ItemDB.has_item(id) and ItemDB.get_item(id).mass_kg > 0.0, "%s exists with a mass" % id)
	var inv := Inventory.new()
	check(inv.take(&"pouch_mag_double") == 1 and inv.attachment_count() == 0, "with no carrier a pouch is just stowed")
	inv.strip()
	inv.take(&"plate_carrier")
	var bare := inv.total_mass()
	check(inv.take(&"pouch_mag_double", 2) == 2 and inv.attachment(&"mag_1").get("id") == &"pouch_mag_double" and inv.attachment(&"mag_2").get("id") == &"pouch_mag_double",
		"mag pouches picked up go onto the carrier's mag points")
	check(inv.take(&"knife") == 1 and inv.attachment(&"knife").get("id") == &"knife", "a knife goes on the knife point")
	check(inv.take(&"pouch_radio") == 1 and inv.attachment(&"radio").get("id") == &"pouch_radio", "the radio pouch on the radio point")
	check(inv.pouch_containers().size() == 3 and not inv.containers.has(Inventory.pouch_container(&"knife")), "pouches are containers, the knife isn't (%s)" % [inv.pouch_containers()])
	check(inv.take(&"mag_556", 5) == 5, "5 magazines taken")
	check(inv.units_in(&"molle:mag_1") == 2 and inv.units_in(&"molle:mag_2") == 2 and _count_in(inv, &"vest", &"mag_556") == 1,
		"they fill the mag pouches first, 2 each, the 5th in the vest")
	check(inv.take(&"radio") == 1 and inv.units_in(&"molle:radio") == 1, "the radio goes in its pouch")
	check(inv.room_for(&"molle:radio", ItemDB.get_item(&"mag_556")) == 0 and inv.room_for(&"molle:mag_1", ItemDB.get_item(&"mag_556")) == 0,
		"a radio pouch takes no magazines, a full mag pouch no more")
	check(inv.attach_problem(ItemDB.get_item(&"pouch_mag_double"), &"radio") != "", "a mag pouch doesn't fit the (taken) radio point")
	check(inv.attach_problem(ItemDB.get_item(&"pouch_radio"), &"utility_1") == "", "a radio pouch fits a utility point")
	# Captain's playtest P0164: chest points take the radio, IFAK and GP pouches too; and
	# "no free point" says why.
	var chest_points := inv.attach_points().filter(func(p: Dictionary) -> bool: return p.type == "chest")
	check(not chest_points.is_empty() and [&"pouch_radio", &"pouch_ifak", &"pouch_utility"].all(func(id: StringName) -> bool:
			return inv.attach_problem(ItemDB.get_item(id), StringName(chest_points[0].id)) == ""),
		"the Medium carrier's chest points take a radio, IFAK or GP pouch")
	var ifak_point := inv.attach_point(inv.free_point_for(ItemDB.get_item(&"pouch_ifak")))
	check(ifak_point.get("type") == "medical", "but an IFAK pouch still goes on its medical point first (%s)" % [ifak_point.get("type")])
	var light_inv := Inventory.new()
	check(light_inv.no_point_problem(ItemDB.get_item(&"pouch_ifak")) == "Put on a plate carrier first", "no carrier: \"%s\"" % light_inv.no_point_problem(ItemDB.get_item(&"pouch_ifak")))
	light_inv.take(&"plate_carrier_light")
	light_inv.take(&"pouch_utility")
	var why := light_inv.no_point_problem(ItemDB.get_item(&"pouch_ifak"))
	check(why.begins_with("Every ") and why.contains("taken") and why.contains("Low-Profile"), "its points taken: \"%s\"" % why)
	light_inv.free()
	var expected := bare + 2 * 0.14 + 0.3 + 0.12 + 1.2 + 5 * 0.5
	check(absf(inv.total_mass() - expected) < 0.01, "pouches and what's in them count in the mass (%.2f kg, expected %.2f)" % [inv.total_mass(), expected])
	# Reloading pulls from the mag pouches first.
	inv.take(&"m4a1")
	for i in 30:
		inv.consume_round(&"primary")
	check(inv.reload(&"primary") == 30 and _rounds_in_container(inv, &"molle:mag_1") == [0, 30] and _count_in(inv, &"vest", &"mag_556") == 1,
		"reload takes a full mag from the first mag pouch and puts the empty back there (%s)" % [_rounds_in_container(inv, &"molle:mag_1")])
	check(inv.spare_rounds(&"mag_556") == 30 * 4, "spare rounds count the pouches (%d)" % inv.spare_rounds(&"mag_556"))
	# Moving and detaching.
	check(inv.move_attachment(&"radio", &"utility_1") and inv.attachment(&"radio").is_empty() and inv.units_in(&"molle:utility_1") == 1,
		"the radio pouch moves to a utility point with the radio in it")
	var pouch := inv.detach(&"mag_2")
	check(pouch.get("id") == &"pouch_mag_double" and pouch.state.held.size() == 1 and int(pouch.state.held[0].count) == 2, "detached, a pouch keeps its magazines (%s)" % [pouch])
	check(inv.spare_rounds(&"mag_556") == 30 * 2, "which no longer count as carried")
	var full_sustain := Inventory.unit_volume(ItemDB.get_item(&"pouch_sustainment"), {"held": [{"id": &"mag_556", "count": 8}]})
	check(is_equal_approx(full_sustain, 2.0) and is_equal_approx(Inventory.unit_volume(ItemDB.get_item(&"pouch_sustainment")), 1.0),
		"stowed, a full pouch takes the room its contents fill, an empty one folds down (%.2f L)" % full_sustain)
	check(inv.attach(&"mag_3", pouch) and inv.units_in(&"molle:mag_3") == 2, "and brings them back when attached again")
	# The vest keeps everything when it comes off (dropped, looted) and in the zone save.
	check(inv.unequip(&"vest").is_empty(), "a carrier with things in its own pockets still won't come off")
	inv.remove_entry(&"vest", 0, 1)  # the 5th magazine
	var vest := inv.unequip(&"vest")
	check(vest.get("id") == &"plate_carrier" and vest.state.molle.size() == 4, "the carrier comes off with its 4 attachments (%s)" % [vest.get("state", {}).get("molle", {}).keys()])
	check(Inventory.unit_volume(ItemDB.get_item(&"plate_carrier"), vest.state) > ItemDB.get_item(&"plate_carrier").volume_l,
		"stowed, it takes more room than a bare carrier (%.2f L)" % Inventory.unit_volume(ItemDB.get_item(&"plate_carrier"), vest.state))
	var saved: Variant = GameState.from_json(JSON.parse_string(JSON.stringify(vest.state)))
	var other := Inventory.new()
	check(other.take(&"plate_carrier", 1, saved) == 1 and other.attachment_count() == 4, "saved and loaded with the zone, then worn by someone else: still 4 attached")
	check(other.spare_rounds(&"mag_556") == 30 * 3 and other.count_of(&"radio") == 1, "with the magazines and radio in its pouches (%d rds)" % other.spare_rounds(&"mag_556"))
	other.take(&"m4a1")
	for i in 30:
		other.consume_round(&"primary")
	check(other.reload(&"primary") == 30, "and those magazines reload a rifle")
	var packed := Inventory.new()
	packed.take(&"plate_carrier")
	packed.take(&"ruck_45")
	check(packed.take(&"plate_carrier", 1, saved) == 1 and Inventory.contents_mass(packed.containers[&"backpack"][0].state) > 2.0,
		"stowed in a pack, a carrier keeps its pouches (and their mass)")
	inv.free()
	other.free()
	packed.free()


func _test_molle_host() -> void:
	print("MOLLE through the host and the inventory screen")
	var inv := player.inventory
	inv.strip()
	player.global_position = Vector3(0, 0.1, 18)
	for id: StringName in [&"plate_carrier", &"m4a1", &"assault_pack"]:
		inv.take(id)
	inv.take(&"mag_556", 3)
	inv.take(&"pouch_mag_double")
	check(inv.attachment(&"mag_1").get("id") == &"pouch_mag_double" and _count_in(inv, &"vest", &"mag_556") == 3, "a mag pouch attached; the magazines stay in the vest")
	inv.insert_entry(&"backpack", {"id": &"pouch_pistol_mag", "count": 1})
	player._server_inventory_action.rpc_id(1, "attach", &"backpack", _index_in(inv, &"backpack", &"pouch_pistol_mag"), &"", &"radio")
	check(inv.attachment(&"radio").is_empty() and _count_in(inv, &"backpack", &"pouch_pistol_mag") == 1, "the host refuses a pistol pouch on the radio point")
	player._server_inventory_action.rpc_id(1, "attach", &"backpack", _index_in(inv, &"backpack", &"pouch_pistol_mag"), &"", &"utility_1")
	check(inv.attachment(&"utility_1").get("id") == &"pouch_pistol_mag", "and puts it on a utility point")
	player._server_inventory_action.rpc_id(1, "move_entry", &"vest", _index_in(inv, &"vest", &"mag_556"), &"", &"molle:mag_1")
	check(inv.units_in(&"molle:mag_1") == 2 and _count_in(inv, &"vest", &"mag_556") == 1,
		"moving 3 magazines into a double mag pouch moves the 2 that fit (%d in the pouch)" % inv.units_in(&"molle:mag_1"))
	player._server_inventory_action.rpc_id(1, "move_entry", &"vest", _index_in(inv, &"vest", &"mag_556"), &"", &"molle:utility_1")
	check(_count_in(inv, &"vest", &"mag_556") == 1 and inv.units_in(&"molle:utility_1") == 0, "a pistol pouch won't take rifle magazines")
	player._server_inventory_action.rpc_id(1, "move_attachment", &"", -1, &"mag_1", &"mag_3")
	check(inv.attachment(&"mag_1").is_empty() and inv.units_in(&"molle:mag_3") == 2, "an attached pouch moves points with its magazines")
	player._server_inventory_action.rpc_id(1, "detach", &"", -1, &"utility_1", &"backpack")
	check(inv.attachment(&"utility_1").is_empty() and _count_in(inv, &"backpack", &"pouch_pistol_mag") == 1, "detached into the backpack")
	# The screen's drag and drop asks for the same actions.
	var screen: InventoryScreen = player._hud.inventory_screen
	screen.visible = true
	await _frames(2)
	var drop := screen.drop_action({"kind": "entry", "container": &"backpack", "index": _index_in(inv, &"backpack", &"pouch_pistol_mag"), "id": &"pouch_pistol_mag"}, {"kind": "point", "point": &"pistol_1"})
	check(drop.is_valid(), "dragging a pouch onto an attach point is an action")
	if drop.is_valid():
		drop.call()
	check(inv.attachment(&"pistol_1").get("id") == &"pouch_pistol_mag", "and it attaches it")
	check(not screen.drop_action({"kind": "slot", "slot": &"primary", "id": &"m4a1"}, {"kind": "point", "point": &"mag_2"}).is_valid(), "a rifle can't be dropped on an attach point")
	await _frames(2)
	var pressed: Array = screen._tiles.filter(func(t: Array) -> bool: return t[1].kind == "slot" and t[1].slot == &"primary")[0]
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	screen._tile_input(press, pressed[1], pressed[0])
	check(is_instance_valid(pressed[0]) and pressed[0].is_inside_tree() and not pressed[0].is_queued_for_deletion() and screen._is_selected(pressed[1]),
		"pressing a tile selects it and keeps it, so a drag can start from it")
	screen._menu_src = {"kind": "entry", "container": &"backpack", "index": 99, "id": &"m4a1"}
	check(not screen._still_there(screen._menu_src), "a menu for an entry that has gone does nothing")
	screen._set_view(InventoryScreen.View.MOLLE)
	await _frames(2)
	check(screen._point_tiles.size() == inv.attach_points().size(), "the MOLLE view lays out every attach point (%d)" % screen._point_tiles.size())
	# A pouch held: the free points it fits light up, the rest dim (P0164).
	screen._mark_points(&"pouch_ifak")
	var lit := []
	var wrong := []
	for p: Dictionary in inv.attach_points():
		var fits: bool = p.type in ["medical", "utility", "chest"] and inv.attachment(StringName(p.id)).is_empty()
		var tint: Color = screen._point_tiles[String(p.id)].modulate
		if fits:
			lit.append(p.id)
		if (tint == InventoryScreen.FITS_TINT) != fits or (not fits and not is_equal_approx(tint.a, InventoryScreen.DIMMED_ALPHA)):
			wrong.append(p.id)
	check(not lit.is_empty() and wrong.is_empty(), "an IFAK pouch held: %s light up, the rest dim (wrong: %s)" % [lit, wrong])
	screen._mark_points(&"")
	check(screen._point_tiles.values().all(func(t: Control) -> bool: return t.modulate == Color.WHITE), "nothing held: all plain")
	screen._set_view(InventoryScreen.View.LOADOUT)
	screen.visible = false
	# Dropping the carrier keeps its pouches; picking it up brings them back.
	while not inv.containers[&"vest"].is_empty():
		inv.remove_entry(&"vest", 0, int(inv.containers[&"vest"][0].count))
	player._server_inventory_action.rpc_id(1, "drop_slot", &"", -1, &"vest", &"")
	check(inv.slots[&"vest"] == &"" and inv.spare_rounds(&"mag_556") == 0, "the carrier dropped, with the magazines in its pouches")
	await _frames(3)
	var dropped: WorldItem = null
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if node.item_id == &"plate_carrier" and not node.state.get("molle", {}).is_empty():
			dropped = node
	check(dropped != null and dropped.state.molle.size() == 2 and GameState.dropped.get(dropped.uid, {}).get("state", {}).has("molle"),
		"it lies there with its 2 pouches, recorded for the zone save")
	if dropped:
		player._server_interact.rpc_id(1, dropped.get_path())
		check(inv.slots[&"vest"] == &"plate_carrier" and inv.attachment_count() == 2 and inv.units_in(&"molle:mag_3") == 2, "picked up again, pouches, magazines and all")
	inv.strip()


func _count_in(inv: Inventory, container: StringName, id: StringName) -> int:
	var n := 0
	for entry: Dictionary in inv.containers.get(container, []):
		if entry.id == id:
			n += int(entry.count)
	return n


func _index_in(inv: Inventory, container: StringName, id: StringName) -> int:
	var list: Array = inv.containers.get(container, [])
	for i in list.size():
		if list[i].id == id:
			return i
	return -1


func _rounds_in_container(inv: Inventory, container: StringName) -> Array:
	var rounds := []
	for entry: Dictionary in inv.containers.get(container, []):
		var full := ItemDB.get_item(entry.id).magazine_rounds()
		for i in int(entry.count):
			rounds.append(int(entry.get("state", {}).get("rounds", full)))
	rounds.sort()
	return rounds


func _test_respawn_kit() -> void:
	print("Respawn kit")
	player.global_position = Vector3(0, 0.1, 18)
	player.vitals.server_damage(500.0)
	await _frames(2)
	player.vitals.server_advance(Vitals.ARREST_WINDOW_S + 1.0)
	await _frames(2)
	var inv := player.inventory
	check(player.vitals.is_up(), "respawned")
	check(inv.slots[&"primary"] == &"m4a1" and inv.rounds_in(&"primary") == 30, "an M4, loaded")
	check(inv.count_of(&"mag_556") == 2 and inv.spare_rounds(&"mag_556") == 60, "2 spare magazines, full")
	check(inv.count_of(&"rounds_556") == 90, "90 loose 5.56 rounds (%d)" % inv.count_of(&"rounds_556"))
	check(inv.count_of(&"smoke_grenade") == 1 and inv.count_of(&"frag_grenade") == 1, "a smoke and a frag")
	var kinds := 0
	for container in Inventory.CONTAINERS:
		kinds += inv.containers[container].size()
	check(kinds == 4, "and nothing else (%d stowed entries)" % kinds)
	check(inv.loadable_rounds(&"rounds_556") == 0, "the loose rounds wait for a magazine to empty")


# --- Smokes ------------------------------------------------------------------------------

func _test_smoke_colours() -> void:
	print("Coloured smokes")
	for colour: String in ["green", "yellow", "blue", "purple"]:
		var item := ItemDB.get_item(StringName("smoke_" + colour))
		check(item != null and item.stats.get("throwable") == "smoke" and item.stats.get("smoke_colour") == colour, "%s smoke grenade item" % colour)
	var loot := CompoundLevel.LOOT.filter(func(l: Dictionary) -> bool: return String(l.id).begins_with("smoke_") and l.id != "smoke_grenade")
	check(loot.size() >= 4, "coloured smokes in the compound loot (%d)" % loot.size())
	var ammo_loot := CompoundLevel.LOOT.filter(func(l: Dictionary) -> bool: return String(l.id).begins_with("rounds_"))
	check(ammo_loot.size() >= 3, "and loose rounds (%d)" % ammo_loot.size())

	var inv := player.inventory
	inv.strip()
	inv.take(&"plate_carrier")
	inv.take(&"smoke_green")
	inv.take(&"smoke_purple", 2)
	check(_cycle(inv, 5) == [&"flashbang", &"smoke_green", &"smoke_purple", &"frag_grenade", &"flashbang"],
		"Shift+G: frag, flashbang, then the smoke colours you carry (%s)" % [_cycle(inv, 5)])
	for id: StringName in [&"smoke_grenade", &"smoke_yellow", &"smoke_blue"]:
		inv.take(id)
	check(_cycle(inv, 7) == [&"flashbang", &"smoke_grenade", &"smoke_green", &"smoke_yellow", &"smoke_blue", &"smoke_purple", &"frag_grenade"],
		"with every colour carried (%s)" % [_cycle(inv, 7)])

	player.global_position = Vector3(0, 0.1, 16)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	await _frames(2)
	player._server_busy_until = 0.0
	player._server_throw.rpc_id(1, player.camera.global_position, -player.global_basis.z, &"smoke_purple")
	check(inv.count_of(&"smoke_purple") == 1, "throwing uses one purple smoke")
	await _seconds(2.0)
	var purple := SmokeCloud.clouds_of("purple")
	check(purple.size() == 1 and _same_colour(purple[0]._material.albedo_color, SmokeCloud.COLOURS["purple"]), "the purple smoke makes a purple cloud")
	var at := Vector3(0, 0.1, 10)
	Throwables.server_detonate(level, "smoke", at, &"smoke_green")
	await _seconds(3.2)
	var green := SmokeCloud.clouds_of("green")
	check(green.size() == 1 and green[0].colour == "green" and _same_colour(green[0]._material.albedo_color, SmokeCloud.COLOURS["green"]), "a green cloud")
	check(SmokeCloud.blocks(at + Vector3(-8, 1.5, 0), at + Vector3(8, 1.5, 0)), "coloured smoke blocks sight lines like white")
	Throwables.server_detonate(level, "smoke", at + Vector3(0, 0, -30))
	await _frames(2)
	check(SmokeCloud.clouds_of("white").size() >= 1, "a smoke without a colour is white")


func _cycle(inv: Inventory, steps: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var t: StringName = &"frag_grenade"
	for i in steps:
		t = PlayerInput.next_throwable(t, inv)
		out.append(t)
	return out


func _same_colour(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


# --- Navigation --------------------------------------------------------------------------

func _test_breach_navigation() -> void:
	print("Navigation and breaches")
	var nav := level.get_node_or_null(^"Navigation") as NavBuilder
	var count := NavBuilder.chunk_count()
	check(nav != null and nav.get_child_count() == count.x * count.y, "the navmesh is baked in %d chunks" % (count.x * count.y))
	if nav == null:
		return
	var world := level.voxel_world
	# solid_voxels reads the voxel world in the order it says.
	var begin := Vector3i(-52, 0, -84)
	var size := Vector3i(6, 4, 5)
	var solid := world.solid_voxels(begin, size)
	var tool := world.terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_COLOR
	var mismatches := 0
	for z in size.z:
		for x in size.x:
			for y in size.y:
				var expect := 1 if tool.get_voxel(begin + Vector3i(x, y, z)) != VoxelWorld.Mat.EMPTY else 0
				if solid[y + size.y * (x + size.x * z)] != expect:
					mismatches += 1
	check(mismatches == 0 and solid.count(1) == 3 * 4 * 5, "solid_voxels matches the voxels (%d solid, %d wrong)" % [solid.count(1), mismatches])

	var map := player.get_world_3d().navigation_map
	var inside := Vector3(-3, 0, -8)
	var outside := Vector3(-7, 0, -8)
	var before := _path_length(map, inside, outside)
	check(before > 7.0, "out of the building, the way goes round through the doorway (%.1f m)" % before)
	var meshes := {}
	for chunk: Vector2i in nav._regions:
		meshes[chunk] = nav._regions[chunk].navigation_mesh
	var rebaked: Array[Vector2i] = []
	nav.rebaked.connect(func(chunk: Vector2i) -> void: rebaked.append(chunk))

	# Bullet holes, a burst of them in one spot, and a frag crater: no rebake.
	var carve := float(ItemDB.get_item(&"m4a1").stats.wall_carve_m)
	for i in 14:
		world.server_carve(Vector3(-4.85, 0.8 + 0.07 * i, -10.6 + 0.06 * (i % 4)), carve)
	world.server_carve(Vector3(-4.85, 1.2, -6.0), Throwables.FRAG_CARVE_M)
	await _seconds(0.8)
	check(rebaked.is_empty() and not nav.is_rebaking(), "bullet holes and a frag crater don't rebake the navmesh")
	check(nav._regions.keys().all(func(c: Vector2i) -> bool: return nav._regions[c].navigation_mesh == meshes[c]), "every chunk keeps its navmesh")
	check(absf(_path_length(map, inside, outside) - before) < 0.01, "and paths don't change")

	# A breach: a gap about 1.3 m wide and 2 m high through the building's west wall.
	var started := Time.get_ticks_usec()
	for y: float in [0.4, 1.0, 1.6]:
		world.server_carve(Vector3(-4.85, y, -8.0), 0.75)
	await _frames(1)
	check(absf(_path_length(map, inside, outside) - before) < 0.01, "until the rebake is done, AI treats the gap as blocked")
	await _wait_for(func() -> bool: return not rebaked.is_empty() and not nav.is_rebaking(), 6.0)
	var took_ms := (Time.get_ticks_usec() - started) / 1000.0
	# The navigation map takes the new chunk meshes on a later physics sync; a slower machine
	# (CI) needs more than a few frames, so wait for the shorter path, up to 3 s.
	await _wait_for(func() -> bool: return _path_length(map, inside, outside) < 5.5, 3.0)
	check(not rebaked.is_empty(), "the breach rebaked %d chunk(s) in the background (done after %.0f ms)" % [rebaked.size(), took_ms])
	check(rebaked.all(func(c: Vector2i) -> bool: return NavBuilder.chunk_aabb(c).grow(NavBuilder.BORDER_M + 1.0).has_point(Vector3(-4.85, 0, -8))), "only the chunks around the gap (%s)" % [rebaked])
	var path := NavigationServer3D.map_get_path(map, inside, outside, true)
	var after := _path_length(map, inside, outside)
	var through := Array(path).any(func(p: Vector3) -> bool: return Vector2(p.x + 4.85, p.z + 8.0).length() < 1.0)
	check(after < 5.5, "now the path goes straight out through the breach (%.1f m, was %.1f)" % [after, before])
	check(through, "right past the gap")
	var path_back := _path_length(map, Vector3(0, 0, 0), Vector3(0, 0, -8))
	check(path_back < 12.0, "paths elsewhere still work (through the doorway: %.1f m)" % path_back)

	# What the host spends on the main thread: the breach check and reading a chunk's voxels.
	var t0 := Time.get_ticks_usec()
	world.find_breach(AABB(Vector3(-49.5, 7.5, -63.5), Vector3(2.4, 2.4, 2.4)))
	var check_ms := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var source := nav._voxel_source(NavBuilder.chunk_at(Vector3(-4.85, 0, -8)))
	var source_ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(source != null and check_ms < 20.0 and source_ms < 60.0, "host cost: breach check %.1f ms, chunk voxels for a rebake %.1f ms" % [check_ms, source_ms])


func _path_length(map: RID, from: Vector3, to: Vector3) -> float:
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	if path.size() < 2 or Vector2(path[-1].x - to.x, path[-1].z - to.z).length() > 0.5:
		return INF
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


# --- Over the network --------------------------------------------------------------------

func _test_over_network() -> void:
	print("Over ENet (a second process joins)")
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/logistics_test.tscn", "--", "--join", "127.0.0.1"])
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "client process started")
	if pid <= 0:
		return
	await _wait_for(func() -> bool: return _client_ready, 30.0)
	check(_client_ready, "the client joined")
	if _client_ready:
		var client: Soldier = null
		for p in level.players.get_children():
			if p is Soldier and p.name != "1":
				client = p
		client.inventory.take(&"plate_carrier")
		client.inventory.take(&"mag_556", 1, {"rounds": 0})
		client.inventory.take(&"rounds_556", 10)
		_start_client_checks.rpc_id(client.owner_peer())
		await _seconds(1.0)
		Throwables.server_detonate(level, "smoke", Vector3(-6, 0.1, 8), &"smoke_green")
		Throwables.server_detonate(level, "smoke", Vector3(6, 0.1, 8), &"smoke_blue")
		await _wait_for(func() -> bool: return _client_done, 25.0)
		check(_client_done, "the client finished its checks")
	if OS.is_process_running(pid):
		OS.kill(pid)


## Client: runs in the joined copy of this test.
func _run_client() -> void:
	level = CompoundLevel.current(self)
	var deadline := Time.get_ticks_msec() + 20000
	var me: Soldier = null
	while Time.get_ticks_msec() < deadline:
		me = level.players.get_node_or_null(str(multiplayer.get_unique_id())) if level else null
		if me and level.voxel_world.is_built():
			break
		level = CompoundLevel.current(self)
		await get_tree().process_frame
	if me == null:
		get_tree().quit(1)
		return
	me.set_physics_process(false)
	_remote_ready.rpc_id(1)
	while not _client_ready and Time.get_ticks_msec() < deadline + 10000:  # the host's go-ahead
		await get_tree().process_frame
	await _wait_for(func() -> bool: return me.inventory.count_of(&"rounds_556") == 10, 5.0)
	me._server_load_mags.rpc_id(1, &"rounds_556")
	await _wait_for(func() -> bool: return me.inventory.count_of(&"rounds_556") == 0, 5.0)
	_remote_check.rpc_id(1, me.inventory.spare_rounds(&"mag_556") == 10 and me.inventory.count_of(&"rounds_556") == 0,
		"Load magazines from a client goes through the host and replicates back (%d in the magazine)" % me.inventory.spare_rounds(&"mag_556"))
	# The green one set off for this check (an older green cloud from the host's own test may still
	# be out: a late joiner sees that too, audit L2-01).
	var here := func() -> Array: return SmokeCloud.clouds_of("green").filter(func(c: SmokeCloud) -> bool: return c.global_position.distance_to(Vector3(-6, 0.1, 8)) < 0.5)
	await _wait_for(func() -> bool: return not here.call().is_empty() and not SmokeCloud.clouds_of("blue").is_empty(), 10.0)
	var green: Array = here.call()
	var blue := SmokeCloud.clouds_of("blue")
	_remote_check.rpc_id(1, green.size() == 1 and _same_colour(green[0]._material.albedo_color, SmokeCloud.COLOURS["green"]), "the client sees the green smoke in green")
	_remote_check.rpc_id(1, blue.size() == 1 and _same_colour(blue[0]._material.albedo_color, SmokeCloud.COLOURS["blue"]), "and the blue one in blue")
	await _seconds(3.2)
	_remote_check.rpc_id(1, SmokeCloud.blocks(Vector3(-14, 1.6, 8), Vector3(-1, 1.6, 8)), "the client's copy blocks sight too")
	_remote_done.rpc_id(1)
	await _seconds(0.5)
	Net.leave()
	get_tree().quit(0)


## Host -> client: the kit is there; go ahead.
@rpc("authority", "reliable")
func _start_client_checks() -> void:
	_client_ready = true


@rpc("any_peer", "reliable")
func _remote_ready() -> void:
	if multiplayer.is_server():
		_client_ready = true


@rpc("any_peer", "reliable")
func _remote_check(ok: bool, what: String) -> void:
	if multiplayer.is_server():
		check(ok, "client: " + what)


@rpc("any_peer", "reliable")
func _remote_done() -> void:
	if multiplayer.is_server():
		_client_done = true


# --- Helpers -----------------------------------------------------------------------------

func _entries(inv: Inventory, id: StringName) -> Array:
	var found := []
	for container in Inventory.CONTAINERS:
		for entry: Dictionary in inv.containers[container]:
			if entry.id == id:
				found.append(entry)
	return found


## Rounds in each stowed magazine of `id`, one per magazine, sorted.
func _rounds_of(inv: Inventory, id: StringName) -> Array:
	var full := ItemDB.get_item(id).magazine_rounds()
	var rounds := []
	for entry: Dictionary in _entries(inv, id):
		for i in int(entry.count):
			rounds.append(int(entry.get("state", {}).get("rounds", full)))
	rounds.sort()
	return rounds


func _spare_and_loose(inv: Inventory) -> int:
	return inv.spare_rounds(&"mag_556") + inv.count_of(&"rounds_556")


func _find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is Button and (child as Button).text == text:
			return child
		var found := _find_button(child, text)
		if found:
			return found
	return null


func _wait_for(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
