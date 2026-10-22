class_name SideCommand
extends Node
## The AI commander of one side (docs/combined_arms.md 3; phase B2). Learned from HAL, with
## LAMBS and VCOM running underneath: it sees the battlefield only through its side's picture
## (SidePicture), knows its groups by their sitreps (GroupBoard), gives them roles and times them
## together through the same HcOrder records high command uses (SquadOrders runs them), keeps a
## reserve, pulls back what's broken and counterattacks what it lost.
##
## - The plan says what the moment needs: HotZonePolicy (a hot zone: EnemyCommand's rules, which
##   keep deciding there), OperationPlan (phases and objectives) or DefencePlan (sites, lines, a
##   mobile reserve, counterattacks).
## - The tasking cycle (3.4.3), every task_s and at once on a trigger: the plan's needs, each
##   commanded group scored per need (suitability x CE x (1 - distance / reach) x availability -
##   commitment), assigned greedily from the highest need; an Assault never without its SBF, a group
##   with no AT power never against known armour; issued as an HcOrder with a sector and a rally;
##   each decision a "[cmd]" line in the session log with its reason.
## - Synchronisation (3.5.1): an Assault waits at its attack position until its SBF is set (or
##   sync_timeout_s), then goes ("Iron 2 is set." "Saber 1, go.").
## - Falling back (3.5.3): AMBER stops and holds and asks for help; RED breaks contact to its rally
##   and reconstitutes (two RED groups of a kind merge); the side withdraws past withdraw_share lost
##   or under withdraw_ce.
## - Who it commands: the groups registered with it (server_register: the employer's troops in an
##   operation, US forces in the living war; never the company, whose groups are on the board as
##   `taskable` false and are planned around). Virtual groups are tasked through their profile's
##   route.
## - For the RequestBroker (4.2.10): can_spare() and the executor for requests to its groups.
## One node a side present ("SideCommand_<side>"), host only. Numbers in data/side_command.json.

signal fire_support_wanted(pos: Vector3, why: String)
signal counterattack_seen(op: Dictionary)
signal phase_changed(index: int)
signal stalled(why: String)

const PATH := "res://data/side_command.json"
const ROLES: Array[String] = ["assault", "sbf", "flank", "recon", "reserve", "qrf", "screen", "defend", "overwatch", "fire_support",
	"resupply", "casevac", "transport", "counterattack", "probe", "reconstituting", "request"]
const GO := "alpha"

static var _data := {}

var side: StringName
## HotZonePolicy, OperationPlan or DefencePlan (all answer task_s, start, update, needs).
var plan: RefCounted
## id -> {"id", "squad", "orders": SquadOrders, "record" (a Virtualizer record or {}), "callsign",
## "kind", "role", "need", "set_at", "start_men", "amber"}.
var groups := {}
## Every [cmd] decision: {"text", "at"} (tests; also SessionLog).
var lines: Array[Dictionary] = []
## What the groups said on the net: {"callsign", "kind", "text", "at"}.
var net: Array[Dictionary] = []
var withdrawn := false
## Request jobs: request id -> group id (B4's executor).
var jobs := {}
## B3: armour id -> its infantry screen's id (ArmourInfantry.pair, each cycle).
var pairs := {}
## B3: hand-offs and AT asks already said ("armour|entry").
var handed := {}
var _offset := 0.0
var _task_left := 0.0
var _think_left := 0.0
var _own_board: GroupBoard
var _own_picture: SidePicture
var _requests := {}  # SquadOrders requests (break contact): answered by the commander at once


static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		var parsed: Variant = JSON.parse_string(text) if text != "" else null
		_data = parsed if parsed is Dictionary else {"_missing": true}
	return _data


static func num(key: String, fallback := 0.0) -> float:
	return float(data().get(key, fallback))


## Every peer may call it; only the host's runs. Adds side `p_side`'s commander to `level` with
## `p_plan` (once).
static func install(level: Node, p_side: StringName, p_plan: RefCounted) -> SideCommand:
	var n := "SideCommand_%s" % String(p_side)
	var have := level.get_node_or_null(n) as SideCommand
	if have:
		return have
	var cmd := SideCommand.new()
	cmd.name = n
	cmd.side = p_side
	cmd.plan = p_plan
	level.add_child(cmd)
	return cmd


static func of(from: Node, p_side: StringName) -> SideCommand:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null("SideCommand_%s" % String(p_side)) as SideCommand if lvl else null


func _ready() -> void:
	if plan and plan.has_method(&"start"):
		plan.call(&"start", self)
	if side == &"friendly":
		var broker := RequestBroker.of(self)
		if broker:
			broker.can_spare = can_spare
			broker.executor = execute_request


func now() -> float:
	return Soldier._now() + _offset


## Tests: moves this commander's clock on, runs its orders and a tasking cycle.
func advance(seconds: float) -> void:
	_offset += seconds
	think()
	server_cycle()


## The side's picture of its enemies (its own, when nothing else keeps one: an operation's side
## with no EnemyCommand).
func picture() -> SidePicture:
	var p := SideIntel.picture_of(self, side)
	if p:
		return p
	if _own_picture == null:
		_own_picture = SidePicture.new(side)
	return _own_picture


## The side's board: SideIntel's (friendly), EnemyCommand's (a hot zone), else its own.
func board() -> GroupBoard:
	if side == &"friendly":
		var intel := SideIntel.of(self)
		if intel:
			return intel.board
	elif side == &"hostile":
		var command := EnemyCommand.of(self)
		if command:
			return command.board
	if _own_board == null:
		_own_board = GroupBoard.new(side)
	return _own_board


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or plan == null:
		return
	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = num("think_s", 0.5)
		think()
	_task_left -= delta
	if _task_left <= 0.0:
		_task_left = float(plan.call(&"task_s"))
		server_cycle()


## A trigger (an objective fell or was lost, a group went RED, a counterattack seen, a request):
## the next cycle runs at once.
func trigger(why := "") -> void:
	_task_left = 0.0
	if why != "":
		_log("trigger: " + why)


# --- Groups --------------------------------------------------------------------------------------

## Host: `squad` is this commander's to task from now on (`kind` a GroupBoard kind, "" guessed;
## `record` its Virtualizer record if it may go virtual). Returns its id.
func server_register(squad: Squad, kind := "", callsign := "", record := {}) -> String:
	var id := GroupBoard.group_id(squad)
	if kind != "":
		squad.set_meta(&"group_kind", kind)
	if callsign != "":
		squad.set_meta(&"callsign", callsign)
		squad.callsign = callsign
	squad.hc_id = id
	_ensure_hero(squad)
	var so := SquadOrders.new(squad, self)
	groups[id] = {"id": id, "squad": squad, "orders": so, "record": record, "callsign": callsign if callsign != "" else String(squad.name),
		"kind": kind, "role": "", "need": "", "set_at": -INF, "start_men": maxi(squad.members().size(), Virtualizer.up(record) if not record.is_empty() else 0),
		"amber": false}
	if not record.is_empty():
		var v := Virtualizer.of(self)
		if v:
			v.track(record, "allied")
	_refresh_board(true)
	trigger("%s joins" % groups[id].callsign)
	return id


## Host: `squad` is no longer commanded (merged away, wiped out).
func server_unregister(id: String) -> void:
	var g: Dictionary = groups.get(id, {})
	if g.is_empty():
		return
	var so := g.orders as SquadOrders
	if so and not so.order.is_empty() and not HcOrder.ended(so.order):
		so.cancel()
	groups.erase(id)


## SquadOrders leads through the squad's hero: a commanded group's leader (else its first man up).
func _ensure_hero(squad: Squad) -> void:
	if squad.hero and is_instance_valid(squad.hero) and squad.hero.vitals.is_up():
		return
	var lead: Soldier = squad.leader if is_instance_valid(squad.leader) and squad.leader.vitals.is_up() else null
	if lead == null:
		for s: Soldier in squad.members():
			if s.vitals.is_up():
				lead = s
				break
	squad.hero = lead


## The board rows of this commander's groups, with their availability now.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var b := board()
	for id: String in groups:
		var row: Dictionary = b.rows.get(id, {})
		if row.is_empty():
			continue
		var r := row.duplicate()
		var g: Dictionary = groups[id]
		r["need"] = g.need
		r["role"] = g.role
		r["availability"] = availability(g)
		out.append(r)
	return out


## 3.4.3: 0 for a group mid-assault, 0.5 in Defend in a quiet sector (and any other task), 1 for a
## reserve or an idle group; none for one reconstituting or pulled out.
func availability(g: Dictionary) -> float:
	var a: Dictionary = data().get("availability", {})
	var role := String(g.role)
	var so := g.orders as SquadOrders
	var busy := so != null and not so.order.is_empty() and not HcOrder.ended(so.order)
	match role:
		"", "reserve", "qrf":
			return float(a.get("idle", 1.0))
		"assault", "counterattack":
			return float(a.get("assault", 0.0)) if busy else float(a.get("idle", 1.0))
		"reconstituting", "withdrawn":
			return 0.0
		"defend":
			var pic := picture()
			var quiet := pic == null or pic.entries_near(_group_pos(g), 300.0).is_empty()
			return float(a.get("defend_quiet", 0.5)) if quiet else 0.2
	return float(a.get("defend_quiet", 0.5)) if busy else float(a.get("idle", 1.0))


## Where group `g` is as its side knows it: its last sitrep.
func _group_pos(g: Dictionary) -> Vector3:
	var row: Dictionary = board().rows.get(g.id, {})
	return row.get("pos", Vector3.INF) if not row.is_empty() else Vector3.INF


func _refresh_board(force := false) -> void:
	if side == &"friendly" and SideIntel.of(self):
		if force:
			SideIntel.of(self).server_feed()
		return
	if side == &"hostile" and EnemyCommand.of(self):
		return
	var list: Array = []
	for g: Dictionary in groups.values():
		list.append(g.squad if (g.record as Dictionary).is_empty() else g.record)
	var b := board()
	if force:
		for g: Dictionary in groups.values():
			var id := String(g.id)
			if b.rows.has(id):
				b.rows[id].sitrep_at = -INF
	b.refresh(list, now())


# --- The cycle -----------------------------------------------------------------------------------

## Host: one tasking cycle (3.4.3).
func server_cycle() -> void:
	if plan == null:
		return
	var t := now()
	_refresh_board()
	plan.call(&"update", self, t)
	_fallbacks(t)
	_check_side(t)
	if withdrawn:
		return
	var needs: Array = plan.call(&"needs", self, t)
	needs = ArmourInfantry.apply(self, needs, plan.call(&"axis_dir") if plan.has_method(&"axis_dir") else Vector3.FORWARD)
	if needs.is_empty():
		return
	for a: Dictionary in allocate(needs, rows()):
		_issue(a.need, a.row, float(a.score))


## 3.4.3 steps 2-3, pure: assigns `rows` (board rows with "need", "availability") to `needs`
## ({"id", "role", "pos", "priority", "armour", "town", "pair" (an assault's SBF need id),
## "prefer" (a group id), "only" (the one group it's for)}), highest priority first. An Assault and
## its SBF go together or not at all; no group without AT power against armour.
## [{"need", "row", "score"}]. The rows go into packed arrays once: the inner loop is the budget.
static func allocate(needs: Array, rows: Array) -> Array[Dictionary]:
	var order := needs.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("priority", 0.0)) > float(b.get("priority", 0.0)))
	var by_id := {}
	var paired := {}
	for n: Dictionary in order:
		by_id[String(n.id)] = n
		if String(n.get("pair", "")) != "":
			paired[String(n.pair)] = true
	var reach: Dictionary = data().get("reach_m", {})
	var foot := float(reach.get("foot", 1500.0))
	var mounted := float(reach.get("mounted", 4000.0))
	var ids := PackedStringArray()
	var kinds := PackedStringArray()  # the distinct kinds
	var kind_of := PackedInt32Array()  # each row's index into them
	var tasked := PackedStringArray()
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	var ws := PackedFloat32Array()
	var ces := PackedFloat32Array()
	var reaches := PackedFloat32Array()
	var ats := PackedFloat32Array()
	for row: Dictionary in rows:
		var at: Vector3 = row.get("pos", Vector3.INF)
		ids.append(String(row.id))
		var k := String(row.get("kind", "rifle_squad"))
		var ki := kinds.find(k)
		if ki < 0:
			kinds.append(k)
			ki = kinds.size() - 1
		kind_of.append(ki)
		tasked.append(String(row.get("need", "")))
		xs.append(at.x if at.is_finite() else NAN)
		zs.append(at.z if at.is_finite() else NAN)
		ws.append(float(row.get("ce", 1.0)) * float(row.get("availability", 1.0)))
		ces.append(float(row.get("ce", 1.0)))
		reaches.append(mounted if not (row.get("mounted_in", []) as Array).is_empty() else foot)
		ats.append(float(row.get("at_cp", 0.0)))
	# (packed arrays are values: built here, then shared read-only; `taken` is the one that changes)
	var t := {"ids": ids, "kinds": kinds, "kind_of": kind_of, "needs": tasked, "x": xs, "z": zs, "w": ws, "ce": ces, "reach": reaches, "at": ats}
	var taken := PackedByteArray()
	taken.resize(ids.size())
	var out: Array[Dictionary] = []
	for n: Dictionary in order:
		if paired.has(String(n.id)):
			continue  # an assault's SBF: assigned with it
		if String(n.role) == "assault" and String(n.get("pair", "")) != "" and by_id.has(String(n.pair)):
			var sbf: Dictionary = by_id[String(n.pair)]
			var si := _best(sbf, t, taken, -1)
			if si.x < 0:
				continue
			var ai := _best(n, t, taken, int(si.x))
			if ai.x < 0:
				continue
			taken[int(si.x)] = 1
			taken[int(ai.x)] = 1
			out.append({"need": sbf, "row": rows[int(si.x)], "score": si.y})
			out.append({"need": n, "row": rows[int(ai.x)], "score": ai.y})
			continue
		var bi := _best(n, t, taken, -1)
		if bi.x >= 0:
			taken[int(bi.x)] = 1
			out.append({"need": n, "row": rows[int(bi.x)], "score": bi.y})
	return out


## The best row for need `n` in packed rows `t`: (index, score), index -1 for none.
static func _best(n: Dictionary, t: Dictionary, taken: PackedByteArray, also_not: int) -> Vector2:
	var only := String(n.get("only", ""))
	var role := String(n.role)
	var town := bool(n.get("town", false))
	var armour := bool(n.get("armour", false))
	var nid := String(n.id)
	var prefer := String(n.get("prefer", ""))
	var to: Vector3 = n.get("pos", Vector3.INF)
	var tx := to.x if to.is_finite() else NAN
	var tz := to.z if to.is_finite() else NAN
	var commitment := num("commitment", 0.2)
	var ids: PackedStringArray = t.ids
	var kinds: PackedStringArray = t.kinds
	var kind_of: PackedInt32Array = t.kind_of
	var tasked: PackedStringArray = t.needs
	var xs: PackedFloat32Array = t.x
	var zs: PackedFloat32Array = t.z
	var ws: PackedFloat32Array = t.ce if bool(n.get("override", false)) else t.w  # an override ignores how busy the group is
	var exclude: Dictionary = n.get("exclude", {})
	var has_exclude := not exclude.is_empty()
	var reaches: PackedFloat32Array = t.reach
	var ats: PackedFloat32Array = t.at
	var suits := PackedFloat32Array()
	for k in kinds:
		suits.append(suitability(k, role, town))
	var has_to := not is_nan(tx)
	var has_only := only != ""
	var has_prefer := prefer != ""
	var best := -1
	var top := 0.0
	for i in ids.size():
		var suit := suits[kind_of[i]]
		if suit <= 0.0 or taken[i] == 1 or i == also_not or (armour and ats[i] <= 0.0) or (has_only and ids[i] != only) or (has_exclude and exclude.has(ids[i])):
			continue
		var d := 0.0
		if has_to and not is_nan(xs[i]):
			var dx := xs[i] - tx
			var dz := zs[i] - tz
			d = sqrt(dx * dx + dz * dz)
		var sc := suit * ws[i] * maxf(1.0 - d / reaches[i], 0.0)
		var tk := tasked[i]
		if not tk.is_empty() and tk != nid:
			sc -= commitment
		if has_prefer and prefer == ids[i]:
			sc += 0.5
		if sc > top:
			top = sc
			best = i
	return Vector2(best, top)


## 3.4.3's score of board row `row` for need `n` (0 or less: can't).
static func score(row: Dictionary, n: Dictionary) -> float:
	if String(n.get("only", "")) != "" and String(n.only) != String(row.id):
		return 0.0  # a need for one group (its reserve, a counterattack's force)
	if bool(n.get("armour", false)) and float(row.get("at_cp", 0.0)) <= 0.0:
		return 0.0  # never a group with no AT power at known armour
	var suit := suitability(String(row.get("kind", "rifle_squad")), String(n.role), bool(n.get("town", false)))
	if suit <= 0.0:
		return 0.0
	var mounted := not (row.get("mounted_in", []) as Array).is_empty()
	var reach: float = (data().get("reach_m", {}) as Dictionary).get("mounted" if mounted else "foot", 1500.0)
	var at: Vector3 = row.get("pos", Vector3.INF)
	var to: Vector3 = n.get("pos", Vector3.INF)
	var d := Vector2(at.x - to.x, at.z - to.z).length() if at.is_finite() and to.is_finite() else 0.0
	var s := suit * float(row.get("ce", 1.0)) * maxf(1.0 - d / reach, 0.0) * float(row.get("availability", 1.0))
	if String(row.get("need", "")) != "" and String(row.need) != String(n.id):
		s -= num("commitment", 0.2)  # hysteresis: tasked groups aren't flipped for a little more
	if String(n.get("prefer", "")) == String(row.id):
		s += 0.5
	return s


## 3.4.2's table (data "suitability"); a kind not listed scores as a rifle squad.
static func suitability(kind: String, role: String, town := false) -> float:
	var table: Dictionary = data().get("suitability", {})
	var k: Dictionary = table.get(kind, table.get("rifle_squad", {}))
	var r := role
	if role in ["qrf"]:
		r = "reserve"
	elif role == "counterattack":
		r = "assault"
	elif role == "probe":
		r = "recon"
	elif role in ["resupply", "casevac", "transport"]:
		return 1.0 if kind in ["transport", "light_armour", "mech_infantry"] else 0.0
	if r == "assault" and town and k.has("town_assault"):
		return float(k.town_assault)
	return float(k.get(r, 0.0))


# --- Off-screen fights (3.8) ---------------------------------------------------------------------

## The virtual-fight kind of board row `row` (data "virtual_fight"): its heaviest vehicle, else by
## what its men carry.
static func fight_kind(row: Dictionary) -> String:
	var vk: Array = row.get("vehicle_kinds", [])
	if vk.has("mbt"):
		return "mbt"
	if vk.has("ifv"):
		return "ifv"
	if vk.has("light_armour"):
		return "mrap"
	if vk.has("soft_vehicle"):
		return "technical"
	match String(row.get("kind", "")):
		"at_team":
			return "at_team"
		"weapons_team", "gun_team":
			return "weapons_team"
	return "rifle_squad"


## How many times a rifle squad's hits a group of `attacker` kind lands on one of `target` kind
## (3.8's table): hard attack against an armoured target, soft against the rest, over a rifle
## squad's soft attack; light armour takes light_armour_share of the soft hits as well. Kinds not in
## the table count as a rifle squad.
static func fight_factor(attacker: String, target: String, attacker_at := false) -> float:
	var vf: Dictionary = data().get("virtual_fight", {})
	var a: Dictionary = vf.get(attacker, vf.get("rifle_squad", {}))
	var t: Dictionary = vf.get(target, vf.get("rifle_squad", {}))
	var base := float(vf.get("base_soft", 6.0))
	var hard := float(a.get("hard_with_at" if attacker_at else "hard", 1.0))
	var soft := float(a.get("soft", 6.0))
	match String(t.get("armoured", "no")):
		"yes":
			return hard / base
		"light":
			return maxf(hard, soft * float(vf.get("light_armour_share", 0.5))) / base
	return soft / base


# --- Issuing -------------------------------------------------------------------------------------

func _issue(n: Dictionary, row: Dictionary, s: float) -> void:
	var g: Dictionary = groups.get(String(row.id), {})
	if g.is_empty():
		return
	if String(g.need) == String(n.id) and String(g.role) == String(n.role):
		var so0 := g.orders as SquadOrders
		if so0 and not so0.order.is_empty() and not HcOrder.ended(so0.order):
			return  # already on it
	g.need = String(n.id)
	g.role = String(n.role)
	g.set_at = -INF
	g.amber = false
	_log("%s to %s on %s: score %.2f, %s %s at %d m" % [g.callsign, String(n.role).to_upper(), String(n.get("label", n.id)), s,
		String(row.get("kind", "")).replace("_", " "), String(row.get("ce_band", "")), roundi(_flat(row.pos, n.pos))])
	n = _sector(g, row, n)
	if not (g.record as Dictionary).is_empty():
		g.record["vf_kind"] = fight_kind(row)
	if not (g.record as Dictionary).is_empty() and Virtualizer.is_virtual(g.record):
		var route: Array[Vector3] = [n.pos]
		(g.squad as Squad).patrol = route  # a virtual group walks its profile's route there
		return
	var list := orders_for(n, g)
	for i in list.size():
		_give(g, list[i], i > 0)


## B5 (4.5): the task's sector, its corridor from the group to the task kept clear of the other
## groups' (a spot that can move moves sideways; an objective can't); the squad carries it
## (meta "sector") for Deconfliction.holds_fire. Returns the need, its spot maybe moved.
func _sector(g: Dictionary, row: Dictionary, n: Dictionary) -> Dictionary:
	var from: Vector3 = row.get("pos", n.pos)
	if not from.is_finite():
		return n
	var sec := Deconfliction.sector_of(from, n.pos, float(n.get("frontage", 0.0)))
	var others: Array = []
	for o: Dictionary in groups.values():
		if not is_same(o, g) and o.has("sector") and not (o.sector as Dictionary).is_empty():
			others.append(o.sector)
	if String(n.role) in ["sbf", "screen", "overwatch", "reserve", "recon", "probe", "flank", "qrf"]:
		var moved := Deconfliction.shift_clear(sec, others)
		if not (moved.to as Vector2).is_equal_approx(sec.to):
			n = n.duplicate()
			n.pos = Vector3(moved.to.x, (n.pos as Vector3).y, moved.to.y)
			_log("%s's lane shifted %.0f m to keep clear of another group's" % [g.callsign, (moved.to as Vector2).distance_to(sec.to)])
			sec = moved
	g.sector = sec
	(g.squad as Squad).set_meta(&"sector", sec)
	return n


## The HcOrders that carry out need `n` for group `g` (3.4.1's "compiles to").
func orders_for(n: Dictionary, g: Dictionary) -> Array[Dictionary]:
	var id := String(g.id)
	var p: Vector3 = n.pos
	var at := [p.x, p.z]
	var route: Array = []  # a move's way round the players' bubbles (B5), then the spot
	if side == &"friendly":
		for w: Vector3 in Deconfliction.detour(_group_pos(g), p, Deconfliction.players(self)):
			route.append([w.x, w.z])
	route.append(at)
	var target: Vector3 = n.get("target", p)
	var face: Variant = n.get("facing", null)
	var facing: Array = [] if face == null else [(face as Vector3).x, (face as Vector3).z]
	var out: Array[Dictionary] = []
	match String(n.role):
		"assault", "counterattack":
			out.append(HcOrder.make(id, "attack", [at], {"target": {"kind": "point", "pos": [target.x, target.z]}, "go": GO if n.get("pair", "") != "" else ""}))
		"sbf":
			out.append(HcOrder.make(id, "sbf", [at], {"target": {"kind": "point", "pos": [target.x, target.z]}}))
		"flank":
			out.append(HcOrder.make(id, "move", [at], {"posture": {"contact": "avoid"}}))
			out.append(HcOrder.make(id, "attack", [[target.x, target.z]], {"target": {"kind": "point", "pos": [target.x, target.z]}}))
		"recon", "probe":
			out.append(HcOrder.make(id, "move", route, {"posture": {"contact": "avoid", "mode": "stealth"}}))
		"reserve", "qrf", "reconstituting":
			out.append(HcOrder.make(id, "move", route, {"posture": {"mode": "aware"}}))
			out.append(HcOrder.make(id, "hold", []))
		"screen", "defend", "overwatch":
			out.append(HcOrder.make(id, "defend", [at], {"facing": facing}))
		"resupply", "casevac", "transport":
			out.append(HcOrder.make(id, "move", route))
		"fire_support":
			fire_support_wanted.emit(target, String(n.get("label", "")))
			out.append(HcOrder.make(id, "hold", []))
		_:
			out.append(HcOrder.make(id, "move", [at]))
	return out


## Gives `o` to group `g` (cleaned like a player's: HcOrder.clean), queued behind with `append`.
func _give(g: Dictionary, o: Dictionary, append := false) -> bool:
	var lvl := MapNodes.level_of(self)
	var ctx := {"commander": true, "squads": {String(g.id): true}, "phase2": true, "queued": (g.orders as SquadOrders).queue.size()}
	if lvl:
		var area: Rect2 = lvl.call(&"map_area")
		ctx["area"] = area
		var pts: Array = []
		for p: Variant in o.get("points", []):  # a spot worked out past the map's edge comes in to it
			pts.append([clampf(float(p[0]), area.position.x + 1.0, area.end.x - 1.0), clampf(float(p[1]), area.position.y + 1.0, area.end.y - 1.0)])
		o.points = pts
	var c := HcOrder.clean(o, ctx)
	if not bool(c.ok):
		_log("%s: order refused: %s" % [g.callsign, c.why])
		return false
	var order: Dictionary = c.order
	order.id = HcOrder.next_id()
	order.at = now()
	(g.orders as SquadOrders).give(order, append)
	return true


# --- Thinking: orders, synchronisation, request jobs -----------------------------------------------

## Every think_s: each group's SquadOrders, assaults waiting on their SBF, request jobs.
func think() -> void:
	var t := now()
	for g: Dictionary in groups.values():
		var squad := g.squad as Squad
		if squad == null or not is_instance_valid(squad):
			continue
		_ensure_hero(squad)
		if g.record is Dictionary and not (g.record as Dictionary).is_empty() and Virtualizer.is_virtual(g.record):
			continue
		(g.orders as SquadOrders).tick(Soldier._now())
	_sync(t)
	_watch_jobs()


## 3.5.1: an Assault set at its attack position goes when its SBF is set (firing), or after
## sync_timeout_s.
func _sync(t: float) -> void:
	for g: Dictionary in groups.values():
		if String(g.role) not in ["assault", "counterattack"]:
			continue
		var so := g.orders as SquadOrders
		if so == null or so.order.is_empty() or String(so.order.state) != "set" or String(so.order.get("go", "")) != GO:
			continue
		if float(g.set_at) == -INF:
			g.set_at = t
		var sbf := _pair_of(g)
		var ready := not sbf.is_empty() and sbf_ready(sbf)
		if ready or t - float(g.set_at) >= num("sync_timeout_s", 120.0):
			if ready:
				_say(sbf, "set", "%s is set." % sbf.callsign)
			_say(g, "go", "%s, go." % g.callsign)
			_log("%s goes in: %s" % [g.callsign, "support set" if ready else "support not set after %d s" % roundi(t - float(g.set_at))])
			so.go(GO)


## Whether SBF group `g` is set: at its position and firing (or set waiting).
static func sbf_ready(g: Dictionary) -> bool:
	var so := g.orders as SquadOrders
	if so == null or so.order.is_empty() or String(so.order.verb) != "sbf":
		return false
	return String(so.order.state) == "set" or String(so.order.get("phase", "")) == "execute"


## The SBF group paired with assault group `g` (the need's pair), or {}.
func _pair_of(g: Dictionary) -> Dictionary:
	var need := String(g.need)
	for other: Dictionary in groups.values():
		if not is_same(other, g) and String(other.role) == "sbf" and String(other.need) == need + ":sbf":
			return other
	return {}


# --- Falling back (3.5.3) -------------------------------------------------------------------------

func _fallbacks(t: float) -> void:
	var b := board()
	for g: Dictionary in groups.values():
		var row: Dictionary = b.rows.get(g.id, {})
		if row.is_empty():
			continue
		var band := String(row.ce_band)
		if band == "red" and String(g.role) != "reconstituting":
			g.role = "reconstituting"
			g.need = ""
			var rally := _rally_for(g, row)
			_give(g, HcOrder.make(String(g.id), "fall_back", [[rally.x, rally.z]]))
			_say(g, "casualty", "%s is red, falling back to %s." % [g.callsign, _grid(rally)])
			_log("%s RED: breaks contact to its rally" % g.callsign)
			trigger()
		elif band == "amber" and String(g.role) in ["assault", "flank", "counterattack"] and not bool(g.amber):
			g.amber = true
			var so := g.orders as SquadOrders
			if so and not so.order.is_empty() and not HcOrder.ended(so.order) and String(so.order.get("phase", "")) != "execute":
				_give(g, HcOrder.make(String(g.id), "hold", []))
			_say(g, "held_up", "%s, amber, holding, need support." % g.callsign)
			_log("%s AMBER: holds and asks for support" % g.callsign)
	_reconstitute()


## Two RED groups of the same kind at their rally merge into one (the larger keeps its name).
func _reconstitute() -> void:
	var red: Array[Dictionary] = []
	for g: Dictionary in groups.values():
		if String(g.role) == "reconstituting":
			red.append(g)
	var merge_m := num("merge_m", 60.0)
	for i in red.size():
		for j in range(i + 1, red.size()):
			var a: Dictionary = red[i]
			var b: Dictionary = red[j]
			if not groups.has(a.id) or not groups.has(b.id) or _kind(a) != _kind(b):
				continue
			if _flat(_group_pos(a), _group_pos(b)) > merge_m:
				continue
			var a_bigger := (a.squad as Squad).members().size() >= (b.squad as Squad).members().size()
			var keep: Dictionary = a if a_bigger else b
			var go: Dictionary = b if a_bigger else a
			for s: Soldier in (go.squad as Squad).members():
				var brain := SquadAI.of(s)
				if brain:
					brain.squad = keep.squad
			_log("%s merges into %s" % [go.callsign, keep.callsign])
			_say(keep, "copy", "%s and %s merged, reconstituting." % [keep.callsign, go.callsign])
			server_unregister(String(go.id))
			keep.role = ""
			keep.need = ""
			_refresh_board(true)


func _kind(g: Dictionary) -> String:
	var row: Dictionary = board().rows.get(g.id, {})
	return String(row.get("kind", g.kind))


func _rally_for(g: Dictionary, row: Dictionary) -> Vector3:
	if plan.has_method(&"rally_for"):
		var r: Variant = plan.call(&"rally_for", self, g)
		if r is Vector3 and (r as Vector3).is_finite():
			return r
	var at: Vector3 = row.pos
	var away := Vector3.ZERO
	var pic := picture()
	if pic:
		for e: Dictionary in pic.entries_near(at, 600.0):
			away += (at - (e.pos as Vector3))
	away.y = 0.0
	return at + (away.normalized() if away.length() > 0.1 else Vector3.BACK) * num("rally_back_m", 250.0)


## The side's state (3.5.3): past withdraw_share of its men lost, or its CE under withdraw_ce, it
## pulls back (friendly: to the last phase line; hostile: consolidates).
func _check_side(t: float) -> void:
	if withdrawn or groups.is_empty():
		return
	var start := 0
	var up := 0
	var ce_sum := 0.0
	var b := board()
	for g: Dictionary in groups.values():
		start += int(g.start_men)
		var row: Dictionary = b.rows.get(g.id, {})
		up += int(row.get("up", 0))
		ce_sum += float(row.get("ce", 0.0)) * int(row.get("up", 0))
	if start <= 0:
		return
	var lost := 1.0 - float(up) / start
	var ce := ce_sum / maxf(up, 1)
	if lost < num("withdraw_share", 0.5) and (up == 0 or ce >= num("withdraw_ce", 0.4)):
		return
	withdrawn = true
	_log("the side withdraws: %d%% lost, CE %.2f" % [roundi(lost * 100.0), ce])
	if plan.has_method(&"withdraw"):
		plan.call(&"withdraw", self, t)


# --- Requests (4.2.10, B4) ------------------------------------------------------------------------

## RequestBroker.can_spare: {"ok", "why", "delay_s"}; {} for a group this commander doesn't command.
func can_spare(row: Dictionary, r: Dictionary) -> Dictionary:
	var g: Dictionary = groups.get(String(row.get("id", "")), {})
	if g.is_empty():
		return {}
	var so := g.orders as SquadOrders
	var busy := so != null and not so.order.is_empty() and not HcOrder.ended(so.order)
	match String(g.role):
		"assault", "counterattack":
			if busy:
				return {"ok": false, "why": "Committed to an assault"}
		"reserve":
			if plan.has_method(&"counterattack_seen") and bool(plan.call(&"counterattack_seen", self)) and _reserves() <= 1:
				return {"ok": false, "why": "We're the last reserve"}
		"sbf", "flank":
			if busy:
				return {"ok": false, "why": "Our orders are to push", "delay_s": 120.0}
	return {"ok": true}


func _reserves() -> int:
	var n := 0
	for g: Dictionary in groups.values():
		if String(g.role) == "reserve":
			n += 1
	return n


## RequestBroker.executor: an accepted request to one of its groups becomes that group's job.
func execute_request(r: Dictionary) -> void:
	var g: Dictionary = groups.get(String(r.group), {})
	if g.is_empty():
		return
	var tp: Vector3 = r.target.pos
	var here := _group_pos(g)
	var o: Dictionary
	match String(r.kind):
		"suppress", "cover":
			o = HcOrder.make(String(g.id), "sbf", [[here.x, here.z]], {"target": {"kind": "point", "pos": [tp.x, tp.z]}})
		"hold":
			o = HcOrder.make(String(g.id), "hold", [])
		_:
			o = HcOrder.make(String(g.id), "move", [[tp.x, tp.z]])
	g.role = "request"
	g.need = "request:%d" % int(r.id)
	jobs[int(r.id)] = String(g.id)
	_give(g, o)


## Request jobs move on with their group's order: route = en route, firing or there = on station,
## ended = done or failed.
func _watch_jobs() -> void:
	var broker := RequestBroker.of(self)
	if broker == null or jobs.is_empty():
		return
	for rid: int in jobs.keys():
		var r: Dictionary = broker.requests.get(rid, {})
		var g: Dictionary = groups.get(String(jobs[rid]), {})
		if r.is_empty() or g.is_empty() or not (String(r.state) in RequestBroker.OPEN):
			jobs.erase(rid)
			if not g.is_empty() and String(g.role) == "request":
				g.role = ""
				g.need = ""
			continue
		var so := g.orders as SquadOrders
		var o := so.order
		if o.is_empty():
			continue
		if HcOrder.ended(o):
			if String(r.state) != "on_station":
				broker.server_progress(rid, "done" if String(o.state) == "done" else "failed", "" if String(o.state) == "done" else "%s: %s" % [g.callsign, o.why])
			continue
		var there := String(o.get("phase", "")) == "execute" or String(o.state) == "set"
		if there and String(r.state) != "on_station":
			broker.server_progress(rid, "on_station")
		elif not there and String(r.state) == "acked":
			broker.server_progress(rid, "en_route")


# --- What SquadOrders asks of its commander (the same calls HighCommand answers) --------------------

func order_changed(_o: Dictionary) -> void:
	pass


func radio(so: SquadOrders, kind: String, text: String, _pos: Variant = null) -> void:
	var g: Dictionary = groups.get(String(so.squad.hc_id), {})
	_say(g, kind, "%s, %s" % [g.get("callsign", "Unit"), text])


func share_contact(_so: SquadOrders, _cluster: Dictionary) -> void:
	pass  # contacts reach the side through its picture (SideIntel feeds every group's clusters)


## A group asks to break contact: its commander says yes (3.5.3: RED groups fall back anyway).
func server_request(so: SquadOrders, kind: String, text: String, answer: Callable, _default_yes: bool) -> int:
	radio(so, "request", text)
	_log("%s asks: %s (%s), approved" % [String(so.squad.hc_id), kind, text])
	answer.call(true)
	return 0


# --- Lines ---------------------------------------------------------------------------------------

func _log(text: String) -> void:
	lines.append({"text": text, "at": now()})
	if lines.size() > 200:
		lines.pop_front()
	SessionLog.note("[cmd] %s: %s" % [String(side), text])


## A group's line on its side's net: the coordination net for the friendly side (every player
## hears it, through the RequestBroker), the enemy net for the hostile one (a looted radio).
func _say(g: Dictionary, kind: String, text: String) -> void:
	net.append({"callsign": String(g.get("callsign", "")), "kind": kind, "text": text, "at": now()})
	if net.size() > 100:
		net.pop_front()
	if side == &"friendly":
		var broker := RequestBroker.of(self)
		if broker:
			broker._say(String(g.get("callsign", "")), text)
	else:
		var radio_chatter := get_parent().get_node_or_null(^"RadioChatter") as RadioChatter if get_parent() else null
		if radio_chatter:
			radio_chatter.order(text, String(g.get("callsign", RadioChatter.NET_CALLSIGN)))


func _grid(pos: Vector3) -> String:
	var lvl := MapNodes.level_of(self)
	return MapGrid.grid_ref_3d(pos, lvl.call(&"map_area")) if lvl else "%.0f %.0f" % [pos.x, pos.z]


static func _flat(a: Vector3, b: Vector3) -> float:
	if not a.is_finite() or not b.is_finite():
		return INF
	return Vector2(a.x - b.x, a.z - b.z).length()
