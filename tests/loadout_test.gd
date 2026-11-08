extends Node
## Headless checks of the loadout menu at the FOB (Captain, 2026-10-14: "we need a menu for
## equipping yourself better and your squadmates how you want to as well"; docs/loadout_menu.md):
##   <voxel godot exe> --headless --path . res://tests/loadout_test.tscn
## The rules first (every template edit rebuilt from a pool conserves it unit by unit; a role
## kit takes only what the pool has and names the rest), then a hub session: changes asked
## through BaseHub.request conserve the armory's items and the kits together, a saved standing
## loadout is what Restock refills to, a role preset with a short stash says what's missing, a
## player can't change another player's kit, the screen fits every window size and UI scale,
## and a client's requests go through the host (a second process joins the hub). Buying from
## the pickers (feat/loadout-buy): what the stash lacks is offered at its price, refused with
## nothing changed when cash is short, else bought and worn; the client buys from its own picker
## through the host, sees the host's purchase on joining, and a save and reload keeps both.
##
## The client is this scene again with `-- --join 127.0.0.1 --log <path>`; it writes its checks
## to the log the host prints. Exits with the number of failures.

const SEED := 5151
## Items the test stash holds besides the starting stash.
const EXTRA_STASH := [["smoke_grenade", 4], ["m110", 1], ["mag_762", 6], ["optic_holo", 2], ["helmet_heavy", 1], ["mag_9mm", 4], ["m17", 1],
	["suppressor_rifle", 1], ["grip_vertical", 1], ["nvg_gen2", 1], ["pouch_mag_double", 2], ["hk416", 1], ["svd", 1], ["optic_t2", 2]]
const CLIENT_DONE := "CLIENT LOADOUT CHECKS DONE"
const CLIENT_KEY := "loadout_client"
const FIT_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440),
	Vector2i(3440, 1440), Vector2i(3840, 2160)]
const FIT_SCALES: Array[float] = [0.75, 1.0, 1.2, 1.5]

var failures := 0
var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
var level: CompoundLevel
var _log: FileAccess
var _notes: Array = []
## The helmet the client bought from its picker (the host reads it off the client's body).
var _client_bought := ""
## This run's own settings.cfg and loadout_editor.cfg (never the player's).
var _settings_path := ""
var _editor_path := ""
## Economy's notices (a picker purchase answers in one note: BaseHub's, none of these).
var _econ_notes: Array = []


## The tree this test started in: a client's scene can be taken out of it near the end (the
## client's level handling), and the waits and the quit still need it (CI: SCRIPT ERRORs, and a
## null tree at the client's quit, after "LOADOUT TEST PASSED").
var _tree: SceneTree


func _ready() -> void:
	_tree = get_tree()
	GameState.zone_id = "test_loadout" + tag
	Campaign.campaign_id = "test_loadout" + tag  # never touch a real save
	_tree.create_timer(420.0).timeout.connect(func() -> void:
		_say("LOADOUT TEST FAILED (timed out)")
		_tree.quit(99))
	# Never the player's own settings.cfg (the buy confirm's "Don't ask again") or
	# user://loadout_editor.cfg (F-406): files of this run's own, fresh, removed at the end.
	var side := "_client" if "--join" in OS.get_cmdline_user_args() else ""
	_settings_path = OS.get_user_data_dir().path_join("test_loadout_settings%s%s.cfg" % [tag, side])
	_editor_path = OS.get_user_data_dir().path_join("test_loadout_editor%s%s.cfg" % [tag, side])
	for path: String in [_settings_path, _editor_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	GameSettings.use_file(_settings_path)
	LoadoutEditor.use_file(_editor_path)
	Economy.notice.connect(func(t: String) -> void: _econ_notes.append(t))
	if "--join" in OS.get_cmdline_user_args():
		await _run_client()
		return
	GameState.delete_save()
	BaseHub.delete_test_campaign_files()
	_test_rules()
	await _test_session()
	GameState.zone_id = "test_loadout" + tag
	GameState.delete_save()
	BaseHub.delete_test_campaign_files()
	_own_files_off()
	print("LOADOUT TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


## Back to the player's own settings files, and this run's removed.
func _own_files_off() -> void:
	GameSettings.use_file("")
	LoadoutEditor.use_file("")
	for path: String in [_settings_path, _editor_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


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


# --- The rules ---------------------------------------------------------------------------------

func _stash() -> Array:
	var stash: Array = []
	for pair: Array in BaseHub.STARTING_STASH + EXTRA_STASH:
		BaseArmory.add(stash, StringName(pair[0]), int(pair[1]))
	return stash


func _test_rules() -> void:
	print("Template edits rebuilt from the stash make nothing and lose nothing")
	var rifleman := Roster.gear_for_kit(Roles.kit(Roles.RIFLEMAN))
	var t := Loadouts.template_of(rifleman)
	var edits := {
		"primary to the M110": Loadouts.set_slot(t, &"primary", "m110"),
		"holo on the primary": Loadouts.set_optic(t, &"primary", "optic_holo"),
		"irons": Loadouts.set_optic(t, &"primary", ""),
		"heavy helmet": Loadouts.set_slot(t, &"helmet", "helmet_heavy"),
		"carrier off": Loadouts.set_slot(t, &"vest", ""),
		"pack off": Loadouts.set_slot(t, &"backpack", ""),
		"+5 smoke": Loadouts.add_units(t, "smoke_grenade", 5),
		"-2 mags": Loadouts.remove_units(t, "mag_556", 2).template,
		"fill ammo (sidearm too)": Loadouts.fill_ammo(Loadouts.set_slot(t, &"sidearm", "m17"), Roles.RIFLEMAN),
		"medic kit": Loadouts.medic_kit(t),
		"medic role kit": Loadouts.role_template(Roles.MEDIC),
	}
	for what: String in edits:
		var pool := _stash()
		var before := Loadouts.units(pool, [rifleman])
		var res: Dictionary = Loadouts.rebuild([{"gear": rifleman, "template": edits[what]}], pool)[0]
		var after := Loadouts.units(pool, [res.gear])
		check(after == before, "%s: the stash and the kit hold the same units after (%s)" % [what, Loadouts.short_text(res) if Loadouts.short_text(res) != "" else "nothing short"])
		if after != before:
			print("    before %s\n    after  %s" % [before, after])
	# What each edit is for.
	var pool := _stash()
	var res: Dictionary = Loadouts.rebuild([{"gear": rifleman, "template": edits["primary to the M110"]}], pool)[0]
	check(String(res.gear.slots.get("primary", "")) == "m110" and BaseArmory.count_of(pool, &"m4a1") == 3, "the M110 is worn, the M4 back in the stash")
	pool = _stash()
	res = Loadouts.rebuild([{"gear": rifleman, "template": edits["holo on the primary"]}], pool)[0]
	var gun := ItemDB.get_item(&"m4a1")
	check(Optics.mounted_id(gun, res.gear.slot_state.get("primary", {})) == &"optic_holo" and BaseArmory.count_of(pool, &"optic_holo") == 1,
		"the holo goes on the M4 (one left in the stash)")
	var mags := int(Roster.gear_counts(rifleman).get("mag_556", 0))
	pool = _stash()
	res = Loadouts.rebuild([{"gear": rifleman, "template": edits["-2 mags"]}], pool)[0]
	check(int(Roster.gear_counts(res.gear).get("mag_556", 0)) == mags - 2, "-2 mags: %d of %d left" % [int(Roster.gear_counts(res.gear).get("mag_556", 0)), mags])
	pool = _stash()
	res = Loadouts.rebuild([{"gear": rifleman, "template": edits["fill ammo (sidearm too)"]}], pool)[0]
	check(int(Roster.gear_counts(res.gear).get("mag_9mm", 0)) == Loadouts.FILL_MAGS[&"sidearm"] and int(Roster.gear_counts(res.gear).get("mag_556", 0)) >= mags,
		"fill ammo gives the sidearm its magazines (%d)" % int(Roster.gear_counts(res.gear).get("mag_9mm", 0)))
	# Give: one person's kit less, another's more, one pool.
	var other := Roster.gear_for_kit(Roles.kit(Roles.GRENADIER))
	pool = _stash()
	var before := Loadouts.units(pool, [rifleman, other])
	var took := Loadouts.remove_units(Loadouts.template_of(rifleman), "smoke_grenade", 1)
	var both := Loadouts.rebuild([{"gear": rifleman, "template": took.template},
		{"gear": other, "template": Loadouts.add_units(Loadouts.template_of(other), "smoke_grenade", 1)}], pool)
	check(Loadouts.units(pool, [both[0].gear, both[1].gear]) == before
		and int(Roster.gear_counts(both[1].gear).get("smoke_grenade", 0)) == int(Roster.gear_counts(other).get("smoke_grenade", 0)) + 1,
		"giving a smoke to a squadmate conserves the units, and he has one more")
	print("A role preset takes only what the stash has")
	pool = _stash()
	for id: StringName in [&"iv_18", &"adenosine"]:
		BaseArmory.remove(pool, id, 99)
	before = Loadouts.units(pool, [{}])
	res = Loadouts.rebuild([{"gear": {}, "template": Loadouts.role_template(Roles.MEDIC)}], pool)[0]
	check(Loadouts.units(pool, [res.gear]) == before, "nothing made: the stash and the new kit hold what the stash held")
	check(int(Roster.gear_counts(res.gear).get("iv_18", 0)) == 0 and res.missing.has("iv_18") and res.missing.has("adenosine")
		and Loadouts.short_text(res).begins_with("Missing from the stash:") and Loadouts.short_text(res).contains("Adenosine"),
		"and it names what's missing (%s)" % Loadouts.short_text(res))
	check(String(res.gear.slots.get("vest", "")) == "plate_carrier" and int(Roster.gear_counts(res.gear).get("tourniquet", 0)) > 0,
		"while the rest of the medic kit is drawn")
	check(Loadouts.group_of(ItemDB.get_item(&"frag_grenade")) == "grenades" and Loadouts.group_of(ItemDB.get_item(&"mag_556")) == "ammo"
		and Loadouts.group_of(ItemDB.get_item(&"aid_bag")) == "pouches" and Loadouts.fits_slot(ItemDB.get_item(&"plate_side"), &"plate_left")
		and not Loadouts.fits_slot(ItemDB.get_item(&"plate_side"), &"plate_front"), "items are grouped and slotted for the paper doll")
	_test_kit_rules(rifleman)
	check(not BaseHub.may_change_loadout(2, {"peer": 1}) and BaseHub.may_change_loadout(2, {"peer": 2}) and BaseHub.may_change_loadout(2, {"peer": 0}),
		"a player may change their own kit and any squadmate's, never another player's")


## claude/loadout-3d: the 3D editor's mounts (muzzle, rails, the helmet's NVG) and MOLLE points
## in templates, saved kits (KitLibrary) and what a set of them is short of.
func _test_kit_rules(rifleman: Dictionary) -> void:
	print("Mounts and points in templates (the 3D editor)")
	var t := Loadouts.template_of(rifleman)
	var gun := ItemDB.get_item(StringName(String(t.slots.get("primary", "m4a1"))))
	var muzzled := Loadouts.set_mount(t, &"primary", "muzzle", "suppressor_rifle")
	muzzled = Loadouts.set_mount(muzzled, &"primary", "underbarrel", "grip_vertical")
	muzzled = Loadouts.set_mount(Loadouts.set_slot(muzzled, &"helmet", "helmet"), &"helmet", "nvg", "nvg_gen2")
	var pool := _stash()
	var before := Loadouts.units(pool, [rifleman])
	var res: Dictionary = Loadouts.rebuild([{"gear": rifleman, "template": muzzled}], pool)[0]
	var state: Dictionary = res.gear.slot_state.get("primary", {})
	check(Loadouts.units(pool, [res.gear]) == before, "a suppressor, a grip and an NVG fitted: nothing made or lost")
	check(String(Suppressors.mounted_id(gun, state)) == "suppressor_rifle" and GearMounts.on(gun, state, "underbarrel") == "grip_vertical"
		and GearMounts.on(ItemDB.get_item(&"helmet"), res.gear.slot_state.get("helmet", {}), "nvg") == "nvg_gen2",
		"the gun has its suppressor and grip, the helmet its NVG (%s)" % [GearMounts.of(gun, state)])
	check(Restock.template_of(res.gear).get("mounts", {}).get("primary", {}) == {"muzzle": "suppressor_rifle", "underbarrel": "grip_vertical"},
		"and the template of what he wears records them (Restock refills them)")
	var bare := Loadouts.set_mount(Restock.template_of(res.gear), &"primary", "muzzle", "")
	var pool2 := pool.duplicate(true)
	var res2: Dictionary = Loadouts.rebuild([{"gear": res.gear, "template": bare}], pool2)[0]
	check(String(Suppressors.mounted_id(gun, res2.gear.slot_state.get("primary", {}))) == "" and int(Loadouts.units(pool2, []).get("suppressor_rifle", 0)) == 1
		and Loadouts.units(pool2, [res2.gear]) == before, "taking the suppressor off leaves it in the stash")
	# F-420: a helmet swapped for another takes its NVG along when it fits (set_slot keeps the
	# mount); before, the NVG stayed on the old helmet in the stash and was listed missing.
	var heavy := ItemDB.get_item(&"helmet_heavy")
	var pool3 := pool.duplicate(true)
	var with_nvg: Dictionary = res.gear
	var before3 := Loadouts.units(pool3, [with_nvg])
	var swap := Loadouts.set_slot(Restock.template_of(with_nvg), &"helmet", "helmet_heavy")
	var res3: Dictionary = Loadouts.rebuild([{"gear": with_nvg, "template": swap}], pool3)[0]
	var old_bare := pool3.all(func(e: Dictionary) -> bool:
		return String(e.id) != "helmet" or GearMounts.on(ItemDB.get_item(&"helmet"), e.get("state", {}), "nvg") == "")
	check(String(res3.gear.slots.get("helmet", "")) == "helmet_heavy" and GearMounts.on(heavy, res3.gear.slot_state.get("helmet", {}), "nvg") == "nvg_gen2"
		and res3.missing.is_empty() and old_bare and Loadouts.units(pool3, [res3.gear]) == before3,
		"swapping the helmet moves its NVG onto the new one: nothing missing, the old helmet bare in the stash (%s, missing %s)" % [
			GearMounts.of(heavy, res3.gear.slot_state.get("helmet", {})), res3.missing])
	_test_gun_swap_rules(rifleman)
	_test_unfit_mounts(rifleman)
	var points: Array = ItemDB.get_item(StringName(String(t.slots.vest))).stats.get("molle", [])
	var free := ""
	for p: Dictionary in points:
		if not t.molle.has(String(p.id)) and "mag" in Inventory.point_types(p):
			free = String(p.id)
	if free != "":
		pool = _stash()
		res = Loadouts.rebuild([{"gear": rifleman, "template": Loadouts.set_point(t, free, "pouch_mag_double")}], pool)[0]
		check(Loadouts.units(pool, [res.gear]) == before and res.missing.is_empty(), "a mag pouch on free point %s: drawn from the stash, nothing short" % free)
	print("Saved kits")
	var data := {"members": {"a": {"callsign": "A", "role": "medic"}, "b": {"callsign": "B", "role": "rifleman"}, "c": {"callsign": "C", "role": "rifleman"},
		"d": {"callsign": "D", "role": "autorifleman"}, "e": {"callsign": "E", "role": "rifleman"}, "h1": {"callsign": "H1", "role": "rifleman"}},
		"detachments": {"d02": {"id": "d02", "callsign": "Hawk 2", "members": ["h1"]}}}
	check(KitLibrary.save(data, "  Assault kit  ", muzzled, "test") == "" and KitLibrary.names(data) == ["Assault kit"],
		"a kit saves under its cleaned name (%s)" % [KitLibrary.names(data)])
	check(KitLibrary.save(data, "", muzzled, "test") != "" and KitLibrary.save(data, "Empty", {}, "test") != "", "no name or an empty kit: refused")
	var sent := muzzled.duplicate(true)
	sent.slots["helmet"] = "m4a1"  # a gun on the head
	sent.slots["primary"] = "no_such_item"
	sent["junk"] = 1
	var clean := KitLibrary.clean_template(sent)
	check(not clean.slots.has("helmet") and not clean.slots.has("primary") and not clean.has("junk") and clean.slots.get("vest", "") == t.slots.vest,
		"a client's template is cleaned: unknown items and wrong slots dropped, the rest kept")
	var picked := ["a", "b", "c", "d", "e"]
	check(KitLibrary.resolve(data, picked, ["team:1"]) == ["a", "b", "c", "d"] and KitLibrary.resolve(data, picked, ["team:2"]) == ["e"],
		"fire teams are the picked squad in fours")
	check(KitLibrary.resolve(data, picked, ["role:rifleman"]) == ["b", "c", "e"] and KitLibrary.resolve(data, picked, ["hc:d02"]) == ["h1"]
		and KitLibrary.resolve(data, picked, ["squad", "a", "player:x"]) == ["a", "b", "c", "d", "e", "player:x"],
		"by role, a high command squad, the squad (no one twice)")
	pool = _stash()
	var one := KitLibrary.shortfall([{"gear": {}, "template": muzzled}], pool)
	var three := KitLibrary.shortfall([{"gear": {}, "template": muzzled}, {"gear": {}, "template": muzzled}, {"gear": {}, "template": muzzled}], pool)
	check(int(three.units) > int(one.units) and int(three.missing.get("suppressor_rifle", 0)) == 3 - 1 and three.each.size() == 3
		and int(three.cost) == int(BaseHub.missing_cost(three.missing).cost) and Loadouts.units(pool, []) == Loadouts.units(_stash(), []),
		"buy missing totals over everyone: 3 kits lack 2 suppressors with 1 in the stash ($%d for %d items), the stash untouched" % [int(three.cost), int(three.units)])
	var st := KitLibrary.stats_of(rifleman)
	check(float(st.kg) > 5.0 and float(st.litres) > 0.0 and not st.protection.is_empty() and String(st.protection[0][2]) != "" and not st.ammo.is_empty(),
		"the stats panel's numbers: %.1f kg, %.1f L, %s, %s" % [float(st.kg), float(st.litres), st.protection, st.ammo])


# --- At the hub --------------------------------------------------------------------------------

func _test_session() -> void:
	print("The loadout menu at the hub")
	CompoundLevel.spawn_ai = true
	Roles.local_choice = Roles.TEAM_LEADER
	BaseHub.local_profile = "loadout_host"
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
	var base := level as BaseLevel
	check(base != null, "the campaign starts at the base hub")
	if base == null:
		return
	var up := await _wait_until(func() -> bool: return ids.all(func(mid: String) -> bool: return base.muster_soldier(mid) != null), 30.0)
	check(up, "the squad stands at the muster line")
	BaseHub.note.connect(func(t: String) -> void: _notes.append(t))
	var mid: String = ids[0]
	var s := base.muster_soldier(mid)
	var me := "player:" + BaseHub.player_key(1)
	# Changes through the request path conserve the hub.
	var steps := [
		[mid, "slot", {"slot": "helmet", "id": "helmet_heavy"}],
		[mid, "slot", {"slot": "primary", "id": "m110"}],
		[mid, "optic", {"slot": "primary", "id": "optic_holo"}],
		[mid, "fill_ammo", {}],
		[mid, "add", {"id": "smoke_grenade", "count": 2}],
		[mid, "remove", {"id": "smoke_grenade", "count": 1}],
		[mid, "give", {"id": "smoke_grenade", "count": 1, "to": me}],
		[me, "medic_kit", {}],
		[me, "copy_kit", {"from": mid}],
		[mid, "slot", {"slot": "backpack", "id": ""}],
	]
	for step: Array in steps:
		var before := _hub_units()
		_notes.clear()
		BaseHub.request("loadout", step)
		await _frames(3)
		var after := _hub_units()
		check(after == before and not _notes.is_empty(), "%s %s: the armory's items and the kits hold the same units (%s)" % [step[1], step[2], _notes])
		if after != before:
			print("    before %s\n    after  %s" % [before, after])
	var gear: Dictionary = Roster.json_safe(s.inventory.net_state)
	check(String(gear.slots.get("helmet", "")) == "helmet_heavy" and String(gear.slots.get("primary", "")) == "m110" and String(gear.slots.get("backpack", "")) == "",
		"%s wears the heavy helmet and the M110, pack off (%s)" % [s.name, gear.slots])
	check(int(Roster.gear_counts(gear).get("mag_762", 0)) >= 5, "fill ammo gave the M110 its magazines (%d)" % int(Roster.gear_counts(gear).get("mag_762", 0)))
	check(Roster.gear_counts(BaseHub.member(mid).gear) == Roster.gear_counts(gear), "and the roster has his gear (the view shows it)")
	# Save as standing, then strip him to the floor: Restock refills to the saved kit.
	print("A saved standing loadout is what Restock refills to")
	BaseHub.request("loadout", [mid, "save", {}])
	await _frames(2)
	var saved: Dictionary = Roster.json_safe(Roster.loadout_of(BaseHub.member(mid)))
	check(saved == Restock.template_of(gear), "Save as standing writes down the kit he wears (%s)" % [_notes.back() if not _notes.is_empty() else ""])
	for e: Dictionary in s.inventory.strip():
		level.server_spawn_dropped(StringName(e.id), int(e.count), BaseLevel.DELIVERY + Vector3(randf_range(-1, 1), 0.3, randf_range(-0.5, 0.5)), e.get("state", {}))
	await _frames(3)
	var before_restock := _hub_units()
	BaseHub.request("loadout", [mid, "restock", {}])
	await _frames(3)
	check(Restock.template_of(Roster.json_safe(s.inventory.net_state)) == saved, "Restock to standing rebuilds exactly the saved kit")
	check(_hub_units() == before_restock, "out of the stash: nothing made or lost")
	# Standing = role kit; copy standing to the squad.
	BaseHub.request("loadout", [mid, "standing_role", {"role": "grenadier"}])
	BaseHub.request("loadout", [mid, "copy_standing", {"to": [ids[1], me]}])
	await _frames(2)
	check(Restock.counts(Roster.loadout_of(BaseHub.member(ids[1]))) == Restock.counts(Loadouts.role_template(Roles.GRENADIER)),
		"Standing = role kit, then Copy standing gives a squadmate the same standing loadout")
	# A role preset with the stash out of IVs: within stock, and it says so. (R0976: a medic's own
	# IVs were locked in his carrier when the rebuild drew another; Loadouts.rebuild unpacks.)
	print("A role preset respects what the stash has")
	var lvl_before := _hub_units()
	var ivs := int(lvl_before.get("iv_18", 0))
	for n: Node in level.items.get_children():
		if n is WorldItem and (n as WorldItem).item_id == &"iv_18":
			GameState.item_taken((n as WorldItem).uid)
			n.queue_free()
	await _frames(2)
	var who := String(ids[1])
	for m: String in ids:  # a squadmate who isn't a medic: his own kit has no IVs to put back
		if StringName(BaseHub.member(m).get("role", "")) != Roles.MEDIC and m != mid:
			who = m
	var s2 := base.muster_soldier(who)
	var had := int(Roster.gear_counts(Roster.json_safe(s2.inventory.net_state)).get("iv_18", 0))
	var stocked := _hub_units()
	_notes.clear()
	BaseHub.request("loadout", [who, "role_kit", {"role": "medic"}])
	await _frames(3)
	var got := int(Roster.gear_counts(Roster.json_safe(s2.inventory.net_state)).get("iv_18", 0))
	check(_hub_units() == stocked, "the medic kit came out of the stash: nothing made")
	check(got <= int(stocked.get("iv_18", 0)) and got == had and not _notes.is_empty() and String(_notes.back()).contains("Missing from the stash: ")
		and String(_notes.back()).contains("IV"), "with the stash's IVs gone (%d before), only what was there; the note says what's missing (%s)" % [ivs, _notes])
	# Buying what the edit is short of: the IVs the stash ran out of, at the shop's price.
	print("Buy missing")
	var miss: Dictionary = BaseHub.member(who).get("edit_missing", {})
	check(miss.has("iv_18"), "the short medic kit is written on the roster entry (%s)" % [miss])
	var cost := int(BaseHub.missing_cost(miss).cost)
	Economy.add_cash(-Economy.cash(), "test: broke")
	Economy.add_cash(cost - 1, "test: a dollar short")
	_notes.clear()
	BaseHub.request("loadout", [who, "buy_missing", {}])
	await _frames(3)
	check(not _notes.is_empty() and String(_notes.back()).contains("Not enough cash") and Economy.cash() == cost - 1,
		"a dollar short: refused, nothing spent (%s)" % [_notes])
	Economy.add_cash(1, "test: enough")
	BaseHub.request("loadout", [who, "buy_missing", {}])
	await _frames(3)
	var bought := int(Roster.gear_counts(Roster.json_safe(s2.inventory.net_state)).get("iv_18", 0))
	check(bought >= 3 and Economy.cash() < cost and not BaseHub.member(who).has("edit_missing"),
		"buying fills the shortfall (%d IVs on him) and takes the money (%d left of %d)" % [bought, Economy.cash(), cost])
	await _test_kits_at_hub(ids, me)
	await _test_3d(me)
	var bought_helmet: String = await _test_picker_buy(String(ids[0]))
	# The host can't change another player's kit (a client is peer 2 here).
	check(BaseHub.server_loadout(2, me, "add", {"id": "smoke_grenade"}).contains("their own kit"), "a client's request on the host's kit is refused")
	_test_gun_swap(ids)
	await _test_fit(ids)
	await _test_client(ids, bought_helmet)
	# Save and load keep what the pickers bought: the squadmate's helmet, the client's, the cash.
	print("A picker purchase survives a save and reload")
	var cash := Economy.cash()
	var was_saved := BaseHub.server_save()
	Campaign.load_campaign()
	var helmet_after := String(BaseHub.member(String(ids[0])).get("gear", {}).get("slots", {}).get("helmet", ""))
	check(was_saved and bought_helmet != "" and helmet_after == bought_helmet and Economy.cash() == cash,
		"after a save and reload %s still wears the bought %s and the cash is $%d (%s, $%d)" % [BaseHub.member(String(ids[0])).get("callsign", "?"), bought_helmet, cash, helmet_after, Economy.cash()])
	var client_after := String(BaseHub.roster().get("players", {}).get(CLIENT_KEY, {}).get("gear", {}).get("slots", {}).get("helmet", ""))
	check(client_after != "" and client_after == _client_bought, "and the client's bought helmet is on its record (%s, bought %s)" % [client_after, _client_bought])


## The host's swap of a squadmate's gun (F-421, the "slot" op): his M4 with a T-2 red dot to an
## HK416 takes the dot along; to an SVD the SVD keeps its own scope and the T-2 goes to the stash
## loose; nothing is listed missing, made or lost. And the "point" op refuses a point he hasn't got
## or a pouch that doesn't fit it (review of 4bcfe79f).
func _test_gun_swap(ids: Array) -> void:
	print("The host swaps a squadmate's gun, and its optic (F-421)")
	var base := level as BaseLevel
	var who := ""
	for m: String in ids:
		var b := base.muster_soldier(m)
		if who == "" and m != String(ids[2]) and b and String(Roster.json_safe(b.inventory.net_state).slots.get("primary", "")) == "m4a1":
			who = m
	if who == "":
		who = String(ids[1])
		BaseHub.server_loadout(1, who, "slot", {"slot": "primary", "id": "m4a1"})
	var s := base.muster_soldier(who)
	var primary := func() -> String:
		var g: Dictionary = Roster.json_safe(s.inventory.net_state)
		var id := String(g.slots.get("primary", ""))
		return "%s+%s" % [id, Optics.mounted_id(ItemDB.get_item(StringName(id)), g.get("slot_state", {}).get("primary", {}))] if id != "" else ""
	var loose := func() -> int:
		return base.server_collect_stash().filter(func(e: Dictionary) -> bool: return String(e.id) == "optic_t2").reduce(func(n: int, e: Dictionary) -> int: return n + int(e.count), 0)
	var said := BaseHub.server_loadout(1, who, "optic", {"slot": "primary", "id": "optic_t2"})
	check(primary.call() == "m4a1+optic_t2", "%s's M4 gets a T-2 red dot (%s)" % [s.name, said])
	var units := _hub_units()
	said = BaseHub.server_loadout(1, who, "slot", {"slot": "primary", "id": "hk416"})
	check(primary.call() == "hk416+optic_t2" and not said.contains("Missing") and _hub_units() == units and not BaseHub.member(who).has("edit_missing"),
		"to an HK416: the T-2 moves over, nothing missing, made or lost (%s)" % said)
	var loose_before: int = loose.call()
	said = BaseHub.server_loadout(1, who, "slot", {"slot": "primary", "id": "svd"})
	check(primary.call() == "svd+optic_prism_4x" and int(loose.call()) == loose_before + 1 and not said.contains("Missing") and _hub_units() == units
		and not BaseHub.member(who).has("edit_missing"),
		"to an SVD: it keeps its own scope, the T-2 goes to the stash loose, nothing listed missing (%s; loose T-2 %d -> %d)" % [said, loose_before, loose.call()])
	said = BaseHub.server_loadout(1, who, "slot", {"slot": "primary", "id": "m4a1"})
	check(primary.call() == "m4a1+optic_red_dot" and not said.contains("Missing") and _hub_units() == units,
		"and back to an M4: its own red dot, the scope stays on the SVD in the stash (%s)" % said)
	# The 3D editor's point op on the host: only a point he wears, only a pouch that fits it.
	var odd := ""
	for p: Dictionary in s.inventory.attach_points():
		if odd == "" and not Inventory.point_types(p).any(func(ty: String) -> bool: return ty in ItemDB.get_item(&"aid_bag").stats.get("attach", [])):
			odd = String(p.id)
	var nope := BaseHub.server_loadout(1, who, "point", {"point": "no_such_point", "id": "pouch_mag_double"})
	var wrong := BaseHub.server_loadout(1, who, "point", {"point": odd, "id": "aid_bag"}) if odd != "" else ""
	check(nope.contains("has that point") and (odd == "" or wrong.contains("doesn't fit")) and _hub_units() == units,
		"a point he hasn't got, or an aid bag on his %s point: refused, nothing changed (%s; %s)" % [odd, nope, wrong])


## Buying from the loadout menu's pickers (Captain's "Next" item 4, "buy missing kit from inside
## the loadout editor"): the Swap picker lists a helmet the stash has none of with its price;
## a dollar short it's greyed out and the host refuses it with nothing changed; with the cash,
## choosing it buys it (the shop's price, company money), into the stash and onto him. The
## Optic picker buys the same way. Returns the helmet bought ("" if none could be tried).
func _test_picker_buy(mid: String) -> String:
	print("Buying from the loadout menu's pickers")
	var base := level as BaseLevel
	var s := base.muster_soldier(mid)
	# An NVG on his helmet (the kits check left one there; else one from the stash): a bought
	# helmet must take it along (F-420).
	var nvg_of := func() -> String:
		var g: Dictionary = Roster.json_safe(s.inventory.net_state)
		return GearMounts.on(ItemDB.get_item(StringName(String(g.slots.get("helmet", "")))), g.slot_state.get("helmet", {}), "nvg")
	if nvg_of.call() == "":
		BaseHub.request("loadout", [mid, "mount", {"slot": "helmet", "mount": "nvg", "id": "nvg_gen2"}])
		await _frames(3)
	var nvg: String = nvg_of.call()
	var frame := Control.new()
	add_child(frame)
	frame.size = Vector2(1920, 1080)
	var screen := LoadoutScreen.new()
	frame.add_child(screen)
	await _frames(2)
	screen.select(mid)
	await _frames(2)
	var picker := screen.find_child("Swap_helmet", true, false) as OptionButton
	var buy_id := ""
	var wearing := String(Roster.json_safe(s.inventory.net_state).slots.get("helmet", ""))
	if picker:
		for i in picker.item_count:
			var v := String(picker.get_item_metadata(i))
			if v.begins_with(LoadoutScreen.BUY) and v.trim_prefix(LoadoutScreen.BUY) != wearing:
				buy_id = v.trim_prefix(LoadoutScreen.BUY)
				break
	var price := BaseEconomy.item_price(StringName(buy_id)) if buy_id != "" else 0
	check(buy_id != "" and price > 0 and int(BaseArmory.counts(base.server_collect_stash()).get(buy_id, 0)) == 0
		and int(LoadoutScreen.buyable_prices(BaseHub.view).get(buy_id, 0)) == price,
		"the helmet picker offers %s, which the stash has none of, at the shop's price ($%d)" % [buy_id, price])
	if buy_id == "":
		screen.close()
		frame.queue_free()
		return ""
	var entry := func() -> int:
		var p := screen.find_child("Swap_helmet", true, false) as OptionButton
		for i in (p.item_count if p else 0):
			if String(p.get_item_metadata(i)) == LoadoutScreen.BUY + buy_id:
				return i
		return -1
	# A dollar short: greyed out, and the host refuses it (as from a stale menu) with nothing changed.
	Economy.add_cash(-Economy.cash(), "test: broke")
	Economy.add_cash(price - 1, "test: a dollar short")
	await _wait_until(func() -> bool: return int(BaseHub.view.get("funds", -1)) == price - 1, 5.0)
	screen.refresh()
	picker = screen.find_child("Swap_helmet", true, false) as OptionButton
	var i_short: int = entry.call()
	check(i_short > 0 and picker.is_item_disabled(i_short) and picker.get_item_text(i_short).contains("$%s" % DebriefCalc.money(price)),
		"a dollar short it's greyed out with its price and the cash (%s)" % [picker.get_item_text(i_short) if i_short > 0 else "missing"])
	var units := _hub_units()
	var gear: Dictionary = Roster.json_safe(s.inventory.net_state)
	var missing_before: Dictionary = BaseHub.member(mid).get("edit_missing", {}).duplicate()
	_notes.clear()
	BaseHub.request("loadout", [mid, "slot", {"slot": "helmet", "id": buy_id, "buy": true}])
	await _frames(3)
	check(not _notes.is_empty() and String(_notes.back()).contains("Not enough cash") and Economy.cash() == price - 1
		and _hub_units() == units and Roster.json_safe(s.inventory.net_state) == gear and BaseHub.member(mid).get("edit_missing", {}) == missing_before,
		"and the host refuses it: nothing spent, bought, moved or written down as missing (%s)" % [_notes])
	# With the cash: choosing it in the picker buys it and puts it on.
	Economy.add_cash(51, "test: enough, and $50 over")
	await _wait_until(func() -> bool: return int(BaseHub.view.get("funds", -1)) == price + 50, 5.0)
	screen.refresh()
	picker = screen.find_child("Swap_helmet", true, false) as OptionButton
	var i_buy: int = entry.call()
	check(i_buy > 0 and not picker.is_item_disabled(i_buy) and picker.get_item_text(i_buy) == "Buy: %s ($%s)" % [ItemDB.get_item(StringName(buy_id)).name, DebriefCalc.money(price)],
		"with the cash it reads \"%s\"" % [picker.get_item_text(i_buy) if i_buy > 0 else "missing"])
	# F-404 (Captain, 2026-11-02: "not always but yes"): choosing it asks first. Cancel backs out of
	# the whole action (F-405, 2026-11-08), even with "Don't ask again" ticked.
	_notes.clear()
	if i_buy > 0:
		picker.item_selected.emit(i_buy)  # the player chooses it
	await _frames(2)
	var old_helmet := String(gear.slots.get("helmet", ""))
	var question := _answer_confirm(screen, "Cancel", true)
	await _frames(3)
	check(question.contains(ItemDB.get_item(StringName(buy_id)).name) and question.contains("$" + DebriefCalc.money(price)) and question.contains("$50 left after")
		and Economy.cash() == price + 50 and _hub_units() == units and Roster.json_safe(s.inventory.net_state) == gear and _notes.is_empty()
		and screen.find_child("Confirm", false, false) == null and picker.selected == 0 and LoadoutScreen.confirm_buy_on(),
		"choosing it asks first (\"%s\"), and Cancel backs out: no cash, stash or kit change, the picker back on its prompt, the question still on" % question)
	# Again, with "Don't ask again" ticked: bought, worn, and the setting saved.
	_notes.clear()
	_econ_notes.clear()
	picker = screen.find_child("Swap_helmet", true, false) as OptionButton
	i_buy = entry.call()
	if i_buy > 0:
		picker.item_selected.emit(i_buy)
	await _frames(2)
	question = _answer_confirm(screen, "Ok", true)
	await _frames(4)
	var diff := _diff(units, _hub_units())
	gear = Roster.json_safe(s.inventory.net_state)
	check(question != "" and String(gear.slots.get("helmet", "")) == buy_id and Economy.cash() == 50 and diff == {buy_id: 1}
		and String(BaseHub.member(mid).gear.slots.get("helmet", "")) == buy_id,
		"Buy: one bought ($%d, $%d left), and he wears it; nothing else came or went (%s)" % [price, Economy.cash(), diff])
	check(_notes.size() == 1 and String(_notes[0]).contains("bought for $%s" % DebriefCalc.money(price)) and _econ_notes.is_empty(),
		"one note for the purchase (%s; shop notices %s)" % [_notes, _econ_notes])
	var cfg := ConfigFile.new()
	cfg.load(GameSettings.settings_path())
	check(not LoadoutScreen.confirm_buy_on() and GameSettings.settings_path() == _settings_path and cfg.get_value("loadout", "confirm_buy", true) == false,
		"\"Don't ask again\" turned the question off, saved in the (test's own) settings file")
	# F-420: his NVG went onto the bought helmet; the old helmet is in the stash bare.
	var stash_now: Array = base.server_collect_stash()
	var old_bare := stash_now.all(func(e: Dictionary) -> bool:
		return String(e.id) != old_helmet or GearMounts.on(ItemDB.get_item(StringName(old_helmet)), e.get("state", {}), "nvg") == "")
	check(nvg != "" and nvg_of.call() == nvg and old_bare and not BaseHub.member(mid).get("edit_missing", {}).has(nvg),
		"his %s moved onto the bought %s, the old %s went to the stash bare, nothing written down as missing (on it %s, old bare %s, missing %s)" % [
			nvg, buy_id, old_helmet, nvg_of.call(), old_bare, BaseHub.member(mid).get("edit_missing", {})])
	await _wait_until(func() -> bool:
		var seen := String(BaseHub.view.get("roster", {}).get("members", {}).get(mid, {}).get("gear", {}).get("slots", {}).get("helmet", ""))
		return seen == buy_id and int(BaseHub.view.get("funds", -1)) == 50, 5.0)
	check(String(BaseHub.view.roster.members[mid].gear.slots.get("helmet", "")) == buy_id and int(BaseHub.view.funds) == 50,
		"the view every peer gets shows it on him and the cash left")
	# An optic the stash lacks, on his primary, the same way.
	Economy.add_cash(5000, "test: an optic")
	await _frames(3)
	screen.refresh()
	var optics := screen.find_child("Optic_primary", true, false) as OptionButton
	var optic_id := ""
	for i in (optics.item_count if optics else 0):
		var v := String(optics.get_item_metadata(i))
		if v.begins_with(LoadoutScreen.BUY) and not optics.is_item_disabled(i):
			optic_id = v.trim_prefix(LoadoutScreen.BUY)
			units = _hub_units()
			var cash := Economy.cash()
			optics.item_selected.emit(i)
			await _frames(1)
			var asked := screen.find_child("Confirm", false, false) != null
			await _frames(3)
			gear = Roster.json_safe(s.inventory.net_state)
			var on := Optics.mounted(ItemDB.get_item(StringName(String(gear.slots.get("primary", "")))), gear.slot_state.get("primary", {}))
			check(not asked and on != null and String(on.id) == optic_id and Economy.cash() == cash - BaseEconomy.item_price(StringName(optic_id))
				and int(_hub_units().get(optic_id, 0)) == int(units.get(optic_id, 0)) + 1,
				"the optic picker buys %s the same way and mounts it, without asking now (%s)" % [optic_id, on.id if on else "none"])
			break
	if optic_id == "":
		print("  (no rail gun or no optic for sale: the optic purchase isn't tried)")
	else:
		# An optic he carries (none in the stash) is his to swap in, not "Buy:" (review of c881a939).
		var spare := ""
		for e: Dictionary in BaseEconomy.shop_catalog():
			var oid := String(e.id)
			if spare == "" and oid != optic_id and Optics.is_optic(ItemDB.get_item(StringName(oid))) and int(e.price) <= Economy.cash():
				spare = oid
		if spare != "":
			var in_stash := int(BaseArmory.counts(base.server_collect_stash()).get(spare, 0))
			if in_stash == 0:
				BaseHub.server_buy(StringName(spare), 1)
				in_stash = 1
			BaseHub.request("loadout", [mid, "add", {"id": spare, "count": in_stash}])
			await _frames(3)
			screen.refresh()
			optics = screen.find_child("Optic_primary", true, false) as OptionButton
			var values: Array = []
			var label := ""
			for i in (optics.item_count if optics else 0):
				values.append(String(optics.get_item_metadata(i)))
				if String(optics.get_item_metadata(i)) == spare:
					label = optics.get_item_text(i)
			var carried := int(Roster.gear_counts(Roster.json_safe(s.inventory.net_state)).get(spare, 0))
			check(carried >= 1 and int(BaseArmory.counts(base.server_collect_stash()).get(spare, 0)) == 0 and label.contains("(carried)")
				and not (LoadoutScreen.BUY + spare) in values, "a %s he carries is offered as \"%s\", not to buy" % [spare, label])
			# Choosing it is a plain swap from his own kit: mounted, one fewer loose, nothing
			# charged, bought or written down as missing (review of 91f13def: the pack's copy stayed
			# in the template and was listed missing, so Buy missing offered a second one).
			var i_carried := values.find(spare)
			if i_carried > 0:
				units = _hub_units()
				var cash := Economy.cash()
				var loose_before := int(Loadouts.take_loose(Loadouts.template_of(Roster.json_safe(s.inventory.net_state)), spare, 99).removed)
				_notes.clear()
				optics.item_selected.emit(i_carried)
				await _frames(1)
				var asked := screen.find_child("Confirm", false, false) != null
				await _frames(3)
				gear = Roster.json_safe(s.inventory.net_state)
				var on := Optics.mounted(ItemDB.get_item(StringName(String(gear.slots.get("primary", "")))), gear.slot_state.get("primary", {}))
				var loose_after := int(Loadouts.take_loose(Loadouts.template_of(gear), spare, 99).removed)
				var missing: Dictionary = BaseHub.member(mid).get("edit_missing", {})
				check(not asked and on != null and String(on.id) == spare and loose_after == loose_before - 1 and missing.is_empty()
					and _notes.size() == 1 and not String(_notes[0]).contains("Missing") and Economy.cash() == cash and _hub_units() == units,
					"choosing the carried %s mounts it from his own kit: one fewer loose (%d -> %d), no question, nothing charged, bought or missing (%s, missing %s)" % [
						spare, loose_before, loose_after, _notes, missing])
			else:
				check(false, "the carried %s is in the optic picker" % spare)
	# The question back on from the screen's own tick, saved.
	screen.refresh()
	var ask_tick := screen.find_child("AskBuy", true, false) as CheckBox
	if ask_tick:
		ask_tick.button_pressed = true
	var cfg2 := ConfigFile.new()
	cfg2.load(GameSettings.settings_path())
	check(ask_tick != null and LoadoutScreen.confirm_buy_on() and cfg2.get_value("loadout", "confirm_buy", false) == true,
		"the \"Ask before buying\" tick by the cash turns the question back on, saved")
	screen.close()
	frame.queue_free()
	await _frames(2)
	return buy_id


## Saved kits at the hub (claude/loadout-3d): save, apply to the squad with buy missing, the
## 3D editor's whole-draft "template" op with buy; units conserved apart from what was bought.
func _test_kits_at_hub(ids: Array, me: String) -> void:
	print("Saved kits at the hub")
	var tmpl := Loadouts.set_mount(Loadouts.role_template(Roles.RIFLEMAN), &"primary", "muzzle", "suppressor_rifle")
	_notes.clear()
	BaseHub.request("loadout", [me, "kit_save", {"name": "Quiet rifleman", "template": tmpl}])
	await _frames(2)
	check("Quiet rifleman" in KitLibrary.names(BaseHub.roster()) and "Quiet rifleman" in KitLibrary.names(BaseHub.view.get("roster", {})),
		"a saved kit is on the roster and in the view every player gets (%s)" % [_notes])
	var whos := KitLibrary.resolve(BaseHub.roster(), BaseHub._prep().get("squad", []), ["squad"])
	var jobs: Array = whos.map(func(w: String) -> Dictionary:
		return {"gear": Roster.json_safe((level as BaseLevel).muster_soldier(w).inventory.net_state), "template": tmpl})
	var short := KitLibrary.shortfall(jobs, (level as BaseLevel).server_collect_stash())
	check(int(short.units) > 0 and int(short.missing.get("suppressor_rifle", 0)) >= whos.size() - 1, "the squad (%d) lacks suppressors: %d items, $%d" % [whos.size(), int(short.units), int(short.cost)])
	Economy.add_cash(-Economy.cash(), "test: broke")
	Economy.add_cash(int(short.cost) - 1, "test: a dollar short")
	_notes.clear()
	BaseHub.request("loadout", [me, "kit_apply", {"name": "Quiet rifleman", "to": ["squad"], "buy": true}])
	await _frames(3)
	check(Economy.cash() == int(short.cost) - 1 and not _notes.is_empty() and String(_notes.back()).contains("Not enough cash"), "a dollar short: nothing bought (%s)" % [_notes])
	Economy.add_cash(1, "test: enough")
	var before := _hub_units()
	_notes.clear()
	BaseHub.request("loadout", [me, "kit_apply", {"name": "Quiet rifleman", "to": ["squad"], "buy": true}])
	await _frames(4)
	var after := _hub_units()
	var bought := {}
	for id: String in after:
		if int(after[id]) != int(before.get(id, 0)):
			bought[id] = int(after[id]) - int(before.get(id, 0))
	check(Economy.cash() == 0 and bought == short.missing.duplicate(), "buy missing bought exactly the shortfall ($%d) and nothing else changed (%s vs %s)" % [int(short.cost), bought, short.missing])
	var all_quiet := whos.all(func(w: String) -> bool:
		var g: Dictionary = Roster.json_safe((level as BaseLevel).muster_soldier(w).inventory.net_state)
		return String(Suppressors.mounted_id(ItemDB.get_item(StringName(String(g.slots.get("primary", "")))), g.slot_state.get("primary", {}))) == "suppressor_rifle")
	check(all_quiet and whos.all(func(w: String) -> bool: return Restock.counts(Roster.loadout_of(BaseHub.member(w))) == Restock.counts(KitLibrary.template_of_kit(BaseHub.roster(), "Quiet rifleman"))),
		"every squadmate wears the kit with its suppressor, and it's their standing loadout (%s)" % [_notes])
	# The editor's draft with buy: one helmet NVG the stash lacks.
	var mid := String(ids[0])
	var t := Loadouts.template_of(Roster.json_safe((level as BaseLevel).muster_soldier(mid).inventory.net_state))
	t = Loadouts.set_mount(Loadouts.set_slot(t, &"helmet", "helmet"), &"helmet", "nvg", "nvg_gen3")
	var price := BaseEconomy.item_price(&"nvg_gen3")
	# (v0.7.1: with no HC heroes granted, ids[0] is one of the squad in the quiet kit, and the draft
	# buys a suppressor besides the NVG: the account gets exactly the shortfall, and $100 more)
	var need := KitLibrary.shortfall([{"gear": Roster.json_safe((level as BaseLevel).muster_soldier(mid).inventory.net_state), "template": t}], (level as BaseLevel).server_collect_stash())
	Economy.add_cash(int(need.cost) + 100, "test: an NVG")
	before = _hub_units()
	BaseHub.request("loadout", [mid, "template", {"template": t, "buy": true}])
	await _frames(3)
	var g: Dictionary = Roster.json_safe((level as BaseLevel).muster_soldier(mid).inventory.net_state)
	check(GearMounts.on(ItemDB.get_item(&"helmet"), g.slot_state.get("helmet", {}), "nvg") == "nvg_gen3" and Economy.cash() == 100
		and int(_hub_units().get("nvg_gen3", 0)) == int(before.get("nvg_gen3", 0)) + 1, "the editor's draft: the NVG bought ($%d) and on his helmet (on: %s, cash %d, units %d -> %d)" % [price, GearMounts.on(ItemDB.get_item(&"helmet"), g.slot_state.get("helmet", {}), "nvg"), Economy.cash(), int(before.get("nvg_gen3", 0)), int(_hub_units().get("nvg_gen3", 0))])
	_notes.clear()
	BaseHub.request("loadout", [me, "kit_delete", {"name": "Quiet rifleman"}])
	await _frames(2)
	check(KitLibrary.names(BaseHub.roster()).is_empty(), "a kit deletes")


## The 3D loadout editor and the 3D armory at the hub (claude/loadout-3d): the model wears the
## draft, slots are markers on it, picking fits, undo, an unowned item's Buy now, Apply through
## the host, a kit saved from the editor; the armory's shelves, its panel, buy, Fit on me.
## The editor remembers its last person in user:// (LoadoutEditor.SETTINGS), which every run on
## a machine shares (a run that left it on a squadmate failed the next one's "on your own
## soldier", R0802). F-406: this run's editor reads and writes its own file
## (LoadoutEditor.use_file, set in _ready; dev builds only), never the player's.
func _test_3d(me: String) -> void:
	var real := ProjectSettings.globalize_path(LoadoutEditor.SETTINGS)
	var kept := FileAccess.get_file_as_string(real) if FileAccess.file_exists(real) else "<none>"
	await _test_3d_editor(me)
	check(LoadoutEditor.settings_path() == _editor_path and FileAccess.file_exists(_editor_path)
		and (FileAccess.get_file_as_string(real) if FileAccess.file_exists(real) else "<none>") == kept,
		"the editor kept its picks in the test's own file; the player's user://loadout_editor.cfg is untouched (F-406)")


func _test_3d_editor(me: String) -> void:
	print("The 3D loadout editor")
	Economy.add_cash(50000, "test: the 3D editor")
	var editor := BaseHub.open_loadout_3d()
	check(editor != null, "the 3D editor opens at the base")
	if editor == null:
		return
	await _frames(3)
	check(editor.who == me and editor.preview.model != null and editor.preview.gear != null, "on your own soldier, his model and kit in 3D (%s)" % editor.who)
	var host := level.players.get_node(^"1") as Soldier
	check(Restock.counts(editor.draft) == Restock.counts(Loadouts.template_of(Roster.json_safe(host.inventory.net_state))) and not editor.dirty(),
		"the draft starts as what he wears")
	var main := editor.preview.anchors().filter(func(a: Dictionary) -> bool: return editor.preview.shown(a))
	editor.focus_region("torso")
	await _frames(2)
	var torso := editor.preview.anchors().filter(func(a: Dictionary) -> bool: return editor.preview.shown(a))
	var points := torso.filter(func(a: Dictionary) -> bool: return String(a.key).begins_with("point:"))
	check(main.size() >= 5 and points.size() >= 3 and editor.preview.screen_of(points[0].at) != null if not points.is_empty() else false,
		"markers: %d slots on the whole body, %d MOLLE points on the torso, on screen" % [main.size(), points.size()])
	var p0: Variant = editor.preview.screen_of(torso[0].at)
	check(p0 != null and editor.preview.key_at(p0) != "", "a click on a marker picks a slot (%s)" % [editor.preview.key_at(p0) if p0 != null else ""])
	editor.pick_slot("slot:helmet")
	check(editor.choices("slot:helmet").has("helmet_heavy") and editor.choices("slot:helmet").all(func(id: String) -> bool: return ItemDB.get_item(StringName(id)).slot == &"helmet"),
		"the helmet's picker lists helmets only (%d)" % editor.choices("slot:helmet").size())
	var try_on := ""
	for id: String in editor.choices("slot:helmet"):
		if try_on == "" and editor.owned(id) > 0 and id != String(editor.worn.slots.get("helmet", "")):
			try_on = id  # one the company owns (an unowned one would be bought: below)
	editor.choose(try_on)
	await _frames(1)
	check(try_on != "" and String(editor.draft.slots.get("helmet", "")) == try_on and String(editor.preview.inventory.slots.get(&"helmet", &"")) == try_on and editor.dirty(),
		"picking an owned %s puts it on the model at once, as a draft" % try_on)
	editor.undo()
	check(String(editor.draft.slots.get("helmet", "")) != try_on and not editor.dirty(), "Ctrl+Z takes it back")
	# A plate pocket is "on what he wears" only while the draft's carrier is his (review of 4bcfe79f).
	var plates_worn := editor.on_worn("slot:plate_front")
	editor.edit(Loadouts.set_slot(editor.draft, &"vest", ""))
	check(plates_worn and not editor.on_worn("slot:plate_front") and editor.on_worn("slot:helmet"),
		"a plate pocket buys in one step only on the carrier he wears, not on a draft without it")
	editor.revert_draft()
	# F-405: an unowned item is bought and fitted in one step, asking first (this run's settings
	# start with the question on). His helmet first, so the NVG mount is on what he wears.
	if String(editor.worn.slots.get("helmet", "")) == "":
		editor.pick_slot("slot:helmet")
		editor.choose("helmet")
		editor.apply_draft()
		await _wait_until(func() -> bool: return String(editor.worn.slots.get("helmet", "")) != "", 6.0)
	var nvg_on := func() -> String:
		var hg: Dictionary = Roster.json_safe(host.inventory.net_state)
		return GearMounts.on(ItemDB.get_item(StringName(String(hg.slots.get("helmet", "")))), hg.slot_state.get("helmet", {}), "nvg")
	var unowned := ""
	for id: String in ["nvg_gen3", "nvg_gen1", "nvg_gen2"]:
		if unowned == "" and editor.owned(id) <= 0 and id != nvg_on.call():
			unowned = id
	var price := LoadoutEditor.price_of(unowned)
	editor.pick_slot("mount:helmet:nvg")
	var draft_was: int = hash(editor.draft)
	var dirty_was: bool = editor.dirty()
	var undo_was: int = editor.undo_stack.size()
	var cash := Economy.cash()
	var units := _hub_units()
	editor.choose(unowned)
	await _frames(2)
	var box := editor.find_child("Confirm", false, false)
	var question := ""
	for l: Node in (box.find_children("*", "Label", true, false) if box else []):
		question += (l as Label).text + " "
	check(box != null and question.contains(ItemDB.get_item(StringName(unowned)).name) and question.contains("$" + DebriefCalc.money(price))
		and question.contains("$%s left after" % DebriefCalc.money(cash - price)),
		"picking an unowned NVG asks first, with its price and the cash left after (%s)" % question.strip_edges())
	if box:
		(box.find_child("Cancel", true, false) as Button).pressed.emit()
	await _frames(3)
	check(Economy.cash() == cash and _hub_units() == units and hash(editor.draft) == draft_was and editor.find_child("Confirm", false, false) == null
		and nvg_on.call() != unowned and editor.dirty() == dirty_was and editor.undo_stack.size() == undo_was and editor._offer == "",
		"Cancel backs out (F-405): nothing bought, the draft, its undo and the close warning as they were, no buy offer")
	# With other changes in the draft: they stay, and so does the close warning.
	editor.edit(Loadouts.add_units(editor.draft, "smoke_grenade", 1))
	var edited: int = hash(editor.draft)
	var undo_edited: int = editor.undo_stack.size()
	editor.choose(unowned)
	await _frames(2)
	box = editor.find_child("Confirm", false, false)
	var asked_edited := box != null
	if box:
		(box.find_child("Cancel", true, false) as Button).pressed.emit()
	await _frames(3)
	check(asked_edited and Economy.cash() == cash and _hub_units() == units and hash(editor.draft) == edited and editor.undo_stack.size() == undo_edited and editor.dirty()
		and nvg_on.call() != unowned, "and Cancel with other changes in the draft keeps them, the close warning too, and buys nothing")
	editor.undo()
	# The host refuses it (the cash spent while the question was up): nothing bought, the draft
	# still what he wears and nothing left waiting for a change (review of 4bcfe79f).
	editor.choose(unowned)
	await _frames(2)
	box = editor.find_child("Confirm", false, false)
	var asked := box != null  # (read now: Ok frees the box, and a freed one compares equal to null)
	Economy.add_cash(-cash, "test: spent meanwhile")
	_notes.clear()
	if box:
		(box.find_child("Ok", true, false) as Button).pressed.emit()
	await _frames(3)
	var refused := {"asked": asked, "cash 0": Economy.cash() == 0, "units": _diff(units, _hub_units()), "clean": not editor.dirty(),
		"pending": editor._applied_pending, "nvg on": nvg_on.call()}
	check(refused.asked and refused["cash 0"] and (refused.units as Dictionary).is_empty() and refused.clean and not refused.pending and refused["nvg on"] != unowned
		and _notes.any(func(t: String) -> bool: return t.contains("Not enough cash")),
		"a purchase the host refuses: nothing bought, the draft still clean, nothing pending (%s; %s)" % [refused, _notes])
	Economy.add_cash(cash, "test: cash back")
	await _wait_until(func() -> bool: return int(BaseHub.view.get("funds", -1)) == cash, 5.0)
	_notes.clear()
	_econ_notes.clear()
	editor.choose(unowned)
	await _frames(2)
	box = editor.find_child("Confirm", false, false)
	if box:
		(box.find_child("DontAsk", true, false) as CheckBox).button_pressed = true
		(box.find_child("Ok", true, false) as Button).pressed.emit()
	var ask_tick := editor.find_child("AskBuy", true, false) as CheckBox
	check(ask_tick != null and not ask_tick.button_pressed and not LoadoutScreen.confirm_buy_on(),
		"\"Don't ask again\" there unticks the editor's own \"Ask before buying\" (review of 4bcfe79f)")
	if ask_tick:
		ask_tick.button_pressed = true
	check(LoadoutScreen.confirm_buy_on(), "and that tick turns the question back on")
	var fitted := await _wait_until(func() -> bool: return nvg_on.call() == unowned and not editor.dirty(), 6.0)
	var diff := _diff(units, _hub_units())
	check(fitted and Economy.cash() == cash - price and diff == {unowned: 1} and not editor.dirty(),
		"Buy: one bought ($%d, $%d left) and on his helmet in one step, no Apply; the draft is what he wears (%s)" % [price, Economy.cash(), diff])
	check(_notes.size() == 1 and String(_notes[0]).contains("bought for") and _econ_notes.is_empty(),
		"one note for the purchase (%s; shop notices %s)" % [_notes, _econ_notes])
	# Can't afford it: it stays in the draft with Buy now greyed out, nothing bought.
	var other := ""
	for id: String in ["nvg_gen1", "nvg_gen2", "nvg_gen3"]:
		if other == "" and editor.owned(id) <= 0:
			other = id
	if other != "":
		var funds_kept := Economy.cash()
		Economy.add_cash(-funds_kept, "test: broke")
		await _wait_until(func() -> bool: return int(BaseHub.view.get("funds", -1)) == 0, 5.0)
		units = _hub_units()
		editor.choose(other)
		await _frames(2)
		var buy_now := editor.find_child("BuyNow", true, false) as Button
		check(editor.find_child("Confirm", false, false) == null and buy_now != null and buy_now.disabled and String(editor.draft.get("mounts", {}).get("helmet", {}).get("nvg", "")) == other
			and _hub_units() == units, "with no cash an unowned NVG goes in the draft only, Buy now greyed out (%s)" % [buy_now.text if buy_now else "none"])
		editor.revert_draft()
		Economy.add_cash(funds_kept, "test: cash back")
		await _frames(2)
	# The rest of the draft still waits for Apply.
	editor.pick_slot("pockets")
	editor.choose("smoke_grenade")
	var smokes := int(Roster.gear_counts(Roster.json_safe(host.inventory.net_state)).get("smoke_grenade", 0))
	check(editor.dirty(), "an owned pick is a draft until Apply")
	editor.apply_draft()
	await _frames(4)
	check(int(Roster.gear_counts(Roster.json_safe(host.inventory.net_state)).get("smoke_grenade", 0)) == smokes + 1 and not editor.dirty() and nvg_on.call() == unowned,
		"Apply fits the draft through the host: one more smoke (%d of %d), the NVG still on (%s), and the draft is what he wears (dirty %s)" % [
		int(Roster.gear_counts(Roster.json_safe(host.inventory.net_state)).get("smoke_grenade", 0)), smokes + 1, nvg_on.call(), editor.dirty()])
	editor.save_kit("Editor kit")
	await _frames(2)
	check("Editor kit" in KitLibrary.names(BaseHub.roster()), "a kit saved from the editor is on the roster")
	editor.close()
	await _frames(2)
	print("The 3D armory")
	var room := BaseHub.open_armory()
	check(room != null, "the armory opens at the base")
	if room == null:
		return
	await _frames(3)
	var groups := {}
	for it: Dictionary in room.items:
		groups[Loadouts.group_of(ItemDB.get_item(StringName(String(it.id))))] = true
	check(room.items.size() > 40 and groups.size() >= 7, "the shelves hold %d items in %d kinds" % [room.items.size(), groups.size()])
	room.walk_to("weapons")
	for i in 40:
		await get_tree().process_frame
	var target: Dictionary = room.items.filter(func(it: Dictionary) -> bool: return Loadouts.group_of(ItemDB.get_item(StringName(String(it.id)))) == "weapons")[0]
	var scale_by: Vector2 = room.view_box.size / Vector2(room.viewport.size)
	var at := room.camera.unproject_position((target.node as Node3D).global_position) * scale_by
	check(room.item_at(at) != "", "pointing at a rifle on the weapons shelf finds it (%s)" % room.item_at(at))
	room.point_at("m4a1")
	await _frames(1)
	var buy := room.find_child("Buy", true, false) as Button
	check(buy != null and buy.text.contains("$%d" % BaseEconomy.item_price(&"m4a1")), "its panel shows the price and a Buy button")
	var had := int(_hub_units().get("m4a1", 0))
	cash = Economy.cash()
	buy.pressed.emit()
	await _frames(3)
	check(int(_hub_units().get("m4a1", 0)) == had + 1 and Economy.cash() == cash - BaseEconomy.item_price(&"m4a1"), "Buy puts one in the stash and takes the money")
	room.fit_on_me("helmet_heavy")
	await _frames(3)
	var ed := get_tree().root.find_child("LoadoutEditor", true, false) as LoadoutEditor
	check(ed != null and not is_instance_valid(room) or room.is_queued_for_deletion(), "Fit on me opens the editor and the armory steps aside")
	if ed:
		check(String(ed.draft.slots.get("helmet", "")) == "helmet_heavy" and ed.slot_key == "slot:helmet" and ed.dirty(),
			"with the heavy helmet on him as a draft, its slot picked (%s, %s)" % [ed.slot_key, ed.draft.slots])
		ed.close()
	await _frames(2)


## Units of every item in the hub's stash (world items, with what's on and in them) and on
## everyone there (players and the muster line).
func _hub_units() -> Dictionary:
	var gears: Array = []
	for p: Node in level.players.get_children():
		if p is Soldier and not p.is_queued_for_deletion():
			gears.append(Roster.json_safe((p as Soldier).inventory.net_state))
	for mid: String in Roster.available_ids(BaseHub.roster()):
		var s := (level as BaseLevel).muster_soldier(mid)
		if s:
			gears.append(Roster.json_safe(s.inventory.net_state))
	return Loadouts.units((level as BaseLevel).server_collect_stash(), gears)


## The screen fits every window size and UI scale: its columns sit inside the window side by
## side and nothing asks for more room than there is (rows wrap, columns scroll).
func _test_fit(ids: Array) -> void:
	print("The loadout screen at every window size")
	var frame := Control.new()
	add_child(frame)
	var screen := LoadoutScreen.new()
	frame.add_child(screen)
	await _frames(2)
	screen.select(String(ids[0]))
	await _frames(2)
	check(screen.doll_box.get_child_count() > 10 and screen.stash_box.get_child_count() > 10 and screen.people_box.get_child_count() >= ids.size() + 1,
		"it lists the people, %s's paper doll and the stash" % BaseHub.member(String(ids[0])).callsign)
	check(screen.find_child("FillAmmo", true, false) != null and screen.find_child("SaveStanding", true, false) != null
		and screen.find_child("Swap_primary", true, false) != null and screen.find_child("Optic_primary", true, false) != null,
		"with the slot pickers, the helpers and the standing loadout's buttons")
	var bad := PackedStringArray()
	for ui_scale in FIT_SCALES:
		for res in FIT_SIZES:
			frame.size = Vector2(res) / ui_scale
			await _frames(2)
			var win := Rect2(Vector2.ZERO, frame.size).grow(0.5)
			var why := ""
			var need := screen.get_combined_minimum_size()
			if need.x > frame.size.x + 0.5 or need.y > frame.size.y + 0.5:
				why += " needs %s" % need
			var last_end := -1.0
			for c: Control in screen.columns:
				var r := c.get_global_rect()
				if not win.encloses(r) or r.size.x < 60.0:
					why += " column %s at %s" % [c.name, r]
				if r.position.x < last_end - 0.5:
					why += " columns overlap"
				last_end = r.end.x
			if not win.encloses(screen.status.get_global_rect()):
				why += " status off the window"
			if why != "":
				bad.append("%dx%d @%.2f:%s" % [res.x, res.y, ui_scale, why])
	check(bad.is_empty(), "at %d window sizes and UI scales %s the three columns fit side by side%s" % [FIT_SIZES.size(), FIT_SCALES, "" if bad.is_empty() else ": " + "; ".join(bad)])
	var tip := LoadoutScreen.item_tooltip("m4a1")
	check(tip.begins_with(ItemDB.get_item(&"m4a1").name), "items have a tooltip (%s)" % tip.replace("\n", " / "))
	screen.close()
	frame.queue_free()
	await _frames(2)


# --- A client ----------------------------------------------------------------------------------

func _test_client(ids: Array, bought_helmet := "") -> void:
	print("A client's loadout requests go through the host")
	var log_path := ProjectSettings.globalize_path("user://loadout_test_client%s.log" % tag)
	if FileAccess.file_exists(log_path):
		DirAccess.remove_absolute(log_path)
	# The client joins after the host's picker purchase (a late joiner: the view brings it) and
	# buys a helmet for itself from its own picker, through the host, on the company's account.
	Economy.add_cash(maxi(0, 20000 - Economy.cash()), "test: the client's purchase")
	var cash_before := Economy.cash()
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/loadout_test.tscn", "--", "--join", "127.0.0.1",
		"--log", log_path, "--member", String(ids[2]), "--bought-by", String(ids[0]), "--bought", bought_helmet if bought_helmet != "" else "-"]
	var before := {}
	var started := Time.get_ticks_msec()
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "a client process starts")
	var joined := await _wait_until(func() -> bool: return level.players.get_child_count() >= 2, 90.0)
	check(joined, "and joins the hub")
	var s := (level as BaseLevel).muster_soldier(String(ids[2]))
	var mags_before := int(Roster.gear_counts(Roster.json_safe(s.inventory.net_state)).get("mag_556", 0)) if s else 0
	var host_body: Soldier = level.players.get_node(^"1")
	var host_gear: Dictionary = Roster.json_safe(host_body.inventory.net_state)
	await _frames(5)
	before = _hub_units()
	var done := false
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - started < 180000:
		if FileAccess.file_exists(log_path) and FileAccess.get_file_as_string(log_path).contains(CLIENT_DONE):
			done = true
			break
		await _seconds(0.25)
	await _frames(5)
	var client_body: Soldier = null
	for p: Node in level.players.get_children():
		if p.name != "1":
			client_body = p as Soldier
	check(done and client_body != null, "the client asked and finished its checks")
	if client_body:
		check(int(Roster.gear_counts(Roster.json_safe(client_body.inventory.net_state)).get("smoke_grenade", 0)) >= 1,
			"the host gave the client's body the smoke it asked for")
	check(Roster.json_safe(host_body.inventory.net_state) == host_gear, "the host's kit is untouched by the client's request on it")
	if s:
		check(int(Roster.gear_counts(Roster.json_safe(s.inventory.net_state)).get("mag_556", 0)) >= mags_before, "the client's Fill ammo on a squadmate went through the host")
	var diff := _diff(before, _hub_units())
	_client_bought = String(Roster.json_safe(client_body.inventory.net_state).slots.get("helmet", "")) if client_body else ""
	var paid := BaseEconomy.item_price(StringName(_client_bought)) if _client_bought != "" else -1
	# And one item from its 3D editor (F-405), bought and fitted in one step through the host.
	var in_3d := ""
	for id: String in diff:
		if id != _client_bought and int(diff[id]) == 1:
			in_3d = id
	var paid_3d := BaseEconomy.item_price(StringName(in_3d)) if in_3d != "" else -1
	var on_client := Loadouts.units([], [Roster.json_safe(client_body.inventory.net_state)]) if client_body else {}
	check(_client_bought != "" and in_3d != "" and diff == {_client_bought: 1, in_3d: 1} and Economy.cash() == cash_before - paid - paid_3d
		and int(on_client.get(in_3d, 0)) >= 1,
		"the client's purchases: one %s from its picker and one %s from its 3D editor, on the company's account ($%d + $%d of $%d) and on the client's body; nothing else made or lost (%s)" % [
			_client_bought, in_3d, paid, paid_3d, cash_before, diff])
	var deadline := Time.get_ticks_msec() + 30000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await _seconds(0.25)
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	var code := OS.get_process_exit_code(pid) if pid > 0 else -1
	if FileAccess.file_exists(log_path):
		for line in FileAccess.get_file_as_string(log_path).split("\n"):
			if line.strip_edges() != "" and line.strip_edges() != CLIENT_DONE:
				print("  (client) " + line.strip_edges())
	check(code == 0, "the client's checks pass (exit %d)" % code)


## F-421 (Captain, 2026-11-06: "varies. if you go from ar to sniper yes, M4 to HK416 yes"): a
## gun swapped for another takes the optic he fitted along, unless the new one is a sniper or DMR
## with a scope of its own (Loadouts.OWN_SCOPE_TAGS): that stays on, his goes to the stash loose.
func _test_gun_swap_rules(rifleman: Dictionary) -> void:
	print("A gun swapped for another, and its optic (F-421)")
	var pool := _stash()
	BaseArmory.add(pool, &"m27", 1)
	var dotted: Dictionary = Loadouts.rebuild([{"gear": rifleman, "template": Loadouts.set_optic(Loadouts.template_of(rifleman), &"primary", "optic_t2")}], pool)[0].gear
	var optic_of := func(gear: Dictionary) -> String:
		var id := String(gear.slots.get("primary", ""))
		return "%s+%s" % [id, Optics.mounted_id(ItemDB.get_item(StringName(id)), gear.get("slot_state", {}).get("primary", {}))] if id != "" else ""
	var loose_t2 := func(p: Array) -> int:
		return p.filter(func(e: Dictionary) -> bool: return String(e.id) == "optic_t2").reduce(func(n: int, e: Dictionary) -> int: return n + int(e.count), 0)
	var gun_has_t2 := func(p: Array) -> bool:
		return p.any(func(e: Dictionary) -> bool:
			var g := ItemDB.get_item(StringName(String(e.id)))
			return Optics.has_rail(g) and Optics.mounted_id(g, e.get("state", {})) == &"optic_t2")
	check(optic_of.call(dotted) == "m4a1+optic_t2", "his M4 with a T-2 red dot (%s)" % optic_of.call(dotted))
	var t := Loadouts.template_of(dotted)
	check(String(Loadouts.set_slot(t, &"primary", "hk416").optics.primary) == "optic_t2" and String(Loadouts.set_slot(t, &"primary", "m110").optics.primary) == "optic_dmr_3_5_10"
		and String(Loadouts.set_slot(t, &"primary", "svd").optics.primary) == "optic_prism_4x" and Loadouts.keeps_own_optic(ItemDB.get_item(&"m110"))
		and String(Loadouts.set_slot(t, &"primary", "m27").optics.primary) == "optic_prism_4x" and Loadouts.keeps_own_optic(ItemDB.get_item(&"m27"))
		and not Loadouts.keeps_own_optic(ItemDB.get_item(&"hk416")), "the template: the T-2 asked for on an HK416, an M110, SVD or M27 (F-465) its own scope")
	for to: String in ["hk416", "m110", "svd", "m27"]:
		var p := pool.duplicate(true)
		var before := Loadouts.units(p, [dotted])
		var loose: int = loose_t2.call(p)
		var res: Dictionary = Loadouts.rebuild([{"gear": dotted, "template": Loadouts.set_slot(t, &"primary", to)}], p)[0]
		var gun := ItemDB.get_item(StringName(to))
		var want := "optic_t2" if to == "hk416" else String(gun.stats.optic)
		check(optic_of.call(res.gear) == to + "+" + want and res.missing.is_empty() and Loadouts.units(p, [res.gear]) == before and not gun_has_t2.call(p)
			and int(loose_t2.call(p)) == loose + (0 if to == "hk416" else 1),
			"M4 with the T-2 to the %s: it wears %s, nothing missing or made, the T-2 %s (missing %s)" % [
				gun.name, optic_of.call(res.gear), "moved over" if to == "hk416" else "in the stash loose, not on the M4", res.missing])
		if to in ["m110", "m27"]:
			# And back: the M4 comes with its own dot; the M110 or M27 keeps its scope in the stash.
			var res2: Dictionary = Loadouts.rebuild([{"gear": res.gear, "template": Loadouts.set_slot(Loadouts.template_of(res.gear), &"primary", "m4a1")}], p)[0]
			var scoped := p.any(func(e: Dictionary) -> bool:
				return String(e.id) == to and String(Optics.mounted_id(gun, e.get("state", {}))) == String(gun.stats.optic))
			check(optic_of.call(res2.gear) == "m4a1+optic_red_dot" and res2.missing.is_empty() and scoped and Loadouts.units(p, [res2.gear]) == before,
				"and back to an M4: its own red dot, the scope stays on the %s (%s, missing %s)" % [gun.name, optic_of.call(res2.gear), res2.missing])
	# A stock M4 (its own red dot) to an HK416, which comes with the same dot: the M4 goes back
	# plain with its dot on, no stray loose dot (review of 4bcfe79f: it went in bare, irons, and
	# its dot loose, while the stash's HK416 came with its own).
	var sp := pool.duplicate(true)
	var stock_before := Loadouts.units(sp, [rifleman])
	var dots := func(p: Array) -> int:
		return p.filter(func(e: Dictionary) -> bool: return String(e.id) == "optic_red_dot").reduce(func(n: int, e: Dictionary) -> int: return n + int(e.count), 0)
	var dots_before: int = dots.call(sp)
	var stock: Dictionary = Loadouts.rebuild([{"gear": rifleman, "template": Loadouts.set_slot(Loadouts.template_of(rifleman), &"primary", "hk416")}], sp)[0]
	var m4 := ItemDB.get_item(&"m4a1")
	var plain_m4s := sp.filter(func(e: Dictionary) -> bool: return String(e.id) == "m4a1")
	var bare := plain_m4s.filter(func(e: Dictionary) -> bool:
		return (e.get("state", {}) as Dictionary).has(Optics.STATE_KEY) or Optics.mounted_id(m4, e.get("state", {})) != &"optic_red_dot")
	check(optic_of.call(rifleman) == "m4a1+optic_red_dot" and optic_of.call(stock.gear) == "hk416+optic_red_dot" and stock.missing.is_empty()
		and Loadouts.units(sp, [stock.gear]) == stock_before and not plain_m4s.is_empty() and bare.is_empty() and int(dots.call(sp)) == dots_before,
		"a stock M4 to an HK416: its own dot stays on the M4 in the stash, no loose dot, nothing missing, made or lost (%s; M4s %s; loose dots %d -> %d)" % [
			optic_of.call(stock.gear), plain_m4s, dots_before, dots.call(sp)])
	# And when every HK416 in the stash is bare (irons): the M4's own dot moves over, so nothing is
	# listed missing; the M4 goes back bare (round 6 review, F-421; Loadouts._comes_with).
	var hk := ItemDB.get_item(&"hk416")
	var bp := pool.duplicate(true)
	for e: Dictionary in bp:
		if String(e.id) == "hk416":
			e["state"] = Optics.with_optic(hk, e.get("state", {}), &"")
	var bare_before := Loadouts.units(bp, [rifleman])
	var bare_dots: int = dots.call(bp)
	var hks_before := int(Loadouts.units(bp, []).get("hk416", 0))
	var onto_bare: Dictionary = Loadouts.rebuild([{"gear": rifleman, "template": Loadouts.set_slot(Loadouts.template_of(rifleman), &"primary", "hk416")}], bp)[0]
	var bare_m4 := bp.any(func(e: Dictionary) -> bool: return String(e.id) == "m4a1" and Optics.mounted_id(m4, e.get("state", {})) == &"")
	check(int(Loadouts.units(bp, []).get("hk416", 0)) == hks_before - 1 and optic_of.call(onto_bare.gear) == "hk416+optic_red_dot"
		and onto_bare.missing.is_empty() and Loadouts.units(bp, [onto_bare.gear]) == bare_before and bare_m4 and int(dots.call(bp)) == bare_dots,
		"a stock M4 to the stash's bare HK416: the M4's dot moves over, the M4 goes back bare, nothing missing, made or lost (%s, missing %s; loose dots %d -> %d)" % [
			optic_of.call(onto_bare.gear), onto_bare.missing, bare_dots, dots.call(bp)])


## F-478: an attachment on a gun that has since stopped taking it (an M320 or Skeleton Key on an
## M27, from before it was tagged "dmr") is still in the gun's raw state, where nothing else sees
## it. The rebuild takes it off into the stash loose with its own state; nothing is lost.
func _test_unfit_mounts(rifleman: Dictionary) -> void:
	print("An attachment the gun no longer takes (F-478)")
	var m27 := ItemDB.get_item(&"m27")
	var ub := String(GunAttachments.UNDERBARREL)
	var loaded := GunAttachments.with_mounted(m27.default_state(), GunAttachments.UNDERBARREL, &"m320", {"round": "m406"})
	var keyed := GunAttachments.with_mounted(m27.default_state(), GunAttachments.UNDERBARREL, &"skeleton_key", {"rounds": 2})
	var loose := func(p: Array, id: String) -> int:
		return p.filter(func(e: Dictionary) -> bool: return String(e.id) == id).reduce(func(n: int, e: Dictionary) -> int: return n + int(e.count), 0)
	var round_on := func(p: Array) -> bool:
		return p.any(func(e: Dictionary) -> bool: return String(e.id) == "m320" and String(e.get("state", {}).get("round", "")) == "m406")
	var raw_27 := func(p: Array) -> bool:
		return p.any(func(e: Dictionary) -> bool: return String(e.id) == "m27" and (e.get("state", {}) as Dictionary).has(ub))
	check(not GunAttachments.fits(m27, ItemDB.get_item(&"m320")) and GunAttachments.mounted_id(m27, loaded, GunAttachments.UNDERBARREL) == &"" and String(loaded.get(ub, "")) == "m320",
		"an M320 left on an M27 is still in its state, and nothing reads it")
	# Worn, nothing named on the slot.
	var worn := rifleman.duplicate(true)
	worn.slots["primary"] = "m27"
	worn.slot_state["primary"] = loaded.duplicate(true)
	var pool := _stash()
	var had: int = loose.call(pool, "m320")
	var res: Dictionary = Loadouts.rebuild([{"gear": worn, "template": Loadouts.template_of(worn)}], pool)[0]
	check(int(loose.call(pool, "m320")) == had + 1 and round_on.call(pool) and not (res.gear.slot_state.get("primary", {}) as Dictionary).has(ub) and String(res.gear.slots.get("primary", "")) == "m27",
		"worn, a rebuild puts the M320 in the stash loose with its grenade in, off the M27 he keeps (%d -> %d)" % [had, loose.call(pool, "m320")])
	# The template names a grip for that mount: writing it used to overwrite the M320.
	pool = _stash()
	BaseArmory.add(pool, &"grip_vertical", 1)
	had = loose.call(pool, "m320")
	res = Loadouts.rebuild([{"gear": worn, "template": Loadouts.set_mount(Loadouts.template_of(worn), &"primary", ub, "grip_vertical")}], pool)[0]
	check(int(loose.call(pool, "m320")) == had + 1 and round_on.call(pool) and GearMounts.on(m27, res.gear.slot_state.get("primary", {}), ub) == "grip_vertical",
		"a grip asked for on that mount goes on and the M320 still ends up in the stash (%d -> %d, on it %s)" % [had, loose.call(pool, "m320"), GearMounts.of(m27, res.gear.slot_state.get("primary", {}))])
	# In the stash, drawn by a swap to the M27, and a Key in his pack.
	pool = _stash()
	pool.append({"id": "m27", "count": 1, "state": Roster.json_safe(loaded)})
	had = loose.call(pool, "m320")
	var packed := rifleman.duplicate(true)
	var keys: int = loose.call(pool, "skeleton_key")
	(packed.containers["backpack"] as Array).append({"id": "m27", "count": 1, "state": Roster.json_safe(keyed)})
	res = Loadouts.rebuild([{"gear": packed, "template": Loadouts.set_slot(Loadouts.template_of(rifleman), &"primary", "m27")}], pool)[0]
	check(int(loose.call(pool, "m320")) == had + 1 and int(loose.call(pool, "skeleton_key")) == keys + 1 and not raw_27.call(pool)
		and not (res.gear.slot_state.get("primary", {}) as Dictionary).has(ub),
		"on a stash M27 and on one in his pack: both come off, the M320 (%d -> %d) and the Key (%d -> %d)" % [had, loose.call(pool, "m320"), keys, loose.call(pool, "skeleton_key")])
	# Left alone where it still fits.
	pool = _stash()
	var m4 := ItemDB.get_item(&"m4a1")
	var good := GunAttachments.with_mounted(m4.default_state(), GunAttachments.UNDERBARREL, &"m320", {"round": "m406"})
	pool.append({"id": "m4a1", "count": 1, "state": Roster.json_safe(good)})
	had = loose.call(pool, "m320")
	Loadouts.rebuild([{"gear": {}, "template": Loadouts.role_template(Roles.RIFLEMAN)}], pool)
	check(int(loose.call(pool, "m320")) == had, "an M320 on an M4, which takes one, stays on it (%d -> %d)" % [had, loose.call(pool, "m320")])


## Client process: joins the hub, asks the host for a smoke on itself, Fill ammo on a squadmate,
## and to change the host's kit (refused); writes its checks to --log.
func _run_client() -> void:
	var args := OS.get_cmdline_user_args()
	_log = FileAccess.open(args[args.find("--log") + 1], FileAccess.WRITE)
	var mid := args[args.find("--member") + 1]
	Campaign.campaign_id = "test_loadout_client" + tag
	BaseHub.local_profile = CLIENT_KEY
	add_child(load("res://scenes/main.tscn").instantiate())
	await _tree.process_frame
	var followed := await _wait_until(func() -> bool: return CompoundLevel.current(self) is BaseLevel and BaseHub.campaign_running, 60.0)
	check(followed, "the client follows the host to the base")
	level = CompoundLevel.current(self)
	var me := multiplayer.get_unique_id()
	var known := await _wait_until(func() -> bool:
		return CLIENT_KEY in BaseHub.view.get("players", {}).values() and level.players.get_node_or_null(str(me)) != null, 30.0)
	check(known, "the host knows the client, and its body is here")
	var notes: Array = []
	BaseHub.note.connect(func(t: String) -> void: notes.append(t))
	var body: Soldier = level.players.get_node_or_null(str(me))
	var smokes := func() -> int: return int(Roster.gear_counts(Roster.json_safe(body.inventory.net_state)).get("smoke_grenade", 0)) if body else 0
	var had: int = smokes.call()
	BaseHub.request("loadout", ["player:" + CLIENT_KEY, "add", {"id": "smoke_grenade", "count": 1}])
	var got := await _wait_until(func() -> bool: return smokes.call() > had, 15.0)
	check(got and not notes.is_empty(), "its +1 smoke went through the host and came back on its body (%s)" % [notes])
	var host_key := ""
	for peer: Variant in BaseHub.view.get("players", {}):
		if int(peer) == 1:
			host_key = String(BaseHub.view.players[peer])
	notes.clear()
	BaseHub.request("loadout", ["player:" + host_key, "add", {"id": "smoke_grenade", "count": 1}])
	var refused := await _wait_until(func() -> bool: return notes.any(func(t: String) -> bool: return t.contains("their own kit")), 15.0)
	check(refused, "changing the host's kit is refused (%s)" % [notes])
	notes.clear()
	BaseHub.request("loadout", [mid, "fill_ammo", {}])
	var answered := await _wait_until(func() -> bool: return not notes.is_empty(), 15.0)
	check(answered and String(notes[0]).contains("ammo filled"), "Fill ammo on a squadmate is answered by the host (%s)" % [notes])
	# A late joiner sees the host's earlier picker purchase: the view brings it.
	var bought := args[args.find("--bought") + 1]
	var bought_by := args[args.find("--bought-by") + 1]
	if bought != "-":
		check(String(BaseHub.view.get("roster", {}).get("members", {}).get(bought_by, {}).get("gear", {}).get("slots", {}).get("helmet", "")) == bought,
			"joining later, it sees the helmet the host bought from the picker on that squadmate (%s)" % bought)
	# Its own picker: a helmet the stash has none of, bought through the host on the company's account.
	var frame := Control.new()
	add_child(frame)
	frame.size = Vector2(1920, 1080)
	var screen := LoadoutScreen.new()
	frame.add_child(screen)
	await _frames(2)
	screen.select("player:" + CLIENT_KEY)
	await _frames(2)
	var picker := screen.find_child("Swap_helmet", true, false) as OptionButton
	var buy_id := ""
	var pick := -1
	var wearing := String(Roster.json_safe(body.inventory.net_state).slots.get("helmet", "")) if body else ""
	for i in (picker.item_count if picker else 0):
		var v := String(picker.get_item_metadata(i))
		if v.begins_with(LoadoutScreen.BUY) and not picker.is_item_disabled(i) and v.trim_prefix(LoadoutScreen.BUY) != wearing:
			buy_id = v.trim_prefix(LoadoutScreen.BUY)
			pick = i
			break
	var price := int(LoadoutScreen.buyable_prices(BaseHub.view).get(buy_id, 0))
	var funds := int(BaseHub.view.get("funds", 0))
	check(pick > 0 and price > 0, "its helmet picker offers %s at $%d (cash $%d in its view)" % [buy_id, price, funds])
	notes.clear()
	_econ_notes.clear()
	if pick > 0:
		picker.item_selected.emit(pick)
	await _frames(2)
	var question := _answer_confirm(screen, "Ok")  # its own settings: the question is on
	var worn := await _wait_until(func() -> bool:
		return body != null and String(Roster.json_safe(body.inventory.net_state).slots.get("helmet", "")) == buy_id, 15.0)
	var paid := await _wait_until(func() -> bool: return int(BaseHub.view.get("funds", 0)) == funds - price, 15.0)
	await _seconds(0.5)
	check(pick > 0 and question != "" and worn and paid and notes.size() == 1 and String(notes[0]).contains("bought for") and _econ_notes.is_empty(),
		"choosing it asks, then the host bought it and put it on its body, its view shows $%d less, one note (%s; shop notices %s)" % [price, notes, _econ_notes])
	screen.close()
	frame.queue_free()
	await _frames(2)
	# Its 3D editor (F-405): something it doesn't own, bought and fitted in one step through the host.
	var editor := BaseHub.open_loadout_3d()
	await _frames(3)
	var funds2 := int(BaseHub.view.get("funds", 0))
	var key := ""
	var id3 := ""
	for k: String in ["mount:helmet:nvg", "slot:sidearm", "slot:launcher", "slot:backpack"]:
		if editor == null or id3 != "" or not editor.on_worn(k):
			continue
		for id: String in editor.choices(k):
			var p := LoadoutEditor.price_of(id)
			if id3 == "" and editor.owned(id) <= 0 and p > 0 and p <= funds2:
				key = k
				id3 = id
	var price3 := LoadoutEditor.price_of(id3) if id3 != "" else 0
	var units_of := func() -> int: return int(Loadouts.units([], [Roster.json_safe(body.inventory.net_state)]).get(id3, 0)) if body and id3 != "" else 0
	var had3: int = units_of.call()
	if id3 != "":
		editor.pick_slot(key)
		editor.choose(id3)
		await _frames(2)
		question = _answer_confirm(editor, "Ok")
	var fitted := await _wait_until(func() -> bool: return id3 != "" and units_of.call() == had3 + 1 and int(BaseHub.view.get("funds", 0)) == funds2 - price3, 15.0)
	var settled := await _wait_until(func() -> bool: return editor != null and not editor.dirty(), 5.0)
	check(editor != null and question != "" and fitted and settled,
		"its 3D editor bought %s ($%d) on %s and fitted it through the host in one step; the draft is what it wears" % [id3, price3, key])
	if editor:
		editor.close()
	await _frames(2)
	# F-421 through the host: its M4 with a T-2 to an HK416 (the dot moves over), then to an SVD
	# (its own scope stays on, the T-2 goes to the stash loose); nothing listed missing.
	var gun_of := func() -> String:
		var g: Dictionary = Roster.json_safe(body.inventory.net_state) if body else {}
		var id := String(g.get("slots", {}).get("primary", ""))
		return "%s+%s" % [id, Optics.mounted_id(ItemDB.get_item(StringName(id)), g.get("slot_state", {}).get("primary", {}))] if id != "" else ""
	var loose_t2 := func() -> int:
		return (BaseHub.view.get("stash", []) as Array).filter(func(e: Dictionary) -> bool: return String(e.id) == "optic_t2").reduce(func(n: int, e: Dictionary) -> int: return n + int(e.count), 0)
	var me_key := "player:" + CLIENT_KEY
	if not String(gun_of.call()).begins_with("m4a1+"):
		BaseHub.request("loadout", [me_key, "slot", {"slot": "primary", "id": "m4a1"}])
		await _wait_until(func() -> bool: return String(gun_of.call()).begins_with("m4a1+"), 15.0)
	BaseHub.request("loadout", [me_key, "optic", {"slot": "primary", "id": "optic_t2"}])
	var dotted := await _wait_until(func() -> bool: return gun_of.call() == "m4a1+optic_t2", 15.0)
	await _seconds(0.5)
	notes.clear()
	BaseHub.request("loadout", [me_key, "slot", {"slot": "primary", "id": "hk416"}])
	var moved := await _wait_until(func() -> bool: return gun_of.call() == "hk416+optic_t2" and not notes.is_empty(), 15.0)
	check(dotted and moved and not notes.any(func(t: String) -> bool: return t.contains("Missing")),
		"its M4 with a T-2 to an HK416 through the host: the T-2 moved over, nothing missing (%s, %s)" % [gun_of.call(), notes])
	await _seconds(0.5)
	var loose_was: int = loose_t2.call()
	notes.clear()
	BaseHub.request("loadout", [me_key, "slot", {"slot": "primary", "id": "svd"}])
	var scoped := await _wait_until(func() -> bool: return gun_of.call() == "svd+optic_prism_4x" and not notes.is_empty() and int(loose_t2.call()) == loose_was + 1, 15.0)
	check(scoped and not notes.any(func(t: String) -> bool: return t.contains("Missing")),
		"then to an SVD: its own scope, the T-2 in the stash loose (%d -> %d in its view), nothing missing (%s, %s)" % [loose_was, loose_t2.call(), gun_of.call(), notes])
	_say(CLIENT_DONE)
	await _seconds(1.0)
	_say("CLIENT %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	_own_files_off()
	_log.close()
	Net.leave()
	_tree.quit(failures)


# --- Bits --------------------------------------------------------------------------------------

## What changed between two unit counts (_hub_units): {id: after - before}, changed ones only.
func _diff(before: Dictionary, after: Dictionary) -> Dictionary:
	var out := {}
	for id: String in after:
		if int(after[id]) != int(before.get(id, 0)):
			out[id] = int(after[id]) - int(before.get(id, 0))
	for id: String in before:
		if not after.has(id) and int(before[id]) != 0:
			out[id] = -int(before[id])
	return out


## The loadout confirm box over `screen` (UiKit.confirm, "Confirm"), answered: "Ok" or "Cancel".
## Returns its question (the labels' text), "" when none was up.
func _answer_confirm(screen: Node, button: String, tick := false) -> String:
	var box := screen.find_child("Confirm", false, false)
	if box == null:
		return ""
	var question := ""
	for l: Node in box.find_children("*", "Label", true, false):
		question += (l as Label).text + " "
	if tick:
		(box.find_child("DontAsk", true, false) as CheckBox).button_pressed = true
	(box.find_child(button, true, false) as Button).pressed.emit()
	return question.strip_edges()


func _cheapest(pool: Array) -> Dictionary:
	var best: Dictionary = pool[0]
	for c: Dictionary in pool:
		if int(c.fee) < int(best.fee):
			best = c
	return best


func _wait_until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not cond.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await _tree.process_frame
	return true


func _frames(n: int) -> void:
	for i in n:
		await _tree.process_frame


func _seconds(s: float) -> void:
	await _tree.create_timer(s).timeout
