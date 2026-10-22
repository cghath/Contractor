class_name Loadouts
extends RefCounted
## The loadout menu's rules (Captain, 2026-10-14: "we need a menu for equipping yourself better
## and your squadmates how you want to as well"; docs/loadout_menu.md). Pure functions on
## Restock's loadout templates ({"slots", "optics", "molle", "containers"}) and stash-like pools.
##
## Every change to someone's kit is an edit of the template of what they wear now (set a slot,
## an optic, add or take away units, fill ammo, a medic kit, a role kit), rebuilt from one pool
## (rebuild): their kit goes into it with the stash first and Restock.build draws the edited
## template from it, so nothing is made or lost and what the stash hasn't got is listed in
## Restock's words. BaseHub.server_loadout applies the result to the bodies and the armory.

## Fill ammo: magazines for a gun when the role kit names none of its magazine (Proposed).
const FILL_MAGS := {&"primary": 6, &"sidearm": 2}
## The stash's "+5" button (ammo and medical; Proposed).
const BULK := 5
## The menu's groups, in order (group_of).
const GROUPS: Array[String] = ["weapons", "optics", "armor", "packs", "pouches", "ammo", "medical", "grenades", "other"]
const GROUP_NAMES := {"weapons": "Weapons", "optics": "Optics", "armor": "Armour", "packs": "Packs", "pouches": "Pouches",
	"ammo": "Ammo and mags", "medical": "Medical", "grenades": "Grenades", "other": "Other"}
## The worn slots the paper doll shows, in order.
const DOLL_SLOTS: Array[StringName] = [&"primary", &"sidearm", &"launcher", &"helmet", &"vest", &"plate_front", &"plate_back",
	&"plate_left", &"plate_right", &"backpack"]
const SLOT_NAMES := {&"primary": "Primary", &"sidearm": "Sidearm", &"launcher": "Launcher", &"helmet": "Helmet", &"vest": "Carrier",
	&"plate_front": "Front plate", &"plate_back": "Back plate", &"plate_left": "Left side plate", &"plate_right": "Right side plate",
	&"backpack": "Pack"}
## Pouches the medic kit hangs on (its medical items go in them first).
const MEDIC_POUCHES: Array[String] = ["aid_bag", "pouch_sustainment"]
## A MOLLE entry's point id when it has none yet: Restock.build hangs it on a free point it fits.
const NEW_POINT := "+"


static func group_of(item: ItemData) -> String:
	if item == null:
		return "other"
	if item.type == "weapon" or item.type == "launcher":
		return "weapons"
	if Optics.is_optic(item):
		return "optics"
	if item.slot == &"backpack":
		return "packs"
	if item.type == "armor" or item.type == "plate":
		return "armor"
	if Inventory.is_attachable(item):
		return "pouches"
	if item.type == "ammo":
		return "ammo"
	if item.type == "medical":
		return "medical"
	if "throwable" in item.tags or ("explosive" in item.tags and not "mortar_round" in item.tags) or "incendiary" in item.tags or "detonator" in item.tags:
		return "grenades"  # and explosives: charges, demo blocks, mines, thermite, firing devices (Demolitions)
	return "other"


## Whether `item` can be put in body slot `slot` from the menu (a plate in a pocket of the
## kind, a gun in its own slot). Whether the carrier takes it is the rebuild's to say.
static func fits_slot(item: ItemData, slot: StringName) -> bool:
	if item == null:
		return false
	if slot in [&"plate_front", &"plate_back"]:
		return item.slot == &"plate"
	if slot in [&"plate_left", &"plate_right"]:
		return item.slot == &"side_plate"
	return item.slot == slot


# --- Template edits (each returns an edited copy) ----------------------------------------

## The template of what `gear` (an Inventory.net_state, JSON-safe) wears and carries.
static func template_of(gear: Dictionary) -> Dictionary:
	return Restock.template_of(gear)


## `slot` holds `id` ("": empty, back to the stash). A carrier or pack taken off takes its
## points and what's in it to the stash too (a carrier its plates); a gun swapped for another
## with a rail keeps the optic asked for.
static func set_slot(t: Dictionary, slot: StringName, id: String) -> Dictionary:
	var out := _copy(t)
	var old := String(out.slots.get(String(slot), ""))
	if id == "":
		out.slots.erase(String(slot))
		out.optics.erase(String(slot))
		if out.has("mounts"):
			out.mounts.erase(String(slot))
		if slot == &"vest" or slot == &"backpack":
			_drop_points(out, old)
			out.containers[String(slot)] = []
			if slot == &"vest":
				for p in Inventory.PLATE_SLOTS:
					out.slots.erase(String(p))
		return out
	out.slots[String(slot)] = id
	var item := ItemDB.get_item(StringName(id))
	if item == null or not Optics.has_rail(item):
		out.optics.erase(String(slot))
	if old != id and out.has("mounts"):
		var kept := {}
		for m: String in out.mounts.get(String(slot), {}):
			if GearMounts.fits(item, m, ItemDB.get_item(StringName(String(out.mounts[String(slot)][m])))):
				kept[m] = out.mounts[String(slot)][m]
		out.mounts[String(slot)] = kept
	return out


## The holder in `slot` (a gun, the helmet) carries `id` on `mount` ("" takes it off; GearMounts).
## From here on the template names every mount of that holder (what it doesn't name comes off).
static func set_mount(t: Dictionary, slot: StringName, mount: String, id: String) -> Dictionary:
	var out := _copy(t)
	var holder := ItemDB.get_item(StringName(String(out.slots.get(String(slot), ""))))
	if holder == null or (mount != "optic" and not (mount in GearMounts.mounts_for(holder))):
		return out
	if mount == "optic":
		return set_optic(out, slot, id)
	if id != "" and not GearMounts.fits(holder, mount, ItemDB.get_item(StringName(id))):
		return out
	if not out.has("mounts"):
		out["mounts"] = {}
	var now: Dictionary = out.mounts.get(String(slot), {})
	if id == "":
		now.erase(mount)
	else:
		now[mount] = id
	out.mounts[String(slot)] = now
	return out


## The gun in `slot` carries optic `optic` ("" for its irons; the one it had goes to the stash).
static func set_optic(t: Dictionary, slot: StringName, optic: String) -> Dictionary:
	var out := _copy(t)
	var gun := ItemDB.get_item(StringName(String(out.slots.get(String(slot), ""))))
	if gun != null and Optics.has_rail(gun):
		out.optics[String(slot)] = optic
	return out


## Attach point `point` holds pouch `id` ("" takes it off): what the old one held stays in the
## new one if it takes it, else goes in the carrier (or the pockets).
static func set_point(t: Dictionary, point: String, id: String) -> Dictionary:
	var out := _copy(t)
	var held: Array = (out.molle.get(point, {}) as Dictionary).get("held", [])
	out.molle.erase(point)
	var into := "vest" if out.slots.has("vest") else "pockets"
	var pouch := ItemDB.get_item(StringName(id)) if id != "" else null
	var keep: Array = []
	for it: Dictionary in held:
		var item := ItemDB.get_item(StringName(String(it.id)))
		if pouch != null and Inventory.is_pouch(pouch) and item != null and Inventory.pouch_accepts(pouch, item):
			keep.append(it)
		else:
			_merge(out.containers[into], String(it.id), int(it.count))
	if pouch != null:
		out.molle[point] = {"id": id, "held": keep}
	return out


## `n` more of `id`: a pouch or a knife onto a free point it fits, anything else into the first
## pouch made for it (or taking its type), else the carrier, the pack or the pockets. What has
## no room there goes wherever it fits when it's rebuilt (Restock._fill).
static func add_units(t: Dictionary, id: String, n: int) -> Dictionary:
	var out := _copy(t)
	var item := ItemDB.get_item(StringName(id))
	if item == null or n <= 0:
		return out
	if Inventory.is_attachable(item):
		for i in n:
			var k := 0
			while out.molle.has("%s%s_%d" % [NEW_POINT, id, k]):
				k += 1
			out.molle["%s%s_%d" % [NEW_POINT, id, k]] = {"id": id, "held": []}
		return out
	var into: Array = []
	for made_for: bool in [true, false]:
		for point: String in out.molle:
			var pouch := ItemDB.get_item(StringName(String(out.molle[point].id)))
			if into.is_empty() and pouch != null and Inventory.pouch_accepts(pouch, item) and (id in pouch.stats.get("accepts", [])) == made_for:
				into = out.molle[point].held
	if into.is_empty() or item.slot != &"":
		var c := "vest" if out.slots.has("vest") else ("backpack" if out.slots.has("backpack") else "pockets")
		into = out.containers[c]
	_merge(into, id, n)
	return out


## Up to `n` fewer of `id` (from the pack, pockets and carrier first, then the pouches; a pouch
## taken off leaves what it held in the carrier). Returns {"template", "removed"}.
static func remove_units(t: Dictionary, id: String, n: int) -> Dictionary:
	var out := _copy(t)
	var left := n
	for c: String in ["backpack", "pockets", "vest"]:
		left -= _take_from(out.containers.get(c, []), id, left)
	for point: String in out.molle.keys():
		left -= _take_from(out.molle[point].held, id, left)
	for point: String in out.molle.keys():
		if left > 0 and String(out.molle[point].id) == id:
			for it: Dictionary in out.molle[point].held:
				_merge(out.containers["vest" if out.slots.has("vest") else "pockets"], String(it.id), int(it.count))
			out.molle.erase(point)
			left -= 1
	for slot: String in out.slots.keys():
		if left > 0 and String(out.slots[slot]) == id:
			out = set_slot(out, StringName(slot), "")
			left -= 1
	return {"template": out, "removed": n - left}


## Each gun's magazines up to what the role kit carries of them (FILL_MAGS when it names
## none); never fewer than are there.
static func fill_ammo(t: Dictionary, role: StringName) -> Dictionary:
	var out := _copy(t)
	var kit := {}
	for pair: Array in Roles.kit(role):
		kit[String(pair[0])] = int(kit.get(String(pair[0]), 0)) + int(pair[1])
	for slot: StringName in FILL_MAGS:
		var gun := ItemDB.get_item(StringName(String(out.slots.get(String(slot), ""))))
		var ammo := String(gun.stats.get("ammo", "")) if gun else ""
		if ammo == "" or not ItemDB.has_item(StringName(ammo)):
			continue
		var want := int(kit.get(ammo, FILL_MAGS[slot]))
		var have := int(Restock.counts(out).get(ammo, 0))
		if want > have:
			out = add_units(out, ammo, want - have)
	return out


## The medic role kit's medical items, its aid bag and sustainment pouch, up to its counts
## (pouches first, so the items go in them).
static func medic_kit(t: Dictionary) -> Dictionary:
	var out := _copy(t)
	var want := {}
	for pair: Array in Roles.kit(Roles.MEDIC):
		var id := String(pair[0])
		var item := ItemDB.get_item(StringName(id))
		if item and (item.type == "medical" or id in MEDIC_POUCHES):
			want[id] = int(want.get(id, 0)) + int(pair[1])
	for pouches: bool in [true, false]:
		for id: String in want:
			if (id in MEDIC_POUCHES) != pouches:
				continue
			var have := int(Restock.counts(out).get(id, 0))
			if int(want[id]) > have:
				out = add_units(out, id, int(want[id]) - have)
	return out


## A role's kit (Roles.kit) as a template, as it's worn when handed out new.
static func role_template(role: StringName) -> Dictionary:
	return Restock.template_of(Roster.gear_for_kit(Roles.kit(role)))


# --- Rebuilding from the stash -------------------------------------------------------------

## `people` ([{"gear": an Inventory.net_state, JSON-safe, "template"}]) rebuilt from one pool:
## `pool` (stash entries; changed in place) with everyone's kit in it first, each drawn in
## order (Restock.build). Returns one Restock.build result each ("gear", "missing", "no_room",
## ...). Nothing is made or lost: the units in the pool and the gears before are the ones after.
static func rebuild(people: Array, pool: Array) -> Array:
	for p: Dictionary in people:
		var own := Inventory.new()
		own.net_state = GameState.from_json(p.gear)
		# Unpacked: what's on and in their own carrier, pack and pouches goes in loose. Left
		# packed, it could only be drawn with that same carrier, and a rebuild that drew another
		# (the stash's, with more pouches) left the medic's own IVs locked in his (R0976).
		for e: Dictionary in own.strip():
			var state: Dictionary = e.get("state", {}).duplicate(true)
			for loose: Dictionary in Restock.unpack(state):
				BaseArmory.add(pool, StringName(String(loose.id)), int(loose.count), loose.get("state", {}))
			BaseArmory.add(pool, StringName(String(e.id)), int(e.count), state)
		own.free()
	var out: Array = []
	for p: Dictionary in people:
		out.append(Restock.build(p.template, pool))
	return out


## What a change left out, in Restock's words: "Missing from the stash: ..., No room for: ..."
## ("" when nothing).
static func short_text(res: Dictionary) -> String:
	var parts := PackedStringArray()
	var missing := Restock.list_text(res.get("missing", {}))
	if missing != "":
		parts.append("Missing from the stash: " + missing)
	var no_room := Restock.list_text(res.get("no_room", {}))
	if no_room != "":
		parts.append("No room for: " + no_room)
	return ". ".join(parts)


## {"kg", "tier"} of `gear` (MovementRules.Tier).
static func load_of(gear: Dictionary) -> Dictionary:
	var inv := Inventory.new()
	inv.net_state = GameState.from_json(gear.duplicate(true))
	var kg := inv.total_mass()
	inv.free()
	return {"kg": kg, "tier": MovementRules.tier_of(kg)}


static func tier_name(tier: int) -> String:
	return ["Light", "Burdened", "Overloaded", "Critical"][clampi(tier, 0, 3)]


## Every unit in `stash` and `gears` (Inventory.net_states), item by item: what's on and in
## carriers, pouches and packs, and the optics on guns too (the conservation checks).
static func units(stash: Array, gears: Array) -> Dictionary:
	var out := {}
	for e: Dictionary in stash:
		_count_entry(e, out)
	for gear: Dictionary in gears:
		var slot_state: Dictionary = gear.get("slot_state", {})
		for slot: Variant in gear.get("slots", {}):
			var id := String(gear.slots[slot])
			if id != "":
				_count_entry({"id": id, "count": 1, "state": slot_state.get(slot, {})}, out)
		for c: Variant in gear.get("containers", {}):
			for e: Dictionary in gear.containers[c]:
				_count_entry(e, out)
		if String(gear.get("hands", "")) != "":
			_add(out, String(gear.hands), 1)
	return out


static func _count_entry(e: Dictionary, out: Dictionary) -> void:
	var n := int(e.get("count", 1))
	var id := String(e.get("id", ""))
	var state: Dictionary = e.get("state", {})
	_add(out, id, n)
	var item := ItemDB.get_item(StringName(id))
	if item and Optics.has_rail(item):
		_add(out, String(Optics.mounted_id(item, state)), n)
	var on := GearMounts.of(item, state)
	for m: String in on:
		_add(out, String(on[m]), n)
	var inside := {}
	var molle: Dictionary = state.get("molle", {})
	for point: Variant in molle:
		var att: Dictionary = molle[point]
		if String(att.get("id", "")) != "":
			_count_entry({"id": att.id, "count": 1, "state": att.get("state", {})}, inside)
		for h: Dictionary in att.get("held", []):
			_count_entry(h, inside)
	for h: Dictionary in state.get("held", []):
		_count_entry(h, inside)
	for k: String in inside:
		_add(out, k, int(inside[k]) * n)


static func _add(out: Dictionary, id: String, n: int) -> void:
	if id != "" and n > 0:
		out[id] = int(out.get(id, 0)) + n


# --- Bits ---------------------------------------------------------------------------------

## A full copy with every part there.
static func _copy(t: Dictionary) -> Dictionary:
	var out: Dictionary = Roster.json_safe(t.duplicate(true))
	for key: String in ["slots", "optics", "molle"]:
		if not out.has(key):
			out[key] = {}
	if not out.has("containers"):
		out["containers"] = {}
	for c in Restock.CONTAINER_ORDER:
		if not out.containers.has(String(c)):
			out.containers[String(c)] = []
	for point: String in out.molle:
		if not out.molle[point].has("held"):
			out.molle[point]["held"] = []
	return out


## Takes the points of carrier or pack `id` out of the template (what's on them goes to the stash).
static func _drop_points(t: Dictionary, id: String) -> void:
	var item := ItemDB.get_item(StringName(id))
	if item == null:
		return
	for p: Dictionary in item.stats.get("molle", []):
		t.molle.erase(String(p.id))


static func _merge(into: Array, id: String, n: int) -> void:
	for it: Dictionary in into:
		if String(it.id) == id and not it.has("optic"):
			it["count"] = int(it.count) + n
			return
	into.append({"id": id, "count": n})


## Up to `n` of `id` out of a template item list; returns how many.
static func _take_from(list: Array, id: String, n: int) -> int:
	var taken := 0
	for i in range(list.size() - 1, -1, -1):
		if taken >= n:
			break
		if String(list[i].id) != id:
			continue
		var k := mini(int(list[i].count), n - taken)
		list[i]["count"] = int(list[i].count) - k
		taken += k
		if int(list[i].count) <= 0:
			list.remove_at(i)
	return taken
