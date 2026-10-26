class_name DeadDress
extends RefCounted
## The dead wear what they were (docs/survival_deadtime.md; survival.md call 114). Static.
##
## Every one of the dead has an **origin**, rolled from where it turned: the site under it (a
## zone module's base type; inside a generated town the lot it stands on: the clinic, the police
## station, a warehouse) and that site's mix (ORIGINS). The origin dresses it (look(): the plain-
## clothes variant in the colours of what it was: a soldier's olive, a cop's navy, a doctor's
## whites and scrubs, a worker's hi-vis, a farmer's overalls) and fills its pockets (kit(): what it
## had on it when it turned, in its Inventory, so the corpse is looted like any other body). The
## dead don't use weapons: a soldier's rifle rides in its pack and a cop's pistol in a pocket,
## never in the hands. The mix of origins at a site is a tell for what the place was (tell()).
## The hazmat kind is a soldier of the decon teams (plates and a mask).
## The early loot curve (FoundLoot; docs/survival_deadtime.md): outside military places soldiers
## and cops are rare and grow with the zone's tier (roll_at), none near the farm; a soldier's rifle
## is usually gone (the "gun" keep share) and a kept one is weathered, its magazine mostly empty.
## Every number here is Proposed.

const ORIGIN_NAMES: Array[String] = ["civilian", "worker", "farmer", "soldier", "cop", "doctor"]
## A site's mix of origins (shares), by base type or town lot.
const ORIGINS := {
	"": {"civilian": 0.63, "farmer": 0.22, "worker": 0.1, "soldier": 0.02, "cop": 0.03},  # (early loot curve: soldier was 0.1)
	"hq": {"soldier": 0.75, "worker": 0.1, "doctor": 0.05, "civilian": 0.1},
	"qrf_base": {"soldier": 0.8, "worker": 0.1, "civilian": 0.1},
	"outpost": {"soldier": 0.7, "civilian": 0.3},
	"checkpoint": {"soldier": 0.6, "cop": 0.2, "civilian": 0.2},
	"comms": {"soldier": 0.7, "worker": 0.3},
	"airfield": {"soldier": 0.5, "worker": 0.4, "civilian": 0.1},
	"fuel_depot": {"soldier": 0.3, "worker": 0.6, "civilian": 0.1},
	"compound": {"civilian": 0.5, "worker": 0.3, "soldier": 0.2},
	"village": {"civilian": 0.65, "farmer": 0.25, "worker": 0.1},
	"farm": {"farmer": 0.7, "civilian": 0.3},
	"town": {"civilian": 0.55, "worker": 0.2, "cop": 0.1, "doctor": 0.08, "soldier": 0.07},
	"clinic": {"doctor": 0.6, "civilian": 0.4},
	"hospital": {"doctor": 0.6, "civilian": 0.4},
	"police": {"cop": 0.7, "civilian": 0.3},
	"church": {"civilian": 0.9, "worker": 0.1},
	"mosque": {"civilian": 0.9, "worker": 0.1},
	"school": {"civilian": 0.9, "worker": 0.1},
	"warehouse": {"worker": 0.7, "civilian": 0.3},
	"factory": {"worker": 0.75, "civilian": 0.25},
	"garage": {"worker": 0.7, "civilian": 0.3},
	"fuel_station": {"worker": 0.5, "civilian": 0.5},
	"harbour": {"worker": 0.7, "civilian": 0.3},
	"oil_field": {"worker": 0.85, "civilian": 0.15},
	"office": {"civilian": 0.6, "worker": 0.4},
}
## What a site's dead say it was, by the origin that leads its mix.
const TELLS := {
	"soldier": "Uniforms and plate carriers among the dead: this was a military post.",
	"cop": "Police uniforms among the dead: the station held out here.",
	"doctor": "Scrubs and white coats among the dead: the sick were brought here.",
	"worker": "Overalls and hi-vis among the dead: people worked here.",
	"farmer": "Work clothes and boots among the dead: farm people.",
	"civilian": "Everyday clothes among the dead: people lived here.",
}
## The clothes by origin: [shirts], [trousers], [shoes] (plain-clothes colours, VoxelArt "civ:").
const CLOTHES := {
	"soldier": [["5b5e3c", "6b6247", "4f5338"], ["5b5e3c", "6b6247", "4a4a40"], ["3a3027"]],
	"cop": [["2b3a55", "34405a", "d8d8d0"], ["1f2633", "26262a"], ["1a1a1a"]],
	"doctor": [["e8e8e2", "7fa8a0", "9fb8cc"], ["e8e8e2", "7fa8a0", "3b4a63"], ["d8d8d0", "2e2a26"]],
	"worker": [["c86a2a", "d9b43a", "5e6e7e"], ["2f3a4a", "3b3b3b"], ["4a3f35"]],
	"farmer": [["6a5a44", "8a7258", "a65e48"], ["3b4a63", "4a4438"], ["3a3027", "4a3f35"]],
}
## What each origin had on it: [id, count]; "pack" the bag it wears (worn first, the rest goes in
## it or in the pockets); "worn" [id, chance] each (a plate only goes in a carrier he has on);
## "maybe" [id, count, chance] rolled each; "gun" its weapon (GUN_KEYS: kept `keep` of the time,
## the rest taken or lost; a kept one weathered, WeaponCondition.found_state, with 0..`loaded`
## rounds in it and up to `spares` magazines of 0..`loaded` rounds each, their condition by where
## it lay). (The early loot curve, Proposed: the soldier's carrier, plate and helmet more often
## than his rifle; a cop's pistol 30% of the time.)
const GUN_KEYS: Array[String] = ["id", "keep", "loaded", "mag", "spares"]
const KITS := {
	"soldier": {"pack": "pack_assault_30", "worn": [["plate_carrier_light", 0.6], ["plate_steel_l3", 0.5], ["helmet_ach", 0.45]],
		"gun": ["m4a1", 0.25, 8, "mag_556", 1], "items": [],
		"maybe": [["pressure_bandage", 1, 0.5], ["radio", 1, 0.2]]},
	"hazmat": {"pack": "pack_assault_30", "worn": [["plate_carrier_light", 1.0], ["plate_steel_l3", 0.7]], "items": [["gas_mask_m50", 1]],
		"gun": ["m4a1", 0.25, 8, "mag_556", 1], "maybe": [["pressure_bandage", 1, 0.5]]},
	"doctor": {"pack": "pack_hydration_12", "worn": [["aid_bag", 1.0]], "items": [["suture_kit", 1], ["antibiotics", 1], ["pressure_bandage", 2]],
		"maybe": [["morphine", 1, 0.4]]},
	"cop": {"gun": ["glock17", 0.3, 6, "", 0], "items": [["zip_cuffs", 2]], "maybe": [["car_keys", 1, 0.3]]},
	"worker": {"items": [], "maybe": [["hammer", 1, 0.4], ["pliers", 1, 0.3], ["wrench_set", 1, 0.15], ["lighter", 1, 0.3]]},
	"farmer": {"items": [], "maybe": [["seed_packet", 2, 0.5], ["lighter", 1, 0.2], ["car_keys", 1, 0.15]]},
	"civilian": {"items": [], "maybe": [["car_keys", 1, 0.2], ["lighter", 1, 0.2], ["digital_watch", 1, 0.1]]},
}

## Tests: a site to use wherever (-"": by the rules).
static var force_site := ""
## Tests: the share of the dead that kept their gun (-1: the kit's own).
static var force_gun_keep := -1.0


# --- Where it turned ----------------------------------------------------------------------------

## The site at `pos` in `level`: a town's lot under it (clinic, police, warehouse) when the town
## knows its lots, else the module's base type; "" in the open.
static func site_at(level: Node, pos: Vector3) -> String:
	if force_site != "":
		return force_site
	var zl := level as ZoneLevel
	if zl == null:
		return ""
	var m := zl.module_at(pos)
	if m == null:
		return ""
	var base := ZoneModules.base(String(m.type))
	if base == "town":
		var lot := _lot_at(m, pos)
		if lot in ORIGINS:
			return lot
	return base


## The town lot (BuildingGen town building type) under `pos` in module `m`, or "".
static func _lot_at(m: ZoneModule, pos: Vector3) -> String:
	var lots: Array = (ZoneModules._towns.get(String(m.type), {}) as Dictionary).get("lots", [])
	var local := pos - m.global_position
	for lot: Array in lots:
		var o: Vector3 = lot[1]
		var half: Vector2 = (lot[2] as Vector2) * 0.5 + Vector2(1.0, 1.0)
		if absf(local.x - o.x) <= half.x and absf(local.z - o.z) <= half.y:
			return String(lot[0])
	return ""


## An origin for one of the dead turning at `pos` in `level`: its site's mix with the soldiers'
## and cops' shares by the early loot curve (FoundLoot.armed_mults: the zone's tier, none near the farm).
static func roll_at(level: Node, pos: Vector3, rng: RandomNumberGenerator, kind := "walker") -> String:
	var site := site_at(level, pos)
	return roll(site, rng, kind, FoundLoot.armed_mults(level, pos, site))


## An origin from `site`'s mix (`kind` the hazmat one is always the decon teams' soldier);
## `armed` scales the soldier (x) and cop (y) shares, the difference to or from the townsfolk.
static func roll(site: String, rng: RandomNumberGenerator, kind := "walker", armed := Vector2.ONE) -> String:
	if kind == "hazmat":
		return "soldier"
	var shares: Dictionary = ORIGINS.get(site, ORIGINS[""])
	if armed != Vector2.ONE:
		shares = shares.duplicate()
		var was := float(shares.get("soldier", 0.0)) + float(shares.get("cop", 0.0))
		for o: String in ["soldier", "cop"]:
			if shares.has(o):
				shares[o] = float(shares[o]) * (armed.x if o == "soldier" else armed.y)
		var now := float(shares.get("soldier", 0.0)) + float(shares.get("cop", 0.0))
		shares["civilian"] = maxf(0.0, float(shares.get("civilian", 0.0)) - (now - was))
	var r := rng.randf()
	var acc := 0.0
	for o: String in shares:
		acc += float(shares[o])
		if r < acc:
			return o
	return "civilian"


## The mix of origins `n` of the dead at `site` would have (counts by origin; a fixed seed).
static func site_mix(site: String, n := 60, seed_v := 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["site mix", site, seed_v])
	var out := {}
	for i in n:
		var o := roll(site, rng)
		out[o] = int(out.get(o, 0)) + 1
	return out


## The origin that leads a mix ({origin: count}).
static func leading(mix: Dictionary) -> String:
	var best := "civilian"
	var most := -1
	for o: String in mix:
		if int(mix[o]) > most:
			best = o
			most = int(mix[o])
	return best


## What the dead at a site say about it (the journal and the look-at line): from the origins of
## the bodies and heads about `pos` (within `radius`), else from the site's own mix.
static func tell(level: Node, pos: Vector3, radius := 60.0) -> String:
	var mix := {}
	for z: Soldier in Survival.zombies(level):
		if z.global_position.distance_to(pos) <= radius:
			var o := String(z.get_meta(&"dead_origin", "civilian"))
			mix[o] = int(mix.get(o, 0)) + 1
	var crowd := ZoneDead.of(level)
	if crowd:
		for d: Dictionary in crowd.dead:
			if bool(d.alive) and (d.pos as Vector2).distance_to(Vector2(pos.x, pos.z)) <= radius:
				var o := String(d.get("origin", "civilian"))
				mix[o] = int(mix.get(o, 0)) + 1
	if mix.size() == 0:
		mix = site_mix(site_at(level, pos))
	return String(TELLS[leading(mix)])


# --- The look and the kit -----------------------------------------------------------------------

## The plain-clothes variant for one of the dead of `origin` (the civilian's own outfit kept),
## seeded by its name: the colours of what it was.
static func look(variant: String, origin: String, name: String) -> String:
	if not CLOTHES.has(origin):
		return variant
	var parts := variant.split(":")
	if parts.size() < 5:
		return variant
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([name, "dress"])
	var c: Array = CLOTHES[origin]
	parts[1] = String(c[0][rng.randi() % (c[0] as Array).size()])
	parts[2] = String(c[1][rng.randi() % (c[1] as Array).size()])
	parts[4] = String(c[2][rng.randi() % (c[2] as Array).size()])
	return ":".join(parts)


## What one of the dead of `origin` (kind "hazmat" the decon kit) had on it when it turned:
## [[id, count, state], ...] in the order it goes on (the pack, what's worn, the rest). `dry`: it
## lay under a roof (a nest's, inside), else out in the weather (its gun and rounds weathered).
static func kit_roll(origin: String, kind: String, rng: RandomNumberGenerator, dry := false) -> Array:
	var k: Dictionary = KITS.get("hazmat" if kind == "hazmat" else origin, KITS.civilian)
	var out: Array = []
	if String(k.get("pack", "")) != "":
		out.append([String(k.pack), 1, {}])
	var carrier := false
	for w: Array in k.get("worn", []):
		if rng.randf() >= float(w[1]):
			continue
		var item := ItemDB.get_item(StringName(String(w[0])))
		if item == null or (item.type == "plate" and not carrier):
			continue  # (a plate rides in a carrier he has on)
		carrier = carrier or item.slot == &"vest"
		out.append([String(w[0]), 1, {}])
	var gun: Array = k.get("gun", [])
	if gun.size() == GUN_KEYS.size() and rng.randf() < (force_gun_keep if force_gun_keep >= 0.0 else float(gun[1])):
		var item := ItemDB.get_item(StringName(String(gun[0])))
		if item:
			out.append([String(gun[0]), 1, WeaponCondition.found_state(item, dry, rng, rng.randi_range(0, int(gun[2])))])
			if String(gun[3]) != "":
				for _i in rng.randi_range(0, int(gun[4])):
					out.append([String(gun[3]), 1, {"rounds": rng.randi_range(0, int(gun[2])), Wear.KEY: AmmoCondition.roll(dry, rng)}])
	for e: Array in k.get("items", []):
		out.append([String(e[0]), int(e[1]), {}])
	for m: Array in k.get("maybe", []):
		if rng.randf() < float(m[2]):
			out.append([String(m[0]), int(m[1]), {}])
	return out


## Host: what `s` had on it when it turned (kit_roll), in its Inventory: the pack and worn things
## first, weapons stowed (never in a weapon slot: the dead don't use them), the rest wherever it
## fits. One of a nest's, inside, is dry; the rest have been out in the weather. Returns the ids given.
static func server_kit(s: Soldier, origin: String, kind: String, rng: RandomNumberGenerator) -> Array:
	var inv: Inventory = s.get_node_or_null(^"Inventory") as Inventory
	if inv == null:
		return []
	var given: Array = []
	for e: Array in kit_roll(origin, kind, rng, s.has_meta(&"nest_inside")):
		if _give(inv, String(e[0]), int(e[1]), e[2]) > 0:
			given.append(String(e[0]))
	return given


## Puts `n` of `id` (with `state`) on the body: a weapon into a container (pack, then pockets),
## else take().
static func _give(inv: Inventory, id: String, n: int, state := {}) -> int:
	var item := ItemDB.get_item(StringName(id))
	if item == null:
		return 0
	if item.slot in Inventory.WEAPON_SLOTS:
		for c: StringName in [&"backpack", &"vest", &"pockets"]:
			var got := inv._stow(c, item, n, state)
			if got > 0:
				inv._commit()
				return got
		return 0
	var taken := inv.take(StringName(id), n, state)
	if taken < n:
		for c: StringName in [&"backpack", &"pockets"]:
			var more := inv._stow(c, item, n - taken, state)
			if more > 0:
				inv._commit()
				taken += more
				break
	return taken


## How many of `id` are on the body anywhere: worn in a slot, on an attach point, or stowed.
static func carried(inv: Inventory, id: StringName) -> int:
	if inv == null:
		return 0
	var n := inv.count_of(id)
	for slot: StringName in inv.slots:
		if inv.slots[slot] == id:
			n += 1
	for slot: StringName in Inventory.ATTACH_SLOTS:
		var molle: Dictionary = (inv.slot_state.get(slot, {}) as Dictionary).get("molle", {})
		for p: String in molle:
			if StringName(String((molle[p] as Dictionary).get("id", ""))) == id:
				n += 1
	return n


## A town's lots for site_at and the nests (ZoneModules' town cache): [type, origin (m from the
## module), size (Vector2), turned] each, from BuildingGen's buildings.
static func lots(buildings: Array) -> Array:
	var out: Array = []
	for b: Dictionary in buildings:
		var size: Vector2 = (b.get("data", {}) as Dictionary).get("size", Vector2(10, 10))
		out.append([String(b.get("type", "")), b.get("origin", Vector3.ZERO), size, bool(b.get("turned", false))])
	return out
