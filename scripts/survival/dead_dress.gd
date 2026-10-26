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
## Every number here is Proposed.

const ORIGIN_NAMES: Array[String] = ["civilian", "worker", "farmer", "soldier", "cop", "doctor"]
## A site's mix of origins (shares), by base type or town lot.
const ORIGINS := {
	"": {"civilian": 0.6, "farmer": 0.2, "worker": 0.1, "soldier": 0.1},
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
## it or in the pockets); "maybe" [id, count, chance] rolled each.
const KITS := {
	"soldier": {"pack": "pack_assault_30", "worn": ["plate_carrier_light", "plate_steel_l3"], "items": [["m4a1", 1], ["mag_556", 2]],
		"maybe": [["pressure_bandage", 1, 0.5], ["radio", 1, 0.2]]},
	"hazmat": {"pack": "pack_assault_30", "worn": ["plate_carrier_light", "plate_steel_l3"], "items": [["gas_mask_m50", 1]],
		"maybe": [["m4a1", 1, 0.4], ["pressure_bandage", 1, 0.5]]},
	"doctor": {"pack": "pack_hydration_12", "worn": ["aid_bag"], "items": [["suture_kit", 1], ["antibiotics", 1], ["pressure_bandage", 2]],
		"maybe": [["morphine", 1, 0.4]]},
	"cop": {"items": [["glock17", 1], ["mag_9mm", 1], ["zip_cuffs", 2]], "maybe": [["car_keys", 1, 0.3]]},
	"worker": {"items": [], "maybe": [["hammer", 1, 0.4], ["pliers", 1, 0.3], ["wrench_set", 1, 0.15], ["lighter", 1, 0.3]]},
	"farmer": {"items": [], "maybe": [["seed_packet", 2, 0.5], ["lighter", 1, 0.2], ["car_keys", 1, 0.15]]},
	"civilian": {"items": [], "maybe": [["car_keys", 1, 0.2], ["lighter", 1, 0.2], ["digital_watch", 1, 0.1]]},
}

## Tests: a site to use wherever (-"": by the rules).
static var force_site := ""


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


## An origin from `site`'s mix (`kind` the hazmat one is always the decon teams' soldier).
static func roll(site: String, rng: RandomNumberGenerator, kind := "walker") -> String:
	if kind == "hazmat":
		return "soldier"
	var shares: Dictionary = ORIGINS.get(site, ORIGINS[""])
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


## Host: what `s` had on it when it turned (its origin's KITS, kind "hazmat" the decon kit), in
## its Inventory: the pack and worn things first, weapons stowed (never in a weapon slot: the
## dead don't use them), the rest wherever it fits. Returns the ids given.
static func server_kit(s: Soldier, origin: String, kind: String, rng: RandomNumberGenerator) -> Array:
	var inv: Inventory = s.get_node_or_null(^"Inventory") as Inventory
	if inv == null:
		return []
	var k: Dictionary = KITS.get("hazmat" if kind == "hazmat" else origin, KITS.civilian)
	var given: Array = []
	if String(k.get("pack", "")) != "" and inv.take(StringName(k.pack)) > 0:
		given.append(String(k.pack))
	for id: String in k.get("worn", []):
		if _give(inv, id, 1) > 0:
			given.append(id)
	var list: Array = (k.get("items", []) as Array).duplicate()
	for m: Array in k.get("maybe", []):
		if rng.randf() < float(m[2]):
			list.append([m[0], m[1]])
	for e: Array in list:
		if _give(inv, String(e[0]), int(e[1])) > 0:
			given.append(String(e[0]))
	return given


## Puts `n` of `id` on the body: a weapon into a container (pack, then pockets), else take().
static func _give(inv: Inventory, id: String, n: int) -> int:
	var item := ItemDB.get_item(StringName(id))
	if item == null:
		return 0
	if item.slot in Inventory.WEAPON_SLOTS:
		for c: StringName in [&"backpack", &"vest", &"pockets"]:
			var got := inv._stow(c, item, n, {})
			if got > 0:
				inv._commit()
				return got
		return 0
	var taken := inv.take(StringName(id), n)
	if taken < n:
		for c: StringName in [&"backpack", &"pockets"]:
			var more := inv._stow(c, item, n - taken, {})
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
