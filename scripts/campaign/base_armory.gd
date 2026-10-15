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
## The armory floor's row bands, back wall first: [name, rows]. Each category of item lies in
## its own band (band_of), left to right; what doesn't fit goes on to the overflow rows.
const BANDS: Array = [["weapons", 1], ["armor", 1], ["gear", 1], ["ammo", 1], ["medical", 2], ["grenades", 1], ["other", 1]]


## Equal entries stack: same item and same state (plain items, magazines holding the same
## rounds). As in Inventory._append, an item in its default state (an undamaged plate or
## helmet, a full weapon) counts as plain. Any other item with state (a carrier with its MOLLE
## pouches and what's in them, a detached pouch with its contents, a damaged plate) keeps its
## own entry, so it lies as its own item and comes back exactly as it went in.
static func add(stash: Array, id: StringName, count := 1, state := {}) -> void:
	if count <= 0 or not ItemDB.has_item(id):
		return
	var item := ItemDB.get_item(id)
	if not state.is_empty() and item.type != "ammo" and _same_state(state, item.default_state()):
		state = {}
	var stacks := state.is_empty() or item.type == "ammo"  # as Inventory._state_stacks
	for entry: Dictionary in stash:
		if stacks and String(entry.id) == String(id) and _same_state(entry.get("state", {}), state):
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


## {item id (String): count} of what's on and in the stash's items rather than lying loose:
## pouches on carriers and their contents, a detached pouch's contents (Roster.count_state).
static func contents_counts(stash: Array) -> Dictionary:
	var out := {}
	for entry: Dictionary in stash:
		Roster.count_state(entry.get("state", {}), int(entry.count), out)
	return out


## The state of a `carrier` set up the way every role's kit wears it: the base kit's MOLLE
## pouches (Roles.kit with no role: the mag pouches, the IFAK pouch, the tourniquet holder) on
## their points, empty. JSON-safe, for a stash entry. {} if it isn't a carrier with points.
static func kitted_carrier_state(carrier: StringName) -> Dictionary:
	var inv := Inventory.new()
	inv.take(carrier)
	if inv.slots[&"vest"] == carrier:
		for pair: Array in Roles.kit(&""):
			if Inventory.is_attachable(ItemDB.get_item(StringName(pair[0]))):
				inv.take(StringName(pair[0]), int(pair[1]))
	var state: Dictionary = Roster.json_safe(inv.state_of(&"vest"))
	inv.free()
	return state


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


## The band an item belongs in: weapons (and optics), armour (plates, helmets, carriers), gear
## (packs, pouches, rigs), ammo (mags and rounds), medical, grenades (throwables), other.
static func band_of(id: StringName) -> int:
	var group := Loadouts.group_of(ItemDB.get_item(id) if ItemDB.has_item(id) else null)
	var name: String = {"optics": "weapons", "packs": "gear", "pouches": "gear"}.get(group, group)
	for b in BANDS.size():
		if BANDS[b][0] == name:
			return b
	return BANDS.size() - 1


static func columns() -> int:
	return maxi(floori(AREA.size.x / SPACING.x), 1)


static func grid_slots() -> int:
	return columns() * maxi(floori(AREA.size.y / SPACING.y), 1)


## The slot index (slot_position) of the k-th place of `band`, or -1 past the band's rows (the
## overflow rows take it from there).
static func band_slot(band: int, k: int) -> int:
	var first := 0
	for b in band:
		first += int(BANDS[b][1])
	if k < int(BANDS[band][1]) * columns():
		return first * columns() + k
	return -1


## Slot index of every stash entry, in stash order: grouped by band, each band sorted by item
## id (then stash order), overflowing into the overflow rows. Deterministic.
static func layout(stash: Array) -> Array:
	var order: Array = range(stash.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var ba := band_of(StringName(String(stash[a].id)))
		var bb := band_of(StringName(String(stash[b].id)))
		if ba != bb:
			return ba < bb
		var ia := String(stash[a].id)
		var ib := String(stash[b].id)
		return ia < ib if ia != ib else a < b)
	var out: Array = []
	out.resize(stash.size())
	var used := {}
	var overflow := grid_slots()
	for idx: int in order:
		var band := band_of(StringName(String(stash[idx].id)))
		var k: int = used.get(band, 0)
		used[band] = k + 1
		var slot := band_slot(band, k)
		if slot < 0:
			slot = overflow
			overflow += 1
		out[idx] = slot
	return out


## The slot a floor position is on (the grid cell it is in, or the nearest overflow place), or -1.
static func slot_at(p: Vector3) -> int:
	var cols := columns()
	var cx := floori((p.x - AREA.position.x) / SPACING.x)
	var cz := floori((p.z - AREA.position.y) / SPACING.y)
	if cx >= 0 and cx < cols and cz >= 0 and cz < grid_slots() / cols:
		return cz * cols + cx
	var ox := roundi((p.x - OVERFLOW_ORIGIN.x) / SPACING.x)
	var oz := roundi((p.z - OVERFLOW_ORIGIN.y) / SPACING.y)
	if ox >= 0 and ox < OVERFLOW_COLUMNS and oz >= 0 and oz < 40:
		return grid_slots() + oz * OVERFLOW_COLUMNS + ox
	return -1


## The first free slot for `id` (not in `occupied`, {slot: true}): its band's, else the first
## free overflow slot.
static func free_slot(id: StringName, occupied: Dictionary) -> int:
	var band := band_of(id)
	var k := 0
	while band_slot(band, k) >= 0:
		if not occupied.has(band_slot(band, k)):
			return band_slot(band, k)
		k += 1
	var j := grid_slots()
	while occupied.has(j):
		j += 1
	return j


static func _same_state(a: Dictionary, b: Dictionary) -> bool:
	return Roster.json_safe(a) == Roster.json_safe(b)
