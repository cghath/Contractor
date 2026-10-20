extends Node
## The story and the multi-zone contracts' markers (docs/story.md, docs/linked_zones.md LZ-7):
##   <voxel godot exe> --headless --path . res://tests/story_test.tscn
## First, the manhunt the Captain played on 2026-10-20 ("the intel case doesn't tell you where
## dude is", "both markers show on the first map but not the second map"), end to end in a
## hosted base-zone campaign: deployed on a manhunt, the first zone's map shows only its own
## objectives (not the man next door); the intel picked up says where he went (his zone and
## site, on the radio and in the objective); walked on through the crossing, the second zone's
## map shows the man and not the first zone's intel. Then the supply line's and the convoy
## chase's markers the same way (Objectives.map_list), and the story: act 1's contracts unlock
## in order, intel advances the arc, the story state saves and loads. Exits with the number of
## failures.

const SEED := 6161

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var level: CompoundLevel
var notices: Array[String] = []


func _ready() -> void:
	GameState.zone_id = "test_story" + tag
	Campaign.campaign_id = "test_story" + tag  # never touch a real save
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("STORY TEST FAILED (timed out)")
		BaseHub.delete_test_campaign_files()
		get_tree().quit(99))
	GameState.delete_save()
	BaseHub.delete_test_campaign_files()
	BaseHub.base_zone_mode = 1
	Contracts.auto_show_debrief = false
	await _run()
	print("STORY TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	BaseHub.delete_test_campaign_files()
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return cond.call()


func _run() -> void:
	CompoundLevel.spawn_ai = false  # (the fight isn't what this suite checks)
	Roles.local_choice = Roles.TEAM_LEADER
	BaseHub.local_profile = "host_profile"
	BaseHub.new_campaign(SEED)
	Campaign.save_campaign()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	BaseHub.prepare_session()
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	check(level is BaseZoneLevel, "the campaign starts at the base zone")
	Contracts.notice.connect(func(t: String) -> void: notices.append(t))
	Economy.notice.connect(func(t: String) -> void: notices.append(t))
	await _test_manhunt()
	_test_leg_markers()
	_test_story()


## A manhunt whose leg is next door, through the real deployment, briefing, pickup and crossing.
func _test_manhunt() -> void:
	print("Manhunt markers and intel (LZ-7, Captain 2026-10-20)")
	var c := _gen("manhunt")
	check(not c.is_empty(), "a manhunt generates with its man in a neighbouring zone")
	if c.is_empty():
		return
	var leg: Dictionary = c.legs[0]
	var cid := Contracts.server_add_offer(c)
	check(Contracts.server_accept(cid, ContractGen.default_terms()) == "" and String(BaseHub.prep_contract().get("cid", "")) == cid,
		"taken: %s (intel in %s, the man in %s)" % [Contracts.contract(cid).title, c.zone_name, leg.zone_name])
	var why := BaseHub.server_deploy()
	await _wait_until(func() -> bool: return CompoundLevel.current(self) is ZoneLevel and not CompoundLevel.current(self) is BaseZoneLevel and not BaseHub.switch_pending(), 40.0)
	level = CompoundLevel.current(self)
	check(why == "" and level is ZoneLevel and String((level as ZoneLevel).def.id) == String(c.zone_id), "deployed into %s (%s)" % [c.zone_id, why])
	if not level is ZoneLevel:
		return
	var briefing := MapNodes.briefing(level)
	await _wait_until(func() -> bool: return briefing != null and briefing.is_open(), 15.0)
	await _wait_until(func() -> bool: return level.players.get_node_or_null(^"1") != null, 10.0)
	var me := level.players.get_node_or_null(^"1") as Soldier
	check(briefing != null and briefing.is_open() and me != null, "the briefing is open")
	if me == null:
		return
	me.vitals.shielded = true
	var leg_name := String(leg.zone_name)
	var leg_on_map := func() -> Array:
		return MapView.objectives_in(level).filter(func(o: Dictionary) -> bool: return String(o.get("title", "")).contains("(in %s)" % leg_name))
	var first_map := MapView.objectives_in(level)
	check(leg_on_map.call().is_empty() and not first_map.is_empty(),
		"briefing: the first zone's map shows its intel and not the man next door (%s)" % _titles(first_map))
	briefing.server_set_ready(1, true)
	check(briefing.server_start(), "everyone ready, the briefing starts")
	await get_tree().create_timer(0.5).timeout
	first_map = MapView.objectives_in(level)
	check(leg_on_map.call().is_empty() and first_map.size() == 1, "deployed: the first zone's map shows only its own objective (%s)" % _titles(first_map))
	# The intel: picked up, it says where he went.
	var intel_obj: Dictionary = Contracts.objectives.for_contract(cid).filter(func(o: Dictionary) -> bool: return String(o.kind) == Objectives.EXTRACT_ITEM)[0]
	var site := Vector3(float(intel_obj.pos[0]), float(intel_obj.pos[1]), float(intel_obj.pos[2]))
	me.global_position = level.above_ground(site + Vector3(4, 0, 4)) + Vector3.UP
	var found: Array = []  # (a lambda gets copies of locals: it fills this)
	await _wait_until(func() -> bool:
		for n: Node in level.items.get_children():
			var wi := n as WorldItem
			if wi and Objectives.entry_matches(intel_obj.params, {"id": String(wi.item_id), "state": wi.state}) and wi.global_position.distance_to(site) < 3.0:
				found.append(wi)
				return true
		return false, 30.0)
	var item: WorldItem = found[0] if not found.is_empty() else null
	check(item != null, "the %s lies at its site (%s)" % [intel_obj.params.get("name", "intel"), item.item_id if item else &"none"])
	if item == null:
		return
	notices.clear()
	me.global_position = item.global_position + Vector3(0, 0.5, 0)
	check(me.inventory.take(item.item_id, 1, item.state.duplicate(true)) == 1, "picked up")
	item.queue_free()
	await get_tree().create_timer(IntelReveal.TICK_S * 2.0 + 0.5).timeout
	var leg_module := MissionRegistry.module_name(String(leg.module))
	var said := notices.filter(func(t: String) -> bool: return t.contains(leg_name) and t.to_lower().contains(leg_module.to_lower()))
	check(not said.is_empty(), "the intel says where he went: %s, the %s (%s)" % [leg_name, leg_module, " | ".join(notices)])
	var hunt: Array = Contracts.objectives.for_contract(cid).filter(func(o: Dictionary) -> bool: return o.has("leg"))
	check(not hunt.is_empty() and String(hunt[0].text).to_lower().contains(leg_module.to_lower()),
		"and his objective names the site (%s)" % (hunt[0].text if not hunt.is_empty() else "none"))
	check(leg_on_map.call().is_empty(), "still not on the first zone's map")
	# Walk on into his zone.
	var zx := MapNodes.extraction(level)
	await _wait_until(func() -> bool: return zx.is_active(), 5.0)
	var on: Dictionary = {}
	for p: Dictionary in zx.points:
		if String(p.get("source", "")) == "crossing" and String(p.get("to", "")) == String(leg.zone_id):
			on = p
	check(not on.is_empty(), "%s has a crossing on into %s" % [c.zone_id, leg.zone_id])
	if on.is_empty():
		return
	me.global_position = level.ground_point(Vector3(on.pos.x, 0, on.pos.y))
	await get_tree().physics_frame
	zx.countdown_s = 0.5
	why = zx.server_confirm(1)
	await _wait_until(func() -> bool:
		var l := CompoundLevel.current(self) as ZoneLevel
		return l != null and String(l.def.id) == String(leg.zone_id) and not BaseHub.switch_pending(), 40.0)
	level = CompoundLevel.current(self)
	check(why == "" and level is ZoneLevel and String((level as ZoneLevel).def.id) == String(leg.zone_id), "walked on into %s (%s)" % [leg.zone_id, why])
	if not level is ZoneLevel:
		return
	await get_tree().create_timer(1.0).timeout
	var second_map := MapView.objectives_in(level)
	var hvt_marks := second_map.filter(func(o: Dictionary) -> bool: return String(o.get("title", "")).contains("(in %s)" % leg_name))
	var at := Contracts.module_origin({"module_id": String(leg.module_id)})
	check(hvt_marks.size() == 1 and (hvt_marks[0].pos as Vector2).distance_to(Vector2(at.x, at.z)) < 60.0,
		"the second zone's map shows the man, at his site (%s)" % _titles(second_map))
	check(second_map.size() == hvt_marks.size(), "and not the first zone's intel")
	Contracts.server_abandon_deployment()


## A contract of `type` from a contract zone with a leg next door, or {}.
func _gen(type: String) -> Dictionary:
	for z: Dictionary in MissionRegistry.zones():
		if String(z.get("kind", "")) != "contract":
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(z.zone_id) + type)
		var o := ContractGen.generate(rng, {"type": type, "zone_id": String(z.zone_id), "source": "safe", "day": Economy.day()})
		if not (o.get("legs", []) as Array).is_empty():
			return o
	return {}


func _titles(list: Array) -> String:
	return ", ".join(PackedStringArray(list.map(func(o: Dictionary) -> String: return "%s @%s" % [o.get("title", "?"), o.get("pos", "?")])))


## The supply line's and the convoy chase's legs the same way (Objectives.map_list, the briefing's
## list): the first zone's map has only its own objectives, the leg's zone only the leg's once placed.
func _test_leg_markers() -> void:
	print("Supply line and convoy chase markers (LZ-7)")
	var case_site := {"items": ["hvt_case"], "tags": ["intel"]}
	check(Contracts._is_lead_piece(case_site, {"id": "hvt_case", "state": {}}) and not Contracts._is_lead_piece(case_site, {"id": "intel_phone", "state": {}})
		and Contracts._is_lead_piece({"items": ["intel_laptop"], "intel_ids": ["x1"]}, {"id": "intel_laptop", "state": {"intel_id": "x1"}})
		and not Contracts._is_lead_piece({"items": ["intel_laptop"], "intel_ids": ["x1"]}, {"id": "intel_laptop", "state": {"intel_id": "x2"}}),
		"only the manhunt's own piece says where he went (not a phone picked up on the way, not another laptop)")
	for type: String in ["supply_line", "convoy_chase"]:
		var c := _gen(type)
		if c.is_empty():
			check(false, "a %s generates with a leg" % type)
			continue
		var cid := Contracts.server_add_offer(c)
		c = Contracts.contract(cid)
		var leg: Dictionary = c.legs[0]
		var objs := Objectives.from_contract(c)
		var fake := ZoneLevel.new()
		fake.def = {"id": String(c.zone_id), "crossings": [{}]}
		var first := Objectives.map_list(objs, fake)
		var mine := objs.filter(func(o: Dictionary) -> bool: return not o.has("leg") and (o.pos as Array).size() >= 3).size()
		check(first.size() == mine and not first.any(func(m: Dictionary) -> bool: return String(m.title).contains("(in %s)" % leg.zone_name)),
			"%s: the first zone's map has its own %d and not the leg's (%s)" % [type, mine, ", ".join(PackedStringArray(first.map(func(m: Dictionary) -> String: return String(m.title))))])
		var briefed: Array = BaseHub.briefing_contract(cid).objectives
		check(briefed.size() == objs.size() - objs.filter(func(o: Dictionary) -> bool: return o.has("leg")).size(),
			"%s: and so does its briefing (%d, no leg at the zone's centre)" % [type, briefed.size()])
		var placed := Objectives.leg_objectives(c, 0, Vector3(300, 0, 300), false)
		var after: Array = objs.filter(func(o: Dictionary) -> bool: return not o.has("leg")) + placed
		fake.def = {"id": String(leg.zone_id), "crossings": [{}]}
		var second := Objectives.map_list(after, fake)
		check(not second.is_empty() and second.size() == placed.filter(func(o: Dictionary) -> bool: return (o.pos as Array).size() >= 3).size()
			and second.all(func(m: Dictionary) -> bool: return String(m.title).contains("(in %s)" % leg.zone_name)),
			"%s: in %s its map has the leg's objectives, placed, and not the first zone's (%d)" % [type, leg.zone_id, second.size()])
		fake.free()


## The story (docs/story.md): act 1's contracts unlock in order, intel advances the arc, the
## story state saves and loads.
func _test_story() -> void:
	print("Story: act 1")
	var s := Campaign.section(Story.SECTION)
	check(Story.act() == 1 and Story.evidence() == 0 and Story.clues().is_empty(), "a new campaign starts the story at act 1, no evidence, no clues")
	var defs := Story.contract_defs(1)
	var ids: Array = defs.map(func(d: Dictionary) -> String: return String(d.id))
	check(ids == ["s1_paper_trail", "s2_quartermaster", "s3_crates", "s4_vantage_point"], "act 1's four story contracts, in order (%s)" % [ids])
	check(_offered() == ["s1_paper_trail"], "only the first is on the board at the start (%s)" % [_offered()])
	var c1 := _story_contract("s1_paper_trail")
	check(String(c1.get("source", "")) == Story.SOURCE and String(c1.get("title", "")).begins_with("Story: Paper trail") and String(c1.get("type", "")) == "intel_grab"
		and String(c1.get("employer", "")) == "meridian" and String(c1.get("target", "")) == "black_ridge" and int(c1.get("expires_day", 0)) > Economy.day() + 100,
		"Paper trail: an intel grab for Meridian against Black Ridge, on the board until taken (%s)" % c1.get("title", "?"))
	# Each kind of story contract generates as written.
	var c2 := Story.make_contract("s2_quartermaster")
	check(String(c2.type) == "manhunt" and not (c2.legs as Array).is_empty() and String(c2.legs[0].objectives[0].text).contains("quartermaster"),
		"The quartermaster: a manhunt, the man in the zone next door")
	var c3 := Story.make_contract("s3_crates")
	check(String(c3.type) == "supply_line" and (c3.objectives as Array).size() == 2 and not (c3.legs as Array).is_empty()
		and (c3.legs[0].objectives as Array).all(func(o: Dictionary) -> bool: return String(o.kind) == Objectives.DESTROY_CACHE),
		"The crates: a supply line, the waybills here and only the cache next door")
	var c4 := Story.make_contract("s4_vantage_point")
	c4["cid"] = "story_c4"
	var ledger := Objectives.from_contract(c4).filter(func(o: Dictionary) -> bool: return String(o.kind) == Objectives.EXTRACT_ITEM)
	check(String(c4.target) == "vantage_group" and ledger.size() == 1 and String(ledger[0].params.get("place", "")) == "vantage_ledger"
		and not (ledger[0].params.get("intel_ids", []) as Array).is_empty() and String(ledger[0].text).contains("Vantage ledger"),
		"Vantage point: against Vantage, their ledger placed at the site (%s)" % (ledger[0].text if not ledger.is_empty() else "none"))
	# In order: done, its clue found, the next on the board.
	notices.clear()
	_close_story("s1_paper_trail", "completed")
	check(Story.is_done("s1_paper_trail") and Story.evidence() == 1 and Story.clues().size() == 1 and _offered() == ["s2_quartermaster"],
		"Paper trail done: its clue found (evidence 1), The quartermaster on the board (%s)" % [_offered()])
	check(notices.any(func(t: String) -> bool: return t.begins_with("Radio, client liaison:") and t.contains("quartermaster")), "the liaison says so on the radio")
	# Failed, it comes back the next day.
	_close_story("s2_quartermaster", "failed")
	check(_offered().is_empty() and not Story.is_done("s2_quartermaster"), "The quartermaster failed: off the board today")
	Economy.advance_days(1, "story test")
	check(_offered() == ["s2_quartermaster"], "and back on it the next day")
	_close_story("s2_quartermaster", "completed")
	check(Story.evidence() == 2 and _offered() == ["s3_crates"], "The quartermaster done: evidence 2, The crates on the board")
	# Intel advances the arc: Vantage point waits on the evidence as well as on The crates.
	_close_story("s3_crates", "completed")
	check(Story.evidence() == 3 and _offered() == ["s4_vantage_point"], "The crates done: evidence 3, Vantage point on the board")
	var v := _story_contract("s4_vantage_point")
	(Contracts._s().board as Array).erase(v)
	(s.offered as Dictionary).erase("s4_vantage_point")
	s.evidence = 2  # (as if a clue had been lost)
	Story.server_update()
	check(_offered().is_empty() and Story.leads_text().contains("evidence 3 (have 2)"),
		"one evidence short, Vantage point waits, and the Leads say so (%s)" % Story.leads_text().split("\n")[1])
	check(Story.on_intel_turned_in("intel_laptop", 3) == 0 and _offered().is_empty(), "three ordinary pieces of intel aren't enough")
	check(Story.on_intel_turned_in("intel_documents", 1) == 1 and Story.evidence() == 3 and _offered() == ["s4_vantage_point"],
		"the fourth makes an evidence point: Vantage point on the board")
	check(Story.on_intel_turned_in(Story.LEDGER, 5) == Story.LEDGER_EVIDENCE_MAX and Story.on_intel_turned_in(Story.LEDGER, 1) == 0,
		"Vantage ledgers turned in count, up to %d" % Story.LEDGER_EVIDENCE_MAX)
	_close_story("s4_vantage_point", "completed")
	check(1 in (s.acts_done as Array) and Story.act() == 1 and Story.clues().size() == 4 and Story.leads_text().contains("Act 2 (Ashore) is still to come"),
		"Vantage point done: act 1 closes with 4 clues; act 2 is a stub (%s)" % Story.leads_text().split("\n")[1])
	check(Story.leads_text().contains("Halden Maritime") and int((Contracts._public().story as Dictionary).get("evidence", -1)) == Story.evidence(),
		"the Leads list every clue, and the contracts' view carries the story to clients")
	# The save round trip.
	var before := Story.view()
	check(Campaign.save_campaign(), "the campaign saves")
	s.clear()
	check(Campaign.load_campaign(), "and loads")
	var after := Story.view()
	check(after == before and Story.evidence() == int(before.evidence) and Story.clues().size() == 4 and Story.is_done("s4_vantage_point"),
		"the story comes back as it was (act %d, evidence %d, %d clues)" % [Story.act(), Story.evidence(), Story.clues().size()])


## Story ids on the board or held now.
func _offered() -> Array:
	var out: Array = []
	for c: Dictionary in (Contracts._s().board as Array) + (Contracts._s().held as Array):
		if String(c.get("story", "")) != "":
			out.append(String(c.story))
	return out


func _story_contract(id: String) -> Dictionary:
	for c: Dictionary in (Contracts._s().board as Array) + (Contracts._s().held as Array):
		if String(c.get("story", "")) == id:
			return c
	return {}


## A story contract off the board as it closes with `outcome` (as Contracts._close would).
func _close_story(id: String, outcome: String) -> void:
	var c := _story_contract(id)
	(Contracts._s().board as Array).erase(c)
	(Contracts._s().held as Array).erase(c)
	Story.on_contract_closed(c, outcome)
