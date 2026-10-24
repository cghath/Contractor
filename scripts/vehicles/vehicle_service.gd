class_name VehicleService
extends RefCounted
## Field service on a vehicle (wave 5, host side): repairs with the vehicle parts in
## items.json, refuelling from jerrycans, and salvaging a wreck for parts. Each is a timed job
## the player stands by for (Vehicle.server_start_job); this file says what each part fixes and
## does it at the end. A part says what it repairs in its stats: "repairs" (zones), "repair_s"
## (seconds), "repair_to" (the zone's health after, at least) or "repair_add" (health added),
## "kinds" (wheeled or tracked only), "battery" (fits a new battery). Proposed numbers.
##
## Combined arms A8 (cg_brief queue item 2.6): a model with modules is repaired module by module
## (VehicleLogistics: 2.2.2's field column, data/vehicle_logistics.json "repair"), and the service
## point offers those jobs. The zone repairs here stay for the models without modules (technicals)
## and for callers that name a zone; on a model with modules they keep to the same field limits
## (a destroyed engine, the hull or a breech is the motor pool's).

const JERRYCAN := &"jerrycan"
## A wreck salvaged yields these, once (Proposed): a set of engine parts and some salvage.
const SALVAGE_ENGINE := &"engine_parts"
const SALVAGE_SCRAP := &"electronics_salvage"
const SALVAGE_SCRAP_COUNT := 2

const ZONE_NAMES := {&"hull": "hull", &"engine": "engine", &"wheels": "wheels", &"crew": "crew compartment",
	&"cargo": "cargo bed", &"fuel": "fuel tank", &"rotor": "rotor", &"battery": "battery"}


## A zone in words ("wheels", "tracks" on a tracked vehicle).
static func zone_name(zone: StringName, kind: String) -> String:
	if zone == Vehicle.ZONE_WHEELS and kind == Vehicle.TRACKED:
		return "tracks"
	return String(ZONE_NAMES.get(zone, String(zone)))


## A module in words (A8: "left track", "driver's periscope"; 2.9.3's zone_name for modules).
static func module_name(module_id: String) -> String:
	return VehicleLogistics.module_name(module_id)


## Whether `actor` has `item` (stowed, or in their hands).
static func has_part(actor: Soldier, item: StringName) -> bool:
	return actor.inventory.hands == item or actor.inventory.count_of(item) > 0


## The parts `actor` carries that can fix `zone` on `vehicle` now (ids), best first.
static func parts_for(vehicle: Vehicle, actor: Soldier, zone: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in [&"engine_parts", &"track_links", &"spare_wheel", &"vehicle_battery", &"repair_kit"]:
		if has_part(actor, id) and repair_problem(vehicle, actor, zone, id) == "":
			out.append(id)
	return out


## "" if `item` can repair `zone` on `vehicle` for `actor` now, else why not.
static func repair_problem(vehicle: Vehicle, actor: Soldier, zone: StringName, item: StringName) -> String:
	if vehicle.wrecked:
		return "It's a wreck"
	if vehicle.is_burning():
		return "It's on fire"
	var part := ItemDB.get_item(item)
	if part == null or not part.stats.has("repair_s"):
		return "That doesn't fix vehicles"
	if not has_part(actor, item):
		return "You have no %s" % part.name
	var kinds: Array = part.stats.get("kinds", [])
	if not kinds.is_empty() and not vehicle.kind in kinds:
		return "%s doesn't fit a %s vehicle" % [part.name, vehicle.kind]
	if zone == &"battery":
		if not part.stats.get("battery", false):
			return "That isn't a battery"
		return "" if not vehicle.battery_ok else "The battery is fine"
	if not String(zone) in (part.stats.get("repairs", []) as Array):
		return "%s can't fix the %s" % [part.name, zone_name(zone, vehicle.kind)]
	if vehicle.modules and vehicle.modules.authored:
		var limit := field_limit(vehicle, zone)
		if limit != "":
			return limit
	var health := vehicle.zone_health(zone)
	var to := float(part.stats.get("repair_to", 0.0))
	var add := float(part.stats.get("repair_add", 0.0))
	if health >= 0.999 or (add <= 0.0 and health >= to - 0.001):
		return "The %s needs no more than that" % zone_name(zone, vehicle.kind)
	return ""


## A8: "" when some module under `zone` of a model with modules is one a field repair may fix in
## the state it's in (VehicleLogistics.repair_rules), else why only the motor pool can.
static func field_limit(vehicle: Vehicle, zone: StringName) -> String:
	var mods := vehicle.modules
	var needs := 0
	for m: Dictionary in mods.mods:
		var mine := String(m.kind) == "structure" if zone == Vehicle.ZONE_HULL else (StringName(m.zone) == zone and float(m.hp) > 0.0)
		if not mine or mods.health[int(m.i)] >= 0.999:
			continue
		needs += 1
		var st := VehicleModules.state_of(mods.health[int(m.i)])
		if st == VehicleModules.WORKING:
			return ""
		for r: Dictionary in VehicleLogistics.repair_rules(String(m.kind)):
			if st in (r.states as Array):
				return ""
	return "" if needs == 0 else "Only the motor pool fixes the %s now" % zone_name(zone, vehicle.kind)


## Litres in the jerrycans `actor` carries.
static func jerrycan_fuel(actor: Soldier) -> float:
	var total := 0.0
	var can := ItemDB.get_item(JERRYCAN)
	if can == null:
		return 0.0
	for c: StringName in actor.inventory.search_containers():
		for entry: Dictionary in actor.inventory.containers[c]:
			if entry.id == JERRYCAN:
				total += float(entry.get("state", {}).get("fuel_l", can.stats.get("fuel_l", 20.0))) * int(entry.count)
	return total


## Host: a finished job. Returns what to tell the player.
static func finish(vehicle: Vehicle, actor: Soldier, action: String, zone: StringName, item: StringName) -> String:
	match action:
		"repair":
			var why := repair_problem(vehicle, actor, zone, item)
			if why != "":
				return why
			var part := ItemDB.get_item(item)
			if not _use_part(actor, item):
				return "You have no %s" % part.name
			if zone == &"battery":
				vehicle.server_set_battery(true)
				return "New battery fitted"
			vehicle.server_repair(zone, float(part.stats.get("repair_to", 0.0)), float(part.stats.get("repair_add", 0.0)))
			return "%s repaired (%d%%)" % [zone_name(zone, vehicle.kind).capitalize(), roundi(vehicle.zone_health(zone) * 100.0)]
		"refuel":
			return refuel_from_cans(vehicle, actor)
		"salvage":
			if not vehicle.wrecked or vehicle.salvaged:
				return "Nothing left to salvage"
			vehicle.server_set_salvaged()
			var lvl := vehicle.level()
			var at := vehicle.exit_spot(0) + Vector3.UP * 0.3
			if lvl:
				lvl.server_spawn_dropped(SALVAGE_ENGINE, 1, at)
				lvl.server_spawn_dropped(SALVAGE_SCRAP, SALVAGE_SCRAP_COUNT, at + Vector3(0.4, 0, 0))
			return "Salvaged parts from the %s" % vehicle.display_name()
	return ""


## Host: empties `actor`'s jerrycans into the tank until it's full. Returns what to tell them.
static func refuel_from_cans(vehicle: Vehicle, actor: Soldier) -> String:
	var can := ItemDB.get_item(JERRYCAN)
	var full := float(can.stats.get("fuel_l", 20.0)) if can else 20.0
	var poured := 0.0
	var inv := actor.inventory
	var done := false
	while not done:
		done = true
		for c: StringName in inv.search_containers():
			var list: Array = inv.containers[c]
			for i in list.size():
				var entry: Dictionary = list[i]
				var litres := float(entry.get("state", {}).get("fuel_l", full))
				if entry.id != JERRYCAN or litres <= 0.0:
					continue
				var taken := vehicle.server_refuel(litres)
				if taken <= 0.0:
					return "Refuelled %.0f L: the tank is full" % poured if poured > 0.0 else "The tank is full"
				poured += taken
				inv.remove_entry(c, i, 1)
				inv.take(JERRYCAN, 1, {"fuel_l": snappedf(litres - taken, 0.1)})
				done = false
				break
			if not done:
				break
	return "Refuelled %.0f L (%.0f L in the tank)" % [poured, vehicle.fuel] if poured > 0.0 else "No fuel in your jerrycans"


static func _use_part(actor: Soldier, item: StringName) -> bool:
	if actor.inventory.hands == item:
		actor.inventory.release_hands()
		return true
	return actor.inventory.remove_one(item)
