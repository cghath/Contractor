extends Node3D
## Headless checks for armor and ballistics: the NIJ-named ladder for every round against
## every helmet, plate and vest, ceramic crack zones and shattering, steel spall by vest tier,
## soft armor, plate fit, armor state that travels with the item, energy falling with range,
## and the impact that every stop lands on the wearer. Run from the project folder with:
##   <voxel godot exe> --headless --path . res://tests/armor_test.tscn
## Exits with the number of failures as the process exit code.

const DUMMY := preload("res://scenes/target_dummy.tscn")
const PROBE := preload("res://tests/armor_probe_vitals.gd")

## The design doc's ladder: each round's threat level.
const ROUND_LEVELS := {
	"9x19_fmj": "IIA", "45acp_fmj": "IIA", "12g_buck": "IIA", "9x19_hot": "II", "357mag": "II",
	"44mag": "IIIA", "10mm_fmj": "IIIA", "357sig_fmj": "IIIA", "12g_slug": "IIIA", "556_m193": "III",
	"762x39_msc": "III+", "762x51_m80": "III+", "556_m855": "III++", "762x54r_lps": "III++",
	"556_m995": "IV", "762x51_m993": "IV", "3006_m2ap": "IV", "50bmg_m33": "ABOVE_IV",
}
## Each armor piece's rating.
const PIECE_RATINGS := {
	"helmet_bump": "IIA", "helmet": "IIIA", "helmet_heavy": "III++",
	"plate_pe_l3": "III", "plate_steel_l3": "III++", "plate_ceramic_l4": "IV", "plate_side": "III++",
}
## Each vest's soft armor (aramid) rating.
const VEST_RATINGS := {"plate_carrier_light": "IIA", "plate_carrier": "IIIA", "plate_carrier_heavy": "IIIA"}
const ARMS: Array[StringName] = [Vitals.UPPER_ARM_L, Vitals.UPPER_ARM_R, Vitals.FOREARM_L, Vitals.FOREARM_R]

var failures := 0
var _shooter: StaticBody3D


func _ready() -> void:
	GameState.zone_id = "test_armor" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	ArmorRules.seed_rng(20261010)
	_shooter = StaticBody3D.new()
	add_child(_shooter)
	_test_rounds()
	_test_energy()
	await _test_ladder()
	await _test_range()
	await _test_ceramic()
	await _test_steel_spall()
	await _test_soft_armor()
	await _test_helmet_impact()
	_test_fit()
	await _test_state_travels()
	print("ARMOR TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- Helpers ----------------------------------------------------------------------------------

## A weapon that fires `round_id` (a data/rounds.json id).
func _gun(round_id: String, wear := 1.0) -> ItemData:
	return ItemData.from_dict({"id": "test_gun_" + round_id, "type": "weapon", "stats": {"round": round_id, "plate_wear": wear, "damage": 30}})


func _carrier_for(plate: ItemData) -> StringName:
	if plate.id == &"plate_pe_l3":
		return &"plate_carrier_light"
	return &"plate_carrier_heavy" if plate.slot == &"side_plate" else &"plate_carrier"


## A piece of armor worn in its own Inventory, with nobody inside (no impacts).
func _piece(id: StringName, state := {}) -> VoxelArmor:
	var item := ItemDB.get_item(id)
	var inv := Inventory.new()
	add_child(inv)
	var slot := &"helmet"
	if item.is_plate():
		inv.take(_carrier_for(item))
		slot = &"plate_left" if item.slot == &"side_plate" else &"plate_front"
	inv.take(id, 1, state)
	var piece := VoxelArmor.new()
	inv.add_child(piece)
	piece.setup(item, slot, inv, 1)
	return piece


## Where a round hits the middle of a loose piece's strike face (it travels +Z).
func _front_of(piece: VoxelArmor) -> Vector3:
	if piece.slot == &"helmet":
		return Vector3(0, 0.08, -VoxelArmor.size_m(piece.item).z * 0.5)
	return Vector3(0, 0, -0.01)


## A target dummy wearing `loadout`, with a Vitals that records impacts and hits.
func _dummy(loadout: Array) -> TargetDummy:
	var dummy: TargetDummy = DUMMY.instantiate()
	dummy.loadout = PackedStringArray(loadout)
	dummy.get_node(^"Vitals").set_script(PROBE)
	add_child(dummy)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return dummy


## Impacts the dummy's probe Vitals recorded ({"part", "round_class", "distance", "energy_j"}).
func _impacts(dummy: TargetDummy) -> Array[Dictionary]:
	return dummy.vitals.get(&"impacts")


## Hits the dummy's probe Vitals recorded ({"part", "hit"}).
func _hits(dummy: TargetDummy) -> Array[Dictionary]:
	return dummy.vitals.get(&"hits")


func _worn(dummy: TargetDummy, slot: StringName) -> VoxelArmor:
	for piece: VoxelArmor in dummy.find_children("*", "VoxelArmor", true, false):
		if piece.slot == slot:
			return piece
	return null


func _fire_at(height: float, weapon: ItemData, x := 0.0) -> Dictionary:
	_shooter.position = Vector3(x, height, -5)  # dummies face -Z: stand in front
	return Ballistics.fire(_shooter, _shooter.position, Vector3.BACK, weapon)


# --- Rounds and ballistics --------------------------------------------------------------------

func _test_rounds() -> void:
	print("Rounds and threat levels")
	var wrong := PackedStringArray()
	for id: String in ROUND_LEVELS:
		var data := Ballistics.round_data(id)
		if data.is_empty() or String(data.level) != ROUND_LEVELS[id]:
			wrong.append(id)
	check(wrong.is_empty(), "every round sits at its ladder level (wrong: %s)" % ", ".join(wrong))
	check(Ballistics.round_ids().size() == ROUND_LEVELS.size(), "%d rounds in data" % Ballistics.round_ids().size())
	for expect: Array in [[&"mag_9mm", "9x19_fmj"], [&"mag_556", "556_m855"], [&"mag_762", "762x51_m80"]]:
		check(Ballistics.round_data(ItemDB.get_item(expect[0])).get("id", "") == expect[1], "%s holds %s" % expect)
	for expect: Array in [[&"m17", &"IIA", Vitals.PISTOL], [&"m4a1", &"III++", Vitals.INTERMEDIATE],
			[&"mk18", &"III++", Vitals.INTERMEDIATE], [&"m110", &"III+", Vitals.FULL_POWER]]:
		var weapon := ItemDB.get_item(expect[0])
		check(Ballistics.threat_level(weapon) == expect[1] and Ballistics.round_class(weapon) == expect[2],
			"%s fires %s (%s, %s)" % [expect[0], Ballistics.round_data(weapon).get("name", "?"), Ballistics.threat_level(weapon), Ballistics.round_class(weapon)])
	var custom := ItemData.from_dict({"id": "test_override", "type": "weapon", "stats": {"ammo": "mag_556", "threat": "IV", "round_class": "full_power"}})
	check(Ballistics.threat_level(custom) == &"IV" and Ballistics.round_class(custom) == Vitals.FULL_POWER, "weapon stats can still override the round")


func _test_energy() -> void:
	print("Energy and velocity with range")
	var m4 := ItemDB.get_item(&"m4a1")
	var muzzle := Ballistics.energy_at(m4, 0.0)
	check(absf(muzzle - 0.5 * 0.00402 * 910.0 * 910.0) < 1.0, "M4 M855 muzzle energy %.0f J" % muzzle)
	var falling := true
	var last := INF
	var text := PackedStringArray()
	for d: float in [0.0, 50.0, 100.0, 200.0, 300.0, 600.0]:
		var e := Ballistics.energy_at(m4, d)
		falling = falling and e < last
		last = e
		text.append("%d m %.0f J" % [d, e])
	check(falling, "energy falls with range (%s)" % ", ".join(text))
	var v100 := Ballistics.velocity_at(m4, 100.0)
	check(v100 > 760.0 and v100 < 850.0, "M855 slows to %.0f m/s at 100 m (ACE3 ~800)" % v100)
	var pistol := Ballistics.energy_at(ItemDB.get_item(&"m17"), 0.0)
	check(pistol > 450.0 and pistol < 650.0, "9mm muzzle energy %.0f J" % pistol)
	check(Ballistics.velocity_at("9x19_fmj", 50.0) < Ballistics.velocity_at("9x19_fmj", 0.0), "pistol rounds slow down too")
	var m80 := Ballistics.energy_at(ItemDB.get_item(&"m110"), 0.0)
	var bmg := Ballistics.energy_at("50bmg_m33", 0.0)
	check(m80 > muzzle and bmg > 15000.0, "7.62 M80 %.0f J and .50 BMG %.0f J outhit 5.56" % [m80, bmg])
	check(Ballistics.velocity_at(m4, 0.0) > Ballistics.velocity_at(ItemDB.get_item(&"mk18"), 0.0), "the short Mk18 barrel is slower than the M4's")
	check(Ballistics.energy_at(ItemDB.get_item(&"breaching_charge"), 10.0) < 0.0, "unknown round: energy -1")
	check(Ballistics.threat_level_at(m4, 50.0) == &"III++" and Ballistics.threat_level_at(m4, 300.0) == &"III",
		"M855 counts as III++ close, III far (%.0f m/s at 300 m)" % Ballistics.velocity_at(m4, 300.0))
	var m110 := ItemDB.get_item(&"m110")
	check(Ballistics.threat_level_at(m110, 300.0) == &"III+", "M80 ball keeps its level")


# --- The ladder -------------------------------------------------------------------------------

func _test_ladder() -> void:
	print("Ladder: every armor piece against every round")
	for id: String in PIECE_RATINGS:
		var item := ItemDB.get_item(StringName(id))
		check(ArmorRules.rating(item) == StringName(PIECE_RATINGS[id]), "%s is rated %s" % [item.name, ArmorRules.rating(item)])
		var wrong := PackedStringArray()
		var stopped := PackedStringArray()
		for round_id: String in ROUND_LEVELS:
			var piece := _piece(StringName(id))
			var expect: bool = Ballistics.level_index(StringName(ROUND_LEVELS[round_id])) <= Ballistics.level_index(StringName(PIECE_RATINGS[id]))
			var got := piece.server_try_stop(_front_of(piece), Vector3.BACK, _gun(round_id), 5.0)
			if got != expect:
				wrong.append("%s %s" % [round_id, "stopped" if got else "through"])
			if got:
				stopped.append(round_id)
			piece.inventory.queue_free()
		check(wrong.is_empty(), "%s stops up to %s: %s%s" % [id, PIECE_RATINGS[id], ", ".join(stopped), "" if wrong.is_empty() else "  WRONG: " + ", ".join(wrong)])
		await get_tree().process_frame
	for id: String in VEST_RATINGS:
		var vest := ItemDB.get_item(StringName(id))
		var wrong := PackedStringArray()
		for round_id: String in ROUND_LEVELS:
			var expect: bool = Ballistics.level_index(StringName(ROUND_LEVELS[round_id])) <= Ballistics.level_index(StringName(VEST_RATINGS[id]))
			if ArmorRules.stops(ArmorRules.soft_rating(vest), StringName(ROUND_LEVELS[round_id])) != expect:
				wrong.append(round_id)
		check(ArmorRules.soft_rating(vest) == StringName(VEST_RATINGS[id]) and wrong.is_empty(), "%s soft armor is %s (wrong: %s)" % [id, ArmorRules.soft_rating(vest), ", ".join(wrong)])
	check(ArmorRules.stops(&"IIA", &"FRAGMENT") and not ArmorRules.stops(&"IV", &"ABOVE_IV"), "any rating stops fragments; nothing stops .50 BMG")


func _test_range() -> void:
	print("Level changes with range")
	var m4 := ItemDB.get_item(&"m4a1")
	var near := _piece(&"plate_pe_l3")
	check(not near.server_try_stop(_front_of(near), Vector3.BACK, m4, 20.0), "light PE plate (III): M855 goes through at 20 m")
	var far := _piece(&"plate_pe_l3")
	check(far.server_try_stop(_front_of(far), Vector3.BACK, m4, 280.0), "...but is stopped at 280 m, slowed below its steel-core velocity")
	var m193 := _piece(&"plate_pe_l3")
	check(m193.server_try_stop(_front_of(m193), Vector3.BACK, _gun("556_m193"), 20.0), "M193 ball is stopped at 20 m")
	for piece: VoxelArmor in [near, far, m193]:
		piece.inventory.queue_free()
	await get_tree().process_frame


# --- Ceramic ----------------------------------------------------------------------------------

func _test_ceramic() -> void:
	print("Ceramic: crack zones, integrity, shattering")
	var cell := Vector3i(12, 15, 0)
	check(is_equal_approx(ArmorRules.ceramic_stop_chance({}, cell), 1.0), "fresh plate: always stops what it's rated for")
	check(is_equal_approx(ArmorRules.ceramic_stop_chance({"cracks": [[14, 17, 0]]}, cell), 0.7), "inside one crack zone (3 cm away): 70%")
	check(is_equal_approx(ArmorRules.ceramic_stop_chance({"cracks": [[14, 17, 0], [10, 14, 1]]}, cell), 0.49), "inside two crack zones: 49%")
	check(is_equal_approx(ArmorRules.ceramic_stop_chance({"cracks": [[19, 15, 0]]}, cell), 1.0), "7 cm from a crack: not weakened")
	var plate := ItemDB.get_item(&"plate_ceramic_l4")
	for cracks: Array in [[[14, 17, 0]], [[14, 17, 0], [10, 14, 1]]]:
		var state := {"chips": [], "cracks": cracks}
		var stops := 0
		for i in 400:
			if ArmorRules.piece_stops(plate, state, cell, &"III++"):
				stops += 1
		var expect := pow(0.7, cracks.size())
		check(absf(stops / 400.0 - expect) < 0.08, "with %d earlier hit(s) nearby, %d of 400 rounds stopped (expect ~%d%%)" % [cracks.size(), stops, roundi(expect * 100.0)])
	check(not ArmorRules.piece_stops(plate, {"cracks": [[14, 17, 0]]}, cell, &"ABOVE_IV"), "a round above its rating always goes through")

	var piece := _piece(&"plate_ceramic_l4")
	var m110 := ItemDB.get_item(&"m110")
	var spots: Array[Vector3] = [Vector3(-0.08, -0.1, -0.01), Vector3(0.08, -0.1, -0.01), Vector3(-0.08, 0.1, -0.01), Vector3(0.08, 0.1, -0.01)]
	var integrity_after := PackedStringArray()
	var all_stopped := true
	for spot in spots:
		all_stopped = piece.server_try_stop(spot, Vector3.BACK, m110, 30.0) and all_stopped
		integrity_after.append("%.0f%%" % (ArmorRules.integrity(piece.inventory.state_of(&"plate_front")) * 100.0))
	var state := piece.inventory.state_of(&"plate_front")
	check(all_stopped, "four 7.62 hits spread out are stopped")
	check(ArmorRules.cracks(state).size() == 4, "each hit left a crack in the item state (%d)" % ArmorRules.cracks(state).size())
	check(ArmorRules.is_shattered(state), "integrity falls by round class until it shatters (%s)" % ", ".join(integrity_after))
	check(not piece.server_try_stop(Vector3(0, 0, -0.01), Vector3.BACK, ItemDB.get_item(&"m17"), 10.0), "a shattered plate doesn't even stop a pistol round")
	var light := _piece(&"plate_ceramic_l4")
	light.server_try_stop(Vector3(-0.08, -0.1, -0.01), Vector3.BACK, ItemDB.get_item(&"m17"), 10.0)
	light.server_try_stop(Vector3(0.08, 0.1, -0.01), Vector3.BACK, ItemDB.get_item(&"m4a1"), 10.0)
	var light_state := light.inventory.state_of(&"plate_front")
	check(is_equal_approx(ArmorRules.integrity(light_state), 1.0 - ArmorRules.INTEGRITY_LOSS[Vitals.PISTOL] - ArmorRules.INTEGRITY_LOSS[Vitals.INTERMEDIATE]),
		"a pistol and a 5.56 hit cost less than 7.62 (%.0f%% left)" % (ArmorRules.integrity(light_state) * 100.0))
	var steel := _piece(&"plate_steel_l3")
	steel.server_try_stop(Vector3(0, 0, -0.01), Vector3.BACK, m110, 10.0)
	check(not steel.inventory.state_of(&"plate_front").has("cracks"), "steel doesn't crack")
	check(steel.server_try_stop(Vector3(0.03, 0, -0.01), Vector3.BACK, m110, 10.0), "steel stops another hit 3 cm away")
	for p: VoxelArmor in [piece, light, steel]:
		p.inventory.queue_free()

	print("Ceramic: a shattered plate on a body, soft armor behind it")
	var dummy := await _dummy(["plate_carrier"])
	dummy.inventory.take(&"plate_ceramic_l4", 1, {"chips": [], "integrity": 0.0})
	await get_tree().physics_frame
	await get_tree().physics_frame
	var probe: Vitals = dummy.vitals
	var plate_y: float = GearRig.plate_rest_position(&"plate_front").y
	var shot := _fire_at(plate_y, ItemDB.get_item(&"m17"))
	check(shot.result == "plate" and not probe.wound_list().any(func(w: Dictionary) -> bool: return w.get("bleeding", false)), "the medium vest's aramid stops a pistol round behind the shattered plate (%s)" % shot.result)
	var impact: Dictionary = _impacts(dummy).back() if not _impacts(dummy).is_empty() else {}
	check(impact.get("part") == Vitals.CHEST and impact.get("round_class") == Vitals.PISTOL, "impact on the chest from a pistol round (%s)" % impact)
	check(dummy.inventory.chips_in(&"plate_front").size() == 1, "the round still holed the shattered plate")
	check(dummy.gear.armor_summary().contains("Front IV shattered"), "summary says so: %s" % dummy.gear.armor_summary())
	var rifle := _fire_at(plate_y, ItemDB.get_item(&"m4a1"), 0.05)
	check(rifle.result == "body" and not probe.wound_list().is_empty(), "a 5.56 round goes through plate and aramid (%s)" % rifle.result)
	dummy.queue_free()
	await get_tree().process_frame


# --- Steel spall ------------------------------------------------------------------------------

func _test_steel_spall() -> void:
	print("Steel spall by vest tier")
	var rifle := ItemDB.get_item(&"m4a1")
	var spots: Array[Vector2] = []
	for x: float in [-0.08, 0.0, 0.08]:
		for y: float in [-0.1, 0.0, 0.1]:
			spots.append(Vector2(x, y))
	for tier: Array in [["plate_carrier", "medium"], ["plate_carrier_heavy", "heavy"]]:
		var dummy := await _dummy([tier[0], "plate_steel_l3"])
		var probe: Vitals = dummy.vitals
		var piece := _worn(dummy, &"plate_front")
		var stopped := 0
		for spot in spots:
			if piece.server_try_stop(piece.to_global(Vector3(spot.x, spot.y, -0.01)), Vector3.BACK, rifle, 12.0):
				stopped += 1
		check(stopped == spots.size(), "%s: steel stopped all %d rounds" % [tier[1], stopped])
		var parts := {}
		var fragments := true
		for hit: Dictionary in _hits(dummy):
			parts[hit.part] = true
			fragments = fragments and hit.hit.get("round_class") == Vitals.FRAGMENT
		if tier[1] == "medium":
			var allowed := ARMS + [Vitals.FACE]
			check(not parts.is_empty() and parts.keys().all(func(p: StringName) -> bool: return p in allowed),
				"medium: spall wounds only face and arms, the collar covers the neck (%s)" % ", ".join(parts.keys()))
			check(fragments and _hits(dummy).size() >= spots.size() and _hits(dummy).size() <= spots.size() * ArmorRules.SPALL_WOUNDS_MAX,
				"medium: %d fragment wounds from %d stops" % [_hits(dummy).size(), spots.size()])
		else:
			check(_hits(dummy).is_empty(), "heavy: neck, face and arms covered, no spall wounds (%d)" % _hits(dummy).size())
		var chest := 0
		var abdomen := 0
		var sensible := _impacts(dummy).size() == spots.size()
		for impact: Dictionary in _impacts(dummy):
			chest += 1 if impact.part == Vitals.CHEST else 0
			abdomen += 1 if impact.part == Vitals.ABDOMEN else 0
			sensible = sensible and impact.round_class == Vitals.INTERMEDIATE and is_equal_approx(impact.distance, 12.0) \
				and absf(impact.energy_j - Ballistics.energy_at(rifle, 12.0)) < 0.5
		check(sensible and chest + abdomen == spots.size() and chest > 0 and abdomen > 0,
			"%s: every stop is an impact (chest %d, abdomen %d, %.0f J at 12 m)" % [tier[1], chest, abdomen, Ballistics.energy_at(rifle, 12.0)])
		if tier[1] == "medium":
			var coated_data := ItemDB.get_item(&"plate_steel_l3").stats.duplicate()
			coated_data["spall_coated"] = true
			var coated := ItemData.from_dict({"id": "test_steel_coated", "type": "plate", "slot": "plate", "stats": coated_data})
			var coated_piece := VoxelArmor.new()
			dummy.add_child(coated_piece)
			coated_piece.setup(coated, &"plate_back", dummy.inventory, 1)
			var before := _hits(dummy).size()
			check(coated_piece.server_try_stop(coated_piece.to_global(Vector3(0, 0, -0.01)), Vector3.BACK, rifle, 12.0) and _hits(dummy).size() == before,
				"an anti-spall coated steel plate throws no spall")
		dummy.queue_free()
	var light := ItemDB.get_item(&"plate_carrier_light")
	var exposed := ArmorRules.spall_parts(light)
	check(Vitals.NECK in exposed and Vitals.FACE in exposed and ARMS.all(func(p: StringName) -> bool: return p in exposed), "light vest: neck, face and arms all exposed to spall")
	check(ArmorRules.spall_parts(ItemDB.get_item(&"plate_carrier_heavy")).is_empty(), "heavy vest: nothing exposed")
	var body := await _dummy(["plate_carrier_light"])
	var parts := {}
	for i in 30:
		for part: StringName in ArmorRules.server_spall(body, body.vitals, body.global_position + Vector3.UP * 1.2, Vector3.BACK):
			parts[part] = true
	check(parts.has(Vitals.NECK) and parts.has(Vitals.FACE), "light vest: spall reaches the neck and face too (%s)" % ", ".join(parts.keys()))
	body.queue_free()
	await get_tree().process_frame


# --- Soft armor -------------------------------------------------------------------------------

func _test_soft_armor() -> void:
	print("Soft armor (aramid)")
	var light := await _dummy(["plate_carrier_light"])
	var medium := await _dummy(["plate_carrier"])
	var heavy := await _dummy(["plate_carrier_heavy"])
	var none := await _dummy(["helmet"])
	var front := Vector3.BACK      # the round travels +Z into a dummy facing -Z
	var back := Vector3.FORWARD
	var side := Vector3.RIGHT
	var cases := [
		[light, Vitals.CHEST, &"IIA", front, true, "light: 9mm to the chest front stopped"],
		[light, Vitals.CHEST, &"IIA", back, false, "light: front only, a 9mm in the back goes through"],
		[light, Vitals.ABDOMEN, &"IIA", front, false, "light: the abdomen isn't covered"],
		[light, Vitals.CHEST, &"II", front, false, "light: a .357 Magnum (II) goes through IIA"],
		[light, Vitals.CHEST, &"FRAGMENT", front, true, "light: fragments stopped at the front"],
		[light, Vitals.CHEST, &"FRAGMENT", side, false, "light: not at the side"],
		[medium, Vitals.ABDOMEN, &"IIIA", back, true, "medium: .44 Magnum to the lower back stopped"],
		[medium, Vitals.CHEST, &"IIIA", side, false, "medium: sides open"],
		[medium, Vitals.CHEST, &"III", front, false, "medium: rifle ball goes through aramid"],
		[medium, Vitals.THIGH_L, &"IIA", front, false, "medium: legs aren't covered"],
		[medium, Vitals.NECK, &"FRAGMENT", front, false, "medium: the neck has no aramid"],
		[heavy, Vitals.CHEST, &"IIIA", side, true, "heavy: sides covered too"],
		[heavy, Vitals.ABDOMEN, &"FRAGMENT", back, true, "heavy: fragments stopped at the back"],
		[heavy, Vitals.CHEST, &"III++", front, false, "heavy: M855 goes through aramid"],
		[none, Vitals.CHEST, &"FRAGMENT", front, false, "no vest: nothing stops it"],
	]
	for c: Array in cases:
		var body: TargetDummy = c[0]
		var before: int = _impacts(body).size()
		var got := VoxelArmor.soft_armor_stops(body, c[1], c[2], Vitals.PISTOL, 15.0, c[3], Vector3.INF, 300.0)
		var impacted: bool = _impacts(body).size() == before + 1
		check(got == c[4] and impacted == c[4], c[5])
	var last: Dictionary = _impacts(medium).back()
	check(last.part == Vitals.ABDOMEN and last.round_class == Vitals.PISTOL and is_equal_approx(last.distance, 15.0) and is_equal_approx(last.energy_j, 300.0),
		"a soft-armor stop is an impact on the part hit (%s)" % last)
	var chest := medium.global_position + Vector3(0, 0.9 + 0.4, -0.12)
	var thigh := medium.global_position + Vector3(0.1, 0.6, -0.12)
	check(VoxelArmor.soft_armor_stops(medium, Vitals.TORSO, &"IIA", Vitals.PISTOL, 5.0, front, chest), "a whole-torso hitbox hit at chest height is covered")
	check(not VoxelArmor.soft_armor_stops(medium, Vitals.TORSO, &"IIA", Vitals.PISTOL, 5.0, front, thigh), "...at thigh height it isn't")
	for body: TargetDummy in [light, medium, heavy, none]:
		body.queue_free()
	await get_tree().process_frame

	print("Soft armor: through Ballistics")
	var dummy := await _dummy(["plate_carrier"])
	var probe: Vitals = dummy.vitals
	var pistol := _fire_at(1.3, ItemDB.get_item(&"m17"))
	check(pistol.result == "plate" and not probe.wound_list().any(func(w: Dictionary) -> bool: return w.get("bleeding", false)), "9mm to an unplated medium vest is stopped (%s)" % pistol.result)
	var impact: Dictionary = _impacts(dummy).back() if not _impacts(dummy).is_empty() else {}
	check(impact.get("part") == Vitals.CHEST and impact.get("energy_j", 0.0) > 400.0 and absf(impact.get("distance", 0.0) - 4.88) < 0.1,
		"impact: chest, pistol, %.2f m, %.0f J" % [impact.get("distance", 0.0), impact.get("energy_j", 0.0)])
	var rifle := _fire_at(1.3, ItemDB.get_item(&"m4a1"))
	check(rifle.result == "body" and not probe.wound_list().is_empty(), "5.56 goes through it (%s)" % rifle.result)
	dummy.queue_free()
	var light_dummy := await _dummy(["plate_carrier_light"])
	_shooter.position = Vector3(0, 1.3, 5)
	var from_back := Ballistics.fire(_shooter, _shooter.position, Vector3.FORWARD, ItemDB.get_item(&"m17"))
	check(from_back.result == "body", "light vest: a 9mm in the back hits the body (%s)" % from_back.result)
	check(_fire_at(1.3, ItemDB.get_item(&"m17")).result == "plate", "light vest: a 9mm in the chest is stopped")
	light_dummy.queue_free()
	await get_tree().process_frame


# --- Helmets ----------------------------------------------------------------------------------

func _test_helmet_impact() -> void:
	print("Helmets: impact on a stop, through above the rating")
	var dummy := await _dummy(["helmet"])
	var probe: Vitals = dummy.vitals
	var pistol := ItemDB.get_item(&"m17")
	var shot := _fire_at(1.73, pistol)
	var impact: Dictionary = _impacts(dummy).back() if not _impacts(dummy).is_empty() else {}
	var distance: float = impact.get("distance", -1.0)
	check(shot.result == "plate" and impact.get("part") == Vitals.HEAD and impact.get("round_class") == Vitals.PISTOL,
		"medium helmet stops a 9mm: impact on the head (%s)" % impact)
	check(distance > 4.5 and distance < 5.0 and absf(impact.get("energy_j", 0.0) - Ballistics.energy_at(pistol, distance)) < 0.5,
		"with the range (%.2f m) and the energy there (%.0f J)" % [distance, impact.get("energy_j", 0.0)])
	var impacts := _impacts(dummy).size()
	var rifle := _fire_at(1.75, ItemDB.get_item(&"m4a1"), 0.04)
	check(rifle.result == "body" and _impacts(dummy).size() == impacts and _hits(dummy).back().part == Vitals.HEAD, "a 5.56 round goes through the IIIA helmet into the head (%s)" % rifle.result)
	dummy.queue_free()
	var heavy := await _dummy(["helmet_heavy"])
	var stop := _fire_at(1.73, ItemDB.get_item(&"m110"))
	check(stop.result == "plate" and _impacts(heavy).back().round_class == Vitals.FULL_POWER, "heavy helmet (III++) stops 7.62 ball, with a full-power impact")
	heavy.queue_free()
	await get_tree().process_frame


# --- Fit --------------------------------------------------------------------------------------

func _test_fit() -> void:
	print("Plate fit")
	var pe := ItemDB.get_item(&"plate_pe_l3")
	var steel := ItemDB.get_item(&"plate_steel_l3")
	var ceramic := ItemDB.get_item(&"plate_ceramic_l4")
	var side := ItemDB.get_item(&"plate_side")
	var bare := Inventory.new()
	add_child(bare)
	check(bare.fit_problem(steel) == "Put on a plate carrier first", "no carrier: \"%s\"" % bare.fit_problem(steel))
	bare.queue_free()
	for tier: Array in [[&"plate_carrier_light", [pe], [steel, ceramic, side]],
			[&"plate_carrier", [steel, ceramic], [pe, side]],
			[&"plate_carrier_heavy", [steel, ceramic, side], [pe]]]:
		var inv := Inventory.new()
		add_child(inv)
		inv.take(&"assault_pack")
		inv.take(tier[0])
		for plate: ItemData in tier[1]:
			check(inv.fit_problem(plate) == "", "%s takes %s" % [tier[0], plate.name])
		for plate: ItemData in tier[2]:
			var problem := inv.fit_problem(plate)
			check(problem.contains("doesn't fit") and problem.contains(plate.name), "%s refuses %s: \"%s\"" % [tier[0], plate.name, problem])
			inv.take(plate.id)
			var worn := Inventory.PLATE_SLOTS.any(func(s: StringName) -> bool: return inv.slots[s] == plate.id)
			check(not worn and inv.count_of(plate.id) == 1, "...so picking it up stows it instead")
			var container: StringName = &""
			var index := -1
			for c in Inventory.CONTAINERS:
				for i in inv.containers[c].size():
					if inv.containers[c][i].id == plate.id:
						container = c
						index = i
			check(not inv.equip_entry(container, index) and inv.entry_fit_problem(container, index) == problem, "...and it won't equip from there")
		inv.queue_free()
	var full := Inventory.new()
	add_child(full)
	full.take(&"plate_carrier_light")
	full.take(&"plate_pe_l3")
	check(full.fit_problem(pe) == "No free plate pocket", "a full carrier: \"%s\"" % full.fit_problem(pe))
	full.queue_free()


# --- Item state -------------------------------------------------------------------------------

func _test_state_travels() -> void:
	print("Cracks and integrity travel with the plate")
	var piece := _piece(&"plate_ceramic_l4")
	var rifle := ItemDB.get_item(&"m4a1")
	piece.server_try_stop(Vector3(-0.08, -0.1, -0.01), Vector3.BACK, rifle, 10.0)
	piece.server_try_stop(Vector3(0.08, 0.1, -0.01), Vector3.BACK, rifle, 10.0)
	var removed := piece.inventory.unequip(&"plate_front")
	check(ArmorRules.cracks(removed.state).size() == 2 and is_equal_approx(ArmorRules.integrity(removed.state), 0.64), "unequipped plate keeps 2 cracks and 64%")
	piece.inventory.queue_free()

	var item := WorldItem.new()
	item.item_id = removed.id
	item.state = removed.state
	add_child(item)
	await get_tree().process_frame
	check(item.describe().contains("[2 cracks, 64%]"), "dropped, inspecting it shows the damage: %s" % item.describe())
	var other := Inventory.new()
	add_child(other)
	other.take(&"plate_carrier")
	other.take(item.item_id, item.count, item.state)  # what picking it up does
	item.queue_free()
	check(ArmorRules.cracks(other.state_of(&"plate_front")).size() == 2 and is_equal_approx(ArmorRules.integrity(other.state_of(&"plate_front")), 0.64),
		"picked up by someone else, the cracks come along")
	var copy := Inventory.new()
	copy.net_state = other.net_state
	check(ArmorRules.cracks(copy.state_of(&"plate_front")).size() == 2, "cracks replicate in net_state")
	copy.free()
	other.take(&"assault_pack")
	other.take(&"plate_ceramic_l4")
	other.take(&"plate_ceramic_l4")
	var stowed: Array = (other.containers[&"vest"] + other.containers[&"pockets"] + other.containers[&"backpack"]).filter(func(e: Dictionary) -> bool: return e.id == &"plate_ceramic_l4")
	check(stowed.size() == 1 and stowed[0].count == 1, "fresh plates fill the back pocket and stow apart from cracked ones")
	other.queue_free()

	var broken := WorldItem.new()
	broken.item_id = &"plate_ceramic_l4"
	broken.state = {"chips": [[12, 15, 0, 2.6]], "cracks": [[12, 15, 0]], "integrity": 0.0}
	add_child(broken)
	await get_tree().process_frame
	check(broken.describe().contains("[shattered]"), "a shattered plate says so: %s" % broken.describe())
	broken.queue_free()

	var dummy := await _dummy(["plate_carrier"])
	dummy.inventory.take(removed.id, 1, removed.state)
	var summary := dummy.gear.armor_summary()
	check(summary.contains("Front IV 64% 2 cracks"), "armor summary: %s" % summary)
	check(is_equal_approx(dummy.gear.armor_integrity(&"plate_front"), 0.64), "armor_integrity is the ceramic integrity")
	dummy.queue_free()
	await get_tree().process_frame
