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
## The Menu and HUD size setting at its default, the Captain's 1.2, and its maximum.
const UI_SCALES: Array[float] = [1.0, 1.2, 1.5]
## "<screen> @<scale>" entries known to overflow, each waiting for its follow-up branch
## (docs/ui_audit.md, "Follow-up branches"). Take an entry off when its branch fixes it.
const KNOWN: Array[String] = [
	"contract board @1.5", "shop @1.5",  # ui/campaign-screens
	"base: squad @1.2", "base: squad @1.5", "base: roster @1.2", "base: roster @1.5", "base: hiring @1.2", "base: hiring @1.5",
	"base: medbay @1.2", "base: medbay @1.5", "base: shop @1.2", "base: shop @1.5", "base: armory @1.2", "base: armory @1.5",  # ui/base-hub
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
			var view := (Vector2(res) / ui_scale).floor()
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
		"and all four radio lines and every vehicle part ('%s')" % hud.vehicle_text())
	check(not hud._status.text.contains(" more") and hud._status.text.count("\n") + 1 == hud._status_lines.size(),
		"at 1920x1080 with the command menu shut the whole squad list shows (%d lines)" % hud._status_lines.size())
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
func _fit(screen: String, make: Callable) -> void:
	print(screen)
	_vp.size = SIZES[0]
	var node: Node = make.call()
	_vp.add_child(node)
	await _frames(3)
	for ui_scale: float in UI_SCALES:
		var bad := PackedStringArray()
		for res in SIZES:
			_vp.size = Vector2i((Vector2(res) / ui_scale).floor())
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
