extends Node
## Clothing, the gear editor on companions and pouches, and third person (docs/survival_clothing.md,
## calls 132-135): the clothing slots hold their own layer and refuse the rest; warmth sums by
## layer and the body's cold reads it; rain soaks the outer layer first and a fire dries it; a
## rain jacket raises step noise; pockets add capacity; a survivor and a companion start dressed;
## the gear editor opens on a companion with their needs and mood, a given item lands in their
## kit, a saved kit applies to them; things go INTO a pouch and a backpack through the editor
## within what they hold; the third-person toggle puts the camera behind the shoulder and aiming
## brings first person back.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier
var layer: SurvivorsLayer


func _ready() -> void:
	get_tree().create_timer(400.0).timeout.connect(func() -> void:
		print("CLOTHING TEST FAILED (timed out)")
		get_tree().quit(99))
	Clothing.force = true
	_test_slots()
	_test_warmth()
	_test_wet()
	_test_noise_camo_pockets()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _test_world()
	if level != null and player != null and layer != null:
		await _test_editor()
		await _test_pouches()
		await _test_third_person()
	_finish()


func _inv() -> Inventory:
	var inv := Inventory.new()
	add_child(inv)
	return inv


func _test_slots() -> void:
	print("Clothing slots and layers")
	var inv := _inv()
	check(inv.take(&"rain_jacket") == 1 and inv.slots[&"torso_outer"] == &"rain_jacket", "a rain jacket goes on the outer layer")
	check(inv.take(&"tshirt") == 1 and inv.slots[&"torso_base"] == &"tshirt" and inv.take(&"jeans") == 1 and inv.slots[&"legs"] == &"jeans",
		"a T-shirt the base layer, jeans the legs")
	check(inv.fit_problem(ItemDB.get_item(&"winter_coat")).begins_with("Already wearing"), "a second outer layer is refused (%s)" % inv.fit_problem(ItemDB.get_item(&"winter_coat")))
	var feet := CompanionGear.put_in(inv, {"id": &"jeans", "count": 1}, "slot:feet")
	var head := CompanionGear.put_in(inv, {"id": &"m4a1", "count": 1}, "slot:head")
	check(feet != "" and head != "" and inv.slots[&"feet"] == &"" and inv.slots[&"head"] == &"", "jeans don't go on the feet, nor a rifle on the head (%s; %s)" % [feet, head])
	check(CompanionGear.put_in(inv, {"id": &"work_boots", "count": 1}, "slot:feet") == "" and inv.slots[&"feet"] == &"work_boots", "boots on the feet")
	check(inv.take(&"gloves_tactical") == 1 and inv.slots[&"hands"] == &"gloves_tactical" and inv.count_of(&"gloves_tactical") == 1 and BodySeason.covers(inv, "hands"),
		"the old tactical gloves are clothing now: worn on the hands, still counted, frost kept off")
	check(inv.take(&"enclave_uniform") == 1 and inv.count_of(&"enclave_uniform") == 1, "the enclave uniform still counts for the disguise, worn or stowed")
	Clothing.force = false
	var plain := _inv()
	plain.take(&"pack_daypack_20")
	check(plain.take(&"wool_hat") == 1 and plain.slots[&"head"] == &"", "outside a survival world clothing is only carried")
	Clothing.force = true
	plain.queue_free()
	inv.queue_free()


func _test_warmth() -> void:
	print("Warmth by layer")
	var inv := _inv()
	for id: StringName in [&"thermal_top", &"wool_sweater", &"field_jacket"]:
		inv.take(id)
	var want := 0.14 + 0.2 + 0.18
	check(is_equal_approx(Clothing.inv_warmth(inv), want) and is_equal_approx(BodySeason.clothing_warmth(inv), want), "three layers sum their warmth (%.2f)" % Clothing.inv_warmth(inv))
	for id: StringName in [&"trapper_hat", &"snow_pants", &"winter_boots", &"wool_gloves", &"scarf_wool"]:
		inv.take(id)
	check(is_equal_approx(Clothing.inv_warmth(inv), BodySeason.CLOTHING_MAX), "a whole winter kit tops out at %.1f" % BodySeason.CLOTHING_MAX)
	var dressed := Needs.fresh()
	var bare := Needs.fresh()
	Needs.step(dressed, 3.0, {"dark": 1.0, "wind": 6.0, "season": "winter", "layers": Clothing.layers(inv)})
	Needs.step(bare, 3.0, {"dark": 1.0, "wind": 6.0, "season": "winter", "layers": []})
	check(float(dressed.warmth) > float(bare.warmth) + 0.5, "the body's cold reads the layers: a winter night %.2f C dressed, %.2f C bare" % [float(dressed.warmth), float(bare.warmth)])
	inv.queue_free()


func _test_wet() -> void:
	print("Wet layers")
	var inv := _inv()
	inv.take(&"tshirt")
	inv.take(&"denim_jacket")
	var lay := Clothing.layers(inv)
	var n := Needs.fresh()
	Needs.step(n, 1.0, {"rain": true, "layers": lay})
	var w := Clothing.wet_of(n, inv)
	check(float(w.torso_outer) > 0.5 and float(w.torso_base) < float(w.torso_outer) and float(w.skin) < 0.05,
		"an hour's rain soaks the jacket first (outer %.2f, base %.2f, skin %.2f)" % [float(w.torso_outer), float(w.torso_base), float(w.skin)])
	Needs.step(n, 2.0, {"rain": true, "layers": lay})
	w = Clothing.wet_of(n, inv)
	check(float(w.torso_outer) >= 0.99 and float(w.torso_base) > 0.3, "then through to the shirt (outer %.2f, base %.2f)" % [float(w.torso_outer), float(w.torso_base)])
	check(Clothing.layers_warmth(lay, n) < Clothing.layers_warmth(lay) * 0.6, "soaked clothes keep less warmth (%.2f of %.2f)" % [Clothing.layers_warmth(lay, n), Clothing.layers_warmth(lay)])
	var by_fire := n.duplicate(true)
	var by_time := n.duplicate(true)
	Needs.step(by_fire, 1.0, {"layers": lay, "fire": true})
	Needs.step(by_time, 1.0, {"layers": lay})
	var wf := Clothing.wet_of(by_fire, inv)
	var wt := Clothing.wet_of(by_time, inv)
	check(float(wf.torso_outer) < 0.1 and float(wt.torso_outer) > 0.5, "an hour by a fire dries the jacket (%.2f), an hour without barely (%.2f)" % [float(wf.torso_outer), float(wt.torso_outer)])
	var shell := _inv()
	shell.take(&"tshirt")
	shell.take(&"rain_jacket")
	var m := Needs.fresh()
	Needs.step(m, 2.0, {"rain": true, "layers": Clothing.layers(shell)})
	check(float(Clothing.wet_of(m, shell).torso_base) == 0.0 and float(m.wet) == 0.0, "under a rain jacket the shirt and skin stay dry")
	shell.queue_free()
	inv.queue_free()


func _test_noise_camo_pockets() -> void:
	print("Noise, camouflage, pockets")
	var a := _inv()
	var b := _inv()
	a.take(&"rain_jacket")
	b.take(&"hunting_jacket")
	check(Clothing.noise_of(a) > 1.3 and Clothing.noise_of(b) < 1.0, "a rain jacket rustles (steps x%.2f), a hunting jacket is quiet (x%.2f)" % [Clothing.noise_of(a), Clothing.noise_of(b)])
	var woods_b := Clothing.spot_factor(b, "temperate")
	var woods_a := Clothing.spot_factor(a, "temperate")
	check(woods_b > 1.0 and woods_a < woods_b - 0.2, "camo: a hunting jacket blends into the woods (spot time x%.2f), a yellow rain jacket doesn't (x%.2f)" % [woods_b, woods_a])
	check(Clothing.spot_factor(_inv(), "temperate") == 0.0, "camo: nothing seen worn leaves it to the body's look")
	check(Clothing.camo_words(woods_b) == "blends in well" and Clothing.camo_words(woods_a) == "stands out", "camo in words: %s / %s" % [Clothing.camo_words(woods_b), Clothing.camo_words(woods_a)])
	var c := _inv()
	check(is_equal_approx(c.capacity(&"pockets"), Inventory.POCKETS_L), "bare pockets: %.1f L" % c.capacity(&"pockets"))
	c.take(&"cargo_pants")
	c.take(&"field_jacket")
	check(is_equal_approx(c.capacity(&"pockets"), Inventory.POCKETS_L + 1.4 + 1.4), "cargo trousers and a field jacket add their pockets (%.1f L)" % c.capacity(&"pockets"))
	c.insert_entry(&"pockets", {"id": &"water_bottle", "count": 4})
	var used := c.used(&"pockets")
	check(used > Inventory.POCKETS_L and c.unequip(&"legs").is_empty() and c.slots[&"legs"] == &"cargo_pants",
		"with %.1f L in the pockets the cargo trousers won't come off" % used)
	for x: Inventory in [a, b, c]:
		x.queue_free()


func _test_world() -> void:
	print("A world: dressed survivors")
	check(Survival.server_new_world(main, "test_clothing" + tag, 9876), "a new world")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	layer = SurvivorsLayer.find(level)
	check(player != null and layer != null, "the survivor is in")
	if player == null or layer == null:
		return
	await _wait_for(func() -> bool: return layer._started, 30.0)
	var worn := Clothing.worn(player.inventory)
	var kit := Survival.kit_of(player.inventory).map(func(e: Dictionary) -> String: return String(e.id))
	check(worn.size() >= 3 and kit.has(String(worn[0].id)), "a new survivor starts dressed (%s), and his clothes are in his saved kit" % [Clothing.lines_of(player.inventory)])
	player.inventory.take(&"pack_ruck_60")
	check(Needs.context_of(player).has("layers") and float(Needs.context_of(player).clothing) > 0.0, "the body's context reads his worn layers")


func _companion() -> Soldier:
	var rec := layer.server_add_person(level.ground_point(player.global_position + Vector3(1.5, 0, 0)), {"traits": ["calm", "kind"], "want": {"kind": "place"}})
	var c := layer.server_recruit(rec, player)
	await _frames(5)
	if c:
		c.global_position = level.ground_point(player.global_position + Vector3(1.5, 0, 0)) + Vector3.UP * 0.1
		var brain := SquadAI.of(c)
		if brain:
			brain.on_order(Squad.Order.HOLD, c.global_position)
	return c


func _test_editor() -> void:
	print("The gear editor on a companion")
	var comp: Soldier = await _companion()
	check(comp != null and not Clothing.worn(comp.inventory).is_empty(), "a companion joins, dressed (%s)" % [Clothing.lines_of(comp.inventory) if comp else []])
	if comp == null:
		return
	var entries := TalkMenu.actions_for(player, comp, InteractionMenu.SQUADMATE)
	check(entries.any(func(e: Dictionary) -> bool: return e.id == &"talk_gear"), "the talk menu offers Gear on a companion")
	var ed := LoadoutGear.open_on(player, comp)
	await _frames(3)
	check(ed != null and LoadoutGear.current(player) == ed and ed.target == comp and ed.preview != null and ed.preview.clothing, "the editor opens on them with their body in 3D")
	check(ed.info.has("needs") and ed.info.has("band") and String(ed.info.get("name", "")) == comp.display_name(), "their needs and mood beside it (%s)" % [ed.info.get("band", "?")])
	player.inventory.take(&"pressure_bandage", 2)
	var at := CompanionGear.find_stowed(player.inventory, &"pressure_bandage")
	var had := comp.inventory.count_of(&"pressure_bandage")
	var why := ed.give(at[0], int(at[1])) if not at.is_empty() else "none"
	var rec := layer.record_of(comp)
	check(why == "" and comp.inventory.count_of(&"pressure_bandage") == had + 1 and (rec.kit as Array).any(func(e: Dictionary) -> bool: return String(e.id) == "pressure_bandage"),
		"a bandage given lands in their kit and their record (%s)" % why)
	if comp.inventory.slots[&"torso_outer"] != &"":
		ed.take("slot:torso_outer")
	check(comp.inventory.slots[&"torso_outer"] == &"", "their outer layer taken back")
	player.inventory.insert_entry(&"backpack", {"id": &"winter_coat", "count": 1})
	at = CompanionGear.find_stowed(player.inventory, &"winter_coat")
	why = ed.give(at[0], int(at[1]), "slot:torso_outer") if not at.is_empty() else "none"
	check(why == "" and comp.inventory.slots[&"torso_outer"] == &"winter_coat", "a winter parka given onto their outer layer (%s)" % why)
	check(ed.save_kit("Winter") == "" and String((CompanionGear.kit("Winter").get("worn", {}) as Dictionary).get("torso_outer", "")) == "winter_coat", "their kit saved as Winter")
	check(ed.take("slot:torso_outer") == "" and comp.inventory.slots[&"torso_outer"] == &"" and player.inventory.count_of(&"winter_coat") >= 1, "the parka taken back")
	why = ed.apply_kit("Winter")
	check(comp.inventory.slots[&"torso_outer"] == &"winter_coat", "the saved kit applied to them puts the parka back on from what you carry (%s)" % why)
	comp.inventory.take(&"assault_pack")
	at = CompanionGear.find_stowed(player.inventory, &"pressure_bandage")
	why = ed.give(at[0], int(at[1]), "container:backpack") if not at.is_empty() else "none"
	check(why == "" and comp.inventory.containers[&"backpack"].any(func(e: Dictionary) -> bool: return e.id == &"pressure_bandage"), "a bandage put INTO their backpack (%s)" % why)
	player.inventory.insert_entry(&"backpack", {"id": &"m4a1", "count": 1})
	at = CompanionGear.find_stowed(player.inventory, &"m4a1")
	why = ed.give(at[0], int(at[1]), "container:pockets") if not at.is_empty() else "none"
	check(why != "" and player.inventory.count_of(&"m4a1") == 1, "a rifle won't go in their pockets, and stays with you (%s)" % why)
	var places := LoadoutGear.places_of(comp.inventory).map(func(p: Dictionary) -> String: return String(p.place))
	check(places.has("slot:torso_outer") and places.has("container:pockets") and places.has("container:backpack"), "the editor lists slots, clothes and containers as places")
	ed.close()
	await _frames(2)
	check(LoadoutGear.current(player) == null, "Close shuts it")


func _test_pouches() -> void:
	print("Pouches and pockets through the editor (your own kit)")
	var inv := player.inventory
	inv.take(&"plate_carrier")
	inv.take(&"pouch_mag_double")
	var ed := LoadoutGear.open_on(player, player)
	await _frames(2)
	var pouch := Inventory.pouch_container(&"mag_1")
	check(inv.containers.has(pouch), "a double mag pouch on the carrier")
	inv.insert_entry(&"backpack", {"id": &"mag_556", "count": 3})
	var got := 0
	var refused := ""
	for i in 3:
		var at := -1
		var list: Array = inv.containers[&"backpack"]
		for k in list.size():
			if list[k].id == &"mag_556":
				at = k
		var why := ed.move("container:backpack", at, "container:" + String(pouch))
		if why == "":
			got += 1
		else:
			refused = why
	check(got == 2 and inv.units_in(pouch) == 2 and refused != "", "two mags go INTO the pouch, the third is refused (%s)" % refused)
	var before := inv.units_in(&"pockets")
	inv.insert_entry(&"backpack", {"id": &"pressure_bandage", "count": 1})
	var idx := -1
	var bl: Array = inv.containers[&"backpack"]
	for k in bl.size():
		if bl[k].id == &"pressure_bandage":
			idx = k
	check(ed.move("container:backpack", idx, "container:pockets") == "" and inv.units_in(&"pockets") == before + 1, "a bandage moved into the pockets")
	ed.close()
	await _frames(2)


func _test_third_person() -> void:
	print("Third person on foot")
	var cam := VehicleCamera.of(player)
	check(cam != null, "the local player has the chase camera")
	if cam == null:
		return
	check(VehicleCamera.foot_key(player, false) == (player.inventory.count_of(&"binoculars") == 0) and VehicleCamera.foot_key(player, true), "B toggles it on foot in a survival zone (Shift+B with binoculars)")
	player.is_aiming = false
	VehicleCamera.on_foot = false
	check(VehicleCamera.toggle_foot() == "Third person" and VehicleCamera.on_foot, "the toggle turns it on")
	cam.follow(0.016)
	var eye := player.camera.global_position
	var ahead := -player.camera.global_basis.z
	var off := cam.global_position - eye
	check(cam.active and cam.current and off.dot(ahead) < -0.3, "the camera goes behind him (%.2f m back)" % -off.dot(ahead))
	check(cam.cull_mask & PlayerInput.LOCAL_ONLY_LAYER != 0 and cam.cull_mask & PlayerInput.VIEW_MODEL_LAYER == 0, "his own body is drawn, the first-person gun isn't")
	player.is_aiming = true
	cam.follow(0.016)
	check(not cam.active and player.camera.current, "aiming gives first person back")
	player.is_aiming = false
	cam.follow(0.016)
	check(cam.active, "and lowering the gun the third person again")
	VehicleCamera.toggle_foot()
	cam.follow(0.016)
	check(not cam.active and player.camera.current, "B again: first person")


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _finish() -> void:
	Clothing.force = false
	VehicleCamera.on_foot = false
	if Survival.world != "":
		GameState.delete_save()
		Survival.running = false
		Campaign.reset_campaign()
	print("CLOTHING TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
