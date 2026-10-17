class_name HotZoneOps
extends Node
## A hot zone as one deployment of several contracts (Captain 2026-10-15: "flesh out HZs too,
## remember multiple missions per and our design"; design doc "Missions: contract zones and hot
## zones"). What it adds on top of Alert, Pressure, EnemyResponse and RadioChatter:
##
## - Several contracts live at once: a hot zone keeps LIVE_RANGE (3-6) of its faction's
##   contracts live. Contracts.server_start_deployment tops the squad's own up on arrival
##   (live_target), each at a site no other holds; they're taken in any order.
## - Radio follow-ups: what the squad does draws new contracts over the radio, reacting to it
##   ("you hit their QRF, now hit the HQ"). A site taken out (ZoneLevel.site_down; the comms
##   site once its mast is down, Alert.comms_down) or a contract done queues a follow-up
##   (FOLLOW_UPS: which sites it goes to, the types it prefers and the employer's words) that
##   comes in FOLLOW_UP_DELAY_S later, at the nearest live site of those types no other
##   contract holds, at most MAX_FOLLOW_UPS a deployment and FOLLOW_UP_GAP_S apart. It needs
##   a field radio in the squad (Contracts.radio_contract_problem): without one it waits.
##   The enemy's commander killed (EnemyCommand.commander_down) sets one off too ("commander").
## - Hazard pay: staying longer pays more (Captain). The highest Pressure tier reached is
##   noted on the deployment ("hazard_tier") and every contract completed there pays
##   HAZARD_SHARE_PER_TIER of its pay per tier on top (DebriefCalc).
## Unfinished contracts lapse at extraction with "rep_lapse" (DebriefCalc). Host only; one node
## per hot zone ("HotZoneOps", ZoneLevel); runs on the Alert's clock (tests jump it with
## Alert.advance and then server_tick). All numbers Proposed; each can be overridden in
## data/contracts.json "settings" under the same name in lower case.

## Host: a follow-up contract came in over the radio: {"cid", "trigger", "from", "site", "time"}.
signal follow_up(entry: Dictionary)

const LIVE_RANGE := Vector2i(3, 6)
const FOLLOW_UP_DELAY_S := 90.0
const FOLLOW_UP_GAP_S := 120.0
const MAX_FOLLOW_UPS := 4
const HAZARD_SHARE_PER_TIER := 0.05
const SCAN_S := 2.0
## What sets off a follow-up (a site type taken out, or "contract": one done), where it goes
## (site types, best first) and what it prefers to be (contract types; any that plays at the
## site when none of these does: the newer types plug in by themselves). "%s" in the line is
## the target site's name.
const FOLLOW_UPS := {
	"qrf_base": {"sites": ["hq", "outpost"], "types": ["raid"],
		"line": "You hit their QRF. Nobody's coming to help the %s now: hit it."},
	"comms": {"sites": ["hq", "outpost"], "types": ["intel_grab", "hvt_capture"],
		"line": "Their net is down. Get into the %s and take what they can't radio out."},
	"outpost": {"sites": ["qrf_base", "comms", "outpost"], "types": ["raid", "intel_grab"],
		"line": "That outpost was their eyes. Hit the %s before it moves on you."},
	"checkpoint": {"sites": ["outpost", "comms"], "types": ["intel_grab", "raid"],
		"line": "The road's open. The %s past it holds their plans: take them."},
	"hq": {"sites": ["qrf_base", "outpost", "comms"], "types": ["raid"],
		"line": "Their command is gone. Clear the %s before they regroup."},
	"commander": {"sites": ["qrf_base", "outpost", "comms"], "types": ["raid"],
		"line": "Their commander's dead and they're blind for a while. Hit the %s before his deputy gets a grip."},
	"contract": {"sites": ["outpost", "comms", "qrf_base", "checkpoint", "hq"], "types": [],
		"line": "Good work. While you're in there: the %s."},
}

## Tests: false turns off the arrival top-up and the radio follow-ups (suites testing one
## contract at a time in a hot zone).
static var enabled := true

var level: Node3D
var alert: Alert
var pressure: Pressure
## Every follow-up that came in this deployment (follow_up's entries).
var follow_ups: Array[Dictionary] = []
## Waiting: {"trigger", "from" (module id), "pos", "due"}.
var queue: Array[Dictionary] = []
var _seen := {}        # module id or "cid:<cid>" -> true: already set one off
var _last_follow := -INF
var _scan := 0.0
var _command: EnemyCommand


func _init() -> void:
	name = "HotZoneOps"


func _ready() -> void:
	level = get_parent() as Node3D
	alert = level.get_node_or_null(^"Alert") as Alert if level else null
	pressure = level.get_node_or_null(^"Pressure") as Pressure if level else null
	if pressure:
		pressure.tier_changed.connect(_on_tier_changed)
	Contracts.deployment_started.connect(_on_deployment_started)


func _exit_tree() -> void:
	if Contracts.deployment_started.is_connected(_on_deployment_started):
		Contracts.deployment_started.disconnect(_on_deployment_started)


## The hot zone ops of the level `from` is in (null outside a hot zone).
static func of(from: Node) -> HotZoneOps:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(^"HotZoneOps") as HotZoneOps if lvl else null


func now() -> float:
	return alert.now() if alert else Soldier._now()


static func _knob(key: String, fallback: Variant) -> Variant:
	return MissionRegistry.setting(key.to_lower(), fallback)


## How many contracts a hot zone keeps live once the squad arrives with `held` of its own: as
## many as it took when that's LIVE_RANGE.x or more, else a roll in LIVE_RANGE (the same for
## the same campaign, day and zone).
static func live_target(campaign_seed: int, day: int, zone_id: String, held: int) -> int:
	var r: Variant = _knob("hot_zone_live", [LIVE_RANGE.x, LIVE_RANGE.y])
	var lo := int(r[0]) if r is Array else LIVE_RANGE.x
	var hi := int(r[1]) if r is Array else LIVE_RANGE.y
	if held >= lo or not enabled:
		return held
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([campaign_seed, day, zone_id, "live"])
	return rng.randi_range(lo, hi)


## The share of a completed contract's pay added as hazard pay at pressure tier `tier`.
static func hazard_share(tier: int) -> float:
	return float(_knob("hazard_pay_per_tier", HAZARD_SHARE_PER_TIER)) * maxi(tier, 0)


## The module type of `module_id` in zone `zone_id`'s layout ("" if it has none).
static func module_type(zone_id: String, module_id: String) -> String:
	for m: Dictionary in MissionRegistry.zone_def(zone_id).get("modules", []):
		if String(m.get("id", "")) == module_id:
			return String(m.type)
	return ""


# --- The clock (host) ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_S
		server_tick()


## Host: looks for sites taken out and contracts done, and sends what's due. Every SCAN_S.
func server_tick() -> void:
	if not multiplayer.is_server() or not enabled or not _deployed_here():
		return
	_hook_command()
	_watch_sites()
	_watch_contracts()
	_send_due()


## EnemyCommand comes in after this node (ZoneLevel): hooked on the first tick.
func _hook_command() -> void:
	if _command and is_instance_valid(_command):
		return
	_command = level.get_node_or_null(^"EnemyCommand") as EnemyCommand if level else null
	if _command and not _command.commander_down.is_connected(_on_commander_down):
		_command.commander_down.connect(_on_commander_down)


func _on_commander_down(deputy: bool) -> void:
	if deputy or _seen.has("commander"):
		return
	_seen["commander"] = true
	var hq := _command._hq_module()
	_queue("commander", hq.module_id if hq else "", hq.global_position if hq else Vector3.ZERO)


func _deployed_here() -> bool:
	var dep := Contracts.deployment()
	return not dep.is_empty() and String(dep.get("zone_kind", "")) == "hot"


func _watch_sites() -> void:
	if level == null or not level.has_method(&"modules"):
		return
	for m: ZoneModule in level.call(&"modules"):
		var type := ZoneModules.base(m.type)
		if not FOLLOW_UPS.has(type) or _seen.has(m.module_id) or not taken_out(m):
			continue
		_seen[m.module_id] = true
		_queue(type, m.module_id, m.global_position)


## Whether site `m` is taken out: its garrison gone (ZoneLevel.site_down) or, for the comms
## site, its mast (Alert.comms_down).
func taken_out(m: ZoneModule) -> bool:
	if ZoneModules.base(m.type) == "comms" and alert and alert.comms_down:
		return true
	return level.has_method(&"site_down") and bool(level.call(&"site_down", m.module_id))


func _watch_contracts() -> void:
	for cid: String in Contracts.deployment().get("cids", []):
		if _seen.has("cid:" + cid) or not Contracts.objectives.contract_done(cid):
			continue
		_seen["cid:" + cid] = true
		var c := Contracts.contract(cid)
		var at := String(c.get("module_id", ""))
		if at != "" and _seen.has(at):
			continue  # its site already set one off
		if at != "":
			_seen[at] = true
		var m := level.call(&"get_module", at) as ZoneModule if at != "" and level.has_method(&"get_module") else null
		_queue("contract", at, m.global_position if m else Vector3.ZERO)


func _queue(trigger: String, from: String, pos: Vector3) -> void:
	queue.append({"trigger": trigger, "from": from, "pos": pos,
		"due": now() + float(_knob("follow_up_delay_s", FOLLOW_UP_DELAY_S))})


func _send_due() -> void:
	if queue.is_empty():
		return
	if follow_ups.size() >= int(_knob("max_follow_ups", MAX_FOLLOW_UPS)):
		queue.clear()
		return
	var q: Dictionary = queue[0]
	if now() < float(q.due) or now() - _last_follow < float(_knob("follow_up_gap_s", FOLLOW_UP_GAP_S)):
		return
	if Contracts.radio_contract_problem() != "":
		return  # the employer can't reach the squad: it waits for a field radio
	queue.pop_front()
	var rule: Dictionary = FOLLOW_UPS[q.trigger]
	var site := target_site(rule.sites, q.pos)
	if site == null:
		return
	var type := ""
	var at := ZoneModules.base(site.type)
	for t: String in rule.types:
		if at in MissionRegistry.type_modules(MissionRegistry.type_def(t)):
			type = t
			break
	var name := MissionRegistry.module_name(at)
	var cid := Contracts.server_radio_contract(type, site.module_id, String(rule.line) % name)
	if cid == "":
		return
	_last_follow = now()
	var entry := {"cid": cid, "trigger": q.trigger, "from": q.from, "site": site.module_id, "time": now()}
	follow_ups.append(entry)
	follow_up.emit(entry)


## The nearest site to `pos` of the first of `types` that has one still standing and held by
## no live contract; null when there's none.
func target_site(types: Array, pos: Vector3) -> ZoneModule:
	if level == null or not level.has_method(&"modules"):
		return null
	var held := Contracts.live_sites()
	for t: String in types:
		var best: ZoneModule = null
		for m: ZoneModule in level.call(&"modules"):
			if ZoneModules.base(m.type) != t or m.module_id in held or _seen.has(m.module_id) or taken_out(m):
				continue
			if best == null or m.global_position.distance_to(pos) < best.global_position.distance_to(pos):
				best = m
		if best:
			return best
	return null


# --- Hazard pay ---------------------------------------------------------------------------------

func _on_tier_changed(tier: int) -> void:
	if multiplayer.is_server() and _deployed_here() and tier > int(Contracts.deployment().get("hazard_tier", 0)):
		# Deferred: a tier reached inside Objectives' `changed` (an objective done) must not
		# commit the campaign before Objectives has stored the change (the commit restores it).
		Contracts.server_note_deployment.call_deferred("hazard_tier", tier)


## A new deployment here: nothing carried over from the last one.
func _on_deployment_started(_dep: Dictionary) -> void:
	follow_ups.clear()
	queue.clear()
	_seen.clear()
	_last_follow = -INF
