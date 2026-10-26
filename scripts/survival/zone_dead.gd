class_name ZoneDead
extends Node3D
## The far tier of the dead (docs/survival.md S3; survival_world.md section 5): the crowd. Hundreds
## of the dead a zone can hold cost almost nothing here: a record each (x, z, facing, kind, alive),
## the host walking them every physics frame toward the zone's pressure point (the loudest recent
## noise: Survival.pressure_point) or about where they stand, one small unreliable packet every
## SEND_S to the peers, and one MultiMesh per kind of a cheap stand-in (VoxelArt "crowd_zombie").
## Like ZoneAnimals. On every peer at the level's "Dead" path (SurvivalLevel).
##
## The two tiers trade: a crowd member that comes within LIVE_M of a player becomes a body
## (Survival.server_spawn_zombie, under LIVE_CAP) and leaves the crowd; a body past DESPAWN_M of
## everyone and not chasing goes back into the crowd where it stood (Survival._populate). A
## **horde** (Survival: the zone's pressure at HORDE_AT) is HORDE_N of the crowd put down
## HORDE_FROM_M to HORDE_TO_M from the pressure point and walked at it; when the pressure falls
## under HORDE_DISPERSE_AT the horde wanders and thins (THIN_S a head) back to the zone's quiet.

const CAP := 400
const SEND_S := 0.5
const LIVE_M := 70.0
const WALK_MPS := 0.9      # a walker's shuffle toward the noise
const DRIFT_MPS := 0.35    # about its spot, nowhere in particular
const DRIFT_M := 12.0
const HORDE_N := Vector2i(30, 60)
const HORDE_FROM_M := 150.0
const HORDE_TO_M := 250.0
const THIN_S := 20.0
const SEE_M := 220.0
const WAIT_S := Vector2(3.0, 12.0)
const CONVERT_TICK_S := 1.0

var dead: Array[Dictionary] = []  # {"pos": Vector2, "face", "kind", "alive", "target": Vector2, "wait", "horde", "show", "show_face"}
var horde_until := -1.0
var sent := 0
var received := 0
var _terrain: ZoneTerrain
var _rng := RandomNumberGenerator.new()
var _send_in := 0.0
var _convert_in := 0.0
var _thin_in := 0.0
var _groups := {}  # kind -> [MultiMeshInstance3D, [indices]]
var _time := 0.0


static func of(level: Node) -> ZoneDead:
	return level.get_node_or_null(^"Dead") as ZoneDead if level else null


func _ready() -> void:
	name = "Dead"
	var level := get_parent() as ZoneLevel
	_terrain = level.terrain if level else null
	_rng.seed = hash("dead|" + String(get_parent().name))
	if DisplayServer.get_name() != "headless":
		for kind: String in ["walker", "runner", "screamer", "crawler", "bloater", "hazmat"]:
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = VoxelArt.far_mesh("crowd_zombie:" + kind, "multicam")
			multi.instance_count = 0
			var node := MultiMeshInstance3D.new()
			node.name = "Crowd_" + kind
			node.multimesh = multi
			node.visibility_range_end = SEE_M
			add_child(node)
			_groups[kind] = [node, []]


## Host: one more of the crowd at `pos` (world), of `kind`; in a horde if `horde`. False when full.
func server_add(pos: Vector3, kind := "walker", horde := false) -> bool:
	if dead.size() >= CAP:
		return false
	var at := Vector2(pos.x, pos.z)
	dead.append({"pos": at, "face": _rng.randf() * TAU, "kind": kind, "alive": true, "target": at,
		"wait": _rng.randf_range(0.0, WAIT_S.y), "horde": horde, "show": at, "show_face": 0.0})
	return true


## Host: a horde of `n` of the crowd, HORDE_FROM_M to HORDE_TO_M from `at`, walking at it.
func server_horde(at: Vector3, n: int) -> int:
	var made := 0
	var a0 := _rng.randf() * TAU
	for i in n:
		var a := a0 + _rng.randf_range(-0.6, 0.6)
		var r := _rng.randf_range(HORDE_FROM_M, HORDE_TO_M)
		var pos := at + Vector3(cos(a), 0.0, sin(a)) * r
		var kind := "runner" if _rng.randf() < 0.1 else "walker"
		if server_add(pos, kind, true):
			dead[dead.size() - 1].target = Vector2(at.x, at.z)
			dead[dead.size() - 1].wait = 0.0
			made += 1
	horde_until = Soldier._now() + 600.0
	return made


## How many stand in the crowd (alive).
func count() -> int:
	return dead.filter(func(d: Dictionary) -> bool: return d.alive).size()


func horde_count() -> int:
	return dead.filter(func(d: Dictionary) -> bool: return d.alive and d.horde).size()


func _physics_process(delta: float) -> void:
	_time += delta
	if not multiplayer.is_server() or dead.is_empty():
		return
	var level := get_parent()
	var point: Variant = Survival.pressure_point(level)
	var pressure := Survival.pressure(level)
	var pull: Vector2 = Vector2(point.x, point.z) if point is Vector3 else Vector2.INF
	for i in dead.size():
		var d := dead[i]
		if not d.alive:
			continue
		if bool(d.get("frozen", false)):
			continue  # (phase D: frozen solid in a hard frost: Seasons; the thaw wakes them)
		var pos: Vector2 = d.pos
		if float(d.wait) > 0.0:
			d.wait = float(d.wait) - delta
			if float(d.wait) <= 0.0:
				if d.has("to"):
					d.target = d.to  # (phase D: a siege's wave walks at the settlement: Sieges)
				elif bool(d.horde) and pull != Vector2.INF and pressure >= Survival.HORDE_DISPERSE_AT:
					d.target = pull
				elif pull != Vector2.INF and pressure >= Survival.DRIFT_AT and pos.distance_to(pull) > 20.0:
					d.target = pos + (pull - pos).normalized() * minf(DRIFT_M, pos.distance_to(pull))  # drifts toward the noise
				else:
					var a := _rng.randf() * TAU
					d.target = pos + Vector2(cos(a), sin(a)) * _rng.randf_range(2.0, DRIFT_M)
			continue
		var to: Vector2 = (d.target as Vector2) - pos
		var speed := (WALK_MPS if bool(d.horde) else DRIFT_MPS) * Seasons.dead_pace_mult()
		var step := speed * delta
		if to.length() <= step:
			d.pos = d.target
			d.wait = _rng.randf_range(WAIT_S.x, WAIT_S.y) * (0.2 if bool(d.horde) else 1.0)
		else:
			d.pos = pos + to.normalized() * step
			d.face = lerp_angle(float(d.face), atan2(-to.y, to.x), minf(delta * 4.0, 1.0))
	_convert_in -= delta
	if _convert_in <= 0.0:
		_convert_in = CONVERT_TICK_S
		_convert(level)
	_thin_in -= delta
	if _thin_in <= 0.0:
		_thin_in = THIN_S
		if horde_count() > 0 and pressure < Survival.HORDE_DISPERSE_AT:
			_thin_horde()
	_send_in -= delta
	if _send_in <= 0.0:
		_send_in = SEND_S
		_state.rpc(_packed())
		sent += 1


## Host: crowd members within LIVE_M of a player become bodies (the live tier), while there's room.
func _convert(level: Node) -> void:
	var players := MapNodes.players(level).filter(func(p: Soldier) -> bool: return p.vitals.is_up())
	if players.is_empty():
		return
	var live := Survival.zombies(level).size()
	var i := 0
	while i < dead.size():
		var d := dead[i]
		if not d.alive:
			i += 1
			continue
		var pos: Vector2 = d.pos
		var near := players.any(func(p: Soldier) -> bool: return Vector2(p.global_position.x, p.global_position.z).distance_to(pos) <= LIVE_M)
		if near and live < Survival.LIVE_CAP:
			var y := _terrain.height_at(pos.x, pos.y) if _terrain else 0.0
			var z := Survival.server_spawn_zombie(level, Vector3(pos.x, y, pos.y), String(d.kind))
			if z and bool(d.get("frozen", false)):
				Seasons.freeze(z)  # (still frozen up close)
			if z:
				if bool(d.horde):
					var brain := ZombieAI.of(z)
					if brain:
						var point: Variant = Survival.pressure_point(level)
						if point is Vector3:
							brain.hear(point, ZombieAI.HEAR_RUN)
				live += 1
				dead.remove_at(i)
				continue
		i += 1


## Host: a horde that has nothing to go to thins out, a head at a time (back into the zone's quiet).
func _thin_horde() -> void:
	for i in dead.size():
		if bool(dead[i].horde) and dead[i].alive:
			dead.remove_at(i)
			return


## Every head's x, z, facing, kind and whether it stands, in one array.
const KIND_IDS := {"walker": 0.0, "runner": 1.0, "screamer": 2.0, "crawler": 3.0, "bloater": 4.0, "hazmat": 5.0}
const KIND_NAMES := ["walker", "runner", "screamer", "crawler", "bloater", "hazmat"]


func _packed() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(dead.size() * 5)
	for i in dead.size():
		var d := dead[i]
		out[i * 5] = (d.pos as Vector2).x
		out[i * 5 + 1] = (d.pos as Vector2).y
		out[i * 5 + 2] = float(d.face)
		out[i * 5 + 3] = float(KIND_IDS.get(d.kind, 0.0))
		out[i * 5 + 4] = 1.0 if d.alive else 0.0
	return out


@rpc("authority", "call_remote", "unreliable_ordered")
func _state(data: PackedFloat32Array) -> void:
	received += 1
	var n := data.size() / 5
	while dead.size() < n:
		dead.append({"pos": Vector2.ZERO, "face": 0.0, "kind": "walker", "alive": true, "target": Vector2.ZERO, "wait": 0.0, "horde": false, "show": Vector2.INF, "show_face": 0.0})
	while dead.size() > n:
		dead.pop_back()
	for i in n:
		var d := dead[i]
		d.pos = Vector2(data[i * 5], data[i * 5 + 1])
		d.face = data[i * 5 + 2]
		d.kind = KIND_NAMES[clampi(int(data[i * 5 + 3]), 0, KIND_NAMES.size() - 1)]
		d.alive = data[i * 5 + 4] > 0.5
		if d.show == Vector2.INF:
			d.show = d.pos


func _process(delta: float) -> void:
	if _groups.is_empty():
		return
	var blend := 1.0 - exp(-delta * 6.0)
	var counts := {}
	for d in dead:
		if d.show == Vector2.INF:
			d.show = d.pos
		d.show = (d.show as Vector2).lerp(d.pos, blend)
		d.show_face = lerp_angle(float(d.show_face), float(d.face), blend)
		counts[d.kind] = int(counts.get(d.kind, 0)) + (1 if d.alive else 0)
	for kind: String in _groups:
		var node: MultiMeshInstance3D = _groups[kind][0]
		var want := int(counts.get(kind, 0))
		if node.multimesh.instance_count != want:
			node.multimesh.instance_count = want
		var k := 0
		for d in dead:
			if d.kind != kind or not d.alive:
				continue
			var p: Vector2 = d.show
			var y := _terrain.height_at(p.x, p.y) if _terrain else 0.0
			y += absf(sin(_time * 2.2 + k)) * 0.04
			node.multimesh.set_instance_transform(k, Transform3D(Basis(Vector3.UP, float(d.show_face)), Vector3(p.x, y, p.y)))
			k += 1
