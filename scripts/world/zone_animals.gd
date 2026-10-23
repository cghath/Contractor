class_name ZoneAnimals
extends Node3D
## The zone's animals (cghath's queue item 1.7): goats, sheep and dogs with no AI beyond wandering
## about their home (a pen's inside, round a farm or a village, a town's main street), from
## ZoneScatter's ANIMAL markers. Every peer starts them in the same places (seeded by the marker),
## then the host walks them and sends where they are to every peer SEND_S apart, all of them in one
## small unreliable packet, and the peers glide them there (late joiners too: the next packet puts
## them right). A round that hits one kills it: it lies down on every peer.
##
## Cheap: at most CAP, one MultiMesh per species and coat (none on a headless server), no physics
## but a small Area3D each on the host for rounds to hit (layer 1: rounds meet it, but sight lines
## and men don't, Throwables.clear_line and movement ignore areas), and one ray when an animal
## picks where to go next, so it doesn't walk through a fence, a car or a wall.

const CAP := 64
## Seconds between the host's packets (Proposed).
const SEND_S := 0.25
## Walking speed (m/s), and the pause at each spot [min, max] (s). Proposed.
const SPEED := {"sheep": 0.55, "goat": 0.75, "dog": 1.4}
const WAIT_S := Vector2(2.0, 9.0)
## A walk is clear when a ray this high over the ground meets nothing (m).
const LOOK_M := 0.4
## Rounds meet this box round each (m, its own x z: length, height, width).
const HIT_BOX := {"sheep": Vector3(0.95, 0.6, 0.55), "goat": Vector3(0.85, 0.55, 0.38), "dog": Vector3(0.75, 0.45, 0.28)}
## Drawn out to this far (m).
const SEE_M := 160.0

## Each: {"species", "home" ({"c" (Vector2), "half" (Vector2), "yaw"}), "pos" (Vector2), "face"
## (yaw), "target" (Vector2), "wait" (s), "alive", "coat" (paint index), "show" (Vector2: drawn),
## "show_face"}.
var animals: Array[Dictionary] = []
## Packets the host sent and a peer took (for tests).
var sent := 0
var received := 0
var _terrain: ZoneTerrain
var _rng := RandomNumberGenerator.new()
var _send_in := 0.0
var _groups := {}  # "species#coat" -> [MultiMeshInstance3D, [animal indices]]
var _areas: Array[Area3D] = []
var _moved := PackedByteArray()  # per animal: walked this tick (its hit box follows)
var _still := PackedByteArray()  # per animal: drawn where it stands, nothing to glide (_place_all)
var _time := 0.0


## Lays the animals out from `scatter`'s ANIMAL markers on `terrain`.
func setup(scatter: ZoneScatter, terrain: ZoneTerrain) -> void:
	name = "Animals"
	_terrain = terrain
	_rng.seed = terrain.seed_value ^ 0xA41A
	for item: Dictionary in scatter.items:
		if int(item.kind) != ZoneScatter.Kind.ANIMAL:
			continue
		var p: Vector3 = item.pos
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(roundi(p.x * 10.0), roundi(p.z * 10.0), terrain.seed_value))
		var species := String(item.shape)
		var home := {"c": Vector2(p.x, p.z), "half": Vector2((item.size as Vector3).x, (item.size as Vector3).z), "yaw": float(item.yaw)}
		for k in int(item.paint):
			if animals.size() >= CAP:
				break
			var at := _in_home(home, rng)
			var face := rng.randf() * TAU
			animals.append({"species": species, "home": home, "pos": at, "face": face, "target": at, "wait": rng.randf_range(0.0, WAIT_S.y),
				"alive": true, "coat": rng.randi() % maxi(PropArt.paints(species).size(), 1), "show": at, "show_face": face})


func _ready() -> void:
	_moved.resize(animals.size())
	_moved.fill(1)
	_still.resize(animals.size())
	if multiplayer.is_server():
		for i in animals.size():
			var a := animals[i]
			var area := Area3D.new()
			area.name = "Animal%d" % i
			area.collision_layer = 1
			area.collision_mask = 0
			area.monitoring = false
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = HIT_BOX.get(a.species, Vector3(0.8, 0.5, 0.4))
			shape.shape = box
			shape.position = Vector3(0, box.size.y * 0.5 + 0.3, 0)
			area.add_child(shape)
			area.set_meta(&"on_bullet", _shot.bind(i))
			area.set_meta(&"animal", i)
			add_child(area)
			_areas.append(area)
	if DisplayServer.get_name() != "headless":
		for i in animals.size():
			var key := "%s#%d" % [animals[i].species, animals[i].coat]
			if not _groups.has(key):
				_groups[key] = [null, []]
			(_groups[key][1] as Array).append(i)
		for key: String in _groups:
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.use_colors = true
			multi.mesh = PropArt.mesh(key.get_slice("#", 0), int(key.get_slice("#", 1)))
			multi.instance_count = (_groups[key][1] as Array).size()
			for k in multi.instance_count:
				multi.set_instance_color(k, Color.WHITE)
			var node := MultiMeshInstance3D.new()
			node.name = "Herd_" + key.replace("#", "_")
			node.multimesh = multi
			node.material_override = ZoneScatter._shared_material_once()
			node.visibility_range_end = SEE_M
			add_child(node)
			_groups[key][0] = node
	_place_all()


## A random spot in `home`'s rectangle.
static func _in_home(home: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	var h: Vector2 = home.half
	var local := Vector2(rng.randf_range(-h.x, h.x), rng.randf_range(-h.y, h.y))
	return (home.c as Vector2) + ZoneProps._to_world(local, float(home.yaw))


func _physics_process(delta: float) -> void:
	_time += delta
	if not multiplayer.is_server() or animals.is_empty():
		return
	for i in animals.size():
		var a := animals[i]
		if not a.alive:
			continue
		if float(a.wait) > 0.0:
			a.wait = float(a.wait) - delta
			if float(a.wait) <= 0.0:
				a.target = _next_spot(a)
			continue
		var to: Vector2 = (a.target as Vector2) - (a.pos as Vector2)
		var step := float(SPEED.get(a.species, 0.7)) * delta
		if to.length() <= step:
			a.pos = a.target
			a.wait = _rng.randf_range(WAIT_S.x, WAIT_S.y)
		else:
			a.pos = (a.pos as Vector2) + to.normalized() * step
			a.face = lerp_angle(float(a.face), atan2(-to.y, to.x), minf(delta * 4.0, 1.0))
		_moved[i] = true
	_send_in -= delta
	if _send_in <= 0.0:
		_send_in = SEND_S
		_state.rpc(_packed())
		sent += 1
	# Perf (world content pass, 2026-10-23): only the hit boxes of animals that moved this tick
	# (most stand grazing; every area moved every tick was ~1 ms a tick in a city).
	for i in _areas.size():
		if not _moved[i]:
			continue
		_moved[i] = false
		var a := animals[i]
		var p: Vector2 = a.pos
		_areas[i].global_transform = Transform3D(Basis(Vector3.UP, float(a.face)), Vector3(p.x, _terrain.height_at(p.x, p.y), p.y))


## Where `a` walks next: a spot in its home with nothing solid on the way (a few tries; else it
## stays put a while longer).
func _next_spot(a: Dictionary) -> Vector2:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	var from: Vector2 = a.pos
	for k in 4:
		var q := _in_home(a.home, _rng)
		if space == null:
			return q
		var y0 := _terrain.height_at(from.x, from.y) + LOOK_M
		var y1 := _terrain.height_at(q.x, q.y) + LOOK_M
		var query := PhysicsRayQueryParameters3D.create(Vector3(from.x, y0, from.y), Vector3(q.x, y1, q.y), 1)
		if space.intersect_ray(query).is_empty():
			return q
	a.wait = _rng.randf_range(WAIT_S.x, WAIT_S.y)
	return from


## Every animal's x, z, facing and whether it's alive, in one array.
func _packed() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(animals.size() * 4)
	for i in animals.size():
		var a := animals[i]
		out[i * 4] = (a.pos as Vector2).x
		out[i * 4 + 1] = (a.pos as Vector2).y
		out[i * 4 + 2] = float(a.face)
		out[i * 4 + 3] = 1.0 if a.alive else 0.0
	return out


@rpc("authority", "call_remote", "unreliable_ordered")
func _state(data: PackedFloat32Array) -> void:
	received += 1
	for i in mini(data.size() / 4, animals.size()):
		var a := animals[i]
		a.pos = Vector2(data[i * 4], data[i * 4 + 1])
		a.face = data[i * 4 + 2]
		a.alive = data[i * 4 + 3] > 0.5


## Host: a round hit animal `index` (Ballistics' "on_bullet"): it dies, on every peer.
func _shot(_at: Vector3, _shooter: Node, index: int) -> void:
	if index < 0 or index >= animals.size() or not animals[index].alive:
		return
	animals[index].alive = false
	if index < _areas.size():
		_areas[index].collision_layer = 0
	_died.rpc(index)


@rpc("authority", "call_remote", "reliable")
func _died(index: int) -> void:
	if index >= 0 and index < animals.size():
		animals[index].alive = false


## How many are alive (for tests).
func alive_count() -> int:
	return animals.filter(func(a: Dictionary) -> bool: return a.alive).size()


func _process(delta: float) -> void:
	_place_all(delta)


## Glides each drawn animal toward where it is (a peer's lag between packets), a little bob as it
## walks, lying on its side once dead.
func _place_all(delta := 1.0) -> void:
	var blend := 1.0 - exp(-delta * 6.0)
	for i in animals.size():
		var a := animals[i]
		var before: Vector2 = a.show
		a.show = before.lerp(a.pos, blend)
		a.show_face = lerp_angle(float(a.show_face), float(a.face), blend)
	if _groups.is_empty():
		return
	for key: String in _groups:
		var node: MultiMeshInstance3D = _groups[key][0]
		var list: Array = _groups[key][1]
		for k in list.size():
			var index := int(list[k])
			var a := animals[index]
			# Perf (world content pass, 2026-10-23): one standing still, drawn there already, is left be.
			var settled := float(a.wait) > 0.0 and (a.show as Vector2).distance_squared_to(a.pos) < 1e-6 \
				and absf(angle_difference(float(a.show_face), float(a.face))) < 1e-3
			var state := (1 if a.alive else 2) if settled else 0
			if state != 0 and _still[index] == state:
				continue
			_still[index] = state
			var p: Vector2 = a.show
			var y := _terrain.height_at(p.x, p.y)
			var basis := Basis(Vector3.UP, float(a.show_face))
			if not a.alive:
				basis = basis * Basis(Vector3.RIGHT, PI * 0.5)
				y += 0.12
			elif (a.show as Vector2).distance_to(a.pos) > 0.05 or float(a.wait) <= 0.0:
				y += absf(sin(_time * 9.0 + int(list[k]))) * 0.03
			node.multimesh.set_instance_transform(k, Transform3D(basis, Vector3(p.x, y, p.y)))
