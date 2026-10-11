extends Node
## Scratch: navigation around the compound module.

var level: ZoneLevel


func _ready() -> void:
	GameState.zone_id = "test_worlddbg"
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(ZoneDef.get_def("test"))
	level = CompoundLevel.current(self) as ZoneLevel
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	var player: Soldier = level.players.get_node(^"1")
	player.set_physics_process(false)
	var m := level.get_module("compound")
	if "--unloaded" in OS.get_cmdline_user_args():
		player.global_position = level.ground_point(m.to_global(Vector3(0, 0, 600)))
		var sitter := level.spawn_soldier({"name": "Sitter", "faction": "friendly", "variant": "multicam", "pos": level.ground_point(m.to_global(Vector3(0, 0, 8))),
			"loadout": [], "combat": 0.5, "discipline": 0.6, "guard": true, "mode": "safe"})
		await get_tree().create_timer(1.0).timeout
		print("streamed: ", m.is_streamed())
	else:
		player.global_position = level.ground_point(m.to_global(Vector3(0, 0, -8)))
		while not m.is_ready():
			await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	level.nav.refresh()
	while not level.nav.is_settled():
		await get_tree().process_frame
	for i in 3:
		await get_tree().physics_frame
	var map := player.get_world_3d().navigation_map
	print("origin ", m.global_position, " chunks ", level.nav.chunk_total())
	var pairs := [[Vector3(0, 0, 25), Vector3(0, 0, 15)], [Vector3(0, 0, 15), Vector3(0, 0, -8)], [Vector3(0, 0, 40), Vector3(0, 0, 25)],
		[Vector3(14, 0, 40), Vector3(0, 0, 25)], [Vector3(10, 0, 10), Vector3(-10, 0, 10)], [Vector3(10, 0, 10), Vector3(10, 0, -16)]]
	for pair: Array in pairs:
		var a := level.ground_point(m.to_global(pair[0]))
		var b := level.ground_point(m.to_global(pair[1]))
		var path := NavigationServer3D.map_get_path(map, a, b, true)
		print("%s -> %s: closest a %s b %s, path %d points, end %s" % [pair[0], pair[1], m.to_local(NavigationServer3D.map_get_closest_point(map, a)),
			m.to_local(NavigationServer3D.map_get_closest_point(map, b)), path.size(), m.to_local(path[path.size() - 1]) if path.size() > 0 else "-"])
	if "--unloaded" in OS.get_cmdline_user_args():
		_grid(m, map)
		get_tree().quit()
		return
	var target := m.to_global(Vector3(0, 0, -8))
	var walker := level.spawn_soldier({"name": "Walker", "faction": "friendly", "variant": "multicam", "pos": level.ground_point(m.to_global(Vector3(14, 0, 62))),
		"loadout": [], "combat": 0.5, "discipline": 0.6, "guard": false, "mode": "safe"})
	await get_tree().create_timer(0.5).timeout
	level.squad_for(&"friendly").give_order(player, Squad.Order.MOVE, target, PackedStringArray(["Walker"]))
	for k in 30:
		await get_tree().create_timer(1.0).timeout
		var brain := SquadAI.of(walker)
		print("t%d walker %s path %d idx %d dest %s intent %s status %s chunks %d" % [k, m.to_local(walker.global_position), brain._path.size(), brain._path_index, m.to_local(brain._destination), brain.intent, brain.status_text(), level.nav.chunk_total()])
	for z in range(-24, 25, 2):
		var line := ""
		for x in range(-24, 25, 1):
			var p := level.ground_point(m.to_global(Vector3(x, 0, z)))
			var c := NavigationServer3D.map_get_closest_point(map, p)
			line += "#" if Vector2(c.x - p.x, c.z - p.z).length() > 0.5 else ("~" if absf(c.y - p.y) > 0.5 else ".")
		print("%4d %s" % [z, line])
	get_tree().quit()


func _grid(m: ZoneModule, map: RID) -> void:
	for z in range(-24, 25, 2):
		var line := ""
		for x in range(-24, 25, 1):
			var p := level.ground_point(m.to_global(Vector3(x, 0, z)))
			var c := NavigationServer3D.map_get_closest_point(map, p)
			line += "#" if Vector2(c.x - p.x, c.z - p.z).length() > 0.5 else ("~" if absf(c.y - p.y) > 0.7 else ".")
		print("%4d %s" % [z, line])
