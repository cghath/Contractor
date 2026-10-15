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
	# The drawn menus (P0-2, P0-3): what they draw, by name, laid out at each size.
	await _fit_drawn("medical menu", func() -> Node: return _in_layer(MedicalMenu.new()), _medical_rects)
	await _fit_drawn("interaction menu", func() -> Node: return _in_layer(InteractionMenu.new()), _interaction_rects)
	await _test_long_submenu()
	_summary()
	GameSettings.reset_all()
	GameSettings.use_file("")
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
	var steps := 0
	while menu.scroll_submenu(1) and steps < loot.size():
		steps += 1
	var rects := menu.submenu_rects(0)
	menu.set_cursor(rects[-1].get_center())
	check(menu.sub_scroll + rects.size() == loot.size() and menu.highlighted() == loot[-1],
		"scrolled %d rows: the last entry is shown and highlighted (%s)" % [steps, menu.highlighted().get("label")])
	menu.set_cursor(menu.submenu_arrows(0)[0].get_center())
	var before := menu.sub_scroll
	menu._process(InteractionMenu.SUB_SCROLL_STEP_S + 0.01)
	check(menu.sub_scroll == before - 1 and menu.highlighted().is_empty(), "resting on the more-above row scrolls back up, and picks nothing")
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
