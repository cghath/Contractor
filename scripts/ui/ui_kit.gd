class_name UiKit
extends RefCounted
## The shared UI look (Captain, 2026-10-14, playtesting v0.3.1: "all of the UIs need a pass"):
## one Theme (themes/contractor_ui.tres: dark translucent olive panels, light text, an amber
## accent) and small builders so every screen gets the same panels, headings, rows, buttons,
## lists, key hints and bars instead of each one setting its own sizes and colours. See
## docs/ui_audit.md for the usage guide.
##
## Sizes are logical pixels: the Menu and HUD size setting (GameSettings "ui_scale", the root's
## content_scale_factor) scales everything, so a screen sized to its viewport's visible rect
## (fit_width/fit_height, screen()) fits at every window size and UI scale.

const THEME: Theme = preload("res://themes/contractor_ui.tres")

## The palette, for the few places a colour is set by hand (drawn things, rich text, bars).
## Kept in step with the theme (ui-modern, 2026-10-20: one palette, brighter dim text for
## contrast over the 3D view).
const TEXT := Color(0.92, 0.93, 0.89)
const TEXT_BRIGHT := Color(0.97, 0.97, 0.94)
const TEXT_DIM := Color(0.7, 0.73, 0.67)
const TEXT_OFF := Color(0.5, 0.52, 0.48)
const ACCENT := Color(0.93, 0.69, 0.27)
const ACCENT_HOT := Color(1.0, 0.8, 0.42)
const GOOD := Color(0.5, 0.8, 0.45)
const WARN := Color(0.95, 0.47, 0.38)
## Worse than WARN: a broken plate, an arterial bleed.
const BAD := Color(0.88, 0.25, 0.2)
const PANEL_BG := Color(0.065, 0.075, 0.065, 0.93)
const DIM_BG := Color(0, 0, 0, 0.55)
## A panel's hairline edge, and a hovered or keyboard-picked row (the accent, faint).
const BORDER := Color(0.3, 0.33, 0.27)
const HOVER_BG := Color(0.93, 0.69, 0.27, 0.2)
## The outline under HUD text and drawn readouts (readable over bright ground).
const OUTLINE := Color(0, 0, 0, 0.9)
## The ink on an amber chip (a key hint, the primary button).
const INK := Color(0.06, 0.07, 0.06)

## The fonts (Inter, SIL Open Font License: fonts/OFL.txt): the theme's default (medium), a
## semibold for headings, buttons and the HUD, and a bold for titles. Drawn UIs use these.
const FONT_REGULAR: Font = preload("res://themes/inter_body.tres")
const FONT_STRONG: Font = preload("res://themes/inter_strong.tres")
const FONT_BOLD: Font = preload("res://themes/inter_bold.tres")

## The spacing scale: between a label and its control, between rows, between sections, and the
## gap kept between a screen's panel and the window's edge.
const SPACE_XS := 4
const SPACE_S := 8
const SPACE_M := 12
const SPACE_L := 20
const EDGE := 24

## Font sizes (logical px): body 16 (the theme's default), small 14, heading 20, title 26.
## Nothing smaller than 14 (the audit found 12 and 13 px at 60% alpha, unreadable).
const FONT_SMALL := 14
const FONT_BODY := 16
const FONT_HEADING := 20
const FONT_TITLE := 26
## The HUD's text over the 3D view (docs/ui_audit.md item 4, P1-9/P1-11): one outlined style,
## readable over bright ground, in the theme's HudLabel (FONT_HUD), HudSmallLabel
## (FONT_HUD_SMALL) and HudAlertLabel (FONT_HUD_ALERT, warn-red, the downed and killed titles).
## ui_test checks the theme matches these.
const FONT_HUD := 20  # Captain, 2026-10-16: HUD "sized up a tiny bit" (was 18)
const FONT_HUD_SMALL := 16  # (was 14)
const FONT_HUD_ALERT := 28  # (was 26)


## Gives `root` (and so everything under it) the shared theme. A CanvasLayer can't hold a
## theme, so call this on its top Control.
static func apply(root: Control) -> void:
	root.theme = THEME


## A full-window darkening behind a menu (`alpha` 0 for none).
static func dim(alpha: float = DIM_BG.a) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, alpha)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	return rect


## A centred menu screen under `parent` (usually a CanvasLayer): a full-window ScrollContainer
## (so a panel taller than a small window, or a big UI scale, scrolls instead of running off it)
## with a centred panel holding a VBox of `width` (clamped to the window less EDGE on each
## side). Returns the VBox; its panel is get_parent(). The theme is applied to the scroll.
static func screen(parent: Node, width: float, solid := false) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "UiKitScreen"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	apply(scroll)
	parent.add_child(scroll)
	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(centre)
	var p := panel(solid)
	centre.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", SPACE_S)
	p.add_child(box)
	fit_width(box, width)
	return box


## A panel in the shared style (`solid`: opaque, for screens over other screens).
static func panel(solid := false) -> PanelContainer:
	var p := PanelContainer.new()
	if solid:
		p.theme_type_variation = &"SolidPanel"
	return p


## Keeps `control`'s minimum width at `width`, or the window's visible width less EDGE on each
## side when that is narrower; follows window resizes and UI scale changes.
static func fit_width(control: Control, width: float) -> void:
	_follow_window(control, func() -> void:
		var room := control.get_viewport().get_visible_rect().size.x - EDGE * 2.0 - 40.0
		control.custom_minimum_size.x = maxf(minf(width, room), 200.0))


## The same for the minimum height (`height`, or the window's visible height less EDGE top and
## bottom and `reserve` for whatever else is in the panel).
static func fit_height(control: Control, height: float, reserve := 0.0) -> void:
	_follow_window(control, func() -> void:
		var room := control.get_viewport().get_visible_rect().size.y - EDGE * 2.0 - reserve
		control.custom_minimum_size.y = maxf(minf(height, room), 120.0))


## Runs `fit` now (if `control` is in the tree) or when it enters it, and again whenever its
## viewport changes size (a window resize, or the Menu and HUD size setting).
static func _follow_window(control: Control, fit: Callable) -> void:
	var safe := func() -> void:
		if is_instance_valid(control) and control.is_inside_tree():
			fit.call()
	var hook := func() -> void:
		safe.call()
		if not control.get_viewport().size_changed.is_connected(safe):
			control.get_viewport().size_changed.connect(safe)
	var unhook := func() -> void:
		if control.get_viewport().size_changed.is_connected(safe):
			control.get_viewport().size_changed.disconnect(safe)
	if control.is_inside_tree():
		hook.call()
	control.tree_entered.connect(hook)
	control.tree_exiting.connect(unhook)


## A screen's title (26 px).
static func title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"TitleLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## A section heading (20 px, accent colour).
static func heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HeadingLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## Body text that wraps (never a run-on line off the panel).
static func text(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## A small, dim note (14 px) that wraps.
static func hint(value: String, centred := false) -> Label:
	var label := text(value)
	label.theme_type_variation = &"HintLabel"
	if centred:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## A warning line (red-orange) that wraps.
static func warn(value: String) -> Label:
	var label := text(value)
	label.theme_type_variation = &"WarnLabel"
	return label


## A table cell: one line of text (no wrapping: numbers and short words) in a label `variation`
## ("" for body text; GoodLabel for a done or claimed row, MutedLabel for one that can't be used
## now, both body size). Give the table's widest column wrapping text (text()) with
## SIZE_EXPAND_FILL so it takes the room the others leave.
static func cell(value: String, variation := &"") -> Label:
	var label := Label.new()
	label.text = value
	if variation != &"":
		label.theme_type_variation = variation
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


## Makes `label` a one-line label that cuts its text with "..." past `cap` px, keeping the
## whole text in its tooltip, instead of widening its row (a long item name or injury in a flow
## of them). Its minimum width is its whole text up to `cap`: Godot leaves a trimmed label's
## text out of its minimum size, so in a flow it would shrink to nothing (as buttons did,
## fit_button_text). Kept up to date when the theme changes.
static func fit_label_text(label: Label, cap := BUTTON_TEXT_CAP) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if label.tooltip_text == "":
		label.tooltip_text = label.text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	var refit := func() -> void:
		if not is_instance_valid(label):
			return
		var font := label.get_theme_font(&"font")
		var full := 0.0
		if font != null and label.text != "":
			full = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size(&"font_size")).x + 2.0
		var style := label.get_theme_stylebox(&"normal")
		if style != null:
			full += style.get_minimum_size().x
		label.custom_minimum_size.x = ceilf(minf(full, cap))
	label.theme_changed.connect(refit)
	refit.call()


## A table: a GridContainer of `headers.size()` columns with a header row in the hint style.
## The first column expands (put its wrapping text there); add the rows' cells in order.
static func table(headers: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = headers.size()
	grid.add_theme_constant_override(&"h_separation", SPACE_M)
	grid.add_theme_constant_override(&"v_separation", SPACE_XS)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in headers.size():
		var head := cell(String(headers[i]), &"HintLabel")
		if i == 0:
			head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(head)
	return grid


## A figure for a summary header: a small dim caption over its value.
static func stat(caption: String, value: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 0)
	box.add_child(cell(caption, &"HintLabel"))
	box.add_child(cell(value, &"StatLabel"))
	return box


## A row for a thing and what can be done with it: its text (wrapping, the whole width) over a
## wrapping row of `controls`, so a narrow panel takes it on two lines instead of running off
## (an item with five buttons and a drop-down doesn't fit beside its name at 1280x720 and 1.5).
## The row's button_row is the meta "controls", for adding more.
static func action_row(value: String, controls: Array = [], label: Label = null) -> VBoxContainer:
	var r := VBoxContainer.new()
	r.add_theme_constant_override(&"separation", SPACE_XS)
	var l := label if label else text(value)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	var buttons := button_row(controls)
	r.add_child(buttons)
	r.set_meta(&"controls", buttons)
	return r


## A HUD line in the one outlined HUD style (`variation`: HudLabel, HudSmallLabel, HudAlertLabel
## or HudWarnLabel). It carries the theme itself, as HUD labels sit straight on a CanvasLayer,
## and never takes the mouse.
static func hud_label(value := "", variation := &"HudLabel") -> Label:
	var label := Label.new()
	label.text = value
	apply(label)
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## A section: a heading over a VBox; add the section's rows to the returned VBox.
static func section(heading_text: String, parent: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", SPACE_XS + 2)
	if heading_text != "":
		box.add_child(heading(heading_text))
	parent.add_child(box)
	return box


## A label-then-control row: `label_text` in a column `label_width` wide (wrapping), then
## `control` filling the rest (if given; more can be added to the returned HBox).
static func row(label_text: String, control: Control = null, label_width := 220.0) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override(&"separation", SPACE_M)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(label_width, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(label)
	if control:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(control)
	return r


## A button that calls `pressed`. Long text is clipped with "..." (and kept whole in the
## tooltip) rather than widening the panel off the window.
static func button(label: String, pressed: Callable, tooltip := "") -> Button:
	var b := Button.new()
	b.text = label
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.tooltip_text = tooltip if tooltip != "" else label
	b.pressed.connect(pressed)
	fit_button_text(b)
	return b


## The widest a button asks to be for its text, in logical px: past it the text is cut with
## "..." (the tooltip has it whole) and the button stretches to fill its row instead.
const BUTTON_TEXT_CAP := 320.0


## Gives a Button with text_overrun_behavior / clip_text a minimum width that fits its whole
## text, up to BUTTON_TEXT_CAP. Godot leaves the text out of such a button's minimum size, so in
## a wrapping row (HFlowContainer gives each child only its minimum) it shrank to its padding
## and showed no text at all (v0.4.2 FOB screen, Captain's 2000x1250 co-op screenshot). Kept up
## to date when the theme or the text changes.
static func fit_button_text(b: Button, cap := BUTTON_TEXT_CAP) -> void:
	if b.has_meta(&"_ui_kit_fitted"):
		return
	b.set_meta(&"_ui_kit_fitted", true)
	var refit := func() -> void:
		if not is_instance_valid(b):
			return
		# A width the caller set itself (not ours) stays the floor.
		if not is_equal_approx(b.custom_minimum_size.x, float(b.get_meta(&"_ui_kit_width", -1.0))):
			b.set_meta(&"_ui_kit_floor", b.custom_minimum_size.x)
		var full := button_text_width(b, b.text) if b.text != "" else 0.0
		var want := maxf(ceilf(minf(full, cap)), float(b.get_meta(&"_ui_kit_floor", 0.0)))
		b.set_meta(&"_ui_kit_width", want)
		if not is_equal_approx(b.custom_minimum_size.x, want):
			b.custom_minimum_size.x = want
		var stretch := full > cap
		if stretch != b.has_meta(&"_ui_kit_stretch"):
			if stretch:
				b.set_meta(&"_ui_kit_stretch", true)
				b.size_flags_horizontal |= Control.SIZE_EXPAND
			else:
				b.remove_meta(&"_ui_kit_stretch")
				b.size_flags_horizontal &= ~Control.SIZE_EXPAND
	b.theme_changed.connect(refit)
	b.draw.connect(func() -> void: refit.call_deferred())  # a changed text redraws the button
	refit.call()


## How wide `b` must be to show `text` whole: the text in its font, its style's padding, and its
## icon if it has one.
static func button_text_width(b: Button, text: String) -> float:
	var font := b.get_theme_font(&"font")
	var w := 0.0
	if font != null and text != "":
		w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size(&"font_size")).x
	var style := b.get_theme_stylebox(&"normal")
	if style != null:
		w += style.get_minimum_size().x
	if b.icon != null and not b.expand_icon:
		w += b.icon.get_width() + b.get_theme_constant(&"h_separation")
	return w + 2.0


## A row of buttons that wraps onto more lines when the panel is too narrow for them (the
## contract board's seven-button row ran off a 1280 window at a big UI scale).
static func button_row(buttons: Array, align_end := false) -> HFlowContainer:
	var r := HFlowContainer.new()
	r.add_theme_constant_override(&"h_separation", SPACE_S)
	r.add_theme_constant_override(&"v_separation", SPACE_S)
	if align_end:
		r.alignment = FlowContainer.ALIGNMENT_END
	for b: Control in buttons:
		if b is Button:
			fit_button_text(b as Button)  # a plain Button (the co-op Ready) too
		r.add_child(b)
	return r


## A list (ItemList) at least `min_height` tall; items longer than it is wide show "...", with
## their full text as the tooltip (add_item does that when given one).
static func list(min_height := 160.0) -> ItemList:
	var l := ItemList.new()
	l.custom_minimum_size = Vector2(0, min_height)
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


## A vertical scroll area (no sideways scrolling) holding a VBox; returns the VBox.
static func scroll(min_height := 0.0) -> VBoxContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, min_height)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(box)
	return box


## A key hint: the key in an accent chip, then what it does ("Esc", "Close").
static func key_hint(key: String, what: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override(&"separation", SPACE_XS + 2)
	var chip := Label.new()
	chip.text = key
	chip.theme_type_variation = &"KeyLabel"
	r.add_child(chip)
	var label := Label.new()
	label.text = what
	label.theme_type_variation = &"HintLabel"
	r.add_child(label)
	return r


## A budget or progress bar: `value` of `maximum` with `caption` written on it (e.g. cash
## against a deployment's cost, a squad's load); red-orange past the maximum.
static func budget_bar(value: float, maximum: float, caption := "") -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = maxf(maximum, 0.001)
	bar.value = minf(value, bar.max_value)
	bar.show_percentage = caption == ""
	bar.custom_minimum_size = Vector2(0, 22)
	if value > maximum:
		var over := StyleBoxFlat.new()
		over.bg_color = WARN
		over.set_corner_radius_all(2)
		bar.add_theme_stylebox_override(&"fill", over)
	if caption != "":
		var label := Label.new()
		label.text = caption
		label.theme_type_variation = &"HintLabel"
		label.add_theme_color_override(&"font_color", TEXT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bar.add_child(label)
	return bar


## Focuses the first focusable Button under `root` (keyboard: Tab, arrows and Enter work from
## the moment a menu opens). Deferred, as a freshly built control can't take focus yet; and
## looked up then, not now: a screen rebuilt in the same frame (the loadout menu's first
## select) would leave the grab on a button already out of the tree.
static func focus_first(root: Node) -> void:
	var pick := func() -> void:
		if not is_instance_valid(root) or not root.is_inside_tree():
			return
		for b in root.find_children("*", "BaseButton", true, false):
			var c := b as Control
			if c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE and not (c as BaseButton).disabled:
				c.grab_focus()
				return
	pick.call_deferred()


# --- ui-modern (Captain, 2026-10-20: "the ui should have a nice modern feel with common sense
# layout tools etc. all menus should have better explanations") ------------------------------

## A screen's one-line "what this is for" under its title (dim, wraps).
static func subtitle(value: String, centred := true) -> Label:
	var label := text(value)
	label.theme_type_variation = &"SubtitleLabel"
	if centred:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## A screen's header: its title with a "?" button on the right, the one-line subtitle under it,
## and a help panel (hidden until "?" is pressed) with `help` (how it works, a line each) and
## `keys` ([key, what] pairs). Add it where the title went; the help pushes the rest down, so a
## screen in a scroll area still fits. The help panel is the meta "help", the button "help_button".
static func header(title_text: String, subtitle_text: String, help: PackedStringArray = PackedStringArray(),
		keys: Array = [], centred := true) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Header"
	box.add_theme_constant_override(&"separation", SPACE_XS)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", SPACE_S)
	box.add_child(top)
	var t := title(title_text)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not centred:
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	top.add_child(t)
	if subtitle_text != "":
		box.add_child(subtitle(subtitle_text, centred))
	if help.is_empty() and keys.is_empty():
		return box
	var panel := help_panel(help, keys)
	panel.visible = false
	var q := help_button(panel)
	q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(q)
	if centred:  # the title stays centred: a gap as wide as the button on its left
		var pad := Control.new()
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(pad)
		top.move_child(pad, 0)
		var match_width := func() -> void:
			if is_instance_valid(pad) and is_instance_valid(q):
				pad.custom_minimum_size.x = q.get_combined_minimum_size().x
		q.minimum_size_changed.connect(match_width)
		q.theme_changed.connect(match_width)
		match_width.call()
	box.add_child(panel)
	box.set_meta(&"help", panel)
	box.set_meta(&"help_button", q)
	return box


## The "?" button that shows and hides `panel` (a help_panel).
static func help_button(panel: Control) -> Button:
	var q := Button.new()
	q.name = "Help"
	q.text = "?"
	q.theme_type_variation = &"HelpButton"
	q.toggle_mode = true
	q.tooltip_text = "How this screen works, and its keys"
	q.toggled.connect(func(on: bool) -> void:
		if is_instance_valid(panel):
			panel.visible = on)
	return q


## A help box: "How it works" over `lines` (one wrapping line each) and the `keys` hints.
static func help_panel(lines: PackedStringArray, keys: Array = []) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "HelpPanel"
	panel.theme_type_variation = &"HelpPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", SPACE_XS + 2)
	panel.add_child(box)
	var head := Label.new()
	head.text = "How it works"
	head.theme_type_variation = &"HelpTitleLabel"
	box.add_child(head)
	for line in lines:
		var l := text(line)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(l)
	if not keys.is_empty():
		box.add_child(key_hints(keys))
	return panel


## A row of key hints that wraps ([[key, what], ...]): a screen's footer.
static func key_hints(keys: Array) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", SPACE_L)
	flow.add_theme_constant_override(&"v_separation", SPACE_XS)
	for pair: Array in keys:
		flow.add_child(key_hint(String(pair[0]), String(pair[1])))
	return flow


## The main action on a screen (amber).
static func accent_button(label: String, pressed: Callable, tooltip := "") -> Button:
	var b := button(label, pressed, tooltip)
	b.theme_type_variation = &"AccentButton"
	return b


## An action that can't be undone (sell, discard): a red edge.
static func danger_button(label: String, pressed: Callable, tooltip := "") -> Button:
	var b := button(label, pressed, tooltip)
	b.theme_type_variation = &"DangerButton"
	return b


## A search box: calls `changed` with the lowered, trimmed text as it is typed. Esc in it
## clears it first where the screen lets the key reach it (most close on Esc before that).
static func search_field(placeholder := "Search...", changed: Callable = Callable()) -> LineEdit:
	var field := LineEdit.new()
	field.name = "Search"
	field.placeholder_text = placeholder
	field.clear_button_enabled = true
	field.tooltip_text = "Type part of a name to show only the matches (the x at its end clears it)"
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size.x = 140.0
	if changed.is_valid():
		field.text_changed.connect(func(t: String) -> void: changed.call(t.strip_edges().to_lower()))
	field.gui_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed(&"pause") and field.text != "":
			field.clear()
			field.text_changed.emit("")
			field.accept_event())
	return field


## A drop-down of `options` ([value, label]) that calls `picked` with the value; `tip` says
## what it does; `now` is the value shown first.
static func picker(options: Array, picked: Callable, tip := "", now: Variant = null) -> OptionButton:
	var p := OptionButton.new()
	p.tooltip_text = tip
	for o: Array in options:
		p.add_item(String(o[1]))
		p.set_item_metadata(p.item_count - 1, o[0])
		if now != null and str(o[0]) == str(now):
			p.select(p.item_count - 1)
	p.item_selected.connect(func(i: int) -> void: picked.call(p.get_item_metadata(i)))
	return p


## Whether `item_name` passes a search `query` (lowered; "" passes everything): every word of
## the query is somewhere in the name.
static func matches(item_name: String, query: String) -> bool:
	if query == "":
		return true
	var low := item_name.to_lower()
	for word in query.split(" ", false):
		if not low.contains(word):
			return false
	return true


## Asks before something that can't be undone: a modal box over `parent` (a Control filling
## its window, or a CanvasLayer) with `question`, Cancel and `ok_label` (red when `danger`).
## Enter confirms, Esc cancels. Returns the box (it frees itself when answered).
static func confirm(parent: Node, question: String, ok_label: String, on_ok: Callable, danger := true) -> Control:
	var overlay := ConfirmBox.new()
	overlay.name = "Confirm"
	overlay.on_ok = on_ok
	apply(overlay)
	parent.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim(0.5))
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(centre)
	var p := panel(true)
	centre.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", SPACE_M)
	p.add_child(box)
	fit_width(box, 420.0)
	box.add_child(heading("Are you sure?"))
	box.add_child(text(question))
	var cancel := button("Cancel", overlay.answer.bind(false), "Keep it (Esc)")
	cancel.name = "Cancel"
	var ok := danger_button(ok_label, overlay.answer.bind(true), "%s (Enter)" % ok_label) if danger \
		else accent_button(ok_label, overlay.answer.bind(true), "%s (Enter)" % ok_label)
	ok.name = "Ok"
	box.add_child(button_row([cancel, ok], true))
	box.add_child(key_hints([["Enter", ok_label], ["Esc", "Cancel"]]))
	ok.grab_focus.call_deferred()
	return overlay


## The confirmation box (confirm()): takes every key while it's up.
class ConfirmBox extends Control:
	var on_ok: Callable

	func answer(yes: bool) -> void:
		if is_queued_for_deletion():
			return
		queue_free()
		if yes and on_ok.is_valid():
			on_ok.call()

	func _input(event: InputEvent) -> void:
		if not is_visible_in_tree() or is_queued_for_deletion():
			return
		if event.is_action_pressed(&"pause"):
			get_viewport().set_input_as_handled()
			answer(false)
		elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER]:
			var focus := get_viewport().gui_get_focus_owner()
			get_viewport().set_input_as_handled()
			answer(not (focus != null and focus.name == &"Cancel"))
