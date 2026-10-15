extends Node
## Contracts, deployments and the debrief (wave 4, W10), the autoload `Contracts`. The host
## owns them in the campaign save's "contracts" section; every peer and late joiner gets a
## public copy (the truth about a contract's threat stays on the host until it's revealed).
##
## The loop, as other parts call it:
## 1. The board (board()) refills every day from the campaign seed: regular offers, a cheap
##    low-risk one (the safety floor), fixers' special jobs once the company's reputation with
##    their faction is high enough, and leads opened by intel. Offers expire after a few days.
## 2. accept(cid, terms) negotiates (ContractGen: pay, salvage share, support budget and the
##    advance, traded MW5-style against negotiation points) and pays the advance, which is kept
##    whatever happens. Several contracts can be held at once; one not deployed by its
##    deadline lapses and costs reputation.
## 3. server_start_deployment(cids, zone_id) starts a deployment: one contract in a contract
##    zone, every held contract for the zone in a hot zone. The objectives (Objectives, a child
##    node) go live for the HUD and the map. enemy_force(cid) tells the world what to spawn.
## 4. In the zone: server_civilian_casualty (fines; the 8th voids the deployment's contracts),
##    server_hvt_delivered, server_cache_destroyed, server_items_banked (loot sent out
##    mid-zone), server_reveal_threat (the briefing understated it: renegotiate or abort).
## 5. server_end_deployment(report) at extraction: the debrief (DebriefCalc) pays out,
##    applies reputation, banks what was carried out, moves the clock on and shows the debrief
##    screen on every peer. Salvage picks and intel (turn in for leads, or sell) are made on it;
##    finish_debrief() banks the picks and closes it.
##
## Debug path on its own: Contracts.open_board() (the main menu's "Contract board" button)
## runs the board, negotiation, shop, days and a stand-in deployment and debrief offline. In
## a session, End (DEBUG_BOARD_KEY) opens the board on any peer until the base hub places it;
## its host-only controls stand in for deploying and extracting until wave 4B joins it up.

signal changed
## A message for the local player.
signal notice(text: String)
signal deployment_started(deployment: Dictionary)
## Every peer: a new debrief to show.
signal debrief_ready(debrief: Dictionary)
signal debrief_closed
signal contract_voided(cid: String)
## Host: an offer was accepted (the base starts its prep: BaseHub).
signal contract_accepted(cid: String)
## Host: a contract left the board or the held list for good, with its outcome (a held
## contract's: completed, failed, voided, lapsed, aborted; an offer that ran out: EXPIRED).
## BaseHub settles a recovery contract's squadmate on it.
signal contract_closed(contract: Dictionary, outcome: String)
## Host: a contract's objectives went live in the zone (the deployment started, or a radio
## contract came in): PeopleLayer puts what they need there (the HVT, the hostage, intel).
signal contract_live(cid: String, objectives: Array)

const SECTION := &"contracts"
const HISTORY_KEEP := 40
## In a session: opens the board (debug, until the base hub places it).
const DEBUG_BOARD_KEY := KEY_END
## Contract states after "offered".
const ACCEPTED := "accepted"
const DEPLOYED := "deployed"
const VOIDED := "voided"
const ABORTED := "aborted"
const LAPSED := "lapsed"
## An offer nobody took before it ran out (contract_closed).
const EXPIRED := "expired"
## A recovery contract's objective: the squadmate left behind, as an HVT to bring out.
const MIA_HVT_PREFIX := "mia:"

## Show the debrief screen by itself when a debrief comes in (tests may turn it off).
var auto_show_debrief := true
## Save the campaign after contract events (accepting, the debrief, days passing).
var autosave := true
## The deployment's objectives (every peer).
var objectives: Objectives

var _remote: Dictionary = {}  # clients: the host's public state
var _dirty := false
var _ensuring := false
var _tried_load := false
var _shown_debrief := ""  # clients: "<campaign tag>:<serial>" of the last debrief shown
var _debrief_screen: Node


func _init() -> void:
	objectives = Objectives.new()
	objectives.name = "Objectives"
	add_child(objectives)


func _ready() -> void:
	Net.peer_joined.connect(_on_peer_joined)
	Economy.day_advanced.connect(_on_day_advanced)
	Economy.changed.connect(_on_economy_changed)
	Campaign.changed.connect(_on_campaign_changed)
	_connect_people.call_deferred()  # People is the next autoload
	debrief_ready.connect(func(_d: Dictionary) -> void:
		if auto_show_debrief:
			show_debrief())


# --- Reading (every peer) ----------------------------------------------------------------

## Offers on the board (public views).
func board() -> Array:
	return _view().get("board", [])


## Contracts the company holds (accepted or deployed; public views).
func held() -> Array:
	return _view().get("held", [])


## The deployment under way ({} when there's none): "zone_id", "zone_name", "zone_kind",
## "region", "module", "cids", "start_day", "civilians", "banked".
func deployment() -> Dictionary:
	return _view().get("deployment", {})


func is_deployed() -> bool:
	return not deployment().is_empty()


## The latest debrief ({} before the first): see DebriefCalc. "finished" once closed.
func last_debrief() -> Dictionary:
	return _view().get("debrief", {})


## Closed contracts, newest last: {"cid", "title", "employer", "outcome", "day"}.
func history() -> Array:
	return _view().get("history", [])


## A contract by id, on the board or held (host: the full record; clients: the public view).
func contract(cid: String) -> Dictionary:
	if _is_host():
		var s := _s()
		var found := _find(s.board, cid)
		return found if not found.is_empty() else _find(s.held, cid)
	for c: Dictionary in board() + held():
		if c.cid == cid:
			return c
	return {}


## What the briefing tells the squad about a contract: its public view plus the estimate in
## words and its objectives placed on the map (for the map agent's briefing).
func briefing(cid: String) -> Dictionary:
	var c := contract(cid)
	if c.is_empty():
		return {}
	var out := ContractGen.public_view(c)
	out["estimate"] = ContractGen.estimate_text(c)
	out["objective_markers"] = Objectives.from_contract(c, module_origin(c)).map(func(o: Dictionary) -> Dictionary:
		return {"text": o.text, "kind": o.kind, "pos": o.pos, "optional": o.optional})
	return out


## Host: the real enemy force of a contract, for whoever spawns it: {"count", "quality",
## "threats", "rating", "target"} (the briefing may have said less).
func enemy_force(cid: String) -> Dictionary:
	var c := _find(_s().held, cid)
	if c.is_empty():
		c = _find(_s().board, cid)
	if c.is_empty():
		return {}
	return {"count": int(c.enemy_count), "quality": float(c.quality), "threats": (c.threats as Array).duplicate(),
		"rating": int(c.true_rating), "target": c.target}


## Support budget left on a held contract (negotiated; supports draw on it before cash).
func support_left(cid: String) -> int:
	return int(contract(cid).get("support_left", 0))


## Where a contract's target module sits in the running level: its zone module's origin (a
## world-scale zone, by the contract's "module_id"), else `fallback` (the test compound sits
## at the origin).
func module_origin(c: Dictionary, fallback := Vector3.ZERO) -> Vector3:
	var module_id := String(c.get("module_id", ""))
	var lvl := CompoundLevel.current(self) if is_inside_tree() else null
	if module_id != "" and lvl and lvl.has_method(&"get_module"):
		var m := lvl.call(&"get_module", module_id) as Node3D
		if m:
			return m.position
	return fallback


## Host: the reinforcement timer's tuning (Reinforcements) for a contract, from its true force
## (enemy_force: what the briefing may have understated). Proposed, in contracts.json
## settings: the first wave comes sooner and the waves grow bigger the higher the true rating,
## living hostiles are capped at the true count plus "reinforcement_alive_extra", and the
## waves fight at the true quality. {} for an unknown contract.
func reinforcement_tuning(cid: String) -> Dictionary:
	var force := enemy_force(cid)
	if force.is_empty():
		return {}
	var t := clampf((int(force.rating) - 1) / 4.0, 0.0, 1.0)
	var first: Array = MissionRegistry.setting("reinforcement_first_wave_s", [420, 240])
	var pairs: Array = MissionRegistry.setting("reinforcement_max_pairs", [2, 4])
	var quality := float(force.quality)
	return {"first_wave_s": lerpf(float(first[0]), float(first[1]), t), "max_pairs": roundi(lerpf(float(pairs[0]), float(pairs[1]), t)),
		"first_pairs": 2 if int(force.count) >= 9 else 1,
		"max_alive": mini(int(force.count) + MissionRegistry.setting_i("reinforcement_alive_extra", 8), MissionRegistry.setting_i("reinforcement_alive_max", 30)),
		"combat": quality, "combat_max": minf(quality + 0.2, 0.9)}


# --- Host: people in the zone (the People ledger) ----------------------------------------

func _connect_people() -> void:
	People.civilian_casualty.connect(_on_civilian_casualty)
	People.hvt_delivered.connect(_on_hvt_delivered)
	People.hvt_lost.connect(_on_hvt_lost)
	People.intel_banked.connect(_on_intel_banked)


## A civilian our side hurt or killed: the first event for each civilian counts once (fines,
## and the 8th voids the deployment's contracts).
func _on_civilian_casualty(event: Dictionary) -> void:
	var dep: Dictionary = _s().deployment if _is_host() else {}
	if dep.is_empty():
		return
	var seen: Array = dep.get("casualty_uids", [])
	if String(event.get("uid", "")) in seen:
		return
	seen.append(String(event.get("uid", "")))
	dep["casualty_uids"] = seen
	server_civilian_casualty(event)


func _on_hvt_delivered(event: Dictionary) -> void:
	if _is_host() and is_deployed():
		server_hvt_delivered(String(event.get("hvt_id", "")), bool(event.get("alive", true)))


func _on_hvt_lost(event: Dictionary) -> void:
	if _is_host() and is_deployed():
		server_hvt_lost(String(event.get("hvt_id", "")))


## Intel carried into an extraction point is out: it counts for "carry it out" objectives
## (its own piece, by intel id), banks and shows in the debrief.
func _on_intel_banked(entry: Dictionary) -> void:
	if not _is_host() or not is_deployed() or String(entry.get("how", "")) != "carried" or String(entry.get("item", "")) == "":
		return
	server_items_banked([{"id": String(entry.item), "count": 1, "state": {"intel_id": String(entry.get("intel_id", "")), "source": String(entry.get("source", ""))}}])


# --- Host: campaign ----------------------------------------------------------------------

## Host: makes sure a campaign exists: loads the save for Campaign.campaign_id the first time
## if nothing has been loaded (its backup too when the save itself is gone, audit A1-02), else
## starts a fresh one. What the load has to say (a backup used, a damaged save kept aside) is
## told to the host.
func ensure_campaign() -> void:
	if _ensuring:
		return
	_ensuring = true
	if Campaign.section(Economy.SECTION).is_empty() and Campaign.section(SECTION).is_empty() and not _tried_load \
			and Campaign.has_save():
		_tried_load = true
		if not Campaign.load_campaign() and Campaign.last_load == Campaign.Loaded.UNREADABLE:
			BaseHub.set_aside_zone_saves()  # a fresh campaign starts in its name: its zones go aside too (A1-01)
		if Campaign.load_notice != "":
			_notify(1, Campaign.load_notice)
		# _on_campaign_changed skips while ensuring: put a saved deployment's objectives back.
		if not Campaign.section(SECTION).is_empty():
			objectives.server_restore(Campaign.section(SECTION).get("objectives", []))
			_commit()
	if Campaign.section(Economy.SECTION).is_empty():
		Economy.new_campaign()
	if Campaign.section(SECTION).is_empty():
		new_campaign()
	_ensuring = false


## Host: fresh contracts (no board, nothing held) from `campaign_seed` (random when < 0),
## and the first board.
func new_campaign(campaign_seed := -1) -> void:
	var s := Campaign.section(SECTION)
	s.clear()
	s.merge({"seed": campaign_seed if campaign_seed >= 0 else randi(), "tag": randi() % 1000000000, "next_id": 1, "board": [], "held": [],
		"history": [], "deployment": {}, "objectives": [], "debrief": {}, "debriefs": 0})
	objectives.server_clear()
	server_refresh_board()


## Host: a fresh campaign for both the economy and contracts.
func new_full_campaign(campaign_seed := -1, start_cash := -1) -> void:
	Economy.new_campaign(start_cash)
	new_campaign(campaign_seed)
	_save()


## Host: drops expired offers and tops the board up for today: regular offers up to
## "board_size", a low-risk one if none is left (the safety floor), and one special job per
## fixer the company stands well enough with.
func server_refresh_board() -> void:
	var s := _s()
	var today := Economy.day()
	for c: Dictionary in (s.board as Array).filter(func(c: Dictionary) -> bool: return int(c.expires_day) < today):
		contract_closed.emit(c, EXPIRED)
	s.board = (s.board as Array).filter(func(c: Dictionary) -> bool: return int(c.expires_day) >= today)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(s.seed), today, int(s.next_id)])
	var board: Array = s.board
	if not board.any(func(c: Dictionary) -> bool: return c.source == "safe"):
		_add_offer(ContractGen.generate(rng, {"day": today, "source": "safe"}))
	var board_size := MissionRegistry.setting_i("board_size", 6)
	while board.filter(func(c: Dictionary) -> bool: return c.source not in ["fixer", "recovery"]).size() < board_size:
		_add_offer(ContractGen.generate(rng, {"day": today, "source": "board"}))
	for fixer: Dictionary in MissionRegistry.fixers():
		if Economy.reputation(String(fixer.faction)) >= int(fixer.min_rep) \
				and not board.any(func(c: Dictionary) -> bool: return c.fixer == fixer.fixer):
			_add_offer(ContractGen.generate(rng, {"day": today, "source": "fixer", "fixer": fixer}))
	_commit()


## Host: puts a contract (ContractGen.generate's shape: a handmade story contract, or one the
## faction war posts) on the board. Returns its id.
func server_add_offer(c: Dictionary) -> String:
	var added := _add_offer(c.duplicate(true))
	_commit()
	return added.cid


func _add_offer(c: Dictionary) -> Dictionary:
	var s := _s()
	c.cid = "K%04d" % int(s.next_id)
	c.uid = "%d-%s" % [int(s.get("tag", 0)), c.cid]  # unique across campaigns: the people and intel it places
	s.next_id = int(s.next_id) + 1
	(s.board as Array).append(c)
	return c


## Host: a squadmate was left behind alive (BaseHub, settling a deployment). A recovery
## contract for the zone goes on the board: the company's own job, so it pays nothing and
## has no client; its one objective is to find them where they were left and bring them out
## (DELIVER_HVT on MIA_HVT_PREFIX + member id at their position, which BaseHub completes when
## they reach extraction). It runs "recovery_offer_days"; BaseHub recovers or writes them off
## when it closes (contract_closed). `info`: {"mid", "name", "callsign", "role", "zone_id",
## "day", "pos": [x, y, z]}. Returns its id.
func server_add_recovery(info: Dictionary) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(_s().seed), Economy.day(), int(_s().next_id), "recovery"])
	var c := ContractGen.generate(rng, {"day": Economy.day(), "source": "safe", "type": "hostage_rescue", "zone_id": String(info.get("zone_id", ""))})
	var callsign := String(info.get("callsign", info.get("name", "?")))
	var pos: Array = info.get("pos", [])
	c.merge({"title": "Recover %s: %s" % [callsign, c.zone_name], "source": "recovery", "type": "recovery", "module_id": "", "employer": "", "base_pay": 0,
		"brief": "%s (%s) was left behind alive in %s. Find them where they were last seen and bring them out." % [
			String(info.get("name", callsign)), String(info.get("role", "")), c.zone_name],
		"recover_mid": String(info.get("mid", "")), "clawback": ContractGen.NO_CLAWBACK,
		"expires_day": Economy.day() + MissionRegistry.setting_i("recovery_offer_days", 7),
		"objectives": [{"kind": Objectives.DELIVER_HVT, "text": "Find %s and bring them out" % callsign,
			"params": {"pos": pos if pos.size() == 3 else [0.0, 0.0, 0.0], "hvt": MIA_HVT_PREFIX + String(info.get("mid", ""))}}]}, true)
	var added := _add_offer(c)
	_notify_all("Recovery contract on the board: %s" % c.title)
	_commit()
	return added.cid


## Host: intel turned in opens a lead: a new, better-informed contract from `faction`
## (a cache, an HVT or more intel). Returns its id.
func server_open_lead(faction: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(_s().seed), Economy.day(), int(_s().next_id), "lead"])
	var lead_types := ["raid", "hvt_capture", "intel_grab"].filter(func(t: String) -> bool: return not MissionRegistry.type_def(t).is_empty())
	var ctx := {"day": Economy.day(), "source": "lead", "employer": faction, "zone_kind": "contract"}
	if not lead_types.is_empty():
		ctx["type"] = lead_types[rng.randi() % lead_types.size()]
	var c := _add_offer(ContractGen.generate(rng, ctx))
	c.title = "Lead: " + String(c.title)
	_commit()
	return c.cid


# --- Host: taking contracts --------------------------------------------------------------

## Host: accepts an offer on `terms` (ContractGen.default_terms() shape). Pays the advance.
## Returns "" or why not.
## `over_cap` (a hot zone's in-zone and radio contracts, HotZoneOps): taken during the
## deployment, so the company's "max_held" doesn't stop it.
func server_accept(cid: String, terms: Dictionary, peer_id := 1, over_cap := false) -> String:
	var s := _s()
	var c := _find(s.board, cid)
	var why := ""
	if c.is_empty():
		why = "That offer is gone"
	elif not over_cap and (s.held as Array).size() >= MissionRegistry.setting_i("max_held", 4):
		why = "The company can't hold more than %d contracts" % MissionRegistry.setting_i("max_held", 4)
	else:
		why = ContractGen.terms_problem(terms, Economy.reputation(String(c.employer)))
	if why != "":
		_notify(peer_id, why)
		return why
	var deal := ContractGen.deal(c, terms)
	c.terms = terms.duplicate()
	c.deal = deal
	c.state = ACCEPTED
	c.accepted_day = Economy.day()
	c.deadline_day = Economy.day() + MissionRegistry.setting_i("accept_window_days", 7)
	c.support_left = int(deal.support_budget)
	(s.board as Array).erase(c)
	(s.held as Array).append(c)
	Economy.add_cash(int(deal.advance), "Advance: %s" % c.title)
	_notify_all("Contract signed: %s. Advance $%s paid." % [c.title, DebriefCalc.money(deal.advance)])
	_commit()
	_save()
	contract_accepted.emit(cid)
	return ""


## Host: the briefing understated the threat (the world saw more than it said). The squad
## may now renegotiate or abort without the usual reputation hit.
func server_reveal_threat(cid: String) -> void:
	var c := _find(_s().held, cid)
	if c.is_empty() or c.revealed or not c.understated:
		return  # an honest briefing has nothing to reveal (and no free abort)
	c.revealed = true
	_notify_all("The briefing lied: %s is a %d, not a %d. Renegotiate or abort." % [c.title, int(c.true_rating), int(c.rated)])
	_commit()


## Host: renegotiates a contract whose threat was understated: completion pay rises by
## "renegotiate_pay_per_step" of the base pay per step the rating was short. Once per contract.
func server_renegotiate(cid: String, peer_id := 1) -> String:
	var c := _find(_s().held, cid)
	var why := ""
	if c.is_empty():
		why = "No such contract"
	elif not c.revealed or not c.understated:
		why = "Nothing to renegotiate: the threat is as briefed"
	elif c.renegotiated:
		why = "Already renegotiated"
	if why != "":
		_notify(peer_id, why)
		return why
	c.raise = ContractGen.renegotiation_raise(c)
	c.renegotiated = true
	c.rated = int(c.true_rating)
	_notify_all("Renegotiated %s: +$%s on completion" % [c.title, DebriefCalc.money(c.raise)])
	_commit()
	return ""


## Host: abandons a held contract. The advance is kept; reputation suffers unless the
## briefing was shown to have lied. Mid-deployment it stays in the debrief as "aborted".
func server_abort(cid: String, peer_id := 1) -> String:
	var s := _s()
	var c := _find(s.held, cid)
	if c.is_empty() or c.state not in [ACCEPTED, DEPLOYED]:
		_notify(peer_id, "No such contract")
		return "No such contract"
	var deployed: bool = c.state == DEPLOYED
	c.state = ABORTED
	objectives.server_fail_contract(cid)
	if not deployed:
		var hit := 0 if c.revealed and c.understated else MissionRegistry.setting_i("rep_abort", -4)
		Economy.change_reputation(String(c.employer), hit, "aborted " + String(c.cid))
		_close(c, ABORTED)
	_notify_all("Aborted %s" % c.title)
	_commit()
	return ""


# --- Host: deployment --------------------------------------------------------------------

## Host: deploys on held contracts. `cids` empty: every held contract for `zone_id` (or for
## the first held contract's zone when that's "" too). A contract zone takes one contract; a
## hot zone all of that zone's. Each contract's objectives sit at its target module in the
## running level (module_origin; `origin` when the level has no such module: the test
## compound sits at the origin). contract_live tells the people layer what to put there.
## Returns "" or why not.
func server_start_deployment(cids: Array = [], zone_id := "", origin := Vector3.ZERO) -> String:
	var s := _s()
	if not (s.deployment as Dictionary).is_empty():
		return "Already deployed"
	var ready: Array = (s.held as Array).filter(func(c: Dictionary) -> bool: return c.state == ACCEPTED)
	if not cids.is_empty():
		ready = ready.filter(func(c: Dictionary) -> bool: return c.cid in cids)
	if zone_id == "" and not ready.is_empty():
		zone_id = ready[0].zone_id
	ready = ready.filter(func(c: Dictionary) -> bool: return c.zone_id == zone_id)
	if ready.is_empty():
		return "No contract to deploy on"
	var first: Dictionary = ready[0]
	if first.zone_kind != "hot":
		ready = [first]
	else:
		ready.append_array(_hot_zone_extras(ready, zone_id))  # several contracts live at once
	var list: Array = []
	var live := {}
	for c: Dictionary in ready:
		c.state = DEPLOYED
		live[c.cid] = Objectives.from_contract(c, module_origin(c, origin))
		list.append_array(live[c.cid])
	if _is_host():
		People.reset_deployment()  # a new deployment's casualties, intel and deliveries
	s.deployment = {"zone_id": zone_id, "zone_name": first.zone_name, "zone_kind": first.zone_kind, "region": first.region,
		"module": first.module, "cids": ready.map(func(c: Dictionary) -> String: return c.cid), "start_day": Economy.day(),
		"civilians": 0, "banked": [], "origin": [origin.x, origin.y, origin.z]}
	objectives.server_begin(list)
	_notify_all("Deploying to %s" % first.zone_name)
	_commit()
	deployment_started.emit(s.deployment)
	for cid: String in live:
		contract_live.emit(cid, live[cid])
	return ""


## A hot zone has several of its faction's contracts live at once (Captain: 3-6, taken in any
## order). When the squad took fewer than HotZoneOps' minimum from the board, the faction hands
## it more on arrival (standard terms, advance paid), each at a site no other contract holds.
## Returns the new contracts (held, ACCEPTED).
func _hot_zone_extras(ready: Array, zone_id: String) -> Array:
	var want := HotZoneOps.live_target(int(_s().seed), Economy.day(), zone_id, ready.size())
	var out: Array = []
	var employer := String(MissionRegistry.zone(zone_id).get("faction", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(_s().seed), Economy.day(), zone_id, "in_zone"])
	var taken: Array = ready.map(func(c: Dictionary) -> String: return String(c.get("module_id", "")))
	while ready.size() + out.size() < want:
		var c := _add_offer(ContractGen.generate(rng, {"day": Economy.day(), "source": "board", "zone_id": zone_id,
			"employer": employer, "avoid_modules": taken}))
		c["in_zone"] = "arrival"
		if server_accept(c.cid, ContractGen.default_terms(), 1, true) != "":
			(_s().board as Array).erase(c)
			break
		taken.append(String(c.module_id))
		out.append(c)
	return out


## Host: notes `key` on the deployment under way (HotZoneOps: "hazard_tier", the highest
## pressure tier reached, for the debrief's hazard pay).
func server_note_deployment(key: String, value: Variant) -> void:
	var dep: Dictionary = _s().deployment
	if dep.is_empty():
		return
	dep[key] = value
	_commit()


## The open (not yet done) deployed contracts' sites, by module id (HotZoneOps: a radio
## contract goes to a site no other live contract holds).
func live_sites() -> Array:
	var dep: Dictionary = _s().deployment
	var out: Array = []
	for c: Dictionary in _s().held:
		if c.cid in dep.get("cids", []) and not objectives.contract_done(c.cid) and String(c.get("module_id", "")) != "":
			out.append(String(c.module_id))
	return out


## Host: a deployment that never ended (a campaign saved mid-deployment and loaded again,
## everyone back at the base): its contracts are held again as before it, its objectives gone.
func server_abandon_deployment() -> void:
	var s := _s()
	var dep: Dictionary = s.deployment
	if dep.is_empty():
		return
	for c: Dictionary in s.held:
		if c.cid in dep.get("cids", []) and c.state == DEPLOYED:
			c.state = ACCEPTED
	s.deployment = {}
	objectives.server_clear()
	_commit()


## Why no radio contract can come in now ("" if one can): only in a hot zone, and only with a
## field radio in the squad (Captain 2026-10-12): a player or squad AI carrying an item tagged
## "radio" that isn't an enemy handheld (RadioChatter.has_field_radio; a looted enemy set
## can't reach the employer).
func radio_contract_problem() -> String:
	var dep: Dictionary = _s().deployment
	if dep.is_empty() or dep.zone_kind != "hot":
		return "Radio contracts come in only in a hot zone"
	if not RadioChatter.has_field_radio(self):
		return "No field radio in the squad"
	return ""


## Host: in a hot zone, a new contract comes in over the radio and the squad takes it on the
## spot (standard terms, advance paid); its objectives join the deployment. Returns its id, or
## "" when radio_contract_problem() says no. HotZoneOps' follow-ups pass the site (`module_id`)
## and the employer's words (`why`, said to everyone with the contract's title).
func server_radio_contract(type_id := "", module_id := "", why := "") -> String:
	if radio_contract_problem() != "":
		return ""
	var dep: Dictionary = _s().deployment
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(_s().seed), Economy.day(), int(_s().next_id), "radio"])
	var employer := String(MissionRegistry.zone(dep.zone_id).get("faction", ""))
	var c := _add_offer(ContractGen.generate(rng, {"day": Economy.day(), "source": "board", "zone_id": dep.zone_id,
		"type": type_id, "employer": employer, "module_id": module_id, "avoid_modules": live_sites()}))
	c["in_zone"] = "radio"
	if server_accept(c.cid, ContractGen.default_terms(), 1, true) != "":
		(_s().board as Array).erase(c)
		return ""
	c.state = DEPLOYED
	(dep.cids as Array).append(c.cid)
	var o: Array = dep.get("origin", [0, 0, 0])
	var added := Objectives.from_contract(c, module_origin(c, Vector3(float(o[0]), float(o[1]), float(o[2]))))
	objectives.server_add(added)
	if why != "":
		_notify_all("Radio, %s: %s New contract: %s" % [MissionRegistry.faction_name(employer), why, c.title])
	_commit()
	contract_live.emit(c.cid, added)
	return c.cid


## Host: a civilian was hurt or killed by the squad (players or their AI; the caller decides,
## other factions' victims don't count). Each costs a fine and reputation at the debrief; at
## "civilian_void_at" (8) every contract of the deployment is voided and pays nothing more.
## `info` is free-form (who, where) for the log. Returns the count so far.
func server_civilian_casualty(info := {}) -> int:
	var dep: Dictionary = _s().deployment
	if dep.is_empty():
		return 0
	dep.civilians = int(dep.civilians) + 1
	var void_at := MissionRegistry.setting_i("civilian_void_at", 8)
	print("[contracts] civilian casualty %d of %d %s" % [int(dep.civilians), void_at, info])
	_notify_all("Civilian casualty (%d). Fine $%s." % [int(dep.civilians), DebriefCalc.money(MissionRegistry.setting_i("civilian_fine", 2500))])
	if int(dep.civilians) >= void_at:
		for cid: String in dep.cids:
			var c := _find(_s().held, cid)
			if not c.is_empty() and c.state == DEPLOYED:
				c.state = VOIDED
				objectives.server_fail_contract(cid)
				contract_voided.emit(cid)
				_notify_all("%s is VOIDED: %d civilian casualties" % [c.title, int(dep.civilians)])
	_commit()
	return int(dep.civilians)


## Host: an HVT reached extraction (or a vehicle seat that got out). The people agent calls it.
func server_hvt_delivered(hvt_id: String, alive := true) -> void:
	objectives.server_hvt_delivered(hvt_id, alive)


func server_hvt_lost(hvt_id: String) -> void:
	objectives.server_hvt_lost(hvt_id)


func server_cache_destroyed(cache_id: String) -> void:
	objectives.server_cache_destroyed(cache_id)


## Host: loot sent out mid-deployment (a hot zone's extraction run): it banks at once, counts
## for "carry it out" objectives and shows in the debrief. [{"id", "count", "state"}].
func server_items_banked(items: Array) -> void:
	var dep: Dictionary = _s().deployment
	if dep.is_empty():
		return
	(dep.banked as Array).append_array(items.duplicate(true))
	objectives.server_items_out(items)
	Economy.bank_items(items, "banked mid-zone")
	_commit()


## Host: takes from a contract's support budget (negative gives back). Returns what it took.
func server_draw_support(cid: String, amount: int) -> int:
	var c := _find(_s().held, cid)
	if c.is_empty():
		return 0
	var take := mini(amount, int(c.get("support_left", 0)))
	c.support_left = int(c.get("support_left", 0)) - take
	_commit()
	return take


## Host: the deployment ends at extraction. The map agent's extraction calls this with what
## got out; the result is the debrief (DebriefCalc), shown on every peer. `report`:
## - "items": [{"id", "count", "state"}]: everything carried out (all banked);
## - "field_items": what was left in the zone (the salvage pool the share lets the squad
##   claim from), optional;
## - "extracted": names of who got out; "casualties": [{"name", "status" ("kia", "mia",
##   "wounded"), "injury"}];
## - "hvts": [{"hvt", "alive"}] delivered at extraction (also server_hvt_delivered);
## - "bank": what else came out, banked instead of "items" (BaseHub: set down at the point,
##   bodies brought in); "driven_out": in the hold of a motor-pool vehicle going home (B-18:
##   it counts and shows in the debrief, but isn't banked: it stays in the vehicle).
## report_from_level(level, soldiers) builds one from the level as it stands.
func server_end_deployment(report: Dictionary) -> Dictionary:
	var s := _s()
	var dep: Dictionary = s.deployment
	if dep.is_empty():
		return {}
	for h: Dictionary in report.get("hvts", []):
		objectives.server_hvt_delivered(String(h.get("hvt", "")), bool(h.get("alive", true)))
	# B-18: what else came out (BaseHub's "bank": items set down in the point, a helicopter's
	# hold, bodies carried in) counts for "carry it out" objectives and shows in the debrief too,
	# not only what the people still hold: intel set down at the point debriefed "failed".
	var out_items: Array = (report.get("items", []) as Array) + (report.get("bank", []) as Array) + (dep.banked as Array)
	# And what went home in a motor-pool vehicle's hold ("driven_out"): a hard case driven out in
	# the M-ATV debriefed "failed" too. It stays in the vehicle, so it isn't banked below.
	for entry: Dictionary in report.get("driven_out", []):
		out_items.append_array(flatten_entry(entry))
	objectives.server_items_out(out_items)
	for o: Dictionary in objectives.active():
		objectives.server_set_state(o.oid, Objectives.FAILED)
	var deployed: Array = (s.held as Array).filter(func(c: Dictionary) -> bool: return c.cid in dep.cids)
	var calc_report := report.duplicate(true)
	calc_report["items"] = out_items
	calc_report["hazard_tier"] = int(dep.get("hazard_tier", 0))  # a hot zone's hazard pay (HotZoneOps)
	var debrief := DebriefCalc.compute(deployed, objectives.list, int(dep.civilians), calc_report)
	debrief["zone_name"] = dep.zone_name
	debrief["extracted"] = report.get("extracted", [])
	s.debriefs = int(s.get("debriefs", 0)) + 1
	debrief["serial"] = s.debriefs
	debrief["key"] = "%d:%d" % [int(s.get("tag", 0)), int(s.debriefs)]  # clients show each debrief once, across campaign resets
	# Pay, fines and reputation.
	for line: Dictionary in debrief.contracts:
		if int(line.pay) > 0:
			Economy.add_cash(int(line.pay), "Completion: %s" % line.title)
	if int(debrief.fines) > 0:
		Economy.add_cash(-int(debrief.fines), "Civilian fines (%d)" % int(debrief.civilians))
	for line: Dictionary in debrief.contracts:
		if int(line.clawback) > 0:
			Economy.add_cash(-int(line.clawback), "Advance clawed back (voided): %s" % line.title)
	for f: String in debrief.rep:
		Economy.change_reputation(f, int(debrief.rep[f]), "debrief")
	Economy.change_locals(int(debrief.locals))
	for c: Dictionary in deployed:
		var result: Dictionary = (debrief.contracts as Array).filter(func(l: Dictionary) -> bool: return l.cid == c.cid)[0]
		_close(c, String(result.outcome))
	# What came home goes to the base. In a campaign the people bring their own gear home
	# (BaseHub), so the report says what else to bank ("bank": bodies and items set down).
	Economy.bank_items(report.get("bank", report.get("items", [])), "carried out")
	s.deployment = {}
	s.debrief = debrief
	objectives.server_clear()
	Economy.advance_days(int(debrief.days), "deployment to %s" % debrief.zone_name)
	debrief["day"] = Economy.day()
	SessionLog.note(debrief_log_line(debrief, report))
	_commit()
	_save()
	debrief_ready.emit(debrief)
	return debrief


## The session log's line for a debrief: each contract's outcome, pay and clawback, fines, and
## the losses ("debrief: Harbour Yard: Hold the Line done, paid $12000; fines $0; out: Gunny,
## Player 1; casualties: Reaper kia").
static func debrief_log_line(debrief: Dictionary, report: Dictionary) -> String:
	var lines := PackedStringArray()
	for line: Dictionary in debrief.get("contracts", []):
		var text := "%s %s, paid $%d" % [String(line.get("title", "?")), String(line.get("outcome", "?")), int(line.get("pay", 0))]
		if int(line.get("clawback", 0)) > 0:
			text += ", $%d advance clawed back" % int(line.clawback)
		lines.append(text)
	var losses := PackedStringArray()
	for c: Dictionary in report.get("casualties", []):
		losses.append("%s %s" % [String(c.get("name", "?")), String(c.get("status", "?"))])
	return "debrief: %s: %s; fines $%d (%d civilians); %d days; out: %s; casualties: %s" % [String(debrief.get("zone_name", "?")),
		"; ".join(lines) if not lines.is_empty() else "no contract", int(debrief.get("fines", 0)), int(debrief.get("civilians", 0)),
		int(debrief.get("days", 0)), ", ".join(PackedStringArray(report.get("extracted", []))) if not (report.get("extracted", []) as Array).is_empty() else "nobody",
		", ".join(losses) if not losses.is_empty() else "none"]


## Host: claims salvage pool entry `index` against the salvage budget. Returns whether it fit.
func server_pick_salvage(index: int) -> bool:
	var d: Dictionary = _s().debrief
	if d.is_empty() or d.finished or not DebriefCalc.can_pick(d, index):
		return false
	(d.salvage.picked as Array).append(index)
	d.salvage.spent = int(d.salvage.spent) + int(d.salvage.pool[index].value)
	_commit()
	return true


func server_unpick_salvage(index: int) -> bool:
	var d: Dictionary = _s().debrief
	if d.is_empty() or d.finished or not index in d.salvage.picked:
		return false
	(d.salvage.picked as Array).erase(index)
	d.salvage.spent = int(d.salvage.spent) - int(d.salvage.pool[index].value)
	_commit()
	return true


## The client of the debriefed deployment (intel goes to them, or is sold behind their back).
func debrief_client() -> String:
	var lines: Array = last_debrief().get("contracts", [])
	return String(lines[0].employer) if not lines.is_empty() else ""


## Host: hands intel entry `index` to the client: each piece opens a lead (a new contract on
## the board) and earns a little reputation. Returns "" or why not.
func server_turn_in_intel(index: int) -> String:
	var d: Dictionary = _s().debrief
	if d.is_empty() or index < 0 or index >= (d.intel as Array).size() or d.intel[index].status != "pending":
		return "Nothing to turn in"
	var client := debrief_client()
	var entry: Dictionary = d.intel[index]
	entry.status = "turned_in"
	entry.leads = []
	for i in int(entry.count):
		(entry.leads as Array).append(server_open_lead(client if client != "" else Economy.best_lender()))
	Economy.change_reputation(client, MissionRegistry.setting_i("intel_lead_rep", 2), "intel turned in")
	_notify_all("Intel turned in: %d new lead%s on the board" % [int(entry.count), "" if int(entry.count) == 1 else "s"])
	_commit()
	return ""


## Host: sells intel entry `index` to `faction` (not the client): cash and a little standing
## with the buyer, but with "intel_sale_risk" the client finds out and is angered. Returns ""
## or why not.
func server_sell_intel(index: int, faction: String) -> String:
	var d: Dictionary = _s().debrief
	var client := debrief_client()
	if d.is_empty() or index < 0 or index >= (d.intel as Array).size() or d.intel[index].status != "pending":
		return "Nothing to sell"
	if faction == client or MissionRegistry.faction(faction).is_empty():
		return "Sell it to another faction"
	var entry: Dictionary = d.intel[index]
	entry.status = "sold"
	entry.buyer = faction
	var price := MissionRegistry.setting_i("intel_sale_price", 6000) * int(entry.count)
	Economy.add_cash(price, "Intel sold to %s" % MissionRegistry.faction_name(faction))
	Economy.change_reputation(faction, MissionRegistry.setting_i("intel_sale_rep_buyer", 2), "bought intel")
	entry.caught = randf() < MissionRegistry.setting_f("intel_sale_risk", 0.35)
	if entry.caught:
		Economy.change_reputation(client, MissionRegistry.setting_i("intel_sale_rep_client", -8), "intel sold behind their back")
	_notify_all("Intel sold to %s for $%s%s" % [MissionRegistry.faction_name(faction), DebriefCalc.money(price),
		(". %s found out." % MissionRegistry.faction_name(client)) if entry.caught else ""])
	_commit()
	return ""


## Host: closes the debrief: the salvage picks are banked and intel nobody decided on goes
## to the client.
func server_finish_debrief() -> void:
	var d: Dictionary = _s().debrief
	if d.is_empty() or d.finished:
		return
	for i in (d.intel as Array).size():
		if d.intel[i].status == "pending":
			server_turn_in_intel(i)
	var picks: Array = []
	for i: int in d.salvage.picked:
		picks.append(d.salvage.pool[i])
	Economy.bank_items(picks, "salvage")
	d.finished = true
	_commit()
	_save()
	debrief_closed.emit()


# --- Host: the level ---------------------------------------------------------------------

## An extraction report (see server_end_deployment) from the level as it stands, with
## `extracted` (Soldiers) getting out: what they carry is "items"; loose items and what's
## on the dead is "field_items"; friendly squadmates left behind are casualties (dead: KIA,
## alive: MIA), and those who got out hurt are "wounded". `banked`: uids (WorldItem.uid,
## Soldier.body_uid) of what came out at the extraction point and is banked on its own (items
## set down there, bodies brought there): not salvage as well (the loop test caught it offered
## twice).
static func report_from_level(level: CompoundLevel, extracted: Array, banked := {}) -> Dictionary:
	var items: Array = []
	var names: Array = []
	var casualties: Array = []
	var out := {}
	for s: Soldier in extracted:
		out[s] = true
		names.append(s.display_name())
		items.append_array(inventory_items(s.inventory))
		if s.vitals.injury() > 0.05 or not s.vitals.is_up():
			casualties.append({"name": s.display_name(), "status": "wounded", "injury": s.vitals.condition_text()})
	var field: Array = []
	for node in level.get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := node as WorldItem
		if item and not item.is_queued_for_deletion() and not banked.has(item.uid):
			field.append_array(flatten_entry({"id": item.item_id, "count": item.count, "state": item.state}))
	for node in level.get_tree().get_nodes_in_group(&"combatants") + level.get_tree().get_nodes_in_group(&"dead_bodies"):
		var s := node as Soldier
		if s == null or out.has(s) or s.is_queued_for_deletion():
			continue
		if s.has_meta(&"vehicle_crew") and not s.vitals.is_dead():
			continue  # wave 5b: a support vehicle's crew isn't the squad's, nor missing (it goes home with it)
		out[s] = true
		if s.vitals.is_dead() and not banked.has(s.body_uid):
			field.append_array(inventory_items(s.inventory))
		if s.faction == &"friendly":
			casualties.append({"name": s.display_name(), "status": "kia" if s.vitals.is_dead() else "mia", "injury": s.vitals.condition_text()})
	return {"items": items, "field_items": field, "extracted": names, "casualties": casualties}


## Everything on a body: worn items (a carrier's MOLLE pouches and what's in them as entries
## of their own, see flatten_entry), what's in its containers and what's in its hands.
static func inventory_items(inv: Inventory) -> Array:
	var items: Array = []
	for slot: StringName in Inventory.SLOTS:
		if inv.slots.get(slot, &"") != &"":
			items.append_array(flatten_entry({"id": inv.slots[slot], "count": 1, "state": inv.slot_state.get(slot, {})}))
	# Pouch containers ("molle:...") are the worn carrier's state, already listed with it.
	for container: StringName in Inventory.CONTAINERS:
		for entry: Dictionary in inv.containers.get(container, []):
			items.append_array(flatten_entry(entry))
	if inv.hands != &"":
		items.append({"id": String(inv.hands), "count": 1, "state": {}})
	return items


## One inventory or world entry ({"id", "count", "state"?}) as report entries: a carrier's
## MOLLE attachments (its state's "molle") and a pouch's contents (its state's "held") come
## out as entries of their own, so each is valued, can be a salvage pick and counts for an
## objective (intel carried in a pouch). Copies; the entry is left as it was.
static func flatten_entry(entry: Dictionary) -> Array:
	var state: Dictionary = (entry.get("state", {}) as Dictionary).duplicate(true)
	var molle: Dictionary = state.get("molle", {})
	var held: Array = state.get("held", [])
	state.erase("molle")
	state.erase("held")
	var out: Array = [{"id": String(entry.get("id", "")), "count": int(entry.get("count", 1)), "state": state}]
	for point: Variant in molle:
		var att: Dictionary = molle[point]
		out.append_array(flatten_entry({"id": att.get("id", ""), "count": 1, "state": {"held": att.get("held", [])}}))
	for inner: Dictionary in held:
		out.append_array(flatten_entry(inner))
	return out


# --- Requests (any peer) -----------------------------------------------------------------

func accept(cid: String, terms: Dictionary) -> void:
	if _is_host():
		server_accept(cid, terms)
	else:
		_rq.rpc_id(1, "accept", [cid, terms])


func renegotiate(cid: String) -> void:
	_request("renegotiate", [cid])


func abort(cid: String) -> void:
	_request("abort", [cid])


func pick_salvage(index: int) -> void:
	_request("pick", [index])


func unpick_salvage(index: int) -> void:
	_request("unpick", [index])


func turn_in_intel(index: int) -> void:
	_request("turn_in", [index])


func sell_intel(index: int, faction: String) -> void:
	_request("sell", [index, faction])


func finish_debrief() -> void:
	_request("finish", [])


func _request(what: String, args: Array) -> void:
	if _is_host():
		_handle(what, args, 1)
	else:
		_rq.rpc_id(1, what, args)


## What each request's arguments must be (audit A1-05), checked before any is read.
const REQUEST_ARGS := {"accept": [TYPE_STRING, TYPE_DICTIONARY], "renegotiate": [TYPE_STRING], "abort": [TYPE_STRING],
	"pick": [TYPE_INT], "unpick": [TYPE_INT], "turn_in": [TYPE_INT], "sell": [TYPE_INT, TYPE_STRING], "finish": []}


## Untyped on purpose: whatever a client sends reaches _handle, which checks it.
@rpc("any_peer", "call_remote", "reliable")
func _rq(what: Variant, args: Variant) -> void:
	if multiplayer.is_server():
		_handle(what, args, multiplayer.get_remote_sender_id())


## Whether `args` are what request `what` takes (REQUEST_ARGS): that many, of those types.
static func request_ok(what: Variant, args: Variant) -> bool:
	if typeof(what) != TYPE_STRING or not REQUEST_ARGS.has(what) or typeof(args) != TYPE_ARRAY:
		return false
	var want: Array = REQUEST_ARGS[what]
	if (args as Array).size() != want.size():
		return false
	for i in want.size():
		var t := typeof(args[i])
		if t != want[i] and not (want[i] == TYPE_STRING and t == TYPE_STRING_NAME):
			return false
	return true


## Host: a request from `peer` (1: the host itself). A malformed one, local or remote, is
## refused before any argument is read (audit A1-05).
func _handle(what: Variant, args: Variant, peer: int) -> void:
	if not request_ok(what, args):
		push_warning("Contracts: refused a malformed request from peer %d: %s %s" % [peer, str(what).left(40), str(args).left(120)])
		_notify(peer, "Bad request")
		return
	var why := ""
	match what:
		"accept":
			why = server_accept(String(args[0]), args[1], peer)
		"renegotiate":
			why = server_renegotiate(String(args[0]), peer)
		"abort":
			why = server_abort(String(args[0]), peer)
		"pick":
			if not server_pick_salvage(int(args[0])):
				why = "That won't fit the salvage budget"
		"unpick":
			server_unpick_salvage(int(args[0]))
		"turn_in":
			why = server_turn_in_intel(int(args[0]))
		"sell":
			why = server_sell_intel(int(args[0]), String(args[1]))
		"finish":
			if peer == 1:  # only the host closes the debrief (it banks the picks and the intel)
				server_finish_debrief()
	if why != "" and what not in ["accept", "renegotiate", "abort"]:
		_notify(peer, why)


# --- Screens -----------------------------------------------------------------------------

## Opens the contract board (with negotiation, the shop and the debug controls) over
## everything. Returns it.
func open_board() -> ContractBoard:
	var board_screen := ContractBoard.new()
	get_tree().root.add_child(board_screen)
	return board_screen


## Shows the latest debrief (once per debrief; returns the screen, or null).
func show_debrief() -> DebriefScreen:
	if is_instance_valid(_debrief_screen):
		_debrief_screen.queue_free()
	var screen := DebriefScreen.new()
	get_tree().root.add_child(screen)
	_debrief_screen = screen
	return screen


func debrief_screen() -> DebriefScreen:
	return _debrief_screen as DebriefScreen if is_instance_valid(_debrief_screen) else null


## Closes the contract screens open on this peer (the debrief, any contract board). BaseHub
## calls it when the session moves into a zone (Captain, 2026-10-14: a client sat on the
## debrief after the host had gone back to base and on into the next zone, and couldn't leave
## it): every peer follows the host's level switch, whatever is open.
func close_screens() -> void:
	var screen := debrief_screen()
	if screen and not screen.is_queued_for_deletion():
		screen.close()
	for child in get_tree().root.get_children():
		if child is ContractBoard and not child.is_queued_for_deletion():
			(child as ContractBoard).close()


# --- Internals ---------------------------------------------------------------------------

## Host: called by Objectives whenever they change, so a saved deployment keeps them.
func store_objectives(list: Array) -> void:
	if _is_host() and not Campaign.section(SECTION).is_empty():
		Campaign.section(SECTION).objectives = list.duplicate(true)
		Campaign.mark_changed(SECTION)


func _on_day_advanced(today: int, _days: int) -> void:
	var s := _s()
	for c: Dictionary in (s.held as Array).duplicate():
		if c.state == ACCEPTED and int(c.deadline_day) < today:
			Economy.change_reputation(String(c.employer), MissionRegistry.setting_i("rep_lapse", -3), "lapsed " + String(c.cid))
			_notify_all("%s lapsed: %s is unhappy" % [c.title, MissionRegistry.faction_name(String(c.employer))])
			_close(c, LAPSED)
	server_refresh_board()
	_save()


## Moves a held contract into the history with its outcome.
func _close(c: Dictionary, outcome: String) -> void:
	var s := _s()
	c.state = outcome
	(s.held as Array).erase(c)
	var hist: Array = s.history
	hist.append({"cid": c.cid, "title": c.title, "employer": c.employer, "outcome": outcome, "day": Economy.day()})
	while hist.size() > HISTORY_KEEP:
		hist.pop_front()
	contract_closed.emit(c, outcome)


func _find(list: Array, cid: String) -> Dictionary:
	for c: Dictionary in list:
		if c.cid == cid:
			return c
	return {}


## Whether this peer decides (the host, or offline).
func is_host() -> bool:
	return _is_host()


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _s() -> Dictionary:
	var s := Campaign.section(SECTION)
	if s.is_empty():
		ensure_campaign()
		s = Campaign.section(SECTION)
	return s


func _view() -> Dictionary:
	return _public() if _is_host() else _remote


## What every peer may see.
func _public() -> Dictionary:
	if Campaign.section(SECTION).is_empty():
		return {}
	var s := Campaign.section(SECTION)
	return {
		"board": (s.board as Array).map(func(c: Dictionary) -> Dictionary: return ContractGen.public_view(c)),
		"held": (s.held as Array).map(func(c: Dictionary) -> Dictionary: return ContractGen.public_view(c)),
		"deployment": (s.deployment as Dictionary).duplicate(true), "debrief": (s.debrief as Dictionary).duplicate(true),
		"history": (s.history as Array).duplicate(true),
	}


func _commit() -> void:
	Campaign.mark_changed(SECTION)
	changed.emit()
	if not _dirty:
		_dirty = true
		_flush.call_deferred()


func _flush() -> void:
	_dirty = false
	if _online():
		_sync.rpc(_public())


func _save() -> void:
	if autosave and _is_host() and not Campaign.save_campaign():
		_notify(1, "Campaign NOT saved: " + Campaign.save_error)  # audit A1-04: the host hears of it


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server() and not Campaign.section(SECTION).is_empty():
		_sync.rpc_id(id, _public())


## Debug: End opens the board in a session (any peer; the host gets its stand-in controls).
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != DEBUG_BOARD_KEY or key.shift_pressed:
		return
	if CompoundLevel.current(self) == null or not get_tree().root.find_children("*", "ContractBoard", true, false).is_empty():
		return
	get_viewport().set_input_as_handled()
	open_board()


func _on_economy_changed() -> void:
	if not _is_host():
		return
	changed.emit()  # the board's negotiation room follows reputation


func _on_campaign_changed(section_name: StringName) -> void:
	if section_name != SECTION or not _is_host() or _ensuring:
		return
	# A loaded save: put its deployment's objectives back.
	var s := Campaign.section(SECTION)
	if not s.is_empty() and objectives.list != s.get("objectives", []):
		objectives.server_restore(s.get("objectives", []))
	if not _dirty:
		_dirty = true
		_flush.call_deferred()


@rpc("authority", "call_remote", "reliable")
func _sync(state: Dictionary) -> void:
	_remote = state
	changed.emit()
	var d: Dictionary = state.get("debrief", {})
	var key := String(d.get("key", str(d.get("serial", -1))))
	if not d.is_empty() and not d.get("finished", false) and key != _shown_debrief:
		_shown_debrief = key
		debrief_ready.emit(d)


func _notify(peer_id: int, text: String) -> void:
	if peer_id <= 1 or not _online():
		notice.emit(text)
	else:
		_notice.rpc_id(peer_id, text)


func _notify_all(text: String) -> void:
	print("[contracts] " + text)
	notice.emit(text)
	if _online():
		_notice.rpc(text)


@rpc("authority", "call_remote", "reliable")
func _notice(text: String) -> void:
	notice.emit(text)


func _online() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
