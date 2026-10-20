class_name BlastGore
extends RefCounted
## What blasts, heavy rounds and vehicles do to a body's shape (Captain, 2026-10-20: "more
## realistic dismemberment and body wounds on the voxel characters"), host only. The wounds
## themselves stay the wound model's (Throwables, Warheads, Vitals); this decides the gore that
## goes with them and records it on the body (Vitals.server_gore_add: WoundModel.gore, replicated
## in net_state), where BodyDeform carves it on every peer, late joiners and saved bodies alike.
##
## By the scaled distance of each part from the burst (metres over the cube root of the filling in
## kg of TNT, Hopkinson; a frag grenade is 0.2 kg, an RPG-7's PG-7V 1 kg):
## - GIB_Z from the centre of mass, or a direct hit by a filling of GIB_DIRECT_KG or more: the
##   body comes apart (head, arms and legs off, the torso blown open) and he's dead.
## - SEVER_Z from a limb: it's torn off. The Captain's rule (body_deform.gd's header): alive, only
##   what can still be treated: a shin or forearm off (Vitals.server_amputate: the arterial bleed a
##   tourniquet stops), a thigh or upper arm left hanging by tissue (an amputation too, it bleeds
##   the same); never the head. Dead (or killed by this blast): the whole limb or the head goes.
## - MANGLE_Z: a big torn crater facing the burst on each part in reach.
## - CHAR_Z: the side facing it scorched.
## - Within PEPPER_SHARE of the fragment reach, with a clear line: small fragment pocks peppering
##   the parts facing it, more up close (cosmetic: the fragment wounds are Throwables'/Warheads').
## A .50 (Vitals.LETHAL_J) takes the limb or head it hits; a heavy vehicle driving over a body
## crushes what it rolls over; one hitting a man hard tears the side it hit.
## All Proposed numbers.

const GIB_Z := 0.6
const GIB_DIRECT_KG := 0.3
const SEVER_Z := 0.55
const MANGLE_Z := 1.0
const CHAR_Z := 1.6
const PEPPER_SHARE := 0.5
const PEPPER_MAX := 12
## A blast-torn piece flies off at this speed (m/s), from the edge of SEVER_Z to point-blank,
## plus LAUNCH_UP; a .50's at HEAVY_LAUNCH.
const LAUNCH := Vector2(3.0, 8.0)
const LAUNCH_UP := 2.0
const HEAVY_LAUNCH := 3.5
## Gore entries one body keeps (severs always fit: the oldest crater, pepper or char goes).
const MAX_ENTRIES := 48
## Vehicles: a body run over by more than CRUSH_KG at CRUSH_MS or more is crushed where the wheels
## go (dead: the head pulped under one of HEAD_CRUSH_KG); one hit standing at MANGLE_MS or more
## is torn on the side it hit. Once per body and part every CRUSH_COOLDOWN_S.
const CRUSH_KG := 1200.0
const HEAD_CRUSH_KG := 2500.0
const CRUSH_MS := 2.5
const MANGLE_MS := 12.0
const CRUSH_COOLDOWN_S := 2.0
## Ragdoll part name -> the body part under it (Vehicle._ride_over meets ragdoll parts).
const RAGDOLL_PART := {"torso": Vitals.CHEST, "head": Vitals.HEAD, "leg_l": Vitals.THIGH_L, "leg_r": Vitals.THIGH_R,
	"shin_l": Vitals.SHIN_L, "shin_r": Vitals.SHIN_R, "arm_l": Vitals.UPPER_ARM_L, "arm_r": Vitals.UPPER_ARM_R,
	"fore_l": Vitals.FOREARM_L, "fore_r": Vitals.FOREARM_R}
const DISTAL: Array[StringName] = [Vitals.SHIN_L, Vitals.SHIN_R, Vitals.FOREARM_L, Vitals.FOREARM_R]
## Each limb chain, distal first: [shin, thigh] etc.
const CHAINS := [[Vitals.SHIN_L, Vitals.THIGH_L], [Vitals.SHIN_R, Vitals.THIGH_R],
	[Vitals.FOREARM_L, Vitals.UPPER_ARM_L], [Vitals.FOREARM_R, Vitals.UPPER_ARM_R]]
const TORSO_PARTS: Array[StringName] = [Vitals.CHEST, Vitals.ABDOMEN, Vitals.PELVIS]

static var _crushed := {}  # "<body id>:<part>" -> when (Soldier._now)


## A Vector3 as a short array for net_state and saves (to `step` metres).
static func vec(v: Vector3, step := 0.005) -> Array:
	return [snappedf(v.x, step), snappedf(v.y, step), snappedf(v.z, step)]


static func to_vec(a: Variant) -> Variant:
	if a is Array and (a as Array).size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return null


## Every body a blast can tear: the living (combatants) and the dead lying about.
static func bodies(tree: SceneTree) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var seen := {}
	for n: Node in tree.get_nodes_in_group(&"combatants") + tree.get_nodes_in_group(Soldier.DEAD_GROUP):
		if n is Node3D and not seen.has(n) and not n.is_queued_for_deletion() and n.get_node_or_null(^"Vitals") is Vitals:
			seen[n] = true
			out.append(n as Node3D)
	return out


## Host only. A burst of `kg` of TNT at `centre` with fragments reaching `frag_m`: the gore on every
## body near enough (not `skip`, nor anyone inside a vehicle's hull). Run after the burst's wounds,
## so a body it killed takes the dead rules. Returns {body: [entries added]} (tests).
static func server_blast(level: Node, centre: Vector3, kg: float, frag_m: float, skip: Array = []) -> Dictionary:
	var out := {}
	if level == null or not level.is_inside_tree() or kg <= 0.0:
		return out
	var kg3 := pow(kg, 1.0 / 3.0)
	var reach := maxf(CHAR_Z * kg3 + 0.6, frag_m * PEPPER_SHARE)
	var aboard := Warheads.vehicle_occupants(level.get_tree())
	var world: World3D = (level as Node3D).get_world_3d()
	for body in bodies(level.get_tree()):
		if body in skip or aboard.has(body):
			continue
		var vitals := body.get_node(^"Vitals") as Vitals
		if Throwables.body_point(body).distance_to(centre) > reach + 1.2:
			continue
		var added := _blast_body(body, vitals, world, centre, kg3, frag_m)
		if not added.is_empty():
			out[body] = added
	return out


## Host only. A warhead of `kg` going off on `body` itself (Warheads._direct_hit, after its wounds
## and the kill): a big filling gibs him, a small one (or a jet) tears off the part it struck.
static func server_direct(body: Node3D, part: StringName, pos: Vector3, dir: Vector3, kg: float) -> void:
	var vitals := body.get_node_or_null(^"Vitals") as Vitals
	if vitals == null:
		return
	var world := body.get_world_3d()
	if kg >= GIB_DIRECT_KG:
		var entries := _gib(body, vitals, world, pos - dir.normalized() * 0.1, maxf(pow(kg, 1.0 / 3.0), 0.5))
		_add(vitals, entries)
		return
	var hitbox := _hitbox(body, part)
	var bone := BodyDeform._bone_part(part)
	if hitbox and (bone in BodyDeform.LIMBS or bone == Vitals.HEAD):
		var rest := _to_rest(hitbox) * pos
		_add(vitals, [_sever(bone, rest, dir.normalized() * HEAVY_LAUNCH + Vector3.UP, hash(body.name) + 31)])


## Host only. A .50-class round (Vitals.LETHAL_J) hit `part` of `vitals`' body at rest-pose `at`,
## flying along `dir` (rest pose): a limb or the head comes off, the torso is torn wide open. It
## kills (Vitals.server_hit), so the dead rules; sent with the kill or the corpse's next publish.
static func server_heavy_hit(vitals: Vitals, part: StringName, at: Vector3, dir: Vector3) -> void:
	var body := vitals.get_parent() as Node3D
	var bone := BodyDeform._bone_part(part)
	var entries: Array = []
	if bone in BodyDeform.LIMBS or bone == Vitals.HEAD:
		var launch := dir.normalized() * HEAVY_LAUNCH
		if body and body.is_inside_tree():
			launch = body.global_basis * launch
		entries.append(_sever(bone, at, launch + Vector3.UP * 0.8, hash("%s%s" % [part, at])))
	else:
		entries.append({"k": "c", "p": String(part), "a": vec(at + dir.normalized() * 0.12), "r": 2.4})
	for e: Dictionary in entries:
		_add_one(vitals, e, false)


## Host only. A vehicle of `mass` kg drove over `body`'s ragdoll part `ragdoll_part` at `speed`
## m/s (Vehicle._ride_over): crushed where it rolled. Dead, a heavy one pulps the head; alive
## (downed), what a weight on him breaks (Vitals.server_fall) and the flattened limb.
static func server_crush(body: Node3D, ragdoll_part: String, mass: float, speed: float) -> void:
	var vitals := body.get_node_or_null(^"Vitals") as Vitals if body else null
	if vitals == null or mass < CRUSH_KG or speed < CRUSH_MS:
		return
	var part: StringName = RAGDOLL_PART.get(ragdoll_part, &"")
	if part == &"":
		return
	var key := "%d:%s" % [body.get_instance_id(), part]
	var now := Soldier._now()
	if now - float(_crushed.get(key, -100.0)) < CRUSH_COOLDOWN_S:
		return
	_crushed[key] = now
	var hitbox := _hitbox(body, part)
	var centre: Vector3 = BodyMap.PART_BOXES[part][0][0] if BodyMap.PART_BOXES.has(part) else Vector3(0, 1.2, 0)
	if hitbox:
		# The side the wheel came down on: up in the world, in the part's rest frame.
		var up := (_to_rest(hitbox).basis * Vector3.UP).normalized()
		centre += up * 0.08
	var entries: Array = []
	if vitals.is_dead() and part == Vitals.HEAD and mass >= HEAD_CRUSH_KG:
		entries.append({"k": "s", "p": String(Vitals.HEAD), "a": vec(centre), "np": true})
	else:
		entries.append({"k": "c", "p": String(part), "a": vec(centre), "r": 1.6 if vitals.is_dead() else 1.1})
	if not vitals.is_dead():
		vitals.server_fall(1.5 + speed * 0.4)  # crushed: what a fall breaks
	_add(vitals, entries)


## Host only. A vehicle hit `body` standing at `speed` m/s coming from `from` (world): past
## MANGLE_MS the side it hit is torn (two or three parts facing it).
static func server_vehicle_hit(body: Node3D, from: Vector3, speed: float) -> void:
	var vitals := body.get_node_or_null(^"Vitals") as Vitals if body else null
	if vitals == null or speed < MANGLE_MS:
		return
	var entries: Array = []
	var near: Array = []
	for hitbox in _hitboxes(body):
		near.append([_nearest(hitbox, from).distance_to(from), hitbox])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(3, near.size()):
		var hitbox: Area3D = near[i][1]
		var p := _nearest(hitbox, from)
		entries.append({"k": "c", "p": String(hitbox.get_meta(&"body_part")), "a": vec(_to_rest(hitbox) * p), "r": clampf(speed / 10.0, 1.2, 2.4)})
	_add(vitals, entries)


# --- One body ------------------------------------------------------------------------------

static func _blast_body(body: Node3D, vitals: Vitals, world: World3D, centre: Vector3, kg3: float, frag_m: float) -> Array:
	var com := Throwables.body_point(body)
	if com.distance_to(centre) / kg3 < GIB_Z and Throwables.clear_line(world, centre, com):
		var gib := _gib(body, vitals, world, centre, kg3)
		_add(vitals, gib)
		return gib
	var dead := vitals.is_dead()
	var entries: Array = []
	var parts := {}  # part -> [hitbox, nearest world point, scaled distance, clear line]
	for hitbox in _hitboxes(body):
		var part: StringName = hitbox.get_meta(&"body_part")
		var p := _nearest(hitbox, centre)
		var clear := Throwables.clear_line(world, centre, p) and _exposed(world, centre, p)
		parts[part] = [hitbox, p, p.distance_to(centre) / kg3, clear]
	var gone := {}
	for part in BodyDeform.severed_parts(vitals):
		gone[part] = true
	var amputate := {}  # alive: part -> rest point, made after the gore goes out (a hanging limb's "d" first)
	# Limbs torn off or left hanging, one cut per arm or leg (the nearest of its two parts).
	for chain: Array in CHAINS:
		var distal: StringName = chain[0]
		var proximal: StringName = chain[1]
		if gone.has(proximal) or gone.has(distal):
			continue
		var d_in := _in_reach(parts, distal, SEVER_Z)
		var p_in := _in_reach(parts, proximal, SEVER_Z)
		if not d_in and not p_in:
			continue
		if dead:
			var take: StringName = proximal if p_in else distal
			entries.append(_blast_sever(body, parts, take, centre, kg3))
		elif d_in:
			entries.append(_blast_sever(body, parts, distal, centre, kg3))
			amputate[distal] = _rest_point(parts, distal)
		else:
			entries.append({"k": "d", "p": String(proximal), "a": vec(_rest_point(parts, proximal)), "s": hash("%s%s" % [body.name, proximal]) % 100000})
			amputate[proximal] = _rest_point(parts, proximal)
	if dead and not gone.has(Vitals.HEAD) and (_in_reach(parts, Vitals.HEAD, SEVER_Z) or _in_reach(parts, Vitals.NECK, SEVER_Z * 0.8)):
		entries.append(_blast_sever(body, parts, Vitals.HEAD, centre, kg3))
	# Torn craters, charring and the pepper, on what's still on the body.
	for part: StringName in parts:
		var e: Array = parts[part]
		if not e[3] or gone.has(BodyDeform._bone_part(part)):
			continue
		var z: float = e[2]
		var rest := _rest_point(parts, part)
		var toward := (_to_rest(e[0]).basis * (centre - (e[1] as Vector3))).normalized()
		if z < MANGLE_Z:
			var closeness := 1.0 - z / MANGLE_Z
			entries.append({"k": "c", "p": String(part), "a": vec(rest), "r": snappedf(lerpf(1.2, 2.6, closeness) * (1.25 if dead else 1.0), 0.01)})
		if z < CHAR_Z:
			entries.append({"k": "h", "p": String(part), "d": vec(toward, 0.01), "m": snappedf(clampf(1.0 - z / CHAR_Z, 0.1, 1.0), 0.01)})
		var pepper_m := frag_m * PEPPER_SHARE
		var dist := (e[1] as Vector3).distance_to(centre)
		if pepper_m > 0.0 and dist < pepper_m:
			var n := roundi(PEPPER_MAX * pow(1.0 - dist / pepper_m, 1.3))
			if n >= 1:
				entries.append({"k": "p", "p": String(part), "d": vec(toward, 0.01), "n": n, "s": hash("%s%s%s" % [body.name, part, centre]) % 100000})
	_add(vitals, entries)
	for part: StringName in amputate:
		vitals.server_amputate(part, amputate[part])
	return entries


## The body comes apart: dead (if it wasn't), every limb and the head off, flung out from
## `centre`, the torso blown open and charred.
static func _gib(body: Node3D, vitals: Vitals, world: World3D, centre: Vector3, kg3: float) -> Array:
	if not vitals.is_dead():
		Harm.note_hit(body, Harm.blast_source)
		vitals.server_kill()
	var entries: Array = [{"k": "g"}]
	var gone := {}
	for part in BodyDeform.severed_parts(vitals):
		gone[part] = true
	var parts := {}
	for hitbox in _hitboxes(body):
		var part: StringName = hitbox.get_meta(&"body_part")
		var p := _nearest(hitbox, centre)
		parts[part] = [hitbox, p, p.distance_to(centre) / kg3, true]
	for part: StringName in [Vitals.THIGH_L, Vitals.THIGH_R, Vitals.UPPER_ARM_L, Vitals.UPPER_ARM_R, Vitals.HEAD]:
		if parts.has(part) and not gone.has(part):
			entries.append(_blast_sever(body, parts, part, centre, kg3, 1.0))
	for part: StringName in TORSO_PARTS:
		if not parts.has(part):
			continue
		var toward := (_to_rest(parts[part][0]).basis * (centre - (parts[part][1] as Vector3))).normalized()
		entries.append({"k": "c", "p": String(part), "a": vec(_rest_point(parts, part)), "r": 3.2})
		entries.append({"k": "h", "p": String(part), "d": vec(toward, 0.01), "m": 1.0})
		entries.append({"k": "p", "p": String(part), "d": vec(toward, 0.01), "n": PEPPER_MAX, "s": hash("%s%s" % [body.name, part]) % 100000})
	return entries


## A sever entry for `part`, cut where the blast came nearest, flung away from it.
static func _blast_sever(body: Node3D, parts: Dictionary, part: StringName, centre: Vector3, kg3: float, closeness := -1.0) -> Dictionary:
	var e: Array = parts[part]
	if closeness < 0.0:
		closeness = clampf(1.0 - float(e[2]) / SEVER_Z, 0.0, 1.0)
	var away := (e[1] as Vector3) - centre
	away = away.normalized() if away.length() > 0.01 else Vector3.UP
	var launch := away * lerpf(LAUNCH.x, LAUNCH.y, closeness) * clampf(kg3 / 0.6, 0.7, 1.6) + Vector3.UP * LAUNCH_UP
	return _sever(part, _rest_point(parts, part), launch, hash("%s%s" % [body.name, part]))


static func _sever(part: StringName, at: Vector3, launch: Vector3, salt: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = salt
	var spin := Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)) * (2.0 + launch.length() * 0.6)
	return {"k": "s", "p": String(part), "a": vec(at), "v": vec(launch, 0.01), "w": vec(spin, 0.01)}


static func _in_reach(parts: Dictionary, part: StringName, z: float) -> bool:
	return parts.has(part) and parts[part][3] and float(parts[part][2]) < z


## Where on `part` the blast came nearest, in the rest pose.
static func _rest_point(parts: Dictionary, part: StringName) -> Vector3:
	return _to_rest(parts[part][0]) * (parts[part][1] as Vector3)


## Adds `entries` to the body (keeping it under MAX_ENTRIES: the oldest non-sever entries go) and
## publishes once.
static func _add(vitals: Vitals, entries: Array) -> void:
	if entries.is_empty():
		return
	for e: Dictionary in entries:
		_add_one(vitals, e, false)
	vitals.server_gore_flush()


static func _add_one(vitals: Vitals, e: Dictionary, publish: bool) -> void:
	var list := vitals.gore_list()
	while list.size() >= MAX_ENTRIES:
		var dropped := false
		for i in list.size():
			if String((list[i] as Dictionary).get("k", "")) in ["p", "h", "c"]:
				list.remove_at(i)
				dropped = true
				break
		if not dropped:
			return
	if String(e.get("k", "")) == "s":
		var part := StringName(e.p)
		if part in BodyDeform.severed_parts(vitals):
			return  # gone already
		BlastGore.drop_helmet(vitals, part)
	vitals.server_gore_add(e, publish)


## Host: a helmet on a head that comes off falls where the head was, a real item to pick up (the
## piece itself carries no gear to loot).
static func drop_helmet(vitals: Vitals, part: StringName) -> void:
	var body := vitals.get_parent() as Soldier
	if part != Vitals.HEAD or body == null or not body.is_inside_tree() or body.inventory == null:
		return
	if body.inventory.slots.get(&"helmet", &"") == &"":
		return
	var level := CompoundLevel.current(body)
	if level == null:
		return
	var removed := body.inventory.unequip(&"helmet")
	if removed.is_empty():
		return
	var at: Vector3 = body.model.head.global_position if body.model and body.model.head else body.global_position + Vector3.UP * 1.6
	level.server_spawn_dropped(StringName(removed.id), 1, at, removed.get("state", {}))


# --- Hitboxes ------------------------------------------------------------------------------

static func _hitboxes(body: Node) -> Array[Area3D]:
	var out: Array[Area3D] = []
	for child in body.get_children():
		var hitbox := child as Area3D
		if hitbox and hitbox.has_meta(&"body_part") and BodyMap.PART_BOXES.has(StringName(hitbox.get_meta(&"body_part"))):
			out.append(hitbox)
	return out


static func _hitbox(body: Node, part: StringName) -> Area3D:
	for hitbox in _hitboxes(body):
		if hitbox.get_meta(&"body_part") == part:
			return hitbox
	return null


## World -> rest pose for points on `hitbox` (Vitals._rest_channel's frame).
static func _to_rest(hitbox: Node3D) -> Transform3D:
	return hitbox.global_transform.affine_inverse()


## The point of `hitbox`'s box nearest `to` (world).
static func _nearest(hitbox: Area3D, to: Vector3) -> Vector3:
	for child in hitbox.get_children():
		var shape := child as CollisionShape3D
		if shape and shape.shape is BoxShape3D:
			var half := (shape.shape as BoxShape3D).size * 0.5
			var local := shape.global_transform.affine_inverse() * to
			return shape.global_transform * local.clamp(-half, half)
	return hitbox.global_position


## No plate, helmet or vehicle hull between the burst and `p` (they shield what's behind them).
static func _exposed(world: World3D, from: Vector3, p: Vector3) -> bool:
	return Warheads._first_hit(world.direct_space_state, from, p, (1 << 3) | Vehicle.LAYER).is_empty()
