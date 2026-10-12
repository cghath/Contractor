class_name InteractionMenu
extends Control
## ACE3-style interaction menu, local to the player (design doc "ACE-style interaction").
##
## Hold Left Ctrl (`interact`) and look at something within REACH: action points appear on
## items, downed bodies, standing squadmates and people (civilians, HVTs, captives). Move
## the cursor onto one to open its radial menu of actions, and let go of Left Ctrl to perform
## the highlighted one; letting go over nothing cancels. Left Ctrl + Left Alt
## (`self_interact`) opens the same kind of menu on your own body and gear. While the menu
## is open the mouse moves a cursor, not the view.
##
## What each kind of target offers is data (ACTIONS) read by the pure actions_for, so later
## work (treatments) adds entries rather than code paths. Anything that changes shared state
## is one of the body's host-side requests (Soldier._server_*); checks only read replicated
## state and show it locally.

enum Mode { CLOSED, OBJECT, SELF }

## How far from your eyes an action point can be (proposed, about ACE's reach).
const REACH := 3.0
## Left Ctrl must be held this long before the object menu shows, so pressing Ctrl then Alt
## goes straight to self-interaction without flashing the object menu.
const OPEN_DELAY_S := 0.15
## Action points show only for things within this angle of where you look.
const VIEW_CONE_DEG := 40.0
## The cursor opens an action point's menu within this many pixels of it.
const POINT_HOVER_PX := 28.0
const RING_RADIUS_PX := 120.0
const ENTRY_SIZE := Vector2(180.0, 26.0)
const SUB_GAP_PX := 8.0
## Most stowed entries the Give item submenu lists.
const MAX_GIVE_ENTRIES := 12
## Most entries the Treat submenu lists (the most urgent first).
const MAX_TREAT_ENTRIES := 12
## Reads the SpO2 in Check condition and Check wounds while carried.
const OXIMETER := &"pulse_oximeter"
## Most entries a dead body's Loot submenu lists (what's worn first, then each container).
const MAX_LOOT_ENTRIES := 20
## Height of an action point above a body's origin: standing, and lying down.
const STANDING_POINT_Y := 1.3
const DOWNED_POINT_Y := 0.3

## Body interaction points (ACE3's medical rig; Captain, 2026-10-11). A body you can treat
## (a downed or standing squadmate, or yourself) gets a point per region, offering that
## region's treatments and a check of it, plus a general point at the waist (WAIST) with
## everything else (carry, drag, give, check condition). Other targets keep one point.
const WAIST := &"waist"
const REGIONS: Array[StringName] = [&"head", &"chest", &"arm_l", &"arm_r", &"leg_l", &"leg_r"]
## Body parts (BodyMap, plus Vitals.TORSO for whole-body treatments) in each region.
const REGION_PARTS := {
	&"head": [&"head", &"face", &"neck"], &"chest": [&"chest", &"abdomen", &"pelvis", &"torso"],
	&"arm_l": [&"upper_arm_l", &"forearm_l"], &"arm_r": [&"upper_arm_r", &"forearm_r"],
	&"leg_l": [&"thigh_l", &"shin_l"], &"leg_r": [&"thigh_r", &"shin_r"],
}
const REGION_NAMES := {&"head": "head", &"chest": "chest", &"arm_l": "left arm", &"arm_r": "right arm",
	&"leg_l": "left leg", &"leg_r": "right leg", &"waist": "waist"}
## The hitbox each region's point sits on (it follows the pose, standing or lying).
const REGION_ANCHORS := {&"head": &"head", &"chest": &"chest", &"arm_l": &"forearm_l", &"arm_r": &"forearm_r",
	&"leg_l": &"thigh_l", &"leg_r": &"thigh_r", &"waist": &"pelvis"}
## Self-interaction lays the points out like a body around the screen centre (your left on
## the left), in pixels.
const SELF_LAYOUT := {&"head": Vector2(0, -170), &"chest": Vector2(0, -95), &"arm_l": Vector2(-135, -60),
	&"arm_r": Vector2(135, -60), &"waist": Vector2(0, -10), &"leg_l": Vector2(-55, 110), &"leg_r": Vector2(55, 110)}

## Target kinds, the keys of ACTIONS.
const ITEM := &"item"
const DOWNED := &"downed"
const DEAD := &"dead"
const SQUADMATE := &"squadmate"
const SELF := &"self"
## A civilian, an HVT or a hostile who gave up, standing (people, wave 4: Person).
const PERSON := &"person"
## Anything else in the INTERACTABLES group (base terminals, wave 4): it lists its own
## actions through interaction_actions(actor) -> Array[Dictionary] ({"id", "label",
## "disabled", "call": a local Callable perform runs}) and may place its point with
## action_point().
const OBJECT := &"object"
const INTERACTABLES := &"interactables"

## Actions per target kind, in menu order. Keys:
## - id, label: what it is and what the menu shows (some labels get details, see _label).
## - needs: a condition (see _check) that hides the entry or greys it out with a reason.
## - request + with: the Soldier host-side request to send and its arguments: "target"
##   (the target's path), "none", "slot" (your active slot), "target_entry" (target path,
##   container, index; used by submenu entries), "treatment" (target path, item, part,
##   rushed), "target_part" (target path, part) and "target_loot" (target path, a slot or
##   container, the entry's index or -1 for a slot, and the item id the host checks).
## - show: a local readout instead of a request ("condition" or "wounds").
## - submenu: a list built at runtime: "stowed_items" and "body_items" (what's on a dead body,
##   like the inventory screen; entries take the parent's request) or "treatments" (entries
##   carry their own request: see treatments).
## - people: a people action (PeopleLayer.request: "cuff", "lead", "stop", "cover", "search")
##   on the target, instead of a Soldier request; its conditions are Person.MENU_NEEDS.
const ACTIONS := {
	ITEM: [
		{"id": &"pick_up", "label": "Pick up", "request": &"_server_interact", "with": &"target"},
	],
	DOWNED: [
		{"id": &"put_down", "label": "Put down", "needs": &"moving_body", "request": &"_server_release_body", "with": &"none"},
		{"id": &"treat", "label": "Treat", "needs": &"treatable", "submenu": &"treatments"},
		{"id": &"carry", "label": "Carry", "needs": &"can_move_body", "request": &"_server_carry_body", "with": &"target"},
		{"id": &"drag", "label": "Drag", "needs": &"can_move_body", "request": &"_server_drag_body", "with": &"target"},
		{"id": &"check_condition", "label": "Check condition", "show": &"condition"},
		{"id": &"cuff", "label": "Zip-cuff", "needs": &"cuffable", "people": &"cuff"},
		{"id": &"search", "label": "Search for intel", "needs": &"searchable", "people": &"search"},
	],
	DEAD: [
		{"id": &"put_down", "label": "Put down", "needs": &"moving_body", "request": &"_server_release_body", "with": &"none"},
		{"id": &"loot", "label": "Loot", "needs": &"has_gear", "submenu": &"body_items", "request": &"_server_loot_item", "with": &"target_loot"},
		{"id": &"loot_all", "label": "Loot all", "needs": &"has_gear", "request": &"_server_loot_body", "with": &"target"},
		{"id": &"carry", "label": "Carry", "needs": &"can_move_body", "request": &"_server_carry_body", "with": &"target"},
		{"id": &"drag", "label": "Drag", "needs": &"can_move_body", "request": &"_server_drag_body", "with": &"target"},
	],
	SQUADMATE: [
		{"id": &"give_item", "label": "Give item", "submenu": &"stowed_items", "request": &"_server_give_item", "with": &"target_entry"},
		{"id": &"treat", "label": "Treat", "needs": &"treatable", "submenu": &"treatments"},
		{"id": &"check_condition", "label": "Check wounds", "needs": &"wounded", "show": &"condition"},
	],
	PERSON: [
		{"id": &"cuff", "label": "Zip-cuff", "needs": &"cuffable", "people": &"cuff"},
		{"id": &"lead", "label": "Follow me", "needs": &"leadable", "people": &"lead"},
		{"id": &"stop", "label": "Stop", "needs": &"led", "people": &"stop"},
		{"id": &"cover", "label": "Get in cover", "needs": &"leadable", "people": &"cover"},
		{"id": &"search", "label": "Search for intel", "needs": &"searchable", "people": &"search"},
		{"id": &"carry", "label": "Carry", "needs": &"carriable_person", "request": &"_server_carry_body", "with": &"target"},
		{"id": &"treat", "label": "Treat", "needs": &"treatable", "submenu": &"treatments"},
		{"id": &"check_condition", "label": "Check wounds", "needs": &"wounded", "show": &"condition"},
	],
	SELF: [
		{"id": &"check_wounds", "label": "Check wounds", "show": &"wounds"},
		{"id": &"treat", "label": "Treat yourself", "needs": &"treatable", "submenu": &"treatments"},
		{"id": &"put_down", "label": "Put down", "needs": &"moving_body", "request": &"_server_release_body", "with": &"none"},
		{"id": &"drop_held", "label": "Drop held item", "needs": &"held_item", "request": &"_server_drop", "with": &"slot"},
		{"id": &"radio_contract", "label": "Radio for a contract", "needs": &"field_radio", "request": &"_server_radio_contract", "with": &"none"},
	],
}
## Wound kinds in words, for Check wounds.
const KIND_TEXT := {
	"arterial": "arterial bleed", "junctional": "junctional bleed", "internal": "internal bleeding",
	"venous": "venous bleed", "muscle": "muscle wound", "graze": "graze", "fracture": "broken bone",
	"chest": "open chest wound", "heart": "heart wound", "rib": "cracked rib",
}
const _HIDE := "-"

const COLOUR_BG := Color(0.05, 0.07, 0.05, 0.82)
const COLOUR_TEXT := Color(1, 1, 1)
const COLOUR_HIGHLIGHT := Color("ffd35a")
const COLOUR_DISABLED := Color(0.55, 0.55, 0.55)
const COLOUR_POINT := Color("c8d6a0")

var player: Soldier
var mode := Mode.CLOSED
## The virtual cursor, in screen pixels.
var cursor := Vector2.ZERO
## Action points on screen: {"target": Node, "screen": Vector2, "actions": Array}.
var points: Array[Dictionary] = []
## Set when update_keys reports the keys let go: the action to perform ({} for none).
var chosen: Dictionary = {}
var _open_target: Node        # whose actions are showing
var _open_region := &""       # and which of its points (a region, WAIST, or &"" for a single point)
var _expanded := -1           # the ring entry whose submenu is showing
var _held_s := -1.0           # how long Left Ctrl has been held (< 0: not held)


func _init(p_player: Soldier = null) -> void:
	player = p_player


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# --- What a target offers (pure) ---------------------------------------------------------

## The kind of target `target` is for `actor` (a key of ACTIONS), or &"" for nothing.
static func target_kind(actor: Soldier, target: Node) -> StringName:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		return &""
	if target == actor:
		return SELF
	if target is WorldItem:
		return ITEM
	if target.is_in_group(INTERACTABLES) and target.has_method(&"interaction_actions"):
		return OBJECT
	var vitals := target.get_node_or_null(^"Vitals") as Vitals
	if vitals == null:
		return &""
	if vitals.downed:
		return DOWNED
	if vitals.is_dead() and target is Soldier:
		return DEAD
	if target is Soldier and vitals.is_up() and Person.is_person(target):
		return PERSON
	if target is Soldier and vitals.is_up() and (target as Soldier).faction == actor.faction:
		return SQUADMATE
	return &""


## The actions `actor` can take on `target` right now, in menu order. Each is a copy of its
## ACTIONS entry plus "target", a final "label", "disabled" (a reason, or "") and, for a
## submenu, "items" (its entries, built the same way).
static func actions_for(actor: Soldier, target: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kind := target_kind(actor, target)
	if kind == &"":
		return out
	if kind == OBJECT:
		for def: Dictionary in target.call(&"interaction_actions", actor):
			var action := def.duplicate()
			action["target"] = target
			action["disabled"] = String(def.get("disabled", ""))
			out.append(action)
		return out
	for def: Dictionary in ACTIONS[kind]:
		var why := _check(def.get("needs", &""), actor, target)
		if why == _HIDE:
			continue
		var action := def.duplicate()
		action["target"] = target
		action["label"] = _label(def, actor, target)
		action["disabled"] = why
		if def.has("submenu"):
			action["items"] = _submenu(def, actor, target)
			if action.items.is_empty() and why == "":
				action["disabled"] = {&"stowed_items": "Nothing stowed to give", &"body_items": "Nothing left on them"}.get(def.submenu, "Nothing to treat")
		out.append(action)
	return out


## `target` gets body interaction points (a region point each, and the waist): a squadmate,
## down or up, yourself, or a civilian, HVT or captive (PERSON, down or up: the people
## actions, zip-cuff, lead, search, sit on the waist point). Enemies (a downed one's single
## point offers zip-cuff and search), the dead, dummies, items and the body you're carrying
## or dragging (its point offers Release / Put down first) keep a single point.
static func has_regions(actor: Soldier, target: Node) -> bool:
	if target is Soldier and target != actor and (target as Soldier).carried_by == actor:
		return false
	return target is Soldier and not _is_enemy(actor, target) and target_kind(actor, target) in [DOWNED, SQUADMATE, SELF, PERSON]


## What the waist point offers: actions_for without Treat (treatments sit on the regions).
static func general_actions(actor: Soldier, target: Node) -> Array[Dictionary]:
	return actions_for(actor, target).filter(func(a: Dictionary) -> bool: return a.id != &"treat")


## What a region point offers: a check of that region, then its treatments (entries as in
## treatments, each with its own request).
static func region_actions(actor: Soldier, target: Node, region: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"id": &"check_part", "label": "Check %s" % REGION_NAMES[region], "show": &"part",
		"target": target, "region": region, "disabled": ""}]
	out.append_array(treatments(actor, target, region))
	return out


## The region a body part (or Vitals.TORSO) belongs to.
static func region_of(part: StringName) -> StringName:
	for region: StringName in REGIONS:
		if part in REGION_PARTS[region]:
			return region
	return &"chest"


## What checking one region shows: its wounds and what's been done for them, tourniquets
## and a line there, the airway on the head, breathing and pulse on the chest.
static func part_report(target: Node, region: StringName, actor: Soldier = null) -> String:
	var vitals := Vitals.find_on(target)
	if vitals == null:
		return ""
	var lines := PackedStringArray()
	for wound in vitals.wound_list():
		if region_of(wound.part) == region:
			lines.append("%s: %s%s" % [part_name(wound.part), _kind_text(wound), _wound_status(wound)])
	var tourniquets := vitals.tourniquets()
	for part: StringName in tourniquets:
		if region_of(part) == region:
			lines.append("%s on the %s" % ["Two tourniquets" if int(tourniquets[part].count) > 1 else "Tourniquet", Vitals.part_name(part)])
	var line := vitals.access()
	if not line.is_empty() and region_of(line.part) == region:
		lines.append("IO line in" if line.kind == "io" else "IV %dG in the %s" % [int(line.gauge), Vitals.part_name(line.part)])
	if region == &"head":
		if vitals.has_npa():
			lines.append("NPA in")
		elif vitals.airway_blocked():
			lines.append("Airway blocked: needs an NPA")
	elif region == &"chest":
		for sign in vitals.signs(target == actor):
			if sign.contains("reath") or sign.contains("ulse") or sign.contains("Trachea") or sign.contains("Coughing"):
				lines.append(sign)
		if has_oximeter(actor) and target != actor:
			lines.append("Pulse oximeter: %s" % ("no reading" if vitals.in_cardiac_arrest() else "SpO2 %d%%, pulse %d" % [roundi(vitals.spo2()), roundi(vitals.heart_rate())]))
	if lines.is_empty():
		lines.append("Nothing found on the %s" % REGION_NAMES[region])
	return "%s, %s:\n%s" % [display_name(target), REGION_NAMES[region], "\n".join(lines)]


## "" if the condition is met, _HIDE to leave the entry out, or why it's greyed out.
static func _check(need: StringName, actor: Soldier, target: Node) -> String:
	match need:
		&"treatable":
			if _is_enemy(actor, target) or treatments(actor, target).is_empty():
				return _HIDE
			return ""
		&"wounded":
			var vitals := Vitals.find_on(target)
			return "" if vitals and (not vitals.wound_list().is_empty() or vitals.condition_text() != "OK") else _HIDE
		&"can_move_body":
			if not target is Soldier:
				return _HIDE  # dummies stay on their stands
			if actor.carry_mode != &"":
				return "You're already moving someone"
			return "" if actor.inventory.hands == &"" else "Your hands are full"
		&"moving_body":
			return "" if actor.carry_mode != &"" else _HIDE
		&"has_gear":
			return "" if target is Soldier and (target as Soldier).has_gear() else "Nothing left on them"
		&"held_item":
			return "" if actor.inventory.hands != &"" or actor.active_weapon() != null else _HIDE
		&"field_radio":  # your own field radio (not a looted enemy set), in a hot zone
			var lvl := CompoundLevel.current(actor)
			var def: Variant = lvl.get(&"def") if lvl else null
			if not (def is Dictionary and String(def.get("kind", "")) == "hot"):
				return _HIDE
			return "" if RadioChatter.carried(actor, "radio", "enemy_radio") > 0 else "You have no field radio"
	if need in Person.MENU_NEEDS:
		return Person.menu_check(need, actor, target)  # people (wave 4)
	return ""


static func _label(def: Dictionary, actor: Soldier, _target: Node) -> String:
	match def.id:
		&"put_down":
			return "Put down" if actor.carry_mode == Soldier.CARRY else "Release"
		&"drop_held":
			var id := actor.inventory.hands
			if id == &"" and actor.active_weapon() != null:
				id = actor.active_weapon().id
			return "Drop %s" % ItemDB.get_item(id).name if id != &"" else String(def.label)
	return String(def.label)


static func _submenu(def: Dictionary, actor: Soldier, target: Node) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	match def.submenu:
		&"stowed_items":
			for container in actor.inventory.search_containers():  # pouches too
				var list: Array = actor.inventory.containers[container]
				for i in list.size():
					if items.size() >= MAX_GIVE_ENTRIES:
						return items
					var entry: Dictionary = list[i]
					var item := ItemDB.get_item(entry.id)
					var detail := " (%d rds)" % int(entry.state.rounds) if entry.has("state") and entry.state.has("rounds") else ""
					items.append({"id": def.id, "label": item.name + detail, "request": def.request, "with": def.with,
						"target": target, "container": container, "index": i, "disabled": ""})
		&"treatments":
			items = treatments(actor, target)
		&"body_items":
			if target is Soldier:
				for entry in body_items(target as Soldier):
					entry.merge({"id": &"loot_item", "request": def.request, "with": def.with, "target": target})
					items.append(entry)
	return items


## What's on a dead body, as the Loot submenu lists it (like the inventory screen): what's
## worn ("Primary: M4A1 Carbine (30 rds)"), what's on the carrier's MOLLE ("Carrier: Double
## Mag Pouch"), then each container's entries, pouches first ("2x Mag pouch: 7.62 Magazine x2",
## "Vest: 5.56 Magazine x4"). Each is {"label", "where" (a slot, pouch container or
## container), "index" (-1 for a slot or an attachment), "item" (its id), "disabled"}: a
## carrier or pack still holding things is greyed out until it's empty (pouches can stay on
## the carrier; they go with it). Past MAX_LOOT_ENTRIES the last line counts the rest.
static func body_items(body: Soldier) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inv := body.inventory
	for slot in Inventory.SLOTS:
		var id: StringName = inv.slots[slot]
		if id == &"":
			continue
		var item := ItemDB.get_item(id)
		var full: bool = (slot == &"backpack" and not inv.containers[&"backpack"].is_empty()) \
			or (slot == &"vest" and (not inv.containers[&"vest"].is_empty() or Inventory.PLATE_SLOTS.any(func(s: StringName) -> bool: return inv.slots[s] != &"")))
		out.append({"label": "%s: %s%s" % [InventoryScreen.SLOT_NAMES.get(slot, String(slot)), item.name, _rounds_text(inv.state_of(slot))],
			"where": slot, "index": -1, "item": id, "disabled": "Take what's in it first" if full else ""})
	for p: Dictionary in inv.attach_points():
		var att := inv.attachment(StringName(p.id))
		if not att.is_empty():
			out.append({"label": "Carrier: %s" % ItemDB.get_item(StringName(att.id)).name,
				"where": Inventory.pouch_container(StringName(p.id)), "index": -1, "item": StringName(att.id), "disabled": ""})
	for container in inv.search_containers():  # pouches first
		var list: Array = inv.containers[container]
		var where_name := String(container).capitalize()
		if Inventory.is_pouch_container(container):
			var pouch := inv.pouch_item(container)
			where_name = "%s pouch" % String(pouch.stats.get("short", "")) if pouch else "Pouch"
		for i in list.size():
			var entry: Dictionary = list[i]
			var item := ItemDB.get_item(entry.id)
			var count := " x%d" % int(entry.count) if int(entry.count) > 1 else ""
			out.append({"label": "%s: %s%s%s" % [where_name, item.name, count, _rounds_text(entry.get("state", {}))],
				"where": container, "index": i, "item": entry.id, "disabled": ""})
	if out.size() > MAX_LOOT_ENTRIES:
		# Too many to list: the last line says how many more there are (take some, or Loot all).
		var more := out.size() - (MAX_LOOT_ENTRIES - 1)
		out = out.slice(0, MAX_LOOT_ENTRIES - 1)
		out.append({"label": "%d more..." % more, "where": &"", "index": -1, "item": &"", "disabled": "Take some first, or Loot all"})
	return out


static func _rounds_text(state: Dictionary) -> String:
	return " (%d rds)" % int(state.rounds) if state.has("rounds") else ""


## What `actor` can do for `target`'s wounds (the Treat submenu), most urgent first: each
## task on its care_needed() with the body part ("Tourniquet, left thigh"; a tourniquet also
## as a quicker rushed entry), then packing an arterial bleed under a tourniquet with gauze,
## and taking a tourniquet off once its wound is packed. Entries are greyed out with a
## reason when you don't carry the item (loose or in a kit). With a `region` (REGIONS), only
## what goes on that region's parts; an IV is then offered at each IV site in it (both
## forearms and both lower legs, not below a tourniquet), an IO on the chest.
static func treatments(actor: Soldier, target: Node, region := &"") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var vitals := Vitals.find_on(target)
	if vitals == null or vitals.is_dead():
		return out
	var here := func(part: StringName) -> bool: return region == &"" or region_of(part) == region
	for task in vitals.care_needed():
		if task.has("items"):  # a line, a bag, a seal or a clamp: one entry per kind you carry, or the usual pick greyed out
			if target == actor and Vitals.needs_other_hands(task.item):
				continue
			var carried := Vitals.task_items(task).filter(func(id: StringName) -> bool: return Vitals.has_item(actor.inventory, id))
			for id: StringName in (carried if not carried.is_empty() else [task.item]):
				var option := ItemDB.get_item(id)
				var sites: Array = [task.part]
				if id == WoundModel.IO_KIT:
					sites = [WoundModel.IO_PART]
				elif WoundModel.IV_GAUGES.has(id) and region != &"":
					sites = WoundModel.IV_SITES.filter(func(s: StringName) -> bool: return vitals.iv_site_ok(s))
				for part: StringName in sites:
					if here.call(part):
						var where := "sternum" if id == WoundModel.IO_KIT else Vitals.part_name(part)
						out.append(_treat_entry(actor, target, option, part, false, "%s, %s" % [option.name, where]))
			continue
		if not here.call(task.part):
			continue
		var item := ItemDB.get_item(task.item)
		out.append(_treat_entry(actor, target, item, task.part, false, "%s, %s" % [item.name, Vitals.part_name(task.part)]))
		if task.item == WoundModel.TOURNIQUET:
			out.append(_treat_entry(actor, target, item, task.part, true,
				"%s (rushed, %.1f s), %s" % [item.name, actor.treat_seconds(target, item, true), Vitals.part_name(task.part)]))
	var gauze := ItemDB.get_item(WoundModel.HEMOSTATIC_GAUZE)
	var packing := {}
	for w in vitals.wound_list():
		if w.kind == "arterial" and w.tourniquet and not w.treated and not packing.has(w.part) and here.call(w.part) \
				and vitals.treatment_problem(gauze.id, w.part) == "":
			packing[w.part] = true
			out.append(_treat_entry(actor, target, gauze, w.part, false, "%s (pack under tourniquet), %s" % [gauze.name, Vitals.part_name(w.part)]))
	var tourniquets := vitals.tourniquets()
	for part: StringName in tourniquets:
		if vitals.removal_problem(part) == "" and here.call(part):
			out.append({"id": &"remove_tourniquet", "label": "Remove tourniquet, %s" % Vitals.part_name(part),
				"request": &"_server_remove_tourniquet", "with": &"target_part", "target": target, "part": part, "disabled": ""})
	return out.slice(0, MAX_TREAT_ENTRIES)


static func _treat_entry(actor: Soldier, target: Node, item: ItemData, part: StringName, rushed: bool, label: String) -> Dictionary:
	var have := Vitals.has_item(actor.inventory, item.id)
	return {"id": &"treat_item", "label": label, "request": &"_server_treat", "with": &"treatment", "target": target,
		"item": item.id, "part": part, "rushed": rushed, "disabled": "" if have else "You have no %s" % item.name}


## Someone on another side who still counts as an enemy (civilians, HVTs and captives don't).
static func _is_enemy(actor: Soldier, target: Node) -> bool:
	return target is Soldier and (target as Soldier).faction != actor.faction and not Person.is_noncombatant(target)


# --- Doing it ------------------------------------------------------------------------------

## Performs `action` for `actor`: sends its host request, or reads out a check. Returns text
## to show the player ("" for none). An empty action, a submenu or a target that's gone does
## nothing.
static func perform(actor: Soldier, action: Dictionary) -> String:
	if action.is_empty() or action.has("items"):
		return ""
	if String(action.get("disabled", "")) != "":
		return action.disabled
	var target: Node = action.get("target")
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		return ""
	if action.has("call"):
		(action.call as Callable).call()  # an interactable's own local action (OBJECT)
		return ""
	match action.get("show", &""):
		&"condition":
			return condition_report(target, actor)
		&"wounds":
			return wound_report(actor.vitals, true, has_oximeter(actor))
		&"part":
			return part_report(target, action.region, actor)
	if action.has("people"):
		var layer := PeopleLayer.find(actor)
		if layer:
			layer.request.rpc_id(1, String(action.people), target.get_path())
		return ""
	var request: StringName = action.get("request", &"")
	if request == &"":
		return ""
	match action.get("with", &"none"):
		&"target":
			actor.rpc_id(1, request, target.get_path())
		&"slot":
			actor.rpc_id(1, request, actor.active_slot)
		&"target_entry":
			actor.rpc_id(1, request, target.get_path(), action.container, action.index)
		&"treatment":
			actor.rpc_id(1, request, target.get_path(), action.item, action.part, action.rushed)
		&"target_part":
			actor.rpc_id(1, request, target.get_path(), action.part)
		&"target_loot":
			actor.rpc_id(1, request, target.get_path(), action.where, action.index, action.item)
		_:
			actor.rpc_id(1, request)
	return ""


## "Alpha: Unconscious" plus what someone checking them can see, for Check condition. An
## `actor` carrying a pulse oximeter also reads the SpO2.
static func condition_report(target: Node, actor: Soldier = null) -> String:
	var vitals := target.get_node_or_null(^"Vitals") as Vitals
	if vitals == null:
		return ""
	var card := "" if vitals.triage() == Vitals.TRIAGE_NONE else " [%s]" % String(Vitals.TRIAGE_TEXT[vitals.triage()])
	return "%s: %s%s\n%s" % [display_name(target), vitals.condition_text(), card, wound_report(vitals, false, has_oximeter(actor))]


## Carries a pulse oximeter (loose or in a kit).
static func has_oximeter(actor: Soldier) -> bool:
	return actor != null and actor.inventory.medical_count(OXIMETER) > 0


## Plain signs first (Vitals.signs: "Unresponsive", "Breathing laboured", "Breathing fast",
## "Blue lips", "No breath sounds on the left", "Pinpoint pupils (morphine)"; on yourself,
## laboured or fast breathing and drowsiness), then one line per wound and what's been done
## for it ("Left thigh: arterial bleed, held by tourniquet, packed"), then the tourniquets and
## airway; or "No wounds found". No numbers: SpO2, blood and the morphine level stay hidden,
## except that with a pulse oximeter (`oximeter`) the first line reads the SpO2.
static func wound_report(vitals: Vitals, on_self := true, oximeter := false) -> String:
	var signs := vitals.signs(on_self)
	if oximeter:
		var reading := "no reading" if vitals.in_cardiac_arrest() or vitals.is_dead() \
			else "SpO2 %d%%, pulse %d" % [roundi(vitals.spo2()), roundi(vitals.heart_rate())]
		signs.insert(0, "Pulse oximeter: %s" % reading)
	var lines := PackedStringArray()
	for wound in vitals.wound_list():
		lines.append("%s: %s%s" % [part_name(wound.get("part", &"")), _kind_text(wound), _wound_status(wound)])
	var tourniquets := vitals.tourniquets()
	for part: StringName in tourniquets:
		var t: Dictionary = tourniquets[part]
		var rushed := int(t.count) == 1 and int(t.rushed) == 1  # a lone rushed one lets some through
		lines.append("%s on the %s%s" % ["Two tourniquets" if int(t.count) > 1 else "Tourniquet", Vitals.part_name(part),
			" (rushed: still bleeding)" if rushed else ""])
	if vitals.has_npa():
		lines.append("NPA in")
	elif vitals.airway_blocked():
		lines.append("Airway blocked: needs an NPA")
	if lines.is_empty():
		lines.append("No wounds found" if vitals.injury() <= 0.0 or not vitals.is_up() else "Hurt, no open wounds found")
	signs.append_array(lines)
	return "\n".join(signs)


## One wound_list() entry's kind in words (a lung that blast lung collapsed is no open wound).
static func _kind_text(wound: Dictionary) -> String:
	if wound.get("pneumo", false):
		return "collapsed lung"
	return KIND_TEXT.get(String(wound.get("kind", "")), "wound")


## What's been done for one wound_list() entry, and whether it still bleeds.
static func _wound_status(wound: Dictionary) -> String:
	var done := PackedStringArray()
	var kind := String(wound.get("kind", ""))
	if wound.get("pneumo", false):
		pass  # nothing to seal: the needle is its fix
	elif wound.get("clamped", false):
		done.append("clamped")
	elif wound.get("closed", false):
		done.append("closed by surgery")
	elif wound.get("packed", false):
		done.append("packed")
	elif wound.get("treated", false):
		done.append({"fracture": "splinted", "chest": "sealed", "rib": "morphine given"}.get(kind, "bandaged"))
	if wound.get("tension", false):
		done.append("tension pneumothorax")
	if wound.get("bleeding", false):
		done.append("bleeding (rushed tourniquet)" if wound.get("tourniquet", false) else "bleeding")
	elif wound.get("tourniquet", false) and not wound.get("treated", false) and float(wound.get("rate", 0.0)) > 0.0:
		done.append("held by tourniquet")
	return ", " + ", ".join(done) if not done.is_empty() else ""


## "upper_arm_l" -> "Left upper arm".
static func part_name(part: StringName) -> String:
	var words := Vitals.part_name(part)
	return words.substr(0, 1).to_upper() + words.substr(1)


static func display_name(target: Node) -> String:
	if target is Soldier:
		return (target as Soldier).display_name()
	if target is WorldItem:
		return ItemDB.get_item((target as WorldItem).item_id).name
	return String(target.name)


# --- Finding action points ---------------------------------------------------------------

## Action points `actor` can see through `camera`: everything within REACH, in front, in
## sight and with at least one action. A body with regions (has_regions) gets its waist point
## (WAIST: the general actions) and a point per region on its hitboxes ("region" says which);
## anything else one point (region &"").
static func collect_points(actor: Soldier, camera: Camera3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for point in _single_points(actor, camera):
		var node: Node3D = point.target
		if not has_regions(actor, node):
			out.append(point)
			continue
		var general := general_actions(actor, node)
		if not general.is_empty():
			out.append({"target": node, "region": WAIST, "screen": point.screen, "actions": general})
		for region in REGIONS:
			var at: Variant = part_anchor(node, REGION_ANCHORS[region])
			if at == null or camera.is_position_behind(at) or (at as Vector3).distance_to(camera.global_position) > REACH + 0.6:
				continue
			out.append({"target": node, "region": region, "screen": camera.unproject_position(at),
				"actions": region_actions(actor, node, region)})
	return out


## Where a body's hitbox for `part` is in the world (it follows the pose), or null if it has none.
static func part_anchor(node: Node, part: StringName) -> Variant:
	for child in node.get_children():
		var hitbox := child as Area3D
		if hitbox == null or hitbox.get_meta(&"body_part", &"") != part:
			continue
		for shape in hitbox.get_children():
			if shape is CollisionShape3D:
				return (shape as CollisionShape3D).global_position
		return hitbox.global_position
	return null


## One point per target (its action_point), as before body regions.
static func _single_points(actor: Soldier, camera: Camera3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var eye := camera.global_position
	var forward := -camera.global_basis.z
	var tree := actor.get_tree()
	var candidates: Array = tree.get_nodes_in_group(WorldItem.GROUP) + tree.get_nodes_in_group(&"combatants") \
		+ tree.get_nodes_in_group(INTERACTABLES)
	for node: Node in candidates:
		if node == actor or not node is Node3D or node.is_queued_for_deletion():
			continue
		var mover: Node = (node as Soldier).carried_by if node is Soldier else null
		if is_instance_valid(mover) and mover != actor:
			continue  # on someone else's shoulder or being dragged by them (yours: Release / Put down)
		var at := action_point(node as Node3D)
		var to := at - eye
		if to.length() > REACH or forward.angle_to(to) > deg_to_rad(VIEW_CONE_DEG) or camera.is_position_behind(at):
			continue
		if not _in_sight(actor, eye, at):
			continue
		var actions := actions_for(actor, node)
		if actions.is_empty():
			continue
		out.append({"target": node, "screen": camera.unproject_position(at), "actions": actions})
	return out


## Where `node`'s action point sits in the world: just above an item as it lies (a plate
## flat on the floor has its centre barely above it, so a point there could be out of sight).
static func action_point(node: Node3D) -> Vector3:
	if node is WorldItem:
		return (node as WorldItem).action_point()
	if node.has_method(&"action_point"):
		return node.call(&"action_point")
	var vitals := node.get_node_or_null(^"Vitals") as Vitals
	var lying := vitals != null and not vitals.is_up()
	return node.global_position + Vector3.UP * (DOWNED_POINT_Y if lying else STANDING_POINT_Y)


## No wall between the eye and the point.
static func _in_sight(actor: Soldier, eye: Vector3, at: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(eye, at, 1, [actor.get_rid()])
	return actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- The menu itself ---------------------------------------------------------------------

func is_open() -> bool:
	return mode != Mode.CLOSED


## Feeds the key state once a frame: `interact` is Left Ctrl held (and allowed), `self_held`
## Left Alt with it. Returns true on the frame the keys are let go with the menu open;
## `chosen` then holds the highlighted action ({} if the cursor was over nothing).
func update_keys(interact: bool, self_held: bool, delta: float) -> bool:
	if not interact:
		_held_s = -1.0
		if not is_open():
			return false
		chosen = release()
		return true
	_held_s = maxf(_held_s, 0.0) + delta
	if self_held and mode != Mode.SELF:
		open_self()
	elif mode == Mode.CLOSED and _held_s >= OPEN_DELAY_S:
		open_object()
	return false


## Opens the menu on the things around you; set_points fills in the action points.
func open_object() -> void:
	mode = Mode.OBJECT
	cursor = _centre()
	points = []
	_open_target = null
	_expanded = -1
	queue_redraw()


## Opens the menu on your own body and gear: the waist point (your general actions) is open,
## with a point per region laid out like a body around it (SELF_LAYOUT).
func open_self() -> void:
	mode = Mode.SELF
	_open_target = player
	_open_region = WAIST
	_expanded = -1
	refresh_self()
	cursor = _open_point().get("screen", _centre())


## Rebuilds the self points (what you carry and your wounds can change while it's open).
func refresh_self() -> void:
	var centre := _centre()
	points = [{"target": player, "region": WAIST, "screen": centre + SELF_LAYOUT[WAIST], "actions": general_actions(player, player)}]
	for region in REGIONS:
		points.append({"target": player, "region": region, "screen": centre + SELF_LAYOUT[region],
			"actions": region_actions(player, player, region)})
	queue_redraw()


## Replaces the action points (object mode, once a frame), keeping the open one if it's still there.
func set_points(new_points: Array[Dictionary]) -> void:
	points = new_points.duplicate()  # never share the caller's array
	if _open_point().is_empty():
		_open_target = null
		_expanded = -1
	_update_hover()
	queue_redraw()


func move_cursor(relative: Vector2) -> void:
	set_cursor(cursor + relative)


func set_cursor(pos: Vector2) -> void:
	var size := _screen_size()
	cursor = Vector2(clampf(pos.x, 0.0, size.x), clampf(pos.y, 0.0, size.y))
	_update_hover()
	queue_redraw()


## Closes the menu and returns the highlighted action ({} if none, or a submenu parent).
func release() -> Dictionary:
	var action := highlighted()
	close()
	return {} if action.has("items") else action


func close() -> void:
	mode = Mode.CLOSED
	points = []
	_open_target = null
	_expanded = -1
	queue_redraw()


## The action under the cursor: a submenu entry, a ring entry, or {} for nothing.
func highlighted() -> Dictionary:
	var point := _open_point()
	if point.is_empty():
		return {}
	var actions: Array = point.actions
	if _expanded >= 0 and _expanded < actions.size():
		var sub: Array = actions[_expanded].get("items", [])
		var sub_rects := _sub_rects(point, _expanded)
		for j in sub_rects.size():
			if sub_rects[j].has_point(cursor):
				return sub[j]
	var rects := _ring_rects(point)
	for i in rects.size():
		if rects[i].has_point(cursor):
			return actions[i]
	return {}


## Screen rects of the open point's actions, around it in a ring.
func entry_rects() -> Array[Rect2]:
	return _ring_rects(_open_point())


## Screen rects of a ring entry's submenu.
func submenu_rects(index: int) -> Array[Rect2]:
	return _sub_rects(_open_point(), index)


func _open_point() -> Dictionary:
	if _open_target == null:
		return {}
	for p in points:
		if p.target == _open_target and p.get("region", &"") == _open_region:
			return p
	return {}


func _update_hover() -> void:
	var point := _open_point()
	if not point.is_empty():
		var actions: Array = point.actions
		if _expanded >= 0 and _expanded < actions.size():
			for r in _sub_rects(point, _expanded):
				if r.has_point(cursor):
					return  # inside the open submenu
		var rects := _ring_rects(point)
		for i in rects.size():
			if rects[i].has_point(cursor):
				_expanded = i if actions[i].has("items") and not actions[i].items.is_empty() else -1
				return
	# Over an action point: open it (the nearest one wins).
	var best := {}
	var best_d := POINT_HOVER_PX
	for p in points:
		var screen: Vector2 = p.screen
		var d := screen.distance_to(cursor)
		if d <= best_d:
			best = p
			best_d = d
	if not best.is_empty() and (best.target != _open_target or best.get("region", &"") != _open_region):
		_open_target = best.target
		_open_region = best.get("region", &"")
		_expanded = -1


func _ring_rects(point: Dictionary) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if point.is_empty():
		return rects
	var n: int = point.actions.size()
	for i in n:
		var angle := -PI * 0.5 + TAU * i / n if n > 1 else 0.0
		var centre: Vector2 = point.screen + Vector2.from_angle(angle) * RING_RADIUS_PX
		rects.append(Rect2(centre - ENTRY_SIZE * 0.5, ENTRY_SIZE))
	return rects


func _sub_rects(point: Dictionary, index: int) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if point.is_empty() or index < 0 or index >= point.actions.size():
		return rects
	var sub: Array = point.actions[index].get("items", [])
	var parent := _ring_rects(point)[index]
	var screen: Vector2 = point.screen
	var right := parent.get_center().x >= screen.x
	var x := parent.end.x + SUB_GAP_PX if right else parent.position.x - SUB_GAP_PX - ENTRY_SIZE.x
	var top := parent.get_center().y - (ENTRY_SIZE.y + 2.0) * sub.size() * 0.5
	for j in sub.size():
		rects.append(Rect2(Vector2(x, top + (ENTRY_SIZE.y + 2.0) * j), ENTRY_SIZE))
	return rects


func _centre() -> Vector2:
	return _screen_size() * 0.5


func _screen_size() -> Vector2:
	return get_viewport_rect().size if is_inside_tree() else Vector2(1152, 648)


func _draw() -> void:
	if not is_open():
		return
	var font := get_theme_default_font()
	var font_size := 15
	var lit := highlighted()
	for p in points:
		var open: bool = p.target == _open_target and p.get("region", &"") == _open_region
		draw_circle(p.screen, 6.0 if open else 4.5, COLOUR_HIGHLIGHT if open else COLOUR_POINT)
		draw_arc(p.screen, 9.0, 0.0, TAU, 20, Color(0, 0, 0, 0.6), 1.5)
		var region: StringName = p.get("region", &"")
		if region != &"" and not open:  # name the body points so they read like ACE's
			draw_string(font, p.screen + Vector2(11, 5), REGION_NAMES[region].capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOUR_POINT)
	var point := _open_point()
	if not point.is_empty():
		var actions: Array = point.actions
		var rects := _ring_rects(point)
		for i in rects.size():
			_draw_entry(font, font_size, rects[i], actions[i], lit, i == _expanded)
			draw_line(point.screen, rects[i].get_center(), Color(1, 1, 1, 0.15), 1.0)
		if _expanded >= 0 and _expanded < actions.size():
			var sub: Array = actions[_expanded].get("items", [])
			var sub_rects := _sub_rects(point, _expanded)
			for j in sub_rects.size():
				_draw_entry(font, font_size, sub_rects[j], sub[j], lit, false)
	draw_circle(cursor, 3.0, Color.WHITE)
	draw_arc(cursor, 5.0, 0.0, TAU, 16, Color.BLACK, 1.0)


func _draw_entry(font: Font, font_size: int, rect: Rect2, action: Dictionary, lit: Dictionary, expanded: bool) -> void:
	var disabled := String(action.get("disabled", "")) != ""
	var on := action == lit or expanded
	draw_rect(rect, COLOUR_BG)
	if on:
		draw_rect(rect, COLOUR_HIGHLIGHT, false, 1.5)
	var colour := COLOUR_DISABLED if disabled else (COLOUR_HIGHLIGHT if on else COLOUR_TEXT)
	var text := String(action.label) + ("  >" if action.has("items") and not action.items.is_empty() else "")
	var baseline := rect.position + Vector2(0.0, (rect.size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, colour)
