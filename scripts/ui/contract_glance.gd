class_name ContractGlance
extends RefCounted
## A contract at a glance (claude/mission-ui; Captain, 2026-10-21: "the mission map, the mission
## ui, armory ui and loadout editor need a pass"): the facts a player weighs a job by, the same
## on the contract board, the briefing and the debrief, as a strip of small figures (UiKit.stat)
## with a tooltip each: pay and its split, risk, the enemy, intel quality, night and weather,
## the employer and the company's standing with it, time, the supports allowed and how many high
## command squads it takes. And the mission flow (board, prep, brief, deploy, track, debrief) as
## a row of steps, the current one lit.
##
## Generic on purpose: a contract kind of its own (cghath's operation contracts) shows its own
## figures by carrying "glance": [{"caption", "value", "tip", "tone"}] (added after these),
## without this file knowing it.

## The mission flow's steps, in order (flow()).
const STEPS: Array[String] = ["Board", "Prep", "Brief", "Deploy", "Track", "Debrief"]
## Intel accuracy words (Proposed): at or above each share.
const INTEL_GOOD := 0.8
const INTEL_FAIR := 0.6
## A rating at or above this reads as high risk (the warning colour).
const RISK_HIGH := 4


## The facts for contract `c` (a board offer, a held contract, or its public view):
## [{"key", "caption", "value", "tip", "tone" ("", "good", "warn")}].
static func facts(c: Dictionary) -> Array:
	var out: Array = []
	if c.is_empty():
		return out
	var offered := String(c.get("state", "offered")) == "offered"
	var deal: Dictionary = c.get("deal", {})
	# Pay and the split.
	if offered or deal.is_empty():
		var share := float(MissionRegistry.setting_f("advance_share", 0.3))
		out.append(_fact("pay", "Pay", "$" + DebriefCalc.money(c.get("base_pay", 0)),
			"Base pay before negotiation. Standard split: %d%% advance at signing, the rest on completion; %s." % [roundi(share * 100.0), ContractGen.clawback_text(c)]))
	else:
		out.append(_fact("pay", "Pay", "$" + DebriefCalc.money(deal.get("pay_total", 0)),
			"Agreed pay: $%s advance (paid at signing), $%s on completion%s; salvage share %d%%; %s." % [DebriefCalc.money(deal.get("advance", 0)),
				DebriefCalc.money(deal.get("completion", 0)), " +$%s renegotiated" % DebriefCalc.money(c.raise) if c.has("raise") else "",
				roundi(float(deal.get("salvage_share", 0)) * 100.0), ContractGen.clawback_text(c)]))
	# Risk: the briefed rating, and the truth once it's out.
	var rated := int(c.get("rated", c.get("difficulty", 1)))
	var hot := String(c.get("zone_kind", "")) == "hot"
	var risk := "%d/5%s" % [rated, " hot zone" if hot else ""]
	var risk_tip := "Difficulty as briefed (1 easy to 5 very hard)%s." % (". A hot zone: the enemy holds it and answers back" if hot else "")
	var tone := "warn" if rated >= RISK_HIGH or hot else ""
	if c.get("revealed", false) and c.has("true_rating"):
		risk = "%d/5 ACTUAL" % int(c.true_rating)
		risk_tip = "The briefing understated it: the real threat is %d/5 with %d fighters. A held contract can be renegotiated once." % [int(c.true_rating), int(c.get("enemy_count", 0))]
		tone = "warn"
	out.append(_fact("risk", "Risk", risk, risk_tip, tone))
	# The enemy, as intel puts it.
	if c.has("enemy_est"):
		var est := ContractGen.estimate_text(c)
		out.append(_fact("threat", "Enemy", est.get_slice(",", 0), "Briefing estimate: %s." % est))
	# Intel quality.
	if c.has("intel_accuracy"):
		var acc := float(c.intel_accuracy)
		out.append(_fact("intel", "Intel", "%s %d%%" % [intel_word(acc), roundi(acc * 100.0)],
			"How far the briefing can be trusted. Poor intel widens the estimate, and %d%% of briefings this poor understate the threat." % roundi(ContractGen.understate_chance(acc) * 100.0),
			"good" if acc >= INTEL_GOOD else ("warn" if acc < INTEL_FAIR else "")))
	# Night and weather.
	var cond := ContractGen.conditions_text(c)
	out.append(_fact("conditions", "Conditions", cond if cond != "" else "Day, clear",
		ContractGen.conditions_text(c, true) if cond != "" else "Daylight and clear weather: no conditions pay.", "warn" if cond != "" else ""))
	# The employer and the company's standing with it.
	var employer := String(c.get("employer", ""))
	if employer != "":
		var rep := Economy.reputation(employer)
		var tier := MissionRegistry.tier_of(rep)
		out.append(_fact("employer", "Employer", MissionRegistry.faction_name(employer),
			"Standing %+d (%s). Better standing gives more negotiation points and better pay; failing or aborting a job costs it." % [rep, String(tier.get("name", tier.get("id", "neutral")))],
			"warn" if rep < 0 else ""))
		out.append(_fact("standing", "Standing", "%+d %s" % [rep, String(tier.get("name", tier.get("id", "")))], "The company's reputation with %s." % MissionRegistry.faction_name(employer),
			"warn" if rep < 0 else ("good" if rep > 0 else "")))
	# Time: days out, any time limit, and the deadline or the offer's end.
	var limit := time_limit_min(c)
	var time := "%d day%s" % [int(c.get("days", 1)), "" if int(c.get("days", 1)) == 1 else "s"]
	if limit > 0:
		time += ", %d min limit" % limit
	var when := ("Offer open until day %d." % int(c.expires_day)) if offered and c.has("expires_day") \
		else ("Deploy by day %d." % int(c.deadline_day) if c.has("deadline_day") else "")
	out.append(_fact("time", "Time", time, "Days out in the field (plus travel)%s. %s" % [", and a %d-minute limit on the timed objectives" % limit if limit > 0 else "", when],
		"warn" if limit > 0 else ""))
	# Supports allowed, and the budget for them.
	var names := supports_allowed(c)
	var budget := int(c.get("support_left", deal.get("support_budget", 0)))
	out.append(_fact("supports", "Supports", "%d allowed%s" % [names.size(), ", $%s" % DebriefCalc.money(budget) if budget > 0 else ""],
		"Supports you can bring: %s.%s" % [", ".join(names) if not names.is_empty() else "none", " Support budget: $%s." % DebriefCalc.money(budget) if budget > 0 else " Negotiate support points for a budget."]))
	# High command squads.
	if c.has("squads_max"):
		var n := int(c.squads_max)
		out.append(_fact("squads", "HC squads", str(n) if n > 0 else "none", "High command squads this job allows besides yours (from its rating%s)." % (" and the hot zone" if hot else "")))
	for extra: Variant in c.get("glance", []):
		if extra is Dictionary:
			out.append(_fact(String(extra.get("key", extra.get("caption", ""))), String(extra.get("caption", "")), String(extra.get("value", "")),
				String(extra.get("tip", "")), String(extra.get("tone", ""))))
	return out


## The shortest time limit on `c`'s objectives, in minutes (0: none).
static func time_limit_min(c: Dictionary) -> int:
	var best := 0.0
	for o: Variant in c.get("objectives", []):
		if o is Dictionary and float(o.get("time_limit_s", 0.0)) > 0.0:
			var s := float(o.time_limit_s)
			best = s if best <= 0.0 else minf(best, s)
	return ceili(best / 60.0)


## The supports a contract may bring, by name (Briefing.SUPPORTS; hot-only ones in a hot zone).
static func supports_allowed(c: Dictionary) -> PackedStringArray:
	var hot := String(c.get("zone_kind", "")) == "hot"
	var out := PackedStringArray()
	for id: Variant in c.get("supports", Briefing.SUPPORTS.keys()):
		var s: Dictionary = Briefing.SUPPORTS.get(String(id), {})
		if not s.is_empty() and (hot or not bool(s.get("hot_only", false))):
			out.append(String(s.name))
	return out


## Intel accuracy (0-1) in a word.
static func intel_word(acc: float) -> String:
	if acc >= INTEL_GOOD:
		return "Good"
	if acc >= INTEL_FAIR:
		return "Fair"
	return "Poor"


## The facts as a wrapping strip of figures, each with its tooltip. `only`: the keys to show
## (all when empty), in facts() order.
static func strip(c: Dictionary, only: Array = []) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.name = "Glance"
	flow.add_theme_constant_override(&"h_separation", UiKit.SPACE_L)
	flow.add_theme_constant_override(&"v_separation", UiKit.SPACE_S)
	for f: Dictionary in facts(c):
		if not only.is_empty() and not String(f.key) in only:
			continue
		var stat := UiKit.stat(String(f.caption), String(f.value))
		stat.tooltip_text = String(f.tip)
		stat.mouse_filter = Control.MOUSE_FILTER_STOP
		var value := stat.get_child(1) as Label
		value.mouse_filter = Control.MOUSE_FILTER_PASS
		(stat.get_child(0) as Label).mouse_filter = Control.MOUSE_FILTER_PASS
		value.tooltip_text = stat.tooltip_text
		match String(f.tone):
			"warn":
				value.add_theme_color_override(&"font_color", UiKit.WARN)
			"good":
				value.add_theme_color_override(&"font_color", UiKit.GOOD)
		flow.add_child(stat)
	return flow


## The facts as plain lines ("Pay: $40,000"), for tests and tooltips.
static func text(c: Dictionary) -> String:
	return "\n".join(PackedStringArray(facts(c).map(func(f: Dictionary) -> String: return "%s: %s" % [f.caption, f.value])))


## The mission flow as a row of steps, `current` (one of STEPS) lit, the ones before it dimmed.
static func flow(current: String) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.name = "MissionFlow"
	row.add_theme_constant_override(&"h_separation", UiKit.SPACE_XS)
	var at := STEPS.find(current)
	for i in STEPS.size():
		if i > 0:
			row.add_child(UiKit.cell(">", &"HintLabel"))
		var step := UiKit.cell(STEPS[i], &"HintLabel")
		step.tooltip_text = STEP_TIPS.get(STEPS[i], "")
		step.mouse_filter = Control.MOUSE_FILTER_PASS
		if i == at:
			step.add_theme_color_override(&"font_color", UiKit.ACCENT_HOT)
			step.text = "[%s]" % STEPS[i]
		elif i < at:
			step.add_theme_color_override(&"font_color", UiKit.TEXT_OFF)
		row.add_child(step)
	return row


const STEP_TIPS := {
	"Board": "Pick and negotiate a contract (contract board).",
	"Prep": "Pick the squad and kit at the base (deployment prep).",
	"Brief": "Plan on the map: insertion, supports, the 3D look at the ground, then ready up.",
	"Deploy": "The insertion: the squad goes in.",
	"Track": "In the field: the objectives panel, top right (O list, N next).",
	"Debrief": "What it paid and cost, salvage, casualties and standing.",
}


static func _fact(key: String, caption: String, value: String, tip := "", tone := "") -> Dictionary:
	return {"key": key, "caption": caption, "value": value, "tip": tip, "tone": tone}
