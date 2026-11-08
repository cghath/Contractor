extends Node
## The settlement's work (docs/survival_building.md §5-7, 11; calls 23, 28, 59, 136, 138):
## in a hosted survival world, the settlement founded on flat ground with a bunk, a stash and a
## stove; a survivor who wants a place joins as a settler for the free bed (and the next, with no
## bed, doesn't); stocks are counted from the stash; a scavenge job fills the stash; a cook turns
## raw meat into hot meals that a hungry settler eats; a build job finishes a blueprint from
## stock; a haul job moves a drop into the stash; the guard on the night watch wakes the sleepers
## when one of the dead comes; a settlement out of food starves (the moods fall); a work order is
## counted and completed, the planning view shows what's short and who's idle and a claimed order
## isn't taken over; the council votes a raider's demand paid from stock and the standing sways
## it; the settlement screen names a member and a stock; waiting until dawn runs the clock and
## stops for the dead; solo pause pauses and co-op doesn't. Ticks are driven directly.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier
var b: Builder
var st: Settlement
var layer: SurvivorsLayer
var origin := Vector3i.ZERO
var stash_id := -1
var a_rec: Dictionary
var b_rec: Dictionary


func _ready() -> void:
	get_tree().create_timer(390.0).timeout.connect(func() -> void:
		print("SETTLEMENT TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _test_host()
	if b != null and player != null and st != null and layer != null:
		await _test_pieces()
		await _test_settler_joins()
		_test_stocks()
		_test_scavenge()
		_test_cook()
		_test_build()
		await _test_haul()
		await _test_guard()
		_test_starve()
		_test_work_orders()
		_test_council()
		await _test_screen()
		await _test_wait()
		await _test_solo_pause()
	_finish()


func _test_host() -> void:
	print("A survival world with a settlement")
	check(Survival.server_new_world(main, "test_settlement" + tag, 4321), "a new world hosts")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	if player == null:
		check(false, "the host's survivor is in")
		return
	for i in 120:
		await get_tree().process_frame
	Survival._pop = -1000.0  # (no dead spawned round us: the tests place their own)
	_clear_dead()
	b = Builder.find(level)
	st = Settlement.find(level)
	layer = SurvivorsLayer.find(level)
	check(b != null and st != null and layer != null, "the zone has its Builder, Settlement and Survivors on the host")
	if st == null or b == null or layer == null:
		return
	st.set_process(false)  # (the test drives the settlement's hours itself)
	await _wait_for(func() -> bool: return layer._started, 30.0)
	check(player.inventory.put_on(&"backpack", &"pack_ruck_60"), "a big pack on for the materials")
	var found := false
	var start := player.global_position
	for ring: float in [6.0, 10.0, 14.0, 20.0, 28.0, 36.0, 44.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var x := start.x + cos(a) * ring
			var z := start.z + sin(a) * ring
			if _flat_and_clear(x, z):
				origin = Builder.ground_cell(Vector3(x, level.ground_height(x, z), z))
				found = true
				break
		if found:
			break
	check(found, "a patch of flat open ground (%s)" % origin)
	var home := BuildPieces.cell_centre(_at(4, 2))
	Settlement.server_found(String(Survival.state().zone), Vector3(home.x, level.ground_height(home.x, home.z), home.z))
	check(Settlement.exists() and Settlement.zone() == String(Survival.state().zone) and st.hosted(), "the settlement founded there, and its zone is the one played")
	_stand_by(origin + Vector3i(0, 0, -3))
	for i in 20:
		await get_tree().process_frame


func _flat_and_clear(x: float, z: float) -> bool:
	var lo := INF
	var hi := -INF
	for dx in range(-6, 7):
		for dz in range(-4, 7):
			var h := level.ground_height(x + dx * 0.5, z + dz * 0.5)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			for up in [0.3, 1.2, 2.2]:
				if b._structure_at(Vector3(x + dx * 0.5, h + up, z + dz * 0.5)):
					return false
	return hi - lo < 0.4


func _at(dx: int, dz: int) -> Vector3i:
	var p := BuildPieces.cell_centre(origin + Vector3i(dx, 0, dz))
	return Builder.ground_cell(Vector3(p.x, level.ground_height(p.x, p.z), p.z))


func _stand_by(c: Vector3i) -> void:
	var p := BuildPieces.cell_centre(c)
	player.global_position = Vector3(p.x, level.ground_height(p.x, p.z) + 0.1, p.z)
	player.velocity = Vector3.ZERO


func _clear_dead() -> void:
	for z: Soldier in Survival.zombies(level):
		z.queue_free()


func _test_pieces() -> void:
	print("The settlement's pieces")
	for pair: Array in [[&"hammer", 1], [&"wrench_set", 1], [&"planks", 10], [&"scrap_sheet", 4], [&"brick", 1]]:
		player.inventory.take(StringName(pair[0]), int(pair[1]))
	var placed := []
	for spec: Array in [["bunk", 0, 0], ["stash", 3, 0], ["stove", 6, 0]]:
		var c := _at(int(spec[1]), int(spec[2]))
		_stand_by(c + Vector3i(0, 0, -3))
		var id := b.server_build_piece_now(player, String(spec[0]), c, 0)
		placed.append(id)
		check(id > 0 and b.is_piece_built(id), "a %s built (%s)" % [spec[0], b.last_problem])
	stash_id = int(placed[1])
	st.refresh()
	check(Settlement.beds() == 1 and int(Settlement.data().stoves) == 1, "the settlement counts one bed and one stove (%d, %d)" % [Settlement.beds(), int(Settlement.data().get("stoves", 0))])
	check(Settlement.data().footprint is Dictionary and float(Settlement.footprint().value) == 0.0, "no generator or lamp: no footprint")
	_stand_by(_at(4, -2))
	await get_tree().process_frame


func _near(off: Vector3) -> Vector3:
	return level.ground_point(player.global_position + off)


func _test_settler_joins() -> void:
	print("A settler joins for a bed")
	a_rec = layer.server_add_person(_near(Vector3(1.5, 0.0, 0.0)), {"traits": ["timid", "kind"], "background": "carpenter", "want": {"kind": "place"}, "age": 60})
	var body := layer.body_of(String(a_rec.id))
	check(body != null and Settlement.place_problem() == "", "a survivor who wants a place stands by; there's a free bed")
	if body == null:
		return
	TalkMenu.server_talk(layer, player, body, "recruit")
	await _frames(3)
	check(String(a_rec.status) == "settler" and Settlement.settlers().size() == 1 and Settlement.free_beds() == 0,
		"they join as a settler (status %s), the bed is theirs" % a_rec.status)
	check(Settlement.jobs_of(a_rec) == ["build", "maintain"], "a carpenter starts on build and maintain (%s)" % [Settlement.jobs_of(a_rec)])
	var other := layer.server_add_person(_near(Vector3(-1.5, 0.0, 0.0)), {"traits": ["calm"], "want": {"kind": "place"}})
	var ob := layer.body_of(String(other.id))
	if ob:
		TalkMenu.server_talk(layer, player, ob, "recruit")
	await _frames(3)
	check(String(other.status) != "settler", "the next one, with no bed free, isn't a settler (%s)" % other.status)
	# A second settler for the tests that follow (the bed doesn't gate this call).
	b_rec = other
	if String(other.status) == "companion":
		layer.server_settle(other, player)
	else:
		var bb := layer.body_of(String(other.id))
		if bb:
			layer.server_settler_body(other, false)
			bb.queue_free()
		Settlement.server_make_settler(other)
	b_rec.traits = ["timid", "gloomy"]
	b_rec.courage = 10
	check(String(b_rec.status) == "settler" and Settlement.settlers().size() == 2 and not Settlement.has_bed(b_rec), "a second settler, without a bed")


func _test_stocks() -> void:
	print("Stocks from a stash")
	player.inventory.take(&"beans_tin", 4)
	player.inventory.take(&"water_bottle", 2)
	var food0 := Settlement.count_cat("food")
	var n := st.server_stow(player)
	var in_stash: Array = Settlement.stores().get(str(stash_id), [])
	var beans := 0
	for e: Dictionary in in_stash:
		if String(e.id) == "beans_tin":
			beans += int(e.count)
	check(n > 0 and beans == 4, "stowing puts what he carries in the stash (%d items, %d tins in the stash)" % [n, beans])
	check(Settlement.count_cat("food") >= food0 + 4 and int(Settlement.stocks().food) == Settlement.count_cat("food") and Settlement.count("planks") > 0,
		"the stocks count it: food %d, water %d, wood %d" % [Settlement.count_cat("food"), Settlement.count_cat("water"), Settlement.count_cat("wood")])
	check(Settlement.category_of("sandbag") == "sand" and Settlement.category_of("pressure_bandage") == "meds" and Settlement.category_of("raw_meat") == "food",
		"items fall in their categories")


func _stash_items() -> int:
	var n := 0
	for e: Dictionary in Settlement.stores().get(str(stash_id), []):
		n += int(e.count)
	return n


func _test_scavenge() -> void:
	print("A scavenge job fills the stash")
	Settlement.server_set_jobs(a_rec, ["scavenge"])
	Settlement.server_set_jobs(b_rec, [])
	Settlement.force_roll = 0.0
	var before := Settlement.taken_count(_all_entries())
	for i in 3:
		st.server_hour(10)
	Settlement.force_roll = -1.0
	var after := Settlement.taken_count(_all_entries())
	check(after > before and String(a_rec.job_now) == "scavenge", "three hours out bring things back (%d -> %d items, now %s)" % [before, after, a_rec.job_now])


func _all_entries() -> Array:
	var out: Array = []
	for k: String in Settlement.stores():
		out.append_array(Settlement.stores()[k])
	return out


func _test_cook() -> void:
	print("A cook job")
	Settlement.server_set_jobs(a_rec, ["cook"])
	st.server_put("raw_meat", 3)
	var raw0 := Settlement.count("raw_meat")
	st.server_hour(10)
	check(Settlement.count("cooked_meal") >= 1 and Settlement.count("raw_meat") < raw0 and String(a_rec.job_now) == "cook",
		"raw meat into hot meals on the stove (%d meals, %d raw left)" % [Settlement.count("cooked_meal"), Settlement.count("raw_meat")])
	var n: Dictionary = b_rec.needs
	n.hunger = 20.0
	Needs.step(n, 0.001, {})
	st.server_hour(12)
	check(Moods.has(b_rec, "ate_hot") and float(n.hunger) > 20.0, "a hungry settler eats a hot meal at noon (hunger %.0f)" % float(n.hunger))


func _test_build() -> void:
	print("A build job finishes a blueprint from stock")
	var c := _at(9, 0)
	_stand_by(c + Vector3i(0, 0, -3))
	var why := b.server_place(player, c, "wood", "block", 0, true)
	check(why == "" and bool(b.blocks[c].bp), "a wood blueprint laid (%s)" % why)
	if why != "":
		return
	st.server_put("planks", 5)
	var planks := Settlement.count("planks")
	Settlement.server_set_jobs(a_rec, ["build"])
	check(WorkOrders.materials_needed(st).is_empty(), "the stock covers the blueprint")
	st.server_hour(10)
	check(b.is_built(c) and Settlement.count("planks") == planks - 5 and String(a_rec.job_now) == "build",
		"the settler builds it from stock (%s, planks %d -> %d)" % [b.blocks.get(c, {}), planks, Settlement.count("planks")])
	_stand_by(_at(4, -2))


func _test_haul() -> void:
	print("A haul job")
	var at := level.ground_point(Settlement.pos() + Vector3(3.0, 0.0, 3.0)) + Vector3.UP * 0.3
	var uid := level.server_spawn_dropped(&"scrap_sheet", 2, at)
	await _frames(3)
	var scrap := Settlement.count("scrap_sheet")
	Settlement.server_set_jobs(a_rec, ["haul"])
	# The start farmstead has its own loose things about (tools, the note, food: docs/survival_firsthour.md) and a
	# hauler carries HAUL_PER_H an hour in SettlementJobs.haul_queue's order, so the drop comes in the hour its place
	# in that queue says. (Four hours flat ran out whenever more than 47 things lay ahead of it.)
	var queue := SettlementJobs.haul_queue(st)
	var place := -1
	for i in queue.size():
		if String(queue[i].uid) == uid:
			place = i
			break
	check(place >= 0, "the drop lies in the settlement, for the hauler (%d things ahead of it)" % place)
	var hours := floori(float(place) / SettlementJobs.HAUL_PER_H) + 1
	var still: Array = []
	var did: Array[String] = []
	for h in hours:
		st.server_hour(10 + h)
		did.append(String(a_rec.get("job_now", "")))
		await _frames(2)
		still = get_tree().get_nodes_in_group(&"world_items").filter(func(w: Node) -> bool: return is_instance_valid(w) and not w.is_queued_for_deletion() and String(w.get(&"uid")) == uid)
		if still.is_empty():
			break
	check(Settlement.count("scrap_sheet") >= scrap + 2 and still.is_empty(), "the drop is carried into the stores in %d hour(s) (%d -> %d; the hauler: %s)" % [hours, scrap, Settlement.count("scrap_sheet"), did])


func _test_guard() -> void:
	print("The watch wakes the sleepers")
	_clear_dead()
	await _frames(2)
	Settlement.server_set_jobs(a_rec, ["guard"])
	Settlement.server_set_jobs(b_rec, ["haul"])
	st.server_hour(23)
	check(String(a_rec.activity) == "watch" and SurvivalSleep.is_asleep(b_rec.needs), "at 23:00 the guard has the watch (%s), the other sleeps" % a_rec.activity)
	var pn := Survival.needs_of(player)
	pn.sleep = 20.0
	check(Survival.server_sleep(player, 8.0, "ground") == "" and SurvivalSleep.is_asleep(pn), "the player lies down too")
	var z := Survival.server_spawn_zombie(level, level.ground_point(Settlement.pos() + Vector3(30.0, 0.0, 0.0)))
	await get_tree().physics_frame
	var brain: ZombieAI = ZombieAI.of(z) if z else null
	if z:
		z.process_mode = Node.PROCESS_MODE_DISABLED
	if brain:
		brain.mode = ZombieAI.Mode.CHASE
	var woke := st.server_guard_check()
	check(woke >= 2 and not SurvivalSleep.is_asleep(b_rec.needs) and not SurvivalSleep.is_asleep(pn) and st.last_call.contains("on watch"),
		"one of the dead coming: the guard calls it (\"%s\") and wakes %d" % [st.last_call, woke])
	check(st.defence() >= Settlement.DEFENCE_GUARD, "a guard on duty counts in the defence (%.1f)" % st.defence())
	if z:
		z.queue_free()
	await _frames(2)


func _test_starve() -> void:
	print("Out of food, they starve")
	for e: Dictionary in _all_entries().duplicate():
		if Settlement.category_of(String(e.id)) == "food":
			Settlement.server_take(String(e.id), int(e.count))
	check(Settlement.count_cat("food") == 0, "the stores hold no food")
	Settlement.server_set_jobs(a_rec, ["guard"])
	var m0 := Moods.mood(b_rec)
	for i in 72:
		st.server_hour((8 + i) % 24)
	check(float(b_rec.needs.hunger) < 35.0 and (Moods.has(b_rec, "starving") or Moods.has(b_rec, "hungry")), "three days on: hungry (hunger %.0f)" % float(b_rec.needs.hunger))
	check(Moods.mood(b_rec) < m0, "and the mood falls (%.0f -> %.0f)" % [m0, Moods.mood(b_rec)])
	var plan := WorkOrders.planning(st)
	check((plan.short as Array).any(func(t: String) -> bool: return t.begins_with("food")), "the planning view calls food short (%s)" % [plan.short])


func _test_work_orders() -> void:
	print("Work orders")
	for r: Dictionary in [a_rec, b_rec]:  # (fed again after the hungry days)
		Needs.restore(r.needs, Needs.fresh())
		Moods.from_needs(r, r.needs)
		r["break"] = ""
	var planks := Settlement.count("planks")
	var o := WorkOrders.server_add("cut_wood", 4, 1)
	check(not o.is_empty() and WorkOrders.open_orders().size() == 1, "an order: %s" % WorkOrders.text_of(o))
	Settlement.server_set_jobs(b_rec, ["build"])
	st.server_hour(10)
	check(int(o.done) == 3 and String(o.state) == "open", "counted: %d of 4" % int(o.done))
	st.server_hour(11)
	check(int(o.done) == 4 and String(o.state) == "done" and Settlement.count("planks") == planks + 4, "completed: 4 planks in stock (%d -> %d)" % [planks, Settlement.count("planks")])
	var bags := WorkOrders.server_add("sandbags", 50, 2)
	Settlement.server_set_jobs(b_rec, [])
	st.server_hour(10)
	var plan := WorkOrders.planning(st)
	check((plan.short as Array).any(func(t: String) -> bool: return t.contains("cloth rags")), "the planning view: cloth rags short for the sandbags (%s)" % [plan.short])
	check(String(b_rec.name) in (plan.idle as Array), "and %s idle with no job (%s)" % [b_rec.name, plan.idle])
	st.server_put("cloth_rag", 3)
	var mine := WorkOrders.server_add("cut_wood", 3, 1)
	WorkOrders.server_claim(int(mine.id), Survival.profile_of(player))
	Settlement.server_set_jobs(b_rec, ["build"])
	st.server_hour(10)
	check(int(mine.done) == 0 and int(bags.done) == 3, "a claimed order is left to the player (%d done); the sandbags get filled instead (%d)" % [int(mine.done), int(bags.done)])
	WorkOrders.server_remove(int(mine.id))


func _test_council() -> void:
	print("The council")
	var profile := Survival.profile_of(player)
	st.server_put("beans_tin", 6)
	for r: Dictionary in Settlement.settlers():
		r.traits = ["timid", "kind"]
		r.courage = 10
		SurvivorPerson.change_opinion(r, profile, -SurvivorPerson.opinion_of(r, profile))
	var got := [""]
	var id := Council.server_put({"kind": "demand", "text": "Raiders want three tins", "pay": [["beans_tin", 3]], "from": "raiders"}, ["pay", "refuse"],
		func(res: String) -> void: got[0] = res)
	check(id > 0 and Council.open_votes().size() == 1, "a raider demand comes to the council")
	var journal: Array = Survival.state().get("journal", [])
	check(journal.any(func(j: Dictionary) -> bool: return String(j.text).contains("Raiders want three tins")), "as a journal line")
	var beans := Settlement.count("beans_tin")
	Council.server_choose(id, "refuse", profile)
	var v := Council.get_vote(id)
	check(String(v.result) == "pay" and Settlement.count("beans_tin") == beans - 3 and got[0] == "pay",
		"with no standing the frightened settlers outvote the player: paid from stock (%s, %d -> %d)" % [v.tally, beans, Settlement.count("beans_tin")])
	for r: Dictionary in Settlement.settlers():
		SurvivorPerson.change_opinion(r, profile, 100.0)
	var id2 := Council.server_put({"kind": "demand", "text": "Raiders want three more", "pay": [["beans_tin", 3]]}, ["pay", "refuse"])
	Council.server_choose(id2, "refuse", profile)
	var v2 := Council.get_vote(id2)
	check(String(v2.result) == "refuse" and Settlement.count("beans_tin") == beans - 3,
		"with their trust (standing %.0f) his word carries it: refused (%s)" % [Council.standing(st, profile), v2.tally])
	check(Council.factions().size() >= 1, "the settlers vote in factions (%s)" % [Council.factions().keys()])


func _test_screen() -> void:
	print("The settlement screen")
	var screen := SettlementScreen.new()
	add_child(screen)
	screen.refresh(st.view())
	await _frames(1)
	var t := screen.text()
	check(t.contains(String(a_rec.name)) and t.contains("food") and t.contains("Work orders"), "it names a member and a stock:\n%s" % t.left(400))
	screen.queue_free()


func _test_wait() -> void:
	print("Waiting until dawn")
	_clear_dead()
	await _frames(2)
	_stand_by(BuildPieces.cell_at(Settlement.pos()))
	await _frames(2)
	var pn := Survival.needs_of(player)
	SurvivalSleep.wake(pn)
	Survival.state()["hour"] = 20.0
	var h0 := Survival.hour()
	check(Survival.server_wait(player, "dawn") == "" and SurvivalSleep.is_waiting(pn) and is_equal_approx(float(pn.wait_left_h), 10.0),
		"at home at 20:00 he waits until dawn (%.1f h)" % float(pn.get("wait_left_h", 0.0)))
	var sleep0 := float(pn.sleep)
	Survival.server_tick_survivors(level, 2.0)
	check(Survival.hour() > h0 + 0.15 and float(pn.sleep) < sleep0, "the clock runs at speed (%.2f -> %.2f) and no sleep is restored" % [h0, Survival.hour()])
	var z := Survival.server_spawn_zombie(level, level.ground_point(player.global_position + Vector3(20.0, 0.0, 0.0)))
	await get_tree().physics_frame
	if z:
		z.process_mode = Node.PROCESS_MODE_DISABLED
		var brain := ZombieAI.of(z)
		if brain:
			brain.mode = ZombieAI.Mode.CHASE
	Survival.server_tick_survivors(level, 0.5)
	check(not SurvivalSleep.is_waiting(pn), "one of the dead coming stops it")
	check(Survival.server_wait(player, "hour") != "", "and he can't wait again while it chases")
	if z:
		z.queue_free()
	await _frames(2)


func _test_solo_pause() -> void:
	print("Solo pause, co-op never")
	var menu := PauseMenu.new()
	add_child(menu)
	await _frames(1)
	SoloPause.force_peers = 0
	menu.open()
	check(get_tree().paused and menu.process_mode == Node.PROCESS_MODE_ALWAYS, "alone, the pause menu pauses the world")
	menu.close()
	check(not get_tree().paused, "closed, it goes on")
	SoloPause.force_peers = 1
	menu.open()
	check(not get_tree().paused, "with someone joined it never pauses")
	menu.close()
	SoloPause.force_peers = -1
	get_tree().paused = false
	menu.queue_free()
	await _frames(1)


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
	Settlement.force_roll = -1.0
	SoloPause.force_peers = -1
	get_tree().paused = false
	if Survival.world != "":
		GameState.delete_save()
		Survival.running = false
		Campaign.reset_campaign()
	print("SETTLEMENT TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
