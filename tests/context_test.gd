extends Node
## Headless checks for the contextual menus (docs/combined_arms.md 5.5, phase C6): ContextResolver's
## table, row by row, the one key's default, recent-first and "More..." always last. Pure.
##   <voxel godot exe> --headless --path . res://tests/context_test.tscn
## Exits with the number of failures.

var failures := 0


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("CONTEXT TEST FAILED (timed out)")
		get_tree().quit(99))
	ContextResolver.recent = {}
	_test_table()
	_test_situation()
	_test_recent()
	_test_hc_first()
	print("CONTEXT TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _ids(ctx: Dictionary) -> Array:
	return ContextResolver.resolve(ctx).map(func(o: Dictionary) -> String: return String(o.id))


func _labels(ctx: Dictionary) -> Array:
	return ContextResolver.resolve(ctx).map(func(o: Dictionary) -> String: return String(o.label))


func _test_table() -> void:
	print("The 5.5 table")
	check(_ids({"kind": "squadmate"}).slice(0, 5) == ["follow", "hold", "move", "heal", "swap_kit"], "a squadmate: Follow, Hold, Move here, Heal, Swap kit")
	check(_ids({"kind": "hero_squad"}).slice(0, 5) == ["hc_move", "hc_defend", "hc_attack", "hc_sbf", "hc_regroup"], "a hero squad: Move, Defend, Attack, Support by fire, Regroup")
	var allied := _ids({"kind": "allied_unit"})
	check(allied[0] == "req_suppress" and "req_sitrep" in allied and "req_fire" in allied and "req_pickup" in allied, "an allied unit: requests, suppress first by default")
	var door := _ids({"kind": "door", "doors": ["charge", "kick"]})
	check(door[0] == "stack" and "breach_charge" in door and "breach_kick" in door and "clear" in door and "engage_building" not in door, "a door: Stack up, the door's own breaches, Clear")
	check("engage_building" in _ids({"kind": "building", "armour_paired": true}), "with armour paired: Engage the building")
	check(_ids({"kind": "casualty"}).slice(0, 4) == ["treat", "carry", "call_medic", "casevac"], "a casualty: Treat, Carry, Call a medic, CASEVAC")
	check(_ids({"kind": "our_vehicle"}).slice(0, 4) == ["get_in", "drive", "take_gun", "command"], "our vehicle: Get in, Drive, Take the gun, Command")
	check(_ids({"kind": "allied_armour"}).slice(0, 2) == ["req_armour", "ride"], "allied armour: Request armour support, Ride with them")
	check(_ids({"kind": "enemy"}).slice(0, 4) == ["target", "suppress", "tag", "report"], "an enemy: Target, Suppress, Tag, Report")
	check(_ids({"kind": "enemy", "selected": "gun_team"})[0] == "gun_cover", "an enemy with a gun team selected: Place gun to cover it first")
	check(_ids({"kind": "gun_team"}).slice(0, 3) == ["gun_here", "gun_facing", "gun_pack"], "a gun team: Set up here, Facing, Pack up")
	var ground := _ids({"kind": "ground"})
	check(ground.slice(0, 3) == ["move", "hold_here", "mark"] and "gun_here" in ground, "ground: Move, Hold here, Mark, Place the gun")
	check(_ids({"kind": "crew", "seat_role": "driver"}).has("bail") and _ids({"kind": "crew", "seat_role": "driver"}).has("pop_smoke"), "the crew wheel: Pop smoke, Bail out")
	for k: String in ContextResolver.KINDS:
		var all := ContextResolver.resolve({"kind": k})
		if all.is_empty() or String(all[-1].id) != "more":
			check(false, "%s: More... last" % k)
			return
	check(true, "every kind ends with More... (the full command menu)")


func _test_situation() -> void:
	print("The situation")
	check(_ids({"kind": "allied_unit", "contact": true})[0] == "req_suppress", "in contact: suppress first")
	check(_ids({"kind": "allied_unit", "casualty_near": true})[0] == "req_medic", "a casualty near: medic first")
	check(String(ContextResolver.default_of({"kind": "squadmate"}).id) == "follow", "the one key's default is the top option")
	check(String(ContextResolver.default_of({"kind": "ground", "selected": "gun_team"}).id) == "gun_here", "ground with a gun team: place the gun first")


func _test_recent() -> void:
	print("Recently used first")
	var rec := {}
	ContextResolver.used("squadmate", "heal", rec)
	ContextResolver.used("squadmate", "hold", rec)
	var ids := _ids({"kind": "squadmate", "recent": rec})
	check(ids.slice(0, 3) == ["hold", "heal", "follow"], "the last used first, then the one before")
	for id: String in ["move", "follow", "swap_kit", "heal"]:
		ContextResolver.used("squadmate", id, rec)
	check((rec.squadmate as Array).size() == ContextResolver.RECENT, "at most %d remembered" % ContextResolver.RECENT)
	check(_ids({"kind": "enemy", "recent": rec})[0] == "target", "each kind keeps its own")


func _test_hc_first() -> void:
	print("The map's order bar")
	var rec := {}
	check(ContextResolver.hc_first("enemy", rec) == ["attack", "sbf"], "over an enemy marker: Attack, Support by fire")
	check(ContextResolver.hc_first("ground", rec) == ["move", "defend"], "open ground: Move, Defend")
	ContextResolver.used("map:ground", "regroup", rec)
	check(ContextResolver.hc_first("ground", rec)[0] == "regroup", "the last order given there comes first")
