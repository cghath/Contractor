class_name ExoMech
extends RefCounted
## The heavy mech-class exo, the "Atlas-pattern Walker" (docs/near_future_hardware.md 2.3;
## Captain, 2026-10-16): a powered chassis the soldier climbs into and pilots, learned from the
## Captain's reference art (a bulky biped with an integrated head unit, thick hydraulic legs, a
## power pack on the back and a two-handed heavy weapon held low and ready, in real camo).
## - It is worn in the exo slot (ExoFrame.SLOT, so never with an LX-3), but never picked up or
##   put on from the inventory: you climb in where it stands and climb out to leave it
##   standing there (server_enter, server_exit; Inventory refuses it anywhere else). A suit left
##   standing is a WorldItem: anyone can climb into it again, damage and all.
## - Its armour is real ArmorRules armour (Captain, 2026-10-16: "armor plates are where they are
##   seen ... pilots can be wounded, shot through it eventually"): its "pads" are VoxelArmor
##   plates on the body parts they cover, rated per part (ceramic IV over the chest and belly,
##   steel III++ on the back, shoulders, arms, legs and the head unit), with their chips and
##   integrity in the suit's state like the LX-3's (ExoFrame.pad_items, GearRig). A round that
##   gets through goes on into the pilot. A parked suit's plates are hit targets too.
## - It carries "assist_kg" (Soldier.load_kg; itself and a heavy load) but never runs: no
##   sprint, jump, climb or prone, and a fixed "speed_mult" (SoldierMovement). Its actuators
##   take rounds like the LX-3's struts (ExoFrame.server_round, "frame_hp"); disabled, the
##   pilot carries all of it, suit included: climb out.
## - Its gun (a mech-only weapon, the WG-50: tag "mech_only") rides on the suit: climbing in
##   swaps the pilot's own rifle onto the suit's rack ("rack" in its state) and the gun into his
##   hands; climbing out puts it back on the suit ("gun") and the rifle in his hands. It is held
##   low and ready at the hip (GearRig.held_transform).
## Numbers proposed. Repair cost and pilot training are open (doc 2.3a): not built.

const SLOT := ExoFrame.SLOT
## Tag on the suit's item; "mech_only" on a weapon only its pilot can carry.
const TAG := "mech"
const GUN_TAG := "mech_only"

## Climbing in: one clip (CharacterModel.MECH_IN), the hatch closing over its middle.
const ENTER_S := 3.0
## Climbing out: the hatch opens (MECH_OPEN), then he steps down out of it (MECH_OUT).
const OPEN_S := 1.2
const OUT_S := 1.0
## How near a standing suit (its action point) you must be to climb in.
const REACH_M := 2.0
## How far in front of the suit he stands once out.
const STEP_OUT_M := 0.85
## A parked suit's box (and the WorldItem's collision).
const PARKED_SIZE := Vector3(0.95, 1.9, 0.85)

## The hatch (Captain's ref: the chest swings up, the belly plate down, the head unit back):
## pad id -> [hinge point on its bone, open angle about X (radians)].
const HATCH := {
	"chest": [Vector3(0, 0.57, -0.2), 1.55],
	"abdomen": [Vector3(0, 0.05, -0.19), -1.2],
	"head": [Vector3(0, 0.0, 0.22), -1.05],
	"head_top": [Vector3(0, 0.0, 0.22), -1.05],
}


static func is_mech(item: ItemData) -> bool:
	return item != null and item.tags.has(TAG)


## Whether `item` is a weapon only a heavy exo's pilot carries (the WG-50).
static func mech_only(item: ItemData) -> bool:
	return item != null and item.tags.has(GUN_TAG)


## The heavy exo `inventory` wears, or null.
static func worn(inventory: Inventory) -> ItemData:
	var item := ExoFrame.worn(inventory)
	return item if is_mech(item) else null


static func piloting(inventory: Inventory) -> bool:
	return worn(inventory) != null


## The suit's fixed walking speed share (1 with none).
static func speed_mult(inventory: Inventory) -> float:
	var item := worn(inventory)
	return float(item.stats.get("speed_mult", 0.75)) if item else 1.0


## How far its back sits behind the torso (GearRig hangs a pack on it), or -1 with none.
static func spine_depth(inventory: Inventory) -> float:
	var item := worn(inventory)
	return float(item.stats.get("spine_depth", 0.25)) if item else -1.0


## Whether `body` is climbing into or out of a suit now (no moving meanwhile).
static func transitioning(body: Node) -> bool:
	var model := body.get(&"model") as CharacterModel if body else null
	return model != null and model.action_shown() in [CharacterModel.MECH_IN, CharacterModel.MECH_OPEN, CharacterModel.MECH_OUT]


## How far the worn suit's hatch stands open now (0 shut .. 1 open), from the clip playing.
static func hatch_open(model: CharacterModel) -> float:
	var u := model.action_progress()
	match model.action_shown():
		CharacterModel.MECH_IN:
			return 1.0 - smoothstep(0.35, 0.8, u)
		CharacterModel.MECH_OPEN:
			return smoothstep(0.1, 0.85, u)
	return 0.0


## "Climb into the Atlas-pattern Walker  [chest 64%, gun]" for the interaction menu.
static func describe(item: ItemData, state: Dictionary) -> String:
	var parts := PackedStringArray()
	var worst := 1.0
	for pad: Dictionary in state.get("pads", {}).values():
		worst = minf(worst, ArmorRules.integrity(pad))
	if worst < 1.0:
		parts.append("plates %d%%" % roundi(worst * 100.0))
	var full := float(item.stats.get("frame_hp", 100.0))
	if bool(state.get("disabled", false)):
		parts.append("DISABLED")
	elif float(state.get("hp", full)) < full:
		parts.append("actuators %d%%" % roundi(float(state.hp) / full * 100.0))
	if not (state.get("gun", {}) as Dictionary).is_empty():
		parts.append(ItemDB.get_item(StringName(state.gun.id)).name)
	return "Climb into the %s%s" % [item.name, "  [%s]" % ", ".join(parts) if not parts.is_empty() else ""]


# --- Climbing in and out (host) -----------------------------------------------------------

## Why `s` can't climb into `suit` now ("" if it can); `reach`: check the distance too.
static func enter_problem(s: Soldier, suit: WorldItem, reach := true) -> String:
	if s.inventory.slots.get(SLOT, &"") != &"":
		return "Climb out of your suit first" if piloting(s.inventory) else "Take off your exo frame first"
	if s.inventory.hands != &"":
		return "Your hands are full"
	if s.carry_mode != &"":
		return "You're already moving someone"
	if is_instance_valid(s.vehicle):
		return "Get out of the vehicle first"
	if reach and parked_point(suit).distance_to(s.global_position + Vector3.UP * 1.2) > REACH_M:
		return "Too far away"
	return ""


## Host: `s` climbs into the suit standing at `suit`. Returns "" once it has started, else why
## not. He's put where it stood, facing its way, wearing it with its damage; its gun goes into
## his hands, his own rifle onto its rack; the hatch closes round him over ENTER_S.
static func server_enter(s: Soldier, suit: WorldItem) -> String:
	var why := enter_problem(s, suit)
	if why != "":
		return why
	var item := ItemDB.get_item(suit.item_id)
	var state := suit.state.duplicate(true)
	var feet := suit.global_position - suit.global_basis.y * PARKED_SIZE.y * 0.5
	var yaw := suit.global_rotation.y
	GameState.item_taken(suit.uid)
	suit.queue_free()
	var gun: Dictionary = state.get("gun", {})
	for key: String in ["gun", "yaw", "camo"]:
		state.erase(key)
	if not gun.is_empty():
		var own := s.inventory.unequip(&"primary")
		if not own.is_empty():
			state["rack"] = own
	s.inventory.put_on(SLOT, item.id, state)
	if not gun.is_empty():
		s.inventory.put_on(&"primary", StringName(gun.id), gun.get("state", {}))
	s.server_place(feet, yaw)
	s.server_busy(ENTER_S, "Climbing into the %s" % item.name)
	s.model.server_play(CharacterModel.MECH_IN, ENTER_S)
	Sfx.server_play(&"impact_plate", feet + Vector3.UP * 1.2)  # the hatch, shutting (a placeholder)
	SessionLog.note("%s climbs into the %s" % [s.log_name(), item.name])
	return ""


## Why `s` can't climb out now ("" if it can).
static func exit_problem(s: Soldier) -> String:
	if not piloting(s.inventory):
		return "You're not in a suit"
	if s.carry_mode != &"":
		return "Put them down first"
	if is_instance_valid(s.vehicle):
		return "Get out of the vehicle first"
	return ""


## Host: `s` climbs out: the hatch opens (OPEN_S), then the suit is left standing where he
## was, facing his way, with its damage and its gun on it (his rifle back in his hands), and
## he steps down in front of it (OUT_S). Interrupted (he went down, or it's gone), he stays in.
static func server_exit(s: Soldier) -> void:
	if exit_problem(s) != "":
		return
	var item := worn(s.inventory)
	s.server_busy(OPEN_S + OUT_S, "Climbing out of the %s" % item.name)
	s.model.server_play(CharacterModel.MECH_OPEN, OPEN_S)
	await s.get_tree().create_timer(OPEN_S).timeout
	if not is_instance_valid(s) or not s.is_inside_tree() or not s.vitals.is_up() or worn(s.inventory) != item:
		return
	var removed := s.inventory.unequip(SLOT)
	var state: Dictionary = removed.get("state", {}).duplicate(true)
	var primary: StringName = s.inventory.slots.get(&"primary", &"")
	if primary != &"" and mech_only(ItemDB.get_item(primary)):
		state["gun"] = s.inventory.unequip(&"primary")
	var rack: Dictionary = state.get("rack", {})
	state.erase("rack")
	if not rack.is_empty():
		s.inventory.put_on(&"primary", StringName(rack.id), rack.get("state", {}))
	var yaw := s.global_rotation.y
	state["yaw"] = yaw
	state["camo"] = String(s.model.variant)
	var feet := s.global_position
	var level := CompoundLevel.current(s)
	if level:
		level.server_spawn_dropped(item.id, 1, feet + Vector3.UP * PARKED_SIZE.y * 0.5, state)
	s.server_place(feet - Basis(Vector3.UP, yaw).z * STEP_OUT_M, yaw)
	s.model.server_play(CharacterModel.MECH_OUT, OUT_S)
	Sfx.server_play(&"impact_plate", feet + Vector3.UP * 1.2)
	SessionLog.note("%s climbs out of the %s" % [s.log_name(), item.name])


# --- A suit left standing (WorldItem) -------------------------------------------------------

## Where a parked suit's interaction point is: at its open cockpit (world).
static func parked_point(suit: Node3D) -> Vector3:
	var b := suit.global_basis
	return suit.global_position + b.y * 0.35 - b.z * 0.35


## A parked suit: the chassis standing open on a bare skeleton (its rest pose, arms a little
## out), its plates real VoxelArmor that records hits into the WorldItem's state ("pads"), in
## the camo of whoever left it ("camo"). Centred on its box (PARKED_SIZE), like a WorldItem.
static func parked_node(item: ItemData, state: Dictionary, suit: WorldItem) -> Node3D:
	var root := Node3D.new()
	root.name = "ParkedSuit"
	root.position = Vector3.DOWN * PARKED_SIZE.y * 0.5
	var bones := Skeleton.new()
	root.add_child(bones)
	var variant := String(state.get("camo", "multicam"))
	for pad: Dictionary in ExoFrame.pad_items(item):
		var bone := bones.part_node(pad.part)
		if bone == null:
			continue
		var piece := VoxelArmor.new()
		piece.pad = pad.id
		piece.body_part = pad.part
		piece.loose_suit = suit
		bone.add_child(piece)
		piece.setup(pad.item, &"", null, 1)
		piece.name = "MechPad_" + pad.id
		piece.transform = hatched(pad.id, pad.at, 1.0)
		piece.set_camo(variant)
	show_parked_damage(root, state)
	dress(bones, item, bool(state.get("disabled", false)), 1, variant)
	return root


## Redraws a parked suit's plates from `state` (its "pads": chips, integrity).
static func show_parked_damage(root: Node3D, state: Dictionary) -> void:
	var pads: Dictionary = state.get("pads", {})
	for piece: VoxelArmor in root.find_children("MechPad_*", "VoxelArmor", true, false):
		var pad: Dictionary = pads.get(piece.pad, {})
		piece.apply_damage(pad.get("chips", []), ArmorRules.is_shattered(pad))


## A pad's transform with the hatch `open` (0..1) of the way open (HATCH; others as they are).
static func hatched(pad: String, at: Transform3D, open: float) -> Transform3D:
	if not HATCH.has(pad) or open <= 0.0:
		return at
	var hinge: Vector3 = HATCH[pad][0]
	var swing := Transform3D(Basis(Vector3.RIGHT, float(HATCH[pad][1]) * open), Vector3.ZERO)
	return Transform3D(Basis.IDENTITY, hinge) * swing * Transform3D(Basis.IDENTITY, -hinge) * at


## The bones of an empty suit (a parked one): CharacterModel's rest layout, arms hanging a
## little out from the body, forearms forward, so the chassis stands as a pilot would.
class Skeleton extends Node3D:
	var torso: Node3D
	var head: Node3D
	var _parts := {}

	func _init() -> void:
		name = "Bones"
		torso = _bone(self, CharacterModel.TORSO_PIVOT)
		head = _bone(torso, CharacterModel.HEAD_PIVOT)
		_parts[Vitals.HEAD] = head
		_parts[Vitals.CHEST] = torso
		_parts[Vitals.ABDOMEN] = torso
		for side: float in [1.0, -1.0]:
			var r := side > 0.0
			var upper := _bone(torso, CharacterModel.SHOULDER * Vector3(side, 1, 1))
			upper.rotation.z = side * 0.14
			var fore := _bone(upper, Vector3(0, -CharacterModel.UPPER_ARM, 0))
			fore.rotation.x = 0.45
			var thigh := _bone(self, CharacterModel.HIP * Vector3(side, 1, 1))
			var shin := _bone(thigh, Vector3(0, -CharacterModel.THIGH, 0))
			_parts[Vitals.UPPER_ARM_R if r else Vitals.UPPER_ARM_L] = upper
			_parts[Vitals.FOREARM_R if r else Vitals.FOREARM_L] = fore
			_parts[Vitals.THIGH_R if r else Vitals.THIGH_L] = thigh
			_parts[Vitals.SHIN_R if r else Vitals.SHIN_L] = shin

	func part_node(part: StringName) -> Node3D:
		return _parts.get(part)

	static func _bone(parent: Node3D, at: Vector3) -> Node3D:
		var n := Node3D.new()
		n.position = at
		parent.add_child(n)
		return n


# --- Art (every peer: GearRig, and a parked suit) ------------------------------------------

const PART_NAME := "ExoMechPart"
## Actuator housings and the frame: dark and matte, like the LX-3's (Captain, 2026-10-17).
const STRUT := Color("3d4038")
const JOINT := Color("222420")
const PISTON := Color("7a7e78")
## The sensor eyes on the head unit.
const SENSOR := Color(1.0, 0.62, 0.2)


## Puts the suit's chassis on `rig`'s bones (a CharacterModel, or a parked Skeleton: anything
## with part_node() and torso), replacing any; nothing with `item` null. The plates are its
## pads (GearRig); this is the rest: the power pack, hip ring, hydraulic legs, gauntlets, boots
## and the head unit's sensors. The big shell pieces are in the side's kit colour
## (GearRig.armor_color_for `variant`); a worn suit also gets its hatch (HatchRig).
static func dress(rig: Node3D, item: ItemData, disabled: bool, layers: int, variant: String) -> void:
	for n: Node in rig.find_children(PART_NAME + "*", "", true, false):
		n.queue_free()
	if item == null:
		return
	var shell := GearRig.armor_color_for(variant)
	var torso: Node3D = rig.torso
	# The power pack on the back (its armour plate, "back", over its rear face), exhausts on top,
	# vents down its sides, the actuators that carry it up over the shoulders.
	_box(torso, Vector3(0.46, 0.5, 0.2), Vector3(0, 0.33, 0.24), shell, layers)
	_box(torso, Vector3(0.36, 0.08, 0.16), Vector3(0, 0.62, 0.22), JOINT, layers)
	for side: float in [1.0, -1.0]:
		_rod(torso, 0.032, 0.16, Vector3(side * 0.14, 0.7, 0.27), JOINT, layers)  # exhaust stack
		for i in 4:
			_box(torso, Vector3(0.012, 0.035, 0.15), Vector3(side * 0.236, 0.2 + i * 0.07, 0.24), JOINT, layers)  # vent slats
		_box(torso, Vector3(0.1, 0.14, 0.22), Vector3(side * 0.27, 0.57, 0.11), STRUT, layers)  # shoulder actuator
		_box(torso, Vector3(0.05, 0.09, 0.3), Vector3(side * 0.215, 0.0, 0.0), JOINT, layers)  # hip ring, side
		_box(torso, Vector3(0.14, 0.15, 0.035), Vector3(side * 0.11, -0.1, -0.175), shell, layers)  # tasset
	_box(torso, Vector3(0.44, 0.09, 0.05), Vector3(0, 0.0, -0.16), JOINT, layers)  # hip ring, front
	_box(torso, Vector3(0.44, 0.09, 0.05), Vector3(0, 0.0, 0.16), JOINT, layers)  # hip ring, back
	_box(torso, Vector3(0.3, 0.06, 0.26), Vector3(0, 0.555, 0.02), JOINT, layers)  # neck collar
	var light := _box(torso, Vector3(0.03, 0.03, 0.012), Vector3(0, 0.6, 0.41), ExoFrame.LIGHT_OFF if disabled else ExoFrame.LIGHT_ON, layers)
	_glow(light, 1.5)
	for side: float in [1.0, -1.0]:
		var r := side > 0.0
		var upper: Node3D = rig.part_node(Vitals.UPPER_ARM_R if r else Vitals.UPPER_ARM_L)
		var fore: Node3D = rig.part_node(Vitals.FOREARM_R if r else Vitals.FOREARM_L)
		var thigh: Node3D = rig.part_node(Vitals.THIGH_R if r else Vitals.THIGH_L)
		var shin: Node3D = rig.part_node(Vitals.SHIN_R if r else Vitals.SHIN_L)
		_box(upper, Vector3(0.11, 0.12, 0.12), Vector3(side * 0.06, -0.01, 0), JOINT, layers)  # shoulder joint
		_rod(upper, 0.012, 0.22, Vector3(side * 0.11, -0.18, 0.05), PISTON, layers)
		_drum(upper, 0.045, 0.06, Vector3(side * 0.08, -0.32, 0), JOINT, layers)  # elbow
		_box(fore, Vector3(0.12, 0.09, 0.13), Vector3(0, -0.265, -0.01), shell.darkened(0.25), layers)  # gauntlet
		_box(fore, Vector3(0.1, 0.03, 0.11), Vector3(0, -0.215, -0.01), JOINT, layers)  # its cuff
		_rod(fore, 0.01, 0.17, Vector3(side * 0.1, -0.11, 0.045), PISTON, layers)
		_drum(thigh, 0.05, 0.06, Vector3(side * 0.165, -0.02, 0), JOINT, layers)  # hip
		_box(thigh, Vector3(0.05, 0.3, 0.07), Vector3(side * 0.18, -0.23, 0.035), STRUT, layers)  # thigh actuator
		_rod(thigh, 0.015, 0.3, Vector3(side * 0.18, -0.24, -0.02), PISTON, layers)
		_drum(thigh, 0.06, 0.08, Vector3(side * 0.16, -0.45, 0), JOINT, layers)  # knee
		_box(thigh, Vector3(0.15, 0.1, 0.045), Vector3(side * 0.025, -0.46, -0.13), shell, layers)  # knee cap
		_box(shin, Vector3(0.05, 0.3, 0.07), Vector3(side * 0.16, -0.2, 0.04), STRUT, layers)  # shin actuator
		_rod(shin, 0.014, 0.3, Vector3(side * 0.16, -0.2, -0.01), PISTON, layers)
		_box(shin, Vector3(0.1, 0.22, 0.06), Vector3(0, -0.19, 0.135), STRUT, layers)  # calf hydraulics
		_drum(shin, 0.045, 0.2, Vector3(0, -0.36, 0.0), JOINT, layers)  # ankle
		_box(shin, Vector3(0.19, 0.1, 0.34), Vector3(0, -0.4, -0.05), JOINT, layers)  # boot
		_box(shin, Vector3(0.18, 0.045, 0.11), Vector3(0, -0.355, -0.18), shell, layers)  # toe plate
		_box(shin, Vector3(0.11, 0.05, 0.07), Vector3(0, -0.42, 0.13), STRUT, layers)  # heel spur
	# The head unit's sensors: three eyes across the visor, side pods, an antenna.
	var head: Node3D = rig.part_node(Vitals.HEAD)
	# On the head unit's own plate when it's there (GearRig's ExoPad_head, a parked suit's
	# MechPad_head), so they swing back with it as the hatch opens; in its space, from the bone's.
	for unit_name: String in ["ExoPad_head", "MechPad_head"]:
		var unit := head.get_node_or_null(unit_name) as Node3D
		if unit:
			var holder := Node3D.new()
			holder.name = PART_NAME + "Sensors"
			for pad: Dictionary in ExoFrame.pad_items(item):
				if pad.id == "head":
					holder.transform = (pad.at as Transform3D).affine_inverse()  # (from its shut place: it may stand open now)
			unit.add_child(holder)
			head = holder
			break
	for i in 3:
		_glow(_box(head, Vector3(0.028, 0.022, 0.012), Vector3((i - 1) * 0.055, 0.17, -0.242), SENSOR, layers), 2.0)
	for side: float in [1.0, -1.0]:
		_box(head, Vector3(0.04, 0.09, 0.11), Vector3(side * 0.235, 0.16, 0.0), STRUT, layers)
	_rod(head, 0.005, 0.22, Vector3(0.16, 0.37, 0.13), JOINT, layers)
	if rig is CharacterModel:
		var hatch := HatchRig.new()
		hatch.name = PART_NAME + "Hatch"
		hatch.item = item
		rig.add_child(hatch)


## Animates a worn suit's hatch (HATCH) while its pilot climbs in or out: the pads GearRig
## put on the bones swing on their hinges, and settle shut once the clip is over.
class HatchRig extends Node:
	var item: ItemData
	var _shown := 0.0

	func _process(_delta: float) -> void:
		var model := get_parent() as CharacterModel
		var gear := model.get_parent().get_node_or_null(^"Gear") as GearRig if model else null
		if gear == null:
			return
		var open := ExoMech.hatch_open(model)
		if open == _shown:
			return
		_shown = open
		var pads := gear.pads()
		for pad: Dictionary in ExoFrame.pad_items(item):
			var piece: VoxelArmor = pads.get(pad.id)
			if piece and ExoMech.HATCH.has(pad.id):
				piece.transform = ExoMech.hatched(pad.id, pad.at, open)


static func _glow(m: MeshInstance3D, energy: float) -> void:
	var mat := m.material_override as StandardMaterial3D
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = energy


static func _rod(parent: Node3D, radius: float, length: float, at: Vector3, colour: Color, layers: int) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 8
	cm.rings = 1
	return _part(parent, cm, at, Basis.IDENTITY, colour, layers)


static func _drum(parent: Node3D, radius: float, width: float, at: Vector3, colour: Color, layers: int) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = width
	cm.radial_segments = 12
	cm.rings = 1
	return _part(parent, cm, at, Basis(Vector3.FORWARD, PI / 2), colour, layers)


static func _box(parent: Node3D, size: Vector3, at: Vector3, colour: Color, layers: int) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _part(parent, bm, at, Basis.IDENTITY, colour, layers)


static func _part(parent: Node3D, mesh: Mesh, at: Vector3, basis: Basis, colour: Color, layers: int) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = PART_NAME
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.6
	mat.metallic = 0.45
	m.material_override = mat
	m.transform = Transform3D(basis, at)
	m.layers = layers
	parent.add_child(m, true)  # readable unique names: dress finds them again by pattern
	return m
