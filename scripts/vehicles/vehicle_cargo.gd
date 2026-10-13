class_name VehicleCargo
extends Inventory
## A vehicle's cargo hold (wave 5): the rolling stash. It is an Inventory (the same entries,
## item state and net_state replication), but with one container, HOLD, of the vehicle's
## litres, a mass limit on top, no body slots and no hands: a two-handed crate goes into the
## hold like anything else. The host changes it; net_state rides the vehicle's StateSync to
## every peer and late joiner, and the zone save keeps it. If the vehicle burns, its cargo goes
## with it (Vehicle).

## The hold (the backpack container underneath: the one Inventory saves and replicates).
const HOLD := &"backpack"

## Litres and kilograms it takes (data/vehicles.json cargo_l, cargo_kg).
var capacity_l := 1000.0
var max_kg := 1500.0


func _init(p_litres := 1000.0, p_kg := 1500.0) -> void:
	super._init()
	capacity_l = p_litres
	stows_loaded_packs = true
	max_kg = p_kg
	name = "Cargo"


func capacity(container: StringName) -> float:
	return capacity_l if container == HOLD else 0.0


## By free litres and by the mass limit.
func room_for(container: StringName, item: ItemData, state := {}) -> int:
	if container != HOLD or item == null:
		return 0
	var room := super.room_for(container, item, state)
	var each := Inventory.entry_mass({"id": item.id, "count": 1, "state": state})
	if each > 0.0:
		room = mini(room, maxi(int(floor((max_kg - total_mass()) / each + 0.0001)), 0))
	return room


## Host only. Stows up to `count` units in the hold (never equips or carries in hands).
## Returns how many went in.
func take(id: StringName, count := 1, state := {}) -> int:
	var item := ItemDB.get_item(id)
	if item == null or count <= 0:
		return 0
	if not state.is_empty() and not Inventory._state_stacks(item):
		count = 1
	var n := _stow(HOLD, item, count, state)
	if n > 0:
		_commit()
	return n


func entries() -> Array:
	return containers.get(HOLD, [])


func used_litres() -> float:
	return used(HOLD)


## Host only. Everything out of the hold (it burned); returns what was there.
func clear_all() -> Array[Dictionary]:
	return strip()


## Rounds the hold has for a mounted gun fed by `feed` (belts count their rounds, loose rounds one each).
func feed_rounds(feed: StringName) -> int:
	var total := 0
	var item := ItemDB.get_item(feed)
	if item == null:
		return 0
	for entry: Dictionary in entries():
		if entry.id == feed:
			total += (int(entry.get("state", {}).get("rounds", item.magazine_rounds())) if item.magazine_rounds() > 0 else 1) * int(entry.count)
	return total


## Host only. Takes one round for a mounted gun from a belt (or one loose round) of `feed`.
## False when there's none left.
func take_feed(feed: StringName) -> bool:
	var item := ItemDB.get_item(feed)
	if item == null:
		return false
	var list := entries()
	for i in list.size():
		var entry: Dictionary = list[i]
		if entry.id != feed:
			continue
		if item.magazine_rounds() <= 0:
			remove_entry(HOLD, i, 1)
			return true
		var rounds := int(entry.get("state", {}).get("rounds", item.magazine_rounds()))
		if rounds <= 0:
			continue
		var belt := remove_entry(HOLD, i, 1)
		belt["state"] = {"rounds": rounds - 1}
		_append(HOLD, item, 1, belt.state)
		_commit()
		return true
	return false
