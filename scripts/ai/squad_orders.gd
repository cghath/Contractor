class_name SquadOrders
extends RefCounted
## One hero squad's order executor (docs/high_command.md 5.2): the current HcOrder and its
## queue, compiled onto the Squad orders that already work, always with `from` = the hero. Host
## only, ticked by HighCommand every THINK_S. SquadTactics still fights every contact.
##
## Phase 1 (C2): move, hold, defend, follow / support (FollowBrain), regroup, extract, posture,
## report; ProgressWatch for "held up" / "unable"; succession; contact, man-down and sitrep
## reports. Phase 2 (C3) adds its own handlers here.
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
		return  # held for a go code (C3)
	var engaged := squad.is_engaged() or bool(_assess().get("contact", false))
	if engaged:
		_engaged_until = now + RESUME_S
	match String(order.verb):
		"move", "defend", "regroup", "extract":
			_tick_route(now, h, engaged)
		"follow", "support":
			_tick_follow(now, h, engaged)
		_:
			hc.call(&"tick_verb", self, now)  # Phase 2 verbs (C3)


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
	watch.reset(Soldier._now())
	var h := hero()
	var p := _point3()
	_goal = p
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
		_:
			hc.call(&"start_verb", self, o)
	hc.call(&"order_changed", order)


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
	if String(order.state) == "set":
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
	match state:
		ProgressWatch.WEDGED:
			_lead_to(watch.steer(h.global_position, _goal))
		ProgressWatch.HELD_UP:
			if not _held_said:
				_held_said = true
				radio("held_up", "held up at %s, finding a way round" % grid(h.global_position))
			_lead_to(watch.steer(h.global_position, _goal, 10.0))
		ProgressWatch.UNABLE:
			_end("failed", "no route to %s" % grid(_goal))
			radio("unable", "unable: no route to %s. Holding" % grid(_goal))
			_hold_here()
			_next()
		_:
			if watch.detour == Vector3.ZERO and _held_said:
				_lead_to(_goal)


func _arrived(h: Soldier) -> void:
	match String(order.verb):
		"move":
			_end("done", "")
			radio("done", "set at %s" % grid(h.global_position))
			_next()
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
	hc.call(&"radio", self, kind, text, pos)


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


func _point3() -> Vector3:
	var p := HcOrder.point(order)
	return Vector3(p.x, 0.0, p.y) if p.is_finite() else (hero().global_position if hero() else Vector3.ZERO)


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
