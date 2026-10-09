class_name VoxelArmor
extends Area3D
## Wearable armor made of 1 cm voxels: plates and helmets. It is both the visual and the
## hit target. A round entering the piece is traced voxel by voxel along its path: if it
## meets material first, the armor stops it and a chip is carved there; if it reaches the
## empty interior (the head inside a helmet) or leaves through a hole, it carries on.
## Chips are part of the item's state ([x, y, z, radius] in Inventory.slot_state), so
## they travel with the plate or helmet when it's dropped. The mesh is rebuilt by
## replaying them, so every peer, including late joiners, sees the same damage.
##
## Shapes come from the item's stats: "shape": "plate" (width/height/thickness_vox) or
## "helmet" (tier light/medium/heavy). The strike face of a plate is -Z.

const VOXEL_SIZE := 0.01
enum { EMPTY, INTACT, SCARRED, INTERIOR, ACCENT, VISOR }
const MISS := Vector3i(-1, -1, -1)

static var _bases: Dictionary = {}    # item id -> {"buffer", "dims", "pivot", "solid"}
static var _meshers: Dictionary = {}  # item id -> VoxelMesherCubes
static var _material: StandardMaterial3D

var item: ItemData
var slot: StringName
var inventory: Inventory

var _base: Dictionary
var _buffer: VoxelBuffer
var _mesh_instance: MeshInstance3D
var _removed := 0


func setup(p_item: ItemData, p_slot: StringName, p_inventory: Inventory, render_layers: int) -> void:
	item = p_item
	slot = p_slot
	inventory = p_inventory
	if slot != &"":
		name = String(slot)
	_base = _get_base(item)
	collision_layer = 1 << 3
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_base.dims) * VOXEL_SIZE
	shape.shape = box
	shape.position = (Vector3(_base.dims) * 0.5 - _base.pivot) * VOXEL_SIZE
	add_child(shape)
	_mesh_instance = make_mesh_instance(item, render_layers)
	add_child(_mesh_instance)
	_buffer = VoxelBuffer.new()
	_buffer.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_8_BIT)
	_buffer.create(_base.dims.x + 2, _base.dims.y + 2, _base.dims.z + 2)
	apply_damage([])


## An undamaged mesh of the piece, positioned so its pivot is at the origin. Also used to
## show armor lying in the world.
static func make_mesh_instance(p_item: ItemData, render_layers := 1) -> MeshInstance3D:
	var base := _get_base(p_item)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.material_override = _get_material()
	mesh_instance.layers = render_layers
	mesh_instance.scale = Vector3.ONE * VOXEL_SIZE
	mesh_instance.position = -base.pivot * VOXEL_SIZE
	mesh_instance.mesh = _get_mesher(p_item).build_mesh(base.buffer, [])
	return mesh_instance


static func size_m(p_item: ItemData) -> Vector3:
	return Vector3(_get_base(p_item).dims) * VOXEL_SIZE


## Offset from a piece's pivot to the centre of its voxel grid, in metres.
static func center_offset(p_item: ItemData) -> Vector3:
	var base := _get_base(p_item)
	return (Vector3(base.dims) * 0.5 - base.pivot) * VOXEL_SIZE


## Rebuilds from the undamaged shape and replays every chip.
func apply_damage(chips: Array) -> void:
	_buffer.copy_channel_from(_base.buffer, VoxelBuffer.CHANNEL_COLOR)
	_removed = 0
	for chip: Array in chips:
		_carve(Vector3i(int(chip[0]), int(chip[1]), int(chip[2])), float(chip[3]))
	_mesh_instance.mesh = _get_mesher(item).build_mesh(_buffer, [])


func integrity() -> float:
	return 1.0 - float(_removed) / float(_base.solid) if _base.solid > 0 else 0.0


## Host only. Returns true if the armor stopped the round (and records the chip).
func server_try_stop(hit_position: Vector3, direction: Vector3, weapon: ItemData) -> bool:
	var impact := trace(hit_position, direction)
	if impact == MISS:
		return false
	var radius := float(item.stats.get("chip_radius", 1.5)) * float(weapon.stats.get("plate_wear", 1.0))
	inventory.add_chip(slot, [impact.x, impact.y, impact.z, radius])
	return true


## First solid voxel a round entering at `hit_position` meets, or MISS if it reaches the
## interior or leaves the grid first (a 3D DDA walk through the voxel grid).
func trace(hit_position: Vector3, direction: Vector3) -> Vector3i:
	var dims: Vector3i = _base.dims
	var pivot: Vector3 = _base.pivot
	var dir := (global_basis.inverse() * direction).normalized()
	var p := to_local(hit_position) / VOXEL_SIZE + pivot + dir * 0.01
	var cell := Vector3i(clampi(floori(p.x), 0, dims.x - 1), clampi(floori(p.y), 0, dims.y - 1), clampi(floori(p.z), 0, dims.z - 1))
	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for axis in 3:
		if dir[axis] != 0.0:
			var boundary := float(cell[axis] + (1 if step[axis] > 0 else 0))
			t_max[axis] = (boundary - p[axis]) / dir[axis]
			t_delta[axis] = absf(1.0 / dir[axis])
	for i in dims.x + dims.y + dims.z + 3:
		if cell.x < 0 or cell.y < 0 or cell.z < 0 or cell.x >= dims.x or cell.y >= dims.y or cell.z >= dims.z:
			return MISS
		var v := _voxel_at(cell)
		if v == INTERIOR:
			return MISS
		if v != EMPTY:
			return cell
		var axis := 0 if t_max.x <= t_max.y and t_max.x <= t_max.z else (1 if t_max.y <= t_max.z else 2)
		cell[axis] += step[axis]
		t_max[axis] += t_delta[axis]
	return MISS


## A hole of half the radius through everything, the surface around it spalled out to the
## full radius, and a scarred ring beyond so damage reads at a glance.
func _carve(center: Vector3i, radius: float) -> void:
	var dims: Vector3i = _base.dims
	var reach := int(ceil(radius + 1.5))
	var lo := (center - Vector3i.ONE * reach).max(Vector3i.ZERO)
	var hi := (center + Vector3i.ONE * (reach + 1)).min(dims)
	for pass_index in 2:
		for x in range(lo.x, hi.x):
			for y in range(lo.y, hi.y):
				for z in range(lo.z, hi.z):
					var c := Vector3i(x, y, z)
					var v := _voxel_at(c)
					if v == EMPTY or v == INTERIOR:
						continue
					var d := Vector3(c - center).length()
					if pass_index == 0 and d <= radius * 0.5:
						_remove(c)
					elif pass_index == 1 and d <= radius and _exposed(c):
						_remove(c)
					elif pass_index == 1 and d <= radius + 1.5 and v == INTACT:
						_set_voxel(c, SCARRED)


func _exposed(c: Vector3i) -> bool:
	for offset: Vector3i in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
		var n := c + offset
		if n.x < 0 or n.y < 0 or n.z < 0 or n.x >= _base.dims.x or n.y >= _base.dims.y or n.z >= _base.dims.z:
			return true
		if _voxel_at(n) == EMPTY:
			return true
	return false


func _remove(c: Vector3i) -> void:
	_set_voxel(c, EMPTY)
	_removed += 1


func _voxel_at(c: Vector3i) -> int:
	return _buffer.get_voxel(c.x + 1, c.y + 1, c.z + 1, VoxelBuffer.CHANNEL_COLOR)


func _set_voxel(c: Vector3i, value: int) -> void:
	_buffer.set_voxel(value, c.x + 1, c.y + 1, c.z + 1, VoxelBuffer.CHANNEL_COLOR)


# --- Shapes ---------------------------------------------------------------------------

static func _get_base(p_item: ItemData) -> Dictionary:
	if _bases.has(p_item.id):
		return _bases[p_item.id]
	var stats := p_item.stats
	var shape: Dictionary
	if stats.get("shape", "plate") == "helmet":
		shape = _helmet_shape(stats)
	else:
		var dims := Vector3i(int(stats.get("width_vox", 25)), int(stats.get("height_vox", 30)), int(stats.get("thickness_vox", 2)))
		shape = {"dims": dims, "pivot": Vector3(dims) * 0.5, "cells": func(_c: Vector3i) -> int: return INTACT}
	var dims: Vector3i = shape.dims
	var buffer := VoxelBuffer.new()
	buffer.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_8_BIT)
	buffer.create(dims.x + 2, dims.y + 2, dims.z + 2)  # 1 voxel of mesher padding per side
	buffer.fill(EMPTY, VoxelBuffer.CHANNEL_COLOR)
	var solid := 0
	var cells: Callable = shape.cells
	for x in dims.x:
		for y in dims.y:
			for z in dims.z:
				var v: int = cells.call(Vector3i(x, y, z))
				if v != EMPTY:
					buffer.set_voxel(v, x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR)
				if v != EMPTY and v != INTERIOR:
					solid += 1
	var base := {"buffer": buffer, "dims": dims, "pivot": shape.pivot, "solid": solid}
	_bases[p_item.id] = base
	return base


## Rounded-box shell (a superellipsoid, which fits a blocky head better than a sphere).
## The pivot is the centre of the dome's base, which sits at head-local y = 0.20 m.
static func _helmet_shape(stats: Dictionary) -> Dictionary:
	var tier: String = stats.get("tier", "medium")
	var th := float(stats.get("thickness_vox", 2))
	var r := Vector3(16, 14, 17) if tier == "light" else Vector3(17, 16, 18)
	var below := 20 if tier == "heavy" else 0  # heavy: ear covers and a visor down to the chin
	var dims := Vector3i(int(r.x * 2), int(r.y) + below, int(r.z * 2))
	var inner := r - Vector3.ONE * th
	var cells := func(c: Vector3i) -> int:
		var d := Vector3(c.x + 0.5 - r.x, c.y + 0.5 - below, c.z + 0.5 - r.z)
		var v := EMPTY
		if d.y >= 0.0:
			if _superellipse(d / inner) <= 1.0:
				v = INTERIOR
			elif _superellipse(d / r) <= 1.0:
				v = INTACT
			if tier != "heavy" and v == INTACT and d.y < r.y * 0.3 and d.z < -r.z * 0.45:
				v = EMPTY  # face opening at the brow
			if v == INTACT and tier == "medium":
				if d.z < -r.z + 3.0 and absf(d.x) < 3.0 and d.y > r.y * 0.4 and d.y < r.y * 0.7:
					v = ACCENT  # NVG shroud
				elif absf(d.x) > r.x - 3.0 and d.y > r.y * 0.2 and d.y < r.y * 0.35:
					v = ACCENT  # side rails
		else:
			var flat := Vector3(d.x, 0.0, d.z)
			if _superellipse(flat / inner) <= 1.0:
				v = INTERIOR
			elif _superellipse(flat / r) <= 1.0 and d.y > -12.0 and d.z > -r.z * 0.3:
				v = INTACT  # ear covers
		# Heavy: a framed visor over the face, from the brow down to the chin.
		if tier == "heavy" and d.z < -(r.z - 2.0) and d.z >= -r.z and absf(d.x) <= r.x - 5.0 and d.y < r.y * 0.3 and d.y >= -15.0:
			var frame := absf(d.x) > r.x - 7.0 or d.y < -13.0 or d.y > r.y * 0.3 - 2.0
			v = ACCENT if frame else VISOR
		return v
	return {"dims": dims, "pivot": Vector3(r.x, below, r.z), "cells": cells}


static func _superellipse(v: Vector3) -> float:
	return pow(absf(v.x), 4.0) + pow(absf(v.y), 4.0) + pow(absf(v.z), 4.0)


static func _get_mesher(p_item: ItemData) -> VoxelMesherCubes:
	if not _meshers.has(p_item.id):
		var colour := Color(p_item.stats.get("color", "4f5a45"))
		var palette := VoxelColorPalette.new()
		palette.set_color(EMPTY, Color(0, 0, 0, 0))
		palette.set_color(INTACT, colour)
		palette.set_color(SCARRED, Color("c9c2ae"))
		palette.set_color(INTERIOR, Color(0, 0, 0, 0))
		palette.set_color(ACCENT, colour.darkened(0.35))
		palette.set_color(VISOR, Color("4d6f80"))  # tinted polycarbonate
		var mesher := VoxelMesherCubes.new()
		mesher.palette = palette
		mesher.color_mode = VoxelMesherCubes.COLOR_MESHER_PALETTE
		_meshers[p_item.id] = mesher
	return _meshers[p_item.id]


static func _get_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.8
	return _material
