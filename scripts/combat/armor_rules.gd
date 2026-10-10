class_name ArmorRules
extends RefCounted
## How armor behaves, on top of the voxels (which stay the visible damage and still let a
## round through a hole). Every round has a threat level and every vest, plate and helmet a
## rating on the same ladder (Ballistics.LEVELS); armor stops a round when its rating is at
## or above the round's level. Materials then fail in their own way:
##
## - Ceramic: each hit cracks a zone around it; a later hit inside cracked zones is less
##   likely to be stopped. Each hit also takes integrity by round class; at zero the plate
##   has shattered and stops nothing. Cracks and integrity are the plate's item state.
## - Steel: doesn't crack (holes only, from the chips), but now and then a stopped round
##   throws spall that scratches (rarely lightly wounds) the neck, face or arms where the
##   vest doesn't cover them.
## - Polyethylene: deforms; repeated hits in one spot let rounds through (the chips).
## - Composite (helmets): rating and chips only.
##
## Vests are aramid soft armor: they stop fragments and rounds up to their own rating where
## they cover the body (light: chest front; medium: chest and abdomen front and back; heavy:
## also the sides), even behind a failed plate.
##
## All numbers here are the design doc's proposed starting values, to tune in playtests.

const CERAMIC := &"ceramic"
const STEEL := &"steel"
const POLYETHYLENE := &"polyethylene"
const COMPOSITE := &"composite"

## Which way a round meets the body (relative to its facing).
const FRONT := &"front"
const BACK := &"back"
const SIDE := &"side"
## A round counts as front (or back) within 60 degrees of straight on; otherwise side.
const FRONT_BACK_COS := 0.5

## Ceramic: radius of the cracked zone around a hit (1 cm voxels), and the stop chance left
## per earlier hit inside it (0.7 = cut by 30% each).
const CRACK_RADIUS_VOX := 5.0
const CRACK_STOP_MULT := 0.7
## Ceramic integrity (1 = new) each hit takes, by round class.
const INTEGRITY_LOSS := {
	Vitals.FRAGMENT: 0.02, Vitals.PISTOL: 0.08, Vitals.INTERMEDIATE: 0.18, Vitals.FULL_POWER: 0.3,
}

## Steel spall (Captain's playtest call: rare and minor): the chance a stopped round throws
## spall that reaches the wearer, by round class, and then exactly one wound (WoundModel's
## SPALL class: a scratch, now and then a light wound) on a body area it can reach (a vest's
## "spall_cover" names the areas it protects).
const SPALL_CHANCE := {
	Vitals.FRAGMENT: 0.0, Vitals.PISTOL: 0.05, Vitals.INTERMEDIATE: 0.1, Vitals.FULL_POWER: 0.2,
}
const SPALL_AREAS := {
	&"neck": [Vitals.NECK],
	&"face": [Vitals.FACE],
	&"arms": [Vitals.UPPER_ARM_L, Vitals.UPPER_ARM_R, Vitals.FOREARM_L, Vitals.FOREARM_R],
}

## Torso-local heights (CharacterModel torso: pivot at the hips, top at 0.56) that split a
## whole-torso hit into parts, and the half-width beyond which it's an arm.
const TORSO_TOP := 0.62
const CHEST_FROM := 0.30
const ABDOMEN_FROM := 0.10
const PELVIS_FROM := -0.12
const TORSO_HALF_WIDTH := 0.2

static var _rng: RandomNumberGenerator


# --- Ratings ------------------------------------------------------------------------------

## The rating of a plate or helmet (a Ballistics.LEVELS name), or &"" if it has none.
static func rating(item: ItemData) -> StringName:
	return StringName(item.stats.get("rating", ""))


## The rating of a vest's soft armor (its aramid), or &"" if it has none.
static func soft_rating(vest: ItemData) -> StringName:
	return StringName(vest.stats.get("soft_rating", "")) if vest else &""


## True if armor rated `armor_rating` stops a round of `threat` (at or above it on the ladder).
static func stops(armor_rating: StringName, threat: StringName) -> bool:
	var r := Ballistics.level_index(armor_rating)
	var t := Ballistics.level_index(threat)
	return r >= 0 and t >= 0 and r >= t


static func material(item: ItemData) -> StringName:
	return StringName(item.stats.get("material", COMPOSITE if item.slot == &"helmet" else STEEL))


# --- Plate state (item state: "chips", plus "cracks" and "integrity" on ceramic) -----------

## Remaining ceramic integrity, 1 (new) to 0 (shattered). Missing means undamaged.
static func integrity(state: Dictionary) -> float:
	return float(state.get("integrity", 1.0))


static func is_shattered(state: Dictionary) -> bool:
	return integrity(state) <= 0.0


## Crack centres ([x, y, z] voxel cells) in a ceramic plate.
static func cracks(state: Dictionary) -> Array:
	return state.get("cracks", [])


## Earlier hits whose cracked zone covers `cell`.
static func cracks_near(state: Dictionary, cell: Vector3i) -> int:
	var n := 0
	for crack: Array in cracks(state):
		if Vector3(cell).distance_to(Vector3(float(crack[0]), float(crack[1]), float(crack[2]))) <= CRACK_RADIUS_VOX:
			n += 1
	return n


## Chance that a ceramic plate in `state` stops a round (rated for it) landing on `cell`.
static func ceramic_stop_chance(state: Dictionary, cell: Vector3i) -> float:
	return pow(CRACK_STOP_MULT, cracks_near(state, cell))


static func integrity_loss(round_class: StringName) -> float:
	return float(INTEGRITY_LOSS.get(round_class, INTEGRITY_LOSS[Vitals.INTERMEDIATE]))


## Host only. Whether the plate or helmet `item` (with item state `state`) stops a round of
## `threat` landing on voxel `cell` (where the round met material, not a hole). Rolls the
## ceramic crack chance.
static func piece_stops(item: ItemData, state: Dictionary, cell: Vector3i, threat: StringName) -> bool:
	if is_shattered(state) or not stops(rating(item), threat):
		return false
	if material(item) == CERAMIC:
		return roll(ceramic_stop_chance(state, cell))
	return true


## The item-state keys a hit on `cell` changes (merged by Inventory.add_armor_hit): a ceramic
## plate gains a crack there and loses integrity by round class. {} for other materials.
static func hit_changes(item: ItemData, state: Dictionary, cell: Vector3i, round_class: StringName) -> Dictionary:
	if material(item) != CERAMIC:
		return {}
	var list := cracks(state).duplicate()
	list.append([cell.x, cell.y, cell.z])
	return {"cracks": list, "integrity": maxf(integrity(state) - integrity_loss(round_class), 0.0)}


## A few words on a piece's damage for prompts and labels: "3 cracks, 46%", "shattered",
## "damaged: 2 hits", or "" when it's undamaged.
static func state_text(item: ItemData, state: Dictionary) -> String:
	if item and material(item) == CERAMIC and (state.has("integrity") or state.has("cracks")):
		if is_shattered(state):
			return "shattered"
		var n := cracks(state).size()
		return "%d crack%s, %d%%" % [n, "" if n == 1 else "s", roundi(integrity(state) * 100.0)]
	var chips: Array = state.get("chips", [])
	return "damaged: %d hits" % chips.size() if not chips.is_empty() else ""


# --- Fit -----------------------------------------------------------------------------------

## True if `plate` goes in `carrier`'s plate pockets: the plate's "fits" names carrier tiers
## (light plates fit only the light carrier; medium and heavy plates fit both bigger ones).
static func plate_fits(plate: ItemData, carrier: ItemData) -> bool:
	if carrier == null:
		return false
	var fits: Array = plate.stats.get("fits", [])
	return fits.is_empty() or String(carrier.stats.get("tier", "")) in fits


## "light carriers", "medium and heavy carriers"... for fit messages.
static func fits_text(plate: ItemData) -> String:
	var fits: Array = plate.stats.get("fits", [])
	return "%s carrier%s" % [" and ".join(PackedStringArray(fits)), "" if fits.size() == 1 else "s"]


# --- Soft armor and spall --------------------------------------------------------------------

## The Inventory of a body (a Soldier or TargetDummy), or null.
static func inventory_of(body: Node) -> Inventory:
	return body.get_node_or_null(^"Inventory") as Inventory if body else null


## The vest `body` wears, or null.
static func vest_of(body: Node) -> ItemData:
	var inventory := inventory_of(body)
	if inventory == null or inventory.slots.get(&"vest", &"") == &"":
		return null
	return ItemDB.get_item(inventory.slots[&"vest"])


## Which way a round travelling along `direction` meets `body`: FRONT, BACK or SIDE.
static func facing(body: Node3D, direction: Vector3) -> StringName:
	var forward := -body.global_basis.z
	forward.y = 0.0
	var travel := direction
	travel.y = 0.0
	if forward.length_squared() < 0.0001 or travel.length_squared() < 0.0001:
		return FRONT  # straight down or up: the vest's shoulders and front take it
	var d := travel.normalized().dot(forward.normalized())
	if d <= -FRONT_BACK_COS:
		return FRONT
	if d >= FRONT_BACK_COS:
		return BACK
	return SIDE


## The torso part (Vitals.CHEST, ABDOMEN or PELVIS) at world `position` on `body`, or &"" if
## it's outside the torso (head, arms, legs). Used for whole-torso hitboxes and plate stops.
static func torso_part_at(body: Node3D, position: Vector3) -> StringName:
	var model := body.get_node_or_null(^"Model") as CharacterModel
	var local: Vector3
	if model and model.torso:
		local = model.torso.to_local(position)
	else:
		local = body.to_local(position) - CharacterModel.TORSO_PIVOT
	if absf(local.x) > TORSO_HALF_WIDTH or local.y > TORSO_TOP or local.y < PELVIS_FROM:
		return &""
	if local.y >= CHEST_FROM:
		return Vitals.CHEST
	if local.y >= ABDOMEN_FROM:
		return Vitals.ABDOMEN
	return Vitals.PELVIS


## The finer part a hit on `part` means for armor: a whole-torso hit (Vitals.TORSO) is split
## by height when its `position` is known, else counted as chest.
static func armor_part(body: Node3D, part: StringName, position := Vector3.INF) -> StringName:
	if part != Vitals.TORSO:
		return part
	if position == Vector3.INF or body == null:
		return Vitals.CHEST
	return torso_part_at(body, position)


## True if `vest`'s aramid covers `part` (a Vitals body part) from `face` (FRONT, BACK, SIDE).
static func soft_covers(vest: ItemData, part: StringName, face: StringName) -> bool:
	if vest == null or soft_rating(vest) == &"":
		return false
	return String(part) in vest.stats.get("soft_parts", []) and String(face) in vest.stats.get("soft_faces", [])


## Body parts steel spall can reach under `vest` (null = no vest): every spall area the vest's
## "spall_cover" doesn't name.
static func spall_parts(vest: ItemData) -> Array[StringName]:
	var covered: Array = vest.stats.get("spall_cover", []) if vest else []
	var parts: Array[StringName] = []
	for area: StringName in SPALL_AREAS:
		if not String(area) in covered:
			for part: StringName in SPALL_AREAS[area]:
				parts.append(part)
	return parts


## Chance a stopped round of `round_class` throws spall that reaches the wearer.
static func spall_chance(round_class: StringName) -> float:
	return float(SPALL_CHANCE.get(round_class, SPALL_CHANCE[Vitals.INTERMEDIATE]))


## Host only. Spall from a round of `round_class` a steel plate stopped at `position`: with
## spall_chance, one spall wound (Vitals.server_hit with WoundModel.SPALL: a scratch, now and
## then a light wound) on a part `body`'s vest leaves exposed. Returns the parts hit (none
## or one).
static func server_spall(body: Node3D, vitals: Vitals, position: Vector3, direction: Vector3, round_class := Vitals.INTERMEDIATE) -> Array[StringName]:
	var hit: Array[StringName] = []
	var vest := vest_of(body)
	var covered: Array = vest.stats.get("spall_cover", []) if vest else []
	var areas: Array[StringName] = []
	for area: StringName in SPALL_AREAS:
		if not String(area) in covered:
			areas.append(area)
	if areas.is_empty() or vitals == null or not roll(spall_chance(round_class)):
		return hit
	var rng := _get_rng()
	var parts: Array = SPALL_AREAS[areas[rng.randi_range(0, areas.size() - 1)]]
	var part: StringName = parts[rng.randi_range(0, parts.size() - 1)]
	vitals.server_hit(part, {
		"round_class": WoundModel.SPALL,
		"position": position,
		"direction": -direction,  # spall sprays back off the strike face
		"distance": 0.3,
		"spall": true,
	})
	hit.append(part)
	return hit


# --- Chance ----------------------------------------------------------------------------------

## True with probability `chance`.
static func roll(chance: float) -> bool:
	if chance >= 1.0:
		return true
	if chance <= 0.0:
		return false
	return _get_rng().randf() < chance


## Makes the armor rolls repeatable (tests).
static func seed_rng(value: int) -> void:
	_get_rng().seed = value


static func _get_rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng
