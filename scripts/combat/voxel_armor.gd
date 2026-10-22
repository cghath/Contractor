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
## Shapes come from the item's stats: "shape": "plate" (width/height/thickness_vox),
## "helmet" (tier light/medium/heavy) or "guard" (an exo frame's limb pad: a sleeve round a
## limb, see _guard_shape). The strike face of a plate is -Z. "dent_radius" and
## "chip_radius" (voxels, scaled by the weapon's "plate_wear") size a stop's dent and a
## penetration's hole.

const VOXEL_SIZE := 0.01
## CAMO_B..CAMO_D: a camo-painted piece's other pattern colours (paint_camo), only ever in the
## copy that is meshed; the piece's own buffer keeps INTACT there.
enum { EMPTY, INTACT, SCARRED, INTERIOR, ACCENT, VISOR, FACEPLATE, GLOW, CAMO_B, CAMO_C, CAMO_D }
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
## The carrier's fabric over a plate in its pocket (alpha 0: none, the bare plate shows).
## The intact surface takes this colour, so the plate reads as enclosed; chips and holes
## show the plate under the torn cover.
var cover := Color(0, 0, 0, 0)
var slot: StringName
var inventory: Inventory
## An exo frame's pad (ExoFrame.pad_items): its id, whose state lives in the frame slot's
## state under "pads" (so it travels with the frame), and the body part it covers ("" for
## plates and helmets, which work theirs out).
var pad := ""
var body_part: StringName = &""
## A camo variant (VoxelArt.VARIANTS) painted over the intact surface of a piece whose item
## says "camo" (the heavy exo's plates, ExoMech; Captain, 2026-10-16: "real camo, not a sci-fi
## monochrome look"), or "" for its plain colour. Chips and scars show the bare metal as usual.
var camo := ""
## A heavy exo standing empty (ExoMech, a WorldItem): this pad's state lives in its "pads".
var loose_suit: WorldItem

var _base: Dictionary
var _buffer: VoxelBuffer
var _mesh_instance: MeshInstance3D
var _removed := 0
var _pristine := false  # no chips, not shattered: shows the shared intact mesh (intact_mesh)
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


## An undamaged mesh of the piece, positioned so its pivot is at the origin, under `cover`
## (alpha 0: none). Also used to show armor lying in the world, and an exo pad in first person.
static func make_mesh_instance(p_item: ItemData, render_layers := 1, cover := Color(0, 0, 0, 0), p_camo := "") -> MeshInstance3D:
	var base := _get_base(p_item)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.material_override = _get_material()
	mesh_instance.layers = render_layers
	mesh_instance.scale = Vector3.ONE * VOXEL_SIZE
	mesh_instance.position = -base.pivot * VOXEL_SIZE
	mesh_instance.mesh = intact_mesh(p_item, cover, p_camo)
	return mesh_instance


## Undamaged pieces' meshes, by item, cover and camo (perf pass 2026-10-22): built once and
## shared by every piece showing no damage, not meshed three times per piece at every spawn
## (setup, apply_damage and the cover) as before. A chipped piece meshes its own (_remesh).
static var _intact := {}


## The undamaged mesh of `p_item` under `p_cover` in `p_camo` (built once, then shared).
static func intact_mesh(p_item: ItemData, p_cover := Color(0, 0, 0, 0), p_camo := "") -> Mesh:
	if not bool(p_item.stats.get("camo", false)):
		p_camo = ""
	var key := "%s|%s|%s" % [p_item.id, p_cover.to_html() if p_cover.a > 0.0 else "", p_camo]
	if not _intact.has(key):
		var t := Time.get_ticks_usec()
		_intact[key] = _get_mesher(p_item, p_cover, p_camo).build_mesh(paint_camo(_get_base(p_item).buffer, p_item, p_camo), [])
		FrameCost.spent(&"armour", t)
	return _intact[key]


## Covers the plate with carrier fabric of `colour` (alpha 0 to show the bare plate).
func set_cover(colour: Color) -> void:
	if colour == cover:
		return
	cover = colour
	_remesh()


## Paints the piece in `variant`'s camo (see camo), "" for its plain colour.
func set_camo(variant: String) -> void:
	if variant == camo:
		return
	camo = variant
	_remesh()


func _remesh() -> void:
	if _mesh_instance:
		if _pristine:
			_mesh_instance.mesh = intact_mesh(item, cover, camo)
		else:
			_mesh_instance.mesh = _get_mesher(item, cover, camo).build_mesh(paint_camo(_buffer, item, camo), [])


## `buffer` as it is meshed: for a piece whose item says "camo", a copy with its intact voxels
## in `variant`'s camo pattern (VoxelArt's own, so the plates match the uniform's), else
## `buffer` itself.
static func paint_camo(buffer: VoxelBuffer, p_item: ItemData, variant: String) -> VoxelBuffer:
	if variant == "" or not bool(p_item.stats.get("camo", false)):
		return buffer
	var out := VoxelBuffer.new()
	out.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_8_BIT)
	var size := buffer.get_size()
	out.create(size.x, size.y, size.z)
	out.copy_channel_from(buffer, VoxelBuffer.CHANNEL_COLOR)
	var salt := absi(String(p_item.id).hash())
	var paint := {VoxelArt.C.CAMO_B: CAMO_B, VoxelArt.C.CAMO_C: CAMO_C, VoxelArt.C.CAMO_D: CAMO_D}
	for x in size.x:
		for y in size.y:
			for z in size.z:
				if out.get_voxel(x, y, z, VoxelBuffer.CHANNEL_COLOR) == INTACT:
					var c: int = paint.get(VoxelArt._camo(Vector3(x, y, z) * VOXEL_SIZE * 100.0, salt, variant), INTACT)
					if c != INTACT:
						out.set_voxel(c, x, y, z, VoxelBuffer.CHANNEL_COLOR)
	return out


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
	_pristine = chips.is_empty() and not shattered
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
	_remesh()


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
	# A visor has its own rating where it has one ("visor_rating": the LX-3's stops fragments only).
	var own := StringName(item.stats.get("visor_rating", "")) if _voxel_at(impact) == VISOR else &""
	var stopped := ArmorRules.piece_stops(item, state, impact, Ballistics.threat_level_at(weapon, distance), own)
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
	if inventory and pad != "":
		return ExoFrame.pad_state(inventory, pad)
	if inventory:
		return inventory.state_of(slot)
	if is_instance_valid(loose_suit):
		return loose_suit.state.get("pads", {}).get(pad, {})
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
		inventory.add_armor_hit(slot, new_chip, changes, pad)
		return
	if is_instance_valid(loose_suit):
		loose_suit.server_add_armor_hit(new_chip, changes, pad)
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


## The body part behind the strike point: an exo pad's own part, HEAD for a helmet, else the
## torso part (CHEST or ABDOMEN) at that height.
func part_behind(hit_position: Vector3) -> StringName:
	if body_part != &"":
		return body_part
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
	if item and item.stats.get("shape", "plate") == "guard":
		var hollow: Array = item.stats.get("hollow_vox", [12, 12])
		var dx := absf(c.x + 0.5 - _base.pivot.x) / float(hollow[0])
		var dz := absf(c.z + 0.5 - _base.pivot.z) / float(hollow[1])
		return 0 if dx >= dz else 2
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
	elif stats.get("shape", "plate") == "guard":
		shape = _guard_shape(stats)
	else:
		shape = _plate_shape(stats)
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
## "face_guard" (the LX-3 helmet; Captain, 2026-10-16/17: "face protection with metal plates like
## modern systems on modern helmets", then "a black visor and protection for the back of the
## head, a modern futuristic pass"): a closed ring bolted on below the shell's rim (RIM_R to JAW_R)
## - a black visor over the eyes (VISOR, "visor_color") with a lit seam along its top and
## bottom (GLOW), metal cheek plates, a nape guard round the back, and a mandible over the mouth
## and chin with a raised centre ridge; the shell above gets a ridge down its crown and
## angular brow and temple plates (ACCENT) in place of the NVG shroud and rails.
static func _helmet_shape(stats: Dictionary) -> Dictionary:
	var tier: String = stats.get("tier", "medium")
	var th := float(stats.get("thickness_vox", 2))
	var r := Vector3(16, 14, 17) if tier == "light" else Vector3(17, 16, 18)
	var guard := bool(stats.get("face_guard", false))
	var below := 20 if tier == "heavy" or guard else 0  # heavy: ear covers and a visor down to the chin
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
			if guard:
				v = _guard_dome_cell(d, r, v)
			elif v == INTACT and tier == "medium":
				if d.z < -r.z + 3.0 and absf(d.x) < 3.0 and d.y > r.y * 0.4 and d.y < r.y * 0.7:
					v = ACCENT  # NVG shroud
				elif absf(d.x) > r.x - 3.0 and d.y > r.y * 0.2 and d.y < r.y * 0.35:
					v = ACCENT  # side rails
		elif guard:
			v = _guard_ring_cell(d, th)
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


## A flat plate, width x height x thickness voxels, its strike face -Z. "curve_vox" bends it
## round the body (its edges that far back, +Z, a smooth arc), "clip_vox" clips its corners
## and "panel_lines" trims its border and runs a ridge down its middle in ACCENT (the exo
## frame's torso pads; Captain, 2026-10-17: "give the armor a future marine look too").
static func _plate_shape(stats: Dictionary) -> Dictionary:
	var w := int(stats.get("width_vox", 25))
	var h := int(stats.get("height_vox", 30))
	var th := int(stats.get("thickness_vox", 2))
	var curve := int(stats.get("curve_vox", 0))
	var clip := int(stats.get("clip_vox", 0))
	var panels := bool(stats.get("panel_lines", false))
	var dims := Vector3i(w, h, th + curve)
	if curve == 0 and clip == 0:
		return {"dims": dims, "pivot": Vector3(dims) * 0.5, "cells": func(_c: Vector3i) -> int: return INTACT}
	var cells := func(c: Vector3i) -> int:
		var ex := mini(c.x, w - 1 - c.x)
		var ey := mini(c.y, h - 1 - c.y)
		if ex + ey < clip:
			return EMPTY
		var u := (c.x + 0.5 - w * 0.5) / (w * 0.5)
		var z := c.z + 0.5 - curve * u * u
		if z < 0.0 or z >= float(th):
			return EMPTY
		if panels and z < 1.0 and (ex + ey == clip or ex == 0 or ey == 0 or absf(u) < 0.07):
			return ACCENT  # the strike face's trimmed border and centre ridge
		return INTACT
	return {"dims": dims, "pivot": Vector3(dims) * 0.5, "cells": cells}


## An exo frame's limb pad (ExoFrame): a rounded sleeve of "height_vox" along the limb (Y) round
## an elliptical hollow of "hollow_vox" [x, z] where the limb is, "thickness_vox" thick, over
## the arcs "walls" names (quarters round the limb: "+x", "-x", "front" = -Z, "back" = +Z);
## the rest is open. Its ends are rounded off. The hollow is the limb's space (like a helmet's
## head space): a round that reaches it, through an open side or a hole, has met no armour.
## The pivot is the middle of the hollow.
static func _guard_shape(stats: Dictionary) -> Dictionary:
	var hollow: Array = stats.get("hollow_vox", [12, 12])
	var th := int(stats.get("thickness_vox", 2))
	var h := int(stats.get("height_vox", 12))
	var walls: Array = stats.get("walls", ["+x", "-x", "front", "back"])
	var panels := bool(stats.get("panel_lines", false))
	var visor: Array = stats.get("visor_band", [])  # [from, to] voxels up: a VISOR slit across the front (the heavy exo's head unit)
	var hx := float(hollow[0]) * 0.5
	var hz := float(hollow[1]) * 0.5
	var dims := Vector3i(int(hollow[0]) + th * 2, h, int(hollow[1]) + th * 2)
	var pivot := Vector3(dims.x * 0.5, h * 0.5, dims.z * 0.5)
	var cells := func(c: Vector3i) -> int:
		var d := Vector3(c.x + 0.5 - pivot.x, 0.0, c.z + 0.5 - pivot.z)
		if (d.x / hx) ** 2 + (d.z / hz) ** 2 < 1.0:
			return INTERIOR
		var end := mini(c.y, h - 1 - c.y)  # rounded ends: thinner at the very rim
		var reach := th - (1.0 if end == 0 else 0.0)
		if (d.x / (hx + reach)) ** 2 + (d.z / (hz + reach)) ** 2 > 1.0:
			return EMPTY
		var side := guard_side(d)
		if not side in walls:
			return EMPTY
		if visor.size() == 2 and side == "front" and c.y >= int(visor[0]) and c.y < int(visor[1]) and absf(d.x) < hx * 0.62:
			return VISOR
		if panels and (d.x / (hx + reach - 1.0)) ** 2 + (d.z / (hz + reach - 1.0)) ** 2 > 1.0:  # the outer face
			if end == 1 or (c.y % 7 == 3) or (side == "front" and absf(d.x) < 1.0):
				return ACCENT  # trim at the ends, panel seams across, a ridge down the front
		return INTACT
	return {"dims": dims, "pivot": pivot, "cells": cells}


## Which quarter round a guard pad's limb the offset `d` (x, z from its middle) is in.
static func guard_side(d: Vector3) -> String:
	if absf(d.x) >= absf(d.z):
		return "+x" if d.x > 0.0 else "-x"
	return "back" if d.z > 0.0 else "front"


## A face guard's half-width (x) and half-depth (z), voxels: at the shell's rim (RIM_R, flush
## with its outer edge: the guard comes off the helmet, Captain 2026-10-17: "it needs to look
## like it comes off of the helmet not in it") sweeping in to the jaw at the chin (JAW_R).
const RIM_R := Vector2(17.0, 18.0)
const JAW_R := Vector2(12.5, 13.5)
## The side hinge hubs: how far below the rim, and their radius (voxels).
const HINGE_DOWN := 3.5
const HINGE_R := 3.0


## A face guard's half-width and half-depth `y` voxels below the shell's rim (y <= 0).
static func guard_jaw(y: float) -> Vector2:
	return RIM_R.lerp(JAW_R, clampf(-y / -GUARD_LOW, 0.0, 1.0))
## Face guard heights (voxels from the dome's base, the eyes at about -3..0): the visor from the
## brow (VISOR_TOP) down to VISOR_BOTTOM, the mandible below it to the chin (GUARD_LOW), the nape
## guard round the back down to NAPE_LOW.
const VISOR_TOP := 2.0
## A metal brow plate from the visor's top up past the shell's brow opening (4.8, r.y * 0.3): no
## skin between the brim and the visor.
const BROW_TOP := 6.0
const VISOR_BOTTOM := -5.0
const GUARD_LOW := -16.0
const NAPE_LOW := -16.0
## The neck seal under the ring, to the bottom of the grid: half-width, half-depth (voxels) and
## how far back its middle sits (the neck is behind the face).
const NECK_R := Vector2(8.5, 8.5)
const NECK_R_Z := 1.5


## The shell above the dome's base on a face guard helmet (`v` as the plain shell gives it): the
## visor's top over the face opening, a ridge down the crown, a brow plate and temple plates.
static func _guard_dome_cell(d: Vector3, r: Vector3, v: int) -> int:
	var front := d.z < -r.z * 0.45
	if v != ACCENT and front and d.y < BROW_TOP:  # (the goggle band and brow sit inside the opening, round the face)
		var e := (d.x / RIM_R.x) ** 2 + (d.z / RIM_R.y) ** 2
		if e <= 1.0 and (d.x / (RIM_R.x - 2.0)) ** 2 + (d.z / (RIM_R.y - 2.0)) ** 2 > 1.0:  # 2 voxels thick
			return VISOR if d.y < VISOR_TOP else INTACT  # the brow plate, in the shell's colour
		if v == EMPTY and e > 1.0 and d.y < r.y * 0.3:
			return INTACT  # the opening's edges, outside the band, closed: no skin at the temples
		return v
	if v != INTACT:
		return v
	if absf(d.x) < 1.5 and d.y > r.y * 0.45:
		return ACCENT  # the crown ridge
	if front and d.y >= r.y * 0.3 and d.y < r.y * 0.3 + 2.0:
		return ACCENT  # the brow plate over the visor
	if absf(d.x) > r.x - 2.5 and d.y > r.y * 0.1 and d.y < r.y * 0.45 and absf(d.z) < r.z * 0.45:
		return ACCENT  # temple plates (comms)
	return v


## Below the dome's base on a face guard helmet: the ring round the head (visor, cheeks, nape,
## mandible), `th` voxels thick, narrowing towards the chin, and under it a neck seal (NECK_R,
## Captain 2026-10-17: "a neck seal of sorts", no skin showing between helmet and collar).
static func _guard_ring_cell(d: Vector3, th: float) -> int:
	if d.y < GUARD_LOW:
		var e_neck := (d.x / NECK_R.x) ** 2 + ((d.z - NECK_R_Z) / NECK_R.y) ** 2
		var e_neck_in := (d.x / (NECK_R.x - 2.0)) ** 2 + ((d.z - NECK_R_Z) / (NECK_R.y - 2.0)) ** 2
		if e_neck <= 1.0:
			return INTERIOR if e_neck_in <= 1.0 else ACCENT
	var jaw := guard_jaw(d.y)
	var e_out := (d.x / jaw.x) ** 2 + (d.z / jaw.y) ** 2
	var e_in := (d.x / (jaw.x - th)) ** 2 + (d.z / (jaw.y - th)) ** 2
	if e_in <= 1.0:
		return INTERIOR
	var front := d.z <= -jaw.y * 0.55
	if front and absf(d.x) < 4.5 and d.y >= GUARD_LOW + 1.0 and d.y < VISOR_BOTTOM - 2.0 \
			and (d.x / (jaw.x + 3.0)) ** 2 + (d.z / (jaw.y + 3.0)) ** 2 <= 1.0 and e_out > 1.0:
		# The respirator block standing proud of the mask, vented across its face.
		var outer := (d.x / (jaw.x + 2.0)) ** 2 + (d.z / (jaw.y + 2.0)) ** 2 > 1.0
		return ACCENT if outer and absf(d.x) < 3.5 and int(floor(d.y)) % 2 == 0 else FACEPLATE
	if e_out > 1.0:
		return EMPTY
	if d.y >= -1.0:
		return ACCENT  # the seam where the guard meets the shell's rim: a part bolted on, not the shell
	if absf(d.x) > jaw.x - 1.5 and (d.y + HINGE_DOWN) ** 2 + d.z ** 2 <= HINGE_R * HINGE_R:
		return ACCENT  # the side hinge hubs it hangs from
	if front:
		if d.y >= VISOR_BOTTOM:
			var thin := (d.x / (jaw.x - 2.0)) ** 2 + (d.z / (jaw.y - 2.0)) ** 2 > 1.0  # a visor is 2 voxels thick
			if not thin:
				return EMPTY
			return VISOR
		return FACEPLATE if d.y >= GUARD_LOW else EMPTY  # the mask, over the nose, mouth and chin
	if d.z > jaw.y * 0.1:
		return FACEPLATE if d.y >= NAPE_LOW else EMPTY  # the nape guard, round the back
	return FACEPLATE if d.y >= GUARD_LOW else EMPTY  # cheek plates over the ears, down to the jaw line


static func _superellipse(v: Vector3) -> float:
	return pow(absf(v.x), 4.0) + pow(absf(v.y), 4.0) + pow(absf(v.z), 4.0)


static func _get_mesher(p_item: ItemData, p_cover := Color(0, 0, 0, 0), p_camo := "") -> VoxelMesherCubes:
	if not bool(p_item.stats.get("camo", false)):
		p_camo = ""
	var key := String(p_item.id) + (p_cover.to_html(false) if p_cover.a > 0.0 else "") + ("|" + p_camo if p_camo != "" else "")
	if not _meshers.has(key):
		var colour := p_cover if p_cover.a > 0.0 else Color(p_item.stats.get("color", "4f5a45"))
		# Camo paint on armour: the pattern's colours a shade darker than the cloth's (paint on
		# steel and ceramic, not fabric), its panel seams darker again.
		var pattern: Array = (VoxelArt.spec(p_camo).camo as Array).map(func(c: Variant) -> Color: return Color(c).darkened(0.12)) if p_camo != "" else []
		if not pattern.is_empty():
			colour = pattern[0]
		var palette := VoxelColorPalette.new()
		for i in pattern.size() - 1:
			palette.set_color([CAMO_B, CAMO_C, CAMO_D][i], pattern[i + 1])
		palette.set_color(EMPTY, Color(0, 0, 0, 0))
		palette.set_color(INTACT, colour)
		palette.set_color(SCARRED, Color("c9c2ae"))
		palette.set_color(INTERIOR, Color(0, 0, 0, 0))
		palette.set_color(ACCENT, colour.darkened(0.35))
		palette.set_color(VISOR, Color(p_item.stats.get("visor_color", "4d6f80")))  # tinted polycarbonate
		palette.set_color(GLOW, Color(p_item.stats.get("glow_color", "37c8d8")))  # a lit seam
		# A face guard's metal: on a helmet in its side's colours ("faction_color", GearRig) a darker
		# shade of the shell's colour (Captain, 2026-10-17: so it "doesn't pop so much"), else its own.
		var faction := p_cover.a > 0.0 and bool(p_item.stats.get("faction_color", false))
		palette.set_color(FACEPLATE, p_cover.darkened(0.3) if faction else Color(p_item.stats.get("plate_color", "3f4446")))
		var mesher := VoxelMesherCubes.new()
		mesher.palette = palette
		mesher.color_mode = VoxelMesherCubes.COLOR_MESHER_PALETTE
		_meshers[key] = mesher
	return _meshers[key]


static func _get_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.8
	return _material
