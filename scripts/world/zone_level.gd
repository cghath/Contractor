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
## Haze: about 70% clear at 1 km, half at 2 km (was 50% at 1 km: everything washed out).
const FOG_DENSITY := 0.00035
const FOG_COLOUR := Color(0.72, 0.77, 0.83)
## Sun and sky: a warm sun, a clear blue sky paling to a warm haze at the horizon.
const SUN_COLOUR := Color(1.0, 0.94, 0.84)
const SKY_TOP := Color(0.24, 0.42, 0.68)
const SKY_HORIZON := Color(0.70, 0.74, 0.78)
const SUN_ENERGY := 1.25
const FILL_ENERGY := 0.35
const EXPOSURE := 1.05
## The sun's elevation (degrees; see _build_environment) and the fill's, for ground_glare.
const SUN_ELEVATION_DEG := 38.0
const FILL_ELEVATION_DEG := 60.0
const AMBIENT_ENERGY := 0.95
## The sky with far ridges, for a preset with a "backdrop" (sky_for).
const SKY_SHADER := preload("res://scripts/world/zone_sky.gdshader")
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
## One man in this many of a garrison (its first, then every RADIO_EVERY-th) carries the
## site's handheld radio ("enemy_radio"; looted, RadioChatter). Proposed.
const RADIO_EVERY := 4
## Captain, 2026-10-17: "the enemy does need some more medics ... we never see them": every
## ENEMY_MEDIC_EVERY'th garrison post is a medic (Roles kit: aid bag and the rest).
const ENEMY_MEDIC_EVERY := 5

## The zone definition (ZoneDef), set before the node enters the tree (configure()).
var def: Dictionary = {}
var terrain: ZoneTerrain
var scatter: ZoneScatter  # rocks, scrub and trees on it
## Spawns WorldCache nodes at the scatter's VALUABLE sites (WorldValuables): one per peer, the
## host's spawn (with its seeded loot) replicates to everyone, late joiners included.
var cache_spawner: MultiplayerSpawner
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
## Host: garrison soldiers put in but still to come out (_spawn_garrison queues them; at most
## PeopleLayer.SPAWN_BUDGET_MS of spawning a frame): [{"module_id", "i", "pos"}], and how many
## each module still has coming (garrison_pending).
var _garrison_queue: Array[Dictionary] = []
var _garrison_pending := {}
var _garrison_nav_held := false
var _next_stream := 0.0
## Host: this zone's EnemyResponse (patrols, QRF waves, hunters), so _on_contract_live can set
## its enemy_faction from a live contract's target (CLAUDE.md squad-roles-pmc bundle).
var _enemy_response: EnemyResponse


## Sets the zone definition (ZoneDef). Call before adding the node to the tree.
func configure(p_def: Dictionary) -> void:
	def = ZoneDef.normalize(p_def)


func _ready() -> void:
	if def.is_empty():
		def = ZoneDef.get_def("test")
	super._ready()
	squad_for(&"hostile").patrol = []  # garrisons hold their ground
	if not def.get("no_pallets", false):  # supply pallets at the sites, taggable (feat/pallet-tagging)
		var pallet_field := PalletField.new()
		add_child(pallet_field)
		pallet_field.build(_modules, ground_point)
	# Captain, 2026-10-16 ("its boring ... missions are repetitive", "roads or paths across the
	# map enemies like to patrol"): Alert/Pressure/EnemyResponse/RadioChatter used to be hot-zone
	# only, so a regular contract zone's garrison just held its ground with no roads, no roaming
	# patrols and no escalation. Every zone gets them now; EnemyResponse degrades gracefully with
	# no "hq"/"qrf_base" modules (no hunters, no QRF waves — those stay a hot-zone thing). Only
	# HotZoneOps (multi-contract radio follow-ups, hazard pay) and the debug overlay stay hot-only.
	add_child(Alert.new())  # the enemy's alert: what they see, hear and report (4B part 3)
	add_child(Pressure.new())  # what the squad has done here, long term
	_enemy_response = EnemyResponse.new()
	add_child(_enemy_response)  # patrols, QRF waves, hunters: the enemy's answer
	if multiplayer.is_server():
		_set_enemy_faction(_zone_enemy())  # wave 6b: whose kit the garrisons wear from the first spawn
		_apply_difficulty_scale()
	add_child(RadioChatter.new())  # what a looted enemy radio lets the squad hear
	add_child(UrbanDefence.new())  # towns fought from inside: reserves, falling back, relief (Captain, 2026-10-17)
	add_child(ZoneCleanup.new())  # bodies and dropped loot go after ~6-7 min (blood on its own clock)
	add_child(DynamicSim.new())  # far AI stops simulating until a player comes near (Captain, 2026-10-18)
	add_child(SquadTrail.new())  # the trail the squad leaves, for enemy trackers (Captain, 2026-10-18)
	add_child(Bombers.new())  # insurgent suicide bombers on foot (wave 6f)
	add_child(RivalTeam.new())  # a rival PMC racing the squad to some contracts' sites (wave 6)
	add_child(RoadsideIeds.new())  # a contract's "IEDs" threat buried on the roads near its site (wave 6)
	add_child(EnemyDrones.new())  # the enemy's recon drones over a hot zone, and the jammer (wave 6)
	add_child(IntelReveal.new())  # intel picked up gives away enemy sites on the map
	if String(def.get("kind", "")) == "hot":
		add_child(HotZoneOps.new())  # several contracts live, radio follow-ups, hazard pay
		add_child(EnemyCommand.new())  # the enemy's high command: what it sends, and whether (docs/enemy_high_command.md)
		if DevTools.on():
			add_child(HotZoneDebug.new())  # playtests: PgUp readout, PgDn skips the enemy's clock
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


## Where there is ground: the whole zone (its edge walls stand just outside).
func ground_area() -> Rect2:
	return map_area()


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


## Where a dead player may respawn (CompoundLevel.respawn_point), best first: the insertion
## point the briefing chose, the zone's other insertion points, then its extraction points.
func respawn_candidates() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var briefing := MapNodes.briefing(self)
	if briefing:
		add_respawn_candidate(out, briefing.insertion().get("pos", []))
	for p in insertion_points():
		add_respawn_candidate(out, ground_point(p))
	for p in extraction_points():
		add_respawn_candidate(out, ground_point(p))
	return out


## Every insertion and extraction point hot: the FOB (Lhd, inland), where the company's ground
## supports come from. An LHD offshore isn't one: nobody walks ashore from its deck.
func respawn_fallback() -> Variant:
	var origin := get_node_or_null(NodePath(Lhd.NODE_NAME)) as Lhd
	if origin == null or origin.is_ship():
		return null
	return ground_point(origin.global_position)


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
	var look := sky_for(String(def.get("terrain", "plain")))
	var sun := DirectionalLight3D.new()
	# A mid-morning sun, lower than before, so slopes and scrub read in light and shade.
	sun.rotation_degrees = Vector3(-SUN_ELEVATION_DEG, -35, 0)
	sun.light_color = SUN_COLOUR
	sun.light_energy = float(look.sun_energy)
	sun.shadow_bias = 0.15  # the lower sun streaks the gentle slopes with acne at the defaults
	sun.shadow_normal_bias = 3.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 250.0
	GameSettings.apply_sun(sun)  # the shadows setting
	add_child(sun)
	# Sky fill: a weak, shadowless light from the far side, so the shade sides of rocks, crowns
	# and walls read as rock and foliage instead of near-black.
	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.rotation_degrees = Vector3(-FILL_ELEVATION_DEG, 145, 0)
	fill.light_color = Color(0.72, 0.80, 0.95)
	fill.light_energy = float(look.fill_energy)
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	add_child(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	if look.has("backdrop"):
		env.sky.sky_material = _backdrop_sky(look)
	else:
		var sky := ProceduralSkyMaterial.new()
		sky.sky_top_color = look.sky_top
		sky.sky_horizon_color = look.sky_horizon
		sky.ground_horizon_color = look.sky_horizon
		sky.ground_bottom_color = look.sky_horizon  # past the camera's far plane: haze, not a dark void
		sky.sun_angle_max = 20.0
		env.sky.sky_material = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = AMBIENT_ENERGY  # with the lower, warmer sun: the shade side reads, the ground stops looking flat-lit
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = float(look.exposure)
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.0
	env.fog_enabled = true
	env.fog_light_color = look.fog_colour
	env.fog_density = float(look.fog_density)
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.6  # distant ground takes the sky's colour, not a flat grey
	env.fog_sun_scatter = 0.15
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	terrain = ZoneTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.generate(def, _flat_areas())
	terrain.build_collision()
	scatter = ZoneScatter.new()
	scatter.name = "Scatter"
	add_child(scatter)
	scatter.generate(terrain, def)
	scatter.build_collision()
	var cache_holder := Node3D.new()
	cache_holder.name = "Caches"
	add_child(cache_holder)
	cache_spawner = MultiplayerSpawner.new()
	cache_spawner.name = "CacheSpawner"
	cache_spawner.spawn_path = NodePath("../" + String(cache_holder.name))
	cache_spawner.spawn_function = _make_cache
	add_child(cache_spawner)
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
		scatter.build_visuals()
		var roads := ZoneRoads.new()
		roads.name = "Roads"
		add_child(roads)
		roads.build(terrain, def)
		var at := insertion_points()[0]
		terrain.build_near(at, 16)
		scatter.build_near(at, 4)
	generate_ms = (Time.get_ticks_usec() - started) / 1000.0
	print("[zone] '%s' (%d m, seed %d, %d modules) generated in %.0f ms" % [def.get("id", ""), int(terrain.size_m), terrain.seed_value, _modules.size(), generate_ms])


## The zone's light for terrain preset `preset_id`: the preset's "sky" (sun_energy, fill_energy,
## exposure, fog_density, and hex fog_colour, sky_top, sky_horizon) over the defaults above, and
## its "backdrop" (far ridges in the sky: colour, near_deg, far_deg) if it has one. Captain,
## 2026-10-14: the salt flats' pan was brighter than the sky ("an actual eye sore"); its preset
## lowers the sun and exposure and hazes the horizon.
static func sky_for(preset_id: String) -> Dictionary:
	var preset := TerrainPresets.get_preset(preset_id)
	var s: Dictionary = preset.get("sky", {})
	var colour := func(key: String, fallback: Color) -> Color: return Color(String(s[key])) if s.has(key) else fallback
	var out := {"sun_energy": float(s.get("sun_energy", SUN_ENERGY)), "fill_energy": float(s.get("fill_energy", FILL_ENERGY)),
		"exposure": float(s.get("exposure", EXPOSURE)), "fog_density": float(s.get("fog_density", FOG_DENSITY)),
		"fog_colour": colour.call("fog_colour", FOG_COLOUR), "sky_top": colour.call("sky_top", SKY_TOP), "sky_horizon": colour.call("sky_horizon", SKY_HORIZON)}
	if preset.has("backdrop"):
		out["backdrop"] = preset.backdrop
	return out


## Roughly how bright the lit flat ground of preset `preset_id` is against the sky at the
## horizon (linear luminance, ratio; 1 is as bright): its palette's ground colours (by
## Spotting's GROUND shares, without the scrub) lit by the sun, the fill and the sky's ambient.
## Over 1 the ground outshines the sky and glares (salt_flats was 1.48 before 2026-10-14).
static func ground_glare(preset_id: String) -> float:
	var look := sky_for(preset_id)
	var palette: Dictionary = TerrainPresets.get_preset(preset_id).get("palette", {})
	var lum := func(c: Color) -> float: return c.srgb_to_linear().get_luminance()
	var ground := 0.0
	var weight := 0.0
	for part: String in ["grass", "dry", "earth"]:
		if palette.has(part):
			ground += float(lum.call(Color(String(palette[part])))) * float(Spotting.GROUND[part])
			weight += float(Spotting.GROUND[part])
	ground /= maxf(weight, 0.001)
	var horizon: float = lum.call(look.sky_horizon)
	var ambient: float = AMBIENT_ENERGY * (horizon + float(lum.call(look.sky_top))) * 0.5
	var light := float(look.sun_energy) * sin(deg_to_rad(SUN_ELEVATION_DEG)) + float(look.fill_energy) * sin(deg_to_rad(FILL_ELEVATION_DEG)) + ambient
	return ground * light / maxf(horizon, 0.001)


## The sky for a preset with a "backdrop" (zone_sky.gdshader): the sky's gradient and sun, and
## far ridges round the horizon, seeded by the zone.
func _backdrop_sky(look: Dictionary) -> ShaderMaterial:
	var b: Dictionary = look.backdrop
	var m := ShaderMaterial.new()
	m.shader = SKY_SHADER
	m.set_shader_parameter(&"sky_top", look.sky_top)
	m.set_shader_parameter(&"sky_horizon", look.sky_horizon)
	m.set_shader_parameter(&"ridge_colour", Color(String(b.get("colour", "8a8478"))))
	var near: Array = b.get("near_deg", [0.25, 1.1])
	var far: Array = b.get("far_deg", [0.6, 2.4])
	m.set_shader_parameter(&"near_deg", Vector2(float(near[0]), float(near[1])))
	m.set_shader_parameter(&"far_deg", Vector2(float(far[0]), float(far[1])))
	m.set_shader_parameter(&"seed", float(int(def.get("seed", 0)) % 101))
	return m


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

func _exit_tree() -> void:
	BodyVolume.finish_warm()


## The CacheSpawner's spawn_function: a WorldCache at `data` ("uid", "pos", "yaw", "label").
func _make_cache(data: Dictionary) -> Node:
	var cache := WorldCache.new(String(data.get("label", "Cache")), StringName(data.get("key", "")))
	cache.name = String(data.uid)
	cache.uid = String(data.uid)
	cache.position = data.pos
	cache.rotation.y = float(data.get("yaw", 0.0))
	return cache


func _on_hosted() -> void:
	# Hits are judged on the host: both bodies' shapes built on a worker as the zone loads (the
	# first hit in a zone used to build them mid-fight: 200-340 ms, tests/perf_timing.gd).
	BodyVolume.warm_async(["", BodyVolume.FEMALE])
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
	WorldValuables.server_spawn_all(self)  # caches, crates, wrecks with kit and dead drops out in the open terrain
	WorldValuables.server_spawn_site_boxes(self)  # a valuables/intel box at each site, sometimes a rare find
	if def.get("insertion_kit", false):
		_spawn_insertion_kit()
	var pallet_node := get_node_or_null(^"PalletField") as PalletField
	if pallet_node:
		pallet_node.server_spawn_vehicles(_modules)  # abandoned vehicles at the sites
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
	var response := get_node_or_null(^"EnemyResponse") as EnemyResponse
	if response:
		response.server_start()  # hot zones: the roaming patrols set out


## How many hostiles hold module `module_id`: the true enemy count (Contracts.enemy_force)
## of a deployed contract that targets it (the most, if several do), else the module's own
## posts (ZoneModules.GARRISON: 4). An understated briefing really bites.
## How much of the zone's enemy a deployment meets, by its contracts' true rating (Captain,
## 2026-10-18: "fighting like 16 dudes at once in a 2 difficulty mission?"): DIFFICULTY_SCALE
## by the highest true_rating of this deployment's contracts here, no lower than
## HOT_ZONE_MIN_SCALE in a hot zone (its fights are meant to be big). 1.0 with no contract
## (tests, free roam). Scales the other sites' garrisons (the contract's own target keeps its
## briefed count), the wave cap (Reinforcements.scale), hunter teams (EnemyResponse.scale) and a
## rival team (RivalTeam).
const DIFFICULTY_SCALE: Array[float] = [1.0, 0.45, 0.6, 0.75, 0.9, 1.0]
const HOT_ZONE_MIN_SCALE := 0.75


func difficulty_scale() -> float:
	var rating := 0
	var zid := GameState.zone_id
	var cids: Array = Contracts.deployment().get("cids", [])
	for c: Dictionary in Contracts.held():
		if String(c.get("cid", "")) in cids and String(c.get("zone_id", zid)) == zid:
			rating = maxi(rating, int(c.get("true_rating", c.get("rated", 0))))
	if rating <= 0:
		return 1.0
	var s: float = DIFFICULTY_SCALE[clampi(rating, 0, DIFFICULTY_SCALE.size() - 1)]
	return maxf(s, HOT_ZONE_MIN_SCALE) if String(def.get("kind", "")) == "hot" else s


func garrison_size(module_id: String) -> int:
	var module := get_module(module_id)
	var n: int = (ZoneModules.GARRISON.get(module.type, []) as Array).size() if module else 0
	n = maxi(mini(n, 2), ceili(n * difficulty_scale()))  # the other sites by difficulty (the target keeps its briefed count, below)
	var target := -1
	for cid: String in Contracts.deployment().get("cids", []):
		if String(Contracts.contract(cid).get("module_id", "")) == module_id:
			# A defend mission's position is ours to hold: no garrison (its enemies come as waves).
			var held: bool = bool(MissionRegistry.type_def(String(Contracts.contract(cid).get("type", ""))).get("no_garrison", false))
			target = maxi(target, 0 if held else int(Contracts.enemy_force(cid).get("count", 0)))
	return target if target >= 0 else n


## Host: a contract went live; its target module may already hold its first garrison (it
## streamed in before the briefing), so it's topped up to the true count.
func _on_contract_live(cid: String, _objectives: Array) -> void:
	if not multiplayer.is_server():
		return
	var contract := Contracts.contract(cid)
	# CLAUDE.md squad-roles-pmc bundle: a contract against the Vantage Group rival PMC switches
	# this zone's reinforcement waves (EnemyResponse) to its gear; any other target leaves the
	# zone's usual hostile mix alone (several contracts can be live in a hot zone; the last one
	# whose target is the PMC wins, same simplification Alert and Pressure already make per zone).
	# Wave 6b: any target faction with a kit of its own (Vantage, a regional army) does the same, and
	# the QRF waves (Reinforcements) follow it too (they stayed Black Ridge's before).
	_apply_difficulty_scale()
	var target := String(contract.get("target", ""))
	if _enemy_response and target != "" and Kits.kit_of(target) != Kits.INSURGENT:
		# Vantage's exo gear is difficulty-gated (CompoundLevel.PMC_LX3_DIFFICULTY/HX1_DIFFICULTY):
		# true_rating, the host's real 1-5 rating, not "rated" (the briefing, which can understate it).
		_set_enemy_faction(target, int(contract.get("true_rating", contract.get("rated", 1))))
	var module := get_module(String(contract.get("module_id", "")))
	if module and _garrisoned.has(module.module_id):
		_spawn_garrison(module)


## Host: whose men this zone's patrols, waves, hunters and garrisons are (and their kit), with
## the difficulty that gates a PMC's exo gear. "" leaves the zone's usual Black Ridge mix.
func _set_enemy_faction(faction: String, difficulty := -1) -> void:
	if _enemy_response == null or faction == "":
		return
	_enemy_response.enemy_faction = StringName(faction)
	if difficulty > 0:
		_enemy_response.difficulty = difficulty
	var waves := _enemy_response.reinforcements
	if waves:
		waves.enemy_faction = StringName(faction)
		waves.difficulty = _enemy_response.difficulty
	_apply_difficulty_scale()


## Host: the deployment's difficulty scale onto the waves' cap and the hunters.
func _apply_difficulty_scale() -> void:
	if _enemy_response == null:
		return
	var s := difficulty_scale()
	_enemy_response.scale = s
	if _enemy_response.reinforcements:
		_enemy_response.reinforcements.scale = s


## Wave 6b's open item ("a garrison already spawned before its contract went live keeps the
## militia kit"): who the zone's enemy is as it loads, before any contract goes live. A held
## contract of this deployment in this zone against a kitted faction (the first one), else a hot
## zone's holder (WorldSites, the persistent world: only read, never seeded here, so a test zone
## hosted on its own writes no campaign), else "" (Black Ridge, as before).
func _zone_enemy() -> String:
	var zid := GameState.zone_id
	var cids: Array = Contracts.deployment().get("cids", [])
	for c: Dictionary in Contracts.held():
		var target := String(c.get("target", ""))
		if String(c.get("cid", "")) in cids and String(c.get("zone_id", "")) == zid and target != "" and Kits.kit_of(target, zid) != Kits.INSURGENT:
			return target
	if String(def.get("kind", "")) == "hot":
		var site: Dictionary = Campaign.section(WorldSites.SECTION).get(zid, {})
		var holder := String(site.get("holder", ""))
		if holder != "" and Kits.kit_of(holder, zid) != Kits.INSURGENT:
			return holder
	return ""


## Host only. A module's hostiles (garrison_size of them: the module's posts, then extra posts
## beside them), all but those whose bodies the zone save holds, in buddy pairs, holding their
## ground. Called again it tops the garrison up to garrison_size (never takes anyone away).
## Their posts are worked out now; the soldiers come out over the next frames, a few a frame
## (Captain P0362: a deploy's spawns all in one frame were a 3.4 s hitch). Until the last is out
## the module's garrison is still coming (garrison_pending): not spawned yet for a clear-area
## objective, not down, no missed check-ins.
func _spawn_garrison(module: ZoneModule) -> void:
	if not _ai_ready or not spawn_ai:
		return
	var from := int(_garrisoned.get(module.module_id, 0))
	var want := garrison_size(module.module_id)
	if _garrisoned.has(module.module_id) and from >= want:
		return
	_garrisoned[module.module_id] = maxi(from, want)
	var spots: Array = ZoneModules.GARRISON.get(module.type, [])
	var faces: Array = ZoneModules.GARRISON_FACE.get(module.type, [])  # the way a post looks out (towns)
	if spots.is_empty():
		return
	var taken: Array[Vector3] = []
	for i in range(from, want):
		var callsign := _garrison_callsign(module, i)
		if GameState.post_is_fallen(callsign) or ai.get_node_or_null(NodePath(callsign)) != null:
			continue
		var pos := module.to_global(spots[i]) if i < spots.size() else _extra_post(module.to_global(spots[i % spots.size()]), taken)
		var face: Vector3 = faces[i] if i < spots.size() and i < faces.size() else Vector3.ZERO
		taken.append(pos)
		if _garrison_queue.is_empty() and nav and not _garrison_nav_held:
			nav.hold()  # the navigation's rebakes wait for the last of them (NavBuilder.hold)
			_garrison_nav_held = true
		_garrison_queue.append({"module_id": module.module_id, "i": i, "pos": pos, "face": face})
		_garrison_pending[module.module_id] = garrison_pending(module.module_id) + 1
	if garrison_pending(module.module_id) == 0:
		_pair_garrison(module)  # nobody to wait for: the ones still up pair as they are


## Host: how many of module `module_id`'s garrison are put in but still to come out.
func garrison_pending(module_id: String) -> int:
	return int(_garrison_pending.get(module_id, 0))


## Host: spawns queued garrison soldiers, at most PeopleLayer.SPAWN_BUDGET_MS a frame (at least one).
func _spawn_queued_garrison() -> void:
	var until := Time.get_ticks_usec() + int(PeopleLayer.SPAWN_BUDGET_MS * 1000.0)
	var alert := get_node_or_null(^"Alert") as Alert  # hot zones: relaxed until something happens
	while not _garrison_queue.is_empty():
		var q: Dictionary = _garrison_queue.pop_front()
		var module := get_module(String(q.module_id))
		var i := int(q.i)
		var pos: Vector3 = q.pos
		if module and ai.get_node_or_null(NodePath(_garrison_callsign(module, i))) == null:
			# Wave 6b: a regional army's (data kit's) garrisons wear and carry its kit.
			var kit_id := Kits.kit_of(_enemy_response.enemy_faction) if _enemy_response else Kits.INSURGENT
			var data_kit := Kits.is_data(kit_id)
			var kit: Array = Kits.loadout(kit_id, i) if data_kit else hostile_loadout(i)
			if module.type == "hq" and i == 0:
				kit = kit + [String(WorldValuables.STRONGBOX_KEY)]  # wave 6: the HQ's officer carries its strongbox key
			var s := spawn_soldier({"name": _garrison_callsign(module, i), "faction": "hostile", "variant": Kits.variant(kit_id) if data_kit else "urban", "pos": pos,
				"loadout": kit + ["enemy_radio"] if i % RADIO_EVERY == 0 else kit, "combat": GARRISON_STATS.combat, "discipline": GARRISON_STATS.discipline, "guard": true,
				"mode": alert.mode_at(pos) if alert else GARRISON_STATS.mode,
				"role": "medic" if i % ENEMY_MEDIC_EVERY == ENEMY_MEDIC_EVERY - 1 else (Kits.role(kit_id, i) if data_kit else CompoundLevel.hostile_role(i))})
			if s:
				var look := module.global_basis * (q.get("face", Vector3.ZERO) as Vector3)  # a post's way out (towns)
				s.rotation.y = post_yaw(module, pos) if look.length() < 0.1 else atan2(-look.x, -look.z)
		var left := garrison_pending(String(q.module_id)) - 1
		if left > 0:
			_garrison_pending[q.module_id] = left
		else:
			_garrison_pending.erase(q.module_id)
			if module:
				_pair_garrison(module)
		if Time.get_ticks_usec() >= until:
			break
	if _garrison_queue.is_empty() and _garrison_nav_held:
		_garrison_nav_held = false
		if is_instance_valid(nav):
			nav.release()


## Buddy pairs in module `module`'s garrison (posts 1 and 2, 3 and 4, ...), for those up.
func _pair_garrison(module: ZoneModule) -> void:
	for i in int(_garrisoned.get(module.module_id, 0)):
		var me := ai.get_node_or_null(NodePath(_garrison_callsign(module, i))) as Soldier
		if me and (me.buddy == null or not is_instance_valid(me.buddy)):
			me.buddy = ai.get_node_or_null(NodePath(_garrison_callsign(module, i ^ 1))) as Soldier


## The way a garrison post at `pos` faces (rotation.y): out of its site, away from the module's
## middle (Captain 2026-10-12: gate guards face the entrance, tower guards look out).
static func post_yaw(module: ZoneModule, pos: Vector3) -> float:
	var d := pos - module.global_position
	if Vector2(d.x, d.z).length() < 0.5:
		return 0.0
	return atan2(-d.x, -d.z)


func _garrison_callsign(module: ZoneModule, i: int) -> String:
	return ("%s_H%d" % [module.module_id, i + 1]).validate_node_name()


## Host: module `module_id`'s garrison still up (spawned and alive; men EnemyCommand put back on
## a retaken site count too: meta "garrison_of"; men who abandoned it don't: meta "left_post").
func garrison_alive(module_id: String) -> int:
	var prefix := ("%s_H" % module_id).validate_node_name()
	var count := 0
	for n in ai.get_children():
		var s := n as Soldier
		if s and (String(s.name).begins_with(prefix) or String(s.get_meta(&"garrison_of", "")) == module_id) \
				and not s.get_meta(&"left_post", false) and not s.is_queued_for_deletion() and s.vitals.is_up() \
				and not s.is_in_group(Soldier.DEAD_GROUP):
			count += 1
	return count


## Host: whether module `module_id`'s garrison has been put in (it streamed in with AI on;
## its posts may all have fallen on an earlier visit, or it may have none). A clear-area
## objective there waits for this (Objectives._garrisoned). True when this session spawns no
## AI (some test fixtures) or there's no such module: nothing will come to wait for.
func garrison_spawned(module_id: String) -> bool:
	return not spawn_ai or get_module(module_id) == null or (_garrisoned.has(module_id) and garrison_pending(module_id) == 0)


## Host: a site taken out (4B part 3): its garrison spawned and none of it is left standing. A
## site nobody has been near yet (never garrisoned) is still up.
func site_down(module_id: String) -> bool:
	return int(_garrisoned.get(module_id, 0)) > 0 and garrison_pending(module_id) == 0 and garrison_alive(module_id) == 0


## Host: a clear spot for an extra garrison post beside the post at `post` (world): the first
## of EXTRA_POST_RINGS_M round it with room for a man (no wall, nobody already put in `taken`)
## and a floor under him at the post's height (a post upstairs or on a roof: never out past the
## wall in mid-air), else the post itself nudged aside.
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
			if not space.intersect_shape(query, 1).is_empty():
				continue
			var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 0.6, 1))
			if not floor_hit.is_empty() and absf((floor_hit.position as Vector3).y - p.y) < 0.5:
				return p
	return post + Vector3(0.9, 0.0, 0.9 * float(taken.size() % 3))


func _player_start(id: int) -> Vector3:
	return player_spawn(id)


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
	if not _garrison_queue.is_empty():
		_spawn_queued_garrison()
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
