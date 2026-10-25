class_name Melee
extends RefCounted
## Melee (docs/survival.md S2b; Captain, 2026-10-25: "melee weapons now and a melee system e.g
## dodge, sidestep, block, parry, counter"). Host-authoritative, the same rules for players,
## companions and the dead.
##
## An attack is telegraphed: a WINDUP (the arm goes back, the dead lunge), then the strike lands
## at its end on whoever is still in REACH in front of the attacker, unless the defender:
## - **dodged** or **sidestepped** in time: a short burst of movement with DODGE_IFRAMES_S in
##   which nothing lands (a sidestep is the short, cheap one), for stamina;
## - is **blocking** (the aim button with a melee weapon, or a long gun held across him): the hit
##   is turned, BLOCK_KEEP of it gets through as a jolt, it costs stamina, and a heavy blow or an
##   empty stamina bar breaks the guard;
## - **parried**: began a block within PARRY_WINDOW_S before the strike landed: nothing gets
##   through, the attacker staggers (STAGGER_S), and the defender has COUNTER_WINDOW_S to
##   **counter**: his next attack is instant (no windup) and does COUNTER_MULT.
## The defence state lives on the body (meta GUARD), set on the host from the owner's requests
## (MeleeInput, the player side) or by a brain.

const GUARD := &"melee_guard"  # {"block_at": t or -1, "dodge_until": t, "counter_until": t, "stagger_until": t}
const REACH_M := 1.6
const ARC_DOT := 0.35  # in front of the attacker: within ~70 degrees of his facing
const PARRY_WINDOW_S := 0.25
const COUNTER_WINDOW_S := 1.2
const COUNTER_MULT := 2.0
const STAGGER_S := 1.1
const BLOCK_KEEP := 0.2
const BLOCK_STAMINA := 0.15
const DODGE_IFRAMES_S := 0.35
const SIDESTEP_IFRAMES_S := 0.2
const DODGE_STAMINA := 0.25
const SIDESTEP_STAMINA := 0.1

## The dead's attack (ZombieAI): a lunge and a bite or a clawing blow.
const ZOMBIE_ATTACK := {"windup": 0.55, "heavy": false, "round_class": &"pistol", "depth": 0.04, "parts": [&"forearm_l", &"forearm_r", &"upper_arm_l", &"upper_arm_r", &"neck", &"chest"], "name": "bite"}


static func guard_of(s: Soldier) -> Dictionary:
	if not s.has_meta(GUARD):
		s.set_meta(GUARD, {"block_at": -1.0, "dodge_until": -1.0, "counter_until": -1.0, "stagger_until": -1.0})
	return s.get_meta(GUARD)


## Whether `s` is staggered (a parried attacker): he can't attack or defend.
static func staggered(s: Soldier) -> bool:
	return Soldier._now() < float(guard_of(s).stagger_until)


## Host: `attacker` starts an attack on whoever's in front of him (`attack`: ZOMBIE_ATTACK or a
## weapon's melee profile, MeleeWeapons). It lands after its windup (none when he's countering).
## Returns false if he can't attack now (staggered, down).
static func server_attack(attacker: Soldier, attack: Dictionary, mult := 1.0) -> bool:
	if not attacker.vitals.is_up() or staggered(attacker):
		return false
	var g := guard_of(attacker)
	var now := Soldier._now()
	var windup := float(attack.get("windup", 0.4))
	if now < float(g.counter_until):
		windup = 0.0
		mult *= COUNTER_MULT
		g.counter_until = -1.0
	attacker.set_meta(&"melee_winding", now + windup)
	if windup <= 0.0:
		_land(attacker, attack, mult)
		return true
	attacker.get_tree().create_timer(windup, false).timeout.connect(func() -> void:
		if is_instance_valid(attacker) and attacker.vitals.is_up() and not staggered(attacker):
			_land(attacker, attack, mult))
	return true


## Host: the zombie's strike on `victim` (ZombieAI, in reach): the same telegraphed attack.
static func server_strike(attacker: Soldier, _victim: Soldier) -> bool:
	return server_attack(attacker, ZOMBIE_ATTACK)


## Host: the strike lands: the first body in reach and in front, through its defence.
static func _land(attacker: Soldier, attack: Dictionary, mult: float) -> void:
	attacker.remove_meta(&"melee_winding")
	var victim := target_in_front(attacker)
	if victim == null:
		return
	var now := Soldier._now()
	var g := guard_of(victim)
	if now < float(g.dodge_until):
		_note(victim, "dodged")
		return
	var block_at := float(g.block_at)
	if block_at >= 0.0 and not staggered(victim):
		if now - block_at <= PARRY_WINDOW_S:
			guard_of(attacker).stagger_until = now + STAGGER_S
			g.counter_until = now + COUNTER_WINDOW_S
			_note(victim, "parried")
			return
		var stamina := victim.movement.stamina if victim.movement else 1.0
		if not bool(attack.get("heavy", false)) and stamina >= BLOCK_STAMINA:
			if victim.movement:
				victim.movement.stamina = maxf(0.0, victim.movement.stamina - BLOCK_STAMINA)
			mult *= BLOCK_KEEP
			_note(victim, "blocked")
		else:
			g.block_at = -1.0  # the guard breaks
			_note(victim, "guard broken")
	_hit(attacker, victim, attack, mult)


## The nearest living body of another side within REACH_M in front of `attacker`, or null.
static func target_in_front(attacker: Soldier) -> Soldier:
	var fwd := -attacker.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var best: Soldier = null
	var best_d := REACH_M
	for n in attacker.get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s == attacker or s.faction == attacker.faction or not s.vitals.is_up():
			continue
		var to := s.global_position - attacker.global_position
		to.y = 0.0
		var d := to.length()
		if d > best_d or (d > 0.3 and fwd.dot(to / d) < ARC_DOT):
			continue
		best = s
		best_d = d
	return best


## Host: the blow itself, through the wound model (Vitals.server_hit): a shallow wound to one of
## the attack's parts (a blade cuts, a blunt weapon bruises and breaks; the dead's head goes to a
## blow aimed there, Vitals.undead).
static func _hit(attacker: Soldier, victim: Soldier, attack: Dictionary, mult: float) -> void:
	if mult <= 0.01:
		return
	var parts: Array = attack.get("parts", [Vitals.CHEST])
	var part: StringName = parts[absi(hash([attacker.name, victim.name, Soldier._now()])) % parts.size()]
	var dir := (victim.global_position - attacker.global_position).normalized()
	var hit := {"round_class": StringName(attack.get("round_class", &"pistol")), "channel_depth": float(attack.get("depth", 0.05)) * mult,
		"direction": dir, "melee": String(attack.get("name", "blow")), "energy_j": float(attack.get("energy_j", 120.0)) * mult}
	if mult < 0.5:
		hit["superficial"] = true
	victim.vitals.server_hit(part, hit)
	SessionLog.note("melee: %s's %s on %s (%s, x%.1f)" % [attacker.log_name(), String(attack.get("name", "blow")), victim.log_name(), part, mult])


static func _note(s: Soldier, what: String) -> void:
	if not s.is_ai():
		s._client_message.rpc_id(s.owner_peer(), what.capitalize())


## Host: `s` raises a block now (a parry if the blow lands within PARRY_WINDOW_S), or drops it.
static func server_block(s: Soldier, on: bool) -> void:
	guard_of(s).block_at = Soldier._now() if on and not staggered(s) else -1.0


## Host: `s` dodges (`sidestep`: the short one) if he has the stamina: DODGE_IFRAMES_S in which no
## blow lands. Returns whether he did (the movement itself is the owner's: MeleeInput).
static func server_dodge(s: Soldier, sidestep := false) -> bool:
	var cost := SIDESTEP_STAMINA if sidestep else DODGE_STAMINA
	if staggered(s) or (s.movement and s.movement.stamina < cost):
		return false
	if s.movement:
		s.movement.stamina -= cost
	guard_of(s).dodge_until = Soldier._now() + (SIDESTEP_IFRAMES_S if sidestep else DODGE_IFRAMES_S)
	return true
