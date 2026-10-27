extends Node
## Contractor: Fallen's fauna and flora (docs/survival_nature.md; calls 42, 100-107): in a hosted
## survival world with a settlement on flat ground: the zone has its animals; deer flee a player's
## shot (a running herd is a tell) and the dead chase an animal and bite it down; a carcass is a
## smell source the dead walk to; a snare catches a rabbit over the hours; butchering yields raw meat
## and a hide; fishing yields by season; winter moves the deer to the valleys and empties the birds;
## crows mark a body; flies sicken and rats cost the settlement food, a cat halves it; an infected dog
## is fast and low; regrowth rises with the day and the settlement's paths stay clear; berries in
## summer and mushrooms in autumn forage, a death cap poisons a novice and is told apart at
## fieldcraft 4; felling an oak takes longer than a pine, makes noise, yields planks, leaves a stump
## and regrows over seasons; a wildfire spreads downwind through dry grass, stops at a firebreak and
## the rain, burns a wood block, draws the dead with its smoke, and a burning zombie keeps walking.
## Ticks and days are driven directly.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier
var b: Builder
var st: Settlement
var nat: Nature
var origin := Vector3i.ZERO
var _n := 0


func _ready() -> void:
	get_tree().create_timer(380.0).timeout.connect(func() -> void:
		print("NATURE TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _test_host()
	if b != null and player != null and st != null and nat != null:
		_test_flee()
		await _test_dead_hunt()
		await _test_smell()
		_test_snare_and_butcher()
		_test_fishing()
		_test_migration()
		await _test_crows()
		_test_flies_rats()
		_test_infected()
		_test_regrowth()
		_test_forage()
		_test_trees()
		await _test_fire()
	_finish()


func _test_host() -> void:
	print("A survival world with a settlement")
	check(Survival.server_new_world(main, "test_nature" + tag, 4242), "a new world hosts")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 20.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	if player == null:
		check(false, "the host's survivor is in")
		return
	for i in 120:
		await get_tree().process_frame
	Survival._pop = -1000.0
	Seasons.force_frost = 0
	_clear_dead()
	b = Builder.find(level)
	st = Settlement.find(level)
	nat = Nature.of(level)
	check(b != null and st != null and nat != null, "the zone has its Builder, Settlement and Nature")
	if b == null or st == null or nat == null:
		return
	await _wait_for(func() -> bool: return Wildlife.zone_id != "", 10.0)
	check(Wildlife.animals.size() > 0 and Wildlife.alive_count("deer") > 0,
		"the zone's animals laid out (%d: %d deer, %d birds)" % [Wildlife.animals.size(), Wildlife.alive_count("deer"), Wildlife.alive_count("bird")])
	var near := Wildlife.animals.filter(func(a: Dictionary) -> bool: return (a.pos as Vector2).distance_to(Vector2(player.global_position.x, player.global_position.z)) < Wildlife.KEEP_M - Wildlife.HOME_R)
	check(near.is_empty(), "none laid out on top of the survivor (%d within %.0f m)" % [near.size(), Wildlife.KEEP_M - Wildlife.HOME_R])
	nat.set_process(false)  # (the test drives the nature itself)
	st.set_process(false)
	var sieges := Sieges.of(level)
	if sieges:
		sieges.set_process(false)
	player.inventory.put_on(&"backpack", &"pack_ruck_60")
	var found := false
	var start := player.global_position
	for ring: float in [8.0, 12.0, 16.0, 22.0, 30.0, 38.0, 46.0, 56.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var x := start.x + cos(a) * ring
			var z := start.z + sin(a) * ring
			if _flat_and_clear(x, z):
				origin = Builder.ground_cell(Vector3(x, level.ground_height(x, z), z))
				found = true
				break
		if found:
			break
	check(found, "a patch of flat open ground (%s)" % origin)
	var home := BuildPieces.cell_centre(_at(0, 0))
	Settlement.server_found(String(Survival.state().zone), Vector3(home.x, level.ground_height(home.x, home.z), home.z))
	check(Settlement.exists() and st.hosted(), "the settlement founded there")
	_stand_by(_at(0, -6))
	await _frames(5)


# --- Wildlife ------------------------------------------------------------------------------------------

func _test_flee() -> void:
	print("Deer flee a shot; a running herd is a tell")
	Wildlife.forget()
	Wildlife.zone_id = Nature.zone()
	var me := player.global_position
	# (A spot 60 m out with nobody else near: the settlement's people and the zone's dead are
	# real threats a deer runs from, and Surv_p3 stood 40 m from the old fixed spot.)
	var off := _clear_spot(me, 60.0, 50.0, 35.0)
	var deer := Wildlife.add(level, "deer", me + off, {"herd": 900})
	var doe := Wildlife.add(level, "deer", me + off + off.normalized().rotated(Vector3.UP, 0.6) * 3.6, {"herd": 900})
	Wildlife.server_tick(level, 0.25)
	check(String(deer.state) != "flee", "a deer 60 m off grazes on (%s)" % deer.state)
	var d0 := (deer.pos as Vector2).distance_to(Vector2(me.x, me.z))
	Wildlife.last_tell = {}
	Survival.server_noise(player, me, ZombieAI.SHOT_HEARD_M, ZombieAI.HEAR_SHOT)
	check(String(deer.state) == "flee" and String(doe.state) == "flee", "the shot: the herd runs (%s, %s)" % [deer.state, doe.state])
	for i in 8:
		Wildlife.server_tick(level, 0.25)
	var d1 := (deer.pos as Vector2).distance_to(Vector2(me.x, me.z))
	check(d1 > d0 + 10.0, "away from the shot (%.0f m -> %.0f m)" % [d0, d1])
	check(not Wildlife.last_tell.is_empty() and String(Wildlife.last_tell.get("line", "")).contains("Deer"), "a running herd is a tell: %s" % Wildlife.last_tell.get("line", "-"))
	# The living close spook prey too; a sneaking man gets closer.
	var rabbit := Wildlife.add(level, "rabbit", me + Vector3(10, 0, 0))
	Wildlife.server_tick(level, 0.25)
	check(String(rabbit.state) == "flee", "a rabbit 10 m from a standing man bolts")


func _test_dead_hunt() -> void:
	print("The dead chase an animal and bite it down")
	Wildlife.forget()
	Wildlife.zone_id = Nature.zone()
	_stand_by(_at(0, -6))
	var at := player.global_position + Vector3(0, 0, 70)
	var z := _zombie(at)
	await _frames(3)
	var brain := ZombieAI.of(z)
	check(brain != null, "one of the dead, 70 m from the survivor")
	if brain == null:
		return
	var deer := Wildlife.add(level, "deer", z.global_position + Vector3(12, 0, 0))
	var what := Wildlife.zombie_hunt(brain)
	check(what == "prey" and brain.mode == ZombieAI.Mode.INVESTIGATE and brain.goal.distance_to(Vector3((deer.pos as Vector2).x, brain.goal.y, (deer.pos as Vector2).y)) < 2.0,
		"it goes after the deer it sees (%s, %s)" % [what, brain.state_name()])
	var lamb := Wildlife.add(level, "rabbit", z.global_position + Vector3(0.8, 0, 0))
	Wildlife.zombie_hunt(brain)
	check(not bool(lamb.alive) and String(lamb.get("cause", "")) == "the dead", "in reach, it bites one down (%s)" % lamb.get("cause", "-"))
	Wildlife.server_tick(level, 0.25)
	check(String(deer.state) == "flee", "and the deer runs from the dead")
	z.queue_free()
	await _frames(2)


func _test_smell() -> void:
	print("A carcass is a smell source")
	Wildlife.forget()
	Wildlife.zone_id = Nature.zone()
	var at := player.global_position + Vector3(0, 0, 70)
	var carcass := Wildlife.add(level, "deer", at, {"alive": false, "cause": "shot"})
	var src := Wildlife.smell_sources()
	check(src.size() == 1 and String(src[0].what) == "carcass:deer" and float(src[0].strength) > 0.9, "a fresh carcass smells (%s)" % [src])
	var z := _zombie(at + Vector3(5, 0, 0))
	await _frames(2)
	var brain: ZombieAI = ZombieAI.of(z) if is_instance_valid(z) else null
	if brain:
		brain.mode = ZombieAI.Mode.IDLE
		var what := Wildlife.zombie_hunt(brain)
		check(what == "smell" and brain.mode == ZombieAI.Mode.INVESTIGATE, "the dead walk to it (%s)" % what)
	carcass.dead_h = Moods.now_h() - Wildlife.CARCASS_H - 1.0
	check(Wildlife.smell_sources().is_empty(), "an old carcass doesn't")
	if is_instance_valid(z):
		z.queue_free()


func _test_snare_and_butcher() -> void:
	print("A snare catches a rabbit over the hours; butchering gives meat")
	Wildlife.forget()
	Wildlife.zone_id = Nature.zone()
	Wildlife.snares().clear()
	player.inventory.take(&"snare", 1)
	check(Wildlife.server_set_snare(player) == "" and Wildlife.snares().size() == 1, "a snare set")
	Wildlife.force_roll = 0.3
	check(Wildlife.server_snare_hours(level, 1.0) == 0, "nothing in it after an hour")
	check(Wildlife.server_snare_hours(level, 12.0) == 1, "a rabbit in it after a night")
	check(Wildlife.server_check_snare(player) == "rabbit", "checked: a rabbit")
	Wildlife.force_roll = -1.0
	var rabbit := Wildlife.carcass_near(player.global_position, 3.0)
	check(not rabbit.is_empty() and String(rabbit.sp) == "rabbit", "it lies in the snare")
	var meat0 := player.inventory.count_of(&"raw_meat")
	var deer := Wildlife.add(level, "deer", player.global_position + Vector3(1, 0, 0), {"alive": false})
	var why := Wildlife.server_butcher(player, deer)
	check(why == "" and player.inventory.count_of(&"raw_meat") == meat0 + 4 and player.inventory.count_of(&"hide") >= 1,
		"a deer butchered: %d raw meat, a hide (%s)" % [player.inventory.count_of(&"raw_meat") - meat0, why])
	check(Wildlife.smell_sources().any(func(s: Dictionary) -> bool: return String(s.what) == "blood"), "its blood smells")
	check(Wildlife.server_butcher(player, deer) != "", "nothing more on it")


func _test_fishing() -> void:
	print("Fishing yields by season")
	check(Migration.fish_rate("river", "summer") > Migration.fish_rate("river", "winter") and Migration.fish_rate("coast", "summer") > 0.0,
		"a river's fish: summer %.1f, winter %.1f an hour" % [Migration.fish_rate("river", "summer"), Migration.fish_rate("river", "winter")])
	check(Migration.server_fish(player, 4.0, "river") == -1, "no rod, no fish")
	player.inventory.take(&"fishing_rod", 1)
	_set_season("summer", 15)
	player.set_meta(&"fish_acc", 0.0)
	var fish0 := player.inventory.count_of(&"raw_fish")
	var summer := Migration.server_fish(player, 6.0, "river")
	_set_season("winter", 35)
	player.set_meta(&"fish_acc", 0.0)
	var winter := Migration.server_fish(player, 6.0, "river")
	check(summer > winter and player.inventory.count_of(&"raw_fish") + _dropped(&"raw_fish") >= fish0 + summer + winter,
		"six hours on a river: %d fish in summer, %d in winter" % [summer, winter])
	var raw := ItemDB.get_item(&"raw_fish")
	var smoked := ItemDB.get_item(&"smoked_fish")
	check(raw != null and smoked != null and float(raw.stats.spoils_days) < float(smoked.stats.spoils_days) and float(raw.stats.spoils_days) <= 1.0
		and Crafting.recipe("smoked_fish").size() > 0, "raw fish spoils in a day, smoked it keeps")
	_set_season("spring", 1)


func _test_migration() -> void:
	print("Winter moves the deer to the valleys and empties the birds")
	_set_season("summer", 15)
	Wildlife.server_populate(level)
	var summer_birds := Wildlife.alive_count("bird")
	var summer_h := _mean_home_h("deer")
	_set_season("winter", 35)
	Wildlife.server_populate(level)
	var winter_h := _mean_home_h("deer")
	check(summer_birds > 0 and Wildlife.alive_count("bird") == 0, "birds: %d in summer, none in winter" % summer_birds)
	check(Migration.where("deer", "winter") == "valleys" and winter_h <= summer_h + 0.5, "deer winter in the valleys (homes at %.1f m in winter, %.1f m in summer)" % [winter_h, summer_h])
	check(Wildlife.alive_count("bear") == 0, "the bear is denned up")
	Rpg.set_level(player, "fieldcraft", 1)
	check(Wildlife.calendar(player).has("note"), "a novice doesn't know the game's calendar")
	Rpg.set_level(player, "fieldcraft", 4)
	var cal := Wildlife.calendar(player)
	check(String((cal.get("winter", {}) as Dictionary).get("deer", "")) == "valleys" and cal.has("fish"), "fieldcraft 4 reads the hunter's calendar, fish too")
	Rpg.set_level(player, "fieldcraft", 0)
	_set_season("spring", 1)
	Wildlife.forget()
	Wildlife.zone_id = Nature.zone()


func _mean_home_h(sp: String) -> float:
	var sum := 0.0
	var n := 0
	for a: Dictionary in Wildlife.animals:
		if String(a.sp) == sp:
			var h: Vector2 = a.home
			sum += level.ground_height(h.x, h.y)
			n += 1
	return sum / maxf(n, 1.0)


func _test_crows() -> void:
	print("Crows mark a body")
	Wildlife.forget()
	Wildlife.zone_id = Nature.zone()
	check(ScavengersFauna.crow_sites(level).is_empty(), "no bodies, no crows")
	var at := player.global_position + Vector3(30, 0, 30)
	Wildlife.add(level, "deer", at, {"alive": false})
	var sites := ScavengersFauna.crow_sites(level)
	check(sites.size() == 1 and (sites[0].pos as Vector3).distance_to(level.ground_point(at)) < 2.0 and int(sites[0].n) >= ScavengersFauna.CROW_PER_BODY,
		"crows circle over a fresh kill (%s)" % [sites])
	var z := _zombie(player.global_position + Vector3(-40, 0, 0))
	await _frames(2)
	z.vitals.server_kill()
	await _frames(2)
	check(ScavengersFauna.crow_sites(level).size() == 2 and ScavengersFauna.packed_crows(level).size() == 8, "and over one of the dead put down")


func _test_flies_rats() -> void:
	print("Flies and rats cost the settlement; a cat halves the rats")
	for id: String in ScavengersFauna._food_ids():
		Settlement.server_take(id, Settlement.count(id))
	st.server_put("canned_meat", 50)
	ScavengersFauna.force_roll = 0.99
	var lost := ScavengersFauna.server_rats_night(level)
	check(lost >= 2 and Settlement.count("canned_meat") == 50 - lost, "a night of rats in open stores: %d tins gone" % lost)
	st.server_put("canned_meat", lost)
	ScavengersFauna.server_found_cat()
	var with_cat := ScavengersFauna.server_rats_night(level)
	check(ScavengersFauna.has_cat() and with_cat < lost and with_cat >= 1 and absi(with_cat * 2 - lost) <= 1, "with a cat: %d (was %d)" % [with_cat, lost])
	Settlement.data()["stores_closed"] = true
	check(ScavengersFauna.server_rats_night(level) == 0, "closed stores: nothing")
	Settlement.data().erase("stores_closed")
	var losses: Array = Settlement.data().get("nature_losses", [])
	check(losses.size() >= 2 and String((losses[0] as Dictionary).what) == "rats", "the losses on the settlement's record")
	# Flies on the unburied.
	var rec := _settler()
	var z := _zombie(Settlement.pos() + Vector3(6, 0, 0))
	z.vitals.server_kill()
	z.set_meta(&"down_h", Moods.now_h() - ScavengersFauna.FLY_FROM_H - 2.0)
	var f := ScavengersFauna.flies_at(level, Settlement.pos(), Settlement.radius())
	var p0 := Survival.pressure(level)
	ScavengersFauna.force_roll = 0.0
	ScavengersFauna.server_flies_hour(level)
	ScavengersFauna.force_roll = -1.0
	check(f > 0.0 and Survival.pressure(level) > p0 and String(((rec.get("needs", {}) as Dictionary).get("sick", {}) as Dictionary).get("id", "")) == "dysentery",
		"flies thicken on the unburied (%.2f): the smell carries and a settler sickens" % f)
	z.queue_free()


func _test_infected() -> void:
	print("An infected dog is fast, low and quiet")
	Wildlife.forget()
	Wildlife.zone_id = Nature.zone()
	check(InfectedAnimals.speed("feral_dog") > InfectedAnimals.MAN_SPRINT_MPS and InfectedAnimals.heard_m("feral_dog") < float(Survival.STEP_M.walk),
		"it runs %.1f m/s (a man sprints %.0f), heard %.0f m off (a walking man %.0f)" % [InfectedAnimals.speed("feral_dog"), InfectedAnimals.MAN_SPRINT_MPS, InfectedAnimals.heard_m("feral_dog"), float(Survival.STEP_M.walk)])
	# (It hunts the nearest of the living, and the survivors walk with him: he steps 80 m out into
	# the open for this, away from them, and the dog starts 20 m off, inside its sight by night
	# too (NIGHT_SEE_M 25). R2864: at his side it went for Surv_p3.)
	var back := player.global_position
	player.global_position = level.ground_point(player.global_position + _clear_spot(player.global_position, 80.0, 45.0, 0.0)) + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	var me := Vector2(player.global_position.x, player.global_position.z)
	var dog := Wildlife.add(level, "feral_dog", player.global_position + Vector3(20, 0, 0), {"infected": true})
	var plain := Wildlife.add(level, "feral_dog", player.global_position + Vector3(140, 0, 0))
	check(bool(dog.infected) and Wildlife.size_of(dog).y < Wildlife.size_of(plain).y and Wildlife.size_of(dog).y <= 0.5, "low: %.2f m high (a feral dog %.2f)" % [Wildlife.size_of(dog).y, Wildlife.size_of(plain).y])
	var d0 := (dog.pos as Vector2).distance_to(me)
	for i in 4:
		Wildlife.server_tick(level, 0.25)
	var d1 := (dog.pos as Vector2).distance_to(me)
	check(String(dog.state) == "hunt" and d0 - d1 > InfectedAnimals.MAN_SPRINT_MPS, "it runs him down: %.0f m closer in a second (%s)" % [d0 - d1, dog.state])
	player.global_position = back
	check(not InfectedAnimals.can_turn("deer") and not InfectedAnimals.turn(Wildlife.add(level, "deer", player.global_position + Vector3(200, 0, 0))), "a deer doesn't turn")
	Wildlife.forget()
	Wildlife.zone_id = Nature.zone()


# --- Flora ------------------------------------------------------------------------------------------------

func _test_regrowth() -> void:
	print("Regrowth rises with the day; the settlement's paths stay clear")
	check(Flora.regrowth(1) < Flora.regrowth(60) and Flora.regrowth(60) < Flora.regrowth(300) and Flora.regrowth(300) <= 1.0,
		"overgrown: day 1 %.2f, 60 %.2f, 300 %.2f" % [Flora.regrowth(1), Flora.regrowth(60), Flora.regrowth(300)])
	Survival.state()["day"] = 90
	Flora.server_apply(level)
	var sc := level.scatter
	check(Flora.grass_now > 1.2 and Flora.road_now > 0.2 and sc._regrown(100) > 120, "day 90: grass x%.2f, %.0f%% of the roads growing over" % [Flora.grass_now, Flora.road_now * 100.0])
	var home := Settlement.pos()
	check(Flora.path_clear(home.x, home.z) and not Flora.path_clear(home.x + Settlement.radius() + 20.0, home.z), "the settlement's ground stays clear, past it doesn't")
	Survival.state()["day"] = 1
	Flora.server_apply(level)
	check(is_equal_approx(Flora.grass_now, Flora.grass_x(1)) and Flora.grass_now < 1.02, "a new world's grass is as it was")


func _test_forage() -> void:
	print("Berries in summer, mushrooms in autumn; a death cap poisons a novice")
	var home := player.global_position
	_set_season("summer", 15)
	var berries := _spot("berries")
	check(berries >= 0, "a berry bush in the zone")
	if berries >= 0:
		var n0 := player.inventory.count_of(&"wild_berries")
		_at_spot(berries)
		var why := Foraging.server_forage(player, berries)
		check(why == "" and player.inventory.count_of(&"wild_berries") > n0, "summer: berries picked (%s)" % why)
		check(Foraging.server_forage(player, berries) != "", "and not again the same day")
	var mush := _spot("mushrooms")
	if mush >= 0:
		_at_spot(mush)
		check(Foraging.server_forage(player, mush) == "Not the season for it", "no mushrooms in summer")
	_set_season("autumn", 25)
	if mush >= 0:
		var m0 := player.inventory.count_of(&"wild_mushrooms")
		_at_spot(mush)
		check(Foraging.server_forage(player, mush) == "" and player.inventory.count_of(&"wild_mushrooms") > m0, "autumn: mushrooms")
	if berries >= 0:
		_at_spot(berries)
		check(Foraging.server_forage(player, berries) == "Not the season for it", "no berries in autumn")
	var cap := _spot("death_cap")
	check(cap >= 0, "a death cap in the zone")
	if cap >= 0:
		Rpg.set_level(player, "fieldcraft", 0)
		while player.inventory.count_of(&"field_guide") > 0:
			player.inventory.remove_one(&"field_guide")
		_at_spot(cap)
		var m1 := player.inventory.count_of(&"wild_mushrooms")
		check(Foraging.server_forage(player, cap) == "" and player.inventory.count_of(&"wild_mushrooms") > m1 and player.inventory.count_of(&"death_cap") == 0,
			"a novice picks a death cap as a good mushroom")
		var n := Survival.needs_of(player)
		n["sick"] = {}
		n.erase("poison")
		Survival.server_eat(player, ItemDB.get_item(&"wild_mushrooms"), {"poison": "death_cap"}, &"ration", 0.25)
		n = Survival.needs_of(player)
		check(String((n.get("poison", {}) as Dictionary).get("id", "")) == "death_cap" and String((n.get("sick", {}) as Dictionary).get("id", "")) == "food_poisoning",
			"eaten, it poisons him (%s)" % [n.get("poison", {})])
		n["sick"] = {}
		n.erase("poison")
		Survival.state()["day"] = 30
		Rpg.set_level(player, "fieldcraft", 4)
		_at_spot(cap)
		var c0 := player.inventory.count_of(&"death_cap")
		check(Foraging.server_forage(player, cap) == "" and player.inventory.count_of(&"death_cap") > c0, "at fieldcraft 4 he tells it apart: a Death Cap")
		Rpg.set_level(player, "fieldcraft", 2)
		check(not Foraging.tells(player, "death_cap"), "fieldcraft 2 alone can't")
		player.inventory.take(&"field_guide", 1)
		check(Foraging.tells(player, "death_cap"), "with a field guide it can")
		player.inventory.remove_one(&"field_guide")
		Rpg.set_level(player, "fieldcraft", 0)
	player.global_position = home
	_set_season("spring", 1)


## The first scatter spot with `plant`, nearest the settlement (-1 none).
func _spot(plant: String) -> int:
	var best := -1
	var best_d := INF
	var home := Settlement.pos()
	for i in level.scatter.items.size():
		var item: Dictionary = level.scatter.items[i]
		if Foraging.plant_of(item) != plant:
			continue
		var d := (item.pos as Vector3).distance_to(home)
		if d < best_d:
			best_d = d
			best = i
	return best


func _at_spot(index: int) -> void:
	var p: Vector3 = level.scatter.items[index].pos
	player.global_position = level.ground_point(p + Vector3(1.0, 0, 0)) + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO


func _test_trees() -> void:
	print("Felling: an oak takes longer than a pine, makes noise, yields planks, leaves a stump, regrows")
	var home := player.global_position
	check(Trees.fell_s("oak") > Trees.fell_s("pine"), "an oak %.0f s with an axe, a pine %.0f s" % [Trees.fell_s("oak"), Trees.fell_s("pine")])
	for id: StringName in [&"wild_berries", &"wild_mushrooms", &"death_cap", &"raw_meat", &"hide", &"raw_fish", &"fishing_rod", &"snare"]:
		while player.inventory.remove_one(id):
			pass
	player.inventory.release_hands()
	player.inventory.take(&"axe", 1)
	check(Wildlife.carries(player, "axe"), "a felling axe in hand")
	var oak := _tree_of("oak", true)
	var pine := _tree_of("pine")
	check(oak >= 0, "an oak in the zone")
	if oak < 0:
		return
	var p0 := Survival.pressure(level)
	var planks0 := player.inventory.count_of(&"planks")
	var oak_s := _fell(oak)
	check(oak_s >= Trees.fell_s("oak") - 0.1 and Trees.is_felled(oak) and level.scatter.items[oak].has("felled"), "the oak down in %.0f s: a stump" % oak_s)
	check(Survival.pressure(level) > p0, "the chopping is heard (pressure %.1f -> %.1f)" % [p0, Survival.pressure(level)])
	check(player.inventory.count_of(&"planks") + _dropped(&"planks") > planks0 and player.inventory.count_of(&"firewood") + _dropped(&"firewood") > 0, "planks and firewood from it")
	check(level.scatter.visual_parts(level.scatter.items[oak]).size() == 1, "drawn as a stump")
	if pine >= 0:
		var pine_s := _fell(pine)
		check(pine_s < oak_s, "a pine falls quicker (%.0f s)" % pine_s)
	var fw := {"cut_day": Survival.day()}
	check(not Trees.seasoned(fw), "green firewood isn't seasoned")
	Survival.state()["day"] = Survival.day() + Trees.SEASON_DAYS
	check(Trees.seasoned(fw), "after %d days it is" % Trees.SEASON_DAYS)
	Survival.state()["day"] = Survival.day() + Trees.REGROW_DAYS
	check(Trees.server_regrow(level) >= 1 and not Trees.is_felled(oak) and not level.scatter.items[oak].has("felled"), "two seasons on, the wood has grown back")
	# The settlement's cut wood fells the trees near it.
	var before := Trees.felled_list().size()
	if Trees.nearest(level, Settlement.pos(), Settlement.radius() * Trees.SETTLE_REACH_X) >= 0:
		Trees.settlement_cut(st, 3)
		check(Trees.felled_list().size() > before and Settlement.count("firewood") > 0, "the settlers' cut wood fells a tree near the settlement (firewood %d)" % Settlement.count("firewood"))
	else:
		print("    (no tree within reach of the settlement: the woodpile stub)")
	player.global_position = home
	Survival.state()["day"] = 1


## The nearest standing tree of `sp` to the settlement; `loud`: one outside the home's quiet
## (FirstHour.in_quiet: noise there draws nothing, by the first hour's design) when there is one.
func _tree_of(sp: String, loud := false) -> int:
	if loud:
		var open := _tree_of_where(sp, func(at: Vector3) -> bool: return not FirstHour.in_quiet(at))
		if open >= 0:
			return open
	return _tree_of_where(sp, func(_at: Vector3) -> bool: return true)


func _tree_of_where(sp: String, ok: Callable) -> int:
	var best := -1
	var best_d := INF
	var home := Settlement.pos()
	for i in level.scatter.items.size():
		var item: Dictionary = level.scatter.items[i]
		if int(item.kind) != ZoneScatter.Kind.TREE or item.has("felled") or Trees.species_of(item) != sp or not ok.call(item.pos as Vector3):
			continue
		var d := (item.pos as Vector3).distance_to(home)
		if d < best_d:
			best_d = d
			best = i
	return best


## An offset `dist` from `from` (around the compass) with no one living but the player within
## `living_m` of it and none of the dead within `dead_m`; the first tried if none is clear.
func _clear_spot(from: Vector3, dist: float, living_m: float, dead_m: float) -> Vector3:
	var ctx := Wildlife.context(level)
	for k in 16:
		var off := Vector3(dist, 0, 0).rotated(Vector3.UP, TAU * k / 16.0)
		var at := Vector2(from.x + off.x, from.z + off.z)
		var crowded := false
		for row: Dictionary in ctx.living:
			if row.s != player and (row.p as Vector2).distance_to(at) <= living_m:
				crowded = true
				break
		if not crowded and (dead_m <= 0.0 or Wildlife.nearest_dead(ctx, at, dead_m) == Vector2.INF):
			return off
	return Vector3(dist, 0, 0)


func _fell(index: int) -> float:
	_at_spot(index)
	var secs := 0.0
	for i in 200:
		var r := Trees.server_fell(player, index, 5.0)
		secs += 5.0
		if String(r.get("why", "")) != "":
			print("    (%s)" % r.why)
			return -1.0
		if bool(r.done):
			return secs
	return secs


func _dropped(id: StringName) -> int:
	var n := 0
	for d: Dictionary in GameState.dropped.values():
		if String(d.get("id", "")) == String(id):
			n += int(d.get("count", 0))
	return n


func _test_fire() -> void:
	print("Wildfire: downwind through dry grass, stopped by a firebreak and the rain; wood burns; the dead burn walking")
	Wildfire.forget()
	Wildfire.force_dry = 1.0
	Wildfire.force_wind = Vector3(6, 0, 0)
	_set_season("summer", 15)
	var c0 := Vector2i.ZERO
	var ok := false
	for k in 40:
		var a := TAU * k / 40.0
		var p := player.global_position + Vector3(cos(a), 0, sin(a)) * (60.0 + k * 3.0)
		c0 = Wildfire.cell_of(p)
		ok = true
		for dx in range(-3, 7):
			for dz in range(-3, 4):
				if Wildfire.fuel_at(level, c0 + Vector2i(dx, dz)) <= 0.0:
					ok = false
		if ok:
			break
	check(ok, "dry grass round %s" % c0)
	for dz in range(-25, 26):
		Wildfire.server_clear(c0 + Vector2i(5, dz))
	var p0 := Survival.pressure(level)
	var mid := Wildfire.centre_of(c0)
	check(Wildfire.server_ignite(level, Vector3(mid.x, 0, mid.y), "test"), "lit")
	for i in 30:
		Wildfire.server_tick(level, 1.0)
	var east := 0
	var west := 0
	var past := 0
	for c: Vector2i in Wildfire.cells:
		if c.x > c0.x and c.x < c0.x + 5:
			east += 1
		elif c.x < c0.x:
			west += 1
		if c.x > c0.x + 5:
			past += 1
	check(east >= 4 and east > west * 2, "it runs downwind: %d cells east, %d west" % [east, west])
	check(past == 0 and not Wildfire.cells.has(c0 + Vector2i(5, 0)), "the firebreak holds (%d past it)" % past)
	check(Survival.pressure(level) > p0, "the smoke draws the dead (pressure %.1f -> %.1f)" % [p0, Survival.pressure(level)])
	# The rain.
	Wildfire.force_dry = -1.0
	Seasons.server_set_weather("rain")
	check(Wildfire.dryness() == 0.0, "rain: nothing's dry")
	Wildfire.server_tick(level, 1.0)
	check(Wildfire.burning_count() == 0, "and the fire's out")
	Seasons.server_set_weather("clear")
	# A wood block in the fire.
	Wildfire.forget()
	Wildfire.force_dry = 1.0
	var cb := _at(3, 3)
	var why := _block(cb, "wood")
	check(why == "" and b.is_built(cb), "a wood block (%s)" % why)
	if b.is_built(cb):
		player.global_position += Vector3(0, 0, -30)
		var bp := BuildPieces.cell_centre(cb)
		Wildfire.cells[Wildfire.cell_of(bp)] = {"s": "burning", "t": 0.0}
		for i in 6:
			Wildfire.server_tick(level, 1.0)
		var hp := float((b.blocks.get(cb, {}) as Dictionary).get("hp", 0.0))
		check(hp < 0.9, "it burns (hp %.2f)" % hp)
	Wildfire.forget()
	# A burning one of the dead keeps walking.
	_stand_by(_at(0, -6))
	var z := _zombie(player.global_position + Vector3(0, 0, 60))
	await _frames(3)
	var brain := ZombieAI.of(z)
	if brain:
		brain.hear(z.global_position + Vector3(20, 0, 0), ZombieAI.HEAR_RUN)
		Wildfire.set_alight(z)
		var pool0 := z.vitals.undead_pool
		await _frames(20)
		Wildfire.burn_step(z, 2.0)
		check(Wildfire.alight(z) and z.vitals.is_up() and z.vitals.undead_pool < pool0 and brain.mode in [ZombieAI.Mode.INVESTIGATE, ZombieAI.Mode.SEARCH]
			and (z.move_input.length() > 0.0 or brain.mode == ZombieAI.Mode.SEARCH), "alight, it keeps walking (%s, pool %.1f -> %.1f)" % [brain.state_name(), pool0, z.vitals.undead_pool])
		Wildfire.burn_step(z, 100.0)
		check(not z.vitals.is_up(), "and burns down in the end")
	Wildfire.force_wind = Vector3.INF
	Wildfire.force_dry = -1.0
	_set_season("spring", 1)


# --- Helpers -------------------------------------------------------------------------------------------------

func _settler() -> Dictionary:
	_n += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 700 + _n
	var rec := SurvivorPerson.make(rng, "p_nature_%d" % _n, {})
	SurvivorsLayer.records()[String(rec.id)] = rec
	Settlement.server_make_settler(rec)
	rec["jobs"] = ["guard"]
	return rec


## The season `s` on world day `day` of a world woken in spring (summer 11-20, autumn 21-30, winter 31-40).
func _set_season(s: String, day := 1) -> void:
	Survival.server_set_options({"season": "spring"})
	Survival.state()["day"] = day
	if Seasons.current() != s:
		print("    (day %d is %s, not %s)" % [day, Seasons.current(), s])


func _flat_and_clear(x: float, z: float) -> bool:
	var lo := INF
	var hi := -INF
	for dx in range(-10, 11, 2):
		for dz in range(-10, 11, 2):
			var h := level.ground_height(x + dx * 0.5, z + dz * 0.5)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			for up in [0.3, 1.2, 2.2]:
				if b._structure_at(Vector3(x + dx * 0.5, h + up, z + dz * 0.5)):
					return false
	return hi - lo < 0.5


func _at(dx: int, dz: int) -> Vector3i:
	var p := BuildPieces.cell_centre(origin + Vector3i(dx, 0, dz))
	return Builder.ground_cell(Vector3(p.x, level.ground_height(p.x, p.z), p.z))


func _pos(c: Vector3i) -> Vector3:
	var p := BuildPieces.cell_centre(c)
	return Vector3(p.x, level.ground_height(p.x, p.z) + 0.05, p.z)


func _stand_by(c: Vector3i) -> void:
	player.global_position = _pos(c) + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO


func _clear_dead() -> void:
	for z: Soldier in Survival.zombies(level):
		z.queue_free()
	var crowd := ZoneDead.of(level)
	if crowd:
		crowd.dead.clear()


func _zombie(at: Vector3, kind := "walker") -> Soldier:
	return Survival.server_spawn_zombie(level, level.ground_point(at), kind)


func _give(pairs: Array) -> void:
	for pair: Array in pairs:
		player.inventory.take(StringName(pair[0]), int(pair[1]))


func _block(c: Vector3i, mat: String) -> String:
	var m: Dictionary = BuildPieces.MATERIALS[mat]
	_give([[BuildPieces.TOOLS[String(m.tool)][0], 1]] + BuildPieces.block_cost(mat, "block"))
	_stand_by(c + Vector3i(0, 0, -3) - Vector3i(0, c.y - _at(c.x - origin.x, c.z - origin.z).y, 0))
	var why := b.server_build_now(player, c, mat)
	return why


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


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
	Wildlife.force_roll = -1.0
	ScavengersFauna.force_roll = -1.0
	Wildfire.force_wind = Vector3.INF
	Wildfire.force_dry = -1.0
	Wildfire.forget()
	Wildlife.forget()
	Flora.reset()
	if Survival.world != "":
		GameState.delete_save()
		Survival.running = false
		Campaign.reset_campaign()
	print("NATURE TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
