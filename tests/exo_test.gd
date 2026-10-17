extends Node
## The light exo frame (ExoFrame; Captain 2026-10-16: frame slot over the vest, weight assist,
## the frame takes rounds and can be disabled, its art on the body). On the vehicle range, the
## host's player puts on an LX-3 Assist Frame:
## - it goes into the "exo" slot over the rest (the vest and plates stay worn);
## - working, the legs carry 30 kg less (Soldier.load_kg);
## - its struts are drawn on the arms, legs and back, the status light green;
## - a round into a thigh can strike its strut: the frame wears down, the round is slowed;
## - into the chest from the front it can't; into the back from behind the spine pack can;
## - worn down to nothing it's disabled: the whole load is back on the legs, the readout says
##   so, the light goes red, and further rounds don't strike it;
## - taken off, the art goes.
##   <godot> --headless --path . res://tests/exo_test.tscn

var failures := 0
var level: VehicleRange
var main: Node
var player: Soldier


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_exo" + tag
	Campaign.campaign_id = "test_exo" + tag
	CompoundLevel.spawn_ai = false
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("EXO TEST FAILED (timed out)")
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
	_finish_after(await _run())


func _run() -> bool:
	var inv := player.inventory
	var vest_before: StringName = inv.slots[&"vest"]
	var bare_load := player.load_kg
	check(inv.take(&"exo_frame_light") == 1, "the LX-3 Assist Frame goes on")
	await _frames(3)
	check(inv.slots[ExoFrame.SLOT] == &"exo_frame_light" and inv.slots[&"vest"] == vest_before, "it's in the exo slot, over the vest (%s, vest %s)" % [inv.slots[ExoFrame.SLOT], inv.slots[&"vest"]])
	var total := inv.total_mass()
	check(absf(total - bare_load - 9.0) < 0.01, "it weighs 9 kg (%.1f -> %.1f kg)" % [bare_load, total])
	check(ExoFrame.working(inv) and absf(player.load_kg - maxf(total - 30.0, 0.0)) < 0.01, "working, it carries 30 kg: the legs feel %.1f of %.1f kg" % [player.load_kg, total])
	var parts := _parts()
	check(parts.size() >= 25, "its struts, hinges, cuffs, spine pack and pylons are on the body (%d parts)" % parts.size())
	check(_light_is(ExoFrame.LIGHT_ON), "the status light is green")
	# Struck in the thigh.
	ExoFrame.roll_override = 0.0
	var hit := {"energy_j": 1700.0, "round_class": Vitals.INTERMEDIATE, "direction": player.global_basis.x}
	check(ExoFrame.server_round(player, &"thigh_l", hit), "a round into the thigh strikes its strut")
	await _frames(2)
	var after_one := ExoFrame.integrity(inv)
	check(after_one < 1.0 and after_one > 0.5, "it wears down (%d%%)" % roundi(after_one * 100.0))
	check(absf(float(hit.energy_j) - 1700.0 * (1.0 - ExoFrame.STRUT_ENERGY_LOSS)) < 0.5, "the round goes on, slowed (%.0f J)" % float(hit.energy_j))
	var front := {"energy_j": 1700.0, "round_class": Vitals.INTERMEDIATE, "direction": player.global_basis.z}  # towards his front: from ahead
	check(not ExoFrame.server_round(player, Vitals.CHEST, front), "into the chest from the front: no strut in the way")
	var behind := {"energy_j": 1700.0, "round_class": Vitals.INTERMEDIATE, "direction": -player.global_basis.z}  # the way he faces: from behind
	check(ExoFrame.server_round(player, Vitals.CHEST, behind), "into the back from behind: the spine pack takes it")
	# Worn down to nothing.
	for i in 10:
		if not ExoFrame.working(inv):
			break
		ExoFrame.server_round(player, &"shin_r", {"energy_j": 1700.0, "round_class": Vitals.INTERMEDIATE, "direction": player.global_basis.x})
	await _frames(3)
	check(not ExoFrame.working(inv) and bool(inv.state_of(ExoFrame.SLOT).get("disabled", false)), "worn down, it's disabled")
	check(absf(player.load_kg - inv.total_mass()) < 0.01, "disabled, the legs carry it all again (%.1f of %.1f kg)" % [player.load_kg, inv.total_mass()])
	check(ExoFrame.summary(inv) == "Frame DISABLED", "the readout says so (%s)" % ExoFrame.summary(inv))
	var gear := player.get_node_or_null(^"Gear") as GearRig
	check(gear != null and gear.armor_summary().begins_with("Frame DISABLED"), "the armour summary leads with it (%s)" % (gear.armor_summary() if gear else "no rig"))
	await _frames(2)
	check(_light_is(ExoFrame.LIGHT_OFF), "the status light is red")
	check(not ExoFrame.server_round(player, &"thigh_r", {"energy_j": 1700.0, "round_class": Vitals.INTERMEDIATE}), "a disabled frame isn't struck again")
	ExoFrame.roll_override = NAN
	# Off again.
	var off := inv.unequip(ExoFrame.SLOT)
	await _frames(3)
	check(String(off.get("id", "")) == "exo_frame_light" and bool(off.get("state", {}).get("disabled", false)), "it comes off, still disabled (the damage travels with it)")
	check(inv.slots[ExoFrame.SLOT] == &"" and _parts().is_empty(), "taken off, the frame's art goes (%d parts left)" % _parts().size())
	return true


func _parts() -> Array:
	return player.get_node(^"Model").find_children(ExoFrame.PART_NAME + "*", "", true, false).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())


func _light_is(colour: Color) -> bool:
	for n: Node in _parts():
		var m := n as MeshInstance3D
		if m and (m.mesh as BoxMesh).size.x < 0.03 and (m.material_override as StandardMaterial3D).albedo_color.is_equal_approx(colour):
			return true
	return false


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _finish_after(_ok: bool) -> void:
	_finish()


func _finish() -> void:
	ExoFrame.roll_override = NAN
	GameState.delete_save()
	print("EXO TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
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
