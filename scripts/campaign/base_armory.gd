class_name BaseArmory
extends RefCounted
## The company stash (wave 4): every item the company owns that isn't on someone, kept in the
## campaign's "base" section as "stash", a list of entries {"id", "count", "state"?} like an
## inventory container's. At the base hub the stash lies in the armory as ordinary world
## items (WorldItem), laid out on its floor: players kit up by picking them up and put gear
## back by dropping it there, with the inventory they already have. Whatever lies anywhere in
## the hub when the stash is read back (BaseLevel.server_collect_stash) is the stash.

## Where the stash is laid out (metres, the hub's ground plane: x, z), row by row from the
## back wall, and how far apart. Past the armory's rows it carries on in the yard behind
## OVERFLOW_ORIGIN.
const AREA := Rect2(-15.4, -15.4, 8.8, 6.6)
const SPACING := Vector2(0.65, 0.75)
const DROP_HEIGHT := 0.35
const OVERFLOW_ORIGIN := Vector2(-15.0, -6.0)
const OVERFLOW_COLUMNS := 12


## Equal entries stack: same item and same state (plain items, full magazines...).
static func add(stash: Array, id: StringName, count := 1, state := {}) -> void:
	if count <= 0 or not ItemDB.has_item(id):
		return
	for entry: Dictionary in stash:
		if String(entry.id) == String(id) and _same_state(entry.get("state", {}), state):
			entry["count"] = int(entry.count) + count
			return
	var entry := {"id": String(id), "count": count}
	if not state.is_empty():
		entry["state"] = Roster.json_safe(state)
	stash.append(entry)


## Takes up to `count` of `id` out of the stash (stateless entries first). Returns how many.
static func remove(stash: Array, id: StringName, count := 1) -> int:
	var taken := 0
	var order := stash.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.get("state", {}).is_empty() and not b.get("state", {}).is_empty())
	for entry: Dictionary in order:
		if taken >= count:
			break
		if String(entry.id) != String(id):
			continue
		var n := mini(int(entry.count), count - taken)
		entry["count"] = int(entry.count) - n
		taken += n
		if int(entry.count) <= 0:
			stash.erase(entry)
	return taken


static func count_of(stash: Array, id: StringName) -> int:
	var n := 0
	for entry: Dictionary in stash:
		if String(entry.id) == String(id):
			n += int(entry.count)
	return n


## {item id (String): count} over the whole stash.
static func counts(stash: Array) -> Dictionary:
	var out := {}
	for entry: Dictionary in stash:
		out[String(entry.id)] = int(out.get(String(entry.id), 0)) + int(entry.count)
	return out


## The stash as world items describe it: [{"id", "count", "state"?}], stacked.
static func from_world_items(items: Array) -> Array:
	var stash: Array = []
	for node: Node in items:
		var item := node as WorldItem
		if item == null or item.is_queued_for_deletion():
			continue
		add(stash, item.item_id, item.count, item.state)
	return stash


## Where the i-th stash entry lies in the hub (on the armory floor, then the overflow rows).
static func slot_position(i: int) -> Vector3:
	var columns := maxi(floori(AREA.size.x / SPACING.x), 1)
	var rows := maxi(floori(AREA.size.y / SPACING.y), 1)
	if i < columns * rows:
		return Vector3(AREA.position.x + (i % columns + 0.5) * SPACING.x, DROP_HEIGHT, AREA.position.y + (i / columns + 0.5) * SPACING.y)
	var j := i - columns * rows
	return Vector3(OVERFLOW_ORIGIN.x + (j % OVERFLOW_COLUMNS) * SPACING.x, DROP_HEIGHT, OVERFLOW_ORIGIN.y + (j / OVERFLOW_COLUMNS) * SPACING.y)


static func _same_state(a: Dictionary, b: Dictionary) -> bool:
	return Roster.json_safe(a) == Roster.json_safe(b)
