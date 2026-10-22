class_name HcCamera
extends Node3D
## The 3D high command camera (docs/combined_arms.md 5.3): a free RTS camera over the live zone,
## entered with `high_command` (Shift+M on foot; the map panel's "3D view" button) and left the
## same way or with Escape. Local to this peer: nothing about it replicates.
##
## - Controls: WASD or the screen's edge pans, the wheel zooms (MIN_AGL_M to MAX_AGL_M over the
##   ground), middle-drag orbits, Q / E rotate, F frames the selection, a click on a squad's marker
##   selects it (Shift adds), a double-click follows it. Never under MIN_AGL_M or off the zone.
## - What it shows: the terrain and buildings as they are, friendly markers at their true
##   positions (HighCommand's view: callsign, strength, CE pip on a pole), their orders draped on
##   the ground, and enemies only from what our side reported (MapMarkers' "enemy" and "spot"
##   markers, with their uncertainty rings). What it hides: every actor (soldiers, vehicles,
##   people and bodies are hidden on this peer while it's up, so an enemy nobody reported isn't
##   there to see however close it gets). It never joins the zone's stream focus, so flying it
##   somewhere spawns nothing.
## - Orders: the commander gives the map's orders from here with the same keys (M, D, A, S, B, F,
##   H, R, X, Y), a click on the ground to place, a drag to face, Shift to queue, right-click to
##   cancel, Ctrl+Z to undo. Other players watch read-only.
## - The body stays where it was; a hit or a near miss shows a red edge, and (the setting, on by
##   default) a hit drops you straight back.
## - Map mode (the 3D mission map, 5.3): the same camera over a relief built from the zone's
##   heights and its map picture (open_map_mode), in its own world inside a SubViewport, with the
##   briefing's objectives, insertion points and known enemies standing on it.

const NODE_NAME := "HcCamera"
const ACTION := &"high_command"
const MIN_AGL_M := 40.0
const MAX_AGL_M := 1500.0
const PAN_SPEED := 0.9  # x the height, a second
const EDGE_PX := 10.0
const ROTATE_DEG_S := 90.0
const POLE_M := 30.0
const MARKERS_S := 0.25
const HIDE_S := 0.5
const PICK_PX := 24.0
## A hit, or this much suppression, on the body: the red edge (and back, by the setting).
const SUPPRESS_EDGE := 0.35
const RELIEF_CELLS := 96
## What a peer had hidden itself is left as it was: only what this camera hid comes back.
const ACTOR_GROUPS: Array[StringName] = [&"combatants", Vehicle.GROUP, Soldier.DEAD_GROUP]

## Drop straight back to the body when it's hit (a setting; on by default).
static var back_when_hit := true

var body: Soldier
var cam: Camera3D
var map_mode := false
var focus := Vector3.ZERO
var yaw := 0.0
var pitch := deg_to_rad(-55.0)
var agl := 300.0
var follow_id := ""
var selected := PackedStringArray()
var placing := ""
var area := Rect2()
var _prev_cam: Camera3D
var _hidden := {}  # node -> its visible before
var _markers: Node3D
var _marker_left := 0.0
var _hide_left := 0.0
var _orbiting := false
var _press := Vector3.INF
var _press_screen := Vector2.INF
var _health0 := -1.0
var _edge: ColorRect
var _help: Label
var _hint: Label
var _layer: CanvasLayer
var _height := Callable()
var _map_view: SubViewport  # map mode: the relief's own world


static func of(from: Node) -> HcCamera:
	var lvl := MapNodes.level_of(from)
	return lvl.get_node_or_null(NodePath(NODE_NAME)) as HcCamera if lvl else null


## The local player opens the camera over the live zone, or closes it.
static func toggle(player: Soldier) -> HcCamera:
	var existing := of(player)
	if existing:
		existing.close()
		return null
	var lvl := MapNodes.level_of(player)
	if lvl == null:
		return null
	var c := HcCamera.new()
	c.name = NODE_NAME
	c.body = player
	lvl.add_child(c)
	c.open()
	return c


func open() -> void:
	area = MapNodes.area_of(self)
	_height = _height_fn(MapNodes.level_of(self))
	cam = Camera3D.new()
	cam.far = 6000.0
	add_child(cam)
	focus = body.global_position if body else Vector3(area.get_center().x, 0.0, area.get_center().y)
	yaw = body.rotation.y if body else 0.0
	_prev_cam = get_viewport().get_camera_3d()
	cam.make_current()
	_markers = Node3D.new()
	add_child(_markers)
	_build_hud()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_health0 = _health()
	if not map_mode:
		hide_actors()
	_place()
	_rebuild_markers()


func close() -> void:
	show_actors()
	if is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	elif body and is_instance_valid(body.camera):
		body.camera.make_current()
	if _layer:
		_layer.queue_free()
	if not map_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()


## Hides every actor on this peer (5.3: the camera sees markers, never the actors themselves).
func hide_actors() -> void:
	for g: StringName in ACTOR_GROUPS:
		for n in get_tree().get_nodes_in_group(g):
			var v := n as Node3D
			if v and v.visible and not _hidden.has(v):
				_hidden[v] = true
				v.visible = false


func show_actors() -> void:
	for v: Variant in _hidden:
		if is_instance_valid(v):
			(v as Node3D).visible = true
	_hidden.clear()


## Whether node `n` would be drawn by this camera (tests: actors never are).
func shows(n: Node3D) -> bool:
	return n.is_visible_in_tree()


# --- Moving --------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if cam == null:
		return
	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) and placing == "": move.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) and placing == "": move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) and placing == "": move.x += 1.0
	if Input.is_physical_key_pressed(KEY_Q): yaw += deg_to_rad(ROTATE_DEG_S) * delta
	if Input.is_physical_key_pressed(KEY_E): yaw -= deg_to_rad(ROTATE_DEG_S) * delta
	var vp := get_viewport()
	var m := vp.get_mouse_position()
	var rect := vp.get_visible_rect()
	if rect.size.x > 0.0 and not _orbiting and DisplayServer.window_is_focused():
		if m.x <= EDGE_PX: move.x -= 1.0
		elif m.x >= rect.size.x - EDGE_PX: move.x += 1.0
		if m.y <= EDGE_PX: move.y -= 1.0
		elif m.y >= rect.size.y - EDGE_PX: move.y += 1.0
	if move != Vector2.ZERO:
		follow_id = ""
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		focus += (right * move.x - fwd * move.y).normalized() * agl * PAN_SPEED * delta
	if follow_id != "":
		var e := _status(follow_id)
		if not e.is_empty():
			focus = Vector3(float(e.pos[0]), focus.y, float(e.pos[1]))
	_place()
	_marker_left -= delta
	if _marker_left <= 0.0:
		_marker_left = MARKERS_S
		_rebuild_markers()
	_hide_left -= delta
	if _hide_left <= 0.0 and not map_mode:
		_hide_left = HIDE_S
		hide_actors()  # (new spawns and arrivals)
	_watch_body()


## Puts the camera where focus, yaw, pitch and agl say, kept over the ground and inside the zone.
func _place() -> void:
	if area.size.x > 0.0:
		focus.x = clampf(focus.x, area.position.x, area.end.x)
		focus.z = clampf(focus.z, area.position.y, area.end.y)
	focus.y = ground(focus.x, focus.z)
	agl = clampf(agl, MIN_AGL_M, MAX_AGL_M)
	var back := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
	var pos := focus + back * (agl / maxf(-sin(pitch), 0.2))
	pos.y = maxf(pos.y, ground(pos.x, pos.z) + MIN_AGL_M)
	if area.size.x > 0.0:
		pos.x = clampf(pos.x, area.position.x, area.end.x)
		pos.z = clampf(pos.z, area.position.y, area.end.y)
	cam.global_position = pos
	if pos.distance_to(focus) > 0.5:
		var dir := (focus - pos).normalized()
		cam.look_at(focus, Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3(-sin(yaw), 0.0, -cos(yaw)))  # (straight down: up is the view's forward)


func ground(x: float, z: float) -> float:
	return float(_height.call(x, z)) if _height.is_valid() else 0.0


func height_above_ground() -> float:
	return cam.global_position.y - ground(cam.global_position.x, cam.global_position.z) if cam else 0.0


static func _height_fn(lvl: Node) -> Callable:
	var terrain: Variant = lvl.get(&"terrain") if lvl else null
	if terrain is ZoneTerrain:
		return func(x: float, z: float) -> float: return (terrain as ZoneTerrain).height_at(x, z)
	return func(_x: float, _z: float) -> float: return 0.0


## The ground point under screen point `s` (marching the view ray down to the terrain).
func ground_at(s: Vector2) -> Vector3:
	var from := cam.project_ray_origin(s)
	var dir := cam.project_ray_normal(s)
	var t := 0.0
	var step := 5.0
	for i in 1200:
		var p := from + dir * t
		if p.y <= ground(p.x, p.z):
			return Vector3(p.x, ground(p.x, p.z), p.z)
		t += step
		step = minf(step * 1.01, 25.0)
	return Vector3.INF


# --- Input ---------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if map_mode:
		return  # (the briefing's own buttons close the 3D map)
	if event.is_action_pressed(ACTION) or (event.is_action_pressed(&"pause") and placing == ""):
		close()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if cam == null:
		return
	if event is InputEventMouseButton:
		_mouse(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _orbiting:
		yaw -= event.relative.x * 0.005
		pitch = clampf(pitch - event.relative.y * 0.005, deg_to_rad(-88.0), deg_to_rad(-15.0))
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if _key(event):
			get_viewport().set_input_as_handled()


func _mouse(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			agl /= 1.15
		MOUSE_BUTTON_WHEEL_DOWN:
			agl *= 1.15
		MOUSE_BUTTON_MIDDLE:
			_orbiting = e.pressed
		MOUSE_BUTTON_RIGHT:
			if e.pressed and placing != "":
				placing = ""
				_hint_text("Cancelled")
		MOUSE_BUTTON_LEFT:
			if placing != "" and _commander():
				var g := ground_at(e.position)
				if e.pressed:
					_press = g
					_press_screen = e.position
				elif _press.is_finite():
					var facing := Vector2(g.x - _press.x, g.z - _press.z) if (e.position - _press_screen).length() > MapCommandLayer.DRAG_PX else Vector2.ZERO
					order_at(placing, _press, e.shift_pressed, facing.normalized())
					_press = Vector3.INF
			elif e.pressed:
				var id := marker_at(e.position)
				if id != "":
					if e.double_click:
						follow_id = id
					elif e.shift_pressed:
						if id not in selected:
							selected.append(id)
					else:
						selected = PackedStringArray([id])
					_rebuild_markers()


func _key(e: InputEventKey) -> bool:
	if e.keycode == KEY_F:
		frame_selection()
		return true
	if e.keycode == KEY_ESCAPE and placing != "":
		placing = ""
		return true
	if not _commander():
		return false
	if e.keycode == KEY_Z and e.ctrl_pressed:
		for id in selected:
			HighCommand.of(self).request_undo(id)
		return true
	for b: Array in MapCommandLayer.BAR:
		if e.keycode == b[2] and String(b[0]) not in ["gun", "defend_frontage", "sbf"]:
			if selected.is_empty():
				_hint_text("Select a squad first (click its marker)")
				return true
			if bool(b[3]):
				placing = String(b[0])
				_hint_text("%s: click the ground, drag to face" % b[1])
			else:
				for id in selected:
					MapCommandLayer.send(HighCommand.of(self), id, String(b[0]), Vector2.INF)
			return true
	return false


## Gives `verb` to the selection at ground point `at` (the tests' way in too).
func order_at(verb: String, at: Vector3, queue := false, facing := Vector2.ZERO) -> void:
	if not at.is_finite() or not area.has_point(Vector2(at.x, at.z)):
		_hint_text("Off the map")
		return
	for id in selected:
		MapCommandLayer.send(HighCommand.of(self), id, verb, Vector2(at.x, at.z), queue, facing)
	_hint_text("%s -> %s" % [verb, MapGrid.grid_ref(Vector2(at.x, at.z), area, 6)])
	if not queue:
		placing = ""


func frame_selection() -> void:
	if selected.is_empty():
		return
	var c := Vector2.ZERO
	var n := 0
	for id in selected:
		var e := _status(id)
		if not e.is_empty():
			c += Vector2(float(e.pos[0]), float(e.pos[1]))
			n += 1
	if n > 0:
		focus = Vector3(c.x / n, 0.0, c.y / n)
		agl = 250.0


## The group whose marker is under screen point `s`, or "".
func marker_at(s: Vector2) -> String:
	var best := ""
	var best_d := PICK_PX
	var hc := HighCommand.of(self)
	if hc == null:
		return ""
	for e: Dictionary in hc.view:
		var p := Vector3(float(e.pos[0]), 0.0, float(e.pos[1]))
		p.y = ground(p.x, p.z) + POLE_M
		if cam.is_position_behind(p):
			continue
		var d := cam.unproject_position(p).distance_to(s)
		if d < best_d:
			best_d = d
			best = String(e.id)
	return best


func _commander() -> bool:
	var hc := HighCommand.of(self)
	return hc != null and hc.is_commander() and not map_mode


func _status(id: String) -> Dictionary:
	var hc := HighCommand.of(self)
	return hc.status(id) if hc else {}


# --- Markers -------------------------------------------------------------------------------------

## Friendly markers at their true positions, enemies only from our side's reports (5.3).
func _rebuild_markers() -> void:
	for c in _markers.get_children():
		c.queue_free()
	var hc := HighCommand.of(self)
	if hc:
		for e: Dictionary in hc.view:
			var colour := MapCommandLayer.ALLIED if String(e.get("kind", "")) == "allied" else MapCommandLayer.COLOUR
			var p := Vector3(float(e.pos[0]), 0.0, float(e.pos[1]))
			p.y = ground(p.x, p.z)
			var sel := String(e.id) in selected
			_pole(p, MapCommandLayer.SELECTED if sel else colour, "%s %d/%d\n%s" % [String(e.callsign).to_upper(), int(e.up), int(e.total),
				String(e.get("order", {}).get("verb", "idle"))], MapCommandLayer.CE_COLOURS.get(String(e.get("band", "green")), Color.WHITE))
			var pts: Array = e.get("order", {}).get("points", [])
			if not pts.is_empty() and String(e.order.get("state", "")) not in ["done", "cancelled"]:
				var line: Array[Vector3] = [p]
				for q: Variant in pts:
					line.append(Vector3(float(q[0]), 0.0, float(q[1])))
				_draped(line, colour)
	for m: Dictionary in known_enemies():
		var colour: Color = m.colour
		_pole(m.pos, colour, String(m.label), colour, 0.6)
		_ring(m.pos, float(m.unc), colour)
	for p: Dictionary in _extra:
		_pole(p.pos, p.colour, String(p.label), p.colour, 0.8)


## Map mode's extra markers (objectives, insertion points): [{"pos", "label", "colour"}].
var _extra: Array = []


## Enemies as our side knows them, from the map's markers only (every peer has these): [{"pos",
## "label", "unc", "colour"}]. Never a true position (the fairness rule, 5.3).
func known_enemies() -> Array:
	var out: Array = []
	var marks := MapNodes.markers(self)
	if marks == null:
		return out
	for m: Dictionary in marks.markers.values():
		var kind := String(m.get("kind", ""))
		var pts: PackedVector2Array = m.get("points", PackedVector2Array())
		if pts.is_empty() or kind not in ["enemy", "spot"]:
			continue
		var unc := 25.0
		var colour := Color(0.95, 0.25, 0.2)
		var label := String(m.get("text", "enemy"))
		if kind == "spot" and m.has("spot"):
			unc = MapMarkers.spot_unc(m)
			var band := MapMarkers.spot_band(m)
			colour.a = {"fresh": 1.0, "aged": 0.7, "stale": 0.4}.get(band, 0.7)
			label = "%s (%s)" % [String(m.spot.get("what", "enemy")), band]
		var p := Vector3(pts[0].x, 0.0, pts[0].y)
		p.y = ground(p.x, p.z)
		out.append({"pos": p, "label": label, "unc": unc, "colour": colour})
	return out


func _pole(at: Vector3, colour: Color, text: String, pip: Color, scale := 1.0) -> void:
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = colour
	mat.no_depth_test = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	mesh.surface_add_vertex(at)
	mesh.surface_add_vertex(at + Vector3.UP * POLE_M * scale)
	mesh.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_markers.add_child(mi)
	var label := Label3D.new()
	label.text = text
	label.modulate = colour
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0015
	label.font_size = 28
	label.position = at + Vector3.UP * POLE_M * scale
	_markers.add_child(label)
	var dot := Label3D.new()
	dot.text = "●"
	dot.modulate = pip
	dot.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dot.no_depth_test = true
	dot.fixed_size = true
	dot.pixel_size = 0.0015
	dot.font_size = 28
	dot.position = at + Vector3.UP * (POLE_M * scale + 2.0)
	dot.offset = Vector2(-60, 0)
	_markers.add_child(dot)


## A line draped on the ground through `points` (sampled every 10 m, 1 m up).
func _draped(points: Array[Vector3], colour: Color) -> void:
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = colour
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var n := maxi(int(Vector2(b.x - a.x, b.z - a.z).length() / 10.0), 1)
		for k in n + 1:
			var t := float(k) / n
			var x := lerpf(a.x, b.x, t)
			var z := lerpf(a.z, b.z, t)
			mesh.surface_add_vertex(Vector3(x, ground(x, z) + 1.0, z))
	mesh.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	_markers.add_child(mi)


func _ring(at: Vector3, radius: float, colour: Color) -> void:
	var pts: Array[Vector3] = []
	for k in 33:
		var a := TAU * k / 32.0
		pts.append(at + Vector3(cos(a), 0.0, sin(a)) * radius)
	_draped(pts, colour)


# --- The body, and the HUD -----------------------------------------------------------------------

func _health() -> float:
	return -body.vitals.injury() if body and is_instance_valid(body) else 0.0  # (falls when he's hit)


func _watch_body() -> void:
	if body == null or map_mode or not is_instance_valid(body):
		return
	var hit := _health() < _health0 - 0.001 or not body.vitals.is_up()
	var danger := hit or body.suppression >= SUPPRESS_EDGE
	_edge.visible = danger
	if hit and back_when_hit:
		close()


func _build_hud() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	_edge = ColorRect.new()
	_edge.color = Color(0.9, 0.1, 0.1, 0.25)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge.visible = false
	_layer.add_child(_edge)
	_help = UiKit.hint("WASD / edges: pan   wheel: zoom   middle-drag: orbit   Q / E: rotate   F: frame   click: select   double-click: follow   Shift+M or Esc: back to your body")
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_help.offset_top = -40
	_layer.add_child(_help)
	_hint = UiKit.text("")
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_top = 16
	_layer.add_child(_hint)


func _hint_text(t: String) -> void:
	if _hint:
		_hint.text = t


# --- Map mode: the 3D mission map ----------------------------------------------------------------

## The 3D mission map (5.3, map mode): a relief of `level`'s zone (its heights and its map
## picture) in its own world inside a SubViewport, the same camera over it, with `marks`
## ([{"pos": Vector3, "label", "colour"}]: the briefing's objectives, insertion, known enemies).
## Returns the SubViewportContainer to show (the briefing's "3D" button).
static func open_map_mode(level: Node, marks: Array) -> SubViewportContainer:
	var box := SubViewportContainer.new()
	box.stretch = true
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.handle_input_locally = true
	box.add_child(sv)
	var c := HcCamera.new()
	c.name = NODE_NAME
	c.map_mode = true
	c.area = level.call(&"map_area") if level and level.has_method(&"map_area") else Rect2(-512, -512, 1024, 1024)
	c._height = _height_fn(level)
	c._extra = marks
	c._map_view = sv
	sv.add_child(c)
	sv.add_child(relief(level, c.area, c._height))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	sv.add_child(light)
	c.ready.connect(func() -> void:
		c.cam = Camera3D.new()
		c.cam.far = 8000.0
		c.add_child(c.cam)
		c.cam.make_current()
		c._markers = Node3D.new()
		c.add_child(c._markers)
		c.focus = Vector3(c.area.get_center().x, 0.0, c.area.get_center().y)
		c.agl = maxf(c.area.size.x, c.area.size.y) * 0.6
		c._build_hud()
		c._edge.visible = false
		c._place()
		c._rebuild_markers(), CONNECT_ONE_SHOT)
	return box


## A RELIEF_CELLS x RELIEF_CELLS mesh of the zone's heights, its map picture as the albedo.
static func relief(level: Node, area: Rect2, height: Callable) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := RELIEF_CELLS
	for j in n:
		for i in n:
			var quad := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]
			for q: Array in quad:
				var u := float(q[0]) / n
				var v := float(q[1]) / n
				var x := area.position.x + u * area.size.x
				var z := area.position.y + v * area.size.y
				st.set_uv(Vector2(u, v))
				st.add_vertex(Vector3(x, float(height.call(x, z)), z))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	var img := MapRender.render(level) if level else null
	if img:
		mat.albedo_texture = ImageTexture.create_from_image(img)
	else:
		mat.albedo_color = Color(0.45, 0.5, 0.38)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	return mi
