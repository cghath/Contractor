class_name RivalTeam
extends Node
## Wave 6: rival contractor teams. Some contracts the squad takes, a rival PMC (the Vantage Group)
## is after too: a race for the same site. Once a contract goes live (Contracts.contract_live),
## RACE_TYPES contracts not against Vantage itself draw a rival team, CHANCE_PCT of them (picked
## by the contract's id, so the same contract always does or doesn't: no RNG drawn, nothing
## seeded shifts). After a delay it comes in from the zone edge out of the players' sight, in
## Vantage's own kit (CompoundLevel.PMC_LOADOUT: EnemyResponse._spawn_team casts its mix), and
## heads for the contract's site. Held by its men for SECURE_S with no friendly up within CLEAR_M,
## the site is theirs: "Vantage got there first", the contract's open objectives fail
## (Objectives.server_fail_contract). Kill or drive them off first and the job goes on.
##
## They fight as "hostile" (the one enemy side the AI knows), so the militia and they don't
## shoot each other: a simplification until factions fight each other in the field. Numbers
## Proposed. Host only; one node per zone level (ZoneLevel._ready).

const NODE_NAME := "RivalTeam"
const RIVAL := "vantage_group"
## The contracts a rival team races the squad on: something to get to first.
const RACE_TYPES := ["intel_grab", "hvt_capture", "recon"]
const CHANCE_PCT := 30
## Seconds after the contract goes live before the team comes in (picked by the contract id).
const DELAY_S := Vector2(90.0, 240.0)
const SIZE := 6
const SECURE_M := 30.0
const CLEAR_M := 60.0
const SECURE_S := 60.0
const COMBAT := 0.7
const DISCIPLINE := 0.8
const TICK_S := 0.5
## What the team's leader carries: evidence of what Vantage is doing out here (story intel).
const LEDGER := &"vantage_ledger"

## Tests: 1 always races, 0 never; -1 by CHANCE_PCT.
static var forced := -1
## Host: [{"cid", "title", "site": Vector3, "go_at", "squad", "soldiers", "held", "state"
## ("pending", "out", "won", "beaten")}].
var races: Array[Dictionary] = []
var _tick := 0.0


static func of(from: Node) -> RivalTeam:
	var level := CompoundLevel.current(from)
	return level.get_node_or_null(NODE_NAME) as RivalTeam if level else null


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	if multiplayer.is_server():
		Contracts.contract_live.connect(_on_live)


## Whether `contract` draws a rival team.
static func races_on(contract: Dictionary) -> bool:
	if forced >= 0:
		return forced == 1 and String(contract.get("target", "")) != RIVAL
	return String(contract.get("type", "")) in RACE_TYPES and String(contract.get("target", "")) != RIVAL \
		and posmod(hash("rival:" + String(contract.get("cid", ""))), 100) < CHANCE_PCT


func _on_live(cid: String, _objectives: Array) -> void:
	var c := Contracts.contract(cid)
	if c.is_empty() or not races_on(c) or races.any(func(r: Dictionary) -> bool: return r.cid == cid):
		return
	var level := CompoundLevel.current(self)
	var module: Node3D = level.call(&"get_module", String(c.get("module_id", ""))) if level and level.has_method(&"get_module") else null
	if module == null:
		return
	var share := float(posmod(hash("rival_delay:" + cid), 1000)) / 1000.0
	races.append({"cid": cid, "title": String(c.get("title", "the job")), "site": module.global_position,
		"go_at": Soldier._now() + lerpf(DELAY_S.x, DELAY_S.y, share), "squad": null, "soldiers": [], "held": 0.0, "state": "pending"})


## Host: sends race `r`'s team in now (tests skip the wait). False when there's nowhere unseen to come from yet.
func server_send(r: Dictionary) -> bool:
	var level := CompoundLevel.current(self)
	var response := EnemyResponse.of(level) if level else null
	if response == null:
		return false
	var at: Array[Vector2] = []
	for p: Soldier in MapNodes.players(level):
		at.append(Vector2(p.global_position.x, p.global_position.z))
	var edge: Vector3 = level.call(&"reinforcement_edge", at)
	if not edge.is_finite():
		return false
	var callsign := "VG%d" % (races.find(r) + 1)
	var squad := response._new_squad(callsign)
	var route: Array[Vector3] = [r.site]
	squad.patrol = route
	r.squad = squad
	r.soldiers = response._spawn_team(squad, callsign, SIZE, edge, r.site, CompoundLevel.PMC_LOADOUT.duplicate(), COMBAT, DISCIPLINE, "combat")
	r.state = "out"
	if not (r.soldiers as Array).is_empty():
		(r.soldiers[0] as Soldier).inventory.take(LEDGER)  # its leader's field ledger: story intel (a lead)
	Contracts._notify_all("Word on the net: a Vantage Group team is going for %s. Get there first." % r.title)
	print("[rival] %s: %d Vantage men from (%.0f, %.0f) for %s" % [callsign, (r.soldiers as Array).size(), edge.x, edge.z, r.cid])
	return true


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	_tick -= delta
	if _tick > 0.0:
		return
	var step := TICK_S - _tick
	_tick = TICK_S
	for r: Dictionary in races:
		match String(r.state):
			"pending":
				if Soldier._now() >= float(r.go_at):
					server_send(r)
			"out":
				server_step(r, step)


## Host: one look at race `r` after `dt` seconds: beaten when its men are all down, won once
## they've held the site SECURE_S with no friendly up near it.
func server_step(r: Dictionary, dt: float) -> void:
	var living := (r.soldiers as Array).filter(func(s: Variant) -> bool: return is_instance_valid(s) and (s as Soldier).vitals.is_up())
	if living.is_empty():
		r.state = "beaten"
		Contracts._notify_all("The Vantage team going for %s is down." % r.title)
		return
	var site: Vector3 = r.site
	var on_site := living.any(func(s: Soldier) -> bool: return _flat(s.global_position, site) <= SECURE_M)
	var contested := false
	var level := CompoundLevel.current(self)
	for s: Soldier in MapNodes.players(level) + MapNodes.squad_ai(level):
		if s.vitals.is_up() and _flat(s.global_position, site) <= CLEAR_M:
			contested = true
			break
	r.held = float(r.held) + dt if on_site and not contested else 0.0
	if float(r.held) >= SECURE_S:
		r.state = "won"
		if Contracts.objectives:
			Contracts.objectives.server_fail_contract(String(r.cid))
		Contracts._notify_all("Vantage got there first: %s is lost to them." % r.title)
		print("[rival] %s: Vantage holds the site; the contract fails" % r.cid)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
