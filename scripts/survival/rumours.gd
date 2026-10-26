class_name Rumours
extends RefCounted
## What a person can tell (docs/survival_world.md section 10, call 37): the events their group
## knows (its intel: seen, scouted, told in a trade), coloured by the teller: true, half-true (the
## wrong group, the wrong day) or a lie (a raider sending you into a horde). The talk menu and
## the intel lanes read for_person(); this is the data, not the UI. Static.
##
## Proposed tellers: raiders lie (to their gain: a horde's zone told as quiet and rich, a fight
## told as nothing); a scout (a person who scouted for their group, or an event their group
## scouted) tells it true; the rest by their traits: the kind, loyal and optimists mostly true,
## the fickle and greedy half-true or worse.

const MAX := 5


## Up to `limit` rumours `person_id` can tell, newest first: [{"text", "truth" (true | half |
## lie), "event" (id), "zone", "kind"}]. `w` is the world section, `people` the records.
static func for_person(w: Dictionary, people: Dictionary, person_id: String, world_seed: int, limit := MAX) -> Array:
	var rec: Dictionary = people.get(person_id, {})
	if rec.is_empty():
		return []
	var g := group_of(w, rec, person_id)
	var out: Array = []
	if g.is_empty():
		if rec.has("outside_rumour"):
			out.append({"text": String(rec.outside_rumour), "truth": "half", "event": 0, "zone": "", "kind": "outside"})
		return out
	var intel: Dictionary = g.get("intel", {})
	var ids: Array = intel.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return a.to_int() > b.to_int())
	var events := {}
	for e: Dictionary in w.get("events", []):
		events[str(e.id)] = e
	for key: String in ids:
		if out.size() >= limit:
			break
		var e: Dictionary = events.get(key, {})
		if e.is_empty() or String(e.kind) in ["trade"] and not (String(g.id) in (e.groups as Array)):
			continue
		var truth := truth_of(g, rec, String(intel[key]), world_seed, int(e.id))
		out.append({"text": tell(w, e, truth, world_seed, person_id), "truth": truth, "event": int(e.id), "zone": String(e.zone), "kind": String(e.kind)})
	if rec.has("outside_rumour") and out.size() < limit:
		out.append({"text": String(rec.outside_rumour), "truth": "half", "event": 0, "zone": "", "kind": "outside"})
	return out


## The group record a person speaks from: their world group, their group of one, their captor's.
static func group_of(w: Dictionary, rec: Dictionary, person_id: String) -> Dictionary:
	var groups: Dictionary = w.get("groups", {})
	for key: String in ["world_group", "captor"]:
		if groups.has(String(rec.get(key, ""))):
			return groups[String(rec[key])]
	return groups.get("lone_" + person_id, {})


## How `rec` (of group `g`, who learned it `how`) tells event `event_id`.
static func truth_of(g: Dictionary, rec: Dictionary, how: String, world_seed: int, event_id: int) -> String:
	if String(g.get("kind", "")) == "raiders":
		return "lie"
	if bool(rec.get("scout", false)) or how == "scout":
		return "true"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, String(rec.get("id", "")), event_id, "rumour"])
	var r := rng.randf()
	var t: Array = rec.get("traits", [])
	if "kind" in t or "loyal" in t or "optimist" in t:
		return "true" if r < 0.75 else "half"
	if "fickle" in t or "greedy" in t:
		return "lie" if r < 0.2 else ("half" if r < 0.7 else "true")
	if how == "told":
		return "half" if r < 0.5 else "true"
	return "true" if r < 0.65 else "half"


## The event as told: true as it happened; half-true with another group's name or a day off; a
## lie that serves the teller (a horde's zone quiet and rich; a fight that never was).
static func tell(w: Dictionary, e: Dictionary, truth: String, world_seed: int, person_id: String) -> String:
	var zones: Dictionary = w.get("zones", {})
	var zname := String((zones.get(String(e.zone), {}) as Dictionary).get("name", String(e.zone)))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, person_id, int(e.id), "tell"])
	match truth:
		"true":
			return "Day %d: %s." % [int(e.day), _cap(String(e.text))]
		"half":
			var groups: Dictionary = w.get("groups", {})
			var text := String(e.text)
			var swapped := false
			for gid: String in e.get("groups", []):
				var g: Dictionary = groups.get(gid, {})
				if g.is_empty() or String(g.get("name", "")) == "":
					continue
				var others := groups.keys().filter(func(k: String) -> bool: return k != gid and String((groups[k] as Dictionary).get("kind", "")) not in ["lone", ""])
				if not others.is_empty():
					others.sort()
					var other: Dictionary = groups[others[rng.randi_range(0, others.size() - 1)]]
					text = text.replace(String(g.name), String(other.name))
					swapped = true
					break
			var off := rng.randi_range(1, 3) * (1 if rng.randf() < 0.5 else -1)
			return "Around day %d, I heard %s." % [maxi(1, int(e.day) + (0 if swapped else off)), text]
		_:
			if String(e.kind) in ["horde", "horde_moved", "horde_attack", "fed", "bell", "burning"]:
				return "%s's quiet now. Nobody's touched the stores out there; go and see." % zname
			if String(e.kind) in ["fight", "raid", "death", "capture"]:
				return "Nothing much happens in %s. Safe enough to cross." % zname
			return "Don't bother with %s; it's picked clean and crawling." % zname


static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s
