class_name GearRig
extends Node3D
## Puts what an Inventory is wearing onto a CharacterModel. Gear is voxel art (VoxelArt)
## mounted on the model's torso or head so it follows the animation; items without a
## voxel model yet fall back to a coloured box. Plates and helmets are VoxelArmor nodes:
## destructible 1 cm voxels that are also the hit targets.
##
## Hands: the weapon the model holds (CharacterModel.hold) is drawn from its sling or
## holster (the hand goes to it first, CharacterModel.start_draw) and goes back there while
## the hands are busy with a casualty or an action (CharacterModel.hands_busy). Both follow
## replicated state, so every peer sees the same.

@export var inventory: Inventory
@export var model: CharacterModel
## Render layers for gear meshes. The local player's camera hides LOCAL_ONLY so your own
## kit doesn't block your view.
@export_flags_3d_render var render_layers := 1:
	set(value):
		render_layers = value
		if is_node_ready():
			_clear()
			_rebuild()

## Armor slots that become VoxelArmor nodes, with HUD names.
const ARMOR_SLOTS := {
	&"plate_front": "Front", &"plate_back": "Back", &"plate_left": "Left", &"plate_right": "Right", &"helmet": "Helmet",
}
## Torso-local plate centre heights (torso pivot is at the hips; torso spans y 0-0.56).
const PLATE_HEIGHT := 0.33
const SIDE_PLATE_HEIGHT := 0.28
## Where a helmet's pivot (the centre of its dome base) sits, head-local.
const HELMET_POSITION := Vector3(0, 0.2, 0)
## A tourniquet's band and the red of medical pull tabs, as drawn on the carrier.
const TQ_BAND := Color("1b1b1a")
const MED_RED := Color("b3261e")
## Torso height (m, before carrier_fit) of a worn pack's middle.
const PACK_CENTRE_Y := 0.3
## How deep an aid bag strapped on a pack is drawn (_pack_bag_size).
const AID_BAG_DEPTH_M := 0.12
## Rest mounts, torso-local, for a right-handed shooter (rest_transform mirrors them for a
## left-handed one): the vest at the cummerbund; the primary on its sling in the patrol
## carry, diagonally across the front of the carrier clear of the pouches (stock up under the
## firing-side armpit, muzzle down at the support-side thigh), lying flat on its side against
## the chest: ejection port out, magazine down towards the firing-side hip. The sidearm is in
## a thigh holster on the firing side.
const MOUNTS := [&"vest", &"primary", &"sidearm"]
const SLING_CENTRE := Vector3(0.02, 0.2, -0.21)
const SLING_DIR := Vector3(-0.5, -0.866, 0.0)  # where the muzzle points: 30 degrees off vertical
const HOLSTER := Vector3(0.22, 0.02, -0.02)
## Held weapons, in CharacterModel.hands_anchor space (shoulder height, pitches with aim),
## for a right-handed shooter (mirrored for a left-handed one):
## - A rifle's butt (VoxelArt.butt_point) sits in the firing shoulder's pocket. Aiming, it
##   points straight out, the optic under the (dipped) eye line. At the ready, the stock stays
##   in the pocket and the muzzle dips READY_DIP and turns READY_TURN in across the body.
## - A pistol is pushed out two-handed at the eye line aiming, and held low in front of the
##   chest at the ready.
## The arms reach for the weapon's VoxelArt.hand_points, the support shoulder brought forward
## (CharacterModel.SUPPORT_REACH).
## The pockets are spots on the chest: torso-local, from hands_anchor's origin, as if the
## upper body faced the view. A rifle held two-handed blades the upper body
## (CharacterModel.BLADE) while hands_anchor turns back to the view, so held_transform turns
## the pocket with the twist and the butt stays on the same spot of the chest.
const SHOULDER_POCKET := Vector3(0.09, 0.07, -0.11)
const READY_POCKET := Vector3(0.11, 0.03, -0.11)
const READY_DIP := 0.5
const READY_TURN := 0.15
const PISTOL_AIM := Vector3(0.0, 0.16, -0.44)
const PISTOL_READY := Vector3(0.06, -0.12, -0.32)
const PISTOL_READY_DIP := 0.45
## Seated in a vehicle (CharacterModel.is_seated; Captain, 2026-10-14: the UH-60M's riders held
## their rifles pointing across the cabin): a rifle stands muzzle down between the knees, the
## butt up in front of the chest and the hands on it, pointing at the floor whichever way he
## looks (hands_anchor follows the upper body then). Proposed: the muzzle's way (hands_anchor
## space; the upper body's forward lean brings it near vertical), the butt (as the pockets
## above), and how much it may rise so the muzzle stays SEATED_MUZZLE_CLEAR off a floor near
## the seat (a low seat); a pistol points down at the floor in front.
const SEATED_DIR := Vector3(0, -0.97, -0.24)
const SEATED_BUTT := Vector3(0.0, 0.0, -0.3)
const SEATED_LIFT_MAX := 0.12
const SEATED_MUZZLE_CLEAR := 0.05
const SEATED_PISTOL := Vector3(0.06, -0.3, -0.28)
const SEATED_PISTOL_DIP := 1.2
## How fast a held weapon moves between the ready and aiming (per second).
const HOLD_EASE := 12.0
## Name tape lettering: cap height in metres, and the ink.
const TAPE_HEIGHT_M := 0.016
const TAPE_INK := Color(0.1, 0.1, 0.08)
## The tape: a strip of tan cloth on the loop panel, letters on it.
const TAPE_SIZE := Vector3(0.12, 0.028, 0.004)
const TAPE_CLOTH := Color("8f8a6c")
## The carrier's plate pocket: 14 cm either side of the spine (VoxelArt._vest). Pouches on it
## stay inside its edges, and a row of them doesn't overlap (POUCH_GAP_M apart).
const PANEL_HALF_M := 0.14
const POUCH_GAP_M := 0.004
## Pack straps: width, thickness, and how far they lie off what they rest on (m).
const STRAP_W := 0.045
const STRAP_T := 0.015
const STRAP_LIFT := 0.012
## Gear secondary motion (queue 10, GearSway): the pack swings from its strap anchors (slow,
## up to 4 cm, turning swings it out), pouches flap from their top edges (quick, 1.2 cm).
## Drawn only where something renders: headless hosts and tests keep gear still.
const PACK_SWAY := [2.4, 0.35, 0.04, 1.0, 0.25, 0.32]  # freq, damping, reach, gain, lever, hang
const POUCH_SWAY := [4.0, 0.3, 0.012, 1.0, 0.0, 0.06]

var _armor: Dictionary = {}        # slot -> VoxelArmor
var _chip_counts: Dictionary = {}  # slot -> chips already applied to the mesh
var _gear: Dictionary = {}    # key -> [item id, Node3D]
var _held_key: StringName = &""  # which _gear entry is in the hands
var _held_dirty := true
var _want_key: StringName = &""  # what should be in the hands
var _clock := 0.0
var _grab_at := -1.0             # _clock when a weapon being drawn reaches the hands
var _pouches: Node3D             # MOLLE attachments on the carrier
var _pouch_key := ""             # what _pouches shows
var _left_shown := false          # model.left_handed the rest mounts were placed for
var _straps: Node3D              # the pack's shoulder straps (torso-local)
var _carrier: ItemData          # the worn carrier (carrier_fit reads its depth and tier)
var _straps_for := ""  # the pack and carrier they were built for
var _tape: Node3D                 # the name tape on the carrier's loop panel
var _tape_key := ""              # carrier and text it shows
var _pack_sway := GearSway.make(PACK_SWAY[0], PACK_SWAY[1], PACK_SWAY[2], PACK_SWAY[3], PACK_SWAY[4], PACK_SWAY[5])
var _pouch_sway := GearSway.make(POUCH_SWAY[0], POUCH_SWAY[1], POUCH_SWAY[2], POUCH_SWAY[3], POUCH_SWAY[4], POUCH_SWAY[5])
var _pack_rest := Transform3D.IDENTITY  # the pack's place, unswung
var _pack_pivot := Vector3.ZERO         # torso-local: where it hangs from (its straps' anchors)
var _swinging: Array = []              # [node, rest Transform3D, pivot Vector3, on the pack]
var _sway_on := DisplayServer.get_name() != "headless"



func _ready() -> void:
	inventory.changed.connect(_rebuild)
	_rebuild()


## Where an armor piece sits. Plates sit on the carrier's faces, outside the 0.12 m-deep
## hitbox, strike face outward; the carrier sets how far out (heavy carriers are thicker).
static func armor_transform(slot: StringName, carrier: ItemData) -> Transform3D:
	var depth: float = carrier.stats.get("plate_depth", 0.14) if carrier else 0.14
	var side: float = carrier.stats.get("side_plate_x", 0.245) if carrier else 0.245
	match slot:
		&"plate_front": return Transform3D(Basis.IDENTITY, Vector3(0, PLATE_HEIGHT, -depth))
		&"plate_back": return Transform3D(Basis(Vector3.UP, PI), Vector3(0, PLATE_HEIGHT, depth))
		&"plate_left": return Transform3D(Basis(Vector3.UP, PI / 2), Vector3(-side, SIDE_PLATE_HEIGHT, 0))
		&"plate_right": return Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(side, SIDE_PLATE_HEIGHT, 0))
	return Transform3D(Basis.IDENTITY, HELMET_POSITION)


## Body-space position of a plate slot at rest with a medium carrier (for tests and tools).
static func plate_rest_position(slot: StringName) -> Vector3:
	return CharacterModel.TORSO_PIVOT + armor_transform(slot, null).origin


func armor_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for piece: VoxelArmor in _armor.values():
		rids.append(piece.get_rid())
	return rids


## Remaining fraction of an armor slot's protection, or -1 if nothing is worn there: the
## piece's integrity (ArmorRules, which every hit wears down), or the share of its voxels
## left if that is lower.
func armor_integrity(slot: StringName) -> float:
	var piece: VoxelArmor = _armor.get(slot)
	if piece == null:
		return -1.0
	return minf(ArmorRules.integrity(inventory.state_of(slot)), piece.integrity())


## "Front IV 64% 3 cracks  Back IV 100%  Helmet IIIA 92%" for HUDs and labels (rating, what's
## left, a ceramic plate's cracks or "shattered"); "" with no armor.
func armor_summary(separator := "  ") -> String:
	var parts := PackedStringArray()
	var frame := ExoFrame.summary(inventory)
	if frame != "":
		parts.append(frame)
	for slot: StringName in ARMOR_SLOTS:
		var integrity := armor_integrity(slot)
		if integrity < 0.0:
			continue
		var piece: VoxelArmor = _armor[slot]
		var state := inventory.state_of(slot)
		var text := "%s %s" % [ARMOR_SLOTS[slot], ArmorRules.rating(piece.item)]
		if ArmorRules.is_shattered(state):
			text += " " + ArmorRules.failed_text(piece.item)
		else:
			text += " %d%%" % roundi(integrity * 100.0)
			var cracks := ArmorRules.cracks(state).size()
			if cracks > 0:
				text += " %d crack%s" % [cracks, "" if cracks == 1 else "s"]
		parts.append(text)
	return separator.join(parts)


func _rebuild() -> void:
	var vest: StringName = inventory.slots[&"vest"]
	var carrier := ItemDB.get_item(vest) if vest != &"" else null
	_carrier = carrier
	model.set_carrier_worn(carrier != null)
	for slot: StringName in ARMOR_SLOTS:
		var id: StringName = inventory.slots[slot]
		var piece: VoxelArmor = _armor.get(slot)
		if piece and piece.item.id != id:
			piece.queue_free()
			_armor.erase(slot)
			piece = null
		if piece == null and id != &"":
			piece = VoxelArmor.new()
			(model.head if slot == &"helmet" else model.torso).add_child(piece)
			piece.setup(ItemDB.get_item(id), slot, inventory, render_layers)
			_armor[slot] = piece
			_chip_counts[slot] = 0
		if piece:
			piece.transform = armor_transform(slot, carrier)
			if slot != &"helmet":
				piece.transform = carrier_fit(String(slot).trim_prefix("plate_")) * piece.transform
			if slot != &"helmet":  # a plate sits inside the carrier's pocket, under its fabric
				piece.set_cover(Color(VoxelArt.spec(model.variant).gear) if carrier else Color(0, 0, 0, 0))
	for slot: StringName in MOUNTS:
		_set_gear(slot, inventory.slots[slot], &"torso", rest_transform(slot), inventory.state_of(slot))
	_fit_front_panel(carrier)
	var pack: StringName = inventory.slots[&"backpack"]
	var pack_size := VoxelArt.size_m(VoxelArt.model_for(ItemDB.get_item(pack))) if pack != &"" else Vector3.ZERO
	var spine := EXO_SPINE_DEPTH if inventory.slots.get(ExoFrame.SLOT, &"") != &"" else 0.0  # an exo's spine pack under it
	_pack_rest = carrier_fit("back") * Transform3D(Basis.IDENTITY, Vector3(0, PACK_CENTRE_Y, 0.165 + spine + pack_size.z * 0.5))
	_pack_pivot = carrier_fit("back") * Vector3(0, 0.3 + pack_size.y * 0.5, 0.165)
	_set_gear(&"backpack", pack, &"torso", _pack_rest)
	var held := inventory.hands
	var held_size := WorldItem.visual_size(ItemDB.get_item(held)) if held != &"" else Vector3.ZERO
	_set_gear(&"hands", held, &"torso", Transform3D(Basis.IDENTITY, Vector3(0, 0.15, -0.15 - held_size.z * 0.5)))
	_set_pouches()
	_set_pack_straps(pack)
	_set_name_tape(carrier)
	_refresh_plate_damage()
	_set_exo_frame()


## The light exo frame's struts on the body (ExoFrame.dress), rebuilt when it's put on, taken
## off, or goes from working to disabled.
const EXO_SPINE_DEPTH := 0.07
var _exo_key := ""
func _set_exo_frame() -> void:
	var item := ExoFrame.worn(inventory)
	var key := "" if item == null else "%s:%s" % [item.id, ExoFrame.working(inventory)]
	if key == _exo_key:
		return
	_exo_key = key
	ExoFrame.dress(model, item, item != null and not ExoFrame.working(inventory), render_layers)


## MOLLE attachments on the worn carrier and pack, drawn as small boxes on their attach points
## (the points' "at" and "face"; a launcher packed on top of the pack as its tube, lying
## across); rebuilt only when what's attached changes.
func _set_pouches() -> void:
	var points := inventory.attach_points()
	var key := "%s+%s" % [inventory.slots[&"vest"], inventory.slots[&"backpack"]]
	for p: Dictionary in points:
		var att := inventory.attachment(StringName(p.id))
		if not att.is_empty():
			key += "|%s=%s%s" % [p.id, att.id, "+" if not att.get("held", []).is_empty() else ""]
	if key == _pouch_key:
		return
	_pouch_key = key
	_swinging.clear()
	if _pouches:
		_pouches.queue_free()
		_pouches = null
	if inventory.attachment_count() + inventory.attachment_count(&"backpack") == 0:
		return
	_pouches = Node3D.new()
	_pouches.name = "Pouches"
	model.torso.add_child(_pouches)
	var gear := Color(VoxelArt.spec(model.variant).gear).darkened(0.12)
	var spots := pouch_spots()
	for p: Dictionary in points:
		var att := inventory.attachment(StringName(p.id))
		if att.is_empty():
			continue
		var item := ItemDB.get_item(StringName(att.id))
		var bag := _pack_bag_size(p, item)  # an aid bag strapped on the pack: in the pack's cloth
		var cloth := Color(VoxelArt.spec(model.variant).pack).darkened(0.08) if bag != Vector3.ZERO else gear
		var node := LauncherRig.make_model(item, render_layers) if item.type == "launcher" \
			else pouch_node(item, cloth, not att.get("held", []).is_empty(), render_layers, bag)
		node.name = String(p.id)
		node.transform = spots[p.id]
		_pouches.add_child(node)
		var h := WorldItem.visual_size(item).y
		var top: Vector3 = (spots[p.id] as Transform3D) * Vector3(0, h * 0.5, 0)
		_swinging.append([node, node.transform, top, inventory.point_slot(StringName(p.id)) == &"backpack"])


## Where each attachment on the worn carrier and pack sits: point id -> torso-local transform.
## Gear fit (queue 4; Captain, build B0330: "still there on both sides"): every pouch on the
## carrier stays on what it hangs on, its tabs and rods too (pouch_extent). The pouches on each
## face (the plate pockets' fronts and backs; the sides: the cummerbund, or a heavy rig's side
## plate pockets) are laid out inside that face (face_region, _fit_face), each as near its own
## point as that allows, and shrunk where a face's pouches don't fit it at full size. A front
## point past the plate pocket's edge on a medium or heavy carrier puts its pouch on the
## cummerbund's corner (_corner_spot). A knife on its own point and what is on the pack go on
## their points as they are.
func pouch_spots() -> Dictionary:
	var out := {}
	var faces := {}  # face -> [{"p", "size", "extent"}], for _fit_face
	for p: Dictionary in inventory.attach_points():
		var att := inventory.attachment(StringName(p.id))
		if att.is_empty():
			continue
		var item := ItemDB.get_item(StringName(att.id))
		var size := WorldItem.visual_size(item)
		var face := String(p.get("face", "front"))
		var on_pack := inventory.point_slot(StringName(p.id)) == &"backpack"
		if on_pack or _carrier == null or face == "top" or String(p.get("type", "")) == "knife":
			# (A pack sits on the carrier's back, so its points take the back's fit.)
			var bag := _pack_bag_size(p, item)
			if bag != Vector3.ZERO:  # centred on the pack's back, as tall as it
				var q := p.duplicate()
				q["at"] = [0.0, PACK_CENTRE_Y, float(p["at"][2])]
				out[p.id] = carrier_fit("back") * point_transform(q, bag)
				continue
			out[p.id] = carrier_fit("back" if on_pack else face) * point_transform(p, size)
			continue
		var extent := pouch_extent(item, not att.get("held", []).is_empty())
		if _on_cummerbund(p):
			out[p.id] = _corner_spot(p, size, extent)
			continue
		if not faces.has(face):
			faces[face] = []
		faces[face].append({"p": p, "size": size, "extent": extent})
	for face: String in faces:
		_fit_face(face, faces[face], out)
	return out


## How an aid bag on point `p` of the worn pack is drawn (Captain: it dangled off the pack like
## a second box): as wide and tall as the pack's back less 1 cm a side, centred on it
## (pouch_spots), strapped flat to it, AID_BAG_DEPTH_M deep. ZERO for anything else.
func _pack_bag_size(p: Dictionary, item: ItemData) -> Vector3:
	var pack: StringName = inventory.slots[&"backpack"]
	if String(p.get("type", "")) != "aid_bag" or pack == &"" or not item.stats.get("attach", []).has("aid_bag"):
		return Vector3.ZERO
	var pack_size := VoxelArt.size_m(VoxelArt.model_for(ItemDB.get_item(pack)))
	return Vector3(pack_size.x - 0.02, pack_size.y - 0.02, minf(AID_BAG_DEPTH_M, WorldItem.visual_size(item).z))


## The part of the worn carrier that the pouches on `face` (front, back, left or right) lie on,
## before carrier_fit, torso-local metres: "u", its extent across (x on the front and back, z
## on the sides), "v", its extent up (y), and "out", how far out from the spine a side's
## surface is at torso height y (a Callable; the front and back keep their points' depth).
## - Front and back: the plate pocket, PANEL_HALF_M either side of the spine, from the mount to
##   the pocket's top (VoxelArt.POCKET_TOP_CM).
## - Sides of a heavy carrier: the side plate pocket's outer face (VoxelArt.SIDE_POCKET_*).
## - Sides of a medium (or light) one: the cummerbund's flat side between its cut corners
##   (VoxelArt.CUMMERBUND_BEVEL), as narrow as it is anywhere up its height, which is the
##   body's own width there plus the padding (VoxelArt.cummerbund_size).
func face_region(face: String) -> Dictionary:
	var mount := VoxelArt.CARRIER_MOUNT_CM * 0.01
	var tier := _carrier_tier()
	if face == "front" or face == "back":
		return {"u": Vector2(-PANEL_HALF_M, PANEL_HALF_M), "v": Vector2(mount, mount + VoxelArt.POCKET_TOP_CM * 0.01),
			"out": Callable()}
	var sx := -1.0 if face == "left" else 1.0
	if tier == 2:
		var pocket_z := VoxelArt.SIDE_POCKET_HALF_Z_CM * 0.01
		var pocket_out := func(_y: float) -> float: return sx * VoxelArt.SIDE_POCKET_OUT_CM * 0.01
		return {"u": Vector2(-pocket_z, pocket_z), "v": Vector2(mount, mount + VoxelArt.SIDE_POCKET_TOP_CM * 0.01), "out": pocket_out}
	var top := mount + VoxelArt.CUMMERBUND_TOP_CM * 0.01
	var half_z := INF
	for i in 12:
		half_z = minf(half_z, VoxelArt.cummerbund_size(tier, model.body, lerpf(mount, top, i / 11.0)).y)
	half_z *= 1.0 - VoxelArt.CUMMERBUND_BEVEL
	var body := model.body
	var side_out := func(y: float) -> float: return sx * VoxelArt.cummerbund_size(tier, body, y).x
	return {"u": Vector2(-half_z, half_z), "v": Vector2(mount, top), "out": side_out}


## Lays out the pouches on one face of the carrier (`entries` from pouch_spots) inside its
## face_region, into `out`: row by row (points within 5 cm of each other's height), each row
## across the face (_fit_line) at its points' height, then the rows up the face, all shrunk
## alike where they don't fit. A side's pouches lie flat on its surface.
func _fit_face(face: String, entries: Array, out: Dictionary) -> void:
	var region := face_region(face)
	var side := face == "left" or face == "right"
	var rows: Array = []
	for e: Dictionary in entries:
		var at: Array = e.p.at
		e.u = float(at[2]) if side else float(at[0])
		e.v = float(at[1])
		var ext: AABB = e.extent
		e.hu = maxf(-ext.position.x, ext.end.x)
		var row: Array = []
		for r: Array in rows:
			if absf(float(r[0].v) - float(e.v)) < 0.05:
				row = r
		if row.is_empty():
			rows.append([e])
		else:
			row.append(e)
	var lines: Array = []  # one per row: [y, reach down, reach up, row]
	for row: Array in rows:
		var across: Array = row.map(func(e: Dictionary) -> Array: return [e.u, -float(e.hu), float(e.hu), e])
		var s := _fit_line(across, region.u.x, region.u.y)
		var y := 0.0
		var down := 0.0
		var up := 0.0
		for a: Array in across:
			var e: Dictionary = a[3]
			e.u = a[0]
			e.s = s
			y += float(e.v) / row.size()
			down = minf(down, (e.extent as AABB).position.y * s)
			up = maxf(up, (e.extent as AABB).end.y * s)
		lines.append([y, down, up, row])
	var shrink := _fit_line(lines, region.v.x, region.v.y)
	for line: Array in lines:
		var y: float = line[0]
		for e: Dictionary in line[3]:
			var q: Dictionary = e.p.duplicate()
			var at: Array = e.p.at
			q.at = [(region.out as Callable).call(y), y, e.u] if side else [e.u, y, at[2]]
			out[e.p.id] = carrier_fit(face) * point_transform(q, e.size, float(e.s) * shrink)


## Lays `items` ([centre, reach down, reach up, ...]: how far each reaches below and above its
## centre) along a line, inside [`lo`, `hi`], in order and POUCH_GAP_M apart, each as near its
## own centre as that allows, moving the centres in place. When they don't all fit at full
## size, they are all shrunk by the same factor first (their reaches with them); that factor
## is returned (1 when they fit).
static func _fit_line(items: Array, lo: float, hi: float) -> float:
	if items.is_empty():
		return 1.0
	items.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var total := 0.0
	for it: Array in items:
		total += float(it[2]) - float(it[1])
	var room := hi - lo - POUCH_GAP_M * (items.size() - 1)
	var s := clampf(room / total, 0.05, 1.0) if total > 0.0 else 1.0
	for it: Array in items:
		it[1] = float(it[1]) * s
		it[2] = float(it[2]) * s
	for i in 8:  # spread them apart, near their own places
		for it: Array in items:
			it[0] = clampf(float(it[0]), lo - float(it[1]), hi - float(it[2]))
		for j in items.size() - 1:
			var a: Array = items[j]
			var b: Array = items[j + 1]
			var overlap := (float(a[0]) + float(a[2])) - (float(b[0]) + float(b[1])) + POUCH_GAP_M
			if overlap > 0.0:
				a[0] = float(a[0]) - overlap * 0.5
				b[0] = float(b[0]) + overlap * 0.5
	# Then settle them for certain: up from the low end, then back down from the high end.
	var edge := lo
	for it: Array in items:
		it[0] = maxf(float(it[0]), edge - float(it[1]))
		edge = float(it[0]) + float(it[2]) + POUCH_GAP_M
	edge = hi
	for k in range(items.size() - 1, -1, -1):
		var it: Array = items[k]
		it[0] = minf(float(it[0]), edge - float(it[2]))
		edge = float(it[0]) + float(it[1]) - POUCH_GAP_M
	return s


## A front point past the plate pocket's edge on a medium or heavy carrier: its pouch goes on
## the cummerbund's front corner (cummerbund_spot), not standing out past the panel.
func _on_cummerbund(p: Dictionary) -> bool:
	var at: Array = p.get("at", [0, 0, 0])
	return _carrier != null and _carrier_tier() > 0 and String(p.get("face", "front")) == "front" \
		and absf(float(at[0])) > PANEL_HALF_M and String(p.get("type", "")) != "knife"


## Where a pouch of `size` (reaching as `extent` says) on front point `p` past the plate
## pocket's edge sits: on the cummerbund's corner (cummerbund_spot), between its bottom and top
## (VoxelArt.CUMMERBUND_TOP_CM), shrunk if it is wider than the corner's cut is there.
func _corner_spot(p: Dictionary, size: Vector3, extent: AABB) -> Transform3D:
	var tier := _carrier_tier()
	var lo := VoxelArt.CARRIER_MOUNT_CM * 0.01
	var hi := lo + VoxelArt.CUMMERBUND_TOP_CM * 0.01
	var at: Array = p.at
	var y := float(at[1])
	var cut := VoxelArt.CUMMERBUND_BEVEL * VoxelArt.cummerbund_size(tier, model.body, y).length()
	var s := minf(1.0, minf(cut / (2.0 * maxf(-extent.position.x, extent.end.x)), (hi - lo) / extent.size.y))
	var q := p.duplicate()
	q.at = [at[0], clampf(y, lo - extent.position.y * s, hi - extent.end.y * s), at[2]]
	return cummerbund_spot(tier, model.body, q, size, s)


## Torso-local transform of an attachment of `size` on the front corner of a tier `tier`
## carrier's cummerbund round body type `body`, on point `p`'s side and at its height: flat on
## the corner's cut (VoxelArt.CUMMERBUND_BEVEL: from 1 - bevel of the way out across the front
## to 1 - bevel of the way back down the side), facing out of it, drawn `scale` of its size.
static func cummerbund_spot(tier: int, body: String, p: Dictionary, size: Vector3, scale := 1.0) -> Transform3D:
	var at: Array = p.at
	var sx := signf(float(at[0]))
	var y := float(at[1])
	var c := VoxelArt.cummerbund_size(tier, body, y)
	var k := 1.0 - VoxelArt.CUMMERBUND_BEVEL
	var a := Vector2(sx * k * c.x, -c.y)
	var b := Vector2(sx * c.x, -k * c.y)
	var n := Vector2(sx * c.y, -c.x).normalized()  # out of the cut
	var mid := (a + b) * 0.5 + n * size.z * 0.5 * scale
	var basis := Basis(Vector3.UP, atan2(-n.x, -n.y)).scaled(Vector3.ONE * scale)  # the pouch's front (-Z) along n
	return Transform3D(basis, Vector3(mid.x, y, mid.y))


## The name tape: the soldier's surname (CharacterModel.name_tape) in dark capitals on the
## carrier's loop panel at the top of the plate pocket's front (VoxelArt._vest), TAPE_HEIGHT_M
## tall. None without a carrier or a name. Rebuilt when either changes (see _process).
func _set_name_tape(carrier: ItemData) -> void:
	var key := "%s|%s" % [carrier.id if carrier else &"", model.name_tape]
	if key == _tape_key:
		return
	_tape_key = key
	if _tape:
		_tape.queue_free()
		_tape = null
	if carrier == null or model.name_tape == "":
		return
	var front := float(carrier.stats.get("plate_depth", 0.14)) + 0.03  # the pocket's face
	_tape = Node3D.new()
	_tape.name = "NameTape"
	_tape.transform = carrier_fit("front") * Transform3D(Basis.IDENTITY, Vector3(0, 0.17 + 0.265, -front))  # the loop panel
	model.torso.add_child(_tape)
	_tape.add_child(_part_box(TAPE_SIZE, Vector3(0, 0, -TAPE_SIZE.z * 0.5), TAPE_CLOTH, render_layers))
	var letters := Label3D.new()
	letters.text = model.name_tape
	letters.font_size = 48
	letters.pixel_size = TAPE_HEIGHT_M / 48.0
	letters.outline_size = 0
	letters.modulate = TAPE_INK
	letters.double_sided = false
	letters.layers = render_layers
	letters.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -TAPE_SIZE.z - 0.001))  # reads from the front
	_tape.add_child(letters)


## A worn pack's padded shoulder straps: from the top of the pack, over each shoulder along
## the carrier's shoulder pad (VoxelArt.shoulder_pad_line) or, with no carrier, on the
## shoulder itself (VoxelArt.shoulder_top), down the plate pocket's front edges (or the chest),
## with a sternum strap across under the ID panel. Rebuilt when the pack or carrier changes.
func _set_pack_straps(pack: StringName) -> void:
	var key := "%s|%s" % [pack, _carrier.id if _carrier else &""]
	if key == _straps_for:
		return
	_straps_for = key
	if _straps:
		_straps.queue_free()
		_straps = null
	if pack == &"":
		return
	_straps = Node3D.new()
	_straps.name = "PackStraps"
	model.torso.add_child(_straps)
	var colour := Color(VoxelArt.spec(model.variant).gear).darkened(0.3)
	var path := strap_path(model.body, _carrier != null, _plate_depth())
	if _carrier:  # (no carrier: nothing to fit to; torso_reach has the body itself)
		path.assign(path.map(func(v: Vector3) -> Vector3: return _on_panels(v) if absf(v.z) > 0.15 else v))
	for s: float in [-1.0, 1.0]:
		for i in path.size() - 1:
			_straps.add_child(_strap(path[i] * Vector3(s, 1, 1), path[i + 1] * Vector3(s, 1, 1), STRAP_W, STRAP_T, colour))
	var front := -(_plate_depth() + 0.03) - STRAP_T if _carrier else -VoxelArt.torso_reach(model.body, 0.355) - STRAP_T
	var fit := func(v: Vector3) -> Vector3: return _on_panels(v) if _carrier else v
	_straps.add_child(_strap(fit.call(Vector3(-0.12, 0.355, front)), fit.call(Vector3(0.12, 0.355, front)), 0.02, 0.008, colour))  # sternum strap


## The right shoulder strap's line, torso-local (mirror x for the left): from the pack's top,
## up over the carrier's shoulder pad (`carrier`) or body type `body`'s shoulder, and down the
## front to the sternum strap's height. Points on the carrier's back or front (|z| > 0.15) are
## moved with its panels by the caller.
static func strap_path(body: String, carrier: bool, plate_depth: float) -> Array[Vector3]:
	var x := VoxelArt.SHOULDER_PAD_X * 0.01
	var path: Array[Vector3] = [Vector3(x, 0.5, 0.17)]  # into the pack's top
	if carrier:
		var centre := Vector3(x, (VoxelArt.CARRIER_MOUNT_CM + 30.0) * 0.01, 0)
		# Up the pad's back and over its top; its front slope lies behind the plate pocket, so from
		# the top the strap drapes over the pocket's top edge and down its face.
		var line := VoxelArt.shoulder_pad_line(body == VoxelArt.FEMALE)
		for v: Vector3 in line.slice(0, 4):
			var out := v - centre
			out.x = 0.0
			path.append(v + out.normalized() * (STRAP_LIFT + STRAP_T * 0.5))
		var face := -(plate_depth + 0.03) - STRAP_T
		path.append(Vector3(PANEL_HALF_M - STRAP_W * 0.5, 0.17 + 0.33 + STRAP_T, face + STRAP_T))  # over the pocket's top
		path.append(Vector3(PANEL_HALF_M - STRAP_W * 0.5, 0.34, face))
	else:
		var top := VoxelArt.shoulder_top(body, x) + STRAP_LIFT
		var back := VoxelArt.torso_reach(body, top - 0.08, true) + STRAP_T
		var chest := VoxelArt.torso_reach(body, top - 0.08) + STRAP_T
		path.append(Vector3(x, top - 0.08, back))
		path.append(Vector3(x, top, 0.04))
		path.append(Vector3(x, top, -0.04))
		path.append(Vector3(x, top - 0.08, -chest))
		path.append(Vector3(x + 0.03, 0.34, -VoxelArt.torso_reach(body, 0.34) - STRAP_T))
	return path


## A strap of `width` and `thick` from `a` to `b` (torso-local), lying flat on the body: its
## face turned out from inside the upper chest.
func _strap(a: Vector3, b: Vector3, width: float, thick: float, colour: Color) -> Node3D:
	var holder := Node3D.new()
	holder.add_child(_part_box(Vector3(width, (b - a).length() + thick, thick), Vector3.ZERO, colour, render_layers))
	var y := (b - a).normalized()
	var out := (a + b) * 0.5 - Vector3(0, 0.45, 0)
	var z := (out - y * out.dot(y)).normalized()
	holder.transform = Transform3D(Basis(y.cross(z), y, z), (a + b) * 0.5)
	return holder


## Torso-local transform of an attachment of `size` on attach point `p`: its back against the
## carrier at "at", facing out of "face" (front, back, left or right), drawn `scale` of its size.
static func point_transform(p: Dictionary, size: Vector3, scale := 1.0) -> Transform3D:
	var at: Array = p.get("at", [0, 0.3, -0.18])
	var origin := Vector3(float(at[0]), float(at[1]), float(at[2]))
	var basis := Basis.IDENTITY
	match String(p.get("face", "front")):
		"back": basis = Basis(Vector3.UP, PI)
		"left": basis = Basis(Vector3.UP, PI / 2)
		"right": basis = Basis(Vector3.UP, -PI / 2)
		"top":  # on top of a pack: lying across it, left to right, resting on "at"
			return Transform3D(Basis(Vector3.UP, PI / 2), origin + Vector3(0, size.y * 0.5, 0))
	return Transform3D(basis.scaled(Vector3.ONE * scale), origin + basis * Vector3(0, 0, -size.z * 0.5 * scale))


## A pouch (or knife) as small boxes: body and a darker flap, or a sheath and handle; a radio
## shows its antenna. A tourniquet holder is open-topped: the tourniquet in it shows (black
## band, windlass rod across the top, red tab). A full IFAK pouch shows its red pull tabs, so
## you can see who carries one; every red tab lies flat on the pouch's face, below its top edge
## (Captain: tabs standing up off a top edge read as a glitch). An aid bag (aid_bag_parts) shows
## a red cross. Front is -Z. Used on the soldier and for item previews. `size`, when given,
## draws it that size instead of its own (an aid bag fitted to the pack it is strapped on).
static func pouch_node(item: ItemData, colour: Color, full: bool, layers := 1, size := Vector3.ZERO) -> Node3D:
	var root := Node3D.new()
	for part: Array in pouch_parts(item, colour, full, size):
		var box := _part_box(part[0], part[1], part[2], layers)
		if part[3]:
			box.name = "Antenna"
		root.add_child(box)
	return root


## The boxes pouch_node draws for `item` (`full`: with what is in it showing), pouch-local:
## [size, centre, colour, whether it is a radio's antenna (which stands up past whatever the
## pouch is on)].
static func pouch_parts(item: ItemData, colour: Color, full: bool, drawn := Vector3.ZERO) -> Array:
	var size := drawn if drawn != Vector3.ZERO else WorldItem.visual_size(item)
	if item.stats.get("attach", []).has("aid_bag"):
		return aid_bag_parts(size, colour)
	if item.id == &"knife" or item.stats.get("attach", []).has("knife") and not Inventory.is_pouch(item):
		return [[Vector3(size.x, size.y * 0.62, size.z), Vector3(0, -size.y * 0.19, 0), colour.darkened(0.35), false],
			[Vector3(size.x * 0.7, size.y * 0.38, size.z * 0.8), Vector3(0, size.y * 0.31, 0), Color("26241f"), false]]
	var accepts: Array = item.stats.get("accepts", [])
	if accepts.has("tourniquet"):
		var holder := [[Vector3(size.x, size.y * 0.6, size.z), Vector3(0, -size.y * 0.2, 0), colour, false]]
		if full:
			holder.append([Vector3(size.x * 0.8, size.y * 0.5, size.z * 0.75), Vector3(0, size.y * 0.25, 0), TQ_BAND, false])
			holder.append([Vector3(size.x * 1.3, 0.012, 0.012), Vector3(0, size.y * 0.5, -size.z * 0.1), TQ_BAND.lightened(0.15), false])
			# the red tab on the band's face, flush, its top below the band's
			holder.append([Vector3(0.016, 0.02, 0.005), Vector3(size.x * 0.25, size.y * 0.36, -size.z * 0.375 - 0.0025), MED_RED, false])
		return holder
	var parts := [[size, Vector3.ZERO, colour, false],
		[Vector3(size.x * 1.02, size.y * 0.28, size.z * 1.08), Vector3(0, size.y * 0.36, -size.z * 0.04), colour.darkened(0.25), false]]
	if full and accepts.has("radio"):
		parts.append([Vector3(0.008, 0.16, 0.008), Vector3(size.x * 0.3, size.y * 0.5 + 0.08, 0), Color("1d1d1b"), true])
	if full and accepts.has("type:medical"):
		# pull tabs flat on the flap's face, inside its top edge
		var tab_h := minf(0.02, size.y * 0.2)
		for side in [-1.0, 1.0]:
			parts.append([Vector3(0.014, tab_h, 0.005), Vector3(side * size.x * 0.32, size.y * 0.36, -size.z * 0.58 - 0.0025), MED_RED, false])
	return parts


## A medic's aid bag, `size`, front -Z: the bag, a darker zipped lid band across its top, two
## compression straps down its face and over its top (it is strapped to the pack), a flat red cross patch between
## them and small red pull loops at the zip's ends, all flush on its face; nothing red above its top.
static func aid_bag_parts(size: Vector3, colour: Color) -> Array:
	var face := -size.z * 0.5 - 0.0025  # a 0.5 cm thing lying on the face
	var strap := colour.darkened(0.35)
	var parts := [[size, Vector3.ZERO, colour, false],
		[Vector3(size.x, size.y * 0.12, size.z), Vector3(0, size.y * 0.44, 0), colour.darkened(0.22), false]]
	for side in [-1.0, 1.0]:
		parts.append([Vector3(0.035, size.y, 0.005), Vector3(side * size.x * 0.3, 0, face), strap, false])
		# and over its top, back to the pack it holds it to
		parts.append([Vector3(0.035, 0.005, size.z + 0.005), Vector3(side * size.x * 0.3, size.y * 0.5 + 0.0025, -0.0025), strap, false])
		parts.append([Vector3(0.012, 0.02, 0.005), Vector3(side * size.x * 0.43, size.y * 0.42, face), MED_RED, false])
	var arm := minf(0.09, size.x * 0.3)
	parts.append([Vector3(arm, arm / 3.0, 0.005), Vector3(0, -size.y * 0.05, face), MED_RED, false])
	parts.append([Vector3(arm / 3.0, arm, 0.005), Vector3(0, -size.y * 0.05, face), MED_RED, false])
	return parts


## The box round what pouch_node draws for `item` (`full`: with its tabs, band and rod), a
## radio's antenna left out, pouch-local. GearRig keeps it on the carrier.
static func pouch_extent(item: ItemData, full: bool) -> AABB:
	var box := AABB()
	var first := true
	for part: Array in pouch_parts(item, Color.WHITE, full):
		if part[3]:
			continue
		var b := AABB(part[1] - part[0] * 0.5, part[0])
		box = b if first else box.merge(b)
		first = false
	return box


static func _part_box(size: Vector3, pos: Vector3, colour: Color, layers: int) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()  # a bevelled box in 0.5 cm voxels, centred on `pos`
	mesh_instance.mesh = VoxelArt.bevel_box_mesh(size, colour)
	mesh_instance.material_override = VoxelArt._get_material()
	mesh_instance.scale = Vector3.ONE * VoxelArt.FINE_VOXEL
	mesh_instance.position = pos - Vector3(VoxelArt.fine_dims(size)) * VoxelArt.FINE_VOXEL * 0.5
	mesh_instance.layers = layers
	return mesh_instance


func _process(delta: float) -> void:
	_clock += delta
	if not _tape_key.ends_with("|" + model.name_tape):  # the name arrives after the body is built
		var vest: StringName = inventory.slots[&"vest"]
		_set_name_tape(ItemDB.get_item(vest) if vest != &"" else null)
	if model.left_handed != _left_shown:
		_left_shown = model.left_handed  # the slung weapons move to the other side
		for slot: StringName in MOUNTS:
			if _gear.has(slot) and slot != _held_key:
				(_gear[slot][1] as Node3D).transform = rest_transform(slot)
		_held_dirty = true
	var want := _wanted_in_hands()
	if want != _want_key:
		_want_key = want
		_grab_at = -1.0
		if want in MOUNTS and _gear.has(want) and want != _held_key:
			# Drawn: what was held goes back first, the hand fetches the new one.
			if _held_key != &"":
				_put_in_hands(&"")
			model.start_draw(_rest_grip(want))
			_grab_at = _clock + CharacterModel.DRAW_S * CharacterModel.DRAW_GRAB
	if _grab_at >= 0.0 and _clock < _grab_at:
		return
	_grab_at = -1.0
	if want != _held_key or _held_dirty:
		_put_in_hands(want)
	_ease_held(delta)


## Gear secondary motion, on physics ticks: the body moves on them, so a render frame between
## two would read as standing still and shake the springs.
func _physics_process(delta: float) -> void:
	if _sway_on:
		_sway(delta)


## The springs follow the torso, the pack swings about its anchors (and what's on it with it),
## every other pouch flaps about its own top edge.
func _sway(delta: float) -> void:
	var pack: Node3D = _gear.get(&"backpack", [&"", null])[1]
	if pack == null and _swinging.is_empty():
		return
	if not model.is_visible_in_tree() or model.ragdolled():
		_pack_sway.reset()
		_pouch_sway.reset()
		return
	var torso := model.torso.global_transform
	_pack_sway.follow(torso, delta)
	_pouch_sway.follow(torso, delta)
	var swing := _about(_pack_pivot, _pack_sway.turn())
	if pack:
		pack.transform = swing * _pack_rest
	var flap := _pouch_sway.turn()
	for e: Array in _swinging:
		var node: Node3D = e[0]
		if not is_instance_valid(node):
			continue
		node.transform = (swing if e[3] else _about(e[2], flap)) * (e[1] as Transform3D)


## A turn `b` about torso-local point `pivot`.
static func _about(pivot: Vector3, b: Basis) -> Transform3D:
	return Transform3D(Basis.IDENTITY, pivot) * Transform3D(b, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)


## True while a weapon is on its way from its sling or holster to the hands.
func drawing() -> bool:
	return _grab_at >= 0.0


func _wanted_in_hands() -> StringName:
	if inventory.hands != &"":
		return &"hands"
	if model.hands_busy():
		return &""  # slung or holstered while the hands work
	match model.hold:
		CharacterModel.Hold.BOTH:
			return &"primary" if _gear.has(&"primary") else &""
		CharacterModel.Hold.RIGHT:
			return &"sidearm" if _gear.has(&"sidearm") else &""
	return &""


func _put_in_hands(key: StringName) -> void:
	# Whatever was held goes back to its rest mount.
	if _held_key in MOUNTS and _gear.has(_held_key):
		var previous: Node3D = _gear[_held_key][1]
		previous.reparent(model.torso, false)
		previous.transform = rest_transform(_held_key)
	_held_key = key
	_held_dirty = false
	model.clear_held()
	if not _gear.has(key):
		return
	var node: Node3D = _gear[key][1]
	if key == &"hands":
		# Bulky item stays in front of the torso; palms press on its sides.
		var half := WorldItem.visual_size(ItemDB.get_item(inventory.hands)).x * 0.5
		model.set_held(node, Vector3(half, 0, 0), Vector3(-half, 0, 0), false)
		return
	var points := VoxelArt.hand_points(VoxelArt.model_for(ItemDB.get_item(_gear[key][0])))
	if points.is_empty():
		return
	node.reparent(model.hands_anchor, false)
	node.transform = _hold_goal(VoxelArt.model_for(ItemDB.get_item(_gear[key][0])))
	model.set_held(node, points.grip, points.support)


## Torso-local point where the firing hand takes hold of the weapon in `key` on its rest
## mount (its grip, or the mount itself).
func _rest_grip(key: StringName) -> Vector3:
	var points := VoxelArt.hand_points(VoxelArt.model_for(ItemDB.get_item(_gear[key][0])))
	var grip: Vector3 = points.get("grip", Vector3.ZERO)
	return rest_transform(key) * grip


## Where this body's carrier panel `face` ("front", "back", "left", "right") sits, as a move
## from the male fit (torso-local; identity for him). A woman's carrier (VoxelArt "vest_f",
## its front panel built apart, "vest_f_front") fits her the way a real one does: the front
## panel hangs from its top edge on the shoulder straps, FEMALE_CARRIER_FRONT_OUT out and
## tilted FEMALE_CARRIER_TILT_DEG, so its top lies on her upper chest and it rests on her bust
## with the bottom standing off a little; the back panel sits FEMALE_CARRIER_BACK further in
## against her slimmer back and the side pockets in at her sides. What is on a panel (plates,
## pouches, name tape, sling, pack) goes with it.
func carrier_fit(face: String) -> Transform3D:
	if model.body != VoxelArt.FEMALE:
		return Transform3D.IDENTITY
	match face:
		"front":
			var top := Vector3(0, 0.17 + 0.33, -(_plate_depth() - 0.03))  # the pocket's top edge, inside
			var tilt := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(VoxelArt.FEMALE_CARRIER_TILT_DEG)), Vector3.ZERO)
			return Transform3D(Basis.IDENTITY, top + Vector3(0, 0, -VoxelArt.FEMALE_CARRIER_FRONT_OUT * 0.01)) * tilt \
				* Transform3D(Basis.IDENTITY, -top)
		"back":
			return Transform3D(Basis.IDENTITY, Vector3(0, 0, -VoxelArt.FEMALE_CARRIER_BACK * 0.01))
		"left":
			return Transform3D(Basis.IDENTITY, Vector3(VoxelArt.carrier_side_inset(_carrier_tier(), VoxelArt.FEMALE) * 0.01, 0, 0))
		"right":
			return Transform3D(Basis.IDENTITY, Vector3(-VoxelArt.carrier_side_inset(_carrier_tier(), VoxelArt.FEMALE) * 0.01, 0, 0))
	return Transform3D.IDENTITY


## The worn carrier's plate depth (its "plate_depth") and tier index (0 light .. 2 heavy).
func _plate_depth() -> float:
	return float(_carrier.stats.get("plate_depth", 0.14)) if _carrier else 0.14


func _carrier_tier() -> int:
	return maxi(["light", "medium", "heavy"].find(_carrier.stats.get("tier", "medium")), 0) if _carrier else 1


## A torso-local point on the carrier or pack, moved with its panel (carrier_fit): behind the
## shoulders with the back, in front with the front.
func _on_panels(p: Vector3) -> Vector3:
	return carrier_fit("back") * p if p.z > 0.1 else carrier_fit("front") * p if p.z < -0.1 else p


## A woman's carrier: its front panel, built apart from the rest of the rig ("vest_f_front"),
## hangs on her as carrier_fit("front") says. Added once to the worn carrier's node.
func _fit_front_panel(carrier: ItemData) -> void:
	var vest: Node3D = _gear.get(&"vest", [&"", null])[1]
	if vest == null or carrier == null or model.body != VoxelArt.FEMALE or vest.get_node_or_null(^"FrontPanel"):
		return
	var panel := VoxelArt.instance(VoxelArt.model_for(carrier).replace("vest:", "vest_f_front:"), model.variant, render_layers)
	panel.name = "FrontPanel"
	var mount := rest_transform(&"vest")
	panel.transform = mount.affine_inverse() * carrier_fit("front") * mount
	vest.add_child(panel)


## Where `slot`'s item rests on the torso (MOUNTS), mirrored for a left-handed shooter.
func rest_transform(slot: StringName) -> Transform3D:
	var s := -1.0 if model.left_handed else 1.0
	match slot:
		&"vest":
			return Transform3D(Basis.IDENTITY, Vector3(0, 0.17, 0))  # vest pivots sit at the cummerbund
		&"primary":
			var centre := SLING_CENTRE * Vector3(s, 1, 1)
			var dir := SLING_DIR * Vector3(s, 1, 1)
			# On its side: the top (optic) towards the support shoulder, across the sling line; on the
			# carrier's front panel as it sits (carrier_fit).
			return carrier_fit("front") * Transform3D(Basis.looking_at(dir, Vector3(-0.866 * s, 0.5, 0.0)), centre)
		&"sidearm":
			return Transform3D(Basis(Vector3.RIGHT, -PI / 2), HOLSTER * Vector3(s, 1, 1))
	return Transform3D.IDENTITY


## Where a held weapon (VoxelArt model `art`) sits in hands_anchor space, aiming or at the
## ready, for the firing shoulder (see SHOULDER_POCKET), the upper body twisted by `twist`
## (CharacterModel.twist_shown; NAN: fully bladed).
static func held_transform(art: String, aiming: bool, left: bool, twist := NAN) -> Transform3D:
	var s := -1.0 if left else 1.0
	if is_nan(twist):
		twist = CharacterModel.blade_twist(left)
	if art.begins_with("rifle"):
		var basis := Basis.IDENTITY
		var pocket := SHOULDER_POCKET
		if not aiming:
			basis = Basis(Vector3.UP, READY_TURN * s) * Basis(Vector3.RIGHT, -READY_DIP)
			pocket = READY_POCKET
		return Transform3D(basis, Basis(Vector3.UP, twist) * (pocket * Vector3(s, 1, 1)) - basis * VoxelArt.butt_point(art))
	if aiming:
		return Transform3D(Basis.IDENTITY, PISTOL_AIM)
	return Transform3D(Basis(Vector3.RIGHT, -PISTOL_READY_DIP), PISTOL_READY * Vector3(s, 1, 1))


## Where seated: a weapon held (VoxelArt model `art`) in hands_anchor space, muzzle down
## (SEATED_*), its hip joint `room` above the floor.
static func seated_transform(art: String, left: bool, room: float) -> Transform3D:
	var s := -1.0 if left else 1.0
	if not art.begins_with("rifle"):
		return Transform3D(Basis(Vector3.RIGHT, -SEATED_PISTOL_DIP), SEATED_PISTOL * Vector3(s, 1, 1))
	var basis := Basis.looking_at(SEATED_DIR, Vector3.BACK)  # the top towards him
	var butt := VoxelArt.butt_point(art)
	var at := SEATED_BUTT * Vector3(s, 1, 1)
	# The muzzle's height over the hips (hands_anchor is HANDS_ANCHOR up the upper body; the
	# butt is at the back end, the muzzle as far the other side of the middle).
	var muzzle := CharacterModel.HANDS_ANCHOR.y + at.y + (basis * Vector3(0, 0, -2.0 * butt.z)).y
	at.y += clampf(SEATED_MUZZLE_CLEAR - room - muzzle, 0.0, SEATED_LIFT_MAX)
	return Transform3D(basis, at - basis * butt)


## Where the weapon in the hands goes now: seated, aiming or at the ready.
func _hold_goal(art: String) -> Transform3D:
	if model.is_seated():
		return seated_transform(art, model.left_handed, model.seat_room())
	return held_transform(art, model.aiming, model.left_handed, model.twist_shown())


## Moves the weapon in the hands towards where it sits now (raised to aim, or at the ready).
func _ease_held(delta: float) -> void:
	if _held_key == &"" or _held_key == &"hands" or not _gear.has(_held_key):
		return
	var node: Node3D = _gear[_held_key][1]
	var goal := _hold_goal(VoxelArt.model_for(ItemDB.get_item(_gear[_held_key][0])))
	node.transform = node.transform.interpolate_with(goal, minf(delta * HOLD_EASE, 1.0))


## Replays armor chips into the meshes, skipping pieces whose chip list hasn't grown.
func _refresh_plate_damage() -> void:
	for slot: StringName in _armor:
		var chips := inventory.chips_in(slot)
		if chips.size() != _chip_counts.get(slot, -1):
			_armor[slot].apply_damage(chips, ArmorRules.is_shattered(inventory.state_of(slot)))
			_chip_counts[slot] = chips.size()


## `state`: the item's state, for a model that shows it (a rifle's optic, P0362).
func _set_gear(key: StringName, id: StringName, mount: StringName, at: Transform3D, state := {}) -> void:
	var current: Array = _gear.get(key, [&"", null, ""])
	var item := ItemDB.get_item(id) if id != &"" else null
	var art := VoxelArt.fitted(VoxelArt.model_for(item, state), model.body) if item else ""
	if current[0] == id and (current.size() < 3 or current[2] == art):
		return
	if current[1]:
		current[1].queue_free()
	_gear.erase(key)
	_held_dirty = true
	if id == &"":
		return
	var node: Node3D = VoxelArt.instance(art, model.variant, render_layers) if art != "" else _box(item)
	node.transform = at
	(model.head if mount == &"head" else model.torso).add_child(node)
	_gear[key] = [id, node, art]
	_held_dirty = true  # a held node may have been replaced


func _box(item: ItemData) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = WorldItem.visual_size(item)
	var material := StandardMaterial3D.new()
	material.albedo_color = WorldItem.color_for(item)
	box.material = material
	mesh_instance.mesh = box
	mesh_instance.layers = render_layers
	return mesh_instance


func _clear() -> void:
	for piece: VoxelArmor in _armor.values():
		piece.queue_free()
	_armor.clear()
	for entry: Array in _gear.values():
		entry[1].queue_free()
	_gear.clear()
	_held_key = &""
	_held_dirty = true
	if _pouches:
		_pouches.queue_free()
		_pouches = null
	_pouch_key = ""
