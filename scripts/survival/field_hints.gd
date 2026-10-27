class_name FieldHints
extends Label
## Contextual control hints for Contractor: Fallen (docs/survival_firsthour.md): the first time a
## situation comes up (FirstHour.situation, judged on the host), a short line on the HUD with the
## player's own key for it (read from the InputMap, never hard-coded: {action} in a hint's text is
## that action's key). Each shows once per profile (seen ids in PATH under BaseHub.profile()), never
## with the Accessibility tab's "Hints" off, and the journal's Field notes page lists the seen ones
## to reread. The HUD holds one of these (Hud._make_body_readout); the statics work without it.

const HINTS := {
	"silent_kill": {"title": "Silent kill", "text": "One of the dead close by hasn't seen you: come up behind it and tap {interact} with a blade for a silent kill."},
	"melee": {"title": "Melee", "text": "{fire} swings, hold {fire} for a heavy, {aim} blocks; block just before a hit lands to parry. Double-tap a move key to dodge."},
	"night": {"title": "Night", "text": "Night: the dead see less and hear more. At a safe spot, Wait until dawn from the ground's menu ({context})."},
	"container": {"title": "Boxes", "text": "{interact} to search it. Picked-over boxes look open, lid up and dull: someone's been through them."},
	"load_mags": {"title": "Loading magazines", "text": "Load magazines: open the inventory ({inventory}) and right-click the loose rounds."},
	"injury": {"title": "Injuries", "text": "Hurt: {body_screen} opens the body screen, {medical_menu} the medical menu."},
	"companion": {"title": "Companions", "text": "Talk: look at them and press {interact}. {context} on them gives an order."},
	"build_kit": {"title": "Building", "text": "{build_mode} for build mode: {fire} builds, the wheel turns it, Shift or Alt + wheel picks the shape and material, {aim} puts it away."},
	"hungry": {"title": "Food and water", "text": "Eat and drink from the inventory ({inventory}, double-click). At a well or a creek, {context} on the water: drink or fill a bottle."},
}
const ORDER: Array[String] = ["silent_kill", "melee", "night", "container", "load_mags", "injury", "companion", "build_kit", "hungry"]
## Proposed: how long a hint stays up.
const SHOW_S := 9.0
const SECTION_SEEN := "seen"

## The file the seen hints live in (tests point it elsewhere: use_file).
static var path := "user://fallen_hints.cfg"
static var _seen: Array = []
static var _loaded := false
## This session: the hints shown, in order, and the last one's words (tests, the HUD).
static var shown_log: Array[String] = []
static var last_text := ""
static var _label: FieldHints = null

var _left := 0.0


# --- Keys --------------------------------------------------------------------------------------

## A key not in the InputMap (a screen's own raw key).
static func _raw_keys() -> Dictionary:
	return {"body_screen": BodyReadout.TOGGLE_KEY, "journal": JournalScreen.TOGGLE_KEY, "character": CharacterScreen.TOGGLE_KEY}


## `action`'s key as the player has it bound ("Ctrl", "6", "Click", "Right-click"), "?" unbound.
static func key_name(action: String) -> String:
	var raw := _raw_keys()
	if raw.has(action):
		return OS.get_keycode_string(int(raw[action]))
	if not InputMap.has_action(StringName(action)):
		return "?"
	for e: InputEvent in InputMap.action_get_events(StringName(action)):
		if e is InputEventKey:
			var k := e as InputEventKey
			var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			return ("Shift+" if k.shift_pressed else "") + OS.get_keycode_string(code)
		if e is InputEventMouseButton:
			match (e as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT:
					return "Click"
				MOUSE_BUTTON_RIGHT:
					return "Right-click"
				MOUSE_BUTTON_MIDDLE:
					return "Middle-click"
				_:
					return "Mouse %d" % int((e as InputEventMouseButton).button_index)
	return "?"


## Hint `id`'s words with the player's keys in.
static func render(id: String) -> String:
	var text := String((HINTS.get(id, {}) as Dictionary).get("text", ""))
	var re := RegEx.create_from_string("\\{(\\w+)\\}")
	var out := text
	for m: RegExMatch in re.search_all(text):
		out = out.replace(m.get_string(0), key_name(m.get_string(1)))
	return out


# --- Seen, per profile -------------------------------------------------------------------------------

static func use_file(p: String) -> void:
	path = p
	_loaded = false
	_seen = []


static func _section() -> String:
	return BaseHub.profile()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	_seen = []
	if cfg.load(path) == OK:
		var v: Variant = cfg.get_value(_section(), SECTION_SEEN, [])
		if v is Array:
			_seen = (v as Array).duplicate()


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value(_section(), SECTION_SEEN, _seen)
	cfg.save(path)


## Whether the Accessibility tab's "Hints" is on.
static func enabled() -> bool:
	return bool(GameSettings.get_value("access", "hints"))


static func is_seen(id: String) -> bool:
	_load()
	return id in _seen


## Forgets every hint seen on this profile (tests; a "show hints again" later).
static func reset_seen() -> void:
	_load()
	_seen.clear()
	_save()
	shown_log.clear()
	last_text = ""


## Owner: hint `id` comes up: shown (and remembered) unless seen before or hints are off. Returns
## whether it showed.
static func client_show(id: String) -> bool:
	if not HINTS.has(id) or is_seen(id) or not enabled():
		return false
	_seen.append(id)
	_save()
	last_text = render(id)
	shown_log.append(id)
	if _label != null and is_instance_valid(_label):
		_label.show_hint(last_text)
	return true


## The Field notes page: every hint seen, "Title: words", in ORDER.
static func field_notes() -> Array:
	_load()
	var out: Array = []
	for id: String in ORDER:
		if id in _seen:
			out.append("%s: %s" % [String(HINTS[id].title), render(id)])
	return out


# --- The HUD line ---------------------------------------------------------------------------------

func _init() -> void:
	name = "FieldHints"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	theme_type_variation = &"HudLabel"
	UiKit.apply(self)
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -320.0
	offset_right = 320.0
	offset_top = 110.0
	offset_bottom = 170.0


func _enter_tree() -> void:
	_label = self


func show_hint(text: String) -> void:
	self.text = text
	_left = SHOW_S
	visible = true


func _process(delta: float) -> void:
	if _left > 0.0:
		_left -= delta
		visible = _left > 0.0
