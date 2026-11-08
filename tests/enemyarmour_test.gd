extends Node
## Headless checks for combined arms D6a/D6b (cg_brief queue items 4.1 and 4.2;
## docs/combined_arms.md 7): the T-72B3, BMP-2, BTR-82A, MT-LB, the three HEMTTs, the rhino truck,
## the armoured SUV and the captured MaxxPro. Nobody has looked at these models by eye, so this
## measures them: the canvas's size against the real vehicle's, its voxel count, what's connected
## to what, the turret and gun parts split out at the right place, every seat, action point,
## muzzle, plate, tile and module where something is drawn; every model parked level on a slab;
## the T-72B3's autoloader, the BMP-2's guns and its Konkurs fired for real; a round through a
## real plate; the faction tables; save and load; then a second process joins over ENet and
## finds the vehicles as the host has them.
##   <voxel godot exe> --headless --path . res://tests/enemyarmour_test.tscn
## The host starts the client itself ("-- --enemyarmour-join"). Exits with the number of failures.

## model: [length, width, height (m, the real vehicle's, gun forward where it reaches past the
## nose)]. Height is taken to the highest layer with some size, so an antenna doesn't count.
const REAL := {
	"t72b3": [9.53, 3.7, 2.45],  # (to the top of the cupola's 12.7 mm)
	"bmp2": [7.4, 3.15, 2.45],
	"btr82a": [8.2, 2.9, 2.6],
	"mtlb": [6.45, 2.86, 1.87],
	"hemtt_cargo": [10.16, 2.44, 2.84],
	"m978": [10.16, 2.44, 2.95],
	"hemtt_ammo": [10.16, 2.44, 2.84],
	"kestrel_rhino": [8.1, 2.5, 3.7],  # (with its plated turret)
	"armoured_suv": [5.25, 2.05, 1.86],
	"maxxpro_captured": [6.5, 3.1, 3.3],
}
const TOLERANCE := 0.1
const LAYER_MIN := 40  # voxels in a layer for it to count as body
const RIG_Y := 300.0

var failures := 0
var level: CompoundLevel
var layer: VehicleLayer
var player: Soldier
var expect: Dictionary = {}
var _client_lines := PackedStringArray()
var _client_failures := -1
var _client_ready := false
var _n := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_enemyarmour" + tag  # never touch a real save
	CompoundLevel.spawn_ai = false
	PeopleLayer.populate = false
	if "--enemyarmour-join" in OS.get_cmdline_user_args():
		_run_client()
		return
	GameState.delete_save()
	get_tree().create_timer(420.0).timeout.connect(func() -> void:
		print("ENEMYARMOUR TEST FAILED (timed out)")
		get_tree().quit(99))
	_test_data()
	_test_factions()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	var anchor := VoxelViewer.new()
	anchor.name = "TestViewer"
	anchor.view_distance = VoxelWorld.VIEW_DISTANCE
	anchor.requires_visuals = false
	anchor.requires_collisions = true
	level.add_child(anchor)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	layer = VehicleLayer.of(level)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0.1, 0)
	Vehicle.fire_rolls = true
	await _test_geometry()
	await _test_on_the_ground()
	await _test_guns()
	await _test_hits()
	await _test_qrf()
	await _test_save()
	await _test_client()
	GameState.delete_save()
	print("ENEMYARMOUR TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- Data -----------------------------------------------------------------------------------

func _test_data() -> void:
	print("The models' data")
	var kinds := func(m: String) -> Dictionary:
		var by := {}
		for seat: Dictionary in VehicleSpecs.spec(m).seats:
			by[String(seat.kind)] = int(by.get(String(seat.kind), 0)) + 1
		return by
	check(kinds.call("t72b3") == {"driver": 1, "gunner": 1, "commander": 1}, "T-72B3: driver, gunner, commander (%s)" % kinds.call("t72b3"))
	check(kinds.call("bmp2") == {"driver": 1, "gunner": 1, "commander": 1, "passenger": 7}, "BMP-2: 3 crew and 7 riders (%s)" % kinds.call("bmp2"))
	check(kinds.call("btr82a") == {"driver": 1, "commander": 1, "gunner": 1, "passenger": 7}, "BTR-82A: 3 crew and 7 riders (%s)" % kinds.call("btr82a"))
	check(kinds.call("mtlb") == {"driver": 1, "gunner": 1, "passenger": 11}, "MT-LB: 2 crew and 11 riders (%s)" % kinds.call("mtlb"))
	check(kinds.call("kestrel_rhino") == {"driver": 1, "passenger": 7, "gunner": 1}, "rhino: driver, co-driver, 6 shooters, a gunner (%s)" % kinds.call("kestrel_rhino"))
	check(kinds.call("armoured_suv") == {"driver": 1, "passenger": 2, "gunner": 1}, "armoured SUV: 4 up, one on the roof gun (%s)" % kinds.call("armoured_suv"))
	for m: String in ["hemtt_cargo", "m978", "hemtt_ammo"]:
		check(kinds.call(m) == {"driver": 1, "passenger": 1} and VehicleSpecs.spec(m).get("gun", {}).is_empty(), "%s: two in the cab, unarmed" % m)
	var fx := VehicleSpecs.spec("t72b3").get("fx", {}) as Dictionary
	check(VehicleSmoke.has_dischargers(VehicleSpecs.spec("t72b3")) and (fx.racks as Dictionary).ammo_carousel.big and VehicleSpecs.spec("t72b3").get("power_kw", 0) == 840,
		"the T-72B3's smoke, its carousel a big rack, its 840 kW from vehicle_drive.json")
	check(float(VehicleSpecs.spec("m978").get("mass_kg", 0)) > 18000.0 and VehicleLogistics.data().fuel.tankers.has("m978"), "the M978 is the tanker A8's data waits for")
	check(VehicleWeapons.short_name("9m119m") == "ATGM" and VehicleWeapons.short_name("3bm42") == "SABOT", "the readout names the 9M119M and the sabot")
	var t := VehicleWeapons.layout(VehicleSpecs.spec("t72b3"))
	var names: Array = t.map(func(m: Dictionary) -> String: return "%s:%s" % [m.id, m.kind])
	check(names == ["main:cannon", "coax:mg", "commander_nsvt:mg"] and is_equal_approx(float(t[0].auto_s), 7.5), "T-72B3: 2A46M on an autoloader (7.5 s), coax, the commander's 12.7 (%s)" % [names])
	var racks := VehicleWeapons.default_racks(VehicleSpecs.spec("t72b3"))
	var modules := {}
	for mod: Dictionary in VehicleSpecs.spec("t72b3").modules:
		modules[String(mod.id)] = mod
	check(VehicleWeapons._sum(racks.ammo_carousel) == 22 and VehicleWeapons._sum(racks.ammo_rack_hull) == 20 and int(modules.ammo_carousel.rounds) == 22,
		"22 rounds in the carousel, 20 in the hull (2.7.1)")
	check(String(modules.ammo_carousel.on_detonate) == "catastrophic" and is_equal_approx(float(modules.ammo_carousel.detonate[1]), 0.75), "a CE penetration of the carousel: 0.75, catastrophic (2.10.2)")
	var bmp := VehicleWeapons.default_racks(VehicleSpecs.spec("bmp2"))
	check(bmp.ready_30 == {"3ubr8": 160, "3uof8": 340} and bmp.rack_konkurs == {"konkurs_m": 4}, "BMP-2: 160 AP, 340 HE, 4 Konkurs (2.7.1)")
	check(VehicleWeapons._sum(VehicleWeapons.default_racks(VehicleSpecs.spec("btr82a")).ready_30) == 300, "BTR-82A: 300 rounds (2.7.1)")
	var rated := ArmourStandards.rating(VehicleSpecs.spec("t72b3"))
	check(int(rated.ke.front) == 6 and String(rated.mine.wheel) == "2a", "T-72B3: STANAG front 6, mine 2a/1 as %s" % ArmourStandards.text(VehicleSpecs.spec("t72b3")))
	check(ArmourStandards.ke_overall(ArmourStandards.rating(VehicleSpecs.spec("armoured_suv")).ke) == 0 and ArmourModel.tiles_at(VehicleSpecs.spec("maxxpro_captured"), Vector3(1.3, 1.5, 0.5)).size() == 1,
		"the SUV isn't a STANAG build; the captured MaxxPro keeps its slat with no package")


# --- Faction tables -------------------------------------------------------------------------

func _test_factions() -> void:
	print("The factions' vehicle tables (7.1)")
	var unknown := PackedStringArray()
	for f: Dictionary in MissionRegistry.factions():
		var t: Dictionary = f.get("vehicles", {})
		for use: String in ["patrol", "qrf", "convoy_cargo", "convoy_escort", "park", "armour"]:
			for m: Variant in FactionVehicles.models(f.id, use):
				if not VehicleArt.MODELS.has(String(m)) or not VehicleSpecs.has_model(String(m)):
					unknown.append("%s %s %s" % [f.id, use, m])
		for tier: Variant in t.get("by_tier", {}):
			for m: Variant in FactionVehicles.models(f.id, "qrf", int(tier)):
				if not VehicleArt.MODELS.has(String(m)):
					unknown.append("%s tier %s %s" % [f.id, tier, m])
	check(unknown.is_empty(), "every model a faction fields has art and numbers (%s)" % ", ".join(unknown))
	for f: String in ["black_ridge", "ashen_banner", "valley_shura", "saltline", "kestrel", "highland_front", "eastern_concord", "vantage_group"]:
		check(not FactionVehicles.models(f, "patrol").is_empty() and not FactionVehicles.models(f, "qrf").is_empty() and not FactionVehicles.models(f, "convoy_cargo").is_empty(),
			"%s patrols, sends QRFs and runs convoys in vehicles" % f)
	check(FactionVehicles.models("eastern_concord", "patrol") == ["btr82a", "mtlb"] and FactionVehicles.models("eastern_concord", "armour") == ["t72b3"]
		and FactionVehicles.models("eastern_concord", "qrf", 2) == ["btr82a", "bmp2", "mtlb"] and FactionVehicles.models("eastern_concord", "qrf", 3) == ["btr82a", "bmp2", "bmp2"],
		"the Concord: BTRs and MT-LBs patrol, BMPs join its QRFs, a heavier mix from tier 3")
	check(FactionVehicles.pick("kestrel", "convoy_cargo", 0, "x") == "kestrel_rhino" and FactionVehicles.pick("nobody", "convoy_cargo", 0, "x") == "x"
		and FactionVehicles.pick("ashen_banner", "armour", 0, "x") == "maxxpro_captured" and FactionVehicles.pick("highland_front", "armour", 0, "x") == "mtlb",
		"the cartel's convoy truck is the rhino, a faction with no table keeps the old model, the Banner's and the Front's captured armour")
	check(FactionVehicles.scheme("vantage_group", "armoured_suv") == "black" and FactionVehicles.scheme("highland_front", "mtlb") == "highland" and FactionVehicles.scheme("saltline", "armoured_suv") == "",
		"Vantage's SUVs are black, the Front's MT-LB is its own colour")
	check(FactionVehicles.packages("eastern_concord", "bmp2", 2).is_empty() and FactionVehicles.packages("eastern_concord", "bmp2", 3) == ["bmp2_kontakt1"], "the Concord's BMP-2s carry Kontakt-1 from Pressure tier 3 (2.4.5)")
	check(FactionVehicles.park("eastern_concord", 3, ["technical"]) == ["btr82a", "bmp2", "mtlb"] and FactionVehicles.park("nobody", 2, ["a", "b"]) == ["a", "b"], "a park has as many vehicles as its site, by faction")
	var inv: Dictionary = Operations.type_def("phased_invasion").get("enemy_oob_by", {})
	var thr: Dictionary = Operations.type_def("armoured_thrust").get("enemy_oob_by", {})
	var in_oob := {}
	for row: Dictionary in (inv.get("eastern_concord", []) as Array) + (thr.get("eastern_concord", []) as Array):
		for m: Variant in row.get("vehicles", []):
			in_oob[String(m)] = true
	check(in_oob.has_all(["t72b3", "bmp2", "btr82a"]) and in_oob.keys().all(func(m: String) -> bool: return VehicleSpecs.has_model(m)), "the invasion and the thrust have the Concord's order of battle (%s)" % [in_oob.keys()])
	var hauls: Array = []
	for row: Dictionary in Operations.type_def("phased_invasion").get("friendly_oob", []):
		if row.has("logistics"):
			hauls.append(row.vehicles[0])
	check("hemtt_ammo" in hauls and "m978" in hauls, "the invasion's ammunition and fuel trucks are HEMTTs now, not MaxxPros (%s)" % [hauls])
	check(UsField.models("us_forces", "convoy").has("hemtt_cargo"), "US convoys have HEMTTs in them")


# --- Geometry (the models, by the numbers) -----------------------------------------------------

func _test_geometry() -> void:
	print("The art, by the numbers (nobody has seen it: it needs a person's eyes)")
	for model: String in REAL:
		VehicleHull.prewarm(model)
	await _until(func() -> bool: return REAL.keys().all(func(m: String) -> bool: return VehicleHull.is_ready(m)), 60.0)
	for model: String in REAL:
		_measure(model)


func _measure(model: String) -> void:
	var whole: Variant = VehicleArt._shape_for(model)  # drawn, before the turret's lifted out
	var cv := VehicleHull.canvas(model)
	var size: Vector3i = whole.size
	var vs: float = whole.vs
	var halfz := size.z * vs * 0.5
	var lo := Vector3i(size)
	var hi := Vector3i(-1, -1, -1)
	var layer_count: Dictionary = {}
	var column_count: Dictionary = {}  # across x (so a mirror doesn't count towards the width)
	var solid := 0
	for x in size.x:
		for y in size.y:
			for z in size.z:
				if whole.get_at(x, y, z) != VehicleArt.P.EMPTY:
					solid += 1
					lo = lo.min(Vector3i(x, y, z))
					hi = hi.max(Vector3i(x, y, z))
					layer_count[y] = int(layer_count.get(y, 0)) + 1
					column_count[x] = int(column_count.get(x, 0)) + 1
	var body_top := 0
	for y: int in layer_count:
		if int(layer_count[y]) >= LAYER_MIN:
			body_top = maxi(body_top, y)
	var x_lo := size.x
	var x_hi := -1
	for x: int in column_count:
		if int(column_count[x]) >= LAYER_MIN:
			x_lo = mini(x_lo, x)
			x_hi = maxi(x_hi, x)
	var length := (hi.z - lo.z + 1) * vs
	var width := (x_hi - x_lo + 1) * vs
	var height := (body_top + 1) * vs
	var r: Array = REAL[model]
	var ok := absf(length - float(r[0])) <= float(r[0]) * TOLERANCE and absf(width - float(r[1])) <= float(r[1]) * TOLERANCE and absf(height - float(r[2])) <= float(r[2]) * TOLERANCE
	check(ok, "%s: %.2f x %.2f x %.2f m, real %.2f x %.2f x %.2f (within %d%%), %d voxels" % [model, length, width, height, r[0], r[1], r[2], int(TOLERANCE * 100), solid])
	check(solid >= 6000 and solid <= 400000, "%s: a sane voxel count (%d)" % [model, solid])
	# Everything hangs together: one connected body (26 neighbours), bar a few loose voxels.
	var parts := _components(whole, size, vs, halfz)
	check(float(parts.largest) / float(solid) >= 0.9, "%s: %.1f%% of it is one connected body (%d pieces; the loose ones: %s)" % [model, 100.0 * float(parts.largest) / float(solid), parts.count, parts.loose])
	var spec := VehicleSpecs.spec(model)
	var extent := AABB()
	for b: Array in spec.boxes:
		extent = extent.merge(VehicleSpecs.box(b)) if extent.has_volume() else VehicleSpecs.box(b)
	var problems := PackedStringArray()
	var near := func(p: Vector3, reach := 0.2) -> bool:  # data frame
		var c := Vector3i(floori(p.x / vs + size.x * 0.5), floori(p.y / vs), floori((p.z + halfz) / vs))
		var n := ceili(reach / vs)
		for x in range(c.x - n, c.x + n + 1):
			for y in range(c.y - n, c.y + n + 1):
				for z in range(c.z - n, c.z + n + 1):
					if whole.get_at(x, y, z) != VehicleArt.P.EMPTY:
						return true
		return false
	for i in (spec.seats as Array).size():
		var at: Vector3 = VehicleSpecs.vec(spec.seats[i].at)
		if not extent.grow(0.75).has_point(at):
			problems.append("seat %d off the hull" % i)
	for p: Dictionary in spec.points:
		var at: Vector3 = VehicleSpecs.vec(p.at)
		if extent.grow(-0.02).has_point(at):
			problems.append("%s point inside the hull" % p.kind)
		if not extent.grow(1.6).has_point(at):
			problems.append("%s point far off" % p.kind)
	for z: Dictionary in spec.zones:
		if not _box_has_voxels(whole, size, vs, halfz, z.box):
			problems.append("zone %s has nothing drawn" % z.zone)
	for pl: Dictionary in spec.get("plates", []):
		if not _box_has_voxels(whole, size, vs, halfz, pl.box):
			problems.append("plate %s has nothing drawn" % pl.id)
	for t: Dictionary in spec.get("tiles", []):
		if not bool(t.has("package")) and not _box_has_voxels(whole, size, vs, halfz, t.box):
			problems.append("tiles %s aren't drawn" % t.group)
	for m: Dictionary in spec.get("modules", []):
		if m.has("box") and String(m.kind) != "compartment" and not extent.grow(0.8).encloses(VehicleSpecs.box(m.box)) and not bool(VehicleModules.layout(spec).filter(func(x: Dictionary) -> bool: return String(x.id) == String(m.id))[0].external):
			problems.append("module %s off the hull" % m.id)
	var gun: Dictionary = spec.get("gun", {})
	if gun.has("at") and not near.call(VehicleSpecs.vec(gun.at), 0.2):
		problems.append("the gun's muzzle isn't at the gun")
	for w: Dictionary in spec.get("weapons", []):
		if w.has("muzzle") and not near.call(VehicleSpecs.vec(w.muzzle), 0.25):
			problems.append("the %s's muzzle isn't at it" % w.id)
	check(problems.is_empty(), "%s: seats, doors, zones, plates, tiles, modules and muzzles where it's drawn (%s)" % [model, ", ".join(problems)])
	if spec.has("turret") and not gun.is_empty():
		var by_name := {}
		for p: Dictionary in cv.parts:
			by_name[String(p.name)] = (p.size as Vector3i)
		check(by_name.has("Turret") and by_name.has("Gun"), "%s: a turret and a gun that turn (%s)" % [model, by_name])
		if by_name.has("Gun"):
			var gun_len := float((by_name.Gun as Vector3i).z) * vs
			check(gun_len >= 0.45, "%s: its gun's length out of the mantlet: %.2f m" % [model, gun_len])


func _box_has_voxels(whole: Variant, size: Vector3i, vs: float, halfz: float, box_a: Array) -> bool:
	var box := VehicleSpecs.box(box_a)
	var a := Vector3i(floori(box.position.x / vs + size.x * 0.5), floori(box.position.y / vs), floori((box.position.z + halfz) / vs))
	var b := Vector3i(floori(box.end.x / vs + size.x * 0.5), floori(box.end.y / vs), floori((box.end.z + halfz) / vs))
	for x in range(maxi(a.x, 0), mini(b.x + 1, size.x)):
		for y in range(maxi(a.y, 0), mini(b.y + 1, size.y)):
			for z in range(maxi(a.z, 0), mini(b.z + 1, size.z)):
				if whole.get_at(x, y, z) != VehicleArt.P.EMPTY:
					return true
	return false


## {"largest", "count", "loose": [[voxels, data-frame metres of its first voxel]]}: the connected
## pieces of solid voxels (26 neighbours), the loose ones biggest first.
func _components(whole: Variant, size: Vector3i, vs: float, halfz: float) -> Dictionary:
	var seen := PackedByteArray()
	seen.resize(size.x * size.y * size.z)
	var largest := 0
	var count := 0
	var pieces: Array = []
	var stack: Array[Vector3i] = []
	var at := func(v: Vector3i) -> int: return v.x + v.y * size.x + v.z * size.x * size.y
	for x in size.x:
		for y in size.y:
			for z in size.z:
				var p := Vector3i(x, y, z)
				if seen[at.call(p)] != 0 or whole.get_at(x, y, z) == VehicleArt.P.EMPTY:
					continue
				var n := 0
				stack = [p]
				seen[at.call(p)] = 1
				while not stack.is_empty():
					var c: Vector3i = stack.pop_back()
					n += 1
					for dx in [-1, 0, 1]:
						for dy in [-1, 0, 1]:
							for dz in [-1, 0, 1]:
								var q: Vector3i = c + Vector3i(dx, dy, dz)
								if q.x < 0 or q.y < 0 or q.z < 0 or q.x >= size.x or q.y >= size.y or q.z >= size.z:
									continue
								if seen[at.call(q)] == 0 and whole.get_at(q.x, q.y, q.z) != VehicleArt.P.EMPTY:
									seen[at.call(q)] = 1
									stack.append(q)
				count += 1
				largest = maxi(largest, n)
				pieces.append([n, Vector3((x + 0.5 - size.x * 0.5) * vs, (y + 0.5) * vs, (z + 0.5) * vs - halfz)])
	pieces.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	return {"largest": largest, "count": count, "loose": pieces.slice(1, 6)}


# --- Parked and driven ---------------------------------------------------------------------------

func _test_on_the_ground() -> void:
	print("Parked level on a slab, and driven")
	var slab := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	col.shape = box
	slab.add_child(col)
	slab.collision_layer = 1
	level.add_child(slab)
	slab.global_position = Vector3(0, RIG_Y - 1.0, 0)
	var spaced := 0
	var models: Array = REAL.keys()
	var vehicles := []
	for model: String in models:
		var v := await _spawn(model, Vector3(-150 + spaced * 16.0, RIG_Y + 0.5, 60), 0.0, &"player", false)
		spaced += 1
		vehicles.append(v)
	await _seconds(5.0)
	for v: Vehicle in vehicles:
		var height: float = v.global_position.y - RIG_Y
		check(absf(height) < 0.25 and v.global_basis.y.dot(Vector3.UP) > 0.995, "%s: stands level on its running gear (%.2f m up)" % [v.model, height])
	# Three drive off under an AI driver: wheels, tracks and the long truck.
	for model: String in ["btr82a", "t72b3", "hemtt_cargo"]:
		var v: Vehicle = vehicles[models.find(model)]
		var driver := await _crew(v, [0])
		var start := v.global_position
		v.server_drive_to(start + Vector3(0, 0, -60.0), 25.0)
		await _until(func() -> bool: return v.global_position.distance_to(start) > 25.0, 30.0)
		check(v.global_position.distance_to(start) > 15.0, "%s: drives off (%.1f m in the time allowed)" % [model, v.global_position.distance_to(start)])
		for s: Soldier in driver:
			v.server_exit(s)
	await _physics(2)
	for v: Vehicle in vehicles:
		if is_instance_valid(v):
			v.queue_free()
	slab.queue_free()
	await _physics(3)


# --- The guns ------------------------------------------------------------------------------------

func _test_guns() -> void:
	print("The guns fired for real")
	var mbt := await _spawn("t72b3", Vector3(-200, RIG_Y, -60), 0.0)
	var crew := await _crew(mbt, [1])
	var w := mbt.weapons
	var carousel_before := w.rack_total("ammo_carousel")
	check(w.loaded("main") == "3bm42", "it comes with a sabot in the breech (%s)" % w.loaded("main"))
	var r := w.server_fire(crew[0], "main")
	check(bool(r.get("ok", false)) and String(r.get("round", "")) == "3bm42", "the gunner fires it (%s)" % [r])
	check(w.loaded("main") == "", "the breech is empty")
	await _physics(2)
	check(String(w.state.main.cy) == "short" and not w.busy_loading(crew[0]), "the autoloader cycles; the gunner stays on his sight")
	var left := float(w.state.main.end) - Soldier._now()
	check(left > 6.5 and left <= 7.5, "the cycle takes 7.5 s (%.1f left)" % left)
	await _until(func() -> bool: return w.loaded("main") != "", 9.0)
	check(w.loaded("main") == "3bm42" and w.rack_total("ammo_carousel") == carousel_before - 1, "one round less in the carousel, the next in the breech")
	await _clear(mbt, crew)
	var ifv := await _spawn("bmp2", Vector3(-225, RIG_Y, -60), 0.0)
	var ic := await _crew(ifv, [1])
	var iw := ifv.weapons
	var ap_before := iw.ready_of(iw.mount("main"), "3ubr8")
	var shot := iw.server_fire(ic[0], "main")
	check(bool(shot.get("ok", false)) and iw.ready_of(iw.mount("main"), "3ubr8") == ap_before - 1 and String(shot.get("round", "")) == "3ubr8", "the BMP-2's 2A42 fires AP from its box (%s)" % [shot])
	iw.server_switch_feed()
	await _seconds(VehicleWeapons.FEED_SWITCH_S + 0.2)
	iw._next.erase("main")
	shot = iw.server_fire(ic[0], "main")
	check(String(shot.get("round", "")) == "3uof8", "and HE from the other feed (%s)" % [shot])
	iw.server_raise(true)
	await _seconds(VehicleWeapons.TOW_RAISE_S + 0.3)
	var m := iw.server_fire(ic[0], "tow")
	check(bool(m.get("ok", false)) and m.has("missile"), "the Konkurs-M comes off the rail (%s)" % [m])
	await _clear(ifv, ic)
	var apc := await _spawn("btr82a", Vector3(-250, RIG_Y, -60), 0.0)
	var ac := await _crew(apc, [2])
	var first := apc.weapons.server_fire(ac[0], "main")
	check(bool(first.get("ok", false)), "the BTR-82A's 2A72 fires (%s)" % [first])
	await _clear(apc, ac)
	# The coax and the roof guns go through Vehicle.server_fire_gun, as every AI gunner's does.
	for model: String in ["mtlb", "kestrel_rhino", "armoured_suv", "maxxpro_captured"]:
		var v := await _spawn(model, Vector3(-275 - _n * 2.0, RIG_Y, -60), 0.0, &"hostile")
		var seat := int(v.spec.gun.seat)
		var c := await _crew(v, [seat])
		v.turret.aim(0.0, deg_to_rad(5.0))
		v.turret.settle()
		var fired := v.server_fire_gun(c[0], -v.global_basis.z)
		check(not fired.is_empty() and v.gun_info(seat).get("rounds", 0) > 0, "%s: its %s fires, with its load aboard (%s)" % [model, v.spec.gun.weapon, fired])
		await _clear(v, c)


func _test_hits() -> void:
	print("Rounds through the real plates")
	var flight := ShellFlight.of(level)
	var v := await _spawn("btr82a", Vector3(-320, RIG_Y, 40), 0.0, &"hostile")
	var hp0 := v.modules.health_of("structure")
	var origin := v.global_position + Vector3(0.0, 1.5, -0.5) + v.global_basis.x * 180.0
	var aim := (v.to_global(Vector3(1.4, 1.5, -0.5)) - origin).normalized()
	flight.server_fire(&"3ubr8", origin, aim * 1100.0, null, {})
	await _until(func() -> bool: return v.modules.health_of("structure") < hp0, 6.0)
	check(v.modules.health_of("structure") < hp0, "3UBR8 through a BTR-82A's side damages it (structure %.0f%%)" % [100.0 * v.modules.health_of("structure") / maxf(hp0, 0.001)])
	await _clear(v, [])
	var tank := await _spawn("t72b3", Vector3(-340, RIG_Y, 40), 0.0, &"hostile")
	var h0 := tank.modules.health_of("structure")
	var from := tank.to_global(Vector3(0.0, 1.8, -220.0))
	flight.server_fire(&"m792", from, (tank.to_global(Vector3(0.0, 1.8, -0.5)) - from).normalized() * 1100.0, null, {})
	await _seconds(1.0)
	check(tank.modules.health_of("structure") >= h0 * 0.97, "a 25 mm HEI on the T-72B3's turret front is nothing (structure %.0f%%)" % [100.0 * tank.modules.health_of("structure") / maxf(h0, 0.001)])
	await _clear(tank, [])
	var ifv := await _spawn("bmp2", Vector3(-360, RIG_Y, 40), 0.0, &"hostile")
	ifv.server_explosion(ifv.global_position + Vector3.UP * 1.8, "breaching_charge")
	check(ifv.can_drive(), "one demolition block on a BMP-2's deck doesn't stop its engine")
	ifv.server_explosion(ifv.global_position + Vector3.UP * 1.8, "breaching_charge")
	check(not ifv.can_drive(), "a second one does (a park of them is a sabotage target)")
	await _clear(ifv, [])


func _test_qrf() -> void:
	print("A faction's own vehicles come out (FactionVehicles in VehicleQrf)")
	var response := EnemyResponse.of(level)
	VehicleQrf.faction_override = "eastern_concord"
	if response:
		response.enemy_faction = &"eastern_concord"
	var was := VehicleQrf.share_override
	VehicleQrf.share_override = 1.0
	var men: Array = []
	var gate := level.ground_point(Vector3(150, 0, 150))
	for i in 6:
		men.append(_soldier("Rider%d" % i, &"hostile", gate + Vector3(i * 1.5, 0.0, 5.0)))
		await get_tree().physics_frame
	var mounted := VehicleQrf.server_mount(level, null, gate, gate + Vector3(0, 0, 300), men)
	var node := VehicleQrf.of(level)
	check(mounted and node != null and not node.convoys.is_empty() and (node.convoys[0].vehicle as Vehicle).model == "btr82a", "a Concord patrol that rides goes in a BTR-82A")
	if mounted and node != null and not node.convoys.is_empty():
		var rig: Vehicle = node.convoys[0].vehicle
		check(rig.occupants().size() >= 3, "its men are aboard (%d)" % rig.occupants().size())
		for s: Soldier in rig.occupants():
			rig.server_exit(s)
		rig.queue_free()
	VehicleQrf.share_override = was
	VehicleQrf.faction_override = ""
	if response:
		response.enemy_faction = &"black_ridge"
	for s: Soldier in men:
		if is_instance_valid(s):
			s.queue_free()
	await _physics(3)


func _test_save() -> void:
	print("Saved with the zone")
	var v := await _spawn("t72b3", Vector3(-30, RIG_Y, -120), 0.0)
	v.weapons.state.main.l = "3bk29m"
	v.weapons.state.main.n = "3of26"
	v.weapons.racks.ammo_carousel = {"3bm42": 3, "9m119m": 1}
	v.weapons._sync_rack("ammo_carousel")
	v.turret.aim(0.6, 0.1)
	v.turret.settle()
	var rec: Dictionary = JSON.parse_string(JSON.stringify(v.to_save()))
	rec.erase("pos")
	rec.erase("rot")
	rec.erase("bodies")
	var copy := layer.server_spawn(v.model, Transform3D(Basis(), v.global_position + Vector3(0, 0, 25)), v.scheme, &"player", "%s_copy" % v.vehicle_id, rec)
	copy.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	copy.freeze = true
	await _seconds(0.4)
	check(copy.weapons.loaded("main") == "3bk29m" and String(copy.weapons.state.main.n) == "3of26" and copy.weapons.rack_contents("ammo_carousel") == {"3bm42": 3, "9m119m": 1},
		"a T-72B3 comes back with the round it had loaded and its carousel as it was")
	check(copy.model == "t72b3" and copy.scheme == v.scheme, "as the same tank in the same paint")
	await _clear(v, [])
	await _clear(copy, [])


# --- A client joins ----------------------------------------------------------------------------

func _test_client() -> void:
	print("Replication (a client joins)")
	var mbt := await _spawn("t72b3", Vector3(60, RIG_Y, -180), 0.0, &"hostile")
	mbt.weapons.state.main.l = "3of26"
	mbt.weapons.state.main.n = "3bm42"
	mbt.turret.aim(0.9, 0.05)
	mbt.turret.settle()
	var flags := PackedByteArray([1, 0, 1])
	mbt.set_meta(ArmourModel.META_TILES, {"k5_glacis": flags})
	var truck := await _spawn("m978", Vector3(85, RIG_Y, -180), 0.0, &"friendly")
	var suv := await _spawn("armoured_suv", Vector3(110, RIG_Y, -180), 0.0, &"hostile")
	suv.scheme = "black"
	await _seconds(0.3)
	var lg := VehicleLogistics.of(mbt)
	if lg:
		lg._publish()
	mbt.weapons._publish()
	expect = {"mbt": String(mbt.vehicle_id), "truck": String(truck.vehicle_id), "suv": String(suv.vehicle_id), "yaw": mbt.turret.yaw,
		"state": mbt.weapons.net_state.duplicate(true)}
	var log_path := OS.get_user_data_dir().path_join("enemyarmour_client%s.log" % OS.get_environment("CONTRACTOR_TEST_TAG"))
	DirAccess.remove_absolute(log_path)
	var args := ["--headless", "--log-file", log_path, "--path", ProjectSettings.globalize_path("res://"), "res://tests/enemyarmour_test.tscn", "--", "--enemyarmour-join"]
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "started the client process")
	await _until(func() -> bool: return _client_ready, 180.0)
	check(_client_ready, "the client checked the vehicles it found on joining")
	await _until(func() -> bool: return _client_failures >= 0, 45.0)
	for line in _client_lines:
		print("    client: %s" % line)
	check(_client_failures == 0, "everything replicated to the client (%d client failures)" % _client_failures)
	if pid > 0:
		await _until(func() -> bool: return not OS.is_process_running(pid), 10.0)
		if OS.is_process_running(pid):
			OS.kill(pid)
	var errors := PackedStringArray()
	if FileAccess.file_exists(log_path):
		for line in FileAccess.get_file_as_string(log_path).split("\n"):
			if line.contains("SCRIPT ERROR") or line.begins_with("ERROR:"):
				errors.append(line)
	for line in errors:
		print("    client: %s" % line)
	check(FileAccess.file_exists(log_path) and errors.is_empty(), "no errors in the client's log (%d)" % errors.size())


@rpc("any_peer", "call_remote", "reliable")
func _expect(data: Dictionary) -> void:
	expect = data


@rpc("any_peer", "call_remote", "reliable")
func _ask_expect() -> void:
	if multiplayer.is_server() and not expect.is_empty():
		_expect.rpc_id(multiplayer.get_remote_sender_id(), expect)


@rpc("any_peer", "call_remote", "reliable")
func _ready_for_live() -> void:
	_client_ready = true


@rpc("any_peer", "call_remote", "reliable")
func _client_report(count: int, lines: PackedStringArray) -> void:
	_client_lines = lines
	_client_failures = count


func _run_client() -> void:
	get_tree().create_timer(280.0).timeout.connect(func() -> void: get_tree().quit(99))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	if Net.session_ended.is_connected(Callable(main, &"_on_session_ended")):
		Net.session_ended.disconnect(Callable(main, &"_on_session_ended"))
	await get_tree().process_frame
	var lines := PackedStringArray()
	var note := func(ok: bool, what: String) -> void:
		lines.append("[%s] %s" % ["ok" if ok else "FAIL", what])
		if not ok:
			failures += 1
	var joined := await _join_host("127.0.0.1", 120.0)
	var asked_until := Time.get_ticks_msec() + 40000
	while joined and expect.is_empty() and Time.get_ticks_msec() < asked_until:
		_ask_expect.rpc_id(1)
		await _until(func() -> bool: return not expect.is_empty(), 3.0)
	level = CompoundLevel.current(self)
	if level == null or expect.is_empty():
		note.call(false, "joined and got the host's expectations")
	else:
		var find := func(id: String) -> Vehicle:
			for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
				if (n as Vehicle).vehicle_id == id:
					return n as Vehicle
			return null
		await _until(func() -> bool: return find.call(String(expect.mbt)) != null and find.call(String(expect.truck)) != null and find.call(String(expect.suv)) != null, 40.0)
		var mbt: Vehicle = find.call(String(expect.mbt))
		var truck: Vehicle = find.call(String(expect.truck))
		var suv: Vehicle = find.call(String(expect.suv))
		await _until(func() -> bool: return mbt != null and mbt.weapons.net_state.get("m", {}).get("main", {}).get("l", "") == "3of26", 20.0)
		await _until(func() -> bool: return mbt != null and VehicleHull.is_ready("t72b3") and VehicleHull.is_ready("m978"), 30.0)
		var state_ok: bool = mbt != null and mbt.weapons.loaded("main") == "3of26" and mbt.weapons.rack_total("ammo_carousel") == int(VehicleWeapons._sum(expect.state.r.ammo_carousel))
		note.call(state_ok, "the T-72B3's breech and carousel as the host has them (late join)")
		note.call(mbt != null and mbt.turret != null and absf(wrapf(mbt.turret.yaw - float(expect.yaw), -PI, PI)) < 0.05, "its turret turned as the host has it")
		note.call(mbt != null and mbt.hull.art != null and mbt.hull.art.get_node_or_null(^"Turret/Gun/Mesh") != null, "the tank's art is built here, its gun a part of its own")
		var lg := VehicleLogistics.of(mbt) if mbt else null
		note.call(lg != null and lg.fired_tiles().get("k5_glacis", []) == [0, 2], "the Kontakt-5 bricks fired on the host are gone here (%s)" % [lg.fired_tiles() if lg else {}])
		note.call(truck != null and truck.hull.art != null and truck.seat_count() == 2, "the tanker truck is here, drawn, two seats")
		note.call(suv != null and suv.turret != null and suv.hull.art.get_node_or_null(^"Turret/Gun") != null and suv.gun_info(3).size() > 0, "the armoured SUV is here with its roof gun")
		_ready_for_live.rpc_id(1)
	_client_report.rpc_id(1, failures, lines)
	await get_tree().create_timer(1.0).timeout
	Net.leave()
	get_tree().quit(failures)


func _join_host(address: String, seconds: float) -> bool:
	var joined := [false]
	Net.joined.connect(func() -> void: joined[0] = true)
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not (joined[0] or 1 in multiplayer.get_peers()) and Time.get_ticks_msec() < deadline:
		var peer := multiplayer.multiplayer_peer
		if not (peer is ENetMultiplayerPeer) or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			Net.join(address)
		await get_tree().create_timer(2.0).timeout
	return joined[0] or 1 in multiplayer.get_peers()


# --- Helpers --------------------------------------------------------------------------------

func _spawn(model: String, pos: Vector3, yaw: float, faction := &"player", frozen := true) -> Vehicle:
	VehicleHull.prewarm(model)
	_n += 1
	var v := layer.server_spawn(model, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos), "", faction, "ea_%s_%d" % [model, _n])
	if frozen:
		v.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		v.freeze = true
	v.server_rearm()
	await _until(func() -> bool: return VehicleHull.is_ready(model), 20.0)
	await _seconds(0.3)
	return v


## AI soldiers in `seats` of `v` (their brains off), seated.
func _crew(v: Vehicle, seats: Array) -> Array:
	var out: Array = []
	for seat: int in seats:
		var s := _soldier("%s%d_%d" % [v.model.capitalize(), seat, _n], &"friendly", v.global_position + Vector3(4.0, 0.0, float(seat)))
		await get_tree().physics_frame
		v.server_enter(s, seat)
		out.append(s)
		_n += 1
	await _seconds(0.5)
	return out


func _soldier(callsign: String, faction: StringName, pos: Vector3) -> Soldier:
	var s := level.spawn_soldier({"name": callsign, "person_name": callsign, "faction": String(faction), "variant": "woodland", "pos": pos,
		"loadout": [], "combat": 0.5, "discipline": 0.6, "guard": true})
	SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
	return s


func _clear(v: Vehicle, people: Array) -> void:
	if is_instance_valid(v):
		for s: Soldier in v.occupants():
			v.server_exit(s)
	await _physics(2)
	for p: Variant in people:
		if is_instance_valid(p) and p != player:
			(p as Node).queue_free()
	if is_instance_valid(v):
		v.queue_free()
	await _physics(2)


func _until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return cond.call()


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
