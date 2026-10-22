class_name MapRender
extends RefCounted
## The picture under the map grid: a generated top-down image of a level's map_area().
##
## A level can draw its own (`map_image() -> Image`, covering map_area() north up, for a
## world-scale zone with terrain), add flat features on top of the generated one
## (`map_features() -> Array` of {"rect": Rect2 in metres (x, z), "colour": Color}, roads or
## fields), or leave it all to this: ground colour, then every voxel structure (VoxelWorld)
## seen from above in its material's colour, taller parts lighter, so walls, roofs and cover
## read as on an Arma map. Pixel (0, 0) is the area's north-west corner (smallest x and z).
##
## Art hook: this is the one place the map's look is made; Noah's art can replace render().

## Proposed: plain ground, a little darker than the level's ground so structures stand out.
const GROUND := Color("5d5b48")
## Biggest image side, and the most detail (pixels per metre: 8 is one pixel per 12.5 cm).
const MAX_PX := 1024
const MAX_PX_PER_M := 8.0
## Structures up to this height (m) shade from dark (low cover) to light (roofs).
const SHADE_HEIGHT_M := 4.0


## The map picture for `level` (anything with map_area()).
static func render(level: Node, max_px := MAX_PX) -> Image:
	if level.has_method(&"map_image"):
		var custom: Variant = level.call(&"map_image")
		if custom is Image and not (custom as Image).is_empty():
			return custom
	if is_zone(level):
		return compose_zone(zone_inputs(level, max_px))
	var area: Rect2 = level.call(&"map_area")
	var scale := px_per_m(area, max_px)
	var size := Vector2i(maxi(1, ceili(area.size.x * scale)), maxi(1, ceili(area.size.y * scale)))
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(GROUND)
	if level.has_method(&"map_features"):
		for feature: Dictionary in level.call(&"map_features"):
			if feature.get("rect") is Rect2:
				_fill(image, area, scale, feature.rect, feature.get("colour", GROUND.lightened(0.2)))
	for world: VoxelWorld in _voxel_worlds(level):
		_draw_structures(image, area, scale, world)
	return image


## Pixels per metre the generated image uses for `area`.
static func px_per_m(area: Rect2, max_px := MAX_PX) -> float:
	return minf(MAX_PX_PER_M, float(max_px) / maxf(maxf(area.size.x, area.size.y), 1.0))


static func _voxel_worlds(level: Node) -> Array[VoxelWorld]:
	var found: Array[VoxelWorld] = []
	var direct: Variant = level.get(&"voxel_world")
	if direct is VoxelWorld:
		found.append(direct)
		return found
	for node in level.find_children("*", "", true, false):
		if node is VoxelWorld:
			found.append(node)
	return found


## Every base structure box from above, lowest first so roofs cover what's under them.
static func _draw_structures(image: Image, area: Rect2, scale: float, world: VoxelWorld) -> void:
	var boxes := world.structure_boxes_m()
	var raw: Variant = world.get(&"_structures")  # [begin, end, mat] in the same order, for colours
	var entries: Array = []
	for i in boxes.size():
		var mat := VoxelWorld.Mat.CONCRETE as int
		if raw is Array and i < (raw as Array).size():
			mat = int((raw as Array)[i][2])
		entries.append([world.global_transform * boxes[i], mat])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as AABB).end.y < (b[0] as AABB).end.y)
	for entry: Array in entries:
		var box: AABB = entry[0]
		var colour: Color = VoxelWorld.PALETTE[entry[1]] if entry[1] > 0 and entry[1] < VoxelWorld.PALETTE.size() else Color.GRAY
		var lift := clampf(box.end.y / SHADE_HEIGHT_M, 0.0, 1.0)
		colour = colour.darkened(0.35 * (1.0 - lift)).lightened(0.15 * lift)
		colour.a = 1.0
		_fill(image, area, scale, Rect2(box.position.x, box.position.z, box.size.x, box.size.z), colour)


## Fills a ground rectangle (metres, x and z) on the image, at least one pixel wide.
static func _fill(image: Image, area: Rect2, scale: float, rect: Rect2, colour: Color) -> void:
	var a := ((rect.position - area.position) * scale).floor()
	var b := ((rect.end - area.position) * scale).ceil()
	var r := Rect2i(Vector2i(a), Vector2i((b - a).max(Vector2.ONE)))
	r = r.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if r.size.x > 0 and r.size.y > 0:
		image.fill_rect(r, colour)


# --- Zones: terrain, sea, woods, roads and buildings -------------------------------------------
# Captain, 2026-10-14 (B0912): the briefing's map of a zone was a flat gray-green square with
# only the grid on it. A zone's map now shows what the level knows, in a clean topographic style
# like Arma 3's map (the Captain's pick): pale land with a light hillshade (from the north-west)
# and brown contour lines from its heights, the sea in blue, woods (the scatter's trees) in light
# green, roads with a dark casing, and buildings and walls as dark footprints on their pads. No
# legend, nothing painterly. Made once per level: the
# level's data is gathered on the main thread (zone_inputs) and the picture composed from that
# alone (compose_zone), so MapView can do the slow part on a worker thread and cache it.

## Most pixels per side of a zone's picture (its ground is sampled per pixel): about 2.4 m a
## pixel on a 1.5 km zone. Proposed.
const ZONE_MAX_PX := 640
## Hillshade: how much the relief is exaggerated, and how strong the light and shadow are
## (subtle: it only hints at the ground's shape; the contours carry it).
const RELIEF_EXAGGERATION := 2.0
const SHADE_STRENGTH := 0.55
## The topographic palette. Proposed.
const LAND_LOW := Color("dedac6")
const LAND_HIGH := Color("d3ccb2")
const BEACH := Color("e8dfbf")
const RIVERBED := Color("d9cfae")
const WATER_SHALLOW := Color("a9cbdc")
const WATER_DEEP := Color("7eabc4")
const WOODS := Color("b4c99a")
const CONTOUR := Color("a8865c")
const PAD := Color("ccc6b4")
const ROAD := Color("f2efe6")
const ROAD_CASING := Color("6d6355")
const STREET := Color("e8e3d6")
const BUILDING := Color("5a5852")
## Trees from above: a crown about this wide (m).
const TREE_CROWN_M := 5.0
## Contour lines: how strongly they're drawn (every fifth, the index line, more).
const CONTOUR_ALPHA := 0.38
const INDEX_ALPHA := 0.7


## Whether `level` is a zone with terrain (a ZoneLevel or anything like it).
static func is_zone(level: Node) -> bool:
	return level != null and level.get(&"terrain") is ZoneTerrain


## The contour interval (m) for a height range: at most about 14 lines over the range.
static func contour_interval(range_m: float) -> float:
	for step: float in [1.0, 2.0, 5.0, 10.0, 20.0, 50.0]:
		if range_m / step <= 14.0:
			return step
	return 100.0


## Everything compose_zone needs from a zone level, copied out so it can run on any thread.
static func zone_inputs(level: Node, max_px := MAX_PX) -> Dictionary:
	var t: ZoneTerrain = level.get(&"terrain")
	var area: Rect2 = level.call(&"map_area")
	var side := mini(mini(max_px, ZONE_MAX_PX), maxi(t.points * 2, 2))
	var trees := PackedVector2Array()
	var scatter: Variant = level.get(&"scatter")
	if scatter is ZoneScatter:
		for item: Dictionary in (scatter as ZoneScatter).items:
			if int(item.kind) == ZoneScatter.Kind.TREE:
				var p: Vector3 = item.pos
				trees.append(Vector2(p.x, p.z))
	var pads: Array[Rect2] = []
	var boxes: Array = []  # [AABB (world), mat, top above the module's ground (m)]
	if level.has_method(&"modules"):
		for module: ZoneModule in level.call(&"modules"):
			pads.append(module.footprint())
			var parts: Variant = module.get(&"_proxy_parts")
			if parts is Array:
				for part: Array in parts:
					var box: AABB = part[0]
					boxes.append([AABB(box.position + module.position, box.size), int(part[1]), box.end.y])
	var roads: Array = []
	var def: Variant = level.get(&"def")
	if def is Dictionary:
		for road: Array in (def as Dictionary).get("roads", []):
			roads.append([Vector2(float(road[0][0]), float(road[0][1])), Vector2(float(road[1][0]), float(road[1][1]))])
	var streets: Array[Rect2] = []
	var raw_streets: Variant = t.get(&"_streets")
	if raw_streets is Array:
		streets.assign(raw_streets)
	var bed: Variant = t.get(&"_bed")
	var water: PackedFloat32Array = t.water.surface_grid() if t.water else PackedFloat32Array()
	return {
		"area": area, "side": side, "heights": t.heights, "points": t.points, "cell": ZoneTerrain.CELL_M, "half": t.size_m * 0.5,
		"min_h": t.min_height, "max_h": t.max_height, "bed": bed if bed is PackedByteArray else PackedByteArray(),
		"sand_below": t.sand_below_m,
		"sea_side": t.sea_side, "sea_rect": t.sea_rect(), "sea_level": t.sea_level, "sea_depth": maxf(t.sea_depth, 1.0),
		"trees": trees, "pads": pads, "boxes": boxes, "roads": roads, "streets": streets, "water": water,
	}


## What MapView paints around the map: the ground past the zone's edge, and the sea past a
## coast's edge ("sea_side" as ZoneTerrain's, -1 for none). {} for a level that isn't a zone.
static func surround(level: Node) -> Dictionary:
	if not is_zone(level):
		return {}
	var t: ZoneTerrain = level.get(&"terrain")
	return {"ground": LAND_HIGH.darkened(0.55), "sea_side": t.sea_side, "sea": WATER_DEEP.darkened(0.5)}


## The zone's picture from zone_inputs (pure: safe on a worker thread).
static func compose_zone(inp: Dictionary) -> Image:
	var area: Rect2 = inp.area
	var side: int = inp.side
	var heights: PackedFloat32Array = inp.heights
	var n: int = inp.points
	var cell: float = inp.cell
	var half: float = inp.half
	var px_m := area.size.x / side  # metres a pixel
	# 1. The ground's height at every pixel centre (bilinear on the terrain grid).
	var hs := PackedFloat32Array()
	hs.resize(side * side)
	var bed: PackedByteArray = inp.bed
	var has_bed := bed.size() == heights.size() and n >= 2
	var bed_w := PackedFloat32Array()
	if has_bed:
		bed_w.resize(side * side)
	for pz in side:
		var gz := clampf((area.position.y + (pz + 0.5) * px_m + half) / cell, 0.0, n - 1.001)
		var j := int(gz)
		var fz := gz - j
		for px in side:
			var gx := clampf((area.position.x + (px + 0.5) * px_m + half) / cell, 0.0, n - 1.001)
			var i := int(gx)
			var fx := gx - i
			var k := i + j * n
			hs[px + pz * side] = lerpf(lerpf(heights[k], heights[k + 1], fx), lerpf(heights[k + n], heights[k + n + 1], fx), fz)
			if has_bed:
				bed_w[px + pz * side] = float(bed[roundi(gx) + roundi(gz) * n]) / 255.0
	# 2. Colour, hillshade, sea and contours.
	var min_h: float = inp.min_h
	var range_h := maxf(float(inp.max_h) - min_h, 0.01)
	var interval := contour_interval(range_h)
	var light := Vector3(-1.0, 1.3, -1.0).normalized()
	var sand_below: float = inp.sand_below
	var sea_side: int = inp.sea_side
	var sea_rect: Rect2 = inp.sea_rect
	var beach_rect := sea_rect.grow(60.0)
	var sea_level: float = inp.sea_level
	var sea_depth: float = inp.sea_depth
	var water: PackedFloat32Array = inp.get("water", PackedFloat32Array())  # rivers and lakes (ZoneWater.surface_grid)
	var has_water := water.size() == heights.size() and n >= 2
	var data := PackedByteArray()
	data.resize(side * side * 4)
	for pz in side:
		var z := area.position.y + (pz + 0.5) * px_m
		var row := pz * side
		var up := maxi(pz - 1, 0) * side
		var down := mini(pz + 1, side - 1) * side
		for px in side:
			var x := area.position.x + (px + 0.5) * px_m
			var k := px + row
			var h := hs[k]
			var colour: Color
			var surface := -INF
			if has_water:
				surface = water[clampi(roundi((x + half) / cell), 0, n - 1) + clampi(roundi((z + half) / cell), 0, n - 1) * n]
			if sea_side >= 0 and h < sea_level and sea_rect.has_point(Vector2(x, z)):
				colour = WATER_SHALLOW.lerp(WATER_DEEP, clampf((sea_level - h) / sea_depth, 0.0, 1.0))
			elif h < surface:
				colour = WATER_SHALLOW.lerp(WATER_DEEP, clampf((surface - h) / 3.0, 0.0, 1.0))
			else:
				var east_h := hs[mini(px + 1, side - 1) + row]
				var south_h := hs[px + down]
				var dx := (east_h - hs[maxi(px - 1, 0) + row]) * RELIEF_EXAGGERATION
				var dz := (south_h - hs[px + up]) * RELIEF_EXAGGERATION
				var nrm := Vector3(-dx, 2.0 * px_m, -dz).normalized()
				colour = LAND_LOW.lerp(LAND_HIGH, clampf((h - min_h) / range_h, 0.0, 1.0))
				if has_bed:
					colour = colour.lerp(RIVERBED, clampf(bed_w[k] * 1.6 - 0.3, 0.0, 0.8))
				if sea_side >= 0 and sand_below > -100.0 and beach_rect.has_point(Vector2(x, z)):
					colour = colour.lerp(BEACH, smoothstep(sea_level + sand_below, sea_level, h))
				var lit := clampf(1.0 + (nrm.dot(light) - light.y) * SHADE_STRENGTH, 0.8, 1.08)
				colour = Color(colour.r * lit, colour.g * lit, colour.b * lit)
				# A contour where this pixel and the one east or south of it are on different bands.
				var band := floori(h / interval)
				var east := floori(east_h / interval)
				var south := floori(south_h / interval)
				if band != east or band != south:
					var line_band := maxi(band, maxi(east, south))
					colour = colour.lerp(CONTOUR, INDEX_ALPHA if line_band % 5 == 0 else CONTOUR_ALPHA)
			data[k * 4] = clampi(roundi(colour.r * 255.0), 0, 255)
			data[k * 4 + 1] = clampi(roundi(colour.g * 255.0), 0, 255)
			data[k * 4 + 2] = clampi(roundi(colour.b * 255.0), 0, 255)
			data[k * 4 + 3] = 255
	var image := Image.create_from_data(side, side, false, Image.FORMAT_RGBA8, data)
	var scale := 1.0 / px_m
	var bounds := Rect2i(Vector2i.ZERO, image.get_size())
	# 3. Woods: each tree's crown, so groves and tree lines read as green patches.
	var crown := maxi(roundi(TREE_CROWN_M * scale), 1)
	for p: Vector2 in inp.trees:
		var c := Vector2i(((p - area.position) * scale).floor())
		var r := Rect2i(c - Vector2i(crown / 2, crown / 2), Vector2i(crown, crown)).intersection(bounds)
		if r.size.x > 0 and r.size.y > 0:
			image.fill_rect(r, WOODS)
	# 4. Pads (a module's flattened ground), then roads and streets over them.
	for pad: Rect2 in inp.pads:
		_fill(image, area, scale, pad, PAD)
	var road_px := maxf(ZoneTerrain.ROAD_CORE_M * 2.0 * scale, 2.0)
	for seg: Array in inp.roads:
		_stroke(image, area, scale, seg[0], seg[1], road_px + 2.0, ROAD_CASING)
	for seg: Array in inp.roads:
		_stroke(image, area, scale, seg[0], seg[1], road_px, ROAD)
	for street: Rect2 in inp.streets:
		_fill(image, area, scale, street, STREET)
	# 5. Buildings and walls as footprints: one dark tone, low cover a little lighter.
	for entry: Array in inp.boxes:
		var box: AABB = entry[0]
		var low := float(entry[2]) < 1.6
		_fill(image, area, scale, Rect2(box.position.x, box.position.z, box.size.x, box.size.z), BUILDING.lightened(0.3) if low else BUILDING)
	return image


## A thick straight line on the image (ends in metres, `width` in pixels): squares stamped
## along it.
static func _stroke(image: Image, area: Rect2, scale: float, a: Vector2, b: Vector2, width: float, colour: Color) -> void:
	var pa := (a - area.position) * scale
	var pb := (b - area.position) * scale
	var steps := maxi(ceili(pa.distance_to(pb) * 2.0), 1)
	var w := maxi(roundi(width), 1)
	var bounds := Rect2i(Vector2i.ZERO, image.get_size())
	for i in steps + 1:
		var p := pa.lerp(pb, float(i) / steps)
		var r := Rect2i(Vector2i((p - Vector2(w, w) * 0.5).round()), Vector2i(w, w)).intersection(bounds)
		if r.size.x > 0 and r.size.y > 0:
			image.fill_rect(r, colour)
