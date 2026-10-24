class_name VehicleFire
extends Node
## What a vehicle's fire and its ammunition do (combined arms A7, cg_brief queue item 2.5;
## docs/combined_arms.md 2.10): the host's state, the "FireState" child of every Vehicle. Its
## looks are VehicleFx's, on every peer, from this state (net_state, in the vehicle's StateSync,
## so late joiners see a burning wreck burning) and its one-off events (the fireball, the vent,
## each cook-off pop: VehicleFx.server_event).
##
## - The stages (2.10.1): a vehicle set on fire (Vehicle.server_start_fire: a fire roll, a
##   destroyed hull, a cook-off) shows grey SMOKE for smoke_s, then FIRE (flames, black smoke). It
##   burns Vehicle.FIRE_S (lost from the start, as before A7: the fire reaches the crew
##   compartment), then it's a wreck that goes on burning (BURN_OUT, seeded 120-300 s, the flames
##   dying down) under a smoke column standing for 5-10 minutes (seeded) from when it became a
##   wreck, then SMOULDER for the rest of the deployment. Every stage is saved with the zone.
## - Ammunition (2.10.2, from VehicleModules._detonation_roll: server_ammo): a VENT (the Abrams'
##   bustle through its blow-out panels: an 8 m column of fire up through the roof for 4 s, the
##   crew unhurt, no fire); a COOK_OFF (the rack's rounds popping every 0.5-3 s for 20-60 s, each
##   a small HE event on whoever is near; a rack of 120/125 mm rounds rolls 5% a second to go up);
##   a CATASTROPHIC kill (2.10.4): a fireball of 2 + 1.5 x rounds^(1/3) m with a blast of
##   min(0.4 x rounds, 12) kg TNT on everyone near and a shake; the turret thrown (TOSS) with 10 or
##   more main-gun rounds aboard, else the hull ruptures (RUPTURE: the roof plates lift); 12-24
##   debris pieces cut from the hull by the seed; the hulk charred.
## - Bail-out (2.10.1): when a cook-off starts, or the flames have burned bail_fire_s, the crew
##   is told "Bail out!" (bail_out_called; Callouts) and, while auto_bail is on, the AI aboard an
##   armoured vehicle get out (Vehicle.server_exit) and the modules know it (server_bail_out:
##   a crew kill). Where they run and the smarter triggers are A9's (F-236).
## - The thrown turret and the debris fly on every peer from the same seed (as BlastGore's gore
##   pieces: no position stream); the host's land, and their resting places come here
##   (server_rested), go to every peer and late joiner, and stay in the zone save.
## Thermal (A4's ThermalView): a burning hull is at heat burning, a burnt-out wreck cools from
## burn_out to ThermalView's cold wreck over cool_s (the vehicle's "thermal_heat" meta, every
## peer). Every number is Proposed (data/vehicle_fx.json).

const PATH := "res://data/vehicle_fx.json"
const NODE_NAME := &"FireState"
## Stages.
const NONE := ""
const SMOKE := "smoke"
const FIRE := "fire"
const BURN_OUT := "burn_out"
const SMOULDER := "smoulder"
## What the ammunition did (kill "k").
const VENT := "vent"
const COOK_OFF := "cook_off"
const TOSS := "toss"
const RUPTURE := "rupture"
## The host looks at the fire this often (s).
const STEP_S := 0.1
## Roll salts on the fire's seed (ArmourModel.roll).
const ROLL_BURN := 7100
const ROLL_COLUMN := 7101
const ROLL_COOK := 7102
const ROLL_POP := 7200
const ROLL_GO := 7300
const ROLL_SPOT := 7400
## Small rounds (25 mm, 40 mm, .50) per main-gun round in the fireball's count (Proposed).
const SMALL_PER_ROUND := 50.0

## Tests and A9: the AI crews of armoured vehicles get out by themselves (off: A9's own rule).
static var auto_bail := true
static var _data: Dictionary = {}

## Host: the crew should get out (`reason`: "cook_off", "fire", "catastrophic"); once a fire.
signal bail_out_called(reason: String)
## Every peer: the stage changed.
signal stage_changed(stage: String)

var vehicle: Vehicle
## The stage now (every peer).
var stage := NONE
## The fire's seed (the host picks it when it starts; every roll and every peer's pieces).
var seed := 0
## Host clock (Soldier._now on the host) when the fire started, the stage began, it became a
## wreck (NEVER: not yet); clients keep the host's numbers and read them through host_now().
const NEVER := -1.0e9
var fire_t := NEVER
var stage_t := NEVER
var wreck_t := NEVER
## Seconds the burnt-out flames last and the column stands (seeded at the wreck).
var burn_out_s := 0.0
var column_s := 0.0
## A cook-off: until when (host clock), the rack it's in, the next pop, pops so far.
var cook_until := -1.0
var cook_rack := ""
var pops := 0
## What the ammunition did: {"k": VENT/TOSS/RUPTURE, "r": main-gun rounds aboard, "e": rounds
## counted for the fireball, "kg", "radius", "t": host clock, "rack"} or {}.
var kill: Dictionary = {}
## Where the thrown turret and the debris came to rest (world: [x, y, z, qx, qy, qz, qw]).
var turret_rest: Array = []
var debris_rest: Array = []
## Host: who the last fireball reached (tests).
var last_hurt: Array = []
## Bail-out called (host), and why.
var bailed := ""
## Replicated (host -> every peer): {"st", "sd", "ft", "stt", "wt", "bo", "co", "cu", "cr", "k",
## "tr", "dr", "n" (host clock at publish)}.
var net_state: Dictionary = {}:
	set(value):
		net_state = value
		if not _is_host():
			_apply_net()
var _step_left := 0.0
var _marks: Array = []  # host: the kill's hull marks still to carve, one a frame
var _pop_next := -1.0
var _go_next := -1.0
var _got_at := 0.0  # clients: local clock when net_state came, and its "n"
var _got_n := 0.0


func _init(p_vehicle: Vehicle = null) -> void:
	name = NODE_NAME
	vehicle = p_vehicle


func _ready() -> void:
	set_physics_process(_is_host())


func _is_host() -> bool:
	return not is_inside_tree() or multiplayer.multiplayer_peer == null or multiplayer.is_server()


# --- Data ---------------------------------------------------------------------------------------

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_data = parsed if parsed is Dictionary else {"fire": {}}
	return _data


## A number from data/vehicle_fx.json's `section`.
static func num(section: String, key: String, fallback: float) -> float:
	return float((data().get(section, {}) as Dictionary).get(key, fallback))


## A [lo, hi] range from `section`, rolled by `r` (0..1).
static func span(section: String, key: String, fallback: Vector2, r: float) -> float:
	var a: Variant = (data().get(section, {}) as Dictionary).get(key, [fallback.x, fallback.y])
	var lo := float(a[0]) if a is Array and (a as Array).size() > 1 else fallback.x
	var hi := float(a[1]) if a is Array and (a as Array).size() > 1 else fallback.y
	return lerpf(lo, hi, clampf(r, 0.0, 1.0))


## Model `model`'s fx block (racks, dischargers, sounds), {} for none.
static func fx_of(spec: Dictionary) -> Dictionary:
	return spec.get("fx", {}) if spec.get("fx") is Dictionary else {}


## The fireball of a detonation with `rounds` counted (2.10.4): {"radius", "kg"}.
static func fireball(rounds: float) -> Dictionary:
	var r := maxf(rounds, 0.0)
	return {"radius": num("fireball", "r0", 2.0) + num("fireball", "r_per", 1.5) * pow(r, 1.0 / 3.0),
		"kg": minf(num("fireball", "kg_per", 0.4) * r, num("fireball", "kg_max", 12.0))}


## The rounds a vehicle has aboard now: {"big": main-gun rounds and missiles (the racks the fx
## block marks big), "small": the rest, "count": what the fireball counts}.
static func rounds_aboard(v: Vehicle) -> Dictionary:
	var racks: Dictionary = fx_of(v.spec).get("racks", {})
	var big := 0
	var small := 0
	if v.modules:
		for i: int in v.modules.rounds:
			var id := String(v.modules.mods[i].id)
			if bool((racks.get(id, {}) as Dictionary).get("big", false)):
				big += int(v.modules.rounds[i])
			else:
				small += int(v.modules.rounds[i])
	return {"big": big, "small": small, "count": float(big) + float(small) / SMALL_PER_ROUND}


# --- Host ---------------------------------------------------------------------------------------

## Host clock now (on a client: the host's, from the vehicle's pose clock, else from the last state).
func host_now() -> float:
	if _is_host():
		return Soldier._now()
	if vehicle and is_finite(vehicle._clock):
		return Soldier._now() - vehicle._clock
	return _got_n + (Soldier._now() - _got_at)


## Seconds in the stage now (every peer).
func stage_age() -> float:
	return maxf(host_now() - stage_t, 0.0) if stage_t > NEVER * 0.5 else 0.0


## Seconds since it became a wreck (-1: not one), every peer.
func wreck_age() -> float:
	return maxf(host_now() - wreck_t, 0.0) if wreck_t > NEVER * 0.5 else -1.0


## Whether the column of smoke stands now (burning, or a wreck within its column time).
func column_up() -> bool:
	if stage == SMOKE or stage == FIRE:
		return true
	return stage == BURN_OUT or (stage == SMOULDER and wreck_age() >= 0.0 and wreck_age() < column_s)


## Whether there are flames (burning, or a burning wreck), and how strong (0..1).
func flames() -> float:
	match stage:
		FIRE:
			return 1.0
		BURN_OUT:
			return clampf(1.0 - stage_age() / maxf(burn_out_s, 1.0), 0.15, 1.0)
	return 0.0


## Whether it's cooking off now.
func cooking() -> bool:
	return cook_until > 0.0 and host_now() < cook_until


## How hot it is for thermal now (2.7.4; -1: ThermalView decides as before A7).
func heat() -> float:
	match stage:
		SMOKE, FIRE:
			return num("heat", "burning", 1.0)
		BURN_OUT:
			return num("heat", "burn_out", 0.95)
		SMOULDER:
			var cool := num("heat", "cool_s", 900.0)
			var since := maxf(wreck_age() - burn_out_s, 0.0)
			return lerpf(num("heat", "burn_out", 0.95), ThermalView.WRECK_HEAT, clampf(since / maxf(cool, 1.0), 0.0, 1.0))
	return -1.0


func _physics_process(delta: float) -> void:
	if not _marks.is_empty() and vehicle:
		vehicle._add_carves([_marks.pop_front()])
	_step_left -= delta
	if _step_left > 0.0 or vehicle == null:
		return
	_step_left = STEP_S
	var now := Soldier._now()
	if stage == NONE and vehicle.is_burning():
		server_ignite()
	if vehicle.wrecked and stage in [NONE, SMOKE, FIRE]:
		server_wrecked()
	match stage:
		SMOKE:
			if now - stage_t >= num("fire", "smoke_s", 8.0):
				_set_stage(FIRE, now)
		FIRE:
			if bailed == "" and now - stage_t >= num("fire", "bail_fire_s", 3.0):
				server_bail("fire")
		BURN_OUT:
			if now - stage_t >= burn_out_s:
				_set_stage(SMOULDER, now)
	if cook_until > 0.0:
		_cook_step(now)
	_heat_meta()


## Host: the fire starts (any way a vehicle is set alight: polled from Vehicle.is_burning).
func server_ignite() -> void:
	if not _is_host() or stage != NONE:
		return
	var now := Soldier._now()
	fire_t = now
	if seed == 0:
		seed = _new_seed()
	# A cook-off or a detonation lights it at once; any other fire smokes first.
	_set_stage(FIRE if (cook_until > 0.0 or not kill.is_empty()) else SMOKE, now)


## Host: it's a wreck now (Vehicle._become_wreck): the flames burn out, the column stands.
func server_wrecked() -> void:
	if not _is_host():
		return
	var now := Soldier._now()
	if seed == 0:
		seed = _new_seed()
	if fire_t <= NEVER * 0.5:
		fire_t = now
	wreck_t = now
	burn_out_s = span("fire", "burn_out_s", Vector2(120.0, 300.0), ArmourModel.roll(seed, ROLL_BURN))
	column_s = span("fire", "column_s", Vector2(300.0, 600.0), ArmourModel.roll(seed, ROLL_COLUMN))
	_set_stage(BURN_OUT, now)


## Host (VehicleModules._detonation_roll): an ammo rack `m` went: `how` "vent", "cook_off" or
## "catastrophic" (2.10.2).
func server_ammo(how: String, m: Dictionary) -> void:
	if not _is_host() or vehicle == null:
		return
	var now := Soldier._now()
	if seed == 0:
		seed = _new_seed()
	match how:
		VENT:
			kill = {"k": VENT, "t": now, "rack": String(m.get("id", "")), "r": 0, "e": 0.0}
			_publish()
			VehicleFx.server_event(vehicle, "vent", {"rack": String(m.get("id", ""))})
		COOK_OFF:
			if cook_until < 0.0:
				cook_rack = String(m.get("id", ""))
				cook_until = now + span("fire", "cook_off_s", Vector2(20.0, 60.0), ArmourModel.roll(seed, ROLL_COOK))
				_pop_next = now + 0.3
				_go_next = now + 1.0
				_publish()
				server_bail("cook_off")
		_:
			server_detonate(String(m.get("id", "")))


## Host: it goes up (a catastrophic kill, 2.10.4): the fireball and its blast on everyone near,
## the turret thrown or the hull ruptured, the debris, the hulk charred. Once.
func server_detonate(rack := "") -> void:
	if not _is_host() or vehicle == null or (not kill.is_empty() and String(kill.k) in [TOSS, RUPTURE]):
		return
	var now := Soldier._now()
	if seed == 0:
		seed = _new_seed()
	var aboard := rounds_aboard(vehicle)
	var ball := fireball(float(aboard.count))
	var toss := int(aboard.big) >= int(num("fireball", "toss_rounds", 10.0)) and vehicle.turret != null
	kill = {"k": TOSS if toss else RUPTURE, "t": now, "rack": rack, "r": int(aboard.big), "e": snappedf(float(aboard.count), 0.01),
		"kg": snappedf(float(ball.kg), 0.01), "radius": snappedf(float(ball.radius), 0.01)}
	cook_until = -1.0
	if vehicle.is_burning():
		vehicle.burning_s = minf(vehicle.burning_s, VehicleModules.DETONATE_BURN_S)  # (already alight from this hit's fire roll: it still goes up at once)
	server_bail("catastrophic")
	var centre := vehicle.global_transform * Vector3(0.0, VehicleArt.size_m(vehicle.model).y * 0.6, 0.0)
	var lvl := vehicle.level()
	if lvl and float(ball.kg) > 0.0:
		var d := {"blast_kg": float(ball.kg), "frag_m": num("fireball", "frag_m", 18.0), "frag_wounds": [1, 4], "kind": String(Vehicle.HE)}
		var skip: Array = vehicle.occupants()  # (the crew go with it: Vehicle._become_wreck)
		last_hurt = Warheads.server_people(lvl, centre, d, null, skip)
		BlastGore.server_blast(lvl, centre, float(ball.kg), float(d.frag_m), skip)
		SmokeCloud.server_blast(centre, float(ball.radius))
		PeopleLayer.server_noise(lvl, centre, PeopleLayer.BLAST_HEARD_M)
	_hull_marks()
	_publish()
	VehicleFx.server_event(vehicle, "kill", {"k": String(kill.k), "sd": seed, "kill": kill.duplicate()})  # (the seed with it: the event can beat the state)


## Host: the roof plates lift, the hull splits where the debris came from (HOLE carves at seeded
## spots on the roof), and the hulk blackened round them: one a frame (_marks), so the kill's
## frame doesn't carry all of VehicleHull's carving (F-241).
func _hull_marks() -> void:
	var size := VehicleArt.size_m(vehicle.model)
	for i in int(num("debris", "holes", 4.0)):
		var p := VehicleFx.debris_spot(size, seed, i)
		_marks.append([p.x, p.y, p.z, 0.25, VehicleHull.HOLE])
		_marks.append([p.x, p.y, p.z, 0.45, VehicleHull.SCORCH])


## Host: a cook-off's pops, each a small HE event round the rack; a rack of big rounds rolls to go up.
func _cook_step(now: float) -> void:
	if now >= cook_until:
		cook_until = -1.0
		_publish()
		return
	var racks: Dictionary = fx_of(vehicle.spec).get("racks", {})
	var rack: Dictionary = racks.get(cook_rack, {})
	if bool(rack.get("big", false)) and now >= _go_next:
		_go_next = now + 1.0
		if Vehicle.fire_rolls and ArmourModel.roll(seed, ROLL_GO + pops) < num("fire", "detonate_per_s", 0.05):
			server_detonate(cook_rack)
			return
	if now < _pop_next:
		return
	pops += 1
	_pop_next = now + span("fire", "pop_gap_s", Vector2(0.5, 3.0), ArmourModel.roll(seed, ROLL_POP + pops))
	var at := _rack_point(cook_rack, pops)
	var kg := float(rack.get("pop_kg", num("fire", "pop_kg", 0.05)))
	var lvl := vehicle.level()
	if lvl and kg > 0.0:
		Warheads.server_people(lvl, at, {"blast_kg": kg, "frag_m": 3.0 * pow(kg / 0.05, 1.0 / 3.0), "frag_wounds": [0, 1], "kind": String(Vehicle.HE)}, null, [])
	VehicleFx.server_event(vehicle, "pop", {"at": at, "n": pops})


## A point in rack `rack`'s box (world), seeded by `n`.
func _rack_point(rack: String, n: int) -> Vector3:
	var box := AABB(Vector3(-0.5, 1.0, -0.5), Vector3(1.0, 1.0, 1.0))
	if vehicle.modules:
		var i := vehicle.modules.index_of(rack)
		if i >= 0 and vehicle.modules.mods[i].box is AABB:
			box = vehicle.modules.mods[i].box
	var r := Vector3(ArmourModel.roll(seed, ROLL_SPOT + n * 3), ArmourModel.roll(seed, ROLL_SPOT + n * 3 + 1), ArmourModel.roll(seed, ROLL_SPOT + n * 3 + 2))
	var local := box.position + box.size * r
	local.y = maxf(local.y, box.end.y)  # out through the top: the pops are seen
	return vehicle.to_global(local)


## Host: the crew are told to get out (once a fire); the AI aboard an armoured vehicle go
## (auto_bail), and the modules count it a crew kill.
func server_bail(reason: String) -> void:
	if not _is_host() or bailed != "":
		return
	bailed = reason
	bail_out_called.emit(reason)
	var crew: Array = vehicle.occupants()
	var callouts := Callouts.of(vehicle) if vehicle.is_inside_tree() else null
	for s: Soldier in crew:
		if s.is_ai() and s.vitals.is_up():
			if callouts:
				callouts.say(s, &"bail_out", "Bail out!")
			break
	if not auto_bail or not VehicleHud.applies(vehicle) or vehicle.kind == Vehicle.HELICOPTER or reason == "catastrophic":
		return
	var out := false
	for s: Soldier in crew:
		if s.is_ai() and s.vitals.is_up() and vehicle.seat_of(s) >= 0:
			vehicle.server_exit(s)
			out = true
	if out and vehicle.modules:
		vehicle.modules.server_bail_out()


## Host (VehicleFx): the thrown turret or the debris came to rest: they go to every peer and the save.
func server_rested(turret: Array, debris: Array) -> void:
	if not _is_host():
		return
	if not turret.is_empty():
		turret_rest = turret
	if not debris.is_empty():
		debris_rest = debris
	_publish()


func _set_stage(s: String, now: float) -> void:
	stage = s
	stage_t = now
	_publish()
	stage_changed.emit(stage)


func _new_seed() -> int:
	return absi(hash([String(vehicle.name) if vehicle else "", Engine.get_physics_frames(), Time.get_ticks_usec()])) | 1


## The vehicle's thermal heat follows the fire (ThermalView reads the meta first), every peer.
func _heat_meta() -> void:
	var h := heat()
	if h >= 0.0:
		vehicle.set_meta(ThermalView.META, snappedf(h, 0.01))
	elif vehicle.has_meta(ThermalView.META):
		vehicle.remove_meta(ThermalView.META)


# --- Net and saves ------------------------------------------------------------------------------

func _publish() -> void:
	if not _is_host():
		return
	net_state = {"st": stage, "sd": seed, "ft": fire_t, "stt": stage_t, "wt": wreck_t, "bo": snappedf(burn_out_s, 0.1), "co": snappedf(column_s, 0.1),
		"cu": cook_until, "cr": cook_rack, "k": kill.duplicate(), "tr": turret_rest.duplicate(), "dr": debris_rest.duplicate(true), "n": Soldier._now()}


func _apply_net() -> void:
	var was := stage
	stage = String(net_state.get("st", NONE))
	seed = int(net_state.get("sd", 0))
	fire_t = float(net_state.get("ft", NEVER))
	stage_t = float(net_state.get("stt", NEVER))
	wreck_t = float(net_state.get("wt", NEVER))
	burn_out_s = float(net_state.get("bo", 0.0))
	column_s = float(net_state.get("co", 0.0))
	cook_until = float(net_state.get("cu", -1.0))
	cook_rack = String(net_state.get("cr", ""))
	kill = (net_state.get("k", {}) as Dictionary).duplicate()
	turret_rest = (net_state.get("tr", []) as Array).duplicate()
	debris_rest = (net_state.get("dr", []) as Array).duplicate(true)
	_got_n = float(net_state.get("n", 0.0))
	_got_at = Soldier._now()
	if stage != was:
		stage_changed.emit(stage)
	if vehicle and vehicle.is_inside_tree():
		_heat_meta()


## Clients: the heat follows the stage between states (it cools on its own).
func _process(_delta: float) -> void:
	if not _is_host() and vehicle and stage != NONE and Engine.get_process_frames() % 30 == 0:
		_heat_meta()


## JSON-safe state for the zone save: the stage and how long it's been in it, the seed, the
## kill, where the turret and debris lie.
func to_save() -> Dictionary:
	if stage == NONE and kill.is_empty():
		return {}
	var now := Soldier._now()
	return {"stage": stage, "seed": seed, "in_stage": snappedf(maxf(now - stage_t, 0.0), 0.1), "since_wreck": snappedf(now - wreck_t, 0.1) if wreck_t > NEVER * 0.5 else -1.0,
		"burn_out_s": burn_out_s, "column_s": column_s, "kill": kill.duplicate(), "turret": turret_rest.duplicate(), "debris": debris_rest.duplicate(true),
		"cook_left": snappedf(maxf(cook_until - now, 0.0), 0.1) if cook_until > 0.0 else 0.0, "cook_rack": cook_rack, "bailed": bailed}


## Puts a to_save() back (host). A wreck from before A7 (no fire saved) smoulders.
func from_save(d: Dictionary) -> void:
	var now := Soldier._now()
	if d.is_empty():
		if vehicle and vehicle.wrecked:
			seed = _new_seed()
			stage = SMOULDER
			stage_t = now
			wreck_t = now - 3600.0  # long burnt out: no column
			column_s = 0.0
			_publish()
		return
	stage = String(d.get("stage", NONE))
	seed = int(d.get("seed", 0))
	if seed == 0:
		seed = _new_seed()
	stage_t = now - float(d.get("in_stage", 0.0))
	var since := float(d.get("since_wreck", -1.0))
	wreck_t = now - since if since >= 0.0 else NEVER
	fire_t = stage_t
	burn_out_s = float(d.get("burn_out_s", 0.0))
	column_s = float(d.get("column_s", 0.0))
	kill = (d.get("kill", {}) as Dictionary).duplicate() if d.get("kill") is Dictionary else {}
	if kill.has("r"):
		kill.r = int(kill.r)
	if not kill.is_empty():
		kill["t"] = now - 3600.0  # long done: shown where it lies, not as a fresh fireball
	turret_rest = (d.get("turret", []) as Array).duplicate() if d.get("turret") is Array else []
	debris_rest = (d.get("debris", []) as Array).duplicate(true) if d.get("debris") is Array else []
	var cook := float(d.get("cook_left", 0.0))
	cook_until = now + cook if cook > 0.0 else -1.0
	cook_rack = String(d.get("cook_rack", ""))
	bailed = String(d.get("bailed", ""))
	if cook_until > 0.0:
		_pop_next = now + 0.5
		_go_next = now + 1.0
	_publish()
