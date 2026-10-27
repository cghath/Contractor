class_name Heroes
extends RefCounted
## Heroes and detachments on the roster (docs/high_command.md 8, combined_arms.md 5.2). Pure
## statics on the roster section, like Roster, so the host, tests and UI share one set of rules.
##
## A detachment is a standing high command squad the company keeps: a hero (its team leader)
## and his men, with a callsign. Since v0.7.1 (the Captain, 2026-10-26) a new campaign starts
## with none: the slots stay open and the host hires one at the FOB (hire_squad, HIRE_FEE) up
## to MAX_HIRED. A hired squad is "standing": it deploys on every contract unless left at home
## and is never charged per deployment. Its members never fill the player squad's slots.
## seed_standing (Hawk 2, Viper 3 at once) is kept for tests and BaseHub.standing_squads.
##
## roster["detachments"]: id -> {"id", "callsign", "leader": mid, "members": [mids], "standing":
## bool, "formed_day", "home": bool (left at home for the next deployment)}.
## member["hero"] (the leader only): {"promoted_day", "rank": 1, "command": {"leadership",
## "tactics", "initiative"}, "detachment": id}. Lazily defaulted: an older save has none.

const STANDING := [
	{"id": "d02", "callsign": "Hawk 2"},
	{"id": "d03", "callsign": "Viper 3"},
]
## The squads the host can hire, in order (the first two are STANDING's).
const HIREABLE := [
	{"id": "d02", "callsign": "Hawk 2"},
	{"id": "d03", "callsign": "Viper 3"},
	{"id": "d04", "callsign": "Raven 4"},
	{"id": "d05", "callsign": "Cobra 5"},
]
## Sign-on for a hired squad of four (about Hiring.FEE_DAYS of their wages). Proposed.
const HIRE_FEE := 12000
## Each standing team: leader, autorifleman, medic, rifleman (Roles.layout's first team).
const TEAM_ROLES: Array[StringName] = [&"team_leader", &"autorifleman", &"medic", &"rifleman"]
## A hero's history before he joined: believable veterans (combined_arms.md 5.2: 4+ missions).
const HERO_MISSIONS := 5
const MAN_MISSIONS := 2
## Start cash rises by this many days of the standing squads' wages (5.2). Proposed.
const START_WAGE_DAYS := 14
## Extra squads by contract (5.1, question 4): rated 5 +1, hot zone +1, operation +1; cap 4 in
## operations and 3 elsewhere. The floor is two slots, filled only by squads the company hired. Proposed.
const FLOOR := 2
const MAX_HIRED := 4
const CAP := 3
const CAP_OPERATION := 4


static func detachments(data: Dictionary) -> Dictionary:
	if not data.has("detachments"):
		data["detachments"] = {}
	return data["detachments"]


static func get_detachment(data: Dictionary, did: String) -> Dictionary:
	return detachments(data).get(did, {})


## The detachment member `mid` is in, or "".
static func detachment_of(data: Dictionary, mid: String) -> String:
	for d: Dictionary in detachments(data).values():
		if mid in (d.get("members", []) as Array):
			return String(d.id)
	return ""


static func in_detachment(data: Dictionary, mid: String) -> bool:
	return detachment_of(data, mid) != ""


## Every member id in any detachment (auto_squad and the slots leave them out).
static func detachment_members(data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for d: Dictionary in detachments(data).values():
		for mid: Variant in d.get("members", []):
			out.append(String(mid))
	return out


## The two standing detachments of four at once (tests, BaseHub.standing_squads), hired from
## `rng` (Hiring.candidate) with their roles' kit, the leader a hero with history. Returns the new member ids.
static func seed_standing(data: Dictionary, day: int, rng: RandomNumberGenerator) -> Array[String]:
	var added: Array[String] = []
	for spec: Dictionary in STANDING:
		if not detachments(data).has(String(spec.id)):
			added.append_array(_form(data, spec, day, rng))
	return added


## The next squad the host can hire ({} when MAX_HIRED are on the books). A squad wiped out (no
## one left alive) frees its callsign: the next hire takes it up again (its dead keep their
## history on the roster).
static func next_hire(data: Dictionary) -> Dictionary:
	var living := 0
	for d: Dictionary in detachments(data).values():
		if int(strength(data, String(d.id)).total) > 0:
			living += 1
	if living >= MAX_HIRED:
		return {}
	for spec: Dictionary in HIREABLE:
		if not detachments(data).has(String(spec.id)) or int(strength(data, String(spec.id)).total) == 0:
			return spec
	return {}


## Hires the next squad of four (the caller has charged HIRE_FEE). Returns its id, or "".
static func hire_squad(data: Dictionary, day: int, rng: RandomNumberGenerator) -> String:
	var spec := next_hire(data)
	if spec.is_empty():
		return ""
	_form(data, spec, day, rng)
	return String(spec.id)


static func _form(data: Dictionary, spec: Dictionary, day: int, rng: RandomNumberGenerator) -> Array[String]:
	var added: Array[String] = []
	var members: Array = []
	for i in TEAM_ROLES.size():
		var person := Hiring.candidate(rng)
		person["role"] = String(TEAM_ROLES[i])
		var missions := HERO_MISSIONS + rng.randi_range(0, 3) if i == 0 else MAN_MISSIONS + rng.randi_range(0, 3)
		person["missions"] = missions
		person["xp"] = missions * Roster.XP_PER_MISSION
		if i == 0:
			for s: String in ["nerve", "aim"]:
				person.skills[s] = snappedf(clampf(float(person.skills[s]) + 0.12, 0.05, Roster.SKILL_MAX), 0.01)
		var kit := Roles.kit(StringName(person.role))
		person["gear"] = Roster.gear_for_kit(kit)
		person["issued"] = kit.map(func(pair: Array) -> Array: return [String(pair[0]), int(pair[1])])
		person.erase("fee")
		person.erase("demand")
		var mid := Roster.add_member(data, person, day)
		var m := Roster.get_member(data, mid)
		m["history"] = []
		Roster.add_history(m, day, "Joined %s as %s, %d missions behind them" % [spec.callsign, Roles.display_name(StringName(person.role)), missions])
		members.append(mid)
		added.append(mid)
	var leader := Roster.get_member(data, String(members[0]))
	leader["hero"] = {"promoted_day": day, "rank": 1, "detachment": String(spec.id),
		"command": command_skills(leader)}
	Roster.add_history(leader, day, "Leads %s" % spec.callsign)
	detachments(data)[String(spec.id)] = {"id": String(spec.id), "callsign": String(spec.callsign), "leader": String(members[0]),
		"members": members, "standing": true, "formed_day": day, "home": false}
	return added


## Leadership, tactics, initiative (0..1) from a member's nerve, experience and role.
static func command_skills(m: Dictionary) -> Dictionary:
	var nerve := float(m.get("skills", {}).get("nerve", 0.5))
	var vet := clampf(float(m.get("missions", 0)) / 20.0, 0.0, 1.0)
	var lead := 0.1 if StringName(m.get("role", "")) == &"team_leader" else 0.0
	return {"leadership": snappedf(clampf(0.35 + nerve * 0.4 + vet * 0.2 + lead, 0.1, 0.95), 0.01),
		"tactics": snappedf(clampf(0.3 + vet * 0.4 + float(m.get("skills", {}).get("aim", 0.5)) * 0.2, 0.1, 0.95), 0.01),
		"initiative": snappedf(clampf(0.3 + nerve * 0.3 + vet * 0.2, 0.1, 0.95), 0.01)}


## What the runtime uses from a hero (high_command.md 8): request timeout, report delay.
static func command_stats(hero: Dictionary) -> Dictionary:
	var c: Dictionary = hero.get("hero", {}).get("command", {"leadership": 0.5, "tactics": 0.5, "initiative": 0.5})
	var lead := float(c.get("leadership", 0.5))
	return {"request_timeout_s": lerpf(30.0, 10.0, float(c.get("initiative", 0.5))), "net_delay_s": lerpf(5.0, 2.0, lead),
		"grid_digits": 8 if lead >= 0.7 else 6, "exact_counts": lead >= 0.6}


## The standing squads' daily wages (their share of Roster.daily_wages).
static func standing_wages(data: Dictionary) -> int:
	var total := 0
	for d: Dictionary in detachments(data).values():
		if bool(d.get("standing", false)):
			for mid: Variant in d.members:
				var m := Roster.get_member(data, String(mid))
				if not m.is_empty() and String(m.get("status", "")) != Roster.DEAD:
					total += int(m.get("wage", 0))
	return total


## A detachment's men ready to deploy / all of them alive: {"ready", "total"}.
static func strength(data: Dictionary, did: String) -> Dictionary:
	var d := get_detachment(data, did)
	var ready := 0
	var total := 0
	for mid: Variant in d.get("members", []):
		var m := Roster.get_member(data, String(mid))
		if m.is_empty() or String(m.get("status", "")) == Roster.DEAD:
			continue
		total += 1
		if Roster.is_available(m):
			ready += 1
	return {"ready": ready, "total": total}


## Detachments that would go on the next deployment: not left at home, with someone ready, in
## id order, at most `max_squads`. The standing ones first.
static func deploying(data: Dictionary, max_squads := FLOOR) -> Array[String]:
	var ids: Array = detachments(data).keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var sa := bool(get_detachment(data, a).get("standing", false))
		var sb := bool(get_detachment(data, b).get("standing", false))
		return sa if sa != sb else a < b)
	var out: Array[String] = []
	for did: String in ids:
		if out.size() >= max_squads:
			break
		var d := get_detachment(data, did)
		if not bool(d.get("home", false)) and int(strength(data, did).ready) > 0 and not SideJobs.is_away(did):  # out on a side job: not here to deploy
			out.append(did)
	return out


## The ready members of `did` for a deployment, the leader first (a downed-and-recovering hero:
## the next man leads).
static func deploy_members(data: Dictionary, did: String) -> Array[String]:
	var d := get_detachment(data, did)
	var out: Array[String] = []
	for mid: Variant in d.get("members", []):
		var m := Roster.get_member(data, String(mid))
		if not m.is_empty() and Roster.is_available(m):
			out.append(String(mid))
	var lead := String(d.get("leader", ""))
	if lead in out:
		out.erase(lead)
		out.push_front(lead)
	return out


## How many high command squads a contract allows (5.1 question 4): the standing floor plus
## extras by the briefed rating (never the hidden one), a hot zone and an operation.
static func squads_max(rated: int, hot := false, operation := false) -> int:
	var n := FLOOR + (1 if rated >= 5 else 0) + (1 if hot else 0) + (1 if operation else 0)
	return mini(n, CAP_OPERATION if operation else CAP)


## Leaves detachment `did` at home (or not) for the next deployment.
static func set_home(data: Dictionary, did: String, home: bool) -> bool:
	var d := get_detachment(data, did)
	if d.is_empty():
		return false
	d["home"] = home
	return true


## Renames a detachment's callsign (editable at the FOB, 5.2). Returns the name kept.
static func rename(data: Dictionary, did: String, callsign: String) -> String:
	var d := get_detachment(data, did)
	var clean := callsign.strip_edges().left(16)
	if d.is_empty() or clean == "":
		return String(d.get("callsign", ""))
	d["callsign"] = clean
	return clean
