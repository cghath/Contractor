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
## GameState.is_looted keeps a taken one from coming back; a cache's contents are rolled the
## first time the zone hosts and kept by the zone save from then on (WorldCache.server_fill,
## GameState.caches): what was taken from inside it stays taken across a reload.
##
## Site boxes (Captain, 2026-10-16, three asks that are really one mechanic; compound loot,
## Captain's tasking 2026-10-19 task 6): WorldCaches at every hand-built module (compound, outpost,
## village, checkpoint, hq, qrf_base, comms), in the rooms where that kind of thing would really be:
## valuables and intel in an HQ's office and radio room, a compound's command building; weapons in
## its armory tent; ammo by the crate stacks; medical chests, footlockers, parts bins. Data-driven
## (data/loot_tables.json, loot_data): each site type lists its box spots (room, position, loot
## table, label; the fitting rooms always, a few of the rest picked per site), each box rolls a
## rarity tier by the site's stated weights (common, uncommon, rare, very rare; very rare only in a
## hot zone) and then one bundle of that tier from its table. Rolled from the zone's id and the
## module's id (site_plan: the same every visit), once: the zone save keeps what's in every box
## (WorldCache.server_fill, GameState.caches), so a looted box stays looted after a reload. A type
## with no entry (a generated town) gets a few boxes by its own proven-safe ZoneModules.LOOT spots
## (a small offset off each one so a box doesn't sit on the WorldItem already there).
##
## Pools (Captain, 2026-10-20, loot rotation): the open-terrain dead drops and hidden caches and the
## HQ strongbox roll tiers too (loot_tables.json "pools": a table and tier weights each), the same
## way a site box does: one tier by the pool's weights (very rare only in a hot zone), then one
## bundle of that tier.

const DEAD_DROP_SHARE := 0.55
## The pre-rotation fixed pools: the loot tables' pools (dead_drop, field_cache, strongbox) replaced them in
## the game; tools/economy_sim.gd still models a drop and a cache from these.
const CACHE_GUNS: Array[String] = ["akm", "ak74", "rpk"]
const CACHE_MEDICAL: Array[String] = ["ifak", "trauma_kit", "tourniquet"]
const VALUABLE_ITEMS: Array[String] = ["cash_bundle", "gold_bars", "jewelry_case", "smuggled_relic"]
const INTEL_ITEMS: Array[String] = ["intel_documents", "intel_phone", "intel_usb_drive", "intel_ledger"]
const SALVAGE_ITEMS: Array[String] = ["scrap_copper", "machine_parts", "electronics_salvage"]
const LIFT_M := 0.35
## A site with no loot_tables.json entry (a generated town): off each used ZoneModules.LOOT spot
## (module space, m), clear of the WorldItem already there and of each other; at most this many
## boxes a site.
const SITE_BOX_OFFSETS: Array[Vector3] = [Vector3(0.8, 0.0, 0.5), Vector3(-0.8, 0.0, 0.5), Vector3(0.8, 0.0, -0.5), Vector3(-0.8, 0.0, -0.5)]
## Every ZoneModules.LOOT (and BuildingGen.town loot) anchor sits this high above the floor it's
## on: clearance for the WorldItem already there, a RigidBody3D that drops and settles onto that
## floor on its own. A WorldCache never falls (StaticBody3D, placed once), so a site box built on
## one of these anchors has to come back down by the same amount or it floats at the WorldItem's
## drop height instead of resting on the floor (Captain, 2026-10-16: "lootboxes float").
const LOOT_ANCHOR_LIFT_M := 0.5
## Contraband (wave 6, the item catalogue): the strongbox always holds one (the loot tables have the rest).
const CONTRABAND_ITEMS: Array[String] = ["smuggled_cigarettes", "captagon", "counterfeit_dollars", "hashish", "tramadol", "unregistered_weapons"]
## Wave 6 (keys): every HQ has a locked strongbox, opened by the key its officer carries
## (ZoneLevel's garrison: the HQ's first post); valuables, contraband and intel inside, and half
## the time a Vantage ledger (story intel, it opens a lead).
const STRONGBOX_KEY := &"hq_strongbox_key"
const STRONGBOX_LABEL := "Strongbox"
const STRONGBOX_OFFSET := Vector3(0.0, 0.0, 1.0)
## The compound loot tables (the file's _note says how they read).
const TABLES_PATH := "res://data/loot_tables.json"
## The rarity tiers, commonest first.
const TIERS: Array[String] = ["common", "uncommon", "rare", "very_rare"]

static var _data: Dictionary = {}


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
	var hot := String(level.def.get("kind", "")) == "hot"
	var seed_key := "%d|%s" % [level.terrain.seed_value, uid]
	if rng.randf() < DEAD_DROP_SHARE:
		var drop_uid := "%s_d" % uid
		if not GameState.is_looted(drop_uid):
			var row: Dictionary = (pool_roll("dead_drop", seed_key, hot).items as Array)[0]  # a drop is one WorldItem: its bundles are one row
			level.spawn_item(StringName(String(row.id)), int(row.count), ground + Vector3.UP * LIFT_M, drop_uid)
		return
	var cache := level.cache_spawner.spawn({"uid": uid, "pos": ground, "yaw": float(site.yaw), "label": "Cache"}) as WorldCache
	if cache:
		cache.server_fill(pool_roll("field_cache", seed_key, hot).items)


## Host: the site boxes at every real module (site_plan), and an HQ's strongbox. Each box is a
## WorldCache through the zone's CacheSpawner (every peer and a late joiner get it), filled with
## what the zone save kept in it, else its roll (WorldCache.server_fill).
static func server_spawn_site_boxes(level: ZoneLevel) -> void:
	if not level.multiplayer.is_server() or level.cache_spawner == null:
		return
	var zone_id := String(level.def.get("id", GameState.zone_id))
	var hot := String(level.def.get("kind", "")) == "hot"
	for module: ZoneModule in level.modules():
		for box: Dictionary in site_plan(module.type, "%s|%s" % [zone_id, module.module_id], hot):
			var uid := "%s_box_%s" % [module.module_id, box.key]
			var cache := level.cache_spawner.spawn({"uid": uid, "pos": module.to_global(box.pos), "yaw": 0.0, "label": String(box.label)}) as WorldCache
			if cache:
				cache.server_fill(box.items)
		var spots: Array = ZoneModules.LOOT.get(module.type, [])
		if module.type == "hq" and not spots.is_empty():
			var strongbox := level.cache_spawner.spawn({"uid": "%s_strongbox" % module.module_id, "key": String(STRONGBOX_KEY), "label": STRONGBOX_LABEL,
				"pos": module.to_global((spots[0] as Dictionary).pos - Vector3(0, LOOT_ANCHOR_LIFT_M, 0) + STRONGBOX_OFFSET), "yaw": 0.0}) as WorldCache
			if strongbox:
				strongbox.server_fill(strongbox_contents(module.module_id, hot))


## The loot tables (data/loot_tables.json), read once.
static func loot_data() -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open(TABLES_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("WorldValuables: cannot read %s" % TABLES_PATH)
			return {"sites": {}, "tables": {}, "default_weights": {"common": 1}, "fallback": {}}
		_data = parsed
	return _data


## A module type's site entry in the tables (by its base type: a grown outpost is an outpost), {}
## for a type with none.
static func site_spec(module_type: String) -> Dictionary:
	return (loot_data().sites as Dictionary).get(ZoneModules.base(module_type), {})


## The tier weights a site type's boxes roll by (its own, else the default), in percent.
static func tier_weights(module_type: String) -> Dictionary:
	return site_spec(module_type).get("tier_weights", loot_data().default_weights)


## Where a module of `module_type` gets its boxes and what is in each: [{"key" (the spot's id),
## "pos" (module space, on its floor), "label", "table", "tier", "items" ([{"id", "count"}])}].
## `seed_key` names the site (the zone's id and the module's id): the same key always gives the
## same boxes and the same loot. `hot`: a hot zone (very rare finds; elsewhere capped to rare).
static func site_plan(module_type: String, seed_key: String, hot: bool) -> Array:
	var out: Array = []
	var spec := site_spec(module_type)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key + "|boxes")
	var weights := tier_weights(module_type)
	if spec.is_empty():
		var loot: Array = ZoneModules.LOOT.get(module_type, []) if ZoneModules.has_type(module_type) else []
		var fallback: Dictionary = loot_data().get("fallback", {})
		if loot.is_empty() or fallback.is_empty():
			return out
		var count := mini(rng.randi_range(int(fallback.extra[0]), int(fallback.extra[1])), mini(loot.size(), SITE_BOX_OFFSETS.size()))
		for k in count:
			var anchor: Vector3 = (loot[loot.size() - 1 - k] as Dictionary).pos
			var key := "loot%d" % k
			var roll := roll_box(String(fallback.table), weights, "%s|%s" % [seed_key, key], hot)
			out.append({"key": key, "pos": anchor - Vector3(0, LOOT_ANCHOR_LIFT_M, 0) + SITE_BOX_OFFSETS[k], "label": String(fallback.get("label", "Cache")),
				"table": String(fallback.table), "tier": roll.tier, "items": roll.items})
		return out
	var spots: Array = spec.spots
	var others: Array = []
	for i in spots.size():
		if not bool((spots[i] as Dictionary).get("always", false)):
			others.append(i)
	for i in range(others.size() - 1, 0, -1):  # a shuffle of the others, by the site
		var j := rng.randi_range(0, i)
		var t: int = others[i]
		others[i] = others[j]
		others[j] = t
	var extra: Array = spec.get("extra", [0, 0])
	var chosen := others.slice(0, mini(rng.randi_range(int(extra[0]), int(extra[1])), others.size()))
	for i in spots.size():
		var spot: Dictionary = spots[i]
		if not bool(spot.get("always", false)) and i not in chosen:
			continue
		var roll := roll_box(String(spot.table), weights, "%s|%s" % [seed_key, spot.id], hot)
		out.append({"key": String(spot.id), "pos": Vector3(float(spot.pos[0]), 0.0, float(spot.pos[1])), "label": String(spot.get("label", "Cache")),
			"table": String(spot.table), "tier": roll.tier, "items": roll.items})
	return out


## One box's roll: a tier by `weights` (capped outside a hot zone, cap_outside_hot), then one
## bundle of that tier from `table`, its counts rolled. Seeded by `seed_key` alone (the site and
## the spot), so one box's roll never shifts another's. {"tier", "items": [{"id", "count"}]}.
static func roll_box(table: String, weights: Dictionary, seed_key: String, hot: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key + "|loot")
	var tier := roll_tier(rng, weights)
	if not hot:
		tier = String((loot_data().get("cap_outside_hot", {}) as Dictionary).get(tier, tier))
	var bundles: Array = ((loot_data().tables as Dictionary).get(table, {}) as Dictionary).get(tier, [])
	var items: Array = []
	if bundles.is_empty():
		push_error("WorldValuables: loot table %s has no %s tier" % [table, tier])
		return {"tier": tier, "items": items}
	for row: Array in bundles[rng.randi_range(0, bundles.size() - 1)]:
		var count := int(row[1]) if row.size() < 3 else rng.randi_range(int(row[1]), int(row[2]))
		items.append({"id": String(row[0]), "count": count})
	return {"tier": tier, "items": items}


## A tier by `weights` (tier -> weight; any scale), in TIERS order.
static func roll_tier(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for tier: String in TIERS:
		total += float(weights.get(tier, 0.0))
	var roll := rng.randf() * total
	for tier: String in TIERS:
		var w := float(weights.get(tier, 0.0))
		if w > 0.0 and roll < w:
			return tier
		roll -= w
	return TIERS[0]


## A pool's roll (the loot tables' "pools": dead_drop, field_cache, strongbox): a tier by the pool's
## own weights (capped outside a hot zone), then one bundle of that tier from its table; the same
## {"tier", "items"} as roll_box. Seeded by `seed_key` alone.
static func pool_roll(pool: String, seed_key: String, hot: bool) -> Dictionary:
	var spec: Dictionary = (loot_data().get("pools", {}) as Dictionary).get(pool, {})
	if spec.is_empty():
		push_error("WorldValuables: no loot pool %s" % pool)
		return {"tier": TIERS[0], "items": []}
	return roll_box(String(spec.table), spec.tier_weights, "%s|%s" % [pool, seed_key], hot)


## What a man carries on him (Captain, 2026-10-20: "we stil havent gotten loot variety in somehow":
## bodies, where most looting happens, carried only their fixed kit): POCKET_ROLLS rolls of the
## "pockets" pool (cash, cigarettes, meds, ammo; rarer phones and documents, grenades, an optic,
## gold; a laptop or NVGs now and then), a leader one more of "pockets_leader" (his intel). Each
## [{"id", "count"}]. `seed_key` makes it repeatable; `hot` lets very rare through (cap_outside_hot).
const POCKET_ROLLS := Vector2i(1, 3)


static func roll_pockets(seed_key: String, hot: bool, leader := false) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key + "|pockets")
	var out: Array = []
	for i in rng.randi_range(POCKET_ROLLS.x, POCKET_ROLLS.y):
		out.append_array(pool_roll("pockets", "%s|%d" % [seed_key, i], hot).items)
	if leader:
		out.append_array(pool_roll("pockets_leader", seed_key, hot).items)
	return out


## An HQ strongbox's contents (by the module id: the same HQ always holds the same): always one
## piece of contraband and one of intel, and a roll of the strongbox pool's valuables (a modest
## stack most times, now and then a real prize), half the time a Vantage ledger too. `hot`: a hot
## zone (a very rare prize; elsewhere capped to rare).
static func strongbox_contents(module_id: String, hot := true) -> Array:
	var h := hash("strongbox:" + module_id)
	var items: Array = (pool_roll("strongbox", module_id, hot).items as Array).duplicate(true)
	items.append({"id": CONTRABAND_ITEMS[posmod(h, CONTRABAND_ITEMS.size() - 1)], "count": 1})
	items.append({"id": INTEL_ITEMS[posmod(h >> 4, INTEL_ITEMS.size())], "count": 1})
	if posmod(h >> 8, 2) == 0:
		items.append({"id": "vantage_ledger", "count": 1})
	return items
