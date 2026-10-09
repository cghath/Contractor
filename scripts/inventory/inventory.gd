class_name Inventory
extends Node
## Volume-budget inventory: gear occupies body slots, and everything else has to fit in the
## litres that equipped gear provides (vest pouches, backpack, pockets). Only the host
## mutates it; every change is copied into `net_state`, which the owner's ServerSync
## replicates to all peers so everyone can see what you are wearing.
##
## Items can carry state that travels with them: rounds in a weapon or magazine, chips in
## a plate or helmet (see ItemData.default_state). Equipped items keep it in `slot_state`;
## stowed entries carry an optional "state" key. Entries with state never stack.

signal changed

const SLOTS: Array[StringName] = [&"primary", &"sidearm", &"helmet", &"vest", &"backpack", &"plate_front", &"plate_back", &"plate_left", &"plate_right"]
const PLATE_SLOTS: Array[StringName] = [&"plate_front", &"plate_back", &"plate_left", &"plate_right"]
const WEAPON_SLOTS: Array[StringName] = [&"primary", &"sidearm"]
## Containers, in the order auto-stow fills them (and reloads search them).
const CONTAINERS: Array[StringName] = [&"vest", &"pockets", &"backpack"]
const POCKETS_L := 2.0

## Replicated snapshot. Always assign a fresh Dictionary so replication sees the change.
var net_state: Dictionary = {}:
	set(value):
		net_state = value
		_apply_state(value)

var slots: Dictionary = {}       # slot -> item id, or &""
var slot_state: Dictionary = {}  # slot -> Dictionary (empty if the item has no state)
var containers: Dictionary = {}  # container -> Array of {"id", "count", "state"?}
var hands: StringName = &""      # two-handed carry


func _init() -> void:
	_apply_state({})


func capacity(container: StringName) -> float:
	if container == &"pockets":
		return POCKETS_L
	var id: StringName = slots.get(container, &"")
	return ItemDB.get_item(id).capacity_l if id != &"" else 0.0


func used(container: StringName) -> float:
	var total := 0.0
	for entry: Dictionary in containers[container]:
		total += ItemDB.get_item(entry.id).volume_l * entry.count
	return total


func free_volume(container: StringName) -> float:
	return capacity(container) - used(container)


func total_mass() -> float:
	var total := 0.0
	for slot in SLOTS:
		if slots[slot] != &"":
			total += ItemDB.get_item(slots[slot]).mass_kg
	for container in CONTAINERS:
		for entry: Dictionary in containers[container]:
			total += ItemDB.get_item(entry.id).mass_kg * entry.count
	if hands != &"":
		total += ItemDB.get_item(hands).mass_kg
	return total


## Units of `id` stowed across all containers.
func count_of(id: StringName) -> int:
	var total := 0
	for container in CONTAINERS:
		for entry: Dictionary in containers[container]:
			if entry.id == id:
				total += entry.count
	return total


func state_of(slot: StringName) -> Dictionary:
	return slot_state.get(slot, {})


## Host only. Takes up to `count` units, equipping into a free slot first and then
## stowing the rest. An item with `state` is always a single unit. Returns how many were
## taken (0 = nothing fit).
func take(id: StringName, count := 1, state := {}) -> int:
	var item := ItemDB.get_item(id)
	if item == null or count <= 0:
		return 0
	if not state.is_empty():
		count = 1
	if item.two_handed:
		if hands != &"":
			return 0
		hands = id
		_commit()
		return 1
	var taken := 0
	var slot := _free_slot_for(item)
	if slot != &"":
		slots[slot] = id
		slot_state[slot] = state.duplicate(true) if not state.is_empty() else item.default_state()
		taken = 1
	for container in CONTAINERS:
		if taken == count:
			break
		taken += _stow(container, item, count - taken, state)
	if taken > 0:
		_commit()
	return taken


## Host only. Empties the hands; returns what was held.
func release_hands() -> StringName:
	var id := hands
	if id != &"":
		hands = &""
		_commit()
	return id


## Host only. Removes the item in `slot` and returns {"id", "state"}, or {} if the slot
## is empty or can't be emptied (a vest still holding plates or pouch contents, a
## backpack that isn't empty).
func unequip(slot: StringName) -> Dictionary:
	var id: StringName = slots.get(slot, &"")
	if id == &"":
		return {}
	if slot == &"vest" and (PLATE_SLOTS.any(func(s: StringName) -> bool: return slots[s] != &"") or not containers[&"vest"].is_empty()):
		return {}
	if slot == &"backpack" and not containers[&"backpack"].is_empty():
		return {}
	var removed := {"id": id, "state": slot_state.get(slot, {})}
	slots[slot] = &""
	slot_state.erase(slot)
	_commit()
	return removed


## Host only. Takes up to `count` units out of a container entry and returns them as an
## entry ({"id", "count", "state"?}), or {} if the index is invalid.
func remove_entry(container: StringName, index: int, count := 1) -> Dictionary:
	var list: Array = containers.get(container, [])
	if index < 0 or index >= list.size() or count <= 0:
		return {}
	var entry: Dictionary = list[index]
	var n := mini(count, entry.count)
	var removed := entry.duplicate(true)
	removed.count = n
	entry.count -= n
	if entry.count <= 0:
		list.remove_at(index)
	_commit()
	return removed


## Host only. Puts a whole entry into `container` if it fits. Returns false otherwise.
func insert_entry(container: StringName, entry: Dictionary) -> bool:
	var item := ItemDB.get_item(entry.id)
	if capacity(container) <= 0.0 or item.volume_l * entry.count > free_volume(container) + 0.0001:
		return false
	_append(container, item, entry.count, entry.get("state", {}))
	_commit()
	return true


## Host only. Moves one unit of a stowed item into its body slot. False if it has no free
## slot (or the carrier has no pocket for it).
func equip_entry(container: StringName, index: int) -> bool:
	var list: Array = containers.get(container, [])
	if index < 0 or index >= list.size():
		return false
	var item := ItemDB.get_item(list[index].id)
	var slot := _free_slot_for(item)
	if slot == &"":
		return false
	var entry := remove_entry(container, index)
	slots[slot] = item.id
	slot_state[slot] = entry.get("state", {}).duplicate(true) if entry.has("state") else item.default_state()
	_commit()
	return true


# --- Ammunition -------------------------------------------------------------------------

func rounds_in(slot: StringName) -> int:
	return int(state_of(slot).get("rounds", 0))


## Rounds carried in spare magazines for `ammo_id`.
func spare_rounds(ammo_id: StringName) -> int:
	var total := 0
	var full := ItemDB.get_item(ammo_id).magazine_rounds() if ItemDB.has_item(ammo_id) else 0
	for container in CONTAINERS:
		for entry: Dictionary in containers[container]:
			if entry.id == ammo_id:
				total += int(entry.get("state", {}).get("rounds", full)) * entry.count
	return total


## Host only. Fires one round from the weapon in `slot`. False if it's empty.
func consume_round(slot: StringName) -> bool:
	var rounds := rounds_in(slot)
	if slots.get(slot, &"") == &"" or rounds <= 0:
		return false
	slot_state[slot]["rounds"] = rounds - 1
	_commit()
	return true


## Host only. Loads the fullest compatible magazine carried into the weapon in `slot`. A
## partly used magazine goes back where the new one came from; an empty one is dropped.
## Returns the rounds now loaded, or -1 if there is nothing to reload with.
func reload(slot: StringName) -> int:
	var id: StringName = slots.get(slot, &"")
	if id == &"":
		return -1
	var ammo_id := StringName(ItemDB.get_item(id).stats.get("ammo", ""))
	if not ItemDB.has_item(ammo_id):
		return -1
	var full := ItemDB.get_item(ammo_id).magazine_rounds()
	var best_container: StringName = &""
	var best_index := -1
	var best_rounds := rounds_in(slot)  # only worth it if the new mag has more
	for container in CONTAINERS:
		var list: Array = containers[container]
		for i in list.size():
			if list[i].id == ammo_id:
				var r := int(list[i].get("state", {}).get("rounds", full))
				if r > best_rounds:
					best_container = container
					best_index = i
					best_rounds = r
	if best_index < 0:
		return -1
	var current := rounds_in(slot)
	remove_entry(best_container, best_index)
	if current > 0:
		containers[best_container].append({"id": ammo_id, "count": 1, "state": {"rounds": current}})
	slot_state[slot]["rounds"] = best_rounds
	_commit()
	return best_rounds


# --- Armor damage -----------------------------------------------------------------------

## Host only. Records a chip on the armor in `slot` (see VoxelArmor). The chip list lives
## in the item's state, so it travels with the plate or helmet when it is dropped.
func add_chip(slot: StringName, chip: Array) -> void:
	if slots.get(slot, &"") == &"":
		return
	var state: Dictionary = slot_state.get(slot, {})
	var chips: Array = state.get("chips", [])
	chips.append(chip)
	state["chips"] = chips
	slot_state[slot] = state
	_commit()


func chips_in(slot: StringName) -> Array:
	return state_of(slot).get("chips", [])


# --- Internals --------------------------------------------------------------------------

func _free_slot_for(item: ItemData) -> StringName:
	match item.slot:
		&"":
			return &""
		&"plate", &"side_plate":
			# Plates need a carrier, and only fit the pockets that carrier has.
			for slot: StringName in carrier_plate_slots():
				var is_side := slot == &"plate_left" or slot == &"plate_right"
				if slots[slot] == &"" and is_side == (item.slot == &"side_plate"):
					return slot
			return &""
		_:
			return item.slot if slots.get(item.slot, &"x") == &"" else &""


## Plate slots the worn carrier provides (none without a carrier).
func carrier_plate_slots() -> Array[StringName]:
	var result: Array[StringName] = []
	if slots[&"vest"] != &"":
		for slot: String in ItemDB.get_item(slots[&"vest"]).stats.get("plate_slots", []):
			result.append(StringName(slot))
	return result


func _stow(container: StringName, item: ItemData, want: int, state: Dictionary) -> int:
	var fit := want
	if item.volume_l > 0.0:
		fit = int(floor(free_volume(container) / item.volume_l + 0.0001))
	var n := mini(fit, want)
	if n > 0:
		_append(container, item, n, state)
	return n


func _append(container: StringName, item: ItemData, count: int, state: Dictionary) -> void:
	var list: Array = containers[container]
	# Stateful items (a part-used magazine, a damaged plate) keep their own entry.
	if not state.is_empty() and state != item.default_state():
		for i in count:
			list.append({"id": item.id, "count": 1, "state": state.duplicate(true)})
		return
	var left := count
	for entry: Dictionary in list:
		if entry.id == item.id and not entry.has("state") and entry.count < item.stack:
			var add := mini(item.stack - entry.count, left)
			entry.count += add
			left -= add
	while left > 0:
		var add := mini(item.stack, left)
		list.append({"id": item.id, "count": add})
		left -= add


func _commit() -> void:
	net_state = {
		"slots": slots.duplicate(),
		"slot_state": slot_state.duplicate(true),
		"containers": containers.duplicate(true),
		"hands": hands,
	}


func _apply_state(state: Dictionary) -> void:
	slots.clear()
	for slot in SLOTS:
		slots[slot] = StringName(state.get("slots", {}).get(slot, &""))
	slot_state = state.get("slot_state", {}).duplicate(true)
	containers.clear()
	for container in CONTAINERS:
		containers[container] = state.get("containers", {}).get(container, []).duplicate(true)
	hands = StringName(state.get("hands", &""))
	changed.emit()
