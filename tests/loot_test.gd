extends Node
## Compound loot (Captain's tasking 2026-10-19, task 6; WorldValuables, data/loot_tables.json):
## the tables (every tier filled, known items, stated weights adding up), every box spot clear of
## its module's walls, furniture, garrison posts, mission points, loose loot and pallets; each
## site type's boxes fit their tables, with valuables and intel in the fitting rooms (an HQ's
## office and radio room); over many seeds each tier's share stays within its stated weight (very
## rare only in a hot zone); the same seed gives the same loot; and in a real zone the boxes stand
## on the floor holding their roll, and a looted box stays looted (and a strongbox unlocked) after
## a save and reload. One process:
##   <exe> --headless --path . res://tests/loot_test.tscn
## Prints LOOT TEST PASSED/FAILED and exits with its failure count.

## Boxes rolled per site type (and per hot or not) for the rarity check.
const RARITY_ROLLS := 4000
## A tier's measured share may be off its stated weight by this many standard errors, plus
## RARITY_SLACK (the rolls are seeded, so the result is fixed; the slack is for re-tuning).
const RARITY_SIGMAS := 4.0
const RARITY_SLACK := 0.005
## Clearances for a box spot (m, centre to centre on the ground): a garrison post (a man stands
## there), a mission point (an objective, intel or cache goes there), loose loot (a WorldItem drops
## there), another box, a supply pallet.
const CLEAR_POST_M := 1.0
const CLEAR_POINT_M := 0.9
const CLEAR_LOOT_M := 1.0
const CLEAR_BOX_M := 1.0
const CLEAR_PALLET_M := 1.5

var failures := 0
var level: ZoneLevel
var main: Node
var player: Soldier


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_loot" + tag  # never touch a real save
	Campaign.campaign_id = "test_loot" + tag
	CompoundLevel.spawn_ai = false
	get_tree().create_timer(280.0).timeout.connect(func() -> void:
		print("LOOT TEST FAILED (timed out)")
		get_tree().quit(99))
	GameState.delete_save()
	_test_tables()
	_test_spots()
	_test_site_rolls()
	_test_rarity()
	_test_same_seed()
	_test_pockets()
	await _test_cache_record()
	await _test_zone()
	GameState.delete_save()
	print("LOOT TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


## Pocket loot (Captain, 2026-10-20: "we stil havent gotten loot variety in"): every hostile body
## carries 1 to 3 rolled finds besides its kit, a leader intel too; 40 bodies carry many kinds of
## thing, and the same seed rolls the same.
func _test_pockets() -> void:
	print("Pocket loot on bodies")
	var kinds := {}
	var per := []
	for i in 40:
		var got := WorldValuables.roll_pockets("body%d" % i, false)
		per.append(got.size())
		for e: Dictionary in got:
			kinds[String(e.id)] = true
	var leader := WorldValuables.roll_pockets("boss", false, true)
	var intel := leader.any(func(e: Dictionary) -> bool: return ItemDB.get_item(StringName(e.id)).type == "intel")
	check(per.min() >= 1 and kinds.size() >= 15, "40 bodies: each carries something, %d kinds of find among them" % kinds.size())
	check(intel, "a leader carries intel (%s)" % [leader.map(func(e: Dictionary) -> String: return String(e.id))])
	check(WorldValuables.roll_pockets("body7", false) == WorldValuables.roll_pockets("body7", false), "the same seed rolls the same")


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


## The site types with loot tables: every hand-built enemy site.
func _site_types() -> Array[String]:
	var out: Array[String] = []
	for t: String in ZoneModules.TYPES:
		if t != "fob":
			out.append(t)
	return out


# --- The tables -------------------------------------------------------------------------------

func _test_tables() -> void:
	print("The loot tables")
	var data := WorldValuables.loot_data()
	var tables: Dictionary = data.get("tables", {})
	var full := true
	var unknown: Array = []
	for name: String in tables:
		for tier: String in WorldValuables.TIERS:
			var bundles: Array = (tables[name] as Dictionary).get(tier, [])
			full = full and not bundles.is_empty()
			for bundle: Array in bundles:
				for row: Array in bundle:
					if not ItemDB.has_item(StringName(String(row[0]))) or int(row[1]) < 1 or (row.size() > 2 and int(row[2]) < int(row[1])):
						unknown.append(row)
	check(tables.size() >= 8 and full, "%d tables, every one with all four tiers (%s)" % [tables.size(), ", ".join(WorldValuables.TIERS)])
	check(unknown.is_empty(), "every row is a known item with a count of 1 or more (%s)" % [unknown])
	var sums := {}
	var missing: Array = []
	for t: String in _site_types():
		var spec := WorldValuables.site_spec(t)
		if spec.is_empty():
			missing.append(t)
			continue
		var sum := 0.0
		for tier: String in WorldValuables.TIERS:
			sum += float((spec.tier_weights as Dictionary).get(tier, 0.0))
		sums[t] = sum
		for spot: Dictionary in spec.spots:
			if not tables.has(String(spot.table)):
				missing.append("%s.%s -> %s" % [t, spot.id, spot.table])
		if not (spec.spots as Array).any(func(s: Dictionary) -> bool: return bool(s.get("always", false))):
			missing.append("%s: no box every time" % t)
	check(missing.is_empty(), "every enemy site type has its spots, at least one box every time, on known tables (%s)" % [missing])
	check(sums.values().all(func(s: float) -> bool: return is_equal_approx(s, 100.0)), "each site's stated tier weights add up to 100%% (%s)" % [sums])
	var rare_ok := true
	for t: String in _site_types():
		var w := WorldValuables.tier_weights(t)
		rare_ok = rare_ok and float(w.rare) + float(w.very_rare) <= 20.0 and float(w.very_rare) < float(w.rare) and float(w.rare) < float(w.uncommon) \
			and float(w.uncommon) < float(w.common)
	check(rare_ok, "rare finds are rare: rare and very rare together 20% or less a box at every site, each tier rarer than the one before")
	var hq := WorldValuables.site_spec("hq")
	var always := (hq.spots as Array).filter(func(s: Dictionary) -> bool: return bool(s.get("always", false))).map(func(s: Dictionary) -> String: return String(s.table))
	check("office" in always and "radio_room" in always, "an HQ always has its office desk and its radio room box (%s)" % [always])
	var comms_always := (WorldValuables.site_spec("comms").spots as Array).filter(func(s: Dictionary) -> bool: return bool(s.get("always", false)))
	check(comms_always.any(func(s: Dictionary) -> bool: return String(s.table) == "radio_room"), "a comms site always has its radio desk")
	check(WorldValuables.site_spec("outpost+5") == WorldValuables.site_spec("outpost"), "a grown outpost loots as an outpost")


# --- Where the boxes stand --------------------------------------------------------------------

func _test_spots() -> void:
	print("Box spots")
	var problems: Array = []
	var half := WorldCache.SIZE * 0.5
	for t: String in _site_types():
		var walls := ZoneModules.boxes_m(t)
		var spots: Array = WorldValuables.site_spec(t).spots
		var module_half: Vector2 = ZoneModules.HALF[t]
		for spot: Dictionary in spots:
			var p := Vector3(float(spot.pos[0]), 0.0, float(spot.pos[1]))
			var flat := Vector2(p.x, p.z)
			var foot := AABB(p - Vector3(half.x, -0.02, half.z), Vector3(WorldCache.SIZE.x, WorldCache.SIZE.y - 0.02, WorldCache.SIZE.z))
			for wall: AABB in walls:
				if wall.intersects(foot):
					problems.append("%s.%s in %s" % [t, spot.id, wall])
					break
			if absf(p.x) > module_half.x - 1.0 or absf(p.z) > module_half.y - 1.0:
				problems.append("%s.%s outside the site" % [t, spot.id])
			for post: Vector3 in ZoneModules.GARRISON.get(t, []):
				if post.y < 1.0 and flat.distance_to(Vector2(post.x, post.z)) < CLEAR_POST_M:
					problems.append("%s.%s on a garrison post %s" % [t, spot.id, post])
			for kind: String in ZoneModules.POINTS.get(t, {}):
				for point: Vector3 in ZoneModules.points(t, kind):
					if flat.distance_to(Vector2(point.x, point.z)) < CLEAR_POINT_M:
						problems.append("%s.%s on the %s point" % [t, spot.id, kind])
			for loot: Dictionary in ZoneModules.LOOT.get(t, []):
				if flat.distance_to(Vector2(loot.pos.x, loot.pos.z)) < CLEAR_LOOT_M:
					problems.append("%s.%s on the %s" % [t, spot.id, loot.id])
			for other: Dictionary in spots:
				if other != spot and flat.distance_to(Vector2(float(other.pos[0]), float(other.pos[1]))) < CLEAR_BOX_M:
					problems.append("%s.%s on %s" % [t, spot.id, other.id])
			for pallet: Dictionary in Pallets.sites(t):
				if flat.distance_to(Vector2(float(pallet.x), float(pallet.z))) < CLEAR_PALLET_M:
					problems.append("%s.%s on a pallet" % [t, spot.id])
			for v: Dictionary in Pallets.site_vehicles(t):
				if flat.distance_to(Vector2(float(v.x), float(v.z))) < 4.0:
					problems.append("%s.%s on the parked %s" % [t, spot.id, v.model])
	check(problems.is_empty(), "every box spot is on its floor clear of walls, furniture, posts, mission points, loose loot, other boxes, pallets and vehicles (%s)" % [problems])


# --- What's in them ---------------------------------------------------------------------------

## Whether `items` ([{"id", "count"}]) is exactly one bundle of `table`'s `tier`, its counts in range.
func _fits(items: Array, table: String, tier: String) -> bool:
	var bundles: Array = ((WorldValuables.loot_data().tables as Dictionary).get(table, {}) as Dictionary).get(tier, [])
	for bundle: Array in bundles:
		if bundle.size() != items.size():
			continue
		var ok := true
		for i in bundle.size():
			var row: Array = bundle[i]
			var it: Dictionary = items[i]
			var lo := int(row[1])
			var hi := int(row[2]) if row.size() > 2 else lo
			ok = ok and String(it.id) == String(row[0]) and int(it.count) >= lo and int(it.count) <= hi
		if ok:
			return true
	return false


func _is_find(id: String) -> bool:
	var item := ItemDB.get_item(StringName(id))
	return item != null and (item.type in ["valuable", "intel"])


func _test_site_rolls() -> void:
	print("Each site's boxes fit its tables")
	var misfits: Array = []
	var counts := {}
	var office_finds := [0, 0]
	var radio_intel := [0, 0]
	for t: String in _site_types():
		var spec := WorldValuables.site_spec(t)
		var always := (spec.spots as Array).filter(func(s: Dictionary) -> bool: return bool(s.get("always", false))).size()
		var extra: Array = spec.extra
		var lo := 99
		var hi := 0
		for n in 300:
			var hot := n % 2 == 0
			var plan := WorldValuables.site_plan(t, "zone%d|%s" % [n, t], hot)
			lo = mini(lo, plan.size())
			hi = maxi(hi, plan.size())
			var keys := plan.map(func(b: Dictionary) -> String: return String(b.key))
			for spot: Dictionary in spec.spots:
				if bool(spot.get("always", false)) and String(spot.id) not in keys:
					misfits.append("%s lacks %s" % [t, spot.id])
			for box: Dictionary in plan:
				var spot: Dictionary = (spec.spots as Array).filter(func(s: Dictionary) -> bool: return String(s.id) == String(box.key))[0]
				if String(box.table) != String(spot.table) or not _fits(box.items, String(box.table), String(box.tier)):
					misfits.append("%s.%s: %s %s %s" % [t, box.key, box.table, box.tier, box.items])
				if String(box.tier) == "very_rare" and not hot:
					misfits.append("%s.%s very rare outside a hot zone" % [t, box.key])
				if String(box.table) == "office":
					office_finds[1] += 1
					if (box.items as Array).any(func(e: Dictionary) -> bool: return _is_find(String(e.id))):
						office_finds[0] += 1
				if String(box.table) == "radio_room":
					radio_intel[1] += 1
					if (box.items as Array).any(func(e: Dictionary) -> bool: return ItemDB.get_item(StringName(e.id)).type == "intel" or String(e.id) in ["enemy_radio", "radio", "jammer"]):
						radio_intel[0] += 1
		counts[t] = "%d-%d" % [lo, hi]
		if lo != always + int(extra[0]) or hi > always + int(extra[1]):
			misfits.append("%s: %d to %d boxes, stated %d + %s" % [t, lo, hi, always, extra])
	check(misfits.is_empty(), "300 rolls of each site type: every box holds one bundle of its table at its tier, the fitting rooms every time (%s)%s" % [counts, "" if misfits.is_empty() else " %s" % [misfits.slice(0, 6)]])
	check(office_finds[1] > 0 and office_finds[0] == office_finds[1], "every office desk holds valuables or intel (%d of %d)" % office_finds)
	check(radio_intel[1] > 0 and radio_intel[0] * 2 > radio_intel[1], "most radio room boxes hold intel or a radio (%d of %d)" % radio_intel)
	var town := WorldValuables.site_plan("town#311", "zone|town", false)
	check(not town.is_empty() and town.all(func(b: Dictionary) -> bool: return _fits(b.items, String(b.table), String(b.tier))),
		"a generated town still gets boxes by its loot spots, on the fallback table (%d)" % town.size())
	check(WorldValuables.site_plan("fob", "zone|fob", true).is_empty(), "the company's own FOB gets none")


func _test_rarity() -> void:
	print("Rare finds are rare (%d boxes a site type)" % RARITY_ROLLS)
	for t: String in _site_types():
		var weights := WorldValuables.tier_weights(t)
		var total := 0.0
		for tier: String in WorldValuables.TIERS:
			total += float(weights.get(tier, 0.0))
		var table := String((WorldValuables.site_spec(t).spots as Array)[0].table)
		for hot: bool in [true, false]:
			var seen := {}
			for i in RARITY_ROLLS:
				var tier := String(WorldValuables.roll_box(table, weights, "rarity|%s|%d" % [t, i], hot).tier)
				seen[tier] = int(seen.get(tier, 0)) + 1
			var ok := true
			var line: Array = []
			for tier: String in WorldValuables.TIERS:
				var p := float(weights.get(tier, 0.0)) / total
				if not hot and tier == "rare":
					p += float(weights.get("very_rare", 0.0)) / total  # capped outside a hot zone
				elif not hot and tier == "very_rare":
					p = 0.0
				var got := float(seen.get(tier, 0)) / RARITY_ROLLS
				var tolerance := RARITY_SIGMAS * sqrt(p * (1.0 - p) / RARITY_ROLLS) + RARITY_SLACK
				ok = ok and absf(got - p) <= tolerance and (p > 0.0 or got == 0.0)
				line.append("%s %.1f%% (stated %.1f)" % [tier, got * 100.0, p * 100.0])
			check(ok, "%s, %s: %s" % [t, "hot zone" if hot else "contract zone", ", ".join(line)])


func _test_same_seed() -> void:
	print("The same seed, the same loot")
	var same := true
	var differs := 0
	for t: String in _site_types():
		var a := WorldValuables.site_plan(t, "red_mesa|%s" % t, true)
		same = same and str(a) == str(WorldValuables.site_plan(t, "red_mesa|%s" % t, true))
		for z in 10:
			if str(WorldValuables.site_plan(t, "zone%d|%s" % [z, t], true)) != str(a):
				differs += 1
	check(same, "a site rolled twice from the same zone and module gives the same boxes and the same loot")
	check(differs >= 50, "another zone's site of the same type rolls its own (%d of 70 differ)" % differs)


# --- Saved with the zone ----------------------------------------------------------------------

## A cache's record round-trips: emptied stays empty, a strongbox opened stays open.
func _test_cache_record() -> void:
	print("A cache's saved record")
	var a := WorldCache.new("Desk")
	a.uid = "rec_a"
	add_child(a)
	a.server_fill([{"id": "cash_bundle", "count": 2}, {"id": "intel_phone", "count": 1}])
	check(a.cargo_hold.count_of(&"cash_bundle") == 2 and a.cargo_hold.count_of(&"intel_phone") == 1, "with no save it holds its roll")
	a.cargo_hold.remove_entry(VehicleCargo.HOLD, 0, 2)
	var box := WorldCache.new(WorldValuables.STRONGBOX_LABEL, WorldValuables.STRONGBOX_KEY)
	box.uid = "rec_box"
	add_child(box)
	box.server_fill(WorldValuables.strongbox_contents("hq_x"))
	box.unlocked = true
	GameState.caches = {"rec_a": a.to_save(), "rec_box": box.to_save()}
	a.queue_free()
	box.queue_free()
	await get_tree().process_frame
	var a2 := WorldCache.new("Desk")
	a2.uid = "rec_a"
	add_child(a2)
	a2.server_fill([{"id": "cash_bundle", "count": 2}, {"id": "intel_phone", "count": 1}])
	var box2 := WorldCache.new(WorldValuables.STRONGBOX_LABEL, WorldValuables.STRONGBOX_KEY)
	box2.uid = "rec_box"
	add_child(box2)
	box2.server_fill(WorldValuables.strongbox_contents("hq_x"))
	check(a2.cargo_hold.count_of(&"cash_bundle") == 0 and a2.cargo_hold.count_of(&"intel_phone") == 1, "a box with its cash taken comes back without it, not restocked")
	check(not box2.is_locked(), "an opened strongbox stays open")
	GameState.caches = {"rec_bad": {"items": [{"id": "no_such_item", "count": 1}]}, "rec_ok": {"items": [], "unlocked": false}}
	var path := "user://saves/test_loot_record.json"
	GameState.write_safely(path, JSON.stringify({"version": GameState.SAVE_VERSION, "caches": GameState.caches}))
	var read := GameState.read_save(path)
	check((read.get("caches", {}) as Dictionary).has("rec_ok") and not (read.get("caches", {}) as Dictionary).has("rec_bad"),
		"reading a save keeps a good cache record (an emptied box) and skips one naming an unknown item")
	for p: String in GameState.save_candidates(path):
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	GameState.caches = {}
	a2.queue_free()
	box2.queue_free()
	await get_tree().process_frame


## A real zone: the site boxes stand on their floors holding the roll site_plan says; one is
## looted, the zone saved and hosted again: it stays empty, the others hold what they held.
func _test_zone() -> void:
	print("Site boxes in a zone, looted, saved and reloaded")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var def := ZoneDef.get_def("test")
	main.host_zone(def)
	level = CompoundLevel.current(self) as ZoneLevel
	check(level != null, "the test zone is up")
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 10.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	var zone_id := String(level.def.get("id", GameState.zone_id))
	var hot := String(level.def.get("kind", "")) == "hot"
	var wrong: Array = []
	var floating: Array = []
	var total := 0
	for m: ZoneModule in level.modules():
		for box: Dictionary in WorldValuables.site_plan(m.type, "%s|%s" % [zone_id, m.module_id], hot):
			total += 1
			var node := level.get_node_or_null(NodePath("Caches/%s_box_%s" % [m.module_id, box.key])) as WorldCache
			if node == null:
				wrong.append("%s_box_%s missing" % [m.module_id, box.key])
				continue
			var held := node.cargo_hold.entries().map(func(e: Dictionary) -> String: return "%s x%d" % [e.id, int(e.count)])
			var rolled := (box.items as Array).map(func(e: Dictionary) -> String: return "%s x%d" % [e.id, int(e.count)])
			if str(held) != str(rolled) or node.display_name() != String(box.label):
				wrong.append("%s: %s, rolled %s" % [node.name, held, rolled])
			if absf(node.global_position.y - m.global_position.y) > 0.3:
				floating.append("%s %.2f" % [node.name, node.global_position.y - m.global_position.y])
	check(total >= level.modules().size() and wrong.is_empty(), "every module's boxes are there holding their roll, by name (%d boxes; %s)" % [total, wrong])
	check(floating.is_empty(), "and stand on their floors (%s)" % [floating])
	var desk := level.get_node_or_null(^"Caches/compound_box_office") as WorldCache
	var armory := level.get_node_or_null(^"Caches/compound_box_armory") as WorldCache
	check(desk != null and armory != null and desk.display_name() == "Desk" and armory.display_name() == "Weapons crate",
		"the compound has its command building desk and its armory crate")
	if desk == null or armory == null:
		return
	var m := level.get_module("compound")
	check(m.to_local(desk.global_position).distance_to(Vector3(4.0, 0.0, -11.0)) < 0.05, "the desk is in the command building (%s)" % m.to_local(desk.global_position))
	var armory_before := str(armory.cargo_hold.entries())
	player.global_position = desk.global_position + Vector3(0, 0, 1.2)
	var guard := 0
	while not desk.cargo_hold.entries().is_empty() and guard < 20:
		guard += 1
		var e: Dictionary = desk.cargo_hold.entries()[0]
		desk.server_unload(player, 0, e.id)
	check(desk.cargo_hold.entries().is_empty(), "the desk is looted bare")
	GameState.save_zone()
	var saved: Dictionary = GameState.read_save(GameState.save_path()).get("caches", {})
	check((saved.get("compound_box_office", {"items": [1]}) as Dictionary).items.is_empty() and saved.has("compound_box_armory"),
		"the save keeps the emptied desk and the armory crate (%d caches saved)" % saved.size())
	Net.leave()
	var old := level
	main.remove_child(old)
	old.queue_free()
	await get_tree().process_frame
	main.host_zone(def)
	level = CompoundLevel.current(self) as ZoneLevel
	if level == null:
		check(false, "the test zone hosts again")
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 10.0)
	desk = level.get_node_or_null(^"Caches/compound_box_office") as WorldCache
	armory = level.get_node_or_null(^"Caches/compound_box_armory") as WorldCache
	check(desk != null and desk.cargo_hold.entries().is_empty(), "after the reload the looted desk is still empty, not restocked (%s)" % [desk.cargo_hold.entries() if desk else "missing"])
	check(armory != null and str(armory.cargo_hold.entries()) == armory_before, "and the armory crate nobody touched holds what it held (%s)" % [armory.cargo_hold.entries() if armory else "missing"])
	Net.leave()
