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
## In a zone (a ZoneTerrain under him) the berm is the ground itself (GroundCuts mound: it
## follows the slope and takes the ground's look; Captain, 2026-10-19: "they need to flow with the
## terrain better"), and a foxhole cuts the pit where he kneels (dig phase 3: GroundCuts.pit_op),
## a stage deeper each dig (GroundCuts.PIT_STAGES_M); stepping aside and digging again runs it
## into a trench, the parapets merging. Elsewhere (the test compound) a dig is a block berm.
##
## AI digs in too (dig phase 4): a friendly soldier holding a spot (SquadAI HOLD, out of
## contact) builds cover in front of it, to kneeling height; AI carry the e-tool on the pack (not
## an item: Proposed, so every kit needn't change), players need the item. The enemy's outposts
## and checkpoints have their parapets up before the squad arrives (server_prepare:
## PREPARED_PER_SITE round each, facing out).
##
## Two digs (Captain, 2026-10-19: "ideally they dont bore down when they build cover in front of
## them"): COVER (the menu's "Build cover in front") only raises the parapet in front, a stage
## higher each time (COVER_STAGES_M: prone, then kneeling), the ground under him untouched; HOLE
## ("Dig a foxhole") cuts the pit under him, with its spoil in front. AI and the enemy's outposts
## build cover. In the test compound (no terrain) either is a block berm.
##
## Blasts cut the ground too (dig phase 2, "explosion craters"): a blast on or near the ground
## of a zone (one with a ZoneTerrain) leaves a crater (GroundCuts.crater_op) you can take cover
## in: a scorched bowl with a lip of thrown-up earth, real depth and collision.
##
## Host authoritative: the host keeps the berms (records) and the cuts (cut_ops) and sends each
## to every peer; a late joiner asks for them all once its level is up (_ask_all). Every peer
## builds the same from them; both go in the zone save (to_save, GameState.ground). Numbers
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
## A foxhole's spoil lip (GroundCuts mound): SPOIL_BASE_M plus SPOIL_PER_M a metre dug (about
## 0.3 m: standing in the hole he fires over it, chest-deep in cover). Proposed.
const SPOIL_BASE_M := 0.25
const SPOIL_PER_M := 0.1
const COVER := &"cover"
const HOLE := &"hole"
## The parapet "Build cover in front" raises, one stage a dig (Captain, 2026-10-19: "they dont
## need to dig a high wall and a deep hole, they still need to be able to effectively fight", "it
## just needs to provide great cover and a good firing position"): low enough to fire over lying
## down, then kneeling, never a wall. Proposed.
const COVER_STAGES_M: Array[float] = [0.4, 0.75]
## How far round where the crest would be cover_height looks (along his facing, to the sides).
const CREST_REACH_M := Vector2(0.4, 0.3)
## Enemy sites dug in at the start (server_prepare): how many positions round each, how far
## outside its footprint, and how high their parapets. Proposed.
const PREPARED_TYPES: Array[String] = ["outpost", "checkpoint"]
const PREPARED_PER_SITE := 3
const PREPARED_OUT_M := 4.0
const PREPARED_COVER_M := 0.75
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
static func problem(s: Soldier, kind := COVER) -> String:
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
		if kind == HOLE:
			var dug := terrain.cuts.dug_depth(p.x, p.z) if terrain.cuts else 0.0
			if GroundCuts.next_stage(dug) == 0.0:
				return "This hole is as deep as it goes"
		elif next_cover(cover_height(terrain, s)) == 0.0:
			return "This cover is as high as it goes"
	elif kind == HOLE:
		return "Foxholes need open ground"
	return ""


## How high the parapet in front of `s` stands now (a zone's ground over the ground as it was,
## at the crest of where his cover would go).
static func cover_height(terrain: ZoneTerrain, s: Soldier) -> float:
	return cover_at(terrain, s.global_position, facing(s))


## The flat way `s` faces.
static func facing(s: Soldier) -> Vector3:
	var fwd := -s.global_basis.z
	fwd.y = 0.0
	return fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD


## How high the parapet stands in front of `pos`, facing `fwd` (flat, normalized).
static func cover_at(terrain: ZoneTerrain, pos: Vector3, fwd: Vector3) -> float:
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var best := -INF
	# The crest's highest round where it would be (a man shuffles on his spot, and one point between
	# the fine grid's vertices reads low): CREST_REACH_M along his facing and to the sides.
	for i in range(-2, 3):
		for j in range(-2, 3):
			var q := pos + fwd * (GroundCuts.MOUND_R_M + i * CREST_REACH_M.x * 0.5) + side * (j * CREST_REACH_M.y * 0.5)
			best = maxf(best, terrain.height_at(q.x, q.z) - terrain.plane_height(q.x, q.z))
	return best


## The next COVER_STAGES_M past `height`, or 0 when it's as high as it goes.
static func next_cover(height: float) -> float:
	for h in COVER_STAGES_M:
		if h > height + 0.15:
			return h
	return 0.0


## Host: `s` starts digging where they stand, facing the way they look. Returns "" or why not.
## `at` (AI holding a spot): dig there, not where he stands; `fwd`: facing that way, not his own.
func server_start(s: Soldier, kind := COVER, at := Vector3.INF, fwd := Vector3.ZERO) -> String:
	if not multiplayer.is_server():
		return ""
	var why := problem(s, kind)
	if why != "":
		return why
	if _digs.has(s.get_instance_id()):
		return "Already digging"
	var serial := s.model.server_play(CharacterModel.LOOT, DIG_S, Vector3(0, 0.1, -0.6), &"", &"", true)
	var way := fwd if fwd.length() > 0.01 else facing(s)  # fixed now: he looks about while he digs
	_digs[s.get_instance_id()] = {"soldier": s, "from": s.global_position, "started": Soldier._now(), "serial": serial, "kind": kind,
		"at": at if at.is_finite() else s.global_position, "fwd": way}
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


## The fields of each kind of saved cut (GroundCuts.crater_op, pit_op, mound_op), checked by
## GameState.read_save (F-176).
const CUT_FIELDS := {"crater": ["x", "z", "r", "depth"], "pit": ["x", "z", "yaw", "depth"], "mound": ["x", "z", "yaw", "h"]}


## Whether `op` is a saved cut GroundCuts.apply can replay: a known kind, every field a finite number.
static func cut_ok(op: Variant) -> bool:
	if typeof(op) != TYPE_DICTIONARY or not CUT_FIELDS.has(String(op.get("kind", ""))):
		return false
	return (CUT_FIELDS[String(op.kind)] as Array).all(func(k: String) -> bool: return GameState.is_number(op.get(k)))


## Whether `b` is a saved berm (to_save): an id, a position, a yaw, a colour and its hits.
static func berm_ok(b: Variant) -> bool:
	return typeof(b) == TYPE_DICTIONARY and GameState.is_number(b.get("id")) and GameState._finite_pos(b.get("pos")) 		and GameState.is_number(b.get("yaw")) and typeof(b.get("colour")) == TYPE_STRING and Color.html_is_valid(String(b.colour)) 		and GameState.is_number(b.get("hits"))


## Host: the ground as saved (to_save) back, to every peer.
func _server_restore(saved: Dictionary) -> void:
	for b: Dictionary in saved.get("berms", []):
		var rec := {"id": int(b.id), "pos": Vector3(b.pos[0], b.pos[1], b.pos[2]), "yaw": float(b.yaw),
			"colour": Color(String(b.colour)), "hits": int(b.hits)}
		_next_id = maxi(_next_id, int(b.id) + 1)
		_client_add.rpc(rec)
	for op: Dictionary in saved.get("cuts", []):
		_client_cut.rpc(op)


## How high the spoil parapet in front of a hole `depth` deep stands (a zone's GroundCuts mound).
static func spoil_height(depth: float) -> float:
	return SPOIL_BASE_M + depth * SPOIL_PER_M


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
			_client_cut.rpc(GroundCuts.mound_op(p, yaw, PREPARED_COVER_M))


func _physics_process(_delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or _digs.is_empty():
		return
	for key: int in _digs.keys():
		var d: Dictionary = _digs[key]
		var s: Soldier = d.soldier if is_instance_valid(d.soldier) else null
		if not is_instance_valid(s) or not s.vitals.is_up() or s.global_position.distance_to(d.from) > DIG_MOVE_M:
			if is_instance_valid(s):
				s.model.server_stop(int(d.serial))
			_digs.erase(key)
			continue
		if Soldier._now() - float(d.started) >= DIG_S:
			_digs.erase(key)
			var fwd: Vector3 = d.fwd
			var yaw := atan2(-fwd.x, -fwd.z)
			var terrain := _terrain()
			if terrain == null:
				server_add(s.global_position, yaw)
			else:
				var p: Vector3 = d.at
				if StringName(d.get("kind", COVER)) == HOLE:
					var dug := terrain.cuts.dug_depth(p.x, p.z) if terrain.cuts else 0.0
					var depth := GroundCuts.next_stage(dug)
					if depth > 0.0:
						_client_cut.rpc(GroundCuts.pit_op(p, yaw, depth))
						_client_cut.rpc(GroundCuts.mound_op(p, yaw, spoil_height(depth)))  # the spoil, in front: higher as the hole goes down
					print("[dig] %s has dug a foxhole (%.2f m down)" % [s.display_name(), depth])
				else:
					var h := next_cover(cover_at(terrain, p, fwd))
					if h > 0.0:
						_client_cut.rpc(GroundCuts.mound_op(p, yaw, h))
					print("[dig] %s has built cover (%.2f m high)" % [s.display_name(), h])
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
## Its crater's radius is `crater_m` (the blast's radius if negative; none at 0).
func server_blast(pos: Vector3, radius_m: float, crater_m := -1.0) -> void:
	if not multiplayer.is_server():
		return
	for id: int in records.keys():
		var rec: Dictionary = records[id]
		if (rec.pos as Vector3).distance_to(pos) <= radius_m + BLAST_REACH_M:
			rec.hits = int(rec.hits) + 1
			if int(rec.hits) >= HITS:
				_client_remove.rpc(id)
	var terrain := _terrain()
	var crater := radius_m if crater_m < 0.0 else crater_m
	if terrain and crater > 0.0 and pos.y - terrain.height_at(pos.x, pos.z) <= maxf(CRATER_FROM_M, crater):
		_client_cut.rpc(GroundCuts.crater_op(pos, crater))


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
