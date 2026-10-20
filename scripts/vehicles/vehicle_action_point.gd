class_name VehicleActionPoint
extends Node3D
## One of a vehicle's Left Ctrl action points (wave 5): a door, the cargo point, the service
## point (bonnet, engine deck), and one inside at each seat for whoever sits there. It is an
## interactable (InteractionMenu's OBJECT kind): the menu shows it like any other point, and
## its interaction_actions list what can be done there; picking one sends the host request
## (Vehicle.request_*), which checks it again.
##
## - Door: get in (as driver, gunner or passenger, by the free seats this door serves), load
##   the body you carry into a seat, pull a body (down or dead) out, check the vehicle.
## - Cargo: what's in the hold (take one), load something you carry or hold, refuel, check.
## - Service: repairs with the parts you carry, a new battery, refuel; on a wreck, salvage.
## - Seat (inside, only for its occupant): get out (unless the get-out key does it:
##   ControlOptions), move to another seat, check the vehicle.
## Rare entries carry a "group" (Check vehicle: InteractionMenu.MORE; "Pull out", "Repair") so
## the ring folds them into a submenu (InteractionMenu.grouped).

const DOOR := "door"
const CARGO := "cargo"
const SERVICE := "service"
const SEAT := "seat"
## Most entries a cargo submenu lists.
const MAX_ENTRIES := 14

var vehicle: Vehicle
var kind := DOOR
## The seats this door serves (a seat point: its own seat).
var seat_list: Array = []
var seat_index := -1


func _init(p_vehicle: Vehicle = null, p_kind := DOOR, p_at := Vector3.ZERO, p_seats: Array = [], p_seat := -1, p_name := "Point") -> void:
	vehicle = p_vehicle
	kind = p_kind
	position = p_at
	seat_list = p_seats.duplicate()
	seat_index = p_seat
	name = p_name


func _ready() -> void:
	add_to_group(InteractionMenu.INTERACTABLES)
	if kind == SEAT and vehicle and not vehicle.spec.is_empty():
		# Inside, just ahead of the seat's eye and a little low, where its occupant sees it.
		position = VehicleSpecs.vec(vehicle.spec.seats[seat_index].at) + Vector3(0, -0.25, -0.55)


func action_point() -> Vector3:
	return global_position


func interaction_actions(actor: Soldier) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if vehicle == null or not is_instance_valid(vehicle) or actor == null:
		return out
	var inside := vehicle.seat_of(actor)
	if kind == SEAT:
		if inside < 0 and vehicle.bay and vehicle.bay.inside(actor):
			return _walk_up_actions()  # standing in the bay (VehicleBay): sit down here
		if inside != seat_index:
			return out
		return _seat_actions(actor)
	if Vehicle.ride_of(actor) != null:
		return out  # from inside, the seat's own point has the actions
	match kind:
		DOOR:
			out = _door_actions(actor)
		CARGO:
			out = _cargo_actions(actor)
		SERVICE:
			out = _service_actions(actor)
	return out


func _entry(id: StringName, label: String, call: Callable, disabled := "") -> Dictionary:
	return {"id": id, "label": label, "disabled": disabled, "call": call, "target": self}


## Check vehicle: on every point, rarely needed, so it's last and shares the ring's MORE submenu
## with anything else rare there.
func _check() -> Dictionary:
	var entry := _entry(&"check_vehicle", "Check vehicle", func() -> void: _say(VehicleActionPoint.report(vehicle)))
	entry["group"] = InteractionMenu.MORE
	return entry


func _say(text: String) -> void:
	var me := _local_player()
	if me and me.player_input:
		me.player_input.flash(text)


func _local_player() -> Soldier:
	var lvl := vehicle.level()
	return lvl.players.get_node_or_null(str(multiplayer.get_unique_id())) as Soldier if lvl else null


## What a look over the vehicle tells you: damage by zone, fuel, fire, the hold.
static func report(v: Vehicle) -> String:
	var lines := PackedStringArray([v.display_name() + (" (wreck)" if v.wrecked else "")])
	if v.is_burning():
		lines.append("On fire")
	var parts: Array = [Vehicle.ZONE_HULL] if v.kind == Vehicle.STATIC else [Vehicle.ZONE_ENGINE, Vehicle.ZONE_WHEELS, Vehicle.ZONE_FUEL, Vehicle.ZONE_HULL]
	for z: StringName in parts:
		var h := v.zone_health(z)
		var state := "fine" if h >= 0.999 else ("wrecked" if h <= 0.0 else ("damaged (%d%%)" % roundi(h * 100.0)))
		lines.append("%s: %s" % [VehicleService.zone_name(z, v.kind).capitalize(), state])
	if v.kind != Vehicle.STATIC:
		if not (v.battery_ok if v.multiplayer.is_server() else bool(v.net_state.get("battery", true))):
			lines.append("Battery: dead")
		lines.append("Fuel: %d of %d L" % [roundi(v.fuel_litres()), roundi(float(v.spec.get("fuel_l", 0.0)))])
	var hold := v.cargo() as VehicleCargo
	if hold:
		lines.append("Cargo: %.0f of %.0f L, %.0f of %.0f kg" % [hold.used_litres(), hold.capacity_l, hold.total_mass(), hold.max_kg])
	return "\n".join(lines)


## A door's ring (Captain, P0164 queue 8: get in and the seat choices first, nothing you can't
## do): a Get in entry for each kind of seat this door serves that has one free (driver,
## gunner, then passenger), never a pilot's (aircraft are flown by AI); when none is free, one
## greyed Get in saying why (on fire, every seat taken, or only a pilot's seat here). Then Pull
## out for each body down or dead in a seat here (two or more share a "Pull out" submenu),
## then Check vehicle. Carrying a body, only Load casualty.
func _door_actions(actor: Soldier) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if vehicle.wrecked:
		var wreck_out: Array[Dictionary] = _tag_entries(actor)
		wreck_out.append(_check())
		return wreck_out
	var v := vehicle
	if actor.carry_mode != &"":
		var free := _first_free(Vehicle.PASSENGER)
		out.append(_entry(&"load_body", "Load casualty", func() -> void: v.request_load_body.rpc_id(1, free),
			"" if free >= 0 else "No free seat on this side"))
		return out
	for k: StringName in [Vehicle.DRIVER, Vehicle.GUNNER, Vehicle.PASSENGER]:
		var seat := _first_free(k)
		if seat < 0 or v.is_burning():
			continue
		var label := "Get in" if k == Vehicle.PASSENGER else "Get in as %s" % _kind_name(k)
		out.append(_entry(StringName("enter_%s" % k), label, func() -> void: v.request_enter.rpc_id(1, seat)))
	if out.is_empty():
		var why := "No free seat on this side"
		if v.is_burning():
			why = "It's on fire"
		elif seat_list.all(func(i: int) -> bool: return v.seat_kind(i) == Vehicle.PILOT):
			why = "Aircraft are flown by AI pilots"
		out.append(_entry(&"enter", "Get in", Callable(), why))
	if v.bay:
		out.append(_bay_entry())
	for i: int in seat_list:
		var s := v.occupant(i)
		if s and not s.vitals.is_up():
			var index := i
			var entry := _entry(&"pull_out", "Pull out %s" % s.display_name(), func() -> void: v.request_pull_out.rpc_id(1, index))
			entry["group"] = "Pull out"
			entry["group_label"] = s.display_name()
			out.append(entry)
	out.append_array(_tag_entries(actor))
	out.append(_check())
	return out


## Tag to sell / Tag for... on an abandoned or captured vehicle (feat/pallet-tagging: not the
## company's own, nobody aboard; PalletField).
func _tag_entries(actor: Soldier) -> Array[Dictionary]:
	var field := PalletField.of(vehicle)
	if field == null or vehicle.faction == &"player" or not vehicle.occupants().is_empty():
		return []
	return field.tag_entries(PalletField.vehicle_key(vehicle), self, actor)


func _cargo_actions(actor: Soldier) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var v := vehicle
	var hold := v.cargo() as VehicleCargo
	if hold == null:
		return [_check()]
	out.append(_entry(&"open_hold", "Open hold", func() -> void:
		if actor._hud:
			actor._hud.open_loot(v)))
	var take_items: Array[Dictionary] = []
	var entries := hold.entries()
	for i in mini(entries.size(), MAX_ENTRIES):
		var e: Dictionary = entries[i]
		var item := ItemDB.get_item(e.id)
		var index := i
		var id: StringName = e.id
		take_items.append(_entry(&"take_cargo", "%s%s%s" % [item.name, " x%d" % int(e.count) if int(e.count) > 1 else "", _state_text(item, e.get("state", {}))],
			func() -> void: v.request_cargo_take.rpc_id(1, index, id)))
	out.append({"id": &"cargo", "label": "Cargo (%.0f/%.0f L)" % [hold.used_litres(), hold.capacity_l], "disabled": "" if not take_items.is_empty() else "The hold is empty",
		"items": take_items, "target": self})
	if v.wrecked:
		return out
	var load_items: Array[Dictionary] = []
	if actor.inventory.hands != &"":
		var held := actor.inventory.hands
		load_items.append(_entry(&"load_held", "%s (in your hands)" % ItemDB.get_item(held).name, func() -> void: v.request_cargo_load.rpc_id(1, &"", -1, held)))
	for c: StringName in actor.inventory.search_containers():
		var list: Array = actor.inventory.containers[c]
		for i in list.size():
			if load_items.size() >= MAX_ENTRIES:
				break
			var e: Dictionary = list[i]
			var item := ItemDB.get_item(e.id)
			var container := c
			var index := i
			var id: StringName = e.id
			load_items.append(_entry(&"load_cargo", "%s%s" % [item.name, " x%d" % int(e.count) if int(e.count) > 1 else ""],
				func() -> void: v.request_cargo_load.rpc_id(1, container, index, id)))
	out.append({"id": &"load", "label": "Load", "disabled": "" if not load_items.is_empty() else "Nothing to load", "items": load_items, "target": self})
	if VehicleService.jerrycan_fuel(actor) > 0.0:
		out.append(_entry(&"refuel", "Refuel (jerrycan)", func() -> void: v.request_service.rpc_id(1, "refuel", &"", VehicleService.JERRYCAN)))
	out.append(_check())
	return out


func _service_actions(actor: Soldier) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var v := vehicle
	if v.wrecked:
		var salvaged := bool(v.salvaged if v.multiplayer.is_server() else v.net_state.get("salvaged", false))
		out.append(_entry(&"salvage", "Salvage parts", func() -> void: v.request_service.rpc_id(1, "salvage", &"", &""),
			"Already stripped" if salvaged else ""))
		out.append(_check())
		return out
	for z: StringName in [Vehicle.ZONE_ENGINE, Vehicle.ZONE_WHEELS, Vehicle.ZONE_FUEL, Vehicle.ZONE_HULL, &"battery"]:
		for part: StringName in VehicleService.parts_for(v, actor, z):
			var zone := z
			var id := part
			var repair := _entry(&"repair", "%s: %s" % [ItemDB.get_item(part).name, VehicleService.zone_name(z, v.kind)],
				func() -> void: v.request_service.rpc_id(1, "repair", zone, id))
			repair["group"] = "Repair"  # two or more share a submenu (InteractionMenu.grouped)
			out.append(repair)
	if VehicleService.jerrycan_fuel(actor) > 0.0:
		out.append(_entry(&"refuel", "Refuel (jerrycan)", func() -> void: v.request_service.rpc_id(1, "refuel", &"", VehicleService.JERRYCAN)))
	out.append(_check())
	return out


## Inside, for whoever sits here: Get out (left off when the get-out key is on:
## ControlOptions; Captain, P0164 queue 8), Move to another seat, Check vehicle.
func _seat_actions(_actor: Soldier) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var v := vehicle
	if not ControlOptions.get_out_key():
		out.append(_entry(&"exit", "Get out", func() -> void: v.request_exit.rpc_id(1)))
	if v.bay:
		out.append(_bay_entry())
	var moves: Array[Dictionary] = []
	for i in v.seat_count():
		if i == seat_index or v.occupant(i) != null or v.seat_kind(i) == Vehicle.PILOT:
			continue
		var index := i
		moves.append(_entry(&"switch", v.seat_name(i), func() -> void: v.request_switch.rpc_id(1, index)))
	out.append({"id": &"move_seat", "label": "Move to", "disabled": "" if not moves.is_empty() else "No free seat", "items": moves, "target": self})
	out.append(_check())
	return out


## Open or shut a walk-in bay's doors and ramp (VehicleBay), from a seat, a door or inside.
func _bay_entry() -> Dictionary:
	var v := vehicle
	var to_open: bool = not v.bay.open
	return _entry(&"bay", "Open bay doors" if to_open else "Close bay doors", func() -> void: v.request_bay.rpc_id(1, to_open))


## Standing in a walk-in bay by this seat: sit in it (a pilot's is the AI's), or work the doors.
func _walk_up_actions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var v := vehicle
	var index := seat_index
	if v.seat_kind(index) != Vehicle.PILOT:
		var why := "" if v.occupant(index) == null else "Taken"
		var label := "Sit here" if v.bay.ffv_side(index) == 0.0 else "Sit here (fires out of the door)"
		out.append(_entry(&"sit", label, func() -> void: v.request_enter.rpc_id(1, index), why))
	out.append(_bay_entry())
	return out


func _first_free(k: StringName) -> int:
	for i: int in seat_list:
		if vehicle.seat_kind(i) == k and vehicle.occupant(i) == null:
			return i
	return -1


static func _kind_name(k: StringName) -> String:
	return {Vehicle.DRIVER: "driver", Vehicle.GUNNER: "gunner", Vehicle.PILOT: "pilot", Vehicle.PASSENGER: "passenger"}.get(k, String(k))


static func _state_text(item: ItemData, state: Dictionary) -> String:
	if state.has("rounds"):
		return " (%d rds)" % int(state.rounds)
	if state.has("fuel_l"):
		return " (%.0f L)" % float(state.fuel_l)
	if item and item.id == VehicleService.JERRYCAN:
		return " (%.0f L)" % float(item.stats.get("fuel_l", 20.0))
	return ""
