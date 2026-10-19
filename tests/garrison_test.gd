extends Node3D
## Site garrisons hold their walls (Captain, 2026-10-19: "troops in compounds shouldnt abandon
## compounds to attack the player and his ai ... they should wait in ambush for us or try to
## escape if they believe they are severely outgunned"): GarrisonPost. In the test zone with AI:
## the compound's garrison gets a post; with the player in sight outside, nobody leaves the walls
## and nobody fires (an ambush); it springs when one of them is fired on; cut down to half and
## faced with a bigger force it breaks, and the survivors run out away from the enemy.

var failures := 0
var level: ZoneLevel
var main: Node
var player: Soldier


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_garrison" + tag  # never touch a real save
	Campaign.campaign_id = "test_garrison" + tag
	GameState.delete_save()
	CompoundLevel.spawn_ai = true
	await _run()
	_finish()


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return condition.call()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(ZoneDef.get_def("test"))
	level = CompoundLevel.current(self) as ZoneLevel
	check(level != null, "the test zone is up")
	if level == null:
		return
	await _wait_for(func() -> bool: return level.players.get_node_or_null(^"1") != null, 5.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	var m := level.get_module("compound")
	var rect := m.footprint()
	# Stand 120 m south of the walls, in the open: the module streams in, its garrison comes out.
	var watch := level.ground_point(m.global_position + Vector3(0, 0, rect.size.y * 0.5 + 120.0))
	player.global_position = watch
	await _wait_for(func() -> bool: return level.post_of("compound") != null and level.garrison_pending("compound") == 0, 30.0)
	var post := level.post_of("compound")
	check(post != null and post.members.size() >= 3, "the compound's garrison holds a post (%d men)" % (post.members.size() if post else 0))
	if post == null:
		return
	check(post.members.all(func(s: Soldier) -> bool: return SquadAI.of(s).post == post), "every one of them knows it")
	check(not post.sprung and post.members.all(func(s: Soldier) -> bool: return not SquadAI.of(s).weapons_free()),
		"in ambush: nobody's weapon is free")
	# 20 s with the player out there in the open: nobody steps outside the walls.
	var worst := 0.0
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.5).timeout
		for s in post.alive():
			if not post.holds(s.global_position):
				var p := Vector2(s.global_position.x, s.global_position.z)
				var r := post.rect
				worst = maxf(worst, maxf(maxf(r.position.x - p.x, p.x - r.end.x), maxf(r.position.y - p.y, p.y - r.end.y)))
	check(worst < 1.0, "20 s with the squad in the open outside: nobody leaves the walls (worst %.1f m out)" % worst)
	check(not post.sprung, "and nobody gives the ambush away at 120 m")
	# One of them fired on: the ambush springs, every weapon free.
	var first := post.alive()[0]
	SquadAI.of(first)._fired_on_at = Soldier._now()
	await _wait_for(func() -> bool: return post.sprung, 3.0)
	check(post.sprung and post.alive().all(func(s: Soldier) -> bool: return SquadAI.of(s).weapons_free() or SquadAI.of(s).hold_fire),
		"fired on, the ambush springs: they open up")
	# Cut down past half, faced with six: it breaks and they run.
	var up := post.alive()
	var keep := int(floor(post.start * GarrisonPost.FLEE_LEFT_SHARE))
	for k in range(keep, up.size()):
		up[k].vitals.server_kill()
	var squad: Array[Soldier] = []
	for k in 6:
		squad.append(level.spawn_soldier({"name": "Friend%d" % k, "faction": "friendly", "variant": "multicam", "guard": false,
			"pos": watch + Vector3(k * 2.0 - 5.0, 0, -60.0), "combat": 0.5, "discipline": 0.5, "loadout": ["m4a1", "mag_556"]}))
	await _wait_for(func() -> bool: return post.fleeing, 5.0)
	check(post.fleeing, "down to %d of %d against six, the garrison breaks" % [post.alive().size(), post.start])
	await get_tree().create_timer(6.0).timeout
	var running := post.alive().filter(func(s: Soldier) -> bool:
		var ai := SquadAI.of(s)
		return ai.intent == SquadAI.Intent.FALL_BACK and ai._fall_back_point != null and not post.holds(ai._fall_back_point as Vector3))
	check(not post.alive().is_empty() and running.size() == post.alive().size(),
		"its survivors run for it, out of the walls (%d of %d)" % [running.size(), post.alive().size()])
	var away := post.alive().all(func(s: Soldier) -> bool:
		return ((SquadAI.of(s)._fall_back_point as Vector3) - m.global_position).dot(m.global_position - watch) > 0.0) if not post.alive().is_empty() else false
	check(away, "away from the squad, not into it")


func _finish() -> void:
	print("GARRISON TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	GameState.delete_save()
	get_tree().quit(failures)
