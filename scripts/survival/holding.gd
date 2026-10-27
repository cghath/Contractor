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
##   hide behind a guard on shift or a player at home, else go to the shelter (a shelter room: a
##   "shelter" marker in a room walled round with a "safe_room_door", shelter_room; else a cellar
##   hatch, else the farmhouse), never out; inside a shelter room with its door shut the dead pass
##   them by (sheltered) till the door's broken down; "Abandon" (a council question, server_ask_abandon)
##   sends everyone away.
## - **Coming back** (server_hour): a place clear of the dead for RETURN_DAYS (the players cleared
##   it, or the dead wandered off: the zone quiet) gets its refugees back; "It's clear now" (TalkMenu)
##   brings them back at once for standing.
## - **Joining** (join_on_arrival, sim_flee): a fleeing household that reaches a held place joins
##   it: another household (one household now, what they carried shared, a "took us in" bond:
##   join_household), a world group's camp (members: take_in; a starving or hostile group turns
##   them away and they go on to the next safe place: group_refuses), the players' farm (they ask
##   to stay: server_ask_stay, a council vote or a player's yes in talk: server_let_stay).
## - **Claiming** (server_claim, from a ClaimPost at the place): a place left to the dead (or an empty
##   homestead a survivor comes near: server_find_empty) is the players' when nobody lives there
##   and the dead aren't within CLAIM_DEAD_M: what's left there theirs (server_take_stock), the
##   map's mark "Ours", the safehouse there if they like (server_make_safehouse), the settlement
##   moved there by the council's vote (server_make_settlement). Its people coming back ask to stay.
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
## The players' settlement: the shelter's fallback after a shelter room (a floor hatch); a shelter
## room (shelter_room) is closed within ROOM_SPAN cells of its marker, at most ROOM_MAX cells.
const SHELTER_PIECES: Array[String] = ["hatch"]
const SHELTER_MARK := "shelter"
const SHELTER_DOOR := "safe_room_door"
const ROOM_SPAN := 12
const ROOM_MAX := 400
const SETTLE_ALERT_M := 20.0
const BEHIND_M := 3.0
## Coming back.
const CLEAR_M := 45.0
const RETURN_DAYS := 1.5
const NOT_CLEAR := -1.0e9  # (clear_since: not clear now; world time can be under RETURN_DAYS early on)
const QUIET_PRESSURE := 30.0
const CLEAR_OPINION := 12.0
const FLEE_LINES: Array[String] = ["They're coming over the fence! Run!", "Get the kids! Go, go, go!", "We can't hold them! Run for the road!"]
const COVER_LINES: Array[String] = ["Go! I'll hold them here!", "Run! I'm right behind you!"]
const CLEAR_YES := "Truly? Then we're going home. Thank you."
const CLEAR_NO := "That's not what I saw. They're still there."
## Joining: the bond a refugee feels for who took them in (and theirs back); a group turns refugees
## away under this many days of food, or at this relation or worse; what one adds to its supplies.
const TOOK_IN_REL := 15.0
const HOST_REL := 5.0
const REFUGE_FOOD_DAYS := 1.0
const REFUGE_HOSTILE := -10.0
const REFUGE_SUPPLY := 0.5
const SKIP_MAX := 3
const STAY_LINES: Array[String] = ["We've nowhere else. Let us stay, we'll work.", "Please. We ran from the dead. Can we stay?"]
const REFUSED_LINES: Array[String] = ["They won't have us. We keep going.", "No room for us here. Come on."]
const STAY_YES := "Thank you. You won't regret it."
const STAY_NO := "Then we'll go. Good luck to you."
## Claiming: no claim with the dead this near or anyone living within CLAIM_INSIDE_M; the claimer
## within CLAIM_REACH_M; the world place under it within CLAIM_PLACE_M; a camp's supplies left
## behind as things (STOCK_ITEMS, at most STOCK_MAX a kind); empty homesteads (EMPTY_TYPES) found
## within EMPTY_SEEN_M of a survivor, looked for every EMPTY_CHECK_S.
const CLAIM_DEAD_M := 30.0
const CLAIM_INSIDE_M := 12.0
const CLAIM_REACH_M := 10.0
const CLAIM_PLACE_M := 40.0
const STOCK_ITEMS := {"food": "beans_tin", "water": "water_bottle", "meds": "pressure_bandage", "fuel": "jerrycan", "wood": "planks", "scrap": "scrap_sheet"}
const STOCK_MAX := 12
const EMPTY_TYPES: Array[String] = ["farm", "farmland"]
const EMPTY_SEEN_M := 60.0
const EMPTY_CHECK_S := 5.0

static var _chase_at := -1000.0
static var _empty_at := -1000.0


# --- The places left ----------------------------------------------------------------------------

## Every place left to the dead, by key: {"key", "zone", "pos" [x, y, z], "ids", "names", "text",
## "word", "day", "state" ("abandoned" | "reclaimed"), "refugees", "where", "signs", "door_open",
## "clear_since" (world days; NOT_CLEAR when not clear), "group"?, "left"?}. Kept in the world section (the sim writes it).
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
	if now - _empty_at >= EMPTY_CHECK_S or now < _empty_at:
		_empty_at = now
		server_find_empty(layer)  # (empty homesteads a survivor comes near: places to claim)


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
			"key": key, "since": now, "cover_until": now + COVER_S if covers else 0.0, "route": route, "leg": 0, "from": _arr(from), "join": String(dest.get("join", ""))}
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
		"state": "abandoned", "refugees": ids.duplicate(), "where": String(dest.label), "signs": true, "door_open": true, "clear_since": NOT_CLEAR, "by": "the dead"}
	e["left"] = _leave_behind(layer, home, e, String(head.get("first", head.get("name", ""))))
	save(e)
	Survival._journal_line(text + ".")
	_event(zone, "abandoned", text)
	_mark(layer, home, "Abandoned: %s" % family_name(members), key)
	_chase_slowest(layer, Survival.zombies(layer.level))
	SessionLog.note("survival: %s (%d) fled to %s" % [family_name(members), members.size(), String(dest.label)])
	return e


## The nearest safe place `members` know from `home`, away from the dead at `from`: {"pos", "kind"
## ("place" | "edge"), "to_zone", "label"}. Another household's home, a world group's camp, the
## players' farm, a town's edge; else a crossing out of the zone (the one most away from the dead).
static func safe_place(layer: SurvivorsLayer, home: Vector3, from: Vector3, members: Array, skip: Array = []) -> Dictionary:
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
		cands.append({"pos": SurvivorPerson.pos_of(rec, "home"), "kind": "place", "label": "%s's place" % String(rec.get("first", rec.get("name", "someone"))), "join": "h|" + k})
	if WorldSim.is_set_up():
		for g: Dictionary in WorldSim.groups_in(zone):
			var h: Dictionary = g.get("home", {})
			if not bool(g.get("alive", false)) or String(g.get("kind", "")) in ["raiders", "cultists", "lone"] or h.is_empty() or String(h.get("zone", "")) != zone:
				continue
			var hp: Array = h.get("pos", [0.0, 0.0])
			cands.append({"pos": layer.level.ground_point(Vector3(float(hp[0]), 0.0, float(hp[1]))), "kind": "place", "label": String(g.get("name", "a camp")), "join": "g|" + String(g.get("id", ""))})
	if Settlement.exists() and Settlement.zone() == zone:
		cands.append({"pos": Settlement.pos(), "kind": "place", "label": "the farm", "join": "settlement"})
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
		if String(c.get("join", "")) in skip or d < SAFE_FROM_M or _bearing_toward(home, p, away) > TOWARD_DEAD or _dead_near(dead, p, HOLD_M):
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
	if Settlement.exists() and Settlement.zone() == layer._zone() and _flat(home, Settlement.pos()) <= Settlement.radius() + 10.0:
		return left  # (inside the players' farm: nothing of theirs dropped for the settlers to haul off)
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


static func _mark(layer: SurvivorsLayer, at: Vector3, text: String, key := "") -> void:
	var m := SurvivalMap.server_add_mark(layer._zone(), at, text, "abandoned")
	if key != "":
		m["place"] = key  # (the claim post's: ClaimPost)
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
			if not at.is_finite():
				join_on_arrival(layer, rec, f)  # (they reached a held place: they join it, or ask to)
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


# --- Joining the place they reach (gap 1) ------------------------------------------------------------

## The household id a household key `hkey` shares when others join it (its own "household" when it
## has one).
static func hid_of(hkey: String) -> String:
	return hkey.substr(2) if hkey.begins_with("h:") else "hh_" + hkey.replace(":", "_")


## The people of household `hkey` (or already joined under its id) out there in `zone`, not running.
static func household_members(people: Dictionary, zone: String, hkey: String) -> Array:
	var hid := hid_of(hkey)
	var out: Array = []
	for id: String in WorldModel._sorted(people.keys()):
		var r: Dictionary = people[id]
		if String(r.get("status", "")) != "out_there" or String(r.get("zone", "")) != zone or r.has("flee"):
			continue
		if household_key(r) == hkey or String(r.get("household", "")) == hid:
			out.append(r)
	return out


## `refugee` joins the household `hosts` (key `hkey`): one household now (a shared "household" id;
## the old one kept in "joined" for going home), what they carried to eat and drink shared (into the
## head's kit: the body's when `layer` has one), and a bond with who took them in. Returns whether.
static func join_household(refugee: Dictionary, hosts: Array, hkey: String, layer: SurvivorsLayer = null) -> bool:
	var rid := String(refugee.get("id", ""))
	var others := hosts.filter(func(r: Dictionary) -> bool: return String(r.get("id", "")) != rid)
	if others.is_empty() or _adults(others) == 0:
		return false
	var hid := hid_of(hkey)
	for h: Dictionary in others:
		if String(h.get("household", "")) == "":
			h["household"] = hid
	if not refugee.has("joined"):
		refugee["joined"] = {"kind": "household", "old": String(refugee.get("household", ""))}
	refugee["household"] = hid
	_share_food(layer, refugee, head_of(others))
	for h: Dictionary in others:
		if Children.is_child_rec(h):
			continue
		SurvivorPerson.change_relation(refugee, String(h.id), TOOK_IN_REL)
		SurvivorPerson.change_relation(h, rid, HOST_REL)
	return true


## What `from` carries to eat and drink (GRAB) goes to `to` (bodies' inventories when they're up).
static func _share_food(layer: SurvivorsLayer, from: Dictionary, to: Dictionary) -> int:
	var fb: Soldier = layer.body_of(String(from.get("id", ""))) if layer else null
	var tb: Soldier = layer.body_of(String(to.get("id", ""))) if layer else null
	var n := 0
	for id: String in GRAB:
		for _i in 4:
			var had := false
			if fb:
				had = fb.inventory.remove_one(StringName(id))
			else:
				var kit: Array = from.get("kit", [])
				for e: Variant in kit:
					if e is Dictionary and String((e as Dictionary).get("id", "")) == id:
						var left := int((e as Dictionary).get("count", 1)) - 1
						if left <= 0:
							kit.erase(e)
						else:
							(e as Dictionary)["count"] = left
						had = true
						break
			if not had:
				break
			n += 1
			if tb:
				tb.inventory.take(StringName(id), 1)
			else:
				if not to.get("kit") is Array:
					to["kit"] = []
				(to.kit as Array).append({"id": id, "count": 1})
	if fb:
		from["kit"] = Survival.kit_of(fb.inventory)
	if tb:
		to["kit"] = Survival.kit_of(tb.inventory)
	return n


## Why world group `g` won't take `rec` in ("" it will): gone, hostile (raiders, cultists, the
## enclave, or its relation to them REFUGE_HOSTILE or worse), or starving (REFUGE_FOOD_DAYS).
static func group_refuses(g: Dictionary, rec: Dictionary) -> String:
	if g.is_empty() or not bool(g.get("alive", false)) or String(g.get("kind", "")) == "lone":
		return "gone"
	if String(g.get("kind", "")) in ["raiders", "cultists", "enclave"] or WorldGroup.relation(g, "lone_" + String(rec.get("id", ""))) <= REFUGE_HOSTILE:
		return "hostile"
	if WorldGroup.days_of_food(g) < REFUGE_FOOD_DAYS:
		return "starving"
	return ""


## `rec` becomes one of world group `g` (records only; the sim and the live side): a member (the
## group bigger and, by its members, stronger), what they carried in its supplies. Safe to replay
## on another copy of the group (the far step's).
static func take_in(g: Dictionary, rec: Dictionary, day: float) -> void:
	var pid := String(rec.get("id", ""))
	rec["status"] = WorldGroup.GROUPED
	rec["world_group"] = String(g.get("id", ""))
	rec["joined"] = {"kind": "group", "group": String(g.get("id", ""))}
	rec.erase("flee")
	if not g.get("members") is Array:
		g["members"] = []
	if pid in (g.members as Array):
		return
	(g.members as Array).append(pid)
	if not Children.is_child_rec(rec):
		for k: String in ["food", "water"]:
			WorldGroup.add_supply(g, k, REFUGE_SUPPLY)
		rec["kit"] = (rec.get("kit", []) as Array).filter(func(e: Variant) -> bool: return not (e is Dictionary and String((e as Dictionary).get("id", "")) in GRAB))
	if g.get("memory") is Array:
		WorldGroup.remember(g, day, "refugees", "%s came to us running from the dead; we took them in" % String(rec.get("name", "someone")))


## Host: `rec` reached the place `f` ran to: they join it (`f.join`: "h|<household key>", "g|<group
## id>" or "settlement"). Returns what came of it: "household", "group", "refused", "asks" or "".
static func join_on_arrival(layer: SurvivorsLayer, rec: Dictionary, f: Dictionary) -> String:
	var join := String(f.get("join", ""))
	if join.begins_with("h|"):
		var hkey := join.substr(2)
		var hosts := household_members(SurvivorsLayer.records(), String(rec.get("zone", "")), hkey)
		var rkey := String(rec.get("refugee_from", ""))
		var first := not hosts.any(func(h: Dictionary) -> bool: return rkey != "" and String(h.get("refugee_from", "")) == rkey)
		if not join_household(rec, hosts, hkey, layer):
			return ""
		var fam := family_name(hosts.filter(func(h: Dictionary) -> bool: return String(h.get("refugee_from", "")) == "" or String(h.get("refugee_from", "")) != rkey))
		SurvivorPerson.note(rec, "was taken in by %s" % fam)
		if first:
			Survival._journal_line("%s took in %s, running from the dead." % [fam.left(1).to_upper() + fam.substr(1), String(rec.get("name", "someone"))])
		return "household"
	if join.begins_with("g|"):
		var gid := join.substr(2)
		var g: Dictionary = WorldSim.group(gid) if WorldSim.is_set_up() else {}
		var why := group_refuses(g, rec)
		if why != "":
			var b := layer.body_of(String(rec.get("id", "")))
			if b and not Children.is_child_rec(rec):
				layer.say(b, REFUSED_LINES[absi(hash([rec.get("id", ""), gid])) % REFUSED_LINES.size()])
			SurvivorPerson.note(rec, "was turned away by %s (%s)" % [String(g.get("name", "a camp")), why])
			_flee_on(layer, rec, f, join)
			return "refused"
		server_join_group(layer, rec, gid)
		return "group"
	if join == "settlement":
		server_ask_stay(layer, rec, "settlement")
		return "asks"
	return ""


## Host: turned away at the place `f` ran to (`join`), `rec` goes on to the next safe place (at
## most SKIP_MAX places tried; then they stay where they are, refugees).
static func _flee_on(layer: SurvivorsLayer, rec: Dictionary, f: Dictionary, join: String) -> void:
	var skip: Array = (f.get("skip", []) as Array).duplicate()
	skip.append(join)
	var b: Soldier = layer.body_of(String(rec.get("id", ""))) if layer else null
	if b == null or skip.size() > SKIP_MAX:
		return
	var here := b.global_position
	var from := _v3(f.get("from", []))
	var dest := safe_place(layer, here, from if from != Vector3.ZERO else here + Vector3.RIGHT, [rec], skip)
	rec["flee"] = {"to": _arr(dest.pos as Vector3), "kind": String(dest.kind), "to_zone": String(dest.get("to_zone", "")), "label": String(dest.label),
		"key": String(f.get("key", "")), "since": Soldier._now(), "cover_until": 0.0, "route": [_arr(dest.pos as Vector3)], "leg": 0,
		"from": f.get("from", _arr(here)), "join": String(dest.get("join", "")), "skip": skip}
	layer._set_known(b, rec)


## Host: `rec` joins world group `gid` at its camp in the hosted zone: the body goes (the group's
## people are WorldLive's), the record a member (take_in, on the world's copy and the far step's).
static func server_join_group(layer: SurvivorsLayer, rec: Dictionary, gid: String) -> void:
	var b: Soldier = layer.body_of(String(rec.get("id", ""))) if layer else null
	if b:
		layer._store(rec, b)
		layer._forget(b)
		b.queue_free()
		layer._bodies.erase(String(rec.id))
	var day := WorldSim.world_now()
	var sim := WorldSim.get_sim()
	if sim:
		sim.mutate(func(w: Dictionary) -> void:
			var g: Dictionary = (w.get("groups", {}) as Dictionary).get(gid, {})
			if not g.is_empty():
				take_in(g, rec, day))
	var name := String(WorldSim.group(gid).get("name", "a camp"))
	SurvivorPerson.note(rec, "joined %s" % name)
	Survival._journal_line("%s took in %s, running from the dead." % [name.left(1).to_upper() + name.substr(1), String(rec.get("name", "someone"))])


## Host: `rec` at `where` ("settlement", or a claimed place's key) asks to stay: a line, the flag
## the talk reads ("Let them stay"), and at the farm the council's question (a take-in vote: one
## for the household, the rest of them added as they come).
static func server_ask_stay(layer: SurvivorsLayer, rec: Dictionary, where: String) -> void:
	rec["asks_stay"] = where
	SurvivorPerson.note(rec, "asked to stay")
	var b: Soldier = layer.body_of(String(rec.get("id", ""))) if layer else null
	if b and not Children.is_child_rec(rec):
		layer.say(b, STAY_LINES[absi(hash(String(rec.get("id", "")))) % STAY_LINES.size()])
	if b:
		layer._set_known(b, rec)
	if where != "settlement" or not Settlement.exists():
		return
	var key := String(rec.get("refugee_from", ""))
	for v: Dictionary in Council.open_votes():
		var q: Dictionary = v.question
		if String(q.get("kind", "")) == "take_in" and q.has("refugees") and String(q.get("refugees_from", "-")) == key:
			if not String(rec.id) in (q.refugees as Array):
				(q.refugees as Array).append(String(rec.id))
			rec["stay_vote"] = int(v.id)
			return
	var id := Council.server_put({"kind": "take_in", "people": [], "refugees": [String(rec.id)], "refugees_from": key,
		"text": "Take in %s, running from the dead?" % String(rec.get("name", "someone"))}, ["Take them in", "Turn them away"],
		func(result: String) -> void: _stay_voted(key, result == "Take them in"))
	rec["stay_vote"] = id


static func _stay_voted(key: String, yes: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var lvl: CompoundLevel = CompoundLevel.current(tree.root) if tree else null
	var layer: SurvivorsLayer = SurvivorsLayer.find(lvl) if lvl else null
	for rec: Dictionary in SurvivorsLayer.records().values().duplicate():
		if String(rec.get("asks_stay", "")) == "settlement" and String(rec.get("refugee_from", "")) == key and String(rec.get("status", "")) == "out_there":
			_stay_answer(layer, rec, yes, null)


## Host: a player's answer (`yes`) to `rec` asking to stay (TalkMenu "Let them stay" / "Turn them
## away"): everyone of theirs asking with them gets it; an open vote on them is closed. Returns the line.
static func server_let_stay(layer: SurvivorsLayer, actor: Soldier, rec: Dictionary, yes: bool) -> String:
	var where := String(rec.get("asks_stay", ""))
	if where == "" or String(rec.get("status", "")) != "out_there":
		return ""
	var b: Soldier = layer.body_of(String(rec.get("id", ""))) if layer else null
	var vid := int(rec.get("stay_vote", -1))
	var v: Dictionary = Council.get_vote(vid) if vid >= 0 else {}
	if not v.is_empty() and String(v.get("state", "")) == "open":
		v["state"] = "done"
		v["result"] = String((v.options as Array)[0 if yes else 1])
		v["done_h"] = Moods.now_h()
		Council._callbacks.erase(vid)
	var key := String(rec.get("refugee_from", ""))
	var hkey := household_key(rec)
	var line := STAY_YES if yes else STAY_NO
	if b:
		layer.say(b, line)
	for r: Dictionary in SurvivorsLayer.records().values().duplicate():
		if String(r.get("asks_stay", "")) == where and String(r.get("status", "")) == "out_there" and (r == rec or (key != "" and String(r.get("refugee_from", "")) == key) or household_key(r) == hkey):
			_stay_answer(layer, r, yes, actor)
	return line


static func _stay_answer(layer: SurvivorsLayer, rec: Dictionary, yes: bool, by: Soldier) -> void:
	var where := String(rec.get("asks_stay", ""))
	rec.erase("asks_stay")
	rec.erase("stay_vote")
	if not yes:
		SurvivorPerson.note(rec, "was turned away")
		if where == "settlement":
			_flee_on(layer, rec, {"from": _arr(Settlement.pos()), "key": String(rec.get("refugee_from", ""))}, "settlement")
		else:
			_turned_from_claimed(layer, rec)
			var b: Soldier = layer.body_of(String(rec.get("id", ""))) if layer else null
			if b:
				layer._set_known(b, rec)
		return
	if by:
		SurvivorPerson.change_opinion(rec, Survival.profile_of(by), TalkMenu.JOIN_OPINION)
	if where == "settlement":
		rec.erase("refugee_from")
		Moods.remove(rec, "lost_home")
		if layer:
			layer.server_settle(rec, by)
		else:
			Settlement.server_make_settler(rec, by)
		return
	_stay_at_claimed(layer, rec, where)


## Host: `rec` stays on at the place `key` the players claimed (call 143, gap 2): it's their home
## now, the players' place.
static func _stay_at_claimed(layer: SurvivorsLayer, rec: Dictionary, key: String) -> void:
	rec.erase("refugee_from")
	rec.erase("asks_from")
	rec["claimed_place"] = key
	var e := entry(key)
	if not e.is_empty():
		var t: Array = e.get("tenants", [])
		if not String(rec.get("id", "")) in t:
			t.append(String(rec.get("id", "")))
		e["tenants"] = t
		save(e)
	SurvivorPerson.note(rec, "stayed on at %s, a place the players hold" % place_title(e))
	var b: Soldier = layer.body_of(String(rec.get("id", ""))) if layer else null
	if b:
		layer._set_known(b, rec)


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
		_mark(layer, home, "Abandoned: %s" % String(g.get("name", "")), "g:%s:%s" % [gid, String(h.get("place", ""))])


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
	var host_key := ""
	var host_g: Dictionary = {}
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
			host_key = household_key(o)
	if not to.is_finite():
		to_zone = WorldFights._quietest_link(m, z)
		var places: Array = m.zone(to_zone).get("places", [])
		var free: Array = []
		var camp: Dictionary = {}
		for p: Dictionary in places:
			var holder := String(p.get("holder", ""))
			if holder == "":
				free.append(p)
			elif host_g.is_empty() and group_refuses(m.group(holder), head) == "":
				host_g = m.group(holder)  # (a camp that takes them in; a starving or hostile one turns them away)
				camp = p
		var pool: Array = free if not free.is_empty() else places
		var pl: Dictionary = camp if not camp.is_empty() else ((pool[rng.randi_range(0, pool.size() - 1)] as Dictionary) if not pool.is_empty() else {})
		to = m._place_pos(pl, rng, 40.0) if not pl.is_empty() else Vector2.ZERO
		label = String(host_g.get("name", "")) if not host_g.is_empty() else String(m.zone(to_zone).get("name", to_zone))
	var hosts: Array = household_members(m.people, z, host_key) if host_key != "" and to_zone == z else []
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
		if not host_g.is_empty():
			take_in(host_g, rec, m.now)  # (the camp they reached takes them in)
		elif not hosts.is_empty() and join_household(rec, hosts, host_key):
			m.note(rec, "was taken in by %s" % family_name(hosts))
	var e := {"key": key, "zone": z, "pos": [home.x, home.y, home.z], "ids": ids, "names": names, "text": text, "word": word, "day": m.day(),
		"state": "abandoned", "refugees": ids.filter(func(id: String) -> bool: return id != caught), "where": label, "signs": false, "door_open": true,
		"clear_since": NOT_CLEAR, "by": "the dead", "y_unset": hp.size() < 3 or is_zero_approx(float(hp[1]))}
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
	var stock := {}
	for k: String in WorldGroup.SUPPLY_KEYS:
		var amt := WorldGroup.supply(g, k) * GROUP_LEAVE
		if amt > 0.0:
			stock[k] = snappedf(amt, 0.01)  # (left behind: the players' if they claim it)
		WorldGroup.add_supply(g, k, -amt)
	if not pl.is_empty():
		pl["abandoned"] = {"day": m.day(), "group": gid}
	m.clear_home(g)
	var to := WorldFights._quietest_link(m, z)
	g.goal = {"kind": "relocate", "zone": to, "place": "", "target": "", "since": m.tick(), "phase": "go", "work": 0, "from": z}
	g.journey = {}
	(g.mood as Dictionary).fear = minf(1.0, float((g.mood as Dictionary).get("fear", 0.0)) + 0.2)
	var e := {"key": key, "zone": z, "pos": [float(hp[0]), 0.0, float(hp[1])], "ids": (g.members as Array).duplicate(), "names": [], "text": text, "word": word,
		"day": m.day(), "state": "abandoned", "refugees": [], "where": String(m.zone(to).get("name", to)), "signs": false, "door_open": true,
		"clear_since": NOT_CLEAR, "by": "the dead", "group": gid, "y_unset": true, "stock": stock}
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
		_mark(layer, at, "Abandoned", key)
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
			var sb := layer.body_of(String(rec.id))
			if sb:
				sb.remove_meta(&"sheltered")
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
	var room := settlement_shelter(layer)
	var builder := Builder.find(layer)
	var shelter: Vector3 = room.pos if not room.is_empty() else shelter_point(layer)
	var hidden := false
	for rec: Dictionary in Settlement.settlers():
		var b := layer.body_of(String(rec.id))
		if b:
			b.remove_meta(&"sheltered")
		var kit := Survival.kit_of(b.inventory) if b else (rec.get("kit", []) as Array)
		if not Children.is_child_rec(rec) and arms_of(kit) != "":
			continue  # (the armed stand)
		var spot := shelter
		var how := "shelter_room" if not room.is_empty() else "shelter"
		if how == "shelter_room" and protector == null and b and in_shelter(builder, room, b):
			b.set_meta(&"sheltered", true)  # (behind the shut safe-room door: the dead pass them by)
			hidden = true
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
	if hidden and builder:  # (the dead nearby come to the door and batter at it: Sieges' push)
		var door_at := builder.piece_pos(int(room.door))
		for z: Soldier in near:
			var ai := ZombieAI.of(z)
			if ai and ai.mode in [ZombieAI.Mode.IDLE, ZombieAI.Mode.SEARCH]:
				ai.mode = ZombieAI.Mode.INVESTIGATE
				ai._set_goal(door_at)


## The settlement's strength against the dead: its settlers (by kit), a guard on watch, its
## defence builds (DEFENCE_PER a point).
static func settlement_strength(layer: SurvivorsLayer) -> float:
	var s := household_strength(Settlement.settlers(), layer)
	var st := Settlement.find(layer)
	if st and not st.on_watch().is_empty():
		s += GUARD_BONUS
	return s + float(Settlement.data().get("defence_builds", 0.0)) * DEFENCE_PER


## The settlement's shelter after a shelter room (settlement_shelter): a cellar hatch within it,
## else the farmhouse.
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
		dest = safe_place(layer, Settlement.pos(), from, list, ["settlement"])
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
		"clear_since": NOT_CLEAR, "by": "the dead", "settlement": true})
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
		if not String(e.get("state", "")) in ["abandoned", "claimed"] or (e.get("refugees", []) as Array).is_empty():
			continue
		if not is_clear(layer, e):
			if float(e.get("clear_since", NOT_CLEAR)) > NOT_CLEAR * 0.5:
				e["clear_since"] = NOT_CLEAR
				save(e)
			continue
		if float(e.get("clear_since", NOT_CLEAR)) <= NOT_CLEAR * 0.5:
			e["clear_since"] = now
			save(e)
			continue
		if now - float(e.clear_since) >= RETURN_DAYS:
			n += server_return(layer, key)
	return n


## Host: the refugees of place `key` go home (`by`: the player who told them it's clear). Returns how many.
static func server_return(layer: SurvivorsLayer, key: String, by: Soldier = null) -> int:
	var e := entry(key)
	if e.is_empty() or not String(e.get("state", "")) in ["abandoned", "claimed"]:
		return 0
	var claimed := String(e.state) == "claimed"  # (the players' now: they come back and ask to stay)
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
		if claimed:
			rec["asks_from"] = _arr(SurvivorPerson.pos_of(rec, "home"))
			rec["asks_stay"] = key
			SurvivorPerson.note(rec, "came home and found it held by others")
		else:
			rec.erase("refugee_from")
			rec.erase("asks_stay")  # (they'd asked to stay where they ran: home instead)
			rec.erase("stay_vote")
		var j: Dictionary = rec.get("joined", {})
		if String(j.get("kind", "")) == "household":  # (they leave the household that took them in)
			if String(j.get("old", "")) != "":
				rec["household"] = String(j.old)
			else:
				rec.erase("household")
			rec.erase("joined")
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
	if claimed:
		e["refugees"] = []
		e["asked_day"] = Survival.day()
		save(e)
		if n > 0:
			Survival._journal_line("%s came back to %s and found it ours. They ask to stay." % [String(e.get("text", "")).get_slice(" left ", 0) if String(e.get("text", "")).contains(" left ") else "Its people", place_title(e)])
		return n
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


# --- Claiming a place left to the dead (gap 2) ---------------------------------------------------------

## Why the players can't claim the place `key` now ("" they can): not a place left (abandoned, or
## an empty homestead), already theirs, the dead within CLAIM_DEAD_M, or someone living there
## (a household's home within CLAIM_INSIDE_M, a group holding it again).
static func claim_problem(layer: SurvivorsLayer, key: String) -> String:
	var e := entry(key)
	if e.is_empty():
		return "Nothing to claim here"
	var state := String(e.get("state", ""))
	if state == "claimed":
		return "It's already ours"
	if not state in ["abandoned", "empty"]:
		return "Its people came back"
	var at := _v3(e.get("pos", []))
	var zone := String(e.get("zone", ""))
	if layer and layer.level and zone == layer._zone():
		if _dead_near(Survival.zombies(layer.level), at, CLAIM_DEAD_M):
			return "The dead are too close"
		var crowd := ZoneDead.of(layer.level)
		if crowd:
			for d: Dictionary in crowd.dead:
				if bool(d.get("alive", false)) and (d.pos as Vector2).distance_to(Vector2(at.x, at.z)) <= CLAIM_DEAD_M:
					return "The dead are too close"
	for r: Dictionary in SurvivorsLayer.records().values():
		if String(r.get("status", "")) == "out_there" and String(r.get("zone", "")) == zone and not r.has("flee") \
				and _flat(SurvivorPerson.pos_of(r, "home"), at) <= CLAIM_INSIDE_M:
			return "Someone still lives here"
	var pid := _claim_place_id(e)
	if pid != "" and WorldSim.is_set_up():
		var holder := WorldSim.holder_of(zone, pid)
		if holder != "" and holder != "player" and holder != String(e.get("group", "-")):
			return "Someone holds it now"
	return ""


## The world place under entry `e` (a group's camp: its place; else the nearest within CLAIM_PLACE_M).
static func _claim_place_id(e: Dictionary) -> String:
	var key := String(e.get("key", ""))
	if key.begins_with("g:") and key.get_slice_count(":") >= 3:
		return key.get_slice(":", 2)
	if not WorldSim.is_set_up():
		return ""
	var at := _v3(e.get("pos", []))
	var best := ""
	var best_d := CLAIM_PLACE_M
	var zd: Dictionary = (WorldSim.section().get("zones", {}) as Dictionary).get(String(e.get("zone", "")), {})
	for pl: Dictionary in zd.get("places", []):
		var d := WorldModel._place_v(pl).distance_to(Vector2(at.x, at.z))
		if d < best_d:
			best_d = d
			best = String(pl.get("id", ""))
	return best


## Host: `actor` claims the place `key` (in reach, claim_problem clear): it's the players' (a
## second home: "owner", the world place held by "player" so no group settles it), what's left
## there theirs ("stores": a camp's supplies left behind as things; take them with server_take_stock),
## the map's mark "Ours", a journal line. Returns why not ("" done).
static func server_claim(layer: SurvivorsLayer, actor: Soldier, key: String) -> String:
	var why := claim_problem(layer, key)
	var e := entry(key)
	if why == "" and actor and _flat(actor.global_position, _v3(e.get("pos", []))) > CLAIM_REACH_M:
		why = "Too far"
	if why != "":
		return why
	var title := place_title(e)
	e["state"] = "claimed"
	e["owner"] = Survival.profile_of(actor) if actor else "host"
	e["claimed_day"] = Survival.day()
	e["stores"] = stock_items(e.get("stock", {}))
	save(e)
	_world_hold(e, "player")
	_retag_mark(layer, e, "claimed", "Ours: %s" % title)
	Survival._journal_line("We claimed %s. It's ours now." % title)
	_event(String(e.get("zone", "")), "claimed", "The newcomers claimed %s" % title)
	return ""


## "the Halvorsens' farm" for entry `e` (a place's own words), "an empty homestead".
static func place_title(e: Dictionary) -> String:
	if String(e.get("title", "")) != "":
		return String(e.title)
	var text := String(e.get("text", ""))
	var word := String(e.get("word", "place"))
	var who := text.get_slice(" left ", 0) if text.contains(" left ") else ""
	if who == "":
		return "the " + word
	if who.begins_with("The "):
		who = "the " + who.substr(4)
	return "%s%s %s" % [who, "'" if who.ends_with("s") else "'s", word]


## A camp's supplies left behind (`stock`: {"food": days, ...}) as things: STOCK_ITEMS each, at most
## STOCK_MAX of a kind. {item id: count}.
static func stock_items(stock: Variant) -> Dictionary:
	var out := {}
	if not stock is Dictionary:
		return out
	for k: String in (stock as Dictionary):
		var id := String(STOCK_ITEMS.get(k, ""))
		var n := clampi(roundi(float((stock as Dictionary)[k])), 0, STOCK_MAX)
		if id != "" and n > 0 and ItemDB.get_item(StringName(id)) != null:
			out[id] = int(out.get(id, 0)) + n
	return out


## Host: `actor` takes what's left at the claimed place `key` (what won't fit is put down by him).
static func server_take_stock(layer: SurvivorsLayer, actor: Soldier, key: String) -> String:
	var e := entry(key)
	if String(e.get("state", "")) != "claimed":
		return "It isn't ours"
	if actor == null or _flat(actor.global_position, _v3(e.get("pos", []))) > CLAIM_REACH_M:
		return "Too far"
	var stores: Dictionary = e.get("stores", {})
	if stores.is_empty():
		return "Nothing left here"
	for id: String in stores.keys():
		var n := int(stores[id])
		var got := actor.inventory.take(StringName(id), n)
		if got < n and layer and layer.level:
			layer.level.server_spawn_dropped(StringName(id), n - got, actor.global_position + Vector3.UP * 0.4)
	e["stores"] = {}
	save(e)
	return ""


## Host: the claimed place `key` is the safehouse now (where the survivors sleep and come back):
## the safehouse mark moves there. Returns why not.
static func server_make_safehouse(layer: SurvivorsLayer, key: String) -> String:
	var e := entry(key)
	if String(e.get("state", "")) != "claimed":
		return "It isn't ours"
	var safe := SurvivalMap.safehouse()
	if safe.is_empty():
		safe = SurvivalMap.server_add_mark(String(e.zone), _v3(e.get("pos", [])), "Safehouse", "safehouse")
	safe["zone"] = String(e.zone)
	safe["pos"] = (e.get("pos", [0.0, 0.0, 0.0]) as Array).duplicate()
	safe["text"] = "Safehouse (%s)" % place_title(e)
	safe.erase("auto")
	_map_changed(layer)
	Survival._journal_line("We'll sleep at %s now: it's our safehouse." % place_title(e))
	return ""


## Host: the claimed place `key` as the settlement: founded there when there's none, else the
## council's question (a "move": never silently). Returns why not.
static func server_make_settlement(key: String) -> String:
	var e := entry(key)
	if String(e.get("state", "")) != "claimed":
		return "It isn't ours"
	var at := _v3(e.get("pos", []))
	if not Settlement.exists():
		Settlement.server_found(String(e.zone), at)
		Survival._journal_line("We made %s our settlement." % place_title(e))
		return ""
	if Settlement.zone() == String(e.zone) and _flat(Settlement.pos(), at) <= Settlement.radius():
		return "It's the settlement already"
	var id := Council.server_put({"kind": "move", "zone": String(e.zone), "pos": _arr(at), "text": "Move the settlement to %s?" % place_title(e)}, ["Move", "Stay"])
	return "" if id >= 0 else "No council to ask"


## Host: the world place under entry `e` held by `holder` ("player": no group settles or forages it).
static func _world_hold(e: Dictionary, holder: String) -> void:
	var pid := _claim_place_id(e)
	var sim := WorldSim.get_sim()
	if pid == "" or sim == null or not WorldSim.is_set_up():
		return
	var z := String(e.get("zone", ""))
	sim.mutate(func(w: Dictionary) -> void:
		var zd: Dictionary = (w.get("zones", {}) as Dictionary).get(z, {})
		for pl: Dictionary in zd.get("places", []):
			if String(pl.get("id", "")) == pid:
				pl["holder"] = holder)


## Host: the map mark for entry `e` (by its "place" key, else an "abandoned" one within 4 m) made
## `kind` with `text` (added when there's none).
static func _retag_mark(layer: SurvivorsLayer, e: Dictionary, kind: String, text: String) -> void:
	var key := String(e.get("key", ""))
	var at := _v3(e.get("pos", []))
	var found := {}
	for m: Variant in SurvivalMap.marks(String(e.get("zone", ""))):
		if not m is Dictionary:
			continue
		var md: Dictionary = m
		if String(md.get("place", "")) == key or (String(md.get("kind", "")) == "abandoned" and String(md.get("place", "")) == "" and SurvivalMap.mark_pos(md).distance_to(Vector2(at.x, at.z)) <= 4.0):
			found = md
			break
	if found.is_empty():
		found = SurvivalMap.server_add_mark(String(e.get("zone", "")), at, text, kind)
	found["kind"] = kind
	found["text"] = text
	found["place"] = key
	_map_changed(layer)


static func _map_changed(layer: SurvivorsLayer) -> void:
	var map: SurvivalMap = SurvivalMap.of(layer.level) if layer and layer.level else null
	if map:
		map.server_changed()


## Host (Settlement.server_action "claim", from a ClaimPost): `actor` does `what` at place `key`
## ("claim", "take", "safehouse", "settlement"); he's told how it went. Returns why not.
static func server_claim_action(actor: Soldier, key: String, what: String) -> String:
	var lvl: CompoundLevel = CompoundLevel.current(actor) if actor and actor.is_inside_tree() else null
	var layer: SurvivorsLayer = SurvivorsLayer.find(lvl) if lvl else null
	var why := "Can't do that"
	var done := ""
	match what:
		"claim":
			why = server_claim(layer, actor, key)
			done = "It's ours now"
		"take":
			why = server_take_stock(layer, actor, key)
			done = "You take what's left"
		"safehouse":
			why = server_make_safehouse(layer, key)
			done = "Our safehouse now"
		"settlement":
			why = server_make_settlement(key)
			done = "Put to the council" if Council.open_votes().any(func(v: Dictionary) -> bool: return String((v.question as Dictionary).get("kind", "")) == "move") else "Our settlement now"
	if actor:
		Survival._tell(actor, why if why != "" else done)
	return why


## Host, from server_tick (every EMPTY_CHECK_S): a homestead nobody holds (a world farm with no
## holder, nobody living there, not the players' farm) a survivor comes near is found: an "empty"
## place to claim, with its mark. Returns how many were found.
static func server_find_empty(layer: SurvivorsLayer) -> int:
	if not WorldSim.is_set_up() or layer == null or layer.level == null:
		return 0
	var zone := layer._zone()
	var zd: Dictionary = (WorldSim.section().get("zones", {}) as Dictionary).get(zone, {})
	var players := MapNodes.players(layer.level)
	var n := 0
	for pl: Dictionary in zd.get("places", []):
		if not ZoneModules.base(String(pl.get("type", ""))) in EMPTY_TYPES or String(pl.get("holder", "")) != "":
			continue
		var key := "e:%s:%s" % [zone, String(pl.get("id", ""))]
		if places().has(key):
			continue
		var p2 := WorldModel._place_v(pl)
		var at := Vector3(p2.x, 0.0, p2.y)
		if Settlement.exists() and Settlement.zone() == zone and _flat(at, Settlement.pos()) <= Settlement.radius() + CLAIM_INSIDE_M:
			continue
		if not players.any(func(p: Soldier) -> bool: return _flat(p.global_position, at) <= EMPTY_SEEN_M):
			continue
		if SurvivorsLayer.records().values().any(func(r: Dictionary) -> bool: return String(r.get("status", "")) == "out_there" and String(r.get("zone", "")) == zone \
				and _flat(SurvivorPerson.pos_of(r, "home"), at) <= CLAIM_INSIDE_M * 2.0):
			continue
		at = layer.level.ground_point(at)
		var e := {"key": key, "zone": zone, "pos": _arr(at), "ids": [], "names": [], "text": "", "title": "an empty homestead", "word": "farm",
			"day": Survival.day(), "state": "empty", "refugees": [], "where": "", "signs": true, "door_open": false, "clear_since": NOT_CLEAR, "by": ""}
		save(e)
		var mark := SurvivalMap.server_add_mark(zone, at, "Empty homestead", "abandoned")
		mark["place"] = key
		_map_changed(layer)
		n += 1
	return n


## Host: `rec` turned away from the place they came back to (it's the players' now): home again to
## where they lived as refugees.
static func _turned_from_claimed(layer: SurvivorsLayer, rec: Dictionary) -> void:
	rec.erase("refugee_from")
	if not rec.has("asks_from"):
		return
	var home := _v3(rec.asks_from)
	rec.erase("asks_from")
	SurvivorPerson.set_pos(rec, home, "home")
	var b: Soldier = layer.body_of(String(rec.get("id", ""))) if layer else null
	if b and b.vitals.is_up():
		rec["flee"] = {"to": _arr(home), "kind": "home", "to_zone": "", "label": "home", "key": "", "since": Soldier._now(), "cover_until": 0.0,
			"route": [_arr(home)], "leg": 0, "from": _arr(b.global_position)}
		layer._set_known(b, rec)


# --- The shelter room (gap 3) -----------------------------------------------------------------------------

## The room a "shelter" marker piece `id` stands in, when it's a shelter: closed round by walls
## (built blocks, solid pieces, shut doors) a block up from its floor, no more than ROOM_SPAN cells
## out, with a "safe_room_door" in its walls: {"id", "door" (the door piece), "cells" ({"x,z": true}),
## "pos" (the marker), "y"}; {} when it isn't one (open somewhere, or no safe-room door).
static func shelter_room(b: Builder, id: int) -> Dictionary:
	var rec: Dictionary = b.pieces.get(id, {})
	if rec.is_empty() or String(rec.get("k", "")) != SHELTER_MARK or not b.is_piece_built(id):
		return {}
	var base := Vector3i(int(rec.c[0]), int(rec.c[1]), int(rec.c[2]))
	var start := Vector3i(base.x, base.y + 1, base.z)
	if _room_wall(b, start):
		return {}
	var cells := {"%d,%d" % [start.x, start.z]: true}
	var queue: Array[Vector3i] = [start]
	var door := -1
	var sides: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	while not queue.is_empty():
		var c: Vector3i = queue.pop_back()
		for side: Vector3i in sides:
			var n := c + side
			var k := "%d,%d" % [n.x, n.z]
			if cells.has(k):
				continue
			var pid := b.piece_at(n)
			if pid > 0 and String((b.pieces[pid] as Dictionary).get("k", "")) == SHELTER_DOOR and b.is_piece_built(pid):
				door = pid
				continue
			if _room_wall(b, n):
				continue
			if absi(n.x - base.x) > ROOM_SPAN or absi(n.z - base.z) > ROOM_SPAN or cells.size() >= ROOM_MAX:
				return {}  # (open to the outside)
			cells[k] = true
			queue.append(n)
	if door < 0:
		return {}
	return {"id": id, "door": door, "cells": cells, "pos": b.piece_pos(id), "y": start.y}


## Whether cell `c` closes a room: a built block, or a built solid piece (a door only shut).
static func _room_wall(b: Builder, c: Vector3i) -> bool:
	if b.is_built(c):
		return true
	var pid := b.piece_at(c)
	if pid <= 0 or not b.is_piece_built(pid):
		return false
	var r: Dictionary = b.pieces[pid]
	var def: Dictionary = BuildPieces.PIECES.get(String(r.get("k", "")), {})
	return bool(def.get("solid", false)) and not (bool(def.get("door", false)) and bool(r.get("open", false)))


## The settlement's shelter room (the first sound one within its radius), or {}.
static func settlement_shelter(layer: SurvivorsLayer) -> Dictionary:
	var b: Builder = Builder.find(layer) if layer else null
	if b == null or not Settlement.exists():
		return {}
	var c := Settlement.pos()
	for id: int in b.pieces:
		if String((b.pieces[id] as Dictionary).get("k", "")) != SHELTER_MARK or _flat(b.piece_pos(id), c) > Settlement.radius():
			continue
		var room := shelter_room(b, id)
		if not room.is_empty():
			return room
	return {}


## Whether `s` is inside shelter `room` with its safe-room door there and shut.
static func in_shelter(b: Builder, room: Dictionary, s: Node3D) -> bool:
	if b == null or room.is_empty() or s == null or not b.pieces.has(int(room.door)) or bool((b.pieces[int(room.door)] as Dictionary).get("open", false)):
		return false
	var c := BuildPieces.cell_at(s.global_position + Vector3.UP * 0.3)
	return (room.cells as Dictionary).has("%d,%d" % [c.x, c.z])


## Whether the dead pass `s` by (ZombieAI): sheltered behind a shut safe-room door
## (settlement_tick sets it; the door broken or open, it's gone).
static func sheltered(s: Node) -> bool:
	return s != null and s.has_meta(&"sheltered")
