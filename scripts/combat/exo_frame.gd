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
## - Armour pads (Captain, 2026-10-16: "they'll use the armor chipping system we already use,
##   be Steel III++ rated and absorb all spall"): its "pads" (shoulders, forearms, thighs,
##   shins, stomach, spine pack) are real armour, VoxelArmor pieces on the body like plates
##   (GearRig), with the frame's "pad_armor" stats (steel III++: ArmorRules dents, wear-through
##   and integrity). A pad that stops a round lands an impact on the part under it; one the
##   round gets through lets it on into the body. They're spall-coated (they throw none), and
##   the frame's "spall_cover" keeps a plate's spall off the arms and neck. Working or not,
##   the pads still protect.
## Its integrity lives in the slot's state ("hp"; "disabled"; each pad's chips and integrity
## under "pads"), so it travels with the item and every peer sees it (Inventory.net_state).
## Numbers proposed.

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


static var _pad_items: Dictionary = {}  # "<frame id>:<pad id>" -> ItemData


## The pads of `frame` (its stats' "pads"): [{"id", "part" (a Vitals part), "item" (an
## ItemData with the frame's "pad_armor" stats and the pad's shape, "outer" walls turned to
## the limb's own side), "at" (Transform3D on the part's bone, CharacterModel.part_node)}].
static func pad_items(frame: ItemData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if frame == null:
		return out
	for spec: Dictionary in frame.stats.get("pads", []):
		var key := "%s:%s" % [frame.id, spec.id]
		if not _pad_items.has(key):
			var stats: Dictionary = (frame.stats.get("pad_armor", {}) as Dictionary).duplicate(true)
			for k: String in spec:
				if not k in ["id", "part", "at", "facing", "tilt_deg"]:
					stats[k] = spec[k]
			var side := "-x" if String(spec.part).ends_with("_l") else "+x"
			stats["walls"] = (spec.get("walls", []) as Array).map(func(w: String) -> String: return side if w == "outer" else w)
			stats["thickness_vox"] = int(stats.get("thickness_vox", 2))
			_pad_items[key] = ItemData.from_dict({"id": key, "name": "%s pad" % frame.name, "type": "plate", "stats": stats})
		var at: Array = spec.get("at", [0, 0, 0])
		var basis := Basis(Vector3.UP, PI) if spec.get("facing", "front") == "back" else Basis.IDENTITY
		basis = basis * Basis(Vector3.RIGHT, deg_to_rad(float(spec.get("tilt_deg", 0.0))))  # (+: its top lies back)
		out.append({"id": String(spec.id), "part": StringName(spec.part), "item": _pad_items[key],
			"at": Transform3D(basis, Vector3(float(at[0]), float(at[1]), float(at[2])))})
	return out


## The state of pad `pad` of the frame `inventory` wears (its chips and integrity).
static func pad_state(inventory: Inventory, pad: String) -> Dictionary:
	return inventory.state_of(SLOT).get("pads", {}).get(pad, {}) if inventory else {}


## Body areas (ArmorRules.SPALL_AREAS) the worn frame keeps spall off.
static func spall_cover(inventory: Inventory) -> Array:
	var item := worn(inventory)
	return item.stats.get("spall_cover", []) if item else []


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


## How much higher a working frame's legs climb (m over SoldierMovement's mantle reach), 0
## otherwise.
static func climb_assist_m(inventory: Inventory) -> float:
	return float(worn(inventory).stats.get("climb_assist_m", 0.0)) if working(inventory) else 0.0


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
## Captain, 2026-10-17 ("tone the light sand robotic feel down"): dark, matte, close to the kit.
const STRUT := Color("464a45")
const JOINT := Color("262826")
## The actuators' bare metal (pistons, hinge drums).
const PISTON := Color("767a74")
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
		# The struts ride on the outside of the armour pads (pad_items, GearRig), bolted over them.
		_box(upper, Vector3(0.02, 0.26, 0.028), Vector3(side * 0.091, -0.15, 0.0), STRUT, layers)
		# Captain, 2026-10-17 ("go back to AW a bit more"): a more mechanical, exposed frame - hinge
		# drums at the elbows, hips and knees, pistons along the struts, stirrups under the boots
		# and a jointed spine on the back.
		_drum(upper, 0.024, 0.05, Vector3(side * 0.085, -0.31, 0.0), JOINT, layers)  # elbow drum
		_rod(upper, 0.008, 0.2, Vector3(side * 0.091, -0.17, 0.026), PISTON, layers)
		# Captain, 2026-10-16 ("connected arm to shoulder"): a shoulder joint housing at the arm's
		# own pivot (part_node's origin), so it always sits at the joint as the arm swings, bridging
		# the upper-arm strut up to the torso-mounted pylon above it.
		_box(upper, Vector3(0.055, 0.08, 0.055), Vector3(side * 0.072, 0.02, 0.0), JOINT, layers)
		_box(fore, Vector3(0.018, 0.19, 0.024), Vector3(side * 0.085, -0.11, 0.0), STRUT, layers)
		_box(fore, Vector3(0.075, 0.022, 0.075), Vector3(0.0, -0.2, 0.0), JOINT, layers)  # wrist cuff
		_rod(fore, 0.007, 0.15, Vector3(side * 0.085, -0.1, 0.022), PISTON, layers)
		_drum(thigh, 0.032, 0.05, Vector3(side * 0.1, -0.02, 0.0), JOINT, layers)  # hip drum
		_box(thigh, Vector3(0.022, 0.36, 0.03), Vector3(side * 0.101, -0.22, 0.0), STRUT, layers)
		_drum(thigh, 0.03, 0.05, Vector3(side * 0.1, -0.45, 0.0), JOINT, layers)  # knee drum
		_rod(thigh, 0.01, 0.28, Vector3(side * 0.101, -0.24, 0.03), PISTON, layers)
		_box(shin, Vector3(0.022, 0.38, 0.03), Vector3(side * 0.092, -0.22, 0.0), STRUT, layers)
		_box(shin, Vector3(0.105, 0.026, 0.12), Vector3(0.0, -0.4, 0.0), JOINT, layers)  # ankle cuff
		_rod(shin, 0.009, 0.26, Vector3(side * 0.092, -0.21, 0.028), PISTON, layers)
		_box(shin, Vector3(0.022, 0.05, 0.03), Vector3(side * 0.092, -0.435, 0.0), STRUT, layers)  # down to the stirrup
		_box(shin, Vector3(0.11, 0.012, 0.2), Vector3(0.0, -0.466, -0.005), JOINT, layers)  # stirrup under the boot
		# Shoulder actuator pylon, up over the shoulder from the spine pack. Captain, 2026-10-16
		# ("these weird things V", a screenshot of the old strut+cap reading as a disconnected V):
		# one straight column, its base overlapping the pack and its cap stacked directly on top
		# (same footprint, no forward jut) rather than two misaligned pieces.
		_box(model.torso, Vector3(0.07, 0.24, 0.06), Vector3(side * 0.085, 0.4, 0.19), STRUT, layers)
		_box(model.torso, Vector3(0.08, 0.03, 0.07), Vector3(side * 0.085, 0.525, 0.19), JOINT, layers)
		# Captain, 2026-10-16 ("way better but we still need something that goes from the shoulder
		# point to the back"): a strap over the top of the shoulder, from the pylon down to the
		# front of the chest - on the torso (not the arm), so it reads right in any arm pose, the
		# way a real backpack strap rests on the shoulder rather than binding to the arm itself.
		_box(model.torso, Vector3(0.05, 0.035, 0.2), Vector3(side * 0.085, 0.565, 0.08), STRUT, layers)
		_box(model.torso, Vector3(0.045, 0.14, 0.04), Vector3(side * 0.085, 0.47, -0.035), STRUT, layers)
	# Spine power pack (its armour pad, "spine", covers its back face), the hip belt round the
	# waist, the status light.
	_box(model.torso, Vector3(0.14, 0.34, 0.06), Vector3(0.0, 0.3, 0.195), JOINT, layers)
	# Captain, 2026-10-16 ("the hip/waist area shouldn't be a flat pane"): a proper belt, built
	# from front, back and side plates round the waist, not one flat slab spanning it.
	_box(model.torso, Vector3(0.32, 0.07, 0.035), Vector3(0.0, 0.03, -0.105), JOINT, layers)  # front
	_box(model.torso, Vector3(0.32, 0.07, 0.035), Vector3(0.0, 0.03, 0.098), JOINT, layers)  # back
	for side: float in [1.0, -1.0]:
		_box(model.torso, Vector3(0.035, 0.07, 0.2), Vector3(side * 0.16, 0.03, 0.0), JOINT, layers)  # side plate
	# Captain, 2026-10-16 ("and the back to the hips"): a spine strut down the lower back, closing
	# the gap between the power pack's base and the belt's back plate.
	_box(model.torso, Vector3(0.08, 0.1, 0.1), Vector3(0.0, 0.07, 0.15), STRUT, layers)
	for i in 6:  # the jointed spine, down the spine pack's armour
		_box(model.torso, Vector3(0.07, 0.04, 0.025), Vector3(0.0, 0.14 + i * 0.06, 0.288), JOINT, layers)
	var light := _box(model.torso, Vector3(0.025, 0.025, 0.012), Vector3(0.0, 0.5, 0.29), LIGHT_OFF if disabled else LIGHT_ON, layers)
	var lm := light.material_override as StandardMaterial3D
	lm.emission_enabled = true
	lm.emission = lm.albedo_color
	lm.emission_energy_multiplier = 1.5


## A piston rod (a cylinder along the bone, Y).
static func _rod(parent: Node3D, radius: float, length: float, at: Vector3, colour: Color, layers: int) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 8
	cm.rings = 1
	return _part(parent, cm, at, Basis.IDENTITY, colour, layers)


## A hinge drum (a short cylinder across the joint, X).
static func _drum(parent: Node3D, radius: float, width: float, at: Vector3, colour: Color, layers: int) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = width
	cm.radial_segments = 12
	cm.rings = 1
	return _part(parent, cm, at, Basis(Vector3.FORWARD, PI / 2), colour, layers)


static func _part(parent: Node3D, mesh: Mesh, at: Vector3, basis: Basis, colour: Color, layers: int) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = PART_NAME
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.45
	mat.metallic = 0.6
	m.material_override = mat
	m.transform = Transform3D(basis, at)
	m.layers = layers
	parent.add_child(m, true)
	return m


## First person (Captain, 2026-10-17: "make sure exo armor is visible in the first person
## view"): the frame's forearm pad, strut, piston and wrist cuff on a view-model forearm
## (PlayerInput._update_view_model), the right or left one, in the wearer's kit colour `cover`.
## Art only: rounds meet the body's own pads (GearRig).
static func dress_view_forearm(forearm: Node3D, frame: ItemData, right: bool, cover: Color) -> void:
	if frame == null:
		return
	var side := 1.0 if right else -1.0
	for pad: Dictionary in pad_items(frame):
		if pad.part == (Vitals.FOREARM_R if right else Vitals.FOREARM_L):
			var holder := Node3D.new()
			holder.name = PART_NAME
			holder.transform = pad.at
			holder.add_child(VoxelArmor.make_mesh_instance(pad.item, 1, cover))
			forearm.add_child(holder)
	_box(forearm, Vector3(0.018, 0.19, 0.024), Vector3(side * 0.085, -0.11, 0.0), STRUT, 1)
	_rod(forearm, 0.007, 0.15, Vector3(side * 0.085, -0.1, 0.022), PISTON, 1)
	_box(forearm, Vector3(0.075, 0.022, 0.075), Vector3(0.0, -0.2, 0.0), JOINT, 1)  # wrist cuff


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
