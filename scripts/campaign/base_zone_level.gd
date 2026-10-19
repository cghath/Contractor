class_name BaseZoneLevel
extends ZoneLevel
## The base as a zone (docs/linked_zones.md LZ-1; Captain, 2026-10-18: "the player base needs to
## be in a zone of its own, one that can be explored"): a full SIZE_M zone from the campaign seed
## on the FOB's region's terrain, with the FOB built in it as its "fob" module (BaseFob: the same
## terminals, stash, delivery and muster line as BaseLevel, offset by the module's origin) and,
## outside the wire, the helipad, the vehicle park and the firing range. Nothing hostile lives
## here yet (no garrisons; LZ-5 brings the local area and its threats).
##
## It keeps BaseLevel's public face (server_spawn_stash, server_collect_stash, server_deliver,
## server_show_roster, server_read_muster_gear, muster_soldier) so BaseHub drives either. Only
## items inside the wire are stash; anything dropped elsewhere lies where it fell, in the base
## zone's own save (BaseHub.base_zone_id(): "fob", never set aside). Deploying is unchanged (the
## heli from the ops desk).

const ZONE_ID := "fob"
const SIZE_M := 2304.0
## The FOB's region (data/contracts.json "regions": inland's base is the FOB; the coast's is the LHD).
const REGION := "inland"
## Mixed into the campaign seed so the base's ground isn't any contract zone's.
const SEED_SALT := 0x0F0B
## The base's local area (docs/linked_zones.md LZ-5: "abandoned sites to scavenge, a village or two
## of civilians"): these site types, LOCAL_REACH_M from the FOB, at least LOCAL_SPACING_M apart and
## clear of the crossings. Nobody holds them (garrison_size). Proposed.
const LOCAL_SITES: Array[String] = ["village", "village", "compound", "outpost"]
const LOCAL_REACH_M := Vector2(400.0, 700.0)
const LOCAL_SPACING_M := 260.0
## Threats to the base (docs/linked_zones.md 1b, call 17): with a faction's heat (Economy.heat) at
## PATROL_HEAT or more its patrols roam the far base area (no nearer than QUIET_M to the wire); at
## PROBE_HEAT or more one probes the wire (comes within PROBE_M of it). Assaults (ASSAULT_HEAT,
## a day's warning) come separately. Proposed numbers from the doc's call 17.
const PATROL_HEAT := 30.0
const PROBE_HEAT := 50.0
const ASSAULT_HEAT := 70.0
const QUIET_M := 600.0
const PROBE_M := 120.0

var fob: BaseFob


## The base zone's definition for a campaign seeded `campaign_seed` (normalized, with its crossings
## into the neighbouring zones: RegionMap, LZ-2): the same every visit.
static func def_for(campaign_seed: int) -> Dictionary:
	var seed := absi(campaign_seed ^ SEED_SALT) % 1000000
	var def := ZoneDef.normalize({"id": ZONE_ID, "name": "FOB", "region": REGION, "kind": "base", "seed": seed,
		"size_m": SIZE_M, "grow": false, "no_pallets": true,
		"modules": [{"id": "fob", "type": "fob", "pos": [0, 0]}] + _local_sites(seed),
		"insertion": [[0.0, BaseFob.VEHICLE_PARK.end.y + 20.0]]})
	def["crossings"] = RegionMap.crossings(RegionMap.BASE, def)
	_add_threats(def, seed)
	return def


## The faction hottest against the company (Economy.heat over every faction with heat), and its
## heat: ["", 0] with none.
static func hottest() -> Array:
	var best := ""
	var most := 0.0
	var s := Campaign.section(&"economy")
	for faction: String in (s.get("heat", {}) as Dictionary):
		var h := Economy.heat(faction)
		if h > most:
			best = faction
			most = h
	return [best, most]


## Heat's patrols and probes into the base zone's def (PATROL_HEAT, PROBE_HEAT): its "patrols"
## routes and "threat_faction" (whose men walk them: _zone_enemy).
static func _add_threats(def: Dictionary, seed: int) -> void:
	var hot := hottest()
	var faction := String(hot[0])
	var heat := float(hot[1])
	if faction == "" or heat < PATROL_HEAT:
		return
	def["threat_faction"] = faction
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 13 + int(heat)
	var half := SIZE_M * 0.5 - 120.0
	var patrols: Array = []
	for k in (2 if heat >= PROBE_HEAT else 1):  # roaming the far area, round the base
		var route: Array = []
		var a0 := rng.randf() * TAU
		for i in 5:
			var a := a0 + i * TAU / 5.0
			var r := rng.randf_range(QUIET_M + 60.0, half)
			route.append([snappedf(cos(a) * r, 1.0), snappedf(sin(a) * r, 1.0)])
		patrols.append(route)
	if heat >= PROBE_HEAT:  # a probe: in from the far area to look at the wire, and out again
		var a := rng.randf() * TAU
		var out := Vector2(cos(a), sin(a))
		var near := out * (BaseFob.MODULE_HALF.x + PROBE_M * 0.5)
		patrols.append([[snappedf(out.x * half, 1.0), snappedf(out.y * half, 1.0)], [snappedf(near.x, 1.0), snappedf(near.y, 1.0)],
			[snappedf(out.x * half * 0.6 + out.y * 200.0, 1.0), snappedf(out.y * half * 0.6 - out.x * 200.0, 1.0)]])
	def["patrols"] = patrols


## The local area's sites (LOCAL_SITES) from `seed`, the same every time.
static func _local_sites(seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7 + 11
	var out: Array = []
	var placed: Array[Vector2] = [Vector2.ZERO]
	var keep_off: Array[Vector2] = []
	var half := SIZE_M * 0.5
	for side in 4:  # the crossings' sides, roughly: keep the edges' middles clear
		keep_off.append([Vector2(0, -half), Vector2(0, half), Vector2(-half, 0), Vector2(half, 0)][side])
	for type: String in LOCAL_SITES:
		for attempt in 60:
			var a := rng.randf() * TAU
			var r := rng.randf_range(LOCAL_REACH_M.x, LOCAL_REACH_M.y)
			var p := Vector2(cos(a), sin(a)) * r
			if placed.any(func(q: Vector2) -> bool: return q.distance_to(p) < LOCAL_SPACING_M):
				continue
			if keep_off.any(func(q: Vector2) -> bool: return q.distance_to(p) < 450.0):
				continue
			placed.append(p)
			out.append({"id": "%s_%d" % [type, out.size() + 1], "type": type, "pos": [p.x, p.y]})
			break
	return out


func _ready() -> void:
	super._ready()
	var m := get_module("fob")
	fob = BaseFob.make(self, m.global_position if m else Vector3.ZERO, true)
	# Supports come and go from the helipad here (docs/linked_zones.md section 4, LZ-3).
	var pad := Marker3D.new()
	pad.name = "HelipadOrigin"
	var c := BaseFob.HELIPAD.get_center()
	pad.position = Vector3(c.x, 0.2, c.y)
	fob.add_child(pad)
	Supports.register_origin(&"fob", pad)
	var assault := BaseAssault.new()
	assault.name = BaseAssault.NODE_NAME
	add_child(assault)  # an assault booked for today comes in (LZ-5)


func is_base() -> bool:
	return true


## Whose men come at the base: the faction hottest against the company (_add_threats), else the
## usual.
func _zone_enemy() -> String:
	var t := String(def.get("threat_faction", ""))
	return t if t != "" else super._zone_enemy()


## Nobody holds the base's local sites (LZ-5: threats come from heat, not garrisons).
func garrison_size(_module_id: String) -> int:
	return 0


## The FOB's terminals and muster line stand on the module's flattened pad from the start.
func fob_ready() -> bool:
	return true


func level_info() -> Dictionary:
	return {"level": "base_zone", "def": def}


func next_spawn_point() -> Vector3:
	_spawn_index += 1
	return spawn_point(_spawn_index)


## Players come in (and respawn) inside the FOB's gate, not at the zone's insertion point; coming
## home through a crossing (def "arrive", LZ-2), at that crossing.
func spawn_point(index: int) -> Vector3:
	if String(def.get("arrive", "")) != "" or fob == null:
		return super.spawn_point(index)
	return fob.spawn_point(index)


func _player_start(_id: int) -> Vector3:
	return next_spawn_point()


## The zone's save is loaded: what was dropped inside the wire is the stash's (BaseHub lays the
## stash out again), so it doesn't come back a second time from the save.
func _zone_loaded() -> void:
	for uid: String in GameState.dropped.keys():
		var p: Array = GameState.dropped[uid].get("pos", [0, 0, 0])
		if fob.holds(Vector3(float(p[0]), float(p[1]), float(p[2]))):
			GameState.dropped.erase(uid)


## Host: the zone comes up (its save, terrain, the host's player), then the stash and the muster
## line, as at the hub.
func _on_hosted() -> void:
	super._on_hosted()
	server_spawn_stash(BaseHub.stash())
	server_show_roster()
	if people:
		people._spawn_civilians()  # the local villages' people (LZ-5)
	var extraction := MapNodes.extraction(self)
	if extraction:
		extraction.server_open_crossings()  # the way out into the neighbouring zones (LZ-2)
	BaseHub.server_level_ready(self)


# --- The FOB's public face (BaseFob) ------------------------------------------------------

func server_spawn_stash(stash: Array) -> void:
	fob.server_spawn_stash(stash)


func server_collect_stash() -> Array:
	return fob.server_collect_stash()


func server_deliver(id: StringName, count: int, state := {}) -> void:
	fob.server_deliver(id, count, state)


func server_show_roster() -> void:
	fob.server_show_roster()


func server_read_muster_gear() -> Dictionary:
	return fob.server_read_muster_gear()


func muster_soldier(mid: String) -> Soldier:
	return fob.muster_soldier(mid)
