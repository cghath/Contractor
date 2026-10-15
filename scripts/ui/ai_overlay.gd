class_name AiOverlay
extends Node3D
## Dev tools only (DevTools.on), on the host (docs/debugging.md, "Planned" 3): Delete toggles a
## label over every AI soldier within RANGE_M (the nearest MAX_LABELS): SquadAI's intent and
## status, its target, combat mode and suppression, and a line to where it is heading. Refreshed
## REFRESH_S apart; labels follow their soldiers every frame.

const RANGE_M := 80.0
## Thinned out (Captain, 2026-10-14: "all the UIs need a pass"; docs/ui_audit.md P2-22, branch
## ui/small-screens): up to 16 three-line labels piled up over the squad. Now the nearest
## MAX_LABELS get one, only the nearest DETAIL_LABELS get all three lines (the rest just intent
## and status), and the farther labels are smaller and fainter.
const MAX_LABELS := 8
const DETAIL_LABELS := 3
const FONT_NEAR := 26
const FONT_FAR := 20
const FAR_ALPHA := 0.65
const REFRESH_S := 0.25
const KEY := KEY_DELETE

var shown := false
## Soldier -> Label3D, for the AI in range at the last refresh.
var labels := {}
var _lines: MeshInstance3D
var _mesh := ImmediateMesh.new()
var _refresh := 0.0


func _init() -> void:
	name = "AiOverlay"
	top_level = true


func _ready() -> void:
	_lines = MeshInstance3D.new()
	_lines.mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.vertex_color_use_as_albedo = true
	_lines.material_override = mat
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)
	set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY and DevTools.on() \
			and multiplayer.is_server():
		get_viewport().set_input_as_handled()
		set_shown(not shown)


func set_shown(on: bool) -> void:
	shown = on
	set_process(on)
	_refresh = 0.0
	if not on:
		clear()


func clear() -> void:
	for l: Label3D in labels.values():
		l.queue_free()
	labels.clear()
	_mesh.clear_surfaces()


func _process(delta: float) -> void:
	for s: Soldier in labels:
		if is_instance_valid(s):
			labels[s].global_position = s.global_position + Vector3(0, 2.3, 0)
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_S
		refresh()


## Rebuilds the labels and heading lines for the AI near the local player (or the camera).
func refresh() -> void:
	var viewer := get_viewport().get_camera_3d()
	var origin := viewer.global_position if viewer else Vector3.ZERO
	var near: Array[Soldier] = []
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.is_inside_tree() and s.is_ai() and s.vitals.is_up() and s.global_position.distance_to(origin) <= RANGE_M:
			near.append(s)
	near.sort_custom(func(a: Soldier, b: Soldier) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	near = near.slice(0, MAX_LABELS)
	for s in labels.keys():
		if not near.has(s):
			if is_instance_valid(labels[s]):
				labels[s].queue_free()
			labels.erase(s)
	_mesh.clear_surfaces()
	var drawing := false
	for rank in near.size():
		var s := near[rank]
		var ai := SquadAI.of(s)
		if ai == null:
			continue
		var label: Label3D = labels.get(s)
		if label == null:
			label = Label3D.new()
			label.top_level = true
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.fixed_size = true
			label.pixel_size = 0.0007
			label.outline_size = 8
			add_child(label)
			labels[s] = label
			label.global_position = s.global_position + Vector3(0, 2.3, 0)
		var detail := rank < DETAIL_LABELS
		label.text = text_for(s, ai) if detail else headline(ai)
		label.font_size = FONT_NEAR if detail else FONT_FAR
		label.modulate = Color(1, 0.5, 0.4) if ai.intent == SquadAI.Intent.FIGHT else Color(0.8, 1, 0.8)
		if not detail:
			label.modulate.a = FAR_ALPHA
		var dest := ai.destination()
		if dest.is_finite():
			if not drawing:
				_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
				drawing = true
			_mesh.surface_set_color(Color(1, 1, 0.3))
			_mesh.surface_add_vertex(s.global_position + Vector3(0, 1.0, 0))
			_mesh.surface_add_vertex(dest + Vector3(0, 0.2, 0))
	if drawing:
		_mesh.surface_end()


## The first line, all a farther AI's label shows: its intent and status.
static func headline(ai: SquadAI) -> String:
	return "%s: %s" % [SquadAI.Intent.keys()[ai.intent], ai.status_text()]


static func text_for(s: Soldier, ai: SquadAI) -> String:
	var lines: Array[String] = [headline(ai)]
	lines.append("target %s; %s; suppr %.1f" % [ai.target.display_name() if is_instance_valid(ai.target) else "none",
		Squad.CombatMode.keys()[ai.combat_mode], s.suppression])
	# What it's half-spotted (SquadAI._aware, Spotting: 1 is a full spot) and, in a hot zone, the
	# alert state a hostile acts on (Alert.state_at).
	var top := 0.0
	var who := ""
	for id: int in ai._aware:
		var a: float = ai._aware[id]
		var other := instance_from_id(id) as Soldier
		if a > top and other != null and is_instance_valid(other):
			top = a
			who = other.display_name()
	var third := "aware %.2f %s" % [top, who] if top > 0.0 else "aware none"
	var alert := Alert.of(s) if s.faction == &"hostile" else null
	if alert:
		third += "; alert %s" % Alert.State.keys()[alert.state_at(s.global_position)]
	lines.append(third)
	return "\n".join(lines)
