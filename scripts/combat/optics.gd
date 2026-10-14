class_name Optics
extends RefCounted
## Weapon optics as attachments (Captain, P0362): an optic is an item (type "optic") that
## mounts on a rifle's rail ("rail" in its stats). Which one a gun carries is part of the
## gun's own item state, "optic" (an item id; "" for none), so it travels with the gun
## wherever its state goes: dropped, picked up, looted from a body, scavenged, stashed at the
## base and saved, and replicated to every peer with the inventory. A gun whose state names no
## optic carries the one it comes with (its stats' "optic"); a gun with none uses its irons
## (back-up irons on a rifle). Swapping happens in the inventory (Mount on / Remove optic,
## Soldier._server_inventory_action): the optic that comes off goes into your containers.
## The AI's accuracy never depends on the optic (Soldier.ai_spread_direction).

const TYPE := "optic"
const STATE_KEY := "optic"


static func is_optic(item: ItemData) -> bool:
	return item != null and item.type == TYPE


## True if `weapon` takes an optic (a rail).
static func has_rail(weapon: ItemData) -> bool:
	return weapon != null and weapon.type == "weapon" and bool(weapon.stats.get("rail", false))


## The id of the optic mounted on `weapon` with item state `state`, or &"" for none (irons).
static func mounted_id(weapon: ItemData, state: Dictionary) -> StringName:
	if not has_rail(weapon):
		return &""
	var id := StringName(String(state.get(STATE_KEY, weapon.stats.get("optic", ""))))
	return id if id != &"" and is_optic(ItemDB.get_item(id)) else &""


## The optic mounted on `weapon` with `state` (null: irons).
static func mounted(weapon: ItemData, state: Dictionary) -> ItemData:
	var id := mounted_id(weapon, state)
	return ItemDB.get_item(id) if id != &"" else null


## The optic on the weapon in `slot` of `inv` (null: none, or no weapon there).
static func on_slot(inv: Inventory, slot: StringName) -> ItemData:
	var id: StringName = inv.slots.get(slot, &"")
	return mounted(ItemDB.get_item(id), inv.state_of(slot)) if id != &"" else null


## `state` with `optic_id` mounted (&"" for none): the key is left out when it's the gun's
## own optic, so a gun as it came stays plain (it stacks and stashes like before).
static func with_optic(weapon: ItemData, state: Dictionary, optic_id: StringName) -> Dictionary:
	var out := state.duplicate(true)
	if String(optic_id) == String(weapon.stats.get("optic", "")):
		out.erase(STATE_KEY)
	else:
		out[STATE_KEY] = String(optic_id)
	return out


## Why the optic entry at `container`/`index` can't go on the weapon in `slot`, or "".
static func mount_problem(inv: Inventory, container: StringName, index: int, slot: StringName) -> String:
	var list: Array = inv.containers.get(container, [])
	if index < 0 or index >= list.size() or not is_optic(ItemDB.get_item(StringName(list[index].id))):
		return "That's not an optic"
	var id: StringName = inv.slots.get(slot, &"")
	if id == &"" or not has_rail(ItemDB.get_item(id)):
		return "No rail for an optic"
	return ""


## Host only. Mounts the optic entry at `container`/`index` on the weapon in `slot`; the
## optic that was on it goes where the new one came from (or the first container with room).
## Returns "" or why not.
static func server_mount(inv: Inventory, container: StringName, index: int, slot: StringName) -> String:
	var problem := mount_problem(inv, container, index, slot)
	if problem != "":
		return problem
	var weapon := ItemDB.get_item(inv.slots[slot])
	var old := mounted_id(weapon, inv.state_of(slot))
	var entry := inv.remove_entry(container, index)
	if entry.is_empty():
		return "Can't do that"
	if old != &"" and not _stow(inv, old, container):
		inv.insert_entry(container, entry)  # no room for the old one: put the new one back
		return "No room for the %s" % ItemDB.get_item(old).name
	inv.set_slot_state(slot, with_optic(weapon, inv.state_of(slot), StringName(entry.id)))
	return ""


## Host only. Takes the optic off the weapon in `slot` into the first container with room
## (`target` first if named). Returns "" or why not.
static func server_remove(inv: Inventory, slot: StringName, target: StringName = &"") -> String:
	var id: StringName = inv.slots.get(slot, &"")
	var weapon := ItemDB.get_item(id) if id != &"" else null
	var old := mounted_id(weapon, inv.state_of(slot)) if weapon else &""
	if old == &"":
		return "No optic on it"
	if not _stow(inv, old, target):
		return "No room for the %s" % ItemDB.get_item(old).name
	inv.set_slot_state(slot, with_optic(weapon, inv.state_of(slot), &""))
	return ""


static func _stow(inv: Inventory, optic_id: StringName, first: StringName) -> bool:
	var order: Array[StringName] = []
	if first != &"" and inv.containers.has(first):
		order.append(first)
	order.append_array(inv.search_containers())
	for c in order:
		if inv.insert_entry(c, {"id": optic_id, "count": 1}):
			return true
	return false


## The model kind (VoxelArt) of `optic`, or "" for irons.
static func art_of(optic: ItemData) -> String:
	return String(optic.stats.get("art", "dot")) if optic else ""


## A short name for the optic on a gun, for readouts ("irons" with none).
static func label(weapon: ItemData, state: Dictionary) -> String:
	if not has_rail(weapon):
		return ""
	var optic := mounted(weapon, state)
	return String(optic.stats.get("short", optic.name)) if optic else "irons"
