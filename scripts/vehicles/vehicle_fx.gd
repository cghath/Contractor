class_name VehicleFx
extends Node3D
## What a vehicle's fire, ammunition and guns look and sound like (combined arms A7, cg_brief
## queue item 2.5; docs/combined_arms.md 2.10, 2.10.3-2.10.6): the "Fx" child of every Vehicle,
## on every peer. It draws VehicleFire's state (the stages: grey smoke, flames and black smoke,
## the burning wreck, the smoulder; a cook-off's pops; the thrown turret and the debris where
## they came to rest) and plays its one-off events (server_event: the fireball, the vent's column,
## a pop, a muzzle's flash and blast, a smoke salvo's grenades). In the voxel look: every particle
## is a small box (GPUParticles3D: the GPU's cost; a headless peer keeps the nodes and numbers).
##
## - The column: a smoke column of boxes rising 30-40 m over a burning vehicle, one tall
##   billboard past billboard_m (seen from range, cheap), gone with the column's time.
## - The catastrophic kill: a fireball of the kill's radius (VehicleFire.fireball), a flash, a
##   burst of black smoke, the detonation heard with its delay (Sfx: the speed of sound), a shake
##   for anyone near; the turret thrown as a RigidBody3D from the seed (8-15 m/s up, 2-4 to the
##   side, a spin), its crash where it lands; 12-24 debris boxes thrown from the seed, asleep
##   after 8 s and frozen static after 30 s; the hulk charred. The host's land and their rest
##   poses go to every peer, late joiners and the save (VehicleFire.server_rested): the same
##   pieces everywhere without a position stream (BlastGore's pattern).
## - The vent: an 8 m column of fire up through the bustle's blow-out panels for 4 s, unlike a
##   detonation's ball (2.10.2).
## - Guns (F-245): the 120 mm's flash, light, the dust its overpressure kicks up round the muzzle,
##   the gun's recoil and the hull rocking, and a thump and a shake for anyone within thump_m
##   outside; the 25 mm's flash; the TOW's launch flash and back-blast, the launcher raised and
##   lowered (the "Turret/Launcher" part, VehicleTurret.split) as VehicleWeapons says.
## - Impacts by round (2.10.3, ShellFlight's end on every peer: impact()): ricochet sparks and a
##   streak, KE stopped sparks and a clang/thud/clank by the hull, a penetration's white flash and
##   glow, HEAT's orange flash and black puff, HE's fireball by its filling.
## Budgets (2.10.6, Proposed, data/vehicle_fx.json): at most full_fires vehicles with flames and
## a light (the nearest; more show smoke only), particles across the zone, lights at once, debris
## bodies; every column a billboard past billboard_m. Headless-safe: no camera means no billboard
## switch, nothing here needs a renderer or audio.

const NODE_NAME := &"Fx"
## Effects update this often (s) between frames; the zone's budget is shared out this often.
const UPDATE_S := 0.1
const SHARE_S := 0.5
## The column (m): its emitter's rise, life, the billboard's size.
const COLUMN_RISE_MPS := 3.5
const COLUMN_LIFE_S := 10.0
const BILLBOARD := Vector2(10.0, 40.0)
## Particle counts wanted (each granted from the zone's budget; the CPU cost of the boxes is
## about 1-4 ms a frame a thousand, headless).
const WANT_SMOKE := 16
const WANT_COLUMN := 40
const WANT_COLUMN_SMOKE_ONLY := 20
const WANT_SMOULDER := 8
const WANT_FLAMES := 24
const WANT_BURST := 30
const WANT_POP := 10
const WANT_VENT := 40
const WANT_DUST := 16
## A thrown turret's mass (kg), a debris piece's density (kg/m^3).
const TURRET_MASS := 8000.0
const DEBRIS_DENSITY := 2500.0
## The hull rocks back this much (rad) on a 120 mm shot; the gun recoils this far (m).
const ROCK_RAD := 0.02
const RECOIL_M := 0.35
## Roll salts.
const ROLL_DEBRIS := 8100
const ROLL_TOSS := 8200
## A kill this new (s) is shown by its event (the fireball), older ones from the state (a late joiner).
const KILL_LIVE_S := 2.0
## The pieces and the turret pass through their own hull this long after they're thrown (s).
const EXCEPTION_S := 0.4
## Debris and the turret on thermal (ThermalView reads this group's "thermal_heat").
const THERMAL_GROUP := &"thermal_bodies"

## Tests: effects made since the start, by kind ("kill", "vent", "pop", "muzzle_cannon", ...).
static var made := {}
## The live emitters, lights and debris bodies of every vehicle (the zone's budgets).
static var _emitters: Array = []
static var _lights: Array = []
static var _debris: Array = []
static var _static_debris: Array = []
## The vehicles showing full fire effects now (shared out every SHARE_S), and the last share.
static var _full: Array = []
static var _shared_at := -100.0
## Milliseconds the effects took in the last frame they ran (budget), and the worst.
static var last_ms := 0.0
static var worst_ms := 0.0
static var _frame := -1
static var _frame_us := 0
static var _mats := {}
static var _meshes := {}

var vehicle: Vehicle
var _left := 0.0
var _column: GPUParticles3D
var _flames: GPUParticles3D
var _light: OmniLight3D
var _billboard: MeshInstance3D
var _look := ""          # what the fire shows now ("stage|full|far")
var _turret_body: RigidBody3D
var _turret_t0 := -1.0
var _turret_max_y := -INF
var _turret_crashed := false
var _pieces: Array = []  # this vehicle's debris bodies, by plan index
var _debris_t0 := -1.0
var _kill_shown := ""    # the kill kind drawn (once)
var _rested := false
var _excepted_off := false
var _launcher: Node3D
var _launcher_up := 0.0
var _charred := false


func _init(p_vehicle: Vehicle = null) -> void:
	name = NODE_NAME
	vehicle = p_vehicle


func _ready() -> void:
	_launcher = vehicle.hull.art.get_node_or_null(^"Turret/Launcher") as Node3D if vehicle and vehicle.hull and vehicle.hull.art else null


static func data() -> Dictionary:
	return VehicleFire.data()


static func num(section: String, key: String, fallback: float) -> float:
	return VehicleFire.num(section, key, fallback)


static func _note(kind: String) -> void:
	made[kind] = int(made.get(kind, 0)) + 1


## The vehicle's Fx (null without one).
static func of(v: Vehicle) -> VehicleFx:
	return v.get_node_or_null(NodePath(String(NODE_NAME))) as VehicleFx if v else null


# --- Events: host -> every peer -----------------------------------------------------------------

## Host: effect `kind` of `v` on every peer ("kill", "vent", "pop", "muzzle", "smoke"), with `args`.
static func server_event(v: Vehicle, kind: String, args: Dictionary) -> void:
	var fx := of(v)
	if fx == null:
		return
	if fx.is_inside_tree() and fx.multiplayer.multiplayer_peer != null and fx.multiplayer.is_server() and fx.multiplayer.get_peers().size() > 0:
		if kind in ["pop", "muzzle"]:
			fx._event_u.rpc(kind, args)
		else:
			fx._event.rpc(kind, args)
	else:
		fx._play(kind, args)


@rpc("authority", "call_local", "reliable")
func _event(kind: String, args: Dictionary) -> void:
	_play(kind, args)


@rpc("authority", "call_local", "unreliable")
func _event_u(kind: String, args: Dictionary) -> void:
	_play(kind, args)


func _play(kind: String, args: Dictionary) -> void:
	if vehicle == null or not is_inside_tree():
		return
	match kind:
		"kill":
			var f := _fire()
			if f and not _is_host() and args.has("sd"):
				f.seed = int(args.sd)  # the same pieces as the host's, whichever of the event and the state came first
				f.kill = (args.get("kill", f.kill) as Dictionary).duplicate()
			_show_kill(String(args.get("k", "")), true)
		"vent":
			_show_vent(String(args.get("rack", "")))
		"pop":
			_show_pop(args.get("at", global_position) as Vector3, int(args.get("n", 0)))
		"muzzle":
			_show_muzzle(String(args.get("kind", "")), args.get("at", global_position) as Vector3, args.get("dir", Vector3.FORWARD) as Vector3)
		"smoke":
			_show_salvo(args.get("from", global_position) as Vector3, args.get("to", global_position) as Vector3)


# --- Each frame ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if vehicle == null:
		return
	var t0 := Time.get_ticks_usec()
	_pose_launcher(delta)
	_left -= delta
	if _left <= 0.0:
		_left = UPDATE_S
		_update()
	if _light and is_instance_valid(_light) and _light.visible:
		var now := Soldier._now()
		var flicker := 0.75 + 0.25 * sin(now * 17.0) * sin(now * 7.3)
		_light.light_energy = 4.0 * flicker * maxf(_fire().flames() if _fire() else 0.0, 0.2)
	_spent(t0)


static func _spent(t0: int) -> void:
	var f := Engine.get_process_frames()
	if f != _frame:
		last_ms = _frame_us / 1000.0
		worst_ms = maxf(worst_ms, last_ms) if _frame >= 0 else 0.0
		_frame = f
		_frame_us = 0
	_frame_us += Time.get_ticks_usec() - t0


func _fire() -> VehicleFire:
	return vehicle.fire_state if vehicle else null


## The fire's look and the pieces, at UPDATE_S.
func _update() -> void:
	var f := _fire()
	if f == null:
		return
	_share_out()
	if not f.kill.is_empty() and _kill_shown == "" and String(f.kill.get("k", "")) in [VehicleFire.TOSS, VehicleFire.RUPTURE] 			and (_is_host() or f.host_now() - float(f.kill.get("t", 0.0)) > KILL_LIVE_S):
		_show_kill(String(f.kill.k), false)  # a late joiner, a reloaded zone: no ball, the pieces where they lie
	if (vehicle.wrecked or not f.kill.is_empty() and String(f.kill.get("k", "")) in [VehicleFire.TOSS, VehicleFire.RUPTURE]) and not _charred:
		_charred = true
		if vehicle.hull:
			vehicle.hull.set_charred(String(f.kill.get("k", "")) in [VehicleFire.TOSS, VehicleFire.RUPTURE] or f.stage != VehicleFire.NONE)
	_step_pieces()
	if vehicle.hull and vehicle.turret:
		vehicle.hull.droop = vehicle.wrecked or (vehicle.modules != null and vehicle.modules.index_of("barrel") >= 0 and vehicle.modules.state("barrel") == VehicleModules.DESTROYED)
	var full := _full.has(self)
	var far := _far()
	var look := "%s|%s|%s|%s|%.2f" % [f.stage, "col" if f.column_up() else "", "full" if full and f.flames() > 0.0 else "", "far" if far else "", snappedf(f.flames(), 0.25)]
	if look == _look:
		return
	_look = look
	_set_column(f, far, full)
	_set_flames(f, full)


## Whether the listener is past billboard_m (no listener: near).
func _far() -> bool:
	var ear: Variant = Sfx.listener() if is_instance_valid(Sfx) else null
	return ear is Vector3 and (ear as Vector3).distance_to(global_position) > num("budgets", "billboard_m", 600.0)


## The zone's full fire effects go to the nearest full_fires vehicles with flames (every SHARE_S).
static func _share_out() -> void:
	var now := Soldier._now()
	if now - _shared_at < SHARE_S:
		return
	_shared_at = now
	var ear: Variant = Sfx.listener() if is_instance_valid(Sfx) else null
	var burning: Array = []
	for fx: VehicleFx in _all():
		var f := fx._fire()
		if f and f.flames() > 0.0:
			var d: float = (ear as Vector3).distance_to(fx.global_position) if ear is Vector3 else 0.0
			burning.append([d, fx])
	burning.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	_full.clear()
	for i in mini(burning.size(), int(num("budgets", "full_fires", 6.0))):
		_full.append(burning[i][1])


static func _all() -> Array:
	var out: Array = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return out
	for n in tree.get_nodes_in_group(Vehicle.GROUP):
		var fx := of(n as Vehicle)
		if fx:
			out.append(fx)
	return out


## Every peer: how many vehicles show full fire effects now (budget: full_fires).
static func full_count() -> int:
	var n := 0
	for fx: Variant in _full:
		if is_instance_valid(fx) and (fx as VehicleFx)._flames != null and (fx as VehicleFx)._flames.emitting:
			n += 1
	return n


# --- The column and the flames ------------------------------------------------------------------

func _set_column(f: VehicleFire, far: bool, full: bool) -> void:
	var size := VehicleArt.size_m(vehicle.model)
	var want := 0
	var colour := Color(0.12, 0.11, 0.1, 0.8)
	match f.stage:
		VehicleFire.SMOKE:
			want = WANT_SMOKE
			colour = Color(0.55, 0.55, 0.53, 0.6)
		VehicleFire.FIRE, VehicleFire.BURN_OUT:
			want = WANT_COLUMN if full else WANT_COLUMN_SMOKE_ONLY
		VehicleFire.SMOULDER:
			want = WANT_COLUMN_SMOKE_ONLY if f.column_up() else WANT_SMOULDER
			colour = Color(0.2, 0.19, 0.18, 0.7) if f.column_up() else Color(0.4, 0.4, 0.38, 0.45)
	var billboard := far and f.column_up()
	if billboard:
		want = 0
	if _billboard == null and billboard:
		_billboard = MeshInstance3D.new()
		_billboard.name = "ColumnFar"
		_billboard.mesh = _billboard_mesh()
		_billboard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_billboard)
		_billboard.position = Vector3(0.0, size.y + BILLBOARD.y * 0.5, 0.0)
	if _billboard:
		_billboard.visible = billboard
	var granted := _free_and_grant(_column, want)
	_column = null
	if granted > 0:
		var long := f.stage != VehicleFire.SMOKE and (f.column_up() or f.stage != VehicleFire.SMOULDER)
		_column = _emitter(granted, COLUMN_LIFE_S if long else 5.0, 1.0, colour, Vector2(COLUMN_RISE_MPS * 0.7, COLUMN_RISE_MPS * 1.2) if long else Vector2(0.8, 1.5),
			12.0, Vector3(0.0, 0.25, 0.0), Vector2(1.0, 6.0 if long else 3.0), Vector3(size.x * 0.25, 0.3, size.z * 0.25))
		_place(_column, "Column", Vector3(0.0, size.y * 0.9, 0.0))


func _set_flames(f: VehicleFire, full: bool) -> void:
	var size := VehicleArt.size_m(vehicle.model)
	var on := full and f.flames() > 0.0
	var want := roundi(WANT_FLAMES * f.flames()) if on else 0
	var granted := _free_and_grant(_flames, want)
	_flames = null
	if granted > 0:
		_flames = _emitter(granted, 0.8, 0.45, Color(1.0, 0.55, 0.15, 0.9), Vector2(2.0, 4.0), 20.0, Vector3(0.0, 1.0, 0.0), Vector2(0.4, 1.4),
			Vector3(size.x * 0.3, 0.2, size.z * 0.3), true)
		_place(_flames, "Flames", Vector3(0.0, size.y * 0.75, 0.0))
	if on and _light == null:
		_light = _take_light(Color(1.0, 0.5, 0.15), 12.0, 4.0)
		if _light:
			add_child(_light)
			_light.position = Vector3(0.0, size.y + 1.0, 0.0)
	elif not on and _light:
		_drop_light(_light)
		_light = null
	_set_roar(f.flames() > 0.0)


## The fire's roar (a loop at the hull) while it has flames.
func _set_roar(on: bool) -> void:
	var roar := get_node_or_null(^"Roar") as AudioStreamPlayer3D
	if on and roar == null and is_instance_valid(Sfx):
		var options := Sfx.streams(&"fire_roar")
		if options.is_empty():
			return
		var def: Dictionary = Sfx.defs.get("fire_roar", {})
		roar = AudioStreamPlayer3D.new()
		roar.name = "Roar"
		roar.stream = options[0]
		roar.bus = &"SFX"
		roar.unit_size = float(def.get("unit_size", 8.0))
		roar.max_distance = float(def.get("range_m", 120.0))
		roar.volume_db = float(def.get("volume_db", 0.0))
		add_child(roar)
		roar.position = Vector3(0.0, VehicleArt.size_m(vehicle.model).y, 0.0)
		if Sfx.enabled:
			roar.play()
		_note("roar")
	elif not on and roar:
		roar.queue_free()


## Frees `old` (an emitter of this vehicle's) and grants up to `want` particles from what's left.
func _free_and_grant(old: GPUParticles3D, want: int) -> int:
	if old and is_instance_valid(old):
		_emitters.erase(old)
		old.queue_free()
	return _grant(want)


## Puts a new emitter `p` under this node at `at`, emitting.
func _place(p: GPUParticles3D, label: String, at: Vector3) -> void:
	p.name = label
	p.local_coords = false
	add_child(p)
	p.position = at
	p.emitting = true


# --- Budgets ------------------------------------------------------------------------------------

## Particles live now across the zone (every emitter's amount while it emits).
static func particles_live() -> int:
	var n := 0
	var keep: Array = []
	for p: Variant in _emitters:
		if is_instance_valid(p) and not (p as Node).is_queued_for_deletion():
			keep.append(p)
			n += (p as GPUParticles3D).amount
	_emitters = keep
	return n


## Up to `want` particles out of what the zone's budget has left.
static func _grant(want: int) -> int:
	if want <= 0:
		return 0
	var left := int(num("budgets", "particles", 2000.0)) - particles_live()
	return clampi(want, 0, maxi(left, 0))


static func lights_live() -> int:
	_lights = _lights.filter(func(l: Variant) -> bool: return is_instance_valid(l) and not (l as Node).is_queued_for_deletion())
	return _lights.size()


## A light if the zone has one to spare (null: at the cap).
static func _take_light(colour: Color, reach: float, energy: float) -> OmniLight3D:
	if lights_live() >= int(num("budgets", "lights", 10.0)):
		return null
	var l := OmniLight3D.new()
	l.light_color = colour
	l.omni_range = reach
	l.light_energy = energy
	l.shadow_enabled = false
	_lights.append(l)
	return l


static func _drop_light(l: OmniLight3D) -> void:
	_lights.erase(l)
	if is_instance_valid(l):
		l.queue_free()


## Debris bodies in the zone (live ones moving, and frozen static ones).
static func debris_count() -> int:
	_debris = _debris.filter(func(b: Variant) -> bool: return is_instance_valid(b) and not (b as Node).is_queued_for_deletion())
	_static_debris = _static_debris.filter(func(b: Variant) -> bool: return is_instance_valid(b) and not (b as Node).is_queued_for_deletion())
	return _debris.size()


static func static_debris_count() -> int:
	debris_count()
	return _static_debris.size()


## A box emitter: `amount` boxes of `box_m` living `life` s, coloured `colour` fading out, at
## `speed` (m/s) up within `spread_deg`, pulled by `gravity`, scaled over life from scale.x to
## scale.y, out of a box of half `extents`; `glow` unshaded and bright (flames). GPUParticles3D:
## simulated on the GPU (GPUParticles3D cost 6-10 ms a frame a thousand in a zone, R0642), and a
## headless peer (the dummy renderer) keeps the node and its numbers only.
static func _emitter(amount: int, life: float, box_m: float, colour: Color, speed: Vector2, spread_deg: float, gravity: Vector3,
		scale: Vector2, extents: Vector3, glow := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.draw_pass_1 = _box_mesh(box_m, glow)
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = extents
	m.direction = Vector3.UP
	m.spread = spread_deg
	m.initial_velocity_min = speed.x
	m.initial_velocity_max = speed.y
	m.gravity = gravity
	m.damping_min = 0.2
	m.damping_max = 0.6
	m.scale_min = scale.x
	m.scale_max = scale.x * 1.3
	var curve := Curve.new()
	curve.max_value = maxf(scale.y / maxf(scale.x, 0.01), 1.0)
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, curve.max_value))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var ramp := Gradient.new()
	ramp.set_color(0, colour)
	ramp.set_color(1, Color(colour.r * 0.6, colour.g * 0.6, colour.b * 0.6, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	m.color_ramp = gt
	m.angle_min = 0.0
	m.angle_max = 90.0
	p.process_material = m
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-20.0, -5.0, -20.0), Vector3(40.0, 60.0, 40.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_emitters.append(p)
	return p


static func _box_mesh(size: float, glow: bool) -> BoxMesh:
	var key := "%s|%s" % [size, glow]
	if _meshes.has(key):
		return _meshes[key]
	var m := BoxMesh.new()
	m.size = Vector3.ONE * size
	m.material = _particle_material(glow)
	_meshes[key] = m
	return m


static func _particle_material(glow: bool) -> StandardMaterial3D:
	var key := "particle|%s" % glow
	if not _mats.has(key):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		if glow:
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mats[key] = mat
	return _mats[key]


static func _solid_material(colour: Color, alpha := false) -> StandardMaterial3D:
	var key := "solid|%s|%s" % [colour, alpha]
	if not _mats.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colour
		if alpha:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[key] = mat
	return _mats[key]


## The far column: one tall billboard, dark at the bottom fading up and out.
static func _billboard_mesh() -> QuadMesh:
	if _meshes.has("billboard"):
		return _meshes["billboard"]
	var g := Gradient.new()
	g.set_color(0, Color(0.1, 0.1, 0.09, 0.85))
	g.set_color(1, Color(0.3, 0.3, 0.28, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 1.0)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 32
	tex.height = 128
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.albedo_texture = tex
	var q := QuadMesh.new()
	q.size = BILLBOARD
	q.material = mat
	_meshes["billboard"] = q
	return q


# --- One-off effects ----------------------------------------------------------------------------

## A ball of `colour` growing to `radius` and fading over `life` s at `pos`, with a flash.
func _ball(pos: Vector3, radius: float, colour: Color, life: float, flash := true) -> void:
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	var mat := (_solid_material(colour, true)).duplicate() as StandardMaterial3D
	sphere.material = mat
	ball.mesh = sphere
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.top_level = true
	add_child(ball)
	ball.global_position = pos
	ball.scale = Vector3.ONE * 0.3
	var tween := ball.create_tween().set_parallel()
	tween.tween_property(ball, "scale", Vector3.ONE * radius * 2.0, life * 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mat, "albedo_color:a", 0.0, life)
	tween.chain().tween_callback(ball.queue_free)
	if flash:
		var l := _take_light(colour, 4.0 + radius * 4.0, 10.0)
		if l:
			ball.add_child(l)
			var lt := l.create_tween()
			lt.tween_property(l, "light_energy", 0.0, life)


## A one-shot burst of `amount` boxes at `pos` (world).
func _burst(pos: Vector3, amount: int, life: float, box_m: float, colour: Color, speed: Vector2, spread: float, gravity: Vector3, scale: Vector2, glow := false, dir := Vector3.UP) -> GPUParticles3D:
	var granted := _grant(amount)
	if granted <= 0:
		return null
	var p := _emitter(granted, life, box_m, colour, speed, spread, gravity, scale, Vector3.ONE * 0.2, glow)
	p.one_shot = true
	p.explosiveness = 0.95
	(p.process_material as ParticleProcessMaterial).direction = dir
	p.top_level = true
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)  # (particles_live drops it from _emitters)
	return p


func _show_kill(k: String, live: bool) -> void:
	if _kill_shown != "":
		return
	_kill_shown = k
	var f := _fire()
	var radius := float(f.kill.get("radius", 4.0)) if f else 4.0
	var centre := vehicle.global_transform * Vector3(0.0, VehicleArt.size_m(vehicle.model).y * 0.6, 0.0)
	if live:
		_note("kill")
		_ball(centre, radius, Color(1.0, 0.55, 0.2, 0.85), 0.9)
		_burst(centre, WANT_BURST, 6.0, 1.2, Color(0.08, 0.07, 0.07, 0.85), Vector2(4.0, 10.0), 70.0, Vector3(0.0, 0.5, 0.0), Vector2(1.0, 5.0))
		_burst(centre, WANT_POP * 2, 1.2, 0.12, Color(1.0, 0.8, 0.4, 1.0), Vector2(10.0, 25.0), 90.0, Vector3(0.0, -9.8, 0.0), Vector2(1.0, 0.5), true)
		Sfx.play_at(&"detonation", centre)
		_shake_near(centre, num("fireball", "shake_m", 120.0), 1.0)
	if k == VehicleFire.TOSS:
		_toss_turret(not live)
	_throw_debris(not live)


func _show_vent(rack: String) -> void:
	_note("vent")
	var top := vehicle.global_transform * Vector3(0.0, VehicleArt.size_m(vehicle.model).y, 0.0)
	if vehicle.modules:
		var i := vehicle.modules.index_of(rack)
		if i >= 0 and vehicle.modules.mods[i].box is AABB:
			var box: AABB = vehicle.modules.mods[i].box
			top = vehicle.to_global(Vector3(box.get_center().x, box.end.y + 0.1, box.get_center().z))
	var s := num("vent", "s", 4.0)
	var col := num("vent", "column_m", 8.0)
	var p := _burst(top, WANT_VENT, 0.6, 0.5, Color(1.0, 0.6, 0.2, 0.95), Vector2(col / 0.6 * 0.8, col / 0.6), 8.0, Vector3.ZERO, Vector2(0.8, 2.0), true)
	if p:
		p.one_shot = false
		p.explosiveness = 0.0
		get_tree().create_timer(s).timeout.connect(p.set.bind(&"emitting", false))
		get_tree().create_timer(s + 1.0).timeout.connect(p.queue_free)
	var l := _take_light(Color(1.0, 0.55, 0.2), 16.0, 8.0)
	if l:
		l.top_level = true
		add_child(l)
		l.global_position = top + Vector3.UP * col * 0.5
		get_tree().create_timer(s).timeout.connect(l.queue_free)  # (lights_live drops it)
	Sfx.play_at(&"vent_roar", top)


func _show_pop(at: Vector3, n: int) -> void:
	_note("pop")
	_burst(at, WANT_POP, 0.5, 0.08, Color(1.0, 0.85, 0.5, 1.0), Vector2(4.0, 12.0), 60.0, Vector3(0.0, -6.0, 0.0), Vector2(1.0, 0.4), true)
	if n % 3 == 0:
		_ball(at, 0.35, Color(1.0, 0.7, 0.35, 0.9), 0.15, false)
	Sfx.play_at(&"cookoff_pop", at)


## A muzzle's effects: "cannon" (the 120 mm: flash, light, dust from the overpressure, recoil,
## the hull rocking, a thump and shake near), "autocannon", "atgm" (the TOW's launch).
func _show_muzzle(kind: String, at: Vector3, dir: Vector3) -> void:
	_note("muzzle_" + kind)
	match kind:
		"cannon":
			_ball(at + dir * 1.0, 1.4, Color(1.0, 0.75, 0.4, 0.9), 0.12)
			var ground := at + Vector3.DOWN * maxf(at.y - vehicle.global_position.y, 0.5)
			var dust := _burst(ground + dir * 3.0, WANT_DUST, 2.0, 0.6, Color(0.62, 0.57, 0.48, 0.6), Vector2(4.0, 9.0), 80.0, Vector3(0.0, -0.5, 0.0), Vector2(1.0, 4.0), false, Vector3.UP)
			if dust:
				var dm := dust.process_material as ParticleProcessMaterial
				dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
				dm.emission_ring_axis = Vector3.UP
				dm.emission_ring_radius = num("muzzle", "dust_m", 6.0) * 0.5
				dm.emission_ring_inner_radius = 0.5
				dm.emission_ring_height = 0.2
			_recoil(RECOIL_M, ROCK_RAD)
			var ear: Variant = Sfx.listener()
			var thump := num("muzzle", "thump_m", 40.0)
			if ear is Vector3 and (ear as Vector3).distance_to(at) < thump and not _listener_inside():
				Sfx.play_at(&"m256_blast", at)
				_shake_near(at, thump, 0.6)
		"autocannon":
			_ball(at + dir * 0.3, 0.35, Color(1.0, 0.75, 0.4, 0.9), 0.06, Engine.get_process_frames() % 3 == 0)
			_recoil(0.08, 0.0)
		"atgm":
			_ball(at, 0.6, Color(1.0, 0.8, 0.5, 0.9), 0.15)
			_burst(at - dir * 1.2, WANT_DUST, 1.6, 0.4, Color(0.7, 0.68, 0.64, 0.6), Vector2(3.0, 7.0), 25.0, Vector3(0.0, 0.3, 0.0), Vector2(1.0, 4.0), false, -dir)
			Sfx.play_at(&"tow_wire", at)


## Host: the 120 mm's overpressure on the men outside in front of its muzzle (within harm_m and
## harm_deg of the bore): their ears ring for deaf_s, less the closer to harm_m (none with ear
## protection: Throwables.has_ear_pro). Who it reached.
static func server_overpressure(v: Vehicle, at: Vector3, dir: Vector3) -> Array:
	var hurt: Array = []
	if v == null or not v.is_inside_tree():
		return hurt
	var reach := num("muzzle", "harm_m", 10.0)
	var cone := cos(deg_to_rad(num("muzzle", "harm_deg", 60.0)))
	for n in v.get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or Vehicle.ride_of(s) != null or not s.vitals.is_up():
			continue
		var to := s.global_position + Vector3.UP * 1.5 - at
		if to.length() > reach or to.normalized().dot(dir.normalized()) < cone:
			continue
		s.vitals.server_deafen(num("muzzle", "deaf_s", 8.0) * (1.0 - 0.5 * to.length() / reach), Throwables.has_ear_pro(s))
		hurt.append(s)
	return hurt


## Whether this peer's listener sits buttoned up in this vehicle.
func _listener_inside() -> bool:
	return is_instance_valid(Sfx) and Sfx.muffled and Sfx.local_vehicle() == vehicle


## The gun slides back `metres` and returns, the hull rocks back `rock` rad and settles.
func _recoil(metres: float, rock: float) -> void:
	var art := vehicle.hull.art if vehicle.hull else null
	if art == null:
		return
	var gun := art.get_node_or_null(^"Turret/Gun/Mesh") as Node3D
	if gun:
		var rest: Vector3 = gun.get_meta(&"rest", gun.position)
		gun.set_meta(&"rest", rest)
		var t := gun.create_tween()
		t.tween_property(gun, "position", rest + Vector3(0.0, 0.0, metres), 0.04)
		t.tween_property(gun, "position", rest, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	if rock > 0.0:
		var rt := art.create_tween()
		rt.tween_property(art, "rotation:x", -rock, 0.06)
		rt.tween_property(art, "rotation:x", 0.0, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)


## A discharger's grenade arcing out to `to`, then bursting (the cloud is SmokeCloud's).
func _show_salvo(from: Vector3, to: Vector3) -> void:
	_note("salvo")
	var g := MeshInstance3D.new()
	g.mesh = _box_mesh(0.08, false)
	g.top_level = true
	add_child(g)
	g.global_position = from
	var mid := from.lerp(to, 0.5) + Vector3.UP * maxf(from.distance_to(to) * 0.25, 2.0)
	var arc := func(k: float) -> void:
		if is_instance_valid(g):
			g.global_position = from.lerp(mid, k).lerp(mid.lerp(to, k), k)
	var land := func() -> void:
		if is_instance_valid(g):
			_ball(to, 0.8, Color(1.0, 0.9, 0.7, 0.8), 0.15, false)
			g.queue_free()
	var t := g.create_tween()
	t.tween_method(arc, 0.0, 1.0, VehicleSmoke.FLIGHT_S)
	t.tween_callback(land)


## A shake for this peer's player within `radius` of `at` (stronger closer).
func _shake_near(at: Vector3, radius: float, strength: float) -> void:
	var lvl := vehicle.level()
	if lvl == null:
		return
	for p in lvl.players.get_children():
		var s := p as Soldier
		if s and s.is_local() and s.player_input:
			var d := s.global_position.distance_to(at)
			if d < radius:
				s.player_input.shake(strength * (1.0 - d / radius))


# --- The thrown turret and the debris -----------------------------------------------------------

## Where debris piece `i` leaves the hull (vehicle frame), by the seed: over the roof.
static func debris_spot(size: Vector3, seed: int, i: int) -> Vector3:
	var rx := ArmourModel.roll(seed, ROLL_DEBRIS + i * 8)
	var rz := ArmourModel.roll(seed, ROLL_DEBRIS + i * 8 + 1)
	return Vector3((rx - 0.5) * size.x * 0.8, size.y * 0.55, (rz - 0.5) * size.z * 0.8)


## The debris a kill of `model` with `seed` throws (the same on every peer): each {"size",
## "from" (vehicle frame), "vel" (vehicle frame, m/s), "spin"}.
static func debris_plan(model: String, seed: int) -> Array:
	var size := VehicleArt.size_m(model)
	var lohi: Array = (data().get("debris", {}) as Dictionary).get("count", [12, 24])
	var n := roundi(lerpf(float(lohi[0]), float(lohi[1]), ArmourModel.roll(seed, ROLL_DEBRIS - 1)))
	var out: Array = []
	for i in n:
		var r := func(k: int) -> float: return ArmourModel.roll(seed, ROLL_DEBRIS + i * 8 + k)
		var s := VehicleFire.span("debris", "size_m", Vector2(0.18, 0.55), r.call(2))
		var from := debris_spot(size, seed, i)
		var out_dir := Vector3(from.x, 0.0, from.z).normalized() if Vector2(from.x, from.z).length() > 0.05 else Vector3.RIGHT
		var up := lerpf(0.5, 1.0, r.call(3))
		var speed := VehicleFire.span("debris", "speed_mps", Vector2(6.0, 16.0), r.call(4))
		var vel := (out_dir * (1.0 - up * 0.6) + Vector3.UP * up).normalized() * speed
		var spin := Vector3(r.call(5) - 0.5, r.call(6) - 0.5, r.call(7) - 0.5) * 12.0
		out.append({"size": Vector3(s, s * lerpf(0.3, 0.8, r.call(5)), s * lerpf(0.6, 1.2, r.call(6))), "from": from + Vector3.UP * 0.3, "vel": vel, "spin": spin})
	return out


## A short digest of a plan (tests: two peers make the same debris from one seed).
static func plan_digest(plan: Array) -> int:
	var parts: Array = []
	for p: Dictionary in plan:
		parts.append([snapped(p.size, Vector3.ONE * 0.001), snapped(p.from, Vector3.ONE * 0.001), snapped(p.vel, Vector3.ONE * 0.001)])
	return hash(parts)


## Throws (or, `settled`, lays where the host's came to rest) this kill's debris.
func _throw_debris(settled: bool) -> void:
	var f := _fire()
	if f == null or not _pieces.is_empty():
		return
	var plan := debris_plan(vehicle.model, f.seed)
	var rests: Array = f.debris_rest
	var colours := [Color(0.13, 0.12, 0.11), Color(0.2, 0.18, 0.15), Color(0.3, 0.22, 0.14)]
	for i in plan.size():
		var p: Dictionary = plan[i]
		var body := RigidBody3D.new()
		body.name = "Debris%d" % i
		body.top_level = true
		body.collision_layer = 1
		body.collision_mask = 1 | Vehicle.LAYER
		var size: Vector3 = p.size
		body.mass = maxf(size.x * size.y * size.z * DEBRIS_DENSITY * 0.3, 5.0)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = _solid_material(colours[i % colours.size()])
		body.add_child(mi)
		body.add_to_group(THERMAL_GROUP)
		body.set_meta(ThermalView.META, num("heat", "debris", 0.8))
		add_child(body)
		var rest: Variant = _pose(rests[i]) if i < rests.size() else null
		if settled and rest is Transform3D:
			body.global_transform = rest
			body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			body.freeze = true
			_static_debris.append(body)
		else:
			body.global_transform = Transform3D(vehicle.global_basis, vehicle.to_global(p.from))
			body.linear_velocity = vehicle.global_basis * (p.vel as Vector3)
			body.angular_velocity = p.spin
			body.add_collision_exception_with(vehicle)  # (until EXCEPTION_S: _step_pieces)
			_debris.append(body)
		_pieces.append(body)
	_debris_t0 = Soldier._now()
	if settled:
		_rested = true
	_cap_debris()


## The zone's cap: at most zone_max moving bodies (the oldest frozen static first), at most
## static_max kept at all (the oldest go).
static func _cap_debris() -> void:
	debris_count()
	var cap := int(num("debris", "zone_max", 64.0))
	while _debris.size() > cap:
		var b := _debris.pop_front() as RigidBody3D
		if is_instance_valid(b):
			b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			b.freeze = true
			_static_debris.append(b)
	var keep := int(num("debris", "static_max", 256.0))
	while _static_debris.size() > keep:
		var old := _static_debris.pop_front() as Node
		if is_instance_valid(old):
			old.queue_free()


## Asleep after sleep_s, frozen static after freeze_s; the host sends where they lie. Clients snap
## theirs to the host's when those come.
func _step_pieces() -> void:
	var f := _fire()
	var now := Soldier._now()
	if not _pieces.is_empty() and not _rested and _debris_t0 >= 0.0:
		var age := now - _debris_t0
		if age >= EXCEPTION_S and not _excepted_off:
			_excepted_off = true
			for b: Variant in _pieces:
				if is_instance_valid(b):
					(b as RigidBody3D).remove_collision_exception_with(vehicle)
		if age >= num("debris", "sleep_s", 8.0):
			for b: Variant in _pieces:
				if is_instance_valid(b) and not (b as RigidBody3D).freeze:
					(b as RigidBody3D).sleeping = true
		if age >= num("debris", "freeze_s", 30.0) or (not f.debris_rest.is_empty() and not _is_host()):
			_rested = true
			var poses: Array = []
			for i in _pieces.size():
				var b := _pieces[i] as RigidBody3D
				if not is_instance_valid(b):
					poses.append([])
					continue
				var rest: Variant = _pose(f.debris_rest[i]) if not _is_host() and i < f.debris_rest.size() else null
				if rest is Transform3D:
					b.global_transform = rest
				b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
				b.freeze = true
				_debris.erase(b)
				if not _static_debris.has(b):
					_static_debris.append(b)
				poses.append(_pose_array(b.global_transform))
			if _is_host():
				f.server_rested([], poses)
			_cap_debris()
	if _turret_body and is_instance_valid(_turret_body) and not _turret_body.freeze:
		var age := now - _turret_t0
		if age >= EXCEPTION_S * 1.5 and _turret_body.get_collision_exceptions().size() > 0:
			_turret_body.remove_collision_exception_with(vehicle)
		_turret_max_y = maxf(_turret_max_y, _turret_body.global_position.y)
		var settled := age > 1.5 and (_turret_body.sleeping or _turret_body.linear_velocity.length() < 0.15)
		if _is_host() and (settled or age >= num("toss", "rest_s", 12.0)):
			_turret_body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			_turret_body.freeze = true
			f.server_rested(_pose_array(_turret_body.global_transform), [])
		elif not _is_host() and not f.turret_rest.is_empty():
			_turret_body.global_transform = _pose(f.turret_rest)
			_turret_body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			_turret_body.freeze = true


func _is_host() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


## Throws the turret (its voxels and gun, the art's "Turret" node) as a body from the seed, or
## (`settled`) lays it where the host's came to rest.
func _toss_turret(settled: bool) -> void:
	if _turret_body or vehicle.hull == null:
		return
	var f := _fire()
	var node := vehicle.hull.detach_turret()
	if node == null:
		return
	var body := RigidBody3D.new()
	body.name = "ThrownTurret"
	body.top_level = true
	body.collision_layer = 1
	body.collision_mask = 1 | Vehicle.LAYER
	body.mass = TURRET_MASS
	body.add_to_group(THERMAL_GROUP)
	body.set_meta(ThermalView.META, num("heat", "turret", 0.9))
	var start: Transform3D = vehicle.global_transform * Transform3D(node.basis, node.position)
	node.transform = Transform3D.IDENTITY
	body.add_child(node)
	var aabb := _aabb_of(node)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size.max(Vector3.ONE * 0.3)
	shape.shape = box
	shape.position = aabb.get_center()
	body.add_child(shape)
	body.contact_monitor = true
	body.max_contacts_reported = 2
	body.body_entered.connect(_on_turret_landed)
	add_child(body)
	_turret_body = body
	_turret_t0 = Soldier._now()
	var rest: Variant = _pose(f.turret_rest) if not f.turret_rest.is_empty() else null
	if settled and rest is Transform3D:
		body.global_transform = rest
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
		return
	body.global_transform = start
	_turret_max_y = start.origin.y
	var seed := f.seed
	var r := func(k: int) -> float: return ArmourModel.roll(seed, ROLL_TOSS + k)
	var up := VehicleFire.span("toss", "up_mps", Vector2(8.0, 15.0), r.call(0))
	var side := VehicleFire.span("toss", "side_mps", Vector2(2.0, 4.0), r.call(1))
	var a: float = r.call(2) * TAU
	body.linear_velocity = Vector3(cos(a) * side, up, sin(a) * side)
	var spin := VehicleFire.span("toss", "spin_rads", Vector2(0.6, 2.5), r.call(3))
	body.angular_velocity = Vector3(r.call(4) - 0.5, r.call(5) - 0.5, r.call(6) - 0.5).normalized() * spin
	body.add_collision_exception_with(vehicle)  # (until EXCEPTION_S: _step_pieces)


func _on_turret_landed(_other: Node) -> void:
	if _turret_crashed or _turret_body == null or Soldier._now() - _turret_t0 < 0.3:
		return
	if _turret_body.linear_velocity.length() >= num("toss", "crash_mps", 4.0) or _turret_body.global_position.y < _turret_max_y - 1.0:
		_turret_crashed = true
		_note("turret_crash")
		Sfx.play_at(&"turret_crash", _turret_body.global_position)
		_burst(_turret_body.global_position, WANT_DUST, 2.0, 0.5, Color(0.55, 0.5, 0.42, 0.6), Vector2(2.0, 6.0), 80.0, Vector3(0.0, -1.0, 0.0), Vector2(1.0, 3.0))


## The thrown turret's body (tests, saves), or null.
func turret_body() -> RigidBody3D:
	return _turret_body if is_instance_valid(_turret_body) else null


## The highest the thrown turret got (world y).
func turret_peak() -> float:
	return _turret_max_y


func pieces() -> Array:
	return _pieces.filter(func(b: Variant) -> bool: return is_instance_valid(b))


static func _aabb_of(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi: Node in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var local := node.global_transform.affine_inverse() * m.global_transform if node.is_inside_tree() and m.is_inside_tree() else _relative(node, m)
		var box := local * m.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out if not first else AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 0.8, 2.0))


static func _relative(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


static func _pose_array(t: Transform3D) -> Array:
	var q := t.basis.get_rotation_quaternion()
	return [snappedf(t.origin.x, 0.001), snappedf(t.origin.y, 0.001), snappedf(t.origin.z, 0.001), snappedf(q.x, 0.0001), snappedf(q.y, 0.0001), snappedf(q.z, 0.0001), snappedf(q.w, 0.0001)]


static func _pose(a: Variant) -> Variant:
	if not (a is Array) or (a as Array).size() < 7:
		return null
	var q := Quaternion(float(a[3]), float(a[4]), float(a[5]), float(a[6]))
	if q.length_squared() < 0.0001:
		return null
	return Transform3D(Basis(q.normalized()), Vector3(float(a[0]), float(a[1]), float(a[2])))


# --- The TOW launcher ---------------------------------------------------------------------------

## The launcher's part follows VehicleWeapons' state: down, raising (over TOW_RAISE_S), up.
func _pose_launcher(delta: float) -> void:
	if _launcher == null or vehicle.weapons == null:
		return
	var p := launcher_state()
	var want := 1.0 if p == "up" else 0.0
	if p == "raising":
		want = 1.0
		_launcher_up = move_toward(_launcher_up, want, delta / VehicleWeapons.TOW_RAISE_S)
	else:
		_launcher_up = move_toward(_launcher_up, want, delta / 1.5)
	var deg := float(((vehicle.spec.get("turret", {}) as Dictionary).get("launcher", {}) as Dictionary).get("raise_deg", 25.0))
	_launcher.rotation.x = deg_to_rad(deg) * _launcher_up


## "down", "raising" or "up" (every peer).
func launcher_state() -> String:
	var w := vehicle.weapons
	if w == null:
		return "down"
	for m: Dictionary in w.mounts:
		if String(m.kind) == VehicleWeapons.ATGM:
			if _is_host():
				return String((w.state.get(m.id, {}) as Dictionary).get("p", "down"))
			return String(((w.net_state.get("m", {}) as Dictionary).get(m.id, {}) as Dictionary).get("p", "down"))
	return "down"


## How far up the launcher is drawn (0 stowed, 1 raised), and its angle (degrees).
func launcher_raised() -> float:
	return _launcher_up


func launcher_deg() -> float:
	return rad_to_deg(_launcher.rotation.x) if _launcher else 0.0


func has_launcher() -> bool:
	return _launcher != null


# --- Impacts by round (every peer: ShellFlight's end) -------------------------------------------

## The impact of a shell (shells.json `sid`) at `pos` that ended `how` ("vehicle", "world",
## "body", "air") with `outcome` (ArmourModel's: "ricochet", "non_pen", "pen", "shatter", "dud",
## "fuzed_outside"; "burst", "ke"), on a hull of class `cls` ("mbt", "ifv", "mrap"...). Returns
## the kind drawn (tests).
static func impact(parent: Node3D, pos: Vector3, how: String, outcome: String, sid: String, cls: String, dir := Vector3.FORWARD) -> String:
	if parent == null or not parent.is_inside_tree() or not pos.is_finite():
		return ""
	var row := Shells.shell(StringName(sid))
	var column := ShellFlight.column_of(String(row.get("kind", "he")))
	var kg := float(row.get("he_kg", 0.0))
	var what := ""
	if how == "vehicle":
		match outcome:
			"ricochet":
				what = "ricochet"
			"pen":
				what = "ke_pen" if column == "ke" else ("heat_pen" if column == "ce" else "he")
			"dud":
				what = "dud"
			_:
				what = "ke_stopped" if column == "ke" else ("heat_stopped" if column == "ce" else "he")
	elif how == "world":
		what = "ke_world" if column == "ke" or outcome in ["ke", "dud"] else "he"
	else:
		what = "he" if kg > 0.0 else "ke_world"
	_note("impact_" + what)
	var host := _impact_host(parent)
	if host == null:
		return what
	match what:
		"ricochet":
			host._burst(pos, WANT_POP, 0.35, 0.06, Color(1.0, 0.9, 0.6, 1.0), Vector2(8.0, 20.0), 35.0, Vector3(0.0, -9.8, 0.0), Vector2(1.0, 0.4), true, -dir)
			Sfx.play_at(&"ricochet", pos)
		"ke_stopped":
			host._burst(pos, WANT_POP, 0.4, 0.07, Color(1.0, 0.85, 0.5, 1.0), Vector2(4.0, 10.0), 70.0, Vector3(0.0, -9.8, 0.0), Vector2(1.0, 0.4), true, -dir)
			Sfx.play_at({"mbt": &"impact_thud", "ifv": &"impact_clank"}.get(cls, &"impact_clang"), pos)
		"ke_pen":
			host._ball(pos, 0.5, Color(1.0, 1.0, 0.9, 0.95), 0.2)
			host._burst(pos, WANT_POP, 0.6, 0.1, Color(1.0, 0.9, 0.7, 1.0), Vector2(5.0, 12.0), 50.0, Vector3(0.0, -9.8, 0.0), Vector2(1.0, 0.5), true, dir)
			Sfx.play_at(&"pen_boom", pos)
		"heat_stopped":
			host._ball(pos, 0.9, Color(1.0, 0.55, 0.15, 0.9), 0.25)
			host._burst(pos, WANT_POP * 2, 2.0, 0.5, Color(0.1, 0.09, 0.08, 0.8), Vector2(1.0, 3.0), 60.0, Vector3(0.0, 0.3, 0.0), Vector2(1.0, 3.0), false, -dir)
			Sfx.play_at(&"heat_bang", pos)
		"heat_pen":
			host._ball(pos, 0.7, Color(1.0, 0.85, 0.5, 0.95), 0.18)
			host._burst(pos, WANT_POP, 1.5, 0.2, Color(0.25, 0.24, 0.22, 0.7), Vector2(0.5, 1.5), 15.0, Vector3(0.0, 0.2, 0.0), Vector2(1.0, 2.0), false, -dir)
			Sfx.play_at(&"heat_bang", pos)
		"he":
			var r := 1.2 * pow(maxf(kg, 0.05), 1.0 / 3.0) + 0.6
			host._ball(pos, r, Color(1.0, 0.55, 0.2, 0.85), 0.35)
			host._burst(pos, WANT_POP * 2, 3.0, 0.6, Color(0.1, 0.09, 0.08, 0.8), Vector2(2.0, 5.0), 80.0, Vector3(0.0, 0.3, 0.0), Vector2(1.0, 3.5))
		"ke_world", "dud":
			host._burst(pos, WANT_POP, 1.2, 0.25, Color(0.6, 0.55, 0.45, 0.7), Vector2(2.0, 6.0), 40.0, Vector3(0.0, -6.0, 0.0), Vector2(1.0, 2.0), false, -dir)
	return what


## The node impacts hang their effects from: the level's "ImpactFx" (made once).
static func _impact_host(parent: Node3D) -> VehicleFx:
	var lvl := CompoundLevel.current(parent) if parent.is_inside_tree() else null
	var root: Node = lvl if lvl else parent
	var host := root.get_node_or_null(^"ImpactFx") as VehicleFx
	if host == null:
		host = VehicleFx.new(null)
		host.name = "ImpactFx"
		root.add_child(host)
	return host
