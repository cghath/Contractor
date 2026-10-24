extends Node
## Headless checks for combined arms A7 (cg_brief queue item 2.5; docs/combined_arms.md 2.10,
## 2.7.1, 9.3): fire, destruction and sound, in the real compound. The fire's stages and their
## times, the bail-out, thermal heat following the fire; each ammunition outcome with its effects
## and wreck state (the Abrams' bustle venting against its hull rack going up with the turret
## thrown, the Bradley's 25 mm cooking off with its pops, its TOW rack rupturing the hull); the
## thrown turret landing and resting; the debris from the seed, asleep and frozen; the smoke
## dischargers' multispectral screen blocking sight, thermal and the laser, then clearing, and
## their reload; each gun's own sound (no heavy-MG stand-in), the 120 mm's overpressure, the TOW
## launcher raised and lowered; the intercom and the own engine from inside by seat and hatch;
## impact effects by round; a wreck's save and load; the effect caps and their cost; then a second
## process joins over ENet and finds the burning wreck burning, the thrown turret and the debris
## where the host's lie, and makes the same debris from the next kill's seed.
##   <voxel godot exe> --headless --path . res://tests/vehiclefx_test.tscn
## The host starts the client itself ("-- --vehiclefx-join"). Exits with the number of failures.

## 9.3: "6 fires and 64 debris within the effects budget" (data/vehicle_fx.json budgets fx_ms);
## locally under load, this much slack.
const LOCAL_SLACK := 3.0

var failures := 0
var level: CompoundLevel
var layer: VehicleLayer
var player: Soldier
var expect: Dictionary = {}
var _client_lines := PackedStringArray()
var _client_failures := -1
var _client_ready := false
var _n := 0
var _wreck: Vehicle  # the Abrams thrown apart (kept for the save and the client)


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_vehiclefx" + tag  # never touch a real save
	GameSettings.use_file(OS.get_user_data_dir().path_join("test_vehiclefx_settings%s.cfg" % tag))  # never the player's
	GameSettings.reset_all()
	CompoundLevel.spawn_ai = false
	PeopleLayer.populate = false
	if "--vehiclefx-join" in OS.get_cmdline_user_args():
		_run_client()
		return
	GameState.delete_save()
	get_tree().create_timer(740.0).timeout.connect(func() -> void:
		print("VEHICLEFX TEST FAILED (timed out)")
		get_tree().quit(99))
	_test_pure()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	var anchor := VoxelViewer.new()
	anchor.name = "TestViewer"
	anchor.view_distance = VoxelWorld.VIEW_DISTANCE
	anchor.requires_visuals = false
	anchor.requires_collisions = true
	level.add_child(anchor)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	layer = VehicleLayer.of(level)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0.1, 0)
	VehicleCamera.chase = false
	for model: String in ["abrams", "bradley", "matv", "technical"]:
		VehicleHull.prewarm(model)
	Vehicle.fire_rolls = false  # (no chance fires on top of the ones each check sets: force_detonate still sets off racks)
	if _want("stages"):
		await _test_stages()
	if _want("kill"):
		await _test_kill()
	if _want("vent"):
		await _test_vent()
	if _want("cookoff"):
		await _test_cook_off()
	if _want("smoke"):
		await _test_dischargers()
	if _want("guns"):
		await _test_guns()
	if _want("impacts"):
		await _test_impacts()
	if _want("audio"):
		await _test_audio()
	if _want("save"):
		await _test_save()
	if _want("budget"):
		await _test_budget()
	if _want("client"):
		await _test_client()
	Sfx.listener_override = null
	GameState.delete_save()
	GameSettings.reset_all()
	GameSettings.use_file("")
	print("VEHICLEFX TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


## While iterating: CONTRACTOR_VEHICLEFX_ONLY="kill,save" runs only those parts.
static func _want(part: String) -> bool:
	var only := OS.get_environment("CONTRACTOR_VEHICLEFX_ONLY")
	return only == "" or part in only.split(",")


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


# --- Pure ---------------------------------------------------------------------------------------

func _test_pure() -> void:
	print("The numbers, the debris plan, the sounds (pure)")
	var big := VehicleFire.fireball(40.0)
	var small := VehicleFire.fireball(5.0)
	check(absf(float(big.radius) - (2.0 + 1.5 * pow(40.0, 1.0 / 3.0))) < 0.01 and is_equal_approx(float(big.kg), 12.0) and is_equal_approx(float(small.kg), 2.0),
		"the fireball: 2 + 1.5 x rounds^(1/3) m, min(0.4 x rounds, 12) kg (40 rounds: %.1f m, %.1f kg; 5: %.1f kg)" % [big.radius, big.kg, small.kg])
	var plan := VehicleFx.debris_plan("abrams", 12345)
	var again := VehicleFx.debris_plan("abrams", 12345)
	var other := VehicleFx.debris_plan("abrams", 54321)
	check(plan.size() >= 12 and plan.size() <= 24 and VehicleFx.plan_digest(plan) == VehicleFx.plan_digest(again) and VehicleFx.plan_digest(plan) != VehicleFx.plan_digest(other),
		"debris from a seed: %d pieces (12-24), the same pieces from the same seed, others from another" % plan.size())
	var guns_ok := true
	for g: String in ["m256", "m242", "tow_launcher"]:
		var sound := String(VehicleSpecs.gun(g).get("sound", ""))
		if sound == "" or sound == "hmg":
			guns_ok = false
	check(guns_ok and String(VehicleSpecs.gun("m256").sound) == "m256" and String(VehicleSpecs.gun("m242").sound) == "m242" and String(VehicleSpecs.gun("tow_launcher").sound) == "tow_launch",
		"each gun its own sound, no heavy-MG stand-in left (m256, m242, tow_launch)")
	var ids := ["shot_m256", "shot_m256_far", "m256_blast", "shot_m242", "shot_m242_far", "tow_launch", "tow_launch_far", "tow_wire", "detonation", "detonation_far",
		"vent_roar", "cookoff_pop", "fire_roar", "turret_crash", "ricochet", "impact_clang", "impact_thud", "impact_clank", "pen_boom", "heat_bang", "smoke_discharge", "tracks_heavy"]
	var missing := ids.filter(func(id: String) -> bool: return not Sfx.defs.has(id) or Sfx.streams(StringName(id)).is_empty())
	check(missing.is_empty(), "every A7 sound is defined with a stream (%d; missing %s)" % [ids.size(), missing])
	check(Sfx.intercom_band() == Sfx.INTERCOM_BAND_HZ and AudioServer.get_bus_index(&"Interior") >= 0 and AudioServer.get_bus_send(AudioServer.get_bus_index(&"Intercom")) == &"Voice",
		"the Intercom bus band-limited %s Hz into Voice; the Interior bus there" % Sfx.intercom_band())
	check(SmokeCloud.COLOURS.has(ThermalView.MULTISPECTRAL) and VehicleSmoke.has_dischargers(VehicleSpecs.spec("abrams")) and VehicleSmoke.has_dischargers(VehicleSpecs.spec("bradley"))
		and not VehicleSmoke.has_dischargers(VehicleSpecs.spec("matv")), "dischargers on the Abrams (M250) and Bradley (M257), a multispectral cloud colour")


# --- Stages --------------------------------------------------------------------------------------

func _test_stages() -> void:
	print("A fire's stages, the bail-out, thermal (2.10.1)")
	var v := await _spawn("matv", Vector3(-40, 0, -70), 0.0)
	var crew := await _men(2, v)
	v.server_enter(crew[0], 0)
	v.server_enter(crew[1], 1)
	await _physics(3)
	var f := v.fire_state
	var said := Callouts.of(level).sent.size()
	v.server_start_fire(600.0)
	await _seconds(0.3)
	var fx := VehicleFx.of(v)
	await _seconds(0.3)
	check(f.stage == VehicleFire.SMOKE and fx._column != null and fx._flames == null and ThermalView.heat_of(v) >= 0.99,
		"set alight: grey smoke first, no flames yet, hot in thermal (%s, heat %.2f)" % [f.stage, ThermalView.heat_of(v)])
	f.stage_t -= VehicleFire.num("fire", "smoke_s", 8.0)
	await _seconds(0.9)
	check(f.stage == VehicleFire.FIRE and fx._flames != null and fx._flames.emitting, "after smoke_s: flames (%s)" % f.stage)
	f.stage_t -= VehicleFire.num("fire", "bail_fire_s", 3.0)
	await _seconds(0.4)
	var out := crew.all(func(s: Soldier) -> bool: return v.seat_of(s) < 0 and s.vitals.is_up())
	var called := Callouts.of(level).sent.slice(said).any(func(e: Dictionary) -> bool: return String(e.text) == "Bail out!")
	check(f.bailed == "fire" and out and called and v.modules.kill_state().crew,
		"burning bail_fire_s: \"Bail out!\" and the AI crew get out alive, a crew kill (%s)" % VehicleModules.kill_text(v.modules.kill))
	v.burning_s = 0.3
	await _until(func() -> bool: return v.wrecked, 5.0)
	await _seconds(0.4)
	check(f.stage == VehicleFire.BURN_OUT and f.burn_out_s >= 120.0 and f.burn_out_s <= 300.0 and f.column_s >= 300.0 and f.column_s <= 600.0 and f.flames() > 0.5
		and ThermalView.heat_of(v) >= 0.9, "burned through: a wreck burning on %.0f s (120-300) under a column for %.0f s (300-600), still hot (%.2f)" % [f.burn_out_s, f.column_s, ThermalView.heat_of(v)])
	f.stage_t -= f.burn_out_s
	await _seconds(0.4)
	var cooling := ThermalView.heat_of(v)
	check(f.stage == VehicleFire.SMOULDER and f.column_up() and fx._flames == null, "burnt out: smouldering, its column still standing (%s)" % f.stage)
	f.wreck_t -= f.column_s + VehicleFire.num("heat", "cool_s", 900.0)
	await _seconds(0.6)
	check(not f.column_up() and fx._column != null and fx._column.amount <= VehicleFx.WANT_SMOULDER and absf(ThermalView.heat_of(v) - ThermalView.WRECK_HEAT) < 0.02 and cooling > ThermalView.heat_of(v),
		"its column gone: a thin smoulder, cooled to a cold wreck in thermal (%.2f, from %.2f)" % [ThermalView.heat_of(v), cooling])
	await _clear(v, crew)


# --- Catastrophic kills ---------------------------------------------------------------------------

func _test_kill() -> void:
	print("The Abrams' hull rack goes up: fireball, the turret thrown, debris (2.10.4)")
	var v := await _spawn("abrams", Vector3(55, 0, 55), 0.0)
	var crew := await _men(4, v)
	for i in 4:
		v.server_enter(crew[i], i)
	var extra := await _men(1, v)
	var near: Soldier = extra[0]
	near.global_position = v.global_position + Vector3(9.0, 0.1, 0.0)
	await _physics(3)
	Sfx.listener_override = v.global_position + Vector3(30, 2, 0)
	var heard := Sfx.heard_count()
	var kills := int(VehicleFx.made.get("kill", 0))
	var aboard := VehicleFire.rounds_aboard(v)
	v.set_meta(&"force_detonate", true)
	var pivot := v.global_transform * v.turret.pivot
	_hit(v, "pg7vr", Vector3(-2.7, 1.0, -1.45), Vector3(1, 0, 0))
	var f := v.fire_state
	var fx := VehicleFx.of(v)
	await _seconds(0.2)
	check(String(f.kill.get("k", "")) == VehicleFire.TOSS and int(f.kill.r) >= int(aboard.big) - 2 and int(f.kill.r) >= 10 and int(VehicleFx.made.get("kill", 0)) == kills + 1,
		"the hull rack goes up with %d main-gun rounds aboard: a catastrophic kill, the turret to be thrown (%s)" % [int(aboard.big), f.kill])
	check(f.last_hurt.has(near) and float(f.kill.kg) > 10.0, "the fireball's %.1f kg blast reaches the man 9 m off" % float(f.kill.get("kg", 0.0)))
	await _until(func() -> bool: return v.wrecked, 3.0)
	await _seconds(1.5)
	var body := fx.turret_body()
	check(body != null and v.hull.parts_gone and fx.turret_peak() > pivot.y + 3.0,
		"the turret flies (%.1f m above its ring at the top)" % (fx.turret_peak() - pivot.y if body else 0.0))
	check(fx.pieces().size() >= 12 and fx.pieces().size() <= 24 and fx.pieces().size() == VehicleFx.debris_plan("abrams", f.seed).size(),
		"%d debris pieces thrown from the seed" % fx.pieces().size())
	await _until(func() -> bool: return not f.turret_rest.is_empty(), 15.0)
	var rest: Variant = VehicleFx._pose(f.turret_rest)
	check(rest is Transform3D and body.freeze and (rest as Transform3D).origin.distance_to(pivot) > 1.0 and (rest as Transform3D).origin.y < fx.turret_peak() - 1.0,
		"it lands and rests %.1f m from its ring, frozen (%s)" % [(rest as Transform3D).origin.distance_to(pivot) if rest is Transform3D else -1.0, "crashed" if fx._turret_crashed else "no crash heard"])
	check(fx._turret_crashed and int(VehicleFx.made.get("turret_crash", 0)) >= 1, "its crash heard where it landed")
	fx._debris_t0 -= VehicleFire.num("debris", "freeze_s", 30.0)
	await _seconds(0.4)
	check(f.debris_rest.size() == fx.pieces().size() and fx.pieces().all(func(b: RigidBody3D) -> bool: return b.freeze),
		"the debris frozen static after freeze_s, where it lies sent with the state (%d)" % f.debris_rest.size())
	check(v.wrecked and v.modules.kill_state().catastrophic and crew.all(func(s: Soldier) -> bool: return s.vitals.is_dead()) and f.stage == VehicleFire.BURN_OUT
		and v.hull._charred, "a charred hulk burning on, the crew dead (%s)" % f.stage)
	check(Sfx.heard_after(heard).has(&"detonation") or Sfx.heard_after(heard).has(&"detonation_far"), "the detonation heard (%s)" % [Sfx.heard_after(heard).slice(0, 6)])
	_wreck = v
	for s: Soldier in crew + [near]:
		if is_instance_valid(s):
			s.queue_free()


func _test_vent() -> void:
	print("The Abrams' bustle vents: a column through the roof, not a detonation (2.10.2)")
	var v := await _spawn("abrams", Vector3(-55, 0, 55), 0.0)
	var crew := await _men(4, v)
	for i in 4:
		v.server_enter(crew[i], i)
	await _physics(3)
	var kills := int(VehicleFx.made.get("kill", 0))
	var vents := int(VehicleFx.made.get("vent", 0))
	v.set_meta(&"force_detonate", true)
	_hit(v, "pg7v", Vector3(2.7, 2.0, 3.2), Vector3(-1, 0, 0))
	await _seconds(0.5)
	var f := v.fire_state
	var fx := VehicleFx.of(v)
	check(String(f.kill.get("k", "")) == VehicleFire.VENT and int(VehicleFx.made.get("vent", 0)) == vents + 1 and int(VehicleFx.made.get("kill", 0)) == kills
		and not v.is_burning() and f.stage == VehicleFire.NONE and not v.hull.parts_gone and fx.pieces().is_empty() and crew.all(func(s: Soldier) -> bool: return s.vitals.is_up()),
		"the bustle vents: its column, no fireball, no fire, no debris, the turret on, the crew unhurt")
	await _clear(v, crew)


func _test_cook_off() -> void:
	print("The Bradley: its 25 mm cooks off; its TOW rack ruptures the hull (2.10.1, 2.10.2)")
	var v := await _spawn("bradley", Vector3(30, 0, 62), 0.0)
	var crew := await _men(3, v)
	for i in 3:
		v.server_enter(crew[i], i)
	await _physics(3)
	var pops := int(VehicleFx.made.get("pop", 0))
	v.set_meta(&"force_detonate", true)
	_hit(v, "pg7vl", Vector3(-2.5, 0.7, -0.8), Vector3(1, 0, 0))
	var f := v.fire_state
	await _seconds(0.4)
	var left := f.cook_until - Soldier._now()
	check(f.cooking() and left > 15.0 and left <= 60.0 and f.stage == VehicleFire.FIRE and f.bailed == "cook_off",
		"the 25 mm rack cooks off for %.0f s (20-60), the flames at once, \"Bail out!\" (%s)" % [left, f.bailed])
	check(crew.all(func(s: Soldier) -> bool: return v.seat_of(s) < 0 or not VehicleModules.able(s)), "the able crew out at the cook-off")
	await _until(func() -> bool: return int(VehicleFx.made.get("pop", 0)) >= pops + 2, 8.0)
	check(int(VehicleFx.made.get("pop", 0)) >= pops + 2 and f.pops >= 2, "rounds popping (%d so far), each a small HE event" % f.pops)
	await _clear(v, crew)
	var ifv := await _spawn("bradley", Vector3(-30, 0, 62), 0.0)
	await _physics(3)
	ifv.set_meta(&"force_detonate", true)
	ifv.modules.server_set("rack_tow", 0.05)
	_hit(ifv, "pg7vr", Vector3(2.6, 1.0, 0.45), Vector3(-1, 0, 0))
	await _until(func() -> bool: return ifv.wrecked, 3.0)
	await _seconds(0.5)
	var fx := VehicleFx.of(ifv)
	var ft := ifv.fire_state
	check(String(ft.kill.get("k", "")) == VehicleFire.RUPTURE and not ifv.hull.parts_gone and fx.turret_body() == null and fx.pieces().size() >= 12 and ifv.wrecked,
		"its TOW rack goes up with %d big rounds aboard: the hull ruptures, the turret stays, debris (%d)" % [int(ft.kill.get("r", -1)), fx.pieces().size()])
	ifv.queue_free()


# --- The smoke dischargers ------------------------------------------------------------------------

func _test_dischargers() -> void:
	print("The smoke dischargers: a multispectral screen (F-249, 2.7.1)")
	var v := await _spawn("abrams", Vector3(-60, 0, 10), 0.0)
	var target := await _spawn("matv", Vector3(-60, 0, -45), 0.0)
	var crew := await _men(2, v)
	v.server_enter(crew[0], 1)
	v.server_enter(crew[1], 3)
	await _physics(3)
	var sm := v.smoke
	var eye := v.global_transform * Vector3(0.75, 2.6, -1.5)
	var aim := target.global_position + Vector3.UP * 1.4
	var lase := func() -> Dictionary: return v.gunnery.range_along(eye, (aim - eye).normalized(), [0, 4000])
	var before: Dictionary = lase.call()
	check(sm.salvos() == 2 and sm.loaded == [6, 6] and sm.stowed == [6, 6] and not SmokeCloud.blocks(eye, aim) and not ThermalView.smoke_blocks(eye, aim)
		and absf(float(before.last) - eye.distance_to(aim)) < 4.0, "the M250 loaded 6 | 6 (2 salvos), 6 a side stowed; the target in sight, thermal and the laser (%.0f m of %.0f; eye %s, aim %s)" % [float(before.last), eye.distance_to(aim), eye, aim])
	var why := sm.server_pop(crew[0])
	check(why == "" and sm.loaded == [3, 3] and sm.last_points.size() == 6 and "SMOKE 3 | 3" in v.readout(1), "pop smoke: a salvo of 3 a side, 3 | 3 left (%s; '%s')" % [why, v.readout(1).get_slice("SMOKE", 1).left(18)])
	await _until(func() -> bool: return SmokeCloud.active.filter(func(c: SmokeCloud) -> bool: return c.colour == ThermalView.MULTISPECTRAL).size() >= 6, 5.0)
	await _seconds(4.0)
	var clouds := SmokeCloud.active.filter(func(c: SmokeCloud) -> bool: return c.colour == ThermalView.MULTISPECTRAL)
	var during: Dictionary = lase.call()
	check(clouds.size() == 6 and SmokeCloud.blocks(eye, aim) and ThermalView.smoke_blocks(eye, aim) and float(during.first) > 0.0 and float(during.last) < eye.distance_to(aim) - 10.0,
		"its six clouds screen the front: sight blocked, thermal blocked, the laser stopped in the smoke, no return off the target (%d clouds, sight %s, thermal %s, first %.0f m, last %.0f)" % [clouds.size(),
		SmokeCloud.blocks(eye, aim), ThermalView.smoke_blocks(eye, aim), float(during.first), float(during.last)])
	for c: SmokeCloud in clouds:
		c.age = SmokeCloud.DURATION_S - 0.2
	await _until(func() -> bool: return SmokeCloud.active.filter(func(c: SmokeCloud) -> bool: return c.colour == ThermalView.MULTISPECTRAL).is_empty(), 5.0)
	var after: Dictionary = lase.call()
	check(not SmokeCloud.blocks(eye, aim) and not ThermalView.smoke_blocks(eye, aim) and float(after.last) > 0.0,
		"the screen gone: everything sees through again (%d clouds, laser %.0f m)" % [SmokeCloud.active.size(), float(after.last)])
	sm.server_pop(null)
	check(sm.salvos() == 0 and sm.can_pop() == "Reload the smoke" and sm.server_pop(null) != "", "every salvo fired: '%s'" % sm.can_pop())
	await _until(func() -> bool: return SmokeCloud.active.is_empty(), 1.0)
	for c: SmokeCloud in SmokeCloud.active.duplicate():
		c.queue_free()
	check(sm.server_reload(crew[1]) == "" and sm.reload_until > 0.0, "the loader reloads from the stowage")
	sm.reload_until = Soldier._now()
	await _seconds(0.4)
	check(sm.loaded == [3, 3] and sm.stowed == [3, 3] and sm.reload_until > 0.0, "a salvo every reload_s from stowage (%s | %s stowed)" % [sm.loaded, sm.stowed])
	sm.server_restock()
	v.modules.server_set("smoke_l", 0.3)
	await _seconds(0.4)
	check(sm.loaded[0] == 3 and sm.loaded[1] == 6, "the left launcher damaged: half its grenades gone (%s)" % [sm.loaded])
	v.modules.server_set("smoke_r", 0.0)
	await _seconds(0.4)
	check(sm.loaded[1] == 0 and sm.salvos() == 1, "the right one destroyed: none from it (%d salvo left)" % sm.salvos())
	target.queue_free()
	await _clear(v, crew)


# --- Guns -----------------------------------------------------------------------------------------

func _test_guns() -> void:
	print("Guns: each its sound, the 120 mm's overpressure, the TOW launcher (F-245)")
	var v := await _spawn("abrams", Vector3(62, 0, 10), 0.0)
	var crew := await _men(2, v)
	v.server_enter(crew[0], 1)
	v.server_enter(crew[1], 3)
	var extra := await _men(1, v)
	var front: Soldier = extra[0]
	front.global_position = v.global_transform * Vector3(0.0, 0.0, -10.5)
	await _physics(3)
	Sfx.listener_override = v.global_position + Vector3(20, 2, 0)
	var heard := Sfx.heard_count()
	var blasts := int(VehicleFx.made.get("muzzle_cannon", 0))
	var r: Dictionary = v.weapons.server_fire(crew[0], "main", Vector3.ZERO)
	await _seconds(0.3)
	var ids := Sfx.heard_after(heard)
	check(bool(r.ok) and ids.has(&"shot_m256") and not ids.has(&"shot_hmg") and int(VehicleFx.made.get("muzzle_cannon", 0)) == blasts + 1,
		"the 120 mm: its own report, flash and dust (%s)" % [ids.slice(0, 4)])
	check(front.vitals.deaf_left() > 0.0, "a man 10 m in front of the muzzle: ears ringing from the overpressure (%.1f s)" % front.vitals.deaf_left())
	front.queue_free()
	await _clear(v, crew)
	var ifv := await _spawn("bradley", Vector3(62, 0, -40), 0.0)
	var gunners := await _men(3, ifv)
	ifv.server_enter(gunners[0], 1)
	ifv.server_enter(gunners[1], 3)
	await _physics(3)
	Sfx.listener_override = ifv.global_position + Vector3(20, 2, 0)
	heard = Sfx.heard_count()
	var shot: Dictionary = ifv.weapons.server_fire(gunners[0], "main", Vector3.ZERO)
	await _seconds(0.3)
	ids = Sfx.heard_after(heard)
	check(bool(shot.ok) and ids.has(&"shot_m242") and not ids.has(&"shot_hmg"), "the 25 mm: its own thud (%s)" % [ids.slice(0, 4)])
	var fx := VehicleFx.of(ifv)
	check(fx.has_launcher() and ifv.hull.art.get_node_or_null(^"Turret/Launcher") != null and fx.launcher_deg() < 1.0, "the TOW launcher a part of its own, stowed (%.1f deg)" % fx.launcher_deg())
	ifv.weapons.server_raise(true)
	await _seconds(VehicleWeapons.TOW_RAISE_S + 0.6)
	var deg := float(((ifv.spec.turret as Dictionary).launcher as Dictionary).raise_deg)
	check(fx.launcher_state() == "up" and absf(fx.launcher_deg() - deg) < 1.0, "raised: the launcher drawn up %.1f degrees (%s)" % [fx.launcher_deg(), fx.launcher_state()])
	heard = Sfx.heard_count()
	var tow: Dictionary = ifv.weapons.server_fire(gunners[0], "tow", Vector3.ZERO)
	await _seconds(0.3)
	ids = Sfx.heard_after(heard)
	check(bool(tow.ok) and ids.has(&"tow_launch") and ids.has(&"tow_wire") and int(VehicleFx.made.get("muzzle_atgm", 0)) >= 1, "the TOW's launch whoosh and the wire spooling (%s)" % [ids.slice(0, 4)])
	ifv.weapons.server_raise(false)
	await _seconds(1.8)
	check(fx.launcher_deg() < 1.0, "lowered again (%.1f deg)" % fx.launcher_deg())
	await _clear(ifv, gunners)


# --- Impacts --------------------------------------------------------------------------------------

func _test_impacts() -> void:
	print("Impacts by round (2.10.3)")
	var at := Vector3(0, 1, -60)
	Sfx.listener_override = at + Vector3(5, 0, 0)
	var flight := ShellFlight.of(level)
	var cases := [["vehicle", "ricochet", "m829a3", "mbt", "ricochet", &"ricochet"], ["vehicle", "non_pen", "m791", "mbt", "ke_stopped", &"impact_thud"],
		["vehicle", "non_pen", "m791", "mrap", "ke_stopped", &"impact_clang"], ["vehicle", "non_pen", "m791", "ifv", "ke_stopped", &"impact_clank"],
		["vehicle", "pen", "m829a3", "ifv", "ke_pen", &"pen_boom"], ["vehicle", "non_pen", "m830a1", "mbt", "heat_stopped", &"heat_bang"],
		["vehicle", "pen", "m830a1", "ifv", "heat_pen", &"heat_bang"], ["world", "burst", "m792", "", "he", &""], ["world", "ke", "m791", "", "ke_world", &""]]
	var bad: Array = []
	for c: Array in cases:
		var heard := Sfx.heard_count()
		var what := VehicleFx.impact(flight, at, String(c[0]), String(c[1]), String(c[2]), String(c[3]))
		if what != String(c[4]) or (c[5] != &"" and not Sfx.heard_after(heard).has(c[5])):
			bad.append([c, what, Sfx.heard_after(heard)])
	check(bad.is_empty() and VehicleFx.particles_live() > 0, "a ricochet's sparks and ping, KE stopped (thud on composite, clang on steel, clank on aluminium), a penetration's flash and boom, HEAT's flash and puff, HE's ball (%s)" % [bad])
	check(ShellFlight.TRACER_COLOURS.has("apfsds") and ShellFlight.tracer_material("apfsds").albedo_color != ShellFlight.tracer_material("he").albedo_color,
		"tracers by round: a sabot's white-hot, HE's red")


# --- Audio inside -----------------------------------------------------------------------------------

func _test_audio() -> void:
	print("The intercom and your own engine from inside (F-260)")
	var v := await _spawn("abrams", Vector3(-65, 0, -65), 0.0)
	v.hatches.auto_ai = false
	var crew := await _men(1, v)
	v.server_enter(crew[0], 0)  # the driver: the engine runs
	await _seat(v, 1)
	Sfx.listener_override = v.global_position + Vector3.UP * 2.0
	await _seconds(0.4)
	var driver := crew[0] as Soldier
	var e := Sfx.engine_of(v)
	check(Sfx.voice_route(driver) == &"intercom" and Sfx.muffle_active() and not e.is_empty() and (e.player as AudioStreamPlayer3D).bus == &"Interior"
		and is_instance_valid(e.get("tracks")), "the gunner buttoned up: the driver on the intercom; the engine and tracks from inside (bus %s)" % ((e.player as AudioStreamPlayer3D).bus if not e.is_empty() else &"-"))
	await _seat(v, 2)
	v.hatches.server_set(2, true, true)
	await _seconds(0.4)
	e = Sfx.engine_of(v)
	check(Sfx.voice_route(driver) == &"intercom" and not Sfx.muffle_active() and (e.player as AudioStreamPlayer3D).bus == &"SFX",
		"the commander turned out: still on the intercom (CVC), the engine as outside")
	v.hatches.server_set(2, false, true)
	await _seconds(0.4)
	e = Sfx.engine_of(v)
	check((e.player as AudioStreamPlayer3D).bus == &"Interior", "buttoned up again: from inside")
	var ifv := await _spawn("bradley", Vector3(-70, 0, 35), 0.0)
	var dr := await _men(1, ifv)
	ifv.server_enter(dr[0], 0)
	var rider := -1
	for i in ifv.seat_count():
		if rider < 0 and ifv.is_rider(i):
			rider = i
	v.server_exit(player)
	await _seconds(0.3)
	ifv.server_enter(player, rider)
	await _seconds(0.4)
	Sfx.listener_override = ifv.global_position + Vector3.UP * 2.0
	await _seconds(0.3)
	check(Sfx.voice_route(dr[0]) == &"open" and Sfx.voice_route(driver) == &"open" and (Sfx.engine_of(v).player as AudioStreamPlayer3D).bus == &"SFX",
		"a rider in the Bradley's back: no intercom (the crew heard in the cabin), the Abrams' engine as outside")
	ifv.server_exit(player)
	await _seconds(0.4)
	check(Sfx.voice_route(dr[0]) == &"open" and (Sfx.engine_of(ifv).player as AudioStreamPlayer3D).bus == &"SFX", "out on foot: nobody on the intercom")
	await _clear(ifv, dr)
	await _clear(v, crew)


# --- Saving -----------------------------------------------------------------------------------------

func _test_save() -> void:
	print("A wreck saved and loaded (2.10.4)")
	if not is_instance_valid(_wreck):
		check(false, "the thrown-apart Abrams is there to save")
		return
	var f := _wreck.fire_state
	var data: Dictionary = JSON.parse_string(JSON.stringify(_wreck.to_save()))
	var copy := layer.server_spawn("abrams", Transform3D.IDENTITY, "", &"player", "fx_saved_copy", data)
	await _seconds(1.0)
	var cf := copy.fire_state
	var cfx := VehicleFx.of(copy)
	var body := cfx.turret_body()
	var rest: Variant = VehicleFx._pose(f.turret_rest)
	check(copy.wrecked and cf.stage == f.stage and String(cf.kill.get("k", "")) == VehicleFire.TOSS and cf.seed == f.seed and absf(cf.stage_age() - f.stage_age()) < 3.0,
		"the stage, the kill and the seed back (%s, %.0f s in)" % [cf.stage, cf.stage_age()])
	check(body != null and body.freeze and rest is Transform3D and body.global_position.distance_to((rest as Transform3D).origin) < 0.05 and copy.hull.parts_gone,
		"the thrown turret lies where it lay, static")
	check(cfx.pieces().size() == f.debris_rest.size() and cfx.pieces().all(func(b: RigidBody3D) -> bool: return b.freeze), "and the debris (%d)" % cfx.pieces().size())
	copy.queue_free()
	var old := layer.server_spawn("technical", Transform3D(Basis(), Vector3(70, 0.3, 30)), "", &"player", "fx_old_wreck", {"id": "fx_old_wreck", "model": "technical", "wrecked": true, "pos": [70, 0.3, 30]})
	await _seconds(0.5)
	check(old.wrecked and old.fire_state.stage == VehicleFire.SMOULDER and not old.fire_state.column_up(), "a wreck saved before A7 smoulders")
	old.queue_free()


# --- Budgets ----------------------------------------------------------------------------------------

func _test_budget() -> void:
	print("Caps and cost (2.10.6, 9.3)")
	var fires: Array = []
	for i in 8:
		fires.append(await _spawn("technical", Vector3(-70 + i * 14, 0, 72), 0.0))
	var kills: Array = []
	for i in 4:
		kills.append(await _spawn("abrams", Vector3(-70 + i * 16, 0, -32), 0.0))
	Sfx.listener_override = Vector3(-20, 2, 72)
	await _seconds(1.0)
	for v: Vehicle in fires:
		v.server_start_fire(900.0)
	await _seconds(0.5)
	for v: Vehicle in fires:
		v.fire_state.stage_t -= 20.0
	VehicleFx._shared_at = -100.0
	await _seconds(1.2)
	var burning := fires.filter(func(v: Vehicle) -> bool: return v.fire_state.flames() > 0.0).size()
	check(burning == 8 and VehicleFx.full_count() <= int(VehicleFire.num("budgets", "full_fires", 6.0)) and VehicleFx.full_count() >= 1,
		"8 burning: %d with full effects (at most %d), the rest smoke only" % [VehicleFx.full_count(), int(VehicleFire.num("budgets", "full_fires", 6.0))])
	var t_kill := Time.get_ticks_usec()
	for t: Vehicle in kills:
		t.set_meta(&"force_detonate", true)
		t.fire_state.server_detonate("ammo_rack_hull")
	var kill_ms := (Time.get_ticks_usec() - t_kill) / 1000.0 / float(kills.size())
	check(kill_ms < VehicleFire.num("budgets", "kill_ms", 40.0) * LOCAL_SLACK, "a catastrophic kill costs the host %.1f ms in its frame (budget %.0f ms; %.0f locally; the hull's marks follow a frame each)" % [kill_ms,
		VehicleFire.num("budgets", "kill_ms", 40.0), VehicleFire.num("budgets", "kill_ms", 40.0) * LOCAL_SLACK])
	await _seconds(1.0)
	var particles := VehicleFx.particles_live()
	check(VehicleFx.debris_count() <= int(VehicleFire.num("debris", "zone_max", 64.0)) and particles <= int(VehicleFire.num("budgets", "particles", 2000.0))
		and VehicleFx.lights_live() <= int(VehicleFire.num("budgets", "lights", 10.0)),
		"4 tanks up at once: %d debris moving (at most 64; %d frozen), %d particles (at most 2,000), %d lights (at most 10)" % [VehicleFx.debris_count(), VehicleFx.static_debris_count(), particles, VehicleFx.lights_live()])
	await _seconds(VehicleFire.num("debris", "sleep_s", 8.0))
	# What the effects add (the fires' and kills' Fx and FireState with their particles, lights and
	# pieces), in alternating windows with them stopped, so whatever else the machine does lands
	# in both.
	var nodes: Array = []
	for v: Vehicle in fires + kills:
		nodes.append(VehicleFx.of(v))
		nodes.append(v.fire_state)
	var on: Array = []
	var off: Array = []
	for round_i in 6:
		for n: Node in nodes:
			n.process_mode = Node.PROCESS_MODE_INHERIT if round_i % 2 == 0 else Node.PROCESS_MODE_DISABLED
		await _frames(3)
		var w := await _frame_ms(15)
		(on if round_i % 2 == 0 else off).append(w.x + w.y)
	for n: Node in nodes:
		n.process_mode = Node.PROCESS_MODE_INHERIT
	on.sort()
	off.sort()
	var cost := float(on[1]) - float(off[1])
	var budget := VehicleFire.num("budgets", "fx_ms", 1.5)
	check(cost < budget * LOCAL_SLACK and VehicleFx.last_ms < budget,
		"the cost: %.2f ms a frame for 8 fires (6 full) and the debris of 4 kills (budget %.1f ms; %.1f locally), the effects' scripts %.2f ms (worst %.2f)" % [cost, budget,
		budget * LOCAL_SLACK, VehicleFx.last_ms, VehicleFx.worst_ms])
	for v: Vehicle in fires + kills:
		v.queue_free()
	await _seconds(0.3)


## The median process and physics frame times over `n` frames (ms).
func _frame_ms(n: int) -> Vector2:
	var proc: Array = []
	var phys: Array = []
	for i in n:
		await get_tree().process_frame
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	proc.sort()
	phys.sort()
	return Vector2(float(proc[n / 2]), float(phys[n / 2]))  # (medians: other work on the machine spikes the means)


# --- Replication ------------------------------------------------------------------------------------

func _test_client() -> void:
	print("Replication (a client joins late)")
	if not is_instance_valid(_wreck):
		_wreck = await _spawn("abrams", Vector3(55, 0, 55), 0.0)
		_wreck.set_meta(&"force_detonate", true)
		_wreck.fire_state.server_detonate("ammo_rack_hull")
		await _until(func() -> bool: return not _wreck.fire_state.turret_rest.is_empty(), 15.0)
		VehicleFx.of(_wreck)._debris_t0 -= 40.0
		await _seconds(0.5)
	var burning := await _spawn("matv", Vector3(40, 0, -70), 0.0)
	burning.server_start_fire(900.0)
	await _seconds(0.3)
	burning.fire_state.stage_t -= 20.0
	await _seconds(0.3)
	var f := _wreck.fire_state
	expect = {"mbt": _wreck.vehicle_id, "stage": f.stage, "tr": f.turret_rest, "dn": f.debris_rest.size(), "seed": f.seed, "burning": burning.vehicle_id,
		"bstage": burning.fire_state.stage}
	var log_path := OS.get_user_data_dir().path_join("vehiclefx_client%s.log" % OS.get_environment("CONTRACTOR_TEST_TAG"))
	DirAccess.remove_absolute(log_path)
	var args := ["--headless", "--log-file", log_path, "--path", ProjectSettings.globalize_path("res://"), "res://tests/vehiclefx_test.tscn", "--", "--vehiclefx-join"]
	# (CI's runners: a peer building the zone stalls for seconds; ENet's own 5-30 s drop came first.)
	multiplayer.peer_connected.connect(func(id: int) -> void:
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if enet and enet.get_peer(id):
			enet.get_peer(id).set_timeout(32, 60000, 120000))
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "started the client process")
	await _until(func() -> bool: return _client_ready or _client_failures >= 0, 300.0)
	if _client_ready:
		var next := await _spawn("bradley", Vector3(70, 0, -60), 0.0)
		await _seconds(1.0)
		next.set_meta(&"force_detonate", true)
		next.fire_state.server_detonate("rack_tow")
		await _seconds(0.3)
		_expect.rpc(expect.merged({"next": next.vehicle_id, "nseed": next.fire_state.seed, "ndigest": VehicleFx.plan_digest(VehicleFx.debris_plan("bradley", next.fire_state.seed)),
			"nk": String(next.fire_state.kill.get("k", ""))}))
	await _until(func() -> bool: return _client_failures >= 0, 240.0)
	for line in _client_lines:
		print("    client: %s" % line)
	check(_client_failures == 0, "everything replicated to the client (%d client failures)" % _client_failures)
	if pid > 0:
		await _until(func() -> bool: return not OS.is_process_running(pid), 10.0)
		if OS.is_process_running(pid):
			OS.kill(pid)
	var errors := PackedStringArray()
	if FileAccess.file_exists(log_path):
		for line in FileAccess.get_file_as_string(log_path).split("\n"):
			if line.contains("SCRIPT ERROR") or line.begins_with("ERROR:"):
				errors.append(line)
	for line in errors:
		print("    client: %s" % line)
	check(FileAccess.file_exists(log_path) and errors.is_empty(), "no errors in the client's log (%d)" % errors.size())


@rpc("any_peer", "call_remote", "reliable")
func _expect(data: Dictionary) -> void:
	expect = data


@rpc("any_peer", "call_remote", "reliable")
func _ask_expect() -> void:
	if multiplayer.is_server() and not expect.is_empty():
		_expect.rpc_id(multiplayer.get_remote_sender_id(), expect)


@rpc("any_peer", "call_remote", "reliable")
func _ready_for_hit() -> void:
	_client_ready = true


@rpc("any_peer", "call_remote", "reliable")
func _client_report(count: int, lines: PackedStringArray) -> void:
	_client_lines = lines
	_client_failures = count


func _run_client() -> void:
	get_tree().create_timer(420.0).timeout.connect(func() -> void: get_tree().quit(99))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	if Net.session_ended.is_connected(Callable(main, &"_on_session_ended")):
		Net.session_ended.disconnect(Callable(main, &"_on_session_ended"))
	await get_tree().process_frame
	var lines := PackedStringArray()
	var note := func(ok: bool, what: String) -> void:
		lines.append("[%s] %s" % ["ok" if ok else "FAIL", what])
		print("  [%s] %s" % ["ok" if ok else "FAIL", what])  # (in the client's own log too, as it goes)
		if not ok:
			failures += 1
	var joined := await _join_host("127.0.0.1", 120.0)
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if joined and enet and enet.get_peer(1):
		enet.get_peer(1).set_timeout(32, 60000, 120000)  # (as the host does for this peer: CI's stalls)
	var asked_until := Time.get_ticks_msec() + 40000
	while joined and expect.is_empty() and Time.get_ticks_msec() < asked_until and multiplayer.get_unique_id() != 1:
		_ask_expect.rpc_id(1)
		await _until(func() -> bool: return not expect.is_empty(), 3.0)
	level = CompoundLevel.current(self)
	if level == null or expect.is_empty():
		note.call(false, "joined and got the host's expectations")
	else:
		var find := func(id: String) -> Vehicle:
			for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
				if (n as Vehicle).vehicle_id == id:
					return n as Vehicle
			return null
		await _until(func() -> bool: return find.call(String(expect.mbt)) != null and find.call(String(expect.burning)) != null, 30.0)
		var v: Vehicle = find.call(String(expect.mbt))
		var b: Vehicle = find.call(String(expect.burning))
		await _until(func() -> bool: return v != null and v.fire_state.stage == String(expect.stage) and VehicleFx.of(v).turret_body() != null, 20.0)
		await _seconds(1.0)
		var fx := VehicleFx.of(v) if v else null
		note.call(v != null and v.wrecked and v.fire_state.stage == String(expect.stage) and v.fire_state.seed == int(expect.seed) and v.fire_state.flames() > 0.0,
			"the burning wreck is burning here too (%s)" % (v.fire_state.stage if v else "-"))
		var rest: Variant = VehicleFx._pose(expect.tr)
		var body := fx.turret_body() if fx else null
		note.call(body != null and body.freeze and rest is Transform3D and body.global_position.distance_to((rest as Transform3D).origin) < 0.05 and v.hull.parts_gone,
			"the thrown turret where the host's lies (%.3f m off)" % (body.global_position.distance_to((rest as Transform3D).origin) if body and rest is Transform3D else -1.0))
		note.call(fx != null and fx.pieces().size() == int(expect.dn) and fx.pieces().all(func(p: RigidBody3D) -> bool: return p.freeze), "the debris where the host's lie (%d)" % (fx.pieces().size() if fx else -1))
		note.call(ThermalView.heat_of(v) >= 0.9 and b != null and b.fire_state.stage == String(expect.bstage) and VehicleFx.of(b)._column != null,
			"hot in thermal (%.2f); the burning M-ATV's smoke column" % ThermalView.heat_of(v))
		var kills := int(VehicleFx.made.get("kill", 0))
		print("client: ready for the next kill")
		_ready_for_hit.rpc_id(1)
		await _until(func() -> bool: return expect.has("next"), 30.0)
		await _until(func() -> bool:
			var found: Vehicle = find.call(String(expect.get("next", "")))
			return found != null and int(VehicleFx.made.get("kill", 0)) > kills and not VehicleFx.of(found).pieces().is_empty(), 20.0)
		var n: Vehicle = find.call(String(expect.get("next", "")))
		note.call(n != null and n.fire_state.seed == int(expect.get("nseed", -1)) and String(n.fire_state.kill.get("k", "")) == String(expect.get("nk", "?"))
			and VehicleFx.plan_digest(VehicleFx.debris_plan("bradley", n.fire_state.seed)) == int(expect.get("ndigest", -1)) and VehicleFx.of(n).pieces().size() == VehicleFx.debris_plan("bradley", n.fire_state.seed).size(),
			"the next kill live: its fireball here, the same debris from the same seed (%s, seed %d / %d, %d pieces)" % [String(n.fire_state.kill.get("k", "")) if n else "-",
			n.fire_state.seed if n else 0, int(expect.get("nseed", -1)), VehicleFx.of(n).pieces().size() if n else -1])
	if multiplayer.get_unique_id() != 1:
		_client_report.rpc_id(1, failures, lines)
	await get_tree().create_timer(1.0).timeout
	Net.leave()
	get_tree().quit(failures)


func _join_host(address: String, seconds: float) -> bool:
	var joined := [false]
	Net.joined.connect(func() -> void: joined[0] = true)
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not (joined[0] or 1 in multiplayer.get_peers()) and Time.get_ticks_msec() < deadline:
		var peer := multiplayer.multiplayer_peer
		if not (peer is ENetMultiplayerPeer) or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			Net.join(address)
		await get_tree().create_timer(2.0).timeout
	return joined[0] or 1 in multiplayer.get_peers()


# --- Helpers ------------------------------------------------------------------------------------

## A vehicle of `model` standing on the compound's ground at (x, z).
func _spawn(model: String, pos: Vector3, yaw: float, faction := &"player") -> Vehicle:
	VehicleHull.prewarm(model)
	_n += 1
	var v := layer.server_spawn(model, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), level.ground_point(pos) + Vector3.UP * 0.3), "", faction, "vfx_%s_%d" % [model, _n])
	v.server_rearm()
	await _until(func() -> bool: return VehicleHull.is_ready(model), 20.0)
	await _seconds(1.2)
	return v


## Puts the player in `seat` of `v` (out of anything he's in first).
func _seat(v: Vehicle, seat: int) -> void:
	var ride := Vehicle.ride_of(player)
	if ride:
		ride.server_exit(player)
		await _physics(2)
	v.server_enter(player, seat)
	await _seconds(VehicleHud.GATHER_S * 3.0)


## `n` AI men beside `v`, not seated.
func _men(n: int, v: Vehicle) -> Array:
	var out: Array = []
	for i in n:
		_n += 1
		var s := level.spawn_soldier({"name": "FxCrew%d" % _n, "person_name": "Crew %d" % _n, "faction": "friendly", "variant": "woodland",
			"pos": v.global_position + Vector3(6.0, 0.1, float(i) * 1.2), "loadout": [], "combat": 0.5, "discipline": 0.6, "guard": true})
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
		out.append(s)
	await _physics(2)
	return out


func _clear(v: Vehicle, people: Array) -> void:
	if is_instance_valid(v):
		for s: Soldier in v.occupants():
			v.server_exit(s)
	await _physics(2)
	for p: Variant in people:
		if is_instance_valid(p) and p != player:
			(p as Node).queue_free()
	if is_instance_valid(v):
		v.queue_free()
	player.global_position = Vector3(0, 0.1, 0)
	await _seconds(0.3)


## Shell or warhead `id` into `v` at `local` (vehicle frame, outside) along `ldir`, the tiles missed.
func _hit(v: Vehicle, id: String, local: Vector3, ldir: Vector3) -> Dictionary:
	var w := Warheads.data(StringName(id))
	var hit := {"position": v.global_transform * local, "direction": (v.global_basis * ldir).normalized(), "shooter": null, "probe_m": 1.5,
		"force": {"coverage": false, "ricochet": false}}
	if w.is_empty():
		hit.merge({"kind": Vehicle.KINETIC, "shell": id})
	else:
		hit.merge({"kind": Warheads.kind_of(StringName(id)), "warhead": id, "penetration_mm": float(w.get("penetration_mm", 0.0)), "blast_kg": float(w.get("blast_kg", 0.0))})
	return v.server_take_hit(hit)


func _until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return cond.call()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
