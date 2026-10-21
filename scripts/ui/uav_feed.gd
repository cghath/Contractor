class_name UavFeed
extends CanvasLayer
## The recon UAV's camera on this peer's screen (UavSupport; the Captain's list, 2026-10-20: "a
## top-down camera view the caller can open"): a picture-in-picture panel at the right of the
## screen, its camera at the UAV (UavSupport.shown, from the host) looking down on the point it
## circles, in the same world (a SubViewport sharing it), so the enemies it tagged show their red
## marks (EnemyTags) in it. Opened and closed from Support > Fire support > Recon UAV > Open the
## UAV feed (FireSupport.local_command); it says so when no UAV is up and closes itself a few
## seconds after the UAV is gone. Doesn't take the mouse: the game goes on under it.

const NODE_NAME := "UavFeed"
const WIDTH := 380.0
## The camera's field of view (degrees): a zoomed sensor.
const FOV_DEG := 32.0
## Closes this long after the UAV's gone (s).
const CLOSE_AFTER_S := 4.0

var player: Soldier
var camera: Camera3D
var view: SubViewport
var _frame: SubViewportContainer
var _panel: PanelContainer
var _status: Label
var _gone_s := 0.0


## Opens the feed for `player` (or closes it when it's open).
static func toggle(p: Soldier) -> void:
	var root := p.get_tree().root
	var open := root.get_node_or_null(NODE_NAME)
	if open:
		open.queue_free()
		return
	var feed := UavFeed.new()
	feed.player = p
	root.add_child(feed)


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	layer = 4
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_panel = UiKit.panel()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.apply(_panel)
	holder.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", UiKit.SPACE_XS)
	_panel.add_child(box)
	box.add_child(UiKit.heading("UAV feed"))
	var sub := UiKit.subtitle("Straight down on the point the UAV circles. Red marks: enemies it tagged.", false)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	_frame = SubViewportContainer.new()
	_frame.stretch = true
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_frame)
	view = SubViewport.new()
	view.name = "UavView"
	view.handle_input_locally = false
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_frame.add_child(view)
	camera = Camera3D.new()
	camera.name = "UavCamera"
	camera.fov = FOV_DEG
	camera.far = 4000.0
	view.add_child(camera)
	camera.current = true
	_status = UiKit.text("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	box.add_child(UiKit.hint("Close: open it again from the menu (Support > Fire support > Recon UAV)."))
	UiKit._follow_window(_panel, _fit)
	_update(0.0)


## Width, picture height and place: right of centre, inside the window at any size.
func _fit() -> void:
	var size := _panel.get_viewport().get_visible_rect().size
	var w := maxf(minf(WIDTH, size.x - UiKit.EDGE * 2.0 - 40.0), 200.0)
	_panel.custom_minimum_size.x = w
	_frame.custom_minimum_size = Vector2(w - 24.0, clampf(size.y * 0.32, 80.0, 240.0))
	_panel.reset_size()
	_panel.position = Vector2(size.x - _panel.size.x - UiKit.EDGE, maxf((size.y - _panel.size.y) * 0.5, UiKit.EDGE))


func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	var uav := UavSupport.of(player) if is_instance_valid(player) and player.is_inside_tree() else null
	var s: Dictionary = uav.shown if uav else {}
	if s.is_empty():
		_status.text = "No UAV up: send one from Support > Fire support > Recon UAV."
		_gone_s += delta
		if _gone_s >= CLOSE_AFTER_S and uav != null:
			queue_free()
		return
	_gone_s = 0.0
	var at: Vector3 = s.pos  # (the view has no world of its own: it shows the level's)
	var centre: Vector3 = s.centre
	camera.global_position = at
	var down := centre - at
	if down.length() > 1.0:
		camera.look_at(centre, Vector3.FORWARD if absf(down.normalized().y) > 0.99 else Vector3.UP)
	var area := MapNodes.area_of(player)
	var left := int(float(s.get("left", 0.0)))
	_status.text = "%s over grid %s. %s. Tagged: %d." % ["Inbound" if String(s.state) == "inbound" else ("Leaving" if String(s.state) == "home" else "On station"),
		FireMission.grid(centre, area), "%d:%02d left" % [left / 60, left % 60] if String(s.state) == "station" else "Not on station", int(s.get("tagged", 0))]


## Where the middle of the picture meets the ground at height `ground_y` (tests).
func looking_at(ground_y: float) -> Vector3:
	var forward := -camera.global_basis.z
	if forward.y > -0.01:
		return Vector3.INF
	return camera.global_position + forward * ((camera.global_position.y - ground_y) / -forward.y)
