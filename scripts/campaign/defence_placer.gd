class_name DefencePlacer
extends Node3D
## Placing a defence yourself (docs/linked_zones.md 1b / LZ-6: "placed at set slots or freely by
## the players with a placement tool (valid ground, inside the base's build area)"). Opened from
## the ops desk's "Place it yourself" (BaseUI): a see-through block the size of the defence follows
## the ground under the crosshair, snapped to the zones' grid (ZoneDef.GRID_M: defences are
## modules), green where it can go and red where it can't (BaseFob.placement_problem, the host's
## own check). Enter places it (BaseHub request "place_defence": paid then, the base reloads with
## it), Esc puts it away. This peer only; one at a time.

const NODE_NAME := "DefencePlacer"
const REACH_M := 150.0
const GHOST_H := 1.6
const OK := Color(0.35, 0.85, 0.4, 0.35)
const BAD := Color(0.9, 0.3, 0.25, 0.35)
const HINT_S := 2.5

var id := ""
## The cell under the crosshair now (zone metres, x and z), and why it can't go there ("" if it can).
var at := Vector2.INF
var problem := "Look at the ground"
var _ghost: MeshInstance3D
var _mat: StandardMaterial3D
var _hint := 0.0


## Opens the tool for defence `p_id` in the level `from` is in. Returns it, or null.
static func start(from: Node, p_id: String) -> DefencePlacer:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	if lvl == null or not BaseFob.DEFENCES.has(p_id):
		return null
	var old := lvl.get_node_or_null(NODE_NAME)
	if old:
		old.free()
	var p := DefencePlacer.new()
	p.name = NODE_NAME
	p.id = p_id
	lvl.add_child(p)
	return p


func _ready() -> void:
	var half: Array = BaseFob.DEFENCES[id].half
	var box := BoxMesh.new()
	box.size = Vector3(float(half[0]) * 2.0, GHOST_H, float(half[1]) * 2.0)
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = BAD
	_ghost = MeshInstance3D.new()
	_ghost.mesh = box
	_ghost.material_override = _mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var hit := {}
	if cam:
		var from := cam.global_position
		hit = get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * REACH_M, 1))
	if hit.is_empty():
		at = Vector2.INF
		problem = "Look at the ground"
		_ghost.visible = false
	else:
		var p: Vector3 = hit.position
		at = Vector2(snappedf(p.x, ZoneDef.GRID_M), snappedf(p.z, ZoneDef.GRID_M))
		problem = BaseFob.placement_problem(id, at, BaseHub.base().get("defences", []))
		var lvl := CompoundLevel.current(self)
		var ground: Vector3 = lvl.ground_point(Vector3(at.x, 0.0, at.y)) if lvl and lvl.has_method(&"ground_point") else Vector3(at.x, p.y, at.y)
		_ghost.global_position = ground + Vector3.UP * GHOST_H * 0.5
		_ghost.visible = true
		_mat.albedo_color = OK if problem == "" else BAD
	_hint -= delta
	if _hint <= 0.0:
		_hint = HINT_S
		var me := MapNodes.local_player(self)
		var hud: Variant = me.get(&"_hud") if me else null
		if hud is Object and (hud as Object).has_method(&"flash"):
			(hud as Object).call(&"flash", "%s: Enter to place it%s, Esc to put it away" % [String(BaseFob.DEFENCES[id].name), "" if problem == "" else " (%s)" % problem])


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		get_viewport().set_input_as_handled()
		if problem == "" and at.is_finite():
			BaseHub.request("place_defence", [id, at.x, at.y])
			queue_free()
