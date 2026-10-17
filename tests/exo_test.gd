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
## - its Steel III++ pads (shoulders, forearms, thighs, shins, stomach, spine pack) are real
##   armour: a III++ round fired at one stops there (a dent in the pad's state, an impact, no
##   wound), an AP round (IV) goes through it into the leg; the wearer's own shots skip them;
##   they're spall-coated, and the frame keeps spall off the arms and neck;
## - taken off, the art and pads go, the pads' damage with the frame.
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
	check(absf(total - bare_load - 14.0) < 0.01, "it weighs 14 kg with its pads (%.1f -> %.1f kg)" % [bare_load, total])
	check(ExoFrame.working(inv) and absf(player.load_kg - maxf(total - 30.0, 0.0)) < 0.01, "working, it carries 30 kg: the legs feel %.1f of %.1f kg" % [player.load_kg, total])
	var parts := _parts()
	check(parts.size() >= 25, "its struts, hinges, cuffs, spine pack and pylons are on the body (%d parts)" % parts.size())
	check(_light_is(ExoFrame.LIGHT_ON), "the status light is green")
	await _test_pads()
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
	check(gear.pads().is_empty() and not (off.get("state", {}).get("pads", {}) as Dictionary).is_empty(),
		"and its pads, their damage going with the frame (%s)" % ", ".join(PackedStringArray((off.get("state", {}).get("pads", {}) as Dictionary).keys())))
	return true


## The pads: real armour on the body (VoxelArmor, ArmorRules), not just art.
func _test_pads() -> void:
	var inv := player.inventory
	var gear := player.get_node(^"Gear") as GearRig
	var pads := gear.pads()
	check(pads.size() == 10, "ten armour pads on the body (%s)" % ", ".join(PackedStringArray(pads.keys())))
	var thigh: VoxelArmor = pads.get("thigh_r")
	var spine: VoxelArmor = pads.get("spine")
	if thigh == null or spine == null:
		return
	check(ArmorRules.rating(thigh.item) == &"III++" and ArmorRules.material(thigh.item) == ArmorRules.STEEL and thigh.item.stats.get("spall_coated", false),
		"rated III++, steel, spall-coated")
	check(thigh.get_parent() == player.model.part_node(Vitals.THIGH_R) and thigh.body_part == Vitals.THIGH_R, "the thigh pad rides on the thigh")
	var rids := gear.armor_rids()
	check(pads.values().all(func(p: VoxelArmor) -> bool: return p.get_rid() in rids), "the wearer's own shots skip them")
	var covered := ArmorRules.spall_cover_of(player)
	check("arms" in covered and "neck" in covered, "the frame keeps spall off the arms and neck (%s)" % [covered])
	await get_tree().physics_frame
	await get_tree().physics_frame
	var shooter := StaticBody3D.new()
	add_child(shooter)
	var m855 := ItemData.from_dict({"id": "test_exo_m855", "type": "weapon", "stats": {"round": "556_m855", "damage": 30}})
	var ap := ItemData.from_dict({"id": "test_exo_ap", "type": "weapon", "stats": {"threat": "IV", "round_class": String(Vitals.INTERMEDIATE), "damage": 30}})
	player.vitals.server_reset_health()
	# From the side, into the thigh pad's outer wall; then from behind, into the spine pack's.
	var side_on := thigh.to_global(Vector3(0.6, 0.02, 0.0))
	var side := Ballistics.fire(shooter, side_on, -thigh.global_basis.x, m855)
	await _frames(2)
	check(side.result == "plate", "M855 (III++) from the side stops on the thigh pad (%s)" % side.result)
	check(inv.chips_in(ExoFrame.SLOT, "thigh_r").size() == 1 and ArmorRules.integrity(ExoFrame.pad_state(inv, "thigh_r")) < 1.0,
		"a dent in the pad's own state, its integrity down (%s)" % [ExoFrame.pad_state(inv, "thigh_r").get("integrity", 1.0)])
	check(not player.vitals.wound_list().any(func(w: Dictionary) -> bool: return w.part == Vitals.THIGH_R), "no wound in the thigh behind it")
	var back := Ballistics.fire(shooter, spine.to_global(Vector3(0.0, 0.05, -0.6)), spine.global_basis.z, m855)
	await _frames(2)
	check(back.result == "plate" and inv.chips_in(ExoFrame.SLOT, "spine").size() == 1, "and from behind on the spine pack's pad (%s)" % back.result)
	check(gear.armor_summary().contains("Pads III++"), "the armour readout shows the pads (%s)" % gear.armor_summary())
	# AP (IV) goes through the pad into the leg.
	var through := Ballistics.fire(shooter, thigh.to_global(Vector3(0.6, -0.06, 0.0)), -thigh.global_basis.x, ap)
	await _frames(2)
	var holes: Array = inv.chips_in(ExoFrame.SLOT, "thigh_r").filter(func(c: Array) -> bool: return int(c[4]) == VoxelArmor.HOLE)
	check(through.result == "body" and holes.size() == 1, "an AP round (IV) goes through it (%s, %d hole)" % [through.result, holes.size()])
	check(player.vitals.wound_list().any(func(w: Dictionary) -> bool: return w.part == Vitals.THIGH_R), "into the thigh")
	player.vitals.server_reset_health()
	shooter.queue_free()


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
