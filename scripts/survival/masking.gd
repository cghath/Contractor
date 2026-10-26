class_name Masking
extends RefCounted
## Masking and the bodies of the dead (docs/survival_seasons.md; call 53): static, host.
## - Gore smeared from a fresh corpse of the dead (the talk menu's "Smear its gore on you" on a
##   dead one: server_smear) hides a man's smell for MASK_S ("gore_until" on him: ZombieAI's smell
##   reads smell_x; the body lane's hygiene and infection read the same meta), and at night,
##   moving slowly among them, their sight of him is cut to NIGHT_SIGHT_X (sight_x).
## - Bodies as hazards: the dead's corpses left in a pile (PILE_N within PILE_M) rot: after ROT_H
##   world hours each hour they raise the zone's pressure and may breed a bloater into the crowd
##   (server_rot_hour); burning them on a lit pyre (server_light_pyre: they go, the fire's light and
##   smoke draw others: noise and pressure); burying them is the settlement's haul job's last
##   chore (server_bury_some: BURY_PER_H an hour in the settlement's radius).
## Every number here is Proposed.

const MASK_S := 600.0  # real seconds (5 world hours at DAY_MIN 48)
const SMEAR_M := 2.5
const SMEARS := 2  # a corpse gives this many smears
const NIGHT_SIGHT_X := 0.3
const SLOW_MPS := 1.6
const PILE_N := 4
const PILE_M := 6.0
const ROT_H := 24.0
const ROT_PRESSURE := 3.0
const BLOATER_CHANCE := 0.15
const PYRE_M := 6.0
const PYRE_NOISE_M := 90.0
const PYRE_PRESSURE := 15.0
const BURY_PER_H := 3


## Whether `s` is masked in the dead's gore now.
static func masked(s: Node) -> bool:
	return s != null and float(s.get_meta(&"gore_until", -1.0)) > Soldier._now()


## The dead's smell of `s`: none while masked.
static func smell_x(s: Node) -> float:
	return 0.0 if masked(s) else 1.0


## The dead's sight of `s` at darkness `dark`: masked and moving slowly at night, a fraction.
static func sight_x(s: Soldier, dark: float) -> float:
	if not masked(s) or dark < 0.5:
		return 1.0
	return NIGHT_SIGHT_X if Vector2(s.velocity.x, s.velocity.z).length() <= SLOW_MPS else 1.0


## Whether `body` is a corpse of the dead (every peer: the menu's check).
static func is_dead_one(body: Node) -> bool:
	var s := body as Soldier
	return s != null and s.faction == ZombieAI.INFECTED and s.vitals != null and s.vitals.is_dead()


## Host: `s` smears himself with `corpse`'s gore. "" or why not.
static func server_smear(s: Soldier, corpse: Soldier) -> String:
	if s == null or not is_dead_one(corpse):
		return "?"
	if s.global_position.distance_to(corpse.global_position) > SMEAR_M:
		return "Too far"
	if int(corpse.get_meta(&"smeared", 0)) >= SMEARS or corpse.has_meta(&"burnt"):
		return "There's nothing fresh left on it"
	corpse.set_meta(&"smeared", int(corpse.get_meta(&"smeared", 0)) + 1)
	s.set_meta(&"gore_until", Soldier._now() + MASK_S)
	s.set_meta(&"gore_at", Survival.day() + Survival.hour() / 24.0)  # (the body lane: hygiene, infection risk)
	Survival._tell(s, "You smear its rot over you: they won't smell you for a while")
	return ""


## The corpses of the dead in `level`.
static func corpses(level: Node) -> Array[Soldier]:
	var out: Array[Soldier] = []
	var ai: Node = level.get(&"ai") if level else null
	if ai == null:
		return out
	for n in ai.get_children():
		var s := n as Soldier
		if s and not s.is_queued_for_deletion() and is_dead_one(s):
			out.append(s)
	return out


## Host, every world hour: piles of the dead's corpses rot (past ROT_H since first seen): the
## zone's pressure rises at the pile, and now and then a bloater joins the crowd there. Returns the piles.
static func server_rot_hour(level: Node, rng: RandomNumberGenerator = null) -> int:
	var now_h := Moods.now_h()
	var list := corpses(level)
	for c: Soldier in list:
		if not c.has_meta(&"down_h"):
			c.set_meta(&"down_h", now_h)
	var piles := 0
	var seen := {}
	for c: Soldier in list:
		if seen.has(c) or now_h - float(c.get_meta(&"down_h", now_h)) < ROT_H:
			continue
		var pile: Array = list.filter(func(o: Soldier) -> bool: return o.global_position.distance_to(c.global_position) <= PILE_M)
		if pile.size() < PILE_N:
			continue
		for o: Soldier in pile:
			seen[o] = true
		piles += 1
		if level is ZoneLevel:
			Survival._raise_pressure(level, c.global_position, ROT_PRESSURE)
		var roll := rng.randf() if rng else randf()
		var crowd := ZoneDead.of(level)
		if crowd and roll < BLOATER_CHANCE:
			crowd.server_add(c.global_position + Vector3(2.0, 0.0, 0.0), "bloater")
	return piles


## Host: `s` lights the pyre piece `id`: the corpses within PYRE_M burn (gone), and the fire's
## light and smoke draw the dead (noise and pressure). "" or why not.
static func server_light_pyre(b: Builder, _s: Soldier, id: int) -> String:
	if not b.is_piece_built(id):
		return "?"
	var level := b.get_parent()
	var n := server_burn(level, b.piece_pos(id))
	return "" if n > 0 else "Nothing on it to burn"


## Host: the dead's corpses within PYRE_M of `at` burnt. Returns how many.
static func server_burn(level: Node, at: Vector3) -> int:
	var n := 0
	for c: Soldier in corpses(level):
		if c.global_position.distance_to(at) <= PYRE_M:
			c.set_meta(&"burnt", true)
			c.queue_free()
			n += 1
	if n > 0:
		Survival.server_noise(level, at, PYRE_NOISE_M, 0.4)
		if level is ZoneLevel:
			Survival._raise_pressure(level, at, PYRE_PRESSURE)
		Survival._journal_line("We burnt %d of the dead. The smoke will be seen." % n)
	return n


## Host (the haul job): up to BURY_PER_H of the dead's corpses in the settlement's radius buried
## an hour. Returns whether any were.
static func server_bury_some(st: Settlement, hours: float) -> bool:
	if st == null or not st.hosted():
		return false
	var cap := BURY_PER_H * maxi(1, roundi(hours))
	var n := 0
	for c: Soldier in corpses(st.level):
		if n >= cap:
			break
		if c.global_position.distance_to(Settlement.pos()) <= Settlement.radius():
			c.queue_free()
			n += 1
	if n > 0:
		Settlement.data()["buried"] = int(Settlement.data().get("buried", 0)) + n
	return n > 0
