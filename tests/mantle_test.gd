extends Node
## Mantle (SoldierMovement.try_mantle; Captain 2026-10-16): on the vehicle range, the host's
## player faces blocks of a few heights and presses jump:
## - a 1.0 m and a 1.7 m block: climbed, on top, standing, in about MANTLE_BASE_S + h x
##   MANTLE_PER_M_S, paying leg stamina, the weapon down and no firing on the way;
## - a 0.3 m kerb: no mantle (a step-up's or a jump's);
## - a 2.3 m wall: no mantle (out of reach);
## - a 1.0 m block under a ceiling 0.5 m over it: no mantle (no room on top);
## - prone: no mantle.
##   <godot> --headless --path . res://tests/mantle_test.tscn

const AT := Vector3(40, 0, -40)

var failures := 0
var level: VehicleRange
var main: Node
var player: Soldier
var _blocks: Array[Node] = []


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_mantle" + tag
	Campaign.campaign_id = "test_mantle" + tag
	CompoundLevel.spawn_ai = false
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("MANTLE TEST FAILED (timed out)")
		get_tree().quit(99))
	GameState.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	level = LevelSwitch.load_level(main, {"level": "range"}) as VehicleRange
	main.menu.host()
	check(level != null and Net.is_hosting(), "hosting the vehicle range")
	if level == null or not Net.is_hosting():
		_finish()
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 5.0)
	player = level.players.get_node(^"1")
	await _case("1.0 m block", 1.0, -1.0, true)
	await _case("1.7 m block", 1.7, -1.0, true)
	await _case("0.3 m kerb", 0.3, -1.0, false)
	await _case("2.3 m wall", 2.3, -1.0, false)
	await _case("1.0 m block under a roof", 1.0, 0.5, false)
	await _prone()
	_finish()


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _finish() -> void:
	GameState.delete_save()
	print("MANTLE TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	Net.leave()
	get_tree().quit(failures)


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	return condition.call()


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


## A floor plate, and a block `h` tall 1 m ahead of where the player stands facing -z
## (`roof` > 0: a slab that far over the block's top too).
func _course(h: float, roof: float) -> float:
	for b in _blocks:
		b.queue_free()
	_blocks.clear()
	var ground := level.ground_point(AT).y
	_blocks.append(_box(Vector3(12, 1, 12), AT + Vector3(0, ground - 0.5, 0)))
	_blocks.append(_box(Vector3(3, h, 2), AT + Vector3(0, ground + h * 0.5, -2.0)))
	if roof > 0.0:
		_blocks.append(_box(Vector3(3, 2.0, 2), AT + Vector3(0, ground + h + roof + 1.0, -2.0)))  # a thick ceiling: its own top out of reach
	return ground


func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	b.add_child(col)
	level.add_child(b)
	b.global_position = at
	return b


func _stand_facing(ground: float) -> void:
	player.global_transform = Transform3D(Basis(), AT + Vector3(0, ground + 0.05, -0.4))  # faces -z, the block's face 0.6 m ahead
	player.velocity = Vector3.ZERO
	player.movement.set_stance(SoldierMovement.Stance.STAND_HIGH)
	player.movement.stamina = 1.0
	await _wait_for(func() -> bool: return player.is_on_floor(), 2.0)
	await _seconds(0.2)


func _case(label: String, h: float, roof: float, climbs: bool) -> void:
	var ground := _course(h, roof)
	await get_tree().physics_frame
	await _stand_facing(ground)
	var stamina := player.movement.stamina
	var started := player.movement.try_mantle()
	check(started == climbs, "%s: %s" % [label, "climbed" if climbs else "no mantle"])
	if not started:
		return
	check(player.movement.mantling, "%s: mantling" % label)
	var rounds := player.inventory.rounds_in(player.active_slot)
	var t0 := Time.get_ticks_msec()
	await _wait_for(func() -> bool: return not player.movement.mantling, 4.0)
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	var want := SoldierMovement.MANTLE_BASE_S + SoldierMovement.MANTLE_PER_M_S * h
	check(absf(took - want) < 0.35, "%s: took %.2f s (about %.2f)" % [label, took, want])
	await _seconds(0.3)
	var feet := player.global_position.y - ground
	check(absf(feet - h) < 0.15 and player.global_position.z < AT.z - 1.0, "%s: on top (feet %.2f m up, z %.2f)" % [label, feet, player.global_position.z - AT.z])
	check(player.movement.stance == SoldierMovement.Stance.STAND_HIGH, "%s: standing on top" % label)
	check(player.movement.stamina < stamina - 0.01, "%s: it cost leg stamina (%.2f -> %.2f)" % [label, stamina, player.movement.stamina])
	check(player.inventory.rounds_in(player.active_slot) == rounds, "%s: nothing fired on the way" % label)


func _prone() -> void:
	var ground := _course(1.0, -1.0)
	await get_tree().physics_frame
	await _stand_facing(ground)
	player.movement.set_stance(SoldierMovement.Stance.PRONE)
	await _seconds(0.3)
	check(not player.movement.try_mantle(), "prone: no mantle")
	player.movement.set_stance(SoldierMovement.Stance.STAND_HIGH)
