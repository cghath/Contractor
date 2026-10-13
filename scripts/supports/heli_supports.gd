class_name HeliSupports
extends Node
## The Black Hawk supports (wave 5b V3): resupply, transport (hot zones only) and extraction,
## called from the command menu's Support entry (0) through Supports, and the helicopter
## insertion a hot zone's briefing can pick. One node, "HeliSupports", in every level on every
## peer (CompoundLevel adds it), so its radio reaches every player; the calls themselves
## (HeliCall) run on the host.
##
## A call ("support:<kind>[:<how>]"), host side, in order (server_call):
## - refused when that support was lost this op (Captain: a lost asset is gone for the rest of
##   the op), when helicopters can't fly (Supports.can_fly: storms, wave 7), transport outside a
##   hot zone (Captain), extraction with no deployment to end, or while its cooldown runs;
## - where: "marker" (the caller's newest point marker on the map: a grid reference), "here"
##   (the spot under the caller's crosshair), "grid:<ref>" (a typed grid reference), or "smoke":
##   the helicopter comes in and loiters near the players until it sees a smoke of its colours
##   (SMOKE_COLOURS in data/supports.json: resupply green or yellow, transport green or blue,
##   extraction purple; the first call takes a smoke both want). A mark given while one is on
##   its way (or loitering) redirects it, free;
## - paid with Economy.server_pay_support(kind, contract id): the deployment's support budget
##   first, then cash (refused if it can't be paid). With DevTools.on() outside a deployment
##   (the vehicle range, the test zone) every call is free and transport flies anywhere, not
##   just in hot zones: the dev way to try each one;
## - one of each kind at a time.
## "cancel" sends that support home (a transport with people aboard first lands them).
##
## Radio: every step goes out to every player as "<callsign>: <line>" (HUD flash), and every
## peer keeps the lines it heard (heard). The state dumps (SessionLog) get readout().
## Numbers are Proposed; most are in data/supports.json.

signal radio_heard(text: String)

const NODE_NAME := "HeliSupports"
const DATA_PATH := "res://data/supports.json"
const KINDS: Array[String] = ["resupply", "transport", "extraction"]
const MODEL := "uh60"
## Proposed: on a zone, helicopters appear this far inside the edge (its invisible wall) and
## leave by it; on a small map (the vehicle range) at least MIN_INBOUND_M from where they go.
const SPAWN_INSET_M := 80.0
const MIN_INBOUND_M := 700.0
## Helicopter insertion (hot zones): it starts this far out from the insertion point.
const INSERT_START_M := 1500.0
## Lines kept on each peer.
const HEARD_KEEP := 60

## Tests: helicopters start (and leave) this far from where they go, not from their origin
## (-1: from the origin).
static var start_m := -1.0
## Tests: calls are free (true), paid (false), or the default (-1: free only with DevTools.on()
## outside a deployment).
static var free_calls := -1
## Tests: launches fail (as when no helicopter can be spawned), to check the refund.
static var launch_fails := false

static var _data := {}

## Every peer: radio lines heard, newest last.
var heard: Array[String] = []
## Host: the calls under way, oldest first.
var calls: Array[HeliCall] = []
## Host: smoke cloud instance id -> the call that took it.
var claimed := {}
var _cooldown_until := {}  # host: kind -> Soldier._now() it can be called again
var _lost := {}            # host: kind -> true once lost this op


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	HeliSupports.register_all()


## The level's HeliSupports node (or null).
static func of(from: Node) -> HeliSupports:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NodePath(NODE_NAME)) as HeliSupports if lvl else null


## Registers resupply, transport and extraction with Supports (every level does on _ready;
## tests call it again after Supports.reset()).
static func register_all() -> void:
	for kind: String in KINDS:
		Supports.register(kind, func(caller: Node, arg: String, point: Vector3, _names: PackedStringArray) -> String:
			var node := HeliSupports.of(caller)
			return node.server_call(kind, caller as Soldier, arg, point) if node else "That support isn't available")


## The numbers in data/supports.json.
static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {}
		if _data.is_empty():
			push_error("HeliSupports: cannot read %s" % DATA_PATH)
	return _data


static func callsign(kind: String) -> String:
	return String((data().get("callsigns", {}) as Dictionary).get(kind, "Blackhawk"))


## The smoke colours a support lands on.
static func smoke_colours(kind: String) -> Array:
	return (data().get("smoke", {}) as Dictionary).get(kind, [])


static func cooldown_s(kind: String) -> float:
	return float((data().get("cooldown_s", {}) as Dictionary).get(kind, 0.0))


func level() -> CompoundLevel:
	return get_parent() as CompoundLevel


## Host: the call of `kind` under way, or null.
func active(kind: String) -> HeliCall:
	for c in calls:
		if c.kind == kind and not c.is_over():
			return c
	return null


## Host: whether `kind` was lost this op.
func is_lost(kind: String) -> bool:
	return _lost.has(kind)


## Host: seconds until `kind` can be called again (0 now).
func cooldown_left(kind: String) -> float:
	return maxf(float(_cooldown_until.get(kind, 0.0)) - Soldier._now(), 0.0)


# --- Calls (host) -------------------------------------------------------------------------------

## Host: `caller` calls support `kind` with `arg` ("marker", "here", "grid:<ref>", "smoke",
## "dest", "cancel"; see the class doc) at `point` (the crosshair's ground for "here").
## Returns "" when it went, or why not (Soldier shows it to the caller).
func server_call(kind: String, caller: Soldier, arg: String, point: Vector3) -> String:
	if not multiplayer.is_server() or caller == null:
		return "That support isn't available"
	var how := arg.get_slice(":", 0)
	var lvl := level()
	var current := active(kind)
	if how == "cancel":
		if current == null:
			return "No %s helicopter is out" % kind
		return current.server_cancel()
	if current:
		if kind == "transport" and (how == "dest" or current.wants_destination()):
			var where := _resolve(caller, "marker" if how == "dest" else arg, point)
			if where.has("why"):
				return String(where.why)
			return current.server_set_destination(where)
		if how == "dest":
			return "Call a transport first"
		var mark := _resolve(caller, arg, point)
		if mark.has("why"):
			return String(mark.why)
		return current.server_redirect(mark)
	if how == "dest":
		return "Call a transport first"
	if is_lost(kind):
		return "No helicopter left for %s: it was lost this op" % kind
	if not Supports.can_fly(lvl):
		return "Helicopters are grounded: the weather won't let them fly"
	if kind == "transport" and not Supports.is_hot_zone(lvl) and not _free():  # dev sessions: anywhere, to try it
		return "Helicopter transport flies in hot zones only"
	var extraction := MapNodes.extraction(self)
	if kind == "extraction" and (extraction == null or not extraction.is_active()) and not _free():
		return "No deployment to extract from"
	if cooldown_left(kind) > 0.0:
		return "%s is available again in %d s" % [kind.capitalize(), ceili(cooldown_left(kind))]
	var target := _resolve(caller, arg, point)
	if target.has("why"):
		return String(target.why)
	var cid := _contract_for_support()
	var budget_before := int(Contracts.contract(cid).get("support_left", 0)) if cid != "" else 0
	var paid := false
	if not _free():
		if not Economy.server_pay_support(kind, cid):
			return "Can't pay for the %s ($%s)" % [kind, DebriefCalc.money(Economy.support_price(kind))]
		paid = true
	if kind == "extraction" and extraction and not extraction.is_active():
		extraction.server_begin({})  # dev, outside a deployment: open extraction to end
	var call := HeliCall.new(self, kind, caller, target)
	if launch_fails or not call.server_launch():
		if is_instance_valid(call.heli):
			call.server_dismiss()
		if paid:
			_refund(kind, cid, budget_before)
		return "No helicopter could take off"
	calls.append(call)
	_cooldown_until[kind] = Soldier._now() + cooldown_s(kind)
	return ""


## Host (Briefing's "heli" insertion, hot zones): the squad (players and AI squadmates) starts
## aboard a UH-60 flying in to `at` (x, z) and landing there (or within 100 m). Returns whether
## it went; on false the caller puts the squad there on foot.
static func server_insert(from: Node, at: Vector2) -> bool:
	var node := HeliSupports.of(from)
	if node == null or not node.multiplayer.is_server() or not Supports.can_fly(node.level()):
		return false
	var pos := node.level().ground_point(Vector3(at.x, 0.0, at.y))
	var call := HeliCall.new(node, "insertion", null, {"source": "grid", "pos": pos})
	if not call.server_launch():
		return false
	node.calls.append(call)
	return true


## Host: a call's helicopter went down: that support is lost for the rest of the op.
func server_lost(kind: String) -> void:
	if kind in KINDS:
		_lost[kind] = true


## Host (tests): forget cooldowns and losses.
func server_reset_limits() -> void:
	_cooldown_until.clear()
	_lost.clear()


## Host (tests): every call ends and its helicopter goes at once.
func server_dismiss_all() -> void:
	for c in calls:
		c.server_dismiss()
	calls.clear()
	claimed.clear()


func _free() -> bool:
	if free_calls >= 0:
		return free_calls == 1
	return DevTools.on() and not Contracts.is_deployed()


## Host: gives back what server_pay_support took for `kind` (a call that couldn't launch): the
## support budget it drew from contract `cid` (which had `budget_before` left), the rest as cash.
static func _refund(kind: String, cid: String, budget_before: int) -> void:
	var price := Economy.support_price(kind)
	var from_budget := 0
	if cid != "":
		from_budget = clampi(budget_before - int(Contracts.contract(cid).get("support_left", 0)), 0, price)
		if from_budget > 0:
			Contracts.server_draw_support(cid, -from_budget)
	Economy.add_cash(price - from_budget, "Support refund: %s" % kind)


## The deployment's contract with the most support budget left ("" outside a deployment).
static func _contract_for_support() -> String:
	var best := ""
	var most := -1
	for cid: String in Contracts.deployment().get("cids", []):
		var left := int(Contracts.contract(cid).get("support_left", 0))
		if left > most:
			best = cid
			most = left
	return best


## Where a call goes: {"source": "grid", "pos": Vector3 (on the ground)}, {"source": "smoke"}
## (look for smoke), or {"why": String} when it can't be worked out.
func _resolve(caller: Soldier, arg: String, point: Vector3) -> Dictionary:
	var how := arg.get_slice(":", 0)
	var lvl := level()
	match how:
		"", "smoke":
			return {"source": "smoke"}
		"here":
			if not point.is_finite():
				return {"why": "Look at a spot on the ground"}
			return {"source": "grid", "pos": lvl.ground_point(Vector3(point.x, 0.0, point.z))}
		"marker", "dest":
			var marker: Variant = newest_marker(caller)
			if marker == null:
				return {"why": "Put a marker on the map first (M, double-click)"}
			var p: Vector2 = marker
			return {"source": "grid", "pos": lvl.ground_point(Vector3(p.x, 0.0, p.y))}
		"grid":
			var at: Variant = MapGrid.parse(arg.substr(5), MapNodes.area_of(self))
			if at == null:
				return {"why": "That isn't a grid reference"}
			var g: Vector2 = at
			return {"source": "grid", "pos": lvl.ground_point(Vector3(g.x, 0.0, g.y))}
	return {"why": "Order not understood"}


## The newest point marker `caller` placed on the map (x, z), or null.
func newest_marker(caller: Soldier) -> Variant:
	var markers := MapNodes.markers(self)
	if markers == null or caller == null:
		return null
	var newest: Variant = null
	for m: Dictionary in markers.list("field") + markers.list("plan"):
		if String(m.get("kind", "")) == "point" and int(m.get("author", -1)) == caller.owner_peer():
			if newest == null or int(m.id) > int((newest as Dictionary).id):
				newest = m
	if newest == null:
		return null
	return ((newest as Dictionary).points as PackedVector2Array)[0]


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or calls.is_empty():
		return
	for c in calls.duplicate():
		c.step(delta)
		if c.is_finished():
			calls.erase(c)
			for id: int in claimed.keys():
				if claimed[id] == c:
					claimed.erase(id)


# --- Radio (every peer) ---------------------------------------------------------------------------

## Host: a radio line from `kind`'s helicopter to every player.
func server_radio(kind: String, text: String) -> void:
	if multiplayer.is_server():
		_client_radio.rpc("%s: %s" % [HeliSupports.callsign(kind), text])


@rpc("authority", "call_local", "reliable")
func _client_radio(text: String) -> void:
	heard.append(text)
	while heard.size() > HEARD_KEEP:
		heard.pop_front()
	MapNodes.flash_local(self, text)
	radio_heard.emit(text)


## Whether a line containing `part` was heard here.
func heard_line(part: String) -> bool:
	for line in heard:
		if line.contains(part):
			return true
	return false


# --- State dumps ----------------------------------------------------------------------------------

## The helicopter supports for a state dump (SessionLog.state_text): each call's kind, state,
## position, target and who's aboard; cooldowns and losses. "" when there's nothing to say.
static func readout(from: Node) -> String:
	var node := HeliSupports.of(from) if from and from.is_inside_tree() else null
	if node == null:
		return ""
	var lines: Array[String] = []
	for c in node.calls:
		lines.append("  " + c.describe())
	for kind: String in KINDS:
		if node.is_lost(kind):
			lines.append("  %s: lost this op" % kind)
		elif node.cooldown_left(kind) > 0.0:
			lines.append("  %s: cooldown %d s" % [kind, ceili(node.cooldown_left(kind))])
	if lines.is_empty():
		return ""
	return "Helicopter supports:\n" + "\n".join(lines)
