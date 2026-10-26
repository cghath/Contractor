class_name ClothingWear
extends RefCounted
## Clothing wear and repair (call 122; docs/survival_wear.md): every worn piece keeps a
## `condition` 0-100 in its slot state (Wear.KEY; absent = 100). Wearing it costs DAY_WEAR a world
## day (divided by its stats' "durability", 1 as standard), more in the rain (RAIN_X: the outer
## layers, head and legs) and wading (WADE_X: legs and feet), boots more walking (WALK_X), little
## asleep; a blow that lands on a covered part tears the outermost layer there (TEAR). Torn
## clothes keep less of their warmth and shed less rain (factor, read by Clothing.layers). Boots
## worn out (or none) on the move make sore feet (the body's "sore_feet" 0..1, stamina down by
## SORE_STAMINA at worst: Needs.stamina_mult reads feet_stamina) that ease off resting or in sound
## boots. A needle and thread mends the most worn piece (SEW_S, +SEW_ADD). Every number is Proposed.

const DAY_WEAR := 2.0
const RAIN_X := 1.5
const WADE_X := 2.0
const WALK_X := 1.5
const ASLEEP_X := 0.2
const TEAR := 6.0
const TORN_AT := 60.0          # from here down a piece loses warmth and wet_resist
const TORN_KEEP := 0.4         # what's left of them at 0
const BOOTS_SORE_AT := 20.0
const SORE_H := 0.15           # sore feet building a world hour on the move in bad boots
const SORE_EASE_H := 0.1       # easing an hour resting or in sound boots
const SORE_STAMINA := 0.25
const SEW_S := 15.0
const SEW_ADD := 35.0
const NEEDLE := &"needle_thread"

const RAIN_SLOTS: Array[StringName] = [&"head", &"torso_outer", &"torso_mid", &"legs"]
const WADE_SLOTS: Array[StringName] = [&"legs", &"feet"]


## Warmth and wet_resist kept at condition `c` (1 down to TORN_KEEP).
static func factor(c: float) -> float:
	if c >= TORN_AT:
		return 1.0
	return lerpf(TORN_KEEP, 1.0, clampf(c / TORN_AT, 0.0, 1.0))


static func factor_of(state: Dictionary) -> float:
	return factor(Wear.cond(state))


## The wear a world day of the piece in `slot` with `durability` takes in `ctx` ("rain", "wading",
## "moving", "asleep").
static func day_wear(slot: StringName, durability: float, ctx: Dictionary) -> float:
	var x := 1.0
	if bool(ctx.get("asleep", false)):
		x = ASLEEP_X
	else:
		if bool(ctx.get("rain", false)) and slot in RAIN_SLOTS:
			x *= RAIN_X
		if bool(ctx.get("wading", false)) and slot in WADE_SLOTS:
			x *= WADE_X
		if slot == &"feet" and bool(ctx.get("moving", false)):
			x *= WALK_X
	return DAY_WEAR * x / maxf(0.2, durability)


## Host: `world_h` world hours of wear on what `s` wears and his feet (`n`: his body). True if a
## state changed (the caller commits).
static func step(s: Soldier, n: Dictionary, world_h: float, ctx: Dictionary) -> bool:
	if world_h <= 0.0:
		return false
	var inv := s.inventory
	var changed := false
	for w: Dictionary in Clothing.worn(inv):
		var it: ItemData = w.item
		var st := Wear.slot_state_rw(inv, w.slot)
		Wear.set_cond(st, Wear.cond(st) - day_wear(w.slot, float(it.stats.get("durability", 1.0)), ctx) * world_h / 24.0)
		changed = true
	step_feet(n, inv, world_h, bool(ctx.get("moving", false)) and not bool(ctx.get("asleep", false)))
	return changed


## The body's sore feet over `world_h` hours: building on the move in worn-out boots (or none),
## easing otherwise.
static func step_feet(n: Dictionary, inv: Inventory, world_h: float, moving: bool) -> void:
	var boots := StringName(inv.slots.get(&"feet", &""))
	var bad := boots == &"" or Wear.cond(inv.state_of(&"feet")) <= BOOTS_SORE_AT
	var sore := float(n.get("sore_feet", 0.0))
	if moving and bad:
		sore += SORE_H * world_h
	else:
		sore -= SORE_EASE_H * world_h
	sore = clampf(sore, 0.0, 1.0)
	if sore <= 0.0:
		n.erase("sore_feet")
	else:
		n["sore_feet"] = sore


## Needs.stamina_mult's share from sore feet (1 when fine).
static func feet_stamina(n: Dictionary) -> float:
	return 1.0 - SORE_STAMINA * clampf(float(n.get("sore_feet", 0.0)), 0.0, 1.0)


## Host (Melee._hit): a blow on `part` of `victim` tears the outermost worn layer covering it.
static func on_hit(victim: Soldier, part: StringName) -> void:
	if not Wear.enabled() or victim == null or victim.inventory == null:
		return
	var slot := cover_of(victim.inventory, part)
	if slot == &"":
		return
	var st := Wear.slot_state_rw(victim.inventory, slot)
	Wear.set_cond(st, Wear.cond(st) - TEAR)
	victim.inventory._commit()


## The outermost worn layer over body part `part`, or &"".
static func cover_of(inv: Inventory, part: StringName) -> StringName:
	var p := String(part)
	var order: Array[StringName] = []
	if p.contains("chest") or p.contains("abdomen") or p.contains("torso") or p.contains("pelvis") or p.contains("arm"):
		if p.contains("pelvis"):
			order.append(&"legs")
		for l: StringName in Clothing.TORSO_OUT_IN:
			order.append(l)
		if p.contains("forearm"):
			order.append(&"hands")
	elif p.contains("thigh") or p.contains("shin") or p.contains("leg"):
		order.append(&"legs")
	elif p.contains("foot"):
		order.append(&"feet")
	elif p.contains("face") or p.contains("neck"):
		order.append(&"face")
		order.append(&"head")
	elif p.contains("head"):
		order.append(&"head")
	for slot: StringName in order:
		if StringName(inv.slots.get(slot, &"")) != &"":
			return slot
	return &""


## The most worn piece `inv` wears under 99.5, or &"".
static func most_worn(inv: Inventory) -> StringName:
	var best := &""
	var best_c := 99.5
	for w: Dictionary in Clothing.worn(inv):
		var c := Wear.cond(inv.state_of(w.slot))
		if c < best_c:
			best = w.slot
			best_c = c
	return best


## Host: `s` mends the piece in `slot` with a needle and thread (a use of it): SEW_S, +SEW_ADD.
static func server_sew(s: Soldier, slot: StringName, instant := false) -> void:
	var rev := s.inventory.slot_revision(slot)
	var done := func() -> void:
		if s.inventory.slot_revision(slot) != rev or not Wear.spend_tool(s.inventory, NEEDLE):
			return
		var st := Wear.slot_state_rw(s.inventory, slot)
		Wear.set_cond(st, Wear.cond(st) + SEW_ADD)
		s.inventory._commit()
		Rpg.xp(s, "fieldcraft", 2.0)
		Wear.tell(s, "Mended: %d%%" % roundi(Wear.cond(st)))
	Wear.timed(s, SEW_S, "Mending", done, instant)


static func words(c: float) -> String:
	if c >= 99.5:
		return ""
	if c >= TORN_AT:
		return "worn %d%%" % roundi(c)
	if c > 0.0:
		return "torn %d%%" % roundi(c)
	return "in rags"
