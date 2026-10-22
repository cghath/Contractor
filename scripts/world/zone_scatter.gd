class_name ZoneScatter
extends Node3D
## Rocks, scrub and trees on a zone's terrain (the terrain preset's "scatter": items per km2 of
## zone, so a bigger zone gets more, up to caps). Deterministic from the zone's seed and
## preset: every peer lays out the same items. Never on a module's pad, an insertion or
## extraction point, a road, in the sea or on steep ground.
##
## Trees grow in clusters (Captain, 2026-10-14: "we need copses and groves and such. the
## terrain is too empty"): woods with a ragged outline, tight copses, hedgerows along field
## edges, lines along the roads, groves on wadi banks, thick scrub and thickets at and in the
## woods, and only a few lone trees. See _lay_out_trees and docs/terrain_presets.md.
##
## Visuals are MultiMeshes per CELL_M square (low-poly blocky shapes, in the voxel look),
## built nearest cells first as the camera comes near (like the terrain's finest level) and
## skipped on a headless server; past SEE_TREE_M the trees give way to low canopy blobs (one
## per FAR_GROUP_M square of trees) out to the horizon. Large rocks and tree trunks also have
## collision (one static body per cell, built up front: cover for the AI) and are baked into the
## navigation mesh as boxes; scrub and thickets are visual only (and hide people: foliage_between).
##
## The layout is cached (Captain, 2026-10-14: "we'll use caching for performance if needed"):
## in memory per zone (seed, preset, ground, pads, roads) with the cells' built meshes, and on
## disk (user://cache), so coming back to a zone costs nothing.
##
## Ruins and wrecks (Captain, 2026-10-16, playtest B1399 on Red Mesa: "open terrain reads nearly
## empty"): bigger, rougher PROP clutter out in the open terrain, not just roadside. VALUABLE
## marks where WorldValuables spawns real lootable pickups (caches, crates, wrecks with kit, dead
## drops) — a placement kind with no mesh of its own; see valuable_sites().

enum Kind { ROCK, SCRUB, TREE, THICKET, PROP, VALUABLE }

## Most items of each kind in a zone (a 16 km2 hot zone hits them). Round 4 raised the trees
## for the woods; a nav chunk is 12 m (ZoneNav), so more trunk boxes cost little per bake.
## Captain, 2026-10-14 (v0.4.0): "the copses of trees are too small and spread out to be
## cover": bigger, denser copses, so trees 5000 -> 6000, thickets 5000 -> 8000 (visual only,
## no collision) and solid 5600 -> 6800 (Proposed).
const CAP_ROCKS := 2600
const CAP_SCRUB := 9000
const CAP_TREES := 9000  # Captain, 2026-10-16: "forests still are too small" (was 6000); 2026-10-17: sprawling woods (was 8000)
const CAP_THICKETS := 11000  # sprawling woods take more (2026-10-17; was 8000): copses keep their thicket skirts
## The shares of CAP_TREES woods, then woods with copses and groves, may take (Proposed: woods
## keep their 3000 trees, round 4's 0.6 of 5000; copses get the most of the rest).
const WOODS_SHARE := 0.5
const COPSES_SHARE := 0.8
## Most items with collision in a zone, rocks and props (trees are always solid since 2026-10-18:
## the Captain's "hitboxes of trees", some trunks past the cap were walk- and shoot-through).
const CAP_SOLID := 9800  # (was 6800, then 8800; the extra trees)
## Man-made clutter (Captain, 2026-10-16: "the terrains need more objects too"): crates and
## debris, sparser than rocks/scrub and only near a road or a pad ("props_near_m"), not out in
## open wilderness; shares this cap with the ruins and wrecks below (both Kind.PROP).
const CAP_PROPS := 1000
## Ruins and wrecks (Captain, 2026-10-16, playtest B1399 on Red Mesa: "open terrain reads
## nearly empty", "nothing to loot out in the world"): broken man-made clutter out in the open
## terrain too, not just roadside ("ruins_per_km2"), placed like the rocks are (anywhere open,
## away from the pads and roads' own keep-out, no "near a road" requirement). Bigger and rougher
## than the roadside crates, so they read as ruins and wrecks, not more debris.
const RUIN_SIZE_LO := 1.2
const RUIN_SIZE_HI := 3.0
## Lootable value out in the open terrain, well away from a mission site or a road (caches,
## crates, wrecks with kit, dead drops): WorldValuables spawns the real pickups at these marked
## spots (ZoneScatter.valuable_sites), so this is only placement, no mesh of its own.
const CAP_VALUABLES := 40
const VALUABLE_AVOID_M := 70.0
## Captain, 2026-10-14 ("include experimental forest mission like we dev'd"; the normal zones'
## woods have a perf problem, a perf pass is queued): the copses-as-cover layout (the caps above,
## COPSE_SPREAD's copses, the woods' edge belt) only for a preset whose scatter says
## "copse_cover": true (forest_experimental). Every other preset keeps round 4's layout and these
## caps, so the normal zones keep today's density.
const ROUND4_CAP_TREES := 5000
const ROUND4_CAP_THICKETS := 5000
const ROUND4_WOODS_SHARE := 0.6
const ROUND4_COPSES_SHARE := 0.82
const ROUND4_CAP_SOLID := 5600
## Items keep this far outside every pad (the pad's own margin is already in its rect), the
## edge of the zone, and a road's line (m).
const PAD_KEEP_M := 10.0
const EDGE_KEEP_M := 12.0
const ROAD_KEEP_M := 9.0
## Trees keep this far apart (trunk to trunk, m), and stand on ground at least this level
## (the up component of its normal).
const TREE_GAP_M := 2.6
## Copses (Captain, 2026-10-14: "the copses of trees are too small and spread out to be
## cover"; Proposed numbers): a compact blob of radius COPSE_SPREAD x sqrt(trees) + 2 m (20 trees
## ~10.5 m, 60 ~16.7 m; trees ~3-3.5 m apart), "copse_thicket_share" thickets a tree inside, a
## ring of thickets every COPSE_SKIRT_M round its edge (no gap to see through at eye height),
## the edge scrub outside that, and COPSE_ROCKS [min, max] big rocks inside as low cover.
const COPSE_SPREAD := 2.6  # sprawling more (Captain, 2026-10-16; was 1.9). Kept tight for cover: the woods sprawl instead (WOOD_SPRAWL)
const COPSE_SKIRT_M := 2.2
const COPSE_ROCKS := [1, 3]
## Woods' edge belt (Proposed): a thicket every WOOD_BELT_M round a wood's ragged edge, just
## inside it, so a wood's edge hides like a copse's.
const WOOD_BELT_M := 3.5
## Scrub belts out in the open (_scrub_belts; Proposed): per km2, length [min, max] (m), a bush
## every BELT_STEP_M along it on alternate sides of the line, BELT_ROW_M off it, BELT_SIZE
## [min, max] wide, a gentle bend (radians over its length), one BELT_GAP_M gap; at most
## BELT_CAP of their own.
const BELTS_PER_KM2 := 8.0
const BELT_LEN_M := [50.0, 150.0]
const BELT_STEP_M := 1.8
const BELT_ROW_M := 0.9
const BELT_SIZE := [1.6, 2.6]
const BELT_BEND := 0.6
const BELT_GAP_M := 8.0
const BELT_CAP := 6000
## Captain, 2026-10-17: "wooded areas on maps are too small, too compacted per se. they need to
## sprawl a bit more". Woods are WOOD_SPRAWL times the preset's "wood_radius_m"; full density out
## to WOOD_CORE of the radius, thinning to WOOD_EDGE_DENSITY at the ragged edge (straggling
## trees, not a wall); and WOOD_OUTLIERS [min, max] small copses (WOOD_OUTLIER_TREES) scattered
## WOOD_OUTLIER_R [min, max] radii out round each, so a wood frays into the open. Proposed.
const WOOD_SPRAWL := 1.35
const WOOD_CORE := 0.85
const WOOD_EDGE_DENSITY := 0.65
const WOOD_OUTLIERS := [1, 3]
const WOOD_OUTLIER_TREES := [6, 18]
const WOOD_OUTLIER_R := [1.05, 1.7]
const TREE_UP := 0.88
## Cells are this wide (m); visuals build for cells within BUILD_M of the camera, this many a
## frame, checked every CHECK_S.
const CELL_M := 128.0
const BUILD_M := 1000.0
const PER_FRAME := 2
const CHECK_S := 0.5
## Draw distances (m): scrub, rocks, trunks and crowns (thickets with the trees).
const SEE_SCRUB_M := 470.0  # bushes read at mid range (round 3: was 400)
const SEE_ROCK_M := 650.0
const SEE_TREE_M := 950.0
## Far stand-ins: past SEE_TREE_M each FAR_GROUP_M square of trees is one low canopy blob.
const FAR_GROUP_M := 24.0
## Layout format: bump when the layout code changes, so old cached layouts are not used.
## 7: denser copses with a thicket skirt and rocks, woods' edge belt (Captain, 2026-10-14).
## 8: ruins and wrecks off the roads, and the VALUABLE placement kind (Captain, 2026-10-16).
## 9: sprawling woods (WOOD_SPRAWL, thinning edges, outlier copses) (Captain, 2026-10-17).
## 10: scrub belts out in the open (_scrub_belts) (Captain, 2026-10-18).
const LAYOUT_VERSION := 11  # 11: every tree solid (2026-10-18), old caches re-roll
## Zones kept in memory (layouts), the newest of them also keep their built cell meshes, and
## files kept in the disk cache.
const CACHE_ZONES := 4
const CACHE_VISUAL_ZONES := 2
const CACHE_FILES := 24
const CACHE_DIR := "user://cache"

## Foliage shapes for spotting (foliage_between), as shares of an item's size (its meshes:
## _scrub_mesh, _crown_mesh), and how far past a line's ends an item can still reach it (m).
## Thickets are scrub-shaped (the same mesh, taller).
const SCRUB_R := 0.5
const SCRUB_TOP := 0.6
const CROWN_R := 1.1
const CROWN_LOW := 2.0
const CROWN_HIGH := 4.9
## A conifer's crown (_conifer_mesh) is a narrowing stack, not a round blob (world visual pass,
## cghath 2026-10-20: its top hid people where no needle was): its cylinder is CONIFER_R x its size
## round, from CROWN_LOW up to CONIFER_HIGH x its size (above that it's a spike).
const CONIFER_R := 0.85
const CONIFER_HIGH := 3.9
const FOLIAGE_PAD_M := 3.0
## Ground cover (visual only, not in `items`, no collision, no effect on sight or the layout's
## checksum): grass tufts and pebbles laid out per cell when it builds, from the cell and the
## seed, so every peer draws the same. The preset's scatter "tufts_per_km2" (0: none) and
## "pebbles_per_km2"; seen out to SEE_TUFT_M / SEE_PEBBLE_M.
const SEE_TUFT_M := 140.0
const SEE_PEBBLE_M := 70.0
## Rock clusters (the preset's scatter "rock_clusters_per_km2"), visual only like the tufts.
const SEE_OUTCROP_M := 300.0
const CAP_TUFTS_PER_CELL := 1200

## Layouts by cache key: {"items", "cells", "counts", "solid", "visual" (cell -> built
## MultiMesh parts), "far" (cell -> MultiMesh)}; _cache_order oldest first.
static var _cache := {}
static var _cache_order: Array[String] = []
## Shared shapes (by the trunk colour) and the material.
static var _shapes := {}
static var _shared_material: StandardMaterial3D

## Every item: {"kind", "pos" (Vector3), "yaw", "size" (Vector3), "colour" (Color), "solid"}.
var items: Array[Dictionary] = []
var counts := {Kind.ROCK: 0, Kind.SCRUB: 0, Kind.TREE: 0, Kind.THICKET: 0, Kind.PROP: 0, Kind.VALUABLE: 0}
var solid_count := 0
## Where the last generate's layout came from: "generated", "memory" or "disk" ("" none).
var cache_source := ""
## The copses and groves the last fresh layout made (not kept in the cache: empty when the
## layout came from memory or disk), for tests: {"centre" (Vector2), "r" (m), "trees", "grove"}.
var copse_sites: Array[Dictionary] = []

var _terrain: ZoneTerrain
var _spec := {}
var _cells := {}  # Vector2i -> Array of item indices
var _built := {}  # Vector2i -> true
var _meshes := {}
var _material: StandardMaterial3D
var _next_check := 0.0
var _visuals_on := false
var _keep: Array[Rect2] = []
var _roads: Array = []
## The road pieces by ROAD_CELL_M cell (_roads_near). Roads (cg_brief 1.2): the curved roads come as
## hundreds of short pieces, too many to test every one for every item tried.
const ROAD_CELL_M := 48.0
var _road_cells := {}
var _cluster: FastNoiseLite
var _key := ""
var _entry := {}  # this zone's cache entry
var _far := {}  # cell -> MultiMesh of far blobs (built in build_visuals)
# While laying out: the zone's half width, colours, scrub sizes, the trees placed so far by
# TREE_GAP_M square (_crowded), and the noise that ragged the woods' outlines.
var _half := 0.0
var _crowns: Array[Color] = []
var _scrubs: Array[Color] = []
var _scrub_lo := 0.6
var _scrub_hi := 1.5
var _rock_colours: Array[Color] = []
var _tree_grid := {}
var _outline: FastNoiseLite
var _tree_limit := CAP_TREES  # the trees allowed so far in the layout (woods leave room for the rest)
## This layout's caps: CAP_* with "copse_cover", else ROUND4_CAP_* (_set_caps).
var _cover := false
var _cap_trees := ROUND4_CAP_TREES
var _cap_thickets := ROUND4_CAP_THICKETS
var _cap_solid := ROUND4_CAP_SOLID
var _woods_share := ROUND4_WOODS_SHARE
var _copses_share := ROUND4_COPSES_SHARE


## Lays the items out. `terrain` must be generated; `def` is the zone's def ("roads" in it
## keep clear).
func generate(terrain: ZoneTerrain, def: Dictionary) -> void:
	_terrain = terrain
	var fresh: Array[Dictionary] = []
	items = fresh  # new arrays, never clear(): a cached layout may share the old ones
	_cells = {}
	_built = {}
	counts = {Kind.ROCK: 0, Kind.SCRUB: 0, Kind.TREE: 0, Kind.THICKET: 0, Kind.PROP: 0, Kind.VALUABLE: 0}
	solid_count = 0
	cache_source = ""
	var sites: Array[Dictionary] = []
	copse_sites = sites
	_spec = terrain.preset.get("scatter", {})
	_set_caps()
	if _spec.is_empty():
		return
	var keep: Array[Rect2] = []
	for pad: Array in terrain.pads:
		keep.append((pad[0] as Rect2).grow(PAD_KEEP_M))
	_keep = keep
	_roads = def.get("roads", [])
	_index_roads()
	var cluster := FastNoiseLite.new()
	cluster.seed = terrain.seed_value + 77
	cluster.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cluster.frequency = 1.0 / 240.0
	_cluster = cluster
	_key = _cache_key()
	if _from_memory() or _from_disk():
		return
	_lay_out()
	cache_source = "generated"
	_remember()
	_to_disk()


## The caps for this preset: the copses-as-cover ones with "copse_cover", else round 4's.
func _set_caps() -> void:
	_cover = bool(_spec.get("copse_cover", false))
	_cap_trees = CAP_TREES if _cover else ROUND4_CAP_TREES
	_cap_thickets = CAP_THICKETS if _cover else ROUND4_CAP_THICKETS
	_cap_solid = CAP_SOLID if _cover else ROUND4_CAP_SOLID
	_woods_share = WOODS_SHARE if _cover else ROUND4_WOODS_SHARE
	_copses_share = COPSES_SHARE if _cover else ROUND4_COPSES_SHARE


func _lay_out() -> void:
	var terrain := _terrain
	_half = terrain.size_m * 0.5
	var area_km2 := terrain.size_m * terrain.size_m / 1.0e6
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain.seed_value ^ 0x5CA7
	if float(_spec.get("tufts_per_km2", 0.0)) > 0.0:
		# Ground cover goes in every cell, not only those holding an item.
		var cells := ceili(terrain.size_m / CELL_M)
		for cz in cells:
			for cx in cells:
				if not _cells.has(Vector2i(cx, cz)):
					_cells[Vector2i(cx, cz)] = []
	var colours: Dictionary = _spec.get("colours", {})
	var rock_colours := _colours(colours.get("rock", ["77736a"]))
	_rock_colours = rock_colours
	_scrubs = _colours(colours.get("scrub", ["55633a"]))
	_crowns = _colours(colours.get("crown", ["46602f"]))
	var large_share := float(_spec.get("large_rock_share", 0.15))
	# An open middle (scatter "margin_m", the salt pan): items only at the margins and round
	# the pads and roads, so the tries go up by how little of the zone that is.
	var open := float(_spec.get("margin_m", 0.0)) > 0.0
	var tries_per := 4.0 / maxf(_open_share(), 0.05) if open else 4.0
	var scrub_size: Array = _spec.get("scrub_size", [0.6, 1.5])
	_scrub_lo = float(scrub_size[0])
	_scrub_hi = float(scrub_size[1])
	_tree_grid = {}
	# Rocks.
	var want := mini(int(round(float(_spec.get("rocks_per_km2", 0.0)) * area_km2)), CAP_ROCKS)
	var attempts := int(want * tries_per)
	while counts[Kind.ROCK] < want and attempts > 0:
		attempts -= 1
		var x := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		var z := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		var yaw := rng.randf() * TAU
		var pick := rng.randf()
		var variation := rng.randf()
		var scale_roll := rng.randf()
		var squash_roll := rng.randf()
		if open and rng.randf() > _open_weight(x, z):
			continue
		if _blocked(x, z, _keep, _roads):
			continue
		var h := terrain.height_at(x, z)
		if terrain.sea_side >= 0 and h < terrain.sea_level + 0.35:
			continue
		if terrain.normal_at(x, z).y < 0.55:
			continue
		var large := pick < large_share and solid_count < _cap_solid
		var s := lerpf(1.6, 3.4, scale_roll) if large else lerpf(0.35, 1.1, scale_roll)
		var size := Vector3(s, s * lerpf(0.55, 0.85, squash_roll), s * lerpf(0.8, 1.2, squash_roll))
		_add({"kind": Kind.ROCK, "yaw": yaw, "solid": large, "size": size, "pos": Vector3(x, h + size.y * 0.3, z),
			"colour": rock_colours[int(variation * rock_colours.size()) % rock_colours.size()]})
	# Man-made clutter: crates and debris, only near a road or pad (props_near_m), not loose
	# in the wilderness like rocks.
	var prop_colours := _colours(colours.get("prop", ["5a5440", "6b4f33", "767166"]))
	var props_near := float(_spec.get("props_near_m", 0.0))
	want = mini(int(round(float(_spec.get("props_per_km2", 0.0)) * area_km2)), CAP_PROPS)
	attempts = int(want * tries_per)
	while counts[Kind.PROP] < want and attempts > 0 and props_near > 0.0:
		attempts -= 1
		var x := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		var z := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		if not _near_road_or_pad(x, z, props_near):
			continue
		if _blocked(x, z, _keep, _roads):
			continue
		var h := terrain.height_at(x, z)
		if terrain.sea_side >= 0 and h < terrain.sea_level + 0.35:
			continue
		if terrain.normal_at(x, z).y < 0.7:
			continue
		var size := Vector3(rng.randf_range(0.5, 1.1), rng.randf_range(0.4, 0.8), rng.randf_range(0.5, 1.1))
		_add({"kind": Kind.PROP, "yaw": rng.randf() * TAU, "solid": true, "size": size, "pos": Vector3(x, h + size.y * 0.5, z),
			"colour": prop_colours[rng.randi() % prop_colours.size()]})
	# Ruins and wrecks: bigger, rougher man-made clutter out in the open terrain too
	# (Captain, 2026-10-16, playtest B1399 on Red Mesa: "open terrain reads nearly empty"),
	# not gated to a road or a pad like the crates above — placed like the rocks are.
	var ruin_colours := _colours(colours.get("ruin", ["5a5648", "6b645a", "4a4038", "68503c"]))
	want = mini(int(round(float(_spec.get("ruins_per_km2", 0.0)) * area_km2)), CAP_PROPS - counts[Kind.PROP])
	attempts = int(want * tries_per)
	while want > 0 and attempts > 0:
		attempts -= 1
		var x := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		var z := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		if _blocked(x, z, _keep, _roads):
			continue
		if open and rng.randf() > _open_weight(x, z):
			continue
		var h := terrain.height_at(x, z)
		if terrain.sea_side >= 0 and h < terrain.sea_level + 0.35:
			continue
		if terrain.normal_at(x, z).y < 0.6:
			continue
		var size := Vector3(rng.randf_range(RUIN_SIZE_LO, RUIN_SIZE_HI), rng.randf_range(RUIN_SIZE_LO, RUIN_SIZE_HI) * 0.6, rng.randf_range(RUIN_SIZE_LO, RUIN_SIZE_HI))
		_add({"kind": Kind.PROP, "yaw": rng.randf() * TAU, "solid": true, "size": size, "pos": Vector3(x, h + size.y * 0.5, z),
			"colour": ruin_colours[rng.randi() % ruin_colours.size()]})
		want -= 1
	# Valuable sites: where WorldValuables (host) will spawn real lootable pickups (caches,
	# crates, wrecks with kit, dead drops) — well away from a site or a road (VALUABLE_AVOID_M,
	# more than the bare pad/road keep-out), so this never marks a spot right by a mission.
	# No mesh of its own: ZoneScatter only places the marker, deterministic like everything else.
	want = mini(int(round(float(_spec.get("valuables_per_km2", 0.0)) * area_km2)), CAP_VALUABLES)
	attempts = int(want * tries_per)
	while counts[Kind.VALUABLE] < want and attempts > 0:
		attempts -= 1
		var x := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		var z := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		if _near_road_or_pad(x, z, VALUABLE_AVOID_M) or _blocked(x, z, _keep, _roads):
			continue
		if open and rng.randf() > _open_weight(x, z):
			continue
		var h := terrain.height_at(x, z)
		if terrain.sea_side >= 0 and h < terrain.sea_level + 0.35:
			continue
		if terrain.normal_at(x, z).y < 0.6:
			continue
		_add({"kind": Kind.VALUABLE, "yaw": rng.randf() * TAU, "solid": false, "size": Vector3.ONE * 0.6,
			"pos": Vector3(x, h, z), "colour": Color.WHITE})
	# Trees in clusters, with their edge scrub and thickets, then the few lone trees.
	_lay_out_trees(area_km2)
	want = mini(int(round(float(_spec.get("trees_per_km2", 0.0)) * area_km2)), _cap_trees - counts[Kind.TREE])
	var lone := 0
	attempts = int(want * tries_per)
	while lone < want and attempts > 0:
		attempts -= 1
		var x := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		var z := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		var roll := rng.randf()
		if roll > clampf(_cluster.get_noise_2d(x + 500.0, z - 500.0) * 2.2 + 0.6, 0.05, 1.0):
			continue
		if open and rng.randf() > _open_weight(x, z):
			continue
		if _try_tree(rng, x, z, 0.8, 1.45):
			lone += 1
	# Scrub everywhere, in clumps: denser where the cluster noise is high.
	want = mini(int(round(float(_spec.get("scrub_per_km2", 0.0)) * area_km2)), CAP_SCRUB - counts[Kind.SCRUB])
	var bushes := 0
	attempts = int(want * tries_per)
	while bushes < want and attempts > 0:
		attempts -= 1
		var x := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		var z := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		if rng.randf() > clampf(_cluster.get_noise_2d(x, z) * 1.6 + 0.8, 0.1, 1.0):
			continue
		if open and rng.randf() > _open_weight(x, z):
			continue
		if _try_bush(rng, x, z, Kind.SCRUB, _scrub_lo, _scrub_hi):
			bushes += 1
	_tree_grid = {}


## How much scatter a preset with an open middle (scatter "margin_m"; Captain, 2026-10-14: the
## salt flats were an empty white plate) puts at (x, z), 0 to 1: 1 within "margin_m" of the
## zone's edge (where the terrain's margin has its berm and mesas), fading to 0 over
## "margin_fade_m" further in, and 1 near a pad ("near_pad_m": compounds, landing zones) or a
## road ("near_road_m"), fading out over half that again. The pan's middle stays open, as a pan
## is and for spotting. 1 everywhere for every other preset.
func _open_weight(x: float, z: float) -> float:
	var margin := float(_spec.get("margin_m", 0.0))
	if margin <= 0.0:
		return 1.0
	var half := _terrain.size_m * 0.5
	var edge := minf(half - absf(x), half - absf(z))
	var w := 1.0 - smoothstep(margin, margin + float(_spec.get("margin_fade_m", 200.0)), edge)
	if w >= 1.0:
		return 1.0
	var p := Vector2(x, z)
	var near_pad := float(_spec.get("near_pad_m", 0.0))
	if near_pad > 0.0:
		for r in _keep:
			var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
			var dz := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
			w = maxf(w, 1.0 - smoothstep(near_pad, near_pad * 1.5, Vector2(dx, dz).length()))
	var near_road := float(_spec.get("near_road_m", 0.0))
	if near_road > 0.0:
		for road: Array in _roads_near(p, near_road * 1.5):
			var a := Vector2(float(road[0][0]), float(road[0][1]))
			var b := Vector2(float(road[1][0]), float(road[1][1]))
			var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
			w = maxf(w, 1.0 - smoothstep(near_road, near_road * 1.5, d))
	return w


## The mean of _open_weight over the zone (a 32 x 32 grid of samples).
func _open_share() -> float:
	var half := _terrain.size_m * 0.5
	var sum := 0.0
	for j in 32:
		for i in 32:
			sum += _open_weight(-half + (i + 0.5) * _terrain.size_m / 32.0, -half + (j + 0.5) * _terrain.size_m / 32.0)
	return sum / 1024.0


## The clustered trees, from the preset's scatter (all optional, per km2 of zone unless said):
## "woods_per_km2" (ragged woods "wood_radius_m" [min, max] across, trees "wood_spacing_m"
## apart, "thicket_share" of the sites also a thicket), "copses_per_km2" (tight clumps of
## "copse_trees" [min, max]), "hedgerows_per_km2" (tree and bush lines along the edges of
## "field_m" fields), "road_trees" (0..1: the share of the roads' sides lined), and
## "wadi_groves_per_km2" (clumps of "wadi_grove_trees" on the wadis' banks). Every wood, copse
## and grove gets "edge_scrub_per_m" bushes per metre round its edge.
func _lay_out_trees(area_km2: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _terrain.seed_value ^ 0xC0B5
	_outline = FastNoiseLite.new()
	_outline.seed = _terrain.seed_value + 91
	_outline.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_outline.frequency = 1.0 / 60.0
	var inner := _half - EDGE_KEEP_M
	# Woods first (the biggest), then copses: each where the cluster noise favours trees.
	var radius: Array = _spec.get("wood_radius_m", [50.0, 130.0])
	# Woods take at most WOODS_SHARE of the tree cap and copses and groves up to COPSES_SHARE, so
	# a big zone's woods leave trees for its copses, hedgerows and roadsides.
	_tree_limit = int(_cap_trees * _woods_share)
	for n in _how_many(rng, float(_spec.get("woods_per_km2", 0.0)) * area_km2):
		var at := _cluster_site(rng, inner)
		var r := rng.randf_range(float(radius[0]), float(radius[1])) * 0.5 * WOOD_SPRAWL
		_wood(rng, at.x, at.y, r)
		for k in rng.randi_range(int(WOOD_OUTLIERS[0]), int(WOOD_OUTLIERS[1])):
			var a := rng.randf() * TAU
			var d := r * rng.randf_range(float(WOOD_OUTLIER_R[0]), float(WOOD_OUTLIER_R[1]))
			_copse(rng, at.x + cos(a) * d, at.y + sin(a) * d, rng.randi_range(int(WOOD_OUTLIER_TREES[0]), int(WOOD_OUTLIER_TREES[1])), false, false)
	_tree_limit = int(_cap_trees * _copses_share)
	var copse: Array = _spec.get("copse_trees", [35, 110] if _cover else [25, 90])  # bigger woods (Captain, 2026-10-16; was 20-60 / 10-40)  # Proposed (round 4: 10-40)
	for n in _how_many(rng, float(_spec.get("copses_per_km2", 0.0)) * area_km2):
		var at := _cluster_site(rng, inner)
		_copse(rng, at.x, at.y, rng.randi_range(int(copse[0]), int(copse[1])))
	# Groves on the wadi banks (the bed's gentle sides, not its floor).
	var groves := _how_many(rng, float(_spec.get("wadi_groves_per_km2", 0.0)) * area_km2)
	var grove: Array = _spec.get("wadi_grove_trees", [6, 16])
	var tries := groves * 60
	while groves > 0 and tries > 0:
		tries -= 1
		var x := rng.randf_range(-inner, inner)
		var z := rng.randf_range(-inner, inner)
		var bed := _terrain.bed_at(x, z)
		if bed < 0.06 or bed > 0.45:
			continue
		_copse(rng, x, z, rng.randi_range(int(grove[0]), int(grove[1])), true)
		groves -= 1
	_tree_limit = _cap_trees
	_hedgerows(rng, _how_many(rng, float(_spec.get("hedgerows_per_km2", 0.0)) * area_km2))
	_road_lines(rng, float(_spec.get("road_trees", 0.0)))
	_scrub_belts(rng, _how_many(rng, float(_spec.get("belts_per_km2", BELTS_PER_KM2)) * area_km2))


## Scrub belts (Captain, 2026-10-18: "we need to not have so many 300m sightlines"; the
## tests/sightline_probe.gd baseline: 38% of eye-level 300 m lines clear over the campaign zones):
## a staggered double row of thickets BELT_LEN_M [min, max] long, a bush every BELT_STEP_M,
## curving gently, with one BELT_GAP_M gap to walk through, out in the open (scaled by
## _open_weight, so a salt pan's middle stays open). Thickets are visual only (no collision, no
## nav cost) and hide people (foliage_between), so they break up long lines for players and AI
## alike. "belts_per_km2" per preset (BELTS_PER_KM2 without), on their own BELT_CAP on top of
## the thicket cap, so the woods' and copses' skirts keep theirs.
func _scrub_belts(rng: RandomNumberGenerator, count: int) -> void:
	if count <= 0:
		return
	var cap := _cap_thickets
	_cap_thickets = counts[Kind.THICKET] + BELT_CAP
	var inner := _half - EDGE_KEEP_M
	for n in count:
		var at := Vector2(rng.randf_range(-inner, inner), rng.randf_range(-inner, inner))
		if rng.randf() > _open_weight(at.x, at.y):
			continue
		var heading := rng.randf() * TAU
		var bend := rng.randf_range(-1.0, 1.0) * BELT_BEND
		var length := rng.randf_range(float(BELT_LEN_M[0]), float(BELT_LEN_M[1]))
		var gap_at := rng.randf_range(0.2, 0.8) * length
		var t := 0.0
		var row := 0
		while t < length:
			var dir := Vector2.from_angle(heading + bend * (t / length - 0.5))
			var side := Vector2(-dir.y, dir.x)
			var off := (BELT_ROW_M if row % 2 == 0 else -BELT_ROW_M) + rng.randf_range(-0.4, 0.4)
			var p := at + dir * (t - length * 0.5) + side * off
			if absf(t - gap_at) > BELT_GAP_M * 0.5 and _open_weight(p.x, p.y) > 0.0:  # (never into a pan's open middle)
				_try_bush(rng, p.x, p.y, Kind.THICKET, float(BELT_SIZE[0]), float(BELT_SIZE[1]))
			row += 1
			t += BELT_STEP_M * rng.randf_range(0.8, 1.15)
	_cap_thickets = cap


## `v` rounded up or down by chance (so 0.4 a km2 still gives one now and then).
static func _how_many(rng: RandomNumberGenerator, v: float) -> int:
	return int(v + rng.randf())


## A spot for a wood or copse: the best of a few tries by the cluster noise (woods gather).
func _cluster_site(rng: RandomNumberGenerator, inner: float) -> Vector2:
	var best := Vector2.ZERO
	var score := -INF
	for k in 3:
		var p := Vector2(rng.randf_range(-inner, inner), rng.randf_range(-inner, inner))
		var s := _cluster.get_noise_2d(p.x + 500.0, p.y - 500.0)
		if s > score:
			score = s
			best = p
	return best


## How far the edge of the wood round (cx, cz) of mean radius `r` lies at angle `a`: lobed and
## ragged from the outline noise, 0.6 to 1.25 of r.
func _edge_r(cx: float, cz: float, r: float, a: float) -> float:
	return r * (0.92 + 0.5 * _outline.get_noise_2d(cx + cos(a) * 70.0, cz + sin(a) * 70.0))


## A wood: trees on a jittered grid inside its ragged outline, clearings, thickets between the
## trees, thick scrub round the edge.
func _wood(rng: RandomNumberGenerator, cx: float, cz: float, r: float) -> void:
	var spacing := float(_spec.get("wood_spacing_m", 6.5))
	var thickets := float(_spec.get("thicket_share", 0.5))
	var steps := ceili(r * 1.3 / spacing)
	for j in range(-steps, steps + 1):
		for i in range(-steps, steps + 1):
			var x := cx + (i + rng.randf_range(-0.42, 0.42)) * spacing
			var z := cz + (j + rng.randf_range(-0.42, 0.42)) * spacing
			var roll := rng.randf()
			var d := Vector2(x - cx, z - cz)
			var edge := _edge_r(cx, cz, r, d.angle())
			if d.length() > edge:
				continue
			var out := inverse_lerp(edge * WOOD_CORE, edge, d.length())
			if out > 0.0 and rng.randf() > lerpf(1.0, WOOD_EDGE_DENSITY, out):
				continue  # thinning toward the edge: straggling trees
			if _cluster.get_noise_2d(x * 4.0, z * 4.0) < -0.45:
				continue  # a clearing
			if roll < 0.85:
				_try_tree(rng, x, z, 0.75, 1.3)
			if roll > 1.0 - thickets or roll < thickets * 0.4:
				_try_bush(rng, x + spacing * 0.5, z + spacing * 0.3, Kind.THICKET, 2.2, 3.4)
	# The edge belt: thickets just inside the ragged edge (Captain, 2026-10-14: cover at the
	# woods' edge, where a fight meets them). Copses-as-cover presets only (_cover).
	for k in (int(TAU * r / WOOD_BELT_M) if _cover else 0):
		var a := rng.randf() * TAU
		var d := _edge_r(cx, cz, r, a) - rng.randf_range(0.5, 4.0)
		_try_bush(rng, cx + cos(a) * d, cz + sin(a) * d, Kind.THICKET, 2.0, 3.0)
	_edge_scrub(rng, cx, cz, r, true)


## A copse (or a wadi grove, `grove`): `n` trees close together round (cx, cz), thickets among
## them, a thicket skirt and scrub round it, a few big rocks inside. Captain, 2026-10-14: "the
## copses of trees are too small and spread out to be cover" (round 4 had r 2.3 sqrt(n) + 3,
## trees ~3.8 m apart, n / 2 thickets and no skirt: a man at the middle was hidden from 50 m on
## under half the lines). The trees look as before (Captain: "but they look fantastic").
func _copse(rng: RandomNumberGenerator, cx: float, cz: float, n: int, grove := false, record := true) -> void:
	if not _cover:
		_round4_copse(rng, cx, cz, n, grove, record)
		return
	var r := COPSE_SPREAD * sqrt(float(n)) + 2.0
	var placed := 0
	var tries := n * 10
	while placed < n and tries > 0:
		tries -= 1
		var a := rng.randf() * TAU
		var d := r * sqrt(rng.randf())
		if _try_tree(rng, cx + cos(a) * d, cz + sin(a) * d, 0.8, 1.4):
			placed += 1
	if placed > 0:
		# Undergrowth through it (round 4: n / 5, then n / 2, left copses see-through at eye height).
		for k in int(n * float(_spec.get("copse_thicket_share", 0.9))):
			var a := rng.randf() * TAU
			var d := r * 0.9 * sqrt(rng.randf())
			_try_bush(rng, cx + cos(a) * d, cz + sin(a) * d, Kind.THICKET, 1.8, 2.8)
		# The skirt: thickets evenly round the edge, so no line in misses them all.
		var skirt := int(TAU * r / COPSE_SKIRT_M)
		var turn := rng.randf() * TAU
		for k in skirt:
			var a := turn + (k + rng.randf_range(-0.3, 0.3)) * TAU / skirt
			var d := r + rng.randf_range(-1.5, 0.5)
			_try_bush(rng, cx + cos(a) * d, cz + sin(a) * d, Kind.THICKET, 2.0, 2.8)
		_edge_scrub(rng, cx, cz, r, false)
		# Low cover inside: a few big rocks (solid), between the trunks.
		for k in rng.randi_range(int(COPSE_ROCKS[0]), int(COPSE_ROCKS[1])):
			var a := rng.randf() * TAU
			var d := r * 0.7 * sqrt(rng.randf())
			_copse_rock(rng, cx + cos(a) * d, cz + sin(a) * d)
	if record:  # a wood's outlier clumps are the wood's, not copses of their own
		copse_sites.append({"centre": Vector2(cx, cz), "r": r, "trees": placed, "grove": grove})


## Round 4's copse (every preset without "copse_cover"; the normal zones keep it until the
## perf pass): `n` trees round (cx, cz), n / 2 thickets among them, scrub round it.
func _round4_copse(rng: RandomNumberGenerator, cx: float, cz: float, n: int, grove: bool, record := true) -> void:
	var r := 2.3 * sqrt(float(n)) + 3.0
	var placed := 0
	var tries := n * 6
	while placed < n and tries > 0:
		tries -= 1
		var a := rng.randf() * TAU
		var d := r * sqrt(rng.randf())
		if _try_tree(rng, cx + cos(a) * d, cz + sin(a) * d, 0.8, 1.4):
			placed += 1
	for k in n / 2:  # undergrowth through it (round 4: n / 5 left most copses see-through at eye height)
		var a := rng.randf() * TAU
		var d := r * 0.85 * sqrt(rng.randf())
		_try_bush(rng, cx + cos(a) * d, cz + sin(a) * d, Kind.THICKET, 1.8, 2.8)
	if placed > 0:
		_edge_scrub(rng, cx, cz, r, false)
	if record:  # a wood's outlier clumps are the wood's, not copses of their own
		copse_sites.append({"centre": Vector2(cx, cz), "r": r, "trees": placed, "grove": grove})


## A big rock (1.4 to 2.2 m, solid) at (x, z) for low cover in a copse, unless it's off the zone,
## blocked, wet, steep, or on a trunk (within TREE_GAP_M of a tree); whether it did.
func _copse_rock(rng: RandomNumberGenerator, x: float, z: float) -> bool:
	var s := lerpf(1.4, 2.2, rng.randf())
	var squash := rng.randf()
	var yaw := rng.randf() * TAU
	var tint := rng.randf()
	if counts[Kind.ROCK] >= CAP_ROCKS or solid_count >= _cap_solid or absf(x) > _half - EDGE_KEEP_M or absf(z) > _half - EDGE_KEEP_M:
		return false
	if _crowded(x, z) or _blocked(x, z, _keep, _roads):
		return false
	var h := _terrain.height_at(x, z)
	if _terrain.sea_side >= 0 and h < _terrain.sea_level + 0.35:
		return false
	if _terrain.normal_at(x, z).y < 0.55:
		return false
	var size := Vector3(s, s * lerpf(0.55, 0.85, squash), s * lerpf(0.8, 1.2, squash))
	_add({"kind": Kind.ROCK, "yaw": yaw, "solid": true, "size": size, "pos": Vector3(x, h + size.y * 0.3, z),
		"colour": _rock_colours[int(tint * _rock_colours.size()) % _rock_colours.size()]})
	return true


## Bushes round a wood's (ragged) or a copse's (round) edge: "edge_scrub_per_m" a metre, the
## larger scrub, from just inside to a few metres out.
func _edge_scrub(rng: RandomNumberGenerator, cx: float, cz: float, r: float, ragged: bool) -> void:
	var n := int(float(_spec.get("edge_scrub_per_m", 0.5)) * TAU * r)
	for k in n:
		var a := rng.randf() * TAU
		var edge := _edge_r(cx, cz, r, a) if ragged else r
		var d := edge + rng.randf_range(-2.5, 4.5)
		_try_bush(rng, cx + cos(a) * d, cz + sin(a) * d, Kind.SCRUB, _scrub_hi * 0.85, _scrub_hi * 1.35)


## Hedgerows: lines of trees and bushes along the edges of a field grid (fields "field_m"
## across, the grid turned by the seed), each a field side or a few long.
func _hedgerows(rng: RandomNumberGenerator, count: int) -> void:
	if count <= 0:
		return
	var field := float(_spec.get("field_m", 120.0))
	var u := Vector2.from_angle(rng.randf() * PI * 0.5)
	var v := Vector2(-u.y, u.x)
	var k := ceili(_half / field)
	for n in count:
		var start := u * rng.randi_range(-k, k) * field + v * rng.randi_range(-k, k) * field
		var along_u := rng.randf() < 0.5
		var dir := u if along_u else v
		var side := v if along_u else u
		var length := field * rng.randi_range(1, 3)
		var t := 0.0
		while t < length:
			var p := start + dir * t + side * rng.randf_range(-0.8, 0.8)
			var roll := rng.randf()
			if roll < 0.6:
				_try_tree(rng, p.x, p.y, 0.8, 1.35)
			elif roll < 0.92:
				_try_bush(rng, p.x, p.y, Kind.SCRUB, _scrub_hi * 0.8, _scrub_hi * 1.3)
			var q := p + dir * 3.0
			if rng.randf() < 0.6:
				_try_bush(rng, q.x, q.y, Kind.SCRUB, _scrub_lo, _scrub_hi * 1.2)
			t += 6.5 * rng.randf_range(0.75, 1.25)


## Trees along the roads, in runs on either side ("road_trees" of their length), just outside
## ROAD_KEEP_M.
func _road_lines(rng: RandomNumberGenerator, share: float) -> void:
	if share <= 0.0:
		return
	for road: Array in _roads:
		var a := Vector2(float(road[0][0]), float(road[0][1]))
		var b := Vector2(float(road[1][0]), float(road[1][1]))
		var length := a.distance_to(b)
		if length < 1.0:
			continue
		var dir := (b - a) / length
		var normal := Vector2(-dir.y, dir.x)
		for side: float in [-1.0, 1.0]:
			var t := 4.0
			while t < length - 4.0:
				var on := a + dir * t
				var run := clampf(_cluster.get_noise_2d(on.x * 3.0 + side * 900.0, on.y * 3.0) * 0.9 + 0.5, 0.0, 1.0)
				var off := ROAD_KEEP_M + rng.randf_range(2.0, 4.0)
				var p := on + normal * side * off
				if run < share:
					_try_tree(rng, p.x, p.y, 0.85, 1.35)
				t += 9.0 * rng.randf_range(0.8, 1.2)


## Places a tree at (x, z), `lo`..`hi` in size, unless it's off the zone, blocked, wet, steep or
## too close to another tree; whether it did.
func _try_tree(rng: RandomNumberGenerator, x: float, z: float, lo: float, hi: float) -> bool:
	var s := lerpf(lo, hi, rng.randf())
	var yaw := rng.randf() * TAU
	var tint := rng.randf()
	if counts[Kind.TREE] >= _tree_limit or absf(x) > _half - EDGE_KEEP_M or absf(z) > _half - EDGE_KEEP_M:
		return false
	if _crowded(x, z) or _blocked(x, z, _keep, _roads):
		return false
	var h := _terrain.height_at(x, z)
	if _terrain.sea_side >= 0 and h < _terrain.sea_level + 0.35:
		return false
	if _terrain.normal_at(x, z).y < TREE_UP:
		return false
	_add({"kind": Kind.TREE, "pos": Vector3(x, h, z), "yaw": yaw, "size": Vector3(s, s, s),
		"colour": _crowns[int(tint * _crowns.size()) % _crowns.size()], "solid": true})  # every trunk blocks (Captain, 2026-10-18: tree hitboxes; past the solid cap some didn't)
	var g := Vector2i(floori(x / TREE_GAP_M), floori(z / TREE_GAP_M))
	if not _tree_grid.has(g):
		_tree_grid[g] = []
	(_tree_grid[g] as Array).append(Vector2(x, z))
	return true


## Whether a tree at (x, z) would stand within TREE_GAP_M of one already placed.
func _crowded(x: float, z: float) -> bool:
	var g := Vector2i(floori(x / TREE_GAP_M), floori(z / TREE_GAP_M))
	var p := Vector2(x, z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for q: Vector2 in _tree_grid.get(g + Vector2i(dx, dz), []):
				if q.distance_to(p) < TREE_GAP_M:
					return true
	return false


## Places scrub or a thicket (`kind`) `lo`..`hi` wide at (x, z) unless it's off the zone,
## blocked, wet or steep; whether it did. Thickets stand tall (size.y 3.0 to 4.2, so SCRUB_TOP
## of it is 1.8 to 2.5 m): undergrowth that hides a standing man in a wood (round 4 measured
## 40 m eye-height lines through woods: with 2.6 to 3.6 and a third as many, a third saw through).
func _try_bush(rng: RandomNumberGenerator, x: float, z: float, kind: int, lo: float, hi: float) -> bool:
	var s := lerpf(lo, hi, rng.randf())
	var squash := rng.randf()
	var yaw := rng.randf() * TAU
	var tint := rng.randf()
	var cap := _cap_thickets if kind == Kind.THICKET else CAP_SCRUB
	if counts[kind] >= cap or absf(x) > _half - EDGE_KEEP_M or absf(z) > _half - EDGE_KEEP_M:
		return false
	if _blocked(x, z, _keep, _roads):
		return false
	var h := _terrain.height_at(x, z)
	if _terrain.sea_side >= 0 and h < _terrain.sea_level + 0.35:
		return false
	if _terrain.normal_at(x, z).y < 0.8:
		return false
	var tall := lerpf(3.0, 4.2, squash) if kind == Kind.THICKET else s * lerpf(0.5, 0.9, squash)
	var colour: Color = _scrubs[int(tint * _scrubs.size()) % _scrubs.size()]
	if kind == Kind.THICKET:
		colour = colour.lerp(_crowns[0], 0.5).darkened(0.08)  # between the bushes and the crowns
	_add({"kind": kind, "pos": Vector3(x, h, z), "yaw": yaw, "size": Vector3(s, tall, s), "colour": colour, "solid": false})
	return true


func _add(item: Dictionary) -> void:
	if int(item.kind) == Kind.TREE:
		item["conifer"] = _is_conifer(item)  # (from where it stands: the same from a cache too)
	if item.solid:
		solid_count += 1
	counts[int(item.kind)] += 1
	var p: Vector3 = item.pos
	var cell := _cell_of(p.x, p.z)
	if not _cells.has(cell):
		_cells[cell] = []
	(_cells[cell] as Array).append(items.size())
	items.append(item)


# --- Cache -------------------------------------------------------------------------------------

## The cache key: everything the layout comes from (the layout code's version, the ground's
## heights, the preset's scatter, the pads and roads).
func _cache_key() -> String:
	var t := _terrain
	var parts := [LAYOUT_VERSION, t.seed_value, t.size_m, t.preset_id, t.checksum(), t.sea_side, t.sea_level, JSON.stringify(_spec, "", true), str(_keep), str(_roads)]
	return str(parts).sha256_text()


func _from_memory() -> bool:
	if not _cache.has(_key):
		return false
	_entry = _cache[_key]
	items = _entry.items
	_cells = _entry.cells
	counts = (_entry.counts as Dictionary).duplicate()
	solid_count = int(_entry.solid)
	cache_source = "memory"
	_touch()
	return true


func _remember() -> void:
	_entry = {"items": items, "cells": _cells, "counts": counts.duplicate(), "solid": solid_count, "visual": {}, "far": {}}
	_cache[_key] = _entry
	_touch()


## Marks this zone the newest; drops the oldest layouts past CACHE_ZONES and the built meshes
## of those past CACHE_VISUAL_ZONES.
func _touch() -> void:
	_cache_order.erase(_key)
	_cache_order.append(_key)
	while _cache_order.size() > CACHE_ZONES:
		_cache.erase(_cache_order.pop_front())
	for k in maxi(_cache_order.size() - CACHE_VISUAL_ZONES, 0):
		var old: Dictionary = _cache[_cache_order[k]]
		old.visual = {}
		old.far = {}


## Forgets every cached layout in memory (and on disk when `disk`), for tests.
static func clear_cache(disk := false) -> void:
	_cache.clear()
	_cache_order.clear()
	if disk and DirAccess.dir_exists_absolute(CACHE_DIR):
		for file in DirAccess.get_files_at(CACHE_DIR):
			if file.begins_with("scatter_"):
				DirAccess.remove_absolute(CACHE_DIR.path_join(file))


func _disk_path() -> String:
	return CACHE_DIR.path_join("scatter_%s.bin" % _key.substr(0, 24))


## Items on disk: 12 numbers each (kind, position, yaw, size, colour, solid), compressed.
func _to_disk() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var flat := PackedFloat64Array()
	flat.resize(items.size() * 12)
	var k := 0
	for item in items:
		var p: Vector3 = item.pos
		var s: Vector3 = item.size
		var c: Color = item.colour
		for v: float in [float(item.kind), p.x, p.y, p.z, float(item.yaw), s.x, s.y, s.z, c.r, c.g, c.b, 1.0 if item.solid else 0.0]:
			flat[k] = v
			k += 1
	var file := FileAccess.open_compressed(_disk_path(), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return
	file.store_var({"version": LAYOUT_VERSION, "key": _key, "items": flat})
	file.close()
	_prune_disk()


func _from_disk() -> bool:
	var path := _disk_path()
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return false
	var data: Variant = file.get_var()
	file.close()
	if not data is Dictionary or int(data.get("version", 0)) != LAYOUT_VERSION or String(data.get("key", "")) != _key:
		return false
	var flat: PackedFloat64Array = data.get("items", PackedFloat64Array())
	if float(_spec.get("tufts_per_km2", 0.0)) > 0.0:
		var cells := ceili(_terrain.size_m / CELL_M)
		for cz in cells:
			for cx in cells:
				_cells[Vector2i(cx, cz)] = []
	for k in range(0, flat.size(), 12):
		_add({"kind": int(flat[k]), "pos": Vector3(flat[k + 1], flat[k + 2], flat[k + 3]), "yaw": flat[k + 4],
			"size": Vector3(flat[k + 5], flat[k + 6], flat[k + 7]), "colour": Color(flat[k + 8], flat[k + 9], flat[k + 10]), "solid": flat[k + 11] > 0.5})
	cache_source = "disk"
	_remember()
	return true


## Keeps the newest CACHE_FILES layouts on disk (it's only a cache: an old zone regenerates).
static func _prune_disk() -> void:
	var files: Array = []
	for file in DirAccess.get_files_at(CACHE_DIR):
		if file.begins_with("scatter_"):
			var path := CACHE_DIR.path_join(file)
			files.append([FileAccess.get_modified_time(path), path])
	if files.size() <= CACHE_FILES:
		return
	files.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for k in files.size() - CACHE_FILES:
		DirAccess.remove_absolute(files[k][1])


func _colours(hexes: Array) -> Array[Color]:
	var out: Array[Color] = []
	for hex in hexes:
		out.append(Color(String(hex)))
	return out


func _blocked(x: float, z: float, keep: Array[Rect2], roads: Array) -> bool:
	if _terrain and _terrain.water and _terrain.water.keeps_clear(x, z):
		return true  # a river, lake or bridge (ZoneWater)
	var p := Vector2(x, z)
	for r in keep:
		if r.has_point(p):
			return true
	for road: Array in (_roads_near(p, ROAD_KEEP_M) if is_same(roads, _roads) else roads):
		var a := Vector2(float(road[0][0]), float(road[0][1]))
		var b := Vector2(float(road[1][0]), float(road[1][1]))
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < ROAD_KEEP_M:
			return true
	return false


## Indexes _roads by ROAD_CELL_M cell: each piece under every cell its bounds touch.
func _index_roads() -> void:
	_road_cells = {}
	for road: Array in _roads:
		var box := Rect2(Vector2(float(road[0][0]), float(road[0][1])), Vector2.ZERO).expand(Vector2(float(road[1][0]), float(road[1][1])))
		for cy in range(floori(box.position.y / ROAD_CELL_M), floori(box.end.y / ROAD_CELL_M) + 1):
			for cx in range(floori(box.position.x / ROAD_CELL_M), floori(box.end.x / ROAD_CELL_M) + 1):
				var key := Vector2i(cx, cy)
				if not _road_cells.has(key):
					_road_cells[key] = []
				_road_cells[key].append(road)


## The road pieces that could come within `reach` of `p` (every one that does; some twice).
func _roads_near(p: Vector2, reach: float) -> Array:
	var out: Array = []
	for cy in range(floori((p.y - reach) / ROAD_CELL_M), floori((p.y + reach) / ROAD_CELL_M) + 1):
		for cx in range(floori((p.x - reach) / ROAD_CELL_M), floori((p.x + reach) / ROAD_CELL_M) + 1):
			out.append_array(_road_cells.get(Vector2i(cx, cy), []))
	return out


## True within `near_m` of a road or a pad (props: man-made clutter belongs near where people
## are, not scattered through open wilderness like rocks).
func _near_road_or_pad(x: float, z: float, near_m: float) -> bool:
	var p := Vector2(x, z)
	for r in _keep:
		var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
		var dz := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
		if Vector2(dx, dz).length() <= near_m:
			return true
	for road: Array in _roads_near(p, near_m):
		var a := Vector2(float(road[0][0]), float(road[0][1]))
		var b := Vector2(float(road[1][0]), float(road[1][1]))
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= near_m:
			return true
	return false


func _cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x + _terrain.size_m * 0.5) / CELL_M), floori((z + _terrain.size_m * 0.5) / CELL_M))


## A hash of the layout: two peers that generated the same zone have the same.
func checksum() -> int:
	var flat := PackedFloat32Array()
	for item in items:
		var p: Vector3 = item.pos
		flat.append_array([float(item.kind), p.x, p.y, p.z, item.yaw, (item.size as Vector3).x])
	return hash(flat)


func total() -> int:
	return items.size()


## The VALUABLE sites this zone's scatter marked (pos, yaw; no mesh): where WorldValuables spawns
## the real lootable pickups, deterministic like the rest of the scatter (every peer, and this
## zone's cache, agree on where).
func valuable_sites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Dictionary in items:
		if int(item.kind) == Kind.VALUABLE:
			out.append(item)
	return out


## The footprints (world AABBs) of the solid items overlapping `area` (x, z in metres), for
## the navigation mesh.
func boxes_in(area: Rect2) -> Array[AABB]:
	var out: Array[AABB] = []
	if _cells.is_empty():
		return out
	var lo := _cell_of(area.position.x, area.position.y)
	var hi := _cell_of(area.end.x, area.end.y)
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			for index: int in _cells.get(Vector2i(cx, cz), []):
				var item: Dictionary = items[index]
				if not item.solid or not area.has_point(Vector2(item.pos.x, item.pos.z)):
					continue
				var half := _solid_half(item)
				var p: Vector3 = item.pos
				var centre := p + Vector3(0, half.y, 0) if item.kind == Kind.TREE else p
				out.append(AABB(centre - half, half * 2.0))
	return out


## The least foliage_between `from` and either of `to_a` and `to_b` (a head and a chest), with
## the foliage walked once for both lines (Spotting.foliage_m: two walks per pair in sight were
## a large share of an AI scan, research 2026-10-13 B2.6).
func foliage_least(from: Vector3, to_a: Vector3, to_b: Vector3) -> float:
	if _cells.is_empty():
		return 0.0
	var lo := _cell_of(minf(from.x, minf(to_a.x, to_b.x)) - FOLIAGE_PAD_M, minf(from.z, minf(to_a.z, to_b.z)) - FOLIAGE_PAD_M)
	var hi := _cell_of(maxf(from.x, maxf(to_a.x, to_b.x)) + FOLIAGE_PAD_M, maxf(from.z, maxf(to_a.z, to_b.z)) + FOLIAGE_PAD_M)
	var a := 0.0
	var b := 0.0
	var eye := Vector2(from.x, from.z)
	var end_a := Vector2(to_a.x, to_a.z)
	var end_b := Vector2(to_b.x, to_b.z)
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			if _cell_off_line(cx, cz, eye, end_a) and _cell_off_line(cx, cz, eye, end_b):
				continue
			for index: int in _cells.get(Vector2i(cx, cz), []):
				var item: Dictionary = items[index]
				var kind := int(item.kind)
				if kind == Kind.ROCK or kind == Kind.VALUABLE:
					continue
				var p: Vector3 = item.pos
				if Vector2(p.x - from.x, p.z - from.z).length() > _see_m(kind):
					continue  # as in foliage_between
				a += _through(item, kind, from, to_a)
				b += _through(item, kind, from, to_b)
	return minf(a, b)


## Metres of `item` (foliage of `kind`) the line `from` -> `to` passes through (foliage_between's
## test, for foliage_least).
static func _through(item: Dictionary, kind: int, from: Vector3, to: Vector3) -> float:
	var flat := Vector2(to.x - from.x, to.z - from.z)
	var flat_len := flat.length()
	if flat_len < 0.01:
		return 0.0
	var p: Vector3 = item.pos
	var size: Vector3 = item.size
	var bush := kind != Kind.TREE
	var conifer := not bush and bool(item.get("conifer", false))
	var r := size.x * (SCRUB_R if bush else (CONIFER_R if conifer else CROWN_R))
	var c := Vector2(p.x - from.x, p.z - from.z)
	var along := c.dot(flat) / (flat_len * flat_len)
	var miss := (c - flat * along).length()
	if miss >= r:
		return 0.0
	var y0 := p.y + (0.0 if bush else size.y * CROWN_LOW)
	var y1 := p.y + size.y * (SCRUB_TOP if bush else (CONIFER_HIGH if conifer else CROWN_HIGH))
	var half_t := sqrt(r * r - miss * miss) / flat_len
	var t0 := maxf(along - half_t, 0.0)
	var t1 := minf(along + half_t, 1.0)
	var dy := to.y - from.y
	if absf(dy) < 0.0001:
		if from.y < y0 or from.y > y1:
			return 0.0
	else:
		var ta := (y0 - from.y) / dy
		var tb := (y1 - from.y) / dy
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	return (t1 - t0) * from.distance_to(to) if t1 > t0 else 0.0


## Metres of foliage (scrub, thickets, and tree crowns) the straight line `from` -> `to` passes
## through, for spotting (Spotting.foliage_m). Each is a vertical cylinder about its mesh: scrub
## and thickets SCRUB_R x their width, up to SCRUB_TOP x their height; a crown CROWN_R x its
## size, from CROWN_LOW to CROWN_HIGH x its size up (a conifer's CONIFER_R, to CONIFER_HIGH). Trunks and rocks are solid: rays see to
## those. A wood's thickets and low crowns add up: a few trees deep hides a standing man.
func foliage_between(from: Vector3, to: Vector3) -> float:
	if _cells.is_empty():
		return 0.0
	var flat := Vector2(to.x - from.x, to.z - from.z)
	var flat_len := flat.length()
	if flat_len < 0.01:
		return 0.0
	var lo := _cell_of(minf(from.x, to.x) - FOLIAGE_PAD_M, minf(from.z, to.z) - FOLIAGE_PAD_M)
	var hi := _cell_of(maxf(from.x, to.x) + FOLIAGE_PAD_M, maxf(from.z, to.z) + FOLIAGE_PAD_M)
	var length := from.distance_to(to)
	var dy := to.y - from.y
	var total := 0.0
	var eye := Vector2(from.x, from.z)
	var end := Vector2(to.x, to.z)
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			if _cell_off_line(cx, cz, eye, end):
				continue
			for index: int in _cells.get(Vector2i(cx, cz), []):
				var item: Dictionary = items[index]
				var kind := int(item.kind)
				if kind == Kind.ROCK or kind == Kind.VALUABLE:
					continue
				var p: Vector3 = item.pos
				if Vector2(p.x - from.x, p.z - from.z).length() > _see_m(kind):
					continue  # past where it's drawn it hides nobody (what players see is what counts)
				var size: Vector3 = item.size
				var bush := kind != Kind.TREE
				var conifer := not bush and bool(item.get("conifer", false))
				var r := size.x * (SCRUB_R if bush else (CONIFER_R if conifer else CROWN_R))
				var y0 := p.y + (0.0 if bush else size.y * CROWN_LOW)
				var y1 := p.y + size.y * (SCRUB_TOP if bush else (CONIFER_HIGH if conifer else CROWN_HIGH))
				# The flat line against the circle: t runs 0..1 along it.
				var c := Vector2(p.x - from.x, p.z - from.z)
				var along := c.dot(flat) / (flat_len * flat_len)
				var miss := (c - flat * along).length()
				if miss >= r:
					continue
				var half_t := sqrt(r * r - miss * miss) / flat_len
				var t0 := maxf(along - half_t, 0.0)
				var t1 := minf(along + half_t, 1.0)
				# ...then its height (the line's y is linear in t).
				if absf(dy) < 0.0001:
					if from.y < y0 or from.y > y1:
						continue
				else:
					var ta := (y0 - from.y) / dy
					var tb := (y1 - from.y) / dy
					t0 = maxf(t0, minf(ta, tb))
					t1 = minf(t1, maxf(ta, tb))
				if t1 > t0:
					total += (t1 - t0) * length
	return total


## How far foliage of `kind` hides anyone: scrub out to SEE_SCRUB_M (where it's drawn);
## crowns and thickets any distance (past SEE_TREE_M the far canopy blobs stand for them).
static func _see_m(kind: int) -> float:
	return SEE_SCRUB_M if kind == Kind.SCRUB else INF


## Whether no foliage in cell (cx, cz) can reach the flat line `a` -> `b`: the cell's centre is
## further from it than half the cell's diagonal and FOLIAGE_PAD_M (round 4: the woods put far
## more items in a cell, and a long sight line's box held many cells it never crosses).
func _cell_off_line(cx: int, cz: int, a: Vector2, b: Vector2) -> bool:
	var half := _terrain.size_m * 0.5
	var centre := Vector2(-half + (cx + 0.5) * CELL_M, -half + (cz + 0.5) * CELL_M)
	return Geometry2D.get_closest_point_to_segment(centre, a, b).distance_to(centre) > CELL_M * 0.7072 + FOLIAGE_PAD_M


func _solid_half(item: Dictionary) -> Vector3:
	var s: Vector3 = item.size
	if item.kind == Kind.TREE:
		return Vector3(TRUNK_HALF * s.x, TRUNK_TALL * 0.5 * s.y, TRUNK_HALF * s.x)
	return Vector3(maxf(s.x, s.z) * 0.5, s.y * 0.5, maxf(s.x, s.z) * 0.5)


# --- Collision -------------------------------------------------------------------------------

## A tree's collision is its drawn trunk (_trunk_mesh: 2.6 tall, 0.38 wide at the foot and 0.28 at
## the top, x the tree's size). It was 0.3 round and 3.0 high, half again as wide as the trunk
## drawn (Captain, 2026-10-18: "the hitboxes of trees": stopped by, and shots stopping on, the air
## beside a trunk); then a cylinder TRUNK_HALF round, a little narrower than the trunk's foot and
## its octagon's corners (rounds through the corners went through). World visual pass (cghath,
## 2026-10-20): now the trunk's own octagonal frustum, turned and sunk as it's drawn (_trunk_points).
## TRUNK_HALF stays the trunk's footprint for the navmesh (boxes_in).
const TRUNK_HALF := 0.17
const TRUNK_TALL := 2.6
const TRUNK_FOOT_R := 0.19
const TRUNK_TOP_R := 0.14
const TRUNK_SINK := 0.1
## Trunk shapes by size, shared (sizes snapped to TRUNK_SHAPE_STEP: a few millimetres at most).
const TRUNK_SHAPE_STEP := 0.02
static var _trunk_shapes := {}


## One static body per cell holding every solid item's shape in it (large rocks, trunks and props),
## each the shape it's drawn as (world visual pass, 2026-10-20: rocks and props were a box 0.9 of
## their size, the rocks' drawn corners pulled in and out of it, and both drawn sheared when turned):
## a trunk its octagonal frustum, a rock the hull of its rock mesh, a prop each of its parts.
func build_collision() -> void:
	for cell: Vector2i in _cells:
		var body: StaticBody3D = null
		for index: int in _cells[cell]:
			var item: Dictionary = items[index]
			if not item.solid:
				continue
			if body == null:
				body = StaticBody3D.new()
				body.name = "Cover_%d_%d" % [cell.x, cell.y]
				body.collision_layer = 1
				body.collision_mask = 0
				add_child(body)
			for part: Array in collision_parts(item):
				var shape := CollisionShape3D.new()
				shape.shape = part[0]
				shape.transform = part[1]
				body.add_child(shape)


## The shapes item `item` collides as, each [Shape3D, Transform3D (world)], exactly as it's drawn
## (_cell_parts): [] for one that doesn't collide (scrub, thickets, small rocks, valuables).
func collision_parts(item: Dictionary) -> Array:
	var s: Vector3 = item.size
	var p: Vector3 = item.pos
	match int(item.kind):
		Kind.TREE:
			var key := snappedf(s.x, TRUNK_SHAPE_STEP)
			if not _trunk_shapes.has(key):
				var trunk := ConvexPolygonShape3D.new()
				trunk.points = _trunk_points(key)
				_trunk_shapes[key] = trunk
			return [[_trunk_shapes[key], Transform3D(Basis(Vector3.UP, float(item.yaw)), p - Vector3(0, TRUNK_SINK, 0))]]
		Kind.ROCK:
			if not item.solid:
				return []
			var rock := ConvexPolygonShape3D.new()
			var points := PackedVector3Array()
			for c: Vector3 in _blocky_corners(Vector3.ONE, ROCK_JITTER, ROCK_SEED, true):
				points.append(c * s)
			rock.points = points
			return [[rock, Transform3D(Basis(Vector3.UP, float(item.yaw)), p - Vector3(0, _sink(item, ROCK_BURIED), 0))]]
		Kind.PROP:
			var out: Array = []
			var xf := _prop_transform(item)
			var size: Vector3 = xf[1]
			var place := Transform3D(Basis(Vector3.UP, float(xf[0])), p - Vector3(0, _sink(item, 0.0), 0))
			for part: Array in PROP_SHAPES[_prop_kind(item)]:
				if part.size() > 4 and not part[4]:
					continue  # a painted detail on another part's face
				var hull := ConvexPolygonShape3D.new()
				var points := PackedVector3Array()
				for c: Vector3 in _part_points(part):
					points.append(c * size)
				hull.points = points
				out.append([hull, place])
			return out
	return []


## The trunk's octagonal frustum (as _trunk_mesh draws it) for a tree of size `s`: its 16 corners,
## from its foot (at 0) to TRUNK_TALL x `s` up.
static func _trunk_points(s: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for ring: Vector2 in [Vector2(0.0, TRUNK_FOOT_R), Vector2(TRUNK_TALL, TRUNK_TOP_R)]:
		for v: Vector2 in _octagon(ring.y * s):
			out.append(Vector3(v.x, ring.x * s, v.y))
	return out


## An octagon's corners (a square of half-width `r` with its corners cut at 45 degrees, as _tier).
static func _octagon(r: float) -> Array[Vector2]:
	var c := r * 0.7
	return [Vector2(c, -r), Vector2(r, -c), Vector2(r, c), Vector2(c, r), Vector2(-c, r), Vector2(-r, c), Vector2(-r, -c), Vector2(-c, -r)]


# --- Visuals ---------------------------------------------------------------------------------

## Starts building the visuals as the camera nears (nothing on a headless server), and lays
## out the far stand-ins for the whole zone at once (they're few: one blob per FAR_GROUP_M
## square of trees, one MultiMesh per cell).
func build_visuals() -> void:
	if _visuals_on or _cells.is_empty():
		return
	_visuals_on = true
	var colours: Dictionary = _spec.get("colours", {})
	_meshes = _shared_meshes(String(colours.get("trunk", "4f3e2c")))
	_material = _shared_material_once()
	_build_far()
	set_process(true)
	if int(_spec.get("tufts_per_km2", 0)) > 0:  # grass near the camera (GrassCarpet), where this ground has tufts at all
		var carpet := GrassCarpet.new()
		carpet.setup(self, _terrain, _meshes["tuft"], _material, _colours(colours.get("tuft", colours.get("scrub", ["6f7040"]))))
		add_child(carpet)


## The material every scatter MultiMesh draws with, made once a game (Captain, 2026-10-14:
## caching for performance).
static func _shared_material_once() -> StandardMaterial3D:
	if _shared_material == null:
		_shared_material = StandardMaterial3D.new()
		_shared_material.vertex_color_use_as_albedo = true
		_shared_material.vertex_color_is_srgb = true
		_shared_material.roughness = 1.0
	return _shared_material


## The shapes by group key, built once a game and shared by every zone (only the trunk's
## colour differs by preset, so trunks are kept by colour).
func _shared_meshes(trunk_hex: String) -> Dictionary:
	if _shapes.is_empty():
		_shapes = {
			Kind.ROCK: _blocky(Vector3(1, 1, 1), Color.WHITE, ROCK_JITTER, ROCK_SEED, true),
			Kind.SCRUB: _scrub_mesh(),
			"crown": _crown_mesh(),
			"conifer": _conifer_mesh(),
			"tuft": _tuft_mesh(),
			"pebble": _blocky(Vector3(1, 1, 1), Color.WHITE, 0.3, 7, true),
			"outcrop": _blocky(Vector3(1, 1, 1), Color.WHITE, 0.26, 3, true),
			"far": _far_mesh(),
		}
		_shapes["thicket"] = _shapes[Kind.SCRUB]
		for kind: String in PROP_SHAPES:
			_shapes["prop_" + kind] = _prop_mesh(kind)
	var trunk_key := "trunk:" + trunk_hex
	if not _shapes.has(trunk_key):
		_shapes[trunk_key] = _trunk_mesh(Color(trunk_hex))
	var out := _shapes.duplicate()
	out["trunk"] = _shapes[trunk_key]
	return out


## Builds up to `budget` cells' visuals near `pos`, nearest first; returns how many it built.
func build_near(pos: Vector3, budget: int) -> int:
	if not _visuals_on:
		return 0
	var wanted: Array = []
	var half := _terrain.size_m * 0.5
	for cell: Vector2i in _cells:
		if _built.has(cell):
			continue
		var centre := Vector2(-half + (cell.x + 0.5) * CELL_M, -half + (cell.y + 0.5) * CELL_M)
		var d := centre.distance_to(Vector2(pos.x, pos.z))
		if d < BUILD_M:
			wanted.append([d, cell])
	wanted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var done := 0
	for w: Array in wanted.slice(0, budget):
		_build_cell(w[1])
		done += 1
	return done


func built_cells() -> int:
	return _built.size()


func _process(delta: float) -> void:
	_next_check -= delta
	if _next_check > 0.0:
		return
	_next_check = CHECK_S
	var camera := get_viewport().get_camera_3d()
	if camera:
		build_near(camera.global_position, PER_FRAME)


func _build_cell(cell: Vector2i) -> void:
	_built[cell] = true
	var kept: Dictionary = _entry.get("visual", {})
	var parts: Array = kept.get(cell, [])
	if not kept.has(cell):
		parts = _cell_parts(cell)
		if _entry.has("visual"):
			kept[cell] = parts  # built once, kept while this zone is among the newest (CACHE_VISUAL_ZONES)
	for part: Array in parts:
		var key: Variant = part[0]
		var node := MultiMeshInstance3D.new()
		node.name = "Scatter_%d_%d_%s" % [cell.x, cell.y, str(key)]
		node.multimesh = part[1]
		node.material_override = _material
		node.visibility_range_end = float(_RANGES[key])
		node.visibility_range_end_margin = 20.0
		var shade: bool = not ((key is int and key == Kind.SCRUB) or (key is String and key in ["tuft", "pebble", "thicket"]))  # keys mix Kind values and names
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shade else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)


## Draw distance by group key.
const _RANGES := {Kind.ROCK: SEE_ROCK_M, Kind.SCRUB: SEE_SCRUB_M, "thicket": SEE_TREE_M, "trunk": SEE_TREE_M, "crown": SEE_TREE_M,
	"conifer": SEE_TREE_M, "tuft": SEE_TUFT_M, "pebble": SEE_PEBBLE_M, "outcrop": SEE_OUTCROP_M,
	"prop_crates": SEE_ROCK_M, "prop_drums": SEE_ROCK_M, "prop_debris": SEE_ROCK_M, "prop_wall": SEE_ROCK_M, "prop_wreck": SEE_ROCK_M, "prop_mound": SEE_ROCK_M}


## Cell `cell`'s MultiMeshes: [[group key, MultiMesh], ...].
func _cell_parts(cell: Vector2i) -> Array:
	var groups := {Kind.ROCK: [], Kind.SCRUB: [], "thicket": [], "trunk": [], "crown": [], "conifer": []}
	for kind: String in PROP_SHAPES:
		groups["prop_" + kind] = []
	for index: int in _cells[cell]:
		for part: Array in visual_parts(items[index]):
			groups[part[0]].append([part[1], part[2]])
	_ground_cover(cell, groups)
	var parts: Array = []
	for key in groups:
		var list: Array = groups[key]
		if list.is_empty():
			continue
		parts.append([key, _multimesh(_meshes[key], list)])
	return parts


## How item `item` is drawn: [group key (its mesh in _shared_meshes), Transform3D (world), colour]
## for each of its meshes. Rocks and props are scaled along their own axes, then turned (they were
## scaled after turning, which sheared a turned one off its collision box), and a prop sinks into
## a slope (_sink), a rock too, all as they collide (collision_parts).
func visual_parts(item: Dictionary) -> Array:
	var basis := Basis(Vector3.UP, float(item.yaw))
	var size: Vector3 = item.size
	var p: Vector3 = item.pos
	var xf := Transform3D(basis.scaled(size), p)  # (x and z the same for these: turned, not sheared)
	match int(item.kind):
		Kind.ROCK:
			return [[Kind.ROCK, Transform3D(basis * Basis.from_scale(size), p - Vector3(0, _sink(item, ROCK_BURIED), 0)), item.colour]]
		Kind.SCRUB:
			return [[Kind.SCRUB, xf, item.colour]]
		Kind.PROP:
			var px := _prop_transform(item)
			var kind := _prop_kind(item)
			var colour: Color = item.colour
			if kind in ["wall", "mound"]:
				colour = colour.lightened(RUIN_LIGHTEN)  # weathered masonry, not a dark slab
			elif PROP_PAINT.has(kind):
				var paint: Array = PROP_PAINT[kind]
				colour = paint[absi(hash(Vector2i(roundi(p.z * 10.0), roundi(p.x * 10.0)))) % paint.size()]
			return [["prop_" + kind, Transform3D(Basis(Vector3.UP, float(px[0])) * Basis.from_scale(px[1]), p - Vector3(0, _sink(item, 0.0), 0)), colour]]
		Kind.THICKET:
			# The scrub mesh (0.58 high), its height scaled so the thicket stands size.y * SCRUB_TOP
			# tall, as foliage_between counts it.
			return [["thicket", Transform3D(basis.scaled(Vector3(size.x, size.y * SCRUB_TOP / 0.58, size.z)), p), item.colour]]
		Kind.TREE:
			return [["trunk", Transform3D(basis.scaled(size), p - Vector3(0, TRUNK_SINK, 0)), Color.WHITE],
				["conifer" if (bool(item.conifer) if item.has("conifer") else _is_conifer(item)) else "crown", xf, item.colour]]
	return []


## How far a prop or rock `item` sits down into the ground it stands on (m): on a slope its low
## side would stand in the air, so it sinks till that side is in, less the share of its height
## already `buried` (a rock's), and at most PROP_SINK_MAX of its height.
func _sink(item: Dictionary, buried: float) -> float:
	var p: Vector3 = item.pos
	var size: Vector3 = item.size
	var up := clampf(_terrain.normal_at(p.x, p.z).y, 0.3, 1.0) if _terrain else 1.0
	var tan_slope := sqrt(1.0 - up * up) / up
	return clampf(0.5 * maxf(size.x, size.z) * tan_slope - buried * size.y, 0.0, size.y * PROP_SINK_MAX)


## A MultiMesh of `mesh` at `list`'s [transform, colour] pairs.
static func _multimesh(mesh: Mesh, list: Array) -> MultiMesh:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = list.size()
	for k in list.size():
		multi.set_instance_transform(k, list[k][0])
		multi.set_instance_color(k, list[k][1])
	return multi


# --- Far stand-ins -----------------------------------------------------------------------------

## Builds the far canopy blobs: per cell, one blob per FAR_GROUP_M square holding trees (at
## their middle, as wide as they spread, as tall as their crowns), one MultiMesh per cell, seen
## from just inside SEE_TREE_M out to the horizon, no shadows. Kept in the zone's cache entry.
func _build_far() -> void:
	var kept: Dictionary = _entry.get("far", {})
	if kept.is_empty():
		kept = _far_parts()
		if _entry.has("far"):
			_entry.far = kept
	_far = kept
	for cell: Vector2i in kept:
		var node := MultiMeshInstance3D.new()
		node.name = "Far_%d_%d" % [cell.x, cell.y]
		node.multimesh = kept[cell]
		node.material_override = _material
		node.visibility_range_begin = SEE_TREE_M - 10.0
		node.visibility_range_begin_margin = 20.0
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)


## cell -> MultiMesh of its far blobs.
func _far_parts() -> Dictionary:
	var out := {}
	var half := _terrain.size_m * 0.5
	for cell: Vector2i in _cells:
		var squares := {}  # Vector2i -> [position sum, count, size sum, colour sum, low corner, high corner]
		for index: int in _cells[cell]:
			var item: Dictionary = items[index]
			if int(item.kind) != Kind.TREE:
				continue
			var p: Vector3 = item.pos
			var g := Vector2i(floori((p.x + half) / FAR_GROUP_M), floori((p.z + half) / FAR_GROUP_M))
			if not squares.has(g):
				squares[g] = [Vector3.ZERO, 0, 0.0, Color(0, 0, 0, 0), Vector2(INF, INF), Vector2(-INF, -INF)]
			var sq: Array = squares[g]
			sq[0] = (sq[0] as Vector3) + p
			sq[1] = int(sq[1]) + 1
			sq[2] = float(sq[2]) + (item.size as Vector3).y
			sq[3] = (sq[3] as Color) + (item.colour as Color)
			sq[4] = (sq[4] as Vector2).min(Vector2(p.x, p.z))
			sq[5] = (sq[5] as Vector2).max(Vector2(p.x, p.z))
		if squares.is_empty():
			continue
		var list: Array = []
		for g: Vector2i in squares:
			var sq: Array = squares[g]
			var n := int(sq[1])
			var mid: Vector3 = (sq[0] as Vector3) / n
			var spread: Vector2 = (sq[5] as Vector2) - (sq[4] as Vector2)
			var r := clampf(maxf(spread.x, spread.y) * 0.5 + CROWN_R * 1.3, 2.5, FAR_GROUP_M * 0.7)
			var tall := float(sq[2]) / n
			var c: Color = (sq[3] as Color) / float(n)
			c.a = 1.0
			var basis := Basis(Vector3.UP, float(g.x * 7 + g.y * 13) * 0.37).scaled(Vector3(r, tall, r))
			list.append([Transform3D(basis, mid), c.darkened(0.06)])
		out[cell] = _multimesh(_meshes.get("far", _far_mesh()), list)
	return out


## How many far stand-ins are built: {"cells": MultiMeshes, "blobs": instances}, for tests.
func far_counts() -> Dictionary:
	var blobs := 0
	for cell: Vector2i in _far:
		blobs += (_far[cell] as MultiMesh).instance_count
	return {"cells": _far.size(), "blobs": blobs}


## A far canopy blob: a low, wide rounded mass from 1.2 to 4.9 x the crowns' size up, radius 1
## (scaled to the trees' spread).
func _far_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t: Array in [[1.2, 2.4, 0.75, 1.0], [2.4, 3.9, 1.0, 0.85], [3.9, 4.9, 0.85, 0.35]]:
		_tier(st, 0.0, 0.0, t[0], t[1], t[2], t[3])
	return st.commit()


## Grass tufts and pebbles for `cell` (visual only, see SEE_TUFT_M): from the cell and the seed,
## thicker where the scrub clusters, none on pads, roads, water or steep ground.
func _ground_cover(cell: Vector2i, groups: Dictionary) -> void:
	var tufts := mini(int(float(_spec.get("tufts_per_km2", 0.0)) * CELL_M * CELL_M / 1.0e6), CAP_TUFTS_PER_CELL)
	var pebbles := mini(int(float(_spec.get("pebbles_per_km2", 0.0)) * CELL_M * CELL_M / 1.0e6), CAP_TUFTS_PER_CELL)
	if tufts + pebbles == 0 and float(_spec.get("rock_clusters_per_km2", 0.0)) <= 0.0:
		return
	groups["tuft"] = []
	groups["pebble"] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, _terrain.seed_value))
	var half := _terrain.size_m * 0.5
	var x0 := -half + cell.x * CELL_M
	var z0 := -half + cell.y * CELL_M
	var colours: Dictionary = _spec.get("colours", {})
	var tuft_colours := _colours(colours.get("tuft", colours.get("scrub", ["6f7040"])))
	var rock_colours := _colours(colours.get("rock", ["77736a"]))
	var open := float(_spec.get("margin_m", 0.0)) > 0.0
	for n in tufts + pebbles:
		var pebble := n >= tufts
		var x := x0 + rng.randf() * CELL_M
		var z := z0 + rng.randf() * CELL_M
		var roll := rng.randf()
		var yaw := rng.randf() * TAU
		var s := rng.randf()
		var tint := rng.randf()
		if absf(x) > half - EDGE_KEEP_M or absf(z) > half - EDGE_KEEP_M:
			continue
		if not pebble and roll > clampf(_cluster.get_noise_2d(x * 3.0, z * 3.0) * 1.4 + 0.7, 0.15, 1.0):
			continue  # tufts in patches
		if open and roll > _open_weight(x, z):
			continue  # an open pan's middle stays bare
		if _ground_blocked(x, z):
			continue
		var h := _terrain.height_at(x, z)
		if _terrain.sea_side >= 0 and h < _terrain.sea_level + 0.5:
			continue
		var nrm := _terrain.normal_at(x, z)
		if nrm.y < 0.82:
			continue
		var basis := Basis(Vector3.UP, yaw)
		if pebble:
			var size := lerpf(0.08, 0.32, s * s)
			var c: Color = rock_colours[int(tint * rock_colours.size()) % rock_colours.size()]
			groups["pebble"].append([Transform3D(basis.scaled(Vector3(size, size * 0.55, size * 1.2)), Vector3(x, h + size * 0.12, z)), c.darkened(tint * 0.15)])
		else:
			var size := lerpf(0.9, 1.8, s)
			var c: Color = tuft_colours[int(tint * tuft_colours.size()) % tuft_colours.size()]
			c = c.lerp(Color(c.r * 1.08, c.g * 1.05, c.b * 0.9), roll)  # some sun-bleached
			groups["tuft"].append([Transform3D(basis.scaled(Vector3(size, size * lerpf(0.8, 1.3, tint), size)), Vector3(x, h - 0.03, z)), c])
	# Rock clusters: a few half-buried stones round a bigger one (visual only, all under a
	# metre like the scatter's small rocks, which have no collision either).
	var clusters := int(float(_spec.get("rock_clusters_per_km2", 0.0)) * CELL_M * CELL_M / 1.0e6 + rng.randf())
	groups["outcrop"] = []
	for n in clusters:
		var cx := x0 + rng.randf() * CELL_M
		var cz := z0 + rng.randf() * CELL_M
		var stones := rng.randi_range(3, 7)
		if absf(cx) > half - EDGE_KEEP_M or absf(cz) > half - EDGE_KEEP_M or _ground_blocked(cx, cz):
			continue
		if open and _open_weight(cx, cz) < 0.5:
			continue  # rubble at the margins and round the compounds, not on the open pan
		var ch := _terrain.height_at(cx, cz)
		if (_terrain.sea_side >= 0 and ch < _terrain.sea_level + 0.5) or _terrain.normal_at(cx, cz).y < 0.6:
			continue
		var base: Color = rock_colours[rng.randi() % rock_colours.size()]
		for k in stones:
			var a := rng.randf() * TAU
			var r := 0.0 if k == 0 else rng.randf_range(0.6, 2.6)
			var x := cx + cos(a) * r
			var z := cz + sin(a) * r
			var size := rng.randf_range(0.55, 0.95) if k == 0 else rng.randf_range(0.2, 0.6)
			var squash := rng.randf_range(0.5, 0.8)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3(cos(a), 0, sin(a)), rng.randf_range(-0.25, 0.25))
			var h := _terrain.height_at(x, z)
			groups["outcrop"].append([Transform3D(basis.scaled(Vector3(size, size * squash, size * rng.randf_range(0.8, 1.3))), Vector3(x, h + size * squash * 0.2, z)),
				base.darkened(rng.randf() * 0.12).lightened(rng.randf() * 0.08)])


## Whether ground cover keeps off (x, z): a pad or the line of a road.
func _ground_blocked(x: float, z: float) -> bool:
	if _terrain.water and _terrain.water.keeps_clear(x, z):
		return true  # a river, lake or bridge (ZoneWater)
	var p := Vector2(x, z)
	for r in _keep:
		if r.grow(-PAD_KEEP_M + 2.0).has_point(p):
			return true
	for road: Array in _roads_near(p, 4.0):
		var a := Vector2(float(road[0][0]), float(road[0][1]))
		var b := Vector2(float(road[1][0]), float(road[1][1]))
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < 4.0:
			return true
	return false


# --- Shapes: low-poly blocks, flat shaded ----------------------------------------------------

## The rock mesh's corner nudge and seed (one shape for every rock, scaled and turned: its
## collision is the hull of the same corners, collision_parts).
const ROCK_JITTER := 0.22
const ROCK_SEED := 1
## A rock stands with this share of its height in the ground (_lay_out: its middle 0.3 of its
## height up); on a slope it sinks further (_sink).
const ROCK_BURIED := 0.2


## A box `size` m with its corners nudged by `jitter` (a fraction of its size), seeded by
## `seed`, flat shaded, in `colour`; centred on the origin, or standing on y = 0.
func _blocky(size: Vector3, colour: Color, jitter: float, seed: int, centred: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_box(st, _blocky_corners(size, jitter, seed, centred), colour)
	return st.commit()


## _blocky's eight corners.
static func _blocky_corners(size: Vector3, jitter: float, seed: int, centred: bool) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var corners: Array[Vector3] = []
	for k in 8:
		var sx := -0.5 if (k & 1) == 0 else 0.5
		var sy := (0.0 if (k & 2) == 0 else 1.0) - (0.5 if centred else 0.0)
		var sz := -0.5 if (k & 4) == 0 else 0.5
		var v := Vector3(sx * size.x, sy * size.y, sz * size.z)
		v += Vector3(rng.randf_range(-jitter, jitter) * size.x, rng.randf_range(-jitter, jitter) * size.y, rng.randf_range(-jitter, jitter) * size.z)
		corners.append(v)
	return corners


# --- Props (world visual pass, cghath 2026-10-20) --------------------------------------------------

## Man-made clutter was one dark box per item. Now each is one of a few shapes, picked by where it
## stands (the layout, its checksum and the caches are as they were): the roadside props (up to
## PROP_SMALL_M) a crate stack, a cluster of drums or a debris pile; the ruins and wrecks a broken
## wall corner with its rubble, a rubble mound, or (a long one) a car wreck. Each shape is parts in
## a unit box (x, z -0.5..0.5, y -0.5 at the ground to 0.5), scaled by the item's size along its
## own axes and turned by its yaw, drawn and collided the same (collision_parts). A part: [0 (a
## box), lo, hi, shade] or [1 (a drum: an upright octagonal prism), foot centre, Vector3(half
## width, height, 0), shade]; a fifth element false: drawn only (a painted detail on another
## part's face, standing out of it by a hair).
const PROP_SHAPES := {
	"crates": [[0, Vector3(-0.5, -0.5, -0.5), Vector3(0.5, 0.1, 0.5), 1.0], [0, Vector3(-0.42, 0.1, -0.38), Vector3(0.18, 0.5, 0.22), 0.92],
		[0, Vector3(-0.51, -0.24, -0.51), Vector3(0.51, -0.14, 0.51), 0.7, false]],
	"drums": [[1, Vector3(-0.24, -0.5, -0.24), Vector3(0.22, 1.0, 0), 1.0], [1, Vector3(0.24, -0.5, -0.2), Vector3(0.22, 1.0, 0), 0.9],
		[1, Vector3(0.0, -0.5, 0.25), Vector3(0.22, 0.85, 0), 0.82]],
	"debris": [[0, Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.2, 0.5), 0.95], [0, Vector3(-0.35, -0.2, -0.3), Vector3(0.3, 0.1, 0.35), 1.0],
		[0, Vector3(-0.15, 0.1, -0.1), Vector3(0.2, 0.5, 0.2), 0.88]],
	"wall": [[0, Vector3(-0.5, -0.5, -0.5), Vector3(-0.1, 0.5, -0.32), 1.0], [0, Vector3(-0.1, -0.5, -0.5), Vector3(0.25, 0.1, -0.32), 1.0],
		[0, Vector3(0.25, -0.5, -0.5), Vector3(0.5, -0.25, -0.32), 1.0], [0, Vector3(-0.5, -0.5, -0.32), Vector3(-0.32, 0.25, 0.0), 0.94],
		[0, Vector3(-0.5, -0.5, 0.0), Vector3(-0.32, -0.15, 0.3), 0.94], [0, Vector3(-0.2, -0.5, -0.2), Vector3(0.3, -0.35, 0.3), 0.82],
		[0, Vector3(0.1, -0.5, 0.05), Vector3(0.45, -0.28, 0.45), 0.78]],
	"wreck": [[0, Vector3(-0.5, -0.3, -0.48), Vector3(0.5, 0.05, 0.48), 1.0], [0, Vector3(-0.25, 0.05, -0.42), Vector3(0.25, 0.5, 0.42), 0.92],
		[0, Vector3(-0.22, 0.18, -0.43), Vector3(0.22, 0.42, 0.43), 0.35, false], [0, Vector3(-0.42, -0.5, -0.5), Vector3(-0.18, -0.15, -0.36), 0.3],
		[0, Vector3(0.18, -0.5, -0.5), Vector3(0.42, -0.15, -0.36), 0.3], [0, Vector3(-0.42, -0.5, 0.36), Vector3(-0.18, -0.15, 0.5), 0.3],
		[0, Vector3(0.18, -0.5, 0.36), Vector3(0.42, -0.15, 0.5), 0.3]],
	"mound": [[0, Vector3(-0.5, -0.5, -0.45), Vector3(0.45, -0.32, 0.5), 0.9], [0, Vector3(-0.45, -0.32, -0.4), Vector3(-0.05, 0.0, 0.05), 1.0],
		[0, Vector3(-0.1, -0.32, -0.1), Vector3(0.35, -0.05, 0.4), 0.94], [0, Vector3(0.15, -0.32, -0.5), Vector3(0.5, -0.12, -0.15), 0.86],
		[0, Vector3(-0.35, 0.0, -0.3), Vector3(-0.1, 0.22, -0.05), 0.97], [0, Vector3(0.0, -0.05, 0.05), Vector3(0.22, 0.12, 0.3), 0.88],
		[0, Vector3(-0.22, -0.32, 0.12), Vector3(-0.08, 0.5, 0.38), 0.82]],
}
## Roadside props are up to this big (m, _lay_out: 0.5 to 1.1); ruins are bigger. A ruin this
## much longer than wide is a car wreck (most of the time).
const PROP_SMALL_M := 1.15
const WRECK_RATIO := 1.35
## Ruins (broken walls, rubble) are drawn this much lighter than their colour; a prop sinks into
## a slope by at most this share of its height (_sink).
const RUIN_LIGHTEN := 0.22
const PROP_SINK_MAX := 0.35


## Paint for the shapes that have their own (a drum is olive, blue or rust, not the colour of the
## crates it would have been), picked by where it stands.
const PROP_PAINT := {"drums": [Color("5b6340"), Color("3f5a78"), Color("8a4e2e"), Color("6b6f6a")]}


## Which PROP_SHAPES shape prop `item` is, from where it stands and its size.
static func _prop_kind(item: Dictionary) -> String:
	var p: Vector3 = item.pos
	var s: Vector3 = item.size
	var roll := absi(hash(Vector2i(roundi(p.x * 10.0), roundi(p.z * 10.0)))) % 1000
	if maxf(s.x, s.z) <= PROP_SMALL_M:
		return ["crates", "drums", "debris"][roll % 3]
	if maxf(s.x, s.z) >= minf(s.x, s.z) * WRECK_RATIO and roll % 5 < 3:
		return "wreck"
	return ["wall", "mound"][roll % 2]


## Prop `item`'s turn and size as drawn: [yaw, size]; a wreck lies along its longer side (its shape
## is long in x), so one longer in z is turned a quarter more with its x and z swapped.
static func _prop_transform(item: Dictionary) -> Array:
	var s: Vector3 = item.size
	var yaw := float(item.yaw)
	if _prop_kind(item) == "wreck" and s.z > s.x:
		return [yaw + PI * 0.5, Vector3(s.z, s.y, s.x)]
	return [yaw, s]


## A prop part's corners in the unit box (8 for a box, 16 for a drum).
static func _part_points(part: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var a: Vector3 = part[1]
	var b: Vector3 = part[2]
	if int(part[0]) == 0:
		for k in 8:
			out.append(Vector3(a.x if (k & 1) == 0 else b.x, a.y if (k & 2) == 0 else b.y, a.z if (k & 4) == 0 else b.z))
	else:
		for y: float in [a.y, a.y + b.y]:
			for v: Vector2 in _octagon(b.x):
				out.append(Vector3(a.x + v.x, y, a.z + v.y))
	return out


## The mesh of prop shape `kind` (PROP_SHAPES), flat shaded like the rest, each part its shade.
func _prop_mesh(kind: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in PROP_SHAPES[kind]:
		var shade := Color.WHITE * float(part[3])
		if int(part[0]) == 0:
			_add_box(st, _part_points(part), shade)
		else:
			var a: Vector3 = part[1]
			var b: Vector3 = part[2]
			_tier(st, a.x, a.z, a.y, a.y + b.y, b.x, b.x, shade / SIDE_SHADE)
	return st.commit()


func _add_box(st: SurfaceTool, corners: Array[Vector3], colour: Color) -> void:
	var centre := Vector3.ZERO
	for c in corners:
		centre += c / 8.0
	for q: Array in [[1, 3, 7, 5], [0, 4, 6, 2], [2, 6, 7, 3], [0, 1, 5, 4], [4, 5, 7, 6], [0, 2, 3, 1]]:
		var a: Vector3 = corners[q[0]]
		var b: Vector3 = corners[q[1]]
		var c: Vector3 = corners[q[2]]
		var d: Vector3 = corners[q[3]]
		var n := (b - a).cross(c - a).normalized()
		if n.dot((a + b + c + d) / 4.0 - centre) < 0.0:
			n = -n
			var swap := b
			b = d
			d = swap
		# a, b, c, d run counter-clockwise seen from outside; Godot wants clockwise.
		for v: Vector3 in [a, c, b, a, d, c]:
			st.set_color(colour)
			st.set_normal(n)
			st.add_vertex(v)


## Trees and scrub are built like the soldiers (VoxelArt lofts): stacked tiers with an
## octagonal cross-section (a square with its corners cut at 45 degrees), flat faces, light on
## top and darker underneath (the instance colour tints them). Scrub keeps inside the cylinder
## spotting hides people in (foliage_between: SCRUB_R, SCRUB_TOP); a crown's octagon corners and
## lobes reach out to about 1.45 x its size, past CROWN_R (as the old blocks' corners did), so its
## outer edge doesn't hide anyone (CROWN_LOW and CROWN_HIGH match it).
const TOP_SHADE := 1.0
const SIDE_SHADE := 0.82
const UNDER_SHADE := 0.6
## A tree's chance of being a conifer when its preset doesn't say ("scatter": "conifer_share").
const CONIFER_SHARE := 0.2


## Whether tree `item` is drawn as a conifer: its preset's share of them, picked by where it
## stands (the same every visit; the layout and its checksum don't change).
func _is_conifer(item: Dictionary) -> bool:
	var p: Vector3 = item.pos
	var roll := float(absi(hash(Vector2i(roundi(p.x * 10.0), roundi(p.z * 10.0)))) % 1000) / 1000.0
	return roll < float(_spec.get("conifer_share", CONIFER_SHARE))


## One tier: an octagonal frustum from y0 (half-width r0) to y1 (r1), centred on (cx, cz),
## with flat top and bottom.
func _tier(st: SurfaceTool, cx: float, cz: float, y0: float, y1: float, r0: float, r1: float, tint := Color.WHITE) -> void:
	var ring := func(y: float, r: float) -> Array[Vector3]:
		var out: Array[Vector3] = []
		var c := r * 0.7  # the 45-degree cut leaves 0.7 of each side (VoxelArt bevel 0.3)
		for v: Vector2 in [Vector2(c, -r), Vector2(r, -c), Vector2(r, c), Vector2(c, r), Vector2(-c, r), Vector2(-r, c), Vector2(-r, -c), Vector2(-c, -r)]:
			out.append(Vector3(cx + v.x, y, cz + v.y))
		return out
	var lo: Array[Vector3] = ring.call(y0, r0)
	var hi: Array[Vector3] = ring.call(y1, r1)
	var mid := Vector3(cx, (y0 + y1) * 0.5, cz)
	for i in 8:
		var j := (i + 1) % 8
		_face(st, [lo[i], lo[j], hi[j], hi[i]], mid, tint * SIDE_SHADE)
	for i in range(1, 7):
		_face(st, [hi[0], hi[i], hi[i + 1]], mid, tint * TOP_SHADE)
		_face(st, [lo[0], lo[i + 1], lo[i]], mid, tint * UNDER_SHADE)


## A flat face through `points` (3 or 4, in order), turned to face away from `inside`.
func _face(st: SurfaceTool, points: Array, inside: Vector3, colour: Color, up_normal := false) -> void:
	var a: Vector3 = points[0]
	var b: Vector3 = points[1]
	var c: Vector3 = points[2]
	var n := (b - a).cross(c - a).normalized()
	var centre := Vector3.ZERO
	for q: Vector3 in points:
		centre += q / points.size()
	var flip := n.dot(centre - inside) < 0.0
	if flip:
		n = -n
	colour.a = 1.0
	var tris := [[0, 1, 2]] if points.size() == 3 else [[0, 1, 2], [0, 2, 3]]
	for t: Array in tris:
		# Godot wants clockwise seen from outside.
		var order: Array = [t[0], t[2], t[1]] if not flip else [t[0], t[1], t[2]]
		for k: int in order:
			st.set_color(colour)
			st.set_normal(Vector3.UP if up_normal else n)  # grass: lit like the ground it stands on
			st.add_vertex(points[k])


## Scrub: four small octagonal clumps on the ground, the middle one tallest (within SCRUB_R,
## up to SCRUB_TOP of its height). World visual pass (cghath, 2026-10-20): the outer clumps were
## small and low (out to about 0.42 of its width and 0.34 to 0.42 of its height), so the cylinder
## spotting hides people in (SCRUB_R, SCRUB_TOP) stood well clear of the leaves round its edge and
## top: a thicket hid a man through air. Now they reach out to 0.46-0.49 and up to 0.46-0.5, the
## same four clumps (no more triangles), filling that cylinder.
func _scrub_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c: Array in [[0.0, 0.0, 0.27, 0.58], [0.22, 0.1, 0.2, 0.5], [-0.19, 0.14, 0.19, 0.48], [0.03, -0.23, 0.19, 0.46]]:
		var r: float = c[2]
		var h: float = c[3]
		_tier(st, c[0], c[1], 0.0, h * 0.7, r * 0.75, r)
		_tier(st, c[0], c[1], h * 0.7, h, r, r * 0.55)
	return st.commit()


## A grass tuft: five thin four-sided blades from a 0.25 m clump, leaning out, up to 0.45 m.
func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 5:
		var a := k * TAU / 5.0 + 0.4 * (k % 2)
		var out := Vector3(cos(a), 0.0, sin(a))
		var foot := out * (0.05 + 0.04 * (k % 3))
		var tip := out * (0.12 + 0.05 * (k % 2)) + Vector3(0, 0.30 + 0.05 * (k % 3), 0)
		var w := 0.035
		var side := out.cross(Vector3.UP) * w
		var b := [foot + side, foot + out * w, foot - side, foot - out * w]
		var inside := foot + (tip - foot) * 0.25
		for i in 4:
			var shade := TOP_SHADE if i % 2 == 0 else SIDE_SHADE
			_face(st, [b[i], b[(i + 1) % 4], tip], inside, Color.WHITE * lerpf(shade, 1.0, 0.3), true)
	return st.commit()


## A broadleaf crown: a rounded blob of four tiers from 2 m up (the trunk's top) to 4.9 m.
func _crown_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t: Array in [[2.0, 2.55, 0.65, 1.05], [2.55, 3.45, 1.05, 1.1], [3.45, 4.3, 1.1, 0.85], [4.3, 4.9, 0.85, 0.35]]:
		_tier(st, 0.0, 0.0, t[0], t[1], t[2], t[3])
	# Two lobes out to the sides break the outline (within CROWN_R of the middle, about).
	_tier(st, 0.72, 0.18, 2.55, 3.15, 0.45, 0.6)
	_tier(st, 0.72, 0.18, 3.15, 3.75, 0.6, 0.3)
	_tier(st, -0.45, -0.62, 3.25, 3.85, 0.42, 0.55)
	_tier(st, -0.45, -0.62, 3.85, 4.4, 0.55, 0.25)
	return st.commit()


## A conifer: three stacked tiers, each narrower, from 2 m up to 4.9 m.
func _conifer_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t: Array in [[2.0, 3.0, 1.15, 0.7], [2.8, 3.9, 0.9, 0.45], [3.7, 4.9, 0.6, 0.06]]:
		_tier(st, 0.0, 0.0, t[0], t[1], t[2], t[3])
	return st.commit()


## The trunk: an octagonal post, a little narrower at the top, 2.6 m tall (into the crown).
func _trunk_mesh(colour: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tier(st, 0.0, 0.0, 0.0, TRUNK_TALL, TRUNK_FOOT_R, TRUNK_TOP_R, colour / SIDE_SHADE)
	return st.commit()
