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
	return layer != null and String(layer.info_of(target).get("status", "")) == "out_there"


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
	if menu_kind == KIND:
		out.append(talk.call("who", "Who are you?", {}, ""))
		out.append(talk.call("want", "What do you want?", {}, ""))
		out.append(talk.call("recruit", "Recruit", {}, ""))
		out.append(talk.call("place", "Ask about this place", {}, ""))
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
			out.append(talk.call("how", "How are you?", {}, ""))
			out.append(talk.call("think", "What do you think?", {}, InteractionMenu.MORE))
	elif menu_kind == InteractionMenu.DEAD:
		if status == "dead" and not bool(info.get("buried", false)):
			var shovel := SurvivorsLayer.shovel_of(actor) != &""
			out.append(talk.call("bury", "Bury (%s)" % ("with the shovel" if shovel else "by hand, slow"), {}, ""))
	return out


# --- Lines (host) ------------------------------------------------------------------------------

static func lines() -> Dictionary:
	if _lines.is_empty():
		var f := FileAccess.open(LINES_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text()) if f else null
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
	var rec := layer.record_of(target)
	if rec.is_empty() or actor == null or not actor.vitals.is_up():
		return ""
	if action == "bury":
		layer.server_start_bury(actor, target)
		return ""
	if not target.vitals.is_up():
		return ""
	if actor.global_position.distance_to(target.global_position) > InteractionMenu.REACH + 1.5:
		return ""
	var profile := Survival.profile_of(actor)
	var topic := ""
	var extra := {}
	match action:
		"who":
			topic = "greet"
		"want":
			topic = "want"
			if String((rec.want as Dictionary).get("kind", "")) == "favour":
				layer.server_mark_favour(rec, target.global_position)
				topic = "favour_marked" if not bool(rec.want.get("done", false)) else "favour_done"
		"place":
			topic = "place"
		"trade":
			topic = "trade"  # (the barter screen is phase C, call 26)
		"recruit":
			var why := want_problem(actor, rec, layer)
			if why == "" and bool(rec.get("grudge", false)) and SurvivorPerson.opinion_of(rec, profile) < 0.0:
				why = "grudge"
			if why == "":
				pay(actor, rec)
				SurvivorPerson.change_opinion(rec, profile, JOIN_OPINION)
				var line := line_for(rec, "recruit_yes")
				layer.say(target, line)
				layer.server_recruit(rec, actor)
				return line
			topic = "recruit_no"
		"give":
			var c := StringName(String(arg.get("container", "")))
			var i := int(arg.get("index", -1))
			var list: Array = actor.inventory.containers.get(c, [])
			if i < 0 or i >= list.size():
				return ""
			var entry: Dictionary = actor.inventory.remove_entry(c, i, 1)
			if entry.is_empty():
				return ""
			(rec.kit as Array).append({"id": String(entry.id), "count": 1, "state": entry.get("state", {})})
			target.inventory.take(StringName(entry.id), 1, entry.get("state", {}))
			SurvivorPerson.change_opinion(rec, profile, GIFT_OPINION)
			Moods.add(rec, "gift")
			topic = "gift"
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
			topic = "how_are_you"
		"think":
			topic = "think"
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
			return "" if not SurvivalMap.safehouse().is_empty() else "place"
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
