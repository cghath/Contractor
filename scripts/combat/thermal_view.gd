class_name ThermalView
extends RefCounted
## Thermal sights (combined arms A4, cg_brief queue item 2.3; docs/combined_arms.md 2.7.4, calls
## 20 and 21): one system, local to the machine whose player looks through a thermal channel
## (VehicleSight today; cghath's thermal rifle scope, cg_brief item 8, reuses it).
##
## The cheapest way this engine allows, with no second render of the world (call 20): the scene
## is drawn as always, then
## - every hot body (living soldiers, running or burning vehicles, anything with a "thermal_heat"
##   meta) gets an additive overlay material (GeometryInstance3D.material_overlay) whose colour
##   carries its heat in a channel nothing else in the world uses (magenta: red and blue over
##   green), one shared material per HEAT_STEPS bucket;
## - a full-screen post-process (thermal_view.gdshader, on the sight's overlay) turns the frame
##   grey: the cold world's light squeezed into a dark band by the time of day (ambient), the sky
##   darker still, the heat channel bright on top; black-hot flips it.
## So walls hide what's behind them (it's the same render), ordinary smoke is transparent (its
## clouds are hidden while thermal is on), and multispectral smoke (a cloud of colour
## MULTISPECTRAL: vehicle dischargers, F-249) still blocks it.
## The global shader uniform "thermal_view" (0 off, 1 white-hot, 2 black-hot) is set too, for any
## shader that wants to read it (none needs to). Heat (2.7.4's list, per body, Proposed): a living
## soldier 0.85, a dead one 0.4; a burning vehicle 1.0, its engine running 0.7, cold 0.3, a cold
## wreck 0.35. The whole body takes one heat (the engine deck and barrel aren't hotter than the
## rest yet: F-250). Nothing here is replicated, and a headless peer only keeps the books.
##
## Cost: the overlays are set only when a body's heat bucket changes, at UPDATE_HZ; the budget
## (gunnery_test) is BUDGET_MS a frame on the CPU. The GPU's extra pass over hot bodies and the
## post-process need a windowed run to measure (F-250).

const OFF := 0
const WHITE_HOT := 1
const BLACK_HOT := 2
const MODE_NAMES := ["OFF", "WHOT", "BHOT"]
const UNIFORM := &"thermal_view"
const SOLDIER_HEAT := 0.85
const DEAD_HEAT := 0.4
const BURNING_HEAT := 1.0
const ENGINE_HEAT := 0.7
const COLD_VEHICLE_HEAT := 0.3
const WRECK_HEAT := 0.35
const META := &"thermal_heat"
## A smoke cloud of this colour blocks thermal (SmokeCloud.colour); every other is see-through.
const MULTISPECTRAL := "multispectral"
const HEAT_STEPS := 20
const UPDATE_HZ := 4.0
## Bodies further than this from the eye aren't tagged (vehicles are drawn to 3 km: 2.7.6).
const RANGE_M := 3000.0
## Proposed: the CPU budget a frame (docs/combined_arms.md 9.3: "Thermal costs under 1 ms a frame").
const BUDGET_MS := 1.0
const SHADER_PATH := "res://scripts/combat/thermal_view.gdshader"

static var mode := OFF
## The cold world's grey (0..1): 0.2 at night to 0.4 in the day (2.7.4's ground).
static var ambient := 0.3
static var last_update_ms := 0.0
static var tagged_count := 0
static var _mats := {}       # bucket -> ShaderMaterial
static var _tags := {}       # node instance id -> {"node": WeakRef, "b": bucket, "geo": [[WeakRef, previous overlay]]}
static var _hidden: Array = []  # smoke clouds hidden while thermal is on (WeakRefs)
static var _next_at := 0.0
static var _post: ShaderMaterial


## Thermal on (WHITE_HOT, BLACK_HOT) or OFF on this machine. Off puts back every overlay and
## shows the smoke again.
static func set_mode(m: int) -> void:
	m = clampi(m, OFF, BLACK_HOT)
	if m == mode:
		return
	mode = m
	_set_uniform()
	if mode == OFF:
		clear()
	else:
		_next_at = 0.0
	if _post:
		_post.set_shader_parameter(&"polarity", mode)


static func _set_uniform() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not RenderingServer.global_shader_parameter_get_list().has(UNIFORM):
		RenderingServer.global_shader_parameter_add(UNIFORM, RenderingServer.GLOBAL_VAR_TYPE_INT, mode)
	RenderingServer.global_shader_parameter_set(UNIFORM, mode)


## How hot `node` is (0..1): its "thermal_heat" meta, else by what it is.
static func heat_of(node: Node) -> float:
	if node == null or not is_instance_valid(node):
		return 0.0
	if node.has_meta(META):
		return clampf(float(node.get_meta(META)), 0.0, 1.0)
	if node is Vehicle:
		var v := node as Vehicle
		if v.is_burning():
			return BURNING_HEAT
		if v.wrecked:
			return WRECK_HEAT
		return ENGINE_HEAT if v.engine_running() else COLD_VEHICLE_HEAT
	var vitals := node.get_node_or_null(^"Vitals") as Vitals
	if vitals:
		return DEAD_HEAT if vitals.is_dead() else SOLDIER_HEAT
	return 0.0


## Each frame thermal is on (the sight calls it): at UPDATE_HZ, the bodies within RANGE_M of
## `eye` get the overlay of their heat, the ordinary smoke hidden. Returns whether it worked.
static func update(tree: SceneTree, eye: Vector3, force := false) -> bool:
	if mode == OFF or tree == null:
		return false
	var now := float(Time.get_ticks_msec()) / 1000.0
	if not force and now < _next_at:
		return false
	_next_at = now + 1.0 / UPDATE_HZ
	var t0 := Time.get_ticks_usec()
	var seen := {}
	for group: StringName in [&"combatants", Soldier.DEAD_GROUP, Vehicle.GROUP]:
		for n: Node in tree.get_nodes_in_group(group):
			var body := n as Node3D
			if body == null or not body.is_inside_tree() or seen.has(body.get_instance_id()) or body.global_position.distance_to(eye) > RANGE_M:
				continue
			var id := body.get_instance_id()
			seen[id] = true
			_tag(body, id, heat_of(body))
	for id: int in _tags.keys():
		if not seen.has(id):
			_untag(id)
	for cloud in SmokeCloud.active:
		if is_instance_valid(cloud) and cloud.visible and cloud.colour != MULTISPECTRAL:
			cloud.visible = false
			_hidden.append(weakref(cloud))
	tagged_count = _tags.size()
	last_update_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	return true


static func _tag(body: Node3D, id: int, heat: float) -> void:
	var b := clampi(roundi(heat * HEAT_STEPS), 0, HEAT_STEPS)
	var tag: Dictionary = _tags.get(id, {})
	if not tag.is_empty() and int(tag.b) == b:
		return
	if tag.is_empty():
		var geo: Array = []
		for g: Node in body.find_children("*", "GeometryInstance3D", true, false):
			geo.append([weakref(g), (g as GeometryInstance3D).material_overlay])
		tag = {"node": weakref(body), "b": b, "geo": geo}
		_tags[id] = tag
	tag.b = b
	var mat := material(b)
	for pair: Array in tag.geo:
		var g := (pair[0] as WeakRef).get_ref() as GeometryInstance3D
		if g:
			g.material_overlay = mat if b > 0 else pair[1]


static func _untag(id: int) -> void:
	var tag: Dictionary = _tags.get(id, {})
	_tags.erase(id)
	for pair: Array in tag.get("geo", []):
		var g := (pair[0] as WeakRef).get_ref() as GeometryInstance3D
		if g:
			g.material_overlay = pair[1]


## Every overlay put back, the smoke shown again.
static func clear() -> void:
	for id: int in _tags.keys():
		_untag(id)
	for w: WeakRef in _hidden:
		var cloud := w.get_ref() as Node3D
		if cloud:
			cloud.visible = true
	_hidden.clear()
	tagged_count = 0


## Whether `node`'s look carries the heat overlay now (tests).
static func tagged(node: Node) -> bool:
	return node != null and _tags.has(node.get_instance_id())


## The heat bucket `node` was drawn at (-1 not tagged; tests).
static func bucket_of(node: Node) -> int:
	return int((_tags.get(node.get_instance_id(), {}) as Dictionary).get("b", -1)) if node else -1


## The additive overlay of heat bucket `b` (shared).
static func material(b: int) -> ShaderMaterial:
	if _mats.has(b):
		return _mats[b]
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;\nuniform float heat = 0.5;\nvoid fragment() {\n\tALBEDO = vec3(heat, 0.0, heat);\n}\n"
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter(&"heat", float(b) / float(HEAT_STEPS))
	_mats[b] = m
	return m


## The full-screen post-process (a ColorRect's material on the sight's overlay).
static func post_material() -> ShaderMaterial:
	if _post == null:
		_post = ShaderMaterial.new()
		_post.shader = load(SHADER_PATH) as Shader
		_post.set_shader_parameter(&"polarity", mode)
	_post.set_shader_parameter(&"ambient", ambient)
	return _post


## Whether thermal can see from `from` to `to` through smoke (multispectral blocks it, the rest
## doesn't). Walls are the render's own business.
static func smoke_blocks(from: Vector3, to: Vector3) -> bool:
	for cloud in SmokeCloud.active:
		if is_instance_valid(cloud) and cloud.colour == MULTISPECTRAL and cloud.depth_along(from, to, SmokeCloud.BLOCK_DEPTH) >= SmokeCloud.BLOCK_DEPTH:
			return true
	return false
