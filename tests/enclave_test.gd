extends Node
## Contractor: Fallen's enclave, ARCHE's trail, the bunkers and the cure chain's places
## (docs/survival_enclave.md; survival_world.md sections 6-7, survival_medical.md section 3): a new
## world has the enclave at its far home with posts, patrols that walk on the far tick and three
## officers; a toll demand reaches the players (and is paid or refused); far groups pay or are
## turned back and a looter gets a fight; the price is set by the seed and paying it flips the
## evac; the uniform and pass make the enclave friendly until a check fails; joining gives tasks,
## drops standing and costs a companion with a conscience; ARCHE's trail lays its pieces across
## the sites by seed (two seeds differ), reading one adds a journal line and a mark and teaches a
## code; a bunker opens with its code (not without power or with the wrong one), its loot holds
## the trail, a breached one lets its sealed dead out; the serum is made with the lab, an immune
## donor and the skill, refused without, and cures a bite; breaking the home post takes the port.

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var main: Node
var level: SurvivalLevel
var player: Soldier
var sim: WorldSim


func _ready() -> void:
	get_tree().create_timer(400.0).timeout.connect(func() -> void:
		print("ENCLAVE TEST FAILED (timed out)")
		get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _test_new_world()
	if level != null and player != null and sim != null and Enclave.is_set_up():
		_test_enclave_setup()
		_test_patrols_move()
		_test_player_toll()
		_test_far_tolls_and_looters()
		_test_price()
		_test_infiltration()
		_test_trail()
		await _test_bunkers()
		_test_serum()
		_test_join()
		_test_break()
	_finish()


func _test_new_world() -> void:
	print("A new world with the enclave")
	check(Survival.server_new_world(main, "test_enclave" + tag, 1357), "the menu's New world hosts one")
	level = SurvivalLevel.of(self)
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 25.0)
	player = level.players.get_node_or_null(^"1") as Soldier
	sim = WorldSim.get_sim()
	check(player != null and sim != null and WorldSim.is_set_up(), "the survivor is in and the world is set up")
	if sim == null:
		return
	sim.enabled = false  # (the test drives the ticks)
	sim.threaded = false
	player.inventory.take(&"pack_daypack_20")  # (room for what the tests hand him)
	check(Enclave.is_set_up() and ArcheTrail.is_set_up() and Bunkers.is_set_up() and Cure.is_set_up(), "the enclave, the trail, the bunkers and the lab are set up with the world")


func _tick(n: int) -> void:
	for i in n:
		sim.server_far_tick(float(WorldSim.section().get("t", WorldSim.world_now())) + WorldModel.TICK_MIN / 1440.0)


func _model() -> WorldModel:
	return WorldSim.model()


func _units(s: Soldier) -> int:
	var n := 0
	for c: StringName in s.inventory.search_containers():
		for e: Dictionary in s.inventory.containers[c]:
			n += int(e.get("count", 1))
	return n


func _events(kind: String) -> Array:
	return (WorldSim.section().get("events", []) as Array).filter(func(e: Dictionary) -> bool: return String(e.kind) == kind)


func _journal_has(text: String) -> bool:
	return (Survival.state().get("journal", []) as Array).any(func(j: Dictionary) -> bool: return String(j.text).contains(text))


# --- The enclave ---------------------------------------------------------------------------------

func _test_enclave_setup() -> void:
	print("The enclave at the far edge")
	var goal := WorldSim.goal_state()
	var g := Enclave.group()
	check(not g.is_empty() and String(g.kind) == "enclave" and bool(g.alive) and String(g.id) == String(goal.evac_group), "the enclave is the world's evac group (%s)" % String(g.get("name", "")))
	check(Enclave.home_zone() == String(goal.evac_zone) and String((g.home as Dictionary).get("zone", "")) == Enclave.home_zone(),
		"its home post is at the evac's zone (%s, %s)" % [Enclave.home_zone(), String(Enclave.data().home)])
	var posts := Enclave.posts()
	check(posts.has("port") and posts.has("base"), "posts at the port and the military base: %s" % ", ".join(posts.values().map(func(p: Dictionary) -> String: return "%s in %s (%d)" % [String(p.id), String(p.zone), EnclaveDetachment.size(p)])))
	var all_in := true
	for d: Dictionary in posts.values() + Enclave.patrols().values():
		for pid: String in d.members:
			all_in = all_in and pid in (g.members as Array) and String((WorldSim.people()[pid] as Dictionary).status) == WorldGroup.GROUPED
	check(all_in and EnclaveDetachment.size(Enclave.home_post()) >= 10, "every post's and patrol's people are the group's Persons (home %d, %d in all)" % [EnclaveDetachment.size(Enclave.home_post()), WorldGroup.size(g)])
	check(Enclave.patrols().size() >= 1 and (Enclave.patrols().values() as Array).all(func(p: Dictionary) -> bool: return (p.route as Array).size() >= 2 and EnclaveDetachment.size(p) == Enclave.PATROL_SIZE),
		"%d patrols with routes: %s" % [Enclave.patrols().size(), "; ".join(Enclave.patrols().values().map(func(p: Dictionary) -> String: return ">".join(PackedStringArray(p.route))))])
	var roles := Enclave.officers().map(func(o: Dictionary) -> String: return String(o.role))
	var o_ok := Enclave.officers().size() == 3 and (Enclave.officers() as Array).all(func(o: Dictionary) -> bool:
		var rec: Dictionary = WorldSim.people().get(String(o.id), {})
		return String(rec.get("enclave_officer", "")) == String(o.role) and String(o.id) in (Enclave.home_post().members as Array))
	check(o_ok and roles == ["hard", "decent", "frightened"], "three officers, named Persons at the home post: %s" % ", ".join(Enclave.officers().map(func(o: Dictionary) -> String: return "%s %s (%s, %+d)" % [String(o.rank), String(o.name), String(o.role), int(o.standing)])))
	check(Enclave.nature() in Enclave.NATURES and String(Enclave.price().kind) in Enclave.PRICE_KINDS, "by seed: %s, price %s" % [Enclave.nature(), String(Enclave.price().text)])


func _test_patrols_move() -> void:
	print("Patrols walk on the far tick")
	var before := {}
	for p: Dictionary in Enclave.patrols().values():
		before[String(p.id)] = String(p.zone)
	_tick(int(EnclaveDetachment.TICKS_A_ZONE) + 1)
	var moved: Array = []
	for p: Dictionary in Enclave.patrols().values():
		if String(p.zone) != String(before[String(p.id)]):
			moved.append("%s %s>%s" % [String(p.id), String(before[String(p.id)]), String(p.zone)])
			var rec: Dictionary = WorldSim.people().get(String(p.members[0]), {})
			check(String(rec.get("zone", "")) == String(p.zone), "%s's people walked with it" % String(p.id))
	check(not moved.is_empty(), "a patrol came into its next zone after %d ticks: %s" % [int(EnclaveDetachment.TICKS_A_ZONE) + 1, ", ".join(moved)])
	var aired := _events("broadcast").filter(func(e: Dictionary) -> bool: return bool(e.get("arche", false)) and e.has("freq"))
	check(not aired.is_empty(), "ARCHE's frequency aired: \"%s\"" % String((aired[0] as Dictionary).get("text", "")) if not aired.is_empty() else "ARCHE's frequency aired")


func _test_player_toll() -> void:
	print("A toll on the players")
	var hosted := WorldSim.hosted_zone()
	var p: Dictionary = Enclave.patrols().values()[0]
	var was := String(p.zone)
	p.zone = hosted
	p.progress = 0.0
	Enclave.data()["player_tolled"] = -100.0
	Enclave.server_after_step(_model())
	var tolls := Enclave.pending_tolls()
	check(tolls.size() == 1 and String(tolls[0].zone) == hosted and _journal_has("toll"), "a patrol in the players' zone asks a toll: \"%s\"" % String((Survival.state().journal as Array)[-1].text))
	if tolls.is_empty():
		p.zone = was
		return
	player.inventory.take(&"antibiotics", 2)
	var units := _units(player)
	check(Enclave.server_answer_toll(String(tolls[0].id), "pay", player) == "" and String(tolls[0].state) == "paid" and _units(player) < units,
		"paid from his kit (%d things to %d)" % [units, _units(player)])
	var rel := WorldGroup.relation(Enclave.group(), "player")
	var t := Enclave.server_put_toll(hosted, String(p.id))
	check(Enclave.server_answer_toll(String(t.id), "refuse") == "" and String(t.state) == "refused" and WorldGroup.relation(Enclave.group(), "player") < rel and not _events("turned_back").is_empty(),
		"refused: turned back, the enclave's standing falls (%d to %d)" % [roundi(rel), roundi(WorldGroup.relation(Enclave.group(), "player"))])
	Enclave.server_after_step(_model())
	check(Enclave.pending_tolls().is_empty(), "not asked again the same day")
	p.zone = was
	WorldSim.get_sim().server_change_relation(Enclave.gid(), rel - WorldGroup.relation(Enclave.group(), "player"))


func _test_far_tolls_and_looters() -> void:
	print("Far groups pay or are turned back; looters are shot at")
	var other: Dictionary = Enclave.posts().get("base", {}) if String(Enclave.data().home) == "port" else Enclave.posts().get("port", {})
	var z := String(other.zone)
	var m := _model()
	var zd := m.zone(z)
	var pl: Dictionary = (zd.places as Array)[-1]
	var looters := m.new_group("scavengers", z, WorldModel._place_v(pl), m.rng_for("test_looters"), 4)
	looters.goal = {"kind": "forage", "zone": z, "place": String(pl.id), "target": "", "since": m.tick(), "phase": "go", "work": 0}
	var hated := m.new_group("raiders", z, WorldModel._place_v(pl), m.rng_for("test_hated"), 3)
	WorldGroup.change_relation(Enclave.group(), String(hated.id), -60.0)
	hated.goal = {"kind": "rest", "zone": z, "place": "", "target": "", "since": m.tick(), "phase": "go", "work": 0}
	var before := WorldGroup.size(looters) + WorldGroup.size(Enclave.group())
	var food := WorldGroup.supply(looters, "food")
	Enclave.server_after_step(_model())
	var tolled := _events("toll").any(func(e: Dictionary) -> bool: return String(looters.id) in (e.groups as Array))
	check(tolled and WorldGroup.supply(looters, "food") < food, "a group at the enclave's post pays its toll (food %.1f to %.1f)" % [food, WorldGroup.supply(looters, "food")])
	var turned := _events("turned_back").any(func(e: Dictionary) -> bool: return String(hated.id) in (e.groups as Array))
	check(turned and (hated.goal as Dictionary).is_empty(), "a group the enclave hates is turned back")
	var shot := _events("looters_shot").filter(func(e: Dictionary) -> bool: return String(looters.id) in (e.groups as Array))
	var fight := _events("fight").any(func(e: Dictionary) -> bool: return String(looters.id) in (e.groups as Array))
	check(not shot.is_empty() and fight and WorldGroup.size(looters) + WorldGroup.size(Enclave.group()) < before, "the looters got a fight: \"%s\"" % String(shot[0].text) if not shot.is_empty() else "the looters got a fight")
	var all_alive := true
	for d: Dictionary in Enclave.posts().values() + Enclave.patrols().values():
		for pid: String in d.members:
			all_alive = all_alive and String((WorldSim.people()[pid] as Dictionary).status) != "dead"
	check(all_alive, "the enclave's dead leave their posts")
	looters.alive = false
	hated.alive = false


func _test_price() -> void:
	print("The price of the evac")
	var terms := Enclave.terms_for(WorldSim.world_seed())
	var pr := Enclave.price()
	check(String(terms.kind) == String(pr.kind) and String(terms.nature) == Enclave.nature() and int(terms.need) == int(pr.need), "the price is the seed's: %s x%d (%s)" % [String(pr.kind), int(pr.need), Enclave.nature()])
	var kinds := {}
	var natures := {}
	for sd in range(1, 60):
		var t := Enclave.terms_for(sd)
		kinds[String(t.kind)] = true
		natures[String(t.nature)] = true
	check(kinds.size() == 4 and natures.size() == 3, "other seeds ask other prices: %s; %s" % [", ".join(kinds.keys()), ", ".join(natures.keys())])
	var p: Dictionary = Enclave.data().price
	var saved := p.duplicate(true)
	var real := Enclave.evac_real()
	p.kind = "cure"
	p.need = 1
	p.progress = 0
	Enclave.data()["evac_real"] = true
	check(Enclave.server_pay_price().begins_with("Not yet") and not bool(WorldSim.goal_state().price_paid), "not paid before it's earned")
	check(Enclave.server_deliver("serum", player) != "", "no serum, nothing to hand over")
	player.inventory.take(&"serum", 1)
	check(Enclave.server_deliver("serum", player) == "" and int(Enclave.price().progress) == 1 and player.inventory.count_of(&"serum") == 0, "a dose of serum handed over: the price earned")
	check(Enclave.server_pay_price() == "" and bool(WorldSim.goal_state().price_paid), "server_pay_price flips the evac (price_paid)")
	WorldSim.section().goal.price_paid = false
	p.paid = false
	p.progress = 1
	Enclave.data()["evac_real"] = false
	check(Enclave.server_pay_price() == "" and not bool(WorldSim.goal_state().price_paid) and bool(Enclave.data().get("betrayed", false)), "a lying enclave takes the price and the evac doesn't come")
	Enclave.data().erase("betrayed")
	Enclave.data()["price"] = saved
	Enclave.data()["evac_real"] = real


func _test_infiltration() -> void:
	print("Infiltration")
	check(Enclave.server_wear_disguise(player) != "", "no uniform, no disguise")
	player.inventory.take(&"enclave_uniform", 1)
	player.inventory.take(&"enclave_pass", 1)
	var rel := WorldGroup.relation(Enclave.group(), "player")
	check(Enclave.server_wear_disguise(player) == "" and Enclave.is_disguised() and WorldGroup.stance(Enclave.group()) == "friendly",
		"in the uniform with the pass the enclave takes him for one of theirs (%s)" % WorldGroup.stance(Enclave.group()))
	Enclave.force_roll = 0.99
	check(Enclave.server_check_disguise(player) and Enclave.is_disguised(), "a check passes")
	Enclave.force_roll = 0.0
	check(not Enclave.server_check_disguise(player) and not Enclave.is_disguised() and WorldGroup.relation(Enclave.group(), "player") < rel and WorldGroup.stance(Enclave.group()) != "friendly",
		"a check fails: seen through, the standing below where it was (%d)" % roundi(WorldGroup.relation(Enclave.group(), "player")))
	Enclave.force_roll = -1.0
	WorldSim.get_sim().server_change_relation(Enclave.gid(), rel - WorldGroup.relation(Enclave.group(), "player"))


# --- ARCHE's trail -------------------------------------------------------------------------------

func _test_trail() -> void:
	print("ARCHE's trail")
	var pcs := ArcheTrail.pieces()
	var site_ids := {}
	var kinds := {}
	for pc: Dictionary in pcs.values():
		site_ids[String(pc.site)] = true
		kinds[String(pc.kind)] = true
	check(pcs.size() >= 6 and site_ids.size() >= 5, "%d pieces over %d sites (%s)" % [pcs.size(), site_ids.size(), ", ".join(site_ids.keys())])
	check(kinds.has("note") and kinds.has("terminal") and kinds.has("recording") and kinds.has("broadcast") and kinds.has("survivor") and kinds.has("officer"),
		"notes, terminals, recordings, broadcasts, a survivor, an officer: %s" % ", ".join(kinds.keys()))
	var tech: Dictionary = WorldSim.people().get(String(ArcheTrail.data().get("survivor", "")), {})
	check(bool(tech.get("arche_survivor", false)) and String(tech.get("status", "")) == "out_there", "the technician is a lone survivor out there (%s in %s)" % [String(tech.get("name", "")), String(tech.get("zone", ""))])
	var zones: Dictionary = WorldSim.section().zones
	var a := ArcheTrail.lay(11, zones, Bunkers.lay(11, zones, ""), "", Enclave.home_zone())
	var b := ArcheTrail.lay(12, zones, Bunkers.lay(12, zones, ""), "", Enclave.home_zone())
	var a2 := ArcheTrail.lay(11, zones, Bunkers.lay(11, zones, ""), "", Enclave.home_zone())
	check(a.order != b.order and a.order == a2.order, "two seeds lay it in different orders, one seed the same: %s / %s" % [",".join(PackedStringArray((a.order as Array).slice(0, 4))), ",".join(PackedStringArray((b.order as Array).slice(0, 4)))])
	var pick := ""
	for id: String in ArcheTrail.data().order:
		var pc := ArcheTrail.piece(id)
		if not bool(pc.read) and String(pc.code_for) != "":
			pick = id
			break
	var marks := SurvivalMap.marks().size()
	var text := ArcheTrail.server_read(pick, player)
	var pc := ArcheTrail.piece(pick)
	check(text != "" and bool(pc.read) and _journal_has("ARCHE - %s" % String(pc.title)), "reading \"%s\" adds a journal line" % String(pc.title))
	check(SurvivalMap.marks().size() > marks and SurvivalMap.marks().any(func(mk: Dictionary) -> bool: return String(mk.kind) == "arche"), "and marks the map (%d marks)" % (SurvivalMap.marks().size() - marks))
	check(ArcheTrail.knows_code(String(pc.code_for)) and text.contains(String(Bunkers.get_bunker(String(pc.code_for)).code)), "and teaches a bunker's code (%s)" % String(pc.code_for))
	var shared: Dictionary = Survival.state().get("trail", {})
	check((shared.get("pieces", []) as Array).any(func(x: Dictionary) -> bool: return String(x.text) == text and x.has("day") and String(x.zone) == String(pc.zone))
		and not (shared.get("numbers", []) as Array).is_empty(), "the journal's trail tab and the radio's numbers station read it (state.trail)")
	var node := Survival.get_node_or_null(^"Enclave")
	check(node != null and node.has_method("is_quartermaster") and node.is_quartermaster(WorldSim.people().get(String(Enclave.data().get("quartermaster", "")), {})), "the enclave's quartermaster is found through Survival/Enclave")
	var th := ArcheTrail.theories()
	check(th.has("leak") and th.has("release"), "two theories stay open (leak %d, release %d)" % [int(th.leak), int(th.release)])


# --- Bunkers -------------------------------------------------------------------------------------

func _test_bunkers() -> void:
	print("ARCHE's bunkers")
	var bl := Bunkers.list()
	check(bl.size() >= 3 and bl.size() <= 6, "%d bunkers: %s" % [bl.size(), ", ".join(bl.map(func(x: Dictionary) -> String: return "%s in %s" % [String(x.name), String(x.zone)]))])
	check(bl.all(func(x: Dictionary) -> bool: return not Bunkers.trail_items(x).is_empty() and not (x.rooms as Array).is_empty()), "each has rooms and a piece of the trail in its loot")
	var b: Dictionary = bl[0]
	check(Bunkers.server_open(String(b.id), "code", player, String(b.code)) == "The keypad is dead", "the keypad needs power")
	check(Bunkers.server_power(String(b.id), player) != "", "power needs a battery or fuel")
	check(Bunkers.server_power(String(b.id), null, true) == "" and bool(b.door.power), "a generator wired to it powers it")
	var wrong := "0000" if String(b.code) != "0000" else "1111"
	check(Bunkers.server_open(String(b.id), "code", player, wrong) == "Wrong code" and not Bunkers.is_open(b), "the wrong code doesn't open it")
	check(Bunkers.server_open(String(b.id), "code", player, String(b.code)) == "" and Bunkers.is_open(b), "its code opens it (%s)" % String(b.code))
	check(_events("bunker_opened").any(func(e: Dictionary) -> bool: return String(e.get("bunker", "")) == String(b.id)), "the zone's groups know it's open (an event)")
	var room: Dictionary = (b.rooms as Array)[0]
	room.trap = {"kind": "gas", "tripped": false}
	var said := Bunkers.server_enter_room(String(b.id), 0, player)
	check(said.contains("gas") and float(Survival.survivor_of(player).get("taint", 0.0)) > 0.0, "a gas pocket in a room taints him (%s)" % said)
	# a breached one in the players' zone lets its sealed dead out
	var b2: Dictionary = bl[1]
	b2.zone = WorldSim.hosted_zone()
	b2.pos = [player.global_position.x + 12.0, player.global_position.z]
	b2.sealed_dead = 4
	b2.dead_out = false
	var dead := Survival.zombies(level).size()
	check(Bunkers.server_open(String(b2.id), "breach", player) != "", "no charge, no breach")
	player.inventory.take(&"breaching_charge", 1)
	check(Bunkers.server_open(String(b2.id), "breach", player) == "" and Bunkers.is_open(b2), "a breach charge blows it open")
	await get_tree().process_frame
	check(Survival.zombies(level).size() >= dead + 4 and bool(b2.dead_out), "its sealed dead come out (%d to %d)" % [dead, Survival.zombies(level).size()])
	check(bool((Bunkers.data().spawned as Dictionary).get(String(b2.id), false)), "its rooms are caches at the door")
	var table: Dictionary = Bunkers.bunker_data().tables
	var serum_in := ["hospital", "lab", "bunker_medical"].all(func(t: String) -> bool: return JSON.stringify(table[t]).contains("\"serum\""))
	check(serum_in, "the rare serum is in the hospital, lab and bunker tables")


# --- The cure chain ------------------------------------------------------------------------------

func _test_serum() -> void:
	print("The serum")
	var lab := Cure.lab()
	check(String(lab.zone) != "" and String((WorldSim.section().zones[String(lab.zone)] as Dictionary).type) == "lab" and bool(lab.centrifuge) and bool(lab.fridge),
		"the lab's centrifuge and fridge are at %s" % String(lab.zone))
	check(not Cure.immune_people().is_empty(), "the world has its immune (%d)" % Cure.immune_people().size())
	check(Cure.server_make_serum(player).contains("skill"), "refused without the medical skill")
	Rpg.set_level(player, "medical", 9)
	check(Cure.server_make_serum(player) == "It needs the lab", "refused away from the lab")
	var lab_zone := String(lab.zone)
	lab["zone"] = WorldSim.hosted_zone()  # (the test stands at the bench)
	check(Cure.server_make_serum(player).contains("power"), "refused with the lab unpowered")
	check(Cure.server_power_lab(null, true) == "" and Cure.lab_ready(), "the lab powered")
	check(Cure.server_make_serum(player, "nobody").contains("doesn't turn"), "refused without an immune donor")
	WorldSim.people()["test_donor"] = {"id": "test_donor", "name": "Ada Donor", "status": "companion", "immune": true, "moodlets": [], "traits": []}
	var n := player.inventory.count_of(&"serum")
	check(Cure.server_make_serum(player, "test_donor") == "" and player.inventory.count_of(&"serum") == n + 1, "with the skill, the lab and a donor: a dose of serum")
	player.set_meta(&"bitten", true)
	check(Cure.server_apply(player) and not player.has_meta(&"bitten") and player.inventory.count_of(&"serum") == n, "the serum clears a bite")
	lab["zone"] = lab_zone
	WorldSim.people().erase("test_donor")


# --- Joining and breaking ------------------------------------------------------------------------

func _test_join() -> void:
	print("Joining the enclave")
	var other := {}
	for g: Dictionary in (WorldSim.section().groups as Dictionary).values():
		if bool(g.alive) and String(g.kind) in ["settlers", "scavengers"]:
			other = g
			break
	var rel_other := WorldGroup.relation(other, "player")
	var rel := WorldGroup.relation(Enclave.group(), "player")
	WorldSim.people()["test_conscience"] = {"id": "test_conscience", "name": "Kit Kind", "status": "companion", "traits": ["kind"], "moodlets": [], "break": ""}
	Enclave.force_roll = 0.0
	check(Enclave.server_join(player) == "" and Enclave.is_joined(), "the players join")
	Enclave.force_roll = -1.0
	check(Enclave.tasks().size() == 3 and _journal_has("Enclave task"), "they're given tasks in the journal: %s" % "; ".join(Enclave.tasks().map(func(t: Dictionary) -> String: return String(t.text))))
	check(WorldGroup.relation(Enclave.group(), "player") > rel and WorldGroup.relation(other, "player") < rel_other,
		"the enclave's standing up (%d), %s's down (%d to %d)" % [roundi(WorldGroup.relation(Enclave.group(), "player")), String(other.get("name", "")), roundi(rel_other), roundi(WorldGroup.relation(other, "player"))])
	var c: Dictionary = WorldSim.people()["test_conscience"]
	check(String(c.get("break", "")) == "desertion" and Moods.has(c, "served_enclave"), "a companion with a conscience walks")
	check(bool(ArcheTrail.piece("officer_story").get("read", false)), "inside, the officer's part of the trail is learnt")
	WorldSim.people().erase("test_conscience")


func _test_break() -> void:
	print("Breaking the port")
	var home := Enclave.home_post()
	var n := WorldGroup.size(Enclave.group())
	for pid: String in (home.members as Array).duplicate():
		Enclave.server_kill(pid, "killed taking the port")
	Enclave.server_after_step(_model())
	check(Enclave.is_broken() and EnclaveDetachment.size(home) == 0 and WorldGroup.size(Enclave.group()) < n, "the home post down to nobody: broken (%d of %d left)" % [WorldGroup.size(Enclave.group()), n])
	var st := WorldSim.goal_state()
	check(bool(st.evac) and bool(st.price_paid) and not _events("port_taken").is_empty(), "the evac is open to the players (port taken)")


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
	print("ENCLAVE TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)
