extends Node
## Headless checks of the loadout menu at the FOB (Captain, 2026-10-14: "we need a menu for
## equipping yourself better and your squadmates how you want to as well"; docs/loadout_menu.md):
##   <voxel godot exe> --headless --path . res://tests/loadout_test.tscn
## The rules first (every template edit rebuilt from a pool conserves it unit by unit; a role
## kit takes only what the pool has and names the rest), then a hub session: changes asked
## through BaseHub.request conserve the armory's items and the kits together, a saved standing
## loadout is what Restock refills to, a role preset with a short stash says what's missing, a
## player can't change another player's kit, the screen fits every window size and UI scale,
## and a client's requests go through the host (a second process joins the hub).
##
## The client is this scene again with `-- --join 127.0.0.1 --log <path>`; it writes its checks
## to the log the host prints. Exits with the number of failures.

const SEED := 5151
## Items the test stash holds besides the starting stash.
const EXTRA_STASH := [["smoke_grenade", 4], ["m110", 1], ["mag_762", 6], ["optic_holo", 2], ["helmet_heavy", 1], ["mag_9mm", 4], ["m17", 1],
	["suppressor_rifle", 1], ["grip_vertical", 1], ["nvg_gen2", 1], ["pouch_mag_double", 2]]
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
	print("LOADOUT TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
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
	# The host can't change another player's kit (a client is peer 2 here).
	check(BaseHub.server_loadout(2, me, "add", {"id": "smoke_grenade"}).contains("their own kit"), "a client's request on the host's kit is refused")
	await _test_fit(ids)
	await _test_client(ids)


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
	Economy.add_cash(price + 100, "test: an NVG")
	before = _hub_units()
	BaseHub.request("loadout", [mid, "template", {"template": t, "buy": true}])
	await _frames(3)
	var g: Dictionary = Roster.json_safe((level as BaseLevel).muster_soldier(mid).inventory.net_state)
	check(GearMounts.on(ItemDB.get_item(&"helmet"), g.slot_state.get("helmet", {}), "nvg") == "nvg_gen3" and Economy.cash() == 100
		and int(_hub_units().get("nvg_gen3", 0)) == int(before.get("nvg_gen3", 0)) + 1, "the editor's draft: the NVG bought ($%d) and on his helmet" % price)
	_notes.clear()
	BaseHub.request("loadout", [me, "kit_delete", {"name": "Quiet rifleman"}])
	await _frames(2)
	check(KitLibrary.names(BaseHub.roster()).is_empty(), "a kit deletes")


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

func _test_client(ids: Array) -> void:
	print("A client's loadout requests go through the host")
	var log_path := ProjectSettings.globalize_path("user://loadout_test_client%s.log" % tag)
	if FileAccess.file_exists(log_path):
		DirAccess.remove_absolute(log_path)
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/loadout_test.tscn", "--", "--join", "127.0.0.1",
		"--log", log_path, "--member", String(ids[2])]
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
	check(_hub_units() == before, "and nothing was made or lost on the way")
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
	_say(CLIENT_DONE)
	await _seconds(1.0)
	_say("CLIENT %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	_log.close()
	Net.leave()
	_tree.quit(failures)


# --- Bits --------------------------------------------------------------------------------------

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
