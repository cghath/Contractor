class_name GearMounts
extends RefCounted
## What hangs on a worn item besides the optic, for loadout templates (claude/loadout-3d,
## Captain 2026-10-22: "click slots on the model: helmet and its mounts ... weapon rails and
## muzzle"): a gun's muzzle (Suppressors), underbarrel, side and choke (GunAttachments), and a
## helmet's NVG (Nvg). Each lives in the holder's own item state, so these read and write it.
##
## A template's "mounts" (Restock): slot -> {mount: item id}. A slot listed there is the whole
## truth for that holder (a mount it leaves out comes off); a slot not listed keeps whatever the
## drawn item already carries, which is how every template recorded before this worked.

const WEAPON_MOUNTS: Array[String] = ["muzzle", "underbarrel", "side", "choke"]
const HELMET_MOUNTS: Array[String] = ["nvg"]
const NAMES := {"optic": "Optic", "muzzle": "Muzzle", "underbarrel": "Underbarrel", "side": "Side rail", "choke": "Choke", "nvg": "NVG mount"}

static var _mounts_cache := {}


## The mounts `holder` has (an optic's rail is Optics', not listed here).
static func mounts_for(holder: ItemData) -> Array[String]:
	var out: Array[String] = []
	if holder == null:
		return out
	if holder.slot == Nvg.HELMET:
		return HELMET_MOUNTS.duplicate()
	if holder.type != "weapon":
		return out
	if _mounts_cache.has(holder.id):
		return (_mounts_cache[holder.id] as Array[String]).duplicate()
	if Suppressors.has_muzzle(holder):
		out.append("muzzle")
	for m: String in ["underbarrel", "side", "choke"]:
		if ItemDB.all_ids().any(func(id: StringName) -> bool: return GunAttachments.fits(holder, ItemDB.get_item(id)) and String(GunAttachments.mount_of(ItemDB.get_item(id))) == m):
			out.append(m)
	_mounts_cache[holder.id] = out.duplicate()
	return out


## Whether `item` goes on `mount` of `holder`.
static func fits(holder: ItemData, mount: String, item: ItemData) -> bool:
	if holder == null or item == null:
		return false
	match mount:
		"muzzle":
			return Suppressors.has_muzzle(holder) and Suppressors.is_suppressor(item)
		"nvg":
			return holder.slot == Nvg.HELMET and Nvg.is_nvg(item)
		"optic":
			return Optics.has_rail(holder) and Optics.is_optic(item)
	return String(GunAttachments.mount_of(item)) == mount and GunAttachments.fits(holder, item)


## The id on `mount` of `holder` with item state `state` ("" for none).
static func on(holder: ItemData, state: Dictionary, mount: String) -> String:
	if holder == null:
		return ""
	match mount:
		"muzzle":
			return String(Suppressors.mounted_id(holder, state))
		"nvg":
			var n: Variant = state.get(Nvg.STATE_KEY, {})
			return String((n as Dictionary).get("id", "")) if n is Dictionary else ""
		"optic":
			return String(Optics.mounted_id(holder, state))
	return String(GunAttachments.mounted_id(holder, state, StringName(mount)))


## {mount: id} of everything on `holder` (non-empty only; the optic left to Optics).
static func of(holder: ItemData, state: Dictionary) -> Dictionary:
	var out := {}
	if holder == null:
		return out
	for m: String in (HELMET_MOUNTS if holder.slot == Nvg.HELMET else WEAPON_MOUNTS):
		var id := on(holder, state, m)
		if id != "":
			out[m] = id
	return out


## What's on `mount` as a loose stash entry ({"id", "count", "state"?}), or {} for none: an
## NVG keeps its charge, an underbarrel its own state (the M320's grenade).
static func entry_on(holder: ItemData, state: Dictionary, mount: String) -> Dictionary:
	var id := on(holder, state, mount)
	if id == "":
		return {}
	var out := {"id": id, "count": 1}
	if mount == "nvg":
		var n: Dictionary = state.get(Nvg.STATE_KEY, {})
		if n.has("battery_h"):
			out["state"] = {"battery_h": n.battery_h}
	elif mount in ["underbarrel", "side", "choke"]:
		var own := GunAttachments.mounted_state(state, StringName(mount))
		if not own.is_empty():
			out["state"] = own
	return out


## `state` with `entry` (a stash entry, {} for none) on `mount` of `holder`.
static func with(holder: ItemData, state: Dictionary, mount: String, entry: Dictionary) -> Dictionary:
	var id := String(entry.get("id", ""))
	var own: Dictionary = entry.get("state", {})
	match mount:
		"muzzle":
			return Suppressors.with_suppressor(state, StringName(id))
		"nvg":
			if id == "":
				return Nvg.with_nvg(state, {})
			return Nvg.with_nvg(state, {"id": id, "lowered": false, "battery_h": Nvg.battery_of(ItemDB.get_item(StringName(id)), own)})
		"optic":
			return Optics.with_optic(holder, state, StringName(id))
	return GunAttachments.with_mounted(state, StringName(mount), StringName(id), own)
