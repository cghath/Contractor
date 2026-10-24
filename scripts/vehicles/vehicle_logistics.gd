class_name VehicleLogistics
extends Node
## Logistics and armour packages on a ground vehicle (combined arms A8, cg_brief queue item 2.6;
## docs/combined_arms.md 2.2.2, 2.4.5, 2.8.3, 2.9, 9.2): the "Logistics" child of every wheeled
## and tracked vehicle. Numbers in data/vehicle_logistics.json, prices in data/prices.json
## ("ammo", "packages", the items), the workshop's in data/ground_supports.json; every one Proposed.
##
## - Rounds are items (data/items.json "shell", "per_item", "stow_s"): a 120 mm round, a 25 mm
##   can of 50, a TOW, a smoke salvo. They live in the racks (VehicleWeapons.racks, by shell: one
##   120 mm round or TOW is one item, 50 rounds of 25 mm a can; rack_items) and the dischargers'
##   stowage (VehicleSmoke), and firing draws on them. They come aboard through the cargo point
##   (rearm): from the worker's kit, the vehicle's own hold, another vehicle's hold within 8 m
##   (the ammo truck's stand-in: the HEMTT isn't in data yet) at twice hand speed, or an ammo
##   pallet (an item holding its load) on the ground within 8 m or in the hold, at hand speed:
##   10 s a 120 mm round, 15 s a can, 30 s a TOW, 10 s a salvo, the vehicle stopped, a man on foot
##   at the cargo point (or a crewman aboard, from the hold). Each goes into the right rack (a
##   cannon's racks then its stowage; the 25 mm and the TOW into the hull's stowage, the crew fills
##   the ready boxes and the launcher from there). Rounds come out the same way (unstow: loot,
##   cross-loading). The FOB motor pool rearms to the load-out picked there, priced (MotorPool).
## - Repairs by module (2.2.2's field column, 2.9.3): what a part fixes in the field, how long
##   (with two men; alone twice as long, a wheel as today), to 60%; a job pauses while its worker
##   is under fire or the vehicle is hit, and keeps its progress on the module when he walks off.
##   ERA tiles and slat panels come back from the spares. The rest is the motor pool's
##   (MotorPool.repair_quote, per module).
## - Recovery (2.8.3's tow: no recovery vehicle in data): a vehicle of at least half the mass
##   hooks up a disabled one (60 s at its service point, both stopped) and tows it on a 3 m bar at
##   up to 15 km/h, its brakes off; home within the extraction's reach it goes back to the pool.
## - Fuel: a fuel pallet's drums pump 60 L a minute within 8 m; a tanker model (the M978) is data.
## - Packages (2.4.5): fitted at the motor pool (MotorPool.server_package), kept here (meta
##   ArmourModel.META_PACKAGES, which the armour, the HUD and the x-ray read), their weight
##   costing speed, acceleration and fuel. Their STANAG ratings are ArmourStandards' with them.
## - The extinguisher bottles (2.10.1; F-262's): counts here, refilled at the FOB.
##
## For A9 (AI crews and support, not built here): needs() says what the vehicle wants (rounds,
## salvos, field repairs, workshop jobs, fuel, recovery); rearm_sources(), repair_options(),
## tow_problem() say why not; server_start_job() runs any job for an AI worker as for a player;
## server_call_recovery() raises the flag a recovery team answers (recoveries()).
##
## Host authoritative: jobs run on the host; net_state (the vehicle's StateSync) gives every peer
## and late joiner the packages, the fired tiles, the bottles, the jobs' progress and the tow; the
## zone save and the motor pool's record keep it (to_save).

const PATH := "res://data/vehicle_logistics.json"
const NODE_NAME := &"Logistics"
## Job actions this node runs (Vehicle.server_start_job hands them over).
const ACTIONS: Array[String] = ["repair_module", "tile", "stow", "unstow", "refuel_from", "load_pallet", "tow", "unhook"]
## Rearm sources (the key a stow job is asked with).
const HANDS := "hands"
const HOLD := "hold"
const SMOKE_RACK := "smoke"
## The module names a menu shows (else the id with spaces).
const NAMES := {"track_l": "left track", "track_r": "right track", "wheel_fl": "front left wheel", "wheel_fr": "front right wheel",
	"wheel_rl": "rear left wheel", "wheel_rr": "rear right wheel", "fuel_tank_fl": "front left fuel tank", "fuel_tank_fr": "front right fuel tank",
	"fuel_tank_rear": "rear fuel tank", "fuel_tank_l": "left fuel cell", "fuel_tank_r": "right fuel cell", "ext_gun_commander": "commander's gun",
	"ext_gun_loader": "loader's gun", "ext_gun": "mounted gun", "driver_vision": "driver's periscope", "ugws": "weapon station",
	"ammo_rack_bustle": "bustle rack", "ammo_rack_hull": "hull rack", "ready_25": "ready boxes", "rack_25": "25 mm stowage", "rack_tow": "TOW rack",
	"smoke": "smoke stowage"}

## A job finished, stopped or paused (host): A9 and tests listen.
signal job_done(actor: Node, action: String, key: String, result: String)
## Host: the vehicle asked for recovery (server_call_recovery).
signal recovery_called(vehicle: Vehicle)

static var _data: Dictionary = {}
static var _round_items: Dictionary = {}  # shell id -> round item id

var vehicle: Vehicle
## Fitted package ids (the motor pool fits them).
var packages: Array = []
## The FOB load-out picked at the motor pool ("" = standard).
var loadout := ""
## Extinguisher bottles aboard: {"halon": n, "engine": n}.
var bottles: Dictionary = {}
## Work done towards each field job, seconds at two men's pace: {job key: seconds} (kept when
## the worker walks off; saved).
var progress: Dictionary = {}
## Host: worker instance id -> the job under way.
var jobs: Dictionary = {}
## Host: the vehicle towing this one (null for none), and the one this one tows.
var tow_by: Vehicle
var towing: Vehicle
## The vehicle asked for recovery (A9 / B4 answer it).
var recovery_wanted := false
## Replicated (host -> every peer): {"pk" packages, "lo" load-out, "b" bottles, "tl" fired tiles
## {group: [index...]}, "p" {job key: share done}, "j" [[worker path, action, key, share, paused]],
## "tw" the tower's vehicle id, "rc" recovery wanted}.
var net_state: Dictionary = {}:
	set(value):
		net_state = value
		if not _is_host():
			_apply_net()
var _hit_at := -INF
var _check_left := 0.0
var _mults := Vector3(1.0, 1.0, 1.0)  # speed, accel, fuel
## A6 (F-272): the tower's vehicle id from the zone save, hooked up again once every vehicle is
## back (server_rehook_saved); the tow bar drawn between the hitches on every peer.
var _saved_tow := ""
var _bar: MeshInstance3D


func _init(p_vehicle: Vehicle = null) -> void:
	name = NODE_NAME
	vehicle = p_vehicle
	if vehicle:
		bottles = full_bottles(vehicle.model)
	_refresh_mults()
	_publish()


func _ready() -> void:
	set_physics_process(_is_host())
	set_process(vehicle != null)  # A6: the tow bar's look on every peer
	if _is_host() and vehicle:
		vehicle.damaged.connect(_on_damaged)
	elif not net_state.is_empty():
		_apply_net()


func _is_host() -> bool:
	return not is_inside_tree() or multiplayer.multiplayer_peer == null or multiplayer.is_server()


## The vehicle's logistics node (or null).
static func of(v: Node) -> VehicleLogistics:
	return v.get_node_or_null(NodePath(String(NODE_NAME))) as VehicleLogistics if v else null


## Whether a model gets one (ground vehicles).
static func wanted(spec: Dictionary) -> bool:
	return String(spec.get("kind", "")) in [Vehicle.WHEELED, Vehicle.TRACKED]


# --- Data (pure) ------------------------------------------------------------------------------

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_data = parsed if parsed is Dictionary else {}
	return _data


static func num(section: String, key: String, fallback: float) -> float:
	return float((data().get(section, {}) as Dictionary).get(key, fallback))


## The data/shells.json round an item holds ("" for none: not a round item).
static func item_shell(id: StringName) -> String:
	var item := ItemDB.get_item(id) if id != &"" and ItemDB.has_item(id) else null
	return String(item.stats.get("shell", "")) if item else ""


## Rounds one item holds (a 25 mm can: 50).
static func per_item(id: StringName) -> int:
	var item := ItemDB.get_item(id) if id != &"" and ItemDB.has_item(id) else null
	return maxi(int(item.stats.get("per_item", 1)), 1) if item else 1


## Hand time to stow (or take out) one item through the cargo point.
static func stow_s(id: StringName) -> float:
	var item := ItemDB.get_item(id) if id != &"" and ItemDB.has_item(id) else null
	return float(item.stats.get("stow_s", 10.0)) if item else 10.0


static func is_salvo(id: StringName) -> bool:
	var item := ItemDB.get_item(id) if id != &"" and ItemDB.has_item(id) else null
	return item != null and bool(item.stats.get("salvo", false))


## A round or a smoke salvo: what rearms a vehicle.
static func is_ammo(id: StringName) -> bool:
	return item_shell(id) != "" or is_salvo(id)


## The item a shell comes in (&"" for none).
static func round_item(shell: String) -> StringName:
	if _round_items.is_empty():
		for id: StringName in ItemDB.all_ids():
			var s := item_shell(id)
			if s != "" and not _round_items.has(s):
				_round_items[s] = id
	return StringName(String(_round_items.get(shell, "")))


## An ammo or fuel pallet's kind (data/pallets.json), "" for any other item.
static func pallet_kind(id: StringName) -> String:
	var item := ItemDB.get_item(id) if id != &"" and ItemDB.has_item(id) else null
	return String(item.stats.get("pallet", "")) if item else ""


## What a pallet item holds now: {item id: count} (its state's "load", else its kind's full load).
static func pallet_load(id: StringName, state: Dictionary) -> Dictionary:
	if state.get("load") is Dictionary:
		var out := {}
		for k: Variant in state.load:
			if int(state.load[k]) > 0:
				out[String(k)] = int(state.load[k])
		return out
	var out2 := {}
	var kind: Dictionary = (Pallets.data().get("kinds", {}) as Dictionary).get(pallet_kind(id), {})
	for row: Array in kind.get("load", []):
		out2[String(row[0])] = int(out2.get(String(row[0]), 0)) + int(row[1])
	return out2


## Litres of fuel a pallet item holds now (0 for none).
static func pallet_fuel(id: StringName, state: Dictionary) -> float:
	var item := ItemDB.get_item(id) if id != &"" and ItemDB.has_item(id) else null
	if item == null or not item.stats.has("fuel_l"):
		return 0.0
	return maxf(float(state.get("fuel_l", item.stats.fuel_l)), 0.0)


## A ground vehicle's full extinguisher bottles (data "extinguishers").
static func full_bottles(model: String) -> Dictionary:
	var d: Dictionary = ((data().get("extinguishers", {}) as Dictionary).get("models", {}) as Dictionary).get(model, {})
	var out := {}
	for k: Variant in d:
		out[String(k)] = int(d[k])
	return out


## A module's name in words.
static func module_name(id: String) -> String:
	return String(NAMES.get(id, id.replace("_", " ")))


## The field repair rules for a module kind: [{"item", "s" (two men), "states" [WORKING...], "to", "solo_x"}].
static func repair_rules(kind: String) -> Array:
	var r: Dictionary = data().get("repair", {})
	var out: Array = []
	for row: Array in (r.get("jobs", {}) as Dictionary).get(kind, []):
		var opts: Dictionary = row[3] if row.size() > 3 and row[3] is Dictionary else {}
		var states: Array = []
		for st: Variant in row[2]:
			states.append(VehicleModules.DESTROYED if String(st) == "destroyed" else VehicleModules.DAMAGED)
		out.append({"item": StringName(String(row[0])), "s": float(row[1]), "states": states,
			"to": float(opts.get("to", r.get("field_to", 0.6))), "solo_x": float(opts.get("solo_x", r.get("solo_x", 2.0)))})
	return out


## Whether module kind `kind` is only fixed at the motor pool.
static func fob_only(kind: String) -> bool:
	return kind in ((data().get("repair", {}) as Dictionary).get("fob_only", []) as Array) or repair_rules(kind).is_empty()


## Tonnes `packages` add to a model of `spec` (each fitted package's weight_t; one included in
## another counts once, in the one that includes it).
static func added_t(spec: Dictionary, p_packages: Array) -> float:
	var defs: Dictionary = spec.get("packages", {})
	var included := {}
	for p: Variant in p_packages:
		for inc: Variant in (defs.get(String(p), {}) as Dictionary).get("includes", []):
			included[String(inc)] = true
	var t := 0.0
	for p: Variant in p_packages:
		if not included.has(String(p)):
			t += float((defs.get(String(p), {}) as Dictionary).get("weight_t", 0.0))
	return t


## 2.4.5's weight costs: {"speed" sqrt(m / (m + added)), "accel" m / (m + added), "fuel" (m + added) / m}.
static func weight_mults(spec: Dictionary, p_packages: Array) -> Dictionary:
	var m := maxf(float(spec.get("mass_kg", 1000.0)), 1.0)
	var add := added_t(spec, p_packages) * 1000.0
	return {"speed": sqrt(m / (m + add)), "accel": m / (m + add), "fuel": (m + add) / m}


## A package's price at the motor pool (data/prices.json "packages"; -1 when it isn't sold).
static func package_price(id: String) -> int:
	var p: Dictionary = Prices.data().get("packages", {})
	return int(p[id]) if p.has(id) else -1


## Days in the workshop to fit (or remove) a package.
static func package_days(id: String, fit := true) -> int:
	var p: Dictionary = data().get("packages", {})
	if not fit:
		return int(p.get("remove_days", 1))
	return int((p.get("days", {}) as Dictionary).get(id, p.get("fit_days", 2)))


## A shell's price a round (data/prices.json "ammo"; its item's price over per_item without one).
static func round_price(shell: String) -> int:
	var a: Dictionary = Prices.data().get("ammo", {})
	if a.has(shell):
		return int(a[shell])
	var item := round_item(shell)
	return roundi(float(Prices.price_of(item)) / float(per_item(item))) if item != &"" else 0


## A model's FOB load-outs (data/vehicle_logistics.json, merged as spec.logistics.loadouts).
static func loadouts(spec: Dictionary) -> Dictionary:
	return ((spec.get("logistics", {}) as Dictionary).get("loadouts", {}) as Dictionary)


## The racks a load-out fills on a vehicle of `spec` with `p_packages` fitted: {rack: {shell: n}}
## ({} for a model without racks). With the Bradley's M919 package fitted, its M791 come as M919
## (F-247: the package unlocks the round; A8 stocks it).
static func loadout_racks(spec: Dictionary, id: String, p_packages: Array) -> Dictionary:
	var all := loadouts(spec)
	var picked: Dictionary = all.get(id, all.get("standard", {}))
	if picked.is_empty():
		picked = VehicleWeapons.default_racks(spec)
	var out := {}
	var m919 := "m919" in p_packages
	for rack: Variant in picked:
		var c := {}
		for sid: Variant in picked[rack]:
			var s := "m919" if m919 and String(sid) == "m791" else String(sid)
			c[s] = int(c.get(s, 0)) + int(picked[rack][sid])
		out[String(rack)] = c
	return out


# --- Queries (every peer) --------------------------------------------------------------------

## Speed, acceleration and fuel multipliers from the packages' weight.
func speed_mult() -> float:
	return _mults.x


func accel_mult() -> float:
	return _mults.y


func fuel_mult() -> float:
	return _mults.z


func _refresh_mults() -> void:
	if vehicle == null:
		return
	var w := weight_mults(vehicle.spec, packages)
	_mults = Vector3(float(w.speed), float(w.accel), float(w.fuel))


## Whether this vehicle is being towed (every peer).
func towed() -> bool:
	return is_instance_valid(tow_by) if _is_host() else String(net_state.get("tw", "")) != ""


## Whether it tows another (host).
func towing_one() -> bool:
	return is_instance_valid(towing)


## The pair's top speed while towing or towed (m/s; INF when neither).
func tow_top() -> float:
	if towed() or towing_one():
		return num("tow", "max_kmh", 15.0) * VehicleSpecs.KMH
	return INF


## The racks rounds of `shell` go into through the cargo point, in order (a cannon's racks then
## its stowage; an autocannon's and a launcher's stowage only: the crew fills the ready boxes).
func stow_racks(shell: String) -> Array:
	var out: Array = []
	var w := vehicle.weapons if vehicle else null
	if w == null:
		return out
	for m: Dictionary in w.mounts:
		var takes := false
		match String(m.kind):
			VehicleWeapons.CANNON:
				takes = shell in (m.g.get("ammo", []) as Array)
				if takes:
					out.append_array(m.racks)
			VehicleWeapons.AUTOCANNON:
				for feed: Variant in (m.g.get("feeds", {}) as Dictionary):
					takes = takes or shell in (m.g.feeds[feed] as Array)
			VehicleWeapons.ATGM:
				takes = shell == String(m.g.get("missile", ""))
		if takes:
			for r: Variant in m.stowage:
				if not String(r) in out:
					out.append(String(r))
	return out


## The rack a whole item of `id` goes into now ("" none has room; SMOKE_RACK for a salvo).
func rack_for(id: StringName) -> String:
	if is_salvo(id):
		return SMOKE_RACK if vehicle and vehicle.smoke and vehicle.smoke.stow_room() > 0 else ""
	var shell := item_shell(id)
	if shell == "" or vehicle == null or vehicle.weapons == null:
		return ""
	for r: Variant in stow_racks(shell):
		if vehicle.weapons.rack_room(String(r)) >= per_item(id):
			return String(r)
	return ""


## Why an item of `id` can't be stowed now ("" it can).
func stow_problem(id: StringName) -> String:
	if vehicle == null or vehicle.wrecked:
		return "It's a wreck"
	if vehicle.is_burning():
		return "It's on fire"
	if not is_ammo(id):
		return "That doesn't go in a rack"
	if is_salvo(id):
		if vehicle.smoke == null:
			return "No smoke dischargers"
		if vehicle.smoke.stow_room() <= 0:
			return "The smoke stowage is full"
	elif stow_racks(item_shell(id)).is_empty():
		return "%s doesn't fire that" % vehicle.display_name()
	elif rack_for(id) == "":
		return "The racks are full"
	if vehicle.linear_velocity.length() > num("rearm", "stopped_mps", 0.5):
		return "Stop first"
	return ""


## Rack `rack` as items: [{"id", "count", "loose" (rounds short of a whole item)}].
func rack_items(rack: String) -> Array:
	var out: Array = []
	if rack == SMOKE_RACK:
		if vehicle and vehicle.smoke:
			out.append({"id": &"smoke_salvo", "count": vehicle.smoke.stowed_salvos(), "loose": 0})
		return out
	if vehicle == null or vehicle.weapons == null:
		return out
	var c := vehicle.weapons.rack_contents(rack)
	for sid: Variant in c:
		var item := round_item(String(sid))
		if item == &"":
			continue
		var per := per_item(item)
		out.append({"id": item, "count": int(c[sid]) / per, "loose": int(c[sid]) % per})
	return out


## Every round aboard by shell (racks, the breech, the TOW's launcher) and "smoke_salvo" (the
## dischargers' loaded and stowed salvos): what the FOB's bill counts.
func ammo_aboard() -> Dictionary:
	var out := {}
	var w := vehicle.weapons if vehicle else null
	if w:
		for rack: Variant in w.racks:
			for sid: Variant in w.racks[rack]:
				out[String(sid)] = int(out.get(String(sid), 0)) + int(w.racks[rack][sid])
		for m: Dictionary in w.mounts:
			var st: Dictionary = w.state.get(m.id, {})
			match String(m.kind):
				VehicleWeapons.CANNON:
					if String(st.get("l", "")) != "":
						out[String(st.l)] = int(out.get(String(st.l), 0)) + 1
				VehicleWeapons.ATGM:
					var mid := String(m.g.get("missile", ""))
					out[mid] = int(out.get(mid, 0)) + int(st.get("rd", 0))
	if vehicle and vehicle.smoke:
		out["smoke_salvo"] = vehicle.smoke.salvos_aboard()
	return out


## What it wants (A9's crews and support; every peer): {"rounds": {shell: short of the load-out},
## "salvos": n, "repairs": [{"module", "item", "s", "state"}] (field jobs it has a rule for),
## "fob": [module ids only the workshop fixes], "tiles": n fired, "fuel_l": room in the tank,
## "bottles": {kind: empty}, "recovery": bool (immobile, or asked)}.
func needs() -> Dictionary:
	var out := {"rounds": {}, "salvos": 0, "repairs": [], "fob": [], "tiles": 0, "fuel_l": 0.0, "bottles": {}, "recovery": recovery_wanted}
	if vehicle == null:
		return out
	if vehicle.weapons:
		var want := loadout_racks(vehicle.spec, loadout, packages)
		var have := ammo_aboard()
		var total := {}
		for rack: Variant in want:
			for sid: Variant in want[rack]:
				total[String(sid)] = int(total.get(String(sid), 0)) + int(want[rack][sid])
		for m: Dictionary in vehicle.weapons.mounts:
			if String(m.kind) == VehicleWeapons.ATGM:  # the launcher's ready missiles on top of the rack's
				var mid := String(m.g.get("missile", ""))
				total[mid] = int(total.get(mid, 0)) + int(m.g.get("ready_max", 2))
		for sid: String in total:
			var short := int(total[sid]) - int(have.get(sid, 0))
			if short > 0:
				out.rounds[sid] = short
	if vehicle.smoke:
		out.salvos = vehicle.smoke.stow_room()
	var mods := vehicle.modules
	if mods and mods.authored:
		for m: Dictionary in mods.mods:
			var st := VehicleModules.state_of(mods.health[int(m.i)])
			if st == VehicleModules.WORKING or float(m.hp) <= 0.0:
				continue
			var rule := _rule_for(String(m.kind), st)
			if rule.is_empty():
				(out.fob as Array).append(String(m.id))
			else:
				(out.repairs as Array).append({"module": String(m.id), "item": rule.item, "s": rule.s, "state": st})
	for g: Variant in fired_tiles():
		out.tiles = int(out.tiles) + (fired_tiles()[g] as Array).size()
	out.fuel_l = maxf(float(vehicle.spec.get("fuel_l", 0.0)) - vehicle.fuel_litres(), 0.0)
	var full := full_bottles(vehicle.model)
	for k: String in full:
		var empty := int(full[k]) - int(bottles.get(k, 0))
		if empty > 0:
			out.bottles[k] = empty
	if mods and mods.mobility_killed():
		out.recovery = true
	return out


func _rule_for(kind: String, st: int, item: StringName = &"") -> Dictionary:
	for r: Dictionary in repair_rules(kind):
		if st in (r.states as Array) and (item == &"" or StringName(r.item) == item):
			return r
	return {}


## The ERA tiles fired and slat torn off: {group: [tile index, ...]} (every peer).
func fired_tiles() -> Dictionary:
	var used: Dictionary = vehicle.get_meta(ArmourModel.META_TILES, {}) if vehicle else {}
	var out := {}
	for g: Variant in used:
		var flags: PackedByteArray = used[g]
		var list: Array = []
		for i in flags.size():
			if flags[i] != 0:
				list.append(i)
		if not list.is_empty():
			out[String(g)] = list
	return out


## The tile kind of group `group` ("" for none).
func tile_kind(group: String) -> String:
	for t: Dictionary in vehicle.spec.get("tiles", []):
		if String(t.group) == group:
			return String(t.kind)
	return ""


## The spare that replaces a tile of `kind` (era_tile or slat_panel; &"" none).
static func tile_spare(kind: String) -> StringName:
	var tiles: Dictionary = (data().get("repair", {}) as Dictionary).get("tiles", {})
	for spare: Variant in tiles:
		if kind in ((tiles[spare] as Dictionary).get("kinds", []) as Array):
			return StringName(String(spare))
	return &""


## Whether `actor` has part `item` on him or the vehicle has it in its hold (spares are carried
## there: 2.9.3).
func has_part(actor: Soldier, item: StringName) -> bool:
	if actor and VehicleService.has_part(actor, item):
		return true
	return vehicle.cargo_hold != null and vehicle.cargo_hold.count_of(item) > 0


## The field repairs `actor` could start on this vehicle now: [{"module", "kind", "item", "s"
## (his time, alone or with a helper), "why" ("" can), "label"}], the modules that need work.
## Workshop-only damage comes as one entry each with its why.
func repair_options(actor: Soldier) -> Array:
	var out: Array = []
	var mods := vehicle.modules
	if mods == null or not mods.authored:
		return out
	for m: Dictionary in mods.mods:
		var h := mods.health[int(m.i)]
		var st := VehicleModules.state_of(h)
		if st == VehicleModules.WORKING or float(m.hp) <= 0.0 or String(m.kind) in ["crew", "compartment", "structure", "stowage"]:
			continue  # (the hull and its compartments are the workshop's: its quote lists them)
		var rules: Array = []
		for r: Dictionary in repair_rules(String(m.kind)):
			if st in (r.states as Array):
				rules.append(r)
		if rules.is_empty():
			out.append({"module": String(m.id), "kind": String(m.kind), "item": &"", "s": 0.0, "label": "%s: motor pool only" % module_name(String(m.id)).capitalize(),
				"why": "%s %s: only the motor pool fixes that" % [module_name(String(m.id)).capitalize(), "destroyed" if st == VehicleModules.DESTROYED else "damaged"]})
			continue
		for r: Dictionary in rules:
			var item: StringName = r.item
			if actor and not has_part(actor, item):
				continue
			var why := repair_problem(actor, String(m.id), item)
			out.append({"module": String(m.id), "kind": String(m.kind), "item": item, "s": job_seconds(actor, "m:" + String(m.id), float(r.s), float(r.solo_x)),
				"label": "%s: %s" % [ItemDB.get_item(item).name, module_name(String(m.id))], "why": why})
	return out


## "" if `actor` can start the field repair of module `module_id` with `item` now, else why.
func repair_problem(actor: Soldier, module_id: String, item: StringName) -> String:
	if vehicle.wrecked:
		return "It's a wreck"
	if vehicle.is_burning():
		return "It's on fire"
	var mods := vehicle.modules
	var i := mods.index_of(module_id) if mods else -1
	if i < 0:
		return "No such part"
	var m: Dictionary = mods.mods[i]
	var st := VehicleModules.state_of(mods.health[i])
	if st == VehicleModules.WORKING:
		return "The %s works" % module_name(module_id)
	var rule := _rule_for(String(m.kind), st, item)
	if rule.is_empty():
		var fits := repair_rules(String(m.kind)).any(func(r: Dictionary) -> bool: return StringName(r.item) == item)
		if fob_only(String(m.kind)) or fits:
			return "Only the motor pool fixes a %s %s" % ["destroyed" if st == VehicleModules.DESTROYED else "damaged", module_name(module_id)]
		return "%s can't fix the %s" % [ItemDB.get_item(item).name if ItemDB.has_item(item) else String(item), module_name(module_id)]
	if not has_part(actor, item):
		return "You have no %s" % ItemDB.get_item(item).name
	return ""


## Seconds `actor` would take on job `key` of `base_s` (two men's), from what's done already:
## alone x solo_x, with a helper as given.
func job_seconds(actor: Soldier, key: String, base_s: float, solo_x: float) -> float:
	var left := maxf(base_s - float(progress.get(key, 0.0)), 0.0)
	return left * (1.0 if actor and _helpers(actor) > 0 else solo_x)


## Able men of `actor`'s side on foot within helper_m of him, not counting him (two men make the
## doc's times: 2.9.3).
func _helpers(actor: Soldier) -> int:
	var n := 0
	var reach := num("repair", "helper_m", 3.0)
	if actor == null or not actor.is_inside_tree():
		return 0
	for c in actor.get_tree().get_nodes_in_group(&"combatants"):
		var s := c as Soldier
		if s == null or s == actor or not s.vitals.is_up() or s.faction != actor.faction:
			continue
		if Vehicle.ride_of(s) == null and s.global_position.distance_to(actor.global_position) <= reach:
			n += 1
	return n


## Where rounds can come from for this vehicle, for `actor` at its cargo point: [{"key" (the
## stow job's), "kind" ("hands", "hold", "carrier", "pallet"), "label", "items" {id: count} (what
## of it this vehicle takes), "mult" (x hand speed)}].
func rearm_sources(actor: Soldier) -> Array:
	var out: Array = []
	if vehicle == null or (vehicle.weapons == null and vehicle.smoke == null):
		return out
	if actor:
		var mine := _usable(_inventory_items(actor.inventory))
		if not mine.is_empty():
			out.append({"key": HANDS, "kind": HANDS, "label": "From your kit", "items": mine, "mult": 1.0})
	if vehicle.cargo_hold:
		var held := _usable(_hold_items(vehicle.cargo_hold))
		if not held.is_empty():
			out.append({"key": HOLD, "kind": HOLD, "label": "From the hold", "items": held, "mult": num("rearm", "pallet_mult", 1.0)})
	for v: Vehicle in _carriers():
		var got := _usable(_hold_items(v.cargo_hold))
		if not got.is_empty():
			out.append({"key": "v:" + v.vehicle_id, "kind": "carrier", "label": "From the %s" % v.display_name(), "items": got,
				"mult": num("rearm", "carrier_mult", 2.0)})
	for wi: WorldItem in _pallets_near(num("rearm", "pallet_reach_m", 8.0)):
		var load := _usable(pallet_load(wi.item_id, wi.state))
		if not load.is_empty():
			out.append({"key": "w:" + wi.uid, "kind": "pallet", "label": "From the %s" % ItemDB.get_item(wi.item_id).name.to_lower(), "items": load,
				"mult": num("rearm", "pallet_mult", 1.0)})
	return out


## Of {item id: count}, the round items this vehicle can take at all.
func _usable(items: Dictionary) -> Dictionary:
	var out := {}
	for id: Variant in items:
		var sid := StringName(String(id))
		if not is_ammo(sid):
			continue
		if is_salvo(sid) and vehicle.smoke == null:
			continue
		if not is_salvo(sid) and stow_racks(item_shell(sid)).is_empty():
			continue
		out[String(id)] = int(items[id])
	return out


## {item id: count} on a soldier (his hands and every container).
static func _inventory_items(inv: Inventory) -> Dictionary:
	var out := {}
	if inv.hands != &"":
		out[String(inv.hands)] = 1
	for c: StringName in inv.search_containers():
		for e: Dictionary in inv.containers.get(c, []):
			out[String(e.id)] = int(out.get(String(e.id), 0)) + int(e.count)
	return out


## {item id: count} in a hold: loose items, and what the ammo pallets in it hold.
static func _hold_items(hold: VehicleCargo) -> Dictionary:
	var out := {}
	if hold == null:
		return out
	for e: Dictionary in hold.entries():
		if pallet_kind(e.id) != "":
			var load := pallet_load(e.id, e.get("state", {}))
			for k: String in load:
				out[k] = int(out.get(k, 0)) + int(load[k]) * int(e.count)
		else:
			out[String(e.id)] = int(out.get(String(e.id), 0)) + int(e.count)
	return out


## Other vehicles within carrier_reach_m with a hold (not wrecked): the ammo trucks' stand-ins.
func _carriers() -> Array:
	var out: Array = []
	if vehicle == null or not vehicle.is_inside_tree():
		return out
	var reach := num("rearm", "carrier_reach_m", 8.0)
	for n in vehicle.get_tree().get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if v == null or v == vehicle or v.wrecked or v.cargo_hold == null or v.is_queued_for_deletion():
			continue
		if v.faction == &"hostile" and not v.occupants().is_empty():
			continue  # (an enemy's crewed truck is no supply point)
		if _gap(v) <= reach:
			out.append(v)
	return out


## The flat gap between this vehicle's hull box and another's (m).
func _gap(other: Vehicle) -> float:
	var a := _footprint(vehicle)
	var b := _footprint(other)
	return maxf(a.global_position.distance_to(b.global_position) - a.radius - b.radius, 0.0)


static func _footprint(v: Vehicle) -> Dictionary:
	var size := VehicleArt.size_m(v.model) if VehicleArt.MODELS.has(v.model) else Vector3(2, 2, 4)
	return {"global_position": v.global_position, "radius": minf(size.x, size.z) * 0.5}


## Ammo and fuel pallets lying within `reach` of the vehicle.
func _pallets_near(reach: float) -> Array:
	var out: Array = []
	if vehicle == null or not vehicle.is_inside_tree():
		return out
	var r := _footprint(vehicle).radius as float
	for n in vehicle.get_tree().get_nodes_in_group(WorldItem.GROUP):
		var wi := n as WorldItem
		if wi == null or wi.is_queued_for_deletion() or pallet_kind(wi.item_id) == "":
			continue
		if Vector2(wi.global_position.x - vehicle.global_position.x, wi.global_position.z - vehicle.global_position.z).length() <= reach + r:
			out.append(wi)
	return out


## Fuel sources for this vehicle: [{"key", "label", "litres", "lpm"}] (fuel pallets on the ground
## within reach, in its own hold or a truck's within reach; tanker models).
func fuel_sources() -> Array:
	var out: Array = []
	if vehicle == null:
		return out
	var reach := num("fuel", "reach_m", 8.0)
	for wi: WorldItem in _pallets_near(reach):
		var l := pallet_fuel(wi.item_id, wi.state)
		if l > 0.0:
			out.append({"key": "w:" + wi.uid, "label": ItemDB.get_item(wi.item_id).name, "litres": l, "lpm": _lpm(wi.item_id)})
	var holds: Array = [vehicle] + _carriers()
	for v: Vehicle in holds:
		if v.cargo_hold == null:
			continue
		var l := 0.0
		var lpm := 0.0
		for e: Dictionary in v.cargo_hold.entries():
			var f := pallet_fuel(e.id, e.get("state", {})) * int(e.count)
			if f > 0.0:
				l += f
				lpm = maxf(lpm, _lpm(e.id))
		if l > 0.0:
			out.append({"key": HOLD if v == vehicle else "v:" + v.vehicle_id, "label": "Fuel in the %s" % ("hold" if v == vehicle else v.display_name()),
				"litres": l, "lpm": lpm})
	var tankers: Dictionary = (data().get("fuel", {}) as Dictionary).get("tankers", {})
	for v: Vehicle in _carriers():
		if tankers.has(v.model):
			out.append({"key": "t:" + v.vehicle_id, "label": "The %s's hose" % v.display_name(), "litres": v.fuel_litres(),
				"lpm": float((tankers[v.model] as Dictionary).get("lpm", 300.0))})
	return out


static func _lpm(id: StringName) -> float:
	var item := ItemDB.get_item(id)
	return float(item.stats.get("pump_lpm", 60.0)) if item else 60.0


## Why `tower` can't tow this vehicle now ("" it can).
func tow_problem(tower: Vehicle) -> String:
	if tower == null or not is_instance_valid(tower) or tower == vehicle:
		return "Nothing to tow with"
	if vehicle.wrecked:
		return "It's a burnt-out wreck"
	if vehicle.is_burning() or tower.is_burning():
		return "It's on fire"
	if tower.wrecked or not tower.can_drive():
		return "The %s can't drive" % tower.display_name()
	if not VehicleLogistics.wanted(tower.spec) or VehicleLogistics.of(tower) == null:
		return "That can't tow"
	if towed():
		return "Already under tow"
	var lt := VehicleLogistics.of(tower)
	if lt.towed() or lt.towing_one():
		return "The %s is already towing" % tower.display_name()
	var share := num("tow", "min_mass_share", 0.5)
	var mine := float(vehicle.spec.get("mass_kg", 0.0)) + added_t(vehicle.spec, packages) * 1000.0
	var theirs := float(tower.spec.get("mass_kg", 0.0))
	if theirs < mine * share:
		return "The %s is too light to tow a %s (%.0f t, needs %.0f t)" % [tower.display_name(), vehicle.display_name(), theirs / 1000.0, mine * share / 1000.0]
	var stopped := num("rearm", "stopped_mps", 0.5)
	if vehicle.linear_velocity.length() > stopped or tower.linear_velocity.length() > stopped:
		return "Both stopped first"
	if _hitch_gap(tower) > num("tow", "hook_m", 8.0):
		return "Back the %s up to it (%.0f m)" % [tower.display_name(), _hitch_gap(tower)]
	return ""


## Vehicles near enough to tow this one, best first (A9; the menu).
func tow_candidates() -> Array:
	var out: Array = []
	if vehicle == null or not vehicle.is_inside_tree():
		return out
	for n in vehicle.get_tree().get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if v and v != vehicle and VehicleLogistics.of(v) != null and not v.wrecked and _hitch_gap(v) <= num("tow", "hook_m", 8.0) * 2.0:
			out.append(v)
	out.sort_custom(func(a: Vehicle, b: Vehicle) -> bool: return _hitch_gap(a) < _hitch_gap(b))
	return out


## This vehicle's tow hitch, front (false) or rear (true), in its own frame.
static func hitch(v: Vehicle, rear: bool) -> Vector3:
	var z0 := INF
	var z1 := -INF
	var y0 := INF
	for b: Array in v.spec.get("boxes", []):
		z0 = minf(z0, float(b[2]))
		z1 = maxf(z1, float(b[5]))
		y0 = minf(y0, float(b[1]))
	if z0 == INF:
		return Vector3(0, 0.6, 2.0 if rear else -2.0)
	return Vector3(0.0, y0 + 0.5, z1 if rear else z0)


## The gap between `tower`'s rear hitch and this vehicle's front one (or rear: whichever is nearer).
func _hitch_gap(tower: Vehicle) -> float:
	var a := tower.to_global(hitch(tower, true))
	return minf(a.distance_to(vehicle.to_global(hitch(vehicle, false))), a.distance_to(vehicle.to_global(hitch(vehicle, true))))


## Vehicles in `from`'s tree that asked for recovery (A9 / B4's recovery teams).
static func recoveries(from: Node) -> Array:
	var out: Array = []
	if from == null or not from.is_inside_tree():
		return out
	for n in from.get_tree().get_nodes_in_group(Vehicle.GROUP):
		var l := VehicleLogistics.of(n)
		if l and l.recovery_wanted and not (n as Vehicle).wrecked:
			out.append(n)
	return out


## The job `actor` is on ({} none; host).
func job_of(actor: Node) -> Dictionary:
	return jobs.get(actor.get_instance_id(), {}) if actor else {}


## Seconds left on `actor`'s job at its current pace (0 none).
func job_left(actor: Node) -> float:
	var job := job_of(actor)
	if job.is_empty():
		return 0.0
	if float(job.need) == INF:  # refuelling: the tank's room at the pump's rate
		return maxf(float(vehicle.spec.get("fuel_l", 0.0)) - vehicle.fuel_litres(), 0.0) / maxf(float(job.get("lpm", 60.0)) / 60.0, 0.01)
	return maxf(float(job.need) - float(job.done), 0.0) / maxf(float(job.get("rate", 1.0)), 0.01)


## The HUD's lines: work under way, a tow (every peer).
func readout_parts(_seat: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for j: Array in net_state.get("j", []):
		out.append({"text": "%s %d%%%s" % [String(j[1]), roundi(float(j[3]) * 100.0), " (paused)" if bool(j[4]) else ""], "style": &"warn" if bool(j[4]) else &""})
	if towed():
		out.append({"text": "UNDER TOW", "style": &"warn"})
	return out


# --- Host: jobs --------------------------------------------------------------------------------

## Host: starts `action` for `actor` (Vehicle.server_start_job hands these over). `key`: the module
## (repair_module), tile group (tile), source (stow, refuel_from: "hands", "hold", "v:<vehicle id>",
## "w:<world item uid>", "t:<tanker id>"), rack (unstow), world item uid (load_pallet), tower's
## vehicle id (tow). `item`: the part, the round (unstow; stow: "" for anything). Returns "" or why.
func server_start_job(actor: Soldier, action: String, key: String, item: StringName) -> String:
	if not _is_host() or actor == null or not actor.vitals.is_up():
		return "Not now"
	if jobs.has(actor.get_instance_id()):
		return "Already working on it"
	var job := {"actor": actor, "action": action, "key": key, "item": item, "done": 0.0, "need": 0.0, "rate": 1.0, "paused": "",
		"at": actor.global_position, "vehicle_at": vehicle.global_position, "inside": vehicle.seat_of(actor) >= 0, "count": 0}
	var label := ""
	match action:
		"repair_module":
			var why := repair_problem(actor, key, item)
			if why != "":
				return why
			var m: Dictionary = vehicle.modules.mods[vehicle.modules.index_of(key)]
			var rule := _rule_for(String(m.kind), vehicle.modules.state(key), item)
			job.pkey = "m:" + key
			job.need = float(rule.s)
			job.done = float(progress.get(job.pkey, 0.0))
			job.solo_x = float(rule.solo_x)
			job.to = float(rule.to)
			label = "%s: %s" % [ItemDB.get_item(item).name, module_name(key)]
		"tile":
			var why := _tile_problem(actor, key, item)
			if why != "":
				return why
			job.pkey = "t:" + key
			job.need = float((((data().get("repair", {}) as Dictionary).get("tiles", {}) as Dictionary).get(String(item), {}) as Dictionary).get("s", 40.0))
			job.done = float(progress.get(job.pkey, 0.0))
			job.solo_x = num("repair", "solo_x", 2.0)
			label = "%s on the %s" % [ItemDB.get_item(item).name, key.replace("_", " ")]
		"stow":
			var src := _source(actor, key)
			if src.is_empty():
				return "Nothing there to rearm from"
			var next := _next_round(actor, key, item)
			if next == &"":
				var any := _usable(src.items)
				if any.is_empty():
					return "Nothing there this vehicle takes"
				return stow_problem(StringName(String(any.keys()[0])))
			var why := stow_problem(next)
			if why != "":
				return why
			job.mult = float(src.mult)
			job.cur = next
			job.need = stow_s(next) / maxf(float(src.mult), 0.01)
			label = "Rearming %s" % String(src.label).to_lower()
		"unstow":
			var why := _unstow_problem(key, item)
			if why != "":
				return why
			job.need = stow_s(item)
			label = "Taking out %s" % ItemDB.get_item(item).name
		"refuel_from":
			var src := _fuel_source(key)
			if src.is_empty():
				return "No fuel there"
			if vehicle.fuel_litres() >= float(vehicle.spec.get("fuel_l", 0.0)) - 0.5:
				return "The tank is full"
			job.lpm = float(src.lpm)
			job.need = INF
			label = "Refuelling from %s" % String(src.label).to_lower()
		"load_pallet":
			return _load_pallet(actor, String(item) if String(item) != "" else key)
		"tow":
			var tower := _find(key)
			var why := tow_problem(tower)
			if why != "":
				return why
			if vehicle.seat_of(actor) >= 0:
				return "Get out to hook up the tow"
			job.need = num("tow", "hook_s", 60.0)
			job.solo_x = 1.0
			label = "Hooking up to the %s" % tower.display_name()
		"unhook":
			if not towed() and not towing_one():
				return "Nothing hooked up"
			server_unhook()
			return ""
		_:
			return "Can't do that here"
	job.label = label
	jobs[actor.get_instance_id()] = job
	_rate(job)
	_busy(job)
	_publish()
	return ""


## Host: the jobs, a step at a time (check_s), and the tow's bar every physics step.
func _physics_process(delta: float) -> void:
	if is_instance_valid(tow_by):
		_tow_step(delta)
	elif tow_by != null:
		server_unhook()
	if not jobs.is_empty():
		_stop_step()
	_check_left -= delta
	if _check_left > 0.0:
		return
	var dt := num("rearm", "check_s", 0.25) - _check_left
	_check_left = num("rearm", "check_s", 0.25)
	if not jobs.is_empty():
		_job_step(dt)
	if _tiles_dirty():
		_publish()


## Every physics step (as Vehicle's own jobs): a worker who walks off, goes down or gets out, or a
## vehicle that moves, stops his job at once (its progress kept).
func _stop_step() -> void:
	for id: int in jobs.keys():
		var job: Dictionary = jobs[id]
		var why := _stop_reason(job, job.actor as Soldier if is_instance_valid(job.actor) else null)
		if why != "":
			_end(id, why)


func _job_step(dt: float) -> void:
	var changed := false
	for id: int in jobs.keys():
		var job: Dictionary = jobs[id]
		var actor: Soldier = job.actor if is_instance_valid(job.actor) else null
		var why := _stop_reason(job, actor)
		if why != "":
			_end(id, why)
			changed = true
			continue
		var paused := _pause_reason(job, actor)
		if paused != String(job.paused):
			job.paused = paused
			changed = true
			if paused != "":
				vehicle._tell(actor, "Paused: %s" % paused)
				if not actor.is_ai():
					actor._client_busy.rpc_id(actor.owner_peer(), 0.0, "")
			else:
				_busy(job)
		if paused != "":
			continue
		var rate := _rate(job)
		match String(job.action):
			"refuel_from":
				if _refuel_tick(job, dt):
					changed = true
					continue
			_:
				job.done = float(job.done) + dt * rate
				if job.has("pkey"):
					progress[job.pkey] = minf(float(job.done), float(job.need))
				if float(job.done) >= float(job.need):
					changed = true
					if not _complete(id, job):
						continue
		changed = true
	if changed:
		_publish()


## Why job `job` stops now ("" it goes on).
func _stop_reason(job: Dictionary, actor: Soldier) -> String:
	if actor == null or not actor.vitals.is_up():
		return "down"
	if vehicle.wrecked:
		return "it's a wreck"
	if String(job.action) != "tow" and vehicle.is_burning():
		return "it's on fire"
	var move := num("repair", "job_move_m", 1.5)
	if vehicle.global_position.distance_to(job.vehicle_at) > move:
		return "it moved away"
	if bool(job.inside):
		if vehicle.seat_of(actor) < 0:
			return "you got out"
	elif actor.global_position.distance_to(job.at) > move or Vehicle.ride_of(actor) != null or not vehicle.in_reach(actor):
		return "you walked off"
	return ""


## Why job `job` waits now ("" it runs): its worker under fire, the vehicle hit lately.
func _pause_reason(job: Dictionary, actor: Soldier) -> String:
	var now := Soldier._now()
	if actor.suppression > num("repair", "suppressed", 0.3) or now - actor.threat_time < num("repair", "threat_pause_s", 2.0):
		return "under fire"
	if now - _hit_at < num("repair", "hit_pause_s", 5.0):
		return "the vehicle is taking hits"
	if String(job.action) in ["stow", "unstow", "refuel_from", "tow"] and vehicle.linear_velocity.length() > num("rearm", "stopped_mps", 0.5):
		return "stop first"
	return ""


## The job's pace (1: the doc's time; a lone man on a two-man job 1 / solo_x).
func _rate(job: Dictionary) -> float:
	var r := 1.0
	if job.has("solo_x") and _helpers(job.actor as Soldier) <= 0:
		r = 1.0 / maxf(float(job.solo_x), 1.0)
	job.rate = r
	return r


func _busy(job: Dictionary) -> void:
	var actor := job.actor as Soldier
	if actor == null or actor.is_ai() or String(job.action) == "refuel_from":
		return
	var left := maxf(float(job.need) - float(job.done), 0.0) / maxf(float(job.rate), 0.01)
	actor._client_busy.rpc_id(actor.owner_peer(), left, "%s (%.0f s)" % [String(job.get("label", "")), left])


## A job's step is done: its effect. Returns whether the job is over (false: the next round).
func _complete(id: int, job: Dictionary) -> bool:
	var actor: Soldier = job.actor
	match String(job.action):
		"repair_module":
			var key := String(job.key)
			var why := repair_problem(actor, key, job.item)
			if why != "" or not _use_part(actor, job.item):
				_end(id, why if why != "" else "no %s" % ItemDB.get_item(job.item).name)
				return true
			vehicle.modules.server_set(key, maxf(vehicle.modules.health_of(key), float(job.to)))
			if String(vehicle.modules.mods[vehicle.modules.index_of(key)].kind) == "fuel_tank":
				vehicle.server_stop_leak()
			progress.erase(job.pkey)
			_end(id, "", "%s repaired (%d%%)" % [module_name(key).capitalize(), roundi(vehicle.modules.health_of(key) * 100.0)])
		"tile":
			var why := _tile_problem(actor, String(job.key), job.item)
			if why != "" or not _use_part(actor, job.item):
				_end(id, why if why != "" else "no spare")
				return true
			server_replace_tile(String(job.key))
			progress.erase(job.pkey)
			_end(id, "", "%s replaced on the %s" % [ItemDB.get_item(job.item).name, String(job.key).replace("_", " ")])
		"stow":
			var cur: StringName = job.cur
			if stow_problem(cur) != "" or not _take_from_source(actor, String(job.key), cur):
				return _next_or_end(id, job)
			server_stow_item(cur)
			job.count = int(job.count) + 1
			return _next_or_end(id, job)
		"unstow":
			var why := _unstow_problem(String(job.key), job.item)
			if why != "":
				_end(id, why)
				return true
			server_unstow_item(String(job.key), job.item, actor)
			_end(id, "", "Took out %s" % ItemDB.get_item(job.item).name)
		"tow":
			var tower := _find(String(job.key))
			var why := tow_problem(tower)
			if why != "":
				_end(id, why)
				return true
			server_hook(tower)
			if vehicle.drive and vehicle.drive.is_rolled():
				vehicle.drive.server_start_righting(tower)  # A6 (2.8.3): the tow rights a rolled vehicle
				_end(id, "", "Hooked up: the %s pulls the %s back onto its wheels" % [tower.display_name(), vehicle.display_name()])
			else:
				_end(id, "", "Hooked up: the %s tows the %s" % [tower.display_name(), vehicle.display_name()])
	return true


## After a stowed round: the next one from the same source, or the job ends with what went in.
func _next_or_end(id: int, job: Dictionary) -> bool:
	var actor: Soldier = job.actor
	var next := _next_round(actor, String(job.key), job.item)
	if next == &"" or stow_problem(next) != "":
		var said := "Rearmed: %d stowed" % int(job.count) if int(job.count) > 0 else "Nothing stowed"
		var why := stow_problem(next) if next != &"" else ""
		_end(id, "", said + (" (%s)" % why.to_lower() if why != "" else ""))
		return true
	job.cur = next
	job.done = 0.0
	job.need = stow_s(next) / maxf(float(job.get("mult", 1.0)), 0.01)
	_busy(job)
	return false


func _end(id: int, why: String, said := "") -> void:
	var job: Dictionary = jobs.get(id, {})
	jobs.erase(id)
	var actor: Soldier = job.get("actor") if is_instance_valid(job.get("actor")) else null
	var text := said if said != "" else ("Stopped work on the %s: %s" % [vehicle.display_name(), why] if why != "" else "")
	if actor:
		vehicle._tell(actor, text)
		if why != "" and not actor.is_ai():
			actor._client_busy.rpc_id(actor.owner_peer(), 0.0, text)
	job_done.emit(actor, String(job.get("action", "")), String(job.get("key", "")), text)
	_publish()


## Host: every job on this vehicle stops (it burned, left, a test).
func server_stop_jobs(why := "stopped") -> void:
	for id: int in jobs.keys():
		_end(id, why)


func _use_part(actor: Soldier, item: StringName) -> bool:
	if actor and VehicleService.has_part(actor, item):
		return VehicleService._use_part(actor, item)
	return vehicle.cargo_hold != null and vehicle.cargo_hold.remove_one(item)


# --- Host: stowing -----------------------------------------------------------------------------

## Host: one item's rounds into its rack (or a salvo into the stowage), at once (a finished stow
## job; the FOB; tests). Returns whether it went in.
func server_stow_item(id: StringName) -> bool:
	if is_salvo(id):
		return vehicle.smoke != null and vehicle.smoke.server_stow_salvos(1) > 0
	var rack := rack_for(id)
	if rack == "":
		return false
	return vehicle.weapons.server_stow(rack, item_shell(id), per_item(id)) == per_item(id)


## Host: one item's rounds out of rack `rack` to `actor` (his kit, his hands, else on the ground by
## the cargo point). Returns whether it came out.
func server_unstow_item(rack: String, id: StringName, actor: Soldier) -> bool:
	if rack == SMOKE_RACK:
		if vehicle.smoke == null or not vehicle.smoke.server_take_salvo():
			return false
	elif vehicle.weapons == null or vehicle.weapons.server_take_rounds(rack, item_shell(id), per_item(id)) < per_item(id):
		return false
	if actor == null or actor.inventory.take(id, 1) <= 0:
		var lvl := vehicle.level()
		if lvl:
			lvl.server_spawn_dropped(id, 1, vehicle._cargo_point() + Vector3.UP * 0.3)
	return true


func _unstow_problem(rack: String, id: StringName) -> String:
	if vehicle.wrecked:
		return "It's a wreck"
	if vehicle.linear_velocity.length() > num("rearm", "stopped_mps", 0.5):
		return "Stop first"
	for e: Dictionary in rack_items(rack):
		if StringName(e.id) == id and int(e.count) > 0:
			return ""
	return "None of those in the %s" % module_name(rack)


## The source behind a stow key: {"label", "items", "mult"} ({} gone).
func _source(actor: Soldier, key: String) -> Dictionary:
	for s: Dictionary in rearm_sources(actor):
		if String(s.key) == key:
			return s
	return {}


## The next round to stow from source `key` (only `want` if given): the one the vehicle is
## shortest of against its load-out, else any that fits. &"" none.
func _next_round(actor: Soldier, key: String, want: StringName) -> StringName:
	var src := _source(actor, key)
	if src.is_empty():
		return &""
	var items: Dictionary = src.items
	var short: Dictionary = needs().rounds
	var best := &""
	var gap := -INF
	for id: Variant in items:
		var sid := StringName(String(id))
		if (want != &"" and sid != want) or int(items[id]) <= 0 or stow_problem(sid) != "":
			continue
		var g := float(short.get(item_shell(sid), 0)) / float(per_item(sid)) if not is_salvo(sid) else float(vehicle.smoke.stow_room())
		if g > gap:
			gap = g
			best = sid
	return best


## Host: one `id` out of source `key` (the worker's kit, a hold, a pallet). Whether it was there.
func _take_from_source(actor: Soldier, key: String, id: StringName) -> bool:
	if key == HANDS:
		if actor.inventory.hands == id:
			actor.inventory.release_hands()
			return true
		return actor.inventory.remove_one(id)
	if key == HOLD:
		return _take_from_hold(vehicle.cargo_hold, id)
	if key.begins_with("v:"):
		var v := _find(key.trim_prefix("v:"))
		return v != null and v in _carriers() and _take_from_hold(v.cargo_hold, id)
	if key.begins_with("w:"):
		var wi := _world_item(key.trim_prefix("w:"))
		if wi == null:
			return false
		var load := pallet_load(wi.item_id, wi.state)
		if int(load.get(String(id), 0)) <= 0:
			return false
		load[String(id)] = int(load[String(id)]) - 1
		_set_world_state(wi, _with_load(wi.state, load))
		return true
	return false


## One `id` from a hold: a loose one first, else out of an ammo pallet in it.
static func _take_from_hold(hold: VehicleCargo, id: StringName) -> bool:
	if hold == null:
		return false
	if hold.remove_one(id):
		return true
	var list := hold.entries()
	for i in list.size():
		var e: Dictionary = list[i]
		if pallet_kind(e.id) == "":
			continue
		var load := pallet_load(e.id, e.get("state", {}))
		if int(load.get(String(id), 0)) <= 0:
			continue
		load[String(id)] = int(load[String(id)]) - 1
		var one := hold.remove_entry(VehicleCargo.HOLD, i, 1)
		hold.take(one.id, 1, _with_load(one.get("state", {}), load))
		return true
	return false


static func _with_load(state: Dictionary, load: Dictionary) -> Dictionary:
	var next := state.duplicate(true)
	next["load"] = load
	return next


func _world_item(uid: String) -> WorldItem:
	for wi: WorldItem in _pallets_near(maxf(num("rearm", "pallet_reach_m", 8.0), num("fuel", "reach_m", 8.0)) + 2.0):
		if wi.uid == uid:
			return wi
	return null


## Host: a world item's new state, replicated and saved (as WorldItem.server_add_armor_hit does).
static func _set_world_state(wi: WorldItem, state: Dictionary) -> void:
	wi.state = state
	if wi.uid == "":
		return
	if not GameState.dropped.has(wi.uid):
		GameState.item_taken(wi.uid)
		GameState.item_dropped(wi.uid, wi.item_id, wi.count, wi.global_position, state.duplicate(true))
	else:
		GameState.dropped[wi.uid]["state"] = state.duplicate(true)


func _find(id: String) -> Vehicle:
	var layer := vehicle.get_parent() as VehicleLayer if vehicle else null
	return layer.find(id) if layer else null


## Host: a pallet lying within reach of the cargo point goes into the hold. Returns what to say.
func _load_pallet(actor: Soldier, uid: String) -> String:
	if vehicle.cargo_hold == null or vehicle.wrecked:
		return "No hold to load it into"
	var wi: WorldItem = null
	for w: WorldItem in _pallets_near(6.0):
		if w.uid == uid:
			wi = w
	if wi == null:
		return "That pallet isn't near enough"
	var item := ItemDB.get_item(wi.item_id)
	if vehicle.cargo_hold.room_for(VehicleCargo.HOLD, item, wi.state) <= 0:
		return "No room in the %s for the %s" % [vehicle.display_name(), item.name.to_lower()]
	vehicle.cargo_hold.take(wi.item_id, 1, wi.state.duplicate(true))
	GameState.item_taken(wi.uid)
	wi.queue_free()
	vehicle._tell(actor, "Loaded the %s" % item.name.to_lower())
	return ""


## Host (the helicopter's resupply; tests): an ammo pallet of `id` holding `load` ({item: n}; {}:
## its full load) set down at `at`. Its uid.
static func server_drop_pallet(level: Node, id: StringName, at: Vector3, load := {}) -> String:
	if level == null or not level.has_method(&"server_spawn_dropped"):
		return ""
	return String(level.call(&"server_spawn_dropped", id, 1, at, {} if load.is_empty() else {"load": load.duplicate()}))


## The helicopter resupply's armour load (2.9.2: 8 x 120 mm or 300 x 25 mm or 2 TOW) for the
## company's armour in `level`: [{"id" (pallet item), "load"}], one per vehicle that's short, the
## calibre it's shortest of.
static func heli_armour_load(level: Node) -> Array:
	var out: Array = []
	if level == null or not level.is_inside_tree():
		return out
	var amounts: Dictionary = (data().get("rearm", {}) as Dictionary).get("heli_load", {})
	for n in level.get_tree().get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		var l := VehicleLogistics.of(v)
		if v == null or l == null or v.wrecked or v.faction != &"player" or v.weapons == null or not level.is_ancestor_of(v):
			continue
		var short: Dictionary = l.needs().rounds
		if short.is_empty():
			continue
		var want := l.loadout_racks(v.spec, l.loadout, l.packages)
		var share := {}  # calibre -> [short, total, {shell: wanted}]
		for rack: Variant in want:
			for sid: Variant in want[rack]:
				var cal := _calibre(String(sid))
				var row: Array = share.get(cal, [0, 0, {}])
				row[1] = int(row[1]) + int(want[rack][sid])
				row[2][String(sid)] = int((row[2] as Dictionary).get(String(sid), 0)) + int(want[rack][sid])
				share[cal] = row
		for sid: String in short:
			var cal := _calibre(sid)
			if share.has(cal):
				share[cal][0] = int(share[cal][0]) + int(short[sid])
		var pick := ""
		var worst := 0.0
		for cal: String in share:
			var frac := float(share[cal][0]) / maxf(float(share[cal][1]), 1.0)
			if frac > worst:
				worst = frac
				pick = cal
		if pick == "":
			continue
		var mix: Dictionary = share[pick][2]
		var shells: Array = mix.keys().filter(func(sid: Variant) -> bool: return round_item(String(sid)) != &"")
		if shells.is_empty():
			continue
		var load := {}
		var total := maxf(float(share[pick][1]), 1.0)
		var items_n := int(amounts.get(pick, 0)) / per_item(round_item(String(shells[0])))  # 8 rounds, 6 cans, 2 missiles
		var left := items_n
		for i in shells.size():
			var sid := String(shells[i])
			var n_items := left if i == shells.size() - 1 else mini(roundi(float(items_n) * float(mix[sid]) / total), left)
			left -= n_items
			if n_items > 0:
				load[String(round_item(sid))] = n_items
		var pallet := {"120": &"pallet_ammo_120", "25": &"pallet_ammo_25", "tow": &"pallet_ammo_tow"}.get(pick, &"") as StringName
		if pallet != &"" and not load.is_empty():
			out.append({"id": pallet, "load": load, "for": v.vehicle_id})
	return out


static func _calibre(shell: String) -> String:
	if shell == "tow2a":
		return "tow"
	return str(roundi(float(Shells.shell(shell).get("calibre_mm", 0.0))))


# --- Host: fuel ---------------------------------------------------------------------------------

func _fuel_source(key: String) -> Dictionary:
	for s: Dictionary in fuel_sources():
		if String(s.key) == key:
			return s
	return {}


## A refuelling step: litres from the source into the tank. Whether the job ended.
func _refuel_tick(job: Dictionary, dt: float) -> bool:
	var want := minf(float(job.lpm) / 60.0 * dt, maxf(float(vehicle.spec.get("fuel_l", 0.0)) - vehicle.fuel, 0.0))
	var got := _draw_fuel(String(job.key), want)
	if got > 0.0:
		vehicle.server_refuel(got)
		job.count = float(job.count) + got
	if got < want - 0.01 or vehicle.fuel >= float(vehicle.spec.get("fuel_l", 0.0)) - 0.5:
		var id: int = (job.actor as Soldier).get_instance_id()
		_end(id, "", "Refuelled %.0f L (%.0f L in the tank)%s" % [float(job.count), vehicle.fuel, "" if got >= want - 0.01 else ": the source is dry"])
		return true
	return false


## Host: up to `litres` out of fuel source `key`. Litres drawn.
func _draw_fuel(key: String, litres: float) -> float:
	if litres <= 0.0:
		return 0.0
	if key.begins_with("w:"):
		var wi := _world_item(key.trim_prefix("w:"))
		if wi == null:
			return 0.0
		var have := pallet_fuel(wi.item_id, wi.state)
		var got := minf(have, litres)
		var next := wi.state.duplicate(true)
		next["fuel_l"] = snappedf(have - got, 0.1)
		_set_world_state(wi, next)
		return got
	if key.begins_with("t:"):
		var t := _find(key.trim_prefix("t:"))
		if t == null:
			return 0.0
		var got2 := minf(t.fuel, litres)
		t.server_set_fuel(t.fuel - got2)
		return got2
	var hold: VehicleCargo = vehicle.cargo_hold if key == HOLD else (_find(key.trim_prefix("v:")).cargo_hold if _find(key.trim_prefix("v:")) else null)
	if hold == null:
		return 0.0
	var list := hold.entries()
	for i in list.size():
		var e: Dictionary = list[i]
		var have2 := pallet_fuel(e.id, e.get("state", {}))
		if have2 <= 0.0:
			continue
		var got3 := minf(have2, litres)
		var one := hold.remove_entry(VehicleCargo.HOLD, i, 1)
		var st: Dictionary = (one.get("state", {}) as Dictionary).duplicate(true)
		st["fuel_l"] = snappedf(have2 - got3, 0.1)
		hold.take(one.id, 1, st)
		return got3
	return 0.0


# --- Host: tiles, packages, bottles, the tow -----------------------------------------------------

func _tile_problem(actor: Soldier, group: String, item: StringName) -> String:
	if vehicle.wrecked:
		return "It's a wreck"
	if not (fired_tiles().has(group)):
		return "No tile missing there"
	if tile_spare(tile_kind(group)) != item:
		return "%s doesn't fit there" % ItemDB.get_item(item).name
	if not has_part(actor, item):
		return "No %s on you or in the hold" % ItemDB.get_item(item).name
	return ""


## Host: one fired tile of `group` back (the first missing). Whether one was missing.
func server_replace_tile(group: String) -> bool:
	var used: Dictionary = vehicle.get_meta(ArmourModel.META_TILES, {})
	var flags: PackedByteArray = used.get(group, PackedByteArray())
	for i in flags.size():
		if flags[i] != 0:
			flags[i] = 0
			used[group] = flags
			vehicle.set_meta(ArmourModel.META_TILES, used)
			_publish()
			return true
	return false


## Host: every fired tile back (the workshop).
func server_replace_all_tiles() -> int:
	var n := 0
	for g: String in fired_tiles():
		n += (fired_tiles()[g] as Array).size()
	vehicle.set_meta(ArmourModel.META_TILES, {})
	_publish()
	return n


## Host: the fitted packages are `list` (the motor pool's record; tests; a column's own kit).
func server_set_packages(list: Array) -> void:
	var defs: Dictionary = vehicle.spec.get("packages", {})
	packages = []
	for p: Variant in list:
		if defs.has(String(p)) and not String(p) in packages:
			packages.append(String(p))
	vehicle.set_meta(ArmourModel.META_PACKAGES, packages.duplicate())
	_refresh_mults()
	_publish()


## Host: an extinguisher bottle of `kind` used (F-262's extinguishers). Whether there was one.
func server_use_bottle(kind: String) -> bool:
	if int(bottles.get(kind, 0)) <= 0:
		return false
	bottles[kind] = int(bottles[kind]) - 1
	_publish()
	return true


## Host (the FOB): every bottle full again. {kind: bottles refilled}.
func server_refill_bottles() -> Dictionary:
	var full := full_bottles(vehicle.model)
	var out := {}
	for k: String in full:
		var n := int(full[k]) - int(bottles.get(k, 0))
		if n > 0:
			out[k] = n
	bottles = full
	_publish()
	return out


## Host (the motor pool at the FOB): rearmed to its load-out, the smoke restocked, the bottles
## refilled. Returns the bill ({"cost", "lines": [[what, count, dollars]]}): main-gun, autocannon
## and TOW rounds and smoke salvos put in, at data/prices.json "ammo"; the bottles at their
## refill price. MG belts are a free top-up (as since 2026-10-14).
func server_fob_rearm() -> Dictionary:
	var before := ammo_aboard()
	vehicle.server_rearm()
	var after := ammo_aboard()
	var lines: Array = []
	var cost := 0
	for sid: String in after:
		var added := int(after[sid]) - int(before.get(sid, 0))
		if added <= 0:
			continue
		var each := round_price(sid) if sid != "smoke_salvo" else int((Prices.data().get("ammo", {}) as Dictionary).get("smoke_salvo", Prices.price_of(&"smoke_salvo")))
		lines.append([sid, added, added * each])
		cost += added * each
	var refills := server_refill_bottles()
	var prices: Dictionary = (data().get("extinguishers", {}) as Dictionary).get("refill_price", {})
	for k: String in refills:
		lines.append(["bottle_" + k, int(refills[k]), int(refills[k]) * int(prices.get(k, 0))])
		cost += int(refills[k]) * int(prices.get(k, 0))
	return {"cost": cost, "lines": lines}


## Host: `tower` tows this vehicle (hooked: the bar's ends at the hitches).
func server_hook(tower: Vehicle) -> void:
	var lt := VehicleLogistics.of(tower)
	if lt == null:
		return
	tow_by = tower
	lt.towing = vehicle
	recovery_wanted = false
	vehicle.sleeping = false
	tower.sleeping = false
	_publish()
	lt._publish()
	print("[logistics] %s takes %s in tow" % [tower.display_name(), vehicle.display_name()])


## Host: the tow bar off (either end).
func server_unhook() -> void:
	if is_instance_valid(towing):
		var lt := VehicleLogistics.of(towing)
		if lt:
			lt.server_unhook()
		return
	if is_instance_valid(tow_by):
		var lt2 := VehicleLogistics.of(tow_by)
		if lt2:
			lt2.towing = null
			lt2._publish()
	tow_by = null
	_publish()


## Host: the bar between the tower's rear hitch and this vehicle's nearer hitch, as a stiff damped
## spring both ways (pulls and pushes), at most max_accel on the towed vehicle.
func _tow_step(_delta: float) -> void:
	var t := tow_by
	if t.wrecked or vehicle.wrecked:
		server_unhook()
		return
	var a := t.to_global(hitch(t, true))
	var front := vehicle.to_global(hitch(vehicle, false))
	var back := vehicle.to_global(hitch(vehicle, true))
	var b := front if a.distance_to(front) <= a.distance_to(back) else back
	var d := a - b
	var dist := d.length()
	if dist < 0.001:
		return
	var dir := d / dist
	var m := maxf(vehicle.mass, 1.0)
	var k := num("tow", "k_per_kg", 6.0) * m
	var c := num("tow", "damping", 0.7) * 2.0 * sqrt(k * m)
	var va := t.linear_velocity + t.angular_velocity.cross(a - t.global_position)
	var vb := vehicle.linear_velocity + vehicle.angular_velocity.cross(b - vehicle.global_position)
	var stretch := dist - num("tow", "bar_m", 3.0)
	var f := k * stretch + c * (va - vb).dot(dir)
	var cap := num("tow", "max_accel", 6.0) * m
	f = clampf(f, -cap, cap)
	vehicle.apply_force(dir * f, b - vehicle.global_position)
	t.apply_force(-dir * f, a - t.global_position)
	if vehicle.sleeping and absf(stretch) > 0.05:
		vehicle.sleeping = false


## Host: the crew (or A9) asks for recovery.
func server_call_recovery(by: Soldier = null) -> String:
	if vehicle.wrecked:
		return "It's a wreck"
	recovery_wanted = true
	_publish()
	recovery_called.emit(vehicle)
	if by and not by.is_ai():
		vehicle._tell(by, "Recovery requested for the %s" % vehicle.display_name())
	return ""


func _on_damaged(_zone: StringName, _hit: Dictionary) -> void:
	_hit_at = Soldier._now()


var _tiles_seen := ""


func _tiles_dirty() -> bool:
	var digest := str(fired_tiles())
	if digest == _tiles_seen:
		return false
	_tiles_seen = digest
	return true


# --- Net and saving ------------------------------------------------------------------------------

func _publish() -> void:
	if not _is_host():
		return
	if vehicle and not packages.is_empty():
		vehicle.set_meta(ArmourModel.META_PACKAGES, packages.duplicate())
	var share := {}
	for k: Variant in progress:
		share[String(k)] = snappedf(float(progress[k]), 0.1)
	var js: Array = []
	for id: int in jobs:
		var j: Dictionary = jobs[id]
		var actor: Soldier = j.actor if is_instance_valid(j.actor) else null
		var lvl := vehicle.level() if vehicle and vehicle.is_inside_tree() else null
		js.append([String(lvl.get_path_to(actor)) if actor and lvl else "", String(j.get("label", j.action)), String(j.key),
			snappedf(clampf(float(j.done) / maxf(float(j.need), 0.01), 0.0, 1.0) if float(j.need) < INF else 0.0, 0.01), String(j.paused) != ""])
	_tiles_seen = str(fired_tiles())
	net_state = {"pk": packages.duplicate(), "lo": loadout, "b": bottles.duplicate(), "tl": fired_tiles(), "p": share, "j": js,
		"tw": tow_by.vehicle_id if is_instance_valid(tow_by) else "", "tg": towing.vehicle_id if is_instance_valid(towing) else "", "rc": recovery_wanted}


## Clients: the published state applied (the packages and fired tiles as the meta the armour,
## HUD and x-ray read).
func _apply_net() -> void:
	packages = (net_state.get("pk", []) as Array).duplicate()
	loadout = String(net_state.get("lo", ""))
	bottles = (net_state.get("b", {}) as Dictionary).duplicate()
	progress = (net_state.get("p", {}) as Dictionary).duplicate()
	recovery_wanted = bool(net_state.get("rc", false))
	if vehicle:
		vehicle.set_meta(ArmourModel.META_PACKAGES, packages.duplicate())
		vehicle.set_meta(ArmourModel.META_TILES, _tiles_from(net_state.get("tl", {})))
	_refresh_mults()


static func _tiles_from(tl: Variant) -> Dictionary:
	var used := {}
	if not tl is Dictionary:
		return used
	for g: Variant in tl:
		var flags := PackedByteArray()
		for i: Variant in tl[g]:
			if int(i) >= flags.size():
				flags.resize(int(i) + 1)
			flags[int(i)] = 1
		used[String(g)] = flags
	return used


## JSON-safe state for the zone save and the motor pool's record.
func to_save() -> Dictionary:
	var out := {"packages": packages.duplicate(), "loadout": loadout, "bottles": bottles.duplicate(), "progress": progress.duplicate(), "tiles": fired_tiles()}
	if recovery_wanted:
		out["recovery"] = true
	if is_instance_valid(tow_by):
		out["tow_by"] = tow_by.vehicle_id  # A6 (F-272): the tow comes back with the zone
	return out


## Puts a to_save() back (an older save without one: no packages, full bottles).
func from_save(d: Dictionary) -> void:
	if d.is_empty():
		_publish()
		return
	server_set_packages(d.get("packages", []) if d.get("packages") is Array else [])
	loadout = String(d.get("loadout", ""))
	if d.get("bottles") is Dictionary:
		bottles = {}
		var full := full_bottles(vehicle.model)
		for k: String in full:
			bottles[k] = clampi(int((d.bottles as Dictionary).get(k, full[k])), 0, int(full[k]))
	progress = {}
	if d.get("progress") is Dictionary:
		for k: Variant in d.progress:
			progress[String(k)] = maxf(float(d.progress[k]), 0.0)
	if vehicle and d.has("tiles"):
		vehicle.set_meta(ArmourModel.META_TILES, _tiles_from(d.tiles))
	recovery_wanted = bool(d.get("recovery", false))
	_saved_tow = String(d.get("tow_by", ""))
	_publish()


## Host (VehicleLayer.server_restore, once every vehicle is back): a tow the zone save had, hooked
## up again (a rolled vehicle being righted carries on).
func server_rehook_saved() -> void:
	if _saved_tow == "" or not _is_host():
		return
	var tower := _find(_saved_tow)
	_saved_tow = ""
	if tower and not tower.wrecked and VehicleLogistics.of(tower) and not towed():
		server_hook(tower)
		if vehicle.drive and vehicle.drive.is_rolled():
			vehicle.drive.server_start_righting(tower)


## Every peer (A6, F-272): the tow bar drawn from the tower's rear hitch to this vehicle's nearer
## hitch while it's towed.
func _process(_delta: float) -> void:
	var tower: Vehicle = tow_by if _is_host() else null
	if not _is_host() and String(net_state.get("tw", "")) != "":
		tower = _find(String(net_state.tw))
	if not is_instance_valid(tower) or not vehicle.is_inside_tree():
		if _bar:
			_bar.visible = false
		return
	var a := tower.to_global(hitch(tower, true))
	var front := vehicle.to_global(hitch(vehicle, false))
	var back := vehicle.to_global(hitch(vehicle, true))
	var b := front if a.distance_to(front) <= a.distance_to(back) else back
	if _bar == null:
		_bar = MeshInstance3D.new()
		_bar.name = "TowBar"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.09, 0.09, 1.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.22, 0.23, 0.2)
		mat.roughness = 0.7
		mesh.material = mat
		_bar.mesh = mesh
		_bar.top_level = true
		vehicle.add_child(_bar)
	var length := a.distance_to(b)
	_bar.visible = length > 0.05
	if _bar.visible:
		var mid := (a + b) * 0.5
		var z := (a - b) / length
		var x := Vector3.UP.cross(z)
		if x.length_squared() < 0.0001:
			x = Vector3.RIGHT
		x = x.normalized()
		_bar.global_transform = Transform3D(Basis(x, z.cross(x), z * length), mid)


## The tow bar's node while one's drawn (tests).
func tow_bar() -> MeshInstance3D:
	return _bar if _bar and _bar.visible else null
