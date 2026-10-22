extends Node
## Headless check: for every zone and every generated contract type (board, hot-zone extras
## and radio follow-ups included) Contracts.module_origin is the target module's real place in
## the hosted zone, never the Vector3.ZERO fallback, so the briefing's HVT, bonus and
## "Hostiles at the ..." markers sit on the module the map draws.
##   <voxel godot exe> --headless --path . res://tests/markers_test.tscn

var failures := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_markers" + tag
	Campaign.campaign_id = "test_markers_campaign" + tag
	CompoundLevel.spawn_ai = false
	Contracts.auto_show_debrief = false
	HotZoneOps.enabled = false
	EnemyDrones.enabled = false  # (wave 6: no recon drones reporting mid-test)
	GameState.delete_save()
	Campaign.reset_campaign()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	for z: Dictionary in MissionRegistry.zones():
		var zid := String(z.zone_id)
		var def := MissionRegistry.zone_def(zid)
		if def.is_empty():
			continue
		main.host_zone(def)
		var level: ZoneLevel = null
		for i in 120:
			await get_tree().process_frame
			level = CompoundLevel.current(self) as ZoneLevel
			if level != null and level.get_module(String((def.modules as Array)[0].id)) != null:
				break
		if level == null:
			check(false, "%s hosts" % zid)
			continue
		var bad := []
		var n := 0
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(zid)
		for type in MissionRegistry.types():
			for k in 6:
				var ctx := {"day": 1, "source": "board", "type": type, "zone_id": zid}
				if k >= 3:
					ctx["avoid_modules"] = ["x"]
				var c := ContractGen.generate(rng, ctx)
				var cid := String(c.get("module_id", ""))
				n += 1
				if cid == "":
					continue
				var m := level.get_module(cid)
				if m == null:
					bad.append("%s/%s: module %s not in level" % [type, c.zone_id, cid])
				# (Vector3.INF as the fallback, not ZERO: a zone's HQ stands at its middle, and on
				# flat ground, as the Old Quarter's "city" preset is, that's (0, 0, 0) itself.)
				elif Contracts.module_origin(c, Vector3.INF) != m.position:
					bad.append("%s: origin %s vs %s" % [type, Contracts.module_origin(c, Vector3.INF), m.position])
				elif BaseHub.known_enemies(c)[0].pos != [m.position.x, m.position.z]:
					bad.append("%s: known_enemies off" % type)
		check(bad.is_empty(), "%s: %d contracts, module_origin is each target module's real place %s" % [zid, n, bad.slice(0, 3)])
		# A contract held from an older build names a module this layout lacks: it is healed
		# to a module of its type, not left at the zone's centre.
		var stale := ContractGen.generate(rng, {"day": 1, "source": "board", "type": "hvt_capture", "zone_id": zid})
		if String(stale.get("module_id", "")) != "":
			var want := ZoneModules.base(String(stale.module))
			stale["module_id"] = "gone_99"
			Contracts.heal_module_id(stale, level)
			var healed := Contracts.module_origin(stale)
			var ok := level.get_module(String(stale.module_id)) != null and ZoneModules.base(level.get_module(String(stale.module_id)).type) == want \
				and healed == level.get_module(String(stale.module_id)).position and healed != Vector3.ZERO
			check(ok, "%s: a contract naming a module the zone lacks is healed to a %s (now %s)" % [zid, want, stale.module_id])
		level.queue_free()
		await get_tree().process_frame
	print("MARKERS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1
