class_name RebelCalls
extends Node
## The rebels' call-ins (rebel support part 2; docs/rebel_support.md, the Captain's calls
## 2026-10-19): what the locals of a region do for the company once their support reaches each
## tier (RebelSupport.CALLINS), from the command menu's Support > Rebels:
##   rebel_lookouts      for LOOKOUT_S the villagers report the gunmen near the caller: they're
##                       tagged for the squad every LOOKOUT_EVERY_S (EnemyTags; no radio needed);
##   rebel_diversion     rebels open fire at the point marked for DIVERSION_S: the hostiles within
##                       DIVERSION_M go to see (their threat point), away from the squad;
##   rebel_fighters      an element of local fighters (AlliedTroops, rebel) comes from the
##                       nearest village, under the host's high command;
##   rebel_vehicle_drop  a technical is left at the point marked, the company's to use;
##   rebel_mortar        after MORTAR_WARN_S, MORTAR_ROUNDS on the point marked.
## Free; each has its cooldown (COOLDOWN_S) per deployment. In a hot zone they work too but
## weaker (Captain: "yes, weaker"): HOT_WEAKER of the reach and rounds and men, cooldowns
## HOT_COOLDOWN times as long. Only where the call-in is unlocked: the caller's region (and the
## Lookouts in the tutorial, which has none: TutorialGuide).
## One node, "RebelCalls", in every level (install); the work is the host's. Proposed numbers.

const NODE_NAME := "RebelCalls"
const COOLDOWN_S := {"lookouts": 600.0, "diversion": 600.0, "fighters": 1200.0, "vehicle_drop": 1800.0, "mortar": 900.0}
const HOT_COOLDOWN := 1.5
const HOT_WEAKER := 0.6
const LOOKOUT_S := 300.0
const LOOKOUT_EVERY_S := 30.0
const LOOKOUT_M := 250.0
const DIVERSION_S := 45.0
const DIVERSION_M := 450.0
const DIVERSION_SHOT_S := 1.5
const FIGHTERS := 6
const VILLAGE_REACH_M := 600.0
const VEHICLE := "technical"
const MORTAR_WARN_S := 10.0
const MORTAR_ROUNDS := 4
const MORTAR_GAP_S := 2.5
const MORTAR_SPREAD_M := 12.0

var _cooldown := {}   # host: call-in -> Soldier._now() it's ready again (this level's; a deployment's below)
var _lookout := {}    # host: {"by", "until", "next"} while the lookouts watch
var _diversion := {}  # host: {"at", "until", "next"}
var _mortar: Array = []  # host: [{"at", "when"}] rounds to fall
var _rng := RandomNumberGenerator.new()


## Every peer, from the level's _ready: this node and its support commands, once.
static func install(level: Node3D) -> void:
	if level.get_node_or_null(NODE_NAME) != null:
		return
	var n := RebelCalls.new()
	n.name = NODE_NAME
	level.add_child(n)
	for id: String in RebelSupport.CALLINS:
		Supports.register("rebel_" + id, func(caller: Node, _arg: String, point: Vector3, _names: PackedStringArray) -> String:
			var node := RebelCalls.of(caller)
			return node.server_call(id, caller as Soldier, point) if node else "No rebels here")


static func of(from: Node) -> RebelCalls:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NODE_NAME) as RebelCalls if lvl else null


func _ready() -> void:
	_rng.randomize()


## Host: call-in `id` for `by` at `point`. Returns "" or why not.
func server_call(id: String, by: Soldier, point: Vector3) -> String:
	if not multiplayer.is_server() or by == null:
		return ""
	var region := RebelSupport.region_here(self)
	# The tutorial (TutorialGuide) has no region: its locals answer the Lookouts, and only those.
	var tutorial := region == "" and not BaseHub.campaign_running and TutorialGuide.of(self) != null
	if tutorial and id != "lookouts":
		return "In the tutorial, try the Lookouts: the rest open up as a region's locals back you more"
	if region == "" and not tutorial:
		return "No locals here to call on"
	if not tutorial and not id in RebelSupport.unlocked(region):
		return "The locals of the %s won't do that yet (support %d of %d)" % [region, int(RebelSupport.support(region)), int(RebelSupport.CALLINS[id])]
	var left := cooldown_left(id)
	if left > 0.0:
		return "The rebels can do that again in %d s" % ceili(left)
	var lvl := CompoundLevel.current(self)
	var hot := Supports.is_hot_zone(lvl)
	var weaker := HOT_WEAKER if hot else 1.0
	var lv := RebelSupport.level(id)  # (part 4: the upgrades)
	if point.is_finite() and lvl.has_method(&"ground_point"):
		point = lvl.call(&"ground_point", point)
	var why := ""
	match id:
		"lookouts":
			_lookout = {"by": by, "until": Soldier._now() + LOOKOUT_S, "next": 0.0, "reach": LOOKOUT_M * weaker * [1.0, 1.4, 1.8][lv],
				"every": LOOKOUT_EVERY_S if lv < 2 else 20.0}
		"diversion":
			if not point.is_finite():
				return "Mark where they should open fire"
			_diversion = {"at": point, "until": Soldier._now() + DIVERSION_S * [1.0, 1.5, 2.0][lv], "next": 0.0, "reach": DIVERSION_M * weaker}
		"fighters":
			why = _send_fighters(by, maxi(roundi((FIGHTERS + 2 * lv) * weaker), 2), lv)
		"vehicle_drop":
			var at := point if point.is_finite() else by.global_position + by.global_basis.z * -8.0
			why = _drop_vehicle(at)
			if why == "" and lv >= 2:
				_drop_vehicle(at + by.global_basis.x * 7.0)  # two at a time
		"mortar":
			if not point.is_finite():
				return "Mark where the rounds should fall"
			var rounds := maxi(roundi((MORTAR_ROUNDS + 2 * lv) * weaker), 1)
			for k in rounds:
				_mortar.append({"at": point, "when": Soldier._now() + MORTAR_WARN_S + k * MORTAR_GAP_S, "spread": MORTAR_SPREAD_M * (0.6 if lv >= 2 else 1.0)})
			Contracts._notify_all("Rebel mortar: %d rounds on the mark in %d s. Get clear." % [rounds, int(MORTAR_WARN_S)])
	if why != "":
		return why
	_set_cooldown(id, COOLDOWN_S[id] * (HOT_COOLDOWN if hot else 1.0) * (0.7 if id == "vehicle_drop" and lv >= 1 else 1.0))
	SessionLog.note("rebels: %s for %s in the %s%s" % [id, by.name, region, " (hot zone: weaker)" if hot else ""])
	if id != "mortar":
		Contracts._notify_all("The rebels: %s%s." % [String(RebelSupport.CALLIN_NAMES[id]), " (thinly, in a hot zone)" if hot else ""])
	return ""


## Host: whether the lookouts are out watching for `s` now.
func lookouts_for(s: Soldier) -> bool:
	return s != null and not _lookout.is_empty() and _lookout.get("by") == s and Soldier._now() <= float(_lookout.until)


## Seconds until `id` can be called again (0: now). A deployment keeps its own (crossings too).
func cooldown_left(id: String) -> float:
	var dep := RosterDeployment.active(BaseHub.roster()) if BaseHub.campaign_running else {}
	var cd: Dictionary = dep.get("rebel_cooldown", _cooldown) if not dep.is_empty() else _cooldown
	return maxf(float(cd.get(id, 0.0)) - Soldier._now(), 0.0)


func _set_cooldown(id: String, seconds: float) -> void:
	var dep := RosterDeployment.active(BaseHub.roster()) if BaseHub.campaign_running else {}
	if not dep.is_empty():
		if not dep.has("rebel_cooldown"):
			dep["rebel_cooldown"] = {}
		dep.rebel_cooldown[id] = Soldier._now() + seconds
	else:
		_cooldown[id] = Soldier._now() + seconds


func _send_fighters(by: Soldier, men: int, lv := 0) -> String:
	var allies := AlliedTroops.current(self)
	if allies == null:
		return "No way to bring them in here"
	var from := _village_near(by.global_position)
	if not from.is_finite():
		from = by.global_position + by.global_basis.z * 60.0  # behind the caller
	var before := allies.out().size()
	var why := allies.server_call(by, true, "rifle", false, from, true, men)  # all `men` of them (audit A2-05: ten at the top level, not the rifle squad's eight)
	if why != "":
		return why
	if allies.out().size() > before:
		var e: Dictionary = allies.out().back()
		var members := (e.squad as Squad).members()
		if lv >= 1 and men >= 4:  # upgraded: two of them bring a DShK (G-25)
			StaticWeapons.arm_gun_team(CompoundLevel.current(self), members[0], members[1], "tripod_dshk", e.squad)
	return ""


## The nearest village or town within VILLAGE_REACH_M of `at` (INF for none).
func _village_near(at: Vector3) -> Vector3:
	var lvl := CompoundLevel.current(self)
	var best := Vector3.INF
	for m: Node in lvl.call(&"modules") if lvl and lvl.has_method(&"modules") else []:
		var t := ZoneModules.base(String(m.get(&"type")))
		var p := (m as Node3D).global_position
		if t in ["village", "town"] and p.distance_to(at) <= VILLAGE_REACH_M and (not best.is_finite() or p.distance_to(at) < best.distance_to(at)):
			best = p
	return best


func _drop_vehicle(at: Vector3) -> String:
	var layer := VehicleLayer.of(self)
	var lvl := CompoundLevel.current(self)
	if layer == null:
		return "No vehicles here"
	var pos: Vector3 = lvl.call(&"ground_point", at) if lvl.has_method(&"ground_point") else at
	var v := layer.server_spawn(VEHICLE, Transform3D(Basis.IDENTITY, pos + Vector3.UP * 0.6), "", &"player")
	return "" if v else "The rebels couldn't bring a vehicle"


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	var now := Soldier._now()
	if not _lookout.is_empty():
		if now > float(_lookout.until) or not is_instance_valid(_lookout.by):
			_lookout = {}
		elif now >= float(_lookout.next):
			_lookout.next = now + float(_lookout.get("every", LOOKOUT_EVERY_S))
			_lookouts_report(_lookout.by, float(_lookout.reach))
	if not _diversion.is_empty():
		if now > float(_diversion.until):
			_diversion = {}
		elif now >= float(_diversion.next):
			_diversion.next = now + DIVERSION_SHOT_S
			_diversion_tick(_diversion.at, float(_diversion.reach))
	for r: Dictionary in _mortar.duplicate():
		if now >= float(r.when):
			_mortar.erase(r)
			_mortar_round(r.at, float(r.get("spread", MORTAR_SPREAD_M)))


## The lookouts' report: every hostile up within `reach` of `by` tagged for the squad.
func _lookouts_report(by: Soldier, reach: float) -> void:
	var tags := EnemyTags.of(self)
	var n := 0
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var s := node as Soldier
		if s and s.faction == &"hostile" and s.vitals.is_up() and not Person.is_noncombatant(s) and s.global_position.distance_to(by.global_position) <= reach:
			if tags:
				tags.server_tag_reported(s)
			n += 1
	if n > 0 and by.owner_connected():
		by._client_message.rpc_id(by.owner_peer(), "Lookouts: %d gunm%s near you, marked" % [n, "an" if n == 1 else "en"])


## The diversion: rebel gunfire at `at`; the hostiles within `reach` turn toward it.
func _diversion_tick(at: Vector3, reach: float) -> void:
	var to := at + Vector3(_rng.randf_range(-40, 40), 1.0, _rng.randf_range(-40, 40))
	Sfx.server_shot(at + Vector3.UP * 1.4, to, "ak")
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var s := node as Soldier
		if s and s.faction == &"hostile" and s.vitals.is_up() and s.global_position.distance_to(at) <= reach:
			s.threat_pos = at
			s.threat_time = Soldier._now()


func _mortar_round(at: Vector3, spread := MORTAR_SPREAD_M) -> void:
	var lvl := CompoundLevel.current(self)
	if lvl == null:
		return
	var p := at + Vector3(_rng.randf_range(-spread, spread), 0.0, _rng.randf_range(-spread, spread))
	if lvl.has_method(&"ground_point"):
		p = lvl.call(&"ground_point", p)
	Throwables.server_detonate(lvl, "frag", p)
	var dig := Digging.of(lvl)
	if dig:
		dig.server_blast(p, 2.0)
