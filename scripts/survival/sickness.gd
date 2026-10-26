class_name Sickness
extends RefCounted
## The sicknesses (docs/survival_medical.md sections 2, 5 and 11, call 81) past Needs' dysentery
## and food poisoning: colds, flu and pneumonia (from cold, wet and crowding; a cough is noise for
## the stealth model; they spread between people living together: spread), tetanus (from rusty
## metal: Infection.server_rusty), the deficiency illnesses (scurvy, rickets, anaemia after weeks
## short of vitamin C, D or iron), a transfusion reaction (blood types on every body) and the
## fever they bring. Kept in the body's Dictionary (Needs' stores) as "ills": {id: {"h", "left_h",
## "onset_h", "sev"}}, "chill_h", "def" ({"c", "d", "iron"}: world hours at empty), "blood_type".
## Static and pure but for the server_ calls: testable without a body.

## Proposed. hours: how long it runs once it shows (-1: while the cause lasts); onset: hidden
## hours first; stamina: the share of stamina return left; sway: aim sway added; fever: the core
## it holds you at; kcal/water: extra lost a world day; spread: the chance a world hour each sick
## person gives it to each other person living with them (doubled sharing bunks); cough: it makes
## noise; sev_h: world hours from nothing to death untreated (the dangerous ones).
const ILLS := {
	"cold": {"name": "a cold", "hours": 72.0, "onset": 12.0, "stamina": 0.9, "sway": 0.0, "fever": 0.0, "kcal": 0.0, "water": 0.2, "spread": 0.03, "cough": true,
		"start": "A scratchy throat, a cough: a cold"},
	"flu": {"name": "flu", "hours": 96.0, "onset": 24.0, "stamina": 0.5, "sway": 0.4, "fever": 38.4, "kcal": 300.0, "water": 0.6, "spread": 0.05, "cough": true,
		"start": "Aching, shivering, burning: flu. Rest it out"},
	"pneumonia": {"name": "pneumonia", "hours": 240.0, "onset": 0.0, "stamina": 0.4, "sway": 0.5, "fever": 38.9, "kcal": 400.0, "water": 0.6, "spread": 0.01, "cough": true,
		"sev_h": 120.0, "start": "Every breath rattles: pneumonia. Antibiotics and warmth, or it kills"},
	"tetanus": {"name": "tetanus", "hours": 336.0, "onset": 120.0, "stamina": 0.5, "sway": 0.8, "fever": 38.0, "kcal": 0.0, "water": 0.0, "spread": 0.0, "cough": false,
		"sev_h": 168.0, "start": "Your jaw locks, your back arches: tetanus"},
	"scurvy": {"name": "scurvy", "hours": -1.0, "onset": 0.0, "stamina": 0.7, "sway": 0.0, "fever": 0.0, "kcal": 0.0, "water": 0.0, "spread": 0.0, "cough": false,
		"start": "Bleeding gums, old cuts opening: scurvy. You need fruit or greens"},
	"rickets": {"name": "rickets", "hours": -1.0, "onset": 0.0, "stamina": 0.85, "sway": 0.0, "fever": 0.0, "kcal": 0.0, "water": 0.0, "spread": 0.0, "cough": false,
		"start": "Your bones ache: no sun, no vitamin D"},
	"anaemia": {"name": "anaemia", "hours": -1.0, "onset": 0.0, "stamina": 0.65, "sway": 0.2, "fever": 0.0, "kcal": 0.0, "water": 0.0, "spread": 0.0, "cough": false,
		"start": "Pale and dizzy: anaemia. Meat, liver, greens"},
	"transfusion_reaction": {"name": "a transfusion reaction", "hours": 8.0, "onset": 0.0, "stamina": 0.5, "sway": 0.4, "fever": 39.0, "kcal": 0.0, "water": 0.0, "spread": 0.0, "cough": false,
		"start": "Wrong blood: chills, fever, your back on fire"},
}
const CONTAGIOUS: Array[String] = ["cold", "flu", "pneumonia"]
## Catching cold: world hours chilled (shivering, or wet and cool) to a cold, then more to pneumonia.
const CHILL_COLD_H := 8.0
const CHILL_PNEU_H := 24.0
## Deficiencies: world hours with the store at empty before the illness (scurvy and anaemia two
## weeks, rickets three), and the store that ends it.
const DEF_H := {"c": 336.0, "d": 504.0, "iron": 336.0}
const DEF_ILL := {"c": "scurvy", "d": "rickets", "iron": "anaemia"}
const DEF_STORE := {"c": "vitamin_c", "d": "vitamin_d", "iron": "iron"}
const DEF_CURED := 30.0
## Blood types and their share of people (Proposed: the usual spread).
const BLOOD_TYPES := {"O+": 38.0, "A+": 34.0, "B+": 9.0, "AB+": 3.0, "O-": 7.0, "A-": 6.0, "B-": 2.0, "AB-": 1.0}
## A found bag of blood: universal donor unless its state says (Proposed).
const BAG_TYPE := "O-"
## A reaction to the wrong blood: trauma on the spot (Vitals.server_damage).
const REACTION_DAMAGE := 25.0
## A cough: heard by the dead COUGH_M away, at COUGH_LOUD (ZombieAI.hear), every COUGH_EVERY_H world hours.
const COUGH_M := 12.0
const COUGH_LOUD := 0.35
const COUGH_EVERY_H := 0.3
## Tests: a roll to use instead of randf() (-1: roll for real).
static var force_roll := -1.0


static func _roll() -> float:
	return force_roll if force_roll >= 0.0 else randf()


static func ills(n: Dictionary) -> Dictionary:
	if not n.get("ills") is Dictionary:
		n["ills"] = {}
	return n["ills"]


## Whether `id` has started on `n` (shown or still hidden).
static func has(n: Dictionary, id: String) -> bool:
	return ills(n).has(id)


## Whether `id` shows on `n` (past its onset).
static func shows(n: Dictionary, id: String) -> bool:
	var d: Dictionary = ills(n).get(id, {})
	return not d.is_empty() and float(d.get("onset_h", 0.0)) <= 0.0


## Starts `id` on `n` (nothing if already there). Returns whether it started.
static func start(n: Dictionary, id: String) -> bool:
	if not ILLS.has(id) or has(n, id):
		return false
	var row: Dictionary = ILLS[id]
	ills(n)[id] = {"h": 0.0, "left_h": float(row.hours), "onset_h": float(row.onset), "sev": 0.0}
	if float(row.onset) <= 0.0:
		_announce(n, String(row.start))
	return true


static func end(n: Dictionary, id: String) -> void:
	ills(n).erase(id)


## The ids of what shows on `n`, for the readout and the body screen.
static func shown(n: Dictionary) -> Array:
	var out: Array = []
	for id: String in ills(n):
		if shows(n, id):
			out.append(id)
	return out


## Whether `n` coughs (a cold, flu or pneumonia showing).
static func coughing(n: Dictionary) -> bool:
	for id: String in CONTAGIOUS:
		if shows(n, id):
			return true
	return false


# --- Stepping ------------------------------------------------------------------------------

## World hours of `n`'s sicknesses in `ctx` ("abx": an antibiotic course covering). Returns
## "death" when one kills (n.killed_by says which), else "".
static func step(n: Dictionary, world_h: float, ctx := {}) -> String:
	var shiver := Needs.shivering(n)
	var chilled := shiver > 0.3 or (float(n.get("wet", 0.0)) > 0.5 and float(n.get("warmth", Needs.NORMAL_C)) < 36.6)
	n.chill_h = float(n.get("chill_h", 0.0)) + world_h if chilled else maxf(0.0, float(n.get("chill_h", 0.0)) - 0.5 * world_h)
	if float(n.chill_h) >= CHILL_COLD_H and not (has(n, "cold") or has(n, "flu") or has(n, "pneumonia")):
		start(n, "cold")
		(ills(n)["cold"] as Dictionary)["onset_h"] = 0.0
		_announce(n, String(ILLS.cold.start))
	elif float(n.chill_h) >= CHILL_PNEU_H and shows(n, "cold") and not has(n, "pneumonia"):
		end(n, "cold")
		start(n, "pneumonia")
	_deficiencies(n, world_h)
	var abx := bool(ctx.get("abx", false))
	var warm := float(n.get("warmth", Needs.NORMAL_C)) >= 36.5 and not chilled
	var killed := ""
	for id: String in ills(n).keys():
		var d: Dictionary = ills(n)[id]
		var row: Dictionary = ILLS.get(id, {})
		if float(d.get("onset_h", 0.0)) > 0.0:
			d.onset_h = float(d.onset_h) - world_h
			if float(d.onset_h) <= 0.0:
				d.onset_h = 0.0
				_announce(n, String(row.get("start", "")))
			continue
		d.h = float(d.get("h", 0.0)) + world_h
		var days := world_h / 24.0
		n.calories = maxf(0.0, float(n.get("calories", 0.0)) - float(row.get("kcal", 0.0)) * days)
		n.water = maxf(0.0, float(n.get("water", 0.0)) - float(row.get("water", 0.0)) * days)
		if row.has("sev_h"):
			var treated := abx and (warm or id == "tetanus")
			d.sev = clampf(float(d.get("sev", 0.0)) + (-1.0 if treated else 1.0) * world_h / float(row.sev_h), 0.0, 1.0)
			if float(d.sev) >= 1.0:
				killed = id
		if float(row.get("hours", -1.0)) > 0.0:
			d.left_h = float(d.left_h) - world_h
			if float(d.left_h) <= 0.0 and float(d.get("sev", 0.0)) < 0.5:
				end(n, id)
	if killed != "":
		n["killed_by"] = killed
		return "death"
	return ""


## Weeks short of a vitamin: the illness; eating it back ends it.
static func _deficiencies(n: Dictionary, world_h: float) -> void:
	if not n.get("def") is Dictionary:
		n["def"] = {}
	var def: Dictionary = n["def"]
	for k: String in DEF_H:
		var store := float(n.get(String(DEF_STORE[k]), 100.0))
		if store <= 0.0:
			def[k] = float(def.get(k, 0.0)) + world_h
			if float(def[k]) >= float(DEF_H[k]):
				start(n, String(DEF_ILL[k]))
		else:
			def[k] = maxf(0.0, float(def.get(k, 0.0)) - world_h)
			if store >= DEF_CURED and has(n, String(DEF_ILL[k])):
				end(n, String(DEF_ILL[k]))
				def[k] = 0.0


# --- Effects ---------------------------------------------------------------------------------

## Stamina return's share left by what shows.
static func stamina_mult(n: Dictionary) -> float:
	var m := 1.0
	for id: String in shown(n):
		m *= float((ILLS.get(id, {}) as Dictionary).get("stamina", 1.0))
	return m


static func sway_add(n: Dictionary) -> float:
	var a := 0.0
	for id: String in shown(n):
		a += float((ILLS.get(id, {}) as Dictionary).get("sway", 0.0))
	return a


## The core a sickness holds the body at (0: none).
static func fever_c(n: Dictionary) -> float:
	var c := 0.0
	for id: String in shown(n):
		c = maxf(c, float((ILLS.get(id, {}) as Dictionary).get("fever", 0.0)))
	return c


# --- Spreading ------------------------------------------------------------------------------

## `world_h` hours of people living together (a settlement's settlers and companions, a shared
## room): each contagious sickness showing on one has its spread chance an hour to start on each
## other (`bunks`: sharing bunks doubles it). `bodies` are their needs Dictionaries. Returns how
## many caught something.
static func spread(bodies: Array, world_h: float, bunks := false) -> int:
	var caught := 0
	var sick_now: Array = []
	for n: Dictionary in bodies:
		for id: String in CONTAGIOUS:
			if shows(n, id):
				sick_now.append([n, id])
	for pair: Array in sick_now:
		var src: Dictionary = pair[0]
		var id := String(pair[1])
		var p := float((ILLS[id] as Dictionary).spread) * (2.0 if bunks else 1.0)
		var chance := 1.0 - pow(1.0 - p, world_h)
		for n: Dictionary in bodies:
			if is_same(n, src):
				continue
			var gives := "flu" if id == "pneumonia" else id  # pneumonia passes on as flu
			if has(n, gives) or (gives == "cold" and (has(n, "flu") or has(n, "pneumonia"))):
				continue
			if _roll() < chance:
				start(n, gives)
				caught += 1
	return caught


## Host: spreading among the records of the people living together (SurvivorsLayer's hour).
static func server_spread_people(records: Array, world_h: float) -> int:
	var bodies: Array = []
	for rec: Dictionary in records:
		if String(rec.get("status", "")) in ["companion", "settler"] and rec.get("needs") is Dictionary:
			bodies.append(rec.needs)
	return spread(bodies, world_h, true) if bodies.size() > 1 else 0


# --- Coughing --------------------------------------------------------------------------------

## Host: `s` coughs: a small noise for the dead (Survival.server_noise).
static func server_cough(s: Soldier) -> void:
	if s == null or not s.is_inside_tree():
		return
	Survival.server_noise(s, s.global_position, COUGH_M, COUGH_LOUD)


# --- Blood -----------------------------------------------------------------------------------

## `n`'s blood type, rolled the first time it's asked (BLOOD_TYPES' shares).
static func blood_type(n: Dictionary) -> String:
	if String(n.get("blood_type", "")) == "":
		var total := 0.0
		for t: String in BLOOD_TYPES:
			total += float(BLOOD_TYPES[t])
		var r := randf() * total
		var pick := "O+"
		for t: String in BLOOD_TYPES:
			r -= float(BLOOD_TYPES[t])
			if r <= 0.0:
				pick = t
				break
		n["blood_type"] = pick
	return String(n.blood_type)


## Whether `donor` blood can go into `recipient` (ABO and Rh).
static func compatible(donor: String, recipient: String) -> bool:
	var d_abo := donor.trim_suffix("+").trim_suffix("-")
	var r_abo := recipient.trim_suffix("+").trim_suffix("-")
	if donor.ends_with("+") and recipient.ends_with("-"):
		return false
	return d_abo == "O" or d_abo == r_abo or r_abo == "AB"


## Blood of `donor_type` into the body `n`: true and a reaction when it's the wrong type.
static func transfuse(n: Dictionary, donor_type: String) -> bool:
	if compatible(donor_type, blood_type(n)):
		return false
	start(n, "transfusion_reaction")
	return true


## Host: a bag of blood went into `s` (the treatment's hook, Body.on_treated): its type from the
## bag's `state` (BAG_TYPE when the bag says nothing); the wrong one reacts.
static func server_transfused(s: Soldier, state := {}) -> bool:
	var n := Survival.needs_of(s)
	if not transfuse(n, String(state.get("blood_type", BAG_TYPE))):
		return false
	s.vitals.server_damage(REACTION_DAMAGE)
	return true


static func _announce(n: Dictionary, line: String) -> void:
	if line == "":
		return
	n["_announce"] = (String(n._announce) + ". " + line) if n.has("_announce") else line
