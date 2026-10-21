class_name Fallen
extends RefCounted
## Dog tags, the memorial wall and the death benefit (cghath's list, 2026-10-20, "Campaign";
## docs/ChrisPlan_handoff.md, items: "a fallen squadmate's dog tags count"). Pure functions on
## the campaign's roster section (Roster), like RosterDeployment; BaseHub runs them on the host.
##
## - **Tags:** every company soldier wears tags (Soldier.dog_tags, set as the body spawns:
##   tags_of a roster member, player_tags a player's main character). Taking a fallen man's
##   tags is an interaction on his body (Soldier.server_take_tags): they become a TAGS item in
##   the taker's gear, the item's state the tags (JSON-safe Strings), and travel like any item.
## - **Extraction:** a man killed this deployment whose tags came out (carried by someone who
##   got out, set down in the point, aboard the ride home, or still on his body brought out) is
##   killed in action, recovered: on the wall at once, his benefit paid in the debrief. Without
##   his tags or his body he is missing in action ("mia_dead": the company saw him fall but can't
##   close the case): no recovery contract (there's nobody to bring back), still on the books
##   (wages, as any MIA), until his tags come out on a later deployment (tags_home) or
##   DECLARE_DAYS pass and he's declared dead (declare_dead), on the wall as "missing".
## - **Memorial wall:** the roster section's "memorial", one entry per fallen member, saved with
##   the campaign and sent to every peer with the roster (BaseHub.view): "mid", "name",
##   "callsign", "role", "day" (died, or declared dead), "zone" (its save id), "zone_name",
##   "contract" (title, "" on a raid or in a hot zone without one), "missions", "tags"
##   (RECOVERED or MISSING) and "how" (in words).
## - **Death benefit:** Prices.operations("kia_benefit"), once per man ("benefit_paid": the day
##   it was paid): BaseHub.server_pay_death_benefit, when his death is confirmed.

## The item a fallen man's tags become when taken off his body.
const TAGS := &"dog_tags"
const RECOVERED := "recovered"
const MISSING := "missing"
## Proposed: a man killed whose tags and body stayed in the zone is declared dead this many
## campaign days after he fell (his benefit paid then). It's the zone memory's week
## (BaseHub.ZONE_FRESH_DAYS): by then his body is long gone from the zone.
const DECLARE_DAYS := 7


## The tags a roster member wears.
static func tags_of(member: Dictionary) -> Dictionary:
	return {"mid": String(member.get("mid", "")), "name": String(member.get("name", "")), "callsign": String(member.get("callsign", "")),
		"role": String(member.get("role", ""))}


## The tags a player's main character wears ("player": their key). A main character never
## falls for good (they respawn), so these only ever go home again.
static func player_tags(key: String, main: Dictionary) -> Dictionary:
	return {"player": key, "name": String(main.get("name", key))}


## Tags in words: "Reaper (Dale Okafor)".
static func tags_text(tags: Dictionary) -> String:
	var callsign := String(tags.get("callsign", ""))
	var name := String(tags.get("name", ""))
	if callsign == "":
		return name if name != "" else "unknown"
	return "%s (%s)" % [callsign, name] if name != "" and name != callsign else callsign


## The member id tags (an item's state) belong to, "" for a player's or none.
static func mid_of(tags: Variant) -> String:
	return String((tags as Dictionary).get("mid", "")) if tags is Dictionary else ""


## Host: takes every TAGS item out of `inv` (its containers and pouches) and returns their
## states (the tags), so they go to the company's records and not home in someone's kit.
static func take_tags_from(inv: Inventory) -> Array:
	var out: Array = []
	for container: StringName in inv.search_containers():
		var list: Array = inv.containers.get(container, [])
		for i in range(list.size() - 1, -1, -1):
			if StringName(list[i].id) == TAGS:
				var removed := inv.remove_entry(container, i, int(list[i].count))
				for n in maxi(int(removed.get("count", 1)), 1):
					out.append((removed.get("state", {}) as Dictionary).duplicate(true))
	return out


## The tags among report entries ({"id", "count", "state"?}; a carrier's pouches and their
## contents are looked into: Contracts.flatten_entry).
static func tags_in(entries: Array) -> Array:
	var out: Array = []
	for entry: Dictionary in entries:
		for e: Dictionary in Contracts.flatten_entry(entry):
			if StringName(e.get("id", "")) == TAGS:
				out.append((e.get("state", {}) as Dictionary).duplicate(true))
	return out


## `entries` without the tags (and with a carrier's pouches and contents as entries of their
## own, as Contracts.flatten_entry gives them).
static func without_tags(entries: Array) -> Array:
	var out: Array = []
	for entry: Dictionary in entries:
		for e: Dictionary in Contracts.flatten_entry(entry):
			if StringName(e.get("id", "")) != TAGS:
				out.append(e)
	return out


# --- The memorial wall ---------------------------------------------------------------------

static func memorial(data: Dictionary) -> Array:
	if not data.has("memorial"):
		data["memorial"] = []
	return data["memorial"]


## The wall's entry for member `mid`, {} if he isn't on it.
static func on_wall(data: Dictionary, mid: String) -> Dictionary:
	for e: Dictionary in memorial(data):
		if String(e.get("mid", "")) == mid:
			return e
	return {}


## Puts `member` on the wall (or, already on it, brings his tags home: RECOVERED wins over
## MISSING). `where`: {"day", "zone", "contract"}, where and when he fell. Returns the entry.
static func add_to_wall(data: Dictionary, member: Dictionary, tags: String, how: String, where: Dictionary) -> Dictionary:
	var mid := String(member.get("mid", ""))
	var entry := on_wall(data, mid)
	if not entry.is_empty():
		if tags == RECOVERED:
			entry["tags"] = RECOVERED
		return entry
	var zone := String(where.get("zone", ""))
	entry = {"mid": mid, "name": String(member.get("name", "")), "callsign": String(member.get("callsign", "")),
		"role": String(member.get("role", "")), "day": int(where.get("day", 0)), "zone": zone, "zone_name": RegionMap.zone_name(zone),
		"contract": String(where.get("contract", "")), "missions": int(member.get("missions", 0)), "tags": tags, "how": how}
	memorial(data).append(entry)
	member["tags"] = tags
	return entry


## A wall entry in words, for the screen and the tests: "Reaper (Dale Okafor), Rifleman. Killed
## in action on day 12 in Harbour Yard (Hold the Line). 4 missions. Tags recovered."
static func wall_line(e: Dictionary) -> String:
	var missions := int(e.get("missions", 0))
	return "%s, %s. %s. %d mission%s. %s." % [tags_text(e), Roles.display_name(StringName(e.get("role", ""))), how_text(e),
		missions, "" if missions == 1 else "s", "Tags recovered" if String(e.get("tags", "")) == RECOVERED else "Missing: tags never recovered"]


## How, when and where a wall entry's man fell: "Killed in action on day 12 in Harbour Yard (Hold
## the Line)", "Missing, declared dead on day 19; lost on day 12 in Harbour Yard".
static func how_text(e: Dictionary) -> String:
	var where := String(e.get("zone_name", e.get("zone", "")))
	if String(e.get("contract", "")) != "":
		where += " (%s)" % String(e.contract)
	var how := String(e.get("how", "Killed in action"))
	if how.begins_with("Killed"):
		return "%s on day %d in %s" % [how, int(e.get("day", 0)), where]
	return "%s; lost on day %d in %s" % [how, int(e.get("day", 0)), where]


# --- Deaths ---------------------------------------------------------------------------------

## Whether `member` fell and his tags are still out there (missing, not yet declared dead).
static func presumed(member: Dictionary) -> bool:
	return String(member.get("status", "")) == Roster.MIA and bool(member.get("mia_dead", false))


## RosterDeployment.resolve: member `m` was killed this deployment. `tags_out`: his tags (or
## his body) came out. `where`: {"day", "zone", "contract"}. Returns whether he's recorded
## killed (true) or missing (false).
static func fell(data: Dictionary, m: Dictionary, tags_out: bool, where: Dictionary) -> bool:
	m["gear"] = {}
	m["sit_out_days"] = 0
	var zone := String(where.get("zone", ""))
	if tags_out:
		m["status"] = Roster.DEAD
		Roster.add_history(m, int(where.get("day", 0)), "Killed in action in %s; his tags came home" % zone)
		add_to_wall(data, m, RECOVERED, "Killed in action", where)
		return true
	m["status"] = Roster.MIA
	m["mia_dead"] = true
	m["mia_zone"] = zone
	m["mia_pos"] = []
	m["fell"] = where.duplicate()
	Roster.add_history(m, int(where.get("day", 0)), "Missing in action in %s: he fell, and neither his tags nor his body came out" % zone)
	return false


## Member `mid`'s tags came out on a later deployment (he fell before and was left missing, or
## was declared dead missing): "confirmed" (he's killed in action now, on the wall with his
## tags: his benefit is due), "recovered" (already on the wall as missing: now with his tags),
## "" (nothing to do).
static func tags_home(data: Dictionary, mid: String, day: int) -> String:
	var m := Roster.get_member(data, mid)
	if m.is_empty():
		return ""
	if presumed(m):
		var where: Dictionary = m.get("fell", {"day": day, "zone": m.get("mia_zone", "")})
		m["status"] = Roster.DEAD
		_clear_missing(m)
		Roster.add_history(m, day, "His tags came home: killed in action")
		add_to_wall(data, m, RECOVERED, "Killed in action", where)
		return "confirmed"
	var entry := on_wall(data, mid)
	if not entry.is_empty() and String(entry.get("tags", "")) == MISSING:
		entry["tags"] = RECOVERED
		m["tags"] = RECOVERED
		Roster.add_history(m, day, "His tags came home")
		return "recovered"
	return ""


## The missing men whose DECLARE_DAYS are up on `today`.
static func declare_due(data: Dictionary, today: int) -> Array[String]:
	var out: Array[String] = []
	for mid in Roster.ids(data):
		var m := Roster.get_member(data, mid)
		if presumed(m) and today - int((m.get("fell", {}) as Dictionary).get("day", today)) >= DECLARE_DAYS:
			out.append(mid)
	return out


## Member `mid`, missing since he fell, is declared dead (on the wall as missing). Returns
## whether he was.
static func declare_dead(data: Dictionary, mid: String, day: int) -> bool:
	var m := Roster.get_member(data, mid)
	if not presumed(m):
		return false
	var where: Dictionary = m.get("fell", {"day": day, "zone": m.get("mia_zone", "")})
	m["status"] = Roster.DEAD
	_clear_missing(m)
	Roster.add_history(m, day, "Declared dead: missing %d days" % (day - int(where.get("day", day))))
	add_to_wall(data, m, MISSING, "Missing, declared dead on day %d" % day, where)
	return true


## A live MIA member whose recovery failed or lapsed (RosterDeployment.written_off): on the
## wall as missing.
static func written_off(data: Dictionary, m: Dictionary, day: int) -> void:
	var where := {"day": day, "zone": String(m.get("mia_zone", "")), "contract": ""}
	_clear_missing(m)
	add_to_wall(data, m, MISSING, "Missing, written off", where)


static func _clear_missing(m: Dictionary) -> void:
	for key: String in ["mia_dead", "mia_zone", "mia_pos", "fell"]:
		m.erase(key)
