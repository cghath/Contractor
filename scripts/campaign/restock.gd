class_name Restock
extends RefCounted
## "Restock last loadout" (playtest S2: kitting up at the base took 5-12 minutes a player, with
## refusal after refusal). At deploy, each player's and each AI squadmate's kit is written down
## as a loadout (template_of), kept on their roster entry ("loadout", see Roster). Back at the
## base one button rebuilds it from the stash (build): the same carrier, plates, helmet, pack,
## the same pouches on the same MOLLE points, the same magazines and meds in the same pouches
## and containers, the same weapons with the same optic mounted. It takes what the stash has
## and lists what's missing.
##
## A loadout (JSON-safe, saved with the campaign):
## - "slots": body slot -> item id, for what's worn (Inventory.SLOTS).
## - "optics": weapon slot -> the optic mounted on that gun ("" for its irons), rail guns only.
## - "molle": attach point id -> {"id": the pouch (or knife, packed launcher), "held": [items]}:
##   the worn carrier's and pack's points.
## - "containers": "vest", "pockets", "backpack" -> [items].
## Items are {"id", "count"} (and "optic" for a stowed rail gun), merged by id. Conditions
## (rounds, chips, what's left in a kit) aren't kept: the best the stash has is drawn (full
## magazines first, undamaged plates first, full kits first).
##
## Pure functions on a stash-like pool (BaseArmory's entries, {"id", "count", "state"?}):
## build() takes from it and puts back what came off (pouches off the carrier it picked, an
## optic swapped off a gun), so nothing is made or lost. BaseHub applies the change to the
## armory's world items (server_restock_*).

const SLOT_ORDER: Array[StringName] = [&"vest", &"backpack", &"helmet", &"plate_front", &"plate_back", &"plate_left", &"plate_right",
	&"primary", &"sidearm", &"launcher"]
const CONTAINER_ORDER: Array[StringName] = [&"vest", &"pockets", &"backpack"]


# --- Recording ----------------------------------------------------------------------------

## The loadout of an Inventory.net_state (worn, on the MOLLE points, in the pouches and
## containers). Two-handed loads (a case, a crate) aren't part of a loadout.
static func template_of(gear: Dictionary) -> Dictionary:
	var slots := {}
	var optics := {}
	var molle := {}
	var slot_state: Dictionary = gear.get("slot_state", {})
	for slot: Variant in gear.get("slots", {}):
		var id := String(gear.slots[slot])
		var item := ItemDB.get_item(StringName(id)) if id != "" else null
		if item == null:
			continue
		slots[String(slot)] = id
		var state: Dictionary = slot_state.get(slot, {})
		if Optics.has_rail(item):
			optics[String(slot)] = String(Optics.mounted_id(item, state))
		var points: Dictionary = state.get("molle", {})
		for point: Variant in points:
			var att: Dictionary = points[point]
			if String(att.get("id", "")) != "":
				molle[String(point)] = {"id": String(att.id), "held": _items_of(att.get("held", []))}
	var containers := {}
	for c in CONTAINER_ORDER:
		containers[String(c)] = _items_of(gear.get("containers", {}).get(c, gear.get("containers", {}).get(String(c), [])))
	return {"slots": slots, "optics": optics, "molle": molle, "containers": containers}


## Whether a loadout holds nothing worth restocking (none recorded yet).
static func is_blank(loadout: Dictionary) -> bool:
	return loadout.get("slots", {}).is_empty() and loadout.get("molle", {}).is_empty() \
		and loadout.get("containers", {}).values().all(func(list: Array) -> bool: return list.is_empty())


## {item id: count} of everything a loadout names (optics included).
static func counts(loadout: Dictionary) -> Dictionary:
	var out := {}
	for slot: String in loadout.get("slots", {}):
		_add_count(out, String(loadout.slots[slot]), 1)
	for slot: String in loadout.get("optics", {}):
		if String(loadout.optics[slot]) != "":
			_add_count(out, String(loadout.optics[slot]), 1)
	for point: String in loadout.get("molle", {}):
		var att: Dictionary = loadout.molle[point]
		_add_count(out, String(att.id), 1)
		for it: Dictionary in att.get("held", []):
			_add_count(out, String(it.id), int(it.count))
	for c: String in loadout.get("containers", {}):
		for it: Dictionary in loadout.containers[c]:
			_add_count(out, String(it.id), int(it.count))
	return out


## Entries ({"id", "count", "state"?}) as loadout items: by id (a rail gun also by its optic),
## counts added up.
static func _items_of(entries: Array) -> Array:
	var out: Array = []
	for entry: Dictionary in entries:
		var id := String(entry.get("id", ""))
		var item := ItemDB.get_item(StringName(id)) if id != "" else null
		if item == null:
			continue
		var it := {"id": id, "count": int(entry.get("count", 1))}
		if Optics.has_rail(item):
			it["optic"] = String(Optics.mounted_id(item, entry.get("state", {})))
		var merged := false
		for o: Dictionary in out:
			if o.id == it.id and o.get("optic", "") == it.get("optic", ""):
				o["count"] = int(o.count) + int(it.count)
				merged = true
				break
		if not merged:
			out.append(it)
	return out


static func _add_count(out: Dictionary, id: String, n: int) -> void:
	if id != "" and n > 0:
		out[id] = int(out.get(id, 0)) + n


# --- Rebuilding ---------------------------------------------------------------------------

## Rebuilds `loadout` from `pool` (stash entries; taken from, and given back what comes off).
## Returns {"gear": an Inventory.net_state (JSON-safe), "missing": {item id: count} the pool
## didn't have, "no_room": {item id: count} drawn but with nowhere to go (back in the pool),
## "wanted": units the loadout names, "placed": units now on the body}.
## `caps` ({item id: units}, fair_caps): at most that many of an id are drawn, the rest is left
## in the pool for the squadmates restocked with this one (counted missing here).
static func build(loadout: Dictionary, pool: Array, caps := {}) -> Dictionary:
	var res := {"missing": {}, "no_room": {}, "wanted": 0, "placed": 0, "caps": caps.duplicate()}
	var inv := Inventory.new()
	var slots: Dictionary = loadout.get("slots", {})
	var optics: Dictionary = loadout.get("optics", {})
	# Worn things first: the carrier and the pack (their points come with them), then plates
	# (into the carrier's pockets), the helmet and the weapons with their optics.
	for slot in SLOT_ORDER:
		var id := String(slots.get(String(slot), ""))
		var item := ItemDB.get_item(StringName(id)) if id != "" else null
		if item == null:
			continue
		res.wanted += 1
		var want_optic: Variant = String(optics[String(slot)]) if optics.has(String(slot)) else null
		var entry := _draw_capped(res, pool, id, 1, want_optic, slot == &"vest" or slot == &"backpack")
		if entry.is_empty():
			_add_count(res.missing, id, 1)
			if want_optic != null and String(want_optic) != "":
				res.wanted += 1
				_add_count(res.missing, String(want_optic), 1)
			continue
		var state: Dictionary = entry.get("state", {}).duplicate(true)
		if slot == &"vest" or slot == &"backpack":
			# What's on it and in it goes back to the pool, to be drawn for the loadout's points.
			for loose: Dictionary in unpack(state):
				BaseArmory.add(pool, StringName(loose.id), int(loose.count), loose.get("state", {}))
		if want_optic != null:
			state = _fit_optic(item, state, String(want_optic), pool, res)
		if inv.take(item.id, 1, state) == 0:
			BaseArmory.add(pool, item.id, 1, state)
			_add_count(res.no_room, id, 1)
		else:
			res.placed += 1
	# The points, each with the pouch it had (on another point it fits if that one isn't there).
	var molle: Dictionary = loadout.get("molle", {})
	var landed := {}  # loadout point -> the point it went on
	for point: String in molle:
		var att: Dictionary = molle[point]
		var id := String(att.id)
		var item := ItemDB.get_item(StringName(id))
		if item == null:
			continue
		res.wanted += 1
		var entry := _draw_capped(res, pool, id, 1)
		if entry.is_empty():
			_add_count(res.missing, id, 1)
			continue
		var state: Dictionary = entry.get("state", {})
		if Inventory.is_pouch(item):  # its old contents go back; the loadout's are drawn below
			for loose: Dictionary in unpack(state):
				BaseArmory.add(pool, StringName(loose.id), int(loose.count), loose.get("state", {}))
			state = {}
		var on := StringName(point) if inv.attach_problem(item, StringName(point)) == "" else inv.free_point_for(item)
		if on == &"" or not inv.attach(on, {"id": item.id, "state": state}):
			BaseArmory.add(pool, item.id, 1, state)
			_add_count(res.no_room, id, 1)
			continue
		res.placed += 1
		landed[point] = on
	# What was in each pouch, then what was in the vest, pockets and pack.
	for point: String in molle:
		for it: Dictionary in molle[point].get("held", []):
			var into: Array[StringName] = []
			if landed.has(point):
				into.append(Inventory.pouch_container(landed[point]))
			_fill(inv, pool, it, into, res)
	var containers: Dictionary = loadout.get("containers", {})
	for c in CONTAINER_ORDER:
		for it: Dictionary in containers.get(String(c), []):
			_fill(inv, pool, it, [c], res)
	var gear: Dictionary = Roster.json_safe(inv.net_state.duplicate(true))
	inv.free()
	res["gear"] = gear
	res.erase("caps")
	return res


## draw() within what `res.caps` still allows of `id` (no cap: as many as asked).
static func _draw_capped(res: Dictionary, pool: Array, id: String, count: int, want_optic: Variant = null, carrier := false) -> Dictionary:
	var caps: Dictionary = res.get("caps", {})
	var n := mini(count, int(caps[id])) if caps.has(id) else count
	var entry := draw(pool, id, n, want_optic, carrier)
	if caps.has(id) and not entry.is_empty():
		caps[id] = int(caps[id]) - int(entry.count)
	return entry


## Medic restock left short (S0736, S0743): restocked one after the other, the first squadmates
## took the IVs, saline and epinephrine the last (often the medic) needed. Where `pool` can't
## fill every loadout of `loadouts` (in the order given: the caller puts medics first), an id's
## units are dealt out one at a time round the squad (everyone's first before anyone's second),
## so the shortfall is shared. Returns one {item id: units} cap per loadout (only the scarce
## ids; for build). What's on and in the pool's carriers and pouches, and the optics on its
## guns, count as there.
static func fair_caps(loadouts: Array, pool: Array) -> Array[Dictionary]:
	var wants: Array[Dictionary] = []
	var total := {}
	for loadout: Dictionary in loadouts:
		var c := counts(loadout)
		wants.append(c)
		for id: String in c:
			total[id] = int(total.get(id, 0)) + int(c[id])
	var have := BaseArmory.counts(pool)
	var inside := BaseArmory.contents_counts(pool)
	for id: String in inside:
		have[id] = int(have.get(id, 0)) + int(inside[id])
	for entry: Dictionary in pool:
		var item := ItemDB.get_item(StringName(String(entry.id)))
		if item and Optics.has_rail(item):
			_add_count(have, String(Optics.mounted_id(item, entry.get("state", {}))), int(entry.count))
	var out: Array[Dictionary] = []
	for i in loadouts.size():
		out.append({})
	for id: String in total:
		var left := int(have.get(id, 0))
		if int(total[id]) <= left:
			continue
		for i in loadouts.size():
			if wants[i].has(id):
				out[i][id] = 0
		var dealt := true
		while left > 0 and dealt:
			dealt = false
			for i in loadouts.size():
				if left > 0 and int(out[i].get(id, -1)) >= 0 and int(out[i][id]) < int(wants[i].get(id, 0)):
					out[i][id] = int(out[i][id]) + 1
					left -= 1
					dealt = true
	return out


## Draws `it` ({"id", "count", "optic"?}) from the pool into `into` (in order), then anywhere it
## fits; what fits nowhere goes back to the pool (no_room).
static func _fill(inv: Inventory, pool: Array, it: Dictionary, into: Array[StringName], res: Dictionary) -> void:
	var id := String(it.get("id", ""))
	var item := ItemDB.get_item(StringName(id)) if id != "" else null
	if item == null:
		return
	var want := int(it.get("count", 1))
	res.wanted += want
	var left := want
	var want_optic: Variant = String(it.optic) if it.has("optic") else null
	while left > 0:
		var entry := _draw_capped(res, pool, id, left, want_optic)
		if entry.is_empty():
			_add_count(res.missing, id, left)
			return
		var state: Dictionary = entry.get("state", {})
		var n := int(entry.count)
		var put := 0
		for c in into:
			if put >= n or not inv.containers.has(c):
				continue
			var room := mini(n - put, inv.room_for(c, item, state))
			if room > 0 and inv.insert_entry(c, {"id": item.id, "count": room, "state": state}):
				put += room
		if put < n:
			put += inv.take(item.id, n - put, state)
		res.placed += put
		left -= n
		if put < n:
			BaseArmory.add(pool, item.id, n - put, state)
			_add_count(res.no_room, id, n - put)
			if left > 0:  # the rest wouldn't fit either: left in the pool, or missing from it
				var there := mini(left, BaseArmory.count_of(pool, item.id))
				_add_count(res.no_room, id, there)
				_add_count(res.missing, id, left - there)
			return


## A gun's optic made the loadout's: the one wanted drawn and mounted (the one it had goes to
## the pool), or taken off for irons. With none to draw, it keeps what it has (missing).
static func _fit_optic(item: ItemData, state: Dictionary, want: String, pool: Array, res: Dictionary) -> Dictionary:
	if not Optics.has_rail(item):
		return state
	var on := String(Optics.mounted_id(item, state))
	if want != "":
		res.wanted += 1
	if on == want:
		if want != "":
			res.placed += 1
		return state
	if want != "":
		var optic := _draw_capped(res, pool, want, 1)
		if optic.is_empty():
			_add_count(res.missing, want, 1)
			return state
		res.placed += 1
	if on != "":
		BaseArmory.add(pool, StringName(on), 1)
	return Optics.with_optic(item, state, StringName(want))


## What sits on and in a carrier's or pack's (or a pouch's) state, as entries, taken out of it:
## its attachments (a packed launcher with its own state), the pouches' contents, a pack's.
static func unpack(state: Dictionary) -> Array:
	var out: Array = []
	var molle: Dictionary = state.get("molle", {})
	for point: Variant in molle:
		var att: Dictionary = molle[point]
		if String(att.get("id", "")) != "":
			var e := {"id": String(att.id), "count": 1}
			if not att.get("state", {}).is_empty():
				e["state"] = att.state
			out.append(e)
		out.append_array(att.get("held", []))
	out.append_array(state.get("held", []))
	state.erase("molle")
	state.erase("held")
	return out


## Takes up to `count` units of `id` out of the pool, the best first, and returns them as one
## entry ({"id", "count", "state"?}), or {} if there are none. Items whose state doesn't stack
## (a plate, a gun, an opened kit) come one at a time. `want_optic` (a rail gun): one with that
## optic first. `carrier`: a carrier or pack with the most on it first (its pouches come with it).
static func draw(pool: Array, id: String, count: int, want_optic: Variant = null, carrier := false) -> Dictionary:
	var item := ItemDB.get_item(StringName(id))
	if item == null or count <= 0:
		return {}
	var best: Dictionary = {}
	var best_score := -INF
	for entry: Dictionary in pool:
		if String(entry.id) != id or int(entry.count) <= 0:
			continue
		var s := score(item, entry.get("state", {}), want_optic, carrier)
		if s > best_score:
			best = entry
			best_score = s
	if best.is_empty():
		return {}
	var state: Dictionary = best.get("state", {})
	var n := mini(count, int(best.count))
	if not state.is_empty() and item.type != "ammo":
		n = 1
	best["count"] = int(best.count) - n
	if int(best.count) <= 0:
		pool.erase(best)
	var out := {"id": item.id, "count": n}
	if not state.is_empty():
		out["state"] = state.duplicate(true)
	return out


## How good a unit of `item` with `state` is to draw: undamaged armour, full magazines and kits,
## a loaded gun, the optic wanted, a carrier with its pouches.
static func score(item: ItemData, state: Dictionary, want_optic: Variant = null, carrier := false) -> float:
	var s := 0.0
	if want_optic != null and Optics.has_rail(item) and String(Optics.mounted_id(item, state)) == String(want_optic):
		s += 1000.0
	if item.is_voxel_armor():
		if ArmorRules.is_shattered(state):
			s -= 500.0
		s += 100.0 * ArmorRules.integrity(state) - float(state.get("chips", []).size())
	var full := item.magazine_rounds()
	if item.type == "ammo" and full > 0:
		s += 100.0 * float(state.get("rounds", full)) / full
	if Inventory.is_kit(item):
		var all := 0
		for n: Variant in Inventory.kit_contents(item, {}).values():
			all += int(n)
		var left := 0
		for n: Variant in Inventory.kit_contents(item, state).values():
			left += int(n)
		s += 100.0 * left / maxi(all, 1)
	if item.type == "weapon" and state.has("rounds"):
		s += 10.0 * minf(float(state.rounds) / maxf(float(item.default_state().get("rounds", 1)), 1.0), 1.0)
	if carrier:
		s += float(state.get("molle", {}).size())
	return s


# --- Reporting ----------------------------------------------------------------------------

## "Restocked Hawk: 31 of 35. Missing: 5.56 Mag x3, Holo Sight. No room: ..." for the player.
static func report_text(who: String, res: Dictionary) -> String:
	var text := "Restocked %s: %d of %d" % [who, int(res.get("placed", 0)), int(res.get("wanted", 0))]
	var missing := list_text(res.get("missing", {}))
	if missing != "":
		text += ". Missing from the stash: " + missing
	var no_room := list_text(res.get("no_room", {}))
	if no_room != "":
		text += ". No room for: " + no_room
	return text + ("" if missing != "" or no_room != "" else ". Nothing missing")


## What a member ended up without after a restock ({item id: units}): missing from the stash
## (or left for a squadmate) and drawn but with no room on them (Roster "restock_short").
static func short_of(res: Dictionary) -> Dictionary:
	var out := {}
	for key: String in ["missing", "no_room"]:
		var by_id: Dictionary = res.get(key, {})
		for id: Variant in by_id:
			_add_count(out, String(id), int(by_id[id]))
	return out


## "5.56 Mag x3, Holo Sight" ({item id: count}, by id).
static func list_text(counts_by_id: Dictionary) -> String:
	var ids := counts_by_id.keys().filter(func(id: Variant) -> bool: return int(counts_by_id[id]) > 0)
	ids.sort()
	var parts := PackedStringArray()
	for id: Variant in ids:
		var item := ItemDB.get_item(StringName(String(id)))
		var n := int(counts_by_id[id])
		parts.append("%s%s" % [item.name if item else String(id), " x%d" % n if n > 1 else ""])
	return ", ".join(parts)


## A stash entry's key for comparing stashes unit by unit: its id and its state as the stash
## keeps it (BaseArmory.add: an item in its default state counts as plain).
static func stash_key(id: StringName, state: Dictionary) -> String:
	var item := ItemDB.get_item(id)
	var s := state
	if item and not s.is_empty() and item.type != "ammo" and Roster.json_safe(s) == Roster.json_safe(item.default_state()):
		s = {}
	return "%s|%s" % [String(id), JSON.stringify(GameState.from_json(Roster.json_safe(s)), "", true)]  # 30.0 and 30 alike


## {stash_key: units} over stash entries.
static func stash_units(stash: Array) -> Dictionary:
	var out := {}
	for entry: Dictionary in stash:
		var key := stash_key(StringName(String(entry.id)), entry.get("state", {}))
		out[key] = int(out.get(key, 0)) + int(entry.count)
	return out
