class_name LhdLevel
extends CompoundLevel
## The company's LHD as a walkable level (docs/lhd_home.md; Captain, 2026-10-20: "the lhd
## functional as thats the players home until they finally take a zone to be their FOB"): the
## home of a new campaign. The hangar deck holds the armory and its stash, the muster line and the
## vehicle park, with the medbay and hiring compartments; stairs lead up to the flight deck, where
## the helicopters stand and the ops room is in the island. Laid out by LhdLayout; the
## terminals, stash and muster line are BaseFob's, with the ship's layout.
##
## It keeps BaseLevel's public face (server_spawn_stash, server_collect_stash, server_deliver,
## server_show_roster, server_read_muster_gear, muster_soldier), so BaseHub drives it like any
## base. Anything aboard is stash (no zone save: the ship's state is the campaign's). Nothing
## hostile, never attacked; deploying is the ops desk's, as at the FOB.

## The voxel world's edit area (voxels) and view distance (voxels): the whole ship, from
## anywhere aboard (VoxelWorld builds once its whole area is loaded).
const VOXEL_BOUNDS := AABB(Vector3(-170, -10, -830), Vector3(340, 290, 1660))
const VOXEL_VIEW := 1800
const SEA := Color("2f4a5c")
const HULL_TOP := Color(0.42, 0.45, 0.48)
const HULL_BOTTOM := Color(0.36, 0.16, 0.14)
const HANGAR_FLOOR := Color("4a4d50")
const PAINT_YELLOW := Color(0.85, 0.78, 0.35)
const PAINT_WHITE := Color(0.85, 0.85, 0.82)

var fob: BaseFob
var _park: Node3D
var _park_models: Array = []


func _enter_tree() -> void:
	# Before the voxel world's own _ready reads them.
	var world := get_node_or_null(^"VoxelWorld") as VoxelWorld
	if world and not world.is_node_ready():
		world.bounds = VOXEL_BOUNDS
		world.view_distance = VOXEL_VIEW


func _ready() -> void:
	super._ready()
	fob = BaseFob.make(self, LhdLayout.FOB_ORIGIN, false, LhdLayout.fob_layout())
	_dress()
	_park = Node3D.new()
	_park.name = "VehiclePark"
	add_child(_park)
	_refresh_park()
	BaseHub.view_changed.connect(_refresh_park)


func is_base() -> bool:
	return true


## Whether the ship's voxels are up (the muster line waits for them).
func fob_ready() -> bool:
	return voxel_world.is_built()


func next_spawn_point() -> Vector3:
	_spawn_index += 1
	return spawn_point(_spawn_index)


func spawn_point(index: int) -> Vector3:
	return fob.spawn_point(index) if fob else LhdLayout.SPAWNS[posmod(index, LhdLayout.SPAWNS.size())]


## What a joining client loads to play here (LevelSwitch).
func level_info() -> Dictionary:
	return {"level": "lhd"}


## The map covers the ship.
func map_area() -> Rect2:
	return LhdLayout.ship_rect().grow(4.0)


## The ground is the hangar deck, the hull's footprint (GroundGuard puts anything lost overboard
## back aboard).
func ground_area() -> Rect2:
	return LhdLayout.ship_rect()


## Host: the ship comes up with the stash, the host's player and the muster line. No zone save,
## no hostiles.
func _on_hosted() -> void:
	GameState.looted.clear()
	GameState.dropped.clear()
	GameState.voxel_edits.clear()
	GameState.bodies.clear()
	GameState.caches.clear()
	server_spawn_stash(BaseHub.stash())
	player_roles[1] = Roles.local_choice
	_add_player(1)
	LhdNav.build_for(self)
	if voxel_world.is_built():
		_on_built()
	else:
		voxel_world.structures_built.connect(_on_built, CONNECT_ONE_SHOT)


func _on_built() -> void:
	server_show_roster()
	BaseHub.server_level_ready(self)


# --- The FOB's public face (BaseFob) ------------------------------------------------------

func server_spawn_stash(stash: Array) -> void:
	fob.server_spawn_stash(stash)


func server_collect_stash() -> Array:
	return fob.server_collect_stash()


func server_deliver(id: StringName, count: int, state := {}) -> void:
	fob.server_deliver(id, count, state)


func server_show_roster() -> void:
	fob.server_show_roster()


func server_read_muster_gear() -> Dictionary:
	return fob.server_read_muster_gear()


func muster_soldier(mid: String) -> Soldier:
	return fob.muster_soldier(mid)


# --- The ship -----------------------------------------------------------------------------

func _build_structures() -> void:
	for b: Array in LhdLayout.boxes():
		voxel_world.add_box_m(b[0], b[1], b[2])


## The sky and sun as every level's (CompoundLevel), but the ground is the hangar deck (the hull's
## footprint, not the compound's pad), with the sea round the ship and the hull below the hangar.
func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	GameSettings.apply_sun(sun)
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var ship := LhdLayout.ship_rect()
	var deck := StaticBody3D.new()
	deck.name = "HangarDeck"
	deck.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ship.size.x, 1.0, ship.size.y)
	shape.shape = box
	shape.position = Vector3(ship.get_center().x, -0.5, ship.get_center().y)
	deck.add_child(shape)
	add_child(deck)
	_paint(self, "HangarFloor", Vector3(LhdLayout.HANGAR.size.x, 0.02, LhdLayout.HANGAR.size.y),
		Vector3(LhdLayout.HANGAR.get_center().x, 0.0, LhdLayout.HANGAR.get_center().y), HANGAR_FLOOR)
	# The hull under the hangar: grey to the waterline, antifouling red under it; the bow narrower.
	var below := -LhdLayout.WATERLINE_Y
	var bow_start := ship.position.y + LhdLayout.BOW_LEN
	var mid_len := ship.end.y - bow_start
	_paint(self, "HullTop", Vector3(ship.size.x - 0.2, below - 0.05, mid_len), Vector3(0, -below * 0.5 - 0.05, bow_start + mid_len * 0.5), HULL_TOP)
	_paint(self, "HullBottom", Vector3(ship.size.x * 0.9, LhdLayout.DRAFT, mid_len), Vector3(0, LhdLayout.WATERLINE_Y - LhdLayout.DRAFT * 0.5, bow_start + mid_len * 0.5), HULL_BOTTOM)
	for i in LhdLayout.BOW_STEPS:
		var half := LhdLayout.HALF_BEAM - (LhdLayout.HALF_BEAM - LhdLayout.BOW_TIP_HALF) * float(i + 1) / LhdLayout.BOW_STEPS
		var step := LhdLayout.BOW_LEN / LhdLayout.BOW_STEPS
		var z := bow_start - (i + 0.5) * step
		_paint(self, "Bow%d" % i, Vector3(half * 2.0 - 0.2, below + LhdLayout.DRAFT * 0.6, step), Vector3(0, -(below + LhdLayout.DRAFT * 0.6) * 0.5 - 0.05, z), HULL_TOP)
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000, 4000)
	var water := StandardMaterial3D.new()
	water.albedo_color = SEA
	water.roughness = 0.25
	water.metallic = 0.1
	plane.material = water
	sea.mesh = plane
	sea.position.y = LhdLayout.WATERLINE_Y
	add_child(sea)


## The ship's paint, lights, signs and parked helicopters (every peer, the same).
func _dress() -> void:
	var dress := Node3D.new()
	dress.name = "Dress"
	add_child(dress)
	var y := LhdLayout.DECK_Y + 0.02
	var ship := LhdLayout.ship_rect()
	# The flight deck: the landing line down the port side, a bar across each spot, the edge lines.
	_paint(dress, "DeckLine", Vector3(0.4, 0.02, ship.size.y - 16.0), Vector3(-6.0, y, 0.0), PAINT_YELLOW)
	for h: Array in LhdLayout.DECK_HELIS:
		var at: Vector3 = h[1]
		_paint(dress, "Spot", Vector3(10.0, 0.02, 0.4), Vector3(at.x, y, at.z + 9.0), PAINT_YELLOW)
		var heli := VehicleArt.prop(String(h[0]))
		heli.name = "Heli_%d" % dress.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with("Heli_")).size()
		heli.position = at
		heli.rotation_degrees.y = float(h[2])
		dress.add_child(heli)
	for side: float in [-1.0, 1.0]:
		_paint(dress, "EdgeLine", Vector3(0.2, 0.02, ship.size.y - 4.0), Vector3(side * (LhdLayout.HALF_BEAM - 0.6), y, 0.0), PAINT_WHITE)
	# The hangar: the vehicle park's bays, a walkway line, lights under the deck and in the compartments.
	var park := LhdLayout.PARK
	for bay: Vector3 in LhdLayout.BAYS:
		for dx: float in [-3.2, 3.2]:
			_paint(dress, "Bay", Vector3(0.15, 0.02, 8.0), Vector3(bay.x + dx, 0.03, bay.z), PAINT_YELLOW)
	_paint(dress, "Walkway", Vector3(0.3, 0.02, park.position.y - LhdLayout.HANGAR.position.y - 4.0),
		Vector3(0.0, 0.03, (LhdLayout.HANGAR.position.y + park.position.y) * 0.5), PAINT_YELLOW)
	var z := LhdLayout.HANGAR.position.y + 8.0
	while z < LhdLayout.HANGAR.end.y:
		_light(dress, Vector3(0.0, LhdLayout.HANGAR_H - 0.6, z), 16.0)
		z += 16.0
	for c: Array in LhdLayout.COMPARTMENTS:
		var r: Rect2 = c[1]
		_light(dress, Vector3(r.get_center().x, LhdLayout.COMPARTMENT_H - 0.4, r.get_center().y), 7.0)
	var isl := LhdLayout.ISLAND
	_light(dress, Vector3(isl.get_center().x, LhdLayout.DECK_Y + 2.6, isl.get_center().y), 8.0)
	# Signs: the stairs, the ops room, the compartments.
	for st: Dictionary in LhdLayout.STAIRS:
		var foot := Vector3((float(st.x[0]) + float(st.x[1])) * 0.5, 2.6, float(st.foot) - int(st.dir) * 0.6)
		_sign(dress, "Flight deck (ops room)", foot)
		var r := LhdLayout.stairwell(st)
		_sign(dress, "Hangar deck", Vector3(r.get_center().x, LhdLayout.DECK_Y + 2.0, r.get_center().y))
	_sign(dress, "Ops room", Vector3(isl.position.x - 0.4, LhdLayout.DECK_Y + 3.0, (float(LhdLayout.OPS_DOOR[0]) + float(LhdLayout.OPS_DOOR[1])) * 0.5))
	_sign(dress, "Armory", Vector3(-11.6, 3.6, LhdLayout.ARMORY.end.y + 0.2))
	_sign(dress, "Medbay", Vector3(11.0, 3.6, LhdLayout.MEDBAY.end.y + 0.2))
	_sign(dress, "Hiring", Vector3(LhdLayout.HIRING.position.x - 0.2, 3.6, -18.5))
	_sign(dress, "Vehicle park", Vector3(0.0, 4.0, park.position.y))


## Every peer: the motor pool's vehicles (the base screen's view, "pool_models") parked in the
## bays as props, one a bay.
func _refresh_park() -> void:
	var models: Array = BaseHub.view.get("pool_models", [])
	if models == _park_models or _park == null:
		return
	_park_models = models.duplicate()
	for n in _park.get_children():
		n.queue_free()
	for i in mini(models.size(), LhdLayout.BAYS.size()):
		var model := String(models[i])
		if not VehicleArt.MODELS.has(model):
			continue
		var prop := VehicleArt.prop(model)
		prop.position = LhdLayout.BAYS[i]
		_park.add_child(prop)


static func _paint(parent: Node3D, node_name: String, size: Vector3, at: Vector3, colour: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.9
	box.material = m
	mesh.mesh = box
	mesh.position = at
	parent.add_child(mesh)


static func _light(parent: Node3D, at: Vector3, reach: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.omni_range = reach
	light.light_energy = 1.2
	light.light_color = Color(1.0, 0.95, 0.85)
	parent.add_child(light)


static func _sign(parent: Node3D, text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 56
	label.pixel_size = 0.005
	label.position = at
	parent.add_child(label)
