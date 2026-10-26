class_name Crafting
extends RefCounted
## Crafting essentials (docs/survival_rpg.md section 5; calls 43, 85; phase B first tier):
## recipes are data (data/survival_recipes.json: inputs, tool, station, time, line and level,
## output). Host-authoritative: server_craft checks the line's level (Rpg.gate), the station
## (hands; a fire = a dropped campfire kit or a lit chem light within FIRE_M, the stand-in until
## the building lane's fire pit; workbench tiers later), the tool and the inputs, then the hands
## are busy for the recipe's time (Soldier.server_busy) and at the end the inputs go, the output
## comes (at his feet if it won't fit) and the line earns its XP.

const PATH := "res://data/survival_recipes.json"
const FIRE_M := 3.0
## What counts as a fire to cook at (Proposed: a chem light as the stand-in heat source until
## the building lane's fire pit and stove exist).
const FIRE_ITEMS: Array[StringName] = [&"campfire", &"chemlight_green", &"chemlight_red", &"chemlight_blue"]

static var _recipes := {}


static func recipes() -> Dictionary:
	if _recipes.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var parsed: Variant = ModKit.overlay("survival_recipes", JSON.parse_string(f.get_as_text()))  # (mods: docs/fallen_modding.md)
			if parsed is Dictionary:
				_recipes = (parsed as Dictionary).get("recipes", {})
	return _recipes


static func recipe(id: String) -> Dictionary:
	return recipes().get(id, {})


## The stations `s` has at hand: "hands" always, "fire" with one within FIRE_M.
static func stations_of(s: Soldier) -> Array:
	var out := ["hands"]
	var level := CompoundLevel.current(s)
	if level and level.items:
		for node in level.items.get_children():
			var wi := node as WorldItem
			if wi and not wi.is_queued_for_deletion() and wi.item_id in FIRE_ITEMS and wi.global_position.distance_to(s.global_position) <= FIRE_M:
				out.append("fire")
				break
	out.append_array(Fieldwork.stations_near(s))  # a smoker, a drying rack (docs/survival_hands.md)
	return out


## Whether `s` carries something that serves as `tool` (a list of ids or "tag:x"; [] = none).
static func has_tool(s: Soldier, tool: Array) -> bool:
	if tool.is_empty():
		return true
	for e: Dictionary in Survival.kit_of(s.inventory):
		var item := ItemDB.get_item(StringName(e.id))
		if item == null:
			continue
		for want: String in tool:
			if (want.begins_with("tag:") and item.tags.has(want.trim_prefix("tag:"))) or want == String(e.id):
				return true
	return MeleeWeapons.blade_carried(s) and ("tag:knife" in tool or "tag:blade" in tool)


## "" if `s` could make `id` here and now, else why not.
static func problem(s: Soldier, id: String) -> String:
	var r := recipe(id)
	if r.is_empty():
		return "No such recipe"
	if not Rpg.gate(s, String(r.get("line", "")), int(r.get("level", 0))):
		return "Needs %s %d" % [String(r.line), int(r.level)]
	var station := String(r.get("station", "hands"))
	if not station in stations_of(s):
		return "Needs a %s" % station.replace("_", " ")
	if not has_tool(s, r.get("tool", [])):
		return "Needs a %s" % " or ".join(PackedStringArray((r.tool as Array).map(func(t: String) -> String: return t.trim_prefix("tag:"))))
	for input: Array in r.get("inputs", []):
		if s.inventory.count_of(StringName(input[0])) < int(input[1]):
			var item := ItemDB.get_item(StringName(input[0]))
			return "Needs %d %s" % [int(input[1]), item.name if item else String(input[0])]
	return ""


## Host: `s` makes recipe `id`: the checks, then RECIPE time_s with the hands busy, then the
## inputs used up, the output given and the line's XP. `instant` skips the wait (tests).
## Returns "" when it started, else why not (he's told).
static func server_craft(s: Soldier, id: String, instant := false) -> String:
	var why := problem(s, id)
	if why == "" and Soldier._now() < s._server_busy_until:
		why = "Busy"
	if why != "":
		Survival._tell(s, why)
		return why
	var r := recipe(id)
	var secs := float(r.get("time_s", 5.0))
	if instant or secs <= 0.0:
		_finish(s, id)
		return ""
	s.server_busy(secs, String(r.get("name", id)))
	s.get_tree().create_timer(secs, false).timeout.connect(func() -> void:
		if is_instance_valid(s) and s.vitals.is_up():
			_finish(s, id))
	return ""


## Host: the work done: the inputs checked again (he may have dropped them) and used up, the
## output to his kit (or his feet), the XP.
static func _finish(s: Soldier, id: String) -> bool:
	var r := recipe(id)
	for input: Array in r.get("inputs", []):
		if s.inventory.count_of(StringName(input[0])) < int(input[1]):
			Survival._tell(s, "Something's missing")
			return false
	for input: Array in r.get("inputs", []):
		for i in int(input[1]):
			s.inventory.remove_one(StringName(input[0]))
	var out: Array = r.get("output", [])
	var state: Dictionary = (r.get("output_state", {}) as Dictionary).duplicate(true)
	if bool(r.get("treat_water", false)):
		state = Needs.treat_water(state)  # boiled: clean water (Needs)
	state = Spoilage.made_state(StringName(out[0]), state)  # made now: fresh (docs/survival_hands.md)
	var made := s.inventory.take(StringName(out[0]), int(out[1]), state)
	if made < int(out[1]):
		var level := CompoundLevel.current(s)
		if level:
			level.server_spawn_dropped(StringName(out[0]), int(out[1]) - made, s.global_position + Vector3.UP * 0.4, state)
	Rpg.xp(s, String(r.get("line", "")), float(r.get("xp", 5.0)), int(r.get("level", 0)))
	Survival._tell(s, "Made: %s" % String(r.get("name", id)))
	return true
