class_name SurvivalSleep
extends RefCounted
## Sleep in Contractor: Fallen (docs/survival_medical.md section 4, call 47). A survivor lies down
## (Survival.server_sleep: a bed, a bedroll or the ground; the bed and bedroll pieces are phase B,
## so for now the caller says which) for some world hours. Asleep, his body steps at SPEED (the
## sleep store fills by Needs.SLEEP_FILL_H, the rest drains as ever, warmth drains with no
## movement to hold it: sleeping out in the cold is a risk), and when every survivor in the zone
## is asleep the world's clock runs at SPEED too. He wakes when the hours are up or he is rested,
## when he moves off his spot, and everyone asleep wakes when one of the dead is chasing one of
## them (ZombieAI's CHASE: no watch yet, so it's waking to what's already there).
## The state lives in his Needs dictionary: "asleep" (where), "sleep_left_h", "sleep_at".

## Proposed: x12 (section 4).
const SPEED := 12.0
## Too rested to sleep at or over this.
const RESTED := 90.0
## Moving this far off the spot wakes him.
const WAKE_MOVE_M := 1.5
const WHERE := ["bed", "bedroll", "ground"]


static func is_asleep(n: Dictionary) -> bool:
	return String(n.get("asleep", "")) != ""


## Host: `s` lies down for `hours` world hours on `where`. "" or why not.
static func start(s: Soldier, n: Dictionary, hours: float, where: String, chased: bool) -> String:
	if not s.vitals.is_up():
		return "Not now"
	if chased:
		return "Not with the dead on you"
	if is_asleep(n):
		return "Already asleep"
	if float(n.get("sleep", 100.0)) >= RESTED:
		return "You're not tired"
	n.asleep = where if where in WHERE else "ground"
	n.sleep_left_h = maxf(0.25, hours)
	var p := s.global_position
	n.sleep_at = [p.x, p.y, p.z]
	return ""


## Wakes `n`.
static func wake(n: Dictionary) -> void:
	n.asleep = ""
	n.erase("sleep_left_h")
	n.erase("sleep_at")
	stop_wait(n)  # (waiting stops the same way: wait_step)


## The world clock's speed for these survivors: SPEED when every one up is asleep.
static func clock_mult(players: Array) -> float:
	var up := players.filter(func(p: Soldier) -> bool: return p.vitals.is_up() and p.respawn_state != Soldier.RESPAWN_WAITING)
	if up.is_empty():
		return 1.0
	for p: Soldier in up:
		if not is_asleep(Survival.needs_of(p)) and not is_waiting(Survival.needs_of(p)):
			return 1.0
	return SPEED


## How fast this body's own time runs (asleep: SPEED).
static func body_mult(s: Soldier) -> float:
	return SPEED if is_asleep(Survival.needs_of(s)) or is_waiting(Survival.needs_of(s)) else 1.0


## After a step of `world_h` world hours asleep: counts the hours down. Returns why he wakes, or
## "" (still asleep, or not asleep).
static func after_step(s: Soldier, n: Dictionary, world_h: float) -> String:
	if is_waiting(n):
		return wait_step(s, n, world_h)
	if not is_asleep(n):
		return ""
	n.sleep_left_h = float(n.get("sleep_left_h", 0.0)) - world_h
	if not s.vitals.is_up():
		return "down"
	var at: Array = n.get("sleep_at", [])
	if at.size() == 3 and s.global_position.distance_to(Vector3(float(at[0]), float(at[1]), float(at[2]))) > WAKE_MOVE_M:
		return "moved"
	if float(n.sleep_left_h) <= 0.0 or float(n.sleep) >= 100.0:
		return "rested"
	return ""


## Whether one of the dead in `level` is chasing one of `players`.
static func chased(level: Node, players: Array) -> bool:
	for z: Soldier in Survival.zombies(level):
		var brain := ZombieAI.of(z)
		if brain and brain.mode == ZombieAI.Mode.CHASE and brain.target in players:
			return true
	return false


## What the sleeper is told on waking, by why.
static func wake_text(why: String) -> String:
	return {"rested": "You wake, rested", "moved": "You get up", "dead": "You wake with a start: the dead are coming", "down": "",
		"watch": "The watch wakes you: the dead are coming", "waited": "You've waited", "wait_moved": "You stop waiting",
		"wait_dead": "Something's coming: you stop waiting"}.get(why, "You wake")


# --- Waiting and passing time (call 136) --------------------------------------------------------
# At a safe spot (home: the settlement or the safehouse mark within SAFE_HOME_M, or indoors) with
# none of the dead chasing within WAIT_SAFE_M, a survivor waits an hour, until dusk or until dawn:
# his body's time and (when every survivor is asleep or waiting) the world's clock run at SPEED as
# in sleep, without sleep's restore (the sleep store drains awake). Moving off the spot, going
# down or one of the dead chasing within WAIT_SAFE_M stops it. The state is "wait_left_h" and
# "wait_at" in his Needs. Proposed numbers.

const WAIT_SAFE_M := 60.0
const SAFE_HOME_M := 40.0
const DUSK_H := 19.0
const DAWN_H := 6.0
const WAIT_MODES := ["hour", "dusk", "dawn"]


static func is_waiting(n: Dictionary) -> bool:
	return float(n.get("wait_left_h", 0.0)) > 0.0


## World hours to wait from `now_h` (hour of day) for `mode`: an hour, until dusk, until dawn.
static func wait_hours(mode: String, now_h: float) -> float:
	match mode:
		"dusk":
			var h := fposmod(DUSK_H - now_h, 24.0)
			return h if h > 0.05 else 24.0
		"dawn":
			var h := fposmod(DAWN_H - now_h, 24.0)
			return h if h > 0.05 else 24.0
	return 1.0


## Whether one of the dead is chasing (anything) within `m` of `at`.
static func dead_chasing_near(level: Node, at: Vector3, m: float) -> bool:
	if level == null:
		return false
	for z: Soldier in Survival.zombies(level):
		var brain := ZombieAI.of(z)
		if brain and brain.mode == ZombieAI.Mode.CHASE and z.global_position.distance_to(at) <= m:
			return true
	return false


## Whether `s` stands somewhere safe to wait: home (the settlement's radius, or near the
## safehouse mark) or indoors (a roof over him: a held building).
static func at_safe_spot(s: Soldier) -> bool:
	var zone := String(Survival.state().get("zone", ""))
	if Settlement.exists() and Settlement.zone() == zone and s.global_position.distance_to(Settlement.pos()) <= Settlement.radius():
		return true
	var mark := SurvivalMap.safehouse()
	if not mark.is_empty() and String(mark.get("zone", "")) == zone:
		var p := SurvivalMap.mark_pos(mark)
		if Vector2(s.global_position.x, s.global_position.z).distance_to(p) <= SAFE_HOME_M:
			return true
	return s.is_inside_tree() and Throwables.indoors(s.get_world_3d(), s.global_position)


## Why `s` can't wait here ("" when he can).
static func wait_problem(s: Soldier, n: Dictionary, level: Node) -> String:
	if not s.vitals.is_up():
		return "Not now"
	if is_asleep(n) or is_waiting(n):
		return "Already resting"
	if dead_chasing_near(level, s.global_position, WAIT_SAFE_M):
		return "Not with the dead about"
	if not at_safe_spot(s):
		return "Not here: wait at home or indoors"
	return ""


## Host: `s` starts waiting `hours` world hours. "" or why not.
static func start_wait(s: Soldier, n: Dictionary, hours: float, level: Node) -> String:
	var why := wait_problem(s, n, level)
	if why != "":
		return why
	n["wait_left_h"] = maxf(0.05, hours)
	var p := s.global_position
	n["wait_at"] = [p.x, p.y, p.z]
	return ""


static func stop_wait(n: Dictionary) -> void:
	n.erase("wait_left_h")
	n.erase("wait_at")


## After a step of `world_h` world hours waiting: counts down; returns why it stops ("waited",
## "wait_moved", "wait_dead", "down") or "".
static func wait_step(s: Soldier, n: Dictionary, world_h: float) -> String:
	n["wait_left_h"] = float(n.get("wait_left_h", 0.0)) - world_h
	if not s.vitals.is_up():
		return "down"
	var at: Array = n.get("wait_at", [])
	if at.size() == 3 and s.global_position.distance_to(Vector3(float(at[0]), float(at[1]), float(at[2]))) > WAKE_MOVE_M:
		return "wait_moved"
	if s.is_inside_tree() and dead_chasing_near(CompoundLevel.current(s), s.global_position, WAIT_SAFE_M):
		return "wait_dead"
	if float(n.wait_left_h) <= 0.0:
		return "waited"
	return ""
