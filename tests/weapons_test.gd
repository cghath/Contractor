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
	"m27": ["mag_556", "556_m855", "rounds_556", "III++", "intermediate"],
	"hk416": ["mag_556", "556_m855", "rounds_556", "III++", "intermediate"],
	"l85a2": ["mag_556", "556_m855", "rounds_556", "III++", "intermediate"],
	"c8": ["mag_556", "556_m855", "rounds_556", "III++", "intermediate"],
}
## Magazines and belts: capacity.
const CAPACITY := {"mag_762x39": 30, "mag_545": 30, "mag_rpk40": 40, "mag_svd": 10, "belt_762x54r": 100, "box_556": 200, "belt_762x51": 100}
## Guns fired and reloaded for real on the host player.
const FIRED: Array[String] = ["akm", "ak74", "rpk", "pkm", "svd", "m249", "m240b"]
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
	await _test_hostile_kits()
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
	check(VoxelArt.model_for(ItemDB.get_item(&"akm")).ends_with(":ak") and VoxelArt.model_for(ItemDB.get_item(&"pkm")).ends_with(":mg"), "AKs and machine guns have their own silhouettes")
	check(not VoxelArt.model_for(ItemDB.get_item(&"m4a1")).ends_with(":ak"), "the M4 keeps its own")
	check(VoxelArt.model_for(ItemDB.get_item(&"akm")).contains(":irons:") and VoxelArt.model_for(ItemDB.get_item(&"pkm")).contains(":irons:"),
		"an AK or MG with no rail shows iron sights, not a dead red-dot block (%s)" % VoxelArt.model_for(ItemDB.get_item(&"akm")))


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
		check(gun in OPFOR and s.inventory.count_of(ammo) >= 1 and s.inventory.rounds_in(&"primary") > 0,
			"hostile %d carries %s with %d spare %s, loaded" % [i, gun, s.inventory.count_of(ammo), ammo])
		s.queue_free()


func _test_roles() -> void:
	print("Roles")
	var ids := Roles.kit(Roles.AUTORIFLEMAN).map(func(p: Array) -> String: return String(p[0]))
	check(ids.has("m249") and ids.has("box_556") and not ids.has("mag_556"), "the autorifleman's kit is an M249 and its boxes")


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
