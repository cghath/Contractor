class_name WorldValuables
extends RefCounted
## Lootable value out in the open terrain, away from the mission sites (Captain, 2026-10-16,
## playtest B1399 on Red Mesa: "nothing to loot out in the world"): at each VALUABLE site
## ZoneScatter marked (same placement rules as its rocks and trees, well clear of a road or a
## pad), either a dead drop (one piece of cash or intel, a plain WorldItem) or a small cache —
## a real WorldCache (docs/loot_window.md: "crates other than vehicle holds don't exist as
## lootable nodes yet") holding a weapon, its mags, and a medical or salvage item, opened
## through the same two-pane LootWindow a vehicle's hold uses.
##
## Both drop into the existing flow rather than a parallel one: a dead drop is an ordinary
## WorldItem (picking one up feeds Prices/Economy and, for intel, IntelReveal's reveal scan
## automatically); a cache is spawned through the zone's CacheSpawner (ZoneLevel.cache_spawner,
## _make_cache) like a vehicle would be, so every peer and a late joiner get it the same way.
## Host only, spawned once a zone hosts (ZoneLevel._on_hosted). A dead drop gets a stable uid so
## GameState.is_looted keeps a taken one from coming back; a cache's contents are rolled fresh
## each time the zone hosts instead (WorldCache's own doc comment) - simpler than tracking what
## was taken from inside it across a reload.
##
## Site boxes (Captain, 2026-10-16, three asks that are really one mechanic): 1-4 WorldCaches at
## every hand-built module (compound, outpost, village, checkpoint, hq, qrf_base, comms), not out
## in the open terrain - "common sense" places a player would actually search (offices, safes,
## command posts, desks), reusing that module's own proven-safe loot spots (ZoneModules.LOOT, a
## small offset off each one so a box doesn't sit on top of the WorldItem already there). How
## many: weighted toward 1-2, more at a site worth more trouble (IMPORTANT_TYPES). Most boxes
## roll a common find (one piece of cash or intel); RARE_SHARE of them roll something better
## instead - half the time a rarer weapon and its mags, half the time more intel and an optic
## ("a couple maps plus a scope").

const DEAD_DROP_SHARE := 0.55
const CACHE_GUNS: Array[String] = ["akm", "ak74", "rpk"]
const CACHE_MEDICAL: Array[String] = ["ifak", "trauma_kit", "tourniquet"]
const VALUABLE_ITEMS: Array[String] = ["cash_bundle", "gold_bars", "jewelry_case", "smuggled_relic"]
const INTEL_ITEMS: Array[String] = ["intel_documents", "intel_phone", "intel_usb_drive", "intel_ledger"]
const SALVAGE_ITEMS: Array[String] = ["scrap_copper", "machine_parts", "electronics_salvage"]
const LIFT_M := 0.35
## A site box's chance of a rare roll (a better weapon, or more intel and an optic) instead of
## the common one, and the even split between those two rare outcomes.
const RARE_SHARE := 0.18
const RARE_OPTICS: Array[String] = ["optic_lpvo", "optic_prism_4x", "optic_dmr_3_5_10"]
const RARE_GUNS: Array[String] = ["svd", "pkm", "rpk"]
const RARE_INTEL_COUNT := 2
## Off each used ZoneModules.LOOT spot (module space, m), clear of the WorldItem already there
## and of each other; at most this many boxes a site.
const SITE_BOX_OFFSETS: Array[Vector3] = [Vector3(0.8, 0.0, 0.5), Vector3(-0.8, 0.0, 0.5), Vector3(0.8, 0.0, -0.5), Vector3(-0.8, 0.0, -0.5)]
## Every ZoneModules.LOOT (and BuildingGen.town loot) anchor sits this high above the floor it's
## on: clearance for the WorldItem already there, a RigidBody3D that drops and settles onto that
## floor on its own. A WorldCache never falls (StaticBody3D, placed once), so a site box built on
## one of these anchors has to come back down by the same amount or it floats at the WorldItem's
## drop height instead of resting on the floor (Captain, 2026-10-16: "lootboxes float").
const LOOT_ANCHOR_LIFT_M := 0.5
## Wave 6 (item catalogue: contraband at "smuggler compounds, checkpoints, caches"): at these
## sites a common box find is contraband instead, CONTRABAND_PCT of the time (by the box's id, no
## RNG drawn: every other roll stays as it was).
const CONTRABAND_ITEMS: Array[String] = ["smuggled_cigarettes", "captagon", "counterfeit_dollars", "unregistered_weapons"]
const CONTRABAND_TYPES: Array[String] = ["checkpoint", "compound", "hq"]
const CONTRABAND_PCT := 40
## Wave 6 (keys): every HQ has a locked strongbox, opened by the key its officer carries
## (ZoneLevel's garrison: the HQ's first post); valuables, contraband and intel inside, and half
## the time a Vantage ledger (story intel, it opens a lead).
const STRONGBOX_KEY := &"hq_strongbox_key"
const STRONGBOX_LABEL := "Strongbox"
const STRONGBOX_OFFSET := Vector3(0.0, 0.0, 1.0)
## Sites worth more trouble: weighted toward more boxes.
const IMPORTANT_TYPES: Array[String] = ["hq", "qrf_base", "compound"]


## Host: every VALUABLE site the zone's scatter marked.
static func server_spawn_all(level: ZoneLevel) -> void:
	if not level.multiplayer.is_server() or level.scatter == null or level.terrain == null or level.cache_spawner == null:
		return
	var sites := level.scatter.valuable_sites()
	for i in sites.size():
		_spawn_site(level, sites[i], "scatter_val%d" % i, i)


## One site: a dead drop (one item) or a small cache (gun, its mags, a medical or salvage item),
## rolled deterministically from the zone's seed and the site's index (so it's the same roll
## every time this zone hosts).
static func _spawn_site(level: ZoneLevel, site: Dictionary, uid: String, index: int) -> void:
	var pos: Vector3 = site.pos
	var ground: Vector3 = level.ground_point(Vector3(pos.x, 0.0, pos.z))
	var rng := RandomNumberGenerator.new()
	rng.seed = level.terrain.seed_value ^ 0x7A1E ^ index
	if rng.randf() < DEAD_DROP_SHARE:
		var pool := INTEL_ITEMS if rng.randf() < 0.5 else VALUABLE_ITEMS
		var drop_uid := "%s_d" % uid
		if not GameState.is_looted(drop_uid):
			level.spawn_item(StringName(pool[rng.randi() % pool.size()]), 1, ground + Vector3.UP * LIFT_M, drop_uid)
		return
	var gun := CACHE_GUNS[rng.randi() % CACHE_GUNS.size()]
	var kit: Array = CompoundLevel.HOSTILE_GUNS.get(gun, [gun])
	var items: Array = [{"id": gun, "count": 1}]
	if kit.size() > 1:
		items.append({"id": String(kit[1]), "count": kit.size() - 1})
	items.append({"id": SALVAGE_ITEMS[rng.randi() % SALVAGE_ITEMS.size()] if rng.randf() < 0.4 else CACHE_MEDICAL[rng.randi() % CACHE_MEDICAL.size()], "count": 1})
	var cache := level.cache_spawner.spawn({"uid": uid, "pos": ground, "yaw": float(site.yaw), "label": "Cache"}) as WorldCache
	if cache:
		cache.server_seed(items)


## Host: 1-4 valuables/intel boxes at every real module (not a generated town, which has its own
## loot through BuildingGen), near spots already proven safe (ZoneModules.LOOT places a
## WorldItem there today).
static func server_spawn_site_boxes(level: ZoneLevel) -> void:
	if not level.multiplayer.is_server() or level.cache_spawner == null:
		return
	for module: ZoneModule in level.modules():
		var spots: Array = ZoneModules.LOOT.get(module.type, [])
		if spots.is_empty():
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s|valbox" % module.module_id)
		var count := mini(_site_box_count(rng, module.type), mini(spots.size(), SITE_BOX_OFFSETS.size()))
		for k in count:
			var anchor: Vector3 = (spots[spots.size() - 1 - k] as Dictionary).pos
			var floor_spot := anchor - Vector3(0, LOOT_ANCHOR_LIFT_M, 0)
			var cache := level.cache_spawner.spawn({"uid": "%s_valbox%d" % [module.module_id, k],
				"pos": module.to_global(floor_spot + SITE_BOX_OFFSETS[k]), "yaw": 0.0, "label": "Cache"}) as WorldCache
			if cache:
				var contents := _roll_site_box(rng)
				var box_id := "%s_valbox%d" % [module.module_id, k]
				if (module.type in CONTRABAND_TYPES or ZoneModules.base(module.type) in CONTRABAND_TYPES) and contents.size() == 1 						and String(contents[0].id) not in RARE_GUNS and posmod(hash("contraband:" + box_id), 100) < CONTRABAND_PCT:
					contents = [{"id": CONTRABAND_ITEMS[posmod(hash("contraband_kind:" + box_id), CONTRABAND_ITEMS.size())], "count": 1}]
				cache.server_seed(contents)
		if module.type == "hq":
			var box := level.cache_spawner.spawn({"uid": "%s_strongbox" % module.module_id, "key": String(STRONGBOX_KEY), "label": STRONGBOX_LABEL,
				"pos": module.to_global((spots[0] as Dictionary).pos - Vector3(0, LOOT_ANCHOR_LIFT_M, 0) + STRONGBOX_OFFSET), "yaw": 0.0}) as WorldCache
			if box:
				box.server_seed(strongbox_contents(module.module_id))


## An HQ strongbox's contents (by the module id: the same HQ always holds the same).
static func strongbox_contents(module_id: String) -> Array:
	var h := hash("strongbox:" + module_id)
	var items: Array = [{"id": "gold_bars", "count": 2}, {"id": CONTRABAND_ITEMS[posmod(h, CONTRABAND_ITEMS.size() - 1)], "count": 1},
		{"id": INTEL_ITEMS[posmod(h >> 4, INTEL_ITEMS.size())], "count": 1}, {"id": "cash_bundle", "count": 3}]
	if posmod(h >> 8, 2) == 0:
		items.append({"id": "vantage_ledger", "count": 1})
	return items


## How many boxes a site gets: weighted toward 1-2, a point more (capped at 4) for an
## IMPORTANT_TYPES site.
static func _site_box_count(rng: RandomNumberGenerator, module_type: String) -> int:
	var roll := rng.randf()
	var count := 1
	if roll < 0.15:
		count = 4
	elif roll < 0.35:
		count = 3
	elif roll < 0.65:
		count = 2
	if module_type in IMPORTANT_TYPES or ZoneModules.base(module_type) in IMPORTANT_TYPES:
		count = mini(count + 1, 4)
	return count


## One box's contents: usually one piece of cash or intel; RARE_SHARE of the time something
## better instead, half a rarer weapon and its mags, half more intel and an optic.
static func _roll_site_box(rng: RandomNumberGenerator) -> Array:
	var roll := rng.randf()
	if roll < RARE_SHARE * 0.5:
		var gun := RARE_GUNS[rng.randi() % RARE_GUNS.size()]
		var kit: Array = CompoundLevel.HOSTILE_GUNS.get(gun, [gun])
		var items: Array = [{"id": gun, "count": 1}]
		if kit.size() > 1:
			items.append({"id": String(kit[1]), "count": kit.size() - 1})
		return items
	if roll < RARE_SHARE:
		var items: Array = []
		for i in RARE_INTEL_COUNT:
			items.append({"id": INTEL_ITEMS[rng.randi() % INTEL_ITEMS.size()], "count": 1})
		items.append({"id": RARE_OPTICS[rng.randi() % RARE_OPTICS.size()], "count": 1})
		return items
	var pool := INTEL_ITEMS if rng.randf() < 0.5 else VALUABLE_ITEMS
	return [{"id": pool[rng.randi() % pool.size()], "count": 1}]
