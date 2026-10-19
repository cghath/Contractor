class_name RoadsideIeds
extends Node
## Wave 6: IEDs on the roads. A contract whose briefing's threats include "ied" (contracts.json
## "threats") now has them for real: once it goes live (Contracts.contract_live), COUNT of them
## (picked by the contract id, no RNG drawn) are buried on the zone's roads (def "roads") within
## NEAR_M of its site. Each is a Charges charge with no fuse (every peer sees the device, as any
## placed charge), set off by a friendly stepping on it (TRIGGER_M) or a vehicle with friendlies
## aboard rolling over it (VEHICLE_TRIGGER_M): the charge's blast and frags, Charges._detonate.
##
## Seen first, it can be dealt with: a friendly up and moving slowly (under SPOT_SPEED_MS) within
## SPOT_M spots it ("IED!" on the net and an IED marker on the map); a player crouched within
## DISARM_M of a spotted one for DISARM_S disarms it (the device goes). Numbers Proposed. Host
## only; one node per zone level (ZoneLevel._ready).

const NODE_NAME := "RoadsideIeds"
const THREAT := "ied"
## How many a contract gets: COUNT.x to COUNT.y.
const COUNT := Vector2i(2, 4)
const NEAR_M := 350.0
const ROAD_STEP_M := 20.0
const MIN_APART_M := 40.0
const TRIGGER_M := 1.2
const VEHICLE_TRIGGER_M := 3.0
const SPOT_M := 10.0
const SPOT_SPEED_MS := 3.0
const DISARM_M := 1.8
const DISARM_S := 8.0
const TICK_S := 0.2

## Host: [{"cid", "pos": Vector3, "charge": id, "state" ("armed", "spotted", "off", "disarmed"),
## "disarm": seconds so far}].
var ieds: Array[Dictionary] = []
var _tick := 0.0


static func of(from: Node) -> RoadsideIeds:
	var level := CompoundLevel.current(from)
	return level.get_node_or_null(NODE_NAME) as RoadsideIeds if level else null


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	if multiplayer.is_server():
		Contracts.contract_live.connect(_on_live)


func _on_live(cid: String, _objectives: Array) -> void:
	var c := Contracts.contract(cid)
	if c.is_empty() or not THREAT in (c.get("threats", []) as Array) or ieds.any(func(e: Dictionary) -> bool: return e.cid == cid):
		return
	var level := CompoundLevel.current(self)
	var module: Node3D = level.call(&"get_module", String(c.get("module_id", ""))) if level and level.has_method(&"get_module") else null
	if module:
		server_plant(cid, module.global_position)


## The road points (x, z) within NEAR_M of `site`, every ROAD_STEP_M along the zone's roads.
func road_spots(site: Vector3) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var level := CompoundLevel.current(self)
	var def: Dictionary = level.get(&"def") if level and "def" in level else {}
	var centre := Vector2(site.x, site.z)
	for road: Array in def.get("roads", []):
		var a := Vector2(float(road[0][0]), float(road[0][1]))
		var b := Vector2(float(road[1][0]), float(road[1][1]))
		var steps := maxi(1, floori(a.distance_to(b) / ROAD_STEP_M))
		for i in steps + 1:
			var p := a.lerp(b, float(i) / steps)
			if p.distance_to(centre) <= NEAR_M:
				out.append(p)
	return out


## Host: buries contract `cid`'s IEDs on the roads near `site`. Returns how many.
func server_plant(cid: String, site: Vector3) -> int:
	var level := CompoundLevel.current(self)
	var charges := Charges.of(self)
	if level == null or charges == null:
		return 0
	var spots := road_spots(site)
	var want := COUNT.x + posmod(hash("ied_n:" + cid), COUNT.y - COUNT.x + 1)
	var placed := 0
	var k := 0
	while placed < want and not spots.is_empty() and k < 64:
		var p: Vector2 = spots.pop_at(posmod(hash("ied:%s:%d" % [cid, k]), spots.size()))
		k += 1
		if ieds.any(func(e: Dictionary) -> bool: return Vector2(e.pos.x, e.pos.z).distance_to(p) < MIN_APART_M):
			continue
		var pos: Vector3 = level.call(&"ground_point", Vector3(p.x, 0.0, p.y))
		var id := charges.server_place_at(null, Transform3D(Basis.IDENTITY, pos))
		if id == "":
			continue
		charges._due.erase(id)  # no fuse: it waits for someone to set it off
		ieds.append({"cid": cid, "pos": pos, "charge": id, "state": "armed", "disarm": 0.0})
		placed += 1
	if placed > 0:
		print("[ieds] %d IEDs on the roads round %s" % [placed, cid])
	return placed


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or ieds.is_empty():
		return
	_tick -= delta
	if _tick > 0.0:
		return
	var step := TICK_S - _tick
	_tick = TICK_S
	server_step(step)


## Host: one look at every IED after `dt` seconds.
func server_step(dt: float) -> void:
	var level := CompoundLevel.current(self)
	if level == null:
		return
	var people: Array[Soldier] = []
	people.append_array(MapNodes.players(level))
	people.append_array(MapNodes.squad_ai(level))
	var vehicles := get_tree().get_nodes_in_group(Vehicle.GROUP)
	for e: Dictionary in ieds:
		if String(e.state) not in ["armed", "spotted"]:
			continue
		var pos: Vector3 = e.pos
		var disarming := false
		for s: Soldier in people:
			if not s.vitals.is_up() or Vehicle.ride_of(s) != null:
				continue
			var d := _flat(s.global_position, pos)
			if d <= TRIGGER_M and not (String(e.state) == "spotted" and s.is_crouching()):
				server_set_off(e, s.display_name())
				break
			if String(e.state) == "armed" and d <= SPOT_M and Vector2(s.velocity.x, s.velocity.z).length() < SPOT_SPEED_MS:
				_spot(e, s)
			if String(e.state) == "spotted" and not s.is_ai() and d <= DISARM_M and s.is_crouching():
				disarming = true
		if String(e.state) not in ["armed", "spotted"]:
			continue
		for v: Node in vehicles:
			var car := v as Vehicle
			if car and _flat(car.global_position, pos) <= VEHICLE_TRIGGER_M \
					and car.occupants().any(func(o: Variant) -> bool: return o is Soldier and (o as Soldier).faction == &"friendly"):
				server_set_off(e, car.name)
				break
		if String(e.state) == "spotted":
			e.disarm = float(e.disarm) + dt if disarming else 0.0
			if float(e.disarm) >= DISARM_S:
				server_disarm(e)


func _spot(e: Dictionary, by: Soldier) -> void:
	e.state = "spotted"
	var markers := MapNodes.markers(self)
	if markers:
		markers.server_report_enemy(e.pos, "IED")
	Contracts._notify_all("%s: IED! On the road, %d m. Crouch beside it to disarm it." % [by.display_name(), roundi(_flat(by.global_position, e.pos))])
	print("[ieds] %s spots the IED at (%.0f, %.0f)" % [by.display_name(), e.pos.x, e.pos.z])


## Host: IED `e` goes off (`by`: who set it off, for the log and the net).
func server_set_off(e: Dictionary, by: String) -> void:
	e.state = "off"
	var charges := Charges.of(self)
	if charges and charges.records.has(String(e.charge)):
		charges._detonate(String(e.charge))
	Contracts._notify_all("IED! %s set one off." % by)
	print("[ieds] %s sets off the IED at (%.0f, %.0f)" % [by, e.pos.x, e.pos.z])


## Host: IED `e` is made safe: the device goes.
func server_disarm(e: Dictionary) -> void:
	e.state = "disarmed"
	var charges := Charges.of(self)
	if charges and charges.records.has(String(e.charge)):
		charges._due.erase(String(e.charge))
		charges._client_remove.rpc(String(e.charge))
	Contracts._notify_all("IED disarmed.")
	print("[ieds] IED at (%.0f, %.0f) disarmed" % [e.pos.x, e.pos.z])


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
