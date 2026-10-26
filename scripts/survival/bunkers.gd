class_name Bunkers
extends RefCounted
## ARCHE's bunkers (docs/survival_world.md section 7, call 62; docs/survival_enclave.md): a
## place type of its own, 3-6 a world by seed (data/bunkers.json), never in the farm's zone or
## the city. A bunker is a sealed door at a place of its zone (a door record with a position in
## the zone, beside the zone's modules: no ZoneModule type fits a hatch in the ground) that opens
## by its code at a powered keypad (the code from ARCHE's trail; power from a battery or a jerrycan
## for the generator), a torch cut or a breach charge (loud: the zone's pressure). Inside, a room
## or two (the prefabs: stores, medical, armoury, quarters), each stocked from its loot table
## (meds, ammo, a serum's chance) with a piece of ARCHE's trail among them (ArcheTrail.items_at,
## or a fragment); a trap or two (a tripwire: noise and pressure; a gas pocket: taint on whoever
## trips it); sometimes the dead sealed in (spawned at the door when it opens, the hazmat kind
## among them), sometimes a survivor (a lone survivor at the door). Opened, it's an event the
## zone's groups know; raiders in its zone may claim it on a later day.
##
## Live: when its zone is hosted, an opened bunker's rooms are WorldCaches at the door (the zone
## save keeps what's taken); the dead and the survivor appear when it opens with the zone hosted,
## or the next time it is. State: Survival.state()["bunkers"]: {"list": [bunker], "spawned":
## {bunker id: true}}. Bunker { id, name, zone, place, pos: [x, z], code, door: {state: sealed |
## open, power: bool, how}, rooms: [{role, label, size, loot: [{id, count, state?}], trap: {kind,
## tripped} | {}, searched}], sealed_dead: n, dead_out: bool, survivor: person id | "",
## opened_day, claimed_by: group id }.

const KEY := "bunkers"
const PATH := "res://data/bunkers.json"
## Proposed: the door's spot off its place (m), the caches' spread at the door.
const DOOR_OFF := 18.0
const CACHE_STEP := 1.4
const TIERS: Array[String] = ["common", "uncommon", "rare", "very_rare"]

static var _data := {}


static func bunker_data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = ModKit.overlay("bunkers", JSON.parse_string(f.get_as_text()) if f else null)  # (mods: docs/fallen_modding.md)
		_data = parsed if parsed is Dictionary else {"tables": {}, "prefabs": [], "names": ["Site 1"]}
	return _data


static func data() -> Dictionary:
	var st := Survival.state()
	if not st.get(KEY) is Dictionary:
		st[KEY] = {}
	return st[KEY]


static func is_set_up() -> bool:
	return data().has("list")


static func list() -> Array:
	return data().get("list", [])


static func get_bunker(id: String) -> Dictionary:
	for b: Dictionary in list():
		if String(b.id) == id:
			return b
	return {}


static func in_zone(zone_id: String) -> Array:
	return list().filter(func(b: Dictionary) -> bool: return String(b.zone) == zone_id)


static func _v(data_key: String, fallback: Variant) -> Variant:
	return bunker_data().get(data_key, fallback)


# --- Loot ----------------------------------------------------------------------------------------

## A roll of loot table `table` (data/bunkers.json's tables: the bunkers' rooms, and "hospital" /
## "lab" for the cure chain's places): one tier by tier_weights, one bundle of it. [{id, count}].
static func roll_table(table: String, r: RandomNumberGenerator) -> Array:
	var t: Dictionary = (bunker_data().get("tables", {}) as Dictionary).get(table, {})
	if t.is_empty():
		return []
	var weights: Dictionary = bunker_data().get("tier_weights", {"common": 1})
	var total := 0.0
	for k: String in TIERS:
		total += float(weights.get(k, 0.0))
	var roll := r.randf() * total
	var tier := "common"
	for k: String in TIERS:
		roll -= float(weights.get(k, 0.0))
		if roll <= 0.0:
			tier = k
			break
	var bundles: Array = t.get(tier, t.get("common", []))
	if bundles.is_empty():
		return []
	var out: Array = []
	for row: Array in bundles[r.randi_range(0, bundles.size() - 1)]:
		var n := int(row[1]) if row.size() < 3 else r.randi_range(int(row[1]), int(row[2]))
		out.append({"id": String(row[0]), "count": n})
	return out


# --- Laying --------------------------------------------------------------------------------------

## The bunkers of a world (pure: the same seed and zones give the same list): COUNT by the seed in
## zones that aren't the farm's or the city's, one a zone, each at one of its places, with a code,
## rooms from the prefabs (their loot rolled), traps, maybe the sealed dead, maybe a survivor.
static func lay(world_seed: int, zones: Dictionary, start_zone: String) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash([world_seed, "bunkers"])
	var count_r: Array = _v("count", [3, 6])
	var n := r.randi_range(int(count_r[0]), int(count_r[1]))
	var pool := WorldModel._sorted(zones.keys()).filter(func(z: String) -> bool:
		var zd: Dictionary = zones[z]
		return z != start_zone and String(zd.get("region", "")) != "city" and not (zd.get("places", []) as Array).is_empty())
	var names: Array = (_v("names", ["Site 1"]) as Array).duplicate()
	var prefabs: Array = _v("prefabs", [])
	var rooms_r: Array = _v("rooms", [2, 3])
	var traps_r: Array = _v("traps", [1, 2])
	var out: Array = []
	for i in mini(n, pool.size()):
		var z := String(pool.pop_at(r.randi_range(0, pool.size() - 1)))
		var zd: Dictionary = zones[z]
		var places: Array = zd.places
		var pl: Dictionary = places[r.randi_range(0, places.size() - 1)]
		var a := r.randf() * TAU
		var p: Array = pl.get("pos", [0.0, 0.0])
		var pos := [snappedf(float(p[0]) + cos(a) * DOOR_OFF, 0.1), snappedf(float(p[1]) + sin(a) * DOOR_OFF, 0.1)]
		var nm: String = String(names.pop_at(r.randi_range(0, names.size() - 1))) if not names.is_empty() else "Site %d" % (i + 1)
		var b := {"id": "bunker%d" % (i + 1), "name": nm, "zone": z, "place": String(pl.get("id", "")), "pos": pos,
			"code": "%04d" % r.randi_range(0, 9999), "door": {"state": "sealed", "power": false, "how": ""}, "rooms": [],
			"sealed_dead": 0, "dead_out": false, "survivor": "", "opened_day": -1.0, "claimed_by": ""}
		var picks := prefabs.duplicate()
		for k in r.randi_range(int(rooms_r[0]), int(rooms_r[1])):
			if picks.is_empty():
				break
			var pf: Dictionary = picks.pop_at(r.randi_range(0, picks.size() - 1))
			var loot := roll_table(String(pf.table), r)
			(b.rooms as Array).append({"role": String(pf.role), "label": String(pf.get("label", "Locker")), "size": (pf.get("size", [4.0, 4.0]) as Array).duplicate(),
				"at": [0.0, -4.0, -4.0 - 5.0 * k], "loot": loot, "trap": {}, "searched": false})
		var rooms: Array = b.rooms
		for k in mini(r.randi_range(int(traps_r[0]), int(traps_r[1])), rooms.size()):
			var room: Dictionary = rooms[r.randi_range(0, rooms.size() - 1)]
			if (room.trap as Dictionary).is_empty():
				room.trap = {"kind": "gas" if r.randf() < float(_v("gas_share", 0.5)) else "tripwire", "tripped": false}
		if r.randf() < float(_v("sealed_dead_chance", 0.4)):
			var sd: Array = _v("sealed_dead", [3, 8])
			b.sealed_dead = r.randi_range(int(sd[0]), int(sd[1]))
		b["has_survivor"] = r.randf() < float(_v("survivor_chance", 0.2))
		out.append(b)
	return out


## Host: the bunkers on world `m` (once): laid, their trail pieces put in their rooms' loot (or a
## fragment: always a piece of the trail), a survivor's Person made for those that have one.
static func server_setup(m: WorldModel) -> void:
	if is_set_up():
		return
	var bl := lay(m.world_seed, m.zones(), String(m.w.get("start_zone", "")))
	data()["list"] = bl
	data()["spawned"] = {}
	SessionLog.note("survival bunkers: %d (%s)" % [bl.size(), ", ".join(PackedStringArray(bl.map(func(b: Dictionary) -> String: return "%s in %s" % [String(b.name), String(b.zone)])))])


## Host: the trail's pieces at each bunker go into its rooms (ArcheTrail lays the trail after the
## bunkers; it calls this when it's laid).
static func server_stock_trail() -> void:
	for b: Dictionary in list():
		if bool(b.get("trail_stocked", false)):
			continue
		b["trail_stocked"] = true
		var rooms: Array = b.rooms
		if rooms.is_empty():
			continue
		var items := ArcheTrail.items_at(String(b.id))
		if items.is_empty():
			items.append(ArcheTrail.fragment(FallenStory.rng(String(b.id), "fragment")))
		for i in items.size():
			((rooms[i % rooms.size()] as Dictionary).loot as Array).append(items[i])


## The ARCHE trail items in bunker `b`'s rooms.
static func trail_items(b: Dictionary) -> Array:
	var out: Array = []
	for room: Dictionary in b.get("rooms", []):
		for e: Dictionary in room.get("loot", []):
			if String(e.id) in ArcheTrail.ITEMS:
				out.append(e)
	return out


# --- Opening -------------------------------------------------------------------------------------

## Whether `b`'s door is open.
static func is_open(b: Dictionary) -> bool:
	return String((b.get("door", {}) as Dictionary).get("state", "")) == "open"


## Host: power to bunker `id`'s keypad: `s` spends a power item (a battery, a jerrycan for the
## generator), or `free` (a generator wired by the building lane). Returns why not.
static func server_power(id: String, s: Soldier = null, free := false) -> String:
	var b := get_bunker(id)
	if b.is_empty():
		return "No such bunker"
	if bool(b.door.power):
		return ""
	if not free:
		var spent := false
		for it: String in _v("power_items", ["vehicle_battery", "jerrycan"]):
			if FallenStory.take_one(s, it):
				spent = true
				break
		if not spent:
			return "The keypad is dead: it needs a battery or fuel for the generator"
	b.door.power = true
	if s:
		Survival._tell(s, "The keypad lights up")
	return ""


## Host: bunker `id`'s door opened `how`: "code" (the keypad powered and `code` right, or the
## players know it from the trail when `code` is ""), "torch" (`s` carries a cutting torch),
## "breach" (`s` spends a breach charge: loud). On opening: an event the zone's groups know, the
## sealed dead and the survivor out (live now if the zone is hosted), the rooms' caches. Returns
## why not ("" done).
static func server_open(id: String, how: String, s: Soldier = null, code := "") -> String:
	var b := get_bunker(id)
	if b.is_empty():
		return "No such bunker"
	if is_open(b):
		return ""
	var pressure := 0.0
	match how:
		"code":
			if not bool(b.door.power):
				return "The keypad is dead"
			var tried := code if code != "" else (String(b.code) if ArcheTrail.knows_code(id) else "")
			if tried != String(b.code):
				return "Wrong code" if tried != "" else "You don't know the code"
		"torch":
			if not FallenStory.has_item(s, String(_v("torch_item", "cutting_torch"))):
				return "You need a cutting torch"
			pressure = float(_v("torch_pressure", 8.0))
		"breach":
			if not FallenStory.take_one(s, String(_v("breach_item", "breaching_charge"))):
				return "You need a breaching charge"
			pressure = float(_v("breach_pressure", 30.0))
		_:
			return "That won't open it"
	b.door.state = "open"
	b.door.how = how
	b.opened_day = WorldSim.world_now()
	var title := "ARCHE %s" % String(b.name)
	var zone_id := String(b.zone)
	var p: Array = b.pos
	if pressure > 0.0:
		_pressure(zone_id, Vector3(float(p[0]), 0.0, float(p[1])), pressure)
	if bool(b.get("has_survivor", false)) and String(b.survivor) == "":
		_survivor_out(b)
	FallenStory.event(zone_id, "bunker_opened", ["player"], "%s in %s was opened%s" % [title, FallenStory.zone_name(zone_id),
		" (blown open)" if how == "breach" else ""], String(b.place), {"bunker": id})
	Survival._journal_line("We opened %s in %s%s." % [title, FallenStory.zone_name(zone_id), (" (%d of the dead were sealed in with it)" % int(b.sealed_dead)) if int(b.sealed_dead) > 0 else ""])
	SurvivalMap.server_add_mark(zone_id, [float(p[0]), 0.0, float(p[1])], "%s (open)" % title, "arche")
	server_spawn_live(b)
	return ""


static func _pressure(zone_id: String, at: Vector3, amount: float) -> void:
	if zone_id == WorldSim.hosted_zone():
		var tree := Engine.get_main_loop() as SceneTree
		var lvl: CompoundLevel = CompoundLevel.current(tree.root) if tree else null
		if lvl:
			Survival._raise_pressure(lvl, at, amount)
		return
	FallenStory.world_do(func(_w: Dictionary) -> void:
		var m := WorldSim.model()
		m.raise_pressure(zone_id, amount, Vector2(at.x, at.z)))


## The survivor who waited it out inside: a lone survivor at the door (SurvivorsLayer shows them
## when the zone is hosted; the companion pool).
static func _survivor_out(b: Dictionary) -> void:
	var p: Array = b.pos
	var made: Array = []
	var bid := String(b.id)
	FallenStory.world_do(func(w: Dictionary) -> void:
		if not made.is_empty():
			return
		var m := WorldModel.new(w, WorldSim.people(), WorldSim.pressure_section(), WorldSim.world_seed())
		m.now = WorldSim.world_now()
		var r := FallenStory.rng(bid, "survivor")
		var g := m.new_lone(String(b.zone), Vector2(float(p[0]) + 2.0, float(p[1]) + 2.0), r, "came up out of an ARCHE bunker after months sealed in")
		made.append(String(g.leader)))
	if made.is_empty():
		return
	b.survivor = String(made[0])
	var rec: Dictionary = WorldSim.people().get(b.survivor, {})
	rec["from_bunker"] = bid
	Survival._journal_line("Someone was still alive inside: %s." % String(rec.get("name", "a survivor")))


## Host: bunker `b`'s live side in the hosted zone (when open and its zone is hosted): its
## rooms' caches at the door, the sealed dead let out (once), the survivor stood at the door.
static func server_spawn_live(b: Dictionary) -> void:
	if not is_open(b) or String(b.zone) != WorldSim.hosted_zone():
		return
	var tree := Engine.get_main_loop() as SceneTree
	var level: SurvivalLevel = (CompoundLevel.current(tree.root) as SurvivalLevel) if tree else null
	if level == null:
		return
	var p: Array = b.pos
	var door := level.ground_point(Vector3(float(p[0]), 0.0, float(p[1])))
	var spawned: Dictionary = data().get("spawned", {})
	if not bool(b.get("dead_out", false)) and int(b.get("sealed_dead", 0)) > 0:
		b.dead_out = true
		var r := FallenStory.rng(String(b.id), "dead")
		for i in int(b.sealed_dead):
			var a := TAU * i / maxf(1.0, float(b.sealed_dead))
			var at := level.ground_point(door + Vector3(cos(a), 0.0, sin(a)) * (3.0 + r.randf() * 3.0))
			Survival.server_spawn_zombie(level, at, "hazmat" if r.randf() < float(_v("hazmat_share", 0.3)) else "walker")
	if not bool(spawned.get(String(b.id), false)) and level.cache_spawner != null:
		spawned[String(b.id)] = true
		data()["spawned"] = spawned
		var rooms: Array = b.rooms
		for i in rooms.size():
			var room: Dictionary = rooms[i]
			var at := level.ground_point(door + Vector3(CACHE_STEP * (i - (rooms.size() - 1) * 0.5), 0.0, -2.0))
			var cache := level.cache_spawner.spawn({"uid": "%s_room%d" % [String(b.id), i], "pos": at, "yaw": 0.0, "label": String(room.label)}) as WorldCache
			if cache:
				cache.server_fill(room.loot)
	var rec: Dictionary = WorldSim.people().get(String(b.get("survivor", "")), {})
	if not rec.is_empty() and bool(rec.get("y_unset", false)):
		SurvivorPerson.set_pos(rec, level.ground_point(door + Vector3(2.0, 0.0, 2.0)))
		SurvivorPerson.set_pos(rec, level.ground_point(door + Vector3(2.0, 0.0, 2.0)), "home")
		rec.erase("y_unset")


## Host: `s` goes into room `index` of bunker `id`: its trap goes off if it hasn't (a tripwire:
## noise and the zone's pressure; a gas pocket: taint on his survivor record), and he gets what's
## in it (the rooms' items into his kit when the live caches aren't there: the far way in).
## Returns what happened.
static func server_enter_room(id: String, index: int, s: Soldier = null, take := true) -> String:
	var b := get_bunker(id)
	if b.is_empty() or not is_open(b):
		return "It's sealed"
	var rooms: Array = b.rooms
	if index < 0 or index >= rooms.size():
		return "No such room"
	var room: Dictionary = rooms[index]
	var said := ""
	var trap: Dictionary = room.trap
	if not trap.is_empty() and not bool(trap.get("tripped", false)):
		trap.tripped = true
		var p: Array = b.pos
		var at := Vector3(float(p[0]), 0.0, float(p[1]))
		if String(trap.kind) == "gas":
			var taint := float(_v("gas_taint", 25.0))
			if s:
				var rec := Survival.survivor_of(s)
				rec["taint"] = float(rec.get("taint", 0.0)) + taint
				Survival._tell(s, "Gas: your eyes and throat burn (taint)")
			said = "a gas pocket (taint +%d)" % roundi(taint)
		else:
			_pressure(String(b.zone), at, float(_v("tripwire_pressure", 15.0)))
			if s:
				Survival.server_noise(s, s.global_position, 40.0, 0.8)
				Survival._tell(s, "A tripwire: cans and a klaxon")
			said = "a tripwire (noise)"
	if take and s and not bool(room.get("searched", false)) and not bool((data().get("spawned", {}) as Dictionary).get(String(b.id), false)):
		room.searched = true
		for e: Dictionary in room.loot:
			s.inventory.take(StringName(String(e.id)), int(e.count), e.get("state", {}))
	return said


# --- The far tick ------------------------------------------------------------------------------

## Host, after a far tick: opened bunkers in the hosted zone come live (their caches, dead,
## survivor); once a day an opened, unclaimed bunker may be claimed by raiders in its zone.
static func server_after_step(m: WorldModel) -> void:
	if not is_set_up():
		return
	for b: Dictionary in list():
		if not is_open(b):
			continue
		if String(b.zone) == m.hosted:
			server_spawn_live(b)
		elif String(b.get("claimed_by", "")) == "" and m.tick() % WorldModel.TICKS_PER_DAY == 0:
			for g: Dictionary in m.groups_in_zone(String(b.zone)):
				if String(g.kind) == "raiders" and bool(g.alive) and m.rng_for(String(b.id), "claim").randf() < float(_v("claim_chance", 0.25)):
					b.claimed_by = String(g.id)
					m.event(String(b.zone), "bunker_claimed", [String(g.id)], "%s have taken over ARCHE %s in %s" % [String(g.name), String(b.name),
						String(m.zone(String(b.zone)).get("name", b.zone))], String(b.place))
					break
