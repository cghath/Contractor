extends Node
## Headless checks of weapon pack 1 (stand-in OPFOR guns and more BLUFOR guns): every new weapon
## has its ammo, rounds, loose rounds, price and a voxel model; fires its round and reloads from
## its own magazine or belt; each round keeps to the armor and vehicle rules; the hostile
## faction's kits are AK-family guns; the autorifleman role carries the M249. The M320 (loaded by
## hand, an arcing HE grenade that arms past its distance and hurts a man near it, a dud inside
## it, smoke) and the pump shotgun (buckshot's pellets, a slug, a breaching round through planks
## and off a lock, shell-by-shell loading), each with its state saved and on a peer's copy.
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
## Items expansion (2026-10-20): every gun it added, fired and reloaded for real (_test_expansion_guns).
const EXPANSION_GUNS: Array[String] = ["glock19", "beretta_m9", "cz75", "makarov_pm", "tt33", "fn57", "glock18c", "usp45", "mp5", "mp5sd", "mp7", "uzi", "vityaz", "p90", "ump45", "rem870", "mossberg590", "m1014", "saiga12", "sig_mcx", "scar_l", "g36c", "aug_a3", "tavor_x95", "ak12", "akms", "ak105", "amd65", "vz58", "mk12", "sr25", "m14_ebr", "g3a3", "fal", "l1a1", "rpd", "negev", "mg3", "m60e4", "lee_enfield", "sks"]

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
	_test_gun_styles()
	_test_reloads()
	_test_muzzle_point()
	_test_m320_data()
	_test_shotgun_data()
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
	await _test_expansion_guns()
	await _test_reload_beats()
	await _test_arm_hits()
	await _test_third_person_reload()
	await _test_hostile_kits()
	_test_faction_kits()
	_test_terror_group_kits()
	await _test_rival_pmc_kits()
	await _test_rival_pmc_exo_gating()
	_test_roles()
	await _test_m320()
	await _test_shotgun()
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


## The items expansion's SMGs, shotguns and pistols have silhouettes of their own (follow-up,
## 2026-10-20: they borrowed the C8's, the AK's and the Mosin's, and every sidearm was one
## pistol): each builds as one solid piece under any sight and a suppressor, a magazine that comes
## out (none on a tube shotgun: shells go in through the top), its action as a moving part with a
## place for the hand, the grip behind the support hand and ahead of the butt, and its reload
## family.
func _test_gun_styles() -> void:
	print("Gun styles: SMGs, shotguns, pistols (2026-10-20)")
	var styles := {&"mp5": "smg", &"mp5sd": "smg_sd", &"ump45": "smg_box", &"mp7": "smg_pdw", &"uzi": "smg_grip",
		&"rem870": "shotgun", &"mossberg590": "shotgun_tac", &"m1014": "shotgun_auto"}
	for id: StringName in styles:
		var gun := ItemDB.get_item(id)
		var model := VoxelArt.model_for(gun)
		var shotgun := String(styles[id]).begins_with("shotgun")
		check(model.contains(":%s:" % styles[id]), "%s has its own silhouette (%s)" % [id, model])
		check(Reloads.family(gun) == (Reloads.BOLT if shotgun else Reloads.AR), "%s reloads as %s" % [id, Reloads.family(gun)])
		var parts := model.split(":")
		var solid := true
		for art: String in ["irons", "dot", "holo", "lpvo", "scope_long"]:
			for sup: String in ["", "sup"]:
				var pieces := _pieces("%s:%s:%s:%s:%s" % [parts[0], parts[1], art, parts[3], sup])
				if pieces.size() != 1:
					solid = false
					print("    %s %s %s: %s" % [id, art, sup, pieces])
		check(solid, "%s is one solid piece under every sight, with or without a suppressor" % id)
		var count := func(prefix: String) -> int: return (VoxelArt._spec(prefix + model).boxes as Array).size()
		var whole := (VoxelArt._spec(model).boxes as Array).size()
		var pts := VoxelArt.reload_points(model)
		var hands := VoxelArt.hand_points(model)
		check(VoxelArt.has_magazine(model) != shotgun and VoxelArt.moving_parts(model) == ["bolt"]
			and count.call(VoxelArt.FIXED) + count.call(VoxelArt.MAG) + count.call(VoxelArt.BOLT) == whole
			and pts.has("bolt") and pts.has("well") and (shotgun or pts.has("catch")),
			"%s: %s, its action moves, places for the hands (%s)" % [id, "shells through the top" if shotgun else "its magazine comes out", pts.keys()])
		var butt := VoxelArt.butt_point(model)
		check((hands.support as Vector3).z < (hands.grip as Vector3).z and (hands.grip as Vector3).z < butt.z,
			"%s: support hand ahead of the grip, the grip ahead of the butt" % id)
	for p: Array in [[&"m17", "pistol"], [&"glock19", "pistol:compact"], [&"m1911", "pistol:steel"], [&"makarov_pm", "pistol:steel_compact"]]:
		var model := VoxelArt.model_for(ItemDB.get_item(p[0]))
		var n := float(VoxelArt._spec(model).size.z)
		check(model == p[1] and n == (9.0 if model.ends_with("compact") else 10.0) and VoxelArt.has_magazine(model)
			and VoxelArt.moving_parts(model) == ["bolt"] and _pieces(model).size() == 1 and Reloads.family(ItemDB.get_item(p[0])) == Reloads.PISTOL,
			"%s draws as %s, %.0f cm: one piece, its magazine and slide parts of their own" % [p[0], model, n * 2.0])
	var under := func(model: String) -> float: return float(VoxelArt.hand_points(model).grip.z) - VoxelArt.sight_point(model).z
	check(is_equal_approx(under.call("pistol:compact"), under.call("pistol")),
		"a compact sits in the hand like the full-size: its grip the same way under its rear sight")


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
	var pressed := false
	for i in 3:
		player._server_fire.rpc_id(1, player.head.global_position, aim, &"primary")
		var shot_end := Time.get_ticks_msec() + int(wait * 1000.0)
		while Time.get_ticks_msec() < shot_end:
			pressed = pressed or player.model.hand_pose(0) == HandPose.PRESS
			await get_tree().process_frame
	check(pressed, "%s: each shot's tracer squeezes the drawn trigger finger" % id)
	check(inv.rounds_in(&"primary") == cap - 3, "3 shots: %d left (%d)" % [cap - 3, inv.rounds_in(&"primary")])
	var spare := inv.spare_rounds(StringName(g[0]))
	player._server_reload.rpc_id(1, &"primary")
	await _seconds(player.reload_seconds(gun) + 0.5)
	check(inv.rounds_in(&"primary") == cap, "reload from its own %s: %d loaded, spare %d -> %d" % [g[0], inv.rounds_in(&"primary"), spare, inv.spare_rounds(StringName(g[0]))])


## Items expansion (2026-10-20): every gun it added has its magazine, loose rounds, prices and a
## model, fires its own round (a shotgun's nine buckshot pellets for one shell) and reloads from
## its own magazine, in its own slot.
func _test_expansion_guns() -> void:
	print("Items expansion: every new gun fires and reloads from its own magazine")
	var inv := player.inventory
	var missing := PackedStringArray()
	for id: String in EXPANSION_GUNS:
		var gun := ItemDB.get_item(StringName(id))
		var mag_id := StringName(String(gun.stats.get("ammo", ""))) if gun else &""
		if Shotguns.is_tube(gun):  # (one 12-gauge system: a tube of loose shells and its speed loader)
			mag_id = StringName(String(gun.stats.get("loader", "")))
			if not ItemDB.has_item(StringName(String(gun.stats.ammo))) or Prices.price_of(StringName(id)) <= 0 or Prices.price_of(mag_id) <= 0 or VoxelArt.model_for(gun) == "":
				missing.append(id)
			continue
		var mag := ItemDB.get_item(mag_id) if mag_id != &"" else null
		if gun == null or mag == null or mag.magazine_rounds() <= 0 or HeliCall.loose_rounds_for(mag_id) == "" or Prices.price_of(StringName(id)) <= 0 				or Prices.price_of(mag_id) <= 0 or VoxelArt.model_for(gun) == "" or Ballistics.round_data(gun).is_empty():
			missing.append(id)
	check(missing.is_empty(), "%d new guns, each with its magazine, loose rounds, round data, prices and a model (missing: %s)" % [EXPANSION_GUNS.size(), ", ".join(missing)])
	var shotguns := EXPANSION_GUNS.filter(func(id: String) -> bool: return ItemDB.get_item(StringName(id)).tags.has("shotgun"))
	check(shotguns.size() == 4 and shotguns.all(func(id: String) -> bool: return Shotguns.is_shotgun(ItemDB.get_item(StringName(id))))
		and int(ItemDB.get_item(Shotguns.STANDARD).stats.pellets) == 9 and Ballistics.pellets(ItemDB.get_item(&"m4a1")) == 1,
		"the four shotguns fire 12 gauge shells (standard buck: 9 pellets), a rifle one bullet")
	for id: String in EXPANSION_GUNS:
		var gun := ItemDB.get_item(StringName(id))
		if Shotguns.is_tube(gun):
			continue  # (its tube and speed loader: _test_shotgun)
		var mag_id := StringName(String(gun.stats.ammo))
		var cap := ItemDB.get_item(mag_id).magazine_rounds()
		var slot := gun.slot
		inv.slots[slot] = &""
		inv.take(StringName(id))
		inv.take(mag_id, 1)
		player._server_busy_until = 0.0
		var aim := -player.global_basis.z
		var wait := 60.0 / float(gun.stats.rpm) + 0.1
		for i in 2:
			player._server_fire.rpc_id(1, player.head.global_position, aim, slot)
			await _seconds(wait)
		var fired := inv.rounds_in(slot)
		player._server_reload.rpc_id(1, slot)
		await _seconds(player.reload_seconds(gun, false) + 0.4)
		check(inv.slots[slot] == StringName(id) and fired == cap - 2 and inv.rounds_in(slot) == cap,
			"%s (%s): 2 shots from %d leave %d; reloads from its own %s to %d" % [id, slot, cap, fired, mag_id, inv.rounds_in(slot)])
	inv.slots[&"sidearm"] = &""


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
	var seen := {"bolt": 0.0, "cover": 0.0, "u": -1.0, "bolt3": -1.0, "cover3": -1.0, "view_hands": {}}
	var start := Soldier._now()
	while Soldier._now() - start < length + 0.4:
		var vh := pi.view_hand_poses()
		if vh.size() == 2:
			seen.view_hands[vh[1]] = true
		var parts := pi.view_parts()
		seen.bolt = maxf(seen.bolt, float(parts.bolt))
		seen.cover = maxf(seen.cover, float(parts.cover))
		seen.u = maxf(seen.u, player.model.reload_u)
		var shown := player.model.reload_parts_shown()  # feel round 2: third person too
		seen.bolt3 = maxf(seen.bolt3, float(shown.bolt))
		seen.cover3 = maxf(seen.cover3, float(shown.cover))
		await get_tree().process_frame
	var heard := Sfx.heard_after(t).filter(func(id: StringName) -> bool: return String(id).begins_with("reload_"))
	var want: Array = Reloads.beats(Reloads.BELT, true).map(func(b: Array) -> StringName: return b[1])
	check(seen.bolt > 0.08 and seen.cover > 1.0, "first person: the charging handle went back %.2f m, the cover up %.2f rad" % [seen.bolt, seen.cover])
	check(seen.view_hands.has(HandPose.MAG) and seen.view_hands.has(HandPose.PINCH) and seen.view_hands.has(HandPose.OPEN),
		"first person: the support hand takes the box (MAG), pinches the handle, opens on the cover (%s)" % [seen.view_hands.keys()])
	var after := pi.view_parts()
	check(is_zero_approx(float(after.bolt)) and absf(float(after.cover)) < 0.01, "and both are home after (%s)" % after)
	check(str(heard) == str(want), "each beat heard in turn (%s)" % [heard])
	check(seen.u > 0.9 and player.model.reload_u < 0.0 and inv.rounds_in(&"primary") == 100, "third person followed it to the end; 100 loaded")
	check(seen.bolt3 > 0.08 and seen.cover3 > 1.0 and float(player.model.reload_parts_shown().bolt) < 0.0,
		"third person, near: the charging handle went back %.2f m, the cover up %.2f rad, and the weapon's whole again after" % [seen.bolt3, seen.cover3])


## Feel round 2 (2026-10-20): an AI's reload drawn in third person as first person plays it.
## The host's _reload_began gives every peer the weapon, the empty flag and the length; from
## them the model follows the keys: the weapon's own pose, the empty magazine falling free and
## the new one carried up and in, and the carrier locked back until the catch is slapped.
## Arms and hands take hits (Captain, 2026-10-21: "fingers and arms cant be hit it seems. i tried
## from both left and right sides"): rounds from the left, the right and the front at an aiming
## soldier's upper arms, forearms and hands. From the arm's own side the round must wound that
## part (a hand is its forearm's part); from the front it must wound an arm (the support arm can
## be in front of the firing hand); from the far side the body may be in the way (the chest in
## front of the far upper arm), but it must wound him, not pass through. The arms' hitboxes are on
## the arms as drawn, and the round takes the part it meets first (Ballistics.nearest_part).
func _test_arm_hits() -> void:
	print("Arm hits: an aiming soldier, from the left, the right and the front")
	var s := level.spawn_soldier({"name": "ArmTarget", "faction": "hostile", "variant": "multicam",
		"pos": player.global_position + Vector3(6, 0, 6), "loadout": ["plate_carrier", "m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
	s.active_slot = &"primary"
	s.want_aim = true
	await _seconds(1.0)
	check(s.is_aiming and s.model._held != null, "the target has his rifle up, aiming")
	var gun := ItemDB.get_item(&"m4a1")
	var arms := [Vitals.UPPER_ARM_L, Vitals.UPPER_ARM_R, Vitals.FOREARM_L, Vitals.FOREARM_R]
	var report: Array[String] = []
	var bad := 0
	for spot: Array in [["upper_arm_r", Vitals.UPPER_ARM_R], ["upper_arm_l", Vitals.UPPER_ARM_L], ["forearm_r", Vitals.FOREARM_R],
			["forearm_l", Vitals.FOREARM_L], ["hand_r", Vitals.FOREARM_R], ["hand_l", Vitals.FOREARM_L]]:
		for from: String in ["left", "right", "front"]:
			s.vitals.server_reset_health()
			if s.inventory.slots.get(&"primary", &"") == &"":  # a forearm hit knocked it out (G-23): back in his hands
				s.inventory.put_on(&"primary", &"m4a1")
				s.active_slot = &"primary"
				await _seconds(0.8)
			await _frames(2)
			var point: Vector3
			match spot[0]:
				"hand_r": point = s.model.hand_position(true)
				"hand_l": point = s.model.hand_position(false)
				_:
					var node := s.model.part_node(spot[1])
					var down := 0.16 if String(spot[0]).begins_with("upper") else 0.12
					point = node.to_global(Vector3(0, -down, 0))
			var across := s.global_basis.x.normalized()
			var ahead := -s.global_basis.z.normalized()
			var dir: Vector3 = {"left": across, "right": -across, "front": -ahead}[from]
			var origin := point - dir * 3.0
			Ballistics._trace(player, origin, dir, gun)
			var parts := s.vitals.wound_list().map(func(w: Dictionary) -> StringName: return w.part)
			var own_side := from != "front" and (from == "right") == String(spot[0]).ends_with("_r")
			var ok: bool
			if own_side:
				ok = parts.has(spot[1])
			elif from == "front":
				ok = parts.any(func(p: StringName) -> bool: return p in arms)
			else:
				ok = not parts.is_empty()
			if not ok:
				bad += 1
			report.append("%s from the %s: %s" % [spot[0], from, parts])
	check(bad == 0, "from its own side every arm and hand took the round, from the front an arm, from the far side the body: %s" % ("; ".join(report) if bad > 0 else "18 of 18"))
	if bad > 0:
		for line in report:
			print("    ", line)
	s.vitals.server_reset_health()
	s.queue_free()
	await _frames(2)


func _test_third_person_reload() -> void:
	print("Third person: an AI's empty M4 reload")
	var s := level.spawn_soldier({"name": "WpnReloader", "faction": "hostile", "variant": "urban",
		"pos": player.global_position + Vector3(3, 0, 0), "loadout": ["plate_carrier", "m4a1", "mag_556", "mag_556"], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(s).set_physics_process(false)
	await _frames(20)
	s.active_slot = &"primary"
	await _frames(5)
	while s.inventory.consume_round(&"primary"):
		pass
	var gun := ItemDB.get_item(&"m4a1")
	var length := s.reload_seconds(gun, true)
	s.is_reloading = true
	s._busy_until = Soldier._now() + length
	s._server_reload.rpc_id(1, &"primary")
	await _frames(1)
	check(s.reload_item == &"m4a1" and s.reload_empty and is_equal_approx(s.reload_len, length) and str(s.model.reload_keys) == str(Reloads.keys(Reloads.AR, true))
		and s.model.reload_parts.has("bolt"),
		"the host's word reached the body: the M4, empty, %.1f s, the AR's empty keys and its bolt track" % length)
	var seen := {"u": -1.0, "pose": 0.0, "mags": 0, "dropped": 0.0, "carried": false, "bolt": -1.0, "seated": false, "hands": {}}
	var start := Soldier._now()
	while Soldier._now() - start < length + 0.4:
		var m := s.model
		seen.hands[m.hand_pose(1)] = true
		seen.u = maxf(seen.u, m.reload_u)
		var pose := m.reload_pose()
		if pose.size() == 2:
			seen.pose = maxf(seen.pose, absf((pose[1] as Vector3).z))
		var held: Node3D = m._held
		var mags: Array = held.get_children().filter(func(c: Node) -> bool: return String(c.name).contains("ReloadMagazine") and not c.is_queued_for_deletion()) if is_instance_valid(held) else []
		seen.mags = maxi(seen.mags, mags.size())
		if mags.size() == 2:
			seen.dropped = minf(seen.dropped, (mags[0] as Node3D).position.y)
			seen.carried = seen.carried or ((mags[1] as Node3D).visible and not (mags[1] as Node3D).transform.is_equal_approx(Transform3D.IDENTITY))
			seen.seated = seen.seated or (m.reload_u > 0.7 and (mags[1] as Node3D).visible and (mags[1] as Node3D).transform.is_equal_approx(Transform3D.IDENTITY))
		seen.bolt = maxf(seen.bolt, float(m.reload_parts_shown().bolt))
		await get_tree().process_frame
	await _frames(2)
	var held_after: Node3D = s.model._held
	var whole := is_instance_valid(held_after) and held_after.get_children().all(func(c: Node) -> bool: return not String(c.name).contains("Reload") or c.is_queued_for_deletion())
	check(seen.u > 0.9 and seen.pose > 0.5, "it played to the end (%.2f), the rifle turned on the keys (rolled %.2f rad)" % [seen.u, seen.pose])
	check(seen.mags == 2 and seen.dropped < -0.2 and seen.carried and seen.seated,
		"the magazine came out of the gun: the empty fell free (%.2f m), the new one carried up and seated (%s)" % [seen.dropped, seen])
	check(seen.bolt > 0.04, "the carrier locked back %.2f m, then home" % seen.bolt)
	check(seen.hands.has(HandPose.MAG) and seen.hands.has(HandPose.POINT), "the support hand grabs the magazine (MAG) and slaps the catch (%s)" % [seen.hands.keys()])
	check(String(s.model.part_node(Vitals.FOREARM_R).get_meta(&"voxel_model", "")).ends_with("b") and VoxelArt.hands_bare("urban") and not VoxelArt.hands_bare("multicam"),
		"militia go bare-handed, contractors gloved (%s)" % s.model.part_node(Vitals.FOREARM_R).get_meta(&"voxel_model", ""))
	check(whole and s.model.reload_u < 0.0 and s.inventory.rounds_in(&"primary") > 0, "after: the rifle whole again and loaded (%d)" % s.inventory.rounds_in(&"primary"))
	s.queue_free()


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


## Terror groups (Captain, 2026-10-20; docs/terror_groups.md): the Ashen Banner, the Valley Shura,
## the Saltline Syndicate, the Kestrel Cartel and the Highland Free Front each field their own kit:
## mixed plain clothes (the Banner's foreign fighters and the Front's men in their own camo), their
## own guns, their marks (militia orange or hostile red), their doctrine; bombers only from the
## Banner and the Shura.
func _test_terror_group_kits() -> void:
	print("Terror group kits")
	var groups := {"ashen_banner": "hostile", "valley_shura": "hostile", "saltline": "militia", "kestrel": "militia", "highland_front": "militia"}
	var i := 0
	for g: String in groups:
		var kit_id := Kits.kit_of(g, "none")
		check(Kits.is_data(kit_id) and MissionRegistry.faction_side(g) == groups[g] and g in MissionRegistry.enemies(),
			"%s fields its own kit (%s), drawn %s" % [g, kit_id, groups[g]])
		var looks := {}
		for n in 6:
			looks[Kits.variant(kit_id, n)] = true
		check(looks.size() >= 3, "%s's men don't all look alike (%d looks in 6)" % [g, looks.size()])
		var doctrine := Kits.doctrine(g)
		check(Doctrine.has(doctrine), "%s fights by its own doctrine (%s)" % [g, doctrine])
		for n in 2:
			var spawn := {"name": "WpnTerror%d_%d" % [i, n], "faction": "hostile", "pos": Vector3(60 + i * 4, 0.1, 60 + n * 3),
				"loadout": Kits.loadout(kit_id, n), "combat": 0.5, "discipline": 0.5, "guard": true, "role": Kits.role(kit_id, n)}
			spawn.merge(Kits.dress(g, kit_id, n), true)
			var s := level.spawn_soldier(spawn)
			SquadAI.of(s).set_physics_process(false)
			var gun := String(s.inventory.slots[&"primary"])
			var ammo := StringName(ItemDB.get_item(StringName(gun)).stats.ammo)
			var marks: Array = s.get_node(^"Model").get(&"iff")
			check(gun in Kits.loadout(kit_id, n) and s.inventory.rounds_in(&"primary") > 0 and s.inventory.count_of(ammo) >= 1
				and s.variant == Kits.variant(kit_id, n) and String(s.get_meta(&"faction_id", "")) == g
				and marks == GearRig.IFF[StringName(groups[g])] and SquadAI.of(s)._doctrine_id() == doctrine,
				"%s man %d spawns with his %s (loaded, %d spare), his clothes (%s), %s marks and the %s doctrine" % [g, n, gun, s.inventory.count_of(ammo), s.variant, groups[g], doctrine])
			s.queue_free()
		i += 1
	check(Kits.sends_bombers("ashen_banner") and Kits.sends_bombers("valley_shura") and not Kits.sends_bombers("black_ridge")
		and not Kits.sends_bombers("saltline"), "suicide bombers: the Banner and the Shura only (Captain), not Black Ridge any more")
	var uniformed := range(6).filter(func(n: int) -> bool: return Kits.is_uniform("banner", n))
	check(not uniformed.is_empty() and uniformed.size() < 6 and Kits.variant("banner", uniformed[0]) == "banner" and Kits.loadout("banner", uniformed[0]).has("helmet_pasgt"),
		"the Banner's foreign fighters wear its camo and a helmet; its locals plain clothes")


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


# --- The M320 and the shotgun (Captain's list for cghath, 2026-10-20) ------------------------

## The M320, its 40 mm grenades and their warheads in the data: what it fits, the rounds it
## takes, the arming distance and the arc.
func _test_m320_data() -> void:
	print("M320 and 40 mm in the data")
	var gl := ItemDB.get_item(&"m320")
	var he := ItemDB.get_item(&"round_40mm_he")
	var smoke := ItemDB.get_item(&"round_40mm_smoke")
	check(gl != null and GunAttachments.mount_of(gl) == GunAttachments.UNDERBARREL and bool(gl.stats.get("launcher", false)), "the M320 is an underbarrel launcher")
	check(GunAttachments.fits(ItemDB.get_item(&"m4a1"), gl) and GunAttachments.fits(ItemDB.get_item(&"hk416"), gl), "it goes on the M4 and the HK416")
	check(not GunAttachments.fits(ItemDB.get_item(&"m249"), gl) and not GunAttachments.fits(ItemDB.get_item(&"mosin9130"), gl)
		and not GunAttachments.fits(ItemDB.get_item(&"akm"), gl) and not GunAttachments.fits(ItemDB.get_item(&"m17"), gl),
		"not on a machine gun, a sniper rifle, a rifle with no rail or a pistol")
	check(Launchers.round_items(gl) == [&"round_40mm_he", &"round_40mm_smoke"] and Launchers.round_item_for(&"m406") == &"round_40mm_he",
		"it takes 40 mm HE and smoke (%s)" % [Launchers.round_items(gl)])
	var d := Warheads.data(&"m406")
	check(float(d.arming_m) >= 14.0 and float(d.speed_mps) < 100.0 and not d.has("motor") and Warheads.kind_of(&"m406") == Vehicle.HE,
		"M406 HE: arms at %.0f m, leaves at %.0f m/s with no motor" % [float(d.arming_m), float(d.speed_mps)])
	check(String(Warheads.data(&"m714").get("kind", "")) == "smoke" and String(smoke.stats.get("smoke_colour", "")) == "white", "M714 is white smoke")
	var drop := float(LauncherProjectile.drop_at(&"m406", 100.0).drop)
	check(drop > 5.0, "a 40 mm grenade arcs: %.1f m below the line at 100 m (a rocket hardly drops)" % drop)
	for id: StringName in [&"m320", &"round_40mm_he", &"round_40mm_smoke"]:
		check(_priced(id), "%s is priced ($%d) and for sale" % [id, Prices.price_of(id)])
	check(he.type == "ammo" and not he.tags.has("launcher_round"), "40 mm grenades aren't shoulder-launcher rounds")


## One 12-gauge system (Captain, 2026-10-21): the three shells, every shotgun on them, breaching
## rounds only in the M1014 and the Skeleton Key, the 870's choke, the M320 and the Key on every
## railed assault rifle, carbine and battle rifle (the AK-12 too) and nothing else; the pattern.
func _test_shotgun_data() -> void:
	print("12 gauge in the data: three shells, every shotgun, the Skeleton Key, the choke")
	var std := ItemDB.get_item(Shotguns.STANDARD)
	var hi := ItemDB.get_item(Shotguns.HI_BRASS)
	var br := ItemDB.get_item(Shotguns.BREACHING)
	check(std != null and hi != null and br != null and bool(br.stats.get("breach", false)) and std.name.contains("Standard") and hi.name.contains("Hi-Brass"),
		"three shells: %s, %s, %s" % [std.name if std else "-", hi.name if hi else "-", br.name if br else "-"])
	check(not ItemDB._items.has(&"shells_12g_slug") and not ItemDB._items.has(&"rounds_12g") and not ItemDB._items.has(&"m870")
		and ItemDB.get_item(&"rounds_12g") == std and ItemDB.get_item(&"shells_12g_slug") == std and ItemDB.get_item(&"m870") == ItemDB.get_item(&"rem870"),
		"slugs and the loose rounds_12g are Standard now, cghath's M870 the Remington 870 (an old save's ids still resolve)")
	check(int(hi.stats.pellets) > int(std.stats.pellets) and float(hi.stats.pellet_spread_deg) > float(std.stats.pellet_spread_deg)
		and float(hi.stats.get("recoil_mult", 1.0)) > 1.0,
		"hi-brass: more pellets (%d > %d), a slightly wider pattern, a harder kick" % [int(hi.stats.pellets), int(std.stats.pellets)])
	var guns: Array[StringName] = [&"rem870", &"mossberg590", &"m1014", &"saiga12"]
	for id: StringName in ItemDB.all_ids():
		var it := ItemDB.get_item(id)
		if it.type == "weapon" and it.tags.has("12ga") and not id in guns:
			guns.append(id)
	for id in guns:
		var g := ItemDB.get_item(id)
		var full := g.default_state()
		var list := Shotguns.list_of(g, full)
		check(Shotguns.is_shotgun(g) and Shotguns.takes(g, Shotguns.STANDARD) and Shotguns.takes(g, Shotguns.HI_BRASS)
			and Shotguns.takes(g, Shotguns.BREACHING) == (id == &"m1014") and list.size() == int(full.rounds) and list.size() > 0
			and list.all(func(x: Variant) -> bool: return StringName(String(x)) == Shotguns.STANDARD),
			"%s fires through one path, takes standard and hi-brass%s, comes full of %d standard" % [g.name, " and breaching" if id == &"m1014" else ", refuses breaching", list.size()])
	check(Shotguns.why_not(ItemDB.get_item(&"rem870"), Shotguns.BREACHING).contains("M1014"), "and says why: %s" % Shotguns.why_not(ItemDB.get_item(&"rem870"), Shotguns.BREACHING))
	var key := ItemDB.get_item(&"skeleton_key")
	check(key != null and Shotguns.is_key(key) and GunAttachments.mount_of(key) == GunAttachments.UNDERBARREL and Shotguns.capacity(key) == 3
		and Shotguns.shells_of(key) == [Shotguns.BREACHING, Shotguns.STANDARD, Shotguns.HI_BRASS] and Shotguns.key_list(key, {}).size() == 3,
		"the Skeleton Key: an underbarrel 12 gauge, a three-shell tube full of breaching rounds, standard and hi-brass too")
	for h: StringName in [&"loader_12g_6", &"loader_12g_7"]:
		check(Shotguns.is_holder(ItemDB.get_item(h)) and [Shotguns.STANDARD, Shotguns.HI_BRASS, Shotguns.BREACHING].all(func(x: StringName) -> bool: return Shotguns.takes(ItemDB.get_item(h), x)),
			"%s holds any of the three" % h)
	check(not Shotguns.takes(ItemDB.get_item(&"mag_saiga12"), Shotguns.BREACHING), "a Saiga magazine takes no breaching rounds")
	# What the shells fire: a pellet each (flagged: gunfire gore scores pellets their own way), the
	# hi-brass pellet faster and harder.
	var gun := ItemDB.get_item(&"rem870")
	var p_std := Shotguns.shot_item(gun, Shotguns.STANDARD)
	var p_hi := Shotguns.shot_item(gun, Shotguns.HI_BRASS)
	var p_br := Shotguns.shot_item(gun, Shotguns.BREACHING)
	check(String(Ballistics.round_data(p_std).get("id", "")) == "12g_00_pellet" and String(Ballistics.round_data(p_hi).get("id", "")) == "12g_00_mag_pellet"
		and String(Ballistics.round_data(p_br).get("id", "")) == "12g_breach" and bool(Ballistics.round_data(p_std).get("pellet", false))
		and bool(Ballistics.round_data(p_hi).get("pellet", false)), "each shell fires its own round, its pellets flagged as pellets")
	var e_std := Ballistics.energy_at(p_std, 10.0)
	var e_hi := Ballistics.energy_at(p_hi, 10.0)
	check(e_hi > e_std * 1.15 and BodyDeform.hit_points(Vitals.PISTOL, e_hi, true) > BodyDeform.hit_points(Vitals.PISTOL, e_std, true),
		"a hi-brass pellet hits harder (%.0f J against %.0f J at 10 m), and gunfire gore scores it higher" % [e_hi, e_std])
	var rng := RandomNumberGenerator.new()
	rng.seed = 870
	var aim := Vector3(0.3, -0.1, -1).normalized()
	var spread := float(std.stats.pellet_spread_deg)
	var dirs := Shotguns.pellet_dirs(aim, 9, spread, rng)
	var widest := 0.0
	var inside := true
	var distinct := {}
	for d in dirs:
		var a := rad_to_deg(d.angle_to(aim))
		widest = maxf(widest, a)
		inside = inside and a <= spread + 0.001
		distinct[str(d.snapped(Vector3.ONE * 0.0001))] = true
	check(dirs.size() == 9 and inside and widest > spread * 0.4 and distinct.size() == 9,
		"buckshot: nine pellets, each its own line inside the %.1f degree cone (widest %.2f)" % [spread, widest])
	# The choke: the 870's upgrade, and only the 870's.
	var choke := ItemDB.get_item(&"choke_870")
	check(choke != null and GunAttachments.mount_of(choke) == GunAttachments.CHOKE and GunAttachments.fits(gun, choke)
		and not GunAttachments.fits(ItemDB.get_item(&"mossberg590"), choke) and not GunAttachments.fits(ItemDB.get_item(&"m1014"), choke)
		and not GunAttachments.fits(ItemDB.get_item(&"m4a1"), choke), "the choke fits the Remington 870 and nothing else")
	var choked := GunAttachments.with_mounted(gun.default_state(), GunAttachments.CHOKE, &"choke_870")
	check(Shotguns.spread_mult(gun, choked) < 0.6 and Shotguns.spread_mult(gun, gun.default_state()) == 1.0, "a choke narrows the pattern to %.2f of its width" % Shotguns.spread_mult(gun, choked))
	# The M320 and the Key: every railed assault rifle, carbine and battle rifle (the AK-12 too, no
	# GP-25 yet), never an SMG, shotgun, machine gun, sniper rifle or DMR.
	var m320 := ItemDB.get_item(&"m320")
	var yes: Array[StringName] = [&"m4a1", &"mk18", &"m16a4", &"c7", &"c8", &"m27", &"hk416", &"l85a2", &"sig_mcx", &"scar_l", &"scar_h", &"g36c", &"aug_a3", &"tavor_x95", &"g3a3", &"fal", &"ak12"]
	var no: Array[StringName] = [&"mp5", &"p90", &"ump45", &"rem870", &"mossberg590", &"m1014", &"m249", &"m240b", &"negev", &"svd", &"svds", &"m110", &"mk12", &"sr25", &"m14_ebr", &"mosin9130", &"springfield_hs", &"akm", &"ak74"]
	var wrong: Array = []
	for id in yes:
		if not GunAttachments.fits(ItemDB.get_item(id), m320) or not GunAttachments.fits(ItemDB.get_item(id), key):
			wrong.append("%s (should)" % id)
	for id in no:
		if GunAttachments.fits(ItemDB.get_item(id), m320) or GunAttachments.fits(ItemDB.get_item(id), key):
			wrong.append("%s (shouldn't)" % id)
	check(wrong.is_empty(), "the M320 and the Skeleton Key go on every railed assault rifle, carbine and battle rifle, the AK-12 too, and on nothing else (%s)" % [wrong])
	for id: StringName in [&"skeleton_key", &"choke_870", Shotguns.STANDARD, Shotguns.HI_BRASS, Shotguns.BREACHING, &"rem870"]:
		check(_priced(id), "%s is priced ($%d) and for sale" % [id, Prices.price_of(id)])
	var tables := FileAccess.get_file_as_string("res://data/loot_tables.json")
	check(tables.contains("\"choke_870\"") and tables.contains("\"skeleton_key\""), "the choke and the Skeleton Key turn up as loot")
	var model := VoxelArt.model_for(gun)
	check(model.contains(":shotgun") and VoxelArt.mesh(model, "multicam") != null and not VoxelArt.hand_points(model).is_empty(),
		"carried, the 870 builds a model with hand points (%s)" % model)
	check(ItemArt.ground_size(key).z > 0.3 and ItemArt.ground_size(m320).z > 0.2, "the Key's ground model and the M320's are their own")


## The M320 on the host player's M4: loaded by hand, an arcing HE grenade that bursts past its
## arming distance and hurts a man near where it lands, a dud inside it, a smoke grenade's cloud.
func _test_m320() -> void:
	print("M320: loads, arcs, arms, bursts, smokes")
	var inv := player.inventory
	inv.slots[&"primary"] = &""
	inv.take(&"m4a1")
	inv.take(&"m320")
	check(GunAttachments.mount_carried(inv, &"m320") and inv.count_of(&"m320") == 0, "the M320 goes on the M4")
	inv.take(&"round_40mm_he", 3)
	inv.take(&"round_40mm_smoke", 1)
	player.active_slot = &"primary"
	player.underbarrel_up = true
	player._server_busy_until = 0.0
	check(Underbarrel.on_gun(player) != null and Underbarrel.loaded_of(player) == &"", "it's on the gun in hand, empty")
	check(Underbarrel.server_fire(player, player.camera.global_position, Vector3.FORWARD) != "", "it won't fire empty")
	var secs := Underbarrel.server_reload(player, &"round_40mm_he")
	check(secs > 2.0, "loading a grenade by hand takes %.1f s" % secs)
	await _seconds(secs + 0.3)
	check(Underbarrel.loaded_of(player) == &"m406" and inv.count_of(&"round_40mm_he") == 2, "an HE grenade in it, two left in the kit")
	check(GunAttachments.label(ItemDB.get_item(&"m4a1"), inv.state_of(&"primary")).contains("M406"), "the gun's readout names it: %s" % GunAttachments.label(ItemDB.get_item(&"m4a1"), inv.state_of(&"primary")))
	var launchers := Launchers.of(player)
	# Level, out over the open ground south of the compound: it falls in an arc and lands about
	# 40 m out, well past its arming distance, by a man standing there.
	player.global_position = Vector3(0, 0.1, 30)
	await _frames(2)
	var eye := player.camera.global_position
	var fall := sqrt(2.0 * maxf(eye.y - 0.1, 0.5) / LauncherProjectile.GRAVITY)
	var lands := eye + Vector3(0, 0, 1) * float(Warheads.data(&"m406").speed_mps) * fall
	var near := _dummy(Vector3(1.5, 0.0, lands.z))
	await _frames(2)
	var wounds_before := near.vitals.wound_list().size()
	check(Underbarrel.server_fire(player, eye, Vector3(0, 0, 1)) == "", "it fires")
	var id := launchers.last_id
	check(Underbarrel.loaded_of(player) == &"", "and is empty after")
	await _wait_result(launchers, id, 6.0)
	var r: Dictionary = launchers.results.get(id, {})
	var at: Vector3 = r.get("position", Vector3.ZERO)
	check(String(r.get("how", "")) == "burst" and float(r.get("flown", 0.0)) > 20.0 and at.y < eye.y - 1.0 and float(r.get("max_height", 1.0)) < 0.3,
		"the grenade arced down and burst %.0f m out at (%.1f, %.1f, %.1f), predicted z %.0f" % [float(r.get("flown", 0.0)), at.x, at.y, at.z, lands.z])
	var hurt: Array = (r.get("burst", {}) as Dictionary).get("hurt", [])
	check(near in hurt or near.vitals.wound_list().size() > wounds_before, "the man %.1f m from it is hurt (%s)" % [at.distance_to(near.global_position), near.vitals.condition_text()])
	near.queue_free()
	# Inside the arming distance: a dud.
	player._server_busy_until = 0.0
	Underbarrel.server_reload(player, &"round_40mm_he")
	await _seconds(secs + 0.3)
	player._server_busy_until = 0.0
	var down := Vector3(0, -1, 1).normalized()
	check(Underbarrel.server_fire(player, eye, down) == "", "fired into the ground a few metres off")
	id = launchers.last_id
	await _wait_result(launchers, id, 3.0)
	r = launchers.results.get(id, {})
	check(String(r.get("how", "")) == "dud" and float(r.get("flown", 99.0)) < float(Warheads.data(&"m406").arming_m),
		"inside its arming distance it doesn't go off (%s after %.1f m)" % [r.get("how", "?"), float(r.get("flown", 0.0))])
	# Smoke.
	player._server_busy_until = 0.0
	Underbarrel.server_reload(player, &"round_40mm_smoke")
	await _seconds(secs + 0.3)
	check(Underbarrel.loaded_of(player) == &"m714", "a smoke grenade in it")
	player._server_busy_until = 0.0
	var clouds := SmokeCloud.active.size()
	check(Underbarrel.server_fire(player, eye, Vector3(0, 0, 1)) == "", "it fires the smoke grenade")
	id = launchers.last_id
	await _wait_result(launchers, id, 6.0)
	await _frames(3)
	r = launchers.results.get(id, {})
	check(String(r.get("how", "")) == "smoke" and SmokeCloud.active.size() == clouds + 1 and (r.get("burst", {}) as Dictionary).is_empty(),
		"it lands in a white cloud, no burst (%s; clouds %d -> %d)" % [r.get("how", "?"), clouds, SmokeCloud.active.size()])
	# The loaded grenade is part of the gun's state: saved and loaded (JSON), and a peer's copy.
	inv.set_slot_state(&"primary", Underbarrel.with_round(ItemDB.get_item(&"m4a1"), inv.state_of(&"primary"), &"m406"))
	var saved: Variant = JSON.parse_string(JSON.stringify(Roster.json_safe(inv.net_state)))
	var loaded := Inventory.new()
	add_child(loaded)
	loaded.net_state = GameState.from_json(saved)
	var copy := Inventory.new()
	add_child(copy)
	copy.net_state = inv.net_state
	await _frames(1)
	check(Underbarrel.loaded(loaded.state_of(&"primary")) == &"m406" and Underbarrel.loaded(copy.state_of(&"primary")) == &"m406",
		"saved and loaded, and on a peer's copy, the M320 still has its grenade in")
	loaded.queue_free()
	copy.queue_free()
	player.underbarrel_up = false
	player.global_position = Vector3(0, 0.1, 24)


## One 12-gauge system on the host player (Captain, 2026-10-21): the 870's standard and hi-brass
## patterns on the shed's plank wall and its choke, an 870 that won't load breaching rounds and
## says why, the M1014's breaching round through the planks and off a box's lock, shell by shell
## and a speed loader in one push (the breaching shell left in it), loose shells into loaders and
## not into a Saiga magazine, the Saiga's shells through a magazine swap, the Skeleton Key under an
## M4 breaching the planks, the breacher's kit, and the AI counting shells as spare ammo (F-131).
func _test_shotgun() -> void:
	print("12 gauge: standard, hi-brass, choke, breaching, loaders, the Saiga, the Skeleton Key")
	var inv := player.inventory
	var gun := ItemDB.get_item(&"rem870")
	inv.slots[&"primary"] = &""
	inv.take(&"rem870")
	player.active_slot = &"primary"
	check(inv.slots[&"primary"] == &"rem870" and inv.rounds_in(&"primary") == 6 and Shotguns.next_shell(inv.state_of(&"primary")) == Shotguns.STANDARD,
		"the 870 in hand, six standard shells in the tube")
	# Standard buck at the shed's west plank wall (x = 16), 6 m off.
	player.global_position = Vector3(10, 0.1, -8.1)
	await _frames(2)
	var eye := player.camera.global_position
	var shoot := func(dir: Vector3) -> void:
		player._server_busy_until = 0.0
		player._server_next_shot = 0.0
		player._server_fire.rpc_id(1, player.camera.global_position, dir, &"primary")
	var widest := func() -> float:
		var w := 0.0
		for d: Vector3 in Shotguns.last_dirs:
			w = maxf(w, rad_to_deg(d.angle_to(Vector3(1, 0, 0))))
		return w
	shoot.call(Vector3(1, 0, 0))
	await _frames(2)
	var on_wall := Shotguns.last_results.filter(func(res: Dictionary) -> bool:
		return String(res.get("result", "")) == "world" and (res.position as Vector3).x > 15.8)
	var open_w: float = widest.call()
	check(Shotguns.last_results.size() == 9 and on_wall.size() >= 7 and inv.rounds_in(&"primary") == 5,
		"standard buck: 9 pellets, %d on the walls 6 m off, one shell gone" % on_wall.size())
	# Hi-brass: twelve pellets, a little wider.
	inv.set_slot_state(&"primary", {"rounds": 1, "tube": [String(Shotguns.HI_BRASS)]})
	check(Shotguns.recoil_of(gun, inv.state_of(&"primary")) > 1.2, "the hi-brass shell up next kicks harder (x%.2f)" % Shotguns.recoil_of(gun, inv.state_of(&"primary")))
	shoot.call(Vector3(1, 0, 0))
	await _frames(2)
	check(Shotguns.last_results.size() == 12, "hi-brass: 12 pellets (%d)" % Shotguns.last_results.size())
	# The choke: the same shell, a pattern under half as wide.
	inv.take(&"choke_870")
	check(GunAttachments.mount_carried(inv, &"choke_870") and GunAttachments.mounted_id(gun, inv.state_of(&"primary"), GunAttachments.CHOKE) == &"choke_870",
		"the choke goes on the 870")
	var tight := 0.0
	var loose := 0.0
	for i in 4:
		var st := inv.state_of(&"primary").duplicate(true)
		st["rounds"] = 1
		st["tube"] = [String(Shotguns.STANDARD)]
		inv.set_slot_state(&"primary", st)
		shoot.call(Vector3(1, 0, 0))
		await _frames(1)
		tight = maxf(tight, widest.call())
	loose = open_w
	check(tight < loose * 0.6, "choked, the pattern's widest pellet is %.2f degrees off the aim, against %.2f open" % [tight, loose])
	GunAttachments.server_remove(inv, &"primary", GunAttachments.CHOKE)
	# Breaching rounds: the 870 won't take them, and says why.
	inv.set_slot_state(&"primary", {"rounds": 0, "tube": []})
	for id: StringName in [Shotguns.STANDARD, Shotguns.HI_BRASS, Shotguns.BREACHING, &"loader_12g_6", &"loader_12g_7"]:
		while inv.remove_one(id):
			pass
	inv.take(Shotguns.BREACHING, 4)
	player._server_busy_until = 0.0
	check(Shotguns.server_load(player, &"primary", Shotguns.BREACHING) < 0.0 and inv.rounds_in(&"primary") == 0 and inv.count_of(Shotguns.BREACHING) == 4,
		"the 870 won't load breaching rounds: %s" % Shotguns.why_not(gun, Shotguns.BREACHING))
	# Shell by shell: the picked kind first, then the next carried.
	inv.take(Shotguns.STANDARD, 2)
	inv.take(Shotguns.HI_BRASS, 2)
	var each := Shotguns.server_load(player, &"primary", Shotguns.HI_BRASS)
	check(each > 0.3, "a shell goes in every %.2f s" % each)
	await _seconds(each * 4.0 + 0.5)
	var tube := Shotguns.tube_of(inv.state_of(&"primary"))
	check(tube == [String(Shotguns.HI_BRASS), String(Shotguns.HI_BRASS), String(Shotguns.STANDARD), String(Shotguns.STANDARD)] and not Shotguns.loading(player)
		and inv.count_of(Shotguns.BREACHING) == 4, "four shells one by one, hi-brass then standard, the breaching rounds left out (%s)" % [tube])
	# A speed loader in one push: what the 870 takes goes in, the breaching shell stays in the loader.
	inv.set_slot_state(&"primary", {"rounds": 0, "tube": []})
	var mixed := {"rounds": 5, "tube": [String(Shotguns.STANDARD), String(Shotguns.BREACHING), String(Shotguns.HI_BRASS), String(Shotguns.STANDARD), String(Shotguns.HI_BRASS)]}
	inv.take(&"loader_12g_6", 1, mixed)
	player._server_busy_until = 0.0
	var push := Shotguns.server_load(player, &"primary")
	check(push > 1.0, "with a loader carried, R pushes it in at once (%.1f s)" % push)
	await _seconds(push + 0.4)
	var left := []
	for c in inv.search_containers():
		for e: Dictionary in inv.containers[c]:
			if e.id == &"loader_12g_6":
				left = Shotguns.list_of(ItemDB.get_item(&"loader_12g_6"), e.get("state", {}))
	check(inv.rounds_in(&"primary") == 4 and left == [String(Shotguns.BREACHING)],
		"the loader's four standard and hi-brass go in, its breaching shell stays (%d in, %s left)" % [inv.rounds_in(&"primary"), left])
	# Loose shells into loaders (any kind), never a breaching round into a Saiga magazine.
	inv.take(&"mag_saiga12", 1, {"rounds": 0, "tube": []})
	var into := inv.load_rounds(Shotguns.BREACHING, 4)
	var saiga_mag: Array = []
	for c in inv.search_containers():
		for e: Dictionary in inv.containers[c]:
			if e.id == &"mag_saiga12":
				saiga_mag = Shotguns.list_of(ItemDB.get_item(&"mag_saiga12"), e.get("state", {}))
	check(into >= 1 and saiga_mag.is_empty(), "loose breaching rounds fill the speed loader (%d went in), none into the Saiga magazine" % into)
	inv.take(Shotguns.HI_BRASS, 3)
	inv.load_rounds(Shotguns.HI_BRASS, 3)
	for c in inv.search_containers():
		for e: Dictionary in inv.containers[c]:
			if e.id == &"mag_saiga12":
				saiga_mag = Shotguns.list_of(ItemDB.get_item(&"mag_saiga12"), e.get("state", {}))
	check(saiga_mag.has(String(Shotguns.HI_BRASS)), "hi-brass goes into the Saiga magazine (%s)" % [saiga_mag])
	# The Saiga: its magazine's shells in through a swap, fired as what they are.
	inv.slots[&"primary"] = &""
	inv.take(&"saiga12")
	player.active_slot = &"primary"
	var saiga := ItemDB.get_item(&"saiga12")
	inv.set_slot_state(&"primary", {"rounds": 0, "tube": []})
	check(inv.reload(&"primary") > 0 and Shotguns.list_of(saiga, inv.state_of(&"primary")).has(String(Shotguns.HI_BRASS)),
		"a magazine swap puts its shells in the Saiga (%s)" % [Shotguns.list_of(saiga, inv.state_of(&"primary"))])
	inv.set_slot_state(&"primary", {"rounds": 1, "tube": [String(Shotguns.HI_BRASS)]})
	await _seconds(0.3)
	shoot.call(Vector3(1, 0, 0))
	await _frames(2)
	check(Shotguns.last_results.size() == 12 and inv.rounds_in(&"primary") == 0, "the Saiga fires its hi-brass shell through the same path: 12 pellets")
	# The M1014: a breaching round through the planks 1.5 m off, and off a locked box's lock.
	inv.slots[&"primary"] = &""
	inv.take(&"m1014")
	player.active_slot = &"primary"
	var m1014 := ItemDB.get_item(&"m1014")
	player.global_position = Vector3(14.5, 0.1, -7.4)
	await _frames(2)
	eye = player.camera.global_position
	var plank := Vector3(16.05, eye.y, eye.z)
	var world := level.voxel_world
	check(world.material_at(plank) == VoxelWorld.Mat.WOOD, "a plank wall in front of him")
	inv.set_slot_state(&"primary", {"rounds": 1, "tube": [String(Shotguns.BREACHING)]})
	await _seconds(60.0 / float(m1014.stats.rpm) + 0.1)
	shoot.call(Vector3(1, 0, 0))
	await _frames(5)
	check(String(Shotguns.last_breach.get("what", "")) == "wall" and world.material_at(plank) == VoxelWorld.Mat.EMPTY,
		"the M1014's breaching round blows a hole through the planks")
	var cache := WorldCache.new("Strongbox", &"hq_strongbox_key")
	level.add_child(cache)
	cache.global_position = Vector3(14.5, 0.0, -5.6)
	await _frames(2)
	inv.set_slot_state(&"primary", {"rounds": 1, "tube": [String(Shotguns.BREACHING)]})
	await _seconds(60.0 / float(m1014.stats.rpm) + 0.1)
	check(cache.is_locked(), "a locked strongbox by his feet")
	player._server_busy_until = 0.0
	player._server_next_shot = 0.0
	player._server_fire.rpc_id(1, player.camera.global_position, (cache.global_position + Vector3.UP * 0.2 - player.camera.global_position).normalized(), &"primary")
	await _frames(3)
	check(not cache.is_locked() and String(Shotguns.last_breach.get("what", "")) == "lock", "and shoots a box's lock off")
	cache.queue_free()
	# Firing stops a load.
	inv.set_slot_state(&"primary", {"rounds": 0, "tube": []})
	for id: StringName in [&"loader_12g_6", &"loader_12g_7"]:
		while inv.remove_one(id):
			pass
	inv.take(Shotguns.STANDARD, 6)
	await _seconds(60.0 / float(m1014.stats.rpm) + 0.1)
	player._server_busy_until = 0.0
	each = Shotguns.server_load(player, &"primary", Shotguns.STANDARD)
	await _seconds(each * 1.5)
	shoot.call(Vector3(0, 0, 1))
	await _seconds(each * 2.0)
	check(inv.rounds_in(&"primary") == 0 and not Shotguns.loading(player), "firing between shells stops the load (%d in the tube)" % inv.rounds_in(&"primary"))
	# The tube is the gun's state: saved and loaded (JSON), and a peer's copy.
	inv.set_slot_state(&"primary", {"rounds": 2, "tube": [String(Shotguns.BREACHING), String(Shotguns.HI_BRASS)]})
	var saved: Variant = JSON.parse_string(JSON.stringify(Roster.json_safe(inv.net_state)))
	var loaded := Inventory.new()
	add_child(loaded)
	loaded.net_state = GameState.from_json(saved)
	var copy := Inventory.new()
	add_child(copy)
	copy.net_state = inv.net_state
	await _frames(1)
	check(Shotguns.tube_of(loaded.state_of(&"primary")) == [String(Shotguns.BREACHING), String(Shotguns.HI_BRASS)] and loaded.rounds_in(&"primary") == 2
		and Shotguns.next_shell(copy.state_of(&"primary")) == Shotguns.HI_BRASS, "saved and loaded, and on a peer's copy, the tube keeps its shells in order")
	loaded.queue_free()
	copy.queue_free()
	var readout := AmmoReadout.summary(player)
	check(String(readout.get("kind", "")) == "tube" and String(readout.get("loaded", "")).contains("Hi-Brass"), "the HUD reads the tube and the shell up next: %s" % AmmoReadout.text_of(readout))
	# F-131: the AI counts the shells it carries, loose and in loaders, as spare ammo for the gun.
	inv.take(Shotguns.STANDARD, 5)
	inv.take(&"loader_12g_7", 1)
	check(inv.spare_rounds(Shotguns.STANDARD, m1014) == inv.count_of(Shotguns.STANDARD) + inv.count_of(Shotguns.HI_BRASS) + inv.count_of(Shotguns.BREACHING) + 7
		and SquadAI._mag_size(m1014) == 7, "an M1014's spare shells: %d (loose and the loader's), a tube of 7" % inv.spare_rounds(Shotguns.STANDARD, m1014))
	# The Skeleton Key under an M4: 4 switches the trigger to it, a breaching round through the planks.
	inv.slots[&"primary"] = &""
	inv.take(&"m4a1")
	inv.take(&"skeleton_key")
	player.active_slot = &"primary"
	check(GunAttachments.mount_carried(inv, &"skeleton_key") and Shotguns.key_of(player) != null, "the Skeleton Key goes under the M4")
	# A stretch of the plank wall clear of the M1014's hole (and the buckshot's): wood a hand either side.
	var bore_y := eye.y - 0.07
	var clear_z := -INF
	for i in 60:
		var z := -11.0 + i * 0.1
		if absf(z + 7.4) < 0.9 or absf(z + 8.1) < 0.5:
			continue
		if [-0.15, 0.0, 0.15].all(func(dz: float) -> bool: return world.material_at(Vector3(16.05, bore_y, z + dz)) == VoxelWorld.Mat.WOOD):
			clear_z = z
			break
	player.global_position = Vector3(14.5, 0.1, clear_z if clear_z > -INF else -6.6)
	await _frames(2)
	eye = player.camera.global_position
	plank = Vector3(16.05, eye.y - 0.07, eye.z)
	var was_wood := world.material_at(plank) == VoxelWorld.Mat.WOOD
	var before := Shotguns.key_list(Shotguns.key_of(player), inv.state_of(&"primary")).size()
	player.underbarrel_up = true
	player._server_busy_until = 0.0
	var why := Shotguns.server_fire_key(player, eye, Vector3(1, 0, 0))
	await _frames(5)
	check(why == "" and was_wood and before == 3 and String(Shotguns.last_breach.get("what", "")) == "wall" and world.material_at(plank) == VoxelWorld.Mat.EMPTY
		and Shotguns.key_list(Shotguns.key_of(player), inv.state_of(&"primary")).size() == 2,
		"the Key fires its breaching round through the planks, two left in its tube (%s; wood %s, %d in it, breach %s, then %s, %d left)"
		% [why, was_wood, before, Shotguns.last_breach, world.material_at(plank), Shotguns.key_list(Shotguns.key_of(player), inv.state_of(&"primary")).size()])
	inv.take(Shotguns.BREACHING, 2)
	player._server_busy_until = 0.0
	var k_each := Shotguns.server_load(player, &"primary", &"", true)
	await _seconds(k_each + 0.3)
	check(Shotguns.key_list(Shotguns.key_of(player), inv.state_of(&"primary")).size() == 3, "R with the Key up loads it shell by shell")
	player.underbarrel_up = false
	inv.slots[&"primary"] = &""
	# The breacher's kit: the Skeleton Key under his Mk18, full of breaching rounds, shells to spare.
	var bkit := Inventory.new()
	add_child(bkit)
	Roles.apply_kit(bkit, Roles.BREACHER)
	var kit_gun := ItemDB.get_item(bkit.slots[&"primary"])
	var kit_key := Shotguns.key_on(kit_gun, bkit.state_of(&"primary"))
	check(bkit.slots[&"primary"] == &"mk18" and kit_key != null and Shotguns.key_list(kit_key, bkit.state_of(&"primary")).all(func(x: Variant) -> bool: return StringName(String(x)) == Shotguns.BREACHING)
		and bkit.count_of(Shotguns.BREACHING) >= 6 and bkit.count_of(Shotguns.STANDARD) >= 4 and bkit.count_of(&"breaching_charge") == 3,
		"the breacher's kit: the Skeleton Key under his Mk18, full of breaching rounds, breaching and standard shells, three charges")
	bkit.queue_free()
	# The grenadier's kit: the M320 on his M4 with HE and smoke.
	var kit := Inventory.new()
	add_child(kit)
	Roles.apply_kit(kit, Roles.GRENADIER)
	check(GunAttachments.mounted_id(ItemDB.get_item(kit.slots[&"primary"]), kit.state_of(&"primary"), GunAttachments.UNDERBARREL) == &"m320"
		and kit.count_of(&"round_40mm_he") >= 6 and kit.count_of(&"round_40mm_smoke") >= 1, "the grenadier's kit: an M320 on his M4, 40 mm HE and smoke")
	kit.queue_free()
	player.global_position = Vector3(0, 0.1, 24)


func _dummy(pos: Vector3) -> TargetDummy:
	var dummy: TargetDummy = load("res://scenes/target_dummy.tscn").instantiate()
	dummy.respawn_seconds = 999.0
	level.add_child(dummy)
	dummy.global_position = pos
	return dummy


func _wait_result(launchers: Launchers, id: int, limit: float) -> void:
	var start := Soldier._now()
	while not launchers.results.has(id) and Soldier._now() - start < limit:
		await get_tree().physics_frame
