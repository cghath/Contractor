class_name Holding
extends RefCounted
## Holding or fleeing (docs/survival_people.md "Holding or fleeing", survival.md call 143): people
## judge whether they can hold their place against the dead, and abandon it when they can't.
##
## - **The judgement** (judge): the defenders' strength (an adult with a gun 1, melee only 0.5,
##   unarmed 0.2, a child 0; a guard on watch, the place's walls and defence builds add) against
##   the threat (the dead in or near the place, HOLD_M, or half that for one idling past: WALKER_THREAT
##   a head; a horde's heads count the same). The threat outweighs them: the place breaks.
## - **Live** (server_tick, from SurvivorsLayer.server_tick on the host): every household of lone
##   survivors in the hosted zone (one family, a couple, or one alone: household_key) is judged by
##   its bodies and the dead's bodies (and a horde's crowd heads) near home. Broken: the unarmed and
##   anyone whose nerve breaks run at once, the armed cover the retreat for COVER_S and follow;
##   they take food and water, shout (FLEE_LINES), run along the nearest road to the nearest safe
##   place they know (another household's home, a world group's camp, the players' farm, a town's
##   edge, else out of the zone at a crossing), the dead after the slowest. Arrived, they live there
##   (refugee_from: the place they left) or, out of the zone, are lone survivors in the next one.
##   The place left is an entry in places() (abandoned: things dropped, a note, the door open), a
##   journal line ("The Halvorsens left their farm to the dead."), a world event and a map mark.
##   A world group's live camp (WorldLive) breaks the same way: the group relocates.
## - **The sim** (sim_tick from WorldModel.step, off the hosted zone and in the catch-up): the dead
##   find a far household now and then (by the zone's dead and pressure; a horde far more); an
##   unarmed household always flees (to another household's home in the zone, else the quietest
##   neighbouring zone), an armed one holds when it's strong enough. A world group whose home a
##   horde falls on and which can't hold relocates (goal "relocate", WorldFights.horde_fight)
##   instead of fighting it out. The zone loaded again: the signs are laid (server_zone_up).
## - **The players' settlement** (settlement_tick): with the dead at the fence, unarmed settlers
##   hide behind a guard on shift or a player at home, else go to the shelter (a shelter piece, a
##   cellar hatch, else the farmhouse), never out; "Abandon" (a council question, server_ask_abandon)
##   sends everyone away.
## - **Coming back** (server_hour): a place clear of the dead for RETURN_DAYS (the players cleared
##   it, or the dead wandered off: the zone quiet) gets its refugees back; "It's clear now" (TalkMenu)
##   brings them back at once for standing.
## Every number here is Proposed.

const KEY := "abandoned"
## The judgement.
const HOLD_M := 30.0
const IDLE_SHARE := 0.5  # one of the dead idling counts only this near (of HOLD_M)
const STRENGTH_GUN := 1.0
const STRENGTH_MELEE := 0.5
const STRENGTH_UNARMED := 0.2
const GUARD_BONUS := 1.0
const DEFENCE_PER := 0.05  # a settlement's defence builds, a point each
const PLACE_DEFENCE_X := 2.0  # a world place's / group's defence (0-1)
const WALKER_THREAT := 0.3
## Nerve: an armed one runs at once under this nerve or courage, or timid.
const NERVE_RUN := 35.0
const COURAGE_RUN := 25
## Fleeing, live.
const COVER_S := 15.0
const REACH_M := 6.0
const FLEE_MAX_S := 150.0
const ROAD_M := 60.0
const SAFE_FROM_M := 60.0
const TOWARD_DEAD := 0.5
const EDGE_PENALTY_M := 200.0
const CHASE_GAP_S := 3.0
const CHASE_M := 40.0
const EDGE_IN_M := 120.0
const LEFT_ITEMS: Array[String] = ["beans_tin", "canned_meat", "water_bottle", "candles", "matches"]
const LEFT_N := Vector2i(2, 4)
const GRAB: Array[String] = ["beans_tin", "water_bottle"]
## The sim: the dead find a far household (a day, at full density; a horde in the zone); a stray
## pack is this many; a horde counts at most this many at the door; the slowest caught running.
const SIM_FIND_DAY := 0.2
const SIM_HORDE_FIND_DAY := 1.5
const SIM_STRAY_N := 3
const SIM_HORDE_CAP := 20
const SIM_CAUGHT := 0.15
const GROUP_LEAVE := 0.3
## The players' settlement.
const SHELTER_PIECES: Array[String] = ["shelter", "safe_room", "hatch"]
const SETTLE_ALERT_M := 20.0
const BEHIND_M := 3.0
## Coming back.
const CLEAR_M := 45.0
const RETURN_DAYS := 1.5
const QUIET_PRESSURE := 30.0
const CLEAR_OPINION := 12.0
const FLEE_LINES: Array[String] = ["They're coming over the fence! Run!", "Get the kids! Go, go, go!", "We can't hold them! Run for the road!"]
const COVER_LINES: Array[String] = ["Go! I'll hold them here!", "Run! I'm right behind you!"]
const CLEAR_YES := "Truly? Then we're going home. Thank you."
const CLEAR_NO := "That's not what I saw. They're still there."

static var _chase_at := -1000.0


# --- The places left ----------------------------------------------------------------------------

## Every place left to the dead, by key: {"key", "zone", "pos" [x, y, z], "ids", "names", "text",
## "word", "day", "state" ("abandoned" | "reclaimed"), "refugees", "where", "signs", "door_open",
## "clear_since" (world days, -1), "group"?, "left"?}. Kept in the world section (the sim writes it).
static func places() -> Dictionary:
	var sec: Dictionary = WorldSim.section() if WorldSim.is_set_up() else Survival.state()
	if not sec.get(KEY) is Dictionary:
		sec[KEY] = {}
	return sec[KEY]


static func entry(key: String) -> Dictionary:
	return places().get(key, {})


## Host: `e` saved (and again on a far step's result if one is out on the worker).
static func save(e: Dictionary) -> void:
	var key := String(e.get("key", ""))
	if key == "":
		return
	places()[key] = e
	var sim := WorldSim.get_sim()
	if sim and WorldSim.is_set_up() and sim._task >= 0:
		var copy := e.duplicate(true)
		sim._pending.append(func(w: Dictionary) -> void:
			if not w.get(KEY) is Dictionary:
				w[KEY] = {}
			(w[KEY] as Dictionary)[key] = copy)


static func _now_d() -> float:
	return WorldSim.world_now() if WorldSim.is_set_up() else float(Survival.day()) + Survival.hour() / 24.0


# --- The judgement ---------------------------------------------------------------------------------

## "gun", "melee" or "" by what `kit` ([{id, count}]) holds.
static func arms_of(kit: Array) -> String:
	var best := ""
	for e: Variant in kit:
		if not e is Dictionary:
			continue
		var item := ItemDB.get_item(StringName(String((e as Dictionary).get("id", ""))))
		if item == null:
			continue
		var melee := "melee" in item.tags or "blade" in item.tags
		if String(item.type) in ["weapon", "launcher"] and not melee:
			return "gun"
		if melee:
			best = "melee"
	return best


## What `rec` (in `kit`) brings to holding a place.
static func person_strength(rec: Dictionary, kit: Array) -> float:
	if Children.is_child_rec(rec):
		return 0.0
	match arms_of(kit):
		"gun":
			return STRENGTH_GUN
		"melee":
			return STRENGTH_MELEE
	return STRENGTH_UNARMED


## Whether a place holds: its strength against the threat.
static func judge(strength: float, threat: float) -> bool:
	return threat <= 0.0 or strength >= threat


## The household's strength: its people (by their kit: the body's when `layer` has one) and a
## guard (an armed adult with "guard" set) on top.
static func household_strength(members: Array, layer: SurvivorsLayer = null) -> float:
	var s := 0.0
	var guard := false
	for rec: Dictionary in members:
		var kit := _kit(rec, layer)
		s += person_strength(rec, kit)
		if bool(rec.get("guard", false)) and not Children.is_child_rec(rec) and arms_of(kit) != "":
			guard = true
	return s + (GUARD_BONUS if guard else 0.0)


static func _kit(rec: Dictionary, layer: SurvivorsLayer) -> Array:
	var b: Soldier = layer.body_of(String(rec.get("id", ""))) if layer else null
	return Survival.kit_of(b.inventory) if b else (rec.get("kit", []) as Array)


## Whether `rec` runs at once (unarmed, or their nerve breaks) rather than covering the retreat.
static func runs_at_once(rec: Dictionary, kit: Array) -> bool:
	if Children.is_child_rec(rec) or arms_of(kit) == "":
		return true
	var n: Dictionary = rec.get("needs", {})
	if not n.is_empty():
		Nerve.shake(n, "horde", rec.get("traits", []))
		if Nerve.value(n) < NERVE_RUN:
			return true
	return int(rec.get("courage", 50)) < COURAGE_RUN or SurvivorPerson.has_trait(rec, "timid")


# --- Households ----------------------------------------------------------------------------------

## The household `rec` lives in: its own "household", else its family (Children), else its partner
## (Relationships), else itself.
static func household_key(rec: Dictionary) -> String:
	var h := String(rec.get("household", ""))
	if h != "":
		return "h:" + h
	var f := String(rec.get("family", ""))
	if f != "":
		return "f:" + f
	var id := String(rec.get("id", ""))
	var p := String(rec.get("partner", ""))
	if p != "":
		return "p:" + (id if id < p else p)
	return "s:" + id


## The lone survivors' households in `zone` (out there, not on the run): key -> [records].
static func households(people: Dictionary, zone: String) -> Dictionary:
	var out := {}
	for id: String in WorldModel._sorted(people.keys()):
		var rec: Dictionary = people[id]
		if String(rec.get("status", "")) != "out_there" or String(rec.get("zone", "")) != zone or rec.has("flee") or HeliCrew.is_crew(rec):
			continue
		var k := household_key(rec)
		if not out.has(k):
			out[k] = []
		(out[k] as Array).append(rec)
	return out


## The household's head: its first adult (else its first).
static func head_of(members: Array) -> Dictionary:
	for rec: Dictionary in members:
		if not Children.is_child_rec(rec):
			return rec
	return members[0] if not members.is_empty() else {}


static func _adults(members: Array) -> int:
	return members.filter(func(r: Dictionary) -> bool: return not Children.is_child_rec(r)).size()


## "the Halvorsens" from the head's surname (one alone: their name).
static func family_name(members: Array) -> String:
	var head := head_of(members)
	var name := String(head.get("name", "someone"))
	if members.size() <= 1:
		return name
	var last := name.get_slice(" ", name.get_slice_count(" ") - 1)
	return "the %s%s" % [last, "es" if last.ends_with("s") else "s"]


static func place_word(type: String) -> String:
	match (ZoneModules.base(type) if type != "" else ""):
		"farm", "farmland":
			return "farm"
		"village", "town", "city":
			return "house"
	return "camp"


## "The Halvorsens left their farm to the dead" (one alone: "Sam Reed left his camp ...").
static func left_text(members: Array, word: String) -> String:
	var who := family_name(members)
	if members.size() <= 1:
		var head := head_of(members)
		return "%s left %s %s to the dead" % [who, "her" if String(head.get("sex", "m")) == "f" else "his", word]
	return "%s left their %s to the dead" % [who.capitalize().left(1) + who.substr(1), word]


static func _entry_key(zone: String, hkey: String, at: Vector3) -> String:
	return "h:%s:%s:%d:%d" % [zone, hkey, roundi(at.x), roundi(at.z)]


static func _v3(a: Variant) -> Vector3:
	var p: Array = a if a is Array else []
	return Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() >= 3 else Vector3.ZERO


static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


# --- Live: the tick -------------------------------------------------------------------------------

## Host, every SurvivorsLayer tick: households (and live world camps) near the dead judged and
## broken, the fleeing moved on, the settlement's people sheltered.
static func server_tick(layer: SurvivorsLayer, dead: Array) -> void:
	if layer == null or layer.level == null:
		return
	var zone := layer._zone()
	var now := Soldier._now()
	var crowd := ZoneDead.of(layer.level)
	var horde := crowd != null and crowd.horde_count() > 0
	if not dead.is_empty() or horde:
		var hh := households(SurvivorsLayer.records(), zone)
		for k: String in hh:
			var members: Array = hh[k]
			if _adults(members) == 0:
				continue  # (children alone: Children's own running)
			judge_household(layer, members, dead)
		_judge_camps(layer, dead)
	_tick_fleeing(layer, dead, now)
	settlement_tick(layer, dead)


## The threat at `at` (and about `bodies`): {"v", "n", "centre"}: the dead's bodies within HOLD_M,
## and a horde's crowd heads.
static func threat_at(layer: SurvivorsLayer, at: Vector3, bodies: Array, dead: Array) -> Dictionary:
	var n := 0
	var sum := Vector3.ZERO
	for z: Soldier in dead:
		if not is_instance_valid(z) or not z.vitals.is_up():
			continue
		var ai := ZombieAI.of(z)
		if ai and ai.dormant:
			continue  # (lying up in a nest: not at the door)
		var reach := HOLD_M if ai == null or ai.mode != ZombieAI.Mode.IDLE else HOLD_M * IDLE_SHARE  # (one shambling past, not coming at them)
		var near := _flat(z.global_position, at) <= reach
		if not near:
			for b: Soldier in bodies:
				if _flat(b.global_position, z.global_position) <= reach:
					near = true
					break
		if near:
			n += 1
			sum += z.global_position
	var crowd := ZoneDead.of(layer.level)
	if crowd:
		var at2 := Vector2(at.x, at.z)
		for d: Dictionary in crowd.dead:
			if bool(d.get("alive", false)) and bool(d.get("horde", false)) and (d.pos as Vector2).distance_to(at2) <= HOLD_M:
				n += 1
				sum += Vector3((d.pos as Vector2).x, at.y, (d.pos as Vector2).y)
	return {"v": n * WALKER_THREAT, "n": n, "centre": sum / n if n > 0 else at}


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


## Host: one household judged against the dead near home; broken, it flees. Returns whether it held.
static func judge_household(layer: SurvivorsLayer, members: Array, dead: Array) -> bool:
	var bodies: Array = []
	for rec: Dictionary in members:
		var b := layer.body_of(String(rec.id))
		if b and b.vitals.is_up():
			bodies.append(b)
	var head := head_of(members)
	var home := SurvivorPerson.pos_of(head, "home")
	var t := threat_at(layer, home, bodies, dead)
	if float(t.v) <= 0.0:
		return true
	if judge(household_strength(members, layer), float(t.v)):
		return true
	server_break(layer, members, home, t.centre)
	return false


## Host: the household `members` gives up its home at `home` to the dead coming from `from`.
## Returns the place's entry.
static func server_break(layer: SurvivorsLayer, members: Array, home: Vector3, from: Vector3) -> Dictionary:
	var zone := layer._zone()
	var head := head_of(members)
	var key := _entry_key(zone, household_key(head), home)
	var dest := safe_place(layer, home, from, members)
	var now := Soldier._now()
	var word := place_word(_type_near(layer, home))
	var text := left_text(members, word)
	var route := _route(layer, home, dest.pos as Vector3, from)
	var ids: Array = []
	var names: Array = []
	var cried := false
	for rec: Dictionary in members:
		var id := String(rec.id)
		ids.append(id)
		names.append(String(rec.get("name", "")))
		var b := layer.body_of(id)
		var kit := _kit(rec, layer)
		var covers := not runs_at_once(rec, kit)
		_grab(rec, b)
		rec["flee"] = {"to": _arr(dest.pos as Vector3), "kind": String(dest.kind), "to_zone": String(dest.get("to_zone", "")), "label": String(dest.label),
			"key": key, "since": now, "cover_until": now + COVER_S if covers else 0.0, "route": route, "leg": 0, "from": _arr(from)}
		if String(rec.get("refugee_from", "")) == "" or entry(String(rec.refugee_from)).is_empty():
			rec["refugee_from"] = key  # (running again from where they took refuge: home is still the first place)
		Moods.add(rec, "lost_home", -10.0, 48.0)
		SurvivorPerson.note(rec, "ran from the dead, leaving %s" % ("home" if word == "camp" else "the " + word))
		if b and b.vitals.is_up():
			layer._set_known(b, rec)
			if not Children.is_child_rec(rec) and (not cried or covers):
				layer.say(b, (COVER_LINES if covers else FLEE_LINES)[absi(hash([id, key])) % (COVER_LINES if covers else FLEE_LINES).size()])
				cried = true
	var e := {"key": key, "zone": zone, "pos": _arr(home), "ids": ids, "names": names, "text": text, "word": word, "day": Survival.day(),
		"state": "abandoned", "refugees": ids.duplicate(), "where": String(dest.label), "signs": true, "door_open": true, "clear_since": -1.0, "by": "the dead"}
	e["left"] = _leave_behind(layer, home, e, String(head.get("first", head.get("name", ""))))
	save(e)
	Survival._journal_line(text + ".")
	_event(zone, "abandoned", text)
	_mark(layer, home, "Abandoned: %s" % family_name(members))
	_chase_slowest(layer, Survival.zombies(layer.level))
	SessionLog.note("survival: %s (%d) fled to %s" % [family_name(members), members.size(), String(dest.label)])
	return e


## The nearest safe place `members` know from `home`, away from the dead at `from`: {"pos", "kind"
## ("place" | "edge"), "to_zone", "label"}. Another household's home, a world group's camp, the
## players' farm, a town's edge; else a crossing out of the zone (the one most away from the dead).
static func safe_place(layer: SurvivorsLayer, home: Vector3, from: Vector3, members: Array) -> Dictionary:
	var zone := layer._zone()
	var away := Vector2(home.x - from.x, home.z - from.z)
	away = away.normalized() if away.length() > 0.1 else Vector2(1.0, 0.0)
	var mine := household_key(head_of(members)) if not members.is_empty() else ""
	var cands: Array = []
	var seen := {}
	for rec: Dictionary in SurvivorsLayer.records().values():
		if String(rec.get("status", "")) != "out_there" or String(rec.get("zone", "")) != zone or rec.has("flee") or Children.is_child_rec(rec):
			continue
		var k := household_key(rec)
		if k == mine or seen.has(k):
			continue
		seen[k] = true
		cands.append({"pos": SurvivorPerson.pos_of(rec, "home"), "kind": "place", "label": "%s's place" % String(rec.get("first", rec.get("name", "someone")))})
	if WorldSim.is_set_up():
		for g: Dictionary in WorldSim.groups_in(zone):
			var h: Dictionary = g.get("home", {})
			if not bool(g.get("alive", false)) or String(g.get("kind", "")) in ["raiders", "cultists", "lone"] or h.is_empty() or String(h.get("zone", "")) != zone:
				continue
			var hp: Array = h.get("pos", [0.0, 0.0])
			cands.append({"pos": layer.level.ground_point(Vector3(float(hp[0]), 0.0, float(hp[1]))), "kind": "place", "label": String(g.get("name", "a camp"))})
	if Settlement.exists() and Settlement.zone() == zone:
		cands.append({"pos": Settlement.pos(), "kind": "place", "label": "the farm"})
	if layer.level.has_method(&"modules"):
		for m: ZoneModule in layer.level.modules():
			if not ZoneModules.base(String(m.type)) in ["village", "town"]:
				continue
			var to_home := home - m.global_position
			to_home.y = 0.0
			var edge := m.global_position + (to_home.normalized() * 30.0 if to_home.length() > 30.0 else Vector3.ZERO)
			cands.append({"pos": layer.level.ground_point(edge), "kind": "place", "label": "the edge of the %s" % ZoneModules.base(String(m.type))})
	var dead := Survival.zombies(layer.level)
	var best := {}
	var best_d := INF
	for c: Dictionary in cands:
		var p: Vector3 = c.pos
		var d := _flat(p, home)
		if d < SAFE_FROM_M or _bearing_toward(home, p, away) > TOWARD_DEAD or _dead_near(dead, p, HOLD_M):
			continue
		if d < best_d:
			best_d = d
			best = c
	for c: Dictionary in _crossings(layer):
		var p: Vector3 = c.pos
		var d := _flat(p, home) + EDGE_PENALTY_M
		if _bearing_toward(home, p, away) > TOWARD_DEAD:
			continue
		if d < best_d:
			best_d = d
			best = c
	if best.is_empty():
		var far := {}
		var far_dot := -INF
		for c: Dictionary in _crossings(layer):
			var dir := Vector2((c.pos as Vector3).x - home.x, (c.pos as Vector3).z - home.z).normalized()
			if dir.dot(away) > far_dot:
				far_dot = dir.dot(away)
				far = c
		best = far if not far.is_empty() else {"pos": layer.level.ground_point(home + Vector3(away.x, 0.0, away.y) * 150.0), "kind": "place", "label": "the fields"}
	return best


## How much the way from `home` to `p` heads at the dead (1 straight at them, -1 straight away).
static func _bearing_toward(home: Vector3, p: Vector3, away: Vector2) -> float:
	var dir := Vector2(p.x - home.x, p.z - home.z)
	return dir.normalized().dot(-away) if dir.length() > 0.1 else 0.0


static func _dead_near(dead: Array, at: Vector3, within: float) -> bool:
	for z: Soldier in dead:
		if is_instance_valid(z) and z.vitals.is_up() and _flat(z.global_position, at) <= within:
			return true
	return false


## The zone's crossings as flee destinations: {"pos", "kind": "edge", "to_zone", "label"}.
static func _crossings(layer: SurvivorsLayer) -> Array:
	var out: Array = []
	var def: Dictionary = layer.level.get(&"def") if "def" in layer.level and layer.level.get(&"def") is Dictionary else {}
	if def.is_empty():
		return out
	for c: Dictionary in RegionMap.crossings(layer._zone(), def):
		var p: Array = c.get("pos", [0.0, 0.0])
		out.append({"pos": layer.level.ground_point(Vector3(float(p[0]), 0.0, float(p[1]))), "kind": "edge", "to_zone": String(c.get("to", "")),
			"label": "the road to %s" % RegionMap.zone_name(String(c.get("to", ""))), "side": int(c.get("side", 0))})
	return out


## The way from `home` to `to`: onto the nearest road first (one within ROAD_M not toward the dead),
## then there. [[x, y, z], ...].
static func _route(layer: SurvivorsLayer, home: Vector3, to: Vector3, from: Vector3) -> Array:
	var out: Array = []
	var def: Dictionary = layer.level.get(&"def") if "def" in layer.level and layer.level.get(&"def") is Dictionary else {}
	var h2 := Vector2(home.x, home.z)
	var away := (h2 - Vector2(from.x, from.z)).normalized()
	var best := Vector2.INF
	var best_d := ROAD_M
	for r: Variant in def.get("roads", []):
		var pts: Array = []
		var raw: Variant = (r as Dictionary).get("points", []) if r is Dictionary else r
		for q: Variant in (raw if raw is Array else []):
			if q is Array and (q as Array).size() >= 2 and not (q as Array)[0] is String:
				pts.append(q)
		for i in pts.size() - 1:
			var a: Array = pts[i]
			var b: Array = pts[i + 1]
			var q := Geometry2D.get_closest_point_to_segment(h2, Vector2(float(a[0]), float(a[1])), Vector2(float(b[0]), float(b[1])))
			var d := q.distance_to(h2)
			if d < best_d and (d < 3.0 or (q - h2).normalized().dot(-away) < TOWARD_DEAD):
				best_d = d
				best = q
	if best.is_finite() and best_d > 3.0:
		out.append(_arr(layer.level.ground_point(Vector3(best.x, 0.0, best.y))))
	out.append(_arr(to))
	return out


static func _type_near(layer: SurvivorsLayer, at: Vector3) -> String:
	if layer.level == null or not layer.level.has_method(&"modules"):
		return ""
	var best := ""
	var best_d := 120.0
	for m: ZoneModule in layer.level.modules():
		var d := _flat(m.global_position, at)
		if d < best_d:
			best_d = d
			best = String(m.type)
	return best


## What they grab running: food and water (GRAB), into the body's kit (or the record's).
static func _grab(rec: Dictionary, b: Soldier) -> void:
	if Children.is_child_rec(rec):
		return
	for id: String in GRAB:
		if ItemDB.get_item(StringName(id)) == null:
			continue
		if b:
			b.inventory.take(StringName(id), 1)
		else:
			(rec.get("kit", []) as Array).append({"id": id, "count": 1})
	if b:
		rec.kit = Survival.kit_of(b.inventory)


## Host: what's left behind at `home`: a few things dropped in the hurry and a note. Returns their ids.
static func _leave_behind(layer: SurvivorsLayer, home: Vector3, e: Dictionary, by: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(e.key), "left"])
	var left: Array = []
	var pool := LEFT_ITEMS.filter(func(id: String) -> bool: return ItemDB.get_item(StringName(id)) != null)
	for i in rng.randi_range(LEFT_N.x, LEFT_N.y):
		if pool.is_empty():
			break
		var id: String = pool[rng.randi_range(0, pool.size() - 1)]
		var a := rng.randf() * TAU
		layer.level.server_spawn_dropped(StringName(id), 1, layer.level.ground_point(home + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(1.0, 3.0)) + Vector3.UP * 0.4)
		left.append(id)
	if ItemDB.get_item(&"handwritten_note") != null:
		var where := String(e.get("where", ""))
		var text := "They came over the fence and we couldn't hold it. We've gone%s. Don't stay here.%s" % [
			(" toward " + where) if where != "" else "", (" - " + by) if by != "" else ""]
		layer.level.server_spawn_dropped(&"handwritten_note", 1, layer.level.ground_point(home + Vector3(0.8, 0.0, -0.6)) + Vector3.UP * 0.5, {"text": text})
		left.append("handwritten_note")
	return left


static func _mark(layer: SurvivorsLayer, at: Vector3, text: String) -> void:
	SurvivalMap.server_add_mark(layer._zone(), at, text, "abandoned")
	var map := SurvivalMap.of(layer.level)
	if map:
		map.server_changed()


## Host: a world event (the rumours read the pool); the journal line is the caller's.
static func _event(zone: String, kind: String, text: String, gids: Array = []) -> void:
	var sim := WorldSim.get_sim()
	if sim == null or not WorldSim.is_set_up():
		return
	sim.mutate(func(_w: Dictionary) -> void:
		var m := WorldSim.model()
		m.now = WorldSim.world_now()
		m.event(zone, kind, gids, text))


## Host: the dead near anyone running go after the slowest of them (the oldest, the hurt).
static func _chase_slowest(layer: SurvivorsLayer, dead: Array) -> void:
	_chase_at = Soldier._now()
	var running: Array[Soldier] = []
	for id: String in SurvivorsLayer.records().keys():
		var rec: Dictionary = SurvivorsLayer.records()[id]
		if not rec.has("flee") or Children.is_child_rec(rec):
			continue
		var b := layer.body_of(id)
		if b and b.vitals.is_up():
			running.append(b)
	if running.is_empty():
		return
	for z: Soldier in dead:
		if not is_instance_valid(z) or not z.vitals.is_up():
			continue
		var ai := ZombieAI.of(z)
		if ai == null or (is_instance_valid(ai.target) and not (ai.target in running)):
			continue  # (one after a player, or someone else, keeps at it)
		var slowest: Soldier = null
		var worst := -INF
		for b: Soldier in running:
			if _flat(b.global_position, z.global_position) > CHASE_M:
				continue
			var rec := layer.record_of(b)
			var v := float(rec.get("age", 30)) + b.vitals.injury() * 100.0
			if v > worst:
				worst = v
				slowest = b
		if slowest:
			ai.target = slowest
			ai.mode = ZombieAI.Mode.CHASE
			ai.awareness = 1.0


# --- Live: on the run -------------------------------------------------------------------------------

static func _tick_fleeing(layer: SurvivorsLayer, dead: Array, now: float) -> void:
	var zone := layer._zone()
	var any := false
	for id: String in SurvivorsLayer.records().keys():
		var rec: Dictionary = SurvivorsLayer.records()[id]
		if not rec.has("flee") or String(rec.get("zone", "")) != zone:
			continue
		if String(rec.get("status", "")) != "out_there":
			rec.erase("flee")
			continue
		var f: Dictionary = rec.flee
		var b := layer.body_of(id)
		if b == null:
			arrive(layer, rec)
			continue
		if not b.vitals.is_up():
			continue
		any = true
		var brain := b.get_node_or_null(NodePath(PeopleLayer.BRAIN)) as CivilianAI
		var threat := _v3(f.get("from", []))
		var td := INF
		for z: Soldier in dead:
			if is_instance_valid(z) and z.vitals.is_up() and _flat(z.global_position, b.global_position) < td:
				td = _flat(z.global_position, b.global_position)
				threat = z.global_position
		if now < float(f.get("cover_until", 0.0)):
			if brain:
				brain.alarm(threat)  # covering the retreat: down where they stand, facing it
			continue
		var route: Array = f.get("route", [])
		var leg := int(f.get("leg", 0))
		var target := _v3(route[leg]) if leg < route.size() else _v3(f.to)
		if _flat(b.global_position, target) <= REACH_M:
			if leg >= route.size() - 1:
				arrive(layer, rec)
				continue
			leg += 1
			f["leg"] = leg
			target = _v3(route[leg])
		if now - float(f.get("since", now)) > FLEE_MAX_S:
			arrive(layer, rec, b.global_position)
			continue
		if brain:
			brain.alarm(threat if threat != Vector3.ZERO else b.global_position - b.global_basis.z * 5.0)
			brain._hide = target
			brain._has_hide = true
	if any and now - _chase_at >= CHASE_GAP_S:
		_chase_slowest(layer, dead)


## Host: `rec` reached where they ran to (or gave up running at `at`): a refugee living there; out
## of the zone, a lone survivor in the next one (the body goes); "home": back home again.
static func arrive(layer: SurvivorsLayer, rec: Dictionary, at := Vector3.INF) -> void:
	var f: Dictionary = rec.get("flee", {})
	rec.erase("flee")
	var id := String(rec.get("id", ""))
	var b: Soldier = layer.body_of(id) if layer else null
	var kind := String(f.get("kind", "place"))
	match kind:
		"edge":
			if b:
				layer._forget(b)
				b.queue_free()
				layer._bodies.erase(id)
			var p := _v3(f.get("to", []))
			var arr := _edge_arrival(p, layer)
			rec.zone = String(f.get("to_zone", rec.get("zone", "")))
			rec.pos = [arr.x, 0.0, arr.y]
			rec.home = [arr.x, 0.0, arr.y]
			rec["y_unset"] = true
			SurvivorPerson.note(rec, "fled into %s" % RegionMap.zone_name(String(rec.zone)))
		"home":
			var h := at if at.is_finite() else _v3(f.get("to", []))
			SurvivorPerson.set_pos(rec, h)
			SurvivorPerson.set_pos(rec, h, "home")
			if b:
				_set_home(b, h)
		_:
			var to := at if at.is_finite() else _v3(f.get("to", []))
			SurvivorPerson.set_pos(rec, to)
			SurvivorPerson.set_pos(rec, to, "home")
			if b:
				_set_home(b, to)
			SurvivorPerson.note(rec, "took refuge at %s" % String(f.get("label", "a safe place")))
	if kind != "home":
		var e := entry(String(f.get("key", "")))
		if not e.is_empty():
			e["where"] = String(f.get("label", e.get("where", "")))
			save(e)


static func _set_home(b: Soldier, at: Vector3) -> void:
	var brain := b.get_node_or_null(NodePath(PeopleLayer.BRAIN)) as CivilianAI
	if brain:
		brain._home = at
		brain._has_hide = false


## Where someone who left by crossing `p` (this zone) comes out in the next zone: the facing side,
## EDGE_IN_M in (x, z).
static func _edge_arrival(p: Vector3, layer: SurvivorsLayer) -> Vector2:
	var def: Dictionary = layer.level.get(&"def") if layer and layer.level and "def" in layer.level and layer.level.get(&"def") is Dictionary else {}
	var half := float(def.get("size_m", 1920.0)) * 0.5
	if absf(p.z) >= absf(p.x):
		return Vector2(p.x, -signf(p.z) * (half - EDGE_IN_M))
	return Vector2(-signf(p.x) * (half - EDGE_IN_M), p.z)


# --- Live: a world group's camp (WorldLive) -----------------------------------------------------------

## Host: the hosted zone's live world camps (settlers, scavengers) judged by their bodies; broken,
## the group relocates (the sim's relocate) and its people run for the crossing toward it.
static func _judge_camps(layer: SurvivorsLayer, dead: Array) -> void:
	var live := WorldLive.of(layer.level)
	if live == null or not WorldSim.is_set_up():
		return
	var zone := layer._zone()
	for gid: String in live.live.keys():
		var g := WorldSim.group(gid)
		var h: Dictionary = g.get("home", {})
		if g.is_empty() or h.is_empty() or String(h.get("zone", "")) != zone or String(g.get("kind", "")) in ["raiders", "cultists", "enclave"]:
			continue
		var bodies: Array = []
		var s := 0.0
		for pid: String in (live.live[gid].bodies as Dictionary).keys():
			var b: Soldier = live.live[gid].bodies[pid]
			if is_instance_valid(b) and b.vitals.is_up():
				bodies.append(b)
				s += person_strength(WorldSim.people().get(pid, {}), Survival.kit_of(b.inventory))
		var hp: Array = h.get("pos", [0.0, 0.0])
		var home := layer.level.ground_point(Vector3(float(hp[0]), 0.0, float(hp[1])))
		var pl := WorldRegions.place((WorldSim.section().zones as Dictionary).get(zone, {}), String(h.get("place", "")))
		s += (float(g.get("defence", 0.0)) + float(pl.get("defence", 0.0))) * PLACE_DEFENCE_X
		var t := threat_at(layer, home, bodies, dead)
		if float(t.v) <= 0.0 or judge(s, float(t.v)):
			continue
		var to_zone := ""
		WorldSim.get_sim().mutate(func(_w: Dictionary) -> void:
			var m := WorldSim.model()
			var gg := m.group(gid)
			if not gg.is_empty() and not (gg.get("home", {}) as Dictionary).is_empty():
				group_relocate(m, gg, zone, false))
		to_zone = String((WorldSim.group(gid).get("goal", {}) as Dictionary).get("zone", ""))
		var exit := home
		for c: Dictionary in _crossings(layer):
			if String(c.to_zone) == to_zone:
				exit = c.pos
		for b: Soldier in bodies:
			var brain := b.get_node_or_null(NodePath(PeopleLayer.BRAIN)) as CivilianAI
			if brain:
				brain.alarm(t.centre)
				brain._hide = exit
				brain._has_hide = true
		if not bodies.is_empty():
			layer.say(bodies[0], FLEE_LINES[absi(hash(gid)) % FLEE_LINES.size()])
		var text := "%s left their %s to the dead" % [String(g.get("name", "A group")), place_word(String(pl.get("type", "")))]
		Survival._journal_line(text + ".")
		_mark(layer, home, "Abandoned: %s" % String(g.get("name", "")))


# --- The sim (WorldModel.step, on the worker; no scene tree) -----------------------------------------

## One far tick: the dead find far households now and then; each found is judged (sim_attack).
static func sim_tick(m: WorldModel) -> void:
	var by := {}
	for pid: String in WorldModel._sorted(m.people.keys()):
		var rec: Dictionary = m.people[pid]
		if String(rec.get("status", "")) != "out_there" or rec.has("flee") or bool(rec.get("heli_crew", false)):
			continue
		var z := String(rec.get("zone", ""))
		if z == "" or z == m.hosted or not m.zones().has(z):
			continue
		var k := z + "|" + household_key(rec)
		if not by.has(k):
			by[k] = []
		(by[k] as Array).append(rec)
	for k: String in WorldModel._sorted(by.keys()):
		var members: Array = by[k]
		if _adults(members) == 0:
			continue
		var z := String((members[0] as Dictionary).zone)
		var zd := m.zone(z)
		var horde: Dictionary = zd.get("horde", {})
		var forced := members.any(func(r: Dictionary) -> bool: return bool(r.get("dead_find_test", false)))
		if not forced:
			var chance := SIM_FIND_DAY / WorldModel.TICKS_PER_DAY * clampf(float(zd.get("dead", 1.0)), 0.0, 1.0) * (1.0 + m.pressure_of(z) / 50.0)
			if not horde.is_empty():
				chance += SIM_HORDE_FIND_DAY / WorldModel.TICKS_PER_DAY
			if m.rng_for(k, "dead_find").randf() >= chance:
				continue
		for r: Dictionary in members:
			r.erase("dead_find_test")
		var heads := mini(int(horde.get("n", 0)), SIM_HORDE_CAP) if not horde.is_empty() else SIM_STRAY_N
		sim_attack(m, members, heads * WALKER_THREAT)


## The dead at a far household's door (`threat`): an armed one strong enough holds (the dead put
## down); an unarmed one always runs (sim_flee). Returns whether they held.
static func sim_attack(m: WorldModel, members: Array, threat: float) -> bool:
	var armed := members.any(func(r: Dictionary) -> bool: return not Children.is_child_rec(r) and arms_of(r.get("kit", [])) != "")
	if armed and judge(household_strength(members), threat):
		var z := String((members[0] as Dictionary).zone)
		var zd := m.zone(z)
		zd.dead = maxf(0.0, float(zd.get("dead", 1.0)) - threat / WALKER_THREAT / maxf(1.0, WorldModel.DEAD_PER_ZONE))
		for r: Dictionary in members:
			m.note(r, "held off the dead at home")
		return true
	sim_flee(m, members)
	return false


## A far household runs: another household's home in the zone (SAFE_FROM_M off), else the quietest
## neighbouring zone (a place there); food and water taken; maybe the slowest caught; the place
## left an entry, an event and a trace. Returns the entry.
static func sim_flee(m: WorldModel, members: Array) -> Dictionary:
	var head := head_of(members)
	var z := String(head.get("zone", ""))
	var hp: Array = head.get("home", head.get("pos", [0.0, 0.0, 0.0]))
	var home := Vector3(float(hp[0]), float(hp[1]) if hp.size() > 2 else 0.0, float(hp[2]) if hp.size() > 2 else float(hp[1]))
	var hkey := household_key(head)
	var key := _entry_key(z, hkey, home)
	var rng := m.rng_for(key, "flee")
	var to_zone := z
	var to := Vector2.INF
	var to_y := 0.0
	var label := ""
	var best_d := INF
	for pid: String in WorldModel._sorted(m.people.keys()):
		var o: Dictionary = m.people[pid]
		if String(o.get("status", "")) != "out_there" or String(o.get("zone", "")) != z or household_key(o) == hkey or Children.is_child_rec(o):
			continue
		var op: Array = o.get("home", o.get("pos", [0.0, 0.0, 0.0]))
		var p2 := Vector2(float(op[0]), float(op[2]) if op.size() > 2 else 0.0)
		var d := p2.distance_to(Vector2(home.x, home.z))
		if d >= SAFE_FROM_M and d < best_d:
			best_d = d
			to = p2
			to_y = float(op[1]) if op.size() > 2 and not bool(o.get("y_unset", false)) else 0.0
			label = "%s's place" % String(o.get("first", o.get("name", "someone")))
	if not to.is_finite():
		to_zone = WorldFights._quietest_link(m, z)
		var places: Array = m.zone(to_zone).get("places", [])
		var pl: Dictionary = places[rng.randi_range(0, places.size() - 1)] if not places.is_empty() else {}
		to = m._place_pos(pl, rng, 40.0) if not pl.is_empty() else Vector2.ZERO
		label = String(m.zone(to_zone).get("name", to_zone))
	var word := place_word(_sim_type_near(m, z, home))
	var text := left_text(members, word)
	var ids: Array = []
	var names: Array = []
	var slowest := ""
	var worst := -INF
	for rec: Dictionary in members:
		if not Children.is_child_rec(rec) and float(rec.get("age", 30)) > worst:
			worst = float(rec.get("age", 30))
			slowest = String(rec.id)
	var caught := ""
	if members.size() > 1 and rng.randf() < SIM_CAUGHT:
		caught = slowest
	for rec: Dictionary in members:
		var pid := String(rec.id)
		ids.append(pid)
		names.append(String(rec.get("name", "")))
		if pid == caught:
			m.person_dies(pid, m.lone_group(rec), "caught by the dead running from home", true, {"pos": [home.x, home.z]})
			continue
		var jit := Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
		rec.zone = to_zone
		rec.pos = [snappedf(to.x + jit.x, 0.01), to_y, snappedf(to.y + jit.y, 0.01)]
		rec.home = (rec.pos as Array).duplicate()
		if is_zero_approx(to_y):
			rec["y_unset"] = true  # (grounded when the zone is up: server_zone_up)
		rec["refugee_from"] = key
		if not Children.is_child_rec(rec):
			for id: String in GRAB:
				(rec.get("kit", []) as Array).append({"id": id, "count": 1})
		m.note(rec, "ran from the dead, to %s" % label)
	var e := {"key": key, "zone": z, "pos": [home.x, home.y, home.z], "ids": ids, "names": names, "text": text, "word": word, "day": m.day(),
		"state": "abandoned", "refugees": ids.filter(func(id: String) -> bool: return id != caught), "where": label, "signs": false, "door_open": true,
		"clear_since": -1.0, "by": "the dead", "y_unset": hp.size() < 3 or is_zero_approx(float(hp[1]))}
	if not m.w.get(KEY) is Dictionary:
		m.w[KEY] = {}
	(m.w[KEY] as Dictionary)[key] = e
	var pl_id := _sim_place_near(m, z, home)
	if caught != "":
		text += " (%s was caught)" % String((m.people.get(caught, {}) as Dictionary).get("name", "one"))
	m.event(z, "abandoned", [], text, pl_id)
	m.add_trace(z, pl_id, "a door left open, things dropped in a hurry, a note", [])
	return e


static func _sim_place_near(m: WorldModel, z: String, at: Vector3) -> String:
	var best := ""
	var best_d := 120.0
	for pl: Dictionary in m.zone(z).get("places", []):
		var d := WorldModel._place_v(pl).distance_to(Vector2(at.x, at.z))
		if d < best_d:
			best_d = d
			best = String(pl.get("id", ""))
	return best


static func _sim_type_near(m: WorldModel, z: String, at: Vector3) -> String:
	var pl := WorldRegions.place(m.zone(z), _sim_place_near(m, z, at))
	return String(pl.get("type", ""))


## Whether far group `g` at home in `z` holds against a horde of `n` (the fight's own sums: its
## strength and defence against the horde's; a group with no guns never does).
static func group_holds(m: WorldModel, g: Dictionary, n: int) -> bool:
	if WorldGroup.supply(g, "ammo") < 1.0 and not (g.members as Array).any(func(pid: Variant) -> bool: return arms_of((m.people.get(String(pid), {}) as Dictionary).get("kit", [])) == "gun"):
		return false
	var mine := WorldGroup.strength(g, m.people) * (1.0 + float(g.get("defence", 0.0)))
	return judge(mine, float(n) * WorldFights.HORDE_STRENGTH_PER)


## Far group `g` gives up its home in `z` to the dead: the home cleared (the place marked
## abandoned), a share of its supplies left, maybe the slowest caught (`caught_roll`), the goal
## "relocate" to the quietest neighbouring zone; an event and a trace. Returns the entry.
static func group_relocate(m: WorldModel, g: Dictionary, z: String, caught_roll := true) -> Dictionary:
	var h: Dictionary = g.get("home", {})
	var pl := WorldRegions.place(m.zone(z), String(h.get("place", "")))
	var hp: Array = h.get("pos", [0.0, 0.0])
	var gid := String(g.id)
	var key := "g:%s:%s" % [gid, String(h.get("place", ""))]
	var rng := m.rng_for(gid, "relocate")
	var caught := ""
	if caught_roll and WorldGroup.size(g) > 1 and rng.randf() < SIM_CAUGHT:
		var oldest := -INF
		for pid: Variant in g.members:
			var r: Dictionary = m.people.get(String(pid), {})
			if not Children.is_child_rec(r) and float(r.get("age", 30)) > oldest:
				oldest = float(r.get("age", 30))
				caught = String(pid)
	var word := place_word(String(pl.get("type", "")))
	var text := "%s left their %s to the dead" % [String(g.get("name", "A group")), word]
	if caught != "":
		text += " (%s was caught)" % String((m.people.get(caught, {}) as Dictionary).get("name", "one"))
		m.person_dies(caught, g, "caught by the dead as they ran", true, pl)
	for k: String in WorldGroup.SUPPLY_KEYS:
		WorldGroup.add_supply(g, k, -WorldGroup.supply(g, k) * GROUP_LEAVE)
	if not pl.is_empty():
		pl["abandoned"] = {"day": m.day(), "group": gid}
	m.clear_home(g)
	var to := WorldFights._quietest_link(m, z)
	g.goal = {"kind": "relocate", "zone": to, "place": "", "target": "", "since": m.tick(), "phase": "go", "work": 0, "from": z}
	g.journey = {}
	(g.mood as Dictionary).fear = minf(1.0, float((g.mood as Dictionary).get("fear", 0.0)) + 0.2)
	var e := {"key": key, "zone": z, "pos": [float(hp[0]), 0.0, float(hp[1])], "ids": (g.members as Array).duplicate(), "names": [], "text": text, "word": word,
		"day": m.day(), "state": "abandoned", "refugees": [], "where": String(m.zone(to).get("name", to)), "signs": false, "door_open": true,
		"clear_since": -1.0, "by": "the dead", "group": gid, "y_unset": true}
	if not m.w.get(KEY) is Dictionary:
		m.w[KEY] = {}
	(m.w[KEY] as Dictionary)[key] = e
	m.add_trace(z, String(pl.get("id", "")), "a camp left in a hurry: doors open, things dropped, a note", [])
	WorldGroup.remember(g, m.now, "horde", text)
	m.event(z, "abandoned", [gid], text, String(pl.get("id", "")))
	if WorldGroup.size(g) == 0:
		m._group_dies(g, "overrun by the dead")
	return e


## WorldGoals.act's "relocate", arrived: a free place here (the quietest) is home now.
static func sim_relocated(m: WorldModel, g: Dictionary, to: String) -> void:
	var best := {}
	for pl: Dictionary in m.zone(to).get("places", []):
		if String(pl.get("holder", "")) == "" and (best.is_empty() or float(pl.get("defence", 0.0)) > float(best.get("defence", 0.0))):
			best = pl
	if not best.is_empty():
		m.set_home(g, to, best)
		g.pos = (best.pos as Array).duplicate()
	m.event(to, "relocated", [String(g.id)], "%s came into %s, running from the dead%s" % [String(g.name), String(m.zone(to).get("name", to)),
		(", and made camp at %s" % m.place_name(to, String(best.id))) if not best.is_empty() else ""], String(best.get("id", "")))


# --- The zone comes up -------------------------------------------------------------------------------

## Host (SurvivorsLayer._server_start): people the sim moved here put on the ground; places the sim
## left here get their signs (things dropped, a note, the map mark) and a journal line.
static func server_zone_up(layer: SurvivorsLayer) -> int:
	var zone := layer._zone()
	for rec: Dictionary in SurvivorsLayer.records().values():
		if String(rec.get("zone", "")) == zone and String(rec.get("status", "")) == "out_there" and bool(rec.get("y_unset", false)):
			var p := SurvivorPerson.pos_of(rec)
			SurvivorPerson.set_pos(rec, layer.level.ground_point(p))
			SurvivorPerson.set_pos(rec, layer.level.ground_point(SurvivorPerson.pos_of(rec, "home")), "home")
			rec.erase("y_unset")
	var n := 0
	for key: String in places().keys():
		var e: Dictionary = places()[key]
		if String(e.get("zone", "")) != zone or String(e.get("state", "")) != "abandoned" or bool(e.get("signs", false)):
			continue
		var at := _v3(e.get("pos", []))
		if bool(e.get("y_unset", false)) or is_zero_approx(at.y):
			at = layer.level.ground_point(at)
			e["pos"] = _arr(at)
			e.erase("y_unset")
		e["left"] = _leave_behind(layer, at, e, "")
		e["signs"] = true
		save(e)
		Survival._journal_line("%s. The door stood open, things dropped in a hurry, a note." % String(e.get("text", "Someone left their home to the dead")))
		_mark(layer, at, "Abandoned")
		n += 1
	return n


# --- The players' settlement ---------------------------------------------------------------------------

## Host: the dead near the settlement: settlers without a weapon hide behind a guard on shift or a
## player at home, else go to the shelter; never out. The dead gone: back about their day.
static func settlement_tick(layer: SurvivorsLayer, dead: Array) -> void:
	if not Settlement.exists() or Settlement.zone() != layer._zone():
		return
	var c := Settlement.pos()
	var r := Settlement.radius()
	var near: Array[Soldier] = []
	var centre := Vector3.ZERO
	for z: Soldier in dead:
		if is_instance_valid(z) and z.vitals.is_up() and _flat(z.global_position, c) <= r + SETTLE_ALERT_M:
			near.append(z)
			centre += z.global_position
	if near.is_empty():
		for rec: Dictionary in Settlement.settlers():
			rec.erase("sheltering")
		Settlement.data().erase("breaking")
		return
	centre /= near.size()
	var held := judge(settlement_strength(layer), near.size() * WALKER_THREAT)
	if not held and not bool(Settlement.data().get("breaking", false)):
		Settlement.data()["breaking"] = true
		Survival._journal_line("The dead are over the fence and we can't hold them. Everyone to shelter!")
	var protector: Soldier = null
	var st := Settlement.find(layer)
	if st:
		for g: Dictionary in st.on_watch():
			var gb := layer.body_of(String(g.id))
			if gb and gb.vitals.is_up() and arms_of(Survival.kit_of(gb.inventory)) != "":
				protector = gb
				break
	if protector == null:
		for p: Soldier in MapNodes.players(layer.level):
			if p.vitals.is_up() and _flat(p.global_position, c) <= r + 10.0:
				protector = p
				break
	var shelter := shelter_point(layer)
	for rec: Dictionary in Settlement.settlers():
		var b := layer.body_of(String(rec.id))
		var kit := Survival.kit_of(b.inventory) if b else (rec.get("kit", []) as Array)
		if not Children.is_child_rec(rec) and arms_of(kit) != "":
			continue  # (the armed stand)
		var spot := shelter
		var how := "shelter"
		if protector:
			var back := protector.global_position - centre
			back.y = 0.0
			back = back.normalized() if back.length() > 0.1 else Vector3.BACK
			spot = protector.global_position + back * BEHIND_M
			how = "behind"
		var off := spot - c
		off.y = 0.0
		if off.length() > r * 0.8:
			spot = c + off.normalized() * r * 0.8  # (never out of the settlement)
		rec["sheltering"] = how
		var brain: CivilianAI = (b.get_node_or_null(NodePath(PeopleLayer.BRAIN)) as CivilianAI) if b else null
		if brain:
			brain.alarm(centre)
			brain._hide = spot
			brain._has_hide = true


## The settlement's strength against the dead: its settlers (by kit), a guard on watch, its
## defence builds (DEFENCE_PER a point).
static func settlement_strength(layer: SurvivorsLayer) -> float:
	var s := household_strength(Settlement.settlers(), layer)
	var st := Settlement.find(layer)
	if st and not st.on_watch().is_empty():
		s += GUARD_BONUS
	return s + float(Settlement.data().get("defence_builds", 0.0)) * DEFENCE_PER


## The settlement's shelter: a shelter piece (or a cellar hatch) within it, else the farmhouse.
static func shelter_point(layer: SurvivorsLayer) -> Vector3:
	var c := Settlement.pos()
	var b := Builder.find(layer)
	var best := c
	var best_d := INF
	if b:
		for id: int in b.pieces:
			if not String(b.pieces[id].k) in SHELTER_PIECES or not b.is_piece_built(id):
				continue
			var p := b.piece_pos(id)
			var d := _flat(p, c)
			if d <= Settlement.radius() and d < best_d:
				best_d = d
				best = p
	return best


## Host: the council asked whether to abandon the farm (call 143's "Abandon"). Returns the vote's id.
static func server_ask_abandon() -> int:
	if not Settlement.exists():
		return -1
	return Council.server_put({"kind": "abandon", "text": "Abandon the farm to the dead and run?", "risky": true}, ["abandon", "stay"],
		func(result: String) -> void: _abandon_if(result))


static func _abandon_if(result: String) -> void:
	if result == "abandon":
		server_abandon_settlement()


## Host: everyone at the settlement leaves it: lone survivors running for the edge (refugees of the
## settlement: they come back when it's clear). Returns how many went.
static func server_abandon_settlement() -> int:
	if not Settlement.exists():
		return 0
	var tree := Engine.get_main_loop() as SceneTree
	var lvl: CompoundLevel = CompoundLevel.current(tree.root) if tree else null
	var layer: SurvivorsLayer = SurvivorsLayer.find(lvl) if lvl else null
	var zone := Settlement.zone()
	var key := "s:" + zone
	var list := Settlement.settlers()
	var ids: Array = []
	var dest := {}
	if layer and layer._zone() == zone:
		var from := Settlement.pos() + Vector3(1.0, 0.0, 0.0)
		var dead := Survival.zombies(layer.level)
		if not dead.is_empty():
			from = (dead[0] as Soldier).global_position
		dest = safe_place(layer, Settlement.pos(), from, list)
	for rec: Dictionary in list:
		ids.append(String(rec.id))
		rec["status"] = "out_there"
		rec["activity"] = ""
		rec["job_now"] = ""
		rec.erase("sheltering")
		rec["refugee_from"] = key
		Moods.add(rec, "lost_home", -10.0, 48.0)
		var b: Soldier = layer.body_of(String(rec.id)) if layer else null
		if b and not dest.is_empty() and String(dest.get("label", "")) != "the farm":
			rec["flee"] = {"to": _arr(dest.pos as Vector3), "kind": String(dest.kind), "to_zone": String(dest.get("to_zone", "")), "label": String(dest.label),
				"key": key, "since": Soldier._now(), "cover_until": 0.0, "route": [_arr(dest.pos as Vector3)], "leg": 0, "from": _arr(Settlement.pos())}
			layer._set_known(b, rec)
		SurvivorPerson.note(rec, "left the farm when it was abandoned")
	save({"key": key, "zone": zone, "pos": _arr(Settlement.pos()), "ids": ids, "names": [], "text": "We left the farm to the dead", "word": "farm",
		"day": Survival.day(), "state": "abandoned", "refugees": ids.duplicate(), "where": String(dest.get("label", "")), "signs": true, "door_open": true,
		"clear_since": -1.0, "by": "the dead", "settlement": true})
	Survival._journal_line("We left the farm to the dead. Everyone ran.")
	return ids.size()


# --- Coming back ---------------------------------------------------------------------------------------

## Whether the place `e` is clear of the dead: in the hosted zone, none within CLEAR_M (the players
## cleared it, or they wandered off); elsewhere, its zone quiet (no horde, the pressure low).
static func is_clear(layer: SurvivorsLayer, e: Dictionary) -> bool:
	var z := String(e.get("zone", ""))
	if layer and layer.level and z == layer._zone():
		var at := _v3(e.get("pos", []))
		if _dead_near(Survival.zombies(layer.level), at, CLEAR_M):
			return false
		var crowd := ZoneDead.of(layer.level)
		if crowd:
			var at2 := Vector2(at.x, at.z)
			for d: Dictionary in crowd.dead:
				if bool(d.get("alive", false)) and (d.pos as Vector2).distance_to(at2) <= CLEAR_M:
					return false
		return true
	if not WorldSim.is_set_up():
		return true
	var m := WorldSim.model()
	return (m.zone(z).get("horde", {}) as Dictionary).is_empty() and m.pressure_of(z) < QUIET_PRESSURE


## Host, every world hour (SurvivorsLayer.server_hour): places clear for RETURN_DAYS get their
## refugees back. Returns how many came home.
static func server_hour(layer: SurvivorsLayer) -> int:
	var now := _now_d()
	var n := 0
	for key: String in places().keys():
		var e: Dictionary = places()[key]
		if String(e.get("state", "")) != "abandoned" or (e.get("refugees", []) as Array).is_empty():
			continue
		if not is_clear(layer, e):
			if float(e.get("clear_since", -1.0)) >= 0.0:
				e["clear_since"] = -1.0
				save(e)
			continue
		if float(e.get("clear_since", -1.0)) < 0.0:
			e["clear_since"] = now
			save(e)
			continue
		if now - float(e.clear_since) >= RETURN_DAYS:
			n += server_return(layer, key)
	return n


## Host: the refugees of place `key` go home (`by`: the player who told them it's clear). Returns how many.
static func server_return(layer: SurvivorsLayer, key: String, by: Soldier = null) -> int:
	var e := entry(key)
	if e.is_empty() or String(e.get("state", "")) != "abandoned":
		return 0
	var home := _v3(e.get("pos", []))
	var hosted: bool = (layer.level != null and layer._zone() == String(e.zone)) if layer else false
	if hosted and (bool(e.get("y_unset", false)) or is_zero_approx(home.y)):
		home = layer.level.ground_point(home)
	var n := 0
	var i := 0
	for id: Variant in e.get("refugees", []):
		var rec := SurvivorsLayer.record(String(id))
		if rec.is_empty() or String(rec.get("status", "")) != "out_there" or String(rec.get("refugee_from", "")) != key:
			continue
		n += 1
		i += 1
		rec.erase("refugee_from")
		Moods.remove(rec, "lost_home")
		Moods.add(rec, "home_again", 8.0, 24.0)
		SurvivorPerson.note(rec, "went home")
		if by:
			SurvivorPerson.change_opinion(rec, Survival.profile_of(by), CLEAR_OPINION)
		if bool(e.get("settlement", false)):
			rec.erase("flee")
			var sb: Soldier = layer.body_of(String(id)) if layer else null
			if sb:
				layer._forget(sb)
				sb.queue_free()
				layer._bodies.erase(String(id))
			Settlement.server_make_settler(rec)
			continue
		var at := home + Vector3(cos(i * 2.4), 0.0, sin(i * 2.4)) * 1.5
		var b: Soldier = layer.body_of(String(id)) if layer else null
		if b and String(rec.get("zone", "")) == String(e.zone) and b.vitals.is_up():
			rec["flee"] = {"to": _arr(at), "kind": "home", "to_zone": "", "label": "home", "key": key, "since": Soldier._now(), "cover_until": 0.0,
				"route": [_arr(at)], "leg": 0, "from": _arr(b.global_position)}  # (they walk back)
			SurvivorPerson.set_pos(rec, at, "home")
			layer._set_known(b, rec)
			continue
		if b:
			layer._forget(b)
			b.queue_free()
			layer._bodies.erase(String(id))
		rec.erase("flee")
		rec.zone = String(e.zone)
		SurvivorPerson.set_pos(rec, at)
		SurvivorPerson.set_pos(rec, at, "home")
		if not hosted:
			rec["y_unset"] = true
		else:
			rec.erase("y_unset")
	e["state"] = "reclaimed"
	e["back_day"] = Survival.day()
	save(e)
	if n > 0:
		var who := String(e.get("text", "")).get_slice(" left ", 0)
		var line := "%s went back to their %s." % [who if who != "" else "They", String(e.get("word", "home"))] if not bool(e.get("settlement", false)) else "Our people came back to the farm."
		Survival._journal_line(line)
		_event(String(e.zone), "returned", line.trim_suffix("."))
	return n


## Host: "It's clear now" said to the refugee `rec` (TalkMenu): true, they go home now and think
## better of `actor`; not, they don't believe it. Returns their line.
static func server_clear_now(layer: SurvivorsLayer, actor: Soldier, rec: Dictionary) -> String:
	var key := String(rec.get("refugee_from", ""))
	var e := entry(key)
	var body := layer.body_of(String(rec.get("id", "")))
	if key == "" or e.is_empty() or String(e.get("state", "")) != "abandoned":
		return ""
	if not is_clear(layer, e):
		if body:
			layer.say(body, CLEAR_NO)
		return CLEAR_NO
	if body:
		layer.say(body, CLEAR_YES)
	server_return(layer, key, actor)
	return CLEAR_YES
