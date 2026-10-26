class_name SettlementScreen
extends PanelContainer
## The settlement screen, first form (docs/survival_building.md §5-7): the members with their job
## priorities, what they're doing and their moods; the stocks with their trend over a day; beds,
## the size cap, defence, the footprint and morale; the work orders (add, remove, claim: "I'll do
## it"); the planning view (what's short, who's idle); the council's open votes; and waiting (an
## hour, until dusk, until dawn: call 136). Built from the host's view (Settlement.view, asked
## for over the network by a client). TOGGLE_KEY shows and hides it, in survival only; the mouse
## is free while it's up. Headless-safe; text() is what tests read.

## Proposed: [ (left bracket), beside the character screen's ]; no letter is free on foot
## (controls.gd).
const TOGGLE_KEY := KEY_BRACKETLEFT
const COUNTS := [1, 3, 5, 10, 20]

var _box: VBoxContainer
var _view := {}


func _init() -> void:
	name = "SettlementScreen"
	visible = false
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	position.x += 24.0


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
	var st := Settlement.install(SurvivalLevel.of(self))
	if st:
		st.ask_view(func(v: Dictionary) -> void: refresh(v))


func _act(action: String, args: Array) -> void:
	var st := Settlement.install(SurvivalLevel.of(self))
	if st:
		st.ask(action, args)
		ask()


## Rebuilds from `view` (Settlement.view's keys).
func refresh(view: Dictionary) -> void:
	_view = view
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	if not bool(view.get("exists", false)):
		_box.add_child(UiKit.heading("No settlement yet"))
		_box.add_child(UiKit.text("Your safehouse becomes one the first time its zone is played."))
		return
	_box.add_child(UiKit.heading("The settlement: morale %d, defence %.0f" % [int(view.get("morale", 50)), float(view.get("defence", 0.0))]))
	var fp: Dictionary = view.get("footprint", {})
	_box.add_child(UiKit.text("Beds %d (%d free), room for %d. Footprint: heard %.0f m, seen %.0f m. Your standing %d." % [int(view.get("beds", 0)),
		int(view.get("free_beds", 0)), int(view.get("cap", 0)), float(fp.get("noise_m", 0.0)), float(fp.get("light_m", 0.0)), int(view.get("standing", 0))]))
	if String(view.get("last_call", "")) != "":
		_box.add_child(UiKit.hint(String(view.last_call)))
	var ch: Dictionary = view.get("challenge", {})
	if not ch.is_empty():
		_box.add_child(UiKit.warn(String(ch.get("text", ""))))
	_people(view)
	_stocks(view)
	_orders(view)
	_planning(view)
	_council(view)
	var rest := UiKit.section("Rest", _box)
	rest.add_child(UiKit.button_row([UiKit.button("Wait an hour", func() -> void: _act("wait", ["hour"]), "Pass an hour here (home or indoors, nothing chasing)"),
		UiKit.button("Wait until dusk", func() -> void: _act("wait", ["dusk"]), "Pass the time until dusk"),
		UiKit.button("Wait until dawn", func() -> void: _act("wait", ["dawn"]), "Pass the night")]))
	rest.add_child(UiKit.button("Stow what I carry", func() -> void: _act("stow", []), "Put your food, water, materials, meds, ammo and parts in the stores"))


func _people(view: Dictionary) -> void:
	var sec := UiKit.section("People", _box)
	var people: Array = view.get("people", [])
	if people.is_empty():
		sec.add_child(UiKit.hint("Nobody lives here yet: a survivor who wants a place joins for a free bed."))
	var job_opts := []
	for j: String in SettlementJobs.JOBS:
		job_opts.append([j, String(SettlementJobs.NAMES[j])])
	for p: Dictionary in people:
		var jobs: Array = p.get("jobs", [])
		var names := PackedStringArray(jobs.map(func(j: Variant) -> String: return String(SettlementJobs.NAMES.get(String(j), String(j)))))
		var doing := String(p.get("job_now", "")) if String(p.get("activity", "")) == "work" else String(p.get("activity", ""))
		sec.add_child(UiKit.text("%s (%s), mood %d %s%s, now: %s. Jobs: %s" % [String(p.name), String(p.status), int(p.mood), String(p.band),
			"" if bool(p.get("bed", false)) or String(p.status) != "settler" else ", no bed", doing if doing != "" else "-",
			" > ".join(names) if not names.is_empty() else "none"]))
		if String(p.status) != "settler":
			continue
		var pick := [SettlementJobs.JOBS[0]]
		var id := String(p.id)
		var add := func() -> void:
			var list: Array = jobs.duplicate()
			list.erase(String(pick[0]))
			list.append(String(pick[0]))
			_act("jobs", [id, list])
		var first := func() -> void:
			var list: Array = jobs.duplicate()
			list.erase(String(pick[0]))
			list.insert(0, String(pick[0]))
			_act("jobs", [id, list])
		sec.add_child(UiKit.button_row([UiKit.picker(job_opts, func(v: Variant) -> void: pick[0] = String(v), "A job"),
			UiKit.button("Add last", add, "Add the job at the bottom of their priorities"),
			UiKit.button("Put first", first, "Make it their first job"),
			UiKit.button("Clear", func() -> void: _act("jobs", [id, []]), "No jobs: they rest")]))


func _stocks(view: Dictionary) -> void:
	var sec := UiKit.section("Stocks", _box)
	var st: Dictionary = view.get("stocks", {})
	var parts := PackedStringArray()
	for c: String in Settlement.CATEGORIES:
		var row: Array = st.get(c, [0, 0])
		var tr := int(row[1])
		var lost := ""
		if c == "food":
			var sp: Array = view.get("spoiled", [0, 0])
			if int(sp[0]) > 0:
				lost = ", %d went off today" % int(sp[0])  # (the larder throws spoiled stock out: Spoilage)
		parts.append("%s %d%s%s" % [c, int(row[0]), (" (%+d)" % tr) if tr != 0 else "", lost])
	for i in range(0, parts.size(), 4):
		sec.add_child(UiKit.text(", ".join(parts.slice(i, i + 4))))


func _orders(view: Dictionary) -> void:
	var sec := UiKit.section("Work orders", _box)
	for o: Dictionary in view.get("orders", []):
		var id := int(o.id)
		var done := String(o.get("state", "open")) == "done"
		var line := "P%d %s: %d/%d%s%s" % [int(o.priority), WorkOrders.text_of(o), int(o.done), int(o.count), " done" if done else "",
			(" (you: %s)" % String(o.by)) if WorkOrders.claimed(o) else ""]
		if done:
			sec.add_child(UiKit.hint(line))
			continue
		sec.add_child(UiKit.action_row(line, [UiKit.button("I'll do it", func() -> void: _act("order_claim", [id]), "Settlers leave it to you a while"),
			UiKit.button("Remove", func() -> void: _act("order_remove", [id]), "Drop the order")]))
	var kinds := []
	for k: String in WorkOrders.KINDS:
		if k != "craft":
			kinds.append([k, String(WorkOrders.KINDS[k].name)])
	var pick := ["cut_wood", 5, 3]
	sec.add_child(UiKit.button_row([UiKit.picker(kinds, func(v: Variant) -> void: pick[0] = String(v), "What"),
		UiKit.picker(COUNTS.map(func(n: int) -> Array: return [n, str(n)]), func(v: Variant) -> void: pick[1] = int(v), "How many", 5),
		UiKit.picker([[1, "P1"], [2, "P2"], [3, "P3"], [4, "P4"], [5, "P5"]], func(v: Variant) -> void: pick[2] = int(v), "Priority (1 first)", 3),
		UiKit.button("Add order", func() -> void: _act("order_add", [String(pick[0]), int(pick[1]), int(pick[2])]), "Add the work order")]))


func _planning(view: Dictionary) -> void:
	var sec := UiKit.section("Planning", _box)
	var pl: Dictionary = view.get("planning", {})
	var short: Array = pl.get("short", [])
	var idle: Array = pl.get("idle", [])
	sec.add_child(UiKit.text("Short: %s" % (", ".join(PackedStringArray(short)) if not short.is_empty() else "nothing")))
	sec.add_child(UiKit.text("Idle: %s" % (", ".join(PackedStringArray(idle)) if not idle.is_empty() else "nobody")))


func _council(view: Dictionary) -> void:
	var votes: Array = view.get("votes", [])
	if votes.is_empty():
		return
	var sec := UiKit.section("The council", _box)
	for v: Dictionary in votes:
		var id := int(v.id)
		sec.add_child(UiKit.text(String((v.question as Dictionary).get("text", "A question"))))
		var buttons := []
		for o: Variant in v.options:
			var opt := String(o)
			buttons.append(UiKit.button(opt.capitalize(), func() -> void: _act("vote", [id, opt]), "Say what you want; the council meets"))
		sec.add_child(UiKit.button_row(buttons))


## The screen's words, top to bottom (tests).
func text() -> String:
	return CharacterScreen._text_of(_box)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == TOGGLE_KEY and SurvivalLevel.of(self) != null:
		toggle()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible and SurvivalLevel.of(self) == null:
		visible = false
