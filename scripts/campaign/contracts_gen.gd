class_name ContractGen
extends RefCounted
## Contract generation and the deal maths, pure (no campaign state): the board's offers from
## a seed, the 1-5 difficulty rating, the briefing that sometimes understates the threat, and
## MW5-style negotiation (wave 4, W10). Contracts (the autoload) owns the offers and calls this.
##
## A contract is a JSON-safe Dictionary:
## - "cid" (given by Contracts), "type", "title", "brief", "source" ("board", "fixer",
##   "safe" or "lead"), "fixer", "employer", "target" (faction ids);
## - "zone_id", "zone_name", "zone_kind" ("contract" or "hot"), "region"; where in the zone:
##   "module" (the target module's type), "module_id" (its id in the zone's layout, "" if the
##   zone has none), "module_name";
## - what the briefing says: "rated" (1-5), "enemy_est", "quality_est", "threats_known",
##   "intel_accuracy" (0-1: how far to trust it);
## - the truth, host only (public_view strips it until "revealed"): "true_rating",
##   "enemy_count", "quality", "threats", "understated";
## - "base_pay", "days", "objectives" (the type's templates, resolved for the target module:
##   mission_target), "offered_day", "expires_day",
##   "state" ("offered", then Contracts' states), and once accepted "terms" and "deal".

## Keys only the host knows until the threat is revealed.
const HIDDEN_KEYS := ["true_rating", "enemy_count", "quality", "threats", "understated"]
## Proposed: how far off intel can be at no accuracy (_intel_fog): the share of the count, and
## the quality (0-1) either way.
const INTEL_COUNT_ERROR := 0.7
const INTEL_QUALITY_ERROR := 0.35
## Below this accuracy the briefing gives the enemy's quality in words, not a figure.
const INTEL_QUALITY_WORDS_BELOW := 0.6
## Clawback terms (Captain): what a voided contract gives back of its advance.
const NO_CLAWBACK := "none"
const PRORATED_CLAWBACK := "prorated"
const FULL_CLAWBACK := "full"


static func S(key: String) -> float:
	return MissionRegistry.setting_f(key)


## The 1-5 difficulty rating from enemy size and quality and the known threats (Proposed
## formula): 4 average fighters with nothing else is a 1, each 6 more fighters, 0.4 of
## quality and each threat's weight (armor 1.5, AA or mortars 1, an MG nest 0.5) add a step.
static func rating(enemy_count: int, quality: float, threats: Array) -> int:
	var score := (enemy_count - 4) / 6.0 + (quality - 0.3) * 2.5
	for t: Variant in threats:
		score += float(MissionRegistry.threat(String(t)).get("weight", 0.5))
	return clampi(1 + floori(score), 1, 5)


## What intel of accuracy `intel` (0-1) makes of the truth (Proposed): {"count", "quality",
## "threats"}. The count is off by up to INTEL_COUNT_ERROR * (1 - intel) of it either way
## (about ±50% at 30% intel, ±4% at 95%), the quality by up to INTEL_QUALITY_ERROR *
## (1 - intel); each real threat goes unreported with a chance of (1 - intel) / 2, and one that
## isn't there gets reported with a chance of (1 - intel) / 4. Errors near zero are likelier
## than the full amount. Leaves `rng` as it was.
static func _intel_fog(rng: RandomNumberGenerator, intel: float, count: int, quality: float, threats: Array, pool: Array) -> Dictionary:
	var roll := RandomNumberGenerator.new()
	roll.seed = hash([rng.state, "intel"])
	var miss := clampf(1.0 - intel, 0.0, 1.0)
	var spread := func() -> float: return roll.randf() + roll.randf() - 1.0  # -1..1, peaked at 0
	var est_count := maxi(1, roundi(count * (1.0 + spread.call() * INTEL_COUNT_ERROR * miss)))
	var est_quality := clampf(quality + spread.call() * INTEL_QUALITY_ERROR * miss, 0.05, 1.0)
	var known: Array = []
	for t: Variant in threats:
		if roll.randf() >= miss * 0.5:
			known.append(t)
	var absent := pool.filter(func(t: Variant) -> bool: return t not in threats)
	if not absent.is_empty() and roll.randf() < miss * 0.25:
		known.append(absent[roll.randi() % absent.size()])
	return {"count": est_count, "quality": snappedf(est_quality, 0.01), "threats": known}


## The chance a briefing understates the threat: likelier on poor intel (Proposed: 35% at
## no intel, 5% at perfect intel).
static func understate_chance(intel_accuracy: float) -> float:
	return lerpf(S("understate_chance_low_intel"), S("understate_chance_high_intel"), clampf(intel_accuracy, 0.0, 1.0))


## The board for one day: `count` offers from `board_seed`, the same every time for the same
## seed and inputs. `rep` is reputation by faction (fixers whose faction rep reaches their
## "min_rep" add one special job each); the first SAFE_OFFERS are cheap low-risk work (the
## safety floor).
static func generate_board(board_seed: int, day: int, rep: Dictionary, count: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = board_seed
	var offers: Array = []
	for i in mini(MissionRegistry.setting_i("safe_offers", 1), count):
		offers.append(generate(rng, {"day": day, "source": "safe"}))
	while offers.size() < count:
		offers.append(generate(rng, {"day": day, "source": "board"}))
	for fixer: Dictionary in MissionRegistry.fixers():
		if int(rep.get(String(fixer.faction), 0)) >= int(fixer.min_rep):
			offers.append(generate(rng, {"day": day, "source": "fixer", "fixer": fixer}))
	return offers


## One contract. `ctx`: "day", "source" ("board", "safe", "fixer", "lead"), and optionally
## "fixer" (a fixers entry), "type", "zone_kind", "zone_id", "employer".
static func generate(rng: RandomNumberGenerator, ctx: Dictionary) -> Dictionary:
	var source: String = ctx.get("source", "board")
	var fixer: Dictionary = ctx.get("fixer", {})
	var safe := source == "safe"
	# What kind of job, where.
	var kind: String = ctx.get("zone_kind", "contract" if safe or source == "fixer" or rng.randf() >= S("hot_zone_chance") else "hot")
	var type_ids: Array = fixer.get("types", MissionRegistry.types()) if ctx.get("type", "") == "" else [ctx.type]
	type_ids = type_ids.filter(func(t: String) -> bool: return not MissionRegistry.type_def(t).is_empty())
	if type_ids.is_empty():
		type_ids = MissionRegistry.types()
	var type_id: String = type_ids[rng.randi() % type_ids.size()]
	var def := MissionRegistry.type_def(type_id)
	var zone := MissionRegistry.zone(ctx.get("zone_id", ""))
	if zone.is_empty():
		var options := MissionRegistry.zones_for(MissionRegistry.type_modules(def), kind)
		if options.is_empty():
			kind = "contract"
			options = MissionRegistry.zones_for(MissionRegistry.type_modules(def), kind)
		zone = options[rng.randi() % options.size()] if not options.is_empty() else {"zone_id": "unknown", "name": "Unknown", "region": "", "kind": kind}
	kind = String(zone.get("kind", kind))
	var hot := kind == "hot"
	# Who pays: the fixer's faction, the hot zone's faction, or any employer.
	var employers := MissionRegistry.employers()
	var employer: String = ctx.get("employer", "")
	if employer == "":
		employer = fixer.get("faction", zone.get("faction", employers[rng.randi() % employers.size()] if not employers.is_empty() else ""))
	var enemies := MissionRegistry.enemies()
	var target: String = enemies[rng.randi() % enemies.size()] if not enemies.is_empty() else ""
	# The real force.
	var count_range: Array = def.get("enemy_count", [4, 8])
	var quality_range: Array = def.get("enemy_quality", [0.3, 0.6])
	var enemy_count := int(count_range[0]) if safe else rng.randi_range(int(count_range[0]), int(count_range[1]))
	var quality := float(quality_range[0]) if safe else rng.randf_range(float(quality_range[0]), float(quality_range[1]))
	var threats: Array = []
	if not safe:
		var pool: Array = (def.get("threat_pool", []) as Array).duplicate()
		var n := rng.randi_range(0, 2) + (1 if hot else 0)
		while n > 0 and not pool.is_empty():
			threats.append(pool.pop_at(rng.randi() % pool.size()))
			n -= 1
	if hot:
		enemy_count = roundi(enemy_count * S("hot_zone_enemy_mult"))
		quality = minf(quality + 0.1, 1.0)
	var true_rating := rating(enemy_count, quality, threats)
	# What the briefing says. Better intel is more often right.
	var accuracy_range: Array = MissionRegistry.setting("lead_intel_accuracy" if source == "lead" else "fixer_intel_accuracy" if source == "fixer" else "intel_accuracy", [0.3, 0.95])
	var intel := 0.95 if safe else rng.randf_range(float(accuracy_range[0]), float(accuracy_range[1]))
	var understated := not safe and true_rating > 1 and rng.randf() < understate_chance(intel)
	# Intel is never spot on (Captain): the count, the quality and the threats are off by up to
	# what the intel's accuracy allows. Rolled on its own generator (seeded from the board's,
	# which it leaves alone) so the boards stay as they were.
	var fog := _intel_fog(rng, intel, enemy_count, quality, threats, def.get("threat_pool", []) as Array)
	var est_count: int = fog.count
	var est_quality: float = fog.quality
	var known: Array = fog.threats
	var rated := true_rating
	if understated:
		est_count = maxi(2, roundi(enemy_count * rng.randf_range(0.45, 0.75)))
		est_quality = maxf(0.1, quality - rng.randf_range(0.1, 0.25))
		known = threats.duplicate()  # the client's lowball, not the fog
		if not known.is_empty():
			known.resize(rng.randi_range(0, known.size() - 1))  # at least one threat goes unmentioned
		rated = mini(rating(est_count, est_quality, known), true_rating - 1)
	# Pay follows the rating the client gives.
	var pay_mult := float((MissionRegistry.setting("difficulty_pay", [0, 1, 1, 1, 1, 1]) as Array)[rated])
	pay_mult *= float(fixer.get("pay_mult", 1.0))
	if safe:
		pay_mult *= S("safe_pay_mult")
	if hot:
		pay_mult *= S("hot_zone_pay_mult")
	if source == "lead":
		pay_mult *= S("lead_pay_mult")
	# What happens to the advance if the contract is voided (Captain): fixers are shady, the
	# safe job strict, the rest rolled; a shady client pays less. Rolled on its own generator
	# (seeded from the board's, which it leaves alone) so the boards stay as they were.
	var clawback := clawback_term(rng, source)
	pay_mult *= float(clawback_terms().get(clawback, {}).get("pay_mult", 1.0))
	var step := maxi(MissionRegistry.setting_i("pay_round", 500), 1)
	var base_pay := maxi(step, roundi(float(def.get("base_pay", 40000)) * pay_mult / step) * step)
	var day := int(ctx.get("day", 1))
	var mission := mission_target(rng, def, String(zone.get("zone_id", "")), target)
	var limit_min := int(def.get("time_limit_min", 0))
	return {
		"cid": "", "type": type_id, "title": "%s%s: %s" % [def.get("name", type_id), mission.title_extra, zone.get("name", "")],
		"brief": String(def.get("brief", "")) + (" Time limit: %d min." % limit_min if limit_min > 0 else ""), "source": source, "fixer": fixer.get("fixer", ""),
		"employer": employer, "target": target,
		"zone_id": zone.get("zone_id", ""), "zone_name": zone.get("name", ""), "zone_kind": kind,
		"region": zone.get("region", ""), "module": mission.module, "module_id": mission.module_id, "module_name": MissionRegistry.module_name(mission.module),
		"rated": rated, "enemy_est": est_count, "quality_est": snappedf(est_quality, 0.01),
		"threats_known": known, "intel_accuracy": snappedf(intel, 0.01),
		"true_rating": true_rating, "enemy_count": enemy_count, "quality": snappedf(quality, 0.01),
		"threats": threats, "understated": understated, "revealed": false, "renegotiated": false,
		"clawback": clawback,
		"base_pay": base_pay, "days": int(def.get("days", 1)) + (1 if hot else 0),
		"objectives": mission.objectives,
		"offered_day": day, "expires_day": day + MissionRegistry.setting_i("offer_days", 5),
		"state": "offered",
	}


## Where a contract of type `def` plays in zone `zone_id` and its objectives there: the target
## module (one of the zone layout's modules of a type `def` plays in, else the type's first
## module type with no module id), each template's site (a list picks one the module has; an
## optional one whose site the module lacks is left out), {name} and {module} filled in, a
## person's real name for an HVT (from the `target` faction's nation) or a hostage (Names.mission_person), and the time limit on the required ones. Picked on a
## generator of its own (seeded from `rng`, which it leaves alone) so the boards stay as they
## were. {"module", "module_id", "objectives", "title_extra"}.
static func mission_target(rng: RandomNumberGenerator, def: Dictionary, zone_id: String, target := "") -> Dictionary:
	var pick := RandomNumberGenerator.new()
	pick.seed = hash([rng.state, "mission"])
	var allowed := MissionRegistry.type_modules(def)
	var module_type: String = String(allowed[0]) if not allowed.is_empty() else ""
	var module_id := ""
	var options: Array = (MissionRegistry.zone_def(zone_id).get("modules", []) as Array).filter(
		func(m: Dictionary) -> bool: return String(m.type) in allowed)
	if not options.is_empty():
		var m: Dictionary = options[pick.randi() % options.size()]
		module_type = String(m.type)
		module_id = String(m.id)
	var limit_s := float(def.get("time_limit_min", 0.0)) * 60.0
	var person_name := ""
	var title_extra := ""
	var objectives: Array = []
	for t: Dictionary in def.get("objectives", []):
		var o := t.duplicate(true)
		var listed: Array = t.site if t.get("site") is Array else [String(t.get("site", ""))]
		var choices := listed.filter(func(s: Variant) -> bool: return MissionRegistry.has_site(module_type, String(s)))
		if choices.is_empty():
			if bool(t.get("optional", false)) and not t.has("params"):
				continue
			choices = [listed[0] if not listed.is_empty() else ""]
		var site_id := String(choices[pick.randi() % choices.size()])
		o.site = site_id
		var site := MissionRegistry.site(module_type, site_id)
		var person: Dictionary = site.get("person", {})
		if site.has("of_hvt"):
			person = MissionRegistry.site(module_type, String(site.of_hvt)).get("person", {})
		var friendly := String(person.get("side", "")) == "friendly"
		var name := String(site.get("name", ""))
		if not person.is_empty():
			if person_name == "":
				person_name = Names.mission_person(pick, "hostage" if friendly else "hvt", Names.faction_nation(target))
			name = person_name
		if site.has("person"):
			o["person"] = {"name": person_name, "label": "%s (%s)" % ["Hostage" if friendly else "HVT", person_name]}
		if t.get("site") is Array and title_extra == "":
			title_extra = " (%s)" % name
		o.text = String(t.get("text", "")).replace("{name}", name).replace("{module}", MissionRegistry.module_name(module_type))
		if limit_s > 0.0 and not bool(t.get("optional", false)):
			o["time_limit_s"] = limit_s
		objectives.append(o)
	return {"module": module_type, "module_id": module_id, "objectives": objectives, "title_extra": title_extra}


## The clawback terms (data/contracts.json "clawback_terms"): {term: {"weight", "pay_mult"}}.
static func clawback_terms() -> Dictionary:
	return MissionRegistry.setting("clawback_terms", {"full": {"weight": 1.0, "pay_mult": 1.0}})


## A contract's clawback term ("none", "prorated" or "full") for an offer from `source`:
## fixers' jobs "none", the safe job "full", the rest rolled by weight. Leaves `rng` as it was.
static func clawback_term(rng: RandomNumberGenerator, source: String) -> String:
	var terms := clawback_terms()
	if source == "fixer" and terms.has(NO_CLAWBACK):
		return NO_CLAWBACK
	if source == "safe" and terms.has(FULL_CLAWBACK):
		return FULL_CLAWBACK
	var roll := RandomNumberGenerator.new()
	roll.seed = hash([rng.state, source])
	var total := 0.0
	for t: String in terms:
		total += float(terms[t].get("weight", 0.0))
	var pick := roll.randf() * total
	for t: String in terms:
		pick -= float(terms[t].get("weight", 0.0))
		if pick <= 0.0:
			return t
	return FULL_CLAWBACK


## What a voided contract gives back of its `advance` under its "clawback" term, with
## `done` of its `required` objectives done: all of it ("full", and contracts from before the
## terms), none, or the share not earned ("prorated").
static func clawback_amount(contract: Dictionary, advance: int, done: int, required: int) -> int:
	match String(contract.get("clawback", FULL_CLAWBACK)):
		NO_CLAWBACK:
			return 0
		PRORATED_CLAWBACK:
			return roundi(advance * (1.0 - float(done) / maxf(required, 1)))
	return advance


## The clawback term in words, for the board and the debrief.
static func clawback_text(contract: Dictionary) -> String:
	match String(contract.get("clawback", FULL_CLAWBACK)):
		NO_CLAWBACK:
			return "advance kept if voided"
		PRORATED_CLAWBACK:
			return "advance prorated if voided"
	return "advance returned if voided"


## The contract as a client may see it: the truth stays on the host until it's revealed.
static func public_view(contract: Dictionary) -> Dictionary:
	var view := contract.duplicate(true)
	if not contract.get("revealed", false):
		for key: String in HIDDEN_KEYS:
			view.erase(key)
	return view


## The briefing's estimate of the enemy in words, wider on poor intel.
static func estimate_text(contract: Dictionary) -> String:
	var est := int(contract.get("enemy_est", 0))
	var spread := maxi(1, roundi(est * (1.0 - float(contract.get("intel_accuracy", 0.5)))))
	var threats: Array = (contract.get("threats_known", []) as Array).map(func(t: Variant) -> String: return MissionRegistry.threat_name(String(t)))
	var q := float(contract.get("quality_est", 0))
	var quality := ("quality %d%%" % roundi(q * 100.0)) if float(contract.get("intel_accuracy", 0.5)) >= INTEL_QUALITY_WORDS_BELOW \
		else "looks " + quality_word(q)
	return "%d-%d fighters, %s%s" % [maxi(est - spread, 1), est + spread, quality,
		(", reported threats: " + ", ".join(threats)) if not threats.is_empty() else ", no reported threats"]


## A rough word for an enemy quality (0-1), for a briefing on poor intel.
static func quality_word(q: float) -> String:
	if q < 0.3:
		return "poorly trained"
	if q < 0.55:
		return "trained"
	if q < 0.8:
		return "well trained"
	return "elite"


# --- Negotiation (MW5-style) -------------------------------------------------------------

## Terms with nothing traded: the base pay, the base salvage share, no support budget and
## the standard advance (30%).
static func default_terms() -> Dictionary:
	return {"pay_points": 0, "salvage_points": 0, "support_points": 0, "advance_share": S("advance_share")}


## Negotiation points with a faction at reputation `rep`: a base, plus one per tier above
## neutral (Proposed).
static func max_points(rep: int) -> int:
	var above := maxi(MissionRegistry.tier_index(rep) - MissionRegistry.neutral_tier(), 0)
	return MissionRegistry.setting_i("points_base", 4) + above * MissionRegistry.setting_i("points_per_tier", 1)


## Points the terms spend: one per pay, salvage or support step, and one per advance step
## above the standard advance (a smaller advance gives none back).
static func terms_cost(terms: Dictionary) -> int:
	var advance_steps := maxi(0, ceili((float(terms.get("advance_share", S("advance_share"))) - S("advance_share")) / S("advance_step") - 0.001))
	return int(terms.get("pay_points", 0)) + int(terms.get("salvage_points", 0)) + int(terms.get("support_points", 0)) + advance_steps


## Why `terms` can't be offered with reputation `rep` ("" when they can).
static func terms_problem(terms: Dictionary, rep: int) -> String:
	for key: String in ["pay_points", "salvage_points", "support_points"]:
		if int(terms.get(key, 0)) < 0:
			return "Negative %s" % key
	var advance := float(terms.get("advance_share", S("advance_share")))
	if advance < S("advance_min") - 0.001 or advance > S("advance_max") + 0.001:
		return "The advance must be %d-%d%%" % [roundi(S("advance_min") * 100), roundi(S("advance_max") * 100)]
	if S("salvage_base") + int(terms.get("salvage_points", 0)) * S("salvage_per_point") > S("salvage_max") + 0.001:
		return "Salvage share is capped at %d%%" % roundi(S("salvage_max") * 100)
	if terms_cost(terms) > max_points(rep):
		return "The client won't go that far (%d of %d points)" % [terms_cost(terms), max_points(rep)]
	return ""


## What `terms` make of a contract: the total pay, the advance paid on signing (kept even if
## the contract fails), the completion pay, the salvage share and the support budget.
static func deal(contract: Dictionary, terms: Dictionary) -> Dictionary:
	var pay_total := roundi(int(contract.get("base_pay", 0)) * (1.0 + int(terms.get("pay_points", 0)) * S("pay_per_point")))
	var advance_share := clampf(float(terms.get("advance_share", S("advance_share"))), S("advance_min"), S("advance_max"))
	var advance := roundi(pay_total * advance_share)
	return {
		"pay_total": pay_total, "advance": advance, "completion": pay_total - advance, "advance_share": advance_share,
		"salvage_share": minf(S("salvage_base") + int(terms.get("salvage_points", 0)) * S("salvage_per_point"), S("salvage_max")),
		"support_budget": int(terms.get("support_points", 0)) * MissionRegistry.setting_i("support_per_point", 5000),
	}


## Extra completion pay for renegotiating an understated contract: a share of the base pay
## per rating step the briefing was short.
static func renegotiation_raise(contract: Dictionary) -> int:
	var steps := maxi(int(contract.get("true_rating", 1)) - int(contract.get("rated", 1)), 0)
	return roundi(int(contract.get("base_pay", 0)) * S("renegotiate_pay_per_step") * steps)
