class_name Nature
extends Node3D
## The living land of Contractor: Fallen (docs/survival_nature.md; calls 42, 100-107): one node
## "Nature" on every peer at the survival level (SurvivalLevel adds it), the clock and the eyes of
## the fauna and flora layers, which are static and keep their state in Survival.state()["nature"]
## (and the hosted zone's animals in Wildlife.animals):
## - **Wildlife** (wildlife.gd, predators.gd, infected_animals.gd, migration.gd): the host ticks the
##   animals every TICK_S and sends where they are SEND_S apart in one small unreliable packet (like
##   ZoneAnimals); every peer draws them, a MultiMesh per species (NatureArt). Rounds meet a small
##   Area3D per animal on the host (Wildlife.server_shot).
## - **Crows, flies, rats** (scavengers_fauna.gd): the crow flocks over the bodies (sent with the
##   animals, drawn circling, seen far: a tell); the settlement's rats, raccoons and flies by the
##   world hour.
## - **Trees** (trees.gd): felled trees as stumps on every peer (ZoneScatter.redraw_at), regrowth by
##   the world day.
## - **Wildfire** (wildfire.gd): the burning cells, ticked here, drawn as flames and smoke.
## - **Flora** (flora.gd): the regrowth multiplier and the settlement's clear paths, set on every
##   peer before the ground cover is drawn.
## Every number here is Proposed.

const NODE_NAME := "Nature"
const TICK_S := 0.25
const SEND_S := 0.5
const FIRE_TICK_S := 1.0
const SLOW_S := 5.0
const JUMP_H := 12
## Drawn out to (m): the animals, and the crows (a far tell).
const SEE_M := 220.0
const CROW_SEE_M := 700.0
const FIRE_SEE_M := 1200.0

static var _fauna := {}
static var _flora := {}

var level: Node
## Every peer: the animals as last sent [species index, x, y, z, face, alive], the crow sites
## [x, y, z, n], the burning cells [x, z] and the burnt ones.
var shown: Array = []
var crows: PackedFloat32Array = PackedFloat32Array()
var fire: PackedFloat32Array = PackedFloat32Array()
var sent := 0
var received := 0
var _tick := 0.0
var _send := 0.0
var _fire := 0.0
var _slow := 0.0
var _hour := -1
var _day := -1
var _areas: Array[Area3D] = []
var _draw := {}  # species -> MultiMeshInstance3D
var _crow_node: MultiMeshInstance3D
var _fire_node: MultiMeshInstance3D
var _time := 0.0


# --- Data ----------------------------------------------------------------------------------------

static func fauna() -> Dictionary:
	if _fauna.is_empty():
		_fauna = _load("res://data/survival_fauna.json")
	return _fauna


static func flora() -> Dictionary:
	if _flora.is_empty():
		_flora = _load("res://data/survival_flora.json")
	return _flora


static func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Nature: cannot open %s" % path)
		return {}
	var parsed: Variant = ModKit.overlay(path.get_file().get_basename(), JSON.parse_string(f.get_as_text()))  # (mods: docs/fallen_modding.md)
	return parsed if parsed is Dictionary else {}


## The nature section of the world's save.
static func rec() -> Dictionary:
	var st := Survival.state()
	if not st.get("nature") is Dictionary:
		st["nature"] = {}
	return st["nature"]


static func zone() -> String:
	return String(Survival.state().get("zone", ""))


static func of(from: Node) -> Nature:
	var lvl: CompoundLevel = CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NODE_NAME) as Nature if lvl else null


# --- The node ------------------------------------------------------------------------------------

func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	if level == null:
		level = get_parent()
	if DisplayServer.get_name() != "headless":
		_make_visuals()
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_ask_all.rpc_id(1)


func _exit_tree() -> void:
	Flora.reset()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		Wildlife.forget()
		Wildfire.forget()


## Host: the zone's nature set up (Survival.server_level_ready): the animals, the regrowth, the
## stumps, a fire still burning.
func server_setup() -> void:
	Wildlife.server_populate(level)
	Flora.server_apply(level)
	Trees.server_apply(level)


func _process(delta: float) -> void:
	_time += delta
	_draw_all()
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or not Survival.running:
		return
	if Wildlife.zone_id != zone() and not MapNodes.players(level).is_empty():
		server_setup()
		_broadcast_world()
	_tick += delta
	if _tick >= TICK_S:
		var dt := _tick
		_tick = 0.0
		Wildlife.server_tick(level, dt)
		_sync_areas()
	_fire += delta
	if _fire >= FIRE_TICK_S:
		var dt := _fire
		_fire = 0.0
		Wildfire.server_tick(level, dt)
	_slow += delta
	if _slow >= SLOW_S:
		_slow = 0.0
		Wildlife.server_slow(level)
	# The world's hours as they pass, a night's sleep too (a jump of the clock past JUMP_H isn't lived through).
	var h := floori(Moods.now_h())
	if _hour >= 0 and h > _hour and h - _hour <= JUMP_H:
		for k in range(_hour + 1, h + 1):
			Wildlife.server_snare_hours(level, 1.0)
			ScavengersFauna.server_hour(level, posmod(k, 24))
	_hour = h
	var d := Survival.day()
	if _day >= 0 and d > _day:
		Trees.server_regrow(level)
		Flora.server_apply(level)
		_broadcast_world()
	_day = d
	_send += delta
	if _send >= SEND_S:
		_send = 0.0
		_state.rpc(Wildlife.packed(), ScavengersFauna.packed_crows(level), Wildfire.packed())
		sent += 1


# --- Hit boxes (host) ------------------------------------------------------------------------------

## One small Area3D per animal for rounds to meet (layer 1, as ZoneAnimals), moved with it.
func _sync_areas() -> void:
	var list := Wildlife.animals
	while _areas.size() < list.size():
		var i := _areas.size()
		var area := Area3D.new()
		area.name = "Wild%d" % i
		area.collision_layer = 1
		area.collision_mask = 0
		area.monitoring = false
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		area.add_child(shape)
		area.set_meta(&"on_bullet", Wildlife.server_shot.bind(i))
		area.set_meta(&"animal", i)
		add_child(area)
		_areas.append(area)
	for i in _areas.size():
		var area := _areas[i]
		if i >= list.size() or not bool(list[i].alive):
			if area.collision_layer != 0:
				area.collision_layer = 0
			continue
		var a: Dictionary = list[i]
		var size := Wildlife.size_of(a)
		var box := (area.get_child(0) as CollisionShape3D).shape as BoxShape3D
		if not box.size.is_equal_approx(size):
			box.size = size
			(area.get_child(0) as CollisionShape3D).position = Vector3(0, size.y * 0.5, 0)
		area.collision_layer = 1
		var p: Vector2 = a.pos
		area.global_transform = Transform3D(Basis(Vector3.UP, float(a.face)), Vector3(p.x, float(a.get("y", 0.0)), p.y))


# --- The peers' copy ---------------------------------------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered")
func _state(animals: PackedFloat32Array, crow_sites: PackedFloat32Array, fire_cells: PackedFloat32Array) -> void:
	received += 1
	var out: Array = []
	for i in animals.size() / 6:
		out.append([int(animals[i * 6]), animals[i * 6 + 1], animals[i * 6 + 2], animals[i * 6 + 3], animals[i * 6 + 4], animals[i * 6 + 5] > 0.5])
	shown = out
	crows = crow_sites
	fire = fire_cells


@rpc("any_peer", "call_remote", "reliable")
func _ask_all() -> void:
	if not multiplayer.is_server():
		return
	_client_world.rpc_id(multiplayer.get_remote_sender_id(), Flora.grass_now, Flora.road_now, Flora.clear_circles, Trees.felled_list())


func _broadcast_world() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		_client_world.rpc(Flora.grass_now, Flora.road_now, Flora.clear_circles, Trees.felled_list())


## A peer: the regrowth, the clear paths and the felled trees (late joiners too).
@rpc("authority", "call_remote", "reliable")
func _client_world(grass: float, road: float, circles: Array, felled: Array) -> void:
	Flora.set_now(grass, road, circles)
	Trees.client_felled(level, felled)


## Host: a tree felled or grown back, to every peer.
func server_tree(index: int, felled: bool) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_client_tree.rpc(index, felled)


@rpc("authority", "call_remote", "reliable")
func _client_tree(index: int, felled: bool) -> void:
	Trees.client_set(level, index, felled)


# --- Drawing (every peer with a screen) ------------------------------------------------------------------

func _make_visuals() -> void:
	for sp: String in (fauna().get("species", {}) as Dictionary):
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = NatureArt.animal_mesh(sp)
		multi.instance_count = 0
		var node := MultiMeshInstance3D.new()
		node.name = "Wild_" + sp
		node.multimesh = multi
		node.visibility_range_end = SEE_M
		add_child(node)
		_draw[sp] = node
	_crow_node = _multi("Crows", NatureArt.animal_mesh("crow"), CROW_SEE_M)
	_fire_node = _multi("Fire", NatureArt.flame_mesh(), FIRE_SEE_M)


func _multi(n: String, mesh: Mesh, see: float) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = n
	node.multimesh = multi
	node.visibility_range_end = see
	add_child(node)
	return node


func _draw_all() -> void:
	if _draw.is_empty():
		return
	var list: Array = shown
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		list = Wildlife.shown_rows()
	var names: Array = (fauna().get("species", {}) as Dictionary).keys()
	var by := {}
	for row: Array in list:
		var sp := String(names[clampi(int(row[0]), 0, names.size() - 1)])
		if not by.has(sp):
			by[sp] = []
		(by[sp] as Array).append(row)
	for sp: String in _draw:
		var node: MultiMeshInstance3D = _draw[sp]
		var rows: Array = by.get(sp, [])
		if node.multimesh.instance_count != rows.size():
			node.multimesh.instance_count = rows.size()
		for k in rows.size():
			var row: Array = rows[k]
			var basis := Basis(Vector3.UP, float(row[4]))
			var y := float(row[2])
			if not bool(row[5]):
				basis = basis * Basis(Vector3.RIGHT, PI * 0.5)
				y += 0.1
			node.multimesh.set_instance_transform(k, Transform3D(basis, Vector3(float(row[1]), y, float(row[3]))))
	# Crows: a ring of birds circling high over each body (a far tell).
	var c := crows
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		c = ScavengersFauna.packed_crows(level)
	var n := 0
	for i in c.size() / 4:
		n += int(c[i * 4 + 3])
	if _crow_node.multimesh.instance_count != n:
		_crow_node.multimesh.instance_count = n
	var k := 0
	for i in c.size() / 4:
		var centre := Vector3(c[i * 4], c[i * 4 + 1], c[i * 4 + 2])
		var count := int(c[i * 4 + 3])
		for j in count:
			var a := _time * 0.6 + TAU * j / maxf(count, 1.0) + i
			var r := 6.0 + 3.0 * sin(j * 1.7)
			var p := centre + Vector3(cos(a) * r, 18.0 + 4.0 * sin(j * 2.3 + _time * 0.3), sin(a) * r)
			_crow_node.multimesh.set_instance_transform(k, Transform3D(Basis(Vector3.UP, -a), p))
			k += 1
	# Fire: a flame block on each burning cell.
	var f := fire
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		f = Wildfire.packed()
	var burning := f.size() / 3
	if _fire_node.multimesh.instance_count != burning:
		_fire_node.multimesh.instance_count = burning
	for i in burning:
		var flick := 0.8 + 0.4 * absf(sin(_time * 7.0 + i))
		_fire_node.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(Wildfire.CELL_M * 0.8, 2.5 * flick, Wildfire.CELL_M * 0.8)),
			Vector3(f[i * 3], f[i * 3 + 1], f[i * 3 + 2])))
