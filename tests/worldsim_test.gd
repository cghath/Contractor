extends Node
## Contractor: Fallen's living world (docs/survival_world.md section 14, phase C core): a new
## world sets up its regions and groups; groups forage, trade and settle by the judgement; a raid
## judged against a scouted settlement sends a demand first (and the players' farm gets one too);
## a far fight leaves traces and an event; pressure forms a local horde that never crosses into a
## quieter zone (only into a louder one), and groups keep loud goals away from a zone near its
## threshold; cultists capture a lone survivor and a friend's group goes searching; a raider's
## rumour lies and a scout's is true; groups near the players come live (bodies, the hostile on a
## squad of their own) and fold back; the catch-up moves the world within its bound, keeps the
## farm and the companions safe and reports it; each goal mode's state and win; two sims from one
## seed agree; a far tick runs on a worker and lands; holding or fleeing (call 143): an unarmed far
## household the dead find relocates and its place is left (signs when the zone is up again), an
## armed one with a guard holds, a camp that can't hold against a horde relocates instead.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier
var sim: WorldSim


func _ready() -> void:
	get_tree().create_timer(400.0).timeout.connect(func() -> void:
		print("WORLDSIM TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _test_new_world()
	if level != null and player != null and sim != null:
		_test_forage_trade_settle()
		_test_raid_and_demand()
		_test_far_fight()
		_test_pressure_and_hordes()
		_test_capture_and_search()
		_test_holding_sim()
		_test_rumours()
		_test_determinism()
		await _test_live()
		await _test_threaded_tick()
		await _test_settlement_demand()
		_test_catch_up()
		_test_holding_zone_up()
		_test_goal_modes()
	_finish()


func _test_new_world() -> void:
	print("A new world")
	check(Survival.server_new_world(main, "test_worldsim" + tag, 2468), "the menu's New world hosts one")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 25.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	sim = WorldSim.get_sim()
	check(player != null and sim != null, "the survivor is in and the world sim is under Survival")
	if sim == null:
		return
	sim.enabled = false  # (the test drives the ticks)
	var w := WorldSim.section()
	var zones: Dictionary = w.get("zones", {})
	check(WorldSim.is_set_up() and zones.size() >= 20, "the world is set up: %d zones" % zones.size())
	var regions := {}
	for zd: Dictionary in zones.values():
		regions[String(zd.region)] = true
	check(regions.has("plains") and regions.has("hills") and regions.has("desert") and regions.has("coast") and regions.has("city"),
		"its zones fall into the regions: %s" % ", ".join(regions.keys()))
	check(WorldSim.region_of("wadi_farm") == "plains" and WorldSim.region_of("harbour_yard") == "coast", "region_of reads the table")
	var groups: Dictionary = w.get("groups", {})
	var kinds := {}
	var held := 0
	for g: Dictionary in groups.values():
		kinds[String(g.kind)] = int(kinds.get(String(g.kind), 0)) + 1
		if not (g.home as Dictionary).is_empty():
			held += 1
			if held == 1:
				check(WorldSim.holder_of(String(g.home.zone), String(g.home.place)) == String(g.id), "holder_of %s's home is them" % String(g.name))
	check(groups.size() >= 10 and kinds.size() >= 3, "groups across the map by the regions' tendencies: %s" % str(kinds))
	var start := String(Survival.state().start_zone)
	check(WorldSim.groups_in(start).filter(func(g: Dictionary) -> bool: return String(g.kind) != "lone").is_empty(), "nobody's group starts at the farm's zone (%s)" % start)
	var g0: Dictionary = groups.values().filter(func(g: Dictionary) -> bool: return String(g.kind) == "settlers")[0] if kinds.has("settlers") else {}
	var leader: Dictionary = WorldSim.people().get(String(g0.get("leader", "")), {})
	check(not leader.is_empty() and String(leader.status) == WorldGroup.GROUPED and String(leader.world_group) == String(g0.id), "a group's people are Person records, in the group")
	check(String(WorldSim.goal_state().mode) == "evac" and String(WorldSim.goal_state().evac_zone) != "", "the default goal is the evac, at %s" % String(WorldSim.goal_state().evac_zone))


# --- An isolated world for the rules --------------------------------------------------------------

func _iso(world_seed := 99) -> WorldModel:
	var table: Dictionary = (WorldSim.section().zones as Dictionary).duplicate(true)
	for zd: Dictionary in table.values():
		zd.traces = []
		zd.horde = {}
		zd.dead = 1.0
		for p: Dictionary in zd.places:
			p.holder = ""
			p.looted = -100.0
	var m := WorldModel.new({"zones": table, "cells": (WorldSim.section().get("cells", {}) as Dictionary).duplicate(true), "start_zone": ""}, {}, {}, world_seed)
	m.now = 5.0
	m.player = {"zone": "", "place": "safehouse", "place_pos": [0.0, 0.0], "strength": 3.0, "home_strength": 0.0, "stocks_value": 4000.0,
		"can_take": false, "hunt_zone": "", "safe": false}
	return m


## A zone with at least `links` links and two places.
func _zone(m: WorldModel, links := 2, skip: Array = []) -> String:
	for z: String in WorldModel._sorted(m.zones().keys()):
		if z in skip:
			continue
		var zd := m.zone(z)
		if (zd.links as Array).size() >= links and (zd.places as Array).size() >= 2 and not bool(WorldRegions.region_def(String(zd.region)).get("unheld", false)):
			return z
	return ""


func _grp(m: WorldModel, kind: String, zone: String, n: int, supplies := {}, p := {}) -> Dictionary:
	var g := m.new_group(kind, zone, Vector2.ZERO, m.rng_for("test_" + kind + str(m.groups().size())), n)
	g.kind = kind
	for k: String in supplies:
		g.supplies[k] = float(supplies[k])
	(g.personality as Dictionary).merge(p, true)
	return g


func _loot_all(m: WorldModel, zone: String) -> void:
	for z: String in [zone] + (m.zone(zone).links as Array):
		for pl: Dictionary in m.zone(z).places:
			pl.looted = m.now


func _act_until_done(m: WorldModel, g: Dictionary, max_ticks: int) -> int:
	for i in max_ticks:
		if (g.goal as Dictionary).is_empty():
			return i
		m.w.tick = m.tick() + 1
		WorldGoals.act(m, g)
	return max_ticks


func _test_forage_trade_settle() -> void:
	print("Forage, trade, settle by the judgement")
	var m := _iso()
	var a := _zone(m)
	var s := _grp(m, "scavengers", a, 3, {"food": 0.0, "water": 0.5, "ammo": 2.0}, {"cruelty": 0.1})
	WorldGoals.decide(m, s)
	check(String(s.goal.get("kind", "")) == "forage", "a hungry scavenger crew forages (%s, %.2f)" % [String(s.goal.get("kind", "")), float(s.goal.get("score", 0.0))])
	var place := String(s.goal.get("place", ""))
	var pzone := String(s.goal.get("zone", ""))
	var food0 := WorldGroup.supply(s, "food")
	_act_until_done(m, s, 30)
	check(WorldGroup.supply(s, "food") > food0 and float(WorldRegions.place(m.zone(pzone), place).get("looted", -100.0)) >= m.now - 0.01,
		"it comes back with food (%.1f) and the place is looted" % WorldGroup.supply(s, "food"))
	var b := _zone(m, 2, [a])
	_loot_all(m, b)
	var t1 := _grp(m, "settlers", b, 3, {"food": 40.0, "water": 40.0, "ammo": 0.0, "meds": 0.0})
	var t2 := _grp(m, "settlers", b, 3, {"food": 0.0, "water": 0.0, "ammo": 30.0, "meds": 10.0})
	m.set_home(t1, b, m.zone(b).places[0])
	m.set_home(t2, b, m.zone(b).places[1])
	WorldGoals.decide(m, t1)
	check(String(t1.goal.get("kind", "")) == "trade" and String(t1.goal.get("target", "")) == String(t2.id), "a settlement with food to spare and no ammo trades with one that's the other way round (%s)" % String(t1.goal.get("kind", "")))
	var events0 := (m.w.events as Array).size()
	_act_until_done(m, t1, 5)
	check(WorldGroup.supply(t1, "ammo") > 0.0 and WorldGroup.supply(t2, "food") > 0.0 and (m.w.events as Array).slice(events0).any(func(e: Dictionary) -> bool: return String(e.kind) == "trade"),
		"the swap at the value scale: ammo %.1f one way, food %.1f the other, and an event" % [WorldGroup.supply(t1, "ammo"), WorldGroup.supply(t2, "food")])
	check(WorldTrade.value("antibiotics") > 0.0, "WorldTrade.value prices an item ($%.0f antibiotics)" % WorldTrade.value("antibiotics"))
	var c := _zone(m, 2, [a, b])
	_loot_all(m, c)
	var z := _grp(m, "settlers", c, 4, {"food": 30.0, "water": 30.0})
	WorldGoals.decide(m, z)
	check(String(z.goal.get("kind", "")) == "settle", "settlers with no home look for one (%s)" % String(z.goal.get("kind", "")))
	_act_until_done(m, z, 30)
	var h: Dictionary = z.home
	check(not h.is_empty() and String(WorldRegions.place(m.zone(String(h.zone)), String(h.place)).holder) == String(z.id), "they make camp at a place and hold it")


func _test_raid_and_demand() -> void:
	print("A raid: judged, a demand first")
	var m := _iso(7)
	var z := _zone(m)
	var s := _grp(m, "settlers", z, 4, {"food": 30.0, "water": 30.0, "ammo": 4.0}, {"caution": 0.3})
	m.set_home(s, z, m.zone(z).places[0])
	var k := _grp(m, "raiders", z, 8, {"food": 2.0, "water": 4.0, "ammo": 60.0}, {"greed": 0.7, "cruelty": 0.6, "caution": 0.3})
	_loot_all(m, z)
	(k.knows as Dictionary)[String(s.id)] = {"t": m.now, "strength": 1.5, "scouted": true}
	var weak := WorldGoals.options(m, k).filter(func(o: Dictionary) -> bool: return String(o.kind) == "raid" and String(o.target) == String(s.id))
	WorldGoals.decide(m, k)
	check(String(k.goal.get("kind", "")) == "raid" and String(k.goal.get("target", "")) == String(s.id), "raiders who scouted a weak settlement raid it (%s)" % String(k.goal.get("kind", "")))
	var events0 := (m.w.events as Array).size()
	for i in 3:
		m.w.tick = m.tick() + 1
		WorldGoals.act(m, k)
	var new := (m.w.events as Array).slice(events0)
	var demand := new.filter(func(e: Dictionary) -> bool: return String(e.kind) == "demand")
	var fight := new.filter(func(e: Dictionary) -> bool: return String(e.kind) == "fight")
	check(not demand.is_empty(), "a demand comes first: \"%s\"" % String(demand[0].text) if not demand.is_empty() else "a demand comes first")
	check(fight.is_empty() or int(fight[0].id) > int(demand[0].id), "and any fight only after it (%d fights)" % fight.size())
	# the same raiders, knowing the settlement is strong, judge it differently
	var m2 := _iso(7)
	var s2 := _grp(m2, "settlers", z, 4, {"food": 30.0, "water": 30.0, "ammo": 4.0})
	m2.set_home(s2, z, m2.zone(z).places[0])
	var k2 := _grp(m2, "raiders", z, 8, {"food": 2.0, "water": 4.0, "ammo": 60.0}, {"greed": 0.7, "cruelty": 0.6, "caution": 0.3})
	(k2.knows as Dictionary)[String(s2.id)] = {"t": m2.now, "strength": 60.0, "scouted": true}
	var strong := WorldGoals.options(m2, k2).filter(func(o: Dictionary) -> bool: return String(o.kind) == "raid" and String(o.target) == String(s2.id))
	check(not weak.is_empty() and not strong.is_empty() and WorldGoals.score(k2, strong[0]) < WorldGoals.score(k, weak[0]) - 1.0,
		"what they know of its strength weighs: %.2f against a weak one, %.2f against a strong one" % [WorldGoals.score(k, weak[0]) if not weak.is_empty() else 0.0, WorldGoals.score(k2, strong[0]) if not strong.is_empty() else 0.0])
	# the players' farm: a demand as a line and a message, time to pay
	var m3 := _iso(8)
	var fz := _zone(m3)
	m3.player.zone = fz
	m3.player.hunt_zone = fz
	var p := _grp(m3, "raiders", fz, 5, {"ammo": 30.0})
	p.goal = {"kind": "raid", "zone": fz, "place": "safehouse", "target": "player", "phase": "go", "since": 0, "work": 0}
	m3.w.tick = m3.tick() + 1
	WorldGoals.decide(m3, p)
	WorldGoals.act(m3, p)
	var d: Dictionary = (m3.w.demands as Dictionary).get(String(p.id), {})
	check(not d.is_empty() and float(d.due) > m3.now and m3.actions.any(func(a: Dictionary) -> bool: return String(a.kind) == "demand"),
		"raiders at the farm send the players a demand first ($%d, due in %.0f h)" % [int(d.get("want", 0)), (float(d.get("due", 0.0)) - m3.now) * 24.0])
	m3.w.tick = m3.tick() + 1
	WorldGoals.act(m3, p)
	check(String(p.goal.get("phase", "")) == "wait", "and wait for an answer")
	d.paid = true
	WorldGoals.act(m3, p)
	check((p.goal as Dictionary).is_empty() and not (m3.w.demands as Dictionary).has(String(p.id)) and WorldGroup.relation(p, "player") > -30.0,
		"paid, they go (standing %.0f)" % WorldGroup.relation(p, "player"))


func _test_far_fight() -> void:
	print("A far fight")
	var m := _iso(11)
	var z := _zone(m)
	var s := _grp(m, "settlers", z, 5, {"food": 20.0, "ammo": 5.0})
	var pl: Dictionary = m.zone(z).places[0]
	m.set_home(s, z, pl)
	var k := _grp(m, "raiders", z, 6, {"ammo": 40.0})
	var size0 := WorldGroup.size(s) + WorldGroup.size(k)
	var p0 := m.pressure_of(z)
	WorldFights.resolve(m, k, s, String(pl.id))
	var dead := m.people.values().filter(func(r: Dictionary) -> bool: return String(r.status) == "dead")
	var traces: Array = m.zone(z).traces
	var fight := (m.w.events as Array).filter(func(e: Dictionary) -> bool: return String(e.kind) == "fight")
	check(dead.size() >= 1 and WorldGroup.size(s) + WorldGroup.size(k) == size0 - dead.size(), "named people die (%s)" % ", ".join(dead.map(func(r: Dictionary) -> String: return String(r.name))))
	check(not traces.is_empty() and not (traces[-1].dead as Array).is_empty() and String(traces[-1].place) == String(pl.id), "their bodies are traces at the place (%s)" % str(traces[-1].get("dead", [])) if not traces.is_empty() else "traces")
	check(not fight.is_empty() and String(fight[0].text).contains(String(s.name)), "and an event: \"%s\"" % (String(fight[0].text) if not fight.is_empty() else ""))
	check(m.pressure_of(z) > p0 + 5.0, "the noise raised the zone's pressure (%.0f)" % m.pressure_of(z))
	check(WorldGroup.relation(s, String(k.id)) <= -50.0 or not bool(s.alive), "the attacked remember it")
	var dead_rec: Dictionary = dead[0] if not dead.is_empty() else {}
	check(String(dead_rec.get("zone", "")) == z and dead_rec.has("body_pos"), "a dead record lies where it happened")


func _test_pressure_and_hordes() -> void:
	print("Pressure and hordes across the map")
	var m := _iso(13)
	var h := _zone(m, 2)
	var t := m.now
	m.pressure[h] = {"v": 92.0, "at": t, "x": 0.0, "z": 0.0}
	for nb: String in m.zone(h).links:
		m.pressure[nb] = {"v": 10.0, "at": t, "x": 0.0, "z": 0.0}
	t += WorldModel.TICK_MIN / 1440.0
	m.step(t)
	var horde: Dictionary = m.zone(h).horde
	check(int(horde.get("n", 0)) >= 15 and (m.w.events as Array).any(func(e: Dictionary) -> bool: return String(e.kind) == "horde" and String(e.zone) == h),
		"at the threshold a horde forms from the zone's own dead (%d)" % int(horde.get("n", 0)))
	for i in 8:
		t += WorldModel.TICK_MIN / 1440.0
		m.step(t)
	var crossed := false
	for nb: String in m.zone(h).links:
		crossed = crossed or not (m.zone(nb).horde as Dictionary).is_empty()
	check(not crossed and not (m.zone(h).horde as Dictionary).is_empty(), "it never crosses into a quieter neighbour (still in %s at %.0f)" % [h, m.pressure_of(h)])
	var loud := String(m.zone(h).links[0])
	m.pressure[loud] = {"v": 99.0, "at": t, "x": 0.0, "z": 0.0}
	for i in 3:
		t += WorldModel.TICK_MIN / 1440.0
		m.step(t)
	check(not (m.zone(loud).horde as Dictionary).is_empty() and (m.zone(h).horde as Dictionary).is_empty(), "but walks the gradient into a louder one on its path (%s)" % loud)
	# a group keeps a loud goal away from a zone near the threshold
	var m2 := _iso(14)
	var z := _zone(m2, 2)
	var s := _grp(m2, "settlers", z, 3, {"food": 30.0, "water": 30.0, "ammo": 1.0})
	m2.set_home(s, z, m2.zone(z).places[0])
	var k := _grp(m2, "raiders", z, 8, {"food": 2.0, "water": 3.0, "ammo": 60.0}, {"greed": 0.7, "cruelty": 0.6, "caution": 0.4})
	(k.knows as Dictionary)[String(s.id)] = {"t": m2.now, "strength": 1.0, "scouted": true}
	var quiet: Array = WorldGoals.options(m2, k).filter(func(o: Dictionary) -> bool: return String(o.kind) == "raid" and String(o.target) == String(s.id))
	m2.pressure[z] = {"v": 75.0, "at": m2.now, "x": 0.0, "z": 0.0}
	var tense: Array = WorldGoals.options(m2, k).filter(func(o: Dictionary) -> bool: return String(o.kind) == "raid" and String(o.target) == String(s.id))
	var sq := WorldGoals.score(k, quiet[0]) if not quiet.is_empty() else 0.0
	var st := WorldGoals.score(k, tense[0]) if not tense.is_empty() else 0.0
	WorldGoals.decide(m2, k)
	check(st < sq - 0.8 and String(k.goal.get("kind", "")) != "raid", "near a horde's threshold the raid scores %.2f (%.2f quiet); they don't (%s)" % [st, sq, String(k.goal.get("kind", ""))])
	m2.raise_pressure(z, 10.0)
	check(m2.pressure_of(z) > 80.0, "noise raises a far zone's pressure")


func _test_capture_and_search() -> void:
	print("Cultists take a lone survivor; a friend's group searches")
	var m := _iso(17)
	var c := _zone(m, 2)
	var lone := m.new_lone(c, Vector2(10.0, 10.0), m.rng_for("lone"), "test")
	var lone_pid := String(lone.leader)
	var c2 := String(m.zone(c).links[0])
	_loot_all(m, c2)
	var f := _grp(m, "settlers", c2, 8, {"food": 40.0, "water": 40.0, "ammo": 40.0})
	m.set_home(f, c2, m.zone(c2).places[0])
	SurvivorPerson.change_relation(m.people[String(f.members[1])], lone_pid, 60.0)
	_loot_all(m, c)
	var k := _grp(m, "cultists", c, 6, {"ammo": 6.0, "food": 40.0, "water": 40.0}, {"faith": 0.9, "cruelty": 0.6})
	WorldGoals.decide(m, k)
	check(String(k.goal.get("kind", "")) == "capture" and String(k.goal.get("target", "")) == String(lone.id), "the cult goes for the lone survivor (%s)" % String(k.goal.get("kind", "")))
	k.goal = {"kind": "capture", "zone": c, "place": "", "target": String(lone.id), "phase": "go", "since": 0, "work": 0}
	m.w.tick = m.tick() + 1
	WorldGoals.act(m, k)
	var rec: Dictionary = m.people[lone_pid]
	check(String(rec.status) == "captive" and String(rec.get("captor", "")) == String(k.id) and lone_pid in (k.captives as Array), "%s is their captive" % String(rec.name))
	check(not (f.missing as Array).is_empty() and String(f.missing[0].id) == lone_pid, "the friend's group misses them")
	WorldGoals.decide(m, f)
	check(String(f.goal.get("kind", "")) == "search" and String(f.goal.get("target", "")) == lone_pid, "and goes searching (%s)" % String(f.goal.get("kind", "")))
	k.goal = {"kind": "feed", "zone": c, "place": "", "target": "", "phase": "go", "since": 0, "work": 0}
	var p0 := m.pressure_of(c)
	WorldGoals.act(m, k)
	check(String(rec.status) == "dead" and m.pressure_of(c) > p0, "fed to the kept dead, the zone's pressure held high (%.0f)" % m.pressure_of(c))


func _test_holding_sim() -> void:
	print("Holding or fleeing, far (call 143)")
	var m := _iso(31)
	var z := _zone(m, 2)
	var pl: Dictionary = m.zone(z).places[0]
	var at := WorldModel._place_v(pl)
	# An unarmed household of three found by the dead: they run, the place is left.
	var fam: Array = []
	for i in 3:
		var r := m.new_person(m.rng_for("hh%d" % i), z, at + Vector2(i * 1.5, 0.0), {"child": true, "age": 8} if i == 2 else {})
		r.status = "out_there"
		r["family"] = "simfam"
		r.kit = [{"id": "beans_tin", "count": 1}]
		m.lone_group(r)
		fam.append(r)
	(fam[0] as Dictionary)["dead_find_test"] = true
	Holding.sim_tick(m)
	var ab: Dictionary = (m.w.get(Holding.KEY, {}) as Dictionary)
	var e: Dictionary = ab.values()[0] if ab.size() == 1 else {}
	var gone := fam.filter(func(r: Dictionary) -> bool: return String(r.status) == "out_there")
	check(not e.is_empty() and String(e.zone) == z and String(e.state) == "abandoned" and not bool(e.signs), "an unarmed household found by the dead leaves its place (%s)" % String(e.get("text", "")))
	check(gone.size() >= 2 and gone.all(func(r: Dictionary) -> bool: return String(r.get("refugee_from", "")) == String(e.get("key", "")) and (String(r.zone) != z or Vector2(float(r.pos[0]), float(r.pos[2])).distance_to(at) >= Holding.SAFE_FROM_M - 5.0)),
		"they relocate, the child with them (to %s)" % String(e.get("where", "")))
	check(Children.is_child_rec(fam[2]) and String((fam[2] as Dictionary).status) == "out_there", "the child is never the one caught")
	check((m.w.events as Array).any(func(ev: Dictionary) -> bool: return String(ev.kind) == "abandoned" and String(ev.zone) == z) and not (m.zone(z).traces as Array).is_empty(),
		"an event for the rumours, and the place keeps the traces (%s)" % String((m.zone(z).traces as Array)[-1].get("text", "")) if not (m.zone(z).traces as Array).is_empty() else "")
	# An armed household with a guard holds.
	var z2 := _zone(m, 2, [z])
	var at2 := WorldModel._place_v(m.zone(z2).places[0])
	var held: Array = []
	for i in 2:
		var r := m.new_person(m.rng_for("arm%d" % i), z2, at2 + Vector2(i * 1.5, 0.0))
		r.status = "out_there"
		r["family"] = "armfam"
		r.kit = [{"id": "akm", "count": 1}] if i == 0 else [{"id": "beans_tin", "count": 1}]
		if i == 0:
			r["guard"] = true
		m.lone_group(r)
		held.append(r)
	(held[0] as Dictionary)["dead_find_test"] = true
	var n0 := ab.size()
	Holding.sim_tick(m)
	check(held.all(func(r: Dictionary) -> bool: return String(r.zone) == z2 and not r.has("refugee_from")) and (m.w.get(Holding.KEY, {}) as Dictionary).size() == n0,
		"an armed household with a guard holds (strength %.1f against %.1f)" % [Holding.household_strength(held), Holding.SIM_STRAY_N * Holding.WALKER_THREAT])
	# A settlers' camp a horde falls on, that can't hold it: they relocate instead of fighting it out.
	var z3 := _zone(m, 2, [z, z2])
	var pl3: Dictionary = m.zone(z3).places[0]
	var s := _grp(m, "settlers", z3, 4, {"food": 10.0, "water": 10.0, "ammo": 0.0})
	m.set_home(s, z3, pl3)
	m.zone(z3).horde = {"n": 40, "since": m.tick()}
	var size0 := WorldGroup.size(s)
	WorldFights.horde_fight(m, s, z3)
	check(String((s.goal as Dictionary).get("kind", "")) == "relocate" and (s.home as Dictionary).is_empty() and String(pl3.holder) == "" and pl3.has("abandoned"),
		"a camp that can't hold against the horde is left: the group relocates to %s" % String((s.goal as Dictionary).get("zone", "")))
	check(WorldGroup.size(s) >= size0 - 1 and (m.w.events as Array).any(func(ev: Dictionary) -> bool: return String(ev.kind) == "abandoned" and String(s.id) in (ev.groups as Array)),
		"no fight to the end (%d of %d got away)" % [WorldGroup.size(s), size0])
	WorldGoals.decide(m, s)
	check(String((s.goal as Dictionary).get("kind", "")) == "relocate", "and they keep going (no second thoughts on the road)")
	var to := String((s.goal as Dictionary).get("zone", ""))
	_act_until_done(m, s, 40)
	check(String(s.zone) == to and (m.w.events as Array).any(func(ev: Dictionary) -> bool: return String(ev.kind) == "relocated" and String(s.id) in (ev.groups as Array)),
		"they come to %s%s" % [to, " and make camp" if not (s.home as Dictionary).is_empty() else ""])


## The hosted zone's household the catch-up sent running: the zone loaded again shows the signs.
func _test_holding_zone_up() -> void:
	print("A household left while you were away (call 143)")
	var layer := SurvivorsLayer.find(level)
	check(layer != null and layer._started, "the zone's people layer is up")
	if layer == null:
		return
	var zone := String(Survival.state().zone)
	var p0 := level.ground_point(player.global_position + Vector3(160.0, 0.0, 120.0))
	var a := layer.server_add_person(p0, {"traits": ["calm", "kind"], "want": {"kind": "place"}, "family": "away_fam", "kit": []})
	var b := layer.server_add_person(level.ground_point(p0 + Vector3(1.5, 0.0, 0.0)), {"traits": ["calm", "kind"], "want": {"kind": "place"}, "family": "away_fam", "kit": []})
	check(layer.body_of(String(a.id)) == null, "far from the player: records only")
	a["dead_find_test"] = true
	WorldSim.server_catch_up(1.0)
	var key := String(a.get("refugee_from", b.get("refugee_from", "")))
	var e := Holding.entry(key)
	check(key != "" and String(e.get("zone", "")) == zone and String(e.get("state", "")) == "abandoned" and not bool(e.get("signs", true)),
		"while you were away the dead found the unarmed household; they left (%s)" % String(e.get("text", "")))
	var journal0 := (Survival.state().get("journal", []) as Array).size()
	var n := Holding.server_zone_up(layer)
	e = Holding.entry(key)
	var lines := (Survival.state().get("journal", []) as Array).slice(journal0).map(func(j: Dictionary) -> String: return String(j.get("text", "")))
	check(n >= 1 and bool(e.get("signs", false)) and "handwritten_note" in (e.get("left", []) as Array) and lines.any(func(t: String) -> bool: return t.contains("door stood open")),
		"the zone up again: an empty place with signs of a hasty exit (%s)" % str(e.get("left", [])))
	check(not [a, b].any(func(r: Dictionary) -> bool: return String(r.status) == "out_there" and String(r.zone) == zone and SurvivorPerson.pos_of(r).distance_to(p0) < 10.0),
		"and nobody fought it out at home")


func _test_rumours() -> void:
	print("Rumours")
	var m := _iso(19)
	var z := _zone(m)
	var r := _grp(m, "raiders", z, 3)
	var s := _grp(m, "settlers", z, 3)
	var e := m.event(z, "horde", [], "a horde is gathering at the test place")
	var rp := String(r.members[0])
	var sp := String(s.members[0])
	var from_raider := Rumours.for_person(m.w, m.people, rp, 19)
	check(not from_raider.is_empty() and String(from_raider[0].truth) == "lie" and not String(from_raider[0].text).contains("horde"),
		"a raider lies: \"%s\"" % (String(from_raider[0].text) if not from_raider.is_empty() else ""))
	(m.people[sp] as Dictionary)["scout"] = true
	var from_scout := Rumours.for_person(m.w, m.people, sp, 19)
	check(not from_scout.is_empty() and String(from_scout[0].truth) == "true" and int(from_scout[0].event) == int(e.id) and String(from_scout[0].text).contains("horde"),
		"a scout tells it true: \"%s\"" % (String(from_scout[0].text) if not from_scout.is_empty() else ""))
	var told := WorldSim.rumours_for("nobody")
	check(told.is_empty(), "rumours_for a stranger to the world is empty")


func _test_determinism() -> void:
	print("Determinism")
	var outs: Array = []
	var start := String(Survival.state().start_zone)
	for i in 2:
		var table: Dictionary = (WorldSim.section().zones as Dictionary).duplicate(true)
		for zd: Dictionary in table.values():
			zd.traces = []
			zd.horde = {}
			for p: Dictionary in zd.places:
				p.holder = ""
				p.looted = -100.0
		var m := WorldModel.new({"cells": (WorldSim.section().get("cells", {}) as Dictionary).duplicate(true)}, {}, {}, 4242)
		m.now = 1.0
		m.player = {"zone": start, "place": "safehouse", "place_pos": [0.0, 0.0], "strength": 3.0, "home_strength": 0.0, "stocks_value": 1500.0,
			"can_take": false, "hunt_zone": start, "safe": false}
		m.setup(table, start)
		m.profile = {}
		var t0 := Time.get_ticks_usec()
		m.run(96, 2.0)
		print("  (perf) where a day's ticks went (ms): %s" % str((m.profile as Dictionary).keys().map(func(k: String) -> String: return "%s %.0f" % [k, int(m.profile[k]) / 1000.0])))
		outs.append([JSON.stringify(m.w), JSON.stringify(m.people), (Time.get_ticks_usec() - t0) / 96000.0, m.groups().size()])
	check(outs[0][0] == outs[1][0] and outs[0][1] == outs[1][1], "two sims from one seed agree after a world day (%d groups)" % int(outs[0][3]))
	check(float(outs[0][2]) < 100.0, "a far tick of the whole world costs %.1f ms" % float(outs[0][2]))
	print("  (perf) a far tick: %.2f ms for %d groups" % [float(outs[0][2]), int(outs[0][3])])


func _test_live() -> void:
	print("Live groups near the players")
	var live := WorldLive.of(level)
	check(live != null, "the hosted zone has its live layer")
	if live == null:
		return
	var zone := String(Survival.state().zone)
	var m := WorldSim.model()
	var at := Vector2(player.global_position.x + 60.0, player.global_position.z)
	var raiders := m.new_group("raiders", zone, at, m.rng_for("live_r"), 3)
	raiders.relations["player"] = -100.0
	var settlers := m.new_group("settlers", zone, at + Vector2(0.0, 40.0), m.rng_for("live_s"), 3)
	settlers.relations["player"] = 0.0
	live.server_tick()
	await _frames(5)
	var rb: Dictionary = (live.live.get(String(raiders.id), {}) as Dictionary).get("bodies", {})
	var sb: Dictionary = (live.live.get(String(settlers.id), {}) as Dictionary).get("bodies", {})
	check(rb.size() == 3 and rb.values().all(func(s: Soldier) -> bool: return is_instance_valid(s) and s.faction == &"hostile" and SquadAI.of(s) != null),
		"raiders within range come live: hostile, with SquadAI (%d)" % rb.size())
	var squad: Squad = (live.live.get(String(raiders.id), {}) as Dictionary).get("squad")
	var so: SquadOrders = (live.live.get(String(raiders.id), {}) as Dictionary).get("orders")
	check(squad != null and so != null and String(so.order.get("verb", "")) == "attack", "on a squad of their own, ordered to attack the players they hate (%s)" % (String(so.order.get("verb", "")) if so else "none"))
	check(sb.size() == 3 and sb.values().all(func(s: Soldier) -> bool: return is_instance_valid(s) and Person.kind_of(s) == &"survivor"), "settlers come live as people (%d)" % sb.size())
	check(bool(WorldSim.group(String(settlers.id)).get("live", false)), "and the records know they're live")
	var body: Soldier = sb.values()[0] if not sb.is_empty() else null
	var before := WorldGroup.relation(WorldSim.group(String(settlers.id)), "player")
	if body:
		var info := Harm.info_of(player)
		info["at"] = Soldier._now() + 10.0
		body.set_meta(Harm.META, info)
		live.server_tick()
	check(WorldGroup.relation(WorldSim.group(String(settlers.id)), "player") < before, "a shot at them where they see it costs standing (%.0f -> %.0f)" % [before, WorldGroup.relation(WorldSim.group(String(settlers.id)), "player")])
	if body:
		body.global_position += Vector3(5.0, 0.0, 0.0)
	live.server_fold(String(settlers.id))
	live.server_fold(String(raiders.id))
	await _frames(5)
	var srec: Dictionary = WorldSim.people().get(String(settlers.members[0]), {})
	check(not live.live.has(String(settlers.id)) and not bool(WorldSim.group(String(settlers.id)).get("live", false)) and not is_instance_valid(body),
		"far again, they fold back into their records")
	check(srec.get("pos") is Array and (srec.pos as Array).size() == 3, "their places kept")
	for g: Dictionary in [raiders, settlers]:
		WorldSim.group(String(g.id)).alive = false  # (out of the way)


func _test_threaded_tick() -> void:
	print("A far tick on a worker")
	var w := WorldSim.section()
	var t0 := int(w.get("tick", 0))
	var some := ""
	for gid: String in WorldModel._sorted((w.groups as Dictionary).keys()):
		if bool(w.groups[gid].alive) and String(w.groups[gid].kind) == "settlers":
			some = gid
			break
	sim.threaded = true
	sim.server_far_tick(float(w.get("t", WorldSim.world_now())) + WorldModel.TICK_MIN / 1440.0)
	check(sim._task >= 0, "the step went to the WorkerThreadPool")
	sim.server_change_relation(some, 7.0, "test")  # a change made here while it runs
	var deadline := Time.get_ticks_msec() + 20000
	while sim._task >= 0 and not WorkerThreadPool.is_task_completed(sim._task) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if sim._task >= 0:
		WorkerThreadPool.wait_for_task_completion(sim._task)
		sim._task = -1
		sim._apply_job()
	w = WorldSim.section()
	check(int(w.get("tick", 0)) == t0 + 1, "its result landed on the main thread (tick %d)" % int(w.get("tick", 0)))
	check(some == "" or (WorldSim.group(some).memory as Array).any(func(mm: Dictionary) -> bool: return String(mm.text) == "test"), "and a change made meanwhile wasn't lost")
	sim.threaded = false


func _test_settlement_demand() -> void:
	print("A demand on the players' settlement")
	await _wait_for(func() -> bool: return Settlement.exists(), 15.0)
	check(Settlement.exists(), "the farm is a settlement (the settlement lane's)")
	if not Settlement.exists():
		return
	var info := WorldSim.player_info()
	check(String(info.zone) == Settlement.zone() and bool(info.can_take) and info.has("defence"), "the sim reads its zone, stores and defence (%.0f, $%.0f of stores)" % [float(info.defence), float(info.stocks_value)])
	var m := WorldSim.model()
	var k := m.new_group("raiders", Settlement.zone(), Vector2(300.0, 300.0), m.rng_for("council"), 4)
	var votes0 := Council.votes().size()
	sim._do_action({"kind": "demand", "group": String(k.id), "name": String(k.name), "want": 300, "due": WorldSim.world_now() + 0.25})
	var votes := Council.votes()
	var v: Dictionary = votes[-1] if votes.size() > votes0 else {}
	check(not v.is_empty() and String((v.question as Dictionary).get("kind", "")) == "demand" and String(v.question.get("from", "")) == String(k.id),
		"the raiders' demand goes to the council: \"%s\"" % String((v.get("question", {}) as Dictionary).get("text", "")))
	(WorldSim.section().demands as Dictionary)[String(k.id)] = {"group": String(k.id), "paid": false, "due": WorldSim.world_now() + 0.25}
	if not v.is_empty() and Council._callbacks.has(int(v.id)):
		(Council._callbacks[int(v.id)] as Callable).call("pay")
	check(bool(((WorldSim.section().demands as Dictionary).get(String(k.id), {}) as Dictionary).get("paid", false)), "the council paying answers the demand")
	(WorldSim.section().demands as Dictionary).erase(String(k.id))
	WorldSim.group(String(k.id)).alive = false


func _test_catch_up() -> void:
	print("The catch-up")
	var w := WorldSim.section()
	var start := String(Survival.state().start_zone)
	var near := String(((w.zones as Dictionary)[start] as Dictionary).links[0])
	WorldSim.pressure_section()[near] = {"v": 95.0, "at": WorldSim.world_now(), "x": 0.0, "z": 0.0}
	var m := WorldSim.model()
	var k := m.new_group("raiders", start, Vector2(100.0, 100.0), m.rng_for("catchup"), 6)
	k.goal = {"kind": "raid", "zone": start, "place": "safehouse", "target": "player", "phase": "go", "since": 0, "work": 0}
	WorldSim.people()["test_comp"] = {"id": "test_comp", "name": "Test Companion", "status": "companion", "zone": near, "pos": [0.0, 0.0, 0.0]}
	var t0 := float(w.get("t", 0.0))
	var day0 := Survival.day() + Survival.hour() / 24.0
	var hours := WorldSim.server_catch_up(60.0)
	w = WorldSim.section()
	check(is_equal_approx(hours, WorldSim.CATCH_UP_DAYS * 24.0), "60 hours away runs %.0f: the bound (call 67)" % hours)
	check(float(w.t) - t0 <= WorldSim.CATCH_UP_DAYS + 0.01 and float(w.t) - t0 >= WorldSim.CATCH_UP_DAYS - 0.02, "the world moved %.2f days" % (float(w.t) - t0))
	check(Survival.day() + Survival.hour() / 24.0 > day0 + 1.9, "and the clock with it (day %d)" % Survival.day())
	var report: Dictionary = w.get("away_report", {})
	check(not (report.get("lines", []) as Array).is_empty(), "the report lists what happened near the farm: %s" % "; ".join(report.get("lines", [])))
	var journal: Array = Survival.state().get("journal", [])
	check(journal.any(func(j: Dictionary) -> bool: return String(j.text).begins_with("While you were away")), "in the journal")
	var raided := (w.events as Array).any(func(e: Dictionary) -> bool: return String(e.kind) == "raid" and "player" in (e.groups as Array))
	var d: Dictionary = (w.demands as Dictionary).get(String(k.id), {})
	check(not raided and not d.is_empty() and not bool(d.get("deferred", true)) and float(d.due) > WorldSim.world_now(), "the farm wasn't hit: the raid waits as a demand on return")
	check(String((WorldSim.people()["test_comp"] as Dictionary).status) == "companion", "companions are safe")
	WorldSim.people().erase("test_comp")
	(w.demands as Dictionary).erase(String(k.id))
	WorldSim.group(String(k.id)).alive = false
	check(WorldSim.server_catch_up(0.1) == 0.0, "no time away, no catch-up")


func _test_goal_modes() -> void:
	print("Goal modes")
	var g: Dictionary = WorldSim.section().goal
	var st := WorldSim.goal_state()
	check(String(st.mode) == "evac" and bool(st.evac) and WorldSim.group(String(st.evac_group)).get("kind", "") == "enclave", "evac: the enclave holds the evac at %s (%s)" % [String(st.evac_zone), String(st.text)])
	var day := int(Survival.state().day)
	Survival.state()["day"] = 25
	check(WorldSim.refill_mult() > 1.0 and WorldSim.dead_mult() > 1.0, "evac: the dead refill and thicken as the season goes (x%.2f, x%.2f)" % [WorldSim.refill_mult(), WorldSim.dead_mult()])
	Survival.state()["day"] = day
	g.mode = "sandbox"
	st = WorldSim.goal_state()
	check(not bool(st.evac) and is_equal_approx(float(st.refill_mult), 1.0) and is_equal_approx(float(st.dead_mult), 1.0), "sandbox: no evac, local pressure only (%s)" % String(st.text))
	g.mode = "clear"
	st = WorldSim.goal_state()
	check(float(st.refill_mult) > 1.5 and not bool(st.evac), "clear: no evac, faster refill (x%.1f)" % float(st.refill_mult))
	sim._update_held()
	check((WorldSim.goal_state().held as Array).has(String(Survival.state().start_zone)), "the farm's zone is held by the players' presence")
	var saved := {}
	for z: String in WorldSim.section().zones:
		saved[z] = float(WorldSim.section().zones[z].dead)
		WorldSim.section().zones[z].dead = 0.05
	sim._check_goal()
	check(bool(WorldSim.goal_state().won), "every zone quiet at once: the map is clear, won")
	var journal: Array = Survival.state().get("journal", [])
	check(String(journal[-1].text).contains("clear"), "said in the journal: \"%s\"" % String(journal[-1].text))
	for z: String in saved:
		WorldSim.section().zones[z].dead = saved[z]
	g.won = false
	g.mode = "evac"
	var enclave := WorldSim.group(String(g.evac_group))
	enclave.alive = false
	sim._check_goal()
	check(bool(WorldSim.goal_state().lost) and String(WorldSim.goal_state().text) == "The evac is gone", "evac: the enclave gone, the evac is lost")
	enclave.alive = true
	g.lost = false
	g.price_paid = true
	Survival.state()["zone"] = String(g.evac_zone)
	sim._check_goal()
	check(bool(WorldSim.goal_state().won), "evac: at the evac with the price paid, won")
	Survival.state()["zone"] = String(Survival.state().start_zone)


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
	if Survival.world != "":
		GameState.delete_save()
		Survival.running = false
		Campaign.reset_campaign()
	print("WORLDSIM TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
