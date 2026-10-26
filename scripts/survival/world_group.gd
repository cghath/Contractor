class_name WorldGroup
extends RefCounted
## A group of the living in Contractor: Fallen's world sim (docs/survival_world.md 4.1-4.2, 4.6;
## calls 20-24, 52): settlers, raiders, scavenger crews, cultists, lone survivors (a group of one:
## the companion pool, read from SurvivorsLayer's records, never moved by the sim) and the
## enclave (a placeholder for the enclave lane). The record is plain JSON-safe data in
## Survival.state()["world"]["groups"][id]; its members are SurvivorPerson records (status
## "grouped" while in a group, "captive" when taken) by id. Static helpers only.
##
## Group { id, kind, name, leader, members, home: {zone, place, pos} | {}, zone, pos: [x, z],
##   supplies: {food, water, fuel, ammo, meds, wood, scrap} (person-days / units), mounts,
##   vehicles, mood: {fear, hunger, morale} 0-1, personality: {greed, caution, cruelty, faith,
##   loyalty} 0-1 (from the leader's traits), goal: {kind, target, since, score, phase},
##   journey: {path, leg_at} | {}, relations: {group id | "player": -100..100}, memory: [{day,
##   kind, text, about}], traces, knows: {group id: {day, strength, home, scouted}}, defence,
##   captives: [person ids], missing: [{id, zone, by}], grudge, alive }

const KINDS: Array[String] = ["settlers", "raiders", "scavengers", "cultists", "lone", "enclave"]
const SUPPLY_KEYS: Array[String] = ["food", "water", "fuel", "ammo", "meds", "wood", "scrap"]
## Person status while in a group (SurvivorPerson.STATUSES' "out_there" is the lone survivor's).
const GROUPED := "grouped"
## Proposed: members a new group starts with, by kind.
const SIZE := {"settlers": Vector2i(3, 9), "raiders": Vector2i(3, 8), "scavengers": Vector2i(2, 5), "cultists": Vector2i(3, 7),
	"enclave": Vector2i(10, 16)}
## Proposed: what a new group carries, per member (person-days of food and water, units else).
const START_SUPPLIES := {
	"settlers": {"food": 4.0, "water": 3.0, "fuel": 1.0, "ammo": 2.0, "meds": 0.5, "wood": 3.0, "scrap": 1.0},
	"raiders": {"food": 2.0, "water": 2.0, "fuel": 2.0, "ammo": 6.0, "meds": 0.5, "wood": 0.5, "scrap": 2.0},
	"scavengers": {"food": 2.5, "water": 2.0, "fuel": 1.5, "ammo": 3.0, "meds": 1.0, "wood": 0.5, "scrap": 3.0},
	"cultists": {"food": 2.0, "water": 2.0, "fuel": 0.5, "ammo": 1.0, "meds": 0.3, "wood": 2.0, "scrap": 0.5},
	"lone": {"food": 1.5, "water": 1.0, "fuel": 0.0, "ammo": 1.0, "meds": 0.2, "wood": 0.0, "scrap": 0.5},
	"enclave": {"food": 10.0, "water": 10.0, "fuel": 10.0, "ammo": 20.0, "meds": 5.0, "wood": 2.0, "scrap": 5.0},
}
## Traits a new leader is given to lean their group to its kind (Proposed).
const LEADER_TRAITS := {"settlers": ["kind", "hard_worker"], "raiders": ["cruel", "hot_headed", "greedy"],
	"scavengers": ["greedy", "calm"], "cultists": ["pious", "cruel", "calm"], "lone": [], "enclave": ["calm", "loyal"]}
const NAME_FIRST := {"settlers": ["Orchard", "Millbrook", "Haven", "Hearth", "Stillwater", "Greenhill", "Fenwick", "Larkspur"],
	"raiders": ["Rust", "Jackal", "Blackjaw", "Cinder", "Hollow", "Razor", "Mange", "Grin"],
	"scavengers": ["Magpie", "Tinker", "Crow", "Junk", "Drift", "Pack", "Wren", "Burrow"],
	"cultists": ["Quiet", "Pale", "Hungry", "Last", "Gathered", "Choir", "Ashen", "Kneeling"],
	"enclave": ["Harbour", "Garrison"], "lone": [""]}
const NAME_SECOND := {"settlers": ["Farm", "Folk", "Steading", "Families", "Hold", "Commune"],
	"raiders": ["Boys", "Gang", "Crew", "Dogs", "Knives", "Riders"],
	"scavengers": ["Crew", "Pickers", "Runners", "Haulers", "Lot"],
	"cultists": ["Flock", "Choir", "Congregation", "Kin", "Gathering"],
	"enclave": ["Command", "Enclave"], "lone": [""]}
const KIND_FIGHT := {"raiders": 1.2, "enclave": 1.6, "cultists": 0.9, "settlers": 0.9, "scavengers": 1.0, "lone": 0.8}


## A new group record (no members yet: WorldModel adds them).
static func make(id: String, kind: String, rng: RandomNumberGenerator, zone: String, pos: Vector2) -> Dictionary:
	var g := {"id": id, "kind": kind, "name": name_for(kind, rng), "leader": "", "members": [], "home": {}, "zone": zone,
		"pos": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1)], "supplies": {}, "mounts": 0, "vehicles": 0,
		"mood": {"fear": 0.2, "hunger": 0.0, "morale": 0.6}, "personality": {}, "goal": {}, "journey": {}, "relations": {},
		"memory": [], "traces": [], "knows": {}, "defence": 0.0, "captives": [], "missing": [], "grudge": "", "alive": true,
		"born_tick": 0}
	for k: String in SUPPLY_KEYS:
		g.supplies[k] = 0.0
	if kind in ["scavengers", "raiders"] and rng.randf() < 0.3:
		g.vehicles = 1
	return g


static func name_for(kind: String, rng: RandomNumberGenerator) -> String:
	var a: Array = NAME_FIRST.get(kind, [""])
	var b: Array = NAME_SECOND.get(kind, [""])
	var n := "%s %s" % [String(a[rng.randi_range(0, a.size() - 1)]), String(b[rng.randi_range(0, b.size() - 1)])]
	return n.strip_edges()


## The leader's personality from their traits (0-1 each; Proposed weights) and a little of the seed.
static func personality_of(leader: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var t: Array = leader.get("traits", [])
	var p := {"greed": 0.3, "caution": 0.45, "cruelty": 0.2, "faith": 0.15, "loyalty": float(leader.get("loyalty", 40.0)) / 100.0}
	if "greedy" in t:
		p.greed += 0.4
	if "kind" in t:
		p.cruelty -= 0.2
	if "cruel" in t:
		p.cruelty += 0.45
	if "timid" in t:
		p.caution += 0.35
	if "brave" in t:
		p.caution -= 0.25
	if "calm" in t:
		p.caution += 0.1
	if "hot_headed" in t:
		p.caution -= 0.2
		p.cruelty += 0.1
	if "pious" in t:
		p.faith += 0.55
	if "loyal" in t:
		p.loyalty += 0.2
	if "fickle" in t:
		p.loyalty -= 0.2
	for k: String in p.keys():
		p[k] = snappedf(clampf(float(p[k]) + rng.randf_range(-0.06, 0.06), 0.0, 1.0), 0.001)
	return p


## The kind a leader's personality makes (call 24, 4.2): the faithful and cruel keep the dead
## holy, the cruel prey, the greedy or reckless roam, the rest settle.
static func kind_for(p: Dictionary) -> String:
	if float(p.get("faith", 0.0)) >= 0.6 and float(p.get("cruelty", 0.0)) >= 0.4:
		return "cultists"
	if float(p.get("cruelty", 0.0)) >= 0.55 or (float(p.get("greed", 0.0)) >= 0.6 and float(p.get("cruelty", 0.0)) >= 0.35):
		return "raiders"
	if float(p.get("greed", 0.0)) >= 0.55 or float(p.get("caution", 0.5)) < 0.25:
		return "scavengers"
	return "settlers"


static func size(g: Dictionary) -> int:
	return (g.get("members", []) as Array).size()


static func supply(g: Dictionary, k: String) -> float:
	return float((g.get("supplies", {}) as Dictionary).get(k, 0.0))


static func add_supply(g: Dictionary, k: String, v: float) -> void:
	var s: Dictionary = g.supplies
	s[k] = snappedf(maxf(0.0, float(s.get(k, 0.0)) + v), 0.001)


## Food and water left in days for everyone.
static func days_of_food(g: Dictionary) -> float:
	var n := maxf(1.0, float(size(g)))
	return minf(supply(g, "food"), supply(g, "water") * 1.5) / n


## What the group can bring to a fight: members x (skill x kit x morale) (4.5), skill from the
## members' courage and the group's kind, kit from ammo per member.
static func strength(g: Dictionary, people: Dictionary) -> float:
	var n := size(g)
	if n == 0:
		return 0.0
	var skill := 0.0
	for id: String in g.members:
		var rec: Dictionary = people.get(id, {})
		skill += 0.5 + float(rec.get("courage", 45.0)) / 200.0
	skill /= n
	var kit := clampf(0.4 + supply(g, "ammo") / maxf(1.0, n * 4.0), 0.4, 1.4)
	var morale := 0.5 + float((g.get("mood", {}) as Dictionary).get("morale", 0.5)) * 0.5
	return n * skill * kit * morale * float(KIND_FIGHT.get(String(g.kind), 1.0))


static func relation(g: Dictionary, other: String) -> float:
	return float((g.get("relations", {}) as Dictionary).get(other, 0.0))


static func change_relation(g: Dictionary, other: String, by: float) -> void:
	var r: Dictionary = g.relations
	r[other] = snappedf(clampf(float(r.get(other, 0.0)) + by, -100.0, 100.0), 0.01)


## The group's stance to the players by its relation (4.4): hostile, wary, neutral, friendly.
## Raiders and cultists start 20 colder; a grudge against the players is always hostile.
static func stance(g: Dictionary) -> String:
	var r := relation(g, "player")
	if String(g.kind) in ["raiders", "cultists"]:
		r -= 20.0
	if String(g.get("grudge", "")) == "player" or r <= -50.0:
		return "hostile"
	if r <= -10.0:
		return "wary"
	if r >= 30.0:
		return "friendly"
	return "neutral"


static func remember(g: Dictionary, day: float, kind: String, text: String, about := "") -> void:
	var mem: Array = g.memory
	mem.append({"day": snappedf(day, 0.01), "kind": kind, "text": text, "about": about})
	if mem.size() > 30:
		g.memory = mem.slice(-30)


static func pos2(g: Dictionary) -> Vector2:
	var p: Array = g.get("pos", [0.0, 0.0])
	return Vector2(float(p[0]), float(p[1]))
