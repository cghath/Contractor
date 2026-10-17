class_name Inventory
extends Node
## Volume-budget inventory: gear occupies body slots, and everything else has to fit in the
## litres that equipped gear provides (vest pouches, backpack, pockets). Only the host
## mutates it; every change is copied into `net_state`, which the owner's ServerSync
## replicates to all peers so everyone can see what you are wearing.
##
## Replication (playtest blocker B2): the whole snapshot (`net_gear`) goes out only when the
## gear really changes (an item put on, taken off, moved, added or removed). A round fired
## changes only a count, so it goes out in `net_ammo` (a few ints: the rounds loaded in each
## weapon slot), not as another whole snapshot. Both carry the snapshot's revision, so a peer
## puts the counts only on the snapshot they belong to, and a late joiner gets both (spawn).
##
## Items can carry state that travels with them: rounds in a weapon or magazine, chips in
## a plate or helmet, a ceramic plate's cracks and integrity (see ItemData.default_state and
## ArmorRules). Equipped items keep it in `slot_state`; stowed entries carry an optional
## "state" key. Entries with state don't stack, except magazines holding the same rounds.
## Plates only go into a carrier that takes them (see fit_problem).
##
## Ammunition: magazines keep their rounds in state and go back in the pouch when they come
## out of the weapon, empty or not; loose rounds of the same calibre load them (load_rounds).
##
## MOLLE: a carrier has typed attach points (its stats' "molle"); pouches, a knife and the
## like attach to points of a type they fit (their stats' "attach"). Attachments live in the
## carrier's own state ({"molle": {point id: {"id", "held"?}}}), so they stay on the vest
## when it's dropped, looted, saved with the zone or stowed. A pouch's contents ("held",
## entries like a container's) are a container of their own while the vest is worn, named
## pouch_container(point) ("molle:mag_1"), and come before the vest, pockets and backpack
## in search_containers(): reloads pull from mag pouches first, and what a pouch accepts
## goes into it first when picked up.
##
## Backpacks (Captain, P0164): a pack comes off with what's in it (the contents travel in its
## state's "held", like a pouch's) and goes back on with them. A loaded pack never goes into
## a container; an empty one fits by volume, and a pack as big as the worn one or bigger only
## once it's rolled (set_rolled: smaller, its stats' "rolled_l"). Wearing a rolled pack
## unrolls it.

signal changed

## "launcher" (wave 5): an anti-armour launcher slung on the back (Launchers.SLOT; key 3).
## "exo": a light exoskeleton frame worn over the rest (ExoFrame.SLOT).
const SLOTS: Array[StringName] = [&"primary", &"sidearm", &"helmet", &"vest", &"backpack", &"plate_front", &"plate_back", &"plate_left", &"plate_right", &"launcher", &"exo"]
const PLATE_SLOTS: Array[StringName] = [&"plate_front", &"plate_back", &"plate_left", &"plate_right"]
const WEAPON_SLOTS: Array[StringName] = [&"primary", &"sidearm", &"launcher"]
## Containers, in the order auto-stow fills them (and reloads search them).
const CONTAINERS: Array[StringName] = [&"vest", &"pockets", &"backpack"]
const POCKETS_L := 2.0
## Pouch containers are named this plus the attach point's id.
const MOLLE_PREFIX := "molle:"
## Display names of attach point types.
const POINT_TYPES := {
	"mag": "Mag", "pistol": "Pistol mag", "knife": "Knife", "radio": "Radio", "medical": "Medical", "tq": "Tourniquet", "utility": "Utility", "chest": "Chest",
	"pack_top": "Pack top", "aid_bag": "Aid bag",
}
## What carries attach points: the carrier and the pack (Captain, 2026-10-12: disposable
## launchers packed on top of a pack, an aid bag on its back). Their attachments live in that
## item's state, so they go with it.
const ATTACH_SLOTS: Array[StringName] = [&"vest", &"backpack"]
## Point types only packs have.
const PACK_POINT_TYPES: Array[String] = ["pack_top", "aid_bag"]

## The whole inventory as one snapshot (saves, loot undo, the base hub's stash read and
## assign it). On the host it is always current, rounds included; assigning it replaces the
## inventory and sends the new snapshot to every peer (net_gear). It keeps a copy of what's
## assigned (consume_round updates its counts in place, which mustn't reach the caller's
## dictionary).
var net_state: Dictionary = {}:
	set(value):
		net_state = value if _committing or _receiving else value.duplicate(true)
		_apply_state(value)
		if not _receiving:
			_publish()

## Replicated (ServerSync): {"rev": the snapshot's revision, "state": a copy of net_state}, set
## by the host only when the gear really changes (_publish). Peers apply it as net_state.
var net_gear: Dictionary = {}:
	set(value):
		net_gear = value
		if not _publishing:
			_receive_gear()

## Replicated (ServerSync): [net_gear's revision, then the rounds loaded in each of
## WEAPON_SLOTS, -1 where the slot's item keeps no count], set by the host on every round
## fired (consume_round) and with every snapshot. A few bytes where a snapshot is a kilobyte
## or more.
var net_ammo: PackedInt32Array = PackedInt32Array():
	set(value):
		net_ammo = value
		if not _publishing:
			_receive_ammo()

var slots: Dictionary = {}       # slot -> item id, or &""
var slot_state: Dictionary = {}  # slot -> Dictionary (empty if the item has no state)
var containers: Dictionary = {}  # container -> Array of {"id", "count", "state"?}
var hands: StringName = &""      # two-handed carry
## A vehicle hold (VehicleCargo) carries packs loaded, and two-handed loads (a case, a
## crate); a body never stows either (a two-handed load goes in the hands, see take).
var stows_loaded_packs := false
## Host: slot -> the revision of the item worn there, bumped whenever something is put on or
## taken off that slot (or the whole inventory is replaced), so a timed action on the weapon
## in a slot (a reload) can tell it's still the same gun, not another of the same model
## picked up meanwhile (audit A2-02). Not replicated: only the host times actions.
var _slot_rev: Dictionary = {}
var _rev := 0
var _committing := false  # _commit's own net_state update keeps the revisions
var _gear_rev := 0          # host: the revision of the last snapshot published (net_gear)
var _publishing := false    # host: setting net_gear/net_ammo to send them, not receiving them
var _receiving := false     # peer: applying a received snapshot, not publishing one


func _init() -> void:
	_apply_state({})


## Litres a container holds. A pouch counted in units (a mag pouch) reports 1; room_for
## decides what fits.
func capacity(container: StringName) -> float:
	if container == &"pockets":
		return POCKETS_L
	if is_pouch_container(container):
		var pouch := pouch_item(container)
		if pouch == null:
			return 0.0
		var litres := float(pouch.stats.get("capacity_l", 0.0))
		return litres if litres > 0.0 else 1.0
	var id: StringName = slots.get(container, &"")
	return ItemDB.get_item(id).capacity_l if id != &"" else 0.0


func used(container: StringName) -> float:
	var total := 0.0
	for entry: Dictionary in containers.get(container, []):
		total += entry_volume(entry)
	return total


## Units stowed in a container.
func units_in(container: StringName) -> int:
	var total := 0
	for entry: Dictionary in containers.get(container, []):
		total += int(entry.count)
	return total


## How many units of `item` fit in `container` now: by free litres, and for a pouch also by
## what it accepts and how many units it takes. `state`: the unit's own state, so a pouch
## or carrier going in takes the room its contents fill (unit_volume).
func room_for(container: StringName, item: ItemData, state := {}) -> int:
	if item == null or (item.two_handed and not stows_loaded_packs):
		return 0
	var each := unit_volume(item, state)
	if pack_problem(container, item, state) != "":
		return 0
	if is_pouch_container(container):
		var pouch := pouch_item(container)
		if pouch == null or not pouch_accepts(pouch, item):
			return 0
		var room := 1000000
		var max_units := int(pouch.stats.get("max_units", 0))
		if max_units > 0:
			room = maxi(max_units - units_in(container), 0)
		var litres := float(pouch.stats.get("capacity_l", 0.0))
		if litres > 0.0 and each > 0.0:
			room = mini(room, int(floor((litres - used(container)) / each + 0.0001)))
		return maxi(room, 0)
	if capacity(container) <= 0.0:
		return 0
	if each <= 0.0:
		return 1000000
	return maxi(int(floor(free_volume(container) / each + 0.0001)), 0)


## Litres one unit of `item` takes up stowed, with its state: a pouch is as big as what it
## holds (an empty one folds down to its own volume_l), a carrier adds its pouches.
static func unit_volume(item: ItemData, state := {}) -> float:
	if state.get("rolled", false):
		return float(item.stats.get("rolled_l", item.volume_l))
	var each := maxf(item.volume_l, held_volume(state.get("held", [])))
	var molle: Dictionary = state.get("molle", {})
	for point: Variant in molle:
		var att: Dictionary = molle[point]
		var pouch := ItemDB.get_item(StringName(att.get("id", "")))
		if pouch:
			each += maxf(pouch.volume_l, held_volume(att.get("held", [])))
	return each


## Litres of a container entry ({"id", "count", "state"?}).
static func entry_volume(entry: Dictionary) -> float:
	var item := ItemDB.get_item(entry.id)
	return unit_volume(item, entry.get("state", {})) * int(entry.count) if item else 0.0


static func held_volume(held: Array) -> float:
	var total := 0.0
	for entry: Dictionary in held:
		total += entry_volume(entry)
	return total


func free_volume(container: StringName) -> float:
	return capacity(container) - used(container)


func total_mass() -> float:
	var total := 0.0
	for slot in SLOTS:
		if slots[slot] != &"":
			var worn := ItemDB.get_item(slots[slot])
			total += worn.mass_kg + contents_mass(state_of(slot)) + Optics.extra_mass(worn, state_of(slot)) + Suppressors.extra_mass(worn, state_of(slot))  # a carrier's pouches, a gun's optic/suppressor
	for container in CONTAINERS:
		for entry: Dictionary in containers[container]:
			total += entry_mass(entry)
	if hands != &"":
		total += ItemDB.get_item(hands).mass_kg
	return total


## Mass of a container entry ({"id", "count", "state"?}). A magazine weighs its empty
## mass plus the rounds in it ("empty_mass_kg"; its mass_kg is full).
static func entry_mass(entry: Dictionary) -> float:
	var item := ItemDB.get_item(entry.id)
	var each := item.mass_kg
	var full := item.magazine_rounds()
	if full > 0 and item.stats.has("empty_mass_kg") and entry.has("state"):
		var empty := float(item.stats.empty_mass_kg)
		each = empty + (item.mass_kg - empty) * clampf(float(entry.state.get("rounds", full)) / full, 0.0, 1.0)
	if entry.has("state"):
		each += contents_mass(entry.state)  # a stowed carrier's pouches, a pouch's contents
		each += Optics.extra_mass(item, entry.state) + Suppressors.extra_mass(item, entry.state)  # a gun with another optic/suppressor on
	return each * entry.count


## Mass of what an item's state carries: a carrier's attachments and their contents
## ("molle"), a detached pouch's contents ("held").
static func contents_mass(state: Dictionary) -> float:
	var total := 0.0
	var molle: Dictionary = state.get("molle", {})
	for point: Variant in molle:
		var att: Dictionary = molle[point]
		var item := ItemDB.get_item(StringName(att.get("id", "")))
		if item:
			total += item.mass_kg
		for entry: Dictionary in att.get("held", []):
			total += entry_mass(entry)
	for entry: Dictionary in state.get("held", []):
		total += entry_mass(entry)
	return total


## Units of `id` stowed across all containers.
func count_of(id: StringName) -> int:
	var total := 0
	for container in search_containers():
		for entry: Dictionary in containers[container]:
			if entry.id == id:
				total += entry.count
	return total


func state_of(slot: StringName) -> Dictionary:
	return slot_state.get(slot, {})


## Host only. The revision of what's worn in `slot`: it changes whenever the item there is
## put on, taken off or swapped, even for another of the same model (see _slot_rev).
func slot_revision(slot: StringName) -> int:
	return int(_slot_rev.get(slot, 0))


func _bump_revision(slot: StringName) -> void:
	_rev += 1
	_slot_rev[slot] = _rev


## Host only. Replaces the state of the item in `slot` (a launcher's loaded round, wave 5).
func set_slot_state(slot: StringName, state: Dictionary) -> void:
	if slots.get(slot, &"") == &"":
		return
	slot_state[slot] = state.duplicate(true)
	_commit()


## Host only. Takes up to `count` units, equipping into a free slot first and then
## stowing the rest. An item with `state` is a single unit, except magazines (a stack of
## magazines with the same round count, see _state_stacks). Returns how many were taken
## (0 = nothing fit).
func take(id: StringName, count := 1, state := {}) -> int:
	var item := ItemDB.get_item(id)
	if item == null or count <= 0:
		return 0
	if not state.is_empty() and not _state_stacks(item):
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
		_wear(slot, item, state)
		taken = 1
	# Pouches and knives go onto free attach points of the worn carrier that they fit.
	while taken < count and is_attachable(item):
		var point := free_point_for(item)
		if point == &"":
			break
		_set_attachment(point, id, state)
		taken += 1
	for container in stow_order(item):
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
## is empty or can't be emptied (a vest still holding plates or pouch contents). A backpack
## comes off loaded: what's in it goes in its state's "held".
func unequip(slot: StringName) -> Dictionary:
	var id: StringName = slots.get(slot, &"")
	if id == &"":
		return {}
	if slot == &"vest" and (PLATE_SLOTS.any(func(s: StringName) -> bool: return slots[s] != &"") or not containers[&"vest"].is_empty()):
		return {}
	var removed := {"id": id, "state": slot_state.get(slot, {})}
	if slot == &"backpack" and not containers[&"backpack"].is_empty():
		removed.state = removed.state.duplicate(true)
		removed.state["held"] = containers[&"backpack"].duplicate(true)
		containers[&"backpack"].clear()
	slots[slot] = &""
	slot_state.erase(slot)
	_bump_revision(slot)
	_commit()
	return removed


## Host only. Empties everything (slots, containers, hands) and returns it all as entries
## ({"id", "count", "state"?}), so it can be left in the world.
func strip() -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for slot in SLOTS:
		if slots[slot] != &"":
			var entry := {"id": slots[slot], "count": 1}
			if not slot_state.get(slot, {}).is_empty():
				entry.state = slot_state[slot].duplicate(true)
			all.append(entry)
	for container in CONTAINERS:
		for entry: Dictionary in containers[container]:
			all.append(entry.duplicate(true))
	if hands != &"":
		all.append({"id": hands, "count": 1})
	_apply_state({})
	_commit()
	return all


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


## Host only. Removes one stowed unit of `id` from whichever container has it first.
func remove_one(id: StringName) -> bool:
	for container in search_containers():
		var list: Array = containers[container]
		for i in list.size():
			if list[i].id == id:
				remove_entry(container, i)
				return true
	return false


## Host only. Puts a whole entry into `container` if it fits. Returns false otherwise.
func insert_entry(container: StringName, entry: Dictionary) -> bool:
	var item := ItemDB.get_item(entry.id)
	if item == null or room_for(container, item, entry.get("state", {})) < int(entry.count):
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
	_wear(slot, item, entry.get("state", {}))
	_commit()
	return true


# --- Ammunition -------------------------------------------------------------------------

func rounds_in(slot: StringName) -> int:
	return int(state_of(slot).get("rounds", 0))


## Rounds carried in spare magazines for `ammo_id`.
func spare_rounds(ammo_id: StringName) -> int:
	var total := 0
	var full := ItemDB.get_item(ammo_id).magazine_rounds() if ItemDB.has_item(ammo_id) else 0
	for container in search_containers():
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
	# Only a count changed: the snapshot keeps up in place and the peers get the counts
	# (net_ammo), not the whole inventory again.
	var snap_state: Dictionary = net_state.get("slot_state", {}).get(slot, {})
	if snap_state.has("rounds"):
		snap_state["rounds"] = rounds - 1
	else:  # (not seen: every snapshot holds the counts slot_state has)
		_commit()
		return true
	_publishing = true
	net_ammo = _ammo_counts()
	_publishing = false
	changed.emit()
	return true


## Host only. Loads the fullest compatible magazine carried into the weapon in `slot`. The
## magazine that comes out goes back where the new one came from, even when it's empty, so
## it can be loaded again from loose rounds (load_rounds). Returns the rounds now loaded,
## or -1 if there is nothing to reload with.
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
	for container in search_containers():
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
	_append(best_container, ItemDB.get_item(ammo_id), 1, {"rounds": current})
	slot_state[slot]["rounds"] = best_rounds
	_commit()
	return best_rounds


# --- Loading magazines --------------------------------------------------------------------

## The calibre an ammo item (magazine or loose rounds) takes or is ("5.56", "7.62", "9mm"),
## or "" for anything else.
static func calibre_of(item: ItemData) -> String:
	return String(item.stats.get("calibre", "")) if item and item.type == "ammo" else ""


## True for loose rounds (stack of single cartridges), as opposed to a magazine.
static func is_loose_rounds(item: ItemData) -> bool:
	return item != null and item.type == "ammo" and bool(item.stats.get("loose", false))


## How many of the carried loose `rounds_id` would fit into the magazines of the same
## calibre carried (part-used and empty ones).
func loadable_rounds(rounds_id: StringName) -> int:
	var loose := ItemDB.get_item(rounds_id)
	if not is_loose_rounds(loose):
		return 0
	var room := 0
	for container in search_containers():
		for entry: Dictionary in containers[container]:
			var item := ItemDB.get_item(entry.id)
			if item.magazine_rounds() > 0 and not is_loose_rounds(item) and calibre_of(item) == calibre_of(loose):
				room += (item.magazine_rounds() - int(entry.get("state", {}).get("rounds", item.magazine_rounds()))) * int(entry.count)
	return mini(room, count_of(rounds_id))


## Host only. Puts up to `count` loose `rounds_id` into the carried magazines of the same
## calibre, fullest first (a part-used magazine before an empty one). A magazine that fills
## up rejoins the full ones. Returns how many rounds went in.
func load_rounds(rounds_id: StringName, count := 1) -> int:
	var loose := ItemDB.get_item(rounds_id)
	if not is_loose_rounds(loose) or count <= 0:
		return 0
	var loaded := 0
	while loaded < count:
		var have := count_of(rounds_id)
		var best := _fullest_unfilled(calibre_of(loose))
		if have <= 0 or best.is_empty():
			break
		var list: Array = containers[best.container]
		var entry: Dictionary = list[best.index]
		var mag := ItemDB.get_item(entry.id)
		var full := mag.magazine_rounds()
		var n := mini(mini(count - loaded, full - int(best.rounds)), have)
		entry.count -= 1
		if entry.count <= 0:
			list.remove_at(best.index)
		var rounds := int(best.rounds) + n
		_append(best.container, mag, 1, {} if rounds >= full else {"rounds": rounds})
		_take_units(rounds_id, n)
		loaded += n
	if loaded > 0:
		_commit()
	return loaded


## The part-used or empty magazine of `calibre` with the most rounds in it, as
## {"container", "index", "rounds"}, or {} if every one is full.
func _fullest_unfilled(calibre: String) -> Dictionary:
	var best := {}
	for container in search_containers():
		var list: Array = containers[container]
		for i in list.size():
			var item := ItemDB.get_item(list[i].id)
			var full := item.magazine_rounds()
			if full <= 0 or is_loose_rounds(item) or calibre_of(item) != calibre:
				continue
			var rounds := int(list[i].get("state", {}).get("rounds", full))
			if rounds < full and (best.is_empty() or rounds > int(best.rounds)):
				best = {"container": container, "index": i, "rounds": rounds}
	return best


## Removes `n` stowed units of `id` (last entries first, so the biggest stacks stay
## together) without committing. Returns how many it found.
func _take_units(id: StringName, n: int) -> int:
	var left := n
	var order := search_containers()
	for c in range(order.size() - 1, -1, -1):
		var list: Array = containers[order[c]]
		for i in range(list.size() - 1, -1, -1):
			if left <= 0:
				return n
			if list[i].id != id or list[i].has("state"):
				continue
			var take_n := mini(left, int(list[i].count))
			list[i].count -= take_n
			left -= take_n
			if list[i].count <= 0:
				list.remove_at(i)
	return n - left


# --- Armor damage -----------------------------------------------------------------------

## Host only. Records a chip on the armor in `slot` (see VoxelArmor). The chip list lives
## in the item's state, so it travels with the plate or helmet when it is dropped.
func add_chip(slot: StringName, chip: Array) -> void:
	add_armor_hit(slot, chip, {})


## Host only. Records a hit on the armor in `slot`: its chip, plus whatever else the hit
## changed in the item's state (a ceramic plate's "cracks" and "integrity", see
## ArmorRules.hit_changes), all in one update. `pad` names one of an exo frame's pads
## (ExoFrame.pad_items): its state is kept in the frame's, under "pads".
func add_armor_hit(slot: StringName, chip: Array, changes: Dictionary, pad := "") -> void:
	if slots.get(slot, &"") == &"":
		return
	var state: Dictionary = slot_state.get(slot, {})
	var pads: Dictionary = state.get("pads", {})
	var piece: Dictionary = pads.get(pad, {}) if pad != "" else state
	var chips: Array = piece.get("chips", [])
	chips.append(chip)
	piece["chips"] = chips
	piece.merge(changes, true)
	if pad != "":
		pads[pad] = piece
		state["pads"] = pads
	slot_state[slot] = state
	_commit()


## The chips in the armor in `slot` (or in exo pad `pad`, see add_armor_hit).
func chips_in(slot: StringName, pad := "") -> Array:
	var state := state_of(slot)
	if pad != "":
		state = state.get("pads", {}).get(pad, {})
	return state.get("chips", [])


# --- Medical kits -----------------------------------------------------------------------
# An IFAK or trauma kit is a bag of kit items (its stats' "contents", item id -> count). An
# untouched kit has no state, so full kits stack; once something comes out, its state holds
# what's left ({"contents"}) and it keeps its own entry, wherever it goes. Treatments draw
# from loose items first, then from a kit.


## Whether `item` is a bag of kit items (IFAK, trauma kit).
static func is_kit(item: ItemData) -> bool:
	return item != null and item.stats.has("contents")


## What's left in a kit with `state`: item id (String) -> count.
static func kit_contents(item: ItemData, state: Dictionary) -> Dictionary:
	var contents: Dictionary = state.get("contents", item.stats.get("contents", {}))
	var counts := {}
	for id: String in contents:
		counts[id] = int(contents[id])  # JSON numbers are floats
	return counts


## What a kit holds, for the inventory screen: "TQ 1, Bandage 2, Gauze 1" ("empty" if nothing).
static func kit_text(item: ItemData, state: Dictionary) -> String:
	var parts := PackedStringArray()
	var contents := kit_contents(item, state)
	for id: String in contents:
		if int(contents[id]) > 0:
			var inside := ItemDB.get_item(StringName(id))
			parts.append("%s %d" % [inside.stats.get("short", inside.name) if inside else id, int(contents[id])])
	return ", ".join(parts) if not parts.is_empty() else "empty"


## Units of the kit item `id` carried: loose, plus inside kits.
func medical_count(id: StringName) -> int:
	var total := count_of(id)
	for container in search_containers():
		for entry: Dictionary in containers[container]:
			var item := ItemDB.get_item(entry.id)
			if is_kit(item):
				total += int(kit_contents(item, entry.get("state", {})).get(String(id), 0)) * int(entry.count)
	return total


## Host only. Uses up one `id`: a loose one if there is any, else one out of a kit (opened
## kits first, then the smallest). A kit with nothing left is thrown away. False if none.
func take_medical(id: StringName) -> bool:
	if remove_one(id):
		return true
	return _take_from_kit(String(id))


## Takes one `what` (an item id) out of the best kit that has one: opened kits first, then
## the one with the least left. A kit left empty is thrown away.
func _take_from_kit(what: String) -> bool:
	var best_container: StringName = &""
	var best_index := -1
	var best_opened := false
	var best_left := 0
	for container in search_containers():
		var list: Array = containers[container]
		for i in list.size():
			var item := ItemDB.get_item(list[i].id)
			var state: Dictionary = list[i].get("state", {})
			if not is_kit(item) or int(kit_contents(item, state).get(what, 0)) <= 0:
				continue
			var opened: bool = list[i].has("state")
			var left := _kit_left(item, state)
			if best_index < 0 or (opened and not best_opened) or (opened == best_opened and left < best_left):
				best_container = container
				best_index = i
				best_opened = opened
				best_left = left
	if best_index < 0:
		return false
	var list: Array = containers[best_container]
	var entry: Dictionary = list[best_index]
	var item := ItemDB.get_item(entry.id)
	var old_state: Dictionary = entry.get("state", {})
	var contents := kit_contents(item, old_state)
	contents[what] = int(contents[what]) - 1
	var state := {"contents": contents}
	var empty := _kit_left(item, state) <= 0
	if int(entry.count) > 1:
		entry.count -= 1  # open one kit out of a stack
		if not empty:
			list.append({"id": entry.id, "count": 1, "state": state})
	elif empty:
		list.remove_at(best_index)
	else:
		entry["state"] = state
	_commit()
	return true


## Everything left in a kit with `state`.
static func _kit_left(item: ItemData, state: Dictionary) -> int:
	var left := 0
	for n: Variant in kit_contents(item, state).values():
		left += int(n)
	return left


## Why the item in a container entry can't be worn right now (for messages), or "" if it can.
func entry_fit_problem(container: StringName, index: int) -> String:
	var list: Array = containers.get(container, [])
	if index < 0 or index >= list.size():
		return "Nothing there"
	return fit_problem(ItemDB.get_item(list[index].id))


## Why `item` can't go into a body slot right now ("" if it can): plates need a carrier that
## takes them (light plates fit only the light carrier; medium and heavy plates only the
## bigger ones) and a free pocket of the right kind.
func fit_problem(item: ItemData) -> String:
	if item.slot == &"":
		return "%s isn't worn" % item.name
	if not item.is_plate():
		return "" if slots.get(item.slot, &"x") == &"" else "Already wearing a %s" % item.slot
	if slots[&"vest"] == &"":
		return "Put on a plate carrier first"
	var carrier := ItemDB.get_item(slots[&"vest"])
	if not ArmorRules.plate_fits(item, carrier):
		return "%s doesn't fit the %s (fits %s)" % [item.name, carrier.name, ArmorRules.fits_text(item)]
	var side := item.slot == &"side_plate"
	var pockets := carrier_plate_slots().filter(func(s: StringName) -> bool: return (s == &"plate_left" or s == &"plate_right") == side)
	if pockets.is_empty():
		return "The %s has no %s pockets" % [carrier.name, "side plate" if side else "plate"]
	if pockets.all(func(s: StringName) -> bool: return slots[s] != &""):
		return "No free %s pocket" % ("side plate" if side else "plate")
	return ""


# --- MOLLE attachments ------------------------------------------------------------------

static func pouch_container(point: StringName) -> StringName:
	return StringName(MOLLE_PREFIX + String(point))


static func is_pouch_container(container: StringName) -> bool:
	return String(container).begins_with(MOLLE_PREFIX)


static func point_of(container: StringName) -> StringName:
	return StringName(String(container).trim_prefix(MOLLE_PREFIX))


## Items that go on an attach point (pouches, a knife).
static func is_attachable(item: ItemData) -> bool:
	return item != null and not item.stats.get("attach", []).is_empty()


## Attachable items that hold things.
static func is_pouch(item: ItemData) -> bool:
	return is_attachable(item) and (item.stats.has("accepts") or item.stats.has("max_units") or item.stats.has("capacity_l"))


## Whether `pouch` takes `item`: what its "accepts" lists (item ids, "type:x", "tag:x";
## anything when it has no list), no bigger than its "max_item_l", and never another
## attachable or a carrier.
static func pouch_accepts(pouch: ItemData, item: ItemData) -> bool:
	if pouch == null or item == null or is_attachable(item) or item.slot == &"vest" or item.slot == &"backpack" or item.two_handed:
		return false
	if pouch.stats.has("max_item_l") and item.volume_l > float(pouch.stats.max_item_l) + 0.0001:
		return false
	var accepts: Array = pouch.stats.get("accepts", [])
	if accepts.is_empty():
		return true
	for rule: String in accepts:
		if rule == String(item.id) or (rule.begins_with("type:") and rule.substr(5) == item.type) \
				or (rule.begins_with("tag:") and rule.substr(4) in item.tags):
			return true
	return false


## The attach points of what's worn (its stats' "molle"): the carrier's, then the pack's
## (a pack's top takes disposable launchers, its back an aid bag). [{"id", "type", "also"?,
## "at", "face"}]; none with neither worn. Point ids are unique across carriers and packs.
func attach_points() -> Array:
	var out := []
	for slot: StringName in ATTACH_SLOTS:
		var id: StringName = slots.get(slot, &"")
		if id != &"":
			out.append_array(ItemDB.get_item(id).stats.get("molle", []))
	return out


## The worn item (slot: &"vest" or &"backpack") whose attach point `point` is, or &"".
func point_slot(point: StringName) -> StringName:
	for slot: StringName in ATTACH_SLOTS:
		var id: StringName = slots.get(slot, &"")
		if id == &"":
			continue
		for p: Dictionary in ItemDB.get_item(id).stats.get("molle", []):
			if p.id == String(point):
				return slot
	return &""


## The types a point takes: its "type", and any "also" (a shared spot: a front corner of the
## carrier that takes a radio or a utility pouch, Captain 2026-10-12).
static func point_types(p: Dictionary) -> Array:
	return [String(p.type)] + Array(p.get("also", []))


## The worn attach point `point` ({} if nothing worn has it).
func attach_point(point: StringName) -> Dictionary:
	for p: Dictionary in attach_points():
		if p.id == String(point):
			return p
	return {}


## What's on attach point `point`: {"id", "held"? (a pouch's contents), "state"? (a launcher's)},
## or {}.
func attachment(point: StringName) -> Dictionary:
	var slot := point_slot(point)
	return slot_state.get(slot, {}).get("molle", {}).get(String(point), {}) if slot != &"" else {}


## The pouch on a pouch container's point, or null.
func pouch_item(container: StringName) -> ItemData:
	var att := attachment(point_of(container))
	return ItemDB.get_item(StringName(att.get("id", ""))) if not att.is_empty() else null


## Whether `item` goes only on a pack's points (a disposable launcher, an aid bag).
static func pack_only(item: ItemData) -> bool:
	return is_attachable(item) and Array(item.stats.attach).all(func(t: String) -> bool: return t in PACK_POINT_TYPES)


## "Put on a plate carrier first" or "... a backpack ...", whichever `item` would hang on.
func _wear_first(item: ItemData) -> String:
	return "Put on a backpack first" if pack_only(item) else "Put on a plate carrier first"


## Why `item` can't go on `point` right now ("" if it can).
func attach_problem(item: ItemData, point: StringName) -> String:
	if not is_attachable(item):
		return "%s doesn't attach to a carrier" % item.name
	var p := attach_point(point)
	if p.is_empty():
		if attach_points().is_empty():
			return _wear_first(item)
		return "Nothing you wear has a %s point" % point
	if not attachment(point).is_empty():
		return "Something is already on that point"
	if not point_types(p).any(func(t: String) -> bool: return t in item.stats.attach):
		return "%s doesn't fit a %s point (fits %s)" % [item.name, types_text(point_types(p), "/"), types_text(item.stats.attach, ", ")]
	return ""


static func types_text(types: Array, sep: String) -> String:
	return sep.join(PackedStringArray(types.map(func(t: String) -> String: return POINT_TYPES.get(t, t))))


## Why `item` has no free point (free_point_for found none): nothing worn to hang it on, no
## point of its types, or those points all taken ("" if one is free).
## (Captain's playtest P0164: "No free point on the carrier" didn't say which.)
func no_point_problem(item: ItemData) -> String:
	if not is_attachable(item):
		return "%s doesn't attach to a carrier" % item.name
	var on := &"backpack" if pack_only(item) else &"vest"
	if slots[on] == &"":
		return _wear_first(item)
	if free_point_for(item) != &"":
		return ""
	var wearing := ItemDB.get_item(slots[on]).name
	var types := types_text(item.stats.attach, " or ")
	var fitting := attach_points().filter(func(p: Dictionary) -> bool: return point_types(p).any(func(t: String) -> bool: return t in item.stats.attach))
	if fitting.is_empty():
		return "The %s has no %s point for the %s" % [wearing, types, item.name]
	return "Every %s point on the %s is taken (%d)" % [types, wearing, fitting.size()]


## The first free attach point that `item` fits (its own point types first: a mag pouch on a
## mag point before a utility one; and a point that's mainly that type before a shared spot
## that also takes it, so a GP pouch leaves the radio spot to the radio), or &"".
func free_point_for(item: ItemData) -> StringName:
	if not is_attachable(item):
		return &""
	for kind: String in item.stats.attach:
		for shared in [false, true]:
			for p: Dictionary in attach_points():
				var fits: bool = (kind in p.get("also", [])) if shared else String(p.type) == kind
				if fits and attachment(StringName(p.id)).is_empty():
					return StringName(p.id)
	return &""


## Pouch containers on the worn carrier, in attach point order.
func pouch_containers() -> Array[StringName]:
	var out: Array[StringName] = []
	for p: Dictionary in attach_points():
		var c := pouch_container(StringName(p.id))
		if containers.has(c):
			out.append(c)
	return out


## Every container, in the order reloads and other searches look: pouches first, then the
## vest, pockets and backpack.
func search_containers() -> Array[StringName]:
	var out := pouch_containers()
	out.append_array(CONTAINERS)
	return out


## Where `item` is stowed when it's picked up: pouches made for it, the ones naming it first
## (a tourniquet holder for a tourniquet, before an IFAK pouch that takes any medical item),
## then the vest, pockets and backpack, then general pouches.
func stow_order(item: ItemData) -> Array[StringName]:
	var made_for: Array[StringName] = []
	var by_type: Array[StringName] = []
	var general: Array[StringName] = []
	for c in pouch_containers():
		var pouch := pouch_item(c)
		if not pouch_accepts(pouch, item):
			continue
		if String(item.id) in pouch.stats.get("accepts", []):
			made_for.append(c)
		elif pouch.stats.has("accepts"):
			by_type.append(c)
		else:
			general.append(c)
	made_for.append_array(by_type)
	made_for.append_array(CONTAINERS)
	made_for.append_array(general)
	return made_for


## Host only. Puts one unit of a stowed entry onto attach point `point` (or the first free
## one it fits, for &""). A pouch's contents ("held" in its state) go on with it.
func attach_entry(container: StringName, index: int, point: StringName = &"") -> bool:
	var list: Array = containers.get(container, [])
	if index < 0 or index >= list.size():
		return false
	var item := ItemDB.get_item(list[index].id)
	if point == &"":
		point = free_point_for(item)
	if point == &"" or attach_problem(item, point) != "":
		return false
	var entry := remove_entry(container, index, 1)
	_set_attachment(point, item.id, entry.get("state", {}))
	_commit()
	return true


## Host only. Takes what's on `point` off what's worn and returns it as an entry
## ({"id", "count": 1, "state"?: {"held": contents} or a launcher's own state}), or {}.
func detach(point: StringName) -> Dictionary:
	var att := attachment(point)
	if att.is_empty():
		return {}
	var molle: Dictionary = slot_state[point_slot(point)]["molle"]
	molle.erase(String(point))
	var entry := {"id": StringName(att.id), "count": 1}
	var held: Array = att.get("held", [])
	if not held.is_empty():
		entry.state = {"held": held.duplicate(true)}
	elif not att.get("state", {}).is_empty():
		entry.state = att.state.duplicate(true)
	_commit()
	return entry


## Host only. Puts an entry from detach() (or any attachable) onto `point`. False if it
## doesn't go there.
func attach(point: StringName, entry: Dictionary) -> bool:
	var item := ItemDB.get_item(entry.get("id", &""))
	if item == null or attach_problem(item, point) != "":
		return false
	_set_attachment(point, item.id, entry.get("state", {}))
	_commit()
	return true


## Host only. Moves what's on attach point `from` to the free point `to` (on the same item or
## the other: carrier and pack).
func move_attachment(from: StringName, to: StringName) -> bool:
	var att := attachment(from)
	if att.is_empty() or from == to:
		return false
	var item := ItemDB.get_item(StringName(att.id))
	if attach_problem(item, to) != "":
		return false
	(slot_state[point_slot(from)]["molle"] as Dictionary).erase(String(from))
	_molle_of(point_slot(to))[String(to)] = att
	_commit()
	return true


## How many attachments the worn carrier (or `slot`: the pack) has.
func attachment_count(slot := &"vest") -> int:
	return slot_state.get(slot, {}).get("molle", {}).size()


## Host only. Puts what's on `point` (a launcher packed on top of the pack) into its body slot,
## its state and all. False if nothing is there, it isn't worn gear, or the slot is taken.
func equip_attachment(point: StringName) -> bool:
	var att := attachment(point)
	if att.is_empty():
		return false
	var item := ItemDB.get_item(StringName(att.id))
	if item == null or item.slot == &"" or slots.get(item.slot, &"x") != &"":
		return false
	var entry := detach(point)
	_wear(item.slot, item, entry.get("state", {}))
	_commit()
	return true


## The "molle" Dictionary in the state of worn `slot` (made if missing).
func _molle_of(slot: StringName) -> Dictionary:
	var s: Dictionary = slot_state.get(slot, {})
	if not s.has("molle"):
		s["molle"] = {}
	slot_state[slot] = s
	return s["molle"]


## Sets what's on `point` (no checks, no commit). A pouch takes its contents from `state`;
## anything else with state (a launcher's loaded round) keeps it.
func _set_attachment(point: StringName, id: StringName, state: Dictionary) -> void:
	var att := {"id": id}
	var item := ItemDB.get_item(id)
	if is_pouch(item):
		att["held"] = state.get("held", []).duplicate(true)
	elif not state.is_empty():
		att["state"] = state.duplicate(true)
	_molle_of(point_slot(point))[String(point)] = att


# --- Backpacks --------------------------------------------------------------------------

## Whether `item` is a pack (worn in the backpack slot).
static func is_pack(item: ItemData) -> bool:
	return item != null and item.slot == &"backpack"


## Why the pack `item` (with `state`) can't go into `container` ("" if it can, or isn't a
## pack): a loaded pack never goes in, and one as big as the worn pack or bigger goes into
## it only rolled.
func pack_problem(container: StringName, item: ItemData, state := {}) -> String:
	if not is_pack(item) or stows_loaded_packs:
		return ""
	if not state.get("held", []).is_empty():
		return "Empty the %s first" % item.name
	if container == &"backpack" and slots.get(&"backpack", &"") != &"" and not state.get("rolled", false) \
			and item.capacity_l >= ItemDB.get_item(slots[&"backpack"]).capacity_l:
		return "Roll the %s up first" % item.name
	return ""


## Why the pack in a container entry can't be rolled up (`rolled` true) or unrolled ("" if it
## can): only an empty pack with nothing attached rolls, and unrolling needs the room.
func roll_problem(container: StringName, index: int, rolled: bool) -> String:
	var list: Array = containers.get(container, [])
	if index < 0 or index >= list.size():
		return "Nothing there"
	var item := ItemDB.get_item(list[index].id)
	var state: Dictionary = list[index].get("state", {})
	if not is_pack(item):
		return "Only a pack rolls up"
	if bool(state.get("rolled", false)) == rolled:
		return "It's already %s" % ("rolled up" if rolled else "unrolled")
	if rolled and (not state.get("held", []).is_empty() or not state.get("molle", {}).is_empty()):
		return "Empty the %s and take everything off it first" % item.name
	if not rolled:
		var unrolled := state.duplicate(true)
		unrolled.erase("rolled")
		if pack_problem(container, item, unrolled) != "" \
				or unit_volume(item, unrolled) - unit_volume(item, state) > free_volume(container) + 0.0001:
			return "No room to unroll it in there"
	return ""


## Host only. Rolls up (or unrolls) the pack in a container entry. False if roll_problem.
func set_rolled(container: StringName, index: int, rolled: bool) -> bool:
	if roll_problem(container, index, rolled) != "":
		return false
	var entry: Dictionary = containers[container][index]
	var state: Dictionary = entry.get("state", {}).duplicate(true)
	if rolled:
		state["rolled"] = true
	else:
		state.erase("rolled")
	if state.is_empty():
		entry.erase("state")
	else:
		entry["state"] = state
	_commit()
	return true


# --- Refusals ---------------------------------------------------------------------------
# Playtest S2 (P0339, P0331): "Not enough room in Sustainment Pouch", "No room for M110 DMR"
# said no more than that, and kitting up took try after try. A refusal now says why, and
# where it would go instead (places_for: the inventory screen lights those up).


## Where one unit of `item` (with `state`) would go right now: [{"kind": "slot", "slot"},
## {"kind": "point", "point"}, {"kind": "container", "container"}], body slot first, then free
## attach points it fits, then pouches and containers with room (stow order).
func places_for(item: ItemData, state := {}) -> Array:
	var out: Array = []
	if item == null:
		return out
	var slot := _free_slot_for(item)
	if slot != &"":
		out.append({"kind": "slot", "slot": slot})
	if is_attachable(item):
		for p: Dictionary in attach_points():
			if attach_problem(item, StringName(p.id)) == "":
				out.append({"kind": "point", "point": StringName(p.id)})
	for c in stow_order(item):
		if containers.has(c) and room_for(c, item, state) > 0:
			out.append({"kind": "container", "container": c})
	return out


## places_for as words: "Vest, Backpack, Utility point (utility_1)".
func places_text(places: Array) -> String:
	var parts := PackedStringArray()
	for p: Dictionary in places:
		match String(p.kind):
			"slot":
				parts.append("%s slot" % String(p.slot).capitalize())
			"point":
				var at := attach_point(p.point)
				parts.append("%s point (%s)" % [types_text(point_types(at), "/"), String(p.point)])
			"container":
				parts.append(container_label(p.container))
	return ", ".join(parts)


## A container's name for messages: "Vest", "Backpack", or the pouch's with its point
## ("Sustainment Pouch on utility_1").
func container_label(container: StringName) -> String:
	if is_pouch_container(container):
		var pouch := pouch_item(container)
		return "%s on %s" % [pouch.name if pouch else "pouch", String(point_of(container))]
	return String(container).capitalize()


## Why `item` (with `state`) won't go into `target` (a container, a pouch's; or &"" for
## anywhere), and where it would: "Not enough room in Backpack (M110 DMR needs 6.0 L, 2.3 L
## free). It fits: Vest". "" if it goes in.
func refusal(item: ItemData, state := {}, target: StringName = &"") -> String:
	if item == null:
		return "Nothing there"
	var why := ""
	if item.two_handed and not stows_loaded_packs:
		why = "%s is carried in both hands" % item.name
	elif target == &"":
		if not places_for(item, state).is_empty():
			return ""
		why = "No room for %s (needs %.1f L)" % [item.name, unit_volume(item, state)]
		var best: StringName = &""
		for c in CONTAINERS:
			if capacity(c) > 0.0 and (best == &"" or free_volume(c) > free_volume(best)):
				best = c
		if best != &"":
			why += ": most free is %s, %.1f L" % [container_label(best), maxf(free_volume(best), 0.0)]
	elif room_for(target, item, state) > 0:
		return ""
	elif pack_problem(target, item, state) != "":
		why = pack_problem(target, item, state)
	elif is_pouch_container(target):
		var pouch := pouch_item(target)
		if pouch == null:
			why = "That pouch is gone"
		elif not pouch_accepts(pouch, item):
			var takes := _pouch_takes(pouch)
			why = "%s doesn't take %s%s" % [pouch.name, item.name, " (it takes %s)" % takes if takes != "" else ""]
		elif int(pouch.stats.get("max_units", 0)) > 0 and units_in(target) >= int(pouch.stats.max_units):
			why = "%s is full (%d of %d)" % [container_label(target), units_in(target), int(pouch.stats.max_units)]
		else:
			why = "Not enough room in %s (%s needs %.1f L, %.1f L free)" % [container_label(target), item.name, unit_volume(item, state),
				maxf(float(pouch.stats.get("capacity_l", 0.0)) - used(target), 0.0)]
	elif capacity(target) <= 0.0:
		why = "No %s worn" % String(target).capitalize() if target != &"pockets" else "No pockets"
	else:
		why = "Not enough room in %s (%s needs %.1f L, %.1f L free)" % [container_label(target), item.name, unit_volume(item, state),
			maxf(free_volume(target), 0.0)]
	return why + where_else(item, state, target)


## ". It fits: Vest, Backpack" (what places_for finds, `target` left out), or ". Nowhere you
## carry has room for it".
func where_else(item: ItemData, state := {}, target: StringName = &"") -> String:
	var places := places_for(item, state).filter(func(p: Dictionary) -> bool: return p.get("container", &"") != target or target == &"")
	if places.is_empty():
		return ". Nowhere you carry has room for it"
	return ". It fits: " + places_text(places)


## What a pouch takes, in words: "M4 Mag, M110 Mag", "medical items".
static func _pouch_takes(pouch: ItemData) -> String:
	var parts := PackedStringArray()
	for rule: String in pouch.stats.get("accepts", []):
		if rule.begins_with("type:"):
			parts.append("%s items" % rule.substr(5))
		elif rule.begins_with("tag:"):
			parts.append("%ss" % rule.substr(4))
		else:
			var it := ItemDB.get_item(StringName(rule))
			parts.append(it.name if it else rule)
	return ", ".join(parts)


# --- Internals --------------------------------------------------------------------------

## Puts `item` into body `slot` with `state` (no checks, no commit). A pack goes on unrolled,
## and what it carried ("held") goes into the backpack container.
func _wear(slot: StringName, item: ItemData, state: Dictionary) -> void:
	var s := state.duplicate(true) if not state.is_empty() else item.default_state()
	if slot == &"backpack":
		s.erase("rolled")
		containers[&"backpack"] = s.get("held", []).duplicate(true)
		s.erase("held")
	slots[slot] = item.id
	slot_state[slot] = s
	_bump_revision(slot)


func _free_slot_for(item: ItemData) -> StringName:
	match item.slot:
		&"":
			return &""
		&"plate", &"side_plate":
			# Plates need a carrier that takes them, and only fit the pockets it has.
			if slots[&"vest"] == &"" or not ArmorRules.plate_fits(item, ItemDB.get_item(slots[&"vest"])):
				return &""
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
	var n := mini(room_for(container, item, state), want)
	if n > 0:
		_append(container, item, n, state)
	return n


func _append(container: StringName, item: ItemData, count: int, state: Dictionary) -> void:
	var list: Array = containers[container]
	var stateful := not state.is_empty() and state != item.default_state()
	# Stateful items (a damaged plate) keep their own entry; magazines stack with others
	# holding the same rounds (two empties, two 12-round mags).
	if stateful and not _state_stacks(item):
		for i in count:
			list.append({"id": item.id, "count": 1, "state": state.duplicate(true)})
		return
	var left := count
	for entry: Dictionary in list:
		if left <= 0:
			break
		var same: bool = entry.get("state", {}) == state if stateful else not entry.has("state")
		if entry.id == item.id and same and entry.count < item.stack:
			var add := mini(item.stack - entry.count, left)
			entry.count += add
			left -= add
	while left > 0:
		var add := mini(item.stack, left)
		var entry := {"id": item.id, "count": add}
		if stateful:
			entry.state = state.duplicate(true)
		list.append(entry)
		left -= add


## Items whose stateful entries still stack when the state is the same: magazines (their
## state is just the round count). Plates and helmets never do.
static func _state_stacks(item: ItemData) -> bool:
	return item.type == "ammo"


func _commit() -> void:
	_committing = true
	net_state = _snapshot()
	_committing = false


func _snapshot() -> Dictionary:
	var stowed := {}
	for container in CONTAINERS:  # pouch contents travel in the carrier's state
		stowed[container] = containers[container].duplicate(true)
	return {
		"slots": slots.duplicate(),
		"slot_state": slot_state.duplicate(true),
		"containers": stowed,
		"hands": hands,
	}


## Host (whoever assigns net_state): sends the whole snapshot, with the counts that go with it.
## The copy keeps consume_round's in-place count updates out of what was sent.
func _publish() -> void:
	if is_inside_tree() and not multiplayer.is_server():
		return  # a peer's copy (a vehicle's cargo applied from its state): nothing to send
	_gear_rev += 1
	_publishing = true
	net_gear = {"rev": _gear_rev, "state": net_state.duplicate(true)}
	net_ammo = _ammo_counts()
	_publishing = false


func _ammo_counts() -> PackedInt32Array:
	var counts := PackedInt32Array([_gear_rev])
	for slot in WEAPON_SLOTS:
		var state: Dictionary = slot_state.get(slot, {})
		counts.append(int(state.rounds) if slots.get(slot, &"") != &"" and state.has("rounds") else -1)
	return counts


## Peer: a snapshot arrived. Becomes net_state, then the counts fired since go on it.
func _receive_gear() -> void:
	_gear_rev = int(net_gear.get("rev", 0))
	_receiving = true
	net_state = net_gear.get("state", {})
	_receiving = false
	_receive_ammo()


## Peer: counts arrived. They go on the snapshot of the same revision; older ones are already
## in a newer snapshot, and newer ones wait for theirs (_receive_gear applies them).
func _receive_ammo() -> void:
	if net_ammo.size() != WEAPON_SLOTS.size() + 1 or net_ammo[0] != _gear_rev or net_gear.is_empty():
		return
	var any := false
	for i in WEAPON_SLOTS.size():
		var slot := WEAPON_SLOTS[i]
		var rounds := net_ammo[i + 1]
		var state: Dictionary = slot_state.get(slot, {})
		if rounds < 0 or not state.has("rounds") or int(state.rounds) == rounds:
			continue
		state["rounds"] = rounds
		var snap_state: Dictionary = net_state.get("slot_state", {}).get(slot, {})
		if snap_state.has("rounds"):
			snap_state["rounds"] = rounds
		any = true
	if any:
		changed.emit()


func _apply_state(state: Dictionary) -> void:
	if not _committing:
		for slot in SLOTS:  # replaced wholesale (stripped, a loot undone, a zone load): new items
			_bump_revision(slot)
	slots.clear()
	for slot in SLOTS:
		slots[slot] = StringName(state.get("slots", {}).get(slot, &""))
	slot_state = state.get("slot_state", {}).duplicate(true)
	containers.clear()
	for container in CONTAINERS:
		containers[container] = state.get("containers", {}).get(container, []).duplicate(true)
	# Each pouch on the worn carrier (or pack: an aid bag) is a container: the very Array in
	# that item's state, so what goes in or out of it is in its state too.
	for slot: StringName in ATTACH_SLOTS:
		var molle: Dictionary = slot_state.get(slot, {}).get("molle", {})
		for point: Variant in molle:
			var att: Dictionary = molle[point]
			if is_pouch(ItemDB.get_item(StringName(att.get("id", "")))):
				if not att.has("held"):
					att["held"] = []
				containers[pouch_container(StringName(point))] = att["held"]
	hands = StringName(state.get("hands", &""))
	changed.emit()
