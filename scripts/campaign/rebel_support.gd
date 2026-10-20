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


## Contracts.contract_closed: one of the locals' own jobs done ("locals": {"support", "favours"},
## contracts.json) raises their support in its region and pays its favours.
static func on_contract_closed(contract: Dictionary, outcome: String) -> void:
	var def := MissionRegistry.type_def(String(contract.get("type", "")))
	if not def.has("locals") or outcome != "completed" or not BaseHub.campaign_running:
		return
	var pay: Dictionary = def.locals
	add_favours(int(pay.get("favours", 0)))
	change(region_of(String(contract.get("zone_id", ""))), float(pay.get("support", 0)), "their job done: %s" % String(contract.get("title", "")))


## Host: favours the locals owe the company (paid by their jobs, spent on upgrades: part 4).
static func add_favours(n: int) -> void:
	if n == 0:
		return
	var s := _s()
	s.favours = maxi(int(s.favours) + n, 0)
	Campaign.mark_changed(SECTION)


static func favours() -> int:
	return int(_s().favours)


## Host (a villager asked, Soldier._server_ask_locals): one of the locals' jobs in this zone goes
## on the board, once a zone a day. Returns what the player hears. Outside a campaign only the
## tutorial's villager answers (TutorialGuide).
static func server_ask(by: Soldier, villager: Soldier) -> String:
	if not BaseHub.campaign_running:
		var tutorial := TutorialGuide.of(villager)
		return tutorial.server_locals_asked(by, villager) if tutorial else "Not now"
	var lvl := CompoundLevel.current(villager)
	var def: Variant = lvl.get(&"def") if lvl else null
	var zone_id := String((def as Dictionary).get("id", "")) if def is Dictionary else ""
	if zone_id == "" or zone_id == RegionMap.BASE:
		return "\"We're fine here, thank you\""
	var s := _s()
	var key := "%s:%d" % [zone_id, BaseHub.day()]
	if not s.has("asked"):
		s["asked"] = {}
	if (s.asked as Dictionary).has(key):
		return "\"We told your people already: it's on your board\""
	s.asked[key] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([key, villager.name])
	var job := ContractGen.generate(rng, {"day": BaseHub.day(), "source": "locals", "zone_id": zone_id})
	Contracts._add_offer(job)
	Contracts._commit()
	Campaign.mark_changed(SECTION)
	return "\"%s\" (on the contract board)" % String(job.get("brief", job.get("title", "")))


## How much support the locals' gratitude for supplies can bring a region a day, and a favour
## for every SUPPLIES_PER_FAVOUR given. Proposed.
const SUPPLIES_DAY_CAP := 4.0
const SUPPLIES_PER_FAVOUR := 3


## Host (Soldier._server_give_locals): `by` gave villager `villager` one medical item `id`.
## Returns what the player hears (outside a campaign, the tutorial's: TutorialGuide).
static func server_given(by: Soldier, villager: Soldier, id: StringName) -> String:
	if not BaseHub.campaign_running:
		var tutorial := TutorialGuide.of(villager)
		return tutorial.server_locals_given(by, villager, id) if tutorial else "They thank you"
	var region := region_here(villager)
	var s := _s()
	if int(s.get("given_day", -1)) != BaseHub.day():
		s["given_day"] = BaseHub.day()
		s["given"] = {}
	var today := float((s.given as Dictionary).get(region, 0.0))
	s["given_count"] = int(s.get("given_count", 0)) + 1
	if int(s.given_count) % SUPPLIES_PER_FAVOUR == 0:
		add_favours(1)
	if today >= SUPPLIES_DAY_CAP:
		Campaign.mark_changed(SECTION)
		return "They thank you for the %s" % ItemDB.get_item(id).name
	s.given[region] = today + 1.0
	change(region, 1.0, "supplies given")
	return "They thank you for the %s: the %s's locals remember it" % [ItemDB.get_item(id).name, region]


## Upgrades (part 4; Captain: paid with "both and materials"): each call-in has two levels, each
## level costing favours, cash and materials (salvage from the stash) together. What a level does
## is RebelCalls' (UPGRADE_TEXT says it). Proposed costs.
const UPGRADE_COSTS: Array[Dictionary] = [
	{"favours": 3, "cash": 5000, "materials": 2},
	{"favours": 6, "cash": 12000, "materials": 4},
]
const MAX_LEVEL := 2
const UPGRADE_TEXT := {
	"lookouts": ["they watch further out", "further still, and report more often"],
	"diversion": ["they keep it up longer", "longer still"],
	"fighters": ["two more fighters come", "two more again"],
	"vehicle_drop": ["a vehicle sooner again", "two vehicles at a time"],
	"mortar": ["two more rounds", "two more again, and they fall tighter"],
}


static func level(id: String) -> int:
	return int((_s().upgrades as Dictionary).get(id, 0))


## The salvage in the stash (the materials upgrades take): item ids of type "salvage" -> count.
static func materials_in_stash() -> Dictionary:
	var out := {}
	for id: String in BaseArmory.counts(BaseHub.stash()):
		var item := ItemDB.get_item(StringName(id)) if ItemDB.has_item(StringName(id)) else null
		if item and item.type == "salvage":
			out[id] = int(BaseArmory.counts(BaseHub.stash())[id])
	return out


## Host (the ops desk): call-in `id` goes up a level. Returns "" or why not.
static func server_upgrade(id: String) -> String:
	if not CALLINS.has(id):
		return "No such call-in"
	var lv := level(id)
	if lv >= MAX_LEVEL:
		return "%s is as good as it gets" % String(CALLIN_NAMES[id])
	var cost: Dictionary = UPGRADE_COSTS[lv]
	if favours() < int(cost.favours):
		return "The locals owe you %d favour%s; this takes %d" % [favours(), "" if favours() == 1 else "s", int(cost.favours)]
	var mats := materials_in_stash()
	var have := 0
	for k: String in mats:
		have += int(mats[k])
	if have < int(cost.materials):
		return "It takes %d salvage (scrap, parts, electronics) from the stash; there's %d" % [int(cost.materials), have]
	if not BaseEconomy.try_spend(int(cost.cash), "Rebel %s upgrade" % String(CALLIN_NAMES[id]).to_lower()):
		return "Can't afford it ($%d)" % int(cost.cash)
	var left := int(cost.materials)
	for k: String in mats:
		if left <= 0:
			break
		left -= BaseHub.server_take_from_stash(StringName(k), mini(left, int(mats[k])))
	add_favours(-int(cost.favours))
	_s().upgrades[id] = lv + 1
	Campaign.mark_changed(SECTION)
	SessionLog.note("rebel upgrade: %s to level %d" % [id, lv + 1])
	return ""


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


## For the ops desk (every peer): each call-in's level, [{"id", "level"}].
static func upgrades_view() -> Array:
	return CALLINS.keys().map(func(id: String) -> Dictionary: return {"id": id, "level": level(id)})
