class_name InjuryText
extends RefCounted
## The medical menu's injuries in words (Captain, 2026-10-21: "injury descriptions in the medical
## helper (H) need to be improved too"), read the way an ACE3 / KAT medic reads a casualty: worst
## first, each one saying
## - where, plainly ("Left thigh, inner", "Chest, right side", "Neck"), from the wound's entry
##   point (Vitals.wound_list "at", rest pose) against the part's middle (BodyMap.PART_BOXES);
## - what, in medic language: arterial bleed (spurting), venous bleed (steady), graze, gunshot or
##   fragment wound, through-and-through, fracture (open or closed), traumatic amputation, open
##   chest wound, tension pneumothorax, blast lung, head injury, burns, internal bleeding;
## - how bad (SEVERITY: minor, serious, critical, life-threatening, each its colour) and, for a
##   bleed, how fast in words ("bleeding out in about 2 min": bleed_out_text);
## - what's been done (tourniquet on and how long ago, from the shared triage log; packed,
##   bandaged, splinted, sealed, needle in, line in);
## - what to do next: the items that treat it, in order ("Tourniquet above the wound, then pack
##   and bandage"), each marked carried or not.
## Plus what isn't one wound (cardiac arrest, a blocked airway, blood loss needing a line and
## fluids, blast lung, burns, cold, a concussion, pain), and the vitals at a glance (summary).
## Static and read-only over Vitals (replicated), so every peer reads the same.

## Severity, 0..3, its word and its colour (the kit's palette: treated and minor green, then
## the accent, the warning red, the strong red).
const MINOR := 0
const SERIOUS := 1
const CRITICAL := 2
const LIFE_THREATENING := 3
const SEVERITY_WORDS: Array[String] = ["Minor", "Serious", "Critical", "Life-threatening"]
const SEVERITY_COLORS: Array[Color] = [UiKit.GOOD, UiKit.ACCENT, UiKit.WARN, UiKit.BAD]
## A bleed this fast (L/min at full blood) is heavy, this one steady; slower oozes.
const HEAVY_RATE := 0.8
const STEADY_RATE := 0.2
## How far off the part's middle (m, rest pose) a wound has to be to get a side ("inner", "front").
const SIDE_M := 0.02
## The trunk's sides: this far off the middle line (m) is its right or left side.
const TRUNK_SIDE_M := 0.06
## What to do for each kind of task, in order: [item id, words]. An id of &"" is advice with no item.
const STEPS := {
	"arterial": [[&"tourniquet", "Tourniquet high above the wound"], [&"hemostatic_gauze", "then pack it"], [&"pressure_bandage", "and bandage"]],
	"amputation": [[&"tourniquet", "Tourniquet high on the stump"], [&"hemostatic_gauze", "then pack"], [&"pressure_bandage", "and bandage it"]],
	"held": [[&"hemostatic_gauze", "Pack the wound"], [&"pressure_bandage", "bandage it, then the tourniquet can come off"]],
	"rushed": [[&"tourniquet", "Second tourniquet beside the first"]],
	"junctional": [[&"hemostatic_gauze", "Pack it with gauze"], [&"pressure_bandage", "then a pressure bandage"]],
	"neck": [[&"hemostatic_gauze", "Pack and hold pressure"], [&"surgical_clamp", "clamp (medic); evacuate"]],
	"venous": [[&"pressure_bandage", "Pressure bandage"]],
	"open_fracture": [[&"pressure_bandage", "Bandage the wound"], [&"splint", "then splint"]],
	"muscle": [[&"pressure_bandage", "Pressure bandage"]],
	"graze": [[&"pressure_bandage", "Bandage it"]],
	"internal": [[&"surgical_clamp", "Surgical clamp (medic)"], [&"saline_500", "fluids meanwhile"]],
	"heart": [[&"surgical_clamp", "Surgical clamp (medic), now"]],
	"chest": [[&"chest_seal", "Vented chest seal over the hole"]],
	"tension": [[&"decompression_needle", "Needle at the 2nd rib space, mid-collarbone"]],
	"collapsed": [[&"", "Watch the breathing; needle it if it gets worse"]],
	"fracture": [[&"splint", "Splint it"]],
	"pelvis": [[&"pelvic_binder", "Pelvic binder"]],
	"rib": [[&"morphine", "Morphine for the pain"]],
	"brain": [[&"npa", "Keep the airway open"], [&"", "evacuate"]],
	"airway": [[&"npa", "NPA up the nose"]],
	"arrest": [[&"cpr", "CPR"], [&"epinephrine", "epinephrine"], [&"defibrillator", "shock"]],
	"access": [[&"iv_18", "IV (forearm or lower leg) or IO"]],
	"fluids": [[&"saline_500", "Hang fluids or blood"]],
	"pressure": [[&"pressure_bag", "Pressure bag on the line"]],
	"blast_lung": [[&"", "No field fix: keep him still, evacuate"]],
	"burn": [[&"burn_dressing", "Burn dressings"]],
	"burn_fluids": [[&"burn_dressing", "Burn dressings"], [&"saline_500", "fluids"]],
	"hypothermia": [[&"hypothermia_blanket", "Wrap him in a blanket"]],
	"concussion": [[&"", "Keep him down; evacuate if it gets worse"]],
	"pain": [[&"morphine", "Morphine"]],
	"racing": [[&"adenosine", "Adenosine"]],
	"slow_heart": [[&"atropine", "Atropine"]],
	"wake": [[&"epinephrine", "Epinephrine to bring him round"]],
}
## Kinds whose bleeding is told as spurting, steady or oozing.
const BLEED_WORDS := {"arterial": "spurting", "junctional": "pouring", "venous": "steady", "muscle": "steady", "graze": "oozing", "internal": "inside"}


## Every injury and condition on `vitals`, worst first: [{"part", "kind", "severity",
## "where", "what", "bleed" (words, or ""), "done" (words, or ""), "next" ([{"item", "text",
## "carried"}, ...]), "order" (its place in the care order)}]. `carries` (a Callable taking an item
## id, or an empty one: nobody's kit) marks each next item carried or not.
static func injuries(vitals: Vitals, carries := Callable()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if vitals == null or vitals.is_dead():
		return out
	var tq: Dictionary = vitals.tourniquets()
	var care := vitals.care_log()
	var tension := vitals.has_tension()
	for w: Dictionary in vitals.wound_list():
		out.append(_wound_entry(vitals, w, tq, care, tension, carries))
	out.append_array(_conditions(vitals, carries))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.severity != b.severity:
			return a.severity > b.severity
		if a.order != b.order:
			return a.order < b.order
		return float(a.get("rate", 0.0)) > float(b.get("rate", 0.0)))
	return out


## The injuries on body part `p` only (injuries' order).
static func injuries_on(vitals: Vitals, p: StringName, carries := Callable()) -> Array[Dictionary]:
	return injuries(vitals, carries).filter(func(e: Dictionary) -> bool: return e.part == p)


## One line for the triage list: "Left thigh, inner: arterial bleed, spurting".
static func line(entry: Dictionary) -> String:
	var text := "%s: %s" % [entry.where, entry.what]
	if String(entry.bleed) != "":
		text += ", " + String(entry.bleed)
	return text


## The next steps as one line: "Tourniquet high above the wound, then pack it and bandage".
static func next_text(entry: Dictionary) -> String:
	var parts := PackedStringArray()
	for step: Dictionary in entry.next:
		parts.append(String(step.text))
	return ", ".join(parts)


# --- One wound -----------------------------------------------------------------------------

static func _wound_entry(vitals: Vitals, w: Dictionary, tq: Dictionary, care: Array[Dictionary], tension: bool, carries: Callable) -> Dictionary:
	var kind := String(w.kind)
	var part: StringName = w.part
	var rate := float(w.rate)
	var bleeding: bool = w.bleeding
	var treated: bool = w.treated
	var amputation := StringName(w.get("name", &"")) == Vitals.AMPUTATION
	var bone := String(w.get("name", ""))
	var held := not bleeding and bool(w.get("tourniquet", false)) and rate > 0.0 and not treated and not bool(w.get("packed", false))
	var what := _what(w, tension)
	var severity := MINOR
	var steps := ""
	match kind:
		"arterial":
			if amputation:
				steps = "amputation" if bleeding else ("held" if held else "")
			elif bleeding and bool(w.get("tourniquet", false)):
				steps = "rushed"
			elif bleeding:
				steps = "arterial"
			elif held:
				steps = "held"
			severity = LIFE_THREATENING if bleeding else (SERIOUS if held else MINOR)
		"junctional":
			var neck := part == Vitals.NECK
			steps = ("neck" if neck else "junctional") if bleeding or (neck and not w.get("clamped", false)) else ""
			severity = LIFE_THREATENING if bleeding else (CRITICAL if neck and not w.get("clamped", false) else MINOR)
		"internal":
			steps = "" if w.get("clamped", false) else "internal"
			severity = MINOR if w.get("clamped", false) else CRITICAL
		"heart":
			steps = "" if w.get("clamped", false) else "heart"
			severity = MINOR if w.get("clamped", false) else LIFE_THREATENING
		"brain":
			steps = "brain"
			severity = LIFE_THREATENING
		"chest":
			if w.get("pneumo", false):
				steps = "tension" if w.get("tension", false) or tension else "collapsed"
				severity = LIFE_THREATENING if w.get("tension", false) or tension else SERIOUS
			else:
				steps = "tension" if w.get("tension", false) else ("" if treated or w.get("closed", false) else "chest")
				severity = LIFE_THREATENING if w.get("tension", false) else (MINOR if treated or w.get("closed", false) else CRITICAL)
		"venous", "muscle", "graze":
			var open_bone := kind == "venous" and BodyMap.BONES.has(StringName(bone))
			steps = ("open_fracture" if open_bone else kind) if not treated else ""
			severity = MINOR if treated or not bleeding else (CRITICAL if rate >= HEAVY_RATE else (SERIOUS if kind != "graze" else MINOR))
		"fracture":
			var pelvis := bone == "pelvis"
			if not treated:
				steps = "pelvis" if pelvis else ("open_fracture" if w.get("open", false) and not w.get("bandaged", false) else "fracture")
			elif w.get("open", false) and not w.get("bandaged", false):
				steps = "graze"
			severity = (CRITICAL if pelvis else SERIOUS) if not treated else MINOR
		"rib":
			steps = "" if treated else "rib"
			severity = MINOR
	var entry := {"part": part, "kind": kind, "severity": severity, "where": where(w), "what": what,
		"bleed": _bleed_words(kind, rate, bleeding), "done": _done(w, tq, care, part), "rate": rate if bleeding else 0.0,
		"order": _order(kind if not (amputation or held) else "arterial"), "next": _steps(steps, carries)}
	return entry


## What a wound is, in medic language.
static func _what(w: Dictionary, tension: bool) -> String:
	var kind := String(w.kind)
	var bone := String(w.get("name", ""))
	var how := ""  # what made it, and whether it went through
	if w.get("out") is Vector3:
		how = "through-and-through"
	elif StringName(w.get("round_class", &"")) == Vitals.FRAGMENT:
		how = "fragment wound"
	elif w.get("at") is Vector3:
		how = "gunshot wound"
	if StringName(w.get("name", &"")) == Vitals.AMPUTATION:
		return "traumatic amputation, arterial bleed"
	match kind:
		"arterial":
			return _with("arterial bleed", how)
		"junctional":
			return _with("junctional bleed", how)
		"venous":
			if BodyMap.BONES.has(StringName(bone)):
				return "open fracture, bleeding"
			return _with("venous bleed", how)
		"muscle":
			return _with("muscle wound", how)
		"graze":
			return "graze"
		"internal":
			return "internal bleeding"
		"heart":
			return _with("heart wound", how)
		"brain":
			return _with("head injury (brain)", how)
		"rib":
			return "cracked rib"
		"chest":
			if w.get("pneumo", false):
				return "tension pneumothorax (collapsed lung)" if w.get("tension", false) or tension else "collapsed lung"
			return "open chest wound, tension pneumothorax" if w.get("tension", false) else _with("open chest wound (sucking)", how)
		"fracture":
			var which := "pelvis" if bone == "pelvis" else ("collarbone" if bone.begins_with("clavicle") else ("hand" if bone.begins_with("hand") else "bone"))
			var state := "open" if w.get("open", false) else "closed"
			return "broken %s (%s fracture)" % [which, state] if which != "bone" else "%s fracture" % state
	return "wound"


static func _with(what: String, how: String) -> String:
	return what if how == "" else "%s, %s" % [what, how]


## A bleed's pace in words: "spurting", "steady", "oozing"; heavy ones say so. "" if it isn't bleeding.
static func _bleed_words(kind: String, rate: float, bleeding: bool) -> String:
	if not bleeding or rate <= 0.0:
		return ""
	var word: String = BLEED_WORDS.get(kind, "bleeding")
	if rate >= HEAVY_RATE and kind != "arterial" and kind != "junctional":
		word = "heavy, " + word
	return word


## What's been done for a wound: tourniquet (and when), packed, bandaged, splinted, sealed.
static func _done(w: Dictionary, tq: Dictionary, care: Array[Dictionary], part: StringName) -> String:
	var done := PackedStringArray()
	var kind := String(w.kind)
	var t: Dictionary = tq.get(part, {})
	if w.get("tourniquet", false) and not t.is_empty():
		var count := int(t.get("count", 1))
		var label := "Two tourniquets on" if count > 1 else "Tourniquet on"
		if int(t.get("rushed", 0)) >= count:
			label += " (rushed: still bleeding)"
		var since := tourniquet_since(care, part)
		done.append(label + (" " + since if since != "" else ""))
	if w.get("clamped", false):
		done.append("clamped")
	elif w.get("closed", false):
		done.append("closed by surgery")
	elif w.get("packed", false):
		done.append("packed")
	elif w.get("treated", false):
		var bone := String(w.get("name", ""))
		match kind:
			"fracture": done.append("binder on" if bone == "pelvis" else "splinted")
			"chest": done.append("chest seal on")
			"rib": done.append("morphine given")
			_: done.append("bandaged")
	if kind == "fracture" and w.get("open", false) and w.get("bandaged", false):
		done.append("wound bandaged")
	return ", ".join(done)


## When the tourniquet on `part` went on, from the shared triage log: "at 14:05, 12 min ago", or
## "" if the log doesn't say (it went on before the log, or it's been trimmed).
static func tourniquet_since(care: Array[Dictionary], part: StringName) -> String:
	var tq := ItemDB.get_item(WoundModel.TOURNIQUET) if ItemDB.has_item(WoundModel.TOURNIQUET) else null
	var on := "%s, %s" % [tq.name if tq else "Tourniquet", Vitals.part_name(part)]
	var off := "Tourniquet off, %s" % Vitals.part_name(part)
	var at := ""
	for e: Dictionary in care:
		var what := String(e.what)
		if what.begins_with(on):
			if at == "":
				at = String(e.t)
		elif what.begins_with(off):
			at = ""
	if at == "":
		return ""
	var ago := minutes_between(at, Vitals.care_time())
	return "at %s (%s)" % [at.left(5), "just now" if ago < 1 else "%d min ago" % ago]


## Whole minutes from clock time `from` to `to` ("14:05" or "14:05:31"), across midnight.
static func minutes_between(from: String, to: String) -> int:
	return posmod(roundi((_clock_s(to) - _clock_s(from)) / 60.0), 24 * 60)


static func _clock_s(clock: String) -> float:
	var bits := clock.split(":")
	var s := 0.0
	for i in mini(bits.size(), 3):
		s += bits[i].to_float() * [3600.0, 60.0, 1.0][i]
	return s


## Where a wound is, plainly: "Left thigh, inner", "Chest, right side", "Neck".
static func where(w: Dictionary) -> String:
	var part: StringName = w.part
	var name := InteractionMenu.part_name(part)
	var at: Variant = w.get("at")
	if not at is Vector3 or not BodyMap.PART_BOXES.has(part):
		return name
	var p: Vector3 = at
	var centre: Vector3 = BodyMap.PART_BOXES[part][0][0]
	var off := p - centre
	if part in [Vitals.CHEST, Vitals.ABDOMEN, Vitals.PELVIS]:
		var bits := PackedStringArray([name])
		if off.z > 0.05:
			bits.append("back")
		if p.x > TRUNK_SIDE_M:
			bits.append("right side")  # the casualty's right (+x)
		elif p.x < -TRUNK_SIDE_M:
			bits.append("left side")
		else:
			bits.append("middle")
		return ", ".join(bits)
	if part in [Vitals.HEAD, Vitals.FACE, Vitals.NECK]:
		return name
	# A limb: towards the middle line (inner) or away from it (outer), front or back.
	var inward := -signf(centre.x) * off.x
	var ahead := -off.z
	if maxf(absf(inward), absf(ahead)) < SIDE_M:
		return name
	if absf(inward) >= absf(ahead):
		return "%s, %s" % [name, "inner" if inward > 0.0 else "outer"]
	return "%s, %s" % [name, "front" if ahead > 0.0 else "back"]


# --- Not one wound -------------------------------------------------------------------------

## Cardiac arrest, a blocked airway, blood loss needing a line and fluids, blast lung, burns,
## cold, a concussion, pain and the heart rate: from Vitals and its care list.
static func _conditions(vitals: Vitals, carries: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tasks := vitals.care_needed()
	var kinds := {}
	for task: Dictionary in tasks:
		kinds[String(task.kind)] = task
	var lost := 1.0 - vitals.blood_fraction()
	if vitals.in_cardiac_arrest():
		var left := maxf(vitals.seconds_to_death(), 0.0)
		out.append(_entry(Vitals.CHEST, "arrest", LIFE_THREATENING, "Heart", "cardiac arrest: no pulse",
			"%d:%02d left" % [floori(left / 60.0), int(left) % 60], "", _order("defib"), _steps("arrest", carries)))
	if vitals.airway_blocked():
		out.append(_entry(Vitals.HEAD, "airway", LIFE_THREATENING, "Airway", "blocked (unconscious, no NPA)", "", "", _order("airway"), _steps("airway", carries)))
	for kind: String in ["access", "fluids", "pressure"]:
		if kinds.has(kind):
			var task: Dictionary = kinds[kind]
			var severity := CRITICAL if lost >= WoundModel.NO_SPRINT_LOST else SERIOUS
			var what: String = {"access": "blood loss: needs a line in", "fluids": "blood loss: needs fluids", "pressure": "veins collapsing: needs a pressure bag"}[kind]
			var steps := _steps(kind, carries)
			if kind == "access":
				steps = [_step(_first_carried(task, carries), "IV in a forearm or lower leg, or IO in the sternum", carries)]
			out.append(_entry(StringName(task.part), kind, severity, "Circulation", what, "", "", _order(kind), steps))
	if vitals.has_blast_lung():
		out.append(_entry(Vitals.CHEST, "blast_lung", CRITICAL, "Lungs", "blast lung (coughing blood)", "", "", _order("tension") + 1, _steps("blast_lung", carries)))
	var burn := vitals.burn_share()
	if burn > 0.0:
		var pct := roundi(burn * 100.0 / 5.0) * 5
		var severity := CRITICAL if burn >= WoundModel.BURN_FLUID_FROM else (SERIOUS if burn >= 0.1 else MINOR)
		out.append(_entry(Vitals.CHEST, "burn", severity, "Body", "burns over about %d%% of the body" % maxi(pct, 5), "", "" if kinds.has("burn") else "dressed",
			_order("burn"), _steps(("burn_fluids" if burn >= WoundModel.BURN_FLUID_FROM else "burn") if kinds.has("burn") else "", carries)))
	if kinds.has("hypothermia") or vitals.hypothermic():
		out.append(_entry(Vitals.CHEST, "hypothermia", SERIOUS, "Body", "hypothermia: cold, shivering", "", "", _order("hypothermia"),
			_steps("hypothermia" if kinds.has("hypothermia") else "", carries)))
	if float(vitals.vision().get("blur", 0.0)) > 0.0:
		out.append(_entry(Vitals.HEAD, "concussion", SERIOUS, "Head", "concussion (head injury)", "", "", _order("pain"), _steps("concussion", carries)))
	for kind: String in ["racing", "slow_heart"]:
		if kinds.has(kind):
			out.append(_entry(Vitals.CHEST, kind, CRITICAL, "Heart", "pulse racing" if kind == "racing" else "pulse dangerously slow", "", "", _order(kind), _steps(kind, carries)))
	if kinds.has("pain"):
		out.append(_entry(Vitals.CHEST, "pain", SERIOUS if vitals.pain() >= 0.5 else MINOR, "Pain", pain_word(vitals.pain()), "", "", _order("pain"), _steps("pain", carries)))
	if kinds.has("wake"):
		out.append(_entry(Vitals.HEAD, "wake", MINOR, "Consciousness", "out, could be brought round", "", "", _order("wake"), _steps("wake", carries)))
	return out


## The first of a care task's items (Vitals.task_items) that's carried, else its first.
static func _first_carried(task: Dictionary, carries: Callable) -> StringName:
	var items := Vitals.task_items(task)
	for id: StringName in items:
		if carries.is_valid() and bool(carries.call(id)):
			return id
	return items[0] if not items.is_empty() else StringName(task.get("item", &""))


static func _entry(part: StringName, kind: String, severity: int, where_text: String, what: String, bleed: String, done: String, order: int, next: Array) -> Dictionary:
	return {"part": part, "kind": kind, "severity": severity, "where": where_text, "what": what, "bleed": bleed, "done": done,
		"rate": 0.0, "order": order, "next": next}


## The steps for a kind of task (STEPS), each marked carried.
static func _steps(key: String, carries: Callable) -> Array:
	var out: Array = []
	for s: Array in STEPS.get(key, []):
		out.append(_step(s[0], s[1], carries))
	return out


static func _step(item: StringName, text: String, carries: Callable) -> Dictionary:
	var carried := item == &"" or (carries.is_valid() and bool(carries.call(item)))
	if item != &"" and ItemDB.has_item(item) and ItemDB.get_item(item).stats.get("no_item", false):
		carried = true  # hands only (CPR)
	return {"item": item, "text": text, "carried": carried}


static func _order(kind: String) -> int:
	var i := Vitals.CARE_ORDER.find(kind)
	return i if i >= 0 else Vitals.CARE_ORDER.size()


# --- The vitals at a glance ------------------------------------------------------------------

## The casualty at a glance, as [text, colour] pieces: how conscious (conscious, dying,
## unconscious, cardiac arrest with the time left), blood lost, breathing and oxygen, the pulse
## and pain, in words; with `oximeter` the SpO2 and pulse in numbers too. `on_self`: what you can
## tell of yourself (no pulse or lips).
static func summary(vitals: Vitals, on_self: bool, oximeter: bool) -> Array:
	var out: Array = []
	if vitals.is_dead():
		return [["DEAD", UiKit.TEXT_OFF]]
	if vitals.in_cardiac_arrest():
		var left := maxf(vitals.seconds_to_death(), 0.0)
		out.append(["CARDIAC ARREST %d:%02d" % [floori(left / 60.0), int(left) % 60], UiKit.BAD])
	elif vitals.is_unconscious():
		out.append(["UNCONSCIOUS", UiKit.WARN])
	elif vitals.is_dying():
		out.append(["CONSCIOUS, DYING", UiKit.BAD])
	else:
		out.append(["CONSCIOUS", UiKit.GOOD])
	var lost := 1.0 - vitals.blood_fraction()
	var blood_color := UiKit.GOOD if lost < WoundModel.EFFECTS_FROM_LOST else (UiKit.ACCENT if lost < WoundModel.NO_SPRINT_LOST else UiKit.BAD)
	out.append(["Blood lost: %s" % blood_word(lost), blood_color])
	var bleed := bleed_out_text(vitals)
	if bleed != "":
		out.append([bleed, UiKit.BAD])
	var spo2 := vitals.spo2()
	var breath := "no breathing" if vitals.in_cardiac_arrest() else ("breathing laboured" if vitals.breathing_laboured() else "breathing well")
	var oxygen := "" if on_self and not oximeter else (", lips blue" if spo2 < WoundModel.SPO2_BLUE_LIPS else (", colour poor" if spo2 < WoundModel.SPO2_LABOURED else ""))
	if oximeter and not vitals.in_cardiac_arrest():
		oxygen = ", SpO2 %d%%" % roundi(spo2)
	out.append(["Breathing: %s%s" % [breath.trim_prefix("breathing "), oxygen], UiKit.BAD if spo2 < WoundModel.SPO2_BLUE_LIPS or vitals.in_cardiac_arrest() else (UiKit.ACCENT if spo2 < WoundModel.SPO2_LABOURED else UiKit.TEXT)])
	if not on_self or oximeter:
		var hr := vitals.heart_rate()
		var pulse := "none" if vitals.in_cardiac_arrest() else pulse_word(hr, lost)
		if oximeter and not vitals.in_cardiac_arrest():
			pulse += " (%d)" % roundi(hr)
		out.append(["Pulse: %s" % pulse, UiKit.BAD if vitals.in_cardiac_arrest() or hr > WoundModel.HR_RACING or hr < WoundModel.HR_SLOW else (UiKit.ACCENT if hr > 110.0 else UiKit.TEXT)])
	if not vitals.is_unconscious():
		var pain := vitals.pain()
		out.append(["Pain: %s" % pain_word(pain), UiKit.ACCENT if pain >= 0.5 else UiKit.TEXT])
	return out


## Blood lost in words: "none", "a little", "about a fifth", "about a third", "nearly half".
static func blood_word(lost: float) -> String:
	if lost < 0.03:
		return "none"
	if lost < 0.12:
		return "a little"
	if lost < 0.22:
		return "about a fifth"
	if lost < 0.3:
		return "about a quarter"
	if lost < 0.4:
		return "about a third"
	return "nearly half"


## The time left at this rate of bleeding, in words: "bleeding out in about 2 min" (until the
## heart stops: WoundModel.ARREST_LOST), "" when nothing's bleeding. Rough: the bleeding slows as
## the blood goes.
static func bleed_out_text(vitals: Vitals) -> String:
	var rate := vitals.bleed_rate()
	if rate <= 0.01 or vitals.in_cardiac_arrest():
		return ""
	var left_l := (WoundModel.ARREST_LOST - (1.0 - vitals.blood_fraction())) * WoundModel.BLOOD_L
	if left_l <= 0.0:
		return "bleeding out now"
	var minutes := left_l / rate
	if minutes < 1.0:
		return "bleeding out in under a minute"
	if minutes > 30.0:
		return "slow bleed"
	return "bleeding out in about %d min" % roundi(minutes)


static func pulse_word(hr: float, lost: float) -> String:
	if hr > WoundModel.HR_RACING:
		return "racing"
	if hr > 110.0:
		return "fast and weak" if lost >= WoundModel.EFFECTS_FROM_LOST else "fast"
	if hr < WoundModel.HR_SLOW:
		return "slow"
	return "normal"


static func pain_word(pain: float) -> String:
	if pain < 0.05:
		return "none"
	if pain < 0.25:
		return "mild"
	if pain < 0.5:
		return "moderate"
	return "severe"
