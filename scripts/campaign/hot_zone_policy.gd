class_name HotZonePolicy
extends RefCounted
## A hot zone's hostile plan (docs/combined_arms.md 3.1; B2): EnemyCommand's rules (hold,
## reinforce, probe, counterattack at 3:1, contain, hunt, consolidate, reoccupy, decapitation). They
## keep running where they are, in EnemyCommand, unchanged: hot zones are tuned on them and
## missions_test checks them, so the hostile SideCommand in a hot zone tasks nothing itself (no
## needs) and reads EnemyCommand's picture and board. B2's call: moved in shape, not yet in code
## (section 10, B2.2); the code move is mechanical once hot zones have their own suite of [tactics]
## and operation lines to compare against.


func task_s() -> float:
	return float((SideCommand.data().get("task_s", {}) as Dictionary).get("hot", 30.0))


func start(_cmd: SideCommand) -> void:
	pass


func update(_cmd: SideCommand, _t: float) -> void:
	pass


func needs(_cmd: SideCommand, _t: float) -> Array:
	return []


## EnemyCommand's operations are this side's counterattacks.
func counterattack_seen(cmd: SideCommand) -> bool:
	var command := EnemyCommand.of(cmd)
	return command != null and command.operations.any(func(o: Dictionary) -> bool:
		return String(o.kind) == "counterattack" and String(o.state) in ["assembling", "attacking"])
