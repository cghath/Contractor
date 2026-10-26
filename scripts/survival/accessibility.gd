class_name Accessibility
extends RefCounted
## Accessibility and readability (call 142; docs/survival_polish.md). The settings live in
## GameSettings' "access" section (the options screen's Accessibility tab):
## - "colour_safe": a colour-blind-safe palette (Okabe-Ito blue and orange) for the stealth ring
##   and eye (Hud.StealthTells) and the load tiers, AND shapes, so colour never carries a tell
##   alone: the noise ring dashed (more dashes the further it carried), the eye boxed in brackets,
##   each load tier its own mark (a circle, a triangle, a square, a cross).
## - "text_scale" (0.8 to 1.5): every font size in the shared theme (UiKit.THEME: the menus built
##   on UiKit and the HUD's HudLabel layers) times this, on top of the Menu and HUD size.
## - "subtitles": the bottom line of barks and voice lines with the speaker's name (Callouts'
##   Subtitles), on by default.
## The tension audio's toggle is FallenAudio's own "tension_on" (its settings file), shown on the
## same tab; music moments stay.

const SECTION := "access"
const TEXT_SCALE_RANGE := [0.8, 1.5, 0.05]

## The usual palette, as before this call.
const RING := Color(1.0, 0.9, 0.6)
const EYE := Color(1.0, 0.45, 0.35)
const LOAD := [Color(0.55, 0.8, 0.45), Color(0.95, 0.85, 0.35), Color(0.95, 0.55, 0.2), Color(0.9, 0.25, 0.2)]
## The colour-blind-safe palette (Okabe-Ito): sky blue and orange, blues to vermillion for load.
const RING_SAFE := Color(0.34, 0.71, 0.91)
const EYE_SAFE := Color(0.9, 0.62, 0.0)
const LOAD_SAFE := [Color(0.0, 0.45, 0.7), Color(0.34, 0.71, 0.91), Color(0.9, 0.62, 0.0), Color(0.84, 0.37, 0.0)]
## Each load tier's mark (MovementRules.Tier order) and its word.
const LOAD_SHAPES := ["●", "▲", "■", "✖"]
const LOAD_WORDS := ["light", "burdened", "overloaded", "critical"]
## The noise ring's dashes in the safe mode: from this many (a whisper) to this many (a shout).
const RING_DASHES := Vector2i(4, 12)

static var _base_sizes := {}  # "type|name" -> the theme's own font size
static var _applied_scale := 1.0


static func colour_safe() -> bool:
	return bool(GameSettings.get_value(SECTION, "colour_safe"))


static func text_scale() -> float:
	return clampf(float(GameSettings.get_value(SECTION, "text_scale")), float(TEXT_SCALE_RANGE[0]), float(TEXT_SCALE_RANGE[1]))


static func subtitles() -> bool:
	return bool(GameSettings.get_value(SECTION, "subtitles"))


static func tension_audio() -> bool:
	return bool(FallenAudio.setting("tension_on"))


static func set_tension_audio(on: bool) -> void:
	FallenAudio.set_setting("tension_on", on)


static func ring_colour() -> Color:
	return RING_SAFE if colour_safe() else RING


static func eye_colour() -> Color:
	return EYE_SAFE if colour_safe() else EYE


static func load_colour(tier: int) -> Color:
	var list: Array = LOAD_SAFE if colour_safe() else LOAD
	return list[clampi(tier, 0, list.size() - 1)]


## The load tier's mark (always shown in the safe mode; "" otherwise).
static func load_shape(tier: int) -> String:
	return String(LOAD_SHAPES[clampi(tier, 0, LOAD_SHAPES.size() - 1)]) if colour_safe() else ""


## "● light" in the safe mode, "light" otherwise.
static func load_text(tier: int) -> String:
	var word := String(LOAD_WORDS[clampi(tier, 0, LOAD_WORDS.size() - 1)])
	var mark := load_shape(tier)
	return "%s %s" % [mark, word] if mark != "" else word


## The noise ring's dash count for a noise that carried `share` (0..1) of the farthest: 0 (a
## whole ring) outside the safe mode.
static func ring_dashes(share: float) -> int:
	if not colour_safe():
		return 0
	return roundi(lerpf(RING_DASHES.x, RING_DASHES.y, clampf(share, 0.0, 1.0)))


## Every font size in the shared theme set to its own size times the text scale (at start, from
## GameSettings.apply_all, and when the setting changes). Returns the scale applied.
static func apply_text_scale() -> float:
	var theme := UiKit.THEME
	if theme == null:
		return 1.0
	if _base_sizes.is_empty():
		_base_sizes["|default"] = theme.default_font_size
		for type: StringName in theme.get_font_size_type_list():
			for n: StringName in theme.get_font_size_list(type):
				_base_sizes["%s|%s" % [type, n]] = theme.get_font_size(n, type)
	var k := text_scale()
	_applied_scale = k
	theme.default_font_size = roundi(int(_base_sizes["|default"]) * k)
	for key: String in _base_sizes:
		if key == "|default":
			continue
		var type := StringName(key.get_slice("|", 0))
		var n := StringName(key.get_slice("|", 1))
		theme.set_font_size(n, type, roundi(int(_base_sizes[key]) * k))
	return k


static func applied_scale() -> float:
	return _applied_scale
