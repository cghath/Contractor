class_name KitLibrary
extends RefCounted
## Saved loadouts (claude/loadout-3d; Captain, 2026-10-22: "saving custom loadouts and applying
## them to units", "with the option just built in to buy what you do not own"). A kit is a
## named Restock template kept on the roster ("kits": {name: {"template", "by", "role"}}), so it
## is saved with the campaign and every player sees the same list (the roster section goes to
## every peer with the base view). Applying one makes it the standing loadout of everyone it
## goes to and rebuilds their kit from the stash together (BaseHub "kit_apply"); what the stash
## can't cover is one total (shortfall) that one click buys.
##
## Pure functions here: names, the template check for anything a client sends, who a target
## means, what a set of kits is short of, and the stats panel's numbers.

## At most this many saved kits (Proposed).
const MAX_KITS := 40
const NAME_MAX := 32
## A fire team is this many of the picked squad, in pick order (Proposed: Roles' two fire teams of four).
const TEAM_SIZE := 4
## Targets a kit can go to (resolve): one person by who, or these.
const TARGET_TEAM := "team:"
const TARGET_ROLE := "role:"
const TARGET_SQUAD := "squad"
const TARGET_HC := "hc:"


static func kits(data: Dictionary) -> Dictionary:
	if not data.has("kits"):
		data["kits"] = {}
	return data["kits"]


## A kit name as typed, cleaned: trimmed, no control characters, at most NAME_MAX.
static func clean_name(text: String) -> String:
	var out := ""
	for c in text.strip_edges():
		if c.unicode_at(0) >= 32:
			out += c
	return out.substr(0, NAME_MAX).strip_edges()


## The saved kits' names, A to Z (`data` the roster or the view's copy of it).
static func names(data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for n: Variant in data.get("kits", {}):
		out.append(String(n))
	out.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return out


static func template_of_kit(data: Dictionary, kit_name: String) -> Dictionary:
	return (data.get("kits", {}).get(kit_name, {}) as Dictionary).get("template", {})


## Saves `template` as `kit_name` (a new one, or over the old). "" or why not.
static func save(data: Dictionary, kit_name: String, template: Dictionary, by: String, role := "") -> String:
	var n := clean_name(kit_name)
	if n == "":
		return "Name the kit first"
	var t := clean_template(template)
	if Restock.is_blank(t):
		return "That kit is empty"
	var all := kits(data)
	if not all.has(n) and all.size() >= MAX_KITS:
		return "%d kits saved already: delete one first" % MAX_KITS
	all[n] = {"template": t, "by": by, "role": role}
	return ""


static func delete(data: Dictionary, kit_name: String) -> bool:
	return kits(data).erase(kit_name)


## A template from a client, made safe: only known items, slots they fit, sane counts, the
## parts Restock reads and nothing else. Anything that doesn't fit is dropped, not refused.
static func clean_template(t: Variant) -> Dictionary:
	var out := {"slots": {}, "optics": {}, "molle": {}, "containers": {}}
	for c in Restock.CONTAINER_ORDER:
		out.containers[String(c)] = []
	if not t is Dictionary:
		return out
	var src: Dictionary = t
	for slot: Variant in src.get("slots", {}):
		var item := _item(src.slots[slot])
		var s := StringName(String(slot))
		if item != null and s in Inventory.SLOTS and (Loadouts.fits_slot(item, s) or (s in Inventory.WEAPON_SLOTS and item.slot == s)):
			out.slots[String(slot)] = String(item.id)
	for slot: Variant in src.get("optics", {}):
		var gun := _item(out.slots.get(String(slot), ""))
		var optic := String(src.optics[slot])
		if gun != null and Optics.has_rail(gun) and (optic == "" or GearMounts.fits(gun, "optic", _item(optic))):
			out.optics[String(slot)] = optic
	var mounts := {}
	for slot: Variant in src.get("mounts", {}):
		var holder := _item(out.slots.get(String(slot), ""))
		if holder == null or not src.mounts[slot] is Dictionary:
			continue
		var kept := {}
		for m: Variant in src.mounts[slot]:
			if String(m) in GearMounts.mounts_for(holder) and GearMounts.fits(holder, String(m), _item(src.mounts[slot][m])):
				kept[String(m)] = String(src.mounts[slot][m])
		mounts[String(slot)] = kept
	if not mounts.is_empty():
		out["mounts"] = mounts
	for point: Variant in src.get("molle", {}):
		var att: Variant = src.molle[point]
		if not att is Dictionary or _item(att.get("id", "")) == null or out.molle.size() >= 64:
			continue
		out.molle[String(point).substr(0, 48)] = {"id": String(att.id), "held": _clean_items(att.get("held", []))}
	for c in Restock.CONTAINER_ORDER:
		out.containers[String(c)] = _clean_items(src.get("containers", {}).get(String(c), []))
	return out


static func _clean_items(list: Variant) -> Array:
	var out: Array = []
	if not list is Array:
		return out
	for it: Variant in list:
		if it is Dictionary and _item(it.get("id", "")) != null and out.size() < 64:
			var e := {"id": String(it.id), "count": clampi(int(it.get("count", 1)), 1, 99)}
			if it.has("optic"):
				e["optic"] = String(it.optic)
			out.append(e)
	return out


static func _item(id: Variant) -> ItemData:
	var s := StringName(String(id)) if id is String or id is StringName else &""
	return ItemDB.get_item(s) if s != &"" and ItemDB.has_item(s) else null


# --- Who a kit goes to ----------------------------------------------------------------------

## The people `targets` name, in order, no one twice: a person ("player:<key>" or a member id),
## TARGET_TEAM + "1"/"2" (that fire team of the picked squad), TARGET_ROLE + role (every
## squadmate in that role), TARGET_SQUAD (the picked squad), TARGET_HC + detachment id (a high
## command squad: Hawk 2, Viper 3). `data` the roster (or the view's), `picked` the squad picked
## for the next deployment (empty: every available member).
static func resolve(data: Dictionary, picked: Array, targets: Array) -> Array[String]:
	var members: Dictionary = data.get("members", {})
	var squad: Array = picked.filter(func(mid: Variant) -> bool: return members.has(mid))
	if squad.is_empty():
		squad = members.keys().filter(func(mid: Variant) -> bool:
			return Roster.is_available(members[mid]) and not Heroes.in_detachment(data, String(mid)))
		squad.sort()
	var out: Array[String] = []
	for t: Variant in targets:
		var spec := String(t)
		var add: Array = []
		if spec == TARGET_SQUAD:
			add = squad
		elif spec.begins_with(TARGET_TEAM):
			var team := spec.trim_prefix(TARGET_TEAM).to_int() - 1
			for i in squad.size():
				if i / TEAM_SIZE == team:
					add.append(squad[i])
		elif spec.begins_with(TARGET_ROLE):
			var role := spec.trim_prefix(TARGET_ROLE)
			add = squad.filter(func(mid: Variant) -> bool: return String(members[mid].get("role", "")) == role)
		elif spec.begins_with(TARGET_HC):
			var d: Dictionary = data.get("detachments", {}).get(spec.trim_prefix(TARGET_HC), {})
			add = (d.get("members", []) as Array).filter(func(mid: Variant) -> bool: return members.has(mid))
		elif spec.begins_with("player:") or members.has(spec):
			add = [spec]
		for who: Variant in add:
			if not String(who) in out:
				out.append(String(who))
	return out


## The target choices to offer: [[spec, label]], the fire teams, the roles in the picked squad,
## the whole squad and each high command squad.
static func target_choices(data: Dictionary, picked: Array) -> Array:
	var out: Array = [[TARGET_SQUAD, "Whole squad"], [TARGET_TEAM + "1", "Fire team 1"], [TARGET_TEAM + "2", "Fire team 2"]]
	var roles: Array[String] = []
	var members: Dictionary = data.get("members", {})
	for mid: String in resolve(data, picked, [TARGET_SQUAD]):
		var r := String(members[mid].get("role", ""))
		if r != "" and not r in roles:
			roles.append(r)
	roles.sort()
	for r: String in roles:
		out.append([TARGET_ROLE + r, "Every %s" % Roles.display_name(StringName(r)).to_lower()])
	var dets: Dictionary = data.get("detachments", {})
	var ids := dets.keys()
	ids.sort()
	for did: Variant in ids:
		out.append([TARGET_HC + String(did), "%s (high command)" % String(dets[did].get("callsign", did))])
	return out


# --- What it costs ---------------------------------------------------------------------------

## What the stash is short of to put `jobs` ([{"gear": an Inventory.net_state, "template"}]) on
## everyone at once, each one's kit going into the stash first (Loadouts.rebuild on copies):
## {"missing": {id: units} all told, "each": [{id: units}], "cost", "units", "unbuyable"}.
static func shortfall(jobs: Array, stash: Array) -> Dictionary:
	var pool: Array = stash.duplicate(true)
	var copies: Array = jobs.map(func(j: Dictionary) -> Dictionary: return {"gear": j.get("gear", {}).duplicate(true), "template": j.template})
	var each: Array = []
	var all := {}
	for res: Dictionary in Loadouts.rebuild(copies, pool):
		var m := {}
		for id: Variant in res.get("missing", {}):
			if int(res.missing[id]) > 0:
				m[String(id)] = int(res.missing[id])
				all[String(id)] = int(all.get(String(id), 0)) + int(res.missing[id])
		each.append(m)
	var price := BaseHub.missing_cost(all)
	return {"missing": all, "each": each, "cost": int(price.cost), "units": int(price.units), "unbuyable": price.unbuyable}


# --- The stats panel ---------------------------------------------------------------------------

## The numbers the editor shows for `gear` (an Inventory.net_state): {"kg", "tier", "speed"
## (MovementRules.load_speed_mult), "litres", "litres_used", "protection": [[slot name, item name,
## rating]], "ammo": [[gun name, mags, rounds]]}.
static func stats_of(gear: Dictionary) -> Dictionary:
	var inv := Inventory.new()
	inv.net_state = GameState.from_json(gear.duplicate(true))
	var kg := inv.total_mass()
	var litres := 0.0
	var used := 0.0
	for c in Inventory.CONTAINERS:
		litres += inv.capacity(c)
		used += inv.used(c)
	var protection: Array = []
	for slot: StringName in [&"helmet", &"plate_front", &"plate_back", &"plate_left", &"plate_right"]:
		var id: StringName = inv.slots.get(slot, &"")
		if id != &"":
			var item := ItemDB.get_item(id)
			var rating := String(ArmorRules.rating(item))
			protection.append([String(Loadouts.SLOT_NAMES.get(slot, slot)), item.name, rating if rating != "" else "-"])
	var counts := Roster.gear_counts(Roster.json_safe(inv.net_state))
	var ammo: Array = []
	for slot: StringName in Inventory.WEAPON_SLOTS:
		var gun_id: StringName = inv.slots.get(slot, &"")
		var gun := ItemDB.get_item(gun_id) if gun_id != &"" else null
		var mag := String(gun.stats.get("ammo", "")) if gun else ""
		if mag == "" or not ItemDB.has_item(StringName(mag)):
			continue
		var n := int(counts.get(mag, 0))
		ammo.append([gun.name, n, n * int(ItemDB.get_item(StringName(mag)).stats.get("rounds", 0))])
	inv.free()
	return {"kg": kg, "tier": MovementRules.tier_of(kg), "speed": MovementRules.load_speed_mult(kg), "litres": litres,
		"litres_used": used, "protection": protection, "ammo": ammo}
