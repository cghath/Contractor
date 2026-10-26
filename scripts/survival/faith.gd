class_name Faith
extends RefCounted
## Faith and funerals in Contractor: Fallen (call 129; docs/survival_children.md section 2). No
## real religion is named: the pious keep a plain faith (a cross or a bare altar, a bench, words
## over the dead) and the cultists keep its dark mirror.
##
## - Rites at a grave: burying a known survivor (SurvivorsLayer.server_bury) with a pious
##   companion or settler about opens a rite (server_on_burial): they ask the player for a few
##   words. "Say a few words" (TalkMenu on the pious one, server_words) gives everyone present
##   "words_said" and settles the player's nerve; declining, or letting it lapse (RITE_H), gives
##   the pious "no_words".
## - The chapel: an altar piece (BuildPieces "altar", with "chapel_bench" pieces) at the
##   settlement; a pious settler's "service" job holds one service a day (service()): "service"
##   for every member, the settlement's "faith" up (the council's faith leaning: lean()), and a
##   cultist deserter's cleansing a step on; CLEANSE_SERVICES and they're cleansed (converted).
## - Small rites: grace at meals when a pious settler cooks ("grace"), a prayer before a raid the
##   council sends ("prayer": server_prayer), a vigil the night after a death (server_vigil: the
##   settlement sleeps less, the loss moodlet halves).
## - Cultists: their rites raise the zone's pressure where they're camped (a daily rite:
##   server_cult_rites); their standing with the players can't be bought (WorldGroup.change_relation
##   refuses a cultist group's rise toward the players: standing_locked).
## Every number here is Proposed.

const KEY := "faith"
## A rite stays open this many world hours, and the words are said within RITE_REACH_M of the
## grave; everyone within PRESENT_M of it is there.
const RITE_H := 6.0
const RITE_REACH_M := 12.0
const PRESENT_M := 25.0
## The words settle the speaker's nerve this much.
const WORDS_NERVE := 12.0
## A service a day; the settlement's faith (0-100) up this much a service, down a day without.
const FAITH_PER_SERVICE := 6.0
const FAITH_FADE_DAY := 1.0
## Services before a deserter is cleansed.
const CLEANSE_SERVICES := 3
## The vigil: the night's sleep store taken from everyone, and the loss moodlets' share kept.
const VIGIL_SLEEP := 20.0
const VIGIL_KEEP := 0.5
const VIGIL_HOD := 22
## A cultist camp's daily rite: pressure where they are (Survival._raise_pressure).
const CULT_RITE_PRESSURE := 8.0
const CULT_RITE_HOD := 0
## The council's take-in lean per point of faith (charity).
const FAITH_LEAN_PER := 1.0 / 50.0


static func data() -> Dictionary:
	var st := Survival.state()
	if not st.get(KEY) is Dictionary:
		st[KEY] = {"rites": [], "next": 1}
	return st[KEY]


static func is_pious(rec: Dictionary) -> bool:
	return SurvivorPerson.has_trait(rec, "pious") and not Children.is_child_rec(rec)


# --- Rites at a grave ----------------------------------------------------------------------------

## Host (SurvivorsLayer.server_bury): `dead` was buried at `at`; a pious companion (or settler
## here) asks for words. Returns the rite opened, or {}.
static func server_on_burial(layer: SurvivorsLayer, dead: Dictionary, at: Vector3) -> Dictionary:
	var pious := _pious_near(layer, at, String(dead.get("id", "")))
	if pious.is_empty():
		return {}
	var d := data()
	var id := int(d.get("next", 1))
	d["next"] = id + 1
	var rite := {"id": id, "dead": String(dead.get("id", "")), "name": String(dead.get("name", "")), "pos": [at.x, at.y, at.z],
		"zone": layer._zone(), "pious": String(pious.id), "until_h": Moods.now_h() + RITE_H, "state": "open"}
	(d.rites as Array).append(rite)
	d["rites"] = (d.rites as Array).slice(-20)
	layer.say_topic(pious, "rite_ask")
	var body := layer.body_of(String(pious.id))
	if body:
		layer._set_known(body, pious)
	return rite


## The pious companion or settler alive in the zone nearest `at` (not `but`).
static func _pious_near(layer: SurvivorsLayer, at: Vector3, but: String) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for r: Dictionary in SurvivorsLayer.records().values():
		if String(r.get("id", "")) == but or not is_pious(r) or not String(r.get("status", "")) in ["companion", "settler"] or String(r.get("zone", "")) != layer._zone():
			continue
		var b := layer.body_of(String(r.id))
		var p := b.global_position if b else SurvivorPerson.pos_of(r)
		var d := p.distance_to(at) + (0.0 if String(r.status) == "companion" else 1000.0)  # (a companion first)
		if d < bd:
			bd = d
			best = r
	return best


## The open rite `pious_id` asked for, or {}.
static func open_rite(pious_id: String) -> Dictionary:
	for r: Dictionary in data().get("rites", []):
		if String(r.get("state", "")) == "open" and String(r.get("pious", "")) == pious_id:
			return r
	return {}


static func rite_pos(rite: Dictionary) -> Vector3:
	var p: Array = rite.get("pos", [0.0, 0.0, 0.0])
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


## Host: `actor` answers the pious `pious`'s rite: `say` the words (everyone present gets
## "words_said", his nerve settles) or not (the pious takes "no_words"). Returns what's said.
static func server_words(layer: SurvivorsLayer, actor: Soldier, pious: Dictionary, say: bool) -> String:
	var rite := open_rite(String(pious.get("id", "")))
	if rite.is_empty():
		return ""
	var at := rite_pos(rite)
	if say and actor and actor.global_position.distance_to(at) > RITE_REACH_M:
		Survival._tell(actor, "Stand at the grave to say the words")
		return ""
	var body := layer.body_of(String(pious.id))
	if not say:
		_decline(pious, rite)
		var no := layer.say_topic(pious, "rite_declined")
		if body:
			layer._set_known(body, pious)
		return no
	rite["state"] = "said"
	var present := 0
	for r: Dictionary in SurvivorsLayer.records().values():
		if not String(r.get("status", "")) in ["companion", "settler"] or String(r.get("zone", "")) != layer._zone():
			continue
		var b := layer.body_of(String(r.id))
		var p := b.global_position if b else SurvivorPerson.pos_of(r)
		if r == pious or p.distance_to(at) <= PRESENT_M:
			Moods.add(r, "words_said:" + String(rite.dead))
			present += 1
	if actor:
		Nerve.settle(Survival.needs_of(actor), WORDS_NERVE)
		Survival._send_needs(actor)
	Survival._journal_line("%s said a few words over %s." % [Survival.survivor_name(actor) if actor else "We", String(rite.name)])
	rite["present"] = present
	if body:
		layer._set_known(body, pious)
	return layer.say_topic(pious, "rite_words")


static func _decline(pious: Dictionary, rite: Dictionary) -> void:
	rite["state"] = "declined"
	Moods.add(pious, "no_words:" + String(rite.get("dead", "")))
	SurvivorPerson.note(pious, "no words were said for %s" % String(rite.get("name", "")))


## Host, every world hour (SurvivorsLayer.server_hour): a rite left past RITE_H lapses (declined).
static func server_hour(layer: SurvivorsLayer) -> void:
	for r: Dictionary in data().get("rites", []):
		if String(r.get("state", "")) == "open" and Moods.now_h() >= float(r.get("until_h", 0.0)):
			var pious := SurvivorsLayer.record(String(r.get("pious", "")))
			if pious.is_empty():
				r["state"] = "declined"
				continue
			_decline(pious, r)
			var body := layer.body_of(String(pious.id)) if layer else null
			if body:
				layer._set_known(body, pious)


# --- The chapel and the service ---------------------------------------------------------------------

## Whether the settlement has a chapel (an altar piece built there).
static func has_chapel() -> bool:
	return int(Settlement.data().get("altars", 0)) > 0


## Host: the service job (SettlementJobs "service"): a pious settler with a chapel holds a service
## once a day: every member gets "service", the settlement's faith rises, deserters are cleansed a
## step. Returns whether one was held.
static func service(st: Settlement, rec: Dictionary) -> bool:
	if not is_pious(rec) or not has_chapel():
		return false
	var d := Settlement.data()
	if int(d.get("served_day", -1)) == Survival.day():
		return false
	d["served_day"] = Survival.day()
	var list: Array = st.members() if st else Settlement.settlers()
	var n := 0
	for r: Dictionary in list:
		Moods.add(r, "service")
		n += 1
		if bool(r.get("cult_deserter", false)):
			server_cleanse_step(r)
	d["faith"] = clampf(float(d.get("faith", 0.0)) + FAITH_PER_SERVICE, 0.0, 100.0)
	d["services"] = int(d.get("services", 0)) + 1
	if int(d.services) == 1:
		Survival._journal_line("%s held the first service in the chapel." % String(rec.get("name", "Someone")))
	SurvivorPerson.note(rec, "held a service for %d" % n)
	return true


## A cultist deserter one service further from the cult; at CLEANSE_SERVICES, cleansed.
static func server_cleanse_step(r: Dictionary) -> bool:
	r["cleansing"] = int(r.get("cleansing", 0)) + 1
	if int(r.cleansing) < CLEANSE_SERVICES:
		return false
	r["cult_deserter"] = false
	r["cleansed"] = true
	var t: Array = r.get("traits", [])
	if not "pious" in t:
		t.append("pious")
	r["traits"] = t
	Moods.add(r, "cleansed")
	SurvivorPerson.note(r, "cleansed of the cult")
	Survival._journal_line("%s is one of us now; the cult has no hold on %s." % [String(r.get("name", "Someone")), "her" if String(r.get("sex", "m")) == "f" else "him"])
	return true


## Host: a cultist deserter turns up at `at` (an event, tests): a person who asks to be cleansed
## (their want a place; at the settlement the services cleanse them).
static func server_add_deserter(layer: SurvivorsLayer, at: Vector3, more := {}) -> Dictionary:
	var opts := {"cult_deserter": true, "want": {"kind": "place"}, "disposition": "wary", "traits": ["timid", "gloomy"], "background": "farmer"}
	opts.merge(more, true)
	var rec := layer.server_add_person(at, opts)
	SurvivorPerson.note(rec, "ran from the cult")
	return rec


## The council's faith leaning (Council.preference): the pious and a faithful settlement lean to
## charity (take them in) and against a raid.
static func lean(rec: Dictionary, v: Dictionary, score: Dictionary) -> void:
	var opts: Array = v.options
	var yes := String(opts[0])
	var no := String(opts[1])
	var faith := float(Settlement.data().get("faith", 0.0)) * FAITH_LEAN_PER
	match String((v.question as Dictionary).get("kind", "")):
		"take_in":
			score[yes] = float(score.get(yes, 0.0)) + faith
		"raid":
			score[no] = float(score.get(no, 0.0)) + faith + (1.0 if is_pious(rec) else 0.0)


# --- Small rites -----------------------------------------------------------------------------------

## Host (Settlement.server_hour): grace at a meal when a pious settler cooks; the vigil at
## VIGIL_HOD; the faith's fade a day without a service; the cultists' rites.
static func settlement_hour(st: Settlement, hod: int) -> void:
	var settlers := Settlement.settlers()
	if hod in Settlement.MEALS and settlers.any(func(r: Dictionary) -> bool: return is_pious(r) and "cook" in Settlement.jobs_of(r) and String(r.get("activity", "")) != "sleep"):
		for r: Dictionary in settlers:
			Moods.add(r, "grace")
	if hod == VIGIL_HOD:
		server_vigil(st)
	if hod == CULT_RITE_HOD:
		var d := Settlement.data()
		if int(d.get("served_day", -1)) < Survival.day() - 1:
			d["faith"] = maxf(0.0, float(d.get("faith", 0.0)) - FAITH_FADE_DAY)
		server_cult_rites(st)


## Host: a prayer before a raid (Council: the raid voted through; Sieges can call it): led by a
## pious settler, everyone at home takes "prayer". Returns how many prayed.
static func server_prayer() -> int:
	var list := Settlement.settlers()
	if not list.any(func(r: Dictionary) -> bool: return is_pious(r)):
		return 0
	for r: Dictionary in list:
		Moods.add(r, "prayer")
	Survival._journal_line("We prayed before going out.")
	return list.size()


## Host (SurvivorsLayer._on_died): a companion or settler died; the settlement keeps a vigil the
## coming night.
static func server_on_death(rec: Dictionary, was: String) -> void:
	if not was in ["companion", "settler"] or not Settlement.exists():
		return
	var d := Settlement.data()
	var v: Dictionary = d.get("vigil", {})
	var ids: Array = v.get("for", [])
	ids.append(String(rec.get("id", "")))
	d["vigil"] = {"for": ids, "day": Survival.day(), "names": (v.get("names", []) as Array) + [String(rec.get("name", ""))]}


## Host: the vigil (VIGIL_HOD, the night after a death): everyone sits up (VIGIL_SLEEP off their
## sleep) and the loss moodlets for the dead are halved. Returns how many kept it.
static func server_vigil(_st: Settlement = null) -> int:
	var d := Settlement.data()
	var v: Dictionary = d.get("vigil", {})
	if v.is_empty():
		return 0
	d.erase("vigil")
	var n := 0
	for r: Dictionary in SurvivorsLayer.records().values():
		if not String(r.get("status", "")) in ["companion", "settler"]:
			continue
		for id: Variant in v.get("for", []):
			for base: String in ["friend_died:", "companion_died:"]:
				var cause := base + String(id)
				if Moods.has(r, cause):
					Moods.add(r, cause, Moods.value_of(r, cause) * VIGIL_KEEP)
		var needs: Dictionary = r.get("needs", {})
		if not needs.is_empty():
			needs["sleep"] = maxf(0.0, float(needs.get("sleep", 100.0)) - VIGIL_SLEEP)
		Moods.add(r, "vigil")
		n += 1
	if n > 0:
		Survival._journal_line("We sat up all night with %s." % " and ".join(PackedStringArray(v.get("names", ["the dead"]) as Array)))
	return n


# --- Cultists: the dark mirror ------------------------------------------------------------------------

## Host (daily): every cultist camp in the hosted zone holds its rite: pressure where it is.
static func server_cult_rites(st: Settlement) -> int:
	if st == null or st.level == null or not WorldSim.is_set_up():
		return 0
	var zone := String(Survival.state().get("zone", ""))
	var n := 0
	for g: Dictionary in WorldSim.groups_in(zone):
		if String(g.get("kind", "")) != "cultists" or not bool(g.get("alive", true)):
			continue
		var p := WorldGroup.pos2(g)
		Survival._raise_pressure(st.level, Vector3(p.x, 0.0, p.y), CULT_RITE_PRESSURE)
		n += 1
	return n


## Whether `g`'s standing with `other` can't rise (WorldGroup.change_relation): a cultist group
## toward the players (their standing can't be bought).
static func standing_locked(g: Dictionary, other: String, by: float) -> bool:
	return by > 0.0 and other == "player" and String(g.get("kind", "")) == "cultists"
