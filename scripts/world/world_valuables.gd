class_name WorldValuables
extends RefCounted
## Lootable value out in the open terrain, away from the mission sites (Captain, 2026-10-16,
## playtest B1399 on Red Mesa: "nothing to loot out in the world"): at each VALUABLE site
## ZoneScatter marked (same placement rules as its rocks and trees, well clear of a road or a
## pad), either a dead drop (one piece of cash or intel) or a small wreck/cache (a weapon, its
## mags, and a medical item) left lying in the open.
##
## Ordinary WorldItems, so these drop into the existing flow rather than a parallel one: picking
## one up already feeds the economy (Prices.sell_price) and, for intel, IntelReveal's reveal
## scan. Host only, spawned once a zone hosts (ZoneLevel._on_hosted); each pickup gets a stable
## uid from its site's index, so GameState.is_looted keeps a taken one from coming back and a
## zone reload doesn't duplicate what's already gone.

const DEAD_DROP_SHARE := 0.55
const CACHE_GUNS: Array[String] = ["akm", "ak74", "rpk"]
const CACHE_MEDICAL: Array[String] = ["ifak", "trauma_kit", "tourniquet"]
const VALUABLE_ITEMS: Array[String] = ["cash_bundle", "gold_bars", "jewelry_case", "smuggled_relic"]
const INTEL_ITEMS: Array[String] = ["intel_documents", "intel_phone", "intel_usb_drive", "intel_ledger"]
const SALVAGE_ITEMS: Array[String] = ["scrap_copper", "machine_parts", "electronics_salvage"]
const CLUSTER_SPREAD_M := 0.5
const LIFT_M := 0.35


## Host: every VALUABLE site the zone's scatter marked (skips any already looted).
static func server_spawn_all(level: ZoneLevel) -> void:
	if not level.multiplayer.is_server() or level.scatter == null or level.terrain == null:
		return
	var sites := level.scatter.valuable_sites()
	for i in sites.size():
		_spawn_site(level, sites[i], "scatter_val%d" % i, i)


## One site: a dead drop (one item) or a small cache (gun, its mags, a medical item), rolled
## deterministically from the zone's seed and the site's index (so it's the same roll every time
## this zone hosts; only which parts are already taken differs, by uid).
static func _spawn_site(level: ZoneLevel, site: Dictionary, uid: String, index: int) -> void:
	var pos: Vector3 = site.pos
	var ground: Vector3 = level.ground_point(Vector3(pos.x, 0.0, pos.z)) + Vector3.UP * LIFT_M
	var rng := RandomNumberGenerator.new()
	rng.seed = level.terrain.seed_value ^ 0x7A1E ^ index
	if rng.randf() < DEAD_DROP_SHARE:
		var pool := INTEL_ITEMS if rng.randf() < 0.5 else VALUABLE_ITEMS
		_spawn_one(level, pool[rng.randi() % pool.size()], 1, ground, "%s_d" % uid)
		return
	var gun := CACHE_GUNS[rng.randi() % CACHE_GUNS.size()]
	var kit: Array = CompoundLevel.HOSTILE_GUNS.get(gun, [gun])
	_spawn_one(level, gun, 1, ground, "%s_g" % uid)
	if kit.size() > 1:
		_spawn_one(level, String(kit[1]), kit.size() - 1, ground + Vector3(CLUSTER_SPREAD_M, 0, 0.2), "%s_m" % uid)
	var extra := SALVAGE_ITEMS[rng.randi() % SALVAGE_ITEMS.size()] if rng.randf() < 0.4 else CACHE_MEDICAL[rng.randi() % CACHE_MEDICAL.size()]
	_spawn_one(level, extra, 1, ground + Vector3(-CLUSTER_SPREAD_M, 0, -0.2), "%s_k" % uid)


static func _spawn_one(level: ZoneLevel, id: String, count: int, pos: Vector3, uid: String) -> void:
	if not GameState.is_looted(uid):
		level.spawn_item(StringName(id), count, pos, uid)
