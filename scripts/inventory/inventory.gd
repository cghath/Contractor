class_name Inventory
extends Node
## Volume-budget inventory: gear occupies body slots, and everything else has to fit in the
## litres that equipped gear provides (vest pouches, backpack, pockets). Only the host
## mutates it; every change is copied into `net_state`, which the owner's ServerSync
## replicates to all peers so everyone can see what you are wearing.

signal changed

const SLOTS: Array[StringName] = [&"primary", &"sidearm", &"helmet", &"vest", &"backpack", &"plate_front", &"plate_back", &"plate_left", &"plate_right"]
const PLATE_SLOTS: Array[StringName] = [&"plate_front", &"plate_back", &"plate_left", &"plate_right"]
## Containers, in the order auto-stow fills them.
const CONTAINERS: Array[StringName] = [&"vest", &"pockets", &"backpack"]
const POCKETS_L := 2.0

## Replicated snapshot. Always assign a fresh Dictionary so replication sees the change.
var net_state: Dictionary = {}:
	set(value):
		net_state = value
		_apply_state(value)

var slots: Dictionary = {}       # slot -> item id, or &""
var containers: Dictionary = {}  # container -> Array of {"id", "count"}
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


## Host only. Takes up to `count` units, equipping into a free slot first and then
## stowing the rest. Returns how many were taken (0 = nothing fit).
func take(id: StringName, count := 1) -> int:
	var item := ItemDB.get_item(id)
	if item == null or count <= 0:
		return 0
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
		taken = 1
	for container in CONTAINERS:
		if taken == count:
			break
		taken += _stow(container, item, count - taken)
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


## Host only. Removes the item in `slot`; returns it, or &"" if the slot can't be emptied
## (a vest still holding plates or pouch contents, a backpack that isn't empty).
func unequip(slot: StringName) -> StringName:
	var id: StringName = slots.get(slot, &"")
	if id == &"":
		return &""
	if slot == &"vest" and (PLATE_SLOTS.any(func(s: StringName) -> bool: return slots[s] != &"") or not containers[&"vest"].is_empty()):
		return &""
	if slot == &"backpack" and not containers[&"backpack"].is_empty():
		return &""
	slots[slot] = &""
	_commit()
	return id


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


func _stow(container: StringName, item: ItemData, want: int) -> int:
	var fit := want
	if item.volume_l > 0.0:
		fit = int(floor((capacity(container) - used(container)) / item.volume_l + 0.0001))
	var n := mini(fit, want)
	if n <= 0:
		return 0
	var list: Array = containers[container]
	var left := n
	for entry: Dictionary in list:
		if entry.id == item.id and entry.count < item.stack:
			var add := mini(item.stack - entry.count, left)
			entry.count += add
			left -= add
	while left > 0:
		var add := mini(item.stack, left)
		list.append({"id": item.id, "count": add})
		left -= add
	return n


func _commit() -> void:
	net_state = {"slots": slots.duplicate(), "containers": containers.duplicate(true), "hands": hands}


func _apply_state(state: Dictionary) -> void:
	slots.clear()
	for slot in SLOTS:
		slots[slot] = StringName(state.get("slots", {}).get(slot, &""))
	containers.clear()
	for container in CONTAINERS:
		containers[container] = state.get("containers", {}).get(container, []).duplicate(true)
	hands = StringName(state.get("hands", &""))
	changed.emit()
