class_name FireSupport
extends Node
## Player fire support (the Captain's list, 2026-10-20: "player artillery and UAV calls"): fire
## missions from an off-map 81 mm mortar section or a 105 mm battery, called from the command
## menu's Support > Fire support (or the fire mission panel, FireMissionPanel) through Supports
## ("support:fire:<verb>:<unit>:<rest>"). The recon UAV is UavSupport's. One node, "FireSupport",
## in every level on every peer (install, CompoundLevel._ready): the host runs the missions and
## the rounds; every peer hears the radio and keeps `shown` (each unit's mission, for the panel).
##
## A mission, host side (data/fire_support.json, Proposed numbers; the sums are FireMission's):
## - call ("call:<unit>:marker|here[:lased]|grid:<ref>"): the point is the caller's newest map
##   marker (a grid), the spot he's looking at (through binoculars it's lased: further, and a
##   smaller starting error), or a typed grid. Refused when the unit doesn't reach this region,
##   no deployment employer stands high enough with the company to lend it (min_tier), it's on
##   cooldown, out of rounds or out of range from where its guns stand off the map. It opens the
##   mission and fires one adjusting round (HE) after response_s, with the mission's starting
##   error (bias) on top of the rounds' dispersion;
## - adjust ("adjust:<unit>:add 50, left 25"): the observer's correction along his line to the
##   target moves the aim (FireMission.corrected) and another adjusting round goes; "repeat"
##   fires one more on the same aim;
## - fire for effect ("ffe:<unit>:he|smoke:<n>"): n rounds (up to max_rounds), gap_s apart;
##   when the last has landed the mission is over and the unit's cooldown_s starts;
## - danger close: friendlies within danger_close_m of the aim and the guns hold the round(s)
##   until the caller confirms ("confirm:<unit>"); confirmed, the rest of the mission fires;
## - "end:<unit>": end of mission (no cooldown unless it fired for effect); "status": a readout.
## Every round is paid as it's fired (the price per round, data/prices.json "supports"): the
## deployment's support budget first, then cash; free with DevTools.on() outside a deployment, as
## the helicopters are. Each round flies its real time of flight (the range from the guns, the
## unit's elevation) and lands within its dispersion: HE through Warheads.server_burst (people,
## the crater, the enemy hearing it: Alert), a blast on the vehicles near it (Vehicle.server_take
## _hit, the hit marked for ObserverMission's credit) and the explosion every peer sees; smoke as
## a white cloud. Radio to every player: the call, "shot", "splash", danger close, end of mission.
##
## Saved where the rebels' call-ins keep theirs: the deployment (RosterDeployment.active) keeps
## each unit's cooldown and the rounds it has given ("fire_support"), so they carry across a
## crossing and a save; outside a campaign this node keeps them.
##
## Test hooks (host): free_calls, gated, dispersion_mult, region_override, offset_s (now()), server_
## advance(seconds), mission(unit), server_set_bias(unit, bias), impacts, server_reset_limits().

signal radio_heard(text: String)

const NODE_NAME := "FireSupport"
const SHELLS: Array[String] = ["he", "smoke"]
## "Splash" this long before a round lands (as a real gun line calls it).
const SPLASH_WARN_S := 5.0
## A mission with nothing fired for this long ends by itself.
const IDLE_END_S := 600.0
## How far a lased point reaches (m; binoculars up). Without them the order range (PlayerInput).
const LASE_RANGE_M := 2500.0
const SMOKE_COLOUR := "white"
## A vehicle a round hurt keeps {"at": now(), "by", "unit"} under this meta (ObserverMission).
const HIT_META := &"fire_mission_hit"
const HEARD_KEEP := 40
const IMPACTS_KEEP := 64
const SHOW_EVERY_S := 1.0

## Tests: calls are free (1), paid (0), or the default (-1: free with DevTools.on() outside a deployment).
static var free_calls := -1
## Tests: who lends what where is asked (1), never (0), or the default (-1: not with DevTools.on()
## outside a deployment, the dev way to try every support anywhere).
static var gated := -1
## Tests: the rounds' dispersion times this (1: as the unit's).
static var dispersion_mult := 1.0
## Tests: the region the guns are asked to reach ("": the level's).
static var region_override := ""
## Tests: seconds added to the clock (server_advance).
static var offset_s := 0.0

## Every peer: radio lines heard, newest last.
var heard: Array[String] = []
## Every peer: unit -> what its mission shows (summary()), from the host.
var shown := {}
## Host: unit -> the open mission (see _open).
var missions := {}
## Host: rounds fired, still to land: {"unit", "land", "aim", "fire_at", "when", "shell", "by", "first", "last", "shot", "warned"}.
var rounds: Array = []
## Host: where rounds landed, newest last: {"unit", "pos", "aim", "shell", "range_m"} (tests, the log).
var impacts: Array = []
var _local := {"cooldown": {}, "spent": {}}  # host: outside a deployment
var _show_left := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	_rng.randomize()


## Every peer, from the level's _ready: this node, the UAV's and the forward observer missions'
## (ObserverMission), and the support commands, once.
static func install(level: Node3D) -> void:
	if level.get_node_or_null(NODE_NAME) != null:
		return
	level.add_child(FireSupport.new())
	level.add_child(UavSupport.new())
	level.add_child(ObserverMission.new())
	register_all()


## The commands (every level does on install; tests call it again after Supports.reset()).
static func register_all() -> void:
	Supports.register("fire", func(caller: Node, arg: String, point: Vector3, _names: PackedStringArray) -> String:
		var node := FireSupport.of(caller)
		return node.server_command(caller as Soldier, arg, point) if node else "No fire support here")
	Supports.register("uav", func(caller: Node, arg: String, point: Vector3, _names: PackedStringArray) -> String:
		var node := UavSupport.of(caller)
		return node.server_call(caller as Soldier, arg, point) if node else "No UAV here")


static func of(from: Node) -> FireSupport:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NODE_NAME) as FireSupport if lvl else null


## The clock fire support keeps (Soldier._now(), moved on by tests).
static func now() -> float:
	return Soldier._now() + offset_s


func level() -> CompoundLevel:
	return get_parent() as CompoundLevel


# --- Who lends what, where -------------------------------------------------------------------

## Whether calls are free now (dev outside a deployment, or the tests' switch).
static func free_now() -> bool:
	if free_calls >= 0:
		return free_calls == 1
	return DevTools.on() and not Contracts.is_deployed()


## The region the guns are asked to reach: the zone's ("" off the region map).
func region() -> String:
	if region_override != "":
		return region_override
	var lvl := level()
	if lvl and "def" in lvl:
		var r := String((lvl.get(&"def") as Dictionary).get("region", ""))
		if r != "":
			return r
	return String(MissionRegistry.zone(GameState.zone_id).get("region", ""))


## The best standing (MissionRegistry.tier_index) a deployment employer has with the company (-1
## with no deployment).
static func best_tier() -> int:
	var best := -1
	var cids: Array = Contracts.deployment().get("cids", [])
	for c: Dictionary in Contracts.held():
		if String(c.get("cid", "")) in cids:
			best = maxi(best, MissionRegistry.tier_index(Economy.reputation(String(c.get("employer", "")))))
	return best


## Whether a standing of `tier` (an index into the reputation tiers) lends support `spec` (its
## "min_tier": a tier id).
static func lends(spec: Dictionary, tier: int) -> bool:
	var need := String(spec.get("min_tier", "neutral"))
	var tiers := MissionRegistry.reputation_tiers()
	for i in tiers.size():
		if String(tiers[i].id) == need:
			return tier >= i
	return tier >= 0


## Whether availability() asks (see `gated`).
static func gates_on() -> bool:
	if gated >= 0:
		return gated == 1
	return not (DevTools.on() and not Contracts.is_deployed())


## Why support `spec` (a unit, or the UAV) named `what` can't be had here and now, or "".
func availability(spec: Dictionary, what: String) -> String:
	if not gates_on():
		return ""
	var r := region()
	var regions: Array = spec.get("regions", [])
	if r != "" and not regions.is_empty() and not r in regions:
		return "The %s can't reach the %s from where it stands" % [what, String(MissionRegistry.region(r).get("name", r)).to_lower()]
	if not Contracts.is_deployed():
		return "No %s outside a deployment" % what
	if not lends(spec, best_tier()):
		return "No employer of this deployment trusts the company enough to lend the %s (it needs %s)" % [what, String(spec.get("min_tier", "neutral")).capitalize()]
	return ""


# --- Cooldowns and rounds given (the deployment's) ---------------------------------------------

## What this deployment (or, outside one, this node) keeps: {"cooldown": {unit: now() ready},
## "spent": {unit: {shell: rounds}}, "uav_cooldown": now() ready}.
func store() -> Dictionary:
	var dep := RosterDeployment.active(BaseHub.roster()) if BaseHub.campaign_running else {}
	if dep.is_empty():
		return _local
	if not dep.has("fire_support"):
		dep["fire_support"] = {"cooldown": {}, "spent": {}}
	return dep.fire_support


func cooldown_left(unit_id: String) -> float:
	return maxf(float((store().get("cooldown", {}) as Dictionary).get(unit_id, 0.0)) - now(), 0.0)


func rounds_left(unit_id: String, shell: String) -> int:
	var allowed := int((FireMission.unit(unit_id).get("rounds_per_op", {}) as Dictionary).get(shell, 0))
	var spent := int(((store().get("spent", {}) as Dictionary).get(unit_id, {}) as Dictionary).get(shell, 0))
	return maxi(allowed - spent, 0)


func _spend(unit_id: String, shell: String, n: int) -> void:
	var s := store()
	if not s.has("spent"):
		s["spent"] = {}
	var by_unit: Dictionary = s.spent.get(unit_id, {})
	by_unit[shell] = int(by_unit.get(shell, 0)) + n
	s.spent[unit_id] = by_unit


func _set_cooldown(unit_id: String, seconds: float) -> void:
	var s := store()
	if not s.has("cooldown"):
		s["cooldown"] = {}
	s.cooldown[unit_id] = now() + seconds


## Host (tests): every cooldown and every round given forgotten.
func server_reset_limits() -> void:
	var s := store()
	s["cooldown"] = {}
	s["spent"] = {}
	s.erase("uav_cooldown")


## Host: pays `amount` for `what`: the deployment's support budget first (the contract with most
## left), then cash. Free calls pay nothing. Returns whether it's paid.
static func server_pay(amount: int, what: String) -> bool:
	if free_now() or amount <= 0:
		return true
	var cid := HeliSupports._contract_for_support()
	var from_budget := Contracts.server_draw_support(cid, amount) if cid != "" else 0
	if from_budget >= amount:
		return true
	var rest := amount - from_budget
	if Economy.spend(rest, "Fire support: %s" % what):
		Economy.note_run_expense(rest, "Fire support: %s" % what)
		return true
	if from_budget > 0:
		Contracts.server_draw_support(cid, -from_budget)
	return false


# --- Commands (host) ---------------------------------------------------------------------------

## Host: "<verb>:<unit>:<rest>" from `caller` (see the class doc); `point` is the crosshair's (or the
## lased) ground for "here". "" when it went, else what to tell the caller.
func server_command(caller: Soldier, arg: String, point: Vector3) -> String:
	if not multiplayer.is_server() or caller == null:
		return "No fire support here"
	var parts := arg.split(":", true, 2)
	var verb := String(parts[0])
	var unit_id := String(parts[1]) if parts.size() > 1 else ""
	var rest := String(parts[2]) if parts.size() > 2 else ""
	if verb == "call":
		return server_call(caller, unit_id, rest, point)
	if verb == "status":
		return status_text()
	if unit_id == "":
		unit_id = _latest_of(caller)
	var m: Dictionary = missions.get(unit_id, {})
	if m.is_empty():
		return "No fire mission open%s: call one first (Support > Fire support)" % ("" if unit_id == "" else " on the " + String(FireMission.unit(unit_id).get("name", unit_id)))
	match verb:
		"adjust":
			var said := FireMission.parse(rest)
			if said.has("why"):
				return String(said.why)
			m.observer = caller.global_position
			m.aim = _ground(FireMission.corrected(m.aim, m.observer, said.move))
			var gun_range := FireMission.flat(m.gun, m.aim)
			var u := FireMission.unit(unit_id)
			if gun_range < float(u.min_m) or gun_range > float(u.max_m):
				return "That puts it out of the %s's range" % String(u.name)
			_radio(unit_id, "%s, adjusting. Out." % _move_text(said.move))
			return _request(m, "adjust", "he", 1)
		"repeat":
			m.observer = caller.global_position
			return _request(m, "adjust", "he", 1)
		"ffe":
			var bits := rest.split(":")
			var shell := String(bits[0]) if bits.size() > 0 and String(bits[0]) in SHELLS else "he"
			var n := int(bits[1]) if bits.size() > 1 and String(bits[1]).is_valid_int() else 3
			return _request(m, "ffe", shell, n)
		"confirm":
			if m.held.is_empty():
				m.confirmed = true
				return "Danger close confirmed for this mission"
			m.confirmed = true
			var held: Dictionary = m.held
			m.held = {}
			_radio(unit_id, "Danger close confirmed. Firing.")
			return _request(m, String(held.kind), String(held.shell), int(held.n))
		"end":
			_end(unit_id, bool(m.ffe))
			return ""
	return "Fire mission order not understood"


## Host: opens a mission on `unit_id` for `caller` at `where` ("marker", "here[:lased]",
## "grid:<ref>") and fires its first adjusting round.
func server_call(caller: Soldier, unit_id: String, where: String, point: Vector3) -> String:
	var u := FireMission.unit(unit_id)
	if u.is_empty():
		return "No such firing unit"
	var why := availability(u, String(u.name))
	if why != "":
		return why
	if missions.has(unit_id):
		return "%s has a mission open: adjust it, fire for effect or end it first" % String(u.callsign)
	if cooldown_left(unit_id) > 0.0:
		return "The %s can fire another mission in %d s" % [String(u.name), ceili(cooldown_left(unit_id))]
	if rounds_left(unit_id, "he") <= 0:
		return "The %s has no HE left for this deployment" % String(u.name)
	var lased := where.ends_with(":lased")
	var target := _resolve(caller, where.trim_suffix(":lased"), point)
	if target.has("why"):
		return String(target.why)
	var at: Vector3 = target.pos
	var lvl := level()
	var area: Rect2 = lvl.map_area() if lvl else Rect2(-500, -500, 1000, 1000)
	var from := Supports.origin_for(lvl, &"fob", at, 0.0).origin
	var gun := FireMission.gun_point(area, at, from, float(u.off_map_m))
	var gun_range := FireMission.flat(gun, at)
	if gun_range < float(u.min_m) or gun_range > float(u.max_m):
		return "Grid %s is out of the %s's range (%d m from its guns; %d-%d m)" % [FireMission.grid(at, area), String(u.name), roundi(gun_range), int(u.min_m), int(u.max_m)]
	var lo_hi: Array = u.get("bias_m", [20, 50])
	var m := {"unit": unit_id, "by": caller, "by_name": String(caller.name), "target": at, "aim": at, "observer": caller.global_position,
		"bias": FireMission.bias(_rng, float(lo_hi[0]), float(lo_hi[1]), float(u.get("lased_bias", 0.35)) if lased else 1.0),
		"gun": gun, "lased": lased, "confirmed": false, "held": {}, "fired": 0, "adjusts": 0, "ffe": false, "next_fire": now(),
		"last_burst": Vector3.INF, "last_at": now(), "ends_at": INF}
	missions[unit_id] = m
	SessionLog.note("fire support: %s called the %s on %s (%s), %d m from the guns" % [caller.name, unit_id, FireMission.grid(at, area), "lased" if lased else where, roundi(gun_range)])
	_radio(unit_id, "Fire mission, grid %s, adjust fire%s. Out." % [FireMission.grid(at, area), " (lased)" if lased else ""])
	var out := _request(m, "adjust", "he", 1)
	if out != "" and not out.begins_with("Danger close"):
		missions.erase(unit_id)  # nothing fired: no mission
	_show()
	return out


## Host: fire `n` rounds of `shell` on mission `m` ("adjust" or "ffe"), or hold them for danger
## close. "" when they're on their way, or why not.
func _request(m: Dictionary, kind: String, shell: String, n: int) -> String:
	var unit_id := String(m.unit)
	var u := FireMission.unit(unit_id)
	if bool(m.ffe):
		return "%s fired for effect already: end the mission" % String(u.callsign)
	n = clampi(n, 1, int(u.get("max_rounds", 6)))
	if rounds_left(unit_id, shell) < n:
		return "The %s has %d %s round%s left for this deployment" % [String(u.name), rounds_left(unit_id, shell), shell.to_upper() if shell == "he" else shell, "" if rounds_left(unit_id, shell) == 1 else "s"]
	var close := FireMission.danger_close(m.aim, _friendly_spots(), float(u.danger_close_m))
	if close > 0 and not bool(m.confirmed):
		m.held = {"kind": kind, "shell": shell, "n": n}
		_radio(unit_id, "Danger close: %d friendl%s within %d m of the aim. Request confirmation, over." % [close, "y" if close == 1 else "ies", int(u.danger_close_m)])
		_show()
		return "Danger close: %d friendl%s within %d m. Confirm danger close (Support > Fire support) to fire" % [close, "y" if close == 1 else "ies", int(u.danger_close_m)]
	var near := Deconfliction.friendlies_near(self, m.aim, float(u.danger_close_m) * 2.0)
	if int(near.count) > 0 and int(m.fired) == 0:  # the FDC warns before a mission near friendlies (combined_arms 4.5)
		_radio(unit_id, "Splash in %d, friendlies stay %s of the target." % [roundi(float(u.response_s) + FireMission.flight_s(FireMission.flat(m.gun, m.aim), float(u.elevation_mils))),
			near.away if String(near.away) != "" else "clear"])
	var price := Prices.support_price(String(u.price)) * n
	if not server_pay(price, "%s, %d %s" % [String(u.name), n, "adjusting round" if kind == "adjust" else ("rounds" if n > 1 else "round")]):
		return "Can't pay for %d round%s ($%s)" % [n, "" if n == 1 else "s", DebriefCalc.money(price)]
	var gun_range := FireMission.flat(m.gun, m.aim)
	var flight := FireMission.flight_s(gun_range, float(u.elevation_mils))
	var start := maxf(now(), float(m.next_fire)) + float(u.response_s if int(m.fired) == 0 else u.adjust_s)
	var gap := float(u.get("gap_s", 2.0))
	var spread := FireMission.dispersion_m(u, gun_range) * dispersion_mult
	for i in n:  # (where each lands is worked out as it's fired: _step)
		rounds.append({"unit": unit_id, "land": m.aim, "aim": m.aim, "spread": spread, "fire_at": start + gap * i, "when": start + gap * i + flight, "shell": shell,
			"by": m.by, "first": i == 0, "last": i == n - 1, "ffe": kind == "ffe", "shot": false, "warned": false, "range_m": gun_range})
	m.next_fire = start + gap * n
	m.fired = int(m.fired) + n
	m.last_at = now()
	if kind == "adjust":
		m.adjusts = int(m.adjusts) + 1
	else:
		m.ffe = true
		m.ends_at = start + gap * (n - 1) + flight + SPLASH_WARN_S
	_spend(unit_id, shell, n)
	SessionLog.note("fire support: %s %s, %d x %s, %d m, time of flight %.0f s" % [unit_id, kind, n, shell, roundi(gun_range), flight])
	_show()
	return ""


## Host (an operation's guns, cg_brief queue item 3.3: OpSupport): `n` rounds of `shell` from
## data "allied_units" `unit_id` (the employer's mortars and battery, naval gunfire, the enemy's
## mortar) on `aim`, from guns off the map past `from` (the side they fire from). No mission, no
## pay, no adjusting: the firing unit's own plan. Held (and why) when friendlies of the firing side
## are within its danger_close_m of the aim, or the aim is out of its reach. "" when they're on
## their way.
func server_allied_fire(unit_id: String, aim: Vector3, n: int, shell: String, from: Vector3, by: Node = null) -> String:
	var u := FireMission.unit(unit_id)
	if u.is_empty():
		return "No such firing unit"
	var lvl := level()
	if lvl == null:
		return "No level"
	aim = _ground(aim)
	var area: Rect2 = lvl.map_area()
	var gun := Vector3(from.x, 0.0, from.z) if bool(u.get("in_zone", false)) else FireMission.gun_point(area, aim, from, float(u.off_map_m))  # (mortars with the battlegroup fire from where their tubes stand)
	var gun_range := FireMission.flat(gun, aim)
	if gun_range < float(u.min_m) or gun_range > float(u.max_m):
		return "out of the %s's range (%d m)" % [String(u.name), roundi(gun_range)]
	var hostile := String(u.get("side", "friendly")) == "hostile"
	if not hostile and int(Deconfliction.friendlies_near(self, aim, float(u.danger_close_m)).count) > 0:
		return "friendlies within %d m of the aim" % int(u.danger_close_m)
	if hostile:
		for s in get_tree().get_nodes_in_group(&"combatants"):
			if s is Soldier and (s as Soldier).faction == &"hostile" and (s as Soldier).vitals.is_up() \
					and FireMission.flat((s as Soldier).global_position, aim) < float(u.danger_close_m):
				return "their own men within %d m of the aim" % int(u.danger_close_m)
	var flight := FireMission.flight_s(gun_range, float(u.elevation_mils))
	var start := now() + float(u.response_s)
	var gap := float(u.get("gap_s", 2.0))
	var spread := FireMission.dispersion_m(u, gun_range) * dispersion_mult
	for i in clampi(n, 1, int(u.get("max_rounds", 12))):
		rounds.append({"unit": unit_id, "land": aim, "aim": aim, "spread": spread, "fire_at": start + gap * i, "when": start + gap * i + flight, "shell": shell,
			"by": by, "first": false, "last": false, "ffe": true, "shot": false, "warned": false, "range_m": gun_range, "gun": gun, "allied": true})
	SessionLog.note("fire support: %s, %d x %s on (%.0f, %.0f), %d m, time of flight %.0f s" % [unit_id, n, shell, aim.x, aim.z, roundi(gun_range), flight])
	return ""


## Host: mission `unit_id` is over; after a fire for effect the unit's cooldown starts.
func _end(unit_id: String, cooldown: bool) -> void:
	if not missions.has(unit_id):
		return
	missions.erase(unit_id)
	var u := FireMission.unit(unit_id)
	if cooldown:
		_set_cooldown(unit_id, float(u.cooldown_s))
	_radio(unit_id, "End of mission%s. Out." % (", ready again in %d min" % ceili(float(u.cooldown_s) / 60.0) if cooldown else ""))
	_show()


## The newest mission `caller` opened (any unit), else any open one ("" for none).
func _latest_of(caller: Soldier) -> String:
	var best := ""
	var best_t := -INF
	for id: String in missions:
		var m: Dictionary = missions[id]
		var mine := String(m.by_name) == String(caller.name)
		var t := float(m.last_at) + (1e6 if mine else 0.0)
		if t > best_t:
			best = id
			best_t = t
	return best


## Where a call goes: {"pos": on the ground} or {"why"} (HeliSupports' marker and grid rules).
func _resolve(caller: Soldier, where: String, point: Vector3) -> Dictionary:
	var how := where.get_slice(":", 0)
	match how:
		"", "here":
			if not point.is_finite():
				return {"why": "Look at the spot (binoculars reach further)"}
			return {"pos": _ground(point)}
		"marker":
			var heli := HeliSupports.of(self)
			var marker: Variant = heli.newest_marker(caller) if heli else null
			if marker == null:
				return {"why": "Put a marker on the map first (M, double-click)"}
			var p: Vector2 = marker
			return {"pos": _ground(Vector3(p.x, 0.0, p.y))}
		"grid":
			var at: Variant = MapGrid.parse(where.substr(5), MapNodes.area_of(self))
			if at == null:
				return {"why": "That isn't a grid reference"}
			var g: Vector2 = at
			return {"pos": _ground(Vector3(g.x, 0.0, g.y))}
	return {"why": "Say where: my map marker, there, or a grid"}


func _ground(p: Vector3) -> Vector3:
	var lvl := level()
	return lvl.ground_point(Vector3(p.x, 0.0, p.z)) if lvl else p


## Where our people are (players, squad AI, allied elements): for danger close.
func _friendly_spots() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.faction == &"friendly" and not s.is_queued_for_deletion() and not s.vitals.is_dead():
			out.append(s.global_position)
	return out


static func _move_text(move: Vector2) -> String:
	var said := PackedStringArray()
	if move.x != 0.0:
		said.append("%s %d" % ["right" if move.x > 0.0 else "left", absi(roundi(move.x))])
	if move.y != 0.0:
		said.append("%s %d" % ["add" if move.y > 0.0 else "drop", absi(roundi(move.y))])
	return (", ".join(said) if not said.is_empty() else "Repeat").capitalize()


# --- Rounds (host) -----------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	_step()
	_show_left -= _delta
	if _show_left <= 0.0 and not missions.is_empty():
		_show()


## Host (tests): the clock `seconds` on, rounds landing as they come due.
func server_advance(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var dt := minf(left, 0.25)
		left -= dt
		offset_s += dt
		_step()


func _step() -> void:
	var t := now()
	for r: Dictionary in rounds.duplicate():
		if not bool(r.shot) and t >= float(r.fire_at) and _check_fire(r):
			continue
		if not bool(r.shot) and t >= float(r.fire_at):
			r.shot = true
			var bias: Vector3 = (missions.get(String(r.unit), {}) as Dictionary).get("bias", Vector3.ZERO)
			r.land = FireMission.in_disc(_rng, (r.aim as Vector3) + bias, float(r.spread))  # the aim, the mission's error, the round's own spread
			var gun: Variant = r.get("gun", (missions.get(String(r.unit), {}) as Dictionary).get("gun"))  # (an operation's allied rounds carry their own: server_allied_fire)
			var lvl := level()
			if gun is Vector3 and lvl:  # every peer sees it come down out of the sky, in the wind (ShellArc)
				lvl.server_show_shell(Vector3(gun.x, maxf(gun.y, 0.0) + 1.5, gun.z), _ground(r.land), float(r.when) - t)
			if bool(r.first):
				_radio(String(r.unit), "Shot, over. Time of flight %d seconds." % roundi(float(r.when) - float(r.fire_at)))
		if not bool(r.warned) and t >= float(r.when) - SPLASH_WARN_S:
			r.warned = true
			if bool(r.first):
				_radio(String(r.unit), "Splash, over.")
		if t >= float(r.when):
			rounds.erase(r)
			_impact(r)
	for id: String in missions.keys():
		var m: Dictionary = missions[id]
		if not is_instance_valid(m.by):
			m.by = null
		if t >= float(m.ends_at) or (t - float(m.last_at) > IDLE_END_S and not _in_flight(id)):
			_end(id, bool(m.ffe))


## A round about to be fired whose target area has a check fire, or a friendly walked into it
## (inside danger close, a mission not confirmed danger close): the mission's rounds not yet fired
## are stopped (combined_arms 4.5). True if `r` was.
func _check_fire(r: Dictionary) -> bool:
	var m: Dictionary = missions.get(String(r.unit), {})
	var u := FireMission.unit(String(r.unit))
	var walked_in := not bool(m.get("confirmed", false)) and int(Deconfliction.friendlies_near(self, r.aim, float(u.get("danger_close_m", 150.0))).count) > 0
	if not Deconfliction.checked(r.aim) and not walked_in:
		return false
	for other: Dictionary in rounds.duplicate():
		if String(other.unit) == String(r.unit) and not bool(other.shot):
			rounds.erase(other)
	_radio(String(r.unit), "Check fire, check fire. %s." % ("Friendlies in the target area" if walked_in else "Check fire called"))
	SessionLog.note("fire support: %s check fire" % String(r.unit))
	return true


func _in_flight(unit_id: String) -> bool:
	return rounds.any(func(r: Dictionary) -> bool: return String(r.unit) == unit_id)


## Host: round `r` lands.
func _impact(r: Dictionary) -> void:
	var lvl := level()
	if lvl == null:
		return
	var p := _ground(r.land)
	var unit_id := String(r.unit)
	var u := FireMission.unit(unit_id)
	var by: Node = r.by if is_instance_valid(r.by) else null
	if String(r.shell) == "smoke":
		lvl.server_spawn_smoke(p + Vector3.UP * 0.3, SMOKE_COLOUR)  # (its seed and wind picked here: the same cloud on every peer)
	else:
		var warhead := StringName(String(u.warhead))
		Warheads.server_burst(lvl, warhead, p + Vector3.UP * 0.15, Vector3.DOWN, null, by)  # people, the crater, the shake
		lvl.show_explosion.rpc(p)
		Alert.server_noise(lvl, p, Alert.BLAST)  # the enemy hears it, as a charge
		var dig := Digging.of(lvl)
		if dig:
			dig.server_blast(p, 2.0 if unit_id == "mortar" else 3.0)
		_blast_vehicles(p, u, warhead, by, unit_id)
	if missions.has(unit_id):
		missions[unit_id].last_burst = p
	impacts.append({"unit": unit_id, "pos": p, "aim": r.aim, "shell": String(r.shell), "range_m": float(r.range_m), "ffe": bool(r.ffe)})
	while impacts.size() > IMPACTS_KEEP:
		impacts.pop_front()
	print("[fire] %s %s lands at (%.0f, %.0f), %.0f m off its aim" % [unit_id, String(r.shell), p.x, p.z, FireMission.flat(p, r.aim)])


## Host: a round's blast on the vehicles within the unit's vehicle_reach_m of `p`: an HE hit with
## the warhead's blast times vehicle_blast_x, falling off with distance squared, each marked with
## HIT_META (whose fire it was, for the forward observer's pay).
func _blast_vehicles(p: Vector3, u: Dictionary, warhead: StringName, by: Node, unit_id: String) -> void:
	var layer := VehicleLayer.of(self)
	if layer == null:
		return
	var reach := float(u.get("vehicle_reach_m", 8.0))
	var kg := float(Warheads.data(warhead).get("blast_kg", 0.5)) * float(u.get("vehicle_blast_x", 2.5))
	var hit_any := false
	for v: Vehicle in layer.vehicles():
		if v.wrecked or v.kind == Vehicle.HELICOPTER:
			continue
		var centre := v.global_transform * v.center_of_mass
		var d := centre.distance_to(p)
		if d > reach:
			continue
		var share := pow(1.0 - d / reach, 2.0)
		var toward := (centre - p).normalized() if d > 0.05 else Vector3.DOWN
		v.server_take_hit({"kind": Vehicle.HE, "position": centre - toward * minf(d, 0.6), "direction": toward, "blast_kg": kg * share,
			"shooter": by, "warhead": String(warhead), "warhead_kind": Vehicle.HE})
		v.set_meta(HIT_META, {"at": now(), "by": String(by.name) if by else "", "unit": unit_id})
		hit_any = true
	# A forward observer's target the round just put out of action is the guns' kill now, not at
	# ObserverMission's next tick (whatever the clock does in between: CI saw a test's clock jump
	# past its credit window first).
	var observer := ObserverMission.of(self)
	if hit_any and observer:
		observer.server_check()


## Whether `v` was hurt by fire support in the last `within_s` seconds.
static func hit_lately(v: Node, within_s: float) -> bool:
	if v == null or not v.has_meta(HIT_META):
		return false
	return now() - float((v.get_meta(HIT_META) as Dictionary).get("at", -INF)) <= within_s


## Host (tests): mission `unit_id`'s state ({} with none).
func mission(unit_id: String) -> Dictionary:
	return missions.get(unit_id, {})


## Host (tests): mission `unit_id`'s starting error set to `b`.
func server_set_bias(unit_id: String, b: Vector3) -> void:
	if missions.has(unit_id):
		missions[unit_id].bias = b


# --- What every peer sees ----------------------------------------------------------------------

## Host: each unit's state for the panel: {"name", "callsign", "open", "target", "aim" (grids),
## "bearing" (the caller's line to the aim), "range_m", "fired", "ffe", "held", "in_flight",
## "cooldown", "he", "smoke", "price", "max_rounds", "why" (not available, or "")}.
func summary() -> Dictionary:
	var out := {}
	var area: Rect2 = level().map_area() if level() else Rect2(-500, -500, 1000, 1000)
	for id: String in FireMission.units():
		var u := FireMission.unit(id)
		var m: Dictionary = missions.get(id, {})
		var e := {"name": String(u.name), "callsign": String(u.callsign), "open": not m.is_empty(), "cooldown": ceili(cooldown_left(id)),
			"he": rounds_left(id, "he"), "smoke": rounds_left(id, "smoke"), "price": Prices.support_price(String(u.price)),
			"max_rounds": int(u.get("max_rounds", 6)), "why": availability(u, String(u.name)), "in_flight": rounds.filter(func(r: Dictionary) -> bool: return String(r.unit) == id).size()}
		if not m.is_empty():
			var observer: Vector3 = m.by.global_position if is_instance_valid(m.by) else m.observer
			e.merge({"target": FireMission.grid(m.target, area), "aim": FireMission.grid(m.aim, area), "bearing": roundi(FireMission.bearing(observer, m.aim)),
				"distance": roundi(FireMission.flat(observer, m.aim)), "range_m": roundi(FireMission.flat(m.gun, m.aim)), "fired": int(m.fired), "ffe": bool(m.ffe),
				"held": not (m.held as Dictionary).is_empty(), "by": String(m.by_name)})
		out[id] = e
	return out


func _show() -> void:
	_show_left = SHOW_EVERY_S
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_client_show.rpc(summary())


@rpc("authority", "call_local", "reliable")
func _client_show(list: Dictionary) -> void:
	shown = list


## Host: a radio line from unit `unit_id` to every player.
func _radio(unit_id: String, text: String) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_client_radio.rpc("%s: %s" % [String(FireMission.unit(unit_id).get("callsign", "Fire support")), text])


## Host: a radio line from the UAV's operator (UavSupport) to every player.
func radio_uav(text: String) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_client_radio.rpc("%s: %s" % [String(FireMission.uav().get("callsign", "UAV")), text])


@rpc("authority", "call_local", "reliable")
func _client_radio(text: String) -> void:
	heard.append(text)
	while heard.size() > HEARD_KEEP:
		heard.pop_front()
	MapNodes.flash_local(self, text)
	radio_heard.emit(text)


## Whether a line containing `part` was heard here.
func heard_line(part: String) -> bool:
	return heard.any(func(line: String) -> bool: return line.contains(part))


## What fire support stands at, for the caller ("status"): each unit's mission or readiness.
func status_text() -> String:
	var lines := PackedStringArray()
	for id: String in FireMission.units():
		var e: Dictionary = summary()[id]
		if bool(e.open):
			lines.append("%s: mission on %s, %d fired%s" % [e.callsign, e.aim, int(e.fired), ", danger close: confirm" if bool(e.held) else ""])
		elif String(e.why) != "":
			lines.append("%s: %s" % [e.callsign, e.why])
		else:
			lines.append("%s: %s, %d HE, %d smoke left" % [e.callsign, "ready" if int(e.cooldown) <= 0 else "ready in %d s" % int(e.cooldown), int(e.he), int(e.smoke)])
	return "; ".join(lines)


# --- The local player's side --------------------------------------------------------------------

## The ground `player` lases through his binoculars (LASE_RANGE_M), else null.
static func lase_point(player: Soldier) -> Variant:
	var from := player.camera.global_position
	var hit := player.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, from - player.camera.global_basis.z * LASE_RANGE_M, 1, [player.get_rid()]))
	return null if hit.is_empty() else hit.position


## The command menu's own screens ("local:<what>"): "fire_panel" (FireMissionPanel), "uav_feed" (UavFeed).
static func local_command(player: Soldier, what: String) -> void:
	match what:
		"fire_panel":
			FireMissionPanel.open(player)
		"uav_feed":
			UavFeed.toggle(player)
