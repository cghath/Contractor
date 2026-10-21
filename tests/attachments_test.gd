extends Node
## Weapon attachments (wave 7, S3; GunAttachments, with Optics and Suppressors). On the vehicle
## range, the host's player:
## - finds the grip, light and lasers in the item data, with their mounts and prices;
## - can't mount a grip on a pistol, a rifle-only laser on a pistol, a magazine on a gun, or
##   anything on an empty slot; mounts a grip on the M4 through the host's inventory action;
## - the grip cuts the kick and the aimed sway; the mass and the value go up by the grip's;
## - stowing the M4 and drawing it again, its grip goes with it; so does saving (JSON) and
##   loading, and a fresh inventory applying the replicated state;
## - a weapon light switched on (the weapon-light action) lights the rig and gives him away
##   (Spotting); a visible laser swapped in for it puts the light back in his kit, goes on off,
##   draws its beam when switched on; an IR laser doesn't draw for the naked eye;
## - a suppressed shot is quiet for the AI (its hearing range is shorter) and marks him so;
## - a 4x prism zooms the aimed view in past the red dot's;
## - taking the grip off puts it back in his kit, and the kick is back to full;
## - the M320 goes on the underbarrel mount (not the pistol's) and its loaded grenade goes with
##   it: off the gun, back on, swapped for the grip, the gun stowed and drawn;
## - a magnified optic's picture-in-picture (GunSight PiP): only behind its glass, at its power,
##   never headless, off unaimed, on a weapon switch, dead, in a vehicle and with the setting off.
##   <godot> --headless --path . res://tests/attachments_test.tscn

var failures := 0
var level: VehicleRange
var main: Node
var player: Soldier


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_attachments" + tag
	Campaign.campaign_id = "test_attachments" + tag
	CompoundLevel.spawn_ai = false
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("ATTACHMENTS TEST FAILED (timed out)")
		get_tree().quit(99))
	GameState.delete_save()
	_test_data()
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
	await _run()
	await _test_pip()
	_finish()


func _test_data() -> void:
	var want := {"grip_vertical": [&"underbarrel", 250], "light_weapon": [&"side", 350], "laser_visible": [&"side", 450], "laser_ir": [&"side", 1100]}
	for id: String in want:
		var item := ItemDB.get_item(StringName(id)) if ItemDB.has_item(StringName(id)) else null
		check(item != null and GunAttachments.mount_of(item) == want[id][0] and Prices.price_of(StringName(id)) == want[id][1],
			"%s: an attachment for the %s mount, $%d" % [id, want[id][0], want[id][1]])
	check(GunAttachments.mount_of(ItemDB.get_item(&"suppressor_rifle")) == &"", "the suppressor stays Suppressors' (the muzzle)")
	check(GunAttachments.fits(ItemDB.get_item(&"m4a1"), ItemDB.get_item(&"grip_vertical")), "the M4 takes a grip")
	check(not GunAttachments.fits(ItemDB.get_item(&"m17"), ItemDB.get_item(&"grip_vertical")), "the M17 pistol doesn't")
	check(GunAttachments.fits(ItemDB.get_item(&"m17"), ItemDB.get_item(&"light_weapon")), "the M17 takes a light")
	check(not GunAttachments.fits(ItemDB.get_item(&"m17"), ItemDB.get_item(&"laser_ir")), "but not the IR laser (rifles only)")


func _run() -> void:
	var inv := player.inventory
	for id: StringName in [&"plate_carrier", &"pouch_mag_double", &"ruck_45"]:
		inv.take(id)
	if inv.slots[&"primary"] != &"":
		inv.unequip(&"primary")
	if inv.slots[&"sidearm"] != &"":
		inv.unequip(&"sidearm")
	check(inv.put_on(&"primary", &"m4a1", {"rounds": 30}) and inv.put_on(&"sidearm", &"m17", {"rounds": 17}), "an M4 and an M17 in hand")
	player.active_slot = &"primary"
	var m4 := ItemDB.get_item(&"m4a1")
	for id: StringName in [&"grip_vertical", &"light_weapon", &"laser_visible", &"laser_ir", &"mag_556"]:
		inv.take(id)
	await _frames(2)
	check(inv.count_of(&"grip_vertical") == 1 and inv.count_of(&"light_weapon") == 1 and inv.count_of(&"laser_ir") == 1, "the grip, light and lasers in his kit")

	# Validation.
	var grip := _find(inv, &"grip_vertical")
	check(GunAttachments.mount_problem(inv, grip[0], grip[1], &"sidearm") != "", "no grip on the pistol: %s" % GunAttachments.mount_problem(inv, grip[0], grip[1], &"sidearm"))
	check(GunAttachments.mount_problem(inv, grip[0], grip[1], &"launcher") != "", "nothing on an empty slot")
	var ir := _find(inv, &"laser_ir")
	check(GunAttachments.mount_problem(inv, ir[0], ir[1], &"sidearm") != "", "no IR laser on the pistol")
	var mag := _find(inv, &"mag_556")
	check(GunAttachments.mount_problem(inv, mag[0], mag[1], &"primary") != "", "a magazine isn't an attachment")
	check(GunAttachments.mount_problem(inv, grip[0], grip[1], &"primary") == "", "the grip fits the M4")
	player._server_inventory_action.rpc_id(1, "mount_attachment", mag[0], mag[1], &"sidearm", &"")
	await _frames(2)
	check(inv.state_of(&"sidearm").get("underbarrel", "") == "" and inv.count_of(&"mag_556") >= 1, "the host refuses a magazine on the pistol")

	# The grip on.
	var bare_mass := inv.total_mass()
	var bare_value := Prices.value_of(&"m4a1", 1, inv.state_of(&"primary"))
	var kick_bare := _kick_of(m4)
	player.is_aiming = true
	var sway_bare := player.aim_sway_deg(m4)
	player.is_aiming = false
	player._server_inventory_action.rpc_id(1, "mount_attachment", grip[0], grip[1], &"primary", &"")
	await _frames(2)
	check(GunAttachments.mounted_id(m4, inv.state_of(&"primary"), GunAttachments.UNDERBARREL) == &"grip_vertical" and inv.count_of(&"grip_vertical") == 0,
		"the grip goes on the M4 (out of his kit)")
	check(GunAttachments.all_of(m4, inv.state_of(&"primary")).underbarrel == "grip_vertical", "the gun's attachments: %s" % GunAttachments.all_of(m4, inv.state_of(&"primary")))
	var kick_grip := _kick_of(m4)
	check(kick_grip < kick_bare * 0.85 and absf(kick_grip / kick_bare - 0.8) < 0.01, "the grip cuts the kick (%.3f -> %.3f deg)" % [kick_bare, kick_grip])
	player.is_aiming = true
	var sway_grip := player.aim_sway_deg(m4)
	player.is_aiming = false
	check(sway_grip < sway_bare, "and the aimed sway (%.3f -> %.3f deg)" % [sway_bare, sway_grip])
	check(absf(inv.total_mass() - bare_mass) < 0.001, "the load is the same: the grip moved from the kit onto the gun (%.2f kg)" % inv.total_mass())
	check(is_equal_approx(MovementRules.weapon_mass(m4, inv.state_of(&"primary")) - MovementRules.weapon_mass(m4, {}), ItemDB.get_item(&"grip_vertical").mass_kg), "the gun is heavier by the grip")
	check(Prices.value_of(&"m4a1", 1, inv.state_of(&"primary")) > bare_value, "and worth more")

	# It travels with the gun: stowed and drawn, saved and loaded, replicated.
	player._server_inventory_action.rpc_id(1, "stow_slot", &"", -1, &"primary", &"")
	await _frames(2)
	var stowed := _find(inv, &"m4a1")
	check(stowed[1] >= 0 and String(inv.containers[stowed[0]][stowed[1]].get("state", {}).get("underbarrel", "")) == "grip_vertical", "stowed, the M4 keeps its grip")
	if stowed[1] >= 0:
		player._server_inventory_action.rpc_id(1, "equip_entry", stowed[0], stowed[1], &"", &"")
		await _frames(2)
	check(inv.slots[&"primary"] == &"m4a1" and GunAttachments.mounted_id(m4, inv.state_of(&"primary"), GunAttachments.UNDERBARREL) == &"grip_vertical", "drawn again, the grip's still on")
	player.active_slot = &"primary"
	var saved: Variant = JSON.parse_string(JSON.stringify(Roster.json_safe(inv.net_state)))
	var loaded := Inventory.new()
	add_child(loaded)
	loaded.net_state = GameState.from_json(saved)
	await _frames(1)
	check(GunAttachments.mounted_id(m4, loaded.state_of(&"primary"), GunAttachments.UNDERBARREL) == &"grip_vertical", "saved and loaded (JSON), the grip's on the gun")
	var copy := Inventory.new()
	add_child(copy)
	copy.net_state = inv.net_state
	await _frames(1)
	check(GunAttachments.all_of(m4, copy.state_of(&"primary")) == GunAttachments.all_of(m4, inv.state_of(&"primary")), "a peer's copy (net_state) has the same attachments")

	# The light.
	var light := _find(inv, &"light_weapon")
	player._server_inventory_action.rpc_id(1, "mount_attachment", light[0], light[1], &"primary", &"")
	await _frames(2)
	check(GunAttachments.mounted_id(m4, inv.state_of(&"primary"), GunAttachments.SIDE) == &"light_weapon", "the light goes on the M4's side rail")
	check(not GunAttachments.light_on(m4, inv.state_of(&"primary")) and not GunAttachments.lit(player), "switched off to begin with")
	check(InputMap.has_action(&"weapon_light"), "there's a weapon-light key (Controls)")
	player._server_inventory_action.rpc_id(1, "toggle_attachment", &"", -1, &"primary", &"")
	await _frames(3)
	var rig := player.camera.get_node_or_null(GunAttachments.RIG_NAME)
	check(GunAttachments.light_on(m4, inv.state_of(&"primary")) and GunAttachments.lit(player), "switched on, it gives him away")
	check(rig != null and rig.get_node(^"WeaponLight").visible, "the light shines from the gun")
	check(Spotting.LIT < 1.0 and Spotting.LIT_SIDE < 1.0, "a lit target is spotted sooner (x%.2f towards, x%.2f side)" % [Spotting.LIT, Spotting.LIT_SIDE])
	player.active_slot = &"sidearm"
	await _frames(2)
	check(not GunAttachments.lit(player) and rig != null and not rig.get_node(^"WeaponLight").visible, "the pistol in hand: no light")
	player.active_slot = &"primary"

	# A visible laser in its place.
	var laser := _find(inv, &"laser_visible")
	player._server_inventory_action.rpc_id(1, "mount_attachment", laser[0], laser[1], &"primary", &"")
	await _frames(2)
	check(GunAttachments.mounted_id(m4, inv.state_of(&"primary"), GunAttachments.SIDE) == &"laser_visible" and inv.count_of(&"light_weapon") == 1,
		"the laser goes on, the light back into his kit")
	check(GunAttachments.laser_beam(m4, inv.state_of(&"primary")) == "", "the laser goes on switched off")
	player._server_inventory_action.rpc_id(1, "toggle_attachment", &"", -1, &"primary", &"")
	await _frames(3)
	check(GunAttachments.laser_beam(m4, inv.state_of(&"primary")) == "visible" and rig.get_node(^"LaserBeam").visible and not rig.get_node(^"WeaponLight").visible,
		"switched on, its beam shows (no light)")
	var ir_now := _find(inv, &"laser_ir")
	player._server_inventory_action.rpc_id(1, "mount_attachment", ir_now[0], ir_now[1], &"primary", &"")
	player._server_inventory_action.rpc_id(1, "toggle_attachment", &"", -1, &"primary", &"")
	await _frames(3)
	check(GunAttachments.ir_on(player) and not GunAttachments.lit(player) and not rig.get_node(^"LaserBeam").visible, "an IR laser on: not seen by the naked eye")
	player._server_inventory_action.rpc_id(1, "remove_attachment", &"", -1, &"primary", GunAttachments.SIDE)
	await _frames(2)
	check(GunAttachments.mounted_id(m4, inv.state_of(&"primary"), GunAttachments.SIDE) == &"" and not inv.state_of(&"primary").has(GunAttachments.ON_KEY), "the IR laser off the gun (and nothing left switched on)")

	# A suppressed shot.
	check(SquadAI.HEAR_SUPPRESSED_M < SquadAI.HEAR_SHOT_M and Alert.SUPPRESSED_HEARD_M < Alert.SHOT_HEARD_M,
		"the AI hears a suppressed shot at a shorter range (%d m, not %d)" % [int(SquadAI.HEAR_SUPPRESSED_M), int(SquadAI.HEAR_SHOT_M)])
	inv.take(&"suppressor_rifle")
	var sup := _find(inv, &"suppressor_rifle")
	player._server_inventory_action.rpc_id(1, "mount_suppressor", sup[0], sup[1], &"primary", &"")
	await _frames(2)
	check(GunAttachments.all_of(m4, inv.state_of(&"primary")).muzzle == "suppressor_rifle", "a suppressor on the muzzle")
	var eye := player.camera.global_position
	player._server_fire.rpc_id(1, eye, -player.camera.global_basis.z, &"primary")
	await _frames(2)
	check(player.last_shot_at > -1000.0 and player.last_shot_suppressed, "his shot goes off suppressed (heard to %d m, flash x%.1f)" % [int(SquadAI.HEAR_SUPPRESSED_M), Spotting.SUPPRESSED_FLASH])

	# Optic zoom.
	inv.take(&"optic_prism_4x")
	var dot_fov := GunSight.aimed_fov_of(player, m4, 75.0)
	var prism := _find(inv, &"optic_prism_4x")
	player._server_inventory_action.rpc_id(1, "mount_optic", prism[0], prism[1], &"primary", &"")
	await _frames(2)
	var prism_fov := GunSight.aimed_fov_of(player, m4, 75.0)
	check(GunSight.optic_of(player) != null and GunSight.optic_of(player).id == &"optic_prism_4x", "a 4x prism on the rail")
	check(prism_fov < dot_fov * 0.5, "it zooms the aimed view in (%.1f deg against the red dot's %.1f)" % [prism_fov, dot_fov])

	# The grip off.
	player._server_inventory_action.rpc_id(1, "remove_attachment", &"", -1, &"primary", GunAttachments.UNDERBARREL)
	await _frames(2)
	check(GunAttachments.mounted_id(m4, inv.state_of(&"primary"), GunAttachments.UNDERBARREL) == &"" and inv.count_of(&"grip_vertical") == 1, "the grip comes off, back into his kit")
	check(absf(_kick_of(m4) - kick_bare) < 0.0001, "the kick's back to full")
	player._server_inventory_action.rpc_id(1, "remove_attachment", &"", -1, &"primary", GunAttachments.UNDERBARREL)
	await _frames(2)
	check(inv.count_of(&"grip_vertical") == 1, "taking off what isn't there does nothing")
	loaded.queue_free()
	copy.queue_free()
	await _test_m320(m4)
	await _test_choke()


## The 870's choke (one 12-gauge system, 2026-10-21): it goes on the Remington 870 the way any
## attachment does (the inventory's mount), shows among the gun's attachments, and the host
## refuses it on any other gun.
func _test_choke() -> void:
	var inv := player.inventory
	var was: StringName = inv.slots[&"primary"]
	var was_state := inv.state_of(&"primary").duplicate(true)
	inv.slots[&"primary"] = &""
	inv.take(&"mossberg590")
	inv.take(&"choke_870")
	var c := _find(inv, &"choke_870")
	player._server_inventory_action.rpc_id(1, "mount_attachment", c[0], c[1], &"primary", &"")
	await _frames(2)
	check(GunAttachments.mounted_id(ItemDB.get_item(&"mossberg590"), inv.state_of(&"primary"), GunAttachments.CHOKE) == &"" and inv.count_of(&"choke_870") == 1,
		"the host refuses the 870's choke on a Mossberg")
	inv.slots[&"primary"] = &""
	inv.take(&"rem870")
	var rem := ItemDB.get_item(&"rem870")
	c = _find(inv, &"choke_870")
	player._server_inventory_action.rpc_id(1, "mount_attachment", c[0], c[1], &"primary", &"")
	await _frames(2)
	check(GunAttachments.mounted_id(rem, inv.state_of(&"primary"), GunAttachments.CHOKE) == &"choke_870" and inv.count_of(&"choke_870") == 0
		and GunAttachments.all_of(rem, inv.state_of(&"primary")).choke == "choke_870" and Shotguns.spread_mult(rem, inv.state_of(&"primary")) < 0.6,
		"the choke goes on the Remington 870 like any attachment: %s" % GunAttachments.all_of(rem, inv.state_of(&"primary")))
	player._server_inventory_action.rpc_id(1, "remove_attachment", &"", -1, &"primary", GunAttachments.CHOKE)
	await _frames(2)
	check(GunAttachments.mounted_id(rem, inv.state_of(&"primary"), GunAttachments.CHOKE) == &"" and inv.count_of(&"choke_870") == 1, "and comes off, back into his kit")
	while inv.remove_one(&"choke_870"):
		pass
	inv.slots[&"primary"] = was
	inv.set_slot_state(&"primary", was_state)


## The M320 (Captain's list for cghath, 2026-10-20) on the underbarrel mount: it goes on and off
## like a grip, and the grenade loaded in it goes with it, off the gun, back on, swapped for the
## grip, and with the gun stowed and drawn.
func _test_m320(m4: ItemData) -> void:
	var inv := player.inventory
	inv.take(&"m320")
	var gl := _find(inv, &"m320")
	check(GunAttachments.mount_problem(inv, gl[0], gl[1], &"sidearm") != "", "no M320 on the pistol: %s" % GunAttachments.mount_problem(inv, gl[0], gl[1], &"sidearm"))
	player._server_inventory_action.rpc_id(1, "mount_attachment", gl[0], gl[1], &"primary", &"")
	await _frames(2)
	check(GunAttachments.mounted_id(m4, inv.state_of(&"primary"), GunAttachments.UNDERBARREL) == &"m320" and Underbarrel.loaded(inv.state_of(&"primary")) == &"",
		"the M320 goes on the M4's underbarrel mount, empty")
	check(InputMap.has_action(&"weapon_underbarrel") and Controls.on_pad(&"weapon_underbarrel"), "there's an underbarrel key, on the pad too (Controls)")
	var bare := MovementRules.weapon_mass(m4, inv.state_of(&"primary"))
	inv.set_slot_state(&"primary", Underbarrel.with_round(m4, inv.state_of(&"primary"), &"m406"))
	check(Underbarrel.loaded(inv.state_of(&"primary")) == &"m406" and GunAttachments.label(m4, inv.state_of(&"primary")).contains("M406")
		and MovementRules.weapon_mass(m4, inv.state_of(&"primary")) > bare, "an HE grenade in it: named on the gun, and the gun weighs it (%s)" % GunAttachments.label(m4, inv.state_of(&"primary")))
	player._server_inventory_action.rpc_id(1, "remove_attachment", &"", -1, &"primary", GunAttachments.UNDERBARREL)
	await _frames(2)
	var off := _find(inv, &"m320")
	var off_state: Dictionary = inv.containers[off[0]][off[1]].get("state", {}) if off[1] >= 0 else {}
	check(String(off_state.get("round", "")) == "m406" and GunAttachments.mounted_state(inv.state_of(&"primary"), GunAttachments.UNDERBARREL).is_empty(),
		"off the gun, it keeps its grenade (%s), and the gun keeps nothing of it" % [off_state])
	player._server_inventory_action.rpc_id(1, "mount_attachment", off[0], off[1], &"primary", &"")
	await _frames(2)
	check(GunAttachments.mounted_id(m4, inv.state_of(&"primary"), GunAttachments.UNDERBARREL) == &"m320" and Underbarrel.loaded(inv.state_of(&"primary")) == &"m406",
		"back on, still loaded")
	player._server_inventory_action.rpc_id(1, "stow_slot", &"", -1, &"primary", &"")
	await _frames(2)
	var stowed := _find(inv, &"m4a1")
	if stowed[1] >= 0:
		check(Underbarrel.loaded(inv.containers[stowed[0]][stowed[1]].get("state", {})) == &"m406", "the M4 stowed, its M320 still loaded")
		player._server_inventory_action.rpc_id(1, "equip_entry", stowed[0], stowed[1], &"", &"")
		await _frames(2)
	check(inv.slots[&"primary"] == &"m4a1" and Underbarrel.loaded(inv.state_of(&"primary")) == &"m406", "drawn again, loaded")
	var grip := _find(inv, &"grip_vertical")
	player._server_inventory_action.rpc_id(1, "mount_attachment", grip[0], grip[1], &"primary", &"")
	await _frames(2)
	var swapped := _find(inv, &"m320")
	check(GunAttachments.mounted_id(m4, inv.state_of(&"primary"), GunAttachments.UNDERBARREL) == &"grip_vertical" and swapped[1] >= 0
		and String(inv.containers[swapped[0]][swapped[1]].get("state", {}).get("round", "")) == "m406" and Underbarrel.loaded(inv.state_of(&"primary")) == &"",
		"a grip in its place: the M320 back in the kit with its grenade, none left on the gun")
	player._server_inventory_action.rpc_id(1, "remove_attachment", &"", -1, &"primary", GunAttachments.UNDERBARREL)
	await _frames(2)


## Picture-in-picture scopes (art task "PiP scopes"; GunSight.pip_wanted, pip_on): wanted only
## behind a magnified optic's glass while aimed, at the optic's power; never for a red dot or a
## holo at 1x; never headless (the whole view zooms behind the ring instead); off unaimed, on a
## weapon switch, dead, in a vehicle's seat and with the setting off. Forced on (a test-only
## switch, as it can't render headless), the picture renders at the optic's power and stops when
## it's no longer wanted.
func _test_pip() -> void:
	var inv := player.inventory
	var m4 := ItemDB.get_item(&"m4a1")
	var sight := GunSight.of(player)
	var settings := OS.get_user_data_dir().path_join("test_pip_settings%s.cfg" % OS.get_environment("CONTRACTOR_TEST_TAG"))
	DirAccess.remove_absolute(settings)
	GameSettings.use_file(settings)  # never the player's
	player.player_input.set_physics_process(false)  # it would lower the aim (no mouse here)
	player.active_slot = &"primary"
	var mount := func(id: StringName) -> void:
		inv.set_slot_state(&"primary", Optics.with_optic(m4, inv.state_of(&"primary"), id))
	check(String(GameSettings.DEFAULTS.video.scope_pip) != "off" and GameSettings.scope_pip_scale() > 0.0, "PiP scopes are on by default (%s)" % GameSettings.DEFAULTS.video.scope_pip)

	mount.call(&"optic_prism_4x")
	_aim(true)
	check(GunSight.pip_wanted(player) and absf(GunSight.glass_power(player) - 4.0) < 0.01,
		"aimed through the 4x prism: its picture-in-picture, at 4x (%.2f)" % GunSight.glass_power(player))
	await _frames(2)
	check(not GunSight.pip_on(player) and not sight.pip_rendering() and sight.pip_camera() == null,
		"headless: no scope picture made (the whole view zooms behind the ring instead)")
	_aim(false)
	check(not GunSight.pip_wanted(player), "lowered: none")
	mount.call(&"optic_red_dot")
	_aim(true)
	check(not GunSight.pip_wanted(player), "a red dot: none (it stays an open sight)")
	mount.call(&"optic_holo")
	_aim(true)
	var holo_1x := GunSight.pip_wanted(player)
	GunSight.zoom_step(player, 1)
	_aim(true)
	check(not holo_1x and GunSight.pip_wanted(player) and absf(GunSight.glass_power(player) - 3.0) < 0.01,
		"a holo: none at 1x, its magnifier's picture at 3x once that's up (%.2f)" % GunSight.glass_power(player))
	GunSight.zoom_step(player, -1)
	mount.call(&"optic_dmr_3_5_10")
	_aim(true)
	var at_start := GunSight.glass_power(player)
	GunSight.zoom_step(player, 1)
	_aim(true)
	check(GunSight.pip_wanted(player) and absf(at_start - 6.0) < 0.01 and absf(GunSight.glass_power(player) - 7.5) < 0.01,
		"the 3.5-10x: its picture at 6x, 7.5x a step up (%.2f, %.2f)" % [at_start, GunSight.glass_power(player)])
	GameSettings.set_value("video", "scope_pip", "off")
	check(GunSight.scoped(player) and not GunSight.pip_wanted(player), "the setting off: behind the glass, but no picture")
	GameSettings.set_value("video", "scope_pip", "medium")

	if not DevTools.on():
		print("  [skip] the scope picture's own render (forcing it is test-only: DevTools.on() is off)")
	else:
		GunSight.force_pip_for_tests(true)
		mount.call(&"optic_prism_4x")
		_aim(true)
		await _frames(2)
		var cam := sight.pip_camera()
		var lens := 2.0 * float(ItemDB.get_item(&"optic_prism_4x").stats.ring)  # the lens across, a share of the screen's height
		var shown := lens * tan(deg_to_rad(GameSettings.view_fov() * 0.5)) / tan(deg_to_rad(cam.fov * 0.5)) if cam else 0.0
		check(sight.pip_rendering() and cam != null and absf(shown - 4.0) < 0.02 and cam.global_position.distance_to(player.camera.global_position) < 0.001
			and cam.cull_mask & PlayerInput.VIEW_MODEL_LAYER == 0,
			"forced on: the 4x picture renders from the eye, 4x the unaimed view (%.2f), without the gun in it" % shown)
		var vp := cam.get_viewport() as SubViewport if cam else null
		check(vp != null and vp.size.x >= GunSight.SCOPE_MIN_PX and vp.size.x <= GunSight.SCOPE_MAX_PX and vp.world_3d == null and not vp.own_world_3d,
			"its viewport %s, sharing the level's world" % (vp.size if vp else Vector2i.ZERO))
		await _pip_stops(sight, "lowered", func() -> void: _aim(false), func() -> void: pass)
		await _pip_stops(sight, "on a switch to the sidearm", func() -> void: player.active_slot = &"sidearm", func() -> void: player.active_slot = &"primary")
		await _pip_stops(sight, "dead, waiting to respawn", func() -> void: player.respawn_state = Soldier.RESPAWN_WAITING,
			func() -> void: player.respawn_state = Soldier.RESPAWN_NONE)
		await _pip_stops(sight, "with the setting off", func() -> void: GameSettings.set_value("video", "scope_pip", "off"),
			func() -> void: GameSettings.set_value("video", "scope_pip", "medium"))
		var layer := level.get_node_or_null(^"Vehicles")
		var rides: Array = layer.get_children().filter(func(v: Node) -> bool: return v is Vehicle) if layer else []
		var ride: Array[Vehicle] = []  # the one he got into (a lambda can't set a local)
		var get_in := func() -> void:
			for v: Vehicle in rides:
				if v.server_enter(player, 0):
					ride.append(v)
					return
		var get_out := func() -> void:
			if not ride.is_empty():
				ride[0].server_exit(player)
		await _pip_stops(sight, "at the wheel of a vehicle", get_in, get_out)
		check(not ride.is_empty(), "(a vehicle on the range he could get into)")
		await _wait_for(func() -> bool: return not is_instance_valid(player.vehicle), 3.0)
		GunSight.force_pip_for_tests(false)
	_aim(false)
	player.player_input.set_physics_process(true)
	GameSettings.use_file("")
	DirAccess.remove_absolute(settings)


## Aims `player` (or lowers), up to the eye at once: the sight's glass eased straight to its
## target (the real ease takes a while).
func _aim(on: bool) -> void:
	player.is_aiming = on
	if on:
		GunSight.ease_glass(player, GunSight.aimed_fov_of(player, player.active_weapon(), GameSettings.view_fov()), 1.0)


## Aimed with the scope picture rendering (forced on), `change` stops it within a couple of
## frames (what: when); `undo` puts things back.
func _pip_stops(sight: GunSight, what: String, change: Callable, undo: Callable) -> void:
	_aim(true)
	await _frames(2)
	var was := sight.pip_rendering()
	change.call()
	await _frames(3)
	_aim(player.is_aiming)  # still holding aim, where that's up to him
	await _frames(1)
	var picture := sight.get_node_or_null(^"ScopePicture") as Control
	check(was and not sight.pip_rendering() and picture != null and not picture.visible, "the scope picture stops rendering %s" % what)
	undo.call()
	await _frames(2)


## Degrees the view kicks up for one shot of `weapon`, from level.
func _kick_of(weapon: ItemData) -> float:
	player.set_pitch(0.0)
	player._kick(weapon)
	var up := rad_to_deg(player.head.rotation.x)
	player.set_pitch(0.0)
	player.recoil_return = 0.0
	player.recoil_heat = 0.0
	return up


func _find(inv: Inventory, id: StringName) -> Array:
	for c in inv.search_containers():
		var list: Array = inv.containers.get(c, [])
		for i in list.size():
			if StringName(list[i].id) == id:
				return [c, i]
	return [&"", -1]


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _finish() -> void:
	GameState.delete_save()
	print("ATTACHMENTS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
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
