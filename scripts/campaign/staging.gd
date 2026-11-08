class_name Staging
extends RefCounted
## Staging from a friendly FOB and what insertion flights cost (combined arms D8, docs/
## combined_arms.md 8): instead of flying every job from home, the company rents a corner of a
## friendly base (FOB Halberd, a US outpost in a US-held zone with an HQ site) and works the
## contracts within reach of it.
##
## Campaign section "staging" ({} while the company isn't staged): {"host" (the faction), "zone",
## "since_day", "vehicles" (the motor-pool ids that came along), "squad" (the member ids that
## came along), "employer" (of the deployment running from it: the host's own job is cheaper),
## "deployments" (run from it this stay), "evict" (why it must go, "" if it may stay),
## "defend_cid" (an assault's defend job on the board), "rent_paid"}.
##
## Everything here that reads is safe on any peer (a client reads the host's copy of the section
## through BaseHub.view "staging", and who holds what through Economy.war_view); server_* are
## the host's. The numbers are in data/prices.json "staging" and "flights", all Proposed.
##
## What the rest of the game asks of it:
## - flight prices: call_price() (HeliSupports' calls, its insertion through Economy);
## - where home is: BaseHub.base_info() goes to the staging zone (StagingLevel) while active();
## - what is on offer there: sells()/item_price() (the terminal), board_problem() (the board),
##   refuses() (no armory, stash, hiring, workshop), MotorPool's parking and repair bill;
## - the daily rent, the war and eviction: server_advance_days() (Economy.advance_days) and
##   server_check_standing() (Economy.change_reputation).

const SECTION := &"staging"
const HOST_DEFEND := "defend_hold"
## Helicopter supports that may refuel at the FOB (heli_mult). The insertion and extraction
## flights are priced from the FOB instead (call_price).
const REFUEL_KINDS: Array[String] = ["resupply", "transport", "medevac", "cargo"]
const FLIGHT_KINDS: Array[String] = ["insertion", "extraction"]
## BaseHub requests refused at the staging FOB (8.2: no armory, no stash, no hiring, no workshop;
## its base defences are at home).
const REFUSED: Array[String] = ["hire", "release", "medbay", "restock", "restock_squad", "loadout", "defence", "place_defence", "fob_tier",
	"guards", "squads", "buy_vehicle", "rebel_upgrade", "certify_hx1"]
const NO_SERVICE := "Not at the staging FOB: only what the squad brought"
## A deployment's zone def, while staged: where a bought respawn comes in, the crossing from the FOB.
const RESPAWN_KEY := "staging_crossing"
const CROSSING_POINT := "staging_crossing"


static func cfg() -> Dictionary:
	return Prices.data().get("staging", {})


static func c_i(key: String, default := 0) -> int:
	return int(cfg().get(key, default))


static func c_f(key: String, default := 0.0) -> float:
	return float(cfg().get(key, default))


static func _is_host() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return true
	var mp := tree.root.multiplayer
	return mp == null or not mp.has_multiplayer_peer() or mp.is_server()


static func _s() -> Dictionary:
	if _is_host():
		return Campaign.section(SECTION)
	return (BaseHub.view.get("staging", {}) as Dictionary).get("state", {}) as Dictionary


# --- State --------------------------------------------------------------------------------------

static func active() -> bool:
	return String(_s().get("zone", "")) != ""


## The zone the company is staged in ("" when it isn't).
static func zone() -> String:
	return String(_s().get("zone", ""))


## The faction it rents from ("" when it isn't staged).
static func host() -> String:
	return String(_s().get("host", ""))


static func evicting() -> bool:
	return String(_s().get("evict", "")) != ""


## The motor-pool vehicles parked with it that are still the company's.
static func vehicles() -> Array:
	var out: Array = []
	for id: Variant in _s().get("vehicles", []):
		if not MotorPool.entry(String(id)).is_empty():
			out.append(String(id))
	return out


## Whether member `mid` came along (a member who didn't is at the company's FOB).
static func has_member(mid: String) -> bool:
	return not active() or mid in (_s().get("squad", []) as Array)


## Whether BaseHub request `action` is refused at the staging FOB.
static func refuses(action: String) -> bool:
	return active() and action in REFUSED


static func zone_name(zone_id: String) -> String:
	return RegionMap.zone_name(zone_id)


## The zone a level plays (its "def" id), "" for a level with none (the test compound).
static func zone_of(level: Node) -> String:
	var def: Variant = level.get(&"def") if level else null
	return String((def as Dictionary).get("id", "")) if def is Dictionary else ""


# --- Hosts and access ---------------------------------------------------------------------------

## Who holds `zone_id` as this peer knows it.
static func _holder(zone_id: String) -> String:
	if _is_host():
		return UsField.holder_of(zone_id)
	var row: Dictionary = (Economy.war_view().get("zones", {}) as Dictionary).get(zone_id, {})
	return String(row.get("holder", ZoneControl.zone_def_raw(zone_id).get("controller", "")))


## The faction that would host the company in `zone_id` ("" for none): the base of a belligerent
## employer ("cant_fall"), or a zone it holds with an HQ site (8.1).
static func host_of(zone_id: String) -> String:
	if zone_id == "" or zone_id == RegionMap.BASE:
		return ""
	var raw := ZoneControl.zone_def_raw(zone_id)
	var h := _holder(zone_id)
	if h == "" or not WorldSites.is_belligerent(h):
		return ""
	return h if bool(raw.get("cant_fall", false)) or "hq" in (raw.get("assets", []) as Array) else ""


## Every zone that could host the company now, in the map's order.
static func hosts() -> Array[String]:
	var out: Array[String] = []
	for z: Dictionary in MissionRegistry.data().get("zones", []):
		if host_of(String(z.zone_id)) != "":
			out.append(String(z.zone_id))
	return out


## Why the company may not rent at `zone_id` ("" if it may).
static func access_problem(zone_id: String) -> String:
	var h := host_of(zone_id)
	if h == "":
		return "No friendly force hosts the company there"
	var rep := Economy.reputation(h)
	if rep < c_i("min_rep", 30):
		return "Needs trusted with %s (standing %+d, needs %+d)" % [MissionRegistry.faction_name(h), rep, c_i("min_rep", 30)]
	return ""


## The rent's multiplier for `employer`'s job at `h`'s base.
static func rent_mult(h: String, employer := "") -> float:
	var m := c_f("mult_allied", 0.7) if MissionRegistry.tier_id(Economy.reputation(h)) == "allied" else c_f("mult_trusted", 1.0)
	return m * c_f("mult_host_contract", 0.5) if employer != "" and employer == h else m


static func rent_deployment(h: String, employer := "") -> int:
	return roundi(c_i("rent_deployment", 6000) * rent_mult(h, employer))


static func rent_day(h: String, employer := "") -> int:
	return roundi(c_i("rent_day", 1500) * rent_mult(h, employer))


# --- Flights ------------------------------------------------------------------------------------

## Region links from the home base to `zone_id`, -1 off the map. The LHD lies off the coast: every
## coast zone is one link from it.
static func home_links(zone_id: String) -> int:
	if not ZoneControl.home_is_lhd():
		return RegionMap.distance(RegionMap.BASE, zone_id)
	var best := -1
	for z: Dictionary in MissionRegistry.data().get("zones", []):
		if String(z.get("region", "")) != "coast" or not RegionMap.layout().has(String(z.zone_id)):
			continue
		var d := RegionMap.distance(String(z.zone_id), zone_id)
		if d >= 0 and (best < 0 or d < best):
			best = d
	return best + 1 if best >= 0 else -1


## One way over `links` region links.
static func flight_cost(links: int) -> int:
	var f: Dictionary = Prices.data().get("flights", {})
	return int(f.get("base", 3000)) + int(f.get("per_link", 1200)) * maxi(links, 0)


## An insertion or extraction flight to `zone_id` from where the company is now (the staging FOB
## while staged, else home): -1 for a zone off the region map.
static func flight_price(zone_id: String) -> int:
	if zone_id == "" or not RegionMap.layout().has(zone_id):
		return -1
	var links := RegionMap.distance(zone(), zone_id) if active() else home_links(zone_id)
	return flight_cost(links) if links >= 0 else -1


## What support `kind` costs in `zone_id` ("" or off the map: the flat price).
static func call_price(kind: String, zone_id: String) -> int:
	var flat := Prices.support_price(kind)
	if kind in FLIGHT_KINDS:
		var flight := flight_price(zone_id)
		return flight if flight >= 0 else flat
	if active() and kind in REFUEL_KINDS and String(ZoneControl.zone_def_raw(zone_id).get("region", "")) == "inland":
		return roundi(flat * c_f("heli_mult", 0.6))
	return flat


# --- Quotes -------------------------------------------------------------------------------------

## The days a contract takes on top of its own: its region's travel, or a short hop from the FOB.
static func travel_days(c: Dictionary) -> int:
	var usual := int(MissionRegistry.region(String(c.get("region", ""))).get("travel_days", 0))
	return mini(usual, c_i("travel_days", 1)) if active() and reach_problem(zone(), c) == "" else usual


## Why the FOB at `at` can't reach contract `c` ("" if it can).
static func reach_problem(at: String, c: Dictionary) -> String:
	var links := RegionMap.distance(at, String(c.get("zone_id", "")))
	if links < 0 or links > c_i("reach_links", 2):
		return "More than %d region links from %s" % [c_i("reach_links", 2), zone_name(at)]
	return ""


## Why this contract isn't on the staging FOB's board ("" when it is, or the company isn't staged).
static func board_problem(c: Dictionary) -> String:
	return reach_problem(zone(), c) if active() else ""


## What renting at `at` for contract `c` would come to: {"key", "name", "zone", "host", "ok", "why",
## "rent", "flights", "cost", "days", "links", "ground"}.
static func quote(at: String, c: Dictionary) -> Dictionary:
	var h := host_of(at)
	var employer := String(c.get("employer", ""))
	var days := int(c.get("days", 1)) + c_i("travel_days", 1)
	var rent := rent_deployment(h, employer) + rent_day(h, employer) * days
	var links := RegionMap.distance(at, String(c.get("zone_id", "")))
	var ground := links >= 0 and links <= 1
	var flights := 0 if ground else 2 * flight_cost(links)  # a helicopter hop: the job is further than one crossing
	var why := access_problem(at)
	if why == "":
		why = reach_problem(at, c)
	return {"key": "stage:" + at, "name": "Stage from %s" % zone_name(at), "zone": at, "host": h, "ok": why == "", "why": why,
		"rent": rent, "flights": flights, "cost": rent + flights, "days": days, "links": links, "ground": ground}


## The ways of reaching contract `c`: flying from home first, then each base within reach,
## cheapest first (each as quote(); the flight's "key" is "home"). None while already staged.
static func options(c: Dictionary) -> Array:
	var out: Array = []
	var zone_id := String(c.get("zone_id", ""))
	if zone_id == "" or active():
		return out
	var fly := flight_price(zone_id)
	var one_way := fly if fly >= 0 else Prices.support_price("insertion")
	var by_air := "Fly from the LHD" if ZoneControl.home_is_lhd() else "Fly from the company's FOB"
	out.append({"key": "home", "name": by_air, "zone": "", "host": "", "ok": true, "why": "", "rent": 0, "flights": 2 * one_way, "cost": 2 * one_way,
		"days": int(c.get("days", 1)) + int(MissionRegistry.region(String(c.get("region", ""))).get("travel_days", 0)), "links": home_links(zone_id), "ground": false})
	var rented: Array = []
	for at: String in hosts():
		if reach_problem(at, c) == "":
			rented.append(quote(at, c))
	rented.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.cost) < int(b.cost))
	out.append_array(rented)
	return out


## One option as the board and the ops desk say it.
static func option_text(o: Dictionary) -> String:
	var parts := PackedStringArray()
	if int(o.get("rent", 0)) > 0:
		parts.append("rent $%s" % DebriefCalc.money(int(o.rent)))
	if int(o.get("flights", 0)) > 0:
		parts.append("flights in and out $%s" % DebriefCalc.money(int(o.flights)))
	elif bool(o.get("ground", false)):
		parts.append("over the crossing: fuel only")
	var text := "%s: $%s (%s), %d day%s" % [String(o.name), DebriefCalc.money(int(o.cost)), ", ".join(parts), int(o.days), "" if int(o.days) == 1 else "s"]
	return text if bool(o.get("ok", true)) else "%s. %s" % [text, String(o.why)]


## What every peer's base screen shows: the section and the options for the contract in prep.
static func view(prep_contract: Dictionary) -> Dictionary:
	var out := {"state": Roster.json_safe(_s().duplicate(true)), "options": options(prep_contract), "models": []}
	if active():
		out["name"] = zone_name(zone())
		out["host_name"] = MissionRegistry.faction_name(host())
		out["rent_day"] = rent_day(host(), String(_s().get("employer", "")))
		out["home_days"] = home_days()
		for id: String in vehicles():
			(out.models as Array).append(String(MotorPool.entry(id).get("model", "")))
	return out


# --- Services -----------------------------------------------------------------------------------

## Whether the staging FOB's terminal sells `id` (8.2: ammo, medical, batteries, fuel, repair kits,
## track links, ERA tiles).
static func sells(id: StringName) -> bool:
	if not Prices.for_sale(id):
		return false
	return String(ItemDB.get_item(id).type) in (cfg().get("resupply_types", []) as Array) or String(id) in (cfg().get("resupply_ids", []) as Array)


static func item_price(id: StringName) -> int:
	return roundi(Prices.price_of(id) * c_f("resupply_mult", 1.25))


## The staged bill for a vehicle's service: `work` (the workshop's cost before fuel) x repair_mult,
## `litres` to fill at the FOB's price.
static func repair_bill(work: int, litres: float) -> int:
	return roundi(work * c_f("repair_mult", 1.5) + litres * c_f("fuel_price", 3.0))


# --- The deployment from the FOB ----------------------------------------------------------------

## The crossing of the zone `def` describes that leads to the staging FOB ({} if none does).
static func crossing_home(def: Dictionary) -> Dictionary:
	for c: Dictionary in def.get("crossings", []):
		if active() and String(c.get("to", "")) == zone():
			return c
	return {}


## Host: `info`, the level a deployment from the FOB goes to, with its supports coming in from the
## FOB's side and its bought respawns over the crossing from it (8.2).
static func stamp_level(info: Dictionary) -> Dictionary:
	var def: Variant = info.get("def")
	if not active() or not def is Dictionary:
		return info
	var c := crossing_home(def)
	if c.is_empty():
		return info
	var out := info.duplicate(true)
	out.def[RESPAWN_KEY] = (c.pos as Array).duplicate()
	out.def["fob_side"] = String(RegionMap.SIDE_NAMES[int(c.side)])
	return out


## The briefing's way in from the FOB, over the crossing ({} if the zone has no crossing to it).
static func insertion_point(def: Dictionary) -> Dictionary:
	var c := crossing_home(def)
	if c.is_empty():
		return {}
	return {"id": CROSSING_POINT, "name": "From %s, over the crossing" % zone_name(zone()), "pos": (c.pos as Array).duplicate(), "method": "foot", "edge": true, "staging": true}


# --- Host: renting ------------------------------------------------------------------------------

## Why the company can't stage at `at` for `contract` now ("" if it can).
static func begin_problem(at: String, contract: Dictionary) -> String:
	if active():
		return "Already staged at %s: go home first" % zone_name(zone())
	var why := access_problem(at)
	if why != "":
		return why
	if not contract.is_empty():
		why = reach_problem(at, contract)
		if why != "":
			return why
	var rent := rent_deployment(host_of(at), String(contract.get("employer", "")))
	return "" if Economy.cash() >= rent else "Can't afford the rent ($%s)" % DebriefCalc.money(rent)


## Host: rents the corner at `at`: the deployment's rent paid now, the squad and up to "parking"
## ready vehicles go along (8.1, steps 1 and 2). Returns "" or why not.
static func server_begin(at: String, contract: Dictionary, squad: Array) -> String:
	var why := begin_problem(at, contract)
	if why != "":
		return why
	var h := host_of(at)
	var employer := String(contract.get("employer", ""))
	var rent := rent_deployment(h, employer)
	if not Economy.spend(rent, "Staging rent: %s" % zone_name(at)):
		return "Can't afford the rent ($%s)" % DebriefCalc.money(rent)
	var parked: Array = []
	for v: Dictionary in MotorPool.list():
		if parked.size() < c_i("parking", 2) and MotorPool.problem(String(v.id)) == "":
			parked.append(String(v.id))
	var s := Campaign.section(SECTION)
	s.merge({"host": h, "zone": at, "since_day": Economy.day(), "vehicles": parked, "squad": squad.duplicate(), "employer": employer,
		"deployments": 0, "evict": "", "defend_cid": "", "rent_paid": rent}, true)
	Campaign.mark_changed(SECTION)
	SessionLog.note("staging: at %s from %s, $%d rent, %d squadmates, %d vehicles" % [at, h, rent, squad.size(), parked.size()])
	Contracts._notify_all("The company moves to %s: a corner inside the wire, rented from %s" % [zone_name(at), MissionRegistry.faction_name(h)])
	return ""


## Host (BaseHub.server_deploy): a deployment leaves the staging FOB. The first (the one that moved
## the company here) is paid already; each further one pays the deployment's rent, into debt if
## it must (the squad is already going). Later days are at this contract's rate.
static func server_on_deploy(contract: Dictionary) -> void:
	if not active():
		return
	var s := Campaign.section(SECTION)
	var employer := String(contract.get("employer", ""))
	if int(s.get("deployments", 0)) >= 1:
		var rent := rent_deployment(host(), employer)
		Economy.charge_run(rent, "Staging rent: %s" % zone_name(zone()))
		s["rent_paid"] = int(s.get("rent_paid", 0)) + rent
	s["deployments"] = int(s.get("deployments", 0)) + 1
	s["employer"] = employer
	Campaign.mark_changed(SECTION)


## Host (Economy.advance_days, after the war's day): the zone lost takes the corner with it; else
## the days' rent, an eviction for a standing that has slipped, and an assault on the base.
static func server_advance_days(days: int) -> void:
	if not active() or days <= 0:
		return
	var s := Campaign.section(SECTION)
	if host_of(zone()) != host():
		server_lost()
		return
	var amount := rent_day(host(), String(s.get("employer", ""))) * days
	if amount > 0:
		Economy.add_cash(-amount, "Staging rent: %s, %d day%s" % [zone_name(zone()), days, "" if days == 1 else "s"])
		Economy.note_run_expense(amount, "Staging rent: %s" % zone_name(zone()))
		s["rent_paid"] = int(s.get("rent_paid", 0)) + amount
	server_check_standing()
	if active():
		_offer_defence()
	Campaign.mark_changed(SECTION)


## Host (Economy.change_reputation, the day's decay): below trusted the company has to go.
static func server_check_standing() -> void:
	if active() and not evicting() and Economy.reputation(host()) < c_i("min_rep", 30):
		server_evict("standing with %s fell below trusted" % MissionRegistry.faction_name(host()))


## Host: the company has to go, at the end of the current deployment, or now with none running.
static func server_evict(why: String) -> void:
	if not active() or evicting():
		return
	Campaign.section(SECTION)["evict"] = why
	Campaign.mark_changed(SECTION)
	Contracts._notify_all("%s orders the company off %s: %s" % [MissionRegistry.faction_name(host()), zone_name(zone()), why])
	SessionLog.note("staging: evicted from %s: %s" % [zone(), why])
	if not RosterDeployment.is_running(BaseHub.roster()):
		server_after_deployment()


## Host (BaseHub.server_end_deployment; at once with none running): an eviction takes effect, with
## the bill for moving what's parked there home; else the deployment's employer lapses.
static func server_after_deployment() -> void:
	if not active():
		return
	var s := Campaign.section(SECTION)
	s["employer"] = ""
	if not evicting():
		Campaign.mark_changed(SECTION)
		return
	var bill := c_i("evict_vehicles_home", 5000) if not vehicles().is_empty() else 0
	if bill > 0:
		Economy.add_cash(-bill, "Evicted: vehicles moved home from %s" % zone_name(zone()))
		Economy.note_run_expense(bill, "Evicted: vehicles moved home")
	_clear()
	_go_home_if_there()


## Host: the zone flipped: the corner is gone, and whatever is parked there unless it's out with
## the squad (8.4).
static func server_lost() -> void:
	if not active():
		return
	var lost := PackedStringArray()
	for id: String in vehicles():
		if String(MotorPool.entry(id).get("out", "")) == "":
			lost.append(String(MotorPool.entry(id).get("name", id)))
			MotorPool.remove(id)
	Contracts._notify_all("%s has fallen: the company's corner there is gone%s" % [zone_name(zone()), " and with it: " + ", ".join(lost) if not lost.is_empty() else ""])
	SessionLog.note("staging: %s lost to the war, %d vehicles with it" % [zone(), lost.size()])
	_clear()
	_go_home_if_there()


## Host: leaves for home (8.1, step 5). The days the usual trip takes are the caller's to pass, and
## no rent runs on them. Returns them; -1 when not staged.
static func server_leave() -> int:
	if not active():
		return -1
	var days := home_days()
	Contracts._notify_all("The company leaves %s for home" % zone_name(zone()))
	_clear()
	return days


## The usual trip home from the staging FOB.
static func home_days() -> int:
	return int(MissionRegistry.region(String(ZoneControl.zone_def_raw(zone()).get("region", ""))).get("travel_days", 0))


static func _clear() -> void:
	Campaign.section(SECTION).clear()
	Campaign.mark_changed(SECTION)


## With the squad standing at the corner, it has to leave now (BaseHub's own level switch does the
## rest when a deployment ends).
static func _go_home_if_there() -> void:
	if BaseHub.level() is StagingLevel and not RosterDeployment.is_running(BaseHub.roster()):
		BaseHub.call_deferred(&"server_return_to_base")


# --- Host: the host's base under attack, misconduct -----------------------------------------------

## A faction attacking the base the company is staged at: a defend job for it on the board (8.4).
static func _offer_defence() -> void:
	var s := Campaign.section(SECTION)
	var at := zone()
	var by := String(WorldSites.front_read(at).get("by", ""))
	if by == "" or not WorldSites.cant_fall(at) or String(s.get("defend_cid", "")) != "" \
			or MissionRegistry.faction(by).get("role", "") != "hostile":
		return
	var r := RandomNumberGenerator.new()
	r.seed = hash([Contracts.campaign_seed(), Economy.day(), "staging_defence", at])
	var offer := ContractGen.generate(r, {"day": Economy.day(), "source": "board", "zone_id": at, "type": HOST_DEFEND, "target": by, "employer": host()})
	if offer.is_empty():
		return
	offer["staging_defend"] = true
	offer["title"] = "Hold %s" % zone_name(at)
	offer["brief"] = "%s are coming at %s while the company is inside the wire. Help hold it. %s" % [MissionRegistry.faction_name(by), zone_name(at), String(offer.get("brief", ""))]
	s["defend_cid"] = Contracts.server_add_offer(offer)


## Host (Contracts.contract_closed): an assault on the host's base held.
static func on_contract_closed(c: Dictionary, outcome: String) -> void:
	if not bool(c.get("staging_defend", false)) or not active():
		return
	var s := Campaign.section(SECTION)
	if String(s.get("defend_cid", "")) == String(c.get("cid", "")):
		s["defend_cid"] = ""
	if outcome == "completed":
		Economy.change_reputation(String(c.get("employer", host())), c_i("rep_defend", 3), "held %s" % zone_name(zone()))
	Campaign.mark_changed(SECTION)


## Whether `node` (a Soldier or a Vehicle) is the host's.
static func _is_hosts(node: Node) -> bool:
	return active() and node != null and (String(node.get_meta(&"faction_id", "")) == host() or String(node.get_meta(&"host_side", "")) == host())


## Host (Harm's record of a hit): the company's fire hit one of the host's men: the standing pays,
## once a man, and if he dies of it the company is out. Every Harm.note_hit comes before the hit
## lands, so a man already dead here is a corpse being shot: nothing (someone else killed him).
static func server_note_harm(victim: Node, info: Dictionary) -> void:
	var s := victim as Soldier
	if s == null or s.vitals.is_dead() or not _is_hosts(s) or not Harm.by_company(info):
		return
	if not s.has_meta(&"staging_hit"):
		s.set_meta(&"staging_hit", true)
		Economy.change_reputation(host(), c_i("rep_friendly_fire", -10), "friendly fire on the host's troops")
		s.vitals.died.connect(_host_man_died.bind(s), CONNECT_ONE_SHOT)


static func _host_man_died(s: Soldier) -> void:
	if is_instance_valid(s) and Harm.by_company(Harm.last(s)):
		server_evict("one of its men was killed by the company's fire")


## Host (Soldier._server_loot_open): one of the company searches `target`, the host's dead or
## vehicle (once each).
static func server_note_loot(target: Node) -> void:
	if not _is_hosts(target) or target.has_meta(&"staging_looted"):
		return
	target.set_meta(&"staging_looted", true)
	Economy.change_reputation(host(), c_i("rep_looting", -15), "looting the host's dead or vehicles")
