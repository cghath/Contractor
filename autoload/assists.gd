extends Node
## Optional assists for co-op newcomers (wave 7, S4; docs/ChrisPlan_handoff.md "Wave 7", S4):
## off by default and set by the host for the whole session, so a squad plays by one set of
## rules. The host's picks are its own settings (GameSettings "assists", the settings menu's
## Assists rows); they go to every client as they change and to each one that joins late.
## A client can't turn them on: its rows are greyed out, a request from it is refused, and a
## sync from anyone but the host is ignored.
##
## - aim_slowdown: on a gamepad, the right stick turns slower while the crosshair is on or
##   near an enemy who is up (aim_slowdown_mult; the mouse is never touched).
## - wound_hints: a HUD line naming your worst wound and what to use on it (wound_hint).
## Objective markers were already on the HUD before this (ObjectiveHelper, the player's own
## "Objective markers on screen" setting, on by default), so they aren't an assist here.

signal changed

## The assists and their labels for the settings menu.
const NAMES := [
	["aim_slowdown", "Aim slowdown on a gamepad (the stick turns slower over an enemy)"],
	["wound_hints", "Wound hints (a HUD line: your worst wound and what to use)"],
]
## Aim slowdown: within this angle (degrees) of an enemy's chest, out to SLOW_RANGE_M, the
## stick turns at SLOW_MULT of its rate (closest at the centre, easing back out to the edge).
const SLOW_ANGLE_DEG := 4.0
const SLOW_RANGE_M := 200.0
const SLOW_MULT := 0.4

## The session's assists now: the host's, here and on every client.
var state := {}


func _ready() -> void:
	state = defaults()
	if not Engine.is_editor_hint():
		Net.hosted.connect(_on_hosted)
		Net.joined.connect(func() -> void: _apply(defaults()))  # until the host's arrive
		Net.session_ended.connect(_on_hosted)  # back on your own: your own picks
		Net.peer_joined.connect(_on_peer_joined)
		_on_hosted()


## Every assist off (what a client has until its host says otherwise).
static func defaults() -> Dictionary:
	var out := {}
	for pair: Array in NAMES:
		out[pair[0]] = false
	return out


func is_on(key: String) -> bool:
	return bool(state.get(key, false))


## Whether this machine sets the assists: the host, or playing alone.
func can_set() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


## The host turns an assist on or off: saved as its pick and sent to every client. A client's
## call is refused (false) and changes nothing.
func set_assist(key: String, on: bool) -> bool:
	if not can_set() or not state.has(key):
		return false
	GameSettings.set_value("assists", key, on)
	var next := state.duplicate()
	next[key] = on
	_apply(next)
	if Net.is_hosting():
		_sync.rpc(state)
	return true


## A client asking the host to change an assist: always refused (only the host's own menu
## sets them). Kept so the refusal is explicit and logged.
@rpc("any_peer", "call_remote", "reliable")
func request_assist(key: String, on: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not accepts_request_from(sender):
		print("[assists] refused %s=%s from peer %d (the host sets assists)" % [key, on, sender])


## Only the host itself may change the assists (a request from any peer is refused).
static func accepts_request_from(sender: int) -> bool:
	return sender == 0 or sender == 1  # 0: called locally, not over the network


## A sync is taken only from the host (peer 1).
static func accepts_sync_from(sender: int) -> bool:
	return sender == 1


@rpc("authority", "call_remote", "reliable")
func _sync(next: Dictionary) -> void:
	if not accepts_sync_from(multiplayer.get_remote_sender_id()):
		return
	receive(next)


## Takes the host's assists (only the keys there are, as booleans).
func receive(next: Dictionary) -> void:
	var clean := defaults()
	for key: String in clean:
		clean[key] = bool(next.get(key, false))
	_apply(clean)


func _apply(next: Dictionary) -> void:
	if next == state:
		return
	state = next
	changed.emit()


## Hosting, or alone: the assists are this machine's own picks.
func _on_hosted() -> void:
	var mine := defaults()
	for key: String in mine:
		mine[key] = bool(GameSettings.get_value("assists", key))
	_apply(mine)


func _on_peer_joined(id: int) -> void:
	if Net.is_hosting():
		_sync.rpc_id(id, state)  # a late joiner gets the session's assists


# --- The assists ------------------------------------------------------------------------------

## Aim slowdown: what the stick's turn rate is multiplied by now for `body` looking through
## `camera` (1.0 with the assist off, or no enemy who is up near the crosshair).
func aim_slowdown_mult(body: Soldier, camera: Camera3D) -> float:
	if not is_on("aim_slowdown") or body == null or camera == null:
		return 1.0
	return slowdown_near(body, camera.global_position, -camera.global_basis.z)


## The slowdown for a view from `eye` along `forward`: SLOW_MULT on an enemy's chest, easing
## back to 1.0 at SLOW_ANGLE_DEG off it.
static func slowdown_near(body: Soldier, eye: Vector3, forward: Vector3) -> float:
	var best := 1.0
	for node: Node in body.get_tree().get_nodes_in_group(&"combatants"):
		var other := node as Soldier
		if other == null or other == body or other.faction == body.faction or not other.vitals.is_up():
			continue
		var to := other.global_position + Vector3(0, 1.3, 0) - eye
		var dist := to.length()
		if dist < 0.5 or dist > SLOW_RANGE_M:
			continue
		var off := rad_to_deg(forward.angle_to(to))
		if off < SLOW_ANGLE_DEG:
			best = minf(best, lerpf(SLOW_MULT, 1.0, off / SLOW_ANGLE_DEG))
	return best


## Wound hints: a short line on your worst wound and what to use on it ("" with the assist off,
## or nothing to treat).
func wound_hint(body: Soldier) -> String:
	if not is_on("wound_hints") or body == null:
		return ""
	return hint_for(body)


## The hint for `body`'s most urgent care task (Vitals.care_needed, most urgent first): the
## wound, where, and the item (whether you carry it).
static func hint_for(body: Soldier) -> String:
	var tasks := body.vitals.care_needed()
	if tasks.is_empty():
		return ""
	var task: Dictionary = tasks[0]
	var carried := Vitals.pick_item(task, body.inventory)
	var item_id: StringName = carried if carried != &"" else Vitals.task_items(task)[0]
	var item := ItemDB.get_item(item_id) if ItemDB.has_item(item_id) else null
	var item_name := item.name if item else String(item_id)
	var kind := String(task.get("kind", ""))
	var what: String = WOUND_WORDS.get(kind, kind.replace("_", " "))
	var line := "Worst: %s (%s). Use %s" % [what, Vitals.part_name(task.get("part", &"torso")), item_name]
	if carried == &"":
		line += " (you have none: ask a squadmate)"
	elif Vitals.needs_other_hands(item_id):
		line += " (needs someone else's hands)"
	return line + ". [%s] medical menu" % GameSettings.binding_name(GameSettings.key_for(&"medical_menu"))


## Care task kinds (WoundModel.care_tasks) in plain words for the hint.
const WOUND_WORDS := {
	"arterial": "arterial bleeding", "junctional": "junctional bleeding", "internal": "internal bleeding",
	"venous": "bleeding", "muscle": "muscle wound", "graze": "graze", "chest": "open chest wound",
	"tension": "tension pneumothorax", "airway": "airway at risk", "pelvis": "broken pelvis", "fracture": "fracture",
	"access": "blood loss (needs a line)", "fluids": "blood loss (needs fluids)", "pressure": "blood loss (collapsed veins)",
	"hypothermia": "getting cold", "defib": "heart stopped", "cpr": "heart stopped", "epinephrine": "heart stopped",
	"racing": "heart racing", "slow_heart": "heart too slow", "burn": "burn", "pain": "pain", "wake": "out cold",
}
