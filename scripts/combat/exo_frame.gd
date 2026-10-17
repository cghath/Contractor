class_name ExoFrame
extends RefCounted
## The light infantry exo (docs/near_future_hardware.md 2.2; Captain, 2026-10-16): a powered
## strut frame worn OVER the normal kit (its own Inventory slot, "exo"; the vest, plates,
## helmet and pack stay as they are). Learned from the Captain's reference art: outer struts
## along the upper arms, forearms, thighs and shins with hinges at the elbows, knees and hips,
## cuffs at the wrists and ankles, a hip belt, and a spine power pack with actuator pylons up
## over the shoulders.
## - Working, it carries "assist_kg" of the load (Soldier.load_kg: the load tiers, speed and
##   stamina see that much less), so the soldier moves as if lighter.
## - It takes rounds (Captain: "should be able to take rounds and possibly become disabled"): a
##   round into an arm or leg may strike its strut, one into the back from behind the spine
##   pack (STRUT_CHANCE), costing the frame energy / DAMAGE_J_PER_HP of its "frame_hp"; the
##   round goes on into the body, a little slowed (STRUT_ENERGY_LOSS). At 0 it's disabled: no
##   assist, so the wearer is back to normal walking with the normal weight debuffs, frame and
##   all ("slowing the user down to normal walk speed with the regular weight debuffs").
## Its integrity lives in the slot's state ("hp"; "disabled"), so it travels with the item and
## every peer sees it (Inventory.net_state). Numbers proposed.

const SLOT := &"exo"
## Chance a round into this part strikes the frame (the back: only from behind).
const STRUT_CHANCE := {
	&"upper_arm_l": 0.3, &"upper_arm_r": 0.3, &"forearm_l": 0.25, &"forearm_r": 0.25,
	&"thigh_l": 0.3, &"thigh_r": 0.3, &"shin_l": 0.3, &"shin_r": 0.3,
}
const SPINE_CHANCE := 0.35
const DAMAGE_J_PER_HP := 60.0
const FRAGMENT_HP := 6.0
const STRUT_ENERGY_LOSS := 0.1
## Tests: the strut roll (0..1) instead of randf(), or NAN.
static var roll_override := NAN


## The frame `inventory` wears, or null.
static func worn(inventory: Inventory) -> ItemData:
	if inventory == null:
		return null
	var id: StringName = inventory.slots.get(SLOT, &"")
	return ItemDB.get_item(id) if id != &"" else null


## Its integrity, 0..1 (1 when the state says nothing yet), or -1 with none worn.
static func integrity(inventory: Inventory) -> float:
	var item := worn(inventory)
	if item == null:
		return -1.0
	var full := float(item.stats.get("frame_hp", 100.0))
	return clampf(float(inventory.state_of(SLOT).get("hp", full)) / full, 0.0, 1.0)


## Whether the worn frame still works.
static func working(inventory: Inventory) -> bool:
	return worn(inventory) != null and not bool(inventory.state_of(SLOT).get("disabled", false)) and integrity(inventory) > 0.0


## How much of the load a working frame carries (kg), 0 otherwise.
static func assist_kg(inventory: Inventory) -> float:
	return float(worn(inventory).stats.get("assist_kg", 0.0)) if working(inventory) else 0.0


## HUD text: "Frame 64%", "Frame DISABLED", or "".
static func summary(inventory: Inventory) -> String:
	var item := worn(inventory)
	if item == null:
		return ""
	return "Frame DISABLED" if not working(inventory) else "Frame %d%%" % roundi(integrity(inventory) * 100.0)


## Host: a round into `part` of `soldier` (Ballistics, before the wound): may strike the frame.
## `hit` is the wound's hit_info ("direction", "energy_j", "round_class"); a strut strike takes
## a little of its energy. Returns whether the frame was struck.
static func server_round(soldier: Node, part: StringName, hit: Dictionary) -> bool:
	var s := soldier as Soldier
	if s == null or worn(s.inventory) == null or bool(s.inventory.state_of(SLOT).get("disabled", false)):
		return false
	var chance := float(STRUT_CHANCE.get(part, 0.0))
	if chance <= 0.0 and part in [Vitals.CHEST, Vitals.ABDOMEN, Vitals.TORSO]:
		var dir: Vector3 = hit.get("direction", Vector3.ZERO)
		var forward := -s.global_basis.z
		if dir.length_squared() > 0.0001 and dir.normalized().dot(forward) > 0.3:  # travelling the way he faces: from behind
			chance = SPINE_CHANCE
	if chance <= 0.0:
		return false
	var roll := roll_override if not is_nan(roll_override) else randf()
	if roll >= chance:
		return false
	var energy := float(hit.get("energy_j", -1.0))
	var cost := FRAGMENT_HP if StringName(hit.get("round_class", &"")) == Vitals.FRAGMENT or energy <= 0.0 else energy / DAMAGE_J_PER_HP
	server_damage(s, cost)
	if energy > 0.0:
		hit["energy_j"] = energy * (1.0 - STRUT_ENERGY_LOSS)
	return true


## Host: takes `hp` off the worn frame's integrity; at 0 it's disabled.
static func server_damage(s: Soldier, hp: float) -> void:
	var item := worn(s.inventory)
	if item == null:
		return
	var state := s.inventory.state_of(SLOT).duplicate(true)
	var full := float(item.stats.get("frame_hp", 100.0))
	var left := maxf(float(state.get("hp", full)) - hp, 0.0)
	state["hp"] = snappedf(left, 0.1)
	var was := bool(state.get("disabled", false))
	if left <= 0.0:
		state["disabled"] = true
	s.inventory.set_slot_state(SLOT, state)  # Soldier._on_inventory_changed: the load the legs now carry
	if not was and left <= 0.0:
		Sfx.server_play(&"impact_plate", s.global_position + Vector3.UP)  # its last strut goes


# --- Art (every peer: GearRig) ---------------------------------------------------------

const PART_NAME := "ExoFramePart"
const STRUT := Color("6b6e69")
const JOINT := Color("2b2d2b")
const LIGHT_ON := Color(0.25, 1.0, 0.4)
const LIGHT_OFF := Color(1.0, 0.18, 0.12)


## Puts the frame's parts on `model`'s bones (replacing any), or takes them off (item null).
static func dress(model: CharacterModel, item: ItemData, disabled: bool, layers: int) -> void:
	for n: Node in model.find_children(PART_NAME + "*", "", true, false):
		n.queue_free()
	if item == null:
		return
	for side: float in [1.0, -1.0]:
		var r := side > 0.0
		var upper := model.part_node(Vitals.UPPER_ARM_R if r else Vitals.UPPER_ARM_L)
		var fore := model.part_node(Vitals.FOREARM_R if r else Vitals.FOREARM_L)
		var thigh := model.part_node(Vitals.THIGH_R if r else Vitals.THIGH_L)
		var shin := model.part_node(Vitals.SHIN_R if r else Vitals.SHIN_L)
		_box(upper, Vector3(0.025, 0.26, 0.035), Vector3(side * 0.072, -0.15, 0.0), STRUT, layers)
		_box(upper, Vector3(0.05, 0.05, 0.05), Vector3(side * 0.072, -0.31, 0.0), JOINT, layers)  # elbow hinge
		# Captain, 2026-10-16 ("connected arm to shoulder"): a shoulder joint housing at the arm's
		# own pivot (part_node's origin), so it always sits at the joint as the arm swings, bridging
		# the upper-arm strut up to the torso-mounted pylon above it.
		_box(upper, Vector3(0.065, 0.09, 0.065), Vector3(side * 0.072, 0.02, 0.0), JOINT, layers)
		_box(fore, Vector3(0.022, 0.19, 0.03), Vector3(side * 0.066, -0.11, 0.0), STRUT, layers)
		_box(fore, Vector3(0.09, 0.03, 0.09), Vector3(0.0, -0.2, 0.0), JOINT, layers)  # wrist cuff
		_box(thigh, Vector3(0.06, 0.06, 0.06), Vector3(side * 0.1, -0.02, 0.0), JOINT, layers)  # hip joint
		_box(thigh, Vector3(0.03, 0.36, 0.04), Vector3(side * 0.1, -0.22, 0.0), STRUT, layers)
		_box(thigh, Vector3(0.06, 0.06, 0.06), Vector3(side * 0.1, -0.45, 0.0), JOINT, layers)  # knee hinge
		_box(shin, Vector3(0.03, 0.38, 0.04), Vector3(side * 0.095, -0.22, 0.0), STRUT, layers)
		_box(shin, Vector3(0.12, 0.035, 0.14), Vector3(0.0, -0.4, 0.0), JOINT, layers)  # ankle cuff
		# Shoulder actuator pylon, up over the shoulder from the spine pack. Captain, 2026-10-16
		# ("these weird things V", a screenshot of the old strut+cap reading as a disconnected V):
		# one straight column, its base overlapping the pack and its cap stacked directly on top
		# (same footprint, no forward jut) rather than two misaligned pieces.
		_box(model.torso, Vector3(0.1, 0.26, 0.08), Vector3(side * 0.09, 0.4, 0.195), STRUT, layers)
		_box(model.torso, Vector3(0.11, 0.035, 0.09), Vector3(side * 0.09, 0.535, 0.195), JOINT, layers)
		# Captain, 2026-10-16 ("way better but we still need something that goes from the shoulder
		# point to the back"): a strap over the top of the shoulder, from the pylon down to the
		# front of the chest - on the torso (not the arm), so it reads right in any arm pose, the
		# way a real backpack strap rests on the shoulder rather than binding to the arm itself.
		_box(model.torso, Vector3(0.07, 0.05, 0.22), Vector3(side * 0.08, 0.57, 0.08), STRUT, layers)
		_box(model.torso, Vector3(0.06, 0.16, 0.055), Vector3(side * 0.08, 0.47, -0.04), STRUT, layers)
	# Spine power pack, the hip belt round the waist, the status light.
	_box(model.torso, Vector3(0.16, 0.36, 0.07), Vector3(0.0, 0.3, 0.2), JOINT, layers)
	_box(model.torso, Vector3(0.12, 0.3, 0.02), Vector3(0.0, 0.3, 0.237), STRUT, layers)
	# Captain, 2026-10-16 ("the hip/waist area shouldn't be a flat pane"): a proper belt, built
	# from front, back and side plates round the waist, not one flat slab spanning it.
	_box(model.torso, Vector3(0.34, 0.09, 0.055), Vector3(0.0, 0.03, -0.11), JOINT, layers)  # front
	_box(model.torso, Vector3(0.34, 0.09, 0.055), Vector3(0.0, 0.03, 0.1), JOINT, layers)  # back
	for side: float in [1.0, -1.0]:
		_box(model.torso, Vector3(0.055, 0.09, 0.22), Vector3(side * 0.165, 0.03, 0.0), JOINT, layers)  # side plate
	# Captain, 2026-10-16 ("and the back to the hips"): a spine strut down the lower back, closing
	# the gap between the power pack's base and the belt's back plate.
	_box(model.torso, Vector3(0.1, 0.1, 0.12), Vector3(0.0, 0.07, 0.15), STRUT, layers)
	var light := _box(model.torso, Vector3(0.025, 0.025, 0.012), Vector3(0.0, 0.43, 0.25), LIGHT_OFF if disabled else LIGHT_ON, layers)
	var lm := light.material_override as StandardMaterial3D
	lm.emission_enabled = true
	lm.emission = lm.albedo_color
	lm.emission_energy_multiplier = 1.5


static func _box(parent: Node3D, size: Vector3, at: Vector3, colour: Color, layers: int) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = PART_NAME
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.55
	mat.metallic = 0.5
	m.material_override = mat
	m.position = at
	m.layers = layers
	parent.add_child(m, true)  # readable unique names (ExoFramePart2, ...): dress finds them again by pattern
	return m
