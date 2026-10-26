class_name WorldGoals
extends RefCounted
## The groups' judgement and goals (docs/survival_world.md 4.3, call 21): every far tick a
## group's leader scores the goals open to it and takes the best, with hysteresis:
##
##   score = expected_gain x need_weight - expected_losses x (1 + caution)
##           - noise_cost x fear_of_dead - relation_cost x (1 - cruelty) + personality_bias
##
## Expected losses come from what the group KNOWS (its scouts' reports in `knows`, what it has
## seen), not the truth: an unscouted target is guessed from its size with an uncertainty premium.
## Noise cost grows sharply as the zone nears the horde threshold, so groups keep loud goals away
## from a zone about to boil over. Goals: forage, work (hunt / fish / farm), trade, settle, raid
## (a demand first for settlements and the players' farm), defend (fortify), flee, scout,
## recruit, search, capture and feed (cultists), hunt_player (a grudge), rest. act() carries the
## goal one tick on: a journey, then the work at the place. Static; all state on the group.

## Proposed: the bonus a goal in progress keeps, and the noise each goal makes (0-1).
const HYSTERESIS := 0.15
const NOISE := {"forage": 0.1, "work": 0.05, "trade": 0.02, "settle": 0.15, "raid": 0.6, "defend": 0.05, "flee": 0.05,
	"scout": 0.0, "recruit": 0.0, "search": 0.05, "capture": 0.1, "feed": 0.0, "hunt_player": 0.5, "rest": 0.0, "patrol": 0.1}
## Proposed: how long each goal's work takes at its place (ticks).
const WORK_TICKS := {"forage": 4, "work": 16, "defend": 8, "rest": 8, "patrol": 8}
## Proposed: an unscouted target's strength is guessed at UNKNOWN_X its size's worth.
const UNKNOWN_X := 1.4
## Proposed: how long the players get to answer a demand (world days: 6 hours).
const DEMAND_DAYS := 0.25
## Proposed: the share of a target's supplies a demand asks for; what a far group that pays gives.
const DEMAND_SHARE := 0.4
## Proposed: a scout report is fresh this many world days.
const FRESH_DAYS := 2.0


# --- Deciding ------------------------------------------------------------------------------------

## `g` scores its options and takes the best (a goal in progress keeps HYSTERESIS).
static func decide(m: WorldModel, g: Dictionary) -> void:
	var cur: Dictionary = g.get("goal", {})
	if not cur.is_empty() and (String(cur.get("phase", "")) in ["demand", "wait", "attack"] or (String(cur.kind) == "raid" and String(cur.get("zone", "")) == String(g.zone))):
		return  # (a raid under way, or at its target, runs to its end)
	var best := {}
	var best_s := -INF
	var rng := m.rng_for(String(g.id), "decide")
	for o: Dictionary in options(m, g):
		var s := score(g, o) + rng.randf_range(-0.02, 0.02)
		if _same(cur, o):
			s += HYSTERESIS
		o["score"] = snappedf(s, 0.001)
		if s > best_s:
			best_s = s
			best = o
	if best.is_empty():
		return
	if _same(cur, best):
		cur.score = best.score
		return
	best["since"] = m.tick()
	best["phase"] = "go"
	best["work"] = 0
	g.goal = best
	g.journey = {}


static func _same(a: Dictionary, b: Dictionary) -> bool:
	return not a.is_empty() and String(a.get("kind", "")) == String(b.get("kind", "")) and String(a.get("zone", "")) == String(b.get("zone", "")) \
		and String(a.get("place", "")) == String(b.get("place", "")) and String(a.get("target", "")) == String(b.get("target", ""))


## The judgement (4.3) of option `o` for `g`. Every term is on the option: gain, need, loss,
## noise (already scaled by the zone's nearness to a horde), rel, bias.
static func score(g: Dictionary, o: Dictionary) -> float:
	var p: Dictionary = g.get("personality", {})
	var fear := 0.5 + float((g.get("mood", {}) as Dictionary).get("fear", 0.2))
	return float(o.get("gain", 0.0)) * float(o.get("need", 1.0)) \
		- float(o.get("loss", 0.0)) * (1.0 + float(p.get("caution", 0.5))) \
		- float(o.get("noise", 0.0)) * fear \
		- float(o.get("rel", 0.0)) * (1.0 - float(p.get("cruelty", 0.2))) \
		+ float(o.get("bias", 0.0))


## The noise cost of a goal of `kind` in `zone_id`: its noise x how near the zone is to a horde
## (rising steeply past half the threshold).
const NOISE_NEAR_X := 5.0
static func noise_cost(m: WorldModel, kind: String, zone_id: String) -> float:
	var near := clampf(m.pressure_of(zone_id) / WorldModel.HORDE_AT, 0.0, 1.2)
	return float(NOISE.get(kind, 0.1)) * (0.2 + NOISE_NEAR_X * near * near)


## How dangerous `zone_id` looks to `g`: its pressure, a known horde, known hostile groups there.
static func danger(m: WorldModel, g: Dictionary, zone_id: String) -> float:
	var zd := m.zone(zone_id)
	var d := m.pressure_of(zone_id) / 100.0 * 0.6 + (0.8 if not (zd.get("horde", {}) as Dictionary).is_empty() else 0.0)
	var mine := maxf(0.5, WorldGroup.strength(g, m.people))
	for o: Dictionary in m.groups_in_zone(zone_id):
		var oid := String(o.id)
		if oid == String(g.id) or not bool(o.alive) or String(o.zone) != zone_id or String(o.kind) == "lone":
			continue
		if WorldGroup.relation(g, oid) <= -30.0 or (String(o.kind) in ["raiders", "cultists"] and String(g.kind) != String(o.kind)):
			d += known_strength(m, g, oid) / mine * 0.3
	return d


## What `g` believes `target`'s strength is (a group id or "player"): a fresh scout report's, else
## a guess from its size with UNKNOWN_X (the players: their guessed numbers).
static func known_strength(m: WorldModel, g: Dictionary, target: String) -> float:
	var k: Dictionary = (g.get("knows", {}) as Dictionary).get(target, {})
	if not k.is_empty() and m.now - float(k.get("t", -100.0)) <= FRESH_DAYS:
		return float(k.get("strength", 1.0))
	if target == "player":
		return float(m.player.get("strength", 3.0)) * UNKNOWN_X
	var o := m.group(target)
	var home: Dictionary = o.get("home", {})
	var defence := 0.5 if not home.is_empty() else 0.0
	return float(WorldGroup.size(o)) * 0.9 * (1.0 + defence) * UNKNOWN_X


static func scouted(m: WorldModel, g: Dictionary, target: String) -> bool:
	var k: Dictionary = (g.get("knows", {}) as Dictionary).get(target, {})
	return not k.is_empty() and bool(k.get("scouted", false)) and m.now - float(k.get("t", -100.0)) <= FRESH_DAYS


## Zones `g` can reach for a goal: its own and the linked ones.
static func reach(m: WorldModel, g: Dictionary) -> Array:
	var out: Array = [String(g.zone)]
	var quiet := String(m.w.get("start_zone", "")) if m.now < 2.0 else ""
	for z: String in m.zone(String(g.zone)).get("links", []):
		if z != quiet and m.zones().has(z) and m.crossing_open(String(g.zone), z):
			out.append(z)
	return out


static func options(m: WorldModel, g: Dictionary) -> Array:
	var out: Array = []
	var kind := String(g.kind)
	var p: Dictionary = g.personality
	var need_food := clampf(1.0 - WorldGroup.days_of_food(g) / 5.0, 0.0, 1.0)
	var mine := maxf(0.5, WorldGroup.strength(g, m.people))
	var here := String(g.zone)
	var r := reach(m, g)
	out.append({"kind": "rest", "zone": here, "place": "", "target": "", "gain": 0.1, "need": 1.0, "loss": 0.0, "noise": 0.0, "rel": 0.0, "bias": 0.0})
	if kind == "enclave":
		var h: Dictionary = g.home
		out.append({"kind": "patrol", "zone": String(h.get("zone", here)), "place": String(h.get("place", "")), "target": "", "gain": 0.5, "need": 1.0,
			"loss": 0.0, "noise": noise_cost(m, "patrol", here), "rel": 0.0, "bias": 0.1})
		out.append({"kind": "defend", "zone": String(h.get("zone", here)), "place": String(h.get("place", "")), "target": "", "gain": 0.4, "need": 1.0,
			"loss": 0.0, "noise": 0.0, "rel": 0.0, "bias": 0.1})
		return out
	# forage: the best place within reach by its richness, the zone's loot and how long since it was looted
	for z: String in r:
		var zd := m.zone(z)
		var reg := WorldRegions.region_def(String(zd.get("region", "")))
		var loot: Dictionary = reg.get("loot", {})
		var dz := danger(m, g, z)
		var nc := noise_cost(m, "forage", z)
		var forage_v := func(pl: Dictionary) -> float:
			if String(pl.holder) != "" and String(pl.holder) != String(g.id):
				return -INF
			var fresh := clampf((m.now - float(pl.get("looted", -100.0))) / WorldModel.REFILL_DAYS, 0.0, 1.0)
			return 0.15 + 0.5 * float(pl.richness) * fresh * (float(loot.get("food", 1.0)) + float(loot.get("ammo", 1.0))) * 0.5
		for pl: Dictionary in _best_places(zd, g, forage_v):
			out.append({"kind": "forage", "zone": z, "place": String(pl.id), "target": "", "gain": float(pl._v), "need": 0.4 + 1.2 * need_food,
				"loss": dz + (0.1 if z != here else 0.0), "noise": nc, "rel": 0.0, "bias": 0.15 if kind == "scavengers" else 0.0})
	# work: hunt, fish, farm (settlers and scavengers), by the region's yield and the season
	if kind in ["settlers", "scavengers"]:
		var zd := m.zone(here)
		var yield_x := float(WorldRegions.region_def(String(zd.get("region", ""))).get("yield", 1.0)) * float(WorldModel.SEASON_YIELD.get(m.season(), 1.0))
		var farm := 1.0 if not (g.home as Dictionary).is_empty() else 0.5
		out.append({"kind": "work", "zone": here, "place": String((g.home as Dictionary).get("place", "")), "target": "", "gain": 0.45 * yield_x * farm,
			"need": 0.4 + need_food, "loss": danger(m, g, here) * 0.3, "noise": noise_cost(m, "work", here), "rel": 0.0, "bias": 0.15 if kind == "settlers" else 0.0})
	# trade: a group within reach that'll deal (not cultists), by how much each lacks what the other has
	if kind != "cultists":
		for o: Dictionary in m.groups_near(r):
			var oid := String(o.id)
			if oid == String(g.id) or not bool(o.alive) or String(o.kind) in ["cultists", "lone"] or bool(o.get("live", false)) or not String(o.zone) in r:
				continue
			if WorldGroup.relation(g, oid) < -10.0 or WorldGroup.relation(o, String(g.id)) < -20.0:
				continue
			var tg := WorldTrade.gain(g, o)
			if tg <= 0.05:
				continue
			out.append({"kind": "trade", "zone": String(o.zone), "place": "", "target": oid, "gain": minf(tg, 1.2), "need": 0.6 + need_food * 0.5,
				"loss": 0.05 + (0.1 if String(o.kind) == "raiders" else 0.0), "noise": noise_cost(m, "trade", String(o.zone)), "rel": 0.0,
				"bias": 0.1 if kind in ["settlers", "scavengers"] else 0.0})
	# settle: a home at the best free place (water, defensibility, loot, quiet)
	if kind in ["settlers", "raiders", "scavengers"] and ((g.home as Dictionary).is_empty() or m.pressure_of(String((g.home as Dictionary).zone)) > 60.0):
		for z: String in r:
			var zd := m.zone(z)
			if bool(WorldRegions.region_def(String(zd.region)).get("unheld", false)):
				continue
			var water := float(WorldRegions.region_def(String(zd.region)).get("water", 1.0))
			var pz := m.pressure_of(z) / 100.0 * 0.5
			var dz := danger(m, g, z) * 0.5
			var nc := noise_cost(m, "settle", z)
			var settle_v := func(pl: Dictionary) -> float:
				if String(pl.holder) != "":
					return -INF
				return water * 0.3 + float(pl.defence) * (0.6 if kind == "raiders" else 0.4) + float(pl.richness) * 0.15 - pz
			for pl: Dictionary in _best_places(zd, g, settle_v):
				out.append({"kind": "settle", "zone": z, "place": String(pl.id), "target": "", "gain": maxf(0.0, float(pl._v)),
					"need": 1.0 if (g.home as Dictionary).is_empty() else 0.4, "loss": dz, "noise": nc, "rel": 0.0,
					"bias": (0.2 if kind == "settlers" else 0.05) - (0.15 if kind == "scavengers" else 0.0)})
	# raid: raiders, and the desperate and cruel; settlements and the players' farm get a demand first
	var desperate := need_food > 0.8 and float(p.get("cruelty", 0.0)) > 0.3
	if kind == "raiders" or desperate:
		for o: Dictionary in m.groups_near(r):
			var oid := String(o.id)
			if oid == String(g.id) or not bool(o.alive) or String(o.kind) in ["enclave", "lone"] or not String(o.zone) in r:
				continue
			if String(o.kind) == kind and kind == "raiders":
				continue
			var their := WorldTrade.supplies_value(o.supplies)
			var gain := clampf(their / (300.0 * maxf(1.0, WorldGroup.size(g))), 0.0, 1.5) * (0.5 + float(p.get("greed", 0.3)))
			var loss := known_strength(m, g, oid) / mine * 0.6
			out.append({"kind": "raid", "zone": String(o.zone), "place": String((o.home as Dictionary).get("place", "")), "target": oid, "gain": gain,
				"need": 0.6 + need_food * 0.8, "loss": loss, "noise": noise_cost(m, "raid", String(o.zone)), "rel": _rel_cost(m, g, oid),
				"bias": (0.3 if kind == "raiders" else 0.0) + float(p.get("cruelty", 0.0)) * 0.2})
		var pz := String(m.player.get("zone", ""))
		if pz != "" and m.now >= 2.0 and WorldRegions.distance(m.zones(), here, pz) in [0, 1, 2]:  # (day one is quiet at the farm)
			var gain := clampf(float(m.player.get("stocks_value", 1500.0)) / (300.0 * maxf(1.0, WorldGroup.size(g))), 0.0, 1.5) * (0.5 + float(p.get("greed", 0.3)))
			out.append({"kind": "raid", "zone": pz, "place": String(m.player.get("place", "safehouse")), "target": "player", "gain": gain,
				"need": 0.6 + need_food * 0.8, "loss": known_strength(m, g, "player") / mine * 0.6, "noise": noise_cost(m, "raid", pz),
				"rel": maxf(0.0, WorldGroup.relation(g, "player")) / 100.0, "bias": (0.25 if kind == "raiders" else 0.0) + float(p.get("cruelty", 0.0)) * 0.2})
	# defend / fortify: a home with a known threat near (a hostile group, a horde)
	var home: Dictionary = g.home
	if not home.is_empty():
		var threat := 0.0
		for z: String in [String(home.zone)] + (m.zone(String(home.zone)).get("links", []) as Array):
			threat = maxf(threat, danger(m, g, z) * (1.0 if z == String(home.zone) else 0.5))
		var room := 1.0 - float(g.get("defence", 0.0))
		out.append({"kind": "defend", "zone": String(home.zone), "place": String(home.place), "target": "", "gain": 0.1 + threat * 0.8 + room * 0.15,
			"need": 1.0, "loss": 0.0, "noise": noise_cost(m, "defend", String(home.zone)), "rel": 0.0, "bias": 0.1 if kind == "settlers" else 0.0})
	# flee: the zone is boiling, or someone much stronger and hostile is here
	var dh := danger(m, g, here)
	if dh > 0.6:
		var best_z := ""
		var best_d := INF
		for z: String in m.zone(here).get("links", []):
			var dz := danger(m, g, z)
			if dz < best_d:
				best_d = dz
				best_z = z
		if best_z != "":
			out.append({"kind": "flee", "zone": best_z, "place": "", "target": "", "gain": dh, "need": 1.0 + float((g.mood as Dictionary).fear),
				"loss": best_d * 0.5 + 0.1, "noise": 0.0, "rel": 0.0, "bias": -0.2 if not home.is_empty() else 0.0})
	# scout: a group within reach it knows nothing fresh of (raiders scout their prey, settlers their threats)
	for o: Dictionary in m.groups_near(r):
		var oid := String(o.id)
		if oid == String(g.id) or not bool(o.alive) or String(o.kind) == "lone" or not String(o.zone) in r or scouted(m, g, oid):
			continue
		var interest := 0.35 if kind == "raiders" or String(o.kind) in ["raiders", "cultists"] else 0.15
		out.append({"kind": "scout", "zone": String(o.zone), "place": "", "target": oid, "gain": interest, "need": 0.8, "loss": 0.1,
			"noise": 0.0, "rel": 0.0, "bias": 0.0})
		break
	# recruit / capture: a lone survivor (or a tiny group, for the cult) within reach, not where the players are
	for o: Dictionary in m.groups_near(r):
		var oid := String(o.id)
		if oid == String(g.id) or not bool(o.alive) or not String(o.zone) in r or String(o.zone) == m.hosted:
			continue
		if String(o.kind) == "lone" and kind in ["settlers", "scavengers", "raiders"] and WorldGroup.relation(g, oid) >= -10.0:
			out.append({"kind": "recruit", "zone": String(o.zone), "place": "", "target": oid, "gain": 0.3 + (0.3 if WorldGroup.size(g) < 4 else 0.0),
				"need": 0.7, "loss": 0.05, "noise": 0.0, "rel": 0.0, "bias": 0.1 if kind == "settlers" else 0.0})
		if kind == "cultists" and (String(o.kind) == "lone" or (WorldGroup.size(o) <= 2 and String(o.kind) != "enclave")):
			out.append({"kind": "capture", "zone": String(o.zone), "place": "", "target": oid, "gain": 0.6 + float(p.get("faith", 0.5)) * 0.3, "need": 0.8,
				"loss": known_strength(m, g, oid) / mine * 0.4, "noise": noise_cost(m, "capture", String(o.zone)), "rel": _rel_cost(m, g, oid),
				"bias": float(p.get("faith", 0.5)) * 0.3})
	# feed the horde: the cult gives a captive to its kept dead
	if kind == "cultists" and not (g.captives as Array).is_empty():
		out.append({"kind": "feed", "zone": here, "place": String(home.get("place", "")), "target": "", "gain": 0.6 + float(p.get("faith", 0.5)) * 0.4,
			"need": 1.0, "loss": 0.0, "noise": 0.0, "rel": 0.0, "bias": 0.2})
	# search: a member taken or lost
	for miss: Dictionary in g.get("missing", []):
		out.append({"kind": "search", "zone": String(miss.get("zone", here)), "place": "", "target": String(miss.get("id", "")),
			"gain": 0.7 + float(p.get("loyalty", 0.4)) * 0.3, "need": 1.0, "loss": danger(m, g, String(miss.get("zone", here))) * 0.5, "noise": 0.0,
			"rel": 0.0, "bias": 0.2})
		break
	# hunt the player: a grudge and the means
	if String(g.get("grudge", "")) == "player":
		var pz := String(m.player.get("hunt_zone", m.player.get("zone", "")))
		if pz != "" and mine >= float(m.player.get("strength", 3.0)) * 0.8:
			out.append({"kind": "hunt_player", "zone": pz, "place": "", "target": "player", "gain": 0.7, "need": 1.0,
				"loss": float(m.player.get("strength", 3.0)) / mine * 0.5, "noise": noise_cost(m, "hunt_player", pz), "rel": 0.0,
				"bias": float(p.get("cruelty", 0.2)) * 0.3})
	Seasons.bias_options(m, g, out)  # (phase D: the season's pull on every goal, a lit settlement)
	return out


## The best place of `zd` by `value` (and the group's current goal's place there, for the
## hysteresis), each as {"id", "_v"}; places valued -INF are out.
static func _best_places(zd: Dictionary, g: Dictionary, value: Callable) -> Array:
	var cur := String((g.get("goal", {}) as Dictionary).get("place", ""))
	var best := {}
	var out: Array = []
	for pl: Dictionary in zd.get("places", []):
		var v: float = value.call(pl)
		if v == -INF:
			continue
		if best.is_empty() or v > float(best._v):
			best = {"id": String(pl.id), "_v": v}
		if String(pl.id) == cur:
			out.append({"id": cur, "_v": v})
	if not best.is_empty() and not out.any(func(o: Dictionary) -> bool: return String(o.id) == String(best.id)):
		out.append(best)
	return out


## What attacking `target` costs `g` in standing: the groups that like the target and how much `g`
## itself likes it (0-1+).
static func _rel_cost(m: WorldModel, g: Dictionary, target: String) -> float:
	var c := maxf(0.0, WorldGroup.relation(g, target)) / 100.0
	for o: Dictionary in m.alive_groups():
		var oid := String(o.id)
		if oid == target or oid == String(g.id) or not bool(o.alive):
			continue
		var likes := WorldGroup.relation(o, target)
		if likes >= 30.0 and WorldGroup.relation(g, oid) > -30.0:
			c += likes / 300.0
	return c


# --- Acting --------------------------------------------------------------------------------------

## One tick of `g`'s goal: the journey to its zone, then its work there.
static func act(m: WorldModel, g: Dictionary) -> void:
	var goal: Dictionary = g.get("goal", {})
	if goal.is_empty():
		return
	var to := String(goal.get("zone", g.zone))
	if to != String(g.zone):
		travel(m, g, to)
		if to != String(g.zone):
			return
	match String(goal.kind):
		"forage":
			_forage(m, g, goal)
		"work":
			_work(m, g, goal)
		"trade":
			_trade(m, g, goal)
		"settle":
			var pl := WorldRegions.place(m.zone(to), String(goal.place))
			if not pl.is_empty() and String(pl.holder) == "":
				m.set_home(g, to, pl)
				g.pos = (pl.pos as Array).duplicate()
				m.event(to, "settled", [String(g.id)], "%s made camp at %s" % [String(g.name), m.place_name(to, String(pl.id))], String(pl.id))
			_done(g)
		"raid":
			_raid(m, g, goal)
		"defend":
			g.defence = snappedf(minf(1.0, float(g.get("defence", 0.0)) + 0.03), 0.001)
			_tick_work(g, goal)
		"patrol", "rest":
			(g.mood as Dictionary).morale = minf(1.0, float((g.mood as Dictionary).morale) + 0.01)
			_tick_work(g, goal)
		"flee":
			if not (g.home as Dictionary).is_empty() and String((g.home as Dictionary).zone) != String(g.zone):
				var h: Dictionary = g.home
				m.add_trace(String(h.zone), String(h.place), "a camp left in a hurry, %s's" % String(g.name), [])
				m.clear_home(g)
			m.event(String(g.zone), "fled", [String(g.id)], "%s fled into %s" % [String(g.name), String(m.zone(String(g.zone)).get("name", g.zone))])
			_done(g)
		"scout":
			_scout(m, g, goal)
		"recruit":
			_recruit(m, g, goal)
		"capture":
			_capture(m, g, goal)
		"feed":
			_feed(m, g, goal)
		"search":
			_search(m, g, goal)
		"hunt_player":
			_hunt_player(m, g, goal)
		_:
			_done(g)


static func _done(g: Dictionary) -> void:
	g.goal = {}
	g.journey = {}


static func _tick_work(g: Dictionary, goal: Dictionary) -> bool:
	goal.work = int(goal.get("work", 0)) + 1
	if int(goal.work) >= int(WORK_TICKS.get(String(goal.kind), 4)):
		_done(g)
		return true
	return false


## A leg of the journey toward `to` (a zone crossing every TRAVEL_TICKS; a vehicle halves it).
static func travel(m: WorldModel, g: Dictionary, to: String) -> void:
	var j: Dictionary = g.get("journey", {})
	if j.is_empty() or String(j.get("to", "")) != to:
		var path := WorldRegions.path(m.zones(), String(g.zone), to)
		if path.size() < 2:
			_done(g)
			return
		j = {"to": to, "path": path, "leg": 1, "progress": 0.0}
		g.journey = j
	j.progress = float(j.progress) + (2.0 if int(g.get("vehicles", 0)) > 0 else 1.0) / WorldModel.TRAVEL_TICKS
	if float(j.progress) < 1.0:
		return
	var next := String((j.path as Array)[int(j.leg)])
	var from := String(g.zone)
	if not m.crossing_open(from, next):
		_done(g)  # (the bridge is down: think again)
		return
	g.zone = next
	j.leg = int(j.leg) + 1
	j.progress = 0.0
	var half := float(m.zone(next).get("size_m", 1920.0)) * 0.5 - 150.0
	var side := _side_from(m, next, from)
	g.pos = [[0.0, -half], [0.0, half], [-half, 0.0], [half, 0.0]][side] if side >= 0 else [0.0, 0.0]
	if int(j.leg) >= (j.path as Array).size():
		g.journey = {}
	if not (m.zone(next).get("horde", {}) as Dictionary).is_empty():
		WorldFights.horde_fight(m, g, next)


## Which side of `zone_id` faces `from` (0 north, 1 south, 2 west, 3 east), by the region grid.
static func _side_from(m: WorldModel, zone_id: String, from: String) -> int:
	var cells: Dictionary = m.w.get("cells", {})
	if not cells.has(zone_id) or not cells.has(from):
		return -1
	var a: Array = cells[zone_id]
	var b: Array = cells[from]
	var d := Vector2i(int(b[0]) - int(a[0]), int(b[1]) - int(a[1]))
	for i in 4:
		if RegionMap.SIDE_STEP[i] == d:
			return i
	return -1


static func _forage(m: WorldModel, g: Dictionary, goal: Dictionary) -> void:
	var zd := m.zone(String(g.zone))
	var pl := WorldRegions.place(zd, String(goal.place))
	if pl.is_empty():
		_done(g)
		return
	g.pos = (pl.pos as Array).duplicate()
	if not _tick_work(g, goal):
		return
	var fresh := clampf((m.now - float(pl.get("looted", -100.0))) / WorldModel.REFILL_DAYS, 0.0, 1.0)
	var loot: Dictionary = WorldRegions.region_def(String(zd.region)).get("loot", {})
	var n := float(WorldGroup.size(g))
	var got := {}
	for k: String in WorldGroup.SUPPLY_KEYS:
		var v := n * 0.5 * float(pl.richness) * fresh * float(loot.get(k, 1.0)) * (1.5 if k in ["food", "water"] else 0.6)
		WorldGroup.add_supply(g, k, v)
		got[k] = snappedf(v, 0.01)
	pl.looted = m.now
	m.raise_pressure(String(g.zone), 2.0, WorldModel._place_v(pl))
	var rng := m.rng_for(String(g.id), "forage")
	if rng.randf() < float(zd.get("dead", 1.0)) * WorldRegions.dead_base(zd) * 0.08 and WorldGroup.size(g) > 1:
		var pid := String(g.members[rng.randi_range(0, WorldGroup.size(g) - 1)])
		var nm := String((m.people.get(pid, {}) as Dictionary).get("name", "someone"))
		m.person_dies(pid, g, "bitten while foraging", true, pl)
		m.add_trace(String(g.zone), String(pl.id), "a body by the door, %s" % nm, [nm])
		m.event(String(g.zone), "death", [String(g.id)], "%s of %s was bitten at %s" % [nm, String(g.name), m.place_name(String(g.zone), String(pl.id))], String(pl.id))
	g["last_forage"] = got


static func _work(m: WorldModel, g: Dictionary, goal: Dictionary) -> void:
	var zd := m.zone(String(g.zone))
	var yield_x := float(WorldRegions.region_def(String(zd.get("region", ""))).get("yield", 1.0)) * float(WorldModel.SEASON_YIELD.get(m.season(), 1.0))
	var farm := 1.0 if not (g.home as Dictionary).is_empty() else 0.5
	var n := float(WorldGroup.size(g))
	WorldGroup.add_supply(g, "food", n * 1.6 * yield_x * farm / WorldModel.TICKS_PER_DAY * 4.0)
	WorldGroup.add_supply(g, "water", n * 1.2 * float(WorldRegions.region_def(String(zd.get("region", ""))).get("water", 1.0)) / WorldModel.TICKS_PER_DAY * 4.0)
	WorldGroup.add_supply(g, "wood", n * 0.2 / WorldModel.TICKS_PER_DAY * 4.0)
	_tick_work(g, goal)


static func _trade(m: WorldModel, g: Dictionary, goal: Dictionary) -> void:
	var o := m.group(String(goal.target))
	if o.is_empty() or not bool(o.alive) or String(o.zone) != String(g.zone) or bool(o.get("live", false)):
		_done(g)
		return
	var moved := WorldTrade.swap(g, o)
	WorldGroup.change_relation(g, String(o.id), 5.0)
	WorldGroup.change_relation(o, String(g.id), 5.0)
	for key: String in (o.get("intel", {}) as Dictionary).keys():  # what each knows, swapped with the goods
		m.learn(g, key.to_int(), "told")
	for key: String in (g.get("intel", {}) as Dictionary).keys():
		m.learn(o, key.to_int(), "told")
	g["last_trade"] = {"with": String(o.id), "value": snappedf(moved, 0.1), "tick": m.tick()}
	m.event(String(g.zone), "trade", [String(g.id), String(o.id)], "%s traded with %s ($%d of goods)" % [String(g.name), String(o.name), roundi(moved)])
	_done(g)


static func _scout(m: WorldModel, g: Dictionary, goal: Dictionary) -> void:
	var tid := String(goal.target)
	var o := m.group(tid)
	if not o.is_empty() and bool(o.alive):
		var defence := 1.0 + float(o.get("defence", 0.0)) + (0.3 if not (o.home as Dictionary).is_empty() else 0.0)
		(g.knows as Dictionary)[tid] = {"t": m.now, "strength": snappedf(WorldGroup.strength(o, m.people) * defence, 0.01), "scouted": true,
			"size": WorldGroup.size(o), "supplies": snappedf(WorldTrade.supplies_value(o.supplies), 1.0), "zone": String(o.zone)}
	var scout_id := String(g.members[m.rng_for(String(g.id), "scout").randi_range(0, WorldGroup.size(g) - 1)]) if WorldGroup.size(g) > 0 else ""
	if scout_id != "":
		(m.people.get(scout_id, {}) as Dictionary)["scout"] = true
	for e: Dictionary in m.w.events:  # what the scout saw there in the last days
		if String(e.zone) == String(g.zone) and m.now - float(e.get("t", 0.0)) <= 3.0:
			m.learn(g, int(e.id), "scout")
	_done(g)


static func _recruit(m: WorldModel, g: Dictionary, goal: Dictionary) -> void:
	var o := m.group(String(goal.target))
	if o.is_empty() or not bool(o.alive) or String(o.kind) != "lone" or String(o.zone) != String(g.zone) or String(o.zone) == m.hosted:
		_done(g)
		return
	var pid := String(o.leader)
	var rec: Dictionary = m.people.get(pid, {})
	var rng := m.rng_for(String(g.id), "recruit")
	var willing := 0.5 + WorldGroup.relation(o, String(g.id)) / 200.0 + (0.2 if String(g.kind) == "settlers" else -0.1) + (0.2 if WorldGroup.days_of_food(o) < 1.0 else 0.0)
	if rec.is_empty() or String(rec.get("status", "")) != "out_there" or rng.randf() > willing:
		WorldGroup.change_relation(g, String(o.id), -5.0)
		_done(g)
		return
	rec.status = WorldGroup.GROUPED
	rec["world_group"] = String(g.id)
	(g.members as Array).append(pid)
	for k: String in WorldGroup.SUPPLY_KEYS:
		WorldGroup.add_supply(g, k, WorldGroup.supply(o, k))
	o.alive = false
	o.members = []
	m.note(rec, "joined %s" % String(g.name))
	m.event(String(g.zone), "recruit", [String(g.id)], "%s took in %s" % [String(g.name), String(rec.get("name", "a stranger"))])
	_done(g)


## The cult takes a lone survivor (or a tiny group): its people become captives; their friends'
## groups (a member who likes one of them, or a group that likes theirs) get a search goal's
## missing entry.
static func _capture(m: WorldModel, g: Dictionary, goal: Dictionary) -> void:
	var o := m.group(String(goal.target))
	if o.is_empty() or not bool(o.alive) or String(o.zone) != String(g.zone) or String(o.zone) == m.hosted:
		_done(g)
		return
	var theirs := WorldGroup.strength(o, m.people)
	var ours := WorldGroup.strength(g, m.people)
	var rng := m.rng_for(String(g.id), "capture")
	if ours * rng.randf_range(0.8, 1.4) < theirs * 1.2:  # they fought them off
		WorldFights.resolve(m, g, o, String((o.home as Dictionary).get("place", "")))
		_done(g)
		return
	var names: Array = []
	for pid: String in (o.members as Array).duplicate():
		var rec: Dictionary = m.people.get(pid, {})
		if rec.is_empty():
			continue
		rec.status = "captive"
		rec["captor"] = String(g.id)
		rec.erase("world_group")
		rec.zone = String(g.zone)
		m.note(rec, "taken by %s" % String(g.name))
		(g.captives as Array).append(pid)
		names.append(String(rec.get("name", "someone")))
		_tell_friends(m, pid, String(o.id), String(g.id))
	o.members = []
	o.alive = false
	var e := m.event(String(g.zone), "capture", [String(g.id), String(o.id)], "%s took %s in %s" % [String(g.name), ", ".join(names), String(m.zone(String(g.zone)).get("name", g.zone))])
	(g as Dictionary)["last_capture"] = int(e.id)
	_done(g)


## Friends of the captive `pid` (from group `from_gid`) miss them: a missing entry on their groups.
static func _tell_friends(m: WorldModel, pid: String, from_gid: String, captor: String) -> void:
	for oid: String in WorldModel._sorted(m.groups().keys()):
		var f: Dictionary = m.groups()[oid]
		if oid == from_gid or oid == captor or not bool(f.alive) or String(f.kind) == "lone":
			continue
		var friend := WorldGroup.relation(f, from_gid) >= SurvivorsLayer.FRIEND_AT
		if not friend:
			for mid: String in f.members:
				if SurvivorPerson.relation(m.people.get(mid, {}), pid) >= SurvivorsLayer.FRIEND_AT:
					friend = true
					break
		if friend:
			(f.missing as Array).append({"id": pid, "zone": String(m.group(captor).get("zone", "")), "by": captor, "since": m.now})
			WorldGroup.change_relation(f, captor, -40.0)


static func _feed(m: WorldModel, g: Dictionary, goal: Dictionary) -> void:
	if (g.captives as Array).is_empty():
		_done(g)
		return
	var pid := String((g.captives as Array).pop_front())
	var rec: Dictionary = m.people.get(pid, {})
	var nm := String(rec.get("name", "someone"))
	if not rec.is_empty():
		rec.status = "dead"
		rec["died_day"] = m.day()
		rec["killed_by_dead"] = true
		rec["world_dead"] = "given to the dead"
		rec["body_pos"] = [float(g.pos[0]), 0.0, float(g.pos[1])]
		rec.erase("captor")
		m.note(rec, "given to the dead by %s" % String(g.name))
	m.raise_pressure(String(g.zone), 15.0, WorldGroup.pos2(g))
	m.add_trace(String(g.zone), String(goal.get("place", "")), "a stake, and what's left of %s" % nm, [nm])
	m.event(String(g.zone), "fed", [String(g.id)], "%s gave %s to the dead" % [String(g.name), nm], String(goal.get("place", "")))
	_done(g)


static func _search(m: WorldModel, g: Dictionary, goal: Dictionary) -> void:
	var pid := String(goal.target)
	var rec: Dictionary = m.people.get(pid, {})
	var miss: Array = g.missing
	var entry := {}
	for e: Dictionary in miss:
		if String(e.id) == pid:
			entry = e
	miss.erase(entry)
	if rec.is_empty() or String(rec.get("status", "")) != "captive":
		WorldGroup.remember(g, m.now, "search", "found no sign of %s" % String(rec.get("name", "them")), pid)
		_done(g)
		return
	var captor := m.group(String(rec.get("captor", "")))
	if not captor.is_empty() and String(captor.zone) == String(g.zone) and WorldGroup.strength(g, m.people) > known_strength(m, g, String(captor.id)) * 0.8:
		var won := WorldFights.resolve(m, g, captor, String((captor.home as Dictionary).get("place", "")))
		if won and String(rec.get("status", "")) == "captive":
			rec.status = WorldGroup.GROUPED
			rec["world_group"] = String(g.id)
			rec.erase("captor")
			(captor.captives as Array).erase(pid)
			(g.members as Array).append(pid)
			m.event(String(g.zone), "rescue", [String(g.id), String(captor.id)], "%s got %s back from %s" % [String(g.name), String(rec.get("name", "")), String(captor.name)])
	else:
		g.grudge = String(captor.get("id", ""))
		WorldGroup.remember(g, m.now, "search", "%s is held by %s" % [String(rec.get("name", "")), String(captor.get("name", "someone"))], pid)
	_done(g)


## A raid: to the target, a demand first when it's a settlement (a home) or the players' farm,
## then the fight (far) or, at the hosted zone, the live attack (WorldLive).
static func _raid(m: WorldModel, g: Dictionary, goal: Dictionary) -> void:
	var tid := String(goal.target)
	if tid == "player":
		_raid_player(m, g, goal)
		return
	var o := m.group(tid)
	if o.is_empty() or not bool(o.alive) or String(o.zone) != String(g.zone) or bool(o.get("live", false)):
		_done(g)
		return
	var settled := not (o.home as Dictionary).is_empty()
	match String(goal.phase):
		"go":
			if settled:
				goal.phase = "demand"
				var want := WorldTrade.supplies_value(o.supplies) * DEMAND_SHARE
				m.event(String(g.zone), "demand", [String(g.id), tid], "%s demanded $%d of goods from %s" % [String(g.name), roundi(want), String(o.name)], String((o.home as Dictionary).place))
				# the target judges it: pays when the raiders look stronger than it can bear, or it's cautious
				var their_view := known_strength(m, o, String(g.id))
				var mine := WorldGroup.strength(o, m.people) * (1.0 + float(o.get("defence", 0.0)))
				if their_view > mine * 1.1 or (float((o.personality as Dictionary).get("caution", 0.5)) > 0.65 and their_view > mine * 0.7):
					for k: String in WorldGroup.SUPPLY_KEYS:
						var give := WorldGroup.supply(o, k) * DEMAND_SHARE
						WorldGroup.add_supply(o, k, -give)
						WorldGroup.add_supply(g, k, give)
					WorldGroup.change_relation(o, String(g.id), -15.0)
					m.event(String(g.zone), "paid", [String(g.id), tid], "%s paid %s off" % [String(o.name), String(g.name)])
					_done(g)
				else:
					goal.phase = "attack"
					WorldGroup.change_relation(o, String(g.id), -25.0)
					m.event(String(g.zone), "refused", [String(g.id), tid], "%s refused %s" % [String(o.name), String(g.name)])
			else:
				goal.phase = "attack"
		"attack":
			WorldFights.resolve(m, g, o, String((o.home as Dictionary).get("place", "")), scouted(m, g, tid))
			_done(g)
		_:
			goal.phase = "attack"


## The players' farm is a place too (call 55, 67): a demand as a journal line and a message, time
## to pay (WorldSim.server_pay_demand); unpaid, an attack. The settlement can't fall (call 25): a
## live attack when its zone is hosted, else the stores taken if undefended (the settlement lane's
## stocks, when it has them) or the raiders beaten off. In the catch-up only the demand stands.
static func _raid_player(m: WorldModel, g: Dictionary, goal: Dictionary) -> void:
	var gid := String(g.id)
	var demands: Dictionary = m.w.demands
	match String(goal.phase):
		"go":
			var want := roundi(clampf(float(m.player.get("stocks_value", 1500.0)) * DEMAND_SHARE, 200.0, 5000.0))
			demands[gid] = {"group": gid, "name": String(g.name), "want": want, "zone": String(g.zone), "made": m.now,
				"due": m.now + DEMAND_DAYS, "paid": false, "deferred": bool(m.player.get("safe", false))}
			goal.phase = "wait"
			m.event(String(g.zone), "demand", [gid, "player"], "%s want $%d of goods from your farm, or they'll take it" % [String(g.name), want])
			m.actions.append({"kind": "demand", "group": gid, "name": String(g.name), "want": want, "due": m.now + DEMAND_DAYS})
		"wait":
			var d: Dictionary = demands.get(gid, {})
			if d.is_empty():
				_done(g)
				return
			if bool(d.get("paid", false)):
				WorldGroup.change_relation(g, "player", 10.0)
				demands.erase(gid)
				_done(g)
				return
			if bool(m.player.get("safe", false)) or bool(d.get("deferred", false)) or m.now < float(d.due):
				return
			goal.phase = "attack"
		"attack":
			demands.erase(gid)
			if String(g.zone) == m.hosted:
				g.pos = (m.player.get("place_pos", [0.0, 0.0]) as Array).duplicate()
				g["assault"] = true  # (WorldLive: the live attack)
				m.event(String(g.zone), "raid", [gid, "player"], "%s are coming for the farm" % String(g.name))
				_done(g)
				return
			var mine := WorldGroup.strength(g, m.people)
			var home := float(m.player.get("home_strength", 0.0))
			if home < mine and bool(m.player.get("can_take", false)):
				m.actions.append({"kind": "take_stock", "group": gid, "share": 0.3})
				WorldGroup.add_supply(g, "food", float(WorldGroup.size(g)) * 2.0)
				m.event(String(g.zone), "raid", [gid, "player"], "%s raided the farm's stores while nobody was there" % String(g.name))
			else:
				var losses := maxi(1, roundi(WorldGroup.size(g) * 0.3))
				var names: Array = []
				for i in mini(losses, WorldGroup.size(g)):
					var pid := String(g.members[-1])
					names.append(String((m.people.get(pid, {}) as Dictionary).get("name", "")))
					m.person_dies(pid, g, "shot raiding the farm", false)
				m.event(String(g.zone), "raid", [gid, "player"], "%s hit the farm and were beaten off (%s dead)" % [String(g.name), ", ".join(names)])
			g.grudge = "player"
			_done(g)
		_:
			goal.phase = "go"


## A grudge: they come to where the players are; at the hosted zone, the live attack.
static func _hunt_player(m: WorldModel, g: Dictionary, goal: Dictionary) -> void:
	if String(g.zone) == m.hosted and not bool(m.player.get("safe", false)):
		g["assault"] = true
		m.event(String(g.zone), "hunt", [String(g.id), "player"], "%s are hunting you" % String(g.name))
	_done(g)
