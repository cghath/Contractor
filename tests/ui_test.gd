extends Node
## Headless UI fit checks (Captain, 2026-10-14, playtesting v0.3.1: "all of the UIs need a
## pass"; docs/ui_audit.md). Every screen that can be built without a level is opened in a
## SubViewport the size of each common window (divided by the Menu and HUD size setting, as the
## root's content_scale_factor does) and nothing that matters (a button, a field, a list, a line
## of text, or the scroll area holding them) may sit outside it. Screens still waiting for their
## follow-up branch are in KNOWN: their overflows are printed, not failed, and a KNOWN entry
## that fits everywhere fails so it gets taken off the list. And the shared look (UiKit, the
## theme) loads and builds.
## Run from the project folder with:
##   <voxel godot exe> --headless --path . res://tests/ui_test.tscn

const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1920, 1200),
	Vector2i(2000, 1250), Vector2i(2560, 1440), Vector2i(2560, 1600), Vector2i(3440, 1440), Vector2i(3840, 2160)]
## The Menu and HUD size setting at its default, the Captain's 1.2, 1.5 and its maximum. It
## multiplies the window's own scale (GameSettings.ui_scale_for: height / 1080, 1.0 to 2.0;
## docs/ui_audit.md P1-7), so each window is divided by that, as the root's
## content_scale_factor does.
const UI_SCALES: Array[float] = [1.0, 1.2, 1.5, 2.0]
## "<screen> @<scale>" entries known to overflow, each waiting for its follow-up branch
## (docs/ui_audit.md, "Follow-up branches"). Take an entry off when its branch fixes it.
const KNOWN: Array[String] = [
	"contract board @2.0", "shop @2.0",  # ui/campaign-screens @2.0 (auto-scale)
	"base: squad @2.0", "base: roster @2.0", "base: hiring @2.0", "base: medbay @2.0", "base: shop @2.0", "base: armory @2.0",  # ui/base-hub @2.0 (auto-scale)
]

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var _vp: SubViewport
## Overflows by screen and scale, for the summary table.
var _report := {}


func _ready() -> void:
	GameSettings.use_file(OS.get_user_data_dir().path_join("test_ui_settings%s.cfg" % tag))  # never the player's
	GameSettings.reset_all()
	Campaign.campaign_id = "test_ui" + tag  # never touch a real save
	_vp = SubViewport.new()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.gui_disable_input = true
	add_child(_vp)
	_test_kit()
	_test_auto_scale()
	await _fit("pause menu", func() -> Node:
		var p := PauseMenu.new()
		p.ready.connect(p.open)
		return p)
	await _fit("settings", func() -> Node:
		var s := SettingsMenu.new()
		s.ready.connect(s.open)
		return s)
	await _fit("main menu", func() -> Node: return Menu.new())
	await _fit("bug report", func() -> Node:
		var b := BugReport.new()
		b.ready.connect(func() -> void: b.visible = true)
		return b)
	await _fit("contract board", func() -> Node: return ContractBoard.new())
	await _fit("shop", func() -> Node: return ShopScreen.new())
	# A full board with an offer picked (details and negotiation up), as the Captain sees it
	# (ui/campaign-screens, docs/ui_audit.md P0-5).
	Contracts.new_full_campaign(71, 100000)
	await _fit("contract board (offer picked)", func() -> Node:
		var b := ContractBoard.new()
		b.ready.connect(func() -> void: b.select_offer(0))
		return b)
	await _fit("debrief (empty)", func() -> Node: return DebriefScreen.new())
	BaseHub.new_campaign(7)
	BaseHub.view = BaseHub.build_view()
	for page: String in BaseUI.PAGES:
		await _fit("base: " + page, func() -> Node:
			var ui := BaseUI.new()
			ui.ready.connect(func() -> void: ui.open(page))
			return ui)
	await _fit("objectives panel", func() -> Node: return _in_layer(ObjectivesPanel.new()))
	await _fit("ammo readout", func() -> Node: return _in_layer(AmmoReadout.new()))
	## The command menu needs no level to draw (ui/small-screens, P2-19). Every level is fitted,
	## not one picked as the longest: the root (ten rows, what opens first) is the tallest, and
	## the deep ones carry the longest selection path (review of ui/small-screens).
	for stack: Array in _menu_levels(CommandMenu.MENU, [CommandMenu.MENU]):
		var labels := PackedStringArray()
		for i in range(1, stack.size()):
			labels.append(stack[i]["label"])
		await _fit("command menu" + ("" if labels.is_empty() else ": " + " > ".join(labels)), func() -> Node:
			var menu := CommandMenu.new(null)
			menu.ready.connect(func() -> void:
				menu.open()
				menu._stack = stack.duplicate()
				menu._redraw())
			return _in_layer(menu))
	# The drawn menus (P0-2, P0-3): what they draw, by name, laid out at each size.
	await _fit_drawn("medical menu", func() -> Node: return _in_layer(MedicalMenu.new()), _medical_rects)
	await _fit_drawn("interaction menu", func() -> Node: return _in_layer(InteractionMenu.new()), _interaction_rects)
	await _test_long_submenu()
	var body := _inventory_body()
	await _fit("inventory", func() -> Node: return _in_layer(InventoryScreen.new(body)))
	await _test_inventory(body)
	body.queue_free()
	await _frames(2)
	await _test_hud()
	_summary()
	GameSettings.reset_all()
	GameSettings.use_file("")
	GameState.delete_save()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("UI TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


## The theme loads with its styles, and the kit's builders make what they say.
## The window picks its own UI scale and the setting multiplies it (docs/ui_audit.md P1-7).
func _test_auto_scale() -> void:
	print("The automatic UI scale")
	check(is_equal_approx(GameSettings.auto_ui_scale(Vector2i(1280, 720)), 1.0) and is_equal_approx(GameSettings.auto_ui_scale(Vector2i(2560, 1440)), 1440.0 / 1080.0)
		and is_equal_approx(GameSettings.auto_ui_scale(Vector2i(3840, 2160)), 2.0) and is_equal_approx(GameSettings.auto_ui_scale(Vector2i(7680, 4320)), 2.0),
		"the window's own scale is its height / 1080, 1.0 to 2.0")
	check(is_equal_approx(GameSettings.ui_scale_for(Vector2i(3840, 2160), 1.2), 2.4) and is_equal_approx(GameSettings.ui_scale_for(Vector2i(1920, 1080), 1.2), 1.2),
		"the Menu and HUD size multiplies it")
	check(is_equal_approx(GameSettings.ui_scale_for(Vector2i(1280, 720), 2.0), 1.5), "but never shrinks the logical window below 1280x720 at 150%")
	check(is_equal_approx(float(GameSettings.RANGES.ui_scale[1]), 2.0), "the Menu and HUD size goes up to 200%")


func _test_kit() -> void:
	print("The shared look (UiKit, themes/contractor_ui.tres)")
	var theme := UiKit.THEME
	check(theme != null and theme.default_font_size == UiKit.FONT_BODY and theme.has_stylebox(&"panel", &"PanelContainer")
		and theme.has_stylebox(&"focus", &"Button") and theme.get_font_size(&"font_size", &"HeadingLabel") == UiKit.FONT_HEADING
		and theme.get_type_variation_base(&"HintLabel") == &"Label", "the theme: 16 px body, panel, button focus, heading and hint variations")
	var layer := CanvasLayer.new()
	_vp.size = Vector2i(800, 600)
	_vp.add_child(layer)
	var box := UiKit.screen(layer, 2000.0)
	var row := UiKit.row("Label", HSlider.new())
	box.add_child(row)
	var buttons := UiKit.button_row([UiKit.button("One", func() -> void: pass), UiKit.button("Two", func() -> void: pass)])
	box.add_child(buttons)
	box.add_child(UiKit.key_hint("Esc", "Close"))
	box.add_child(UiKit.budget_bar(120.0, 100.0, "$120 of $100"))
	check(box.custom_minimum_size.x < 800.0 and box.custom_minimum_size.x >= 200.0,
		"a screen asked for 2000 px is fitted to an 800 px window (%.0f)" % box.custom_minimum_size.x)
	check((box.get_parent() as PanelContainer) != null and (box.get_parent().get_parent().get_parent() as ScrollContainer).theme == UiKit.THEME,
		"inside a themed, scrolling panel")
	## Freed after: labels never put in the tree leaked at exit (with the font and styles they hold).
	var heading := UiKit.heading("H")
	var hint := UiKit.hint("h")
	var text := UiKit.text("t")
	check(heading.theme_type_variation == &"HeadingLabel" and hint.autowrap_mode != TextServer.AUTOWRAP_OFF
		and text.autowrap_mode != TextServer.AUTOWRAP_OFF, "headings and hints in their styles; text wraps")
	for label: Label in [heading, hint, text]:
		label.free()
	layer.queue_free()


## A body for the inventory screen (docs/ui_audit.md item 6): an AI soldier in the test's own
## tree with its processing off (there's no level to stand in), in a carrier with two pouches,
## a pack, a rifle, magazines and loose rounds, so every kind of tile and section is built.
func _inventory_body() -> Soldier:
	var body: Soldier = load("res://scenes/soldier.tscn").instantiate()
	body.name = "UiTestBody"
	add_child(body)
	body.process_mode = Node.PROCESS_MODE_DISABLED
	for pair: Array in [[&"plate_carrier", 1], [&"pouch_mag_double", 2], [&"assault_pack", 1], [&"m4a1", 1], [&"mag_556", 4], [&"rounds_556", 60]]:
		body.inventory.take(pair[0], pair[1])
	return body


## The inventory screen in the shared look (audit item 6, P1-8 and P1-15): themed, nothing under
## 14 px, every button and tile reachable from the keyboard (focusing a tile selects it), and
## the soldier's two tile columns not overlapping, from the smallest layout (1280x720 at 1.5)
## to the biggest (3840x2160 at 1.0).
func _test_inventory(body: Soldier) -> void:
	print("Inventory screen: theme, text sizes, keyboard, columns")
	for layout: Vector2i in [Vector2i((Vector2(1280, 720) / 1.5).floor()), Vector2i(3840, 2160)]:
		_vp.size = layout
		var layer := _in_layer(InventoryScreen.new(body))
		_vp.add_child(layer)
		await _frames(3)
		var screen := layer.get_child(0).get_child(0) as InventoryScreen
		var small := PackedStringArray()
		for label: Label in screen.find_children("*", "Label", true, false):
			if label.is_visible_in_tree() and label.text.strip_edges() != "" and label.get_theme_font_size(&"font_size") < UiKit.FONT_SMALL:
				small.append("'%s' %d px" % [label.text.left(24), label.get_theme_font_size(&"font_size")])
		check(screen.theme == UiKit.THEME and small.is_empty(), "%dx%d: themed, no text under %d px%s" % [layout.x, layout.y, UiKit.FONT_SMALL, "" if small.is_empty() else ": " + ", ".join(small)])
		var unreachable := PackedStringArray()
		for b: BaseButton in screen.find_children("*", "BaseButton", true, false):
			if b.focus_mode == Control.FOCUS_NONE:
				unreachable.append((b as Button).text if b is Button else String(b.name))
		var tiles_focus := screen._tiles.all(func(t: Array) -> bool: return (t[0] as Control).focus_mode == Control.FOCUS_ALL)
		check(unreachable.is_empty() and tiles_focus and screen._tiles.size() >= 6,
			"every button and all %d tiles take keyboard focus%s" % [screen._tiles.size(), "" if unreachable.is_empty() else " (not: %s)" % ", ".join(unreachable)])
		var entry: Array = []
		for t: Array in screen._tiles:
			if t[1].kind == "entry" and entry.is_empty():
				entry = t
		if not entry.is_empty():
			(entry[0] as Control).grab_focus()
			await _frames(1)
			check(screen._is_selected(entry[1]) and (entry[0] as Control).has_focus(), "%dx%d: focusing a tile (the arrow keys) selects it" % [layout.x, layout.y])
			# Review, ui/inventory: the selected item going away (a mouse drag to the ground, or
			# Drop) puts the focus back without selecting whatever tile it lands on.
			var src: Dictionary = entry[1]
			var list: Array = body.inventory.containers[src.container]
			var removed := body.inventory.remove_entry(src.container, src.index, list[src.index].count)
			screen._redraw()
			await _frames(1)
			var owner := screen.get_viewport().gui_get_focus_owner()
			check(screen.selected.is_empty() and owner != null and screen.is_ancestor_of(owner),
				"%dx%d: removing the selected item keeps the focus on the screen and selects nothing (%s)" % [layout.x, layout.y, "nothing" if screen.selected.is_empty() else String(screen.selected.get("id", ""))])
			body.inventory.insert_entry(src.container, removed)
			screen._redraw()
			await _frames(1)
		# Review, ui/inventory: every scroll follows the keyboard focus, so the last tile of the
		# containers list is scrolled into view when it's focused.
		var scrolls: Array = [screen._containers_box, screen._detail_box, screen._left_slots, screen._right_slots].map(
			func(box: Control) -> ScrollContainer: return box.get_parent() as ScrollContainer)
		check(scrolls.all(func(sc: ScrollContainer) -> bool: return sc != null and sc.follow_focus),
			"%dx%d: the containers, details and both slot-column scrolls (%d) follow the focus" % [layout.x, layout.y, scrolls.size()])
		var last: Control = null
		for t: Array in screen._tiles:
			if t[1].kind == "entry":
				last = t[0]
		if last:
			last.grab_focus()
			await _frames(3)
			var sc := screen._containers_box.get_parent() as ScrollContainer
			var shown := sc.get_global_rect().grow(1.0)
			check(shown.encloses(last.get_global_rect()), "%dx%d: the focused last container tile is scrolled into view (%s in %s)" % [layout.x, layout.y, last.get_global_rect(), sc.get_global_rect()])
		var left := screen._left_slots.get_parent() as Control
		var right := screen._right_slots.get_parent() as Control
		check(left.get_global_rect().end.x <= right.get_global_rect().position.x + 0.5 and screen._wide_w >= InventoryScreen.WIDE_TILE_MIN,
			"%dx%d: the soldier's two tile columns don't overlap (%.0f..%.0f, tiles %.0f px)" % [layout.x, layout.y, left.get_global_rect().end.x, right.get_global_rect().position.x, screen._wide_w])
		layer.queue_free()
		await _frames(2)
## The in-game HUD in a hosted level (docs/ui_audit.md item 4, ui/hud-pass), the way map_test
## hosts one: everything it can show at once, filled in at its longest (a full squad list and
## the command menu, objectives and hint, the dev hot-zone readout, four radio lines over a
## vehicle readout, the prompt and a flash message; then downed), at every window size and UI
## scale. Nothing may run off the window, and no two HUD zones may overlap.
func _test_hud() -> void:
	print("The HUD in a hosted level")
	GameState.zone_id = "test_ui" + tag  # never touch a real save
	GameState.delete_save()
	BaseHub.cancel_session()
	CompoundLevel.spawn_ai = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.get_node(^"Menu").host()
	var level := CompoundLevel.current(self)
	var waited := 0
	while (level == null or level.players.get_node_or_null(^"1") == null or level.ai.get_child_count() < 3) and waited < 1800:
		await get_tree().process_frame
		level = CompoundLevel.current(self)
		waited += 1
	var player := level.players.get_node_or_null(^"1") as Soldier if level else null
	check(player != null and player._hud != null, "hosted a level with the local player's HUD")
	if player == null or player._hud == null:
		return
	# The test fills the HUD in: nothing of the player's or the HUD's own may overwrite it.
	player.set_physics_process(false)
	player.player_input.set_process(false)
	player.player_input.set_physics_process(false)
	var hud := player._hud
	hud.objective_helper.set_process(false)
	hud._subtitles.set_process(false)
	hud.update_status(player)
	var squad := hud._status_lines.size()
	hud._status_lines = PackedStringArray(["Carrying Ammunition crate, 7.62x51 mm, linked (Alt+G to drop)", "Spawn protection 9 s - firing ends it"]) \
		+ hud._status_lines
	hud.command_menu.open()
	var panel := hud.zone_top_right.get_child(0) as ObjectivesPanel
	panel.visible = true
	panel._label.text = "OBJECTIVES - Kessler Farm compound\n[ ] Destroy the weapons cache in the farmhouse cellar\n[ ] Recover the field laptop" \
		+ "\n[x] Clear the checkpoint on the north road\n[-] Capture the courier alive\nCivilian casualties: 2 of 8"
	hud.objective_helper._hint.text = "Head to the farmhouse cellar (NW, 1.2 km); the cache is under the stairs"
	hud.objective_helper._hint.visible = true
	hud._subtitles.feed = PackedStringArray(["Golf: Contact front, two hundred metres, by the tree line", "Hotel: Moving to cover by the low wall",
		"Echo: I'm hit, I'm hit, need a medic over here", "India: Reloading, cover me"])
	hud._prompt.text = "[Ctrl] Ammunition crate, 7.62x51 mm, linked, 200 rounds    [F] Inspect"
	var hot := HotZoneDebug.new()
	add_child(hot)
	hot.set_process(false)
	hot._label.text = "HOT ZONE (debug; PgUp hide, PgDn +5 min)\nZone: ALERTED  (comms down)\nAreas: farm ALERTED, north road SUSPICIOUS" \
		+ "\nLast known: (120, -340) +/- 45 m\nReports: 3 heard, 1 on the way\nPressure: 4.5 (tier 2)  last: gunfire +1.5" \
		+ "\nPatrols out: 2 (1 looking)  checkpoints closed\nQRF launches: 1  (QRF turning out: 40 s)  hunter teams: 1  HQ pairs: 0  coordination 0.6" \
		+ "\nEnemy radio: listening"
	hot._label.visible = true
	var vehicle: Array = [{"text": "Humvee, Gunner"}, {"text": "Fuel 40 L"}, {"text": "Engine 55%"}, {"text": "Wheels 80%"}, {"text": "Hull 20%", "style": &"warn"},
		{"text": "M2 Browning: 200 rounds"}, {"text": "ON FIRE: GET OUT", "style": &"warn"}, {"text": "V: 3rd person", "style": &"key"},
		{"text": "F: get out", "style": &"key"}]
	check(squad >= 4, "the squad list shows the squad (%d lines)" % squad)
	var root := get_tree().root
	var keep := [root.content_scale_mode, root.content_scale_aspect, root.content_scale_size, root.content_scale_factor]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.content_scale_factor = 1.0
	for ui_scale: float in UI_SCALES:
		var bad := PackedStringArray()
		for res in SIZES:
			var view := (Vector2(res) / GameSettings.ui_scale_for(res, ui_scale)).floor()  # the auto scale, as _fit
			root.content_scale_size = Vector2i(view)
			for downed in [false, true]:
				hud._downed.text = "UNCONSCIOUS" if downed else ""
				hud._downed_detail.text = ("Your team can treat you; you'll come round when your body recovers\n\nHold [Y] to give up and respawn" if downed else "")
				hud._downed.visible = downed
				hud._downed_detail.visible = downed
				hud._prompt.visible = not downed
				hud._crosshair.visible = not downed
				hud.flash("Contract signed: Kessler Farm. Civilian casualties void the contract at 8")
				hud.show_vehicle(vehicle)
				await _frames(3)
				hot.place()  # twice: as in the game, where it places itself twice a second
				await _frames(1)
				hot.place()
				await _frames(1)
				var window := Rect2(Vector2.ZERO, view).grow(1.0)
				var why := PackedStringArray()
				if not root.get_visible_rect().size.is_equal_approx(view):
					why.append("window laid out as %s" % root.get_visible_rect().size)
				why.append_array(_off_screen(hud, window))
				why.append_array(_off_screen(hot, window))
				var zones := {"squad list": hud._status, "command menu": hud.command_menu, "objectives": hud.zone_top_right, "hot zone": hot._label,
					"weapon": hud.ammo_readout, "radio and vehicle": hud.zone_bottom_centre, "message": hud._message}
				if downed:
					zones["downed"] = hud._downed_box
				else:
					zones["prompt"] = hud._prompt
					zones["crosshair"] = hud._crosshair
				# What isn't showing takes no room (a squad list with no room left under an open
				# command menu at 1280x720 and UI scale 1.5 hides); the weapon's corner is kept.
				var names := zones.keys().filter(func(n: String) -> bool: return n == "weapon" or (zones[n] as Control).is_visible_in_tree())
				for i in names.size():
					var a := (zones[names[i]] as Control).get_global_rect()
					if not window.encloses(a):
						why.append("%s %s off the window" % [names[i], a])
					for j in range(i + 1, names.size()):
						var b := (zones[names[j]] as Control).get_global_rect()
						if a.intersects(b):
							why.append("%s %s over %s %s" % [names[i], a, names[j], b])
				if not why.is_empty():
					print("    %dx%d @%.1f: radio %d lines (room %.0f), vehicle '%s' %s" % [res.x, res.y, ui_scale, hud._subtitles.get_line_count(),
						hud._subtitles.room, hud.vehicle_text(), hud._vehicle.get_combined_minimum_size()])
					bad.append("%dx%d%s: %s" % [res.x, res.y, " downed" if downed else "", ", ".join(why.slice(0, 3)) + (" (+%d more)" % (why.size() - 3) if why.size() > 3 else "")])
		var key := "hud @%.1f" % ui_scale
		_report[key] = bad
		if key in KNOWN:
			print("  [known] %s: %s" % [key, "fits everywhere" if bad.is_empty() else "; ".join(bad)])
			check(not bad.is_empty(), "%s is listed as KNOWN but now fits at every size: take it off KNOWN" % key)
		else:
			check(bad.is_empty(), "%s: every zone fits, none overlaps, at %d window sizes%s" % [key, SIZES.size(), "" if bad.is_empty() else ": " + "; ".join(bad)])
	root.content_scale_size = Vector2i(1920, 1080)
	hud.command_menu.close()
	hud.show_vehicle(vehicle)
	await _frames(3)
	check(hud._subtitles.visible and hud._subtitles.text.count("\n") == 3 and hud.vehicle_text().ends_with("F: get out"),
		"and all four radio lines and every vehicle part ('%s'; radio %d lines, room %.0f, shown %s, window %s)" % [hud.vehicle_text(), hud._subtitles.text.count("\n") + 1, hud._subtitles.room, hud._subtitles.visible, root.get_visible_rect().size])
	check(not hud._status.text.contains(" more") and hud._status.text.count("\n") + 1 == hud._status_lines.size(),
		"at 1920x1080 with the command menu shut the whole squad list shows (%d lines)" % hud._status_lines.size())
	# Review of ui/hud-pass, 2026-10-14: the squad list drew over the open inventory (it sits in
	# the left zone, added after the inventory screen) and vanished, unsaid, under an open command
	# menu on a short window - taking the F-key ">" marks with it while units were being picked.
	var cut := Hud.status_cut(PackedStringArray(["Carrying crate (Alt+G to drop)", "SQUAD  [F-keys] select  [~] all", "  F1 You", "  F2 Golf: idle",
		">  F3 Hotel: moving", "  F4 India: idle"]), 3)
	check(cut == PackedStringArray(["Carrying crate (Alt+G to drop)", ">  F3 Hotel: moving", "+4 more"]),
		"a short squad list keeps the selected members first, then what you carry, and says what it cut (%s)" % ", ".join(cut))
	check(Hud.status_cut(PackedStringArray(["a", "b"]), 1) == PackedStringArray(["+2 more"]) and Hud.status_cut(PackedStringArray(["a", "b"]), 0).is_empty()
		and Hud.status_cut(PackedStringArray(["a", "b"]), 2) == PackedStringArray(["a", "b"]), "one line left says '+n more'; none left, nothing")
	hud.inventory_screen.visible = true
	await _frames(2)
	check(not hud._status.visible, "the squad list hides under the open inventory, as the weapon readout does")
	hud.inventory_screen.visible = false
	var picked := PackedStringArray()
	for s in hud.command_menu.roster():
		if s.is_ai():
			picked.append(String(s.name))
	for res: Vector2i in [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(3840, 2160)]:
		for ui_scale: float in [1.5, 2.0]:
			root.content_scale_size = Vector2i((Vector2(res) / GameSettings.ui_scale_for(res, ui_scale)).floor())
			hud.command_menu.open()
			hud.command_menu.selected = picked.slice(0, 2)
			hud.update_status(player)
			hud._status_lines = PackedStringArray(["Carrying Ammunition crate, 7.62x51 mm, linked (Alt+G to drop)", "Spawn protection 9 s - firing ends it"]) \
				+ hud._status_lines
			await _frames(3)
			var shown := hud._status.text if hud._status.visible else ""
			var marks := shown.count("\n>") + int(shown.begins_with(">"))
			var whole := hud._status_lines.size() == shown.count("\n") + 1
			var said := shown.contains(" more") or hud.command_menu._title.text.contains("squad lines below")
			check(whole or (said and (marks == 2 or shown == "" or shown.count("\n") < 2)),
				"%dx%d @%.1f, command menu open: the squad list shows the picked units' marks or says what it cut ('%s'; title '%s')"
				% [res.x, res.y, ui_scale, shown.replace("\n", " | "), hud.command_menu._title.text])
	hud.command_menu.close()
	root.content_scale_size = Vector2i(1920, 1080)
	await _frames(2)
	check(hud.vehicle_text().contains("ON FIRE: GET OUT") and hud._vehicle.get_child_count() == vehicle.size(), "the vehicle readout is in parts, one label each")
	check(hud._subtitles.theme_type_variation == &"HudLabel" and hud._status.theme_type_variation == &"HudLabel" and hud._downed.theme_type_variation == &"HudAlertLabel"
		and UiKit.THEME.get_constant(&"outline_size", &"HudLabel") > 0 and UiKit.THEME.get_font_size(&"font_size", &"HudSmallLabel") >= UiKit.FONT_SMALL,
		"the HUD lines share the theme's outlined style, nothing under 14 px")
	root.content_scale_mode = keep[0]
	root.content_scale_aspect = keep[1]
	root.content_scale_size = keep[2]
	root.content_scale_factor = keep[3]
	hot.queue_free()  # the level stays up until the test quits, as in map_test
	await _frames(2)


## Wraps a HUD Control in a CanvasLayer with a full-window frame, as the Hud holds it.
func _in_layer(control: Control) -> CanvasLayer:
	var layer := CanvasLayer.new()
	var frame := Control.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(frame)
	frame.add_child(control)
	return layer


## Opens `make`'s screen at every size and UI scale and records what runs off the window.
## Every level of a command menu tree as the stack that opens it, the root first.
func _menu_levels(level: Dictionary, stack: Array) -> Array:
	var out: Array = [stack]
	for item: Dictionary in level["items"]:
		if item.has("items") and not (item["items"] as Array).is_empty():
			out.append_array(_menu_levels(item, stack + [item]))
	return out


func _fit(screen: String, make: Callable) -> void:
	print(screen)
	_vp.size = SIZES[0]
	var node: Node = make.call()
	_vp.add_child(node)
	await _frames(3)
	for ui_scale: float in UI_SCALES:
		var bad := PackedStringArray()
		for res in SIZES:
			_vp.size = Vector2i((Vector2(res) / GameSettings.ui_scale_for(res, ui_scale)).floor())
			await _frames(2)
			var off := _off_screen(node, Rect2(Vector2.ZERO, Vector2(_vp.size)).grow(1.0))
			if not off.is_empty():
				bad.append("%dx%d: %s" % [res.x, res.y, ", ".join(off.slice(0, 3)) + (" (+%d more)" % (off.size() - 3) if off.size() > 3 else "")])
		var key := "%s @%.1f" % [screen, ui_scale]
		_report[key] = bad
		if key in KNOWN:
			print("  [known] %s: %s" % [key, "fits everywhere" if bad.is_empty() else "; ".join(bad)])
			check(not bad.is_empty(), "%s is listed as KNOWN but now fits at every size: take it off KNOWN" % key)
		else:
			check(bad.is_empty(), "%s fits at %d window sizes%s" % [key, SIZES.size(), "" if bad.is_empty() else ": " + "; ".join(bad)])
	node.queue_free()
	await _frames(2)


## Like _fit, for a menu drawn by hand (no Controls to walk): `rects` gives the boxes it draws
## text and buttons in, by name, for the menu under `node` at the viewport's current size.
func _fit_drawn(screen: String, make: Callable, rects: Callable) -> void:
	print(screen)
	_vp.size = SIZES[0]
	var node: Node = make.call()
	_vp.add_child(node)
	await _frames(3)
	var menu: Control = node.get_child(0).get_child(0)
	for ui_scale: float in UI_SCALES:
		var bad := PackedStringArray()
		for res in SIZES:
			_vp.size = Vector2i((Vector2(res) / ui_scale).floor())
			await _frames(2)
			var window := Rect2(Vector2.ZERO, Vector2(_vp.size)).grow(1.0)
			var off := PackedStringArray()
			var boxes: Dictionary = rects.call(menu)
			for name: String in boxes:
				var r: Rect2 = boxes[name]
				if r.size.x <= 0.0 or r.size.y <= 0.0 or not window.encloses(r):
					off.append("%s %s" % [name, r])
			if not off.is_empty():
				bad.append("%dx%d: %s" % [res.x, res.y, ", ".join(off.slice(0, 3)) + (" (+%d more)" % (off.size() - 3) if off.size() > 3 else "")])
		var key := "%s @%.1f" % [screen, ui_scale]
		_report[key] = bad
		if key in KNOWN:
			print("  [known] %s: %s" % [key, "fits everywhere" if bad.is_empty() else "; ".join(bad)])
			check(not bad.is_empty(), "%s is listed as KNOWN but now fits at every size: take it off KNOWN" % key)
		else:
			check(bad.is_empty(), "%s fits at %d window sizes%s" % [key, SIZES.size(), "" if bad.is_empty() else ": " + "; ".join(bad)])
	node.queue_free()
	await _frames(2)


## The medical menu's boxes (MedicalMenu.layout_rects): each inside the panel too.
func _medical_rects(menu: MedicalMenu) -> Dictionary:
	var out := menu.layout_rects()
	var panel: Rect2 = out.panel
	for name: String in out.keys():
		if name != "panel" and not panel.grow(0.5).encloses(out[name]):
			out[name + " (outside the panel)"] = Rect2(-1, -1, 0, 0)
	return out


## A ring of RING_MAX entries, one with a full body's Loot list (MAX_LOOT_ENTRIES) and one with
## a short submenu, opened on a point in the middle, at each corner and edge, and where the
## self menu puts each body region (InteractionMenu.SELF_LAYOUT): every ring entry, submenu
## entry and "more" row.
func _interaction_rects(menu: InteractionMenu) -> Dictionary:
	var out := {}
	var size := menu.get_viewport_rect().size
	var spots: Array[Vector2] = [size * 0.5, Vector2(4, 4), Vector2(size.x - 4, 4), Vector2(4, size.y - 4), size - Vector2(4, 4),
		Vector2(size.x * 0.5, 4), Vector2(size.x * 0.5, size.y - 4), Vector2(4, size.y * 0.5), Vector2(size.x - 4, size.y * 0.5)]
	for region: StringName in InteractionMenu.SELF_LAYOUT:
		spots.append(size * 0.5 + InteractionMenu.SELF_LAYOUT[region])
	var actions := _ring_actions()
	for spot in spots:
		menu.open_object()
		var points: Array[Dictionary] = [{"target": menu, "screen": spot, "actions": actions}]
		menu.set_points(points)
		menu.set_cursor(spot)
		var ring := menu.entry_rects()
		if ring.size() != actions.size():
			out["ring at %s didn't open" % spot] = Rect2(-1, -1, 0, 0)
			continue
		for i in ring.size():
			out["ring %d at %s" % [i, spot]] = ring[i]
			if actions[i].has("items"):
				menu.close()  # fresh, so another submenu still open can't sit over this entry
				menu.open_object()
				menu.set_points(points)
				menu.set_cursor(spot)
				menu.set_cursor(ring[i].get_center())
				var sub := menu.submenu_rects(i) + menu.submenu_arrows(i)
				if sub.is_empty():
					out["submenu %d at %s didn't open" % [i, spot]] = Rect2(-1, -1, 0, 0)
				for j in sub.size():
					out["submenu %d.%d at %s" % [i, j, spot]] = sub[j]
	menu.close()
	return out


func _ring_actions() -> Array[Dictionary]:
	var loot := []
	for j in InteractionMenu.MAX_LOOT_ENTRIES:
		loot.append({"id": &"loot_item", "label": "Loot entry %d with a long name" % j, "disabled": ""})
	var actions: Array[Dictionary] = [{"id": &"loot", "label": "Loot", "disabled": "", "items": loot}]
	for i in InteractionMenu.RING_MAX - 2:
		actions.append({"id": StringName("entry_%d" % i), "label": "Entry %d" % i, "disabled": ""})
	actions.append({"id": &"group", "label": "More", "disabled": "", "items": [{"id": &"a", "label": "A", "disabled": ""}, {"id": &"b", "label": "B", "disabled": ""}]})
	return actions


## In the shortest window (1280 x 720 at UI scale 1.5) a full Loot list doesn't fit: it shows
## what does with a "more" row each way, scrolls to its last entry, and the cursor on an entry
## highlights that entry (P0-3: it used to run off the window, its last rows out of reach).
func _test_long_submenu() -> void:
	print("A long Loot list in a short window")
	_vp.size = Vector2i((Vector2(SIZES[0]) / UI_SCALES[-1]).floor())
	var layer := _in_layer(InteractionMenu.new())
	_vp.add_child(layer)
	await _frames(2)
	var menu: InteractionMenu = layer.get_child(0).get_child(0)
	var actions := _ring_actions()
	var loot: Array = actions[0].items
	var spot := Vector2(_vp.size) * 0.5
	menu.open_object()
	var points: Array[Dictionary] = [{"target": menu, "screen": spot, "actions": actions}]
	menu.set_points(points)
	menu.set_cursor(spot)
	menu.set_cursor(menu.entry_rects()[0].get_center())
	var shown := menu.submenu_rects(0).size()
	check(shown < loot.size() and menu.submenu_arrows(0).size() == 2,
		"%d loot entries in a %d px window: %d shown, with a more row each way" % [loot.size(), _vp.size.y, shown])
	## Object mode refreshes the points every frame (PlayerInput._update_interaction): the scroll
	## has to survive that, or the list never leaves its first page (review of P0-3).
	var steps := 0
	while menu.scroll_submenu(1) and steps < loot.size():
		steps += 1
		menu.set_points(points)
	check(steps > 0 and menu.sub_scroll == steps, "the scroll keeps across a per-frame set_points (%d rows)" % menu.sub_scroll)
	var rects := menu.submenu_rects(0)
	menu.set_cursor(rects[-1].get_center())
	check(menu.sub_scroll + rects.size() == loot.size() and menu.highlighted() == loot[-1],
		"scrolled %d rows: the last entry is shown and highlighted (%s)" % [steps, menu.highlighted().get("label")])
	menu.set_cursor(menu.submenu_arrows(0)[0].get_center())
	var before := menu.sub_scroll
	menu._process(InteractionMenu.SUB_SCROLL_STEP_S + 0.01)
	check(menu.sub_scroll == before - 1 and menu.highlighted().is_empty(), "resting on the more-above row scrolls back up, and picks nothing")
	## A shorter list (an item taken) clamps the scroll: no short page, no negative "more" count.
	while menu.scroll_submenu(1):
		pass
	var shorter := actions.duplicate(true)
	(shorter[0].items as Array).resize(loot.size() - 3)
	var fewer: Array[Dictionary] = [{"target": menu, "screen": spot, "actions": shorter}]
	menu.set_points(fewer)
	var left: int = shorter[0].items.size()
	var sub_rects := menu.submenu_rects(0)
	check(menu.sub_scroll + sub_rects.size() == left and left - menu.sub_scroll - sub_rects.size() >= 0,
		"3 loot entries taken at the bottom: the scroll clamps to %d, the page still full" % menu.sub_scroll)
	(shorter[0].items as Array).resize(2)
	menu.set_points(fewer)
	check(menu.sub_scroll == 0 and menu.submenu_rects(0).size() == 2 and menu.submenu_arrows(0).is_empty(),
		"the list cut to 2 entries: back to the top, both shown, no more rows")
	menu.set_points(points)
	check(MedicalMenu.LOG_FONT >= UiKit.FONT_SMALL and InteractionMenu.ENTRY_FONT >= UiKit.FONT_SMALL and InteractionMenu.POINT_FONT >= UiKit.FONT_SMALL
		and InteractionMenu.HINT_FONT >= UiKit.FONT_SMALL, "the drawn menus' text is 14 px or more")
	menu.close()
	layer.queue_free()
	await _frames(2)


## The visible controls under `node` that matter and aren't wholly inside `window`. A scroll
## area counts as one (what's inside it can scroll), as does a clipping control.
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
				out.append("%s '%s' %s" % [c.get_class(), _name(c), c.get_global_rect()])
				continue
			if c is ScrollContainer or c.clip_contents:
				continue
		out.append_array(_off_screen(child, window))
	return out


func _name(c: Control) -> String:
	if c is Label:
		return (c as Label).text.left(32)
	if c is Button:
		return (c as Button).text.left(32)
	return String(c.name)


## A table of every screen and scale: which window sizes overflow (docs/ui_audit.md's table).
func _summary() -> void:
	print("Fit summary (screen @ UI scale: window sizes that overflow)")
	for key: String in _report:
		var bad: PackedStringArray = _report[key]
		var sizes := PackedStringArray(Array(bad).map(func(b: String) -> String: return b.get_slice(":", 0)))
		print("  FIT %s: %s" % [key, "fits" if bad.is_empty() else ", ".join(sizes)])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
