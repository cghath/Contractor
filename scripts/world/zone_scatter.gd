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
## skipped on a headless server, in two tiers (woods perf pass, cghath's queue item 1.8): the
## full shapes out to LOD_M, low-poly stand-ins past it; past SEE_TREE_M the trees give way to low
## canopy blobs (one per FAR_GROUP_M square of trees, a MultiMesh per FAR_BLOCK cells a side) out
## to the horizon. Large rocks and tree trunks also have
## collision (one static body per cell, built up front: cover for the AI) and are baked into the
## navigation mesh as boxes; scrub and thickets are visual only (and hide people: foliage_between,
## walked on a FINE_M index).
##
## The layout is cached (Captain, 2026-10-14: "we'll use caching for performance if needed"):
## in memory per zone (seed, preset, ground, pads, roads) with the cells' built meshes, and on
## disk (user://cache), so coming back to a zone costs nothing.
##
## Ruins and wrecks (Captain, 2026-10-16, playtest B1399 on Red Mesa: "open terrain reads nearly
## empty"): bigger, rougher PROP clutter out in the open terrain, not just roadside. VALUABLE
## marks where WorldValuables spawns real lootable pickups (caches, crates, wrecks with kit, dead
## drops) — a placement kind with no mesh of its own; see valuable_sites().
##
## The prop library (cghath's queue item 1.7, PropArt and ZoneProps): street furniture, market
## stalls, fences and gates, pylons and poles with their wires, farm and water props, scenery
## vehicles and burnt-out hulks (in place of the old box wrecks), shipping containers, graves, site
## clutter, laid out first (ZoneProps.lay_out) so the rocks and trees keep off them. A library prop
## is a PROP item with a "shape" (PropArt.NAMES), a "paint" and a "link" (its wires run to the item
## before it); its size is a scale (ONE). Each part collides as drawn and takes rounds by its own
## material (round_through, from Ballistics and VoxelWorld.stops_round_in); see-through parts
## (chain-link, barbed wire) stop men but not sight or rounds. ANIMAL marks where ZoneAnimals keeps
## goats, sheep and dogs (no mesh of its own).

enum Kind { ROCK, SCRUB, TREE, THICKET, PROP, VALUABLE, ANIMAL }

## Most items of each kind in a zone (a 16 km2 hot zone hits them). Round 4 raised the trees
## for the woods; a nav chunk is 12 m (ZoneNav), so more trunk boxes cost little per bake.
## Captain, 2026-10-14 (v0.4.0): "the copses of trees are too small and spread out to be
## cover": bigger, denser copses, so trees 5000 -> 6000, thickets 5000 -> 8000 (visual only,
## no collision) and solid 5600 -> 6800 (Proposed).
const CAP_ROCKS := 2600
const CAP_SCRUB := 9000
const CAP_TREES := 9000  # Captain, 2026-10-16: "forests still are too small" (was 6000); 2026-10-17: sprawling woods (was 8000)
const CAP_THICKETS := 16000  # sprawling woods take more (2026-10-17; was 8000): copses keep their thicket skirts. Woods perf pass (queue item 1.8; was 11000): a 16 km2 zone of a normal preset with the dense copses ran out before its last copses had their skirts
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
## Woods perf pass (cghath's queue item 1.8; Captain, 2026-10-14: "frame goes 4 -> 10 ms in woods,
## up to 1.5k draws, 1.4M prims. Then denser copses"). Each cell is drawn in two tiers that hand
## over at LOD_M from its middle (the same margin both ways, so never both and never neither):
## near, the full trees, thickets and scrub as before plus the ground cover, built only for cells
## within NEAR_BUILD_M (the farthest near thing, the rock clusters at SEE_OUTCROP_M, plus half a
## cell's diagonal and the margin); and far (out to BUILD_M), low-poly stand-ins of the same items
## (_lod_meshes: a crown is 44 triangles, not 164; a thicket 38, not 152) with the rocks and props.
## Proposed.
const LOD_M := 200.0
const LOD_MARGIN_M := 20.0
const NEAR_BUILD_M := 420.0
## A cell's tiers (the cache keeps each tier's built parts: Vector3i(cell.x, cell.y, tier)).
enum Tier { FAR, NEAR }
## The keys drawn as the near tier's full shapes and their low-poly stand-ins in the far tier.
const LOD_KEYS := {Kind.SCRUB: "scrub_lod", "thicket": "thicket_lod", "trunk": "trunk_lod", "crown": "crown_lod", "conifer": "conifer_lod"}
## Far canopy blobs are grouped FAR_BLOCK x FAR_BLOCK cells to a MultiMesh (a fourth of the draws),
## and each block is its cells' far-tier trees' visibility parent: past SEE_TREE_M from the block's
## middle the blobs show and its cells' trees and thickets don't (hierarchical LOD, so a tree is
## never drawn twice and never missing). Proposed.
const FAR_BLOCK := 2
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
## 11: every tree solid (2026-10-18).
const LAYOUT_VERSION := 16  # 12: the prop library (ZoneProps, 2026-10-21); 13: its props keep out of the water; 14: out of farmland's fields, a city's laid once (F-187) / the woods perf pass's thicket cap (2026-10-22, two branches' 14s); 15: the terrain features and paved roads in the same layout; 16: all of these met (world/perf); old caches re-roll
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
var counts := {Kind.ROCK: 0, Kind.SCRUB: 0, Kind.TREE: 0, Kind.THICKET: 0, Kind.PROP: 0, Kind.VALUABLE: 0, Kind.ANIMAL: 0}
var solid_count := 0
## Library props (PropArt shapes) in the layout (they're PROP items too, but not in solid_count).
var library_count := 0
## What the last fresh layout's ZoneProps laid ({} from a cache), for tests.
var props_report := {}
## Where the last generate's layout came from: "generated", "memory" or "disk" ("" none).
var cache_source := ""
## The copses and groves the last fresh layout made (not kept in the cache: empty when the
## layout came from memory or disk), for tests: {"centre" (Vector2), "r" (m), "trees", "grove"}.
var copse_sites: Array[Dictionary] = []

var _terrain: ZoneTerrain
var _spec := {}
var _cells := {}  # Vector2i -> Array of item indices
var _tall := {}  # Vector2i (TALL_CELL_M) -> PackedFloat32Array of x, z, reach, top: tall_top's index
var _tall_built := false
var _built := {}  # Vector2i -> true: the cell's far tier is built
var _built_near := {}  # Vector2i -> true: its near tier
## The woods perf pass's fine index (FINE_M squares, from where each item stands): the foliage as
## packed numbers for spotting (_foliage: Vector2i -> PackedFloat64Array of FOLIAGE_FIELDS each:
## x, z, its cylinder's radius, bottom, top, and 1 for scrub, seen only to SEE_SCRUB_M), the
## widest radius in it, and the solid items and library props by index for navigation (_solids).
## Built with the layout (_index_fine) and kept in its cache entry.
var _foliage := {}
var _foliage_reach := 0.0
var _solids := {}
var _indexed := -1  # items.size() when the fine index was built (a test may hand-fill items: built again on use)
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
var _def := {}
var _props: ZoneProps  # while laying out: the library's placement (rocks and trees keep off its props)
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
## An 8 km zone (BigZoneStreaming): every cap times its area over a hot zone's (the density held,
## not the count: docs/combined_arms.md 6.2.2), and its cover collides only near the action.
var _scale := 1.0
var on_demand := false
var _cover_bodies := {}  # Vector2i cell -> its StaticBody3D


## Lays the items out. `terrain` must be generated; `def` is the zone's def ("roads" in it
## keep clear).
func generate(terrain: ZoneTerrain, def: Dictionary) -> void:
	_terrain = terrain
	var fresh: Array[Dictionary] = []
	items = fresh  # new arrays, never clear(): a cached layout may share the old ones
	_cells = {}
	_built = {}
	_built_near = {}
	_foliage = {}
	_foliage_reach = 0.0
	_solids = {}
	_indexed = -1
	_tall = {}
	_tall_built = false
	counts = {Kind.ROCK: 0, Kind.SCRUB: 0, Kind.TREE: 0, Kind.THICKET: 0, Kind.PROP: 0, Kind.VALUABLE: 0, Kind.ANIMAL: 0}
	solid_count = 0
	library_count = 0
	props_report = {}
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
	_def = def
	var cluster := FastNoiseLite.new()
	cluster.seed = terrain.seed_value + 77
	cluster.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cluster.frequency = 1.0 / 240.0
	_cluster = cluster
	_key = _cache_key()
	if _from_memory() or _from_disk():
		return
	_lay_out()
	_index_fine()
	cache_source = "generated"
	_remember()
	_to_disk()


## The caps for this preset: the copses-as-cover ones with "copse_cover", else round 4's.
func _set_caps() -> void:
	_cover = bool(_spec.get("copse_cover", false))
	on_demand = _terrain != null and BigZoneStreaming.streams(_terrain.size_m)
	_scale = BigZoneStreaming.scatter_scale(_terrain.size_m) if on_demand else 1.0
	_cap_trees = _cap(CAP_TREES if _cover else ROUND4_CAP_TREES)
	_cap_thickets = _cap(CAP_THICKETS if _cover else ROUND4_CAP_THICKETS)
	_cap_solid = _cap(CAP_SOLID if _cover else ROUND4_CAP_SOLID)


	_woods_share = WOODS_SHARE if _cover else ROUND4_WOODS_SHARE
	_copses_share = COPSES_SHARE if _cover else ROUND4_COPSES_SHARE


## Cap `n` for this zone (times _scale).
func _cap(n: int) -> int:
	return int(n * _scale)


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
	# The prop library first: everything after keeps off it (_props.blocks).
	_props = ZoneProps.new()
	_props.lay_out(self, terrain, _def)
	props_report = _props.report
	# Rocks.
	var want := mini(int(round(float(_spec.get("rocks_per_km2", 0.0)) * area_km2)), _cap(CAP_ROCKS))
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
		if _blocked(x, z, _keep, _roads) or _props.blocks(x, z, 0.8 + scale_roll * 1.0):
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
	want = mini(int(round(float(_spec.get("props_per_km2", 0.0)) * area_km2)), _cap(CAP_PROPS))
	attempts = int(want * tries_per)
	while counts[Kind.PROP] < want and attempts > 0 and props_near > 0.0:
		attempts -= 1
		var x := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		var z := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		if not _near_road_or_pad(x, z, props_near):
			continue
		if _blocked(x, z, _keep, _roads) or _props.blocks(x, z, 0.8):
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
	want = mini(int(round(float(_spec.get("ruins_per_km2", 0.0)) * area_km2)), _cap(CAP_PROPS) - counts[Kind.PROP])
	attempts = int(want * tries_per)
	while want > 0 and attempts > 0:
		attempts -= 1
		var x := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		var z := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		if _blocked(x, z, _keep, _roads) or _props.blocks(x, z, 2.0):
			continue
		if open and rng.randf() > _open_weight(x, z):
			continue
		var h := terrain.height_at(x, z)
		if terrain.sea_side >= 0 and h < terrain.sea_level + 0.35:
			continue
		if terrain.normal_at(x, z).y < 0.6:
			continue
		var size := Vector3(rng.randf_range(RUIN_SIZE_LO, RUIN_SIZE_HI), rng.randf_range(RUIN_SIZE_LO, RUIN_SIZE_HI) * 0.6, rng.randf_range(RUIN_SIZE_LO, RUIN_SIZE_HI))
		var ruin := {"kind": Kind.PROP, "yaw": rng.randf() * TAU, "solid": true, "size": size, "pos": Vector3(x, h + size.y * 0.5, z),
			"colour": ruin_colours[rng.randi() % ruin_colours.size()]}
		# A car wreck is a burnt-out vehicle hulk from the library now (queue item 1.7: "real voxel
		# shapes in place of box wrecks"), lying the way the wreck would have; the old box only where
		# a hulk doesn't fit.
		if _prop_kind(ruin) == "wreck" and _props.hulk(x, z, float(_prop_transform(ruin)[0])):
			want -= 1
			continue
		_add(ruin)
		want -= 1
	# Valuable sites: where WorldValuables (host) will spawn real lootable pickups (caches,
	# crates, wrecks with kit, dead drops) — well away from a site or a road (VALUABLE_AVOID_M,
	# more than the bare pad/road keep-out), so this never marks a spot right by a mission.
	# No mesh of its own: ZoneScatter only places the marker, deterministic like everything else.
	want = mini(int(round(float(_spec.get("valuables_per_km2", 0.0)) * area_km2)), _cap(CAP_VALUABLES))
	attempts = int(want * tries_per)
	while counts[Kind.VALUABLE] < want and attempts > 0:
		attempts -= 1
		var x := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		var z := rng.randf_range(-_half + EDGE_KEEP_M, _half - EDGE_KEEP_M)
		if _near_road_or_pad(x, z, VALUABLE_AVOID_M) or _blocked(x, z, _keep, _roads) or _props.blocks(x, z, 1.0):
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
	if terrain.features:
		terrain.features.lay_out(self)  # talus under the cliffs, orchards, hedges (queue item 1.3)
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
	want = mini(int(round(float(_spec.get("scrub_per_km2", 0.0)) * area_km2)), _cap(CAP_SCRUB) - counts[Kind.SCRUB])
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
	_props = null


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
	_cap_thickets = counts[Kind.THICKET] + _cap(BELT_CAP)
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
	if counts[Kind.ROCK] >= _cap(CAP_ROCKS) or solid_count >= _cap_solid or absf(x) > _half - EDGE_KEEP_M or absf(z) > _half - EDGE_KEEP_M:
		return false
	if _crowded(x, z) or _blocked(x, z, _keep, _roads) or (_props and _props.blocks(x, z, s * 0.6)):
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
	if _crowded(x, z) or _blocked(x, z, _keep, _roads) or (_props and _props.blocks(x, z, 1.3 * s)):
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
	var cap := _cap_thickets if kind == Kind.THICKET else _cap(CAP_SCRUB)
	if counts[kind] >= cap or absf(x) > _half - EDGE_KEEP_M or absf(z) > _half - EDGE_KEEP_M:
		return false
	if _blocked(x, z, _keep, _roads) or (_props and _props.blocks(x, z, s * SCRUB_R)):
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
	if item.has("shape") and int(item.kind) == Kind.PROP:
		library_count += 1
		_tall_built = false
	elif item.solid:
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
	var modules: Array = []  # (the library's town streets and site clutter go by the modules' types)
	for m: Dictionary in _def.get("modules", []):
		modules.append([String(m.get("type", "")), m.get("pos", [])])
	var parts := [LAYOUT_VERSION, t.seed_value, t.size_m, t.preset_id, t.checksum(), t.sea_side, t.sea_level, JSON.stringify(_spec, "", true), str(_keep), str(_roads), str(modules)]
	return str(parts).sha256_text()


func _from_memory() -> bool:
	if not _cache.has(_key):
		return false
	_entry = _cache[_key]
	items = _entry.items
	_cells = _entry.cells
	counts = (_entry.counts as Dictionary).duplicate()
	solid_count = int(_entry.solid)
	library_count = int(_entry.get("library", 0))
	_foliage = _entry.foliage
	_foliage_reach = float(_entry.foliage_reach)
	_solids = _entry.solids
	_indexed = items.size()
	cache_source = "memory"
	_touch()
	return true


func _remember() -> void:
	_entry = {"items": items, "cells": _cells, "counts": counts.duplicate(), "solid": solid_count, "library": library_count, "visual": {}, "far": {},
		"foliage": _foliage, "foliage_reach": _foliage_reach, "solids": _solids}
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


## Forgets this layout in memory (it stays on disk). An on_demand (8 km) zone's does as it leaves
## the tree (_exit_tree; cg_brief 3.1, memory cap): ~160,000 items, so up to CACHE_ZONES of them kept
## in memory would be gigabytes. Proposed.
func forget() -> void:
	_cache.erase(_key)
	_cache_order.erase(_key)
	_entry = {}


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


## Items on disk: DISK_FIELDS numbers each (kind, position, yaw, size, colour, solid, and a library
## prop's shape (PropArt.NAMES index, -1 none), paint and link), compressed.
const DISK_FIELDS := 15


func _to_disk() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var flat := PackedFloat64Array()
	flat.resize(items.size() * DISK_FIELDS)
	var k := 0
	for item in items:
		var p: Vector3 = item.pos
		var s: Vector3 = item.size
		var c: Color = item.colour
		var shape := float(PropArt.index_of(String(item.shape))) if item.has("shape") else -1.0
		for v: float in [float(item.kind), p.x, p.y, p.z, float(item.yaw), s.x, s.y, s.z, c.r, c.g, c.b, 1.0 if item.solid else 0.0,
				shape, float(item.get("paint", 0)), float(item.get("link", 0))]:
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
	for k in range(0, flat.size(), DISK_FIELDS):
		var item := {"kind": int(flat[k]), "pos": Vector3(flat[k + 1], flat[k + 2], flat[k + 3]), "yaw": flat[k + 4],
			"size": Vector3(flat[k + 5], flat[k + 6], flat[k + 7]), "colour": Color(flat[k + 8], flat[k + 9], flat[k + 10]), "solid": flat[k + 11] > 0.5}
		if flat[k + 12] >= 0.0:
			item["shape"] = PropArt.NAMES[int(flat[k + 12])]
			item["paint"] = int(flat[k + 13])
			item["link"] = int(flat[k + 14])
		_add(item)
	_index_fine()
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
	if _terrain and _terrain.features and _terrain.features.keeps_clear(x, z):
		return true  # a field (ZoneFeatures: its orchards and hedges go in through its lay_out)
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
		flat.append_array([float(item.kind), p.x, p.y, p.z, item.yaw, (item.size as Vector3).x, float(PropArt.index_of(String(item.get("shape", "")))), float(item.get("paint", 0))])
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
## the navigation mesh (by the fine index: a nav chunk is 12 m, a cell 128 m).
func boxes_in(area: Rect2) -> Array[AABB]:
	var out: Array[AABB] = []
	if _cells.is_empty():
		return out
	if _indexed != items.size():
		_index_fine()
	for row: PackedInt32Array in _fine_rows(_solids, area):
		for index in row:
			var item: Dictionary = items[index]
			if not item.solid or item.has("shape") or not area.has_point(Vector2(item.pos.x, item.pos.z)):
				continue
			var half := _solid_half(item)
			var p: Vector3 = item.pos
			var centre := p + Vector3(0, half.y, 0) if item.kind == Kind.TREE else p
			out.append(AABB(centre - half, half * 2.0))
	return out


# --- The fine index (woods perf pass) --------------------------------------------------------

## The fine index's squares (m) and the numbers a foliage item has in it (_foliage). Proposed: a
## 128 m cell holds up to ~2000 items in a dense wood, and every sight line and nav chunk near it
## walked them all (cghath's queue item 1.8).
const FINE_M := 16.0
const FOLIAGE_FIELDS := 6


## Indexes the layout by FINE_M square: the foliage's cylinders, as foliage_between measures them
## (_foliage, _foliage_reach), and the solid items and library props (_solids).
func _index_fine() -> void:
	var rows := {}  # Vector2i -> Array of numbers
	var solids := {}  # Vector2i -> Array of item indices
	var reach := 0.0
	for index in items.size():
		var item: Dictionary = items[index]
		var kind := int(item.kind)
		var p: Vector3 = item.pos
		var g := Vector2i(floori(p.x / FINE_M), floori(p.z / FINE_M))
		if item.get("solid", false) or (item.has("shape") and kind == Kind.PROP):
			if not solids.has(g):
				solids[g] = []
			(solids[g] as Array).append(index)
		if kind == Kind.ROCK or kind >= Kind.PROP:
			continue  # solid (rays see to it) or not foliage
		var size: Vector3 = item.size
		var bush := kind != Kind.TREE
		var conifer := not bush and bool(item.get("conifer", false))
		var r := size.x * (SCRUB_R if bush else (CONIFER_R if conifer else CROWN_R))
		reach = maxf(reach, r)
		if not rows.has(g):
			rows[g] = []
		(rows[g] as Array).append_array([p.x, p.z, r, p.y + (0.0 if bush else size.y * CROWN_LOW),
			p.y + size.y * (SCRUB_TOP if bush else (CONIFER_HIGH if conifer else CROWN_HIGH)), 1.0 if kind == Kind.SCRUB else 0.0])
	_foliage = {}
	for g: Vector2i in rows:
		_foliage[g] = PackedFloat64Array(rows[g])
	_solids = {}
	for g: Vector2i in solids:
		_solids[g] = PackedInt32Array(solids[g])
	_foliage_reach = reach
	_indexed = items.size()


## The rows of `index` (_solids) for the FINE_M squares over `area`.
func _fine_rows(index: Dictionary, area: Rect2) -> Array:
	var out: Array = []
	for gz in range(floori(area.position.y / FINE_M), floori(area.end.y / FINE_M) + 1):
		for gx in range(floori(area.position.x / FINE_M), floori(area.end.x / FINE_M) + 1):
			var row: Variant = index.get(Vector2i(gx, gz))
			if row != null:
				out.append(row)
	return out


## The foliage rows (_foliage) of the FINE_M squares whose items, `pad` round at most, can reach
## the flat line from (ax, az) to (bx, bz), the squares nearest (ax, az) first: square by square
## along x, each column only the squares the line crosses in it (and `pad` either side).
func _foliage_rows(ax: float, az: float, bx: float, bz: float, pad: float) -> Array:
	var out: Array = []
	var dx := bx - ax
	var dz := bz - az
	var lo := floori((minf(ax, bx) - pad) / FINE_M)
	var hi := floori((maxf(ax, bx) + pad) / FINE_M)
	var step := 1 if dx >= 0.0 else -1
	var gx := lo if step > 0 else hi
	var last := hi if step > 0 else lo
	while true:
		var t0 := 0.0
		var t1 := 1.0
		if absf(dx) > 0.000001:
			var ta := (gx * FINE_M - pad - ax) / dx
			var tb := ((gx + 1) * FINE_M + pad - ax) / dx
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
		if t0 <= t1:
			var za := az + dz * t0
			var zb := az + dz * t1
			var z0 := floori((minf(za, zb) - pad) / FINE_M)
			var z1 := floori((maxf(za, zb) + pad) / FINE_M)
			var zs := range(z0, z1 + 1) if dz >= 0.0 else range(z1, z0 - 1, -1)
			for gz: int in zs:
				var row: Variant = _foliage.get(Vector2i(gx, gz))
				if row != null:
					out.append(row)
		if gx == last:
			break
		gx += step
	return out


## Metres of a foliage cylinder (its middle (cx, cz) from the line's start, radius r, from y0 up
## to y1) that the line from height `fy` along (fx, dy, fz) passes through (`flen2` the square of
## its flat length, `length` its length): foliage_between's test, on the fine index's numbers.
static func _span(cx: float, cz: float, r: float, y0: float, y1: float, fx: float, fz: float, flen2: float, fy: float, dy: float, length: float) -> float:
	var along := (cx * fx + cz * fz) / flen2
	var mx := cx - fx * along
	var mz := cz - fz * along
	var miss2 := mx * mx + mz * mz
	if miss2 >= r * r:
		return 0.0
	var half_t := sqrt(r * r - miss2) / sqrt(flen2)
	var t0 := maxf(along - half_t, 0.0)
	var t1 := minf(along + half_t, 1.0)
	if absf(dy) < 0.0001:
		if fy < y0 or fy > y1:
			return 0.0
	else:
		var ta := (y0 - fy) / dy
		var tb := (y1 - fy) / dy
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	return (t1 - t0) * length if t1 > t0 else 0.0


## The least foliage_between `from` and either of `to_a` and `to_b` (a head and a chest), with
## the foliage walked once for both lines (Spotting.foliage_m: two walks per pair in sight were
## a large share of an AI scan, research 2026-10-13 B2.6). Walks the fine index from `from` out
## and stops once both lines have `enough` (Spotting: FOLIAGE_OPAQUE_M hides them, however much
## more there is), so the answer is exact below `enough` and at least `enough` past it.
func foliage_least(from: Vector3, to_a: Vector3, to_b: Vector3, enough := INF) -> float:
	if _indexed != items.size():
		_index_fine()
	if _foliage.is_empty() and not (_terrain and _terrain.features):
		return 0.0
	var started := Time.get_ticks_usec()
	var ax := to_a.x - from.x
	var az := to_a.z - from.z
	var bx := to_b.x - from.x
	var bz := to_b.z - from.z
	var a2 := ax * ax + az * az
	var b2 := bx * bx + bz * bz
	var a_on := a2 >= 0.0001  # (a line under a centimetre across meets nothing, as foliage_between)
	var b_on := b2 >= 0.0001
	var a_len := from.distance_to(to_a)
	var b_len := from.distance_to(to_b)
	var a_dy := to_a.y - from.y
	var b_dy := to_b.y - from.y
	var far2 := SEE_SCRUB_M * SEE_SCRUB_M
	var spread := Vector2(to_a.x - to_b.x, to_a.z - to_b.z).length() * 0.5
	# The middle line (from `from` to between the ends): an item further from it than its radius
	# and `spread` meets neither line.
	var mx := (ax + bx) * 0.5
	var mz := (az + bz) * 0.5
	var m2 := maxf(mx * mx + mz * mz, 0.0001)
	var a := 0.0
	var b := 0.0
	# The squares from both ends in turn (from `from`, then from the far end, ...): a line from in
	# a wood or into one meets most of its leaves near one end, and stops as soon as it has enough.
	var rows := _foliage_rows(from.x, from.z, from.x + mx, from.z + mz, _foliage_reach + spread)
	var n := rows.size()
	for k in n:
		var row: PackedFloat64Array = rows[k / 2 if k % 2 == 0 else n - 1 - k / 2]
		for i in range(0, row.size(), FOLIAGE_FIELDS):
			var cx := row[i] - from.x
			var cz := row[i + 1] - from.z
			if row[i + 5] > 0.5 and cx * cx + cz * cz > far2:
				continue  # as in foliage_between
			var t := clampf((cx * mx + cz * mz) / m2, 0.0, 1.0)
			var ex := cx - mx * t
			var ez := cz - mz * t
			var reach := row[i + 2] + spread
			if ex * ex + ez * ez >= reach * reach:
				continue
			if a_on:
				a += _span(cx, cz, row[i + 2], row[i + 3], row[i + 4], ax, az, a2, from.y, a_dy, a_len)
			if b_on:
				b += _span(cx, cz, row[i + 2], row[i + 3], row[i + 4], bx, bz, b2, from.y, b_dy, b_len)
		if a >= enough and b >= enough:
			break
	if _terrain and _terrain.features:
		var standing := _terrain.features.cover_least(from, to_a, to_b)  # crops and reed beds (queue item 1.3)
		a += standing.x
		b += standing.y
	FrameCost.spent(&"foliage", started)
	return minf(a, b)


## Metres of foliage (scrub, thickets, and tree crowns) the straight line `from` -> `to` passes
## through, for spotting (Spotting.foliage_m). Each is a vertical cylinder about its mesh: scrub
## and thickets SCRUB_R x their width, up to SCRUB_TOP x their height; a crown CROWN_R x its
## size, from CROWN_LOW to CROWN_HIGH x its size up (a conifer's CONIFER_R, to CONIFER_HIGH). Trunks and rocks are solid: rays see to
## those. A wood's thickets and low crowns add up: a few trees deep hides a standing man. Scrub
## past SEE_SCRUB_M of `from` (where it's no longer drawn) hides nobody; crowns and thickets any
## distance (past SEE_TREE_M the far canopy blobs stand for them). Walks the fine index's
## squares along the line (woods perf pass): the same answer as walking every item near it.
func foliage_between(from: Vector3, to: Vector3) -> float:
	if _indexed != items.size():
		_index_fine()
	if _foliage.is_empty():
		return 0.0
	var fx := to.x - from.x
	var fz := to.z - from.z
	var flen2 := fx * fx + fz * fz
	if flen2 < 0.0001:
		return 0.0
	var length := from.distance_to(to)
	var dy := to.y - from.y
	var far2 := SEE_SCRUB_M * SEE_SCRUB_M
	var total := 0.0
	for row: PackedFloat64Array in _foliage_rows(from.x, from.z, to.x, to.z, _foliage_reach):
		for i in range(0, row.size(), FOLIAGE_FIELDS):
			var cx := row[i] - from.x
			var cz := row[i + 1] - from.z
			if row[i + 5] > 0.5 and cx * cx + cz * cz > far2:
				continue
			var t := clampf((cx * fx + cz * fz) / flen2, 0.0, 1.0)
			var ex := cx - fx * t
			var ez := cz - fz * t
			if ex * ex + ez * ez >= row[i + 2] * row[i + 2]:
				continue  # (clear of the line: _span would say 0)
			total += _span(cx, cz, row[i + 2], row[i + 3], row[i + 4], fx, fz, flen2, from.y, dy, length)
	return total


## The same as foliage_between, the slow way it was measured before the fine index (every item in
## every 128 m cell near the line, from the items themselves), for tests to check the two agree.
func foliage_between_slow(from: Vector3, to: Vector3) -> float:
	if _cells.is_empty():
		return 0.0
	var flat := Vector2(to.x - from.x, to.z - from.z)
	var flat_len := flat.length()
	if flat_len < 0.01:
		return 0.0
	var pad := FOLIAGE_PAD_M
	var lo := _cell_of(minf(from.x, to.x) - pad, minf(from.z, to.z) - pad)
	var hi := _cell_of(maxf(from.x, to.x) + pad, maxf(from.z, to.z) + pad)
	var length := from.distance_to(to)
	var dy := to.y - from.y
	var total := 0.0
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			for index: int in _cells.get(Vector2i(cx, cz), []):
				var item: Dictionary = items[index]
				var kind := int(item.kind)
				if kind == Kind.ROCK or kind >= Kind.PROP:
					continue
				var p: Vector3 = item.pos
				if Vector2(p.x - from.x, p.z - from.z).length() > _see_m(kind):
					continue
				var size: Vector3 = item.size
				var bush := kind != Kind.TREE
				var conifer := not bush and bool(item.get("conifer", false))
				var r := size.x * (SCRUB_R if bush else (CONIFER_R if conifer else CROWN_R))
				var y0 := p.y + (0.0 if bush else size.y * CROWN_LOW)
				var y1 := p.y + size.y * (SCRUB_TOP if bush else (CONIFER_HIGH if conifer else CROWN_HIGH))
				var c := Vector2(p.x - from.x, p.z - from.z)
				var along := c.dot(flat) / (flat_len * flat_len)
				var miss := (c - flat * along).length()
				if miss >= r:
					continue
				var half_t := sqrt(r * r - miss * miss) / flat_len
				var t0 := maxf(along - half_t, 0.0)
				var t1 := minf(along + half_t, 1.0)
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
## A library prop's parts each name their item and part (the "prop" meta: Vector2i(item index, part
## index), for round_through); see-through parts (chain-link, barbed wire) go in a body of their own
## on Soldier.BODY_LAYER ("SeeThrough_x_z"): it stops men walking (and vehicles' sensing) but not
## sight lines or rounds, which look on layer 1. Also adds the zone's animals (ZoneAnimals, from the
## ANIMAL markers), at the same path on every peer.
func build_collision() -> void:
	if not on_demand:  # an 8 km zone's cover is built near the action instead (stream_collision)
		for cell: Vector2i in _cells:
			_build_cover(cell)
	if get_node_or_null(^"Animals") == null:
		var zoo := ZoneAnimals.new()
		zoo.setup(self, _terrain)
		add_child(zoo)


## Cell `cell`'s cover body (and its see-through body), as build_collision describes. Each body
## gets its shapes before it enters the tree (D2: one at a time inside it, the physics server rebuilt
## the body's shape for every one: a wooded cell was ~25 ms).
func _build_cover(cell: Vector2i) -> void:
	var body: StaticBody3D = null
	var through: StaticBody3D = null
	for index: int in _cells[cell]:
		var item: Dictionary = items[index]
		if not item.solid:
			continue
		if body == null:
			body = StaticBody3D.new()
			body.name = "Cover_%d_%d" % [cell.x, cell.y]
			body.collision_layer = 1
			body.collision_mask = 0
		for part: Array in collision_parts(item):
			var shape := CollisionShape3D.new()
			shape.shape = part[0]
			shape.transform = part[1]
			var holder := body
			if part.size() > 2:
				shape.set_meta(&"prop", Vector2i(index, int(part[2])))
				if bool(part[3]):
					if through == null:
						through = StaticBody3D.new()
						through.name = "SeeThrough_%d_%d" % [cell.x, cell.y]
						through.collision_layer = Soldier.BODY_LAYER
						through.collision_mask = 0
					holder = through
			holder.add_child(shape)
	if body:
		add_child(body)
	if through:
		add_child(through)
	_cover_bodies[cell] = [body, through]  # (nulls: a cell with nothing solid, still counted as built)


## An on_demand zone (BigZoneStreaming): the cover collision of the cells within `in_m` of any of
## `focus` (or `reach[k]` of focus k, where given), nearest first, at most `budget` (-1: all);
## cells further than `out_m` (scaled the same) from all of them freed. Returns how many it built.
## `until_usec` as ZoneTerrain.stream_collision's.
func stream_collision(focus: Array[Vector3], in_m: float, out_m: float, budget := -1, reach := PackedFloat32Array(), until_usec := 0) -> int:
	var todo := stream_plan(focus, in_m, out_m, reach)
	if budget >= 0:
		todo = todo.slice(0, budget)
	return build_cells(todo, until_usec)


## stream_collision's first half: frees the cells past reach (but those something lies by: held)
## and returns the wanted ones not built yet, nearest first, for build_cells.
func stream_plan(focus: Array[Vector3], in_m: float, out_m: float, reach := PackedFloat32Array()) -> Array:
	if not on_demand:
		return []
	var plan := BigZoneStreaming.plan(focus, reach, in_m, out_m, CELL_M, ceili(_terrain.size_m / CELL_M), _terrain.size_m * 0.5)
	var wanted: Dictionary = plan[0]
	var keep: Dictionary = plan[1]
	var half := _terrain.size_m * 0.5
	for c: Vector2i in _cover_bodies.keys():
		if not keep.has(c):
			if BigZoneStreaming.held(self, c, Rect2(-half + c.x * CELL_M, -half + c.y * CELL_M, CELL_M, CELL_M), _terrain):
				continue  # something lies by its cover (a body, an item, a wreck): it stays
			for body: Variant in _cover_bodies[c]:
				if body != null:
					(body as Node).queue_free()
			_cover_bodies.erase(c)
	var todo: Array = []
	for c: Vector2i in wanted:
		if _cells.has(c) and not _cover_bodies.has(c):
			todo.append(c)
	todo.sort_custom(func(x: Vector2i, y: Vector2i) -> bool: return float(wanted[x]) < float(wanted[y]))
	return todo


## Builds the cells of `todo` (stream_plan's) from its front as ZoneTerrain.build_chunks does.
func build_cells(todo: Array, until_usec := 0) -> int:
	var built := 0
	while not todo.is_empty():
		if until_usec > 0 and built > 0 and Time.get_ticks_usec() > until_usec:
			break
		var c: Vector2i = todo.pop_front()
		if _cover_bodies.has(c) or not _cells.has(c):
			continue
		_build_cover(c)
		built += 1
	return built


## How many cells have their cover collision built (on_demand: near the action; else all).
func cover_cells() -> int:
	return _cover_bodies.size()


## The shapes item `item` collides as, each [Shape3D, Transform3D (world)], exactly as it's drawn
## (_cell_parts): [] for one that doesn't collide (scrub, thickets, small rocks, valuables). A
## library prop's are [Shape3D, Transform3D, its part's index, see-through], one per solid part.
func collision_parts(item: Dictionary) -> Array:
	var s: Vector3 = item.size
	var p: Vector3 = item.pos
	if item.has("shape") and int(item.kind) == Kind.PROP:
		var out: Array = []
		var shape := String(item.shape)
		var place := Transform3D(Basis(Vector3.UP, float(item.yaw)), p)  # (the scale is in the shape's points)
		var list := PropArt.parts(shape)
		for i in list.size():
			var part: Dictionary = list[i]
			if not part.solid:
				continue
			out.append([_library_shape(shape, i, s), place, i, PropArt.material_of(shape, part) == PropArt.SEE_THROUGH])
		return out
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


## Library shapes' hulls by shape, part and scale, shared (a shape's parts never change).
static var _library_shapes := {}


static func _library_shape(shape: String, part: int, scale: Vector3) -> ConvexPolygonShape3D:
	var key := "%s|%d|%s" % [shape, part, scale.snapped(Vector3.ONE * 0.01)]
	if not _library_shapes.has(key):
		var hull := ConvexPolygonShape3D.new()
		var points := PackedVector3Array()
		for c: Vector3 in (PropArt.parts(shape)[part] as Dictionary).pts:
			points.append(c * scale)
		hull.points = points
		_library_shapes[key] = hull
	return _library_shapes[key]


## A library prop's transform from its own metres to the world: turned, scaled, on its spot.
static func library_transform(item: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, float(item.yaw)) * Basis.from_scale(item.size as Vector3), item.pos as Vector3)


## How a round meets a library prop's part (Ballistics, and the AI's soft-cover test through
## VoxelWorld.stops_round_in): `hit` is the ray's hit on a scatter body, the round going `direction`
## with `energy_j`. {} when it isn't a library prop (the caller goes on as before: a rock, a trunk,
## an old box prop stops it). Else {"stopped", "material", "lost_j", "exit"}: the part's material
## (PropArt.MATERIALS) takes its loss per metre over the round's path through the part; one that
## stops every round, or the round's energy runs out inside, stops it there.
static func round_through(hit: Dictionary, direction: Vector3, energy_j: float) -> Dictionary:
	var body := hit.get("collider") as StaticBody3D
	if body == null or not body.get_parent() is ZoneScatter:
		return {}
	var owner_id := body.shape_find_owner(int(hit.get("shape", 0)))
	var node := body.shape_owner_get_owner(owner_id) as Node
	if node == null or not node.has_meta(&"prop"):
		return {}
	var scatter := body.get_parent() as ZoneScatter
	var ids: Vector2i = node.get_meta(&"prop")
	var item: Dictionary = scatter.items[ids.x]
	var shape := String(item.shape)
	var part: Dictionary = PropArt.parts(shape)[ids.y]
	var material := PropArt.material_of(shape, part)
	var at: Vector3 = hit.position
	var out := {"stopped": true, "material": material, "lost_j": maxf(energy_j, 0.0), "exit": at}
	var per_m := PropArt.loss_per_m(material)
	if per_m == INF or energy_j <= 0.0:
		return out
	var xf := library_transform(item)
	var inv := xf.affine_inverse()
	var dir := direction.normalized()
	var span := PropArt.ray_span(part, inv * (at - dir * 0.05), inv.basis * dir)
	var exit := at
	if span.y > span.x:
		exit = xf * ((inv * (at - dir * 0.05)) + (inv.basis * dir) * span.y)
	var loss := per_m * maxf((exit - at).dot(dir), 0.0)
	if loss >= energy_j:
		return out
	return {"stopped": false, "material": material, "lost_j": loss, "exit": exit}


## What a helicopter must clear (Helicopter.obstacle_top): a pylon's or a mast's lattice is too
## thin for its rays to find, so it asks for the top (y) of every library prop at least TALL_M tall
## whose reach (the farthest corner of its drawn bounds from where it stands) comes within
## `radius` of `at` (x, z); -INF when none does.
const TALL_M := 6.0
const TALL_CELL_M := 32.0


func tall_top(at: Vector3, radius: float) -> float:
	if not _tall_built:
		_index_tall()
	var top := -INF
	if _tall.is_empty():
		return top
	var reach := radius + 16.0  # (the widest tall prop's reach: a pylon's cross arm)
	var lo := Vector2i(floori((at.x - reach) / TALL_CELL_M), floori((at.z - reach) / TALL_CELL_M))
	var hi := Vector2i(floori((at.x + reach) / TALL_CELL_M), floori((at.z + reach) / TALL_CELL_M))
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var row: PackedFloat32Array = _tall.get(Vector2i(cx, cz), PackedFloat32Array())
			for i in range(0, row.size(), 4):
				var r := radius + row[i + 2]
				if Vector2(at.x - row[i], at.z - row[i + 1]).length_squared() <= r * r:
					top = maxf(top, row[i + 3])
	return top


func _index_tall() -> void:
	_tall = {}
	_tall_built = true
	for item: Dictionary in items:
		if not item.has("shape") or int(item.kind) != Kind.PROP:
			continue
		var b: AABB = PropArt.shape(String(item.shape)).bounds
		var size: Vector3 = item.size
		if b.end.y * size.y < TALL_M:
			continue
		var p: Vector3 = item.pos
		var reach := PropArt.half_extents(String(item.shape)).length() * maxf(size.x, size.z)
		var cell := Vector2i(floori(p.x / TALL_CELL_M), floori(p.z / TALL_CELL_M))
		var row: PackedFloat32Array = _tall.get(cell, PackedFloat32Array())
		row.append_array(PackedFloat32Array([p.x, p.z, reach, p.y + b.end.y * size.y]))
		_tall[cell] = row


## The library props' solid parts near `area` (x, z in metres) as triangles, for the navigation
## mesh (ZoneNav): what stands on the ground (parts starting under NAV_TOP_M; a lamp's arm or a
## pylon's cross arms overhead don't block anyone), see-through fences too (they stop men).
const NAV_TOP_M := 2.0


func faces_in(area: Rect2) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _cells.is_empty():
		return out
	if _indexed != items.size():
		_index_fine()
	var reach := area.grow(14.0)  # (a prop standing just outside still reaches in: a 40 ft container)
	for row: PackedInt32Array in _fine_rows(_solids, reach):  # (by the fine index: its solids and library props)
		for index in row:
			var item: Dictionary = items[index]
			if not item.has("shape") or int(item.kind) != Kind.PROP:
				continue
			var p: Vector3 = item.pos
			var half := PropArt.half_extents(String(item.shape)).length()
			if not area.grow(half).has_point(Vector2(p.x, p.z)):
				continue
			var xf := library_transform(item)
			for part: Dictionary in PropArt.parts(String(item.shape)):
				if not part.solid:
					continue
				var low := INF
				for c: Vector3 in part.pts:
					low = minf(low, c.y)
				if low >= NAV_TOP_M:
					continue
				var centre := Vector3.ZERO
				for c: Vector3 in part.pts:
					centre += c / float((part.pts as PackedVector3Array).size())
				for poly: PackedVector3Array in PropArt.faces(part):
					var n := (poly[1] - poly[0]).cross(poly[2] - poly[0])
					var flip := n.dot((poly[0] + poly[2]) * 0.5 - centre) < 0.0
					for i in range(1, poly.size() - 1):
						var tri := [poly[0], poly[i + 1], poly[i]] if not flip else [poly[0], poly[i], poly[i + 1]]
						for v: Vector3 in tri:
							out.append(xf * v)
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
		_shapes.merge(_lod_meshes())
	var trunk_key := "trunk:" + trunk_hex
	if not _shapes.has(trunk_key):
		_shapes[trunk_key] = _trunk_mesh(Color(trunk_hex))
		_shapes["trunk_lod:" + trunk_hex] = _trunk_lod_mesh(Color(trunk_hex))
	var out := _shapes.duplicate()
	out["trunk"] = _shapes[trunk_key]
	out["trunk_lod"] = _shapes["trunk_lod:" + trunk_hex]
	return out


## Builds up to `budget` cells' visuals near `pos`, most needed first; returns how many it built.
## A cell's near tier is wanted within NEAR_BUILD_M (first where its full trees show, inside LOD_M
## and half a cell, then its ground cover's ring), its far tier within BUILD_M, and as long as its
## block's far blobs aren't showing (SEE_TREE_M from the block's middle: its trees are drawn till
## then), first past where the near tier hands over.
func build_near(pos: Vector3, budget: int) -> int:
	var done := 0
	for w: Array in _wanted_near(pos, budget):
		_build_cell(w[0], w[1])
		done += 1
	return done


## The `budget` most needed [cell, tier] builds near `pos` (build_near), most needed first.
func _wanted_near(pos: Vector3, budget: int) -> Array:
	if not _visuals_on:
		return []
	var wanted: Array = []
	var half := _terrain.size_m * 0.5
	var reach := CELL_M * 0.7072  # half a cell's diagonal
	var block_m := CELL_M * FAR_BLOCK
	var at := Vector2(pos.x, pos.z)
	for cell: Vector2i in (_cells_round(pos, BUILD_M + block_m) if on_demand else _cells.keys()):
		var centre := Vector2(-half + (cell.x + 0.5) * CELL_M, -half + (cell.y + 0.5) * CELL_M)
		var d := centre.distance_to(at)
		if d < NEAR_BUILD_M and not _built_near.has(cell):
			wanted.append([d if d < LOD_M + reach else d + LOD_M, cell, Tier.NEAR])
		if _built.has(cell):
			continue
		var block := Vector2i(floori(cell.x / float(FAR_BLOCK)), floori(cell.y / float(FAR_BLOCK)))
		var blobs_hidden := _far.has(block) and Vector2(-half + (block.x + 0.5) * block_m, -half + (block.y + 0.5) * block_m).distance_to(at) < SEE_TREE_M + LOD_MARGIN_M
		if d < BUILD_M or blobs_hidden:
			wanted.append([d if d > LOD_M - reach else BUILD_M, cell, Tier.FAR])
	wanted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return wanted.slice(0, budget).map(func(w: Array) -> Array: return [w[1], w[2]])


## An on_demand zone (8 km, BigZoneStreaming): the cells with items within `reach` m of `pos`'s
## square (not all 4,096 of the zone: _wanted_near runs every CHECK_S).
func _cells_round(pos: Vector3, reach: float) -> Array:
	var half := _terrain.size_m * 0.5
	var n := ceili(_terrain.size_m / CELL_M)
	var out: Array = []
	for cz in range(maxi(floori((pos.z - reach + half) / CELL_M), 0), mini(floori((pos.z + reach + half) / CELL_M), n - 1) + 1):
		for cx in range(maxi(floori((pos.x - reach + half) / CELL_M), 0), mini(floori((pos.x + reach + half) / CELL_M), n - 1) + 1):
			if _cells.has(Vector2i(cx, cz)):
				out.append(Vector2i(cx, cz))
	return out


## An on_demand zone's memory cap (D2, cg_brief queue item 3.1; Proposed): a cell's near tier is
## freed past NEAR_FREE_M from the camera and its far tier past FAR_FREE_M (its meshes and the
## kept parts), so what the scatter holds follows the camera, not every cell it ever passed. Built
## again on the way back as they were.
const NEAR_FREE_M := NEAR_BUILD_M + 200.0
const FAR_FREE_M := BUILD_M + 400.0
var _cell_nodes := {}  # Vector3i(cell.x, cell.y, tier) -> its nodes (on_demand)
## Tests and the invasion suite: cell tiers freed so far.
var freed_cells := 0


func _free_far_cells(pos: Vector3) -> void:
	var half := _terrain.size_m * 0.5
	var at := Vector2(pos.x, pos.z)
	var kept: Dictionary = _entry.get("visual", {})
	for key: Vector3i in _cell_nodes.keys():
		var d := Vector2(-half + (key.x + 0.5) * CELL_M, -half + (key.y + 0.5) * CELL_M).distance_to(at)
		if d <= (NEAR_FREE_M if key.z == Tier.NEAR else FAR_FREE_M):
			continue
		for node: Node in _cell_nodes[key]:
			if is_instance_valid(node):
				node.queue_free()
		_cell_nodes.erase(key)
		(_built_near if key.z == Tier.NEAR else _built).erase(Vector2i(key.x, key.y))
		kept.erase(key)
		freed_cells += 1


## How many cells have their far tier built (every cell within BUILD_M once the camera has been
## there); built_near_cells: their near tier.
func built_cells() -> int:
	return _built.size()


func built_near_cells() -> int:
	return _built_near.size()


## Perf pass (2026-10-22): the PER_FRAME builds a check wants ([cell, tier]) are made one a frame,
## not all in the check's frame (a cell is tens of milliseconds of main thread).
func _process(delta: float) -> void:
	if _cover_task >= 0:
		_take_cover()
	elif not _queued.is_empty():
		var w: Array = _queued.pop_front()
		if not (_built_near if int(w[1]) == Tier.NEAR else _built).has(w[0]):
			if int(w[1]) == Tier.NEAR and not (_entry.get("visual", {}) as Dictionary).has(Vector3i(w[0].x, w[0].y, Tier.NEAR)):
				_start_cover(w[0])
			else:
				_build_cell(w[0], w[1])
	_next_check -= delta
	if _next_check > 0.0:
		return
	_next_check = CHECK_S
	var camera := get_viewport().get_camera_3d()
	if camera and on_demand:
		_free_far_cells(camera.global_position)
	if camera and _queued.is_empty():
		_queued = _wanted_near(camera.global_position, PER_FRAME)


var _queued: Array = []  # [cell, tier] builds, one a frame (_process)
## World content pass (2026-10-23; F-225): a near tier's ground cover (a cell's ~1000 tufts and
## pebbles, each tested against the pads, roads, water and fields and set on the ground: 20-35 ms of
## GDScript, the scatter's whole near-tier cost) is laid out on a worker thread, one cell at a time;
## the cell is built here once it's done (_take_cover). build_near (tests, the first build round a
## spot) still builds in place.
var _cover_task := -1
var _cover_cell := Vector2i.ZERO
var _cover_out := {}


func _start_cover(cell: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	_cover_cell = cell
	_cover_out = {}
	_cover_task = WorkerThreadPool.add_task(_cover_on_worker.bind(cell, _pads_for(cell)), false, "scatter ground cover")
	FrameCost.spent(&"scatter_cells", t0)


func _cover_on_worker(cell: Vector2i, keep: Array[Rect2]) -> void:
	var groups := {}
	_ground_cover(cell, groups, keep)
	_cover_out = groups


func _take_cover() -> void:
	if not WorkerThreadPool.is_task_completed(_cover_task):
		return
	WorkerThreadPool.wait_for_task_completion(_cover_task)
	_cover_task = -1
	if not _built_near.has(_cover_cell):
		_build_cell(_cover_cell, Tier.NEAR, _cover_out)
	_cover_out = {}


func _exit_tree() -> void:
	if _cover_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_cover_task)
		_cover_task = -1
	if on_demand:
		forget()


## Builds cell `cell`'s `tier` (Tier): its MultiMeshes (from the cache entry when this zone built
## them before), each drawn over its tier's range: the near tier's full shapes out to LOD_M and its
## ground cover to their own ranges; the far tier's stand-ins from LOD_M out to their full shapes'
## ranges (the trees and thickets till their block's far blobs take over, _far_parent), and the
## rocks and props over theirs. Each node has its "centre" (the cell's middle) as a meta, for tests.
## Ranges are scaled by the Detail setting (_range_of, GameSettings.detail).
func _build_cell(cell: Vector2i, tier := Tier.FAR, cover: Variant = null) -> void:
	var t0 := Time.get_ticks_usec()
	if tier == Tier.NEAR:
		_built_near[cell] = true
	else:
		_built[cell] = true
	var kept: Dictionary = _entry.get("visual", {})
	var at := Vector3i(cell.x, cell.y, tier)
	var parts: Array = kept.get(at, [])
	if not kept.has(at):
		parts = _cell_parts(cell, tier, cover)
		if _entry.has("visual"):
			kept[at] = parts  # built once, kept while this zone is among the newest (CACHE_VISUAL_ZONES)
	var half := _terrain.size_m * 0.5
	var centre := Vector3(-half + (cell.x + 0.5) * CELL_M, 0.0, -half + (cell.y + 0.5) * CELL_M)
	centre.y = _terrain.height_at(clampf(centre.x, -half, half), clampf(centre.z, -half, half))
	var lod_keys := LOD_KEYS.values()
	for part: Array in parts:
		var key: Variant = part[0]
		var node := MultiMeshInstance3D.new()
		node.name = "Scatter_%d_%d_%s" % [cell.x, cell.y, str(key)]
		node.set_meta(&"centre", centre)
		node.multimesh = part[1]
		node.material_override = _material
		if tier == Tier.NEAR and LOD_KEYS.has(key):
			node.visibility_range_end = LOD_M
			node.visibility_range_end_margin = LOD_MARGIN_M
		elif key is String and key in lod_keys:
			node.visibility_range_begin = LOD_M
			node.visibility_range_begin_margin = LOD_MARGIN_M
			var full: Variant = LOD_KEYS.find_key(key)
			var parent := _far_parent(cell) if full is String else ""  # (scrub ends at SEE_SCRUB_M, well inside the blobs)
			if parent.is_empty():
				node.visibility_range_end = _range_of(full)
				node.visibility_range_end_margin = 20.0
			else:
				node.visibility_parent = NodePath("../" + parent)
		else:
			node.visibility_range_end = _range_of(key)
			node.visibility_range_end_margin = 20.0
		# No sun shadow from the far tier's trunks either (woods perf pass, 2026-10-31): past LOD_M a
		# 0.3 m post is under a pixel and so is its shadow in the sun's far cascade, but it was a shadow
		# draw a cell inside the shadow reach. The crowns' stand-ins keep theirs (their shade reads).
		var shade: bool = not ((key is int and key == Kind.SCRUB) or (key is String and key in ["tuft", "pebble", "thicket", "wire", "thicket_lod", "scrub_lod", "trunk_lod"]))  # keys mix Kind values and names
		if key is String and String(key).begins_with(LIBRARY):
			shade = bool(PropArt.shape(String(key).trim_prefix(LIBRARY).get_slice("#", 0)).shadow)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shade else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		if on_demand:
			(_cell_nodes.get_or_add(at, []) as Array).append(node)
	FrameCost.spent(&"scatter_cells", t0)


## The name of the far blobs' node for cell `cell`'s block ("" when its block has no trees).
func _far_parent(cell: Vector2i) -> String:
	var block := Vector2i(floori(cell.x / float(FAR_BLOCK)), floori(cell.y / float(FAR_BLOCK)))
	return "Far_%d_%d" % [block.x, block.y] if _far.has(block) else ""


## Draw distance by group key: _RANGES, a library prop's shape's own (PropArt), its wires SEE_WIRE_M,
## times the Detail setting's share (GameSettings.detail "scatter": 1 at High and Ultra).
static func _range_of(key: Variant) -> float:
	return _base_range_of(key) * float(GameSettings.detail().scatter)


static func _base_range_of(key: Variant) -> float:
	if key is String and String(key).begins_with(LIBRARY):
		return PropArt.see_m(String(key).trim_prefix(LIBRARY).get_slice("#", 0))
	if key is String and key == "wire":
		return SEE_WIRE_M
	return float(_RANGES[key])


## A library prop's group key: LIBRARY + "<shape>#<paint>" (one mesh each, PropArt.mesh).
const LIBRARY := "lib:"
## Power and phone lines are drawn out to this far (m), WIRE_W thick, sagging WIRE_SAG of their
## span in the middle, in WIRE_SEGMENTS straight pieces. Proposed.
const SEE_WIRE_M := 700.0
const WIRE_W := 0.03
const WIRE_SAG := 0.03
const WIRE_SEGMENTS := 6
const _RANGES := {Kind.ROCK: SEE_ROCK_M, Kind.SCRUB: SEE_SCRUB_M, "thicket": SEE_TREE_M, "trunk": SEE_TREE_M, "crown": SEE_TREE_M,
	"conifer": SEE_TREE_M, "tuft": SEE_TUFT_M, "pebble": SEE_PEBBLE_M, "outcrop": SEE_OUTCROP_M,
	"prop_crates": SEE_ROCK_M, "prop_drums": SEE_ROCK_M, "prop_debris": SEE_ROCK_M, "prop_wall": SEE_ROCK_M, "prop_wreck": SEE_ROCK_M, "prop_mound": SEE_ROCK_M}


## Cell `cell`'s MultiMeshes for `tier` (Tier): [[group key, MultiMesh], ...]. The near tier: the
## trees, thickets and scrub as visual_parts draws them, and the ground cover; the far tier: their
## low-poly stand-ins (LOD_KEYS, at the same transforms), the rocks, props and wires.
func _cell_parts(cell: Vector2i, tier := Tier.FAR, cover: Variant = null) -> Array:
	var groups := {}
	for index: int in _cells[cell]:
		for part: Array in visual_parts(items[index]):
			var key: Variant = part[0]
			if LOD_KEYS.has(key):
				if tier == Tier.FAR:
					key = LOD_KEYS[key]
			elif tier == Tier.NEAR:
				continue
			if not groups.has(key):
				groups[key] = []
			groups[key].append([part[1], part[2]])
		if tier == Tier.FAR and int(items[index].get("link", 0)) == 1 and index > 0:
			if not groups.has("wire"):
				groups["wire"] = []
			_wires(items[index - 1], items[index], groups["wire"])
	if tier == Tier.NEAR:
		if cover is Dictionary:
			groups.merge(cover)  # (laid out on a worker: _start_cover)
		else:
			_ground_cover(cell, groups, _pads_for(cell))
	var parts: Array = []
	for key in groups:
		var list: Array = groups[key]
		if list.is_empty():
			continue
		var mesh: Mesh = _meshes.get(key)
		if mesh == null and key is String and String(key).begins_with(LIBRARY):
			var name_paint := String(key).trim_prefix(LIBRARY)
			mesh = PropArt.mesh(name_paint.get_slice("#", 0), int(name_paint.get_slice("#", 1)))
		elif mesh == null and key is String and key == "wire":
			mesh = _wire_mesh()
		parts.append([key, _multimesh(mesh, list)])
	return parts


## The wires from library prop `a` to `b` (the next pole or pylon along its line): one from each of
## a's hanging points (PropArt wire_points) to b's same, sagging in the middle, as WIRE_SEGMENTS
## thin bars, into `list` ([transform, colour]).
func _wires(a: Dictionary, b: Dictionary, list: Array) -> void:
	if not a.has("shape") or not b.has("shape"):
		return
	var from := PropArt.wire_points(String(a.shape))
	var to := PropArt.wire_points(String(b.shape))
	var xa := library_transform(a)
	var xb := library_transform(b)
	for i in mini(from.size(), to.size()):
		var p0 := xa * from[i]
		var p1 := xb * to[i]
		var sag := p0.distance_to(p1) * WIRE_SAG
		var prev := p0
		for k in range(1, WIRE_SEGMENTS + 1):
			var t := float(k) / WIRE_SEGMENTS
			var q := p0.lerp(p1, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
			var along := q - prev
			var x := along.cross(Vector3.UP).normalized()
			if x == Vector3.ZERO:
				x = Vector3.RIGHT
			var y := x.cross(along).normalized()
			list.append([Transform3D(Basis(x * WIRE_W, y * WIRE_W, along), prev), Color("26272a")])
			prev = q


## A wire piece: a unit bar from z 0 to 1, 1 across (scaled to WIRE_W and its length).
func _wire_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array[Vector3] = []
	for c: Vector3 in _blocky_corners(Vector3.ONE, 0.0, 0, true):
		corners.append(c + Vector3(0, 0, 0.5))
	_add_box(st, corners, Color.WHITE)
	return st.commit()


## How item `item` is drawn: [group key (its mesh in _shared_meshes), Transform3D (world), colour]
## for each of its meshes. Rocks and props are scaled along their own axes, then turned (they were
## scaled after turning, which sheared a turned one off its collision box), and a prop sinks into
## a slope (_sink), a rock too, all as they collide (collision_parts).
func visual_parts(item: Dictionary) -> Array:
	var basis := Basis(Vector3.UP, float(item.yaw))
	var size: Vector3 = item.size
	var p: Vector3 = item.pos
	var xf := Transform3D(basis.scaled(size), p)  # (x and z the same for these: turned, not sheared)
	if item.has("shape"):
		if int(item.kind) != Kind.PROP:
			return []  # an ANIMAL marker (ZoneAnimals draws them)
		return [[LIBRARY + "%s#%d" % [item.shape, int(item.get("paint", 0))], library_transform(item), item.colour]]
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
## their middle, as wide as they spread, as tall as their crowns), one MultiMesh per block of
## FAR_BLOCK x FAR_BLOCK cells, seen from just inside SEE_TREE_M of the block's middle out to the
## horizon, no shadows; each block is the visibility parent of its cells' far-tier trees and
## thickets (_build_cell). Kept in the zone's cache entry.
func _build_far() -> void:
	var kept: Dictionary = _entry.get("far", {})
	if kept.is_empty():
		kept = _far_parts()
		if _entry.has("far"):
			_entry.far = kept
	_far = kept
	var half := _terrain.size_m * 0.5
	var block_m := CELL_M * FAR_BLOCK
	for block: Vector2i in kept:
		var node := MultiMeshInstance3D.new()
		node.name = "Far_%d_%d" % [block.x, block.y]
		var centre := Vector3(-half + (block.x + 0.5) * block_m, 0.0, -half + (block.y + 0.5) * block_m)
		node.set_meta(&"centre", centre)
		node.multimesh = kept[block]
		node.material_override = _material
		node.visibility_range_begin = SEE_TREE_M * float(GameSettings.detail().scatter) - 10.0  # (where the trees stop, by the detail setting)
		node.visibility_range_begin_margin = 20.0
		var far_m := float(GameSettings.detail().far_trees_m)  # the detail setting (perf pass; "ultra": to the horizon)
		if far_m > 0.0:
			node.visibility_range_end = far_m
			node.visibility_range_end_margin = GameSettings.FAR_FADE_M
			node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)


## block (FAR_BLOCK cells a side) -> MultiMesh of its far blobs (one per FAR_GROUP_M square of a
## cell holding trees).
func _far_parts() -> Dictionary:
	var out := {}
	var lists := {}  # block -> [transform, colour] of its blobs
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
		var block := Vector2i(floori(cell.x / float(FAR_BLOCK)), floori(cell.y / float(FAR_BLOCK)))
		if not lists.has(block):
			lists[block] = []
		var list: Array = lists[block]
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
	for block: Vector2i in lists:
		out[block] = _multimesh(_meshes.get("far", _far_mesh()), lists[block])
	return out


## How many far stand-ins are built: {"cells": MultiMeshes (one a block of cells), "blobs":
## instances}, for tests.
func far_counts() -> Dictionary:
	var blobs := 0
	for block: Vector2i in _far:
		blobs += (_far[block] as MultiMesh).instance_count
	return {"cells": _far.size(), "blobs": blobs}


## A far canopy blob: a low, wide rounded mass from 1.2 to 4.9 x the crowns' size up, radius 1
## (scaled to the trees' spread).
func _far_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t: Array in [[1.2, 2.4, 0.75, 1.0, BOTTOM], [2.4, 3.9, 1.0, 0.85, 0], [3.9, 4.9, 0.85, 0.35, TOP]]:
		_tier(st, 0.0, 0.0, t[0], t[1], t[2], t[3], Color.WHITE, t[4])  # (the caps between tiers are inside: none)
	return st.commit()


## Grass tufts and pebbles for `cell` (visual only, see SEE_TUFT_M): from the cell and the seed,
## thicker where the scrub clusters, none on pads, roads, water or steep ground.
func _ground_cover(cell: Vector2i, groups: Dictionary, keep: Array[Rect2]) -> void:
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
		if _cover_blocked(x, z, keep):
			continue
		var h := _terrain.plane_height(x, z)
		if _terrain.sea_side >= 0 and h < _terrain.sea_level + 0.5:
			continue
		var nrm := _terrain.plane_normal(x, z)
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
		if absf(cx) > half - EDGE_KEEP_M or absf(cz) > half - EDGE_KEEP_M or _cover_blocked(cx, cz, keep):
			continue
		if open and _open_weight(cx, cz) < 0.5:
			continue  # rubble at the margins and round the compounds, not on the open pan
		var ch := _terrain.plane_height(cx, cz)
		if (_terrain.sea_side >= 0 and ch < _terrain.sea_level + 0.5) or _terrain.plane_normal(cx, cz).y < 0.6:
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
			var h := _terrain.plane_height(x, z)
			groups["outcrop"].append([Transform3D(basis.scaled(Vector3(size, size * squash, size * rng.randf_range(0.8, 1.3))), Vector3(x, h + size * squash * 0.2, z)),
				base.darkened(rng.randf() * 0.12).lightened(rng.randf() * 0.08)])


## Whether ground cover keeps off (x, z): a pad or the line of a road.
## Perf pass (2026-10-22): the pads and roads are narrowed to those reaching (x, z)'s cell, once
## per cell (_pads_for): every tuft and pebble of a cell tested every road in the zone.
func _ground_blocked(x: float, z: float) -> bool:
	var cell := _cell_of(x, z)
	if cell != _gb_cell:
		_gb_cell = cell
		_gb_keep = _pads_for(cell)
	return _cover_blocked(x, z, _gb_keep)


## _ground_blocked with the pads reaching the point's cell given (_pads_for): no shared state, so
## a worker thread can lay ground cover with it (_start_cover). Reads only the generated layout.
func _cover_blocked(x: float, z: float, keep: Array[Rect2]) -> bool:
	if _terrain.water and _terrain.water.keeps_clear(x, z):
		return true  # a river, lake or bridge (ZoneWater)
	if _terrain.features and _terrain.features.keeps_clear(x, z):
		return true  # a field (ZoneFeatures)
	var p := Vector2(x, z)
	for r in keep:
		if r.has_point(p):
			return true
	for road: Array in _roads_near(p, 4.0):
		var a := Vector2(float(road[0][0]), float(road[0][1]))
		var b := Vector2(float(road[1][0]), float(road[1][1]))
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < 4.0:
			return true
	return false


var _gb_cell := Vector2i(1 << 30, 1 << 30)
var _gb_keep: Array[Rect2] = []


## The pads (shrunk as ground cover keeps off them) reaching `cell` (perf pass 2026-10-22: every
## tuft and pebble of a cell tested every pad of the zone; the roads go by _roads_near's index).
func _pads_for(cell: Vector2i) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var half := _terrain.size_m * 0.5
	var box := Rect2(Vector2(-half + cell.x * CELL_M, -half + cell.y * CELL_M), Vector2(CELL_M, CELL_M)).grow(8.0)
	for r in _keep:
		var g := r.grow(-PAD_KEEP_M + 2.0)
		if g.intersects(box):
			out.append(g)
	return out


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
	if item.has("shape"):
		return String(item.shape)
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


## _tier's `caps`: its flat bottom, its flat top (both by default). The woods perf pass leaves out
## the caps nobody can see: those inside the tier above or below, on or under the ground, inside
## the crown (a crown 224 -> 164 triangles, scrub 224 -> 152, a trunk 28 -> 16; the look unchanged).
const BOTTOM := 1
const TOP := 2


## One tier: an octagonal frustum from y0 (half-width r0) to y1 (r1), centred on (cx, cz),
## with flat top and bottom (`caps`); with `sides` 4, a square one (the far tier's trunks).
func _tier(st: SurfaceTool, cx: float, cz: float, y0: float, y1: float, r0: float, r1: float, tint := Color.WHITE, caps := BOTTOM | TOP, sides := 8) -> void:
	var ring := func(y: float, r: float) -> Array[Vector3]:
		var out: Array[Vector3] = []
		var c := r * 0.7  # the 45-degree cut leaves 0.7 of each side (VoxelArt bevel 0.3)
		var corners: Array[Vector2] = [Vector2(c, -r), Vector2(r, -c), Vector2(r, c), Vector2(c, r), Vector2(-c, r), Vector2(-r, c), Vector2(-r, -c), Vector2(-c, -r)]
		if sides == 4:
			corners = [Vector2(r, -r), Vector2(r, r), Vector2(-r, r), Vector2(-r, -r)]
		for v: Vector2 in corners:
			out.append(Vector3(cx + v.x, y, cz + v.y))
		return out
	var lo: Array[Vector3] = ring.call(y0, r0)
	var hi: Array[Vector3] = ring.call(y1, r1)
	var mid := Vector3(cx, (y0 + y1) * 0.5, cz)
	for i in sides:
		var j := (i + 1) % sides
		_face(st, [lo[i], lo[j], hi[j], hi[i]], mid, tint * SIDE_SHADE)
	for i in range(1, sides - 1):
		if caps & TOP:
			_face(st, [hi[0], hi[i], hi[i + 1]], mid, tint * TOP_SHADE)
		if caps & BOTTOM:
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
		_tier(st, c[0], c[1], 0.0, h * 0.7, r * 0.75, r, Color.WHITE, 0)  # (its foot on the ground, its top inside the tier above)
		_tier(st, c[0], c[1], h * 0.7, h, r, r * 0.55, Color.WHITE, TOP)
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
	for t: Array in [[2.0, 2.55, 0.65, 1.05, BOTTOM], [2.55, 3.45, 1.05, 1.1, 0], [3.45, 4.3, 1.1, 0.85, 0], [4.3, 4.9, 0.85, 0.35, TOP]]:
		_tier(st, 0.0, 0.0, t[0], t[1], t[2], t[3], Color.WHITE, t[4])
	# Two lobes out to the sides break the outline (within CROWN_R of the middle, about).
	_tier(st, 0.72, 0.18, 2.55, 3.15, 0.45, 0.6, Color.WHITE, BOTTOM)
	_tier(st, 0.72, 0.18, 3.15, 3.75, 0.6, 0.3, Color.WHITE, TOP)
	_tier(st, -0.45, -0.62, 3.25, 3.85, 0.42, 0.55, Color.WHITE, BOTTOM)
	_tier(st, -0.45, -0.62, 3.85, 4.4, 0.55, 0.25, Color.WHITE, TOP)
	return st.commit()


## A conifer: three stacked tiers, each narrower, from 2 m up to 4.9 m. (Each top is inside the
## tier above, and the last comes to a point: bottoms only.)
func _conifer_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t: Array in [[2.0, 3.0, 1.15, 0.7], [2.8, 3.9, 0.9, 0.45], [3.7, 4.9, 0.6, 0.06]]:
		_tier(st, 0.0, 0.0, t[0], t[1], t[2], t[3], Color.WHITE, BOTTOM)
	return st.commit()


## The trunk: an octagonal post, a little narrower at the top, 2.6 m tall (into the crown; its
## foot sunk TRUNK_SINK into the ground: no caps).
func _trunk_mesh(colour: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tier(st, 0.0, 0.0, 0.0, TRUNK_TALL, TRUNK_FOOT_R, TRUNK_TOP_R, colour / SIDE_SHADE, 0)
	return st.commit()


## The far tier's low-poly stand-ins (LOD_KEYS), each in its full shape's space (the same
## transforms) and shades: a broadleaf crown two tiers (44 triangles), a conifer two (44), a
## thicket or bush one clump (38); indexed.
func _lod_meshes() -> Dictionary:
	var out := {}
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tier(st, 0.0, 0.0, 2.0, 3.3, 0.75, 1.12, Color.WHITE, BOTTOM)
	_tier(st, 0.0, 0.0, 3.3, 4.9, 1.12, 0.42, Color.WHITE, TOP)
	st.index()
	out["crown_lod"] = st.commit()
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tier(st, 0.0, 0.0, 2.0, 3.35, 1.15, 0.6, Color.WHITE, BOTTOM)
	_tier(st, 0.0, 0.0, 3.1, 4.9, 0.8, 0.06, Color.WHITE, BOTTOM)
	st.index()
	out["conifer_lod"] = st.commit()
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tier(st, 0.0, 0.0, 0.0, 0.41, 0.38, 0.49, Color.WHITE, 0)
	_tier(st, 0.0, 0.0, 0.41, 0.58, 0.49, 0.27, Color.WHITE, TOP)
	st.index()
	out["thicket_lod"] = st.commit()
	out["scrub_lod"] = out["thicket_lod"]
	return out


## The far tier's trunk: a square post (8 triangles), as wide as the octagon's middle.
func _trunk_lod_mesh(colour: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tier(st, 0.0, 0.0, 0.0, TRUNK_TALL, TRUNK_FOOT_R * 0.85, TRUNK_TOP_R * 0.85, colour / SIDE_SHADE, 0, 4)
	st.index()
	return st.commit()
