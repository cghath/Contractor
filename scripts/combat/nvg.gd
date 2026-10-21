class_name Nvg
extends RefCounted
## Night vision goggles (wave 7, S2): helmet-mounted gear by generation. An NVG is an item
## (its stats' "nvg_gen") that mounts on a worn helmet; what's mounted lives in the helmet's
## own item state, "nvg": {"id", "lowered", "battery_h"}, so it travels with the helmet
## wherever its state goes (dropped, looted, stashed, saved with the zone) and replicates to
## every peer with the inventory, like an optic on a gun (Optics). Stowed, an NVG keeps its
## charge in its entry's state ({"battery_h"}; missing means full).
##
## Flip it down or up with the NVG key (Controls "nvg_toggle"; Soldier._server_toggle_nvg). With
## none mounted, the key mounts the first NVG you carry and lowers it. Lowered, the battery
## drains in real hours of use (the stats' "battery_h", Proposed); flat, the goggles show
## nothing. The wearer's own view through them is NvgView (green, grain, the tube's narrower
## field of view: the stats' "fov_deg").
##
## Sight (for S1's day and night): restores() is the share of the darkness penalty to spotting
## that the viewer's lowered, powered NVG gives back. At integration, spotting does
## `dark *= 1.0 - Nvg.restores(viewer)`.
##
## Proposed numbers (items.json): gen 1 restores 0.6, 40 deg, 6 h; gen 2 0.8, 45 deg, 10 h;
## gen 3 0.9, 50 deg (binocular), 14 h. Prices 3000 / 5500 / 9000 (prices.json).

const STATE_KEY := "nvg"
const HELMET := &"helmet"
## Host: lowered time is charged to the battery in steps this long (one inventory commit each),
## and at once when the battery would run out sooner.
const DRAIN_STEP_S := 10.0


static func is_nvg(item: ItemData) -> bool:
	return item != null and item.stats.has("nvg_gen")


## The NVG mounted on `inv`'s helmet: {"id", "lowered", "battery_h"}, or {} (none, or no helmet).
static func mounted_state(inv: Inventory) -> Dictionary:
	if inv == null or inv.slots.get(HELMET, &"") == &"":
		return {}
	return inv.state_of(HELMET).get(STATE_KEY, {})


## The NVG item mounted on `inv`'s helmet, or null.
static func mounted(inv: Inventory) -> ItemData:
	var s := mounted_state(inv)
	return ItemDB.get_item(StringName(String(s.id))) if not s.is_empty() else null


## Full charge of `item` (hours of lowered use).
static func capacity_h(item: ItemData) -> float:
	return float(item.stats.get("battery_h", 0.0)) if item else 0.0


## Charge left (hours) in an NVG with state `state` (a mounted one's, or a stowed entry's).
static func battery_of(item: ItemData, state: Dictionary) -> float:
	return float(state.get("battery_h", capacity_h(item)))


## 0..1 charge of the mounted NVG (0 with none).
static func battery_fraction(inv: Inventory) -> float:
	var item := mounted(inv)
	var cap := capacity_h(item)
	return clampf(battery_of(item, mounted_state(inv)) / cap, 0.0, 1.0) if cap > 0.0 else 0.0


static func _inv_of(viewer: Node) -> Inventory:
	if viewer == null or not is_instance_valid(viewer):
		return null
	return viewer.get(&"inventory") as Inventory


## Whether `viewer`'s NVG is flipped down (powered or not).
static func is_lowered(viewer: Node) -> bool:
	return bool(mounted_state(_inv_of(viewer)).get("lowered", false))


## Whether `viewer` sees through NVGs right now: lowered, with charge left.
static func is_on(viewer: Node) -> bool:
	var inv := _inv_of(viewer)
	var s := mounted_state(inv)
	return bool(s.get("lowered", false)) and battery_of(mounted(inv), s) > 0.0


## 0..1: the share of the darkness penalty to sight that `viewer`'s lowered, powered NVG gives
## back (its stats' "restores", by generation; Proposed). 0 raised, flat or with none.
static func restores(viewer: Node) -> float:
	if not is_on(viewer):
		return 0.0
	return clampf(float(mounted(_inv_of(viewer)).stats.get("restores", 0.0)), 0.0, 1.0)


## The tube's field of view (degrees) of `viewer`'s NVG (0 when it's not on).
static func fov_of(viewer: Node) -> float:
	return float(mounted(_inv_of(viewer)).stats.get("fov_deg", 40.0)) if is_on(viewer) else 0.0


## The helmet state `state` with `nvg` mounted ({} takes it off).
static func with_nvg(state: Dictionary, nvg: Dictionary) -> Dictionary:
	var out := state.duplicate(true)
	if nvg.is_empty():
		out.erase(STATE_KEY)
	else:
		out[STATE_KEY] = nvg.duplicate(true)
	return out


## Why the entry at `container`/`index` can't mount on the helmet, or "".
static func mount_problem(inv: Inventory, container: StringName, index: int) -> String:
	var list: Array = inv.containers.get(container, [])
	if index < 0 or index >= list.size() or not is_nvg(ItemDB.get_item(StringName(list[index].id))):
		return "That's not an NVG"
	if inv.slots.get(HELMET, &"") == &"":
		return "Put on a helmet first"
	return ""


## Host only. Mounts the NVG entry at `container`/`index` on the helmet, raised; the one that
## was on it goes where the new one came from (or the first container with room). "" or why not.
static func server_mount(inv: Inventory, container: StringName, index: int, lowered := false) -> String:
	var problem := mount_problem(inv, container, index)
	if problem != "":
		return problem
	var old := mounted_state(inv)
	var entry := inv.remove_entry(container, index)
	if entry.is_empty():
		return "Can't do that"
	if not old.is_empty() and not _stow(inv, old, container):
		inv.insert_entry(container, entry)  # no room for the old one: put the new one back
		return "No room for the %s" % ItemDB.get_item(StringName(String(old.id))).name
	var item := ItemDB.get_item(StringName(entry.id))
	var nvg := {"id": String(item.id), "lowered": lowered, "battery_h": battery_of(item, entry.get("state", {}))}
	inv.set_slot_state(HELMET, with_nvg(inv.state_of(HELMET), nvg))
	return ""


## Host only. Takes the NVG off the helmet into the first container with room (`target` first
## if named), its charge kept. "" or why not.
static func server_remove(inv: Inventory, target: StringName = &"") -> String:
	var old := mounted_state(inv)
	if old.is_empty():
		return "No NVG on the helmet"
	if not _stow(inv, old, target):
		return "No room for the %s" % ItemDB.get_item(StringName(String(old.id))).name
	inv.set_slot_state(HELMET, with_nvg(inv.state_of(HELMET), {}))
	return ""


## The first NVG carried in `inv`'s containers: [container, index], or [].
static func first_carried(inv: Inventory) -> Array:
	for c in inv.search_containers():
		var list: Array = inv.containers.get(c, [])
		for i in list.size():
			if is_nvg(ItemDB.get_item(StringName(list[i].id))):
				return [c, i]
	return []


## Host only. Flips the mounted NVG down (`lowered`) or up. "" or why not.
static func server_set_lowered(inv: Inventory, lowered: bool) -> String:
	var s := mounted_state(inv)
	if s.is_empty():
		return "No NVG on the helmet"
	s = s.duplicate(true)
	s["lowered"] = lowered
	inv.set_slot_state(HELMET, with_nvg(inv.state_of(HELMET), s))
	return ""


## Host only. Charges `seconds` of lowered use to the mounted NVG's battery (nothing when it's
## raised or flat). True if that emptied it.
static func server_drain(inv: Inventory, seconds: float) -> bool:
	var s := mounted_state(inv)
	if s.is_empty() or not bool(s.get("lowered", false)) or seconds <= 0.0:
		return false
	var left := battery_of(mounted(inv), s)
	if left <= 0.0:
		return false
	s = s.duplicate(true)
	s["battery_h"] = maxf(left - seconds / 3600.0, 0.0)
	inv.set_slot_state(HELMET, with_nvg(inv.state_of(HELMET), s))
	return float(s.battery_h) <= 0.0


## Seconds of lowered use left in the mounted NVG (0 with none).
static func seconds_left(inv: Inventory) -> float:
	var s := mounted_state(inv)
	return battery_of(mounted(inv), s) * 3600.0 if not s.is_empty() else 0.0


## A short readout for the HUD ("NVG 87%"), "" with none mounted.
static func label(inv: Inventory) -> String:
	if mounted_state(inv).is_empty():
		return ""
	return "NVG %d%%" % roundi(battery_fraction(inv) * 100.0)


static func _stow(inv: Inventory, nvg: Dictionary, first: StringName) -> bool:
	var item := ItemDB.get_item(StringName(String(nvg.id)))
	var state := {}
	if battery_of(item, nvg) < capacity_h(item):
		state["battery_h"] = battery_of(item, nvg)
	var order: Array[StringName] = []
	if first != &"" and inv.containers.has(first):
		order.append(first)
	order.append_array(inv.search_containers())
	for c in order:
		if inv.insert_entry(c, {"id": item.id, "count": 1, "state": state}):
			return true
	return false


## Host only. A fresh battery (a consumable: Consumables): the NVG on the helmet back to full,
## else the flattest NVG carried. "" or why not ("No NVG needs a battery").
static func server_recharge(inv: Inventory) -> String:
	var s := mounted_state(inv)
	var item := mounted(inv)
	if not s.is_empty() and battery_of(item, s) < capacity_h(item) - 0.0001:
		s = s.duplicate(true)
		s["battery_h"] = capacity_h(item)
		inv.set_slot_state(HELMET, with_nvg(inv.state_of(HELMET), s))
		return ""
	var best := []
	var lowest := INF
	for c in inv.search_containers():
		var list: Array = inv.containers.get(c, [])
		for i in list.size():
			var it := ItemDB.get_item(StringName(list[i].id))
			if is_nvg(it):
				var share := battery_of(it, list[i].get("state", {})) / maxf(capacity_h(it), 0.0001)
				if share < 1.0 - 0.0001 and share < lowest:
					lowest = share
					best = [c, i]
	if best.is_empty():
		return "No NVG needs a battery"
	var entry := inv.remove_entry(best[0], best[1])
	var state: Dictionary = (entry.get("state", {}) as Dictionary).duplicate(true)
	state.erase("battery_h")  # missing means full
	entry["state"] = state
	inv.insert_entry(best[0], entry)
	return ""
