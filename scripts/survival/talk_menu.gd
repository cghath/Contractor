class_name TalkMenu
extends RefCounted
## The contextual talk of Contractor: Fallen (docs/survival_people.md sections 4-5, calls 2, 54):
## looking at a survivor within InteractionMenu.REACH (3 m) and holding the interact key offers
## Who are you, What do you want, Ask about this place, Trade, Recruit, Give, Threaten; a
## companion adds How are you and What do you think to the squadmate's entries; a dead one can be
## buried. The entries are local Callables (InteractionMenu's OBJECT pattern) that send
## SurvivorsLayer.request_talk to the host, which answers here (server_talk): a line picked by tags
## from data/survival_lines.json (pick_line), said as a subtitle (SurvivorsLayer.say), and what the
## action does: the want met and they join (meet_want, pay), a gift, a threat remembered.
## Phase C (the intel lane): "Trade" opens the barter screen on a trader (Barter, TradeScreen) and
## "Ask about..." tells a rumour by topic (Intel.server_ask); the world sim's live people (WorldLive
## bodies, metas "world_person" and "world_group") talk too: Who are you, Ask about, Trade.

const LINES_PATH := "res://data/survival_lines.json"
## The interaction menu's target kind for a survivor (InteractionMenu.target_kind).
const KIND := &"survivor"
## Proposed: how much a threat costs, a gift buys, joining is worth, in opinion.
const THREAT_OPINION := -35.0
const GIFT_OPINION := 8.0
const JOIN_OPINION := 25.0

static var _lines: Dictionary = {}


# --- The menu (every peer) -------------------------------------------------------------------

## Whether `target` is a survivor on their feet who isn't one of ours yet (out in the world).
static func is_survivor(target: Node) -> bool:
	var layer := SurvivorsLayer.find(target)
	if layer != null and target.has_meta(&"world_person"):
		return true  # (a world group's live person: WorldLive)
	return layer != null and String(layer.info_of(target).get("status", "")) in ["out_there", "settler"]


## The "Ask about..." submenu (Intel.TOPICS) built with `talk` (actions_for's maker).
static func _ask_entry(target: Node, talk: Callable) -> Dictionary:
	var ask := {"id": &"talk_ask", "label": "Ask about...", "target": target, "disabled": "", "items": [] as Array[Dictionary]}
	for t: Array in Intel.TOPICS:
		(ask.items as Array).append(talk.call("ask", String(t[1]), {"topic": String(t[0])}, ""))
	return ask


## The talk entries `actor` gets on `target` (InteractionMenu.actions_for: the SURVIVOR kind, and
## extra entries on a companion and a dead survivor), each with a local "call".
static func actions_for(actor: Soldier, target: Node, menu_kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var layer := SurvivorsLayer.find(target)
	if layer == null or not target is Soldier:
		return out
	var info := layer.info_of(target)
	var status := String(info.get("status", ""))
	var path := target.get_path()
	var talk := func(action: String, label: String, arg: Dictionary, group: String) -> Dictionary:
		var e := {"id": StringName("talk_" + action), "label": label, "target": target, "disabled": "",
			"call": func() -> void: layer.request_talk.rpc_id(1, action, path, arg)}
		if group != "":
			e["group"] = group
		return e
	if menu_kind == KIND and target.has_meta(&"world_person"):  # (a world group's person: Intel, Barter)
		out.append(talk.call("who", "Who are you?", {}, ""))
		out.append(_ask_entry(target, talk))
		out.append(talk.call("trade", "Trade", {}, ""))
	elif menu_kind == KIND and bool(info.get("child", false)):  # a child (call 128): no recruiting, no threats
		out.append(talk.call("who", "Who are you?", {}, ""))
		if status == "out_there" and bool(info.get("orphan", false)):
			out.append(talk.call("come", "Come with me", {}, ""))
		elif status == "settler":
			out.append(talk.call("how", "How are you?", {}, ""))
	elif menu_kind == KIND and status == "settler":  # (a settler at home: Settlement)
		if bool(info.get("rite", false)):  # a pious one asks for words at a grave (call 129)
			out.append(talk.call("words", "Say a few words", {}, ""))
			out.append(talk.call("no_words", "Not now", {}, InteractionMenu.MORE))
		out.append(talk.call("how", "How are you?", {}, ""))
		out.append(talk.call("take_along", "Take along", {}, ""))
		out.append(talk.call("who", "Who are you?", {}, InteractionMenu.MORE))
		out.append(_gift_entry(actor, target, talk))  # bonds (call 74)
		out.append(talk.call("settle_it", "Settle it (a feud)", {}, InteractionMenu.MORE))
	elif menu_kind == KIND:
		if bool(info.get("crew", false)):  # the downed helicopter's crew: escort them home (HeliCrew)
			out.append(talk.call("crew_come", "Come with me", {}, ""))
		out.append(talk.call("who", "Who are you?", {}, ""))
		if bool(info.get("asks_stay", false)):  # they ran here from the dead and ask to stay (Holding, call 143)
			out.append(talk.call("let_stay", "Let them stay", {}, ""))
			out.append(talk.call("turn_away", "Turn them away", {}, InteractionMenu.MORE))
		if bool(info.get("refugee", false)):  # they left their place to the dead (Holding, call 143)
			out.append(talk.call("clear_now", "It's clear now", {}, ""))
		out.append(talk.call("want", "What do you want?", {}, ""))
		out.append(talk.call("recruit", "Recruit", {}, ""))
		out.append(talk.call("place", "Ask about this place", {}, ""))
		out.append(_ask_entry(target, talk))
		var give := {"id": &"talk_give", "label": "Give", "target": target, "disabled": "", "items": [] as Array[Dictionary]}
		for c: StringName in actor.inventory.search_containers():
			var list: Array = actor.inventory.containers[c]
			for i in list.size():
				if (give.items as Array).size() >= InteractionMenu.MAX_GIVE_ENTRIES:
					break
				var item := ItemDB.get_item(StringName(list[i].id))
				if item:
					(give.items as Array).append(talk.call("give", item.name, {"container": String(c), "index": i}, ""))
		if (give.items as Array).is_empty():
			give.disabled = "Nothing stowed to give"
		out.append(give)
		out.append(talk.call("trade", "Trade", {}, InteractionMenu.MORE))
		out.append(talk.call("threaten", "Threaten", {}, InteractionMenu.MORE))
	elif menu_kind == InteractionMenu.SQUADMATE:
		if status == "companion":
			if bool(info.get("escort", false)):  # an escorted crew member: the enclave's pickup by radio (HeliCrew)
				var pick: Dictionary = talk.call("crew_pickup", "Radio a pickup", {}, "")
				pick.disabled = HeliCrew.radio_problem(actor)
				out.append(pick)
			out.append({"id": &"talk_gear", "label": "Gear", "target": target, "disabled": "", "call": func() -> void: LoadoutGear.open_on(actor, target as Soldier)})
			out.append(talk.call("how", "How are you?", {}, ""))
			out.append(talk.call("talk_down", "Talk me down", {}, ""))  # the nerve (Nerve, call 116)
			if bool(info.get("rite", false)):  # a pious companion asks for words at a grave (call 129)
				out.append(talk.call("words", "Say a few words", {}, ""))
				out.append(talk.call("no_words", "Not now", {}, InteractionMenu.MORE))
			out.append(talk.call("think", "What do you think?", {}, InteractionMenu.MORE))
			out.append(talk.call("settle", "Make a settler", {}, InteractionMenu.MORE))
			out.append(_gift_entry(actor, target, talk))  # bonds (call 74)
			out.append(talk.call("settle_it", "Settle it (a feud)", {}, InteractionMenu.MORE))
	elif menu_kind == InteractionMenu.DEAD and Masking.is_dead_one(target):
		out.append(talk.call("smear", "Smear its gore on you", {}, ""))  # (phase D masking: Masking)
	elif menu_kind == InteractionMenu.DEAD:
		if status == "dead" and bool(info.get("crew", false)) and not bool(info.get("tags", false)):
			out.append(talk.call("crew_tags", "Take their tags", {}, ""))  # (HeliCrew: the enclave wants them)
		if status == "dead" and not bool(info.get("buried", false)):
			var shovel := SurvivorsLayer.shovel_of(actor) != &""
			out.append(talk.call("bury", "Bury (%s)" % ("with the shovel" if shovel else "by hand, slow"), {}, ""))
			if not bool(info.get("butchered", false)):  # the dark line (Cannibalism, call 117)
				var cut: Dictionary = talk.call("butcher", "Butcher for meat", {}, InteractionMenu.MORE)
				if not Crafting.has_tool(actor, ["tag:blade", "tag:knife"]):
					cut.disabled = "You need a knife or a blade"
				out.append(cut)
	return out


## The bond-aware "Gift" submenu (call 74): what `actor` has stowed, each a "gift" talk action.
static func _gift_entry(actor: Soldier, target: Node, talk: Callable) -> Dictionary:
	var gift := {"id": &"talk_gift", "label": "Gift", "target": target, "disabled": "", "items": [] as Array[Dictionary]}
	for c: StringName in actor.inventory.search_containers():
		var list: Array = actor.inventory.containers[c]
		for i in list.size():
			if (gift.items as Array).size() >= InteractionMenu.MAX_GIVE_ENTRIES:
				break
			var item := ItemDB.get_item(StringName(list[i].id))
			if item:
				(gift.items as Array).append(talk.call("gift", item.name, {"container": String(c), "index": i}, ""))
	if (gift.items as Array).is_empty():
		gift.disabled = "Nothing stowed to give"
	return gift


# --- Lines (host) ------------------------------------------------------------------------------

static func lines() -> Dictionary:
	if _lines.is_empty():
		var f := FileAccess.open(LINES_PATH, FileAccess.READ)
		var parsed: Variant = ModKit.overlay("survival_lines", JSON.parse_string(f.get_as_text()) if f else null)  # (mods: docs/fallen_modding.md)
		_lines = (parsed as Dictionary).get("topics", {}) if parsed is Dictionary else {}
	return _lines


## The tags a person speaks with (pick_line): their status, mood band, traits, want, disposition,
## scared or cocky, a grudge, and what their body says (hungry, cold).
static func tags_of(rec: Dictionary) -> Dictionary:
	var t := {}
	t[String(rec.get("status", "out_there"))] = true
	var b := Moods.band(rec)
	t["mood_" + b] = true
	for tr: String in rec.get("traits", []):
		t[tr] = true
	var w := String((rec.get("want", {}) as Dictionary).get("kind", ""))
	if w != "":
		t["want_" + w] = true
	t[String(rec.get("disposition", "friendly"))] = true
	var brave := SurvivorPerson.has_trait(rec, "brave")
	if not brave and (SurvivorPerson.has_trait(rec, "timid") or b in ["low", "broken"]):
		t["scared"] = true
	if brave and (SurvivorPerson.has_trait(rec, "hot_headed") or SurvivorPerson.has_trait(rec, "cruel") or b == "high"):
		t["cocky"] = true
	if bool(rec.get("grudge", false)):
		t["grudge"] = true
	var n: Dictionary = rec.get("needs", {})
	if not n.is_empty():
		Needs.ensure(n)
		if float(n.hunger) < 35.0:
			t["hungry"] = true
		if float(n.warmth) < Needs.SHIVER_C:
			t["cold"] = true
	return t


## A line of `topic` for a speaker with `tags`: only lines whose tags are all the speaker's; the
## most specific (most tags) win, ties at random. {} when the topic has none.
static func pick_line(topic: String, tags: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	var best: Array = []
	var best_n := -1
	for line: Dictionary in lines().get(topic, []):
		var lt: Array = line.get("tags", [])
		if not lt.all(func(x: String) -> bool: return tags.has(x)):
			continue
		if lt.size() > best_n:
			best_n = lt.size()
			best = [line]
		elif lt.size() == best_n:
			best.append(line)
	if best.is_empty():
		return {}
	return best[(rng.randi() if rng else randi()) % best.size()]


## `rec`'s line for `topic`, filled in ({name}, {first}, {want}, {zone}, {background}, {item}).
static func line_for(rec: Dictionary, topic: String, extra := {}) -> String:
	var line := pick_line(topic, tags_of(rec))
	if line.is_empty():
		return ""
	var fill := {"name": rec.get("name", ""), "first": rec.get("first", rec.get("name", "")), "want": SurvivorPerson.want_text(rec),
		"zone": _zone_name(String(rec.get("zone", ""))), "background": rec.get("background", "nobody"), "item": extra.get("item", "it")}
	return String(line.text).format(fill)


static func _zone_name(zone_id: String) -> String:
	var z: Dictionary = MissionRegistry.zone(zone_id) if zone_id != "" else {}
	return String(z.get("name", "this place")) if not z.is_empty() else "this place"


# --- What talking does (host) --------------------------------------------------------------------

## Host: `actor` did `action` (with `arg`) on the survivor `target`. Returns the line they said.
static func server_talk(layer: SurvivorsLayer, actor: Soldier, target: Soldier, action: String, arg := {}) -> String:
	if action == "gear":  # the gear editor's ops (LoadoutGear; the actor's own kit too)
		return CompanionGear.server_op(actor, target, arg)
	var rec := layer.record_of(target)
	if rec.is_empty() and target and target.has_meta(&"world_person"):
		rec = WorldSim.people().get(String(target.get_meta(&"world_person")), {})
	if rec.is_empty() or actor == null or not actor.vitals.is_up():
		return ""
	if action == "crew_tags":
		var took: String = HeliCrew.server_take_tags(actor, rec)
		layer._set_known(target, rec)
		Survival._tell(actor, took)
		return took
	if action == "bury":
		layer.server_start_bury(actor, target)
		return ""
	if action == "smear":
		Masking.server_smear(actor, target)
		return ""
	if action == "butcher":
		Cannibalism.server_butcher(actor, target, rec)
		return ""
	if not target.vitals.is_up():
		return ""
	if actor.global_position.distance_to(target.global_position) > InteractionMenu.REACH + 1.5:
		return ""
	var profile := Survival.profile_of(actor)
	var topic := ""
	var extra := {}
	if action in ["words", "no_words"]:  # (call 129: Faith's rite at a grave)
		return Faith.server_words(layer, actor, rec, action == "words")
	if action == "clear_now":  # (call 143: their place is clear, they can go home)
		return Holding.server_clear_now(layer, actor, rec)
	if action in ["let_stay", "turn_away"]:  # (call 143: refugees asking to stay)
		return Holding.server_let_stay(layer, actor, rec, action == "let_stay")
	if Children.is_child_rec(rec) and action in ["recruit", "threaten", "trade", "take_along", "settle", "talk_down", "settle_it"]:
		return ""  # (call 128: a child is never a companion, never threatened)
	match action:
		"crew_come":  # the downed crew follow (HeliCrew)
			var come: String = HeliCrew.server_come(layer, actor, rec)
			return come
		"crew_pickup":
			var pickup: String = HeliCrew.server_radio_pickup(layer, actor)
			Survival._tell(actor, pickup if pickup != "" else "Nobody here to pick up")
			return pickup
		"come":  # an orphan comes along: a settler (call 128)
			if not Children.is_child_rec(rec) or String(rec.get("status", "")) != "out_there":
				return ""
			if not Settlement.exists():
				topic = "child_wait"
			else:
				var yes := line_for(rec, "child_come")
				layer.say(target, yes)
				Children.server_take_in(layer, rec)
				Survival._journal_line("%s came with us. %s'll live at the settlement." % [String(rec.get("first", rec.name)), "She" if String(rec.get("sex", "m")) == "f" else "He"])
				return yes
		"who":
			topic = "child_greet" if Children.is_child_rec(rec) else ("deserter_ask" if bool(rec.get("cult_deserter", false)) else "greet")
			Intel.server_met(rec, "who")
		"want":
			topic = "want"
			if String((rec.want as Dictionary).get("kind", "")) == "favour":
				layer.server_mark_favour(rec, target.global_position)
				topic = "favour_marked" if not bool(rec.want.get("done", false)) else "favour_done"
		"place":
			topic = "place"
		"trade":
			Intel.server_met(rec, "trade")
			var why := Barter.trader_problem(rec)
			topic = "trade" if why == "" else "trade_no"
			if why == "" and Intel.get_intel():
				Intel.get_intel().server_send_deal(actor, Barter.deal(actor, rec))
			elif why != "":
				Survival._tell(actor, why)
		"ask":
			var told := Intel.server_ask(rec, String(arg.get("topic", "here")), String(Survival.state().get("zone", "")))
			var said_r := String(told.text) if String(told.text) != "" else line_for(rec, "rumour_none")
			layer.say(target, said_r)
			return said_r
		"recruit":
			var why := want_problem(actor, rec, layer)
			if why == "" and bool(rec.get("grudge", false)) and SurvivorPerson.opinion_of(rec, profile) < 0.0:
				why = "grudge"
			if why == "":
				pay(actor, rec)
				SurvivorPerson.change_opinion(rec, profile, JOIN_OPINION)
				var line := line_for(rec, "recruit_yes")
				layer.say(target, line)
				if String((rec.want as Dictionary).get("kind", "")) == "place" and Settlement.place_problem() == "":
					layer.server_settle(rec, actor)  # a bed at the settlement (call 23)
				else:
					layer.server_recruit(rec, actor)
				return line
			topic = "recruit_no"
		"give":
			var c := StringName(String(arg.get("container", "")))
			var i := int(arg.get("index", -1))
			var list: Array = actor.inventory.containers.get(c, [])
			if i < 0 or i >= list.size():
				return ""
			if Children.give_refused(rec, ItemDB.get_item(StringName(String(list[i].id)))):
				var no := line_for(rec, "child_no_weapon")
				layer.say(target, no)
				return no  # (call 128: no weapon for a child)
			var entry: Dictionary = actor.inventory.remove_entry(c, i, 1)
			if entry.is_empty():
				return ""
			(rec.kit as Array).append({"id": String(entry.id), "count": 1, "state": entry.get("state", {})})
			target.inventory.take(StringName(entry.id), 1, entry.get("state", {}))
			SurvivorPerson.change_opinion(rec, profile, GIFT_OPINION)
			Moods.add(rec, "gift")
			topic = "gift"
		"gift":  # a companion or a settler (call 74: the bond with you)
			if not String(rec.get("status", "")) in ["companion", "settler"]:
				return ""
			var gc := StringName(String(arg.get("container", "")))
			var gi := int(arg.get("index", -1))
			var glist: Array = actor.inventory.containers.get(gc, [])
			if gi < 0 or gi >= glist.size():
				return ""
			var gitem := ItemDB.get_item(StringName(String(glist[gi].id)))
			if Children.give_refused(rec, gitem):
				var gno := line_for(rec, "child_no_weapon")
				layer.say(target, gno)
				return gno
			var gentry: Dictionary = actor.inventory.remove_entry(gc, gi, 1)
			if gentry.is_empty():
				return ""
			if target.inventory.take(StringName(gentry.id), 1, gentry.get("state", {})) < 1:
				(rec.kit as Array).append({"id": String(gentry.id), "count": 1, "state": gentry.get("state", {})})
			Relationships.on_gift(rec, profile, gitem)
			topic = "gift"
		"settle_it":  # mediate a feud (call 74)
			var said_s := Relationships.server_mediate(actor, rec)
			layer.say(target, said_s)
			return said_s
		"threaten":
			SurvivorPerson.change_opinion(rec, profile, THREAT_OPINION)
			Moods.add(rec, "threatened")
			SurvivorPerson.note(rec, "threatened by %s" % Survival.survivor_name(actor))
			if SurvivorPerson.has_trait(rec, "brave") or float(rec.get("courage", 0.0)) >= 60.0:
				topic = "threaten_draw"
				rec["disposition"] = "hostile"
				rec["grudge"] = true
			elif SurvivorPerson.has_trait(rec, "calm"):
				topic = "threaten_calm"
			else:
				topic = "threaten_fold"
				var dropped := layer.server_drop_one(target)  # the cowardly fold: something of theirs at your feet
				if dropped != "":
					extra.item = dropped
		"how":
			topic = "child_how" if Children.is_child_rec(rec) else "how_are_you"
		"settle", "take_along":
			var said_now := settle_talk(layer, actor, rec, action)
			layer.say(target, said_now)
			return said_now
		"think":
			topic = "think"
		"talk_down":
			if Relationships.free_talk(rec, profile):
				rec.erase("talk_down_until")  # a close bond talks you down any time (call 74)
			var busy := Nerve.server_talk_down(actor, rec) != ""
			var said_n := Nerve.talk_line(rec, busy)
			layer.say(target, said_n)
			return said_n
	var said := line_for(rec, topic, extra)
	layer.say(target, said)
	return said


## Why `rec`'s want isn't met by `actor` yet ("" when it is): money in cash items' CASH_VALUE, an
## item of the want on him (count of it), a favour done, a place (a safehouse for now).
static func want_problem(actor: Soldier, rec: Dictionary, layer: SurvivorsLayer = null) -> String:
	var w: Dictionary = rec.get("want", {})
	match String(w.get("kind", "")):
		"money":
			return "" if cash_of(actor) >= int(w.get("amount", 0)) else "money"
		"item":
			return "" if count_matching(actor, w) >= int(w.get("count", 1)) else "item"
		"favour":
			if not bool(w.get("done", false)):
				return "favour"
			if String(w.get("task", "")) == "fetch" and actor.inventory.count_of(StringName(String(w.get("item", "")))) <= 0:
				return "favour"
			return ""
		"place":
			return "" if Settlement.place_problem() == "" or not SurvivalMap.safehouse().is_empty() else "place"
	return ""


## Cash `s` carries, by CASH_VALUE.
static func cash_of(s: Soldier) -> int:
	var total := 0
	for id: String in SurvivorPerson.CASH_VALUE:
		total += s.inventory.count_of(StringName(id)) * int(SurvivorPerson.CASH_VALUE[id])
	return total


## How many items answering the want `w` `s` carries (stowed, worn or held).
static func count_matching(s: Soldier, w: Dictionary) -> int:
	var n := 0
	for e: Dictionary in Survival.kit_of(s.inventory):
		if SurvivorPerson.matches(w, ItemDB.get_item(StringName(String(e.id)))):
			n += int(e.get("count", 1))
	return n


## Host: `actor` hands over what `rec` wants (cash up to the amount, smallest notes first, no
## change: Proposed; or the items; or the fetched one); it goes into their kit.
static func pay(actor: Soldier, rec: Dictionary) -> void:
	var w: Dictionary = rec.get("want", {})
	var inv := actor.inventory
	match String(w.get("kind", "")):
		"money":
			var left := int(w.get("amount", 0))
			var ids := SurvivorPerson.CASH_VALUE.keys()
			ids.sort_custom(func(a: String, b: String) -> bool: return int(SurvivorPerson.CASH_VALUE[a]) < int(SurvivorPerson.CASH_VALUE[b]))
			for id: String in ids:
				while left > 0 and inv.count_of(StringName(id)) > 0:
					inv.remove_one(StringName(id))
					left -= int(SurvivorPerson.CASH_VALUE[id])
					_to_kit(rec, id, {})
		"item":
			var need := int(w.get("count", 1))
			need -= _take_matching(inv, w, need, rec)
		"favour":
			if String(w.get("task", "")) == "fetch":
				var id := StringName(String(w.get("item", "")))
				if inv.count_of(id) > 0:
					inv.remove_one(id)
					_to_kit(rec, String(id), {})


static func _to_kit(rec: Dictionary, id: String, state: Dictionary) -> void:
	for e: Dictionary in rec.kit:
		if String(e.id) == id and state.is_empty() and (e.get("state", {}) as Dictionary).is_empty():
			e.count = int(e.get("count", 1)) + 1
			return
	(rec.kit as Array).append({"id": id, "count": 1, "state": state} if not state.is_empty() else {"id": id, "count": 1})


## Takes up to `need` items answering `w` off `inv` (stowed first, then worn, then held) into
## `rec`'s kit; returns how many.
static func _take_matching(inv: Inventory, w: Dictionary, need: int, rec: Dictionary) -> int:
	var got := 0
	for c: StringName in inv.search_containers():
		var i: int = (inv.containers.get(c, []) as Array).size() - 1
		while i >= 0 and got < need:
			var e: Dictionary = inv.containers[c][i]
			if SurvivorPerson.matches(w, ItemDB.get_item(StringName(String(e.id)))):
				var took: Dictionary = inv.remove_entry(c, i, mini(int(e.get("count", 1)), need - got))
				if not took.is_empty():
					got += int(took.get("count", 1))
					for k in int(took.get("count", 1)):
						_to_kit(rec, String(took.id), took.get("state", {}))
			i -= 1
	for slot: StringName in Inventory.SLOTS:
		if got >= need:
			break
		var id := inv.slots.get(slot, &"") as StringName
		if id != &"" and SurvivorPerson.matches(w, ItemDB.get_item(id)):
			var off: Dictionary = inv.unequip(slot)
			if not off.is_empty():
				got += 1
				_to_kit(rec, String(off.id), off.get("state", {}))
	if got < need and inv.hands != &"" and SurvivorPerson.matches(w, ItemDB.get_item(inv.hands)):
		_to_kit(rec, String(inv.release_hands()), {})
		got += 1
	return got


## Host: "Make a settler" (a companion stays at the settlement: a free bed wanted) and "Take
## along" (a settler comes with `actor` as a companion). Returns what they say.
static func settle_talk(layer: SurvivorsLayer, actor: Soldier, rec: Dictionary, action: String) -> String:
	if action == "settle":
		if String(rec.get("status", "")) != "companion":
			return ""
		if Settlement.place_problem() != "":
			return "There's no bed for me there yet."
		layer.server_settle(rec, actor)
		return "I'll stay and keep the place."
	if String(rec.get("status", "")) != "settler":
		return ""
	layer.server_take_along(rec, actor)
	return "Right behind you."
