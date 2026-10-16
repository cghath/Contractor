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

const DEAD_DROP_SHARE := 0.55
const CACHE_GUNS: Array[String] = ["akm", "ak74", "rpk"]
const CACHE_MEDICAL: Array[String] = ["ifak", "trauma_kit", "tourniquet"]
const VALUABLE_ITEMS: Array[String] = ["cash_bundle", "gold_bars", "jewelry_case", "smuggled_relic"]
const INTEL_ITEMS: Array[String] = ["intel_documents", "intel_phone", "intel_usb_drive", "intel_ledger"]
const SALVAGE_ITEMS: Array[String] = ["scrap_copper", "machine_parts", "electronics_salvage"]
const LIFT_M := 0.35


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
