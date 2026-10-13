class_name Scavenge
extends RefCounted
## What an AI soldier takes off a dead body, one item at a time (Captain, 2026-10-11: AI that
## loot take what they need, as realistically as possible). Squadmates and enemies use the
## same rules (SquadAI's SCAVENGE intent).
##
## A soldier restocks to his basic load, not to everything on the body:
## - Ammunition for the weapons he carries, up to his role kit's magazines (BASIC_MAGS for a
##   soldier without a role, such as an enemy). Only magazines his weapon takes; loose rounds
##   stay, since the AI doesn't load magazines.
## - Medical items his role kit has, counting what's left in his own IFAK or trauma kit. A whole
##   kit comes over when what's in it is what he lacks.
## - Grenades and smokes up to his role kit's count, and anything else his kit has that he lost
##   (a team leader's radio).
## - Intel (items tagged "intel") always comes.
## - Armor, only well out of contact (the swap takes time): a plate that protects more than his
##   own (higher rating, or his own is cracked through or missing) and fits his carrier; a
##   helmet when he has none or a better one is there. His old piece stays on the body.
## - Another rifle only when his own has no ammunition left at all and the body's has some. His
##   empty one he lays on the ground beside the body, not on its sling: a body whose rifle was
##   taken shows none (Captain, P0164 queue 15: the old rifle slung on the body looked like
##   the one taken off it).
## Each candidate scores how short of it he is, weighted by how much it matters (ammo first,
## then the life-saving medical items, other medical, grenades, the rest). He takes nothing
## that would put his load over MAX_LOAD_KG (intel and armor swaps aside), no bulky items
## (anything carried in both hands, spare carriers and packs), and leaves the rest for players.
## Each pick takes time by where it is (a pouch is quick, digging in a pack is slow).

## Proposed: the load an AI won't scavenge past (Soldier slows from FREE_LOAD_KG; 35 kg is
## a fighting load plus a little).
const MAX_LOAD_KG := 35.0
## Proposed: spare magazines (on top of the one loaded) a soldier without a role kit counts as
## his basic load, for his primary and his sidearm.
const BASIC_MAGS := {&"primary": 4, &"sidearm": 2}
## Proposed: what a soldier without a role kit counts as the rest of his basic load.
const BASIC_KIT := [[&"ifak", 1], [&"frag_grenade", 1], [&"smoke_grenade", 1]]
## How much each kind of need weighs (a need's score is this times how short he is, 0..1).
const W_AMMO := {&"primary": 1.0, &"sidearm": 0.4}
const W_MED_CRITICAL := 0.85
const W_MED := 0.6
const W_GRENADE := 0.5
const W_OTHER := 0.3
const W_INTEL := 0.9
const W_WEAPON := 0.95
const W_PLATE := 0.6
const W_HELMET := 0.45
## Medical items that stop someone dying in the next minutes: restocked first.
const CRITICAL_MED: Array[StringName] = [&"tourniquet", &"hemostatic_gauze", &"chest_seal", &"pressure_bandage", &"decompression_needle"]
## Proposed: a better plate or helmet must be at least this much better (Ballistics.LEVELS
## steps times integrity) to be worth the swap.
const ARMOR_MARGIN := 1.0
## A whole kit scores this much of what's in it that he needs: the loose item comes first
## when the body has one (lighter, and it's the one thing he lacks).
const KIT_SCORE := 0.9
## Proposed: seconds per pick, by where the item is.
const PICK_S := {&"pouch": 1.5, &"vest": 2.0, &"pockets": 2.0, &"backpack": 4.0, &"weapon": 3.0, &"helmet": 3.0, &"plate": 8.0}
## Proposed: an empty weapon swapped for the body's is laid this far (metres) from the body's
## chest towards the soldier, let go this high above it (beside_body).
const DROP_BESIDE_M := 0.6
const DROP_LIFT_M := 0.4


## What `s` is short of, as needs keyed by item id: {"kind", "want" (units; rounds for ammo),
## "frac" (how short, 0..1), "weight"}. Kinds: ammo, medical, grenade, other, intel (by tag).
static func needs(s: Soldier) -> Dictionary:
	var inv := s.inventory
	var kit := _basic_kit(s)
	var out := {}
	var med := {}  # medical item id -> basic load, summed over every kit source
	for slot: StringName in Inventory.WEAPON_SLOTS:
		var weapon_id: StringName = inv.slots[slot]
		if weapon_id == &"":
			continue
		var ammo := StringName(ItemDB.get_item(weapon_id).stats.get("ammo", ""))
		if not ItemDB.has_item(ammo):
			continue
		var per_mag := ItemDB.get_item(ammo).magazine_rounds()
		var mags := int(kit.get(ammo, 0))
		if mags <= 0:
			mags = BASIC_MAGS[slot]
		var target := (mags + 1) * per_mag  # the loaded magazine too
		var have := inv.spare_rounds(ammo) + inv.rounds_in(slot)
		if have < target:
			_add(out, ammo, "ammo", target - have, float(target - have) / target, W_AMMO[slot])
	for id: StringName in kit:
		var item := ItemDB.get_item(id)
		if item == null or item.type == "ammo" or item.type == "weapon":
			continue
		if Inventory.is_kit(item):
			# What a kit holds counts item by item: a soldier whose IFAK is used up wants its
			# contents, whether they come loose or in another kit. Summed with the loose ones
			# (a TQ in the holder plus one in the IFAK is a basic load of 2), since
			# medical_count counts both.
			var contents := Inventory.kit_contents(item, {})
			for inside: String in contents:
				med[StringName(inside)] = int(med.get(StringName(inside), 0)) + int(contents[inside]) * int(kit[id])
		elif item.type == "medical":
			med[id] = int(med.get(id, 0)) + int(kit[id])
		elif item.stats.has("throwable"):
			var have_g := inv.count_of(id)
			if have_g < int(kit[id]):
				_add(out, id, "grenade", int(kit[id]) - have_g, float(int(kit[id]) - have_g) / int(kit[id]), W_GRENADE)
		elif item.type in ["utility", "medical"] and not Inventory.is_attachable(item) and inv.count_of(id) < int(kit[id]):
			_add(out, id, "other", int(kit[id]) - inv.count_of(id), 1.0, W_OTHER)
	for id: StringName in med:
		_add_med(out, inv, id, int(med[id]))
	return out


## The best thing for `s` to take off `dead` now, or {} if nothing scores at least
## `min_score`: {"kind" (stowed, kit, plate, helmet, weapon, intel), "where", "index", "id",
## "count", "score", "seconds", and for armor "into" (his slot)}. `calm`: well out of contact,
## so armor swaps are allowed.
static func best_pick(s: Soldier, dead: Soldier, calm: bool, min_score := 0.0) -> Dictionary:
	var want := needs(s)
	var inv := dead.inventory
	var best := {}
	var room := maxf(MAX_LOAD_KG, s.inventory.total_mass()) - s.inventory.total_mass()
	for container in inv.search_containers():
		var list: Array = inv.containers[container]
		for i in list.size():
			var pick := _stowed_pick(want, list[i], room)
			if pick.is_empty():
				continue
			pick.merge({"where": container, "index": i, "seconds": _pick_seconds(container)})
			if float(pick.score) > float(best.get("score", min_score - 0.001)):
				best = pick
	for pick: Dictionary in [_weapon_pick(s, dead), _plate_pick(s, dead, calm), _helmet_pick(s, dead, calm)]:
		if not pick.is_empty() and float(pick.score) > float(best.get("score", min_score - 0.001)):
			best = pick
	return best


## How much `s` would get out of `dead` (the best pick's score, 0 for nothing).
static func value(s: Soldier, dead: Soldier, calm: bool) -> float:
	return float(best_pick(s, dead, calm).get("score", 0.0))


## Host only. Carries out `pick` (from best_pick): moves the item(s) from `dead` to `s`, and
## for a swap puts his old piece on the body. Re-checks that the item is still there. Returns
## the units moved (0 if nothing could).
static func apply(s: Soldier, dead: Soldier, pick: Dictionary) -> int:
	var inv := dead.inventory
	match String(pick.kind):
		"stowed", "kit", "intel":
			var list: Array = inv.containers.get(pick.where, [])
			if int(pick.index) >= list.size() or list[pick.index].id != pick.id:
				return 0
			var entry := inv.remove_entry(pick.where, pick.index, int(pick.count))
			var moved := s.inventory.take(entry.id, int(entry.count), entry.get("state", {}))
			if moved < int(entry.count):
				var rest := entry.duplicate(true)
				rest.count = int(entry.count) - moved
				if not inv.insert_entry(pick.where, rest):
					inv.take(rest.id, int(rest.count), rest.get("state", {}))
			return moved
		"weapon", "plate", "helmet":
			return 1 if _swap(s, dead, pick) else 0
	return 0


# --- Needs ------------------------------------------------------------------------------

## The soldier's basic load as item id -> count: his role kit, or BASIC_KIT without a role.
static func _basic_kit(s: Soldier) -> Dictionary:
	var kit := {}
	var pairs: Array = Roles.kit(s.role) if Roles.has(s.role) else BASIC_KIT
	for pair: Array in pairs:
		kit[StringName(pair[0])] = int(kit.get(StringName(pair[0]), 0)) + int(pair[1])
	return kit


static func _add(out: Dictionary, id: StringName, kind: String, want: int, frac: float, weight: float) -> void:
	if want <= 0:
		return
	if out.has(id):
		out[id].want += want
		out[id].frac = minf(1.0, maxf(out[id].frac, frac))
		return
	out[id] = {"kind": kind, "want": want, "frac": clampf(frac, 0.0, 1.0), "weight": weight}


static func _add_med(out: Dictionary, inv: Inventory, id: StringName, target: int) -> void:
	if target <= 0:
		return
	var have := inv.medical_count(id)
	var item := ItemDB.get_item(id)
	if have < target and item and not item.stats.get("reusable", false):
		_add(out, id, "medical", target - have, float(target - have) / target, W_MED_CRITICAL if id in CRITICAL_MED else W_MED)
	elif have == 0 and item and item.stats.get("reusable", false):
		_add(out, id, "medical", 1, 1.0, W_MED)  # a pulse oximeter or a defibrillator: one is enough


# --- Picks ------------------------------------------------------------------------------

## A stowed entry worth taking for `want`, with how many: magazines up to the rounds he's
## short (a fuller magazine first by score), medical and grenades up to what he lacks, a kit
## when its contents are what he lacks, intel always. Kept within `room` kg.
static func _stowed_pick(want: Dictionary, entry: Dictionary, room: float) -> Dictionary:
	var id := StringName(entry.id)
	var item := ItemDB.get_item(id)
	if item == null or item.two_handed or item.slot in [&"vest", &"backpack"]:
		return {}
	var unit_mass := Inventory.entry_mass({"id": id, "count": 1, "state": entry.get("state", {})})
	if "intel" in item.tags:
		return {"kind": "intel", "id": id, "count": int(entry.count), "score": W_INTEL}
	if Inventory.is_kit(item):
		var score := 0.0
		var contents := Inventory.kit_contents(item, entry.get("state", {}))
		for inside: String in contents:
			var need: Dictionary = want.get(StringName(inside), {})
			if not need.is_empty() and int(contents[inside]) > 0:
				score = maxf(score, float(need.weight) * float(need.frac))
		if score <= 0.0 or unit_mass > room:
			return {}
		return {"kind": "kit", "id": id, "count": 1, "score": score * KIT_SCORE}
	var need: Dictionary = want.get(id, {})
	if need.is_empty():
		return {}
	var count := int(entry.count)
	if need.kind == "ammo":
		var rounds := int(entry.get("state", {}).get("rounds", item.magazine_rounds()))
		if rounds <= 0:
			return {}  # an empty magazine is no use without loose rounds to load it
		count = mini(count, ceili(float(need.want) / rounds))
	else:
		count = mini(count, int(need.want))
	if unit_mass > 0.0:
		count = mini(count, floori(room / unit_mass))
	if count <= 0:
		return {}
	var fill := 1.0
	if need.kind == "ammo" and item.magazine_rounds() > 0:
		fill = float(entry.get("state", {}).get("rounds", item.magazine_rounds())) / item.magazine_rounds()
	return {"kind": "stowed", "id": id, "count": count, "score": float(need.weight) * float(need.frac) * lerpf(0.8, 1.0, fill)}


## The body's rifle, when his own primary has no rounds left anywhere (or he has none) and
## the body's has some, in it or in the body's magazines.
static func _weapon_pick(s: Soldier, dead: Soldier) -> Dictionary:
	var theirs: StringName = dead.inventory.slots[&"primary"]
	if theirs == &"":
		return {}
	var mine: StringName = s.inventory.slots[&"primary"]
	if mine != &"" and _rounds_for(s.inventory, &"primary") > 0:
		return {}
	if mine != &"" and dead.inventory.spare_rounds(StringName(ItemDB.get_item(mine).stats.get("ammo", ""))) > 0:
		return {}  # his own rifle takes the body's magazines: those come instead (a dry M4 and an MK18)
	if _rounds_for(dead.inventory, &"primary") <= 0:
		return {}
	return {"kind": "weapon", "id": theirs, "where": &"primary", "index": -1, "into": &"primary", "count": 1,
		"score": W_WEAPON, "seconds": PICK_S[&"weapon"]}


## Rounds for the weapon in `slot`: in it, plus its magazines.
static func _rounds_for(inv: Inventory, slot: StringName) -> int:
	var weapon_id: StringName = inv.slots[slot]
	if weapon_id == &"":
		return 0
	return inv.rounds_in(slot) + inv.spare_rounds(StringName(ItemDB.get_item(weapon_id).stats.get("ammo", "")))


## A plate on the body (worn or stowed) that fits his carrier and protects clearly more than
## what's in the matching pocket of his own (calm only).
static func _plate_pick(s: Soldier, dead: Soldier, calm: bool) -> Dictionary:
	var vest: StringName = s.inventory.slots[&"vest"]
	if not calm or vest == &"":
		return {}
	var carrier := ItemDB.get_item(vest)
	var best := {}
	for found: Dictionary in _armor_on(dead, func(item: ItemData) -> bool: return item.is_plate() and ArmorRules.plate_fits(item, carrier)):
		var item := ItemDB.get_item(found.id)
		for slot: StringName in s.inventory.carrier_plate_slots():
			var side := slot == &"plate_left" or slot == &"plate_right"
			if side != (item.slot == &"side_plate"):
				continue
			var gain := _protection(item, found.state) - _worn_protection(s.inventory, slot)
			if gain >= ARMOR_MARGIN:
				var score := W_PLATE * minf(1.0, gain / 3.0)
				if score > float(best.get("score", 0.0)):
					best = found.merged({"kind": "plate", "into": slot, "count": 1, "score": score, "seconds": PICK_S[&"plate"]}, true)
	return best


## A helmet on the body when he has none, or one clearly better (calm only).
static func _helmet_pick(s: Soldier, dead: Soldier, calm: bool) -> Dictionary:
	if not calm:
		return {}
	var best := {}
	for found: Dictionary in _armor_on(dead, func(item: ItemData) -> bool: return item.slot == &"helmet"):
		var gain := _protection(ItemDB.get_item(found.id), found.state) - _worn_protection(s.inventory, &"helmet")
		var score := W_HELMET if s.inventory.slots[&"helmet"] == &"" else W_HELMET * minf(1.0, gain / 3.0)
		if gain >= ARMOR_MARGIN and score > float(best.get("score", 0.0)):
			best = found.merged({"kind": "helmet", "into": &"helmet", "count": 1, "score": score, "seconds": PICK_S[&"helmet"]}, true)
	return best


## Armor on `dead` that passes `keep`, worn or stowed: [{"id", "state", "where", "index"}].
static func _armor_on(dead: Soldier, keep: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inv := dead.inventory
	var worn: Array[StringName] = Inventory.PLATE_SLOTS.duplicate()
	worn.append(&"helmet")
	for slot: StringName in worn:
		var id: StringName = inv.slots[slot]
		if id != &"" and keep.call(ItemDB.get_item(id)):
			out.append({"id": id, "state": inv.state_of(slot), "where": slot, "index": -1})
	for container in inv.search_containers():
		var list: Array = inv.containers[container]
		for i in list.size():
			var item := ItemDB.get_item(list[i].id)
			if item and keep.call(item):
				out.append({"id": list[i].id, "state": list[i].get("state", {}), "where": container, "index": i})
	return out


## How much a plate or helmet protects: its rating's step on Ballistics.LEVELS (1 = the
## lowest) times what's left of its integrity. 0 for none.
static func _protection(item: ItemData, state: Dictionary) -> float:
	if item == null:
		return 0.0
	var step := Ballistics.level_index(ArmorRules.rating(item)) + 1
	return maxf(step, 0) * ArmorRules.integrity(state)


static func _worn_protection(inv: Inventory, slot: StringName) -> float:
	var id: StringName = inv.slots[slot]
	return _protection(ItemDB.get_item(id), inv.state_of(slot)) if id != &"" else 0.0


static func _pick_seconds(container: StringName) -> float:
	if Inventory.is_pouch_container(container):
		return PICK_S[&"pouch"]
	return float(PICK_S.get(container, PICK_S[&"backpack"]))


# --- Swaps ------------------------------------------------------------------------------

## Takes the body's weapon, plate or helmet into his slot `pick.into` and leaves his old one:
## a weapon on the ground beside the body (DROP_BESIDE_M towards him), armour on the body (in
## the slot it came out of when it fits there, else stowed on the body). If any step can't be
## done, everything goes back as it was.
static func _swap(s: Soldier, dead: Soldier, pick: Dictionary) -> bool:
	var theirs := dead.inventory
	var mine := s.inventory
	var before_theirs := theirs.net_state.duplicate(true)
	var before_mine := mine.net_state.duplicate(true)
	var slot_before := s.active_slot
	var taken := {}
	if int(pick.index) < 0:
		if theirs.slots.get(pick.where, &"") != pick.id:
			return false
		taken = theirs.unequip(pick.where)
	else:
		var list: Array = theirs.containers.get(pick.where, [])
		if int(pick.index) >= list.size() or list[pick.index].id != pick.id:
			return false
		taken = theirs.remove_entry(pick.where, pick.index, 1)
	if taken.is_empty():
		return false
	var old := mine.unequip(pick.into) if mine.slots[pick.into] != &"" else {}
	var level := CompoundLevel.current(dead)
	var lay_down: bool = not old.is_empty() and pick.into in Inventory.WEAPON_SLOTS and level != null
	if not mine.slots[pick.into] == &"" or mine.take(taken.id, 1, taken.get("state", {})) != 1 \
			or (not old.is_empty() and not lay_down and theirs.take(old.id, 1, old.get("state", {})) != 1):
		theirs.net_state = before_theirs
		mine.net_state = before_mine
		if s.active_slot != slot_before:
			s.select_weapon(slot_before)
		return false
	if lay_down:
		level.server_spawn_dropped(old.id, 1, beside_body(s, dead), old.get("state", {}))
	# Unequipping his own rifle switched him to the sidearm; the AI never selects a weapon
	# itself, so bring up the one he just took.
	if pick.into in Inventory.WEAPON_SLOTS and s.active_slot != pick.into:
		s.select_weapon(pick.into)
	return true


## Where `s` lays something down beside the body `dead`: DROP_BESIDE_M from where it lies
## (Soldier.body_point) towards him, a little up so it falls onto the ground (items fall
## through bodies, onto the world).
static func beside_body(s: Soldier, dead: Soldier) -> Vector3:
	var chest := dead.body_point()
	var towards := s.global_position - chest
	towards.y = 0.0
	if towards.length() < 0.05:
		towards = Vector3.RIGHT
	return chest + towards.normalized() * DROP_BESIDE_M + Vector3.UP * DROP_LIFT_M
