class_name Enclave
extends RefCounted
## The enclave as a real faction on the world sim (docs/survival_world.md section 6, calls 24,
## 56, 68; docs/survival_enclave.md): the one enclave group (WorldSim's evac group; in clear the
## map it is made here, a faction with no evac) with its posts at its homes (the port and the
## military base: the world's first zones of those types) and its patrols walking routes between
## them on the far tick (EnclaveDetachment); tolls at its places (far groups pay or are turned
## back; the players get a demand: the council's question at the settlement, else a direct ask
## answered through server_answer_toll); looters shot (a group foraging where the enclave holds
## the ground gets a fight); trade with trusted settlements (meds and fuel for food and, now and
## then, a person); three officers (named Persons: a hard one, a decent one, a frightened one)
## with standing toward the players; its nature by seed (honest, corrupt, collapsing: the
## price's size, whether the evac is real, members drifting off); the price by seed (the cure:
## a serum or an immune person; an escorted convoy base-to-port; a settlement's loyalty; your
## best people conscripted), its progress, and server_pay_price (WorldSim.server_set_evac_paid);
## the three routes: help (earn the price), infiltrate (a uniform and a forged pass: the
## enclave's stance to the players friendly while worn, until a check fails), break (its home
## post down to nobody: the port taken, the evac the players' own); and joining as a path
## (server_join: tasks in the journal, standing with everyone else falls, companions with a
## conscience may leave, what they learn inside feeds ARCHE's trail).
##
## State: Survival.state()["enclave"] (beside the world section: a far tick on the worker never
## overwrites it). Public API for the UI and talk lanes: price, price_text, officers, posts,
## patrols, pending_tolls, server_answer_toll, server_pay_price, server_deliver, server_start_convoy,
## server_hand_over, server_conscript, server_wear_disguise, server_take_off_disguise,
## server_check_disguise, server_join, tasks, server_officer_standing, server_kill, is_broken.

const KEY := "enclave"
const NATURES: Array[String] = ["honest", "corrupt", "collapsing"]
const PRICE_KINDS: Array[String] = ["cure", "convoy", "loyalty", "conscripts"]
const ROLES: Array[String] = ["hard", "decent", "frightened"]
## Proposed: the officers' ranks, leanings and starting standing with the players.
const OFFICER := {
	"hard": {"rank": "Major", "traits": ["hot_headed", "brave"], "standing": -10.0},
	"decent": {"rank": "Lieutenant", "traits": ["kind", "calm"], "standing": 10.0},
	"frightened": {"rank": "Sergeant", "traits": ["timid", "gloomy"], "standing": 0.0},
}
## Proposed: the second post's people, the patrols and their size.
const POST_SIZE := Vector2i(5, 8)
const PATROLS := 2
const PATROL_SIZE := 3
## Proposed: the evac is real by nature (honest always; the corrupt may take the price and run;
## the collapsing may have no boats left).
const EVAC_REAL := {"honest": 1.0, "corrupt": 0.6, "collapsing": 0.7}
## Proposed: how much of each price the enclave wants (corrupt asks one more where it can).
const NEED := {"cure": 1, "convoy": 1, "loyalty": 1, "conscripts": 2}
## Proposed: tolls: the players' toll in dollars of goods (corrupt x2), a far group's share of
## its food, ammo and fuel, at most once a day each; a group the enclave hates (or a cruel raider
## crew) is turned back.
const TOLL_VALUE := 100.0
const TOLL_SHARE := 0.1
const TOLL_GAP_DAYS := 1.0
const TURN_BACK_REL := -30.0
## Proposed: a group foraging on the enclave's ground is shot at, once a day at most.
const LOOTER_GAP_DAYS := 1.0
## Proposed: trade with trusted settlements (relation TRUST+), a day apart: meds and fuel for food;
## a settlement of PEOPLE_FROM or more gives a person now and then.
const TRUST := 30.0
const TRADE_MEDS := 1.0
const TRADE_FUEL := 1.0
const TRADE_FOOD := 4.0
const PEOPLE_FROM := 7
const PEOPLE_CHANCE := 0.2
## Proposed: the collapsing enclave loses someone on a day at this chance.
const COLLAPSE_CHANCE := 0.35
## Proposed: the disguise: the enclave's standing with the players while it's worn, a check's
## chance to see through it (more with the hard officer about, less when the frightened one likes
## you).
const DISGUISE_REL := 40.0
const CHECK_CHANCE := 0.15
const HARD_X := 0.15
## Proposed: joining: the enclave's standing up, everyone else's down (more for its enemies);
## a companion with a conscience (kind or loyal) leaves at this chance.
const JOIN_REL := 50.0
const JOIN_OTHERS := -15.0
const JOIN_ENEMIES := -10.0
const CONSCIENCE: Array[String] = ["kind", "loyal"]
const CONSCIENCE_LEAVE := 0.35
## Proposed: a convoy's risk a zone unescorted (a horde or raiders there).
const CONVOY_RISK := 0.35
## Tests: a roll to use instead of a random one (-1: roll for real).
static var force_roll := -1.0


# --- State ---------------------------------------------------------------------------------------

static func data() -> Dictionary:
	var st := Survival.state()
	if not st.get(KEY) is Dictionary:
		st[KEY] = {}
	return st[KEY]


static func is_set_up() -> bool:
	return data().has("gid")


static func gid() -> String:
	return String(data().get("gid", ""))


static func group() -> Dictionary:
	return WorldSim.group(gid())


static func nature() -> String:
	return String(data().get("nature", ""))


static func evac_real() -> bool:
	return bool(data().get("evac_real", true))


static func posts() -> Dictionary:
	if not data().get("posts") is Dictionary:
		data()["posts"] = {}
	return data()["posts"]


static func patrols() -> Dictionary:
	if not data().get("patrols") is Dictionary:
		data()["patrols"] = {}
	return data()["patrols"]


## The post that is the enclave's home (the evac's: "port" or "base").
static func home_post() -> Dictionary:
	return posts().get(String(data().get("home", "")), {})


static func home_zone() -> String:
	return String(home_post().get("zone", ""))


static func is_broken() -> bool:
	return bool(data().get("broken", false))


static func is_joined() -> bool:
	return bool(data().get("joined", false))


static func _roll(r: RandomNumberGenerator) -> float:
	return force_roll if force_roll >= 0.0 else r.randf()


## The zones the enclave holds now: its posts' and its patrols' (zone id -> post or patrol id).
static func held_zones() -> Dictionary:
	var out := {}
	for p: Dictionary in posts().values():
		if EnclaveDetachment.size(p) > 0:
			out[String(p.zone)] = String(p.id)
	for p: Dictionary in patrols().values():
		if EnclaveDetachment.size(p) > 0 and not out.has(String(p.zone)):
			out[String(p.zone)] = String(p.id)
	return out


## The world's port and military base zones (the first of each type by id; the evac zone first
## when it is one): {"port": zone, "base": zone}.
static func post_zones(zones: Dictionary, evac_zone := "") -> Dictionary:
	var out := {}
	for z: String in [evac_zone] + WorldModel._sorted(zones.keys()):
		if z == "" or not zones.has(z):
			continue
		var t := String((zones[z] as Dictionary).get("type", ""))
		if t in ["port", "base"] and not out.has(t):
			out[t] = z
	return out


static func _strongest(zd: Dictionary) -> Dictionary:
	var best := {}
	for p: Dictionary in zd.get("places", []):
		if best.is_empty() or float(p.get("defence", 0.0)) > float(best.get("defence", 0.0)) or \
				(float(p.get("defence", 0.0)) == float(best.get("defence", 0.0)) and String(p.id) < String(best.id)):
			best = p
	return best


# --- Setup ---------------------------------------------------------------------------------------

## Host, main thread: the enclave on world `m` (once): its group (WorldSim's evac group, or a new
## one in clear-the-map), nature, price, posts, patrols, officers and trusted settlements.
static func server_setup(m: WorldModel) -> void:
	if is_set_up() or m.zones().is_empty():
		return
	var d := data()
	var goal: Dictionary = m.w.get("goal", {})
	var pz := post_zones(m.zones(), String(goal.get("evac_zone", "")))
	if pz.is_empty():
		return
	var g := m.group(String(goal.get("evac_group", "")))
	if g.is_empty() or not bool(g.get("alive", false)):
		var z := String(pz.get("port", pz.get("base", "")))
		var pl := _strongest(m.zone(z))
		g = m.new_group("enclave", z, WorldModel._place_v(pl), m.rng_for("enclave", "setup"))
		m.set_home(g, z, pl)
		g.defence = 0.8
	var terms := terms_for(m.world_seed)
	var nat := String(terms.nature)
	var kind := String(terms.kind)
	var need := int(terms.need)
	d["gid"] = String(g.id)
	d["nature"] = nat
	d["evac_real"] = bool(terms.evac_real)
	d["price"] = {"kind": kind, "need": need, "progress": 0, "paid": false, "log": []}
	d["tolls"] = {}
	d["next_toll"] = 1
	d["tolled"] = {}
	d["shot"] = {}
	d["joined"] = false
	d["tasks"] = []
	d["broken"] = false
	d["disguise"] = {}
	d["last_day"] = m.day()
	var home: Dictionary = g.home
	var home_z := String(home.get("zone", g.zone))
	var home_kind := "port" if String(pz.get("port", "")) == home_z else ("base" if String(pz.get("base", "")) == home_z else "home")
	d["home"] = home_kind
	var rng := m.rng_for(String(g.id), "posts")
	# the officers: named Persons at the home post
	var officers: Array = []
	for role: String in ROLES:
		var o: Dictionary = OFFICER[role]
		var rec := m.new_person(rng, home_z, WorldGroup.pos2(g), {"traits": (o.traits as Array).duplicate()})
		rec.status = WorldGroup.GROUPED
		rec["world_group"] = String(g.id)
		rec["enclave_officer"] = role
		rec["rank"] = String(o.rank)
		(g.members as Array).append(String(rec.id))
		officers.append({"id": String(rec.id), "role": role, "rank": String(o.rank), "name": String(rec.name), "standing": float(o.standing), "alive": true})
	d["officers"] = officers
	var qm := m.new_person(rng, home_z, WorldGroup.pos2(g), {"traits": ["greedy", "calm"]})  # the quartermaster: its trader
	qm.status = WorldGroup.GROUPED
	qm["world_group"] = String(g.id)
	qm["enclave"] = true
	qm["enclave_quartermaster"] = true
	(g.members as Array).append(String(qm.id))
	d["quartermaster"] = String(qm.id)
	# the other post's and the patrols' people are new members of the one group
	var home_members: Array = (g.members as Array).duplicate()
	var ps := posts()
	ps[home_kind] = EnclaveDetachment.make_post(home_kind, _post_name(home_kind, m.zone(home_z)), home_z,
		WorldRegions.place(m.zone(home_z), String(home.get("place", ""))), home_members)
	for k: String in ["port", "base"]:
		var z := String(pz.get(k, ""))
		if z == "" or k == home_kind:
			continue
		var pl := _strongest(m.zone(z))
		var members := _new_members(m, g, z, WorldModel._place_v(pl), rng.randi_range(POST_SIZE.x, POST_SIZE.y), rng)
		ps[k] = EnclaveDetachment.make_post(k, _post_name(k, m.zone(z)), z, pl, members)
		if not pl.is_empty() and String(pl.get("holder", "")) == "":
			pl.holder = String(g.id)
	var other := ""
	for k: String in ps:
		if k != home_kind:
			other = String((ps[k] as Dictionary).zone)
	var routes: Array = []
	if other != "":
		routes.append(EnclaveDetachment.loop_of(WorldRegions.path(m.zones(), home_z, other)))
	routes.append(EnclaveDetachment.ring_of(home_z, (m.zone(home_z).get("links", []) as Array)))
	if other != "":
		routes.append(EnclaveDetachment.ring_of(other, (m.zone(other).get("links", []) as Array)))
	var pt := patrols()
	for i in mini(PATROLS, routes.size()):
		var route: Array = routes[i]
		if route.size() < 2:
			continue
		var members := _new_members(m, g, String(route[0]), WorldGroup.pos2(g), PATROL_SIZE, rng)
		var pid := "patrol%d" % (i + 1)
		pt[pid] = EnclaveDetachment.make_patrol(pid, "the enclave's patrol %d" % (i + 1), route, members)
	# trusted settlements: settlers within two zones of a post, by seed
	for o: Dictionary in m.alive_groups():
		if String(o.kind) != "settlers":
			continue
		var near := false
		for p: Dictionary in ps.values():
			var dist := WorldRegions.distance(m.zones(), String(o.zone), String(p.zone))
			near = near or (dist >= 0 and dist <= 2)
		if near and m.rng_for(String(o.id), "enclave_trust").randf() < 0.6:
			WorldGroup.change_relation(g, String(o.id), 35.0)
			WorldGroup.change_relation(o, String(g.id), 35.0)
	m.event(home_z, "enclave", [String(g.id)], "the enclave holds %s with %d people under arms" % [String(m.zone(home_z).get("name", home_z)), WorldGroup.size(g)])
	SessionLog.note("survival enclave: %s at %s, %s, price %s x%d, evac %s, %d posts, %d patrols, %d people" % [String(g.name), home_z, nat, kind, need,
		"real" if bool(d.evac_real) else "a lie", ps.size(), pt.size(), WorldGroup.size(g)])


## The enclave's terms by the world seed (pure): {"nature", "evac_real", "kind" (the price's),
## "need"}.
static func terms_for(world_seed: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = hash([world_seed, "enclave", "nature"])
	var nat := NATURES[r.randi_range(0, NATURES.size() - 1)]
	var real := r.randf() < float(EVAC_REAL[nat])
	var kind := PRICE_KINDS[r.randi_range(0, PRICE_KINDS.size() - 1)]
	var need := int(NEED[kind]) + (1 if nat == "corrupt" and kind in ["convoy", "conscripts"] else 0)
	return {"nature": nat, "evac_real": real, "kind": kind, "need": need}


static func _post_name(kind: String, zd: Dictionary) -> String:
	match kind:
		"port":
			return "the enclave's port at %s" % String(zd.get("name", ""))
		"base":
			return "the enclave's garrison at the base in %s" % String(zd.get("name", ""))
	return "the enclave's post at %s" % String(zd.get("name", ""))


static func _new_members(m: WorldModel, g: Dictionary, zone_id: String, pos: Vector2, n: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for i in n:
		var rec := m.new_person(rng, zone_id, pos, {"traits": ["loyal"] if rng.randf() < 0.4 else []})
		rec.status = WorldGroup.GROUPED
		rec["world_group"] = String(g.id)
		rec["enclave"] = true
		(g.members as Array).append(String(rec.id))
		out.append(String(rec.id))
	return out


# --- The far tick ------------------------------------------------------------------------------

## Host, main thread, after a far tick (FallenStory): members, patrols, tolls, looters, the day's
## trade and drift, the convoy, the home's fall.
static func server_after_step(m: WorldModel) -> void:
	if not is_set_up():
		return
	var g := m.group(gid())
	if g.is_empty():
		return
	_sync(m, g)
	if bool(g.get("alive", false)):
		for p: Dictionary in patrols().values():
			if EnclaveDetachment.step(p):
				_patrol_arrived(m, g, p)
		_far_tolls(m, g)
		_looters(m, g)
		_player_toll(m, g)
		_convoy(m, g)
		if m.day() != int(data().get("last_day", m.day())):
			data()["last_day"] = m.day()
			_daily(m, g)
	_check_broken(m, g)


## Members gone from the group (dead in a fight, deserted, conscripted out) leave their post or
## patrol; people the group gained (recruited, traded for) join its home post.
static func _sync(m: WorldModel, g: Dictionary) -> void:
	var keep := {}
	for pid: String in g.get("members", []):
		var rec: Dictionary = m.people.get(pid, {})
		if String(rec.get("status", "")) == "dead":
			continue
		keep[pid] = true
	g.members = (g.members as Array).filter(func(pid: String) -> bool: return keep.has(pid))
	var placed := {}
	for d: Dictionary in posts().values() + patrols().values():
		EnclaveDetachment.prune(d, keep)
		for pid: String in d.members:
			placed[pid] = true
	var home := home_post()
	if not home.is_empty() and not is_broken():
		for pid: String in keep:
			if not placed.has(pid):
				(home.members as Array).append(pid)
	for o: Dictionary in data().get("officers", []):
		o["alive"] = keep.has(String(o.id))


static func _patrol_arrived(m: WorldModel, g: Dictionary, p: Dictionary) -> void:
	for pid: String in p.members:
		var rec: Dictionary = m.people.get(pid, {})
		if not rec.is_empty():
			rec.zone = String(p.zone)
	if String(p.zone) == m.hosted:
		m.event(String(p.zone), "patrol", [String(g.id)], "an enclave patrol came into %s" % String(m.zone(String(p.zone)).get("name", p.zone)))


## Far groups in a zone the enclave holds pay a toll (a share of food, ammo and fuel) once a day,
## or are turned back (a group it hates, or a cruel raider crew): their journey ends.
static func _far_tolls(m: WorldModel, g: Dictionary) -> void:
	var held := held_zones()
	var tolled: Dictionary = data().get("tolled", {})
	for o: Dictionary in m.alive_groups():
		var oid := String(o.id)
		if oid == String(g.id) or String(o.kind) in ["lone", "enclave"] or bool(o.get("live", false)) or not held.has(String(o.zone)):
			continue
		if m.now - float(tolled.get(oid, -100.0)) < TOLL_GAP_DAYS:
			continue
		tolled[oid] = m.now
		var hated := WorldGroup.relation(g, oid) <= TURN_BACK_REL or WorldGroup.relation(o, String(g.id)) <= TURN_BACK_REL
		var defiant := float((o.get("personality", {}) as Dictionary).get("cruelty", 0.0)) >= 0.6 and String(o.kind) == "raiders"
		var zn := String(m.zone(String(o.zone)).get("name", o.zone))
		if hated or defiant:
			o.goal = {}
			o.journey = {}
			WorldGroup.change_relation(o, String(g.id), -5.0)
			m.event(String(o.zone), "turned_back", [String(g.id), oid], "the enclave turned %s back at %s" % [String(o.name), zn])
			continue
		var share := TOLL_SHARE * (2.0 if nature() == "corrupt" else 1.0)
		var paid := 0.0
		for k: String in ["food", "ammo", "fuel"]:
			var v := WorldGroup.supply(o, k) * share
			WorldGroup.add_supply(o, k, -v)
			WorldGroup.add_supply(g, k, v)
			paid += v * float(WorldTrade.SUPPLY_VALUE.get(k, 0.0))
		WorldGroup.change_relation(o, String(g.id), -2.0)
		m.event(String(o.zone), "toll", [String(g.id), oid], "%s paid the enclave's toll at %s ($%d of goods)" % [String(o.name), zn, roundi(paid)])
	data()["tolled"] = tolled


## A group foraging on the enclave's ground (a zone it holds) is shot at: a far fight, once a day.
static func _looters(m: WorldModel, g: Dictionary) -> void:
	var held := held_zones()
	var shot: Dictionary = data().get("shot", {})
	var fought := false
	for o: Dictionary in m.alive_groups().duplicate():
		var oid := String(o.id)
		var goal: Dictionary = o.get("goal", {})
		if oid == String(g.id) or String(o.kind) in ["lone", "enclave"] or bool(o.get("live", false)) or String(goal.get("kind", "")) != "forage":
			continue
		if String(goal.get("zone", "")) != String(o.zone) or not held.has(String(o.zone)) or String(o.zone) == m.hosted or not bool(g.get("alive", false)):
			continue
		if m.now - float(shot.get(oid, -100.0)) < LOOTER_GAP_DAYS:
			continue
		shot[oid] = m.now
		var won := WorldFights.resolve(m, g, o, String(goal.get("place", "")), true)
		fought = true
		o.goal = {}
		o.journey = {}
		m.event(String(o.zone), "looters_shot", [String(g.id), oid], "the enclave shot at %s for looting in %s%s" % [String(o.name),
			String(m.zone(String(o.zone)).get("name", o.zone)), "" if won else "; the looters fought them off"])
	data()["shot"] = shot
	if fought:
		_sync(m, g)


## The players at a place the enclave holds (the hosted zone, or a patrol at their settlement) get
## a toll demand, once a day; in disguise a check first; joined, broken or at war, none.
static func _player_toll(m: WorldModel, g: Dictionary) -> void:
	if is_joined() or is_broken() or m.hosted == "" or not pending_tolls().is_empty():
		return
	var held := held_zones()
	var at_settlement := Settlement.exists() and held.has(Settlement.zone())
	if not held.has(m.hosted) and not at_settlement:
		return
	if m.now - float(data().get("player_tolled", -100.0)) < TOLL_GAP_DAYS or WorldGroup.relation(g, "player") <= -50.0:
		return
	data()["player_tolled"] = m.now
	if is_disguised() and held.has(m.hosted):
		if server_check_disguise(null):
			return
	var zone_id := m.hosted if held.has(m.hosted) else Settlement.zone()
	server_put_toll(zone_id, String(held.get(zone_id, "")))


## A day: trade with trusted settlements; the collapsing enclave loses people.
static func _daily(m: WorldModel, g: Dictionary) -> void:
	for o: Dictionary in m.alive_groups():
		var oid := String(o.id)
		if String(o.kind) != "settlers" or WorldGroup.relation(g, oid) < TRUST or WorldGroup.relation(o, String(g.id)) < TRUST:
			continue
		if WorldGroup.supply(o, "food") < TRADE_FOOD * 2.0 or WorldGroup.supply(g, "meds") < TRADE_MEDS:
			continue
		WorldGroup.add_supply(g, "meds", -TRADE_MEDS)
		WorldGroup.add_supply(o, "meds", TRADE_MEDS)
		var fuel := minf(TRADE_FUEL, WorldGroup.supply(g, "fuel"))
		WorldGroup.add_supply(g, "fuel", -fuel)
		WorldGroup.add_supply(o, "fuel", fuel)
		WorldGroup.add_supply(o, "food", -TRADE_FOOD)
		WorldGroup.add_supply(g, "food", TRADE_FOOD)
		var text := "the enclave traded meds and fuel with %s for food" % String(o.name)
		if WorldGroup.size(o) >= PEOPLE_FROM and m.rng_for(oid, "enclave_people").randf() < PEOPLE_CHANCE:
			var pid := String(o.members[-1]) if String(o.members[-1]) != String(o.leader) else String(o.members[0])
			(o.members as Array).erase(pid)
			(g.members as Array).append(pid)
			var rec: Dictionary = m.people.get(pid, {})
			rec["world_group"] = String(g.id)
			rec["enclave"] = true
			m.note(rec, "went to the enclave in a trade")
			text += ", and %s went with them" % String(rec.get("name", "someone"))
		WorldGroup.change_relation(g, oid, 2.0)
		WorldGroup.change_relation(o, String(g.id), 2.0)
		m.event(String(o.zone), "enclave_trade", [String(g.id), oid], text)
	if nature() == "collapsing" and WorldGroup.size(g) > 3 and m.rng_for(String(g.id), "collapse").randf() < COLLAPSE_CHANCE:
		var pid := ""
		for p: Dictionary in patrols().values() + posts().values():
			for id: String in p.members:
				if not _is_officer(id) and id != String(data().get("quartermaster", "")):
					pid = id
		if pid != "":
			m._desert(g, pid)
			m.event(String(g.zone), "deserted", [String(g.id)], "another of the enclave's people walked off in the night")
			_sync(m, g)


## Whether `rec` is the enclave's quartermaster (EnclaveNode.is_quartermaster: the trade lane).
static func is_quartermaster(rec: Dictionary) -> bool:
	return bool(rec.get("enclave_quartermaster", false)) or (String(rec.get("id", "")) != "" and String(rec.get("id", "")) == String(data().get("quartermaster", "")))


static func _is_officer(pid: String) -> bool:
	for o: Dictionary in data().get("officers", []):
		if String(o.id) == pid:
			return true
	return false


## The home post down to nobody: the enclave is broken (the port taken). The evac becomes the
## players' own (WorldSim.goal_state reads goal.port_taken; the price counts as paid: the boats
## are theirs); what's left of the enclave falls back to its other post.
static func _check_broken(m: WorldModel, g: Dictionary) -> void:
	var home := home_post()
	if is_broken() or home.is_empty() or EnclaveDetachment.size(home) > 0:
		return
	data()["broken"] = true
	var z := String(home.zone)
	var goal: Dictionary = m.w.get("goal", {})
	goal["port_taken"] = true
	goal["price_paid"] = true
	var pl := WorldRegions.place(m.zone(z), String(home.place))
	if not pl.is_empty() and String(pl.get("holder", "")) == String(g.id):
		pl.holder = ""
	var fallback := {}
	for p: Dictionary in posts().values():
		if String(p.id) != String(home.id) and EnclaveDetachment.size(p) > 0:
			fallback = p
	if not fallback.is_empty() and bool(g.get("alive", false)):
		var fz := String(fallback.zone)
		var fpl := WorldRegions.place(m.zone(fz), String(fallback.place))
		if not fpl.is_empty():
			m.set_home(g, fz, fpl)
	m.event(z, "port_taken", [String(g.id), "player"], "the enclave lost %s: its home is taken, the evac is open to whoever holds it" % String(m.zone(z).get("name", z)))
	Survival._journal_line("The enclave's hold on %s is broken. The evac is ours to take." % String(m.zone(z).get("name", z)))
	FallenStory.tell_all("The enclave's hold on %s is broken" % String(m.zone(z).get("name", z)))


# --- Tolls on the players -----------------------------------------------------------------------

static func pending_tolls() -> Array:
	var out: Array = []
	var tolls: Dictionary = data().get("tolls", {})
	for k: String in WorldModel._sorted(tolls.keys()):
		if String((tolls[k] as Dictionary).get("state", "")) == "pending":
			out.append(tolls[k])
	return out


## Host: a toll on the players at `zone_id` (by the post or patrol `by`): the council's question
## at the settlement (its stores pay), else a direct ask: a journal line and a message to every
## player, answered by server_answer_toll (the UI lane's "pay" / "refuse"). Returns the toll.
static func server_put_toll(zone_id: String, by := "") -> Dictionary:
	var d := data()
	if not d.get("tolls") is Dictionary:
		d["tolls"] = {}
	var id := "t%d" % int(d.get("next_toll", 1))
	d["next_toll"] = int(d.get("next_toll", 1)) + 1
	var value := TOLL_VALUE * (2.0 if nature() == "corrupt" else 1.0)
	var t := {"id": id, "zone": zone_id, "by": by, "value": value, "state": "pending", "day": WorldSim.world_now(), "council": -1}
	(d["tolls"] as Dictionary)[id] = t
	var text := "%s's people want $%d of goods as the enclave's toll at %s" % [_officer_on_duty(), roundi(value), FallenStory.zone_name(zone_id)]
	if Settlement.exists() and zone_id == Settlement.zone():
		var pay: Array = []
		var got := 0.0
		for e: Dictionary in WorldSim._store_entries():
			if got >= value:
				break
			var unit := maxf(1.0, WorldTrade.value(String(e.id)))
			var n := mini(int(e.get("count", 1)), ceili((value - got) / unit))
			pay.append([String(e.id), n])
			got += unit * n
		var vid := Council.server_put({"kind": "demand", "text": text, "pay": pay, "from": gid()}, ["pay", "refuse"], func(result: String) -> void:
			_settle_toll(id, result == "pay", true))
		if vid >= 0:
			t["council"] = vid
			return t
	Survival._journal_line(text + " (pay or refuse).")
	FallenStory.tell_all(text + " (pay or refuse)")
	return t


static func _officer_on_duty() -> String:
	for o: Dictionary in data().get("officers", []):
		if bool(o.get("alive", true)):
			return "%s %s" % [String(o.rank), String(o.name)]
	return "The enclave"


## Host: the players answer toll `id`: "pay" (goods worth its value from `s`'s kit, food, meds and
## ammo first; refused when he hasn't enough) or "refuse" (turned back: the enclave's standing
## falls). Returns why not ("" done).
static func server_answer_toll(id: String, answer: String, s: Soldier = null) -> String:
	var t: Dictionary = (data().get("tolls", {}) as Dictionary).get(id, {})
	if t.is_empty() or String(t.get("state", "")) != "pending":
		return "No such toll"
	if answer == "pay":
		if s == null:
			var ps := FallenStory.players()
			s = ps[0] if not ps.is_empty() else null
		if s == null or s.inventory == null:
			return "Nobody to pay"
		var plan := pay_plan(s.inventory, float(t.value))
		if plan.is_empty():
			return "Not enough to pay"
		for e: Array in plan:
			for i in int(e[1]):
				s.inventory.remove_one(StringName(String(e[0])))
	_settle_toll(id, answer == "pay", false)
	return ""


## What to hand over from `inv` for `value` dollars: [[item id, count]] ([] when it isn't there).
## Food, meds and ammo first; guns, armour and packs never.
static func pay_plan(inv: Inventory, value: float) -> Array:
	var have := {}
	for c: StringName in inv.search_containers():
		for e: Dictionary in inv.containers[c]:
			have[String(e.id)] = int(have.get(String(e.id), 0)) + int(e.get("count", 1))
	var ids: Array = have.keys()
	var rank := {}
	for id: String in ids:
		var item := ItemDB.get_item(StringName(id))
		var r := 5
		if item == null or String(item.type) in ["weapon", "pistol", "armor", "chest", "backpack", "plate", "launcher"]:
			r = 99
		elif "food" in item.tags:
			r = 0
		elif "medical_supply" in item.tags or String(item.type) == "medical":
			r = 1
		elif String(item.type) == "ammo":
			r = 2
		rank[id] = r
	ids.sort_custom(func(a: String, b: String) -> bool: return int(rank[a]) < int(rank[b]) or (int(rank[a]) == int(rank[b]) and a < b))
	var out: Array = []
	var got := 0.0
	for id: String in ids:
		if got >= value or int(rank[id]) >= 99:
			break
		var unit := maxf(1.0, WorldTrade.value(id))
		var n := mini(int(have[id]), ceili((value - got) / unit))
		out.append([id, n])
		got += unit * n
	return out if got >= value else []


static func _settle_toll(id: String, paid: bool, by_council: bool) -> void:
	var t: Dictionary = (data().get("tolls", {}) as Dictionary).get(id, {})
	if t.is_empty() or String(t.get("state", "")) != "pending":
		return
	t["state"] = "paid" if paid else "refused"
	var sim := WorldSim.get_sim()
	if paid:
		if sim:
			sim.server_change_relation(gid(), 3.0, "paid the toll")
		Survival._journal_line("We paid the enclave's toll%s." % (" from the stores" if by_council else ""))
		return
	if sim:
		sim.server_change_relation(gid(), -15.0, "refused the toll")
	Survival._journal_line("We refused the enclave's toll. They told us to turn back.")
	FallenStory.tell_all("The enclave: turn back")
	FallenStory.event(String(t.get("zone", "")), "turned_back", [gid(), "player"], "the enclave turned the farm's people back at %s" % FallenStory.zone_name(String(t.get("zone", ""))))


# --- The price -----------------------------------------------------------------------------------

## The price of the evac: {"kind" (cure | convoy | loyalty | conscripts), "need", "progress",
## "paid", "text", "log"}.
static func price() -> Dictionary:
	var p: Dictionary = data().get("price", {})
	if p.is_empty():
		return {}
	var out := p.duplicate(true)
	out["text"] = price_text()
	return out


static func price_text() -> String:
	var p: Dictionary = data().get("price", {})
	var n := int(p.get("need", 1))
	match String(p.get("kind", "")):
		"cure":
			return "the cure: a dose of ARCHE's serum or someone who doesn't turn"
		"convoy":
			return "escort %s from the base to the port" % ("a convoy" if n == 1 else "%d convoys" % n)
		"loyalty":
			return "a settlement's loyalty, handed over to the enclave"
		"conscripts":
			return "%d of your best people, to serve the enclave" % n
	return ""


## Host: progress on the price (`amount` toward its need), with why; returns the progress.
static func server_progress(amount: int, why: String) -> int:
	var p: Dictionary = data().get("price", {})
	if p.is_empty() or bool(p.get("paid", false)):
		return int(p.get("progress", 0))
	p["progress"] = mini(int(p.get("need", 1)), int(p.get("progress", 0)) + amount)
	if not p.get("log") is Array:
		p["log"] = []
	(p["log"] as Array).append({"day": WorldSim.world_now(), "why": why})
	Survival._journal_line("The enclave's price: %s (%d of %d)." % [why, int(p.progress), int(p.need)])
	return int(p.progress)


## Host: hand the price over: when its progress is whole, the evac is paid for
## (WorldSim.server_set_evac_paid) — unless the evac was a lie (by nature and seed): then the
## price is gone and the journal learns it; breaking the port is the way left. Returns why not.
static func server_pay_price() -> String:
	var p: Dictionary = data().get("price", {})
	if p.is_empty():
		return "There's no enclave to pay"
	if bool(p.get("paid", false)):
		return "Already paid"
	if int(p.get("progress", 0)) < int(p.get("need", 1)):
		return "Not yet: %s (%d of %d)" % [price_text(), int(p.get("progress", 0)), int(p.get("need", 1))]
	p["paid"] = true
	if not evac_real():
		data()["betrayed"] = true
		Survival._journal_line("We paid the enclave's price. There are no boats. There never were: it was a lie to keep people coming.")
		FallenStory.tell_all("The enclave took the price. There is no evac")
		return ""
	var sim := WorldSim.get_sim()
	if sim:
		sim.server_set_evac_paid(true)
		sim.server_change_relation(gid(), 20.0, "paid the price")
	Survival._journal_line("We paid the enclave's price. They say there's a place for us on the evac.")
	FallenStory.tell_all("The enclave's price is paid: the evac will take you")
	return ""


## Host: something handed over toward a "cure" price: "serum" (a dose from `s`) or "immune"
## (`pid`, an immune companion, settler or found person who goes to the enclave). Returns why not.
static func server_deliver(what: String, s: Soldier = null, pid := "") -> String:
	var p: Dictionary = data().get("price", {})
	if String(p.get("kind", "")) != "cure":
		return "They aren't asking for that"
	match what:
		"serum":
			if not FallenStory.take_one(s, "serum"):
				return "No serum to give"
			server_progress(1, "a dose of serum handed over")
			return ""
		"immune":
			var rec: Dictionary = WorldSim.people().get(pid, {})
			if rec.is_empty() or not bool(rec.get("immune", false)):
				return "They need someone who doesn't turn"
			_take_person(rec, "given to the enclave for the cure")
			server_progress(1, "%s handed to the enclave" % String(rec.get("name", "someone")))
			return ""
	return "They aren't asking for that"


## Host: `pids` (companions or settlers) conscripted toward a "conscripts" price; their friends
## take it hard. Returns why not.
static func server_conscript(pids: Array) -> String:
	var p: Dictionary = data().get("price", {})
	if String(p.get("kind", "")) != "conscripts":
		return "They aren't asking for people"
	var n := 0
	for pid: String in pids:
		var rec: Dictionary = WorldSim.people().get(pid, {})
		if rec.is_empty() or not String(rec.get("status", "")) in ["companion", "settler"]:
			continue
		_take_person(rec, "conscripted by the enclave")
		for other: Dictionary in WorldSim.people().values():
			if String(other.get("status", "")) in ["companion", "settler"] and SurvivorPerson.relation(other, pid) > 20.0:
				Moods.add(other, "paid_in_people")
		n += 1
	if n == 0:
		return "Nobody to send"
	server_progress(n, "%d of ours conscripted" % n)
	return ""


## A person (companion, settler or found) goes to the enclave: into its group and home post.
static func _take_person(rec: Dictionary, why: String) -> void:
	var pid := String(rec.get("id", ""))
	rec["status"] = WorldGroup.GROUPED
	rec["world_group"] = gid()
	rec["enclave"] = true
	rec["zone"] = home_zone()
	SurvivorPerson.note(rec, why)
	var the_gid := gid()
	FallenStory.world_do(func(w: Dictionary) -> void:
		var g: Dictionary = (w.get("groups", {}) as Dictionary).get(the_gid, {})
		if not g.is_empty() and not pid in (g.members as Array):
			(g.members as Array).append(pid))
	var post := home_post()
	if not post.is_empty() and not pid in (post.members as Array):
		(post.members as Array).append(pid)


## Host: a convoy from the base to the port starts (a "convoy" price, or an escort task once
## joined): it travels on the far tick, a zone a TRAVEL_TICKS; a zone with a horde or raiders
## where none of the players is (unescorted) risks it. It counts toward the price when the players
## were with it for a tick at least. Returns why not.
static func server_start_convoy() -> String:
	var p: Dictionary = data().get("price", {})
	if String(p.get("kind", "")) != "convoy" and not is_joined():
		return "They aren't asking for a convoy"
	if String((data().get("convoy", {}) as Dictionary).get("state", "")) == "moving":
		return "A convoy is already on the road"
	var zones: Dictionary = WorldSim.section().get("zones", {})
	var from := String((posts().get("base", {}) as Dictionary).get("zone", ""))
	var to := String((posts().get("port", {}) as Dictionary).get("zone", ""))
	if from == "" or to == "":
		to = home_zone()
		var links: Array = (zones.get(to, {}) as Dictionary).get("links", [])
		from = String(links[0]) if not links.is_empty() else to
	var route := WorldRegions.path(zones, from, to)
	if route.is_empty():
		route = [to]
	data()["convoy"] = {"state": "moving", "route": route, "at": 0, "progress": 0.0, "zone": String(route[0]), "escorted": 0}
	Survival._journal_line("An enclave convoy leaves %s for %s; it wants an escort." % [FallenStory.zone_name(String(route[0])), FallenStory.zone_name(to)])
	return ""


static func _convoy(m: WorldModel, g: Dictionary) -> void:
	var c: Dictionary = data().get("convoy", {})
	if String(c.get("state", "")) != "moving":
		return
	if String(c.zone) == m.hosted:
		c["escorted"] = int(c.get("escorted", 0)) + 1
	var route: Array = c.route
	if int(c.at) >= route.size() - 1:
		c["state"] = "arrived"
		m.event(String(c.zone), "convoy", [String(g.id)], "an enclave convoy reached %s" % String(m.zone(String(c.zone)).get("name", c.zone)))
		if String((data().get("price", {}) as Dictionary).get("kind", "")) == "convoy" and int(c.get("escorted", 0)) > 0:
			server_progress(1, "a convoy escorted to the port")
		if is_joined():
			_task_done("escort")
		return
	c["progress"] = float(c.get("progress", 0.0)) + 1.0 / EnclaveDetachment.TICKS_A_ZONE
	if float(c.progress) < 1.0:
		return
	c["progress"] = 0.0
	c["at"] = int(c.at) + 1
	c["zone"] = String(route[int(c.at)])
	var zd := m.zone(String(c.zone))
	var risky := not (zd.get("horde", {}) as Dictionary).is_empty()
	for o: Dictionary in m.groups_in_zone(String(c.zone)):
		risky = risky or String(o.kind) == "raiders"
	if risky and String(c.zone) != m.hosted and _roll(m.rng_for("convoy", str(c.at))) < CONVOY_RISK:
		c["state"] = "lost"
		m.event(String(c.zone), "convoy", [String(g.id)], "an enclave convoy was lost in %s" % String(zd.get("name", c.zone)))
		Survival._journal_line("The enclave's convoy was lost in %s." % String(zd.get("name", c.zone)))


## Host: a settlement's loyalty handed to the enclave (a "loyalty" price): `group_id` a far
## settlers group friendly to the players (its standing with them falls, with the enclave rises),
## or "" for the players' own settlement (the council decides). Returns why not.
static func server_hand_over(group_id := "") -> String:
	var p: Dictionary = data().get("price", {})
	if String(p.get("kind", "")) != "loyalty":
		return "They aren't asking for that"
	if group_id == "":
		if not Settlement.exists():
			return "There's no settlement to hand over"
		var vid := Council.server_put({"kind": "custom", "text": "hand the farm's loyalty to the enclave (its tolls, its orders) for the evac"}, ["yes", "no"], func(result: String) -> void:
			if result == "yes":
				data()["settlement_loyal"] = true
				server_progress(1, "the farm's loyalty handed to the enclave"))
		return "" if vid >= 0 else "The council can't sit"
	var o := WorldSim.group(group_id)
	if o.is_empty() or String(o.get("kind", "")) != "settlers" or WorldGroup.relation(o, "player") < 30.0:
		return "They don't trust you enough to follow you"
	var the_gid := gid()
	FallenStory.world_do(func(w: Dictionary) -> void:
		var og: Dictionary = (w.get("groups", {}) as Dictionary).get(group_id, {})
		var eg: Dictionary = (w.get("groups", {}) as Dictionary).get(the_gid, {})
		if og.is_empty() or eg.is_empty():
			return
		og["loyal_to"] = the_gid
		WorldGroup.change_relation(og, "player", -40.0)
		WorldGroup.change_relation(og, the_gid, 50.0)
		WorldGroup.change_relation(eg, group_id, 50.0))
	server_progress(1, "%s handed to the enclave" % String(o.get("name", "a settlement")))
	return ""


# --- Infiltration --------------------------------------------------------------------------------

static func is_disguised() -> bool:
	return not (data().get("disguise", {}) as Dictionary).is_empty()


## Host: `s` puts on the enclave's uniform with a forged pass (both carried): while it's worn the
## enclave's standing with the players reads DISGUISE_REL (the stance its people take, live or
## far: friendly), until a check fails. Returns why not.
static func server_wear_disguise(s: Soldier) -> String:
	if not FallenStory.has_item(s, "enclave_uniform") or not FallenStory.has_item(s, "enclave_pass"):
		return "You need an enclave uniform and a pass"
	if is_broken():
		return "There's nobody left to fool"
	var dis: Dictionary = data().get("disguise", {})
	if dis.is_empty():
		dis["before"] = WorldGroup.relation(group(), "player")
	dis[Survival.profile_of(s)] = true
	data()["disguise"] = dis
	_set_player_rel(DISGUISE_REL)
	Survival._tell(s, "In the uniform, with the pass: you're one of them, until somebody looks closely")
	return ""


## Host: the disguise comes off (taken off, or seen through): the enclave's standing back to what
## it was, less when it was seen through.
static func server_take_off_disguise(blown := false) -> void:
	var dis: Dictionary = data().get("disguise", {})
	if dis.is_empty():
		return
	var before := float(dis.get("before", 0.0))
	data()["disguise"] = {}
	_set_player_rel(before - (25.0 if blown else 0.0))
	if blown:
		Survival._journal_line("The enclave saw through our uniforms. They know our faces now.")
		FallenStory.tell_all("The enclave saw through the disguise")


## Host: a check at a post or a toll (`s` the one looked at, or null): passes (true) or the
## disguise is blown (false). Harder where the hard officer is alive and dislikes you, easier
## when the frightened one likes you.
static func server_check_disguise(s: Soldier, extra := 0.0) -> bool:
	if not is_disguised():
		return false
	if s != null and (not FallenStory.has_item(s, "enclave_uniform") or not FallenStory.has_item(s, "enclave_pass")):
		server_take_off_disguise(true)
		return false
	var chance := CHECK_CHANCE + extra
	var hard := officer("hard")
	if not hard.is_empty() and bool(hard.get("alive", true)) and float(hard.get("standing", 0.0)) < 20.0:
		chance += HARD_X
	var scared := officer("frightened")
	if not scared.is_empty() and float(scared.get("standing", 0.0)) >= 30.0:
		chance -= 0.1
	var n := int(data().get("checks", 0)) + 1
	data()["checks"] = n
	if _roll(FallenStory.rng("disguise", str(n))) < chance:
		server_take_off_disguise(true)
		return false
	return true


static func _set_player_rel(v: float) -> void:
	var g := group()
	if g.is_empty():
		return
	var by := v - WorldGroup.relation(g, "player")
	var sim := WorldSim.get_sim()
	if sim:
		sim.server_change_relation(gid(), by)
	else:
		WorldGroup.change_relation(g, "player", by)


# --- Joining (call 68) ---------------------------------------------------------------------------

static func tasks() -> Array:
	return data().get("tasks", [])


## Host: the players join the enclave (`s` the one who signs; the party serves): no tolls on them,
## the enclave's standing up, every other group's down (more for its enemies); tasks given (a
## patrol, an escort, a toll on a settlement they may know) as journal lines; companions with a
## conscience take it hard and may walk (a moodlet; a desertion break); what they learn inside
## feeds ARCHE's trail. Returns why not.
static func server_join(s: Soldier = null) -> String:
	if is_joined():
		return "Already in"
	var g := group()
	if is_broken() or g.is_empty() or not bool(g.get("alive", false)):
		return "There's no enclave to join"
	data()["joined"] = true
	data()["joined_day"] = WorldSim.world_now()
	var the_gid := gid()
	var enemies := {}
	for oid: String in (g.get("relations", {}) as Dictionary):
		if oid != "player" and WorldGroup.relation(g, oid) < 0.0:
			enemies[oid] = true
	var sim := WorldSim.get_sim()
	if sim:
		sim.server_change_relation(the_gid, JOIN_REL, "the farm's people joined us")
	FallenStory.world_do(func(w: Dictionary) -> void:
		for o: Dictionary in (w.get("groups", {}) as Dictionary).values():
			var oid := String(o.id)
			if oid == the_gid or String(o.kind) in ["lone", "enclave"] or not bool(o.get("alive", false)):
				continue
			var by := JOIN_OTHERS + (JOIN_ENEMIES if enemies.has(oid) or WorldGroup.relation(o, the_gid) < 0.0 else 0.0)
			WorldGroup.change_relation(o, "player", by))
	var list: Array = []
	var p1: Dictionary = patrols().values()[0] if not patrols().is_empty() else {}
	list.append({"kind": "patrol", "text": "walk with %s from %s" % [String(p1.get("name", "a patrol")), FallenStory.zone_name(String(p1.get("zone", home_zone())))],
		"zone": String(p1.get("zone", home_zone())), "done": false})
	list.append({"kind": "escort", "text": "escort a convoy from the base to the port", "zone": String((posts().get("base", {}) as Dictionary).get("zone", home_zone())), "done": false})
	var toll_zone := ""
	var toll_name := ""
	for o: Dictionary in (WorldSim.section().get("groups", {}) as Dictionary).values():
		if String(o.get("kind", "")) == "settlers" and bool(o.get("alive", false)) and not (o.get("home", {}) as Dictionary).is_empty():
			toll_zone = String(o.zone)
			toll_name = String(o.name)
			break
	list.append({"kind": "toll", "text": "collect the toll from %s in %s" % [toll_name if toll_name != "" else "the settlers", FallenStory.zone_name(toll_zone)],
		"zone": toll_zone, "done": false})
	data()["tasks"] = list
	Survival._journal_line("We joined the enclave. Everyone else will hear of it.")
	for t: Dictionary in list:
		Survival._journal_line("Enclave task: %s." % String(t.text))
	var left: Array = []
	for rec: Dictionary in WorldSim.people().values():
		if String(rec.get("status", "")) != "companion":
			continue
		var conscience := false
		for t: String in CONSCIENCE:
			conscience = conscience or SurvivorPerson.has_trait(rec, t)
		Moods.add(rec, "served_enclave", -12.0 if conscience else -4.0, 120.0)
		if conscience and _roll(FallenStory.rng(String(rec.get("id", "")), "conscience")) < CONSCIENCE_LEAVE:
			Moods.start_break(rec, "desertion")
			rec["left_over"] = "enclave"
			left.append(String(rec.get("name", "someone")))
	if not left.is_empty():
		Survival._journal_line("%s won't serve the enclave and %s leaving." % [", ".join(left), "is" if left.size() == 1 else "are"])
	ArcheTrail.server_reveal("enclave")
	if s:
		Survival._tell(s, "You're the enclave's now: %d tasks in the journal" % list.size())
	return ""


static func _task_done(kind: String) -> void:
	for t: Dictionary in tasks():
		if String(t.kind) == kind and not bool(t.done):
			t["done"] = true
			Survival._journal_line("Enclave task done: %s." % String(t.text))
			return


## Host: a task the players did for the enclave (the live lanes call it: "patrol", "toll").
static func server_task_done(kind: String) -> void:
	_task_done(kind)


# --- Officers ------------------------------------------------------------------------------------

## The officer of `role` ({id, role, rank, name, standing, alive}), {} if none.
static func officer(role: String) -> Dictionary:
	for o: Dictionary in data().get("officers", []):
		if String(o.role) == role:
			return o
	return {}


static func officers() -> Array:
	return data().get("officers", [])


## Host: an officer's standing with the players moves (talk, favours, threats). The decent one
## at 40+ tells what he knows of ARCHE; the frightened one at 40+ slips `s` a real pass.
static func server_officer_standing(role: String, by: float, s: Soldier = null) -> float:
	var o := officer(role)
	if o.is_empty():
		return 0.0
	o["standing"] = clampf(float(o.get("standing", 0.0)) + by, -100.0, 100.0)
	if float(o.standing) >= 40.0 and not bool(o.get("gave", false)):
		match role:
			"decent":
				o["gave"] = true
				ArcheTrail.server_reveal("enclave")
				Survival._journal_line("%s %s told us what he knows about ARCHE." % [String(o.rank), String(o.name)])
			"frightened":
				if s and s.inventory and s.inventory.take(&"enclave_pass") == 1:
					o["gave"] = true
					Survival._journal_line("%s %s slipped us a pass. He wants out too." % [String(o.rank), String(o.name)])
	return float(o.standing)


## Host: a member of the enclave dies (the live layer: shot in its zone): their record dead, out
## of the group and its post; the next far tick sees whether the home has fallen.
static func server_kill(pid: String, how := "killed") -> void:
	var rec: Dictionary = WorldSim.people().get(pid, {})
	if rec.is_empty() or String(rec.get("status", "")) == "dead":
		return
	var the_gid := gid()
	FallenStory.world_do(func(w: Dictionary) -> void:
		var m := WorldModel.new(w, WorldSim.people(), WorldSim.pressure_section(), WorldSim.world_seed())
		m.now = WorldSim.world_now()
		var g: Dictionary = (w.get("groups", {}) as Dictionary).get(the_gid, {})
		if not g.is_empty() and pid in (g.members as Array):
			m.person_dies(pid, g, how, false))
	for d: Dictionary in posts().values() + patrols().values():
		(d.members as Array).erase(pid)
