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
	Soldier.respawn_delay_s = 0.0  # these checks want the old instant respawn (the wait and spawn
	Soldier.spawn_protect_s = 0.0  # protection have their own checks in gameplay and missions)
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
	BaseHub.delete_test_campaign_files()  # whatever a run cut short left behind
	_test_stash_and_saves()
	_test_damaged_saves()
	_test_archive()
	_test_squad_count()
	_test_hiring()
	_test_callsigns()
	_test_wages()
	_test_heli_upgrades()
	_test_growth()
	_test_injuries_and_medbay()
	_test_respawn_pool()
	_test_resolve()
	_test_stand_ins()
	_test_restock()
	await _test_session()
	GameState.zone_id = "test_base" + tag
	GameState.delete_save()
	BaseHub.delete_test_campaign_files()  # every zone save and copy set aside: the game deletes none
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
	check(not FileAccess.file_exists(path) and Array(GameState.kept_copies(path)).any(func(f: String) -> bool: return f.contains(".replaced-")),
		"and a new campaign starts with none: the old one is set aside, never deleted (%s)" % ", ".join(GameState.kept_copies(path)))
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


## Deletes the campaign's save and zone saves, their backups, interrupted writes and every copy
## kept aside (BaseHub.delete_test_campaign_files: the game itself never deletes a save).
func _wipe_campaign_files() -> void:
	if BaseHub.delete_test_campaign_files() < 0:
		check(false, "the test campaign's files are deleted (only a test_ campaign's ever are)")


## Captain, 2026-10-14: "New campaign (archive current saves)" puts the campaign away, never
## deletes it: its save, zone saves (the FOB's too), backups and copies kept aside all move into
## the archive folder as they were, and another campaign's files stay. A deployment sets the
## zone's earlier save aside (kept, never loaded), never the FOB's. And the test-only delete
## refuses a campaign that isn't a test's.
func _test_archive() -> void:
	print("Archiving a campaign, setting zone saves aside")
	_wipe_campaign_files()
	var own_id := Campaign.campaign_id
	var real := "not_a_test" + tag
	Campaign.campaign_id = real
	check(BaseHub.delete_test_campaign_files() == -1, "the test-only delete refuses a campaign that isn't a test's (%s)" % real)
	Campaign.campaign_id = own_id
	# set_aside_zone_save: a zone's earlier save is kept aside, the FOB's never.
	var zone_path := "%s/%s.json" % [GameState.SAVE_DIR, BaseHub.zone_save_id("aside_zone")]
	var zone_text := JSON.stringify({"version": GameState.SAVE_VERSION, "looted": ["earlier"], "dropped": {}, "voxel_edits": [], "bodies": []})
	_write(zone_path, zone_text)
	_write(GameState.backup_path(zone_path), zone_text)
	var n := BaseHub.set_aside_zone_save("aside_zone")
	var kept := GameState.kept_copies(zone_path)
	check(n == 2 and not GameState.has_save(zone_path) and kept.size() == 2
		and Array(kept).all(func(f: String) -> bool: return f.contains("earlier-deployment") and FileAccess.get_file_as_string("%s/%s" % [GameState.SAVE_DIR, f]) == zone_text),
		"a zone's earlier save and backup are set aside, as they were, and nothing loads them (%s)" % ", ".join(kept))
	var fob_path := "%s/%s.json" % [GameState.SAVE_DIR, BaseHub.base_zone_id()]
	_write(fob_path, zone_text)
	check(BaseHub.set_aside_zone_save("fob") == 0 and FileAccess.file_exists(fob_path) and GameState.kept_copies(fob_path).is_empty(),
		"never the FOB's save")
	# archive_campaign into a test folder (never the real archive folder).
	BaseHub.new_campaign(SEED)
	BaseHub.base()["sentinel"] = 4141
	BaseHub.server_save()
	BaseHub.server_save()  # the second keeps the first as the backup
	_write(fob_path, zone_text)  # new_campaign set the FOB's aside: it's back
	_write(zone_path, zone_text)
	_write(GameState.backup_path(zone_path), zone_text)
	_write(Campaign.save_path() + ".unreadable-20261014-000000", "{broken")
	var other := "%s/test_base_other%s.json" % [Campaign.SAVE_DIR, tag]
	_write(other, "other campaign")
	var expect := {}
	for f in BaseHub._campaign_files():
		expect[f] = FileAccess.get_file_as_string("%s/%s" % [Campaign.SAVE_DIR, f])
	var names := PackedStringArray(expect.keys())
	var save_file := Campaign.save_path().get_file()
	var wanted := [save_file, save_file + ".bak", save_file + ".unreadable-20261014-000000", zone_path.get_file(), zone_path.get_file() + ".bak", fob_path.get_file()]
	check(wanted.all(func(f: String) -> bool: return expect.has(f)) and Array(kept).all(func(f: String) -> bool: return expect.has(f))
		and not expect.has(other.get_file()),
		"the campaign's files: save, backup, zone save and backup, the FOB's, copies kept aside (%d)" % names.size())
	var into := "user://test_archive" + tag
	_wipe_folder(into)
	var out := BaseHub.archive_campaign(into)
	var moved := PackedStringArray(out.moved)
	moved.sort()
	names.sort()
	check(out.dir == ProjectSettings.globalize_path(into) and (out.failed as Array).is_empty() and moved == names,
		"archive_campaign moves every one into the folder given (%d moved, %d failed)" % [moved.size(), (out.failed as Array).size()])
	check(expect.keys().all(func(f: String) -> bool: return FileAccess.get_file_as_string("%s/%s" % [into, f]) == expect[f]),
		"each as it was")
	check(BaseHub._campaign_files().is_empty() and not Campaign.has_save() and not GameState.has_save(zone_path) and not GameState.has_save(fob_path),
		"nothing of the campaign is left in the saves folder")
	check(FileAccess.get_file_as_string(other) == "other campaign", "another campaign's save is left alone")
	check(not BaseHub.started() and not BaseHub.base().has("sentinel") and not BaseHub.campaign_running, "and the campaign in memory is empty")
	DirAccess.remove_absolute(other)
	_wipe_folder(into)
	DirAccess.remove_absolute(into)


## Deletes every file in `dir` (a test's own folder).
func _wipe_folder(dir: String) -> void:
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute("%s/%s" % [dir, f])


## Captain, 2026-10-14: the Ops desk said "6 of 7 AI" over three names, the other three KIA.
## The count (BaseUI.picked_count) and the pick itself (BaseHub._prune_prep_squad) leave out
## the killed, the MIA and the recovering.
func _test_squad_count() -> void:
	print("The Ops desk's squad count")
	_wipe_campaign_files()
	BaseHub.new_campaign(SEED)
	for i in 4:
		BaseHub.server_hire(String(_cheapest(Hiring.pool(BaseHub.hiring(), 1)).cid))
	var ids := Roster.ids(BaseHub.roster())
	check(ids.size() == 4, "four hired (%d)" % ids.size())
	if ids.size() < 4:
		return
	for mid in ids:
		BaseHub.server_pick(mid, true)
	var picked: Array = BaseHub._prep().squad
	var members: Dictionary = BaseHub.roster().get("members", {})
	check(BaseUI.picked_count(picked, members) == 4, "four picked, four counted")
	BaseHub.member(ids[0])["status"] = Roster.DEAD
	BaseHub.member(ids[1])["status"] = Roster.MIA
	BaseHub.member(ids[2])["sit_out_days"] = 3
	check(BaseUI.picked_count(picked, members) == 1 and BaseUI.picked_count(picked + ["nobody"], members) == 1,
		"the killed, the MIA and the recovering aren't counted, nor anyone not on the roster (%d)" % BaseUI.picked_count(picked, members))
	check(BaseHub._prune_prep_squad() and BaseHub._prep().squad == [ids[3]], "and they leave the pick (%s)" % ", ".join(PackedStringArray(BaseHub._prep().squad)))
	check(not BaseHub._prune_prep_squad(), "a pick of the deployable stays as it is")
	_wipe_campaign_files()


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
	check(on == want_pouches and (mags_in_pouches > 0 or not want.keys().any(func(k: String) -> bool: return k.begins_with("mag_"))) and tq_held,
		"their carrier wears the kit's pouches (%d), with magazines (%d) and a tourniquet in them" % [molle.size(), mags_in_pouches])
	var counts := Roster.gear_counts(m.gear)
	var missing := want.keys().filter(func(id: String) -> bool: return int(counts.get(id, 0)) < int(want[id]))
	check(missing.is_empty(), "and all of the kit is counted, pouch contents too%s" % ("" if missing.is_empty() else " (short: %s)" % ", ".join(PackedStringArray(missing))))


## Captain, 2026-10-17: "the upgrade system for the helicopters" (HeliUpgrades): one-time air
## wing purchases, company-wide in the economy section: the Razorback for transport, extraction
## and insertion, an armoured cabin kit, faster turnarounds. Paid from cash, kept by the save,
## gone with a new campaign.
func _test_heli_upgrades() -> void:
	print("Air wing upgrades")
	BaseHub.new_campaign(SEED)
	var base_cd := float((HeliSupports.data().cooldown_s as Dictionary).transport)
	check(HeliUpgrades.owned_ids().is_empty() and HeliUpgrades.model_for("transport") == HeliSupports.MODEL
		and HeliUpgrades.damage_mult() == 1.0 and is_equal_approx(HeliSupports.cooldown_s("transport"), base_cd),
		"a new company flies the stock air wing (%s, %d s transport cooldown)" % [HeliSupports.MODEL, roundi(base_cd)])
	check(HeliSupports.MODEL == "uh60", "the stock air wing is the UH-60")
	Economy.add_cash(500000 - Economy.cash(), "test: flush")
	check(Economy.server_buy_heli_upgrade("razorback").begins_with("Needs the") and not HeliUpgrades.owned("razorback") and Economy.cash() == 500000,
		"the Razorback needs the Petrel first: refused, nothing taken")
	var petrel_cost := int(HeliUpgrades.def("petrel").cost)
	check(Economy.server_buy_heli_upgrade("petrel") == "" and HeliUpgrades.owned("petrel") and Economy.cash() == 500000 - petrel_cost,
		"bought the Petrel ($%s off the cash)" % DebriefCalc.money(petrel_cost))
	check(HeliUpgrades.model_for("transport") == "vtol_petrel" and HeliUpgrades.model_for("resupply") == "vtol_petrel"
		and HeliUpgrades.model_for("medevac") == "vtol_petrel", "every support call now flies the Petrel")
	var cost := int(HeliUpgrades.def("razorback").cost)
	Economy.add_cash(cost - 1 - Economy.cash(), "test: just short")
	check(Economy.server_buy_heli_upgrade("razorback") == "Can't afford it" and not HeliUpgrades.owned("razorback") and Economy.cash() == cost - 1,
		"$1 short of the Razorback: refused, nothing taken")
	Economy.add_cash(500000 - Economy.cash(), "test: flush")
	check(Economy.server_buy_heli_upgrade("razorback") == "" and HeliUpgrades.owned("razorback") and Economy.cash() == 500000 - cost,
		"bought the Razorback ($%s off the cash)" % DebriefCalc.money(cost))
	check(Economy.server_buy_heli_upgrade("razorback") == "Already owned" and Economy.cash() == 500000 - cost, "bought once: a second buy is refused, free")
	check(HeliUpgrades.model_for("transport") == "vtol_razorback" and HeliUpgrades.model_for("extraction") == "vtol_razorback"
		and HeliUpgrades.model_for("insertion") == "vtol_razorback" and HeliUpgrades.model_for("resupply") == "vtol_petrel"
		and HeliUpgrades.model_for("medevac") == "vtol_petrel" and HeliCall.new(null, "transport", null, {}).model == "vtol_razorback",
		"transport, extraction and insertion calls fly the Razorback; resupply and medevac stay on the Petrel")
	var seats := func(m: String) -> int:
		return (VehicleSpecs.spec(m).seats as Array).filter(func(st: Dictionary) -> bool: return String(st.kind) == "passenger").size()
	check(seats.call("vtol_razorback") > seats.call("vtol_petrel"), "and it carries more troops (%d passenger seats, not %d)" % [seats.call("vtol_razorback"), seats.call("vtol_petrel")])
	check(HeliUpgrades.lost_mult("transport") > 1.0 and HeliUpgrades.lost_mult("transport") > HeliUpgrades.lost_mult("resupply") and HeliUpgrades.lost_mult("resupply") > 1.0, "a lost Razorback costs more to replace than a lost Petrel, a Petrel more than a UH-60")
	check(Economy.server_buy_heli_upgrade("armoured_cabin") == "" and Economy.server_buy_heli_upgrade("fast_turnaround") == "",
		"the armoured cabin kit and fast turnaround bought")
	check(is_equal_approx(HeliUpgrades.damage_mult(), float(HeliUpgrades.def("armoured_cabin").damage_mult))
		and is_equal_approx(HeliSupports.cooldown_s("transport"), base_cd * float(HeliUpgrades.def("fast_turnaround").cooldown_mult)),
		"hits do %d%% of the damage, cooldowns %d s" % [roundi(HeliUpgrades.damage_mult() * 100.0), roundi(HeliSupports.cooldown_s("transport"))])
	check(Economy.server_buy_heli_upgrade("no_such") == "No such upgrade", "an unknown upgrade is refused")
	BaseHub.new_campaign(SEED)
	check(HeliUpgrades.owned_ids().is_empty() and HeliUpgrades.model_for("transport") == HeliSupports.MODEL, "a new campaign starts without them")


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
	var roster_before := roster.duplicate(true)
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
	terms["support_points"] = 2
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
	var roster_before := roster.duplicate(true)
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
	# The armory is organised: bands per category, no shared slot; deliveries take free slots.
	var stash_now := BaseHub.stash()
	var slots := BaseArmory.layout(stash_now)
	var seen := {}
	var bands_ok := true
	for k in stash_now.size():
		bands_ok = bands_ok and not seen.has(slots[k])
		seen[slots[k]] = true
	check(bands_ok, "the stash is laid out one item to a slot (%d entries)" % stash_now.size())
	var band_rows := {}
	for k in stash_now.size():
		if slots[k] < BaseArmory.grid_slots():
			var b := BaseArmory.band_of(StringName(String(stash_now[k].id)))
			var row: int = slots[k] / BaseArmory.columns()
			band_rows[row] = band_rows.get(row, b)
			bands_ok = bands_ok and band_rows[row] == b
	check(bands_ok, "each armory row holds one category")
	var occupied_before := {}
	for node: Node in base.items.get_children():
		if node is WorldItem and BaseArmory.slot_at((node as WorldItem).global_position) >= 0:
			occupied_before[BaseArmory.slot_at((node as WorldItem).global_position)] = true
	var fresh: Array[StringName] = []
	for gid: StringName in [&"flashbang", &"smoke_grenade", &"frag_grenade"]:
		if BaseArmory.count_of(BaseHub.stash(), gid) == 0:
			fresh.append(gid)
			base.server_deliver(gid, 2, {})
	var landed := {}
	var clash := false
	for node: Node in base.items.get_children():
		var w := node as WorldItem
		if w and BaseArmory.slot_at(w.global_position) >= 0:
			var sl := BaseArmory.slot_at(w.global_position)
			if landed.has(sl):
				clash = true
			landed[sl] = true
	check(not clash, "a delivery lands on a free slot, never on top of another item")
	check(BaseArmory.band_of(&"flashbang") == BaseArmory.band_of(&"frag_grenade"), "grenades share a band")
	for node: Node in base.items.get_children():  # the test's deliveries go again: the stash is what it was
		var w := node as WorldItem
		if w and w.item_id in fresh:
			GameState.item_taken(w.uid)
			w.queue_free()
	var stash_counts := BaseArmory.counts(BaseHub.stash())
	check(BaseArmory.counts(base.server_collect_stash()) == stash_counts, "the stash lies in the armory as world items (%d kinds)" % stash_counts.size())
	var member0 := BaseHub.member(ids[0])
	var s0 := base.muster_soldier(ids[0])
	check(s0 != null and String(s0.name) == String(member0.callsign) and Roster.gear_counts(Roster.json_safe(s0.inventory.net_state)) == Roster.gear_counts(member0.gear),
		"each in their own gear, by callsign (%s)" % member0.callsign)
	await _test_gear_vs_kit(base)
	await _test_terminals(base)
	var client := await _start_client(ids, stash_counts)
	await _test_armory(base)
	await _test_deployment(client)
	await _finish_client(client)
	await _test_restock_session()
	await _test_restock_conservation()
	await _test_restock_medic_first()
	await _test_restock_top_up()
	await _test_restock_player_leaves_medic()
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
	check(BaseHub.all_ready() and BaseHub.not_ready_names().is_empty(), "FOB ready-up: a host alone is always ready (their Deploy is their ready)")
	BaseHub.server_set_ready(77, true)  # stands for someone who readied before the client came
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "a client process starts")
	var deadline := Time.get_ticks_msec() + 120000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(log_path) and FileAccess.get_file_as_string(log_path).contains(CLIENT_HUB_DONE):
			break
		await _seconds(0.25)
	check(Roster.ids(BaseHub.roster()).size() == ids.size() + 1, "the host hired who the client asked for (%d on the books)" % Roster.ids(BaseHub.roster()).size())
	check(77 not in BaseHub.ready_peers(), "a player joining resets the FOB ready-up")
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
	var me := multiplayer.get_unique_id()
	check(not BaseHub.is_ready(me) and ", ".join(PackedStringArray(BaseHub.not_ready_names())) == "Player %d" % me,
		"FOB ready-up: the client starts not ready and sees the host waiting for it (%s)" % ", ".join(PackedStringArray(BaseHub.not_ready_names())))
	BaseHub.request("ready", [true])
	var readied := await _wait_until(func() -> bool: return BaseHub.is_ready(me) and BaseHub.all_ready(), 10.0)
	check(readied, "its Ready goes through the host and comes back in the view")
	_say(CLIENT_HUB_DONE)
	# Captain, 2026-10-14: a client sat on the debrief when the host moved on into the next zone
	# and couldn't leave it. A debrief left open here closes when the client follows.
	var debrief: Object = Contracts.show_debrief()
	var had_debrief := debrief != null
	# The host deploys: the session moves to the zone, then back.
	var deployed := await _wait_until(func() -> bool:
		var l := CompoundLevel.current(self)
		return l != null and not l is BaseLevel, 120.0)
	check(deployed, "the client follows the host into the zone")
	await get_tree().process_frame
	check(had_debrief and not is_instance_valid(debrief) and Contracts.debrief_screen() == null,
		"and the debrief it had open closed on the way (the switch doesn't wait on it)")
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
	check(not BaseHub.is_ready(me), "back at the FOB the client has to ready up again")
	_say("CLIENT %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	_log.close()
	Net.leave()
	get_tree().quit(failures)


## B-23: in a campaign the player's own saved gear is what they carry and no role kit is
## stacked on it, whichever comes first (their role or their gear); a brand-new player gets
## their role's kit once. The bug: with player_role_kits on, rebalance_squad put the kit on
## first and _apply_player_gear then replaced the whole inventory, so a late joiner with no
## saved gear deployed with nothing.
func _test_gear_vs_kit(base: BaseLevel) -> void:
	print("Campaign gear against the role kit (B-23)")
	var player: Soldier = level.players.get_node(^"1")
	var key := BaseHub.player_key(1)
	var main := Roster.main_character(BaseHub.roster(), key)
	var kit_counts := Roster.gear_counts(Roster.gear_for_kit(Roles.kit(player.role)))
	check(player.role != &"" and Roster.gear_counts(Roster.json_safe(player.inventory.net_state)) == kit_counts,
		"a brand-new player starts in their %s kit" % player.role)
	check(not main.get("kit_due", false), "and owes no second one")
	var before: Dictionary = player.inventory.net_state.duplicate(true)
	# Someone with saved gear: the kit flag left on (as a stale play session would), the role
	# arriving before the gear (a joiner's pick racing their hello).
	var saved := Roster.gear_for_kit([[&"m17", 1]])
	main["gear"] = saved.duplicate(true)
	CompoundLevel.player_role_kits = true
	BaseHub._gear_applied.erase(1)
	base.rebalance_squad()
	BaseHub._apply_player_gear(1, player)
	base.rebalance_squad()
	check(Roster.gear_counts(Roster.json_safe(player.inventory.net_state)) == Roster.gear_counts(saved),
		"saved gear wins: no role kit on top of it (%s)" % Roster.gear_counts(Roster.json_safe(player.inventory.net_state)))
	# A new player whose gear goes on before their role is known: the kit once, when it is.
	var fresh_key := key
	Roster.players(BaseHub.roster()).erase(fresh_key)
	BaseHub._gear_applied.erase(1)
	var role := player.role
	player.role = &""
	BaseHub._apply_player_gear(1, player)
	check(Roster.gear_counts(Roster.json_safe(player.inventory.net_state)).is_empty(), "a new player waits for their role with nothing doubled")
	player.role = role
	base.rebalance_squad()
	base.rebalance_squad()
	check(Roster.gear_counts(Roster.json_safe(player.inventory.net_state)) == kit_counts, "then gets their kit exactly once")
	CompoundLevel.player_role_kits = false
	main = Roster.main_character(BaseHub.roster(), key)
	main["gear"] = Roster.json_safe(before.duplicate(true))
	player.inventory.net_state = before
	await get_tree().process_frame
	await _test_stand_in_own_kit(player, key)


## Captain, 2026-10-15 (loadouts reset when infiltrating): a player whose main character is
## recovering plays a stand-in, but in HIS OWN armory kit; the kit moves (never copies) onto the
## stand-in and comes home on his main character, the stand-in getting their own gear back.
func _test_stand_in_own_kit(player: Soldier, key: String) -> void:
	print("A recovering player keeps his own kit")
	var inv_before: Dictionary = player.inventory.net_state.duplicate(true)
	var roster := BaseHub.roster()
	var roster_before := roster.duplicate(true)
	var ids := Roster.ids(roster)
	if ids.is_empty():
		BaseHub.server_hire(String(_cheapest(Hiring.pool(BaseHub.hiring(), 1)).cid))
		ids = Roster.ids(roster)
	var mid: String = ids[0]
	var sm := BaseHub.member(mid)
	var own := Roster.gear_for_kit([[&"m17", 1], [&"helmet", 1]])
	var theirs: Dictionary = (sm.get("gear", {}) as Dictionary).duplicate(true)
	var main := Roster.main_character(roster, key)
	var main_before: Dictionary = (main.get("gear", {}) as Dictionary).duplicate(true)
	main["gear"] = own.duplicate(true)
	main["sit_out_days"] = 3
	RosterDeployment.begin(roster, [], RosterDeployment.CONTRACT, "test", "", BaseHub.day(), {}, {key: mid})
	BaseHub._gear_applied.erase(1)
	BaseHub._apply_player_gear(1, player)
	check(Roster.gear_counts(Roster.json_safe(player.inventory.net_state)) == Roster.gear_counts(own),
		"he plays the stand-in in his own kit, not theirs (%s)" % Roster.gear_counts(Roster.json_safe(player.inventory.net_state)))
	check((BaseHub.member(mid).gear as Dictionary).hash() == own.hash() and (Roster.main_character(roster, key).get("gear", {}) as Dictionary).is_empty(),
		"the kit moved onto the stand-in: never on two people at once")
	BaseHub._gear_applied.erase(1)  # a rejoin in the same deployment: still his kit, still one copy
	BaseHub._apply_player_gear(1, player)
	check(Roster.gear_counts(Roster.json_safe(player.inventory.net_state)) == Roster.gear_counts(own), "applied again (a rejoin): still his own kit")
	var came_home := Roster.gear_for_kit([[&"m17", 1], [&"helmet", 1], [&"smoke_purple", 1]])
	var outcomes := {"members": {}, "players": {key: {"state": RosterDeployment.EXTRACTED, "gear": came_home, "pos": [0.0, 0.0, 0.0]}}}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	RosterDeployment.resolve(roster, outcomes, rng, BaseHub.day())
	check((Roster.main_character(roster, key).get("gear", {}) as Dictionary).hash() == came_home.hash() and (BaseHub.member(mid).gear as Dictionary).hash() == theirs.hash(),
		"extracted: the kit (and what he picked up) is home on him, the stand-in has their own gear back")
	roster.clear()  # the roster as it was: nothing of this stays for the checks after it
	roster.merge(roster_before)
	BaseHub._gear_applied[1] = true
	player.inventory.net_state = inv_before


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
	## The motor pool's sign opens its own page (audit P2-23: it was only an interaction ring).
	var pool: Dictionary = InteractionMenu.actions_for(player, base.get_node(^"Terminal_motor_pool"))[0]
	check(String(pool.label) == "Use Motor pool" and String(pool.disabled) == "" and pool.has("call"), "the motor pool offers Use in the interaction menu")
	InteractionMenu.perform(player, pool)
	check(ui.is_open() and ui.page == "motor_pool" and ui._pages["motor_pool"].get_child_count() > 0, "and opens the base screen on its page")
	## Service is on only at the motor pool's sign (review of ui/base-hub: the page is a tab on
	## every terminal's screen, and the host refused bookings from the ops desk unseen).
	var hurt := MotorPool.add("matv", "", {"zones": {"hull": 0.5}, "fuel": 300.0})
	var sign: Node3D = base.get_node(^"Terminal_motor_pool")
	var was := player.global_transform
	player.global_position = sign.global_position + Vector3(30, 0, 0)
	await get_tree().process_frame
	await get_tree().process_frame  # the pool's view comes over (MotorPoolNode._send, deferred)
	ui.open("motor_pool")
	await get_tree().process_frame
	var service := ui._pages["motor_pool"].find_child("Service_" + hurt.validate_node_name(), true, false) as Button
	check(service != null and service.disabled and service.tooltip_text == BaseUI.AWAY_FROM_POOL,
		"away from the sign (the ops desk's Motor pool tab), Service is off: \"%s\"" % (service.tooltip_text if service else "no Service button"))
	player.global_position = sign.global_position + Vector3(1.5, 0, 0)
	ui.refresh()
	await get_tree().process_frame
	service = ui._pages["motor_pool"].find_child("Service_" + hurt.validate_node_name(), true, false) as Button
	check(service != null and not service.disabled, "and on at the sign")
	var upgrade := ui._pages["motor_pool"].find_child("Upgrade_razorback", true, false) as Button
	check(upgrade != null and (upgrade.text.begins_with("Buy: $") or upgrade.text == "Owned"),
		"the Motor pool page lists the air wing upgrades with a Buy button (%s)" % (upgrade.text if upgrade else "none"))
	player.global_transform = was
	MotorPool.remove(hurt)
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
	# A co-op client's own kit (Captain, 2026-10-15: loadouts reset when infiltrating): what the
	# client stands in at the FOB is what it deploys in, under the profile it played at the base.
	var client_body := level.players.get_node_or_null(str(multiplayer.get_peers()[0]) if not multiplayer.get_peers().is_empty() else "0") as Soldier
	var client_before := {}
	if client_body != null:
		client_body.inventory.take(&"smoke_purple", 2)
		client_before = Roster.gear_counts(Roster.json_safe(client_body.inventory.net_state))
	for mid: String in squad:
		BaseHub.server_pick(mid, true)
	var wage_a := int(BaseHub.member(a).wage)
	var day := BaseHub.day()
	# FOB ready-up (Captain, 2026-10-14): no deploying while a player isn't ready.
	var peers := multiplayer.get_peers()
	var client_peer: int = peers[0] if not peers.is_empty() else 0
	check(client_peer != 0 and BaseHub.is_ready(client_peer), "the client readied up from its base screen (Player %d)" % client_peer)
	BaseHub.server_set_ready(client_peer, false)
	var why := BaseHub.server_deploy({"zone_id": ZONE + tag, "no_contract": true})
	check(why == BaseHub.WAITING_FOR + "Player %d" % client_peer and not RosterDeployment.is_running(BaseHub.roster()),
		"deploy is refused while the client isn't ready, naming them (%s)" % why)
	BaseHub.request("deploy")  # the Deploy button's way: refused the same
	await _frames(2)
	check(not RosterDeployment.is_running(BaseHub.roster()), "and so is the Deploy button's request")
	BaseHub.server_set_ready(client_peer, true)
	check(BaseHub.all_ready(), "once the client is ready again everyone is")
	why = BaseHub.server_deploy({"zone_id": ZONE + tag, "no_contract": true})
	check(why == "" and RosterDeployment.is_running(BaseHub.roster()), "deploy starts the deployment")
	check(BaseHub.ready_peers().is_empty(), "and the ready-up resets for the next one")
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
	var client_after := level.players.get_node_or_null(str(multiplayer.get_peers()[0]) if not multiplayer.get_peers().is_empty() else "0") as Soldier
	check(client_after != null and not client_before.is_empty()
		and Roster.gear_counts(Roster.json_safe(client_after.inventory.net_state)) == client_before,
		"the client deploys in its own kit, not a default one (%s vs %s)" % [client_before, Roster.gear_counts(Roster.json_safe(client_after.inventory.net_state)) if client_after else "none"])
	# A player death counts against the pool.
	var deployed_kit := Roster.gear_counts(Roster.json_safe(player.inventory.net_state))
	var bodies_before := level.bodies.get_child_count()
	player.vitals.server_kill()
	await _frames(2)
	check(int(RosterDeployment.active(BaseHub.roster()).get("respawns_used", 0)) == 1, "a player respawn counts (%d free left)" % RosterDeployment.free_respawns_left(BaseHub.roster()))
	# Captain, 2026-10-14: "respawn with the kit you had on. delete old player/bot bodies": the
	# armory kit is still on him, and no body holds a second set of it.
	check(Roster.gear_counts(Roster.json_safe(player.inventory.net_state)) == deployed_kit and level.bodies.get_child_count() == bodies_before,
		"he respawns in the kit he deployed in, and leaves no body with a second set of it")
	# Giving up while down (Captain, P0362) is a death like any other: the pool counts it too.
	player.vitals.server_damage(500.0)
	await _frames(2)
	player._down_since = Soldier._now() - Soldier.GIVE_UP_AFTER_S - 1.0  # down long enough, help near or not
	player._server_give_up.rpc_id(1)
	await _frames(2)
	check(player.vitals.is_up() and int(RosterDeployment.active(BaseHub.roster()).get("respawns_used", 0)) == 2,
		"giving up while down respawns through the pool (%d free left)" % RosterDeployment.free_respawns_left(BaseHub.roster()))
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
	var debrief: Object = Contracts.show_debrief()  # Captain, 2026-10-14: an open debrief doesn't hold anyone at the base
	# Captain, 2026-10-14: every contract finds its zone fresh. The zone's save from an earlier
	# deployment (the compound's from _test_deployment, bodies and all) is set aside, not loaded.
	var earlier_path := "%s/%s.json" % [GameState.SAVE_DIR, BaseHub.zone_save_id(ZONE + tag)]
	var wide_path := "%s/%s.json" % [GameState.SAVE_DIR, BaseHub.zone_save_id(ZONE + "_wide" + tag)]
	var earlier := FileAccess.get_file_as_string(earlier_path)
	var earlier_data: Variant = JSON.parse_string(earlier) if earlier != "" else null
	check(earlier_data is Dictionary and not (earlier_data.get("bodies", []) as Array).is_empty(), "the earlier deployment's zone save has bodies in it")
	_write(wide_path, earlier)
	var why := BaseHub.server_deploy({"level": {"level": "zone", "def": def}, "zone_id": ZONE + "_wide" + tag, "squad": squad, "no_contract": true})
	var moved := await _wait_until(func() -> bool: return CompoundLevel.current(self) is ZoneLevel, 20.0)
	await get_tree().process_frame
	check(not is_instance_valid(debrief) and Contracts.debrief_screen() == null, "heading into the zone closes an open debrief")
	var zone := CompoundLevel.current(self) as ZoneLevel
	check(why == "" and moved and zone != null and int(zone.def.get("seed", -1)) == int(def.seed) and zone.modules().size() == (def.modules as Array).size(),
		"deploying into a zone generates it from its definition (%s, %d modules)" % [String(def.get("name", "?")), zone.modules().size() if zone else 0])
	if zone == null:
		return
	level = zone
	check(get_tree().get_nodes_in_group(&"level").size() == 1, "and it is the session's one level")
	await _frames(5)
	check(GameState.bodies.is_empty() and get_tree().get_nodes_in_group(&"dead_bodies").is_empty(),
		"a second deployment into the zone starts fresh: no bodies from the earlier one (%d)" % get_tree().get_nodes_in_group(&"dead_bodies").size())
	var set_aside := GameState.kept_copies(wide_path)
	check(set_aside.size() == 1 and set_aside[0].contains("earlier-deployment") and FileAccess.get_file_as_string("%s/%s" % [GameState.SAVE_DIR, set_aside[0]]) == earlier,
		"and the earlier save is set aside as it was, not deleted (%s)" % ", ".join(set_aside))
	var player := zone.players.get_node_or_null(^"1") as Soldier
	var start := zone.insertion_points()[0]
	check(player != null and Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length() < 10.0,
		"the host's player starts at the zone's insertion point")
	var up := squad.is_empty() or await _wait_until(func() -> bool: return _roster_soldier(String(squad[0])) != null, 30.0)
	check(up, "the picked squadmate deploys into the zone with them")
	# Captain, 2026-10-14 (falling out of the world): straight after the switch, and a moment
	# on, everyone stands on the zone's ground, none below it or past its edge.
	check(_all_on_ground(zone), "right after the switch into the zone, nobody is below or past its ground")
	await get_tree().create_timer(1.5).timeout
	check(_all_on_ground(zone) and zone.get_node_or_null(^"GroundGuard") is GroundGuard,
		"and a moment on still nobody has fallen (the zone's safety net is in place)")
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
	await get_tree().create_timer(1.5).timeout
	check(level != null and _all_on_ground(level), "back at the base a moment on, nobody is below or past its ground (S0736)")


## Every soldier in `lvl` within 2 m of its ground height and inside its ground area.
func _all_on_ground(lvl: CompoundLevel) -> bool:
	var ok := true
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s.is_queued_for_deletion() or is_instance_valid(s.vehicle):
			continue
		var p := s.global_position
		var fine := absf(p.y - lvl.ground_height(p.x, p.z)) < 2.0 and lvl.ground_area().grow(0.5).has_point(Vector2(p.x, p.z))
		if not fine:
			print("    %s is at %s (ground %.1f)" % [s.log_name(), p, lvl.ground_height(p.x, p.z)])
		ok = ok and fine
	return ok


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
	check(Economy.cash() == cash_before + int(debrief.totals.paid_now) - bills[0] - (debrief.expenses as Array).reduce(func(a: int, l: Dictionary) -> int: return a + (int(l.amount) if bool(l.charge) else 0), 0) and int(line.get("pay", 0)) > 0,
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
	# A grid beside the recovered member may be inland: that is a helicopter LZ.
	# Bring everyone to a real walk-out point at the zone edge for this foot extraction.
	var area := MapNodes.area_of(level)
	var exit_at := Vector2(area.position.x + 10.0, area.get_center().y)
	var ground := (level as ZoneLevel).ground_point(Vector3(exit_at.x, 0, exit_at.y))
	player.global_position = ground
	target.global_position = ground + Vector3(1, 0, 0)
	if mate:
		mate.global_position = ground + Vector3(-1, 0, 1)
	await _frames(2)
	var exit_id := extraction.server_add_point(exit_at)
	check(bool(extraction.point_by_id(exit_id).get("foot", false)), "the recovery's walk-out point is at the zone edge")
	var exit_why := extraction.server_confirm()
	check(exit_why == "", "and extract with the squad (%s)" % exit_why)
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
	# Role kits wear both plates (Inventory.take wears one unit per call: the second went in the vest).
	var kitted := Inventory.new()
	Roles.apply_kit(kitted, Roles.RIFLEMAN)
	var from_roster := Inventory.new()
	from_roster.net_state = GameState.from_json(Roster.gear_for_kit(Roles.kit(Roles.MEDIC)))
	for k: Inventory in [kitted, from_roster]:
		check(k.slots[&"plate_front"] == &"plate_ceramic_l4" and k.slots[&"plate_back"] == &"plate_ceramic_l4" and k.count_of(&"plate_ceramic_l4") == 0,
			"a role kit wears both plates, front and back, none stowed (%s / %s, %d stowed)" % [k.slots[&"plate_front"], k.slots[&"plate_back"], k.count_of(&"plate_ceramic_l4")])
		k.free()
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
	_test_restock_shared()


## S0743 (restock left the medic short silently): two medics (one per fire team) restocked
## from a stash with 3 IVs and 1 epinephrine for 6 and 6. Dealt out round the squad
## (Restock.fair_caps): 2 IVs and the epinephrine to the first, 1 IV to the second, not all
## of it to whoever went first; each one's shortfall is listed and kept for the squad page.
func _test_restock_shared() -> void:
	var medic_gear: Dictionary = Roster.gear_for_kit(Roles.kit(Roles.MEDIC))
	var medic := Restock.template_of(medic_gear)
	var pool := _scatter(medic_gear)
	for e: Dictionary in _scatter(medic_gear):
		BaseArmory.add(pool, StringName(String(e.id)), int(e.count), e.get("state", {}))
	BaseArmory.remove(pool, &"iv_18", 3)
	BaseArmory.remove(pool, &"epinephrine", 5)
	var before := _units(pool, {})
	var caps := Restock.fair_caps([medic, medic], pool)
	check(caps[0] == {"iv_18": 2, "epinephrine": 1} and caps[1] == {"iv_18": 1, "epinephrine": 0},
		"what the stash can't fill for both is dealt out one at a time, the rest of the kit uncapped (%s / %s)" % [caps[0], caps[1]])
	var first := Restock.build(medic, pool, caps[0])
	var second := Restock.build(medic, pool, caps[1])
	check(first.missing == {"epinephrine": 2} and first.held_back == {"iv_18": 1} and second.missing == {"iv_18": 2, "epinephrine": 3},
		"the first medic doesn't take it all: both come out short, both listed (%s + %s / %s)" % [first.missing, first.held_back, second.missing])
	var first_text := Restock.report_text("Doc", first)
	check(first_text.contains("Left in the armory for squadmates: IV") and not first_text.contains("Missing from the stash: IV")
		and Restock.short_of(first) == {"iv_18": 1, "epinephrine": 2},
		"the IV kept for the second isn't called missing from the stash, but he's still short of it (%s)" % first_text)
	var after := _units(pool, first.gear)
	var worn := _units([], second.gear)  # the optic on his gun too
	for id: String in worn:
		after[id] = int(after.get(id, 0)) + int(worn[id])
	check(after == before and BaseArmory.count_of(pool, &"iv_18") == 0, "nothing made or lost; no IV left lying in the stash")
	var alone := Restock.fair_caps([medic], _scatter(medic_gear))
	check(alone.size() == 1 and alone[0].is_empty(), "a stash that fills the loadout caps nothing (%s)" % [alone])
	var short := Restock.short_of(second)
	var person := {}
	Roster.record_restock_short(person, short)
	check(Roster.restock_short_of(person) == {"iv_18": 2, "epinephrine": 3} and Restock.list_text(short).contains("x3"),
		"the shortfall is kept on the roster entry (%s)" % Restock.list_text(short))
	Roster.record_restock_short(person, {})
	check(not person.has("restock_short"), "and a full restock clears it")
	# Review of c33712a: a share someone couldn't use goes round again (Restock.top_up), less
	# what's kept for the medics not restocking.
	var loose: Array = []
	BaseArmory.add(loose, &"iv_18", 2)
	var held: Array = [{"iv_18": 1}, {"iv_18": 3}]
	check(Restock.top_up(held, loose, {}) == [{"iv_18": 1}, {"iv_18": 1}] and Restock.top_up(held, loose, {"iv_18": 1}) == [{"iv_18": 1}, {}]
		and Restock.top_up(held, loose, {"iv_18": 2}) == [{}, {}],
		"what lies spare goes round those it was kept from, one at a time, but not a medic's share (%s)" % [Restock.top_up(held, loose, {})])
	_test_restock_keep_short()


## Review of c33712a (S0743): the medic restocked "73 of 74, missing Adenosine", then deployed;
## the loadout written down at deploy had no adenosine, and the next restock said "Nothing
## missing". What a short restock couldn't give stays in the loadout and on the roster
## (Roster.record_loadout, Restock.keep_short) until he has it again.
func _test_restock_keep_short() -> void:
	var medic_gear: Dictionary = Roster.gear_for_kit(Roles.kit(Roles.MEDIC))
	var full := Restock.template_of(medic_gear)
	var inv := Inventory.new()
	inv.net_state = GameState.from_json(medic_gear.duplicate(true))
	var had := inv.count_of(&"adenosine")
	while inv.remove_one(&"adenosine"):
		pass
	var short_gear: Dictionary = Roster.json_safe(inv.net_state.duplicate(true))
	inv.free()
	var person := {"loadout": full.duplicate(true)}
	Roster.record_restock_short(person, {"adenosine": had})
	Roster.record_loadout(person, short_gear)  # he deploys short
	check(had > 0 and Restock.counts(Roster.loadout_of(person)) == Restock.counts(full) and Roster.restock_short_of(person) == {"adenosine": had},
		"deploying short keeps the adenosine in his loadout and on the roster (%d; %s)" % [had, Roster.restock_short_of(person)])
	var res := Restock.build(Roster.loadout_of(person), _scatter(short_gear))
	check(res.missing == {"adenosine": had} and Restock.report_text("Doc", res).contains("Missing from the stash: Adenosine"),
		"so the next restock still names it (%s)" % Restock.report_text("Doc", res))
	var no_pack: Dictionary = short_gear.duplicate(true)
	no_pack.slots["backpack"] = ""
	no_pack.containers["backpack"] = []
	var other := {"loadout": full.duplicate(true)}
	Roster.record_restock_short(other, {"adenosine": had})
	Roster.record_loadout(other, no_pack)
	var put_back := int(Restock.counts(Roster.loadout_of(other)).get("adenosine", 0))
	check(int(Roster.restock_short_of(other).get("adenosine", 0)) == put_back and (Roster.loadout_of(other).containers.get("backpack", []) as Array).is_empty(),
		"nothing goes back into a pack he left behind; what's put back stays noted (%d; %s)" % [put_back, Roster.restock_short_of(other)])
	Roster.record_loadout(person, medic_gear)  # he has it again
	check(Roster.restock_short_of(person).is_empty() and Roster.loadout_of(person) == full, "deploying with it clears the note")


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
	var short := Roster.restock_short_of(Roster.main_character(BaseHub.roster(), BaseHub.player_key(1)))
	check(short == {"helmet": 1}, "and the shortfall stays on the player's roster entry for the squad page (%s)" % [short])
	check(Roster.restock_short_of(BaseHub.member(mid)).is_empty(), "a squadmate restocked in full has none")
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


## The screenshot run S0590's question: with every loose 5.56 magazine taken off the armory
## floor, the player's Restock still came out with six. They came out of a squadmate's carrier
## lying on the floor with its pouches full (the stash's own carriers count as stash: their
## pouches and what's in them are unpacked into the pool). Restock never makes anything: every
## item in the base level (world items, the player, everyone at the muster line), optics on
## guns and what's in pouches and kits included, is counted before and after.
func _test_restock_conservation() -> void:
	print("Restock makes nothing (S2, S0590's six magazines)")
	var base := level as BaseLevel
	if base == null:
		check(false, "at the base for the conservation checks")
		return
	var player: Soldier = level.players.get_node(^"1")
	var muster: Array = []
	for mid: String in Roster.available_ids(BaseHub.roster()):
		if base.muster_soldier(mid) != null:
			muster.append(base.muster_soldier(mid))
	# The player deployed as a rifleman; a squadmate's full kit lies on the floor as it came
	# off him (carrier with pouches and magazines); no loose magazines anywhere.
	player.inventory.net_state = GameState.from_json(Roster.gear_for_kit(Roles.kit(Roles.RIFLEMAN)))
	Roster.record_loadout(Roster.main_character(BaseHub.roster(), BaseHub.player_key(1)), Roster.json_safe(player.inventory.net_state))
	player.inventory.strip()
	var donor: Soldier = muster[0] if not muster.is_empty() else null
	var in_pouches := 0
	if donor:
		donor.inventory.net_state = GameState.from_json(Roster.gear_for_kit(Roles.kit(Roles.RIFLEMAN)))
		for e: Dictionary in donor.inventory.strip():
			in_pouches += int(_deep_units([e]).get("mag_556", 0)) if String(e.id) == "plate_carrier" else 0
			level.server_spawn_dropped(StringName(e.id), int(e.count), BaseLevel.DELIVERY + Vector3(randf_range(-1, 1), 0.3, randf_range(-0.5, 0.5)), e.get("state", {}))
	for n: Node in level.items.get_children():
		if n is WorldItem and (n as WorldItem).item_id == &"mag_556":
			GameState.item_taken((n as WorldItem).uid)
			n.queue_free()
	await _frames(3)
	var loose := level.items.get_children().filter(func(n: Node) -> bool: return n is WorldItem and not n.is_queued_for_deletion() and (n as WorldItem).item_id == &"mag_556")
	var everyone: Array = [player] + muster
	var before := _level_units(everyone)
	check(loose.is_empty() and in_pouches == 6 and int(before.get("mag_556", 0)) >= 6,
		"no loose magazines on the floor; the dropped carrier holds %d in its pouches (%d in the level)" % [in_pouches, int(before.get("mag_556", 0))])
	BaseHub.request("restock")
	await _frames(3)
	var after := _level_units(everyone)
	check(after == before, "the player's Restock makes nothing and loses nothing: every item in the base level, item by item")
	if after != before:
		print("    before %s\n    after  %s" % [before, after])
	check(player.inventory.count_of(&"mag_556") <= int(before.get("mag_556", 0)) and player.inventory.count_of(&"mag_556") == 6,
		"its six magazines are the ones from the carrier's pouches (%d)" % player.inventory.count_of(&"mag_556"))
	BaseHub.request("restock_squad")
	await _frames(3)
	check(_level_units(everyone) == before, "and Restock squad after it makes nothing either")
	await _seconds(BaseHub.STASH_POLL_S + 0.3)
	check(_deep_units(BaseHub.stash()) == _deep_units(base.server_collect_stash()), "the campaign's stash is the floor (no stale copy to draw from)")


## S0743: restock left the medic short silently. Two squadmates at the muster line want the
## medic's kit, the medic picked second; the stash has one IV. "Restock squad" restocks them
## together, medic first: the IV goes to the medic, the other is short of it, and the squad
## page names him and what he's short of.
func _test_restock_medic_first() -> void:
	print("Restock squad shares out what the stash is short of, medics first (S0743)")
	var base := level as BaseLevel
	var mids: Array[String] = []
	for mid: String in Roster.available_ids(BaseHub.roster()):
		if base.muster_soldier(mid) != null:
			mids.append(mid)
	if mids.size() < 2:
		check(false, "two squadmates at the muster line (%d)" % mids.size())
		return
	var a := BaseHub.member(mids[0])
	var b := BaseHub.member(mids[1])
	var kept := [a.get("role"), a.get("loadout"), b.get("role"), b.get("loadout")]
	var medic := Restock.template_of(Roster.gear_for_kit(Roles.kit(Roles.MEDIC)))
	a["role"] = String(Roles.RIFLEMAN)
	b["role"] = String(Roles.MEDIC)
	a["loadout"] = medic.duplicate(true)
	b["loadout"] = medic.duplicate(true)
	for mid in [mids[0], mids[1]]:
		base.muster_soldier(mid).inventory.strip()  # kit gone (left in the field)
	for n: Node in level.items.get_children():
		if n is WorldItem and (n as WorldItem).item_id == &"iv_18":
			GameState.item_taken((n as WorldItem).uid)
			n.queue_free()
	level.server_spawn_dropped(&"iv_18", 1, BaseLevel.DELIVERY + Vector3(0.5, 0.3, 0.0))
	await _frames(3)
	var picked: Array = BaseHub._prep().get("squad", []).duplicate()
	BaseHub._prep()["squad"] = [mids[0], mids[1]]  # the rifleman asked first
	var text := BaseHub.server_restock_squad()
	BaseHub._prep()["squad"] = picked
	var sa := base.muster_soldier(mids[0])
	var sb := base.muster_soldier(mids[1])
	check(sb.inventory.count_of(&"iv_18") == 1 and sa.inventory.count_of(&"iv_18") == 0,
		"the one IV goes to the medic, though he was picked second (%d / %d)" % [sb.inventory.count_of(&"iv_18"), sa.inventory.count_of(&"iv_18")])
	check(int(Roster.restock_short_of(a).get("iv_18", 0)) == 3 and int(Roster.restock_short_of(b).get("iv_18", 0)) == 2,
		"each one's shortfall is on the roster (%s / %s)" % [Roster.restock_short_of(a), Roster.restock_short_of(b)])
	check(text.contains(String(b.callsign)) and text.contains("Missing from the stash") and text.contains("IV"), "the host is told who is short of what")
	await _frames(3)  # the view goes out
	var ui: BaseUI = BaseHub._ui
	if ui:
		ui.open("squad")
		await _frames(2)
		var lines: Array = ui._pages["squad"].find_children("*", "Label", true, false).filter(func(l: Label) -> bool:
			return not l.is_queued_for_deletion() and l.text.contains(String(a.callsign) + " is short after restock") and l.text.contains("IV"))
		check(lines.size() == 1, "the squad page names him and what he's short of (%s)" % (lines[0].text if not lines.is_empty() else "no line"))
		ui.close()
	for i in 2:
		var m: Dictionary = [a, b][i]
		m["role"] = kept[i * 2]
		if kept[i * 2 + 1] == null:
			m.erase("loadout")
		else:
			m["loadout"] = kept[i * 2 + 1]
		Roster.record_restock_short(m, {})


## Review of c33712a: the medic's IFAKs, drawn with no room on him (his pockets full), went
## back to the stash while the squadmate capped below him was told he was short. Restock squad
## hands what's left over round again: the squadmate gets both.
func _test_restock_top_up() -> void:
	print("Restock squad hands round what someone had no room for (review of c33712a)")
	var base := level as BaseLevel
	var mids: Array[String] = []
	for mid: String in Roster.available_ids(BaseHub.roster()):
		if base.muster_soldier(mid) != null:
			mids.append(mid)
	if mids.size() < 2:
		check(false, "two squadmates at the muster line (%d)" % mids.size())
		return
	var a := BaseHub.member(mids[0])
	var b := BaseHub.member(mids[1])
	var kept := [a.get("role"), a.get("loadout"), b.get("role"), b.get("loadout")]
	a["role"] = String(Roles.RIFLEMAN)
	b["role"] = String(Roles.MEDIC)
	a["loadout"] = {"slots": {}, "optics": {}, "molle": {}, "containers": {"pockets": [{"id": "ifak", "count": 2}]}}
	b["loadout"] = {"slots": {}, "optics": {}, "molle": {}, "containers": {"pockets": [{"id": "hypothermia_blanket", "count": 3}, {"id": "ifak", "count": 2}]}}
	for mid in [mids[0], mids[1]]:
		base.muster_soldier(mid).inventory.strip()
	for n: Node in level.items.get_children():
		if n is WorldItem and (n as WorldItem).item_id in [&"ifak", &"hypothermia_blanket"]:
			GameState.item_taken((n as WorldItem).uid)
			n.queue_free()
	level.server_spawn_dropped(&"ifak", 2, BaseLevel.DELIVERY + Vector3(0.5, 0.3, 0.0))
	level.server_spawn_dropped(&"hypothermia_blanket", 3, BaseLevel.DELIVERY + Vector3(-0.5, 0.3, 0.0))
	await _frames(3)
	var picked: Array = BaseHub._prep().get("squad", []).duplicate()
	BaseHub._prep()["squad"] = [mids[0], mids[1]]
	var text := BaseHub.server_restock_squad()
	BaseHub._prep()["squad"] = picked
	var sa := base.muster_soldier(mids[0])
	var sb := base.muster_soldier(mids[1])
	check(sa.inventory.count_of(&"ifak") == 2 and sb.inventory.count_of(&"ifak") == 0 and Roster.restock_short_of(a).is_empty(),
		"the squadmate gets both IFAKs, the medic had no room for his (%d / %d; %s) [%s]" % [sa.inventory.count_of(&"ifak"), sb.inventory.count_of(&"ifak"), Roster.restock_short_of(a), text])
	check(int(Roster.restock_short_of(b).get("ifak", 0)) == 2 and text.contains("No room for: IFAK x2"), "the medic is short of them for want of room, and told so")
	for i in 2:
		var m: Dictionary = [a, b][i]
		m["role"] = kept[i * 2]
		if kept[i * 2 + 1] == null:
			m.erase("loadout")
		else:
			m["loadout"] = kept[i * 2 + 1]
		Roster.record_restock_short(m, {})


## Review of c33712a (player restocks first-come): the host player, a rifleman whose loadout
## names IVs, restocks while the squad's medic at the muster line still needs his; the stash
## has one IV. The player leaves it for the medic and is told it's in the armory for a
## squadmate; Restock squad then gives it to the medic.
func _test_restock_player_leaves_medic() -> void:
	print("A player's Restock leaves a medic's share (review of c33712a)")
	var base := level as BaseLevel
	var mids: Array[String] = []
	for mid: String in Roster.available_ids(BaseHub.roster()):
		if base.muster_soldier(mid) != null:
			mids.append(mid)
	if mids.is_empty():
		check(false, "a squadmate at the muster line")
		return
	var b := BaseHub.member(mids[0])
	var main := Roster.main_character(BaseHub.roster(), BaseHub.player_key(1))
	var player: Soldier = level.players.get_node(^"1")
	var kept := [b.get("role"), b.get("loadout"), main.get("role"), main.get("loadout"), player.inventory.net_state.duplicate(true)]
	var ivs := {"slots": {}, "optics": {}, "molle": {}, "containers": {"pockets": [{"id": "iv_18", "count": 2}]}}
	b["role"] = String(Roles.MEDIC)
	b["loadout"] = ivs.duplicate(true)
	main["role"] = String(Roles.RIFLEMAN)
	main["loadout"] = ivs.duplicate(true)
	base.muster_soldier(mids[0]).inventory.strip()
	player.inventory.strip()
	for n: Node in level.items.get_children():
		if n is WorldItem and (n as WorldItem).item_id == &"iv_18":
			GameState.item_taken((n as WorldItem).uid)
			n.queue_free()
	level.server_spawn_dropped(&"iv_18", 1, BaseLevel.DELIVERY + Vector3(0.5, 0.3, 0.0))
	await _frames(3)
	var picked: Array = BaseHub._prep().get("squad", []).duplicate()
	BaseHub._prep()["squad"] = [mids[0]]
	var text := BaseHub.server_restock_player(1)
	check(player.inventory.count_of(&"iv_18") == 0 and text.contains("Left in the armory for squadmates: IV"),
		"the player leaves the one IV for the medic and is told where it is (%s)" % text)
	BaseHub.server_restock_squad()
	BaseHub._prep()["squad"] = picked
	check(base.muster_soldier(mids[0]).inventory.count_of(&"iv_18") == 1, "and Restock squad gives it to the medic")
	b["role"] = kept[0]
	if kept[1] == null:
		b.erase("loadout")
	else:
		b["loadout"] = kept[1]
	main["role"] = kept[2]
	if kept[3] == null:
		main.erase("loadout")
	else:
		main["loadout"] = kept[3]
	player.inventory.net_state = kept[4]
	Roster.record_restock_short(b, {})
	Roster.record_restock_short(main, {})


## Every unit in the base level: its world items and `soldiers`' kit, with what's on and in
## them (carriers' pouches, pouch and pack contents, kits) and the optic on each gun.
func _level_units(soldiers: Array) -> Dictionary:
	var entries: Array = []
	for n: Node in level.items.get_children():
		var w := n as WorldItem
		if w and not w.is_queued_for_deletion():
			entries.append({"id": w.item_id, "count": w.count, "state": w.state})
	for s: Soldier in soldiers:
		if is_instance_valid(s):
			var copy := Inventory.new()
			copy.net_state = s.inventory.net_state
			entries.append_array(copy.strip())
			copy.free()
	return _deep_units(entries)


## Units of each item in `entries` ({"id", "count", "state"?}), into their states (attachments,
## held contents, a kit's contents), and a rail gun's optic (its own one when its state names none).
func _deep_units(entries: Array, out := {}) -> Dictionary:
	for e: Dictionary in entries:
		var id := String(e.id)
		var n := int(e.get("count", 1))
		var state: Dictionary = e.get("state", {})
		var item := ItemDB.get_item(StringName(id))
		out[id] = int(out.get(id, 0)) + n
		if item and Optics.has_rail(item) and Optics.mounted_id(item, state) != &"":
			out[String(Optics.mounted_id(item, state))] = int(out.get(String(Optics.mounted_id(item, state)), 0)) + n
		var inner: Array = []
		var molle: Dictionary = state.get("molle", {})
		for point: Variant in molle:
			var att: Dictionary = molle[point]
			inner.append({"id": att.id, "count": 1, "state": att.get("state", {})})
			inner.append_array(att.get("held", []))
		inner.append_array(state.get("held", []))
		for i in n:
			_deep_units(inner, out)
	return out


## Captain, 2026-10-14: "2"s are not an option for names: a taken callsign gets another one from
## the list, never a number, and an old save's "Saint 2" is renamed on load.
func _test_callsigns() -> void:
	print("Callsigns: never numbered")
	var data := {"members": {}}
	var got: Array[String] = []
	for i in Roster.CALLSIGNS.size() + 5:
		var cs := Roster.unique_callsign(data, "Saint")
		got.append(cs)
		data.members["m%d" % i] = {"callsign": cs}
	var numbered := got.filter(func(c: String) -> bool: return Roster._numbered(c) or c.is_valid_int())
	var unique := {}
	for c in got:
		unique[c] = true
	check(numbered.is_empty() and unique.size() == got.size(), "%d hires asking for \"Saint\": all different, none numbered (%s ... %s)" % [got.size(), got[1], got[got.size() - 1]])
	var old := {"members": {"a": {"callsign": "Saint"}, "b": {"callsign": "Saint 2"}, "c": {"callsign": "Gunny 2"}}}
	var renamed := Roster.rename_numbered_callsigns(old)
	var names: Array = old.members.values().map(func(m: Dictionary) -> String: return String(m.callsign))
	check(renamed == 2 and not names.any(func(c: String) -> bool: return Roster._numbered(c)) and names.has("Saint"),
		"an old save's \"Saint 2\" and \"Gunny 2\" are renamed (%s)" % [names])

