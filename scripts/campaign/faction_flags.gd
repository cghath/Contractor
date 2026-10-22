class_name FactionFlags
extends RefCounted
## Who holds a site, flown over it (terror groups, Captain 2026-10-20: "our terrorist
## organization faction needs to look more like one"; docs/terror_groups.md): a pole and a flag
## in the holder's fictional colours (factions.json "symbol": "field", "mark", "glyph") at the
## corner of each of its compounds, outposts, checkpoints, HQs and QRF bases. No writing and no
## real organisation's emblem: a field, and a mark drawn from plain blocks by its glyph. Visual
## only (no collision), built on every peer from the zone's controller (ZoneControl), the same
## everywhere. The cartels fly none: their mark is a stencilled board at the gate (SIGN_GLYPHS).

const NODE_NAME := "FactionFlags"
## The module types that fly a flag.
const SITES: Array[String] = ["compound", "outpost", "checkpoint", "hq", "qrf_base", "village"]
const POLE_H := 5.0
const FLAG := Vector2(1.5, 1.0)
const POLE_COLOUR := Color("3a3a36")
## Glyphs shown as a painted board on a short post instead of a flag (the cartels' marks).
const SIGN_GLYPHS: Array[String] = ["hook_wave", "kestrel"]

static var _materials := {}


## Builds the flags over `modules` (ZoneModules) for `faction` under `level`; returns the holder
## node (none for a faction without a symbol). `ground` maps a point to the ground (Callable).
static func build(level: Node3D, modules: Array, faction: String, ground: Callable) -> Node3D:
	var old := level.get_node_or_null(NODE_NAME)
	if old:
		old.free()
	var symbol: Dictionary = MissionRegistry.faction(faction).get("symbol", {})
	if symbol.is_empty():
		return null
	var holder := Node3D.new()
	holder.name = NODE_NAME
	holder.set_meta(&"faction", faction)
	level.add_child(holder)
	for m: Variant in modules:
		var module := m as ZoneModule
		if module == null or ZoneModules.base(module.type) not in SITES:
			continue
		var half: Vector2 = ZoneModules.HALF.get(module.type, Vector2(20, 20))
		var corner := module.position + Vector3(half.x - 3.0, 0.0, -half.y + 3.0)  # (the modules' holder sits at the level's origin)
		var at: Vector3 = ground.call(corner)
		holder.add_child(_flag(symbol, at, "Flag_" + module.module_id.validate_node_name()))
	return holder


static func _flag(symbol: Dictionary, at: Vector3, node_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = at
	var field := Color(String(symbol.get("field", "808080")))
	var mark := Color(String(symbol.get("mark", "ffffff")))
	var glyph := String(symbol.get("glyph", ""))
	var board := glyph in SIGN_GLYPHS
	var pole_h := 1.6 if board else POLE_H
	_box(root, Vector3(0.08, pole_h, 0.08), Vector3(0.0, pole_h * 0.5, 0.0), POLE_COLOUR)
	var size := FLAG * (0.8 if board else 1.0)
	var centre := Vector3(0.04 + size.x * 0.5, pole_h - size.y * 0.5 - 0.05, 0.0)
	if board:
		centre = Vector3(0.0, pole_h + size.y * 0.5 - 0.1, 0.0)
	_box(root, Vector3(size.x, size.y, 0.03), centre, field)
	for part: Array in _glyph(glyph):  # [offset (x, y) in flag units -0.5..0.5, size (x, y) in flag units]
		var off: Vector2 = part[0]
		var sz: Vector2 = part[1]
		_box(root, Vector3(sz.x * size.x, sz.y * size.y, 0.045), centre + Vector3(off.x * size.x, off.y * size.y, 0.0), mark)
	return root


## A glyph as plain blocks: [[offset, size], ...] in flag units.
static func _glyph(glyph: String) -> Array:
	match glyph:
		"arc_star":  # a red arc over a white star (the arc's colour is the mark; the star, the field's light)
			return [[Vector2(0.0, 0.22), Vector2(0.7, 0.1)], [Vector2(-0.3, 0.12), Vector2(0.1, 0.12)], [Vector2(0.3, 0.12), Vector2(0.1, 0.12)],
				[Vector2(0.0, -0.12), Vector2(0.2, 0.2)]]
		"mountain_river":
			return [[Vector2(0.0, 0.05), Vector2(0.12, 0.3)], [Vector2(0.0, -0.05), Vector2(0.36, 0.1)], [Vector2(0.0, -0.3), Vector2(0.8, 0.06)]]
		"hook_wave":
			return [[Vector2(-0.1, 0.05), Vector2(0.08, 0.5)], [Vector2(0.02, -0.18), Vector2(0.3, 0.08)], [Vector2(0.0, -0.36), Vector2(0.7, 0.06)]]
		"kestrel":
			return [[Vector2(0.0, 0.0), Vector2(0.16, 0.24)], [Vector2(-0.22, 0.08), Vector2(0.3, 0.07)], [Vector2(0.22, 0.08), Vector2(0.3, 0.07)]]
		"ridge":
			return [[Vector2(0.0, 0.25), Vector2(1.0, 0.12)], [Vector2(-0.2, -0.1), Vector2(0.18, 0.3)], [Vector2(0.15, -0.15), Vector2(0.24, 0.2)]]
		"peak_bars":
			return [[Vector2(0.0, 0.2), Vector2(0.14, 0.24)], [Vector2(0.0, 0.05), Vector2(0.36, 0.08)], [Vector2(0.0, -0.15), Vector2(0.8, 0.06)],
				[Vector2(0.0, -0.27), Vector2(0.8, 0.06)], [Vector2(0.0, -0.39), Vector2(0.8, 0.06)]]
		"star_ring":
			return [[Vector2(0.0, 0.0), Vector2(0.2, 0.2)], [Vector2(0.0, 0.28), Vector2(0.4, 0.06)], [Vector2(0.0, -0.28), Vector2(0.4, 0.06)]]
		"stripes":  # the US flag in blocks (D7): a blue canton on the field's blue, red and white bars
			return [[Vector2(0.1, 0.33), Vector2(0.8, 0.08)], [Vector2(0.1, 0.11), Vector2(0.8, 0.08)], [Vector2(0.0, -0.11), Vector2(1.0, 0.08)],
				[Vector2(0.0, -0.33), Vector2(1.0, 0.08)]]
		"chevron":
			return [[Vector2(-0.12, 0.0), Vector2(0.24, 0.1)], [Vector2(0.12, -0.08), Vector2(0.24, 0.1)]]
	return [[Vector2.ZERO, Vector2(0.4, 0.4)]]


static func _box(parent: Node3D, size: Vector3, at: Vector3, colour: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _material(colour)
	mi.position = at
	parent.add_child(mi)


static func _material(colour: Color) -> StandardMaterial3D:
	var key := colour.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.roughness = 0.95
		_materials[key] = m
	return _materials[key]
