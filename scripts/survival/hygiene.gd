class_name Hygiene
extends RefCounted
## Hygiene (docs/survival_medical.md sections 1 and 5, call 48): washing at a basin, a river or
## a bath (soap doubles it), clean clothes (a wash job: on_wash_job), and blood and gore on you
## (the masking play, call 53): it costs hygiene, raises the wound infection risk and makes you
## smell of the dead's interest (Soldier.smell_strength reads the meta GORE_META, "gore_until",
## in Soldier._now() seconds). The hygiene store itself drains in Needs.step.

## Proposed: what a wash gives by where, and soap's multiplier (it doubles it).
const WASH := {"basin": 35.0, "river": 45.0, "lake": 45.0, "bath": 70.0, "rain": 15.0}
const SOAP_MULT := 2.0
## A winter wash outdoors (a river, a lake) is a cold risk: the core drops this much, and you're wet.
const WINTER_WASH_C := 0.8
## Gore smeared on (the masking play): hygiene lost, how long it lasts on you (world hours),
## and the risk it adds to wounds.
const GORE_HYGIENE := 25.0
const GORE_H := 12.0
const GORE_RISK := 0.4
const GORE_META := &"gore_until"
## Clothes go dirty after CLOTHES_DAYS world days unwashed: hygiene drains faster (x DIRTY_CLOTHES).
const CLOTHES_DAYS := 5.0
const DIRTY_CLOTHES := 1.5


## A wash at `where` (WASH's keys) on the body `n`, with or without soap: hygiene up, gore off.
## `season` for the cold risk. Returns the hygiene gained.
static func wash(n: Dictionary, where: String, soap: bool, season := "spring") -> float:
	var gain := float(WASH.get(where, 30.0)) * (SOAP_MULT if soap else 1.0)
	var before := float(n.get("hygiene", 0.0))
	n.hygiene = minf(100.0, before + gain)
	n.gore_h = 0.0
	if season == "winter" and where in ["river", "lake"]:
		n.warmth = maxf(Needs.MIN_C, float(n.get("warmth", Needs.NORMAL_C)) - WINTER_WASH_C)
		n.wet = 1.0
	return float(n.hygiene) - before


## Host: `s` washes at `where` (soap used up from his kit when he has some and `use_soap`).
## Returns what he's told.
static func server_wash(s: Soldier, where: String, use_soap := true) -> String:
	var n := Survival.needs_of(s)
	var soap := use_soap and FallenStory.take_one(s, "soap")
	wash(n, where, soap, BodySeason.season())
	if s.has_meta(GORE_META):
		s.remove_meta(GORE_META)
	Needs.apply(s, n)
	return "You wash%s: %s" % [" with soap" if soap else "", Needs.words(n).hygiene]


## Gore smeared on the body `n` (the masking play): hygiene down, the gore hours on.
static func gore(n: Dictionary) -> void:
	n.hygiene = maxf(0.0, float(n.get("hygiene", 0.0)) - GORE_HYGIENE)
	n.gore_h = GORE_H


## Host: `s` smears himself with the dead's gore: the body's gore and the smell meta.
static func server_gore(s: Soldier) -> void:
	gore(Survival.needs_of(s))
	s.set_meta(GORE_META, Soldier._now() + GORE_H / 24.0 * Survival.DAY_MIN * 60.0)


## Clean clothes on (a wash job done, a fresh set found): the dirty clock back to zero.
static func clean_clothes(n: Dictionary) -> void:
	n.clothes_h = 0.0


## The settlement's wash job (a hook for the settlement lane): a settler's record's clothes clean.
static func on_wash_job(rec: Dictionary) -> void:
	var n: Dictionary = rec.get("needs", {})
	if not n.is_empty():
		clean_clothes(n)


## Whether the clothes are dirty (flies, smell, hygiene draining faster).
static func clothes_dirty(n: Dictionary) -> bool:
	return float(n.get("clothes_h", 0.0)) >= CLOTHES_DAYS * 24.0


## World hours on the body: the gore wears off, the clothes get dirtier (and dirty clothes drain
## hygiene a little faster), mud in spring and autumn rain too.
static func step(n: Dictionary, world_h: float, season := "spring", rain := false) -> void:
	n.gore_h = maxf(0.0, float(n.get("gore_h", 0.0)) - world_h)
	n.clothes_h = float(n.get("clothes_h", 0.0)) + world_h
	var extra := (DIRTY_CLOTHES - 1.0 if clothes_dirty(n) else 0.0) + (BodySeason.mud_mult(season) - 1.0 if rain else 0.0)
	if extra > 0.0:
		n.hygiene = maxf(0.0, float(n.get("hygiene", 0.0)) - 100.0 / Needs.HYGIENE_DAYS / 24.0 * world_h * extra)


## The wound infection risk from dirt, 0 .. 1: Needs' hygiene risk plus gore on you.
static func risk(n: Dictionary) -> float:
	return clampf(Needs.infection_risk(n) + (GORE_RISK if float(n.get("gore_h", 0.0)) > 0.0 else 0.0), 0.0, 1.0)


## How much the body smells to the dead (Soldier.smell_strength adds it): gore, filth.
static func smell(n: Dictionary) -> float:
	if float(n.get("gore_h", 0.0)) > 0.0:
		return 0.8
	return 0.3 if float(n.get("hygiene", 100.0)) < 15.0 or clothes_dirty(n) else 0.0
