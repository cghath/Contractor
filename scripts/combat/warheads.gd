class_name Warheads
extends RefCounted
## What an anti-armour round does when it goes off (wave 5, V2), host only. The rounds are
## data (res://data/warheads.json): a kind (Vehicle.HEAT, TANDEM_HEAT, HE, HEDP, THERMOBARIC),
## a shaped-charge penetration in mm of RHA, a filling as kg of TNT, fragments, an arming
## distance and the flight numbers Launchers uses. By what the round meets:
##
## - A vehicle (layer 7): Vehicle.server_take_hit with the kind (TOP_ATTACK for a Javelin's
##   dive or an NLAW's overfly, on the roof), the penetration and the blast. V1 decides what
##   the hull does with it (zones, carving, fire, and the spall that wounds the crew round the
##   hole: Vehicle._spall); a hit it doesn't stop (penetrated) carries on into the cabin as the
##   residual jet, and whoever it meets on its line dies. A round reaches a hull only where
##   its voxels are (LauncherProjectile._trace): through an open bed it flies on.
## - A structure (VoxelWorld): a shaped charge bores a small deep hole (the jet walks the
##   voxels, its penetration spent per metre by material: JET_MATERIAL_MM_PER_M) and comes out
##   the far side into whoever is behind; HE and HEDP blow a crater (VoxelWorld.server_blast,
##   by material: concrete only chips), thermobaric a much bigger one that clears a room.
## - People: a direct hit is lethal. Around the burst, overpressure through the wound model
##   (Vitals.server_blast, the radius scaled by the filling's cube root, doubled indoors;
##   thermobaric much worse indoors and through the whole room), a lethal zone of primary
##   blast injury close in (Vitals.server_damage: internal bleeding), burns, and fragments
##   (Throwables-style wounds over the exposed hitboxes: walls, armour, other bodies and
##   vehicle hulls stop them).
##
## Launchers also call server_backblast when a launcher fires: the cone behind it.

const PATH := "res://data/warheads.json"
## What a round in flight (and its jet) meets: world, hitboxes, armor, vehicles.
const MASK := (1 << 0) | (1 << 1) | (1 << 3) | (1 << 6)
## What fragments meet: the same; vehicle hulls shield the crew.
const FRAG_MASK := MASK
const WORLD_MASK := 1

## Proposed: the frag grenade's filling (an M67: 0.18 kg of Comp B, about 0.2 kg of TNT), the
## blast WoundModel.BLAST_RADIUS is tuned for. A bigger filling reaches further by the cube
## root of its weight (Hopkinson scaling).
const GRENADE_TNT_KG := 0.2
## Proposed: primary blast injury (internal bleeding, Vitals.server_damage) within
## LETHAL_M_PER_KG3 x cbrt(kg) metres in the open, from LETHAL_DAMAGE.x at its edge to .y at
## the centre (100 is 60% of the blood: cardiac arrest).
const LETHAL_M_PER_KG3 := 1.2
const LETHAL_DAMAGE := Vector2(70.0, 130.0)
## Proposed: thermobaric fillings push their overpressure further in the open and much further
## in a room (reflected, the whole room): radius multipliers (HE indoors: Throwables'
## BLAST_INDOOR_MULT). Inside THERMO_BURN_SHARE of the radius they burn LETHAL_BURN.
const THERMO_OPEN_MULT := 1.3
const THERMO_INDOOR_MULT := 3.0
const THERMO_BURN_SHARE := 0.6
## Proposed: "the room" a thermobaric burst fills: people under a roof within this of it.
const THERMO_ROOM_M := 8.0
const BURN := Vector2(0.05, 0.4)
## Proposed: voxel craters, radius per cbrt(kg) (VoxelWorld materials take their "blast" share
## of it: wood and sheet metal go, concrete chips). A shaped charge's entry crater is
## HEAT_CRATER_M across whatever its filling.
const HE_CRATER_M := 0.9
const THERMO_CRATER_M := 1.6
const HEAT_CRATER_M := 0.25
## Proposed: the shaped-charge jet in structures: mm of RHA it spends per metre of each
## material (concrete about 3.5 times RHA, wood about 12, sandbags/earth 4; sheet metal walls
## are mostly air). Unknown materials count as concrete. JET_RADIUS_M is the hole it bores.
const JET_MATERIAL_MM_PER_M := {
	VoxelWorld.Mat.CONCRETE: 1000.0 / 3.5, VoxelWorld.Mat.PAINTED: 1000.0 / 3.5, VoxelWorld.Mat.STEEL: 1000.0,
	VoxelWorld.Mat.WOOD: 1000.0 / 12.0, VoxelWorld.Mat.SHEET_METAL: 1000.0 / 10.0, VoxelWorld.Mat.SANDBAG: 1000.0 / 4.0,
}
const JET_RADIUS_M := 0.1
const JET_MAX_M := 4.0
## Proposed: a top-attack hit on a vehicle (a Javelin's dive, an NLAW's overfly fired from its
## sensor at the box's top) looks this far down for the hull's voxels (Vehicle's "probe_m"):
## an NLAW's jet over an open bed carries down to its floor.
const TOP_PROBE_M := 3.0
## Proposed: past a wall or hull it goes through, the jet carries on JET_BEHIND_M (whoever it
## meets dies) and throws spall within SPALL_M in a SPALL_CONE_DEG cone: SPALL_WOUNDS
## fragment wounds on whoever it reaches.
const JET_BEHIND_M := 3.0
const SPALL_M := 2.5
const SPALL_CONE_DEG := 60.0
const SPALL_WOUNDS := Vector2i(2, 5)
## Proposed: a backblast in its lethal zone does LETHAL_DAMAGE and burns; in the first
## BACKBLAST_BURN_SHARE of the injury zone it burns BURN.x and throws BACKBLAST_DEBRIS debris
## wounds (superficial). A wall within the launcher's reflect_m behind the shooter throws it
## back at them: overpressure as from REFLECT_AS_M (wall touching) to WoundModel.BLAST_RADIUS
## (at reflect_m), and REFLECT_DAMAGE trauma. In a small room (ENCLOSED_HITS of ENCLOSED_RAYS
## level rays meet a wall within ENCLOSED_M, under a roof) everyone in it within ENCLOSED_M
## takes the overpressure of a blast ROOM_BLAST_AS_M away.
const BACKBLAST_BURN_SHARE := 0.25
const BACKBLAST_DEBRIS := Vector2i(1, 3)
const REFLECT_AS_M := 0.5
const REFLECT_DAMAGE := Vector2(45.0, 10.0)
const ENCLOSED_RAYS := 8
const ENCLOSED_HITS := 6
const ENCLOSED_M := 4.0
const ROOM_BLAST_AS_M := 1.5

static var _data: Dictionary = {}  # warhead id -> entry of warheads.json


## The warhead `id`'s entry of data/warheads.json ({} if none).
static func data(id: Variant) -> Dictionary:
	_load()
	return _data.get(StringName(id), {})


## Every warhead id.
static func ids() -> Array:
	_load()
	return _data.keys()


## The Vehicle hit kind of warhead `id` (Vehicle.HEAT...).
static func kind_of(id: Variant) -> StringName:
	return StringName(data(id).get("kind", "he"))


## Whether warhead `id` is a shaped charge (it bores with a jet).
static func has_jet(id: Variant) -> bool:
	return float(data(id).get("penetration_mm", 0.0)) > 0.0


## Blast radius (m) of `blast_kg` TNT: WoundModel.BLAST_RADIUS for a grenade, by cube root.
static func blast_radius(blast_kg: float) -> float:
	return WoundModel.BLAST_RADIUS * pow(maxf(blast_kg, 0.0) / GRENADE_TNT_KG, 1.0 / 3.0)


## Radius (m) of the crater warhead `id` blows in voxel structures (before materials).
static func crater_radius(id: Variant) -> float:
	var d := data(id)
	var kg3 := pow(maxf(float(d.get("blast_kg", 0.0)), 0.0), 1.0 / 3.0)
	match kind_of(id):
		Vehicle.HEAT, Vehicle.TANDEM_HEAT:
			return HEAT_CRATER_M
		Vehicle.THERMOBARIC:
			return THERMO_CRATER_M * kg3
	return HE_CRATER_M * kg3


static func _load() -> void:
	if not _data.is_empty():
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("Warheads: cannot open %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("warheads"):
		push_error("Warheads: %s is not a valid warhead file" % PATH)
		return
	for entry: Dictionary in parsed.warheads:
		_data[StringName(entry.id)] = entry


# --- A round goes off ---------------------------------------------------------------------

## Host only. Warhead `id` goes off at `pos` flying along `dir`, having met `collider` (a
## vehicle, a hitbox or plate, a voxel structure, the ground; null: in the air). `shooter` is
## who fired it (Harm), `top_attack` a hit from above (Javelin dive, NLAW overfly). Returns
## what it did, for tests and callers: {"vehicle": the Vehicle hit or null, "vehicle_hit": the
## hit sent, "vehicle_result": what server_take_hit said, "direct": the body hit directly or
## null, "holes": voxels the jet bored, "through": whether the jet came out the far side,
## "hurt": bodies it hurt}.
static func server_burst(level: CompoundLevel, id: StringName, pos: Vector3, dir: Vector3, collider: Object, shooter: Node, top_attack := false) -> Dictionary:
	var d := data(id)
	var out := {"vehicle": null, "vehicle_hit": {}, "vehicle_result": {}, "direct": null, "holes": 0, "through": false, "hurt": []}
	if d.is_empty() or level == null:
		return out
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	var kind := kind_of(id)
	var pen := float(d.get("penetration_mm", 0.0))
	var skip: Array = []  # bodies already dealt with (the one hit directly)
	var vehicle := Vehicle.find_on(collider) if collider else null
	var missed := false
	if vehicle:
		out.vehicle = vehicle
		var hit := {"kind": Vehicle.TOP_ATTACK if top_attack else kind, "position": pos, "direction": dir, "shooter": shooter,
			"penetration_mm": pen, "blast_kg": float(d.get("blast_kg", 0.0)), "warhead": String(id), "warhead_kind": kind,
			"calibre_mm": float(d.get("calibre_mm", 0.0)), "top_attack": top_attack,
			"probe_m": TOP_PROBE_M if top_attack else Vehicle.PROBE_M}
		out.vehicle_hit = hit
		var result: Dictionary = vehicle.server_take_hit(hit)
		out.vehicle_result = result
		missed = bool(result.get("missed", false))
		if missed:
			# It met only the box (an overfly's jet down into an open bed): no armour in the way,
			# the jet goes on into whoever is under it.
			out.vehicle = null
			if pen > 0.0:
				out.through = true
				_jet_behind(level, pos, dir, shooter, [], out, false)
		elif pen > 0.0 and (bool(result.get("penetrated", false)) or not bool(result.get("stopped", true))):
			# Through the armour: the jet kills whoever is on its line. The spall inside is
			# the vehicle's (Vehicle._spall, V1), so the jet throws none of its own here.
			out.through = true
			var at: Vector3 = result.get("position", pos)
			_jet_behind(level, at + dir * 0.05, dir, shooter, _rids_of(vehicle), out, false)
	else:
		var body := body_of(collider)
		if body and body.get_node_or_null(^"Vitals"):
			out.direct = body
			skip.append(body)
			_direct_hit(body, collider, pos, dir, shooter)
		var world := VoxelWorld.find_on(collider) if collider else null
		if world and pen > 0.0:
			var jet := _jet_world(world, pos, dir, pen)
			if not (jet.cells as Array).is_empty():
				world.server_holes(jet.cells)
			out.holes = (jet.cells as Array).size()
			if jet.through:
				out.through = true
				_jet_behind(level, jet.exit, dir, shooter, [], out)
	# The blast: a crater by kind (the burst sits just outside what it hit), people around.
	var centre := pos - dir * 0.08
	var jet_on_hull := (kind == Vehicle.HEAT or kind == Vehicle.TANDEM_HEAT) and pen > 0.0 and vehicle != null and not missed
	if not jet_on_hull:  # a shaped charge on a hull spends itself on the hull (V1 carves it)
		level.server_blast(centre, crater_radius(id) * (1.5 if kind == Vehicle.THERMOBARIC and Throwables.indoors(level.get_world_3d(), centre) else 1.0))
	var hurt := server_people(level, centre, d, shooter, skip)
	for b in hurt:
		if not b in out.hurt:
			out.hurt.append(b)
	if out.direct and not out.direct in out.hurt:
		out.hurt.append(out.direct)
	Contracts.objectives.server_charge_blast(pos)  # a raid's cache or AA gun, as a charge would
	PeopleLayer.server_noise(level, pos, PeopleLayer.BLAST_HEARD_M * 1.5)
	_shake_players(level, pos, 20.0 + 15.0 * pow(float(d.get("blast_kg", 0.5)), 1.0 / 3.0))
	return out


## The body (a Soldier or dummy with Vitals) that owns `collider` (a hitbox, a plate or helmet
## under its model, the body itself), or null.
static func body_of(collider: Object) -> Node3D:
	var n := collider as Node
	for i in 10:
		if n == null:
			return null
		if n.get_node_or_null(^"Vitals") is Vitals:
			return n as Node3D
		n = n.get_parent()
	return null


## Host only. A round going off on (or a jet through) `body`: lethal. Wounds where it struck
## (so the body shows them), then dead.
static func _direct_hit(body: Node3D, collider: Object, pos: Vector3, dir: Vector3, shooter: Node) -> void:
	var vitals := body.get_node(^"Vitals") as Vitals
	if vitals.is_dead():
		return
	Harm.note_hit(body, shooter)
	var part: StringName = (collider as Node).get_meta(&"body_part", Vitals.CHEST) if collider is Node and (collider as Node).has_meta(&"body_part") else Vitals.CHEST
	vitals.server_hit(part, {"round_class": Vitals.FULL_POWER, "position": pos, "direction": dir, "distance": 0.0})
	vitals.server_hit(Vitals.CHEST, {"round_class": Vitals.FULL_POWER, "direction": dir, "distance": 0.0})
	vitals.server_kill()


## Host only. Overpressure, the lethal zone, burns and fragments of warhead data `d` going off
## at `centre`, on every combatant not in `skip`; soldiers inside a vehicle are left to the
## vehicle (its hull stops all of it). Returns the bodies it hurt.
static func server_people(level: CompoundLevel, centre: Vector3, d: Dictionary, shooter: Node, skip: Array = []) -> Array:
	var hurt: Array = []
	var world := level.get_world_3d()
	var kg := float(d.get("blast_kg", 0.0))
	var thermo := StringName(d.get("kind", "")) == Vehicle.THERMOBARIC
	var inside := Throwables.indoors(world, centre)
	# The open-air reach; indoors HE reaches further (Throwables' grenade rule), and a
	# thermobaric burst in a room much further for whoever is in the room with it.
	var open_mult := THERMO_OPEN_MULT if thermo else 1.0
	var room_mult := (THERMO_INDOOR_MULT if thermo else Throwables.BLAST_INDOOR_MULT) if inside else open_mult
	var kg3 := pow(maxf(kg, 0.0), 1.0 / 3.0)
	var frag_m := float(d.get("frag_m", 0.0))
	var wounds: Array = d.get("frag_wounds", [1, 3])
	var aboard := vehicle_occupants(level.get_tree())
	for n in Throwables.combatants(level.get_tree()):
		var body := n as Node3D
		var vitals := body.get_node_or_null(^"Vitals") as Vitals
		if vitals == null or vitals.is_dead() or body in skip or aboard.has(body):
			continue
		var point := Throwables.body_point(body)
		var dist := centre.distance_to(point)
		var in_room := inside and Throwables.indoors(world, point) and dist <= THERMO_ROOM_M
		var mult := room_mult if (in_room or not thermo) and inside else open_mult
		var blast_r := blast_radius(kg) * mult
		var lethal_r := LETHAL_M_PER_KG3 * kg3 * mult
		if dist > maxf(blast_r, frag_m):
			continue
		# Walls shelter from the lethal zone and burns, except a thermobaric burst in the
		# same room (the pressure fills it).
		var sheltered := not Throwables.clear_line(world, centre, point)
		if thermo and in_room:
			sheltered = false
		var before := vitals.wound_list().size()
		var was_up := vitals.is_up()
		if dist <= blast_r:
			vitals.server_blast(dist, blast_r, Throwables.has_ear_pro(body))
			Harm.note_hit(body, shooter)
		if thermo and dist <= blast_r * THERMO_BURN_SHARE and not sheltered:
			vitals.server_burn(lerpf(BURN.x, BURN.y, 1.0 - dist / (blast_r * THERMO_BURN_SHARE)))
		if dist <= lethal_r and not sheltered:
			var closeness := 1.0 - dist / maxf(lethal_r, 0.01)
			vitals.server_damage(lerpf(LETHAL_DAMAGE.x, LETHAL_DAMAGE.y, closeness))
		if dist <= frag_m and not vitals.is_dead():
			frag_body(body, vitals, centre, dist, frag_m, Vector2i(int(wounds[0]), int(wounds[1])), shooter)
		if body.has_method(&"suppress"):
			body.suppress(1.0, centre)
		if dist <= blast_r or vitals.wound_list().size() != before or was_up != vitals.is_up():
			hurt.append(body)
	return hurt


## Every soldier inside a vehicle's hull (Vehicle.occupants in seats that aren't "open"), as a
## set: the hull keeps a blast outside off them (a hit on the vehicle itself is the vehicle's:
## Vehicle.server_take_hit's spall and crew blast). Riders in an open seat (a pickup bed, a
## gunner's hatch) take it like anyone, their fragments stopped only where the hull's voxels
## are (Vehicle.blocks_fragment), as a grenade's are.
static func vehicle_occupants(tree: SceneTree) -> Dictionary:
	var out := {}
	for n in tree.get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if v == null:
			continue
		var defs: Array = v.spec.get("seats", [])
		for o in v.occupants():
			var seat := v.seat_of(o)
			if seat < 0 or seat >= defs.size() or not v.seat_open(seat):  # an FFV seat out of an open bay is out in it (VehicleBay)
				out[o] = true
	return out


## Host only. Fragments from a burst at `centre`, `distance` metres from `body`, reaching
## `reach_m`: `wounds.x` to `wounds.y` small wounds (more up close) over the hitboxes with a
## clear line to it, only one of them deep; beyond half the reach a body may be missed
## altogether (Throwables.frag_body's rules, with vehicle hulls shielding too). Returns how
## many wounds it made.
static func frag_body(body: Node3D, vitals: Vitals, centre: Vector3, distance: float, reach_m: float, wounds: Vector2i, shooter: Node, deep := 1) -> int:
	var closeness := clampf(1.0 - distance / maxf(reach_m, 0.01), 0.0, 1.0)
	if closeness < 1.0 - Throwables.FRAG_SURE_SHARE and randf() > closeness / (1.0 - Throwables.FRAG_SURE_SHARE):
		return 0
	var space := body.get_world_3d().direct_space_state
	var exposed: Array[Area3D] = []
	for child in body.get_children():
		var hitbox := child as Area3D
		if hitbox and hitbox.has_meta(&"body_part") and _first_hit(space, centre, hitbox_point(hitbox, Vector3.ZERO)).get("collider") == hitbox:
			exposed.append(hitbox)
	if exposed.is_empty():
		return 0
	var count := clampi(roundi(lerpf(wounds.x, wounds.y, closeness)) + randi_range(-1, 1), wounds.x, wounds.y)
	var made := 0
	for i in count:
		var hitbox := exposed[randi() % exposed.size()]
		var part: StringName = hitbox.get_meta(&"body_part")
		var target := hitbox_point(hitbox, Vector3(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35), randf_range(-0.35, 0.35)))
		var direction := (target - centre).normalized()
		var hit := _first_hit(space, centre, target + direction * 0.05)
		if hit.get("collider") != hitbox:
			continue  # armour or something else took this one
		if VoxelArmor.soft_armor_stops(body, part, Ballistics.LEVELS[0], Vitals.FRAGMENT, distance, direction):
			continue
		Harm.note_hit(body, shooter)
		vitals.server_hit(part, {"round_class": Vitals.FRAGMENT, "position": hit.position, "direction": direction,
			"hitbox": hitbox, "distance": distance, "superficial": deep <= 0})
		deep -= 1
		made += 1
	return made


## The first thing a fragment from `from` to `to` meets. A vehicle's box stops it only where
## the hull's voxels are (Vehicle.blocks_fragment, as Throwables' fragments): an open bed or a
## hatch lets it by.
static func _first_hit(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask := FRAG_MASK) -> Dictionary:
	var exclude: Array[RID] = []
	for i in 4:
		var query := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
		query.collide_with_areas = true
		var hit := space.intersect_ray(query)
		var vehicle := Vehicle.find_on(hit.get("collider")) if not hit.is_empty() else null
		if vehicle == null or vehicle.hull == null or vehicle.blocks_fragment(hit.position, to):
			return hit
		exclude.append(vehicle.get_rid())
	return {}


## A point in a hitbox's first box shape: its centre plus `jitter` (fractions of its size).
static func hitbox_point(hitbox: Area3D, jitter: Vector3) -> Vector3:
	for child in hitbox.get_children():
		var shape := child as CollisionShape3D
		if shape and shape.shape is BoxShape3D:
			return shape.global_transform * ((shape.shape as BoxShape3D).size * jitter)
	return hitbox.global_position


static func _rids_of(node: Node) -> Array[RID]:
	var out: Array[RID] = []
	if node is CollisionObject3D:
		out.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		if child is CollisionObject3D:
			out.append((child as CollisionObject3D).get_rid())
	return out


# --- The shaped-charge jet ------------------------------------------------------------------

## Host only. Walks a jet of `pen_mm` (RHA) into the voxels of `world` from `entry` along `dir`.
## Returns {"cells": the voxels it bores out (Vector3i, JET_RADIUS_M around its line), "through":
## whether it came out the far side, "exit": where (world space), "left_mm": what it had left}.
static func _jet_world(world: VoxelWorld, entry: Vector3, dir: Vector3, pen_mm: float) -> Dictionary:
	var out := {"cells": [], "through": false, "exit": entry, "left_mm": pen_mm}
	var terrain := world.terrain
	if terrain == null:
		return out
	var step_m := VoxelWorld.VOXEL_SIZE * 0.5
	var seen := {}
	var left := pen_mm
	var inside := false
	var travelled := 0.0
	var p := entry - dir * VoxelWorld.VOXEL_SIZE * 0.5  # start just in front of the face
	while travelled < JET_MAX_M:
		var mat := world.material_at(p)
		if mat != VoxelWorld.Mat.EMPTY:
			inside = true
			left -= float(JET_MATERIAL_MM_PER_M.get(mat, JET_MATERIAL_MM_PER_M[VoxelWorld.Mat.CONCRETE])) * step_m
			_bore(terrain, p, dir, seen)
			if left <= 0.0:
				break
		elif inside and travelled > VoxelWorld.VOXEL_SIZE:
			out.through = true
			out.exit = p
			break
		p += dir * step_m
		travelled += step_m
	out.cells = seen.keys()
	out.left_mm = maxf(left, 0.0)
	return out


## Adds the voxels within JET_RADIUS_M of the jet's line at world point `p` to `seen`.
static func _bore(terrain: Node3D, p: Vector3, dir: Vector3, seen: Dictionary) -> void:
	var local := terrain.to_local(p)  # voxel units
	var r := JET_RADIUS_M / VoxelWorld.VOXEL_SIZE
	var local_dir := (terrain.global_basis.inverse() * dir).normalized()
	var lo := Vector3i((local - Vector3.ONE * (r + 1.0)).floor())
	var hi := Vector3i((local + Vector3.ONE * (r + 1.0)).floor())
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var c := Vector3(x, y, z) + Vector3.ONE * 0.5
				var off := c - local
				var radial := off - local_dir * off.dot(local_dir)
				if radial.length() <= r + 0.35 and absf(off.dot(local_dir)) <= 0.75:
					seen[Vector3i(x, y, z)] = true


## Host only. The jet carries on past what it went through, from `from` along `dir`: the first
## body on its line (within JET_BEHIND_M) dies, and (with `spall`: a wall, not a vehicle hull,
## whose spall Vehicle._spall throws) spall wounds whoever is in the cone just behind.
## `exclude` are colliders it has already gone through. Adds them to out.hurt.
static func _jet_behind(level: CompoundLevel, from: Vector3, dir: Vector3, shooter: Node, exclude: Array[RID], out: Dictionary, spall := true) -> void:
	var space := level.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * JET_BEHIND_M, (1 << 0) | (1 << 1) | (1 << 3), exclude)
	query.collide_with_areas = true
	var hit := space.intersect_ray(query)
	var struck: Node3D = null
	if not hit.is_empty():
		struck = body_of(hit.collider)
		if struck and struck.get_node_or_null(^"Vitals"):
			_direct_hit(struck, hit.collider, hit.position, dir, shooter)
			out.hurt.append(struck)
	if not spall:
		return
	var cone := cos(deg_to_rad(SPALL_CONE_DEG))
	for n in Throwables.combatants(level.get_tree()):
		var body := n as Node3D
		if body == struck:
			continue
		var vitals := body.get_node_or_null(^"Vitals") as Vitals
		if vitals == null or vitals.is_dead():
			continue
		var to := Throwables.body_point(body) - from
		if to.length() > SPALL_M or (to.length() > 0.3 and to.normalized().dot(dir) < cone):
			continue
		if frag_body(body, vitals, from, to.length(), SPALL_M, SPALL_WOUNDS, shooter) > 0 and not body in out.hurt:
			out.hurt.append(body)


# --- Backblast ------------------------------------------------------------------------------

## Host only. `shooter` fired a launcher whose backblast (its item's stats "backblast":
## lethal_m, injury_m, cone_deg, reflect_m) leaves `rear` along `back`. Hurts whoever is in
## the cone with nothing in between, throws it back at the shooter off a wall close behind,
## and fills a small room. Returns {"hurt": bodies hurt, "reflected": metres to the wall
## behind (-1: none), "enclosed": a small room}.
static func server_backblast(level: CompoundLevel, shooter: Node3D, rear: Vector3, back: Vector3, spec: Dictionary) -> Dictionary:
	var out := {"hurt": [], "reflected": -1.0, "enclosed": false}
	var lethal_m := float(spec.get("lethal_m", 0.0))
	var injury_m := float(spec.get("injury_m", 0.0))
	var reflect_m := float(spec.get("reflect_m", 0.0))
	var cone := cos(deg_to_rad(float(spec.get("cone_deg", 45.0))))
	back = back.normalized()
	var world := level.get_world_3d()
	var aboard := vehicle_occupants(level.get_tree())
	for n in Throwables.combatants(level.get_tree()):
		var body := n as Node3D
		var vitals := body.get_node_or_null(^"Vitals") as Vitals
		if body == shooter or vitals == null or vitals.is_dead() or aboard.has(body):
			continue
		var point := Throwables.body_point(body)
		var to := point - rear
		var dist := to.length()
		if dist > injury_m or dist < 0.01 or to.normalized().dot(back) < cone:
			continue
		if not Throwables.clear_line(world, rear, point):
			continue  # a wall or cover between
		vitals.server_blast(dist * WoundModel.BLAST_RADIUS / maxf(injury_m, 0.01), WoundModel.BLAST_RADIUS, Throwables.has_ear_pro(body))
		Harm.note_hit(body, shooter)
		if dist <= lethal_m:
			var closeness := 1.0 - dist / maxf(lethal_m, 0.01)
			vitals.server_burn(lerpf(BURN.x, BURN.y, closeness))
			frag_body(body, vitals, rear, dist * 0.5, lethal_m, Vector2i(2, 4), shooter)
			vitals.server_damage(lerpf(LETHAL_DAMAGE.x, LETHAL_DAMAGE.y, closeness))
		elif dist <= injury_m * BACKBLAST_BURN_SHARE:
			vitals.server_burn(BURN.x)
			frag_body(body, vitals, rear, dist, injury_m * BACKBLAST_BURN_SHARE, BACKBLAST_DEBRIS, shooter, 0)
		if body.has_method(&"suppress"):
			body.suppress(0.6, rear)
		out.hurt.append(body)
	if reflect_m <= 0.0:
		return out  # a soft launch: safe from an enclosure (Javelin, NLAW)
	var space := world.direct_space_state
	var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(rear, rear + back * reflect_m, WORLD_MASK | Vehicle.LAYER))  # a wall, or a vehicle's hull
	var shooter_vitals := shooter.get_node_or_null(^"Vitals") as Vitals
	if not wall.is_empty() and shooter_vitals and not shooter_vitals.is_dead():
		var w := rear.distance_to(wall.position)
		out.reflected = w
		var share := clampf(w / reflect_m, 0.0, 1.0)
		shooter_vitals.server_blast(lerpf(REFLECT_AS_M, WoundModel.BLAST_RADIUS * 0.9, share), WoundModel.BLAST_RADIUS, Throwables.has_ear_pro(shooter))
		shooter_vitals.server_burn(lerpf(BURN.x, 0.0, share))
		shooter_vitals.server_damage(lerpf(REFLECT_DAMAGE.x, REFLECT_DAMAGE.y, share))
		if not shooter in out.hurt:
			out.hurt.append(shooter)
	if enclosed(world, shooter.global_position + Vector3.UP * 1.0):
		out.enclosed = true
		for n in Throwables.combatants(level.get_tree()):
			var body := n as Node3D
			var vitals := body.get_node_or_null(^"Vitals") as Vitals
			if vitals == null or vitals.is_dead() or aboard.has(body) or body.global_position.distance_to(shooter.global_position) > ENCLOSED_M:
				continue
			if not Throwables.indoors(world, Throwables.body_point(body)):
				continue
			vitals.server_blast(ROOM_BLAST_AS_M, WoundModel.BLAST_RADIUS, Throwables.has_ear_pro(body))
			if not body in out.hurt:
				out.hurt.append(body)
	return out


## Whether `pos` is in a small room: under a roof, with walls within ENCLOSED_M on most sides.
static func enclosed(world: World3D, pos: Vector3) -> bool:
	if not Throwables.indoors(world, pos):
		return false
	var space := world.direct_space_state
	var hits := 0
	for i in ENCLOSED_RAYS:
		var a := TAU * i / ENCLOSED_RAYS
		var to := pos + Vector3(cos(a), 0.0, sin(a)) * ENCLOSED_M
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(pos, to, WORLD_MASK)).is_empty():
			hits += 1
	return hits >= ENCLOSED_HITS


static func _shake_players(level: CompoundLevel, pos: Vector3, radius: float) -> void:
	for player in level.players.get_children():
		var d := (player as Node3D).global_position.distance_to(pos)
		if d < radius and player is Soldier:
			player._client_shake.rpc_id((player as Soldier).owner_peer(), 1.0 - d / radius)
