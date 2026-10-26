class_name Mounts
extends Node
## A survival zone's mounts (docs/survival_mounts.md; calls 31, 35; survival_people.md section 6):
## one node, "Mounts", under the SurvivalLevel (Survival.server_level_ready installs it). Host only.
## - Placing: once the zone's save is loaded and the first survivor is in, the zone's mounts are
##   parked through VehicleLayer.server_place_parked by stable ids, so a mount the save holds comes
##   back as it was left (ridden off, tied, dead) and only the never-seen are fresh: at the start
##   farm START_HORSES wild horses and a cart, at every other farm FARM_HORSES and a cart now and
##   then, at villages and towns VILLAGE_BIKES bicycles leant by the houses (by the zone's seed).
## - Shots: Survival.server_noise calls on_noise; a loud one spooks the horses within Mount.SPOOK_M.
## - Companions: server_mount_up ("Everyone mount up", a mount's menu) sends each companion on foot
##   to a free mount of their own (walking up and getting on: VehicleLayer.server_board), and once
##   they're up, SquadDrivers' column has them follow the player's mount (or him on foot); with no
##   mount each they walk and keep up (their follow order). server_stay ("Stay with the horses", a
##   tied horse's menu) holds the nearest companion by it: the horse is minded (spooks less) and he
##   calls out the dead coming at it (CALLOUT_M).
## - The world lane: server_spawn (a mount anywhere, tame or wild) and Mount.counts_in_zone.
## Numbers Proposed.

const NODE_NAME := "Mounts"
const START_HORSES := 2
const FARM_HORSES := 1
const FARM_CART_CHANCE := 0.5
const VILLAGE_BIKES := Vector2i(1, 2)
## Companions take a mount this close to the one who called (m).
const MOUNT_UP_M := 60.0
## A minder stands this far off the horse's flank (m) and calls the dead within CALLOUT_M of it,
## one call every CALLOUT_GAP_S at most.
const STAY_OFF_M := 2.5
const CALLOUT_M := 30.0
const CALLOUT_GAP_S := 12.0
const STAY_PICK_M := 40.0
## After a mount up, the column is (re)formed while new riders get on, for this long (s).
const CONVOY_FOR_S := 90.0
const TICK_S := 1.0
const HORSE_SCHEMES: Array[String] = ["bay", "chestnut", "grey", "black_horse"]
const BIKE_SCHEMES: Array[String] = ["bike_red", "bike_blue", "bike_green"]
const LINES_MOUNT_UP: Array[String] = ["Mounting up.", "Right behind you.", "Got one."]
const LINES_STAY: Array[String] = ["I'll stay with the horses.", "Go on, I've got them.", "They'll be here when you're back."]
const LINES_CALL: Array[String] = ["Dead coming at the horses!", "Something at the horses!", "Walkers by the horses!"]

var level: Node
var placed := false
var _left := 0.0
var _convoy := {}       # by (Soldier) instance id -> {"by": Soldier, "until": time, "riders": n formed with}
var _called := {}       # zombie instance id -> true (called once)
var _called_at := -100.0
var _serial := 0


## Host: the level's Mounts (added once).
static func install(p_level: Node) -> Mounts:
	var have := p_level.get_node_or_null(NODE_NAME) as Mounts
	if have:
		return have
	var m := Mounts.new()
	m.name = NODE_NAME
	m.level = p_level
	p_level.add_child(m)
	return m


static func of(from: Node) -> Mounts:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NODE_NAME) as Mounts if lvl else null


## Every mount in `from`'s level.
static func all(from: Node) -> Array[Mount]:
	var out: Array[Mount] = []
	var layer := VehicleLayer.of(from)
	if layer == null:
		return out
	for v: Vehicle in layer.vehicles():
		if v is Mount:
			out.append(v as Mount)
	return out


## Host (Survival.server_noise): a loud noise (a shot, a scream) spooks the horses near it.
static func on_noise(p_level: Node, source: Node, pos: Vector3, _radius: float, loud: float) -> void:
	if loud < ZombieAI.HEAR_SHOT * 0.9 or p_level == null:
		return
	for m: Mount in all(p_level):
		if m != source and m.mount_type != Mount.BICYCLE and m.global_position.distance_to(pos) <= Mount.SPOOK_M:
			m.server_spook(pos, "shot", source)


## Host: a mount of `model` ("horse", "bicycle", "cart") at `pos` (on the ground there), facing
## `yaw_deg`; opts: "wild" (a horse not yet caught; default tame), "id", "scheme", "faction", "save"
## (false: not kept in the zone save, e.g. a passing group's). The world lane's groups use it.
static func server_spawn(p_level: Node, model: String, pos: Vector3, yaw_deg := 0.0, opts := {}) -> Mount:
	var layer := VehicleLayer.of(p_level)
	if layer == null or not Mount.is_mount_model(model):
		return null
	var at := pos
	if p_level.has_method(&"ground_point"):
		at = p_level.call(&"ground_point", pos)
	var scheme := String(opts.get("scheme", ""))
	var v := layer.server_spawn(model, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), at), scheme, StringName(String(opts.get("faction", "player"))), String(opts.get("id", "")))
	var m := v as Mount
	if m == null:
		return null
	if model == Mount.HORSE:
		m.tamed = not bool(opts.get("wild", false))
	m.home = at
	if not bool(opts.get("save", true)):
		m.set_meta(&"no_save", true)
	m._publish_state(true)
	return m


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or level == null:
		return
	if not placed:
		var players: Node = level.get(&"players")
		if players and players.get_child_count() > 0:
			placed = true
			server_place()
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = TICK_S
	_step_convoys()
	_step_minders()


# --- Placing (host) -----------------------------------------------------------------------------

## The zone's mounts, by its seed (see the header). Returns the ones parked fresh now.
func server_place() -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	var layer := VehicleLayer.of(level)
	var zl := level as ZoneLevel
	if layer == null or zl == null:
		return out
	var zone := String(Survival.state().get("zone", GameState.zone_id))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(zone + "|mounts")
	var entries: Array = []
	var points := zl.insertion_points()
	if zone == String(Survival.state().get("start_zone", "")) and not points.is_empty():
		var farm: Vector3 = points[0]
		for i in START_HORSES:
			entries.append({"id": "mnt_start_horse_%d" % i, "model": Mount.HORSE, "scheme": HORSE_SCHEMES[rng.randi() % HORSE_SCHEMES.size()],
				"pos": zl.ground_point(farm + Vector3(12.0 + 4.0 * i, 0.0, 7.0 - 6.0 * i)), "yaw": rng.randf() * 360.0})
		entries.append({"id": "mnt_start_cart", "model": Mount.CART, "pos": zl.ground_point(farm + Vector3(-9.0, 0.0, 9.0)), "yaw": rng.randf() * 360.0})
	for m: ZoneModule in zl.get(&"_modules"):
		var base := ZoneModules.base(m.type)
		var at := m.global_position
		if base == "farm" or m.type.contains("farm"):
			for i in FARM_HORSES:
				entries.append({"id": "mnt_%s_horse_%d" % [m.module_id, i], "model": Mount.HORSE, "scheme": HORSE_SCHEMES[rng.randi() % HORSE_SCHEMES.size()],
					"pos": zl.ground_point(at + Vector3(rng.randf_range(-14.0, 14.0), 0.0, rng.randf_range(14.0, 20.0))), "yaw": rng.randf() * 360.0})
			if rng.randf() < FARM_CART_CHANCE:
				entries.append({"id": "mnt_%s_cart" % m.module_id, "model": Mount.CART, "pos": zl.ground_point(at + Vector3(rng.randf_range(-10.0, 10.0), 0.0, -16.0)), "yaw": rng.randf() * 360.0})
		elif base in ["village", "town"]:
			for i in rng.randi_range(VILLAGE_BIKES.x, VILLAGE_BIKES.y):
				entries.append({"id": "mnt_%s_bike_%d" % [m.module_id, i], "model": Mount.BICYCLE, "scheme": BIKE_SCHEMES[rng.randi() % BIKE_SCHEMES.size()],
					"pos": zl.ground_point(at + Vector3(rng.randf_range(-18.0, 18.0), 0.0, rng.randf_range(-18.0, 18.0))), "yaw": rng.randf() * 360.0})
	out = layer.server_place_parked(entries)
	for v: Vehicle in out:
		var mt := v as Mount
		if mt:
			mt.home = mt.global_position
	return out


# --- Companions (host) ----------------------------------------------------------------------------

## The companions and squad AI of `by`'s side, up and on their feet.
func _walkers(by: Soldier) -> Array[Soldier]:
	var out: Array[Soldier] = []
	var people := SurvivorsLayer.find(level)
	var pool: Array = people.companions() if people else []
	var zl := level as CompoundLevel
	var squad: Squad = zl.squad_for(by.faction) if zl else null
	if squad:
		for s: Soldier in squad.members():
			if not s in pool:
				pool.append(s)
	for s: Soldier in pool:
		if is_instance_valid(s) and s.is_ai() and s.vitals.is_up() and Vehicle.ride_of(s) == null and s.faction == by.faction:
			out.append(s)
	return out


## Free mounts for a companion near `at`: a tame horse loose (not tied, not in the shafts), a bike
## standing, a hitched cart's free seats.
func _free_mounts(at: Vector3) -> Array[Mount]:
	var out: Array[Mount] = []
	var layer := VehicleLayer.of(level)
	for m: Mount in all(level):
		if m.wrecked or m.global_position.distance_to(at) > MOUNT_UP_M or m.ride_block() != "":
			continue
		if m.mount_type == Mount.CART and m.horse() == null:
			continue
		if m.mount_type != Mount.CART and (m.rider() != null or (layer and layer.boarding_to(m) > 0)):
			continue
		out.append(m)
	out.sort_custom(func(a: Mount, b: Mount) -> bool: return a.global_position.distance_to(at) < b.global_position.distance_to(at))
	return out


## Host: "Everyone mount up": each companion on foot to a free mount of their own. "" or why not
## (for `by`'s message line).
func server_mount_up(by: Soldier) -> String:
	if by == null:
		return ""
	var walkers := _walkers(by)
	if walkers.is_empty():
		return "Nobody on foot to mount up"
	var layer := VehicleLayer.of(level)
	var free := _free_mounts(by.global_position)
	var mine := Vehicle.ride_of(by)
	free = free.filter(func(m: Mount) -> bool: return m != mine or m.mount_type == Mount.CART)
	var sent := 0
	for m: Mount in free:
		var seats := 1
		if m.mount_type == Mount.CART:
			seats = 0
			for i in m.seat_count():
				if m.occupant(i) == null:
					seats += 1
			seats -= layer.boarding_to(m)
		while seats > 0 and not walkers.is_empty():
			walkers.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.global_position.distance_to(m.global_position) < b.global_position.distance_to(m.global_position))
			var c: Soldier = walkers.pop_front()
			var seat := 0 if m.occupant(0) == null else 1
			if layer.server_board(by, c, m, seat):
				sent += 1
				seats -= 1
				_say(c, LINES_MOUNT_UP[sent % LINES_MOUNT_UP.size()])
			else:
				break
	if sent == 0:
		return "No free mounts near"
	_convoy[by.get_instance_id()] = {"by": by, "until": Soldier._now() + CONVOY_FOR_S, "riders": 0}
	return "%d mounting up%s" % [sent, "" if walkers.is_empty() else " (%d walk)" % walkers.size()]


## The column (SquadDrivers.server_convoy) behind `by`, re-formed as more riders get on.
func _step_convoys() -> void:
	var drivers := SquadDrivers.of(level)
	if drivers == null:
		return
	var now := Soldier._now()
	for id: int in _convoy.keys():
		var c: Dictionary = _convoy[id]
		var by: Soldier = c.by as Soldier if is_instance_valid(c.by) else null
		if by == null or now > float(c.until):
			_convoy.erase(id)
			continue
		var riders := drivers.driven(by).filter(func(v: Vehicle) -> bool: return v is Mount and v != Vehicle.ride_of(by)).size()
		if riders > int(c.riders):
			if drivers.server_convoy(by) == "":
				c.riders = riders


## Host: "Stay with the horses": the nearest companion on foot holds by `m` (tied), minding it.
func server_stay(by: Soldier, m: Mount) -> String:
	if m == null or not m.tied:
		return "Tie it first"
	var best: Soldier = null
	for s: Soldier in _walkers(by):
		var d := s.global_position.distance_to(m.global_position)
		if d <= STAY_PICK_M and (best == null or d < best.global_position.distance_to(m.global_position)):
			best = s
	if best == null:
		return "Nobody near to stay with it"
	var side := m.global_basis.x * STAY_OFF_M
	var spot: Vector3 = m.global_position + side
	if level.has_method(&"ground_point"):
		spot = level.call(&"ground_point", spot)
	var brain := SquadAI.of(best)
	if brain:
		brain.on_order(Squad.Order.HOLD, spot)
	best.set_meta(&"minding", m.vehicle_id)
	m.minder = best
	m._publish_state(true)
	_say(best, LINES_STAY[randi() % LINES_STAY.size()])
	return ""


## Minders: off duty when told otherwise; calling the dead that come at their horse.
func _step_minders() -> void:
	var now := Soldier._now()
	for m: Mount in all(level):
		var c := m.minder
		if not is_instance_valid(c):
			continue
		var brain := SquadAI.of(c)
		if not c.vitals.is_up() or not m.tied or (brain and brain.order != Squad.Order.HOLD):
			c.remove_meta(&"minding")
			m.minder = null
			continue
		if not Survival.running:
			continue
		for z: Soldier in Survival.zombies(level):
			if _called.has(z.get_instance_id()) or z.global_position.distance_to(m.global_position) > CALLOUT_M:
				continue
			_called[z.get_instance_id()] = true
			if now - _called_at >= CALLOUT_GAP_S:
				_called_at = now
				_say(c, LINES_CALL[randi() % LINES_CALL.size()])
			break


## Whether `c` is minding a horse now.
static func minding(c: Soldier) -> bool:
	return is_instance_valid(c) and c.has_meta(&"minding")


func _say(s: Soldier, text: String) -> void:
	var people := SurvivorsLayer.find(level)
	if people:
		people.say(s, text)
