class_name VehicleXray
extends Control
## The x-ray: hit analysis (combined arms A5, cg_brief queue item 2.4; docs/combined_arms.md 2.11,
## call 31, F-239), learned from War Thunder's hit camera and protection analysis. Local to each
## player; it reads A2's HitEvents (VehicleModules.events: the host's own trace, on every peer)
## through HitReport, never resolving a hit again.
##
## - The card: for HitEvents the "hit analysis" setting wants (GameSettings "hud" "hit_analysis":
##   off, my shots, my shots and hits on me (the default), every hit (dev)), a small card in the
##   HUD's top-right zone for CARD_S: the target, an outcome mark, one line ("PEN: engine
##   destroyed, gunner wounded" or "RICOCHET: Turret front, 81 degrees") and the key.
## - The full view (the x-ray key, 5 by default; the pause menu's "Last hits"): the vehicle drawn
##   from its data in a SubViewport, orbitable (drag the mouse, the wheel; the pad's right stick):
##   plates as see-through boxes shaded by their KE figure (fired ERA tiles grey), modules
##   outlined (white working, yellow damaged, red destroyed), the crew as capsules (green up,
##   orange wounded, red down), the round's line from its entry through each module it crossed,
##   the plate marker and the angle's arc, the spall rays; the text (HitReport.panel_text), and
##   the last KEEP hits to pick from. The game doesn't pause (co-op); Esc or the key closes it.
## - Protection analysis (the vehicle range and the base's firing range, or dev tools): pick a
##   round and a range, click the model, and see what ArmourModel.resolve predicts there with a
##   fixed seed, and the ricochet chance over RICOCHET_SAMPLES seeds (predict()).
## - Dev: "--xray-log" on the command line writes every HitReport to the session log.
## Fits the ui_test's 10 resolutions (ui_test checks the card and the full view). Numbers Proposed.

const NODE_NAME := &"VehicleXray"
const GROUP := &"vehicle_xray"
const ACTION := &"xray"
const CARD_S := 6.0
const KEEP := 10
const SETTING := "hit_analysis"
const SETTINGS := [["off", "Off"], ["mine", "My shots"], ["mine_and_me", "My shots and hits on me"], ["all", "Every hit (dev)"]]
## Protection analysis: the ranges offered (m), its fixed seed, the seeds for the ricochet chance.
const RANGES_M: Array[int] = [100, 500, 1000, 1500, 2000, 3000]
const ANALYSIS_SEED := 20261023
const RICOCHET_SAMPLES := 40
## The full view: the widest it gets (logical px), the orbit (radians a pixel, a second of stick).
const FULL_MAX := Vector2(1100.0, 640.0)
const ORBIT_PER_PX := 0.008
const ORBIT_PAD_S := 2.2
const OUTCOME_COLOURS := {"pen": Color(0.9, 0.25, 0.2), "non_pen": Color(0.6, 0.62, 0.58), "ricochet": Color(0.98, 0.8, 0.28),
	"shatter": Color(0.75, 0.75, 0.85), "dud": Color(0.5, 0.5, 0.5), "fuzed_outside": Color(0.95, 0.55, 0.25), "belly": Color(0.9, 0.4, 0.2)}

var player: Soldier
var hud: Hud
## The last KEEP reports this peer has seen (every hit, whatever the setting: the pause menu's
## list), newest last; and those the card was shown for.
var reports: Array = []
var card: PanelContainer
var full: PanelContainer
## The report in the full view ({} none), or the analysis' vehicle model.
var shown: Dictionary = {}
var analysis: Dictionary = {}
var _card_mark: ColorRect
var _card_title: Label
var _card_line: Label
var _card_left := 0.0
var _vpc: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _root3d: Node3D
var _text: Label
var _picker: OptionButton
var _analysis_box: VBoxContainer
var _shell_pick: OptionButton
var _range_pick: OptionButton
var _result: Label
var _seen := {}  # vehicle instance id -> its modules' events_seen when last looked
var _yaw := 0.7
var _pitch := -0.45
var _dist := 14.0
var _centre := Vector3.ZERO
var _drag := false
var _log := false


func _init(p_player: Soldier = null, p_hud: Hud = null) -> void:
	player = p_player
	hud = p_hud
	name = NODE_NAME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_to_group(GROUP)
	_log = "--xray-log" in OS.get_cmdline_user_args() or "--xray-log" in OS.get_cmdline_args()
	_build_card()
	_build_full()


func _ready() -> void:
	if hud and card.get_parent() == null:
		hud.zone_top_right.add_child(card)  # the cards' zone (RequestCards)
	elif card.get_parent() == null:
		add_child(card)


func _exit_tree() -> void:
	if is_instance_valid(card) and card.get_parent() != self and card.get_parent() != null:
		card.queue_free()


## The local player `s`'s x-ray, or null.
static func of(s: Soldier) -> VehicleXray:
	if s == null or not is_instance_valid(s) or s.player_input == null or s.player_input.hud == null:
		return null
	return s.player_input.hud.get_node_or_null(NodePath(String(NODE_NAME))) as VehicleXray


## The setting now ("off", "mine", "mine_and_me", "all").
static func setting() -> String:
	return String(GameSettings.get_value("hud", SETTING))


# --- The card -------------------------------------------------------------------------------------

func _build_card() -> void:
	card = UiKit.panel()
	card.name = "HitCard"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	card.add_child(row)
	_card_mark = ColorRect.new()
	_card_mark.custom_minimum_size = Vector2(8, 0)
	row.add_child(_card_mark)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	_card_title = UiKit.hud_label("", &"HudSmallLabel")
	_card_line = UiKit.hud_label("", &"HudSmallLabel")
	for l: Label in [_card_title, _card_line]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 120.0
		col.add_child(l)


## Shows report `r` on the card (`mine`: the local player's shot; else a hit on him).
func show_card(r: Dictionary, mine: bool) -> void:
	_card_title.text = "%s: %s    [%s] x-ray" % ["YOUR HIT" if mine else "HIT ON YOU", String(r.get("vehicle", r.get("model", ""))),
		GameSettings.binding_name(GameSettings.key_for(ACTION))]
	_card_line.text = HitReport.line(r)
	_card_mark.color = OUTCOME_COLOURS.get(String(r.get("outcome", "")), UiKit.TEXT_DIM)
	_card_left = CARD_S
	card.visible = true


## Whether a hit on `v` by "by" (a node name) is one the card shows for `p` under setting `which`.
static func wanted(which: String, by: String, p: Soldier, v: Vehicle) -> Dictionary:
	if p == null or which == "off":
		return {}
	var mine := by != "" and by == String(p.name)
	var on_me := v != null and v.seat_of(p) >= 0
	if which == "all" or mine or (which == "mine_and_me" and on_me):
		return {"mine": mine or not on_me}
	return {}


# --- Watching every vehicle's HitEvents ------------------------------------------------------------

func _process(delta: float) -> void:
	_card_left -= delta
	card.visible = _card_left > 0.0
	_poll()
	if full.visible:
		var stick := Vector2(Input.get_action_strength(&"look_right") - Input.get_action_strength(&"look_left"),
			Input.get_action_strength(&"look_down") - Input.get_action_strength(&"look_up"))
		if stick.length() > 0.15:
			_yaw -= stick.x * ORBIT_PAD_S * delta
			_pitch = clampf(_pitch - stick.y * ORBIT_PAD_S * delta, -1.4, 0.6)
		_place_camera()


## New HitEvents on any vehicle since the last look: a report each, the card for the wanted ones.
func _poll() -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if v == null or v.modules == null:
			continue
		var id := v.get_instance_id()
		var seen := int(_seen.get(id, 0))
		var now := v.modules.events_seen
		if now == seen:
			continue
		_seen[id] = now
		var fresh := mini(now - seen, v.modules.events.size())
		for i in range(v.modules.events.size() - fresh, v.modules.events.size()):
			take(v, v.modules.events[i])


## One HitEvent `ev` on `v`: kept, logged with --xray-log, and on the card if wanted.
func take(v: Vehicle, ev: Dictionary) -> Dictionary:
	var r := HitReport.of_event(v, ev)
	reports.append(r)
	if reports.size() > KEEP:
		reports.pop_front()
	if _log:
		SessionLog.note("[xray] " + HitReport.to_json(r))
	var w := wanted(setting(), String(ev.get("by", "")), player, v)
	if not w.is_empty():
		show_card(r, bool(w.mine))
	if full.visible and not shown.is_empty() and analysis.is_empty():
		_refresh_picker()
	return r


# --- Keys ---------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if player == null or not is_instance_valid(player) or not player.is_local():
		return
	if event.is_action_pressed(ACTION) and not event.is_echo():
		if full.visible:
			close()
		else:
			open_latest()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if full.visible and event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()


## The key: the latest report in the full view; with none, protection analysis where it's allowed.
func open_latest() -> bool:
	if not reports.is_empty():
		open_report(reports.back())
		return true
	var v := analysis_vehicle()
	if v != null:
		open_analysis(v.model, v.get_meta(ArmourModel.META_PACKAGES, []))
		return true
	if hud:
		hud.flash("No hits to analyse yet")
	return false


## Whether protection analysis is offered here: the vehicle range, the base zone (its firing
## range), or dev tools.
func analysis_allowed() -> bool:
	var lvl := CompoundLevel.current(self) if is_inside_tree() else null
	return DevTools.on() or lvl is VehicleRange or lvl is BaseZoneLevel


## The vehicle to analyse: the one the player sits in, else the nearest armoured one within 40 m.
func analysis_vehicle() -> Vehicle:
	if player == null or not analysis_allowed():
		return null
	var ride := Vehicle.ride_of(player)
	if VehicleHud.applies(ride):
		return ride
	var best: Vehicle = null
	var near := 40.0
	for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if VehicleHud.applies(v) and v.global_position.distance_to(player.global_position) < near:
			near = v.global_position.distance_to(player.global_position)
			best = v
	return best


# --- The full view -----------------------------------------------------------------------------

func _build_full() -> void:
	full = UiKit.panel(true)
	full.name = "XrayView"
	full.visible = false
	full.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(full)
	var outer := VBoxContainer.new()
	outer.name = "Outer"
	outer.add_theme_constant_override(&"separation", UiKit.SPACE_S)
	full.add_child(outer)
	var head := HBoxContainer.new()
	head.add_child(UiKit.heading("X-ray: hit analysis"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(UiKit.button("Close", close, "Close the x-ray (Esc)"))
	outer.add_child(head)
	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", UiKit.SPACE_M)
	outer.add_child(body)
	_vpc = SubViewportContainer.new()
	_vpc.name = "XrayModel"
	_vpc.stretch = true
	_vpc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vpc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vpc.custom_minimum_size = Vector2(220, 160)
	_vpc.mouse_filter = Control.MOUSE_FILTER_STOP
	_vpc.gui_input.connect(_on_model_input)
	body.add_child(_vpc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_vpc.add_child(_vp)
	_root3d = Node3D.new()
	_vp.add_child(_root3d)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.9, 0.6, 0.0)
	_vp.add_child(light)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_vp.add_child(_cam)
	var side := VBoxContainer.new()
	side.name = "Side"
	side.custom_minimum_size = Vector2(240, 0)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_stretch_ratio = 0.8
	body.add_child(side)
	_picker = _options("The last hits this game", _on_pick)
	side.add_child(_picker)
	_text = UiKit.text("")
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_text)
	_analysis_box = VBoxContainer.new()
	_analysis_box.visible = false
	side.add_child(_analysis_box)
	_shell_pick = _options("The round", func(_i: int) -> void: _result.text = "Click the model to see the outcome there")
	_range_pick = _options("The range it's fired from", func(_i: int) -> void: pass)
	for r: int in RANGES_M:
		_range_pick.add_item("%d m" % r)
	_range_pick.select(2)
	_result = UiKit.text("Click the model to see the outcome there")
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for c: Control in [UiKit.hint("Protection analysis: pick a round and a range, click the model."), _shell_pick, _range_pick, _result]:
		_analysis_box.add_child(c)
	outer.add_child(UiKit.hint("Drag or the right stick: turn it    Wheel: zoom    Esc / %s: close" % GameSettings.binding_name(GameSettings.key_for(ACTION))))


static func _options(tip: String, picked: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.tooltip_text = tip
	o.fit_to_longest_item = false
	o.clip_text = true
	o.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	o.item_selected.connect(picked)
	return o


## Sizes the full view to the window (FULL_MAX at most, the window less UiKit.EDGE a side), side
## by side, or the text under the model on a narrow window.
func _fit_full() -> void:
	var view := get_viewport_rect().size if is_inside_tree() else FULL_MAX
	var w := minf(FULL_MAX.x, view.x - UiKit.EDGE * 2.0)
	var h := minf(FULL_MAX.y, view.y - UiKit.EDGE * 2.0)
	full.custom_minimum_size = Vector2(w, h)
	full.size = Vector2(w, h)
	full.position = (view - Vector2(w, h)) * 0.5
	var body := full.get_node_or_null(^"Outer/Body")
	var side := _text.get_parent() as Control
	side.custom_minimum_size.x = clampf(w * 0.36, 200.0, 360.0)
	_vpc.custom_minimum_size = Vector2(maxf(w - side.custom_minimum_size.x - UiKit.SPACE_M - 40.0, 160.0), 160.0)
	if body:
		(body as Control).custom_minimum_size.y = maxf(h - 120.0, 120.0)


func is_open() -> bool:
	return full.visible


## The full view on report `r`.
func open_report(r: Dictionary) -> void:
	analysis = {}
	shown = r
	_analysis_box.visible = false
	_picker.visible = true
	_refresh_picker()
	_text.text = HitReport.panel_text(r)
	_draw_model(String(r.model), _live(String(r.get("vid", ""))), r)
	_open()


## Protection analysis on model `model` fitted with `packages`.
func open_analysis(model: String, packages: Array = []) -> void:
	shown = {}
	analysis = {"model": model, "packages": packages.duplicate()}
	_picker.visible = false
	_analysis_box.visible = true
	_text.text = "%s: protection analysis" % String(VehicleSpecs.spec(model).get("name", model))
	_shell_pick.clear()
	for sid: Variant in analysis_shells():
		_shell_pick.add_item(String(Shells.shell(sid).get("name", sid)))
		_shell_pick.set_item_metadata(_shell_pick.item_count - 1, String(sid))
	_shell_pick.select(0)
	_draw_model(model, _live_model(model), {})
	_open()


func _open() -> void:
	full.visible = true
	_fit_full()
	_place_camera()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not full.visible:
		return
	full.visible = false
	if player and is_instance_valid(player) and player.player_input and not player.player_input.pause_menu.is_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_picker() -> void:
	_picker.clear()
	for i in range(reports.size() - 1, -1, -1):
		var r: Dictionary = reports[i]
		_picker.add_item("%s: %s" % [String(r.get("vehicle", r.model)), HitReport.line(r)])
	var at := reports.find(shown)
	_picker.select(reports.size() - 1 - at if at >= 0 else 0)


func _on_pick(i: int) -> void:
	var at := reports.size() - 1 - i
	if at >= 0 and at < reports.size():
		open_report(reports[at])


func _live(vid: String) -> Vehicle:
	if vid == "" or not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
		if (n as Vehicle).vehicle_id == vid:
			return n as Vehicle
	return null


func _live_model(model: String) -> Vehicle:
	var v := analysis_vehicle()
	return v if v and v.model == model else null


## The rounds the analysis offers: every shell with a penetration figure.
static func analysis_shells() -> Array:
	return Shells.ids().filter(func(sid: Variant) -> bool:
		var s := Shells.shell(sid)
		return not (s.get("pen_ke", []) as Array).is_empty() or float(s.get("pen_ce", 0.0)) > 0.0 or float(s.get("he_kg", 0.0)) > 0.0)


# --- Drawing the model ------------------------------------------------------------------------------

## Builds the x-ray of `model` (its live vehicle `v` for the states now, or null), with report `r`'s
## shot over it ({} none).
func _draw_model(model: String, v: Vehicle, r: Dictionary) -> void:
	for c in _root3d.get_children():
		c.queue_free()
	var spec := VehicleSpecs.spec(model)
	var bounds := AABB()
	var first := true
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, _unshaded(Color.WHITE, 1.0, true))
	var used: Dictionary = v.get_meta(ArmourModel.META_TILES, {}) if v else {}
	for p: Dictionary in spec.get("plates", []):
		var b := VehicleSpecs.box(p.box)
		bounds = b if first else bounds.merge(b)
		first = false
		var ke := float(p.get("ke_mm", 0.0))
		var t := clampf(ke / 1000.0, 0.0, 1.0)
		_box(b, Color(lerpf(0.75, 0.2, t), lerpf(0.82, 0.35, t), lerpf(0.9, 0.7, t), lerpf(0.1, 0.32, t)))
	var fitted := ArmourModel.fitted_packages(spec, v.get_meta(ArmourModel.META_PACKAGES, []) if v else analysis.get("packages", []))
	for tile: Dictionary in spec.get("tiles", []):
		if not ArmourModel.tile_fitted(tile, fitted):
			continue
		var flags: PackedByteArray = used.get(String(tile.group), PackedByteArray())
		var any_used := flags.has(1)
		_box(VehicleSpecs.box(tile.box), Color(0.5, 0.5, 0.5, 0.35) if any_used else Color(0.55, 0.7, 0.45, 0.3))
	var mods := VehicleModules.layout_of(model, spec)
	var states := {}
	for e: Dictionary in r.get("path", []):
		states[String(e.id)] = String(e.state)
	for m: Dictionary in mods:
		if m.box == null or String(m.kind) in ["structure", "compartment"]:
			continue
		var b: AABB = m.box
		if bool(m.crew):
			var st := String(states.get(String(m.id), HitReport.crew_state(v.occupant(int(m.seat))) if v else "up"))
			_capsule(b, VehicleHud.CREW_COLOURS.get(st, UiKit.TEXT_OFF))
			continue
		var s := 0
		if states.has(String(m.id)):
			s = HitReport.STATE_WORDS.find(String(states[String(m.id)]))
		elif v and v.modules and int(m.i) < v.modules.health.size():
			s = VehicleModules.state_of(v.modules.health[int(m.i)])
		_edges(lines, b, VehicleHud.STATE_COLOURS[maxi(s, 0)])
	if not r.is_empty():
		_shot(lines, r, spec)
	lines.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = lines
	_root3d.add_child(mi)
	_centre = bounds.get_center() if not first else Vector3.ZERO
	_dist = clampf(bounds.size.length() * 1.6, 6.0, 30.0) if not first else 14.0


## The round's line, the plate marker and its angle's arc, the spall rays.
func _shot(lines: ImmediateMesh, r: Dictionary, spec: Dictionary) -> void:
	var e: Array = r.get("entry", [0, 0, 0])
	var d: Array = r.get("dir", [0, 0, -1])
	var entry := Vector3(float(e[0]), float(e[1]), float(e[2]))
	var dir := Vector3(float(d[0]), float(d[1]), float(d[2])).normalized()
	var reach := 0.0
	for p: Dictionary in r.get("path", []):
		reach = maxf(reach, float(p.t1))
	var col: Color = OUTCOME_COLOURS.get(String(r.get("outcome", "")), Color.WHITE)
	_rod(entry - dir * 4.0, entry, Color(1.0, 0.85, 0.3))
	if reach > 0.0:
		_rod(entry, entry + dir * reach, col)
	var dot := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	dot.mesh = sphere
	dot.material_override = _unshaded(col, 1.0)
	dot.position = entry
	_root3d.add_child(dot)
	var plate := HitReport.plate_of(spec, String(r.get("plate", "")))
	var n := ArmourModel.normal_of(plate, dir) if not plate.is_empty() else -dir
	var a := -dir
	if a.angle_to(n) > 0.01:
		var axis := a.cross(n).normalized()
		var steps := 12
		var prev := entry + a * 0.6
		for i in range(1, steps + 1):
			var q := entry + a.rotated(axis, a.angle_to(n) * i / steps) * 0.6
			lines.surface_set_color(Color(1, 1, 1))
			lines.surface_add_vertex(prev)
			lines.surface_add_vertex(q)
			prev = q
	lines.surface_set_color(Color(0.7, 0.85, 1.0))
	lines.surface_add_vertex(entry)
	lines.surface_add_vertex(entry + n * 0.8)
	for sp: Array in r.get("spall", []):
		var sd := Vector3(float(sp[0]), float(sp[1]), float(sp[2]))
		lines.surface_set_color(Color(1.0, 0.55, 0.2))
		lines.surface_add_vertex(entry + dir * 0.02)
		lines.surface_add_vertex(entry + dir * 0.02 + sd * float(sp[3]))


func _box(b: AABB, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = b.size
	mi.mesh = bm
	mi.material_override = _unshaded(c, c.a)
	mi.position = b.get_center()
	_root3d.add_child(mi)


func _capsule(b: AABB, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.2
	cm.height = clampf(b.size.y, 0.6, 1.8)
	mi.mesh = cm
	mi.material_override = _unshaded(c, 0.85)
	mi.position = b.get_center()
	_root3d.add_child(mi)


## A thick line (a thin cylinder) from `a` to `b`.
func _rod(a: Vector3, b: Vector3, c: Color) -> void:
	var length := a.distance_to(b)
	if length < 0.01:
		return
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.035
	cyl.height = length
	cyl.radial_segments = 6
	mi.mesh = cyl
	mi.material_override = _unshaded(c, 1.0)
	var up := (b - a) / length
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(side, up, side.cross(up)).orthonormalized(), (a + b) * 0.5)
	_root3d.add_child(mi)


static func _edges(lines: ImmediateMesh, b: AABB, c: Color) -> void:
	lines.surface_set_color(c)
	for i in 12:
		var e := b.get_endpoint(EDGES[i][0])
		var f := b.get_endpoint(EDGES[i][1])
		lines.surface_set_color(c)
		lines.surface_add_vertex(e)
		lines.surface_add_vertex(f)


## AABB.get_endpoint's corners joined into its 12 edges.
const EDGES := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]


static func _unshaded(c: Color, alpha: float, vertex_colours := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c, alpha)
	m.vertex_color_use_as_albedo = vertex_colours
	if alpha < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = false
	return m


func _place_camera() -> void:
	var off := Basis.from_euler(Vector3(_pitch, _yaw, 0.0)) * Vector3(0, 0, _dist)
	_cam.transform = Transform3D(Basis.looking_at(-off.normalized(), Vector3.UP), _centre + off)  # (the viewport's own world: its frame is the vehicle's)


func _on_model_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_dist = maxf(_dist * 0.9, 3.0)
	elif mb and mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_dist = minf(_dist * 1.1, 40.0)
	elif mb and mb.button_index == MOUSE_BUTTON_RIGHT:
		_drag = mb.pressed
	elif mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if not analysis.is_empty():
			analyse_at(mb.position)
		else:
			_drag = true
	elif mb and not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_drag = false
	var mm := event as InputEventMouseMotion
	if mm and _drag:
		_yaw -= mm.relative.x * ORBIT_PER_PX
		_pitch = clampf(_pitch - mm.relative.y * ORBIT_PER_PX, -1.4, 0.6)
	_place_camera()


# --- Protection analysis ------------------------------------------------------------------------

## A click at `at` (the model's pixels): the plate it meets, and the prediction there.
func analyse_at(at: Vector2) -> Dictionary:
	var model := String(analysis.get("model", ""))
	var spec := VehicleSpecs.spec(model)
	var from := _cam.project_ray_origin(at)
	var dir := _cam.project_ray_normal(at)
	var hit := ray_plates(spec, from, dir)
	if hit.is_empty():
		_result.text = "Missed the vehicle: click on it"
		return {}
	var sid := String(_shell_pick.get_item_metadata(maxi(_shell_pick.selected, 0)))
	var range_m := float(RANGES_M[clampi(_range_pick.selected, 0, RANGES_M.size() - 1)])
	var out := predict(model, sid, range_m, hit.point, dir, analysis.get("packages", []))
	_result.text = analysis_text(out)
	_draw_model(model, _live_model(model), {"entry": [hit.point.x, hit.point.y, hit.point.z], "dir": [dir.x, dir.y, dir.z], "plate": String(out.get("plate", "")),
		"outcome": String(out.get("outcome", "")), "path": []})
	return out


## Where a ray from `from` along `dir` (the vehicle's frame) first meets one of `spec`'s plates:
## {"point", "plate"} or {}.
static func ray_plates(spec: Dictionary, from: Vector3, dir: Vector3) -> Dictionary:
	var best := INF
	var out := {}
	for p: Dictionary in spec.get("plates", []):
		var b := VehicleSpecs.box(p.box)
		var hit: Variant = b.intersects_ray(from, dir)
		if hit is Vector3 and from.distance_to(hit) < best:
			best = from.distance_to(hit)
			out = {"point": hit, "plate": String(p.id)}
	return out


## Pure: what ArmourModel.resolve says shell `sid` fired from `range_m` does at `local` along
## `ldir` on `model` (fitted with `packages`, its tiles all whole) with the fixed ANALYSIS_SEED, and
## the ricochet chance over RICOCHET_SAMPLES seeds: the HitResult plus "ricochet_chance" (0..1).
static func predict(model: String, sid: String, range_m: float, local: Vector3, ldir: Vector3, packages: Array = []) -> Dictionary:
	var spec := VehicleSpecs.spec(model)
	var shell := Shells.shell(sid)
	var plate := ArmourModel.plate_at(spec, local, ldir)
	if plate.is_empty() or shell.is_empty():
		return {}
	plate = ArmourModel.with_packages(plate, spec, ArmourModel.fitted_packages(spec, packages))
	var shot := {"dir": ldir, "range_m": range_m, "check_arming": true, "seed": ANALYSIS_SEED, "tiles": ArmourModel.tiles_at(spec, local, packages, {})}
	var out := ArmourModel.resolve(shell, plate, shot)
	var bounces := 0
	for i in RICOCHET_SAMPLES:
		shot.seed = ANALYSIS_SEED + 1 + i
		if ArmourModel.resolve(shell, plate, shot).outcome == ArmourModel.RICOCHET:
			bounces += 1
	out["ricochet_chance"] = float(bounces) / RICOCHET_SAMPLES
	out["range_m"] = range_m
	out["shell_name"] = String(shell.get("name", sid))
	return out


## "M829A3 APFSDS-T at 1000 m on Turret front, 12 degrees: 912 mm effective against 780 mm.
## NON-PENETRATION (ricochet 0%)".
static func analysis_text(out: Dictionary) -> String:
	if out.is_empty():
		return "Nothing to say there"
	return "%s at %d m on %s, %d degrees: %d mm effective against %d mm. %s (ricochet %d%%)" % [String(out.get("shell_name", "")),
		roundi(float(out.get("range_m", 0.0))), HitReport.plate_name(String(out.get("plate", ""))), roundi(float(out.get("theta_deg", 0.0))),
		roundi(float(out.get("t_eff", 0.0))), roundi(float(out.get("pen", 0.0))),
		String(HitReport.OUTCOME_WORDS.get(String(out.get("outcome", "")), String(out.get("outcome", "")).to_upper())), roundi(float(out.get("ricochet_chance", 0.0)) * 100.0)]
