class_name Roster
extends RefCounted
## The company's people (wave 4, design doc "NPC squad and roster"): AI squadmates as
## persistent people, and each player's one main character. Pure functions on the campaign's
## "roster" section (Campaign.section(&"roster")), so the host, the tests and the UI all use
## the same rules; BaseHub calls them and replicates the result.
##
## The section:
## - "members": member id (String) -> member, a JSON-safe Dictionary:
##   "mid" (its id), "name" ("first surname"), "callsign" (unique in the company: the AI body's
##   node name), the person ("first", "surname" (on the name tape, unique in the company),
##   "nation" (Names), "left" (shoots left-handed), "body" (Names.MALE or FEMALE): rolled once
##   at hiring, the same in every deployment, Roster.identity),
##   "role" (a Roles id), "skills" ({aim, nerve, medical, movement}, 0..1), "xp", "missions",
##   "wage" (cash per day), "wage_factor" (what they haggled at hiring: wage = wage_for x it),
##   "gear" (an Inventory.net_state: their own kit, which deploys with them; the carrier's
##   MOLLE pouches and what's in them ride in its slot state), "status"
##   (READY, MIA or DEAD), "sit_out_days" (days left recovering), "injuries" (words),
##   "history" ([{"day", "text"}]), "hired_day", "medbay" (treated this spell already),
##   "mia_zone" (where an MIA one was left), "loadout" (optional, {} until their first
##   deployment: the kit they last deployed with, Restock.template_of, for "Restock last
##   loadout" at the base; loadout_of).
## - "players": player key -> main character: "name", "role", "gear", "sit_out_days",
##   "injuries", "history", "missions", "medbay", "loadout" (optional, as a member's).
## - "next_id": the counter member ids come from.
## - "deployment": the running deployment (RosterDeployment), {} between deployments.
##
## Skills (proposed): aim and nerve drive the squad AI's aim and reaction (SquadAI.combat)
## and how firmly it keeps orders (SquadAI.discipline); medical and movement are kept and
## grow, for the AI to use later. Wages grow with skill and missions, so veterans cost more.

const READY := "ready"
const MIA := "mia"
const DEAD := "dead"
const SKILLS: Array[String] = ["aim", "nerve", "medical", "movement"]

## Proposed: a day's wage is WAGE_BASE + WAGE_PER_SKILL x the mean skill + WAGE_PER_MISSION
## per mission survived (counted up to WAGE_MISSION_CAP).
const WAGE_BASE := 40
const WAGE_PER_SKILL := 100
const WAGE_PER_MISSION := 4
const WAGE_MISSION_CAP := 30
## Proposed: experience per mission survived, and how much each skill closes on 1.0 per
## mission (a random share between these, of what's left to learn).
const XP_PER_MISSION := 100
const SKILL_GROWTH_MIN := 0.04
const SKILL_GROWTH_MAX := 0.12
const SKILL_MAX := 0.95

## Proposed sit-out days for serious wounds (design doc: fractures, surgery and heavy blood
## loss sit them out some campaign days). The worst one counts in full, each other serious
## one adds EXTRA_INJURY_DAYS.
const FRACTURE_DAYS := 14
const SURGERY_DAYS := 10       # a clamped or internal torso bleed, a heart or chest wound
const HEAVY_BLOOD_DAYS := 6    # HEAVY_BLOOD_LOST or more of the blood lost
const MODERATE_BLOOD_DAYS := 2 # MODERATE_BLOOD_LOST or more
const RIB_DAYS := 3
const BURN_DAYS := 4           # burns over SERIOUS_BURN of the body (Vitals.burn_share)
const BLAST_LUNG_DAYS := 4     # Vitals.has_blast_lung
const EXTRA_INJURY_DAYS := 2
const SERIOUS_BURN := 0.1
const HEAVY_BLOOD_LOST := 0.3
const MODERATE_BLOOD_LOST := 0.2
## Proposed: the medbay halves what's left of a recovery (rounded up, at least a day) for
## MEDBAY_COST_PER_DAY per day it saves, once per injury.
const MEDBAY_COST_PER_DAY := 150

## Player keys and member ids are Strings; member ids look like "m0001".
const ID_FORMAT := "m%04d"

const FIRST_NAMES: Array[String] = ["Dale", "Marcus", "Eli", "Owen", "Ruben", "Tariq", "Jonah", "Viktor", "Sam", "Nadia",
	"Ana", "Kofi", "Liam", "Mateo", "Ivan", "Reza", "Cole", "Hana", "Jae", "Pieter", "Luis", "Grace", "Tomas", "Aiden",
	"Femi", "Rafael", "Yusuf", "Erik", "Maya", "Declan", "Andrei", "Kai"]
const LAST_NAMES: Array[String] = ["Mercer", "Okafor", "Brandt", "Haddad", "Novak", "Reyes", "Lindqvist", "Morrow",
	"Kowalski", "Takeda", "Duarte", "Abara", "Sorensen", "Vance", "Petrov", "Nakamura", "Quinn", "Farouk", "Holt",
	"Castillo", "Byrne", "Adeyemi", "Kaur", "Volkov", "Harlan", "Moreau", "Strand", "Osei", "Calder", "Ibarra"]
const CALLSIGNS: Array[String] = ["Hawk", "Viper", "Ghost", "Rook", "Saint", "Tank", "Ox", "Doc", "Spider", "Mako",
	"Raven", "Bishop", "Hammer", "Cobra", "Moose", "Wolf", "Jester", "Reaper", "Atlas", "Boone", "Dutch", "Nomad",
	"Smokey", "Torch", "Gunny", "Kodiak", "Lynx", "Maverick", "Patch", "Sparrow", "Tex", "Zulu", "Badger", "Coyote",
	"Falcon", "Grizzly", "Husky", "Mustang", "Ranger", "Sarge"]


# --- Members ---------------------------------------------------------------------------

static func members(data: Dictionary) -> Dictionary:
	if not data.has("members"):
		data["members"] = {}
	return data["members"]


static func players(data: Dictionary) -> Dictionary:
	if not data.has("players"):
		data["players"] = {}
	return data["players"]


static func get_member(data: Dictionary, mid: String) -> Dictionary:
	return members(data).get(mid, {})


## Member ids in hiring order.
static func ids(data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for mid: String in members(data):
		out.append(mid)
	out.sort()
	return out


## Adds a member (a Hiring candidate or a generated one) under a new id and returns that id.
## The callsign is made unique in the company (it names the AI body).
static func add_member(data: Dictionary, person: Dictionary, day: int) -> String:
	var n := int(data.get("next_id", 1))
	data["next_id"] = n + 1
	var mid := ID_FORMAT % n
	var member := person.duplicate(true)
	member["mid"] = mid
	member["callsign"] = unique_callsign(data, String(person.get("callsign", "Recruit")))
	ensure_identity(member)
	unique_surname(member, surnames(data))
	for key: String in ["xp", "missions", "sit_out_days"]:
		member[key] = int(member.get(key, 0))
	member["status"] = READY
	member["injuries"] = []
	member["history"] = []
	member["hired_day"] = day
	member["medbay"] = false
	member.erase("fee")
	member.erase("demand")
	if not member.has("gear"):
		member["gear"] = {}
	if not member.has("wage_factor"):
		member["wage_factor"] = 1.0
	member["wage"] = wage_of(member)
	members(data)[mid] = member
	add_history(member, day, "Hired as %s" % Roles.display_name(StringName(member.role)))
	return mid


## The surnames the company's members carry (the dead included), as a set.
static func surnames(data: Dictionary) -> Dictionary:
	var out := {}
	for m: Dictionary in members(data).values():
		var surname := String(m.get("surname", ""))
		if surname == "":
			var parts := String(m.get("name", "")).split(" ", false)
			surname = parts[parts.size() - 1] if not parts.is_empty() else ""
		if surname != "":
			out[surname] = true
	return out


## Fills in `member`'s person where it's missing, once: a hire from the board already has it
## (Hiring.candidate); one from a save older than that keeps the name on their roster entry
## ("Dale Okafor": first "Dale", surname "Okafor") and gets a nationality and shooting hand
## seeded by their callsign. Returns whether anything changed.
static func ensure_identity(member: Dictionary) -> bool:
	if member.has("surname") and member.has("nation") and member.has("left") and member.has("body"):
		return false
	if not member.has("surname"):
		var parts := String(member.get("name", "")).strip_edges().split(" ", false)
		member["surname"] = parts[parts.size() - 1] if not parts.is_empty() else String(member.get("callsign", "Recruit"))
		member["first"] = " ".join(parts.slice(0, parts.size() - 1)) if parts.size() > 1 else ""
	if not member.has("nation"):
		member["nation"] = String(Names.pick(&"friendly", String(member.get("callsign", "")), {}).nation)
	if not member.has("left"):
		member["left"] = Handedness.roll_ai(String(member.get("callsign", "")))
	if not member.has("body"):
		member["body"] = Names.MALE
	return true


## A new hire whose surname another member already carries (`taken`, surnames()) gets another
## from their own nationality, so no two name tapes in the company match.
static func unique_surname(member: Dictionary, taken: Dictionary) -> void:
	if not taken.has(String(member.surname)):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["surname", String(member.callsign), String(member.surname)])
	var pool: Array = Names.POOLS.get(String(member.nation), Names.US)
	for attempt in 50:
		member["surname"] = pool[rng.randi_range(0, pool.size() - 1)]
		if not taken.has(String(member.surname)):
			break
	member["name"] = ("%s %s" % [member.get("first", ""), member.surname]).strip_edges()


## A member's or candidate's person for the base screens: "US, left-handed".
static func person_text(m: Dictionary) -> String:
	if not m.has("nation"):
		return ""
	return "%s, %s" % [String(m.nation), "left-handed" if bool(m.get("left", false)) else "right-handed"]


## What a member's AI body spawns with (CompoundLevel.spawn_soldier data): the same person in
## every deployment.
static func identity(member: Dictionary) -> Dictionary:
	ensure_identity(member)
	return {"person_name": String(member.surname), "nation": String(member.nation), "left": bool(member.left),
		"body": String(member.body)}


## `wanted`, or "wanted 2", "wanted 3"... whichever no member holds yet.
static func unique_callsign(data: Dictionary, wanted: String) -> String:
	var taken := {}
	for m: Dictionary in members(data).values():
		taken[String(m.get("callsign", ""))] = true
	var callsign := wanted
	var lap := 2
	while taken.has(callsign) or callsign.is_valid_int():
		callsign = "%s %d" % [wanted, lap]
		lap += 1
	return callsign


static func add_history(person: Dictionary, day: int, text: String) -> void:
	var history: Array = person.get("history", [])
	history.append({"day": day, "text": text})
	person["history"] = history


## Ready to deploy: on the books, not MIA or dead, not recovering.
static func is_available(member: Dictionary) -> bool:
	return String(member.get("status", READY)) == READY and int(member.get("sit_out_days", 0)) <= 0


static func available_ids(data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for mid in ids(data):
		if is_available(get_member(data, mid)):
			out.append(mid)
	return out


## "Ready", "Recovering (5 d)", "MIA", "KIA".
static func status_text(person: Dictionary) -> String:
	match String(person.get("status", READY)):
		MIA:
			return "MIA"
		DEAD:
			return "KIA"
	var days := int(person.get("sit_out_days", 0))
	return "Recovering (%d d)" % days if days > 0 else "Ready"


# --- Skills and wages -------------------------------------------------------------------

static func mean_skill(skills: Dictionary) -> float:
	var total := 0.0
	for s in SKILLS:
		total += float(skills.get(s, 0.0))
	return total / SKILLS.size()


## A day's wage for these skills and missions, before what they haggled (wage_factor).
static func wage_for(skills: Dictionary, missions: int) -> int:
	return roundi(WAGE_BASE + WAGE_PER_SKILL * mean_skill(skills) + WAGE_PER_MISSION * mini(missions, WAGE_MISSION_CAP))


static func wage_of(member: Dictionary) -> int:
	return roundi(wage_for(member.get("skills", {}), int(member.get("missions", 0))) * float(member.get("wage_factor", 1.0)))


## What the company pays in wages per day: every member still on the books (MIA ones too,
## until they're found or written off; the dead cost nothing).
static func daily_wages(data: Dictionary) -> int:
	var total := 0
	for m: Dictionary in members(data).values():
		if String(m.get("status", READY)) != DEAD:
			total += int(m.get("wage", 0))
	return total


## The squad AI's stats for this member: SquadAI.combat (aim error and reaction) from aim,
## SquadAI.discipline (keeping orders under fire) from nerve. Proposed mapping.
static func ai_stats(member: Dictionary) -> Dictionary:
	var skills: Dictionary = member.get("skills", {})
	return {"combat": 0.3 + 0.6 * float(skills.get("aim", 0.4)), "discipline": 0.3 + 0.6 * float(skills.get("nerve", 0.4))}


## A member came back from a mission alive: experience, a mission more, every skill closes
## on SKILL_MAX by a random share, and the wage follows (it only ever grows).
static func after_mission(member: Dictionary, rng: RandomNumberGenerator, day: int, what := "a deployment") -> void:
	member["missions"] = int(member.get("missions", 0)) + 1
	member["xp"] = int(member.get("xp", 0)) + XP_PER_MISSION
	var skills: Dictionary = member.get("skills", {})
	for s in SKILLS:
		var v := float(skills.get(s, 0.4))
		skills[s] = minf(v + (SKILL_MAX - v) * rng.randf_range(SKILL_GROWTH_MIN, SKILL_GROWTH_MAX), SKILL_MAX)
	member["skills"] = skills
	member["wage"] = maxi(int(member.get("wage", 0)), wage_of(member))
	add_history(member, day, "Came back from %s" % what)


# --- Injuries and recovery --------------------------------------------------------------

## The serious injuries in a body's wounds (Vitals.wound_list()), blood (Vitals.blood_fraction()),
## burns (Vitals.burn_share()) and blast lung (Vitals.has_blast_lung()), and the days they sit
## out: {"days": int, "injuries": Array[String]}. Minor wounds (grazes, muscle and venous
## wounds, light blood loss, small burns) cost nothing.
static func assess_injuries(wounds: Array, blood_fraction: float, burn := 0.0, blast_lung := false) -> Dictionary:
	var found: Array = []  # [days, words]
	for w: Dictionary in wounds:
		var where := Vitals.part_name(StringName(w.get("part", &"")))
		match String(w.get("kind", "")):
			"fracture":
				var bone := String(w.get("name", ""))  # a BodyMap.BONES id ("tibia_l")
				found.append([FRACTURE_DAYS, "broken %s" % (Vitals.part_name(StringName(bone)).replace(" bones", "") if bone != "" else "bone")])
			"internal", "heart", "chest", "brain":
				found.append([SURGERY_DAYS, "surgery (%s)" % where])
			"arterial", "junctional":
				if w.get("clamped", false):
					found.append([SURGERY_DAYS, "surgery (%s)" % where])
			"rib":
				found.append([RIB_DAYS, "cracked rib"])
	if burn >= SERIOUS_BURN:
		found.append([BURN_DAYS, "burns"])
	if blast_lung:
		found.append([BLAST_LUNG_DAYS, "blast lung"])
	var lost := 1.0 - blood_fraction
	if lost >= HEAVY_BLOOD_LOST:
		found.append([HEAVY_BLOOD_DAYS, "heavy blood loss"])
	elif lost >= MODERATE_BLOOD_LOST:
		found.append([MODERATE_BLOOD_DAYS, "blood loss"])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var days := 0
	var words: Array[String] = []
	for i in found.size():
		days += int(found[i][0]) if i == 0 else EXTRA_INJURY_DAYS
		if String(found[i][1]) not in words:
			words.append(String(found[i][1]))
	return {"days": days, "injuries": words}


## assess_injuries for an outcome as BaseHub records one: {"wounds", "blood", "burn",
## "blast_lung"} (the last two may be missing).
static func assess_outcome(o: Dictionary) -> Dictionary:
	return assess_injuries(o.get("wounds", []), float(o.get("blood", 1.0)), float(o.get("burn", 0.0)), bool(o.get("blast_lung", false)))


## Puts a body's injuries on a member or main character: they sit out the days (the longer
## of what's left and the new), and the injuries go on their record.
static func injure(person: Dictionary, assessment: Dictionary, day: int) -> void:
	var days := int(assessment.get("days", 0))
	if days <= 0:
		return
	person["sit_out_days"] = maxi(int(person.get("sit_out_days", 0)), days)
	person["medbay"] = false
	var injuries: Array = person.get("injuries", [])
	for words: String in assessment.get("injuries", []):
		injuries.append(words)
	person["injuries"] = injuries
	add_history(person, day, "Wounded: %s (%d days)" % [", ".join(PackedStringArray(assessment.get("injuries", []))), days])


## What the medbay would do for someone now: {"days_saved", "cost"}, or {} if nothing (not
## recovering, or already treated this spell).
static func medbay_quote(person: Dictionary) -> Dictionary:
	var left := int(person.get("sit_out_days", 0))
	if left <= 0 or person.get("medbay", false) or String(person.get("status", READY)) != READY:
		return {}
	var saved := maxi(ceili(left / 2.0), 1)
	return {"days_saved": saved, "cost": saved * MEDBAY_COST_PER_DAY}


## Applies a medbay treatment (the caller has charged the quote). Returns the days saved.
static func medbay_treat(person: Dictionary, day: int) -> int:
	var quote := medbay_quote(person)
	if quote.is_empty():
		return 0
	person["sit_out_days"] = int(person.sit_out_days) - int(quote.days_saved)
	person["medbay"] = true
	add_history(person, day, "Treated in the medbay (%d days sooner)" % int(quote.days_saved))
	if int(person.sit_out_days) <= 0:
		_recovered(person, day)
	return int(quote.days_saved)


## Days pass: everyone recovering gets that much better.
static func advance_days(data: Dictionary, days: int, day: int) -> void:
	for person: Dictionary in members(data).values() + players(data).values():
		var left := int(person.get("sit_out_days", 0))
		if left <= 0:
			continue
		person["sit_out_days"] = maxi(left - days, 0)
		if int(person.sit_out_days) == 0:
			_recovered(person, day)


static func _recovered(person: Dictionary, day: int) -> void:
	person["sit_out_days"] = 0
	person["injuries"] = []
	person["medbay"] = false
	add_history(person, day, "Fit for duty")


# --- Players' main characters -----------------------------------------------------------

## The main character for player `key`, made the first time they're seen (design doc: one
## main character per player).
static func main_character(data: Dictionary, key: String, role: StringName = Roles.RIFLEMAN) -> Dictionary:
	var all := players(data)
	if not all.has(key):
		all[key] = {"name": key, "role": String(role), "gear": {}, "sit_out_days": 0, "injuries": [], "history": [],
			"missions": 0, "medbay": false, "status": READY}
	return all[key]


## Whether a player's main character must sit this deployment out.
static func main_recovering(data: Dictionary, key: String) -> bool:
	return players(data).has(key) and int(players(data)[key].get("sit_out_days", 0)) > 0


# --- Gear -------------------------------------------------------------------------------

## A member's or main character's last deployed loadout (Restock), {} if none was recorded
## (a save from before loadouts, or nobody deployed yet): the field is optional.
static func loadout_of(person: Dictionary) -> Dictionary:
	return person.get("loadout", {})


## Writes down `person`'s kit (an Inventory.net_state) as their last loadout; an empty kit
## leaves the last one as it was.
static func record_loadout(person: Dictionary, gear: Dictionary) -> void:
	var loadout := Restock.template_of(gear)
	if not Restock.is_blank(loadout):
		person["loadout"] = loadout


## An Inventory.net_state holding `kit` ([item id, count] pairs, as Roles.kit gives them).
static func gear_for_kit(kit: Array) -> Dictionary:
	var inv := Inventory.new()
	for pair: Array in kit:
		inv.take(StringName(pair[0]), int(pair[1]))
	var state := inv.net_state.duplicate(true)
	inv.free()
	return json_safe(state)


## A copy of an Inventory.net_state with every StringName as a String, so it saves and
## compares the same before and after a JSON round trip (GameState.from_json turns them back).
static func json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_STRING_NAME:
			return String(value)
		TYPE_ARRAY:
			return (value as Array).map(func(v: Variant) -> Variant: return json_safe(v))
		TYPE_DICTIONARY:
			var out := {}
			for key: Variant in value:
				out[String(key) if typeof(key) == TYPE_STRING_NAME else key] = json_safe(value[key])
			return out
	return value


## Every item in an Inventory.net_state, as {item id (String): count}: what's worn and stowed,
## and what's on a carrier's MOLLE points and in its pouches (worn or stowed), since pouch
## contents travel in the carrier's state (Inventory, "MOLLE").
static func gear_counts(gear: Dictionary) -> Dictionary:
	var out := {}
	var slot_state: Dictionary = gear.get("slot_state", {})
	for slot: Variant in gear.get("slots", {}):
		var id := String(gear.slots[slot])
		if id != "":
			out[id] = int(out.get(id, 0)) + 1
			count_state(slot_state.get(slot, {}), 1, out)
	for container: Variant in gear.get("containers", {}):
		for entry: Dictionary in gear.containers[container]:
			count_entry(entry, out)
	var hands := String(gear.get("hands", ""))
	if hands != "":
		out[hands] = int(out.get(hands, 0)) + 1
	return out


## Adds an entry ({"id", "count", "state"?}) and whatever its state carries to `out`
## ({item id (String): count}).
static func count_entry(entry: Dictionary, out: Dictionary) -> void:
	var n := int(entry.get("count", 1))
	out[String(entry.id)] = int(out.get(String(entry.id), 0)) + n
	count_state(entry.get("state", {}), n, out)


## Adds what an item's state carries, `n` times over, to `out`: a carrier's attachments and
## their contents ("molle"), a detached pouch's contents ("held").
static func count_state(state: Dictionary, n: int, out: Dictionary) -> void:
	var held: Array = state.get("held", []).duplicate()
	var molle: Dictionary = state.get("molle", {})
	for point: Variant in molle:
		var att: Dictionary = molle[point]
		if String(att.get("id", "")) != "":
			out[String(att.id)] = int(out.get(String(att.id), 0)) + n
		held.append_array(att.get("held", []))
	for entry: Dictionary in held:
		var inside := {}
		count_entry(entry, inside)
		for id: String in inside:
			out[id] = int(out.get(id, 0)) + int(inside[id]) * n
