class_name SideJobs
extends RefCounted
## The high command squads' own jobs (Income 1; docs/income.md 1). Between or during contracts the
## host sends a standing squad (Hawk 2, Viper 3, later hero squads: any detachment) on a job an
## employer or fixer offers: escort a client, guard a site, train locals, run a supply route
## (and, from Bounties, recover a captured vehicle). The squad is away for the job's days and
## can't deploy with the company (Heroes.deploying skips it). It comes back on its own: the job is
## resolved off-screen by a risk roll that uses the squad's skill, kit, morale and men ready
## against the job's risk and the zone's danger in the living war (Income.zone_danger). Pay scales
## with the danger; a share comes up front. A job can go wrong: wounded men, a man lost, or a
## failed job (no pay beyond the advance). The squad reports on the company net and leaves a
## debrief card on the side work page (Income.report).
##
## Section "income": "offers" [offer], "jobs" [job under way], "morale" {did: 0..1}.
## An offer: {"id", "kind", "client" (faction), "from" (a fixer's name or the faction's), "zone",
## "days", "pay", "danger", "expires"}; a job: the offer plus {"did", "callsign", "start", "end",
## "advance", "quality", "trouble"} and, for a recovery, "lot". All numbers in data/income.json.

const GROUP := "side_jobs"


static func cfg() -> Dictionary:
	return Income.data().get(GROUP, {})


static func kinds() -> Array:
	return cfg().get("kinds", [])


static func kind(id: String) -> Dictionary:
	for k: Dictionary in kinds():
		if String(k.kind) == id:
			return k
	return {}


static func c(key: String, default := 0.0) -> float:
	return float(cfg().get(key, default))


# --- Squads -------------------------------------------------------------------------------

static func _roster() -> Dictionary:
	return Campaign.section(&"roster")


## The job `did` is out on ({} if none).
static func job_of(did: String, s: Dictionary = {}) -> Dictionary:
	var st := s if not s.is_empty() else Income.view()
	for j: Dictionary in st.get("jobs", []):
		if String(j.did) == did:
			return j
	return {}


static func is_away(did: String) -> bool:
	return not job_of(did).is_empty()


static func morale(did: String, s: Dictionary = {}) -> float:
	var st := s if not s.is_empty() else Income.view()
	return float((st.get("morale", {}) as Dictionary).get(did, c("morale_start", 0.7)))


## A member's kit as 0..1: what his gear is worth against a fully kitted man ("kit_full_value").
static func kit_score(m: Dictionary) -> float:
	var total := 0
	var counts := Roster.gear_counts(m.get("gear", {}))
	for id: String in counts:
		total += Prices.price_of(StringName(id)) * int(counts[id])
	return clampf(float(total) / maxf(c("kit_full_value", 9000.0), 1.0), 0.0, 1.0)


## How good squad `did` is for a job now, 0..1, and why: {"quality", "skill", "kit", "morale",
## "ready", "total"}. Skill and kit average its ready men; the leader's leadership counts a little.
static func quality(data: Dictionary, did: String, s: Dictionary = {}) -> Dictionary:
	var skill := 0.0
	var kit := 0.0
	var n := 0
	for mid in Heroes.deploy_members(data, did):
		var m := Roster.get_member(data, mid)
		skill += Roster.mean_skill(m.get("skills", {}))
		kit += kit_score(m)
		n += 1
	var st := Heroes.strength(data, did)
	skill = skill / n if n > 0 else 0.0
	kit = kit / n if n > 0 else 0.0
	var mor := morale(did, s)
	var lead := Roster.get_member(data, String(Heroes.get_detachment(data, did).get("leader", "")))
	var leadership := float(lead.get("hero", {}).get("command", {}).get("leadership", 0.5)) if not lead.is_empty() else 0.4
	var manning := float(n) / float(Heroes.TEAM_ROLES.size())
	var q := 0.35 * skill + 0.25 * kit + 0.25 * mor + 0.15 * manning + 0.1 * (leadership - 0.5)
	return {"quality": clampf(q, 0.05, 0.95), "skill": skill, "kit": kit, "morale": mor, "ready": n, "total": int(st.total)}


## Why squad `did` can't take a job now ("" if it can).
static func cant_send(data: Dictionary, did: String) -> String:
	var d := Heroes.get_detachment(data, did)
	if d.is_empty():
		return "No such squad"
	if is_away(did):
		return "%s is already out on a job" % String(d.callsign)
	if RosterDeployment.is_running(data) and not bool(d.get("home", false)):
		return "%s is deployed with the company" % String(d.callsign)
	if int(Heroes.strength(data, did).ready) < int(c("min_ready", 3)):
		return "%s has fewer than %d men fit" % [String(d.callsign), int(c("min_ready", 3))]
	return ""


# --- Offers -------------------------------------------------------------------------------

## The clients that would offer `k` now: [{"client", "from", "mult"}]: its client factions that deal
## with the company (Neutral or better, not barred from work) and the fixers at their min_rep.
static func clients_for(k: Dictionary) -> Array:
	var out: Array = []
	for f: String in k.get("clients", []):
		if f in MissionRegistry.employers() and Economy.tier(f) >= MissionRegistry.neutral_tier() and Economy.work_problem(f) == "":
			out.append({"client": f, "from": MissionRegistry.faction_name(f), "mult": 1.0})
	for fx: Dictionary in MissionRegistry.fixers():
		var f := String(fx.get("faction", ""))
		if f in k.get("clients", []) and Economy.reputation(f) >= int(fx.get("min_rep", 0)):
			out.append({"client": f, "from": String(fx.fixer), "mult": float(fx.get("pay_mult", 1.0))})
	return out


## What an offer pays at `danger`.
static func pay_for(k: Dictionary, client: String, mult: float, danger: float) -> int:
	var pay := float(k.get("base_pay", 0)) * (c("pay_floor", 0.6) + danger * c("pay_danger", 1.3)) * Economy.pay_mult(client) * mult
	return roundi(pay / 100.0) * 100


## The odds a job would run for squad `did` at `danger` ({"trouble", "loss", "fail"}, 0..1): the
## same numbers the roll uses (server_resolve), shown before the host commits.
static func odds(k: Dictionary, danger: float, q: float) -> Dictionary:
	var trouble := clampf(float(k.get("risk", 0.3)) * (c("trouble_base", 0.5) + danger) * (c("trouble_quality", 1.45) - q),
		c("trouble_min", 0.04), c("trouble_max", 0.85))
	return {"trouble": trouble, "loss": trouble * c("kia_share", 0.3), "fail": trouble * c("fail_share", 0.35)}


## Host: the board's offers move on a day: expired ones go, danger and pay follow the war, and new
## ones top it up to "board_size" from today's clients.
static func refresh_offers(day: int) -> void:
	var s := Income.state()
	var keep: Array = []
	for o: Dictionary in s.offers:
		if int(o.get("expires", 0)) < day:
			continue
		var k := kind(String(o.kind))
		o["danger"] = snappedf(Income.zone_danger(String(o.zone)), 0.01)
		if not bool(k.get("recovery", false)):
			o["pay"] = pay_for(k, String(o.client), float(o.get("mult", 1.0)), float(o.danger))
		keep.append(o)
	s["offers"] = keep
	var zones := WorldSites.war_zones()
	var r := Income.rng(day, "side_offers")
	var tries := 0
	while (s.offers as Array).filter(func(o: Dictionary) -> bool: return not bool(kind(String(o.kind)).get("recovery", false))).size() < int(c("board_size", 3)) \
			and tries < 12 and not zones.is_empty():
		tries += 1
		var pool := kinds().filter(func(k: Dictionary) -> bool: return not bool(k.get("recovery", false)))
		var k: Dictionary = pool[r.randi() % pool.size()]
		var who := clients_for(k)
		if who.is_empty():
			continue
		var cl: Dictionary = who[r.randi() % who.size()]
		var zone := String(zones[r.randi() % zones.size()])
		if (s.offers as Array).any(func(o: Dictionary) -> bool: return String(o.kind) == String(k.kind) and String(o.zone) == zone):
			continue
		var danger := snappedf(Income.zone_danger(zone), 0.01)
		(s.offers as Array).append({"id": Income.next_id("sj"), "kind": String(k.kind), "client": String(cl.client), "from": String(cl.from),
			"mult": float(cl.mult), "zone": zone, "days": int(k.days), "danger": danger, "pay": pay_for(k, String(cl.client), float(cl.mult), danger),
			"expires": day + int(c("offer_days", 4))})
	s["offers_day"] = day


static func offer(oid: String) -> Dictionary:
	for o: Dictionary in Income.view().get("offers", []):
		if String(o.id) == oid:
			return o
	return {}


# --- Host: sending and coming back --------------------------------------------------------

## Host: sends squad `did` on offer `oid`. Returns "" or why not.
static func server_send(oid: String, did: String) -> String:
	var data := _roster()
	var o := offer(oid)
	if o.is_empty():
		return "That job has gone"
	var why := cant_send(data, did)
	if why != "":
		return why
	var s := Income.state()
	var d := Heroes.get_detachment(data, did)
	var q := quality(data, did, s)
	var k := kind(String(o.kind))
	var od := odds(k, float(o.danger), float(q.quality))
	var job := o.duplicate(true)
	var today := Economy.day()
	job.merge({"did": did, "callsign": String(d.callsign), "start": today, "end": today + int(o.days),
		"advance": roundi(int(o.pay) * c("advance_share", 0.25)), "quality": snappedf(float(q.quality), 0.01), "trouble": snappedf(float(od.trouble), 0.001)}, true)
	(s.offers as Array).erase(o)
	(s.jobs as Array).append(job)
	if int(job.advance) > 0:
		Economy.add_cash(int(job.advance), "%s advance: %s, %s for %s" % [Income.LEDGER_SIDE_JOB, String(d.callsign), String(k.get("name", "")), String(o.from)])
	Contracts._notify_all("%s heads out %s in %s for %s: back on day %d" % [String(d.callsign), String(k.get("verb", "on a job")),
		RegionMap.zone_name(String(o.zone)), String(o.from), int(job.end)])
	Campaign.mark_changed(&"roster")
	Campaign.mark_changed(Income.SECTION)
	return ""


## Host: a day or more passed: morale rests, jobs due come back, the board turns over.
static func server_day(days: int) -> void:
	var s := Income.state()
	var today := Economy.day()
	var mor: Dictionary = s.morale
	for did: String in Heroes.detachments(_roster()):
		if is_away(did):
			continue
		var m := float(mor.get(did, c("morale_start", 0.7)))
		var rest := c("morale_rest_per_day", 0.02) * days
		mor[did] = snappedf(move_toward(m, c("morale_start", 0.7), rest), 0.01)
	for job: Dictionary in (s.jobs as Array).duplicate():
		if int(job.end) <= today:
			server_resolve(job)
	refresh_offers(today)


## Host: job `job` comes back: the roll, the pay, the casualties, the report. Returns the outcome
## ({"result": "clean"/"trouble"/"failed", "wounded": [mids], "kia": [mids], "paid"}).
static func server_resolve(job: Dictionary) -> Dictionary:
	var s := Income.state()
	(s.jobs as Array).erase(job)
	var data := _roster()
	var did := String(job.did)
	var k := kind(String(job.kind))
	var r := Income.rng(int(job.start), "side_job:" + String(job.id))
	var trouble := float(job.trouble)
	var out := {"result": "clean", "wounded": [], "kia": [], "paid": 0}
	var men := Heroes.deploy_members(data, did)
	men.reverse()  # the leader last: the men behind him take the hits first
	if r.randf() < trouble and not men.is_empty():
		out.result = "trouble"
		var hurt := 1 + (1 if r.randf() < trouble else 0)
		var wd: Array = cfg().get("wound_days", [3, 9])
		var kia := r.randf() < c("kia_share", 0.3)
		for mid in men:
			var m := Roster.get_member(data, mid)
			if kia:
				kia = false
				_kill(data, m, job)
				(out.kia as Array).append(mid)
			elif hurt > 0:
				hurt -= 1
				Roster.injure(m, {"days": r.randi_range(int(wd[0]), int(wd[1])), "injuries": ["hurt %s" % String(k.get("verb", "on a job"))]}, Economy.day())
				(out.wounded as Array).append(mid)
		if r.randf() < c("fail_share", 0.35):
			out.result = "failed"
	var mor: Dictionary = s.morale
	var m0 := morale(did, s)
	var rest := int(job.pay) - int(job.advance)
	var callsign := String(job.callsign)
	var where := RegionMap.zone_name(String(job.zone))
	var lines: Array = [["Advance", int(job.advance)]]
	if out.result == "failed":
		m0 += c("morale_fail", -0.1)
		var part := roundi(rest * c("fail_pay_share", 0.0))
		if part > 0:
			Economy.add_cash(part, "%s: %s, part pay (failed)" % [Income.LEDGER_SIDE_JOB, callsign])
			lines.append(["Part pay", part])
		out.paid = int(job.advance) + part
		Economy.change_reputation(String(job.client), -1, "a side job failed", false)
	else:
		m0 += c("morale_win", 0.05)
		if rest > 0:
			Economy.add_cash(rest, "%s: %s, %s for %s" % [Income.LEDGER_SIDE_JOB, callsign, String(k.get("name", "")), String(job.from)])
			lines.append(["Paid on return", rest])
		out.paid = int(job.pay)
		Economy.note_job(String(job.client))
		if int(k.get("rebel_support", 0)) != 0:
			RebelSupport.change(RebelSupport.region_of(String(job.zone)), float(k.rebel_support), "%s trained locals" % callsign)
	m0 += c("morale_kia", -0.15) * (out.kia as Array).size()
	mor[did] = snappedf(clampf(m0, 0.1, 1.0), 0.01)
	var text := ""
	match String(out.result):
		"clean":
			text = "back from %s in %s, no casualties. $%s paid." % [String(k.get("verb", "a job")), where, DebriefCalc.money(out.paid)]
		"trouble":
			text = "back from %s in %s: it got hot. %s. $%s paid." % [String(k.get("verb", "a job")), where, _casualty_words(out), DebriefCalc.money(out.paid)]
		"failed":
			text = "back from %s in %s: the job went wrong and the client won't pay. %s. Kept the $%s advance." % [String(k.get("verb", "a job")), where,
				_casualty_words(out), DebriefCalc.money(out.paid)]
	for mid: String in out.wounded:
		lines.append(["Wounded: %s" % String(Roster.get_member(data, mid).get("callsign", mid)), 0])
	for mid: String in out.kia:
		lines.append(["Killed: %s" % String(Roster.get_member(data, mid).get("callsign", mid)), 0])
	Income.report("%s, %s" % [callsign, String(k.get("name", "Side job"))], "%s %s" % [callsign, text],
		"good" if out.result == "clean" else ("bad" if out.result == "failed" or not (out.kia as Array).is_empty() else "neutral"), lines)
	for mid in Heroes.get_detachment(data, did).get("members", []):
		var m := Roster.get_member(data, String(mid))
		if not m.is_empty() and String(m.get("status", "")) != Roster.DEAD:
			Roster.add_history(m, Economy.day(), "%s in %s for %s (%s)" % [String(k.get("name", "Side job")), where, String(job.from), String(out.result)])
	Campaign.mark_changed(&"roster")
	return out


static func _casualty_words(out: Dictionary) -> String:
	var parts := PackedStringArray()
	if not (out.kia as Array).is_empty():
		parts.append("%d killed" % (out.kia as Array).size())
	if not (out.wounded as Array).is_empty():
		parts.append("%d wounded" % (out.wounded as Array).size())
	return ", ".join(parts) if not parts.is_empty() else "Nobody hurt"


## A man lost on a side job: dead, on the memorial wall with his tags (the squad brought him
## home), his family paid the death benefit.
static func _kill(data: Dictionary, m: Dictionary, job: Dictionary) -> void:
	m["status"] = Roster.DEAD
	Roster.add_history(m, Economy.day(), "Killed %s in %s" % [String(kind(String(job.kind)).get("verb", "on a side job")), RegionMap.zone_name(String(job.zone))])
	Fallen.add_to_wall(data, m, Fallen.RECOVERED, "Killed on a side job", {"zone": String(job.zone), "day": Economy.day(),
		"contract": String(kind(String(job.kind)).get("name", ""))})
	var hub := (Engine.get_main_loop() as SceneTree).root.get_node_or_null(^"BaseHub") if Engine.get_main_loop() is SceneTree else null
	if hub and hub.has_method(&"server_pay_death_benefit"):
		hub.server_pay_death_benefit(String(m.mid), "killed on a side job")
	elif not m.has("benefit_paid"):
		m["benefit_paid"] = Economy.day()
		Economy.add_cash(-Prices.operations("kia_benefit"), "Death benefit: %s (killed on a side job)" % String(m.get("callsign", "")))
