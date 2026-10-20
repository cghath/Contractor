class_name LhdLayout
extends RefCounted
## The walkable LHD's plan (docs/lhd_home.md section 1): where everything aboard stands and the
## voxel boxes it's built of. Pure; LhdLevel builds it and LhdNav bakes it.
##
## Ship space is the level's: the origin is the middle of the hangar floor, -z is the bow, +x is
## starboard, y up. The hangar deck is the level's flat ground (y 0); the flight deck's top is
## DECK_Y above it and the waterline WATERLINE_Y below, so the flight deck stands 18 m over the
## water like the offshore LHD (LhdArt.DECK_M). The ship is shorter than the offshore art
## (FLIGHT_DECK_LEN, not LhdArt.LENGTH_M): all of it sits in one voxel world a player's viewer
## loads whole (VoxelWorld builds its structures once their whole area is loaded).
##
## The FOB's terminals, stash and muster line are BaseFob's (LhdLevel puts one at FOB_ORIGIN with
## fob_layout()), so the armory floor is BaseArmory's slots, FOB_ORIGIN away: the armory sits port
## side forward, its overflow racks running aft along the port side. Proposed layout.

const BEAM := 32.0
const HALF_BEAM := 16.0
const FLIGHT_DECK_LEN := 160.0
## The hangar: inside the hull's sides (WALL_T thick), between its two bulkheads, HANGAR_H clear.
const WALL_T := 0.4
const HANGAR := Rect2(-15.6, -48.0, 31.2, 96.0)
const HANGAR_H := 6.6
const DECK_Y := 7.0
const DECK_T := DECK_Y - HANGAR_H
const WATERLINE_Y := -11.0
const DRAFT := 8.0
## The hull narrows to the bow over BOW_LEN at the fore end, in BOW_STEPS steps.
const BOW_LEN := 16.0
const BOW_STEPS := 4
const BOW_TIP_HALF := 4.0
## Railings round the flight deck's edge and the stairwells.
const RAIL_H := 1.1
const RAIL_T := 0.1
## The flight deck is built in pieces at most this long (VoxelWorld stamps a box at a time).
const PIECE_M := 20.0

## The FOB's node (BaseFob) stands here: the armory floor's slots (BaseArmory) come out port
## side forward, in the armory compartment.
const FOB_ORIGIN := Vector3(0.0, 0.0, -18.0)
## The compartments: [name, Rect2 (x, z) of its outside walls, door wall ("fore", "aft", "port",
## "starboard"), door's [from, to] along that wall, its material]. Walls COMPARTMENT_H high,
## roofed. The armory's matches the FOB's (BaseFob._hut) FOB_ORIGIN away, its port wall the hull's.
const COMPARTMENT_H := 3.0
const ARMORY := Rect2(-15.6, -34.2, 9.8, 8.8)
const MEDBAY := Rect2(5.8, -34.2, 9.8, 8.8)
const HIRING := Rect2(8.0, -22.0, 7.6, 7.0)
const COMPARTMENTS := [
	["armory", ARMORY, "aft", [-12.4, -10.8]],
	["medbay", MEDBAY, "aft", [10.2, 11.8]],
	["hiring", HIRING, "port", [-19.3, -17.7]],
]
## The island, starboard on the flight deck, forward of the starboard stair: the ops room at deck
## level (door to port, onto the deck), the bridge block over it, the mast.
const ISLAND := Rect2(8.5, -32.0, 7.1, 14.0)
const OPS_DOOR := [-26.0, -24.4]
const ISLAND_TOP := 9.0  # the bridge block's height over the ops room
const MAST_H := 8.0

## The stairs between the decks: the house stair (BuildingGen.STAIR_RISE, STAIR_TREAD), 2.4 m
## wide against the hull, from its foot up to the flight deck. "x": [from, to]; "foot": z of the
## first step's near edge; "dir": -1 climbs forward (to -z), 1 climbs aft.
const STAIR_RISE := BuildingGen.STAIR_RISE
const STAIR_TREAD := BuildingGen.STAIR_TREAD
const STAIRS := [
	{"name": "starboard", "x": [13.1, 15.5], "foot": 4.0, "dir": -1},
	{"name": "port", "x": [-15.5, -13.1], "foot": 14.0, "dir": 1},
]
## A stairwell is open over the steps from this far below the flight deck up (head room).
const STAIRWELL_BELOW_M := 3.2
## and this much wider than the stair on its open side.
const STAIRWELL_MARGIN_M := 0.4

## Where players come aboard (spawn and respawn): the hangar, aft of the muster line.
const SPAWNS: Array[Vector3] = [Vector3(-3, 0.1, 4), Vector3(-1, 0.1, 4), Vector3(1, 0.1, 4), Vector3(3, 0.1, 4)]
## The muster line, athwartships across the hangar's middle, facing aft (towards the spawns).
const MUSTER_ORIGIN := Vector3(-5.6, 0.1, -8.0)
const MUSTER_STEP := Vector3(1.4, 0.0, 0.0)
const MUSTER_ROWS := Vector3(0.0, 0.0, 1.8)
## The terminals (BaseTerminal kinds), ship space: [kind, feet, facing (y degrees)].
const TERMINALS := [
	[&"armory", Vector3(-14.0, 0, -24.6), 0.0],
	[&"shop", Vector3(-7.0, 0, -24.6), 0.0],
	[&"stores", Vector3(-4.0, 0, -27.0), 90.0],
	[&"medbay", Vector3(8.0, 0, -30.0), 90.0],
	[&"hiring", Vector3(12.5, 0, -18.5), -90.0],
	[&"ops", Vector3(12.0, DECK_Y, -25.2), 90.0],
	[&"motor_pool", Vector3(10.0, 0, 13.0), 0.0],
]
## The vehicle park: the hangar aft, bays two abreast facing the bow, the motor pool's vehicles
## parked in them as props (as many as there are bays).
const PARK := Rect2(-12.0, 16.0, 24.0, 31.0)
const BAYS: Array[Vector3] = [Vector3(-6, 0, 22), Vector3(6, 0, 22), Vector3(-6, 0, 31.5), Vector3(6, 0, 31.5), Vector3(-6, 0, 41), Vector3(6, 0, 41)]
## The flight deck's helicopters (props) on their spots, port side: [model, position, yaw degrees].
const DECK_HELIS := [["uh60", Vector3(-6, DECK_Y, -50), 0.0], ["uh60", Vector3(-6, DECK_Y, -6), 0.0], ["ah1z", Vector3(-6, DECK_Y, 40), 0.0]]


## The FOB's layout in BaseFob's own space (BaseFob.layout), from the ship's.
static func fob_layout() -> Dictionary:
	var terminals: Array = []
	for t: Array in TERMINALS:
		terminals.append([t[0], (t[1] as Vector3) - FOB_ORIGIN, t[2]])
	var spawns: Array = []
	for p: Vector3 in SPAWNS:
		spawns.append(p - FOB_ORIGIN)
	var ship := ship_rect()
	return {"terminals": terminals, "spawns": spawns, "muster_origin": MUSTER_ORIGIN - FOB_ORIGIN, "muster_step": MUSTER_STEP,
		"muster_rows": MUSTER_ROWS, "muster_per_row": BaseFob.MUSTER_PER_ROW, "muster_max": BaseFob.MUSTER_MAX, "muster_facing": PI,
		"holds": Rect2(ship.position - Vector2(FOB_ORIGIN.x, FOB_ORIGIN.z), ship.size)}


## The hull's footprint (x, z): the flight deck's.
static func ship_rect() -> Rect2:
	return Rect2(-HALF_BEAM, -FLIGHT_DECK_LEN * 0.5, BEAM, FLIGHT_DECK_LEN)


## Whether (x, z) is on the hangar deck's floor, inside the hangar.
static func in_hangar(p: Vector3) -> bool:
	return HANGAR.has_point(Vector2(p.x, p.z))


## Whether `p` stands on the flight deck (on top of it, inside the hull's footprint).
static func on_flight_deck(p: Vector3) -> bool:
	return ship_rect().has_point(Vector2(p.x, p.z)) and p.y > DECK_Y - 0.3


## A stair's steps: [{"from": z, "to": z, "top": y}] in climbing order.
static func steps(stair: Dictionary) -> Array:
	var out: Array = []
	var n := stair_steps()
	var dir := int(stair.dir)
	for k in n:
		var z0 := float(stair.foot) + dir * k * STAIR_TREAD
		out.append({"from": z0, "to": z0 + dir * STAIR_TREAD, "top": DECK_Y * float(k + 1) / n})
	return out


## How many steps take a stair up to the flight deck.
static func stair_steps() -> int:
	return roundi(DECK_Y / STAIR_RISE)


## A stair's footprint (x, z): its steps.
static func stair_rect(stair: Dictionary) -> Rect2:
	var x0 := float(stair.x[0])
	var z_end := float(stair.foot) + int(stair.dir) * stair_steps() * STAIR_TREAD
	return Rect2(x0, minf(float(stair.foot), z_end), float(stair.x[1]) - x0, absf(z_end - float(stair.foot)))


## A stair's opening in the flight deck (x, z): over the steps from STAIRWELL_BELOW_M under the
## deck up, to the hull's side.
static func stairwell(stair: Dictionary) -> Rect2:
	var dir := int(stair.dir)
	var top_z := float(stair.foot) + dir * stair_steps() * STAIR_TREAD
	var open_k := ceili((DECK_Y - STAIRWELL_BELOW_M) / STAIR_RISE)  # the first step with too little head room under the deck
	var open_z := float(stair.foot) + dir * open_k * STAIR_TREAD
	var x0 := minf(float(stair.x[0]), float(stair.x[1]))
	var x1 := maxf(float(stair.x[0]), float(stair.x[1]))
	x0 = -HALF_BEAM if x0 < 0.0 else x0 - STAIRWELL_MARGIN_M
	x1 = HALF_BEAM if x1 > 0.0 else x1 + STAIRWELL_MARGIN_M
	return Rect2(x0, minf(open_z, top_z), x1 - x0, absf(top_z - open_z))


## For the navmesh bake (LhdNav): a ramp over each stair (BuildingGen.ramp_faces' way: a step's
## rise over the nosings, from the foot to the deck), triangles facing up.
static func ramp_faces() -> PackedVector3Array:
	var faces := PackedVector3Array()
	for st: Dictionary in STAIRS:
		var r := stair_rect(st)
		var y_foot := STAIR_RISE
		var y_top := DECK_Y + STAIR_RISE
		var foot := float(st.foot)
		var top := foot + int(st.dir) * stair_steps() * STAIR_TREAD
		var a := Vector3(r.position.x, y_foot, foot)
		var b := Vector3(r.end.x, y_foot, foot)
		var c := Vector3(r.end.x, y_top, top)
		var d := Vector3(r.position.x, y_top, top)
		if int(st.dir) < 0:
			faces.append_array([a, c, b, a, d, c])  # (wound to face up either way)
		else:
			faces.append_array([a, b, c, a, c, d])
	return faces


## The ship in voxel boxes ([from, to, VoxelWorld.Mat], ship metres), in build order: the hull's
## sides and ends above the hangar floor, the hangar's bulkheads, the flight deck (in pieces,
## open over the stairwells), its railings, the stairs, the compartments, the island, and the
## fittings (the medbay's bunks, the armory's racks, crates by the vehicle park).
static func boxes() -> Array:
	var out: Array = []
	var M := VoxelWorld.Mat
	var h := HANGAR_H
	var fore_end := -FLIGHT_DECK_LEN * 0.5
	var aft_end := FLIGHT_DECK_LEN * 0.5
	var bow_start := fore_end + BOW_LEN
	# The sides, from the bow's start to the stern, in pieces; the transom.
	for side: float in [-1.0, 1.0]:
		var x0 := HALF_BEAM - WALL_T if side > 0.0 else -HALF_BEAM
		var z := bow_start
		while z < aft_end - 0.01:
			var z1 := minf(z + PIECE_M * 2.0, aft_end)
			out.append([Vector3(x0, 0, z), Vector3(x0 + WALL_T, h, z1), M.STEEL])
			z = z1
	out.append([Vector3(-HALF_BEAM, 0, aft_end - WALL_T), Vector3(HALF_BEAM, h, aft_end), M.STEEL])
	# The bow: the sides step in to the tip.
	var half := HALF_BEAM
	for i in BOW_STEPS:
		var z0 := bow_start - i * (BOW_LEN / BOW_STEPS)
		var z1 := z0 - BOW_LEN / BOW_STEPS
		var next := HALF_BEAM - (HALF_BEAM - BOW_TIP_HALF) * float(i + 1) / BOW_STEPS
		for side: float in [-1.0, 1.0]:
			var lo := minf(side * next, side * half)
			var hi := maxf(side * next, side * half)
			out.append([Vector3(lo, 0, z0 - WALL_T), Vector3(hi, h, z0), M.STEEL])  # the step across
			var wx := side * next - (WALL_T if side > 0.0 else 0.0)
			out.append([Vector3(wx, 0, z1), Vector3(wx + WALL_T, h, z0), M.STEEL])  # the side, in
		half = next
	out.append([Vector3(-BOW_TIP_HALF, 0, fore_end), Vector3(BOW_TIP_HALF, h, fore_end + WALL_T), M.STEEL])
	# The hangar's bulkheads.
	out.append([Vector3(HANGAR.position.x, 0, HANGAR.position.y - WALL_T), Vector3(HANGAR.end.x, h, HANGAR.position.y), M.STEEL])
	out.append([Vector3(HANGAR.position.x, 0, HANGAR.end.y), Vector3(HANGAR.end.x, h, HANGAR.end.y + WALL_T), M.STEEL])
	# The flight deck, open over the stairwells.
	var wells: Array[Rect2] = []
	for st: Dictionary in STAIRS:
		wells.append(stairwell(st))
	for r: Rect2 in slab_pieces(ship_rect(), wells, PIECE_M):
		out.append([Vector3(r.position.x, HANGAR_H, r.position.y), Vector3(r.end.x, DECK_Y, r.end.y), M.STEEL])
	# Railings round the flight deck's edge, and round each stairwell (its open side and the end
	# away from the stair's top).
	var y := DECK_Y
	for side: float in [-1.0, 1.0]:
		var x0 := HALF_BEAM - RAIL_T if side > 0.0 else -HALF_BEAM
		var z := fore_end
		while z < aft_end - 0.01:
			var z1 := minf(z + PIECE_M * 2.0, aft_end)
			out.append([Vector3(x0, y, z), Vector3(x0 + RAIL_T, y + RAIL_H, z1), M.STEEL])
			z = z1
	out.append([Vector3(-HALF_BEAM, y, fore_end), Vector3(HALF_BEAM, y + RAIL_H, fore_end + RAIL_T), M.STEEL])
	out.append([Vector3(-HALF_BEAM, y, aft_end - RAIL_T), Vector3(HALF_BEAM, y + RAIL_H, aft_end), M.STEEL])
	for st: Dictionary in STAIRS:
		var w := stairwell(st)
		var inboard := w.position.x if float(st.x[0]) > 0.0 else w.end.x  # the well's side towards the middle
		var ix := inboard - RAIL_T if float(st.x[0]) > 0.0 else inboard
		out.append([Vector3(ix, y, w.position.y), Vector3(ix + RAIL_T, y + RAIL_H, w.end.y), M.STEEL])
		var low_end := w.end.y if int(st.dir) < 0 else w.position.y - RAIL_T  # the end the stair comes up from
		out.append([Vector3(w.position.x, y, low_end), Vector3(w.end.x, y + RAIL_H, low_end + RAIL_T), M.STEEL])
	# The stairs: solid steps up from the hangar floor.
	for st: Dictionary in STAIRS:
		for s: Dictionary in steps(st):
			var z0 := minf(float(s.from), float(s.to))
			var z1 := maxf(float(s.from), float(s.to))
			out.append([Vector3(float(st.x[0]), 0, z0), Vector3(float(st.x[1]), float(s.top), z1), M.STEEL])
	# The compartments.
	for c: Array in COMPARTMENTS:
		compartment(out, c[1], String(c[2]), c[3], COMPARTMENT_H, 0.0, M.SHEET_METAL)
	# The island: the ops room (door to port), the bridge block, the mast.
	compartment(out, ISLAND, "port", OPS_DOOR, 3.0, DECK_Y, M.SHEET_METAL)
	out.append([Vector3(ISLAND.position.x + 0.5, DECK_Y + 3.2, ISLAND.position.y + 1.0), Vector3(ISLAND.end.x, DECK_Y + 3.2 + ISLAND_TOP, ISLAND.end.y - 1.0), M.SHEET_METAL])
	var mx := ISLAND.get_center().x
	var mz := ISLAND.get_center().y
	out.append([Vector3(mx - 0.3, DECK_Y + 3.2 + ISLAND_TOP, mz - 0.3), Vector3(mx + 0.3, DECK_Y + 3.2 + ISLAND_TOP + MAST_H, mz + 0.3), M.STEEL])
	# Fittings: the medbay's bunks along its fore wall, the armory's racks on its fore wall,
	# the motor pool's crates and fuel by the vehicle park.
	for k in 3:
		var bx := MEDBAY.position.x + 1.2 + k * 2.8
		out.append([Vector3(bx, 0, MEDBAY.position.y + 0.6), Vector3(bx + 0.9, 0.6, MEDBAY.position.y + 2.6), M.STEEL])
	out.append([Vector3(ARMORY.position.x + 0.4, 0, ARMORY.position.y + 0.3), Vector3(ARMORY.end.x - 0.6, 1.8, ARMORY.position.y + 0.6), M.STEEL])
	for k in 3:
		var cz := PARK.position.y + 2.0 + k * 1.3
		out.append([Vector3(PARK.end.x + 0.8, 0, cz), Vector3(PARK.end.x + 2.0, 1.0, cz + 1.0), M.WOOD])
	return out


## A walled, roofed compartment on `rect` (x, z, outside walls), floor at `y0`, `top` high, with a
## doorway (2.2 m high) in its `door` wall between `door_at` [from, to] along that wall.
static func compartment(out: Array, rect: Rect2, door: String, door_at: Array, top: float, y0: float, mat: int) -> void:
	var t := 0.3
	var a := rect.position
	var b := rect.end
	var walls := {
		"fore": [Vector3(a.x, y0, a.y), Vector3(b.x, y0 + top, a.y + t), "x"],
		"aft": [Vector3(a.x, y0, b.y - t), Vector3(b.x, y0 + top, b.y), "x"],
		"port": [Vector3(a.x, y0, a.y), Vector3(a.x + t, y0 + top, b.y), "z"],
		"starboard": [Vector3(b.x - t, y0, a.y), Vector3(b.x, y0 + top, b.y), "z"],
	}
	for side: String in walls:
		var w: Array = walls[side]
		var lo: Vector3 = w[0]
		var hi: Vector3 = w[1]
		if side != door:
			out.append([lo, hi, mat])
			continue
		var d0 := float(door_at[0])
		var d1 := float(door_at[1])
		if w[2] == "x":
			out.append([lo, Vector3(d0, hi.y, hi.z), mat])
			out.append([Vector3(d1, lo.y, lo.z), hi, mat])
			out.append([Vector3(d0, y0 + 2.2, lo.z), Vector3(d1, hi.y, hi.z), mat])
		else:
			out.append([lo, Vector3(hi.x, hi.y, d0), mat])
			out.append([Vector3(lo.x, lo.y, d1), hi, mat])
			out.append([Vector3(lo.x, y0 + 2.2, d0), Vector3(hi.x, hi.y, d1), mat])
	out.append([Vector3(a.x, y0 + top, a.y), Vector3(b.x, y0 + top + 0.2, b.y), mat])


## `slab` (x, z) less `holes`, as rects no longer than `piece` along z: banded along z at the
## holes' ends, each band split along x round the holes that cross it.
static func slab_pieces(slab: Rect2, holes: Array[Rect2], piece: float) -> Array[Rect2]:
	var cuts: Array[float] = [slab.position.y, slab.end.y]
	for r: Rect2 in holes:
		cuts.append_array([clampf(r.position.y, slab.position.y, slab.end.y), clampf(r.end.y, slab.position.y, slab.end.y)])
	var z := slab.position.y + piece
	while z < slab.end.y:
		cuts.append(z)
		z += piece
	cuts.sort()
	var out: Array[Rect2] = []
	for i in cuts.size() - 1:
		var z0 := cuts[i]
		var z1 := cuts[i + 1]
		if z1 - z0 < 0.01:
			continue
		var mid := (z0 + z1) * 0.5
		var spans: Array = []
		for r: Rect2 in holes:
			if mid > r.position.y and mid < r.end.y:
				spans.append([r.position.x, r.end.x])
		spans.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
		var x := slab.position.x
		for s: Array in spans:
			if float(s[0]) > x + 0.01:
				out.append(Rect2(x, z0, float(s[0]) - x, z1 - z0))
			x = maxf(x, float(s[1]))
		if slab.end.x > x + 0.01:
			out.append(Rect2(x, z0, slab.end.x - x, z1 - z0))
	return out
