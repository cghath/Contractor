class_name FrontGrid
extends RefCounted
## The moving front of an operation zone (docs/combined_arms.md 6.3, call 58; phase D3, cg_brief
## queue item 3.2): a CELLS x CELLS grid of CELL_M cells lined up with the 8,192 m zone (32 x 256 m),
## each owned by a side. Pure: Operations feeds it and replicates it; tests drive it directly.
##
## - Presence: each side's combat power (CP: its groups live and virtual, the OOB still to come, by
##   man and vehicle) in a cell and its eight neighbours, and the sites held in it (a standing site
##   is its expected garrison's CP).
## - A cell flips when the side that doesn't own it has flip_ratio x the owner's presence for flip_s
##   and no standing site of the owner's is left in it.
## - Objectives falling hand their cells over at once (server: set_cells); a phase done consolidates
##   every cell short of its line with no enemy presence (consolidate); the side falling back gives
##   back every cell past the last line it held with none of its own there (give_back).
## - The front line: for each column across the axis, the far edge of the friendly cells connected
##   to the friendly edge (a bypassed pocket on either side doesn't bend it). Recomputed when any
##   owner changes.
## - Replication: to_bytes / from_bytes (the whole grid: a late joiner), deltas as [cell, owner]
##   pairs (apply_delta). Saves as base64.
## Numbers in data/operations.json "front", Proposed.

const NONE := 0
const FRIENDLY := 1
const HOSTILE := 2

var cells := 32
var cell_m := 256.0
var half := 4096.0
## The axis of advance (a unit vector along x or z, OperationGen's), friendly edge to enemy depth.
var axis := Vector2(0, 1)
var flip_ratio := 2.0
var flip_s := 60.0
## Cell owners (FRIENDLY, HOSTILE), cells x cells, row by row (z, then x).
var owner := PackedByteArray()
## Since when the side that doesn't own each cell has had the presence to flip it (-1: not now).
var since := PackedFloat32Array()
## Bumps on every change of an owner (the line and the shares are worked out again).
var rev := 0
## Cells flipped by presence so far.
var flips := 0
## The last cycle's cost (µs).
var last_us := 0.0
## Each side's presence (CP) per cell, its own cell only, and the same over each cell's 3 x 3 (what
## a flip weighs): only valid this cycle where its stamp says so; read them with raw_at() and
## presence_near().
var raw_f := PackedFloat32Array()
var raw_h := PackedFloat32Array()
var nb_f := PackedFloat32Array()
var nb_h := PackedFloat32Array()

var _line := PackedVector2Array()
var _line_rev := -1
var _connected := PackedByteArray()
var _cycle_no := 0
var _touched := PackedInt32Array()  # cells with presence or a site in the last cycle
var _tstamp := PackedInt32Array()  # per cell: the cycle its raw_f/raw_h/_standing are from
var _pressured := PackedInt32Array()  # cells with since >= 0
var _reach := PackedInt32Array()  # cells the last cycle's presence reached (their 3 x 3)
var _rstamp := PackedInt32Array()  # per cell: the cycle its nb_f/nb_h are from
var _standing := PackedByteArray()  # per cell: 1 friendly site standing, 2 hostile, 3 both
var _offsets := PackedInt32Array()  # a cell's 3 x 3 as index offsets (away from the edges)


## A grid for an operation zone `def` (OperationGen's "op"): the friendly side holds every cell short
## of the start band's far end. `cfg`: data/operations.json "front".
static func for_zone(def: Dictionary, cfg: Dictionary = {}) -> FrontGrid:
	var g := FrontGrid.new()
	var a: Array = (def.get("op", {}) as Dictionary).get("axis", [0, 1])
	g.setup(float(def.get("size_m", 8192.0)), int(cfg.get("cells", 32)), Vector2(float(a[0]), float(a[1])),
		OperationGen.band_range(def, "start").y if OperationGen.is_operation(def) else 0.0)
	g.flip_ratio = float(cfg.get("flip_ratio", 2.0))
	g.flip_s = float(cfg.get("flip_s", 60.0))
	return g


## `size_m` square, `n` x `n` cells, `p_axis` the way of advance; the friendly side holds the cells
## whose middle is short of `start_m` along it.
func setup(size_m: float, n: int, p_axis: Vector2, start_m: float) -> void:
	cells = maxi(n, 2)
	half = size_m * 0.5
	cell_m = size_m / cells
	axis = p_axis.normalized() if p_axis.length() > 0.01 else Vector2(0, 1)
	owner = PackedByteArray()
	owner.resize(cells * cells)
	since = PackedFloat32Array()
	since.resize(cells * cells)
	since.fill(-1.0)
	raw_f = PackedFloat32Array()
	raw_f.resize(cells * cells)
	raw_h = PackedFloat32Array()
	raw_h.resize(cells * cells)
	nb_f = PackedFloat32Array()
	nb_f.resize(cells * cells)
	nb_h = PackedFloat32Array()
	nb_h.resize(cells * cells)
	_reach = PackedInt32Array()
	_rstamp = PackedInt32Array()
	_rstamp.resize(cells * cells)
	_tstamp = PackedInt32Array()
	_tstamp.resize(cells * cells)
	_cycle_no = 0
	_offsets = PackedInt32Array([-cells - 1, -cells, -cells + 1, -1, 0, 1, cells - 1, cells, cells + 1])
	_touched = PackedInt32Array()
	_pressured = PackedInt32Array()
	_standing = PackedByteArray()
	_standing.resize(cells * cells)
	for i in cells * cells:
		owner[i] = FRIENDLY if along_of(i) < start_m else HOSTILE
	rev += 1


# --- Geometry --------------------------------------------------------------------------------------

## The cell holding `p` (x, z), clamped to the grid.
func index_of(p: Vector2) -> int:
	var cx := clampi(floori((p.x + half) / cell_m), 0, cells - 1)
	var cz := clampi(floori((p.y + half) / cell_m), 0, cells - 1)
	return cz * cells + cx


func centre(i: int) -> Vector2:
	return Vector2((i % cells + 0.5) * cell_m - half, (i / cells + 0.5) * cell_m - half)


## How far cell `i`'s middle is along the axis from the friendly edge (m).
func along_of(i: int) -> float:
	return axis.dot(centre(i)) + half


## The owner of the cell holding `p`.
func owner_at(p: Vector2) -> int:
	return owner[index_of(p)]


## Cell (along index, lateral index) -> its index: along 0 at the friendly edge.
func _cell_at(a: int, l: int) -> int:
	var cx := 0
	var cz := 0
	if absf(axis.y) >= absf(axis.x):
		cz = a if axis.y > 0.0 else cells - 1 - a
		cx = l
	else:
		cx = a if axis.x > 0.0 else cells - 1 - a
		cz = l
	return cz * cells + cx


# --- The cycle ------------------------------------------------------------------------------------

## One cycle at time `t`: `presence` [{"pos": Vector2 (x, z), "side": FRIENDLY|HOSTILE, "cp"}] and
## `sites` [{"pos", "side", "cp", "standing"}] (a standing site adds its CP and keeps its cell from
## flipping away from its side). Returns the cells that flipped. Each cell's presence is spread onto
## its 3 x 3 once (nb_f, nb_h), so a cell is weighed in one step; only cells some presence reaches,
## and those already under pressure, are looked at.
func cycle(presence: Array, sites: Array, t: float) -> PackedInt32Array:
	var started := Time.get_ticks_usec()
	var out := PackedInt32Array()
	_cycle_no += 1
	var cyc := _cycle_no
	_touched = PackedInt32Array()
	_reach = PackedInt32Array()
	var n := cells
	var inv := 1.0 / cell_m
	for e: Dictionary in presence:
		var p: Vector2 = e.pos
		var i := clampi(floori((p.y + half) * inv), 0, n - 1) * n + clampi(floori((p.x + half) * inv), 0, n - 1)
		if _tstamp[i] != cyc:
			_tstamp[i] = cyc
			raw_f[i] = 0.0
			raw_h[i] = 0.0
			_standing[i] = 0
			_touched.append(i)
		if int(e.side) == FRIENDLY:
			raw_f[i] += float(e.cp)
		else:
			raw_h[i] += float(e.cp)
	for st: Dictionary in sites:
		if not bool(st.get("standing", true)):
			continue
		var p: Vector2 = st.pos
		var i := clampi(floori((p.y + half) * inv), 0, n - 1) * n + clampi(floori((p.x + half) * inv), 0, n - 1)
		if _tstamp[i] != cyc:
			_tstamp[i] = cyc
			raw_f[i] = 0.0
			raw_h[i] = 0.0
			_standing[i] = 0
			_touched.append(i)
		if int(st.side) == FRIENDLY:
			raw_f[i] += float(st.cp)
		else:
			raw_h[i] += float(st.cp)
		_standing[i] = _standing[i] | int(st.side)
	# Spread each touched cell onto its 3 x 3 (offsets away from the edges, bounds at them).
	for i in _touched:
		var f := raw_f[i]
		var h := raw_h[i]
		var cx := i % n
		var cz := i / n
		if cx > 0 and cx < n - 1 and cz > 0 and cz < n - 1:
			for o in _offsets:
				var j := i + o
				if _rstamp[j] != cyc:
					_rstamp[j] = cyc
					nb_f[j] = f
					nb_h[j] = h
					_reach.append(j)
				else:
					nb_f[j] += f
					nb_h[j] += h
			continue
		for z in range(maxi(cz - 1, 0), mini(cz + 1, n - 1) + 1):
			for x in range(maxi(cx - 1, 0), mini(cx + 1, n - 1) + 1):
				var j := z * n + x
				if _rstamp[j] != cyc:
					_rstamp[j] = cyc
					nb_f[j] = f
					nb_h[j] = h
					_reach.append(j)
				else:
					nb_f[j] += f
					nb_h[j] += h
	var cand := _reach
	if not _pressured.is_empty():
		cand = _reach.duplicate()
		for j in _pressured:
			if since[j] >= 0.0 and _rstamp[j] != cyc:
				cand.append(j)
	_pressured = PackedInt32Array()
	for j in cand:
		var own := owner[j]
		var here := _rstamp[j] == cyc
		var att := 0.0
		var dfn := 0.0
		if here:
			att = nb_h[j] if own == FRIENDLY else nb_f[j]
			dfn = nb_f[j] if own == FRIENDLY else nb_h[j]
		if att > 0.0 and att >= flip_ratio * dfn and (standing_at(j) & own) == 0:
			if since[j] < 0.0:
				since[j] = t
				_pressured.append(j)
			elif t - since[j] >= flip_s:
				owner[j] = HOSTILE if own == FRIENDLY else FRIENDLY
				since[j] = -1.0
				flips += 1
				out.append(j)
			else:
				_pressured.append(j)
		else:
			since[j] = -1.0
	if not out.is_empty():
		rev += 1
	last_us = float(Time.get_ticks_usec() - started)
	return out


## `side`'s presence (CP) round cell `i` (its 3 x 3) in the last cycle.
func presence_near(i: int, side: int) -> float:
	if _rstamp.is_empty() or _rstamp[i] != _cycle_no or _cycle_no == 0:
		return 0.0
	return nb_f[i] if side == FRIENDLY else nb_h[i]


## `side`'s presence (CP) in cell `i` itself in the last cycle.
func raw_at(i: int, side: int) -> float:
	if _tstamp.is_empty() or _tstamp[i] != _cycle_no or _cycle_no == 0:
		return 0.0
	return raw_f[i] if side == FRIENDLY else raw_h[i]


## The sides whose site stands in cell `i` (1 friendly, 2 hostile, 3 both) in the last cycle.
func standing_at(i: int) -> int:
	if _tstamp.is_empty() or _tstamp[i] != _cycle_no or _cycle_no == 0:
		return 0
	return _standing[i]


# --- Changes from outside the presence rule --------------------------------------------------------

## Objectives fell: `list` cells to `side` at once (no wait). Returns those that changed.
func set_cells(list: PackedInt32Array, side: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in list:
		if i >= 0 and i < owner.size() and owner[i] != side:
			owner[i] = side
			since[i] = -1.0
			out.append(i)
	if not out.is_empty():
		rev += 1
	return out


## The cells within `radius_m` of `p` (x, z): what an objective falling there hands over.
func cells_within(p: Vector2, radius_m: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var c := index_of(p)
	var reach := ceili(radius_m / cell_m)
	var cx := c % cells
	var cz := c / cells
	for z in range(maxi(cz - reach, 0), mini(cz + reach + 1, cells)):
		for x in range(maxi(cx - reach, 0), mini(cx + reach + 1, cells)):
			var i := z * cells + x
			if i == c or centre(i).distance_to(p) <= radius_m + cell_m * 0.5:
				out.append(i)
	return out


## A phase done: every cell short of `line_m` along the axis with no presence of the other side
## (last cycle) and no standing site of it goes to `side`. Returns those that changed.
func consolidate(line_m: float, side: int) -> PackedInt32Array:
	var other := HOSTILE if side == FRIENDLY else FRIENDLY
	var list := PackedInt32Array()
	for i in cells * cells:
		if owner[i] != side and along_of(i) < line_m and presence_near(i, other) <= 0.0 and (standing_at(i) & other) == 0:
			list.append(i)
	return set_cells(list, side)


## The friendly side falls back to `line_m`: every friendly cell past it with no friendly presence
## goes back to the enemy. Returns those that changed.
func give_back(line_m: float) -> PackedInt32Array:
	var list := PackedInt32Array()
	for i in cells * cells:
		if owner[i] == FRIENDLY and along_of(i) >= line_m and presence_near(i, FRIENDLY) <= 0.0:
			list.append(i)
	return set_cells(list, HOSTILE)


# --- Reading ---------------------------------------------------------------------------------------

## The share of the zone `side` holds (0..1).
func share(side: int) -> float:
	var n := 0
	for o in owner:
		if o == side:
			n += 1
	return float(n) / maxf(owner.size(), 1.0)


## The front line (x, z): for each column across the axis, the far edge of the friendly cells
## connected to the friendly edge. CELLS points, from the axis's left to its right.
func front_line() -> PackedVector2Array:
	if _line_rev == rev:
		return _line
	_line_rev = rev
	_flood()
	_line = PackedVector2Array()
	var left := Vector2(-axis.y, axis.x)
	for l in cells:
		var reach := -1
		for a in cells:
			if _connected[_cell_at(a, l)] == 1:
				reach = a
		var c := centre(_cell_at(maxi(reach, 0), l))
		var across := left.dot(c)
		var along_m := (reach + 1) * cell_m  # the far edge of the furthest connected cell
		_line.append(axis * (along_m - half) + left * across)
	return _line


## How far the front line is along the axis on average (m from the friendly edge).
func front_m() -> float:
	var pts := front_line()
	var sum := 0.0
	for p in pts:
		sum += axis.dot(p) + half
	return sum / maxf(pts.size(), 1.0)


## Friendly cells connected (4-way) to a friendly cell on the friendly edge.
func _flood() -> void:
	_connected = PackedByteArray()
	_connected.resize(cells * cells)
	var queue := PackedInt32Array()
	for l in cells:
		var i := _cell_at(0, l)
		if owner[i] == FRIENDLY:
			_connected[i] = 1
			queue.append(i)
	var k := 0
	while k < queue.size():
		var i := queue[k]
		k += 1
		var cx := i % cells
		var cz := i / cells
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var x := cx + d.x
			var z := cz + d.y
			if x < 0 or z < 0 or x >= cells or z >= cells:
				continue
			var j := z * cells + x
			if owner[j] == FRIENDLY and _connected[j] == 0:
				_connected[j] = 1
				queue.append(j)


# --- Saves and replication ------------------------------------------------------------------------

func to_bytes() -> PackedByteArray:
	return owner.duplicate()


## The owners from `bytes` (a whole grid); false if it doesn't fit this grid.
func from_bytes(bytes: PackedByteArray) -> bool:
	if bytes.size() != cells * cells:
		return false
	owner = bytes.duplicate()
	since.fill(-1.0)
	_pressured = PackedInt32Array()
	rev += 1
	return true


func to_save() -> String:
	return Marshalls.raw_to_base64(owner)


func from_save(text: String) -> bool:
	return text != "" and from_bytes(Marshalls.base64_to_raw(text))


## `cells_changed` as [cell, owner, cell, owner, ...] (what a client gets after a cycle).
func delta(cells_changed: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in cells_changed:
		out.append(i)
		out.append(owner[i])
	return out


## Applies a delta of [cell, owner] pairs.
func apply_delta(pairs: PackedInt32Array) -> void:
	var k := 0
	while k + 1 < pairs.size():
		var i := pairs[k]
		if i >= 0 and i < owner.size():
			owner[i] = pairs[k + 1]
		k += 2
	rev += 1
