extends Node
## Headless checks of rounds' flight paths and their tracers (Captain, 2026-10-21: "tracers flight
## paths and ballistic arcs ... theyre still wonky depending on terrain"). A seeded hilly terrain
## (ZoneTerrain, its height-field collision) under the compound level: rounds fired at the ground
## 50, 300 and 800 m out, onto slopes up, down and across, and down a long hillside, then into the
## compound's voxels. For each: the round lands on the terrain where the height field says the
## ground is, its path never passes through a hill, the path every peer rebuilds from the shot
## (Ballistics.flight_path) is the path it flew point for point, and the tracer runs along that
## path from the muzzle and ends exactly at the impact. Then a player's real shot (the fire RPC):
## its tracer leaves the muzzle, not the eye, also with the muzzle in the ground; and a peer that
## draws the shooter a moment behind starts the streak at the gun it sees and joins the real path.
## Mortar and artillery shells (ShellArc; Captain, 2026-10-21: "i wanna see the mortar streak down
## or up depending on weather conditions"): a shell flies the real arc from the tube to the burst
## in its time of flight, and the weather's wind bends it, more in a storm than on a clear day.
## Client vs host over ENet is the net suite's (_check_tracer_path); the mortar team's and the fire
## missions' shells are the vehicles and firesupport suites'.
##   <voxel godot exe> --headless --path . res://tests/ballistics_test.tscn
## Exits with the number of failures.

## The test terrain, well below the compound (its own collision, out of everything else's way).
const TERRAIN_AT := Vector3(0.0, -3000.0, 0.0)
const TERRAIN_DEF := {"seed": 4242, "size_m": 2048.0, "terrain": "temperate", "relief_m": 70.0}
## How close a rebuilt path or a tracer must be to the path flown (m), and an impact to the ground.
const SAME_M := 0.001
const ON_GROUND_M := 0.02

var failures := 0
var level: CompoundLevel
var player: Soldier
var terrain: ZoneTerrain
var _shooter: StaticBody3D


func _ready() -> void:
	GameState.zone_id = "test_ballistics" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	Soldier.respawn_delay_s = 0.0
	Soldier.spawn_protect_s = 0.0
	CompoundLevel.spawn_ai = false
	GameState.delete_save()
	_test_path_math()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.players.get_node_or_null(^"1") == null or not level.voxel_world.is_built():
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)
	Ballistics.record_path = true
	terrain = ZoneTerrain.new()
	terrain.generate(TERRAIN_DEF, [])
	level.add_child(terrain)
	terrain.position = TERRAIN_AT
	terrain.set_process(false)  # no meshes: collision is all a round meets
	terrain.build_collision()
	_shooter = StaticBody3D.new()
	_shooter.collision_layer = 0
	level.add_child(_shooter)
	await _frames(5)
	await _test_terrain_shots()
	await _test_voxel_shot()
	await _test_player_shot()
	await _test_muzzle_in_ground()
	_test_seen_lead()
	await _test_shells()
	print("BALLISTICS TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Pure: a round flown with no ground rises off the zeroed barrel and falls; flight_path from its
## launch, cut anywhere along it, ends at that point, and its steps are the ones _trace flies.
func _test_path_math() -> void:
	print("Flight path math")
	var m4 := ItemDB.get_item(&"m4a1")
	var launch := Ballistics.launch_velocity(Vector3.FORWARD, m4)
	check(launch.y > 0.0 and is_equal_approx(launch.length(), Ballistics.muzzle_velocity(m4)),
		"the round leaves zeroed (a hair up off the line of sight) at its muzzle velocity (%.0f m/s)" % launch.length())
	var full := Ballistics.flight_path(Vector3.ZERO, launch, Ballistics.round_id(m4), Vector3(0, -1e6, -1e6))
	var lowest := 0.0
	for i in full.size() - 1:  # (the last point is the far-off end it was given)
		lowest = minf(lowest, full[i].y)
	check(full.size() > 20 and lowest < -5.0, "over its range it drops (%d steps, %.1f m below the bore line at the end)" % [full.size(), -lowest])
	var cut := full[6].lerp(full[7], 0.4)
	var to_cut := Ballistics.flight_path(Vector3.ZERO, launch, Ballistics.round_id(m4), cut)
	check(to_cut.size() == 8 and to_cut[7] == cut and to_cut[6].distance_to(full[6]) < SAME_M,
		"cut on a step, it's the same steps up to there and ends exactly at the cut (%d points)" % to_cut.size())
	var none := Ballistics.flight_path(Vector3.ZERO, Vector3.ZERO, &"", Vector3(0, 0, -30))
	check(none.size() == 2, "no launch: a straight streak")


# --- On the terrain ---------------------------------------------------------------------------------

## Rounds at the ground: [label, weapon, range m, filter on (eye, target, slope deg)].
func _test_terrain_shots() -> void:
	print("Rounds onto the terrain")
	var flat_ok := func(_eye: Vector3, _to: Vector3, _slope: float) -> bool: return true
	var cases := [
		["50 m", &"m4a1", 50.0, flat_ok],
		["300 m", &"m4a1", 300.0, flat_ok],
		["800 m", &"m110", 800.0, flat_ok],
		["up a slope", &"m4a1", 120.0, func(eye: Vector3, to: Vector3, slope: float) -> bool: return slope > 12.0 and to.y > eye.y + 6.0],
		["down a slope", &"m4a1", 120.0, func(eye: Vector3, to: Vector3, slope: float) -> bool: return slope > 12.0 and to.y < eye.y - 10.0],
		["across a slope", &"m4a1", 150.0, func(eye: Vector3, to: Vector3, slope: float) -> bool: return slope > 12.0 and absf(to.y - eye.y) < 3.0],
		["up a hillside 700 m out", &"m110", 700.0, func(eye: Vector3, to: Vector3, slope: float) -> bool: return slope > 8.0 and to.y > eye.y + 8.0],
	]
	for c: Array in cases:
		var setup := _find_shot(float(c[2]), c[3])
		check(not setup.is_empty(), "%s: a clear line to the ground found on the test terrain" % c[0])
		if setup.is_empty():
			continue
		await _shoot_ground(String(c[0]), ItemDB.get_item(c[1]), setup.eye, setup.target, float(c[2]))


## A shooter's eye and a ground point `range_m` away (horizontally) in plain sight of it, the
## ground there passing `ok`; {} if none.
func _find_shot(range_m: float, ok: Callable) -> Dictionary:
	var space := _shooter.get_world_3d().direct_space_state
	for sx in range(-600, 601, 150):
		for sz in range(-600, 601, 150):
			var eye := _ground(float(sx), float(sz)) + Vector3.UP * 1.6
			for heading in range(0, 360, 15):
				var flat := Vector2(float(sx), float(sz)) + Vector2.from_angle(deg_to_rad(heading)) * range_m
				if absf(flat.x) > 800.0 or absf(flat.y) > 800.0:
					continue
				var target := _ground(flat.x, flat.y)
				var n := terrain.normal_at(flat.x, flat.y)
				var slope := rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))
				if not ok.call(eye, target, slope):
					continue
				if (eye - target).normalized().dot(n) < 0.15:
					continue  # grazing: a hair high or low lands metres off
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, target + (eye - target).normalized() * 0.3, 1))
				if hit.is_empty():
					return {"eye": eye, "target": target}
	return {}


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, terrain.height_at(x, z), z) + TERRAIN_AT


## Fires `weapon` from `eye` at `target` (held over by its drop, as the AI holds: G-27) from the
## muzzle, then checks the impact, the path and the tracer.
func _shoot_ground(label: String, weapon: ItemData, eye: Vector3, target: Vector3, range_m: float) -> void:
	var aim := (target + Vector3.UP * Ballistics.drop_m(weapon, eye.distance_to(target)) - eye).normalized()
	var muzzle := Soldier.muzzle_point(eye, aim, false, false, true)
	_shooter.global_position = eye
	var result := Ballistics.fire(_shooter, muzzle, aim, weapon)
	var at: Vector3 = result.position
	var ground := _ground(at.x, at.z)
	var out := Vector2(at.x - eye.x, at.z - eye.z).length()
	check(String(result.result) == "world" and absf(at.y - ground.y) < ON_GROUND_M and absf(out - range_m) < maxf(range_m * 0.1, 5.0),
		"%s: lands on the ground %.0f m out (%s; %.3f m off the height field, %.1f m from the aim point)" % [label, out, result.result, at.y - ground.y, at.distance_to(target)])
	_check_path_and_tracer(label, result, muzzle, weapon, true)


## The path `result` flew from `muzzle`: rebuilt from the shot it is the same, point for point;
## (on the terrain) it passes through no hill before the impact; the tracer drawn for it runs
## along it from the muzzle and ends exactly at the impact.
func _check_path_and_tracer(label: String, result: Dictionary, muzzle: Vector3, weapon: ItemData, clear_of_ground: bool) -> void:
	var flown := Ballistics.last_path
	var end: Vector3 = result.position
	var rebuilt := Ballistics.flight_path(muzzle, result.launch, Ballistics.round_id(weapon), end)
	check(_worst(rebuilt, flown) < SAME_M, "%s: the path every peer rebuilds is the one it flew (%d points)" % [label, flown.size()])
	if clear_of_ground:
		var space := _shooter.get_world_3d().direct_space_state
		var through := false
		for i in flown.size() - 2:
			through = through or not space.intersect_ray(PhysicsRayQueryParameters3D.create(flown[i], flown[i + 1], 1)).is_empty()
		check(not through, "%s: the path passes through no hill before it lands" % label)
	# The old straight streak: how far off the round's real path it was.
	var off := 0.0
	for p in flown:
		off = maxf(off, _off_segment(p, muzzle, end))
	level.show_tracer(muzzle, result.launch, Ballistics.round_id(weapon), end, false, Tracer.Kind.RED, false)
	var t := _latest_tracer()
	check(t != null and _worst(Tracer.last_path, flown) < SAME_M and Tracer.last_path[0].distance_to(muzzle) < SAME_M,
		"%s: the tracer runs along it from the muzzle (a straight one was up to %.2f m off it)" % [label, off])
	if t == null:
		return
	var mid_off := 0.0
	var s := 0.0
	while s < t._length:
		mid_off = maxf(mid_off, _off_path(t.point_at(s), flown))
		s += 1.0
	t._set_drawn(t._length)
	var head: Vector3 = t.streak()[0]
	var tail: Vector3 = t.streak()[1]
	check(head.distance_to(end) < SAME_M and _off_path(tail, flown) < 0.01 and mid_off < SAME_M,
		"%s: the streak stays on the path all the way (%.4f m) and its head ends at the impact (%.4f m)" % [label, mid_off, head.distance_to(end)])
	t.queue_free()


func _latest_tracer() -> Tracer:
	var found: Tracer = null
	for n in level.get_children():
		if n is Tracer and not n.is_queued_for_deletion():
			found = n
	return found


## The worst distance between matching points of two paths (INF if they differ in length).
static func _worst(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size() or a.is_empty():
		return INF
	var w := 0.0
	for i in a.size():
		w = maxf(w, a[i].distance_to(b[i]))
	return w


static func _off_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	return p.distance_to(Geometry3D.get_closest_point_to_segment(p, a, b))


static func _off_path(p: Vector3, path: PackedVector3Array) -> float:
	var best := INF
	for i in path.size() - 1:
		best = minf(best, _off_segment(p, path[i], path[i + 1]))
	return best


# --- Voxels, and a player's real shot -------------------------------------------------------------

## A round at a slant into the compound's voxels: the path and the tracer the same, the tracer
## through the spot it met them.
func _test_voxel_shot() -> void:
	print("A round into the voxels")
	var space := player.get_world_3d().direct_space_state
	var eye := player.camera.global_position
	var met := {}
	for heading in range(0, 360, 10):
		var dir := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(heading)) + Vector3.DOWN * 0.05
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + dir.normalized() * 80.0, 1, [player.get_rid()]))
		if not hit.is_empty() and VoxelWorld.find_on(hit.collider) != null and absf(hit.normal.dot(dir.normalized())) < 0.9:
			met = hit
			break
	check(not met.is_empty(), "a voxel wall in sight, met at a slant")
	if met.is_empty():
		return
	var aim: Vector3 = (met.position - eye).normalized()
	var muzzle := Soldier.muzzle_point(eye, aim, false, false, true)
	_shooter.global_position = eye
	var m4 := ItemDB.get_item(&"m4a1")
	var result := Ballistics.fire(_shooter, muzzle, aim, m4)
	check(String(result.result) == "world", "it hits the voxels (%s)" % result.result)
	_check_path_and_tracer("voxels", result, muzzle, m4, false)
	check(_off_path(met.position, Tracer.last_path) < 0.15, "the tracer passes where the round met the wall (%.3f m)" % _off_path(met.position, Tracer.last_path))


func _arm() -> void:
	var inv := player.inventory
	inv.slots[&"primary"] = &""
	inv.take(&"m4a1")
	inv.take(&"mag_556", 2)
	player._server_busy_until = 0.0
	player._server_next_shot = 0.0


## The fire RPC itself: the tracer every peer draws leaves the muzzle (not the eye) and follows
## the path the host's round flew.
func _test_player_shot() -> void:
	print("A player's shot")
	_arm()
	var eye := player.camera.global_position
	var aim := (-player.global_basis.z + Vector3.DOWN * 0.08).normalized()
	player._server_fire.rpc_id(1, eye, aim, &"primary")
	await _frames(2)
	var muzzle := Soldier.muzzle_point(eye, aim, false, player.left_handed, player.is_aiming)
	var drawn := Tracer.last_path
	check(drawn.size() >= 2 and drawn[0].distance_to(muzzle) < SAME_M and drawn[0].distance_to(eye) > 0.3,
		"the tracer leaves the muzzle, %.2f m from the eye" % (drawn[0].distance_to(eye) if drawn.size() > 0 else 0.0))
	check(_worst(drawn, Ballistics.last_path) < SAME_M, "and runs along the path the round flew (%d points) to %s" % [drawn.size(), player.last_shot_to])


## A muzzle in the ground (prone on a rise, or a wall leaned on): the round leaves just short of
## it, not from the eye, and doesn't go through.
func _test_muzzle_in_ground() -> void:
	print("Muzzle in the ground")
	_arm()
	await _frames(int(ceil(60.0 / 800.0 * 60.0)) + 2)
	var eye := player.camera.global_position
	var aim := -player.global_basis.z
	var bank := StaticBody3D.new()  # a rise right in front of the face
	bank.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	shape.shape = box
	bank.add_child(shape)
	level.add_child(bank)
	var face := eye + aim * 0.25
	bank.global_transform = Transform3D(Basis.looking_at(aim), face + aim * 1.0)
	await _frames(3)
	player._server_fire.rpc_id(1, eye, aim, &"primary")
	await _frames(2)
	var drawn := Tracer.last_path
	var start := drawn[0] if drawn.size() > 0 else eye
	check(drawn.size() >= 2 and start.distance_to(eye) > 0.2 and (start - face).dot(aim) < 0.0 and (start - face).dot(aim) > -0.05,
		"the round leaves just short of the bank (%.3f m before it), not from the eye (%.2f m from it)" % [-(start - face).dot(aim), start.distance_to(eye)])
	bank.queue_free()


## A peer that draws the shooter a moment behind (Soldier._smooth_remote): the streak starts at the
## gun it sees and is on the real path by Tracer.LEAD_BLEND_M.
func _test_seen_lead() -> void:
	print("A shooter drawn behind")
	var eye := player.camera.global_position
	var aim := -player.global_basis.z
	var muzzle := Soldier.muzzle_point(eye, aim, false, false, true)
	var lag := Vector3(0.6, 0.0, 0.0)
	player.model.net_offset = Transform3D(Basis.IDENTITY, player.global_basis.inverse() * lag)
	var launch := Ballistics.launch_velocity(aim, ItemDB.get_item(&"m4a1"))
	var end := muzzle + aim * 60.0
	level.show_tracer(muzzle, launch, &"556_m855", end, false, Tracer.Kind.RED)
	player.model.net_offset = Transform3D.IDENTITY
	var t := _latest_tracer()
	var path := Ballistics.flight_path(muzzle, launch, &"556_m855", end)
	check(t != null and t.point_at(0.0).distance_to(muzzle + lag) < SAME_M and _off_path(t.point_at(Tracer.LEAD_BLEND_M), path) < SAME_M
		and t.point_at(t._length).distance_to(end) < SAME_M,
		"it starts at the gun drawn %.1f m behind, joins the real path by %.0f m and ends at the impact" % [lag.length(), Tracer.LEAD_BLEND_M])
	if t:
		t.queue_free()


# --- Mortar and artillery shells -----------------------------------------------------------------

## A shell over 1 km in 25 s, in each weather: up off the tube, high over, down exactly onto the
## burst; the wind leans the arc by its push (ShellArc.WIND_PUSH) times T^2/8 at the top.
func _test_shells() -> void:
	print("Mortar shells in the weather")
	var sky := DayNight.current()
	check(sky != null, "the level has its day and weather")
	if sky == null:
		return
	var was := [sky.hour, sky.weather]
	var start := Vector3(0, 1.1, 0)
	var end := Vector3(600, 0.1, -800)
	var flight := 25.0
	var leans := {}
	for w: String in ["fog", "clear", "storm"]:
		sky.server_set(sky.hour, w)
		var wind := DayNight.wind()
		level.server_show_shell(start, end, flight)
		await _frames(1)
		var arc := ShellArc.last
		var shell := _latest_shell()
		var calm := ShellArc.launch_for(start, end, flight, Vector3.ZERO)
		var mid := ShellArc.point_at(start, arc.launch, arc.accel, flight * 0.5)
		var calm_mid := ShellArc.point_at(start, calm, Vector3.ZERO, flight * 0.5)
		leans[w] = mid.distance_to(calm_mid)
		var want := (arc.accel as Vector3).length() * flight * flight / 8.0
		check(shell != null and shell.at(0.0).distance_to(start) < 0.01 and shell.at(flight).distance_to(end) < 0.01 and (arc.launch as Vector3).y > 0.0
			and mid.y > start.y + 500.0 and absf(leans[w] - want) < 0.05 and is_equal_approx(wind.length(), float(DayNight.WEATHER[w].wind_mps)),
			"%s (wind %.0f m/s): up off the tube, %.0f m high at the top, down exactly on the burst, leaning %.1f m" % [w, wind.length(), mid.y, leans[w]])
		if shell:
			shell.queue_free()
	check(float(leans.storm) > float(leans.clear) * 3.0 and float(leans.clear) > float(leans.fog),
		"a storm bends the arc far more than a clear day, a still fog least (%.1f / %.1f / %.1f m)" % [leans.storm, leans.clear, leans.fog])
	sky.server_set(float(was[0]), String(was[1]))
	# Indirect fire (Captain, 2026-10-21: "they arc high into the sky and come down"): a mortar team's
	# shell leaves its tube steeper than 45 degrees at its shortest and longest range, and goes far
	# higher than it goes out at the short end; the called 81 mm section fires high angle too.
	var steep := true
	var lines: Array[String] = []
	for kit: String in ["mortar_m224", "mortar_2b14"]:
		var m: Dictionary = StaticWeapons.KITS[kit].mortar
		for d: float in [float(m.min_m), float(m.max_m)]:
			var t := lerpf(MortarFire.FLIGHT_S.x, MortarFire.FLIGHT_S.y, inverse_lerp(float(m.min_m), float(m.max_m), d))
			var v := ShellArc.launch_for(Vector3.ZERO, Vector3(d, 0, 0), t, Vector3.ZERO)
			var angle := rad_to_deg(atan2(v.y, v.x))
			var apex := v.y * v.y / (2.0 * -Ballistics.GRAVITY.y)
			steep = steep and angle > 45.0 and (d > 1000.0 or apex > d)
			lines.append("%s %.0f m: %.0f deg, %.0f m up" % [kit.trim_prefix("mortar_"), d, angle, apex])
	var section := FireMission.unit("mortar")
	check(steep and float(section.elevation_mils) / 6400.0 * 360.0 > 45.0,
		"mortars are indirect fire: high into the sky and down (%s; the 81 mm section at %.0f deg)" % [", ".join(lines), float(section.elevation_mils) / 6400.0 * 360.0])


func _latest_shell() -> ShellArc:
	var found: ShellArc = null
	for n in level.get_children():
		if n is ShellArc and not n.is_queued_for_deletion():
			found = n
	return found
