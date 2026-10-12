class_name LauncherProjectile
extends Node3D
## A rocket or missile in flight (wave 5, V2), on every peer under the level's Launchers node.
## The host flies it for real (server_step: motor, gravity, guidance, what it meets) and sends
## its position now and then; every other peer flies the same motor and gravity between those
## (integrate) so it looks smooth, and snaps to the host's track (Launchers._client_track).
##
## Flight by the warhead's data (Warheads.data): it leaves the launcher at speed_mps, a rocket
## motor lights delay_s later and takes it to to_mps over burn_s (the RPG-7's sustainer), and
## unguided rounds fall under gravity. Guided ones:
## - "javelin": flies at a locked vehicle. Top attack (the default) climbs to a point
##   top_apex_m up (less at short range) short of the target, then dives onto the roof at
##   about 45 degrees; direct attack climbs only to direct_apex_m (a few metres at short
##   range) and comes in flat. It turns at up to turn_dps (DIVE_TURN_MULT times that diving).
## - "nlaw": predicted line of sight. It flies the straight line the gunner tracked (led for a
##   moving target), ota_height_m above it in overfly top attack, and a sensor looking
##   sensor_m down fires the warhead when it passes over a vehicle. Direct attack flies the
##   line itself.

## Proposed: a Javelin's climb ends at its apex this many apex heights short of the target
## (flat): top attack dives at about 45 degrees, direct attack comes in flat.
const TOP_DIVE_RATIO := 1.0
const DIRECT_DIVE_RATIO := 6.0
## Proposed: the apex's share of the range at short range, and the lowest it goes.
const MIN_APEX_M := 20.0
const APEX_RANGE_SHARE := 0.35
const DIRECT_APEX_SHARE := 0.06
const DIRECT_MIN_APEX_M := 3.0
## Proposed: diving, it turns this much harder.
const DIVE_TURN_MULT := 2.5
## The climb waypoint counts as reached within this (m).
const WAYPOINT_REACH_M := 6.0
## Proposed: an NLAW climbs to its overfly height over this much of its flight.
const NLAW_RISE_M := 15.0
## Sensor samples along each step (an NLAW at 200 m/s covers 3 m a physics frame).
const SENSOR_STEP_M := 0.5
const GRAVITY := 9.8

static var _drops := {}  # drop_at's answers: "warhead|range" -> {"drop", "time"}

var id := 0
var warhead: StringName
var data: Dictionary = {}
## Javelin: "top" or "direct"; NLAW: "ota" or "da"; "" for unguided rounds.
var mode := ""
var velocity := Vector3.ZERO
## Seconds in flight and metres flown.
var age := 0.0
var travelled := 0.0
## Host only: who fired it (Harm, and never hits them), the vehicle it was locked on (Javelin)
## or led for (NLAW), colliders it ignores, and the guidance state.
var shooter: Node
var target: Node3D
var exclude: Array[RID] = []
var launch_pos := Vector3.ZERO
var phase := "climb"
var apex_y := 0.0
var waypoint := Vector3.ZERO  # Javelin: the top of its climb
var max_height := 0.0  # highest it got above its launch point (tests)
var line_from := Vector3.ZERO  # NLAW: the predicted line of sight
var line_dir := Vector3.FORWARD
var line_s := 0.0
var _speed := 0.0
var _last_aim := Vector3.ZERO
var _visual: Node3D
var _flame: Node3D
var _trail_cd := 0.0


## Every peer: sets it up from a launch record (Launchers._client_launch).
func setup(rec: Dictionary) -> void:
	id = int(rec.id)
	warhead = StringName(rec.w)
	data = Warheads.data(warhead)
	mode = String(rec.get("mode", ""))
	velocity = rec.vel
	age = float(rec.get("age", 0.0))
	travelled = float(rec.get("flown", 0.0))
	_speed = velocity.length()
	name = "Round%d" % id
	_build_visual()


func _ready() -> void:
	look_along(velocity)


## Every peer: the motor's speed `age` seconds into the flight (0: unpowered, keep what it has).
func motor_target(at_age: float) -> float:
	var motor: Dictionary = data.get("motor", {})
	if motor.is_empty():
		return 0.0
	var start := float(motor.get("delay_s", 0.0))
	if at_age < start:
		return 0.0
	var burn := maxf(float(motor.get("burn_s", 0.1)), 0.01)
	var from := float(data.get("speed_mps", 100.0))
	return lerpf(from, float(motor.get("to_mps", from)), clampf((at_age - start) / burn, 0.0, 1.0))


func motor_burning() -> bool:
	var motor: Dictionary = data.get("motor", {})
	if motor.is_empty():
		return false
	var start := float(motor.get("delay_s", 0.0))
	return age >= start and age <= start + float(motor.get("burn_s", 0.0)) + (30.0 if guided() else 0.0)


func guided() -> bool:
	return String(data.get("guidance", "")) != ""


## How far below the line it was fired along an unguided round of warhead `w` has dropped
## after `range_m` metres (m), and how long it took (s): {"drop", "time"}. Sights mark it
## (LauncherSight) and the AI aims over it (LauncherAI). Guided rounds don't drop.
static func drop_at(w: StringName, range_m: float) -> Dictionary:
	var key := "%s|%d" % [w, roundi(range_m)]
	if _drops.has(key):
		return _drops[key]
	var d := Warheads.data(w)
	if d.is_empty() or String(d.get("guidance", "")) != "":
		return {"drop": 0.0, "time": range_m / maxf(float(d.get("cruise_mps", 150.0)), 1.0)}
	var probe := LauncherProjectile.new()
	probe.data = d
	probe.velocity = Vector3.FORWARD * float(d.get("speed_mps", 100.0))
	var pos := Vector3.ZERO
	var dt := 1.0 / 60.0
	while -pos.z < range_m and probe.age < float(d.get("max_s", 10.0)) + 2.0:
		probe.age += dt
		var want := probe.motor_target(probe.age)
		if want > probe.velocity.length():
			probe.velocity = probe.velocity.normalized() * want
		probe.velocity += Vector3.DOWN * GRAVITY * dt
		pos += probe.velocity * dt
	var out := {"drop": -pos.y, "time": probe.age}
	probe.free()
	_drops[key] = out
	return out


## Every peer: one step of unguided flight (motor along the velocity, gravity). Guided rounds
## keep their velocity between the host's tracks on other peers.
func integrate(dt: float) -> Vector3:
	age += dt
	if not guided():
		var want := motor_target(age)
		if want > velocity.length():
			velocity = velocity.normalized() * want
		velocity += Vector3.DOWN * GRAVITY * dt
	var step := velocity * dt
	return global_position + step


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		return  # the host steps it from Launchers (server_step), checking what it meets
	var to := integrate(delta)
	travelled += global_position.distance_to(to)
	global_position = to
	_face_and_trail(delta)


## Host only. Flies one physics step; returns {} or what happened: {"hit": the collider,
## "position", "normal", "direction", "top_attack"} when it meets something, {"dud": true...}
## when it met something before arming, or {"expired": true} past its max flight time.
func server_step(delta: float) -> Dictionary:
	var from := global_position
	var to: Vector3
	match String(data.get("guidance", "")):
		"javelin":
			to = _javelin_step(delta)
		"nlaw":
			to = _nlaw_step(delta)
		_:
			to = integrate(delta)
	var space := get_world_3d().direct_space_state
	var top := false
	var hit := {}
	if String(data.get("guidance", "")) == "nlaw" and mode != "da" and travelled >= float(data.get("arming_m", 0.0)):
		hit = _nlaw_sensor(space, from, to)
		top = not hit.is_empty()
	if hit.is_empty():
		var query := PhysicsRayQueryParameters3D.create(from, to, Warheads.MASK, exclude)
		query.collide_with_areas = true
		hit = space.intersect_ray(query)
	var dir := (to - from).normalized() if to != from else velocity.normalized()
	if not hit.is_empty():
		var flown := travelled + from.distance_to(hit.position)
		travelled = flown
		global_position = hit.position
		if flown < float(data.get("arming_m", 0.0)):
			return {"dud": true, "hit": hit.collider, "position": hit.position, "normal": hit.normal, "direction": dir}
		if not top and String(data.get("guidance", "")) == "javelin" and mode == "top" and phase == "dive" and dir.y < -0.5:
			top = true
		return {"hit": hit.collider, "position": hit.position, "normal": hit.normal, "direction": Vector3.DOWN if top and String(data.get("guidance", "")) == "nlaw" else dir, "top_attack": top}
	travelled += from.distance_to(to)
	global_position = to
	max_height = maxf(max_height, to.y - launch_pos.y)
	_face_and_trail(delta)
	if age >= float(data.get("max_s", 10.0)):
		return {"expired": true, "position": to, "direction": dir}
	return {}


# --- Javelin --------------------------------------------------------------------------------

## Host only. Sets up the climb for a Javelin launched from `from` at `target`: the waypoint
## at the top of its climb, short of the target by the apex height times the dive ratio.
func javelin_start(from: Vector3) -> void:
	launch_pos = from
	var aim := aim_point()
	var flat_v := Vector3(aim.x - from.x, 0.0, aim.z - from.z)
	var flat := flat_v.length()
	var top := mode != "direct"
	var apex: float
	if top:
		apex = minf(float(data.get("top_apex_m", 150.0)), maxf(MIN_APEX_M, flat * APEX_RANGE_SHARE))
	else:
		apex = minf(float(data.get("direct_apex_m", 50.0)), maxf(DIRECT_MIN_APEX_M, flat * DIRECT_APEX_SHARE))
	apex_y = maxf(from.y, aim.y) + apex
	var short := clampf(apex * (TOP_DIVE_RATIO if top else DIRECT_DIVE_RATIO), flat * 0.25, flat * 0.75)
	var dir := flat_v / flat if flat > 0.01 else Vector3.FORWARD
	waypoint = Vector3(from.x, apex_y, from.z) + dir * (flat - short)
	phase = "climb"


## Where the missile goes on its target: the middle of the roof (top attack) or the centre of
## the hull (direct). Its last known point once the target is gone.
func aim_point() -> Vector3:
	if is_instance_valid(target) and target.is_inside_tree():
		var box := Launchers.hull_box(target)
		_last_aim = box.get_center() + Vector3.UP * (box.size.y * 0.5 - 0.05 if mode != "direct" else 0.0)
	return _last_aim


func _javelin_step(dt: float) -> Vector3:
	age += dt
	var delay := float((data.get("motor", {}) as Dictionary).get("delay_s", 0.0))
	var speed := velocity.length()
	if age >= delay:
		speed = maxf(speed, motor_target(age))
	var pos := global_position
	var want: Vector3
	if age < delay:
		want = (velocity + Vector3.DOWN * GRAVITY * dt).normalized()  # soft launch: ejected, it drops a little
	else:
		var aim := aim_point()
		if phase == "climb":
			var flown_flat := Vector2(pos.x - launch_pos.x, pos.z - launch_pos.z).length()
			var to_wp := Vector2(waypoint.x - launch_pos.x, waypoint.z - launch_pos.z).length()
			if pos.distance_to(waypoint) <= WAYPOINT_REACH_M or flown_flat >= to_wp:
				phase = "dive"
		want = ((waypoint if phase == "climb" else aim) - pos).normalized()
		var turn := deg_to_rad(float(data.get("turn_dps", 120.0))) * (DIVE_TURN_MULT if phase == "dive" else 1.0) * dt
		want = _turn_toward(velocity.normalized(), want, turn)
	velocity = want * speed
	return pos + velocity * dt


static func _turn_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var angle := from.angle_to(to)
	if angle <= max_angle or angle < 0.0001:
		return to
	var axis := from.cross(to)
	if axis.length() < 0.0001:
		axis = Vector3.UP if absf(from.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	return from.rotated(axis.normalized(), max_angle).normalized()


# --- NLAW -----------------------------------------------------------------------------------

## Host only. Sets up an NLAW's predicted line of sight from `from` along `dir`.
func nlaw_start(from: Vector3, dir: Vector3) -> void:
	launch_pos = from
	line_from = from
	line_dir = dir.normalized()
	line_s = 0.0


func _nlaw_step(dt: float) -> Vector3:
	age += dt
	var speed := maxf(motor_target(age), float(data.get("speed_mps", 40.0)))
	line_s += speed * dt
	var rise := 0.0
	if mode != "da":
		rise = float(data.get("ota_height_m", 1.2)) * clampf(line_s / NLAW_RISE_M, 0.0, 1.0)
	var to := line_from + line_dir * line_s + Vector3.UP * rise
	velocity = (to - global_position) / maxf(dt, 0.0001)
	return to


## Host only. The overfly sensor: looks down from points along the step for a vehicle within
## sensor_m. Returns a hit dictionary (the roof) or {}.
func _nlaw_sensor(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var length := from.distance_to(to)
	var samples := maxi(1, ceili(length / SENSOR_STEP_M))
	var reach := float(data.get("sensor_m", 3.5))
	for i in range(1, samples + 1):
		var p := from.lerp(to, float(i) / samples)
		var query := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * reach, Vehicle.LAYER, exclude)
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and Vehicle.find_on(hit.collider) != null:
			global_position = p
			return hit
	return {}


# --- Looks (every peer) ---------------------------------------------------------------------

func _build_visual() -> void:
	var calibre := float(data.get("calibre_mm", 84.0)) / 1000.0
	var length := clampf(calibre * 9.0, 0.5, 1.2)
	_visual = Node3D.new()
	add_child(_visual)
	var body := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = calibre * 0.5
	tube.bottom_radius = calibre * 0.42
	tube.height = length
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("4d5236") if guided() else Color("3c4030")
	tube.material = m
	body.mesh = tube
	body.rotation.x = -PI * 0.5  # along -Z, the way it flies
	_visual.add_child(body)
	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = calibre * 0.5
	cone.height = calibre * 1.6
	var nm := StandardMaterial3D.new()
	nm.albedo_color = Color("2c2e25")
	cone.material = nm
	nose.mesh = cone
	nose.rotation.x = -PI * 0.5
	nose.position = Vector3(0, 0, -length * 0.5 - calibre * 0.8)
	_visual.add_child(nose)
	_flame = MeshInstance3D.new()
	var fs := SphereMesh.new()
	fs.radius = calibre * 0.7
	fs.height = calibre * 2.2
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.75, 0.35)
	fs.material = fm
	(_flame as MeshInstance3D).mesh = fs
	_flame.position = Vector3(0, 0, length * 0.5 + calibre)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.3)
	light.light_energy = 2.5
	light.omni_range = 6.0
	_flame.add_child(light)
	_visual.add_child(_flame)


func _face_and_trail(delta: float) -> void:
	if velocity.length_squared() > 0.01:
		look_along(velocity)
	if _flame:
		_flame.visible = motor_burning()
	_trail_cd -= delta
	if _trail_cd > 0.0 or not is_inside_tree():
		return
	_trail_cd = 0.04
	var puff := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.85, 0.82, 0.5) if motor_burning() else Color(0.7, 0.7, 0.68, 0.25)
	s.material = mat
	puff.mesh = s
	get_parent().add_child(puff)
	puff.global_position = global_position
	var tween := puff.create_tween().set_parallel()
	tween.tween_property(puff, "scale", Vector3.ONE * 4.0, 1.6)
	tween.tween_property(mat, "albedo_color:a", 0.0, 1.6)
	tween.chain().tween_callback(puff.queue_free)


func look_along(v: Vector3) -> void:
	if not is_inside_tree() or v.length_squared() < 0.0001:
		return
	var up := Vector3.UP if absf(v.normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	look_at(global_position + v, up)
