extends Node
## Landmark buildings (queue item 1.4, cghath 2026-10-21; docs/building_gen.md "Landmarks"):
## every landmark type (BuildingGen.LANDMARK_TYPES: an office, a mosque, a church, a school, a
## garage, a fuel station, a factory, a farmhouse and barn, a harbour shed, a hangar and control
## tower, a pump house, a drug lab, an IED workshop) generates by seed with the rooms it should
## have, every room reachable through its doorways and up its stairs, its doorways clear, all of
## it inside its lot; its ruined and bombed-out variants generate with their stairs and doorways
## kept; the sites (BuildingGen.site: those alone, a farm, a fuel depot, a harbour, an airfield,
## an oil field) have garrison posts, loot and named points, turned or not; they are module types
## (ZoneModules "lm#..."); the campaign's zones get the ones their asset tags name (data/
## landmarks.json), a harbour on the sea with its piers out over the water. Then, standing in
## the test compound's open ground one at a time: the navmesh baked over each type covers its
## rooms, its stairs reach its upper floors and roof, and the AI's building scan (Buildings)
## finds its floors, rooms, entrances and firing ports. Headless; never touches a real save.

## Where each building stands for the in-world checks: the compound's open ground north-west of
## its walls, inside its navigation grid (CompoundLevel: 108 m square).
const AT := Vector3(-30, 0, 36)
## Proposed: the most voxels one landmark building may be (a mosque with its dome and minaret is
## the biggest, about 360 000), and a whole site.
const BUILDING_VOXELS := 450000
const SITE_VOXELS := 1200000
## Seeds per type for the generation checks.
const SEEDS := 10

var failures := 0
var level: CompoundLevel
var player: Soldier


func _ready() -> void:
	GameState.zone_id = "test_landmarks" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	GameState.delete_save()
	CompoundLevel.spawn_ai = false
	get_tree().create_timer(450.0).timeout.connect(func() -> void:
		print("LANDMARKS TEST FAILED (timed out)")
		get_tree().quit(99))
	_test_types()
	_test_ruins()
	_test_sites()
	_test_modules()
	_test_placement()
	_test_harbour_water()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	await _test_in_world()
	GameState.delete_save()
	print("LANDMARKS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


## A building's voxels (its boxes' volume, overlaps counted twice: an upper bound).
func _voxels(boxes: Array) -> int:
	var n := 0
	for bx: Array in boxes:
		var d: Vector3 = (bx[1] as Vector3) - (bx[0] as Vector3)
		n += int(d.x * d.y * d.z / pow(VoxelWorld.VOXEL_SIZE, 3))
	return n


## Whether point `q` is inside any of `boxes`.
func _solid(boxes: Array, q: Vector3) -> bool:
	return boxes.any(func(bx: Array) -> bool: return AABB(bx[0], (bx[1] as Vector3) - (bx[0] as Vector3)).has_point(q))


## Building `b`'s rooms reached from the street through its doorways (and stairs): their count.
func _reached(b: Dictionary) -> int:
	var seen := {-1: true}
	var grew := true
	while grew:
		grew = false
		for dr: Dictionary in b.doors:
			if (b.buried as Array).has(dr.at):
				continue
			var a: int = dr.rooms[0]
			var c: int = dr.rooms[1]
			if seen.has(a) != seen.has(c):
				seen[a] = true
				seen[c] = true
				grew = true
	return seen.keys().filter(func(k: int) -> bool: return k >= 0).size()


## Doorways of `b` with no way through (blocked, or nothing open either side), buried ones aside.
func _blocked_doors(b: Dictionary) -> Array:
	var out: Array = []
	for dr: Dictionary in b.doors:
		if (b.buried as Array).has(dr.at) or dr.get("stair", false):
			continue
		var at: Vector3 = (dr.at as Vector3) + Vector3(0, 0.5, 0)
		var through_x: bool = not _solid(b.boxes, at + Vector3(0.6, 0, 0)) and not _solid(b.boxes, at - Vector3(0.6, 0, 0))
		var through_z: bool = not _solid(b.boxes, at + Vector3(0, 0, 0.6)) and not _solid(b.boxes, at - Vector3(0, 0, 0.6))
		if _solid(b.boxes, at) or not (through_x or through_z):
			out.append(dr.at)
	return out


## Everything of `b` inside its lot (its size, centred on its origin) and under its height.
func _inside(b: Dictionary) -> bool:
	var half := (b.size as Vector2) * 0.5
	for bx: Array in b.boxes:
		var lo: Vector3 = bx[0]
		var hi: Vector3 = bx[1]
		if lo.x < -half.x - 0.01 or lo.z < -half.y - 0.01 or hi.x > half.x + 0.01 or hi.z > half.y + 0.01 or hi.y > float(b.height) + 0.01 or lo.y < -0.01:
			return false
	return true


## The roles each type must have on its ground floor (and above), and how many of them.
const MUST := {
	"office": {"reception": 1, "open_office": 1}, "mosque": {"prayer_hall": 1}, "church": {"nave": 1}, "school": {"reception": 1, "classroom": 2},
	"garage": {"workshop": 1}, "fuel_station": {"shopfront": 1}, "factory": {"factory_floor": 1}, "farmhouse": {"living": 1, "kitchen": 1, "bathroom": 1},
	"barn": {"barn": 1}, "harbour_shed": {"dock_hall": 1}, "hangar": {"hangar": 1, "office": 1}, "control_tower": {"tower_cab": 1},
	"pumphouse": {"plant": 1}, "drug_lab": {"lab": 1}, "ied_workshop": {"bomb_workshop": 1},
}
## Halls furnished with more than one chunk.
const HALLS: Array[String] = ["prayer_hall", "nave", "factory_floor", "hangar", "dock_hall"]


func _test_types() -> void:
	print("Landmark types: rooms, doorways, stairs, lot, voxels, by seed")
	var bad: Array = []
	var worst := {}
	var furnished := 0
	var rooms_all := 0
	var halls_ok := 0
	var halls := 0
	for type: String in BuildingGen.LANDMARK_TYPES:
		for k in SEEDS:
			var seed := k * 37 + 5
			var b := BuildingGen.building(type, seed)
			var roles: Array = (b.rooms as Array).map(func(r: Dictionary) -> String: return r.role)
			for role: String in MUST[type]:
				if roles.count(role) < int(MUST[type][role]):
					bad.append("%s %d: %s rooms %s" % [type, seed, role, roles])
			if _reached(b) != (b.rooms as Array).size():
				bad.append("%s %d: %d of %d rooms reached" % [type, seed, _reached(b), (b.rooms as Array).size()])
			if BuildingGen.front_door(b) == null or (BuildingGen.front_door(b) as Vector3).z < float(b.size.y) * 0.5 - float(b.apron) - 0.5:
				bad.append("%s %d: no front door" % [type, seed])
			var blocked := _blocked_doors(b)
			if not blocked.is_empty():
				bad.append("%s %d: doorways blocked %s" % [type, seed, blocked])
			for st: Dictionary in b.stairs:
				if (float(st.to_y) - float(st.from_y)) / int(st.steps) > 0.25 + 0.001:
					bad.append("%s %d: stair steps too high" % [type, seed])
			if (b.doors as Array).filter(func(dr: Dictionary) -> bool: return dr.get("stair", false)).size() != (b.stairs as Array).size() \
					or (int(b.storeys) == 2) != (b.rooms as Array).any(func(r: Dictionary) -> bool: return int(r.floor) == 1):
				bad.append("%s %d: storeys %d, %d stairs" % [type, seed, b.storeys, (b.stairs as Array).size()])
			if not _inside(b):
				bad.append("%s %d: outside its lot %s" % [type, seed, b.size])
			worst[type] = maxi(int(worst.get(type, 0)), _voxels(b.boxes))
			for r: Dictionary in b.rooms:
				rooms_all += 1
				furnished += 1 if String(r.chunk) != "" else 0
				if String(r.role) in HALLS and (r.rect as Rect2).get_area() > 40.0:
					halls += 1
					halls_ok += 1 if (r.chunks as Array).size() >= 2 else 0
			if type == "drug_lab" and not (b.windows as Array).is_empty():
				bad.append("drug lab %d: windows %d (blacked out)" % [seed, (b.windows as Array).size()])
			if type in ["office", "control_tower"] and (int(b.storeys) != 2 or not b.roof_access):
				bad.append("%s %d: storeys %d, roof %s" % [type, seed, b.storeys, b.roof_access])
		var again := BuildingGen.building(type, 41)
		if BuildingGen.building(type, 41).boxes != again.boxes or BuildingGen.building(type, 42).boxes == again.boxes:
			bad.append("%s: not the same from the same seed" % type)
	check(bad.is_empty(), "%d types x %d seeds: the rooms each should have, every room reached, a front door, doorways clear, stairs 0.25 m a step, inside the lot, the same from a seed %s" % [
		BuildingGen.LANDMARK_TYPES.size(), SEEDS, bad.slice(0, 4)])
	var over: Array = worst.keys().filter(func(t: String) -> bool: return int(worst[t]) > BUILDING_VOXELS)
	check(over.is_empty(), "each under %d voxels (largest: %s)" % [BUILDING_VOXELS, _largest(worst)])
	check(furnished >= rooms_all * 0.9 and halls_ok >= halls * 0.8, "rooms furnished from the chunk library (%d of %d), big halls with more than one chunk (%d of %d)" % [furnished, rooms_all, halls_ok, halls])
	# Their own things: a dome and a minaret, a bell tower, a canopy, a chimney, a hangar's arch.
	var mosque := BuildingGen.building("mosque", 5)
	var church := BuildingGen.building("church", 5)
	var station := BuildingGen.building("fuel_station", 5)
	var factory := BuildingGen.building("factory", 5)
	var hangar := BuildingGen.building("hangar", 5)
	check(float(mosque.height) >= BuildingGen.MINARET_H.x and _top_over(mosque, float(mosque.roof_y) + 2.0, 6),
		"a mosque has its minaret (%.1f m) and a dome over its prayer hall" % mosque.height)
	check(float(church.height) >= float(church.roof_y) + BuildingGen.BELL_TOWER_UP and _top_over(church, float(church.roof_y) + 1.0, 20),
		"a church has its bell tower (%.1f m) and a gable roof" % church.height)
	check(_top_over(station, BuildingGen.CANOPY_H - 0.01, 1), "a fuel station has its canopy over the pumps")
	check(float(factory.height) >= BuildingGen.CHIMNEY_H.x - 0.01 or (factory.boxes as Array).size() > 0 and float(factory.height) > 6.0,
		"a factory has its chimney (%.1f m)" % factory.height)
	check(_top_over(hangar, float(hangar.roof_y) + 1.5, 10), "a hangar has its curved roof")
	# The office (feature_comparison 8.2, building_gen.md claimed one before there was).
	check(BuildingGen.TYPES.has("office") and "office" in BuildingGen.LANDMARK_TYPES and "office" in BuildingGen.SITE_KINDS, "an office is a building type and a site")


func _largest(worst: Dictionary) -> String:
	var best := ""
	for t: String in worst:
		if best == "" or int(worst[t]) > int(worst[best]):
			best = t
	return "%s %d" % [best, int(worst.get(best, 0))]


## Whether at least `n` of `b`'s boxes top out over `y`.
func _top_over(b: Dictionary, y: float, n: int) -> bool:
	return (b.boxes as Array).filter(func(bx: Array) -> bool: return (bx[1] as Vector3).y > y).size() >= n


func _test_ruins() -> void:
	print("Ruined and bombed-out variants")
	var bad: Array = []
	var differ := 0
	var runs := 0
	var corners := 0
	var roofs_down := 0
	for type: String in BuildingGen.LANDMARK_TYPES + ["house", "shop", "warehouse", "clinic", "police"]:
		for k in 6:
			var seed := k * 53 + 9
			var whole := BuildingGen.building(type, seed)
			for level: int in [BuildingGen.RUINED, BuildingGen.BOMBED]:
				var b := BuildingGen.building(type, seed, "", level)
				runs += 1
				if int(b.ruin) != level:
					bad.append("%s %d: ruin %d" % [type, seed, b.ruin])
				if b.boxes != whole.boxes:
					differ += 1
				if not _inside(b):
					bad.append("%s %d/%d: outside its lot" % [type, seed, level])
				# Its stairs stand, every step of them.
				for st: Dictionary in b.stairs:
					var f: Rect2 = st.foot
					var mid := Vector3(f.get_center().x, float(st.from_y) + 0.05, f.get_center().y)
					if not _solid(b.boxes, mid):
						bad.append("%s %d/%d: stair gone" % [type, seed, level])
				var blocked := _blocked_doors(b)
				if not blocked.is_empty():
					bad.append("%s %d/%d: doorways blocked %s" % [type, seed, level, blocked])
				# The room inside the front door is reached from the street.
				var front: Array = (b.doors as Array).filter(func(dr: Dictionary) -> bool: return int(dr.rooms[1]) == -1 and not (b.buried as Array).has(dr.at))
				if front.is_empty():
					bad.append("%s %d/%d: no way in" % [type, seed, level])
				corners += 1 if level == BuildingGen.BOMBED and _voxels(b.boxes) < _voxels(whole.boxes) else 0
				if level == BuildingGen.BOMBED and int(b.storeys) == 2:
					roofs_down += 1 if not b.roof_access else 0
					if b.roof_access:
						bad.append("%s %d: bombed out, its roof still reached" % [type, seed])
	check(bad.is_empty() and differ == runs, "%d ruined and bombed-out buildings (every type): each its own, inside its lot, its stairs standing, doorways clear, a way in %s" % [runs, bad.slice(0, 4)])
	check(corners >= runs / 4 and roofs_down > 0, "bombed out: walls and roofs down (%d of %d lighter than whole), two-storey roofs gone (%d)" % [corners, runs / 2, roofs_down])


func _test_sites() -> void:
	print("Landmark sites: posts, loot, points, footprint, turned")
	var bad: Array = []
	var posts := []
	for kind: String in BuildingGen.SITE_KINDS:
		for level in 3:
			for seed: int in [3, 17]:
				var s := BuildingGen.site(kind, seed, level)
				var g: Array = s.garrison
				posts.append(g.size())
				if g.size() < 2 or (s.garrison_face as Array).size() != g.size():
					bad.append("%s %d/%d: %d posts" % [kind, seed, level, g.size()])
				for p: Vector3 in g:
					var standing := BuildingGen._clear_standing(s.boxes, p)
					if not standing:
						bad.append("%s %d/%d: post %s in something" % [kind, seed, level, p])
				if (s.loot as Array).size() > BuildingGen.LANDMARK_LOOT_MAX:
					bad.append("%s: %d loot" % [kind, (s.loot as Array).size()])
				for key in ["objective", "cache", "intel"]:
					if (s.points[key] as Array).is_empty():
						bad.append("%s: no %s point" % [kind, key])
				var half: Vector2 = s.half
				for bx: Array in s.boxes:
					var lo: Vector3 = bx[0]
					var hi: Vector3 = bx[1]
					if absf(lo.x) > half.x + 0.01 or absf(hi.x) > half.x + 0.01 or absf(lo.z) > half.y + 0.01 or absf(hi.z) > half.y + 0.01:
						bad.append("%s: a box outside its footprint" % kind)
						break
				if _voxels(s.boxes) > SITE_VOXELS:
					bad.append("%s: %d voxels" % [kind, _voxels(s.boxes)])
		var a := BuildingGen.site(kind, 3, 0, 0)
		for turn in [1, 2, 3]:
			var t := BuildingGen.site(kind, 3, 0, turn)
			var swapped: Vector2 = Vector2((a.half as Vector2).y, (a.half as Vector2).x) if turn % 2 == 1 else a.half
			if (t.boxes as Array).size() != (a.boxes as Array).size() or _voxels(t.boxes) != _voxels(a.boxes) or t.half != swapped \
					or (t.garrison as Array).size() != (a.garrison as Array).size():
				bad.append("%s turned %d: not the same site" % [kind, turn])
	check(bad.is_empty(), "%d sites x 3 states x 2 seeds: 2+ garrison posts each standing clear (%d-%d), loot, objective/cache/intel points, all inside its footprint, under %d voxels; turned, the same %s" % [
		BuildingGen.SITE_KINDS.size(), posts.min(), posts.max(), SITE_VOXELS, bad.slice(0, 4)])
	var harbour := BuildingGen.site("harbour", 3)
	var air := BuildingGen.site("airfield", 3)
	var runway := (air.streets as Array).any(func(r: Rect2) -> bool: return r.size.x >= BuildingGen.RUNWAY.x - 0.01)
	check(absf(float(harbour.pad_sea) - BuildingGen.QUAY_OVER_SEA) < 0.01 and (harbour.pad as Rect2).position.y > BuildingGen.QUAY_Z
		and (harbour.boxes as Array).any(func(bx: Array) -> bool: return (bx[0] as Vector3).z < BuildingGen.QUAY_Z - BuildingGen.PIER_L + 1.0),
		"a harbour's pad is its land at %.1f m over the sea, its piers reach %.0f m past the quay" % [BuildingGen.QUAY_OVER_SEA, BuildingGen.PIER_L])
	check(runway and (air.extent as Vector2).x < (air.half as Vector2).x, "an airfield's runway (%.0f m) is painted ground: its voxels span %s of its footprint %s" % [BuildingGen.RUNWAY.x, air.extent, air.half])
	check(str(BuildingGen.site("oil_field", 9).boxes) == str(BuildingGen.site("oil_field", 9).boxes), "the same seed builds the same site")


func _test_modules() -> void:
	print("Landmark module types")
	var type := "lm#mosque#4242#0#0"
	var ok := ZoneModules.has_type(type) and ZoneModules.base(type) == "mosque" and not ZoneModules.boxes(type).is_empty() \
		and ZoneModules.HALF.has(type) and (ZoneModules.GARRISON.get(type, []) as Array).size() >= 2 \
		and (ZoneModules.GARRISON_FACE.get(type, []) as Array).size() == (ZoneModules.GARRISON.get(type, []) as Array).size()
	check(ok, "\"%s\" is a module type: base \"%s\", %d boxes, footprint %s, %d garrison posts" % [type, ZoneModules.base(type), ZoneModules.boxes(type).size(),
		ZoneModules.HALF.get(type), (ZoneModules.GARRISON.get(type, []) as Array).size()])
	check(not ZoneModules.has_type("lm#castle#1#0#0") and not ZoneModules.has_type("lm#mosque#x#0#0") and not ZoneModules.has_type("lm#mosque#1#3#0")
		and not ZoneModules.has_type("lm#mosque#1#0"), "a bad landmark type isn't one")
	var stairs := 0
	var seed := 70
	while stairs == 0 and seed < 120:
		seed += 1
		for bt: Dictionary in BuildingGen.site("school", seed).buildings:
			stairs += (bt.data.stairs as Array).size()
	var school := "lm#school#%d#0#0" % seed
	ZoneModules.has_type(school)
	check(ZoneModules.ramps(school).size() == stairs * BuildingGen.RAMP_FACES, "its stairs have ramps for the navmesh (%d stairs)" % stairs)
	var air := "lm#airfield#5#0#1"
	ZoneModules.has_type(air)
	var bounds := ZoneModules.bounds_voxels(air)
	var half: Vector2 = ZoneModules.HALF[air]
	check(bounds.size.z * VoxelWorld.VOXEL_SIZE < half.y * 2.0 and not ZoneModules.streets(air).is_empty() and ZoneModules.pad_rect(air, Vector2.ZERO).size == half * 2.0,
		"an airfield's voxel bounds (%.0f m) are its buildings', its footprint (%.0f m) its runway's" % [bounds.size.z * VoxelWorld.VOXEL_SIZE, half.y * 2.0])
	var harbour := "lm#harbour#5#0#2"
	ZoneModules.has_type(harbour)
	var pad := ZoneModules.pad_rect(harbour, Vector2(100, 100))
	check(absf(ZoneModules.pad_sea(harbour) - BuildingGen.QUAY_OVER_SEA) < 0.01 and pad.position.y < 100.0 and pad.end.y > 100.0 and pad.end.y < 100.0 + (ZoneModules.HALF[harbour] as Vector2).y
		and float(ZoneModules.bounds_voxels(harbour).position.y) * VoxelWorld.VOXEL_SIZE < -5.0,
		"a harbour (turned to a sea at +z) has its land as its pad, its quay's piles reach down into the sea")


func _test_placement() -> void:
	print("Landmarks in the campaign's zones, by their asset tags")
	var tag_kinds: Dictionary = ZoneModules.landmark_data().tags
	var missing: Array = []
	var seen := {}
	var bad: Array = []
	var by_zone: Array = []
	for z: Dictionary in MissionRegistry.data().get("zones", []):
		var id := String(z.zone_id)
		var def := MissionRegistry.zone_def(id)
		if def.is_empty():
			continue
		var kinds := ZoneModules.landmark_kinds(def)
		var placed: Array = (def.modules as Array).filter(func(m: Dictionary) -> bool: return String(m.id).begins_with("lm_"))
		var names: Array = placed.map(func(m: Dictionary) -> String: return ZoneModules.base(String(m.type)))
		for n: String in names:
			seen[n] = true
		if not names.is_empty():
			by_zone.append("%s: %s" % [id, ", ".join(names)])
		for tag: Variant in z.get("assets", []):
			for k: Variant in tag_kinds.get(String(tag), []):
				if String(k) in kinds and not String(k) in names and not (String(k) == "harbour" and int(def.get("sea_side", -1)) < 0):
					missing.append("%s %s" % [id, k])
		# Clear of the other modules; once placed, kept: normalizing again changes nothing.
		for m: Dictionary in placed:
			var r := ZoneModules.pad_rect(String(m.type), Vector2(float(m.pos[0]), float(m.pos[1])))
			for o: Dictionary in def.modules:
				if o != m and ZoneModules.pad_rect(String(o.type), Vector2(float(o.pos[0]), float(o.pos[1]))).grow(ZoneModules.LANDMARK_KEEP_M - 1.0).intersects(r):
					bad.append("%s: %s on %s" % [id, m.id, o.id])
			if not (def.get("roads", []) as Array).any(func(rd: Array) -> bool: return absf(float(rd[0][0]) - float(m.pos[0])) < 0.01 and absf(float(rd[0][1]) - float(m.pos[1])) < 0.01):
				bad.append("%s: no road to %s" % [id, m.id])
		var again := ZoneDef.normalize(def)
		if str(again.modules) != str(def.modules) or int(again.sea_side) != int(def.sea_side) or absf(float(again.sea_m) - float(def.sea_m)) > 0.01:
			bad.append("%s: normalized again, not the same" % id)
	print("    " + "\n    ".join(by_zone))
	check(missing.is_empty(), "every zone has the landmarks its asset tags name (mosque, harbour on a sea, oil field, airfield, farm, and the rest) %s" % [missing.slice(0, 6)])
	var all_kinds: Array = BuildingGen.SITE_KINDS.filter(func(k: String) -> bool: return not seen.has(k))
	check(all_kinds.is_empty(), "every landmark appears in at least one zone of the campaign (missing: %s)" % [all_kinds])
	check(bad.is_empty(), "each clear of the other modules, a road to it, and the zone the same normalized again %s" % [bad.slice(0, 4)])
	# A terror group's own site: the Kestrels' drug lab, the Banner's IED workshop.
	var lab := MissionRegistry.zone_def("kestrel_valley").modules as Array
	var ied := MissionRegistry.zone_def("red_mesa").modules as Array
	check(lab.any(func(m: Dictionary) -> bool: return ZoneModules.base(String(m.type)) == "drug_lab") and ied.any(func(m: Dictionary) -> bool: return ZoneModules.base(String(m.type)) == "ied_workshop"),
		"a cartel's zone has its drug lab, the Banner's its IED workshop")


## A harbour's piers reach the water: the zone's terrain under them is sea, its quay land.
func _test_harbour_water() -> void:
	print("A harbour on its coast")
	var checked := 0
	var bad: Array = []
	for id: String in ["fishers_reach", "harbour_yard", "cove_outpost", "mudflat_crossing", "landing_beach", "marrow_shore"]:
		var def := MissionRegistry.zone_def(id)
		var m: Array = (def.modules as Array).filter(func(x: Dictionary) -> bool: return String(x.id) == "lm_harbour")
		if m.is_empty():
			continue
		var flat: Array = []
		for o: Dictionary in def.modules:
			flat.append(ZoneModules.pad_rect(String(o.type), Vector2(float(o.pos[0]), float(o.pos[1]))))
		var t := ZoneTerrain.new()
		t.generate(def, flat)
		var at := Vector2(float(m[0].pos[0]), float(m[0].pos[1]))
		var turn := int(String(m[0].type).get_slice("#", 4))
		var tip := BuildingGen._rot(Vector3(-26.5, 0, BuildingGen.QUAY_Z - BuildingGen.PIER_L + 2.0), turn)
		var yard := BuildingGen._rot(Vector3(0, 0, 10.0), turn)
		var tip_h := t.height_at(at.x + tip.x, at.y + tip.z)
		var yard_h := t.height_at(at.x + yard.x, at.y + yard.z)
		checked += 1
		if tip_h > t.sea_level - 0.3 or absf(yard_h - (t.sea_level + BuildingGen.QUAY_OVER_SEA)) > 0.1:
			bad.append("%s: pier tip ground %.1f, yard %.1f (sea %.1f)" % [id, tip_h, yard_h, t.sea_level])
		t.free()
	check(checked >= 3 and bad.is_empty(), "%d harbours: the yard %.1f m over the sea, the piers' ends over water %s" % [checked, BuildingGen.QUAY_OVER_SEA, bad])


# --- In the world ----------------------------------------------------------------------------

func _test_in_world() -> void:
	print("Landmarks standing: navmesh over their rooms, stairs up, the AI's building scan")
	var runs: Array = []
	for type: String in BuildingGen.LANDMARK_TYPES if OS.get_environment("LM_ONLY") == "" else [OS.get_environment("LM_ONLY")]:
		runs.append([type, 5, BuildingGen.INTACT])
	for type: String in ["mosque", "school", "office", "ied_workshop"]:
		runs.append([type, 5, BuildingGen.BOMBED])
	for type: String in ["church", "garage", "factory", "fuel_station", "drug_lab"]:
		runs.append([type, 5, BuildingGen.RUINED])
	var bad_nav: Array = []
	var bad_up: Array = []
	var bad_scan: Array = []
	var found_rooms := 0
	var summary: Array = []
	for run: Array in runs:
		var b := BuildingGen.building(String(run[0]), int(run[1]), "", int(run[2]))
		var name := "%s%s" % [run[0], "" if int(run[2]) == 0 else ["", " (ruined)", " (bombed)"][int(run[2])]]
		var holder := Node3D.new()
		holder.name = "Landmark"
		holder.position = AT
		var world := VoxelWorld.new()
		world.bounds = AABB(Vector3(-170, -10, -170), Vector3(340, 210, 340))
		world.view_distance = 2000
		for bx: Array in b.boxes:
			world.add_box_m(bx[0], bx[1], bx[2])
		level.add_child(holder)
		holder.add_child(world)
		player.global_position = AT + Vector3(0, 0.1, (b.size as Vector2).y * 0.5 + 6.0)
		var built := await _wait_until(func() -> bool: return world.is_built(), 40.0)
		await _physics_frames(10)
		var readable := await _wait_until(func() -> bool:
			return world.is_area_readable(AABB(Vector3(-160, -5, -160), Vector3(320, 200, 320))), 30.0)
		var map := player.get_world_3d().navigation_map
		var iteration := NavigationServer3D.map_get_iteration_id(map)
		_bake(world, b)
		# (The navigation server takes its regions' new meshes in over a few iterations of its own.)
		await _wait_until(func() -> bool: return NavigationServer3D.map_get_iteration_id(map) > iteration + 2, 10.0)
		await _physics_frames(10)
		Buildings.forget()
		var street := NavigationServer3D.map_get_closest_point(map, AT + Vector3(0, 0, (b.size as Vector2).y * 0.5 + 3.0))
		# Every room (not one buried in a fallen corner) reached by a path from the street.
		var reached := 0
		var rooms := 0
		for r: Dictionary in b.rooms:
			var rect: Rect2 = r.rect
			var y := float(r.y)
			var goal := _room_goal(map, rect, y, street)
			var local := goal - AT
			if int(run[2]) == BuildingGen.BOMBED and int(r.floor) > 0:
				continue  # (a bombed-out building's upper floor: open to the sky now, may be cut off)
			rooms += 1
			var on_floor := goal.is_finite()
			var path := NavigationServer3D.map_get_path(map, street, goal, true) if on_floor else PackedVector3Array()
			if on_floor and path.size() > 1 and path[-1].distance_to(goal) < 0.5:
				reached += 1
			elif int(run[2]) != BuildingGen.BOMBED:
				var down := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(AT + Vector3(rect.get_center().x, y + 2.0, rect.get_center().y), AT + Vector3(rect.get_center().x, y - 1.0, rect.get_center().y), 1))
				bad_nav.append("%s %s (floor %d, %s: %s, %s, under it %s)" % [name, r.role, r.floor, "no navmesh there" if not on_floor else "no path", rect, local,
					(down.position as Vector3) - AT if not down.is_empty() else "nothing"])
		if int(run[2]) == BuildingGen.BOMBED and reached < ceili(rooms * 0.5):
			bad_nav.append("%s: %d of %d rooms reached" % [name, reached, rooms])
		# Up the stairs: the roof (or the floor above) from the street.
		if int(run[2]) == BuildingGen.INTACT and (int(b.storeys) == 2 or b.roof_access):
			var top_y := float(b.roof_y) if b.roof_access else float((b.rooms as Array).filter(func(r: Dictionary) -> bool: return int(r.floor) == 1)[0].y)
			var ups: Array = (b.rooms as Array).filter(func(r: Dictionary) -> bool: return int(r.floor) == int(b.storeys) - 1)
			var spot: Rect2 = ups[0].rect
			var goal := NavigationServer3D.map_get_closest_point(map, AT + Vector3(spot.get_center().x, top_y + 0.2, spot.get_center().y))
			var path := NavigationServer3D.map_get_path(map, street, goal, true)
			if absf(goal.y - AT.y - top_y) > Buildings.SURFACE_SNAP_M or path.size() < 3 or path[-1].distance_to(goal) > 0.5:
				bad_up.append("%s (to %.1f m: got %.1f)" % [name, top_y, goal.y - AT.y])
		# The AI's scan from inside the front door.
		var front_door: Variant = BuildingGen.front_door(b)
		# (From inside its front door; a hangar's hall is too open by its door for the scan's probes,
		# so from its rooms in turn after that.)
		var tries: Array = [AT + (front_door as Vector3) + Vector3(0, 0.1, -1.5)] if front_door != null else []
		for r: Dictionary in b.rooms:
			tries.append(AT + Vector3((r.rect as Rect2).get_center().x, float(r.y) + 0.1, (r.rect as Rect2).get_center().y))
		var found := {}
		for q: Vector3 in tries:
			found = Buildings.nearest(player, q, 4.0)
			if not found.is_empty():
				break
		var floors: Array = found.get("floors", [])
		var entrances: Array = found.get("entrances", [])
		var ports: Array = found.get("ports", [])
		var scan_rooms: Array = found.get("rooms", [])
		found_rooms += scan_rooms.size()
		var want_floors := 1 if int(run[2]) != BuildingGen.INTACT else int(b.storeys) + (1 if b.roof_access else 0)
		if found.is_empty() or floors.size() < want_floors or entrances.is_empty() or scan_rooms.is_empty() or ports.is_empty():
			bad_scan.append("%s: %d floors (want %d), %d entrances, %d rooms, %d ports" % [name, floors.size(), want_floors, entrances.size(), scan_rooms.size(), ports.size()])
		summary.append("%s %d/%d rooms, scan %df %de %dr %dp" % [name, reached, rooms, floors.size(), entrances.size(), scan_rooms.size(), ports.size()])
		if not built or not readable:
			bad_scan.append("%s: voxels built %s, readable %s" % [name, built, readable])
		holder.queue_free()
		await _physics_frames(3)
	print("    " + "\n    ".join(summary))
	check(bad_nav.is_empty(), "the navmesh covers every room of every type, a path to each from the street (ruins: most) %s" % [bad_nav.slice(0, 5)])
	check(bad_up.is_empty(), "their stairs reach their upper floors and roofs %s" % [bad_up.slice(0, 4)])
	check(bad_scan.is_empty() and found_rooms > runs.size(), "the AI's building scan finds each one's floors, rooms (%d), entrances and firing ports %s" % [found_rooms, bad_scan.slice(0, 4)])


## A walkable spot on room `rect`'s floor (at `y`) by the navmesh (zone space): the one nearest
## its middle that a path from `street` reaches (furniture tops are walkable too, islands of their
## own), else the nearest; Vector3.INF if the room has none.
func _room_goal(map: RID, rect: Rect2, y: float, street: Vector3) -> Vector3:
	var found: Array = []
	var c := rect.get_center()
	var x := rect.position.x + 0.25
	while x < rect.end.x:
		var z := rect.position.y + 0.25
		while z < rect.end.y:
			var q := NavigationServer3D.map_get_closest_point(map, AT + Vector3(x, y + 0.1, z))
			var local := q - AT
			if rect.has_point(Vector2(local.x, local.z)) and absf(local.y - y) < Buildings.SURFACE_SNAP_M:
				found.append([Vector2(local.x, local.z).distance_to(c), q])
			z += 0.5
		x += 0.5
	if found.is_empty():
		return Vector3.INF
	found.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for k in mini(found.size(), 16):
		var q: Vector3 = found[k][1]
		var path := NavigationServer3D.map_get_path(map, street, q, true)
		if path.size() > 1 and path[-1].distance_to(q) < 0.5:
			return q
	return found[0][1]


## The navigation over building `b` (in `world`, at AT) as NavBuilder bakes a chunk: the ground,
## the voxels as they stand, and ramps over its stairs (as ZoneNav adds a module's).
func _bake(world: VoxelWorld, b: Dictionary) -> void:
	var nav := level.get_node(^"Navigation") as NavBuilder
	var foot := Rect2(AT.x - 19.0, AT.z - 19.0, 38.0, 38.0)
	var lo := NavBuilder.chunk_at(Vector3(foot.position.x, 0, foot.position.y))
	var hi := NavBuilder.chunk_at(Vector3(foot.end.x, 0, foot.end.y))
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var chunk := Vector2i(cx, cz)
			if nav.region_of(chunk) == null:
				continue
			var source := nav._ground_source(chunk)
			var bounds := NavBuilder._bake_bounds(chunk)
			var local := world.global_transform.affine_inverse() * bounds
			for box in world.solid_boxes_m(local):
				source.add_faces(NavBuilder._box_faces(box), world.global_transform)
			if not BuildingGen.ramp_faces(b).is_empty():
				source.add_faces(BuildingGen.ramp_faces(b), world.global_transform)
			var mesh := NavBuilder._new_mesh(chunk)
			NavigationServer3D.bake_from_source_geometry_data(mesh, source)
			nav.region_of(chunk).navigation_mesh = mesh


func _wait_until(cond: Callable, timeout: float) -> bool:
	var left := timeout
	while left > 0.0:
		if cond.call():
			return true
		await get_tree().create_timer(0.25).timeout
		left -= 0.25
	return cond.call()


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
