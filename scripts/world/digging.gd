class_name Digging
extends Node
## Digging in (Captain, 2026-10-16: "an e tool that digs dirt fighting positions, they take the
## color of the terrain you dig them up from"; 2026-10-19: e-tool berms first, about 20 s each).
## Anyone carrying an e-tool (data/items.json "etool") can dig from the self-interaction menu
## ("Dig a fighting position"): kneeling DIG_S seconds where they stand (moving off DIG_MOVE_M or
## going down stops it), then a berm rises in front of them: a crescent parapet of dirt in the
## local ground's colour, built of BLOCK_M blocks like the voxel walls and the ground near the
## camera. It stops rounds (its collision is world: Ballistics stops there, as at a wall) and
## blasts wear it down (server_blast, from the level's own: HITS of them flatten it).
##
## In a zone (a ZoneTerrain under him) a dig also cuts a hole where he kneels (dig phase 3,
## "real foxholes and trenches": GroundCuts.pit_op): each dig takes it a stage deeper (a prone
## scrape, then kneeling, then standing: GroundCuts.PIT_STAGES_M), digging on from inside one
## makes it a trench, and only the first dig at a spot throws up the berm in front (the spoil).
## Elsewhere (the test compound) a dig is a berm alone. (A trench runs sideways, along the
## berms: step aside a pit's width and dig again, and the new berm joins the last; a dig within
## SPOIL_APART_M of an earlier one deepens it, no new berm.)
##
## AI digs in too (dig phase 4): a friendly soldier holding a spot (SquadAI HOLD, out of
## contact) digs down to the kneeling stage there; AI carry the e-tool on the pack (not an item:
## Proposed, so every kit needn't change), players need the item. The enemy's outposts and
## checkpoints are dug in before the squad arrives (server_prepare: PREPARED_PER_SITE pits with
## their berms round each, facing out).
##
## Blasts cut the ground too (dig phase 2, "explosion craters"): a blast on or near the ground
## of a zone (one with a ZoneTerrain) leaves a crater (GroundCuts.crater_op) you can take cover
## in: a scorched bowl with a lip of thrown-up earth, real depth and collision.
##
## Host authoritative: the host keeps the berms (records) and the cuts (cut_ops) and sends each
## to every peer; a late joiner asks for them all once its level is up (_ask_all). Every peer
## builds the same from them. Not saved with the zone yet (they last the deployment). Numbers
## Proposed. One node per level ("Digging").

const NODE_NAME := "Digging"
const GROUP := &"digging"  # GameState.save_zone finds it here
const ITEM := &"etool"
const DIG_S := 20.0
const DIG_MOVE_M := 0.6
const BLOCK_M := 0.25
## The crescent: RADIUS_M in front of the digger, over ARC_DEG, LAYERS blocks high, DEPTH blocks thick.
const RADIUS_M := 1.4
const ARC_DEG := 110.0
const LAYERS := 3
const DEPTH := 2
const HITS := 3
const SPOIL_APART_M := 1.0
## Enemy sites dug in at the start (server_prepare): how many positions round each, how far
## outside its footprint, and how deep. Proposed.
const PREPARED_TYPES: Array[String] = ["outpost", "checkpoint"]
const PREPARED_PER_SITE := 3
const PREPARED_OUT_M := 4.0
const PREPARED_DEPTH_M := 0.9
const BLAST_REACH_M := 1.5
## A blast cuts a crater when it goes off at most this high over the ground (or its radius, if more).
const CRATER_FROM_M := 0.8

## Every peer: id -> {"id", "pos": Vector3, "yaw", "colour": Color, "hits"}.
var records := {}
## Every peer: the cuts in the ground so far (GroundCuts ops), in order.
var cut_ops: Array = []
## Host: soldier instance id -> {"soldier", "from": Vector3, "started", "serial"}.
var _digs := {}
var _next_id := 1
var _nodes := {}


static func of(from: Node) -> Digging:
	var level := CompoundLevel.current(from)
	if level == null:
		return null
	var d := level.get_node_or_null(NODE_NAME) as Digging
	if d == null:
		d = Digging.new()
		d.name = NODE_NAME
		level.add_child(d)
	return d


func _ready() -> void:
	add_to_group(GROUP)
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		(func() -> void: _ask_all.rpc_id(1)).call_deferred()


## Why `s` can't dig here and now ("" when they can).
static func problem(s: Soldier) -> String:
	if not s.is_ai() and s.inventory.count_of(ITEM) <= 0 and not s.inventory.slots.values().has(ITEM):
		return "You have no e-tool"
	if not s.vitals.is_up() or Vehicle.ride_of(s) != null or s.carry_mode != &"":
		return "Not now"
	var level := CompoundLevel.current(s)
	var t: Variant = level.get(&"terrain") if level else null
	if t is ZoneTerrain:
		var terrain := t as ZoneTerrain
		var p := s.global_position
		if p.y - terrain.height_at(p.x, p.z) > 0.4:
			return "Dig on open ground"
		var dug := terrain.cuts.dug_depth(p.x, p.z) if terrain.cuts else 0.0
		if GroundCuts.next_stage(dug) == 0.0:
			return "This hole is as deep as it goes"
	return ""


## Host: `s` starts digging where they stand, facing the way they look. Returns "" or why not.
func server_start(s: Soldier) -> String:
	if not multiplayer.is_server():
		return ""
	var why := problem(s)
	if why != "":
		return why
	if _digs.has(s.get_instance_id()):
		return "Already digging"
	var serial := s.model.server_play(CharacterModel.LOOT, DIG_S, Vector3(0, 0.1, -0.6), &"", &"", true)
	_digs[s.get_instance_id()] = {"soldier": s, "from": s.global_position, "started": Soldier._now(), "serial": serial}
	print("[dig] %s digs in" % s.display_name())
	return ""


## The zone save's record of the ground (GameState.ground): every cut, every berm standing.
func to_save() -> Dictionary:
	var berms: Array = []
	for id: int in records:
		var r: Dictionary = records[id]
		var p: Vector3 = r.pos
		berms.append({"id": id, "pos": [p.x, p.y, p.z], "yaw": r.yaw, "colour": (r.colour as Color).to_html(false), "hits": r.hits})
	return {"cuts": cut_ops.duplicate(true), "berms": berms}


## Host: the ground as saved (to_save) back, to every peer.
func _server_restore(saved: Dictionary) -> void:
	for b: Dictionary in saved.get("berms", []):
		var rec := {"id": int(b.id), "pos": Vector3(b.pos[0], b.pos[1], b.pos[2]), "yaw": float(b.yaw),
			"colour": Color(String(b.colour)), "hits": int(b.hits)}
		_next_id = maxi(_next_id, int(b.id) + 1)
		_client_add.rpc(rec)
	for op: Dictionary in saved.get("cuts", []):
		_client_cut.rpc(op)


## Whether `s` is digging now (host).
func digging(s: Soldier) -> bool:
	return _digs.has(s.get_instance_id())


## Host: `s` stops digging (nothing dug).
func server_stop(s: Soldier) -> void:
	var d: Dictionary = _digs.get(s.get_instance_id(), {})
	if d.is_empty():
		return
	s.model.server_stop(int(d.serial))
	_digs.erase(s.get_instance_id())


## Host, a zone's start: a zone with a save gets its cuts and berms back from it (to_save);
## otherwise the enemy's outposts and checkpoints dug in (PREPARED_PER_SITE pits and
## their berms round each, facing out from it, spread round it from a seed of its id).
func server_prepare(level: ZoneLevel) -> void:
	if not multiplayer.is_server() or level.terrain == null:
		return
	if GameState.ground.has("cuts"):
		_server_restore(GameState.ground)  # a saved zone: what was dug and blasted, back
		return
	for m: ZoneModule in level.modules():
		if not PREPARED_TYPES.any(func(t: String) -> bool: return String(m.type).begins_with(t)):
			continue
		var rect := m.footprint()
		var reach := maxf(rect.size.x, rect.size.y) * 0.5 + PREPARED_OUT_M
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(m.module_id)
		var first := rng.randf() * TAU
		for k in PREPARED_PER_SITE:
			var a := first + TAU * k / PREPARED_PER_SITE + rng.randf_range(-0.3, 0.3)
			var out := Vector3(sin(a), 0.0, cos(a))
			var p := m.global_position + out * reach
			if level.module_at(p) != null or p.distance_to(m.global_position) < 1.0:
				continue
			p.y = level.terrain.height_at(p.x, p.z)
			var yaw := atan2(-out.x, -out.z)
			_client_cut.rpc(GroundCuts.pit_op(p, yaw, PREPARED_DEPTH_M))
			server_add(Vector3(p.x, level.terrain.plane_height(p.x, p.z), p.z), yaw)


func _physics_process(_delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or _digs.is_empty():
		return
	for key: int in _digs.keys():
		var d: Dictionary = _digs[key]
		var s := d.soldier as Soldier
		if not is_instance_valid(s) or not s.vitals.is_up() or s.global_position.distance_to(d.from) > DIG_MOVE_M:
			if is_instance_valid(s):
				s.model.server_stop(int(d.serial))
			_digs.erase(key)
			continue
		if Soldier._now() - float(d.started) >= DIG_S:
			_digs.erase(key)
			var fwd := -s.global_basis.z
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
			var yaw := atan2(-fwd.x, -fwd.z)
			var terrain := _terrain()
			if terrain == null:
				server_add(s.global_position, yaw)
			else:
				var p := s.global_position
				var dug := terrain.cuts.dug_depth(p.x, p.z) if terrain.cuts else 0.0
				var depth := GroundCuts.next_stage(dug)
				if depth > 0.0:
					_client_cut.rpc(GroundCuts.pit_op(p, yaw, depth))
				# The spoil: a berm in front, unless one is near there already (a hole being deepened).
				if not records.values().any(func(r: Dictionary) -> bool: return (r.pos as Vector3).distance_to(p) < SPOIL_APART_M):
					server_add(Vector3(p.x, terrain.plane_height(p.x, p.z), p.z), yaw)
				print("[dig] %s has dug in (%.2f m down)" % [s.display_name(), depth])
				continue
			print("[dig] %s has dug a fighting position" % s.display_name())


## Host: a berm at `pos` (the digger's feet), facing `yaw`. Returns its id.
func server_add(pos: Vector3, yaw: float) -> int:
	var level := CompoundLevel.current(self)
	var colour := Color("6e5a48")
	var terrain: Variant = level.get(&"terrain") if level else null
	if terrain is ZoneTerrain:
		colour = (terrain as ZoneTerrain).c_earth
	var id := _next_id
	_next_id += 1
	var rec := {"id": id, "pos": pos, "yaw": yaw, "colour": colour, "hits": 0}
	_client_add.rpc(rec)
	return id


## Host: a blast at `pos` (radius `radius_m`) wears down the berms it reaches; HITS flatten one.
func server_blast(pos: Vector3, radius_m: float) -> void:
	if not multiplayer.is_server():
		return
	for id: int in records.keys():
		var rec: Dictionary = records[id]
		if (rec.pos as Vector3).distance_to(pos) <= radius_m + BLAST_REACH_M:
			rec.hits = int(rec.hits) + 1
			if int(rec.hits) >= HITS:
				_client_remove.rpc(id)
	var terrain := _terrain()
	if terrain and pos.y - terrain.height_at(pos.x, pos.z) <= maxf(CRATER_FROM_M, radius_m):
		_client_cut.rpc(GroundCuts.crater_op(pos, radius_m))


func _terrain() -> ZoneTerrain:
	var level := CompoundLevel.current(self)
	var t: Variant = level.get(&"terrain") if level else null
	return t as ZoneTerrain if t is ZoneTerrain else null


## A late joiner, its level up: sends it every berm and every cut so far.
@rpc("any_peer", "call_remote", "reliable")
func _ask_all() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	print("[dig] peer %d joined: %d berms, %d cuts" % [peer, records.size(), cut_ops.size()])
	print("[dig] peer %d joined: %d berms, %d cuts" % [peer, records.size(), cut_ops.size()])
	for id: int in records:
		_client_add.rpc_id(peer, records[id])
	if not cut_ops.is_empty():
		_client_cuts.rpc_id(peer, cut_ops)


@rpc("authority", "call_local", "reliable")
func _client_cut(op: Dictionary) -> void:
	_apply_cut(op)


@rpc("authority", "call_remote", "reliable")
func _client_cuts(ops: Array) -> void:
	for op: Dictionary in ops:
		_apply_cut(op)


func _apply_cut(op: Dictionary) -> void:
	var terrain := _terrain()
	if terrain and GroundCuts.of(terrain).apply(op):
		cut_ops.append(op)


@rpc("authority", "call_local", "reliable")
func _client_add(rec: Dictionary) -> void:
	records[int(rec.id)] = rec
	var node := make_berm(rec)
	add_child(node)
	_nodes[int(rec.id)] = node


@rpc("authority", "call_local", "reliable")
func _client_remove(id: int) -> void:
	records.erase(id)
	var node: Node = _nodes.get(id)
	if node and is_instance_valid(node):
		node.queue_free()
	_nodes.erase(id)


## A berm from its record: a static body (world collision) with its blocks drawn as one
## MultiMesh (one draw call), each block a slightly different shade of the dug earth.
static func make_berm(rec: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Berm_%d" % int(rec.id)
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = rec.pos
	body.rotation.y = float(rec.yaw)
	var base: Color = rec.colour
	var steps := int(ceil(deg_to_rad(ARC_DEG) * RADIUS_M / BLOCK_M))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rec.id) * 7919
	var blocks: Array = []  # [Transform3D, Color]
	for k in steps + 1:
		var a := deg_to_rad(-ARC_DEG * 0.5) + deg_to_rad(ARC_DEG) * k / maxf(steps, 1)
		var edge := absf(float(k) / maxf(steps, 1) - 0.5) * 2.0  # 0 in the middle, 1 at the ends
		var layers := LAYERS if edge < 0.7 else LAYERS - 1
		for d in DEPTH:
			var r := RADIUS_M + d * BLOCK_M
			var centre := Vector3(sin(a) * r, 0.0, -cos(a) * r)
			for l in layers - d:
				var at := centre + Vector3(0, l * BLOCK_M + BLOCK_M * 0.5 - 0.05, 0)
				var c := base.darkened(rng.randf_range(0.0, 0.16)).lightened(rng.randf_range(0.0, 0.05))
				blocks.append([Transform3D(Basis(Vector3.UP, -a), at), c])
				var shape := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3.ONE * BLOCK_M
				shape.shape = box
				shape.position = at
				shape.rotation.y = -a
				body.add_child(shape)
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * BLOCK_M
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	cube.material = mat
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = cube
	multi.instance_count = blocks.size()
	for n in blocks.size():
		multi.set_instance_transform(n, blocks[n][0])
		multi.set_instance_color(n, blocks[n][1])
	var draw := MultiMeshInstance3D.new()
	draw.multimesh = multi
	body.add_child(draw)
	return body
