class_name GameSettings
extends RefCounted
## The player's settings (Captain, 2026-10-13: "a settings menu with well settings"): video,
## audio, controls and key bindings, saved in settings.cfg beside the shooting hand (Handedness)
## and the get-out key (ControlOptions), which keep their own sections. The settings menu
## (SettingsMenu) changes them; each takes effect at once and is saved. apply_all() puts the
## saved ones into effect at start (the main menu calls it), and the game reads the rest where
## it needs them: mouse_turn() and invert_y() in PlayerInput, fov() for the view, apply_sun() on
## each level's sun, apply_audio() once Sfx has made its buses.

## Where they're saved: settings_path() (a test points it somewhere else with use_file). Kept
## as an Engine meta, not a static var: a class with only static members can be unloaded and
## loaded again between uses, which resets its static vars (the cache below just reloads).
const PATH_META := &"game_settings_path"

## Every setting: section, default, and for a choice its options [value, label].
const WINDOW_MODES := [
	["windowed", "Windowed"], ["borderless", "Borderless fullscreen"], ["fullscreen", "Fullscreen (exclusive)"],
]
const RESOLUTIONS := [
	"1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3840x2160",
]
const FPS_CAPS := [
	[30, "30"], [60, "60"], [90, "90"], [120, "120"], [144, "144"], [165, "165"], [240, "240"], [0, "Unlimited"],
]
const ANTIALIASING := [
	["off", "Off"], ["fxaa", "FXAA (cheap)"], ["msaa2", "MSAA 2x"], ["msaa4", "MSAA 4x"], ["msaa8", "MSAA 8x"],
	["taa", "TAA (steadier far off)"], ["msaa4_taa", "MSAA 4x + TAA (sharpest far off)"],
]
const SHADOWS := [
	["off", "Off"], ["low", "Low"], ["medium", "Medium"], ["high", "High"],
]
## Shadow quality: the sun's shadow map size, how far its shadows reach (m), and soft edges.
const SHADOW_LEVELS := {
	"low": {"atlas": 2048, "reach_m": 120.0, "soft": RenderingServer.SHADOW_QUALITY_HARD},
	"medium": {"atlas": 4096, "reach_m": 320.0, "soft": RenderingServer.SHADOW_QUALITY_SOFT_LOW},
	"high": {"atlas": 8192, "reach_m": 500.0, "soft": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM},
}
## A magnified optic's picture-in-picture (GunSight): "off" zooms the whole view behind the
## eyepiece ring, as before PiP; the others render the scope's own picture at SCOPE_PIP_SCALE of
## the lens' size on screen (real pixels, and no more than the render scale), the rest unzoomed.
const SCOPE_PIP := [
	["off", "Off (zoom the whole view)"], ["low", "Low resolution (fastest)"], ["medium", "Medium resolution"], ["high", "Full resolution"],
]
const SCOPE_PIP_SCALE := {"low": 0.45, "medium": 0.65, "high": 1.0}
## Body gore (BodyDeform, BlastGore; blast-gore 2026-10-20): "off" draws bodies whole (no craters,
## cuts or loose pieces), "reduced" carves craters and takes limbs but shows no bone, pepper or
## gibbed chunks, "full" everything. Only how this machine draws it: the host's wounds, which
## parts are gone and the ragdolls are the same for everyone.
const GORE := [
	["full", "Full"], ["reduced", "Reduced"], ["off", "Off"],
]
## World detail at distance (perf pass, Captain 2026-10-22: "we definitely need more performance
## fixes"): "ultra" draws everything as before, to the horizon; the others stop the far tree canopy
## at "far_trees_m" (fading out over its last FAR_FADE_M; 0: to the horizon), draw rocks, scrub,
## trees and props out to "scatter" times their usual distance, and soldiers further than
## "soldier_shadow_m" cast no sun shadow (0: always; CharacterModel). Up close every level looks the
## same. The scatter is read as a zone's visuals are built (the next zone after a change), the
## soldiers' shadows at once. All numbers Proposed.
const DETAIL := [
	["low", "Low"], ["medium", "Medium"], ["high", "High"], ["ultra", "Ultra (full draw distance)"],
]
const DETAIL_LEVELS := {
	"low": {"far_trees_m": 1800.0, "scatter": 0.65, "soldier_shadow_m": 60.0},
	"medium": {"far_trees_m": 2400.0, "scatter": 0.8, "soldier_shadow_m": 100.0},
	"high": {"far_trees_m": 3200.0, "scatter": 1.0, "soldier_shadow_m": 150.0},
	"ultra": {"far_trees_m": 0.0, "scatter": 1.0, "soldier_shadow_m": 0.0},
}
const FAR_FADE_M := 300.0


## The world detail level's numbers (DETAIL_LEVELS).
static func detail() -> Dictionary:
	return DETAIL_LEVELS.get(String(get_value("video", "detail")), DETAIL_LEVELS.high)


const DEFAULTS := {
	"video": {"window_mode": "windowed", "resolution": "1600x900", "vsync": true, "fps_cap": 0,
		"render_scale": 1.0, "antialiasing": "msaa4_taa", "shadows": "medium", "hfov": 90.0, "ui_scale": 1.0, "head_bob": true,
		"scope_pip": "medium", "gore": "full", "detail": "high"},
	# infil_music: Captain, 2026-10-14, temporary (InfilMusic: Ride of the Valkyries on helicopter insertions).
	"audio": {"master": 0.8, "effects": 1.0, "voice": 1.0, "music": 0.8, "mute_unfocused": false, "infil_music": true},
	"controls": {"mouse_sensitivity": 1.0, "aim_sensitivity": 0.75, "invert_y": false},
	# The HUD layout (HudLayout, ui-modern): each part's size and opacity.
	# spot_diamonds: the side's spot reports as diamonds in the world (combined_arms 4.4, B1).
	"hud": {"objective_markers": true, "objectives_expanded": true, "spot_diamonds": true, "spot_diamond_range_m": 800.0,
		"objectives_scale": 1.0, "objectives_opacity": 1.0, "compass_scale": 1.0, "compass_opacity": 1.0,
		"squad_scale": 1.0, "squad_opacity": 1.0, "radio_scale": 1.0, "radio_opacity": 1.0,
		"weapon_scale": 1.0, "weapon_opacity": 1.0, "wounds_scale": 1.0, "wounds_opacity": 1.0,
		"markers_scale": 1.0, "markers_opacity": 1.0},
	# The gamepad's right stick (wave 7, S4: stick_look). curve: the stick's travel to the power
	# of this (1 straight, higher finer near the centre).
	"gamepad": {"stick_sensitivity": 1.0, "stick_deadzone": 0.15, "stick_curve": 1.6, "stick_invert_y": false},
	# Co-op assists (wave 7, S4; Assists): this machine's picks when it hosts. Off by default; a
	# client follows its host's.
	"assists": {"aim_slowdown": false, "wound_hints": false},
	# The mission screens' last choices (claude/mission-ui, "the last choices remembered"): the
	# board's negotiation terms and the contract picked, the briefing's drop and supports, the
	# debrief's salvage sort.
	"mission_ui": {"board_terms": {}, "board_pick": "", "briefing_drop": "", "briefing_approach": -2, "briefing_supports": [],
		"debrief_sort": "value"},
}
## Ranges for the sliders: [min, max, step].
const RANGES := {
	"render_scale": [0.5, 2.0, 0.05], "hfov": [70.0, 120.0, 1.0], "ui_scale": [0.75, 2.0, 0.05],
	"master": [0.0, 1.0, 0.01], "effects": [0.0, 1.0, 0.01], "voice": [0.0, 1.0, 0.01], "music": [0.0, 1.0, 0.01],
	"mouse_sensitivity": [0.2, 3.0, 0.05], "aim_sensitivity": [0.2, 1.5, 0.05],
	"stick_sensitivity": [0.2, 3.0, 0.05], "stick_deadzone": [0.0, 0.5, 0.01], "stick_curve": [1.0, 3.0, 0.1],
	"spot_diamond_range_m": [100.0, 1500.0, 50.0],
}
## The UI scale (docs/ui_audit.md P1-7, "no automatic UI scale": on 1440p and 4K every screen
## was laid out for 1600x900 and its text was physically tiny). The window height over
## AUTO_UI_HEIGHT, within AUTO_UI_SCALE, picks the scale, and the Menu and HUD size setting
## ("ui_scale") multiplies it. The result never shrinks the logical window below MIN_UI_SIZE,
## the smallest one tests/ui_test.gd fits screens at (1280x720 at the setting's old 1.5 most).
const AUTO_UI_HEIGHT := 1080.0
const AUTO_UI_SCALE := Vector2(1.0, 2.0)
const MIN_UI_SIZE := Vector2(1280.0, 720.0) / 1.5

## The keys a player can rebind (Controls.KEYS, each one key): the label in the Keys list. The
## rest stay fixed (Escape, the Ctrl/Alt menus, fire and aim, Shift combinations, dev keys). An
## optic's zoom is on the side mouse buttons by default (Controls.BUTTONS; bindings: key_for).
const BINDABLE := [
	[&"move_forward", "Move forward"], [&"move_back", "Move back"], [&"move_left", "Move left"], [&"move_right", "Move right"],
	[&"jump", "Jump"], [&"sprint", "Sprint"], [&"hold_breath", "Hold breath (aiming)"], [&"crouch", "Crouch (toggle)"], [&"prone", "Prone (toggle)"],
	[&"stance_adjust", "Adjust stance (hold)"], [&"lean_left", "Lean left"], [&"lean_right", "Lean right"],
	[&"mount", "Rest weapon"], [&"fire_mode", "Fire mode"], [&"reload", "Reload"], [&"grenade", "Grenade"],
	[&"medical_menu", "Medical menu"], [&"inventory", "Inventory"], [&"map", "Map"],
	[&"objectives_toggle", "Objectives list (compact / full)"], [&"objectives_next", "Next objective (picks the active one)"],
	[&"weapon_primary", "Primary weapon"], [&"weapon_sidearm", "Sidearm"], [&"weapon_launcher", "Launcher"],
	[&"weapon_underbarrel", "Underbarrel launcher / shotgun shells"],
	[&"get_out", "Get out of vehicle"], [&"vehicle_view", "Vehicle view (1st/3rd person)"], [&"quick_save", "Quick save"],
	[&"zoom_in", "Optic zoom in / magnifier up"], [&"zoom_out", "Optic zoom out / magnifier down"],
	[&"give_up", "Give up while down (hold)"], [&"inspect", "Inspect item (ground)"],
	[&"nvg_toggle", "NVG down / up"], [&"tag_enemy", "Tag enemy (radio)"],
	[&"binoculars", "Binoculars (raise / lower, on foot)"],
	[&"auto_walk", "Auto-walk (on / off)"],
	[&"walk", "Walk / jog (toggle)"],
	[&"context", "Contextual order (tap: the top one, hold: all)"],
]
## Pairs of bindable actions that may share a key, because they never apply at the same time:
## sprint and hold breath (no sprint while aiming; hold breath only aimed). Binding one of them
## to a key never swaps the other away from it.
const SHARED := [[&"sprint", &"hold_breath"], [&"vehicle_view", &"binoculars"]]  # (B: binoculars on foot, the view seated)
## The audio buses each volume sets (Sfx makes them; the room bus follows effects).
const BUSES := {"master": [&"Master"], "effects": [&"SFX", &"SFX_Room"], "voice": [&"Voice"], "music": [&"Music"]}

static var _values := {}
static var _keys := {}  # action -> physical keycode the player picked
static var _loaded := false
## Whether this window has focus (mute_unfocused).
static var _focused := true


## A setting's value (the saved one, else its default).
static func get_value(section: String, key: String) -> Variant:
	_load()
	return (_values.get(section, {}) as Dictionary).get(key, DEFAULTS[section][key])


## Changes a setting, saves it and puts it into effect.
static func set_value(section: String, key: String, value: Variant) -> void:
	_load()
	if not _values.has(section):
		_values[section] = {}
	_values[section][key] = value
	_save()
	match section:
		"video":
			apply_video()
		"audio":
			apply_audio()


## Every setting back to its default (the key bindings too), saved and in effect.
static func reset_all() -> void:
	_load()
	_values = {}
	_keys = {}
	_save()
	apply_all()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_values = {}
	_keys = {}
	var cfg := ConfigFile.new()
	if cfg.load(settings_path()) != OK:
		return
	for section: String in DEFAULTS:
		if not cfg.has_section(section):
			continue
		_values[section] = {}
		for key: String in DEFAULTS[section]:
			if cfg.has_section_key(section, key):
				_values[section][key] = cfg.get_value(section, key)
	if cfg.has_section("keys"):
		for action: String in cfg.get_section_keys("keys"):
			_keys[StringName(action)] = int(cfg.get_value("keys", action))


## Saves into the file, keeping the sections other code owns (the hand, the get-out key).
static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_path())
	for section: String in DEFAULTS:
		for key: String in DEFAULTS[section]:  # only these keys: "controls" also holds the get-out key
			if (_values.get(section, {}) as Dictionary).has(key):
				cfg.set_value(section, key, _values[section][key])
			elif cfg.has_section_key(section, key):
				cfg.erase_section_key(section, key)
	if cfg.has_section("keys"):
		cfg.erase_section("keys")
	for action: StringName in _keys:
		cfg.set_value("keys", String(action), _keys[action])
	cfg.save(settings_path())


## Forgets what was loaded and reads it again.
static func reload() -> void:
	_loaded = false
	_load()


## Reads and saves the settings at `p` from now on (a test, on a file of its own); "" for the
## real one.
static func use_file(p: String) -> void:
	if p == "":
		Engine.remove_meta(PATH_META)
	else:
		Engine.set_meta(PATH_META, p)
	reload()


static func settings_path() -> String:
	return String(Engine.get_meta(PATH_META, Handedness.SETTINGS_PATH))


# --- Putting them into effect -----------------------------------------------------------------

## Everything saved, into effect (at start: the main menu).
static func apply_all() -> void:
	_load()
	apply_video()
	apply_audio()
	apply_keys()


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


## Window, frame rate, render scale, anti-aliasing, shadows, UI scale. (FOV is read by the view.)
static func apply_video() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var root := tree.root
	if not _headless():
		match String(get_value("video", "window_mode")):
			"borderless":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			"fullscreen":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			_:
				if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				var size := resolution_size(String(get_value("video", "resolution")))
				if size != Vector2i.ZERO and DisplayServer.window_get_size() != size:
					DisplayServer.window_set_size(size)
					var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
					DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(get_value("video", "vsync")) else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(get_value("video", "fps_cap"))
	var scale := float(get_value("video", "render_scale"))
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 0.999 else Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = scale
	var aa := String(get_value("video", "antialiasing"))
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
	root.msaa_3d = {"msaa2": Viewport.MSAA_2X, "msaa4": Viewport.MSAA_4X, "msaa4_taa": Viewport.MSAA_4X, "msaa8": Viewport.MSAA_8X}.get(aa, Viewport.MSAA_DISABLED)
	root.use_taa = aa.ends_with("taa")  # Captain, 2026-10-18: enemies at 300 m (a few pixels tall) shimmered and broke up
	apply_ui_scale()
	if not root.size_changed.is_connected(apply_ui_scale):
		root.size_changed.connect(apply_ui_scale)  # the auto scale follows the window size
	var shadows := String(get_value("video", "shadows"))
	if SHADOW_LEVELS.has(shadows):
		RenderingServer.directional_shadow_atlas_set_size(int(SHADOW_LEVELS[shadows].atlas), true)
		RenderingServer.directional_soft_shadow_filter_set_quality(SHADOW_LEVELS[shadows].soft)
	for sun: Node in root.find_children("*", "DirectionalLight3D", true, false):
		apply_sun(sun as DirectionalLight3D)


## The root's content scale from its window size and the Menu and HUD size setting (apply_video,
## and again whenever the window is resized).
static func apply_ui_scale() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	tree.root.content_scale_factor = ui_scale_for(tree.root.size, float(get_value("video", "ui_scale")))


## The UI scale a window of `window` pixels picks by itself: its height over 1080, 1.0 to 2.0.
static func auto_ui_scale(window: Vector2i) -> float:
	return clampf(float(window.y) / AUTO_UI_HEIGHT, AUTO_UI_SCALE.x, AUTO_UI_SCALE.y)


## The UI scale used in a window of `window` pixels with the setting at `setting`: the auto
## scale times the setting, kept so the logical window stays at least MIN_UI_SIZE.
static func ui_scale_for(window: Vector2i, setting: float) -> float:
	var scale := auto_ui_scale(window) * setting
	if window.x > 0 and window.y > 0:
		scale = minf(scale, maxf(1.0, minf(window.x / MIN_UI_SIZE.x, window.y / MIN_UI_SIZE.y)))
	return scale


## A level's sun under the shadow setting (each level calls it when it makes its sun).
static func apply_sun(sun: DirectionalLight3D) -> void:
	if sun == null or sun.name == &"SkyFill":  # ZoneLevel's shadowless fill light stays shadowless
		return
	var shadows := String(get_value("video", "shadows"))
	sun.shadow_enabled = shadows != "off"
	if SHADOW_LEVELS.has(shadows):
		sun.directional_shadow_max_distance = float(SHADOW_LEVELS[shadows].reach_m)


## "1920x1080" as a size (zero if it isn't one).
static func resolution_size(text: String) -> Vector2i:
	var parts := text.split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


## The field of view setting (degrees, not aiming): HORIZONTAL, as seen on a 16:9 screen
## (docs/animation.md, "World scale"). Its key is "hfov": the old "fov" was the camera's
## vertical angle (Godot's Camera3D keeps the height), and its default of 80 vertical was about
## 112 deg across on 16:9, which made the world look small and far and every pace look fast.
static func fov() -> float:
	return float(get_value("video", "hfov"))


## Whether the view bobs with the steps (docs/animation.md, "First person").
static func head_bob() -> bool:
	return bool(get_value("video", "head_bob"))


## The scope picture's render size against the lens' size on screen (SCOPE_PIP_SCALE); 0 with
## picture-in-picture scopes off (GunSight zooms the whole view instead).
static func scope_pip_scale() -> float:
	return float(SCOPE_PIP_SCALE.get(String(get_value("video", "scope_pip")), 0.0))


## The gore setting (GORE): "full", "reduced" or "off".
static func gore() -> String:
	var g := String(get_value("video", "gore"))
	return g if g in ["full", "reduced", "off"] else "full"


## The camera's (vertical) field of view for the setting: what Camera3D.fov takes. Hor+: wider
## screens see more to the sides, the same up and down.
static func view_fov() -> float:
	return vertical_fov(fov())


## Vertical degrees for `horizontal` degrees across a 16:9 view.
static func vertical_fov(horizontal: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal) * 0.5) * 9.0 / 16.0))


## The volumes on their buses (Sfx calls this once it has made them; muted in the background
## when that's on and the window has lost focus).
static func apply_audio() -> void:
	var mute := bool(get_value("audio", "mute_unfocused")) and not _focused
	for key: String in BUSES:
		var level := 0.0 if mute else float(get_value("audio", key))
		for bus: StringName in BUSES[key]:
			var i := AudioServer.get_bus_index(bus)
			if i < 0:
				continue
			AudioServer.set_bus_mute(i, level <= 0.001)
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(level, 0.001)))


## The window gained or lost focus (the main menu passes it on): for mute_unfocused.
static func focus_changed(focused: bool) -> void:
	_focused = focused
	if bool(get_value("audio", "mute_unfocused")):
		apply_audio()


## How far a mouse count turns the view (radians): the base rate times the sensitivity, and
## the aim sensitivity on top while aiming down sights.
static func mouse_turn(base: float, aiming: bool) -> float:
	var turn := base * float(get_value("controls", "mouse_sensitivity"))
	return turn * float(get_value("controls", "aim_sensitivity")) if aiming else turn


static func invert_y() -> bool:
	return bool(get_value("controls", "invert_y"))


## The gamepad's full turn rate (radians a second) at sensitivity 1, the stick all the way over.
const STICK_TURN_RATE := 3.0


## The right stick's raw deflection (x right, y down; each -1..1) as look: zero inside the
## deadzone (round, so diagonals aren't cut), then the travel past it rescaled to 0..1 and
## raised to the curve setting, the same way round; y flipped with stick_invert_y. The result
## times STICK_TURN_RATE and the sensitivity is radians a second.
static func stick_look(raw: Vector2) -> Vector2:
	var dead := float(get_value("gamepad", "stick_deadzone"))
	var length := minf(raw.length(), 1.0)
	if length <= dead or length <= 0.0:
		return Vector2.ZERO
	var travel := pow((length - dead) / maxf(1.0 - dead, 0.001), float(get_value("gamepad", "stick_curve")))
	var out := raw.normalized() * travel
	if bool(get_value("gamepad", "stick_invert_y")):
		out.y = -out.y
	return out


## How far the stick turns the view this frame (radians, x yaw, y pitch: both "positive is
## right / down" as on the stick), from its look (stick_look), with the sensitivity, the aim
## sensitivity while aiming, and `mult` (concussion, scope, aim slowdown).
static func stick_turn(look: Vector2, aiming: bool, delta: float, mult := 1.0) -> Vector2:
	var rate := STICK_TURN_RATE * float(get_value("gamepad", "stick_sensitivity")) * mult
	if aiming:
		rate *= float(get_value("controls", "aim_sensitivity"))
	return look * rate * delta


# --- Key bindings -----------------------------------------------------------------------------

## A binding that is a mouse button: this bit with the button index (Controls.BUTTONS).
const MOUSE_BIND := 1 << 28


## The key an action is on now (its rebinding, else Controls.KEYS, else its mouse button in
## Controls.BUTTONS as MOUSE_BIND | index).
static func key_for(action: StringName) -> int:
	_load()
	if _keys.has(action):
		return int(_keys[action])
	if Controls.BUTTONS.has(action):
		return MOUSE_BIND | int(Controls.BUTTONS[action])
	var keys: Array = Controls.KEYS.get(action, [])
	return keys[0] if not keys.is_empty() else KEY_NONE


## A binding's name for the Keys list: the key's, or "Mouse 4" and the like.
static func binding_name(code: int) -> String:
	if code & MOUSE_BIND:
		match code & ~MOUSE_BIND:
			MOUSE_BUTTON_MIDDLE: return "Middle mouse"
			MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
		return "Mouse %d" % (code & ~MOUSE_BIND)
	return OS.get_keycode_string(code)


## Puts `action` on `key` (saved). Any other bindable action on that key is moved to the
## first one's old key, so nothing is left on two actions. Returns the action that swapped, or &"".
static func bind(action: StringName, key: int) -> StringName:
	_load()
	var old := key_for(action)
	var swapped := &""
	for pair: Array in BINDABLE:
		var other: StringName = pair[0]
		if other != action and key_for(other) == key and not shares_key(action, other):
			_keys[other] = old
			swapped = other
	_keys[action] = key
	_save()
	apply_keys()
	return swapped


## Whether `a` and `b` may sit on one key (SHARED).
static func shares_key(a: StringName, b: StringName) -> bool:
	return SHARED.any(func(pair: Array) -> bool: return (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a))


## Every key back to Controls.KEYS (saved).
static func reset_keys() -> void:
	_load()
	_keys = {}
	_save()
	apply_keys()


## The bindable actions' plain-key events in the InputMap, from key_for (the Shift, Ctrl and
## Alt ones Controls adds are left alone).
static func apply_keys() -> void:
	_load()
	for pair: Array in BINDABLE:
		var action: StringName = pair[0]
		if not InputMap.has_action(action):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			var k := event as InputEventKey
			if (k and not k.shift_pressed and not k.ctrl_pressed and not k.alt_pressed and k.location == KEY_LOCATION_UNSPECIFIED) \
					or event is InputEventMouseButton:
				InputMap.action_erase_event(action, event)
		var key := key_for(action)
		if key & MOUSE_BIND:
			var button := InputEventMouseButton.new()
			button.button_index = (key & ~MOUSE_BIND) as MouseButton
			InputMap.action_add_event(action, button)
		elif key != KEY_NONE:
			var event := InputEventKey.new()
			event.physical_keycode = key as Key
			InputMap.action_add_event(action, event)
