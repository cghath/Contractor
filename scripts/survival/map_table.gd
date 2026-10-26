class_name MapTable
extends RefCounted
## The settlement's map table (docs/survival.md call 45): a build piece ("map_table",
## BuildPieces); standing at one (REACH_M), the map (FallenMap) shows the near-real-time picture
## the settlement's friends send in (reports):
## - sightings: the last SIGHT_DAYS of events seen by groups at ALLY standing or better (their
##   scouts' and allied settlements' reports), each with who sent it;
## - trade routes: trade events of the last ROUTE_DAYS between the places the traders call home;
## - known group movements: the far groups' last known places (allies' scouting, what the players
##   were told or heard), aged.
## Static; the host reads the world, a peer's map gets the reports with the map section (later:
## for now the host's own map draws them).

const PIECE := "map_table"
## Proposed numbers.
const REACH_M := 3.0
const SIGHT_DAYS := 1.0
const ROUTE_DAYS := 3.0
const ALLY := 50.0
const MOVE_DAYS := 7.0


## The built map tables of the level `from` is in (their middles).
static func tables(from: Node) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var b := Builder.find(from)
	if b == null:
		return out
	for id: int in b.pieces:
		if String((b.pieces[id] as Dictionary).get("k", "")) == PIECE and b.is_piece_built(id):
			out.append(b.piece_pos(id))
	return out


## Whether `s` stands at a map table.
static func near(s: Soldier) -> bool:
	if s == null:
		return false
	for p: Vector3 in tables(s):
		if Vector2(p.x, p.z).distance_to(Vector2(s.global_position.x, s.global_position.z)) <= REACH_M:
			return true
	return false


## The groups at ALLY standing or better with the players.
static func allies() -> Array:
	var out: Array = []
	for g: Dictionary in (WorldSim.section().get("groups", {}) as Dictionary).values():
		if bool(g.get("alive", true)) and String(g.get("kind", "")) != "lone" and WorldGroup.relation(g, "player") >= ALLY:
			out.append(g)
	return out


## The group's home zone (else where it is): the farm's for "player".
static func home_zone(gid: String) -> String:
	if gid == "player":
		return Settlement.zone() if Settlement.exists() else String(Survival.state().get("start_zone", ""))
	var g := WorldSim.group(gid)
	var home: Dictionary = g.get("home", {})
	return String(home.get("zone", g.get("zone", ""))) if not home.is_empty() else String(g.get("zone", ""))


static func _group_name(gid: String) -> String:
	if gid == "player":
		return "the farm"
	var g := WorldSim.group(gid)
	if not g.is_empty():
		return String(g.get("name", gid))
	return String(((WorldSim.section().get("fallen", {}) as Dictionary).get(gid, {}) as Dictionary).get("name", gid))


## What the table shows now: {"sightings": [{"text", "zone", "t", "from"}], "routes": [{"a", "b",
## "a_zone", "b_zone", "t", "text"}], "movements": [{"group", "name", "zone", "t", "age", "text"}]}.
static func reports(now := -1.0) -> Dictionary:
	if now < 0.0:
		now = WorldSim.world_now()
	var ally_list := allies()
	var ally_ids := {}
	for g: Dictionary in ally_list:
		ally_ids[String(g.id)] = g
	var sightings: Array = []
	var routes: Array = []
	for e: Dictionary in WorldSim.section().get("events", []):
		var t := float(e.get("t", float(e.get("day", 0))))
		if String(e.kind) == "trade" and t >= now - ROUTE_DAYS:
			var gids: Array = e.get("groups", [])
			if gids.size() >= 2:
				var a := String(gids[0])
				var b := String(gids[1])
				routes.append({"a": a, "b": b, "a_zone": home_zone(a), "b_zone": home_zone(b), "t": t,
					"text": "%s (%s) <-> %s (%s)" % [_group_name(a), RegionMap.zone_name(home_zone(a)), _group_name(b), RegionMap.zone_name(home_zone(b))]})
		if t < now - SIGHT_DAYS or "player" in (e.get("groups", []) as Array):
			continue
		var from := ""
		for gid: String in ally_ids:
			var g: Dictionary = ally_ids[gid]
			if gid in (e.get("groups", []) as Array) or (g.get("intel", {}) as Dictionary).has(str(e.id)):
				from = String(g.name)
				break
		if from != "":
			sightings.append({"text": "Day %d %02d:00, %s: %s (from %s)" % [int(e.day), int(float(e.get("hour", 0.0))), RegionMap.zone_name(String(e.zone)), String(e.text), from],
				"zone": String(e.zone), "t": t, "from": from})
	var moves := {}
	for g: Dictionary in ally_list:
		for gid: String in (g.get("knows", {}) as Dictionary):
			var k: Dictionary = g.knows[gid]
			var kt := float(k.get("t", k.get("day", -100.0)))
			if ally_ids.has(gid) or String(k.get("zone", "")) == "" or now - kt > MOVE_DAYS:
				continue
			if not moves.has(gid) or float(moves[gid].t) < kt:
				moves[gid] = {"zone": String(k.zone), "t": kt}
	for gid: String in (Intel.section().seen_groups as Dictionary):
		var s: Dictionary = Intel.section().seen_groups[gid]
		if ally_ids.has(gid) or now - float(s.get("t", -100.0)) > MOVE_DAYS:
			continue
		if not moves.has(gid) or float(moves[gid].t) < float(s.t):
			moves[gid] = {"zone": String(s.zone), "t": float(s.t)}
	var movements: Array = []
	for gid: String in moves:
		var m: Dictionary = moves[gid]
		var age := maxf(0.0, now - float(m.t))
		movements.append({"group": gid, "name": _group_name(gid), "zone": String(m.zone), "t": float(m.t), "age": age,
			"text": "%s: last known near %s, %s" % [_group_name(gid), RegionMap.zone_name(String(m.zone)), "today" if age < 1.0 else "%d days ago" % floori(age)]})
	return {"sightings": sightings, "routes": routes, "movements": movements}


## The reports as lines (tests, the map's side list).
static func lines(r: Dictionary = {}) -> PackedStringArray:
	if r.is_empty():
		r = reports()
	var out := PackedStringArray()
	for s: Dictionary in r.get("sightings", []):
		out.append("Sighting: " + String(s.text))
	for t: Dictionary in r.get("routes", []):
		out.append("Trade route: " + String(t.text))
	for m: Dictionary in r.get("movements", []):
		out.append("Movement: " + String(m.text))
	return out
