class_name Roles
extends RefCounted
## Squad roles and the 8-slot squad layout, loaded once from res://data/roles.json.
##
## The squad is two fire teams of four (A and B), each with one medic. Each slot has a
## default role; a player takes the slot of the role they picked, and AI fills the rest
## with their slot's role and kit. When a player's role has no free slot left (say two
## players both pick marksman), they take a free non-medic slot, which becomes their role
## while they hold it. Medic slots are never handed to a non-medic, so every fire team
## keeps its medic.

const PATH := "res://data/roles.json"
const TEAM_LEADER := &"team_leader"
const MEDIC := &"medic"
const AUTORIFLEMAN := &"autorifleman"
const GRENADIER := &"grenadier"
const MARKSMAN := &"marksman"
const RIFLEMAN := &"rifleman"
## Fire team names, by index (Soldier.fire_team).
const TEAMS: Array[String] = ["A", "B"]
## Which slots a player whose role has no free slot takes first: the least specialised.
const CONVERT_ORDER: Array[StringName] = [RIFLEMAN, GRENADIER, AUTORIFLEMAN, MARKSMAN, TEAM_LEADER]

## The role this machine's player picked in the main menu (sent to the host on join).
static var local_choice: StringName = TEAM_LEADER

static var _data := {}


## Every role id, in the order the menu lists them.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: String in _roles():
		out.append(StringName(id))
	return out


static func has(role: StringName) -> bool:
	return _roles().has(String(role))


## "Team Leader", "Medic", ... ("" for no role).
static func display_name(role: StringName) -> String:
	return String(_roles().get(String(role), {}).get("name", ""))


## "TL", "MED", ...
static func short_name(role: StringName) -> String:
	return String(_roles().get(String(role), {}).get("short", ""))


## What stands in for a weapon the item list doesn't have yet ("" if nothing is missing).
static func weapon_note(role: StringName) -> String:
	return String(_roles().get(String(role), {}).get("weapon_note", ""))


## The role's starting kit, base kit first, as [item id, count] pairs.
static func kit(role: StringName) -> Array:
	var out: Array = []
	for pair: Array in _load().get("base_kit", []):
		out.append([StringName(pair[0]), int(pair[1])])
	for pair: Array in _roles().get(String(role), {}).get("kit", []):
		out.append([StringName(pair[0]), int(pair[1])])
	return out


## Gives `inventory` the role's kit. Host only.
static func apply_kit(inventory: Inventory, role: StringName) -> void:
	for pair: Array in kit(role):
		inventory.take(pair[0], pair[1])


## The squad's slots in order: [{"role": StringName, "team": int}], fire team A first.
static func layout() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var teams: Array = _load().get("fire_teams", [])
	for team in teams.size():
		for role: String in teams[team]:
			out.append({"role": StringName(role), "team": team})
	return out


static func slot_count() -> int:
	return layout().size()


## Battle-buddy partner of a slot: slots pair up in order within each team (0+1, 2+3, ...).
static func buddy_slot(slot: int) -> int:
	return slot ^ 1


## Assigns players to slots. `choices` are the players' roles in priority order (host
## first); `current` is each player's slot so far (-1 for none) and `current_roles` the role
## they play in it now. A player keeps their slot when it is their pick's slot, or when they
## hold a converted non-medic slot and their pick hasn't changed, so other players joining,
## leaving or switching roles never move them. Returns {"slots": Array[int] (one per
## player), "roles": Array[StringName] (one per slot, after any conversions)}.
static func assign(choices: Array, current: Array = [], current_roles: Array = []) -> Dictionary:
	var slots := layout()
	var roles: Array[StringName] = []
	for s: Dictionary in slots:
		roles.append(s.role)
	var taken: Array[bool] = []
	taken.resize(slots.size())
	taken.fill(false)
	var result: Array[int] = []
	result.resize(choices.size())
	result.fill(-1)
	var wants: Array[StringName] = []
	for c: Variant in choices:
		wants.append(StringName(c) if has(StringName(c)) else TEAM_LEADER)
	# Players keep the slot they already hold when it is their role's slot, or a converted
	# non-medic slot they still play the same role in. A medic slot is kept only by a medic.
	for i in wants.size():
		var held: int = current[i] if i < current.size() else -1
		if held < 0 or held >= slots.size() or taken[held]:
			continue
		var playing := StringName(current_roles[i]) if i < current_roles.size() else &""
		var converted_kept: bool = playing == wants[i] and wants[i] != MEDIC and slots[held].role != MEDIC
		if slots[held].role == wants[i] or converted_kept:
			result[i] = held
			taken[held] = true
			roles[held] = wants[i]
	# Then the first free slot with their role, on the team with fewer players.
	for i in wants.size():
		if result[i] >= 0:
			continue
		var best := -1
		for s in slots.size():
			if taken[s] or slots[s].role != wants[i]:
				continue
			if best < 0 or _players_on(result, slots, slots[s].team) < _players_on(result, slots, slots[best].team):
				best = s
		if best >= 0:
			result[i] = best
			taken[best] = true
	# No slot left for their role: a free non-medic slot takes it on.
	for i in wants.size():
		if result[i] >= 0:
			continue
		var best := -1
		for role in CONVERT_ORDER:
			for s in range(slots.size() - 1, -1, -1):
				if taken[s] or slots[s].role != role:
					continue
				if best < 0 or _players_on(result, slots, slots[s].team) < _players_on(result, slots, slots[best].team):
					best = s
			if best >= 0:
				break
		if best < 0:
			best = taken.find(false)  # only medic slots left (more players than slots allow)
		if best < 0:
			continue
		result[i] = best
		taken[best] = true
		roles[best] = wants[i]
	return {"slots": result, "roles": roles}


static func _players_on(result: Array[int], slots: Array[Dictionary], team: int) -> int:
	var n := 0
	for s in result:
		if s >= 0 and slots[s].team == team:
			n += 1
	return n


static func _roles() -> Dictionary:
	return _load().get("roles", {})


static func _load() -> Dictionary:
	if not _data.is_empty():
		return _data
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("Roles: cannot open %s" % PATH)
		return _data
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("roles"):
		push_error("Roles: %s is not a valid role file" % PATH)
		return _data
	_data = parsed
	return _data
