class_name ColdOpen
extends RefCounted
## The first hour of a new world (docs/survival.md calls 41 and 64): you wake at the safehouse farm
## with the starter kit, a note from whoever was here and what they left, the nearest village
## marked on the map; the first night comes with a small local pressure so the fence matters. No
## popups: the note, the journal and the HUD's messages teach it. **Every start rolls differently**
## from the world's seed: who left the note and what they left, the thing nearby (a walker in the
## barn, the well gone bad, a wreck with a part), the day-one weather. The neighbour (a settler,
## a scavenger, a wounded stranger) comes with the people of phase B; the bunker door with phase C.
## Host-side, static, its state in Survival.state()["cold_open"] and the "journal" and "map"
## sections (the map's marks in SurvivalMap's shape: {"zone", "pos", "text", "kind", "day_added"}).

const AUTHORS := [
	{"who": "a farmer", "line": "This was my family's farm. We went for the coast when the radio said the port was holding. Take what's in the barn, God keep you."},
	{"who": "a nurse", "line": "Worked the clinic in the village till the dead filled it. Boil everything. The dressings on the shelf are clean."},
	{"who": "a deserter", "line": "Walked off the base when the officers stopped making sense. Don't trust the uniform. Left you something sharp."},
	{"who": "a hunter", "line": "Game's still in the woods if you're quiet about it. The fence is wire on the north side, I ran out. Mind the barn."},
	{"who": "a mechanic", "line": "Truck on the road east has a good battery in it, I never got it out. Tools in the shed. Water's gone bad, sorry."},
	{"who": "a teacher", "line": "I kept a map of what I saw. The village is the mark. People there once, I don't know now. Be kind if you can."},
]
## What the author left: items (ids must exist in data/items.json; missing ones are skipped).
const GIFTS := [
	[["crowbar", 1], ["canned_meat", 2]],
	[["pressure_bandage", 3], ["water_bottle", 2]],
	[["machete", 1]],
	[["hatchet", 1], ["canned_meat", 1]],
	[["wrench_set", 1], ["water_bottle", 1]],
	[["water_bottle", 2], ["canned_meat", 2]],
]
const THINGS := ["walker_in_barn", "well_gone_bad", "wreck_with_part", "quiet"]
const DAY_ONE_WEATHER := ["clear", "clear", "overcast", "fog", "rain"]
const NIGHT_PRESSURE := 25.0
const NIGHT_HOUR := 19.0
const BARN_M := 22.0
const WRECK_M := 45.0


## Host: the start zone is ready for a new world: the note, the gift, the thing, the weather, the
## mark and the journal. Once a world (Survival.state()["cold_open"]).
static func server_begin(level: SurvivalLevel) -> void:
	var st := Survival.state()
	if st.has("cold_open") or String(st.get("zone", "")) != String(st.get("start_zone", "")):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["cold_open", int(st.get("seed", 0))])
	var author: Dictionary = AUTHORS[rng.randi() % AUTHORS.size()]
	var gift: Array = GIFTS[rng.randi() % GIFTS.size()]
	var thing: String = THINGS[rng.randi() % THINGS.size()]
	var weather: String = DAY_ONE_WEATHER[rng.randi() % DAY_ONE_WEATHER.size()]
	var points := level.insertion_points()
	var home := level.ground_point(points[0]) if not points.is_empty() else level.ground_point(Vector3.ZERO)
	# The note on the table, and what they left beside it.
	var text := "%s\n\n- %s" % [String(author.line), String(author.who)]
	level.server_spawn_dropped(&"handwritten_note", 1, home + Vector3(1.2, 0.5, 0.6), {"text": text})
	var k := 0
	for e: Array in gift:
		if ItemDB.get_item(StringName(e[0])) != null:
			level.server_spawn_dropped(StringName(e[0]), int(e[1]), home + Vector3(1.6 + 0.4 * k, 0.5, 0.2 - 0.3 * k))
			k += 1
	# The nearest village or town on the map, from the note.
	var mark := _nearest_site(level, home)
	if not mark.is_empty():
		_add_mark(String(st.get("zone", "")), mark.pos, "%s (the note's mark)" % String(mark.name), "village")
	_add_mark(String(st.get("zone", "")), home, "The farm", "safehouse")
	# The thing nearby.
	var thing_note := ""
	match thing:
		"walker_in_barn":
			var barn := home + Vector3(cos(rng.randf() * TAU), 0.0, sin(rng.randf() * TAU)).normalized() * BARN_M
			var z := Survival.server_spawn_zombie(level, level.ground_point(barn), "walker")
			if z:
				z.set_meta(&"cold_open", "barn")
			thing_note = "Something moves in the barn."
		"well_gone_bad":
			st["well_bad"] = true  # (the metabolism's water: the farm's well is dirty until treated)
			thing_note = "The well water is brown. It will want boiling."
		"wreck_with_part":
			var wreck := home + Vector3(cos(rng.randf() * TAU), 0.0, sin(rng.randf() * TAU)).normalized() * WRECK_M
			var part := &"car_battery" if ItemDB.get_item(&"car_battery") != null else &"wrench_set"
			level.server_spawn_dropped(part, 1, level.ground_point(wreck) + Vector3.UP * 0.5)
			_add_mark(String(st.get("zone", "")), level.ground_point(wreck), "A wreck on the road", "wreck")
			thing_note = "There's a wreck on the road with something still in it."
		_:
			thing_note = "It's quiet. For now."
	# Day one's weather.
	var dn := DayNight.current()
	if dn and dn.is_inside_tree() and dn.multiplayer.is_server():
		dn.server_set(Survival.hour(), weather)
	st["cold_open"] = {"author": String(author.who), "gift": gift, "thing": thing, "weather": weather, "night_done": false}
	_journal("Day 1. Woke at the farm. A note on the table from %s. %s" % [String(author.who), thing_note])
	for p: Soldier in MapNodes.players(level):
		if not p.is_ai():
			p._client_message.rpc_id(p.owner_peer(), "A note on the table. Read it.")
	SessionLog.note("survival: cold open: %s left %s; %s; %s" % [String(author.who), str(gift), thing, weather])


## Host, every clock tick: the first night's pressure (once), so a few of the dead drift in.
static func server_tick(level: SurvivalLevel) -> void:
	var st := Survival.state()
	var co: Dictionary = st.get("cold_open", {})
	if co.is_empty() or bool(co.get("night_done", false)):
		return
	if Survival.day() >= 2 or (Survival.day() == 1 and Survival.hour() >= NIGHT_HOUR):
		co["night_done"] = true
		var points := level.insertion_points()
		var home := level.ground_point(points[0]) if not points.is_empty() else Vector3.ZERO
		Survival._raise_pressure(level, home + Vector3(30.0, 0.0, 0.0), NIGHT_PRESSURE)
		_journal("The first night. They come for the light and the noise.")
		for p: Soldier in MapNodes.players(level):
			if not p.is_ai():
				p._client_message.rpc_id(p.owner_peer(), "Night. Keep the light low.")


## The nearest village or town module to `from`: {"name", "pos"}, or {}.
static func _nearest_site(level: ZoneLevel, from: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for m: ZoneModule in level.modules():
		var base := ZoneModules.base(String(m.type))
		if base not in ["village", "town", "city"]:
			continue
		var d := m.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = {"name": RegionMap.zone_name(String(Survival.state().get("zone", ""))) + " " + base, "pos": m.global_position}
	return best


static func _add_mark(zone: String, pos: Vector3, text: String, kind: String) -> void:
	var st := Survival.state()
	var map: Dictionary = st.get("map", {})
	var marks: Array = map.get("marks", [])
	marks.append({"zone": zone, "pos": [pos.x, pos.y, pos.z], "text": text, "kind": kind, "day_added": Survival.day() + Survival.hour() / 24.0})
	map["marks"] = marks
	st["map"] = map


static func _journal(line: String) -> void:
	var st := Survival.state()
	var j: Array = st.get("journal", [])
	j.append({"day": Survival.day(), "hour": snappedf(Survival.hour(), 0.1), "text": line})
	st["journal"] = j.slice(-200)
