class_name RebelSupport
extends RefCounted
## Rebel support (docs/rebel_support.md; Captain's calls 2026-10-19): how much the local people
## back the company, per region (coast, inland: a zone's "region"), 0-100. It starts at START and
## moves with what the company does there:
##   +HELPED            a civilian treated by one of ours (once each a day),
##   +PER_ENEMY_NEAR    each hostile killed within NEAR_VILLAGE_M of a village or town (at most
##                      NEAR_CAP a deployment): their oppressors gone,
##   +local tasks       (part 3), and supplies given at a village (part 3),
##   -PER_CASUALTY      a civilian casualty our side caused,
##   -heat / HEAT_PER_POINT each week, with the region's hottest faction's heat.
## Its tiers (TIERS) unlock the call-ins (CALLINS, part 2). Favours (paid by local tasks) and
## upgrades live here too (part 4). The campaign's "rebels" section, host authoritative (Campaign
## sends it to every peer). Proposed numbers.

const SECTION := &"rebels"
const REGIONS: Array[String] = ["coast", "inland"]
const START := 10.0
const TIERS: Array[int] = [20, 40, 60, 80]
## The call-ins and the support each needs (Captain: "as proposed").
const CALLINS := {"lookouts": 20, "diversion": 40, "fighters": 60, "vehicle_drop": 60, "mortar": 80}
const CALLIN_NAMES := {"lookouts": "Lookouts", "diversion": "Diversion", "fighters": "Rebel fighters", "vehicle_drop": "Vehicle drop", "mortar": "Mortar"}
const HELPED := 2.0
const PER_CASUALTY := 8.0
const PER_ENEMY_NEAR := 0.5
const NEAR_CAP := 6.0
const NEAR_VILLAGE_M := 250.0
const HEAT_PER_POINT := 20.0


static func _s() -> Dictionary:
	var s := Campaign.section(SECTION)
	if not s.has("support"):
		s["support"] = {}
	for r: String in REGIONS:
		if not (s.support as Dictionary).has(r):
			s.support[r] = START
	for k: String in ["favours", "near_gain", "helped_day"]:
		if not s.has(k):
			s[k] = 0
	if not s.has("helped"):
		s["helped"] = {}
	if not s.has("upgrades"):
		s["upgrades"] = {}
	return s


## Support in `region` (0-100); START for an unknown one.
static func support(region: String) -> float:
	return float((_s().support as Dictionary).get(region, START))


## The tier reached in `region`: 0 (below the first) to TIERS.size().
static func tier(region: String) -> int:
	var t := 0
	for need in TIERS:
		if support(region) >= need:
			t += 1
	return t


## The call-ins unlocked in `region`.
static func unlocked(region: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in CALLINS:
		if support(region) >= float(CALLINS[id]):
			out.append(id)
	return out


## Host: support in `region` moves by `delta` (clamped 0-100); crossing a tier says so.
static func change(region: String, delta: float, why := "") -> void:
	if region == "" or delta == 0.0:
		return
	var before := tier(region)
	var s := _s()
	s.support[region] = clampf(support(region) + delta, 0.0, 100.0)
	Campaign.mark_changed(SECTION)
	var after := tier(region)
	SessionLog.note("rebel support %s %+.1f (%s): %.1f" % [region, delta, why, support(region)])
	if after > before:
		var opened := unlocked(region).filter(func(id: String) -> bool: return float(CALLINS[id]) == float(TIERS[after - 1]))
		Contracts._notify_all("The locals of the %s back you more: %s." % [region, ", ".join(PackedStringArray(opened.map(func(id: String) -> String: return String(CALLIN_NAMES[id])))) + " now on call" if not opened.is_empty() else "support up"])
	elif after < before:
		Contracts._notify_all("The locals of the %s have turned cooler on the company." % region)


## The region zone `zone_id` is in ("" for none).
static func region_of(zone_id: String) -> String:
	if zone_id == RegionMap.BASE:
		return BaseZoneLevel.REGION
	return String(MissionRegistry.zone(zone_id).get("region", ""))


## The region of the level `from` is in ("" for none: the compound, a test level).
static func region_here(from: Node) -> String:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	var def: Variant = lvl.get(&"def") if lvl else null
	if def is Dictionary:
		var r := String((def as Dictionary).get("region", ""))
		if r == "" and (def as Dictionary).has("id"):
			r = region_of(String(def.id))
		return r
	return ""


# --- Hooks (host) ------------------------------------------------------------------------------

## People.civilian_casualty: the company hurt or killed one of theirs (never an ally's, a rebel's
## or an enemy's doing: Harm.by_company).
static func on_civilian_casualty(event: Dictionary) -> void:
	if not BaseHub.campaign_running:
		return
	if bool(event.get("shooter_company", event.get("shooter_player", false))):  # only ours (Harm.by_company)
		var lvl := BaseHub.level()
		change(region_here(lvl) if lvl else "", -PER_CASUALTY, "a civilian casualty")


## Soldier._log_care, a treatment done: one of ours treated `target`; a civilian counts once a day.
static func on_treated(by: Node, target: Node) -> void:
	if not BaseHub.campaign_running or not target is Soldier or not Person.is_civilian(target) or by == target:
		return
	var s := _s()
	if int(s.helped_day) != BaseHub.day():
		s.helped_day = BaseHub.day()
		s.helped = {}
	var uid := String(Person.state(target).get("uid", target.name))
	if (s.helped as Dictionary).has(uid):
		return
	s.helped[uid] = true
	change(region_here(target), HELPED, "a civilian treated")


## Soldier._server_become_body: a hostile down; near a village or town it counts for the locals.
static func on_enemy_down(body: Soldier) -> void:
	if not BaseHub.campaign_running or body == null or body.faction != &"hostile":
		return
	var by := Harm.last(body)
	if not by.is_empty() and not Harm.by_company(by):
		return  # someone else's kill (rebels, allies, a rival team): not the company's credit
	var lvl := CompoundLevel.current(body)
	if lvl == null or not lvl.has_method(&"modules"):
		return
	var near := false
	for m: Node in lvl.call(&"modules"):
		var t := ZoneModules.base(String(m.get(&"type")))
		if t in ["village", "town"] and (m as Node3D).global_position.distance_to(body.global_position) <= NEAR_VILLAGE_M:
			near = true
			break
	var s := _s()
	if near and float(s.near_gain) < NEAR_CAP:
		s.near_gain = float(s.near_gain) + PER_ENEMY_NEAR
		change(region_here(lvl), PER_ENEMY_NEAR, "a gunman near a village down")


## BaseHub, a deployment starting: the per-deployment cap on gains from fighting resets.
static func on_deployment_started() -> void:
	_s().near_gain = 0.0


## BaseHub.server_advance_days, each week: heat with the company costs support everywhere.
static func on_week() -> void:
	var hot := BaseZoneLevel.hottest()
	if float(hot[1]) < HEAT_PER_POINT:
		return
	for r: String in REGIONS:
		change(r, -float(hot[1]) / HEAT_PER_POINT, "heat with %s" % String(hot[0]))


## For the ops desk's Locals page (every peer): [{"region", "support", "tier", "next", "unlocked"}].
static func view() -> Array:
	var out: Array = []
	for r: String in REGIONS:
		var t := tier(r)
		out.append({"region": r, "support": snappedf(support(r), 0.1), "tier": t, "next": TIERS[t] if t < TIERS.size() else -1,
			"unlocked": unlocked(r)})
	return out
