class_name JournalScreen
extends PanelContainer
## The journal (docs/survival_world.md section 10; call 45): what the survivors have seen and been
## told, in tabs: Log (the journal list, by day), People (persons met: their want, skills as known,
## where last seen), Places (the map's marks with their age and who told), Deadlines (a demand's
## hours left; others' clocks in state()["deadlines"]: [{"text", "due" (world days)}], a fever
## clock when the infection lane writes one there), The trail (ARCHE's pieces read:
## state()["trail"] when the enclave lane writes it, else empty), and the radio's switch.
## Built from the host's view (view(), asked over the network by a client: Intel.request_journal).
## TOGGLE_KEY shows and hides it, in survival only; the mouse is free while it's up. Headless-safe;
## text() is what tests read.

## Proposed: 7 (6 is build mode; no letter is free on foot: controls.gd).
const TOGGLE_KEY := KEY_7
const TABS: Array = [["log", "Log"], ["people", "People"], ["places", "Places"], ["deadlines", "Deadlines"], ["trail", "The trail"],
	["lineage", "Lineage"]]  # (the world's survivors in order: Legacy, call 130)
## Proposed: the Log tab shows this many days back.
const LOG_DAYS := 10

static var _current: JournalScreen = null

var tab := "log"
var _box: VBoxContainer
var _view := {}


static func current() -> JournalScreen:
	return _current if _current != null and is_instance_valid(_current) else null


func _init() -> void:
	name = "JournalScreen"
	visible = false
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 540)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func _enter_tree() -> void:
	_current = self


func toggle() -> void:
	visible = not visible and SurvivalLevel.of(self) != null
	if visible:
		ask()
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Asks the host for the view (the screen fills in when it comes).
func ask() -> void:
	var intel := Intel.get_intel()
	if intel:
		intel.request_journal()


func show_view(v: Dictionary) -> void:
	_view = v
	if visible or DisplayServer.get_name() == "headless":
		refresh()


# --- The view (host) -----------------------------------------------------------------------------

## Host: everything the tabs show, as lines: {"log": [{"day", "lines"}], "people", "places",
## "deadlines", "trail": [lines], "radio": {"repaired", "on", "last"}}.
static func view() -> Dictionary:
	return {"log": log_days(), "people": people_lines(), "places": place_lines(), "deadlines": deadline_lines(), "trail": trail_lines(),
		"lineage": Legacy.lineage_lines((Campaign.section(Survival.SURVIVORS) as Dictionary).get(BaseHub.profile(), {})),
		"radio": {"repaired": bool(FallenRadio.data().repaired), "on": FallenRadio.is_on(), "last": String(FallenRadio.data().get("last", ""))}}


## The journal by day, newest day first: [{"day", "lines": ["14:00 text"]}].
static func log_days() -> Array:
	var by_day := {}
	var days: Array = []
	for e: Variant in Survival.state().get("journal", []):
		if not e is Dictionary:
			continue
		var d := int((e as Dictionary).get("day", 0))
		if d < Survival.day() - LOG_DAYS:
			continue
		if not by_day.has(d):
			by_day[d] = []
			days.append(d)
		var h := float((e as Dictionary).get("hour", 0.0))
		var said := String((e as Dictionary).get("voice", (e as Dictionary).get("text", "")))  # the writer's voice (JournalVoice)
		(by_day[d] as Array).append("%02d:%02d %s" % [floori(h), floori(fmod(h, 1.0) * 60.0), said])
	days.sort()
	days.reverse()
	var out: Array = []
	for d: int in days:
		out.append({"day": d, "lines": by_day[d]})
	return out


## Persons met: "Name (background): wants ...; skills ...; last seen Zone, day N".
static func people_lines() -> Array:
	var out: Array = []
	var met: Dictionary = Intel.section().met
	var ids := met.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return float((met[a] as Dictionary).get("day", 0.0)) > float((met[b] as Dictionary).get("day", 0.0)))
	for pid: String in ids:
		var m: Dictionary = met[pid]
		var rec: Dictionary = WorldSim.people().get(pid, {})
		var who := String(rec.get("name", m.get("name", "someone")))
		var parts := PackedStringArray()
		if not rec.is_empty():
			parts.append("wants %s" % SurvivorPerson.want_text(rec))
			var sk: Dictionary = rec.get("skills", {})
			var known := PackedStringArray()
			for k: String in sk:
				if float(sk[k]) > 0.0:
					known.append("%s %d" % [k, int(sk[k])])
			if not known.is_empty():
				parts.append("skills: " + ", ".join(known.slice(0, 4)))
			var g := Barter.group_of(rec)
			if not g.is_empty() and String(g.get("kind", "")) != "lone":
				parts.append("of %s" % String(g.get("name", "")))
		parts.append("last seen %s, day %d" % [RegionMap.zone_name(String(m.get("zone", ""))), int(float(m.get("day", 0.0)))])
		if String(rec.get("status", "")) == "dead":
			parts.append("dead")
		out.append("%s (%s): %s" % [who, String(rec.get("background", "?")), "; ".join(parts)])
	out.append_array(Legacy.found_lines())  # the dead ones' letters, found on them, in their voice (call 130)
	out.append_array(Letters.lines(CompoundLevel.current(Survival)))  # the dead's letters, read (call 130)
	return out


## The map's marks: "text: Zone, age, told by X".
static func place_lines() -> Array:
	var out: Array = []
	for m: Variant in SurvivalMap.marks(""):
		if not m is Dictionary:
			continue
		var md: Dictionary = m
		var teller := String(md.get("teller", ""))
		var age := SurvivalMap.age_text(md)
		out.append("%s: %s, %s%s%s" % [String(md.get("text", "")), RegionMap.zone_name(String(md.get("zone", ""))), "seen " + age if teller == "" else "told " + age,
			(", told by " + teller) if teller != "" else "", " (faded)" if SurvivalMap.is_faded(md) else ""])
	return out


## The clocks: a demand's hours left, and any other lane's (state()["deadlines"]).
static func deadline_lines() -> Array:
	var out: Array = []
	var now := WorldSim.world_now()
	for gid: String in (WorldSim.section().get("demands", {}) as Dictionary):
		var d: Dictionary = WorldSim.section().demands[gid]
		if bool(d.get("paid", false)) or not d.has("due"):
			continue
		var hours := (float(d.due) - now) * 24.0
		out.append("%s want $%d of goods: %s" % [String(WorldSim.group(gid).get("name", d.get("name", "Raiders"))), int(d.get("want", 0)),
			("%d hours left" % ceili(hours)) if hours > 0.0 else "due now"])
	for d: Variant in Survival.state().get("deadlines", []):
		if d is Dictionary:
			var hours := (float((d as Dictionary).get("due", now)) - now) * 24.0
			out.append("%s: %s" % [String((d as Dictionary).get("text", "")), ("%d hours left" % ceili(hours)) if hours > 0.0 else "now"])
	return out


## ARCHE's trail as read so far (the enclave lane's state()["trail"]: an Array of pieces, or a
## Dictionary with "pieces"; a piece a String or {"text"}).
static func trail_lines() -> Array:
	var trail: Variant = Survival.state().get("trail")
	var pieces: Array = []
	if trail is Array:
		pieces = trail
	elif trail is Dictionary:
		pieces = (trail as Dictionary).get("pieces", [])
	var out: Array = []
	for p: Variant in pieces:
		out.append(String((p as Dictionary).get("text", "")) if p is Dictionary else String(p))
	return out


# --- The screen ----------------------------------------------------------------------------------

func refresh() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_box.add_child(UiKit.heading("Journal"))
	var row := HBoxContainer.new()
	for t: Array in TABS:
		var id := String(t[0])
		var b := UiKit.button(("[%s]" % String(t[1])) if id == tab else String(t[1]), func() -> void:
			tab = id
			refresh())
		row.add_child(b)
	_box.add_child(row)
	match tab:
		"log":
			var days: Array = _view.get("log", [])
			if days.is_empty():
				_box.add_child(UiKit.hint("Nothing written yet."))
			for d: Dictionary in days:
				_box.add_child(UiKit.heading("Day %d" % int(d.day)))
				for l: String in d.lines:
					_box.add_child(UiKit.text(l))
		_:
			if tab == "people":  # write a letter (Letters, call 130): kept on you, found on your body
				var letter := LineEdit.new()
				letter.placeholder_text = "A letter to whoever finds it"
				letter.max_length = Letters.MAX_CHARS
				_box.add_child(letter)
				_box.add_child(UiKit.button("Write a letter", func() -> void:
					var intel_l := Intel.get_intel()
					if intel_l and letter.text.strip_edges() != "":
						intel_l.request_letter(letter.text)))
			var lines: Array = _view.get(tab, [])
			if lines.is_empty():
				_box.add_child(UiKit.hint({"people": "Nobody met yet.", "places": "No marks yet.", "deadlines": "No clocks running.",
					"trail": "Nothing of the trail yet.", "lineage": "Nobody has died here yet."}.get(tab, "")))
			for l: String in lines:
				_box.add_child(UiKit.text(l))
	var radio: Dictionary = _view.get("radio", {})
	var on := bool(radio.get("on", false))
	_box.add_child(UiKit.text("Radio: %s%s" % ["on" if on else ("off" if bool(radio.get("repaired", false)) else "broken"),
		(". Last: " + String(radio.last)) if String(radio.get("last", "")) != "" else ""]))
	var intel := Intel.get_intel()
	if intel:
		var act := "off" if on else ("on" if bool(radio.get("repaired", false)) else "repair")
		_box.add_child(UiKit.button({"off": "Switch the radio off", "on": "Switch the radio on", "repair": "Repair the radio"}[act], func() -> void:
			intel.request_radio(act)))


## The screen's words, top to bottom (tests).
func text() -> String:
	var out := PackedStringArray()
	for c in _box.get_children():
		if c.is_queued_for_deletion():
			continue
		out.append(CharacterScreen._text_of(c))
	return "\n".join(out)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == TOGGLE_KEY and not key.shift_pressed and SurvivalLevel.of(self) != null:
		toggle()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible and SurvivalLevel.of(self) == null:
		visible = false
