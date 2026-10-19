class_name AavSupport
extends Node
## The AAV support (wave 5b, V4; design doc "Player faction supports", Captain): an AAV-7 with
## an AI crew (driver and gunner) comes from the LHD on a coastal zone (out of its stern gate
## into the water, swimming in to the beach and on to whoever called it) or, inland, from the
## friendly FOB's side of the map (driving in from its edge), and takes orders from the command
## menu's Support > AAV entries ("support:aav_*", registered with Supports):
##   aav_call      bring one to the caller (paid: Economy.server_pay_support("aav", contract));
##   aav_move      go to the point under the crosshair (swimming there if it's water);
##   aav_hold      stop where it is;
##   aav_follow    keep near the caller;
##   aav_mount     the selected AI squadmates walk to the ramp and get in the back; players get
##                 in through Left Ctrl at the ramp (V1's seats);
##   aav_dismount  everyone in the back gets out (not in open water);
##   aav_return    back to the LHD or the FOB (empty), then gone.
## Its gunner fires the M2 at enemies (AavGunner). One at a time (Proposed). Refused in a
## contract zone unless it's on the coast and data says so (Proposed: "contract_coast"); in
## mountains (Captain: AAVs can't work mountains: the zone's "terrain": "mountain", hills of
## "mountain_relief_m", or ground steeper than "max_slope_deg" on its way); when the company
## can't pay. On the way it stops below ground too steep to climb, and holds if it gets nowhere
## for STUCK_S (going home, it's simply gone). Destroyed, it's lost with its
## cargo and whoever is aboard (V1's fire) and not refunded, and no other comes for the rest of
## the op (Captain). Numbers in data/ground_supports.json "aav" (Proposed).
##
## Host authoritative: the host runs the AAV and decides every command; every peer (late
## joiners too) gets the support's state (_client_state: the vehicle's id, its order, lost)
## and sees the AAV itself through the vehicle layer. One node, "AavSupport", in every level
## (install(), from CompoundLevel._ready), which also adds the support origin (Lhd) and the
## motor pool's level node (MotorPoolNode).
##
## Dev tools (DevTools.on()): ] (right bracket, by its place on the keyboard) calls an AAV to you anywhere (the vehicle range, the test
## zone, any zone) without paying.

const NODE_NAME := "AavSupport"
const DATA_PATH := "res://data/ground_supports.json"
const DEV_KEY := KEY_BRACKETRIGHT  # Insert is Captain's bug-report key, Delete his AI overlay
## The AAV's orders (every peer reads them; "" when none is out).
const INBOUND := "inbound"
const MOVE := "move"
const HOLD := "hold"
const FOLLOW := "follow"
const RETURN := "return"
const LOST := "lost"
## AI ordered in get in this close to the ramp; checked this often.
const BOARD_REACH_M := 3.5
const TICK_S := 0.25
## On its way, the ground under it this much steeper than max_slope_deg stops it.
const SLOPE_STOP_MARGIN_DEG := 4.0
## Getting nowhere (under 3 m) this long while under way, it gives up (Proposed).
const STUCK_S := 45.0

static var _data := {}

## The AAV out now (host; clients resolve it by id: current()).
var vehicle: Vehicle
## Its order (INBOUND, MOVE...), "" with none out.
var order := ""
## This op's AAV was destroyed: no other comes.
var lost := false
## Where it came from: &"lhd" or &"fob".
var origin_kind := &""
## Host: the player who last commanded it (it goes to them, follows them).
var caller: Soldier
## Host: AAVs called this op.
var calls := 0
## Host: the last thing it told its caller (tests, the session log).
var last_message := ""

var _vehicle_id := ""
var _cfg := {}
var _legs: Array = []
var _leg: Dictionary = {}
var _target := Vector3.INF
var _tick := 0.0
var _boarding := {}  # host: soldier instance id -> {"soldier", "until", "by", "going", "next_at"}
var _progress_pos := Vector3.ZERO
var _progress_at := 0.0


## The numbers (data/ground_supports.json), read once.
static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {"aav": {}, "lhd": {}, "motor_pool": {}, "vehicle_qrf": {}, "gunner": {}}
	return _data


## Every peer, from the level's _ready: the support origin (Lhd), this node and the motor
## pool's level node (once each).
static func install(level: Node3D) -> void:
	Lhd.install(level)
	if level.get_node_or_null(NodePath(NODE_NAME)) == null:
		var node := AavSupport.new()
		node.name = NODE_NAME
		level.add_child(node)
	if level.get_node_or_null(NodePath(MotorPoolNode.NODE_NAME)) == null:
		level.add_child(MotorPoolNode.new())


## The level's AAV support (or null).
static func of(from: Node) -> AavSupport:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NodePath(NODE_NAME)) as AavSupport if lvl else null


func _ready() -> void:
	_cfg = data().get("aav", {})
	for cmd: String in ["aav_call", "aav_move", "aav_hold", "aav_follow", "aav_mount", "aav_dismount", "aav_return"]:
		Supports.register(cmd, Callable(self, "_cmd_" + cmd))
	Net.peer_joined.connect(_on_peer_joined)


# --- Every peer ------------------------------------------------------------------------------

## The AAV out now, or null.
func current() -> Vehicle:
	if is_instance_valid(vehicle) and not vehicle.is_queued_for_deletion():
		return vehicle
	var layer := VehicleLayer.of(self)
	var v := layer.find(_vehicle_id) if layer and _vehicle_id != "" else null
	return v if v and not v.is_queued_for_deletion() else null


## Whether an AAV is out (on its way, on station, going home).
func is_out() -> bool:
	return order != "" and order != LOST


func order_text() -> String:
	return {INBOUND: "on its way", MOVE: "moving", HOLD: "holding", FOLLOW: "following", RETURN: "going home", LOST: "lost"}.get(order, "none")


func level() -> Node:
	return get_parent()


# --- Commands (host; Supports handlers: (caller, arg, point, names) -> "" or a message) ----------

func _cmd_aav_call(who: Node, arg: String, _point: Vector3, _names: PackedStringArray) -> String:
	return server_call(who as Soldier, arg == "dev" and DevTools.on())


func _cmd_aav_move(who: Node, _arg: String, point: Vector3, _names: PackedStringArray) -> String:
	return server_move(who as Soldier, point)


func _cmd_aav_hold(who: Node, _arg: String, _point: Vector3, _names: PackedStringArray) -> String:
	return server_hold(who as Soldier)


func _cmd_aav_follow(who: Node, _arg: String, _point: Vector3, _names: PackedStringArray) -> String:
	return server_follow(who as Soldier)


func _cmd_aav_mount(who: Node, _arg: String, _point: Vector3, names: PackedStringArray) -> String:
	return server_mount(who as Soldier, names)


func _cmd_aav_dismount(who: Node, _arg: String, _point: Vector3, _names: PackedStringArray) -> String:
	return server_dismount(who as Soldier)


func _cmd_aav_return(who: Node, _arg: String, _point: Vector3, _names: PackedStringArray) -> String:
	return server_return(who as Soldier)


## Host: `by` calls an AAV to them. `dev`: free and anywhere (dev tools, tests). Returns "" when
## it's on its way, else why not.
func server_call(by: Soldier, dev := false) -> String:
	if not multiplayer.is_server() or by == null:
		return ""
	if lost:
		return "The AAV was lost: none left for this operation"
	if is_out() and bool(_cfg.get("one_at_a_time", true)):
		return "The AAV is already out (%s)" % order_text()
	var origin := Lhd.of(self)
	var layer := VehicleLayer.of(self)
	if origin == null or layer == null:
		return "No AAVs here"
	if not dev:
		var why := zone_problem()
		if why != "":
			return why
	var to := by.global_position
	var steep := terrain_problem(_route_start(origin, to), to)
	if steep != "":
		return steep
	if not dev and not Economy.server_pay_support("aav", contract_id()):
		return "Can't afford an AAV ($%s)" % DebriefCalc.money(Prices.support_price("aav"))
	var v := _spawn(origin, to, layer)
	if v == null:
		return "The AAV couldn't launch"
	caller = by
	calls += 1
	_set_order(INBOUND)
	_legs.clear()
	if origin.is_ship():
		var terrain := _terrain()
		_legs.append({"swim": [origin.approach_point(v.global_position), terrain.shore_point(to, -float(_cfg.get("beach_out_m", 40.0))),
			terrain.shore_point(to, float(_cfg.get("beach_in_m", 25.0)))]})
	_legs.append({"caller": true})
	_next_leg()
	_tell(by, "AAV on its way from the %s" % ("LHD" if origin.is_ship() else "FOB"))
	print("[aav] called by %s from the %s at (%.0f, %.0f)%s" % [by.name, origin.kind, v.global_position.x, v.global_position.z, " (dev)" if dev else ""])
	return ""


## Host (BaseHub, the squad crossing on): the AAV out (not going home) follows it; returns its
## condition (damage, fuel), or {} for none.
func server_take_follower() -> Dictionary:
	var v := current()
	if v == null or lost or order == RETURN or v.wrecked:
		return {}
	return v.condition()


## Host, the squad's new zone: the AAV that followed comes in from this zone's origin to `by`,
## free, in the condition it left with.
func server_follow_in(cond: Dictionary, by: Soldier) -> void:
	if cond.is_empty() or lost or is_out() or by == null:
		return
	if server_call(by, true) == "" and current():
		current().apply_condition(cond)
		_tell(by, "The AAV followed you over")


## Host: the AAV goes to `point` (swimming if it's water) and holds there.
func server_move(by: Soldier, point: Vector3) -> String:
	var why := _commandable(by)
	if why != "":
		return why
	var terrain := _terrain()
	var wet := terrain != null and terrain.water_height(point.x, point.z) > terrain.height_at(point.x, point.z)
	if not wet:
		var steep := terrain_problem(vehicle.global_position, point)
		if steep != "":
			return steep
	_legs.clear()
	_leg = {}
	if wet:
		vehicle.server_follow_path(PackedVector3Array([Vector3(point.x, terrain.sea_level, point.z)]))
	else:
		vehicle.server_drive_to(point)
	_set_order(MOVE)
	return ""


func server_hold(by: Soldier) -> String:
	var why := _commandable(by)
	if why != "":
		return why
	_legs.clear()
	_leg = {}
	vehicle.server_stop()
	_set_order(HOLD)
	return ""


func server_follow(by: Soldier) -> String:
	var why := _commandable(by)
	if why != "":
		return why
	_legs.clear()
	_leg = {}
	_target = Vector3.INF
	_set_order(FOLLOW)
	_follow_step()
	return ""


## Host: the AAV stops; the named AI squadmates (all if none) walk to its ramp and get in the
## back; players get in themselves (Left Ctrl at the ramp).
func server_mount(by: Soldier, names: PackedStringArray) -> String:
	var why := _commandable(by)
	if why != "":
		return why
	if AavWater.afloat(vehicle):
		return "The AAV is in the water"
	_legs.clear()
	_leg = {}
	vehicle.server_stop()
	_set_order(HOLD)
	var lvl := level() as CompoundLevel
	var squad := lvl.squad_for(by.faction) if lvl else null
	var sent := 0
	var timeout := float(_cfg.get("board_timeout_s", 60.0))
	if squad:
		for s: Soldier in squad.pick(names):
			if not s.is_ai() or not s.vitals.is_up() or s.has_meta(&"vehicle_crew") or Vehicle.ride_of(s) == vehicle:
				continue
			if _flat(s.global_position).distance_to(_flat(ramp())) <= BOARD_REACH_M and _board(s):
				sent += 1
				continue
			_boarding[s.get_instance_id()] = {"soldier": s, "until": Soldier._now() + timeout, "by": by}
			sent += 1
	_board_step()
	_tell(by, "%sPlayers: get in at the ramp (Left Ctrl)" % ("Squad mounting the AAV. " if sent > 0 else ""))
	return ""


## Host: everyone in the back gets out (the crew stays; bodies loaded in stay); AI squadmates
## fall in on whoever ordered it.
func server_dismount(by: Soldier) -> String:
	var why := _commandable(by)
	if why != "":
		return why
	if AavWater.afloat(vehicle):
		return "Not in open water"
	vehicle.server_stop()
	if order != HOLD:
		_legs.clear()
		_leg = {}
		_set_order(HOLD)
	var out := 0
	var mates := PackedStringArray()
	for s: Soldier in vehicle.occupants():
		if s.has_meta(&"vehicle_crew") or not s.vitals.is_up():
			continue
		vehicle.server_exit(s)
		out += 1
		if s.is_ai():
			mates.append(String(s.name))
	var lvl := level() as CompoundLevel
	var squad := lvl.squad_for(by.faction) if lvl else null
	if squad and not mates.is_empty():
		squad.give_order(by, Squad.Order.FOLLOW, by.global_position, mates)
	return "" if out > 0 else "Nobody in the back"


## Host: the AAV goes home (it must be empty but for its crew): to the LHD's stern by sea, or the
## FOB's side of the map; there it's gone.
func server_return(by: Soldier) -> String:
	var why := _commandable(by)
	if why != "":
		return why
	for s: Soldier in vehicle.occupants():
		if not s.has_meta(&"vehicle_crew"):
			return "Everyone out of the AAV first"
	var origin := Lhd.of(self)
	var pos := vehicle.global_position
	_legs.clear()
	if origin.is_ship():
		var terrain := _terrain()
		var dock := origin.dock_point(pos)
		if AavWater.depth(vehicle) <= 0.0 and terrain.shore_distance(pos.x, pos.z) > 0.0:
			_legs.append({"drive": terrain.shore_point(pos, float(_cfg.get("beach_in_m", 25.0)))})
			_legs.append({"swim": [terrain.shore_point(pos, -float(_cfg.get("beach_out_m", 40.0))), origin.approach_point(pos), dock]})
		else:
			_legs.append({"swim": [origin.approach_point(pos), dock]})
	else:
		_legs.append({"drive": origin.dock_point(pos)})
	_set_order(RETURN)
	_next_leg()
	return ""


## Host: why `by` can't command the AAV now ("" if they can).
func _commandable(by: Soldier) -> String:
	if not multiplayer.is_server() or by == null:
		return "No"
	if lost:
		return "The AAV was lost"
	if not is_out() or not is_instance_valid(vehicle):
		return "No AAV out: call one first"
	if vehicle.wrecked or vehicle.is_burning():
		return "The AAV is burning"
	caller = by
	return ""


## Host: why the AAV support doesn't work in this zone ("" if it does): hot zones, and contract
## zones on the coast when data allows.
func zone_problem() -> String:
	var lvl := level()
	if bool(_cfg.get("hot_zones", true)) and Supports.is_hot_zone(lvl):
		return ""
	var origin := Lhd.of(self)
	if bool(_cfg.get("contract_coast", true)) and origin and origin.is_ship():
		return ""
	return "AAVs support hot zones%s only" % (" and coastal contracts" if bool(_cfg.get("contract_coast", true)) else "")


## Host: why an AAV can't drive from `from` to `to` here ("" if it can): mountains (the zone's
## "terrain", or its hills' height), or ground steeper than it climbs on the way.
func terrain_problem(from: Vector3, to: Vector3) -> String:
	var def: Variant = level().get(&"def")
	if def is Dictionary and (String(def.get("terrain", "")) == "mountain" or float(def.get("relief_m", 0.0)) >= float(_cfg.get("mountain_relief_m", 45.0))):
		return "AAVs can't work in mountains"
	var steep := route_slope_deg(from, to)
	if steep > float(_cfg.get("max_slope_deg", 31.0)):
		return "Too steep for an AAV (%d°)" % roundi(steep)
	return ""


## The steepest ground (degrees) on the straight line from `from` to `to`, out of the water.
func route_slope_deg(from: Vector3, to: Vector3) -> float:
	var terrain := _terrain()
	if terrain == null:
		return 0.0
	var step := maxf(float(_cfg.get("route_step_m", 8.0)), 1.0)
	var flat := Vector2(to.x - from.x, to.z - from.z)
	var n := maxi(ceili(flat.length() / step), 1)
	var worst := 0.0
	for i in n + 1:
		var p := Vector2(from.x, from.z) + flat * (float(i) / n)
		if terrain.water_height(p.x, p.y) > terrain.height_at(p.x, p.y):
			continue
		worst = maxf(worst, rad_to_deg(acos(clampf(terrain.normal_at(p.x, p.y).y, -1.0, 1.0))))
	return worst


## Whether AAVs work in `from`'s level as a contract zone: on the coast (the LHD offshore), when
## data allows ("contract_coast"). Every peer (the briefing asks).
static func coast_contracts(from: Node) -> bool:
	var origin := Lhd.of(from)
	return bool(data().get("aav", {}).get("contract_coast", true)) and origin != null and origin.is_ship()


## The contract the support is charged to: the running deployment's first.
static func contract_id() -> String:
	var cids: Array = Contracts.deployment().get("cids", [])
	return String(cids[0]) if not cids.is_empty() else ""


# --- Host: the AAV ---------------------------------------------------------------------------------

func _spawn(origin: Lhd, toward: Vector3, layer: VehicleLayer) -> Vehicle:
	var lvl := level() as CompoundLevel
	var v := layer.server_spawn(String(_cfg.get("model", "aav7")), origin.entry_transform(toward), String(_cfg.get("scheme", "")), &"player", "")
	if v == null or lvl == null:
		return null
	v.set_meta(&"support", "aav")
	v.set_meta(&"no_save", true)  # a support goes home with the op; only its wreck stays (VehicleLayer.records)
	for c: Array in _cfg.get("cargo", []):
		v.cargo_hold.take(StringName(String(c[0])), int(c[1]) if c.size() > 1 else 1)
	var gun_seat := int(v.spec.get("gun", {}).get("seat", -1))
	for i in v.seat_count():
		if v.seat_kind(i) == Vehicle.DRIVER or i == gun_seat:
			var role := "Driver" if v.seat_kind(i) == Vehicle.DRIVER else "Gunner"
			var crew := lvl.spawn_soldier({"name": ("AAV%d_%s" % [calls + 1, role]).validate_node_name(), "faction": "friendly",
				"variant": "tan", "pos": v.global_position + Vector3.UP * 3.0, "loadout": _cfg.get("crew_loadout", []),
				"combat": 0.55, "discipline": 0.7, "guard": false})
			if crew == null:
				continue
			# Not a squadmate (no squad orders, no slot: Squad.members() and CompoundLevel._squad_ai
			# skip it), but still a combatant: enemies see it, medics and friendly-fire checks too.
			crew.set_meta(&"vehicle_crew", v.vehicle_id)
			v.server_enter(crew, i)
	AavGunner.attach(v)
	v.destroyed.connect(_on_destroyed)
	vehicle = v
	_vehicle_id = v.vehicle_id
	origin_kind = origin.kind
	return v


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_board_step()
	if order == "" or order == LOST:
		return
	if not is_instance_valid(vehicle) or vehicle.is_queued_for_deletion():
		vehicle = null
		_vehicle_id = ""
		_set_order("")
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK_S
	match order:
		INBOUND:
			_inbound_step()
		MOVE:
			if _ai_done():
				_set_order(HOLD)
		FOLLOW:
			_follow_step()
		RETURN:
			_return_step()
	if is_instance_valid(vehicle) and is_out():
		_slope_check()
	if is_instance_valid(vehicle) and is_out():
		_stuck_check()


## Getting nowhere for STUCK_S while it should be moving: going home it's gone anyway;
## otherwise it holds and says so.
func _stuck_check() -> void:
	var now := Soldier._now()
	if _ai_done() or order == HOLD or vehicle.global_position.distance_to(_progress_pos) > 3.0:
		_progress_pos = vehicle.global_position
		_progress_at = now
		return
	if now - _progress_at < STUCK_S:
		return
	print("[aav] stuck at (%.0f, %.0f) %s" % [vehicle.global_position.x, vehicle.global_position.z, order_text()])
	if order == RETURN:
		_go_home(Lhd.of(self))
		return
	vehicle.server_stop()
	_legs.clear()
	_leg = {}
	_set_order(HOLD)
	_tell(caller, "The AAV is stuck: holding")


func _ai_done() -> bool:
	return not is_instance_valid(vehicle.ai) or not vehicle.ai.active


func _next_leg() -> void:
	_leg = _legs.pop_front() if not _legs.is_empty() else {}
	if _leg.has("swim"):
		vehicle.server_follow_path(PackedVector3Array(_leg.swim))
	elif _leg.has("drive"):
		vehicle.server_drive_to(_leg.drive)
	elif _leg.has("caller"):
		_target = Vector3.INF
		_inbound_step()


## A swim or drive leg is done when the AI got there (or nearly: it doesn't stop between legs).
func _leg_done() -> bool:
	return _ai_done() or (is_instance_valid(vehicle.ai) and vehicle.ai.remaining() < 6.0)


func _inbound_step() -> void:
	if _leg.has("swim") or _leg.has("drive"):
		if _leg_done():
			_next_leg()
		return
	if not _caller_ok():
		vehicle.server_stop()
		_set_order(HOLD)
		return
	var d := _flat(vehicle.global_position).distance_to(_flat(caller.global_position))
	if d <= float(_cfg.get("arrive_m", 14.0)) + 3.0 or (_ai_done() and _target != Vector3.INF and d <= float(_cfg.get("arrive_m", 14.0)) * 2.0):
		vehicle.server_stop()
		_set_order(HOLD)
		_tell(caller, "AAV on station")
		return
	if _target == Vector3.INF or _flat(caller.global_position).distance_to(_flat(_target)) > float(_cfg.get("retarget_m", 20.0)) or _ai_done():
		_drive_near(caller.global_position, float(_cfg.get("arrive_m", 14.0)))


func _follow_step() -> void:
	if not _caller_ok():
		return
	if Vehicle.ride_of(caller) == vehicle:
		if not _ai_done():
			vehicle.server_stop()
		return
	var d := _flat(vehicle.global_position).distance_to(_flat(caller.global_position))
	var gap := float(_cfg.get("follow_gap_m", 14.0))
	if d > float(_cfg.get("follow_m", 30.0)) and (_ai_done() or _target == Vector3.INF or _flat(caller.global_position).distance_to(_flat(_target)) > 8.0):
		_drive_near(caller.global_position, gap)
	elif d <= gap + 2.0 and not _ai_done():
		vehicle.server_stop()


func _return_step() -> void:
	var origin := Lhd.of(self)
	if origin == null:
		return
	var dock := origin.dock_point(vehicle.global_position)
	if _flat(vehicle.global_position).distance_to(_flat(dock)) <= float(_cfg.get("dock_m", 25.0)):
		_go_home(origin)
		return
	if _leg_done():
		if _legs.is_empty():
			_legs.append({"swim": [dock]} if origin.is_ship() else {"drive": dock})
		_next_leg()


## Drives to `dist` metres short of `at` (on the line from the AAV), so it doesn't run them over.
func _drive_near(at: Vector3, dist: float) -> void:
	_target = at
	var back := _flat(vehicle.global_position - at)
	var spot := at + (back.normalized() * dist if back.length() > 0.5 else Vector3.ZERO)
	var lvl := level()
	if lvl.has_method(&"ground_point"):
		spot = lvl.call(&"ground_point", spot)
	vehicle.server_drive_to(spot)


## On its way, ground too steep to climb stops it (Captain: AAVs can't work mountains).
func _slope_check() -> void:
	var terrain := _terrain()
	if terrain == null or _ai_done() or order == HOLD:
		return
	var p := vehicle.global_position
	if terrain.water_height(p.x, p.z) > terrain.height_at(p.x, p.z):
		return
	var ahead := p - vehicle.global_basis.z * 4.0
	var slope := rad_to_deg(acos(clampf(terrain.normal_at(ahead.x, ahead.z).y, -1.0, 1.0)))
	if slope > float(_cfg.get("max_slope_deg", 31.0)) + SLOPE_STOP_MARGIN_DEG:
		vehicle.server_stop()
		_legs.clear()
		_leg = {}
		_set_order(HOLD)
		_tell(caller, "The AAV can't climb that (%d°): holding" % roundi(slope))
		print("[aav] too steep ahead (%.0f°)" % slope)


func _go_home(origin: Lhd) -> void:
	var v := vehicle
	for s: Soldier in v.occupants():
		if s.has_meta(&"vehicle_crew"):
			s.queue_free()
		else:
			v.server_exit(s)
	v.queue_free()
	vehicle = null
	_vehicle_id = ""
	_legs.clear()
	_leg = {}
	_set_order("")
	_tell(caller, "The AAV is back %s" % ("aboard the LHD" if origin.is_ship() else "at the FOB"))
	print("[aav] home at the %s" % origin.kind)


func _on_destroyed(v: Vehicle) -> void:
	if v != vehicle:
		return
	lost = true
	_boarding.clear()
	_legs.clear()
	_leg = {}
	_set_order(LOST)
	_tell(caller, "The AAV is hit and burning: get out!")
	print("[aav] destroyed")


func _caller_ok() -> bool:
	return is_instance_valid(caller) and not caller.is_queued_for_deletion() and caller.vitals.is_up()


func _terrain() -> ZoneTerrain:
	var t: Variant = level().get(&"terrain") if level() else null
	return t as ZoneTerrain if t is ZoneTerrain else null


func _route_start(origin: Lhd, to: Vector3) -> Vector3:
	if origin.is_ship():
		return _terrain().shore_point(to, float(_cfg.get("beach_in_m", 25.0)))
	return origin.edge_point(to)


static func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)


# --- Boarding (host) -----------------------------------------------------------------------------

## The ramp (the troop door at the back) in the world, on the ground.
func ramp() -> Vector3:
	var v := current()
	if v == null:
		return Vector3.ZERO
	for p in v.get_children():
		var point := p as VehicleActionPoint
		if point and point.kind == VehicleActionPoint.DOOR and point.seat_list.any(func(i: Variant) -> bool: return v.seat_kind(int(i)) == Vehicle.PASSENGER and int(i) > 2):
			return Vector3(point.global_position.x, v.global_position.y, point.global_position.z)
	return v.global_position


## `s` into the first free seat in the back. Returns whether they got in.
func _board(s: Soldier) -> bool:
	for i in vehicle.seat_count():
		if vehicle.seat_kind(i) == Vehicle.PASSENGER and vehicle.occupant(i) == null and i > 2:
			return vehicle.server_enter(s, i)
	return vehicle.server_enter(s)


func _board_step() -> void:
	if _boarding.is_empty():
		return
	for id: int in _boarding.keys():
		var b: Dictionary = _boarding[id]
		var s: Soldier = b.soldier if is_instance_valid(b.soldier) else null
		if s == null or not is_instance_valid(vehicle) or vehicle.wrecked or vehicle.is_burning() or not s.vitals.is_up() \
				or Soldier._now() > float(b.until) or Vehicle.ride_of(s) != null:
			_boarding.erase(id)
			continue
		if _flat(s.global_position).distance_to(_flat(ramp())) <= BOARD_REACH_M:
			_boarding.erase(id)
			_board(s)
			continue
		# The navigation doesn't know the hull: one ahead of the ramp walks round its side first.
		var next := board_waypoint(s.global_position)
		var going: Vector3 = b.get("going", Vector3.INF)
		if not going.is_finite() or _flat(next).distance_to(_flat(going)) > 1.0 or Soldier._now() >= float(b.get("next_at", 0.0)):
			b["going"] = next
			b["next_at"] = Soldier._now() + 4.0
			var lvl := level() as CompoundLevel
			var squad := lvl.squad_for(s.faction) if lvl else null
			var by: Soldier = b.get("by") if is_instance_valid(b.get("by")) else s
			if squad:
				squad.give_order(by, Squad.Order.MOVE, next, PackedStringArray([String(s.name)]))


## Where someone at `from` walks next to reach the ramp: straight to it from behind the hull,
## else to the rear corner on their side, else (ahead of the hull) to the middle of their side.
func board_waypoint(from: Vector3) -> Vector3:
	var v := current()
	if v == null:
		return from
	var size := VehicleArt.size_m(v.model)
	var local := v.to_local(from)
	var side := signf(local.x) if absf(local.x) > 0.1 else 1.0
	var out: Vector3
	if local.z > size.z * 0.5 - 0.5:
		out = v.to_local(ramp()) + Vector3(0, 0, 0.8)
	elif local.z > -0.5 and absf(local.x) > size.x * 0.5 + 0.8:
		out = Vector3(side * (size.x * 0.5 + 1.4), 0.0, size.z * 0.5 + 1.2)
	else:
		out = Vector3(side * (size.x * 0.5 + 1.6), 0.0, 0.5)
	var at := v.to_global(Vector3(out.x, 0.0, out.z))
	var lvl := level()
	return lvl.call(&"ground_point", at) if lvl.has_method(&"ground_point") else Vector3(at.x, v.global_position.y, at.z)


## Host (tests): squadmates still walking to the ramp.
func boarding_count() -> int:
	return _boarding.size()


# --- State to every peer -----------------------------------------------------------------------------

func _set_order(o: String) -> void:
	if o == order:
		return
	order = o
	if multiplayer.is_server():
		var at := vehicle.global_position if is_instance_valid(vehicle) else Vector3.ZERO
		print("[aav] %s at (%.0f, %.1f, %.0f)" % [order_text(), at.x, at.y, at.z])
		_broadcast()


func _state() -> Dictionary:
	return {"id": _vehicle_id, "order": order, "lost": lost, "from": String(origin_kind), "calls": calls}


func _broadcast() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_client_state.rpc(_state())


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server() and is_inside_tree():
		_client_state.rpc_id(id, _state())


@rpc("authority", "call_remote", "reliable")
func _client_state(s: Dictionary) -> void:
	_vehicle_id = String(s.get("id", ""))
	order = String(s.get("order", ""))
	lost = bool(s.get("lost", false))
	origin_kind = StringName(String(s.get("from", "")))
	calls = int(s.get("calls", 0))
	vehicle = null


func _tell(who: Soldier, text: String) -> void:
	last_message = text
	if who and is_instance_valid(who) and not who.is_ai():
		who._client_message.rpc_id(who.owner_peer(), text)


# --- Dev tools -----------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.physical_keycode != DEV_KEY or not DevTools.on():
		return
	get_viewport().set_input_as_handled()
	request_dev_call.rpc_id(1)


## Dev tools: the sender's player calls an AAV to them, free, anywhere (the host must run with
## dev tools too).
@rpc("any_peer", "call_local", "reliable")
func request_dev_call() -> void:
	if not multiplayer.is_server() or not DevTools.on():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	var lvl := level() as CompoundLevel
	var me := lvl.players.get_node_or_null(str(id)) as Soldier if lvl else null
	if me == null or not me.vitals.is_up():
		return
	var why := server_call(me, true)
	if why != "":
		_tell(me, why)


# --- Session log ----------------------------------------------------------------------------------

## Lines for SessionLog.state_text: every vehicle in the level (id, model, side, driver,
## passengers, damage by zone, fuel, what its AI is doing) and the AAV support's state.
static func state_text(from: Node) -> String:
	var layer := VehicleLayer.of(from) if from and from.is_inside_tree() else null
	if layer == null:
		return ""
	var lines: Array[String] = []
	var support := AavSupport.of(from)
	if support:
		lines.append("AAV support: %s%s, %d called, from %s" % [support.order_text(), " (LOST)" if support.lost else "", support.calls, String(support.origin_kind) if support.origin_kind != &"" else "-"])
	var vehicles := layer.vehicles()
	lines.append("Vehicles (%d):" % vehicles.size())
	for v in vehicles:
		var p := v.global_position
		var d := v.driver()
		var riders: Array[String] = []
		for s: Soldier in v.occupants():
			if s != d:
				riders.append("%s%s" % [s.name, "" if s.vitals.is_up() else " (down)" if not s.vitals.is_dead() else " (dead)"])
		var zones: Array[String] = []
		for z: StringName in Vehicle.ZONES:
			var h := v.zone_health(z)
			if h < 0.999:
				zones.append("%s %d%%" % [z, roundi(h * 100.0)])
		var doing := "-"
		if is_instance_valid(v.ai):
			doing = "%s%s" % [v.ai.status, " (%.0f m left)" % v.ai.remaining() if v.ai.active else ""]
		if v.has_meta(&"support") and support and support.current() == v:
			doing = "AAV %s; %s" % [support.order_text(), doing]
		elif v.has_meta(&"qrf"):
			doing = "QRF %s; %s" % [String(v.get_meta(&"qrf")), doing]
		lines.append("  %s %s (%s) at (%.0f, %.1f, %.0f)%s | driver %s | aboard %s | damage %s | fuel %.0f L | %s" % [v.vehicle_id, v.model, v.faction,
			p.x, p.y, p.z, " WRECK" if v.wrecked else (" BURNING" if v.is_burning() else (" afloat" if AavWater.afloat(v) else "")),
			String(d.name) if d else "none", ", ".join(riders) if not riders.is_empty() else "nobody",
			", ".join(zones) if not zones.is_empty() else "none", v.fuel_litres(), doing])
	return "\n".join(lines)
