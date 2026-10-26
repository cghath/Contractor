extends Node
## Survival polish (docs/survival_polish.md; calls 134, 136, 139, 141, 142): the 3D loadout
## editor puts an item dropped on a pouch's hotspot INTO that pouch and a saved kit restores it
## (and a survival kit refills its pouches); Wait passes the time to dusk and something coming
## stops it; Continue lists two saved worlds and carries on the one picked (the other put away,
## not deleted), and New world warns on a name in use; a wall built between two points changes
## a zombie's path within a second; the colour-blind-safe toggle swaps the ring's palette and
## shapes; the text scale resizes a HUD label; the tension toggle silences the layer; a bark
## shows a subtitle (and the toggle hides it); the survival screens fit the 10 window sizes.

const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1920, 1200),
	Vector2i(2000, 1250), Vector2i(2560, 1440), Vector2i(2560, 1600), Vector2i(3440, 1440), Vector2i(3840, 2160)]

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier
var _vp: SubViewport
var _other_world := ""


func _ready() -> void:
	get_tree().create_timer(390.0).timeout.connect(func() -> void:
		print("POLISH TEST FAILED (timed out)")
		get_tree().quit(99))
	GameSettings.use_file(OS.get_user_data_dir().path_join("test_polish_settings%s.cfg" % tag))  # never the player's
	GameSettings.reset_all()
	_vp = SubViewport.new()
	_vp.size = Vector2i(1600, 900)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.gui_disable_input = true
	add_child(_vp)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _test_editor_pouches()
	_test_survival_kit()
	await _test_screens_fit()
	await _test_new_world()
	if level != null and player != null:
		await _test_wait()
		await _test_navmesh()
		await _test_access()
		await _test_world_list()
	GameSettings.set_value("access", "text_scale", 1.0)
	GameSettings.set_value("access", "colour_safe", false)
	_finish()


# --- Call 134: the 3D editor's pouches and pockets ----------------------------------------------

func _test_editor_pouches() -> void:
	print("The 3D loadout editor fills pouches and pockets")
	Campaign.campaign_id = "test_polish_kit" + tag  # never a real save
	BaseHub.new_campaign(7)
	for hire: Dictionary in Hiring.pool(BaseHub.hiring(), BaseHub.day()).slice(0, 1):
		BaseHub.server_hire(String(hire.cid))
	BaseHub.view = BaseHub.build_view()
	var members: Dictionary = BaseHub.view.get("roster", {}).get("members", {})
	var mids := members.keys()
	mids.sort()
	var mate := String(mids[0]) if not mids.is_empty() else ""
	check(mate != "", "a squadmate to kit")
	if mate == "":
		return
	var body := _kitted_body()
	members[mate]["gear"] = Roster.json_safe(body.inventory.net_state)
	body.queue_free()
	# The editor remembers the last person picked on this machine (LoadoutEditor.SETTINGS): kept
	# as it was, so the loadout suite still opens on your own soldier.
	var cfg_was := FileAccess.get_file_as_bytes(LoadoutEditor.SETTINGS) if FileAccess.file_exists(LoadoutEditor.SETTINGS) else PackedByteArray()
	var layer := CanvasLayer.new()
	var editor := LoadoutEditor.new()
	layer.add_child(editor)
	_vp.add_child(layer)
	await _frames(3)
	editor.select(mate)
	editor.focus_region("torso")
	await _frames(20)
	var box := ""
	for b: Dictionary in editor.boxes():
		if String(b.box).begins_with(Inventory.MOLLE_PREFIX) and editor.box_problem(String(b.box), "mag_556") == "":
			box = String(b.box)
			break
	check(box != "", "a mag pouch on the carrier with room for a magazine (%s; boxes: %s)" % [box, editor.boxes().map(func(b: Dictionary) -> String: return String(b.box))])
	var spot: Dictionary = {}
	for a: Dictionary in editor.preview.anchors():
		if String(a.key) == "box:" + box:
			spot = a
	check(not spot.is_empty() and editor.preview.shown(spot), "the pouch has its own hotspot on the model, labelled with its fill (%s)" % String(spot.get("label", "none")))
	check(LoadoutGear.place_of_marker("box:" + box) == "container:" + box and LoadoutGear.marker_of_place("container:" + box) == "box:" + box,
		"the survival gear editor reads the same hotspot as that container (companions' kits)")
	var before := Loadouts.box_count(editor.draft, box, "mag_556")
	var how := "the hotspot"
	var at: Variant = editor.preview.screen_of(spot.at) if not spot.is_empty() else null
	if at != null and editor._box_at(at as Vector2) == box and editor._can_drop_preview(at as Vector2, {"lo_item": "mag_556"}):
		editor._drop_preview(at as Vector2, {"lo_item": "mag_556"})
	else:
		how = "the hotspot's drop (marker off screen in this viewport)"
		editor.drop_on_marker(box, {"lo_item": "mag_556"})
	await _frames(2)
	var inv_count := 0
	for e: Dictionary in editor.preview.inventory.containers.get(StringName(box), []):
		if StringName(String(e.id)) == &"mag_556":
			inv_count += int(e.get("count", 1))
	check(Loadouts.box_count(editor.draft, box, "mag_556") == before + 1 and inv_count == before + 1,
		"a magazine dropped on %s lands INTO that pouch, on the model too (%d to %d)" % [how, before, Loadouts.box_count(editor.draft, box, "mag_556")])
	check(editor.drop_on_marker(box, {"lo_item": "ifak"}) != "", "an IFAK won't go in a mag pouch (%s)" % editor.box_problem(box, "ifak"))
	editor.pick_slot("box:" + box)
	await _frames(1)
	check(editor.find_child("TakeOut_mag_556", true, false) != null and editor.picker_title.text.contains("of"), "picking the pouch lists what's in it with Take out, and its fill (%s)" % editor.picker_title.text)
	# The saved kit: the draft as the roster keeps it, fitted from a stash holding what it names.
	var kit := KitLibrary.clean_template(editor.draft)
	var pool: Array = []
	var counts := Restock.counts(kit)
	for id: String in counts:
		pool.append({"id": id, "count": int(counts[id])})
	var res := Restock.build(kit, pool)
	var fitted := Inventory.new()
	fitted.net_state = GameState.from_json((res.gear as Dictionary).duplicate(true))
	var held := 0
	for e: Dictionary in fitted.containers.get(StringName(box), []):
		if StringName(String(e.id)) == &"mag_556":
			held += int(e.get("count", 1))
	fitted.free()
	check(held == before + 1, "the saved kit restores it: applied, the pouch holds %d magazines (missing %s)" % [held, res.missing])
	editor.take_out(box, "mag_556")
	check(Loadouts.box_count(editor.draft, box, "mag_556") == before, "Take out puts it back in the stash")
	editor.drop_on_marker("pockets", {"lo_item": "ifak"})
	var moved := editor.drop_on_marker(box, {"lo_box": "pockets", "id": "ifak"})
	check(Loadouts.box_count(editor.draft, "pockets", "ifak") == 1 and moved != "", "dragged from the pockets onto a mag pouch, an IFAK stays in the pockets (%s)" % moved)
	layer.queue_free()
	await _frames(2)
	if cfg_was.is_empty():
		DirAccess.remove_absolute(LoadoutEditor.SETTINGS)
	else:
		var f := FileAccess.open(LoadoutEditor.SETTINGS, FileAccess.WRITE)
		f.store_buffer(cfg_was)
		f.close()
	BaseHub.delete_test_campaign_files()
	Campaign.restore({})


func _test_survival_kit() -> void:
	print("A survival kit refills its pouches")
	var body := _kitted_body()
	var inv := body.inventory
	var pouch := StringName("")
	for c: StringName in inv.pouch_containers():
		if inv.units_in(c) > 0:
			pouch = c
	check(pouch != &"", "the body carries magazines in a pouch")
	if pouch == &"":
		body.queue_free()
		return
	var n := inv.units_in(pouch)
	var tpl := CompanionGear.template_of(inv)
	check(int((tpl.get("into", {}) as Dictionary).get(String(pouch), {}).get("mag_556", 0)) == n, "a saved survival kit records what's in each pouch (%s)" % tpl.get("into", {}))
	check(CompanionGear.transfer(inv, "container:" + String(pouch), 0, inv, "container:backpack") == "", "a magazine moved out to the pack")
	CompanionGear.apply_kit(inv, inv, tpl)
	check(inv.units_in(pouch) == n, "applying the kit puts it back INTO the pouch (%d of %d)" % [inv.units_in(pouch), n])
	body.queue_free()


func _kitted_body() -> Soldier:
	var body: Soldier = load("res://scenes/soldier.tscn").instantiate()
	add_child(body)
	body.process_mode = Node.PROCESS_MODE_DISABLED
	for pair: Array in [[&"plate_carrier", 1], [&"pouch_mag_double", 2], [&"assault_pack", 1], [&"m4a1", 1], [&"mag_556", 2]]:
		body.inventory.take(pair[0], pair[1])
	return body


# --- The survival screens at the 10 window sizes ------------------------------------------------

func _test_screens_fit() -> void:
	print("The survival screens fit")
	var screens: Array[String] = ["new world", "continue (world list)", "settings: accessibility"]
	for k: float in [1.0, 1.5]:
		GameSettings.set_value("access", "text_scale", k)
		for screen: String in screens:
			_vp.size = SIZES[0]
			var node := _make_screen(screen)
			_vp.add_child(node)
			await _frames(3)
			var bad := PackedStringArray()
			for res in SIZES:
				_vp.size = Vector2i((Vector2(res) / GameSettings.ui_scale_for(res, 1.0)).floor())
				await _frames(2)
				var off := _off_screen(node, Rect2(Vector2.ZERO, Vector2(_vp.size)).grow(1.0))
				if not off.is_empty():
					bad.append("%dx%d: %s" % [res.x, res.y, ", ".join(off.slice(0, 3))])
			check(bad.is_empty(), "%s at text %d%% fits at %d window sizes%s" % [screen, roundi(k * 100.0), SIZES.size(), "" if bad.is_empty() else ": " + "; ".join(bad)])
			node.queue_free()
			await _frames(2)
	GameSettings.set_value("access", "text_scale", 1.0)


func _make_screen(screen: String) -> Node:
	match screen:
		"new world":
			return NewWorldScreen.new(Callable())
		"continue (world list)":
			return WorldListScreen.new()
	var s := SettingsMenu.new()
	s.ready.connect(func() -> void:
		s.open()
		s._tabs.current_tab = s._tabs.get_tab_count() - 1)
	return s


## Whatever matters under `node` (a button, a field, a line of text, a scroll area) that sits
## outside `window` (ui_test's _off_screen).
func _off_screen(node: Node, window: Rect2) -> PackedStringArray:
	var out := PackedStringArray()
	for child in node.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if child is Control:
			var c := child as Control
			var important := c is BaseButton or c is LineEdit or c is Range or c is ItemList or c is TabContainer or c is ScrollContainer \
				or (c is Label and (c as Label).text.strip_edges() != "")
			if important and c.size.x > 0.0 and not window.encloses(c.get_global_rect()):
				out.append("%s '%s' %s" % [c.get_class(), c.name, c.get_global_rect()])
				continue
			if c is ScrollContainer or c.clip_contents:
				continue
		out.append_array(_off_screen(child, window))
	return out


# --- A world ------------------------------------------------------------------------------------

func _test_new_world() -> void:
	print("A new world")
	check(Survival.server_new_world(main, "test_polish" + tag, 4242), "the menu's New world hosts one")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	await _frames(60)
	check(player != null, "the survivor is in")
	Wear.tick_off = true


# --- Call 136: wait and pass time -------------------------------------------------------------

func _clear_dead() -> void:
	for z: Soldier in Survival.zombies(level):
		z.queue_free()
	var crowd := ZoneDead.of(level)
	if crowd:
		var p2 := Vector2(player.global_position.x, player.global_position.z)
		for d: Dictionary in crowd.dead:
			if (d.pos as Vector2).distance_to(p2) < 200.0:
				d["alive"] = false
	(Survival.state().get("pressure", {}) as Dictionary).erase(String(Survival.state().get("zone", "")))


func _test_wait() -> void:
	print("Wait and pass time")
	_clear_dead()
	var pop := Survival._pop
	Survival._pop = -1000.0
	await _frames(2)
	var n := Survival.needs_of(player)
	Needs.respawn(n, 90.0)
	Survival.state()["hour"] = 16.0
	var ground := ContextResolver.resolve({"kind": "ground"}).map(func(o: Dictionary) -> String: return String(o.get("label", "")))
	check(ground.has("Wait an hour") and ground.has("Wait until dusk") and ground.has("Wait until dawn"), "the ground's menu offers Wait an hour, until dusk, until dawn")
	check(Survival.server_wait(player, "dusk") == "" and SurvivalSleep.is_waiting(n), "somewhere quiet, he waits until dusk")
	check(is_equal_approx(SurvivalSleep.clock_mult(MapNodes.players(level)), SurvivalSleep.SPEED), "everyone waiting: the world runs at x%.0f" % SurvivalSleep.SPEED)
	var sleep0 := float(n.sleep)
	for i in 6:
		if not SurvivalSleep.is_waiting(n):
			break
		Survival.server_tick_survivors(level, 10.0)
	await _frames(2)
	var hud: Hud = player._hud
	var line := hud.message_text() if hud else ""
	check(not SurvivalSleep.is_waiting(n) and absf(Survival.hour() - SurvivalSleep.DUSK_H) < 0.6, "the clock reaches dusk and the wait ends (%.2f h)" % Survival.hour())
	check(line.begins_with("You waited until dusk"), "the HUD says so (%s)" % line)
	check(float(n.sleep) <= sleep0, "waiting isn't sleeping: no rest restored (%.0f to %.0f)" % [sleep0, n.sleep])
	check(Survival.server_wait(player, "dawn") == "" and SurvivalSleep.is_waiting(n), "then he waits for dawn")
	var fwd := -player.global_basis.z
	fwd.y = 0.0
	var z := Survival.server_spawn_zombie(level, level.ground_point(player.global_position + fwd.normalized() * 20.0))
	await get_tree().physics_frame
	if z:
		z.process_mode = Node.PROCESS_MODE_DISABLED
	Survival.server_tick_survivors(level, 0.5)
	await _frames(2)
	line = hud.message_text() if hud else ""
	check(z != null and not SurvivalSleep.is_waiting(n) and line.contains("stop waiting"), "one of the dead in sight 20 m off stops it (%s)" % line)
	if z:
		z.queue_free()
	Survival._pop = pop
	await _frames(2)


# --- Call 141: builds and the navmesh -----------------------------------------------------------

func _test_navmesh() -> void:
	print("Builds and the navmesh")
	_clear_dead()
	var pop := Survival._pop
	Survival._pop = -1000.0
	var b := Builder.find(level)
	check(b != null, "the zone has its Builder")
	if b == null:
		return
	var origin := Vector3i.ZERO
	var found := false
	var start := player.global_position
	for ring: float in [8.0, 12.0, 16.0, 20.0, 26.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var x := start.x + cos(a) * ring
			var zz := start.z + sin(a) * ring
			if _flat_and_clear(b, x, zz):
				origin = Builder.ground_cell(Vector3(x, level.ground_height(x, zz), zz))
				found = true
				break
		if found:
			break
	check(found, "flat open ground near the survivor (%s)" % origin)
	if not found:
		Survival._pop = pop
		return
	var nav := level.nav
	await _wait_for(func() -> bool: return nav != null and nav.is_settled(), 15.0)
	var centre := BuildPieces.cell_centre(origin)
	var from := level.ground_point(centre + Vector3(-3.0, 0.0, 0.0))
	var to := level.ground_point(centre + Vector3(3.0, 0.0, 0.0))
	var map := player.get_world_3d().navigation_map
	var path0 := NavigationServer3D.map_get_path(map, from, to, true, ZombieAI.NAV_LAYERS)
	var wall_x := centre.x
	check(path0.size() >= 2 and _crosses(path0, wall_x, centre.z, 4.0), "before: the path runs straight across (%.1f m)" % _length(path0))
	var z := Survival.server_spawn_zombie(level, from)
	await get_tree().physics_frame
	var brain: ZombieAI = ZombieAI.of(z) if z else null
	if z:
		z.process_mode = Node.PROCESS_MODE_DISABLED
	if brain:
		brain._set_goal(to)
	var zpath0 := brain._path if brain else PackedVector3Array()
	# A wall 9 m long and 2 m high across the line, built at once.
	var flushes := b.nav_flushes
	for y in 4:
		for dz in range(-9, 10):
			var c := origin + Vector3i(0, y, dz)
			var p := BuildPieces.cell_centre(c)
			c = Builder.ground_cell(Vector3(p.x, level.ground_height(p.x, p.z), p.z)) + Vector3i(0, y, 0)
			if b.server_place(null, c, "wood", "block", 0, true) == "":  # (a blueprint: nobody pays; built at once)
				b._finish_block(c, b.blocks[c])
	var built_at := Time.get_ticks_msec()
	var round_it := func() -> bool:
		var p := NavigationServer3D.map_get_path(map, from, to, true, ZombieAI.NAV_LAYERS)
		return b.nav_flushes > flushes and not _crosses(p, wall_x, centre.z, 4.0)
	var changed := await _wait_for(round_it, 3.0)
	var secs := (Time.get_ticks_msec() - built_at) / 1000.0
	var path1 := NavigationServer3D.map_get_path(map, from, to, true, ZombieAI.NAV_LAYERS)
	check(changed and secs <= 1.0, "after: the navigation takes the wall in within a second (%.2f s, %d rebake)" % [secs, b.nav_flushes - flushes])
	check(not _crosses(path1, wall_x, centre.z, 4.0) and (path1.is_empty() or _length(path1) > _length(path0) + 1.0),
		"the path goes round the wall, never through it (%.1f m, was %.1f m)" % [_length(path1), _length(path0)])
	if brain:
		brain._path_t = -1000.0
		brain._set_goal(to)
		check(brain._path != zpath0 and not _crosses(brain._path, wall_x, centre.z, 4.0), "the zombie's own path changes and goes round (%.1f m, was %.1f m)" % [_length(brain._path), _length(zpath0)])
	if z:
		z.queue_free()
	Survival._pop = pop
	await _frames(2)


## Whether `path` crosses the plane x = `x` within `half` m of `zc` (through the wall).
func _crosses(path: PackedVector3Array, x: float, zc: float, half: float) -> bool:
	for i in range(1, path.size()):
		var a := path[i - 1]
		var c := path[i]
		if (a.x - x) * (c.x - x) > 0.0 or is_equal_approx(a.x, c.x):
			continue
		var t := (x - a.x) / (c.x - a.x)
		var zz := lerpf(a.z, c.z, t)
		if absf(zz - zc) <= half:
			return true
	return false


func _length(path: PackedVector3Array) -> float:
	var d := 0.0
	for i in range(1, path.size()):
		d += path[i - 1].distance_to(path[i])
	return d


func _flat_and_clear(b: Builder, x: float, z: float) -> bool:
	var lo := INF
	var hi := -INF
	for dx in range(-8, 9):
		for dz in range(-10, 11):
			var h := level.ground_height(x + dx * 0.5, z + dz * 0.5)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			for up in [0.3, 1.2, 2.2]:
				if b._structure_at(Vector3(x + dx * 0.5, h + up, z + dz * 0.5)):
					return false
	return hi - lo < 0.4


# --- Call 142: accessibility --------------------------------------------------------------------

func _test_access() -> void:
	print("Accessibility")
	var hud: Hud = player._hud
	var tells: Hud.StealthTells = hud._tells if hud else null
	player.noise_radius = 90.0
	player.noise_at = Soldier._now()
	GameSettings.set_value("access", "colour_safe", false)
	check(tells != null and tells.dashes() == 0 and Accessibility.ring_colour() == Accessibility.RING and not tells.eye_boxed()
		and Accessibility.load_shape(MovementRules.Tier.OVERLOADED) == "", "the usual tells: a whole ring, the old colours, no marks")
	GameSettings.set_value("access", "colour_safe", true)
	check(tells != null and tells.dashes() >= Accessibility.RING_DASHES.x and Accessibility.ring_colour() == Accessibility.RING_SAFE
		and Accessibility.eye_colour() == Accessibility.EYE_SAFE and tells.eye_boxed(),
		"colour-blind-safe: the ring blue and dashed (%d dashes), the eye orange and boxed" % [tells.dashes() if tells else -1])
	var marks := {}
	for t in 4:
		marks[Accessibility.load_shape(t)] = Accessibility.load_colour(t)
	check(marks.size() == 4 and Accessibility.load_text(MovementRules.Tier.OVERLOADED).begins_with("■"), "each load tier has its own mark (%s)" % ", ".join(PackedStringArray(marks.keys())))
	player.noise_radius = 10.0
	var quiet := tells.dashes() if tells else 0
	player.noise_radius = 170.0
	check(tells != null and tells.dashes() > quiet, "a louder noise draws more dashes (%d to %d)" % [quiet, tells.dashes() if tells else -1])
	GameSettings.set_value("access", "colour_safe", false)
	# The text scale.
	var label := UiKit.hud_label("Text")
	hud.add_child(label)
	var base := label.get_theme_font_size(&"font_size")
	GameSettings.set_value("access", "text_scale", 1.5)
	await _frames(1)
	var big := label.get_theme_font_size(&"font_size")
	GameSettings.set_value("access", "text_scale", 1.0)
	await _frames(1)
	check(base == UiKit.FONT_HUD and big == roundi(UiKit.FONT_HUD * 1.5) and label.get_theme_font_size(&"font_size") == base,
		"text scale 150%%: a HUD label goes %d to %d px, and back" % [base, big])
	label.queue_free()
	# The tension toggle.
	var fa := FallenAudio.of(level)
	var was := Accessibility.tension_audio()
	var danger := {"zombies": [{"d": 10.0, "mode": ZombieAI.Mode.CHASE, "awareness": 1.0}]}
	if fa:
		Accessibility.set_tension_audio(true)
		for i in 8:
			fa.tension.update(danger, 0.5)
		var loud := fa.tension.drone
		Accessibility.set_tension_audio(false)
		fa.tension.update(danger, 0.5)
		check(loud > 0.3 and fa.tension.drone == 0.0 and fa.tension.heart == 0.0 and not Accessibility.tension_audio(),
			"the tension toggle off silences the drone and heartbeat at once (%.2f to %.2f)" % [loud, fa.tension.drone])
	else:
		check(false, "the zone has its FallenAudio")
	Accessibility.set_tension_audio(was)
	# Subtitles for every bark.
	var subs := hud._subtitles as Callouts.Subtitles if hud else null
	var said := level.people.server_say(player, "Polish test bark") if level.people else false
	await _frames(3)
	var shown := subs != null and Array(subs.feed).any(func(l: String) -> bool: return l.contains("Polish test bark") and l.contains(":"))
	check(said and shown, "a bark shows as a subtitle with the speaker's name (%s)" % [", ".join(subs.feed) if subs else "no subtitles"])
	GameSettings.set_value("access", "subtitles", false)
	await _frames(2)
	check(subs != null and subs.feed.is_empty(), "the subtitles toggle hides them")
	GameSettings.set_value("access", "subtitles", true)


# --- Call 139: the world list -------------------------------------------------------------------

func _test_world_list() -> void:
	print("Continue's world list")
	Survival.state()["day"] = 12
	Survival.server_save()
	var name := Survival.world
	_other_world = "test_polish_b" + tag
	var other := {"version": Campaign.SAVE_VERSION, "sections": {"survival": {"name": "Polish B", "day": 25, "options": {"season": "spring"}},
		"survivors": {"x": {"name": "Ann Hale", "generation": 2}}}}
	var f := FileAccess.open("%s/%s%s.json" % [Campaign.SAVE_DIR, Survival.PREFIX, _other_world], FileAccess.WRITE)
	f.store_string(JSON.stringify(other))
	f.close()
	var picked := [""]
	var screen := WorldListScreen.new(func(id: String) -> void: picked[0] = id)
	_vp.add_child(screen)
	await _frames(2)
	var ids := screen.ids()
	var info: Dictionary = {}
	for w: Dictionary in Survival.worlds():
		if String(w.id) == _other_world:
			info = w
	check(ids.has(name) and ids.has(_other_world), "Continue lists both saved worlds (%s)" % ", ".join(ids))
	check(String(info.get("name", "")) == "Polish B" and int(info.get("day", 0)) == 25 and String(info.get("season", "")) == "autumn"
		and String(info.get("survivor", "")) == "Ann Hale" and int(info.get("generation", 0)) == 2 and String(info.get("played_text", "")) != "",
		"each with its name, day, season, survivor and generation, last played (%s)" % WorldListScreen.line_of(info) if not info.is_empty() else "no line")
	var nws := NewWorldScreen.new(Callable())
	_vp.add_child(nws)
	await _frames(1)
	nws.set_world_name("Polish fresh name")
	var fresh := nws.check_name()
	nws.set_world_name("test_polish" + tag)
	check(fresh == "" and nws.check_name() != "" and nws.name_warning.visible, "New world warns on a name in use, not on a new one")
	nws.queue_free()
	var archive_dir := "%s/test_polish_archive%s" % [Campaign.SAVE_DIR, tag]
	screen.archive(_other_world, archive_dir)
	check(not screen.ids().has(_other_world) and FileAccess.file_exists("%s/%s%s.json" % [archive_dir, Survival.PREFIX, _other_world]),
		"Put away moves its save into an archive folder, not deleted")
	DirAccess.remove_absolute("%s/%s%s.json" % [archive_dir, Survival.PREFIX, _other_world])
	DirAccess.remove_absolute(archive_dir)
	var play := screen.find_child("Play_" + name, true, false) as Button
	if play:
		play.pressed.emit()
	check(picked[0] == name, "picking a world hands its id to Continue (%s)" % picked[0])
	Survival.state()["day"] = 1
	Net.leave()  # (back at the menu)
	await get_tree().process_frame
	check(Survival.server_continue(main, String(picked[0])), "Continue hosts the picked world")
	level = SurvivalLevel.of(self)
	check(level != null and Survival.world == name and Survival.day() == 12, "where it was left: day %d" % Survival.day())
	await _wait_for(func() -> bool: return level != null and level.players.get_node_or_null(^"1") != null, 20.0)


# --- Bits ---------------------------------------------------------------------------------------

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
	if _other_world != "":
		for path: String in GameState.save_candidates("%s/%s%s.json" % [Campaign.SAVE_DIR, Survival.PREFIX, _other_world]):
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
	if Survival.world != "":
		GameState.delete_save()
		Survival.running = false
		Campaign.reset_campaign()
	print("POLISH TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
