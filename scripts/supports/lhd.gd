class_name Lhd
extends Node3D
## Where the company's supports come from in a level (wave 5b, V4): the LHD offshore on a
## coastal zone, else the friendly FOB's side of the map (Captain: the LHD on the coast, the FOB
## inland; the LHD is the company's only base and is never attacked).
##
## install() (AavSupport.install, every peer) adds one node named "SupportOrigin" to the level,
## built the same everywhere from the zone definition (so clients and late joiners have it with
## no traffic), and registers it with Supports:
## - A zone whose terrain has a coast: this node, the LHD (LhdArt), lying parallel to the coast
##   "lhd_m" from the coast's edge (default half the shoreline's distance), but never nearer
##   the shore than OFFSHORE_M (ship_frame), and "lhd_along_m" along it;
##   Supports.register_origin(&"lhd", its "Deck" marker): helicopters (V3) start on its flight
##   deck; AAVs launch from its stern into the water (launch_transform).
## - Anywhere else: a plain marker on the ground FOB_INSET_M inside the map's edge on the FOB's
##   side (the zone's "fob_side", else the side nearest the default insertion point);
##   Supports.register_origin(&"fob", it). Ground supports drive in from that side (fob_entry).

const NODE_NAME := "SupportOrigin"
const SIDES := ["north", "south", "east", "west"]
## Swimming round the ship, an AAV keeps this far off its side (m, Proposed).
const CLEAR_M := 25.0
## Anchored offshore: the hull's shoreward side at least this far seaward of the shoreline at
## its nearest (m, Proposed: 150-250). Captain, 2026-10-14: on harbour_yard the LHD lay a few
## metres off the sand, "way too close to shore". A ship is moored at a quay or anchored out,
## never on the beach; a narrow sea puts it out past the zone's edge, over the apron's seabed.
const OFFSHORE_M := 200.0
## Water kept under the keel: the draft is the shallowest water under the hull less this (m, Proposed).
const KEEL_CLEAR_M := 0.5
## The hull's footprint is checked for water every this many metres along it (m).
const FOOTPRINT_STEP_M := 16.0

## &"lhd" or &"fob".
var kind := &"fob"
## The FOB's side of the map (inland), or the coast's side (the LHD).
var side := ""
var _area := Rect2()


## Every peer: the level's support origin (once). Returns it.
static func install(level: Node3D) -> Lhd:
	var have := level.get_node_or_null(NodePath(NODE_NAME)) as Lhd
	if have:
		return have
	var origin := Lhd.new()
	origin.name = NODE_NAME
	level.add_child(origin)
	var terrain: Variant = level.get(&"terrain")
	var def: Variant = level.get(&"def")
	var coast: Dictionary = (def as Dictionary).get("coast", {}) if def is Dictionary else {}
	if terrain is ZoneTerrain and (terrain as ZoneTerrain).has_coast():
		origin._place_ship(terrain as ZoneTerrain, coast)
	else:
		origin._place_fob(level, def if def is Dictionary else {})
	if origin.kind == &"lhd":
		Supports.register_origin(&"lhd", origin.get_node(^"LHD/Deck") as Node3D)
	else:
		Supports.register_origin(&"fob", origin)
	return origin


## The level's support origin (or null).
static func of(from: Node) -> Lhd:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NodePath(NODE_NAME)) as Lhd if lvl else null


func is_ship() -> bool:
	return kind == &"lhd"


func _place_ship(terrain: ZoneTerrain, coast: Dictionary) -> void:
	kind = &"lhd"
	side = terrain.coast_side
	var data: Dictionary = AavSupport.data().get("lhd", {})
	var frame := Lhd.ship_frame(terrain, coast)
	transform = frame.transform
	add_child(LhdArt.build(frame.length, frame.beam, float(data.get("deck_m", LhdArt.DECK_M)), frame.draft))


## Where the LHD lies on `terrain`'s coast (`coast`: the zone's "coast"), the same on every
## peer and in tests: {"transform" (the middle of the ship at the waterline, the bow along the
## coast), "length", "beam", "draft"}. Its centre line "lhd_m" from the coast's edge, pulled
## seaward (past the edge if need be) until the hull's shoreward side is OFFSHORE_M out from
## the shoreline's nearest point; the draft the data's, less where the water under the hull is
## shallower (a shallow preset sea: TerrainPresets "sea" depth_m), so the keel stays off the seabed.
static func ship_frame(terrain: ZoneTerrain, coast: Dictionary) -> Dictionary:
	var data: Dictionary = AavSupport.data().get("lhd", {})
	var length := float(data.get("length_m", LhdArt.LENGTH_M))
	var beam := float(data.get("beam_m", LhdArt.BEAM_M))
	var half := terrain.size_m * 0.5
	var out := terrain.seaward()
	var along := Vector3(absf(out.z), 0.0, absf(out.x))  # x along a north or south coast, z along an east or west one
	var from_edge := minf(float(coast.get("lhd_m", terrain.shore_m * 0.5)), terrain.shore_m - OFFSHORE_M - beam * 0.5)
	var at := out * (half - from_edge) + along * clampf(float(coast.get("lhd_along_m", 0.0)), -half + length * 0.5, half - length * 0.5)
	var xform := Transform3D(Basis.looking_at(along, Vector3.UP), Vector3(at.x, terrain.sea_level, at.z))
	var shallow := INF
	for p in Lhd.footprint(xform, length, beam):
		shallow = minf(shallow, terrain.sea_level - terrain.height_at(p.x, p.z))
	var draft := clampf(shallow - KEEL_CLEAR_M, 1.0, float(data.get("draft_m", LhdArt.DRAFT_M)))
	return {"transform": xform, "length": length, "beam": beam, "draft": draft}


## Points over the hull's footprint (a `length` by `beam` box about `xform`, the bow -z):
## every FOOTPRINT_STEP_M along it, at both sides and the centre line, ends included.
static func footprint(xform: Transform3D, length: float, beam: float) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var n := maxi(ceili(length / FOOTPRINT_STEP_M), 1)
	for i in n + 1:
		var z := -length * 0.5 + length * float(i) / n
		for x: float in [-beam * 0.5, 0.0, beam * 0.5]:
			pts.append(xform * Vector3(x, 0.0, z))
	return pts


func _place_fob(level: Node, def: Dictionary) -> void:
	kind = &"fob"
	_area = level.call(&"map_area") if level.has_method(&"map_area") else Rect2(-50, -50, 100, 100)
	side = String(def.get("fob_side", ""))
	if not side in SIDES:
		var toward := Vector3.ZERO
		var ins: Array = def.get("insertion", [])
		if not ins.is_empty():
			toward = Vector3(float(ins[0][0]), 0.0, float(ins[0][1]))
		elif level.has_method(&"spawn_point"):
			toward = level.call(&"spawn_point", 0)
		side = Lhd.nearest_side(_area, toward)
	var gate := edge_point(Vector3(_area.get_center().x, 0.0, _area.get_center().y))
	transform = Transform3D(Basis.looking_at(-Lhd.outward(side), Vector3.UP), gate)


## The side of `area` nearest `p`.
static func nearest_side(area: Rect2, p: Vector3) -> String:
	var d := {"north": p.z - area.position.y, "south": area.end.y - p.z, "west": p.x - area.position.x, "east": area.end.x - p.x}
	var best := "south"
	for k: String in d:
		if float(d[k]) < float(d[best]):
			best = k
	return best


## Out of the map on `side_name` (a unit vector on the ground plane; north is -z).
static func outward(side_name: String) -> Vector3:
	return {"north": Vector3(0, 0, -1), "south": Vector3(0, 0, 1), "east": Vector3(1, 0, 0), "west": Vector3(-1, 0, 0)}.get(side_name, Vector3(0, 0, 1))


## Inland: the point on the FOB's side FOB_INSET_M inside the edge, level with `toward` along
## it, on the ground (the level's ground_point).
func edge_point(toward: Vector3) -> Vector3:
	var inset := float(AavSupport.data().get("lhd", {}).get("fob_inset_m", 40.0))
	var r := _area.grow(-inset)
	var x := clampf(toward.x, r.position.x, r.end.x)
	var z := clampf(toward.z, r.position.y, r.end.y)
	match side:
		"north":
			z = r.position.y
		"south":
			z = r.end.y
		"west":
			x = r.position.x
		_:
			x = r.end.x
	var lvl := get_parent() if is_inside_tree() else null
	var p := Vector3(x, 0.0, z)
	return lvl.call(&"ground_point", p) if lvl and lvl.has_method(&"ground_point") else p


## Where a ground support comes in toward `toward`: the LHD's stern, in the water, facing the
## shore; or the FOB's side of the map level with `toward`, facing in.
func entry_transform(toward: Vector3) -> Transform3D:
	if is_ship():
		return launch_transform()
	var at := edge_point(toward)
	return Transform3D(Basis.looking_at(-Lhd.outward(side), Vector3.UP), at + Vector3.UP * 0.3)


## The LHD: an AAV comes out of the well deck's stern gate STERN_GAP_M astern, afloat, facing the shore.
func launch_transform() -> Transform3D:
	var gap := float(AavSupport.data().get("aav", {}).get("stern_gap_m", 20.0))
	var stern := (get_node(^"LHD/Stern") as Node3D).global_position
	var astern := global_basis.z  # the bow is -z
	var at := stern + Vector3(astern.x, 0.0, astern.z).normalized() * gap
	var terrain := _terrain()
	var shore := -terrain.seaward() if terrain else -global_basis.x
	return Transform3D(Basis.looking_at(shore, Vector3.UP), Vector3(at.x, _sea_level() - 1.2, at.z))


## Where an AAV going home heads for: astern of the LHD on the water, or the FOB's road.
func dock_point(from: Vector3) -> Vector3:
	if is_ship():
		var t := launch_transform()
		return Vector3(t.origin.x, _sea_level(), t.origin.z)
	return edge_point(from)


## The LHD: a point on the water CLEAR_M shoreward of the stern's launch point, clear of the
## ship's side, so an AAV swims round the hull rather than into it (out, and back in). Inland:
## dock_point.
func approach_point(from: Vector3) -> Vector3:
	if not is_ship():
		return dock_point(from)
	var terrain := _terrain()
	var shoreward := -terrain.seaward() if terrain else -global_basis.x
	return dock_point(from) + shoreward * (float(AavSupport.data().get("lhd", {}).get("beam_m", LhdArt.BEAM_M)) * 0.5 + CLEAR_M)


## The flight deck's marker (helicopters start there), or this node inland.
func deck() -> Node3D:
	return get_node(^"LHD/Deck") as Node3D if is_ship() else self


## The water's surface (the zone's sea level; 0 inland).
func _sea_level() -> float:
	var terrain := _terrain()
	return terrain.sea_level if terrain else 0.0


func _terrain() -> ZoneTerrain:
	var lvl := get_parent()
	var t: Variant = lvl.get(&"terrain") if lvl else null
	return t as ZoneTerrain if t is ZoneTerrain else null
