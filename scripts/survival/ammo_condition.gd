class_name AmmoCondition
extends RefCounted
## Ammo condition (call 121; docs/survival_wear.md): a `condition` 0-100 on an ammo stack's state
## (a magazine's, beside its "rounds"; loose rounds' too; absent = 100, factory fresh). Loaded,
## the gun's state keeps the rounds' condition as IN_GUN (Inventory.reload carries it in and the
## old magazine takes it back out). A worse round misfires more (misfire_chance: a dud, a click
## and the clear action: WeaponCondition.server_dud). Found ammo rolls its condition by where it
## lay (roll: dry stores good, outdoors and wrecks bad; WorldCache seeds through weather_loot);
## ammo lying outdoors in the rain corrodes (step_ground), under a roof it keeps; carried, only
## swimming soaks it (soak_carried). Reloads from the RPG's reloading are RELOADED (x0.9). The
## firearms skill shows the condition (words, from SEE_LEVEL). Every number is Proposed.

const IN_GUN := "ammo_cond"
const MISFIRE_FROM := 85.0
const MISFIRE_MAX := 0.25
const RELOADED := 90.0          # x0.9: hand-loaded rounds
const DRY_RANGE := Vector2(85.0, 100.0)
const WET_RANGE := Vector2(25.0, 75.0)
const RAIN_H := 3.0             # condition lost a world hour lying in the rain
const WADE_H := 6.0             # carried through water, a world hour
const SEE_LEVEL := 2


static func misfire_chance(c: float) -> float:
	if c >= MISFIRE_FROM:
		return 0.0
	return MISFIRE_MAX * pow((MISFIRE_FROM - c) / MISFIRE_FROM, 1.5)


## A found stack's condition: `dry` (a roofed store, a home, an armoury) or not (outdoors, a wreck,
## a body in the open).
static func roll(dry: bool, rng: RandomNumberGenerator = null) -> float:
	var r := DRY_RANGE if dry else WET_RANGE
	var t := rng.randf() if rng else randf()
	return roundf(lerpf(r.x, r.y, t))


## The state a hand-loaded stack gets (the reloading bench's output_state).
static func reloaded_state() -> Dictionary:
	return {Wear.KEY: RELOADED}


static func is_ammo(item: ItemData) -> bool:
	return item != null and item.type == "ammo"


## Host (WorldCache.server_seed): ammo in `items` gets its found condition by where `at` is (under
## a roof: dry). Returns the list (entries copied).
static func weather_loot(items: Array, at: Node3D) -> Array:
	if not Wear.enabled():
		return items
	var dry := true
	if at != null and at.is_inside_tree():
		dry = Throwables.indoors(at.get_world_3d(), at.global_position)
	var out: Array = []
	for e: Dictionary in items:
		var item := ItemDB.get_item(StringName(String(e.get("id", ""))))
		if is_ammo(item) and not (e.get("state", {}) as Dictionary).has(Wear.KEY):
			var c := roll(dry)
			if c < 99.5:
				var e2 := e.duplicate(true)
				var st: Dictionary = (e2.get("state", {}) as Dictionary).duplicate(true)
				st[Wear.KEY] = c
				e2["state"] = st
				out.append(e2)
				continue
		out.append(e)
	return out


## Host: `world_h` hours of ammo lying in `level` (its WorldItems): outdoors in the rain it
## corrodes by RAIN_H an hour; under a roof (a built one too) it keeps.
static func step_ground(level: Node, world_h: float) -> void:
	var dn := DayNight.current()
	if dn == null or int(dn.row().get("rain", 0)) <= 0:
		return
	var items: Node = level.get("items")
	for node in items.get_children():
		var wi := node as WorldItem
		if wi == null or wi.is_queued_for_deletion() or not is_ammo(ItemDB.get_item(wi.item_id)):
			continue
		if Throwables.indoors(wi.get_world_3d(), wi.global_position):
			continue
		var st := wi.state.duplicate(true)
		Wear.set_cond(st, Wear.cond(st) - RAIN_H * world_h)
		wi.state = st
		if GameState.dropped.has(wi.uid):
			var rec: Dictionary = GameState.dropped[wi.uid]
			rec["state"] = st


## Host: `world_h` hours of the ammo `inv` carries through water. True if anything changed.
static func soak_carried(inv: Inventory, world_h: float) -> bool:
	var changed := false
	for c: StringName in inv.search_containers():
		for e: Dictionary in inv.containers.get(c, []):
			if not is_ammo(ItemDB.get_item(StringName(e.id))):
				continue
			var st: Dictionary = e.get("state", {})
			Wear.set_cond(st, Wear.cond(st) - WADE_H * world_h)
			e["state"] = st
			changed = true
	for slot: StringName in Inventory.WEAPON_SLOTS:
		if StringName(inv.slots.get(slot, &"")) != &"":
			var gs := Wear.slot_state_rw(inv, slot)
			if gs.has("rounds"):
				gs[IN_GUN] = clampf(float(gs.get(IN_GUN, 100.0)) - WADE_H * world_h, 0.0, 100.0)
				changed = true
	return changed


## Inventory.reload: the magazine's condition into the gun (`gun_state`), the gun's old rounds'
## condition onto the magazine coming out (`out_state`). Kept off states that are as new.
static func on_reload(gun_state: Dictionary, in_state: Dictionary, out_state: Dictionary) -> void:
	var was := float(gun_state.get(IN_GUN, 100.0))
	if was < 99.5:
		out_state[Wear.KEY] = was
	var now := Wear.cond(in_state)
	if now < 99.5:
		gun_state[IN_GUN] = now
	else:
		gun_state.erase(IN_GUN)


## The inventory's words for an ammo stack: its condition to a man of firearms SEE_LEVEL and up
## ("clean", "tarnished", "corroded", "badly corroded"); below, nothing.
static func words(state: Dictionary, firearms: int) -> String:
	if firearms < SEE_LEVEL or not state.has(Wear.KEY):
		return ""
	var c := Wear.cond(state)
	if c >= MISFIRE_FROM:
		return "clean"
	if c >= 60.0:
		return "tarnished"
	if c >= 35.0:
		return "corroded"
	return "badly corroded"
