class_name DynamicSim
extends Node
## Dynamic simulation (Captain, 2026-10-18: performance beyond the players' sightlines; "for now
## do dynamic sim", the ALiVE-style profile system in docs/virtualization.md saved for later).
## Inspired by Arma's: AI far from every player stops simulating (no brain, no physics, no
## animation, nothing sent over the net) and stays exactly where it is, kit, wounds and orders
## and all, until a player comes near again.
##
## Host only; one node per zone ("DynamicSim", ZoneLevel). Every TICK_S each AI soldier that
## isn't on our side is checked against every player:
## - asleep once further than SLEEP_M from all of them, awake again inside WAKE_M (the gap keeps
##   it from flickering);
## - never asleep while it's fighting (SquadAI.fighting), off the ground, down, in a vehicle, carrying or being
##   carried, mid-action (busy), or walking somewhere within SLEEP_M of a player (a patrol sent to
##   look, a QRF, hunters: whatever is coming at the squad keeps coming).
## Friendly AI (the squad) never sleeps. All numbers Proposed.
## Going to sleep he first SETTLES for SETTLE_S: his brain stops, he stands still and his model
## eases out of its stride, so he's frozen standing, not mid-step (Captain, 2026-10-19: "i see ai
## just still walking places" in MP: frozen walking poses out at range).

const TICK_S := 1.0
const SLEEP_M := 650.0
const WAKE_M := 550.0
## Further than this above or below the terrain he's off the ground (falling, or on a roof or a
## floor up: those keep simulating, so nobody is frozen mid-fall).
const OFF_GROUND_M := 1.0
const SETTLE_S := 1.5
const SETTLE_META := &"sim_settle"
const BRAIN_META := &"sim_brain_off"

## Host: how many sleep now (SessionLog's perf line).
var asleep := 0
var _tick := 0.0


func _init() -> void:
	name = "DynamicSim"


static func of(from: Node) -> DynamicSim:
	var lvl := CompoundLevel.current(from)
	return lvl.get_node_or_null(^"DynamicSim") as DynamicSim if lvl else null


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK_S
	server_tick()


## Host: sleep or wake every AI soldier by the rules above.
func server_tick() -> void:
	var lvl := get_parent() as CompoundLevel
	if lvl == null or not multiplayer.is_server():
		return
	var players: Array[Vector3] = []
	for p in lvl.players.get_children():
		var s := p as Soldier
		if s and not s.is_queued_for_deletion():
			players.append(s.global_position)
	var count := 0
	for n in lvl.ai.get_children():
		var s := n as Soldier
		if s == null or s.is_queued_for_deletion():
			continue
		var sleeping := s.process_mode == Node.PROCESS_MODE_DISABLED
		var want := should_sleep(s, players, sleeping or s.has_meta(SETTLE_META))
		if want and not sleeping:
			if not s.has_meta(SETTLE_META):
				_settle(s)  # first stand still: the model eases out of its stride
			elif Soldier._now() - float(s.get_meta(SETTLE_META)) >= SETTLE_S:
				s.remove_meta(SETTLE_META)
				s.process_mode = Node.PROCESS_MODE_DISABLED
				sleeping = true
		elif not want:
			if sleeping:
				s.process_mode = Node.PROCESS_MODE_INHERIT
			if sleeping or s.has_meta(SETTLE_META):
				_wake_brain(s)
		if want and sleeping:
			count += 1
	asleep = count


## Host: `s` stops where he is before he sleeps: no brain, no input, no speed.
static func _settle(s: Soldier) -> void:
	s.set_meta(SETTLE_META, Soldier._now())
	var brain := SquadAI.of(s)
	if brain and brain.process_mode != Node.PROCESS_MODE_DISABLED:
		brain.process_mode = Node.PROCESS_MODE_DISABLED
		s.set_meta(BRAIN_META, true)  # ours to turn back on (tests and vehicles switch brains off too)
	s.move_input = Vector2.ZERO
	s.want_sprint = false
	s.velocity = Vector3.ZERO


## Host: awake again (or wanted after all before he slept): his brain back on.
static func _wake_brain(s: Soldier) -> void:
	if s.has_meta(SETTLE_META):
		s.remove_meta(SETTLE_META)
	var brain := SquadAI.of(s)
	if brain and s.has_meta(BRAIN_META):
		brain.process_mode = Node.PROCESS_MODE_INHERIT
	if s.has_meta(BRAIN_META):
		s.remove_meta(BRAIN_META)


## Whether `s` should be asleep now, `sleeping` saying whether it is (the wake distance is
## shorter than the sleep one).
static func should_sleep(s: Soldier, players: Array[Vector3], sleeping: bool) -> bool:
	if s.faction == &"friendly" or players.is_empty():
		return false
	var near := INF
	for p in players:
		near = minf(near, Vector2(p.x - s.global_position.x, p.z - s.global_position.z).length())
	if near < (WAKE_M if sleeping else SLEEP_M):
		return false
	if not s.vitals.is_up() or is_instance_valid(s.vehicle) or s.carry_mode != &"" or is_instance_valid(s.carried_by) or s._is_busy():
		return false
	var lvl := CompoundLevel.current(s)
	if not sleeping and lvl and absf(s.global_position.y - lvl.ground_point(s.global_position).y) > OFF_GROUND_M:
		return false  # falling, or waiting for the ground under him to load: let him land first
	var brain := SquadAI.of(s)
	if brain:
		if brain.fighting():
			return false
		if brain._has_destination:
			for p in players:
				if Vector2(p.x - brain._destination.x, p.z - brain._destination.z).length() < SLEEP_M:
					return false  # on its way to the squad: it keeps coming
	return true
