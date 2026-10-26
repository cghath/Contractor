class_name BuildMode
extends Node3D
## Build mode (docs/survival_building.md §4): the owner's first-person placement, DefencePlacer's
## ghost generalised. The build_mode key (Controls: 6) toggles it in a survival zone. A ghost of
## the block or piece sits at the aimed cell, snapped to the build grid, coloured by the load it
## would carry (BuildIntegrity: green, amber, red; red too where it can't go), with the cost and
## what's wrong in a small label. Everything goes to the host through Builder.ask.
##
## Keys while it's on (PlayerInput hands it every event first: handle()):
## - Use (Fire): lay a site at the ghost and work it; held, keep working the site you aim at and
##   lay the next one where the aim moves on (a line of blocks). Pieces: lay one, hold to build.
## - Wheel: turn the ghost; Shift + wheel: the next shape (or piece); Alt + wheel: the next
##   material.
## - Reload (R): blocks or pieces; Walk (P): blueprint mode (ghosts without materials, built
##   later by anyone with them: Builder's "bp" records).
## - Fire mode (F): upgrade the block you aim at to the chosen material (call 12); 4: repair it;
##   Grenade (G): dismantle the block or piece you aim at.
## - Aim (right-click) or the build key again: put it away.

const NODE_NAME := "BuildMode"
const ACTION := &"build_mode"
const REACH_M := 5.0
const WORK_SEND_S := 0.25
const CHECK_S := 0.2

var body: Soldier
var layer := "block"  # or "piece"
var mat_i := 0
var shape_i := 0
var piece_i := 0
var rot := 0
var blueprint := false
## The cell a new block or piece goes in (Vector3i.MAX for none), the built block aimed at, the
## piece aimed at (-1).
var cell := Vector3i.MAX
var aim_block := Vector3i.MAX
var aim_piece := -1
## What the ghost shows: the load (Builder.preview) and why it can't go ("" when it can).
var load_info := {}
var problem := ""
var _ghost: MeshInstance3D
var _mat: StandardMaterial3D
var _label: Label
var _send := 0.0
var _check := 0.0
var _checked := []


static func of(p_body: Node) -> BuildMode:
	return p_body.get_node_or_null(NODE_NAME) as BuildMode if p_body else null


static func is_on(p_body: Node) -> bool:
	return of(p_body) != null


## PlayerInput's hook: the build key, and every event while build mode is on. Returns whether
## it took the event.
static func handle(p_body: Soldier, event: InputEvent) -> bool:
	if event.is_action_pressed(ACTION) and not event.is_echo():
		toggle(p_body)
		return true
	var bm := of(p_body)
	return bm != null and bm._handle(event)


static func toggle(p_body: Soldier) -> void:
	var bm := of(p_body)
	if bm:
		bm.queue_free()
		p_body.player_input.flash("Build mode off")
		return
	var lvl := CompoundLevel.current(p_body)
	if lvl == null or not lvl.is_survival() or Builder.of(p_body) == null:
		p_body.player_input.flash("Nothing to build with here")
		return
	bm = BuildMode.new()
	bm.name = NODE_NAME
	bm.body = p_body
	p_body.add_child(bm)
	if DevTools.on() and not Builder.has_tool(p_body, "hammer"):
		Builder.ask(p_body, "dev_kit", [])  # (dev: a building kit until felling and stripping give materials)


func _ready() -> void:
	top_level = true
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.no_depth_test = false
	_ghost = MeshInstance3D.new()
	_ghost.mesh = BoxMesh.new()
	_ghost.material_override = _mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_label = Label.new()
	_label.add_theme_font_size_override(&"font_size", 15)
	_label.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = -360.0
	_label.offset_right = 360.0
	_label.offset_top = -170.0
	_label.offset_bottom = -110.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	canvas.add_child(_label)


func mat_key() -> String:
	return BuildPieces.MATERIAL_KEYS[mat_i]


func shape_key() -> String:
	return BuildPieces.SHAPE_KEYS[shape_i]


func piece_key() -> String:
	return BuildPieces.PIECE_KEYS[piece_i]


func _builder() -> Builder:
	return Builder.find(body)


func _handle(event: InputEvent) -> bool:
	if event.is_action_pressed(&"aim"):
		toggle(body)
		return true
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var step := 1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1
		if mb.shift_pressed:
			if layer == "block":
				shape_i = posmod(shape_i + step, BuildPieces.SHAPE_KEYS.size())
			else:
				piece_i = posmod(piece_i + step, BuildPieces.PIECE_KEYS.size())
		elif mb.alt_pressed:
			mat_i = posmod(mat_i + step, BuildPieces.MATERIAL_KEYS.size())
		else:
			rot = posmod(rot + step, 4)
		_check = 0.0
		return true
	if event.is_action_pressed(&"reload"):
		layer = "piece" if layer == "block" else "block"
		_check = 0.0
		return true
	if event.is_action_pressed(&"walk"):
		blueprint = not blueprint
		body.player_input.flash("Blueprint mode %s" % ("on: ghosts now, materials later" if blueprint else "off"))
		_check = 0.0
		return true
	if event.is_action_pressed(&"fire_mode"):
		if aim_block != Vector3i.MAX:
			Builder.ask(body, "upgrade", [aim_block, mat_key()])
		return true
	if event.is_action_pressed(&"weapon_underbarrel"):
		if aim_piece >= 0:
			Builder.ask(body, "piece_act", [aim_piece, "repair", ""])
		elif aim_block != Vector3i.MAX:
			Builder.ask(body, "repair", [aim_block])
		return true
	if event.is_action_pressed(&"grenade"):
		if aim_piece >= 0:
			Builder.ask(body, "piece_act", [aim_piece, "dismantle", ""])
		elif aim_block != Vector3i.MAX:
			Builder.ask(body, "dismantle", [aim_block])
		return true
	if event.is_action_pressed(&"fire"):
		_use(true)
		return true
	return false


## The use key: lay a site where the ghost is (pressed), or keep working what's aimed at (held).
func _use(pressed: bool) -> void:
	var b := _builder()
	if b == null:
		return
	if layer == "piece":
		var aimed := aim_piece
		if aimed >= 0 and not b.is_piece_built(aimed):
			Builder.ask(body, "work_piece", [aimed])
		elif pressed and cell != Vector3i.MAX:
			Builder.ask(body, "piece", [piece_key(), cell, rot, blueprint])
		return
	if cell == Vector3i.MAX:
		return
	var site: Dictionary = b.blocks.get(aim_block, {}) if aim_block != Vector3i.MAX else {}
	if not site.is_empty() and (float(site.prog) < 1.0 or site.has("up")) and not blueprint:
		Builder.ask(body, "work", [aim_block])
		return
	var at: Dictionary = b.blocks.get(cell, {})
	if at.is_empty():
		if pressed or problem == "":
			Builder.ask(body, "place", [cell, mat_key(), shape_key(), rot, blueprint])
		if not blueprint:
			Builder.ask(body, "work", [cell])
	elif not blueprint and (float(at.prog) < 1.0 or at.has("up")):
		Builder.ask(body, "work", [cell])


func _process(delta: float) -> void:
	if body == null or not is_instance_valid(body) or not body.vitals.is_up() or Vehicle.ride_of(body) != null:
		queue_free()
		return
	_aim()
	_check -= delta
	var key := [cell, aim_block, aim_piece, layer, mat_i, shape_i, piece_i, rot, blueprint]
	if _check <= 0.0 or key != _checked:
		_check = CHECK_S
		_checked = key
		_judge()
	_draw_ghost()
	_send -= delta
	if Input.is_action_pressed(&"fire") and _send <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_send = WORK_SEND_S
		_use(false)


## Where the camera looks: the cell a new block or piece goes in (on the ground: the cell its
## surface is in; on a block or anything else: the cell in front of the face), the built block or
## piece under the crosshair.
func _aim() -> void:
	cell = Vector3i.MAX
	aim_block = Vector3i.MAX
	aim_piece = -1
	var cam := body.camera
	if cam == null:
		return
	var from := cam.global_position
	var hit := body.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * REACH_M, 1, [body.get_rid()]))
	if hit.is_empty():
		return
	var p: Vector3 = hit.position
	var n: Vector3 = hit.normal
	var collider: Object = hit.collider
	var world := VoxelWorld.find_on(collider as Node) if collider is Node else null
	if collider is BuildPiece:
		aim_piece = (collider as BuildPiece).id
		cell = BuildPieces.cell_at(p + n * 0.25)
	elif world is BuildVoxels:
		aim_block = BuildPieces.cell_at(p - n * 0.05)
		cell = BuildPieces.cell_at(p + n * 0.25)
	elif world == null and n.y > 0.7:
		cell = Builder.ground_cell(p)
	else:
		cell = BuildPieces.cell_at(p + n * 0.25)
	var b := _builder()
	if b and aim_block == Vector3i.MAX and b.blocks.has(BuildPieces.cell_at(p - n * 0.05)):
		aim_block = BuildPieces.cell_at(p - n * 0.05)
	if b and b.blocks.has(cell) and not b.is_built(cell):
		aim_block = cell  # looking into a site's ghost: that's the one to work


func _judge() -> void:
	var b := _builder()
	load_info = {}
	problem = ""
	if b == null or cell == Vector3i.MAX:
		problem = "Look at the ground or a block"
		return
	if layer == "piece":
		problem = b.piece_problem(body, piece_key(), cell, rot, blueprint)
		return
	if b.blocks.has(cell):
		return  # a site: use works it
	problem = b.place_problem(body, cell, mat_key(), shape_key(), blueprint)
	load_info = b.preview(cell, mat_key(), shape_key(), true)


func _draw_ghost() -> void:
	_ghost.visible = cell != Vector3i.MAX
	if not _ghost.visible:
		_label.text = "Build mode: %s" % problem
		return
	var box := Vector3.ONE * BuildPieces.BLOCK_M
	var base := Vector3(cell) * BuildPieces.BLOCK_M
	var what := ""
	var cost: Array = []
	if layer == "piece":
		box = Vector3(BuildPieces.piece_size(piece_key(), rot)) * BuildPieces.BLOCK_M
		what = String(BuildPieces.PIECES[piece_key()].name)
		cost = BuildPieces.PIECES[piece_key()].cost
		_mat.albedo_color = BuildIntegrity.colour(BuildIntegrity.State.OK if problem == "" else BuildIntegrity.State.OVER)
	else:
		match shape_key():
			"half":
				box.y = 0.3
			"slab":
				box.y = 0.1
			"pillar":
				box = Vector3(0.3, 0.5, 0.3)
		what = "%s %s" % [BuildPieces.MATERIALS[mat_key()].name, String(BuildPieces.SHAPES[shape_key()].name).to_lower()]
		cost = BuildPieces.block_cost(mat_key(), shape_key())
		var state := int(load_info.get("state", BuildIntegrity.State.OK))
		if problem != "" and problem.begins_with("Not enough") == false and problem.begins_with("You need") == false:
			state = BuildIntegrity.State.OVER
		_mat.albedo_color = BuildIntegrity.colour(state)
	(_ghost.mesh as BoxMesh).size = box * 1.01
	_ghost.global_transform = Transform3D(Basis(Vector3.UP, rot * PI * 0.5), base + Vector3(BuildPieces.BLOCK_M * 0.5, box.y * 0.5, BuildPieces.BLOCK_M * 0.5)) \
		if layer == "block" else Transform3D(Basis(), base + box * 0.5)
	var load_line := ""
	if not load_info.is_empty():
		load_line = " · load_info %s (%d%%)" % [BuildIntegrity.state_name(int(load_info.state)), roundi(minf(float(load_info.ratio), 9.99) * 100.0)] \
			if int(load_info.state) != BuildIntegrity.State.FREE else " · nothing holds it"
	_label.text = "%s%s · %s%s%s\n%s\nUse: build (hold: a line) · Wheel: turn · Shift+wheel: %s · Alt+wheel: material · R: blocks/pieces · P: blueprint · F: upgrade · 4: repair · G: dismantle · Right-click: done" % [
		"Blueprint: " if blueprint else "", what, "no materials now" if blueprint else BuildPieces.cost_text(cost), load_line,
		"", problem, "shape" if layer == "block" else "piece"]
