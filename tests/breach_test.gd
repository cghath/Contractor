extends Node
## Breaching holes and "Breach and clear" (Captain's list 2026-10-14, item 3: "breaching charges
## make holes too small; add a 'Breach and clear' team order through walls"; F-317, F-318). On the
## compound, the host's player and his squad:
## - the hole's size comes from the soldier: his capsule (scenes/soldier.tscn) and his kit;
## - a charge on the compound's concrete perimeter wall opens a hole a soldier in kit passes
##   through (a capsule his size and his kit's swept through it touches nothing; it didn't before),
##   and the navmesh is rebaked through it;
## - the same through a generated stone house's wall (the thickest walls a town builds);
## - a wall with no building behind it opens into the yard past it; an AI team against a held
##   building whose door is round the far side picks its own wall breach, not with the door near;
## - then a second process joins, and with it watching: ordered to breach and clear the main
##   building through its east wall, the team stacks on that wall, the one with the charge sets
##   it, backs off, it goes off with nobody in its blast, they go in through the hole once it's
##   on the navmesh and clear the building, every stage in order, and end inside; the client
##   sees the charge, the blast, the hole and the team inside;
## - ordered on the player's own charge (nobody selected carries one), and he goes down before he
##   sets it: they don't wait at the wall for ever, but go in by the building's door and clear it;
## - a wall breach whose charge carriers all go down before the charge is set falls back to the
##   building's door, and the team restacks there before the door is breached (nobody works the
##   new door from where he stood, even once the setter is back up);
## - squadmates in no breach order (F-373): a follower and a man holding, at the wall when the
##   player sets a charge on it, step out of its blast on their side of the wall before it goes,
##   nobody is hurt by it, and they go back to following and to the spot they hold after;
## - a breach under a roof (F-396): the stack stands off past the charge's indoor reach and
##   nobody of it is in the blast when it goes;
## - a medic treating a downed man beside a wall a charge is set on (F-397; Captain, 2026-11-02:
##   "drag him clear asap") drags him out of its blast before it goes, nobody is hurt by it, and
##   he treats him again where he put him down; the same with a man down dying, conscious (F-412;
##   Captain, 2026-11-06: "make him draggable");
## - a door's charge (F-413): the stack stands off from where it really goes, on the stack's own
##   side of a doorway by a corner too, and the indoor push looks over the charge, not the doorway.
##   <godot> --headless --path . res://tests/breach_test.tscn
## The host starts the client itself (same scene, "-- --breach-join"). Exits with the number of
## failures.

var failures := 0
var level: CompoundLevel
var main: Node
var player: Soldier
## Host -> client: what to watch.
var expect: Dictionary = {}
var _client_lines := PackedStringArray()
var _client_failures := -1
var _client_ready := false

## The main building's east wall, its outer face at x = 5 (CompoundLevel.structure_boxes), and the
## north perimeter wall's outer face at z = -20.
const EAST_WALL := Vector3(5.0, 1.2, -8.0)
const NORTH_WALL := Vector3(10.0, 1.0, -20.0)
const HOUSE_AT := Vector3(-34, 0, 44)
const STAGES: Array[String] = ["stacking", "stacked", "charge_set", "backed_off", "blown", "hole_open", "through", "clear"]


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_breach" + tag
	Campaign.campaign_id = "test_breach" + tag
	CompoundLevel.spawn_ai = true
	PeopleLayer.populate = false
	if "--breach-join" in OS.get_cmdline_user_args():
		_run_client()
		return
	get_tree().create_timer(720.0).timeout.connect(func() -> void:
		print("BREACH TEST FAILED (timed out)")
		get_tree().quit(99))
	GameState.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.menu.host()
	level = CompoundLevel.current(self)
	check(level != null and Net.is_hosting(), "hosting the compound")
	if level == null:
		_finish()
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	await _wait_until(func() -> bool: return level.ai.get_node_or_null(^"Golf") != null and level.players.get_node_or_null(^"1") != null, 60.0)
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # placed by hand
	for id: StringName in [&"plate_carrier", &"m4a1", &"helmet"]:
		player.inventory.take(id)
	for s: Soldier in level.ai.get_children():
		if s.faction == &"hostile":
			s.queue_free()
	await _frames(10)
	_test_size()
	_test_door_stand_off()
	await _test_compound_wall()
	await _test_house_wall()
	await _test_targets()
	await _test_order_with_client()
	await _test_lead_down()
	await _test_carriers_down()
	await _test_bystanders()
	await _test_roof_stand_off()
	await _test_medic_drag()
	await _test_medic_drag(DYING_FACE, Vector3(1, 0, 0), true)
	_finish()


# --- The hole ------------------------------------------------------------------------------

func _test_size() -> void:
	print("The hole's size, from the soldier")
	var scene: Node = load("res://scenes/soldier.tscn").instantiate()
	var shape := (scene.get_node(^"Collision") as CollisionShape3D).shape as CapsuleShape3D
	check(shape != null and is_equal_approx(shape.radius, Charges.SOLDIER_R) and is_equal_approx(shape.height, Charges.SOLDIER_H),
		"the sizes start from the soldier's own capsule (%.2f m round, %.2f m tall)" % [shape.radius if shape else 0.0, shape.height if shape else 0.0])
	scene.free()
	check(is_equal_approx(Charges.BREACH_W_M, 1.5) and is_equal_approx(Charges.BREACH_H_M, 2.25)
		and Charges.BREACH_W_M >= 2.0 * (Charges.SOLDIER_R + Charges.KIT_M) + 0.4 and Charges.BREACH_H_M >= Charges.SOLDIER_H + Charges.HEAD_KIT_M + 0.2,
		"capsule plus kit plus room either side: %.2f m wide, %.2f m high (was 1.3 x 2.2)" % [Charges.BREACH_W_M, Charges.BREACH_H_M])
	check(Squad.BLAST_SAFE_M < SquadTactics.STACK_FIRST_M + Squad.CHARGE_STANDOFF_M,
		"the stack's stand-off (%.1f m) is past the charge's blast on its side (%.1f m)" % [SquadTactics.STACK_FIRST_M + Squad.CHARGE_STANDOFF_M, Squad.BLAST_SAFE_M])


## Whether a soldier in kit passes through the wall at `spot` (outer face `n`): a capsule his
## size and his kit's (Charges.SOLDIER_R + KIT_M round, SOLDIER_H + HEAD_KIT_M tall), its foot a
## little over the higher floor, swept from `out_m` outside the face to `in_m` past it, touches
## nothing of the world's layer. Returns where it first touched ("" for nowhere).
func _snag(spot: Vector3, n: Vector3, floor_y: float, out_m := 1.0, in_m := 1.2) -> String:
	var shape := CapsuleShape3D.new()
	shape.radius = Charges.SOLDIER_R + Charges.KIT_M
	shape.height = Charges.SOLDIER_H + Charges.HEAD_KIT_M
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	var space := level.get_world_3d().direct_space_state
	var d := out_m
	while d >= -in_m:
		var p := Vector3(spot.x, floor_y + 0.1 + shape.height * 0.5, spot.z) + n * d
		q.transform = Transform3D(Basis.IDENTITY, p)
		var hits := space.intersect_shape(q, 1)
		if not hits.is_empty():
			var what: Object = hits[0].get("collider")
			return "%.1f m %s the face, on %s" % [absf(d), "out from" if d >= 0.0 else "in past", (what as Node).name if what is Node else "?"]
		d -= 0.1
	return ""


## The sweep through a fresh hole (_snag) in a wall `depth` thick: from 1 m out to where the
## capsule's middle is SNAG_PAST_M past the wall's inner face (its back still inside the hole), so
## it tests the hole and not what stands in the room behind it (a generated house's furniture
## stands FURNITURE_GAP off its walls: CI runs 41181174649 and 41183382775 touched something 0.9 m
## in past a stone house's face, 1.0 m into the room, every time; the sweep used to run 1.2 m in
## whatever the wall). Swept again until clear for up to SNAG_SETTLE_S, in case the collider of a
## chunk past the cut is rebuilt a few frames after the rays find the hole open; a hole really too
## small still fails.
const SNAG_PAST_M := 0.4
const SNAG_SETTLE_S := 3.0


func _snag_after(spot: Vector3, n: Vector3, floor_y: float, depth: float) -> String:
	var got := {"at": ""}  # (a lambda can't set the function's locals)
	await _wait_until(func() -> bool:
		got.at = _snag(spot, n, floor_y, 1.0, depth + SNAG_PAST_M)
		return got.at == "", SNAG_SETTLE_S)
	return got.at


## A charge set by nobody at `spot` on the wall (outer face `n`), fired at once.
func _blow(spot: Vector3, n: Vector3) -> void:
	var charges := Charges.of(level)
	var before := charges.recent.size()
	if not spot.is_finite():
		return
	var id := charges.server_place_at(null, Charges.surface_transform(spot, n, Vector3.UP))
	charges._due[id] = Charges._now()
	await _wait_until(func() -> bool: return charges.recent.size() > before, 5.0)


func _open_at(spot: Vector3, n: Vector3, floor_y: float) -> bool:
	var space := level.get_world_3d().direct_space_state
	for h: float in [0.3, 1.0, 1.9]:
		var p := Vector3(spot.x, floor_y + h, spot.z)
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(p + n * 0.8, p - n * 0.8, 1)).is_empty():
			return false
	return true


func _test_compound_wall() -> void:
	print("A hole in the compound's concrete wall")
	var n := Vector3(0, 0, -1)
	var spot := NORTH_WALL
	var floors := Charges.hole_floors(level, spot, n)
	var depth := Charges.wall_depth(level, spot, n)
	check(absf(floors.x) < 0.15 and absf(floors.y) < 0.15 and absf(depth - CompoundLevel.WALL_THICKNESS) < 0.12,
		"the floors either side (%.2f, %.2f m) and the wall's thickness (%.2f m) are found" % [floors.x, floors.y, depth])
	var before := _snag(spot, n, floors.y)
	var map := level.get_world_3d().navigation_map
	var a := NavigationServer3D.map_get_closest_point(map, spot + n * 3.0)
	var b := NavigationServer3D.map_get_closest_point(map, spot - n * 3.0)
	var nav := level.get_node(^"Navigation") as NavBuilder
	var bakes := nav.bakes
	await _blow(spot, n)
	var open := await _wait_until(func() -> bool: return _open_at(spot, n, floors.y), 8.0)
	await _physics_frames(3)
	var after := await _snag_after(spot, n, floors.y, depth)
	check(before != "" and open and after == "",
		"a soldier in kit is stopped by the wall before (at %s) and walks through the hole after without touching it (%s)" % [before, after if after != "" else "nothing touched"])
	await _wait_until(func() -> bool: return nav.bakes > bakes and not nav.is_rebaking() and nav.map_caught_up(), 10.0)
	await _physics_frames(3)
	var path := NavigationServer3D.map_get_path(map, a, b, true)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	check(nav.bakes > bakes and path.size() >= 2 and length < 8.0, "the navmesh is rebaked through it (a path %.1f m long from outside to in)" % length)


func _test_house_wall() -> void:
	print("A hole in a generated stone house's wall")
	var house := {}
	for seed in range(1, 300):
		var c := BuildingGen.house(seed, "stone")
		if int(c.storeys) == 1 and (c.yards as Array).is_empty() and c.shape == "rect":
			house = c
			house["seed"] = seed
			break
	if house.is_empty():
		check(false, "a single-storey stone house")
		return
	var holder := Node3D.new()
	holder.name = "BreachHouse"
	holder.position = HOUSE_AT
	var world := VoxelWorld.new()
	world.bounds = AABB(Vector3(-120, -10, -120), Vector3(240, 80, 240))
	world.view_distance = 2000
	world.edit_sink = func(w: VoxelWorld, edit: Dictionary) -> void: w.apply_edit(edit)  # (this world's alone: not the compound's edit log)
	for bx: Array in house.boxes:
		world.add_box_m(bx[0], bx[1], bx[2])
	level.add_child(holder)
	holder.add_child(world)
	_place(player, HOUSE_AT + Vector3(-(house.size as Vector2).x * 0.5 - 6.0, 0.1, 0))  # (voxels build round the player)
	await _wait_until(func() -> bool: return world.is_built(), 30.0)
	# A stretch of its west wall with no window or door: rays at three heights stop on its face.
	var space := level.get_world_3d().direct_space_state
	var n := Vector3(-1, 0, 0)
	var picked := {"spot": Vector3.INF}  # (a lambda can't set the function's locals)
	var found := await _wait_until(func() -> bool:
		for dz: float in [0.0, 1.0, -1.0, 2.0, -2.0, 1.5, -1.5, 0.5, -0.5]:
			var face_x := INF
			var ok := true
			for h: float in [0.3, 1.0, 1.9]:
				var from := HOUSE_AT + Vector3(-(house.size as Vector2).x * 0.5 - 3.0, h, dz)
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(6, 0, 0), 1))
				if hit.is_empty() or (hit.normal as Vector3).dot(n) < 0.9 or (is_finite(face_x) and absf((hit.position as Vector3).x - face_x) > 0.05):
					ok = false
					break
				face_x = (hit.position as Vector3).x
			if ok:
				picked.spot = Vector3(face_x, 1.0, HOUSE_AT.z + dz)
				return true
		return false, 15.0)
	if not found:
		check(false, "a stretch of the house's wall without a window or door (seed %d)" % house.seed)
		holder.queue_free()
		return
	var spot: Vector3 = picked.spot
	var floors := Charges.hole_floors(level, spot, n)
	var depth := Charges.wall_depth(level, spot, n)
	print("    house seed %d, wall at x %.2f (z %.2f), %.2f m thick, floors %.2f / %.2f m" % [house.seed, spot.x, spot.z, depth, floors.x, floors.y])
	var before := _snag(spot, n, floors.y)
	var compound_world := level.voxel_world
	level.voxel_world = world  # blasts reach the level's voxel_worlds(): the house stands in for it meanwhile
	await _blow(spot, n)
	var open := await _wait_until(func() -> bool: return _open_at(spot, n, floors.x), 8.0)
	await _physics_frames(3)
	level.voxel_world = compound_world
	var after := await _snag_after(spot, n, floors.y, depth)
	check(depth > 0.3 and depth < 0.55, "its wall is found %.2f m thick (stone: %.2f m)" % [depth, float(BuildingGen.STYLES.stone.t)])
	check(before != "" and open and after == "",
		"a soldier in kit is stopped by it before (at %s) and walks through the hole after without touching it (%s)" % [before, after if after != "" else "nothing touched"])
	holder.queue_free()
	await _frames(2)


# --- What's past the wall, and an AI team's choice ------------------------------------------

func _test_targets() -> void:
	print("What's past the wall; an AI team's own wall breach")
	var squad := level.squad_for(&"friendly")
	var mates := _team(4)
	if mates.size() < 4:
		check(false, "four fit squadmates (%d)" % mates.size())
		return
	_place(player, Vector3(0, 0.1, -26))
	await _seconds(0.3)
	var perimeter := SquadTactics.wall_at(player, Vector3(0, 1.0, -20))
	var yard := squad.breach_target(player, perimeter)
	check(bool(yard.get("yard", false)) and (yard.rooms[0].corners as Array).size() == 4
		and (yard.rooms[0].corners as Array).all(func(p: Vector3) -> bool: return p.z > -19.5)
		and not SquadTactics.building_beyond(player.get_world_3d(), perimeter),
		"the perimeter wall from outside: no building behind it, the yard past it (%s)" % [yard.get("rooms", [{}])[0].get("corners", [])])
	_place(player, Vector3(10, 0.1, -8))
	await _seconds(0.3)
	var wall := SquadTactics.wall_at(player, EAST_WALL)
	# Asked once, on a cold cache, with the frame budget a player's machine has (review of
	# 7b6d7576: a budgeted scan cut short came back as no building, and the wall as a yard's).
	Buildings.forget()
	Buildings.budget_always = true
	var b: Dictionary = squad.breach_target(player, wall) if not wall.is_empty() else {}
	Buildings.budget_always = false
	check(not wall.is_empty() and (wall.face as Vector3).dot(Vector3.RIGHT) > 0.95 and absf((wall.at as Vector3).x - 5.0) < 0.1
		and not b.is_empty() and not bool(b.get("yard", false)) and not b.has("refused") and Buildings.contains(b, Vector3(0, 0.1, -8)),
		"the main building's east wall, pointed at (asked once, cold, budgeted): its face (%s) and the building behind it (found %s, a yard %s, %s, %d spots, centre %s)"
		% [wall.get("face", Vector3.ZERO), not b.is_empty(), b.get("yard", false), b.get("refused", "not refused"), (b.get("spots", []) as Array).size(), b.get("centre", Vector3.INF)])
	check(not wall.is_empty() and SquadTactics.building_beyond(player.get_world_3d(), wall) and SquadTactics.yard_beyond(player.get_world_3d(), wall).is_empty(),
		"past that wall is a building's inside even with no lookup: never taken for a yard")
	check(SquadTactics.wall_at(player, Vector3(9, 0.0, -8)).is_empty(), "the ground isn't a wall")
	# An AI team east of the building (its door round on the south side) with a charge: through the wall.
	var kits := _strip_charges(mates)
	Roles.give(mates[2].body.inventory, Charges.ITEM, 1)
	for i in mates.size():
		_place(mates[i].body, Vector3(10, 0.1, -9.5 + i))
	await _physics_frames(3)
	var entry: Array[SquadAI] = []
	entry.assign(mates)
	var door_op := SquadTactics.clear_op(b, entry)
	var op := squad.tactics.wall_breach_for(b, entry, door_op)
	check(not op.is_empty() and bool(op.get("wall", false)) and String(op.get("door", "")) == "charge" and entry[0] == mates[2]
		and absf((op.charge_spot.at as Vector3).x - 5.0) < 0.2,
		"a team east of it, its door round the south side: they blow their own way in through the east wall, the one with the charge first (%s)"
		% [op.get("charge_spot", {})])
	# By the door: the door.
	for i in mates.size():
		_place(mates[i].body, Vector3(-1.5 + i, 0.1, -1.0))
	await _physics_frames(3)
	entry.assign(mates)
	door_op = SquadTactics.clear_op(b, entry)
	check(squad.tactics.wall_breach_for(b, entry, door_op).is_empty(), "a team by the door: in by the door")
	_strip_charges(mates)
	for ai: SquadAI in mates:
		if int(kits.get(ai, 0)) > 0:
			Roles.give(ai.body.inventory, Charges.ITEM, int(kits[ai]))


# --- The order, with a client watching ------------------------------------------------------

func _test_order_with_client() -> void:
	print("Breach and clear, ordered (a client joins and watches)")
	var squad := level.squad_for(&"friendly")
	_place(player, Vector3(11, 0.1, -8))
	expect = {"spot": EAST_WALL, "normal": Vector3.RIGHT}
	# The client joins first, to watch it all live (a joining player takes an AI's place in the
	# squad, so the team is picked after).
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = false
	var log_path := OS.get_user_data_dir().path_join("breach_client%s.log" % OS.get_environment("CONTRACTOR_TEST_TAG"))
	DirAccess.remove_absolute(log_path)
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--log-file", log_path, "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/breach_test.tscn", "--", "--breach-join"])
	check(pid > 0, "started the client process")
	await _wait_until(func() -> bool: return _client_ready, 150.0)
	check(_client_ready, "the client joined and is watching")
	await _heal_squad()
	var mates := _team(4)
	if mates.size() < 4:
		check(false, "four fit squadmates (%d)" % mates.size())
		_done_watching.rpc()
		await _end_client(pid, log_path)
		return
	_strip_charges(mates)
	Roles.give(mates[1].body.inventory, Charges.ITEM, 1)
	for i in mates.size():
		_place(mates[i].body, Vector3(11.5, 0.1, -4.0 + i * 0.9))
	var names := PackedStringArray(mates.map(func(ai: SquadAI) -> String: return String(ai.body.name)))
	_team_names.rpc(names)
	await _seconds(0.5)
	var why := squad.order_command(player, "breach_clear", EAST_WALL, names)
	var setter := mates[1]
	var op: Dictionary = setter.ordered.get("op", {}) if why == "" else {}
	check(why == "" and not op.is_empty() and bool(op.get("wall", false)) and int(setter.ordered.get("slot", -1)) == 0 and String(op.get("door", "")) == "charge",
		"ordered: they stack on the east wall, the one with the charge first (%s)" % why)
	if op.is_empty():
		_done_watching.rpc()
		await _end_client(pid, log_path)
		return
	var stack_bad := (op.stack as Array).filter(func(p: Vector3) -> bool:
		return (p - (op.charge_spot.at as Vector3)).dot(Vector3.RIGHT) < 0.2 or Buildings.contains(op.building, p))
	check(stack_bad.is_empty(), "the stack forms outside, along that wall (%s)" % [op.stack])
	# Watch every frame until the charge goes off: where each of them is when it does.
	var charges := Charges.of(level)
	var at_blast := {"d": {}, "at": Vector3.INF}
	var blown := await _wait_until(func() -> bool:
		var id := String(op.get("charge_id", ""))
		if id != "" and charges.records.has(id):
			at_blast.at = charges.position_of(id)
			for ai: SquadAI in mates:
				if is_instance_valid(ai):
					at_blast.d[String(ai.body.name)] = ai.body.global_position.distance_to(at_blast.at)
			return false
		return id != "", 70.0)
	await _physics_frames(2)
	var hurt := mates.filter(func(ai: SquadAI) -> bool: return not is_instance_valid(ai) or ai.body.vitals.deaf_left() > 0.0 or not ai.body.vitals.is_up())
	var nearest := INF
	for k: String in at_blast.d:
		nearest = minf(nearest, float(at_blast.d[k]))
	check(blown and nearest > Squad.BLAST_SAFE_M and hurt.is_empty(),
		"he sets it, they back off, it goes off with nobody in its blast (nearest %.1f m, past %.1f m; hurt: %d)"
		% [nearest, Squad.BLAST_SAFE_M, hurt.size()])
	var spot: Vector3 = op.charge_spot.at
	check(absf(spot.x - 5.0) < 0.15 and absf(spot.z - EAST_WALL.z) < 0.3, "the charge went where he pointed (%s)" % spot)
	# In through the hole, and the building cleared.
	var came_in := {}
	var cleared := await _wait_until(func() -> bool:
		for ai: SquadAI in mates:
			if is_instance_valid(ai) and not came_in.has(ai) and Buildings.contains(op.building, ai.body.global_position):
				came_in[ai] = ai.body.global_position
		return _stage_at(op, "clear") > 0.0, 90.0)
	var stage_names: Array = (op.get("stages", []) as Array).map(func(s: Dictionary) -> String: return String(s.name))
	var in_order := stage_names == STAGES
	for i in range(1, (op.get("stages", []) as Array).size()):
		in_order = in_order and float(op.stages[i].at) >= float(op.stages[i - 1].at)
	check(in_order and _stage_at(op, "backed_off") < _stage_at(op, "blown"),
		"every stage, in order: %s" % [stage_names])
	var via_hole := came_in.values().filter(func(p: Vector3) -> bool: return p.x > 2.0)
	check(cleared and via_hole.size() == mates.size(),
		"they go in through the hole, not round by the door (%d of %d first seen inside by it)" % [via_hole.size(), mates.size()])
	await _seconds(1.0)
	var inside := mates.filter(func(ai: SquadAI) -> bool: return is_instance_valid(ai) and Buildings.contains(op.building, ai.body.global_position))
	check(cleared and inside.size() == mates.size(), "and the team ends inside the building, cleared (%d of %d)" % [inside.size(), mates.size()])
	_done_watching.rpc()
	await _end_client(pid, log_path)


# --- The leader's own charge, and he goes down before he sets it ---------------------------

## Review of 7b6d7576: nobody selected carries a charge but the player does, so the team stacks on
## the wall and holds for his; he goes down before he sets it. They mustn't wait at the wall for
## ever: with nobody else carrying one, in by the building's door, and the building cleared.
const WEST_WALL := Vector3(-5.0, 1.2, -8.0)


func _test_lead_down() -> void:
	print("Breach and clear on the leader's own charge; he goes down before he sets it")
	var squad := level.squad_for(&"friendly")
	await _heal_squad()
	var mates := _team(4)
	if mates.size() < 4:
		check(false, "four fit squadmates (%d)" % mates.size())
		return
	_strip_charges(mates)
	while player.inventory.remove_one(Charges.ITEM):
		pass
	Roles.give(player.inventory, Charges.ITEM, 1)
	_place(player, Vector3(-9, 0.1, -8))
	for i in mates.size():
		_place(mates[i].body, Vector3(-9.5, 0.1, -11.0 + i * 0.9))
	await _seconds(0.5)
	var names := PackedStringArray(mates.map(func(ai: SquadAI) -> String: return String(ai.body.name)))
	var why := squad.order_command(player, "breach_clear", WEST_WALL, names)
	var op: Dictionary = mates[0].ordered.get("op", {}) if why == "" else {}  # (every one of them has the same op)
	check(why == "" and not op.is_empty() and bool(op.get("wall", false)) and op.get("on") == player and String(op.get("door", "")) == "",
		"ordered with only his charge: they stack on the west wall and hold for it (%s)" % why)
	if op.is_empty():
		return
	# Down before he sets it: out cold (the wound model's own unconsciousness; Vitals.downed follows
	# it every sim step, so setting the flag alone doesn't hold).
	player.vitals.server_damage(70.0)
	var down := await _wait_until(func() -> bool: return not player.vitals.is_up(), 5.0)
	check(down, "he's out cold (%s)" % player.vitals.condition_text())
	var handed := await _wait_until(func() -> bool: return not bool(op.get("wall", true)) or mates.all(func(ai: SquadAI) -> bool: return ai.ordered.is_empty()), 60.0)
	player.vitals.server_reset_health()  # (back up, so nobody stays to treat him while they clear)
	if not handed:
		print("    op: ready %s of %d, first ready %.1f s ago, go_at %s, stages %s" % [op.ready, int(op.units), Soldier._now() - float(op.first_ready_at), op.go_at,
			(op.get("stages", []) as Array).map(func(st: Dictionary) -> String: return String(st.name))])
		for ai: SquadAI in mates:
			print("    %s: care %d, tactic %s (same op %s), at %s, %.1f m from its stack spot" % [ai.body.name, ai.care, ai._tactic().get("kind", "-"),
				is_same(ai._tactic().get("op"), op), ai.body.global_position, ai.body.global_position.distance_to(op.stack[int(ai.ordered.get("slot", 0))])])
	check(handed and not bool(op.get("wall", true)) and not op.has("on") and (op.entrance.door as Vector3).z > -5.0,
		"he's down: they don't wait at the wall for his charge, nobody else has one, so in by the door (wall %s, door at %s)"
		% [op.get("wall", "?"), op.entrance.get("door", Vector3.INF)])
	var cleared := await _wait_until(func() -> bool: return _stage_at(op, "clear") > 0.0, 90.0)
	await _seconds(0.5)
	var inside := mates.filter(func(ai: SquadAI) -> bool: return is_instance_valid(ai) and Buildings.contains(op.building, ai.body.global_position))
	check(cleared and inside.size() == mates.size(), "and they clear the building and end inside it (%d of %d)" % [inside.size(), mates.size()])


# --- Every charge carrier down before the charge is set ------------------------------------

## Review of feat/breach-and-clear: the door fallback (SquadAI._wall_breacher_lost) left the op
## "breaching", so the setter (back up, or out of charges at the wall) worked the new door from
## where he stood and the team went before it had restacked. Two of four carry a charge; the
## setter is on his way to the wall when both go down: in by the door, everyone at his new place
## in the stack before it's breached, the setter (woken) with them.
func _test_carriers_down() -> void:
	print("Breach and clear: every charge carrier down before the charge is set")
	var squad := level.squad_for(&"friendly")
	await _heal_squad()
	var mates := _team(4)
	if mates.size() < 4:
		check(false, "four fit squadmates (%d)" % mates.size())
		return
	_strip_charges(mates)
	while player.inventory.remove_one(Charges.ITEM):
		pass
	Roles.give(mates[0].body.inventory, Charges.ITEM, 1)
	Roles.give(mates[1].body.inventory, Charges.ITEM, 1)
	_place(player, Vector3(-12, 0.1, -16))
	for i in mates.size():
		_place(mates[i].body, Vector3(-9.5, 0.1, -11.0 + i * 0.9))
	await _seconds(0.5)
	var names := PackedStringArray(mates.map(func(ai: SquadAI) -> String: return String(ai.body.name)))
	var why := squad.order_command(player, "breach_clear", WEST_WALL, names)
	var op: Dictionary = mates[0].ordered.get("op", {}) if why == "" else {}
	var carriers: Array[SquadAI] = [mates[0], mates[1]]
	check(why == "" and not op.is_empty() and bool(op.get("wall", false)) and String(op.get("door", "")) == "charge" and carriers.has(op.get("breacher_ai")),
		"ordered with two charges among them: they stack on the west wall, a carrier to set it (%s)" % why)
	if op.is_empty():
		return
	var setting := await _wait_until(func() -> bool: return bool(op.get("breaching", false)), 60.0)
	var setter: SquadAI = op.get("breacher_ai")
	for ai: SquadAI in carriers:
		ai.body.vitals.server_damage(70.0)
	var down := await _wait_until(func() -> bool: return carriers.all(func(ai: SquadAI) -> bool: return not ai.body.vitals.is_up()), 5.0)
	check(setting and down and not op.has("charge_id"), "the setter's on his way to the wall when both carriers go down, his charge not yet set (down %s)" % down)
	var fell_back := await _wait_until(func() -> bool: return not bool(op.get("wall", true)), 30.0)
	var since := Soldier._now()
	check(fell_back and String(op.get("door", "?")) == "" and not bool(op.get("breaching", true)) and not op.has("breach_from") and (op.entrance.door as Vector3).z > -5.0,
		"nobody left with a charge: in by the door (at %s), and nobody's working it yet (breaching %s)" % [op.entrance.get("door", Vector3.INF), op.get("breaching", "?")])
	for ai: SquadAI in carriers:
		ai.body.vitals.server_reset_health()  # (back up: the setter mustn't go for the door on his own)
	# The door's breach (go_at) only once they've restacked by it: every one of them ready at his
	# new place, or the stack's wait out since the first was.
	var went := await _wait_until(func() -> bool: return is_finite(float(op.go_at)), 60.0)
	var ready: Dictionary = op.ready
	var waited := Soldier._now() - float(op.first_ready_at) >= SquadTactics.STACK_WAIT_S - 0.1
	var setter_slot := int(setter._tactic().get("slot", -1)) if is_instance_valid(setter) else -1
	check(went and is_finite(float(op.first_ready_at)) and float(op.first_ready_at) >= since and (ready.size() >= int(op.units) or waited) and ready.has(setter_slot),
		"they restack by the door before it's breached, the setter with them (%d of %d ready, setter's slot %d ready %s, waited out %s)"
		% [ready.size(), int(op.units), setter_slot, ready.has(setter_slot), waited])
	await _heal_squad()


# --- Squadmates in no breach order, at a wall a charge is set on ---------------------------

## F-373 (Captain, 2026-10-31: yes): only the ordered team stood off from a charge; a follower or
## a man holding by the wall stayed where he was while it burned. The player sets a charge on the
## main building's north wall (untouched so far) with a follower and a man holding beside it: both
## step out of its blast, on their side of the wall, before it goes; nobody is hurt by it; then
## the follower follows again and the other goes back to the spot he holds.
const NORTH_FACE := Vector3(0.0, 1.0, -12.0)


func _test_bystanders() -> void:
	print("Squadmates in no breach order step clear of a charge, then go back to it")
	var squad := level.squad_for(&"friendly")
	await _heal_squad()
	var mates := _team(2)
	if mates.size() < 2:
		check(false, "two fit squadmates (%d)" % mates.size())
		return
	var n := Vector3(0, 0, -1)
	var hit := level.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(NORTH_FACE + n * 2.0, NORTH_FACE - n * 0.5, 1))
	check(not hit.is_empty() and (hit.normal as Vector3).dot(n) > 0.95, "the main building's north wall, its face to the north (%s)" % [hit.get("position", "not found")])
	if hit.is_empty():
		return
	var spot: Vector3 = hit.position
	while player.inventory.remove_one(Charges.ITEM):
		pass
	Roles.give(player.inventory, Charges.ITEM, 1)
	squad.leader = player
	# The leader stands 1.5 m off the wall until the charge is set and the follower stands in its
	# blast beside him; his place behind the leader lies outside it (about 5.4 m from it, printed
	# below), so what shows he steps clear, rather than just walking back to his place, is that he
	# goes through "Getting clear of a charge" (checked below; review of feat/breach-and-clear).
	# Then the leader steps 4.5 m out himself.
	_place(player, Vector3(spot.x, 0.1, spot.z) + n * 1.5)
	var follower := mates[0]
	var holder := mates[1]
	follower.on_order(Squad.Order.FOLLOW, player.global_position)
	_place(follower.body, spot + n * 0.7 + Vector3(-1.2, -0.9, 0.0))
	_place(holder.body, spot + n * 0.7 + Vector3(1.2, -0.9, 0.0))
	holder.on_order(Squad.Order.HOLD, holder.body.global_position)
	var hold_at: Vector3 = holder._hold_point
	await _seconds(1.0)  # (the holder settles on his spot; the follower may already be heading to his slot)
	_place(follower.body, spot + n * 0.7 + Vector3(-1.2, -0.9, 0.0))
	var slot_then := squad.follow_point(follower.body)
	var friends: Array = level.ai.get_children().filter(func(s: Node) -> bool: return s is Soldier and (s as Soldier).faction == &"friendly" and not s.is_queued_for_deletion())
	friends.append(player)
	var was_hurt := {}
	for s: Soldier in friends:
		was_hurt[s] = s.vitals.injury()
	var charges := Charges.of(level)
	var id := charges.server_place_at(player, Charges.surface_transform(spot, n, Vector3.UP))
	_place(player, Vector3(spot.x, 0.1, spot.z) + n * 4.5)  # (clear of it himself now)
	var info: Dictionary = {}
	for c: Dictionary in charges.burning():
		if c.id == id:
			info = c
	var reach := SquadAI.charge_reach(info, spot + n) if not info.is_empty() else 0.0
	print("    the follower's place behind the leader when it was set: %.1f m from it (in its blast: %s)" % [SquadAI._flat_between(slot_then, spot), SquadAI._flat_between(slot_then, spot) < reach])
	var men: Array[SquadAI] = [follower, holder]
	var started := men.map(func(ai: SquadAI) -> float: return SquadAI._flat_between(ai.body.global_position, spot))
	check(id != "" and not info.is_empty() and info.wall.dot(n) > 0.95 and not bool(info.indoors) and StringName(info.faction) == player.faction
		and is_equal_approx(reach, Squad.BLAST_SAFE_M) and started.all(func(d: float) -> bool: return d < reach),
		"he sets it on the wall, both of them in its blast (%.1f and %.1f m from it; it reaches %.1f m their side, the ordered stack's stand-off)" % [started[0], started[1], reach])
	if id == "" or info.is_empty():
		return
	# Every frame until it goes off: where each of them is, and never past the wall's face.
	var seen := {"d": [INF, INF], "through": false, "statuses": [[], []]}
	await _wait_until(func() -> bool:
		if not charges.records.has(id):
			return true
		for i in men.size():
			var p := men[i].body.global_position
			seen.d[i] = SquadAI._flat_between(p, spot)
			if (p - spot).dot(n) < 0.0:
				seen.through = true
			if not seen.statuses[i].has(men[i].body.ai_status):
				seen.statuses[i].append(men[i].body.ai_status)
		return false, MissionRegistry.setting_f("charge_fuse_s", 10.0) + 5.0)
	await _physics_frames(2)
	var blown := not charges.records.has(id)
	var hurt := friends.filter(func(s: Soldier) -> bool: return is_instance_valid(s) and (s.vitals.deaf_left() > 0.0 or not s.vitals.is_up() or s.vitals.injury() > float(was_hurt[s]) + 0.001))
	check(blown and (seen.d as Array).all(func(d: float) -> bool: return d > reach) and not seen.through,
		"before it goes off both step out of its blast, on their side of the wall (%.1f and %.1f m from it, past %.1f m; through the wall: %s; %s / %s)"
		% [seen.d[0], seen.d[1], reach, seen.through, ", ".join(seen.statuses[0]), ", ".join(seen.statuses[1])])
	check((seen.statuses[0] as Array).has("Getting clear of a charge") and (seen.statuses[1] as Array).has("Getting clear of a charge"),
		"each of them, the follower too, went through \"Getting clear of a charge\" (not just to a place that was clear anyway: %s / %s)"
		% [", ".join(seen.statuses[0]), ", ".join(seen.statuses[1])])
	check(blown and hurt.is_empty(), "nobody is hurt by it (%s)" % [", ".join(hurt.map(func(s: Soldier) -> String: return "%s: %s" % [s.name, s.vitals.condition_text()]))])
	# Then back to what they were doing: following, and the spot he holds.
	var following := func() -> bool:
		var to := follower.destination()
		var slot := squad.follow_point(follower.body)
		return SquadAI._flat_between(to, slot) < 0.6 or (follower._halt_spot != null and SquadAI._flat_between(to, follower._halt_spot) < 0.6)
	var back := await _wait_until(func() -> bool:
		return (follower._clear_spot == null and holder._clear_spot == null and follower.order == Squad.Order.FOLLOW and follower.intent == SquadAI.Intent.FOLLOW
			and following.call() and holder.order == Squad.Order.HOLD and holder.intent == SquadAI.Intent.HOLD and holder._flat_distance(hold_at) <= SquadAI.ARRIVE + 0.3), 20.0)
	check(back, "then the follower follows again (to %s, %s) and the other is back on the spot he holds (%.1f m from it, %s)"
		% [follower.destination(), follower.body.ai_status, holder._flat_distance(hold_at), holder.body.ai_status])
	holder.on_order(Squad.Order.FOLLOW, player.global_position)
	await _heal_squad()


# --- A medic treating a man beside a charge ------------------------------------------------

## F-397 (Captain, 2026-11-02: "drag him clear asap"): a medic treating a downed man beside the
## main building's west wall (by its south-west corner, 2.5 m from where the roof case blew it;
## the north wall's bystanders' hole is too near for a spot on that one) when the player
## sets a charge on it stops, drags him out of its blast on their side of the wall before it
## goes, nobody is hurt by it, and he treats him again where he put him down. Then the same with
## a man down dying, conscious (F-412; Captain, 2026-11-06: "make him draggable"), by the east
## wall (mirrored: by its south-east corner, 2.5 m from the client case's hole).
const MEDIC_FACE := Vector3(-5.0, 1.0, -5.5)
const DYING_FACE := Vector3(5.0, 1.0, -5.5)


func _test_medic_drag(face := MEDIC_FACE, n := Vector3(-1, 0, 0), dying := false) -> void:
	print("A medic treating a man %s beside a charge drags him clear of it, then treats him again" % ("down dying" if dying else "out cold"))
	var squad := level.squad_for(&"friendly")
	await _heal_squad()
	var medic: SquadAI = null
	var man: Soldier = null
	for node in level.ai.get_children():
		var s := node as Soldier
		var ai := SquadAI.of(s) if s and not s.is_queued_for_deletion() else null
		if ai == null or s.faction != &"friendly" or not s.vitals.is_up() or s.carrying != null or is_instance_valid(s.carried_by):
			continue
		if s.role == Roles.MEDIC and medic == null:
			medic = ai
		elif s.role != Roles.MEDIC and man == null:
			man = s
	check(medic != null and man != null, "a medic and a squadmate (%s, %s)" % [medic.body.name if medic else "none", man.name if man else "none"])
	if medic == null or man == null:
		return
	var along := n.cross(Vector3.UP) * (-1.0 if n.x > 0.0 else 1.0)  # (towards the building's north either side: mirrored)
	var hit := level.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(face + n * 2.0, face - n * 0.5, 1))
	check(not hit.is_empty() and (hit.normal as Vector3).dot(n) > 0.95, "the wall there, its face out (%s)" % [hit.get("position", "not found")])
	if hit.is_empty():
		return
	var spot: Vector3 = hit.position
	while player.inventory.remove_one(Charges.ITEM):
		pass
	Roles.give(player.inventory, Charges.ITEM, 1)
	squad.leader = player
	_place(player, Vector3(spot.x, 0.1, spot.z) + n * 8.0 - along * 7.0)  # (well clear of it)
	medic.on_order(Squad.Order.FOLLOW, player.global_position)  # (no hold from earlier keeps him off a casualty)
	_place(man, Vector3(spot.x, 0.1, spot.z) + n * 0.9)
	_place(medic.body, Vector3(spot.x, 0.1, spot.z) + along * 1.0 + n * 1.3)
	await _physics_frames(3)
	# Out cold (as _test_lead_down's player), or down dying with nothing of his own to treat
	# himself with (he calls for a medic), with wounds to treat that take a while.
	if not dying:
		man.vitals.server_damage(70.0)
	man.vitals.server_add_wound(Vitals.THIGH_L, "venous", 0.03)
	man.vitals.server_add_wound(Vitals.FOREARM_R, "venous", 0.02)
	man.vitals.server_add_wound(Vitals.UPPER_ARM_L, "venous", 0.02)
	if dying:
		_strip_medical(man)
		man.vitals._model.blood = 1.0 - WoundModel.DYING_LOST - 0.02
		man.vitals._model.update_state(0.1)
		SquadAI.of(man)._medic_called_at = Soldier._now()
	var down := await _wait_until(func() -> bool: return man.vitals.is_dying() and man.vitals.is_up() if dying else man.vitals.downed, 5.0)
	var why := squad.order_treat(player, String(man.name), PackedStringArray([String(medic.body.name)]))
	var treating := await _wait_until(func() -> bool:
		return medic.casualty == man and medic.care == SquadAI.Care.TREAT and medic._treat_until >= 0.0, 20.0)
	check(down and why == "" and treating, "%s is down by the wall and the medic %s is treating him (%s; %s; down %s, care %d, intent %d, his casualty %s)"
		% [man.name, medic.body.name, why, medic.body.ai_status, down, medic.care, medic.intent, medic.casualty.name if is_instance_valid(medic.casualty) else "none"])
	if not treating:
		man.vitals.server_reset_health()
		await _heal_squad()
		return
	var friends: Array = level.ai.get_children().filter(func(s: Node) -> bool: return s is Soldier and (s as Soldier).faction == &"friendly" and not s.is_queued_for_deletion())
	friends.append(player)
	var charges := Charges.of(level)
	var id := charges.server_place_at(player, Charges.surface_transform(spot, n, Vector3.UP))
	var was := {}
	for s: Soldier in friends:
		was[s] = s.vitals.last_cause
	var info: Dictionary = {}
	for c: Dictionary in charges.burning():
		if c.id == id:
			info = c
	var reach := SquadAI.charge_reach(info, spot + n) if not info.is_empty() else 0.0
	var started := [SquadAI._flat_between(man.body_point(), spot), SquadAI._flat_between(medic.body.global_position, spot)]
	check(id != "" and not info.is_empty() and not bool(info.indoors) and started.all(func(d: float) -> bool: return d < reach),
		"the player sets a charge on the wall beside them, both in its blast (%.1f and %.1f m from it; it reaches %.1f m)" % [started[0], started[1], reach])
	if id == "" or info.is_empty():
		man.vitals.server_reset_health()
		await _heal_squad()
		return
	var seen := {"man": INF, "capsule": INF, "medic": INF, "through": false, "statuses": [], "held_dying": false}
	await _wait_until(func() -> bool:
		if not charges.records.has(id):
			return true
		if man.is_held() and man.vitals.is_dying():
			seen.held_dying = true
		seen.man = SquadAI._flat_between(man.body_point(), spot)
		seen.capsule = SquadAI._flat_between(man.global_position, spot)
		seen.medic = SquadAI._flat_between(medic.body.global_position, spot)
		var points := {"his ragdoll": man.body_point(), "his capsule": man.global_position, "the medic": medic.body.global_position}
		for k: String in points:
			if not seen.through and ((points[k] as Vector3) - spot).dot(n) < -0.3:  # (into the wall: a ragdoll lying against it reaches a little in)
				seen.through = "%s at %s" % [k, points[k]]
		if not seen.statuses.has(medic.body.ai_status):
			seen.statuses.append(medic.body.ai_status)
		return false, MissionRegistry.setting_f("charge_fuse_s", 10.0) + 5.0)
	await _physics_frames(2)
	var blown := not charges.records.has(id)
	var dragged := (seen.statuses as Array).any(func(st: String) -> bool: return st.begins_with("Dragging") and st.ends_with("clear of a charge"))
	check(blown and dragged and seen.man > reach and seen.capsule > reach and seen.medic > reach and not seen.through,  # (false, or what went through)
		"before it goes off he drags him out of its blast, on their side of the wall (him %.1f m from it, %.1f m by his capsule; the medic %.1f m; past %.1f m; through the wall: %s; %s)"
		% [seen.man, seen.capsule, seen.medic, reach, seen.through, ", ".join(seen.statuses)])
	if dying:
		check(seen.held_dying, "dragged while still conscious and dying, not left to crawl (%s)" % man.vitals.condition_text())
	var blasted := friends.filter(func(s: Soldier) -> bool:
		return is_instance_valid(s) and (s.vitals.deaf_left() > 0.0 or (not is_same(s.vitals.last_cause, was[s]) and String(s.vitals.last_cause.get("cause", "")) == "blast")))
	check(blown and blasted.is_empty(), "nobody is hurt by it (%s)" % [", ".join(blasted.map(func(s: Soldier) -> String: return "%s: %s" % [s.name, s.vitals.condition_text()]))])
	var again := await _wait_until(func() -> bool:
		return medic.casualty == man and medic.care == SquadAI.Care.TREAT and medic._treat_until >= 0.0 and medic.body.carrying == null, 20.0)
	check(again and medic._flat_distance(man.body_point()) <= SquadAI.CASUALTY_REACH + 1.0,
		"then he treats him again where he put him down (%s, %.1f m from him)" % [medic.body.ai_status, medic._flat_distance(man.body_point())])
	man.vitals.server_reset_health()
	await _heal_squad()


# --- A door charge's stand-off ---------------------------------------------------------------

## F-413 (Captain, 2026-11-06: yes): a door's charge goes on the wall CHARGE_ALONG_M past the
## doorway from the stack, else, with no wall there (a doorway by a corner), on the stack's own
## side: the stack stands off from where it really goes, as far from it either way. And the
## indoor push (F-396) looks over where the charge goes, not over the doorway, so a door stack on
## a building with no roof over its wall isn't pushed on past its corner (review of
## feat/breach-and-clear). On the main building's south face (z = -4, its doorway at x = 0, its
## south-east corner at x = 5), stacks laid out by hand to the west of a doorway.
func _test_door_stand_off() -> void:
	print("A door charge: the stack stands off from where it really goes")
	var world := level.get_world_3d()
	var normal := Vector3(0, 0, 1)
	var west := Vector3(-1, 0, 0)
	var make := func(door: Vector3) -> Dictionary:
		var stack: Array[Vector3] = []
		for i in 4:
			stack.append(door + normal * SquadTactics.STACK_OUT_M + west * (SquadTactics.STACK_FIRST_M + SquadTactics.STACK_GAP_M * i))
		return {"entrance": {"door": door, "normal": normal}, "stack": stack, "breach": "charge"}
	var nearest := func(op: Dictionary, at: Vector3) -> float:
		var d := INF
		for p: Vector3 in op.stack:
			d = minf(d, SquadAI._flat_between(p, at))
		return d
	# The building's own doorway: a wall past it to the east, so the charge goes there.
	var real: Dictionary = make.call(Vector3(0.0, 0.1, -4.0))
	var real_spot := SquadAI.door_charge_spot(real, world.direct_space_state)
	var real_first: Vector3 = real.stack[0]
	print("    over the doorway itself (where the indoor push used to look): indoors %s; over its charge: %s"
		% [Throwables.indoors(world, Vector3(0.0, 0.1, -4.0) + Vector3.UP * 1.25), Throwables.indoors(world, (real_spot.at as Vector3) + Vector3.UP * 0.25)])
	Squad.stand_off(real, world)
	var real_off := SquadAI._flat_between(real.stack[0], real_first)
	check(((real_spot.at as Vector3) - Vector3(0.0, 0.1, -4.0)).dot(west) < -1.5 and not bool(real.get("charge_indoors", true))
		and absf(real_off - Squad.CHARGE_STANDOFF_M) < 0.05,
		"the doorway: its charge goes on the wall past it (at %s), no roof over it (the lintel isn't one: %s), and the stack stands the usual %.1f m off (%.2f m)"
		% [(real_spot.at as Vector3).snapped(Vector3.ONE * 0.1), real.get("charge_indoors"), Squad.CHARGE_STANDOFF_M, real_off])
	# A doorway by the corner: no wall past it, so the charge goes on the stack's side.
	var corner: Dictionary = make.call(Vector3(4.0, 0.1, -4.0))
	var spot := SquadAI.door_charge_spot(corner, world.direct_space_state)
	var at: Vector3 = spot.at
	Squad.stand_off(corner, world)
	var far_side := nearest.call(real, real_spot.at) as float
	var own_side := nearest.call(corner, at) as float
	check((at - Vector3(4.0, 0.1, -4.0)).dot(west) > 1.5 and absf(at.z + 4.0) < 0.1,
		"by the corner its charge goes on the stack's own side of the doorway (at %s)" % [at.snapped(Vector3.ONE * 0.1)])
	check(own_side > Squad.BLAST_SAFE_M + 0.9 and own_side >= SquadTactics.STACK_FIRST_M + Squad.CHARGE_STANDOFF_M - 0.05,
		"the stack stands off from it there too: its nearest man %.1f m from it (past its %.1f m reach; %.1f m from a charge past the doorway)"
		% [own_side, Squad.BLAST_SAFE_M, far_side])


# --- A breach under a roof ------------------------------------------------------------------

## F-396 (Captain, 2026-11-02: yes): under a roof (something solid within 4 m over the charge)
## the blast doubles and its face side reaches 5 m (Throwables._frag), past the stack's outdoor
## stand-off (4.1 m). With a slab over the main building's west wall at the spot (a porch roof),
## ordered to breach there: the stack stands off past Squad.BLAST_SAFE_INDOOR_M, and nobody of
## the team is in the blast, or hurt, when it goes.
func _test_roof_stand_off() -> void:
	print("Breach and clear under a roof: the stack stands off past the charge's indoor reach")
	var squad := level.squad_for(&"friendly")
	await _heal_squad()
	var mates := _team(4)
	if mates.size() < 4:
		check(false, "four fit squadmates (%d)" % mates.size())
		return
	var roof := StaticBody3D.new()
	roof.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 0.2, 2.0)
	shape.shape = box
	roof.add_child(shape)
	level.add_child(roof)
	roof.global_position = Vector3(WEST_WALL.x - 1.0, 3.0, WEST_WALL.z)  # (over the wall's face too, where the charge sits)
	await _physics_frames(2)
	_strip_charges(mates)
	while player.inventory.remove_one(Charges.ITEM):
		pass
	Roles.give(mates[0].body.inventory, Charges.ITEM, 1)
	_place(player, Vector3(-12, 0.1, -16))
	for i in mates.size():
		_place(mates[i].body, Vector3(-9.5, 0.1, -11.0 + i * 0.9))
	await _seconds(0.5)
	var names := PackedStringArray(mates.map(func(ai: SquadAI) -> String: return String(ai.body.name)))
	var why := squad.order_command(player, "breach_clear", WEST_WALL, names)
	var op: Dictionary = mates[0].ordered.get("op", {}) if why == "" else {}
	check(why == "" and not op.is_empty() and bool(op.get("wall", false)) and String(op.get("door", "")) == "charge" and bool(op.get("charge_indoors", false)),
		"ordered under the roof: they stack on the west wall, the charge's spot is under a roof (%s)" % why)
	if op.is_empty():
		roof.queue_free()
		await _heal_squad()
		return
	var at: Vector3 = op.charge_spot.at
	var nearest_spot := INF
	for p: Vector3 in op.stack:
		nearest_spot = minf(nearest_spot, SquadAI._flat_between(p, at))
	check(nearest_spot > Squad.BLAST_SAFE_INDOOR_M,
		"the stack's places are past its indoor reach (nearest %.1f m from it, past %.1f m; %.1f m in the open)"
		% [nearest_spot, Squad.BLAST_SAFE_INDOOR_M, Squad.BLAST_SAFE_M])
	var friends: Array = level.ai.get_children().filter(func(s: Node) -> bool: return s is Soldier and (s as Soldier).faction == &"friendly" and not s.is_queued_for_deletion())
	friends.append(player)
	var was := {}
	for s: Soldier in friends:
		was[s] = s.vitals.last_cause
	var charges := Charges.of(level)
	var at_blast := {"d": {}, "indoors": false}
	var blown := await _wait_until(func() -> bool:
		var id := String(op.get("charge_id", ""))
		if id != "" and charges.records.has(id):
			for c: Dictionary in charges.burning():
				if c.id == id:
					at_blast.indoors = bool(c.indoors)
			for ai: SquadAI in mates:
				if is_instance_valid(ai):
					at_blast.d[String(ai.body.name)] = SquadAI._flat_between(ai.body.global_position, at)
			return false
		return id != "", 70.0)
	await _physics_frames(2)
	var nearest := INF
	for k: String in at_blast.d:
		nearest = minf(nearest, float(at_blast.d[k]))
	var blasted := friends.filter(func(s: Soldier) -> bool:
		return is_instance_valid(s) and (s.vitals.deaf_left() > 0.0 or not s.vitals.is_up() or (not is_same(s.vitals.last_cause, was[s]) and String(s.vitals.last_cause.get("cause", "")) == "blast")))
	check(blown and at_blast.indoors and nearest > Squad.BLAST_SAFE_INDOOR_M and blasted.is_empty(),
		"he sets it, they hold off, it goes off (under the roof: %s) with nobody in its blast (nearest %.1f m, past %.1f m; hurt: %s)"
		% [at_blast.indoors, nearest, Squad.BLAST_SAFE_INDOOR_M, ", ".join(blasted.map(func(s: Soldier) -> String: return String(s.name)))])
	roof.queue_free()
	await _heal_squad()


func _stage_at(op: Dictionary, stage: String) -> float:
	for s: Dictionary in op.get("stages", []):
		if s.name == stage:
			return float(s.at)
	return -1.0


func _end_client(pid: int, log_path: String) -> void:
	await _wait_until(func() -> bool: return _client_failures >= 0, 60.0)
	for line in _client_lines:
		print("    client: %s" % line)
	check(_client_failures == 0, "the client saw it all (%d client failures)" % _client_failures)
	if pid > 0:
		await _wait_until(func() -> bool: return not OS.is_process_running(pid), 10.0)
		if OS.is_process_running(pid):
			OS.kill(pid)
	var errors := PackedStringArray()
	if FileAccess.file_exists(log_path):
		for line in FileAccess.get_file_as_string(log_path).split("\n"):
			if line.contains("SCRIPT ERROR"):
				errors.append(line)
	for line in errors:
		print("    client: %s" % line)
	check(FileAccess.file_exists(log_path) and errors.is_empty(), "no script errors in the client's log (%d)" % errors.size())


@rpc("any_peer", "call_remote", "reliable")
func _ask_expect() -> void:
	if multiplayer.is_server() and not expect.is_empty():
		_expect.rpc_id(multiplayer.get_remote_sender_id(), expect)


@rpc("authority", "call_remote", "reliable")
func _expect(data: Dictionary) -> void:
	expect = data


@rpc("any_peer", "call_remote", "reliable")
func _ready_to_watch() -> void:
	_client_ready = true


@rpc("authority", "call_remote", "reliable")
func _team_names(names: PackedStringArray) -> void:
	expect["names"] = names


@rpc("authority", "call_remote", "reliable")
func _done_watching() -> void:
	expect["done"] = true


@rpc("any_peer", "call_remote", "reliable")
func _client_report(count: int, lines: PackedStringArray) -> void:
	_client_lines = lines
	_client_failures = count


func _run_client() -> void:
	get_tree().create_timer(400.0).timeout.connect(func() -> void: get_tree().quit(99))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	if Net.session_ended.is_connected(Callable(main, &"_on_session_ended")):
		Net.session_ended.disconnect(Callable(main, &"_on_session_ended"))
	await get_tree().process_frame
	var lines := PackedStringArray()
	var note := func(ok: bool, what: String) -> void:
		lines.append("[%s] %s" % ["ok" if ok else "FAIL", what])
		if not ok:
			failures += 1
	await _wait_until(func() -> bool: return Sfx.is_prebuilt(), 60.0)
	await _join_host("127.0.0.1", 90.0)
	var asked_until := Time.get_ticks_msec() + 90000
	while expect.is_empty() and Time.get_ticks_msec() < asked_until:
		if 1 in multiplayer.get_peers():
			_ask_expect.rpc_id(1)
		await _wait_until(func() -> bool: return not expect.is_empty(), 3.0)
	var lvl := CompoundLevel.current(self)
	var charges := Charges.of(lvl) if lvl else null
	if charges == null or expect.is_empty():
		note.call(false, "joined and got the host's expectations")
	else:
		await _wait_until(func() -> bool: return lvl.voxel_world.is_built(), 30.0)
		_ready_to_watch.rpc_id(1)
		var seen := {"charge": "", "gone": false}
		await _wait_until(func() -> bool:
			if seen.charge == "" and not charges.records.is_empty():
				seen.charge = String(charges.records.keys()[0])
			if seen.charge != "" and not charges.records.has(seen.charge):
				seen.gone = true
			return bool(seen.gone) or expect.has("done"), 200.0)
		note.call(seen.charge != "", "the charge set on the wall shows here (%s)" % seen.charge)
		note.call(bool(seen.gone), "and goes off here too")
		var spot: Vector3 = expect.spot
		var n: Vector3 = expect.normal
		var hole := func() -> bool:
			for h: float in [0.3, 1.0, 1.9]:
				for along: float in [-0.5, 0.0, 0.5]:
					for into: float in [0.05, 0.15, 0.25]:
						if lvl.voxel_world.material_at(Vector3(spot.x, h, spot.z + along) - n * into) != VoxelWorld.Mat.EMPTY:
							return false
			return true
		var edge := Vector3(spot.x, 1.0, spot.z + Charges.BREACH_W_M * 0.5 + 0.6) - n * 0.15
		var holed := await _wait_until(hole, 10.0)
		note.call(holed and lvl.voxel_world.material_at(edge) != VoxelWorld.Mat.EMPTY,
			"the hole is open here, through the wall from the floor up (the wall beside it still stands: %s)" % [lvl.voxel_world.material_at(edge)])
		await _wait_until(func() -> bool: return expect.has("names"), 30.0)
		var names: PackedStringArray = expect.get("names", PackedStringArray())
		var inside := func() -> int:
			var count := 0
			for nm in names:
				var s := lvl.ai.get_node_or_null(NodePath(nm)) as Node3D
				if s and s.global_position.x > -5.0 and s.global_position.x < 5.0 and s.global_position.z > -12.0 and s.global_position.z < -4.0:
					count += 1
			return count
		await _wait_until(func() -> bool: return expect.has("done") and inside.call() == names.size(), 120.0)
		note.call(not names.is_empty() and inside.call() == names.size(), "the team is inside the building here (%d of %d)" % [inside.call(), names.size()])
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


# --- Helpers -------------------------------------------------------------------------------

## The first `count` fit friendly squadmates' brains.
func _team(count: int) -> Array[SquadAI]:
	var out: Array[SquadAI] = []
	for n in level.ai.get_children():
		var s := n as Soldier
		var ai := SquadAI.of(s) if s and not s.is_queued_for_deletion() else null
		if ai and s.faction == &"friendly" and s.vitals.is_up() and s.carrying == null and not is_instance_valid(s.carried_by) \
				and ai.care == SquadAI.Care.NONE and out.size() < count:
			out.append(ai)
	return out


## Takes every breaching charge off `mates`; returns how many each had.
func _strip_charges(mates: Array[SquadAI]) -> Dictionary:
	var had := {}
	for ai: SquadAI in mates:
		var n := 0
		while ai.body.inventory.remove_one(Charges.ITEM):
			n += 1
		had[ai] = n
	return had


## Takes every medical item off `s` (he can't treat himself: he calls for a medic).
func _strip_medical(s: Soldier) -> void:
	for container: StringName in s.inventory.containers:
		for entry: Dictionary in (s.inventory.containers[container] as Array).duplicate():
			var id := StringName(String(entry.get("id", "")))
			if ItemDB.has_item(id) and ItemDB.get_item(id).type == "medical":
				while s.inventory.remove_one(id):
					pass


func _heal_squad() -> void:
	for n in level.ai.get_children():
		var mate := n as Soldier
		if mate and mate.faction == &"friendly" and not mate.vitals.is_dead() and not mate.is_queued_for_deletion():
			mate.vitals.server_reset_health()
			var ai := SquadAI.of(mate)
			if ai:
				ai._end_care()
				ai.give_tactic({})
	await _seconds(1.0)


func _place(s: Soldier, pos: Vector3) -> void:
	s.global_position = pos
	s.velocity = Vector3.ZERO


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _finish() -> void:
	GameState.delete_save()
	print("BREACH TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	Net.leave()
	get_tree().quit(failures)


func _wait_until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return cond.call()


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
