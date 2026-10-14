extends Node
## The map, briefing, extraction and reinforcement timer (W13): grid references, the map
## picture and view on the compound and on a 2 km zone, shared markers and the briefing over
## real ENet (a client that joins during the briefing and one that joins late, both started
## by this test as separate processes), extraction (only with the squad inside, the report
## of who and what got out, purple smoke and grid points) and the reinforcement waves.
##   <voxel godot exe> --headless --path . res://tests/map_test.tscn
## Exits with the number of failures (the clients' included). A client is the same scene
## run with `-- --join 127.0.0.1 --client <A|B>`; it reports its checks back by RPC.

## The briefing's stand-in contract and zone for this test.
const CONTRACT := {
	"id": "test_contract", "title": "Test: recover the case", "type": "hvt_capture", "difficulty": 3,
	"summary": "A test contract.",
	"objectives": [{"id": "case", "title": "Recover the case", "pos": [0.0, -10.0], "radius": 4.0}],
	"known_enemies": [{"pos": [0.0, -8.0], "text": "Guards"}, {"pos": [-11.0, -2.0], "text": "Patrol"}],
	"reinforcements": {"first_wave_s": 3600.0},  # not during this test's own checks
}
const ZONE := {
	"id": "test_zone", "name": "Compound", "kind": "contract",
	"insertion_points": [
		{"id": "south", "name": "South road", "pos": [0.0, 30.0], "method": "foot"},
		{"id": "east", "name": "East field", "pos": [32.0, 4.0], "method": "foot"},
		{"id": "west", "name": "West field", "pos": [-32.0, 4.0], "method": "foot"},
	],
	"extraction_points": [{"name": "LZ South", "pos": [0.0, 34.0], "radius": 12.0}],
}
const INSERT_EAST := Vector2(32.0, 4.0)
## The host's markers before the first client joins, and where the host then moves one.
const HQ_AT := Vector2(1.0, -9.0)
const HQ_MOVED := Vector2(6.0, -12.0)
const CLIENT_WAIT_S := 45.0

var failures := 0
var level: CompoundLevel
var player: Soldier
## Host: what each client reported, by stage ("a1", "a2", "b1").
var _reports := {}
var _pids: Array[int] = []
## Client: which tag it runs as, and the stage the host said to go on to.
var _tag := ""
var _go := ""
var _lines := PackedStringArray()
## Reports handed to the deployment-end handler (this node is in Extraction.END_GROUP).
var _ended: Array[Dictionary] = []


func _ready() -> void:
	var suffix := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_map" + suffix  # never touch a real save
	Campaign.campaign_id = "test_map" + suffix
	var args := OS.get_cmdline_user_args()
	if "--client" in args:
		_tag = args[args.find("--client") + 1] if args.find("--client") + 1 < args.size() else "?"
		CompoundLevel.spawn_ai = true
		add_child(load("res://scenes/main.tscn").instantiate())  # main reads --join
		await get_tree().process_frame
		level = CompoundLevel.current(self)
		get_tree().create_timer(90.0).timeout.connect(func() -> void: get_tree().quit(98))
		await _run_client()
		return
	GameState.delete_save()
	CompoundLevel.spawn_ai = true
	get_tree().create_timer(400.0).timeout.connect(func() -> void:
		print("MAP TEST FAILED (timed out)")
		_kill_clients()
		get_tree().quit(99))
	add_to_group(Extraction.END_GROUP)
	_test_grid()
	await _test_large_map()
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	$Main/Menu.host()
	level = CompoundLevel.current(self)
	while level.ai.get_node_or_null(^"Golf") == null:
		await get_tree().process_frame
	player = level.players.get_node(^"1")
	player.set_physics_process(false)  # the test places the player by hand
	_test_render()
	await _test_map_contents()
	await _test_briefing_and_markers()
	await _test_extraction()
	await _test_reinforcements()
	_kill_clients()
	GameState.delete_save()
	print("MAP TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	var line := "  [%s] %s" % ["ok" if condition else "FAIL", what]
	if _tag != "":
		line = "  [%s] client %s: %s" % ["ok" if condition else "FAIL", _tag, what]
		_lines.append(line)
	print(line)
	if not condition:
		failures += 1


# --- Grid references and the map view ----------------------------------------------

func _test_grid() -> void:
	print("Grid references")
	var compound := Rect2(-22, -22, 44, 44)
	check(MapGrid.grid_ref(Vector2(-22, 22), compound) == "0000 0000", "the south-west corner is 0000 0000")
	var p := Vector2(-22 + 12.3, 22 - 34.5)
	check(MapGrid.grid_ref(p, compound) == "0001 0003" and MapGrid.grid_ref(p, compound, 5) == "00012 00034" and MapGrid.grid_ref(p, compound, 3) == "000 000",
		"12.3 m east, 34.5 m north: 0001 0003 (10 m), 00012 00034 (1 m), 000 000 (100 m) (%s)" % MapGrid.grid_ref(p, compound))
	check(MapGrid.grid_ref(Vector2(21.9, -21.9), compound) == "0004 0004", "the north-east corner of 44 m is 0004 0004")
	var big := Rect2(-1000, -1000, 2000, 2000)
	var q := Vector2(234.5, -567.8)  # 1234.5 m east, 1567.8 m north of the south-west corner
	check(MapGrid.grid_ref(q, big, 3) == "012 015" and MapGrid.grid_ref(q, big) == "0123 0156" and MapGrid.grid_ref(q, big, 5) == "01234 01567",
		"on a 2 km map: 012 015, 0123 0156, 01234 01567 (%s)" % MapGrid.grid_ref(q, big))
	var centre: Variant = MapGrid.parse("0123 0156", big)
	check(centre is Vector2 and (centre as Vector2).distance_to(Vector2(235, -565)) < 0.01 and MapGrid.parse("01230156", big) == centre,
		"a reference parses to the centre of its square (%s)" % [centre])
	check(MapGrid.parse("12 3", big) == null and MapGrid.parse("abc def", big) == null and MapGrid.parse("", big) == null, "and nonsense doesn't parse")
	var back: Vector2 = MapGrid.parse(MapGrid.grid_ref(q, big), big)
	check(absf(back.x - q.x) <= 5.0 and absf(back.y - q.y) <= 5.0, "a point and its reference's centre are within half a square")
	check(MapGrid.line_spacing(0.414) == 100.0 and MapGrid.line_spacing(24.0) == 10.0 and MapGrid.line_spacing(0.03) == 1000.0 and MapGrid.line_spacing(50.0) == 1.0,
		"grid lines: 100 m zoomed out on 2 km, 10 m zoomed in, 1 km far out, 1 m very close")


## A level with a 2 km map area (the world agent's zone size) and nothing else in it.
func _test_large_map() -> void:
	print("A 2 km map")
	var script := GDScript.new()
	script.source_code = "extends Node3D\nfunc map_area() -> Rect2:\n\treturn Rect2(-1000, -1000, 2000, 2000)\n"
	script.reload()
	var zone := Node3D.new()
	zone.set_script(script)
	add_child(zone)
	var view := MapView.new()
	add_child(view)
	view.size = Vector2(1600, 900)
	view.setup(zone)
	check(absf(view.zoom - 900.0 / 2000.0 * 0.92) < 0.001 and view.centre == Vector2.ZERO, "it opens fitted to the whole 2 km (%.3f px/m)" % view.zoom)
	check(view.grid_spacing() == 100.0 and view.reference_at(view.map_to_screen(Vector2(-999, 999))) == "000 000",
		"100 m grid lines and 6-digit references when zoomed out (%s)" % view.reference_at(view.map_to_screen(Vector2(-999, 999))))
	var corner := Vector2(995.0, -995.0)
	var at := view.map_to_screen(corner)
	for i in 30:
		view.zoom_at(at, MapView.ZOOM_STEP)
	check(view.zoom == MapView.MAX_PX_PER_M, "zooms in to %.0f px/m" % view.zoom)
	check(view.screen_to_map(at).distance_to(corner) < 1.0 or view.centre.distance_to(Vector2(1000, -1000) + Vector2(500, -500)) < 600.0,
		"keeping the corner under the cursor (or as near as the pan limit lets it)")
	view.look_at_point(corner)
	var shown := view.visible_rect()
	check(shown.has_point(corner) and shown.size.x < 80.0 and view.grid_spacing() == 10.0,
		"panned to the far corner: about %.0f m across, 10 m grid lines" % shown.size.x)
	check(view.reference_at(view.map_to_screen(corner)) == "0199 0199", "the cursor reads 0199 0199 there (%s)" % view.reference_at(view.map_to_screen(corner)))
	for p: Vector2 in [Vector2(-1000, 1000), Vector2(1000, -1000), Vector2(12.5, -700)]:
		if view.screen_to_map(view.map_to_screen(p)).distance_to(p) > 0.01:
			check(false, "map and screen points round-trip (%s)" % p)
	view.look_at_point(Vector2(9000, 9000))
	check(view.centre.x <= 1000.0 + 2000.0 * MapView.PAN_MARGIN + 0.01, "the view can't be panned far off the map (%s)" % view.centre)
	for i in 40:
		view.zoom_at(Vector2(800, 450), 1.0 / MapView.ZOOM_STEP)
	check(is_equal_approx(view.zoom, view.min_zoom()), "and zooms back out to show the whole area and some margin")
	var tex := view.texture()
	check(tex != null and tex.get_width() == 1024 and tex.get_height() == 1024, "its picture is capped at 1024 px (%s)" % (tex.get_size() if tex else "none"))
	view.queue_free()
	zone.queue_free()
	await get_tree().process_frame


func _test_render() -> void:
	print("The compound's map picture")
	var area := level.map_area()
	var image := MapRender.render(level)
	var scale := MapRender.px_per_m(area)
	check(image.get_width() == roundi(area.size.x * scale) and scale == MapRender.MAX_PX_PER_M, "%d px for %.0f m (%.0f px/m)" % [image.get_width(), area.size.x, scale])
	var px := func(x: float, z: float) -> Color: return image.get_pixel(int((x - area.position.x) * scale), int((z - area.position.y) * scale))
	var wall: Color = px.call(-10.0, 19.85)
	var open: Color = px.call(0.0, 15.0)
	check(not wall.is_equal_approx(MapRender.GROUND) and open.is_equal_approx(MapRender.GROUND), "walls are drawn from above, open ground is ground (%s, %s)" % [wall, open])
	var roof: Color = px.call(18.0, -9.0)  # the shed's sheet-metal roof, 2.5 m up
	check(roof.v > wall.v * 0.9 and not roof.is_equal_approx(MapRender.GROUND), "the shed's roof shows over its walls")


## What the map shows of the soldiers (no enemies) and a dead player's gear.
func _test_map_contents() -> void:
	print("Who the map shows")
	var points := MapView.soldier_points(level)
	var kinds := points.map(func(p: Dictionary) -> String: return p.kind)
	check(kinds.count("self") == 1 and kinds.count("squad") == 7 and points.size() == 8,
		"you and your 7 squadmates, and none of the %d hostiles (%s)" % [level.ai.get_children().filter(func(s: Soldier) -> bool: return s.faction == &"hostile").size(), kinds])
	var me: Dictionary = points.filter(func(p: Dictionary) -> bool: return p.kind == "self").front()
	check(me.text == "You" and (me.pos as Vector2).distance_to(Vector2(player.global_position.x, player.global_position.z)) < 0.01, "you are where you stand")
	var body := level.server_spawn_body({"uid": "test_map_gear", "label": "Player 9", "faction": "friendly", "variant": "desert", "marker": true,
		"pos": [6.0, 0.1, 15.0], "gear": {"slots": {"primary": "m4a1"}, "slot_state": {}, "containers": {"vest": [], "pockets": [], "backpack": []}, "hands": ""}})
	await _frames(2)
	var gear := MapView.gear_points(level)
	check(gear.size() == 1 and gear[0].text == "Player 9's gear" and (gear[0].pos as Vector2).distance_to(Vector2(6, 15)) < 0.5,
		"a dead player's gear marker is on the map (%s)" % [gear])
	body.server_remove_body()
	await _frames(2)


# --- Briefing and markers over the network -----------------------------------------

func _test_briefing_and_markers() -> void:
	print("Briefing, markers and a client")
	var markers := MapNodes.markers(level)
	var briefing := MapNodes.briefing(level)
	var screen := player._hud.map_screen
	briefing.server_open(CONTRACT, ZONE)
	await _frames(3)
	check(briefing.is_open() and briefing.insertion_id == "south" and markers.list("intel").size() == 2,
		"the briefing opens: first insertion candidate picked, 2 known enemy positions on the map from intel")
	check(screen.visible and screen.briefing_panel.visible and screen.view.marker_channel == "plan", "and the map opens on its own with the briefing panel; marks are plan marks")
	screen.close()
	check(screen.visible, "it stays open until the deployment starts")
	var objectives := MapView.objectives_in(level)
	check(objectives.size() == 1 and objectives[0].title == "Recover the case" and objectives[0].pos == Vector2(0, -10),
		"the contract's objective is on the map (%s)" % [objectives])
	var hq := markers.server_add({"kind": "point", "points": PackedVector2Array([HQ_AT]), "text": "HQ", "colour": "black", "channel": "plan", "author": 1})
	var line := markers.server_add({"kind": "line", "points": PackedVector2Array([Vector2(-5, 25), Vector2(-5, 10), Vector2(0, 0)]), "colour": "blue", "channel": "plan", "author": 1})
	check(hq > 0 and line > 0 and markers.markers[line].points.size() == 3, "the host places a marker and draws a line")
	check(markers.server_add({"kind": "line", "points": PackedVector2Array([Vector2(1, 1)])}) == 0 and markers.server_add({"kind": "blob", "points": PackedVector2Array([Vector2(1, 1)])}) == 0,
		"a one-point line or an unknown kind is refused")
	# No live hostiles while the clients stand about in the open: this part is about the map, and
	# an unarmoured client shot down here leaves a body that the extraction report then counts.
	_remove_hostiles()
	await _frames(2)
	# Client A joins during the briefing.
	_spawn_client("A")
	var a1 := await _wait_report("a1")
	var a_peer := int(a1.get("peer", 0))
	var a_mark := _marker_with_text("A mark")
	check(not a_mark.is_empty() and a_mark.author == a_peer and a_mark.channel == "plan" and a_mark.colour == "blue",
		"the client's marker reached the host with its author (%s)" % [a_mark])
	check(markers.list("plan").filter(func(m: Dictionary) -> bool: return m.kind == "line" and m.author == a_peer).size() == 1, "and its line")
	check(briefing.ready_peers.has(a_peer) and not briefing.ready_peers.has(1) and "resupply" in briefing.supports and briefing.insertion_id == "east",
		"the client is ready, picked the resupply support and the east field insertion")
	check(not briefing.server_start(), "the host can't start while it isn't ready itself")
	briefing.server_set_ready(1, true)
	check(briefing.all_ready() and briefing.server_start() and briefing.is_deployed(), "everyone ready: the host starts the deployment")
	check(briefing.plan.insertion.get("id") == "east" and briefing.plan.supports == ["resupply"] and briefing.plan.plan_marks.size() >= 4,
		"the plan carries the insertion, supports and plan marks (%d)" % briefing.plan.get("plan_marks", []).size())
	await _frames(3)
	check(_flat(player.global_position, INSERT_EAST) < 4.0, "the host's player is at the insertion point (%s)" % player.global_position)
	check(not screen.visible, "the map closes when the deployment starts")
	var ext := MapNodes.extraction(level)
	check(ext.is_active() and ext.points.size() == 1 and ext.points[0].source == "zone", "extraction is open with the zone's LZ")
	check(MapNodes.reinforcements(level).running, "and the reinforcement timer runs")
	markers.server_move(hq, HQ_MOVED)
	markers.server_remove(line)
	_client_go.rpc_id(a_peer, "a2")
	await _wait_report("a2")
	# Then a grid extraction point, and client B joins late.
	var grid_ref := MapGrid.grid_ref(Vector2(-10, 20), level.map_area())
	var grid_id := ext.server_add_point_at_grid(grid_ref)
	var grid_point := ext.point_by_id(grid_id)
	check(grid_id > 0 and grid_point.source == "grid" and (grid_point.pos as Vector2).distance_to(MapGrid.parse(grid_ref, level.map_area())) < 0.01 and (grid_point.pos as Vector2).distance_to(Vector2(-10, 20)) < 7.1,
		"a grid reference (%s) sets an extraction point at its square's centre (%s)" % [grid_ref, grid_point.get("pos")])
	_spawn_client("B")
	await _wait_report("b1")
	# The M key on the host's own map.
	var m := InputEventKey.new()
	m.physical_keycode = KEY_M
	m.pressed = true
	screen._unhandled_input(m)
	await _frames(3)
	check(screen.visible and screen.extraction_panel.visible and screen.view.texture() != null, "M opens the map with the extraction panel")
	var slot_before := player.active_slot
	var two := InputEventKey.new()
	two.physical_keycode = KEY_2
	two.pressed = true
	player.player_input._unhandled_input(two)
	check(player.active_slot == slot_before, "with the map open, the game's keys don't act behind it (2 doesn't switch weapons)")
	await _test_map_mouse(screen.view)
	screen._unhandled_input(m)
	check(not screen.visible, "and M closes it")


## Placing, moving, drawing and deleting with the mouse on the host's own map.
func _test_map_mouse(view: MapView) -> void:
	print("Markers with the mouse")
	var markers := MapNodes.markers(level)
	view.zoom = 8.0
	view.look_at_point(Vector2(-30, -30))  # an empty corner of the map
	var spot := Vector2(-30, -30)
	var at := view.map_to_screen(spot)
	_mouse(view, at, MOUSE_BUTTON_LEFT, true, true)
	check(view._text.visible, "a double-click asks for the marker's text")
	view._on_text_submitted("Mouse mark")
	await _frames(2)
	var mark := _marker_with_text("Mouse mark")
	check(not mark.is_empty() and (mark.points[0] as Vector2).distance_to(spot) < 0.2 and mark.channel == "field" and mark.author == 1,
		"Enter places it there, on the field channel (%s)" % [mark])
	_mouse(view, at, MOUSE_BUTTON_LEFT, true)
	_motion(view, at + Vector2(40, 0))
	_mouse(view, at + Vector2(40, 0), MOUSE_BUTTON_LEFT, false)
	await _frames(2)
	mark = _marker_with_text("Mouse mark")
	check(not mark.is_empty() and (mark.points[0] as Vector2).distance_to(spot + Vector2(5, 0)) < 0.2, "dragging it moves it 5 m east (40 px at 8 px/m)")
	var lines_before := markers.list().filter(func(m: Dictionary) -> bool: return m.kind == "line").size()
	var a := view.map_to_screen(Vector2(-36, -22))
	_mouse(view, a, MOUSE_BUTTON_LEFT, true, false, true)
	_motion(view, a + Vector2(20, 0))
	_motion(view, a + Vector2(40, 20))
	_mouse(view, a + Vector2(40, 20), MOUSE_BUTTON_LEFT, false)
	await _frames(2)
	var lines := markers.list().filter(func(m: Dictionary) -> bool: return m.kind == "line")
	check(lines.size() == lines_before + 1 and (lines.back().points as PackedVector2Array).size() == 3, "Ctrl + drag draws a line")
	_motion(view, view.map_to_screen(spot + Vector2(5, 0)))
	var del := InputEventKey.new()
	del.keycode = KEY_DELETE
	del.pressed = true
	view._gui_input(del)
	await _frames(2)
	check(_marker_with_text("Mouse mark").is_empty(), "Delete removes the marker under the cursor")
	var zoom := view.zoom
	_mouse(view, view.view_size() * 0.5, MOUSE_BUTTON_WHEEL_UP, true)
	check(is_equal_approx(view.zoom, zoom * MapView.ZOOM_STEP), "the wheel zooms")
	_motion(view, view.map_to_screen(Vector2(-31, -31)))
	check(view.cursor_reference() == MapGrid.grid_ref(Vector2(-31, -31), level.map_area()), "the cursor's grid reference (%s)" % view.cursor_reference())


func _mouse(view: MapView, at: Vector2, button: MouseButton, pressed: bool, double := false, ctrl := false) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = at
	ev.button_index = button
	ev.pressed = pressed
	ev.double_click = double
	ev.ctrl_pressed = ctrl
	view._gui_input(ev)


func _motion(view: MapView, at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	view._gui_input(ev)


func _marker_with_text(text: String) -> Dictionary:
	for marker: Dictionary in MapNodes.markers(level).list():
		if marker.text == text:
			return marker
	return {}


func _spawn_client(tag: String) -> void:
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/map_test.tscn",
		"--", "--join", "127.0.0.1", "--client", tag])
	var pid := OS.create_process(OS.get_executable_path(), args)
	check(pid > 0, "client %s started (pid %d)" % [tag, pid])
	_pids.append(pid)


func _kill_clients() -> void:
	for pid in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)


## Host: waits for a client's report of `stage`; its checks count here.
func _wait_report(stage: String) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(CLIENT_WAIT_S * 1000)
	while not _reports.has(stage) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(_reports.has(stage), "client report %s arrived" % stage)
	return _reports.get(stage, {})


## Client -> host: a stage's checks.
@rpc("any_peer", "call_remote", "reliable")
func _host_report(stage: String, fails: int, lines: PackedStringArray) -> void:
	if not multiplayer.is_server():
		return
	for line in lines:
		print(line)
	failures += fails
	_reports[stage] = {"peer": multiplayer.get_remote_sender_id(), "failures": fails}


## Host -> client: go on to `stage`.
@rpc("authority", "call_remote", "reliable")
func _client_go(stage: String) -> void:
	_go = stage


# --- The clients --------------------------------------------------------------------

func _run_client() -> void:
	await _wait_for(func() -> bool: return multiplayer.has_multiplayer_peer() and multiplayer.get_unique_id() != 1 \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, 20.0)
	if _tag == "A":
		await _client_a()
	else:
		await _client_b()
	await get_tree().create_timer(0.5).timeout
	Net.leave()
	get_tree().quit(failures)


func _report(stage: String) -> void:
	_host_report.rpc_id(1, stage, failures, _lines)
	failures = 0
	_lines = PackedStringArray()


## Joins during the briefing: sees what the host placed, plans, readies up, and sees the
## deployment start.
func _client_a() -> void:
	var markers := MapNodes.markers(level)
	var briefing := MapNodes.briefing(level)
	await _wait_for(func() -> bool: return not _marker_with_text("HQ").is_empty() and briefing.is_open(), 10.0)
	check(not _marker_with_text("HQ").is_empty() and markers.list("plan").any(func(m: Dictionary) -> bool: return m.kind == "line"),
		"markers and lines placed before joining are here")
	check(briefing.is_open() and briefing.contract.get("title") == CONTRACT.title and briefing.insertion_points().size() == 3 and markers.list("intel").size() == 2,
		"the briefing is open here too, with the contract, 3 insertion candidates and 2 intel positions")
	await _wait_for(func() -> bool: return MapNodes.local_player(level) != null and MapNodes.local_player(level)._hud != null, 5.0)
	var me := MapNodes.local_player(level)
	await _frames(3)
	check(me != null and me._hud.map_screen.visible and me._hud.map_screen.briefing_panel.visible, "and its map opened with the briefing")
	markers.request_add("point", PackedVector2Array([Vector2(5, 5)]), "A mark", "blue", "plan")
	markers.request_add("line", PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)]), "", "red", "plan")
	markers.request_add("enemy", PackedVector2Array([Vector2(3, 3)]), "fake intel", "red", "intel")  # refused: intel is the game's
	briefing.request_support("resupply", true)
	briefing.request_insertion("east")
	briefing.request_set_ready(true)
	await _wait_for(func() -> bool: return not _marker_with_text("A mark").is_empty() and briefing.ready_peers.has(multiplayer.get_unique_id()) \
		and briefing.insertion_id == "east", 5.0)
	var mine := _marker_with_text("A mark")
	check(not mine.is_empty() and mine.author == multiplayer.get_unique_id(), "its own marker came back from the host with its author")
	check(briefing.ready_peers.has(multiplayer.get_unique_id()) and briefing.insertion_id == "east" and "resupply" in briefing.supports,
		"its ready, insertion and support picks came back")
	check(_marker_with_text("fake intel").is_empty(), "a client can't add intel")
	_report("a1")
	await _wait_for(func() -> bool: return _go == "a2", 30.0)
	await _wait_for(func() -> bool: return briefing.is_deployed() and _marker_with_text("HQ").get("points", [Vector2.ZERO])[0] == HQ_MOVED, 10.0)
	check(briefing.is_deployed() and briefing.plan.get("insertion", {}).get("id") == "east", "the deployment started here too, from the east field")
	check(_marker_with_text("HQ").get("points", [Vector2.ZERO])[0] == HQ_MOVED and markers.list("plan").filter(func(m: Dictionary) -> bool: return m.kind == "line").size() == 1,
		"the host's move and delete replicated (its line gone, ours still there)")
	await _wait_for(func() -> bool: return _flat(me.global_position, INSERT_EAST) < 6.0, 5.0)
	check(_flat(me.global_position, INSERT_EAST) < 6.0, "this player was moved to the insertion point (%s)" % me.global_position)
	check(not me._hud.map_screen.visible, "and the map closed")
	_report("a2")


## Joins late, mid-deployment: everything is already there.
func _client_b() -> void:
	var markers := MapNodes.markers(level)
	var briefing := MapNodes.briefing(level)
	var ext := MapNodes.extraction(level)
	await _wait_for(func() -> bool: return not _marker_with_text("A mark").is_empty() and ext.points.size() == 2 and briefing.is_deployed(), 10.0)
	check(_marker_with_text("HQ").get("points", [Vector2.ZERO])[0] == HQ_MOVED and not _marker_with_text("A mark").is_empty()
		and markers.list("plan").filter(func(m: Dictionary) -> bool: return m.kind == "line").size() == 1 and markers.list("intel").size() == 2,
		"a late joiner gets every marker as it is now (%d)" % markers.markers.size())
	check(briefing.is_deployed() and not briefing.is_open() and briefing.plan.get("supports") == ["resupply"], "and the deployment's state, not a briefing")
	check(ext.is_active() and ext.points.size() == 2 and ext.points.any(func(p: Dictionary) -> bool: return p.source == "grid"),
		"and both extraction points, the zone's and the grid one")
	_report("b1")


# --- Extraction ------------------------------------------------------------------

func _test_extraction() -> void:
	print("Extraction")
	await _wait_for(func() -> bool: return level.players.get_child_count() == 1 and MapNodes.squad_ai(level).size() == 7, 10.0)
	await _frames(5)
	_remove_hostiles()
	var ext := MapNodes.extraction(level)
	ext.countdown_s = 1.0
	# A purple smoke sets a point; a second one moves it; white smoke doesn't.
	var smoke_at := Vector3(10, 0.1, 10)
	Throwables.server_detonate(level, "smoke", smoke_at, &"smoke_purple")
	await _wait_for(func() -> bool: return ext.points.any(func(p: Dictionary) -> bool: return p.source == "smoke"), 3.0)
	var smoke := ext.points.filter(func(p: Dictionary) -> bool: return p.source == "smoke")
	check(smoke.size() == 1 and (smoke[0].pos as Vector2).distance_to(Vector2(10, 10)) < 0.5, "a purple smoke sets an extraction point where it is")
	Throwables.server_detonate(level, "smoke", Vector3(-12, 0.1, 6), &"smoke_white_test")
	Throwables.server_detonate(level, "smoke", Vector3(14, 0.1, -14), &"smoke_purple")
	await _seconds(1.2)
	smoke = ext.points.filter(func(p: Dictionary) -> bool: return p.source == "smoke")
	check(smoke.size() == 1 and (smoke[0].pos as Vector2).distance_to(Vector2(14, -14)) < 0.5 and ext.points.size() == 3,
		"a second purple smoke moves it; white smoke sets nothing (%d points)" % ext.points.size())
	# Stage the squad at LZ South with Golf left out west, carrying the HVT case.
	var lz := Vector2(0, 34)
	_place(player, Vector3(lz.x, 0.1, lz.y))
	player.inventory.take(&"hvt_case")
	# A tourniquet holder with a tourniquet in it on the host's carrier (MOLLE).
	if player.inventory.slots[&"vest"] == &"":
		player.inventory.take(&"plate_carrier_light")
	var tq_point := player.inventory.free_point_for(ItemDB.get_item(&"pouch_tq"))
	if tq_point != &"":
		player.inventory.attach(tq_point, {"id": &"pouch_tq", "count": 1})
		player.inventory.take(&"tourniquet")
	var mates := MapNodes.squad_ai(level)
	var golf: Soldier = mates.back()  # the last slot's squadmate (Golf) stays out west
	var i := 0
	for s: Soldier in mates:
		SquadAI.of(s).process_mode = Node.PROCESS_MODE_DISABLED
		_place(s, Vector3(lz.x - 4.0 + 1.5 * i, 0.1, lz.y + 3.0) if s != golf else Vector3(-15, 0.1, -15))
		i += 1
	var hvt := Node3D.new()
	hvt.name = "TestHVT"
	hvt.add_to_group(Extraction.HVT_GROUP)
	level.add_child(hvt)
	hvt.global_position = Vector3(2, 0.1, 36)
	var far_hvt := Node3D.new()
	far_hvt.name = "FarHVT"
	far_hvt.add_to_group(Extraction.HVT_GROUP)
	level.add_child(far_hvt)
	far_hvt.global_position = Vector3(0, 0.1, -10)
	level.server_spawn_body({"uid": "test_map_body", "label": "Hostile9", "faction": "hostile", "variant": "urban", "pos": [-3.0, 0.1, 35.0],
		"gear": {"slots": {"vest": "plate_carrier_light"}, "slot_state": {}, "containers": {"vest": [{"id": "mag_556", "count": 2}], "pockets": [], "backpack": []}, "hands": ""}})
	level.spawn_item(&"electronics_salvage", 3, Vector3(3, 0.5, 33), "test_map_deposit")
	# Audit A3-03: bodies count where they lie, not where their capsule fell. One fell just
	# outside the LZ and its ragdoll slid in; the other fell inside and slid out.
	var slid_in := level.server_spawn_body({"uid": "test_map_slid_in", "label": "SlidIn", "faction": "friendly", "variant": "multicam", "pos": [8.0, 0.1, 20.0],
		"gear": {"slots": {"vest": "plate_carrier_light"}, "slot_state": {}, "containers": {"vest": [], "pockets": [], "backpack": []}, "hands": ""}})
	var slid_out := level.server_spawn_body({"uid": "test_map_slid_out", "label": "SlidOut", "faction": "friendly", "variant": "multicam", "pos": [-6.0, 0.1, 30.0],
		"gear": {"slots": {"vest": "plate_carrier_light"}, "slot_state": {}, "containers": {"vest": [], "pockets": [], "backpack": []}, "hands": ""}})
	var slid: bool = await _slide_body(slid_in, Vector3(0, 0, 8))
	slid = await _slide_body(slid_out, Vector3(0, 0, -8)) and slid
	await _seconds(0.5)
	check(mates.size() == 7, "seven squadmates to bring (%d)" % mates.size())
	var why := ext.server_confirm()
	check(why.contains(String(golf.name)) and ext.state == Extraction.State.ACTIVE, "with %s away, the host can't extract: %s" % [golf.name, why])
	ext.server_set_bring(String(golf.name), false)
	why = ext.server_confirm()
	check(why == "" and ext.state == Extraction.State.COUNTDOWN, "leaving Golf behind, the countdown starts (%s)" % why)
	_place(player, Vector3(0, 0.1, 0))
	await _frames(3)
	check(ext.state == Extraction.State.ACTIVE, "the host walking out of the LZ stops it")
	_place(player, Vector3(lz.x, 0.1, lz.y))
	await _frames(2)
	check(ext.server_confirm() == "", "back inside, the host confirms again")
	await _wait_for(func() -> bool: return ext.state == Extraction.State.ENDED, 4.0)
	check(ext.state == Extraction.State.ENDED and _ended.size() == 1, "after the countdown the deployment ends and the economy's handler gets the report")
	var report: Dictionary = _ended[0] if not _ended.is_empty() else {}
	var squad_names: Array = report.get("squad", []).map(func(r: Dictionary) -> String: return r.name)
	check(report.get("players", []).size() == 1 and report.players[0].peer == 1 and squad_names.size() == 6 and String(golf.name) not in squad_names,
		"out: the host and six squadmates (%s)" % [squad_names])
	var left: Array = report.get("left_behind", [])
	check(left.size() == 1 and left[0].name == String(golf.name) and left[0].alive and left[0].chosen, "left behind, alive, by choice: %s (%s)" % [golf.name, left])
	var items: Dictionary = report.get("items", {})
	check(int(items.get("hvt_case", 0)) == 1 and int(items.get("electronics_salvage", 0)) == 3 and int(items.get("plate_carrier_light", 0)) >= 1,
		"items out: the HVT case in the host's hands, the salvage set down in the LZ, the body's vest (%s)" % [items])
	check(report.players[0].items.any(func(e: Dictionary) -> bool: return e.id == "hvt_case" and e.where == "hands") if not report.get("players", []).is_empty() else false,
		"the case is listed in the host's hands")
	# MOLLE: the pouches on the host's carrier and what's in them count, once each.
	var host_totals := Extraction.totals_of(report.players[0].items) if not report.get("players", []).is_empty() else {}
	var in_pouches := {}
	var pouch_ids := {}
	for c: StringName in player.inventory.pouch_containers():
		pouch_ids[String(player.inventory.pouch_item(c).id)] = true
		for e: Dictionary in player.inventory.containers[c]:
			in_pouches[String(e.id)] = true
	var counted := in_pouches.keys().all(func(id: String) -> bool: return int(host_totals.get(id, 0)) == player.inventory.count_of(StringName(id)))
	counted = counted and pouch_ids.keys().all(func(id: String) -> bool: return int(host_totals.get(id, 0)) >= 1)
	check(not in_pouches.is_empty() and counted and in_pouches.has("tourniquet"),
		"the host's MOLLE pouches and their contents are in the report, once each (%s in %s)" % [in_pouches.keys(), pouch_ids.keys()])
	var bodies: Array = report.get("bodies", [])
	var hostile9 := bodies.filter(func(b: Dictionary) -> bool: return b.label == "Hostile9")
	check(hostile9.size() == 1 and hostile9[0].items.size() >= 2, "the body brought along, with its gear (%s)" % [bodies])
	var out_labels: Array = bodies.map(func(b: Dictionary) -> String: return b.label)
	var left_labels: Array = report.get("bodies_left", []).map(func(b: Dictionary) -> String: return b.label)
	check(slid and bodies.size() == 2 and "SlidIn" in out_labels and "SlidOut" in left_labels and "SlidOut" not in out_labels,
		"bodies count where they lie: one that slid into the LZ goes out with its gear, one that slid out of it stays (slid %s; out %s, left %s)" % [slid, out_labels, left_labels])
	var hvts: Array = report.get("hvts", [])
	check(hvts.size() == 1 and hvts[0].name == "TestHVT", "the HVT inside the LZ, not the one left in the compound (%s)" % [hvts])
	check(report.get("point", {}).get("name") == "LZ South" and report.get("contract_id") == "test_contract" and report.get("objectives", []).size() <= 1,
		"at LZ South, for the test contract")
	check(JSON.parse_string(JSON.stringify(report)) is Dictionary, "the report is JSON-safe (for the campaign save)")
	check(not MapNodes.reinforcements(level).running, "the reinforcement timer stops at extraction")
	check(ext.server_confirm() != "", "an ended deployment can't extract again")
	hvt.queue_free()
	far_hvt.queue_free()
	for s: Soldier in mates:
		if is_instance_valid(s):
			SquadAI.of(s).process_mode = Node.PROCESS_MODE_INHERIT


## Once `body`'s ragdoll is at rest, moves it `by` (its capsule stays where it fell), as a
## ragdoll sliding or rolling would. False if it never lay as one.
func _slide_body(body: Soldier, by: Vector3) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while not is_instance_valid(body.ragdoll) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not is_instance_valid(body.ragdoll):
		print("  (%s never lay as a ragdoll)" % body.display_name())
		return false
	for part: RigidBody3D in body.ragdoll.parts.values():
		part.freeze = true
		part.global_position += by
	body.ragdoll._send(true)
	await _frames(5)  # the shown pose (and its hitboxes) follows
	print("  %s: capsule %s, lies at %s" % [body.display_name(), body.global_position, body.body_point()])
	return _flat(body.body_point(), body.global_position) > by.length() - 1.5


func end_deployment(report: Dictionary) -> void:
	_ended.append(report)


# --- Reinforcements --------------------------------------------------------------

func _test_reinforcements() -> void:
	print("Reinforcement timer")
	var defaults := Reinforcements.DEFAULTS
	var gaps := []
	for k in 8:
		gaps.append(Reinforcements.gap_after(k, defaults))
	check(Reinforcements.wave_time(0) == 300.0 and gaps[0] == 240.0 and gaps[1] < gaps[0] and gaps[7] == 90.0,
		"by default the first wave comes at 5 min, then each sooner, down to every 90 s (%s)" % [gaps])
	check(Reinforcements.wave_size(0) == 2 and Reinforcements.wave_size(2) == 4 and Reinforcements.wave_size(20) == 8, "and each bigger: 2, 2, 4, 4 ... up to 8 (4 pairs)")
	var r := MapNodes.reinforcements(level)
	var area := level.map_area()
	_place(player, Vector3(0, 0.1, 10))
	r.server_start({"first_wave_s": 60.0, "first_gap_s": 40.0, "gap_shrink": 0.5, "min_gap_s": 10.0, "first_pairs": 1,
		"pairs_every": 1, "max_pairs": 3, "max_alive": 12})
	var before := r.hostiles_alive()
	r.server_advance(59.0)
	check(r.waves_sent == 0 and r.hostiles_alive() == before, "nothing before the first wave is due (%d hostiles)" % before)
	r.server_advance(1.5)
	await _frames(2)
	check(r.waves_sent == 1 and r.waves[0].soldiers.size() == 2, "the first wave arrives on time: a pair (%d)" % (r.waves[0].soldiers.size() if r.waves_sent > 0 else -1))
	if r.waves_sent > 0:
		var outside: Array = r.waves[0].soldiers.filter(func(s: Soldier) -> bool: return not area.has_point(Vector2(s.global_position.x, s.global_position.z)))
		check(outside.size() == 2 and r.waves[0].soldiers.all(func(s: Soldier) -> bool: return s.faction == &"hostile" and s.is_ai()),
			"hostile AI, spawned off the map's edge (%s)" % [r.waves[0].edge])
		var squad: Squad = r.waves[0].squad
		check(squad.patrol.size() >= 2 and _flat(squad.patrol[1], player.global_position) < 3.0, "their route leads to the players")
	r.server_advance(40.0)
	r.server_advance(20.0)
	await _frames(2)
	check(r.waves_sent == 3 and r.waves[1].soldiers.size() == 4 and r.waves[2].soldiers.size() == 6, "escalating: then 4, then 6")
	if r.waves_sent == 3:
		check(absf(r.waves[1].at_s - r.waves[0].at_s - 40.0) < 2.0 and absf(r.waves[2].at_s - r.waves[1].at_s - 20.0) < 2.0,
			"and sooner each time: 40 s, then 20 s apart")
	r.server_advance(10.0)
	await _frames(2)
	check(r.waves_sent == 4 and r.hostiles_alive() <= 12, "no wave takes the hostiles past the cap (%d alive)" % r.hostiles_alive())
	r.server_stop()
	r.server_advance(500.0)
	check(r.waves_sent == 4, "stopped, nothing more comes")


# --- Helpers ---------------------------------------------------------------------

func _remove_hostiles() -> void:
	for s: Soldier in level.ai.get_children():
		if s.faction == &"hostile":
			s.queue_free()


func _place(s: Soldier, pos: Vector3) -> void:
	s.global_position = pos
	s.velocity = Vector3.ZERO


func _flat(a: Vector3, b: Variant) -> float:
	var p := Vector2(b.x, b.z) if b is Vector3 else b as Vector2
	return Vector2(a.x, a.z).distance_to(p)


func _wait_for(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
