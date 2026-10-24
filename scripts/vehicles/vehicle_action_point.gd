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
## Combined arms A8 (cg_brief queue item 2.6, VehicleLogistics): the cargo point rearms (from your
## kit, the hold, a truck's hold or a pallet within 8 m), takes rounds out, refuels from fuel
## pallets and loads a pallet lying by it; the service point repairs module by module (a model
## with modules), puts back fired ERA tiles and slat, and hooks up or drops a tow; a crewman
## stows rounds from the hold from his seat.
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
	lines.append_array(logistics_report(v))
	return "\n".join(lines)


## A8's lines for Check vehicle: packages and their STANAG rating, the racks as items, the smoke
## stowage, the extinguisher bottles, a tow.
static func logistics_report(v: Vehicle) -> PackedStringArray:
	var lines := PackedStringArray()
	var lg := v.logistics
	if lg == null:
		return lines
	if not lg.packages.is_empty():
		var names: Array = lg.packages.map(func(p: Variant) -> String: return String((v.spec.get("packages", {}) as Dictionary).get(String(p), {}).get("name", p)))
		lines.append("Packages: %s (%s)" % [", ".join(PackedStringArray(names)), ArmourStandards.text(v.spec, lg.packages)])
	if v.weapons:
		for rack: Variant in v.weapons.racks:
			var parts := PackedStringArray()
			for e: Dictionary in lg.rack_items(String(rack)):
				if int(e.count) > 0 or int(e.loose) > 0:
					parts.append("%d %s%s" % [int(e.count), ItemDB.get_item(e.id).name, " + %d loose" % int(e.loose) if int(e.loose) > 0 else ""])
			lines.append("%s: %s" % [VehicleLogistics.module_name(String(rack)).capitalize(), ", ".join(parts) if not parts.is_empty() else "empty"])
	if v.smoke:
		lines.append("Smoke stowage: %d salvos" % v.smoke.stowed_salvos())
	if not lg.bottles.is_empty():
		var full := VehicleLogistics.full_bottles(v.model)
		lines.append("Extinguishers: %s" % ", ".join(PackedStringArray(lg.bottles.keys().map(func(k: Variant) -> String:
			return "%s %d/%d" % [String(k), int(lg.bottles[k]), int(full.get(k, 0))]))))
	if lg.towed():
		lines.append("Under tow")
	return lines


## A door's ring (Captain, P0164 queue 8: get in and the seat choices first, nothing you can't
## do): a Get in entry for each kind of seat this door serves that has one free (driver,
## gunner, a tank's commander and loader (A3), then passenger), never a pilot's (aircraft are flown by AI); when none is free, one
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
		for k: StringName in [Vehicle.COMMANDER, Vehicle.LOADER]:  # A3: a tank's hatch seats take a casualty as before
			free = _first_free(k) if free < 0 else free
		out.append(_entry(&"load_body", "Load casualty", func() -> void: v.request_load_body.rpc_id(1, free),
			"" if free >= 0 else "No free seat on this side"))
		return out
	for k: StringName in [Vehicle.DRIVER, Vehicle.GUNNER, Vehicle.COMMANDER, Vehicle.LOADER, Vehicle.PASSENGER]:
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
	if v.kind == Vehicle.STATIC and StaticWeapons.KITS.has(v.model):  # G-25: back to its loads
		out.append(_entry(&"pack_static", "Pack up the gun (%d s)" % int(StaticWeapons.KITS[v.model].pack_s), func() -> void: v.request_pack.rpc_id(1),
			StaticWeapons.pack_problem(actor, v)))
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
	if v.kind == Vehicle.STATIC and not v.wrecked and not MortarFire.spec_of(v).is_empty():  # G-25 part d: a mortar
		out.append(_entry(&"lay_mortar", "Lay and fire (firing table)", func() -> void:
			MortarPanel.open(v, rad_to_deg(-actor.camera.global_rotation.y))))
		out.append(_entry(&"pack_static", "Pack up the mortar (%d s)" % int(StaticWeapons.KITS[v.model].pack_s), func() -> void: v.request_pack.rpc_id(1),
			StaticWeapons.pack_problem(actor, v)))
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
	out.append_array(_logistics_cargo(actor))  # A8
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
	var lg := v.logistics
	var by_module := v.modules != null and v.modules.authored and lg != null
	if by_module:
		out.append_array(_module_repairs(actor))  # A8: module by module, 2.2.2's field column
	for z: StringName in ([&"battery"] if by_module else [Vehicle.ZONE_ENGINE, Vehicle.ZONE_WHEELS, Vehicle.ZONE_FUEL, Vehicle.ZONE_HULL, &"battery"]):
		for part: StringName in VehicleService.parts_for(v, actor, z):
			var zone := z
			var id := part
			var repair := _entry(&"repair", "%s: %s" % [ItemDB.get_item(part).name, VehicleService.zone_name(z, v.kind)],
				func() -> void: v.request_service.rpc_id(1, "repair", zone, id))
			repair["group"] = "Repair"  # two or more share a submenu (InteractionMenu.grouped)
			out.append(repair)
	if VehicleService.jerrycan_fuel(actor) > 0.0:
		out.append(_entry(&"refuel", "Refuel (jerrycan)", func() -> void: v.request_service.rpc_id(1, "refuel", &"", VehicleService.JERRYCAN)))
	if lg:
		out.append_array(_tow_entries())
	out.append(_check())
	return out


## A8: the field repairs of a model with modules, each "<part>: <module>" in the Repair submenu,
## greyed with why (a part missing, the workshop's job); fired ERA tiles and slat with a spare.
func _module_repairs(actor: Soldier) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var v := vehicle
	var lg := v.logistics
	for o: Dictionary in lg.repair_options(actor):
		var module := String(o.module)
		var id: StringName = o.item
		var e := _entry(&"repair", String(o.label), (func() -> void: v.request_service.rpc_id(1, "repair_module", StringName(module), id)) if id != &"" else Callable(),
			String(o.why))
		e["group"] = "Repair"
		out.append(e)
	var fired := lg.fired_tiles()
	for g: String in fired:
		var spare := VehicleLogistics.tile_spare(lg.tile_kind(g))
		if spare == &"" or not lg.has_part(actor, spare):
			continue
		var group := g
		var e2 := _entry(&"replace_tile", "%s: %s (%d missing)" % [ItemDB.get_item(spare).name, g.replace("_", " "), (fired[g] as Array).size()],
			func() -> void: v.request_service.rpc_id(1, "tile", StringName(group), spare))
		e2["group"] = "Repair"
		out.append(e2)
	return out


## A8: the tow at the service point: Unhook while it's towed or towing; on a vehicle that can't
## drive, Hook up to each vehicle near enough to tow it (2.8.3's stand-in for a recovery vehicle).
func _tow_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var v := vehicle
	var lg := v.logistics
	if lg.towed() or String(lg.net_state.get("tg", "")) != "":
		out.append(_entry(&"unhook", "Unhook the tow", func() -> void: v.request_service.rpc_id(1, "unhook", &"", &"")))
		return out
	if v.can_drive() or v.wrecked:
		return out
	var n := 0
	for t: Vehicle in lg.tow_candidates():
		if n >= 3:
			break
		n += 1
		var id := t.vehicle_id
		var e := _entry(&"tow", ("Hook up to the %s to right it (%d s)" if v.drive and v.drive.is_rolled() else "Hook up to the %s for a tow (%d s)") % [t.display_name(), roundi(VehicleLogistics.num("tow", "hook_s", 60.0))],
			func() -> void: v.request_service.rpc_id(1, "tow", StringName(id), &""), lg.tow_problem(t))
		e["group"] = "Tow"
		out.append(e)
	return out


## A8: the cargo point's rearming: one entry per source (your kit, the hold, a truck's hold, a
## pallet within 8 m) in a Rearm submenu, rounds out of the racks in a Take out rounds submenu,
## refuelling from fuel pallets, and loading a pallet lying by the cargo point.
func _logistics_cargo(actor: Soldier) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var v := vehicle
	var lg := v.logistics
	if lg == null or v.wrecked:
		return out
	for src: Dictionary in lg.rearm_sources(actor):
		var key := String(src.key)
		var items: Dictionary = src.items
		var n := 0
		var why := ""
		var ok := false
		for id: Variant in items:
			n += int(items[id])
			var w := lg.stow_problem(StringName(String(id)))
			if w == "":
				ok = true
			elif why == "":
				why = w
		var e := _entry(&"rearm", "Rearm: %s (%d)%s" % [String(src.label).to_lower(), n, " x%d speed" % roundi(float(src.mult)) if float(src.mult) > 1.0 else ""],
			func() -> void: v.request_service.rpc_id(1, "stow", StringName(key), &""), "" if ok else why)
		e["group"] = "Rearm"
		out.append(e)
	var racks: Array = (v.weapons.racks.keys() if v.weapons else []) + ([VehicleLogistics.SMOKE_RACK] if v.smoke else [])
	var taken := 0
	for rack: Variant in racks:
		for e: Dictionary in lg.rack_items(String(rack)):
			if int(e.count) <= 0 or taken >= MAX_ENTRIES:
				continue
			taken += 1
			var r := String(rack)
			var id: StringName = e.id
			var out_e := _entry(&"unstow", "%s from the %s (%d)" % [ItemDB.get_item(id).name, VehicleLogistics.module_name(r), int(e.count)],
				func() -> void: v.request_service.rpc_id(1, "unstow", StringName(r), id))
			out_e["group"] = "Take out rounds"
			out.append(out_e)
	for f: Dictionary in lg.fuel_sources():
		var key2 := String(f.key)
		out.append(_entry(&"refuel_from", "Refuel: %s (%.0f L, %.0f L/min)" % [String(f.label).to_lower(), float(f.litres), float(f.lpm)],
			func() -> void: v.request_service.rpc_id(1, "refuel_from", StringName(key2), &""),
			"The tank is full" if v.fuel_litres() >= float(v.spec.get("fuel_l", 0.0)) - 0.5 else ""))
	if v.cargo_hold:
		for wi: WorldItem in lg._pallets_near(6.0):
			var uid := wi.uid
			var item := ItemDB.get_item(wi.item_id)
			out.append(_entry(&"load_pallet", "Load the %s" % item.name.to_lower(), func() -> void: v.request_service.rpc_id(1, "load_pallet", &"", StringName(uid)),
				"" if v.cargo_hold.room_for(VehicleCargo.HOLD, item, wi.state) > 0 else "No room in the hold"))
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
	if v.logistics and not v.wrecked:  # A8: a crewman stows rounds from the hold
		for src: Dictionary in v.logistics.rearm_sources(null):
			if String(src.key) == VehicleLogistics.HOLD:
				out.append(_entry(&"rearm", "Stow rounds from the hold", func() -> void: v.request_service.rpc_id(1, "stow", StringName(VehicleLogistics.HOLD), &"")))
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
	return {Vehicle.DRIVER: "driver", Vehicle.GUNNER: "gunner", Vehicle.PILOT: "pilot", Vehicle.PASSENGER: "passenger", Vehicle.COMMANDER: "commander",
		Vehicle.LOADER: "loader"}.get(k, String(k))


static func _state_text(item: ItemData, state: Dictionary) -> String:
	if state.has("rounds"):
		return " (%d rds)" % int(state.rounds)
	if state.has("fuel_l"):
		return " (%.0f L)" % float(state.fuel_l)
	if item and item.id == VehicleService.JERRYCAN:
		return " (%.0f L)" % float(item.stats.get("fuel_l", 20.0))
	return ""
