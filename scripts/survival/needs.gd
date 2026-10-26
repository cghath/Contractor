class_name Needs
extends RefCounted
## The metabolism of Contractor: Fallen (docs/survival_medical.md section 1, calls 14, 47, 48, 78):
## a survivor's body as a handful of stores, kept in the Dictionary Survival.needs_of(s) holds on
## the body (host-authoritative, saved with the survivor, sent to the owner as Survival.my_body):
##   calories (0-MAX_KCAL kcal), water (0-MAX_L litres), protein, carbs, fat (0-100: 100 is two
##   days' need), vitamin_c, vitamin_d, iron (0-100: 100 is two weeks' need), sleep (0-100),
##   warmth (core temperature, 34-39 C), wet (0 dry .. 1 soaked), hygiene (0-100),
##   sick ({"id", "left_h"} or empty), asleep ("" or "bed", "bedroll", "ground"),
##   starving_h (world hours at 0 kcal).
## S1's "hunger" and "thirst" (0-100) stay in the same Dictionary as derived values (calories
## against FED_KCAL, water against FED_L), so its checks and save keep working; writing one of
## them (S1's respawn, an old save) writes through to calories or water on the next step.
## Rates are per world day (Survival.DAY_MIN real minutes), scaled by the time stepped. All of it
## is static: the stores are plain data and the math is testable without a body.

## Proposed (call 78: ~1,800 kcal and 2.5 l a world day, three days without food before danger,
## three without water before death, warnings well before harm).
const MAX_KCAL := 4000.0
const MAX_L := 4.0
const FED_KCAL := 2500.0  # "hunger" 100
const FED_L := 3.0  # "thirst" 100
const KCAL_DAY := 1800.0
const WATER_DAY := 2.5
## Running and a heavy load (over HEAVY_KG carried) burn more; shivering burns more too.
const SPRINT_MULT := 2.0
const HEAVY_KG := 25.0
const HEAVY_MULT := 1.4
const SHIVER_KCAL := 0.5
## Empty calories hurt only after STARVE_GRACE_H world hours on nothing (the body's reserves).
const STARVE_GRACE_H := 36.0
## Macros: a day's need in grams; the store holds two days (100), drains 50 a world day.
const PROTEIN_G_DAY := 60.0
const CARBS_G_DAY := 250.0
const FAT_G_DAY := 70.0
const MACRO_DAY := 50.0
## Vitamins: an item's vitamins are % of a day's need; the store holds VITAMIN_DAYS days.
const VITAMIN_DAYS := 14.0
## Sleep: awake it empties over SLEEP_AWAKE_H world hours; asleep it fills per world hour by bed.
const SLEEP_AWAKE_H := 36.0
const SLEEP_FILL_H := {"bed": 14.0, "bedroll": 10.0, "ground": 7.0}
const SLEEP_LOW := 30.0
## Warmth (C per world hour): darkness, wind, rain and being wet pull the core down; the body
## and moving push it back to NORMAL_C. Indoors the wind and rain mostly stop.
const NORMAL_C := 37.0
const MIN_C := 34.0
const MAX_C := 39.0
const SHIVER_C := 36.2
const FROZEN_C := 35.0
const WARM_DARK := 0.25
const WARM_WIND := 0.03  # per m/s of wind
const WARM_RAIN := 0.2
const WARM_WET := 0.6
const WARM_BASE := 0.25
const WARM_MOVE := 0.25
const WARM_BED := 0.4
const WET_RAIN_H := 0.8
const WET_DRY_H := 0.25
const WADE_WET_M := 0.3
## Hygiene empties over HYGIENE_DAYS world days unwashed.
const HYGIENE_DAYS := 7.0
const HYGIENE_RISK := 50.0
## Effects: below LOW hunger/thirst stamina comes back slower (S1's numbers); sleep and
## shivering take their own share.
const LOW := 25.0
const LOW_STAMINA_MULT := 0.6
const EMPTY_STAMINA_MULT := 0.3
const SLEEPY_STAMINA_MULT := 0.7
const SHIVER_STAMINA := 0.4
const DULLED_SWAY := 0.8
const SHIVER_SWAY := 0.6
## Empty water (twice) and calories past the grace cost blood (Vitals.server_damage a second,
## as S1's EMPTY_DAMAGE).
const EMPTY_DAMAGE := 0.01
## Sicknesses (call 81; section 5): extra kcal and litres lost a world day while they last.
const SICKNESS := {
	"dysentery": {"hours": 36.0, "kcal_day": 1200.0, "water_day": 2.0, "name": "dysentery", "start": "Your gut turns: dysentery. Drink, rest, and keep eating"},
	"food_poisoning": {"hours": 12.0, "kcal_day": 900.0, "water_day": 1.2, "name": "food poisoning", "start": "Something you ate was bad: food poisoning"},
}
## Raw water's dysentery chance by quality (section 5: a river 10%, a puddle 40%: Proposed), and
## raw meat's food poisoning chance.
const WATER_RISK := {"clean": 0.0, "questionable": 0.1, "dirty": 0.4}
const RAW_FOOD_RISK := 0.25
## World hours from the bad drink or meal to the first cramps (Proposed).
const ONSET_H := 2.0
## Tests: a roll to use instead of randf() (-1: roll for real).
static var force_roll := -1.0


## A fresh survivor's stores.
static func fresh() -> Dictionary:
	var n := {"calories": FED_KCAL, "water": FED_L, "protein": 80.0, "carbs": 80.0, "fat": 80.0,
		"vitamin_c": 80.0, "vitamin_d": 80.0, "iron": 80.0, "sleep": 90.0, "warmth": NORMAL_C, "wet": 0.0,
		"hygiene": 90.0, "sick": {}, "asleep": "", "starving_h": 0.0}
	_derive(n)
	return n


## Fills in any store `n` lacks (an S1 save, an S1 dict) from S1's hunger and thirst.
static func ensure(n: Dictionary) -> Dictionary:
	if not n.has("calories"):
		var base := fresh()
		var hunger := float(n.get("hunger", 100.0))
		var thirst := float(n.get("thirst", 100.0))
		for k: String in base:
			if not n.has(k) or k in ["hunger", "thirst"]:
				n[k] = base[k]
		n.calories = FED_KCAL * hunger / 100.0
		n.water = FED_L * thirst / 100.0
		_derive(n)
	return n


## A saved body back into `n` (Survival.server_survivor_joined).
static func restore(n: Dictionary, saved: Dictionary) -> void:
	for k: String in saved:
		n[k] = saved[k]
	n.erase("_seen_hunger")
	n.erase("_seen_thirst")
	ensure(n)
	_derive(n)


## A survivor back after a death: S1's RESPAWN_NEEDS on hunger and thirst, rested, warm, well.
static func respawn(n: Dictionary, needs: float) -> void:
	var base := fresh()
	for k: String in base:
		n[k] = base[k]
	n.calories = FED_KCAL * needs / 100.0
	n.water = FED_L * needs / 100.0
	_derive(n)
	n.hunger = needs  # exactly S1's number (the derived one can be a hair off)
	n.thirst = needs
	n._seen_hunger = needs
	n._seen_thirst = needs
	Body.reset(n)  # phase D's bite, wounds, sicknesses: a new survivor has none of them
	Mind.reset(n)  # nor the old one's nerve, habits or dreams


# --- Stepping ------------------------------------------------------------------------------

## What the world does to a body this step, from the body itself (host): sprinting, heavy,
## moving, the dark, wind and rain, indoors, wading.
static func context_of(s: Soldier) -> Dictionary:
	var ctx := {"sprint": s.want_sprint and s.velocity.length() > 3.0, "moving": s.velocity.length() > 0.5,
		"heavy": s.load_kg > HEAVY_KG, "dark": 0.0, "wind": 0.0, "rain": false,
		"indoors": false, "wading": 0.0}
	if s.is_inside_tree():
		ctx.dark = DayNight.darkness_at(s.global_position)
		var dn := DayNight.current()
		if dn:
			var row := dn.row()
			ctx.wind = float(row.get("wind_mps", 0.0))
			ctx.rain = int(row.get("rain", 0)) > 0
		ctx.indoors = Throwables.indoors(s.get_world_3d(), s.global_position)
	if s.movement:
		ctx.wading = float(s.movement.wet)
	ctx["cold_mult"] = Rpg.cold_mult(s)  # thin-skinned, thick skin, fitness (Rpg)
	ctx["season"] = BodySeason.season()  # phase D: winter bites, summer dries (BodySeason)
	ctx["clothing"] = Clothing.warmth(s)  # the worn layers, less what's soaked (call 132)
	ctx["layers"] = Clothing.layers(s.inventory)
	ctx["fire"] = Clothing.near_fire(s)  # clothes dry by a fire
	return ctx


## `world_h` world hours of a body in `ctx` (context_of's keys; missing ones are calm): every
## store moves by its rate. A sickness caught (eat()) shows after its onset: then "_announce"
## holds the line for the owner (Survival.server_drain sends it and clears it).
static func step(n: Dictionary, world_h: float, ctx: Dictionary) -> void:
	ensure(n)
	_take_legacy(n)
	if world_h <= 0.0:
		return
	var days := world_h / 24.0
	var asleep := String(n.get("asleep", ""))
	var work := (SPRINT_MULT if bool(ctx.get("sprint", false)) else 1.0) * (HEAVY_MULT if bool(ctx.get("heavy", false)) else 1.0)
	if asleep != "":
		work = 0.8  # Proposed: the body burns a little less asleep
	var shiver := shivering(n)
	var sick: Dictionary = SICKNESS.get(String((n.get("sick", {}) as Dictionary).get("id", "")), {})
	if not sick.is_empty() and float(n.sick.get("onset_h", 0.0)) > 0.0:
		var onset := float(n.sick.onset_h) - world_h
		n.sick.onset_h = maxf(0.0, onset)
		if onset > 0.0:
			sick = {}  # not showing yet
		else:
			n._announce = String(sick.start)
	var fat_mult := 1.15 if float(n.fat) <= 0.0 else 1.0
	n.calories = clampf(float(n.calories) - (KCAL_DAY * work * (1.0 + SHIVER_KCAL * shiver) * fat_mult + float(sick.get("kcal_day", 0.0))) * days, 0.0, MAX_KCAL)
	var season := String(ctx.get("season", "spring"))
	n.water = clampf(float(n.water) - (WATER_DAY * work * BodySeason.thirst_mult(season) + float(sick.get("water_day", 0.0))) * days, 0.0, MAX_L)
	n.protein = maxf(0.0, float(n.protein) - MACRO_DAY * days)
	n.carbs = maxf(0.0, float(n.carbs) - MACRO_DAY * days * work)
	n.fat = maxf(0.0, float(n.fat) - MACRO_DAY * days * (1.0 + shiver))
	var vit := 100.0 / VITAMIN_DAYS * days
	n.vitamin_c = maxf(0.0, float(n.vitamin_c) - vit)
	n.iron = maxf(0.0, float(n.iron) - vit)
	var sun := 1.5 if float(ctx.get("dark", 0.0)) < 0.3 and not bool(ctx.get("indoors", false)) and asleep == "" else 0.0
	n.vitamin_d = clampf(float(n.vitamin_d) - vit + vit * sun, 0.0, 100.0)
	# Sleep.
	if asleep != "":
		n.sleep = minf(100.0, float(n.sleep) + float(SLEEP_FILL_H.get(asleep, SLEEP_FILL_H.ground)) * world_h * Dreams.restore_mult(n))  # (a nightmare: less)
	else:
		n.sleep = maxf(0.0, float(n.sleep) - 100.0 / SLEEP_AWAKE_H * world_h * (1.5 if work > 1.0 else 1.0))
	# Wet, then warmth.
	var indoors := bool(ctx.get("indoors", false))
	if ctx.has("layers"):  # clothes: the rain soaks the outer layer first (Clothing, call 132)
		Clothing.step_wet(n, ctx.layers, world_h, ctx)
		ctx["clothing"] = Clothing.layers_warmth(ctx.layers, n)
	elif float(ctx.get("wading", 0.0)) > WADE_WET_M:
		n.wet = 1.0
	elif bool(ctx.get("rain", false)) and not indoors:
		n.wet = minf(1.0, float(n.wet) + WET_RAIN_H * world_h)
	else:
		n.wet = maxf(0.0, float(n.wet) - WET_DRY_H * world_h)
	var cold := WARM_DARK * float(ctx.get("dark", 0.0)) + WARM_WIND * float(ctx.get("wind", 0.0)) * (0.3 if indoors else 1.0) \
		+ (WARM_RAIN if bool(ctx.get("rain", false)) and not indoors else 0.0) + WARM_WET * float(n.wet)
	cold *= float(ctx.get("cold_mult", 1.0)) * BodySeason.cold_mult(season) * (1.0 - clampf(float(ctx.get("clothing", 0.0)), 0.0, BodySeason.CLOTHING_MAX))
	var heat := WARM_BASE + (WARM_MOVE if bool(ctx.get("moving", false)) and asleep == "" else 0.0) + (WARM_BED if asleep == "bed" else 0.0)
	var core := float(n.warmth)
	var net := heat - cold
	if net < 0.0:
		core = maxf(MIN_C, core + net * world_h)
	elif core < NORMAL_C:
		core = minf(NORMAL_C, core + net * world_h)
	if core > NORMAL_C:
		core = maxf(NORMAL_C, core - 0.5 * world_h)  # Proposed: nothing heats past normal yet (heat stroke: phase D)
	n.warmth = clampf(core, MIN_C, MAX_C)
	n.hygiene = maxf(0.0, float(n.hygiene) - 100.0 / HYGIENE_DAYS / 24.0 * world_h)
	# Sickness runs its course; starving counts its hours.
	if not sick.is_empty():
		var left := float(n.sick.left_h) - world_h
		n.sick = {} if left <= 0.0 else {"id": String(n.sick.id), "left_h": left, "onset_h": 0.0}
	n.starving_h = float(n.get("starving_h", 0.0)) + world_h if float(n.calories) <= 0.0 else 0.0
	_derive(n)


## Host: `seconds` of a survivor's life (Survival.server_drain): steps the stores and puts their
## effects on the body: stamina return, aim sway, blood lost when empty.
## The New world screen's "needs" option scales the body's time (call 49: x0.6 to x1.5; Proposed:
## every store at once, sleep's restore included).
static func server_step(s: Soldier, n: Dictionary, seconds: float) -> void:
	var world_h := seconds / (Survival.DAY_MIN * 60.0) * 24.0 * Survival.option_mult("needs")
	var ctx := context_of(s)
	step(n, world_h, ctx)
	Body.server_step(s, n, world_h, ctx)  # phase D: the bite's clock, wounds, sicknesses, the season
	Mind.server_step(s, n, world_h, ctx)  # the nerve, habits, the shaking sickness (calls 116-118)
	if s.vitals.is_dead():
		return
	apply(s, n)
	var hurt := blood_cost(n)
	if hurt > 0.0 and s.vitals.is_up():
		s.vitals.server_damage(hurt * seconds)


## Puts `n`'s effects on `s` (host, and the owner for the parts he simulates).
static func apply(s: Soldier, n: Dictionary) -> void:
	s.needs_stamina = stamina_mult(n)
	if s.vitals:
		s.vitals.needs_sway = sway_mult(n)


## Damage a second (Vitals.server_damage) the empty stores cost now.
static func blood_cost(n: Dictionary) -> float:
	var hurt := EMPTY_DAMAGE * 2.0 if float(n.water) <= 0.0 else 0.0
	if float(n.calories) <= 0.0 and float(n.get("starving_h", 0.0)) >= STARVE_GRACE_H:
		hurt += EMPTY_DAMAGE
	return hurt


# --- Effects ---------------------------------------------------------------------------------

## S1's share from hunger and thirst (1 fed and watered, less when low).
static func food_stamina_mult(hunger: float, thirst: float) -> float:
	var worst := minf(hunger, thirst)
	if worst >= LOW:
		return 1.0
	return lerpf(EMPTY_STAMINA_MULT, LOW_STAMINA_MULT, worst / LOW)


## Stamina return's share: food and water, sleep, shivering.
static func stamina_mult(n: Dictionary) -> float:
	ensure(n)
	var m := food_stamina_mult(float(n.hunger), float(n.thirst))
	m *= lerpf(SLEEPY_STAMINA_MULT, 1.0, 1.0 - dulled(n))
	m *= 1.0 - SHIVER_STAMINA * shivering(n)
	m *= Body.stamina_factor(n)  # fever, sickness, sepsis, heat stroke
	m *= Mind.stamina_factor(n)  # low nerve, withdrawal (Mind)
	return m


## Aim sway's share (Vitals.needs_sway): tired and shivering hands shake.
static func sway_mult(n: Dictionary) -> float:
	return 1.0 + DULLED_SWAY * dulled(n) + SHIVER_SWAY * shivering(n) + Body.sway_add(n) + Mind.sway_add(n)  # shaking hands: nerve, withdrawal


## How dulled the senses are by lack of sleep, 0 (rested) .. 1 (none left): the stealth model can
## shrink a survivor's sight and hearing by it (call 47).
static func dulled(n: Dictionary) -> float:
	return maxf(clampf((SLEEP_LOW - float(n.get("sleep", 100.0))) / SLEEP_LOW, 0.0, 1.0), maxf(Body.dulled_add(n), Mind.dulled_add(n)))  # and delirium, ringing ears (Mind)


## How hard he shivers, 0 (warm) .. 1 (frozen through).
static func shivering(n: Dictionary) -> float:
	return clampf((SHIVER_C - float(n.get("warmth", NORMAL_C))) / (SHIVER_C - FROZEN_C), 0.0, 1.0)


## Wound infection risk from being dirty, 0 .. 1 (exposed for the infection chain, phase D).
static func infection_risk(n: Dictionary) -> float:
	return clampf((HYGIENE_RISK - float(n.get("hygiene", 100.0))) / HYGIENE_RISK, 0.0, 1.0)


## A body's dulled value (0 off survival or with no stores yet).
static func dulled_of(s: Soldier) -> float:
	return dulled(s.get_meta(&"needs")) if s.has_meta(&"needs") else 0.0


# --- Eating and drinking ---------------------------------------------------------------------

## Whether `item` carries food values (kcal or water_l).
static func has_values(item: ItemData) -> bool:
	return item != null and (item.stats.has("kcal") or item.stats.has("water_l"))


## A water item's quality: its state's (treated) else the item's, else clean.
static func quality_of(item: ItemData, state: Dictionary = {}) -> String:
	return String(state.get("quality", item.stats.get("quality", "clean") if item else "clean"))


## Treats water (boiled, filtered, a tablet: phase B/D): the item's `state` says clean after.
static func treat_water(state: Dictionary) -> Dictionary:
	state["quality"] = "clean"
	return state


## Host: one of `item` (with its entry `state`) eaten or drunk: its values into the stores, and a
## raw or unclean one rolls its sickness. Returns the sickness id that started, or "".
static func eat(n: Dictionary, item: ItemData, state: Dictionary = {}) -> String:
	ensure(n)
	_take_legacy(n)
	var st := item.stats
	n.calories = clampf(float(n.calories) + float(st.get("kcal", 0.0)), 0.0, MAX_KCAL)
	n.water = clampf(float(n.water) + float(st.get("water_l", 0.0)), 0.0, MAX_L)
	n.protein = minf(100.0, float(n.protein) + float(st.get("protein", 0.0)) / PROTEIN_G_DAY * MACRO_DAY)
	n.carbs = minf(100.0, float(n.carbs) + float(st.get("carbs", 0.0)) / CARBS_G_DAY * MACRO_DAY)
	n.fat = minf(100.0, float(n.fat) + float(st.get("fat", 0.0)) / FAT_G_DAY * MACRO_DAY)
	var vits: Dictionary = st.get("vitamins", {})
	var per_day := 100.0 / VITAMIN_DAYS
	n.vitamin_c = minf(100.0, float(n.vitamin_c) + float(vits.get("C", 0.0)) / 100.0 * per_day)
	n.vitamin_d = minf(100.0, float(n.vitamin_d) + float(vits.get("D", 0.0)) / 100.0 * per_day)
	n.iron = minf(100.0, float(n.iron) + float(vits.get("iron", 0.0)) / 100.0 * per_day)
	var started := ""
	if bool(st.get("raw", false)):
		var chance := float(WATER_RISK.get(quality_of(item, state), 0.0)) if st.has("water_l") and not st.has("kcal") else RAW_FOOD_RISK
		var kind := "dysentery" if st.has("water_l") and not st.has("kcal") else "food_poisoning"
		var roll := force_roll if force_roll >= 0.0 else randf()
		if chance > 0.0 and roll < chance:
			started = kind
			n.sick = {"id": kind, "left_h": float(SICKNESS[kind].hours), "onset_h": ONSET_H}
	_derive(n)
	return started


## Host: S1's fallback for items without values: a "water" dose is WATER_PER_DOSE% of FED_L, a
## "ration" dose FOOD_PER_DOSE% of FED_KCAL. Returns whether it counted.
static func feed_dose(n: Dictionary, drug: StringName, doses: float) -> bool:
	ensure(n)
	_take_legacy(n)
	if drug == &"water":
		n.water = minf(MAX_L, float(n.water) + FED_L * Survival.WATER_PER_DOSE / 100.0 * doses)
	elif drug == &"ration":
		n.calories = minf(MAX_KCAL, float(n.calories) + FED_KCAL * Survival.FOOD_PER_DOSE / 100.0 * doses)
	else:
		return false
	_derive(n)
	return true


## Washing (a basin, a river; soap better): hygiene up by `amount` (phase D's pieces call it).
static func wash(n: Dictionary, amount: float) -> void:
	n.hygiene = minf(100.0, float(n.get("hygiene", 0.0)) + amount)


# --- Words -----------------------------------------------------------------------------------

## Plain words for each store (docs/survival_medical.md section 1: "hungry", "parched",
## "frozen through"), as {store: word}.
static func words(n: Dictionary) -> Dictionary:
	ensure(n)
	var w := {}
	w.calories = _band(float(n.hunger), [[60.0, "fed"], [35.0, "peckish"], [15.0, "hungry"], [0.01, "starving"]], "running on empty")
	w.water = _band(float(n.thirst), [[60.0, "watered"], [35.0, "thirsty"], [15.0, "parched"], [0.01, "dehydrated"]], "bone dry")
	w.sleep = _band(float(n.sleep), [[60.0, "rested"], [SLEEP_LOW, "tired"], [10.0, "exhausted"]], "dead on your feet")
	var c := float(n.warmth)
	w.warmth = "overheating" if c >= BodySeason.HEAT_STROKE_C and not Body.has_fever(n) else ("feverish" if c >= 37.8 else ("warm" if c >= 36.5 else ("chilly" if c >= SHIVER_C else ("cold, shivering" if c >= FROZEN_C + 0.5 else ("freezing" if c > FROZEN_C else "frozen through")))))
	w.hygiene = _band(float(n.hygiene), [[60.0, "clean"], [30.0, "grubby"]], "filthy")
	for k: String in ["protein", "carbs", "fat", "vitamin_c", "vitamin_d", "iron"]:
		w[k] = _band(float(n[k]), [[50.0, "good"], [20.0, "low"]], "lacking")
	var wet := float(n.wet)
	w.wet = "soaked" if wet > 0.5 else ("damp" if wet > 0.1 else "dry")
	var sd: Dictionary = n.get("sick", {})
	var sick := String(sd.get("id", "")) if float(sd.get("onset_h", 0.0)) <= 0.0 else ""  # not felt yet
	w.sick = String(SICKNESS[sick].name) if SICKNESS.has(sick) else "well"
	return w


static func _band(v: float, bands: Array, last: String) -> String:
	for b: Array in bands:
		if v >= float(b[0]):
			return String(b[1])
	return last


## The HUD's small signs (section 7: only what is low), as short words; empty when all is well.
static func signs(n: Dictionary) -> Array:
	if n.is_empty():
		return []
	var w := words(n)
	var out: Array = []
	if float(n.hunger) < 35.0:
		out.append(w.calories)
	if float(n.thirst) < 35.0:
		out.append(w.water)
	if float(n.sleep) < SLEEP_LOW:
		out.append(w.sleep)
	if float(n.warmth) < SHIVER_C or float(n.warmth) >= 37.8:
		out.append(w.warmth)
	if float(n.wet) > 0.5:
		out.append(w.wet)
	if w.sick != "well" or not Sickness.shown(n).is_empty():
		out.append("sick")
	if float(n.hygiene) < 30.0:
		out.append(w.hygiene)
	out.append_array(Mind.signs(n))  # shaken, withdrawal (Mind)
	return out


## The body readout (the body screen's first form, section 7: words and numbers, no figure yet):
## every store as a line.
static func readout(n: Dictionary) -> String:
	if n.is_empty():
		return "Body: nothing known yet"
	var w := words(n)
	var lines: Array = ["Body"]
	lines.append("Calories: %s (%d kcal)" % [w.calories, roundi(float(n.calories))])
	lines.append("Water: %s (%.1f l)" % [w.water, float(n.water)])
	lines.append("Protein: %s (%d)   Carbs: %s (%d)   Fat: %s (%d)" % [w.protein, roundi(float(n.protein)), w.carbs, roundi(float(n.carbs)), w.fat, roundi(float(n.fat))])
	lines.append("Vitamin C: %s (%d)   Vitamin D: %s (%d)   Iron: %s (%d)" % [w.vitamin_c, roundi(float(n.vitamin_c)), w.vitamin_d, roundi(float(n.vitamin_d)), w.iron, roundi(float(n.iron))])
	lines.append("Sleep: %s (%d)" % [w.sleep, roundi(float(n.sleep))])
	lines.append("Warmth: %s (%.1f C), %s" % [w.warmth, float(n.warmth), w.wet])
	lines.append("Hygiene: %s (%d)" % [w.hygiene, roundi(float(n.hygiene))])
	var sick: Dictionary = n.get("sick", {})
	lines.append("Health: %s" % (w.sick if w.sick == "well" else "%s (%d h left)" % [w.sick, ceili(float(sick.left_h))]))
	if String(n.get("asleep", "")) != "":
		lines.append("Asleep (%s)" % n.asleep)
	var mind := Mind.words(n)
	if not mind.is_empty():
		lines.append("Mind: %s" % ", ".join(PackedStringArray(mind)))
	return "\n".join(lines)


# --- S1's hunger and thirst ------------------------------------------------------------------

## Hunger and thirst from calories and water; remembers them to spot a write from S1's code.
static func _derive(n: Dictionary) -> void:
	n.hunger = clampf(float(n.calories) / FED_KCAL * 100.0, 0.0, 100.0)
	n.thirst = clampf(float(n.water) / FED_L * 100.0, 0.0, 100.0)
	n._seen_hunger = n.hunger
	n._seen_thirst = n.thirst


## A hunger or thirst written since the last step (S1's respawn, a test) writes through.
static func _take_legacy(n: Dictionary) -> void:
	if n.has("_seen_hunger") and not is_equal_approx(float(n.hunger), float(n._seen_hunger)):
		n.calories = FED_KCAL * float(n.hunger) / 100.0
	if n.has("_seen_thirst") and not is_equal_approx(float(n.thirst), float(n._seen_thirst)):
		n.water = FED_L * float(n.thirst) / 100.0
