class_name ExoMech
extends RefCounted
## The heavy mech-class exo, the HX-1 Assault Frame (docs/near_future_hardware.md 2.3;
## Captain, 2026-10-16): a powered chassis the soldier climbs into and pilots, learned from the
## Captain's reference art (a bulky biped with an integrated head unit, thick hydraulic legs, a
## power pack on the back and a two-handed heavy weapon held low and ready, in real camo).
## - It is worn in the exo slot (ExoFrame.SLOT, so never with an LX-3), but never picked up or
##   put on from the inventory: you climb in where it stands and climb out to leave it
##   standing there (server_enter, server_exit; Inventory refuses it anywhere else). A suit left
##   standing is a WorldItem: anyone can climb into it again, damage and all.
## - Its armour is real ArmorRules armour (Captain, 2026-10-16: "armor plates are where they are
##   seen ... pilots can be wounded, shot through it eventually"): its "pads" are VoxelArmor
##   plates on the body parts they cover, rated per part (Captain, 2026-10-17: AR500 steel, IV on the chest, head
##   unit, shoulders and back, steel III over the belly, steel III++ on the arms and legs), with their chips and
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
## Numbers proposed. Repair cost and pilot training (doc 2.3a, Captain, 2026-10-17): priced in
## data/prices.json and gated by Roster.hx1_certified/cert_problem below; no armory UI to spend
## the certification cost yet.

const SLOT := ExoFrame.SLOT
## Tag on the suit's item; "mech_only" on a weapon only its pilot can carry.
const TAG := "mech"
const GUN_TAG := "mech_only"

## Climbing in, from behind: he hits the manual release on its back (CharacterModel.MECH_RELEASE)
## and the standing suit's back unzips (RELEASE_S); then he's in it, his arms pushed into its
## sleeves, and it zips shut round him (MECH_IN, ENTER_S).
const RELEASE_S := 1.3
const ENTER_S := 2.2
## Climbing out: the back opens (MECH_OPEN), then he steps back out of it (MECH_OUT).
const OPEN_S := 1.4
const OUT_S := 1.6
## How near a standing suit (its action point) you must be to climb in.
const REACH_M := 2.0
## How far behind the suit he stands once out.
const STEP_OUT_M := 0.7  # CharacterModel.MECH_STEP: the clip walks him out that far
## A parked suit's box (and the WorldItem's collision): standing, and lying face down ("prone").
const PARKED_SIZE := Vector3(1.2, 2.35, 1.1)
const PRONE_SIZE := Vector3(1.2, 0.95, 2.35)
## A suit lying face down (Captain, 2026-10-17, the AW scene he pointed to: a downed suit "still
## looks functional", the manual punch-out, the soldier lies down into it and it pushes itself
## up): its bones turned onto its front, this high off the ground (its chest plate's depth).
const LIE_LIFT := 0.36
## Lying in and pushing up: open round him, zipping shut, then up onto its feet
## (CharacterModel.MECH_RISE).
const RISE_S := 3.6

## The back is the hatch (Captain, 2026-10-17, from the punch-out scene he pointed to: you get in
## from the back, "the full back opens, the legs too", it opens like a zipper): the back armour
## and power pack split down the spine, each half swinging out on a hinge at its outer edge, then
## the backs of the thighs, then of the shins, each a beat after the one above. Pad (or the
## torso's lid, LID) id -> [hinge point on its bone, hinge axis, open angle (radians), order].
const HATCH := {
	"back_r": [Vector3(0.27, 0, 0.3), Vector3.UP, 1.9, 0],
	"back_l": [Vector3(-0.27, 0, 0.3), Vector3.UP, -1.9, 0],
	"thigh_back_r": [Vector3(0.13, 0, 0.12), Vector3.UP, 1.6, 1],
	"thigh_back_l": [Vector3(-0.13, 0, 0.12), Vector3.UP, -1.6, 1],
	"shin_back_r": [Vector3(0.12, 0, 0.11), Vector3.UP, 1.6, 2],
	"shin_back_l": [Vector3(-0.12, 0, 0.11), Vector3.UP, -1.6, 2],
}
## The power pack's halves (art: dress) ride on the back plate's halves.
const LID := {"r": "back_r", "l": "back_l"}
## The zipper: each step of HATCH's order starts this share of the way later.
const ZIP_STEP := 0.3


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


## How big a body piloting the suit `inventory` wears is drawn (stats "size": the whole model,
## plates, hitboxes and capsule; CharacterModel.suit_size), 1 with none.
static func size(inventory: Inventory) -> float:
	var item := worn(inventory)
	return float(item.stats.get("size", 1.25)) if item else 1.0


## The pilot's own body (all but his head, which looks out of the cockpit) and his kit (carrier,
## pouches, straps, holster) shown or hidden inside the suit: GearRig, every rebuild. His armour
## stays armour, only its look goes.
static func hide_pilot(model: CharacterModel, gear_nodes: Array, hidden: bool) -> void:
	for part: StringName in [Vitals.CHEST, Vitals.UPPER_ARM_R, Vitals.UPPER_ARM_L, Vitals.FOREARM_R, Vitals.FOREARM_L,
			Vitals.THIGH_R, Vitals.THIGH_L, Vitals.SHIN_R, Vitals.SHIN_L]:
		var bone := model.part_node(part)
		var flesh := bone.get_child(0) as MeshInstance3D if bone and bone.get_child_count() > 0 else null
		if flesh:
			flesh.visible = not hidden
	for n: Variant in gear_nodes:
		if n is Node3D and is_instance_valid(n):
			(n as Node3D).visible = not hidden


## Whether `body` is climbing into or out of a suit now (no moving meanwhile).
static func transitioning(body: Node) -> bool:
	var model := body.get(&"model") as CharacterModel if body else null
	return model != null and model.action_shown() in [CharacterModel.MECH_RELEASE, CharacterModel.MECH_IN, CharacterModel.MECH_RISE, CharacterModel.MECH_OPEN, CharacterModel.MECH_OUT]


## How far the worn suit's back stands open now (0 shut .. 1 open), from the clip playing:
## climbing in, open as he settles in, then zipping shut; climbing out, unzipping.
static func hatch_open(model: CharacterModel) -> float:
	var u := model.action_progress()
	match model.action_shown():
		CharacterModel.MECH_IN:
			return 1.0 - smoothstep(0.3, 0.92, u)
		CharacterModel.MECH_RISE:
			return 1.0 - smoothstep(0.12, 0.42, u)
		CharacterModel.MECH_OPEN:
			return smoothstep(0.05, 0.9, u)
	return 0.0


## How far hatch piece `id` is open when the zipper as a whole is `open` of the way: the upper
## back first, then the thighs, then the shins (ZIP_STEP).
static func piece_open(id: String, open: float) -> float:
	var order := float(HATCH[id][3])
	return clampf(open * (1.0 + ZIP_STEP * 2.0) - ZIP_STEP * order, 0.0, 1.0)


## "Climb into the HX-1 Assault Frame  [chest 64%, gun]" for the interaction menu.
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

## In the campaign (a roster member: "roster_id" meta, set only on a real deployment), whether
## `s` is certified to pilot the HX-1 (Roster.hx1_certified); "" outside the campaign (tests,
## the vehicle range), where nothing gates it.
static func cert_problem(s: Soldier) -> String:
	if not s.has_meta(&"roster_id"):
		return ""
	var m := Roster.get_member(BaseHub.roster(), String(s.get_meta(&"roster_id")))
	if m.is_empty() or Roster.hx1_certified(m):
		return ""
	return "Not certified on the HX-1 (see the base)"


## Why `s` can't climb into `suit` now ("" if it can); `reach`: check the distance too.
static func enter_problem(s: Soldier, suit: WorldItem, reach := true) -> String:
	var why := _pilot_problem(s)
	if why != "":
		return why
	if reach and parked_point(suit).distance_to(s.global_position + Vector3.UP * 1.2) > REACH_M:
		return "Too far away"
	return cert_problem(s)


## Why `s` can't become a suit's pilot now, wherever the suit is ("" if he can): his exo slot
## free (the suit goes on there: an LX-3 or another suit comes off first, by his own hand),
## his hands free, nobody being moved, not in a vehicle. Every way in checks it (enter_problem,
## climb_in_body_problem), before and after the release's wait.
static func _pilot_problem(s: Soldier) -> String:
	if s.inventory.slots.get(SLOT, &"") != &"":
		return "Climb out of your suit first" if piloting(s.inventory) else "Take off your exo frame first"
	if s.inventory.hands != &"":
		return "Your hands are full"
	if s.carry_mode != &"":
		return "You're already moving someone"
	if is_instance_valid(s.vehicle):
		return "Get out of the vehicle first"
	return ""


## Host: `s` climbs into the suit standing at `suit` (check enter_problem first). He hits the
## release on its back and it unzips (RELEASE_S, every peer: the WorldItem's "open"); then he's
## put where it stood, facing its way, wearing it with its damage; its gun goes into his hands,
## his own rifle onto its rack; it zips shut round him over ENTER_S. Interrupted (he went down
## or moved off, it's gone or taken), it stays standing, open.
static func server_enter(s: Soldier, suit: WorldItem) -> void:
	var item := ItemDB.get_item(suit.item_id)
	var from := s.global_position
	s.server_busy(RELEASE_S + ENTER_S, "Climbing into the %s" % item.name)
	var lying := bool(suit.state.get("prone", false))
	s.model.server_play(CharacterModel.MECH_RELEASE, RELEASE_S, s.to_local(parked_point(suit)), &"", &"", lying)  # (down on a knee to one lying there)
	if not bool(suit.state.get("open", false)):
		var opening := suit.state.duplicate(true)
		opening["open"] = true
		suit.state = opening  # every peer's parked suit unzips (ParkedHatch)
		if GameState.dropped.has(suit.uid):
			GameState.dropped[suit.uid]["state"] = opening.duplicate(true)
		Sfx.server_play(&"impact_plate", parked_point(suit))  # the release (a placeholder)
	await s.get_tree().create_timer(RELEASE_S).timeout
	if not is_instance_valid(s) or not s.is_inside_tree() or not s.vitals.is_up() or not is_instance_valid(suit) \
			or suit.is_queued_for_deletion() or s.global_position.distance_to(from) > 0.5 or enter_problem(s, suit) != "":
		return
	var state := suit.state.duplicate(true)
	var feet := parked_feet(suit)
	var yaw := suit.global_rotation.y
	GameState.item_taken(suit.uid)
	suit.queue_free()
	var gun: Dictionary = state.get("gun", {})
	for key: String in ["gun", "yaw", "camo", "open", "prone"]:
		state.erase(key)
	if not gun.is_empty():
		var own := s.inventory.unequip(&"primary")
		if not own.is_empty():
			state["rack"] = own
	s.inventory.put_on(SLOT, item.id, state)
	if not gun.is_empty():
		s.inventory.put_on(&"primary", StringName(gun.id), gun.get("state", {}))
	s.server_place(feet, yaw)
	if lying:  # he lies down into it, it zips shut and pushes itself up
		s.server_busy(RISE_S, "Climbing into the %s" % item.name)
		s.model.server_play(CharacterModel.MECH_RISE, RISE_S)
	else:
		s.model.server_play(CharacterModel.MECH_IN, ENTER_S)
	Sfx.server_play(&"impact_plate", feet + Vector3.UP * 1.2)  # the back, shutting (a placeholder)
	SessionLog.note("%s climbs into the %s" % [s.log_name(), item.name])


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
	var state := _suit_off(s)
	var yaw := s.global_rotation.y
	state["yaw"] = yaw
	state["camo"] = String(s.model.variant)
	state["open"] = true  # left standing with its back open, as he climbed out
	var feet := s.global_position
	var level := CompoundLevel.current(s)
	if level:
		level.server_spawn_dropped(item.id, 1, feet + Vector3.UP * PARKED_SIZE.y * 0.5, state)
	s.server_place(feet + Basis(Vector3.UP, yaw).z * STEP_OUT_M, yaw)  # behind it, out of its back
	s.model.server_play(CharacterModel.MECH_OUT, OUT_S)
	Sfx.server_play(&"impact_plate", feet + Vector3.UP * 1.2)
	SessionLog.note("%s climbs out of the %s" % [s.log_name(), item.name])


## Why `actor` can't punch the pilot `body` out of his suit now ("" if he can): a squadmate's
## manual release, on a pilot who's down or dead.
static func punch_out_problem(actor: Soldier, body: Soldier) -> String:
	if body == null or not piloting(body.inventory) or body.vitals.is_up():
		return "Only a downed or dead pilot is punched out"
	if actor.inventory.hands != &"":
		return "Your hands are full"
	if actor.carry_mode != &"":
		return "You're already moving someone"
	if body.body_point().distance_to(actor.global_position) > REACH_M + 0.5:
		return "Too far away"
	return ""


## Host: `actor` hits the manual release on the back of downed or dead pilot `body`'s suit
## ("hit the manual punch out"): its back unzips (RELEASE_S, down on a knee at it), the pilot
## comes out of it, lying beside it, and the suit is left lying face down where he lay, open,
## its damage and gun on it (his rifle back on him), for someone to climb into.
static func server_punch_out(actor: Soldier, body: Soldier) -> void:
	var item := worn(body.inventory)
	actor.server_busy(RELEASE_S, "Punching out the %s" % item.name)
	actor.model.server_play(CharacterModel.MECH_RELEASE, RELEASE_S, actor.to_local(body.body_point() + Vector3.UP * 0.3), &"", &"", true)
	await actor.get_tree().create_timer(RELEASE_S).timeout
	if not is_instance_valid(actor) or not actor.vitals.is_up() or not is_instance_valid(body) or body.is_queued_for_deletion() \
			or worn(body.inventory) != item:
		return
	server_leave_lying(body)
	SessionLog.note("%s punches %s out of the %s" % [actor.log_name(), body.log_name(), item.name])


## Why `actor` can't climb straight into downed or dead pilot `body`'s suit now ("" if he
## can): the same manual release as punching him out (punch_out_problem) — climbing in pulls
## the old pilot out as part of getting in, so needs exactly what punching out needs, plus
## what any way into a suit needs (_pilot_problem: A2-09, an LX-3 wearer passed and the suit
## he pulled off its pilot had nowhere to go) and `actor`'s own certification (cert_problem)
## since he's the one piloting it after.
static func climb_in_body_problem(actor: Soldier, body: Soldier) -> String:
	var why := punch_out_problem(actor, body)
	if why == "":
		why = _pilot_problem(actor)
	return why if why != "" else cert_problem(actor)


## Host: `actor` hits the manual release on downed or dead pilot `body`'s suit and climbs
## straight into it himself (Captain, 2026-10-17: the new pilot's own get-in, not a separate
## punch-out first) — the old pilot comes out of it, left lying beside it, and `actor` lies
## face down into the vacated suit as it zips shut and pushes itself up (as server_enter's
## lying branch does for a suit already left on the ground).
static func server_climb_in_body(actor: Soldier, body: Soldier) -> void:
	var item := worn(body.inventory)
	actor.server_busy(RELEASE_S, "Climbing into the %s" % item.name)
	actor.model.server_play(CharacterModel.MECH_RELEASE, RELEASE_S, actor.to_local(body.body_point() + Vector3.UP * 0.3), &"", &"", true)
	await actor.get_tree().create_timer(RELEASE_S).timeout
	if not is_instance_valid(actor) or not actor.is_inside_tree() or not actor.vitals.is_up() or not is_instance_valid(body) \
			or body.is_queued_for_deletion() or worn(body.inventory) != item or climb_in_body_problem(actor, body) != "":
		return
	var state := _suit_off(body)
	var yaw := body.global_rotation.y
	var feet := body.global_position
	var aside := Basis(Vector3.UP, yaw).x * (PRONE_SIZE.x * 0.5 + 0.45)
	body.server_place(feet + aside, yaw)  # the old pilot out of it, left lying beside it
	var gun: Dictionary = state.get("gun", {})
	for key: String in ["gun", "yaw", "camo", "open", "prone"]:
		state.erase(key)
	if not gun.is_empty():
		var own := actor.inventory.unequip(&"primary")
		if not own.is_empty():
			state["rack"] = own
	actor.inventory.put_on(SLOT, item.id, state)
	if not gun.is_empty():
		actor.inventory.put_on(&"primary", StringName(gun.id), gun.get("state", {}))
	actor.server_place(feet, yaw)
	actor.server_busy(RISE_S, "Climbing into the %s" % item.name)
	actor.model.server_play(CharacterModel.MECH_RISE, RISE_S)
	Sfx.server_play(&"impact_plate", feet + Vector3.UP * 1.2)
	SessionLog.note("%s climbs into %s's %s" % [actor.log_name(), body.log_name(), item.name])


## Host: the suit `body` wears comes off him and is left lying face down where he is, facing
## his way, its back open (the punch-out's end); him beside it.
static func server_leave_lying(body: Soldier) -> void:
	var item := worn(body.inventory)
	if item == null:
		return
	var state := _suit_off(body)
	var yaw := body.global_rotation.y
	var feet := body.global_position
	state["yaw"] = yaw
	state["camo"] = String(body.model.variant)
	state["open"] = true
	state["prone"] = true
	var level := CompoundLevel.current(body)
	if level:
		level.server_spawn_dropped(item.id, 1, prone_centre(feet, yaw), state)
	var aside := Basis(Vector3.UP, yaw).x * (PRONE_SIZE.x * 0.5 + 0.45)
	body.server_place(feet + aside, yaw)  # the pilot out of it, beside it
	Sfx.server_play(&"impact_plate", feet + Vector3.UP * 0.5)


## Host: takes the suit off `s` (its state: his own rifle back on him off its rack, its gun
## back on it).
static func _suit_off(s: Soldier) -> Dictionary:
	var removed := s.inventory.unequip(SLOT)
	var state: Dictionary = removed.get("state", {}).duplicate(true)
	var primary: StringName = s.inventory.slots.get(&"primary", &"")
	if primary != &"" and mech_only(ItemDB.get_item(primary)):
		state["gun"] = s.inventory.unequip(&"primary")
	var rack: Dictionary = state.get("rack", {})
	state.erase("rack")
	if not rack.is_empty():
		s.inventory.put_on(&"primary", StringName(rack.id), rack.get("state", {}))
	return state


# --- A suit left standing (WorldItem) -------------------------------------------------------

## A parked suit's box: lying face down, or standing.
static func parked_size(state: Dictionary) -> Vector3:
	return PRONE_SIZE if bool(state.get("prone", false)) else PARKED_SIZE


## Where a suit lying face down with its feet at `feet`, facing `yaw`, has its box's centre.
static func prone_centre(feet: Vector3, yaw: float) -> Vector3:
	return feet + Vector3.UP * PRONE_SIZE.y * 0.5 - Basis(Vector3.UP, yaw).z * PRONE_SIZE.z * 0.5


## Where a parked suit's feet are (world): under it standing, at the back end of it lying.
static func parked_feet(suit: Node3D) -> Vector3:
	var b := suit.global_basis
	if suit is WorldItem and bool((suit as WorldItem).state.get("prone", false)):
		return suit.global_position - b.y * PRONE_SIZE.y * 0.5 + b.z * PRONE_SIZE.z * 0.5
	return suit.global_position - b.y * PARKED_SIZE.y * 0.5

## Where a parked suit's interaction point is: at the release on its back (world), standing or
## lying.
static func parked_point(suit: Node3D) -> Vector3:
	var bones := suit.get_node_or_null(^"ParkedSuit/Bones") as Node3D
	if bones:
		return bones.to_global(RELEASE_AT)
	return suit.global_position + suit.global_basis.y * 0.35 + suit.global_basis.z * 0.5


## The release panel on its back, in its bones' space (dress: the right lid's panel).
const RELEASE_AT := Vector3(0.1, 1.32, 0.46)


## A parked suit: the chassis standing open on a bare skeleton (its rest pose, arms a little
## out), its plates real VoxelArmor that records hits into the WorldItem's state ("pads"), in
## the camo of whoever left it ("camo"). Centred on its box (PARKED_SIZE), like a WorldItem.
static func parked_node(item: ItemData, state: Dictionary, suit: WorldItem) -> Node3D:
	var root := Node3D.new()
	root.name = "ParkedSuit"
	var bones := Skeleton.new()
	var size := Vector3.ONE * float(item.stats.get("size", 1.25))  # the suit's own size, as worn (size)
	if bool(state.get("prone", false)):
		# Lying face down: its feet at the box's back end, turned onto its front, up off the ground.
		root.position = Vector3(0, -PRONE_SIZE.y * 0.5, PRONE_SIZE.z * 0.5)
		bones.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2).scaled(size), Vector3.UP * LIE_LIFT)
	else:
		root.position = Vector3.DOWN * PARKED_SIZE.y * 0.5
		bones.scale = size
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
		piece.transform = pad.at
		piece.set_camo(variant)
	show_parked_damage(root, state)
	dress(bones, item, bool(state.get("disabled", false)), 1, variant)
	var hatch := ParkedHatch.new()
	hatch.name = "ParkedHatch"
	hatch.item = item
	hatch.bones = bones
	hatch.shown = 1.0 if bool(state.get("open", false)) else 0.0
	hatch.target = hatch.shown
	root.add_child(hatch)
	hatch.apply()
	return root


## Redraws a parked suit's plates from `state` (its "pads": chips, integrity), and has its back
## unzip (or zip up) to `state`'s "open".
static func show_parked_damage(root: Node3D, state: Dictionary) -> void:
	var hatch := root.get_node_or_null(^"ParkedHatch") as ParkedHatch
	if hatch:
		hatch.target = 1.0 if bool(state.get("open", false)) else 0.0
	var pads: Dictionary = state.get("pads", {})
	for piece: VoxelArmor in root.find_children("MechPad_*", "VoxelArmor", true, false):
		var pad: Dictionary = pads.get(piece.pad, {})
		piece.apply_damage(pad.get("chips", []), ArmorRules.is_shattered(pad))


## A pad's transform with the back `open` (0..1, the whole zipper) of the way open (HATCH,
## piece_open; others as they are).
static func hatched(pad: String, at: Transform3D, open: float) -> Transform3D:
	if not HATCH.has(pad):
		return at
	var o := piece_open(pad, open)
	if o <= 0.0:
		return at
	var hinge: Vector3 = HATCH[pad][0]
	var swing := Transform3D(Basis(HATCH[pad][1] as Vector3, float(HATCH[pad][2]) * o), Vector3.ZERO)
	return Transform3D(Basis.IDENTITY, hinge) * swing * Transform3D(Basis.IDENTITY, -hinge) * at


## The power pack's halves on `torso` (dress's lids) swung with the back plate's halves.
static func set_lids(torso: Node3D, open: float) -> void:
	for side: String in LID:
		var lid := torso.get_node_or_null(NodePath(PART_NAME + "Lid_" + side)) as Node3D
		if lid:
			lid.transform = hatched(LID[side], Transform3D.IDENTITY, open)


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
	# Captain's refs (2026-10-17, "its not it"): a big hunched chassis, much bigger than a man, the
	# head sunk low between high shoulders, huge pauldrons and forearms, thick legs on big feet,
	# a power pack with a launcher pod on the back. Under the plates, dark mechanical cores in
	# place of the pilot's body (hide_pilot), so the gaps read as machinery, not uniform.
	_core(_box(torso, Vector3(0.36, 0.56, 0.26), Vector3(0, 0.3, 0.0), JOINT, layers))  # torso core
	_core(_box(torso, Vector3(0.26, 0.2, 0.22), Vector3(0, -0.02, 0.0), STRUT, layers))  # waist core
	# The power pack in two halves split down the spine (its armour plates, "back_r" and "back_l",
	# over their rear faces): the back hatch, each half on a lid that swings out with its plate
	# (HATCH, set_lids), padded inside.
	for side: float in [1.0, -1.0]:
		var lid := Node3D.new()
		lid.name = PART_NAME + "Lid_" + ("r" if side > 0.0 else "l")
		torso.add_child(lid)
		_box(lid, Vector3(0.26, 0.56, 0.2), Vector3(side * 0.13, 0.33, 0.27), shell, layers)  # its half of the pack
		_box(lid, Vector3(0.22, 0.5, 0.02), Vector3(side * 0.12, 0.33, 0.16), Color("2b2c27"), layers)  # its padded lining
		_box(lid, Vector3(0.2, 0.08, 0.16), Vector3(side * 0.1, 0.65, 0.25), JOINT, layers)
		_rod(lid, 0.035, 0.18, Vector3(side * 0.15, 0.74, 0.3), JOINT, layers)  # exhaust stack
		for i in 4:
			_box(lid, Vector3(0.012, 0.035, 0.17), Vector3(side * 0.266, 0.2 + i * 0.07, 0.27), JOINT, layers)  # vent slats
		if side > 0.0:
			# The launcher pod (art: it doesn't fire yet), four tubes up top, and the manual
			# release: a panel with a green button and a warning triangle.
			_box(lid, Vector3(0.15, 0.36, 0.18), Vector3(0.2, 0.72, 0.33), shell, layers)
			for i in 4:
				_box(lid, Vector3(0.05, 0.012, 0.05), Vector3(0.2 + (i % 2 - 0.5) * 0.07, 0.905, 0.3 + (floorf(i / 2.0) - 0.5) * 0.07), JOINT, layers)
			_box(lid, Vector3(0.1, 0.12, 0.012), Vector3(0.1, 0.42, 0.444), STRUT, layers)  # release panel
			_glow(_box(lid, Vector3(0.03, 0.03, 0.01), Vector3(0.08, 0.44, 0.452), Color(0.2, 0.9, 0.5), layers), 1.2)  # its button
			_box(lid, Vector3(0.035, 0.03, 0.01), Vector3(0.125, 0.4, 0.452), Color(0.95, 0.75, 0.15), layers)  # the warning triangle
		else:
			var light := _box(lid, Vector3(0.03, 0.03, 0.012), Vector3(-0.08, 0.6, 0.44), ExoFrame.LIGHT_OFF if disabled else ExoFrame.LIGHT_ON, layers)
			_glow(light, 1.5)
	for side: float in [1.0, -1.0]:
		_box(torso, Vector3(0.14, 0.16, 0.26), Vector3(side * 0.27, 0.6, 0.08), STRUT, layers)  # shoulder actuator
		_box(torso, Vector3(0.17, 0.17, 0.3), Vector3(side * 0.2, 0.66, 0.0), shell, layers)  # shoulder hump, up beside the head
		_box(torso, Vector3(0.06, 0.1, 0.32), Vector3(side * 0.2, 0.0, 0.0), JOINT, layers)  # hip ring, side
		_box(torso, Vector3(0.16, 0.18, 0.04), Vector3(side * 0.12, -0.1, -0.18), shell, layers)  # tasset
		_box(torso, Vector3(0.05, 0.2, 0.2), Vector3(side * 0.205, -0.08, 0.0), shell, layers)  # hip plate
	_box(torso, Vector3(0.42, 0.1, 0.05), Vector3(0, 0.0, -0.165), JOINT, layers)  # hip ring, front
	_box(torso, Vector3(0.42, 0.1, 0.05), Vector3(0, 0.0, 0.165), JOINT, layers)  # hip ring, back
	_box(torso, Vector3(0.3, 0.1, 0.3), Vector3(0, 0.59, 0.03), JOINT, layers)  # collar the head sits down in
	for side: float in [1.0, -1.0]:
		var r := side > 0.0
		var upper: Node3D = rig.part_node(Vitals.UPPER_ARM_R if r else Vitals.UPPER_ARM_L)
		var fore: Node3D = rig.part_node(Vitals.FOREARM_R if r else Vitals.FOREARM_L)
		var thigh: Node3D = rig.part_node(Vitals.THIGH_R if r else Vitals.THIGH_L)
		var shin: Node3D = rig.part_node(Vitals.SHIN_R if r else Vitals.SHIN_L)
		_core(_box(upper, Vector3(0.12, 0.3, 0.12), Vector3(0, -0.16, 0), JOINT, layers))  # arm core
		_box(upper, Vector3(0.14, 0.14, 0.14), Vector3(side * 0.05, -0.01, 0), JOINT, layers)  # shoulder joint
		_rod(upper, 0.014, 0.22, Vector3(side * 0.13, -0.18, 0.06), PISTON, layers)
		_drum(upper, 0.055, 0.07, Vector3(side * 0.08, -0.32, 0), JOINT, layers)  # elbow
		_core(_box(fore, Vector3(0.11, 0.24, 0.11), Vector3(0, -0.12, 0), JOINT, layers))  # forearm core
		_box(fore, Vector3(0.15, 0.11, 0.16), Vector3(0, -0.275, -0.01), shell.darkened(0.25), layers)  # mechanical fist
		_box(fore, Vector3(0.13, 0.035, 0.14), Vector3(0, -0.215, -0.01), JOINT, layers)  # its cuff
		_rod(fore, 0.012, 0.17, Vector3(side * 0.12, -0.11, 0.05), PISTON, layers)
		_core(_box(thigh, Vector3(0.15, 0.42, 0.15), Vector3(side * 0.02, -0.22, 0), JOINT, layers))  # thigh core
		_drum(thigh, 0.06, 0.07, Vector3(side * 0.17, -0.02, 0), JOINT, layers)  # hip
		_box(thigh, Vector3(0.05, 0.3, 0.08), Vector3(side * 0.19, -0.23, 0.04), STRUT, layers)  # thigh actuator
		_rod(thigh, 0.017, 0.3, Vector3(side * 0.19, -0.24, -0.025), PISTON, layers)
		_drum(thigh, 0.07, 0.09, Vector3(side * 0.17, -0.45, 0), JOINT, layers)  # knee
		_box(thigh, Vector3(0.17, 0.13, 0.06), Vector3(side * 0.03, -0.46, -0.14), shell, layers)  # knee cap
		_core(_box(shin, Vector3(0.14, 0.38, 0.14), Vector3(side * 0.02, -0.19, 0), JOINT, layers))  # shin core
		_box(shin, Vector3(0.05, 0.28, 0.08), Vector3(side * 0.17, -0.2, 0.045), STRUT, layers)  # shin actuator
		_rod(shin, 0.016, 0.28, Vector3(side * 0.17, -0.2, -0.015), PISTON, layers)
		_box(shin, Vector3(0.14, 0.26, 0.08), Vector3(side * 0.02, -0.19, 0.15), STRUT, layers)  # calf hydraulics
		_drum(shin, 0.05, 0.22, Vector3(side * 0.02, -0.36, 0.0), JOINT, layers)  # ankle
		_box(shin, Vector3(0.23, 0.11, 0.4), Vector3(side * 0.02, -0.395, -0.06), JOINT, layers)  # big armoured foot
		_box(shin, Vector3(0.22, 0.05, 0.14), Vector3(side * 0.02, -0.34, -0.2), shell, layers)  # toe plate
		_box(shin, Vector3(0.13, 0.06, 0.08), Vector3(side * 0.02, -0.42, 0.16), STRUT, layers)  # heel spur
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
		_glow(_box(head, Vector3(0.028, 0.022, 0.012), Vector3((i - 1) * 0.055, 0.145, -0.225), SENSOR, layers), 2.0)
	for side: float in [1.0, -1.0]:
		_box(head, Vector3(0.04, 0.09, 0.11), Vector3(side * 0.225, 0.13, 0.0), STRUT, layers)
	_rod(head, 0.005, 0.22, Vector3(0.15, 0.33, 0.12), JOINT, layers)
	if rig is CharacterModel:
		var hatch := HatchRig.new()
		hatch.name = PART_NAME + "Hatch"
		hatch.item = item
		rig.add_child(hatch)


## A parked suit's back unzipping (or zipping up) to its state's "open" over RELEASE_S, on
## every peer: its plates and the power pack's halves swing on their hinges (HATCH).
class ParkedHatch extends Node:
	var item: ItemData
	var bones: Node3D
	var shown := 0.0
	var target := 0.0

	func _process(delta: float) -> void:
		if shown != target:
			shown = move_toward(shown, target, delta / ExoMech.RELEASE_S)
			apply()

	func apply() -> void:
		for piece: VoxelArmor in bones.find_children("MechPad_*", "VoxelArmor", true, false):
			for pad: Dictionary in ExoFrame.pad_items(item):
				if pad.id == piece.pad:
					piece.transform = ExoMech.hatched(pad.id, pad.at, shown)
		ExoMech.set_lids(bones.torso, shown)


## Animates a worn suit's hatch (HATCH) while its pilot climbs in or out: the pads GearRig
## put on the bones swing on their hinges, and settle shut once the clip is over. While it
## stands open, the pilot's body shows inside it (hide_pilot hides it the rest of the time).
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
		if (open > 0.02) != (_shown > 0.02):
			ExoMech.hide_pilot(model, [], open <= 0.02)  # him, inside it while it's open
			for n: Node in model.find_children(ExoMech.PART_NAME + "*", "MeshInstance3D", true, false):
				if n.has_meta(&"mech_core"):
					(n as Node3D).visible = open <= 0.02  # (its machinery cores out of the way meanwhile)
		_shown = open
		var pads := gear.pads()
		for pad: Dictionary in ExoFrame.pad_items(item):
			var piece: VoxelArmor = pads.get(pad.id)
			if piece and ExoMech.HATCH.has(pad.id):
				piece.transform = ExoMech.hatched(pad.id, pad.at, open)
		ExoMech.set_lids(model.torso, open)


## Marks a dark machinery core (in place of the pilot's body): HatchRig hides it while the back
## stands open, so he's seen inside.
static func _core(m: MeshInstance3D) -> void:
	m.set_meta(&"mech_core", true)


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
