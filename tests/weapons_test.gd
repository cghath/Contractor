extends Node
## Headless checks of weapon pack 1 (stand-in OPFOR guns and more BLUFOR guns): every new weapon
## has its ammo, rounds, loose rounds, price and a voxel model; fires its round and reloads from
## its own magazine or belt; each round keeps to the armor and vehicle rules; the hostile
## faction's kits are AK-family guns; the autorifleman role carries the M249.
##   <voxel godot exe> --headless --path . res://tests/weapons_test.tscn
## Exits with the number of failures.

## weapon id -> [ammo id, round id, loose rounds id, ladder level, round class]
const GUNS := {
	"akm": ["mag_762x39", "762x39_msc", "rounds_762x39", "III+", "intermediate"],
	"ak74": ["mag_545", "545x39_7n6", "rounds_545", "III++", "intermediate"],
	"rpk": ["mag_rpk40", "762x39_msc", "rounds_762x39", "III+", "intermediate"],
	"pkm": ["belt_762x54r", "762x54r_lps", "rounds_762x54r", "III++", "full_power"],
	"svd": ["mag_svd", "762x54r_lps", "rounds_762x54r", "III++", "full_power"],
	"m249": ["box_556", "556_m855", "rounds_556", "III++", "intermediate"],
	"m240b": ["belt_762x51", "762x51_m80", "rounds_762", "III+", "full_power"],
	"scar_h": ["mag_762", "762x51_m80", "rounds_762", "III+", "full_power"],
	"m27": ["mag_556", "556_m855", "rounds_556", "III++", "intermediate"],
	"hk416": ["mag_556", "556_m855", "rounds_556", "III++", "intermediate"],
	"l85a2": ["mag_556", "556_m855", "rounds_556", "III++", "intermediate"],
	"c8": ["mag_556", "556_m855", "rounds_556", "III++", "intermediate"],
	"mosin9130": ["clip_762x54r", "762x54r_lps", "rounds_762x54r", "III++", "full_power"],
	"springfield_hs": ["mag_65cm", "65cm_eldm", "rounds_65cm", "III+", "full_power"],
}
## Magazines and belts: capacity.
const CAPACITY := {"mag_762x39": 30, "mag_545": 30, "mag_rpk40": 40, "mag_svd": 10, "belt_762x54r": 100, "box_556": 200, "belt_762x51": 100, "clip_762x54r": 5, "mag_65cm": 10, "mag_762": 20}
## Guns fired and reloaded for real on the host player.
const FIRED: Array[String] = ["akm", "ak74", "rpk", "pkm", "svd", "m249", "m240b", "mosin9130", "springfield_hs", "scar_h"]
const OPFOR: Array[String] = ["akm", "ak74", "rpk", "pkm", "svd"]

var failures := 0
var level: CompoundLevel
var player: Soldier


func _ready() -> void:
	GameState.zone_id = "test_weapons" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	Soldier.respawn_delay_s = 0.0
	Soldier.spawn_protect_s = 0.0
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	_test_data()
	_test_rounds_and_rules()
	_test_models()
	_test_reloads()
	_test_muzzle_point()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	for id: StringName in [&"plate_carrier", &"pouch_mag_double", &"ruck_45"]:
		player.inventory.take(id)
	await _frames(30)
	for id: String in FIRED:
		await _test_fire_and_reload(id)
	await _test_reload_beats()
	await _test_hostile_kits()
	_test_faction_kits()
	await _test_rival_pmc_kits()
	await _test_rival_pmc_exo_gating()
	_test_roles()
	GameState.delete_save()
	print("WEAPONS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _priced(id: StringName) -> bool:
	return Prices.price_of(id) > 0 and Prices.for_sale(id)


func _test_data() -> void:
	print("Every new gun and its ammo in the data")
	for id: String in GUNS:
		var g: Array = GUNS[id]
		var gun := ItemDB.get_item(StringName(id))
		var ammo := ItemDB.get_item(StringName(g[0]))
		check(gun != null and gun.type == "weapon" and gun.slot == &"primary", "%s is a primary weapon" % id)
		check(ammo != null and String(gun.stats.get("ammo", "")) == g[0], "%s takes %s" % [id, g[0]])
		check(ammo.magazine_rounds() > 0 and String(ammo.stats.round) == g[1], "%s holds %d rounds of %s" % [g[0], ammo.magazine_rounds(), g[1]])
		check(gun.default_state().get("rounds", 0) == ammo.magazine_rounds(), "%s comes loaded" % id)
		var loose := HeliCall.loose_rounds_for(StringName(g[0]))
		check(loose == g[2] and String(ItemDB.get_item(StringName(loose)).stats.round) == g[1], "%s's loose rounds are %s (%s)" % [g[0], g[2], loose])
		check(_priced(StringName(id)) and _priced(StringName(g[0])), "%s and %s are priced and for sale" % [id, g[0]])
		check(float(gun.stats.get("muzzle_velocity_mps", 0)) > 600.0 and float(gun.stats.rpm) > 0.0 and gun.tags.has("rifle"), "%s has real stats" % id)
	for mag: String in CAPACITY:
		check(ItemDB.get_item(StringName(mag)).magazine_rounds() == CAPACITY[mag], "%s holds %d" % [mag, CAPACITY[mag]])
	var cals := {}
	for m: String in ["mag_762x39", "mag_545", "mag_svd", "mag_762", "mag_556"]:
		cals[String(ItemDB.get_item(StringName(m)).stats.calibre)] = true
	check(cals.size() == 5, "five separate calibres (%s)" % ", ".join(cals.keys()))
	for pouch: String in ["pouch_mag_single", "pouch_mag_double"]:
		var accepts: Array = ItemDB.get_item(StringName(pouch)).stats.accepts
		check(accepts.has("mag_762x39") and accepts.has("mag_545") and accepts.has("mag_rpk40") and accepts.has("mag_svd"), "%s takes the new magazines" % pouch)
	for ak: String in ["akm", "ak74", "rpk", "pkm"]:
		check(not bool(ItemDB.get_item(StringName(ak)).stats.get("rail", false)), "%s has no rail (irons)" % ak)


func _test_rounds_and_rules() -> void:
	print("Rounds keep to the ladder, plate and vehicle rules")
	for id: String in GUNS:
		var g: Array = GUNS[id]
		var gun := ItemDB.get_item(StringName(id))
		check(String(Ballistics.threat_level(gun)) == g[3] and String(Ballistics.round_class(gun)) == g[4],
			"%s fires %s (%s, %s)" % [id, Ballistics.round_data(gun).get("name", "?"), Ballistics.threat_level(gun), Ballistics.round_class(gun)])
	for id: String in GUNS:  # vehicle armour: only 7.62x54R and above is more than small arms
		var tier := VehicleSpecs.round_tier(StringName(String(GUNS[id][1])))
		var want := 1 if String(GUNS[id][1]) == "762x54r_lps" else 0
		check(tier == want, "%s's round is vehicle tier %d (want %d)" % [id, tier, want])
	# plates: a light (level III) plate stops a .223 at most, not AK or 7.62 ball
	var akm := Ballistics.threat_level_at(ItemDB.get_item(&"akm"), 20.0)
	var m249_far := Ballistics.threat_level_at(ItemDB.get_item(&"m249"), 400.0)
	check(not ArmorRules.stops(&"III", akm), "a light III plate does not stop an AKM round (%s)" % akm)
	check(not ArmorRules.stops(&"III", Ballistics.threat_level_at(ItemDB.get_item(&"m240b"), 20.0)), "nor 7.62x51 ball")
	check(not ArmorRules.stops(&"III", Ballistics.threat_level_at(ItemDB.get_item(&"ak74"), 20.0)), "nor a close 5.45 7N6 (steel core)")
	check(ArmorRules.stops(&"III", m249_far), "but it does stop a far 5.56 (%s)" % m249_far)
	for id: String in GUNS:
		check(ArmorRules.stops(&"IV", Ballistics.threat_level_at(ItemDB.get_item(StringName(id)), 10.0)), "a ceramic IV plate stops %s" % id)
	var ak74 := ItemDB.get_item(&"ak74")
	check(Ballistics.threat_level_at(ak74, 50.0) == &"III++" and Ballistics.threat_level_at(ak74, 400.0) == &"III", "7N6 is III++ close and III far, like M855")
	check(Ballistics.energy_at(ItemDB.get_item(&"akm"), 0.0) > Ballistics.energy_at(ItemDB.get_item(&"m4a1"), 0.0), "an AKM round carries more energy than an M855")
	check(Ballistics.energy_at(ItemDB.get_item(&"m240b"), 0.0) > Ballistics.energy_at(ItemDB.get_item(&"akm"), 0.0), "7.62x51 beats 7.62x39")


func _test_models() -> void:
	print("Voxel models")
	for id: String in GUNS:
		var gun := ItemDB.get_item(StringName(id))
		var model := VoxelArt.model_for(gun)
		var mesh := VoxelArt.mesh(model, "multicam")
		check(model.begins_with("rifle:") and mesh != null and mesh.get_surface_count() > 0, "%s builds a model (%s)" % [id, model])
		check(not VoxelArt.hand_points(model).is_empty() and VoxelArt.butt_point(model) != Vector3.ZERO, "%s has hand points and a butt" % id)
	check(VoxelArt.model_for(ItemDB.get_item(&"akm")).contains(":ak:") and VoxelArt.model_for(ItemDB.get_item(&"m240b")).contains(":m240:") and VoxelArt.model_for(ItemDB.get_item(&"pkm")).contains(":pk:"), "AKs and machine guns have their own silhouettes")
	check(not VoxelArt.model_for(ItemDB.get_item(&"m4a1")).contains(":ak:"), "the M4 keeps its own")
	# The MG trio no longer shares one silhouette (Captain, reference photos, 2026-10-16): the
	# PKM, M240B and M249 each get their own model_style now, not two of them sharing "mg".
	check(VoxelArt.model_for(ItemDB.get_item(&"m249")).contains(":m249:") and not VoxelArt.model_for(ItemDB.get_item(&"m249")).contains(":m240:"),
		"the M249 has its own silhouette, not the M240B's")
	# The AR trio: L85A2 (bullpup), C8 (short carbine) and HK416 (piston) no longer fall through
	# to the generic AR silhouette they shared with the M27.
	check(VoxelArt.model_for(ItemDB.get_item(&"l85a2")).contains(":bullpup:"), "the L85A2 is a bullpup")
	check(VoxelArt.model_for(ItemDB.get_item(&"c8")).contains(":carbine_short:"), "the C8 is a short carbine")
	check(VoxelArt.model_for(ItemDB.get_item(&"hk416")).contains(":piston_ar:"), "the HK416 is piston-driven")
	check(VoxelArt.model_for(ItemDB.get_item(&"m27")).contains("::"), "the M27 still falls through to the generic AR silhouette (no model_style)")
	# The two bolt-action snipers: the Mosin-Nagant (vintage, "mosin") and the Springfield
	# Heatseeker (modern precision chassis, "chassis_bolt") have their own silhouettes too.
	check(VoxelArt.model_for(ItemDB.get_item(&"mosin9130")).contains(":mosin:"), "the Mosin-Nagant has its own silhouette")
	check(VoxelArt.model_for(ItemDB.get_item(&"springfield_hs")).contains(":chassis_bolt:"), "the Springfield Heatseeker has its own silhouette")
	check(ItemDB.get_item(&"mosin9130").stats.get("fire_modes", []) == ["bolt"] and ItemDB.get_item(&"springfield_hs").stats.get("fire_modes", []) == ["bolt"],
		"both bolt-action snipers only cycle between shots")
	check(VoxelArt.model_for(ItemDB.get_item(&"akm")).contains(":irons:") and VoxelArt.model_for(ItemDB.get_item(&"pkm")).contains(":irons:"),
		"an AK or MG with no rail shows iron sights, not a dead red-dot block (%s)" % VoxelArt.model_for(ItemDB.get_item(&"akm")))
	# Captain, 2026-10-16 (v0.4.26 on the ground: "the 249 is just missing a lot of its model"):
	# every gun is one solid piece, whatever sits on it (irons, an optic, a suppressor), with no
	# part floating free of the rest.
	for id: String in GUNS.keys() + ["m4a1", "m27"]:
		var parts := VoxelArt.model_for(ItemDB.get_item(StringName(id))).split(":")
		for art: String in ["irons", "dot", "holo", "lpvo", "scope_long"]:
			for sup: String in ["", "sup"]:
				var model := "%s:%s:%s:%s:%s" % [parts[0], parts[1], art, parts[3], sup]
				var pieces := _pieces(model)
				check(pieces.size() == 1, "%s is one solid piece (%s: %s)" % [id, model, pieces])


## Reloads (Captain, 2026-10-20: "reload anims also need work", and the L85's): every family's
## keys run 0 to 1 in order from rest back to rest, the magazine comes out as a part of its own
## (the weapon without it plus it: the same boxes), and an empty reload takes longer.
func _test_reloads() -> void:
	print("Reloads (2026-10-20)")
	var ok := true
	for fam: StringName in [Reloads.AR, Reloads.AK, Reloads.BULLPUP, Reloads.BELT, Reloads.BOLT, Reloads.BOLT_MAG, Reloads.PISTOL]:
		for empty: bool in [false, true]:
			var ks := Reloads.keys(fam, empty)
			var last := -1.0
			for k: Array in ks:
				ok = ok and float(k[0]) > last and k.size() == 8
				last = float(k[0])
			ok = ok and float(ks[0][0]) == 0.0 and last == 1.0 and ks[0][1] == &"rest" and ks[-1][1] == &"rest" 				and (ks[-1][3] as Vector3) == Vector3.ZERO and (ks[-1][4] as Vector3) == Vector3.ZERO
			var mid := Reloads.sample(ks, 0.5)
			ok = ok and (mid.rot as Vector3).length() > 0.1  # tipped in, mid-reload
	check(ok, "every family's reload keys run from rest to rest, tactical and empty")
	var fams := {}
	for id: StringName in [&"m4a1", &"akm", &"l85a2", &"pkm", &"m249", &"mosin9130", &"m17"]:
		if ItemDB.has_item(id):
			fams[id] = Reloads.family(ItemDB.get_item(id))
	check(fams.get(&"m4a1") == Reloads.AR and fams.get(&"akm") == Reloads.AK and fams.get(&"l85a2") == Reloads.BULLPUP
		and fams.get(&"pkm") == Reloads.BELT and fams.get(&"m249") == Reloads.BELT, "families: AR, AK, the L85 a bullpup, belt-feds (%s)" % fams)
	for id: StringName in [&"m4a1", &"akm", &"l85a2", &"pkm", &"m249"]:
		var model := VoxelArt.model_for(ItemDB.get_item(id))
		var whole := (VoxelArt._spec(model).boxes as Array).size()
		var mag := (VoxelArt._spec(VoxelArt.MAG + model).boxes as Array).size()
		var rest := (VoxelArt._spec(VoxelArt.WITHOUT_MAG + model).boxes as Array).size()
		var pts := VoxelArt.reload_points(model)
		check(VoxelArt.has_magazine(model) and mag > 0 and rest > 0 and mag + rest == whole and pts.has("mag") and pts.has("bolt"),
			"%s: its magazine comes out (%d of %d boxes), with places to take it and work the bolt" % [id, mag, whole])
	var l85 := VoxelArt.model_for(ItemDB.get_item(&"l85a2"))
	var lp := VoxelArt.reload_points(l85)
	var lh := VoxelArt.hand_points(l85)
	check((lp.mag as Vector3).z > (lh.grip as Vector3).z and lp.has("catch") and (lh.support as Vector3).z < (lh.grip as Vector3).z - 0.2,
		"the L85: its magazine behind the grip, a bolt release to press, the support hand out on the handguard")
	var plain := VoxelArt.model_for(ItemDB.get_item(&"m4a1"))
	var suppressed := plain.substr(0, plain.rfind(":") + 1) + "sup"
	check(VoxelArt._rifle_suppressed(suppressed) and VoxelArt.has_magazine(suppressed), "a suppressed rifle's magazine still comes out (%s)" % suppressed)
	var m4 := ItemDB.get_item(&"m4a1")
	check(Reloads.seconds(m4, true) > Reloads.seconds(m4, false) and is_equal_approx(Reloads.seconds(m4, false), float(m4.stats.reload_s)),
		"an empty reload works the bolt: %.1f s against %.1f" % [Reloads.seconds(m4, true), Reloads.seconds(m4, false)])
	_test_weapon_detail()


## Weapon detail pass (2026-10-20): each family's moving parts are tagged (the AR's carrier, the
## AK's carrier and handle, the L85's handle, a belt-fed's handle and feed cover and its belt, a
## bolt-action's bolt, a pistol's slide) and the weapon still adds up from its parts; their
## tracks and the sounds' beats run in order inside the reload; the parts come home by the end.
func _test_weapon_detail() -> void:
	print("Weapon detail: moving parts, beats (2026-10-20)")
	var want := {&"m4a1": ["bolt"], &"hk416": ["bolt"], &"c8": ["bolt"], &"l85a2": ["bolt"], &"akm": ["bolt"],
		&"pkm": ["bolt", "cover"], &"m249": ["bolt", "cover"], &"m240b": ["bolt", "cover"], &"mosin9130": ["bolt"], &"springfield_hs": ["bolt"]}
	for id: StringName in want:
		var model := VoxelArt.model_for(ItemDB.get_item(id))
		var parts := VoxelArt.moving_parts(model)
		parts.sort()
		var count := func(prefix: String) -> int: return (VoxelArt._spec(prefix + model).boxes as Array).size()
		var whole := (VoxelArt._spec(model).boxes as Array).size()
		var adds: bool = count.call(VoxelArt.FIXED) + count.call(VoxelArt.MAG) + count.call(VoxelArt.BOLT) + count.call(VoxelArt.COVER) == whole
		var pts := VoxelArt.reload_points(model)
		check(parts == want[id] and adds and (not parts.has("cover") or pts.has("cover")) and pts.has("bolt"),
			"%s: moving parts %s, the weapon adds up from them, a place for the hand on each" % [id, parts])
	check(VoxelArt.has_magazine("pistol") and VoxelArt.moving_parts("pistol") == ["bolt"] and _pieces("pistol").size() == 1,
		"the pistol's magazine and slide are parts of their own (Captain, 2026-10-20), and it's still one piece")
	var pk_spec := VoxelArt._spec(VoxelArt.model_for(ItemDB.get_item(&"pkm")))
	var pk_box: Array = VoxelArt._part_box(pk_spec, VoxelArt.MAG_TAG)
	var pk_belt: Array = VoxelArt._part_box(pk_spec, VoxelArt.BELT_TAG)
	check(((pk_box[0] as Vector3).x + (pk_box[1] as Vector3).x) * 0.5 > 1.5 and (pk_belt[1] as Vector3).x >= 3.0,
		"a realistic PKM (Captain, 2026-10-20): its box hangs on the right and the belt feeds in from the right")
	for g: Array in [[&"m4a1", 0.17], [&"hk416", 0.17], [&"akm", 0.18], [&"l85a2", 0.14]]:
		var box: Array = VoxelArt._part_box(VoxelArt._spec(VoxelArt.model_for(ItemDB.get_item(g[0]))), VoxelArt.MAG_TAG)
		var tall := ((box[1] as Vector3).y - (box[0] as Vector3).y) * VoxelArt.VOXEL_SIZE
		check(tall >= float(g[1]), "%s's magazine is full length: %.0f cm (a real one's about %.0f)" % [g[0], tall * 100.0, float(g[1]) * 100.0 + 1.0])
	var belt := VoxelArt.model_for(ItemDB.get_item(&"pkm"))
	var belted := (VoxelArt._spec(VoxelArt.MAG + belt).boxes as Array).any(func(b: Array) -> bool: return VoxelArt._tag(b) == VoxelArt.BELT_TAG)
	var motion := VoxelArt.part_motion(belt)
	check(belted and motion.has("hinge") and float(motion.open) > 1.0, "a belt-fed's belt comes off with its box, its cover hinges at the front")
	check(float(VoxelArt.part_motion(VoxelArt.model_for(ItemDB.get_item(&"mosin9130"))).lift) > 1.0, "a bolt-action's handle turns up")
	var ok := true
	var ids_ok := true
	for fam: StringName in [Reloads.AR, Reloads.AK, Reloads.BULLPUP, Reloads.BELT, Reloads.BOLT, Reloads.BOLT_MAG, Reloads.PISTOL]:
		for empty: bool in [false, true]:
			var tracks := Reloads.parts(fam, empty)
			for part: String in tracks:
				var last := -1.0
				for point: Array in tracks[part]:
					ok = ok and float(point[0]) > last and float(point[0]) <= 1.0
					last = float(point[0])
				ok = ok and is_zero_approx(Reloads.track(tracks[part], 1.0))  # home by the end
			var last_beat := -1.0
			for beat: Array in Reloads.beats(fam, empty):
				ok = ok and float(beat[0]) >= last_beat and float(beat[0]) < 1.0
				last_beat = float(beat[0])
				ids_ok = ids_ok and Sfx.defs.has(String(beat[1]))
			ok = ok and not Reloads.beats(fam, empty).is_empty()
	check(ok, "every family's part tracks and sound beats run in order inside the reload, the parts home by the end")
	check(ids_ok, "every beat's sound is defined (data/sounds.json)")
	var ar := Reloads.parts(Reloads.AR, true)
	var pk := Reloads.parts(Reloads.BELT, false)
	check(is_equal_approx(Reloads.track(ar.bolt, 0.3), 1.0) and is_zero_approx(Reloads.track(ar.bolt, 0.8)) and Reloads.parts(Reloads.AR, false).is_empty(),
		"an AR's empty reload: the carrier locked back until the catch is slapped; a tactical one leaves it home")
	check(is_equal_approx(Reloads.track(pk.cover, 0.5), 1.0) and is_zero_approx(Reloads.track(pk.cover, 0.1)) and not pk.has("bolt"),
		"a belt-fed's cover is up while the box is changed and down either side; a tactical one isn't charged")


## The separate (face-connected) pieces of model `model`'s voxels: each one's voxel count and
## bounding box, in the spec's voxels.
func _pieces(model: String) -> Array:
	var spec := VoxelArt._spec(model)
	var s: int = spec.get("sub", 1)
	var buffer := VoxelArt._rasterize(spec, "multicam", 0)
	var size := buffer.get_size()
	var seen := PackedByteArray()
	seen.resize(size.x * size.y * size.z)
	var out: Array = []
	for z in size.z:
		for y in size.y:
			for x in size.x:
				var start := Vector3i(x, y, z)
				if seen[(z * size.y + y) * size.x + x] or buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_COLOR) == VoxelArt.C.EMPTY:
					continue
				var count := 0
				var lo := start
				var hi := start
				var stack: Array[Vector3i] = [start]
				seen[(z * size.y + y) * size.x + x] = 1
				while not stack.is_empty():
					var p: Vector3i = stack.pop_back()
					count += 1
					lo = lo.min(p)
					hi = hi.max(p)
					for d: Vector3i in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
						var q := p + d
						if q.x < 0 or q.y < 0 or q.z < 0 or q.x >= size.x or q.y >= size.y or q.z >= size.z:
							continue
						var i := (q.z * size.y + q.y) * size.x + q.x
						if seen[i] or buffer.get_voxel(q.x, q.y, q.z, VoxelBuffer.CHANNEL_COLOR) == VoxelArt.C.EMPTY:
							continue
						seen[i] = 1
						stack.append(q)
				out.append("%d vox y %.2f-%.2f z %.2f-%.2f" % [count, (lo.y - 1) / float(s), hi.y / float(s), (lo.z - 1) / float(s), hi.z / float(s)])
	return out


func _test_fire_and_reload(id: String) -> void:
	print("%s: fires and reloads" % id)
	var g: Array = GUNS[id]
	var gun := ItemDB.get_item(StringName(id))
	var cap := int(CAPACITY[g[0]])
	var inv := player.inventory
	inv.slots[&"primary"] = &""
	inv.take(StringName(id))
	inv.take(StringName(g[0]), 2)
	check(inv.slots[&"primary"] == StringName(id) and inv.rounds_in(&"primary") == cap, "%s in hand with %d rounds" % [id, cap])
	player._server_busy_until = 0.0
	var aim := -player.global_basis.z
	var wait := 60.0 / float(gun.stats.rpm) + 0.1
	for i in 3:
		player._server_fire.rpc_id(1, player.head.global_position, aim, &"primary")
		await _seconds(wait)
	check(inv.rounds_in(&"primary") == cap - 3, "3 shots: %d left (%d)" % [cap - 3, inv.rounds_in(&"primary")])
	var spare := inv.spare_rounds(StringName(g[0]))
	player._server_reload.rpc_id(1, &"primary")
	await _seconds(player.reload_seconds(gun) + 0.5)
	check(inv.rounds_in(&"primary") == cap, "reload from its own %s: %d loaded, spare %d -> %d" % [g[0], inv.rounds_in(&"primary"), spare, inv.spare_rounds(StringName(g[0]))])


## Weapon detail pass (2026-10-20): a PKM's empty reload in first person, from the reload key:
## the charging handle goes back and home, the feed cover lifts and comes down on their beats,
## each beat is heard in turn, and the third-person model follows the same keys.
func _test_reload_beats() -> void:
	print("Reload beats: a PKM's empty reload")
	var inv := player.inventory
	var pi: PlayerInput = player.player_input
	inv.slots[&"primary"] = &""
	inv.take(&"pkm")
	inv.take(&"belt_762x54r", 2)
	player.active_slot = &"primary"
	while inv.consume_round(&"primary"):
		pass
	player._busy_until = 0.0
	player._server_busy_until = 0.0
	await _frames(5)
	var t := Sfx.heard_count()
	pi._try_reload()
	var length := player.reload_seconds(ItemDB.get_item(&"pkm"), true)
	check(player.is_reloading and player.reload_item == &"pkm" and player.reload_empty and is_equal_approx(player.reload_len, length),
		"the reload begins here at once: the PKM, empty, %.1f s" % length)
	var seen := {"bolt": 0.0, "cover": 0.0, "u": -1.0}
	var start := Soldier._now()
	while Soldier._now() - start < length + 0.4:
		var parts := pi.view_parts()
		seen.bolt = maxf(seen.bolt, float(parts.bolt))
		seen.cover = maxf(seen.cover, float(parts.cover))
		seen.u = maxf(seen.u, player.model.reload_u)
		await get_tree().process_frame
	var heard := Sfx.heard_after(t).filter(func(id: StringName) -> bool: return String(id).begins_with("reload_"))
	var want: Array = Reloads.beats(Reloads.BELT, true).map(func(b: Array) -> StringName: return b[1])
	check(seen.bolt > 0.08 and seen.cover > 1.0, "first person: the charging handle went back %.2f m, the cover up %.2f rad" % [seen.bolt, seen.cover])
	var after := pi.view_parts()
	check(is_zero_approx(float(after.bolt)) and absf(float(after.cover)) < 0.01, "and both are home after (%s)" % after)
	check(str(heard) == str(want), "each beat heard in turn (%s)" % [heard])
	check(seen.u > 0.9 and player.model.reload_u < 0.0 and inv.rounds_in(&"primary") == 100, "third person followed it to the end; 100 loaded")


## Wave 6b (2026-10-18): each enemy faction fields its own kit (factions.json "kits"); Black
## Ridge's and Vantage's come from their code tables unchanged; the one conventional army (the
## Eastern Concord Forces, call 4) from data, its kit by region: Russian inland, Iranian on the
## coast, Chinese in the Old Quarter (a zone_kits override), each in its own camo.
func _test_faction_kits() -> void:
	print("Faction kits (wave 6b)")
	check(Kits.kit_of("black_ridge") == Kits.INSURGENT and Kits.kit_of("vantage_group") == Kits.PMC and Kits.kit_of("eastern_concord", "none") == "concord_ru",
		"Black Ridge, Vantage and the Eastern Concord Forces each have their kit")
	check(Kits.kit_of("eastern_concord", "pinewood_ridge") == "concord_ru" and Kits.kit_of("eastern_concord", "harbour_yard") == "concord_ir"
		and Kits.kit_of("eastern_concord", "city_hot") == "concord_cn",
		"the Concord's kit goes by region (inland Russian, coast Iranian) and a zone override (Old Quarter Chinese)")
	check(Names.faction_nation("eastern_concord", "harbour_yard") == "IR" and Names.faction_nation("eastern_concord", "city_hot") == "CN"
		and Names.faction_nation("eastern_concord", "pinewood_ridge") == "RU" and Names.faction_nation("black_ridge", "harbour_yard") == "insurgent",
		"its men (HVTs, nemeses) are named from the kit's nation; Black Ridge stays insurgent")
	check(Kits.kit_of("federal_army", "none") == "concord_ru" and MissionRegistry.faction_name("federal_army") == "Eastern Concord Forces",
		"the old placeholder id still resolves to the renamed faction")
	var same := true
	for i in 9:
		same = same and Kits.loadout(Kits.INSURGENT, i) == CompoundLevel.hostile_loadout(i) and Kits.loadout(Kits.PMC, i, 3) == CompoundLevel.rival_pmc_loadout(i, 3)
	check(same and Kits.variant(Kits.INSURGENT) == "urban" and Kits.variant(Kits.PMC) == "black", "the militia's and the PMC's kits are what they were")
	var guns := {}
	var roles := {}
	for i in 8:
		var kit := Kits.loadout("concord_ru", i)
		check(kit.has("plate_carrier") and kit.has("plate_steel_l3") and kit.has("ifak"), "army kit %d: carrier, steel plate, IFAK" % i)
		for g: String in ["ak74", "rpk", "pkm", "svd"]:
			if kit.has(g):
				guns[g] = true
		if Kits.role("concord_ru", i) != "":
			roles[Kits.role("concord_ru", i)] = true
	check(guns.size() == 4 and roles.has("heavy_gunner") and roles.has("ammo_bearer") and roles.has("anti_tank") and Kits.variant("concord_ru") == "woodland",
		"the army: AK-74s, an RPK, a PKM with its ammo bearer, an RPG, an SVD, in woodland (%s)" % [guns.keys()])
	check(Kits.loadout("concord_ir", 0).has("akm") and Kits.variant("concord_ir") == "desert" and Kits.variant("concord_cn") == "urban",
		"the coast kit carries AKMs in desert camo; the Old Quarter's is urban")
	# Wave 6e: allied kits by employer, and the MG + AT weapons team as a named mix.
	check(Kits.kit_of("us_forces") == "allied_us" and Kits.loadout("allied_uk", 0).has("l85a2") and Kits.loadout("allied_ca", 0).has("c8"),
		"the allied employers dress their troops in their own kit (M4, L85A2, C8)")
	var team := range(Kits.mix("allied_us", "weapons_team").size()).map(func(i: int) -> Array: return Kits.loadout("allied_us", i, 1, "weapons_team"))
	check(team.size() == 4 and team.any(func(k: Array) -> bool: return k.has("m240b")) and team.filter(func(k: Array) -> bool: return k.has("at4")).size() == 2
		and Kits.role("allied_us", 0, "weapons_team") == "heavy_gunner",
		"a weapons team: an M240B gunner, his ammo bearer and two AT4s")
	var captured := range(CompoundLevel.HOSTILE_MIX.size()).any(func(i: int) -> bool: return CompoundLevel.hostile_loadout(i).has("m4a1"))
	check(captured, "the militia fields a captured M4 (a faction known to use AR-pattern rifles uses them)")
	check("eastern_concord" in MissionRegistry.enemies(), "the Eastern Concord Forces are a faction the squad can be hired against")
	check(["us_forces", "uk_forces", "ca_forces"].all(func(f: String) -> bool: return f in MissionRegistry.employers()),
		"the US, UK and Canada hire the squad")


func _test_hostile_kits() -> void:
	print("OPFOR carry AK-family guns")
	var seen := {}
	for i in CompoundLevel.HOSTILE_MIX.size():
		var kit := CompoundLevel.hostile_loadout(i)
		check(CompoundLevel.is_hostile_kit(kit), "kit %d is a hostile kit" % i)
		for id: String in OPFOR:
			if kit.has(id):
				seen[id] = true
	check(seen.size() == OPFOR.size(), "the mix has the AKM, AK-74, RPK, PKM and SVD (%s)" % ", ".join(seen.keys()))
	check(CompoundLevel.HOSTILE_LOADOUT.has("akm") and not CompoundLevel.HOSTILE_LOADOUT.has("mk18"), "the default OPFOR kit is the AKM, not an M4")
	for i in CompoundLevel.HOSTILE_MIX.size():
		var s := level.spawn_soldier({"name": "WpnHostile%d" % i, "faction": "hostile", "variant": "urban",
			"pos": Vector3(40 + i * 3, 0.1, 40), "loadout": CompoundLevel.hostile_loadout(i), "combat": 0.5, "discipline": 0.5, "guard": true})
		SquadAI.of(s).set_physics_process(false)
		var gun := String(s.inventory.slots[&"primary"])
		var ammo := StringName(ItemDB.get_item(StringName(gun)).stats.ammo)
		check((gun in OPFOR or gun == "m4a1") and s.inventory.count_of(ammo) >= 1 and s.inventory.rounds_in(&"primary") > 0,  # (one captured M4, 2026-10-18)
			"hostile %d carries %s with %d spare %s, loaded" % [i, gun, s.inventory.count_of(ammo), ammo])
		s.queue_free()


func _test_roles() -> void:
	print("Roles")
	var ids := Roles.kit(Roles.AUTORIFLEMAN).map(func(p: Array) -> String: return String(p[0]))
	check(ids.has("m249") and ids.has("box_556") and not ids.has("mag_556"), "the autorifleman's kit is an M249 and its boxes")
	var hg_ids := Roles.kit(&"heavy_gunner").map(func(p: Array) -> String: return String(p[0]))
	check(hg_ids.has("m240b") and hg_ids.has("belt_762x51"), "the heavy gunner's kit is an M240B and its belts")


## CompoundLevel.rival_pmc_loadout: the Vantage Group rival PMC's own mix (M4s, SCAR-Hs, an
## M240B and its ammo bearer), not Black Ridge's AKs, and the roles that go with it.
func _test_rival_pmc_kits() -> void:
	print("Vantage Group rival PMC carries modern gear")
	var seen := {}
	for i in CompoundLevel.PMC_MIX.size():
		var kit := CompoundLevel.rival_pmc_loadout(i)
		check(CompoundLevel.is_rival_pmc_kit(kit), "kit %d is a rival PMC kit" % i)
		for id: String in ["m4a1", "scar_h", "m240b"]:
			if kit.has(id):
				seen[id] = true
	check(seen.size() == 3, "the mix has the M4A1, SCAR-H and M240B (%s)" % ", ".join(seen.keys()))
	check(not CompoundLevel.PMC_LOADOUT.has("akm") and CompoundLevel.PMC_LOADOUT.has("m4a1"), "the default PMC kit is an M4, not an AKM")
	for i in CompoundLevel.PMC_MIX.size():
		var s := level.spawn_soldier({"name": "WpnPmc%d" % i, "faction": "hostile", "variant": "urban",
			"pos": Vector3(60 + i * 3, 0.1, 40), "loadout": CompoundLevel.rival_pmc_loadout(i), "combat": 0.5, "discipline": 0.5, "guard": true,
			"role": CompoundLevel.rival_pmc_role(i)})
		SquadAI.of(s).set_physics_process(false)
		var gun := String(s.inventory.slots[&"primary"])
		check(gun in ["m4a1", "scar_h", "m240b", "m110"], "rival PMC %d carries %s, not an AK-family gun" % [i, gun])
		if gun == "m240b":
			check(s.role == &"heavy_gunner", "the M240B carrier is cast as the heavy gunner")
		s.queue_free()


## Captain, 2026-10-17: "Vantage gets exo suits and heavy exo suits but only on higher diffs."
## Below PMC_LX3_DIFFICULTY nobody wears exo gear; from it, everyone but the exo pilot slot
## wears the LX-3; from PMC_HX1_DIFFICULTY that slot climbs straight into the HX-1 instead.
func _test_rival_pmc_exo_gating() -> void:
	print("Vantage's exo gear is difficulty-gated")
	for i in CompoundLevel.PMC_MIX.size():
		check(not CompoundLevel.rival_pmc_loadout(i, CompoundLevel.PMC_LX3_DIFFICULTY - 1).has("exo_frame_light"),
			"kit %d below the LX-3 cutoff carries no exo frame" % i)
	var lx3_kit := CompoundLevel.rival_pmc_loadout(0, CompoundLevel.PMC_LX3_DIFFICULTY)
	check(lx3_kit.has("exo_frame_light") and lx3_kit.has("helmet_lx3") and not lx3_kit.has("helmet"),
		"at the LX-3 cutoff, a normal slot wears the LX-3 frame and visor instead of a helmet (%s)" % [lx3_kit])
	var pilot_kit := CompoundLevel.rival_pmc_loadout(CompoundLevel.PMC_EXO_PILOT_SLOT, CompoundLevel.PMC_HX1_DIFFICULTY - 1)
	check(pilot_kit.has("exo_frame_light") and not pilot_kit.has("exo_mech_heavy"), "below the HX-1 cutoff the exo pilot slot wears the LX-3 like everyone else at this difficulty (%s)" % [pilot_kit])
	check(CompoundLevel.rival_pmc_exo_at(CompoundLevel.PMC_EXO_PILOT_SLOT, CompoundLevel.PMC_HX1_DIFFICULTY - 1) == "",
		"below the HX-1 cutoff nobody climbs into one")
	var s := level.spawn_soldier({"name": "WpnPmcHx1", "faction": "hostile", "variant": "urban", "pos": Vector3(90, 0.1, 40),
		"loadout": CompoundLevel.rival_pmc_loadout(CompoundLevel.PMC_EXO_PILOT_SLOT, CompoundLevel.PMC_HX1_DIFFICULTY), "combat": 0.5, "discipline": 0.5, "guard": true,
		"exo": CompoundLevel.rival_pmc_exo_at(CompoundLevel.PMC_EXO_PILOT_SLOT, CompoundLevel.PMC_HX1_DIFFICULTY)})
	SquadAI.of(s).set_physics_process(false)
	check(ExoMech.piloting(s.inventory) and s.inventory.slots[&"primary"] == &"wg50_walker" and s.inventory.count_of(&"belt_50bmg") > 0,
		"at the HX-1 cutoff the exo pilot climbs straight into the HX-1 with its Walker Gun (piloting %s, primary %s)" % [ExoMech.piloting(s.inventory), s.inventory.slots[&"primary"]])
	s.queue_free()


## Tracers and the shot sound start at the muzzle, not the eye (Captain, 2026-10-16: "bullets
## come from eyes not from guns"): ahead along the aim, to the firing hand's side, below the eye.
func _test_muzzle_point() -> void:
	var eye := Vector3(10, 2, 5)
	var north := Vector3(0, 0, -1)
	var m := Soldier.muzzle_point(eye, north, false, false)
	check((m - eye).dot(north) > 0.3, "the muzzle is ahead of the eye along the aim")
	check(m.x > eye.x and m.y < eye.y, "right-handed: the muzzle sits right of and below the eye")
	check(Soldier.muzzle_point(eye, north, false, true).x < eye.x, "left-handed: mirrored to the left")
	check(eye.distance_to(Soldier.muzzle_point(eye, north, true, false)) < eye.distance_to(m), "a sidearm's muzzle sits closer than a rifle's")
	check(Soldier.muzzle_point(eye, Vector3.DOWN, false, false).is_finite(), "straight down still gives a usable point")
