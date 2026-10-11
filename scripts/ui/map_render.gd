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
