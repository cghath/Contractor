class_name CompanionGear
extends RefCounted
## The gear editor's rules on the host (docs/survival_clothing.md, calls 133-134): give and take
## gear between a survivor and a companion (or move it about your own kit), into any place: a body
## slot (the gear's and the clothing slots), a MOLLE point, or INTO a container: the pockets (the
## clothes' pockets add to them), the vest, the backpack, a pouch on the carrier or the pack
## ("molle:<point>"). The capacity rules are Inventory's own (room_for, attach_problem,
## fit_problem); what doesn't go in goes back where it came from, and the actor is told why.
## Saved kits (the world's "gear_kits": a name -> a template) apply to a companion from what the
## giver carries. LoadoutGear (the screen) sends these through SurvivorsLayer.request_talk
## ("gear"); TalkMenu.server_talk hands them here.
##
## A place is a String: "auto" (wherever it goes: Inventory.take), "slot:<slot>", "point:<point
## id>", "container:<container>" (pockets, vest, backpack, molle:<point>).

## How close a companion must be (InteractionMenu.REACH, with the talk menu's slack).
const REACH_M := 4.5
const KITS_KEY := "gear_kits"
const KITS_MAX := 30


## Whether `actor` may edit `target`'s kit: his own, or a companion's (or a settler's) on their
## feet within REACH_M.
static func may_edit(actor: Soldier, target: Soldier) -> String:
	if actor == null or target == null or not is_instance_valid(target):
		return "Nobody there"
	if actor == target:
		return ""
	var layer := SurvivorsLayer.find(target)
	var status: String = String(layer.info_of(target).get("status", "")) if layer else ""
	if status not in ["companion", "settler"]:
		return "Only your own people take gear from you"
	if not target.vitals.is_up():
		return "%s can't take anything now" % target.display_name()
	if actor.global_position.distance_to(target.global_position) > REACH_M:
		return "Too far from %s" % target.display_name()
	return ""


## Host: one editor op from `actor` on `target`'s kit ({"op": "give" | "take" | "move" |
## "kit_save" | "kit_apply" | "info", ...}). "" done, else why not (the actor is told).
static func server_op(actor: Soldier, target: Soldier, op: Dictionary) -> String:
	var why := may_edit(actor, target)
	if why == "":
		match String(op.get("op", "")):
			"give":
				why = transfer(actor.inventory, String(op.get("from", "")), int(op.get("index", -1)), target.inventory, String(op.get("to", "auto")))
			"take":
				why = transfer(target.inventory, String(op.get("from", "")), int(op.get("index", -1)), actor.inventory, String(op.get("to", "auto")), false)
			"move":
				why = transfer(target.inventory, String(op.get("from", "")), int(op.get("index", -1)), target.inventory, String(op.get("to", "auto")))
			"kit_save":
				why = save_kit(String(op.get("name", "")), target.inventory)
			"kit_apply":
				var got := apply_kit(actor.inventory, target.inventory, kit(String(op.get("name", ""))))
				why = "" if (got.missing as Array).is_empty() else "Not carried: %s" % ", ".join(PackedStringArray(got.missing))
			"info":
				_send_info(actor, target)
				return ""
			_:
				why = "Unknown"
	_after(target)
	if why != "":
		Survival._tell(actor, why)
	return why


## Host: the companion's record keeps up with their kit.
static func _after(target: Soldier) -> void:
	var layer: SurvivorsLayer = SurvivorsLayer.find(target) if target else null
	if layer == null:
		return
	var rec := layer.record_of(target)
	if not rec.is_empty():
		rec.kit = Survival.kit_of(target.inventory)


# --- Moving one thing ---------------------------------------------------------------------------

## Host: one unit from `from` (a place; `index` for a container's entry) of `src` into `to` of
## `dst` (src and dst may be the same inventory). "" done, else why not (it stays where it was).
static func transfer(src: Inventory, from: String, index: int, dst: Inventory, to: String, wear_free := true) -> String:
	if src == null or dst == null:
		return "Nothing there"
	var entry := take_out(src, from, index)
	if entry.is_empty():
		var kind := from.get_slice(":", 0)
		if kind == "slot" and StringName(src.slots.get(StringName(from.get_slice(":", 1)), &"")) != &"":
			return "It won't come off now (empty it first)"
		return "Nothing there"
	var why := put_in(dst, entry, to, wear_free)
	if why != "":
		put_back(src, entry, from)
	return why


## Host: one unit out of `place` of `inv` as an entry ({"id", "count": 1, "state"?}), or {}.
static func take_out(inv: Inventory, place: String, index := -1) -> Dictionary:
	var kind := place.get_slice(":", 0)
	var what := StringName(place.substr(kind.length() + 1))
	match kind:
		"slot":
			var off := inv.unequip(what)
			if off.is_empty():
				return {}
			var e := {"id": StringName(off.id), "count": 1}
			if not (off.get("state", {}) as Dictionary).is_empty():
				e.state = off.state
			return e
		"point":
			return inv.detach(what)
		"container":
			return inv.remove_entry(what, index, 1)
	return {}


## Host: `entry` into `place` of `inv`. "" done, else why not (nothing changed). `wear_free`: an
## "auto" place puts clothes on when their slot is free (giving to someone); false stows them
## (taking back: what you take goes in your pack, so a saved kit can find it).
static func put_in(inv: Inventory, entry: Dictionary, place: String, wear_free := true) -> String:
	var item := ItemDB.get_item(StringName(String(entry.get("id", ""))))
	if item == null:
		return "Nothing there"
	var state: Dictionary = entry.get("state", {})
	var kind := place.get_slice(":", 0)
	var what := StringName(place.substr(kind.length() + 1))
	match kind:
		"slot":
			return _wear(inv, item, state, what)
		"point":
			return "" if inv.attach(what, entry) else inv.attach_problem(item, what)
		"container":
			if not inv.containers.has(what):
				return "No %s" % String(what).capitalize()
			return "" if inv.insert_entry(what, {"id": item.id, "count": 1, "state": state} if not state.is_empty() else {"id": item.id, "count": 1}) else inv.refusal(item, state, what)
	if not wear_free and Clothing.slot_of(item) != &"":  # taken-back clothes go in a container, not on
		var one: Dictionary = {"id": item.id, "count": 1, "state": state} if not state.is_empty() else {"id": item.id, "count": 1}
		for c: StringName in inv.stow_order(item):
			if inv.insert_entry(c, one.duplicate(true)):
				return ""
		# (no room anywhere: worn if its slot is free, as before)
	var was := Clothing.force
	Clothing.force = true  # (given clothes go on when their slot is free)
	var took := inv.take(item.id, 1, state)
	Clothing.force = was
	return "" if took == 1 else inv.refusal(item, state)


## Host: `item` worn in `slot` of `inv` (a clothing slot by its layer, a gear slot by the item's
## own slot and Inventory's rules). "" done, else why not.
static func _wear(inv: Inventory, item: ItemData, state: Dictionary, slot: StringName) -> String:
	if not inv.slots.has(slot):
		return "No such slot"
	if StringName(inv.slots[slot]) != &"":
		return "Take off the %s first" % ItemDB.get_item(inv.slots[slot]).name
	if slot in Inventory.CLOTHING_SLOTS:
		if Clothing.slot_of(item) != slot:
			return "%s doesn't go on the %s" % [item.name, String(Clothing.NAMES.get(slot, slot)).to_lower()]
	else:
		var why := inv.fit_problem(item)
		if why != "":
			return why
		var fits := item.slot == slot or (item.is_plate() and slot in inv.carrier_plate_slots() and (slot in [&"plate_left", &"plate_right"]) == (item.slot == &"side_plate"))
		if not fits:
			return "%s doesn't go in the %s slot" % [item.name, String(slot).replace("_", " ")]
	inv.put_on(slot, item.id, state)
	return ""


## Host: `entry` back where it came from (a refused move), wherever it can go if not there.
static func put_back(inv: Inventory, entry: Dictionary, place: String) -> void:
	var kind := place.get_slice(":", 0)
	var what := StringName(place.substr(kind.length() + 1))
	var ok := false
	match kind:
		"slot":
			ok = inv.put_on(what, StringName(entry.id), entry.get("state", {}))
		"point":
			ok = inv.attach(what, entry)
		"container":
			ok = inv.insert_entry(what, entry)
	if not ok:
		inv.take(StringName(entry.id), 1, entry.get("state", {}))


## Where a unit of `id` is stowed in `inv`: [container, index], or [] (none).
static func find_stowed(inv: Inventory, id: StringName) -> Array:
	for c: StringName in inv.search_containers():
		var list: Array = inv.containers.get(c, [])
		for i in list.size():
			if StringName(String(list[i].id)) == id:
				return [c, i]
	return []


# --- Saved kits ---------------------------------------------------------------------------------

## The world's saved kits ({name: template}; host).
static func kits() -> Dictionary:
	var st := Survival.state()
	if not st.get(KITS_KEY) is Dictionary:
		st[KITS_KEY] = {}
	return st[KITS_KEY]


static func kit(name: String) -> Dictionary:
	return kits().get(name, {})


## `inv`'s kit as a template: {"worn": {slot: id}, "points": {point: id}, "carry": {id: count},
## "into": {container: {id: count}}} (call 134: what's in each pouch and pocket, so applying the
## kit fills the same ones).
static func template_of(inv: Inventory) -> Dictionary:
	var worn := {}
	for slot: StringName in Inventory.all_slots():
		if StringName(inv.slots.get(slot, &"")) != &"":
			worn[String(slot)] = String(inv.slots[slot])
	var points := {}
	for p: Dictionary in inv.attach_points():
		var att := inv.attachment(StringName(p.id))
		if not att.is_empty():
			points[String(p.id)] = String(att.id)
	var carry := {}
	var into := {}
	for c: StringName in inv.search_containers():
		var here := {}
		for e: Dictionary in inv.containers.get(c, []):
			carry[String(e.id)] = int(carry.get(String(e.id), 0)) + int(e.get("count", 1))
			here[String(e.id)] = int(here.get(String(e.id), 0)) + int(e.get("count", 1))
		if not here.is_empty():
			into[String(c)] = here
	return {"worn": worn, "points": points, "carry": carry, "into": into}


## Host: `inv`'s kit saved as `name`. "" or why not.
static func save_kit(name: String, inv: Inventory) -> String:
	name = name.strip_edges().left(32)
	if name == "":
		return "Name the kit first"
	var all := kits()
	if not all.has(name) and all.size() >= KITS_MAX:
		return "Too many saved kits (%d)" % KITS_MAX
	all[name] = template_of(inv)
	return ""


## Host: `tpl` (template_of) put on `target` from what `pool` carries (the giver's stowed kit;
## pool may be target itself). What target wore in a slot the kit fills goes to the pool.
## {"moved": n, "missing": [item names not carried]}.
static func apply_kit(pool: Inventory, target: Inventory, tpl: Dictionary) -> Dictionary:
	var out := {"moved": 0, "missing": []}
	if tpl.is_empty():
		(out.missing as Array).append("no such kit")
		return out
	var worn: Dictionary = tpl.get("worn", {})
	for slot: StringName in Inventory.all_slots():
		var want := StringName(String(worn.get(String(slot), "")))
		if want == &"" or StringName(target.slots.get(slot, &"")) == want:
			continue
		var at := find_stowed(pool, want)
		if at.is_empty():
			_missing(out, want)
			continue
		if StringName(target.slots.get(slot, &"")) != &"":
			var old := take_out(target, "slot:" + String(slot))
			if old.is_empty():
				_missing(out, want)
				continue
			pool.take(StringName(old.id), 1, old.get("state", {}))
			at = find_stowed(pool, want)  # (indexes may have moved)
			if at.is_empty():
				_missing(out, want)
				continue
		if transfer(pool, "container:" + String(at[0]), int(at[1]), target, "slot:" + String(slot)) == "":
			out.moved = int(out.moved) + 1
		else:
			_missing(out, want)
	var points: Dictionary = tpl.get("points", {})
	for point: String in points:
		var want := StringName(String(points[point]))
		var att := target.attachment(StringName(point))
		if StringName(String(att.get("id", ""))) == want:
			continue
		var at := find_stowed(pool, want)
		if at.is_empty() or not att.is_empty() or transfer(pool, "container:" + String(at[0]), int(at[1]), target, "point:" + point) != "":
			_missing(out, want)
		else:
			out.moved = int(out.moved) + 1
	# What goes INTO each pouch and pocket (call 134): from the pool, or (applying to oneself, or
	# what the pool lacks) from the target's other containers.
	var into: Dictionary = tpl.get("into", {})
	for c: String in into:
		if not target.containers.has(StringName(c)) or not into[c] is Dictionary:
			continue
		for id: String in into[c]:
			var need := int(into[c][id]) - _count_in(target, StringName(c), StringName(id))
			while need > 0:
				var from: Inventory = pool
				var at := find_stowed(pool, StringName(id)) if pool != target else []
				if at.is_empty():
					from = target
					at = _find_elsewhere(target, StringName(id), StringName(c))
				if at.is_empty() or transfer(from, "container:" + String(at[0]), int(at[1]), target, "container:" + c) != "":
					if pool != target and find_stowed(pool, StringName(id)).is_empty() and target.count_of(StringName(id)) < int(tpl.get("carry", {}).get(id, 0)):
						_missing(out, StringName(id))
					break
				if from == pool:
					out.moved = int(out.moved) + 1
				need -= 1
	if pool != target:
		var carry: Dictionary = tpl.get("carry", {})
		for id: String in carry:
			var need := int(carry[id]) - target.count_of(StringName(id))
			while need > 0:
				var at := find_stowed(pool, StringName(id))
				if at.is_empty() or transfer(pool, "container:" + String(at[0]), int(at[1]), target, "auto") != "":
					_missing(out, StringName(id))
					break
				out.moved = int(out.moved) + 1
				need -= 1
	return out


## Units of `id` in container `c` of `inv`.
static func _count_in(inv: Inventory, c: StringName, id: StringName) -> int:
	var n := 0
	for e: Dictionary in inv.containers.get(c, []):
		if StringName(String(e.id)) == id:
			n += int(e.get("count", 1))
	return n


## Where a unit of `id` is in `inv` outside container `not_in`: [container, index], or [].
static func _find_elsewhere(inv: Inventory, id: StringName, not_in: StringName) -> Array:
	for c: StringName in inv.search_containers():
		if c == not_in:
			continue
		var list: Array = inv.containers.get(c, [])
		for i in list.size():
			if StringName(String(list[i].id)) == id:
				return [c, i]
	return []


static func _missing(out: Dictionary, id: StringName) -> void:
	var it := ItemDB.get_item(id)
	var n := it.name if it else String(id)
	if n not in (out.missing as Array):
		(out.missing as Array).append(n)


# --- What the screen shows beside the kit -------------------------------------------------------

## Host: a companion's state for the editor: name, needs in words, mood, clothes, warmth.
static func info_of(target: Soldier) -> Dictionary:
	var layer := SurvivorsLayer.find(target)
	var rec: Dictionary = layer.record_of(target) if layer else {}
	var n: Dictionary = rec.get("needs", target.get_meta(&"needs", {})) if not rec.is_empty() else target.get_meta(&"needs", {})
	var info := {"name": target.display_name(), "clothes": Array(Clothing.lines_of(target.inventory, n)), "warmth": Clothing.warmth(target),
		"noise": Clothing.noise_of(target.inventory), "kits": kits().keys()}
	if not n.is_empty():
		info["needs"] = Needs.words(Needs.ensure(n))
	if not rec.is_empty():
		info["mood"] = Moods.mood(rec)
		info["band"] = Moods.band(rec)
		info["status"] = String(rec.get("status", ""))
	return info


static func _send_info(actor: Soldier, target: Soldier) -> void:
	var layer := SurvivorsLayer.find(target)
	if layer == null:
		return
	var info := info_of(target)
	info["path"] = String(target.get_path())
	var peer := actor.owner_peer()
	if peer == actor.multiplayer.get_unique_id():
		layer.gear_info.emit(info)
	else:
		layer._client_gear_info.rpc_id(peer, info)
