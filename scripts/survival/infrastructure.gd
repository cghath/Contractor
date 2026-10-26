class_name Infrastructure
extends RefCounted
## The old world's infrastructure brought back (docs/survival_building.md §8, call 60;
## docs/survival_seasons.md): static, its state in the settlement's record (Settlement.data():
## "power", "powered", "lamps_lit", "battery", "projects") and the world's (Survival.state()["infra"]:
## water works, zone power, cleared roads; the world section's "crossings": bridges blown).
##
## - Power: sources are generators (running on fuel in stock, loud: the footprint's noise),
##   solar panels (quiet, by day by the weather), wind turbines (by the wind) and battery banks
##   (charged by the hour from what's spare, run things at night). Wiring is reach: a piece is on
##   the network when it's within WIRE_M of a source or of a wiring piece (or a consumer) that is.
##   Consumers draw DRAW watts, in PRIORITY order, while supply and the batteries last: lamps (the
##   footprint's light: a lit settlement is found sooner, and at night it raises the zone's
##   pressure), a fridge (food keeps: fridge_on for the body lane), the radio (FallenRadio's power
##   check: powered_here), an electric fence (Traps: stuns walkers), a power tool bench (the build
##   job FASTER), a water pump (pump_on for the body lane).
## - Projects (call 60), worked by the settlement's maintain job (SettlementJobs) a world hour at a
##   time once their parts are paid from stock: the water works (a town's tower or pump house:
##   the body lane's WaterWorks told through has_method), the dam or power plant (a late multi-day
##   job: an event when done, the zone powered, every group's eye on it), clearing a road of wrecks
##   (a truck's job), repairing a bridge; blowing a bridge (demolitions) marks the crossing between
##   two zones closed in the world sim (WorldModel.crossing_open): hordes and raiders go round.
## Every number here is Proposed.

const SOURCES := {"generator": 3.0, "solar_panel": 1.0, "wind_turbine": 1.5}
const DRAW := {"lamp": 0.25, "fridge": 0.6, "electric_fence": 1.0, "power_tools": 1.0, "water_pump": 0.8}
const PRIORITY: Array[String] = ["electric_fence", "fridge", "water_pump", "lamp", "power_tools"]
const BATTERY_KWH := 4.0
const WIRE_M := 3.5
const WIND_MIN_MPS := 2.0
const FASTER := 1.5
## At night a lit settlement raises the zone's pressure this much an hour per metre of light.
const LIGHT_PRESSURE := 0.05
const PROJECTS := {
	"water_works": {"name": "Repair the water works", "hours": 24.0, "cost": [[&"scrap_sheet", 4], [&"machine_parts", 1]]},
	"dam": {"name": "Bring the dam back", "hours": 96.0, "cost": [[&"steel_beam", 4], [&"concrete_bag", 6], [&"engine_parts", 2], [&"copper_wire", 4]]},
	"clear_road": {"name": "Clear the road of wrecks", "hours": 8.0, "cost": []},
	"bridge_repair": {"name": "Repair the bridge", "hours": 16.0, "cost": [[&"steel_beam", 2], [&"concrete_bag", 4]]},
}


static func world() -> Dictionary:
	var st := Survival.state()
	if not st.get("infra") is Dictionary:
		st["infra"] = {}
	return st["infra"]


# --- Power ------------------------------------------------------------------------------------

## Host (Settlement.refresh): the network from the builds in the settlement's radius: what's
## connected, what it makes now, what's powered (by PRIORITY while supply and battery last).
static func server_refresh(st: Settlement, b: Builder) -> void:
	var d := Settlement.data()
	if b == null:
		return
	var c := Settlement.pos()
	var r := Settlement.radius() + 4.0
	var nodes: Array = []  # [id, kind, pos]
	for id: int in b.pieces:
		if not b.is_piece_built(id) or b.piece_pos(id).distance_to(c) > r:
			continue
		var k := String(b.pieces[id].k)
		if SOURCES.has(k) or DRAW.has(k) or k in ["wiring", "battery_bank"]:
			nodes.append([id, k, b.piece_pos(id)])
	# The network: from every source, through anything within WIRE_M.
	var on := {}
	var queue: Array = []
	for n: Array in nodes:
		if SOURCES.has(String(n[1])) or String(n[1]) == "battery_bank":
			on[int(n[0])] = true
			queue.append(n)
	while not queue.is_empty():
		var a: Array = queue.pop_back()
		for n: Array in nodes:
			if not on.has(int(n[0])) and (n[2] as Vector3).distance_to(a[2] as Vector3) <= WIRE_M:
				on[int(n[0])] = true
				queue.append(n)
	var supply := 0.0
	var batteries := 0
	for n: Array in nodes:
		if not on.has(int(n[0])):
			continue
		match String(n[1]):
			"generator":
				supply += float(SOURCES.generator) if Settlement.count_cat("fuel") > 0 else 0.0
			"solar_panel":
				supply += float(SOURCES.solar_panel) * sun()
			"wind_turbine":
				supply += float(SOURCES.wind_turbine) * (1.0 if DayNight.wind().length() >= WIND_MIN_MPS else 0.3)
			"battery_bank":
				batteries += 1
	var stored := float(d.get("battery", 0.0))
	var cap := BATTERY_KWH * batteries
	stored = minf(stored, cap)
	var left := supply + (stored if stored > 0.0 else 0.0)
	var powered := {}
	var kinds := {}
	var lamps_lit := 0
	var demand := 0.0
	for want: String in PRIORITY:
		for n: Array in nodes:
			if String(n[1]) != want or not on.has(int(n[0])):
				continue
			var w := float(DRAW[want])
			demand += w
			if left >= w - 0.001:
				left -= w
				powered[str(int(n[0]))] = true
				kinds[str(int(n[0]))] = want
				if want == "lamp":
					lamps_lit += 1
	d["power"] = {"supply": snappedf(supply, 0.01), "demand": snappedf(demand, 0.01), "batteries": batteries, "cap": cap, "on": on.size()}
	d["powered"] = powered
	d["powered_kinds"] = kinds
	d["lamps_lit"] = lamps_lit
	d["battery"] = stored


## How much sun the panels see now (0 at night, less under cloud and rain).
static func sun() -> float:
	var h := Survival.hour()
	if h < 7.0 or h > 18.0:
		return 0.0
	var dn := DayNight.current()
	var w := dn.weather if dn else "clear"
	return float({"clear": 1.0, "overcast": 0.5, "fog": 0.5, "rain": 0.3, "storm": 0.1}.get(w, 1.0))


## Whether piece `id` has power (the last refresh).
static func is_powered(id: int) -> bool:
	return bool((Settlement.data().get("powered", {}) as Dictionary).get(str(id), false))


## A powered fridge in the settlement (the body lane: food keeps).
static func fridge_on() -> bool:
	return _powered_kind("fridge")


## A powered water pump (the body lane: water at the taps).
static func pump_on() -> bool:
	return _powered_kind("water_pump")


## The build job's speed with powered power tools.
static func build_mult() -> float:
	return FASTER if _powered_kind("power_tools") else 1.0


## Whether the settlement has power to spare for the radio (FallenRadio.at_generator).
static func powered_here() -> bool:
	var p: Dictionary = Settlement.data().get("power", {})
	return float(p.get("supply", 0.0)) > 0.0 or float(Settlement.data().get("battery", 0.0)) > 0.0


static func _powered_kind(kind: String) -> bool:
	return kind in (Settlement.data().get("powered_kinds", {}) as Dictionary).values()


## Host, every world hour (Settlement.server_hour): the batteries charge from what's spare (or run
## down at night), and a lit settlement at night raises the zone's pressure.
static func server_hour(st: Settlement, hod: int) -> void:
	var d := Settlement.data()
	var p: Dictionary = d.get("power", {})
	var spare := float(p.get("supply", 0.0)) - float(p.get("demand", 0.0))
	d["battery"] = clampf(float(d.get("battery", 0.0)) + spare, 0.0, float(p.get("cap", 0.0)))
	var night := hod >= Settlement.SLEEP_FROM or hod < Settlement.SLEEP_TO - 1
	var light := float((Settlement.footprint() as Dictionary).get("light_m", 0.0))
	if night and light > 0.0 and st and st.hosted() and st.level is ZoneLevel:
		Survival._raise_pressure(st.level, Settlement.pos(), light * LIGHT_PRESSURE)


# --- Projects ---------------------------------------------------------------------------------

## Host: a project of `kind` for `zone_id` (its parts paid from the settlement's stock now).
## "" or why not.
static func server_start_project(kind: String, zone_id := "", extra := {}) -> String:
	if not PROJECTS.has(kind) or not Settlement.exists():
		return "?"
	var def: Dictionary = PROJECTS[kind]
	if not Settlement.pay(def.cost):
		return "Not enough in stock: %s" % BuildPieces.cost_text(def.cost)
	var d := Settlement.data()
	var list: Array = d.get("projects", [])
	var p := {"kind": kind, "zone": zone_id if zone_id != "" else Settlement.zone(), "hours": 0.0, "need": float(def.hours), "started": Survival.day()}
	p.merge(extra, false)
	list.append(p)
	d["projects"] = list
	Survival._journal_line("We've started on it: %s." % String(def.name).to_lower())
	return ""


## Host (the maintain job): `hours` on the first open project. Returns whether any work was done.
static func work_project(_st: Settlement, hours: float) -> bool:
	var list: Array = Settlement.data().get("projects", [])
	for p: Dictionary in list:
		if bool(p.get("done", false)):
			continue
		p["hours"] = float(p.hours) + hours
		if float(p.hours) >= float(p.need):
			p["done"] = true
			_finish(p)
		return true
	return false


static func _finish(p: Dictionary) -> void:
	var z := String(p.zone)
	var w := world()
	match String(p.kind):
		"water_works":
			var water: Dictionary = w.get("water", {})
			water[z] = true
			w["water"] = water
			_call_global("WaterWorks", "server_repaired", [z])  # (the body lane's: taps run)
			Survival._journal_line("The water works run again: the taps in %s have water." % RegionMap.zone_name(z))
		"dam":
			var zp: Dictionary = w.get("zone_power", {})
			zp[z] = true
			w["zone_power"] = zp
			_world_event(z, "dam", "the dam's turbines are turning: %s has power again, and every group has seen the lights" % RegionMap.zone_name(z), 40.0)
			Survival._journal_line("The dam runs. %s has power: every group will have seen the lights." % RegionMap.zone_name(z))
		"clear_road":
			var roads: Dictionary = w.get("roads", {})
			roads[z] = true
			w["roads"] = roads
			Survival._journal_line("The road through %s is clear of wrecks." % RegionMap.zone_name(z))
		"bridge_repair":
			server_set_crossing(z, String(p.get("to", "")), true)
			Survival._journal_line("The bridge is passable again.")


## Whether zone `z` has power from the dam or plant.
static func zone_powered(z: String) -> bool:
	return bool((world().get("zone_power", {}) as Dictionary).get(z, false))


static func water_works_on(z: String) -> bool:
	return bool((world().get("water", {}) as Dictionary).get(z, false))


# --- Bridges --------------------------------------------------------------------------------

## Host: the crossing between zones `a` and `b` open or closed (a bridge blown or repaired): the
## world sim's goals and hordes go round a closed one (WorldModel.crossing_open).
static func server_set_crossing(a: String, b: String, open: bool) -> void:
	if a == "" or b == "":
		return
	var key := WorldModel.crossing_key(a, b)
	var fn := func(w: Dictionary) -> void:
		var cr: Dictionary = w.get("crossings", {})
		if open:
			cr.erase(key)
		else:
			cr[key] = "blown"
		w["crossings"] = cr
	var sim := WorldSim.get_sim()
	if sim:
		sim.mutate(fn)
	else:
		fn.call(WorldSim.section())
	_world_event(a, "bridge_repaired" if open else "bridge_blown", ("the bridge between %s and %s is passable again" if open else "the bridge between %s and %s was blown") % [RegionMap.zone_name(a), RegionMap.zone_name(b)], 0.0 if open else 20.0)


static func server_blow_bridge(a: String, b: String) -> void:
	server_set_crossing(a, b, false)


static func _world_event(z: String, kind: String, text: String, pressure: float) -> void:
	var fn := func(w: Dictionary) -> void:
		var m := WorldModel.new(w, WorldSim.people(), WorldSim.pressure_section(), WorldSim.world_seed())
		m.now = WorldSim.world_now()
		m.hosted = WorldSim.hosted_zone()
		if pressure > 0.0 and z != m.hosted:
			m.raise_pressure(z, pressure)
		m.event(z, kind, [], text)
	var sim := WorldSim.get_sim()
	if sim:
		sim.mutate(fn)
	else:
		fn.call(WorldSim.section())


## Calls `method` on the global class `cls` if another lane has made it (it may not exist here).
static func _call_global(cls: String, method: String, args: Array) -> Variant:
	for g: Dictionary in ProjectSettings.get_global_class_list():
		if String(g.get("class", "")) == cls:
			var script: Script = load(String(g.path))
			if script and (script.get_script_method_list() as Array).any(func(m: Dictionary) -> bool: return String(m.name) == method):
				return script.callv(method, args)
	return null


# --- Pieces' actions (Builder piece_act) -----------------------------------------------------

## Host: `s` did `what` on piece `id` (BuildPiece's menu through Builder): the phase D pieces'
## own actions. "?" when it isn't one of them.
static func server_piece_act(b: Builder, s: Soldier, id: int, what: String) -> String:
	match what:
		"reset_trap":
			return Traps.server_reset(b, id)
		"radio_on":
			return Lures.server_radio_on(b, id)
		"light_pyre":
			return Masking.server_light_pyre(b, s, id)
	return "?"


## The phase D pieces' menu entries for BuildPiece (built pieces): [[id, label, what], ...].
static func piece_menu(rec: Dictionary) -> Array:
	match String(rec.get("k", "")):
		"bear_trap":
			return [[&"trap_reset", "Reset the trap", "reset_trap"]] if bool(rec.get("sprung", false)) else []
		"lure_radio":
			return [[&"radio_on", "Leave it playing", "radio_on"]]
		"pyre":
			return [[&"pyre_light", "Light the pyre", "light_pyre"]]
	return []
