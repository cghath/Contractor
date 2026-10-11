class_name RosterDeployment
extends RefCounted
## One deployment of the company's people (wave 4): who goes, who stands in for a recovering
## player, the respawn pool, and what happens to everyone at extraction. Pure functions on the
## roster section (Roster); the running deployment is its "deployment" entry:
## - "active": true while it runs.
## - "zone_kind": "contract" or "hot"; "zone_id": the zone's save id; "scene": the level.
## - "contract": what the economy handed over when the contract was accepted (opaque here).
## - "squad": member ids picked at the base, in pick order (the AI that may deploy).
## - "spawned": member id -> true for each one who went into the zone as an AI squadmate.
## - "fallen": member id -> true for each one killed this deployment (no slot refills with them).
## - "stand_ins": player key -> member id, for players whose main character is recovering
##   (design doc: they play an available NPC squadmate).
## - "respawns_free", "respawns_used", "respawns_bought": the players' shared respawn pool.
## - "day": the campaign day it started.
##
## The squad is 8 slots: players take theirs, the rest are filled from "squad" by role.
## Nobody else fills them: a company with three hires deploys three AI.

const CONTRACT := "contract"
const HOT := "hot"
## Respawns free per deployment (Captain): 4 in a contract zone, 8 in a hot zone; past them,
## each one is bought (BaseEconomy.respawn_price).
const FREE_RESPAWNS := {CONTRACT: 4, HOT: 8}
## Proposed: campaign days a deployment takes, by zone kind (design doc: missions advance
## the clock).
const DAYS := {CONTRACT: 1, HOT: 2}

## Outcomes for resolve().
const EXTRACTED := "extracted"
const LEFT_BEHIND := "left"
const KILLED := "dead"


static func active(data: Dictionary) -> Dictionary:
	var dep: Dictionary = data.get("deployment", {})
	return dep if dep.get("active", false) else {}


static func is_running(data: Dictionary) -> bool:
	return not active(data).is_empty()


## Starts a deployment and returns it. `squad` are the member ids picked (unavailable ones are
## dropped), `stand_ins` player key -> member id.
static func begin(data: Dictionary, squad: Array, zone_kind: String, zone_id: String, scene: String, day: int,
		contract := {}, stand_ins := {}) -> Dictionary:
	var picked: Array = []
	for mid: Variant in squad:
		var m := Roster.get_member(data, String(mid))
		if not m.is_empty() and Roster.is_available(m) and String(mid) not in picked and String(mid) not in stand_ins.values():
			picked.append(String(mid))
	var kind := zone_kind if FREE_RESPAWNS.has(zone_kind) else CONTRACT
	var dep := {"active": true, "zone_kind": kind, "zone_id": zone_id, "scene": scene, "contract": contract.duplicate(true),
		"squad": picked, "spawned": {}, "fallen": {}, "stand_ins": stand_ins.duplicate(), "day": day,
		"respawns_free": int(FREE_RESPAWNS[kind]), "respawns_used": 0, "respawns_bought": 0}
	data["deployment"] = dep
	return dep


## The default pick: one available member per squad slot's role (Roles.layout), then anyone
## available, up to `size`, leaving out `exclude`.
static func auto_squad(data: Dictionary, size: int, exclude: Array = []) -> Array[String]:
	var free: Array[String] = []
	for mid in Roster.available_ids(data):
		if mid not in exclude:
			free.append(mid)
	var out: Array[String] = []
	for slot: Dictionary in Roles.layout():
		if out.size() >= size:
			break
		for mid in free:
			if mid not in out and StringName(Roster.get_member(data, mid).role) == slot.role:
				out.append(mid)
				break
	for mid in free:
		if out.size() >= size:
			break
		if mid not in out:
			out.append(mid)
	return out


## The member who fills a squad slot of `role` now: one of the deployment's squad not in the
## zone already (`present`: member id -> true), who hasn't died, gone missing or been wounded
## out of it (stepped out hurt: Roster.is_available) this deployment. Their own role first; a medic slot takes anyone rather than stay empty, other
## slots prefer a non-medic. "" if nobody is left.
static func member_for_slot(data: Dictionary, role: StringName, present: Dictionary) -> String:
	var dep := active(data)
	if dep.is_empty():
		return ""
	var free: Array[String] = []
	for mid: Variant in dep.squad:
		var m := Roster.get_member(data, String(mid))
		if not m.is_empty() and Roster.is_available(m) and not present.has(String(mid)) and not dep.get("fallen", {}).has(String(mid)):
			free.append(String(mid))
	for mid in free:
		if StringName(Roster.get_member(data, mid).role) == role:
			return mid
	if role != Roles.MEDIC:
		for mid in free:
			if StringName(Roster.get_member(data, mid).role) != Roles.MEDIC:
				return mid
	return free[0] if not free.is_empty() else ""


static func mark_spawned(data: Dictionary, mid: String) -> void:
	var dep := active(data)
	if not dep.is_empty():
		dep.spawned[mid] = true


## A squadmate left the zone before the end (a player took their slot): they didn't deploy.
static func unmark_spawned(data: Dictionary, mid: String) -> void:
	var dep := active(data)
	if not dep.is_empty():
		dep.spawned.erase(mid)


## A squadmate was killed: they stay dead (resolve makes it so) and never refill a slot.
static func mark_fallen(data: Dictionary, mid: String) -> void:
	var dep := active(data)
	if not dep.is_empty():
		if not dep.has("fallen"):
			dep["fallen"] = {}
		dep.fallen[mid] = true


## What the next player respawn costs: 0 while free ones are left, else `price`, rising by
## `rise` of it with each one already bought (the mission brainstorm: "cost rises with each one").
static func respawn_cost(data: Dictionary, price: int, rise := 0.0) -> int:
	var dep := active(data)
	if dep.is_empty():
		return 0
	return 0 if int(dep.respawns_used) < int(dep.respawns_free) else roundi(price * (1.0 + rise * int(dep.get("respawns_bought", 0))))


## Counts a player respawn (`bought`: past the free ones). Returns the free ones left.
static func count_respawn(data: Dictionary, bought: bool) -> int:
	var dep := active(data)
	if dep.is_empty():
		return 0
	dep["respawns_used"] = int(dep.respawns_used) + 1
	if bought:
		dep["respawns_bought"] = int(dep.respawns_bought) + 1
	return maxi(int(dep.respawns_free) - int(dep.respawns_used), 0)


static func free_respawns_left(data: Dictionary) -> int:
	var dep := active(data)
	return maxi(int(dep.get("respawns_free", 0)) - int(dep.get("respawns_used", 0)), 0)


## Ends the deployment at extraction. `outcomes`:
## - "members": member id -> {"state": EXTRACTED, LEFT_BEHIND or KILLED, "gear" (their
##   Inventory.net_state now, carrier pouches and all), "wounds" (Vitals.wound_list()), "blood"
##   (Vitals.blood_fraction()), "burn" (Vitals.burn_share()), "blast_lung"
##   (Vitals.has_blast_lung()), "pos" ([x, y, z])}, for the AI squadmates who deployed.
## - "players": player key -> {"gear", "wounds", "blood", "burn", "blast_lung"}, for the
##   players there at the end.
## The dead are lost with their gear (it lies on the body in the zone); those left behind
## alive go MIA, gear and all; those who extracted come back with what they carry, a mission
## more experience, and any serious wounds as days to sit out. A player's outcome lands on
## their stand-in when they had one, else on their main character. Returns the debrief:
## {"extracted", "mia", "dead": member ids, "injured": {name: days}, "respawns_used",
## "respawns_bought", "zone_id", "zone_kind"}. The deployment is cleared.
static func resolve(data: Dictionary, outcomes: Dictionary, rng: RandomNumberGenerator, day: int) -> Dictionary:
	var dep := active(data)
	var report := {"extracted": [], "mia": [], "dead": [], "injured": {}, "respawns_used": int(dep.get("respawns_used", 0)),
		"respawns_bought": int(dep.get("respawns_bought", 0)), "zone_id": String(dep.get("zone_id", "")),
		"zone_kind": String(dep.get("zone_kind", CONTRACT))}
	var what := "a %s zone" % ("hot" if report.zone_kind == HOT else "contract")
	var member_outcomes: Dictionary = outcomes.get("members", {})
	for mid: String in member_outcomes:
		var m := Roster.get_member(data, mid)
		if m.is_empty():
			continue
		var o: Dictionary = member_outcomes[mid]
		match String(o.get("state", EXTRACTED)):
			KILLED:
				m["status"] = Roster.DEAD
				m["gear"] = {}
				m["sit_out_days"] = 0
				Roster.add_history(m, day, "Killed in action in %s" % report.zone_id)
				report.dead.append(mid)
			LEFT_BEHIND:
				m["status"] = Roster.MIA
				m["gear"] = Roster.json_safe(o.get("gear", m.gear))
				m["mia_zone"] = report.zone_id
				m["mia_pos"] = o.get("pos", [])
				Roster.add_history(m, day, "Missing in action in %s" % report.zone_id)
				report.mia.append(mid)
			_:
				_came_back(m, o, rng, day, what, report)
	var stand_ins: Dictionary = dep.get("stand_ins", {})
	var player_outcomes: Dictionary = outcomes.get("players", {})
	for key: String in player_outcomes:
		var o: Dictionary = player_outcomes[key]
		if stand_ins.has(key) and not Roster.get_member(data, String(stand_ins[key])).is_empty():
			_came_back(Roster.get_member(data, String(stand_ins[key])), o, rng, day, what, report)
		else:
			var main := Roster.main_character(data, key)
			main["gear"] = Roster.json_safe(o.get("gear", {}))
			main["missions"] = int(main.get("missions", 0)) + 1
			var hurt := Roster.assess_outcome(o)
			Roster.injure(main, hurt, day)
			if int(hurt.days) > 0:
				report.injured[String(main.name)] = int(hurt.days)
			Roster.add_history(main, day, "Came back from %s" % what)
	data["deployment"] = {}
	data["last_debrief"] = report
	return report


static func _came_back(m: Dictionary, o: Dictionary, rng: RandomNumberGenerator, day: int, what: String, report: Dictionary) -> void:
	m["gear"] = Roster.json_safe(o.get("gear", m.get("gear", {})))
	Roster.after_mission(m, rng, day, what)
	var hurt := Roster.assess_outcome(o)
	Roster.injure(m, hurt, day)
	if int(hurt.days) > 0:
		report.injured[String(m.callsign)] = int(hurt.days)
	report.extracted.append(String(m.mid))


## A recovery contract brought an MIA member home (the economy's recovery contract calls this
## through BaseHub): back on the books with whatever they had, and wounds to recover from.
static func recovered(data: Dictionary, mid: String, day: int, sit_out_days := 0) -> bool:
	var m := Roster.get_member(data, mid)
	if m.is_empty() or String(m.status) != Roster.MIA:
		return false
	m["status"] = Roster.READY
	m.erase("mia_zone")
	m.erase("mia_pos")
	m["sit_out_days"] = maxi(int(m.get("sit_out_days", 0)), sit_out_days)
	Roster.add_history(m, day, "Recovered")
	return true


## A recovery failed or lapsed: the MIA member is written off (gear and all).
static func written_off(data: Dictionary, mid: String, day: int) -> bool:
	var m := Roster.get_member(data, mid)
	if m.is_empty() or String(m.status) != Roster.MIA:
		return false
	m["status"] = Roster.DEAD
	m["gear"] = {}
	Roster.add_history(m, day, "Written off: never recovered")
	return true
