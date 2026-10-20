class_name TutorialGuide
extends CanvasLayer
## The tutorial (Captain, 2026-10-14: "he needs a tutorial in the game at some point soon"; for
## cghath first): a solo session on the compound (Menu "Tutorial") with a panel down the left that
## walks a new player through the controls one step at a time, in sections (moving, shooting,
## gear, squad orders, medical, casualties, tagging, vehicles, rebel support, static guns, the
## campaign). Each step says what to do and on which key (read from the live bindings, so a
## rebind shows), and ticks itself off when it's done: the basics on the action's press, the rest
## on what the game's state shows (moved, a pouch on the carrier, the weapon light on, the squad
## sent off and back, treated, a medic called, a casualty dragged and his tourniquet on, seated as
## driver, a squadmate aboard, a tag on the target, a villager's job taken, a gun set up then
## packed). What can't be played on the compound (the contract board, extraction, the debrief)
## is a short step to read ("read": Page Down goes on, counted done).
##
## Round 2 (cghath, 2026-10-20: "it should include anything complex that a new player wouldn't
## immediately understand and the ability to skip things if a teammate wants to teach them"): the
## section list (Page Up, and open at the start) ticks sections off as "a teammate teaches it":
## the guide jumps past them. Each row also has Start here (go to that section). Shift + Page Down
## skips the rest of the current section, Page Down one step. The ticks are kept for the rest of
## the game's run (skip_sections, static), so a second tutorial starts with them.
##
## Co-op: the guide is the host's alone. It's made on the host's machine (Menu.host_tutorial),
## follows the host's own player and isn't sent anywhere, so the learner is whoever hosts the
## tutorial, and the section list, Page Up and the skip keys are theirs. A teammate who joins to
## teach sees no panel: they tell the learner which sections to tick.
##
## The session's setup (host, _set_up_session): the player gets a radio, grenades and medical kit
## to try things with; the compound's own hostile patrol goes and the squad holds fire, so nobody
## fights while the player learns; a stand-in enemy (TARGET, not moving or shooting) stands across
## the yard; an M-ATV is parked south of the gate, a villager (VILLAGER) waits by it, and an M2's
## two loads lie beside him (only once the game has static guns: StaticWeapons' loads). A step
## that needs more sets it up when it starts ("setup": a spare pouch and a weapon light to put on,
## a graze to treat, a hurt villager to drag and tourniquet). Outside a campaign the locals'
## requests answer here (server_locals_asked, server_locals_given; RebelSupport) and the rebels'
## Lookouts work without a region (RebelCalls). Proposed steps; text is the game's plain voice.

const NODE_NAME := "TutorialGuide"
const TARGET := "TutorialTarget"
const VILLAGER := "TutorialVillager"
## A second villager, hurt (the Casualties section): not a squadmate, so the squad's medics leave
## him to you (SquadAI cares for its own side).
const CASUALTY := "TutorialCasualty"
const VEHICLE_ID := "tutorial_matv"
const VEHICLE_MODEL := "matv"
## The kit to try things with: item id -> how many, most needed first (a bare start has little
## room). Loose bandages first: with none loose a medic comes unasked (docs/audits/followups.md
## F-20), and the treat-yourself step wants you to do it.
const KIT := {&"pressure_bandage": 2, &"radio": 1, &"ifak": 1, &"tourniquet": 1, &"frag_grenade": 1, &"smoke_grenade": 1}
## A static gun's two loads, one a man (StaticWeapons.KITS "tripod_m2"), and the gun they make.
const STATIC_LOADS: Array[StringName] = [&"static_m2_gun", &"static_m3_tripod"]
const STATIC_MODEL := "tripod_m2"
## The spare pouch to put on the carrier: the first of these with a free point on what you wear.
const POUCHES: Array[StringName] = [&"pouch_utility", &"pouch_tq", &"pouch_grenade", &"pouch_mag_single", &"pouch_pistol_mag", &"pouch_radio"]
const LIGHT := &"light_weapon"
const CARRIER := &"plate_carrier"
const RIFLE := &"m4a1"
const MOVE_M := 4.0
## Driving this far counts as driving.
const DRIVE_M := 10.0
## A gun set up this close to the player is his.
const GUN_NEAR_M := 15.0
## The tutorial's grazes: a slow bleed one pressure bandage stops (WoundModel.BANDAGED_KINDS).
const GRAZE_RATE := 0.05
const BLEEDS: Array[String] = ["graze", "muscle", "venous"]
## The hurt villager: an artery in his right thigh, slow enough to leave time to learn, and
## trauma enough (Vitals.server_damage: 42% of his blood) to put him out until it's stopped.
const CASUALTY_PART := &"thigh_r"
const CASUALTY_RATE := 0.05
const CASUALTY_TRAUMA := 70.0
## Where things stand on the compound (its own coordinates, on the ground): the target in the
## open yard west of the main building's door, in sight from the gate; the M-ATV south-west of the
## gate facing the open ground; the villager by the gate; the M2's loads beside him; the hurt
## villager just west of the gate.
const TARGET_AT := Vector3(-6, 0.1, -1)
const VEHICLE_AT := Vector3(-14, 0, 32)
const VILLAGER_AT := Vector3(7, 0, 26)
const GUN_AT := Vector3(10, 0.3, 28)
const TRIPOD_AT := Vector3(11.2, 0.3, 28)
const CASUALTY_AT := Vector3(-3, 0, 24)
## Page Down skips a step (with Shift, the section); Page Up opens and closes the section list.
const SKIP_KEY := KEY_PAGEDOWN
const SECTIONS_KEY := KEY_PAGEUP
const TICK_S := 0.2
## The panel's top when the window has room (it moves up to fit a short one).
const PANEL_Y := 180.0
const PANEL_W := 380.0
const LIST_W := 620.0
const SKIP_TEXT := "Skip: a teammate teaches it"

## The steps in order: "section" (shown in the title), "text" (what to do; "{get_out}" says how
## to get out of a vehicle, as the settings have it), "keys" (actions whose keys are shown), and
## how it completes: "on" (any of these actions pressed), "raw" (any of these keycodes), "check"
## (a method name on this node returning true once done) or "read" (Page Down, once read).
## "setup": a method run on the host when the step starts. "needs": a method saying whether the
## step is in at all (steps).
const STEPS := [
	{"section": "Moving", "text": "Walk around: look with the mouse, move with", "keys": [&"move_forward", &"move_left", &"move_back", &"move_right"], "check": "_moved"},
	{"section": "Moving", "text": "Sprint: hold", "keys": [&"sprint"], "on": [&"sprint"]},
	{"section": "Moving", "text": "Crouch (a toggle)", "keys": [&"crouch"], "on": [&"crouch"]},
	{"section": "Moving", "text": "Go prone (a toggle; again to get up)", "keys": [&"prone"], "on": [&"prone"]},
	{"section": "Moving", "text": "Lean round a corner: hold", "keys": [&"lean_left", &"lean_right"], "on": [&"lean_left", &"lean_right"]},
	{"section": "Moving", "text": "Finer stances: hold this, then W / S to stand or crouch higher or lower, A / D for a side stance", "keys": [&"stance_adjust"], "on": [&"stance_adjust"]},
	{"section": "Shooting", "text": "Aim down the sights: hold the right mouse button", "keys": [], "on": [&"aim"]},
	{"section": "Shooting", "text": "Fire: the left mouse button (the target across the yard won't shoot back)", "keys": [], "on": [&"fire"]},
	{"section": "Shooting", "text": "Reload", "keys": [&"reload"], "on": [&"reload"]},
	{"section": "Shooting", "text": "Switch the fire mode (single, burst, auto)", "keys": [&"fire_mode"], "on": [&"fire_mode"]},
	{"section": "Shooting", "text": "Rest the weapon on a wall or a sandbag in front of you", "keys": [&"mount"], "on": [&"mount"]},
	{"section": "Shooting", "text": "Take a grenade in hand (Fire throws, Aim lobs, the same key again puts it away)", "keys": [&"grenade"], "on": [&"grenade"]},
	{"section": "Gear", "text": "Hold Left Ctrl and look at a crate, a door or a person: the interaction menu", "keys": [], "on": [&"interact"]},
	{"section": "Gear", "text": "Open your inventory: your gear, its pouches and the backpack. Mass, at the top, is what you carry: the heavier, the slower you move, turn and tire", "keys": [&"inventory"], "on": [&"inventory"]},
	{"section": "Gear", "setup": "_give_pouch", "check": "_pouch_on", "keys": [&"inventory"],
		"text": "You were given a spare pouch. Hang it on your carrier: in the inventory, right-click it and pick Attach (the MOLLE button shows the carrier's points)"},
	{"section": "Gear", "setup": "_give_light", "check": "_light_mounted", "keys": [&"inventory"],
		"text": "And a Weapon Light: in the inventory, right-click it and pick Mount on your rifle"},
	{"section": "Gear", "check": "_light_on", "keys": [&"weapon_light"],
		"text": "Switch the light on (again for off), the rifle in hand. Careful: the enemy sees it too"},
	{"section": "Gear", "text": "Night vision: flip it down or up (on a helmet with NVGs)", "keys": [&"nvg_toggle"], "on": [&"nvg_toggle"]},
	{"section": "Squad orders", "text": "The map: double-click to place a marker, right-click for orders", "keys": [&"map"], "on": [&"map"]},
	{"section": "Squad orders", "text": "Squad orders: ` (backquote) opens the command menu for everyone, F1-F8 picks a squadmate", "keys": [], "raw": [KEY_QUOTELEFT, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8]},
	{"section": "Squad orders", "check": "_squad_sent", "keys": [],
		"text": "Send the squad somewhere: look at a spot on the ground, then ` (backquote), 1 Move, 2 Move there"},
	{"section": "Squad orders", "setup": "_mark_squad", "check": "_squad_back", "keys": [],
		"text": "Bring them back: ` (backquote), 1 Move, 1 Return to formation"},
	{"section": "Squad orders", "setup": "_mark_formation", "check": "_formation_set", "keys": [],
		"text": "Pick their formation: ` (backquote), 8 Formation, then one (Line, File...). 7 Spacing there sets how far apart they keep"},
	{"section": "Medical", "text": "The medical menu: treat yourself or a squadmate (Shift + it treats yourself fast)", "keys": [&"medical_menu"], "on": [&"medical_menu"]},
	{"section": "Medical", "setup": "_graze_arm", "check": "_self_treated", "keys": [&"medical_menu"],
		"text": "You have a graze on the arm. Treat it yourself: hold Left Ctrl, add Left Alt, pick your arm, Treat yourself, Pressure Bandage. The medical menu works too"},
	{"section": "Medical", "setup": "_graze_leg", "check": "_medic_called", "keys": [],
		"text": "Another graze, on the leg. This time call a medic: ` (backquote), 5 Status, 3 Medic!. Or pick one squadmate (F1-F8) and 5, 4 Treat me"},
	{"section": "Medical", "check": "_patched_up", "keys": [],
		"text": "Stay where you are: a squadmate comes over and patches you up"},
	{"section": "Casualties", "setup": "_fell_casualty", "check": "_dragging", "keys": [],
		"text": "A villager is down just inside the gate, bleeding hard from his thigh. Get him out of the open first: hold Left Ctrl on him and pick Drag (S backs you away)"},
	{"section": "Casualties", "check": "_let_go", "keys": [&"grenade"],
		"text": "Let go of him: this key, or hold Left Ctrl, add Left Alt, Put down"},
	{"section": "Casualties", "setup": "_top_up_tourniquet", "check": "_tourniquet_on", "keys": [&"medical_menu"],
		"text": "An artery: a bandage won't hold it. Hold Left Ctrl on his right leg and pick the Tourniquet. This key, looking at him, shows all he needs"},
	{"section": "Casualties", "read": true, "keys": [&"give_up"],
		"text": "If you go down: you can't move or fight, and a medic comes for you; with the bleeding stopped you come round in time. After 15 s down (at once, with nobody near), hold this key to give up and respawn"},
	{"section": "Tagging enemies", "check": "_tagged", "keys": [&"tag_enemy"],
		"text": "Tag the enemy across the yard for the squad: look at him and press the key. It goes out by radio, so you need the one you carry"},
	{"section": "Vehicles", "check": "_driving", "keys": [],
		"text": "An M-ATV is parked south-west of the gate. Hold Left Ctrl at its driver's door and pick Get in as driver"},
	{"section": "Vehicles", "setup": "_mark_vehicle", "check": "_driven", "keys": [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"vehicle_view"],
		"text": "Drive a little way: throttle, reverse, steer, brake. The last key switches the view"},
	{"section": "Vehicles", "check": "_on_gun", "keys": [],
		"text": "The gun seat: hold Left Ctrl inside, Move to, Gunner. The left mouse button fires"},
	{"section": "Vehicles", "check": "_squad_aboard", "keys": [],
		"text": "Order the squad in: aim at the M-ATV and press ` (backquote), 4 Mount, 1 Get in that vehicle. They walk over and climb in"},
	{"section": "Vehicles", "check": "_all_out", "keys": [],
		"text": "Everyone out: {get_out} yourself, then ` (backquote), 4 Mount, 2 Get out for the squad"},
	{"section": "Rebel support", "check": "_asked_for_work", "keys": [],
		"text": "The locals back you more as you help them. Find the villager by the gate, hold Left Ctrl on him and pick Ask if they need help"},
	{"section": "Rebel support", "check": "_gave_supplies", "keys": [],
		"text": "He asked for medical supplies. Hold Left Ctrl on him: More, Give supplies, then a bandage or your IFAK"},
	{"section": "Rebel support", "check": "_lookouts_out", "keys": [],
		"text": "Backing earns call-ins. Ask for lookouts: ` (backquote), 0 Support, 9 Rebels, 1 Lookouts. They mark the gunmen near you. (In a campaign each region opens more as its support grows.)"},
	{"section": "Static guns", "needs": "_has_static_guns", "check": "_holding_load", "keys": [],
		"text": "An M2 and its tripod lie by the villager: two heavy loads, one per man. Pick one up: hold Left Ctrl on it, Pick up"},
	{"section": "Static guns", "needs": "_has_static_guns", "setup": "_mark_guns", "check": "_gun_up", "keys": [],
		"text": "Set it up: with the other load within 3 m (on the ground, or in a squadmate's hands), hold Left Ctrl, add Left Alt, Set up the gun. Hold still while it goes up"},
	{"section": "Static guns", "needs": "_has_static_guns", "setup": "_mark_gun", "check": "_gun_packed", "keys": [],
		"text": "Pack it up: nobody on the gun, hold Left Ctrl at it and pick Pack up the gun. The loads come back into free hands"},
	{"section": "The campaign", "read": true, "keys": [],
		"text": "In the campaign you run a small company from its base. At the ops desk (Left Ctrl on it), the Contract board offers jobs: pick one, agree the pay, accept it"},
	{"section": "The campaign", "read": true, "keys": [],
		"text": "The ops desk's Loadouts kits you and each squadmate from the company's stash. Anything you're short of, buy right there (Buy missing)"},
	{"section": "The campaign", "read": true, "keys": [],
		"text": "Deploy from the ops desk. The briefing map shows the objectives and your intel: mark a plan, pick where you go in, and everyone presses Ready"},
	{"section": "The campaign", "on": [&"map"], "keys": [&"map"],
		"text": "Getting out is on the map: call extraction at an LZ, a grid or a purple smoke, and get everyone in. Leaving someone behind takes a second confirm. Open the map now"},
	{"section": "The campaign", "read": true, "keys": [],
		"text": "The debrief: pay, casualties, what you carried out (bodies and kit come out with you), and salvage to claim from the field. Then back to the board"},
]

## The sections ticked "a teammate teaches it" (section name -> true): skipped. Kept for the game's
## run, so a second tutorial starts with the same ticks.
static var skip_sections := {}

## The steps this session runs: STEPS whose "needs" holds (no static guns in this build: none of theirs).
var steps: Array = []
var step := 0
var done := 0
## The steps done by doing them (index in steps -> true): a section's "done" in the list.
var done_steps := {}
var _panel: PanelContainer
var _title: Label
var _text: Label
var _keys: Label
var _list: Label
## The section list (open_sections): its layer, and each section's skip tick by name.
var _sections: CanvasLayer
var _section_box: VBoxContainer
var section_ticks := {}
var _start := Vector3.INF
var _tick := 0.0
var _since := 0.0             # host: Soldier._now() when the current step started
var _mark := Vector3.INF      # host: where the vehicle stood when the drive step started
var _hurt := false            # host: a step's graze went on
var _asked := false           # host: the villager was asked for work (server_locals_asked)
var _given := false           # host: he was given supplies (server_locals_given)
var _guns_before := {}        # host: static guns standing when the set-up step started (instance ids)
var _gun_id := 0              # host: the instance id of the gun the player set up (0: none)
var _pouch: StringName = &""  # host: the spare pouch handed out (_give_pouch)
var _pouches_on := 0          # host: how many of it hung on what you wear then
var _was_away := false        # host: a squadmate was off on an order during the bring-back step
var _formation_was := ""      # host: the squad's formation and spacing when that step started
var _held := false            # host: the player had hold of the hurt villager


## Opens the tutorial in the level `from` is in (host, after it's up): the guide, the kit and the
## target, and the section list over it (`sections`). Returns the guide.
static func start(from: Node, sections := true) -> TutorialGuide:
	var lvl := CompoundLevel.current(from)
	if lvl == null:
		return null
	var old := lvl.get_node_or_null(NODE_NAME)
	if old:
		old.free()
	var g := TutorialGuide.new()
	g.name = NODE_NAME
	lvl.add_child(g)
	if sections:
		g.open_sections()
	return g


## The tutorial running in the level `from` is in, or null (no tutorial: a real session).
static func of(from: Node) -> TutorialGuide:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	var g := lvl.get_node_or_null(NODE_NAME) as TutorialGuide if lvl else null
	return g if g and not g.is_queued_for_deletion() else null


func _ready() -> void:
	layer = 5
	steps = STEPS.filter(func(s: Dictionary) -> bool: return String(s.get("needs", "")) == "" or bool(call(String(s.needs))))
	_panel = UiKit.panel()
	UiKit.apply(_panel)
	_panel.custom_minimum_size = Vector2(PANEL_W, 0)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	_panel.add_child(box)
	_title = _label(UiKit.FONT_HEADING, UiKit.ACCENT)
	_text = _label(UiKit.FONT_BODY, UiKit.TEXT)
	_keys = _label(UiKit.FONT_HEADING, UiKit.GOOD)
	_list = _label(UiKit.FONT_SMALL, UiKit.TEXT_DIM)
	for l in [_title, _text, _keys, _list]:
		box.add_child(l)
	_panel.resized.connect(_place)
	get_viewport().size_changed.connect(_place)
	_place()
	_set_up_session.call_deferred()
	_begin()


func _label(size: int, colour: Color) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_W - UiKit.SPACE_L - 4, 0)
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", colour)
	return l


## The panel down the left, at PANEL_Y, or higher in a window too short for it there.
func _place() -> void:
	if not is_instance_valid(_panel) or not _panel.is_inside_tree():
		return
	var room := _panel.get_viewport_rect().size
	var lowest := room.y - _panel.size.y - UiKit.EDGE
	_panel.position = Vector2(UiKit.EDGE, maxf(minf(PANEL_Y, lowest), UiKit.EDGE * 0.5))


## Host: the kit to try things with; once the compound's walls are up (the AI comes with them),
## the yard cleared of the compound's patrol, the squad told to hold fire, and the target, the
## M-ATV, the villager and the static gun's loads put out.
func _set_up_session() -> void:
	var lvl := CompoundLevel.current(self)
	if lvl == null or not multiplayer.is_server():
		return
	var me := MapNodes.local_player(self)
	if me:
		for id: StringName in KIT:
			var short := int(KIT[id]) - me.inventory.count_of(id)
			if short > 0:
				me.inventory.take(id, short)
		_start = me.global_position
	if lvl.voxel_world and not lvl.voxel_world.is_built():
		await lvl.voxel_world.structures_built  # (CompoundLevel._spawn_ai, connected first, has run by now)
	if not is_inside_tree():
		return
	me = MapNodes.local_player(self)
	for h: Dictionary in CompoundLevel.HOSTILES:  # nobody fights while you learn
		var foe := lvl.ai.get_node_or_null(NodePath(String(h.name)))
		if foe:
			foe.queue_free()
	var squad := lvl.squad_for(&"friendly")
	if squad and me:
		squad.set_hold_fire(me, true)  # the target is for you; Engage > Open fire lets them shoot
	if lvl.ai.get_node_or_null(NodePath(TARGET)) == null and lvl.has_method(&"spawn_soldier"):
		var target: Soldier = lvl.call(&"spawn_soldier", {"name": TARGET, "faction": "hostile", "variant": "urban", "pos": lvl.above_ground(TARGET_AT),
			"loadout": ["plate_carrier", "helmet"], "combat": 0.1, "discipline": 1.0, "guard": true, "mode": "calm"})
		if target:
			var brain := SquadAI.of(target)
			if brain:
				brain.process_mode = Node.PROCESS_MODE_DISABLED  # a stand-in: it doesn't move or shoot
	var layer := VehicleLayer.of(self)
	if layer and layer.find(VEHICLE_ID) == null:  # facing south, the open ground ahead
		layer.server_spawn(VEHICLE_MODEL, Transform3D(Basis(Vector3.UP, PI), lvl.above_ground(VEHICLE_AT) + Vector3.UP * 0.6), "", &"player", VEHICLE_ID)
	var people := PeopleLayer.find(self)
	if people and lvl.ai.get_node_or_null(NodePath(VILLAGER)) == null and _person(VILLAGER) == null:
		var villager := people.server_spawn_person({"name": VILLAGER, "kind": "civilian", "side": "neutral", "label": "Villager (Karim)",
			"pos": lvl.above_ground(VILLAGER_AT + Vector3.UP * 0.1), "rot_y": PI})
		if villager:
			people.server_set_state(villager, {"order": "stop"})  # he waits for you by the gate
	if _has_static_guns():
		lvl.spawn_item(STATIC_LOADS[0], 1, lvl.above_ground(GUN_AT), "tutorial_static_gun")
		lvl.spawn_item(STATIC_LOADS[1], 1, lvl.above_ground(TRIPOD_AT), "tutorial_static_tripod")


## The keys of `actions`, as the player has them bound now ("W / A / S / D").
static func keys_text(actions: Array) -> String:
	var out := PackedStringArray()
	for a: StringName in actions:
		for e in InputMap.action_get_events(a) if InputMap.has_action(a) else []:
			var k := e as InputEventKey
			if k:
				out.append(OS.get_keycode_string(k.physical_keycode if k.physical_keycode != 0 else k.keycode))
				break
	return " / ".join(out)


## The current step's text as this player has the controls ("{get_out}": the get-out key, or the
## seat's Left Ctrl menu: ControlOptions).
static func step_text(s: Dictionary) -> String:
	var get_out := "press %s" % ControlOptions.get_out_key_name() if ControlOptions.get_out_key() else "hold Left Ctrl inside, Get out"
	return String(s.text).replace("{get_out}", get_out)


func _show() -> void:
	if step >= steps.size():
		_title.text = "Tutorial: done (%d of %d)" % [done, steps.size()]
		_text.text = "That's the basics. Esc and Main menu to leave; host the campaign from there to start a company. The shooting range at the base and the vehicle range (Test zones) are good places to practise. A gamepad works too: hold View for the pad wheel."
		_keys.text = ""
		_list.text = "Page Up: the section list."
		return
	var s: Dictionary = steps[step]
	_title.text = "Tutorial %d of %d: %s" % [step + 1, steps.size(), String(s.get("section", ""))]
	_text.text = step_text(s)
	_keys.text = keys_text(s.get("keys", []))
	_list.text = "Page Down: %s. Shift + Page Down skips the section, Page Up lists them." % ("next" if s.get("read", false) else "skip this step")


## The current step starts: past any section ticked to skip, its setup on the host, then the panel.
func _begin() -> void:
	while step < steps.size() and skip_sections.has(section_of(step)):
		step += 1
	_since = Soldier._now()
	if step < steps.size() and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var setup := String((steps[step] as Dictionary).get("setup", ""))
		if setup != "":
			call(setup)
	_show()
	if sections_open():
		_fill_sections()


## Every peer, this player only: a step's action pressed, or the guide's own keys.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		if key.physical_keycode == SECTIONS_KEY or (key.physical_keycode == KEY_ESCAPE and sections_open()):
			if sections_open():
				close_sections()
			elif key.physical_keycode == SECTIONS_KEY:
				open_sections()
			_handled()
			return
		if key.physical_keycode == SKIP_KEY:
			if key.shift_pressed:
				skip_section()
			elif step < steps.size():
				_next(bool((steps[step] as Dictionary).get("read", false)))  # a step to read: read
			_handled()
			return
	if step >= steps.size() or event.is_echo():
		return
	var s: Dictionary = steps[step]
	for a: StringName in s.get("on", []):
		if InputMap.has_action(a) and event.is_action_pressed(a):
			_next(true)
			return
	if key and key.pressed and (key.physical_keycode in s.get("raw", []) or key.keycode in s.get("raw", [])):
		_next(true)


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0 or step >= steps.size():
		return
	_tick = TICK_S
	var check := String((steps[step] as Dictionary).get("check", ""))
	if check != "" and bool(call(check)):
		_next(true)


## Marks the current step done (or skipped) and starts the next.
func _next(did: bool) -> void:
	if did:
		done += 1
		done_steps[step] = true
	step += 1
	_begin()


## The index in `steps` of the first step checked by `check` (-1 for none).
func index_of(check: String) -> int:
	for i in steps.size():
		if String((steps[i] as Dictionary).get("check", "")) == check:
			return i
	return -1


# --- Sections -----------------------------------------------------------------------------------

## The section step `i` is in ("" past the end).
func section_of(i: int) -> String:
	return String((steps[i] as Dictionary).get("section", "")) if i >= 0 and i < steps.size() else ""


## The sections this session runs, in order.
func sections() -> PackedStringArray:
	var out := PackedStringArray()
	for s: Dictionary in steps:
		if not String(s.section) in out:
			out.append(String(s.section))
	return out


## The index of the first step of `section` (-1 for none).
func first_of(section: String) -> int:
	for i in steps.size():
		if section_of(i) == section:
			return i
	return -1


## Shift + Page Down: past the rest of the current section, to the next one not ticked.
func skip_section() -> void:
	if step >= steps.size():
		return
	var here := section_of(step)
	while step < steps.size() and section_of(step) == here:
		step += 1
	_begin()


## Ticks `section` as "a teammate teaches it" (or not), for the rest of the game's run. Ticking
## the current one goes past it once the list closes.
func set_skipped(section: String, skip: bool) -> void:
	if skip:
		skip_sections[section] = true
	else:
		skip_sections.erase(section)
	var box := section_ticks.get(section) as CheckBox
	if box and box.button_pressed != skip:
		box.set_pressed_no_signal(skip)


## Start here: goes to the first step of `section` (taking its skip tick off) and closes the list.
func go_to(section: String) -> void:
	var at := first_of(section)
	if at < 0:
		return
	set_skipped(section, false)
	step = at
	close_sections()
	_begin()


func sections_open() -> bool:
	return _sections != null and _sections.visible


## The section list over the game (Page Up; open at the start): each section with its steps, a
## tick to skip it and Start here. The mouse is free while it's open; the game keeps running.
func open_sections() -> void:
	if _sections == null:
		_sections = CanvasLayer.new()
		_sections.name = "TutorialSections"
		_sections.layer = 19  # over the HUD, under the Escape menu
		add_child(_sections)
		_sections.add_child(UiKit.dim(0.45))
		_section_box = UiKit.screen(_sections, LIST_W)
	_sections.visible = true
	_fill_sections()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UiKit.focus_first(_section_box)


## Closes the list: past the current section if it was just ticked, the mouse back to the game.
func close_sections() -> void:
	if not sections_open():
		return
	_sections.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if step < steps.size() and skip_sections.has(section_of(step)):
		_begin()


func _fill_sections() -> void:
	for c in _section_box.get_children():
		_section_box.remove_child(c)
		c.queue_free()
	section_ticks.clear()
	_section_box.add_child(UiKit.title("Tutorial sections"))
	_section_box.add_child(UiKit.hint("Tick a section a teammate will teach you (or one you know): the tutorial skips it. Start here goes to a section now. Your ticks last until you quit the game."))
	var names := sections()
	for n in names.size():
		var section := names[n]
		var count := 0
		var did := 0
		for i in steps.size():
			if section_of(i) == section:
				count += 1
				did += 1 if done_steps.has(i) else 0
		var state := "now" if section_of(step) == section else ("done" if did == count else ("%d of %d done" % [did, count] if did > 0 else ""))
		var row := HFlowContainer.new()
		row.add_theme_constant_override(&"h_separation", UiKit.SPACE_M)
		row.add_theme_constant_override(&"v_separation", UiKit.SPACE_XS)
		var label := UiKit.heading("%d. %s (%d step%s%s)" % [n + 1, section, count, "" if count == 1 else "s", ", " + state if state != "" else ""])
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(label)
		var tick := CheckBox.new()
		tick.text = SKIP_TEXT
		tick.button_pressed = skip_sections.has(section)
		tick.toggled.connect(func(on: bool) -> void: set_skipped(section, on))
		section_ticks[section] = tick
		row.add_child(tick)
		row.add_child(UiKit.button("Start here", go_to.bind(section), "Go to %s now" % section))
		_section_box.add_child(row)
	_section_box.add_child(UiKit.button_row([UiKit.button("Back to the tutorial" if step > 0 else "Start the tutorial", close_sections)], true))
	_section_box.add_child(UiKit.key_hint("Page Up", "This list, any time"))


func _me() -> Soldier:
	return MapNodes.local_player(self)


func _moved() -> bool:
	var me := _me()
	if me == null:
		return false
	if not _start.is_finite():
		_start = me.global_position
	return Vector2(me.global_position.x - _start.x, me.global_position.z - _start.z).length() >= MOVE_M


## Host: one of `id` into the first of your containers with room (loose, so the step can have you
## put it on; Inventory.take would hang a pouch on the carrier itself). False if none had room.
static func _stow_loose(inv: Inventory, id: StringName) -> bool:
	for c: StringName in Inventory.CONTAINERS:
		if inv.containers.has(c) and inv.insert_entry(c, {"id": id, "count": 1}):
			return true
	return false


# --- Gear ---------------------------------------------------------------------------------------

## Host (setup): a carrier if you wear none, and a spare pouch, loose, of a kind with a free point
## on it.
func _give_pouch() -> void:
	var me := _me()
	_pouch = &""
	if me == null:
		return
	var inv := me.inventory
	if inv.slots.get(&"vest", &"") == &"" and ItemDB.has_item(CARRIER):
		inv.take(CARRIER)
	for id: StringName in POUCHES:
		if ItemDB.has_item(id) and inv.free_point_for(ItemDB.get_item(id)) != &"":
			_pouch = id
			break
	if _pouch == &"":
		return
	_pouches_on = _count_on(_pouch)
	if inv.count_of(_pouch) == 0:
		_stow_loose(inv, _pouch)


## How many `id` hang on what you wear.
func _count_on(id: StringName) -> int:
	var me := _me()
	var n := 0
	for p: Dictionary in me.inventory.attach_points() if me else []:
		if StringName(String(me.inventory.attachment(StringName(p.id)).get("id", ""))) == id:
			n += 1
	return n


func _pouch_on() -> bool:
	return _pouch != &"" and _count_on(_pouch) > _pouches_on


## Host (setup): a rifle if you have none, and a weapon light, loose (one already on the rifle comes
## off into your kit, to put back on).
func _give_light() -> void:
	var me := _me()
	if me == null or not ItemDB.has_item(LIGHT):
		return
	var inv := me.inventory
	if inv.slots.get(&"primary", &"") == &"" and ItemDB.has_item(RIFLE):
		inv.take(RIFLE)
	if _light_mounted():
		GunAttachments.server_remove(inv, &"primary", GunAttachments.SIDE)
	if inv.count_of(LIGHT) == 0:
		_stow_loose(inv, LIGHT)


func _light_mounted() -> bool:
	var me := _me()
	var id: StringName = me.inventory.slots.get(&"primary", &"") if me else &""
	return id != &"" and GunAttachments.mounted_id(ItemDB.get_item(id), me.inventory.state_of(&"primary"), GunAttachments.SIDE) == LIGHT


func _light_on() -> bool:
	var me := _me()
	var gun := me.active_weapon() if me else null
	return gun != null and GunAttachments.light_on(gun, me.inventory.state_of(me.active_slot))


# --- Squad orders -------------------------------------------------------------------------------

func _squad() -> Squad:
	var lvl := CompoundLevel.current(self)
	return lvl.squad_for(&"friendly") if lvl else null


## The squad's AI brains (up or not).
func _brains() -> Array[SquadAI]:
	var out: Array[SquadAI] = []
	var squad := _squad()
	for s in squad.members() if squad else []:
		var ai := SquadAI.of(s)
		if ai:
			out.append(ai)
	return out


## A squadmate was sent off (command menu Move there: Squad.Order.MOVE).
func _squad_sent() -> bool:
	return _brains().any(func(ai: SquadAI) -> bool: return ai.order == Squad.Order.MOVE)


## Host (setup): the bring-back step starts; it counts once they were off and are all back.
func _mark_squad() -> void:
	_was_away = false


func _squad_back() -> bool:
	var brains := _brains()
	var away := brains.any(func(ai: SquadAI) -> bool: return ai.order != Squad.Order.FOLLOW)
	if away:
		_was_away = true
	return _was_away and not away and not brains.is_empty()


## The squad's formation and spacing orders, as one string to compare.
func _formation_key() -> String:
	var squad := _squad()
	return "%s|%s|%s" % [squad.formation, squad.spacing, squad.team_orders] if squad else ""


## Host (setup): the formation as the step starts.
func _mark_formation() -> void:
	_formation_was = _formation_key()


func _formation_set() -> bool:
	return _squad() != null and _formation_key() != _formation_was


# --- Medical ------------------------------------------------------------------------------------

## Host (setup): a graze on the left forearm, unless something already bleeds.
func _graze_arm() -> void:
	_graze(&"forearm_l")


func _graze_leg() -> void:
	_graze(&"shin_r")


func _graze(part: StringName) -> void:
	var me := _me()
	_hurt = false
	if me == null or not me.vitals.is_up():
		return
	if not _bleeding(me):
		me.vitals.server_add_wound(part, "graze", GRAZE_RATE)
	_hurt = _bleeding(me)


## `s` has a bleed a bandage would stop (Vitals.care_needed).
static func _bleeding(s: Soldier) -> bool:
	return s.vitals.care_needed().any(func(t: Dictionary) -> bool: return String(t.kind) in BLEEDS)


func _self_treated() -> bool:
	var me := _me()
	return _hurt and me != null and not _bleeding(me)


## The command menu's Medic! or Treat me reached the host since the step began (Soldier.medic_asked_at).
func _medic_called() -> bool:
	var me := _me()
	return me != null and me.medic_asked_at >= _since


func _patched_up() -> bool:
	var me := _me()
	return _hurt and me != null and not _bleeding(me)


# --- Casualties ---------------------------------------------------------------------------------

## The person named `person_name` in the people layer (the villagers), or null.
func _person(person_name: String) -> Soldier:
	var people := PeopleLayer.find(self)
	for p in people.people() if people else []:
		if String(p.name) == person_name:
			return p
	return null


func casualty() -> Soldier:
	return _person(CASUALTY)


## Host (setup): the hurt villager, down just inside the gate with an artery open in his thigh
## (spawned the first time; hurt again if he's up and nothing of his bleeds).
func _fell_casualty() -> void:
	_held = false
	var lvl := CompoundLevel.current(self)
	var people := PeopleLayer.find(self)
	var c := casualty()
	if c == null and lvl and people:
		c = people.server_spawn_person({"name": CASUALTY, "kind": "civilian", "side": "neutral", "label": "Villager (Farid)",
			"pos": lvl.above_ground(CASUALTY_AT + Vector3.UP * 0.1), "rot_y": PI * 0.5})
		if c:
			people.server_set_state(c, {"order": "stop"})  # he stays put
	if c == null or c.vitals.is_dead():
		return
	if not _artery(c):
		c.vitals.server_add_wound(CASUALTY_PART, "arterial", CASUALTY_RATE)
	if c.vitals.is_up():
		c.vitals.server_damage(CASUALTY_TRAUMA)  # out cold: too much blood gone


## `c`'s arterial wounds (Vitals.wound_list).
static func _artery(c: Soldier) -> Array:
	return c.vitals.wound_list().filter(func(w: Dictionary) -> bool: return String(w.kind) == "arterial")


func _dragging() -> bool:
	var me := _me()
	var c := casualty()
	if me != null and c != null and me.carrying == c:
		_held = true
	return _held


func _let_go() -> bool:
	var me := _me()
	return _held and me != null and me.carrying == null


## Host (setup): a tourniquet to put on him, if you have none left.
func _top_up_tourniquet() -> void:
	var me := _me()
	if me and me.inventory.medical_count(&"tourniquet") == 0:
		me.inventory.take(&"tourniquet")


func _tourniquet_on() -> bool:
	var c := casualty()
	if c == null:
		return false
	var arteries := _artery(c)
	return not arteries.is_empty() and arteries.all(func(w: Dictionary) -> bool: return not w.bleeding)


# --- Tagging ------------------------------------------------------------------------------------

func _tagged() -> bool:
	var tags := EnemyTags.of(self)
	return tags != null and tags.tags.has(TARGET)


# --- Vehicles -----------------------------------------------------------------------------------

func _vehicle() -> Vehicle:
	var layer := VehicleLayer.of(self)
	return layer.find(VEHICLE_ID) if layer else null


func _seat_kind() -> StringName:
	var v := _vehicle()
	var me := _me()
	return v.seat_kind(v.seat_of(me)) if v and me and v.seat_of(me) >= 0 else &""


func _driving() -> bool:
	return _seat_kind() == Vehicle.DRIVER


## Host (setup): where the M-ATV stands as the drive step starts.
func _mark_vehicle() -> void:
	var v := _vehicle()
	_mark = v.global_position if v else Vector3.INF


func _driven() -> bool:
	var v := _vehicle()
	if v == null or not _driving():
		return false
	if not _mark.is_finite():
		_mark = v.global_position
	return Vector2(v.global_position.x - _mark.x, v.global_position.z - _mark.z).length() >= DRIVE_M


func _on_gun() -> bool:
	return _seat_kind() == Vehicle.GUNNER


func _squad_aboard() -> bool:
	var v := _vehicle()
	return v != null and v.occupants().any(func(s: Soldier) -> bool: return s.is_ai() and not Person.is_person(s))


func _all_out() -> bool:
	var v := _vehicle()
	return v != null and v.occupants().is_empty()


# --- Rebel support ------------------------------------------------------------------------------

## Host (RebelSupport.server_ask, outside a campaign): the villager's answer. Asking takes his
## job; in a campaign it would go on the contract board.
func server_locals_asked(_by: Soldier, _villager: Soldier) -> String:
	_asked = true
	return "\"Our clinic is out of bandages. Could you spare some?\" (In a campaign, a village's jobs go on your contract board.)"


## Host (RebelSupport.server_given, outside a campaign): `id` handed over.
func server_locals_given(_by: Soldier, _villager: Soldier, id: StringName) -> String:
	_given = true
	return "They thank you for the %s. In a campaign it raises the region's support for the company" % ItemDB.get_item(id).name


func _asked_for_work() -> bool:
	return _asked


func _gave_supplies() -> bool:
	return _given


func _lookouts_out() -> bool:
	var calls := RebelCalls.of(self)
	return calls != null and calls.lookouts_for(_me())


# --- Static guns --------------------------------------------------------------------------------

## Whether this build has static guns to set up (StaticWeapons' loads).
func _has_static_guns() -> bool:
	return STATIC_LOADS.all(func(id: StringName) -> bool: return ItemDB.has_item(id))


func _holding_load() -> bool:
	var me := _me()
	return me != null and me.inventory.hands in STATIC_LOADS


## The static guns standing within GUN_NEAR_M of the player.
func _guns_near() -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	var layer := VehicleLayer.of(self)
	var me := _me()
	if layer == null or me == null:
		return out
	for v in layer.vehicles():
		if v.kind == Vehicle.STATIC and v.model == STATIC_MODEL and not v.wrecked and v.global_position.distance_to(me.global_position) <= GUN_NEAR_M:
			out.append(v)
	return out


## Host (setup): the guns already standing, so only one set up now counts.
func _mark_guns() -> void:
	_guns_before = {}
	for v in _guns_near():
		_guns_before[v.get_instance_id()] = true


func _gun_up() -> bool:
	for v in _guns_near():
		if not _guns_before.has(v.get_instance_id()):
			_gun_id = v.get_instance_id()
			return true
	return false


## The gun the player set up while it stands, or null.
func _gun() -> Vehicle:
	var v := instance_from_id(_gun_id) as Vehicle if _gun_id != 0 else null
	return v if v and not v.is_queued_for_deletion() else null


## Host (setup): the gun to pack: the one set up, else the nearest standing.
func _mark_gun() -> void:
	if _gun() != null:
		return
	_gun_id = 0
	var me := _me()
	var best := INF
	for v in _guns_near():
		var d := v.global_position.distance_to(me.global_position)
		if d < best:
			best = d
			_gun_id = v.get_instance_id()


## The gun is gone back to its loads, one of them in the player's hands.
func _gun_packed() -> bool:
	return _gun_id != 0 and _gun() == null and _holding_load()
