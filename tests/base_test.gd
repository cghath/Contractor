extends Node
## Headless checks of the base hub, the roster and hiring (wave 4, W12):
##   <voxel godot exe> --headless --path . res://tests/base_test.tscn
## The rules first (hiring from a seed, wages, growth after a mission, injuries and the medbay,
## the respawn pool, MIA, stand-ins), then a real session: the hub with its stash and muster
## line, a second process joining it as a client (it must see the same roster and stash, and
## hire through the host), the armory round trip, a deployment into the compound with the
## roster's own people in their own gear, extraction with one MIA and one killed, back to the
## hub, and a save and reload. A second client joins late, mid-deployment, with a plain
## Join: it must land in the zone with the squad. Exits with the number of failures.
##
## The client is this scene again with `-- --join 127.0.0.1 --expect <base64 JSON>` (the late
## joiner `-- --late --expect ...`: it joins through the menu); it writes its checks to a log
## the host prints.

const SEED := 4242
## Items the test stash holds besides the starting stash.
const EXTRA_STASH := [["m17", 1], ["burn_dressing", 3]]
## The client's log line once its hub checks are done (the host goes on then).
const CLIENT_HUB_DONE := "HUB CHECKS DONE"
## ...and once it has looked at the zone (the host extracts then).
const CLIENT_ZONE_DONE := "ZONE CHECKS DONE"
## The zone the test deploys to (its save is the campaign's: BaseHub.zone_save_id).
const ZONE := "test_base_zone"

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var level: CompoundLevel
var _log: FileAccess  # client: where its checks go


func _ready() -> void:
	GameState.zone_id = "test_base" + tag
	Campaign.campaign_id = "test_base" + tag  # never touch a real save
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		_say("BASE TEST FAILED (timed out)")
		get_tree().quit(99))
	if "--late" in OS.get_cmdline_user_args():
		await _run_late_client()
		return
	if "--join" in OS.get_cmdline_user_args():
		await _run_client()
		return
	GameState.delete_save()
	Campaign.reset_campaign()
	_test_stash_and_saves()
	_test_damaged_saves()
	_test_hiring()
	_test_wages()
	_test_growth()
	_test_injuries_and_medbay()
	_test_respawn_pool()
	_test_resolve()
	_test_stand_ins()
	_test_restock()
	await _test_session()
	for zone_id: String in [ZONE + tag, ZONE + "_wide" + tag]:
		GameState.zone_id = BaseHub.zone_save_id(zone_id)
		GameState.delete_save()
	GameState.zone_id = "test_base" + tag
	GameState.delete_save()
	Campaign.reset_campaign()
	print("BASE TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	_say("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _say(text: String) -> void:
	if _log:
		_log.store_line(text)
		_log.flush()
	else:
		print(text)


# --- The rules -------------------------------------------------------------------------------

func _test_stash_and_saves() -> void:
	print("The stash and the saves")
	var stash: Array = []
	var plate := ItemDB.get_item(&"plate_ceramic_l4")
	BaseArmory.add(stash, &"plate_ceramic_l4", 1, plate.default_state())
	BaseArmory.add(stash, &"plate_ceramic_l4", 2)
	BaseArmory.add(stash, &"m4a1", 1, ItemDB.get_item(&"m4a1").default_state())
	BaseArmory.add(stash, &"m4a1", 1)
	check(stash.size() == 2 and stash.all(func(e: Dictionary) -> bool: return not e.has("state")) and BaseArmory.count_of(stash, &"plate_ceramic_l4") == 3,
		"items in their default state stack with plain ones (as in an inventory)")
	BaseArmory.add(stash, &"plate_ceramic_l4", 1, {"chips": [[1, 2]]})
	check(stash.size() == 3 and BaseArmory.count_of(stash, &"plate_ceramic_l4") == 4, "a damaged plate keeps its own entry")
	# A campaign never loaded is never saved (it would wipe the real save).
	Campaign.reset_campaign()
	BaseHub.server_save()
	check(not FileAccess.file_exists(Campaign.save_path()), "no campaign loaded: nothing is saved over the save")
	BaseHub.new_campaign(SEED)
	check(BaseHub.zone_save_id("compound_01") != "compound_01" and BaseHub.base_zone_id().begins_with(Campaign.campaign_id),
		"the campaign's zone saves are its own (%s)" % BaseHub.zone_save_id("compound_01"))
	GameState.zone_id = BaseHub.zone_save_id("old_zone")
	GameState.save_zone()
	var path := GameState.save_path()
	BaseHub.new_campaign(SEED)
	check(not FileAccess.file_exists(path), "and a new campaign starts with none")
	GameState.zone_id = "test_base" + tag
	# Requests the host refuses.
	BaseHub.campaign_running = true
	var notes: Array = []
	var on_note := func(text: String) -> void: notes.append(text)
	BaseHub.note.connect(on_note)
	BaseHub.request("pick", ["x"])
	BaseHub.note.disconnect(on_note)
	BaseHub.campaign_running = false
	check(notes == ["Bad request"], "a request short of its arguments is refused (%s)" % ", ".join(PackedStringArray(notes)))


## Audit A1-01 to A1-04: a campaign save that's missing, cut off, broken or of another version
## never costs the campaign: its backup or an interrupted write loads; files that can't be read,
## and the zones of a campaign that can't be, are kept aside (never deleted, never loaded) and
## the host is told; a save that can't be written says so and leaves the last good one.
func _test_damaged_saves() -> void:
	print("Damaged, missing and unwritable campaign saves")
	var path := Campaign.save_path()
	var bak := GameState.backup_path(path)
	var notes: Array = []
	var on_note := func(text: String) -> void: notes.append(text)
	BaseHub.note.connect(on_note)
	BaseHub.new_campaign(SEED)
	BaseHub.base()["sentinel"] = 731
	check(BaseHub.server_save(), "a campaign saves")
	var good := FileAccess.get_file_as_string(path)
	var data: Dictionary = JSON.parse_string(good)
	# The save itself gone (lost between write_safely's renames): the backup is the campaign.
	_wipe_campaign_files()
	_write(bak, good)
	BaseHub.load_or_new()
	check(Campaign.last_load == Campaign.Loaded.LOADED and int(BaseHub.base().get("sentinel", 0)) == 731,
		"with the save gone its backup loads, not a new campaign (A1-02)")
	check(notes.any(func(n: String) -> bool: return n.contains(bak.get_file())), "and the host is told which copy loaded")
	# A new save written whole but not put in place yet is newer than the backup.
	_wipe_campaign_files()
	data.sections.base.sentinel = 732
	_write(path + ".tmp", JSON.stringify(data))
	_write(bak, good)
	BaseHub.load_or_new()
	check(int(BaseHub.base().get("sentinel", 0)) == 732, "an interrupted save's finished temporary file loads before the older backup")
	# Saves this game can't use (A1-03): another version, a section of the wrong shape, nothing.
	data.sections.base.sentinel = 731
	var bad_economy: Dictionary = data.duplicate(true)
	bad_economy.sections.economy = []
	var bad_board: Dictionary = data.duplicate(true)
	bad_board.sections.contracts.board = [1, 2]
	var wrong := {"version 999": JSON.stringify({"version": 999, "sections": data.sections}), "an economy that is a list": JSON.stringify(bad_economy),
		"a contract board of numbers": JSON.stringify(bad_board), "no version or sections": "{}"}
	for what: String in wrong:
		_wipe_campaign_files()
		_write(path, wrong[what])
		_write(bak, good)
		BaseHub.load_or_new()
		var refused := GameState.kept_copies(path)
		check(int(BaseHub.base().get("sentinel", 0)) == 731 and refused.size() == 1
			and FileAccess.get_file_as_string("%s/%s" % [Campaign.SAVE_DIR, refused[0]]) == wrong[what],
			"a save with %s is refused: the backup loads and the refused file is kept as it was (%s)" % [what, ", ".join(refused)])
	# Nothing readable (A1-01): a new campaign, but nothing deleted.
	_wipe_campaign_files()
	_write(path, "{broken")
	_write(bak, "{also broken")
	var zone_path := "%s/%s.json" % [GameState.SAVE_DIR, BaseHub.zone_save_id("old_zone")]
	var zone_text := JSON.stringify({"version": GameState.SAVE_VERSION, "looted": ["old_progress"], "dropped": {}, "voxel_edits": [], "bodies": []})
	_write(zone_path, zone_text)
	_write(GameState.backup_path(zone_path), zone_text)
	notes.clear()
	BaseHub.load_or_new()
	var kept := GameState.kept_copies(path)
	var kept_text := Array(kept).map(func(f: String) -> String: return FileAccess.get_file_as_string("%s/%s" % [Campaign.SAVE_DIR, f]))
	check(BaseHub.started() and Campaign.last_load == Campaign.Loaded.UNREADABLE and not BaseHub.base().has("sentinel"),
		"with nothing readable a new campaign starts")
	check(kept.size() == 2 and "{broken" in kept_text and "{also broken" in kept_text,
		"but the unreadable save and backup are kept aside as they were (%s)" % ", ".join(kept))
	var zone_kept := GameState.kept_copies(zone_path)
	check(not GameState.has_save(zone_path) and zone_kept.size() == 2
		and FileAccess.get_file_as_string("%s/%s" % [GameState.SAVE_DIR, zone_kept[0]]) == zone_text,
		"and so are its zone saves: not deleted, and not loaded by the new campaign (%s)" % ", ".join(zone_kept))
	check(notes.any(func(n: String) -> bool: return n.contains("couldn't be read") and n.contains(kept[0] if kept.size() > 0 else "?"))
		and BaseHub._host_notice.contains("couldn't be read"), "the host is told where they are, now and when the base screen opens")
	for f in GameState.kept_copies(zone_path):
		DirAccess.remove_absolute("%s/%s" % [GameState.SAVE_DIR, f])
	BaseHub._host_notice = ""
	# A save that can't be written (A1-04): it says so, and the last good save stays.
	_wipe_campaign_files()
	BaseHub.new_campaign(SEED)
	check(BaseHub.server_save(), "a fresh campaign saves")
	var before := FileAccess.get_file_as_string(path)
	BaseHub.base()["sentinel"] = 999
	DirAccess.make_dir_recursive_absolute(path + ".tmp")  # a folder where the new save is written first: the write fails
	BaseHub.campaign_running = true
	notes.clear()
	var saved := BaseHub.server_save()
	BaseHub.request("save")
	check(not saved and FileAccess.get_file_as_string(path) == before and not Campaign.save_error.is_empty(),
		"a save that can't be written fails and leaves the last good save as it was")
	check(notes.size() == 1 and String(notes[0]).begins_with("Campaign NOT saved"), "and the save request says so, not \"Campaign saved\" (%s)" % ", ".join(PackedStringArray(notes)))
	DirAccess.remove_absolute(path + ".tmp")
	notes.clear()
	BaseHub.request("save")
	BaseHub.campaign_running = false
	check(notes == ["Campaign saved"] and int(JSON.parse_string(FileAccess.get_file_as_string(path)).sections.base.sentinel) == 999,
		"once it can be written it saves and says so")
	BaseHub.note.disconnect(on_note)
	_wipe_campaign_files()


## Deletes the campaign's save, backup, interrupted write and every copy kept aside.
func _wipe_campaign_files() -> void:
	Campaign.reset_campaign()
	for f in GameState.kept_copies(Campaign.save_path()):
		DirAccess.remove_absolute("%s/%s" % [Campaign.SAVE_DIR, f])


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _test_hiring() -> void:
	print("Hiring")
	BaseHub.new_campaign(SEED)
	var pool: Array = Hiring.pool(BaseHub.hiring(), 1)
	check(pool.size() == Hiring.POOL_SIZE and pool == Hiring.draw_pool(SEED, 0), "a new campaign's board: %d contractors drawn from the seed" % pool.size())
	check(Hiring.draw_pool(SEED, 0) == Hiring.draw_pool(SEED, 0) and Hiring.draw_pool(SEED, 1) != pool, "the same seed draws the same board; the next refresh another")
	check(Roster.members(BaseHub.roster()).is_empty(), "no fixed starting squad")
	check(BaseEconomy.funds() == Economy.cash() and Economy.cash() == MissionRegistry.setting_i("start_cash", 150000),
		"one bank: the base's funds are the economy's starting cash ($%d)" % BaseEconomy.funds())
	var ok := pool.all(func(c: Dictionary) -> bool:
		return Roles.has(StringName(c.role)) and int(c.demand) > 0 and int(c.fee) == int(c.demand) * Hiring.FEE_DAYS \
			and Roster.SKILLS.all(func(s: String) -> bool: return float(c.skills[s]) > 0.0 and float(c.skills[s]) <= 1.0))
	check(ok, "each has a role, skills, a wage demand and a fee of %d days' wage" % Hiring.FEE_DAYS)
	# Veterans cost more.
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var rookie := []
	var veteran := []
	for i in 400:
		var c := Hiring.candidate(rng)
		if int(c.missions) <= 2:
			rookie.append(int(c.demand))
		elif int(c.missions) >= 10:
			veteran.append(int(c.demand))
	check(not veteran.is_empty() and _mean(veteran) > _mean(rookie) + 20.0, "veterans ask more (about $%d/day against $%d)" % [_mean(veteran), _mean(rookie)])
	# Hire the cheapest.
	var cheapest := _cheapest(pool)
	var funds := BaseEconomy.funds()
	var why := BaseHub.server_hire(String(cheapest.cid))
	var ids := Roster.ids(BaseHub.roster())
	var m := BaseHub.member(ids[0]) if ids.size() == 1 else {}
	check(why == "" and ids.size() == 1 and BaseEconomy.funds() == funds - int(cheapest.fee), "hiring %s costs the $%d fee" % [cheapest.name, int(cheapest.fee)])
	check(not m.is_empty() and m.callsign == cheapest.callsign and m.role == cheapest.role and int(m.wage) == int(cheapest.demand)
		and Roster.gear_counts(m.gear).size() > 3, "they join with their role, skills, wage and their role's kit as their own gear")
	if not m.is_empty():
		_check_kit_pouches(m)
	_check_identity(pool, m, cheapest)
	check(Hiring.find(BaseHub.hiring(), String(cheapest.cid), 1).is_empty(), "and leave the board")
	var cash := Economy.cash()
	Economy.add_cash(10 - cash, "test: nearly broke")
	var pricey := _cheapest(Hiring.pool(BaseHub.hiring(), 1))
	check(BaseHub.server_hire(String(pricey.cid)) != "" and Roster.ids(BaseHub.roster()).size() == 1, "no cash, no hire")
	Economy.add_cash(cash - 10, "test: the cash back")
	BaseHub.server_advance_days(Hiring.REFRESH_DAYS)
	check(int(BaseHub.hiring().refresh) == 1 and Hiring.pool(BaseHub.hiring(), BaseHub.day()) == Hiring.draw_pool(SEED, 1),
		"after %d days the board turns over (refresh 1, from the seed)" % Hiring.REFRESH_DAYS)


## Roster identity (Captain, 2026-10-11): each contractor on the board is a whole person, rolled
## once; the hire keeps them; a second with the same surname gets another; an older save's
## member keeps their roster name and gets the rest filled in once.
func _check_identity(pool: Array, m: Dictionary, hired: Dictionary) -> void:
	var people := true
	for c: Dictionary in pool:
		people = people and Names.POOLS.has(String(c.get("nation", ""))) and String(c.get("surname", "")) != "" \
			and String(c.name) == "%s %s" % [c.first, c.surname] and c.get("left") is bool and String(c.get("body", "")) in [Names.MALE, Names.FEMALE]
	check(people,
		"each contractor on the board is a person: first name, surname, nationality, hand, body")
	check(not m.is_empty() and m.surname == hired.surname and m.nation == hired.nation and m.left == hired.left and m.name == hired.name,
		"the hire is the person on the board (%s, %s)" % [m.get("name", "?"), Roster.person_text(m)])
	var data := {"members": {"m0001": m.duplicate(true)}, "next_id": 2}
	var twin := hired.duplicate(true)
	var mid := Roster.add_member(data, twin, 1)
	var second: Dictionary = Roster.get_member(data, mid)
	check(second.surname != m.surname and second.name == "%s %s" % [second.first, second.surname], "a second hire with the same surname gets another (%s)" % second.surname)
	var old := {"name": "Dale Okafor", "callsign": "Viper", "role": "rifleman"}
	check(Roster.ensure_identity(old) and old.surname == "Okafor" and old.first == "Dale" and old.name == "Dale Okafor"
		and Names.POOLS.has(String(old.nation)) and old.left == Handedness.roll_ai("Viper") and not Roster.ensure_identity(old),
		"an older save's member keeps their roster name and is filled in once (%s)" % Roster.person_text(old))
	var spawn := Roster.identity(old)
	check(spawn == {"person_name": "Okafor", "nation": old.nation, "left": old.left, "body": Names.MALE}, "and spawns as that person (%s)" % [spawn])


## A hire's own gear is their role's kit as dev's role kits wear it: the kit's pouches on the
## carrier's MOLLE points, magazines and the tourniquet in them (in the carrier's state), and
## every kit item counted, pouch contents included.
func _check_kit_pouches(m: Dictionary) -> void:
	var kit := Roles.kit(StringName(m.role))
	var want := {}
	var want_pouches := {}
	for pair: Array in kit:
		want[String(pair[0])] = int(want.get(String(pair[0]), 0)) + int(pair[1])
		if Inventory.is_attachable(ItemDB.get_item(pair[0])) and not Inventory.pack_only(ItemDB.get_item(pair[0])):  # (a packed AT4 or aid bag goes on the pack)
			want_pouches[String(pair[0])] = int(want_pouches.get(String(pair[0]), 0)) + int(pair[1])
	var molle: Dictionary = m.gear.get("slot_state", {}).get("vest", {}).get("molle", {})
	var on := {}
	var mags_in_pouches := 0
	var tq_held := false
	for point: String in molle:
		var att: Dictionary = molle[point]
		on[String(att.id)] = int(on.get(String(att.id), 0)) + 1
		for entry: Dictionary in att.get("held", []):
			if String(entry.id).begins_with("mag_"):
				mags_in_pouches += int(entry.count)
			tq_held = tq_held or (String(att.id) == "pouch_tq" and String(entry.id) == "tourniquet")
	check(on == want_pouches and mags_in_pouches > 0 and tq_held,
		"their carrier wears the kit's pouches (%d), with magazines (%d) and a tourniquet in them" % [molle.size(), mags_in_pouches])
	var counts := Roster.gear_counts(m.gear)
	var missing := want.keys().filter(func(id: String) -> bool: return int(counts.get(id, 0)) < int(want[id]))
	check(missing.is_empty(), "and all of the kit is counted, pouch contents too%s" % ("" if missing.is_empty() else " (short: %s)" % ", ".join(PackedStringArray(missing))))


func _test_wages() -> void:
	print("Wages")
	BaseHub.new_campaign(SEED)
	for i in 2:
		BaseHub.server_hire(String(_cheapest(Hiring.pool(BaseHub.hiring(), BaseHub.day())).cid))
	var daily := Roster.daily_wages(BaseHub.roster())
	var week := MissionRegistry.setting_i("week_days", 7)
	var funds := BaseEconomy.funds()
	var bill := Economy.weekly_bill()
	check(daily > 0 and int(bill.wages) == daily * week, "one clock: the roster's wages are the economy's weekly bill ($%d for two)" % int(bill.wages))
	BaseHub.server_advance_days(Economy.days_to_bill() - 1)
	check(BaseEconomy.funds() == funds, "nothing is paid during the week")
	BaseHub.server_advance_days(1)
	check(BaseEconomy.funds() == funds - int(bill.total), "the week's bill is paid on its day, base upkeep with it ($%d)" % int(bill.total))
	check(BaseHub.day() == Economy.day() and BaseHub.day() == MissionRegistry.setting_i("start_day", 1) + week, "the base's day is the economy's (day %d)" % BaseHub.day())


func _test_growth() -> void:
	print("Skills and wage after a mission")
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var m := Hiring.candidate(rng)
	m["missions"] = 0
	m["wage"] = Roster.wage_of(m)
	var before: Dictionary = m.skills.duplicate()
	var wage := int(m.wage)
	var stats := Roster.ai_stats(m)
	Roster.after_mission(m, rng, 2)
	check(Roster.SKILLS.all(func(s: String) -> bool: return float(m.skills[s]) > float(before[s])), "every skill grows (aim %.2f -> %.2f)" % [before.aim, m.skills.aim])
	check(int(m.wage) > wage and int(m.missions) == 1 and int(m.xp) >= Roster.XP_PER_MISSION, "and the wage ($%d -> $%d), a mission and experience" % [wage, int(m.wage)])
	var after := Roster.ai_stats(m)
	check(after.combat > stats.combat and after.discipline > stats.discipline, "the squad AI aims and holds better (combat %.2f -> %.2f)" % [stats.combat, after.combat])


func _test_injuries_and_medbay() -> void:
	print("Injuries and the medbay")
	var leg := {"part": &"shin_l", "kind": "fracture", "name": &"tibia_l"}  # as Vitals.wound_list() gives it
	var a := Roster.assess_injuries([leg], 1.0)
	check(int(a.days) == Roster.FRACTURE_DAYS and "broken left tibia" in a.injuries, "a broken leg sits out %d days (%s)" % [int(a.days), ", ".join(PackedStringArray(a.injuries))])
	var b := Roster.assess_injuries([leg, {"part": &"thigh_r", "kind": "arterial", "clamped": true}], 0.62)
	check(int(b.days) == Roster.FRACTURE_DAYS + 2 * Roster.EXTRA_INJURY_DAYS, "with surgery and heavy blood loss: %d days" % int(b.days))
	check(int(Roster.assess_injuries([{"part": &"forearm_l", "kind": "graze"}], 0.95).days) == 0, "a graze and a little blood cost nothing")
	var blast := Roster.assess_outcome({"wounds": [], "blood": 1.0, "burn": 0.25, "blast_lung": true})
	check(int(blast.days) == maxi(Roster.BURN_DAYS, Roster.BLAST_LUNG_DAYS) + Roster.EXTRA_INJURY_DAYS and "burns" in blast.injuries
		and "blast lung" in blast.injuries and int(Roster.assess_outcome({"burn": 0.05}).days) == 0,
		"burns over %d%% of the body and blast lung sit out %d days; a small burn nothing" % [roundi(Roster.SERIOUS_BURN * 100.0), int(blast.days)])
	# The wound model's own output, read the way extraction reads it (BaseHub._outcome_of).
	var broken := {}
	for i in 20:
		var v := Vitals.new()
		add_child(v)
		v.rng.seed = i + 1
		v.care_rng.seed = i + 1
		v.server_burn(0.3)
		v.server_fall(4.5)
		var o := {"wounds": v.wound_list(), "blood": v.blood_fraction(), "burn": v.burn_share(), "blast_lung": v.has_blast_lung()}
		v.queue_free()
		if o.wounds.any(func(w: Dictionary) -> bool: return String(w.kind) == "fracture" and StringName(w.name) in BodyMap.LEG_BONES):  # a leg, not the pelvis a fall can break too
			broken = Roster.assess_outcome(o)
			break
	check(not broken.is_empty() and int(broken.days) == Roster.FRACTURE_DAYS + Roster.EXTRA_INJURY_DAYS and "burns" in broken.injuries
		and (broken.injuries as Array).any(func(t: String) -> bool: return t.begins_with("broken left ") or t.begins_with("broken right ")),
		"a fall that breaks a leg and 30%% burns, from Vitals: %s" % ", ".join(PackedStringArray(broken.get("injuries", []))))
	BaseHub.new_campaign(SEED)
	BaseHub.server_hire(String(_cheapest(Hiring.pool(BaseHub.hiring(), 1)).cid))
	var mid := Roster.ids(BaseHub.roster())[0]
	var m := BaseHub.member(mid)
	Roster.injure(m, b, BaseHub.day())
	check(not Roster.is_available(m) and int(m.sit_out_days) == int(b.days), "a wounded squadmate sits out (%s)" % Roster.status_text(m))
	var quote := Roster.medbay_quote(m)
	var funds := BaseEconomy.funds()
	var why := BaseHub.server_medbay(mid)
	check(why == "" and int(m.sit_out_days) == int(b.days) - int(quote.days_saved) and BaseEconomy.funds() == funds - int(quote.cost),
		"the medbay takes %d days off for $%d" % [int(quote.days_saved), int(quote.cost)])
	check(BaseHub.server_medbay(mid) != "", "once per injury")
	BaseHub.server_advance_days(int(m.sit_out_days))
	check(Roster.is_available(m) and (m.injuries as Array).is_empty(), "days pass and they're fit again")
	var main := Roster.main_character(BaseHub.roster(), "medbay_player")
	Roster.injure(main, a, BaseHub.day())
	check(BaseHub.server_medbay("player:medbay_player") == "" and int(main.sit_out_days) == Roster.FRACTURE_DAYS / 2,
		"players' main characters recover the same way (%d days left)" % int(main.sit_out_days))


func _test_respawn_pool() -> void:
	print("Respawn pool")
	BaseHub.new_campaign(SEED)
	var roster := BaseHub.roster()
	RosterDeployment.begin(roster, [], RosterDeployment.CONTRACT, "z", "", 1)
	for i in 4:
		BaseHub.server_count_respawn()
	var funds := BaseEconomy.funds()
	check(RosterDeployment.free_respawns_left(roster) == 0 and BaseEconomy.funds() == funds, "a contract zone: 4 free respawns")
	BaseHub.server_count_respawn()
	var dep := RosterDeployment.active(roster)
	check(int(dep.respawns_bought) == 1 and BaseEconomy.funds() == funds - BaseEconomy.respawn_price(), "the fifth is bought ($%d)" % BaseEconomy.respawn_price())
	var second := RosterDeployment.respawn_cost(roster, BaseEconomy.respawn_price(), Prices.respawn_rise())
	check(second > BaseEconomy.respawn_price(), "each one bought costs more ($%d next)" % second)
	# Cash first, then the deployed contract's support budget (Captain), then credit.
	var offer: Dictionary = Contracts.board().filter(func(c: Dictionary) -> bool: return c.source != "recovery")[0]
	var terms := ContractGen.default_terms()
	terms["support_points"] = 1
	var cid := String(offer.cid)
	check(Contracts.server_accept(cid, terms) == "" and Contracts.server_start_deployment([cid]) == "", "(a contract with a support budget is deployed)")
	var budget := Contracts.support_left(cid)
	Economy.add_cash(500 - Economy.cash(), "test: $500 left")
	BaseHub.server_count_respawn()
	check(int(dep.respawns_bought) == 2 and BaseEconomy.funds() == 0 and Contracts.support_left(cid) == budget - (second - 500),
		"short of cash: the $500 there, the rest from the support budget ($%d of $%d)" % [second - 500, budget])
	Contracts.server_draw_support(cid, Contracts.support_left(cid))
	var third := RosterDeployment.respawn_cost(roster, BaseEconomy.respawn_price(), Prices.respawn_rise())
	BaseHub.server_count_respawn()
	check(int(dep.respawns_bought) == 3 and BaseEconomy.funds() == -third, "with neither, it goes on credit ($%d)" % third)
	Contracts.server_abandon_deployment()
	RosterDeployment.begin(roster, [], RosterDeployment.HOT, "z", "", 1)
	check(RosterDeployment.free_respawns_left(roster) == 8, "a hot zone: 8 free")
	roster["deployment"] = {}


func _test_resolve() -> void:
	print("Extraction: back, MIA, killed")
	BaseHub.new_campaign(SEED)
	for i in 3:
		BaseHub.server_hire(String(_cheapest(Hiring.pool(BaseHub.hiring(), 1)).cid))
	var ids := Roster.ids(BaseHub.roster())
	var roster := BaseHub.roster()
	RosterDeployment.begin(roster, ids, RosterDeployment.CONTRACT, "zone_x", "", 1)
	for mid in ids:
		RosterDeployment.mark_spawned(roster, mid)
	var gear := {"slots": {"primary": "m4a1"}, "containers": {"vest": [], "pockets": [{"id": "frag_grenade", "count": 1}], "backpack": []}, "hands": ""}
	var rng := RandomNumberGenerator.new()
	var report := RosterDeployment.resolve(roster, {"members": {
		ids[0]: {"state": RosterDeployment.EXTRACTED, "gear": gear, "wounds": [], "blood": 1.0},
		ids[1]: {"state": RosterDeployment.LEFT_BEHIND, "gear": gear, "pos": [1.0, 0.0, 2.0]},
		ids[2]: {"state": RosterDeployment.KILLED}}}, rng, 2)
	var back := BaseHub.member(ids[0])
	var mia := BaseHub.member(ids[1])
	var dead := BaseHub.member(ids[2])
	check(Roster.is_available(back) and Roster.gear_counts(back.gear) == {"m4a1": 1, "frag_grenade": 1} and int(back.missions) >= 1,
		"who extracts comes back with what they carry")
	check(String(mia.status) == Roster.MIA and mia.mia_zone == "zone_x" and report.mia == [ids[1]], "who's left behind alive is MIA")
	check(String(dead.status) == Roster.DEAD and (dead.gear as Dictionary).is_empty() and report.dead == [ids[2]], "the dead are lost with their gear")
	check(not RosterDeployment.is_running(roster), "the deployment is over")
	check(RosterDeployment.recovered(roster, ids[1], 3, 4) and Roster.status_text(mia) == "Recovering (4 d)", "a recovery brings the MIA one home, to recover")
	check(not Roster.is_available(dead) and not RosterDeployment.recovered(roster, ids[2], 3), "the dead stay dead")
	# Players: their outcome lands on their main character, or on the squadmate standing in.
	RosterDeployment.begin(roster, [], RosterDeployment.CONTRACT, "zone_x", "", 3, {}, {"p2": ids[0]})
	var broken := [{"part": &"thigh_l", "kind": "fracture", "name": "femur"}]
	RosterDeployment.resolve(roster, {"players": {"p1": {"gear": gear, "wounds": broken, "blood": 0.9},
		"p2": {"gear": gear, "wounds": broken, "blood": 0.9}}}, rng, 3)
	var p1 := Roster.main_character(roster, "p1")
	check(int(p1.sit_out_days) == Roster.FRACTURE_DAYS and Roster.main_recovering(roster, "p1") and Roster.gear_counts(p1.gear).has("m4a1"),
		"a badly hurt player's main character sits out %d days, keeping what they carried" % int(p1.sit_out_days))
	check(not Roster.main_recovering(roster, "p2") and int(back.sit_out_days) == Roster.FRACTURE_DAYS, "a stand-in's wounds are the stand-in's")


func _test_stand_ins() -> void:
	print("A recovering player plays a squadmate")
	BaseHub.new_campaign(SEED)
	BaseHub.server_hire(String(_cheapest(Hiring.pool(BaseHub.hiring(), 1)).cid))
	var mid := Roster.ids(BaseHub.roster())[0]
	var main := Roster.main_character(BaseHub.roster(), BaseHub.profile())
	main["sit_out_days"] = 5
	var picks := BaseHub._pick_stand_ins([])
	check(picks.get(BaseHub.profile(), "") == mid, "an available squadmate stands in")
	var funds := BaseEconomy.funds()
	picks = BaseHub._pick_stand_ins([mid])
	var free := BaseHub.member(String(picks.get(BaseHub.profile(), "")))
	check(not free.is_empty() and free.mid != mid and BaseEconomy.funds() == funds and int(free.missions) <= 2,
		"with nobody free, a rookie is provided free (%s)" % free.get("callsign", "none"))
	if not free.is_empty():
		_check_kit_pouches(free)


# --- A real session -----------------------------------------------------------------------------

func _test_session() -> void:
	print("The hub")
	CompoundLevel.spawn_ai = true
	Roles.local_choice = Roles.TEAM_LEADER
	BaseHub.local_profile = "host_profile"
	BaseHub.new_campaign(SEED)
	for i in 3:
		BaseHub.server_hire(String(_cheapest(Hiring.pool(BaseHub.hiring(), 1)).cid))
	for pair: Array in EXTRA_STASH:
		BaseArmory.add(BaseHub.stash(), StringName(pair[0]), int(pair[1]))
	Campaign.save_campaign()
	var ids := Roster.ids(BaseHub.roster())
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	BaseHub.prepare_session()
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	check(level is BaseLevel, "the campaign starts at the base hub")
	var base := level as BaseLevel
	check(base.map_area().size.x == BaseLevel.PERIMETER_HALF * 2.0 and base.map_area().has_point(Vector2(BaseLevel.DELIVERY.x, BaseLevel.DELIVERY.z)),
		"the hub's map covers the FOB (%.0f m across)" % base.map_area().size.x)
	var up := await _wait_until(func() -> bool: return ids.all(func(mid: String) -> bool: return base.muster_soldier(mid) != null), 30.0)
	check(up, "the company's people stand at the muster line")
	var stash_counts := BaseArmory.counts(BaseHub.stash())
	check(BaseArmory.counts(base.server_collect_stash()) == stash_counts, "the stash lies in the armory as world items (%d kinds)" % stash_counts.size())
	var member0 := BaseHub.member(ids[0])
	var s0 := base.muster_soldier(ids[0])
	check(s0 != null and String(s0.name) == String(member0.callsign) and Roster.gear_counts(Roster.json_safe(s0.inventory.net_state)) == Roster.gear_counts(member0.gear),
		"each in their own gear, by callsign (%s)" % member0.callsign)
	await _test_terminals(base)
	var client := await _start_client(ids, stash_counts)
	await _test_armory(base)
	await _test_deployment(client)
	await _finish_client(client)
	await _test_restock_session()
	await _test_zone_deployment()
	await _test_revert()
	await _test_contract_loop()


## Starts a second process that joins the hub as a client and checks what it sees; returns
## once it has checked the hub (it then stays to follow the deployment): {"pid", "log"}.
func _start_client(ids: Array, stash_counts: Dictionary) -> Dictionary:
	print("A client in the hub")
	var callsigns: Array = ids.map(func(mid: String) -> String: return String(BaseHub.member(mid).callsign))
	var hire := _cheapest(Hiring.pool(BaseHub.hiring(), BaseHub.day()))
	var expect := {"callsigns": callsigns, "stash": stash_counts, "cid": String(hire.cid), "hire_callsign": String(hire.callsign),
		"back": callsigns[0], "dead": callsigns[2]}
	var log_path := ProjectSettings.globalize_path("user://base_test_client%s.log" % tag)
	if FileAccess.file_exists(log_path):
		DirAccess.remove_absolute(log_path)
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/base_test.tscn", "--", "--join", "127.0.0.1",
		"--expect", Marshalls.utf8_to_base64(JSON.stringify(expect)), "--log", log_path]
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "a client process starts")
	var deadline := Time.get_ticks_msec() + 120000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(log_path) and FileAccess.get_file_as_string(log_path).contains(CLIENT_HUB_DONE):
			break
		await _seconds(0.25)
	check(Roster.ids(BaseHub.roster()).size() == ids.size() + 1, "the host hired who the client asked for (%d on the books)" % Roster.ids(BaseHub.roster()).size())
	return {"pid": pid, "log": log_path}


## Waits for the client to finish following the deployment and prints what it checked.
func _finish_client(client: Dictionary) -> void:
	print("The client, through the deployment")
	var pid: int = client.pid
	var deadline := Time.get_ticks_msec() + 120000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await _seconds(0.25)
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	var code := OS.get_process_exit_code(pid) if pid > 0 else -1
	if FileAccess.file_exists(client.log):
		for line in FileAccess.get_file_as_string(client.log).split("\n"):
			if line.strip_edges() != "" and line.strip_edges() not in [CLIENT_HUB_DONE, CLIENT_ZONE_DONE]:
				print("  (client) " + line.strip_edges())
	check(code == 0, "the client's checks pass (exit %d)" % code)


## Client process: joins the hub and checks the roster, the stash and a request through the
## host, then follows the host into the zone and back.
func _run_client() -> void:
	var args := OS.get_cmdline_user_args()
	var expect: Dictionary = JSON.parse_string(Marshalls.base64_to_utf8(args[args.find("--expect") + 1]))
	_log = FileAccess.open(args[args.find("--log") + 1], FileAccess.WRITE)
	Campaign.campaign_id = "test_base_client" + tag  # a client never saves, but keep apart anyway
	BaseHub.local_profile = "client_profile"
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame  # Main joined (--join on the command line): a plain Join, the host says where it is
	var followed := await _wait_until(func() -> bool: return CompoundLevel.current(self) is BaseLevel and BaseHub.campaign_running, 30.0)
	check(followed, "a plain Join follows the host to the base, in campaign mode")
	level = CompoundLevel.current(self)
	var got := await _wait_until(func() -> bool: return BaseHub.view.get("roster", {}).get("members", {}).size() == expect.callsigns.size(), 30.0)
	var members: Dictionary = BaseHub.view.get("roster", {}).get("members", {})
	var seen: Array = members.values().map(func(m: Dictionary) -> String: return String(m.callsign))
	seen.sort()
	var wanted: Array = expect.callsigns.duplicate()
	wanted.sort()
	check(got and seen == wanted, "the client sees the same roster: %s" % ", ".join(PackedStringArray(seen)))
	var want_stash: Dictionary = {}
	for id: String in expect.stash:
		want_stash[id] = int(expect.stash[id])
	var stash_ok := await _wait_until(func() -> bool: return BaseArmory.counts(BaseHub.view.get("stash", [])) == want_stash, 10.0)
	check(stash_ok, "and the same stash in the base screen's copy")
	var items_ok := await _wait_until(func() -> bool: return BaseArmory.counts(BaseArmory.from_world_items(level.items.get_children())) == want_stash, 20.0)
	check(items_ok, "and lying in the armory (%d items)" % level.items.get_child_count())
	var muster_ok := await _wait_until(func() -> bool:
		return expect.callsigns.all(func(c: String) -> bool: return level.ai.get_node_or_null(NodePath(c)) != null), 20.0)
	check(muster_ok, "the squadmates stand at the muster line on the client too")
	var known := await _wait_until(func() -> bool: return "client_profile" in BaseHub.view.get("players", {}).values(), 10.0)
	check(known, "the host knows the client's profile")
	BaseHub.request("hire", [String(expect.cid)])
	var hired := await _wait_until(func() -> bool:
		return BaseHub.view.get("roster", {}).get("members", {}).values().any(func(m: Dictionary) -> bool: return String(m.callsign).begins_with(String(expect.hire_callsign))), 10.0)
	check(hired, "a hire asked from the client goes through the host and comes back (%s)" % expect.hire_callsign)
	_say(CLIENT_HUB_DONE)
	# The host deploys: the session moves to the zone, then back.
	var deployed := await _wait_until(func() -> bool:
		var l := CompoundLevel.current(self)
		return l != null and not l is BaseLevel, 120.0)
	check(deployed, "the client follows the host into the zone")
	level = CompoundLevel.current(self)
	var squad_ok := await _wait_until(func() -> bool:
		return expect.callsigns.all(func(c: String) -> bool: return level.ai.get_node_or_null(NodePath(c)) != null), 60.0)
	check(squad_ok, "and sees the squad there as the roster's people")
	var mine := await _wait_until(func() -> bool: return level.players.get_node_or_null(str(multiplayer.get_unique_id())) != null, 30.0)
	check(mine, "with its own player in the zone")
	if not squad_ok:
		_say("    zone AI: %s" % ", ".join(PackedStringArray(level.ai.get_children().map(func(n: Node) -> String: return String(n.name)))))
	_say(CLIENT_ZONE_DONE)
	var home := await _wait_until(func() -> bool: return CompoundLevel.current(self) is BaseLevel, 180.0)
	check(home, "and comes back to the base with everyone")
	level = CompoundLevel.current(self)
	var back := await _wait_until(func() -> bool:
		return level.ai.get_node_or_null(NodePath(String(expect.back))) != null and level.ai.get_node_or_null(NodePath(String(expect.dead))) == null, 30.0)
	check(back, "where %s is back at the muster line and %s isn't" % [expect.back, expect.dead])
	_say("CLIENT %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	_log.close()
	Net.leave()
	get_tree().quit(failures)


## The terminals open the base screen through the interaction menu, and every page draws.
func _test_terminals(base: BaseLevel) -> void:
	print("Terminals and the base screen")
	var player: Soldier = level.players.get_node(^"1")
	var board: BaseTerminal = base.get_node_or_null(^"Terminal_hiring")
	var actions := InteractionMenu.actions_for(player, board) if board else []
	check(actions.size() == 1 and String(actions[0].label) == "Use Hiring board" and actions[0].has("call"), "the hiring board offers Use in the interaction menu")
	if actions.is_empty():
		return
	InteractionMenu.perform(player, actions[0])
	var ui: BaseUI = BaseHub._ui
	check(ui != null and ui.is_open() and ui.page == "hiring", "and opens the base screen on the hiring page")
	var drawn := true
	for p in BaseUI.PAGES:
		ui.open(p)
		drawn = drawn and ui._pages[p].get_child_count() > 0
	check(drawn, "every page draws (%s)" % ", ".join(PackedStringArray(BaseUI.PAGES)))
	# No contract in prep (P0331): Deploy waits, and the host's deploy itself refuses (a deploy
	# without one had no briefing, so no extraction and no way home).
	ui.open("squad")
	await get_tree().process_frame  # the page's old rows go
	var deploy := ui._pages["squad"].find_child("Deploy", true, false) as Button
	check(BaseHub.prep_contract().is_empty() and deploy != null and deploy.disabled and deploy.tooltip_text == "Prep a contract first",
		"with no contract in prep, Deploy is off: \"%s\"" % (deploy.tooltip_text if deploy else "no Deploy button"))
	check(BaseHub.server_deploy() == BaseHub.NO_CONTRACT and not RosterDeployment.is_running(BaseHub.roster()),
		"and deploying without a contract is refused")
	# The contract board over it (P0362): this screen steps aside, and the board keeps the mouse
	# until it closes, then this screen is back with it.
	ui.open("squad")
	ui._open_board()
	var boards := get_tree().root.get_children().filter(func(n: Node) -> bool: return n is ContractBoard)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # something under it took the mouse
	await get_tree().process_frame
	var held := Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	var aside := not ui.is_open()
	if not boards.is_empty():
		(boards.back() as ContractBoard).close()
	await get_tree().process_frame
	check(boards.size() == 1 and aside and held and ui.is_open() and ui.page == "squad",
		"the contract board: the base screen steps aside, the board keeps the mouse, and the screen is back when it closes")
	var pool: Dictionary = InteractionMenu.actions_for(player, base.get_node(^"Terminal_motor_pool"))[0]
	check(String(pool.disabled) != "", "the motor pool waits for wave 5's vehicles")
	ui.close()


func _test_armory(base: BaseLevel) -> void:
	print("The armory")
	var player: Soldier = level.players.get_node(^"1")
	var pistol: WorldItem = null
	for n: Node in level.items.get_children():
		if n is WorldItem and (n as WorldItem).item_id == &"m17":
			pistol = n
	check(pistol != null, "the M17 from the stash lies in the armory")
	if pistol == null:
		return
	player.global_position = pistol.global_position + Vector3(0.6, 0, 0)
	player._server_interact.rpc_id(1, pistol.get_path())
	await _frames(3)
	var counts := BaseArmory.counts(base.server_collect_stash())
	check(player.inventory.slots[&"sidearm"] == &"m17" and not counts.has("m17"), "kitting up takes it out of the stash")
	player._server_drop.rpc_id(1, &"sidearm")
	await _frames(3)
	check(BaseArmory.counts(base.server_collect_stash()).get("m17", 0) == 1, "putting it back (dropped in the base) returns it")
	await _seconds(BaseHub.STASH_POLL_S + 0.3)
	check(BaseArmory.count_of(BaseHub.stash(), &"m17") == 1, "the campaign's stash follows")
	var funds := BaseEconomy.funds()
	var why := BaseHub.server_buy(&"pressure_bandage", 4)
	await _frames(3)
	check(why == "" and BaseArmory.counts(base.server_collect_stash()).get("pressure_bandage", 0) >= 4
		and BaseEconomy.funds() == funds - 4 * BaseEconomy.item_price(&"pressure_bandage"), "the shop delivers to the armory for its price")
	check(BaseEconomy.item_price(&"cpr") == 0 and BaseHub.server_buy(&"cpr") != "" and BaseEconomy.item_price(&"surgery_kit_3") > 0,
		"the shop sells surgery kits but not CPR")
	await _test_armory_molle(base, player)
	BaseHub.server_save()
	var saved := BaseArmory.counts(BaseHub.stash())
	var saved_inside := BaseArmory.contents_counts(BaseHub.stash())
	Campaign.load_campaign()
	check(BaseArmory.counts(BaseHub.stash()) == saved and saved.get("m17", 0) == 1, "the stash survives a save and reload")
	check(BaseArmory.contents_counts(BaseHub.stash()) == saved_inside and int(saved_inside.get("mag_556", 0)) >= 2,
		"and so do the carriers' pouches and the magazines in them (%d)" % int(saved_inside.get("mag_556", 0)))


## The stash and dev's MOLLE inventory: a carrier from the stash comes with its pouches,
## magazines picked up go into them, and dropped back in the base the carrier keeps its pouches
## and what's in them (in its state) in the stash.
func _test_armory_molle(base: BaseLevel, player: Soldier) -> void:
	var carrier: WorldItem = null
	var mags: WorldItem = null
	for n: Node in level.items.get_children():
		var item := n as WorldItem
		if item and item.item_id == &"plate_carrier" and not item.state.get("molle", {}).is_empty():
			carrier = item
		elif item and item.item_id == &"mag_556" and item.state.is_empty():
			mags = item
	var base_pouches := 0
	for p: Array in Roles.kit(&""):
		if Inventory.is_attachable(ItemDB.get_item(p[0])):
			base_pouches += int(p[1])
	check(carrier != null and carrier.state.molle.size() == base_pouches, "the stash's carriers come with the base kit's %d pouches" % base_pouches)
	if carrier == null or mags == null:
		return
	player.inventory.strip()
	player.global_position = carrier.global_position + Vector3(0.6, 0, 0)
	player._server_interact.rpc_id(1, carrier.get_path())
	await _frames(3)
	player.global_position = mags.global_position + Vector3(0.6, 0, 0)
	player._server_interact.rpc_id(1, mags.get_path())
	await _frames(3)
	var in_pouches := 0
	for c in player.inventory.pouch_containers():
		for e: Dictionary in player.inventory.containers[c]:
			if e.id == &"mag_556":
				in_pouches += int(e.count)
	check(player.inventory.slots[&"vest"] == &"plate_carrier" and player.inventory.attachment_count() == base_pouches and in_pouches >= 2,
		"kitting up: the carrier's pouches come on with it and take the magazines (%d)" % in_pouches)
	# Back into the stash: what's loose in the vest first, then the carrier with its pouches.
	while not player.inventory.containers[&"vest"].is_empty():
		player._server_inventory_action.rpc_id(1, "drop_entry", &"vest", 0, &"", &"")
		await _frames(1)
	player._server_inventory_action.rpc_id(1, "drop_slot", &"", -1, &"vest", &"")
	await _frames(3)
	var stash := base.server_collect_stash()
	var dropped := stash.filter(func(e: Dictionary) -> bool:
		return String(e.id) == "plate_carrier" and Roster.gear_counts({"containers": {"x": [e]}}).get("mag_556", 0) == in_pouches)
	check(player.inventory.slots[&"vest"] == &"" and dropped.size() == 1, "dropped in the base, the carrier is stash again with its pouches and magazines")
	await _seconds(BaseHub.STASH_POLL_S + 0.3)
	check(int(BaseArmory.contents_counts(BaseHub.stash()).get("mag_556", 0)) == in_pouches, "the campaign's stash keeps them in the carrier's state")


func _test_deployment(client: Dictionary) -> void:
	print("Deployment")
	var base := level as BaseLevel
	var ids := Roster.ids(BaseHub.roster())
	var squad: Array = ids.slice(0, 3)
	var a: String = squad[0]
	var b: String = squad[1]
	var c: String = squad[2]
	var callsign_a := String(BaseHub.member(a).callsign)
	var callsign_b := String(BaseHub.member(b).callsign)
	var callsign_c := String(BaseHub.member(c).callsign)
	base.muster_soldier(a).inventory.take(&"smoke_purple", 1)  # what Give item would do
	var player: Soldier = level.players.get_node(^"1")
	player.inventory.strip()
	player.inventory.take(&"plate_carrier")
	player.inventory.take(&"helmet")
	for mid: String in squad:
		BaseHub.server_pick(mid, true)
	var wage_a := int(BaseHub.member(a).wage)
	var day := BaseHub.day()
	var why := BaseHub.server_deploy({"zone_id": ZONE + tag, "no_contract": true})
	check(why == "" and RosterDeployment.is_running(BaseHub.roster()), "deploy starts the deployment")
	await _wait_until(func() -> bool: return not CompoundLevel.current(self) is BaseLevel, 10.0)
	level = CompoundLevel.current(self)
	check(level != null and not level is BaseLevel, "and the session moves to the zone")
	var up := await _wait_until(func() -> bool: return squad.all(func(mid: String) -> bool: return _roster_soldier(mid) != null), 40.0)
	check(up, "the squad spawns as the roster's people (%s, %s, %s)" % [callsign_a, callsign_b, callsign_c])
	for s: Node in level.ai.get_children():
		if (s as Soldier).faction == &"hostile":
			s.queue_free()
	if up:
		await _late_joiner(squad.map(func(mid: String) -> String: return String(BaseHub.member(mid).callsign)))
		up = await _wait_until(func() -> bool: return squad.all(func(mid: String) -> bool: return _roster_soldier(mid) != null) and _friendly_ai() == 3, 20.0)
		check(up, "after the late joiner leaves, the squad is the three picked again (%d)" % _friendly_ai())
	var sa := _roster_soldier(a)
	if not up or sa == null:
		return
	check(String(sa.name) == callsign_a and sa.inventory.count_of(&"smoke_purple") == 1, "%s carries the smoke handed over at the base" % callsign_a)
	check(_friendly_ai() == 3, "only the three picked deploy: nobody else fills the other slots")
	var as_people := true
	var tapes: PackedStringArray = []
	for mid: String in squad:
		var s := _roster_soldier(mid)
		var m := BaseHub.member(mid)
		as_people = as_people and s != null and s.person_name == String(m.surname) and s.nation == String(m.nation) and s.left_handed == bool(m.left)
		tapes.append(String(m.surname))
	check(as_people, "each squadmate deploys as their roster person: the name tape, nationality and hand (%s)" % ", ".join(tapes))
	check(is_equal_approx(SquadAI.of(sa).combat, Roster.ai_stats(BaseHub.member(a)).combat), "their aim skill drives the AI (combat %.2f)" % SquadAI.of(sa).combat)
	player = level.players.get_node(^"1")
	check(player.inventory.slots[&"vest"] == &"plate_carrier" and player.inventory.slots[&"helmet"] == &"helmet", "the player deploys in the kit from the armory")
	# A player death counts against the pool.
	player.vitals.server_kill()
	await _frames(2)
	check(int(RosterDeployment.active(BaseHub.roster()).get("respawns_used", 0)) == 1, "a player respawn counts (%d free left)" % RosterDeployment.free_respawns_left(BaseHub.roster()))
	# A picks up a frag; C is killed; B wanders off; the rest extract by the player.
	var frags := sa.inventory.count_of(&"frag_grenade") + sa.inventory.take(&"frag_grenade", 1)
	var sc := _roster_soldier(c)
	var label_c := sc.display_name()  # the body is labelled with the name on the tape
	var surname_c := String(BaseHub.member(c).surname)
	sc.vitals.server_kill()
	await _frames(2)
	var sb := _roster_soldier(b)
	SquadAI.of(sb).process_mode = Node.PROCESS_MODE_DISABLED
	sb.global_position = player.global_position + Vector3(0, 0, -45)
	SquadAI.of(sa).process_mode = Node.PROCESS_MODE_DISABLED
	sa.global_position = player.global_position + Vector3(1, 0, 1)
	var zone_seen := await _wait_client_line(client, CLIENT_ZONE_DONE, 60.0)
	check(zone_seen, "the client has seen the zone")
	var report := BaseHub.server_extract_near(player.global_position, 20.0)
	check(report.get("extracted", []) == [a] and report.get("mia", []) == [b] and report.get("dead", []) == [c],
		"extraction: %s back, %s MIA, %s killed" % [callsign_a, callsign_b, callsign_c])
	check(String(BaseHub.member(b).status) == Roster.MIA and _recovery_requested(b), "the one left behind is MIA and a recovery contract is requested")
	var zone_save: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s.json" % [GameState.SAVE_DIR, BaseHub.zone_save_id(ZONE + tag)]))
	var zone_bodies: Array = zone_save.get("bodies", []) if zone_save is Dictionary else []
	check(String(BaseHub.member(c).status) == Roster.DEAD and (BaseHub.member(c).gear as Dictionary).is_empty()
		and zone_bodies.any(func(r: Dictionary) -> bool: return String(r.get("label", "")) == label_c and not (r.get("gear", {}) as Dictionary).is_empty()),
		"the dead one is lost, gear and all on the body saved in the zone")
	check(zone_bodies.any(func(r: Dictionary) -> bool: return String(r.get("person_name", "")) == surname_c and r.get("nation", "") == BaseHub.member(c).nation),
		"their body keeps their name tape and nationality (%s)" % surname_c)
	check(int(BaseHub.member(a).wage) > wage_a and int(BaseHub.member(a).missions) >= 1, "the one who came back earns more ($%d -> $%d)" % [wage_a, int(BaseHub.member(a).wage)])
	check(BaseHub.day() == day + 1, "a day passed")
	await _wait_until(func() -> bool: return CompoundLevel.current(self) is BaseLevel, 10.0)
	level = CompoundLevel.current(self)
	check(level is BaseLevel, "everyone is back at the base")
	base = level as BaseLevel
	var back := await _wait_until(func() -> bool: return base.muster_soldier(a) != null, 30.0)
	var sa_home := base.muster_soldier(a)
	check(back and sa_home.inventory.count_of(&"smoke_purple") == 1 and sa_home.inventory.count_of(&"frag_grenade") == frags,
		"%s's gear came home with them (the smoke, and the frag picked up in the zone)" % callsign_a)
	check(base.muster_soldier(b) == null and base.muster_soldier(c) == null, "the MIA and the dead aren't at the muster line")
	var pouched := 0
	if sa_home:
		for pc in sa_home.inventory.pouch_containers():
			pouched += sa_home.inventory.containers[pc].size()
	check(sa_home != null and sa_home.inventory.attachment_count() > 0 and pouched > 0,
		"%s's carrier came home with its pouches and what's in them (%d entries)" % [callsign_a, pouched])
	var home_inside := BaseArmory.contents_counts(base.server_collect_stash())
	check(int(home_inside.get("mag_556", 0)) >= 2, "the stash's carriers lie in the armory again with their pouches and magazines (%d)" % int(home_inside.get("mag_556", 0)))
	var gear_a := Roster.gear_counts(BaseHub.member(a).gear)
	BaseHub.server_save()
	Campaign.load_campaign()
	check(Roster.gear_counts(BaseHub.member(a).gear) == Roster.gear_counts(Roster.json_safe(sa_home.inventory.net_state)) and gear_a.get("smoke_purple", 0) == 1,
		"their gear survives a save and reload")
	check(String(BaseHub.member(b).status) == Roster.MIA and String(BaseHub.member(c).status) == Roster.DEAD, "and so do MIA and KIA")


## A deployment into a zone (a ZoneLevel generated from the definition the deployment names)
## and back: the same switch as into the compound.
func _test_zone_deployment() -> void:
	print("Deployment into a zone")
	level = CompoundLevel.current(self)
	if not level is BaseLevel:
		check(false, "back at the base before deploying into a zone")
		return
	var squad: Array = Roster.available_ids(BaseHub.roster()).slice(0, 1)
	var def := ZoneDef.get_def("test")
	var why := BaseHub.server_deploy({"level": {"level": "zone", "def": def}, "zone_id": ZONE + "_wide" + tag, "squad": squad, "no_contract": true})
	var moved := await _wait_until(func() -> bool: return CompoundLevel.current(self) is ZoneLevel, 20.0)
	var zone := CompoundLevel.current(self) as ZoneLevel
	check(why == "" and moved and zone != null and int(zone.def.get("seed", -1)) == int(def.seed) and zone.modules().size() == (def.modules as Array).size(),
		"deploying into a zone generates it from its definition (%s, %d modules)" % [String(def.get("name", "?")), zone.modules().size() if zone else 0])
	if zone == null:
		return
	level = zone
	check(get_tree().get_nodes_in_group(&"level").size() == 1, "and it is the session's one level")
	var player := zone.players.get_node_or_null(^"1") as Soldier
	var start := zone.insertion_points()[0]
	check(player != null and Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length() < 10.0,
		"the host's player starts at the zone's insertion point")
	var up := squad.is_empty() or await _wait_until(func() -> bool: return _roster_soldier(String(squad[0])) != null, 30.0)
	check(up, "the picked squadmate deploys into the zone with them")
	var out: Array = [player]
	if not squad.is_empty() and _roster_soldier(String(squad[0])):
		out.append(_roster_soldier(String(squad[0])))
		check(_roster_soldier(String(squad[0])).person_name == String(BaseHub.member(String(squad[0])).surname),
			"another deployment, the same person (%s)" % BaseHub.member(String(squad[0])).surname)
	var report := BaseHub.server_end_deployment(out)
	check(report.get("zone_id", "") == ZONE + "_wide" + tag and (report.get("mia", []) as Array).is_empty(),
		"extracting ends it with nobody left behind (%s back, %s MIA)" % [report.get("extracted", []), report.get("mia", [])])
	var home := await _wait_until(func() -> bool: return CompoundLevel.current(self) is BaseLevel, 20.0)
	check(home, "and everyone is back at the base")
	level = CompoundLevel.current(self)


## Wave 4B part 1, the loop: accept on the board -> prep -> deploy -> the briefing in the zone
## -> objectives live at its start -> extraction -> the debrief and the roster settled once
## -> back at the base, on one bank and one clock. One squadmate left behind is MIA with a
## recovery contract on the board; deploying on it, they wait where they were left, join the
## player who finds them and come home recovered.
func _test_contract_loop() -> void:
	print("The loop: board, prep, briefing, extraction, debrief")
	level = CompoundLevel.current(self)
	if not level is BaseLevel:
		check(false, "back at the base before the loop")
		return
	Contracts.auto_show_debrief = false
	var offer := {}
	for c: Dictionary in Contracts.board():
		if c.source == "board" and c.zone_kind == "contract" and c.type == "clear_compound":
			offer = c
	if offer.is_empty():
		offer = Contracts.board().filter(func(c: Dictionary) -> bool: return c.zone_kind == "contract")[0]
	var cid := String(offer.cid)
	var cash := Economy.cash()
	check(Contracts.server_accept(cid, ContractGen.default_terms()) == "", "a contract is accepted on the board (%s, %s)" % [offer.title, ContractGen.clawback_text(offer)])
	var advance := int(Contracts.contract(cid).deal.advance)
	check(BaseEconomy.funds() == cash + advance,
		"one bank: the advance is in the base's funds ($%s)" % DebriefCalc.money(advance))
	check(String(BaseHub.prep_contract().get("cid", "")) == cid and not BaseHub.prep_contract().has("true_rating"),
		"accepting it starts the prep at the base (the threat it hides stays hidden)")
	var squad: Array = Roster.available_ids(BaseHub.roster()).slice(0, 2)
	BaseHub._prep().squad = squad.duplicate()
	var stay: String = squad[0]
	var lost: String = squad[1]
	var day0 := Economy.day()
	# The session log tells the night's story (S3, P0331 triage): a session of its own, in a
	# scratch folder of this test's.
	SessionLog.start(OS.get_user_data_dir().path_join("base_test_session_log" + tag))
	var why := BaseHub.server_deploy()
	var moved := await _wait_until(func() -> bool: return not CompoundLevel.current(self) is BaseLevel, 20.0)
	level = CompoundLevel.current(self)
	check(why == "" and moved and not Contracts.is_deployed(), "deploying takes the squad into the zone; the contract isn't live yet")
	var briefing := MapNodes.briefing(level)
	check(briefing != null and briefing.is_open() and String(briefing.contract.get("id", "")) == cid and not briefing.insertion_points().is_empty()
		and not (briefing.contract.get("objectives", []) as Array).is_empty(),
		"the briefing opens in the zone: the contract's objectives and insertion points (%d)" % (briefing.insertion_points().size() if briefing else 0))
	var up := await _wait_until(func() -> bool: return squad.all(func(mid: String) -> bool: return _roster_soldier(mid) != null), 40.0)
	check(up, "the picked squad is there")
	if briefing == null or not up:
		return
	briefing.server_start(true)
	await _frames(2)
	var extraction := MapNodes.extraction(level)
	check(Contracts.is_deployed() and not Contracts.objectives.for_contract(cid).is_empty() and extraction.is_active(),
		"its start makes the contract live (objectives) and opens extraction")
	for s: Node in level.ai.get_children():
		if (s as Soldier).faction == &"hostile":
			s.queue_free()
	for o: Dictionary in Contracts.objectives.for_contract(cid):
		if not o.optional:
			Contracts.objectives.server_set_state(o.oid, Objectives.DONE)
	var player: Soldier = level.players.get_node(^"1")
	var s_stay := _roster_soldier(stay)
	var s_lost := _roster_soldier(lost)
	for s: Soldier in [s_stay, s_lost]:
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
	s_stay.global_position = player.global_position + Vector3(1, 0, 1)
	s_lost.global_position = player.global_position + Vector3(0, 0, -45)
	var lost_at := s_lost.global_position
	extraction.server_set_bring(String(s_lost.name), false)
	extraction.countdown_s = 0.2
	extraction.server_add_point(Vector2(player.global_position.x, player.global_position.z))
	var cash_before := Economy.cash()
	var bills := [0]  # weekly bills that fall due in the deployment's days
	var on_week := func(_week: int, bill: Dictionary) -> void: bills[0] += int(bill.total) - int(bill.get("loan_taken", 0))
	Economy.week_paid.connect(on_week)
	check(extraction.server_confirm() == "", "the squad (one left behind by choice) confirms at the extraction point")
	var home := await _wait_until(func() -> bool: return CompoundLevel.current(self) is BaseLevel, 20.0)
	level = CompoundLevel.current(self)
	var debrief := Contracts.last_debrief()
	var line: Dictionary = (debrief.get("contracts", [{}]) as Array)[0] if not (debrief.get("contracts", []) as Array).is_empty() else {}
	check(home and String(line.get("cid", "")) == cid and line.get("outcome") == "completed", "extraction ends it once: the debrief (%s) and back at the base" % line.get("outcome", "none"))
	Economy.week_paid.disconnect(on_week)
	_check_story(cid, String(BaseHub.member(lost).callsign))
	check(Economy.cash() == cash_before + int(debrief.totals.paid_now) - bills[0] and int(line.get("pay", 0)) > 0,
		"the pay lands in the one bank (+$%s)" % DebriefCalc.money(debrief.totals.paid_now))
	check(Economy.day() == day0 + int(debrief.days) and BaseHub.day() == Economy.day(), "the days pass once, on one clock (%d -> %d)" % [day0, Economy.day()])
	check(String(BaseHub.member(stay).status) != Roster.MIA and String(BaseHub.member(lost).status) == Roster.MIA,
		"the roster is settled: one back, one MIA")
	var recovery := {}
	for c: Dictionary in Contracts.board():
		if String(c.get("recover_mid", "")) == lost:
			recovery = c
	check(not recovery.is_empty() and int(recovery.base_pay) == 0, "a recovery contract for them is on the board (%s)" % recovery.get("title", "none"))
	if recovery.is_empty() or not level is BaseLevel:
		return
	# The recovery: they wait where they were left and come home with whoever finds them.
	print("A recovery contract")
	var rid := String(recovery.cid)
	check(Contracts.server_accept(rid, ContractGen.default_terms()) == "" and String(BaseHub.prep_contract().get("cid", "")) == rid,
		"accepting it preps it")
	BaseHub._prep().squad = [stay]
	why = BaseHub.server_deploy()
	moved = await _wait_until(func() -> bool: return not CompoundLevel.current(self) is BaseLevel, 20.0)
	level = CompoundLevel.current(self)
	briefing = MapNodes.briefing(level)
	if why != "" or not moved or briefing == null or not briefing.is_open():
		check(false, "deploying on the recovery contract opens its briefing (%s)" % why)
		return
	briefing.server_start(true)
	var waiting := await _wait_until(func() -> bool: return _recovery_target(lost) != null, 10.0)
	var target := _recovery_target(lost)
	check(waiting and target.global_position.distance_to(lost_at) < 3.0 and target.person_name == String(BaseHub.member(lost).surname),
		"%s waits where they were left, the same person" % BaseHub.member(lost).callsign)
	if target == null:
		return
	for s: Node in level.ai.get_children():
		if (s as Soldier).faction == &"hostile":
			s.queue_free()
	player = level.players.get_node(^"1")
	player.global_position = target.global_position + Vector3(1.5, 0, 0)
	var found := await _wait_until(func() -> bool: return target.has_meta(&"found"), 5.0)
	check(found, "a player reaching them finds them: they join")
	var mate := _roster_soldier(stay)
	if mate:
		SquadAI.of(mate).process_mode = Node.PROCESS_MODE_DISABLED
		mate.global_position = player.global_position + Vector3(-1, 0, 1)
	SquadAI.of(target).process_mode = Node.PROCESS_MODE_DISABLED
	extraction = MapNodes.extraction(level)
	extraction.countdown_s = 0.2
	extraction.server_add_point(Vector2(player.global_position.x, player.global_position.z))
	check(extraction.server_confirm() == "", "and extract with the squad")
	home = await _wait_until(func() -> bool: return CompoundLevel.current(self) is BaseLevel, 20.0)
	level = CompoundLevel.current(self)
	check(home and String(BaseHub.member(lost).status) == Roster.READY and Contracts.history().any(func(h: Dictionary) -> bool: return h.cid == rid and h.outcome == "completed"),
		"the recovery completes: %s is back on the roster" % BaseHub.member(lost).callsign)
	Contracts.auto_show_debrief = true


func _recovery_target(mid: String) -> Soldier:
	for n: Node in level.ai.get_children():
		var s := n as Soldier
		if s and s.has_meta(&"recovery") and String(s.get_meta(&"roster_id")) == mid and not s.vitals.is_dead():
			return s
	return null


## The late joiner (another process): joins the deployed host with a plain Join and checks it
## is in the zone with everyone, then leaves.
func _run_late_client() -> void:
	var args := OS.get_cmdline_user_args()
	var expect: Dictionary = JSON.parse_string(Marshalls.base64_to_utf8(args[args.find("--expect") + 1]))
	_log = FileAccess.open(args[args.find("--log") + 1], FileAccess.WRITE)
	Campaign.campaign_id = "test_base_late" + tag
	BaseHub.local_profile = "late_profile"
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.join("127.0.0.1")
	var in_zone := await _wait_until(func() -> bool: return BaseHub.campaign_running and CompoundLevel.current(self) != null 		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, 30.0)
	level = CompoundLevel.current(self)
	check(in_zone and level != null and not level is BaseLevel, "the late joiner is in the zone, in campaign mode")
	var mine := await _wait_until(func() -> bool: return level.players.get_node_or_null(str(multiplayer.get_unique_id())) != null, 30.0)
	check(mine, "with its own player")
	var squad_ok := await _wait_until(func() -> bool:
		return expect.callsigns.all(func(c: String) -> bool: return level.ai.get_node_or_null(NodePath(c)) != null), 30.0)
	check(squad_ok, "and the roster's people: %s" % ", ".join(PackedStringArray(expect.callsigns)))
	var host_seen := await _wait_until(func() -> bool: return level.players.get_node_or_null(^"1") != null, 10.0)
	check(host_seen, "and the host's player")
	var view_ok := await _wait_until(func() -> bool: return not BaseHub.view.is_empty() and not bool(BaseHub.view.get("in_base", true)), 10.0)
	check(view_ok, "the base screen's copy says the session is deployed")
	_say("CLIENT %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	_log.close()
	Net.leave()
	get_tree().quit(failures)


## Waits until the client's log has `line` (or it has exited, or `timeout` passes).
func _wait_client_line(client: Dictionary, line: String, timeout: float) -> bool:
	var pid: int = client.get("pid", -1)
	return await _wait_until(func() -> bool:
		if pid <= 0 or not OS.is_process_running(pid):
			return false
		return FileAccess.file_exists(client.log) and FileAccess.get_file_as_string(client.log).contains(line), timeout)


## Living friendly AI in the zone.
func _friendly_ai() -> int:
	return level.ai.get_children().filter(func(n: Node) -> bool:
		return (n as Soldier).faction == &"friendly" and not n.is_queued_for_deletion() and not (n as Soldier).vitals.is_dead()).size()


## A second client joins mid-deployment with a plain Join (it never saw the base): it must
## land in the zone, in campaign mode, with its own player and the roster's people, then it
## leaves. A squadmate whose slot it took steps out and comes back when it's gone.
func _late_joiner(callsigns: Array) -> void:
	print("A late joiner, mid-deployment")
	var log_path := ProjectSettings.globalize_path("user://base_test_late%s.log" % tag)
	if FileAccess.file_exists(log_path):
		DirAccess.remove_absolute(log_path)
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/base_test.tscn", "--", "--late",
		"--expect", Marshalls.utf8_to_base64(JSON.stringify({"callsigns": callsigns})), "--log", log_path]
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "a late client process starts")
	var added: Array[String] = []
	var on_added := func(n: Node) -> void: added.append(String(n.name))
	level.players.child_entered_tree.connect(on_added)
	await _finish_client({"pid": pid, "log": log_path})
	level.players.child_entered_tree.disconnect(on_added)
	check(added.size() == 1 and added[0] != "1", "the host added the late joiner's player in the zone (%s)" % ", ".join(PackedStringArray(added)))


func _roster_soldier(mid: String) -> Soldier:
	for n: Node in level.ai.get_children():
		var s := n as Soldier
		if s and not s.is_queued_for_deletion() and s.has_meta(&"roster_id") and String(s.get_meta(&"roster_id")) == mid and not s.vitals.is_dead():
			return s
	return null


func _recovery_requested(mid: String) -> bool:
	return Contracts.board().any(func(c: Dictionary) -> bool: return String(c.get("recover_mid", "")) == mid)


# --- Helpers --------------------------------------------------------------------------------------

func _cheapest(pool: Array) -> Dictionary:
	var best := {}
	for c: Dictionary in pool:
		if best.is_empty() or int(c.fee) < int(best.fee):
			best = c
	return best


func _mean(values: Array) -> float:
	var total := 0.0
	for v: Variant in values:
		total += float(v)
	return total / maxf(values.size(), 1.0)


## Waits until `cond` holds or `timeout` seconds pass; returns whether it held.
func _wait_until(cond: Callable, timeout: float) -> bool:
	var left := timeout
	while left > 0.0:
		if cond.call():
			return true
		await _seconds(0.25)
		left -= 0.25
	return cond.call()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


## The Escape menu's "Return to Base (revert)" (Captain, 2026-10-12): back to just before the
## deployment, as if it never happened.
## The session log's lines for the contract loop (S3): deployment start and end, the contract
## going live, extraction open, called and complete, and the debrief's pay and losses.
func _check_story(cid: String, lost_callsign: String) -> void:
	var story := Array(FileAccess.get_file_as_string(SessionLog.folder.path_join("session.log")).split("
")).filter(
		func(l: String) -> bool: return not "  [ok] " in l and not "  [FAIL] " in l)
	var has := func(parts: Array) -> bool: return story.any(func(l: String) -> bool: return parts.all(func(p: String) -> bool: return p in l))
	check(has.call(["deployment started: zone ", "[%s]" % cid, "squad "]), "the session log has the deployment's start: zone, contract and squad")
	check(has.call(["deployment: briefing done, contract ", "[%s] is live" % cid]) and has.call(["extraction open: contract %s" % cid]),
		"the contract going live and extraction opening")
	check(has.call(["extraction called at "]) and has.call(["extraction complete at ", "Extracted: "]), "extraction called and complete")
	check(has.call(["debrief: ", "paid $", "casualties: "]), "the debrief: pay and losses")
	check(has.call(["deployment ended: zone ", "MIA %s" % lost_callsign]), "and the deployment's end: who's back, MIA and KIA")
	SessionLog.finish()


func _test_revert() -> void:
	print("Return to Base (revert)")
	level = CompoundLevel.current(self)
	if not level is BaseLevel:
		check(false, "at the base before reverting a deployment")
		return
	var cash_before := Economy.cash()
	var day_before := BaseHub.day()
	var squad: Array = Roster.available_ids(BaseHub.roster()).slice(0, 1)
	var why := BaseHub.server_deploy({"level": {"level": "zone", "def": ZoneDef.get_def("test")}, "zone_id": ZONE + "_revert" + tag, "squad": squad, "no_contract": true})
	var moved := await _wait_until(func() -> bool: return CompoundLevel.current(self) is ZoneLevel, 20.0)
	check(why == "" and moved and RosterDeployment.is_running(BaseHub.roster()), "deployed into a zone")
	Economy.spend(1234, "test: money spent out there")
	var undo := BaseHub.server_revert_deployment()
	var home := await _wait_until(func() -> bool: return CompoundLevel.current(self) is BaseLevel, 20.0)
	check(undo == "" and home and not RosterDeployment.is_running(BaseHub.roster()), "reverting brings everyone back to the base, no deployment running")
	check(Economy.cash() == cash_before and BaseHub.day() == day_before,
		"and the campaign is as it was before deploying (cash %d, day %d)" % [Economy.cash(), BaseHub.day()])
	check(BaseHub.server_revert_deployment() != "", "with nothing to revert at the base, it says why")
	level = CompoundLevel.current(self)


# --- Restock last loadout (playtest S2) -----------------------------------------------------------

## Restock's rules on a stash list: a stocked stash rebuilds the loadout exactly (pouches on the
## same points, mags in the same pouches, the optic it had), the best of each first, and nothing
## is made or lost; a short stash builds what it can and lists the rest; a loadout survives a
## JSON round trip, and a person from an older save has none.
func _test_restock() -> void:
	print("Restock last loadout (S2)")
	var m4 := ItemDB.get_item(&"m4a1")
	# A rifleman as deployed: his kit, a holo on the M4 (it comes with a red dot), and the GP
	# pouch moved to the back.
	var inv := Inventory.new()
	inv.net_state = GameState.from_json(Roster.gear_for_kit(Roles.kit(Roles.RIFLEMAN)))
	var stock: Dictionary = Roster.json_safe(inv.net_state.duplicate(true))  # before the player's touches
	inv.set_slot_state(&"primary", Optics.with_optic(m4, inv.state_of(&"primary"), &"optic_holo"))
	var gp := ""
	for p: Variant in inv.state_of(&"vest").get("molle", {}):
		if String(inv.attachment(StringName(p)).get("id", "")) == "pouch_utility":
			gp = String(p)
	var moved := gp != "" and inv.move_attachment(StringName(gp), &"utility_2")
	var gear: Dictionary = Roster.json_safe(inv.net_state.duplicate(true))
	inv.free()
	var loadout := Restock.template_of(gear)
	check(moved and String(loadout.molle.get("utility_2", {}).get("id", "")) == "pouch_utility" and String(loadout.optics.get("primary", "")) == "optic_holo",
		"a loadout keeps which pouch is on which point and the optic on the gun (%d points, %s)" % [loadout.molle.size(), loadout.optics])
	check(int(loadout.molle.get("mag_1", {}).get("held", [{}])[0].get("count", 0)) == 2 and String(loadout.molle.mag_1.held[0].id) == "mag_556",
		"and which magazines are in which pouch (mag_1: %s)" % [loadout.molle.get("mag_1", {}).get("held", [])])
	# The stash: the same kit in pieces (the M4 with its red dot, the holo loose), plus a damaged
	# plate and a part-used magazine that mustn't be picked over good ones.
	var stash := _scatter(stock)
	BaseArmory.add(stash, &"optic_holo", 1)
	BaseArmory.add(stash, &"plate_ceramic_l4", 1, {"chips": [[1, 2, 3], [4, 5, 6]], "integrity": 0.4})
	BaseArmory.add(stash, &"mag_556", 1, {"rounds": 9})
	BaseArmory.add(stash, &"m17", 1)
	var before := _units(stash, {})
	var res := Restock.build(loadout, stash)
	var rebuilt := Restock.template_of(res.gear)
	check(rebuilt == loadout, "a stocked stash rebuilds it exactly: same worn kit, same points, same contents, same optic")
	if rebuilt != loadout:
		print("    wanted %s\n    got    %s" % [JSON.stringify(loadout, "", true), JSON.stringify(rebuilt, "", true)])
	check((res.missing as Dictionary).is_empty() and (res.no_room as Dictionary).is_empty() and int(res.placed) == int(res.wanted),
		"nothing missing, nothing without room (%d of %d)" % [int(res.placed), int(res.wanted)])
	var plates_ok := true
	for slot: StringName in [&"plate_front", &"plate_back"]:
		plates_ok = plates_ok and not (res.gear.slot_state.get(String(slot), {}) as Dictionary).has("integrity")
	var full_mags := true
	for point: String in res.gear.slot_state.vest.molle:
		for e: Dictionary in res.gear.slot_state.vest.molle[point].get("held", []):
			full_mags = full_mags and int(e.get("state", {}).get("rounds", 30)) == 30
	check(plates_ok and full_mags and BaseArmory.count_of(stash, &"plate_ceramic_l4") == 1 and BaseArmory.count_of(stash, &"mag_556") == 1,
		"the best of each first: undamaged plates and full magazines; the damaged plate and the 9-round mag stay in the stash")
	check(BaseArmory.count_of(stash, &"optic_red_dot") == 1 and BaseArmory.count_of(stash, &"optic_holo") == 0 and BaseArmory.count_of(stash, &"m17") == 1,
		"the holo goes on the M4 and its red dot into the stash; what the loadout doesn't name stays")
	var after := _units(stash, res.gear)
	check(after == before, "nothing is made or lost (stash + kit, item by item)")
	if after != before:
		print("    before %s\n    after  %s" % [before, after])
	# A short stash: four magazines, the holo and the helmet aren't there.
	var short := _scatter(stock)
	BaseArmory.remove(short, &"helmet", 1)
	var mags_short := 0
	for e: Dictionary in short:
		if String(e.id) == "mag_556":
			mags_short = int(e.count)
	BaseArmory.remove(short, &"mag_556", 4)
	var part := Restock.build(loadout, short)
	check(part.missing == {"mag_556": 4, "optic_holo": 1, "helmet": 1} and int(part.placed) == int(part.wanted) - 6,
		"a short stash builds the rest and lists what's missing (%s; %d of %d)" % [part.missing, int(part.placed), int(part.wanted)])
	var text := Restock.report_text("Hawk", part)
	check(text.contains("Missing from the stash") and text.contains("Helmet") and text.contains("x4") and text.contains("Holographic"),
		"and says so: %s" % text)
	var part_inv := Inventory.new()
	part_inv.net_state = GameState.from_json(part.gear.duplicate(true))
	check(part_inv.slots[&"helmet"] == &"" and part_inv.slots[&"vest"] == &"plate_carrier" and Optics.on_slot(part_inv, &"primary") != null
		and Optics.on_slot(part_inv, &"primary").id == &"optic_red_dot" and part_inv.count_of(&"mag_556") == mags_short - 4,
		"with no holo the M4 keeps its red dot; the magazines there are go in (%d)" % part_inv.count_of(&"mag_556"))
	part_inv.free()
	# Saved with the roster: a JSON round trip changes nothing; an old save's people have none.
	var round_trip: Dictionary = GameState.from_json(JSON.parse_string(JSON.stringify(loadout)))
	var again := Restock.build(round_trip, _scatter_with_holo(stock))
	check(Restock.template_of(again.gear) == loadout, "a loadout read back from a save rebuilds the same")
	var old_member := {"mid": "m0099", "callsign": "Old", "gear": stock}
	check(Restock.is_blank(Roster.loadout_of(old_member)), "a member from an older save has no loadout (the field is optional)")
	Roster.record_loadout(old_member, {})
	check(not old_member.has("loadout"), "and an empty kit doesn't write one")
	Roster.record_loadout(old_member, gear)
	check(Roster.loadout_of(old_member) == loadout, "deploying writes it down")


## `gear`'s items as a stash: everything taken off, out of and off the carrier, pack and pouches.
func _scatter(gear: Dictionary) -> Array:
	var inv := Inventory.new()
	inv.net_state = GameState.from_json(gear.duplicate(true))
	var stash: Array = []
	for e: Dictionary in inv.strip():
		var state: Dictionary = e.get("state", {}).duplicate(true)
		for loose: Dictionary in Restock.unpack(state):
			BaseArmory.add(stash, StringName(String(loose.id)), int(loose.count), loose.get("state", {}))
		BaseArmory.add(stash, StringName(String(e.id)), int(e.count), state)
	inv.free()
	return stash


func _scatter_with_holo(gear: Dictionary) -> Array:
	var stash := _scatter(gear)
	BaseArmory.add(stash, &"optic_holo", 1)
	return stash


## Every unit in a stash plus a kit, item by item (pouch contents and the optics on guns too).
func _units(stash: Array, gear: Dictionary) -> Dictionary:
	var out := BaseArmory.counts(stash)
	for id: String in BaseArmory.contents_counts(stash):
		out[id] = int(out.get(id, 0)) + int(BaseArmory.contents_counts(stash)[id])
	var worn := Roster.gear_counts(gear)
	for id: String in worn:
		out[id] = int(out.get(id, 0)) + int(worn[id])
	var optics := func(id: StringName, state: Dictionary) -> void:
		var item := ItemDB.get_item(id)
		var o := Optics.mounted_id(item, state) if item else &""
		if o != &"":
			out[String(o)] = int(out.get(String(o), 0)) + 1
	for e: Dictionary in stash:
		for i in int(e.count):
			optics.call(StringName(String(e.id)), e.get("state", {}))
	for slot: Variant in gear.get("slots", {}):
		if String(gear.slots[slot]) != "":
			optics.call(StringName(String(gear.slots[slot])), gear.get("slot_state", {}).get(slot, {}))
	return out


## At the hub: deploying wrote down the squadmate's and the player's loadouts; "Restock squad"
## rebuilds the squadmate's from the armory's world items after his kit went into the stash,
## and the player's own "Restock" builds what the stash has and names what it hasn't. The
## stash on the floor and the kits together hold the same items before and after.
func _test_restock_session() -> void:
	print("Restock last loadout at the hub (S2)")
	var base := level as BaseLevel
	if base == null:
		check(false, "at the base for the restock checks")
		return
	var mid := ""
	for m: String in Roster.available_ids(BaseHub.roster()):
		if base.muster_soldier(m) != null and not Restock.is_blank(Roster.loadout_of(BaseHub.member(m))):
			mid = m
	check(mid != "", "deploying wrote down the squad's loadouts")
	var main := Roster.main_character(BaseHub.roster(), BaseHub.player_key(1))
	check(String(Roster.loadout_of(main).get("slots", {}).get("vest", "")) == "plate_carrier", "and the player's (%s)" % [Roster.loadout_of(main).get("slots", {})])
	if mid == "":
		return
	var s := base.muster_soldier(mid)
	var loadout: Dictionary = Roster.json_safe(Roster.loadout_of(BaseHub.member(mid)))  # read back from the save: ids as StringNames
	var player: Soldier = level.players.get_node(^"1")
	# His kit goes onto the armory floor, as if he'd dropped it all there.
	for e: Dictionary in s.inventory.strip():
		level.server_spawn_dropped(StringName(e.id), int(e.count), BaseLevel.DELIVERY + Vector3(randf_range(-1, 1), 0.3, randf_range(-0.5, 0.5)), e.get("state", {}))
	await _frames(3)
	var before := _hub_units([s, player])
	var notes: Array = []
	var on_note := func(t: String) -> void: notes.append(t)
	BaseHub.note.connect(on_note)
	BaseHub.request("restock_squad")
	await _frames(3)
	var rebuilt := Restock.template_of(Roster.json_safe(s.inventory.net_state))
	check(rebuilt == loadout, "Restock squad rebuilds %s's loadout from the stash on the floor" % String(s.name))
	if rebuilt != loadout:
		print("    wanted %s\n    got    %s\n    notes %s" % [JSON.stringify(loadout, "", true), JSON.stringify(rebuilt, "", true), notes])
	check(Roster.gear_counts(BaseHub.member(mid).gear) == Roster.gear_counts(Roster.json_safe(s.inventory.net_state)), "and it's his gear on the roster")
	check(_hub_units([s, player]) == before, "nothing is made or lost: the armory's items and the kits hold the same")
	# The player: kit off and gone; the stash has no helmet.
	player.inventory.strip()
	for n: Node in level.items.get_children():
		if n is WorldItem and (n as WorldItem).item_id == &"helmet":
			GameState.item_taken((n as WorldItem).uid)
			n.queue_free()
	await _frames(2)
	before = _hub_units([s, player])
	notes.clear()
	BaseHub.request("restock")
	await _frames(3)
	BaseHub.note.disconnect(on_note)
	check(player.inventory.slots[&"vest"] == &"plate_carrier" and player.inventory.slots[&"helmet"] == &"",
		"the player's Restock puts on what the stash has (the carrier)")
	check(notes.size() == 1 and String(notes[0]).contains("Missing from the stash: Ballistic Helmet"), "and lists what it hasn't (%s)" % [notes])
	check(_hub_units([s, player]) == before, "and the carrier's pouches it didn't need lie in the stash: nothing made or lost")
	var screen: InventoryScreen = player._hud.inventory_screen if player._hud else null
	if screen:
		screen.visible = true
		await _frames(2)
		check(screen._quick_box.get_node_or_null(^"RestockButton") != null, "the inventory screen has the Restock button at the base")
		screen.visible = false


## Units of every item in the hub's stash (world items, with what's on and in them) and on
## `soldiers`, item by item.
func _hub_units(soldiers: Array) -> Dictionary:
	var stash := (level as BaseLevel).server_collect_stash()
	var out := BaseArmory.counts(stash)
	var inside := BaseArmory.contents_counts(stash)
	for id: String in inside:
		out[id] = int(out.get(id, 0)) + int(inside[id])
	for s: Soldier in soldiers:
		var worn := Roster.gear_counts(Roster.json_safe(s.inventory.net_state))
		for id: String in worn:
			out[id] = int(out.get(id, 0)) + int(worn[id])
	return out
