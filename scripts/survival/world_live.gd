class_name WorldLive
extends Node
## The world's groups near the players (docs/survival_world.md 4.4, call 21): host only, a child
## of the hosted SurvivalLevel ("WorldLive"). A group in the hosted zone within LIVE_M of a player
## gets bodies, its members' Person records as people with the AI they'd have:
## - settlers and scavengers (and the enclave's placeholder): PeopleLayer persons (kind
##   "survivor", side neutral: CivilianAI), dressed in their kit, about the group's place;
## - raiders and cultists: Soldiers of the hostile faction on a Squad of their own (hc_id
##   "wg_<id>") with SquadAI, their goal turned into SquadOrders (move / defend / attack), this
##   node standing in as the orders' commander (order_changed, radio, share_contact,
##   server_request). Their stance by the group's relation to the players (WorldGroup.stance):
##   hostile fires freely and attacks; wary holds fire and warns players off; neutral and
##   friendly hold fire.
## Live people are capped at LIVE_PEOPLE (sharing FIGHT_BUDGET with the dead's live bodies). Far
## again (past FOLD_M of every player), the bodies fold back into the records: where they are,
## their kit; deaths are recorded as they happen (the record dead where they fell, an event).
## What the players do where the group's people can see moves their standing: a player's hit on
## one of them, a kill of one of the dead near them (help); trading is the trade lane's call to
## WorldSim.server_player_trade. A raid or a hunt that reached the hosted zone ("assault") comes
## in hostile.

const NODE_NAME := "WorldLive"
## Proposed numbers.
const LIVE_M := 400.0
const FOLD_M := 500.0
const LIVE_PEOPLE := 24
const FIGHT_BUDGET := 64
const TICK_S := 1.0
const DECIDE_S := 20.0
const THINK_S := 0.5
const SPREAD_M := 6.0
const WARN_M := 25.0
const WARN_GAP_S := 40.0
const HELP_M := 30.0
const HIT_RELATION := -25.0
const KILL_RELATION := -60.0
const HELP_RELATION := 3.0
const HIT_GAP_S := 3.0
const WARN_LINES: Array[String] = ["That's close enough.", "Keep walking, friend.", "Not one step closer.", "We see you. Move on."]
const RAIDER_GUNS: Array[String] = ["akm", "ak74", "akm"]

var level: SurvivalLevel
## gid -> {"squad": Squad or null, "orders": SquadOrders or null, "bodies": {pid: Soldier}, "said": t}
var live := {}
var report_told := false
var _tick := 0.0
var _think := 0.0
var _decide := 0.0
var _hits := {}  # body instance id -> last harm "at" seen


static func of(from: Node) -> WorldLive:
	var lvl := SurvivalLevel.of(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NodePath(NODE_NAME)) as WorldLive if lvl else null


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	level = get_parent() as SurvivalLevel


func _process(delta: float) -> void:
	if level == null or not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or not Survival.running or not WorldSim.is_set_up():
		return
	_think += delta
	if _think >= THINK_S:
		_think = 0.0
		var now := Soldier._now()
		for gid: String in live:
			var so: SquadOrders = live[gid].get("orders")
			if so:
				so.tick(now)
	_tick += delta
	if _tick < TICK_S:
		return
	_tick = 0.0
	server_tick()


## Host, every TICK_S: groups in and out of range, standing from what the players did, the
## report of the catch-up told to the first player in.
func server_tick() -> void:
	var players := MapNodes.players(level).filter(func(p: Soldier) -> bool: return p.vitals.is_up())
	if players.is_empty():
		return
	_tell_report(players)
	var zone := WorldSim.hosted_zone()
	_decide += TICK_S
	var redecide := _decide >= DECIDE_S
	if redecide:
		_decide = 0.0
	for gid: String in WorldModel._sorted((WorldSim.section().get("groups", {}) as Dictionary).keys()):
		var g := WorldSim.group(gid)
		if g.is_empty() or String(g.kind) == "lone":
			continue
		var d := _nearest(players, _pos3(g))
		if live.has(gid):
			if not bool(g.alive) or String(g.zone) != zone or d > FOLD_M:
				server_fold(gid)
				continue
			_watch(gid, g, players)
			if redecide or bool(g.get("assault", false)):
				_orders(gid, g, players)
		elif bool(g.alive) and String(g.zone) == zone and (d <= LIVE_M or bool(g.get("assault", false))):
			server_spawn(gid)


func _nearest(players: Array, at: Vector3) -> float:
	var d := INF
	for p: Soldier in players:
		d = minf(d, Vector2(p.global_position.x, p.global_position.z).distance_to(Vector2(at.x, at.z)))
	return d


func _pos3(g: Dictionary) -> Vector3:
	var p := WorldGroup.pos2(g)
	return Vector3(p.x, 0.0, p.y)


## How many live people the budget allows now (LIVE_PEOPLE, and FIGHT_BUDGET with the dead).
func room() -> int:
	var n := 0
	for gid: String in live:
		n += (live[gid].bodies as Dictionary).size()
	return maxi(0, mini(LIVE_PEOPLE - n, FIGHT_BUDGET - Survival.zombies(level).size() - n))


## Host: group `gid`'s members as bodies about its place (as many as the budget allows).
func server_spawn(gid: String) -> int:
	var g := WorldSim.group(gid)
	if g.is_empty() or live.has(gid):
		return 0
	var n := mini(WorldGroup.size(g), room())
	if n <= 0:
		return 0
	var hostile := String(g.kind) in ["raiders", "cultists"]
	var entry := {"squad": null, "orders": null, "bodies": {}, "said": -1000.0}
	var squad: Squad = null
	if hostile:
		squad = Squad.new()
		squad.name = "WG_%s" % gid
		squad.faction = &"hostile"
		squad.hc_id = StringName("wg_" + gid)
		squad.callsign = String(g.name)
		level.add_child(squad)
		entry.squad = squad
	var centre := _pos3(g)
	var members: Array = g.members
	for i in n:
		var pid := String(members[i])
		var rec: Dictionary = WorldSim.people().get(pid, {})
		if rec.is_empty():
			continue
		var a := float(i) / maxf(1.0, n) * TAU
		var at := level.ground_point(centre + Vector3(cos(a), 0.0, sin(a)) * SPREAD_M * (1.0 + i * 0.15))
		var s := _spawn_soldier(rec, gid, i, at) if hostile else _spawn_person(rec, gid, at)
		if s == null:
			continue
		s.set_meta(&"world_person", pid)
		s.set_meta(&"world_group", gid)
		s.died_for_good.connect(_on_died.bind(gid, pid))
		(entry.bodies as Dictionary)[pid] = s
	if squad:
		var men := squad.members()
		if not men.is_empty():
			squad.hero = men[0]
			squad.leader = men[0]
		entry.orders = SquadOrders.new(squad, self)
	live[gid] = entry
	WorldSim.get_sim().mutate(func(w: Dictionary) -> void:
		var gg: Dictionary = (w.get("groups", {}) as Dictionary).get(gid, {})
		if not gg.is_empty():
			gg["live"] = true)
	_orders(gid, WorldSim.group(gid), MapNodes.players(level))
	SessionLog.note("survival world: %s (%s, %s) live, %d bodies" % [String(g.name), String(g.kind), WorldGroup.stance(g), (entry.bodies as Dictionary).size()])
	return (entry.bodies as Dictionary).size()


func _spawn_person(rec: Dictionary, gid: String, at: Vector3) -> Soldier:
	if level.people == null:
		return null
	var s := level.people.server_spawn_person({"name": ("W_%s_%s" % [gid, String(rec.id)]).validate_node_name(), "kind": "survivor", "side": "neutral",
		"label": String(rec.name), "pos": at, "look": String(rec.look), "face": String(rec.get("face", ""))})
	if s:
		_dress(s, rec)
	return s


func _spawn_soldier(rec: Dictionary, gid: String, i: int, at: Vector3) -> Soldier:
	var female := String(rec.get("sex", "m")) == "f"
	var loadout: Array = []
	var g := WorldSim.group(gid)
	if String(g.kind) == "raiders" or i % 3 == 0:
		var gun := RAIDER_GUNS[i % RAIDER_GUNS.size()]
		loadout = (CompoundLevel.HOSTILE_GUNS[gun] as Array).slice(0, 3)
	var s := level.spawn_soldier({"name": ("WG_%s_%s" % [gid, String(rec.id)]).validate_node_name(), "faction": "hostile", "hc_id": "wg_" + gid,
		"variant": String(rec.look), "body": VoxelArt.FEMALE if female else VoxelArt.MALE, "face": String(rec.get("face", "")),
		"person_name": String(rec.name), "nation": "US", "pos": at, "loadout": loadout, "role": "", "team": 0, "slot": -1,
		"combat": 0.4, "discipline": 0.4, "guard": false, "mode": "aware", "no_pockets": true, "spawn_id": "wg_" + String(rec.id)})
	if s:
		for e: Dictionary in rec.get("kit", []):
			if ItemDB.get_item(StringName(String(e.id))) != null:
				s.inventory.take(StringName(String(e.id)), int(e.get("count", 1)))
		s.set_meta(&"survivor_name", String(rec.name))
	return s


func _dress(s: Soldier, rec: Dictionary) -> void:
	s.inventory.strip()
	for e: Dictionary in rec.get("kit", []):
		if ItemDB.get_item(StringName(String(e.id))) != null:
			s.inventory.take(StringName(String(e.id)), int(e.get("count", 1)))
	s.set_meta(&"survivor_name", String(rec.name))


## The group's goal as orders (4.4): attack the players when hostile (or a raid / hunt has reached
## them), defend the home when settled, move to the goal's place, else hold; fire held unless hostile.
func _orders(gid: String, g: Dictionary, players: Array) -> void:
	var entry: Dictionary = live.get(gid, {})
	var so: SquadOrders = entry.get("orders")
	if so == null or g.is_empty():
		return
	var stance := WorldGroup.stance(g)
	if bool(g.get("assault", false)):
		stance = "hostile"
	var verb := "hold"
	var point := _pos3(g)
	var goal: Dictionary = g.get("goal", {})
	var home: Dictionary = g.get("home", {})
	if stance == "hostile" and not players.is_empty():
		verb = "attack"
		var target: Soldier = players[0]
		for p: Soldier in players:
			if p.global_position.distance_to(point) < target.global_position.distance_to(point):
				target = p
		point = target.global_position
	elif not home.is_empty() and String(home.zone) == WorldSim.hosted_zone():
		verb = "defend"
		var hp: Array = home.get("pos", [0.0, 0.0])
		point = Vector3(float(hp[0]), 0.0, float(hp[1]))
	elif String(goal.get("place", "")) != "" and String(goal.get("zone", "")) == WorldSim.hosted_zone():
		var pl := WorldRegions.place((WorldSim.section().zones as Dictionary).get(String(goal.zone), {}), String(goal.place))
		if not pl.is_empty():
			verb = "move"
			point = Vector3(float(pl.pos[0]), 0.0, float(pl.pos[1]))
	var key := "%s|%d|%d|%s" % [verb, roundi(point.x / 10.0), roundi(point.z / 10.0), stance]
	if String(entry.get("order_key", "")) == key:
		return
	entry["order_key"] = key
	var o := HcOrder.make("wg_" + gid, verb, [[point.x, point.z]], {"id": HcOrder.next_id(), "posture": {"roe": "free" if stance == "hostile" else "hold"}})
	so.give(o)


## What the players did where the group's people can see: a hit by a player (standing down, a
## grudge on a kill), a wary group's warning to players coming too close.
func _watch(gid: String, g: Dictionary, players: Array) -> void:
	var entry: Dictionary = live[gid]
	var sim := WorldSim.get_sim()
	for pid: String in (entry.bodies as Dictionary).keys():
		var s: Soldier = entry.bodies[pid]
		if not is_instance_valid(s):
			continue
		var info: Dictionary = s.get_meta(Harm.META, {})
		var at := float(info.get("at", -1.0))
		if bool(info.get("player", false)) and at > float(_hits.get(s.get_instance_id(), -1.0)) + HIT_GAP_S:
			_hits[s.get_instance_id()] = at
			sim.server_change_relation(gid, HIT_RELATION, "shot at by %s" % String(info.get("name", "a stranger")))
	if WorldGroup.stance(g) == "wary":
		var now := Soldier._now()
		for pid: String in (entry.bodies as Dictionary).keys():
			var s: Soldier = entry.bodies[pid]
			if not is_instance_valid(s) or not s.vitals.is_up():
				continue
			for p: Soldier in players:
				if p.global_position.distance_to(s.global_position) <= WARN_M and now - float(entry.said) > WARN_GAP_S:
					entry.said = now
					_say(s, WARN_LINES[absi(hash([gid, int(now)])) % WARN_LINES.size()])
					break


func _say(s: Soldier, text: String) -> void:
	var layer := SurvivorsLayer.find(level)
	if layer:
		layer.say(s, text)


## Host: one of the dead fell near a live group's people at a player's hand: help they saw.
func server_dead_down(z: Soldier) -> void:
	var info: Dictionary = z.get_meta(Harm.META, {})
	if not bool(info.get("player", false)):
		return
	for gid: String in live:
		for pid: String in (live[gid].bodies as Dictionary).keys():
			var s: Soldier = live[gid].bodies[pid]
			if is_instance_valid(s) and s.vitals.is_up() and s.global_position.distance_to(z.global_position) <= HELP_M:
				WorldSim.get_sim().server_change_relation(gid, HELP_RELATION)
				break


## A live member died: their record dead where they fell (by the dead's hand, or a player's: a
## grudge), out of the group, an event.
func _on_died(s: Soldier, gid: String, pid: String) -> void:
	var info: Dictionary = s.get_meta(Harm.META, {})
	var by_dead := String(info.get("faction", "")) == String(ZombieAI.INFECTED)
	var by_player := bool(info.get("player", false))
	var at := s.global_position
	var sim := WorldSim.get_sim()
	if live.has(gid):
		(live[gid].bodies as Dictionary).erase(pid)
	sim.mutate(func(w: Dictionary) -> void:
		var m := WorldSim.model()
		var g := m.group(gid)
		if g.is_empty() or not pid in (g.members as Array):
			return
		var nm := String((m.people.get(pid, {}) as Dictionary).get("name", pid))
		m.person_dies(pid, g, "killed by %s" % ("the dead" if by_dead else String(info.get("name", "someone"))), by_dead, {"pos": [at.x, at.z]})
		var rec: Dictionary = m.people.get(pid, {})
		rec["body_pos"] = [at.x, at.y, at.z]
		m.event(String(g.zone), "death", [gid] + (["player"] if by_player else []), "%s of %s was killed%s" % [nm, String(g.name), " by %s" % String(info.get("name", "")) if by_player else (" by the dead" if by_dead else "")])
		if WorldGroup.size(g) == 0:
			m._group_dies(g, "wiped out"))
	if by_player:
		sim.server_change_relation(gid, KILL_RELATION, "%s killed one of ours" % String(info.get("name", "a stranger")))


## Host: group `gid`'s bodies folded back into its records (where they stand, their kit).
func server_fold(gid: String) -> void:
	var entry: Dictionary = live.get(gid, {})
	live.erase(gid)
	var sum := Vector3.ZERO
	var n := 0
	for pid: String in (entry.get("bodies", {}) as Dictionary).keys():
		var s: Soldier = entry.bodies[pid]
		if not is_instance_valid(s):
			continue
		var rec: Dictionary = WorldSim.people().get(pid, {})
		if s.vitals.is_up() and not rec.is_empty():
			SurvivorPerson.set_pos(rec, s.global_position)
			rec.kit = Survival.kit_of(s.inventory)
			sum += s.global_position
			n += 1
		s.queue_free()
	var sq: Squad = entry.get("squad")
	if sq and is_instance_valid(sq):
		sq.queue_free()
	var centre := sum / n if n > 0 else Vector3.INF
	WorldSim.get_sim().mutate(func(w: Dictionary) -> void:
		var g: Dictionary = (w.get("groups", {}) as Dictionary).get(gid, {})
		if g.is_empty():
			return
		g.erase("live")
		g.erase("assault")
		if centre.is_finite():
			g.pos = [snappedf(centre.x, 0.1), snappedf(centre.z, 0.1)])


## Host: everything live folded back (the level going: a save, a crossing).
func server_fold_all() -> void:
	for gid: String in live.keys():
		server_fold(gid)


func _exit_tree() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and WorldSim.get_sim():
		for gid: String in live.keys():
			WorldSim.get_sim().mutate(func(w: Dictionary) -> void:
				var g: Dictionary = (w.get("groups", {}) as Dictionary).get(gid, {})
				g.erase("live")
				g.erase("assault"))
		live.clear()


## The catch-up's report, told to the players once they're in.
func _tell_report(players: Array) -> void:
	if report_told:
		return
	report_told = true
	var r: Dictionary = WorldSim.section().get("away_report", {})
	if r.is_empty() or bool(r.get("told", false)):
		return
	r.told = true
	var lines: Array = r.get("lines", [])
	var text := "While you were away (%d hours): %s" % [roundi(float(r.get("hours", 0.0))), "; ".join(lines.slice(-4)) if not lines.is_empty() else "nothing near the farm changed"]
	for p: Soldier in players:
		Survival._tell(p, text)


# --- SquadOrders' commander (the calls it makes) -------------------------------------------------

func order_changed(_o: Dictionary) -> void:
	pass


func radio(_so: SquadOrders, _kind: String, _text: String, _pos: Variant = null) -> void:
	pass  # (no radio net for the world's groups: the intel lane's radio may listen later)


func share_contact(_so: SquadOrders, _cluster: Dictionary) -> void:
	pass


func server_request(_so: SquadOrders, _kind: String, _text: String, answer: Callable, default_yes: bool) -> int:
	answer.call(default_yes)
	return 0
