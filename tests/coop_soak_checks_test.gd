extends Node
## Headless checks for the co-op soak bots' own rules (tests/coop_soak.gd), on a real hosted
## zone with no garrison: the planned knock-out stays off when it would stack on real
## casualties (S1 review: a medic already down from fire left the victim untreated, since buddy
## aid skips the planned victim), the medic counts as lost once down, and the advance ends at
## the first casualty (S1, S0736).
##   <voxel godot exe> --headless --path . res://tests/coop_soak_checks_test.tscn
## Exits with the number of failures.

const Probe := preload("res://tests/coop_soak_probe.gd")

var failures := 0
var level: CompoundLevel


func _ready() -> void:
	GameState.zone_id = "test_coop_soak_checks" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		print("COOP_SOAK_CHECKS TEST FAILED (timed out)")
		get_tree().quit(99))
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	var host: Soldier = level.players.get_node(^"1")
	host.set_physics_process(false)
	var at := host.global_position
	var medic := _spawn("Medic", at + Vector3(2.0, 0.0, 0.0))
	var victim := _spawn("Victim", at + Vector3(-2.0, 0.0, 0.0))
	var probe: Probe = Probe.new()
	add_child(probe)
	probe.stand_ins = {5: medic, 6: victim}
	await get_tree().process_frame

	check(probe._knockout_skip(6, 5) == "", "everyone up: the knock-out goes ahead (%s)" % probe._knockout_skip(6, 5))
	check(probe._knockout_skip(6, 0) != "", "no medic in the zone: no knock-out (S0755)")
	check(probe._knockout_skip(6, 7) != "", "a medic not in the zone: no knock-out")
	check(not probe._medic_lost(5), "an up medic is not lost")
	medic.vitals.downed = true
	check(probe._knockout_skip(6, 5) != "", "the medic already down from fire: no knock-out (S1 review)")
	check(probe._medic_lost(5), "a downed medic is lost: the casualty goes to buddy aid")
	medic.vitals.downed = false
	victim.vitals.downed = true
	check(probe._knockout_skip(6, 5) != "", "the victim already down: no knock-out on top")
	victim.vitals.downed = false
	check(probe._knockout_skip(6, 5) == "", "all back up: the knock-out goes ahead again")
	check(not probe._contact_while_advancing(), "nobody hurt and no hostile: no contact")
	host.vitals.downed = true
	check(probe._players_down() == 1, "a player down from fire counts (%d)" % probe._players_down())
	check(probe._knockout_skip(6, 5) != "", "a player already down from fire: no knock-out (S0792)")
	check(probe._me() != null and probe._contact_while_advancing(), "a player down: the advance is over (S0736)")
	check(probe._advance_done(at + Vector3(0.0, 0.0, 500.0)), "a player down 500 m short: the advance still ends")
	host.vitals.downed = false
	GameState.delete_save()
	print("COOP_SOAK_CHECKS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func _spawn(callsign: String, pos: Vector3) -> Soldier:
	var s := level.spawn_soldier({"name": callsign, "faction": "friendly", "variant": "multicam", "pos": pos,
		"loadout": ["plate_carrier", "m4a1"], "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED  # staged by hand
	return s


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1
