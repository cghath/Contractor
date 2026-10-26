class_name DeadDecay
extends RefCounted
## The dead over time: decay stages (docs/survival_deadtime.md; survival.md call 112). Static.
##
## The world has a date: STORY_DAYS of the story's time to every world day (a year of four
## Seasons.SEASON_DAYS seasons is a story year), and the fall came fall_weeks() before day one
## (2-8 weeks, from the seed). Each of the dead turned some time after the fall ("turned": story
## days after it, as the cold-kept clock counts them), so its **age** is the story's days since it
## turned; winter days don't count (the frozen don't rot: the cold keeps them, call 113's thaw
## brings back fresh-looking ones).
## - **decay** 0..1 from the age (fresh under FRESH_DAYS, all the way at FRESH_DAYS + ROT_DAYS);
## - the **stage**: "fresh" (weeks: faster, stronger, more pool), "worn", "old" (months: slower,
##   softer, falling apart: less pool, the limbs come off easier; but more of them about);
## - the **mix**: early on most are fresh; months on most are old (roll(): a fresh share falling
##   with the months, the rest turned in the first weeks of the fall).
## The body carries it as metas: "dead_turned" (float), "dead_decay" (the stage, the model reads
## it: look()), "dead_decay_x" (0..1). ZoneDead's crowd records carry "turned" too.
## Every number here is Proposed.

const STORY_DAYS := 9.125  # 365 / (4 seasons x Seasons.SEASON_DAYS)
const FALL_WEEKS := Vector2i(2, 8)
const FRESH_DAYS := 14.0
const ROT_DAYS := 120.0
const STAGES: Array[String] = ["fresh", "worn", "old"]
const WORN_AT := 0.25
const OLD_AT := 0.6
## What the age does, fresh (decay 0) .. old (decay 1).
const PACE := Vector2(1.15, 0.8)
const POOL := Vector2(1.0, 0.55)  # (fresh at the kinds' own pools: the survival suite's 12 rounds to the body)
const STRIKE := Vector2(1.25, 0.8)
const LIMB := Vector2(1.0, 1.6)
## The fresh share of the dead by months since the fall: FRESH_SHARE.x at the fall, down by
## FRESH_PER_MONTH, never under FRESH_SHARE.y (people still turn).
const FRESH_SHARE := Vector2(0.9, 0.1)
const FRESH_PER_MONTH := 0.25
## More of them as the months go (dead_near, the crowd): COUNT.x at the fall .. COUNT.y by COUNT_MONTHS.
const COUNT := Vector2(0.9, 1.3)
const COUNT_MONTHS := 8.0
## Limbs (Vitals' undead branch): the parts that come off.
const LIMBS: Array[StringName] = [&"upper_arm_l", &"upper_arm_r", &"forearm_l", &"forearm_r", &"hand_l", &"hand_r",
	&"thigh_l", &"thigh_r", &"shin_l", &"shin_r", &"foot_l", &"foot_r"]

## Tests: the world day to count from (-1: Survival.day()).
static var force_day := -1.0
static var _winter_cache := {}  # "start|day" -> winter days in 1..day


# --- The world's date -------------------------------------------------------------------------

## Weeks between the fall and the world's day one (state "fall_weeks", else from the seed).
static func fall_weeks() -> int:
	var st := Survival.state()
	if st.has("fall_weeks"):
		return int(st.fall_weeks)
	var span := FALL_WEEKS.y - FALL_WEEKS.x + 1
	return FALL_WEEKS.x + absi(hash([int(st.get("seed", 0)), "fall"])) % span


## The world day now (fractional).
static func world_day() -> float:
	if force_day >= 0.0:
		return force_day
	return float(Survival.day()) + Survival.hour() / 24.0


## Story days since the fall at world day `day` (-1: now), every day counted.
static func since_fall(day := -1.0) -> float:
	var d := world_day() if day < 0.0 else day
	return fall_weeks() * 7.0 + maxf(d - 1.0, 0.0) * STORY_DAYS


## Months since the fall (30 story days).
static func months(day := -1.0) -> float:
	return since_fall(day) / 30.0


## The cold-kept clock: story days since the fall that rot counts (winter's world days left out).
static func kept_since(day := -1.0) -> float:
	var d := world_day() if day < 0.0 else day
	var whole := floori(maxf(d - 1.0, 0.0))
	var winter := _winter_days(whole)
	var part := maxf(d - 1.0, 0.0) - whole
	if part > 0.0 and Seasons.of_day(whole + 1, Seasons.start()) == "winter":
		part = 0.0
	return fall_weeks() * 7.0 + (float(whole - winter) + part) * STORY_DAYS


static func _winter_days(whole: int) -> int:
	var start := Seasons.start()
	var key := "%s|%d" % [start, whole]
	if _winter_cache.has(key):
		return int(_winter_cache[key])
	var n := 0
	for i in whole:
		if Seasons.of_day(i + 1, start) == "winter":
			n += 1
	if _winter_cache.size() > 64:
		_winter_cache.clear()
	_winter_cache[key] = n
	return n


# --- One of the dead ----------------------------------------------------------------------------

## A new head's "turned" (on the cold-kept clock) at world day `day` (-1 now): a fresh one
## (turned in the last weeks) the fresh share of the time, else one of the first weeks' dead.
static func roll(rng: RandomNumberGenerator, day := -1.0) -> float:
	var kept := kept_since(day)
	var fresh := clampf(FRESH_SHARE.x - months(day) * FRESH_PER_MONTH, FRESH_SHARE.y, FRESH_SHARE.x)
	var age := 0.0
	if rng.randf() < fresh:
		age = rng.randf() * minf(kept, FRESH_DAYS * 1.5)
	else:
		age = kept * (0.6 + 0.4 * rng.randf())
	return kept - age


## The decay (0..1) of one that turned at `turned` (on the cold-kept clock), at `day` (-1 now).
static func decay_of(turned: float, day := -1.0) -> float:
	return clampf((kept_since(day) - turned - FRESH_DAYS) / ROT_DAYS, 0.0, 1.0)


static func stage_of(decay: float) -> String:
	if decay >= OLD_AT:
		return "old"
	return "worn" if decay >= WORN_AT else "fresh"


## The share of each stage among the dead at world day `day`: {"fresh", "worn", "old"} (n rolls
## on a fixed seed, so the same day gives the same mix).
static func mix(day: float, n := 200) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["dead mix", int(Survival.state().get("seed", 0))])
	var out := {"fresh": 0.0, "worn": 0.0, "old": 0.0}
	for i in n:
		out[stage_of(decay_of(roll(rng, day), day))] += 1.0 / n
	return out


## How many of the dead about, by the months since the fall (Survival.dead_near).
static func count_mult(day := -1.0) -> float:
	return lerpf(COUNT.x, COUNT.y, clampf(months(day) / COUNT_MONTHS, 0.0, 1.0))


## The body's decay (0..1; 0 for one without the meta).
static func of(s: Node) -> float:
	return float(s.get_meta(&"dead_decay_x", 0.0)) if s else 0.0


static func pace_mult(decay: float) -> float:
	return lerpf(PACE.x, PACE.y, decay)


static func pool_mult(decay: float) -> float:
	return lerpf(POOL.x, POOL.y, decay)


static func strike_mult(s: Node) -> float:
	return lerpf(STRIKE.x, STRIKE.y, of(s))


## A hit's share of the pool on `part` (Vitals' undead branch): an old one's limbs come apart.
static func limb_mult(s: Node, part: StringName) -> float:
	return lerpf(LIMB.x, LIMB.y, of(s)) if part in LIMBS else 1.0


## Host + every peer (CompoundLevel._make_zombie): the stage on body `s` from its spawn data.
static func apply(s: Node, turned: float, decay: float) -> void:
	s.set_meta(&"dead_turned", turned)
	s.set_meta(&"dead_decay_x", decay)
	s.set_meta(&"dead_decay", stage_of(decay))


# --- The look ---------------------------------------------------------------------------------

## The skin by stage: a fresh one's still flesh-grey, a worn one's the familiar grey-green, an
## old one's gone to the bone.
const SKIN := {"fresh": "9a8f80", "worn": "8a9183", "old": "b3ab98"}
## The clothes: torn and dirtied by this share (darkened), greyed (desaturated) by this.
const CLOTH_DARK := {"fresh": 0.08, "worn": 0.25, "old": 0.4}
const CLOTH_GREY := {"fresh": 0.1, "worn": 0.4, "old": 0.7}


## The plain-clothes variant (VoxelArt "civ:shirt:trousers:skin:shoes") aged by `decay`.
static func look(variant: String, decay: float) -> String:
	var parts := variant.split(":")
	if parts.size() < 5:
		return variant
	var stage := stage_of(decay)
	for i: int in [1, 2, 4]:
		parts[i] = _wear(parts[i], float(CLOTH_DARK[stage]), float(CLOTH_GREY[stage]))
	parts[3] = String(SKIN[stage])
	return ":".join(parts)


static func _wear(hex: String, dark: float, grey: float) -> String:
	var c := Color(hex)
	var g := c.get_luminance()
	return c.lerp(Color(g, g, g), grey).darkened(dark).to_html(false)


# --- Spawning ---------------------------------------------------------------------------------

static var _rng := RandomNumberGenerator.new()


## Host (Survival.server_spawn_zombie): the spawn data's "turned", "decay", "origin" (and "nest",
## "dormant" passed through) for one of the dead of `kind` at `at`: `extra`'s when given (a crowd
## head becoming a body keeps its own), else rolled.
static func spawn_data(level: Node, at: Vector3, kind: String, extra: Dictionary) -> Dictionary:
	var out := extra.duplicate()
	var turned := float(extra.turned) if extra.has("turned") else roll(_rng)
	out["turned"] = turned
	out["decay"] = decay_of(turned)
	if not extra.has("origin"):
		out["origin"] = DeadDress.roll_at(level, at, _rng, kind)
	return out


## What a body carries back into the crowd (ZoneDead.server_add's extra).
static func carry(z: Node) -> Dictionary:
	var out := {"turned": float(z.get_meta(&"dead_turned", kept_since())), "origin": String(z.get_meta(&"dead_origin", "civilian"))}
	if String(z.get_meta(&"dead_nest", "")) != "":
		out["nest"] = String(z.get_meta(&"dead_nest", ""))
	return out
