class_name ZoneCleanup
extends Node
## Bodies and dropped loot don't lie about forever in a contract zone (Captain, 2026-10-16: "we
## also need body, loot and blood/decal cleanup over time", "~6-7 minutes is a good enough
## lifetime for most things"). Every TICK_S the host looks over:
## - dead bodies (Soldier.DEAD_GROUP) older than LIFE_S (each its own time in that span, from
##   its uid): the body goes with its gear on it (no pile of kit left behind to clean up too);
## - dropped items (GameState.dropped: what bodies and players let fall, not the map's own loot)
##   lying LIFE_S since this node first saw them: gone, and forgotten by the save. Intel never.
## Nothing goes with a player within NEAR_M (he may be looting it) or while being carried.
## Blood, pools and brain go on their own clocks (WoundMarks), cut-off limbs too (BodyDeform).
## Host only; ZoneLevel adds one (the FOB keeps what's dropped there).

const TICK_S := 15.0
const LIFE_S := Vector2(360.0, 420.0)
const NEAR_M := 20.0

var level: CompoundLevel
var _seen := {}   # dropped item uid -> when this node first saw it (seconds)
var _tick := 0.0


func _init() -> void:
	name = "ZoneCleanup"


func _ready() -> void:
	level = get_parent() as CompoundLevel


func _process(delta: float) -> void:
	if not multiplayer.is_server() or level == null:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK_S
		server_sweep()


## Host: one look round (tests call it with `now` moved on).
func server_sweep(now := -1.0) -> void:
	if now < 0.0:
		now = Soldier._now()
	var players := MapNodes.players(self)
	for n in get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
		var b := n as Soldier
		if b == null or b.is_queued_for_deletion() or is_instance_valid(b.carried_by):
			continue
		if now - b.died_at < life_of(b.body_uid) or _near(b.global_position, players):
			continue
		b.remove_from_group(Soldier.DEAD_GROUP)
		b.queue_free()
	if level.items == null:
		return
	for child in level.items.get_children():
		var item := child as WorldItem
		if item == null or item.is_queued_for_deletion() or not GameState.dropped.has(item.uid):
			continue
		var data := ItemDB.get_item(item.item_id)
		if data and data.type == "intel":
			continue
		if not _seen.has(item.uid):
			_seen[item.uid] = now
			continue
		if now - float(_seen[item.uid]) < life_of(item.uid) or _near(item.global_position, players):
			continue
		_seen.erase(item.uid)
		GameState.item_taken(item.uid)
		item.queue_free()


## How long a thing with `uid` lies about: its own point in LIFE_S (the same every time).
static func life_of(uid: String) -> float:
	return lerpf(LIFE_S.x, LIFE_S.y, float(absi(hash(uid)) % 1000) / 999.0)


static func _near(pos: Vector3, players: Array) -> bool:
	for p: Node3D in players:
		if is_instance_valid(p) and p.global_position.distance_to(pos) < NEAR_M:
			return true
	return false
