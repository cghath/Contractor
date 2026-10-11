extends Node
## Headless AI scavenging (Scavenge, SquadAI's SCAVENGE intent; Captain 2026-10-11): what a
## soldier takes off a body (ammo for his own weapon up to his basic load, the medical items
## and grenades he lacks, a better plate or helmet only when calm, another rifle only when his
## own is dry, nothing past the load limit), that a dead player's gear is left alone, and the
## behaviour: out of contact a squadmate short of magazines goes to a dead enemy and takes
## them, one unit per body, contact stops it, and the command menu orders it or forbids it.
##   <voxel godot exe> --headless --path . res://tests/scavenge_test.tscn
## Exits with the number of failures.

var failures := 0
var level: CompoundLevel
var player: Soldier
var _spawned := 0


func _ready() -> void:
	GameState.zone_id = "test_scavenge" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	GameState.delete_save()
	CompoundLevel.spawn_ai = true
	get_tree().create_timer(300.0, true, false, true).timeout.connect(func() -> void:
		print("SCAVENGE TEST FAILED (timed out)")
		get_tree().quit(99))
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.ai.get_node_or_null(^"Golf") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	for id: StringName in [&"plate_carrier", &"m4a1", &"helmet"]:
		player.inventory.take(id)
	for s: Soldier in level.ai.get_children():
		if s.faction == &"hostile":
			s.queue_free()
	_place(player, Vector3(0, 0.1, 22))
	await _seconds(1.0)
	_test_ammo()
	_test_medical_and_grenades()
	_test_load_limit()
	_test_weapon_swap()
	_test_armor()
	_test_player_body()
	await _test_goes_and_takes()
	await _test_orders()
	await _test_contact_stops()
	GameState.delete_save()
	print("SCAVENGE TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- What gets taken ----------------------------------------------------------------

func _test_ammo() -> void:
	print("Ammunition")
	var rifleman := _role(Roles.RIFLEMAN)
	var marksman := _role(Roles.MARKSMAN)
	var dead := _dead_hostile(Vector3(-30, 0.1, -60))
	var full := Scavenge.best_pick(rifleman, dead, false)
	check(float(full.get("score", 0.0)) < SquadAI.SCAVENGE_MIN, "a rifleman with his basic load isn't worth sending (%.2f)" % float(full.get("score", 0.0)))
	var saved := rifleman.inventory.net_state.duplicate(true)
	_strip_mags(rifleman, &"mag_556", 1)
	var pick := Scavenge.best_pick(rifleman, dead, false)
	check(pick.get("id") == &"mag_556" and pick.kind == "stowed" and float(pick.score) >= SquadAI.SCAVENGE_MIN,
		"down to one spare magazine he goes for the body's 5.56 magazines first (%s)" % [pick])
	var want := 7 * 30 - rifleman.inventory.spare_rounds(&"mag_556") - rifleman.inventory.rounds_in(&"primary")
	check(int(pick.count) * 30 <= want + 29, "and only as many as his basic load lacks (%d for %d rounds)" % [int(pick.count), want])
	var before := rifleman.inventory.spare_rounds(&"mag_556")
	var on_body := dead.inventory.count_of(&"mag_556")
	var moved := Scavenge.apply(rifleman, dead, pick)
	check(moved > 0 and rifleman.inventory.spare_rounds(&"mag_556") > before and dead.inventory.count_of(&"mag_556") == on_body - moved,
		"taking them moves them from the body into his gear (%d)" % moved)
	rifleman.inventory.net_state = saved
	_strip_mags(marksman, &"mag_762", 0)
	var m_pick := Scavenge.best_pick(marksman, dead, false)
	check(m_pick.get("id") != &"mag_556", "a marksman out of 7.62 leaves 5.56 magazines his rifle can't take (%s)" % [m_pick.get("id", "nothing")])
	marksman.inventory.net_state = _fresh(marksman)
	dead.server_remove_body()


func _test_medical_and_grenades() -> void:
	print("Medical items and grenades")
	var rifleman := _role(Roles.RIFLEMAN)
	var dead := _dead_hostile(Vector3(-30, 0.1, -60))
	dead.inventory.take(&"tourniquet", 2)
	var saved := rifleman.inventory.net_state.duplicate(true)
	rifleman.inventory.take_medical(&"tourniquet")
	check(int(Scavenge.needs(rifleman).get(&"tourniquet", {}).get("want", 0)) == 1,
		"one of his two tourniquets used (holder and IFAK both count), he wants one more (%s)" % [Scavenge.needs(rifleman).get(&"tourniquet")])
	while rifleman.inventory.medical_count(&"tourniquet") > 0:
		rifleman.inventory.take_medical(&"tourniquet")
	while rifleman.inventory.remove_one(&"frag_grenade"):
		pass
	var pick := Scavenge.best_pick(rifleman, dead, false)
	check(pick.get("id") == &"tourniquet" and int(pick.count) == 2,
		"a rifleman whose tourniquets are used takes the two his kit has (holder and IFAK) before a grenade (%s)" % [pick])
	Scavenge.apply(rifleman, dead, pick)
	pick = Scavenge.best_pick(rifleman, dead, false)
	check(pick.get("id") == &"frag_grenade", "then the frag his kit is missing (%s)" % [pick.get("id", "nothing")])
	Scavenge.apply(rifleman, dead, pick)
	pick = Scavenge.best_pick(rifleman, dead, false)
	check(pick.get("id") != &"tourniquet" and pick.get("id") != &"frag_grenade", "and no more of either once he has his kit's count (%s)" % [pick.get("id", "nothing")])
	rifleman.inventory.net_state = saved
	dead.server_remove_body()


func _test_load_limit() -> void:
	print("Load limit")
	var rifleman := _role(Roles.RIFLEMAN)
	var dead := _dead_hostile(Vector3(-30, 0.1, -60))
	var saved := rifleman.inventory.net_state.duplicate(true)
	_strip_mags(rifleman, &"mag_556", 0)
	var spare := 0
	while rifleman.inventory.total_mass() < Scavenge.MAX_LOAD_KG and spare < 40:
		if rifleman.inventory.take(&"plate_pe_l3") == 0:
			break
		spare += 1
	var pick := Scavenge.best_pick(rifleman, dead, false)
	check(rifleman.inventory.total_mass() < Scavenge.MAX_LOAD_KG or pick.is_empty() or pick.kind != "stowed",
		"past %d kg he takes nothing more (%.1f kg, %s)" % [Scavenge.MAX_LOAD_KG, rifleman.inventory.total_mass(), pick.get("id", "nothing")])
	rifleman.inventory.net_state = saved
	dead.server_remove_body()


func _test_weapon_swap() -> void:
	print("Weapon swap")
	var rifleman := _role(Roles.RIFLEMAN)
	var marksman := _role(Roles.MARKSMAN)
	var dead := _dead_hostile(Vector3(-30, 0.1, -60))
	var saved := rifleman.inventory.net_state.duplicate(true)
	var pick := Scavenge.best_pick(marksman, dead, true, 0.9)
	check(pick.is_empty() or pick.kind != "weapon", "with rounds for his own rifle he keeps it")
	_dry(rifleman, &"mag_556")
	pick = Scavenge.best_pick(rifleman, dead, false)
	check(pick.get("id") == &"mag_556", "a dry M4 takes the body's 5.56 magazines (the MK18's fit it) rather than its rifle (%s)" % [pick.get("id", "nothing")])
	_part_use(dead, &"mag_556", 10)
	pick = Scavenge.best_pick(rifleman, dead, false)
	check(pick.get("id") == &"mag_556", "even when the body's magazines are part used (%s)" % [pick.get("id", "nothing")])
	rifleman.inventory.net_state = saved
	var m_saved := marksman.inventory.net_state.duplicate(true)
	_dry(marksman, &"mag_762")
	pick = Scavenge.best_pick(marksman, dead, false)
	check(pick.get("kind") == "weapon" and pick.id == &"mk18", "a marksman with no 7.62 left at all takes the body's loaded rifle (%s)" % [pick])
	var mine: StringName = marksman.inventory.slots[&"primary"]
	check(Scavenge.apply(marksman, dead, pick) == 1 and marksman.inventory.slots[&"primary"] == &"mk18" and dead.inventory.slots[&"primary"] == mine,
		"and leaves his empty one on the body (%s, body has %s)" % [marksman.inventory.slots[&"primary"], dead.inventory.slots[&"primary"]])
	check(marksman.active_slot == &"primary", "and fights with it, not his sidearm (%s)" % marksman.active_slot)
	pick = Scavenge.best_pick(marksman, dead, false)
	check(pick.get("id") == &"mag_556", "then its magazines (%s)" % [pick.get("id", "nothing")])
	marksman.inventory.net_state = m_saved
	dead.server_remove_body()


## Leaves `rounds` in each `mag` stowed on `s`.
func _part_use(s: Soldier, mag: StringName, rounds: int) -> void:
	for container in s.inventory.search_containers():
		for entry: Dictionary in s.inventory.containers[container]:
			if entry.id == mag:
				var state: Dictionary = entry.get("state", {}).duplicate(true)
				state.rounds = rounds
				entry["state"] = state
	s.inventory._commit()


## Empties `s`'s primary and takes away its magazines (`mag`).
func _dry(s: Soldier, mag: StringName) -> void:
	_strip_mags(s, mag, 0)
	var state := s.inventory.state_of(&"primary").duplicate(true)
	state.rounds = 0
	s.inventory.slot_state[&"primary"] = state
	s.inventory._commit()


func _test_armor() -> void:
	print("Armor")
	var rifleman := _role(Roles.RIFLEMAN)
	var dead := _dead_hostile(Vector3(-30, 0.1, -60))
	var saved := rifleman.inventory.net_state.duplicate(true)
	var front: StringName = rifleman.inventory.slots[&"plate_front"]
	var cracked := rifleman.inventory.state_of(&"plate_front").duplicate(true)
	cracked["integrity"] = 0.05
	rifleman.inventory.slot_state[&"plate_front"] = cracked
	rifleman.inventory._commit()
	var hot := Scavenge.best_pick(rifleman, dead, false)
	check(hot.is_empty() or hot.kind != "plate", "with contact recent he doesn't open his carrier to swap a plate")
	dead.inventory.take(&"plate_ceramic_l4")  # a whole IV plate stowed in the body's pack
	var pick := Scavenge.best_pick(rifleman, dead, true)
	check(pick.get("kind") == "plate" and pick.get("id") == &"plate_ceramic_l4",
		"calm, he swaps his shattered %s for the body's intact plate (%s)" % [front, pick])
	check(Scavenge.apply(rifleman, dead, pick) == 1 and ArmorRules.integrity(rifleman.inventory.state_of(pick.into)) >= 1.0
		and dead.inventory.count_of(front) + (1 if dead.inventory.slots.values().has(front) else 0) >= 1,
		"his cracked plate stays on the body")
	rifleman.inventory.net_state = saved
	dead.server_remove_body()


func _test_player_body() -> void:
	print("A dead player's gear")
	var rifleman := _role(Roles.RIFLEMAN)
	var dead := _dead_hostile(Vector3(-30, 0.1, -60))
	dead.has_gear_marker = true
	check(not SquadAI.of(rifleman)._may_scavenge(dead), "a dead player's body (with its gear marker) is left for the player")
	check(squad().order_scavenge(player, dead.global_position, PackedStringArray()) != "", "and the command menu won't send anyone to it")
	dead.server_remove_body()


# --- Behaviour ----------------------------------------------------------------------

func _test_goes_and_takes() -> void:
	print("Going through a body")
	var rifleman := _role(Roles.RIFLEMAN)
	var ai := SquadAI.of(rifleman)
	_strip_mags(rifleman, &"mag_556", 1)
	var dead := _dead_hostile(player.global_position + Vector3(3, 0, -3))
	var mags_before := rifleman.inventory.count_of(&"mag_556")
	var on_body := dead.inventory.count_of(&"mag_556")
	var ground := _item_ids()
	var statuses := {}
	var claims := [0]
	var watch := func() -> bool:
		statuses[rifleman.ai_status] = true
		var looters := _squad().filter(func(s: Soldier) -> bool: return SquadAI.of(s).loot_body == dead).size()
		claims[0] = maxi(claims[0], looters)
		return rifleman.inventory.count_of(&"mag_556") > mags_before and ai.loot_body == null
	var done := await _wait_until(watch, 40.0)
	check(done, "short of magazines, a rifleman goes to a dead enemy nearby and takes some (%d -> %d; %s)"
		% [mags_before, rifleman.inventory.count_of(&"mag_556"), statuses.keys()])
	check(statuses.has("Searching the body"), "the HUD shows him searching the body")
	check(claims[0] <= 1, "one unit at a time on a body (%d)" % claims[0])
	check(dead.inventory.count_of(&"mag_556") < on_body and _new_items(ground, dead.global_position, 10.0).is_empty(),
		"what he took came off the body, nothing went on the ground")
	check(dead.has_gear() and dead.inventory.slots[&"primary"] != &"", "the rest stays on the body for players (its rifle too)")
	check(dead.scavenged_by == null or dead.scavenged_by != rifleman or ai.loot_body == null, "done, he lets go of it")
	dead.server_remove_body()


func _test_orders() -> void:
	print("Orders")
	var rifleman := _role(Roles.RIFLEMAN)
	var ai := SquadAI.of(rifleman)
	_strip_mags(rifleman, &"mag_556", 1)
	squad().set_scavenge(player, false, PackedStringArray([String(rifleman.name)]))
	var dead := _dead_hostile(player.global_position + Vector3(-3, 0, -3))
	await _seconds(4.0)
	check(ai.loot_body == null and ai.intent != SquadAI.Intent.SCAVENGE, "told not to scavenge, he leaves the body alone (%s)" % rifleman.ai_status)
	var why := squad().order_scavenge(player, dead.global_position + Vector3(0.5, 0, 0), PackedStringArray([String(rifleman.name)]))
	check(why == "" and ai.scavenge_order == dead, "\"Scavenge that body\" sends him to the body under the crosshair (%s)" % why)
	var went := await _wait_until(func() -> bool: return ai.loot_body == dead or rifleman.inventory.count_of(&"mag_556") > 1, 20.0)
	check(went, "and he goes, even with scavenging forbidden (%s)" % rifleman.ai_status)
	await _wait_until(func() -> bool: return ai.loot_body == null and ai.scavenge_order == null, 30.0)
	squad().set_scavenge(player, true, PackedStringArray())
	check(squad().order_scavenge(player, Vector3(60, 0, 60), PackedStringArray()) == "Look at a body", "with no body there the order says so")
	dead.server_remove_body()


func _test_contact_stops() -> void:
	print("Contact")
	var rifleman := _role(Roles.RIFLEMAN)
	var ai := SquadAI.of(rifleman)
	_strip_mags(rifleman, &"mag_556", 0)
	var dead := _dead_hostile(player.global_position + Vector3(3, 0, 3))
	var started := await _wait_until(func() -> bool: return ai.loot_body == dead, 20.0)
	check(started, "he starts on the body (%s)" % rifleman.ai_status)
	rifleman.threat_pos = rifleman.global_position + Vector3(20, 0, 0)
	rifleman.threat_time = Soldier._now()
	await _seconds(1.5)
	check(ai.loot_body == null and dead.scavenged_by != rifleman, "contact: he drops the body and fights (%s)" % rifleman.ai_status)
	rifleman.inventory.net_state = _fresh(rifleman)
	dead.server_remove_body()


# --- Helpers ------------------------------------------------------------------------

func squad() -> Squad:
	return level.squad_for(&"friendly")


func _squad() -> Array:
	return level.ai.get_children().filter(func(s: Node) -> bool: return s is Soldier and s.faction == &"friendly" and not s.is_queued_for_deletion() and not s.vitals.is_dead())


func _role(role: StringName) -> Soldier:
	for s: Soldier in _squad():
		if s.role == role:
			return s
	return null


## A freshly killed enemy with HOSTILE_LOADOUT lying at `pos`.
func _dead_hostile(pos: Vector3) -> Soldier:
	_spawned += 1
	var s := level.spawn_soldier({"name": "ScavHostile%d" % _spawned, "faction": "hostile", "variant": "urban", "pos": pos,
		"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(s).set_physics_process(false)
	s.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.INTERMEDIATE})
	return s


## Removes `id` magazines from `s` until `keep` are left.
func _strip_mags(s: Soldier, id: StringName, keep: int) -> void:
	while s.inventory.count_of(id) > keep and s.inventory.remove_one(id):
		pass


## `s`'s role kit as an inventory state (to put things back after a test).
func _fresh(s: Soldier) -> Dictionary:
	var inv := Inventory.new()
	Roles.apply_kit(inv, s.role)
	var state := inv.net_state.duplicate(true)
	inv.free()
	return state


func _item_ids() -> Dictionary:
	var out := {}
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		out[node.get_instance_id()] = true
	return out


func _new_items(before: Dictionary, pos: Vector3, radius: float) -> Array:
	var out := []
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if not before.has(node.get_instance_id()) and not node.is_queued_for_deletion() \
				and Vector2((node as Node3D).global_position.x - pos.x, (node as Node3D).global_position.z - pos.z).length() <= radius:
			out.append(String((node as WorldItem).item_id))
	return out


func _place(s: Soldier, pos: Vector3) -> void:
	s.global_position = pos
	s.velocity = Vector3.ZERO


func _wait_until(cond: Callable, timeout: float) -> bool:
	var left := timeout
	while left > 0.0:
		if cond.call():
			return true
		await _seconds(0.25)
		left -= 0.25
	return cond.call()


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
