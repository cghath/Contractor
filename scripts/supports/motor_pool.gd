class_name MotorPool
extends RefCounted
## The company's motor pool (wave 5b, V4): its own vehicles between deployments, kept in the
## campaign save's "motor_pool" section (Campaign) as records: each {"id", "model", "scheme",
## "name", "record" (Vehicle.to_save without its place: damage by zone, fuel, battery, cargo,
## hull damage), "out" (the zone it's deployed in, "" at home), "ready_day" (in the workshop
## until then), "added_day"}. Host only; clients see it through MotorPoolNode.
##
## - add() / remove() / list() / entry(): the records.
## - server_bring(id, level, xform): the vehicle at a deployment's insertion, as the record has
##   it (Vehicle id "pool_<id>", meta "pool_id"); it's out until it comes back.
## - server_return(vehicle): it extracted with the squad: its record takes the vehicle's state
##   now (damage, fuel, cargo) and it's home. Destroyed, or left behind: removed (remove()).
## - repair_quote(id) / server_repair(id): the workshop fixes every hit zone, the battery and
##   the hull and fills the tank, for money (Economy) and days (it can't deploy until ready_day).
## A new campaign starts with data/ground_supports.json "motor_pool" "start" (Proposed: one
## M-ATV), given the first time the section is used. Numbers there are Proposed.

const SECTION := &"motor_pool"
## Record keys that are about one zone, not the vehicle.
const PLACE_KEYS := ["id", "pos", "rot", "bodies", "faction"]


static func _cfg() -> Dictionary:
	return AavSupport.data().get("motor_pool", {})


## The campaign's day, read without starting a campaign (Economy.day() would make one).
static func today() -> int:
	return int(Campaign.section(&"economy").get("day", 1))


## Whether the pool is in use this session (a campaign runs, or it was set up): only then do
## briefings offer its vehicles.
static func in_use() -> bool:
	return BaseHub.campaign_running or Campaign.section(SECTION).has("vehicles")


## The section, with the starting vehicles the first time.
static func _s() -> Dictionary:
	var s := Campaign.section(SECTION)
	if not s.has("vehicles"):
		s["vehicles"] = []
		s["serial"] = 0
		for v: Dictionary in _cfg().get("start", []):
			_add_to(s, String(v.get("model", "matv")), String(v.get("scheme", "")), {})
		Campaign.mark_changed(SECTION)
	return s


## Every vehicle in the pool (copies).
static func list() -> Array:
	return (_s().vehicles as Array).duplicate(true)


## One vehicle's entry (a copy), {} if there's none.
static func entry(id: String) -> Dictionary:
	return _find(id).duplicate(true)


static func _find(id: String) -> Dictionary:
	for e: Dictionary in _s().vehicles:
		if String(e.id) == id:
			return e
	return {}


## Host: a vehicle of `model` joins the pool, as `record` has it (Vehicle.to_save; {} for a new
## one). Returns its id ("" for a model with no numbers).
static func add(model: String, scheme := "", record := {}) -> String:
	if not VehicleSpecs.has_model(model):
		return ""
	var id := _add_to(_s(), model, scheme, record)
	Campaign.mark_changed(SECTION)
	return id


static func _add_to(s: Dictionary, model: String, scheme: String, record: Dictionary) -> String:
	s.serial = int(s.get("serial", 0)) + 1
	var id := "mp%d" % int(s.serial)
	var rec := record.duplicate(true)
	for k: String in PLACE_KEYS:
		rec.erase(k)
	if scheme == "":
		scheme = String(rec.get("scheme", VehicleArt.MODELS.get(model, ["od"])[0]))
	(s.vehicles as Array).append({"id": id, "model": model, "scheme": scheme, "name": String(VehicleSpecs.spec(model).get("name", model)),
		"record": rec, "out": "", "ready_day": 0, "added_day": today()})
	return id


## Host: the vehicle leaves the pool for good. Returns whether it was there.
static func remove(id: String) -> bool:
	var list: Array = _s().vehicles
	for i in list.size():
		if String(list[i].id) == id:
			list.remove_at(i)
			Campaign.mark_changed(SECTION)
			return true
	return false


## Why vehicle `id` can't go on a deployment now ("" if it can).
static func problem(id: String) -> String:
	var e := _find(id)
	if e.is_empty():
		return "Not in the motor pool"
	if String(e.get("out", "")) != "":
		return "Out on a deployment"
	if bool((e.record as Dictionary).get("wrecked", false)):
		return "Written off"
	if today() < int(e.get("ready_day", 0)):
		return "In the workshop until day %d" % int(e.ready_day)
	return ""


## Host: vehicle `id` comes to `level` at `xform` (a deployment's insertion), as its record has
## it. Returns the vehicle, or null if it can't come (problem()).
static func server_bring(id: String, level: Node, xform: Transform3D) -> Vehicle:
	var e := _find(id)
	var layer := level.get_node_or_null(^"Vehicles") as VehicleLayer if level else null
	if e.is_empty() or problem(id) != "" or layer == null or not level.multiplayer.is_server():
		return null
	var rec: Dictionary = (e.record as Dictionary).duplicate(true)
	var v := layer.server_spawn(String(e.model), xform, String(e.scheme), &"player", "pool_%s" % id, rec)
	if v == null:
		return null
	v.set_meta(&"pool_id", id)
	v.set_meta(&"no_save", true)  # it goes home with the squad; left behind, MotorPoolNode lets the zone keep it
	e.out = GameState.zone_id
	Campaign.mark_changed(SECTION)
	print("[motor pool] %s (%s) brought to %s" % [e.name, id, GameState.zone_id])
	return v


## The pool id of a vehicle brought from the pool ("" for any other).
static func pool_id(v: Vehicle) -> String:
	return String(v.get_meta(&"pool_id", "")) if is_instance_valid(v) else ""


## Host: `v` came home with the squad: its record takes its state now (damage, fuel, cargo,
## hull) and it leaves the zone. A wreck, or one burning, is lost instead (removed). Returns
## whether it's back in the pool.
static func server_return(v: Vehicle) -> bool:
	var id := pool_id(v)
	var e := _find(id)
	if e.is_empty() or not v.multiplayer.is_server():
		return false
	if v.wrecked or v.is_burning():
		remove(id)
		return false
	var rec := v.to_save()
	for k: String in PLACE_KEYS:
		rec.erase(k)
	e.record = rec
	e.out = ""
	Campaign.mark_changed(SECTION)
	for s: Soldier in v.occupants():
		v.server_exit(s)
	v.queue_free()
	print("[motor pool] %s (%s) back" % [e.name, id])
	return true


## How much vehicle `id` is damaged, 0 (whole) to 1 (written off): its hit zones' wear, weighted.
static func damage_of(id: String) -> float:
	var e := _find(id)
	if e.is_empty():
		return 0.0
	var zones: Dictionary = (e.record as Dictionary).get("zones", {})
	var weights: Dictionary = _cfg().get("zone_weights", {"hull": 0.4, "engine": 0.3, "wheels": 0.2, "fuel": 0.1})
	var total := 0.0
	var worn := 0.0
	for z: String in weights:
		total += float(weights[z])
		worn += float(weights[z]) * (1.0 - clampf(float(zones.get(z, 1.0)), 0.0, 1.0))
	return worn / total if total > 0.0 else 0.0


## What the workshop would charge for vehicle `id`: {"cost" (dollars), "days", "damage" (0-1),
## "fuel_l" (litres to fill)}.
static func repair_quote(id: String) -> Dictionary:
	var e := _find(id)
	if e.is_empty():
		return {"cost": 0, "days": 0, "damage": 0.0, "fuel_l": 0.0}
	var cfg := _cfg()
	var rec: Dictionary = e.record
	var spec := VehicleSpecs.spec(String(e.model))
	var damage := damage_of(id)
	var value := float((cfg.get("value", {}) as Dictionary).get(String(e.model), cfg.get("default_value", 250000)))
	var cost := roundi(value * float(cfg.get("repair_share", 0.12)) * damage)
	var days := ceili(damage * float(cfg.get("repair_days", 6))) if damage > 0.001 else 0
	if not bool(rec.get("battery", true)):
		cost += int(cfg.get("battery_price", 800))
		days = maxi(days, 1)
	var fuel_l := maxf(float(spec.get("fuel_l", 0.0)) - float(rec.get("fuel", spec.get("fuel_l", 0.0))), 0.0)
	cost += roundi(fuel_l * float(cfg.get("fuel_price", 2)))
	return {"cost": cost, "days": days, "damage": damage, "fuel_l": fuel_l}


## Host: the workshop fixes vehicle `id` (every zone whole, the battery, the hull's damage, a
## full tank) if the company pays; it's back from the workshop on ready_day. Returns "" or why not.
static func server_repair(id: String) -> String:
	var e := _find(id)
	if e.is_empty():
		return "Not in the motor pool"
	if String(e.get("out", "")) != "":
		return "It's out on a deployment"
	if bool((e.record as Dictionary).get("wrecked", false)):
		return "Written off"
	var quote := repair_quote(id)
	if int(quote.cost) <= 0 and int(quote.days) <= 0:
		return "Nothing to repair"
	if not Economy.spend(int(quote.cost), "Motor pool: %s serviced" % String(e.name)):
		return "Can't afford it ($%s)" % DebriefCalc.money(int(quote.cost))
	var rec: Dictionary = e.record
	var zones := {}
	for z: StringName in Vehicle.ZONES:
		zones[String(z)] = 1.0
	rec["zones"] = zones
	rec["battery"] = true
	rec["leak"] = 0.0
	rec["carves"] = []
	rec["fuel"] = float(VehicleSpecs.spec(String(e.model)).get("fuel_l", 0.0))
	e.ready_day = maxi(int(e.get("ready_day", 0)), today() + int(quote.days))
	Campaign.mark_changed(SECTION)
	print("[motor pool] %s (%s) serviced: $%d, %d days" % [e.name, id, int(quote.cost), int(quote.days)])
	return ""


## Host: what each vehicle looks like on a screen: {"id", "name", "model", "damage", "fuel",
## "problem", "quote"}.
static func view() -> Array:
	var out: Array = []
	for e: Dictionary in _s().vehicles:
		var id := String(e.id)
		out.append({"id": id, "name": String(e.name), "model": String(e.model), "damage": snappedf(damage_of(id), 0.01),
			"fuel": snappedf(float((e.record as Dictionary).get("fuel", VehicleSpecs.spec(String(e.model)).get("fuel_l", 0.0))), 0.1),
			"problem": problem(id), "quote": repair_quote(id)})
	return out
