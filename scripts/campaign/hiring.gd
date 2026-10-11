class_name Hiring
extends RefCounted
## The hiring board (wave 4, design doc: "AI squadmates are recruited from a rotating hiring
## pool of contractors, each with a role, skills and wage demands, and veterans cost more;
## there is no fixed starting squad"). Pure functions on the campaign's "hiring" section:
## - "seed": the campaign's hiring seed (a new campaign picks one; tests set it).
## - "refresh": how many times the pool has been redrawn; with the seed it fixes the pool.
## - "refreshed_day": the campaign day the pool was last drawn.
## - "pool": the candidates on the board, each a Roster member-to-be plus "cid" (its id on
##   the board), "demand" (the wage they ask, per day) and "fee" (the sign-on fee).
##
## The same seed and refresh always draw the same pool, so every peer and every test agrees.

## Proposed: candidates on the board, and how often (campaign days) it's redrawn.
const POOL_SIZE := 6
const REFRESH_DAYS := 3
## Proposed: the sign-on fee is this many days of the wage they ask.
const FEE_DAYS := 5
## Proposed: how the board's experience is spread: [chance, fewest missions, most missions].
## Most are new to the work; a few are veterans (who cost more).
const EXPERIENCE := [[0.55, 0, 2], [0.33, 3, 9], [0.12, 10, 24]]
## Proposed: how often each role turns up on the board (weights).
const ROLE_WEIGHTS := {"rifleman": 4.0, "medic": 3.0, "autorifleman": 2.0, "grenadier": 2.0, "marksman": 1.5, "team_leader": 1.5}
## Proposed: a role's strong skill starts this much higher.
const ROLE_SKILL := {"medic": ["medical", 0.25], "marksman": ["aim", 0.2], "autorifleman": ["nerve", 0.12],
	"team_leader": ["nerve", 0.15], "grenadier": ["movement", 0.1], "rifleman": ["movement", 0.08]}
## Proposed: a contractor's skills on the board: a base between these, plus this much per
## mission they've done.
const SKILL_LOW := 0.25
const SKILL_HIGH := 0.5
const SKILL_PER_MISSION := 0.022
## Proposed: the wage they ask is wage_for x a haggling factor between these.
const DEMAND_LOW := 0.95
const DEMAND_HIGH := 1.2


## The pool on the board (drawn on first use).
static func pool(data: Dictionary, day: int) -> Array:
	if not data.has("pool"):
		redraw(data, day)
	return data["pool"]


## Draws a fresh pool from the seed and the refresh count.
static func redraw(data: Dictionary, day: int) -> void:
	if not data.has("seed"):
		data["seed"] = randi()
	var refresh := int(data.get("refresh", 0))
	data["pool"] = draw_pool(int(data.seed), refresh)
	data["refreshed_day"] = day


## Days passed: the board is redrawn every REFRESH_DAYS (whoever wasn't hired moves on).
## Returns whether it was.
static func refresh_if_due(data: Dictionary, day: int) -> bool:
	if not data.has("pool"):
		redraw(data, day)
		return true
	if day - int(data.get("refreshed_day", day)) < REFRESH_DAYS:
		return false
	data["refresh"] = int(data.get("refresh", 0)) + 1
	redraw(data, day)
	return true


## The candidates drawn from `seed` on its `refresh`-th draw.
static func draw_pool(seed_value: int, refresh: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, refresh])
	var out: Array = []
	for i in POOL_SIZE:
		var c := candidate(rng)
		c["cid"] = "c%d_%d" % [refresh, i]
		out.append(c)
	return out


## One contractor on the board, drawn from `rng`: name, callsign, role, skills, missions
## done (their experience), the wage they ask ("demand", also "wage") and the sign-on fee.
## The person (first name, surname, nationality, shooting hand and body, Names.person) comes
## from a second generator seeded by `rng`'s state, so the rest of the board draws as before.
static func candidate(rng: RandomNumberGenerator) -> Dictionary:
	var missions := _missions(rng)
	var role := _role(rng)
	var skills := {}
	for s in Roster.SKILLS:
		skills[s] = snappedf(clampf(rng.randf_range(SKILL_LOW, SKILL_HIGH) + SKILL_PER_MISSION * missions, 0.05, Roster.SKILL_MAX), 0.01)
	var strong: Array = ROLE_SKILL.get(role, [])
	if not strong.is_empty():
		skills[strong[0]] = snappedf(minf(float(skills[strong[0]]) + float(strong[1]), Roster.SKILL_MAX), 0.01)
	var factor := snappedf(rng.randf_range(DEMAND_LOW, DEMAND_HIGH), 0.01)
	var person := {
		"name": "%s %s" % [Roster.FIRST_NAMES[rng.randi() % Roster.FIRST_NAMES.size()], Roster.LAST_NAMES[rng.randi() % Roster.LAST_NAMES.size()]],
		"callsign": Roster.CALLSIGNS[rng.randi() % Roster.CALLSIGNS.size()],
		"role": role, "skills": skills, "missions": missions, "xp": missions * Roster.XP_PER_MISSION, "wage_factor": factor,
	}
	var who_rng := RandomNumberGenerator.new()
	who_rng.seed = hash(["person", rng.state])
	person.merge(Names.person(who_rng, &"friendly", StringName(role)), true)
	person["name"] = "%s %s" % [person.first, person.surname]
	var demand := Roster.wage_of(person)
	person["demand"] = demand
	person["wage"] = demand
	person["fee"] = demand * FEE_DAYS
	return person


static func find(data: Dictionary, cid: String, day: int) -> Dictionary:
	for c: Dictionary in pool(data, day):
		if String(c.cid) == cid:
			return c
	return {}


## Takes a candidate off the board into the roster (the caller has charged the fee) and gives
## them their role's kit as their own gear. Returns the new member id ("" if they're gone).
static func hire(data: Dictionary, roster: Dictionary, cid: String, day: int) -> String:
	var c := find(data, cid, day)
	if c.is_empty():
		return ""
	(data["pool"] as Array).erase(c)
	var person := c.duplicate(true)
	person.erase("cid")
	person["gear"] = Roster.gear_for_kit(Roles.kit(StringName(person.role)))
	return Roster.add_member(roster, person, day)


## A rookie for a player whose main character is recovering and finds nobody free (design
## doc: "if none is available, one is provided free"): drawn like a board candidate with no
## experience, joins without a fee. Returns the member id.
static func provide_free(roster: Dictionary, role: StringName, day: int, seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "free", int(roster.get("next_id", 1))])
	var person := candidate(rng)
	while int(person.missions) > 2:
		person = candidate(rng)
	person["role"] = String(role) if Roles.has(role) else String(Roles.RIFLEMAN)
	person["gear"] = Roster.gear_for_kit(Roles.kit(StringName(person.role)))
	var mid := Roster.add_member(roster, person, day)
	Roster.add_history(Roster.get_member(roster, mid), day, "Provided free while a player recovers")
	return mid


static func _missions(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	for band: Array in EXPERIENCE:
		if roll < float(band[0]):
			return rng.randi_range(int(band[1]), int(band[2]))
		roll -= float(band[0])
	return 0


static func _role(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for w: float in ROLE_WEIGHTS.values():
		total += w
	var roll := rng.randf() * total
	for role: String in ROLE_WEIGHTS:
		roll -= float(ROLE_WEIGHTS[role])
		if roll <= 0.0:
			return role
	return "rifleman"
