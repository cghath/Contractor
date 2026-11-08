class_name FallenConvoy
extends Node3D
## The live convoy of Contractor: Fallen (docs/survival_events.md section 1b): a "convoy" world
## event in the zone being played comes in as a column on the road (ConvoyRoad: from the edge it
## came through to the edge it's bound for; else the longest laid road, ZoneRoads) and moves along
## it over what is left of its window. Host only: one node a live convoy, a child of the
## SurvivalLevel ("Convoy_<event id>").
##
## - The column (data/survival_convoy.json by who runs it): the enclave's truck (an M-ATV with
##   the cargo) and a technical as escort, 4 guards with rifles; or a trader's cart train (two
##   carts, a horse), 2 guards. A driver for each vehicle, the guards and the trader: 4-8 people,
##   seated in or on the vehicles while it moves (the drivers at the wheel, the guards in the
##   passenger seats, the open ones first; the trader walks beside his cart, the enclave's man
##   rides). The cargo is the cargo vehicle's real hold (rolled from the column's cargo table by
##   the event's id).
## - Motor columns ("drive" in the data) really drive: each truck under VehicleAI on the road ahead,
##   the column in order by ConvoyColumn.follow_speed, while a player is within drive_near_m. Out
##   of sight, for carts and horses (a Mount's drive is a scripted glide, and a cart with no horse
##   in its shafts can't go), and across a site two roads only meet at (no road there: a compound's
##   walls), it slides: frozen and set along the road each frame. A truck
##   stuck (no progress for stuck_s), off the road or overturned is recovered: frozen back onto the
##   road for recover_s, then driven again, recover_max times; after that it slides.
## - It stops when blocked: a vehicle or a wreck ("wreck"), anything in the "convoy_blocks" group
##   ("barricade") within block_m on the road ahead; the dead near the lead ("dead"); raiders
##   ("raiders"). Halted, everyone dismounts (their own AI: the guards are a friendly-faction
##   squad of their own, so they shoot the dead and never the players); a wreck or a barricade is
##   pushed off the road after clear_s; the dead and raiders are fought until none are left in
##   reach; then they walk back and mount up (mount_s at most) and go on.
## - Noise: the column is heard every noise_every_s (Survival.server_noise: the dead hear it,
##   the zone's pressure rises like a shot's, scaled by the radius), the guards' shots as any.
## - The players: one walking up openly (up, not aiming) within hail_m hails it: it holds while he
##   stays (hail_hold_s at most) and the trader (a world person, meta "world_person": the talk
##   menu's "Trade" opens the barter screen on his stock) deals; the enclave's only with standing
##   >= its min_standing (Barter.trader_problem reads the record's "min_standing"). Robbing it (a
##   player's hit on one of its people, its cargo taken from the hold, or driving off in one of its
##   vehicles: steal_m with a stranger at the wheel) turns it: its people go hostile and fight, the
##   owner's standing -30, a convoy_robbed event naming the player (WorldEvents.server_convoy_robbed).
##   Somebody at one of its wheels holds the column until he gets out or drives off. A vehicle left
##   when its crew all died, or given away (server_give_vehicle), is nobody's: no crime to take it.
## - An ambush (the event's 35% roll with raiders in reach: WorldEvents.ambush_group) plays out
##   live: at ambush_at of the way raiders come out ambush_ahead_m up the road. The guards all
##   down: the column is lost (convoy_ambushed); the raiders all down: it goes on.
## - The far end reached (or its window long over): on into the next zone in the world sim, with
##   what's left of it (WorldEvents.server_convoy_cross), or convoy_passed at the end of its way;
##   its bodies and vehicles go.
## The record keeps "s" (how far it got), "live" (a column is on the road: the far tick leaves it
## alone), "ambush_by" and "carry" (the survivors, the vehicles' condition, the cargo and the stock:
## what the next spawn builds). A zone without a road long enough keeps the wagon cache (WorldEvents).

const PATH := "res://data/survival_convoy.json"
const GROUP := &"fallen_convoys"
const BLOCKS := &"convoy_blocks"
const PREFIX := "Convoy_"
## Proposed: how often (s) the column looks about and gives its drivers their road; the physics
## step only moves what's sliding. A truck needs speed under this to be told to stop.
const THINK_S := 0.25
const STOP_MS := 0.4
## Proposed: how often the record's "carry" is refreshed (s).
const CARRY_S := 5.0
## Road points a driver is given: from this far ahead of him (m).
const STEER_FROM_M := 5.0

static var _data := {}
## Tests: as if the zone had no road (the wagon cache's fallback).
static var force_no_road := false
## Tests: motor columns drive for real wherever the players are.
static var force_drive := false

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
## What halted it: "wreck", "barricade", "dead", "raiders", "wheel" ("" none).
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
## Whether this column's motor vehicles drive for real (the column's "drive"), and tests' count of
## recoveries (the kinematic fallback).
var drive_col := false
var recoveries := 0

var _places := {}  # person instance id -> [vehicle index, Vector3 offset (vehicle space)]: unseated, walks beside
var _seats := {}  # person instance id -> [vehicle index, seat]
var _vs: Array[Dictionary] = []  # per vehicle: {"idx", "driven", "s", "off", "stuck", "at_s", "recover", "recovers", "want"}
var _crew_i := {}  # person instance id -> his index in the column's crew (who he is, next zone too)
var _crew_n := -1
var _gaps: Array = []  # [from, to] (m along the road): stretches with no road to drive (measure_road)
var _mounting := false
var _mount_t := 0.0
var _think_t := 0.0
var _carry_t := 0.0
var _taken := {}  # vehicle instance id -> {"by": Soldier, "from": Vector3}: a stranger at its wheel
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


## The way a column of event `r` takes through `p_level`: from the edge it came in by to the edge
## it's bound for (ConvoyRoad); no way through: the main road, which end it starts from by the event.
static func road_for(p_level: Node, r: Dictionary) -> PackedVector3Array:
	var roads := ZoneRoads.of(p_level)
	if roads == null or force_no_road:
		return PackedVector3Array()
	var way := ConvoyRoad.between_exits(roads, String(r.get("from", "")), String(r.get("to", "")))
	if way.size() >= 2 and _length(way) >= num("min_road_m", 80.0):
		return way
	var road := main_road(p_level)
	if road.size() >= 2 and int(r.get("id", 0)) % 2 == 1:
		road.reverse()  # (which edge it comes in at: by the event)
	return road


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


## Host: the column of convoy event `r` on `p_level`'s road; null when there's no road (the wagon
## cache then: WorldEvents).
static func server_spawn(p_level: SurvivalLevel, r: Dictionary) -> FallenConvoy:
	var have := of_event(p_level, int(r.get("id", 0)))
	if have:
		return have
	var road := road_for(p_level, r)
	if road.size() < 2 or VehicleLayer.of(p_level) == null:
		return null
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
		_write_carry()
		_stick()
	_drop_trader_record()


# --- Building it --------------------------------------------------------------------------------

func _build() -> void:
	_rng.seed = hash([WorldSim.world_seed(), int(rec.get("id", 0)), "convoy"])
	column = String(rec.get("column", "trader"))
	var def := column_def(column)
	drive_col = bool(def.get("drive", false))
	measure_road()
	var carry: Dictionary = rec.get("carry", {}) if rec.get("carry") is Dictionary else {}
	var vdefs: Array = def.get("vehicles", [])
	var kept: Array = []  # [index in vdefs, its condition or {}]
	if carry.has("vehicles"):
		for e: Dictionary in carry.vehicles:
			kept.append([int(e.get("i", 0)), e.get("cond", {})])
	else:
		for i in vdefs.size():
			kept.append([i, {}])
	var first_gap := float(vdefs[int(kept[0][0])].get("gap", 0.0)) if not kept.is_empty() else 0.0
	var tail := 0.0
	for k: Array in kept:
		tail = maxf(tail, float(vdefs[int(k[0])].get("gap", 0.0)) - first_gap)
	s = clampf(maxf(float(rec.get("s", 0.0)), tail + 2.0), 0.0, length)
	var left_days := maxf(0.02, float(rec.get("until", 0.0)) - WorldSim.world_now())
	var span: Array = def.get("speed", [1.5, 4.0])
	speed = clampf((length - s) / (left_days * Survival.DAY_MIN * 60.0), float(span[0]), float(span[1]))
	# The vehicles (those that came through, as they were).
	var id := int(rec.get("id", 0))
	for k: Array in kept:
		var i := int(k[0])
		var vd: Dictionary = vdefs[i]
		var gap := float(vd.get("gap", 0.0)) - first_gap
		var model := String(vd.get("model", "cart"))
		var xf := _xform_at(s - gap)
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
		if k[1] is Dictionary and not (k[1] as Dictionary).is_empty():
			v.apply_condition(GameState.from_json(k[1]))
		if VehicleWear.ground_vehicle(v):
			VehicleWear.of(v)["fuel_day"] = float(Survival.day())  # (the enclave's tanks are fresh: no stale-fuel stalls)
		vehicles.append(v)
		gaps.append(gap)
		_vs.append({"idx": i, "driven": false, "s": s - gap, "off": 0.0, "stuck": 0.0, "at_s": s - gap, "recover": 0.0, "recovers": 0, "want": 0.0})
		if String(vd.get("role", "")) == "cargo" and cargo_vehicle == null:
			cargo_vehicle = v
	if cargo_vehicle == null and not vehicles.is_empty():
		cargo_vehicle = vehicles[0]
	if cargo_vehicle and cargo_vehicle.cargo():
		var load_list: Array = carry.cargo if carry.get("cargo") is Array else roll_table(String(def.get("cargo", "")), [WorldSim.world_seed(), id, "cargo"])
		for e: Dictionary in load_list:  # (rolled the first time it comes in; after that what it carried)
			cargo_vehicle.cargo_hold.take(StringName(String(e.id)), int(e.count), e.get("state", {}) if e.get("state") is Dictionary else {})
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
	var crew := vdefs.size() + n_guards
	var who_lives: Array = carry.crew if carry.get("crew") is Array else range(crew)
	var ordinal := 0
	for raw: Variant in who_lives:
		var i := int(raw)
		var vi := ordinal % maxi(1, vehicles.size())
		var guard := ordinal >= vehicles.size()
		var gun := String(guns[i % guns.size()])
		var loadout: Array = (CompoundLevel.HOSTILE_GUNS.get(gun, CompoundLevel.HOSTILE_GUNS["akm"]) as Array).slice(0, 3) if guard or column == "enclave" else []
		var off := Vector3(2.4 if ordinal % 2 == 0 else -2.4, 0.0, 1.0 + float(ordinal / 2 % 2) * 1.5)
		var at := _place_of(vi, off)
		var prng := RandomNumberGenerator.new()
		prng.seed = hash([WorldSim.world_seed(), id, i, "person"])  # (the same people, whichever zone they reach)
		var who := SurvivorPerson.make(prng, "conv%d_%d" % [id, i])
		var sol := level.spawn_soldier({"name": ("Convoy_%d_%d" % [id, i]).validate_node_name(), "faction": "friendly", "hc_id": "convoy_%d" % id,
			"variant": String(who.look), "body": VoxelArt.FEMALE if String(who.sex) == "f" else VoxelArt.MALE, "face": String(who.face),
			"person_name": String(who.name), "nation": "US", "pos": at, "loadout": loadout, "role": "", "team": -1, "slot": -1,
			"combat": 0.5, "discipline": 0.6, "guard": false, "mode": "aware", "no_pockets": true, "spawn_id": "conv%d_%d" % [id, i]})
		ordinal += 1
		if sol == null:
			continue
		sol.set_meta(&"fallen_convoy", id)
		sol.set_meta(&"survivor_name", String(who.name))
		people.append(sol)
		_crew_i[sol.get_instance_id()] = i
		if guard:
			guards.append(sol)
		_places[sol.get_instance_id()] = [vi, off]
	var men := squad.members()
	if not men.is_empty():
		squad.leader = men[0]
		squad.hero = men[0]
	_make_trader(def, carry)
	if not rec.has("ambush_by"):
		var g: Dictionary = WorldEvents.ambush_group(WorldSim.model(), rec)
		rec["ambush_by"] = String(g.get("id", "")) if not g.is_empty() else "-"
	rec["live"] = true
	rec["live_spawned"] = true
	_crew_n = _alive(people)
	_assign_seats()
	_board_all()
	_place_all()
	_write_carry()
	SessionLog.note("survival convoy: %s column live (%d vehicles, %d people%s) on a %.0f m road at %.1f m/s" % [column, vehicles.size(), people.size() + (1 if trader else 0), ", came through from %s" % String(rec.from) if rec.has("from") else "", length, speed])


## The trader: a world person (Barter's record in WorldSim.people(), status "convoy") with the
## column's stock as his kit; the enclave's is its quartermaster's man, sold to by standing.
func _make_trader(def: Dictionary, carry: Dictionary) -> void:
	if level.people == null or (carry.has("trader") and not bool(carry.trader)):
		return
	var id := int(rec.get("id", 0))
	trader_id = "conv%d_trader" % id
	var r := SurvivorPerson.make(_rng, trader_id, {"disposition": "friendly"})
	r.status = "convoy"
	r.zone = WorldSim.hosted_zone()
	r.kit = carry.stock if carry.get("stock") is Array else roll_table(String(def.get("stock", "")), [WorldSim.world_seed(), id, "stock"])
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


## The record as the world has it now (the far tick's worker replaces the world section: a record
## held from before it would go stale, and the event would never close).
func _refresh_record() -> void:
	var fresh := WorldEvents.record(WorldSim.section(), int(rec.get("id", 0)))
	if not fresh.is_empty():
		rec = fresh


## This record's fields, also onto a far step's result if one is out on the worker (WorldSim.mutate).
func _stick() -> void:
	var sim := WorldSim.get_sim()
	if sim == null:
		return
	var id := int(rec.get("id", 0))
	var copy := rec.duplicate(true)
	sim.mutate(func(w: Dictionary) -> void:
		var r := WorldEvents.record(w, id)
		if not r.is_empty():
			r.merge(copy, true))


## What's left of the column, for the record: who's alive (their crew index), the vehicles (their
## place in the column's list and their condition), the cargo, the trader's stock.
func _write_carry() -> void:
	var crew: Array = []
	for p: Soldier in people:
		if is_instance_valid(p) and p.vitals.is_up():
			crew.append(int(_crew_i.get(p.get_instance_id(), 0)))
	var vs: Array = []
	for i in vehicles.size():
		var v := vehicles[i]
		if not is_instance_valid(v) or v.wrecked:
			continue
		var c := v.condition()
		c.erase("carves")  # (the shot-up look stays behind; a save's size isn't worth it)
		vs.append({"i": int(_vs[i].idx), "cond": c})
	var hold: Array = []
	if cargo_vehicle and is_instance_valid(cargo_vehicle) and cargo_vehicle.cargo_hold:
		for e: Dictionary in cargo_vehicle.cargo_hold.entries():
			var row := {"id": String(e.id), "count": int(e.get("count", 1))}
			if e.get("state") is Dictionary and not (e.state as Dictionary).is_empty():
				row["state"] = (e.state as Dictionary).duplicate(true)
			hold.append(row)
	var out: Dictionary = {"crew": crew, "vehicles": vs, "cargo": hold}
	var tr: Dictionary = WorldSim.people().get(trader_id, {})
	var up := trader != null and is_instance_valid(trader) and trader.vitals.is_up()
	out["trader"] = up
	if up and not tr.is_empty():
		out["stock"] = (tr.get("kit", []) as Array).duplicate(true)
	rec["carry"] = out


# --- The road -----------------------------------------------------------------------------------

## The way's arcs and length, and its gaps: where two roads meet only at a site between them (a
## compound's walls, a stretch ConvoyRoad had to bridge in a straight line) nothing can be driven,
## from gap_before_m short of it (the wall's in front of the truck by then) to gap_after_m past it.
func measure_road() -> void:
	arcs.resize(path.size())
	_gaps.clear()
	var acc := 0.0
	for i in path.size():
		if i > 0:
			var leg := path[i - 1].distance_to(path[i])
			if leg > num("gap_leg_m", 12.0):
				_gaps.append([acc - num("gap_before_m", 25.0), acc + leg + num("gap_after_m", 25.0)])
			acc += leg
		arcs[i] = acc
	length = acc


## Whether `d` metres along the way is in one of its gaps (the column slides through those).
func in_gap(d: float) -> bool:
	for g: Array in _gaps:
		if d >= float(g[0]) and d <= float(g[1]):
			return true
	return false


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
	return _along_in(p, 1, path.size())


## As along_of, looking only at the legs within 50 m before `hint` and 70 m after it (cheap, and
## it can't jump to another stretch of a road that doubles back).
func _along_near(p: Vector3, hint: float) -> Array[float]:
	return _along_in(p, maxi(arcs.bsearch(hint - 50.0), 1), mini(arcs.bsearch(hint + 70.0) + 1, path.size()))


func _along_in(p: Vector3, from_i: int, to_i: int) -> Array[float]:
	var best_d := INF
	var best_a := 0.0
	for i in range(from_i, to_i):
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
		if is_instance_valid(v) and not v.wrecked:
			return v
	return null


func lead_pos() -> Vector3:
	return point_at(s)


## A column's vehicle really driving now (tests, the docs' "really drive").
func is_driven(v: Vehicle) -> bool:
	var i := vehicles.find(v)
	return i >= 0 and bool(_vs[i].driven)


func _place_of(vi: int, off: Vector3) -> Vector3:
	var d := s - (gaps[vi] if vi < gaps.size() else 0.0)
	var xf := _xform_at(d)
	return level.ground_point(xf * off)


func _place_all() -> void:
	for i in vehicles.size():
		var v := vehicles[i]
		if not is_instance_valid(v) or v.wrecked or bool(_vs[i].driven) or _taken.has(v.get_instance_id()):
			continue
		if not v.freeze:
			v.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			v.freeze = true
		v.global_transform = _xform_at(s - gaps[i])
	if riding:
		for p: Soldier in everyone():
			_pin(p)


func _pin(p: Soldier) -> void:
	if p == null or not is_instance_valid(p) or not p.vitals.is_up() or _seats.has(p.get_instance_id()):
		return
	var pl: Array = _places.get(p.get_instance_id(), [0, Vector3.ZERO])
	p.global_position = _place_of(int(pl[0]), pl[1])
	p.velocity = Vector3.ZERO


# --- Who sits where -----------------------------------------------------------------------------

## Whether `o` is somebody not of this column.
func _stranger(o: Soldier) -> bool:
	return o != null and not o in people and o != trader


## Who rides where: a driver to each vehicle (the living, in order; a vehicle there's nobody left
## to drive is left behind), then the guards (and the enclave's man) to the passenger seats, the
## open ones first and spread over the vehicles.
func _assign_seats() -> void:
	_seats.clear()
	var crew: Array[Soldier] = []
	for p: Soldier in people:
		if is_instance_valid(p) and p.vitals.is_up():
			crew.append(p)
	var i := vehicles.size() - 1
	while i >= 0 and vehicles.size() > maxi(crew.size(), 1):
		if vehicles[i] != cargo_vehicle or vehicles.size() == 1:
			_drop_vehicle(i)
		i -= 1
	var n := 0
	var free: Array = []
	for vi in vehicles.size():
		var v := vehicles[vi]
		var ds := v.driver_seat()
		if ds >= 0 and n < crew.size() and not _stranger(v.occupant(ds)):
			_seats[crew[n].get_instance_id()] = [vi, ds]
			n += 1
		var defs: Array = v.spec.get("seats", [])
		for seat in v.seat_count():
			if v.seat_kind(seat) == Vehicle.PASSENGER and not _stranger(v.occupant(seat)):
				free.append([vi, seat, bool((defs[seat] as Dictionary).get("open", false))])
	var rest: Array[Soldier] = crew.slice(n)
	if drive_col and trader and is_instance_valid(trader) and trader.vitals.is_up():
		rest.append(trader)
	var loads := {}
	for p: Soldier in rest:
		var best := -1
		var best_key := INF
		for k in free.size():
			var key := float(loads.get(int(free[k][0]), 0)) * 10.0 + (0.0 if bool(free[k][2]) else 1.0) + float(k) * 0.01
			if key < best_key:
				best_key = key
				best = k
		if best < 0:
			break
		var pick: Array = free.pop_at(best)
		_seats[p.get_instance_id()] = [int(pick[0]), int(pick[1])]
		loads[int(pick[0])] = int(loads.get(int(pick[0]), 0)) + 1


## Everyone into their seats now (the column as it comes in).
func _board_all() -> void:
	for p: Soldier in everyone():
		if not is_instance_valid(p):
			continue
		var seat: Array = _seats.get(p.get_instance_id(), [])
		if not seat.is_empty():
			vehicles[int(seat[0])].server_enter(p, int(seat[1]))


## While riding, anyone not in the seat _assign_seats gave him moves there (a driver shot dead:
## the next man takes the wheel). Tried again each look, so swaps sort themselves out.
func _reseat() -> void:
	for p: Soldier in everyone():
		if not is_instance_valid(p) or not p.vitals.is_up():
			continue
		var seat: Array = _seats.get(p.get_instance_id(), [])
		if seat.is_empty():
			continue
		var v := vehicles[int(seat[0])]
		if v.seat_of(p) != int(seat[1]):
			v.server_enter(p, int(seat[1]))


## Takes vehicle `i` out of the column: an ordinary vehicle again (its people out of it; its cargo
## stays in it), no longer anyone's, so a player taking it is no crime.
func _drop_vehicle(i: int) -> void:
	var v := vehicles[i]
	if is_instance_valid(v):
		for o: Variant in v.occupants():
			var who := o as Soldier
			if who and not _stranger(who) and who.vitals.is_up():
				v.server_exit(who)
		_release(v)
	vehicles.remove_at(i)
	gaps.remove_at(i)
	_vs.remove_at(i)
	if i == 0 and not gaps.is_empty():  # (the next one leads: the column is measured from it)
		var first := gaps[0]
		s -= first
		for k in gaps.size():
			gaps[k] -= first
	if v == cargo_vehicle:
		cargo_vehicle = vehicles[0] if not vehicles.is_empty() else null
		_cargo_n = _cargo_count()


## `v` is nobody's now: unfrozen, stopped, saved with the zone like any other.
func _release(v: Vehicle) -> void:
	if not is_instance_valid(v):
		return
	if is_instance_valid(v.ai):
		v.server_stop()
	if v.freeze and not v.wrecked:
		v.freeze = false
	v.remove_meta(&"no_save")
	v.remove_meta(&"fallen_convoy")


## Every vehicle let go (the column robbed or lost): whoever has them now may drive them.
func _free_vehicles() -> void:
	for v: Vehicle in vehicles:
		_release(v)


## Host: vehicle `v` is given or sold to the players: out of the column, no robbery. Whether it was
## one of this column's.
func server_give_vehicle(v: Vehicle) -> bool:
	var i := vehicles.find(v)
	if i < 0:
		return false
	_drop_vehicle(i)
	_assign_seats()
	return true


# --- The step (host) ------------------------------------------------------------------------------

func server_step(delta: float) -> void:
	if state in ["done", "lost"] or level == null:
		return
	_think_t += delta
	if manual or _think_t >= THINK_S:
		var dt := _think_t
		_think_t = 0.0
		_think(dt)
	if state == "moving" and riding:
		_advance(delta)


## What's sliding moves every physics step; a truck under VehicleAI needs nothing from us here.
func _advance(delta: float) -> void:
	if vehicles.is_empty():
		return
	if not bool(_vs[0].driven):
		s = minf(length, s + speed * delta)
	rec["s"] = snappedf(s, 0.1)
	_place_all()
	if s >= length - (num("arrive_m", 7.0) if bool(_vs[0].driven) else 0.5):
		_arrive()


## A look about, every THINK_S (every step when stepped by hand).
func _think(dt: float) -> void:
	_refresh_record()
	_check_hits()
	_check_cargo()
	_check_wheels()
	if state == "hostile":
		return
	if not _vehicles_tick():
		return
	if WorldSim.world_now() > float(rec.get("until", 0.0)) + 0.25:
		_arrive()  # (its window long over, whatever it's held up by: a world event can't hang here)
		return
	if _alive(people) == 0 and not people.is_empty():
		if not raiders.is_empty():
			_lost_to_raiders()
		else:
			_abandoned()
		return
	if _alive(guards) == 0 and not guards.is_empty() and not raiders.is_empty():
		_lost_to_raiders()
		return
	if not bool(rec.get("ambush_spawned", false)) and String(rec.get("ambush_by", "-")) not in ["", "-"] and s >= length * num("ambush_at", 0.35):
		server_spawn_ambush()
	_noise_t -= dt
	if _noise_t <= 0.0 and riding:
		_noise_t = num("noise_every_s", 3.0)
		var lv := lead()
		if lv:
			Survival.server_noise(lv, lv.global_position, float(column_def(column).get("noise_m", 40.0)), ZombieAI.HEAR_RUN)
	_carry_t -= dt
	if _carry_t <= 0.0:
		_carry_t = CARRY_S
		_write_carry()
	var block := blocker_ahead()
	if not block.is_empty():
		_halt(String(block.kind), block.get("node") as Node3D, dt)
		_hold_vehicles()
		return
	if _hailed(dt):
		_hold_vehicles()
		return
	if not _mount_up(dt):
		_hold_vehicles()
		return
	state = "moving"
	why = ""
	_halt_t = 0.0
	if riding:
		_reseat()
	_drive_tick(dt)
	if not vehicles.is_empty() and bool(_vs[0].driven) and s >= length - num("arrive_m", 7.0):
		_arrive()


## The vehicles and the crew as they are: wrecks and crewless ones out of the column, seats dealt
## again when someone's fallen, where each truck is along the road. False when no vehicle is left.
func _vehicles_tick() -> bool:
	var dropped := false
	for i in range(vehicles.size() - 1, -1, -1):
		if not is_instance_valid(vehicles[i]) or vehicles[i].wrecked:
			_drop_vehicle(i)
			dropped = true
	var up := _alive(people)
	if up != _crew_n or dropped:
		_crew_n = up
		_assign_seats()
	if vehicles.is_empty():
		_stranded()
		return false
	for i in vehicles.size():
		var st: Dictionary = _vs[i]
		if bool(st.driven):
			var ao := _along_near(vehicles[i].global_position, float(st.s))
			st["s"] = ao[0]
			st["off"] = ao[1]
		else:
			st["s"] = s - gaps[i]
			st["off"] = 0.0
	if bool(_vs[0].driven):
		s = maxf(s, float(_vs[0].s))
		rec["s"] = snappedf(s, 0.1)
	return true


## What blocks the road ahead: {"kind": "wreck" | "barricade" | "dead" | "raiders" | "wheel", "node"}, or {}.
func blocker_ahead() -> Dictionary:
	for v: Vehicle in vehicles:
		if is_instance_valid(v) and _taken.has(v.get_instance_id()):
			return {"kind": "wheel", "node": v}
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


## Everyone gets down: out of their seats, or a step off the road beside it for those on foot.
func _dismount() -> void:
	if not riding:
		_mounting = false
		return
	riding = false
	_mounting = false
	var dir := dir_at(s)
	for p: Soldier in everyone():
		if not is_instance_valid(p) or not p.vitals.is_up():
			continue
		var v := Vehicle.ride_of(p)
		if v and v in vehicles:
			v.server_exit(p)
		elif p != trader:
			p.global_position = level.ground_point(p.global_position + Vector3(-dir.z, 0.0, dir.x) * (1.5 if p.get_index() % 2 == 0 else -1.5))


## Back aboard: those by their vehicle get in, the rest walk over (VehicleLayer.server_board) and
## after mount_s are put in anyway, a world event can't wait on a man who won't come. True when
## everyone's aboard.
func _mount_up(dt: float) -> bool:
	if riding:
		return true
	if not _mounting:
		_mounting = true
		_mount_t = 0.0
		_say(String(_line("moving")))
		_assign_seats()
	_mount_t += dt
	var over := _mount_t >= num("mount_s", 20.0)
	var reach := num("mount_reach_m", 6.0)
	var layer := VehicleLayer.of(level)
	var boss := _first_up()
	var all := true
	for p: Soldier in everyone():
		if not is_instance_valid(p) or not p.vitals.is_up():
			continue
		var seat: Array = _seats.get(p.get_instance_id(), [])
		if seat.is_empty():
			continue
		var v := vehicles[int(seat[0])]
		if v.seat_of(p) == int(seat[1]):
			continue
		if over or p.global_position.distance_to(v.global_position) <= reach:
			if not v.server_enter(p, int(seat[1])):
				if over:
					_seats.erase(p.get_instance_id())  # (his seat's gone: he walks beside)
				else:
					all = false
		else:
			all = false
			if layer and boss and SquadAI.of(p) and layer.boarding_of(p) != v:
				layer.server_board(boss, p, v, int(seat[1]))
	if all:
		riding = true
		_mounting = false
	return all


func _first_up() -> Soldier:
	for p: Soldier in people:
		if is_instance_valid(p) and p.vitals.is_up():
			return p
	return null


## Trucks hold where they are while the column is stopped.
func _hold_vehicles() -> void:
	for i in vehicles.size():
		if bool(_vs[i].driven) and is_instance_valid(vehicles[i].ai) and vehicles[i].ai.active:
			vehicles[i].server_stop()


## The motor vehicles' drivers, a look at a time: each truck drives only with a player near and
## while it can; each gets the road ahead of it and the speed that keeps the column in order; one
## that's stuck, off the road or overturned goes back to sliding for a while (the fallback).
func _drive_tick(dt: float) -> void:
	if not drive_col:
		return
	var near := force_drive or _player_within(num("drive_near_m", 350.0))
	for i in vehicles.size():
		var v := vehicles[i]
		var st: Dictionary = _vs[i]
		if v is Mount or _taken.has(v.get_instance_id()) or v.wrecked:
			continue
		if float(st.recover) > 0.0:
			st["recover"] = float(st.recover) - dt
			continue
		var want_drive := near and int(st.recovers) < int(num("recover_max", 3.0)) and not in_gap(float(st.s))
		if want_drive != bool(st.driven):
			_set_driven(i, want_drive)
		if want_drive:
			_steer(i, dt)


func _player_within(m: float) -> bool:
	var lp := lead_pos()
	for p: Soldier in MapNodes.players(level):
		if p.global_position.distance_to(lp) <= m:
			return true
	return false


func _set_driven(i: int, on: bool) -> void:
	var v := vehicles[i]
	var st: Dictionary = _vs[i]
	st["driven"] = on
	if on:
		var stream := level.get_node_or_null(NodePath(BigZoneStreaming.NODE_NAME)) as BigZoneStreaming
		if stream:
			stream.ensure(v.global_position)
		v.freeze = false
		v.sleeping = false
		st["at_s"] = float(st.s)
		st["stuck"] = 0.0
		if is_instance_valid(v.ai):
			v.ai.follow(PackedVector3Array([v.global_position]))  # (a fresh start: not a detour from where it was before)
	else:
		v.server_stop()
		v.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		v.freeze = true


## Vehicle `i`'s road and speed for now; the stuck, off-road and overturned checks.
func _steer(i: int, dt: float) -> void:
	var v := vehicles[i]
	var st: Dictionary = _vs[i]
	var at := float(st.s)
	var want := speed
	if i == 0:
		if vehicles.size() > 1 and at - float(_vs[1].s) > (gaps[1] - gaps[0]) * num("straggle_gaps", 2.5):
			want = minf(speed, num("crawl_ms", 1.5))
	else:
		var ahead_ms := absf(vehicles[i - 1].forward_speed()) if bool(_vs[i - 1].driven) else speed
		want = ConvoyColumn.follow_speed(float(_vs[i - 1].s) - at, gaps[i] - gaps[i - 1], ahead_ms, speed * 1.8)
	st["want"] = want
	if want >= STOP_MS and absf(at - float(st.at_s)) < num("stuck_m", 2.5):
		st["stuck"] = float(st.stuck) + dt
	else:
		st["at_s"] = at
		st["stuck"] = 0.0
	var ground := level.ground_point(v.global_position)
	var fell := v.global_position.y < ground.y - 3.0 or v.global_basis.y.y < 0.5 or (v.drive != null and v.drive.blocked() != "")
	if float(st.stuck) >= num("stuck_s", 12.0) or float(st.off) >= num("off_road_m", 14.0) or fell or not v.can_drive():
		_recover(i)
		return
	if want < STOP_MS:
		v.server_stop()
		return
	var pts := _road_ahead(at, num("steer_ahead_m", 70.0))
	if not is_instance_valid(v.ai):
		v.server_follow_path(pts)
	v.ai.steer_to(pts, want, true)


## The road's points from just ahead of `at` to `ahead_m` on it.
func _road_ahead(at: float, ahead_m: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var from_d := minf(at + STEER_FROM_M, length)
	var to_d := minf(at + ahead_m, length)
	out.append(point_at(from_d))
	for k in range(arcs.bsearch(from_d), mini(arcs.bsearch(to_d) + 1, arcs.size())):
		if arcs[k] > from_d + 1.0 and arcs[k] < to_d:
			out.append(path[k])
	if to_d > from_d + 1.0:
		out.append(point_at(to_d))
	return out


## A truck that can't get on: back on the road and sliding for a while (recover_s), not a hung event.
func _recover(i: int) -> void:
	var st: Dictionary = _vs[i]
	st["recover"] = num("recover_s", 10.0)
	st["recovers"] = int(st.recovers) + 1
	recoveries += 1
	_set_driven(i, false)
	SessionLog.note("survival convoy %d: %s stuck (%.0f m off the road, %.0f s still): back on the road by hand (%d)" % [int(rec.get("id", 0)), vehicles[i].model, float(st.off), float(st.stuck), int(st.recovers)])


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
	_hold_vehicles()
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
		server_rob(_nearest_player(cargo_vehicle.global_position if is_instance_valid(cargo_vehicle) else lead_pos()), "took from the cargo")
	_cargo_n = n


func _nearest_player(at: Vector3) -> Soldier:
	var who: Soldier = null
	var best := INF
	for p: Soldier in MapNodes.players(level):
		var d := p.global_position.distance_to(at)
		if d < best:
			best = d
			who = p
	return who


## A stranger at one of its wheels (a player, or a man of his told to drive): the column holds and
## its people shout; once the vehicle's gone steal_m from where he took the seat, it's robbed. A
## passenger is no thief, and getting out again is the end of it.
func _check_wheels() -> void:
	if state == "hostile":
		return
	for v: Vehicle in vehicles:
		if not is_instance_valid(v) or v.wrecked:
			continue
		var id := v.get_instance_id()
		var d := v.driver()
		if not _stranger(d):
			_taken.erase(id)
			continue
		if not _taken.has(id):
			_taken[id] = {"by": d, "from": v.global_position}
			if v.freeze:
				v.freeze = false  # (it's his to steer now, unless it's stolen)
			_say(String(_line("halt_wheel")))
			continue
		if v.global_position.distance_to((_taken[id] as Dictionary).from) >= num("steal_m", 6.0):
			server_rob(d if not d.is_ai() else _nearest_player(v.global_position), "drove off in the %s" % v.short_name())
			return


## Host: the players rob the column (`by`: who): its people turn on them (hostile), the owner's
## standing falls, an event names him (WorldEvents.server_convoy_robbed).
func server_rob(by: Soldier, how := "robbed") -> void:
	if state in ["hostile", "done"]:
		return
	_dismount()
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
	_free_vehicles()
	rec["live"] = false
	WorldEvents.server_convoy_robbed(rec, by)
	_stick()
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
			WeaponCondition.server_used_guns(r, _rng)  # their guns come used (survival wear)
			r.set_meta(&"world_group", gid)
			raiders.append(r)
	var men := rsq.members()
	if not men.is_empty():
		rsq.leader = men[0]
		rsq.hero = men[0]
	SessionLog.note("survival convoy %d: %d raiders of %s waiting %.0f m up the road" % [id, raiders.size(), String(g.get("name", gid)), at_d - s])
	return raiders


func _lost_to_raiders() -> void:
	_dismount()
	state = "lost"
	rec["live"] = false
	_free_vehicles()
	var gid := String(rec.get("ambush_by", ""))
	var g := WorldSim.group(gid)
	var def: Dictionary = WorldEvents.kind_def("convoy")
	WorldEvents.server_end_live(rec, "ambushed", "convoy_ambushed", String(def.get("ambushed", "")).format({"group": String(g.get("name", "Raiders")),
		"column": column, "zone": RegionMap.zone_name(String(rec.get("zone", "")))}), [gid] if gid != "" else [])
	_stick()
	var col := String(rec.get("group", ""))
	var sim := WorldSim.get_sim()
	if sim and col != "" and gid != "":
		sim.mutate(func(w: Dictionary) -> void:
			var cg: Dictionary = (w.get("groups", {}) as Dictionary).get(col, {})
			if not cg.is_empty():
				(cg.relations as Dictionary)[gid] = float((cg.relations as Dictionary).get(gid, 0.0)) - 30.0)


## All its people dead (nobody's fault it can name): the column is over, its vehicles and cargo left
## on the road for whoever comes by.
func _abandoned() -> void:
	state = "lost"
	riding = false
	rec["live"] = false
	_free_vehicles()
	var def: Dictionary = WorldEvents.kind_def("convoy")
	WorldEvents.server_end_live(rec, "lost", "convoy_ambushed", String(def.get("lost", "")).format({"column": column, "zone": RegionMap.zone_name(String(rec.get("zone", "")))}), [])
	_stick()


## No vehicle left under it: the people stay where they are, the event's over.
func _stranded() -> void:
	_abandoned()


## The end of its road here: on into the next zone in the world sim with what's left of it
## (WorldEvents.server_convoy_cross), or, at the end of its way, convoy_passed; the column leaves.
func _arrive() -> void:
	state = "done"
	rec["live"] = false
	_write_carry()
	if not WorldEvents.server_convoy_cross(rec):
		var def: Dictionary = WorldEvents.kind_def("convoy")
		WorldEvents.server_end_live(rec, "passed", "convoy_passed", String(def.get("passed", "")).format({"column": column,
			"zone": RegionMap.zone_name(String(rec.get("zone", "")))}), [])
	_stick()
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
