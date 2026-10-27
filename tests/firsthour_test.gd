extends Node
## The first hour of Contractor: Fallen (docs/survival_firsthour.md): what a fresh world puts within
## 120 m of the spawn (the start farmstead); the first-day thread in the journal with marks;
## drinking at the well, picking up the barn's weapon (and the melee hint once, with the real key),
## boarding the farmhouse, day 2's radio survivor recruited; every control hint once and not again,
## silenced by the Hints toggle, listed in Field notes; the journal's "Now" and the landmarks
## visited; no horde on night 1 at Normal, one can on night 2, High keeps the hard first night; and
## the dead's density measured before/after (open country walking, near an AI farm, shots in the
## open and by a town).

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier


func _ready() -> void:
	get_tree().create_timer(420.0).timeout.connect(func() -> void:
		print("FIRSTHOUR TEST FAILED (timed out)")
		get_tree().quit(99))
	GameSettings.use_file(OS.get_user_data_dir().path_join("test_firsthour_settings%s.cfg" % tag))  # never the player's
	GameSettings.reset_all()
	FieldHints.use_file(OS.get_user_data_dir().path_join("test_firsthour_hints%s.cfg" % tag))
	FieldHints.reset_seen()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	check(Survival.server_new_world(main, "test_firsthour" + tag, 5151), "a new world is hosted")
	level = SurvivalLevel.of(self)
	if level != null:
		await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
		player = level.players.get_node_or_null(^"1") as Soldier
		await _frames(60)
	check(player != null, "the survivor is in")
	if player != null:
		player.server_end_spawn_protection()
		Wear.tick_off = true
		await _test_spawn()
		_test_thread()
		await _test_water_weapon()
		await _test_shelter()
		await _test_voice()
		await _test_hints()
		_test_now()
		await _test_density()
		await _test_shots()
		_test_pacing()
	_finish()


# --- What's at the spawn (the Captain: "at the spawn there is nothing") -------------------------

func _test_spawn() -> void:
	print("What a fresh world puts within 120 m of the spawn")
	var at := player.global_position
	var farm := FirstHour.farm_of(level)
	check(not farm.is_empty(), "the start zone has a farmstead (%s)" % str(farm))
	var mods := PackedStringArray()
	var home_m := INF
	for m: ZoneModule in level.modules():
		var d := Vector2(m.global_position.x - at.x, m.global_position.z - at.z).length()
		if d <= 120.0:
			mods.append("%s (%s) %.0f m" % [m.module_id, ZoneModules.base(String(m.type)), d])
		if m.module_id == FirstHour.HOME_ID:
			home_m = d
	print("  modules within 120 m: %s" % ", ".join(mods))
	check(home_m <= 60.0, "the farmstead stands at the spawn (%.0f m)" % home_m)
	var door: Variant = FirstHour.farm_point(level, "door")
	check(door is Vector3 and (door as Vector3).distance_to(at) <= 8.0, "he wakes at the farmhouse's front door (%.1f m)" % ((door as Vector3).distance_to(at) if door is Vector3 else -1.0))
	var boxes := 0
	var guns := 0
	for c: Node in get_tree().get_nodes_in_group(WorldCache.GROUP):
		var wc := c as WorldCache
		if wc == null or wc.global_position.distance_to(at) > 120.0:
			continue
		var what := PackedStringArray()
		var held := 0
		for e: Dictionary in wc.cargo_hold.entries():
			what.append("%s x%d" % [String(e.id), int(e.get("count", 1))])
			held += int(e.get("count", 1))
			var it := ItemDB.get_item(StringName(String(e.id)))
			if it and it.type == "weapon" and not it.stats.has("melee"):
				guns += 1
		print("  box %s at %.0f m: %s" % [wc._label, wc.global_position.distance_to(at), ", ".join(what)])
		if held > 0:
			boxes += 1
	check(boxes >= 2, "boxes near the farmhouse with something in them (%d)" % boxes)
	check(guns == 0, "no guns in the farm's boxes (the early loot curve)")
	var items := PackedStringArray()
	for n: Node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var wi := n as WorldItem
		if wi and wi.global_position.distance_to(at) <= 120.0:
			items.append("%s x%d %.0f m" % [String(wi.item_id), wi.count, wi.global_position.distance_to(at)])
	print("  on the ground within 120 m: %s" % ", ".join(items))
	var well: Variant = FirstHour.farm_point(level, "well")
	check(well is Vector3 and (well as Vector3).distance_to(at) <= 60.0 and FirstHour.source_at(level, well as Vector3) == "well", "a well in the yard")
	var lms := PackedStringArray()
	for l: Dictionary in Landmarks.of(String(Survival.state().get("zone", ""))):
		lms.append("%s %.0f m" % [String(l.name), (l.pos as Vector2).distance_to(Vector2(at.x, at.z))])
	print("  landmarks: %s" % ", ".join(lms))


# --- The thread -----------------------------------------------------------------------------------

func _journal_has(text: String) -> bool:
	return (Survival.state().get("journal", []) as Array).any(func(e: Dictionary) -> bool: return String(e.get("text", "")).contains(text))


func _test_thread() -> void:
	print("The first-day thread")
	var d := FirstHour.data()
	check(d.has("goals") and FirstHour.is_open("water") and FirstHour.is_open("weapon") and FirstHour.is_open("shelter") and not FirstHour.is_open("voice"),
		"three goals open on the first wake, the voice waits for day 2")
	check(_journal_has("Three things before dark"), "the journal has the thread")
	var goals := SurvivalMap.marks("").filter(func(m: Dictionary) -> bool: return String(m.get("kind", "")) == "goal")
	check(goals.size() >= 3, "each goal has a map mark (%d)" % goals.size())
	var note := false
	for n: Node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var wi := n as WorldItem
		if wi and wi.item_id == &"handwritten_note" and String(wi.state.get("text", "")).contains("P.S."):
			note = true
	check(note, "the note on the table carries the postscript")
	var lines := FirstHour.now_lines()
	check(lines.size() == 3 and String(lines[0]).contains(FieldHints.key_name("context")), "the journal's Now lists the three, with the real keys (%s)" % str(lines))


func _test_water_weapon() -> void:
	print("Water at the well; the barn's weapon")
	var well: Vector3 = FirstHour._v3(FirstHour.data().well)
	player.global_position = well + Vector3(1.5, 0.3, 0.0)
	await _frames(2)
	var ctx := Fieldwork.classify(player, well)
	check(String(ctx.get("kind", "")) == "water" and String(ctx.get("body", "")) == "well", "looking at the well: water (%s)" % str(ctx))
	var labels := Fieldwork.options(ctx).map(func(o: Dictionary) -> String: return String(o.label))
	check(labels.has("Drink") and labels.has("Fill a bottle"), "Drink and Fill a bottle offered (%s)" % str(labels))
	var why := Fieldwork.server_request(player, "drink", "", well)
	check(why == "" and FirstHour.is_done("water"), "drinking at the well does the water (%s)" % why)
	check(player.inventory.count_of(&"water_tablets") >= 1, "and pays (purification tablets)")
	# The weapon: the dropped one in the barn, picked up.
	var wid := StringName(String(FirstHour.data().weapon))
	var shed: Vector3 = FirstHour._v3(FirstHour.data().shed)
	var found: WorldItem = null
	for n: Node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var wi := n as WorldItem
		if wi and wi.item_id == wid and wi.global_position.distance_to(shed) <= 4.0:
			found = wi
	check(found != null, "the %s lies at the marked barn" % String(wid))
	FirstHour._sent.clear()
	FieldHints.reset_seen()
	player.global_position = shed + Vector3(2.0, 0.3, 0.0)
	player.inventory.take(wid, 1)
	if found:
		found.queue_free()
	FirstHour.server_tick(level)
	check(FirstHour.is_done("weapon"), "carrying it does the weapon goal")
	player.inventory.slots[&"sidearm"] = wid
	player.active_slot = &"sidearm"
	FirstHour._hint_tick(level)
	FirstHour._hint_tick(level)
	var n_melee := FieldHints.shown_log.count("melee")
	check(n_melee == 1, "the melee hint shows once (%d)" % n_melee)
	check(FieldHints.field_notes().any(func(l: String) -> bool: return l.begins_with("Melee") and l.contains(FieldHints.key_name("fire")) and l.contains(FieldHints.key_name("aim"))),
		"with the real keys (%s / %s)" % [FieldHints.key_name("fire"), FieldHints.key_name("aim")])
	check(FieldHints.key_name("interact") == "Ctrl" and FieldHints.key_name("build_mode") == "6", "the keys read from the bindings (interact %s, build %s)" % [FieldHints.key_name("interact"), FieldHints.key_name("build_mode")])
	player.active_slot = &"primary"


func _test_shelter() -> void:
	print("Boarding up the farmhouse")
	var home: Vector3 = FirstHour._v3(FirstHour.data().home)
	var b := Builder.of(level)
	check(b != null, "the zone builds")
	if b == null:
		return
	_make_room()
	player.inventory.take(&"pack_patrol_35", 1)  # (a pack: planks are bulky)
	player.inventory.take(&"hammer", 1)
	for k in 4:
		player.inventory.take(&"planks", 5)
	print("  carrying %d planks, %d hammer" % [player.inventory.count_of(&"planks"), player.inventory.count_of(&"hammer")])
	player.global_position = home + Vector3(0.0, 0.3, 0.0)
	await _frames(2)
	var built := false
	var why := ""
	var kind_built := ""
	for kind: String in ["shutter", "fence"]:
		for off: Vector3 in [Vector3(2, 0, 2), Vector3(-2, 0, 2), Vector3(3, 0, -2), Vector3(0, 0, 4), Vector3(4, 0, 0)]:
			var g := level.ground_point(home + off)
			var c := Builder.ground_cell(g)
			if b.server_build_piece_now(player, kind, c, 0) > 0:
				built = true
				kind_built = kind
				break
			why = b.last_problem
		if built:
			break
	if not built:  # (blocks against the wall instead: a board-up of blocks)
		var g2 := level.ground_point(home + Vector3(2, 0, 2))
		var c2 := Builder.ground_cell(g2)
		var made := 0
		for k in 3:
			for dy: int in [0, 1, -1, 2, 3]:
				var bw := b.server_build_now(player, c2 + Vector3i(k, dy, 0), "wood", "block", 0)
				if bw == "":
					made += 1
					var up := b.server_build_now(player, c2 + Vector3i(k, dy + 1, 0), "wood", "block", 0)  # (stacked: boards up a gap)
					made += 1 if up == "" else 0
					if up != "":
						why += "; stacked: " + up
					break
				why += "; block: " + bw
			if made >= FirstHour.SHELTER_BLOCKS:
				break
	FirstHour.server_tick(level)
	check(FirstHour.is_done("shelter"), "boarding a window does the shelter (%s)" % [("a %s built" % kind_built) if built else "pieces refused: " + why + "; blocks"])


func _test_voice() -> void:
	print("Day 2: the voice on the radio")
	Survival.state()["day"] = 2
	Survival.state()["hour"] = 10.0
	FirstHour.server_tick(level)
	var pid := String(FirstHour.data().get("voice_pid", ""))
	var rec: Dictionary = (Survival.state().get("people", {}) as Dictionary).get(pid, {})
	check(not rec.is_empty() and FirstHour.is_open("voice"), "a lone survivor is placed (%s)" % String(rec.get("name", "nobody")))
	check(SurvivalMap.marks("").any(func(m: Dictionary) -> bool: return String(m.get("text", "")).begins_with("The voice on the radio")), "and marked on the map")
	check(_journal_has("The old set in the kitchen crackled"), "the journal has the call")
	if rec.is_empty():
		return
	var layer := SurvivorsLayer.find(level)
	player.global_position = SurvivorPerson.pos_of(rec) + Vector3(1.5, 0.5, 0.0)
	await _wait_for(func() -> bool: return layer.body_of(pid) != null, 8.0)
	var body := layer.body_of(pid)
	var said := ""
	if body:
		player.global_position = body.global_position + Vector3(1.2, 0.2, 0.0)
		await _frames(2)
		said = TalkMenu.server_talk(layer, player, body, "recruit")
	if not String(rec.get("status", "")) in ["companion", "settler"]:
		layer.server_recruit(rec, player)
		said += " (recruited directly: no body came)"
	FirstHour.server_tick(level)
	check(FirstHour.is_done("voice"), "recruiting them does the voice (%s)" % said)
	Survival.state()["day"] = 1
	Survival.state()["hour"] = 12.0


## Empties the survivor's pockets and packs (his clothes stay on): room for what a check gives him.
func _make_room() -> void:
	for c: StringName in player.inventory.search_containers():
		var list: Array = player.inventory.containers.get(c, [])
		while not list.is_empty():
			var before := list.size()
			player.inventory.remove_entry(c, 0, int((list[0] as Dictionary).get("count", 1)))
			list = player.inventory.containers.get(c, [])
			if list.size() >= before:
				break


# --- Hints ----------------------------------------------------------------------------------------

func _situate(id: String) -> void:
	match id:
		"silent_kill":
			var back := player.global_basis.z
			back.y = 0.0
			var z := Survival.server_spawn_zombie(level, level.ground_point(player.global_position + back.normalized() * 12.0), "walker")
			if z:
				z.set_meta(&"firsthour_test", true)
				z.look_at(z.global_position - back, Vector3.UP)  # (facing away: it hasn't seen him)
				z.rotation.x = 0.0
				var brain := ZombieAI.of(z)
				if brain:
					brain.mode = ZombieAI.Mode.IDLE
		"night":
			Survival.state()["hour"] = 22.0
		"container":
			for c: Node in get_tree().get_nodes_in_group(WorldCache.GROUP):
				player.global_position = (c as Node3D).global_position + Vector3(1.0, 0.3, 0.0)
				break
		"load_mags":
			player.inventory.take(&"rounds_9mm", 10)
			player.inventory.take(&"mag_9mm", 1)
		"injury":
			player.vitals.server_hit(Vitals.FOREARM_L, {"round_class": Vitals.FRAGMENT})
		"build_kit":
			_make_room()
			player.inventory.take(&"planks", 2)
		"hungry":
			var n := Survival.needs_of(player)
			Needs.respawn(n, 20.0)
		"melee":
			player.inventory.slots[&"sidearm"] = &"crowbar"
			player.active_slot = &"sidearm"


func _test_hints() -> void:
	print("Control hints: once each, off silences them, Field notes")
	FieldHints.reset_seen()
	FirstHour._sent.clear()
	var at := player.global_position
	for id: String in FieldHints.ORDER:
		_situate(id)
		await _frames(1)
		var ok := FirstHour.situation(level, player, id)
		FirstHour._hint_tick(level)
		FirstHour._hint_tick(level)
		check(FieldHints.shown_log.count(id) == 1, "%s: the situation (%s) shows it once (%d)" % [id, "holds" if ok else "not met", FieldHints.shown_log.count(id)])
	# Once per profile: a new session (the host forgets) still doesn't show it again.
	var shown := FieldHints.shown_log.size()
	FirstHour._sent.clear()
	FirstHour._hint_tick(level)
	check(FieldHints.shown_log.size() == shown, "a new session: none again (%d shown, %d before)" % [FieldHints.shown_log.size(), shown])
	var js := JournalScreen.new()
	add_child(js)
	js.tab = "notes"
	js.show_view(JournalScreen.view())
	var t := js.text()
	check(t.contains("Field notes") and t.contains("Melee:") and t.contains("Night:") and t.contains(FieldHints.key_name("interact")), "the journal's Field notes lists them")
	js.queue_free()
	# Off: silenced.
	GameSettings.set_value("access", "hints", false)
	FieldHints.reset_seen()
	FirstHour._sent.clear()
	FirstHour._hint_tick(level)
	check(FieldHints.shown_log.is_empty(), "with Hints off nothing shows (%s)" % str(FieldHints.shown_log))
	GameSettings.set_value("access", "hints", true)
	# Tidy: the situations undone.
	for z: Soldier in Survival.zombies(level):
		if z.has_meta(&"firsthour_test"):
			z.queue_free()
	player.vitals.server_reset_health()
	Needs.respawn(Survival.needs_of(player), 90.0)
	player.active_slot = &"primary"
	Survival.state()["hour"] = 12.0
	player.global_position = at


func _test_now() -> void:
	print("Now: the front page and the landmarks visited")
	var zone := String(Survival.state().get("zone", ""))
	FirstHour._visit(level)
	var near := Landmarks.nearest(player.global_position, zone)
	var v := FirstHour.visited(zone)
	var near_d := (near.pos as Vector2).distance_to(Vector2(player.global_position.x, player.global_position.z)) if not near.is_empty() else INF
	check(near_d > FirstHour.VISIT_M or v.has(String(near.name)), "the landmark he stands by is visited (%s, %.0f m)" % [String(near.get("name", "none")), near_d])
	var un := FirstHour.nearest_unvisited(zone, player.global_position)
	check(not un.is_empty() and not v.has(String(un.name)), "the nearest unvisited landmark is named (%s)" % str(un))
	var js := JournalScreen.new()
	add_child(js)
	js.show_view(JournalScreen.view())
	var t := js.text()
	check(t.contains("Now") and t.contains("Nearest place not yet seen"), "the journal's front page shows Now and the nearest unvisited place")
	js.queue_free()


# --- The dead's density (the Captain: "nearly non existent out in the wild and near AI farms") ---

func _clear_dead() -> void:
	for z: Soldier in Survival.zombies(level):
		z.queue_free()
	(Survival.state().get("pressure", {}) as Dictionary).erase(String(Survival.state().get("zone", "")))
	Survival._last_spawn.clear()
	Survival._area.clear()
	var crowd := ZoneDead.of(level)
	if crowd:
		for d: Dictionary in crowd.dead:
			if bool(d.get("horde", false)):
				d["alive"] = false


func _open_point(from: Vector3, min_m: float) -> Vector3:
	var half := float(level.def.get("size_m", 1920.0)) * 0.5 - 120.0
	for k in 64:
		var a := k * TAU / 64.0
		for r: float in [min_m, min_m + 150.0, min_m + 300.0]:
			var p := from + Vector3(cos(a), 0.0, sin(a)) * r
			if absf(p.x) > half or absf(p.z) > half:
				continue
			p = level.ground_point(p)
			if level.module_at(p) == null and not FirstHour.in_quiet(p) and _site_m(p) > FirstHour.DRAW_SITE_M + 30.0:
				return p
	return level.ground_point(from + Vector3(min_m, 0, 0))


func _site_m(p: Vector3) -> float:
	var best := INF
	for m: ZoneModule in level.modules():
		best = minf(best, Vector2(m.global_position.x - p.x, m.global_position.z - p.z).length())
	return best


## Walks `seconds` (simulated) from `start` along `dir` at 1.4 m/s (a call to _populate a POP_TICK_S),
## turning back at the zone's edge; returns {"spawned", "close"} (bodies new about him; came within 20 m).
func _walk(start: Vector3, dir: Vector3, seconds: float, circle_round := Vector3.INF, radius := 120.0) -> Dictionary:
	_clear_dead()
	await _frames(2)
	var seen := {}
	for z: Soldier in Survival.zombies(level):
		seen[z.get_instance_id()] = true
	var spawned := 0
	var close := 0
	var near_farm := 0
	var half := float(level.def.get("size_m", 1920.0)) * 0.5 - 80.0
	var p := start
	var steps := int(seconds / Survival.POP_TICK_S)
	for i in steps:
		if circle_round.is_finite():
			var a := float(i) / steps * TAU * 2.0
			p = circle_round + Vector3(cos(a), 0, sin(a)) * radius
		else:
			p += dir * 1.4 * Survival.POP_TICK_S
			if absf(p.x) > half or absf(p.z) > half:
				dir = -dir
				p += dir * 2.8 * Survival.POP_TICK_S
		player.global_position = level.ground_point(p) + Vector3.UP * 0.2
		Survival._populate(level)
		for z: Soldier in Survival.zombies(level):
			var zid := z.get_instance_id()
			if not seen.has(zid):
				seen[zid] = true
				spawned += 1
				if circle_round.is_finite() and z.global_position.distance_to(circle_round) <= FirstHour.QUIET_M:
					near_farm += 1
			if z.global_position.distance_to(player.global_position) <= 20.0:
				close += 1
		if i % 5 == 0:
			await get_tree().process_frame
	return {"spawned": spawned, "close": close, "near_farm": near_farm}


func _test_density() -> void:
	print("The dead's density: open country and an AI farm, before and after")
	var pop := Survival._pop
	Survival._pop = -1000000.0
	var start := _open_point(FirstHour._v3(FirstHour.data().home), 400.0)
	var after: Dictionary = await _walk(start, Vector3.ZERO, 300.0, start)
	Survival.state()["day"] = 7
	var late: Dictionary = await _walk(start, Vector3.ZERO, 300.0, start)
	Survival.state()["day"] = 1
	Survival.legacy_spawns = true
	var before: Dictionary = await _walk(start, Vector3.ZERO, 300.0, start)
	Survival.legacy_spawns = false
	print("  open country, 5 min walking: before %d new (%d times within 20 m), after %d (%d), day 7 %d (%d)" % [before.spawned, before.close, after.spawned, after.close, late.spawned, late.close])
	check(int(after.spawned) <= 2 and int(after.spawned) <= int(before.spawned), "open country on day 1: a rare wanderer, not a stream (%d in 5 min; before %d)" % [after.spawned, before.spawned])
	check(int(late.spawned) <= 4, "day 7: still only a few (%d)" % late.spawned)
	# An AI farm: a lone survivor's home in the open.
	var layer := SurvivorsLayer.find(level)
	var farm_at := _open_point(start, 300.0)
	var rec := layer.server_add_person(farm_at, {"disposition": "friendly"}) if layer else {}
	FirstHour._quiet_at = -100.0
	check(FirstHour.in_quiet(farm_at + Vector3(100, 0, 0)), "a living person's place is quiet within %.0f m" % FirstHour.QUIET_M)
	var f_after: Dictionary = await _walk(farm_at, Vector3.ZERO, 300.0, farm_at)
	Survival.legacy_spawns = true
	var f_before: Dictionary = await _walk(farm_at, Vector3.ZERO, 300.0, farm_at)
	Survival.legacy_spawns = false
	print("  round an AI farm, 5 min: before %d new (%d within %.0f m of it), after %d (%d)" % [f_before.spawned, f_before.near_farm, FirstHour.QUIET_M, f_after.spawned, f_after.near_farm])
	check(int(f_after.near_farm) == 0, "none come about a survivor near an AI farm (before %d)" % f_before.near_farm)
	# Towns stay dangerous.
	var town := _town_module()
	if town:
		var t_near := Survival.dead_near(level, town.global_position)
		check(t_near >= 4, "a site nobody holds keeps its dead (%s: %d about a survivor there)" % [town.module_id, t_near])
		check(Survival.spawn_gap(level, town.global_position) <= Survival.SITE_GAP_S, "and they come as fast as before there")
	if not rec.is_empty():
		rec["status"] = "dead"  # (out of the quiet list for what follows)
	FirstHour._quiet_at = -100.0
	_clear_dead()
	Survival._pop = pop


func _town_module() -> ZoneModule:
	FirstHour._quiet_at = -100.0
	for base: String in ["city", "town", "village", "compound", "outpost", "checkpoint"]:
		for m: ZoneModule in level.modules():
			if ZoneModules.base(String(m.type)) == base and not FirstHour.in_quiet(m.global_position):
				return m
	return null


## Shots every 2 s for 3 simulated minutes at `at`: the crowd stepped, the pressure ticked, the dead
## kept about him; returns {"arrived" (bodies new about him), "far" (the farthest a crowd head that
## became a body started from), "hordes"}.
func _shoot(at: Vector3) -> Dictionary:
	_clear_dead()
	Survival._horde_at = -100000.0
	player.global_position = at + Vector3.UP * 0.2
	await _frames(2)
	var crowd := ZoneDead.of(level)
	var start := {}
	if crowd:
		var k := 0
		for d: Dictionary in crowd.dead:
			if d.alive:
				k += 1
				d["_fh"] = k
				start[k] = d.pos
	var seen := {}
	for z: Soldier in Survival.zombies(level):
		seen[z.get_instance_id()] = true
	var hordes0 := int(Survival.state().get("hordes", 0))
	var arrived := 0
	var far := 0.0
	for i in 90:
		Survival.server_noise(player, at, ZombieAI.SHOT_HEARD_M, ZombieAI.HEAR_SHOT)
		Survival.state()["hour"] = Survival.hour() + 2.0 / (Survival.DAY_MIN * 60.0) * 24.0
		if crowd:
			crowd._physics_process(1.0)
			crowd._physics_process(1.0)
		Survival._populate(level)
		Survival._pressure_tick(level, 2.0)
		for z: Soldier in Survival.zombies(level):
			if not seen.has(z.get_instance_id()):
				seen[z.get_instance_id()] = true
				arrived += 1
		if crowd:
			var still := {}
			for d: Dictionary in crowd.dead:
				if d.has("_fh") and bool(d.alive):
					still[int(d["_fh"])] = true
			for k2: Variant in start.keys():
				if not still.has(k2):
					far = maxf(far, (start[k2] as Vector2).distance_to(Vector2(at.x, at.z)))
					start.erase(k2)
		if i % 5 == 0:
			await get_tree().process_frame
	return {"arrived": arrived, "far": far, "hordes": int(Survival.state().get("hordes", 0)) - hordes0, "pressure": Survival.pressure(level)}


func _test_shots() -> void:
	print("Shots: the dead that are there, not a stream")
	var pop := Survival._pop
	Survival._pop = -1000000.0
	Survival.state()["day"] = 3
	Survival.state()["hour"] = 12.0
	var open := _open_point(FirstHour._v3(FirstHour.data().home), 450.0)
	var o_after: Dictionary = await _shoot(open)
	Survival.legacy_spawns = true
	var o_before: Dictionary = await _shoot(open)
	Survival.legacy_spawns = false
	print("  open country, a shot every 2 s for 3 min: before %d arrived (farthest from %.0f m), %d hordes, pressure %.0f; after %d (%.0f m), %d hordes, pressure %.0f" % [
		o_before.arrived, o_before.far, o_before.hordes, o_before.pressure, o_after.arrived, o_after.far, o_after.hordes, o_after.pressure])
	check(int(o_after.hordes) == 0 and int(o_after.arrived) * 3 <= int(o_before.arrived) + 3, "in the open, shooting draws the few that are there and no horde (%d, %d hordes; before %d)" % [o_after.arrived, o_after.hordes, o_before.arrived])
	check(float(o_after.far) <= ZombieAI.SHOT_HEARD_M + FirstHour.HEARD_MARGIN_M + 80.0, "nothing walks in from beyond the heard radius (%.0f m)" % o_after.far)
	var town := _town_module()
	if town:
		var by_town := level.ground_point(town.global_position + Vector3(40, 0, 0))
		var t_after: Dictionary = await _shoot(by_town)
		Survival.legacy_spawns = true
		var t_before: Dictionary = await _shoot(by_town)
		Survival.legacy_spawns = false
		print("  by %s, the same: before %d arrived (%.0f m), %d hordes; after %d (%.0f m), %d hordes, pressure %.0f" % [town.module_id, t_before.arrived, t_before.far, t_before.hordes,
			t_after.arrived, t_after.far, t_after.hordes, t_after.pressure])
		check(int(t_after.arrived) >= int(o_after.arrived) and float(t_after.pressure) > float(o_after.pressure), "a town stays dangerous: more come, the pressure builds (%d, %.0f)" % [t_after.arrived, t_after.pressure])
	Survival.state()["day"] = 1
	Survival.state()["hour"] = 12.0
	_clear_dead()
	Survival._pop = pop


# --- Pacing the first night --------------------------------------------------------------------------

func _horde_now(d: int, h: float, point: Vector3) -> int:
	Survival.state()["day"] = d
	Survival.state()["hour"] = h
	Survival._horde_at = -100000.0
	var all: Dictionary = Survival.state().get("pressure", {})
	all[String(Survival.state().get("zone", ""))] = {"v": 100.0, "at": d + h / 24.0, "x": point.x, "y": point.y, "z": point.z}
	Survival.state()["pressure"] = all
	var before := int(Survival.state().get("hordes", 0))
	Survival._pressure_tick(level, 0.1)
	return int(Survival.state().get("hordes", 0)) - before


func _test_pacing() -> void:
	print("The first night: softened at Normal, hard at High")
	var town := _town_module()
	var point := town.global_position if town else player.global_position
	check(_horde_now(1, 22.0, point) == 0, "no horde on night 1 at Normal")
	check(_horde_now(2, 3.0, point) == 0, "nor in its small hours")
	check(_horde_now(2, 22.0, point) == 1, "one can on night 2")
	Survival.state()["day"] = 1
	Survival.state()["hour"] = 22.0
	check(is_equal_approx(FirstHour.night_bonus_share(), 0.0), "the dead's night pace bonus is off on night 1")
	Survival.state()["day"] = 2
	check(is_equal_approx(FirstHour.night_bonus_share(), 0.5), "half on night 2")
	Survival.state()["day"] = 3
	check(is_equal_approx(FirstHour.night_bonus_share(), 1.0), "all of it from night 3")
	Survival.server_set_options({"dead": "high"})
	check(_horde_now(1, 22.0, point) == 1 and is_equal_approx(FirstHour.night_bonus_share(), 1.0), "High keeps the hard first night (a horde can come, full night pace)")
	Survival.server_set_options({"dead": "normal"})
	(Survival.state().get("pressure", {}) as Dictionary).erase(String(Survival.state().get("zone", "")))


# --- Plumbing --------------------------------------------------------------------------------------

func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _finish() -> void:
	Survival.legacy_spawns = false
	if Survival.world != "":
		GameState.delete_save()
		Survival.running = false
		Campaign.reset_campaign()
	print("FIRSTHOUR TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
