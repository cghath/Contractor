class_name Consumables
extends RefCounted
## Things you use up from the inventory (items expansion, 2026-10-20; Captain: "we genuinely need
## more items"): type "consumable", whose stats' "consume" says what one use does.
##   {"drug": id, "doses": n}: n doses of a WoundModel.DRUGS id by mouth (Vitals.server_take_drug).
##     caffeine (energy drink, caffeine tablets): stamina comes back faster for a while;
##     ibuprofen, paracetamol: a little pain relief (far under morphine);
##     water, ration (bottled water, electrolytes, MRE, IRP, energy bar, canned meat): stamina
##     comes back a little faster. Outside survival food and water aren't tracked, so eating and
##     drinking only help; in survival they feed the metabolism (Survival.server_eat, Needs.eat:
##     an item's kcal, water_l, protein, carbs, fat, vitamins, raw and quality; items without
##     values fall back to S1's water and ration doses, Survival.server_feed).
##   {"battery": true} (AA, CR123A): a fresh battery for an NVG (Nvg.server_recharge).
## Right-click > Use in the inventory (InventoryScreen; Soldier "consume"): instant, one unit used.

const TYPE := "consumable"


static func is_consumable(item: ItemData) -> bool:
	return item != null and item.type == TYPE and item.stats.get("consume", {}) is Dictionary and not (item.stats.get("consume", {}) as Dictionary).is_empty()


## The verb on the Use button: "Drink", "Eat", "Take" or "Use".
static func verb(item: ItemData) -> String:
	if item.tags.has("drink"):
		return "Drink"
	if item.tags.has("food"):
		return "Eat"
	if item.tags.has("drug"):
		return "Take"
	return "Use"


## Why `soldier` can't use the entry at `container`/`index` now, or "".
static func use_problem(soldier: Soldier, container: StringName, index: int) -> String:
	var list: Array = soldier.inventory.containers.get(container, [])
	if index < 0 or index >= list.size():
		return "Can't do that"
	var item := ItemDB.get_item(StringName(list[index].id))
	if not is_consumable(item):
		return "You can't use that"
	if not soldier.vitals.is_up():
		return "Not now"
	var c: Dictionary = item.stats.consume
	if c.has("wear"):
		return Wear.tool_problem(soldier, item)  # a cleaning kit, whetstone, needle, tyre patch (survival wear)
	if bool(c.get("battery", false)):
		return "" if _nvg_needs_battery(soldier.inventory) else "No NVG needs a battery"
	if not WoundModel.DRUGS.has(StringName(String(c.get("drug", "")))):
		return "You can't use that"
	return ""


## Host only. `soldier` uses one of the entry at `container`/`index`. "" or why not; the
## message for the owner is `done_text`.
static func server_use(soldier: Soldier, container: StringName, index: int) -> String:
	var problem := use_problem(soldier, container, index)
	if problem != "":
		return problem
	var entry: Dictionary = soldier.inventory.containers[container][index]
	var item := ItemDB.get_item(StringName(entry.id))
	var c: Dictionary = item.stats.consume
	if c.has("wear"):
		return Wear.server_use_tool(soldier, container, index)  # a timed job; the tool's use spent at its end
	if bool(c.get("battery", false)):
		problem = Nvg.server_recharge(soldier.inventory)
	elif not soldier.vitals.server_take_drug(StringName(String(c.drug)), float(c.get("doses", 1.0))):
		problem = "You can't use that"
	else:
		# Survival: its food values (kcal, water_l, macros, vitamins; raw or dirty ones can make him
		# sick) into his body (Needs), else the old water and ration doses.
		Survival.server_eat(soldier, item, entry.get("state", {}), StringName(String(c.drug)), float(c.get("doses", 1.0)))
	if problem != "":
		return problem
	# Re-find the entry: a recharge moves an NVG entry, which can shift the indices.
	if not soldier.inventory.remove_one(item.id):
		push_error("Consumables: %s was used but not found to take away" % item.id)
	return ""


## What the owner is told after using `item`.
static func done_text(item: ItemData) -> String:
	if bool((item.stats.get("consume", {}) as Dictionary).get("battery", false)):
		return "Fresh battery in the NVG"
	return {"Drink": "Drank the %s", "Eat": "Ate the %s", "Take": "Took the %s"}.get(verb(item), "Used the %s") % item.name


static func _nvg_needs_battery(inv: Inventory) -> bool:
	var s := Nvg.mounted_state(inv)
	var m := Nvg.mounted(inv)
	if not s.is_empty() and Nvg.battery_of(m, s) < Nvg.capacity_h(m) - 0.0001:
		return true
	for c in inv.search_containers():
		for e: Dictionary in inv.containers.get(c, []):
			var it := ItemDB.get_item(StringName(e.id))
			if Nvg.is_nvg(it) and Nvg.battery_of(it, e.get("state", {})) < Nvg.capacity_h(it) - 0.0001:
				return true
	return false
