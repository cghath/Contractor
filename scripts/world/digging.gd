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
## Host authoritative: the host keeps the berms (records) and sends each to every peer (late
## joiners get them all); every peer builds the same node from a record. Not saved with the zone
## yet (a berm lasts the deployment). Numbers Proposed. One node per level ("Digging").

const NODE_NAME := "Digging"
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
const BLAST_REACH_M := 1.5

## Every peer: id -> {"id", "pos": Vector3, "yaw", "colour": Color, "hits"}.
var records := {}
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
	if multiplayer.has_multiplayer_peer():
		multiplayer.peer_connected.connect(_on_peer_joined)


## Why `s` can't dig here and now ("" when they can).
static func problem(s: Soldier) -> String:
	if s.inventory.count_of(ITEM) <= 0 and not s.inventory.slots.values().has(ITEM):
		return "You have no e-tool"
	if not s.vitals.is_up() or Vehicle.ride_of(s) != null or s.carry_mode != &"":
		return "Not now"
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
			server_add(s.global_position, atan2(-fwd.x, -fwd.z))
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


func _on_peer_joined(peer: int) -> void:
	if multiplayer.is_server():
		for id: int in records:
			_client_add.rpc_id(peer, records[id])


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
