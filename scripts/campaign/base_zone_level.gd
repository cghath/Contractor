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

var fob: BaseFob


## The base zone's definition for a campaign seeded `campaign_seed` (normalized, with its crossings
## into the neighbouring zones: RegionMap, LZ-2): the same every visit.
static func def_for(campaign_seed: int) -> Dictionary:
	var def := ZoneDef.normalize({"id": ZONE_ID, "name": "FOB", "region": REGION, "kind": "base", "seed": absi(campaign_seed ^ SEED_SALT) % 1000000,
		"size_m": SIZE_M, "grow": false, "no_pallets": true,
		"modules": [{"id": "fob", "type": "fob", "pos": [0, 0]}],
		"insertion": [[0.0, BaseFob.VEHICLE_PARK.end.y + 20.0]]})
	def["crossings"] = RegionMap.crossings(RegionMap.BASE, def)
	return def


func _ready() -> void:
	super._ready()
	var m := get_module("fob")
	fob = BaseFob.make(self, m.global_position if m else Vector3.ZERO, true)


func is_base() -> bool:
	return true


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
