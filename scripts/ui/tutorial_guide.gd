class_name TutorialGuide
extends CanvasLayer
## The tutorial (Captain, 2026-10-14: "he needs a tutorial in the game at some point soon"; for
## cghath first): a solo session on the compound (Menu "Tutorial") with a panel down the left that
## walks a new player through the controls one step at a time, in sections (moving, shooting,
## gear and orders, medical, tagging, vehicles, rebel support, static guns). Each step says what
## to do and on which key (read from the live bindings, so a rebind shows), and ticks itself off
## when it's done: the basics on the action's press, the rest on what the game's state shows (moved,
## treated, a medic called, seated as driver, a squadmate aboard, a tag on the target, a villager's
## job taken, a gun set up then packed). Page Down skips a step.
##
## The session's setup (host, _set_up_session): the player gets a radio, grenades and medical kit
## to try things with; the compound's own hostile patrol goes and the squad holds fire, so nobody
## fights while the player learns; a stand-in enemy (TARGET, not moving or shooting) stands across
## the yard; an M-ATV is parked south of the gate, a villager (VILLAGER) waits by it, and an M2's
## two loads lie beside him (only once the game has static guns: StaticWeapons' loads). A step
## that needs more sets it up when it starts ("setup": a graze to treat). Outside a campaign the
## locals' requests answer here (server_locals_asked, server_locals_given; RebelSupport) and the
## rebels' Lookouts work without a region (RebelCalls). Local only: nothing here is sent anywhere.
## Proposed steps; text is the game's plain voice.

const NODE_NAME := "TutorialGuide"
const TARGET := "TutorialTarget"
const VILLAGER := "TutorialVillager"
const VEHICLE_ID := "tutorial_matv"
const VEHICLE_MODEL := "matv"
## The kit to try things with: item id -> how many, most needed first (a bare start has little
## room). Loose bandages first: with none loose a medic comes unasked (docs/audits/followups.md
## F-20), and the treat-yourself step wants you to do it.
const KIT := {&"pressure_bandage": 2, &"radio": 1, &"ifak": 1, &"tourniquet": 1, &"frag_grenade": 1, &"smoke_grenade": 1}
## A static gun's two loads, one a man (StaticWeapons.KITS "tripod_m2"), and the gun they make.
const STATIC_LOADS: Array[StringName] = [&"static_m2_gun", &"static_m3_tripod"]
const STATIC_MODEL := "tripod_m2"
const MOVE_M := 4.0
## Driving this far counts as driving.
const DRIVE_M := 10.0
## A gun set up this close to the player is his.
const GUN_NEAR_M := 15.0
## The tutorial's grazes: a slow bleed one pressure bandage stops (WoundModel.BANDAGED_KINDS).
const GRAZE_RATE := 0.05
const BLEEDS: Array[String] = ["graze", "muscle", "venous"]
## Where things stand on the compound (its own coordinates, on the ground): the target in the
## open yard west of the main building's door, in sight from the gate; the M-ATV south-west of the
## gate facing the open ground; the villager by the gate; the M2's loads beside him.
const TARGET_AT := Vector3(-6, 0.1, -1)
const VEHICLE_AT := Vector3(-14, 0, 32)
const VILLAGER_AT := Vector3(7, 0, 26)
const GUN_AT := Vector3(10, 0.3, 28)
const TRIPOD_AT := Vector3(11.2, 0.3, 28)
const SKIP_KEY := KEY_PAGEDOWN
const TICK_S := 0.2

## The steps in order: "section" (shown in the title), "text" (what to do; "{get_out}" says how
## to get out of a vehicle, as the settings have it), "keys" (actions whose keys are shown), and
## how it completes: "on" (any of these actions pressed), "raw" (any of these keycodes), or
## "check" (a method name on this node returning true once done). "setup": a method run on the
## host when the step starts. "needs": a method saying whether the step is in at all (steps).
const STEPS := [
	{"section": "Moving", "text": "Walk around: look with the mouse, move with", "keys": [&"move_forward", &"move_left", &"move_back", &"move_right"], "check": "_moved"},
	{"section": "Moving", "text": "Sprint: hold", "keys": [&"sprint"], "on": [&"sprint"]},
	{"section": "Moving", "text": "Crouch (a toggle)", "keys": [&"crouch"], "on": [&"crouch"]},
	{"section": "Moving", "text": "Go prone (a toggle; again to get up)", "keys": [&"prone"], "on": [&"prone"]},
	{"section": "Moving", "text": "Lean round a corner: hold", "keys": [&"lean_left", &"lean_right"], "on": [&"lean_left", &"lean_right"]},
	{"section": "Shooting", "text": "Aim down the sights: hold the right mouse button", "keys": [], "on": [&"aim"]},
	{"section": "Shooting", "text": "Fire: the left mouse button (the target across the yard won't shoot back)", "keys": [], "on": [&"fire"]},
	{"section": "Shooting", "text": "Reload", "keys": [&"reload"], "on": [&"reload"]},
	{"section": "Shooting", "text": "Switch the fire mode (single, burst, auto)", "keys": [&"fire_mode"], "on": [&"fire_mode"]},
	{"section": "Shooting", "text": "Rest the weapon on a wall or a sandbag in front of you", "keys": [&"mount"], "on": [&"mount"]},
	{"section": "Shooting", "text": "Take a grenade in hand (Fire throws, Aim lobs, the same key again puts it away)", "keys": [&"grenade"], "on": [&"grenade"]},
	{"section": "Gear and orders", "text": "Open your inventory: gear, pouches, the backpack", "keys": [&"inventory"], "on": [&"inventory"]},
	{"section": "Gear and orders", "text": "Hold Left Ctrl and look at a crate, a door or a person: the interaction menu", "keys": [], "on": [&"interact"]},
	{"section": "Gear and orders", "text": "The map: double-click to place a marker, right-click for orders", "keys": [&"map"], "on": [&"map"]},
	{"section": "Gear and orders", "text": "Squad orders: ` (backquote) opens the command menu for everyone, F1-F8 picks a squadmate", "keys": [], "raw": [KEY_QUOTELEFT, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8]},
	{"section": "Gear and orders", "text": "Night vision: flip it down or up (on a helmet with NVGs)", "keys": [&"nvg_toggle"], "on": [&"nvg_toggle"]},
	{"section": "Medical", "text": "The medical menu: treat yourself or a squadmate (Shift + it treats yourself fast)", "keys": [&"medical_menu"], "on": [&"medical_menu"]},
	{"section": "Medical", "setup": "_graze_arm", "check": "_self_treated", "keys": [&"medical_menu"],
		"text": "You have a graze on the arm. Treat it yourself: hold Left Ctrl, add Left Alt, pick your arm, Treat yourself, Pressure Bandage. The medical menu works too"},
	{"section": "Medical", "setup": "_graze_leg", "check": "_medic_called", "keys": [],
		"text": "Another graze, on the leg. This time call a medic: ` (backquote), 5 Status, 3 Medic!. Or pick one squadmate (F1-F8) and 5, 4 Treat me"},
	{"section": "Medical", "check": "_patched_up", "keys": [],
		"text": "Stay where you are: a squadmate comes over and patches you up"},
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
]

## The steps this session runs: STEPS whose "needs" holds (no static guns in this build: none of theirs).
var steps: Array = []
var step := 0
var done := 0
var _panel: PanelContainer
var _title: Label
var _text: Label
var _keys: Label
var _list: Label
var _start := Vector3.INF
var _tick := 0.0
var _since := 0.0             # host: Soldier._now() when the current step started
var _mark := Vector3.INF      # host: where the vehicle stood when the drive step started
var _hurt := false            # host: a step's graze went on
var _asked := false           # host: the villager was asked for work (server_locals_asked)
var _given := false           # host: he was given supplies (server_locals_given)
var _guns_before := {}        # host: static guns standing when the set-up step started (instance ids)
var _gun_id := 0              # host: the instance id of the gun the player set up (0: none)


## Opens the tutorial in the level `from` is in (host, after it's up): the guide, the kit and the
## target. Returns the guide.
static func start(from: Node) -> TutorialGuide:
	var lvl := CompoundLevel.current(from)
	if lvl == null:
		return null
	var old := lvl.get_node_or_null(NODE_NAME)
	if old:
		old.free()
	var g := TutorialGuide.new()
	g.name = NODE_NAME
	lvl.add_child(g)
	return g


## The tutorial running in the level `from` is in, or null (no tutorial: a real session).
static func of(from: Node) -> TutorialGuide:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	var g := lvl.get_node_or_null(NODE_NAME) as TutorialGuide if lvl else null
	return g if g and not g.is_queued_for_deletion() else null


func _ready() -> void:
	layer = 5
	steps = STEPS.filter(func(s: Dictionary) -> bool: return String(s.get("needs", "")) == "" or bool(call(String(s.needs))))
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UiKit.PANEL_BG
	style.set_corner_radius_all(6)
	style.set_content_margin_all(UiKit.SPACE_M)
	_panel.add_theme_stylebox_override(&"panel", style)
	_panel.position = Vector2(UiKit.EDGE, 180)
	_panel.custom_minimum_size = Vector2(380, 0)
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
	_set_up_session.call_deferred()
	_begin()


func _label(size: int, colour: Color) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(356, 0)
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", colour)
	return l


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
	if people and lvl.ai.get_node_or_null(NodePath(VILLAGER)) == null and people.get_node_or_null(NodePath(VILLAGER)) == null:
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
		_text.text = "That's the basics. Esc and Main menu to leave; host the campaign from there to start a company. The shooting range at the base and the vehicle range (Test zones) are good places to practise."
		_keys.text = ""
		_list.text = ""
		return
	var s: Dictionary = steps[step]
	_title.text = "Tutorial %d of %d: %s" % [step + 1, steps.size(), String(s.get("section", ""))]
	_text.text = step_text(s)
	_keys.text = keys_text(s.get("keys", []))
	_list.text = "Page Down skips a step."


## The current step starts: its setup on the host, then the panel.
func _begin() -> void:
	_since = Soldier._now()
	if step < steps.size() and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var setup := String((steps[step] as Dictionary).get("setup", ""))
		if setup != "":
			call(setup)
	_show()


## Every peer, this player only: a step's action pressed.
func _input(event: InputEvent) -> void:
	if step >= steps.size() or event.is_echo():
		return
	var key := event as InputEventKey
	if key and key.pressed and key.physical_keycode == SKIP_KEY:
		_next(false)
		return
	var s: Dictionary = steps[step]
	for a: StringName in s.get("on", []):
		if InputMap.has_action(a) and event.is_action_pressed(a):
			_next(true)
			return
	if key and key.pressed and (key.physical_keycode in s.get("raw", []) or key.keycode in s.get("raw", [])):
		_next(true)


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
	step += 1
	_begin()


## The index in `steps` of the first step checked by `check` (-1 for none).
func index_of(check: String) -> int:
	for i in steps.size():
		if String((steps[i] as Dictionary).get("check", "")) == check:
			return i
	return -1


func _me() -> Soldier:
	return MapNodes.local_player(self)


func _moved() -> bool:
	var me := _me()
	if me == null:
		return false
	if not _start.is_finite():
		_start = me.global_position
	return Vector2(me.global_position.x - _start.x, me.global_position.z - _start.z).length() >= MOVE_M


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
