extends Node
## Contractor: Fallen's world events, loot states, drop-in co-op and the mod kit (calls 124-127;
## docs/survival_events.md, docs/fallen_modding.md): a supply drop makes a place, a race for every
## group in reach and a journal line, and its crate comes out in the hosted zone; a convoy, a downed
## helicopter, a burning town (its glow) and a storm (a closed crossing) run their windows; the
## world option sets the frequency; a bell rung raises the pressure and the companions remember who;
## a searched box looks picked over and the save keeps it; a hidden cache's clue leads to it; a
## locked box opens with its key or a crowbar's pry; boxes refill only where people pass; a joiner
## lands at the farm with the starter kit, the journal goes to peers, a leaver sleeps at home and
## wakes there; ModKit loads a mod from a folder (an item patched and one added, a kind of the dead
## added) and skips a broken one; the validator passes the shipped data and fails a broken mod; a
## world card exports and imports. The live convoy: a column on the zone's main road that advances,
## halts at a wreck and goes on once it's cleared, hails into a trade (the enclave's by standing),
## turns on a robber (standing, an event), meets a raider ambush ahead; the wagon without a road.
## The downed crew: "Come with me", brought to an enclave post (standing, the reward, the journal),
## their tags, and the enclave's reclaim (a little standing lost when a player was near).

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier
var sim: WorldSim
var start := ""


func _ready() -> void:
	get_tree().create_timer(380.0).timeout.connect(func() -> void:
		print("FALLENEVENTS TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _test_new_world()
	if level != null and player != null and sim != null:
		_test_supply_drop()
		_test_live_drop()
		_test_other_events()
		_test_live_convoy()
		_test_convoy_robbed_and_ambush()
		_test_convoy_no_road()
		_test_crew_home()
		_test_frequency_and_roll()
		await _test_bell()
		_test_searched_and_saved()
		_test_hidden_and_clue()
		await _test_locks()
		_test_refill()
		_test_coop()
		_test_modkit()
		_test_validator()
		_test_world_card()
	_finish()


func _test_new_world() -> void:
	print("A new world")
	check(Survival.server_new_world(main, "test_fallenevents" + tag, 4242), "the menu's New world hosts one")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 25.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	sim = WorldSim.get_sim()
	check(player != null and sim != null and CoopFallen.get_coop() != null, "the survivor is in; the world sim and CoopFallen are under Survival")
	if sim == null:
		return
	sim.enabled = false  # (the test drives the ticks)
	sim.threaded = false
	start = String(Survival.state().get("start_zone", ""))
	for i in 60:
		await get_tree().process_frame


## A zone linked to the farm's (near the players), with places.
func _near_zone(skip: Array = []) -> String:
	var zones: Dictionary = WorldSim.section().get("zones", {})
	for z: String in (zones.get(start, {}) as Dictionary).get("links", []):
		if zones.has(z) and not z in skip and not ((zones[z] as Dictionary).get("places", []) as Array).is_empty():
			return z
	return ""


func _journal_has(text: String) -> bool:
	for e: Dictionary in Survival.state().get("journal", []):
		if String(e.get("text", "")).to_lower().contains(text.to_lower()):
			return true
	return false


# --- World events -----------------------------------------------------------------------------------

func _test_supply_drop() -> void:
	print("A supply drop")
	var z := _near_zone()
	check(z != "", "a zone next to the farm's (%s)" % z)
	if z == "":
		return
	var m := WorldSim.model()
	var racer := m.new_group("scavengers", z, Vector2.ZERO, m.rng_for("test_racer", "made"), 3)
	racer.kind = "scavengers"
	var r := WorldEvents.begin(m, "supply_drop", z)
	check(not r.is_empty() and String(r.place) != "" and String(r.state) == "open" and float(r.until) > float(r.t), "it has a place, a window (%s, %.2f days)" % [r.get("place", ""), float(r.get("until", 0.0)) - float(r.get("t", 0.0))])
	var place := WorldRegions.place(m.zone(z), String(r.get("place", "")))
	check(float(place.get("richness", 0.0)) >= 3.0, "the place is rich while it lasts (%.1f)" % float(place.get("richness", 0.0)))
	var goal: Dictionary = racer.get("goal", {})
	check(String(goal.get("kind", "")) == "forage" and String(goal.get("place", "")) == String(r.place) and int(goal.get("event", 0)) == int(r.id),
		"a group in reach races for it: a forage goal there (%s)" % [goal])
	var e := Intel.event_by_id(int(r.id))
	check(String(e.get("kind", "")) == "supply_drop" and ((racer.get("intel", {}) as Dictionary).has(str(int(r.id)))), "it's an event in the pool the zone's groups know (the rumour layer's)")
	var bc := (WorldSim.section().events as Array).filter(func(x: Dictionary) -> bool: return String(x.kind) == "broadcast" and int(x.id) > int(r.id))
	check(not bc.is_empty(), "the enclave broadcasts it (the radio's enclave channel): %s" % (String(bc[0].text) if not bc.is_empty() else "none"))
	sim._after_step(m)
	check(_journal_has("supply drop came down"), "near the players, it's in the journal")
	place["looted"] = m.now + 0.01
	m.now += 0.02
	WorldEvents.tick(m)
	check(String(r.state) == "done" and String(r.outcome) == "taken", "a group foraging it takes it: done, taken (%s)" % String(r.outcome))
	check((WorldSim.section().events as Array).any(func(x: Dictionary) -> bool: return String(x.kind) == "supply_taken"), "and that's an event too")
	racer.alive = false


func _test_live_drop() -> void:
	print("A supply drop in the zone being played")
	var m := WorldSim.model()
	var r := WorldEvents.begin(m, "supply_drop", start)
	WorldEvents.server_live(level)
	var cache := LootStates.cache_by_uid(level, WorldEvents.cache_uid(int(r.get("id", 0))))
	check(cache != null and cache.cargo_hold.entries().size() >= 1 and bool(r.get("spawned", false)), "its crate comes down where it fell, with the drop's loot (%d entries)" % (cache.cargo_hold.entries().size() if cache else -1))
	if cache == null:
		return
	cache.global_position = player.global_position + Vector3(1.0, 0.0, 0.0)
	var rel0 := WorldGroup.relation(WorldSim.group(String((WorldSim.section().goal as Dictionary).get("evac_group", ""))), "player")
	check(cache.server_open_for(player) == "" and String(r.state) == "done" and String(r.outcome) == "players", "opening it first claims it for the players (%s)" % String(r.outcome))
	var rel1 := WorldGroup.relation(WorldSim.group(String((WorldSim.section().goal as Dictionary).get("evac_group", ""))), "player")
	check(rel1 < rel0, "the enclave minds: it was theirs (%.0f -> %.0f)" % [rel0, rel1])


func _test_other_events() -> void:
	print("A convoy, a downed helicopter, a burning town, a storm")
	var iso := WorldModel.new(WorldSim.section().duplicate(true), WorldSim.people().duplicate(true), WorldSim.pressure_section().duplicate(true), WorldSim.world_seed())
	iso.now = WorldSim.world_now()
	iso.hosted = start
	var road := ""
	for z: String in WorldModel._sorted(iso.zones().keys()):
		if z != start and (iso.zone(z).get("links", []) as Array).size() >= 3:
			road = z
			break
	var c := WorldEvents.begin(iso, "convoy", road)
	check(not c.is_empty() and String(c.get("to", "")) != "" and String(c.get("column", "")) in ["enclave", "trader"], "a %s column moves through %s toward %s" % [c.get("column", "?"), road, c.get("to", "?")])
	var raid := iso.new_group("raiders", road, Vector2.ZERO, iso.rng_for("test_raiders", "made"), 5)
	raid.kind = "raiders"
	iso.now = float(c.get("until", iso.now)) + 0.01
	WorldEvents.tick(iso)
	check(String(c.get("state", "")) == "done" and String(c.get("outcome", "")) in ["ambushed", "passed"], "its window ends: %s" % String(c.get("outcome", "")))
	var h := WorldEvents.begin(iso, "heli_down", road)
	var crew: Array = h.get("crew", [])
	check(crew.size() == 2 and crew.all(func(pid: String) -> bool: return String((iso.people.get(pid, {}) as Dictionary).get("status", "")) == "out_there"),
		"a helicopter down: its crew of %d are lone survivors at the wreck" % crew.size())
	h["near"] = true  # (a player came near them and left them: HeliCrew's tick sets it)
	var enc_iso := iso.group(String((iso.w.get("goal", {}) as Dictionary).get("evac_group", "")))
	var before := WorldGroup.relation(enc_iso, "player")
	iso.now = float(h.get("until", iso.now)) + 0.01
	WorldEvents.tick(iso)
	check(String(h.get("outcome", "")) == "recovered", "with the crew still out there at the window's end, the enclave takes them back (%s)" % String(h.get("outcome", "")))
	check(enc_iso.is_empty() or WorldGroup.relation(enc_iso, "player") < before, "a player who was near and left them costs a little standing (%.0f -> %.0f)" % [before, WorldGroup.relation(enc_iso, "player")])
	# A burning town near the farm glows on its horizon.
	var near := _near_zone()
	var m := WorldSim.model()
	var b := WorldEvents.begin(m, "burning", near)
	check(WorldEvents.glow(start) > 0.0 and WorldEvents.glow(start) <= 0.5, "a town burning next door glows on the farm's sky (%.2f)" % WorldEvents.glow(start))
	var g := WorldEvents.apply_glow(level)
	var dn := DayNight.current()
	check(g > 0.0 and (dn == null or float(dn.get_meta(WorldEvents.GLOW_META, 0.0)) > 0.0), "the sky's glow hook carries it (DayNight's \"glow\" meta %.2f)" % (float(dn.get_meta(WorldEvents.GLOW_META, 0.0)) if dn else -1.0))
	b.state = "done"
	WorldEvents.apply_glow(level)
	# A storm takes a bridge out.
	var s := WorldEvents.begin(m, "storm", near)
	var to := String(s.get("to", ""))
	check(to != "" and not m.crossing_open(near, to) and (WorldSim.section().get("crossings", {}) as Dictionary).has(WorldModel.crossing_key(near, to)),
		"a storm closes the crossing between %s and %s" % [near, to])
	Infrastructure.server_set_crossing(near, to, true)
	check(m.crossing_open(near, to), "the bridge repaired opens it again (Infrastructure)")


# --- The live convoy and the crew ------------------------------------------------------------------

## The scene for a column: nothing of the zone's own on the road (its cars, the dead) for these checks.
func _clear_road() -> void:
	for z: Soldier in Survival.zombies(level):
		z.queue_free()
	var layer := VehicleLayer.of(level)
	if layer:
		for v: Vehicle in layer.vehicles():
			if not v.has_meta(&"fallen_convoy"):
				v.set_meta(&"convoy_cleared", true)


func _live_convoy(column: String, extra := {}) -> FallenConvoy:
	var m := WorldSim.model()
	var r := WorldEvents.begin(m, "convoy", start, {"column": column})
	if r.is_empty():
		return null
	r["manual"] = true
	r["ambush_by"] = "-"
	r.merge(extra, true)
	WorldEvents.server_live(level)
	var c := FallenConvoy.of_event(level, int(r.id))
	if c:
		c.hail_ok = false
	return c


func _test_live_convoy() -> void:
	print("A live convoy on the road")
	var road := FallenConvoy.main_road(level)
	check(road.size() >= 2, "the zone has a main road (%d points)" % road.size())
	if road.size() < 2:
		return
	_clear_road()
	var c := _live_convoy("trader")
	check(c != null, "a convoy in the zone being played comes in as a live column")
	if c == null:
		return
	var r := c.rec
	var n_people := c.people.size() + (1 if c.trader else 0)
	check(c.vehicles.size() >= 2 and c.vehicles.size() <= 3 and n_people >= 4 and n_people <= 8,
		"a trader's cart train: %d vehicles, %d people (drivers, guards, the trader)" % [c.vehicles.size(), n_people])
	check(c.cargo_vehicle != null and c.cargo_vehicle.cargo() != null and not c.cargo_vehicle.cargo_hold.entries().is_empty(),
		"its cargo is a real hold on the cart (%d entries)" % (c.cargo_vehicle.cargo_hold.entries().size() if c.cargo_vehicle and c.cargo_vehicle.cargo_hold else -1))
	check(LootStates.cache_by_uid(level, WorldEvents.cache_uid(int(r.id))) == null, "no wagon cache when it's on the road")
	var lv := c.lead()
	check(lv != null and c.along_of(lv.global_position)[1] < 1.5, "the lead is on the road (%.1f m off)" % (c.along_of(lv.global_position)[1] if lv else -1.0))
	var s0 := c.s
	var p0 := lv.global_position if lv else Vector3.ZERO
	for i in 20:
		c.server_step(0.5)
	check(c.state == "moving" and c.s > s0 + 5.0 and lv != null and lv.global_position.distance_to(p0) > 5.0 and c.along_of(lv.global_position)[1] < 1.5,
		"it advances along the road (%.1f -> %.1f m of %.0f, %s)" % [s0, c.s, c.length, c.state])
	check(bool(r.get("live", false)) and float(r.get("s", 0.0)) > s0, "the record knows it's live and how far it got")
	# A wreck across the road ahead.
	var at := c.point_at(c.s + 8.0)
	var wreck := VehicleLayer.of(level).server_spawn("technical", Transform3D(Basis(), at + Vector3.UP * 0.3), "", &"player")
	if wreck:
		wreck.set_meta(&"no_save", true)
		wreck.freeze = true
		wreck.global_position = at + Vector3.UP * 0.3
	c.server_step(0.5)
	var s_h := c.s
	check(wreck != null and c.state == "halted" and c.why == "wreck" and not c.riding, "it halts at a wreck on the road and they get down (%s, %s)" % [c.state, c.why])
	for i in 4:
		c.server_step(0.5)
	check(c.state == "halted" and is_equal_approx(c.s, s_h), "it holds while they clear it")
	for i in 20:
		c.server_step(0.5)
	check(wreck != null and wreck.has_meta(&"convoy_cleared") and c.state == "moving" and c.s > s_h + 1.0 and c.riding,
		"the wreck pushed off the road, they mount up and go on (%.1f -> %.1f)" % [s_h, c.s])
	if wreck:
		wreck.queue_free()
	# Hailed: the trader's stock on the barter screen.
	var line := c.server_hail(player)
	var trec: Dictionary = WorldSim.people().get(c.trader_id, {})
	check(c.state == "hailed" and line != "" and Barter.trader_problem(trec) == "", "walking up openly hails it: it holds (\"%s\")" % line)
	var deal := Barter.deal(player, trec)
	var kit_ids: Array = (trec.get("kit", []) as Array).map(func(e: Dictionary) -> String: return String(e.id))
	check(not kit_ids.is_empty() and (deal.theirs as Array).any(func(row: Dictionary) -> bool: return String(row.id) in kit_ids),
		"its trader deals from the column's stock (%d lines)" % (deal.theirs as Array).size())
	if c.trader:
		c.trader.global_position = player.global_position + Vector3(1.5, 0.0, 0.0)
		TalkMenu.server_talk(SurvivorsLayer.find(level), player, c.trader, "trade", {})
		var ts := TradeScreen.current()
		check(ts == null or (ts.visible and String(ts.deal.get("trader", "")) == c.trader_id), "the talk menu's Trade opens the barter screen on him")
		if ts:
			ts.close()
	c._hail_t = 9999.0  # (the hail's hold over)
	c.server_step(0.5)
	check(c.state == "moving", "left alone, it goes on")
	# The enclave's sells only to its friends.
	var gid := String((WorldSim.section().goal as Dictionary).get("evac_group", ""))
	if gid != "":
		var qrec := {"id": "test_conv_qm", "status": "convoy", "world_group": gid, "enclave_quartermaster": true, "min_standing": 10.0, "kit": []}
		var rel := WorldGroup.relation(WorldSim.group(gid), "player")
		sim.server_change_relation(gid, -rel)
		check(Barter.trader_problem(qrec) != "", "an enclave convoy won't sell to a stranger (%s)" % Barter.trader_problem(qrec))
		sim.server_change_relation(gid, 20.0)
		check(Barter.trader_problem(qrec) == "", "and sells to a friend of the enclave (standing 20)")
		sim.server_change_relation(gid, rel - 20.0)
	# It reaches the far edge: through, gone.
	c.s = c.length - 1.0
	c.server_step(1.0)
	check(String(r.get("outcome", "")) == "passed" and String(r.state) == "done" and c.is_queued_for_deletion() and not WorldSim.people().has(c.trader_id),
		"at the far edge it's through (%s) and leaves the zone" % String(r.get("outcome", "")))


func _test_convoy_robbed_and_ambush() -> void:
	print("Robbing a convoy, and a raider ambush")
	if FallenConvoy.main_road(level).size() < 2:
		return
	_clear_road()
	var gid := String((WorldSim.section().goal as Dictionary).get("evac_group", ""))
	var c := _live_convoy("enclave" if gid != "" else "trader")
	check(c != null and (gid == "" or String(c.rec.get("group", "")) == gid), "an enclave column (%s)" % (c.column if c else "none"))
	if c == null:
		return
	var r := c.rec
	var rel0 := WorldGroup.relation(WorldSim.group(gid), "player") if gid != "" else 0.0
	var who: Soldier = c.guards[0] if not c.guards.is_empty() else c.people[0]
	Harm.note_hit(who, player)
	c.server_step(0.2)
	var rel1 := WorldGroup.relation(WorldSim.group(gid), "player") if gid != "" else 0.0
	check(c.state == "hostile" and String(r.get("outcome", "")) == "robbed" and who.faction == &"hostile", "shooting one of its people turns the column on you (%s)" % c.state)
	check(gid == "" or rel1 <= rel0 - 25.0, "the owner's standing falls (%.0f -> %.0f)" % [rel0, rel1])
	var ev := (WorldSim.section().events as Array).filter(func(x: Dictionary) -> bool: return String(x.kind) == "convoy_robbed" and int(x.id) > int(r.id) and String(x.get("actor", "")) == Survival.profile_of(player))
	check(not ev.is_empty() and String(ev[0].text).contains(Survival.survivor_name(player)), "a world event names the robber (%s)" % (String(ev[0].text) if not ev.is_empty() else "none"))
	c.server_despawn()
	# The ambush, rolled: raiders wait up the road.
	var m := WorldSim.model()
	var raid := m.new_group("raiders", start, Vector2.ZERO, m.rng_for("test_conv_raiders", "made"), 4)
	raid.kind = "raiders"
	var a := _live_convoy("trader", {"ambush_by": String(raid.id)})
	check(a != null and String(a.rec.get("ambush_by", "")) == String(raid.id), "a column with the ambush rolled")
	if a == null:
		return
	a.s = maxf(a.s, a.length * FallenConvoy.num("ambush_at", 0.35))
	a.server_step(0.1)
	check(a.raiders.size() >= 3 and a.raiders.size() <= 5 and a.raiders.all(func(x: Soldier) -> bool: return x.faction == &"hostile" and a.along_of(x.global_position)[0] > a.s + 20.0),
		"%d raiders come out ahead on the road" % a.raiders.size())
	a.server_step(0.1)
	check(a.state == "halted" and a.why == "raiders", "the column halts and fights (%s, %s)" % [a.state, a.why])
	for g: Soldier in a.guards:
		g.vitals.server_kill()
	a.server_step(0.1)
	check(a.state == "lost" and String(a.rec.get("outcome", "")) == "ambushed", "the guards all down: the column is lost to the raiders (%s)" % String(a.rec.get("outcome", "")))
	for x: Soldier in a.raiders:
		if is_instance_valid(x):
			x.queue_free()
	a.server_despawn()
	raid.alive = false


func _test_convoy_no_road() -> void:
	print("A convoy where the zone has no road")
	FallenConvoy.force_no_road = true
	var m := WorldSim.model()
	var r := WorldEvents.begin(m, "convoy", start, {"column": "trader"})
	WorldEvents.server_live(level)
	FallenConvoy.force_no_road = false
	var cache := LootStates.cache_by_uid(level, WorldEvents.cache_uid(int(r.get("id", 0))))
	check(FallenConvoy.of_event(level, int(r.get("id", 0))) == null and cache != null and cache.cargo_hold.entries().size() >= 1, "it's the column's wagon, a cache, as before")
	if cache == null:
		return
	cache.global_position = player.global_position + Vector3(1.0, 0.0, 0.0)
	check(cache.server_open_for(player) == "" and String(r.get("outcome", "")) == "robbed", "and opening it robs it (%s)" % String(r.get("outcome", "")))


func _test_crew_home() -> void:
	print("The downed crew brought home")
	var layer := SurvivorsLayer.find(level)
	var m := WorldSim.model()
	var h := WorldEvents.begin(m, "heli_down", start)
	var crew: Array = h.get("crew", [])
	check(layer != null and crew.size() == 2, "a helicopter down in the zone being played, its crew of %d" % crew.size())
	if layer == null or crew.size() < 2:
		return
	var a: Dictionary = WorldSim.people()[String(crew[0])]
	var b: Dictionary = WorldSim.people()[String(crew[1])]
	var line := HeliCrew.server_come(layer, player, a)
	var body := layer.body_of(String(a.id))
	check(line != "" and String(a.status) == "companion" and HeliCrew.is_escort(a) and body != null, "\"Come with me\": they follow as a companion (%s)" % String(a.status))
	var acts: Array = []
	if body:
		acts = TalkMenu.actions_for(player, body, InteractionMenu.SQUADMATE)
	check(acts.any(func(e: Dictionary) -> bool: return StringName(e.id) == &"talk_crew_pickup"), "an escorted one's menu offers a radio pickup")
	check(HeliCrew.radio_problem(player) != "" or FallenRadio.has_radio(player), "a pickup needs a working radio (%s)" % HeliCrew.radio_problem(player))
	# The other dead: their tags.
	b.status = "dead"
	check(HeliCrew.server_take_tags(player, b) != "" and HeliCrew.tags_of(Survival.profile_of(player)).has(String(b.id)), "a dead one's tags taken")
	# At an enclave post.
	var gid := Enclave.gid() if Enclave.is_set_up() else String((WorldSim.section().goal as Dictionary).get("evac_group", ""))
	var rel0 := WorldGroup.relation(WorldSim.group(gid), "player")
	var med0 := 0
	var had := {"serum": player.inventory.count_of(&"serum")}
	for row: Array in HeliCrew.cfg().get("reward", []):
		med0 += player.inventory.count_of(StringName(String(row[0])))
		had[String(row[0])] = player.inventory.count_of(StringName(String(row[0])))
	var j0 := (Survival.state().get("journal", []) as Array).size()
	var faked := Enclave.is_set_up()
	if faked:
		Enclave.posts()["test_post"] = {"id": "test_post", "kind": "post", "name": "Test Post", "zone": start, "place": "", "pos": [player.global_position.x, player.global_position.z], "members": [], "kit": {}}
		body.global_position = player.global_position + Vector3(2.0, 0.0, 0.0)
		HeliCrew.server_tick(layer)
		Enclave.posts().erase("test_post")
	else:
		HeliCrew.server_deliver(layer, player, [String(a.id), String(b.id)], "enclave")
	var rel1 := WorldGroup.relation(WorldSim.group(gid), "player")
	var med1 := 0
	for row: Array in HeliCrew.cfg().get("reward", []):
		med1 += player.inventory.count_of(StringName(String(row[0])))
	check(bool(a.get("heli_home", false)) and String(a.status) != "companion" and layer.body_of(String(a.id)) == null, "walked to an enclave post, they're home (%s)" % String(a.status))
	check(gid == "" or rel1 >= rel0 + 19.0, "the enclave's standing up for the crew and the tags (%.0f -> %.0f)" % [rel0, rel1])
	check(med1 > med0 or player.inventory.count_of(&"serum") > 0, "the reward: medical stock (%d -> %d)" % [med0, med1])
	var lines := (Survival.state().get("journal", []) as Array).slice(j0)
	check(lines.any(func(e: Dictionary) -> bool: return String(e.get("text", "")).contains("home to the enclave")), "a journal line")
	check(gid == "" or (WorldSim.section().events as Array).any(func(x: Dictionary) -> bool: return String(x.kind) == "broadcast" and String(x.text).contains("thanks")), "and the enclave's thanks on the radio")
	check(String(h.get("outcome", "")) == "delivered", "the event's done: delivered (%s)" % String(h.get("outcome", "")))
	for id: String in had:  # (the reward back out of his kit: the later checks want the room)
		while player.inventory.count_of(StringName(id)) > int(had[id]):
			if not player.inventory.remove_one(StringName(id)):
				break


func _test_frequency_and_roll() -> void:
	print("How often they come, and the roll")
	Survival.server_set_options({"world": "high"})
	WorldEvents.server_after_step()
	check(is_equal_approx(float(WorldSim.section().get("event_mult", 0.0)), 1.5), "the world option sets the frequency (high: x%.1f)" % float(WorldSim.section().get("event_mult", 0.0)))
	Survival.server_set_options({"world": "normal"})
	WorldEvents.server_after_step()
	var iso := WorldModel.new(WorldSim.section().duplicate(true), WorldSim.people().duplicate(true), WorldSim.pressure_section().duplicate(true), WorldSim.world_seed())
	iso.now = WorldSim.world_now()
	iso.hosted = start
	var kinds := {}
	for i in 60:
		iso.w["tick"] = 1000 + i * 96
		var r := WorldEvents.roll(iso)
		if not r.is_empty():
			kinds[String(r.kind)] = true
	check(kinds.size() >= 3, "a day's roll gives events of several kinds over two months (%s)" % ", ".join(PackedStringArray(kinds.keys())))


func _test_bell() -> void:
	print("A bell rung")
	var bells := level.get_node_or_null(NodePath(FallenBell.HOLDER))
	check(bells != null, "the zone's bells are placed (%d)" % (bells.get_child_count() if bells else 0))
	var bell := FallenBell.new()
	bell.name = "TestBell"
	bell._at = player.global_position + Vector3(1.0, 0.0, 0.0)
	bell.position = bell._at
	level.add_child(bell)
	for i in 3:
		await get_tree().process_frame
	var comp := {"id": "test_comp" + tag, "name": "Ann Test", "status": "companion", "opinion_of_players": {}}
	WorldSim.people()[String(comp.id)] = comp
	var p0 := Survival.pressure(level)
	var acts := bell.interaction_actions(player)
	check(not acts.is_empty() and String(acts[0].disabled) == "", "standing by it: \"Ring the bell\"")
	var line := bell.server_ring_by(player)
	check(line != "" and Survival.pressure(level) > p0, "ringing it raises the zone's pressure (%.1f -> %.1f)" % [p0, Survival.pressure(level)])
	check(Lures.active.any(func(l: Dictionary) -> bool: return String(l.kind) == WorldEvents.BELL_LURE), "it keeps ringing: a lure the dead walk to")
	var ev := (WorldSim.section().events as Array).filter(func(x: Dictionary) -> bool: return String(x.kind) == "bell" and String(x.get("actor", "")) == Survival.profile_of(player))
	check(not ev.is_empty() and _journal_has("rang the bell"), "an event carrying who rang it, and the journal's line")
	var prof := Survival.profile_of(player)
	check(SurvivorPerson.opinion_of(comp, prof) < 0.0 and not CoopFallen.memories_of(comp, prof).is_empty(), "a companion remembers who did it (%s; opinion %.0f)" % [CoopFallen.memories_of(comp, prof), SurvivorPerson.opinion_of(comp, prof)])
	check(bell.server_ring_by(player) == "", "not again straight away")
	for i in range(Lures.active.size() - 1, -1, -1):
		if String(Lures.active[i].kind) == WorldEvents.BELL_LURE:
			Lures.active.remove_at(i)
	bell.queue_free()


# --- Loot that shows its state -----------------------------------------------------------------------

func _box(uid: String, items: Array = [{"id": "canned_meat", "count": 2}]) -> WorldCache:
	var c := level.cache_spawner.spawn({"uid": uid, "pos": player.global_position + Vector3(1.5, 0.0, 0.5), "yaw": 0.0, "label": "Cache"}) as WorldCache
	if c:
		c.server_seed(items)
	return c


func _test_searched_and_saved() -> void:
	print("A searched box looks it, and the save keeps it")
	var c := _box("test_box_a")
	check(c != null and c.look() == "fresh" and not c.searched, "a fresh box")
	if c == null:
		return
	check(c.server_open_for(player) == "" and c.searched and c.look() == "searched" and c.get_node_or_null(^"Visual/Lid") != null, "opened, it's picked over: lid up, dulled")
	GameState.save_zone()
	GameState.load_zone()
	check(bool((GameState.caches.get("test_box_a", {}) as Dictionary).get("searched", false)), "the zone save keeps it searched")
	var again := WorldCache.new("Cache")
	again.uid = "test_box_a"
	again.name = "TestBoxReload"
	level.add_child(again)
	again.server_fill([])
	check(again.searched and again.look() == "searched", "a reload shows it picked over")
	again.queue_free()


func _test_hidden_and_clue() -> void:
	print("Hidden caches and their clues")
	var rec := LootStates.zone_rec(start)
	var hidden: Array = rec.get("hidden", [])
	check(hidden.size() >= LootStates.HIDDEN.x and hidden.size() <= LootStates.HIDDEN.y, "the farm's zone has %d hidden caches (by the seed)" % hidden.size())
	if hidden.is_empty():
		return
	var h: Dictionary = hidden[0]
	var cache := LootStates.cache_by_uid(level, String(h.uid))
	check(cache != null and cache.hidden and cache.look() == "hidden" and cache.cargo_hold.entries().size() >= 2, "it's in the ground, half buried, the richest box (%d entries)" % (cache.cargo_hold.entries().size() if cache else -1))
	var note := level.items.get_node_or_null(NodePath(String(h.clue))) as WorldItem
	check(note != null and String(note.state.get("clue", "")) == String(h.uid) and String(note.state.get("text", "")) != "", "a note lies elsewhere: \"%s\"" % (String(note.state.get("text", "")) if note else "none"))
	var p: Array = h.pos
	var target: Variant = LootStates.clue_target(String(h.text), start)
	if target is Vector2:
		var d := (target as Vector2).distance_to(Vector2(float(p[0]), float(p[2])))
		check(d < 6.0, "its words lead to the cache (%.1f m off, from %s)" % [d, String(h.landmark)])
	else:
		check(String(h.text).contains("buried"), "(no landmark in this zone: the note still says it's buried)")
	GameState.item_taken(String(h.clue))
	LootStates.server_tick(level)
	var marks := SurvivalMap.marks(start).filter(func(mk: Dictionary) -> bool: return String(mk.get("text", "")).begins_with("A cache?"))
	check(not marks.is_empty() and SurvivalMap.mark_pos(marks[0]).distance_to(Vector2(float(p[0]), float(p[2]))) <= LootStates.CLUE_MARK_SPREAD_M + 0.5,
		"picking the note up marks the cache's ground on the map")


func _test_locks() -> void:
	print("Locked boxes: a key or a pry")
	var rec := LootStates.zone_rec(start)
	var locked: Dictionary = rec.get("locked", {})
	check(locked.size() <= LootStates.MAX_LOCKED, "at most %d of the zone's boxes are locked (%d)" % [LootStates.MAX_LOCKED, locked.size()])
	for uid: String in locked:
		var home := LootStates.cache_by_uid(level, String(locked[uid]))
		var lc := LootStates.cache_by_uid(level, uid)
		var key_there := false
		if home != null:
			for e: Dictionary in home.cargo_hold.entries():
				if StringName(String(e.id)) == LootStates.KEY_ITEM and String((e.get("state", {}) as Dictionary).get("opens", "")) == uid:
					key_there = true
		check(lc != null and lc.key_id == LootStates.KEY_ITEM and key_there, "%s is locked; its key lies in %s" % [uid, String(locked[uid])])
	var c := _box("test_box_locked")
	c.key_id = LootStates.KEY_ITEM
	check(c.is_locked() and c.lock_problem(player) != "" and c.server_open_for(player) != "", "a locked box won't open without its key")
	player.inventory.take(LootStates.KEY_ITEM, 1, {"opens": "some_other_box"})
	check(c.lock_problem(player) != "", "another box's key doesn't fit")
	player.inventory.take(LootStates.KEY_ITEM, 1, {"opens": "test_box_locked"})
	check(c.lock_problem(player) == "" and c.server_open_for(player) == "" and c.unlocked and c.searched, "its own key opens it")
	var pry := _box("test_box_pry")
	pry.key_id = LootStates.KEY_ITEM
	var no_bar := not LootStates.has_pry_tool(player)
	if no_bar:
		check(LootStates.server_start_pry(pry, player) == "You need a crowbar", "no crowbar, no pry")
	player.inventory.take(&"crowbar")
	check(LootStates.has_pry_tool(player) and pry.interaction_actions(player).any(func(a: Dictionary) -> bool: return a.id == &"pry"), "with a crowbar: \"Pry it open\"")
	var p0 := Survival.pressure(level)
	check(LootStates.server_start_pry(pry, player, 0.2) == "" and pry.is_locked(), "the pry takes time")
	await get_tree().create_timer(0.5).timeout
	check(not pry.is_locked() and pry.pried and Survival.pressure(level) > p0, "then it gives, loudly (pressure %.1f -> %.1f)" % [p0, Survival.pressure(level)])


func _test_refill() -> void:
	print("Stock refills only where people pass")
	var c := LootStates.cache_by_uid(level, "test_box_a")
	if c == null:
		check(false, "the searched box is there")
		return
	c.cargo_hold.clear_all()
	c.searched = true
	c.searched_day = LootStates.now()
	check(not LootStates.people_pass(start) or not WorldSim.groups_in(start).is_empty(), "the farm's zone starts with nobody passing (%d groups)" % WorldSim.groups_in(start).size())
	var later := LootStates.now() + LootStates.REFILL_DAYS + 1.0
	if not LootStates.people_pass(start):
		check(LootStates.server_refill(level, start, later) == 0 and c.cargo_hold.entries().is_empty(), "an empty quarter's box stays empty")
	var m := WorldSim.model()
	var g := m.new_group("scavengers", start, Vector2.ZERO, m.rng_for("test_passers", "made"), 2)
	g.kind = "scavengers"
	check(LootStates.people_pass(start), "a group living in the zone: people pass")
	check(LootStates.server_refill(level, start, LootStates.now() + 0.5) == 0, "not before its days are up")
	check(LootStates.server_refill(level, start, later) >= 1 and not c.cargo_hold.entries().is_empty() and not c.searched and c.refills == 1,
		"after them, the box has something again (%d entries)" % c.cargo_hold.entries().size())
	g.alive = false


# --- Drop-in co-op -----------------------------------------------------------------------------------

func _test_coop() -> void:
	print("Drop-in co-op and the shared journal")
	var coop := CoopFallen.get_coop()
	var home := CoopFallen.home_point(level)
	check(CoopFallen.join_mode() == "farm" and CoopFallen.join_point(level, 2).distance_to(home) < 0.5, "a friend comes in at the farm by default")
	Survival.server_set_options({"join": "host"})
	check(CoopFallen.join_point(level, 3).distance_to(player.global_position) < CoopFallen.BESIDE_M + 1.5, "or beside the host when the world allows it")
	Survival.server_set_options({"join": "farm"})
	Survival._store_survivor(player)  # (the host's own kit kept, to put back after)
	var prof := "test_joiner" + tag
	player.set_meta(&"fallen_profile", prof)
	Survival.server_survivor_joined(player)
	var have := Survival.kit_of(player.inventory).map(func(e: Dictionary) -> String: return String(e.id))
	check(have.has("knife") and have.has("water_bottle") and have.has("canned_meat"), "a joiner is a fresh survivor with the starter kit (%s)" % [have])
	check(CoopFallen.server_arrive(player) == "newcomer" and _journal_has("came to the farm"), "a newcomer, in the journal")
	coop.server_push()
	var sent := JSON.stringify(coop.last_push.get("payload", {}))
	check(coop.pushes >= 1 and sent.contains("came to the farm") and (coop.last_push.payload as Dictionary).has("journal"), "the journal's view goes to the peers when it changes (%d bytes)" % sent.length())
	check(not coop.server_push(), "and not again until it changes")
	var comp := {"id": "test_comp2" + tag, "name": "Bo Test", "status": "settler", "opinion_of_players": {}}
	WorldSim.people()[String(comp.id)] = comp
	CoopFallen.server_deed(player, "brought the water in", 4.0)
	check(SurvivorPerson.opinion_of(comp, prof) > 0.0 and SurvivorPerson.opinion_of(comp, BaseHub.profile()) == 0.0, "people hold an opinion per player")
	WorldSim.people().erase(String(comp.id))
	var rec := CoopFallen.server_left(player)
	var rp: Array = rec.get("pos", [0, 0, 0])
	check(bool(rec.get("asleep", false)) and String(rec.get("zone", "")) == start and Vector3(float(rp[0]), float(rp[1]), float(rp[2])).distance_to(home) < 0.5,
		"a leaving player's survivor sleeps at the safehouse")
	Survival.server_survivor_joined(player)
	check(CoopFallen.server_arrive(player) == "woke" and _journal_has("woke at the farm") and not bool(rec.get("asleep", false)), "coming back, he wakes there")
	player.remove_meta(&"fallen_profile")
	Survival.server_survivor_joined(player)
	check(CoopFallen.server_arrive(player) == "host", "(the host is himself again)")
	WorldSim.people().erase("test_comp" + tag)


# --- The mod kit ------------------------------------------------------------------------------------

var _mod_root := ""


func _write(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(data if data is String else JSON.stringify(data))


func _make_mods() -> void:
	_mod_root = "user://fallen_modkit_test%s" % tag
	DirAccess.make_dir_recursive_absolute(_mod_root + "/good_mod")
	DirAccess.make_dir_recursive_absolute(_mod_root + "/broken_mod")
	_write(_mod_root + "/good_mod/mod.json", {"name": "Test Mod", "version": "1.0", "files": ["items.json", "zombies.json", "survival_events.json"], "load_order": 5})
	_write(_mod_root + "/good_mod/items.json", {"items": [{"id": "canned_meat", "name": "Tinned Meat (modded)"},
		{"id": "mod_test_charm", "name": "Lucky Charm", "type": "misc", "volume_l": 0.01, "mass_kg": 0.01, "desc": "A mod's own item.", "uses": ["Carry it."]}]})
	_write(_mod_root + "/good_mod/zombies.json", {"kinds": {"shambler_test": {"walk": 0.2, "chase": 0.3, "sprint": false, "pool": 15.0, "share": 0.05}}})
	_write(_mod_root + "/good_mod/survival_events.json", {"kinds": {"bell": {"window_h": 3}}})
	_write(_mod_root + "/broken_mod/mod.json", {"name": "Broken", "version": "1", "files": ["items.json", "nope.json"]})
	_write(_mod_root + "/broken_mod/items.json", {"items": [{"id": "broken_thing", "name": 5}]})


func _test_modkit() -> void:
	print("The mod kit")
	_make_mods()
	var meat_name := ItemDB.get_item(&"canned_meat").name
	var meat_kg := ItemDB.get_item(&"canned_meat").mass_kg
	ModKit.dirs_override = [_mod_root]
	ModKit.activate()
	check(ModKit.mods.size() == 1 and String(ModKit.mods[0].name) == "Test Mod", "a mod in the folder loads (%d on)" % ModKit.mods.size())
	check(ModKit.errors.size() == 1 and String(ModKit.errors[0].dir).ends_with("broken_mod"), "a broken one is skipped with why (%s)" % [ModKit.errors[0].problems if not ModKit.errors.is_empty() else []])
	check(ItemDB.get_item(&"canned_meat").name == "Tinned Meat (modded)" and is_equal_approx(ItemDB.get_item(&"canned_meat").mass_kg, meat_kg), "an item overridden by id, field by field (its weight kept)")
	check(ItemDB.has_item(&"mod_test_charm"), "an item added")
	check(is_equal_approx(float(ModKit.zombie_kind("shambler_test").pool), 15.0) and ModKit.extra_zombie_shares().has("shambler_test") and float(ModKit.zombie_kind("walker").pool) == float(ZombieAI.KINDS.walker.pool),
		"a kind of the dead added (it spawns by its share)")
	check(is_equal_approx(float(WorldEvents.kind_def("bell").window_h), 3.0) and is_equal_approx(float(WorldEvents.kind_def("bell").weight), 2.0), "a data file merged over by key (the bell's window, its weight kept)")
	var merged: Dictionary = ModKit.merge({"a": [{"id": "x", "v": 1}], "b": 1, "lines": [{"text": "one"}]}, {"a": [{"id": "x", "v": 2}, {"id": "y"}], "b": null, "lines": [{"text": "two"}]})
	check((merged.a as Array).size() == 2 and int(merged.a[0].v) == 2 and not merged.has("b") and (merged.lines as Array).size() == 2, "merging: records by id, null removes, other lists add")
	ModKit.deactivate()
	ModKit.dirs_override = []
	check(ItemDB.get_item(&"canned_meat").name == meat_name and not ItemDB.has_item(&"mod_test_charm") and not ModKit.zombie_kinds().has("shambler_test"), "off again, the game's own data is back")
	ModKit.activate()


func _test_validator() -> void:
	print("The validator")
	check(ModKit.validate(_mod_root + "/good_mod").is_empty(), "the good mod passes the schema")
	var bad := ModKit.validate(_mod_root + "/broken_mod")
	check(bad.size() >= 2 and bad.any(func(p: String) -> bool: return p.contains("nope.json")) and bad.any(func(p: String) -> bool: return p.contains("'name' should be string")),
		"the broken one fails: %s" % [bad])
	var shipped: Array = []
	for kind: String in (ModKit.schema().kinds as Dictionary):
		var base := String(ModKit.schema().kinds[kind].get("base", ""))
		if base.begins_with("res://"):
			ModKit.check_file(kind, ModKit._read_json(base), base, shipped)
	check(shipped.is_empty(), "the shipped data passes (%s)" % [shipped.slice(0, 3)])
	var script := ProjectSettings.globalize_path("res://tools/fallen_modkit/validate.py")
	var ran := false
	for py: String in ["python3", "python"]:
		var out: Array = []
		var code := OS.execute(py, [script, "--shipped", "--quiet"], out, true)
		if code < 0 or (code != 0 and String(out[0] if not out.is_empty() else "").contains("not found")):
			continue
		if not String(out[0] if not out.is_empty() else "").contains("shipped data:"):
			continue
		ran = true
		check(code == 0, "validate.py passes the shipped data (%s)" % String(out[0]).strip_edges().get_slice("\n", String(out[0]).strip_edges().count("\n")))
		var out2: Array = []
		var code2 := OS.execute(py, [script, ProjectSettings.globalize_path(_mod_root + "/broken_mod"), "--quiet"], out2, true)
		check(code2 == 1, "validate.py fails the broken mod (exit %d)" % code2)
		var out3: Array = []
		check(OS.execute(py, [script, ProjectSettings.globalize_path(_mod_root + "/good_mod"), "--quiet"], out3, true) == 0, "and passes the good one")
		break
	if not ran:
		print("  (no python on this machine: validate.py not run)")


func _test_world_card() -> void:
	print("A world card")
	var card := ModKit.world_card()
	check(int(card.seed) == 4242 and String(card.options.get("goal", "")) == Survival.option("goal") and not (card.options as Dictionary).has("survivor"), "the world's seed and options as a card")
	var path := ModKit.export_card({}, _mod_root + "/cards")
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text() if f else ""
	var back := ModKit.import_card(text)
	check(path != "" and not back.has("error") and int(back.seed) == 4242 and String((back.options as Dictionary).get("goal", "")) == String(card.options.goal), "exported and imported back (%s)" % path)
	check(ModKit.import_card("{\"seed\": 1}").has("error"), "something else isn't a card")
	var screen := NewWorldScreen.new(func(_n: String, _s: int, _o: Dictionary) -> void: pass)
	add_child(screen)
	var why := screen.apply_card(text)
	check(why == "" and screen.choices().get("goal", "") == String(card.options.goal) and screen._seed.text == "4242", "New world's Import fills the seed and options")
	screen.queue_free()
	for sub: String in ["good_mod", "broken_mod", "cards"]:
		var d := DirAccess.open(_mod_root + "/" + sub)
		if d:
			for file: String in d.get_files():
				DirAccess.remove_absolute(_mod_root + "/" + sub + "/" + file)
			DirAccess.remove_absolute(_mod_root + "/" + sub)
	DirAccess.remove_absolute(_mod_root)


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
	print("FALLENEVENTS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
