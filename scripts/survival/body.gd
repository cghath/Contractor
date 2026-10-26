class_name Body
extends RefCounted
## The body's phase D (docs/survival_medical.md sections 2, 3, 5, 6): what Needs' metabolism
## steps alongside the stores every time a survivor's body is stepped (Needs.server_step calls
## server_step): the bite's fever clock (BiteFever), wound infection and healing (Infection), the
## sicknesses (Sickness), hygiene (Hygiene), the seasons' heat and frostbite (BodySeason), and
## their effects on stamina, aim and the senses (read by Needs.stamina_mult, sway_mult, dulled).
## Also the hooks the rest of the game calls: a bite landed (on_bitten, from Melee), a treatment
## done (on_treated, from Soldier._log_care), and the body screen's actions (server_action).

## The extra keys phase D keeps in the body's Dictionary (a new survivor starts without them).
const KEYS: Array[String] = ["bite", "wounds", "wound_seq", "abx", "ills", "chill_h", "def", "care_h", "gore_h", "clothes_h",
	"frost_h", "cough_h", "vision_sway", "permanent", "killed_by", "blood_type", "immune_known", "heat_h", "gore_seen"]
## Heat stroke's toll a world hour at the top of the scale (Vitals.server_damage), and
## frostbite's wound.
const HEAT_DAMAGE_H := 3.0
const FROST_PARTS := {"hands": [&"forearm_l", &"forearm_r"], "face": [&"face"]}
const DRESSINGS: Array[StringName] = [&"pressure_bandage", &"hemostatic_gauze", &"burn_dressing", &"chest_seal"]
const NOTICE_M := 15.0


## A new survivor's body: none of phase D's state carried over (Needs.respawn).
static func reset(n: Dictionary) -> void:
	for k: String in KEYS:
		n.erase(k)


# --- Effects (Needs reads these) ----------------------------------------------------------

## The core a fever holds the body at: the bite's, the wounds', a sickness's (0 none).
static func fever_c(n: Dictionary) -> float:
	return maxf(float(BiteFever.effects(n).get("fever", 0.0)), maxf(Infection.fever_c(n), Sickness.fever_c(n)))


static func has_fever(n: Dictionary) -> bool:
	return fever_c(n) > 0.0


static func stamina_factor(n: Dictionary) -> float:
	var m := float(BiteFever.effects(n).get("stamina", 1.0)) * Sickness.stamina_mult(n)
	var worst := Infection.worst(n)
	if worst >= 3:
		m *= 0.5
	elif worst == 2:
		m *= 0.8
	if BodySeason.heat_stroke(n):
		m *= 0.5
	return m


static func sway_add(n: Dictionary) -> float:
	var a := float(BiteFever.effects(n).get("sway", 0.0)) + Sickness.sway_add(n)
	if Infection.worst(n) >= 3:
		a += 0.6
	if BodySeason.heat_stroke(n):
		a += 0.5
	return a


## The senses dulled by delirium (the bite's, sepsis's), 0 .. 1 (Needs.dulled takes the larger).
static func dulled_add(n: Dictionary) -> float:
	var d := float(BiteFever.effects(n).get("dulled", 0.0))
	if Infection.worst(n) >= 3:
		d = maxf(d, 0.5)
	return d


# --- Stepping ------------------------------------------------------------------------------

## Host: `world_h` world hours of `s`'s body `n` in `ctx` (Needs.context_of's keys, "season"):
## everything phase D runs, after Needs.step.
static func server_step(s: Soldier, n: Dictionary, world_h: float, ctx: Dictionary) -> void:
	if world_h <= 0.0 or s == null or s.vitals == null or s.vitals.is_dead():
		return
	var season := String(ctx.get("season", "spring"))
	var rain := bool(ctx.get("rain", false)) and not bool(ctx.get("indoors", false))
	n.care_h = maxf(0.0, float(n.get("care_h", 0.0)) - world_h)
	Hygiene.server_take_gore(s, n)  # masking's smear (the world lane's metas)
	Hygiene.step(n, world_h, season, rain)
	var abx := Infection.covered(n)
	# Wounds: infection and healing.
	var by_id := Infection.server_sync(s, n)
	var bleeding := {}
	for id: int in by_id:
		if s.vitals.wound_bleeds(by_id[id]):
			bleeding[id] = true
	var res := Infection.step(n, world_h, {"risk": Hygiene.risk(n), "mud": BodySeason.mud_mult(season) if rain else 1.0, "bleeding": bleeding})
	for id: int in res.healed:
		if by_id.has(id):
			s.vitals.server_heal(by_id[id])
	var damage := float(res.gangrene_h) * Infection.GANGRENE_DAMAGE_H
	# The bite.
	var ev := BiteFever.step(n, world_h, {"abx": abx})
	n.vision_sway = float(BiteFever.effects(n).get("vision", 0.0))
	# Sicknesses, the cough.
	var ill := Sickness.step(n, world_h, {"abx": abx})
	if Sickness.coughing(n):
		n.cough_h = float(n.get("cough_h", 0.0)) + world_h
		if float(n.cough_h) >= Sickness.COUGH_EVERY_H:
			n.cough_h = 0.0
			Sickness.server_cough(s)
	# Fever and thirst.
	var fever := fever_c(n)
	if fever > 0.0:
		n.warmth = maxf(float(n.warmth), fever)
	n.water = maxf(0.0, float(n.water) - float(BiteFever.effects(n).get("water", 0.0)) * world_h / 24.0)
	# The season: heat in summer, frostbite in winter.
	var heat := BodySeason.heat_gain(n, ctx)
	if heat > 0.0:
		n.warmth = minf(Needs.MAX_C, float(n.warmth) + heat * world_h)
	if float(n.warmth) >= Needs.MAX_C and fever <= 0.0:
		damage += HEAT_DAMAGE_H * world_h
	_frost(s, n, world_h, season, ctx)
	Needs._derive(n)
	if damage > 0.0:
		s.vitals.server_damage(damage)
	# What happened, told and done.
	match ev:
		"fever", "delirium":
			_notice(s, ev)
		"immune":
			Survival._tell(s, "The bite healed clean. No fever, nothing. You don't turn")
			Survival._journal_line("%s was bitten a week ago and never turned: immune." % _name_of(s))
		"collapse":
			BiteFever.server_collapse(s)
			return
	if bool(res.death):
		s.vitals.last_cause = {"cause": "sepsis"}
		Survival._journal_line("%s died of a wound gone bad." % _name_of(s))
		s.vitals.server_kill()
		return
	if ill == "death":
		s.vitals.last_cause = {"cause": String(n.get("killed_by", "sickness"))}
		Survival._journal_line("%s died of %s." % [_name_of(s), String((Sickness.ILLS.get(String(n.get("killed_by", "")), {}) as Dictionary).get("name", "sickness"))])
		s.vitals.server_kill()


## Winter, outdoors, the core low for hours: frostbite on uncovered hands or face (a wound).
static func _frost(s: Soldier, n: Dictionary, world_h: float, season: String, ctx: Dictionary) -> void:
	if season != "winter" or bool(ctx.get("indoors", false)) or float(n.warmth) >= BodySeason.FROST_C:
		n.frost_h = maxf(0.0, float(n.get("frost_h", 0.0)) - world_h)
		return
	n.frost_h = float(n.get("frost_h", 0.0)) + world_h
	if float(n.frost_h) < BodySeason.FROST_H:
		return
	n.frost_h = 0.0
	for where: String in ["hands", "face"]:
		if BodySeason.covers(s.inventory, where):
			continue
		var parts: Array = FROST_PARTS[where]
		var part: StringName = parts[randi() % parts.size()]
		var w := s.vitals.server_add_wound(part, "graze", 0.0)
		w["name"] = &"frostbite"
		Survival._tell(s, "Frostbite: your %s are white and numb" % where)
		return


static func _name_of(s: Soldier) -> String:
	if not s.is_ai():
		return Survival.survivor_name(s)
	var layer := SurvivorsLayer.find(s)
	var rec := layer.record_of(s) if layer else {}
	return String(rec.get("name", s.log_name()))


## The fever noticed: a companion near says so (a player's), or the delirious one says odd things.
static func _notice(s: Soldier, stage: String) -> void:
	var layer := SurvivorsLayer.find(s)
	if not s.is_ai():
		Survival._tell(s, "You're burning up: the bite's fever" if stage == "fever" else "The world tilts and swims: delirium")
	if layer == null:
		return
	var lines: Array = BiteFever.LINES.get(stage, [])
	var best: Soldier = null
	for c: Soldier in layer.companions():
		if c != s and c.vitals.is_up() and c.global_position.distance_to(s.global_position) <= NOTICE_M:
			if best == null or c.global_position.distance_to(s.global_position) < best.global_position.distance_to(s.global_position):
				best = c
	if best and not lines.is_empty():
		layer.say(best, String(lines[randi() % lines.size()]))
	if stage == "delirium" and s.is_ai() and not layer.record_of(s).is_empty():
		layer.say(s, String(BiteFever.LINES.odd[randi() % (BiteFever.LINES.odd as Array).size()]))


# --- Hooks ------------------------------------------------------------------------------------

## Whether `s` is immune (the immunity roll on their person record, the player's survivor
## record, or the body's own flag).
static func immune_of(s: Soldier) -> bool:
	var n := Survival.needs_of(s)
	if bool(n.get("immune", false)):
		return true
	var layer := SurvivorsLayer.find(s)
	if layer and bool(layer.record_of(s).get("immune", false)):
		return true
	return not s.is_ai() and bool(Survival.survivor_of(s).get("immune", false))


## The medical level of `s`: the RPG line for a player, a companion's record's skills, else 0.
static func medical_level(s: Soldier) -> int:
	if Rpg.active(s):
		return Rpg.level(s, "medical")
	var layer := SurvivorsLayer.find(s)
	if layer:
		var skills: Variant = layer.record_of(s).get("skills", {})
		if skills is Dictionary:
			return int((skills as Dictionary).get("medical", 0))
	return 0


## Host: a zombie's bite (Melee's "bite" hit) landed on `victim`'s `part`: the wound is a bite
## (dirty from the start) and, if not already, the clock starts (an immune body's runs out).
static func on_bitten(victim: Soldier, part: StringName) -> void:
	if not Survival.running or victim == null or victim.vitals == null or victim.vitals.is_dead() or victim.vitals.undead:
		return
	var n := Survival.needs_of(victim)
	Infection.server_sync(victim, n)
	var newest := {}
	for r: Dictionary in Infection.on_part(n, String(part)):
		if newest.is_empty() or int(r.id) > int(newest.id):
			newest = r
	if not newest.is_empty():
		newest.bite = true
		newest.stage = maxi(int(newest.stage), 1)
	if BiteFever.bitten(n):
		return
	BiteFever.start(n, immune_of(victim), Survival.day())
	victim.set_meta(&"bitten", true)
	var layer := SurvivorsLayer.find(victim)
	var rec := layer.record_of(victim) if layer else {}
	if not rec.is_empty():
		rec["bitten"] = true
		rec["bite_day"] = Survival.day()
		Moods.add(rec, "bitten")
	elif not victim.is_ai():
		var srec := Survival.survivor_of(victim)
		srec["bitten"] = true
		srec["bite_day"] = Survival.day()
		Survival._tell(victim, "Bitten")
	Survival._journal_line("%s was bitten." % _name_of(victim))


## Host: `treater` finished `item_id` on `target`'s `part` (Soldier._log_care): a dressing is a
## clean dressing on the wound, blood is checked against the patient's type, and a doctor's hands
## (medical 5+) slow a bite's clock for a day.
static func on_treated(treater: Soldier, target: Node, item_id: StringName, part: StringName) -> void:
	var patient := target as Soldier
	if not Survival.running or patient == null or not is_instance_valid(patient) or patient.vitals == null:
		return
	var n := Survival.needs_of(patient)
	if item_id in DRESSINGS:
		Infection.server_sync(patient, n)
		Infection.dress(n, String(part))
	elif String(item_id).begins_with("blood_"):
		Sickness.server_transfused(patient, {})
	if treater != null and medical_level(treater) >= BiteFever.DOCTOR_LEVEL:
		n.care_h = BiteFever.DOCTOR_CARE_H


## Host: the body screen's actions on `target` by `actor`: "antibiotics" (a dose from the actor's
## kit), "clean" (`arg`: "antiseptic", "water" (a clean bottle), "dirty_water"), "surgery" (`arg`:
## a Surgery op), "drink" (a strong drink for the patient), "wash" (`arg`: where), "serum" (Cure),
## "send_away" / "keep" / "put_down" (a bitten companion: BiteFever.server_choice). Returns what
## the actor is told.
static func server_action(actor: Soldier, target: Soldier, action: String, part: String, arg: String) -> String:
	var n := Survival.needs_of(target)
	match action:
		"antibiotics":
			if actor.inventory.count_of(&"antibiotics") <= 0:
				return "No antibiotics"
			if not Infection.dose(n):
				return "Too soon for another dose"
			FallenStory.take_one(actor, "antibiotics")
			var doses := int(Infection.course(n).get("doses", 0))
			return "A dose of antibiotics (%d of %d in the course)" % [doses, Infection.COURSE]
		"clean":
			Infection.server_sync(target, n)
			var how := arg
			match arg:
				"antiseptic":
					if not FallenStory.take_one(actor, "antiseptic"):
						return "No antiseptic"
				"water":
					if not FallenStory.take_one(actor, "water_bottle"):
						return "No clean water"
					how = "boiled"
				"dirty_water":
					if not FallenStory.take_one(actor, "dirty_water_bottle"):
						return "No water"
					how = "water"
			var better := Infection.clean(n, part, how)
			return "Cleaned" if better > 0 else "Cleaned, for what it's worth"
		"surgery":
			return String(Surgery.server_operate(actor, target, arg, part).get("text", ""))
		"drink":
			return "A long swallow: numb enough" if Surgery.server_drink(target) else "Nothing strong to drink"
		"wash":
			return Hygiene.server_wash(actor, arg if arg != "" else "basin")
		"serum":
			var layer := SurvivorsLayer.find(target)
			var rec := layer.record_of(target) if layer else {}
			if actor.inventory.count_of(&"serum") <= 0:
				return "No serum"
			FallenStory.take_one(actor, "serum")
			Cure.server_apply(target, rec, false)
			if not rec.is_empty():
				BiteFever.on_cured(layer, rec)
			return "The serum's in"
		"send_away", "keep", "put_down":
			var layer := SurvivorsLayer.find(target)
			var why := BiteFever.server_choice(layer, layer.record_of(target) if layer else {}, action)
			return why if why != "" else "Done"
	return ""
