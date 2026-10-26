class_name FallenConvoy
extends Node3D
## The live convoy of Contractor: Fallen (docs/survival_events.md section 1b): a "convoy" world
## event in the zone being played comes in as a column on the zone's main road (the longest laid
## road, ZoneRoads) at one edge and moves along it to the other over what is left of its window.
## Host only: one node a live convoy, a child of the SurvivalLevel ("Convoy_<event id>").
##
## - The column (data/survival_convoy.json by who runs it): the enclave's truck (an M-ATV with
##   the cargo) and a technical as escort, 4 guards with rifles; or a trader's cart train (two
##   carts, a horse), 2 guards. A driver for each vehicle, the guards and the trader: 4-8 people.
##   The vehicles are kinematic on the road (frozen, set along it each frame, VehicleAI not used);
##   the people ride with them (pinned at their places) while it moves. The cargo is the cargo
##   vehicle's real hold (rolled from the column's cargo table by the event's id).
## - It stops when blocked: a vehicle or a wreck ("wreck"), anything in the "convoy_blocks" group
##   ("barricade") within block_m on the road ahead; the dead near the lead ("dead"); raiders
##   ("raiders"). Halted, everyone dismounts (their own AI: the guards are a friendly-faction
##   squad of their own, so they shoot the dead and never the players); a wreck or a barricade is
##   pushed off the road after clear_s; the dead and raiders are fought until none are left in
##   reach; then they mount up and go on.
## - Noise: the column is heard every noise_every_s (Survival.server_noise: the dead hear it,
##   the zone's pressure rises like a shot's, scaled by the radius), the guards' shots as any.
## - The players: one walking up openly (up, not aiming) within hail_m hails it: it holds while he
##   stays (hail_hold_s at most) and the trader (a world person, meta "world_person": the talk
##   menu's "Trade" opens the barter screen on his stock) deals; the enclave's only with standing
##   >= its min_standing (Barter.trader_problem reads the record's "min_standing"). Robbing it (a
##   player's hit on one of its people, or its cargo taken from the hold) turns it: its people go
##   hostile and fight, the owner's standing -30, a convoy_robbed event naming the player
##   (WorldEvents.server_convoy_robbed).
## - An ambush (the event's 35% roll with raiders in reach: WorldEvents.ambush_group) plays out
##   live: at ambush_at of the way raiders come out ambush_ahead_m up the road. The guards all
##   down: the column is lost (convoy_ambushed); the raiders all down: it goes on.
## - The far end reached (or its window long over): convoy_passed; its bodies and vehicles go.
## The record keeps "s" (how far it got), "live" (a column is on the road: the far tick leaves it
## alone) and "ambush_by". A zone without a road long enough keeps the wagon cache (WorldEvents).

const PATH := "res://data/survival_convoy.json"
const GROUP := &"fallen_convoys"
const BLOCKS := &"convoy_blocks"
const PREFIX := "Convoy_"

static var _data := {}
## Tests: as if the zone had no road (the wagon cache's fallback).
static var force_no_road := false

var level: SurvivalLevel
var rec: Dictionary = {}
var column := "trader"
var path := PackedVector3Array()
var arcs := PackedFloat32Array()
var length := 0.0
## The lead's distance along the road (m), and its speed (m/s).
var s := 0.0
var speed := 2.0
## moving | halted | hailed | hostile | lost | done
var state := "moving"
## What halted it: "wreck", "barricade", "dead", "raiders" ("" none).
var why := ""
var vehicles: Array[Vehicle] = []
var gaps: Array[float] = []
var people: Array[Soldier] = []
var guards: Array[Soldier] = []
var raiders: Array[Soldier] = []
var trader: Soldier
var trader_id := ""
var cargo_vehicle: Vehicle
var squad: Squad
## Tests step it by hand (server_step) when true; hail_ok false: players walking up don't hail it.
var manual := false
var hail_ok := true
var riding := true

var _places := {}  # person instance id -> [vehicle index, Vector3 offset (vehicle space)]
var _halt_t := 0.0
var _blocker: Node3D
var _cargo_n := -1
var _noise_t := 0.0
var _hits := {}
var _hail_t := 0.0
var _away_t := 0.0
var _said_t := -100.0
var _rng := RandomNumberGenerator.new()


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text()) if f else null
		parsed = ModKit.overlay("survival_convoy", parsed)
		_data = parsed if parsed is Dictionary else {"columns": {}, "tables": {}}
	return _data


static func num(key: String, fallback: float) -> float:
	return float(data().get(key, fallback))


static func column_def(kind: String) -> Dictionary:
	return (data().get("columns", {}) as Dictionary).get(kind, (data().get("columns", {}) as Dictionary).get("trader", {}))


## A table's roll ([{"id", "count"}], by id), seeded by `seed_parts`.
static func roll_table(table: String, seed_parts: Array) -> Array:
	var t: Dictionary = (data().get("tables", {}) as Dictionary).get(table, {})
	return roll_rows(t.get("rows", []), int(t.get("rolls", 0)), seed_parts)


static func roll_rows(rows: Array, rolls: int, seed_parts: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_parts)
	var got := {}
	for i in rolls:
		if rows.is_empty():
			break
		var row: Array = rows[rng.randi_range(0, rows.size() - 1)]
		var id := String(row[0])
		if not ItemDB.has_item(StringName(id)):
			continue
		var n := rng.randi_range(int(row[1]), int(row[2]) if row.size() > 2 else int(row[1]))
		if n > 0:
			got[id] = int(got.get(id, 0)) + n
	var out: Array = []
	for id: String in WorldModel._sorted(got.keys()):
		out.append({"id": id, "count": int(got[id])})
	return out


## The level's main road: the longest laid road's centreline (empty: none long enough).
static func main_road(p_level: Node) -> PackedVector3Array:
	var roads := ZoneRoads.of(p_level)
	var best := PackedVector3Array()
	var best_len := num("min_road_m", 80.0)
	if roads == null or force_no_road:
		return best
	for seg: Dictionary in roads.segments():
		var pts: PackedVector3Array = seg.get("points", PackedVector3Array())
		var l := _length(pts)
		if l > best_len:
			best_len = l
			best = pts
	return best


static func _length(pts: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += pts[i - 1].distance_to(pts[i])
	return l


## The live column of event `id` in `from`'s level, or null.
static func of_event(from: Node, id: int) -> FallenConvoy:
	if from == null or not from.is_inside_tree():
		return null
	for n: Node in from.get_tree().get_nodes_in_group(GROUP):
		var c := n as FallenConvoy
		if c and int(c.rec.get("id", 0)) == id and not c.is_queued_for_deletion():
			return c
	return null


## Host: the column of convoy event `r` on `p_level`'s main road; null when there's no road (the
## wagon cache then: WorldEvents).
static func server_spawn(p_level: SurvivalLevel, r: Dictionary) -> FallenConvoy:
	var have := of_event(p_level, int(r.get("id", 0)))
	if have:
		return have
	var road := main_road(p_level)
	if road.size() < 2 or VehicleLayer.of(p_level) == null:
		return null
	if int(r.get("id", 0)) % 2 == 1:
		road.reverse()  # (which edge it comes in at: by the event)
	var c := FallenConvoy.new()
	c.name = "%s%d" % [PREFIX, int(r.get("id", 0))]
	c.level = p_level
	c.rec = r
	c.path = road
	c.manual = bool(r.get("manual", false))
	p_level.add_child(c)
	c._build()
	return c


func _init() -> void:
	add_to_group(GROUP)
	process_physics_priority = 100  # (after the vehicles' and the people's own steps: they stay put)


func _physics_process(delta: float) -> void:
	if manual or level == null or not multiplayer.is_server():
		return
	server_step(delta)


func _exit_tree() -> void:
	if state in ["moving", "halted", "hailed"]:
		rec["live"] = false  # (the far tick takes it on from here)
		rec["s"] = snappedf(s, 0.1)
	_drop_trader_record()


# --- Building it --------------------------------------------------------------------------------

func _build() -> void:
	_rng.seed = hash([WorldSim.world_seed(), int(rec.get("id", 0)), "convoy"])
	column = String(rec.get("column", "trader"))
	var def := column_def(column)
	arcs.resize(path.size())
	var acc := 0.0
	for i in path.size():
		if i > 0:
			acc += path[i - 1].distance_to(path[i])
		arcs[i] = acc
	length = acc
	var vdefs: Array = def.get("vehicles", [])
	var tail := 0.0
	for vd: Dictionary in vdefs:
		tail = maxf(tail, float(vd.get("gap", 0.0)))
	s = clampf(maxf(float(rec.get("s", 0.0)), tail + 2.0), 0.0, length)
	var left_days := maxf(0.02, float(rec.get("until", 0.0)) - WorldSim.world_now())
	var span: Array = def.get("speed", [1.5, 4.0])
	speed = clampf((length - s) / (left_days * Survival.DAY_MIN * 60.0), float(span[0]), float(span[1]))
	# The vehicles.
	var id := int(rec.get("id", 0))
	for i in vdefs.size():
		var vd: Dictionary = vdefs[i]
		var model := String(vd.get("model", "cart"))
		var xf := _xform_at(s - float(vd.get("gap", 0.0)))
		var v: Vehicle = null
		var vid := "conv%d_%d" % [id, i]
		if Mount.is_mount_model(model):
			v = Mounts.server_spawn(level, model, xf.origin, rad_to_deg(xf.basis.get_euler().y), {"id": vid, "save": false})
		else:
			v = VehicleLayer.of(level).server_spawn(model, xf, "", &"player", vid)
		if v == null:
			continue
		v.set_meta(&"no_save", true)
		v.set_meta(&"fallen_convoy", id)
		v.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		v.freeze = true
		v.global_transform = xf
		vehicles.append(v)
		gaps.append(float(vd.get("gap", 0.0)))
		if String(vd.get("role", "")) == "cargo" and cargo_vehicle == null:
			cargo_vehicle = v
	if cargo_vehicle == null and not vehicles.is_empty():
		cargo_vehicle = vehicles[0]
	if cargo_vehicle and cargo_vehicle.cargo():  # (rolled afresh each time it comes in: its vehicles aren't saved)
		for e: Dictionary in roll_table(String(def.get("cargo", "")), [WorldSim.world_seed(), id, "cargo"]):
			cargo_vehicle.cargo_hold.take(StringName(String(e.id)), int(e.count))
	_cargo_n = _cargo_count()
	# The people: their own squad (friendly: they shoot the dead, never the players).
	squad = Squad.new()
	squad.name = "ConvoySquad_%d" % id
	squad.faction = &"friendly"
	squad.hc_id = StringName("convoy_%d" % id)
	squad.callsign = String(def.get("label", "Convoy"))
	level.add_child(squad)
	var guns: Array = def.get("guns", ["akm"])
	var n_guards := int(def.get("guards", 2))
	var crew := vehicles.size() + n_guards
	for i in crew:
		var vi := i % maxi(1, vehicles.size()) if i < vehicles.size() else (i - vehicles.size()) % maxi(1, vehicles.size())
		var guard := i >= vehicles.size()
		var gun := String(guns[i % guns.size()])
		var loadout: Array = (CompoundLevel.HOSTILE_GUNS.get(gun, CompoundLevel.HOSTILE_GUNS["akm"]) as Array).slice(0, 3) if guard or column == "enclave" else []
		var off := Vector3(2.4 if i % 2 == 0 else -2.4, 0.0, 1.0 + float(i / 2 % 2) * 1.5)
		var at := _place_of(vi, off)
		var who := SurvivorPerson.make(_rng, "conv%d_%d" % [id, i])
		var sol := level.spawn_soldier({"name": ("Convoy_%d_%d" % [id, i]).validate_node_name(), "faction": "friendly", "hc_id": "convoy_%d" % id,
			"variant": String(who.look), "body": VoxelArt.FEMALE if String(who.sex) == "f" else VoxelArt.MALE, "face": String(who.face),
			"person_name": String(who.name), "nation": "US", "pos": at, "loadout": loadout, "role": "", "team": -1, "slot": -1,
			"combat": 0.5, "discipline": 0.6, "guard": false, "mode": "aware", "no_pockets": true, "spawn_id": "conv%d_%d" % [id, i]})
		if sol == null:
			continue
		sol.set_meta(&"fallen_convoy", id)
		sol.set_meta(&"survivor_name", String(who.name))
		people.append(sol)
		if guard:
			guards.append(sol)
		_places[sol.get_instance_id()] = [vi, off]
	var men := squad.members()
	if not men.is_empty():
		squad.leader = men[0]
		squad.hero = men[0]
	_make_trader(def)
	if not rec.has("ambush_by"):
		var g: Dictionary = WorldEvents.ambush_group(WorldSim.model(), rec)
		rec["ambush_by"] = String(g.get("id", "")) if not g.is_empty() else "-"
	rec["live"] = true
	rec["live_spawned"] = true
	_place_all()
	SessionLog.note("survival convoy: %s column live (%d vehicles, %d people) on a %.0f m road at %.1f m/s" % [column, vehicles.size(), people.size() + (1 if trader else 0), length, speed])


## The trader: a world person (Barter's record in WorldSim.people(), status "convoy") with the
## column's stock as his kit; the enclave's is its quartermaster's man, sold to by standing.
func _make_trader(def: Dictionary) -> void:
	if level.people == null:
		return
	var id := int(rec.get("id", 0))
	trader_id = "conv%d_trader" % id
	var r := SurvivorPerson.make(_rng, trader_id, {"disposition": "friendly"})
	r.status = "convoy"
	r.zone = WorldSim.hosted_zone()
	r.kit = roll_table(String(def.get("stock", "")), [WorldSim.world_seed(), id, "stock"])
	r["convoy"] = id
	r["role"] = "trader"
	r["min_standing"] = float(def.get("min_standing", -40.0))
	if column == "enclave" and String(rec.get("group", "")) != "":
		r["world_group"] = String(rec.group)
		r["enclave"] = true
		r["enclave_quartermaster"] = true
	WorldSim.people()[trader_id] = r
	var at := _place_of(0, Vector3(-2.4, 0.0, -1.0))
	trader = level.people.server_spawn_person({"name": ("Convoy_%d_trader" % id).validate_node_name(), "kind": "survivor", "side": "neutral",
		"label": String(r.name), "pos": at, "look": String(r.look), "face": String(r.get("face", ""))})
	if trader:
		trader.set_meta(&"world_person", trader_id)
		if r.has("world_group"):
			trader.set_meta(&"world_group", String(r.world_group))
		trader.set_meta(&"survivor_name", String(r.name))
		trader.set_meta(&"fallen_convoy", id)
		_places[trader.get_instance_id()] = [0, Vector3(-2.4, 0.0, -1.0)]


func _drop_trader_record() -> void:
	if trader_id != "" and WorldSim.people().has(trader_id) and String((WorldSim.people()[trader_id] as Dictionary).get("status", "")) == "convoy":
		WorldSim.people().erase(trader_id)


# --- The road -----------------------------------------------------------------------------------

## The point `d` metres along the road (clamped to it).
func point_at(d: float) -> Vector3:
	if path.is_empty():
		return Vector3.ZERO
	d = clampf(d, 0.0, length)
	var i := arcs.bsearch(d)
	if i <= 0:
		return path[0]
	if i >= path.size():
		return path[path.size() - 1]
	var a := arcs[i - 1]
	var b := arcs[i]
	return path[i - 1].lerp(path[i], (d - a) / maxf(0.001, b - a))


func dir_at(d: float) -> Vector3:
	var a := point_at(d - 2.0)
	var b := point_at(d + 2.0)
	var v := Vector3(b.x - a.x, 0.0, b.z - a.z)
	return v.normalized() if v.length() > 0.01 else Vector3.FORWARD


func _xform_at(d: float) -> Transform3D:
	var dir := dir_at(d)
	return Transform3D(Basis.looking_at(dir, Vector3.UP), point_at(d))


## How far along the road the point nearest `p` is, and how far off it (m): [along, off].
func along_of(p: Vector3) -> Array[float]:
	var best_d := INF
	var best_a := 0.0
	for i in range(1, path.size()):
		var a := Vector2(path[i - 1].x, path[i - 1].z)
		var b := Vector2(path[i].x, path[i].z)
		var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), a, b)
		var dd := q.distance_to(Vector2(p.x, p.z))
		if dd < best_d:
			best_d = dd
			best_a = arcs[i - 1] + a.distance_to(q)
	return [best_a, best_d]


## The column's people with the trader.
func everyone() -> Array[Soldier]:
	var out: Array[Soldier] = people.duplicate()
	if trader:
		out.append(trader)
	return out


func lead() -> Vehicle:
	for v: Vehicle in vehicles:
		if is_instance_valid(v):
			return v
	return null


func lead_pos() -> Vector3:
	return point_at(s)


func _place_of(vi: int, off: Vector3) -> Vector3:
	var d := s - (gaps[vi] if vi < gaps.size() else 0.0)
	var xf := _xform_at(d)
	return level.ground_point(xf * off)


func _place_all() -> void:
	for i in vehicles.size():
		var v := vehicles[i]
		if not is_instance_valid(v) or v.wrecked:
			continue
		if not v.freeze:
			v.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			v.freeze = true
		v.global_transform = _xform_at(s - gaps[i])
	if riding:
		for p: Soldier in everyone():
			_pin(p)


func _pin(p: Soldier) -> void:
	if p == null or not is_instance_valid(p) or not p.vitals.is_up():
		return
	var pl: Array = _places.get(p.get_instance_id(), [0, Vector3.ZERO])
	p.global_position = _place_of(int(pl[0]), pl[1])
	p.velocity = Vector3.ZERO


# --- The step (host) ------------------------------------------------------------------------------

func server_step(delta: float) -> void:
	if state in ["done", "lost"] or level == null:
		return
	_check_hits()
	_check_cargo()
	if state == "hostile":
		return
	if _alive(guards) == 0 and not guards.is_empty() and not raiders.is_empty():
		_lost_to_raiders()
		return
	if not bool(rec.get("ambush_spawned", false)) and String(rec.get("ambush_by", "-")) not in ["", "-"] and s >= length * num("ambush_at", 0.35):
		server_spawn_ambush()
	_noise_t -= delta
	if _noise_t <= 0.0 and riding:
		_noise_t = num("noise_every_s", 3.0)
		var lv := lead()
		if lv:
			Survival.server_noise(lv, lv.global_position, float(column_def(column).get("noise_m", 40.0)), ZombieAI.HEAR_RUN)
	var block := blocker_ahead()
	if not block.is_empty():
		_halt(String(block.kind), block.get("node") as Node3D, delta)
		return
	if _hailed(delta):
		return
	if state != "moving":
		_mount_up()
	state = "moving"
	why = ""
	_halt_t = 0.0
	s = minf(length, s + speed * delta)
	rec["s"] = snappedf(s, 0.1)
	_place_all()
	if s >= length - 0.5 or WorldSim.world_now() > float(rec.get("until", 0.0)) + 0.25:
		_arrive()


## What blocks the road ahead: {"kind": "wreck" | "barricade" | "dead" | "raiders", "node"}, or {}.
func blocker_ahead() -> Dictionary:
	var lp := lead_pos()
	for r: Soldier in raiders:
		if is_instance_valid(r) and r.vitals.is_up() and r.global_position.distance_to(lp) <= num("raider_block_m", 110.0):
			return {"kind": "raiders", "node": r}
	for z: Soldier in Survival.zombies(level):
		if z.global_position.distance_to(lp) <= num("dead_block_m", 22.0):
			return {"kind": "dead", "node": z}
	var reach := num("block_m", 14.0)
	var layer := VehicleLayer.of(level)
	if layer:
		for v: Vehicle in layer.vehicles():
			if v in vehicles or v.has_meta(&"convoy_cleared"):
				continue
			if _on_road_ahead(v.global_position, reach, 3.5):
				return {"kind": "wreck", "node": v}
	for n: Node in get_tree().get_nodes_in_group(BLOCKS):
		var b := n as Node3D
		if b and not b.is_queued_for_deletion() and not b.has_meta(&"convoy_cleared") and _on_road_ahead(b.global_position, reach, 3.5):
			return {"kind": "barricade", "node": b}
	return {}


func _on_road_ahead(p: Vector3, reach: float, half_w: float) -> bool:
	if p.distance_to(lead_pos()) > reach + 20.0:
		return false
	var ao := along_of(p)
	return ao[0] > s - 1.0 and ao[0] <= s + reach and ao[1] <= half_w


func _halt(kind: String, node: Node3D, delta: float) -> void:
	if state != "halted" or why != kind:
		_say(String(_line("halt_" + ("wreck" if kind in ["wreck", "barricade"] else kind))))
		_halt_t = 0.0
	state = "halted"
	why = kind
	_blocker = node
	_halt_t += delta
	_dismount()
	if kind in ["wreck", "barricade"] and _halt_t >= num("clear_s", 8.0) and is_instance_valid(node):
		_clear(node)


## A wreck or a barricade pushed off the road (the guards' work): clear_aside_m to the side.
func _clear(node: Node3D) -> void:
	var dir := dir_at(along_of(node.global_position)[0])
	var side := Vector3(-dir.z, 0.0, dir.x)
	var off := node.global_position - point_at(along_of(node.global_position)[0])
	if off.dot(side) < 0.0:
		side = -side
	var to := level.ground_point(node.global_position + side * num("clear_aside_m", 9.0))
	if node is RigidBody3D:
		var rb := node as RigidBody3D
		rb.linear_velocity = Vector3.ZERO
		var xf := rb.global_transform
		xf.origin = to + Vector3.UP * 0.2
		rb.global_transform = xf
	else:
		node.global_position = to
	node.set_meta(&"convoy_cleared", true)
	SessionLog.note("survival convoy %d: cleared a %s off the road" % [int(rec.get("id", 0)), why])


func _dismount() -> void:
	if not riding:
		return
	riding = false
	for p: Soldier in people:
		if is_instance_valid(p) and p.vitals.is_up():
			var dir := dir_at(s)
			p.global_position = level.ground_point(p.global_position + Vector3(-dir.z, 0.0, dir.x) * (1.5 if p.get_index() % 2 == 0 else -1.5))


func _mount_up() -> void:
	if riding:
		return
	riding = true
	_say(String(_line("moving")))


func _hailed(delta: float) -> bool:
	var hm := num("hail_m", 18.0)
	var by: Soldier = null
	for p: Soldier in MapNodes.players(level):
		if not p.vitals.is_up() or p.is_aiming:
			continue
		var near := p.global_position.distance_to(lead_pos()) <= hm or (trader and is_instance_valid(trader) and p.global_position.distance_to(trader.global_position) <= hm)
		if near:
			by = p
			break
	if state == "hailed":
		_hail_t += delta
		var stay := false
		for p: Soldier in MapNodes.players(level):
			if p.vitals.is_up() and p.global_position.distance_to(lead_pos()) <= num("hail_leave_m", 30.0):
				stay = true
		_away_t = 0.0 if stay else _away_t + delta
		if _away_t < 5.0 and _hail_t < num("hail_hold_s", 120.0):
			return true
		rec["hailed_out"] = true
		return false
	if by and hail_ok and not bool(rec.get("hailed_out", false)):
		server_hail(by)
		return true
	return false


## Host: `by` hails the column: it holds, the trader steps down and offers to trade (the barter
## screen is the talk menu's Trade on him, or `open` here). Returns the line said.
func server_hail(by: Soldier, open := false) -> String:
	if state in ["hostile", "lost", "done"]:
		return ""
	state = "hailed"
	why = ""
	_hail_t = 0.0
	_away_t = 0.0
	_dismount()
	var r: Dictionary = WorldSim.people().get(trader_id, {})
	var problem := Barter.trader_problem(r)
	var line := String(_line("hail")) if problem == "" else String(_line("no_sale"))
	if trader and is_instance_valid(trader):
		_say_by(trader, line)
	if open and by and Intel.get_intel():
		Intel.get_intel().server_send_deal(by, Barter.deal(by, r))
	return line


# --- Robbery, the ambush, the end -------------------------------------------------------------------

func _check_hits() -> void:
	for p: Soldier in everyone():
		if not is_instance_valid(p):
			continue
		var info: Dictionary = p.get_meta(Harm.META, {})
		var at := float(info.get("at", -1.0))
		if bool(info.get("player", false)) and at > float(_hits.get(p.get_instance_id(), -1.0)):
			_hits[p.get_instance_id()] = at
			if state != "hostile":
				server_rob(get_node_or_null(NodePath(String(info.get("path", "")))) as Soldier, "attacked")


func _cargo_count() -> int:
	if cargo_vehicle == null or not is_instance_valid(cargo_vehicle) or cargo_vehicle.cargo_hold == null:
		return 0
	var n := 0
	for e: Dictionary in cargo_vehicle.cargo_hold.entries():
		n += int(e.get("count", 1))
	return n


func _check_cargo() -> void:
	var n := _cargo_count()
	if _cargo_n >= 0 and n < _cargo_n and state != "hostile":
		var thief: Soldier = null
		var best := INF
		for p: Soldier in MapNodes.players(level):
			var d := p.global_position.distance_to(cargo_vehicle.global_position) if is_instance_valid(cargo_vehicle) else INF
			if d < best:
				best = d
				thief = p
		server_rob(thief, "took from the cargo")
	_cargo_n = n


## Host: the players rob the column (`by`: who): its people turn on them (hostile), the owner's
## standing falls, an event names him (WorldEvents.server_convoy_robbed).
func server_rob(by: Soldier, how := "robbed") -> void:
	if state in ["hostile", "done"]:
		return
	state = "hostile"
	riding = false
	_say(String(_line("robbed")))
	if squad:
		squad.faction = &"hostile"
	for p: Soldier in people:
		if is_instance_valid(p):
			p.faction = &"hostile"
			var brain := SquadAI.of(p)
			if brain:
				brain.hold_fire = false
	rec["live"] = false
	WorldEvents.server_convoy_robbed(rec, by)
	SessionLog.note("survival convoy %d: %s by %s" % [int(rec.get("id", 0)), how, by.display_name() if by else "someone"])


## Host: the raiders of the ambush come out ambush_ahead_m up the road, either side of it.
func server_spawn_ambush() -> Array[Soldier]:
	rec["ambush_spawned"] = true
	var id := int(rec.get("id", 0))
	var span: Array = data().get("raiders", [3, 5])
	var n := _rng.randi_range(int(span[0]), int(span[1]))
	var gid := String(rec.get("ambush_by", ""))
	var g := WorldSim.group(gid)
	var rsq := Squad.new()
	rsq.name = "ConvoyAmbush_%d" % id
	rsq.faction = &"hostile"
	rsq.hc_id = StringName("convoy_amb_%d" % id)
	rsq.callsign = String(g.get("name", "Raiders"))
	level.add_child(rsq)
	var at_d := minf(length, s + num("ambush_ahead_m", 90.0))
	var dir := dir_at(at_d)
	var side := Vector3(-dir.z, 0.0, dir.x)
	var guns := ["akm", "ak74", "akm", "rpk"]
	for i in n:
		var who := SurvivorPerson.make(_rng, "amb%d_%d" % [id, i])
		var at := level.ground_point(point_at(at_d + float(i) * 4.0) + side * (9.0 + float(i % 3) * 3.0) * (1.0 if i % 2 == 0 else -1.0))
		var r := level.spawn_soldier({"name": ("ConvoyAmbush_%d_%d" % [id, i]).validate_node_name(), "faction": "hostile", "hc_id": "convoy_amb_%d" % id,
			"variant": String(who.look), "body": VoxelArt.FEMALE if String(who.sex) == "f" else VoxelArt.MALE, "face": String(who.face),
			"person_name": String(who.name), "nation": "US", "pos": at, "loadout": (CompoundLevel.HOSTILE_GUNS[guns[i % guns.size()]] as Array).slice(0, 3),
			"role": "", "team": 0, "slot": -1, "combat": 0.45, "discipline": 0.4, "guard": false, "mode": "aware", "no_pockets": true, "spawn_id": "amb%d_%d" % [id, i]})
		if r:
			r.set_meta(&"fallen_convoy_ambush", id)
			r.set_meta(&"world_group", gid)
			raiders.append(r)
	var men := rsq.members()
	if not men.is_empty():
		rsq.leader = men[0]
		rsq.hero = men[0]
	SessionLog.note("survival convoy %d: %d raiders of %s waiting %.0f m up the road" % [id, raiders.size(), String(g.get("name", gid)), at_d - s])
	return raiders


func _lost_to_raiders() -> void:
	state = "lost"
	rec["live"] = false
	var gid := String(rec.get("ambush_by", ""))
	var g := WorldSim.group(gid)
	var def: Dictionary = WorldEvents.kind_def("convoy")
	WorldEvents.server_end_live(rec, "ambushed", "convoy_ambushed", String(def.get("ambushed", "")).format({"group": String(g.get("name", "Raiders")),
		"column": column, "zone": RegionMap.zone_name(String(rec.get("zone", "")))}), [gid] if gid != "" else [])
	var col := String(rec.get("group", ""))
	var sim := WorldSim.get_sim()
	if sim and col != "" and gid != "":
		sim.mutate(func(w: Dictionary) -> void:
			var cg: Dictionary = (w.get("groups", {}) as Dictionary).get(col, {})
			if not cg.is_empty():
				(cg.relations as Dictionary)[gid] = float((cg.relations as Dictionary).get(gid, 0.0)) - 30.0)


## The far end reached: convoy_passed, and the column leaves the zone (its bodies and vehicles go).
func _arrive() -> void:
	state = "done"
	rec["live"] = false
	var def: Dictionary = WorldEvents.kind_def("convoy")
	WorldEvents.server_end_live(rec, "passed", "convoy_passed", String(def.get("passed", "")).format({"column": column,
		"zone": RegionMap.zone_name(String(rec.get("zone", "")))}), [])
	server_despawn()


## Host: the column's living bodies and its vehicles gone (it left the zone).
func server_despawn() -> void:
	for p: Soldier in everyone():
		if is_instance_valid(p) and not p.vitals.is_dead():
			p.queue_free()
	for v: Vehicle in vehicles:
		if is_instance_valid(v) and not v.wrecked:
			v.queue_free()
	if squad and is_instance_valid(squad):
		squad.queue_free()
	_drop_trader_record()
	queue_free()


static func _alive(list: Array[Soldier]) -> int:
	var n := 0
	for p: Soldier in list:
		if is_instance_valid(p) and p.vitals.is_up():
			n += 1
	return n


func _line(topic: String) -> String:
	var lines: Array = (data().get("lines", {}) as Dictionary).get(topic, [])
	return String(lines[_rng.randi_range(0, lines.size() - 1)]) if not lines.is_empty() else ""


func _say(text: String) -> void:
	for p: Soldier in people:
		if is_instance_valid(p) and p.vitals.is_up():
			_say_by(p, text)
			return


func _say_by(sp: Soldier, text: String) -> void:
	var now := Soldier._now()
	if text == "" or now - _said_t < 2.0:
		return
	_said_t = now
	var layer := SurvivorsLayer.find(level)
	if layer:
		layer.say(sp, text)
