class_name BodyDevices
extends Node3D
## What treatment leaves on the body, in 0.5 cm voxels on the bone of the part it is on, so it
## moves with the limb: a tourniquet's strap high and tight above the wound with its windlass,
## red tip and a time tag written when it went on; a splint along a broken limb, strapped; a
## pelvic binder round the hips; a sling for a broken collarbone; an IV taped in a forearm or
## shin (or an IO in the sternum) with its line running to the bag hung on the casualty's
## chest, the bag emptying as it goes in; an NPA's flange at the nostril; a foil blanket
## wrapped round the body; and bone showing at an open fracture until it is dressed.
## (Dressings, gauze and chest seals over the holes are WoundMarks', see dressing_cells.)
##
## Drawn on every peer from the replicated treatment state (Vitals: tourniquets, wound_list,
## access, infusion, has_npa, the blanket flag), redrawn when it changes. Created by WoundMarks.

const VOXEL := 0.005
const UP := Vector3.UP
## Colours. A CAT-style tourniquet: black strap and windlass, a red tip, a white time label.
const STRAP := Color("1d1d1b")
const STRAP_EDGE := Color("2c2c29")
const WINDLASS := Color("2a2a2a")
const RED_TIP := Color("b3221c")
const TAG := Color("ecebe4")
const INK := Color("1f2a44")
## A SAM-style splint (orange out, blue in) and the dark cravats holding it.
const SPLINT_OUT := Color("d2662a")
const SPLINT_IN := Color("3e5c84")
const CRAVAT := Color("3b3d2f")
## A pelvic binder: black band, grey buckle.
const BINDER := Color("232323")
const BINDER_EDGE := Color("3a3a3a")
const BUCKLE := Color("8c8c86")
const SLING := Color("d6ccb0")
## IV and IO: a clear dressing, white tape, a hub coloured by its gauge, a clear line.
const TEGADERM := Color("d9e2e3")
const TAPE := Color("f1f0ea")
const LINE := Color("c7d4da")
const GAUGE_COLOURS := {10: Color("6b3fa0"), 12: Color("2f6db5"), 14: Color("e07b1f"), 16: Color("8a8d90"),
	18: Color("3b9b48"), 20: Color("e48aa8")}
const IO_PAD := Color("e9e7df")
const IO_HUB := Color("2e6fb0")
## The bag: clear plastic, saline (pale) or blood; a pressure bag's blue cuff.
const BAG_PLASTIC := Color("dde4e6")
const BAG_PORT := Color("c94a3c")
const SALINE := Color("b9d3df")
const BLOOD_BAG := Color("6b0f0f")
const PRESSURE_CUFF := Color("2f4f8f")
const NPA_COLOUR := Color("d9893f")
const NPA_HOLE := Color("3a1c10")
## A foil blanket's creased panels.
const FOIL := [Color("b9bec4"), Color("d3d7dc"), Color("9da3aa"), Color("c7cbd0")]
const BONE := Color("e6dfcc")
const BONE_DARK := Color("b8ab8c")
## How a tourniquet sits: TOURNIQUET_HIGH above the wound (CharacterModel's high and tight), at
## most TOP_MARGIN under the top of the limb segment; a second one TQ_GAP beside it.
const TOURNIQUET_HIGH := CharacterModel.TOURNIQUET_HIGH
const TOP_MARGIN := 0.035
const TQ_GAP := 0.045
const STRAP_TALL := 0.04
const RING_SAMPLES := 32
## How far off the skin each device lies (blood cells reach about 0.7 cm out).
const ON_SKIN := 0.006
## What's worn over the chest (a vest): the bag and an IO sit on its front instead.
const VEST_OUT := 0.055
## A 3 x 5 digit font for the time tag, rows top to bottom.
const DIGITS := ["111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
	"111100111001111", "111100111101111", "111001010010010", "111101111101111", "111101111001111"]
const LINE_SEGMENTS := 12
const SPLINT_BONES := {&"femur_l": &"thigh_l", &"femur_r": &"thigh_r", &"tibia_l": &"shin_l", &"tibia_r": &"shin_r",
	&"humerus_l": &"upper_arm_l", &"humerus_r": &"upper_arm_r", &"forearm_bones_l": &"forearm_l", &"forearm_bones_r": &"forearm_r",
	&"hand_l": &"forearm_l", &"hand_r": &"forearm_r"}

var model: CharacterModel
var vitals: Vitals
var body := ""
var _key := ""
var _bone_meshes: Dictionary = {}  # bone -> MultiMeshInstance3D
## What's on the body now: [{"kind", "part", "at" (rest pose)}], for tests and tools.
var _shown: Array[Dictionary] = []
## When each tourniquet went on (as seen here): part -> ["HHMM", ...], one per tourniquet.
var _tq_times: Dictionary = {}
var _bag_fill := -1.0
## The IV line, drawn in world space from the bag to the site (two bones apart): its ends in
## their bones' spaces, or {} with no line.
var _line: Dictionary = {}
var _line_mesh: MultiMeshInstance3D
var _built: Dictionary = {}  # what each device was built from -> its cells (_cached)
var _built_now: Dictionary = {}
static var _material: StandardMaterial3D


func setup(p_model: CharacterModel, p_vitals: Vitals, p_body: String) -> void:
	model = p_model
	vitals = p_vitals
	body = p_body
	vitals.changed.connect(_rebuild)
	set_process(false)
	_rebuild()


## The kinds of device on `part` now (&"tourniquet", &"splint", &"pelvic_binder", &"sling",
## &"iv", &"io", &"bag", &"npa", &"blanket", &"bone").
func devices_on(part: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for d: Dictionary in _shown:
		if d.part == part:
			out.append(d.kind)
	return out


## Every device of `kind` shown: [{"kind", "part", "at"}].
func shown(kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in _shown:
		if d.kind == kind:
			out.append(d)
	return out


## How full the hung bag is drawn (0..1), or -1 for no bag.
func bag_fill() -> float:
	return _bag_fill


## The time written on the tourniquets on `part` ("HHMM" each).
func tourniquet_times(part: StringName) -> Array:
	return _tq_times.get(part, [])


## Voxels drawn on `part`'s bone for devices (tests).
func voxels_on(part: StringName) -> int:
	var bone := model.part_node(part)
	var inst: MultiMeshInstance3D = _bone_meshes.get(bone)
	return inst.multimesh.visible_instance_count if inst and is_instance_valid(inst) else 0


func _rebuild() -> void:
	if not is_instance_valid(vitals) or not is_instance_valid(model):
		return
	var tqs := vitals.tourniquets()
	var wounds := vitals.wound_list()
	var line := vitals.access()
	var bag := vitals.infusion()
	var fill := -1.0
	if not bag.is_empty():
		fill = clampf(float(bag.left) / maxf(float(bag.ml), 1.0), 0.0, 1.0)
	var key := "%s|%s|%s|%s|%d|%s|%s|%s|%s" % [tqs, line, bag.get("item", ""), bag.get("ml", 0), roundi(fill * 20.0),
		vitals.has_npa(), _blanket(), vitals.is_dead(), _vest_worn()]
	for w: Dictionary in wounds:
		if w.kind == "fracture" or w.get("open", false) or (w.kind == "venous" and w.name != &""):
			key += "%s%s%s%s%s%s|" % [w.part, w.kind, w.name, w.treated, w.get("open", false), w.get("at")]
	if key == _key:
		return
	_key = key
	_bag_fill = fill
	_note_tourniquet_times(tqs)
	var cells := {}  # part -> Array of cells (rest pose)
	_shown.clear()
	_built_now = {}
	for part: StringName in tqs:
		_add(cells, part, &"tourniquet", _cached("tq%s%s%s%.3f" % [part, tqs[part].count, _tq_times.get(part), tourniquet_height(part, wounds)], _tourniquets.bind(part, int(tqs[part].count), wounds)))
	for w: Dictionary in wounds:
		if w.kind != "fracture":
			continue
		var bone := StringName(w.name)
		if w.treated:
			if bone == BodyMap.PELVIS_BONE:
				_add(cells, Vitals.PELVIS, &"pelvic_binder", _cached("binder", _binder))
			elif bone in BodyMap.CLAVICLE_BONES:
				_add(cells, Vitals.CHEST, &"sling", _cached("sling%s%s" % [bone, _vest_worn()], _sling.bind(String(bone).ends_with("_l"))))
			elif SPLINT_BONES.has(bone):
				_add(cells, SPLINT_BONES[bone], &"splint", _cached("splint%s" % SPLINT_BONES[bone], _splint.bind(SPLINT_BONES[bone])))
		if w.get("open", false) and not _open_dressed(wounds, w):
			_add(cells, w.part, &"bone", _cached("bone%s%s" % [w.part, w.get("at")], _bone_out.bind(w)))
	_line = {}
	if not line.is_empty():
		var site: Dictionary = _cached("site%s%s" % [line, _vest_worn()], _site.bind(line))
		_add(cells, StringName(line.part), &"io" if line.kind == "io" else &"iv", site.cells)
		var hang := _bag(line, bag, fill)
		if not bag.is_empty():  # the line runs up to the bag while one is hung
			_add(cells, Vitals.CHEST, &"bag", hang.cells)
			_line = {"from_part": Vitals.CHEST, "from": hang.port, "to_part": StringName(line.part), "to": site.port}
	if vitals.has_npa():
		_add(cells, Vitals.FACE, &"npa", _cached("npa", _npa))
	if _blanket():
		for part: StringName in [Vitals.CHEST, Vitals.UPPER_ARM_L, Vitals.UPPER_ARM_R, Vitals.FOREARM_L, Vitals.FOREARM_R,
				Vitals.THIGH_L, Vitals.THIGH_R, Vitals.SHIN_L, Vitals.SHIN_R]:
			_add(cells, part, &"blanket", _cached("blanket%s" % part, _blanket_shell.bind(part)))
	_built = _built_now
	_draw(cells)
	set_process(not _line.is_empty())
	if _line.is_empty() and _line_mesh:
		_line_mesh.multimesh.visible_instance_count = 0


## A device's cells, built by `build` only when `key` (what it's built from) is new: the shapes
## probe the body's voxels, too slow to redo on every change (the bag's level, another wound).
func _cached(key: String, build: Callable) -> Variant:
	var made: Variant = _built[key] if _built.has(key) else build.call()
	_built_now[key] = made
	return made


func _blanket() -> bool:
	return vitals._m().blanket


func _vest_worn() -> bool:
	var inventory: Variant = model.get_parent().get("inventory") if model.get_parent() else null
	return inventory is Inventory and (inventory as Inventory).slots.get(&"vest", &"") != &""


## The time each tourniquet on went on, as first seen here (the game clock where there is one).
func _note_tourniquet_times(tqs: Dictionary) -> void:
	for part: StringName in _tq_times.keys():
		if not tqs.has(part):
			_tq_times.erase(part)
	for part: StringName in tqs:
		var times: Array = _tq_times.get(part, [])
		while times.size() < int(tqs[part].count):
			times.append(_clock())
		times.resize(int(tqs[part].count))
		_tq_times[part] = times


static func _clock() -> String:
	var sky := DayNight.current()
	if sky and is_instance_valid(sky):
		var minutes := int(fposmod(sky.hour, 24.0) * 60.0)
		return "%02d%02d" % [minutes / 60, minutes % 60]
	var now := Time.get_time_dict_from_system()
	return "%02d%02d" % [now.hour, now.minute]


func _add(cells: Dictionary, part: StringName, kind: StringName, list: Array) -> void:
	if list.is_empty():
		return
	var into: Array = cells.get(part, [])
	into.append_array(list)
	cells[part] = into
	var centre := Vector3.ZERO
	for c: Array in list:
		centre += c[0]
	_shown.append({"kind": kind, "part": part, "at": centre / list.size()})


## A wound's dressing covers its open break: the bleeding "venous" wound named after the bone.
static func _open_dressed(wounds: Array, fracture: Dictionary) -> bool:
	for w: Dictionary in wounds:
		if w.kind == "venous" and w.name == fracture.name and w.part == fracture.part:
			return w.treated or w.get("packed", false)
	return false


# --- Shapes (rest pose, metres; each cell [centre, size, colour, basis]) ------------------

static func _cell(p: Vector3, size: Vector3, colour: Color, basis := Basis.IDENTITY) -> Array:
	return [p, size, colour, basis]


## Flat against the skin facing `n` (horizontal): x round the limb, y up, z out.
static func _facing(n: Vector3) -> Basis:
	var out := Vector3(n.x, 0.0, n.z)
	out = out.normalized() if out.length() > 0.001 else Vector3.FORWARD
	return Basis(UP.cross(out), UP, out)


## The skin round `part` at rest-pose height `y`, about the part's box centre: points every
## `step` metres round it, each [point, outward, tangent], starting at the front (-Z).
## `centre` overrides the box's centre (the torso's middle for a binder).
func _ring(part: StringName, y: float, step: float, centre: Variant = null) -> Array:
	var c: Vector3 = centre if centre is Vector3 else BodyMap.PART_BOXES[part][0][0]
	var mid := Vector3(c.x, y, c.z)
	var poly: Array[Vector3] = []
	for i in RING_SAMPLES:
		var a := TAU * i / RING_SAMPLES
		var dir := Vector3(sin(a), 0.0, -cos(a))
		var s: Variant = BodyVolume.surface(part, mid, dir, 0.2, body)
		if s is Vector3:
			poly.append(Vector3(s.x, y, s.z))
	var out: Array = []
	if poly.size() < 3:
		return out
	var carry := 0.0
	for i in poly.size():
		var a: Vector3 = poly[i]
		var b: Vector3 = poly[(i + 1) % poly.size()]
		var length := a.distance_to(b)
		if length < 0.0001:
			continue
		var t := (b - a) / length
		var d := carry
		while d < length:
			var p := a + t * d
			out.append([p, _facing(p - mid).z, t])
			d += step
		carry = d - length
	return out


## A band round `part` at `y`, `tall` high, `out` off the skin, one cell every `step`.
func _band(part: StringName, y: float, tall: float, out: float, colour: Color, step := VOXEL, edge := Color(0, 0, 0, 0), centre: Variant = null) -> Array:
	var cells: Array = []
	for r: Array in _ring(part, y, step, centre):
		var n: Vector3 = r[1]
		var basis := _facing(n)
		cells.append(_cell(r[0] + n * (out + VOXEL * 0.5), Vector3(step + 0.001, tall, VOXEL), colour, basis))
		if edge.a > 0.0:  # stitched edges, half a voxel proud
			for side: float in [-1.0, 1.0]:
				cells.append(_cell(r[0] + n * (out + VOXEL) + UP * side * (tall * 0.5 - VOXEL * 0.5), Vector3(step + 0.001, VOXEL, VOXEL), edge, basis))
	return cells


## Top and bottom of `part`'s box in the rest pose.
static func _span(part: StringName) -> Vector2:
	var box: Array = BodyMap.PART_BOXES[part][0]
	return Vector2(box[0].y - box[1].y * 0.5, box[0].y + box[1].y * 0.5)


## Where the tourniquets on `part` sit: TOURNIQUET_HIGH above the highest bleeding wound on the
## part itself, never higher than TOP_MARGIN under its top; as high as that goes for a wound
## further down the limb.
func tourniquet_height(part: StringName, wounds: Array) -> float:
	var span := _span(part)
	var top := span.y - TOP_MARGIN
	var y := top
	var found := -INF
	for w: Dictionary in wounds:
		if w.part == part and w.kind in ["arterial", "venous", "muscle", "junctional"] and w.get("at") is Vector3:
			found = maxf(found, Vector3(w.at).y)
	if found > -INF:
		y = minf(top, found + TOURNIQUET_HIGH)
	return clampf(y, span.x + STRAP_TALL, top)


func _tourniquets(part: StringName, count: int, wounds: Array) -> Array:
	var y := tourniquet_height(part, wounds)
	var cells: Array = []
	var times: Array = _tq_times.get(part, [])
	for i in count:
		var at := y - TQ_GAP * i if y - TQ_GAP * i > _span(part).x + STRAP_TALL else y + TQ_GAP * i
		cells.append_array(_tourniquet(part, at, times[i] if i < times.size() else "0000"))
	return cells


## One tourniquet round `part` at `y`: the strap, its windlass locked in the clip on the
## outside of the limb, the red tip, and the white time label written `time` ("HHMM").
func _tourniquet(part: StringName, y: float, time: String) -> Array:
	var ring := _ring(part, y, VOXEL)
	if ring.is_empty():
		return []
	var cells := _band(part, y, STRAP_TALL, ON_SKIN, STRAP, VOXEL, STRAP_EDGE)
	# The windlass on the outer side (away from the body's middle).
	var side := -1.0 if String(part).ends_with("_l") else 1.0
	var best := 0
	for i in ring.size():
		if (ring[i][1] as Vector3).x * side > (ring[best][1] as Vector3).x * side:
			best = i
	var p: Vector3 = ring[best][0]
	var n: Vector3 = ring[best][1]
	var basis := _facing(n)
	var proud := p + n * (ON_SKIN + VOXEL * 2.0)
	cells.append(_cell(proud, Vector3(0.024, 0.024, VOXEL * 2.0), STRAP_EDGE, basis))  # the clip
	cells.append(_cell(proud + n * VOXEL * 1.5, Vector3(0.09, 0.01, 0.01), WINDLASS, basis))  # the rod, along the strap
	cells.append(_cell(proud + n * VOXEL * 1.5 + basis.x * 0.045, Vector3(0.01, 0.015, 0.012), WINDLASS, basis))
	# The strap's free end, with its red tip, hanging off below the clip.
	cells.append(_cell(proud + basis.x * -0.02 - UP * 0.035, Vector3(0.025, 0.03, VOXEL), STRAP, basis))
	cells.append(_cell(proud + basis.x * -0.02 - UP * 0.055, Vector3(0.025, 0.012, VOXEL), RED_TIP, basis))
	# The time label just round from the windlass: a white strip, the time in a 3 x 5 font.
	var columns := 4 * 3 + 3 + 2
	var start := best + 8
	for col in columns:
		var r: Array = ring[(start + col) % ring.size()]
		var q: Vector3 = r[0]
		var m: Vector3 = r[1]
		var b := _facing(m)
		var digit := floori((col - 1) / 4.0)
		var dx := (col - 1) % 4
		for row in 7:
			var ink := false
			if col > 0 and col < columns - 1 and dx < 3 and row > 0 and row < 6 and digit < time.length():
				var glyph: String = DIGITS[int(time[digit])] if time[digit].is_valid_int() else "000000000000000"
				ink = glyph[(row - 1) * 3 + dx] == "1"
			var py := (3 - row) * VOXEL
			cells.append(_cell(q + m * (ON_SKIN + VOXEL * 1.5) + UP * py, Vector3(VOXEL + 0.0008, VOXEL, VOXEL), INK if ink else TAG, b))
	return cells


## A splint along `part`: two rails (outer side and back), orange out, blue showing at the
## edges, held by three cravats.
func _splint(part: StringName) -> Array:
	var span := _span(part)
	var c: Vector3 = BodyMap.PART_BOXES[part][0][0]
	var side := -1.0 if String(part).ends_with("_l") else 1.0
	var cells: Array = []
	var lo := span.x + 0.03
	var hi := span.y - 0.02
	for dir: Vector3 in [Vector3(side, 0, 0), Vector3.BACK]:
		var y := lo
		while y < hi:
			var s: Variant = BodyVolume.surface(part, Vector3(c.x, y, c.z), dir, 0.2, body)
			if s is Vector3:
				var basis := _facing(dir)
				var p: Vector3 = Vector3(s) + dir * (ON_SKIN + VOXEL * 0.5)
				cells.append(_cell(p, Vector3(0.05, 0.0105, VOXEL), SPLINT_IN, basis))
				cells.append(_cell(p + dir * VOXEL, Vector3(0.04, 0.0105, VOXEL), SPLINT_OUT, basis))
			y += 0.01
	for share: float in [0.2, 0.5, 0.8]:
		cells.append_array(_band(part, lerpf(lo, hi, share), 0.025, ON_SKIN + VOXEL * 2.0, CRAVAT, 0.01))
	return cells


## A pelvic binder round the hips (over the greater trochanters), its buckle at the front.
func _binder() -> Array:
	var centre := Vector3(0, 0.0, 0)
	var cells: Array = []
	for y: float in [0.875, 0.915, 0.955]:
		cells.append_array(_band(Vitals.PELVIS, y, 0.0405, 0.012, BINDER, 0.01, BINDER_EDGE if y != 0.915 else Color(0, 0, 0, 0), centre))
	var front: Variant = BodyVolume.surface(Vitals.PELVIS, Vector3(0, 0.915, 0), Vector3.FORWARD, 0.2, body)
	if front is Vector3:
		var basis := _facing(Vector3.FORWARD)
		cells.append(_cell(Vector3(front) + Vector3.FORWARD * 0.024, Vector3(0.05, 0.05, 0.01), BUCKLE, basis))
		cells.append(_cell(Vector3(front) + Vector3.FORWARD * 0.03, Vector3(0.03, 0.03, VOXEL), BINDER_EDGE, basis))
	return cells


## A broken collarbone's sling: a triangular bandage from the far shoulder down across the
## chest to the hurt side's waist.
func _sling(left: bool) -> Array:
	var side := -1.0 if left else 1.0
	var a := Vector3(-side * 0.12, 1.42, 0)
	var b := Vector3(side * 0.13, 1.08, 0)
	var cells: Array = []
	var out := ON_SKIN + (VEST_OUT if _vest_worn() else 0.0)
	for i in 24:
		var p := a.lerp(b, i / 23.0)
		var s: Variant = BodyVolume.surface(Vitals.CHEST if p.y > 1.18 else Vitals.ABDOMEN, p, Vector3.FORWARD, 0.2, body)
		if s is Vector3:
			var basis := _facing(Vector3.FORWARD).rotated(Vector3.FORWARD, side * 0.6)
			cells.append(_cell(Vector3(s) + Vector3.FORWARD * (out + VOXEL * 0.5), Vector3(0.06, 0.016, VOXEL), SLING, basis))
	return cells


## The IV or IO site: {"cells", "port" (where the line leaves it, rest pose)}.
func _site(line: Dictionary) -> Dictionary:
	var part := StringName(line.part)
	if line.kind == "io":
		var out := ON_SKIN + (VEST_OUT if _vest_worn() else 0.0)
		var s: Variant = BodyVolume.surface(Vitals.CHEST, Vector3(0, 1.36, 0), Vector3.FORWARD, 0.2, body)
		var p: Vector3 = (Vector3(s) if s is Vector3 else Vector3(0, 1.36, -0.11)) + Vector3.FORWARD * out
		var basis := _facing(Vector3.FORWARD)
		var cells: Array = []
		for gx in range(-5, 6):  # the round target patch, 5.5 cm across
			for gy in range(-5, 6):
				if gx * gx + gy * gy <= 26:
					cells.append(_cell(p + basis.x * gx * VOXEL + UP * gy * VOXEL, Vector3(VOXEL, VOXEL, VOXEL), IO_PAD, basis))
		for gx in range(-1, 2):  # the hub and its dome
			for gy in range(-1, 2):
				cells.append(_cell(p + basis.x * gx * VOXEL + UP * gy * VOXEL + Vector3.FORWARD * VOXEL * 1.5, Vector3(VOXEL, VOXEL, VOXEL * 2.0), IO_HUB, basis))
		return {"cells": cells, "port": p + Vector3.FORWARD * VOXEL * 3.0}
	var span := _span(part)
	var c: Vector3 = BodyMap.PART_BOXES[part][0][0]
	var arm := String(part).begins_with("forearm")
	var y := span.y - 0.07 if arm else lerpf(span.x, span.y, 0.62)  # inner forearm below the elbow, or the shin's front
	var side := -1.0 if String(part).ends_with("_l") else 1.0
	var dir := Vector3(-side * 0.5, 0, -1).normalized() if arm else Vector3.FORWARD
	var s: Variant = BodyVolume.surface(part, Vector3(c.x, y, c.z), dir, 0.2, body)
	var p: Vector3 = (Vector3(s) if s is Vector3 else Vector3(c.x, y, c.z)) + dir * ON_SKIN
	var basis := _facing(dir)
	var gauge := int(line.get("gauge", 18))
	var cells: Array = [
		_cell(p, Vector3(0.04, 0.05, VOXEL), TEGADERM, basis),  # the clear dressing
		_cell(p + dir * VOXEL + UP * 0.005, Vector3(0.01, 0.015, VOXEL * 2.0), GAUGE_COLOURS.get(gauge, GAUGE_COLOURS[18]), basis),  # the hub
		_cell(p + dir * VOXEL - UP * 0.012, Vector3(0.05, 0.01, VOXEL), TAPE, basis),
		_cell(p + dir * VOXEL + UP * 0.022, Vector3(0.05, 0.01, VOXEL), TAPE, basis),
	]
	for i in 4:  # the line looped once under the tape
		cells.append(_cell(p + dir * VOXEL * 1.5 + UP * (0.015 + i * VOXEL) + basis.x * 0.006 * sin(i * 1.4), Vector3(VOXEL, VOXEL, VOXEL), LINE, basis))
	return {"cells": cells, "port": p + dir * VOXEL * 2.0 + UP * 0.035}


## The bag hung on the casualty's chest (on the vest's front with one on), on the side away
## from the line: {"cells", "port" (its outlet, rest pose)}. Empty cells for no bag, the port
## still where the line goes up to.
func _bag(line: Dictionary, bag: Dictionary, fill: float) -> Dictionary:
	var arm_side := -1.0 if String(line.part).ends_with("_l") else 1.0
	var x := -arm_side * 0.1 if line.kind == "iv" else 0.1
	var s: Variant = BodyVolume.surface(Vitals.CHEST, Vector3(x, 1.33, 0), Vector3.FORWARD, 0.2, body)
	var skin: Vector3 = Vector3(s) if s is Vector3 else Vector3(x, 1.33, -0.11)
	var out := ON_SKIN + 0.01 + (VEST_OUT if _vest_worn() else 0.0)
	var ml := int(bag.get("ml", 500))
	var size := Vector3(0.07, 0.11, 0.015) if ml <= 250 else (Vector3(0.09, 0.15, 0.02) if ml <= 500 else Vector3(0.11, 0.2, 0.025))
	var centre := skin + Vector3.FORWARD * (out + size.z * 0.5)
	var basis := _facing(Vector3.FORWARD)
	var bottom := centre - UP * size.y * 0.5
	var port := bottom - UP * 0.015
	if bag.is_empty():
		return {"cells": [], "port": port}
	var liquid: Color = BLOOD_BAG if String(bag.item).begins_with("blood") else SALINE
	var cells: Array = []
	var full := snappedf(size.y * fill, VOXEL)
	if full > 0.0:
		cells.append(_cell(bottom + UP * full * 0.5, Vector3(size.x, full, size.z), liquid, basis))
	if full < size.y:  # the emptied plastic, collapsed flat
		var empty := size.y - full
		cells.append(_cell(bottom + UP * (full + empty * 0.5) + Vector3.BACK * size.z * 0.3, Vector3(size.x, empty, VOXEL), BAG_PLASTIC, basis))
	cells.append(_cell(bottom + UP * size.y + UP * 0.005, Vector3(size.x * 0.6, 0.01, VOXEL), BAG_PLASTIC, basis))  # the hanging tab
	cells.append(_cell(bottom - UP * 0.0075, Vector3(0.01, 0.015, 0.01), BAG_PORT, basis))  # the outlet
	if line.get("pressure", false):  # a pressure bag's cuff round it and its bulb
		cells.append(_cell(centre + Vector3.FORWARD * (size.z * 0.5 + VOXEL * 0.5), Vector3(size.x + 0.01, size.y * 0.8, VOXEL), PRESSURE_CUFF, basis))
		cells.append(_cell(centre + basis.x * (size.x * 0.5 + 0.015) - UP * size.y * 0.3, Vector3(0.02, 0.03, 0.02), PRESSURE_CUFF.darkened(0.3), basis))
	return {"cells": cells, "port": port}


## An NPA in the right nostril: its flange just under the nose tip.
func _npa() -> Array:
	var pivot := BodyVolume.pivot_at(Vitals.HEAD, body)
	var tip_z := INF
	var tip_y := pivot.y + 0.14
	var bottom := pivot.y + 0.13
	# Down the nose from its bridge, below the eyes (FaceArt: higher up, the brow ridge stands
	# out over the bridge's dip and would read as the tip): its tip, then where the face comes
	# back under it.
	for i in 20:
		var y := pivot.y + 0.165 - i * VOXEL
		var s: Variant = BodyVolume.surface(Vitals.FACE, Vector3(pivot.x, y, pivot.z), Vector3.FORWARD, 0.2, body)
		if not s is Vector3:
			continue
		if Vector3(s).z < tip_z - 0.001:
			tip_z = Vector3(s).z
			tip_y = y
		elif Vector3(s).z > tip_z + 0.004 and y < tip_y:
			bottom = y + VOXEL
			break
	if tip_z == INF:
		tip_z = pivot.z - 0.125
	var at := Vector3(pivot.x + 0.006, bottom - VOXEL * 0.5, tip_z - VOXEL)
	var basis := _facing(Vector3.FORWARD)
	return [
		_cell(at, Vector3(0.015, VOXEL, 0.01), NPA_COLOUR, basis),  # the flange
		_cell(at - UP * VOXEL * 0.7, Vector3(VOXEL, VOXEL * 0.5, VOXEL), NPA_HOLE, basis),
	]


## A foil blanket's shell round `part` (the whole torso for CHEST): creased panels a little off
## the body (further off the torso, over the vest and pack straps).
func _blanket_shell(part: StringName) -> Array:
	var span := _span(part)
	var centre: Variant = null
	var off := 0.02
	var panel := 0.06
	if part == Vitals.CHEST:
		span = Vector2(0.84, 1.44)
		centre = Vector3.ZERO
		off = 0.05
	var cells: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(part)
	var y := span.x + panel * 0.5
	while y < span.y:
		var probe := part
		if part == Vitals.CHEST:
			probe = Vitals.PELVIS if y < 1.0 else (Vitals.ABDOMEN if y < 1.18 else Vitals.CHEST)
		var ring := _ring(probe, y, panel, centre)
		for i in ring.size():
			var n: Vector3 = ring[i][1]
			# One sheet, not tiles (v0.7.1, the Captain: "looks like chain mail"): panels square
			# to the body, overlapping, the shade running in broad bands with a crease now and then.
			var shade: Color = FOIL[1] if (i / 6 + int(y / panel / 3.0)) % 2 == 0 else FOIL[3]
			if rng.randf() < 0.08:
				shade = FOIL[0]  # a crease
			cells.append(_cell(ring[i][0] + n * off, Vector3(panel * 1.35, panel * 1.15, VOXEL), shade, _facing(n)))
		y += panel
	return cells


## An open break: bone ends through the skin at the wound, jagged, darker at the broken end.
func _bone_out(w: Dictionary) -> Array:
	var part := StringName(w.part)
	var at: Variant = w.get("at")
	var c: Vector3 = BodyMap.PART_BOXES[part][0][0]
	if not at is Vector3:
		at = c + Vector3(0, 0, -0.05)
	var n := WoundMarks._outward(part, at)
	var s: Variant = BodyVolume.surface(part, at, n, 0.05, body)
	var p: Vector3 = Vector3(s) if s is Vector3 else Vector3(at)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s%s" % [part, at])
	var basis := _facing(n)
	var cells: Array = []
	for i in 6:
		var reach := (i + 1) * VOXEL * 0.8
		var q := p + n * reach + UP * rng.randf_range(-0.004, 0.006) + basis.x * rng.randf_range(-0.005, 0.005)
		cells.append(_cell(q, Vector3(VOXEL, VOXEL * rng.randf_range(1.0, 2.0), VOXEL), BONE_DARK if i == 5 or rng.randf() < 0.2 else BONE, basis))
	cells.append(_cell(p + n * VOXEL * 2.0 + UP * 0.006, Vector3(VOXEL, VOXEL, VOXEL), BONE, basis))
	return cells


# --- Drawing ------------------------------------------------------------------------------

func _draw(cells: Dictionary) -> void:
	var per_bone := {}
	for part: StringName in cells:
		var bone := model.part_node(part)
		if bone == null:
			continue
		var pivot := BodyVolume.pivot_at(part, body)
		var list: Array = per_bone.get(bone, [])
		for c: Array in cells[part]:
			list.append([c[0] - pivot, c[1], c[2], c[3]])
		per_bone[bone] = list
	for bone: Node3D in _bone_meshes.keys():
		if not per_bone.has(bone) and is_instance_valid(_bone_meshes[bone]):
			_bone_meshes[bone].multimesh.visible_instance_count = 0
	for bone: Node3D in per_bone:
		var list: Array = per_bone[bone]
		var inst: MultiMeshInstance3D = _bone_meshes.get(bone)
		if inst == null or not is_instance_valid(inst) or inst.multimesh.instance_count < list.size():
			if inst and is_instance_valid(inst):
				inst.name = "DevicesOld"  # (the new one takes its name now, not next frame)
				inst.queue_free()
			inst = multimesh_instance(maxi(64, list.size() + list.size() / 2))
			inst.name = "Devices"
			inst.layers = model.render_layers
			bone.add_child(inst, true)
			_bone_meshes[bone] = inst
		inst.transform = Transform3D(WoundMarks.fit_of(bone), Vector3.ZERO)  # widened with the build, as the part is
		var mm := inst.multimesh
		for i in list.size():
			var c: Array = list[i]
			mm.set_instance_transform(i, Transform3D(Basis(c[3]) * Basis.from_scale(c[1]), c[0]))
			mm.set_instance_color(i, c[2])
		mm.visible_instance_count = list.size()


## Keeps the devices widened with the body's build as it's drawn now (WoundMarks._refit).
func refit() -> void:
	for bone: Variant in _bone_meshes:
		if is_instance_valid(bone) and is_instance_valid(_bone_meshes[bone]):
			(_bone_meshes[bone] as Node3D).transform = Transform3D(WoundMarks.fit_of(bone), Vector3.ZERO)


## The IV line from the bag's outlet to the site, sagging a little between them (world space,
## moving with both bones).
func _process(_delta: float) -> void:
	if _line.is_empty():
		set_process(false)
		return
	var from_bone := model.part_node(_line.from_part)
	var to_bone := model.part_node(_line.to_part)
	if from_bone == null or to_bone == null:
		return
	var a: Vector3 = from_bone.global_transform * (WoundMarks.fit_of(from_bone) * (Vector3(_line.from) - BodyVolume.pivot_at(_line.from_part, body)))
	var b: Vector3 = to_bone.global_transform * (WoundMarks.fit_of(to_bone) * (Vector3(_line.to) - BodyVolume.pivot_at(_line.to_part, body)))
	if _line_mesh == null:
		_line_mesh = multimesh_instance(LINE_SEGMENTS)
		_line_mesh.name = "IVLine"
		_line_mesh.top_level = true
		_line_mesh.layers = model.render_layers
		add_child(_line_mesh)
		_line_mesh.global_transform = Transform3D.IDENTITY
	var mm := _line_mesh.multimesh
	var sag := minf(a.distance_to(b) * 0.15, 0.08)
	var last := a
	for i in LINE_SEGMENTS:
		var t := float(i + 1) / LINE_SEGMENTS
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		var d := p - last
		var length := d.length()
		var basis := Basis.IDENTITY
		if length > 0.0001:
			var z := d / length
			var x := z.cross(Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT).normalized()
			basis = Basis(x, z.cross(x), z)
		mm.set_instance_transform(i, Transform3D(basis * Basis.from_scale(Vector3(VOXEL, VOXEL, length + 0.001)), (last + p) * 0.5))
		mm.set_instance_color(i, LINE)
		last = p
	mm.visible_instance_count = LINE_SEGMENTS


## A box MultiMesh with per-instance colours (WoundMarks draws with the same).
static func multimesh_instance(count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = count
	mm.visible_instance_count = 0
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.7
	inst.material_override = _material
	return inst
