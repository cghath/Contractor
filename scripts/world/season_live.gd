class_name SeasonLive
extends Node
## The season shown on the land now, live mid-visit (Captain, 2026-11-21, plans/fallen-seasons.md
## call D). One per level on every peer, same name so its RPCs line up. The host sets the target
## state (Seasons.server_update -> server_set); clients get it by RPC, and a late joiner asks for it
## when its node is ready. The look blends over SeasonLook.BLEND_S and `look_changed` fires about
## 10 times a second while it does, then once more at the end; the ground, grass, trees, water and
## leaves listen and set their uniforms and colours.
##
## The zone def's season (ZoneFeatures.season, crops, orchards, the mountain snow line) is separate:
## it is geometry and follows on the next zone load.

signal look_changed(look: Dictionary)
## Fires when the ice comes or goes (walkable water, the nav mesh's rebake).
signal ice_changed(on: bool)

const NODE_NAME := "SeasonLive"
const EMIT_S := 0.1
## Falling leaves (autumn): at most LEAVES_MAX in the air in a box round the camera, as many as the
## look's "leaves" a second where LEAVES_FULL_TREES broadleaf trees stand within LEAVES_NEAR_M,
## fewer with fewer trees, none in the open; the woods sampled every LEAVES_SAMPLE_S. Proposed.
const LEAVES_MAX := 120
const LEAVES_LIFE_S := 6.0
const LEAVES_NEAR_M := 25.0
const LEAVES_FULL_TREES := 12
const LEAVES_SAMPLE_S := 1.0

## The target: {"season", "day" (1..Seasons.SEASON_DAYS)}; empty until the host sets it.
var target := {}
## The blended look now: SeasonLook.of(...) with numbers and Colors blended, plus "snow" (0-1).
var look := {}
var ice := false
var _from := {}
var _to := {}
var _t := 1.0
var _emit_left := 0.0
var _peers := {}  # host: the peers whose SeasonLive is up (they asked: _server_ask)
## The falling leaves (a display only), and how many a second they're falling now (checks).
var leaves: GPUParticles3D
var leaves_rate := 0.0
var _leaves_left := 0.0


## The level's SeasonLive, added once (any peer).
static func install(level: Node) -> SeasonLive:
	if level == null:
		return null
	var have := level.get_node_or_null(NODE_NAME) as SeasonLive
	if have:
		return have
	var s := SeasonLive.new()
	s.name = NODE_NAME
	level.add_child(s)
	return s


## The level's SeasonLive, or null.
static func of(level: Node) -> SeasonLive:
	return level.get_node_or_null(NODE_NAME) as SeasonLive if level else null


func _ready() -> void:
	set_process(false)  # (on while blending, and always with the leaves: _leaves_tick)
	look_changed.connect(_on_look)
	ice_changed.connect(_on_ice)
	if DisplayServer.get_name() != "headless":
		_make_leaves()
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_server_ask.rpc_id(1)  # a late joiner (or any client) asks for the season now


## Host: the season and its day now; the first call snaps, a new season blends.
func server_set(season: String, day: int) -> void:
	var t := {"season": season, "day": day}
	if t == target:
		return
	var snap := target.is_empty()
	_apply(t, snap)
	if multiplayer.has_multiplayer_peer():
		for peer: int in _peers.keys():
			if peer in multiplayer.get_peers():
				_client_set.rpc_id(peer, season, day, snap)
			else:
				_peers.erase(peer)


@rpc("any_peer", "call_remote", "reliable")
func _server_ask() -> void:
	if not multiplayer.is_server():
		return
	_peers[multiplayer.get_remote_sender_id()] = true  # its node is up: it gets every change from now on
	if target.is_empty():
		return
	_client_set.rpc_id(multiplayer.get_remote_sender_id(), String(target.season), int(target.day), true)


@rpc("authority", "call_remote", "reliable")
func _client_set(season: String, day: int, snap: bool) -> void:
	_apply({"season": season, "day": day}, snap or target.is_empty())


func _apply(t: Dictionary, snap: bool) -> void:
	target = t
	_to = SeasonLook.of(String(t.season))
	_to["snow"] = SeasonLook.snow(String(t.season), int(t.day))
	var now_ice := SeasonLook.ice(String(t.season), int(t.day))
	if snap or look.is_empty():
		look = _to.duplicate(true)
		_t = 1.0
		set_process(leaves != null)
		look_changed.emit(look)
	else:
		_from = look.duplicate(true)
		_t = 0.0
		_emit_left = 0.0
		set_process(true)
	if now_ice != ice:
		ice = now_ice
		ice_changed.emit(ice)


func _process(delta: float) -> void:
	_leaves_tick(delta)
	if _t >= 1.0:
		return
	_t = minf(_t + delta / SeasonLook.BLEND_S, 1.0)
	look = _to.duplicate(true) if _t >= 1.0 else blend(_from, _to, _t)  # (the end exactly the target: no "_mix" left over)
	_emit_left -= delta
	if _emit_left <= 0.0 or _t >= 1.0:
		_emit_left = EMIT_S
		look_changed.emit(look)
	if _t >= 1.0 and leaves == null:
		set_process(false)


## Ends a blend now (tests; screenshot scripts): the look is the target's.
func finish_blend() -> void:
	if _t >= 1.0:
		return
	_t = 1.0
	look = _to.duplicate(true)
	look_changed.emit(look)


## The leaves: tumbling quads drifting down and sideways in a box round the camera, in the look's
## crown colours (autumn's rust, ochre and green).
func _make_leaves() -> void:
	leaves = GPUParticles3D.new()
	leaves.name = "FallingLeaves"
	leaves.amount = LEAVES_MAX
	leaves.lifetime = LEAVES_LIFE_S
	leaves.local_coords = false
	leaves.emitting = false
	leaves.amount_ratio = 0.0
	leaves.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18.0, 3.0, 18.0)
	pm.direction = Vector3(0.3, -1.0, 0.1)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0.25, -0.9, 0.0)  # a leaf falls at about a metre a second, drifting downwind
	pm.damping_min = 0.3
	pm.damping_max = 0.6
	pm.angular_velocity_min = -220.0
	pm.angular_velocity_max = 220.0
	pm.particle_flag_rotate_y = true
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	ramp.colors = PackedColorArray([Color("9a5a26"), Color("b07a2e"), Color("8a7a32"), Color("a0442a")])
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	pm.color_initial_ramp = tex
	leaves.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.05)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	quad.material = m
	leaves.draw_pass_1 = quad
	leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(leaves)
	set_process(true)


## Every LEAVES_SAMPLE_S: how many leaves fall here now (the look's rate by the woods round the
## camera); the box follows the camera every frame.
func _leaves_tick(delta: float) -> void:
	if leaves == null:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		leaves.global_position = cam.global_position + Vector3.UP * 4.0
	_leaves_left -= delta
	if _leaves_left > 0.0:
		return
	_leaves_left = LEAVES_SAMPLE_S
	var rate := float(look.get("leaves", 0.0))
	var lvl := get_parent() as ZoneLevel
	if rate > 0.0 and cam and lvl and lvl.scatter:
		rate *= minf(float(lvl.scatter.broadleaf_near(cam.global_position, LEAVES_NEAR_M)) / LEAVES_FULL_TREES, 1.0)
	else:
		rate = 0.0
	leaves_rate = rate
	leaves.amount_ratio = clampf(rate * LEAVES_LIFE_S / LEAVES_MAX, 0.0, 1.0)
	leaves.emitting = rate > 0.0


## Every peer: the look to the level's land (the ground and its snow, the wild trees and grass).
func _on_look(l: Dictionary) -> void:
	var lvl := get_parent() as ZoneLevel
	if lvl == null:
		return
	if lvl.terrain:
		lvl.terrain.set_season_look(l)
	if lvl.scatter and lvl.scatter.has_method(&"set_season_look"):
		lvl.scatter.set_season_look(l)
	if lvl.terrain and lvl.terrain.water:
		lvl.terrain.water.set_season_look(l)  # (the reed beds)


## Every peer: the ice comes or goes on the level's water (walkable, the nav rebaked).
func _on_ice(on: bool) -> void:
	var lvl := get_parent() as ZoneLevel
	if lvl and lvl.terrain and lvl.terrain.water and lvl.terrain.water.has_method(&"set_ice"):
		lvl.terrain.water.set_ice(on)


## Two looks blended by `t` (0 = a, 1 = b): numbers lerp, colours lerp pairwise (an empty list,
## "keep the preset's", switches at the halfway point), anything else switches at the halfway point.
static func blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k: Variant in b:
		var va: Variant = a.get(k, b[k])
		var vb: Variant = b[k]
		if (va is float or va is int) and (vb is float or vb is int):
			out[k] = lerpf(float(va), float(vb), t)
		elif va is String and vb is String and String(va).is_valid_html_color() and String(vb).is_valid_html_color():
			out[k] = Color(String(va)).lerp(Color(String(vb)), t).to_html(false)
		elif va is Array and vb is Array and ((va as Array).is_empty() != (vb as Array).is_empty()):
			# One side keeps the preset's colours (empty): keep the palette and fade it in or out
			# by "<key>_mix" (ZoneScatter reads it), so nothing snaps at the halfway point.
			out[k] = vb if not (vb as Array).is_empty() else va
			out[str(k) + "_mix"] = t if not (vb as Array).is_empty() else 1.0 - t
		elif va is Array and vb is Array and not (va as Array).is_empty() and not (vb as Array).is_empty():
			var arr := []
			for i in (vb as Array).size():
				var ca := Color(String((va as Array)[i % (va as Array).size()]))
				arr.append(ca.lerp(Color(String((vb as Array)[i])), t).to_html(false))
			out[k] = arr
		else:
			out[k] = vb if t >= 0.5 else va
	return out
