extends Node
## Headless checks for the action animations (CharacterModel "Actions", GearRig draws):
## poses come from replicated state (carry_net, action_net) and nothing host-only; hands
## reach their targets (items, mounts, straps, wounds, bodies); a casualty is draped over the
## carrier's shoulders or dragged on its back, head first, and its hitboxes follow; the
## carrier's camera stays clear of it; the first-person view model lowers; AI bodies and
## dummies keep working.
##   <voxel godot exe> --headless --path . res://tests/animations_test.tscn
## Exits with the number of failures.

const SPOT := Vector3(0, 0.1, 20)
## How close a palm must get to its target (metres).
const HAND_TOLERANCE := 0.06
## How far the looted body's ragdoll is moved from its capsule (_test_loot).
const SLID := Vector3(-6.0, 0, 0)
## How far the downed body's ragdoll is moved before it's revived (_test_stand_where_it_lay).
const ROLLED := Vector3(2.5, 0, 2.0)

var failures := 0
var level: CompoundLevel
var player: Soldier
var alpha: Soldier    # friendly AI: the casualty
var bravo: Soldier    # friendly AI: carries
var hostile: Soldier  # becomes a dead body to loot


func _ready() -> void:
	GameState.zone_id = "test_animations" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	Soldier.respawn_delay_s = 0.0  # these checks want the old instant respawn (the wait and spawn
	Soldier.spawn_protect_s = 0.0  # protection have their own checks in gameplay and missions)
	CompoundLevel.spawn_ai = false
	Handedness._left = false  # right-handed whatever this machine's settings say (never saved)
	Handedness._loaded = true
	GameState.delete_save()
	get_tree().create_timer(260.0).timeout.connect(func() -> void:
		print("ANIMATIONS TEST FAILED (timed out)")
		get_tree().quit(99))
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # we place the player by hand
	_place_player()
	player.inventory.strip()
	for id: StringName in [&"plate_carrier", &"assault_pack", &"m4a1", &"m17"]:
		player.inventory.take(id)
	player.inventory.take(&"mag_556", 2)
	player.inventory.take(&"pressure_bandage", 3)
	alpha = _spawn_ai("Alpha", &"friendly", SPOT + Vector3(0, 0, -1.5), ["plate_carrier", "plate_steel_l3", "m4a1", "assault_pack"])
	bravo = _spawn_ai("Bravo", &"friendly", SPOT + Vector3(3.0, 0, 0), ["plate_carrier", "m4a1"])
	hostile = _spawn_ai("Hostile", &"hostile", SPOT + Vector3(-3.0, 0, 1.0), ["plate_carrier", "m4a1", "mag_556"])
	await _frames(10)
	_test_replication_config()
	_test_gear_sway()
	_test_seated_bones()
	_test_world_scale()
	_test_locomotion()
	_test_stance_and_carry()
	await _test_view_low_ready()
	await _test_carry()
	await _test_drag()
	await _test_put_down()
	await _test_from_replicated_state()
	await _test_human_casualty()
	await _test_ai_carry()
	await _test_pick_up()
	await _test_equip_and_draw()
	await _test_fingers()
	_test_feet()
	await _test_treat()
	await _test_techniques()
	await _test_treat_props()
	await _test_medic_view()
	await _test_self_treat_poses()
	await _test_patient_reactions()
	await _test_treat_timings()
	await _test_loot()
	await _test_looted_weapons()
	await _test_stand_where_it_lay()
	await _test_respawn_not_where_it_lay()
	await _test_dummy()
	await _test_faces()
	GameState.delete_save()
	print("ANIMATIONS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


## Gear secondary motion (queue 10): the pack's spring (GearRig.PACK_SWAY) lags behind the
## torso when it speeds up, settles once it's steady, isn't flung by a teleport, and swings out
## on a turn.
func _test_gear_sway() -> void:
	print("Gear sway")
	var c := GearRig.PACK_SWAY
	var pack := GearSway.make(c[0], c[1], c[2], c[3], c[4], c[5])
	for i in 18:  # 0.3 s speeding up forward (-Z) at 4 m/s^2
		pack.step(Vector3(0, 0, -4.0), 1.0 / 60.0)
	var lag := pack.offset()
	check(lag.z > 0.005 and lag.length() <= pack.reach + 0.0001,
		"speeding up, the pack lags back (%.3f m, at most %.2f)" % [lag.z, pack.reach])
	check(pack.turn().z.z < 1.0 and (pack.turn() * Vector3(0, -pack.hang, 0)).z > 0.0, "its bottom swings back, about its straps")
	for i in 120:  # 2 s steady
		pack.step(Vector3.ZERO, 1.0 / 60.0)
	check(pack.offset().length() < 0.002, "and settles once the pace is steady (%.4f m)" % pack.offset().length())
	pack.reset()
	var t := Transform3D.IDENTITY
	pack.follow(t, 1.0 / 60.0)
	t.origin = Vector3(40, 0, 0)  # respawned, or got out of a vehicle
	pack.follow(t, 1.0 / 60.0)
	pack.follow(t, 1.0 / 60.0)
	check(pack.offset().length() < 0.001, "a teleport doesn't fling it (%.4f m)" % pack.offset().length())
	pack.reset()
	t = Transform3D.IDENTITY
	pack.follow(t, 1.0 / 60.0)
	var yaw := 0.0
	var spin := 0.0
	for i in 12:  # turning left, faster and faster
		spin += 0.5
		yaw += spin / 60.0
		t.basis = Basis(Vector3.UP, yaw)
		pack.follow(t, 1.0 / 60.0)
	check(pack.offset().x < -0.001, "turning left, his back swings right and the pack lags behind it, to his left (%.4f m)" % pack.offset().x)
	pack.step(Vector3(0, 0, -4.0), 0.5)
	pack.reset()
	t = Transform3D.IDENTITY
	pack.follow(t, 1.0 / 60.0)
	pack.follow(t, 1.0 / 60.0)
	check(pack.offset().length() < 0.0001, "after a reset (ragdolled, hidden) standing still doesn't jolt it (%.4f m)" % pack.offset().length())
	pack.reset()
	t = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-88.0)), Vector3.ZERO)  # prone: the torso pitched flat
	pack.follow(t, 1.0 / 60.0)
	for i in 30:
		t.basis = Basis(Vector3.RIGHT, deg_to_rad(-88.0 + sin(i * 0.5) * 3.0))  # breathing, a little rock
		pack.follow(t, 1.0 / 60.0)
	check(absf(pack.offset().x) < 0.002, "lying prone it doesn't jitter side to side (%.4f m)" % pack.offset().x)


## Captain, 2026-10-14: riders in a UH-60M stood in their seats with rifles across the cabin.
## The seated pose: hips where it says, feet on its floor in front, the head at seated height,
## and a rifle in the hands muzzle down, its muzzle off a low seat's floor.
func _test_seated_bones() -> void:
	print("Seated pose")
	var pose := CharacterModel.seated_pose(0.55, -0.05, false)
	var bones := CharacterModel.with_shins(CharacterModel.pose_bones(pose, false))
	var shin := CharacterModel.LEG_LENGTH - CharacterModel.THIGH
	var pelvis: Vector3 = (bones.pelvis as Transform3D).origin
	var soles: Array[Vector3] = [(bones.shin_l as Transform3D) * Vector3(0, -shin, 0), (bones.shin_r as Transform3D) * Vector3(0, -shin, 0)]
	var head: Vector3 = (bones.head as Transform3D).origin
	check(absf(pelvis.y - 0.55) < 0.001, "the hips at the seat's height (%.2f)" % pelvis.y)
	check(soles.all(func(p: Vector3) -> bool: return absf(p.y - (-0.05 + CharacterModel.SEAT_SOLE_UP)) < 0.03 and p.z < pelvis.z - 0.2),
		"the feet on the floor, in front of the seat (%s)" % [soles])
	check(head.y < CharacterModel.TORSO_PIVOT.y + CharacterModel.HEAD_PIVOT.y - 0.2, "the head at seated height (%.2f)" % head.y)
	var art := VoxelArt.model_for(ItemDB.get_item(&"m4a1"))
	var held := GearRig.seated_transform(art, false, 0.3)
	var muzzle := held * (VoxelArt.butt_point(art) * Vector3(1, 1, -1))
	check((-held.basis.z).normalized().dot(Vector3.DOWN) > 0.9, "a rifle seated: muzzle down (%s)" % [-held.basis.z])
	check(CharacterModel.HANDS_ANCHOR.y + muzzle.y > -0.3, "and off a low seat's floor (muzzle %.2f over the hips)" % (CharacterModel.HANDS_ANCHOR.y + muzzle.y))


## World scale (docs/animation.md): the eye where a 1.80 m man's is, under a doorway's
## head; the view setting horizontal at 16:9, the camera's vertical angle from it.
func _test_world_scale() -> void:
	print("World scale")
	var eye := func(st: int) -> float: return CharacterModel.eye_position(SoldierMovement.pose_for(st, 0, 0.0)).y
	var stand: float = eye.call(SoldierMovement.Stance.STAND_HIGH)
	var crouch: float = eye.call(SoldierMovement.Stance.CROUCH_MID)
	var prone: float = eye.call(SoldierMovement.Stance.PRONE)
	var head := VoxelArt.instance(VoxelArt.body_part("head", VoxelArt.MALE), "multicam")
	var mesh := head.get_child(0) as MeshInstance3D
	var top := CharacterModel.TORSO_PIVOT.y + CharacterModel.HEAD_PIVOT.y + (mesh.transform * mesh.mesh.get_aabb()).end.y  # the head's top
	head.free()
	check(absf(stand - 1.65) < 0.02 and stand / top > 0.9 and stand / top < 0.95 and stand < BuildingGen.DOOR_H - 0.3,
		"standing eye %.2f m on a %.2f m man (%.0f%%; real 91-94%%), under a %.1f m door" % [stand, top, stand / top * 100.0, BuildingGen.DOOR_H])
	check(crouch > 0.9 and crouch < 1.15 and prone > 0.2 and prone < 0.45, "crouched eye %.2f m, prone %.2f m" % [crouch, prone])
	check(bool(GameSettings.DEFAULTS.video.head_bob) and player.camera.position.length() < 0.001, "head bob on by default (a settings toggle), the view still standing still (%s)" % player.camera.position)
	check(is_equal_approx(float(GameSettings.DEFAULTS.video.hfov), 90.0) and absf(GameSettings.vertical_fov(90.0) - 58.72) < 0.01
		and absf(GameSettings.vertical_fov(112.33) - 80.0) < 0.05,
		"the view: 90 deg across 16:9 by default, a %.1f deg vertical camera (the old 80 vertical was 112 across)" % GameSettings.vertical_fov(90.0))


## Locomotion (docs/animation.md): a model walked along by hand at each pace and stance shows
## its cycle, and a planted foot stays where it landed (no sliding) whatever the direction.
func _test_locomotion() -> void:
	print("Locomotion")
	var stand := SoldierMovement.Stance.STAND_HIGH
	var crouch := SoldierMovement.Stance.CROUCH_MID
	for c: Array in [
			[stand, 1.4, Vector3.FORWARD, "male", CharacterModel.WALK],
			[stand, SoldierMovement.WALK_SPEED, Vector3.FORWARD, "male", CharacterModel.JOG],
			[stand, SoldierMovement.SPRINT_SPEED, Vector3.FORWARD, "male", CharacterModel.SPRINT],
			[stand, SoldierMovement.WALK_SPEED, Vector3.RIGHT, "male", CharacterModel.JOG],
			[stand, SoldierMovement.WALK_SPEED, Vector3.BACK, "male", CharacterModel.JOG],
			[stand, 3.0, Vector3(-1, 0, -1).normalized(), "male", CharacterModel.JOG],
			[stand, SoldierMovement.SPRINT_SPEED, Vector3.FORWARD, "female", CharacterModel.SPRINT],
			[crouch, SoldierMovement.CROUCH_SPEED, Vector3.FORWARD, "male", CharacterModel.CROUCH_WALK],
			[crouch, SoldierMovement.CROUCH_SPEED, Vector3.LEFT, "male", CharacterModel.CROUCH_WALK]]:
		var seen := _walk_model(c[0], c[1], c[2], c[3])
		check(seen.gait == c[4] and seen.planted >= 2 and seen.slide < 0.02,
			"%s %s at %.1f m/s %s: %s cycle (%s), %d footfalls, a planted foot slides %.3f m at most" % [c[3], "standing" if c[0] == stand else "crouched", c[1], c[2], c[4], seen.gait, seen.planted, seen.slide])
	var crawl := _walk_model(SoldierMovement.Stance.PRONE, SoldierMovement.PRONE_SPEED, Vector3.FORWARD, "male")
	var idle := _walk_model(stand, 0.0, Vector3.FORWARD, "male")
	check(crawl.gait == CharacterModel.CRAWL and idle.gait == CharacterModel.IDLE and idle.weight == 0.0,
		"prone it crawls (%s); stood still, idle (%s, cycle shown %.2f)" % [crawl.gait, idle.gait, idle.weight])


## Walks a fresh model `speed` m/s along `dir` (its own space; it faces -Z) in `stance` for
## 4 s, by hand at 60 frames a second, and reports its cycle, how many times a foot was put
## down in the last 2.5 s, and the furthest a planted foot moved.
## The Captain's Star Citizen reference (2026-10-18, B:/Contractor-refs/captures/2026-10-18):
## going prone is a move (the hands out to the floor), so is getting up (pushing off it); on the
## move the rifle is carried muzzle-down; reloading it rolls onto its side.
func _test_stance_and_carry() -> void:
	print("Stance moves, the carry on the move, the reload roll")
	var holder := Node3D.new()
	holder.position = Vector3(420, 0, 420)
	add_child(holder)
	var model := CharacterModel.new()
	model.lod = false
	holder.add_child(model)
	model.set_process(false)
	var dt := 1.0 / 60.0
	model.pose = SoldierMovement.pose_for(SoldierMovement.Stance.STAND_HIGH, 0, 0.0)
	for i in 10:
		model._process(dt)
	model.pose = SoldierMovement.pose_for(SoldierMovement.Stance.PRONE, 0, 0.0)
	model._process(dt)
	check(model.stance_move().get("kind", &"") == &"down", "going prone: a move, not a snap")
	for i in 12:
		model._process(dt)
	var hands := model._stance_hands()
	var floor_y := holder.global_position.y
	check(hands.size() == 2 and hands.all(func(h: Array) -> bool: return absf(model.torso.to_global(h[1]).y - floor_y) < 0.12),
		"the hands go out to the floor and take the weight (a dive)")
	for i in 45:
		model._process(dt)
	check(model.stance_move().is_empty(), "then it lies prone")
	model.pose = SoldierMovement.pose_for(SoldierMovement.Stance.STAND_HIGH, 0, 0.0)
	model._process(dt)
	check(model.stance_move().get("kind", &"") == &"up" and not model._stance_hands().is_empty(), "getting up: it pushes off the floor")
	holder.queue_free()
	var art := VoxelArt.model_for(ItemDB.get_item(&"m4a1"))
	var ready := GearRig.held_transform(art, false, false)
	var run := GearRig.held_transform(art, false, false, NAN, 1.0)
	var reload := GearRig.held_transform(art, false, false, NAN, 0.0, 1.0)
	var aim := GearRig.held_transform(art, true, false, NAN, 1.0, 1.0)
	check((-run.basis.z).y < (-ready.basis.z).y - 0.3, "on the move the rifle's carried muzzle-down (%.2f vs %.2f)" % [(-run.basis.z).y, (-ready.basis.z).y])
	check(absf(reload.basis.x.y) > 0.4, "reloading it's rolled onto its side (%.2f)" % reload.basis.x.y)
	check(aim.is_equal_approx(GearRig.held_transform(art, true, false)), "aiming, neither applies")
	var kicked := GearRig.held_transform(art, true, false, NAN, 0.0, 0.0, 1.0)
	var aimed := GearRig.held_transform(art, true, false)
	check((-kicked.basis.z).y > (-aimed.basis.z).y + 0.05 and kicked.origin.z > aimed.origin.z, "a shot kicks the rifle back and its muzzle up")
	var walled := GearRig.held_transform(art, false, false, NAN, 0.0, 0.0, 0.0, 1.0)
	check((-walled.basis.z).y > (-ready.basis.z).y + 0.3 and walled.origin.z > ready.origin.z + 0.1, "against a wall the rifle comes back and tips up (compressed)")
	# Feel round 2: third person follows the reload's own keys (CharacterModel.reload_pose), as first
	# person does: rolled in and brought in for the new magazine, back at the ready at either end.
	var gain := CharacterModel.RELOAD_POSE_GAIN
	var keyed := func(fam: StringName, u: float) -> Transform3D:
		var at := Reloads.sample(Reloads.keys(fam, false), u)
		return GearRig.held_transform(art, false, false, NAN, 0.0, 1.0, 0.0, 0.0, [(at.pos as Vector3) * gain, (at.rot as Vector3) * gain])
	var look: Transform3D = keyed.call(Reloads.AR, 0.62)
	check(absf(look.basis.x.y) > 0.4 and look.origin.distance_to(ready.origin) > 0.03 and (keyed.call(Reloads.AR, 0.0) as Transform3D).is_equal_approx(ready)
		and (keyed.call(Reloads.AR, 1.0) as Transform3D).is_equal_approx(ready),
		"third person, the reload's keys pose the rifle: rolled %.2f and brought in for the magazine, at the ready at the ends" % look.basis.x.y)
	check(not (keyed.call(Reloads.BULLPUP, 0.62) as Transform3D).is_equal_approx(look), "each family its own pose (the L85 forward and down out of the shoulder)")
	# Feel round 2: climbing forces the weapon low (the run carry), standing still or not.
	var climb_at := Node3D.new()
	climb_at.position = Vector3(430, 0, 420)
	add_child(climb_at)
	var climber := CharacterModel.new()
	climber.lod = false
	climb_at.add_child(climber)
	climber.set_process(false)
	climber.pose = SoldierMovement.pose_for(SoldierMovement.Stance.STAND_HIGH, 0, 0.0)
	climber.climbing = true
	for i in 30:
		climber._process(dt)
	var low := climber.run_carry()
	climber.climbing = false
	for i in 60:
		climber._process(dt)
	check(low > 0.9 and climber.run_carry() < 0.1, "climbing, the rifle's carried low (%.2f), then back up (%.2f)" % [low, climber.run_carry()])
	climb_at.queue_free()


## First person: not aiming or firing for a moment, the weapon eases down to the low ready.
func _test_view_low_ready() -> void:
	print("First person: the low ready")
	var pi := player.player_input
	if pi == null:
		check(false, "the player's input")
		return
	player.is_aiming = false
	await _seconds(PlayerInput.LOW_READY_AFTER_S + 1.0)
	check(float(pi.view_carry().low) > 0.8, "idle: the weapon at the low ready (%.2f)" % float(pi.view_carry().low))


func _walk_model(stance: int, speed: float, dir: Vector3, body: String) -> Dictionary:
	var holder := Node3D.new()
	holder.position = Vector3(400, 0, 400)
	holder.rotation.y = 0.7
	add_child(holder)
	var model := CharacterModel.new()
	model.body = body
	model.lod = false
	holder.add_child(model)
	model.set_process(false)
	model.pose = SoldierMovement.pose_for(stance, 0, 0.0)
	var dt := 1.0 / 60.0
	var world_dir := holder.global_basis * dir
	var slide := 0.0
	var planted := 0
	var down_at: Array = [null, null]
	var feet := {"pitch_max": -INF, "pitch_min": INF, "toes": false}
	for i in 240:
		holder.position += world_dir * speed * dt
		model._process(dt)
		if i < 90:
			continue
		for left in [true, false]:
			feet.pitch_max = maxf(feet.pitch_max, model.foot_pitch(left))
			feet.pitch_min = minf(feet.pitch_min, model.foot_pitch(left))
			feet.toes = feet.toes or model.foot_toes(left)
		for f in 2:
			var sole := model.foot_position(f == 0)
			if sole.y - holder.position.y < 0.002:
				if down_at[f] == null:
					down_at[f] = sole
					planted += 1
				slide = maxf(slide, _flat(sole, down_at[f]))
			else:
				down_at[f] = null
	var out := {"gait": model.gait(), "slide": slide, "planted": planted, "weight": model.gait_weight(),
		"pitch_max": feet.pitch_max, "pitch_min": feet.pitch_min, "toes": feet.toes}
	holder.queue_free()
	return out


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _test_replication_config() -> void:
	print("Replication")
	var soldier: Node = load("res://scenes/soldier.tscn").instantiate()
	var config: SceneReplicationConfig = soldier.get_node(^"ServerSync").replication_config
	for prop: NodePath in [^"Model:carry_net", ^"Model:action_net"]:
		check(config.has_property(prop) and config.property_get_spawn(prop)
			and config.property_get_replication_mode(prop) == SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE,
			"%s replicates from the host on change, and to late joiners on spawn" % prop)
	var owner: SceneReplicationConfig = soldier.get_node(^"Sync").replication_config
	check(owner.has_property(^"Movement:mantling") and owner.property_get_spawn(^"Movement:mantling")
		and owner.property_get_replication_mode(^"Movement:mantling") == SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE,
		"climbing (Movement:mantling) replicates from its owner on change: every peer lowers the weapon for it (feel round 2)")
	soldier.free()


# --- Carry and drag -------------------------------------------------------------------------

func _test_carry() -> void:
	print("Fireman's carry")
	_down(alpha)
	alpha.global_position = SPOT + Vector3(0, 0, -1.5)
	await _frames(2)
	player._server_carry_body.rpc_id(1, alpha.get_path())
	check(player.carrying == alpha and player.model.carry_net.get("mode") == CharacterModel.CARRY
		and player.model.carry_net.get("with") == String(alpha.get_path()), "the carrier's carry_net: carrying Alpha")
	check(alpha.model.carry_net.get("mode") == CharacterModel.CARRIED and alpha.model.carry_net.get("with") == String(player.get_path()),
		"the casualty's carry_net: carried by the player")
	await _seconds(Soldier.CARRY_LIFT_S + 0.5)  # picked up off the ground, then up on the shoulder
	check(alpha.model.carry_shown().get("mode") == CharacterModel.CARRIED and player.model.carry_shown().get("mode") == CharacterModel.CARRY,
		"both models show the carry")
	var hips := player.model.torso.to_global(CharacterModel.CARRY_HIPS)
	check(alpha.model.torso.global_position.distance_to(hips) < 0.05,
		"the casualty's hips rest across the carrier's shoulders (%.2f m off)" % alpha.model.torso.global_position.distance_to(hips))
	var pelvis := _part(alpha, Vitals.PELVIS)
	var head := _part(alpha, Vitals.HEAD)
	var shin := _part(alpha, Vitals.SHIN_R)
	check(pelvis.y > player.global_position.y + 1.35, "carried high, over the shoulders (pelvis %.2f m up)" % (pelvis.y - player.global_position.y))
	check(head.y < pelvis.y - 0.25 and shin.y < pelvis.y - 0.25,
		"limp and draped, not a plank: head %.2f m and shins %.2f m below the hips" % [pelvis.y - head.y, pelvis.y - shin.y])
	var at_head := player.to_local(head)
	var at_shin := player.to_local(shin)
	check(at_head.z > 0.1 and at_head.x < 0.1 and at_shin.z < 0.05 and at_shin.x > 0.2,
		"folded over the right shoulder: head and arms down the back, legs down the front on the right (head %s, shin %s)" % [at_head.snapped(Vector3.ONE * 0.01), at_shin.snapped(Vector3.ONE * 0.01)])
	for i in 2:
		var target := player.model.torso.to_global(CharacterModel.CARRY_HANDS[i])
		var off := player.model.hand_position(i == 0).distance_to(target)
		check(off < HAND_TOLERANCE, "carrier's %s hand holds the casualty (%.1f cm off)" % ["right" if i == 0 else "left", off * 100.0])
	check(alpha.model.hand_position(true).y < _part(alpha, Vitals.UPPER_ARM_R).y - 0.2, "the casualty's arms hang down")
	check(player.model.hand_error() < 0.0 and player.model.hands_busy(), "the rifle is slung: both hands are on the casualty")
	check(is_equal_approx(player.model.view_lower(), 1.0), "first person: the view model is lowered")
	_check_camera_clear(player, alpha, "carrying")


func _test_drag() -> void:
	print("Drag")
	player._server_drag_body.rpc_id(1, alpha.get_path())
	check(player.model.carry_net.get("mode") == CharacterModel.DRAG and alpha.model.carry_net.get("mode") == CharacterModel.DRAGGED,
		"switching to a drag updates both sides")
	player.global_position += Vector3(0, 0, -1.0)
	await _seconds(0.7)
	var back := alpha.model.torso.global_basis.z  # the casualty's back
	check(back.dot(Vector3.UP) < -0.6, "the casualty lies on its back (back faces %.2f up)" % back.dot(Vector3.UP))
	var head := _part(alpha, Vitals.HEAD)
	var pelvis := _part(alpha, Vitals.PELVIS)
	check(_flat(head, player.global_position) < _flat(pelvis, player.global_position) - 0.3, "head first, towards the dragger")
	var behind := player.to_local(pelvis).z
	check(behind > 0.8, "the casualty is behind the dragger's direction of travel (%.2f m)" % behind)
	check(pelvis.y - player.global_position.y < 0.4 and head.y > pelvis.y, "the hips on the ground, the shoulders lifted by the collar")
	for i in 2:
		var hand := alpha.model.hand_position(i == 0)
		var shoulder := _part(alpha, Vitals.UPPER_ARM_R if i == 0 else Vitals.UPPER_ARM_L)
		check(_flat(hand, player.global_position) > _flat(shoulder, player.global_position) and hand.y < shoulder.y,
			"its %s arm trails along the ground" % ["right" if i == 0 else "left"])
	var dragger_head := player.to_local(_part(player, Vitals.HEAD))
	check(dragger_head.z > 0.2 and dragger_head.y < 1.3, "the dragger is bent at the hips towards the casualty, facing it (head at %s)" % dragger_head)
	for i in 2:
		var strap := alpha.model.torso.to_global(CharacterModel.STRAP_POINTS[i])
		var off := player.model.hand_position(i == 0).distance_to(strap)
		check(off < HAND_TOLERANCE, "dragger's %s hand on the casualty's shoulder strap (%.1f cm off)" % ["right" if i == 0 else "left", off * 100.0])
	_check_camera_clear(player, alpha, "dragging")


func _test_put_down() -> void:
	print("Put down")
	player._server_release_body.rpc_id(1)
	check(player.model.carry_net.is_empty() and alpha.model.carry_net.is_empty(), "letting go clears both sides")
	await _seconds(0.6)
	check(alpha.model.transform.is_equal_approx(alpha.model.base_transform()) and alpha.model.carry_shown().is_empty() and alpha.model.downed,
		"the casualty lies where its own body is again")
	check(not player.model.hands_busy() and is_equal_approx(player.model.view_lower(), 0.0), "the carrier's hands are free")
	await _seconds(0.5)
	check(player.model.hand_error() >= 0.0 and player.model.hand_error() < 0.02, "and the rifle is drawn again (%.3f)" % player.model.hand_error())


## A peer only has the replicated state (no carried_by, carrying or carry_mode, which are
## host-only): the poses must follow carry_net alone.
func _test_from_replicated_state() -> void:
	print("Poses from replicated state only")
	_down(hostile)
	# A late joiner's first snapshot is already down and being dragged. It must not
	# replay a new fall instead of taking the held pose.
	hostile.model._was_downed = false
	hostile.model._downed_t = 0.0
	hostile.global_position = bravo.global_position + Vector3(0, 0, 1.1)
	await _frames(2)
	check(hostile.carried_by == null and bravo.carrying == null and bravo.carry_mode == &"", "no host-side carry at all")
	bravo.model.carry_net = {"mode": CharacterModel.DRAG, "with": String(hostile.get_path())}
	hostile.model.carry_net = {"mode": CharacterModel.DRAGGED, "with": String(bravo.get_path())}
	await _seconds(0.7)
	var strap := hostile.model.torso.to_global(CharacterModel.STRAP_POINTS[0])
	check(hostile.model.carry_shown().get("mode") == CharacterModel.DRAGGED and bravo.model.hand_position(true).distance_to(strap) < HAND_TOLERANCE,
		"as a late joiner gets it: the drag shows from carry_net alone")
	check(_flat(_part(hostile, Vitals.HEAD), bravo.global_position) < _flat(_part(hostile, Vitals.PELVIS), bravo.global_position),
		"with the casualty head first to the dragger")
	hostile.model.carry_net = {}
	bravo.model.carry_net = {}
	hostile.vitals.server_reset_health()
	await _seconds(0.5)
	check(hostile.model.transform.is_equal_approx(hostile.model.base_transform()) and not hostile.model.downed, "cleared, both stand again")


func _test_human_casualty() -> void:
	print("Human casualty")
	_down(player)
	bravo.global_position = player.global_position + Vector3(1.5, 0, 0)
	await _frames(2)
	bravo._server_carry_body.rpc_id(1, player.get_path())
	check(player.model.carry_net.get("mode") == CharacterModel.CARRIED and bravo.model.carry_net.get("mode") == CharacterModel.CARRY,
		"a downed player carried by an AI squadmate")
	await _seconds(Soldier.CARRY_LIFT_S + 0.5)
	# The player's own body isn't moved here (their machine does that): the drawn body
	# still rides on Bravo, because it follows the carrier, not its own replicated transform.
	var hips := bravo.model.torso.to_global(CharacterModel.CARRY_HIPS)
	check(player.model.torso.global_position.distance_to(hips) < 0.05, "drawn over Bravo's shoulders wherever its own body is")
	bravo._server_drag_body.rpc_id(1, player.get_path())
	await _seconds(Soldier.DRAG_GRAB_S + 0.5)
	var strap := player.model.torso.to_global(CharacterModel.STRAP_POINTS[1])
	check(bravo.model.hand_position(false).distance_to(strap) < HAND_TOLERANCE, "and dragged by the strap")
	bravo._server_release_body.rpc_id(1)
	player.vitals.server_reset_health()
	player.carried_by_pos = null
	_place_player()
	await _seconds(0.5)
	check(player.model.carry_net.is_empty() and player.model.transform.is_equal_approx(player.model.base_transform()), "put down, and up again")


func _test_ai_carry() -> void:
	print("AI casualty care")
	alpha.global_position = bravo.global_position + Vector3(0.0, 0, -1.0)
	await _frames(2)
	check(bravo.server_pick_up_body(alpha, Soldier.CARRY) and bravo.model.carry_net.get("mode") == CharacterModel.CARRY
		and alpha.model.carry_net.get("mode") == CharacterModel.CARRIED, "AI care (server_pick_up_body) sets the same state")
	bravo._set_carry_mode(Soldier.DRAG)
	check(bravo.model.carry_net.get("mode") == CharacterModel.DRAG and alpha.model.carry_net.get("mode") == CharacterModel.DRAGGED,
		"switching to a drag the way squad AI does")
	bravo.global_position += Vector3(0, 0, -0.5)
	await _seconds(0.7)
	check(bravo.model.hand_position(true).distance_to(alpha.model.torso.to_global(CharacterModel.STRAP_POINTS[0])) < HAND_TOLERANCE,
		"the AI drags by the strap too")
	alpha.vitals.server_reset_health()
	await _frames(3)
	check(bravo.carrying == null and bravo.model.carry_net.is_empty() and alpha.model.carry_net.is_empty(),
		"a casualty who comes round is let go, and both poses clear")
	_place(alpha, SPOT + Vector3(0, 0, -1.5))
	_place(bravo, SPOT + Vector3(3.0, 0, 0))


# --- Hands ----------------------------------------------------------------------------------

func _test_pick_up() -> void:
	print("Pick up")
	_place_player()
	await _seconds(0.6)
	var item := await _spawn_item(&"mag_556", player.global_position + Vector3(0.1, 0.3, -0.5))
	await _seconds(0.5)  # settles on the ground
	check(item != null, "a magazine on the ground in front")
	if item == null:
		return
	var rest_low := player.model.torso.global_position.y
	player._server_interact.rpc_id(1, item.get_path())
	var at: Vector3 = player.model.action_net.get("at", Vector3.INF)
	check(player.model.action_net.get("id") == CharacterModel.PICK_UP and player.model.action_net.get("to") == &"pouch",
		"the host starts a pickup that ends in a pouch")
	check(at.distance_to(player.to_local(item.global_position)) < 0.05, "aimed at the item (%s)" % at)
	var seen := {"best": INF, "low": rest_low, "lower": 0.0, "view": player.view_model.position.y}
	await _watch(CharacterModel.PICK_UP_S, func() -> void:
		seen.best = minf(seen.best, player.model.hand_position(true).distance_to(player.to_global(at)))
		seen.low = minf(seen.low, player.model.torso.global_position.y)
		seen.lower = maxf(seen.lower, player.model.view_lower())
		seen.view = minf(seen.view, player.view_model.position.y))
	check(seen.best < HAND_TOLERANCE, "the hand reaches the item (%.1f cm)" % (seen.best * 100.0))
	check(rest_low - seen.low > 0.25, "bending or kneeling to reach it (hips %.2f m lower)" % (rest_low - seen.low))
	check(seen.lower > 0.8 and seen.view < PlayerInput.HIP_VIEW.y - 0.08, "first person: the view model ducks (%.2f)" % seen.view)
	await _seconds(0.6)
	check(player.model.action_net.is_empty() and player.model.action_shown() == &"", "the host clears the finished clip (nothing for late joiners to replay)")
	check(absf(player.model.torso.global_position.y - rest_low) < 0.03, "and stands back up")


func _test_equip_and_draw() -> void:
	print("Equip, stow and draw")
	var gear: GearRig = player.gear
	await _seconds(0.5)
	player._server_inventory_action.rpc_id(1, "stow_slot", &"", -1, &"sidearm", &"")
	check(player.model.action_net.get("id") == CharacterModel.EQUIP and player.model.action_net.get("from") == &"holster",
		"stowing the pistol: from the holster (%s)" % player.model.action_net)
	await _check_mount_path(player.model.action_net.get("from"), player.model.action_net.get("to"))
	var where := _entry_of(player, &"m17")
	check(not where.is_empty(), "the pistol went into %s" % where.get("container", "nothing"))
	if where.is_empty():
		return
	await _seconds(0.4)
	player._server_inventory_action.rpc_id(1, "equip_entry", where.container, where.index, &"", &"")
	check(player.model.action_net.get("from") == CharacterModel.CONTAINER_MOUNTS[where.container] and player.model.action_net.get("to") == &"holster",
		"equipping it: from the %s to the holster" % where.container)
	await _check_mount_path(player.model.action_net.get("from"), player.model.action_net.get("to"))
	await _seconds(0.5)
	check(player.inventory.slots[&"sidearm"] == &"m17", "the pistol is back in its holster")
	# Switching weapons (replicated active_slot): the hand fetches the pistol first.
	var grip := player.model.torso.to_global(gear._rest_grip(&"sidearm"))
	player.select_weapon(&"sidearm")
	var seen := {"best": INF, "drawing": false}
	await _watch(CharacterModel.DRAW_S, func() -> void:
		seen.drawing = seen.drawing or gear.drawing()
		seen.best = minf(seen.best, player.model.hand_position(true).distance_to(player.model.torso.to_global(gear._rest_grip(&"sidearm")))))
	check(seen.drawing and seen.best < HAND_TOLERANCE, "drawing the pistol: the hand goes to the holster first (%.1f cm)" % (seen.best * 100.0))
	await _seconds(0.3)
	var error := player.model.hand_error()
	check(error >= 0.0 and error < 0.015 and grip.distance_to(player.model.hand_position(true)) > 0.1, "then holds it up (%.1f cm)" % (error * 100.0))
	player.select_weapon(&"primary")
	await _seconds(0.6)


## Fingers (HandPose, 2026-10-20): hands are a palm, four fingers and a thumb at 0.5 cm, in poses
## swapped by what the hand does: the firing grip on a weapon up (the trigger finger on the trigger
## aimed, squeezing on a shot), the support grip, palms turned to the weapon; first person the same.
func _test_fingers() -> void:
	print("Fingers")
	var spec := VoxelArt._spec(HandPose.model(HandPose.OPEN, false, false))
	check(is_equal_approx(float(spec.voxel) / int(spec.sub), VoxelArt.FINE_VOXEL), "the hand is built in 0.5 cm voxels (%.4f m)" % (float(spec.voxel) / int(spec.sub)))
	for body in VoxelArt.BODIES:
		for bare in [false, true]:
			var n := _finger_count(HandPose.model(HandPose.OPEN, false, bare, body))
			check(n == 4, "%s %s hand, open: four fingers across it below the knuckles (%d)" % [body, "bare" if bare else "gloved", n])
	var male_w := _hand_width(HandPose.model(HandPose.OPEN, false, false))
	var female_w := _hand_width(HandPose.model(HandPose.OPEN, false, false, VoxelArt.FEMALE))
	check(female_w < male_w, "a woman's hand is smaller (%.1f cm across the knuckles, his %.1f)" % [female_w * 100.0, male_w * 100.0])
	var model := player.model
	player.select_weapon(&"primary")
	player.is_aiming = false
	await _seconds(CharacterModel.TRIGGER_HOLD_S + 0.6)
	check(model.hand_pose(0) == HandPose.GRIP and model.hand_pose(1) == HandPose.SUPPORT,
		"a rifle up: the firing grip, the index along the frame, and the support grip (%s, %s)" % [model.hand_pose(0), model.hand_pose(1)])
	var fore: Node3D = model.part_node(Vitals.FOREARM_R)
	check(String(fore.get_meta(&"voxel_model", "")) == HandPose.model(HandPose.GRIP, false, VoxelArt.hands_bare(model.variant), model.body),
		"the right forearm is drawn in it (%s)" % fore.get_meta(&"voxel_model", ""))
	var held: Node3D = model._held
	if is_instance_valid(held):
		var palm := fore.global_basis.orthonormalized() * HandPose.palm_normal(false)
		check(palm.dot(-held.global_basis.x.normalized()) > 0.6, "the firing palm turned in to the grip (%.2f)" % palm.dot(-held.global_basis.x.normalized()))
		var support := model.part_node(Vitals.FOREARM_L).global_basis.orthonormalized() * HandPose.palm_normal(true)
		check(support.dot(held.global_basis.y.normalized()) > 0.3, "the support palm up under the handguard (%.2f)" % support.dot(held.global_basis.y.normalized()))
	var error := model.hand_error()
	check(error >= 0.0 and error < 0.015, "the grips' grasp centres on the grip and the handguard (%.1f cm)" % (error * 100.0))
	var resting := (fore.get_child(0) as MeshInstance3D).mesh
	model.kick(1.0)
	await _frames(2)
	check(model.hand_pose(0) == HandPose.PRESS and (fore.get_child(0) as MeshInstance3D).mesh != resting, "a shot: the trigger finger squeezes (%s)" % model.hand_pose(0))
	await _seconds(CharacterModel.PRESS_S + 0.15)
	check(model.hand_pose(0) == HandPose.TRIGGER, "and lets off, still on the trigger (%s)" % model.hand_pose(0))
	await _seconds(CharacterModel.TRIGGER_HOLD_S)
	check(model.hand_pose(0) == HandPose.GRIP, "and back along the frame a while after (%s)" % model.hand_pose(0))
	# Aiming (an AI's: the player's own aim follows the mouse, which a headless test hasn't got).
	bravo.active_slot = &"primary"
	bravo.want_aim = true
	await _seconds(0.8)
	check(bravo.model.hand_pose(0) == HandPose.TRIGGER and bravo.model.hand_pose(1) == HandPose.SUPPORT,
		"an AI aiming: the finger on the trigger, the support grip (%s, %s)" % [bravo.model.hand_pose(0), bravo.model.hand_pose(1)])
	bravo.want_aim = false
	# First person: the view model's forearms have the same hands.
	var pi := player.player_input
	if pi:
		await _frames(3)
		var arms := player.view_model.get_children().filter(func(a: Node) -> bool: return a.has_meta(&"hand_pose") and not a.is_queued_for_deletion())
		var posed := arms.filter(func(a: Node) -> bool: return String(a.get_meta(&"voxel_model", "")).contains(":") and HandPose.TABLE.has(HandPose.pose_of(String(a.get_meta(&"voxel_model", "")))))
		check(arms.size() == 2 and posed.size() == 2, "first person: both forearms have fingers (%d of %d posed)" % [posed.size(), arms.size()])
		var poses := pi.view_hand_poses()
		check(poses.size() == 2 and poses[0] == HandPose.GRIP and poses[1] == HandPose.SUPPORT, "the firing grip, the index along the frame, and the support grip (%s)" % [poses])
		player._kick(player.active_weapon())
		for i in 3:  # (physics ticks: headless, process frames can run many to a tick)
			await get_tree().physics_frame
		check(pi.view_hand_poses()[0] == HandPose.PRESS, "a shot in first person: the trigger finger moves (%s)" % [pi.view_hand_poses()])
		var mesh := (arms[0].get_child(0) as MeshInstance3D).mesh if arms.size() > 0 else null
		await _seconds(CharacterModel.PRESS_S + 0.15)
		check(pi.view_hand_poses()[0] == HandPose.TRIGGER and (arms[0].get_child(0) as MeshInstance3D).mesh != mesh, "and back on it")
	player.is_aiming = false
	# The hook for props in the hand (the treatment session): a pose held and an anchor in the hand.
	model.set_hand_pose(1, HandPose.PINCH)
	await _frames(2)
	var anchor := model.hand_anchor(1)
	check(model.hand_pose(1) == HandPose.PINCH and anchor.get_parent() == model.part_node(Vitals.FOREARM_L)
		and anchor.global_position.distance_to(model.hand_position(false)) < 0.001, "set_hand_pose holds a pose; hand_anchor is its grasp centre")
	model.set_hand_pose(1, &"")
	await _frames(2)
	check(model.hand_pose(1) == HandPose.SUPPORT, "and let go, the hand is back on the handguard (%s)" % model.hand_pose(1))


## Feet (Feet, 2026-10-21): boots, sneakers, shoes, sandals and bare feet at 0.5 cm, each foot on an
## ankle of its own: flat standing, the heel striking with the toes up and pushing off the bent
## toes walking, the toes tucked kneeling on that knee and prone.
func _test_feet() -> void:
	print("Feet")
	for style in Feet.STYLES:
		var spec := VoxelArt._spec(Feet.model(style, false, false))
		var occ := VoxelArt.occupancy(Feet.model(style, false, false))
		var length := _solid_extent(occ, 2)
		check(is_equal_approx(float(spec.voxel) / int(spec.sub), VoxelArt.FINE_VOXEL) and length > 0.24 and length < 0.34,
			"%s: built in 0.5 cm voxels, %.1f cm long" % [style, length * 100.0])
	var boot := Feet.model(Feet.BOOTS, false, false)
	var heel := _sole_depth(boot, 0.04)
	var ball := _sole_depth(boot, -0.13)
	check(heel > ball + 0.004, "a boot's sole has a heel (%.1f cm of sole under the heel, %.1f under the ball)" % [heel * 100.0, ball * 100.0])
	var toes := _toe_count(VoxelArt.occupancy(Feet.model(Feet.BARE, false, false)))
	check(toes == 5, "a bare foot has five toes (%d)" % toes)
	check(Feet.style_of("multicam") == Feet.BOOTS and Feet.style_of("banner") == Feet.SNEAKERS
		and Feet.style_of("civ:a8a49a:a8a49a:b07a52:4a3f35:sandals") == Feet.SANDALS
		and Feet.style_of("civ:a8a49a:a8a49a:b07a52:3a3027") == Feet.BOOTS
		and Feet.STYLES.has(Feet.style_of("civ:aaaaaa:bbbbbb:b07a52:6b4a2b")),
		"footwear by kit: contractors in boots, Banner in sneakers, sandals where named, plain clothes their own")
	var model := player.model
	var foot := model.foot_node(true)
	check(foot != null and foot.get_parent() == model.part_node(Vitals.SHIN_L) and String(foot.get_meta(&"voxel_model", "")).begins_with("foot:boots"),
		"each foot is its own part on the shin's ankle (%s)" % (foot.get_meta(&"voxel_model", "") if foot else "none"))
	check(absf(model.foot_pitch(true)) < 0.12 and absf(model.foot_pitch(false)) < 0.12,
		"standing: both soles flat on the ground (%.2f, %.2f rad)" % [model.foot_pitch(true), model.foot_pitch(false)])
	var walk := _walk_model(SoldierMovement.Stance.STAND_HIGH, 1.4, Vector3.FORWARD, VoxelArt.MALE)
	check(walk.pitch_max > 0.15 and walk.pitch_min < -0.3 and walk.toes,
		"walking: the heel strikes with the toes up (%.2f), the foot pushes off its bent toes (%.2f)" % [walk.pitch_max, walk.pitch_min])
	var run := _walk_model(SoldierMovement.Stance.STAND_HIGH, 5.0, Vector3.FORWARD, VoxelArt.FEMALE)
	check(run.pitch_min < -0.3 and run.toes, "running (a woman's): the same roll off the toes (%.2f)" % run.pitch_min)
	var kneel := _posed_feet(SoldierMovement.Stance.CROUCH_LOW)
	check(kneel.toes[1] and kneel.pitch[1] < -0.6 and absf(kneel.pitch[0]) < 0.2,
		"kneeling: the back foot up on its tucked toes (%.2f), the front flat (%.2f)" % [kneel.pitch[1], kneel.pitch[0]])
	var prone := _posed_feet(SoldierMovement.Stance.PRONE)
	check(prone.toes[0] and prone.toes[1], "prone: the toes tucked into the ground")


## A model posed in `stance` for a second: {"pitch": [left, right] foot pitch, "toes": [left, right]}.
func _posed_feet(stance: int) -> Dictionary:
	var holder := Node3D.new()
	holder.position = Vector3(420, 0, 400)
	add_child(holder)
	var model := CharacterModel.new()
	model.lod = false
	holder.add_child(model)
	model.set_process(false)
	model.pose = SoldierMovement.pose_for(stance, 0, 0.0)
	for i in 90:
		model._process(1.0 / 60.0)
	var out := {"pitch": [model.foot_pitch(true), model.foot_pitch(false)], "toes": [model.foot_toes(true), model.foot_toes(false)]}
	holder.queue_free()
	return out


## How far (m) a model's voxels reach along `axis` (0 x, 1 y, 2 z).
func _solid_extent(occ: Dictionary, axis: int) -> float:
	var dims: Vector3i = occ.dims
	var lo := 1 << 30
	var hi := -1
	for z in dims.z:
		for y in dims.y:
			for x in dims.x:
				if occ.solid[x + dims.x * (y + dims.y * z)] == 1:
					var c: int = [x, y, z][axis]
					lo = mini(lo, c)
					hi = maxi(hi, c)
	return (hi - lo + 1) * float(occ.cell) if hi >= lo else 0.0


## How deep (m) model `m`'s sole (VoxelArt.C.SOLE voxels) is at `z_m` metres forward (-) or back (+)
## of the ankle, under the middle of the foot.
func _sole_depth(m: String, z_m: float) -> float:
	var spec := VoxelArt._spec(m)
	var cell: float = float(spec.voxel) / int(spec.sub)
	var buffer := VoxelArt.raster_copy(m, "multicam")
	var dims: Vector3i = spec.size * int(spec.sub)
	var z := int((Vector3(spec.pivot).z * float(spec.voxel) + z_m) / cell)
	var n := 0
	for y in dims.y:
		if buffer.get_voxel(dims.x / 2 + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR) == VoxelArt.C.SOLE:
			n += 1
	return n * cell


## How many toes cross a foot model just above its sole, 3.8 cm back from the big toe (where all five reach).
func _toe_count(occ: Dictionary) -> int:
	var dims: Vector3i = occ.dims
	var cell: float = occ.cell
	var front := dims.z
	for z in dims.z:
		for y in dims.y:
			for x in dims.x:
				if occ.solid[x + dims.x * (y + dims.y * z)] == 1:
					front = mini(front, z)
	var z := front + int(0.038 / cell)
	var best := 0
	for y in range(1, int(0.02 / cell)):
		var runs := 0
		var inside := false
		for x in dims.x:
			var solid: bool = occ.solid[x + dims.x * (y + dims.y * z)] == 1
			if solid and not inside:
				runs += 1
			inside = solid
		best = maxi(best, runs)
	return best


## How many fingers cross a slice through hand model `m` 3 cm below its knuckles (the voxels'
## solid runs across the hand, along z, in the hand's plane).
func _finger_count(m: String) -> int:
	var occ := VoxelArt.occupancy(m)
	var dims: Vector3i = occ.dims
	var cell: float = occ.cell
	var female := m.begins_with("forearm_f")
	var hand_y := HandPose.WRIST.y - (13.5 * (HandPose.FEMALE_SIZE if female else 1.0))  # cm, the frame's own
	var y := int(hand_y * VoxelArt.BODY_VOXEL / cell)
	var best := 0
	for x in range(int(dims.x * 0.35), int(dims.x * 0.65)):
		var runs := 0
		var inside := false
		for z in dims.z:
			var solid: bool = occ.solid[x + dims.x * (y + dims.y * z)] == 1
			if solid and not inside:
				runs += 1
			inside = solid
		best = maxi(best, runs)
	return best


## The hand's width across the knuckles (metres) in model `m`.
func _hand_width(m: String) -> float:
	var occ := VoxelArt.occupancy(m)
	var dims: Vector3i = occ.dims
	var cell: float = occ.cell
	var female := m.begins_with("forearm_f")
	var y := int((HandPose.WRIST.y - 10.0 * (HandPose.FEMALE_SIZE if female else 1.0)) * VoxelArt.BODY_VOXEL / cell)
	var lo := dims.z
	var hi := -1
	for x in dims.x:
		for z in dims.z:
			if occ.solid[x + dims.x * (y + dims.y * z)] == 1:
				lo = mini(lo, z)
				hi = maxi(hi, z)
	return (hi - lo + 1) * cell if hi >= lo else 0.0


func _test_treat() -> void:
	print("Treating")
	_down(alpha)
	alpha.vitals.server_hit(Vitals.FOREARM_L, {"round_class": Vitals.FRAGMENT, "superficial": true})
	_place(alpha, SPOT + Vector3(0, 0, -1.5))
	await _settled(alpha)  # he falls as a ragdoll: treat him where he comes to rest
	_place_player()
	await _seconds(0.3)
	var task := _task_with(alpha, &"pressure_bandage")
	if not task.is_empty():
		_beside(_drawn(alpha, task.part))  # kneel within reach of the wound (the arm as it lies)
	await _seconds(0.5)
	check(not task.is_empty() and not alpha.vitals.is_dead(), "Alpha is down with a wound to bandage (%s)" % [alpha.vitals.care_needed()])
	if task.is_empty():
		return
	var rest_y := player.model.torso.global_position.y
	player._server_treat.rpc_id(1, alpha.get_path(), &"pressure_bandage", task.part)
	check(player.model.action_net.get("id") == CharacterModel.TREAT and player.model.action_net.get("kneel") == true, "treating another: kneeling (replicated)")
	await _seconds(0.8)
	var wound := _drawn(alpha, task.part)  # (an arm's hitbox rides the torso; the hands go to the arm drawn)
	var at: Vector3 = player.to_global(player.model.action_net.get("at", Vector3.ZERO))
	var hands := (player.model.hand_position(true) + player.model.hand_position(false)) * 0.5
	check(player.model.action_shown() == CharacterModel.TREAT and rest_y - player.model.torso.global_position.y > 0.25,
		"kneeling beside the casualty (hips %.2f m lower)" % (rest_y - player.model.torso.global_position.y))
	# (The live site, not action_net's "at": that's body-space at the start, and the first-person
	# view turns the body to the work.)
	var site: Dictionary = player.model.treat_site()
	var on: Vector3 = site.get("p", at)
	check(hands.distance_to(on) < 0.08 and on.distance_to(wound) < 0.35, "hands working at the wound (%.1f cm from the site, %.1f cm from the wound)"
		% [hands.distance_to(on) * 100.0, on.distance_to(wound) * 100.0])
	check(player.model.hand_error() < 0.0, "the rifle slung meanwhile")
	var done := await _wait(func() -> bool: return player.model.action_net.is_empty(), 8.0)
	check(done and not player.model.hands_busy(), "the clip ends with the treatment")
	# Yourself, standing: no kneel, hands at your own wound.
	player.vitals.server_hit(Vitals.FOREARM_L, {"round_class": Vitals.FRAGMENT, "superficial": true})
	await _seconds(0.3)
	player._server_use_medical.rpc_id(1)
	check(player.model.action_net.get("id") == CharacterModel.TREAT and player.model.action_net.get("kneel") == false, "treating yourself (no kneel)")
	await _seconds(0.8)
	# Your own arm: held out in front, the right hand wrapping round it (_test_self_treat_poses).
	var own: Dictionary = player.model.treat_site()
	var hand := player.model.hand_position(true)
	check(not own.is_empty() and hand.distance_to(own.p) < float(own.r) + 0.1, "the hand at your own wound (%.1f cm)" % (hand.distance_to(own.get("p", hand)) * 100.0))
	player.global_position += Vector3(0, 0, 2.0)  # moving interrupts it
	var stopped := await _wait(func() -> bool: return player.model.action_net.is_empty(), 1.0)
	check(stopped, "an interrupted treatment stops the clip")
	_place_player()
	player.vitals.server_reset_health()
	alpha.vitals.server_reset_health()


## Each treatment's own technique (CharacterModel.TECHNIQUES, _treat_goals): wrapping,
## tourniquets high and tight with windlass turns, needles, injectors, CPR and the rest.
func _test_techniques() -> void:
	print("Treatment techniques")
	var missing := []
	for id: StringName in [&"pressure_bandage", &"hemostatic_gauze", &"tourniquet", &"splint", &"chest_seal", &"decompression_needle",
			&"morphine", &"epinephrine", &"atropine", &"adenosine", &"iv_18", &"iv_10", &"io_kit", &"cpr", &"defibrillator",
			&"surgical_clamp", &"saline_500", &"blood_1000", &"pressure_bag", &"burn_dressing", &"hypothermia_blanket", &"npa"]:
		if not CharacterModel.TECHNIQUES.has(id):
			missing.append(id)
	check(missing.is_empty(), "every treatment has its technique (missing %s)" % [missing])
	var m := player.model
	var at := Vector3(0.0, 0.2, -0.5)
	var radii := []
	var angles := []
	for i in 6:
		var hand: Vector3 = m._treat_goals(&"wrap", at, i * 0.15, 6.0)[0][1]
		radii.append(snappedf(hand.distance_to(at), 0.001))
		angles.append(hand)
	check(radii.all(func(r: float) -> bool: return absf(r - CharacterModel.WRAP_RADIUS) < 0.002) and angles[0].distance_to(angles[2]) > 0.03,
		"a bandage: the right hand wraps round the limb (%s)" % [radii])
	var depths := []
	for i in 12:
		var t := i / (CharacterModel.CPR_HZ * 12.0)
		var hand: Vector3 = m._treat_goals(&"cpr", at, t, 10.0)[0][1]
		depths.append(hand.distance_to(CharacterModel.HANDS_ANCHOR))
	check(absf((depths.max() - depths.min()) - CharacterModel.COMPRESSION_M) < 0.01, "CPR: compressions %.1f cm deep at %.0f a minute"
		% [(depths.max() - depths.min()) * 100.0, CharacterModel.CPR_HZ * 60.0])
	var jab: Vector3 = m._treat_goals(&"inject", at, 1.0, 2.0)[0][1]
	var ready: Vector3 = m._treat_goals(&"inject", at, 0.2, 2.0)[0][1]
	check(jab.distance_to(at) < 0.001 and ready.distance_to(at) > 0.15, "an injector: wound up, then jabbed home")
	var strap: Vector3 = m._treat_goals(&"tourniquet", at, 0.5, 6.0)[0][1]
	var turn_a: Vector3 = m._treat_goals(&"tourniquet", at, 3.0, 6.0)[0][1]
	var turn_b: Vector3 = m._treat_goals(&"tourniquet", at, 3.0 + 0.25 / CharacterModel.WINDLASS_HZ, 6.0)[0][1]
	var clip: Vector3 = m._treat_goals(&"tourniquet", at, 6.0 - CharacterModel.CLIP_S * 0.4, 6.0)[0][1]
	check(strap.distance_to(at) > 0.05 and turn_a.distance_to(turn_b) > 0.03 and clip.distance_to(turn_a) > 0.01,
		"a tourniquet: strap round, windlass turns, into the clip")
	var needle_in: Vector3 = m._treat_goals(&"needle", at, 4.0, 5.0)[0][1]
	var needle_start: Vector3 = m._treat_goals(&"needle", at, 0.0, 5.0)[0][1]
	check(needle_start.distance_to(at) > 0.1 and needle_in.distance_to(at) < 0.02, "a needle: slowly in")
	var bag: Vector3 = m._treat_goals(&"fluids", at, 1.0, 3.0)[0][1]
	check(bag.y > at.y + 0.3, "a bag held up high")
	var pads: Vector3 = m._treat_goals(&"defib", at, 1.0, 5.0)[0][1]
	var clear: Vector3 = m._treat_goals(&"defib", at, 4.0, 5.0)[0][1]
	check(pads.distance_to(at) < 0.2 and clear.distance_to(at) > 0.2, "defib: pads on, then hands clear for the shock")
	# In the scene: a tourniquet on Alpha's thigh goes on high, above the wound, and says which technique.
	_down(alpha)
	_place(alpha, SPOT + Vector3(0, 0, -1.5))
	_place_player()
	await _seconds(0.3)
	_beside(CharacterModel.part_position(alpha, &"thigh_l"))
	await _seconds(0.3)
	player.model.server_treat(alpha, &"thigh_l", 2.0, &"tourniquet")
	var high: Vector3 = player.to_global(player.model.action_net.get("at", Vector3.ZERO))
	var wound := CharacterModel.part_position(alpha, &"thigh_l")
	var chest := CharacterModel.part_position(alpha, &"chest")
	check(player.model.action_net.get("tech") == &"tourniquet" and high.distance_to(chest) < wound.distance_to(chest) - 0.05,
		"high and tight: %.0f cm nearer the trunk than the wound" % ((wound.distance_to(chest) - high.distance_to(chest)) * 100.0))
	await _seconds(0.5)
	check(player.model.action_shown() == CharacterModel.TREAT, "and it plays")
	player.model.action_net = {}
	# On yourself: an injector into your own thigh, standing.
	player.model.server_treat(player, &"thigh_l", 2.0, &"morphine")
	check(player.model.action_net.get("tech") == &"inject" and player.model.action_net.get("kneel") == false, "an injector on yourself: standing, own thigh")
	player.model.action_net = {}
	alpha.vitals.server_reset_health()


## Each technique's kit in the hands (TreatProps, CharacterModel.held_anchor) through its phases,
## and what goes onto the casualty (a tourniquet's band, a pad, a seal, the AED beside him), all
## gone once the clip ends; the hands on the casualty's own skin at the wound (treat_site).
func _test_treat_props() -> void:
	print("Treatment props")
	_down(alpha)
	alpha.vitals.server_hit(Vitals.THIGH_L, {"round_class": Vitals.FRAGMENT, "superficial": true})
	_place(alpha, SPOT + Vector3(0, 0, -1.5))
	await _settled(alpha)
	_place_player()
	await _seconds(0.3)
	_beside(CharacterModel.part_position(alpha, &"thigh_l"))
	await _seconds(0.3)
	var m := player.model
	# item: [part, [[share of the clip, a prop that shows then], ...]]; "r:"/"l:" in that hand.
	var expect := {
		&"tourniquet": [&"thigh_l", [[0.15, "r:strap"], [0.15, "band"], [0.6, "rod"], [0.6, "band"]]],
		&"pressure_bandage": [&"thigh_l", [[0.3, "r:roll"], [0.3, "pad"], [0.6, "tail"], [0.6, "turns"]]],
		&"hemostatic_gauze": [&"thigh_l", [[0.3, "r:gauze"], [0.3, "tail"], [0.85, "wad"]]],
		&"splint": [&"thigh_l", [[0.15, "splint"], [0.7, "r:wrap"], [0.7, "splint"]]],
		&"chest_seal": [&"chest", [[0.15, "l:seal"], [0.15, "r:backing"], [0.6, "seal"]]],
		&"decompression_needle": [&"chest", [[0.4, "r:needle"], [0.92, "hub"]]],
		&"morphine": [&"thigh_l", [[0.04, "r:injector"], [0.2, "l:cap"], [0.6, "r:injector"]]],
		&"adenosine": [&"thigh_l", [[0.5, "r:syringe"]]],
		&"iv_18": [&"forearm_l", [[0.4, "r:catheter"], [0.85, "tape"]]],
		&"io_kit": [&"chest", [[0.5, "r:driver"]]],
		&"saline_500": [&"forearm_l", [[0.5, "r:bag"], [0.5, "line"]]],
		&"defibrillator": [&"chest", [[0.2, "r:pad"], [0.2, "l:pad"], [0.2, "aed"], [0.6, "pad_0"], [0.6, "cable_1"]]],
		&"surgical_clamp": [&"abdomen", [[0.5, "r:hemostat"], [0.5, "l:forceps"], [0.5, "kit"]]],
		&"hypothermia_blanket": [&"chest", [[0.5, "sheet"]]],
		&"npa": [&"head", [[0.5, "r:npa"]]],
		&"pelvic_binder": [&"pelvis", [[0.5, "r:handle"], [0.5, "l:handle"]]],
	}
	var missing: Array[String] = []
	var left_over: Array[String] = []
	for item: StringName in expect:
		var part: StringName = expect[item][0]
		var serial := m.server_treat(alpha, part, 2.0, item)
		for want: Array in expect[item][1]:
			await _wait(func() -> bool: return m.action_progress() >= float(want[0]) or m.action_net.is_empty(), 3.0)
			await _frames(2)
			var shown: Dictionary = m._props.shown() if is_instance_valid(m._props) else {}
			var slot: String = want[1]
			if not shown.has(slot):
				missing.append("%s %s at %.0f%% (%s)" % [item, slot, float(want[0]) * 100.0, shown.keys()])
			elif slot.begins_with("r:") and m.held_prop(true) == null or slot.begins_with("l:") and m.held_prop(false) == null:
				missing.append("%s %s: not in the hand (held_prop)" % [item, slot])
		m.server_stop(serial)
		await _frames(3)
		if is_instance_valid(m._props) and not m._props.shown().is_empty():
			left_over.append("%s %s" % [item, m._props.shown().keys()])
	check(missing.is_empty(), "each technique's kit shows through its phases (%d techniques; missing %s)" % [expect.size(), missing])
	check(left_over.is_empty() and m.held_prop(true) == null and m.held_prop(false) == null, "and it's gone when the clip ends (left over %s)" % [left_over])
	# On the skin at the wound, not the part's middle, and the hands there.
	m.server_treat(alpha, &"thigh_l", 3.0, &"pressure_bandage")
	await _seconds(0.9)
	var site := m.treat_site()
	var centre := CharacterModel.part_position(alpha, &"thigh_l")
	var hand := m.hand_position(false)  # the left holds the pad on it
	check(not site.is_empty() and Vector3(site.p).distance_to(centre) > 0.03 and Vector3(site.p).distance_to(centre) < 0.2,
		"the site is on the thigh's skin (%.1f cm from its middle)" % (Vector3(site.get("p", centre)).distance_to(centre) * 100.0))
	check(not site.is_empty() and hand.distance_to(site.p) < 0.1, "the hand on it (%.1f cm)" % (hand.distance_to(site.get("p", hand)) * 100.0))
	var anchor := m.held_anchor(true)
	var own_anchor := not m.has_method(&"hand_anchor")  # (with the fingers: their grasp centre)
	check(anchor.get_parent() == m._forearm[0] and (not own_anchor or anchor.position.is_equal_approx(CharacterModel.HELD_AT)) and m.held_prop(true) != null \
		and m.held_prop(true).has_meta(&"grip"), "a held-prop anchor at the right palm, the roll in it (with its grip for the fingers)")
	m.action_net = {}
	await _frames(3)
	alpha.vitals.server_reset_health()


## First person while treating: the weapon gone from the view, your own forearms and the kit on
## the camera's layer, the eye down with the kneel; all back after.
func _test_medic_view() -> void:
	print("First-person medic view")
	_down(alpha)
	_place(alpha, SPOT + Vector3(0, 0, -1.5))
	await _settled(alpha)
	_place_player()
	await _seconds(0.3)
	_beside(CharacterModel.part_position(alpha, &"thigh_r"))
	await _seconds(0.5)
	var m := player.model
	var input := player.get_node(^"PlayerInput") as PlayerInput
	var forearm := m._forearm[0].get_child(0) as MeshInstance3D
	check(player.view_model.visible and forearm.layers & CharacterModel.VIEW_HANDS_LAYER == 0, "before: the weapon in view, your own arms not")
	m.server_treat(alpha, &"thigh_r", 3.0, &"tourniquet")
	await _seconds(0.6)  # (the strap, in the hand)
	var prop := m.held_prop(true)
	var prop_mesh: MeshInstance3D = prop.get_child(0) as MeshInstance3D if prop else null
	check(not player.view_model.visible, "treating: the weapon view model hidden")
	check(m.view_hands_shown() and forearm.layers & CharacterModel.VIEW_HANDS_LAYER != 0 and player.camera.cull_mask & CharacterModel.VIEW_HANDS_LAYER != 0,
		"your own forearms on the camera")
	check(prop_mesh != null and prop_mesh.layers & CharacterModel.VIEW_HANDS_LAYER != 0, "and the kit in your hand")
	var to_hands := (m.hand_position(true) + m.hand_position(false)) * 0.5 - player.camera.global_position
	var in_view := (-player.camera.global_basis.z).angle_to(to_hands)
	check(in_view < deg_to_rad(40.0), "your hands in the view (%.0f degrees off its middle)" % rad_to_deg(in_view))
	check(m.treat_view_offset().y < -0.2 and input._medic_eye.length() > 0.2, "the eye down with the kneel (%.2f m)" % m.treat_view_offset().y)
	m.action_net = {}
	await _seconds(0.6)
	check(player.view_model.visible and forearm.layers & CharacterModel.VIEW_HANDS_LAYER == 0 and m.treat_view_offset().length() < 0.02,
		"after: the weapon back, your arms off the camera, the eye back up")
	_place_player()


## Treating yourself: a tourniquet one-handed on your own arm (the hurt arm held out, the upper
## body turned to it), on your own leg down on a knee, an injector into your outer thigh standing.
func _test_self_treat_poses() -> void:
	print("Self-treatment poses")
	_place_player()
	await _seconds(0.5)
	var m := player.model
	var rest_y := m.torso.global_position.y
	m.server_treat(player, &"upper_arm_l", 3.0, &"tourniquet")
	await _seconds(0.9)
	var site := m.treat_site()
	var present := m.torso.to_local(m.hand_position(false))
	var want := CharacterModel.PRESENT * Vector3(-1, 1, 1)
	check(not site.is_empty() and m.hand_position(true).distance_to(site.p) < 0.12, "your own arm: the right hand at the tourniquet on the left arm (%.1f cm)"
		% (m.hand_position(true).distance_to(site.get("p", Vector3.ZERO)) * 100.0))
	check(present.distance_to(want) < 0.08 and m.twist_shown() > 0.15, "the left arm held out (%.1f cm off), the upper body turned to it (%.2f)"
		% [present.distance_to(want) * 100.0, m.twist_shown()])
	check(m.held_prop(true) != null and m.held_prop(false) == null, "one-handed: the strap in the right hand only")
	m.action_net = {}
	await _seconds(0.6)
	m.server_treat(player, &"thigh_l", 3.0, &"tourniquet")
	await _seconds(0.9)
	var drop := rest_y - m.torso.global_position.y
	site = m.treat_site()
	check(drop > 0.25 and not site.is_empty() and (m.hand_position(true) + m.hand_position(false)).distance_to(Vector3(site.p) * 2.0) < 0.3,
		"your own leg: down on a knee over it (hips %.2f m lower), hands at it" % drop)
	m.action_net = {}
	await _seconds(0.6)
	m.server_treat(player, &"thigh_l", 2.0, &"morphine")
	await _wait(func() -> bool: return m.action_progress() > 0.5, 2.0)
	await _frames(3)
	site = m.treat_site()
	drop = rest_y - m.torso.global_position.y
	check(drop < 0.12 and StringName(site.get("part", &"")) == Vitals.THIGH_R and m.hand_position(true).distance_to(site.p) < 0.14 and m.held_prop(true) != null,
		"an injector: standing (%.2f m), into the outer right thigh (%.1f cm)" % [drop, m.hand_position(true).distance_to(site.get("p", Vector3.ZERO)) * 100.0])
	m.action_net = {}
	await _seconds(0.5)


## The casualty reacts: a wince as a tourniquet tightens (awake), relaxing after morphine, a gasp on
## decompression, the chest going down under CPR, a spasm on the shock.
func _test_patient_reactions() -> void:
	print("Patient reactions")
	var m := player.model
	# Bravo, awake, takes a tourniquet and morphine.
	bravo.vitals.server_reset_health()
	_place(bravo, SPOT + Vector3(0, 0, -1.2))
	_place_player()
	await _seconds(0.4)
	m.server_treat(bravo, &"thigh_r", 3.0, &"tourniquet")
	var winced := 0.0
	var end := Time.get_ticks_msec() + 3200
	while Time.get_ticks_msec() < end and not m.action_net.is_empty():
		if m.action_progress() > CharacterModel.STRAP_END:
			winced = maxf(winced, float(bravo.model.reaction_shown().get(&"wince", 0.0)))
		await get_tree().process_frame
	check(winced > 0.3, "a wince as the windlass turns (%.2f)" % winced)
	m.server_treat(bravo, &"thigh_r", 2.0, &"morphine")
	await _wait(func() -> bool: return m.action_net.is_empty() or m.action_progress() > 0.95, 3.0)
	await _seconds(0.6)
	check(float(bravo.model.reaction_shown().get(&"relax", 0.0)) > 0.1, "relaxing after the morphine (%.2f)" % float(bravo.model.reaction_shown().get(&"relax", 0.0)))
	m.action_net = {}
	# Alpha, down: a needle, CPR and the defib.
	_down(alpha)
	_place(alpha, SPOT + Vector3(0, 0, -1.5))
	await _settled(alpha)
	_beside(CharacterModel.part_position(alpha, &"chest"))
	await _seconds(0.3)
	m.server_treat(alpha, &"chest", 2.0, &"decompression_needle")
	var gasp := 0.0
	end = Time.get_ticks_msec() + 2400
	while Time.get_ticks_msec() < end and not m.action_net.is_empty():
		gasp = maxf(gasp, float(alpha.model.reaction_shown().get(&"gasp", 0.0)))
		await get_tree().process_frame
	check(gasp > 0.3, "a gasp as the needle goes in (%.2f)" % gasp)
	m.server_treat(alpha, &"chest", 2.0, &"cpr")
	await _seconds(0.4)
	var lo := INF
	var hi := -INF
	var hands := 0.0
	end = Time.get_ticks_msec() + 1200
	while Time.get_ticks_msec() < end:
		var site := m.treat_site()
		if not site.is_empty():
			var along: float = alpha.model.torso.global_position.dot(site.n)
			lo = minf(lo, along)
			hi = maxf(hi, along)
			hands = maxf(hands, m.hand_position(true).distance_to(site.p))
		await get_tree().process_frame
	check(hi - lo > 0.025 and hi - lo < CharacterModel.COMPRESSION_M + 0.02, "the chest goes down under CPR (%.1f cm)" % ((hi - lo) * 100.0))
	m.action_net = {}
	await _frames(3)
	m.server_treat(alpha, &"chest", 2.0, &"defibrillator")
	var spasm := 0.0
	var early := false
	end = Time.get_ticks_msec() + 2400
	while Time.get_ticks_msec() < end and not m.action_net.is_empty():
		if m.action_progress() < CharacterModel.DEFIB_SHOCK - 0.05:
			early = early or alpha.model.reaction_shown().has(&"spasm")
		spasm = maxf(spasm, float(alpha.model.reaction_shown().get(&"spasm", 0.0)))
		await get_tree().process_frame
	check(spasm > 0.3 and not early, "a spasm on the shock, not before (%.2f)" % spasm)
	m.action_net = {}
	await _frames(3)
	alpha.vitals.server_reset_health()
	bravo.vitals.server_reset_health()
	_place(bravo, SPOT + Vector3(3.0, 0, 0))


## Treatment times as they were (items.json treat_s, the clip as long as the treatment), props
## or not.
func _test_treat_timings() -> void:
	print("Treatment timings")
	var was := {&"tourniquet": 4.0, &"pressure_bandage": 5.0, &"hemostatic_gauze": 8.0, &"chest_seal": 5.0, &"splint": 8.0,
		&"pelvic_binder": 10.0, &"morphine": 2.0, &"npa": 3.0, &"iv_18": 10.0, &"io_kit": 5.0, &"saline_500": 3.0,
		&"decompression_needle": 5.0, &"defibrillator": 5.0, &"cpr": 10.0, &"surgical_clamp": 20.0, &"hypothermia_blanket": 5.0}
	var changed: Array[String] = []
	for id: StringName in was:
		var item := ItemDB.get_item(id)
		if not is_equal_approx(float(item.stats.get("treat_s", -1.0)), was[id]):
			changed.append("%s %s" % [id, item.stats.get("treat_s")])
	check(changed.is_empty(), "treat_s unchanged (%s)" % [changed])
	_down(alpha)
	alpha.vitals.server_hit(Vitals.FOREARM_L, {"round_class": Vitals.FRAGMENT, "superficial": true})
	_place(alpha, SPOT + Vector3(0, 0, -1.5))
	await _settled(alpha)
	var task := _task_with(alpha, &"pressure_bandage")
	if task.is_empty():
		check(false, "a wound to bandage for the timing")
		return
	_beside(CharacterModel.part_position(alpha, task.part))
	await _seconds(0.3)
	var expected := player.treat_seconds(alpha, ItemDB.get_item(&"pressure_bandage"))
	var started := Time.get_ticks_msec()
	player._server_treat.rpc_id(1, alpha.get_path(), &"pressure_bandage", task.part)
	var clip := float(player.model.action_net.get("s", -1.0))
	await _wait(func() -> bool: return player.model.action_net.is_empty(), expected + 3.0)
	var took := (Time.get_ticks_msec() - started) / 1000.0
	check(is_equal_approx(clip, expected) and absf(took - expected) < 0.5, "a bandage takes %.1f s as before (clip %.1f s, took %.1f s)" % [expected, clip, took])
	alpha.vitals.server_reset_health()
	_place_player()


func _test_loot() -> void:
	print("Looting")
	hostile.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.INTERMEDIATE})
	await _frames(3)
	check(hostile.vitals.is_dead(), "a dead body with gear")
	_place(hostile, SPOT + Vector3(-1.0, 0, -0.8))
	await _settled(hostile)
	# Placed before its ragdoll's first physics step: the parts still go with it (they stayed
	# behind once, and the body later stood up metres from where it was put).
	var placed_at: Vector3 = (hostile.ragdoll.parts["torso"] as Node3D).global_position if is_instance_valid(hostile.ragdoll) else Vector3.INF
	check(_flat(placed_at, hostile.global_position) < 1.5, "the body put somewhere takes its ragdoll along (%.1f m)" % _flat(placed_at, hostile.global_position))
	# A ragdoll can slide or roll metres from the capsule, which stays where it fell (this
	# flaked when it did by chance): put it 6 m off, and loot it where it lies.
	check(is_instance_valid(hostile.ragdoll) and hostile.ragdoll.frozen, "it lies as a ragdoll, at rest")
	for part: Node3D in hostile.ragdoll.parts.values():
		part.global_position += SLID
	hostile.ragdoll._send(true)
	await _frames(3)
	check(_flat(hostile.aim_point(), hostile.global_position) > 4.5, "it lies %.1f m from where it fell" % _flat(hostile.aim_point(), hostile.global_position))
	_place_player()
	await _seconds(0.3)
	_beside(hostile.aim_point())
	await _seconds(0.5)
	var rest_y := player.model.torso.global_position.y
	var index := _entry_of(hostile, &"mag_556")
	player._server_loot_item.rpc_id(1, hostile.get_path(), index.get("container", &"vest"), int(index.get("index", 0)), &"mag_556")
	if player.model.action_net.is_empty():
		print("  (refused: '%s')" % player.player_input.hud._message.text)
	check(player.model.action_net.get("id") == CharacterModel.LOOT and player.model.action_net.get("kneel") == true, "looting: kneeling at the body")
	var at: Vector3 = player.to_global(player.model.action_net.get("at", Vector3.ZERO))
	var seen := {"best": INF, "low": rest_y}
	await _watch(CharacterModel.LOOT_S * CharacterModel.LOOT_WORK_END, func() -> void:
		seen.best = minf(seen.best, ((player.model.hand_position(true) + player.model.hand_position(false)) * 0.5).distance_to(at))
		seen.low = minf(seen.low, player.model.torso.global_position.y))
	check(seen.best < 0.08 and rest_y - seen.low > 0.25, "hands at the body (%.1f cm), knelt down (%.2f m)" % [seen.best * 100.0, rest_y - seen.low])
	check(at.distance_to(hostile.aim_point()) < 0.3, "at the body's chest (%.1f cm)" % (at.distance_to(hostile.aim_point()) * 100.0))
	await _seconds(1.0)
	check(player.model.action_net.is_empty(), "the clip ends")
	player._server_loot_body.rpc_id(1, hostile.get_path())
	check(player.model.action_net.get("id") == CharacterModel.LOOT and is_equal_approx(float(player.model.action_net.get("s")), CharacterModel.LOOT_ALL_S),
		"Loot all: a longer clip")
	await _seconds(2.0)


## A weapon looted off a body leaves it (Captain, P0164 queue 15: a rifle stayed drawn on the
## chest of a body it had been looted off). An AI is killed while aiming its rifle or its pistol,
## or with its launcher on the shoulder; the rifle is taken by a player (Loot) or by a squadmate
## whose own rifle is dry (Scavenge, as SquadAI does: a swap, his empty one laid on the ground),
## the pistol and the launcher by a player. Nothing of either rifle, the pistol or the launcher
## is drawn on the body or its ragdoll after, and its hands hold nothing.
func _test_looted_weapons() -> void:
	print("Looted weapons leave the body")
	var mine := player.inventory.net_state.duplicate(true)
	var cases := [[&"primary", &"m4a1", "player"], [&"primary", &"m4a1", "scavenger"], [&"sidearm", &"m17", "player"],
		[&"launcher", &"at4", "player"]]
	for i in cases.size():
		var slot: StringName = cases[i][0]
		var id: StringName = cases[i][1]
		var by: String = cases[i][2]
		var dead := _spawn_ai("Kilo%d" % i, &"hostile", SPOT + Vector3(-4.0 + i * 2.5, 0, 6.0), ["plate_carrier", "m4a1", "m17", "at4", "mag_556"])
		await _frames(3)
		dead.select_weapon(slot)
		dead.want_aim = true
		var ready := await _wait(func() -> bool:
			if slot == &"launcher":
				var rig := dead.get_node_or_null(^"LauncherRig") as LauncherRig
				return rig != null and rig._held
			return dead.is_aiming and dead.gear._held_key == slot and not dead.gear.drawing(), 3.0)
		check(ready, "%s: an AI aims its %s (%s)" % [id, slot, "on the shoulder" if slot == &"launcher" else dead.gear._held_key])
		dead.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.INTERMEDIATE})
		await _frames(3)
		await _settled(dead)
		check(dead.vitals.is_dead() and not _weapon_drawn(dead, id).is_empty(), "killed mid-aim, its %s is still drawn on the body" % id)
		var looter: Soldier = player
		if by == "scavenger":
			looter = _spawn_ai("Lima%d" % i, &"friendly", dead.body_point() + Vector3(0.6, 0.0, 0.0), ["plate_carrier", "m110"])
			await _frames(3)
			var dry := looter.inventory.state_of(&"primary").duplicate(true)
			dry["rounds"] = 0  # no 7.62 left anywhere: he wants the body's rifle
			looter.inventory.slot_state[&"primary"] = dry
			looter.inventory._commit()
			var pick := Scavenge.best_pick(looter, dead, false)
			check(pick.get("kind") == "weapon" and Scavenge.apply(looter, dead, pick) == 1, "a squadmate with his M110 dry swaps it for the body's (%s)" % [pick])
		else:
			player.inventory.unequip(slot)  # room for it in the player's own slot
			_beside(dead.body_point())
			await _seconds(0.3)
			player._server_loot_item.rpc_id(1, dead.get_path(), slot, -1, id)
		check(dead.inventory.slots[slot] == &"" and looter.inventory.slots[slot] == id, "the %s goes from the body to the %s" % [id, by])
		await _frames(3)
		var left := _weapon_drawn(dead, id) + _weapon_drawn(dead, &"m110")
		check(left.is_empty(), "and no weapon is drawn on the body or its ragdoll (%s)" % [left])
		check(not is_instance_valid(dead.model._held), "its hands hold nothing")
		player.inventory.net_state = mine.duplicate(true)
		if looter != player:
			looter.queue_free()
		dead.inventory.strip()  # nothing left to drop round the test area
		dead.server_remove_body()
	_place_player()
	await _frames(3)


## A downed body whose ragdoll slid or rolled off stands up where it lay, not back where it fell
## (Soldier._stand_where_ragdoll_lay, Ragdoll.rest_spot), and a following peer's ragdoll finds
## the same spot.
func _test_stand_where_it_lay() -> void:
	print("Standing up where the ragdoll lay")
	_place(bravo, SPOT + Vector3(3.0, 0, 0))
	await _frames(2)
	_down(bravo)
	await _settled(bravo)
	check(not bravo.vitals.is_up() and not bravo.vitals.is_dead() and is_instance_valid(bravo.ragdoll) and bravo.ragdoll.frozen,
		"a downed body lies as a ragdoll, at rest")
	var fell := bravo.global_position
	for part: Node3D in bravo.ragdoll.parts.values():
		part.global_position += ROLLED
	bravo.ragdoll._send(true)
	await _frames(3)
	var lay: Vector3 = (bravo.ragdoll.parts["torso"] as Node3D).global_position
	check(_flat(lay, fell) > 2.5, "its hips lie %.1f m from where it fell" % _flat(lay, fell))
	var host_spot: Variant = bravo.ragdoll.rest_spot()
	var follower := Ragdoll.follow(bravo)  # what another peer builds from the replicated pose
	var peer_spot: Variant = follower.rest_spot()
	follower.free()
	check(host_spot != null and peer_spot != null and (host_spot as Transform3D).origin.distance_to((peer_spot as Transform3D).origin) < 0.05,
		"a following peer's ragdoll stands it up at the same spot")
	bravo.vitals.server_reset_health()
	await _frames(3)
	check(bravo.vitals.is_up() and not is_instance_valid(bravo.ragdoll), "revived: the ragdoll goes")
	check(_flat(bravo.global_position, lay) < 0.5, "and it stands up where it lay (%.2f m from its hips, %.1f m from where it fell)"
		% [_flat(bravo.global_position, lay), _flat(bravo.global_position, fell)])
	await _seconds(0.5)
	check(_flat(bravo.global_position, lay) < 0.5 and absf(bravo.global_position.y - fell.y) < 0.3 and bravo.rotation.is_finite(),
		"on the ground, and stays there (%.2f m, %.2f m up)" % [_flat(bravo.global_position, lay), bravo.global_position.y - fell.y])
	_place(bravo, SPOT + Vector3(3.0, 0, 0))


## A player who dies while lying as a ragdoll respawns at a spawn point, not where the ragdoll lay
## (Captain, 2026-10-12: the revive's stand-up overrode the respawn; Soldier._respawned_until).
func _test_respawn_not_where_it_lay() -> void:
	print("Respawning, not standing up where the ragdoll lay")
	_place(player, SPOT + Vector3(8.0, 0, -6.0))
	await _frames(2)
	_down(player)
	await _settled(player)
	check(not player.vitals.is_up() and is_instance_valid(player.ragdoll), "a downed player lies as a ragdoll")
	for part: Node3D in player.ragdoll.parts.values():
		part.global_position += Vector3(3.0, 0, -3.0)
	player.ragdoll._send(true)
	await _frames(3)
	var lay: Vector3 = (player.ragdoll.parts["torso"] as Node3D).global_position
	player.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.INTERMEDIATE})  # dies: no body is left (Captain, 2026-10-14), the player respawns
	await _frames(5)
	var spawn_gap: float = CompoundLevel.SPAWN_POINTS.map(func(p: Vector3) -> float: return _flat(p, player.global_position)).min()
	check(player.vitals.is_up() and not is_instance_valid(player.ragdoll), "respawned: up, no ragdoll")
	check(spawn_gap < 0.5 and _flat(player.global_position, lay) > 5.0,
		"at a spawn point (%.2f m off), not where the ragdoll lay (%.1f m away)" % [spawn_gap, _flat(player.global_position, lay)])
	await _seconds(2.5)  # past Soldier.RESPAWN_HOLD_S
	check(_flat(player.global_position, lay) > 5.0, "and still there once the hold is over")
	_place_player()


func _test_dummy() -> void:
	print("Dummies")
	var dummy: TargetDummy = level.get_node(^"Dummies/LightDummy")
	check(dummy.model.carry_net.is_empty() and dummy.model.action_shown() == &"" and not dummy.model.hands_busy(), "a dummy has no carry or action")
	dummy.vitals.server_damage(500.0)
	await _frames(3)
	check(dummy.model.downed and dummy.model.transform.is_equal_approx(dummy.model.base_transform()), "and still lies down where it stands")
	dummy.vitals.server_reset_health()


# --- Faces and builds (SoldierLook, FaceArt, FaceRig) ----------------------------------------

## Captain, 2026-10-20: real faces and per-soldier variety. Two soldiers of a side look like two
## people, each the same from his spawn data on every peer; his own head and face parts build
## off the main thread; his eyes shut when he dies, his mouth opens when he calls out; a tall,
## heavy build scales the rig without the hands leaving the weapon or the hitboxes leaving the
## body.
func _test_faces() -> void:
	print("Faces")
	var charlie := _spawn_ai("Charlie", &"friendly", SPOT + Vector3(6.0, 0, 4.0), ["m4a1"])
	var delta := _spawn_ai("Delta", &"friendly", SPOT + Vector3(7.0, 0, 4.0), ["m4a1"])
	check(SoldierLook.valid(charlie.face) and SoldierLook.valid(delta.face) and charlie.model.face == charlie.face,
		"each AI spawns with a look (%s, %s)" % [charlie.face, delta.face])
	check(charlie.face != delta.face and SoldierLook.head_model(charlie.face, charlie.model.body) + SoldierLook.palette(charlie.face)
		!= SoldierLook.head_model(delta.face, delta.model.body) + SoldierLook.palette(delta.face), "two soldiers of a side get different faces")
	var expected := SoldierLook.make(SoldierLook.seed_of(["Charlie", charlie.person_name, charlie.nation]), charlie.nation, charlie.model.body)
	check(charlie.face == expected, "and the face is his identity's: any peer rolls the same from the same spawn")
	var looks := {}
	for i in 40:
		looks[SoldierLook.make(i, "US", VoxelArt.MALE)] = true
	check(looks.size() == 40, "forty American contractors: forty different looks")
	var cn := SoldierLook.parse(SoldierLook.make(7, "CN", VoxelArt.MALE))
	check(String(cn.skin) in SoldierLook.SKINS["eas"], "a soldier of a nation looks like its people (a Chinese soldier's skin: %s)" % cn.skin)
	var built := await _wait(func() -> bool: return charlie.model.face_rig.is_built() and delta.model.face_rig.is_built(), 10.0)
	var mi := charlie.model.head.get_child(0) as MeshInstance3D
	check(built and mi.mesh != null and String(charlie.model.head.get_meta(&"voxel_model")) == SoldierLook.head_model(charlie.face, charlie.model.body),
		"his own head builds off the main thread and goes on")
	var parts_on := true
	for part in FaceRig.PARTS:
		var inst := mi.get_node_or_null(NodePath("Face_" + part)) as MeshInstance3D
		parts_on = parts_on and inst != null and inst.mesh != null
	check(parts_on, "with eyes, a mouth and brows of their own")
	# Expressions.
	charlie.model.shout(1.0)
	await _seconds(0.15)
	check(charlie.model.face_rig.expression == FaceArt.SHOUT, "calling out, the mouth opens (shout)")
	await _seconds(1.0)
	check(charlie.model.face_rig.expression != FaceArt.SHOUT, "and closes after")
	delta.vitals.server_kill()
	await _seconds(0.3)
	var eye := (delta.model.head.get_child(0) as MeshInstance3D).get_node(^"Face_eye_l") as MeshInstance3D
	check(delta.model.face_rig.eye_state == "c" and String(eye.get_meta(&"model", "")).begins_with("eye:c:"),
		"dead, his eyes close")
	check(delta.model.face_rig.expression == FaceArt.SLACK, "and his face goes slack")
	check(delta.body_record().get("face", "") == delta.face, "his body keeps his face (the body record)")
	# Builds: a tall, heavy man scales the rig; the hands stay on the weapon, the hitboxes on him.
	var old := player.model.face  # (a player outside a campaign wears his default face: Soldier.face is "")
	var tall := ":".join((old if SoldierLook.valid(old) else SoldierLook.DEFAULT).split(":").slice(0, 4)) + ":2:1050"
	player.select_weapon(&"primary")
	player.face = tall
	await _seconds(0.8)
	check(is_equal_approx(player.model.body_scale(), 1.05), "a tall soldier is drawn taller (%.3f)" % player.model.body_scale())
	var torso_mi := player.model.torso.get_child(0) as MeshInstance3D
	var base: Array = torso_mi.get_meta(&"base")
	check(is_equal_approx(torso_mi.scale.x / (base[1] as Vector3).x, SoldierLook.BUILD_GIRTH[SoldierLook.HEAVY]) and is_equal_approx(torso_mi.scale.y, (base[1] as Vector3).y),
		"a heavy build is broader through the trunk, not taller")
	var error := player.model.hand_error()
	check(error >= 0.0 and error < 0.02, "the hands stay on the rifle (%.1f cm)" % (error * 100.0))
	# The head's hitbox rides as high as the taller body's head: its shapes' height over the feet
	# is their rest height times his size.
	var off := INF
	for area in CharacterModel._posable_hitboxes(player):
		if area.get_meta(&"body_part") == Vitals.HEAD:
			for shape in area.get_children():
				if shape is CollisionShape3D:
					var rest_y := (CharacterModel._rest_of(area) * (shape as CollisionShape3D).position).y
					off = minf(off, absf((shape as CollisionShape3D).global_position.y - player.global_position.y - rest_y * player.model.body_scale()))
	check(off < 0.03, "the head's hitbox rises with the taller head (%.1f cm off)" % (off * 100.0))
	var chest: Area3D = null
	for area in CharacterModel._posable_hitboxes(player):
		if area.get_meta(&"body_part") == Vitals.CHEST:
			chest = area
	var front := player.model.torso.global_position + Vector3(0, 0.4, -0.4)  # (BodyVolume marches LEAD_M back, REACH_M on)
	var broad := BodyVolume.entry(chest, Vitals.CHEST, front, Vector3(0, 0, 1), BodyVolume.body_of(chest)) if chest else {}
	var g: Vector3 = chest.get_meta(&"girth", Vector3.ONE) if chest else Vector3.ONE
	if chest:
		chest.set_meta(&"girth", Vector3.ONE)
	var plain := BodyVolume.entry(chest, Vitals.CHEST, front, Vector3(0, 0, 1), BodyVolume.body_of(chest)) if chest else {}
	if chest:
		chest.set_meta(&"girth", g)
	check(g.x > 1.0 and not broad.is_empty() and not plain.is_empty() and (broad.position as Vector3).z < (plain.position as Vector3).z - 0.003,
		"the broad chest is hit where it's drawn, further forward (BodyVolume widens with the build: %s, %s vs %s)" % [g, broad.get("position"), plain.get("position")])
	player.face = old
	await _seconds(0.3)
	check(is_equal_approx(player.model.body_scale(), SoldierLook.height_of(old)), "and back as he was")


# --- Helpers --------------------------------------------------------------------------------

## The carrier's camera isn't inside any of the casualty's meshes (body parts and gear).
func _check_camera_clear(carrier: Soldier, casualty: Soldier, what: String) -> void:
	var eye := carrier.camera.global_position
	var inside := []
	for node in casualty.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if not visual.is_visible_in_tree():
			continue
		var local := visual.global_transform.affine_inverse() * eye
		var box := visual.get_aabb()
		if box.grow(0.05).has_point(local):
			inside.append(visual.name)
	check(inside.is_empty(), "%s: the camera stays clear of the casualty (inside %s)" % [what, inside])


## The right hand passes through MOUNT_POINTS[from] and then [to] during an equip clip.
func _check_mount_path(from: StringName, to: StringName) -> void:
	var seen := {"from": INF, "to": INF}
	await _watch(CharacterModel.EQUIP_S, func() -> void:
		var hand := player.model.hand_position(true)
		seen.from = minf(seen.from, hand.distance_to(player.model.torso.to_global(CharacterModel.MOUNT_POINTS[from])))
		seen.to = minf(seen.to, hand.distance_to(player.model.torso.to_global(CharacterModel.MOUNT_POINTS[to]))))
	check(seen.from < HAND_TOLERANCE and seen.to < HAND_TOLERANCE,
		"the hand goes to the %s (%.1f cm) and then the %s (%.1f cm)" % [from, seen.from * 100.0, to, seen.to * 100.0])


## The middle of body part `part` of `s` as drawn (its bone, ragdoll or pose: an arm's hitbox
## stays with the torso).
func _drawn(s: Soldier, part: StringName) -> Vector3:
	var bone := s.model.part_node(part)
	if bone == null:
		return _part(s, part)
	var down := CharacterModel.UPPER_ARM * 0.5 if String(part).begins_with("upper") else CharacterModel.FOREARM * 0.6
	return bone.to_global(Vector3(0, -down, 0)) if String(part).contains("arm") else _part(s, part)


func _down(s: Soldier) -> void:
	s.vitals.server_damage(500.0)


## Where a body part's hitbox is now.
func _part(s: Soldier, part: StringName) -> Vector3:
	return CharacterModel.part_position(s, part)


func _task_with(s: Soldier, item: StringName) -> Dictionary:
	for task in s.vitals.care_needed():
		if task.item == item:
			return task
	return {}


## Where weapon `id` is drawn on `s` now (shown, not on its way out), as paths from `s`: a
## mesh of its voxel model anywhere on the body (gear, hands, ragdoll), or for a launcher (no
## voxel model) a "Launcher" node.
func _weapon_drawn(s: Soldier, id: StringName) -> Array[String]:
	var art := VoxelArt.model_for(ItemDB.get_item(id))
	var drawn: Array[Node] = []
	if art != "":
		var mesh := VoxelArt.mesh(art, s.model.variant)
		drawn = s.find_children("*", "MeshInstance3D", true, false).filter(func(n: Node) -> bool: return (n as MeshInstance3D).mesh == mesh)
	else:
		drawn = s.find_children("*", "Node3D", true, false).filter(func(n: Node) -> bool:
			return n.name == &"Launcher" or String(n.name).begins_with("@Launcher@"))
	var out: Array[String] = []
	for n in drawn:
		if (n as Node3D).is_visible_in_tree() and not _going(n, s):
			out.append(String(s.get_path_to(n)))
	return out


## Whether `n` or anything above it up to `top` is queued to go.
static func _going(n: Node, top: Node) -> bool:
	while n != null and n != top:
		if n.is_queued_for_deletion():
			return true
		n = n.get_parent()
	return false


func _entry_of(s: Soldier, id: StringName) -> Dictionary:
	for container in Inventory.CONTAINERS:
		var list: Array = s.inventory.containers[container]
		for i in list.size():
			if list[i].id == id:
				return {"container": container, "index": i}
	return {}


func _spawn_ai(callsign: String, faction: StringName, pos: Vector3, loadout: Array) -> Soldier:
	var s := level.spawn_soldier({"name": callsign, "faction": String(faction), "variant": "multicam", "pos": pos,
		"loadout": loadout, "combat": 0.5, "discipline": 0.5, "guard": true})
	SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED  # we stage everything by hand
	return s


func _spawn_item(id: StringName, pos: Vector3) -> WorldItem:
	level.server_spawn_dropped(id, 1, pos)
	await _frames(2)
	var best: WorldItem = null
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := node as WorldItem
		if item.item_id == id and not item.is_queued_for_deletion() and (best == null or item.global_position.distance_to(pos) < best.global_position.distance_to(pos)):
			best = item
	return best


func _place_player() -> void:
	_place(player, SPOT)
	player.head.rotation = Vector3.ZERO


## Stands the player half a metre to the side of `point`, facing along the casualty.
func _beside(point: Vector3) -> void:
	_place(player, Vector3(point.x + 0.5, SPOT.y, point.z))


func _place(s: Soldier, pos: Vector3) -> void:
	s.global_position = pos
	s.rotation = Vector3.ZERO
	s.velocity = Vector3.ZERO


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Calls `probe` every frame for `seconds`.
func _watch(seconds: float, probe: Callable) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		probe.call()
		await get_tree().process_frame


func _wait(condition: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() >= end:
			return false
		await get_tree().process_frame
	return true


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


## Until `s`'s ragdoll has come to rest (Ragdoll.frozen), at most 10 s.
func _settled(s: Soldier) -> void:
	var left := 10.0
	while left > 0.0 and not (is_instance_valid(s.ragdoll) and s.ragdoll.frozen):
		await _seconds(0.1)
		left -= 0.1
