class_name VoxelArmor
extends Area3D
## Armor made of 1 cm voxels: plates and helmets. It is both the visual and the hit target,
## worn (in a GearRig) or lying on the ground (in a WorldItem). A round entering the piece is
## traced voxel by voxel along its path: if it reaches the empty interior (the head inside a
## helmet) or leaves through a hole, it carries on. If it meets material, ArmorRules decide:
## the piece stops it when its rating is at or above the round's threat level (and, for
## ceramic, the crack roll holds, and the spot isn't worn through), else the round goes
## through. A stopped round leaves a small DENT on the strike face, a few voxels that never
## open a hole; a round that gets through bores a HOLE through the wall it crossed, spalled
## out around it. When someone wears the piece, a stop still lands an impact on them
## (Vitals.server_impact), and a steel plate throws spall.
## Chips are part of the item's state (see make_chip(); in Inventory.slot_state when worn, in
## WorldItem.state on the ground), with a ceramic plate's cracks and integrity, so they
## travel with the plate or helmet. The mesh is rebuilt by replaying them, so every peer,
## including late joiners, sees the same damage.
##
## Shapes come from the item's stats: "shape": "plate" (width/height/thickness_vox) or
## "helmet" (tier light/medium/heavy). The strike face of a plate is -Z. "dent_radius" and
## "chip_radius" (voxels, scaled by the weapon's "plate_wear") size a stop's dent and a
## penetration's hole.

const VOXEL_SIZE := 0.01
enum { EMPTY, INTACT, SCARRED, INTERIOR, ACCENT, VISOR }
const MISS := Vector3i(-1, -1, -1)
## Chip kinds, a chip's fifth entry. Chips saved before kinds existed ([x, y, z, radius])
## are holes, carved the old way.
const HOLE := 0
const DENT := 1
## Smallest radius (voxels) a hole is bored with: wide enough that the line of fire that
## made it passes through it again.
const MIN_HOLE_RADIUS := 1.0
## A dent scuffs (scars) the strike face this far (voxels) beyond what it removes.
const DENT_SCAR_VOX := 0.75
## A hole scars the surface this far (voxels) beyond its spalled-out rim.
const HOLE_SCAR_VOX := 1.5
## Defaults when an item's stats don't say.
const DEFAULT_DENT_RADIUS := 1.0
const DEFAULT_CHIP_RADIUS := 2.0

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
var _own_state: Dictionary = {}  # state of a piece that is neither worn nor in a WorldItem


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


## Rebuilds from the undamaged shape and replays every chip. A `shattered` plate shows its
## whole face scarred.
func apply_damage(chips: Array, shattered := false) -> void:
	_buffer.copy_channel_from(_base.buffer, VoxelBuffer.CHANNEL_COLOR)
	_removed = 0
	for chip: Array in chips:
		var cell := Vector3i(int(chip[0]), int(chip[1]), int(chip[2]))
		if chip.size() >= 8:
			var dir := Vector3(float(chip[5]), float(chip[6]), float(chip[7]))
			if int(chip[4]) == DENT:
				_dent(cell, float(chip[3]), dir)
			else:
				_bore(cell, float(chip[3]), dir)
		else:
			_carve(cell, float(chip[3]))
	if shattered:
		for x in _base.dims.x:
			for y in _base.dims.y:
				for z in _base.dims.z:
					if _voxel_at(Vector3i(x, y, z)) == INTACT:
						_set_voxel(Vector3i(x, y, z), SCARRED)
	_mesh_instance.mesh = _get_mesher(item).build_mesh(_buffer, [])


## Share of the piece's voxels still there, 1 (new) to 0.
func integrity() -> float:
	return 1.0 - float(_removed) / float(_base.solid) if _base.solid > 0 else 0.0


## How many voxels the damage shown has knocked out.
func voxels_removed() -> int:
	return _removed


## Host only. Whether the soft armor `body` wears (the vest's aramid) stops a round of
## `threat` (a Ballistics.LEVELS entry) and `round_class` (Vitals.PISTOL...) at `part`, where
## it met no plate (or went through one). `direction` is the round's travel direction (a
## light vest covers the front only). `position` (where it hit) splits a whole-torso hit
## into chest, abdomen and pelvis; `energy_j` is passed on to the impact (-1 if unknown).
## FRAGMENT threat is stopped by any aramid that covers the part. If it stops, the impact
## goes to the wearer's Vitals.server_impact on the torso part hit.
static func soft_armor_stops(body: Node, part: StringName, threat: StringName, round_class: StringName, distance: float, direction: Vector3, position := Vector3.INF, energy_j := -1.0) -> bool:
	var body_3d := body as Node3D
	var vest := ArmorRules.vest_of(body)
	if body_3d == null or vest == null:
		return false
	var torso_part := ArmorRules.armor_part(body_3d, part, position)
	if not ArmorRules.soft_covers(vest, torso_part, ArmorRules.facing(body_3d, direction)):
		return false
	if not ArmorRules.stops(ArmorRules.soft_rating(vest), threat):
		return false
	var vitals := Vitals.find_on(body)
	if vitals:
		vitals.server_impact(torso_part, round_class, distance, energy_j)
	return true


## Host only. Resolves a round from `weapon` entering the piece at `hit_position`, fired from
## `distance` metres. Returns true if the armor stopped it. Records the chip (a dent for a
## stop, a hole for a penetration) and a ceramic plate's crack and integrity in the item's
## state either way, and on a stop lands the impact on the wearer and throws a steel plate's
## spall. Works the same on a piece lying on the ground (no wearer, so no impact or spall).
func server_try_stop(hit_position: Vector3, direction: Vector3, weapon: ItemData, distance := 0.0) -> bool:
	var impact := trace(hit_position, direction)
	if impact == MISS:
		return false
	var state := item_state()
	var round_class := Ballistics.round_class(weapon)
	var stopped := ArmorRules.piece_stops(item, state, impact, Ballistics.threat_level_at(weapon, distance))
	var wear := float(weapon.stats.get("plate_wear", 1.0))
	var radius: float
	if stopped:
		radius = float(item.stats.get("dent_radius", DEFAULT_DENT_RADIUS)) * wear
	else:
		radius = float(item.stats.get("chip_radius", DEFAULT_CHIP_RADIUS)) * wear
	var local_dir := (global_basis.inverse() * direction).normalized()
	_record_hit(make_chip(impact, radius, DENT if stopped else HOLE, local_dir), ArmorRules.hit_changes(item, state, impact, round_class))
	if stopped:
		_server_after_stop(hit_position, direction, weapon, distance, round_class)
	return stopped


## A chip as item state stores it: [x, y, z, radius, kind, dx, dy, dz], the voxel the round
## met, the dent's or hole's radius in voxels, DENT or HOLE, and the round's direction in the
## piece's own axes (rounded, so state stays small and compares by value).
static func make_chip(cell: Vector3i, radius: float, kind: int, local_dir: Vector3) -> Array:
	return [cell.x, cell.y, cell.z, snappedf(radius, 0.01), kind,
		snappedf(local_dir.x, 0.01), snappedf(local_dir.y, 0.01), snappedf(local_dir.z, 0.01)]


## The item state this piece shows: its slot's in the wearer's inventory, or the state of
## the WorldItem it lies in.
func item_state() -> Dictionary:
	if inventory:
		return inventory.state_of(slot)
	var loose := get_parent() as WorldItem
	return loose.state if loose else _own_state


## The wearer's body (a Soldier or TargetDummy), or null for a loose piece.
func wearer() -> Node3D:
	return inventory.get_parent() as Node3D if inventory else null


## Host only. Records a hit where this piece's state lives: the wearer's inventory (which
## replicates it and GearRig redraws), the WorldItem it lies in (which replicates, saves and
## redraws it), or this piece alone.
func _record_hit(new_chip: Array, changes: Dictionary) -> void:
	if inventory:
		inventory.add_armor_hit(slot, new_chip, changes)
		return
	var loose := get_parent() as WorldItem
	if loose:
		loose.server_add_armor_hit(new_chip, changes)
		return
	var chips: Array = _own_state.get("chips", []).duplicate()
	chips.append(new_chip)
	_own_state["chips"] = chips
	_own_state.merge(changes, true)
	apply_damage(chips, ArmorRules.is_shattered(_own_state))


## The body part behind the strike point: HEAD for a helmet, else the torso part (CHEST or
## ABDOMEN) at that height.
func part_behind(hit_position: Vector3) -> StringName:
	if slot == &"helmet":
		return Vitals.HEAD
	var body := wearer()
	var part: StringName = ArmorRules.torso_part_at(body, hit_position) if body else Vitals.CHEST
	return Vitals.ABDOMEN if part == Vitals.ABDOMEN or part == Vitals.PELVIS else Vitals.CHEST


func _server_after_stop(hit_position: Vector3, direction: Vector3, weapon: ItemData, distance: float, round_class: StringName) -> void:
	var body := wearer()
	var vitals: Vitals = Vitals.find_on(body) if body else null
	if vitals == null:
		return
	vitals.server_impact(part_behind(hit_position), round_class, distance, Ballistics.energy_at(weapon, distance))
	if ArmorRules.material(item) == ArmorRules.STEEL and not bool(item.stats.get("spall_coated", false)):
		ArmorRules.server_spall(body, vitals, hit_position, direction, round_class)


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


## A stopped round's mark: the strike-face voxels within `radius` of `center` (the voxel it
## met) knocked out, and a scuffed ring just beyond. It never opens a hole. "Behind" a voxel
## is one step through the piece's thickness (_thickness_axis: a plate's Z, a helmet shell's
## inward normal), on the side the round travels, whatever the round's angle; a voxel goes
## only if nothing solid is in front of it that way (it is on the strike face), the voxel
## behind it is solid and stays, and it isn't in the innermost layer of a helmet (next to the
## head space). So every line through the thickness keeps material, and a plate's back layer
## is never touched. Where nothing is left behind, the round only scars the surface.
## Repeated stops on one spot dig in a layer at a time; wearing right through is
## ArmorRules.worn_through's call, as a hole.
func _dent(center: Vector3i, radius: float, dir: Vector3) -> void:
	var reach := int(ceil(radius + DENT_SCAR_VOX))
	var lo := (center - Vector3i.ONE * reach).max(Vector3i.ZERO)
	var hi := (center + Vector3i.ONE * (reach + 1)).min(_base.dims)
	var face: Array[Vector3i] = []   # solid voxels on the strike side, within the scar reach
	var hit := {}                    # those within the dent radius
	for x in range(lo.x, hi.x):
		for y in range(lo.y, hi.y):
			for z in range(lo.z, hi.z):
				var c := Vector3i(x, y, z)
				var offset := Vector3(c - center)
				if not _is_solid(c) or offset.dot(dir) > 0.5:
					continue
				var d := offset.length()
				if d <= radius:
					hit[c] = true
				if d <= radius + DENT_SCAR_VOX:
					face.append(c)
	var removable := {}  # strike-face voxel -> the voxel behind it; decided on the piece as it was
	for c: Vector3i in hit:
		var axis := _thickness_axis(c)
		if absf(dir[axis]) == 0.0:
			continue
		var behind := Vector3i.ZERO
		behind[axis] = 1 if dir[axis] > 0.0 else -1
		if not _is_solid(c - behind) and _is_solid(c + behind) and not _touches_interior(c):
			removable[c] = c + behind
	for c: Vector3i in hit:
		# Goes only if what's behind it stays (on a helmet's curve, neighbours' axes differ).
		if removable.has(c) and not removable.has(removable[c]):
			_remove(c)
		elif _voxel_at(c) == INTACT:
			_set_voxel(c, SCARRED)
	for c in face:
		if _voxel_at(c) == INTACT and _exposed(c):
			_set_voxel(c, SCARRED)


## The axis (0 x, 1 y, 2 z) through the piece's thickness at voxel `c`: Z for a plate; for a
## helmet the main axis of the shell's normal there (the superellipsoid's gradient, flat for
## the ear covers below the dome's base; a visor is Z).
func _thickness_axis(c: Vector3i) -> int:
	if item == null or item.stats.get("shape", "plate") != "helmet":
		return 2
	var pivot: Vector3 = _base.pivot
	var d := Vector3(c) + Vector3.ONE * 0.5 - pivot
	var dims := Vector3(_base.dims)
	var r := Vector3(dims.x * 0.5, maxf(dims.y - pivot.y, 1.0), dims.z * 0.5)
	var n := Vector3(absf(d.x) / r.x, absf(d.y) / r.y if d.y >= 0.0 else 0.0, absf(d.z) / r.z)
	return 0 if n.x >= n.y and n.x >= n.z else (1 if n.y >= n.z else 2)


## A penetration: a hole of half `radius` (at least MIN_HOLE_RADIUS) bored along `dir` from
## `center` through the wall the round crossed (to where it reached the head space or left
## the piece, so a helmet's far side is untouched), the surface around it spalled out to
## `radius`, and a scarred ring beyond so the damage reads at a glance.
func _bore(center: Vector3i, radius: float, dir: Vector3) -> void:
	var from := Vector3(center) + Vector3.ONE * 0.5
	var t_end := 0.0
	var max_t := float(_base.dims.x + _base.dims.y + _base.dims.z)
	while t_end < max_t and _is_solid(_cell_at(from + dir * (t_end + 0.25))):
		t_end += 0.25
	var a := from - dir * 0.5
	var b := from + dir * (t_end + 0.5)
	var hole := maxf(radius * 0.5, MIN_HOLE_RADIUS)
	var reach := int(ceil(radius + HOLE_SCAR_VOX))
	var lo := (Vector3i(a.min(b).floor()) - Vector3i.ONE * reach).max(Vector3i.ZERO)
	var hi := (Vector3i(a.max(b).floor()) + Vector3i.ONE * (reach + 1)).min(_base.dims)
	for pass_index in 2:
		for x in range(lo.x, hi.x):
			for y in range(lo.y, hi.y):
				for z in range(lo.z, hi.z):
					var c := Vector3i(x, y, z)
					if not _is_solid(c):
						continue
					var p := Vector3(c) + Vector3.ONE * 0.5
					var d := p.distance_to(Geometry3D.get_closest_point_to_segment(p, a, b))
					if pass_index == 0 and d <= hole:
						_remove(c)
					elif pass_index == 1 and d <= radius and _exposed(c):
						_remove(c)
					elif pass_index == 1 and d <= radius + HOLE_SCAR_VOX and _voxel_at(c) == INTACT:
						_set_voxel(c, SCARRED)


func _cell_at(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x), floori(p.y), floori(p.z))


## Inside the grid and material (not empty space or the head space inside a helmet).
func _is_solid(c: Vector3i) -> bool:
	if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= _base.dims.x or c.y >= _base.dims.y or c.z >= _base.dims.z:
		return false
	var v := _voxel_at(c)
	return v != EMPTY and v != INTERIOR


func _touches_interior(c: Vector3i) -> bool:
	for offset: Vector3i in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
		var n := c + offset
		if n.x >= 0 and n.y >= 0 and n.z >= 0 and n.x < _base.dims.x and n.y < _base.dims.y and n.z < _base.dims.z \
				and _voxel_at(n) == INTERIOR:
			return true
	return false


## Legacy chips ([x, y, z, radius], saved before chips had kinds): a hole of half the radius
## through everything, the surface around it spalled out to the full radius, and a scarred
## ring beyond.
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
