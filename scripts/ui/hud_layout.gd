class_name HudLayout
extends RefCounted
## The HUD layout setting (Captain, 2026-10-20: "common sense layout tools"): a size and an
## opacity for each part of the HUD, saved with the other settings (GameSettings section "hud",
## keys "<id>_scale" and "<id>_opacity") and set on the settings screen's HUD tab, with a reset.
## The Hud reads them in its _layout and whenever they change (changes(), a counter): a part
## made bigger keeps its corner of the screen and its zone's room (Hud._scaled), so nothing
## else moves.

## Each part: [id, what the settings screen calls it, whether it has a size (the markers only
## fade)].
const ELEMENTS := [
	["objectives", "Objectives and the hint under them (top right)", true],
	["compass", "Compass (top)", true],
	["squad", "Squad list and command menu (left)", true],
	["radio", "Radio and vehicle readout (bottom middle)", true],
	["weapon", "Weapon and armour (bottom right)", true],
	["wounds", "Wound silhouette (top left)", true],
	["markers", "Objective markers (in the world)", false],
]
## The sliders' ranges: [min, max, step].
const SCALE_RANGE := [0.75, 1.5, 0.05]
const OPACITY_RANGE := [0.3, 1.0, 0.05]
## Where the change counter lives: an Engine meta (a static var on a class of only static
## members is reset when the class is unloaded between uses, as GameSettings notes).
const CHANGES_META := &"hud_layout_changes"


static func scale_of(id: String) -> float:
	return clampf(float(GameSettings.get_value("hud", id + "_scale")), SCALE_RANGE[0], SCALE_RANGE[1])


static func opacity_of(id: String) -> float:
	return clampf(float(GameSettings.get_value("hud", id + "_opacity")), OPACITY_RANGE[0], OPACITY_RANGE[1])


## Sets part `id`'s size (`what` "scale") or opacity ("opacity"), saved; the Hud follows.
static func set_value(id: String, what: String, value: float) -> void:
	GameSettings.set_value("hud", "%s_%s" % [id, what], value)
	_changed()


## Every part back to full size and opacity.
static func reset() -> void:
	for e: Array in ELEMENTS:
		GameSettings.set_value("hud", String(e[0]) + "_scale", 1.0)
		GameSettings.set_value("hud", String(e[0]) + "_opacity", 1.0)
	_changed()


## Whether every part is at its default.
static func is_default() -> bool:
	for e: Array in ELEMENTS:
		if not is_equal_approx(scale_of(String(e[0])), 1.0) or not is_equal_approx(opacity_of(String(e[0])), 1.0):
			return false
	return true


## A number that goes up on every change (the Hud lays itself out again when it differs).
static func changes() -> int:
	return int(Engine.get_meta(CHANGES_META, 0))


static func _changed() -> void:
	Engine.set_meta(CHANGES_META, changes() + 1)
