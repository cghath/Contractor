class_name Relationships
extends RefCounted
## Bonds between people in Contractor: Fallen (call 74; docs/survival_bonds.md): every pair who
## spend time together carries a bond (-100..100) in their records' "relations" (SurvivorPerson:
## the same field the council, grief and nerve already read), kept symmetric here. It drifts by
## the hour (never per frame): time together (more with traits that get on, less with ones that
## grate), the same shift at the settlement, danger shared in the field; and by events: a life
## saved, small arguments between people whose traits clash (the hot-headed and the calm), the
## kind comforting someone low, gifts, a brawl between enemies. Bonds read as labels: stranger,
## acquaintance, friend, close friend, rival, enemy, partner (two adult close friends with traits
## that get on, close for PARTNER_H: a moodlet, one bunk between them, a long grief and a nerve
## shake when one dies; a breakup when it sours). Families start bonded; a child grows attached to
## whoever minds them. Rivals refuse to work a shift together and split off in a vote; enemies may
## brawl and the council may vote one out. The players' bond with a person is their opinion of
## that player (SurvivorPerson.opinion_of): a high one follows into worse odds and talks you down
## any time, a low one refuses risky orders and may leave. Static: the records are plain data.
## Every number here is Proposed.

## Labels (bond lines).
const ACQUAINTED_AT := 5.0
const FRIEND_AT := 30.0
const CLOSE_AT := 60.0
const RIVAL_AT := -25.0
const ENEMY_AT := -60.0
## Drift a world hour.
const TOGETHER_H := 0.3
const SHIFT_H := 1.5
const DANGER_H := 1.0
const PLAYER_TOGETHER_H := 0.1
const CARER_H := 2.0
## Events.
const SAVED := 30.0
const SAVED_BACK := 10.0
const SAVED_PLAYER := 20.0
const SAVE_M := 3.0
const ARGUE := -8.0
const COMFORT := 6.0
const BRAWL := -15.0
const BRAWL_DAMAGE := 6.0
## Chances a world hour a pair spends together: an argument per point of friction (and a rival
## or an enemy counts more), a comfort from a kind one to someone low, a brawl between enemies.
const ARGUE_P := 0.05
const COMFORT_P := 0.04
const COMFORT_MOOD := 40.0
const BRAWL_P := 0.1
## Families (Children's "family") start here.
const FAMILY := 70.0
## Partners: close friends this many hours, both adults with no friction.
const PARTNER_H := 48.0
const PARTNER_AGE := 18
const BREAKUP_BELOW := 20.0
const PARTNER_GRIEF_NERVE := 40.0
## Gifts (the talk's Gift): the player's bond with them.
const GIFT := 12.0
const GIFT_WANTED := 8.0
## The players' bond: follow anywhere at or over FOLLOW_BOND, refuse risky orders at or under
## REFUSE_BOND, may leave (LEAVE_P an hour, mood under LEAVE_MOOD) at or under LEAVE_BOND; talk
## you down with no cooldown at or over FREE_TALK_BOND.
const FOLLOW_BOND := 60.0
const REFUSE_BOND := -30.0
const LEAVE_BOND := -50.0
const LEAVE_P := 0.1
const LEAVE_MOOD := 35.0
const FREE_TALK_BOND := 60.0
## "Settle it" (mediating a rival pair): SETTLE_BASE + SETTLE_PER x social; success lifts both to
## SETTLE_TO, a failure costs SETTLE_FAIL; once a day a pair.
const SETTLE_BASE := 0.2
const SETTLE_PER := 0.1
const SETTLE_TO := 10.0
const SETTLE_FAIL := -5.0
const SETTLE_GAP_H := 24.0
const SOCIAL_BACKGROUNDS: Array[String] = ["teacher", "nurse", "police officer", "paramedic", "shop clerk"]
## Traits that grate ([a, b, weight]) and traits that get on when both share them.
const FRICTION := [["hot_headed", "calm", 1.0], ["hot_headed", "hot_headed", 1.0], ["kind", "cruel", 1.0], ["hard_worker", "lazy", 1.0],
	["optimist", "gloomy", 0.5], ["greedy", "kind", 0.5], ["pious", "cruel", 0.5], ["loyal", "fickle", 0.5]]
const AFFINITY: Array[String] = ["kind", "calm", "optimist", "pious", "hard_worker", "loyal", "brave", "night_owl", "drinker", "smoker"]
## The council question after a brawl.
const VOTE_OUT := "vote_out"
## Tests: a roll to use instead of randf() (-1: roll for real).
static var force_roll := -1.0


static func roll() -> float:
	return force_roll if force_roll >= 0.0 else randf()


# --- The bond -----------------------------------------------------------------------------------

static func id_of(rec: Dictionary) -> String:
	return String(rec.get("id", ""))


static func bond(a: Dictionary, b: Dictionary) -> float:
	return SurvivorPerson.relation(a, id_of(b))


static func knows(a: Dictionary, b: Dictionary) -> bool:
	return (a.get("relations", {}) as Dictionary).has(id_of(b))


## Both ways by `by` (a bond is shared; the record keeps each side).
static func change(a: Dictionary, b: Dictionary, by: float) -> void:
	if a == b or id_of(a) == "" or id_of(b) == "":
		return
	SurvivorPerson.change_relation(a, id_of(b), by)
	SurvivorPerson.change_relation(b, id_of(a), by)


static func set_bond(a: Dictionary, b: Dictionary, v: float) -> void:
	SurvivorPerson.change_relation(a, id_of(b), v - bond(a, b))
	SurvivorPerson.change_relation(b, id_of(a), v - bond(b, a))


static func partner_of(rec: Dictionary) -> String:
	return String(rec.get("partner", ""))


static func are_partners(a: Dictionary, b: Dictionary) -> bool:
	return partner_of(a) != "" and partner_of(a) == id_of(b) and partner_of(b) == id_of(a)


## The label of `a`'s bond with `b`.
static func label(a: Dictionary, b: Dictionary) -> String:
	if are_partners(a, b):
		return "partner"
	if not knows(a, b):
		return "stranger"
	return label_of(bond(a, b))


static func label_of(v: float) -> String:
	if v <= ENEMY_AT:
		return "enemy"
	if v <= RIVAL_AT:
		return "rival"
	if v >= CLOSE_AT:
		return "close friend"
	if v >= FRIEND_AT:
		return "friend"
	if absf(v) >= ACQUAINTED_AT:
		return "acquaintance"
	return "stranger"


static func is_rival(a: Dictionary, b: Dictionary) -> bool:
	return minf(bond(a, b), bond(b, a)) <= RIVAL_AT and knows(a, b)


static func is_enemy(a: Dictionary, b: Dictionary) -> bool:
	return minf(bond(a, b), bond(b, a)) <= ENEMY_AT and knows(a, b)


## How much two people's traits grate (FRICTION).
static func friction(a: Dictionary, b: Dictionary) -> float:
	var f := 0.0
	for row: Array in FRICTION:
		var x := String(row[0])
		var y := String(row[1])
		if (SurvivorPerson.has_trait(a, x) and SurvivorPerson.has_trait(b, y)) or (x != y and SurvivorPerson.has_trait(a, y) and SurvivorPerson.has_trait(b, x)):
			f += float(row[2])
	return f


## How much they get on by traits they share (AFFINITY), 0.25 each, at most 1.
static func affinity(a: Dictionary, b: Dictionary) -> float:
	var n := 0.0
	for t: String in AFFINITY:
		if SurvivorPerson.has_trait(a, t) and SurvivorPerson.has_trait(b, t):
			n += 0.25
	return minf(n, 1.0)


static func adult(rec: Dictionary) -> bool:
	return not Children.is_child_rec(rec) and int(rec.get("age", 30)) >= PARTNER_AGE


static func alive_here(rec: Dictionary) -> bool:
	return String(rec.get("status", "")) in ["companion", "settler"]


static func asleep(rec: Dictionary) -> bool:
	var n: Dictionary = rec.get("needs", {})
	return String(rec.get("activity", "")) == "sleep" or (not n.is_empty() and SurvivalSleep.is_asleep(n))


# --- Hourly drift and events (host) -------------------------------------------------------------------

## One world hour of `a` and `b` together: the drift (TOGETHER_H by how they get on, SHIFT_H on
## the same shift, DANGER_H in danger) and maybe an event (argue, comfort, brawl). Returns the
## event ("" none).
static func pair_hour(a: Dictionary, b: Dictionary, shift := false, danger := false, layer: SurvivorsLayer = null) -> String:
	var g := TOGETHER_H * (1.0 + affinity(a, b) - friction(a, b))
	if shift:
		g += SHIFT_H * (1.0 - 0.5 * minf(friction(a, b), 1.0))
	if danger:
		g += DANGER_H
	if Children.is_child_rec(a) != Children.is_child_rec(b):
		g = maxf(g, 0.0)  # (a child and an adult never drift into a feud)
	change(a, b, g)
	return event(a, b, layer)


## A small event between `a` and `b` (one roll): enemies may brawl, friction and rivalry argue, the
## kind comfort one who's low.
static func event(a: Dictionary, b: Dictionary, layer: SurvivorsLayer = null) -> String:
	var r := roll()
	if Children.is_child_rec(a) or Children.is_child_rec(b):
		return ""  # (no fights with children)
	if is_enemy(a, b) and r < BRAWL_P:
		brawl(a, b, layer)
		return "brawl"
	var argue_p := ARGUE_P * (friction(a, b) + (1.0 if is_rival(a, b) else 0.0) + (1.0 if is_enemy(a, b) else 0.0))
	if argue_p > 0.0 and r < argue_p:
		argue(a, b)
		return "argue"
	for pair: Array in [[a, b], [b, a]]:
		var kind: Dictionary = pair[0]
		var low: Dictionary = pair[1]
		if SurvivorPerson.has_trait(kind, "kind") and Moods.mood(low) < COMFORT_MOOD and r < argue_p + COMFORT_P and not is_rival(a, b):
			change(kind, low, COMFORT)
			Moods.add(low, "comforted")
			SurvivorPerson.note(low, "comforted by %s" % String(kind.get("first", kind.get("name", ""))))
			return "comfort"
	return ""


static func argue(a: Dictionary, b: Dictionary) -> void:
	change(a, b, ARGUE)
	Moods.add(a, "argued")
	Moods.add(b, "argued")
	SurvivorPerson.note(a, "argued with %s" % String(b.get("first", b.get("name", ""))))
	SurvivorPerson.note(b, "argued with %s" % String(a.get("first", a.get("name", ""))))


## Two enemies come to blows: both lose a little health (their bodies hurt, bruises on the record),
## the moodlet, the bond worse; the council may vote one out (the one who's liked least).
static func brawl(a: Dictionary, b: Dictionary, layer: SurvivorsLayer = null) -> void:
	change(a, b, BRAWL)
	for r: Dictionary in [a, b]:
		Moods.add(r, "brawled")
		var w: Array = r.get("wounds", []) if r.get("wounds") is Array else []
		w.append({"kind": "bruises", "from": "brawl", "day": Survival.day(), "hp": BRAWL_DAMAGE})
		r["wounds"] = w
		r["hurt"] = float(r.get("hurt", 0.0)) + BRAWL_DAMAGE
		var body: Soldier = layer.body_of(id_of(r)) if layer else null
		if body and body.vitals.is_up():
			body.vitals.server_damage(BRAWL_DAMAGE)
	var text := "%s and %s came to blows." % [String(a.get("name", "")), String(b.get("name", ""))]
	SurvivorPerson.note(a, "fought %s" % String(b.get("name", "")))
	SurvivorPerson.note(b, "fought %s" % String(a.get("name", "")))
	Survival._journal_line(text)
	if String(a.get("status", "")) == "settler" and String(b.get("status", "")) == "settler" and Settlement.exists():
		var out := a if standing_of(a) <= standing_of(b) else b
		for v: Dictionary in Council.open_votes():
			if String((v.question as Dictionary).get("kind", "")) == VOTE_OUT:
				return
		Council.server_put({"kind": VOTE_OUT, "person": id_of(out), "text": "Send %s away after the fight?" % String(out.get("name", ""))},
			["Send them away", "Let them stay"])


## How well liked `rec` is among the settlers (the sum of their bonds).
static func standing_of(rec: Dictionary) -> float:
	var s := 0.0
	for o: Dictionary in Settlement.settlers():
		if o != rec:
			s += bond(o, rec)
	return s


## Host (Settlement.server_hour, after the work): an hour at home: every pair of settlers awake
## drifts (TOGETHER_H; SHIFT_H for the same job this hour) and maybe has an event; a child near
## whoever minds them grows attached; families start bonded (partners: server_hour).
static func settlement_hour(st: Settlement, _hod: int) -> void:
	var list := Settlement.settlers()
	var layer: SurvivorsLayer = SurvivorsLayer.find(st) if st and st.is_inside_tree() else null
	var now := floorf(Moods.now_h())
	for i in list.size():
		var a: Dictionary = list[i]
		for j in range(i + 1, list.size()):
			var b: Dictionary = list[j]
			_family(a, b)
			if asleep(a) or asleep(b):
				continue
			var shift := _working(a, now) and _working(b, now) and String(a.get("job_now", "")) == String(b.get("job_now", ""))
			pair_hour(a, b, shift, false, layer)
			_carer(a, b)
			_carer(b, a)


static func _working(rec: Dictionary, now: float) -> bool:
	return String(rec.get("activity", "")) == "work" and float(rec.get("job_h", -1.0)) == now and String(rec.get("job_now", "")) not in ["", "idle"]


## A child grows attached to `adult` minding them this hour.
static func _carer(adult_rec: Dictionary, child: Dictionary) -> void:
	if Children.is_child_rec(child) and not Children.is_child_rec(adult_rec) and String(adult_rec.get("job_now", "")) == "minding":
		change(adult_rec, child, CARER_H)
		child["carer"] = id_of(adult_rec)


## Families (Children: a shared "family") start bonded.
static func _family(a: Dictionary, b: Dictionary) -> void:
	var fa := String(a.get("family", ""))
	if fa != "" and fa == String(b.get("family", "")) and not knows(a, b):
		set_bond(a, b, FAMILY)


## Host (SurvivorsLayer.server_hour): an hour of the companions in the field: together (and in
## danger with a horde about) they drift, maybe an event; their bond with the players drifts up a
## little; one with a low bond and a low mood may leave; families and partners for everyone.
static func server_hour(layer: SurvivorsLayer, horde: bool) -> void:
	var zone := layer._zone() if layer else ""
	var comps: Array[Dictionary] = []
	var everyone: Array[Dictionary] = []
	for rec: Dictionary in SurvivorsLayer.records().values():
		if not alive_here(rec):
			continue
		everyone.append(rec)
		if String(rec.status) == "companion" and String(rec.get("zone", "")) == zone:
			comps.append(rec)
	for i in comps.size():
		for j in range(i + 1, comps.size()):
			_family(comps[i], comps[j])
			pair_hour(comps[i], comps[j], false, horde, layer)
	var profiles: Array[String] = []
	if layer and layer.level:
		for p: Soldier in MapNodes.players(layer.level):
			profiles.append(Survival.profile_of(p))
	for rec: Dictionary in comps:
		for pr: String in profiles:
			SurvivorPerson.change_opinion(rec, pr, PLAYER_TOGETHER_H)
		if player_bond(rec) <= LEAVE_BOND and Moods.mood(rec) < LEAVE_MOOD and roll() < LEAVE_P and layer:
			SurvivorPerson.note(rec, "had enough of you")
			Survival._journal_line("%s had enough of us and left." % String(rec.get("name", "")))
			layer.server_desert(rec)
	partners_hour(everyone)


## Partners: adult close friends with no friction for PARTNER_H become a couple; a couple whose
## bond falls under BREAKUP_BELOW parts; one alone in a couple (the other gone) is single again.
static func partners_hour(list: Array) -> void:
	for i in list.size():
		var a: Dictionary = list[i]
		var p := partner_of(a)
		if p != "":
			var other := SurvivorsLayer.record(p)
			if other.is_empty() or not alive_here(other) or partner_of(other) != id_of(a):
				a.erase("partner")
				Moods.hold(a, "with_partner", false)
				continue
			Moods.hold(a, "with_partner", true)
			if bond(a, other) < BREAKUP_BELOW:
				breakup(a, other)
			continue
		for j in range(i + 1, list.size()):
			var b: Dictionary = list[j]
			if partner_of(b) != "" or not adult(a) or not adult(b):
				continue
			var ch: Dictionary = a.get("close_h", {}) if a.get("close_h") is Dictionary else {}
			if bond(a, b) >= CLOSE_AT and bond(b, a) >= CLOSE_AT and friction(a, b) <= 0.0:
				ch[id_of(b)] = float(ch.get(id_of(b), 0.0)) + 1.0
				a["close_h"] = ch
				if float(ch[id_of(b)]) >= PARTNER_H:
					pair_up(a, b)
					break
			elif ch.has(id_of(b)):
				ch.erase(id_of(b))


static func pair_up(a: Dictionary, b: Dictionary) -> void:
	a["partner"] = id_of(b)
	b["partner"] = id_of(a)
	for r: Dictionary in [a, b]:
		Moods.add(r, "partnered")
		Moods.hold(r, "with_partner", true)
	SurvivorPerson.note(a, "together with %s" % String(b.get("name", "")))
	SurvivorPerson.note(b, "together with %s" % String(a.get("name", "")))
	Survival._journal_line("%s and %s are together now." % [String(a.get("first", a.get("name", ""))), String(b.get("first", b.get("name", "")))])


static func breakup(a: Dictionary, b: Dictionary) -> void:
	for r: Dictionary in [a, b]:
		r.erase("partner")
		Moods.hold(r, "with_partner", false)
		Moods.add(r, "breakup")
	Survival._journal_line("%s and %s split up." % [String(a.get("first", a.get("name", ""))), String(b.get("first", b.get("name", "")))])


## Host (SurvivorsLayer._on_died): `rec` died: their partner grieves long and is shaken.
static func server_on_death(rec: Dictionary) -> void:
	var p := partner_of(rec)
	if p == "":
		return
	var other := SurvivorsLayer.record(p)
	if other.is_empty() or partner_of(other) != id_of(rec):
		return
	other.erase("partner")
	other["widowed"] = id_of(rec)
	Moods.hold(other, "with_partner", false)
	Moods.add(other, "partner_died:" + id_of(rec))
	var n: Dictionary = other.get("needs", {})
	if not n.is_empty():
		Nerve.shake(n, "partner_died", other.get("traits", []), PARTNER_GRIEF_NERVE)
	SurvivorPerson.note(other, "lost %s, the one they loved" % String(rec.get("name", "")))


# --- Saved lives (host) -------------------------------------------------------------------------

## `saver` (a person) brought `saved` back: a jump in the bond (more from the one saved).
static func server_saved(saver: Dictionary, saved: Dictionary) -> void:
	if saver.is_empty() or saved.is_empty() or saver == saved:
		return
	SurvivorPerson.change_relation(saved, id_of(saver), SAVED)
	SurvivorPerson.change_relation(saver, id_of(saved), SAVED_BACK)
	SurvivorPerson.note(saved, "owes %s their life" % String(saver.get("name", "")))


## SurvivorsLayer._dress: a person's body down then up again with someone at their side: they
## saved them (a companion's bond, or that player's).
static func watch_body(layer: SurvivorsLayer, s: Soldier) -> void:
	if s == null or s.vitals == null:
		return
	if not s.vitals.went_down.is_connected(_on_down):
		s.vitals.went_down.connect(_on_down.bind(s))
	if not s.vitals.woke.is_connected(_on_woke):
		s.vitals.woke.connect(_on_woke.bind(layer, s))


static func _on_down(s: Soldier) -> void:
	if is_instance_valid(s):
		s.set_meta(&"bond_down", true)


static func _on_woke(layer: SurvivorsLayer, s: Soldier) -> void:
	if not is_instance_valid(s) or not is_instance_valid(layer) or not bool(s.get_meta(&"bond_down", false)):
		return
	s.remove_meta(&"bond_down")
	var saved := layer.record_of(s)
	if saved.is_empty():
		return
	var best: Soldier = null
	var lvl := layer.level
	var near: Array[Soldier] = layer.companions()
	if lvl:
		near.append_array(MapNodes.players(lvl))
	for o: Soldier in near:
		if o != s and o.vitals.is_up() and o.global_position.distance_to(s.global_position) <= SAVE_M:
			if best == null or o.global_position.distance_to(s.global_position) < best.global_position.distance_to(s.global_position):
				best = o
	if best == null:
		return
	if best.is_ai():
		server_saved(layer.record_of(best), saved)
	else:
		SurvivorPerson.change_opinion(saved, Survival.profile_of(best), SAVED_PLAYER)
		SurvivorPerson.note(saved, "owes %s their life" % Survival.survivor_name(best))


# --- The players' bond ------------------------------------------------------------------------------

## The person's bond with player `profile` (their opinion of them); "" = the best of the players'.
static func player_bond(rec: Dictionary, profile := "") -> float:
	if profile != "":
		return SurvivorPerson.opinion_of(rec, profile)
	var o: Dictionary = rec.get("opinion_of_players", {})
	if o.is_empty():
		return 0.0
	var best := -INF
	for k: String in o:
		best = maxf(best, float(o[k]))
	return best


## A companion who'd follow `profile` into worse odds (no refusal of a risky order).
static func follows_anywhere(rec: Dictionary, profile := "") -> bool:
	return player_bond(rec, profile) >= FOLLOW_BOND


## A companion whose bond is too low to take a risky order at all.
static func refuses_risky(rec: Dictionary, profile := "") -> bool:
	return player_bond(rec, profile) <= REFUSE_BOND


## Talking `profile` down costs a close companion nothing (no cooldown).
static func free_talk(rec: Dictionary, profile: String) -> bool:
	return player_bond(rec, profile) >= FREE_TALK_BOND


## A gift (the talk's Gift) of `item` from `profile`: the bond up (more for what they want).
static func on_gift(rec: Dictionary, profile: String, item: ItemData) -> float:
	var by := GIFT
	var w: Dictionary = rec.get("want", {})
	if String(w.get("kind", "")) == "item" and SurvivorPerson.matches(w, item):
		by += GIFT_WANTED
	SurvivorPerson.change_opinion(rec, profile, by)
	Moods.add(rec, "gift")
	return by


# --- Settle it (mediation) ------------------------------------------------------------------------

## `rec`'s worst rival among the living here ({} none).
static func worst_rival(rec: Dictionary) -> Dictionary:
	var worst: Dictionary = {}
	for o: Dictionary in SurvivorsLayer.records().values():
		if o == rec or not alive_here(o) or not is_rival(rec, o):
			continue
		if worst.is_empty() or bond(rec, o) < bond(rec, worst):
			worst = o
	return worst


## The social skill `s` brings to a mediation of `a` and `b`: a base 1, the People person perk 3,
## a talking background 2, and how much the two think of him (up to 2 either way).
static func social_of(s: Soldier, a: Dictionary, b: Dictionary) -> float:
	var n := 1.0
	if Rpg.has_perk(s, "people_person"):
		n += 3.0
	if String(Rpg.view(s).get("background", "")) in SOCIAL_BACKGROUNDS:
		n += 2.0
	var p := Survival.profile_of(s)
	n += clampf((SurvivorPerson.opinion_of(a, p) + SurvivorPerson.opinion_of(b, p)) / 50.0, -2.0, 2.0)
	return n


static func settle_chance(social: float) -> float:
	return clampf(SETTLE_BASE + SETTLE_PER * social, 0.05, 0.95)


## Host: "Settle it": `actor` sits `rec` down with their worst rival. Returns what's said.
static func server_mediate(actor: Soldier, rec: Dictionary) -> String:
	var other := worst_rival(rec)
	if other.is_empty():
		return "There's nobody I can't stand. Not right now."
	var key := "settle_" + id_of(other)
	if Moods.now_h() - float(rec.get(key, -1000.0)) < SETTLE_GAP_H:
		return "We've talked. Give it a day."
	rec[key] = Moods.now_h()
	var social := social_of(actor, rec, other)
	if roll() < settle_chance(social):
		for pair: Array in [[rec, other], [other, rec]]:
			var x: Dictionary = pair[0]
			var y: Dictionary = pair[1]
			SurvivorPerson.change_relation(x, id_of(y), maxf(0.0, SETTLE_TO - bond(x, y)))
			Moods.add(x, "made_peace")
		Rpg.xp(actor, "fieldcraft", 4.0)
		Survival._journal_line("%s and %s made their peace." % [String(rec.get("first", rec.get("name", ""))), String(other.get("first", other.get("name", "")))])
		return "Fine. %s and I will get on. For the place." % String(other.get("first", other.get("name", "")))
	change(rec, other, SETTLE_FAIL)
	return "No. Not with %s. Not after that." % String(other.get("first", other.get("name", "")))


# --- The settlement: shifts, votes, beds ------------------------------------------------------------

## Host (Settlement.server_hour): `rec`'s work this hour: their jobs in order, skipping any a rival
## already works this hour (they refuse the shift: an argument). Returns the job worked or "idle".
static func work(st: Settlement, rec: Dictionary, hours: float) -> String:
	var now := floorf(Moods.now_h())
	var taken := {}
	for o: Dictionary in Settlement.settlers():
		if o != rec and _working(o, now) and is_rival(rec, o):
			taken[String(o.job_now)] = o
	for job: String in Settlement.jobs_of(rec):
		if taken.has(job):
			var o: Dictionary = taken[job]
			if float(rec.get("refused_h", -1.0)) != now:
				rec["refused_h"] = now
				rec["refused_with"] = id_of(o)
				argue(rec, o)
				SurvivorPerson.note(rec, "wouldn't work %s with %s" % [job, String(o.get("name", ""))])
			continue
		if SettlementJobs.do_job(st, job, rec, hours):
			rec["job_h"] = now
			return job
	rec["job_h"] = now
	return "idle"


## Council.factions: rivals in one faction don't vote together: the newer of the two splits off.
static func split_rivals(out: Dictionary) -> void:
	for f: String in out.keys():
		if f.begins_with("alone:"):
			continue
		var list: Array = out[f]
		for r: Dictionary in list.duplicate():
			if not list.has(r):
				continue
			for o: Dictionary in list:
				if o != r and is_rival(r, o):
					var newer: Dictionary = r if float(r.get("settled_h", 0.0)) >= float(o.get("settled_h", 0.0)) else o
					list.erase(newer)
					out["alone:" + id_of(newer)] = [newer]
					break


## Council.preference: how `rec` leans on a vote to send someone away (by their bond with them).
static func lean(rec: Dictionary, v: Dictionary, score: Dictionary) -> void:
	var q: Dictionary = v.get("question", {})
	if String(q.get("kind", "")) != VOTE_OUT:
		return
	var opts: Array = v.options
	var who := SurvivorsLayer.record(String(q.get("person", "")))
	if who.is_empty():
		return
	var yes := String(opts[0])
	var no := String(opts[1])
	if who == rec or are_partners(rec, who):
		score[no] = float(score.get(no, 0.0)) + 10.0
		return
	var b := bond(rec, who)
	score[yes] = float(score.get(yes, 0.0)) + maxf(0.0, -b) / 20.0 + (0.5 if SurvivorPerson.has_trait(rec, "calm") else 0.0)
	score[no] = float(score.get(no, 0.0)) + maxf(0.0, b) / 20.0 + (0.5 if SurvivorPerson.has_trait(rec, "kind") else 0.0)


## Council._apply: the vote to send someone away carried: they leave (a lone survivor again).
static func apply_vote(st: Settlement, v: Dictionary, yes: bool) -> void:
	var q: Dictionary = v.get("question", {})
	var who := SurvivorsLayer.record(String(q.get("person", "")))
	if not yes or who.is_empty() or String(who.get("status", "")) != "settler":
		return
	who["grudge"] = true
	SurvivorPerson.note(who, "voted out of the settlement")
	var layer: SurvivorsLayer = SurvivorsLayer.find(st) if st and st.is_inside_tree() else null
	if layer:
		layer.server_desert(who)
	else:
		who["status"] = "out_there"
	Survival._journal_line("%s was sent away." % String(who.get("name", "")))


## Settlement.has_bed: the bed `rec` has among `list` (a couple shares one); -1 none counted yet.
static func bed_slot(rec: Dictionary, list: Array) -> int:
	var slots := {}
	var n := 0
	for r: Dictionary in list:
		var p := partner_of(r)
		if p != "" and slots.has(p):
			slots[id_of(r)] = slots[p]
		else:
			slots[id_of(r)] = n
			n += 1
		if r == rec:
			return int(slots[id_of(r)])
	return -1


## The beds `list` needs (a couple one between them).
static func beds_used(list: Array) -> int:
	var ids := {}
	for r: Dictionary in list:
		ids[id_of(r)] = true
	var n := 0
	for r: Dictionary in list:
		var p := partner_of(r)
		if p != "" and ids.has(p) and p < id_of(r):
			continue
		n += 1
	return n


# --- The People tab ---------------------------------------------------------------------------------

## One line a person (companions and settlers): "Ana Reed: partner of Tom; friend of Sam (41);
## rival of Joe (-33); you: close friend (64)".
static func people_lines() -> Array:
	var out: Array = []
	var recs: Array[Dictionary] = []
	for r: Dictionary in SurvivorsLayer.records().values():
		if alive_here(r):
			recs.append(r)
	recs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("name", "")) < String(b.get("name", "")))
	for r: Dictionary in recs:
		var l := line_of(r)
		if l != "":
			out.append(l)
	return out


static func line_of(rec: Dictionary) -> String:
	var parts := PackedStringArray()
	var rel: Dictionary = rec.get("relations", {})
	var ids := rel.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return absf(float(rel[a])) > absf(float(rel[b])))
	for oid: String in ids:
		var o := SurvivorsLayer.record(oid)
		if o.is_empty() or not alive_here(o):
			continue
		var lb := label(rec, o)
		if lb in ["stranger", "acquaintance"]:
			continue
		var first := String(o.get("first", o.get("name", "")))
		if lb == "partner":
			parts.append("partner of %s" % first)
		elif Children.is_child_rec(rec) and String(rec.get("carer", "")) == oid:
			parts.append("attached to %s (%d)" % [first, roundi(float(rel[oid]))])
		else:
			parts.append("%s of %s (%d)" % [lb, first, roundi(float(rel[oid]))])
		if parts.size() >= 4:
			break
	var pb := player_bond(rec)
	parts.append("you: %s (%d)" % [label_of(pb), roundi(pb)])
	return "%s: %s" % [String(rec.get("name", "")), "; ".join(parts)]
