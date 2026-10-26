extends Node
## The dead over time (docs/survival_deadtime.md; survival.md calls 112, 114, 115, 140): in a
## hosted survival world: a fresh one of the dead is faster, hits harder and has more pool than an
## old one, and the old one's limbs come apart; the world's date sets the mix of stages and winter
## keeps them (no decay); the look meta and the clothes change with the stage; the crowd's heads
## carry their stage and origin; one of the dead at a military site has plates on it and now and
## then a weathered rifle, at a clinic a doctor's bag, and they stay on the corpse for the looting;
## the early loot curve: no soldiers' dead or guns in the boxes about the farm, the soldiers' share
## grows with the zone's tier, a soldier's rifle is usually gone and a kept one is worn and near empty; a site's mix of origins
## says what it was; a nest holds its heads by day, pours them out at dusk and takes them back at
## dawn; a nest entered by day lies dormant, a silent kill leaves the rest asleep, a scream wakes
## them all; clearing it flags the payoff and it refills over the days; walkers don't climb, a
## runner vaults a metre, a crawler squeezes a 0.4 m gap and the dead's paths keep off climb links.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier


func _ready() -> void:
	get_tree().create_timer(380.0).timeout.connect(func() -> void:
		print("DEADTIME TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _test_host()
	if level != null and player != null:
		await _probe_start_loot()
		await _test_decay()
		_test_mix()
		await _test_dress()
		await _test_nests()
		await _test_climb()
	_finish()


func _test_host() -> void:
	print("A survival world")
	check(Survival.server_new_world(main, "test_deadtime" + tag, 777), "a new world hosts")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	check(player != null, "the host's survivor is in")
	if player == null:
		return
	for i in 120:
		await get_tree().process_frame
	Survival._pop = -100000.0  # (the test puts the dead down itself)
	Seasons.force_frost = 0
	DeadNests.force_hour = 12.0
	Survival.state()["nests_seeded_" + String(Survival.state().get("zone", ""))] = true  # (the zone's own nests left out: the test makes its own)
	DeadNests.all().clear()
	_clear_dead()


# --- The early loot curve (the Captain's playtest, 2026-10-26: "got a gun off a mil zombie in the
# first 5 minutes"): what a fresh world's start puts within START_PROBE_M of the farm. Prints the
# numbers (docs/survival_deadtime.md "Early loot curve") and holds the targets.
const START_PROBE_M := 300.0
const START_PROBE_DEAD := 30


func _probe_start_loot() -> void:
	print("The early loot curve: what lies within %.0f m of the farm" % START_PROBE_M)
	var points := level.insertion_points()
	var home := level.ground_point(points[0] if not points.is_empty() else Vector3.ZERO)
	var guns := 0
	var working := 0
	var rounds := 0
	var gun_ids: Array = []
	for c: Node in get_tree().get_nodes_in_group(WorldCache.GROUP):
		var cache := c as WorldCache
		if cache == null or cache.global_position.distance_to(home) > START_PROBE_M:
			continue
		for e: Dictionary in cache.cargo_hold.entries():
			var r := _probe_count(StringName(String(e.id)), int(e.count), e.get("state", {}))
			guns += r[0]
			working += r[1]
			rounds += r[2]
			if r[0] > 0:
				gun_ids.append("%s (%s)" % [e.id, cache.display_name()])
	for n: Node in level.items.get_children():
		var wi := n as WorldItem
		if wi == null or wi.global_position.distance_to(home) > START_PROBE_M:
			continue
		var r := _probe_count(wi.item_id, wi.count, wi.state)
		guns += r[0]
		working += r[1]
		rounds += r[2]
		if r[0] > 0:
			gun_ids.append("%s (ground)" % wi.item_id)
	print("  containers and ground: %d guns (%d working), %d rounds: %s" % [guns, working, rounds, gun_ids])
	# The dead: their origins over many rolls where they'd turn about the farm, then the first
	# START_PROBE_DEAD as bodies, looted.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var mix := {}
	for i in 600:
		var a := rng.randf() * TAU
		var at := home + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(20.0, START_PROBE_M)
		var o := String(DeadDecay.spawn_data(level, at, Survival.roll_kind(level, at, rng), {}).origin)
		mix[o] = int(mix.get(o, 0)) + 1
	print("  the dead's origins about the farm (600 rolls): %s" % [mix])
	var armed := 0
	var armed_working := 0
	var dead_rounds := 0
	for i in START_PROBE_DEAD:
		var a := rng.randf() * TAU
		var at := level.ground_point(home + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(45.0, START_PROBE_M))
		var z := Survival.server_spawn_zombie(level, at, Survival.roll_kind(level, at, rng))
		if z == null:
			continue
		var has_gun := false
		var has_working := false
		for e: Dictionary in Survival.kit_of(z.inventory):
			var r := _probe_count(StringName(String(e.id)), int(e.get("count", 1)), e.get("state", {}))
			has_gun = has_gun or r[0] > 0
			has_working = has_working or r[1] > 0
			dead_rounds += r[2]
		armed += 1 if has_gun else 0
		armed_working += 1 if has_working else 0
	print("  the first %d dead: %d carry a gun (%d working), %d rounds between them" % [START_PROBE_DEAD, armed, armed_working, dead_rounds])
	_clear_dead()
	await get_tree().process_frame
	# The targets (Proposed): nothing armed turns or lies in a box near the farm; on the rest of the
	# start zone's ground fewer than one of the first 30 dead carries a gun, on average.
	var near_soldiers := 0
	var near_guns := 0
	for i in 400:
		var a := rng.randf() * TAU
		var at := home + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(5.0, FoundLoot.START_CLEAR_M - 5.0)
		if not FoundLoot.military(DeadDress.site_at(level, at)) and String(DeadDress.roll_at(level, at, rng)) == "soldier":
			near_soldiers += 1
	for c: Node in get_tree().get_nodes_in_group(WorldCache.GROUP):
		var cache := c as WorldCache
		if cache and cache.global_position.distance_to(home) <= FoundLoot.START_CLEAR_M - 1.0 and not FoundLoot.military(DeadDress.site_at(level, cache.global_position)) \
				and FoundLoot.first_roll([{"id": "akm", "count": 1}], cache).size() > 0 and (cache.uid.begins_with("scatter_val") or "_box_" in cache.uid):
			near_guns += 1
	var per := 0.0
	for o: String in mix:
		var gun: Array = (DeadDress.KITS.get(o, {}) as Dictionary).get("gun", [])
		per += float(mix[o]) / 600.0 * (float(gun[1]) if gun.size() == DeadDress.GUN_KEYS.size() else 0.0)
	print("  expected: %.2f of the first %d dead carry a gun" % [per * START_PROBE_DEAD, START_PROBE_DEAD])
	check(near_soldiers == 0, "no soldiers turn within %.0f m of the farm (%d of 400)" % [FoundLoot.START_CLEAR_M, near_soldiers])
	check(near_guns == 0, "a box about the farm keeps no gun (%d)" % near_guns)
	check(per * START_PROBE_DEAD < 1.0, "fewer than one of the first %d dead about the farm carries a gun, on average (%.2f)" % [START_PROBE_DEAD, per * START_PROBE_DEAD])
	_test_kit_odds()


## The soldier's and the cop's kit over many seeded rolls (DeadDress.kit_roll), and the tier.
func _test_kit_odds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var n := 400
	var tally := {"gun": 0, "carrier": 0, "helmet": 0, "pistol": 0}
	var worst_rounds := 0
	var weathered := true
	for i in n:
		for e: Array in DeadDress.kit_roll("soldier", "walker", rng):
			match String(e[0]):
				"m4a1":
					tally.gun += 1
					weathered = weathered and Wear.cond(e[2]) <= WeaponCondition.FOUND_WET.y
					worst_rounds = maxi(worst_rounds, int((e[2] as Dictionary).get("rounds", 0)))
				"mag_556":
					worst_rounds = maxi(worst_rounds, int((e[2] as Dictionary).get("rounds", 0)))
				"plate_carrier_light":
					tally.carrier += 1
				"helmet_ach":
					tally.helmet += 1
		for e: Array in DeadDress.kit_roll("cop", "walker", rng):
			if String(e[0]) == "glock17":
				tally.pistol += 1
				worst_rounds = maxi(worst_rounds, int((e[2] as Dictionary).get("rounds", 0)))
	var g := float(tally.gun) / n
	check(g > 0.18 and g < 0.32 and int(tally.carrier) > int(tally.gun) and int(tally.helmet) > int(tally.gun),
		"a soldier keeps his rifle %.0f%% of the time; his carrier (%.0f%%) and helmet (%.0f%%) more often" % [g * 100.0, float(tally.carrier) / n * 100.0, float(tally.helmet) / n * 100.0])
	var pc := float(tally.pistol) / n
	check(pc > 0.22 and pc < 0.38 and weathered and worst_rounds <= 8,
		"a cop's pistol %.0f%% of the time; out in the weather every kept gun is worn, no more than 8 rounds in a magazine (%d)" % [pc * 100.0, worst_rounds])
	var far := level.ground_point(player.global_position + Vector3(0, 0, 600))
	var shares: Array[float] = []
	for t in [0, 2]:
		FoundLoot.force_tier = t
		var hits := 0
		for i in 2000:
			if DeadDress.roll("", rng, "walker", FoundLoot.armed_mults(level, far, "")) == "soldier":
				hits += 1
		shares.append(float(hits) / 2000.0)
	FoundLoot.force_tier = -1
	check(shares[0] < 0.04 and shares[1] > shares[0] * 2.0, "away from the military the soldiers' share grows with the zone's tier (%.1f%% at 0, %.1f%% at 2)" % [shares[0] * 100.0, shares[1] * 100.0])


## [guns, working guns, rounds] in `n` of `id` with `state` (a gun's loaded rounds count; a
## working gun is one not broken (condition over 0)).
func _probe_count(id: StringName, n: int, state: Dictionary) -> Array:
	var item := ItemDB.get_item(id)
	if item == null:
		return [0, 0, 0]
	if WeaponCondition.is_gun(item):
		var st: Dictionary = state if not state.is_empty() else item.default_state()
		var ok := 0 if (st.has(Wear.KEY) and Wear.cond(st) <= 0.0) else n
		return [n, ok, int(st.get("rounds", 0)) * n]
	if item.type == "ammo":
		if Inventory.is_loose_rounds(item):
			return [0, 0, n]
		return [0, 0, int(state.get("rounds", item.magazine_rounds())) * n]
	return [0, 0, 0]


func _test_decay() -> void:
	print("Decay stages (call 112)")
	Survival.state()["fall_weeks"] = 3
	var now := DeadDecay.kept_since()
	var fresh := _zombie(Vector3(70, 0, 0), "walker", {"turned": now})
	var old := _zombie(Vector3(70, 0, 6), "walker", {"turned": now - 400.0})
	await get_tree().process_frame
	check(fresh != null and old != null, "a fresh one and an old one")
	if fresh == null or old == null:
		return
	var fb := ZombieAI.of(fresh)
	var ob := ZombieAI.of(old)
	check(String(fresh.get_meta(&"dead_decay", "")) == "fresh" and String(old.get_meta(&"dead_decay", "")) == "old",
		"the look meta says the age (%s, %s)" % [fresh.get_meta(&"dead_decay", "?"), old.get_meta(&"dead_decay", "?")])
	check(fb != null and ob != null and fb.pace() > ob.pace() * 1.2, "the fresh one is faster (%.2f vs %.2f)" % [fb.pace() if fb else 0.0, ob.pace() if ob else 0.0])
	check(fresh.vitals.undead_pool > old.vitals.undead_pool * 1.5, "and has more pool (%.1f vs %.1f)" % [fresh.vitals.undead_pool, old.vitals.undead_pool])
	check(DeadDecay.strike_mult(fresh) > DeadDecay.strike_mult(old), "and hits harder (x%.2f vs x%.2f)" % [DeadDecay.strike_mult(fresh), DeadDecay.strike_mult(old)])
	check(DeadDecay.limb_mult(old, &"forearm_l") > DeadDecay.limb_mult(fresh, &"forearm_l") and is_equal_approx(DeadDecay.limb_mult(old, Vitals.HEAD), 1.0),
		"an old one's limbs come apart easier (x%.2f), its head no different" % DeadDecay.limb_mult(old, &"forearm_l"))
	var fskin := fresh.variant.split(":")
	var oskin := old.variant.split(":")
	check(fskin.size() >= 5 and oskin.size() >= 5 and fskin[3] != oskin[3], "the skin goes from flesh-grey to bone (%s -> %s)" % [fskin[3] if fskin.size() > 3 else "?", oskin[3] if oskin.size() > 3 else "?"])
	var plain := "civ:a65e48:3b4a63:c8996f:6b4a2b"
	var aged := DeadDecay.look(plain, 1.0).split(":")
	check(Color(aged[1]).s < Color("a65e48").s and Color(aged[1]).v < Color("a65e48").v, "an old one's clothes are greyed and dirtied (%s)" % aged[1])
	# The crowd's heads carry it.
	var crowd := ZoneDead.of(level)
	check(crowd != null and crowd.server_add(level.ground_point(player.global_position + Vector3(150, 0, 0))), "a head in the crowd")
	if crowd:
		var d: Dictionary = crowd.dead[crowd.dead.size() - 1]
		check(d.has("turned") and String(d.get("origin", "")) in DeadDress.ORIGIN_NAMES and ZoneDead.stage_of(d) in DeadDecay.STAGES,
			"the crowd's head carries its age and origin (%s, %s)" % [ZoneDead.stage_of(d), d.get("origin", "?")])
		var back := DeadDecay.carry(old)
		check(is_equal_approx(float(back.turned), float(old.get_meta(&"dead_turned"))) and String(back.origin) == String(old.get_meta(&"dead_origin")),
			"a body going back into the crowd keeps both")
		crowd.dead.clear()
	_clear_dead()
	await get_tree().process_frame


func _test_mix() -> void:
	print("The world's date sets the mix")
	Survival.state()["fall_weeks"] = 3
	var early := DeadDecay.mix(1.0)
	var late := DeadDecay.mix(60.0)
	check(float(early.fresh) > 0.6 and float(late.old) > float(early.old) + 0.3 and float(late.fresh) < float(early.fresh),
		"early on most are fresh (%s); months on most are old (%s)" % [_pct(early), _pct(late)])
	var a := DeadDecay.kept_since(31.0)
	var b := DeadDecay.kept_since(41.0)
	check(Seasons.of_day(35, "spring") == "winter" and is_equal_approx(a, b) and DeadDecay.kept_since(51.0) > b,
		"winter's days don't rot them: the frozen keep (%.0f = %.0f story days, then %.0f)" % [a, b, DeadDecay.kept_since(51.0)])
	check(DeadDecay.count_mult(60.0) > DeadDecay.count_mult(1.0), "and there are more of them as the months go (x%.2f -> x%.2f)" % [DeadDecay.count_mult(1.0), DeadDecay.count_mult(60.0)])


func _test_dress() -> void:
	print("The dead wear what they were (call 114)")
	DeadDress.force_site = "hq"
	DeadDress.force_gun_keep = 1.0  # (the rifle's share is checked on kit_roll: _test_kit_odds)
	var soldiers: Array = []
	for i in 8:
		var z := _zombie(Vector3(80, 0, i * 2.0), "walker")
		if z and String(z.get_meta(&"dead_origin", "")) == "soldier":
			soldiers.append(z)
	DeadDress.force_site = "clinic"
	var doctors: Array = []
	for i in 8:
		var z := _zombie(Vector3(86, 0, i * 2.0), "walker")
		if z and String(z.get_meta(&"dead_origin", "")) == "doctor":
			doctors.append(z)
	DeadDress.force_site = ""
	DeadDress.force_gun_keep = -1.0
	await get_tree().process_frame
	check(not soldiers.is_empty() and not doctors.is_empty(), "the base's dead are mostly soldiers (%d of 8), the clinic's doctors (%d of 8)" % [soldiers.size(), doctors.size()])
	if soldiers.is_empty() or doctors.is_empty():
		return
	var s: Soldier = soldiers[0]
	var inv := s.inventory
	var plated: Array = soldiers.filter(func(z: Soldier) -> bool: return DeadDress.carried(z.inventory, &"plate_carrier_light") > 0)
	check(DeadDress.carried(inv, &"m4a1") > 0 and not plated.is_empty(),
		"a soldier who kept his rifle has it on him, and soldiers wear carriers (%d of %d: %s)" % [plated.size(), soldiers.size(), Survival.kit_of(inv).map(func(e: Dictionary) -> String: return String(e.id))])
	var gun_st: Dictionary = {}
	for e: Dictionary in Survival.kit_of(inv):
		if String(e.id) == "m4a1":
			gun_st = e.get("state", {})
	check(gun_st.has(Wear.KEY) and Wear.cond(gun_st) <= WeaponCondition.FOUND_WET.y and int(gun_st.get("rounds", 99)) <= 8,
		"and it's weathered (%.0f%%), its magazine near empty (%d rounds)" % [Wear.cond(gun_st), int(gun_st.get("rounds", -1))])
	check(inv.slots[&"primary"] == &"" and inv.slots[&"sidearm"] == &"" and s.active_weapon() == null, "and the rifle rides in his pack: the dead don't use weapons")
	var shirt := s.variant.split(":")[1]
	check(Color(shirt).g >= Color(shirt).b, "and he's in uniform colours (%s)" % shirt)
	var doc: Soldier = doctors[0]
	check(DeadDress.carried(doc.inventory, &"aid_bag") > 0 and DeadDress.carried(doc.inventory, &"suture_kit") > 0, "a doctor has a doctor's bag and meds")
	var hz := _zombie(Vector3(92, 0, 0), "hazmat")
	check(hz != null and String(hz.get_meta(&"dead_origin", "")) == "soldier" and DeadDress.carried(hz.inventory, &"gas_mask_m50") > 0 and DeadDress.carried(hz.inventory, &"plate_carrier_light") > 0,
		"the hazmat one was a soldier of the decon teams: plates and a mask")
	# Loot yields them: the corpse keeps it all.
	s.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.PISTOL, "energy_j": 400.0})
	for i in 6:
		await get_tree().process_frame
	check(s.vitals.is_dead() and DeadDress.carried(s.inventory, &"m4a1") > 0,
		"put down, his corpse still has the rifle to loot")
	# A site's mix of origins tells what it was.
	check(DeadDress.leading(DeadDress.site_mix("hq")) == "soldier" and DeadDress.leading(DeadDress.site_mix("clinic")) == "doctor"
		and DeadDress.leading(DeadDress.site_mix("police")) == "cop" and DeadDress.leading(DeadDress.site_mix("farm")) == "farmer"
		and DeadDress.leading(DeadDress.site_mix("factory")) == "worker", "a site's mix of origins tells its type")
	DeadDress.force_site = "police"
	var line := DeadDress.tell(level, player.global_position + Vector3(0, 0, -300), 5.0)
	DeadDress.force_site = ""
	check("Police" in line, "a place's dead say what it was (%s)" % line)
	_clear_dead()
	await get_tree().process_frame


func _test_nests() -> void:
	print("Nests and roosts (call 115)")
	var crowd := ZoneDead.of(level)
	crowd.dead.clear()
	DeadNests.force_hour = 12.0
	var at := player.global_position + Vector3(0, 0, 150)
	var id := DeadNests.server_add(level, "nest_test", at, 6, "church")
	DeadNests.server_tick(level)
	var rec := DeadNests.get_nest(id)
	check(not bool(rec.out) and int(rec.n) == 6 and _tagged(id) == 0, "by day the nest holds its six inside, none drawn outside")
	DeadNests.force_hour = 20.0
	DeadNests.server_tick(level)
	check(bool(rec.out) and int(rec.n) == 0 and _tagged(id) == 6, "at dusk they pour out of its door (%d in the crowd)" % _tagged(id))
	for d: Dictionary in crowd.dead:
		if String(d.get("nest", "")) == id:
			d.pos = d.to  # (the night out: they've walked off round it)
	DeadNests.force_hour = 6.5
	DeadNests.server_tick(level)
	var walking_back := crowd.dead.filter(func(d: Dictionary) -> bool: return String(d.get("nest", "")) == id and (d.target as Vector2).distance_to(Vector2(at.x, at.z)) < 3.0).size()
	check(walking_back == 6, "at dawn they walk back to it (%d)" % walking_back)
	DeadNests.force_hour = 8.5
	DeadNests.server_tick(level)
	check(not bool(rec.out) and int(rec.n) == 6 and _tagged(id) == 0, "and are counted back in (%d inside)" % int(rec.n))
	if not level.modules().is_empty():
		var mod: ZoneModule = level.modules()[0]
		var mid := DeadNests.server_add(level, "nest_" + mod.module_id, mod.global_position, 4)
		var by_day := DeadNests.outside_mult(mod)
		DeadNests.force_hour = 22.0
		var by_night := DeadNests.outside_mult(mod)
		DeadNests.force_hour = 8.5
		check(is_equal_approx(by_day, DeadNests.OUTSIDE_BY_DAY) and is_equal_approx(by_night, 1.0), "by day a site's dead sit in its nest: fewer about it outside (x%.1f by day, x%.1f by night)" % [by_day, by_night])
		DeadNests.all().erase(mid)
	# Entering it by day: dormant.
	DeadNests.force_hour = 12.0
	var made := DeadNests.server_enter(level, id)
	await get_tree().process_frame
	var bodies := DeadNests.bodies(level, id)
	check(made == 6 and bodies.size() == 6 and bodies.all(func(z: Soldier) -> bool: return ZombieAI.of(z) != null and ZombieAI.of(z).dormant and ZombieAI.of(z).unaware()),
		"entered by day, the six lie dormant, packed by the door (%d)" % bodies.size())
	for i in 30:
		await get_tree().physics_frame
	var first: Soldier = bodies[0]
	first.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.PISTOL, "channel_depth": 0.08, "melee": "silent", "energy_j": 400.0})
	for i in 10:
		await get_tree().physics_frame
	var asleep := DeadNests.bodies(level, id).filter(func(z: Soldier) -> bool: return ZombieAI.of(z).dormant).size()
	check(first.vitals.is_dead() and asleep == 5 and int(rec.inside) == 5, "a silent kill leaves the rest asleep (%d dormant)" % asleep)
	var screamer: Soldier = DeadNests.bodies(level, id)[0]
	Survival.server_noise(screamer, screamer.global_position, ZombieAI.SCREAM_M, ZombieAI.HEAR_SHOT)
	await get_tree().physics_frame
	# (>= 0.9: a body whose think tick lands on this frame has already let FALL x THINK_S go: a flake, R2713)
	var awake := DeadNests.bodies(level, id).filter(func(z: Soldier) -> bool: return not ZombieAI.of(z).dormant and ZombieAI.of(z).awareness >= 0.9).size()
	check(awake == 5, "a scream wakes them all at once (%d of 5)" % awake)
	for z: Soldier in DeadNests.bodies(level, id):
		z.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.PISTOL, "energy_j": 400.0})
	for i in 10:
		await get_tree().physics_frame
	check(bool(rec.cleared) and DeadNests.loot_bonus(id), "the last of it down clears the nest: its loot untouched (the payoff flag)")
	var journal: Array = Survival.state().get("journal", [])
	check(not journal.is_empty() and "nest" in String((journal[journal.size() - 1] as Dictionary).text), "and the journal says so")
	var day0 := Survival.day()
	Survival.state()["day"] = day0 + 2
	DeadNests._refill(rec)
	check(int(rec.n) > 0 and int(rec.n) < int(rec.cap), "it refills slowly (%d of %d after two days)" % [int(rec.n), int(rec.cap)])
	Survival.state()["day"] = day0
	check(DeadNests.take_bonus(id) and not DeadNests.loot_bonus(id), "the payoff is taken once")
	DeadNests.all().erase(id)
	_clear_dead()
	await get_tree().process_frame


func _test_climb() -> void:
	print("Climbing rules (call 140)")
	check(not ZombieAI.can_climb("walker") and not ZombieAI.can_climb("runner") and not ZombieAI.can_get_up("walker", 1.0), "walkers don't climb a ladder or get up a metre")
	check(ZombieAI.can_get_up("runner", 1.0) and not ZombieAI.can_get_up("runner", 1.4), "a runner vaults a metre, not more")
	check(ZombieAI.can_pass_gap("crawler", 0.4) and not ZombieAI.can_pass_gap("walker", 0.4) and not ZombieAI.can_pass_gap("runner", 0.4), "a crawler squeezes through a 0.4 m gap, nobody else")
	check(is_equal_approx(ZombieAI.VAULT_M, Sieges.VAULT_M) and (ZombieAI.NAV_LAYERS & ZombieAI.CLIMB_LAYER) == 0, "the walls' vault matches, and the dead's paths keep off climb links")
	var w := _zombie(Vector3(70, 0, -10), "walker")
	var r := _zombie(Vector3(70, 0, -14), "runner")
	await get_tree().process_frame
	if w and r:
		var wb := ZombieAI.of(w)
		var rb := ZombieAI.of(r)
		check(wb.ledge_blocked(w.global_position + Vector3(1, 3.0, 0)) and not rb.ledge_blocked(r.global_position + Vector3(1, 1.0, 0)),
			"a man on a 3 m platform is out of a walker's reach; a runner gets up a metre")
	_clear_dead()


func _tagged(id: String) -> int:
	return ZoneDead.of(level).dead.filter(func(d: Dictionary) -> bool: return String(d.get("nest", "")) == id and bool(d.alive)).size()


func _pct(m: Dictionary) -> String:
	return "%.0f%% fresh, %.0f%% worn, %.0f%% old" % [float(m.fresh) * 100.0, float(m.worn) * 100.0, float(m.old) * 100.0]


func _zombie(off: Vector3, kind := "walker", extra := {}) -> Soldier:
	return Survival.server_spawn_zombie(level, level.ground_point(player.global_position + off), kind, extra)


func _clear_dead() -> void:
	for z: Soldier in Survival.zombies(level):
		z.queue_free()
	var crowd := ZoneDead.of(level)
	if crowd:
		crowd.dead.clear()


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _finish() -> void:
	Seasons.force_frost = -1
	DeadNests.force_hour = -1.0
	DeadDecay.force_day = -1.0
	DeadDress.force_site = ""
	DeadDress.force_gun_keep = -1.0
	FoundLoot.force_tier = -1
	if Survival.world != "":
		GameState.delete_save()
		Survival.running = false
		Campaign.reset_campaign()
	print("DEADTIME TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
