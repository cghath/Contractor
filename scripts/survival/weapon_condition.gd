class_name WeaponCondition
extends RefCounted
## Weapon wear, jams and cleaning (call 120; docs/survival_wear.md): a gun's or a melee weapon's
## `condition` 0-100 in its item state (Wear.KEY; absent = 100).
## Guns: every shot wears it (more when wet: rain on him, soaked clothes, wading or swimming; much
## more for improvised guns), a wet gun rusts by the hour; under JAM_FROM a shot can jam (the shot
## fails, "jammed" on the state) and R clears it (CLEAR_S by firearms level: jam clearing at 3);
## at 0 it's broken and won't fire until a gun repair kit (firearms REPAIR_LEVEL). A cleaning kit
## (with gun oil carried, more and to full) and gun oil alone (a wipe) bring it back.
## Melee: every swing wears it; a dull blade hits softer (down to DULL_MULT), a whetstone sharpens
## it; a worn-out blunt weapon is taped up with duct tape; a worn axe or hatchet fells slower
## (Trees reads tool_mult). Host side; every number is Proposed.
## The AI fires through the same Soldier._server_fire, so companions', settlers' and raiders' guns
## wear and jam the same way; an AI clears its own jam (ai_clear: AI_CLEAR_S and a "Jammed!" bark).
## Raiders' guns come used (server_used_guns, RAIDER_COND). A mounted suppressor wears per shot
## (can_wear: CAN_SHOTS_FACTORY, the improvised oil-filter Gunsmith.CAN_SHOTS), lets more sound out
## as it wears (can_loss, heard_m) and is gone at 0. Any gun worn to HOT_GUN_AT or under firing hot
## hand-loads (AmmoCondition.hot) may blow like a pipe gun (HOT_BLOW_CHANCE: Gunsmith.server_blow).

const SHOT_WEAR := 0.08
const WET_SHOT_X := 2.5
const IMPROVISED_X := 3.0
const RUST_H := 0.25          # condition lost a world hour wet
const DRY_H := 0.25           # a soaked gun dries in about 4 world hours
const JAM_FROM := 70.0
const JAM_MAX := 0.15         # the jam chance a shot at condition 0 (x IMPROVISED_X for pipe guns)
const CLEAR_S: Array[float] = [3.0, 1.5, 1.0]  # firearms 0-2, 3-5, 6+
const CLEAR_FAST_LEVEL := 3
const CLEAR_FASTEST_LEVEL := 6
const CLEAN_S := 20.0
const CLEAN_ADD := 30.0
const CLEAN_MAX := 85.0
const OIL_ADD := 20.0         # more when a gun oil is used with the kit (one bottle used up)
const OIL_MAX := 100.0
const OIL_WIPE := 8.0         # gun oil alone: a wipe and dry
const OIL_S := 5.0
const REPAIR_TO := 45.0
const REPAIR_S := 40.0
const REPAIR_LEVEL := 2
const SWING_WEAR := 0.12
const CHOP_WEAR_S := 0.05     # an axe's condition a second of felling
const DULL_FULL := 50.0       # a blade at or above this cuts as new
const DULL_LOW := 20.0        # at or below this, DULL_MULT
const DULL_MULT := 0.7
const BLUNT_WORN_MULT := 0.85 # a blunt weapon worn to nothing still hits, a little softer
const SHARPEN_S := 8.0
const SHARPEN_ADD := 50.0
const TAPE_S := 6.0
const TAPE_ADD := 30.0
const AXE_SLOW := 1.6         # a worn-out axe takes this much longer to fell a tree
## A found gun's condition (the early loot curve: found_state): kept dry (a home, a store, a sealed
## box) or out in the weather (on one of the dead, a box in the open). Proposed.
const FOUND_DRY := Vector2(40.0, 85.0)
const FOUND_WET := Vector2(10.0, 45.0)
const FOUND_WET_BROKEN := 0.2   # out in the weather, rusted through (0: a gun repair kit)
const FOUND_JAMMED := Vector2(0.1, 0.45)  # dry, wet: found with a round stuck in it

## The AI clearing its own jam (s), and the used guns raiders carry (a found condition, dry-ish).
const AI_CLEAR_S := 2.0
const RAIDER_COND := Vector2(30.0, 75.0)
## A suppressor's life in shots: a factory can, wearing evenly to 0 (the oil-filter can: Gunsmith.CAN_SHOTS).
const CAN_SHOTS_FACTORY := 4000.0
## Under CAN_LOSS_FROM the can lets more out: the heard radius grows toward unsuppressed at 0.
const CAN_LOSS_FROM := 60.0
## A gun worn to this or under, firing hot hand-loads, may blow (x the hand-loaded share).
const HOT_GUN_AT := 5.0
const HOT_BLOW_CHANCE := 0.05

const CLEANING_KIT := &"gun_cleaning_kit"
const GUN_OIL := &"gun_oil"
const REPAIR_KIT := &"gun_repair_kit"
const WHETSTONE := &"whetstone"
const DUCT_TAPE := &"duct_tape"


static func is_gun(item: ItemData) -> bool:
	return item != null and item.type == "weapon" and not MeleeWeapons.is_melee(item)


static func improvised(item: ItemData) -> bool:
	return item != null and item.tags.has("improvised")


static func jammed(state: Dictionary) -> bool:
	return bool(state.get("jammed", false))


static func is_broken(state: Dictionary) -> bool:
	return state.has(Wear.KEY) and Wear.cond(state) <= 0.0


## The chance a shot jams at condition `c` (0 from JAM_FROM up, JAM_MAX at 0, quadratic).
static func jam_chance(c: float, item: ItemData = null, wet := false) -> float:
	if c >= JAM_FROM:
		return 0.0
	var t := (JAM_FROM - c) / JAM_FROM
	return clampf(JAM_MAX * t * t * (IMPROVISED_X if improvised(item) else 1.0) * (1.25 if wet else 1.0), 0.0, 0.9)


## A found gun's state (the early loot curve, docs/survival_deadtime.md): its default state (a full
## magazine, a full tube) with a found condition: FOUND_DRY kept dry, else FOUND_WET, rusted
## through (0, broken) FOUND_WET_BROKEN of the time, and wet; jammed FOUND_JAMMED of the time.
## `rounds` >= 0: what's left loaded (the dead's mostly empty magazine).
static func found_state(item: ItemData, dry: bool, rng: RandomNumberGenerator, rounds := -1) -> Dictionary:
	var st: Dictionary = item.default_state().duplicate(true) if item else {}
	if not is_gun(item):
		return st
	var r := FOUND_DRY if dry else FOUND_WET
	var c := roundf(lerpf(r.x, r.y, rng.randf()))
	if not dry and rng.randf() < FOUND_WET_BROKEN:
		c = 0.0
	Wear.set_cond(st, c)
	if c > 0.0 and rng.randf() < (FOUND_JAMMED.x if dry else FOUND_JAMMED.y):
		st["jammed"] = true
	if not dry:
		st["wet"] = true
	if rounds >= 0 and st.has("rounds"):
		st["rounds"] = mini(rounds, int(st.rounds))
	return st

# --- Shots (Soldier._server_fire) ----------------------------------------------------------------

## Host, before a shot from the gun in `slot`: true if it doesn't fire (jammed, broken, or it jams
## now). The shooter hears why (not every frame of a held trigger).
static func server_blocked(s: Soldier, slot: StringName, weapon: ItemData) -> bool:
	if not Wear.enabled() or not is_gun(weapon):
		return false
	var st := Wear.slot_state_rw(s.inventory, slot)
	if jammed(st):
		_nag(s, "Jammed: R to clear it")
		ai_clear(s, slot)
		return true
	if improvised(weapon) and Gunsmith.server_improvised(s, slot, weapon, st):
		return true  # a misfire (the round lost), or at 0% it blew (call 85: Gunsmith)
	if not improvised(weapon) and Wear.cond(st) <= HOT_GUN_AT and AmmoCondition.hot(st) and Gunsmith._has_round(s, slot, weapon) \
			and Wear.roll() < HOT_BLOW_CHANCE * float(st.get(AmmoCondition.IN_GUN_HL, 0.0)):
		Gunsmith.server_blow(s, slot, weapon)  # a worn-out gun on a hot hand-load (call 43)
		return true
	if is_broken(st) and not improvised(weapon):  # (a crude gun at 0% still goes bang, until it blows)
		_nag(s, "It's broken: it needs a gun repair kit")
		return true
	if Wear.roll() < jam_chance(Wear.cond(st), weapon, bool(st.get("wet", false))):
		st["jammed"] = true
		s.inventory._commit()
		s._server_next_shot = Soldier._now() + 0.3
		Wear.tell(s, "Jammed! R to clear it")
		ai_clear(s, slot)
		return true
	return false


## Host, after the round left: a dud from bad ammunition (AmmoCondition) jams it: true then.
static func server_dud(s: Soldier, slot: StringName, weapon: ItemData) -> bool:
	if not Wear.enabled() or not is_gun(weapon):
		return false
	var st := Wear.slot_state_rw(s.inventory, slot)
	var chance := AmmoCondition.misfire_chance(float(st.get(AmmoCondition.IN_GUN, 100.0)))
	if improvised(weapon):
		chance = minf(0.9, chance + 0.03)
	if chance <= 0.0 or Wear.roll() >= chance:
		return false
	st["jammed"] = true
	s.inventory._commit()
	Wear.tell(s, "Click. A dud: R to clear it")
	ai_clear(s, slot)
	return true


## Host: the shot's wear on the gun in `slot`.
static func on_shot(s: Soldier, slot: StringName, weapon: ItemData) -> void:
	if not Wear.enabled() or not is_gun(weapon):
		return
	var st := Wear.slot_state_rw(s.inventory, slot)
	Wear.set_cond(st, Wear.cond(st) - shot_wear(weapon, bool(st.get("wet", false))))
	can_wear(s, weapon, st)  # the suppressor on it (call 38; the oil-filter can: call 85)


static func shot_wear(weapon: ItemData, wet: bool) -> float:
	return SHOT_WEAR * (WET_SHOT_X if wet else 1.0) * (IMPROVISED_X if improvised(weapon) else 1.0)


# --- The AI's guns ---------------------------------------------------------------------------------

## Host: an AI (a companion, a settler, a raider) clears the jam in `slot` itself: AI_CLEAR_S busy,
## a "Jammed!" bark (a companion's own line), then cleared. Once per jam.
static func ai_clear(s: Soldier, slot: StringName) -> void:
	if s == null or not s.is_ai() or not s.is_inside_tree():
		return
	var now := Soldier._now()
	if now < float(s.get_meta(&"jam_clear_until", -1.0)):
		return
	s.set_meta(&"jam_clear_until", now + AI_CLEAR_S)
	s.set_meta(&"jam_bark", now)
	var ai := CompanionAI.of(s)
	if ai and ai.layer:
		var line := TalkMenu.line_for(ai.rec, "jammed")
		ai.layer.say(s, line if line != "" else "Jammed!")
	var rev := s.inventory.slot_revision(slot)
	var done := func() -> void:
		if s.inventory.slot_revision(slot) == rev:
			Wear.slot_state_rw(s.inventory, slot).erase("jammed")
			s.inventory._commit()
	Wear.timed(s, AI_CLEAR_S, "Clearing the jam", done)


## Host (WorldLive, the convoy's ambush): a raider's guns come used: a condition in RAIDER_COND,
## so a looted raider gun shows its use; they wear on as they fire.
static func server_used_guns(s: Soldier, rng: RandomNumberGenerator = null) -> void:
	if not Wear.enabled() or s == null:
		return
	var changed := false
	for slot: StringName in Inventory.WEAPON_SLOTS:
		var id := StringName(s.inventory.slots.get(slot, &""))
		if id == &"" or not is_gun(ItemDB.get_item(id)):
			continue
		var st := Wear.slot_state_rw(s.inventory, slot)
		if st.has(Wear.KEY):
			continue
		var t := rng.randf() if rng else randf()
		Wear.set_cond(st, roundf(lerpf(RAIDER_COND.x, RAIDER_COND.y, t)))
		changed = true
	if changed:
		s.inventory._commit()

# --- Suppressors ---------------------------------------------------------------------------------

static func can_cond(state: Dictionary) -> float:
	return clampf(float(state.get(Suppressors.CAN_KEY, 100.0)), 0.0, 100.0)


## How much of the can's suppression is lost on `weapon` with `state`: 0 (as new, or no can) .. 1.
static func can_loss(weapon: ItemData, state: Dictionary) -> float:
	if Suppressors.mounted(weapon, state) == null:
		return 0.0
	return clampf((CAN_LOSS_FROM - can_cond(state)) / CAN_LOSS_FROM, 0.0, 1.0)


## The dead's hearing radius of a shot (Soldier._server_fire): suppressed, it grows with `loss`
## toward an unsuppressed shot's.
static func heard_m(suppressed: bool, loss: float) -> float:
	if not suppressed:
		return ZombieAI.SHOT_HEARD_M
	return lerpf(ZombieAI.SUPPRESSED_HEARD_M, ZombieAI.SHOT_HEARD_M, clampf(loss, 0.0, 1.0))


## A shot's wear on the can on the gun (`st` its state): a factory can over CAN_SHOTS_FACTORY,
## the improvised oil-filter over Gunsmith.CAN_SHOTS; at 0 it's shot through and gone.
static func can_wear(s: Soldier, weapon: ItemData, st: Dictionary) -> void:
	var can := Suppressors.mounted(weapon, st)
	if can == null:
		return
	var per := 100.0 / (float(Gunsmith.CAN_SHOTS) if can.tags.has("improvised") else CAN_SHOTS_FACTORY)
	var c := can_cond(st) - per
	if c <= 0.01:
		st.erase(Suppressors.STATE_KEY)
		st.erase(Suppressors.CAN_KEY)
		s.inventory._commit()
		Wear.tell(s, "The %s is shot through" % can.name.to_lower())
		return
	st[Suppressors.CAN_KEY] = snappedf(c, 0.001)


static func _nag(s: Soldier, text: String) -> void:
	var now := Soldier._now()
	if now >= float(s.get_meta(&"wear_nag_at", -10.0)) + 1.0:
		s.set_meta(&"wear_nag_at", now)
		Wear.tell(s, text)


## Seconds to clear a jam for `s` (CLEAR_S by firearms level).
static func clear_s(s: Soldier) -> float:
	var lvl := Rpg.level(s, "firearms")
	return CLEAR_S[2] if lvl >= CLEAR_FASTEST_LEVEL else (CLEAR_S[1] if lvl >= CLEAR_FAST_LEVEL else CLEAR_S[0])


## Host (Soldier._server_reload): a jammed gun in `slot` is cleared instead of reloaded. True if
## it was jammed (the clear started).
static func server_try_clear(s: Soldier, slot: StringName, instant := false) -> bool:
	if not Wear.enabled():
		return false
	var st := s.inventory.state_of(slot)
	if not jammed(st):
		return false
	var rev := s.inventory.slot_revision(slot)
	var done := func() -> void:
		if s.inventory.slot_revision(slot) == rev:
			Wear.slot_state_rw(s.inventory, slot).erase("jammed")
			s.inventory._commit()
			Rpg.xp(s, "firearms", 1.0)
			Wear.tell(s, "Cleared")
	Wear.timed(s, clear_s(s), "Clearing the jam", done, instant)
	return true


# --- Carried: the wet and rust ----------------------------------------------------------------------

## `world_h` world hours of the guns `s` carries in slots: wet ones (`wet`: he's in the rain or
## soaked) soak, rust by RUST_H an hour, and dry out of it.
static func step_carried(s: Soldier, world_h: float, wet: bool) -> void:
	for slot: StringName in Inventory.WEAPON_SLOTS:
		var id := StringName(s.inventory.slots.get(slot, &""))
		if id == &"" or not is_gun(ItemDB.get_item(id)):
			continue
		var st := Wear.slot_state_rw(s.inventory, slot)
		if wet:
			st["wet"] = true
		elif st.has("wet"):
			var left := float(st.get("wet_h", 1.0 / DRY_H)) - world_h
			if left <= 0.0:
				st.erase("wet")
				st.erase("wet_h")
			else:
				st["wet_h"] = left
		if bool(st.get("wet", false)):
			Wear.set_cond(st, Wear.cond(st) - RUST_H * world_h)
			if wet:
				st["wet_h"] = 1.0 / DRY_H


# --- Cleaning and repair -----------------------------------------------------------------------------

## The gun to clean: the one in his hands if it's a gun, else the most worn gun in a slot.
static func gun_to_clean(s: Soldier) -> StringName:
	return _pick(s, func(item: ItemData, st: Dictionary) -> bool: return is_gun(item) and not is_broken(st) and (Wear.cond(st) < 99.5 or bool(st.get("wet", false)) or jammed(st)))


static func broken_gun(s: Soldier) -> StringName:
	return _pick(s, func(item: ItemData, st: Dictionary) -> bool: return is_gun(item) and is_broken(st))


static func blade_to_sharpen(s: Soldier) -> StringName:
	return _pick(s, func(item: ItemData, st: Dictionary) -> bool: return MeleeWeapons.is_blade(item) and Wear.cond(st) < 99.5)


static func blunt_to_tape(s: Soldier) -> StringName:
	return _pick(s, func(item: ItemData, st: Dictionary) -> bool: return MeleeWeapons.is_melee(item) and not MeleeWeapons.is_blade(item) and Wear.cond(st) < 99.5)


## The weapon slot whose item and state pass `ok`: the one in his hands first, else the most worn.
static func _pick(s: Soldier, ok: Callable) -> StringName:
	var best := &""
	var best_c := 1000.0
	for slot: StringName in Inventory.WEAPON_SLOTS:
		var id := StringName(s.inventory.slots.get(slot, &""))
		if id == &"":
			continue
		var st := s.inventory.state_of(slot)
		if not ok.call(ItemDB.get_item(id), st):
			continue
		if slot == s.active_slot:
			return slot
		if Wear.cond(st) < best_c:
			best = slot
			best_c = Wear.cond(st)
	return best


## Host: `s` cleans the gun in `slot` with his cleaning kit: CLEAN_S (x0.75 from firearms 3), then
## +CLEAN_ADD up to CLEAN_MAX, or with a gun oil carried (used up) +CLEAN_ADD+OIL_ADD up to
## OIL_MAX; dry and unjammed. A use of the kit.
static func server_clean(s: Soldier, slot: StringName, instant := false) -> void:
	var rev := s.inventory.slot_revision(slot)
	var secs := CLEAN_S * (0.75 if Rpg.level(s, "firearms") >= CLEAR_FAST_LEVEL else 1.0)
	var done := func() -> void:
		if s.inventory.slot_revision(slot) != rev or not Wear.spend_tool(s.inventory, CLEANING_KIT):
			Wear.tell(s, "Something's missing")
			return
		var oiled := s.inventory.remove_one(GUN_OIL)
		var st := Wear.slot_state_rw(s.inventory, slot)  # (after the commits: they rebuild the states)
		var c := Wear.cond(st)
		Wear.set_cond(st, maxf(c, minf(c + CLEAN_ADD + (OIL_ADD if oiled else 0.0), OIL_MAX if oiled else CLEAN_MAX)))
		for k: String in ["wet", "wet_h", "jammed"]:
			st.erase(k)
		s.inventory._commit()
		Rpg.xp(s, "firearms", 2.0)
		Wear.tell(s, "Cleaned%s: %d%%" % [" and oiled" if oiled else "", roundi(Wear.cond(st))])
	Wear.timed(s, secs, "Cleaning the gun", done, instant)


## Host: a wipe with gun oil alone: dry, +OIL_WIPE (up to CLEAN_MAX); one oil used.
static func server_oil(s: Soldier, slot: StringName, instant := false) -> void:
	var rev := s.inventory.slot_revision(slot)
	var done := func() -> void:
		if s.inventory.slot_revision(slot) != rev or not s.inventory.remove_one(GUN_OIL):
			return
		var st := Wear.slot_state_rw(s.inventory, slot)
		var c := Wear.cond(st)
		Wear.set_cond(st, maxf(c, minf(c + OIL_WIPE, CLEAN_MAX)))
		st.erase("wet")
		st.erase("wet_h")
		s.inventory._commit()
		Wear.tell(s, "Oiled: %d%%" % roundi(Wear.cond(st)))
	Wear.timed(s, OIL_S, "Oiling the gun", done, instant)


## Host: a broken gun in `slot` repaired with a gun repair kit (used up): REPAIR_TO.
static func server_repair(s: Soldier, slot: StringName, instant := false) -> void:
	var rev := s.inventory.slot_revision(slot)
	var done := func() -> void:
		if s.inventory.slot_revision(slot) != rev or not s.inventory.remove_one(REPAIR_KIT):
			return
		var st := Wear.slot_state_rw(s.inventory, slot)
		Wear.set_cond(st, maxf(Wear.cond(st), REPAIR_TO))
		st.erase("jammed")
		s.inventory._commit()
		Rpg.xp(s, "firearms", 6.0)
		Wear.tell(s, "Repaired: it fires again")
	Wear.timed(s, REPAIR_S, "Repairing the gun", done, instant)


static func server_sharpen(s: Soldier, slot: StringName, instant := false) -> void:
	var rev := s.inventory.slot_revision(slot)
	var done := func() -> void:
		if s.inventory.slot_revision(slot) != rev or not Wear.spend_tool(s.inventory, WHETSTONE):
			return
		var st := Wear.slot_state_rw(s.inventory, slot)
		Wear.set_cond(st, Wear.cond(st) + SHARPEN_ADD)
		s.inventory._commit()
		Wear.tell(s, "Sharp again: %d%%" % roundi(Wear.cond(st)))
	Wear.timed(s, SHARPEN_S, "Sharpening", done, instant)


static func server_tape(s: Soldier, slot: StringName, instant := false) -> void:
	var rev := s.inventory.slot_revision(slot)
	var done := func() -> void:
		if s.inventory.slot_revision(slot) != rev or not s.inventory.remove_one(DUCT_TAPE):
			return
		var st := Wear.slot_state_rw(s.inventory, slot)
		Wear.set_cond(st, Wear.cond(st) + TAPE_ADD)
		s.inventory._commit()
		Wear.tell(s, "Taped up: %d%%" % roundi(Wear.cond(st)))
	Wear.timed(s, TAPE_S, "Taping it up", done, instant)


# --- Melee --------------------------------------------------------------------------------------------

## The damage multiplier of a melee weapon at condition `c` (a blade dulls; blunt barely).
static func melee_mult_of(item: ItemData, c: float) -> float:
	if MeleeWeapons.is_blade(item):
		if c >= DULL_FULL:
			return 1.0
		if c <= DULL_LOW:
			return DULL_MULT
		return lerpf(DULL_MULT, 1.0, (c - DULL_LOW) / (DULL_FULL - DULL_LOW))
	return lerpf(BLUNT_WORN_MULT, 1.0, clampf(c / DULL_LOW, 0.0, 1.0))


## Host (MeleeWeapons.server_action): a swing's damage multiplier for what `s` holds, and the
## swing's wear on it.
static func server_swing(s: Soldier) -> float:
	var weapon := s.active_weapon()
	if not Wear.enabled() or not MeleeWeapons.is_melee(weapon):
		return 1.0
	var st := Wear.slot_state_rw(s.inventory, s.active_slot)
	var mult := melee_mult_of(weapon, Wear.cond(st))
	Wear.set_cond(st, Wear.cond(st) - SWING_WEAR)
	return mult


## Trees: the felling-time multiplier of the tool `id` (axe, hatchet) `s` carries: 1 as new, up to
## AXE_SLOW worn out.
static func tool_mult(s: Soldier, id: String) -> float:
	if not Wear.enabled():
		return 1.0
	var st := Wear.carried_state_rw(s.inventory, StringName(id))
	var c := Wear.cond(st)
	if c >= DULL_FULL:
		return 1.0
	return lerpf(AXE_SLOW, 1.0, c / DULL_FULL)


## Trees: `seconds` of felling wear on the tool `id`.
static func on_chop(s: Soldier, id: String, seconds: float) -> void:
	if not Wear.enabled():
		return
	var st := Wear.carried_state_rw(s.inventory, StringName(id))
	Wear.set_cond(st, Wear.cond(st) - CHOP_WEAR_S * seconds)


## Inventory words: "jammed", "broken", "wet", "worn 42%", "dull".
static func words(item: ItemData, state: Dictionary) -> String:
	var out := PackedStringArray()
	if jammed(state):
		out.append("jammed")
	var c := Wear.cond(state)
	if is_broken(state):
		out.append("broken")
	elif MeleeWeapons.is_blade(item) and c < DULL_FULL:
		out.append("dull %d%%" % roundi(c))
	elif c < 99.5:
		out.append("%d%%" % roundi(c))
	if bool(state.get("wet", false)):
		out.append("wet")
	if state.has("zeroed"):
		out.append("zeroed")
	if state.has(Suppressors.CAN_KEY):
		out.append("can %d%%" % roundi(can_cond(state)))
	return ", ".join(out)
