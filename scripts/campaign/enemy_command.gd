class_name EnemyCommand
extends Node
## A hot zone's enemy high command, OPFOR's guiding hand (docs/enemy_high_command.md; Captain,
## 2026-10-17: "if an outpost is lost and a suitable force cant take it back we shouldnt be
## assaulted by the rest of the map. the high commander can control high level stuff like that";
## his answers the same day: ratios kept, finite reserves, a huntable commander, reoccupy when
## the commander decides). It decides; the zone's EnemyResponse does the doing (spawning,
## routes, gates, technicals).
##
## - Fog: it judges the squad only by what reached its radio net. A contact report says how many
##   it saw (Alert: "seen", "exo"); the most seen (CP: SQUAD_MAN_CP a man, +EXO_CP in a frame)
##   fades SEEN_FADE_PER_MIN a minute unseen, raised by its own recent losses (LOSS_SHARE of the
##   dead in LOSS_WINDOW_S). At a site it counts only contact reports from within SITE_THREAT_M
##   fresher than LKP_FRESH_S (the most any one saw): a quiet squad is misjudged.
## - Reserves: a finite pool for the deployment (RESERVE_POOL by Pressure tier, more as the tier
##   rises), refilled slowly (REFILL_PER_MIN) up to a cap that shrinks with every QRF base or HQ
##   lost (and the pool with it). Everything it sends is paid from it, beside the spawn budget.
## - Hunts (EnemyResponse's QRF launches and hunter teams) go only at HUNT_RATIO of the threat
##   (approve); hunters also need an LKP fresher than HUNT_FRESH_S. A stale LKP gets a Probe.
## - Hunts have a stop: a hunter team out HUNT_STOP_S is called home (no endless sweeps).
## - Probe: PROBE_SIZE men walk to a stale LKP or a lost site, look PROBE_LOOK_S and pull back
##   on contact. With comms down they never report back.
## - A garrisoned site lost (ZoneLevel.site_down): if it thinks the squad is there, a
##   Counterattack at COUNTER_RATIO (assemble at a rally point RALLY_M short, out of sight, go in
##   together; called off under CALL_OFF_RATIO), else Contain (no attack, rechecked every
##   RECHECK_S). If it thinks nobody's there, a Probe first: a clear site is Reoccupied
##   (REOCCUPY_MIN men, the probe stays); contact, and it decides again with what it now knows:
##   fewer there than it thinks the squad is (someone left behind on it, a squadmate or rebel),
##   it retakes the site at REOCCUPY_RATIO instead.
##   Men on a retaken site are its garrison again (meta "garrison_of": ZoneLevel.garrison_alive).
## - The HQ's pairs to its outposts and checkpoints (EnemyResponse._reinforce_sites) ask it too
##   (request_men) and are paid from the reserves; none once it consolidates.
## Kept simple to be extended (the rest of Phase 2b in the doc).
## - Consolidate: past WITHDRAW_SHARE of all its men lost, hunters, waves and task forces fall
##   back on the HQ and QRF bases, and the outposts and checkpoints are abandoned (their
##   garrisons walk to the nearest base: meta "left_post", no longer the site's garrison); no
##   more hunts or probes, and only the bases are fought for.
## - Decapitation: the commander is the HQ's officer post 0 (commander_name: a contract can name
##   him). Killed, nobody decides for HEADLESS_S (task forces assembling hold where they are),
##   then the deputy (post 1) commands at DEPUTY_TICK_MULT the tick; both dead, nobody does.
##   No HQ in the zone: an unseen commander, never killed. A hostile HVT at the HQ (an
##   hvt_capture contract there: HotZoneOps sends one after the QRF base falls) IS the
##   commander: captured (cuffed or surrendered), delivered or dead, the zone is headless.
##   He has GUARD_SIZE bodyguards (HvtAI keeps him behind the nearest hostile up). The HQ hit
##   (a contact report near it, or its area ENGAGED): the guards take him to the nearest QRF base
##   (none left: they hold at the HQ) and he calls for help, one relief counterattack on the HQ
##   at COUNTER_RATIO. Guards dead and the squad on him, HvtAI has him give up (cornered).
## - Comms down (Alert.comms_down): the tick is COMMS_TICK_MULT slower, task forces take
##   COMMS_ASSEMBLE_MULT longer to assemble, probes don't report.
## - Deception (Captain, 2026-10-17): noise (shots, blasts) reported farther than NOISE_FAR_M
##   from the last sighting is unconfirmed: hunts and QRFs toward it are turned down for a probe.
##   Loud fire is over-reported: every shot (SHOT_CP) and blast (BLAST_CP) reported within
##   NOISE_NEAR_M in NOISE_WINDOW_S reads as more men (to NOISE_CP_MAX), so a loud squad gets a
##   cautious enemy. With a looted radio the squad can call in a fake contact (server_spoof);
##   after the first, each may be caught (SPOOF_CATCH_CHANCE): the net switches frequency.
## - Memory: a commander who keeps losing grows cautious, one who keeps winning bold (`caution`,
##   -1..1: every ratio × 1 + CAUTION_RATIO × caution). Kept per zone across deployments in the
##   campaign (section "enemy_command"), drifting back toward 0 by CAUTION_DRIFT_PER_DAY a
##   campaign day so a beaten zone recovers.
## - Its orders go out on the net (RadioChatter.order): a looted radio hears them.
## - At most MAX_OPS operations moving or attacking at once (MAX_OPS_HIGH from tier 3).
## - The picture (docs/combined_arms.md 3.2, B1): what reached its net lives in `picture`, the
##   hostile SidePicture (Alert's reports, already delayed by Alert: 60-15 s by discipline, x1.5
##   under fire, x3 with the mast down), merged into entries like the friendly side's; shots and
##   blasts are in its log as noise, never entries. threat_cp reads that log, so the fog above is
##   unchanged. Its groups are on `board` (GroupBoard, refreshed each tick) for B2's SideCommand.
## Every decision is a record in `operations` ({"kind", "target", "state", "why", "at", ...}).
## Host only; one node per hot zone ("EnemyCommand", ZoneLevel), on the Alert's clock. All
## numbers Proposed.

## Host: the commander was killed (decapitation; HotZoneOps answers it over the radio).
signal commander_down(deputy: bool)
## Host: an operation set out (counterattack, probe, reoccupy): HotZoneOps may tip the squad off.
signal operation_started(op: Dictionary)

const TICK_S := 30.0
const HUNT_RATIO := 2.0
const COUNTER_RATIO := 3.0
const CALL_OFF_RATIO := 1.5
const REOCCUPY_RATIO := 2.0
const REOCCUPY_MIN := 2
const SITE_THREAT_M := 200.0
const RALLY_M := 150.0
const ASSEMBLE_S := 120.0
const ASSEMBLED_M := 25.0
const ARRIVED_M := 30.0
const RECHECK_S := 300.0
const MAX_OPS := 2
const MAX_OPS_HIGH := 3
## Combat power of one of the squad: armoured contractors; in a working exo frame, more.
const SQUAD_MAN_CP := 1.5
const EXO_CP := 1.0
const SITE_TYPES: Array[String] = ["outpost", "checkpoint", "qrf_base", "comms", "hq", "town"]
## Fog.
const SEEN_FADE_PER_MIN := 0.1
const LOSS_WINDOW_S := 600.0
const LOSS_SHARE := 1.0 / 3.0
const LKP_FRESH_S := 600.0
const HUNT_FRESH_S := 180.0
## Reserves (men), by Pressure tier.
const RESERVE_POOL: Array[int] = [12, 16, 20, 26, 32]
const REFILL_PER_MIN: Array[float] = [0.2, 0.3, 0.4, 0.6, 0.8]
const HUNT_STOP_S := 900.0
## Probes.
const PROBE_SIZE := 2
const PROBE_GAP_S := 300.0
const PROBE_LOOK_S := 20.0
const PROBE_GIVE_UP_S := 600.0
## Seconds after a probe's contact before the commander decides again (the report's on its way).
const PROBE_DECIDE_S := 120.0
## Deception.
const NOISE_FAR_M := 150.0
const NOISE_WINDOW_S := 60.0
const NOISE_NEAR_M := 100.0
const SHOT_CP := 0.75
const BLAST_CP := 1.5
const NOISE_CP_MAX := 9.0
const SPOOF_CATCH_CHANCE := 0.25
## Memory (per zone, across deployments).
const CAUTION_FAIL := 0.15
const CAUTION_WIN := 0.1
const CAUTION_DECAPITATED := 0.3
const CAUTION_DRIFT_PER_DAY := 0.3
const CAUTION_RATIO := 0.3
const MEMORY_SECTION := &"enemy_command"
## Decapitation and friction.
const HEADLESS_S := 600.0
## A hostile HVT this close to the HQ is the commander.
const COMMANDER_HVT_M := 80.0
## His bodyguards (spawned beside him, out of the squad's sight), and how far they let him get.
const GUARD_SIZE := 2
const GUARD_CLOSE_M := 6.0
const DEPUTY_TICK_MULT := 2.0
const COMMS_TICK_MULT := 2.0
const COMMS_ASSEMBLE_MULT := 2.0
## Consolidate.
const WITHDRAW_SHARE := 0.5
const WITHDRAW_MIN_MEN := 8
const HELD_AFTER_WITHDRAW: Array[String] = ["hq", "qrf_base"]

var level: Node3D
var response: EnemyResponse
var alert: Alert
var operations: Array[Dictionary] = []
## What the hostile side knows (B1): every report that reached the net, merged and aged.
var picture := SidePicture.new(&"hostile", "insurgent")
## The hostile side's groups, live and virtual (B1; B2 tasks from it).
var board := GroupBoard.new(&"hostile")
## The squad's strength as reported (CP), before fading.
var seen_cp := 0.0
var reserves := 0.0
## "commanding", "headless", "deputy" or "leaderless".
var commander_state := "commanding"
var consolidated := false
## -1 (bold) .. 1 (cautious): what this zone's commander learned (see the header).
var caution := 0.0
var spoofs := 0
var _memory_loaded := false
var _last_contact := {}            # {"pos", "time"} of the last sighting reported
var _noise: Array[Dictionary] = []  # recent shots and blasts reported: {"pos", "time", "blast"}
var _tick := 0.0
var _last_tick := INF
var _seen_at := -INF
## Recent contact reports (the picture's log: {"pos", "reported_at", "cp", ...}); tests clear it.
var _contacts: Array[Dictionary]:
	get:
		return picture.received
var _handled := {}  # module id -> true: its loss already has an operation
var _deaths := {}   # hostile name -> when its death was noticed
var _ever := {}     # hostile name -> true: every man it has had
var _reserve_tier := -1
var _bases_start := -1
var _bases_had := -1
var _headless_until := INF
var _commander_hvt := ""  # hvt_id of the HVT who is the commander, once seen
var _guards := {}         # his bodyguard team: {"squad", "soldiers"}
var _fell_back := false   # the HQ was hit: he's left for a base (or holds at the HQ)
var _last_probe := -INF
var _probes := 0
var _teams := 0


func _init() -> void:
	name = "EnemyCommand"
	picture.max_received = 4096


func _ready() -> void:
	level = get_parent() as Node3D
	response = level.get_node_or_null(^"EnemyResponse") as EnemyResponse if level else null
	alert = level.get_node_or_null(^"Alert") as Alert if level else null
	if alert:
		alert.report_received.connect(_on_reported)


static func of(from: Node) -> EnemyCommand:
	var lvl := CompoundLevel.current(from) if from else null
	return lvl.get_node_or_null(^"EnemyCommand") as EnemyCommand if lvl else null


func now() -> float:
	return alert.now() if alert else Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = tick_s()
		server_tick()


## Seconds between decisions: slower under the deputy and with comms down.
func tick_s() -> float:
	return TICK_S * (DEPUTY_TICK_MULT if commander_state == "deputy" else 1.0) * (COMMS_TICK_MULT if _comms_down() else 1.0)


func _comms_down() -> bool:
	return alert != null and alert.comms_down


# --- The picture --------------------------------------------------------------------------------

func _on_reported(r: Dictionary) -> void:
	if r.kind == &"shot" or r.kind == &"blast":
		_on_noise(r)
		return
	if r.kind != &"contact":
		return
	_last_contact = {"pos": r.pos, "time": now()}
	var cp := float(r.get("seen", 1)) * SQUAD_MAN_CP + float(r.get("exo", 0)) * EXO_CP
	seen_cp = maxf(seen_now(), cp)
	_seen_at = now()
	picture.submit({"kind": "inf", "count": int(r.get("seen", 1)), "pos": r.pos, "by": String(r.get("by", "")), "source": "alert",
		"cp": cp, "unc0": SidePicture.base_uncertainty("seen")}, now())  # Alert already held it for the radio delay


## Loud fire reads as more men: the shots and blasts reported near this one lately.
func _on_noise(r: Dictionary) -> void:
	_noise = _noise.filter(func(n: Dictionary) -> bool: return now() - float(n.time) <= NOISE_WINDOW_S)
	_noise.append({"pos": r.pos, "time": now(), "blast": r.kind == &"blast"})
	var cp := 0.0
	for n: Dictionary in _noise:
		if (n.pos as Vector3).distance_to(r.pos) <= NOISE_NEAR_M:
			cp += BLAST_CP if n.blast else SHOT_CP
	cp = minf(cp, NOISE_CP_MAX)
	if cp > seen_now():
		seen_cp = cp
		_seen_at = now()
	picture.submit({"kind": "inf", "count": 1, "pos": r.pos, "by": String(r.get("by", "")), "source": "alert", "cp": cp, "noise": true,
		"unc0": SidePicture.base_uncertainty("noise")}, now())


## Whether `target` is only noise: no sighting reported within NOISE_FAR_M of it lately.
func unconfirmed(target: Vector3) -> bool:
	return _last_contact.is_empty() or now() - float(_last_contact.time) > LKP_FRESH_S 		or (_last_contact.pos as Vector3).distance_to(target) > NOISE_FAR_M


## Host: the squad, on a looted enemy radio (RadioChatter tuned in), calls in a fake contact
## of `men` at `pos`; the commander takes it as real. After the first, each may be caught
## (SPOOF_CATCH_CHANCE): the enemy switches frequency. True if it went in.
func server_spoof(pos: Vector3, men := 4) -> bool:
	var radio := level.get_node_or_null(^"RadioChatter") as RadioChatter if level else null
	if radio == null or not radio.tuned or alert == null:
		return false
	spoofs += 1
	if spoofs > 1 and randf() < SPOOF_CATCH_CHANCE:
		_order("all stations, that last report is false. Go to alternate.")
		radio._switch()
		_record("spoof", pos, "caught", "spoof %d caught" % spoofs)
		return false
	alert._receive({"kind": &"contact", "pos": pos, "area": alert.area_of(pos), "by": "", "seen": men, "exo": 0})
	_record("spoof", pos, "believed", "spoof %d: %d men" % [spoofs, men])
	return true


## `base` ratio as this commander applies it (memory: caution raises it, boldness lowers it).
func applied_ratio(base: float) -> float:
	return base * (1.0 + CAUTION_RATIO * caution)


func _load_memory() -> void:
	if _memory_loaded:
		return
	_memory_loaded = true
	var z: Dictionary = Campaign.section(MEMORY_SECTION).get(GameState.zone_id, {})
	var days := maxf(float(Economy.day()) - float(z.get("day", Economy.day())), 0.0)
	caution = clampf(float(z.get("caution", 0.0)) * pow(1.0 - CAUTION_DRIFT_PER_DAY, days), -1.0, 1.0)


func _learn(delta: float) -> void:
	caution = clampf(caution + delta, -1.0, 1.0)
	Campaign.section(MEMORY_SECTION)[GameState.zone_id] = {"caution": caution, "day": float(Economy.day())}
	Campaign.mark_changed(MEMORY_SECTION)


## The reported strength now, faded since the last sighting.
func seen_now() -> float:
	if _seen_at == -INF:
		return 0.0
	return seen_cp * pow(1.0 - SEEN_FADE_PER_MIN, (now() - _seen_at) / 60.0)


## Its men lost in the last LOSS_WINDOW_S.
func recent_losses() -> int:
	var count := 0
	for t: float in _deaths.values():
		if now() - t <= LOSS_WINDOW_S:
			count += 1
	return count


## What it thinks the squad's combat power is (fog): the zone's estimate, or with `at` the
## most any fresh contact report within `radius` of it saw (0 with none).
func threat_cp(at := Vector3.INF, radius := INF) -> float:
	if not at.is_finite():
		return maxf(seen_now(), recent_losses() * LOSS_SHARE)
	var best := 0.0
	for c: Dictionary in picture.received:
		if c.has("cp") and now() - float(c.reported_at) <= LKP_FRESH_S and (c.pos as Vector3).distance_to(at) <= radius:
			best = maxf(best, float(c.cp))
	return best


## The HQ asks before sending `men` out on its own errands (pairs to its sites): paid from the
## reserves; false with nobody in command, consolidating, or too little left.
func request_men(men: int, why: String) -> bool:
	var ok := men > 0 and can_decide() and not consolidated and available_cp() >= men
	if ok:
		_spend(men)
	_record("request", Vector3.INF, "approved" if ok else "denied", why)
	return ok


## The squad's real combat power within `radius` of `at` (all of it with no point): only for
## men on the spot (a task force on its objective) and tests.
func squad_cp(at := Vector3.INF, radius := INF) -> float:
	var cp := 0.0
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s.faction != &"friendly" or not s.vitals.is_up() or s.is_queued_for_deletion():
			continue
		if at.is_finite() and s.global_position.distance_to(at) > radius:
			continue
		cp += SQUAD_MAN_CP + (EXO_CP if ExoFrame.working(s.inventory) else 0.0)
	return cp


## The force it can send now: its reserves, within what the spawn budget has room for.
func available_cp() -> float:
	return minf(float(response._room()), reserves) if response else 0.0


func _spend(men: int) -> void:
	reserves = maxf(reserves - men, 0.0)


## Return an approved allocation that could not actually spawn.
func refund_men(men: int) -> void:
	reserves += maxi(men, 0)


## Pay `men` for a later wave of a hunt approve() already let go (the second QRF wave of the
## same launch): from the reserves within the spawn budget, nothing else asked (no ratio, no
## operation slot, no record, no second order on the net). False with too little left.
func reserve_men(men: int) -> bool:
	if men <= 0 or available_cp() < men:
		return false
	_spend(men)
	return true


func _active_ops() -> int:
	return operations.filter(func(o: Dictionary) -> bool:
		return o.state in ["assembling", "attacking", "approved", "moving", "looking"]).size()


func max_ops() -> int:
	return MAX_OPS_HIGH if _tier() >= 3 else MAX_OPS


func _tier() -> int:
	return clampi(response._tier() if response else 0, 0, RESERVE_POOL.size() - 1)


## Whether anyone is in command to start something new.
func can_decide() -> bool:
	return commander_state in ["commanding", "deputy"]


## The picture's tick (B1): its comms follow the mast, aged entries go; the board's sitreps.
func _step_picture() -> void:
	picture.comms_down = _comms_down()
	picture.step(now())
	var groups: Array = GroupBoard.squads_of(get_tree(), &"hostile")
	var virtualizer := Virtualizer.of(self)
	if virtualizer:
		for r: Dictionary in virtualizer.virtual_records():
			if r.get("squad") is Squad and (r.squad as Squad).faction == &"hostile" and not groups.has(r.squad):
				groups.append(r)
	board.refresh(groups, now())


# --- Reserves, losses, the commander -------------------------------------------------------------

func _bases_alive() -> int:
	return response._living_sites("qrf_base", Vector3.ZERO).size() + (1 if response._hq() else 0)


func _tick_reserves(dt: float) -> void:
	var tier := _tier()
	if _reserve_tier < 0:
		_reserve_tier = tier
		reserves = _pool(tier)
		_bases_start = maxi(_bases_alive(), 1)
		_bases_had = _bases_start
	elif tier > _reserve_tier:
		reserves += _pool(tier) - _pool(_reserve_tier)
		_reserve_tier = tier
	var bases := _bases_alive()
	if bases < _bases_had:
		reserves *= float(bases) / _bases_had  # a base lost takes its share of the pool
		_bases_had = bases
	var cap := _pool(tier) * float(bases) / _bases_start
	if reserves < cap:
		reserves = minf(reserves + REFILL_PER_MIN[tier] * dt / 60.0, cap)


## The reserve pool at Pressure tier `tier`, by the enemy's echelon now (FactionForce: 1.0 at its
## starting echelon).
func _pool(tier: int) -> float:
	return RESERVE_POOL[tier] * FactionForce.size_mult(String(response.enemy_faction) if response else "")


func _count_losses() -> void:
	var ai := level.get(&"ai") as Node
	if ai == null:
		return
	for n in ai.get_children():
		var s := n as Soldier
		if s == null or s.faction != &"hostile":
			continue
		_ever[String(s.name)] = true
		if (s.vitals.is_dead() or s.is_in_group(Soldier.DEAD_GROUP)) and not _deaths.has(String(s.name)):
			_deaths[String(s.name)] = now()
	var virtualizer := Virtualizer.of(self)
	if virtualizer:
		for p: Dictionary in virtualizer.profiles():
			if String(p.side) != "hostile":
				continue
			for m: Dictionary in p.members:
				_ever[String(m.name)] = true  # its men are out there, as a profile
		for who: String in virtualizer.deaths:
			_ever[who] = true
			if not _deaths.has(who):
				_deaths[who] = now()  # killed off-screen


## The commander's name (the HQ's officer post 0), "" with no HQ: what a decapitation contract
## would target.
func commander_name(post := 0) -> String:
	if post == 0 and _find_commander_hvt():
		var layer := PeopleLayer.find(self)
		var s := layer.hvt(_commander_hvt) if layer else null
		if s:
			return String(s.name)
	var hq := _hq_module()
	return ("%s_H%d" % [hq.module_id, post + 1]).validate_node_name() if hq else ""


func _hq_module() -> ZoneModule:
	for m: ZoneModule in level.call(&"modules"):
		if m.type == "hq":
			return m
	return null


## Whether there's an HVT commander (a hostile HVT seen at the HQ; remembered once seen).
func _find_commander_hvt() -> bool:
	if _commander_hvt != "":
		return true
	var hq := _hq_module()
	var layer := PeopleLayer.find(self)
	if hq == null or layer == null:
		return false
	for s: Soldier in layer.people():
		if Person.is_hvt(s) and String(Person.state(s).get("side", "")) == Person.HOSTILE and s.global_position.distance_to(hq.global_position) <= COMMANDER_HVT_M:
			_commander_hvt = String(Person.state(s).get("hvt_id", ""))
			return _commander_hvt != ""
	return false


## PeopleLayer knows this identity at spawn, before the first command tick or a death.
func register_commander(hvt_id: String) -> void:
	if _commander_hvt == "" and hvt_id != "":
		_commander_hvt = hvt_id


## The HVT commander's guards and fallback (see the header).
func _tend_commander() -> void:
	if not _find_commander_hvt() or not can_decide():
		return
	var layer := PeopleLayer.find(self)
	var hvt := layer.hvt(_commander_hvt) if layer else null
	var hq := _hq_module()
	if hvt == null or hvt.vitals.is_dead() or Person.is_captive(hvt) or hq == null:
		return
	if _guards.is_empty():
		if not response._unseen(hvt.global_position) or available_cp() < GUARD_SIZE:
			return  # not where the squad would see them pop in
		var beside := hvt.global_position + hvt.global_transform.basis.x * 2.0
		_guards = _send_team("BG", GUARD_SIZE, beside, hvt.global_position)
		_record("bodyguard", hvt.global_position, "done", "%d guard the commander" % (_guards.soldiers as Array).size())
	var guards: Array = response._living(_guards.soldiers)
	if not _fell_back and (threat_cp(hq.global_position, SITE_THREAT_M) > 0.0 or (alert and alert.state_of(hq.module_id) >= Alert.State.ENGAGED)):
		_fell_back = true
		var bases := response._living_sites("qrf_base", hq.global_position)
		if not bases.is_empty() and not guards.is_empty():
			var to := response._ground(bases[0].global_position)
			var route: Array[Vector3] = [to]
			response._set_route(_guards.squad, guards, route)
			_record("fallback", to, "done", "the commander falls back on %s" % bases[0].module_id)
			_order("this is Command, we're relocating to %s. Hold them off." % _callsign(bases[0]))
		else:
			_record("fallback", hq.global_position, "done", "the commander holds at the HQ")
			_order("this is Command, we're holding here. All units, to me.")
		_launch_counterattack(hq, maxf(threat_cp(hq.global_position, SITE_THREAT_M), SQUAD_MAN_CP), applied_ratio(COUNTER_RATIO), "relief of the HQ", false)
	elif not _fell_back and not guards.is_empty() and (guards[0] as Soldier).global_position.distance_to(hvt.global_position) > GUARD_CLOSE_M:
		var route: Array[Vector3] = [response._ground(hvt.global_position)]
		response._set_route(_guards.squad, guards, route)


## Whether officer post `post` of the HQ is dead (spawned and down, or fallen on an earlier
## visit). Post 0 with an HVT commander: whether he's captured, delivered or dead.
func _officer_down(post: int) -> bool:
	if post == 0 and _find_commander_hvt():
		var layer := PeopleLayer.find(self)
		var hvt := layer.hvt(_commander_hvt) if layer else null
		return hvt == null or hvt.vitals.is_dead() or Person.is_captive(hvt) or bool(Person.state(hvt).get("delivered", false)) or People.is_delivered(_commander_hvt)
	var hq := _hq_module()
	var ai := level.get(&"ai") as Node
	if hq == null or ai == null:
		return false
	var s := ai.get_node_or_null(NodePath(commander_name(post))) as Soldier
	if s:
		return s.vitals.is_dead() or s.is_in_group(Soldier.DEAD_GROUP)
	var virtualizer := Virtualizer.of(self)
	if virtualizer and not virtualizer.member(commander_name(post)).is_empty():
		return false  # at his post with the HQ's garrison, as a profile
	var had := level.get(&"_garrisoned") as Dictionary
	return had != null and int(had.get(hq.module_id, 0)) > post and int(level.call(&"garrison_pending", hq.module_id)) == 0


func _watch_command() -> void:
	match commander_state:
		"commanding":
			if _officer_down(0):
				commander_state = "headless"
				_headless_until = now() + HEADLESS_S
				_record("decapitated", Vector3.INF, "headless", "the commander is down")
				_learn(CAUTION_DECAPITATED)
				_order("Command, respond. Command, come in.", _callsign_at(Vector3.ZERO, true), true)
				commander_down.emit(false)
		"headless":
			if now() >= _headless_until:
				if _officer_down(1):
					commander_state = "leaderless"
					_record("decapitated", Vector3.INF, "leaderless", "the deputy is down too")
				else:
					commander_state = "deputy"
					_record("deputy", Vector3.INF, "commanding", "the deputy takes command")
					_order("all stations, this is the deputy. I have command. Hold your positions.")
		"deputy":
			if _officer_down(1):
				commander_state = "leaderless"
				_record("decapitated", Vector3.INF, "leaderless", "the deputy is down")
				commander_down.emit(true)


# --- Decisions --------------------------------------------------------------------------------

## EnemyResponse asks before a hunt (`kind` "qrf" or "hunters") toward `target`: true to go,
## `men` paid from the reserves and one operation recorded. Asked once per launch (a two-wave
## QRF pays its second wave with reserve_men), and asked even when the reserves are short of a
## team (`men` the team it wanted): the denial is recorded and a stale LKP still gets its probe.
func approve(kind: String, target: Vector3, men: int) -> bool:
	var threat := maxf(threat_cp(), 1.0)
	var have := available_cp()
	var why := "%.0f CP against %.1f (%.1f:1)" % [have, threat, have / threat]
	if have < men:
		why = "%d men wanted, %.0f to hand" % [men, have]
	var ok := men > 0 and have >= men and have >= threat * applied_ratio(HUNT_RATIO) and _active_ops() < max_ops()
	if not can_decide():
		ok = false
		why = "no commander"
	elif consolidated:
		ok = false
		why = "consolidating"
	elif kind == "hunters" and alert and (alert.lkp.is_empty() or now() - float(alert.lkp.time) > HUNT_FRESH_S):
		ok = false
		why = "LKP stale: a probe instead"
		_maybe_probe()
	elif unconfirmed(target):
		ok = false
		why = "unconfirmed noise: a probe first"
		if now() - _last_probe >= PROBE_GAP_S:
			_send_probe(target)
	_record("hunt:" + kind, target, "approved" if ok else "denied", why)
	if ok:
		_spend(men)
		_order("%s, move out %s side. Find them." % [_callsign_at(target, true), RadioChatter.compass(Vector3.ZERO, target)])
	else:
		print("[command] %s turned down: %s" % [kind, why])
	return ok


func server_tick() -> void:
	if not multiplayer.is_server() or level == null or response == null:
		return
	var dt := now() - _last_tick if _last_tick != INF else 0.0
	_last_tick = now()
	_load_memory()
	_step_picture()
	_tick_reserves(maxf(dt, 0.0))
	_count_losses()
	_watch_command()
	_tend_commander()
	for op: Dictionary in operations:
		if op.state == "approved" and now() - float(op.at) > 60.0:
			op.state = "done"  # a hunt is EnemyResponse's from here on
	_stop_hunts()
	if can_decide():
		_check_consolidate()
		_watch_sites()
		if not consolidated:
			_maybe_probe()
	for op: Dictionary in operations.duplicate():
		match String(op.kind):
			"counterattack", "reoccupy":
				_step_task_force(op)
			"probe":
				_step_probe(op)
			"contain":
				if op.state == "containing" and now() >= float(op.recheck_at) and can_decide():
					op.state = "rechecked"
					_handled.erase(op.target_id)  # looked at again next tick: maybe retaken now


## Sites with a garrison that have fallen: each gets one operation.
func _watch_sites() -> void:
	var had := level.get(&"_garrisoned") as Dictionary
	if had == null:
		return
	for m: ZoneModule in level.call(&"modules"):
		if not (ZoneModules.base(m.type) in SITE_TYPES) or int(had.get(m.module_id, 0)) <= 0 or _handled.has(m.module_id):
			continue
		if level.call(&"site_down", m.module_id):
			_handled[m.module_id] = true
			_decide_lost(m)


## Site `m` is down: counterattack (it thinks the squad's there), probe (it thinks nobody is) or
## contain. `probed`: a probe already had contact there (nobody seen yet still means contain).
func _decide_lost(m: ZoneModule, probed := false) -> void:
	var threat := threat_cp(m.global_position, SITE_THREAT_M)
	if consolidated and not (m.type in HELD_AFTER_WITHDRAW):
		_contain(m, "%s written off (consolidating)" % m.module_id, false)
		return
	if threat <= 0.0 and probed:
		_contain(m, "%s: the probe met someone, nothing reported" % m.module_id)
		return
	if threat <= 0.0:
		if not _send_probe(m.global_position, m.module_id):
			_contain(m, "%s lost, nobody seen there, no probe to send" % m.module_id, false)
		return
	# a probe met fewer than it thinks the squad is: someone left on the site, retaken at 2:1
	var r := REOCCUPY_RATIO if probed and threat_cp() > threat else COUNTER_RATIO
	_launch_counterattack(m, threat, applied_ratio(r), "%s lost" % m.module_id)


## A counterattack on site `m` at `ratio` of `threat` (assembling out of sight), or Contain
## when it can't field it. Also the HQ's relief when the commander calls for help.
func _launch_counterattack(m: ZoneModule, threat: float, ratio: float, what: String, contain := true) -> void:
	var need := ceili(threat * ratio)
	var have := available_cp()
	var base := _nearest_base(m.global_position)
	if base == m:
		var others := response._living_sites("qrf_base", m.global_position).filter(func(b: ZoneModule) -> bool: return b != m)
		base = others[0] if not others.is_empty() else null
	var why := "%s: %.0f CP against %.1f there (needs %d at %.0f:1)" % [what, have, threat, need, ratio]
	if base == null or have < need or _active_ops() >= max_ops():
		if contain:
			_contain(m, why + (", no base" if base == null else ""))
		else:
			_record("relief", m.global_position, "denied", why)
		return
	var gate := response._unseen_gate(base, m.global_position)
	if not gate.is_finite():
		if contain:
			_contain(m, why + ", every gate watched")
		return
	var rally := response._ground(m.global_position.move_toward(gate, RALLY_M))
	var team := _send_team("CA_%s" % m.module_id, need, gate, rally)
	operations.append({"kind": "counterattack", "target": m.global_position, "target_id": m.module_id, "state": "assembling",
		"why": why, "at": now(), "rally": rally, "base": base.module_id, "squad": team.squad, "soldiers": team.soldiers,
		"threat": threat})
	_virtualize(operations.back(), "task_force")
	operation_started.emit(operations.back())
	print("[command] counterattack %s: %d men assembling at (%.0f, %.0f)" % [m.module_id, team.soldiers.size(), rally.x, rally.z])
	_order("%s, assemble %s of %s. We take it back together." % [_callsign(base), RadioChatter.compass(m.global_position, rally),
		_callsign(m)])


func _contain(m: ZoneModule, why: String, say := true) -> void:
	_record("contain", m.global_position, "containing", why, {"target_id": m.module_id, "recheck_at": now() + RECHECK_S})
	print("[command] contain %s" % why)
	if say:
		_order("%s is lost. Do not engage. Hold your positions." % _callsign(m))


## `size` men from `gate` toward `to` (spawn budget and reserves paid): {"squad", "soldiers"}.
func _send_team(callsign: String, size: int, gate: Vector3, to: Vector3) -> Dictionary:
	size = mini(size, floori(available_cp()))
	_teams += 1
	var cs := ("%s_%d" % [callsign, _teams]).validate_node_name()
	var squad := response._new_squad(cs)
	var route: Array[Vector3] = [to]
	squad.patrol = route
	var soldiers := response._spawn_team(squad, cs, size, gate, to, CompoundLevel.HOSTILE_LOADOUT,
		EnemyResponse.HUNTER_COMBAT, EnemyResponse.HUNTER_DISCIPLINE * response.coordination(), "combat")
	_spend(soldiers.size())
	return {"squad": squad, "soldiers": soldiers}


## Counterattacks and reoccupations: assemble (counterattacks), go in, hold the site.
func _step_task_force(op: Dictionary) -> void:
	if op.state in ["done", "failed", "called off"]:
		return
	var living: Array = response._living(op.soldiers)
	var at: Array[Vector3] = Virtualizer.points(op)  # where its men are, live or virtual
	if at.is_empty():
		op.state = "failed"
		op.why = "task force lost"
		_handled.erase(op.target_id)  # still down: decided again
		_learn(CAUTION_FAIL)
		return
	if op.state == "assembling":
		if not can_decide():
			return  # nobody to give the word: they hold at the rally point
		var wait := ASSEMBLE_S / maxf(response.coordination(), 0.2) * (COMMS_ASSEMBLE_MULT if _comms_down() else 1.0)
		var there := at.all(func(p: Vector3) -> bool: return p.distance_to(op.rally) <= ASSEMBLED_M)
		if there or now() - float(op.at) >= wait:
			op.state = "attacking"
			op.attack_at = now()
			var route: Array[Vector3] = [response._ground(op.target)]
			response._set_route(op.squad, living, route)
			_order("all units, move on %s. Go, go." % _callsign(level.call(&"get_module", op.target_id)))
		return
	var threat := maxf(threat_cp(op.target, SITE_THREAT_M), squad_cp(op.target, ARRIVED_M))
	if op.kind == "counterattack" and threat > 0.0 and at.size() < threat * CALL_OFF_RATIO:
		op.state = "called off"
		op.why = "%d left against %.1f" % [at.size(), threat]
		_send_home(op.squad, living, op.get("base", ""), op.rally)
		_handled.erase(op.target_id)
		_learn(CAUTION_FAIL)
		_order("pull back, pull back. Break contact.")
		return
	if squad_cp(op.target, SITE_THREAT_M) <= 0.0 and at.any(func(p: Vector3) -> bool: return p.distance_to(op.target) <= ARRIVED_M):
		op.state = "done"
		op.why = "retaken" if op.kind == "counterattack" else "reoccupied"
		for s: Soldier in living:
			s.set_meta(&"garrison_of", op.target_id)  # the site's garrison again (ZoneLevel.garrison_alive)
		for m: Dictionary in Virtualizer.virtual_men(op):
			var meta: Dictionary = m.get("meta", {})
			meta["garrison_of"] = op.target_id  # (a virtual one's too)
			m["meta"] = meta
		_handled.erase(op.target_id)
		_learn(-CAUTION_WIN)
		_order("%s is ours. Hold it." % _callsign(level.call(&"get_module", op.target_id)))


## Probe: PROBE_SIZE men to `target` (a stale LKP, or lost site `site_id`). False if it can't.
func _send_probe(target: Vector3, site_id := "") -> bool:
	if available_cp() < PROBE_SIZE or _active_ops() >= max_ops():
		return false
	var base := _nearest_base(target)
	if base == null:
		return false
	var gate := response._unseen_gate(base, target)
	if not gate.is_finite():
		return false
	_probes += 1
	_last_probe = now()
	var team := _send_team("PR%d" % _probes, PROBE_SIZE, gate, response._ground(target))
	operations.append({"kind": "probe", "target": target, "target_id": site_id, "state": "moving", "at": now(),
		"base": base.module_id, "squad": team.squad, "soldiers": team.soldiers})
	_virtualize(operations.back(), "probe")
	print("[command] probe %d toward (%.0f, %.0f)%s" % [_probes, target.x, target.z, (" (" + site_id + ")") if site_id != "" else ""])
	_order("%s, send a patrol %s and report." % [_callsign(base), RadioChatter.compass(base.global_position, target)])
	return true


## A probe toward a stale LKP, when the zone is up and none went lately.
func _maybe_probe() -> void:
	if alert == null or alert.zone_state < Alert.State.ALERTED or now() - _last_probe < PROBE_GAP_S:
		return
	var lk := alert.lkp
	if lk.is_empty() or now() - float(lk.time) <= HUNT_FRESH_S:
		return
	for op: Dictionary in operations:
		if op.kind == "probe" and op.target_id == "" and op.state in ["moving", "looking"]:
			return
	_send_probe(lk.pos)


func _step_probe(op: Dictionary) -> void:
	if op.state == "done" or op.state == "failed":
		return
	var site := level.call(&"get_module", op.target_id) as ZoneModule if op.target_id != "" else null
	var living: Array = response._living(op.soldiers)
	var at: Array[Vector3] = Virtualizer.points(op)  # where its men are, live or virtual
	if at.is_empty():
		op.state = "failed"
		op.why = "probe lost"
		if site:
			_contain(site, "%s: the probe didn't come back" % site.module_id)
		return
	var contact := living.any(func(s: Soldier) -> bool:
		var brain := SquadAI.of(s)
		return brain != null and brain.in_contact())
	if op.state in ["moving", "looking"] and contact:
		op.state = "returning"
		op.why = "contact"
		op.decide_at = now() + PROBE_DECIDE_S
		_send_home(op.squad, living, op.base, op.target)
		return
	match String(op.state):
		"moving":
			if at.any(func(p: Vector3) -> bool: return p.distance_to(op.target) <= ARRIVED_M):
				op.state = "looking"
				op.look_until = now() + PROBE_LOOK_S
			elif now() - float(op.at) > PROBE_GIVE_UP_S:
				op.state = "returning"
				op.why = "never got there"
				_send_home(op.squad, living, op.base, op.target)
		"looking":
			if now() < float(op.look_until):
				return
			if _comms_down():
				op.state = "done"
				op.why = "no report (comms down)"
				if site:
					_contain(site, "%s: no word from the probe" % site.module_id, false)
			elif site:
				op.state = "done"
				op.why = "all clear"
				_reoccupy(site, living, op.squad)
			else:
				op.state = "returning"
				op.why = "nothing there"
				_send_home(op.squad, living, op.base, op.target)
		"returning":
			if site and not op.get("decided", false) and now() >= float(op.get("decide_at", INF)):
				op.decided = true
				if can_decide() and level.call(&"site_down", site.module_id):
					_decide_lost(site, true)  # the contact report is in by now: counterattack or contain
			if now() - float(op.at) > PROBE_GIVE_UP_S * 2.0:
				op.state = "done"


## A clear site: the probe stays, REOCCUPY_MIN men in all hold it again.
func _reoccupy(m: ZoneModule, probe: Array, probe_squad: Squad) -> void:
	var need := maxi(REOCCUPY_MIN - probe.size(), 0)
	var soldiers: Array = probe.duplicate()
	var squad := probe_squad
	if need > 0:
		var base := _nearest_base(m.global_position)
		var gate := response._unseen_gate(base, m.global_position) if base else Vector3.INF
		if gate.is_finite() and available_cp() >= need:
			var team := _send_team("RO_%s" % m.module_id, need, gate, response._ground(m.global_position))
			soldiers.append_array(team.soldiers)
	operations.append({"kind": "reoccupy", "target": m.global_position, "target_id": m.module_id, "state": "moving",
		"why": "all clear", "at": now(), "squad": squad, "soldiers": soldiers})
	_virtualize(operations.back(), "task_force")
	print("[command] reoccupy %s with %d" % [m.module_id, soldiers.size()])
	_order("%s, reoccupy and hold." % _callsign(m))


## Hunter teams out HUNT_STOP_S go home (headless or not: their orders had a stop).
func _stop_hunts() -> void:
	for record: Dictionary in response.hunters:
		if record.get("recalled", false) or now() - float(record.at) < HUNT_STOP_S:
			continue
		record.recalled = true
		if Virtualizer.up(record) > 0:
			_send_home(record.squad, response._living(record.soldiers), "", Virtualizer.lead(record))
			_order("hunters, break off. Return to base.")


## Past WITHDRAW_SHARE lost: everyone out falls back on the HQ and QRF bases.
func _check_consolidate() -> void:
	if consolidated or _ever.size() < WITHDRAW_MIN_MEN or float(_deaths.size()) / _ever.size() < WITHDRAW_SHARE:
		return
	consolidated = true
	_record("consolidate", Vector3.INF, "done", "%d of %d lost" % [_deaths.size(), _ever.size()])
	for record: Dictionary in response.hunters:
		if Virtualizer.up(record) > 0:
			_send_home(record.squad, response._living(record.soldiers), "", Virtualizer.lead(record))
	if response.reinforcements:
		for w: Dictionary in response.reinforcements.waves:
			var squad := w.get("squad") as Squad
			if squad and Virtualizer.up(w) > 0:
				_send_home(squad, response._living(w.soldiers), "", Virtualizer.lead(w))
	for op: Dictionary in operations:
		if op.kind in ["counterattack", "probe"] and op.state in ["assembling", "attacking", "moving", "looking"]:
			var target_site := level.call(&"get_module", op.target_id) as ZoneModule if op.target_id != "" else null
			if target_site and target_site.type in HELD_AFTER_WITHDRAW:
				continue
			op.state = "called off"
			op.why = "consolidating"
			_send_home(op.squad, response._living(op.soldiers), op.get("base", ""), op.target)
	_abandon_outposts()
	_order("all stations, fall back on %s. Hold the bases." % RadioChatter.NET_CALLSIGN)


## Consolidating: every outpost and checkpoint garrison still up walks to the nearest base.
func _abandon_outposts() -> void:
	var ai := level.get(&"ai") as Node
	if ai == null:
		return
	for m: ZoneModule in level.call(&"modules"):
		if ZoneModules.base(m.type) in HELD_AFTER_WITHDRAW or not (ZoneModules.base(m.type) in SITE_TYPES):
			continue
		var prefix := ("%s_H" % m.module_id).validate_node_name()
		var leaving: Array = []
		for n in ai.get_children():
			var s := n as Soldier
			if s and s.faction == &"hostile" and s.vitals.is_up() and not s.is_in_group(Soldier.DEAD_GROUP) 					and (String(s.name).begins_with(prefix) or String(s.get_meta(&"garrison_of", "")) == m.module_id):
				leaving.append(s)
		var virtualizer := Virtualizer.of(self)
		var virtual_garrison := virtualizer != null and virtualizer.has_garrison(m.module_id)
		if leaving.is_empty() and not virtual_garrison:
			continue
		var base := _nearest_base(m.global_position)
		if base == null:
			return
		_teams += 1
		var squad := response._new_squad(("WD_%s_%d" % [m.module_id, _teams]).validate_node_name())
		for s: Soldier in leaving:
			s.set_meta(&"left_post", true)
			s.remove_meta(&"garrison_of")
			var brain := SquadAI.of(s)
			if brain:
				brain.guard = false
				brain.squad = squad
		var gone := leaving.size()
		if virtual_garrison:
			gone += Virtualizer.virtual_men(virtualizer.server_detach_garrison(m.module_id, squad)).size()  # at its posts as a profile: it walks off as one
		_send_home(squad, leaving, base.module_id, m.global_position)
		_record("abandon", m.global_position, "done", "%s: %d fall back on %s" % [m.module_id, gone, base.module_id],
			{"target_id": m.module_id})
		_handled[m.module_id] = true  # written off: no op when it reads as down


## Sends `living` of `squad` back to base `base_id` (else the nearest base to `from`).
func _send_home(squad: Squad, living: Array, base_id: String, from: Vector3) -> void:
	if squad == null or not from.is_finite():
		return  # (`living` may be empty: a virtual group walks its squad's route too)
	var home: ZoneModule = level.call(&"get_module", base_id) as ZoneModule if base_id != "" else null
	if home == null or level.call(&"site_down", home.module_id):
		home = _nearest_base(from)
	if home == null:
		return
	var route: Array[Vector3] = [response._ground(home.global_position)]
	response._set_route(squad, living, route)


## Host: `record` (a task force, a probe) may go virtual far from the squad (Virtualizer.track).
func _virtualize(record: Dictionary, kind: String) -> void:
	var virtualizer := Virtualizer.of(self)
	if virtualizer:
		virtualizer.track(record, kind)


func _nearest_base(pos: Vector3) -> ZoneModule:
	var bases := response._living_sites("qrf_base", pos)
	if not bases.is_empty():
		return bases[0]
	return response._hq()


func _record(kind: String, target: Vector3, state: String, why: String, extra := {}) -> void:
	var op := {"kind": kind, "target": target, "state": state, "why": why, "at": now()}
	op.merge(extra)
	operations.append(op)


# --- The net ------------------------------------------------------------------------------------

## The order goes out on the enemy net (a looted radio hears it). Nobody gives orders headless
## unless `always` (the net calling for its commander).
func _order(text: String, speaker := RadioChatter.NET_CALLSIGN, always := false) -> void:
	if not always and not can_decide():
		return
	var radio := level.get_node_or_null(^"RadioChatter") as RadioChatter if level else null
	if radio:
		radio.order(text, speaker)


func _callsign(m: ZoneModule) -> String:
	if m == null:
		return "that position"
	var radio := level.get_node_or_null(^"RadioChatter") as RadioChatter
	return radio._callsign(m.module_id) if radio else m.module_id


func _callsign_at(pos: Vector3, qrf := false) -> String:
	var radio := level.get_node_or_null(^"RadioChatter") as RadioChatter
	return radio._callsign_at(pos, qrf) if radio else RadioChatter.NET_CALLSIGN
