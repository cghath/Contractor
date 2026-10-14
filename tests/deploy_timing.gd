extends Node
## Timing script (not a suite): how long deploying an HVT capture at Harbour yard's town takes,
## and the frames after it, as the Captain's P0362 hitch (3.42 s: the HVT and 12 civilians
## spawned in one frame, each new plain-clothes outfit rasterising a 0.5 cm body). Headless:
##   <voxel godot exe> --headless --path . res://tests/deploy_timing.tscn
## Prints the first hostile of the session spawned (his uniform's art; P0362's 0.43 s frame when
## the first garrison came in), the deploy call, every frame over 33 ms for 400 frames after, and
## five more civilians spawned at once. Never touches a real save.

var level: ZoneLevel


func _ready() -> void:
	GameState.zone_id = "test_deploy_timing"
	Campaign.campaign_id = "test_deploy_timing_campaign"
	CompoundLevel.spawn_ai = false  # no garrison before the first hostile is timed
	Contracts.auto_show_debrief = false
	GameState.delete_save()
	Campaign.reset_campaign()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.host_zone(MissionRegistry.zone_def("harbour_yard"))
	level = CompoundLevel.current(self) as ZoneLevel
	while level.players.get_node_or_null(^"1") == null:
		await get_tree().process_frame
	for i in 120:
		await get_tree().process_frame
	var h0 := Time.get_ticks_usec()
	level.spawn_soldier({"name": "TimingHostile", "faction": "hostile", "variant": "urban", "pos": level.ground_point(Vector3(6, 0, 8)),
		"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.45, "discipline": 0.5, "mode": "aware", "guard": true})
	var h1 := Time.get_ticks_usec()
	level.spawn_soldier({"name": "TimingHostile2", "faction": "hostile", "variant": "urban", "pos": level.ground_point(Vector3(8, 0, 8)),
		"loadout": CompoundLevel.HOSTILE_LOADOUT, "combat": 0.45, "discipline": 0.5, "mode": "aware", "guard": true})
	print("timing: first hostile of the session %.1f ms, the next %.1f ms" % [(h1 - h0) / 1000.0, (Time.get_ticks_usec() - h1) / 1000.0])
	await get_tree().process_frame
	Contracts.new_full_campaign(77, 300000)
	var town := ""
	for m in level.modules():
		if ZoneModules.base(m.type) == "town":
			town = m.type
	var c := {}
	for k in 60:
		var rng := RandomNumberGenerator.new()
		rng.seed = k
		c = ContractGen.generate(rng, {"day": Economy.day(), "source": "board", "type": "hvt_capture", "zone_id": "harbour_yard"})
		if String(c.module) == town:
			break
	var cid := Contracts.server_add_offer(c)
	Contracts.server_accept(cid, ContractGen.default_terms())
	var t0 := Time.get_ticks_usec()
	var why := Contracts.server_start_deployment([cid])
	print("timing: deploy call %.1f ms at %s (%s)" % [(Time.get_ticks_usec() - t0) / 1000.0, c.module, why if why != "" else "ok"])
	var worst := 0.0
	var long_frames := 0
	var last := Time.get_ticks_usec()
	for i in 400:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var f := (now - last) / 1000.0
		last = now
		worst = maxf(worst, f)
		if f > 33.0:
			long_frames += 1
			print("timing:   frame %d: %.1f ms" % [i, f])
	var people := PeopleLayer.find(level)
	print("timing: after it, worst frame %.1f ms, %d frames over 33 ms; %d people, %d AI" % [worst, long_frames, people.people().size(), level.ai.get_child_count()])
	var t1 := Time.get_ticks_usec()
	for i in 5:
		people.server_spawn_person({"name": "TimingCiv%d" % i, "kind": "civilian", "side": "neutral", "label": "Timing %d" % i,
			"pos": level.ground_point(Vector3(10 + i, 0, 10))})
	print("timing: 5 more civilians at once %.1f ms" % [(Time.get_ticks_usec() - t1) / 1000.0])
	Campaign.reset_campaign()
	GameState.delete_save()
	get_tree().quit(0)
