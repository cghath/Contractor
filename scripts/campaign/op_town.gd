class_name OpTown
extends OpBase
## Holding a captured town (docs/combined_arms.md 6.4.5; phase D5, cg_brief queue item 3.3). The town
## has just been taken (its garrisons are gone, its cells ours): the company is its garrison with an
## allied platoon, two Bradleys and a mortar section (the friendly OOB, "at" the town). The zone is
## a city where cghath's city work allows (D1-12), the company inserting in it (OperationGen).
##
## - Prepare (phase 1, its clock on the strip): dig in (the e-tool: Digging), site the company's guns
##   with their cones (C4's map placement), and place defences from the budget: "budget" pieces of
##   sandbag wall, HESCO or concertina wire ("pieces"), each where a player puts it (Support >
##   Operation > Field defences: DefencePlacer's field mode, within "radius_m" of the centre), a
##   solid piece with collision and cover on every peer (and for a late joiner), saved with the run.
##   The employer's engineers' stores: no charge.
## - The counterattack (phase 2): two or three waves ("counter") over 25-35 minutes from the enemy's
##   side, each from the axis its commander picks from its picture (OpBase.pick_axis): what it has
##   seen of the defence. A piece is seen once a live enemy within "seen_m" has a line of sight to it
##   (or its picture has a contact on it); a piece it hasn't seen it doesn't plan around, so a hidden
##   gun pays off. The second wave brings its technicals, its mortar first.
## - Win: the town centre held to the end ("op_hold_centre": every wave out and beaten, or "hold_s"
##   with the centre ours). Fail: the enemy holds the centre for "hold_fail_s" with none of ours in
##   it (as defend_hold).
## Numbers in data/operations.json "hold_town" "town", Proposed.

const NODE_GROUP := &"op_field_defences"
const HOLD_CENTRE := "op_hold_centre"
const TICK_S := 1.0

var _tick_left := 0.0
var _seen_left := 0.0
var _bodies := {}  # every peer: piece id -> StaticBody3D


static func of(from: Node) -> OpTown:
	var o := Operations.of(from)
	return o.get_node_or_null(OpTypes.MECHANIC) as OpTown if o else null


func pieces() -> Array:
	return mine().get("pieces", []) if _host() else state.get("pieces", [])


static func catalogue() -> Dictionary:
	return (Operations.type_def("hold_town").get("town", {}) as Dictionary).get("pieces", {})


func centre() -> Vector3:
	var at := Operations.resolve(ops.def, {"site": "@town"})
	return v3(at[0].pos) if not at.is_empty() else v3(ops.def.op.get("start", [0, 0]))


func start() -> void:
	var m := mine()
	if not m.has("pieces"):
		m["pieces"] = []
		m["next"] = 1
		# The town is ours: its garrisons are gone, its ground ours.
		var r := run()
		var lvl := level() as ZoneLevel
		var c := centre()
		for mod: Dictionary in ops.def.get("modules", []):
			var id := String(mod.id)
			var p := v3(mod.pos)
			if (id == "town" or id.begins_with("city")) or (ZoneModules.base(String(mod.type)) in Operations.ENEMY_SITES and Vector2(p.x - c.x, p.z - c.z).length() < num("town", "taken_m", 700.0)):
				if not id in (r.taken as Array):
					(r.taken as Array).append(id)
				if lvl and lvl.get_module(id):
					lvl._garrisoned[id] = maxi(int(lvl._garrisoned.get(id, 0)), lvl.garrison_size(id))
		var moved := ops.grid.set_cells(ops.grid.cells_within(Vector2(c.x, c.z), num("town", "taken_m", 700.0)), FrontGrid.FRIENDLY)
		if not moved.is_empty():
			ops._front_moved(moved)
		var allies := PackedStringArray()
		for e: Dictionary in contract().get("friendly_oob", []):
			allies.append(String(e.get("callsign", e.get("kind", ""))))
		note("The company took over the town's defence beside %s." % ", ".join(allies))
	_refresh()
	_on_state()


func tick(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick_left -= dt
	if _tick_left > 0.0:
		return
	_tick_left = TICK_S
	if String(run().get("state", "")) != Operations.RUNNING:
		return
	_seen_left -= TICK_S
	if _seen_left <= 0.0:
		_seen_left = num("town", "seen_every_s", 5.0)
		_look()
	var phases: Array = contract().get("phases", [])
	if phase() == phases.size() - 1:
		counter_step("town", centre(), ops._axis(), seen_points())
	_refresh()
	cost_us = float(Time.get_ticks_usec() - t0)
	if not heavy:
		worst_us = maxf(worst_us, cost_us)
	heavy = false


func phase_done(k: int) -> void:
	if k == 0:
		var placed := pieces().size()
		note("The defence was ready in time: %d of %d pieces placed." % [placed, int(num("town", "budget", 6))])
		say("Citadel: time's up. Here they come: hold the centre.")


## The hold: done with every wave out and beaten (or hold_s with the centre ours); failed when the
## enemy holds the centre for hold_fail_s with none of ours there.
func task(o: Dictionary, _dt: float) -> String:
	if String(o.kind) != HOLD_CENTRE:
		return ""
	var params: Dictionary = o.get("params", {})
	var k := int(params.get("phase", -1))
	var c := centre()
	if held_by_enemy("centre", c, num("town", "centre_m", 60.0), TICK_S, num("town", "hold_fail_s", 60.0)):
		note("The enemy held the town centre for %d s with none of ours in it." % roundi(num("town", "hold_fail_s", 60.0)))
		return Objectives.FAILED
	var recs: Array = run().get("phases", [])
	var since := clock() - float((recs[k] as Dictionary).get("started_s", clock())) if k >= 0 and k < recs.size() else 0.0
	if counter_beaten("town", k) and since >= num("town", "min_hold_s", 600.0):
		note("Every wave of the counterattack was beaten off (%s)." % Operations.clock_text(since))
		return Objectives.DONE
	if since >= float(params.get("hold_s", 1800.0)) and ops.grid.owner_at(Vector2(c.x, c.z)) == FrontGrid.FRIENDLY:
		note("The town centre was held to the end (%s)." % Operations.clock_text(since))
		return Objectives.DONE
	var waves: Dictionary = mine().get("waves", {})
	Contracts.objectives.server_set_state(String(o.oid), Objectives.ACTIVE, "waves %d of %d, held %s" % [waves.size(), (cfg("town").get("counter", []) as Array).size(), Operations.clock_text(since)])
	return ""


# --- What the enemy has seen (host) ----------------------------------------------------------------

func seen_points() -> Array:
	var out: Array = []
	for p: Dictionary in mine().get("pieces", []):
		if bool(p.get("seen", false)):
			out.append(Vector3(float(p.pos[0]), float(p.pos[1]), float(p.pos[2])))
	return out


## Each piece not yet seen: an enemy up within seen_m with a line of sight to it, or its picture's
## contact on it.
func _look() -> void:
	var lvl := level() as Node3D
	if lvl == null or not lvl.is_inside_tree():
		return
	var space := lvl.get_world_3d().direct_space_state
	var reach := num("town", "seen_m", 450.0)
	var eyes: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var s := node as Soldier
		if s and s.faction == &"hostile" and s.vitals.is_up() and not s.is_queued_for_deletion():
			eyes.append(s.global_position + Vector3.UP * 1.6)
	var pic: SidePicture = ops.hostile.picture() if ops.hostile and is_instance_valid(ops.hostile) else null
	var rays := 0
	for p: Dictionary in mine().get("pieces", []):
		if bool(p.get("seen", false)):
			continue
		var at := Vector3(float(p.pos[0]), float(p.pos[1]) + 0.6, float(p.pos[2]))
		var by := ""
		if pic and not pic.entries_near(at, 25.0).is_empty():
			by = "its picture"
		for eye: Vector3 in eyes:
			if by != "" or rays >= int(num("town", "rays_max", 24)):
				break
			if eye.distance_to(at) > reach:
				continue
			rays += 1
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, at, 1))
			var body: Variant = _bodies.get(String(p.id))
			if hit.is_empty() or hit.get("collider") == body or (hit.position as Vector3).distance_to(at) < 1.6:
				by = "an enemy at %s" % grid_ref(eye)
		if by != "":
			p["seen"] = true
			SessionLog.note("operation %s: the enemy saw the %s at %s (%s)" % [ops.cid, String(p.kind), grid_ref(at), by])


# --- Placing defences ---------------------------------------------------------------------------------

## Why a `kind` piece can't go at `at` (zone metres) now ("" if it can): the prep phase (or before it),
## within radius_m of the centre, the budget, clear of the others.
func placement_problem(kind: String, at: Vector3) -> String:
	if not catalogue().has(kind):
		return "No such defence"
	var v := ops.view if ops else {}
	var st := String(v.get("state", run().get("state", "")))
	if st in [Operations.DONE, Operations.STALLED] or int(v.get("phase", phase())) > 0:
		return "The time to prepare is over"
	if pieces().size() >= int(num("town", "budget", 6)):
		return "The defence budget is spent (%d pieces)" % int(num("town", "budget", 6))
	var c := centre()
	if Vector2(at.x - c.x, at.z - c.z).length() > num("town", "radius_m", 250.0):
		return "Too far from the town centre (%d m at most)" % roundi(num("town", "radius_m", 250.0))
	for p: Dictionary in pieces():
		if Vector2(float(p.pos[0]) - at.x, float(p.pos[2]) - at.z).length() < num("town", "gap_m", 1.5):
			return "Another defence stands there"
	return ""


## Any peer (DefencePlacer's field mode): asks the host for a `kind` piece at `at`, turned `yaw`.
func request_place(kind: String, at: Vector3, yaw: float) -> void:
	if _host():
		server_place(kind, at, yaw, MapNodes.local_player(self))
	else:
		_rpc_place.rpc_id(1, kind, at, yaw)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_place(kind: String, at: Vector3, yaw: float) -> void:
	if not multiplayer.is_server():
		return
	var who: Soldier = null
	var lvl := level()
	var players: Node = lvl.get(&"players") if lvl else null
	if players:
		who = players.get_node_or_null(NodePath(str(multiplayer.get_remote_sender_id()))) as Soldier
	var why := server_place(kind, at, yaw, who)
	if why != "" and who:
		Contracts._notify_all("%s: %s" % [who.display_name(), why])


## Host: a `kind` piece at `at`, turned `yaw`, by `by`. "" or why not.
func server_place(kind: String, at: Vector3, yaw: float, by: Soldier = null) -> String:
	at = ground(at)
	var why := placement_problem(kind, at)
	if why != "":
		return why
	var m := mine()
	var id := "p%d" % int(m.get("next", 1))
	m["next"] = int(m.get("next", 1)) + 1
	(m.pieces as Array).append({"id": id, "kind": kind, "pos": [snappedf(at.x, 0.05), snappedf(at.y, 0.05), snappedf(at.z, 0.05)], "yaw": snappedf(yaw, 0.01),
		"by": by.display_name() if by else "", "seen": false})
	SessionLog.note("operation %s: %s placed a %s at %s (%d of %d)" % [ops.cid, by.display_name() if by else "the host", kind, grid_ref(at),
		(m.pieces as Array).size(), int(num("town", "budget", 6))])
	_refresh()
	_on_state()
	return ""


## The local player opens the placing tool for a `kind` piece (the command menu, "local:op_defence:<kind>").
static func local_command(player: Soldier, what: String) -> void:
	var kind := what.trim_prefix("op_defence:")
	var town := OpTown.of(player)
	if town == null:
		if player._hud:
			player._hud.flash("Field defences are for holding a town")
		return
	var why := town.placement_problem(kind, town.centre())
	if why != "" and not why.begins_with("Too far") and not why.begins_with("Another"):
		if player._hud:
			player._hud.flash(why)
		return
	DefencePlacer.start_field(player, kind)


# --- Every peer: the pieces -----------------------------------------------------------------------------

func strip_line() -> String:
	return "Defences %d/%d (%d seen)  Waves %d/%d" % [(state.get("pieces", []) as Array).size(), int(state.get("budget", 6)), int(state.get("seen", 0)),
		int(state.get("waves", 0)), int(state.get("waves_max", 0))]


func _refresh() -> void:
	var list: Array = []
	for p: Dictionary in mine().get("pieces", []):
		list.append({"id": String(p.id), "kind": String(p.kind), "pos": (p.pos as Array).duplicate(), "yaw": float(p.yaw)})
	var waves: Dictionary = mine().get("waves", {})
	var s := {"pieces": list, "budget": int(num("town", "budget", 6)), "waves": waves.size(), "waves_max": (cfg("town").get("counter", []) as Array).size(),
		"seen": seen_points().size()}
	if s != state:
		state = s
		publish()


func _on_state() -> void:
	var want := {}
	for p: Dictionary in state.get("pieces", []):
		want[String(p.id)] = p
	for id: String in _bodies.keys():
		if not want.has(id):
			if is_instance_valid(_bodies[id]):
				(_bodies[id] as Node).queue_free()
			_bodies.erase(id)
	for id: String in want:
		if not _bodies.has(id) or not is_instance_valid(_bodies[id]):
			_bodies[id] = _build(want[id])


## A piece: a solid box of its size with collision (cover that stops what it's drawn as), coloured.
func _build(p: Dictionary) -> StaticBody3D:
	var spec: Dictionary = catalogue().get(String(p.kind), {})
	var size_a: Array = spec.get("size", [3.0, 1.1, 0.6])
	var size := Vector3(float(size_a[0]), float(size_a[1]), float(size_a[2]))
	var body := StaticBody3D.new()
	body.name = "FieldDefence_%s" % String(p.id)
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group(NODE_GROUP)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(String(spec.get("colour", "a08c64")))
	bm.material = mat
	mesh.mesh = bm
	mesh.position = shape.position
	body.add_child(mesh)
	var lvl := level() as Node3D
	(lvl if lvl else self).add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, float(p.yaw)), Vector3(float(p.pos[0]), float(p.pos[1]), float(p.pos[2])))
	return body


func _exit_tree() -> void:
	for id: String in _bodies:
		if is_instance_valid(_bodies[id]):
			(_bodies[id] as Node).queue_free()
	_bodies.clear()
