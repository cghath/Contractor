class_name Infection
extends RefCounted
## Wound infection staging and healing over days (docs/survival_medical.md section 2, call 14):
## every wound the wound model holds gets a record in the body's Dictionary (Needs' stores,
## "wounds": the same list the owner gets for the body screen), linked by the id "bw" it puts on
## the wound model's own wound. A record:
##   id, part, kind, stage (STAGES: clean, contaminated, infected, sepsis), stage_h (world hours in
##   it), infected_h (hours infected or worse, all told), dirt (0..1 toward contaminated),
##   dressed_h (hours since a clean dressing; -1 none), fragment (a bullet or fragment still in),
##   bite, stitched, debrided, bone ("", "splinted", "set_well", "set_badly"), heal_h (world hours
##   of healing left), heal_total, abx_back (stages a course took back), abscess, gangrene,
##   closed (a closed fracture or a cracked rib: it heals but doesn't infect).
## clean -> contaminated (dirt: open to the air, a stale dressing, dirt and gore on you, mud, a
## bite, dirty water on it, a fragment in it) -> infected (a day: redness, pain, fever) -> sepsis
## (two and a half days: fever, racing pulse, pressure down, delirium) -> death (two days). Cleaning
## (water, boiled better, antiseptic best), a clean dressing changed daily and an antibiotic course
## (5 doses over 5 world days: each day of it takes every wound back a stage; stopping early lets it
## come back a stage) move it back. Healing: by kind (a deep wound a week, a fracture three),
## faster stitched, slower with a fragment in; protein, sleep and warmth help it; infection, fever,
## cold and hunger stop it. Static: the rules are plain data, testable without a body.

const STAGES: Array[String] = ["clean", "contaminated", "infected", "sepsis"]
## Kinds that are open to the air (and can go bad), and kinds that only heal.
const OPEN_KINDS: Array[String] = ["arterial", "junctional", "venous", "muscle", "graze", "chest", "burn"]
const CLOSED_KINDS: Array[String] = ["fracture", "rib"]
## Proposed: world hours to heal by kind (call 78's "a deep wound takes a world week, a fracture three").
const HEAL_H := {"graze": 48.0, "venous": 120.0, "muscle": 168.0, "arterial": 240.0, "junctional": 240.0, "chest": 240.0,
	"burn": 168.0, "fracture": 504.0, "rib": 336.0}
const STITCHED_MULT := 0.4
## Proposed: hours open to the air before dirt contaminates it (x(1 + 2 x the dirt risk), mud),
## a dressing's life, the slower dirt under a stale one; then the stages' lengths.
const DIRT_OPEN_H := 12.0
const DRESSING_FRESH_H := 24.0
const DIRT_STALE_H := 24.0
const INFECT_H := 24.0
const SEPSIS_H := 60.0
const SEPSIS_DEATH_H := 48.0
const ABSCESS_H := 36.0
const GANGRENE_H := 72.0
const LIMB_PARTS: Array[String] = ["upper_arm_l", "upper_arm_r", "forearm_l", "forearm_r", "thigh_l", "thigh_r", "shin_l", "shin_r"]
## The fever an infection brings (the core it holds), by stage.
const FEVER_C := {2: 38.2, 3: 39.0}
## An antibiotic course: a dose covers a world day; COURSE doses make a course; DOSE_MAX_COVER caps
## doses taken early.
const COURSE := 5
const DOSE_COVER_H := 24.0
const DOSE_MAX_COVER_H := 36.0
## Gangrene's toll (Vitals.server_damage a world hour) until it's cut off.
const GANGRENE_DAMAGE_H := 2.0
## Tetanus from rusty metal (rare).
const TETANUS_CHANCE := 0.05
## A course left: the hours without cover (no next dose) before it counts as stopped early.
const COURSE_GAP_H := 12.0
## Healing's pace: low protein halves it, none stops it; asleep 1.5x; a fragment in 0.6x; a
## fracture untreated 0.3x, set badly 0.8x; short of vitamin D (rickets) 0.5x for bones.
const HEAL_ASLEEP := 1.5
const HEAL_FRAGMENT := 0.6
const HEAL_UNSET := 0.3
const HEAL_BADLY := 0.8
const HEAL_RICKETS := 0.5
## Scurvy reopens healing wounds: hours of healing lost a world day.
const SCURVY_REOPEN_H := 36.0
## Tests: a roll to use instead of randf() (-1: roll for real).
static var force_roll := -1.0


static func records(n: Dictionary) -> Array:
	if not n.get("wounds") is Array:
		n["wounds"] = []
	return n["wounds"]


static func record(n: Dictionary, id: int) -> Dictionary:
	for r: Dictionary in records(n):
		if int(r.id) == id:
			return r
	return {}


static func on_part(n: Dictionary, part: String) -> Array:
	return records(n).filter(func(r: Dictionary) -> bool: return part == "" or String(r.part) == part)


## A new record for a wound of `kind` on `part` (its heal time by kind, dirty from the start
## when the body is filthy: `risk` 0..1).
static func add(n: Dictionary, part: String, kind: String, risk := 0.0, fragment := false) -> Dictionary:
	var seq := int(n.get("wound_seq", 0)) + 1
	n["wound_seq"] = seq
	var heal := float(HEAL_H.get(kind, 168.0))
	var closed := kind in CLOSED_KINDS
	var r := {"id": seq, "part": part, "kind": kind, "stage": 0, "stage_h": 0.0, "infected_h": 0.0, "dirt": 0.0 if closed else clampf(risk, 0.0, 0.99),
		"dressed_h": -1.0, "fragment": fragment and not closed, "bite": false, "stitched": false, "debrided": false, "bone": "",
		"heal_h": heal, "heal_total": heal, "abx_back": 0, "abscess": false, "gangrene": false, "closed": closed}
	if fragment and not closed:
		r.stage = 1  # a round or fragment left in: dirty until it's out
	records(n).append(r)
	return r


static func stage_name(r: Dictionary) -> String:
	return STAGES[clampi(int(r.get("stage", 0)), 0, 3)]


## The worst stage on the body (0 clean).
static func worst(n: Dictionary) -> int:
	var w := 0
	for r: Dictionary in records(n):
		w = maxi(w, int(r.stage))
	return w


static func has_gangrene(n: Dictionary) -> bool:
	return records(n).any(func(r: Dictionary) -> bool: return bool(r.get("gangrene", false)))


# --- The antibiotic course ---------------------------------------------------------------------

static func course(n: Dictionary) -> Dictionary:
	if not n.get("abx") is Dictionary:
		n["abx"] = {}
	return n["abx"]


## Whether a course covers the body now.
static func covered(n: Dictionary) -> bool:
	return float(course(n).get("cover_h", 0.0)) > 0.0


## A dose of antibiotics into `n` (one box: a world day's dose). Returns false when the body has
## enough in it for now (DOSE_MAX_COVER_H).
static func dose(n: Dictionary) -> bool:
	var c := course(n)
	if float(c.get("cover_h", 0.0)) + DOSE_COVER_H > DOSE_MAX_COVER_H + 0.01:
		return false
	c["doses"] = int(c.get("doses", 0)) + 1
	c["cover_h"] = float(c.get("cover_h", 0.0)) + DOSE_COVER_H
	if not c.has("back_h"):
		c["back_h"] = 0.0
	return true


## The course runs `world_h` hours: each full day of cover takes every wound back a stage
## (not gangrene; a fragment keeps it contaminated); a course that runs out before COURSE doses
## lets what it took back return a stage.
static func _course_step(n: Dictionary, world_h: float) -> void:
	var c := course(n)
	if c.is_empty():
		return
	if not covered(n):
		# Between doses: a course left COURSE_GAP_H without the next one has stopped (early, if
		# it's short of COURSE doses: what it took back comes back a stage).
		c["gap_h"] = float(c.get("gap_h", 0.0)) + world_h
		if int(c.get("doses", 0)) >= COURSE or float(c.gap_h) >= COURSE_GAP_H:
			_course_over(n, int(c.get("doses", 0)) < COURSE)
		return
	c["gap_h"] = 0.0
	var h := minf(world_h, float(c.cover_h))
	c.cover_h = float(c.cover_h) - h
	c.back_h = float(c.get("back_h", 0.0)) + h
	while float(c.back_h) >= DOSE_COVER_H:
		c.back_h = float(c.back_h) - DOSE_COVER_H
		for r: Dictionary in records(n):
			if int(r.stage) > 0 and not bool(r.gangrene):
				var floor_stage := 1 if bool(r.fragment) else 0
				if int(r.stage) > floor_stage:
					r.stage = int(r.stage) - 1
					r.stage_h = 0.0
					r.abx_back = int(r.get("abx_back", 0)) + 1
					if int(r.stage) == 0:
						r.dirt = 0.0
	if float(c.cover_h) <= 0.0 and int(c.get("doses", 0)) >= COURSE:
		_course_over(n, false)


static func _course_over(n: Dictionary, early: bool) -> void:
	for r: Dictionary in records(n):
		if early and int(r.get("abx_back", 0)) > 0:
			r.stage = mini(3, int(r.stage) + 1)  # stopped early: it comes back
			r.stage_h = 0.0
		r.abx_back = 0
	n["abx"] = {}


# --- Stepping ------------------------------------------------------------------------------

## `world_h` world hours of every wound on `n` in `ctx`: "risk" (dirt 0..1: Hygiene.risk),
## "mud" (spring and autumn rain), "bleeding" ({id: true} for records whose wound still bleeds),
## "fever" (a fever from elsewhere stops healing), "asleep". Returns {"healed": [ids],
## "death": bool, "gangrene_h": hours of gangrene this step}.
static func step(n: Dictionary, world_h: float, ctx := {}) -> Dictionary:
	var out := {"healed": [], "death": false, "gangrene_h": 0.0}
	if world_h <= 0.0:
		return out
	var abx := covered(n)
	_course_step(n, world_h)
	var risk := float(ctx.get("risk", Hygiene.risk(n)))
	var mud := float(ctx.get("mud", 1.0))
	var bleeding: Dictionary = ctx.get("bleeding", {})
	for r: Dictionary in records(n):
		if float(r.dressed_h) >= 0.0:
			r.dressed_h = float(r.dressed_h) + world_h
		if not bool(r.closed) and not abx:
			_stage_step(r, world_h, risk, mud)
		if int(r.stage) >= 2:
			r.infected_h = float(r.get("infected_h", 0.0)) + world_h
		if int(r.stage) >= 3 and float(r.stage_h) >= SEPSIS_DEATH_H:
			out.death = true
		if bool(r.gangrene):
			out.gangrene_h = float(out.gangrene_h) + world_h
		var rate := heal_rate(n, r, ctx) if not bleeding.has(int(r.id)) else 0.0
		r.heal_h = float(r.heal_h) - world_h * rate
		if Sickness.shows(n, "scurvy") and float(r.heal_h) < float(r.heal_total):
			r.heal_h = minf(float(r.heal_total), float(r.heal_h) + SCURVY_REOPEN_H * world_h / 24.0)  # old cuts open
		if float(r.heal_h) <= 0.0 and int(r.stage) == 0 and not bool(r.fragment):
			(out.healed as Array).append(int(r.id))
		if rate > 0.0:
			n.protein = maxf(0.0, float(n.get("protein", 0.0)) - 0.05 * world_h)  # rebuilding uses it
	for id: int in out.healed:
		records(n).erase(record(n, id))
	return out


## One record's dirt and stages for `world_h` hours, with no course covering it.
static func _stage_step(r: Dictionary, world_h: float, risk: float, mud: float) -> void:
	var st := int(r.stage)
	if st == 0:
		var fresh := float(r.dressed_h) >= 0.0 and float(r.dressed_h) < DRESSING_FRESH_H
		var per_h := 0.0
		if float(r.dressed_h) < 0.0:
			per_h = 1.0 / DIRT_OPEN_H
		elif not fresh:
			per_h = 1.0 / DIRT_STALE_H  # a dirty dressing
		if bool(r.stitched):
			per_h *= 0.3
		r.dirt = float(r.dirt) + world_h * per_h * (1.0 + 2.0 * risk) * mud
		if fresh:
			r.dirt = maxf(0.0, float(r.dirt) - world_h / DRESSING_FRESH_H * 0.5)  # a clean dressing keeps it clean
		if float(r.dirt) >= 1.0:
			r.stage = 1
			r.stage_h = 0.0
		return
	r.stage_h = float(r.stage_h) + world_h
	if st == 1 and float(r.stage_h) >= INFECT_H:
		r.stage = 2
		r.stage_h = 0.0
	elif st == 2:
		if float(r.stage_h) >= ABSCESS_H:
			r.abscess = true
		if String(r.part) in LIMB_PARTS and float(r.get("infected_h", 0.0)) >= GANGRENE_H:
			r.gangrene = true
		if float(r.stage_h) >= SEPSIS_H:
			r.stage = 3
			r.stage_h = 0.0


## Healing's pace for `r` now (1 the normal pace, 0 stopped), from the body `n`.
static func heal_rate(n: Dictionary, r: Dictionary, ctx := {}) -> float:
	return float(_rate_and_why(n, r, ctx)[0])


## Why `r` heals slower now: plain words ("infected", "hungry", "cold", ...).
static func slowed_by(n: Dictionary, r: Dictionary, ctx := {}) -> Array:
	return _rate_and_why(n, r, ctx)[1]


static func _rate_and_why(n: Dictionary, r: Dictionary, ctx: Dictionary) -> Array:
	var why: Array = []
	var rate := 1.0
	if int(r.stage) >= 2:
		why.append("infected")
		rate = 0.0
	if bool(ctx.get("fever", false)) or Body.has_fever(n):
		why.append("fever")
		rate = 0.0
	if Needs.shivering(n) > 0.5:
		why.append("cold")
		rate = 0.0
	if float(n.get("calories", 1.0)) <= 0.0:
		why.append("starving")
		rate = 0.0
	var protein := float(n.get("protein", 100.0))
	if protein <= 0.0:
		why.append("no protein")
		rate = 0.0
	elif protein < 20.0:
		why.append("short of protein")
		rate *= 0.5
	if bool(r.fragment):
		why.append("something still in it")
		rate *= HEAL_FRAGMENT
	if String(r.kind) == "fracture":
		var bone := String(r.get("bone", ""))
		if bone == "":
			why.append("not set")
			rate *= HEAL_UNSET
		elif bone == "set_badly":
			why.append("set crooked")
			rate *= HEAL_BADLY
		if Sickness.shows(n, "rickets"):
			why.append("rickets")
			rate *= HEAL_RICKETS
	if String(n.get("asleep", "")) != "" or bool(ctx.get("asleep", false)):
		rate *= HEAL_ASLEEP
	return [rate, why]


## World days `r` has left to heal at today's pace (INF when it isn't healing).
static func days_left(n: Dictionary, r: Dictionary) -> float:
	var rate := heal_rate(n, r)
	if rate <= 0.0:
		return INF
	return maxf(0.0, float(r.heal_h)) / rate / 24.0


## The fever the wounds bring (the core held; 0 none).
static func fever_c(n: Dictionary) -> float:
	var w := worst(n)
	var c := float(FEVER_C.get(w, 0.0))
	if has_gangrene(n):
		c = maxf(c, 38.6)
	return c


# --- Care --------------------------------------------------------------------------------------

## Cleans the wounds on `part` ("" all) by `how`: "water" (a contaminated wound only while fresh:
## under half a day), "boiled" (contaminated to clean), "antiseptic" (contaminated to clean,
## infected to contaminated), "dirty" (dirty water on it: contaminated). A fragment keeps it
## contaminated. Returns how many got better.
static func clean(n: Dictionary, part: String, how: String) -> int:
	var better := 0
	for r: Dictionary in on_part(n, part):
		if bool(r.closed):
			continue
		var floor_stage := 1 if bool(r.fragment) else 0
		var st := int(r.stage)
		var to := st
		match how:
			"dirty":
				r.dirt = 1.0
				to = maxi(st, 1)
			"water":
				r.dirt = 0.0
				if st == 1 and float(r.stage_h) < INFECT_H * 0.5:
					to = 0
			"boiled":
				r.dirt = 0.0
				if st == 1:
					to = 0
			"antiseptic":
				r.dirt = 0.0
				if st == 1 or st == 2:
					to = st - 1
		if how != "dirty" and st >= floor_stage:
			to = maxi(to, floor_stage)
		if to < st:
			better += 1
		if to != st:
			r.stage = to
			r.stage_h = 0.0
	return better


## A clean dressing on the wounds on `part` ("" all): the dressing clock back to zero.
static func dress(n: Dictionary, part: String) -> int:
	var count := 0
	for r: Dictionary in on_part(n, part):
		if not bool(r.closed) or String(r.kind) == "fracture":
			r.dressed_h = 0.0
			count += 1
	return count


# --- Host: the body's wounds ---------------------------------------------------------------------

## Host: the wound model's wounds on `s` matched to the records in `n`: a new wound gets a record
## (a round or fragment that stayed in: `fragment`; dirty from the start on a filthy body), a wound
## gone takes its record with it. Returns {record id: the wound Dictionary}.
static func server_sync(s: Soldier, n: Dictionary) -> Dictionary:
	var by_id := {}
	if s == null or s.vitals == null:
		return by_id
	var risk := Hygiene.risk(n)
	for w: Dictionary in s.vitals.server_wounds():
		var kind := String(w.get("kind", ""))
		var named := String(w.get("name", ""))
		if named == "amputation":
			kind = "muscle"  # a stump: an open wound to dress and keep clean
		if not (kind in OPEN_KINDS or kind in CLOSED_KINDS):
			continue
		if not w.has("bw") or record(n, int(w.bw)).is_empty():
			var stayed: bool = StringName(w.get("rc", &"")) == Vitals.FRAGMENT or (w.get("at") != null and w.get("out") == null and kind in ["muscle", "venous", "arterial"])
			var r := add(n, String(w.part), kind, risk * 0.5, stayed)
			if kind == "fracture" and bool(w.get("open", false)):
				r.closed = false  # an open break can go bad
			w["bw"] = int(r.id)
		var rec := record(n, int(w.bw))
		if kind == "fracture" and bool(w.get("treated", false)) and String(rec.get("bone", "")) == "":
			rec["bone"] = "splinted"  # the splint holds it: it heals (set_bone in surgery sets it properly)
		by_id[int(w.bw)] = w
	for r: Dictionary in records(n).duplicate():
		if not by_id.has(int(r.id)):
			records(n).erase(r)
	return by_id


## Host: rusty metal in a wound on `part` of `s` (a hit marked "rusty"): contaminated, and the
## rare tetanus roll. Returns whether tetanus started.
static func server_rusty(s: Soldier, part: String) -> bool:
	var n := Survival.needs_of(s)
	server_sync(s, n)
	for r: Dictionary in on_part(n, part):
		r.stage = maxi(int(r.stage), 1)
	var roll := force_roll if force_roll >= 0.0 else randf()
	return roll < TETANUS_CHANCE and Sickness.start(n, "tetanus")
