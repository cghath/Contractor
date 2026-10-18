class_name WorldItem
extends RigidBody3D
## An item lying in the world. Spawned by the level's ItemSpawner on the host and
## replicated to every peer; only the host simulates physics, clients follow the synced
## transform.
## Plates and helmets lie here as their real VoxelArmor piece, which is a hit target like
## worn armor: a round that hits it is traced through its voxels, dents or holes it and is
## stopped or passes, and the damage goes into `state` (replicated, and saved with the zone).
## Items move with continuous collision, so a thin plate landing flat can't sink below the
## ground or drop through a voxel surface out of reach.

const GROUP := &"world_items"
## How far above the top of an item its interaction point sits (metres), so an item lying
## flat, or pressed slightly into the ground, can still be seen and picked up.
const ACTION_POINT_LIFT := 0.03

var item_id: StringName
var count := 1
## Item state that travels with it (rounds, armor chips); see ItemData.default_state.
## Replicated; on a plate or helmet a change redraws its damage.
var state: Dictionary = {}:
	set(value):
		state = value
		if _armor:
			_armor.apply_damage(state.get("chips", []), ArmorRules.is_shattered(state))
		if _suit:
			ExoMech.show_parked_damage(_suit, state)
## Stable id for persistence (see GameState). Also used as the node name.
var uid := ""

var _armor: VoxelArmor   # the piece shown, for a plate or helmet
var _suit: Node3D        # a heavy exo left standing (ExoMech.parked_node)
var _box: BoxShape3D


func _init() -> void:
	collision_layer = 1 << 2
	collision_mask = 1 | (1 << 2)
	continuous_cd = true  # thin plates landing flat at speed sank under the ground or fell through voxels
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	for prop: NodePath in [^".:position", ^".:rotation", ^".:count", ^".:state"]:
		config.add_property(prop)
		config.property_set_spawn(prop, true)
		config.property_set_replication_mode(prop, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	sync.replication_config = config
	add_child(sync)


func _ready() -> void:
	add_to_group(GROUP)
	freeze = not multiplayer.is_server()
	var item := ItemDB.get_item(item_id)
	var is_armor := item.type == "plate" or item.slot == &"helmet"
	var size := visual_size(item)
	if ExoMech.is_mech(item):
		# A heavy exo stands where its pilot left it, open, facing the way he faced (ExoMech):
		# never tumbling, its plates still armour a round can hit.
		freeze = true
		rotation = Vector3(0.0, float(state.get("yaw", rotation.y)), 0.0)
		_suit = ExoMech.parked_node(item, state, self)
		add_child(_suit)
		size = ExoMech.parked_size(state)
	elif is_armor:
		# The real voxel piece, with any damage it carries; rounds hit it (see server_add_armor_hit).
		size = VoxelArmor.size_m(item)
		var piece := VoxelArmor.new()
		add_child(piece)
		piece.setup(item, &"", null, 1)
		piece.position = -VoxelArmor.center_offset(item)  # centred, like the collision box
		_armor = piece
		piece.apply_damage(state.get("chips", []), ArmorRules.is_shattered(state))
	else:
		# Its ground model (ItemArt), lying as it rests; the collision box is the model's bounds.
		add_child(ItemArt.ground_node(item, state))  # a rifle shows the optic it carries (P0362)
		size = ItemArt.ground_size(item, state)
	var shape := CollisionShape3D.new()
	_box = BoxShape3D.new()
	_box.size = size
	shape.shape = _box
	add_child(shape)
	mass = maxf(item.mass_kg, 0.1)


## Where the interaction menu puts this item's action point: just above the top of its box
## as it lies (in any orientation), so the sight check isn't blocked by the floor it rests on.
func action_point() -> Vector3:
	if _box == null:
		return global_position
	if _suit:
		return ExoMech.parked_point(self)  # at the open cockpit
	var b := global_basis
	var half := _box.size * 0.5
	var up := absf(b.x.y) * half.x + absf(b.y.y) * half.y + absf(b.z.y) * half.z
	return global_position + Vector3.UP * (up + ACTION_POINT_LIFT)


## Host only. Records a hit on the plate or helmet lying here (VoxelArmor._record_hit): its
## chip, plus whatever else the hit changed (a ceramic plate's cracks and integrity). The new
## state replicates to every peer (Sync), redraws the damage, and is saved with the zone: a
## level-placed item becomes a dropped one, so it comes back damaged instead of new.
func server_add_armor_hit(chip: Array, changes: Dictionary, pad := "") -> void:
	var next := state.duplicate(true)  # a new Dictionary, so Sync sees the change
	var pads: Dictionary = next.get("pads", {})
	var piece: Dictionary = pads.get(pad, {}) if pad != "" else next  # a parked heavy exo's plate (ExoMech): under "pads"
	var chips: Array = piece.get("chips", [])
	chips.append(chip)
	piece["chips"] = chips
	piece.merge(changes, true)
	if pad != "":
		pads[pad] = piece
		next["pads"] = pads
	state = next
	if uid == "":
		return
	if not GameState.dropped.has(uid):
		GameState.item_taken(uid)
		GameState.item_dropped(uid, item_id, count, global_position, state.duplicate(true))
	else:
		GameState.dropped[uid]["state"] = state.duplicate(true)


func describe() -> String:
	var item := ItemDB.get_item(item_id)
	if ExoMech.is_mech(item):
		return ExoMech.describe(item, state)
	var verb := "Carry" if item.two_handed else "Take"
	var amount := " x%d" % count if count > 1 else ""
	var detail := ""
	if state.has("rounds"):
		var optic := GunAttachments.label_with_optic(item, state)  # what's on its rail (P0362), grip and light (S3)
		detail = "  [%d rds%s]" % [int(state.rounds), ", " + optic if optic != "" else ""]
	elif not state.get("molle", {}).is_empty():
		detail = "  [%d attached]" % state.molle.size()  # a carrier keeps its pouches
	elif not state.get("held", []).is_empty():
		detail = "  [%d inside]" % state.held.reduce(func(a: int, e: Dictionary) -> int: return a + int(e.count), 0)
	elif item.is_voxel_armor():
		var damage := ArmorRules.state_text(item, state)  # "3 cracks, 46%", "shattered"...
		if damage != "":
			detail = "  [%s]" % damage
	var mass := Inventory.entry_mass({"id": item_id, "count": count, "state": state})
	return "%s %s%s%s   %.1f L  %.1f kg" % [verb, item.name, amount, detail, item.volume_l * count, mass]


## Placeholder box size: explicit `size_m` from item stats, else a cube of the item's volume.
static func visual_size(item: ItemData) -> Vector3:
	if item.stats.has("size_m"):
		var s: Array = item.stats["size_m"]
		return Vector3(s[0], s[1], s[2])
	var edge := pow(maxf(item.volume_l, 0.05) / 1000.0, 1.0 / 3.0)
	return Vector3.ONE * edge


static func color_for(item: ItemData) -> Color:
	match item.type:
		"weapon": return Color("2b2b2b")
		"ammo": return Color("b08d3c")
		"armor", "plate": return Color("5b6650")
		"backpack": return Color("6e5b3e")
		"medical": return Color("c23b3b")
		"utility": return Color("3f5f7a")
		"objective": return Color("d9a400")
		"valuable": return Color("c9a443")
		"intel": return Color("d2b77c")
		_: return Color("8a8a8a")
