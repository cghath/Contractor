class_name Suppressors
extends RefCounted
## A suppressor as an attachment (Captain, 2026-10-16, alongside the weapon-model rework): an
## item (type "attachment", tagged "suppressor") that mounts on a threaded weapon's muzzle
## ("threaded" in its stats), the same way an optic mounts on a rail (Optics). Which one a gun
## carries is part of its item state, "suppressor" (an item id; "" for none), so it travels
## with the gun the same way an optic does. Mounted, Soldier._server_fire treats the shot as
## suppressed: the quieter "shot_suppressed" sound (or synth placeholder), a dimmer tracer, and
## a much shorter alert radius (Alert.server_noise) — no separate sound-suppression system
## needed, the engine already had one for a static "suppressed" stat, just never wired to an
## attachment. VoxelArt shows it as a can stacked on the muzzle (_with_suppressor), generic
## over every rifle silhouette.

const TYPE := "attachment"
const STATE_KEY := "suppressor"
## The mounted can's condition (survival wear: WeaponCondition.can_wear), 0-100 (absent = 100). Off
## the gun, the can's own state keeps it as "condition" (Wear.KEY).
const CAN_KEY := "can_cond"


static func is_suppressor(item: ItemData) -> bool:
	return item != null and item.type == TYPE and "suppressor" in item.tags


## True if `weapon` takes a suppressor (a threaded muzzle).
static func has_muzzle(weapon: ItemData) -> bool:
	return weapon != null and weapon.type == "weapon" and bool(weapon.stats.get("threaded", false))


## The id of the suppressor mounted on `weapon` with item state `state`, or &"" for none.
static func mounted_id(weapon: ItemData, state: Dictionary) -> StringName:
	if not has_muzzle(weapon):
		return &""
	var id := StringName(String(state.get(STATE_KEY, "")))
	return id if id != &"" and is_suppressor(ItemDB.get_item(id)) else &""


## The suppressor mounted on `weapon` with `state` (null: none).
static func mounted(weapon: ItemData, state: Dictionary) -> ItemData:
	var id := mounted_id(weapon, state)
	return ItemDB.get_item(id) if id != &"" else null


## `state` with `suppressor_id` mounted (&"" for none); `own`: the can's own state (its condition).
static func with_suppressor(state: Dictionary, suppressor_id: StringName, own := {}) -> Dictionary:
	var out := state.duplicate(true)
	out.erase(CAN_KEY)
	if String(suppressor_id) == "":
		out.erase(STATE_KEY)
	else:
		out[STATE_KEY] = String(suppressor_id)
		var c := float(own.get("condition", 100.0))
		if c < 99.5:
			out[CAN_KEY] = c
	return out


## The mounted can's own state off the gun ({} as new): its condition.
static func can_state(state: Dictionary) -> Dictionary:
	var c := float(state.get(CAN_KEY, 100.0))
	return {"condition": c} if c < 99.5 else {}


## Why the attachment entry at `container`/`index` can't go on the weapon in `slot`, or "".
static func mount_problem(inv: Inventory, container: StringName, index: int, slot: StringName) -> String:
	var list: Array = inv.containers.get(container, [])
	if index < 0 or index >= list.size() or not is_suppressor(ItemDB.get_item(StringName(list[index].id))):
		return "That's not a suppressor"
	var id: StringName = inv.slots.get(slot, &"")
	if id == &"" or not has_muzzle(ItemDB.get_item(id)):
		return "No threaded muzzle for a suppressor"
	return ""


## Host only. Mounts the suppressor entry at `container`/`index` on the weapon in `slot`; the
## one it had goes into your containers. Returns "" or why not.
static func server_mount(inv: Inventory, container: StringName, index: int, slot: StringName) -> String:
	var problem := mount_problem(inv, container, index, slot)
	if problem != "":
		return problem
	var old := mounted_id(ItemDB.get_item(inv.slots[slot]), inv.state_of(slot))
	var old_state := can_state(inv.state_of(slot))
	var entry := inv.remove_entry(container, index)
	if entry.is_empty():
		return "Can't do that"
	if old != &"" and not _stow(inv, old, container, old_state):
		inv.insert_entry(container, entry)  # no room for the old one: put the new one back
		return "No room for the %s" % ItemDB.get_item(old).name
	inv.set_slot_state(slot, with_suppressor(inv.state_of(slot), StringName(entry.id), entry.get("state", {})))
	return ""


## Host only. Takes the suppressor off the weapon in `slot` into the first container with room
## (`target` first if named). Returns "" or why not.
static func server_remove(inv: Inventory, slot: StringName, target: StringName = &"") -> String:
	var id: StringName = inv.slots.get(slot, &"")
	var weapon := ItemDB.get_item(id) if id != &"" else null
	var old := mounted_id(weapon, inv.state_of(slot)) if weapon else &""
	if old == &"":
		return "No suppressor on it"
	if not _stow(inv, old, target, can_state(inv.state_of(slot))):
		return "No room for the %s" % ItemDB.get_item(old).name
	inv.set_slot_state(slot, with_suppressor(inv.state_of(slot), &""))
	return ""


static func _stow(inv: Inventory, suppressor_id: StringName, first: StringName, state := {}) -> bool:
	var order: Array[StringName] = []
	if first != &"" and inv.containers.has(first):
		order.append(first)
	order.append_array(inv.search_containers())
	var entry := {"id": suppressor_id, "count": 1}
	if not state.is_empty():
		entry["state"] = state
	for c in order:
		if inv.insert_entry(c, entry):
			return true
	return false


## A short name for the suppressor on a gun, for readouts ("" with none or no muzzle for one).
static func label(weapon: ItemData, state: Dictionary) -> String:
	var on := mounted(weapon, state)
	return String(on.stats.get("short", on.name)) if on else ""


## A gun's mass_kg as it comes carries no suppressor; mounting one adds its mass_kg in full
## (Inventory.total_mass/entry_mass, the same way Optics.extra_mass adds an optic's).
static func extra_mass(weapon: ItemData, state: Dictionary) -> float:
	var on := mounted(weapon, state)
	return on.mass_kg if on else 0.0


## As extra_mass, in shop dollars (Prices.price_of).
static func extra_price(weapon: ItemData, state: Dictionary) -> int:
	var on := mounted_id(weapon, state)
	return Prices.price_of(on) if on != &"" else 0
