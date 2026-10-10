class_name WoundModel
extends RefCounted
## The ACE3/KAT-style wound model behind Vitals (design doc, "Damage and medical"): 6 L of
## blood, wounds per body part that bleed at a rate scaled by the heart's output, pain
## from 0 to 1, fractures, chest wounds, concussion and impact. Blood loss, pain and
## breathing decide when a soldier slows, goes unconscious, arrests or dies.
##
## The host owns the real state and steps it (advance). Every other peer holds a copy
## rebuilt from to_net()/apply_net(), so every query works everywhere. Pure data: no nodes,
## no signals (Vitals turns state changes into its signals). Values the design doc marks as
## proposed are constants here, for Captain's playtests.

const BLOOD_L := 6.0
## Shares of blood volume lost (design doc).
const UNCONSCIOUS_LOST := 0.40
const ARREST_LOST := 0.50
const EFFECTS_FROM_LOST := 0.15   # blood-loss effects start here and reach full strength at 40%
const NO_SPRINT_LOST := 0.30
## Cardiac arrest: the unit dies when this window runs out with no heart rate.
const ARREST_WINDOW_S := 600.0

## Blood-loss effects at full strength (s = 1 at 40% lost; linear from 15%). These give the
## design doc's table: +60% sway, 64% stamina recovery and 88% speed at 30% lost.
const BLOOD_SWAY := 1.0
const BLOOD_STAMINA := 0.6
const BLOOD_SPEED := 0.2

## Bleed rates in L/min at full blood for a fully hit wound (design doc). Vessel rates are
## in BodyMap.VESSELS.
const MUSCLE_RATE := 0.25
const GRAZE_RATE := 0.03
const FEMUR_RATE := 0.05    # broken femur, internal, until splinted
const CHEST_RATE := 0.15    # proposed: blood into the chest cavity from a lung or chest wall
const HEART_RATE := 2.0     # proposed
## Muscle wound size by round class (proposed): fragments make small wounds.
const MUSCLE_CLASS_MULT := {&"pistol": 0.7, &"intermediate": 1.0, &"full_power": 1.2, &"fragment": 0.4}
## Fracture chance when a bone is hit (design doc).
const FRACTURE_CHANCE := {&"pistol": 0.25, &"intermediate": 0.70, &"full_power": 0.95, &"fragment": 0.20}

## Pain added per hit, as [min, max] (design doc: arterial or rifle 0.6-0.9, graze 0.1-0.2;
## pistol and fragment proposed).
const PAIN_SEVERE := Vector2(0.6, 0.9)
const PAIN_PISTOL := Vector2(0.3, 0.5)
const PAIN_FRAGMENT := Vector2(0.1, 0.25)
const PAIN_GRAZE := Vector2(0.1, 0.2)
const PAIN_FRACTURE := 0.15
## Untreated fractures keep pain at least this high (a broken leg is heavy pain).
const PAIN_FLOOR_LEG := 0.35
const PAIN_FLOOR_ARM := 0.2
const PAIN_FLOOR_RIB := 0.15
## Pain fades over about 15 minutes, impact over about 5.
const PAIN_FADE_PER_S := 1.0 / 900.0
const IMPACT_FADE_PER_S := 1.0 / 300.0
## Knockout: pain at or over the threshold, 0.9 at full blood falling linearly to 0.6 at
## 30% lost; at 40% lost you're out regardless.
const KNOCKOUT_PAIN_FULL := 0.9
const KNOCKOUT_PAIN_LOW := 0.6
const KNOCKOUT_PAIN_LOW_AT := 0.30
## Once stable, an unconscious casualty rolls to wake every 15 s at 15%.
const WAKE_ROLL_S := 15.0
const WAKE_CHANCE := 0.15
## Stable means not in arrest, under 40% lost and bleeding less than this (L/min).
const STABLE_BLEED_L_MIN := 0.05

## Heart hit: cardiac arrest within seconds. Chest: without a seal, a 50% chance of tension
## pneumothorax 60-120 s later, then cardiac arrest about 90 s after.
const HEART_ARREST_S := Vector2(2.0, 6.0)
const TENSION_CHANCE := 0.5
const TENSION_DELAY_S := Vector2(60.0, 120.0)
const TENSION_ARREST_S := 90.0

## Extra sway (added to 1.0) from pain at 1.0, a broken arm, concussion and a stagger.
const PAIN_SWAY := 0.6
const BROKEN_ARM_SWAY := 1.0
const CONCUSSION_SWAY := 0.8
const STAGGER_SWAY := 1.0
const BROKEN_LEG_SPEED := 0.6     # walk only
const STAGGER_SPEED := 0.5
const BROKEN_ARM_RELOAD := 1.6
const CONCUSSION_TURN := 0.6
const RIB_STAMINA := 0.7

## Impact (shock) from rounds armor stopped (design doc table).
const PLATE_IMPACT_PAIN := {&"pistol": 0.05, &"intermediate": 0.15, &"full_power": 0.3}
const HELMET_IMPACT_PAIN := {&"pistol": 0.15, &"intermediate": 0.3, &"full_power": 0.45}
const CONCUSSION_CHANCE := {&"pistol": 0.1, &"intermediate": 0.4, &"full_power": 0.8}
const STAGGER_S := 0.8            # intermediate plate stop: brief stagger
const WINDED_S := 4.0             # full-power plate stop: stamina emptied for a few seconds
## Concussion: possible knockout for 5-20 s, then 60 s of blur, sway and slow turning; a
## second one in the same fight lasts twice as long.
const CONCUSSION_KO_CHANCE := 0.5
const CONCUSSION_KO_S := Vector2(5.0, 20.0)
const CONCUSSION_S := 60.0
const SAME_FIGHT_S := 600.0
## Cracked rib from a plate stop, only within these ranges (design doc), at these odds (proposed).
const RIB_RANGE_M := {&"pistol": 30.0, &"intermediate": 100.0, &"full_power": 200.0}
const RIB_CRACK_CHANCE := {&"pistol": 0.3, &"intermediate": 0.5, &"full_power": 0.7}
const RIB_PAIN := 0.1
## A helmet stop is fatal only where it would be in real life: a full-power rifle round
## arriving with at least this energy (or, energy unknown, within this range), at these odds.
const HELMET_FATAL_ENERGY_J := 2400.0
const HELMET_FATAL_RANGE_M := 200.0
const HELMET_FATAL_CHANCE := 0.35

## Share of blood, 0 to 1.
var blood := 1.0
## Pain from wounds and trauma (fades over ~15 min) and from impact (fades over ~5 min).
var pain_wounds := 0.0
var impact := 0.0
## One Dictionary per wound: part, kind, rate (L/min at full blood), treated, name (vessel
## or bone), and for chest wounds tension_in / arrest_in (seconds, -1 when not pending).
var wounds: Array[Dictionary] = []
var unconscious := false
var arrest := false
var dead := false
var arrest_left := 0.0
var concussion_left := 0.0
var knockout_left := 0.0
var winded_left := 0.0
var stagger_left := 0.0
var rng := RandomNumberGenerator.new()

var _time := 0.0
var _last_concussion := -INF
var _heart_arrest_in := -1.0
var _wake_roll_in := WAKE_ROLL_S
var _knockout_only := false     # out only because of a concussion knockout
var _heal_left := 0.0           # stopgap treatment in progress (seconds)
var _heal_pain_per_s := 0.0
var _heal_queue: Array[Dictionary] = []   # wounds still to treat, in order
var _heal_every := 0.0
var _heal_next := 0.0


# --- Queries --------------------------------------------------------------------------

func lost() -> float:
	return 1.0 - blood


## Blood-loss effect strength: 0 up to 15% lost, 1 at 40%.
func shock() -> float:
	return clampf((lost() - EFFECTS_FROM_LOST) / (UNCONSCIOUS_LOST - EFFECTS_FROM_LOST), 0.0, 1.0)


func pain() -> float:
	var floor_pain := 0.0
	for w in wounds:
		if w.kind == "fracture" and not w.treated:
			floor_pain = maxf(floor_pain, PAIN_FLOOR_LEG if w.name in BodyMap.LEG_BONES else PAIN_FLOOR_ARM)
		elif w.kind == "rib":
			floor_pain = maxf(floor_pain, PAIN_FLOOR_RIB)
	return clampf(maxf(pain_wounds + impact, floor_pain), 0.0, 1.0)


func knockout_threshold() -> float:
	return lerpf(KNOCKOUT_PAIN_FULL, KNOCKOUT_PAIN_LOW, clampf(lost() / KNOCKOUT_PAIN_LOW_AT, 0.0, 1.0))


static func is_bleeding(w: Dictionary) -> bool:
	return float(w.rate) > 0.0 and not w.treated


## Untreated bleeding in L/min at full blood (the wounds' own rates).
func wound_bleed_rate() -> float:
	var rate := 0.0
	for w in wounds:
		if is_bleeding(w):
			rate += float(w.rate)
	return rate


## The heart's output, 0 to 1: proportional to the blood left, nothing in arrest.
func cardiac_output() -> float:
	return 0.0 if arrest or dead else blood


## Blood actually leaving the body now, in L/min.
func bleed_rate() -> float:
	return wound_bleed_rate() * cardiac_output()


func has_fracture(bones: Array, untreated_only: bool) -> bool:
	for w in wounds:
		if w.kind == "fracture" and w.name in bones and not (untreated_only and w.treated):
			return true
	return false


func has_kind(kind: String) -> bool:
	return wounds.any(func(w: Dictionary) -> bool: return w.kind == kind)


func is_healing() -> bool:
	return _heal_left > 0.0


func is_stable() -> bool:
	return not arrest and not dead and lost() < UNCONSCIOUS_LOST and bleed_rate() < STABLE_BLEED_L_MIN


func sway_mult() -> float:
	var sway := 1.0 + BLOOD_SWAY * shock() + PAIN_SWAY * pain()
	if has_fracture(BodyMap.ARM_BONES, true):
		sway += BROKEN_ARM_SWAY
	if concussion_left > 0.0:
		sway += CONCUSSION_SWAY
	if stagger_left > 0.0:
		sway += STAGGER_SWAY
	return sway


func speed_mult() -> float:
	var speed := 1.0 - BLOOD_SPEED * shock()
	if has_fracture(BodyMap.LEG_BONES, true):
		speed *= BROKEN_LEG_SPEED
	if stagger_left > 0.0:
		speed *= STAGGER_SPEED
	return speed


func stamina_mult() -> float:
	if winded_left > 0.0:
		return 0.0
	var stamina := 1.0 - BLOOD_STAMINA * shock()
	if has_kind("rib"):
		stamina *= RIB_STAMINA
	return stamina


## A splinted leg still can't sprint until the mission ends (design doc).
func can_sprint() -> bool:
	return not unconscious and not dead and lost() < NO_SPRINT_LOST and winded_left <= 0.0 \
		and not has_fracture(BodyMap.LEG_BONES, false)


func reload_mult() -> float:
	return BROKEN_ARM_RELOAD if has_fracture(BodyMap.ARM_BONES, true) else 1.0


func turn_mult() -> float:
	return CONCUSSION_TURN if concussion_left > 0.0 else 1.0


## 0 (fine) to 1: blood loss counts for up to 0.4, the worse of pain and untreated wounds
## for up to 0.6, so a kit (which treats wounds and pain, not blood) brings it down.
func injury() -> float:
	var wound_term := clampf(wound_bleed_rate() / 0.5, 0.0, 1.0)
	if has_fracture(BodyMap.LEG_BONES + BodyMap.ARM_BONES, true):
		wound_term = minf(wound_term + 0.3, 1.0)
	var blood_term := clampf(lost() / UNCONSCIOUS_LOST, 0.0, 1.0)
	return clampf(0.4 * blood_term + 0.6 * maxf(pain(), wound_term), 0.0, 1.0)


# --- Host-side changes ----------------------------------------------------------------

## A round or fragment reached `part` along `channel` (BodyMap.trace). Returns the new wounds.
func add_hit(part: StringName, channel: Dictionary, round_class: StringName) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if dead:
		return added
	var rifle := round_class == &"intermediate" or round_class == &"full_power"
	if part == &"head" and round_class != &"fragment":
		kill()  # an unprotected head hit past the helmet is fatal
		return added
	if &"brain" in channel.organs:
		kill()
		return added
	var hit_pain := 0.0
	if channel.graze:
		added.append(_add_wound(part, "graze", GRAZE_RATE))
		hit_pain = rng.randf_range(PAIN_GRAZE.x, PAIN_GRAZE.y)
	else:
		var pain_range := PAIN_SEVERE if rifle else (PAIN_PISTOL if round_class == &"pistol" else PAIN_FRAGMENT)
		for v: Dictionary in channel.vessels:
			added.append(_add_wound(part, v.kind, float(v.rate) * float(v.share), v.name))
			if v.kind != BodyMap.VENOUS and float(v.share) >= 0.5:
				pain_range = PAIN_SEVERE  # an arterial wound hurts like a rifle wound
		if channel.vessels.is_empty():
			added.append(_add_wound(part, "muscle", MUSCLE_RATE * float(MUSCLE_CLASS_MULT.get(round_class, 1.0))))
		hit_pain = rng.randf_range(pain_range.x, pain_range.y)
		if &"heart" in channel.organs:
			added.append(_add_wound(part, "heart", HEART_RATE, &"heart"))
			if _heart_arrest_in < 0.0 and not arrest:
				_heart_arrest_in = rng.randf_range(HEART_ARREST_S.x, HEART_ARREST_S.y)
		var lung: bool = &"lung_l" in channel.organs or &"lung_r" in channel.organs
		# A bullet through the chest wall opens the cavity; a fragment has to reach a lung.
		if lung or (part == &"chest" and round_class != &"fragment" and float(channel.depth) >= BodyMap.CHEST_WALL_M):
			var chest := _add_wound(&"chest", "chest", CHEST_RATE, &"lung_l" if &"lung_l" in channel.organs else &"lung_r")
			if rng.randf() < TENSION_CHANCE:
				chest.tension_in = rng.randf_range(TENSION_DELAY_S.x, TENSION_DELAY_S.y)
			added.append(chest)
		for bone: StringName in channel.bones:
			if has_fracture([bone], false) or rng.randf() >= float(FRACTURE_CHANCE.get(round_class, 0.5)):
				continue
			added.append(_add_wound(part, "fracture", FEMUR_RATE if bone.begins_with("femur") else 0.0, bone))
			hit_pain += PAIN_FRACTURE
	pain_wounds = minf(pain_wounds + hit_pain, 1.0)
	update_state(0.0)
	return added


## A round armor stopped still lands on `part` (design doc impact table).
func add_impact(part: StringName, round_class: StringName, distance: float, energy_j: float) -> void:
	if dead:
		return
	if part == &"head" or part == &"face":
		impact += float(HELMET_IMPACT_PAIN.get(round_class, 0.0))
		if round_class == &"full_power":
			var lethal := energy_j >= HELMET_FATAL_ENERGY_J if energy_j >= 0.0 else distance <= HELMET_FATAL_RANGE_M
			if lethal and rng.randf() < HELMET_FATAL_CHANCE:
				kill()
				return
		if rng.randf() < float(CONCUSSION_CHANCE.get(round_class, 0.0)):
			_concuss()
	else:
		impact += float(PLATE_IMPACT_PAIN.get(round_class, 0.0))
		if round_class == &"intermediate":
			stagger_left = maxf(stagger_left, STAGGER_S)
		elif round_class == &"full_power":
			stagger_left = maxf(stagger_left, STAGGER_S)
			winded_left = maxf(winded_left, WINDED_S)
		if distance <= float(RIB_RANGE_M.get(round_class, -1.0)) and rng.randf() < float(RIB_CRACK_CHANCE.get(round_class, 0.0)):
			if not has_kind("rib"):
				_add_wound(&"chest", "rib", 0.0, &"rib")
			impact += RIB_PAIN
	impact = minf(impact, 1.0)
	update_state(0.0)


## Generic trauma (the legacy damage call): pain and an immediate share of blood lost.
func add_trauma(pain_amount: float, blood_share: float) -> void:
	if dead:
		return
	pain_wounds = minf(pain_wounds + pain_amount, 1.0)
	blood = maxf(blood - blood_share, 0.0)
	update_state(0.0)


func kill() -> void:
	dead = true
	arrest = false
	unconscious = false
	_heal_left = 0.0


## Starts stopgap treatment (IFAK or trauma kit until the wave 2 kit): stops bleeding wound
## by wound, worst first, over `seconds`, and takes `pain_relief` off pain. Replaces one in
## progress.
func start_treatment(pain_relief: float, seconds: float) -> void:
	seconds = maxf(seconds, 0.01)
	_heal_left = seconds
	_heal_pain_per_s = pain_relief / seconds
	_heal_queue.clear()
	for w in wounds:
		if is_bleeding(w) or (w.kind == "chest" and not w.treated):
			_heal_queue.append(w)
	_heal_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.rate) > float(b.rate))
	_heal_every = seconds / maxf(_heal_queue.size(), 1)
	_heal_next = _heal_every


## Stopgap revive (IFAK or trauma kit): stops all bleeding, tops blood up to `min_blood`
## (stopgap until IV in wave 3), ends arrest, caps pain at `pain_cap` and wakes the casualty.
func revive(min_blood: float, pain_cap: float) -> void:
	if dead:
		return
	for w in wounds:
		_stop_bleeding(w)
	blood = maxf(blood, min_blood)
	arrest = false
	arrest_left = 0.0
	_heart_arrest_in = -1.0
	knockout_left = 0.0
	var total := pain_wounds + impact
	if total > pain_cap:
		pain_wounds *= pain_cap / total
		impact *= pain_cap / total
	unconscious = false
	_knockout_only = false


func reset() -> void:
	blood = 1.0
	pain_wounds = 0.0
	impact = 0.0
	wounds.clear()
	unconscious = false
	arrest = false
	dead = false
	arrest_left = 0.0
	concussion_left = 0.0
	knockout_left = 0.0
	winded_left = 0.0
	stagger_left = 0.0
	_last_concussion = -INF
	_heart_arrest_in = -1.0
	_wake_roll_in = WAKE_ROLL_S
	_knockout_only = false
	_heal_left = 0.0
	_heal_queue.clear()


## Host only: steps the simulation by `dt` seconds.
func advance(dt: float) -> void:
	if dead:
		return
	_time += dt
	concussion_left = maxf(concussion_left - dt, 0.0)
	knockout_left = maxf(knockout_left - dt, 0.0)
	winded_left = maxf(winded_left - dt, 0.0)
	stagger_left = maxf(stagger_left - dt, 0.0)
	pain_wounds = maxf(pain_wounds - PAIN_FADE_PER_S * dt, 0.0)
	impact = maxf(impact - IMPACT_FADE_PER_S * dt, 0.0)
	# Bleeding, scaled by what the heart still pushes out.
	blood = maxf(blood - bleed_rate() / 60.0 * dt / BLOOD_L, 0.0)
	if _heal_left > 0.0:
		_treat_step(dt)
	if _heart_arrest_in >= 0.0:
		_heart_arrest_in -= dt
		if _heart_arrest_in <= 0.0:
			_heart_arrest_in = -1.0
			_start_arrest()
	for w in wounds:
		if w.kind != "chest" or w.treated:
			continue
		if float(w.tension_in) >= 0.0:
			w.tension_in = float(w.tension_in) - dt
			if w.tension_in <= 0.0:
				w.tension_in = -1.0
				w.arrest_in = TENSION_ARREST_S  # tension pneumothorax
		elif float(w.arrest_in) >= 0.0:
			w.arrest_in = float(w.arrest_in) - dt
			if w.arrest_in <= 0.0:
				w.arrest_in = -1.0
				_start_arrest()
	if arrest:
		arrest_left -= dt
		if arrest_left <= 0.0:
			kill()  # no heart rate when the window ran out
			return
	update_state(dt)


## Re-evaluates consciousness and arrest from the current state; `dt` drives wake rolls.
func update_state(dt: float) -> void:
	if dead:
		return
	if not arrest and lost() >= ARREST_LOST:
		_start_arrest()
	var other_cause := arrest or lost() >= UNCONSCIOUS_LOST or pain() >= knockout_threshold()
	var out := other_cause or knockout_left > 0.0
	if out:
		if not unconscious:
			unconscious = true
			_knockout_only = not other_cause
			_heal_left = 0.0  # treatment stops when you go out
		elif other_cause:
			_knockout_only = false
		_wake_roll_in = WAKE_ROLL_S
		return
	if not unconscious:
		return
	if _knockout_only:
		unconscious = false  # the concussion knockout passed
		return
	if not is_stable():
		_wake_roll_in = WAKE_ROLL_S
		return
	_wake_roll_in -= dt
	if _wake_roll_in <= 0.0:
		_wake_roll_in = WAKE_ROLL_S
		if rng.randf() < WAKE_CHANCE:
			unconscious = false


# --- Replication ----------------------------------------------------------------------

## Compact state for Vitals.net_state. "t" holds countdowns, which clients run down locally.
func to_net() -> Dictionary:
	var list: Array = []
	for w in wounds:
		list.append([String(w.part), w.kind, snappedf(float(w.rate), 0.001), 1 if w.treated else 0, String(w.name)])
	var flags := (1 if unconscious else 0) | (2 if arrest else 0) | (4 if dead else 0) | (8 if is_healing() else 0)
	var timers := {}
	for key: String in ["arrest_left", "concussion_left", "knockout_left", "winded_left", "stagger_left"]:
		if float(get(key)) > 0.0:
			timers[key] = snappedf(float(get(key)), 0.1)
	return {"b": snappedf(blood, 0.001), "p": snappedf(pain_wounds, 0.01), "i": snappedf(impact, 0.01),
		"f": flags, "w": list, "t": timers}


## Rebuilds this copy from a peer's net_state (clients).
func apply_net(state: Dictionary) -> void:
	blood = float(state.get("b", 1.0))
	pain_wounds = float(state.get("p", 0.0))
	impact = float(state.get("i", 0.0))
	var flags := int(state.get("f", 0))
	unconscious = flags & 1 != 0
	arrest = flags & 2 != 0
	dead = flags & 4 != 0
	_heal_left = 1.0 if flags & 8 != 0 else 0.0
	wounds.clear()
	for entry: Array in state.get("w", []):
		wounds.append({"part": StringName(entry[0]), "kind": String(entry[1]), "rate": float(entry[2]),
			"treated": int(entry[3]) != 0, "name": StringName(entry[4]), "tension_in": -1.0, "arrest_in": -1.0})
	var timers: Dictionary = state.get("t", {})
	for key: String in ["arrest_left", "concussion_left", "knockout_left", "winded_left", "stagger_left"]:
		set(key, float(timers.get(key, 0.0)))


## Clients: runs the replicated countdowns down between updates.
func tick_display(dt: float) -> void:
	for key: String in ["arrest_left", "concussion_left", "knockout_left", "winded_left", "stagger_left"]:
		set(key, maxf(float(get(key)) - dt, 0.0))


# --- Internals ------------------------------------------------------------------------

func _add_wound(part: StringName, kind: String, rate: float, name: StringName = &"") -> Dictionary:
	var w := {"part": part, "kind": kind, "rate": rate, "treated": false, "name": name,
		"tension_in": -1.0, "arrest_in": -1.0}
	wounds.append(w)
	return w


func _stop_bleeding(w: Dictionary) -> void:
	if w.kind == "fracture":
		w.rate = 0.0  # internal bleeding stopped; the bone still needs a splint
	elif w.kind != "rib":
		w.treated = true
	if w.kind == "chest":
		w.tension_in = -1.0  # sealed (stopgap: also relieves a tension pneumothorax)
		w.arrest_in = -1.0
	if w.kind == "heart":
		_heart_arrest_in = -1.0


func _treat_step(dt: float) -> void:
	if unconscious:
		_heal_left = 0.0
		return
	var step := minf(dt, _heal_left)
	pain_wounds = maxf(pain_wounds - _heal_pain_per_s * step, 0.0)
	_heal_left -= step
	_heal_next -= step
	while not _heal_queue.is_empty() and (_heal_next <= 0.0001 or _heal_left <= 0.0):
		_stop_bleeding(_heal_queue.pop_front())
		_heal_next += _heal_every


func _start_arrest() -> void:
	if arrest or dead:
		return
	arrest = true
	arrest_left = ARREST_WINDOW_S
	_heart_arrest_in = -1.0
	_heal_left = 0.0


func _concuss() -> void:
	var mult := 2.0 if _time - _last_concussion < SAME_FIGHT_S else 1.0
	_last_concussion = _time
	var knockout := 0.0
	if rng.randf() < CONCUSSION_KO_CHANCE:
		knockout = rng.randf_range(CONCUSSION_KO_S.x, CONCUSSION_KO_S.y) * mult
		knockout_left = maxf(knockout_left, knockout)
	concussion_left = maxf(concussion_left, knockout + CONCUSSION_S * mult)
