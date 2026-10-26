class_name Politics
extends RefCounted
## Settlement politics (docs/survival_people.md §9, survival_building.md §7; calls 28, 52, 59, 72):
## static, host, run by the settlement's hour (Settlement.server_hour) and the world sim's step.
## - Factions inside the settlement (Council.factions: a family, the pious, the old crew, the
##   newcomers) vote together (Council.server_resolve) and share moodlets: a faction low together
##   ("faction_low") or high together ("faction_high") by its members' mean mood.
## - Theft: at night a hungry, gloomy settler (hunger under THEFT_HUNGER, mood under THEFT_MOOD)
##   may steal food from the stores (THEFT_CHANCE): the stock falls, the thief has "stole", the
##   rest "theft" (and less trust in the thief), a journal line.
## - Splits (call 52): a faction whose mean mood is under SPLIT_MOOD with a leader-trait member
##   leaves the settlement as a new group in the world sim (WorldModel.group_from_people), with a
##   grudge.
## - The leader challenge's contest (Council.challenge): won by standing (the players' weight
##   against the challenger's backers), a contest of skill (a melee duel stub: skill and a roll), a
##   vote (the settlers by opinion), or by leaving; lost or left, the settlement passes to the
##   challenger: its settlers become a world group holding the place, and the builds are theirs
##   (call 72: who holds the place owns it). The players' record is kept as "settlement_lost".
## - Relations with other settlements (world groups of settlers): an alliance (relation up, they
##   warn of hordes and raiders nearby, a shared defence call brings them), a feud (relation down:
##   their raids, their refusals to trade), protection (you guard them for PROTECTION_SHARE of their
##   food each day) in the world section's "pacts".
## Every number here is Proposed.

const THEFT_HUNGER := 35.0
const THEFT_MOOD := 40.0
const THEFT_CHANCE := 0.3
const THEFT_HOUR := 2
const SPLIT_MOOD := 25.0
const SPLIT_HOUR := 12
const FACTION_LOW := 35.0
const FACTION_HIGH := 65.0
const DUEL_ROLL := 30.0
const PACT_RELATION := {"alliance": 40.0, "feud": -60.0, "protection": 20.0}
const PROTECTION_SHARE := 0.1
const PACT_HOUR := 8
const WARN_KINDS: Array[String] = ["horde", "horde_moved", "raid", "demand", "thaw"]

## Tests: a roll to use instead of randf() (-1: roll for real).
static var force_roll := -1.0


static func _roll() -> float:
	return force_roll if force_roll >= 0.0 else randf()


## Host, every world hour of the settlement (Settlement.server_hour, after the settlers' hour).
static func server_hour(st: Settlement, hod: int) -> void:
	server_share_moodlets()
	if hod == THEFT_HOUR:
		for rec: Dictionary in Settlement.settlers():
			if server_theft(st, rec):
				break
	if hod == SPLIT_HOUR:
		server_split(st)
	if hod == PACT_HOUR:
		server_pacts_day(st)


# --- Factions -------------------------------------------------------------------------------

## The faction `rec` votes with (Council.factions' name; "" for none).
static func faction_of(rec: Dictionary) -> String:
	var fs := Council.factions()
	for f: String in fs:
		if (fs[f] as Array).has(rec):
			return f
	return ""


## Host: every faction of two or more shares its mood: low together, high together.
static func server_share_moodlets() -> void:
	var fs := Council.factions()
	for f: String in fs:
		var list: Array = fs[f]
		if list.size() < 2:
			for r: Dictionary in list:
				Moods.hold(r, "faction_low", false)
				Moods.hold(r, "faction_high", false)
			continue
		var sum := 0.0
		for r: Dictionary in list:
			sum += Moods.mood(r) - Moods.value_of(r, "faction_low") - Moods.value_of(r, "faction_high")
		var mean := sum / list.size()
		for r: Dictionary in list:
			Moods.hold(r, "faction_low", mean < FACTION_LOW)
			Moods.hold(r, "faction_high", mean > FACTION_HIGH)


# --- Theft ----------------------------------------------------------------------------------

## Host: `rec`, hungry and gloomy, may steal food in the night. Returns whether they did.
static func server_theft(st: Settlement, rec: Dictionary) -> bool:
	var n: Dictionary = rec.get("needs", {})
	if float(n.get("hunger", 100.0)) >= THEFT_HUNGER or Moods.mood(rec) >= THEFT_MOOD or _roll() >= THEFT_CHANCE:
		return false
	var food := Settlement.first_stocked(func(_item: ItemData, iid: String) -> bool: return Settlement.category_of(iid) == "food")
	if food == "":
		return false
	var got := Settlement.server_take(food, 2)
	if got.is_empty():
		return false
	var kit: Array = rec.get("kit", [])
	for e: Dictionary in got:
		kit.append({"id": String(e.id), "count": int(e.count)})
	rec["kit"] = kit
	Moods.add(rec, "stole")
	for o: Dictionary in Settlement.settlers():
		if o != rec:
			Moods.add(o, "theft")
	var d := Settlement.data()
	d["thefts"] = int(d.get("thefts", 0)) + 1
	SurvivorPerson.note(rec, "took food from the stores in the night")
	Survival._journal_line("Food went missing from the stores in the night.")
	return true


# --- Splits -----------------------------------------------------------------------------------

## Host: a faction at the end of its rope with someone to lead it walks out as a new world group.
## Returns the new group's id ("" none).
static func server_split(_st: Settlement) -> String:
	var fs := Council.factions()
	for f: String in fs:
		if f.begins_with("alone:"):
			continue
		var list: Array = fs[f]
		if list.size() < 2 or list.size() >= Settlement.settlers().size():
			continue
		var sum := 0.0
		var leader: Dictionary = {}
		for r: Dictionary in list:
			sum += Moods.mood(r)
			if Council.rec_traits(r) > 0 and (leader.is_empty() or Council.rec_traits(r) > Council.rec_traits(leader)):
				leader = r
		if sum / list.size() >= SPLIT_MOOD or leader.is_empty():
			continue
		return server_leave(list, String(leader.id), "%s and %s walked out of the settlement" % [String(leader.name), "the rest of " + _faction_name(f)])
	return ""


static func _faction_name(f: String) -> String:
	if f.begins_with("family:"):
		return "the %s family" % f.trim_prefix("family:")
	return f


## Host: the settlers `list` leave the settlement as a world group led by `leader_id`. Returns its id.
static func server_leave(list: Array, leader_id: String, why: String, kind := "settlers", home := false) -> String:
	var pids: Array = []
	var layer: SurvivorsLayer = null
	var st := WorkOrders._st()
	if st and st.level:
		layer = SurvivorsLayer.find(st.level)
	for r: Dictionary in list:
		pids.append(String(r.id))
		if layer:
			layer.server_settler_body(r, false)
	var at := Settlement.pos()
	var zone := Settlement.zone()
	var gid := "gs_%s_%d" % [leader_id, Survival.day()]
	var h: Dictionary = {"zone": zone, "place": "settlement", "pos": [at.x, at.z]} if home else {}
	var fn := func(w: Dictionary) -> void:
		var m := WorldModel.new(w, WorldSim.people(), WorldSim.pressure_section(), WorldSim.world_seed())
		m.now = WorldSim.world_now()
		m.group_from_people(gid, kind, zone, Vector2(at.x + (0.0 if home else 80.0), at.z), pids, leader_id, why, h)
	var sim := WorldSim.get_sim()
	if sim:
		sim.mutate(fn)
	else:
		fn.call(WorldSim.section())
	Survival._journal_line(why[0].to_upper() + why.substr(1) + ".")
	return gid


# --- The leader challenge's contest ------------------------------------------------------------

## Host: the open challenge (Council.challenge) decided by `how`: "standing", "duel", "vote" or
## "leave", for the player `profile` (his `fighter` for the duel). Returns "kept", "lost" or "?".
static func server_contest(how: String, profile: String, fighter: Soldier = null) -> String:
	var ch := Council.challenge()
	if ch.is_empty() or String(ch.get("state", "open")) != "open":
		return "?"
	var by := SurvivorsLayer.record(String(ch.get("by", "")))
	if by.is_empty():
		return "?"
	var st := WorkOrders._st()
	var won := false
	match how:
		"standing":
			won = Council.player_weight(st, profile) >= backing(by)
		"duel":
			var mine := float(Rpg.level(fighter, "melee") if fighter else 1) * 10.0 + _roll() * DUEL_ROLL
			var theirs := float(by.get("courage", 50.0)) / 5.0 + float(Council.rec_traits(by)) * 5.0 + (1.0 - _roll()) * DUEL_ROLL
			won = mine >= theirs
		"vote":
			var yes := 0.0
			var no := 0.0
			for r: Dictionary in Settlement.settlers():
				if r == by:
					continue
				if SurvivorPerson.opinion_of(r, profile) >= SurvivorPerson.relation(r, String(by.id)):
					yes += Council.influence(r)
				else:
					no += Council.influence(r)
			won = yes >= no
		"leave":
			won = false
		_:
			return "?"
	ch["state"] = "kept" if won else "lost"
	ch["how"] = how
	if won:
		Moods.add(by, "lost_challenge")
		Survival._journal_line("%s backed down: the settlement is still ours to lead." % String(by.get("name", "The challenger")))
		return "kept"
	server_pass_settlement(by)
	return "lost"


## The challenger's backing: their influence and every settler who thinks more of them than of the players.
static func backing(by: Dictionary) -> float:
	var w := Council.influence(by)
	for r: Dictionary in Settlement.settlers():
		if r == by:
			continue
		var best := -INF
		for p: String in (r.get("opinion_of_players", {}) as Dictionary):
			best = maxf(best, SurvivorPerson.opinion_of(r, p))
		if SurvivorPerson.relation(r, String(by.id)) > (best if best > -INF else 0.0):
			w += Council.influence(r)
	return w


## Host: the settlement passes to `by` (call 72): its settlers a world group led by them, holding
## the place and the builds; the players' settlement record put away as "settlement_lost".
static func server_pass_settlement(by: Dictionary) -> String:
	var list: Array = Settlement.settlers()
	var gid := server_leave(list, String(by.id), "%s took the settlement; it's theirs now, walls and all" % String(by.get("name", "Someone")), "settlers", true)
	var d := Settlement.data().duplicate(true)
	d["held_by"] = gid
	d["lost_day"] = Survival.day()
	Survival.state()["settlement_lost"] = d
	Survival.state().erase(Settlement.KEY)
	return gid


# --- Relations with other settlements -----------------------------------------------------------

static func pacts() -> Dictionary:
	var w := WorldSim.section()
	if not w.get("pacts") is Dictionary:
		w["pacts"] = {}
	return w["pacts"]


static func pact_with(gid: String) -> String:
	return String((pacts().get(gid, {}) as Dictionary).get("kind", ""))


## Host: an alliance, a feud or protection with group `gid` ("" ends one). "" or why not.
static func server_pact(gid: String, kind: String) -> String:
	var g := WorldSim.group(gid)
	if g.is_empty() or not bool(g.get("alive", true)):
		return "?"
	if kind != "" and not PACT_RELATION.has(kind):
		return "?"
	var day := Survival.day()
	var fn := func(w: Dictionary) -> void:
		if not w.get("pacts") is Dictionary:
			w["pacts"] = {}
		var gg: Dictionary = (w.get("groups", {}) as Dictionary).get(gid, {})
		if kind == "":
			(w.pacts as Dictionary).erase(gid)
		else:
			w.pacts[gid] = {"kind": kind, "since": day}
			if not gg.is_empty():
				var rel: Dictionary = gg.get("relations", {})
				rel["player"] = PACT_RELATION[kind] if kind != "feud" else minf(float(rel.get("player", 0.0)), float(PACT_RELATION.feud))
				gg["relations"] = rel
				if kind == "feud":
					gg["grudge"] = "player"
	var sim := WorldSim.get_sim()
	if sim:
		sim.mutate(fn)
	else:
		fn.call(WorldSim.section())
	var line := String({"alliance": "We stand with %s now.", "feud": "It's a feud with %s.", "protection": "We guard %s now, for a share.", "": "We're done with %s."}[kind])
	Survival._journal_line(line % String(g.get("name", gid)))
	return ""


## Host: the shared defence call: every ally within reach comes to the settlement's zone to help.
## Returns how many answered.
static func server_call_allies() -> int:
	var zone := Settlement.zone()
	var n := 0
	var ids: Array = []
	for gid: String in pacts():
		if pact_with(gid) == "alliance" and bool(WorldSim.group(gid).get("alive", false)):
			ids.append(gid)
	var fn := func(w: Dictionary) -> void:
		for gid: String in ids:
			var g: Dictionary = (w.get("groups", {}) as Dictionary).get(gid, {})
			if g.is_empty():
				continue
			g["goal"] = {"kind": "defend", "zone": zone, "place": "", "target": "player", "phase": "go", "work": 0, "since": int(w.get("tick", 0)), "help": true}
			g["journey"] = {}
	var sim := WorldSim.get_sim()
	if sim:
		sim.mutate(fn)
	else:
		fn.call(WorldSim.section())
	n = ids.size()
	if n > 0:
		Survival._journal_line("We called on our allies: %d coming." % n)
	return n


## Host, once a day: what each pact does: protection pays its share of food into the stores.
static func server_pacts_day(st: Settlement) -> int:
	var paid := 0
	for gid: String in pacts().keys():
		var g := WorldSim.group(gid)
		if g.is_empty() or not bool(g.get("alive", false)):
			pacts().erase(gid)
			continue
		if pact_with(gid) == "protection" and st:
			var food := WorldGroup.supply(g, "food")
			var share := floori(food * PROTECTION_SHARE)
			if share > 0:
				WorldGroup.add_supply(g, "food", -share)
				paid += st.server_put("beans_tin", share)
	if paid > 0:
		Survival._journal_line("Our share from the ones we guard came in: %d tins." % paid)
	return paid


## Main thread, after each world step: allies warn of trouble near the settlement (hordes, raiders).
static func server_after_step(m: WorldModel) -> void:
	if not Settlement.exists() or pacts().is_empty():
		return
	var home := Settlement.zone()
	var near: Array = [home] + (m.zone(home).get("links", []) as Array)
	for e: Dictionary in m.new_events:
		if not String(e.kind) in WARN_KINDS or not String(e.zone) in near:
			continue
		for gid: String in pacts():
			if pact_with(gid) != "alliance":
				continue
			var g := m.group(gid)
			if g.is_empty() or not bool(g.get("alive", false)) or not String(g.zone) in near:
				continue
			Survival._journal_line("Word from %s: %s." % [String(g.name), String(e.text)])
			break
