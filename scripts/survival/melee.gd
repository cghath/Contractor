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

## The dead's attack (ZombieAI): a lunge and a bite or a clawing blow, harder from a fresh one and
## softer from an old one (DeadDecay.strike_mult: the attack's mult).
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
	if not attacker.vitals.is_up() or staggered(attacker) or attacker.has_meta(&"melee_winding"):
		return false
	var cost := float(attack.get("stamina", 0.0)) * Rpg.melee_stamina_mult(attacker)
	if cost > 0.0 and attacker.movement and attacker.movement.stamina < cost:
		_note(attacker, "too tired")
		return false
	if cost > 0.0 and attacker.movement:
		attacker.movement.stamina -= cost
	var g := guard_of(attacker)
	var now := Soldier._now()
	var windup := float(attack.get("windup", 0.4))
	if now < float(g.counter_until):
		windup = 0.0
		mult *= COUNTER_MULT
		g.counter_until = -1.0
	var land_at := now + windup
	attacker.set_meta(&"melee_winding", land_at)
	if windup <= 0.0:
		_land(attacker, attack, mult, land_at)
		return true
	attacker.get_tree().create_timer(windup, false).timeout.connect(func() -> void:
		if not is_instance_valid(attacker):
			return
		if attacker.vitals.is_up() and not staggered(attacker):
			_land(attacker, attack, mult, land_at)
		else:
			attacker.remove_meta(&"melee_winding")  # parried or put down in the windup: the swing is gone, the next one allowed (R2635: a stale flag kept it from ever swinging again)
	)
	return true


## Host: the zombie's strike on `victim` (ZombieAI, in reach): the same telegraphed attack.
static func server_strike(attacker: Soldier, _victim: Soldier) -> bool:
	return server_attack(attacker, ZOMBIE_ATTACK, DeadDecay.strike_mult(attacker))  # (the dead over time: a fresh one hits harder)


## A crawler's attack (call 19): grabs his legs: a shallow bite low and a trip (TRIP_S staggered:
## he can't swing or guard, and the dead about him get their bites in).
const TRIP_ATTACK := {"windup": 0.45, "heavy": false, "round_class": &"pistol", "depth": 0.03, "parts": [&"shin_l", &"shin_r", &"thigh_l", &"thigh_r"], "name": "grab", "trip": true}
const TRIP_S := 1.2


static func server_trip(attacker: Soldier, _victim: Soldier) -> bool:
	return server_attack(attacker, TRIP_ATTACK)


## Host: the strike lands: the first body in reach and in front, through its defence. `land_at`
## is when the windup said it would land: a parry is judged against that, not against when the
## timer got round to firing (a slow frame landed the strike late and turned a timely block into
## a plain block; survival_test R2593).
static func _land(attacker: Soldier, attack: Dictionary, mult: float, land_at := -1.0) -> void:
	attacker.remove_meta(&"melee_winding")
	var victim := target_in_front(attacker, float(attack.get("reach", REACH_M)))
	if victim == null:
		return
	var now := Soldier._now()
	if land_at < 0.0:
		land_at = now
	var g := guard_of(victim)
	if now < float(g.dodge_until) or land_at < float(g.dodge_until):
		_note(victim, "dodged")
		return
	var block_at := float(g.block_at)
	if block_at >= 0.0 and not staggered(victim):
		if block_at >= land_at - PARRY_WINDOW_S * Rpg.parry_window_mult(victim):
			guard_of(attacker).stagger_until = now + STAGGER_S
			g.counter_until = now + COUNTER_WINDOW_S
			_note(victim, "parried")
			Rpg.on_parry(victim)
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
static func target_in_front(attacker: Soldier, reach := REACH_M) -> Soldier:
	var fwd := -attacker.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var best: Soldier = null
	var best_d := reach
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
	if Children.on_harmed(victim, attacker):
		return  # a child: "You don't." (call 128)
	if mult <= 0.01:
		if String(attack.get("name", "")) == "bite":
			Nerve.server_close_call(victim)  # a bite dodged (Mind)
		return
	if bool(attack.get("shove", false)):
		guard_of(victim).stagger_until = Soldier._now() + SHOVE_STAGGER_S  # a shove: a second bought, little harm
		mult *= 0.3
	if bool(attack.get("trip", false)):
		guard_of(victim).stagger_until = Soldier._now() + TRIP_S  # tripped: no swing, no guard
		_note(victim, "tripped")
	var parts: Array = attack.get("parts", [Vitals.CHEST])
	var part: StringName = parts[absi(hash([attacker.name, victim.name, Soldier._now()])) % parts.size()]
	if not attacker.is_ai() and attack.has("kind"):
		part = _part_for(attacker, victim, part)  # a player's swing lands where he looks (the head, or not)
	var dir := (victim.global_position - attacker.global_position).normalized()
	var hit := {"round_class": StringName(attack.get("round_class", &"pistol")), "channel_depth": float(attack.get("depth", 0.05)) * mult,
		"direction": dir, "melee": String(attack.get("name", "blow")), "energy_j": float(attack.get("energy_j", 120.0)) * mult}
	if mult < 0.5:
		hit["superficial"] = true
	victim.vitals.server_hit(part, hit)
	if attack.has("kind") and victim.vitals.undead and victim.vitals.is_up():
		var g := guard_of(victim)  # a weapon's blow on one of the dead (MeleeWeapons.HIT_STAGGER_S)
		if bool(attack.get("heavy", false)):
			g.stagger_until = maxf(float(g.stagger_until), Soldier._now() + MeleeWeapons.HIT_STAGGER_S)  # a heavy rocks it back
		elif victim.has_meta(&"melee_winding"):
			# a light one spoils the lunge it's winding (staggered at its landing), no more: spammed stabs don't lock it down
			g.stagger_until = maxf(float(g.stagger_until), float(victim.get_meta(&"melee_winding")) + 0.05)
	_feedback(attacker, victim, part, dir)
	ClothingWear.on_hit(victim, part)  # the blow tears what covers it (call 122)
	if String(attack.get("name", "")) == "bite":
		Body.on_bitten(victim, part)  # the fever clock (phase D)
	Rpg.on_melee_hit(attacker, victim)
	if not attacker.vitals.undead:
		Survival.server_noise(attacker, attacker.global_position, SWING_HEARD_M, ZombieAI.HEAR_STEP)  # a blow landing: a small noise
	SessionLog.note("melee: %s's %s on %s (%s, x%.1f)" % [attacker.log_name(), String(attack.get("name", "blow")), victim.log_name(), part, mult])


## A blow that landed, seen and heard (player report 2026-11-10, "I can't tell I'm hitting
## something"): the guns' flesh impact (CompoundLevel.show_impact "body": its sound and red mark)
## where it struck, and a small camera jolt for a player who struck it.
const HIT_SHAKE := 0.18


static func _feedback(attacker: Soldier, victim: Soldier, part: StringName, dir: Vector3) -> void:
	var level := CompoundLevel.current(attacker)
	if level:
		var at := head_point(victim) if part in Vitals.UNDEAD_KILL_PARTS else victim.aim_point()
		level.show_impact.rpc(at - dir * 0.15, -dir, "body")
	if not attacker.is_ai():
		attacker._client_shake.rpc_id(attacker.owner_peer(), HIT_SHAKE)


## The middle of `s`'s head hitbox, wherever its stance put it (a crawler's is near the ground);
## head height over its origin when it has none.
static func head_point(s: Soldier) -> Vector3:
	for child in s.get_children():
		if child is Area3D and child.get_meta(&"body_part", &"") == Vitals.HEAD:
			for shape in child.get_children():
				if shape is CollisionShape3D:
					return (shape as Node3D).global_position
	return s.global_position + Vector3.UP * 1.62


static func _note(s: Soldier, what: String) -> void:
	if not s.is_ai():
		s._client_message.rpc_id(s.owner_peer(), what.capitalize())


const SHOVE_STAGGER_S := 0.6
const SWING_HEARD_M := 8.0
const HEAD_LOOK_DOT := 0.97  # looking within ~14 degrees of the head's centre (Proposed; was 0.985, ~10)


## Where a player's swing lands: the head when his view is on it (a heavy there drops a walker:
## MeleeWeapons.HEAD_ONE_HIT_J), else the part the profile rolled.
static func _part_for(attacker: Soldier, victim: Soldier, rolled: StringName) -> StringName:
	if attacker.camera == null:
		return rolled
	var to := (head_point(victim) - attacker.camera.global_position).normalized()  # (its head hitbox: a crawler's or a hunched one's isn't at 1.62 m)
	return Vitals.HEAD if (-attacker.camera.global_basis.z).dot(to) >= HEAD_LOOK_DOT else rolled


## The zombie `s` could kill quietly right now (MeleeInput, the interact key): one of the dead,
## unaware (its brain not chasing), within MeleeWeapons.SILENT_KILL_M in front of him, and he
## is behind it. Null when there is none.
static func silent_kill_target(s: Soldier) -> Soldier:
	var z := target_in_front(s, MeleeWeapons.SILENT_KILL_M)
	if z == null or not z.vitals.undead:
		return null
	var brain := ZombieAI.of(z)
	if brain != null and not brain.unaware():
		return null
	var its_fwd := -z.global_basis.z
	its_fwd.y = 0.0
	var to_me := s.global_position - z.global_position
	to_me.y = 0.0
	if its_fwd.normalized().dot(to_me.normalized()) > -0.2:
		return null  # it would see him coming
	return z


## Host: the silent kill (call 89): SILENT_KILL_S with the hands on it, then the blade in the
## head and no noise; if it turns to him in that time (its brain chasing), he's seen and it bites.
static func server_silent_kill(s: Soldier, has_blade: bool) -> void:
	if not has_blade:
		_note(s, "no blade")
		return
	var z := silent_kill_target(s)
	if z == null:
		return
	s.server_busy(MeleeWeapons.SILENT_KILL_S, "Silent kill")
	z.set_meta(&"held_quiet", true)
	s.get_tree().create_timer(MeleeWeapons.SILENT_KILL_S, false).timeout.connect(func() -> void:
		if not is_instance_valid(z) or not is_instance_valid(s):
			return
		z.remove_meta(&"held_quiet")
		if not s.vitals.is_up() or not z.vitals.is_up():
			return
		var brain := ZombieAI.of(z)
		if (brain != null and not brain.unaware()) or z.global_position.distance_to(s.global_position) > MeleeWeapons.SILENT_KILL_M + 0.5:
			_note(s, "seen")
			return
		z.vitals.server_hit(Vitals.HEAD, {"round_class": Vitals.PISTOL, "channel_depth": 0.08, "direction": (z.global_position - s.global_position).normalized(),
			"melee": "silent", "energy_j": 400.0})
		Rpg.on_silent_kill(s)
		SessionLog.note("melee: %s's silent kill on %s" % [s.log_name(), z.log_name()]))


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
