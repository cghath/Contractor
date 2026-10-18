class_name GunAttachments
extends RefCounted
## Weapon attachments beyond the optic and the suppressor (wave 7, S3; Captain: "Modular
## weapon attachments"). The optic (Optics, the rail on top) and the suppressor (Suppressors,
## the threaded muzzle) keep their own modules; this one adds the two mounts they leave:
##   underbarrel: a grip (tag "grip"): less recoil (recoil_mult) and less aimed sway (sway_mult);
##   side:        a weapon light (tag "light") or a laser (tag "laser", beam "visible" or "ir"),
##                switched on and off with the weapon-light key (Controls.KEYS weapon_light)
##                or the inventory's "Light on / off".
## Each is an item (type "attachment", stats.mount = its mount, stats.fits = weapon tags it
## fits; an underbarrel one also needs a rail). What's on a gun is part of the gun's own item
## state, like its magazine and optic: state[mount] = the item id, and "side_on" = the light or
## laser is switched on. So it travels with the gun everywhere its state goes (dropped,
## stowed, looted, stashed, saved) and replicates with the inventory (Inventory.net_state).
## all_of() gives the whole slot -> item id picture, optic and muzzle included.
## A visible light or laser that's on gives its carrier away to the AI (Spotting.LIT, lit());
## an IR laser shows only through night vision (ir_on(): the hook for the NVG work; no AI
## effect yet). Every number is proposed, for Captain's playtests.

const TYPE := "attachment"
const UNDERBARREL := &"underbarrel"
const SIDE := &"side"
const MOUNTS: Array[StringName] = [UNDERBARREL, SIDE]
const ON_KEY := "side_on"
## The node the light and laser hang from, under the soldier's camera (rig()).
const RIG_NAME := "GunLightRig"


## The mount `item` goes on (&"" if it isn't one of these attachments).
static func mount_of(item: ItemData) -> StringName:
	if item == null or item.type != TYPE:
		return &""
	var m := StringName(String(item.stats.get("mount", "")))
	return m if m in MOUNTS else &""


static func is_attachment(item: ItemData) -> bool:
	return mount_of(item) != &""


## True if `weapon` takes `item` (its mount, and a tag it fits; an underbarrel needs a rail).
static func fits(weapon: ItemData, item: ItemData) -> bool:
	var m := mount_of(item)
	if m == &"" or weapon == null or weapon.type != "weapon":
		return false
	if m == UNDERBARREL and not bool(weapon.stats.get("rail", false)):
		return false
	for tag: Variant in item.stats.get("fits", []):
		if weapon.tags.has(String(tag)):
			return true
	return false


## The id of what's on `mount` of `weapon` with item state `state` (&"" for nothing).
static func mounted_id(weapon: ItemData, state: Dictionary, mount: StringName) -> StringName:
	var id := StringName(String(state.get(String(mount), "")))
	if id == &"":
		return &""
	var item := ItemDB.get_item(id) if ItemDB.has_item(id) else null
	return id if item != null and mount_of(item) == mount and fits(weapon, item) else &""


static func mounted(weapon: ItemData, state: Dictionary, mount: StringName) -> ItemData:
	var id := mounted_id(weapon, state, mount)
	return ItemDB.get_item(id) if id != &"" else null


## Every attachment point of `weapon` as `state` has it: mount -> item id ("" for none), for
## the optic ("optic"), the muzzle ("muzzle"), underbarrel and side.
static func all_of(weapon: ItemData, state: Dictionary) -> Dictionary:
	return {
		"optic": String(Optics.mounted_id(weapon, state)),
		"muzzle": String(Suppressors.mounted_id(weapon, state)),
		"underbarrel": String(mounted_id(weapon, state, UNDERBARREL)),
		"side": String(mounted_id(weapon, state, SIDE)),
	}


## `state` with `id` on `mount` (&"" for none; taking the side one off switches it off).
static func with_mounted(state: Dictionary, mount: StringName, id: StringName) -> Dictionary:
	var out := state.duplicate(true)
	if id == &"":
		out.erase(String(mount))
		if mount == SIDE:
			out.erase(ON_KEY)
	else:
		out[String(mount)] = String(id)
	return out


## Why the entry at `container`/`index` can't go on the weapon in `slot`, or "".
static func mount_problem(inv: Inventory, container: StringName, index: int, slot: StringName) -> String:
	var list: Array = inv.containers.get(container, [])
	if index < 0 or index >= list.size():
		return "Can't do that"
	var item := ItemDB.get_item(StringName(list[index].id))
	if not is_attachment(item):
		return "That doesn't go on a gun"
	if not slot in Inventory.WEAPON_SLOTS:
		return "Not a gun"
	var id: StringName = inv.slots.get(slot, &"")
	if id == &"":
		return "No gun there"
	if not fits(ItemDB.get_item(id), item):
		return "The %s doesn't take a %s" % [ItemDB.get_item(id).name, item.name]
	return ""


## Host only. Mounts the entry at `container`/`index` on the weapon in `slot`; what was on that
## mount goes where the new one came from (or the first container with room). "" or why not.
static func server_mount(inv: Inventory, container: StringName, index: int, slot: StringName) -> String:
	var problem := mount_problem(inv, container, index, slot)
	if problem != "":
		return problem
	var item := ItemDB.get_item(StringName(inv.containers[container][index].id))
	var m := mount_of(item)
	var weapon := ItemDB.get_item(inv.slots[slot])
	var old := mounted_id(weapon, inv.state_of(slot), m)
	var entry := inv.remove_entry(container, index)
	if entry.is_empty():
		return "Can't do that"
	if old != &"" and not _stow(inv, old, container):
		inv.insert_entry(container, entry)  # no room for the old one: put the new one back
		return "No room for the %s" % ItemDB.get_item(old).name
	var state := with_mounted(inv.state_of(slot), m, StringName(entry.id))
	if m == SIDE:
		state.erase(ON_KEY)  # a new light or laser goes on switched off
	inv.set_slot_state(slot, state)
	return ""


## Host only. Takes what's on `mount` of the weapon in `slot` off into the first container
## with room (`target` first if named). "" or why not.
static func server_remove(inv: Inventory, slot: StringName, mount: StringName, target: StringName = &"") -> String:
	var id: StringName = inv.slots.get(slot, &"")
	var weapon := ItemDB.get_item(id) if id != &"" else null
	var old := mounted_id(weapon, inv.state_of(slot), mount) if weapon else &""
	if old == &"":
		return "Nothing on it there"
	if not _stow(inv, old, target):
		return "No room for the %s" % ItemDB.get_item(old).name
	inv.set_slot_state(slot, with_mounted(inv.state_of(slot), mount, &""))
	return ""


## Host only. Switches the light or laser on the weapon in `slot` on or off. "" or why not.
static func server_toggle(inv: Inventory, slot: StringName) -> String:
	var id: StringName = inv.slots.get(slot, &"")
	var weapon := ItemDB.get_item(id) if id != &"" else null
	if weapon == null or mounted_id(weapon, inv.state_of(slot), SIDE) == &"":
		return "No light or laser on it"
	var state := inv.state_of(slot).duplicate(true)
	if bool(state.get(ON_KEY, false)):
		state.erase(ON_KEY)
	else:
		state[ON_KEY] = true
	inv.set_slot_state(slot, state)
	return ""


static func _stow(inv: Inventory, id: StringName, first: StringName) -> bool:
	var order: Array[StringName] = []
	if first != &"" and inv.containers.has(first):
		order.append(first)
	order.append_array(inv.search_containers())
	for c in order:
		if inv.insert_entry(c, {"id": id, "count": 1}):
			return true
	return false


# --- What they do -----------------------------------------------------------------------

## Recoil (the kick and its heat) times this: a grip's recoil_mult (1 with none).
static func recoil_mult(weapon: ItemData, state: Dictionary) -> float:
	var grip := mounted(weapon, state, UNDERBARREL)
	return float(grip.stats.get("recoil_mult", 1.0)) if grip else 1.0


## Aimed sway and breathing times this: a grip's sway_mult (1 with none).
static func sway_mult(weapon: ItemData, state: Dictionary) -> float:
	var grip := mounted(weapon, state, UNDERBARREL)
	return float(grip.stats.get("sway_mult", 1.0)) if grip else 1.0


## The side attachment that's switched on (null: none, or off).
static func side_on(weapon: ItemData, state: Dictionary) -> ItemData:
	return mounted(weapon, state, SIDE) if bool(state.get(ON_KEY, false)) else null


static func light_on(weapon: ItemData, state: Dictionary) -> bool:
	var on := side_on(weapon, state)
	return on != null and "light" in on.tags


## The beam of the laser that's on: "visible", "ir" or "" (none, or off).
static func laser_beam(weapon: ItemData, state: Dictionary) -> String:
	var on := side_on(weapon, state)
	return String(on.stats.get("beam", "visible")) if on != null and "laser" in on.tags else ""


## True if `s` shows a light or visible laser the naked eye can see, from the gun in hand.
static func lit(s: Soldier) -> bool:
	if s == null or s.inventory == null or not s.vitals.is_up():
		return false
	var weapon := s.active_weapon()
	var state := s.inventory.state_of(s.active_slot)
	return weapon != null and (light_on(weapon, state) or laser_beam(weapon, state) == "visible")


## True if `s` shows an IR laser (seen only through night vision: the NVG work's hook).
static func ir_on(s: Soldier) -> bool:
	if s == null or s.inventory == null or not s.vitals.is_up():
		return false
	var weapon := s.active_weapon()
	return weapon != null and laser_beam(weapon, s.inventory.state_of(s.active_slot)) == "ir"


## What these add to a gun's mass_kg (a gun as it comes carries none of them).
static func extra_mass(weapon: ItemData, state: Dictionary) -> float:
	var kg := 0.0
	for m in MOUNTS:
		var on := mounted(weapon, state, m)
		if on:
			kg += on.mass_kg
	return kg


## As extra_mass, in shop dollars (Prices.price_of).
static func extra_price(weapon: ItemData, state: Dictionary) -> int:
	var usd := 0
	for m in MOUNTS:
		var id := mounted_id(weapon, state, m)
		if id != &"":
			usd += Prices.price_of(id)
	return usd


## Short names of what's on, for readouts ("" with none): "Grip, Light (on)".
static func label(weapon: ItemData, state: Dictionary) -> String:
	var parts: PackedStringArray = []
	for m in MOUNTS:
		var on := mounted(weapon, state, m)
		if on:
			var text := String(on.stats.get("short", on.name))
			if m == SIDE and bool(state.get(ON_KEY, false)):
				text += " (on)"
			parts.append(text)
	return ", ".join(parts)


## The optic's label (Optics.label) and then label()'s, for a gun's readout.
static func label_with_optic(weapon: ItemData, state: Dictionary) -> String:
	var optic := Optics.label(weapon, state)
	var rest := label(weapon, state)
	return optic + (", " if optic != "" and rest != "" else "") + rest


# --- The light and the laser, on every peer ---------------------------------------------

## Adds the light-and-laser rig under `s`'s camera (once). It reads the replicated item state
## every frame, so it shows the same on every peer with nothing more sent.
static func rig(s: Soldier) -> Node3D:
	var existing := s.camera.get_node_or_null(RIG_NAME) as Node3D
	if existing:
		return existing
	var r := Node3D.new()
	r.name = RIG_NAME
	r.set_script(load("res://scripts/combat/gun_light_rig.gd"))
	s.camera.add_child(r)
	return r
