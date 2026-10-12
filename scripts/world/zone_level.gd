class_name ZoneLevel
extends CompoundLevel
## A contract zone (2 to 4 km²): a seeded heightmap terrain (ZoneTerrain) with hand-built
## voxel modules placed on it (ZoneModule, types in ZoneModules), all made from a zone
## definition (ZoneDef) the same way on every peer. The host sends the definition to joining
## clients (LevelSwitch) and every module's edit log after that; each peer streams modules in
## around its own player (the host: around every player and every AI soldier in a fight) and
## out again past STREAM_OUT_M.
##
## It is a CompoundLevel, so everything that calls CompoundLevel.current(node) works here:
## players, AI squads, items, bodies, impacts, throws, smoke, saves. What differs is the
## world: spawn points at the insertion point, ground_point() on the terrain, map_area()
## over the whole zone, voxel_worlds() and server_blast() over the loaded modules, and a
## ZoneNav baking navigation around soldiers as they move.
##
## Saves: one zone save (GameState, under its zone_id) holds every module's voxel edits in
## GameState.voxel_edits, each tagged with its module ("w"), with the items, loot taken and
## bodies as in the compound. Hostile garrisons spawn the first time their module streams in
## on the host; one killed before a save stays dead (its body is in the save).

## Proposed: a module streams in when anyone it streams for is this close to its footprint
## (m), and out once all of them are further than STREAM_OUT_M. Checked every STREAM_CHECK_S;
## at most one module streams in per check (each is a hitch of a few ms).
const STREAM_IN_M := 260.0
const STREAM_OUT_M := 340.0
const STREAM_CHECK_S := 0.25
## Haze: about 50% at 1 km, 25% at 2 km.
const FOG_DENSITY := 0.0007
const FOG_COLOUR := Color(0.70, 0.74, 0.78)
## Reinforcements (Reinforcements.edge_point): they come in this far inside the zone's edge
## (there is no ground beyond it), at the spot of REINFORCE_TRIES round the edge nearest the
## players but at least REINFORCE_MIN_M from every one of them (the furthest if none is).
## Proposed.
const REINFORCE_INSET_M := 40.0
const REINFORCE_MIN_M := 350.0
const REINFORCE_TRIES := 32
## Players insert this far apart around the insertion point.
const SPAWN_SPREAD_M := 2.0
## Hostile garrisons: kit and stats (the compound's hostiles').
const GARRISON_STATS := {"combat": 0.45, "discipline": 0.5, "mode": "aware"}
## A contract's target module holds its true enemy count (Captain, 2026-10-11; garrison_size).
## Posts past the module's own (ZoneModules.GARRISON) go beside them: the first clear spot
## this far out round a post, a man's width (EXTRA_POST_CLEAR_M) from walls and each other.
const EXTRA_POST_RINGS_M: Array[float] = [1.3, 2.4, 3.5]
const EXTRA_POST_CLEAR_M := 0.4

## The zone definition (ZoneDef), set before the node enters the tree (configure()).
var def: Dictionary = {}
var terrain: ZoneTerrain
## Host only: the navigation (null on clients).
var nav: ZoneNav
## How long generating the zone took on this peer (ms): terrain heights, collision and,
## with a display, the coarse meshes.
var generate_ms := 0.0

var _modules: Array[ZoneModule] = []
var _by_id := {}  # module id -> ZoneModule
## Every module's voxel edit log (module id -> Array of edits), on every peer. On the host its
## entries are the same dictionaries as in GameState.voxel_edits.
var _logs := {}
var _garrisoned := {}  # host: module id -> how many of its garrison posts have spawned
var _next_stream := 0.0


## Sets the zone definition (ZoneDef). Call before adding the node to the tree.
func configure(p_def: Dictionary) -> void:
	def = ZoneDef.normalize(p_def)


func _ready() -> void:
	if def.is_empty():
		def = ZoneDef.get_def("test")
	super._ready()
	squad_for(&"hostile").patrol = []  # garrisons hold their ground
	Contracts.contract_live.connect(_on_contract_live)
	players.child_entered_tree.connect(_on_player_entered)


# --- Level API --------------------------------------------------------------------------------

func level_info() -> Dictionary:
	return {"level": "zone", "def": def}


## The whole zone (x along x, y along z, metres).
func map_area() -> Rect2:
	var half := terrain.size_m * 0.5
	return Rect2(-half, -half, terrain.size_m, terrain.size_m)


## Around the default insertion point: eight spots, two rows of four SPAWN_SPREAD_M apart.
func spawn_point(index: int) -> Vector3:
	var k := posmod(index, 8)
	return ground_point(insertion_points()[0] + Vector3((k % 4 - 1.5) * SPAWN_SPREAD_M, 0, (k / 4) * SPAWN_SPREAD_M))


## Where player `id` starts: worked out the same on the host and on that player's own peer
## (_on_player_entered), since the player, not the host, drives its position.
func player_spawn(id: int) -> Vector3:
	return spawn_point(posmod(id - 1, 8))


## `pos` on the terrain (0.1 m above it).
func ground_point(pos: Vector3) -> Vector3:
	return Vector3(pos.x, terrain.height_at(pos.x, pos.z) + 0.1, pos.z)


## The ground's height at (x, z).
func ground_height(x: float, z: float) -> float:
	return terrain.height_at(x, z)


func voxel_worlds() -> Array[VoxelWorld]:
	var out: Array[VoxelWorld] = []
	for module in _modules:
		if module.voxel_world:
			out.append(module.voxel_world)
	return out


## Host only. A blast against the voxels of every loaded module it reaches.
func server_blast(pos: Vector3, radius_m: float) -> void:
	for module in _modules:
		if module.voxel_world and module.distance_to(pos) <= radius_m + 1.0:
			module.voxel_world.server_blast(pos, radius_m)


func modules() -> Array[ZoneModule]:
	return _modules


func get_module(id: String) -> ZoneModule:
	return _by_id.get(id)


## The module whose footprint holds `pos`, or null.
func module_at(pos: Vector3) -> ZoneModule:
	for m in _modules:
		if m.distance_to(pos) <= 0.0:
			return m
	return null


## Insertion points (world space, on the ground), the default first.
func insertion_points() -> Array[Vector3]:
	return _points(def.get("insertion", []))


## Extraction candidates (world space, on the ground).
func extraction_points() -> Array[Vector3]:
	return _points(def.get("extraction", []))


func _points(list: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p: Array in list:
		out.append(Vector3(float(p[0]), terrain.height_at(float(p[0]), float(p[1])), float(p[1])))
	return out


## Every module's edit log (module id -> Array). Read only.
func edit_logs() -> Dictionary:
	return _logs


## The modules streamed in on this peer now.
func streamed_modules() -> Array[ZoneModule]:
	return _modules.filter(func(m: ZoneModule) -> bool: return m.is_streamed())


# --- Building ---------------------------------------------------------------------------------

## Sun, sky and haze, the terrain, and every module (as its proxy until it streams in).
func _build_environment() -> void:
	var started := Time.get_ticks_usec()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 250.0
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = FOG_COLOUR
	env.fog_density = FOG_DENSITY
	env.fog_sky_affect = 0.5
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	terrain = ZoneTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.generate(def, _flat_areas())
	terrain.build_collision()
	var holder := Node3D.new()
	holder.name = "Modules"
	add_child(holder)
	for m: Dictionary in def.get("modules", []):
		var p: Array = m.pos
		var module := ZoneModule.new()
		module.setup(String(m.id), String(m.type), Vector3(float(p[0]), terrain.height_at(float(p[0]), float(p[1])), float(p[1])))
		module.view_voxels = int((STREAM_OUT_M + 80.0) / VoxelWorld.VOXEL_SIZE)
		holder.add_child(module)
		_modules.append(module)
		_by_id[module.module_id] = module
	if DisplayServer.get_name() != "headless":
		terrain.build_visuals()
		var at := insertion_points()[0]
		terrain.build_near(at, 16)
	generate_ms = (Time.get_ticks_usec() - started) / 1000.0
	print("[zone] '%s' (%d m, seed %d, %d modules) generated in %.0f ms" % [def.get("id", ""), int(terrain.size_m), terrain.seed_value, _modules.size(), generate_ms])


## Flat pads: each module's footprint, landing zones at the extraction candidates, and the
## insertion points.
func _flat_areas() -> Array:
	var out: Array = []
	for m: Dictionary in def.get("modules", []):
		var half: Vector2 = ZoneModules.HALF.get(String(m.type), Vector2(20, 20))
		var p := Vector2(float(m.pos[0]), float(m.pos[1]))
		out.append(Rect2(p - half, half * 2.0))
	for p: Array in def.get("extraction", []):
		out.append(Rect2(float(p[0]) - 12.0, float(p[1]) - 12.0, 24.0, 24.0))
	for p: Array in def.get("insertion", []):
		out.append(Rect2(float(p[0]) - 8.0, float(p[1]) - 8.0, 16.0, 16.0))
	return out


func _build_structures() -> void:
	pass  # the modules hold the structures


# --- Hosting ----------------------------------------------------------------------------------

func _on_hosted() -> void:
	GameState.load_zone()
	_logs = {}
	for edit: Dictionary in GameState.voxel_edits:
		if edit.has("w"):
			_log(String(edit.w)).append(edit)
	for module in _modules:
		for loot: Dictionary in ZoneModules.LOOT.get(module.type, []):
			var uid := "%s_%s" % [module.module_id, loot.uid]
			if not GameState.is_looted(uid):
				spawn_item(StringName(loot.id), loot.get("count", 1), module.to_global(loot.pos), uid)
	if def.get("insertion_kit", false):
		_spawn_insertion_kit()
	for uid: String in GameState.dropped:
		var d: Dictionary = GameState.dropped[uid]
		spawn_item(StringName(d.id), int(d.count), Vector3(d.pos[0], d.pos[1], d.pos[2]), uid, GameState.from_json(d.get("state", {})))
	player_roles[1] = Roles.local_choice
	_add_player(1)
	nav = ZoneNav.build_zone(self)
	_restore_bodies()
	if spawn_ai:
		_spawn_ai()
	_update_streaming()


## The test compound's starting loot, laid out in rows in front of the default insertion
## point (a zone definition with "insertion_kit": the test zone).
func _spawn_insertion_kit() -> void:
	var at := insertion_points()[0]
	# Clean sessions: only the spares row (the compound's objective items mean nothing here).
	var kit: Array = LOOT if not clean_loot else CLEAN_LOOT.filter(func(l: Dictionary) -> bool: return float((l.pos as Vector3).z) > 20.0)
	for i in kit.size():
		var loot: Dictionary = kit[i]
		var uid := "kit_%s" % loot.uid
		if GameState.is_looted(uid):
			continue
		var p := at + Vector3((i % 8 - 3.5) * 0.8, 0, -4.0 - (i / 8) * 0.8)
		spawn_item(StringName(loot.id), loot.get("count", 1), ground_point(p) + Vector3.UP * 0.4, uid)


## Host only. The player squad; hostile garrisons come with their modules (_on_streamed_in).
func _spawn_ai() -> void:
	_ai_ready = true
	rebalance_squad()
	for module in _modules:
		if module.is_ready():
			_spawn_garrison(module)


## How many hostiles hold module `module_id`: the true enemy count (Contracts.enemy_force)
## of a deployed contract that targets it (the most, if several do), else the module's own
## posts (ZoneModules.GARRISON: 4). An understated briefing really bites.
func garrison_size(module_id: String) -> int:
	var module := get_module(module_id)
	var n: int = (ZoneModules.GARRISON.get(module.type, []) as Array).size() if module else 0
	var target := -1
	for cid: String in Contracts.deployment().get("cids", []):
		if String(Contracts.contract(cid).get("module_id", "")) == module_id:
			target = maxi(target, int(Contracts.enemy_force(cid).get("count", 0)))
	return target if target >= 0 else n


## Host: a contract went live; its target module may already hold its first garrison (it
## streamed in before the briefing), so it's topped up to the true count.
func _on_contract_live(cid: String, _objectives: Array) -> void:
	if not multiplayer.is_server():
		return
	var module := get_module(String(Contracts.contract(cid).get("module_id", "")))
	if module and _garrisoned.has(module.module_id):
		_spawn_garrison(module)


## Host only. A module's hostiles (garrison_size of them: the module's posts, then extra posts
## beside them), all but those whose bodies the zone save holds, in buddy pairs, holding their
## ground. Called again it tops the garrison up to garrison_size (never takes anyone away).
func _spawn_garrison(module: ZoneModule) -> void:
	if not _ai_ready or not spawn_ai:
		return
	var from := int(_garrisoned.get(module.module_id, 0))
	var want := garrison_size(module.module_id)
	if _garrisoned.has(module.module_id) and from >= want:
		return
	_garrisoned[module.module_id] = maxi(from, want)
	var fallen := {}
	for record: Dictionary in GameState.bodies:
		if String(record.get("faction", "")) == "hostile":
			fallen[String(record.get("label", ""))] = true
	var spots: Array = ZoneModules.GARRISON.get(module.type, [])
	if spots.is_empty():
		return
	var taken: Array[Vector3] = []
	for i in range(from, want):
		var callsign := _garrison_callsign(module, i)
		if fallen.has(callsign) or ai.get_node_or_null(NodePath(callsign)) != null:
			continue
		var pos := module.to_global(spots[i]) if i < spots.size() else _extra_post(module.to_global(spots[i % spots.size()]), taken)
		taken.append(pos)
		spawn_soldier({"name": callsign, "faction": "hostile", "variant": "urban", "pos": pos,
			"loadout": HOSTILE_LOADOUT, "combat": GARRISON_STATS.combat, "discipline": GARRISON_STATS.discipline, "guard": true,
			"mode": GARRISON_STATS.mode})
	for i in want:
		var me := ai.get_node_or_null(NodePath(_garrison_callsign(module, i))) as Soldier
		if me and (me.buddy == null or not is_instance_valid(me.buddy)):
			me.buddy = ai.get_node_or_null(NodePath(_garrison_callsign(module, i ^ 1))) as Soldier


func _garrison_callsign(module: ZoneModule, i: int) -> String:
	return ("%s_H%d" % [module.module_id, i + 1]).validate_node_name()


## Host: a clear spot for an extra garrison post beside the post at `post` (world): the first
## of EXTRA_POST_RINGS_M round it with room for a man (no wall, nobody already put in `taken`),
## else the post itself nudged aside.
func _extra_post(post: Vector3, taken: Array[Vector3]) -> Vector3:
	var space := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = EXTRA_POST_CLEAR_M
	shape.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	var start := absi(hash(post)) % 8
	for r in EXTRA_POST_RINGS_M:
		for k in 8:
			var a := TAU * float((start + k) % 8) / 8.0
			var p := post + Vector3(cos(a), 0.0, sin(a)) * r
			if taken.any(func(t: Vector3) -> bool: return t.distance_to(p) < EXTRA_POST_CLEAR_M * 2.5):
				continue
			query.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.0)
			if space.intersect_shape(query, 1).is_empty():
				return p
	return post + Vector3(0.9, 0.0, 0.9 * float(taken.size() % 3))


func _add_player(id: int) -> void:
	super._add_player(id)
	var player := players.get_node_or_null(str(id)) as Node3D
	if player:
		player.position = player_spawn(id)
		(player as Soldier).spawn_position = player.position


## A client's own player as it spawns there: the host's spawn doesn't carry its position (its
## owner drives that, so it would start at the zone's centre), so it goes to the same spot
## the host put it on (player_spawn).
func _on_player_entered(node: Node) -> void:
	var me := multiplayer.get_unique_id()
	if not multiplayer.is_server() and node is Node3D and String(node.name) == str(me):
		(node as Node3D).position = player_spawn(me)


func _on_peer_joined(id: int) -> void:
	if not multiplayer.is_server():
		return
	_receive_logs.rpc_id(id, _logs)
	_add_player(id)
	get_tree().create_timer(JOIN_ROLE_WAIT_S).timeout.connect(_on_join_role_timeout.bind(id))


# --- Voxel edits ------------------------------------------------------------------------------

func _log(id: String) -> Array:
	if not _logs.has(id):
		_logs[id] = []
	return _logs[id]


## Host only (a module's VoxelWorld.edit_sink): logs the edit for its module and for the save,
## applies it here and sends it to every client.
func _on_module_edit(world: VoxelWorld, edit: Dictionary) -> void:
	edit["w"] = world.module_id
	GameState.voxel_edits.append(edit)
	_log(world.module_id).append(edit)
	var m := get_module(world.module_id)
	if m:
		m.sync(_logs[world.module_id])
	_module_edit.rpc(edit)


@rpc("authority", "reliable")
func _module_edit(edit: Dictionary) -> void:
	var id := String(edit.get("w", ""))
	_log(id).append(edit)
	var m := get_module(id)
	if m:
		m.sync(_logs[id])


## A joining client gets every module's log (applied as each module streams in).
@rpc("authority", "reliable")
func _receive_logs(logs: Dictionary) -> void:
	_logs = logs
	for m in _modules:
		m.sync(_log(m.module_id))


# --- Streaming --------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _next_stream:
		_next_stream = now + STREAM_CHECK_S
		_update_streaming()


## Streams modules in near the soldiers this peer streams for (stream_focus) and out far from
## all of them; at most one in per call.
func _update_streaming() -> void:
	var focus := stream_focus()
	var nearest: ZoneModule = null
	var nearest_d := INF
	for m in _modules:
		var d := INF
		for p in focus:
			d = minf(d, m.distance_to(p))
		if m.is_streamed():
			if d > STREAM_OUT_M:
				m.stream_out()
		elif d <= STREAM_IN_M and d < nearest_d:
			nearest = m
			nearest_d = d
	if nearest:
		_stream_in(nearest)


func _stream_in(m: ZoneModule) -> void:
	var host := multiplayer.is_server()
	m.stream_in(_log(m.module_id), _on_module_edit if host else Callable())
	if host:
		if nav:
			nav.watch(m.voxel_world)
		if not m.streamed_in.is_connected(_on_streamed_in):
			m.streamed_in.connect(_on_streamed_in)


func _on_streamed_in(m: ZoneModule) -> void:
	if multiplayer.is_server():
		_spawn_garrison(m)


## Where modules stream in around on this peer: on the host every player and every AI soldier
## in a fight (SquadAI.fighting), on a client its own player.
func stream_focus() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var host := multiplayer.is_server()
	for p in players.get_children():
		var s := p as Soldier
		if s and not s.is_queued_for_deletion() and (host or s.is_local()):
			out.append(s.global_position)
	if host:
		for n in ai.get_children():
			var s := n as Soldier
			if s and not s.is_queued_for_deletion() and not s.vitals.is_dead():
				var brain := SquadAI.of(s)
				if brain and brain.fighting():
					out.append(s.global_position)
	return out


## Host: the soldiers the navigation is kept baked around (players and living AI).
func soldiers_for_navigation() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for holder: Node in [players, ai]:
		for n in holder.get_children():
			var s := n as Soldier
			if s and not s.is_queued_for_deletion() and not s.vitals.is_dead():
				out.append(s)
	return out


## Where a reinforcement wave comes in (Reinforcements.edge_point): on the zone's edge, inside
## the terrain, near the players (`players`: their x, z) but out of their sight. A world point.
func reinforcement_edge(players: Array[Vector2]) -> Vector3:
	var area := map_area().grow(-REINFORCE_INSET_M)
	var best := area.get_center()
	var best_score := INF
	var far := best
	var far_d := -1.0
	for i in REINFORCE_TRIES:
		var spot := Reinforcements._perimeter_point(area, (float(i) + randf()) / REINFORCE_TRIES)
		var d := INF
		for p in players:
			d = minf(d, spot.distance_to(p))
		if d > far_d:
			far_d = d
			far = spot
		if d >= REINFORCE_MIN_M and d < best_score:
			best_score = d
			best = spot
	var at := best if best_score < INF else far
	return ground_point(Vector3(at.x, 0.0, at.y))
