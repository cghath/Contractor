class_name Council
extends RefCounted
## The settlement's council, first form (docs/survival_building.md §7, survival_people.md §9,
## calls 28, 59): big decisions go to a vote the players' standing sways. A question comes in
## through server_put (the world lane's raider demand, taking in a group, moving the settlement,
## or anything with its own on_result), as a journal line and a message to every player; a player
## says what he wants (server_choose, from the settlement screen) and the council meets; with no
## word from the players it meets after VOTE_H world hours anyway.
##
## Every settler votes by mood, relations and traits (preference); factions inside the settlement
## (a family, the old crew, the newcomers: factions) vote together, each member's weight going to
## the faction's choice; a member's weight is their influence (the oldest, a medic and the first
## to settle count more). The players' side carries their standing (the sum of the settlers'
## opinions of them weighted by influence) as a weight. Losing the vote, the settlement does the
## other thing (pays the demand from stock, refuses the group) and the players live with it.
## A leader challenge comes when morale and the host's standing both fall under their lines: a
## flag and a message for now. Every number here is Proposed.

const VOTE_H := 2.0
## The players' weight: PLAYER_BASE plus their standing over STANDING_PER (never under 0).
const PLAYER_BASE := 1.0
const STANDING_PER := 20.0
## Newcomers: settled within this many days.
const NEWCOMER_DAYS := 3.0
## A member whose relations with the rest of their faction average under this votes alone.
const ODD_ONE_OUT := -20.0
## The leader challenge: morale under CHALLENGE_MORALE and standing under CHALLENGE_STANDING, at
## most once in CHALLENGE_GAP_DAYS; the traits that make a challenger.
const CHALLENGE_MORALE := 35.0
const CHALLENGE_STANDING := 0.0
const CHALLENGE_GAP_DAYS := 3
const LEADER_TRAITS: Array[String] = ["brave", "hot_headed", "cruel", "greedy"]
## A demand is easier to pay with a weak defence.
const WEAK_DEFENCE := 30.0

## Host: what to call when vote id is decided (not saved: a vote back from a save is applied by
## its question's kind alone).
static var _callbacks := {}


static func _rec() -> Dictionary:
	var d := Settlement.data()
	if not d.get("council") is Dictionary:
		d["council"] = {}
	var c: Dictionary = d.get("council", {})
	if not c.get("votes") is Array:
		c["votes"] = []
	return c


static func votes() -> Array:
	return _rec().get("votes", [])


static func open_votes() -> Array:
	return votes().filter(func(v: Dictionary) -> bool: return String(v.get("state", "")) == "open")


static func get_vote(id: int) -> Dictionary:
	for v: Dictionary in votes():
		if int(v.id) == id:
			return v
	return {}


static func challenge() -> Dictionary:
	var c: Variant = _rec().get("challenge", {})
	return c if c is Dictionary else {}


## Host: a question for the council: `question` a {kind, text, ...} (kind "demand" with "pay":
## [[item, count], ...] and "from"; "take_in" with "people": [person ids]; "move" with "zone" and
## "pos"; anything else is "custom") or a plain text, `options` the answers (the first is the
## "yes": pay, take them, move), `on_result` called with the winner. Returns the vote's id (-1 when
## there's no settlement). The world lane's raider demand calls this.
static func server_put(question: Variant, options: Array, on_result: Callable = Callable()) -> int:
	if not Settlement.exists() or options.size() < 2:
		return -1
	var q: Dictionary = (question as Dictionary).duplicate(true) if question is Dictionary else {"kind": "custom", "text": String(question)}
	if not q.has("kind"):
		q["kind"] = "custom"
	var c := _rec()
	var id := int(c.get("next", 1))
	c["next"] = id + 1
	var v := {"id": id, "question": q, "options": options.map(func(o: Variant) -> String: return str(o)), "open_h": Moods.now_h(),
		"close_h": Moods.now_h() + VOTE_H, "player": {}, "state": "open", "result": "", "tally": {}}
	votes().append(v)
	if on_result.is_valid():
		_callbacks[id] = on_result
	var text := "The council: %s (%s)" % [String(q.get("text", "a question")), " or ".join(PackedStringArray(v.options))]
	Survival._journal_line(text)
	_tell_all(text)
	return id


static func _tell_all(text: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var lvl: CompoundLevel = CompoundLevel.current(tree.root) if tree else null
	if lvl:
		for p: Soldier in MapNodes.players(lvl):
			Survival._tell(p, text)


## Host: player `profile` wants `option` on vote `id`; the council meets at once. "" or why not.
static func server_choose(id: int, option: String, profile: String) -> String:
	var v := get_vote(id)
	if v.is_empty() or String(v.state) != "open":
		return "No such vote"
	if not option in (v.options as Array):
		return "No such answer"
	(v.player as Dictionary)[profile] = option
	server_resolve(id)
	return ""


## Host, every world hour (Settlement.server_hour): votes past their time are decided; the
## leader challenge is checked.
static func server_hour(st: Settlement) -> void:
	for v: Dictionary in open_votes():
		if Moods.now_h() >= float(v.close_h):
			server_resolve(int(v.id))
	check_challenge(st)


# --- Who votes how ----------------------------------------------------------------------------

## A member's weight: 1, +1 the oldest, +1 holding the medic job, +1 the first to settle.
static func influence(rec: Dictionary) -> float:
	var list := Settlement.settlers()
	if list.is_empty():
		return 1.0
	var w := 1.0
	var oldest := 0
	for r: Dictionary in list:
		oldest = maxi(oldest, int(r.get("age", 0)))
	if int(rec.get("age", 0)) == oldest:
		w += 1.0
	if "medic" in Settlement.jobs_of(rec):
		w += 1.0
	if String(list[0].get("id", "")) == String(rec.get("id", "")):
		w += 1.0
	return w


## The players' standing with the settlement (survival_people.md §9): every settler's opinion of
## `profile` times their influence, summed.
static func standing(_st: Settlement, profile: String) -> float:
	var s := 0.0
	for r: Dictionary in Settlement.settlers():
		s += SurvivorPerson.opinion_of(r, profile) * influence(r)
	return s


## The players' weight from `profile`'s standing.
static func player_weight(st: Settlement, profile: String) -> float:
	return maxf(0.0, PLAYER_BASE + standing(st, profile) / STANDING_PER)


## How `rec` leans on vote `v`: a score for each option (the highest is their vote).
static func preference(st: Settlement, rec: Dictionary, v: Dictionary) -> Dictionary:
	var opts: Array = v.options
	var yes := String(opts[0])
	var no := String(opts[1])
	var score := {}
	for o: String in opts:
		score[o] = 0.0
	var t := func(name: String) -> float: return 1.0 if SurvivorPerson.has_trait(rec, name) else 0.0
	var mood := Moods.mood(rec)
	var courage := float(rec.get("courage", 50.0))
	var food_days := Settlement.food_kcal() / (Needs.KCAL_DAY * maxf(1.0, Settlement.settlers().size()))
	var q: Dictionary = v.question
	match String(q.get("kind", "custom")):
		"demand":  # yes = pay, no = refuse
			score[yes] = 2.0 * t.call("timid") + t.call("kind") + t.call("calm") + t.call("gloomy") + (50.0 - courage) / 25.0 \
				+ (1.0 if st and st.defence() < WEAK_DEFENCE else 0.0)
			score[no] = 2.0 * t.call("brave") + 2.0 * t.call("hot_headed") + t.call("cruel") + 2.0 * t.call("greedy") + (courage - 50.0) / 25.0 \
				+ (1.0 if mood > 60.0 else 0.0)
		"take_in":  # yes = take them in
			score[yes] = 2.0 * t.call("kind") + t.call("optimist") + t.call("pious") + (1.0 if food_days > 3.0 else 0.0) + (1.0 if Settlement.free_beds() > 0 else 0.0)
			score[no] = 2.0 * t.call("greedy") + t.call("cruel") + t.call("gloomy") + 0.5 * t.call("fickle") + (2.0 if food_days < 2.0 else 0.0) \
				+ (2.0 if Settlement.free_beds() <= 0 else 0.0)
		"move":  # yes = move
			score[yes] = (2.0 if mood < 40.0 else 0.0) + t.call("fickle") + t.call("timid")
			var days := (Moods.now_h() - float(rec.get("settled_h", Moods.now_h()))) / 24.0
			score[no] = t.call("loyal") + t.call("hard_worker") + (1.0 if mood >= 60.0 else 0.0) + (1.0 if days > 7.0 else 0.0)
		"raid":  # yes = go (Proposed: the brave and the hungry for it, the timid against)
			score[yes] = t.call("brave") + t.call("hot_headed") + t.call("cruel") + (1.0 if food_days < 2.0 else 0.0)
			score[no] = t.call("timid") + t.call("kind") + t.call("calm") + (1.0 if food_days >= 3.0 else 0.0)
		_:  # custom: with the players if they think well of them, else against
			var liked := 0.0
			for p: String in (v.player as Dictionary):
				liked += SurvivorPerson.opinion_of(rec, p)
			for p: String in (v.player as Dictionary):
				score[String(v.player[p])] = float(score.get(String(v.player[p]), 0.0)) + (1.0 if liked > 0.0 else -1.0)
	Children.lean(rec, v, score)  # children here: safety first (call 128)
	Relationships.lean(rec, v, score)  # sending someone away after a fight (call 74)
	Faith.lean(rec, v, score)  # the settlement's faith (call 129)
	return score


static func _pick(score: Dictionary, opts: Array) -> String:
	var best := String(opts[0])
	for o: String in opts:
		if float(score.get(o, 0.0)) > float(score.get(best, 0.0)):
			best = o
	return best


## The factions inside the settlement (survival_people.md §9): {name: [records]}: a family
## ("family" on the record) votes together, then the pious, the rest split into the old crew and the newcomers
## (settled within NEWCOMER_DAYS); one whose relations with the rest of their faction average
## under ODD_ONE_OUT votes alone ("alone:<id>").
static func factions() -> Dictionary:
	var out := {}
	var now := Moods.now_h()
	for r: Dictionary in Settlement.settlers():
		if Children.is_child_rec(r):
			continue  # (children don't vote: call 128)
		var f := ""
		if String(r.get("family", "")) != "":
			f = "family:" + String(r.family)
		elif SurvivorPerson.has_trait(r, "pious"):
			f = "the pious"  # (phase D politics: the pious vote together, Politics)
		else:
			f = "newcomers" if now - float(r.get("settled_h", now)) < NEWCOMER_DAYS * 24.0 else "old crew"
		if not out.has(f):
			out[f] = []
		(out[f] as Array).append(r)
	for f: String in out.keys():
		var list: Array = out[f]
		if list.size() < 2:
			continue
		for r: Dictionary in list.duplicate():
			var sum := 0.0
			for o: Dictionary in list:
				if o != r:
					sum += SurvivorPerson.relation(r, String(o.id))
			if sum / (list.size() - 1) < ODD_ONE_OUT:
				list.erase(r)
				out["alone:" + String(r.id)] = [r]
	Relationships.split_rivals(out)  # rivals don't vote together (call 74)
	return out


## Host: the council meets on vote `id`: every faction's choice (its members' preferences by
## influence) carries all its members' weight, the players' choices carry their weight; the
## winner is done (by the question's kind: a demand paid from stock, a group taken in, the
## settlement moved) and on_result called. Returns the winner.
static func server_resolve(id: int) -> String:
	var v := get_vote(id)
	if v.is_empty() or String(v.state) != "open":
		return String(v.get("result", ""))
	var st := WorkOrders._st()
	var opts: Array = v.options
	var tally := {}
	for o: String in opts:
		tally[o] = 0.0
	var fs := factions()
	for f: String in fs:
		var inner := {}
		var weight := 0.0
		for r: Dictionary in fs[f]:
			var w := influence(r)
			weight += w
			var pick := _pick(preference(st, r, v), opts)
			inner[pick] = float(inner.get(pick, 0.0)) + w
		var choice := _pick(inner, opts)
		tally[choice] = float(tally[choice]) + weight
	var players: Dictionary = v.player
	for p: String in players:
		tally[String(players[p])] = float(tally.get(String(players[p]), 0.0)) + player_weight(st, p)
	var result := _pick(tally, opts)
	result = Children.risky_result(v, tally, result)  # a risky question with children here needs more (call 128)
	# A tie goes the players' way when they spoke.
	for p: String in players:
		if is_equal_approx(float(tally[String(players[p])]), float(tally[result])):
			result = String(players[p])
			break
	v["tally"] = tally
	v["result"] = result
	v["state"] = "done"
	v["done_h"] = Moods.now_h()
	_apply(st, v)
	var wanted := ""
	for p: String in players:
		wanted = String(players[p])
	var line := "The council voted: %s%s." % [result, (" (you wanted %s)" % wanted) if wanted != "" and wanted != result else ""]
	Survival._journal_line(line)
	_tell_all(line)
	var cb: Variant = _callbacks.get(id)
	_callbacks.erase(id)
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call(result)
	return result


## What the winner does, by the question's kind (the first option is the "yes").
static func _apply(_st: Settlement, v: Dictionary) -> void:
	var q: Dictionary = v.question
	var yes := String((v.options as Array)[0]) == String(v.result)
	match String(q.get("kind", "")):
		"demand":
			if yes:
				var paid := 0
				for pair: Array in q.get("pay", []):
					paid += Settlement.taken_count(Settlement.server_take(String(pair[0]), int(pair[1])))
				v["paid"] = paid
				for r: Dictionary in Settlement.settlers():
					if bool(q.get("people", false)):
						Moods.add(r, "paid_in_people")
		"take_in":
			if yes:
				for pid: Variant in q.get("people", []):
					var r := SurvivorsLayer.record(String(pid))
					if not r.is_empty() and String(r.get("status", "")) != "dead":
						Settlement.server_make_settler(r)
		"raid":
			if yes:
				Faith.server_prayer()  # a prayer before going out (call 129)
		"vote_out":  # (call 74: Relationships.VOTE_OUT)
			Relationships.apply_vote(_st, v, yes)
		"move":
			if yes:
				var p: Array = q.get("pos", [])
				if p.size() >= 3:
					Settlement.server_found(String(q.get("zone", Settlement.zone())), Vector3(float(p[0]), float(p[1]), float(p[2])))


## Host: a leader challenge when morale and the host's standing are both under their lines (at
## most once in CHALLENGE_GAP_DAYS): the settler with the most LEADER_TRAITS (then courage) asks
## for the lead. A flag and a message for now (winning it by standing, a contest or leaving later).
static func check_challenge(st: Settlement) -> Dictionary:
	if st == null:
		return {}
	var c := _rec()
	if Survival.day() - int(c.get("challenge_day", -99)) < CHALLENGE_GAP_DAYS:
		return {}
	var list := Settlement.settlers()
	if list.size() < 2 or st.morale() >= CHALLENGE_MORALE or standing(st, BaseHub.profile()) >= CHALLENGE_STANDING:
		return {}
	var best: Dictionary = {}
	var best_score := -1.0
	for r: Dictionary in list:
		var s := float(rec_traits(r)) * 100.0 + float(r.get("courage", 0.0))
		if s > best_score:
			best_score = s
			best = r
	var ch := {"by": String(best.id), "name": String(best.get("name", "")), "day": Survival.day(),
		"text": "%s wants the lead: morale and your standing are low." % String(best.get("name", "Someone"))}
	c["challenge"] = ch
	c["challenge_day"] = Survival.day()
	Survival._journal_line(String(ch.text))
	_tell_all(String(ch.text))
	return ch


static func rec_traits(r: Dictionary) -> int:
	var n := 0
	for t: String in LEADER_TRAITS:
		if SurvivorPerson.has_trait(r, t):
			n += 1
	return n
