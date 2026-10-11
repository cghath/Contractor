extends Node
## Autoload "People": the deployment's ledger of people and intel (wave 4, W11), host-owned
## and replicated to every peer and late joiner.
##
## - Civilian casualties caused by the players' side (players and their AI squad); civilians
##   hurt by anyone else don't count (design doc "Missions": fines, reputation, and the
##   contract voided at 8). Each civilian gives at most one "wounded" event (the first hit
##   from our side) and one "killed" event (dying after that).
## - Intel banked: items carried out to an extraction point, and enemy positions reported by
##   radio (banked at once). Each has its own intel_id and a proposed value.
## - HVTs delivered to an extraction point (the objective hook).
##
## The economy reads it three ways: the signals, summary() (the debrief), or by adding a node
## to LISTENER_GROUP with on_civilian_casualty(event), on_intel_banked(entry) and
## on_hvt_delivered(event) (host; any it lacks are skipped). The deployment part and every
## piece of intel ever banked (archive, for leads) are kept in the campaign's "people" section
## (Campaign), so they survive a save; reset_deployment() starts a new deployment.

signal civilian_casualty(event: Dictionary)
signal intel_banked(entry: Dictionary)
signal hvt_delivered(event: Dictionary)
## The ledger changed (every peer, after a replicated update too).
signal changed

const SECTION := &"people"
const LISTENER_GROUP := &"mission_listeners"
const WOUNDED := "wounded"
const KILLED := "killed"
## The contract is voided at this many civilian casualties (design doc; the economy decides).
const VOID_AT := 8

## This deployment's civilian casualty events, oldest first: {"civilian" (name), "uid",
## "kind" (WOUNDED or KILLED), "shooter", "shooter_faction", "shooter_player",
## "shooter_peer", "zone", "pos" ([x, z]), "time" (unix seconds)}.
var casualties: Array = []
## This deployment's banked intel, oldest first: {"intel_id", "how" ("carried" or
## "reported"), "item" (an intel item id, "" for a report), "name", "value", "source", "by",
## "zone", "time"; a report also "pos" ([x, z]), "count" and "enemies"}.
var intel: Array = []
## This deployment's HVT deliveries: {"hvt_id", "name", "side", "alive", "cuffed", "by",
## "point" ([x, z]), "zone", "time"}.
var deliveries: Array = []
## Host: every piece of intel ever banked in this campaign (leads for later contracts).
var archive: Array = []

var _loading := false


func _ready() -> void:
	Net.peer_joined.connect(_on_peer_joined)
	Campaign.changed.connect(_on_campaign_changed)


# --- Reading it ----------------------------------------------------------------------------

## How many different civilians our side has hurt or killed this deployment.
func casualty_count() -> int:
	var seen := {}
	for e: Dictionary in casualties:
		seen[e.uid] = true
	return seen.size()


func civilians_killed() -> int:
	return casualties.filter(func(e: Dictionary) -> bool: return e.kind == KILLED).size()


func is_delivered(hvt_id: String) -> bool:
	return deliveries.any(func(d: Dictionary) -> bool: return d.hvt_id == hvt_id)


func has_intel(intel_id: String) -> bool:
	return intel.any(func(e: Dictionary) -> bool: return e.intel_id == intel_id) \
		or archive.any(func(e: Dictionary) -> bool: return e.intel_id == intel_id)


## The debrief's view: {"civilian_casualties" (different civilians), "civilians_killed",
## "civilians_wounded", "contract_voided" (at VOID_AT), "casualties", "intel", "intel_value",
## "intel_carried", "intel_reported", "hvts_delivered" (the deliveries)}.
func summary() -> Dictionary:
	var value := 0
	var carried := 0
	for e: Dictionary in intel:
		value += int(e.get("value", 0))
		if e.how == "carried":
			carried += 1
	var count := casualty_count()
	var killed := civilians_killed()
	return {"civilian_casualties": count, "civilians_killed": killed, "civilians_wounded": count - killed,
		"contract_voided": count >= VOID_AT, "casualties": casualties.duplicate(true), "intel": intel.duplicate(true),
		"intel_value": value, "intel_carried": carried, "intel_reported": intel.size() - carried,
		"hvts_delivered": deliveries.duplicate(true)}


# --- Host: recording -----------------------------------------------------------------------

## Host only (Harm.note_hit): `victim` was hit by `info` (Harm.info_of). A civilian hit by
## the players' side is a casualty (WOUNDED, once per civilian).
func server_harmed(victim: Node, info: Dictionary) -> void:
	if not multiplayer.is_server() or not Person.is_civilian(victim):
		return
	if String(info.get("faction", "")) != "friendly":
		return
	server_civilian_casualty(victim as Soldier, info, false)


## Host only. Records a casualty event for civilian `victim` caused by `info` (Harm.info_of)
## unless that civilian already has one of this kind. Returns the event ({} if not recorded).
func server_civilian_casualty(victim: Soldier, info: Dictionary, killed: bool) -> Dictionary:
	var uid := String(Person.state(victim).get("uid", victim.name))
	var kind := KILLED if killed else WOUNDED
	if casualties.any(func(e: Dictionary) -> bool: return e.uid == uid and e.kind == kind):
		return {}
	var p := victim.global_position
	var event := {"civilian": victim.display_name(), "uid": uid, "kind": kind, "shooter": String(info.get("name", "")),
		"shooter_faction": String(info.get("faction", "")), "shooter_player": bool(info.get("player", false)),
		"shooter_peer": int(info.get("peer", 0)), "zone": GameState.zone_id, "pos": [p.x, p.z],
		"time": int(Time.get_unix_time_from_system())}
	casualties.append(event)
	print("[people] civilian casualty: %s %s by %s" % [event.civilian, kind, event.shooter])
	civilian_casualty.emit(event)
	_tell(&"on_civilian_casualty", event)
	_after_change()
	return event


## Host only. Banks one piece of intel (see `intel` for its keys) unless its intel_id is
## already banked. Returns whether it was.
func server_bank_intel(entry: Dictionary) -> bool:
	if not multiplayer.is_server() or has_intel(String(entry.get("intel_id", ""))):
		return false
	var e := entry.duplicate(true)
	if not e.has("zone"):
		e["zone"] = GameState.zone_id
	if not e.has("time"):
		e["time"] = int(Time.get_unix_time_from_system())
	intel.append(e)
	archive.append(e)
	print("[people] intel banked: %s (%s, %d)" % [e.intel_id, e.how, int(e.get("value", 0))])
	intel_banked.emit(e)
	_tell(&"on_intel_banked", e)
	_after_change()
	return true


## Host only. An HVT reached an extraction point (PeopleLayer): the objective hook. Once per
## hvt_id.
func server_hvt_delivered(event: Dictionary) -> bool:
	if not multiplayer.is_server() or is_delivered(String(event.get("hvt_id", ""))):
		return false
	var e := event.duplicate(true)
	if not e.has("zone"):
		e["zone"] = GameState.zone_id
	if not e.has("time"):
		e["time"] = int(Time.get_unix_time_from_system())
	deliveries.append(e)
	print("[people] HVT delivered: %s" % e.hvt_id)
	hvt_delivered.emit(e)
	_tell(&"on_hvt_delivered", e)
	_after_change()
	return true


## Host only. A new deployment: clears casualties, intel and deliveries (the archive stays).
func reset_deployment() -> void:
	casualties = []
	intel = []
	deliveries = []
	_after_change()


## Host only. Forgets everything, the archive too (tests; a new campaign).
func reset_all() -> void:
	archive = []
	reset_deployment()


# --- Saving and replication ----------------------------------------------------------------

func _tell(method: StringName, data: Dictionary) -> void:
	for node in get_tree().get_nodes_in_group(LISTENER_GROUP):
		if node.has_method(method):
			node.call(method, data.duplicate(true))


func _snapshot() -> Dictionary:
	return {"casualties": casualties, "intel": intel, "deliveries": deliveries}


func _after_change() -> void:
	if multiplayer.is_server():
		_loading = true
		var section := Campaign.section(SECTION)
		section["deployment"] = _snapshot().duplicate(true)
		section["archive"] = archive.duplicate(true)
		Campaign.mark_changed(SECTION)
		_loading = false
		if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
			_sync.rpc(_snapshot())
	changed.emit()


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server():
		_sync.rpc_id(id, _snapshot())


@rpc("authority", "call_remote", "reliable")
func _sync(data: Dictionary) -> void:
	casualties = data.get("casualties", [])
	intel = data.get("intel", [])
	deliveries = data.get("deliveries", [])
	changed.emit()


## A loaded campaign brings its deployment back.
func _on_campaign_changed(section_name: StringName) -> void:
	if section_name != SECTION or _loading:
		return
	var section := Campaign.section(SECTION)
	var deployment: Dictionary = section.get("deployment", {})
	casualties = deployment.get("casualties", [])
	intel = deployment.get("intel", [])
	deliveries = deployment.get("deliveries", [])
	archive = section.get("archive", [])
	if multiplayer.is_server() and multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_sync.rpc(_snapshot())
	changed.emit()
