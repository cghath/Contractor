extends Node
## Plays back a co-op soak replay (tests/coop_soak_recorder.gd's replay.jsonl) in the real
## level (the base, or the zone generated again from its definition), offline: no network, no
## AI, nothing simulated. Soldiers are drawn as markers (players blue, squad AI green, hostiles
## red; lying down when down, grey when dead) with their name and blood over them; shots are
## tracers, hits flash. A follow camera takes each player in turn, with an overhead view in the
## corner. Given a client's replay too (--compare), every soldier the two disagree about gets a
## magenta flag and a ghost where the client had it.
##
## Rendered to a video with Godot's Movie Maker (tools/coop_replay.sh does all this):
##   <godot> --path . --gpu-index 0 --resolution 1280x720 --fixed-fps 30 --write-movie out.avi \
##       res://tests/coop_replay.tscn -- --replay <run>/host/replay.jsonl [--compare <run>/client1/replay.jsonl] \
##       [--cut highlights|full] [--speed 4] [--from S --to S]
## --cut highlights (default): first contact, a player going down and being treated back up,
## the reconnect, and the extraction, from the first two contracts; --cut full: the whole run at
## --speed (4 by default). Without --write-movie it plays in a window. Quits at the end.

const FLAGS := preload("res://tests/coop_soak_recorder.gd")
const POS_TOL := 2.5
const SWITCH_HOLD_FRAMES := 45  # frames held after a level loads (the voxels mesh in)
const CAM_TURN_S := 12.0         # video seconds on each player before the next

var frames: Array = []          # parsed replay frames (dicts), host's
var compare: Array = []         # the client's, or []
var compare_t: PackedFloat64Array = PackedFloat64Array()
var segments: Array = []        # [{"from", "to", "speed", "title", "focus"}] in replay time
var level: CompoundLevel
var level_key := ""
var info_at: PackedInt32Array = PackedInt32Array()  # frame index -> index of the frame holding its level info
var puppets := {}               # key -> Node3D
var cam: Camera3D
var top_cam: Camera3D
var hud: Label
var feed: Label
var title: Label
var _viewer: Node3D
var _seg := 0
var _t := 0.0
var _i := 0
var _hold := 0
var _cam_left := 0.0
var _cam_target := ""
var _feed_lines: Array[String] = []
var _tracers: Array = []        # [MeshInstance3D, seconds left]
var _speed := 1.0
var _start_t := 0.0
## Draw soldiers with the game's own body (soldier.tscn, nothing simulated: placed each frame,
## posed from the replay) instead of capsules (--capsules).
var models := true
## Render layers: names only in the main view, map discs only in the overhead one.
const LABEL_LAYER := 1 << 10
const MAP_LAYER := 1 << 11


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var path := _arg(args, "--replay", "")
	if path == "" or not FileAccess.file_exists(path):
		push_error("coop_replay: no --replay file (%s)" % path)
		get_tree().quit(2)
		return
	CompoundLevel.spawn_ai = false
	Ragdoll.enabled = false  # a puppet lies down posed, not as physics
	models = not args.has("--capsules")
	frames = _load(path)
	var cpath := _arg(args, "--compare", "")
	if cpath != "" and FileAccess.file_exists(cpath):
		compare = _load(cpath)
		for f: Dictionary in compare:
			compare_t.append(float(f.t))
	if frames.is_empty():
		push_error("coop_replay: the replay is empty")
		get_tree().quit(2)
		return
	_start_t = float(frames[0].t)
	var last := -1
	for i in frames.size():
		if frames[i].has("info"):
			last = i
		info_at.append(last)
	var cut := _arg(args, "--cut", "highlights")
	_speed = float(_arg(args, "--speed", "4" if cut == "full" else "1"))
	if args.has("--from"):
		segments = [{"from": _start_t + float(_arg(args, "--from", "0")), "to": _start_t + float(_arg(args, "--to", "99999")),
			"speed": _speed, "title": "", "focus": ""}]
	elif cut == "full":
		segments = [{"from": _start_t, "to": float(frames[-1].t), "speed": _speed, "title": "Full run (x%s)" % _speed, "focus": ""}]
	else:
		segments = _highlights()
	print("[replay] %d frames (%.0f s), %d segments: %s" % [frames.size(), float(frames[-1].t) - _start_t, segments.size(),
		JSON.stringify(segments.map(func(s: Dictionary) -> String: return "%s %.0f-%.0f x%.1f" % [s.title, s.from - _start_t, s.to - _start_t, s.speed]))])
	_build_view()
	_begin_segment(0)


static func _arg(args: PackedStringArray, flag: String, fallback: String) -> String:
	var i := args.find(flag)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


static func _load(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	while f and not f.eof_reached():
		var line := f.get_line()
		if line.is_empty():
			continue
		var d: Variant = JSON.parse_string(line)
		if d is Dictionary and d.has("t"):
			out.append(d)
	return out


# --- The cut ------------------------------------------------------------------------------------

## Contact, a down and revive, the reconnect and the extraction, from the first two contracts.
func _highlights() -> Array:
	var out: Array = []
	var phase_at := {}  # "cycle:phase" -> first time
	var first_fire := {}  # cycle -> time
	var downs: Array = []  # [time, key, cycle]
	var ups := {}  # key -> [times]
	var joins: Array = []
	var leaves: Array = []
	var cycle := 0
	var base_after := {}  # cycle -> first time back at the base after its extract
	for f: Dictionary in frames:
		var t := float(f.t)
		if f.has("ph"):
			var ph := String(f.ph)
			cycle = int(ph.get_slice(":", 0))
			if not phase_at.has(ph):
				phase_at[ph] = t
		if phase_at.has("%d:extract" % cycle) and String(f.get("L", "")) == "base" and not base_after.has(cycle):
			base_after[cycle] = t
		for e: Array in f.get("e", []):
			match String(e[0]):
				"fire":
					if not first_fire.has(cycle) and phase_at.has("%d:fight" % cycle):
						first_fire[cycle] = t
				"down":
					if String(e[1]).begins_with("Players/"):
						downs.append([t, String(e[1]), cycle])
				"up":
					if not ups.has(String(e[1])):
						ups[String(e[1])] = []
					ups[String(e[1])].append(t)
				"join":
					joins.append(t)
				"leave":
					leaves.append(t)
	for c in [1, 2]:
		if first_fire.has(c):
			out.append({"from": first_fire[c] - 3.0, "to": first_fire[c] + (40.0 if c == 1 else 25.0), "speed": 1.0, "title": "Contract %d: contact" % c, "focus": ""})
		elif phase_at.has("%d:fight" % c):
			out.append({"from": phase_at["%d:fight" % c], "to": phase_at["%d:fight" % c] + 30.0, "speed": 1.0, "title": "Contract %d: the fight" % c, "focus": ""})
		for d: Array in downs:
			if int(d[2]) != c:
				continue
			var back := float(d[0]) + 60.0
			for t: float in ups.get(d[1], []):
				if t > float(d[0]):
					back = t
					break
			var length := back - float(d[0]) + 10.0
			out.append({"from": float(d[0]) - 5.0, "to": back + 5.0, "speed": maxf(1.0, length / 40.0),
				"title": "Contract %d: %s down, treated back up" % [c, d[1]], "focus": String(d[1])})
			break
		if c == 1:
			for t: float in leaves:
				out.append({"from": t - 3.0, "to": t + 6.0, "speed": 1.0, "title": "A player leaves mid-deployment", "focus": ""})
				break
			for t: float in joins:
				if not leaves.is_empty() and t > float(leaves[0]):
					out.append({"from": t - 2.0, "to": t + 8.0, "speed": 1.0, "title": "...and joins again", "focus": ""})
					break
		if phase_at.has("%d:extract" % c):
			var from := float(phase_at["%d:extract" % c])
			var to := float(base_after.get(c, from + 60.0)) + 4.0
			out.append({"from": from, "to": to, "speed": maxf(1.0, (to - from) / 45.0), "title": "Contract %d: extraction" % c, "focus": ""})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.from < b.from)
	# Overlapping pieces become one.
	var merged: Array = []
	for s: Dictionary in out:
		if not merged.is_empty() and s.from <= merged[-1].to:
			merged[-1].to = maxf(merged[-1].to, s.to)
			merged[-1].speed = maxf(merged[-1].speed, s.speed)
			continue
		merged.append(s)
	if merged.is_empty():
		merged.append({"from": _start_t, "to": float(frames[-1].t), "speed": 4.0, "title": "Whole run (no highlights found)", "focus": ""})
	return merged


# --- The view -----------------------------------------------------------------------------------

func _build_view() -> void:
	cam = Camera3D.new()
	cam.cull_mask &= ~MAP_LAYER
	cam.fov = 70.0
	cam.far = 3000.0
	add_child(cam)
	cam.current = true
	_viewer = Node3D.new()
	add_child(_viewer)
	var viewer := VoxelViewer.new()
	viewer.view_distance = VoxelWorld.VIEW_DISTANCE
	viewer.requires_visuals = true
	viewer.requires_collisions = false
	_viewer.add_child(viewer)
	var ui := CanvasLayer.new()
	add_child(ui)
	# The overhead view, top right.
	var box := SubViewportContainer.new()
	box.stretch = true
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -330.0
	box.offset_right = -10.0
	box.offset_top = 10.0
	box.offset_bottom = 250.0
	ui.add_child(box)
	var sub := SubViewport.new()
	sub.size = Vector2i(320, 240)
	sub.world_3d = get_viewport().find_world_3d()
	box.add_child(sub)
	top_cam = Camera3D.new()
	top_cam.cull_mask &= ~LABEL_LAYER
	top_cam.fov = 60.0
	top_cam.far = 3000.0
	sub.add_child(top_cam)
	top_cam.current = true
	hud = _label(ui, Vector2(12, 8), 18)
	feed = _label(ui, Vector2(12, 470), 15)
	feed.anchor_top = 1.0
	feed.anchor_bottom = 1.0
	feed.offset_top = -190.0
	title = _label(ui, Vector2(0, 0), 30)
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.anchor_top = 0.5
	title.offset_left = -500
	title.offset_right = 500
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _label(parent: Node, at: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = at
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_outline_color", Color.BLACK)
	l.add_theme_constant_override(&"outline_size", 6)
	parent.add_child(l)
	return l


func _begin_segment(n: int) -> void:
	_seg = n
	if _seg >= segments.size():
		print("[replay] done")
		get_tree().quit(0)
		return
	var s: Dictionary = segments[_seg]
	_t = float(s.from)
	_i = _frame_at(_t)
	title.text = String(s.title)
	_hold = SWITCH_HOLD_FRAMES
	_ensure_level(_i)
	_cam_left = 0.0
	_cam_target = String(s.get("focus", ""))
	_feed_lines.clear()


func _frame_at(t: float) -> int:
	var lo := 0
	var hi := frames.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if float(frames[mid].t) <= t:
			lo = mid
		else:
			hi = mid - 1
	return lo


## The level the replay was in at frame `i` (loaded again when it changed).
func _ensure_level(i: int) -> void:
	var holder := info_at[i]
	if holder < 0:
		return
	var info: Dictionary = frames[holder].info
	var key := JSON.stringify(info)
	if key == level_key:
		return
	level_key = key
	for p in puppets.values():
		(p as Node).queue_free()
	puppets.clear()
	if info.is_empty():
		return
	level = LevelSwitch.load_level(self, info, true)
	_hold = SWITCH_HOLD_FRAMES * 2
	print("[replay] level %s" % String(info.get("level", "?")))


func _process(delta: float) -> void:
	if _seg >= segments.size() or frames.is_empty():
		return
	var s: Dictionary = segments[_seg]
	if _hold > 0:
		_hold -= 1
		title.modulate.a = 1.0
	else:
		title.modulate.a = maxf(title.modulate.a - delta * 0.5, 0.0)
		_t += delta * float(s.speed)
	if _t >= float(s.to) or _i >= frames.size() - 1:
		_begin_segment(_seg + 1)
		return
	while _i < frames.size() - 1 and float(frames[_i + 1].t) <= _t:
		_i += 1
		_ensure_level(_i)
		_events(frames[_i])
	_draw_frame(delta)


func _events(f: Dictionary) -> void:
	for e: Array in f.get("e", []):
		var what := String(e[0])
		var key := String(e[1]) if e.size() > 1 else ""
		match what:
			"fire":
				if e.size() >= 5 and puppets.has(key):
					_tracer((puppets[key] as Node3D).global_position + Vector3.UP * 1.5, Vector3(float(e[2]), float(e[3]), float(e[4])))
			"hit":
				_feed("%s hit (-%d%% blood)" % [_name(key), int(float(e[2]) * 100.0)])
				if puppets.has(key):
					_flash(puppets[key])
			"down", "up", "dead":
				_feed("%s %s" % [_name(key), {"down": "is DOWN", "up": "is back up", "dead": "is dead"}[what]])
			"obj":
				_feed("objective %s: %s" % [key, String(e[2])])
			"phase":
				_feed("phase %s" % key)
			"join", "leave", "joined", "lost", "leave_on_purpose":
				_feed("peer %s %s" % [key, what])
			"note":
				if key.begins_with("PROBLEM") or "knocking" in key or "treated" in key or "insertion" in key:
					_feed(key.left(90))


func _name(key: String) -> String:
	for row: Array in frames[_i].get("s", []):
		if String(row[0]) == key:
			return String(row[8])
	return key


func _feed(text: String) -> void:
	_feed_lines.append("%s  %s" % [_clock(_t), text])
	while _feed_lines.size() > 8:
		_feed_lines.pop_front()
	feed.text = "\n".join(_feed_lines)


func _clock(t: float) -> String:
	var s := int(t - _start_t)
	return "%02d:%02d" % [floori(s / 60.0), s % 60]


func _draw_frame(delta: float) -> void:
	var a: Dictionary = frames[_i]
	var b: Dictionary = frames[mini(_i + 1, frames.size() - 1)]
	var span := maxf(float(b.t) - float(a.t), 0.001)
	var w := clampf((_t - float(a.t)) / span, 0.0, 1.0)
	var next := {}
	for row: Array in b.get("s", []):
		next[String(row[0])] = row
	var seen := {}
	var client := _compare_frame(_t)
	var flagged := 0
	var players: Array[String] = []
	for row: Array in a.get("s", []):
		var key := String(row[0])
		seen[key] = true
		var p := Vector3(float(row[1]), float(row[2]), float(row[3]))
		var nrow: Array = next.get(key, row)
		p = p.lerp(Vector3(float(nrow[1]), float(nrow[2]), float(nrow[3])), w)
		var flags := int(row[6])
		if flags & FLAGS.F_PLAYER:
			players.append(key)
		var puppet := _puppet(key, flags)
		puppet.global_position = p
		puppet.rotation.y = lerp_angle(float(row[4]), float(nrow[4]), w)
		var lying := not (flags & FLAGS.F_UP)
		var disc: MeshInstance3D = puppet.get_node(^"Disc")
		(disc.material_override as StandardMaterial3D).albedo_color = _colour(flags)
		var soldier := puppet.get_node_or_null(^"Soldier") as Soldier
		if soldier:
			soldier.vitals.downed = lying
			soldier.is_aiming = bool(flags & FLAGS.F_AIM) and not lying
			soldier.is_reloading = bool(flags & FLAGS.F_RELOAD)
			soldier.head.rotation.x = float(row[5])
			soldier.role = StringName(String(row[9]))
		else:
			var body: Node3D = puppet.get_node(^"Body")
			body.rotation.x = -PI / 2.0 if lying else 0.0
			body.position.y = 0.3 if lying else 0.9
			var mat: StandardMaterial3D = (body as MeshInstance3D).material_override
			mat.albedo_color = _colour(flags)
			var aim: Node3D = puppet.get_node(^"Aim")
			aim.visible = bool(flags & FLAGS.F_AIM) and not lying
			aim.rotation.x = float(row[5])
		var label: Label3D = puppet.get_node(^"Label")
		var state := "DEAD" if flags & FLAGS.F_DEAD else ("DOWN" if flags & FLAGS.F_DOWNED else "")
		var text := "%s\n%d%%%s" % [String(row[8]), int(float(row[7]) * 100.0), (" " + state) if state != "" else ""]
		var ghost: Node3D = puppet.get_node(^"Ghost")
		ghost.visible = false
		label.modulate = Color.WHITE if not (flags & FLAGS.F_HOSTILE) else Color(1.0, 0.75, 0.75)
		if not client.is_empty():
			var c: Array = client.get(key, [])
			var why := ""
			if c.is_empty():
				why = "missing on client"
			else:
				var cp := Vector3(float(c[1]), float(c[2]), float(c[3]))
				var d := cp.distance_to(p)
				if d > POS_TOL + 3.0:
					why = "%.1f m off" % d
					ghost.visible = true
					ghost.global_position = cp
				if (int(c[6]) & (FLAGS.F_UP | FLAGS.F_DOWNED | FLAGS.F_DEAD)) != (flags & (FLAGS.F_UP | FLAGS.F_DOWNED | FLAGS.F_DEAD)):
					why += (", " if why != "" else "") + "condition differs"
			if why != "":
				text += "\n!! " + why
				label.modulate = Color(1.0, 0.3, 1.0)
				flagged += 1
		label.text = text
	for key: String in puppets.keys():
		if not seen.has(key):
			(puppets[key] as Node).queue_free()
			puppets.erase(key)
	_update_tracers(delta)
	_update_cameras(delta, players)
	var s: Dictionary = segments[_seg]
	hud.text = "Co-op soak replay   %s   %s   x%.1f\nphase %s   level %s   soldiers %d%s" % [_clock(_t), String(s.title), float(s.speed),
		_phase_at(_i), String(a.get("L", "")), a.get("s", []).size(), ("   client disagrees on %d" % flagged) if not client.is_empty() else ""]


func _phase_at(i: int) -> String:
	for j in range(i, -1, -1):
		if frames[j].has("ph"):
			return String(frames[j].ph)
	return ""


## The client's frame nearest `t`, as key -> row, or {}.
func _compare_frame(t: float) -> Dictionary:
	if compare.is_empty():
		return {}
	var lo := 0
	var hi := compare_t.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if compare_t[mid] <= t:
			lo = mid
		else:
			hi = mid - 1
	var f: Dictionary = compare[lo]
	if absf(float(f.t) - t) > 0.5 or String(f.get("L", "")) != String(frames[_i].get("L", "")):
		return {}
	var out := {}
	for row: Array in f.get("s", []):
		out[String(row[0])] = row
	return out


func _colour(flags: int) -> Color:
	if flags & FLAGS.F_DEAD:
		return Color(0.35, 0.35, 0.35)
	var c := Color(0.2, 0.45, 1.0) if flags & FLAGS.F_PLAYER else (Color(0.9, 0.2, 0.15) if flags & FLAGS.F_HOSTILE else Color(0.25, 0.8, 0.3))
	if flags & FLAGS.F_DOWNED:
		c = c.lerp(Color(1.0, 0.9, 0.1), 0.5)
	return c


func _puppet(key: String, flags: int) -> Node3D:
	if puppets.has(key):
		return puppets[key]
	var root := Node3D.new()
	var disc := MeshInstance3D.new()  # the overhead view's marker
	disc.name = "Disc"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.6
	cyl.bottom_radius = 1.6
	cyl.height = 0.2
	disc.mesh = cyl
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = _colour(flags)
	disc.material_override = dmat
	disc.layers = MAP_LAYER
	disc.position.y = 3.0
	root.add_child(disc)
	if models:
		_add_model(root, key, flags)
	else:
		_add_capsule(root, flags)
	var label := Label3D.new()
	label.name = "Label"
	label.layers = LABEL_LAYER
	label.position = Vector3(0, 2.3, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.font_size = 28
	label.outline_size = 8
	root.add_child(label)
	var ghost := MeshInstance3D.new()
	ghost.name = "Ghost"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	ghost.mesh = capsule
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(1.0, 0.2, 1.0, 0.45)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost.material_override = gmat
	ghost.top_level = true
	ghost.visible = false
	root.add_child(ghost)
	add_child(root)
	puppets[key] = root
	return root


## The game's soldier body as a puppet: an AI-named Soldier (so no player input or camera),
## nothing simulated (no physics step, no wound model, no voxel streaming of its own), in its
## side's camo with a rifle, armour and helmet.
func _add_model(root: Node3D, key: String, flags: int) -> void:
	var s := CompoundLevel.PLAYER_SCENE.instantiate() as Soldier
	s.name = "Soldier"
	s.faction = &"hostile" if flags & FLAGS.F_HOSTILE else &"friendly"
	s.variant = "urban" if flags & FLAGS.F_HOSTILE else ("multicam" if flags & FLAGS.F_PLAYER else "woodland")
	s.set_meta(&"replay_key", key)
	root.add_child(s)
	s.set_physics_process(false)
	s.vitals.process_mode = Node.PROCESS_MODE_DISABLED
	s.collision_layer = 0
	s.collision_mask = 0
	for n in s.get_children():
		if n is VoxelViewer:
			n.queue_free()
	for id: StringName in [&"m4a1", &"plate_carrier", &"helmet"]:
		s.inventory.take(id)
	s.remove_from_group(&"combatants")


func _add_capsule(root: Node3D, flags: int) -> void:
	var body := MeshInstance3D.new()
	body.name = "Body"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	body.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _colour(flags)
	body.material_override = mat
	body.position.y = 0.9
	root.add_child(body)
	var nose := MeshInstance3D.new()  # which way it faces
	var box := BoxMesh.new()
	box.size = Vector3(0.18, 0.12, 0.35)
	nose.mesh = box
	nose.position = Vector3(0, 0.6, -0.3)
	body.add_child(nose)
	var aim := Node3D.new()
	aim.name = "Aim"
	aim.position = Vector3(0, 1.45, 0)
	var line := MeshInstance3D.new()
	var rod := BoxMesh.new()
	rod.size = Vector3(0.04, 0.04, 1.2)
	line.mesh = rod
	line.position = Vector3(0, 0, -0.6)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(1, 1, 0.3)
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.material_override = lmat
	aim.add_child(line)
	root.add_child(aim)


func _tracer(from: Vector3, dir: Vector3) -> void:
	var m := MeshInstance3D.new()
	var rod := BoxMesh.new()
	rod.size = Vector3(0.05, 0.05, 40.0)
	m.mesh = rod
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.3)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	add_child(m)
	m.global_position = from + dir.normalized() * 20.0
	if dir.length() > 0.01:
		m.look_at(from + dir.normalized() * 40.0, Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT)
	_tracers.append([m, 0.12])


func _flash(puppet: Node3D) -> void:
	var m := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	m.mesh = ball
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 0, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	add_child(m)
	m.global_position = puppet.global_position + Vector3.UP * 1.2
	_tracers.append([m, 0.25])


func _update_tracers(delta: float) -> void:
	for tr: Array in _tracers.duplicate():
		tr[1] = float(tr[1]) - delta
		if float(tr[1]) <= 0.0:
			(tr[0] as Node).queue_free()
			_tracers.erase(tr)


func _update_cameras(delta: float, players: Array[String]) -> void:
	_cam_left -= delta
	var s: Dictionary = segments[_seg]
	if String(s.get("focus", "")) != "" and puppets.has(String(s.focus)):
		_cam_target = String(s.focus)
	elif _cam_left <= 0.0 or not puppets.has(_cam_target):
		_cam_left = CAM_TURN_S
		if not players.is_empty():
			var at := players.find(_cam_target)
			_cam_target = players[(at + 1) % players.size()]
	var centre := Vector3.ZERO
	if puppets.has(_cam_target):
		var target: Node3D = puppets[_cam_target]
		var back := target.global_basis.z
		back.y = 0.0
		back = back.normalized() if back.length() > 0.01 else Vector3.BACK
		var want := target.global_position + back * 6.0 + Vector3.UP * 3.2
		cam.global_position = cam.global_position.lerp(want, minf(delta * 3.0, 1.0)) if cam.global_position.distance_to(want) < 30.0 else want
		cam.look_at(target.global_position + Vector3.UP * 1.4, Vector3.UP)
		centre = target.global_position
	elif not puppets.is_empty():
		centre = (puppets.values()[0] as Node3D).global_position
		cam.global_position = centre + Vector3(0, 25, 25)
		cam.look_at(centre, Vector3.UP)
	# Overhead: over the players' middle, high enough for them all.
	var sum := Vector3.ZERO
	var n := 0
	var spread := 20.0
	for key: String in players:
		if puppets.has(key):
			sum += (puppets[key] as Node3D).global_position
			n += 1
	if n > 0:
		var mid := sum / n
		for key: String in players:
			if puppets.has(key):
				spread = maxf(spread, (puppets[key] as Node3D).global_position.distance_to(mid) * 2.5)
		top_cam.global_position = mid + Vector3(0, spread + 25.0, 0.01)
		top_cam.look_at(mid, Vector3.FORWARD)
	_viewer.global_position = centre
