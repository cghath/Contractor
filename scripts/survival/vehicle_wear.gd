class_name VehicleWear
extends RefCounted
## Vehicle wear (call 123; docs/survival_wear.md): on the host, in a survival world, a ground
## vehicle keeps its wear in its meta ("wear": engine, tyres, battery 0-100, km, flat, fuel_day,
## stall_until). Distance wears the engine, the tyres and the battery (Vehicle._use_fuel ->
## on_moved); rough ground punctures a tyre (PUNCTURE_100M by the ground, much more by a wreck):
## a flat drops top speed to FLAT_MULT until a tyre patch (server_patch); fuel goes stale with
## the world's days (stale(): found fuel is FOUND_FUEL_AGE days old, fresh for FRESH_DAYS, fully
## stale STALE_DAYS later) and stale fuel stalls the engine now and then (STALL_PER_S at worst,
## STALL_S); a worn engine is slower; a flat battery won't start. The vehicle service (engine
## parts, a new battery, a wheel) resets those (on_repair, on_battery); a settlement's mechanic
## services the vehicles near it an hour at a time (settlement_service: the "maintain" job). A
## horse's hooves wear by distance; worn under HOOF_SLOW_AT the horse is slower (hoof_mult, to
## HOOF_SLOW_MULT), and the settlement's "maintain" job reshoes the horses within its radius
## (farrier: one an hour, back to new, with a hammer in stock or a workbench built standing in for
## the anvil). Every number is Proposed.

const META := &"wear"
const ENGINE_KM := 0.02         # condition a km
const TYRES_KM := 0.04
const BATTERY_KM := 0.01
const ENGINE_SLOW_AT := 40.0
const ENGINE_SLOW_MULT := 0.75
const FLAT_MULT := 0.4
const PUNCTURE_100M := {"asphalt": 0.002, "dirt": 0.006, "grass": 0.004, "rock": 0.03, "rubble": 0.05, "sand": 0.003, "mud": 0.004, "snow": 0.003}
const WRECK_M := 6.0
const WRECK_PUNCTURE_100M := 0.15
const WORN_TYRE_X := 3.0        # tyres under 25: punctures this much more often
const FOUND_FUEL_AGE := 90.0
const FRESH_DAYS := 60.0
const STALE_DAYS := 180.0
const STALL_PER_S := 0.004
const STALL_S := Vector2(3.0, 6.0)
const PATCH_S := 25.0
const PATCH_M := 5.0
const TYRE_PATCH := &"tyre_patch"
const SERVICE_PER_H := 5.0      # a mechanic's hour: engine and battery points back (to SERVICE_TO)
const SERVICE_TO := 90.0
const HOOVES_KM := 0.05
const HOOF_SLOW_AT := 30.0
const HOOF_SLOW_MULT := 0.85
const FARRIER_BELOW := 80.0     # hooves under this get reshod
const FARRIER_TOOL := "hammer"

## Tests: force a puncture or stall roll (0..1); -1 rolls for real. (Wear.force_roll covers both too.)
static var force_roll := -1.0


static func _roll() -> float:
	if force_roll >= 0.0:
		return force_roll
	return Wear.roll()


static func ground_vehicle(v: Vehicle) -> bool:
	return v != null and (v.kind == Vehicle.WHEELED or v.kind == Vehicle.TRACKED)


## `v`'s wear record (made on first sight: as new parts, fuel FOUND_FUEL_AGE days old).
static func of(v: Vehicle) -> Dictionary:
	if not v.has_meta(META):
		v.set_meta(META, {"engine": 100.0, "tyres": 100.0, "battery": 100.0, "km": 0.0, "flat": false,
			"fuel_day": float(Survival.day()) - FOUND_FUEL_AGE, "hooves": 100.0})
	return v.get_meta(META)


## How stale `v`'s fuel is, 0 (fresh) .. 1.
static func stale(v: Vehicle) -> float:
	var age := float(Survival.day()) - float(of(v).get("fuel_day", float(Survival.day())))
	return clampf((age - FRESH_DAYS) / STALE_DAYS, 0.0, 1.0)


static func flat(v: Vehicle) -> bool:
	return v.has_meta(META) and bool(of(v).get("flat", false))


## Whether the engine has stalled just now (Vehicle.can_drive).
static func stalled(v: Vehicle) -> bool:
	return v.has_meta(META) and Soldier._now() < float(of(v).get("stall_until", -1.0))


## Vehicle.top_speed's share: a flat, a worn engine.
static func speed_mult(v: Vehicle) -> float:
	if not v.has_meta(META):
		return 1.0
	var w := of(v)
	var m := FLAT_MULT if bool(w.get("flat", false)) else 1.0
	var e := float(w.get("engine", 100.0))
	if e < ENGINE_SLOW_AT:
		m *= lerpf(ENGINE_SLOW_MULT, 1.0, e / ENGINE_SLOW_AT)
	return m


## Host (Vehicle._use_fuel): `v` moved `moved_m` metres in `delta` s.
static func on_moved(v: Vehicle, moved_m: float, delta: float) -> void:
	if not Wear.enabled() or v.wrecked:
		return
	if v.kind == "mount":
		if moved_m > 0.01 and moved_m < 50.0 and v.has_method(&"is_horse") and bool(v.call(&"is_horse")):
			var hw := of(v)
			hw["hooves"] = maxf(0.0, float(hw.get("hooves", 100.0)) - HOOVES_KM * moved_m / 1000.0)  # (the farrier reshoes them: farrier)
		return
	if not ground_vehicle(v):
		return
	var w := of(v)
	if moved_m > 0.01 and moved_m < 50.0:  # (a teleport isn't driving)
		var km := moved_m / 1000.0
		w["km"] = float(w.get("km", 0.0)) + km
		w["engine"] = maxf(0.0, float(w.engine) - ENGINE_KM * km)
		w["tyres"] = maxf(0.0, float(w.tyres) - TYRES_KM * km)
		w["battery"] = maxf(0.0, float(w.battery) - BATTERY_KM * km)
		if float(w.battery) <= 0.0 and v.battery_ok:
			v.server_set_battery(false)
		if v.kind == Vehicle.WHEELED and not bool(w.flat) and _roll() < puncture_chance(v, moved_m, float(w.tyres)):
			set_flat(v, true)
	if v.engine_running() and v.fuel > 0.0 and not stalled(v):
		var st := stale(v)
		if st > 0.0 and _roll() < STALL_PER_S * st * delta:
			w["stall_until"] = Soldier._now() + randf_range(STALL_S.x, STALL_S.y)
			var d := v.driver()
			if d:
				Wear.tell(d, "The engine sputters and dies (stale fuel)")


## The chance `moved_m` metres on `v`'s ground (and by any wreck) punctures a tyre.
static func puncture_chance(v: Vehicle, moved_m: float, tyres: float) -> float:
	var g := String(v.drive.ground()) if v.drive else "asphalt"
	var per := float(PUNCTURE_100M.get(g, 0.005))
	if near_wreck(v):
		per = maxf(per, WRECK_PUNCTURE_100M)
	if tyres < 25.0:
		per *= WORN_TYRE_X
	return per * moved_m / 100.0


static func near_wreck(v: Vehicle) -> bool:
	if not v.is_inside_tree():
		return false
	for n in v.get_tree().get_nodes_in_group(Vehicle.GROUP):
		var o := n as Vehicle
		if o and o != v and o.wrecked and o.global_position.distance_to(v.global_position) <= WRECK_M:
			return true
	return false


## A horse's speed share by its hooves (Mount.gait_speed): 1, down to HOOF_SLOW_MULT worn out.
static func hoof_mult(v: Vehicle) -> float:
	if not v.has_meta(META):
		return 1.0
	var h := float(of(v).get("hooves", 100.0))
	return 1.0 if h >= HOOF_SLOW_AT else lerpf(HOOF_SLOW_MULT, 1.0, h / HOOF_SLOW_AT)


## Whether the settlement can shoe a horse: a hammer in its stock, or a workbench built (the anvil).
static func farrier_ok() -> bool:
	return Settlement.exists() and (Settlement.count(FARRIER_TOOL) > 0 or int(Settlement.data().get("workbenches", 0)) > 0)


## Host (settlement_service, the "maintain" job's hour): the most worn horse within the
## settlement's radius under FARRIER_BELOW is reshod (hooves back to 100). The horse, or null.
static func farrier(st: Node) -> Vehicle:
	if not farrier_ok() or st == null or not st.is_inside_tree():
		return null
	var c := Settlement.pos()
	var best: Vehicle = null
	var worst := FARRIER_BELOW
	for n in st.get_tree().get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if v == null or v.wrecked or v.kind != "mount" or not v.has_meta(META) or not v.has_method(&"is_horse") or not bool(v.call(&"is_horse")):
			continue
		if v.global_position.distance_to(c) > Settlement.radius():
			continue
		var h := float(of(v).get("hooves", 100.0))
		if h < worst:
			worst = h
			best = v
	if best:
		of(best)["hooves"] = 100.0
		Survival._journal_line("The farrier reshod a horse.")
	return best


static func set_flat(v: Vehicle, on: bool) -> void:
	of(v)["flat"] = on
	if on:
		var d := v.driver()
		if d:
			Wear.tell(d, "A tyre's gone flat")


## Host (Vehicle.server_refuel): `taken` litres in on top of `before`: the tank's age blends with
## the new fuel's (found fuel: FOUND_FUEL_AGE days old; `age_days` if known).
static func on_refuel(v: Vehicle, before: float, taken: float, age_days := FOUND_FUEL_AGE) -> void:
	if not Wear.enabled() or taken <= 0.0 or not ground_vehicle(v):
		return
	var w := of(v)
	var new_day := float(Survival.day()) - age_days
	w["fuel_day"] = (float(w.fuel_day) * before + new_day * taken) / maxf(0.001, before + taken)


## Host (Vehicle.server_repair): the service's parts reset the wear they cover.
static func on_repair(v: Vehicle, zone: StringName) -> void:
	if not v.has_meta(META):
		return
	var w := of(v)
	if zone == Vehicle.ZONE_ENGINE:
		w["engine"] = maxf(float(w.engine), 80.0)
	elif zone == Vehicle.ZONE_WHEELS:
		w["tyres"] = 100.0
		w["flat"] = false


## Host (Vehicle.server_set_battery): a new battery fitted.
static func on_battery(v: Vehicle, ok: bool) -> void:
	if ok and v.has_meta(META):
		of(v)["battery"] = 100.0


## The nearest vehicle with a flat within PATCH_M of `s`, or null.
static func flat_near(s: Soldier) -> Vehicle:
	if not s.is_inside_tree():
		return null
	var best: Vehicle = null
	var best_d := PATCH_M
	for n in s.get_tree().get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if v == null or v.wrecked or not flat(v):
			continue
		var d := v.global_position.distance_to(s.global_position)
		if d <= best_d:
			best = v
			best_d = d
	return best


## Host: `s` patches `v`'s flat with a tyre patch (used up): PATCH_S (faster with mechanics 2).
static func server_patch(s: Soldier, v: Vehicle, instant := false) -> void:
	if v == null:
		return
	var secs := PATCH_S * (0.7 if Rpg.level(s, "mechanics") >= 2 else 1.0)
	var done := func() -> void:
		if not is_instance_valid(v) or not flat(v) or not s.inventory.remove_one(TYRE_PATCH):
			return
		var w := of(v)
		w["flat"] = false
		w["tyres"] = maxf(float(w.tyres), 20.0)
		Rpg.xp(s, "mechanics", 4.0)
		Wear.tell(s, "Tyre patched")
	Wear.timed(s, secs, "Patching the tyre", done, instant)


## A settlement's mechanic (SettlementJobs "maintain"): `hours` of servicing the ground vehicles
## within the settlement's radius: engine and battery SERVICE_PER_H points an hour each, up to
## SERVICE_TO. True if there was something to do.
static func settlement_service(st: Node, hours: float) -> bool:
	if not Wear.enabled() or st == null or not st.is_inside_tree():
		return false
	var c := Settlement.pos()
	var r := Settlement.radius()
	var did := farrier(st) != null
	for n in st.get_tree().get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if v == null or v.wrecked or not ground_vehicle(v) or not v.has_meta(META) or v.global_position.distance_to(c) > r:
			continue
		var w := of(v)
		for part: String in ["engine", "battery"]:
			var now := float(w.get(part, 100.0))
			if now < SERVICE_TO:
				w[part] = minf(SERVICE_TO, now + SERVICE_PER_H * hours)
				did = true
	return did


## Words for the vehicle's check ("engine 72%, tyres 40%, flat, fuel stale").
static func report(v: Vehicle) -> String:
	if not v.has_meta(META):
		return ""
	var w := of(v)
	var out := PackedStringArray()
	for part: String in ["engine", "tyres", "battery"]:
		out.append("%s %d%%" % [part, roundi(float(w.get(part, 100.0)))])
	if bool(w.get("flat", false)):
		out.append("a flat")
	var s := stale(v)
	if s > 0.0:
		out.append("fuel %s" % ("stale" if s > 0.5 else "going off"))
	return ", ".join(out)
