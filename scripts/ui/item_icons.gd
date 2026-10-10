class_name ItemIcons
extends Node
## Item preview images for the inventory screen, rendered at runtime: each item's own model
## (its VoxelArt, a plate's or helmet's VoxelArmor, a pouch's boxes, else the placeholder box
## it has in the world) in a small SubViewport of its own, captured once and cached per item
## id. Rendering is batched a few items a frame. Where nothing can be rendered (headless
## runs, a failed capture), get_icon() returns null and the screen draws a coloured tile.

signal icon_ready(id: StringName)

const SIZE := 128
const PER_BATCH := 6
## Three-quarter view: items turned and tipped a little towards the camera.
const VIEW_TURN := deg_to_rad(28.0)
const VIEW_TIP := deg_to_rad(14.0)

static var _cache: Dictionary = {}  # item id -> Texture2D, or null when it couldn't render
static var _instance: ItemIcons

var _queue: Array[StringName] = []
var _busy := false


## The preview of item `id`, or null while it's being made (icon_ready fires when it's
## done) or when it can't be rendered.
static func get_icon(id: StringName) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	if not can_render() or not ItemDB.has_item(id):
		return null
	var icons := instance()
	if icons and not id in icons._queue:
		icons._queue.append(id)
		icons._pump.call_deferred()
	return null


## False in headless runs (tests), where there's no renderer to capture from.
static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"


## The shared renderer node (made on first use, under the scene tree root).
static func instance() -> ItemIcons:
	if is_instance_valid(_instance):
		return _instance
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	_instance = ItemIcons.new()
	_instance.name = "ItemIcons"
	tree.root.add_child.call_deferred(_instance)
	return _instance


## A node showing `item` as it looks in the world, front towards -Z.
static func preview_node(item: ItemData) -> Node3D:
	if item.is_voxel_armor():
		var holder := Node3D.new()
		holder.add_child(VoxelArmor.make_mesh_instance(item))
		return holder
	var art := VoxelArt.model_for(item)
	if art != "":
		return VoxelArt.instance(art, "multicam")
	if Inventory.is_attachable(item):
		return GearRig.pouch_node(item, Color(VoxelArt.VARIANTS.multicam.gear).darkened(0.12), false)
	var holder := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = WorldItem.visual_size(item)
	var material := StandardMaterial3D.new()
	material.albedo_color = WorldItem.color_for(item)
	box.material = material
	mesh_instance.mesh = box
	holder.add_child(mesh_instance)
	return holder


func _pump() -> void:
	if _busy or not is_inside_tree():
		return
	_busy = true
	while not _queue.is_empty():
		var batch: Array[StringName] = []
		while not _queue.is_empty() and batch.size() < PER_BATCH:
			var id: StringName = _queue.pop_front()
			if not _cache.has(id):
				batch.append(id)
		var viewports: Array[SubViewport] = []
		for id in batch:
			viewports.append(_stage(ItemDB.get_item(id)))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		for i in batch.size():
			var image := viewports[i].get_texture().get_image() if viewports[i] else null
			_cache[batch[i]] = ImageTexture.create_from_image(image) if image and not image.is_empty() else null
			if viewports[i]:
				viewports[i].queue_free()
			icon_ready.emit(batch[i])
	_busy = false


## A SubViewport with `item` lit and framed, set to render once.
func _stage(item: ItemData) -> SubViewport:
	if item == null:
		return null
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.85)
	env.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-40), deg_to_rad(150), 0)
	key.light_energy = 1.3
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(deg_to_rad(-20), deg_to_rad(-30), 0)
	rim.light_energy = 0.5
	viewport.add_child(rim)

	var turn := Node3D.new()
	viewport.add_child(turn)
	var node := preview_node(item)
	turn.add_child(node)
	var size := _bounds(turn).size
	if size.z > size.x * 1.4:
		node.rotation.y = -PI / 2  # long things (rifles) shown side on, muzzle to the left
	turn.rotation = Vector3(VIEW_TIP, PI + VIEW_TURN, 0)  # the camera looks at the item's front
	var bounds := _bounds(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(maxf(bounds.size.x, bounds.size.y) * 1.18, 0.02)
	camera.near = 0.01
	camera.far = 20.0
	camera.position = bounds.get_center() + Vector3(0, 0, maxf(bounds.size.z, 0.5) + 1.0)
	viewport.add_child(camera)
	camera.current = true
	return viewport


## Bounds of every mesh under `root`, in `root`'s parent space (world space for a viewport).
static func _bounds(root: Node) -> AABB:
	var out := AABB()
	var first := true
	for mesh_instance: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null:
			continue
		var box := mesh_instance.global_transform * mesh_instance.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out
