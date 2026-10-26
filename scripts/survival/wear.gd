class_name Wear
extends RefCounted
## Condition and wear in Contractor: Fallen (docs/survival_wear.md; calls 120-123): the shared
## part. Guns and melee (WeaponCondition), ammunition (AmmoCondition), clothes (ClothingWear) and
## vehicles (VehicleWear) each keep a `condition` 0-100 in the item's state (or the vehicle's
## meta); absent reads as 100, so items from before (and every item outside survival) are as new.
## This file: whether wear runs (a survival world on the host; tests force it), the host's tick
## (Survival.server_tick_survivors), the timed jobs (cleaning, sharpening, sewing, patching: the
## hands busy like Crafting), the tool items used from the inventory (Consumables routes a
## "consume": {"wear": ...} item here) and the small state helpers. Every number is Proposed.

const KEY := "condition"
## Real seconds between wear ticks (the clothes' day, wet guns, ammo in the rain).
const TICK_S := 10.0
## A tool item's uses: its state's "uses", from its stats' "uses_max" when new.
const USES := "uses"

## Tests (and the host's other modes): wear runs outside a survival world.
static var force := false
## Tests: every wear roll returns this (0..1); -1 rolls for real.
static var force_roll := -1.0
## Tests: the tick holds off (the test steps wear itself).
static var tick_off := false
static var _acc := 0.0


static func enabled() -> bool:
	return force or Survival.running


static func roll() -> float:
	return force_roll if force_roll >= 0.0 else randf()


static func cond(state: Dictionary) -> float:
	return clampf(float(state.get(KEY, 100.0)), 0.0, 100.0)


static func set_cond(state: Dictionary, value: float) -> void:
	state[KEY] = clampf(value, 0.0, 100.0)


## The state of what `inv` has in `slot`, kept in the inventory (written in place).
static func slot_state_rw(inv: Inventory, slot: StringName) -> Dictionary:
	if not inv.slot_state.get(slot, null) is Dictionary:
		inv.slot_state[slot] = {}
	return inv.slot_state[slot]


## The state (written in place) of the first `id` `inv` carries: a slot first, then the
## containers and pouches, then what's on the carrier's attach points ({} if it has none).
## Every Inventory._commit rebuilds the states: fetch it again after one.
static func carried_state_rw(inv: Inventory, id: StringName) -> Dictionary:
	for slot: StringName in Inventory.all_slots():
		if StringName(inv.slots.get(slot, &"")) == id:
			return slot_state_rw(inv, slot)
	for c: StringName in inv.search_containers():
		for e: Dictionary in inv.containers.get(c, []):
			if StringName(e.id) == id and int(e.get("count", 1)) == 1:
				if not e.get("state", null) is Dictionary:
					e["state"] = {}
				return e.state
	for slot: StringName in Inventory.ATTACH_SLOTS:
		var molle: Dictionary = (inv.slot_state.get(slot, {}) as Dictionary).get("molle", {})
		for point: Variant in molle:
			var att: Dictionary = molle[point]
			if StringName(String(att.get("id", ""))) == id:
				if not att.get("state", null) is Dictionary:
					att["state"] = {}
				return att.state
	return {}


## World hours in `seconds` real seconds (Survival's day).
static func hours_in(seconds: float) -> float:
	return seconds / (Survival.DAY_MIN * 60.0) * 24.0


## Host: the hands busy `secs` with `text`, then `done` (if he's still up). `instant`: now (tests).
static func timed(s: Soldier, secs: float, text: String, done: Callable, instant := false) -> void:
	if instant or secs <= 0.0 or not s.is_inside_tree():
		done.call()
		return
	s.server_busy(secs, text)
	s.get_tree().create_timer(secs, false).timeout.connect(func() -> void:
		if is_instance_valid(s) and s.vitals.is_up():
			done.call())


static func tell(s: Soldier, text: String) -> void:
	if s != null and is_instance_valid(s):
		Survival._tell(s, text)


# --- The tick ----------------------------------------------------------------------------------

## Host (Survival.server_tick_survivors): `dt` real seconds of wear on the players in `level`
## (their guns in the wet, their clothes, sore feet, ammo when they swim) and the ammo lying in
## the rain.
static func server_tick(level: Node, players: Array, dt: float) -> void:
	if not enabled() or tick_off:
		return
	_acc += dt
	if _acc < TICK_S:
		return
	var secs := _acc
	_acc = 0.0
	var h := hours_in(secs) * Survival.option_mult("needs")
	for s: Soldier in players:
		if s.vitals.is_up():
			step_soldier(s, h)
	if level and level.get("items") is Node:
		AmmoCondition.step_ground(level, h)


## `world_h` world hours on `s`: his guns soak and rust, his clothes wear, his feet, his ammo.
static func step_soldier(s: Soldier, world_h: float) -> void:
	var n: Dictionary = s.get_meta(&"needs", {}) as Dictionary
	var wading := s.movement != null and float(s.movement.wet) > Needs.WADE_WET_M
	var soaked := float(n.get("wet", 0.0)) > 0.4 or wading
	var raining := _raining(s)
	WeaponCondition.step_carried(s, world_h, soaked or raining)
	var changed := ClothingWear.step(s, n, world_h, {"rain": raining, "wading": wading, "moving": s.velocity.length() > 0.5, "asleep": String(n.get("asleep", "")) != ""})
	if wading:
		changed = AmmoCondition.soak_carried(s.inventory, world_h) or changed
	if changed:
		s.inventory._commit()


static func _raining(s: Soldier) -> bool:
	var dn := DayNight.current()
	if dn == null or not s.is_inside_tree():
		return false
	return int(dn.row().get("rain", 0)) > 0 and not Throwables.indoors(s.get_world_3d(), s.global_position)


# --- Tool items (Consumables: "consume": {"wear": what}) ----------------------------------------

static func is_tool(item: ItemData) -> bool:
	return item != null and (item.stats.get("consume", {}) as Dictionary).has("wear")


static func tool_kind(item: ItemData) -> String:
	return String((item.stats.get("consume", {}) as Dictionary).get("wear", ""))


## Why `s` can't use the wear tool `item` now, or "".
static func tool_problem(s: Soldier, item: ItemData) -> String:
	if not s.vitals.is_up():
		return "Not now"
	if Soldier._now() < s._server_busy_until - 0.1:
		return "Busy"
	match tool_kind(item):
		"clean", "oil":
			var slot := WeaponCondition.gun_to_clean(s)
			if slot == &"":
				return "No gun to clean"
			if WeaponCondition.is_broken(s.inventory.state_of(slot)):
				return "It's broken: it needs a gun repair kit"
			return ""
		"repair_gun":
			if WeaponCondition.broken_gun(s) == &"":
				return "No broken gun"
			return "" if Rpg.gate(s, "firearms", WeaponCondition.REPAIR_LEVEL) else "Needs firearms %d" % WeaponCondition.REPAIR_LEVEL
		"sharpen":
			return "" if WeaponCondition.blade_to_sharpen(s) != &"" else "No blade to sharpen"
		"tape":
			return "" if WeaponCondition.blunt_to_tape(s) != &"" else "Nothing to tape up"
		"sew":
			return "" if ClothingWear.most_worn(s.inventory) != &"" else "Your clothes need no mending"
		"patch":
			return "" if VehicleWear.flat_near(s) != null else "No flat tyre here"
	return "You can't use that"


## Host: `s` uses the wear tool at `container`/`index` (Consumables.server_use). "" or why not.
static func server_use_tool(s: Soldier, container: StringName, index: int, instant := false) -> String:
	var list: Array = s.inventory.containers.get(container, [])
	if index < 0 or index >= list.size():
		return "Can't do that"
	var item := ItemDB.get_item(StringName(list[index].id))
	var why := tool_problem(s, item)
	if why != "":
		return why
	match tool_kind(item):
		"clean":
			WeaponCondition.server_clean(s, WeaponCondition.gun_to_clean(s), instant)
		"oil":
			WeaponCondition.server_oil(s, WeaponCondition.gun_to_clean(s), instant)
		"repair_gun":
			WeaponCondition.server_repair(s, WeaponCondition.broken_gun(s), instant)
		"sharpen":
			WeaponCondition.server_sharpen(s, WeaponCondition.blade_to_sharpen(s), instant)
		"tape":
			WeaponCondition.server_tape(s, WeaponCondition.blunt_to_tape(s), instant)
		"sew":
			ClothingWear.server_sew(s, ClothingWear.most_worn(s.inventory), instant)
		"patch":
			VehicleWear.server_patch(s, VehicleWear.flat_near(s), instant)
	return ""


## Host: one use of the tool `id` spent from `inv` (its "uses" down by one; the last one goes).
## False if he no longer has it.
static func spend_tool(inv: Inventory, id: StringName) -> bool:
	var item := ItemDB.get_item(id)
	for c: StringName in inv.search_containers():
		var list: Array = inv.containers.get(c, [])
		for i in list.size():
			var e: Dictionary = list[i]
			if StringName(e.id) != id:
				continue
			var max_uses := int(item.stats.get("uses_max", 1)) if item else 1
			var st: Dictionary = e.get("state", {})
			var left := int(st.get(USES, max_uses)) - 1
			if left <= 0:
				inv.remove_entry(c, i)
				return true
			if int(e.get("count", 1)) > 1:  # one off the stack keeps the rest whole
				inv.remove_entry(c, i)
				inv.insert_entry(c, {"id": String(id), "count": 1, "state": {USES: left}})
			else:
				e["state"] = {USES: left}
				inv._commit()
			return true
	return false


## Words for the inventory's readout of `item` with `state` ("worn 42%", "jammed", "dull",
## "corroded"); "" for nothing to say. `firearms`: the viewer's level (ammo's condition shows
## from AmmoCondition.SEE_LEVEL).
static func tag(item: ItemData, state: Dictionary, firearms := -1) -> String:
	if item == null or state.is_empty():
		return ""
	if item.type == "ammo":
		return AmmoCondition.words(state, firearms if firearms >= 0 else _my_firearms())
	if not state.has(KEY) and not state.has("jammed"):
		return ""
	var c := cond(state)
	if item.type == "weapon":
		return WeaponCondition.words(item, state)
	if Clothing.is_clothing(item):
		return ClothingWear.words(c)
	return "%d%%" % roundi(c) if c < 99.5 else ""


static func _my_firearms() -> int:
	var r := Rpg.net()
	if r == null:
		return 0
	var levels: Dictionary = (r.my as Dictionary).get("levels", {})
	return int(levels.get("firearms", 0))
