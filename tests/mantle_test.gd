extends Node
## Mantle (SoldierMovement.try_mantle; Captain 2026-10-16): on the vehicle range, the host's
## player faces blocks of a few heights and presses jump:
## - a 1.0 m and a 1.7 m block: climbed, on top, standing, in about MANTLE_BASE_S + h x
##   MANTLE_PER_M_S, paying leg stamina, the weapon down and no firing on the way;
## - a 0.3 m kerb: no mantle (a step-up's or a jump's);
## - a 2.3 m wall: no mantle (out of reach);
## - a 1.0 m block under a ceiling 0.5 m over it: no mantle (no room on top);
## - prone: no mantle;
## - wearing a working LX-3 Assist Frame (ExoFrame.climb_assist_m), the 2.3 m wall is climbed;
## - the squad's "Climb up there" order (Squad.order_climb): an AI squadmate walks to the block,
##   climbs it and holds on top; with the frame it climbs the 2.3 m wall; without, at the wall
##   it can't climb, the order ends where it stands.
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
	await _running_mantle()
	await _prone()
	player.inventory.take(&"exo_frame_light")
	await get_tree().physics_frame
	check(absf(player.movement.mantle_reach() - SoldierMovement.MANTLE_MAX_M - 1.3) < 0.01, "the LX-3's legs reach 1.3 m higher (%.1f m)" % player.movement.mantle_reach())
	await _case("2.3 m block (a roof) in the LX-3", 2.3, -1.0, true)
	await _leap_over_wall()
	player.inventory.unequip(ExoFrame.SLOT)
	await _ai_climb("1.7 m block", 1.7, false, true)
	await _ai_climb("2.3 m wall in the LX-3", 2.3, true, true)
	await _ai_climb("2.3 m wall", 2.3, false, false)
	await _follow_onto_roof()
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


## Captain, 2026-10-17 ("matle needs to be more fluid, not just when youre standing still"):
## running at the block, 1.6 m short of its face, it climbs on the move (the ledge looked for
## further out at speed), quicker than from a stand, and goes on over the top still moving.
func _running_mantle() -> void:
	var ground := _course(1.0, -1.0)
	await get_tree().physics_frame
	await _stand_facing(ground)
	player.global_position = AT + Vector3(0, ground + 0.05, 0.6)  # 1.6 m short of the face
	player.velocity = Vector3(0, 0, -5.0)
	var started := false
	for i in 30:
		await get_tree().physics_frame
		player.velocity = Vector3(player.velocity.x, player.velocity.y, -5.0)  # still running at it
		if player.movement.try_mantle():
			started = true
			break
	check(started, "running at a 1.0 m block: it climbs on the move")
	if not started:
		return
	var t0 := Time.get_ticks_msec()
	await _wait_for(func() -> bool: return not player.movement.mantling, 3.0)
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	check(took < SoldierMovement.MANTLE_BASE_S + SoldierMovement.MANTLE_PER_M_S + 0.05, "quicker than from a stand (%.2f s)" % took)
	check(Vector2(player.velocity.x, player.velocity.z).length() > 2.0 and player.global_position.y > ground + 0.8,
		"on top and still going (%.1f m/s)" % Vector2(player.velocity.x, player.velocity.z).length())


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
	var leap := ExoFrame.working(player.inventory)  # the LX-3 leaps: one quick arc
	var want := (SoldierMovement.LEAP_BASE_S + SoldierMovement.LEAP_PER_M_S * h) if leap else (SoldierMovement.MANTLE_BASE_S + SoldierMovement.MANTLE_PER_M_S * h)
	check(absf(took - want) < 0.35, "%s: %s in %.2f s (about %.2f)" % [label, "leapt" if leap else "took", took, want])
	await _seconds(0.3)
	var feet := player.global_position.y - ground
	check(absf(feet - h) < 0.15 and player.global_position.z < AT.z - 1.0, "%s: on top (feet %.2f m up, z %.2f)" % [label, feet, player.global_position.z - AT.z])
	check(player.movement.stance == SoldierMovement.Stance.STAND_HIGH, "%s: standing on top" % label)
	check(player.movement.stamina < stamina - 0.01, "%s: it cost leg stamina (%.2f -> %.2f)" % [label, stamina, player.movement.stamina])
	check(player.inventory.rounds_in(player.active_slot) == rounds, "%s: nothing fired on the way" % label)


## The squad's climb order for an AI squadmate 1.5 m behind the player's spot: up `h` (in the
## LX-3 if `exo`), or (`climbs` false) not, the order ending at the wall.
func _ai_climb(label: String, h: float, exo: bool, climbs: bool) -> void:
	var ground := _course(h, -1.0)
	player.global_position = AT + Vector3(4, ground + 0.05, 2)  # out of the way
	await get_tree().physics_frame
	var mate := level.spawn_soldier({"name": "Climber", "faction": "friendly", "variant": "multicam", "pos": AT + Vector3(0, ground + 0.05, 1.5),
		"loadout": ["m4a1"], "role": "rifleman", "team": 0, "slot": 1, "combat": 0.5, "discipline": 0.6, "guard": false})
	await _wait_for(func() -> bool: return SquadAI.of(mate) != null and SquadAI.of(mate)._ready_done and mate.is_on_floor(), 5.0)
	if exo:
		mate.inventory.take(&"exo_frame_light")
	await _seconds(0.3)
	var top := AT + Vector3(0, ground + h, -2.0)
	player.server_squad_command("climb", top, PackedStringArray([String(mate.name)]))
	var ai := SquadAI.of(mate)
	check(StringName(ai.ordered.get("kind", &"")) == &"climb", "AI, %s: the climb order taken (%s)" % [label, ai.status_text()])
	var saw_mantle := [false]
	await _wait_for(func() -> bool:
		saw_mantle[0] = saw_mantle[0] or mate.movement.mantling
		return ai.ordered.is_empty(), 20.0)
	var feet := mate.global_position.y - ground
	if climbs:
		check(saw_mantle[0] and absf(feet - h) < 0.2, "AI, %s: climbed it, on top (feet %.2f m up)" % [label, feet])
		check(ai.ordered.is_empty() and ai.order == Squad.Order.HOLD, "AI, %s: and holds up there (%s)" % [label, ai.status_text()])
	else:
		check(not saw_mantle[0] and feet < 0.3 and ai.ordered.is_empty(), "AI, %s: out of reach, the order ends at the wall (feet %.2f m up, %.1f m from the spot, %s)" % [label, feet, Vector2(mate.global_position.x - top.x, mate.global_position.z - top.z).length(), ai.status_text()])
	mate.queue_free()
	await get_tree().physics_frame


## In the LX-3, a 2.2 m compound wall 0.25 m thick: the leap clears it and lands on the far side
## (Captain, 2026-10-17: "we jump over the compound walls, not on top of them").
func _leap_over_wall() -> void:
	for b in _blocks:
		b.queue_free()
	_blocks.clear()
	var ground := level.ground_point(AT).y
	_blocks.append(_box(Vector3(12, 1, 12), AT + Vector3(0, ground - 0.5, 0)))
	_blocks.append(_box(Vector3(3, 2.2, 0.25), AT + Vector3(0, ground + 1.1, -1.125)))  # its face 0.6 m ahead
	await get_tree().physics_frame
	await _stand_facing(ground)
	check(player.movement.try_mantle(), "2.2 m compound wall in the LX-3: a leap")
	await _wait_for(func() -> bool: return not player.movement.mantling, 4.0)
	await _seconds(0.3)
	var feet := player.global_position.y - ground
	check(player.movement.last_over and player.global_position.z < AT.z - 1.4 and feet < 0.3,
		"over it, landing on the far side (feet %.2f m up, z %.2f past the wall's face)" % [feet, -(player.global_position.z - (AT.z - 1.0))])


## Captain, 2026-10-17: "make sure squaddies also follow you onto the rooftop you jump onto if
## they can": the player up on a 1.7 m block (no stairs), a squadmate following him climbs up too.
func _follow_onto_roof() -> void:
	var ground := _course(1.7, -1.0)
	await get_tree().physics_frame
	player.global_position = AT + Vector3(0, ground + 1.75, -2.0)  # on top of the block
	player.velocity = Vector3.ZERO
	var mate := level.spawn_soldier({"name": "Follower", "faction": "friendly", "variant": "multicam", "pos": AT + Vector3(0, ground + 0.05, 2.5),
		"loadout": ["m4a1"], "role": "rifleman", "team": 0, "slot": 1, "combat": 0.5, "discipline": 0.6, "guard": false})
	await _wait_for(func() -> bool: return SquadAI.of(mate) != null and SquadAI.of(mate)._ready_done and mate.is_on_floor() and player.is_on_floor(), 5.0)
	var squad := level.squad_for(&"friendly")
	squad.give_order(player, Squad.Order.FOLLOW, player.global_position, PackedStringArray([String(mate.name)]))
	var up := await _wait_for(func() -> bool: return mate.global_position.y - ground > 1.5, 25.0)
	var ai := SquadAI.of(mate)
	check(up, "a squadmate following the player up on a 1.7 m roof climbs up after him (feet %.2f m up, %s)" % [mate.global_position.y - ground, ai.status_text()])
	mate.queue_free()
	await get_tree().physics_frame


func _prone() -> void:
	var ground := _course(1.0, -1.0)
	await get_tree().physics_frame
	await _stand_facing(ground)
	player.movement.set_stance(SoldierMovement.Stance.PRONE)
	await _seconds(0.3)
	check(not player.movement.try_mantle(), "prone: no mantle")
	player.movement.set_stance(SoldierMovement.Stance.STAND_HIGH)
