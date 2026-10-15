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
const TEXT := Color(0.9, 0.91, 0.87)
const TEXT_DIM := Color(0.64, 0.67, 0.61)
const ACCENT := Color(0.91, 0.67, 0.25)
const GOOD := Color(0.47, 0.76, 0.42)
const WARN := Color(0.93, 0.45, 0.36)
const PANEL_BG := Color(0.07, 0.08, 0.07, 0.9)
const DIM_BG := Color(0, 0, 0, 0.55)

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
	return b


## A row of buttons that wraps onto more lines when the panel is too narrow for them (the
## contract board's seven-button row ran off a 1280 window at a big UI scale).
static func button_row(buttons: Array, align_end := false) -> HFlowContainer:
	var r := HFlowContainer.new()
	r.add_theme_constant_override(&"h_separation", SPACE_S)
	r.add_theme_constant_override(&"v_separation", SPACE_S)
	if align_end:
		r.alignment = FlowContainer.ALIGNMENT_END
	for b: Control in buttons:
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
	chip.text = " %s " % key
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
## the moment a menu opens). Deferred, as a freshly built control can't take focus yet.
static func focus_first(root: Node) -> void:
	for b in root.find_children("*", "BaseButton", true, false):
		var c := b as Control
		if c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE and not (c as BaseButton).disabled:
			c.call_deferred(&"grab_focus")
			return
