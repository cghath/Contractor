extends Node
## Phase D of Contractor: Fallen's world (docs/survival_seasons.md; calls 28, 30, 34, 53, 55, 59, 60,
## 113, 137, 140): in a hosted survival world with a settlement on flat ground: the season from the
## clock and the New world option; winter stops the crops and slows the dead; a hard frost freezes
## the crowd's heads and the live dead solid (a hit shatters one); the thaw wakes them as a horde
## and the far zones that froze get theirs; summer's flags and a wildfire; a farm planted in the
## window harvests and one that missed it doesn't, and a winter eats the stocks down; autumn biases
## raiders' raids in the goal scoring; a live raid spawns its attackers, blows a wood wall and takes
## the stores when lost; at a wall the dead chew wood and not steel, pile into a ramp and climb,
## runners vault waist-high, crawlers squeeze through a gap, gates take a push; a horde siege's waves
## walk at the settlement and the dawn ends it; a solar panel powers a lamp and the footprint
## grows; a powered electric fence stuns one of the dead; a blown bridge closes the crossing in the
## world sim; a spike pit kills, wire holds; a thrown bottle draws the dead; gore masks the smell and
## the pyre burns the bodies; the pious vote together and share their moods; a hungry gloomy settler
## steals; a low faction with a leader splits off as a world group; the leader challenge lost passes
## the settlement on; an alliance, protection and a feud with other settlements. Ticks driven directly.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier
var b: Builder
var st: Settlement
var layer: SurvivorsLayer
var sieges: Sieges
var origin := Vector3i.ZERO
var _n := 0


func _ready() -> void:
	get_tree().create_timer(390.0).timeout.connect(func() -> void:
		print("SEASONS TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _test_host()
	if b != null and player != null and st != null and sieges != null:
		await _test_calendar()
		await _test_winter()
		await _test_frozen()
		await _test_thaw()
		_test_summer()
		_test_harvest()
		_test_autumn_bias()
		await _test_raid()
		await _test_walls()
		await _test_siege()
		await _test_power()
		await _test_fence()
		_test_bridge()
		await _test_traps()
		await _test_lure()
		await _test_masking()
		await _test_politics()
	_finish()


func _test_host() -> void:
	print("A survival world with a settlement")
	check(Survival.server_new_world(main, "test_seasons" + tag, 8642), "a new world hosts")
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
	Survival._pop = -1000.0  # (no dead spawned round us: the tests place their own)
	Seasons.force_frost = 0
	_clear_dead()
	b = Builder.find(level)
	st = Settlement.find(level)
	layer = SurvivorsLayer.find(level)
	sieges = Sieges.of(level)
	check(b != null and st != null and layer != null and sieges != null, "the zone has its Builder, Settlement, Survivors and Sieges on the host")
	if st == null or b == null or layer == null or sieges == null:
		return
	st.set_process(false)  # (the test drives the settlement's hours itself)
	sieges.set_process(false)  # (and the sieges, traps and lures)
	await _wait_for(func() -> bool: return layer._started, 30.0)
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
	await _frames(10)


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
	var z := Survival.server_spawn_zombie(level, level.ground_point(at), kind)
	return z


func _give(pairs: Array) -> void:
	for pair: Array in pairs:
		player.inventory.take(StringName(pair[0]), int(pair[1]))


## Lays and builds a block at `c` of `mat`, its tool and materials given first, standing by it.
func _block(c: Vector3i, mat: String) -> String:
	var m: Dictionary = BuildPieces.MATERIALS[mat]
	_give([[BuildPieces.TOOLS[String(m.tool)][0], 1]] + BuildPieces.block_cost(mat, "block"))
	_stand_by(c + Vector3i(0, 0, -3) - Vector3i(0, c.y - _at(c.x - origin.x, c.z - origin.z).y, 0))
	var why := b.server_build_now(player, c, mat)
	if why != "":
		print("    (%s at %s: %s)" % [mat, c, why])
	return why


## Builds a piece of `kind` at `c` (its tool and cost given first). Returns its id (-1 none).
func _piece(kind: String, c: Vector3i) -> int:
	var def: Dictionary = BuildPieces.PIECES[kind]
	_give([[BuildPieces.TOOLS[String(def.tool)][0], 1]] + (def.cost as Array))
	_stand_by(c + Vector3i(0, 0, -3))
	var id := b.server_build_piece_now(player, kind, c, 0)
	if id <= 0:
		print("    (%s at %s: %s)" % [kind, c, b.last_problem])
	return id


func _set_season(s: String, day := 1) -> void:
	Survival.server_set_options({"season": s})
	Survival.state()["day"] = day


func _settler(opts: Dictionary) -> Dictionary:
	_n += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + _n
	var rec := SurvivorPerson.make(rng, "p_season_%d" % _n, opts)
	SurvivorsLayer.records()[String(rec.id)] = rec
	Settlement.server_make_settler(rec)
	rec["jobs"] = ["guard"]
	return rec


func _test_calendar() -> void:
	print("The season from the clock and the option")
	check(Survival.season() == "spring" and Survival.option("season") == "spring", "a new world wakes in spring by default (%s)" % Survival.season())
	check(Seasons.of_day(10) == "spring" and Seasons.of_day(11) == "summer" and Seasons.of_day(31) == "winter" and Seasons.of_day(41) == "spring",
		"four seasons of %d world days: day 11 %s, 31 %s, 41 %s" % [Seasons.SEASON_DAYS, Seasons.of_day(11), Seasons.of_day(31), Seasons.of_day(41)])
	_set_season("winter")
	check(Survival.season() == "winter" and Seasons.of_day(11, "winter") == "spring", "woken in winter: winter now, spring on day 11")
	Seasons.server_update(level)
	check(WorldSim.model().season() == "winter", "the world sim keeps the same year (%s)" % WorldSim.model().season())
	Seasons.server_set_weather("snow")
	var dn := DayNight.current()
	check(Seasons.snow() and dn != null and dn.weather == "overcast", "winter snow: overcast skies with the snow flag (%s)" % (dn.weather if dn else "none"))
	var screen := NewWorldScreen.new(func(_n2: String, _s: int, _o: Dictionary) -> void: pass)
	add_child(screen)
	await _frames(1)
	check(String(screen.choices().get("season", "")) == "spring", "the New world screen offers the starting season (%s)" % [screen.choices()])
	screen.queue_free()


func _test_winter() -> void:
	print("Winter stops the crops and slows the dead")
	_set_season("winter")
	Seasons.force_frost = 0
	Settlement.data()["farm_beds"] = 2
	check(Seasons.farm_yield_x(st, 2) < 0.0 and not SettlementJobs.farm(st, 1.0), "the farm job has nothing to do in winter")
	check(Seasons.water_frozen() == false or Seasons.day_in_season() >= 2, "the water's flag for the body lane (%s)" % Seasons.water_frozen())
	check(is_equal_approx(Seasons.dead_pace_mult(), Seasons.WINTER_PACE), "the dead at %.2f pace in the cold" % Seasons.dead_pace_mult())
	Seasons.force_frost = 1
	check(is_equal_approx(Seasons.dead_pace_mult(), Seasons.FROST_PACE) and Seasons.water_frozen() and Seasons.temperature_c() <= -10.0,
		"a hard frost: a crawl (%.2f), the water frozen, %.0f C" % [Seasons.dead_pace_mult(), Seasons.temperature_c()])
	Seasons.force_frost = 0
	# One walking off: its pace in winter against spring.
	var z := _zombie(player.global_position + Vector3(14.0, 0.0, 0.0))
	await _frames(3)
	var brain := ZombieAI.of(z) if z else null
	if brain == null:
		check(false, "one of the dead to watch")
		return
	z.process_mode = Node.PROCESS_MODE_DISABLED
	brain.mode = ZombieAI.Mode.INVESTIGATE
	brain._set_goal(z.global_position + Vector3(0.0, 0.0, 20.0))
	brain._steer(0.016)
	var winter := z.move_input.length()
	_set_season("spring")
	brain._steer(0.016)
	var spring := z.move_input.length()
	check(winter > 0.0 and winter < spring - 0.01, "a walker's shuffle is slower in winter (%.3f against %.3f)" % [winter, spring])
	z.queue_free()
	await _frames(2)


func _test_frozen() -> void:
	print("A hard frost freezes the dead outdoors")
	_set_season("winter")
	Seasons.force_frost = 1
	var crowd := ZoneDead.of(level)
	var far := player.global_position + Vector3(0.0, 0.0, 150.0)
	for i in 5:
		crowd.server_add(level.ground_point(far + Vector3(i * 3.0, 0.0, 0.0)))
	var z := _zombie(player.global_position + Vector3(-12.0, 0.0, 6.0))
	await _frames(3)
	if z and ZombieAI.of(z):
		ZombieAI.of(z).mode = ZombieAI.Mode.IDLE
		ZombieAI.of(z).awareness = 0.0
	Seasons.server_update(level)
	var frozen := crowd.dead.filter(func(d: Dictionary) -> bool: return bool(d.get("frozen", false))).size()
	check(frozen == 5, "the crowd's heads frozen solid (%d of 5)" % frozen)
	var p0: Vector2 = crowd.dead[0].pos
	for i in 40:
		await get_tree().physics_frame
	check((crowd.dead[0].pos as Vector2).distance_to(p0) < 0.01, "and they stand still")
	check(z != null and Seasons.frozen(z) and Traps.holds(z), "one of the dead outdoors frozen too")
	if z:
		await _frames(3)
		check(z.move_input.length() < 0.01, "it can't move")
		z.vitals.server_hit(Vitals.TORSO, {"round_class": Vitals.INTERMEDIATE})
		check(z.vitals.is_dead(), "one hit shatters it")
	var zones: Dictionary = Seasons.rec().get("frozen_zones", {})
	check(zones.size() > 2, "the world's zones froze with it (%d)" % zones.size())


func _test_thaw() -> void:
	print("The spring thaw")
	var crowd := ZoneDead.of(level)
	var z := _zombie(player.global_position + Vector3(-14.0, 0.0, -6.0))
	await _frames(3)
	if z:
		Seasons.freeze(z)
	var events0 := (WorldSim.section().get("events", []) as Array).size()
	Seasons.rec()["last"] = "winter"
	Seasons.force_frost = 0
	_set_season("spring")
	Seasons.server_update(level)
	var still := crowd.dead.filter(func(d: Dictionary) -> bool: return bool(d.get("frozen", false))).size()
	check(still == 0 and crowd.horde_count() >= 5, "every frozen head wakes at once, a horde (%d in it)" % crowd.horde_count())
	check(z == null or (not Seasons.frozen(z) and z.vitals.undead_pool > 1.0), "the live one thaws too")
	await _frames(2)
	var thaws := (WorldSim.section().get("events", []) as Array).slice(events0).filter(func(e: Dictionary) -> bool: return String(e.kind) == "thaw").size()
	check(thaws > 0, "and the far zones that froze get their thaw (%d events)" % thaws)
	_clear_dead()
	Survival.state()["pressure"] = {}
	await _frames(2)


func _test_summer() -> void:
	print("Summer")
	_set_season("summer")
	check(is_equal_approx(Seasons.thirst_mult(), 1.5) and is_equal_approx(Seasons.spoil_mult(), 0.5) and Seasons.dead_pace_mult() > 1.0,
		"thirst x%.1f, food keeps x%.1f, the dead x%.2f" % [Seasons.thirst_mult(), Seasons.spoil_mult(), Seasons.dead_pace_mult()])
	var z := Seasons.server_wildfire(7)
	var fires := (WorldSim.section().get("events", []) as Array).filter(func(e: Dictionary) -> bool: return String(e.kind) == "wildfire").size()
	check(z != "" and fires > 0, "a wildfire somewhere else (%s)" % z)


func _test_harvest() -> void:
	print("Planting and harvest windows")
	_set_season("spring", 2)
	var d := Settlement.data()
	d["farm_beds"] = 2
	d["crop"] = {}
	st.server_put("seed_packet", 2)
	var seeds := Settlement.count("seed_packet")
	check(Seasons.planting_window() and SettlementJobs.farm(st, 1.0) and Settlement.count("seed_packet") < seeds and int((d.crop as Dictionary).get("beds", 0)) == 2,
		"in spring the farm job plants the beds with a seed packet (%s)" % [d.get("crop")])
	Survival.state()["day"] = 15  # (summer, past planting)
	var veg := Settlement.count("vegetables")
	for i in 8:
		SettlementJobs.farm(st, 1.0)
	check(Seasons.harvest_window() and Settlement.count("vegetables") > veg, "in the harvest window the beds yield (%d vegetables)" % (Settlement.count("vegetables") - veg))
	d["crop"] = {}
	check(Seasons.farm_yield_x(st, 2) < 0.0 and not SettlementJobs.farm(st, 1.0), "a settlement that missed the window has nothing to harvest")
	# The winter eats the stocks down.
	Survival.state()["day"] = 35
	var a := _settler({"traits": ["calm"]})
	var bb := _settler({"traits": ["optimist"]})
	for r: Dictionary in [a, bb]:
		var n := Needs.fresh()
		n["hunger"] = 30.0
		r["needs"] = n
	st.server_put("beans_tin", 6)
	var food0 := Settlement.count_cat("food")
	veg = Settlement.count("vegetables")
	for h: int in [12, 13, 14]:
		st.server_hour(h)
	check(Settlement.count_cat("food") < food0 and Settlement.count("vegetables") <= veg, "in winter the stocks only fall (food %d -> %d)" % [food0, Settlement.count_cat("food")])
	_set_season("spring")


func _test_autumn_bias() -> void:
	print("Autumn's raids in the goal scoring")
	var m := WorldModel.new(WorldSim.section().duplicate(true), WorldSim.people().duplicate(true), WorldSim.pressure_section().duplicate(true), WorldSim.world_seed())
	m.now = 1.5
	var g := {"kind": "raiders"}
	var opts := [{"kind": "raid", "target": "g1", "bias": 0.0, "gain": 0.5}, {"kind": "forage", "bias": 0.0}]
	m.w["season_start"] = "spring"
	Seasons.bias_options(m, g, opts)
	var spring := float(opts[0].bias)
	m.w["season_start"] = "autumn"
	opts = [{"kind": "raid", "target": "g1", "bias": 0.0, "gain": 0.5}]
	Seasons.bias_options(m, g, opts)
	check(m.season() == "autumn" and float(opts[0].bias) > spring + 0.2, "raiders weigh a raid higher in autumn (%.2f against %.2f)" % [float(opts[0].bias), spring])
	var s := {"kind": "settlers"}
	opts = [{"kind": "forage", "bias": 0.0}]
	Seasons.bias_options(m, s, opts)
	check(float(opts[0].bias) > 0.0, "settlers stock up before the winter")
	# Through the real options: a raider group next to a settlers' group.
	var zone := String(Survival.state().get("start_zone", ""))
	var near := String((m.zone(zone).get("links", []) as Array)[0])
	var r := m.new_group("raiders", near, Vector2.ZERO, m.rng_for("bias_r"), 5)
	var v := m.new_group("settlers", near, Vector2(100.0, 0.0), m.rng_for("bias_v"), 4)
	v.supplies["food"] = 40.0
	var best := func() -> float:
		var top := -INF
		for o: Dictionary in WorldGoals.options(m, r):
			if String(o.kind) == "raid" and String(o.target) == String(v.id):
				top = maxf(top, WorldGoals.score(r, o))
		return top
	var autumn_s: float = best.call()
	m.w["season_start"] = "spring"
	var spring_s: float = best.call()
	check(autumn_s > spring_s, "the raid on the settlers scores higher in autumn (%.2f against %.2f)" % [autumn_s, spring_s])


func _test_raid() -> void:
	print("A live raid on the settlement")
	for x in range(-2, 3):
		_block(_at(x, -4), "wood")
	var walls := 0
	for x in range(-2, 3):
		if b.is_built(_at(x, -4)):
			walls += 1
	check(walls == 5, "a wood wall of 5 blocks (%s)" % b.last_problem)
	var m := WorldSim.model()
	var home := Settlement.pos()
	var g := m.new_group("raiders", String(Survival.state().zone), Vector2(home.x, home.z - 28.0), m.rng_for("season_raid"), 3)
	g.relations["player"] = -100.0
	var gid := String(g.id)
	var n := sieges.server_raid_start(gid)
	await _frames(3)
	check(n == 3 and bool(WorldSim.group(gid).get("assault", false)), "the raiders come live, attacking (%d bodies)" % n)
	var blown: Variant = sieges.server_breach_wall(gid)
	await _frames(2)
	check(blown is Vector3i and not b.is_built(blown), "a breach charge blows the wood wall (%s)" % [blown])
	st.server_put("beans_tin", 10)
	st.server_put("planks", 10)
	var food0 := Settlement.count("beans_tin")
	var taken := sieges.server_raid_lost(gid)
	check(taken > 0 and Settlement.count("beans_tin") < food0, "lost: the stores taken (%d things; beans %d -> %d)" % [taken, food0, Settlement.count("beans_tin")])
	var live := WorldLive.of(level)
	if live:
		live.server_fold(gid)
	WorldSim.group(gid).alive = false
	await _frames(3)


func _test_walls() -> void:
	print("The dead at a wall")
	# Wood three high at x=6, steel three high at x=8, wood two high (waist) at x=10; a gap: x=12
	# built from one up, held by x=13 standing from the ground.
	var specs := [[6, "wood", [0, 1, 2]], [8, "steel", [0, 1, 2]], [10, "wood", [0, 1]], [13, "wood", [0, 1, 2]], [12, "wood", [1, 2]]]
	for spec: Array in specs:
		for y: int in spec[2]:
			_block(_at(int(spec[0]), 6) + Vector3i(0, y, 0), String(spec[1]))
	await _frames(2)
	var fwd := Vector3(0.0, 0.0, 1.0)
	var from := func(x: int) -> Vector3: return _pos(_at(x, 5)) + Vector3(0.0, 0.0, 0.1)
	var z := _zombie(from.call(6))
	await _frames(3)
	if z == null:
		check(false, "one of the dead at the wall")
		return
	z.process_mode = Node.PROCESS_MODE_DISABLED
	Sieges.piles.clear()
	var wood := Sieges.wall_ahead(b, from.call(6), fwd)
	check(not wood.is_empty() and String(wood.mat) == "wood" and is_equal_approx(float(wood.height_m), 1.5), "the wall ahead: wood, 1.5 m (%s)" % [wood])
	var hp0 := float(b.blocks[wood.cell].hp) if not wood.is_empty() else 1.0
	var did := Sieges.server_wall_step(z, "walker", wood, fwd, 300.0) if not wood.is_empty() else ""
	check(did == "chew" and float(b.blocks[wood.cell].hp) < hp0, "a walker chews the wood (%s, hp %.2f -> %.2f)" % [did, hp0, float(b.blocks[wood.cell].hp) if b.blocks.has(wood.cell) else -1.0])
	var steel := Sieges.wall_ahead(b, from.call(8), fwd)
	z.global_position = from.call(8)
	var s0 := float(b.blocks[steel.cell].hp) if not steel.is_empty() else 1.0
	did = Sieges.server_wall_step(z, "walker", steel, fwd, 300.0) if not steel.is_empty() else ""
	check(did == "pile" and is_equal_approx(float(b.blocks[steel.cell].hp), s0), "and not the steel: they pile at it (%s)" % did)
	# The pile at the steel becomes a ramp: five heads at 0.3 m make 1.5 m.
	var climbed := ""
	var bodies: Array[Soldier] = []
	for i in 4:
		var o := _zombie(from.call(8) + Vector3(0.0, 0.0, -0.5 - i * 0.6))
		if o:
			o.process_mode = Node.PROCESS_MODE_DISABLED
			bodies.append(o)
	await _frames(2)
	for o: Soldier in bodies:
		climbed = Sieges.server_wall_step(o, "walker", steel, fwd, 0.4)
	var last: Soldier = bodies[-1] if not bodies.is_empty() else null
	check(climbed == "climb" and last != null and last.global_position.z > BuildPieces.cell_centre(steel.cell).z, "the pile is a ramp: the next walker climbs over (%s, pile %.1f m)" % [climbed, Sieges.pile_m(String(steel.get("key", "")))])
	var low := Sieges.wall_ahead(b, from.call(10), fwd)
	z.global_position = from.call(10)
	did = Sieges.server_wall_step(z, "runner", low, fwd, 0.4) if not low.is_empty() else ""
	check(did == "vault" and z.global_position.z > BuildPieces.cell_centre(low.cell).z, "a runner vaults a waist-high wall (%s)" % did)
	var gap := Sieges.wall_ahead(b, from.call(12), fwd)
	z.global_position = from.call(12)
	did = Sieges.server_wall_step(z, "crawler", gap, fwd, 0.4) if not gap.is_empty() else ""
	check(bool(gap.get("gap", false)) and did == "squeeze", "a crawler squeezes through the gap under one (%s)" % [gap])
	# A gate takes a push.
	var gate := _piece("gate", _at(15, 6))
	var gw := Sieges.wall_ahead(b, from.call(16), fwd)
	z.global_position = from.call(16)
	var g0 := float(b.pieces[gate].hp) if gate > 0 else 0.0
	did = Sieges.server_wall_step(z, "walker", gw, fwd, 10.0) if not gw.is_empty() else ""
	check(gate > 0 and did == "push" and float(b.pieces[gate].hp) < g0, "and the dead push on a gate (%s)" % did)
	for o: Soldier in bodies:
		o.queue_free()
	z.queue_free()
	Sieges.piles.clear()
	await _frames(2)


func _test_siege() -> void:
	print("A horde siege")
	Survival.state()["pressure"] = {}
	var crowd := ZoneDead.of(level)
	crowd.dead.clear()
	var a := _settler({"traits": ["calm"]})
	var sg := sieges.server_start_siege()
	var walking := crowd.dead.filter(func(d: Dictionary) -> bool: return d.has("to")).size()
	check(not sg.is_empty() and walking >= Sieges.WAVE_N.x and int(sg.waves_left) == Sieges.WAVES - 1, "the first wave walks at the settlement (%d)" % walking)
	check((Survival.pressure_point(level) as Vector3).distance_to(Settlement.pos()) < 60.0, "the zone's noise is at the settlement")
	sieges.server_wave()
	check(int(Sieges.siege().waves_left) == Sieges.WAVES - 2, "the next wave comes")
	var done := sieges.server_end_siege()
	check(bool(done.over) and Moods.has(a, "siege_survived"), "dawn ends it, and the settlers lived through it")
	crowd.dead.clear()
	Survival.state()["pressure"] = {}


func _test_power() -> void:
	print("Power")
	Survival.state()["hour"] = 12.0
	Seasons.rec()["slot"] = Survival.day() * 4 + 2  # (no re-roll of the weather mid-test)
	Seasons.server_set_weather("clear")
	var lamp := _piece("lamp", _at(-6, 10))
	st.refresh()
	check(lamp > 0 and int(Settlement.data().get("lamps_lit", -1)) == 0 and float(Settlement.footprint().light_m) == 0.0, "a lamp with no power gives no light (%s)" % b.last_problem)
	var panel := _piece("solar_panel", _at(-9, 10))
	st.refresh()
	check(panel > 0 and Infrastructure.is_powered(lamp) and float(Settlement.footprint().light_m) > 0.0,
		"a solar panel by day powers it: the footprint grows (%s; %s)" % [Settlement.footprint(), b.last_problem])
	check(Infrastructure.powered_here(), "and the radio has power at the settlement")


func _test_fence() -> void:
	print("An electric fence")
	var fence := _piece("electric_fence", _at(-13, 10))
	st.refresh()
	check(fence > 0 and Infrastructure.is_powered(fence), "a fence wired by the panel has power (%s)" % b.last_problem)
	var z := _zombie(_pos(_at(-12, 8)))
	await _frames(2)
	if z == null or fence <= 0:
		return
	z.process_mode = Node.PROCESS_MODE_DISABLED
	z.global_position = b.piece_pos(fence)
	z.global_position.y = level.ground_height(z.global_position.x, z.global_position.z) + 0.05
	Traps.server_tick(level)
	check(Traps.holds(z) and float(z.get_meta(&"stunned_until", 0.0)) > Soldier._now(), "it stuns one of the dead against it")
	z.queue_free()
	await _frames(2)


func _test_bridge() -> void:
	print("Blowing a bridge")
	var a := String(Survival.state().get("start_zone", ""))
	var links: Array = WorldSim.model().zone(a).get("links", [])
	if links.is_empty():
		check(false, "the start zone has a neighbour")
		return
	var other := String(links[0])
	check(WorldSim.model().crossing_open(a, other), "the crossing is open")
	Infrastructure.server_blow_bridge(a, other)
	var m := WorldSim.model()
	var g := {"zone": a, "id": "x"}
	check(not m.crossing_open(a, other) and not other in WorldGoals.reach(m, g), "blown: closed, and no goal reaches over it")
	Infrastructure.server_set_crossing(a, other, true)
	check(WorldSim.model().crossing_open(a, other), "repaired: open again")


func _test_traps() -> void:
	print("Traps")
	var pit := _piece("spike_pit", _at(8, -11))
	var wire := _piece("wire", _at(12, -11))
	check(pit > 0 and wire > 0, "a spike pit and wire (%s)" % b.last_problem)
	var z1 := _zombie(_pos(_at(8, -11)))
	var z2 := _zombie(_pos(_at(12, -11)))
	await _frames(2)
	if z1 == null or z2 == null:
		return
	for z: Soldier in [z1, z2]:
		z.process_mode = Node.PROCESS_MODE_DISABLED
	z1.global_position = b.piece_pos(pit)
	z1.global_position.y = level.ground_height(z1.global_position.x, z1.global_position.z) + 0.05
	z2.global_position = b.piece_pos(wire)
	z2.global_position.y = level.ground_height(z2.global_position.x, z2.global_position.z) + 0.05
	var hp0 := float(b.pieces[wire].hp)
	Traps.server_tick(level)
	check(z1.vitals.is_dead(), "the spike pit kills a walker")
	check(Traps.holds(z2) and z2.vitals.is_up() and float(b.pieces[wire].hp) < hp0, "wire holds one, and it chews at it (%.1f -> %.1f)" % [hp0, float(b.pieces[wire].hp)])
	z2.queue_free()
	await _frames(2)


func _test_lure() -> void:
	print("A thrown bottle")
	_clear_dead()
	await _frames(2)
	var z := _zombie(player.global_position + Vector3(30.0, 0.0, 0.0))
	await _frames(3)
	var brain := ZombieAI.of(z) if z else null
	if brain == null:
		check(false, "one of the dead to lure")
		return
	z.process_mode = Node.PROCESS_MODE_DISABLED
	brain.mode = ZombieAI.Mode.IDLE
	brain.goal = Vector3.INF
	var spot := z.global_position + Vector3(0.0, 0.0, 20.0)
	var heard := Lures.server_bottle(level, spot)
	check(heard >= 1 and brain.mode == ZombieAI.Mode.INVESTIGATE and brain.goal.distance_to(spot) < 2.0, "the dead go to where it smashed (%s)" % brain.state_name())
	z.queue_free()
	await _frames(2)


func _test_masking() -> void:
	print("Masking and the bodies")
	var z := _zombie(player.global_position + Vector3(1.5, 0.0, 0.0))
	await _frames(3)
	if z == null:
		return
	z.vitals.server_kill()
	await _frames(2)
	z.global_position = player.global_position + Vector3(1.5, 0.0, 0.0)
	check(Masking.is_dead_one(z) and Masking.server_smear(player, z) == "", "gore smeared from a fresh one")
	check(Masking.masked(player) and Masking.smell_x(player) == 0.0 and is_equal_approx(Masking.sight_x(player, 1.0), Masking.NIGHT_SIGHT_X),
		"it hides his smell, and at night slow among them their sight of him")
	var actions := TalkMenu.actions_for(player, z, InteractionMenu.DEAD)
	check(actions.any(func(e: Dictionary) -> bool: return String(e.id) == "talk_smear"), "the dead one's menu offers it")
	check(Masking.server_burn(level, z.global_position) >= 1 and z.is_queued_for_deletion(), "a pyre burns the body")
	player.set_meta(&"gore_until", -1.0)
	await _frames(2)


func _test_politics() -> void:
	print("Settlement politics")
	for r: Dictionary in Settlement.settlers():
		r["status"] = "out_there"
	var p1 := _settler({"traits": ["pious", "kind"]})
	var p2 := _settler({"traits": ["pious", "brave"]})
	var p3 := _settler({"traits": ["pious", "greedy"]})
	var other := _settler({"traits": ["calm"]})
	var fs := Council.factions()
	check((fs.get("the pious", []) as Array).size() == 3, "the pious are a faction (%s)" % [fs.keys()])
	var id := Council.server_put({"kind": "take_in", "text": "take in strangers", "people": []}, ["take", "refuse"])
	var res := Council.server_resolve(id)
	var v := Council.get_vote(id)
	var pious_w := 0.0
	for r: Dictionary in [p1, p2, p3]:
		pious_w += Council.influence(r)
	check(float((v.tally as Dictionary).get(res, 0.0)) >= pious_w - 0.01 or float((v.tally as Dictionary).values().max()) >= pious_w - 0.01,
		"they vote together: all their weight on one answer (%s)" % [v.tally])
	for r: Dictionary in [p1, p2, p3]:
		r["mood_forced"] = 20.0
	Politics.server_share_moodlets()
	check(Moods.has(p1, "faction_low") and Moods.has(p3, "faction_low") and not Moods.has(other, "faction_low"), "and share their low mood")
	# Theft.
	var n := Needs.fresh()
	n["hunger"] = 20.0
	other["needs"] = n
	other["mood_forced"] = 20.0
	st.server_put("beans_tin", 4)
	var food0 := Settlement.count_cat("food")
	Politics.force_roll = 0.0
	check(Politics.server_theft(st, other) and Settlement.count_cat("food") < food0 and Moods.has(other, "stole") and Moods.has(p1, "theft"),
		"a hungry gloomy settler steals food (%d -> %d)" % [food0, Settlement.count_cat("food")])
	Politics.force_roll = -1.0
	other.erase("mood_forced")
	# A split.
	var gid := Politics.server_split(st)
	await _frames(2)
	var g := WorldSim.group(gid)
	check(gid != "" and (g.get("members", []) as Array).size() == 3 and String(p2.status) == WorldGroup.GROUPED and String(g.leader) == String(p2.id),
		"the low faction with a leader walks out as a world group (%s, led by %s)" % [String(g.get("name", "")), String(g.get("leader", ""))])
	# The leader challenge, lost by vote: the settlement passes on.
	var ch := _settler({"traits": ["brave", "hot_headed"]})
	var follower := _settler({"traits": ["calm"]})
	var profile := Survival.profile_of(player)
	SurvivorPerson.change_relation(follower, String(ch.id), 60.0)
	SurvivorPerson.change_relation(other, String(ch.id), 60.0)
	for r: Dictionary in [follower, other]:
		SurvivorPerson.change_opinion(r, profile, -40.0)
	Council._rec()["challenge"] = {"by": String(ch.id), "name": String(ch.name), "day": Survival.day(), "text": "test", "state": "open"}
	var out := Politics.server_contest("vote", profile)
	await _frames(2)
	var lost: Dictionary = Survival.state().get("settlement_lost", {})
	var holder := WorldSim.group(String(lost.get("held_by", "")))
	check(out == "lost" and not Settlement.exists() and not holder.is_empty() and not (holder.get("home", {}) as Dictionary).is_empty(),
		"the challenge lost: the settlement and its builds are %s's group's now (%s)" % [String(ch.name), String(holder.get("name", ""))])
	# Relations with other settlements.
	var m := WorldSim.model()
	var town := m.new_group("settlers", String(Survival.state().get("start_zone", "")), Vector2(400.0, 400.0), m.rng_for("season_pact"), 4)
	town.supplies["food"] = 50.0
	var tid := String(town.id)
	check(Politics.server_pact(tid, "alliance") == "" and Politics.pact_with(tid) == "alliance" and WorldGroup.relation(WorldSim.group(tid), "player") >= 40.0,
		"an alliance with %s (relation %.0f)" % [String(town.name), WorldGroup.relation(WorldSim.group(tid), "player")])
	Settlement.server_found(String(Survival.state().zone), _pos(_at(0, 0)))
	check(Politics.server_call_allies() == 1 and String((WorldSim.group(tid).goal as Dictionary).get("kind", "")) == "defend", "the shared defence call brings them")
	Politics.server_pact(tid, "protection")
	var paid := Politics.server_pacts_day(Settlement.find(level))
	check(paid > 0, "protection: their share of food comes in (%d)" % paid)
	Politics.server_pact(tid, "feud")
	check(Politics.pact_with(tid) == "feud" and WorldGroup.relation(WorldSim.group(tid), "player") <= -60.0, "a feud turns them hostile")


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
	Politics.force_roll = -1.0
	Sieges.piles.clear()
	Lures.active.clear()
	if Survival.world != "":
		GameState.delete_save()
		Survival.running = false
		Campaign.reset_campaign()
	print("SEASONS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
