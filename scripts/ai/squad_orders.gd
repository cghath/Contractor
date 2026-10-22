class_name SquadOrders
extends RefCounted
## One hero squad's order executor (docs/high_command.md 5.2): the current HcOrder and its
## queue, compiled onto the Squad orders that already work, always with `from` = the hero. Host
## only, ticked by HighCommand every THINK_S. SquadTactics still fights every contact.
##
## Phase 1 (C2): move (a route of legs), hold, defend, follow / support (FollowBrain), regroup,
## extract, posture, report; ProgressWatch for "held up" / "unable"; succession; contact,
## man-down and sitrep reports.
## Phase 2 (C3): attack (approach, set, assault, consolidate, commander's intent, CE abort),
## support by fire (safe_to_fire, danger close: shift or lift), bound, fall back, defend a
## frontage (a sector per buddy pair), go codes, risk and the break-contact request, going dark.
##
## The hero leads through the existing MOVE order to himself: his men keep FOLLOW on him (the
## squad's leader), so they walk in formation behind him and fight as they do for a player.

const THINK_S := 0.5
## The hero is there within this (m).
const ARRIVE_M := 6.0
## Regroup: every man within this of the point.
const REGROUP_M := 15.0
## Defend: garrison a building within this of the point, else a line facing.
const GARRISON_M := 30.0
## React to contact: the move resumes this long after the last contact.
const RESUME_S := 10.0
## Follow / Support me: re-aim the hero at his station this often.
const FOLLOW_EVERY_S := 2.0
## Straggler control: the hero waits while a man up is further than this behind him.
const STRAGGLE_M := 25.0
## A sitrep when idle this long (high_command.md 6 SITREP_S). Proposed.
const SITREP_S := 180.0
## A contact report isn't repeated within this time and distance.
const CONTACT_GAP_S := 60.0
const CONTACT_GAP_M := 40.0
## CE bands (5.2): GREEN >= 0.7, AMBER >= 0.45, else RED.
const CE_GREEN := 0.7
const CE_AMBER := 0.45
## Attack (Phase 2): the attack position this far short of the objective along the approach;
## the objective is secure when no known enemy is within OBJ_RADIUS_M of it for CONSOLIDATE_S;
## a cluster within OBJ_DRIFT_M re-aims it (commander's intent); ATTACK_MAX_S to take it.
const ATTACK_STANDOFF_M := 120.0
const OBJ_RADIUS_M := 40.0
const CONSOLIDATE_S := 20.0
const OBJ_DRIFT_M := 60.0
const ATTACK_MAX_S := 300.0
## Support by fire: a burst order every SBF_BURST_S while it's safe; the target's quiet for
## SBF_IDLE_S and it's done. safe_to_fire's fan: SAFE_FAN_DEG either side, out to the target +
## SAFE_PAST_M; a friendly within DANGER_CLOSE_M of the target shifts fire SHIFT_M deeper or lifts.
const SBF_BURST_S := 6.0
const SBF_IDLE_S := 60.0
const SAFE_FAN_DEG := 5.0
const SAFE_PAST_M := 30.0
const DANGER_CLOSE_M := 35.0
const SHIFT_M := 40.0
## Defend frontage: 15-25 m a man; wider covers the centre.
const FRONTAGE_PER_MAN_M := 25.0
## Risk (4.1): past this share down, the hero asks to break contact (Careful also at the first
## urgent casualty).
const RISK_DOWN := {"careful": 0.25, "balanced": 0.35, "press": 0.5}
## After a succession the squad is dark (no reports, no shared contacts) until the new leader
## has the radio.
const DARK_S := 15.0

var squad: Squad
var hc: Node  # HighCommand
var order: Dictionary = {}
var queue: Array = []
var watch := ProgressWatch.new()
var size := 4
## The last order and its posture (combined_arms.md 5.4.1: remembered per unit).
var last_verb := ""
var last_posture := {}

var _goal := Vector3.INF
var _engaged_until := -INF
var _paused := false
var _follow_next := 0.0
var _sitrep_at := 0.0
var _held_said := false
var _down := {}  # instance id -> true: men we've reported down
var dark_until := -INF
var _target := Vector3.INF  # attack's objective / SBF's target
var _attack_pos := Vector3.INF
var _quiet_since := -INF
var _exec_at := -INF
var _burst_next := 0.0
var _lifted := false
var _shifted := false
var _asked := false  # the break-contact request went out for this order
var _rally := Vector3.INF
var _leg := 0
var _spots: Array = []  # frontage: [{"names", "spot", "facing"}]
var _contacts: Array = []  # [{"pos", "at"}]: reported contacts


func _init(p_squad: Squad, p_hc: Node) -> void:
	squad = p_squad
	hc = p_hc
	size = maxi(squad.members().size(), 1)


func men() -> Array[Soldier]:
	return squad.members()


func up_men() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for s in squad.members():
		if s.vitals.is_up():
			out.append(s)
	return out


func hero() -> Soldier:
	return squad.hero if squad.hero and is_instance_valid(squad.hero) else null


## Host: takes `o` (cleaned by HcOrder.clean). `append` queues it behind the current one.
func give(o: Dictionary, append := false) -> void:
	if append and not order.is_empty() and not HcOrder.ended(order):
		o.state = "queued"
		queue.append(o)
		return
	if not order.is_empty() and not HcOrder.ended(order):
		_end("cancelled", "replaced")
	queue.clear()
	_start(o)


## Host: cancels order `id` (0: the current one), or a queued one.
func cancel(id := 0) -> bool:
	if id == 0 or int(order.get("id", -1)) == id:
		if order.is_empty() or HcOrder.ended(order):
			return false
		_end("cancelled", "cancelled")
		_hold_here()
		_next()
		return true
	for q: Dictionary in queue:
		if int(q.id) == id:
			queue.erase(q)
			q.state = "cancelled"
			hc.call(&"order_changed", q)
			return true
	return false


func tick(now: float) -> void:
	if squad == null or not is_instance_valid(squad):
		return
	_succession()
	var h := hero()
	if h == null:
		return
	_watch_casualties()
	_watch_contacts(now)
	if order.is_empty() or HcOrder.ended(order):
		if now - _sitrep_at > SITREP_S:
			_sitrep_at = now
			radio("sitrep", sitrep())
		return
	if String(order.state) == "waiting":
		return  # held for a go code
	var engaged := squad.is_engaged() or bool(_assess().get("contact", false))
	if engaged:
		_engaged_until = now + RESUME_S
	_check_risk()
	if HcOrder.ended(order):
		return
	match String(order.verb):
		"move", "defend", "regroup", "extract", "bound", "fall_back":
			_tick_route(now, h, engaged)
		"follow", "support":
			_tick_follow(now, h, engaged)
		"attack":
			_tick_attack(now, h, engaged)
		"sbf":
			_tick_sbf(now, h)
		"defend_frontage":
			_tick_frontage(now)


# --- Starting orders ----------------------------------------------------------------------------

func _start(o: Dictionary) -> void:
	order = o
	order.state = "active"
	order.phase = "route"
	last_verb = String(o.verb)
	if not (o.get("posture", {}) as Dictionary).is_empty():
		last_posture = (o.posture as Dictionary).duplicate()
	_held_said = false
	_paused = false
	_asked = false
	_lifted = false
	_shifted = false
	_leg = 0
	watch.reset(Soldier._now())
	var h := hero()
	_rally = h.global_position if h else Vector3.INF
	var p := _point3(0)
	_goal = p
	if String(o.get("go", "")) != "" and String(o.verb) not in ["attack", "sbf", "hold", "posture", "report"]:
		order.state = "waiting"  # held until the go code (Phase 2): nothing moves yet
		radio("copy", "copy, %s on %s" % [HcOrder.verb_text(String(o.verb)), String(o.go).capitalize()])
		hc.call(&"order_changed", order)
		return
	match String(o.verb):
		"move":
			_apply_posture(o.get("posture", {}))
			_lead_to(p)
			radio("copy", "copy, moving to %s" % grid(p))
		"defend":
			_lead_to(p)
			radio("copy", "copy, defending %s" % grid(p))
		"regroup":
			if h:
				squad.give_order(h, Squad.Order.MOVE, p, _names(men()))
			radio("copy", "copy, regrouping at %s" % grid(p))
		"extract":
			_apply_posture({"contact": "avoid", "mode": "aware"})
			if h:
				squad.give_order(h, Squad.Order.MOVE, p, _names(men()))
			radio("copy", "copy, extracting to %s" % grid(p))
		"hold":
			_hold_here()
			order.state = "set"
			radio("copy", "copy, holding at %s" % grid(h.global_position if h else p))
		"follow", "support":
			_follow_next = 0.0
			var who := _follow_target()
			radio("copy", "copy, %s %s" % ["following" if o.verb == "follow" else "supporting", who.person_name if who and who.person_name != "" else "you"])
		"posture":
			_apply_posture(o.get("posture", {}))
			_end("done", "")
			radio("copy", "copy, %s" % _posture_text(o.get("posture", {})))
			_next()
		"report":
			_end("done", "")
			radio("sitrep", sitrep())
			_next()
		"bound":
			if h:
				squad.order_bound(h, _ground(p), _names(men()))
			radio("copy", "copy, bounding to %s" % grid(p))
		"fall_back":
			if h:
				squad.order_fall_back(h, _ground(p), _names(men()))
			radio("copy", "copy, falling back to %s" % grid(p))
		"attack":
			_start_attack(h, p)
		"sbf":
			_start_sbf(h, p)
		"defend_frontage":
			_start_frontage(h)
		_:
			_end("failed", "can't do %s" % String(o.verb))
	hc.call(&"order_changed", order)


## Host (HighCommand.server_go): go code `code` was given. A waiting order starts; an attack or
## support by fire set at its position goes in. Returns whether this squad went.
func go(code: String) -> bool:
	if order.is_empty() or HcOrder.ended(order) or String(order.get("go", "")) != code:
		return false
	if String(order.state) == "waiting":
		order.go = ""
		_start(order)
		return true
	if String(order.state) == "set" and String(order.verb) in ["attack", "sbf"]:
		order.go = ""
		_execute()
		return true
	return false


func _next() -> void:
	if queue.is_empty():
		return
	var o: Dictionary = queue.pop_front()
	_start(o)


func _end(state: String, why: String) -> void:
	order.state = state
	order.why = why
	hc.call(&"order_changed", order)


# --- Route verbs --------------------------------------------------------------------------------

func _tick_route(now: float, h: Soldier, engaged: bool) -> void:
	var contact := String((order.get("posture", {}) as Dictionary).get("contact", "react"))
	if engaged and contact == "react" and String(order.verb) in ["move", "defend"]:
		if not _paused:
			_paused = true
			_hold_here()  # react: halt and let SquadTactics fight; the move resumes after
		watch.reset(now)
		return
	if _paused and now >= _engaged_until:
		_paused = false
		_lead_to(_goal)
	if _paused:
		return
	if String(order.state) == "set" or String(order.get("phase", "")) in ["execute", "consolidate"]:
		return
	var who: Array[Soldier] = up_men()
	match String(order.verb):
		"regroup":
			if who.all(func(s: Soldier) -> bool: return _flat(s.global_position, _goal) <= REGROUP_M):
				_end("done", "")
				radio("done", "regrouped at %s, %s" % [grid(_goal), _strength_text()])
				_next()
				return
		"extract":
			var point := _extraction_point()
			if not point.is_empty() and who.all(func(s: Soldier) -> bool: return Extraction.inside(point, s.global_position)):
				order.state = "set"
				order.phase = "execute"
				hc.call(&"order_changed", order)
				radio("done", "at the LZ")
				return
	if _flat(h.global_position, _goal) <= ARRIVE_M:
		_arrived(h)
		return
	# straggler control: wait for the men
	var straggling := who.any(func(s: Soldier) -> bool: return s != h and _flat(s.global_position, h.global_position) > STRAGGLE_M)
	var state := watch.feed(h.global_position, _goal, now)
	if straggling and state == ProgressWatch.OK:
		return
	var steers := String(order.verb) not in ["bound", "fall_back"]  # (their own drills move the pairs)
	match state:
		ProgressWatch.WEDGED:
			if steers:
				_lead_to(watch.steer(h.global_position, _goal))
		ProgressWatch.HELD_UP:
			if not _held_said:
				_held_said = true
				radio("held_up", "held up at %s, finding a way round" % grid(h.global_position))
			if steers:
				_lead_to(watch.steer(h.global_position, _goal, 10.0))
		ProgressWatch.UNABLE:
			_end("failed", "no route to %s" % grid(_goal))
			radio("unable", "unable: no route to %s. Holding" % grid(_goal))
			_hold_here()
			_next()
		_:
			if watch.detour == Vector3.ZERO and _held_said and steers:
				_lead_to(_goal)


func _arrived(h: Soldier) -> void:
	match String(order.verb):
		"move":
			if _leg < (order.points as Array).size() - 1:
				_leg += 1
				_goal = _point3(_leg)
				watch.reset(Soldier._now())
				_lead_to(_goal)
				return
			_end("done", "")
			radio("done", "set at %s" % grid(h.global_position))
			_next()
		"bound":
			_end("done", "")
			radio("done", "set at %s" % grid(h.global_position))
			_next()
		"fall_back":
			_hold_here()
			order.state = "set"
			hc.call(&"order_changed", order)
			radio("set", "fell back to %s, holding" % grid(h.global_position))
		"attack", "sbf":
			_in_position(h)
		"defend":
			var lvl := _level()
			var b := Buildings.nearest(lvl, _goal, GARRISON_M) if lvl else {}
			var how := ""
			if not b.is_empty():
				how = squad.order_garrison(h, _goal, _names(men()))
			if b.is_empty() or how != "":
				squad.give_order(h, Squad.Order.HOLD, h.global_position, _names(men()))
				var facing := _facing()
				squad.order_command(h, "watch", h.global_position + facing * 50.0, _names(men()))
			order.state = "set"
			order.phase = "set"
			hc.call(&"order_changed", order)
			radio("set", "set at %s%s" % [grid(h.global_position), ", in the building" if not b.is_empty() and how == "" else ""])
		_:
			pass


# --- Follow / Support me ------------------------------------------------------------------------

func _tick_follow(now: float, h: Soldier, engaged: bool) -> void:
	if now < _follow_next:
		return
	_follow_next = now + FOLLOW_EVERY_S
	var lead := _follow_target()
	if lead == null:
		_end("failed", "nobody to follow")
		radio("unable", "unable: nobody to follow. Holding")
		_hold_here()
		return
	var band: Vector2 = FollowBrain.BANDS.get(String(order.verb), Vector2(30, 60))
	var side := 1.0 if hash(String(squad.hc_id)) % 2 == 0 else -1.0
	var d := FollowBrain.decide({"me": h.global_position, "lead": lead.global_position, "lead_yaw": lead.rotation.y,
		"lead_ride": lead.vehicle if is_instance_valid(lead.vehicle) else null, "my_ride": h.vehicle if is_instance_valid(h.vehicle) else null,
		"contact": engaged, "offset": FollowBrain.offset_for(String(order.verb), side), "near_m": band.x, "far_m": band.y})
	match String(d.kind):
		"walk":
			_lead_to(d.point)
		"hold":
			if not engaged:
				_hold_here()
		_:
			pass


func _follow_target() -> Soldier:
	var ref := String((order.get("target", {}) as Dictionary).get("ref", ""))
	var peer := int(ref) if ref.is_valid_int() else int(order.get("by", 1))
	for p: Soldier in MapNodes.players(hc):
		if p.name.to_int() == peer:
			return p
	var all := MapNodes.players(hc)
	return all[0] if not all.is_empty() else null


# --- Reports ------------------------------------------------------------------------------------

func radio(kind: String, text: String, pos: Variant = null) -> void:
	if is_dark() and kind not in ["succession"]:
		return  # dark: nobody on the radio yet (5.3)
	hc.call(&"radio", self, kind, text, pos)


func is_dark() -> bool:
	return Soldier._now() < dark_until


## "green, 4 up, ammo amber, holding at 041 053"
func sitrep() -> String:
	var sit := _assess()
	var h := hero()
	var doing := "holding" if order.is_empty() or HcOrder.ended(order) else HcOrder.verb_text(String(order.verb))
	return "%s, %s, ammo %s, %s at %s" % [ce_band(ce()), _strength_text(), _band(float(sit.get("ammo", 1.0))), doing,
		grid(h.global_position if h else Vector3.ZERO)]


func ce() -> float:
	return combat_effectiveness(_assess(), size)


## CE (5.2): clamp(up / size) x 0.5 + ammo x 0.25 + morale x 0.25 - 0.1 x urgent casualties.
static func combat_effectiveness(sit: Dictionary, team_size: int) -> float:
	var up := clampf(float(sit.get("up", 0)) / maxf(team_size, 1), 0.0, 1.0)
	return clampf(up * 0.5 + float(sit.get("ammo", 1.0)) * 0.25 + float(sit.get("morale", 1.0)) * 0.25 - 0.1 * float(sit.get("urgent", 0)), 0.0, 1.0)


static func ce_band(v: float) -> String:
	return "green" if v >= CE_GREEN else ("amber" if v >= CE_AMBER else "red")


static func _band(v: float) -> String:
	return "green" if v >= 0.6 else ("amber" if v >= 0.3 else "red")


func _strength_text() -> String:
	return "%d up" % up_men().size()


func _watch_casualties() -> void:
	for s in men():
		var id := s.get_instance_id()
		if not s.vitals.is_up() and not _down.has(id):
			_down[id] = true
			radio("casualty", "man down: %s" % (s.person_name if s.person_name != "" else String(s.name)), s.global_position)
		elif s.vitals.is_up() and _down.has(id):
			_down.erase(id)


func _watch_contacts(now: float) -> void:
	var cl := squad.clusters()
	if cl.is_empty():
		return
	var c: Dictionary = cl[0]
	if float(c.age) > Squad.FRESH_S:
		return
	for r: Dictionary in _contacts:
		if now - float(r.at) < CONTACT_GAP_S and _flat(r.pos, c.centre) < CONTACT_GAP_M:
			return
	_contacts.append({"pos": c.centre, "at": now})
	if _contacts.size() > 8:
		_contacts.pop_front()
	var h := hero()
	var dist := _flat(h.global_position, c.centre) if h else 0.0
	var dir := Callouts.direction_word(h, c.centre) if h else ""
	radio("contact", "contact: %d enemy, %s, %d m, engaging" % [int(c.count), _compass(h.global_position if h else c.centre, c.centre), int(round(dist / 10.0) * 10.0)], c.centre)
	if not is_dark():
		hc.call(&"share_contact", self, c)
	if dir == "":
		pass


static func _compass(from: Vector3, to: Vector3) -> String:
	var d := Vector2(to.x - from.x, to.z - from.z)
	if d.length() < 0.1:
		return "here"
	var bearing := fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)
	return ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][int(round(bearing / 45.0)) % 8]


# --- Succession (5.3) ---------------------------------------------------------------------------

func _succession() -> void:
	var h := hero()
	if h and h.vitals.is_up():
		return
	var best: Soldier = null
	var best_key := -INF
	for s in men():
		if not s.vitals.is_up() or s == h:
			continue
		var key := (2.0 if s.role == Roles.TEAM_LEADER else 0.0) + float(SquadAI.of(s).discipline if SquadAI.of(s) else 0.5)
		if key > best_key:
			best_key = key
			best = s
	if best == null:
		return
	var was := h.person_name if h and h.person_name != "" else "the leader"
	squad.hero = best
	squad.leader = best
	radio("succession", "%s is down. %s has command" % [was, best.person_name if best.person_name != "" else String(best.name)])
	dark_until = Soldier._now() + DARK_S  # until he has the radio
	if not order.is_empty() and not HcOrder.ended(order):
		var o := order
		order = {}
		_start(o)


# --- Helpers ------------------------------------------------------------------------------------

func _lead_to(p: Vector3) -> void:
	var h := hero()
	if h == null or not p.is_finite():
		return
	var lvl := _level()
	if lvl and lvl.has_method(&"ground_point"):
		p = lvl.call(&"ground_point", p)
	squad.give_order(h, Squad.Order.MOVE, p, PackedStringArray([String(h.name)]))
	# the rest follow the hero (their leader now); a man left holding from an ordered tactic
	# gets FOLLOW back (G10: the resting order)
	var rest := PackedStringArray()
	for s in men():
		if s != h and SquadAI.of(s) and SquadAI.of(s).order != Squad.Order.FOLLOW:
			rest.append(String(s.name))
	if not rest.is_empty():
		squad.give_order(h, Squad.Order.FOLLOW, p, rest)


func _hold_here() -> void:
	var h := hero()
	if h:
		squad.give_order(h, Squad.Order.HOLD, h.global_position, _names(men()))


func _apply_posture(p: Variant) -> void:
	var h := hero()
	if h == null or not p is Dictionary:
		return
	var posture: Dictionary = p
	if posture.has("roe"):
		squad.set_hold_fire(h, String(posture.roe) == "hold", _names(men()))
	if posture.has("mode"):
		squad.set_combat_mode(h, Squad.COMBAT_MODES.get(String(posture.mode), Squad.CombatMode.AWARE), _names(men()))
	if posture.has("formation"):
		squad.set_formation(h, "formation", String(posture.formation), _names(men()))


static func _posture_text(p: Variant) -> String:
	if not p is Dictionary or (p as Dictionary).is_empty():
		return "no change"
	var parts := PackedStringArray()
	for k: String in (p as Dictionary):
		parts.append("%s %s" % [k, p[k]])
	return ", ".join(parts)


func _facing() -> Vector3:
	var f: Array = order.get("facing", [])
	if f.size() >= 2:
		return Vector3(float(f[0]), 0.0, float(f[1])).normalized()
	var cl := squad.clusters()
	var h := hero()
	if not cl.is_empty() and h:
		var d: Vector3 = (cl[0].centre as Vector3) - h.global_position
		d.y = 0.0
		if d.length() > 1.0:
			return d.normalized()
	return h.global_basis.z * -1.0 if h else Vector3.FORWARD


func _extraction_point() -> Dictionary:
	var ex := MapNodes.extraction(hc)
	if ex == null:
		return {}
	var best := {}
	var best_d := INF
	for p: Dictionary in ex.points:
		var d := Vector2(_goal.x, _goal.z).distance_to(p.pos)
		if d < best_d:
			best_d = d
			best = p
	return best if best_d <= 60.0 else {}


func _point3(i := -1) -> Vector3:
	var p := HcOrder.point(order, i)
	return Vector3(p.x, 0.0, p.y) if p.is_finite() else (hero().global_position if hero() else Vector3.ZERO)


func _ground(p: Vector3) -> Vector3:
	var lvl := _level()
	return lvl.call(&"ground_point", p) if lvl and lvl.has_method(&"ground_point") else p


func _assess() -> Dictionary:
	if squad.tactics == null:
		squad.tactics = SquadTactics.new(squad)
	return squad.tactics.assess()


func _level() -> Node:
	return MapNodes.level_of(hc)


func grid(p: Vector3) -> String:
	return MapGrid.grid_ref_3d(p, MapNodes.area_of(hc), 6)


static func _names(list: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for s: Soldier in list:
		out.append(String(s.name))
	return out


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Phase 2: attack (high_command.md 3.2, 4.1) ------------------------------------------------

## The objective: the order's target, else its last point.
func _target_of() -> Vector3:
	var t: Dictionary = order.get("target", {})
	var tp: Variant = t.get("pos")
	if tp is Array and (tp as Array).size() >= 2:
		return Vector3(float(tp[0]), 0.0, float(tp[1]))
	return _point3()


func _start_attack(h: Soldier, _p: Vector3) -> void:
	_target = _target_of()
	if h == null:
		return
	var axis := _target - h.global_position
	axis.y = 0.0
	var dist := axis.length()
	axis = axis.normalized() if dist > 0.1 else Vector3.FORWARD
	_attack_pos = h.global_position if dist <= ATTACK_STANDOFF_M else _target - axis * ATTACK_STANDOFF_M
	_goal = _attack_pos
	_quiet_since = -INF
	if dist <= ATTACK_STANDOFF_M:
		radio("copy", "copy, attacking %s" % grid(_target))
		_in_position(h)
		return
	_lead_to(_attack_pos)
	radio("copy", "copy, attacking %s, moving to the attack position" % grid(_target))


## At the attack or SBF position: set and wait for the go code, else go in.
func _in_position(h: Soldier) -> void:
	order.phase = "set"
	if String(order.get("go", "")) != "":
		_hold_here()
		order.state = "set"
		hc.call(&"order_changed", order)
		radio("set", "set at %s. Ready on %s" % [grid(h.global_position), String(order.go).capitalize()])
		return
	_execute()


func _execute() -> void:
	var h := hero()
	if h == null:
		return
	order.state = "active"
	order.phase = "execute"
	_exec_at = Soldier._now()
	_burst_next = 0.0
	match String(order.verb):
		"attack":
			var why := squad.order_assault(h, _ground(_target), _names(men()))
			if why != "":
				squad.give_order(h, Squad.Order.MOVE, _ground(_target), _names(men()))  # no enemy known there: walk on it
			radio("copy", "going in on %s" % grid(_target))
		"sbf":
			radio("copy", "opening fire on %s" % grid(_target))
	hc.call(&"order_changed", order)


func _tick_attack(now: float, h: Soldier, engaged: bool) -> void:
	if String(order.phase) == "route":
		_tick_route(now, h, engaged)
		return
	if String(order.state) == "set":
		return  # waiting on its go code
	if ce_band(ce()) == "red":
		_end("failed", "combat ineffective")
		radio("unable", "is red, request orders. Falling back")
		if _attack_pos.is_finite():
			squad.order_fall_back(h, _ground(_attack_pos), _names(men()))
		_next()
		return
	# commander's intent: a cluster drifted within OBJ_DRIFT_M is still the objective
	var cl := squad.clusters()
	if not cl.is_empty() and _flat(cl[0].centre, _target) <= OBJ_DRIFT_M and _flat(cl[0].centre, _target) > 5.0:
		_target = cl[0].centre
	var near := squad.enemy_picture().filter(func(e: Dictionary) -> bool: return _flat(e.pos, _target) <= OBJ_RADIUS_M)
	if near.is_empty() and _flat(h.global_position, _target) <= OBJ_RADIUS_M:
		if _quiet_since == -INF:  # (uptime starts at 0: never a negative test)
			_quiet_since = now
			order.phase = "consolidate"
			hc.call(&"order_changed", order)
		elif now - _quiet_since >= CONSOLIDATE_S:
			_hold_here()
			_end("done", "")
			radio("done", "objective secure at %s" % grid(_target))
			_next()
			return
	else:
		_quiet_since = -INF
		if near.is_empty() and now - _exec_at > 10.0 and _flat(h.global_position, _target) > OBJ_RADIUS_M and not engaged:
			_lead_to(_target)  # nobody there that we know of: close on it
	if now - _exec_at > ATTACK_MAX_S:
		_end("failed", "objective not taken")
		radio("unable", "unable to take %s. Holding" % grid(_target))
		_hold_here()
		_next()


# --- Phase 2: support by fire (5.4) --------------------------------------------------------------

func _start_sbf(h: Soldier, p: Vector3) -> void:
	var t: Dictionary = order.get("target", {})
	if not t.has("pos") and (order.points as Array).size() < 2:
		_end("failed", "support by fire needs a target")
		radio("unable", "unable: no target to fire on")
		return
	_target = _target_of() if t.has("pos") else _point3(1)
	_goal = p
	_quiet_since = -INF
	if h and _flat(h.global_position, p) <= ARRIVE_M:
		_in_position(h)
		return
	_lead_to(p)
	radio("copy", "copy, support by fire from %s on %s" % [grid(p), grid(_target)])


func _tick_sbf(now: float, h: Soldier) -> void:
	if String(order.phase) == "route":
		_tick_route(now, h, false)  # (an SBF position is taken under fire too)
		return
	if String(order.state) == "set" or now < _burst_next:
		return
	_burst_next = now + SBF_BURST_S
	var friends := _friendlies()
	var close := friends.filter(func(f: Vector3) -> bool: return _flat(f, _target) <= DANGER_CLOSE_M)
	if not close.is_empty():
		var axis := _target - h.global_position
		axis.y = 0.0
		var deeper := _target + axis.normalized() * SHIFT_M
		if not _shifted and friends.all(func(f: Vector3) -> bool: return _flat(f, deeper) > DANGER_CLOSE_M) and safe_to_fire(h.global_position, deeper, friends):
			_shifted = true
			_target = deeper
			radio("set", "shifting fire")
		else:
			if not _lifted:
				_lifted = true
				squad.set_hold_fire(h, true, _names(men()))
				radio("set", "check fire, friendlies on target")
			return
	if not safe_to_fire(h.global_position, _target, friends):
		if not _lifted:
			_lifted = true
			squad.set_hold_fire(h, true, _names(men()))
			radio("set", "can't fire, friendlies in the lane")
		return
	if _lifted:
		_lifted = false
		squad.set_hold_fire(h, false, _names(men()))
		radio("set", "resuming fire")
	squad.order_suppress(h, _ground(_target), _names(up_men()))
	var near := squad.enemy_picture().filter(func(e: Dictionary) -> bool: return _flat(e.pos, _target) <= OBJ_RADIUS_M)
	if near.is_empty():
		if _quiet_since == -INF:  # (uptime starts at 0: never a negative test)
			_quiet_since = now
		elif now - _quiet_since >= SBF_IDLE_S:
			_end("done", "")
			radio("done", "target quiet, holding")
			_hold_here()
			_next()
	else:
		_quiet_since = -INF


## No fire with any friendly inside a SAFE_FAN_DEG fan either side of the shot line from
## `shooter` to `target`, out to the target + SAFE_PAST_M (5.4: the most important safety rule
## once several squads fight in one place). Friendlies within 3 m of the shooter (his own
## buddy beside him) don't count. Pure.
static func safe_to_fire(shooter: Vector3, target: Vector3, friendlies: Array) -> bool:
	var line := Vector2(target.x - shooter.x, target.z - shooter.z)
	var reach := line.length() + SAFE_PAST_M
	if line.length() < 0.5:
		return false
	for f: Vector3 in friendlies:
		var d := Vector2(f.x - shooter.x, f.z - shooter.z)
		if d.length() < 3.0 or d.length() > reach:
			continue
		if absf(rad_to_deg(line.angle_to(d))) <= SAFE_FAN_DEG:
			return false
	return true


## Where every friendly not in this squad stands: players, the player squad, other groups.
func _friendlies() -> Array:
	var out: Array = []
	var mine := {}
	for s in men():
		mine[s] = true
	for n in hc.get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.faction == squad.faction and not mine.has(s) and not s.vitals.is_dead() and not s.is_queued_for_deletion():
			out.append(s.global_position)
	return out


# --- Phase 2: defend a frontage (5.2) ------------------------------------------------------------

## A frontage from `a` to `b` split for `pairs` buddy pairs: [{"spot", "facing"}], each pair at
## its sector's middle facing out (to `out`'s side). Wider than `men` x FRONTAGE_PER_MAN_M it
## covers the centre only ("too_wide" true on the first). Pure.
static func frontage_split(a: Vector3, b: Vector3, pairs: int, men_count: int, out: Vector3) -> Array:
	var res: Array = []
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var width := along.length()
	var too_wide := width > men_count * FRONTAGE_PER_MAN_M
	var centre := (a + b) * 0.5
	if too_wide:
		var half := along.normalized() * men_count * FRONTAGE_PER_MAN_M * 0.5
		a = centre - half
		b = centre + half
		along = b - a
	var facing := along.cross(Vector3.UP).normalized()
	if out != Vector3.ZERO and facing.dot(out - centre) < 0.0:
		facing = -facing
	pairs = maxi(pairs, 1)
	for i in pairs:
		var t := (i + 0.5) / pairs
		res.append({"spot": a + along * t, "facing": facing, "too_wide": too_wide and i == 0})
	return res


func _start_frontage(h: Soldier) -> void:
	if (order.points as Array).size() < 2:
		_end("failed", "a frontage needs two points")
		return
	var list := up_men()
	var pairs := ceili(list.size() / 2.0)
	var out := _point3(0) + _facing() * 50.0
	var split := frontage_split(_point3(0), _point3(1), pairs, list.size(), out)
	_spots.clear()
	for i in split.size():
		var names := PackedStringArray()
		for j in [i * 2, i * 2 + 1]:
			if j < list.size():
				names.append(String(list[j].name))
		_spots.append({"names": names, "spot": split[i].spot, "facing": split[i].facing})
		if h:
			squad.give_order(h, Squad.Order.MOVE, _ground(split[i].spot), names)
	_goal = (_point3(0) + _point3(1)) * 0.5
	order.phase = "route"
	radio("copy", "copy, defending the frontage %s to %s%s" % [grid(_point3(0)), grid(_point3(1)),
		". Frontage too wide, covering the centre" if not split.is_empty() and bool(split[0].too_wide) else ""])


func _tick_frontage(now: float) -> void:
	if String(order.state) == "set":
		return
	var h := hero()
	var all_in := true
	for sp: Dictionary in _spots:
		for n: String in sp.names:
			var s := squad.find_soldier(n)
			if s and s.vitals.is_up() and _flat(s.global_position, sp.spot) > 5.0:
				all_in = false
	if all_in or now - float(order.get("at", now)) > 90.0:
		for sp: Dictionary in _spots:
			squad.give_order(h, Squad.Order.HOLD, sp.spot, sp.names)
			squad.order_command(h, "watch", (sp.spot as Vector3) + (sp.facing as Vector3) * 60.0, sp.names)
		order.state = "set"
		order.phase = "set"
		hc.call(&"order_changed", order)
		radio("set", "set on the frontage, %d sectors" % _spots.size())


# --- Phase 2: risk and requests (4.1, 4.2) -------------------------------------------------------

## Past the risk threshold on a Defend, an Attack or SBF, the hero asks to break contact once
## (HighCommand.server_request); unanswered, he decides by the risk.
func _check_risk() -> void:
	if _asked or String(order.verb) not in ["defend", "defend_frontage", "attack", "sbf", "hold"]:
		return
	var sit := _assess()
	var down := 1.0 - clampf(float(sit.get("up", 0)) / maxf(size, 1), 0.0, 1.0)
	var risk := String(order.get("risk", "balanced"))
	var past := down >= float(RISK_DOWN.get(risk, 0.35)) or (risk == "careful" and int(sit.get("urgent", 0)) > 0)
	if not past:
		return
	_asked = true
	if risk == "careful":
		radio("request", "%s, breaking contact" % ce_band(ce()))
		_break_contact()
		return
	hc.call(&"server_request", self, "break_contact", "%s: %d down, request to break contact" % [ce_band(ce()), roundi(down * size)],
		func(yes: bool) -> void:
			if yes:
				_break_contact()
			else:
				radio("copy", "copy, holding on"), risk != "press")


func _break_contact() -> void:
	var h := hero()
	if h == null:
		return
	var back := _rally if _rally.is_finite() else h.global_position - h.global_basis.z * -40.0
	_end("cancelled", "broke contact")
	squad.order_fall_back(h, _ground(back), _names(men()))
	var o := HcOrder.make(String(squad.hc_id), "fall_back", [[back.x, back.z]])
	o.id = HcOrder.next_id()
	o.at = Soldier._now()
	order = o
	order.state = "active"
	_goal = back
	watch.reset(Soldier._now())
	hc.call(&"order_changed", order)
	radio("copy", "breaking contact to %s" % grid(back))
