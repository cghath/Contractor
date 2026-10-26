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
## Loose rounds loaded into a magazine (Inventory.load_rounds) mix in by count: the magazine keeps
## the mean (mix_into), and the hand-loaded share (HL) the same way; a gun's tube (Shotguns) keeps
## its shells' mean as IN_GUN. Shotgun shells (tag "shell") soak: a wet shell (WET) fires as at
## most WET_SHELL_CAP (eff). Hand-loads under HOT_BELOW are hot (hot: a worn-out gun may blow on
## them, WeaponCondition.HOT_GUN_AT).

const IN_GUN := "ammo_cond"
const MISFIRE_FROM := 85.0
const MISFIRE_MAX := 0.25
const RELOADED := 90.0          # x0.9: hand-loaded rounds
const DRY_RANGE := Vector2(85.0, 100.0)
const WET_RANGE := Vector2(25.0, 75.0)
const RAIN_H := 3.0             # condition lost a world hour lying in the rain
const WADE_H := 6.0             # carried through water, a world hour
const SEE_LEVEL := 2
## The hand-loaded share of a stack's rounds (1.0 on a hand-loaded loose stack; a mean in a
## magazine); loaded, IN_GUN_HL on the gun.
const HL := "handload"
const IN_GUN_HL := "ammo_hl"
const HOT_BELOW := 40.0
## A soaked shotgun shell (its hull swells): fires as at most WET_SHELL_CAP.
const WET := "wet"
const WET_SHELL_CAP := 30.0


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
	return {Wear.KEY: RELOADED, HL: 1.0}


static func is_shell(item: ItemData) -> bool:
	return item != null and item.type == "ammo" and item.tags.has("shell")


## The condition a stack's rounds fire at: its condition, a wet shell's at most WET_SHELL_CAP.
static func eff(state: Dictionary) -> float:
	var c := Wear.cond(state)
	return minf(c, WET_SHELL_CAP) if bool(state.get(WET, false)) else c


static func hl_of(state: Dictionary) -> float:
	return clampf(float(state.get(HL, 0.0)), 0.0, 1.0)


## Hot hand-loads in the gun with `gun_state`: some hand-loaded, the rounds under HOT_BELOW.
static func hot(gun_state: Dictionary) -> bool:
	return float(gun_state.get(IN_GUN_HL, 0.0)) > 0.0 and float(gun_state.get(IN_GUN, 100.0)) < HOT_BELOW


## `state` held `n_old` rounds at `c_old` with `hl_old` hand-loaded; `n_new` more come in summing
## `c_sum` condition and `hl_sum` hand-loads: the mean by count kept under `ckey` and `hkey`
## (erased when as new / none, so clean magazines still stack).
static func mix_into(state: Dictionary, n_old: int, c_old: float, hl_old: float, n_new: int, c_sum: float, hl_sum: float, ckey := Wear.KEY, hkey := HL) -> void:
	var a := maxi(0, n_old)
	var n := a + maxi(0, n_new)
	if n <= 0:
		return
	var c := (c_old * a + c_sum) / float(n)
	var h := (hl_old * a + hl_sum) / float(n)
	if c < 99.5:
		state[ckey] = snappedf(clampf(c, 0.0, 100.0), 0.01)
	else:
		state.erase(ckey)
	if h > 0.001:
		state[hkey] = snappedf(clampf(h, 0.0, 1.0), 0.001)
	else:
		state.erase(hkey)


## Host (Inventory.load_rounds): up to `n` loose `id` taken out of `inv`'s containers, last entries
## first (any state: a corroded box too), without a commit. Vector3(taken, condition sum, hand-load sum).
static func take_loose(inv: Inventory, id: StringName, n: int) -> Vector3:
	var left := n
	var c_sum := 0.0
	var hl_sum := 0.0
	var order := inv.search_containers()
	for ci in range(order.size() - 1, -1, -1):
		var list: Array = inv.containers[order[ci]]
		for i in range(list.size() - 1, -1, -1):
			if left <= 0:
				break
			var e: Dictionary = list[i]
			if StringName(e.id) != id:
				continue
			var st: Dictionary = e.get("state", {})
			var k := mini(left, int(e.count))
			c_sum += eff(st) * k
			hl_sum += hl_of(st) * k
			e["count"] = int(e.count) - k
			left -= k
			if int(e.count) <= 0:
				list.remove_at(i)
	return Vector3(n - left, c_sum, hl_sum)


## The state of the first stowed `id` (the one Inventory.remove_one takes), {} for none.
static func first_state(inv: Inventory, id: StringName) -> Dictionary:
	for c: StringName in inv.search_containers():
		for e: Dictionary in inv.containers[c]:
			if StringName(e.id) == id:
				return e.get("state", {})
	return {}


## Host (Shotguns' loading): `n_new` shells summing `c_sum` / `hl_sum` went into the gun in `slot`
## (now holding `n_now`): the tube's mean (IN_GUN, IN_GUN_HL). Commits.
static func tube_add(inv: Inventory, slot: StringName, n_now: int, n_new: int, c_sum: float, hl_sum: float) -> void:
	if n_new <= 0 or StringName(inv.slots.get(slot, &"")) == &"":
		return
	var st := Wear.slot_state_rw(inv, slot)
	mix_into(st, n_now - n_new, float(st.get(IN_GUN, 100.0)), float(st.get(IN_GUN_HL, 0.0)), n_new, c_sum, hl_sum, IN_GUN, IN_GUN_HL)
	inv._commit()


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
		if is_shell(ItemDB.get_item(wi.item_id)):
			st[WET] = true  # (a shell's hull soaks)
		wi.state = st
		if GameState.dropped.has(wi.uid):
			var rec: Dictionary = GameState.dropped[wi.uid]
			rec["state"] = st


## Host: `world_h` hours of the ammo `inv` carries through water. True if anything changed.
static func soak_carried(inv: Inventory, world_h: float) -> bool:
	var changed := false
	for c: StringName in inv.search_containers():
		for e: Dictionary in inv.containers.get(c, []):
			var ammo := ItemDB.get_item(StringName(e.id))
			if not is_ammo(ammo):
				continue
			var st: Dictionary = e.get("state", {})
			Wear.set_cond(st, Wear.cond(st) - WADE_H * world_h)
			if is_shell(ammo):
				st[WET] = true
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
	var was_hl := float(gun_state.get(IN_GUN_HL, 0.0))
	if was_hl > 0.001:
		out_state[HL] = was_hl
	var now := eff(in_state)
	if now < 99.5:
		gun_state[IN_GUN] = now
	else:
		gun_state.erase(IN_GUN)
	var now_hl := hl_of(in_state)
	if now_hl > 0.001:
		gun_state[IN_GUN_HL] = now_hl
	else:
		gun_state.erase(IN_GUN_HL)


## The inventory's words for an ammo stack: its condition to a man of firearms SEE_LEVEL and up
## ("clean", "tarnished", "corroded", "badly corroded"); below, nothing.
static func words(state: Dictionary, firearms: int) -> String:
	if firearms < SEE_LEVEL or not (state.has(Wear.KEY) or state.has(WET) or state.has(HL)):
		return ""
	var c := Wear.cond(state)
	var w := "badly corroded"
	if c >= MISFIRE_FROM:
		w = "clean"
	elif c >= 60.0:
		w = "tarnished"
	elif c >= 35.0:
		w = "corroded"
	if state.has(Wear.KEY) and (state.has("rounds") or state.has(Shotguns.LIST_KEY)):
		w += " (%d%%)" % roundi(c)  # a magazine's mean: a corroded box mixed in shows
	if bool(state.get(WET, false)):
		w += ", wet"
	var h := hl_of(state)
	if h > 0.001:
		w += ", hand-loaded" if h >= 0.999 else ", %d%% hand-loads" % roundi(h * 100.0)
	return w
