class_name EnemyTags
extends Node
## Tagging enemies (Captain, 2026-10-16: "tagging with radio equipment + animations, Ghost Recon
## Wildlands style"): a player looks at an enemy he can see, within TAG_RANGE_M, and presses Tag
## (Controls "tag_enemy"); keying his radio (a hand to the radio on his carrier: CharacterModel
## RADIO) he passes it on, and for TAG_S, or until that enemy is down, every player of his side sees
## a red mark over him, through walls (a Label3D on each peer), and on the map (MapView), and the
## AI squadmates of his squad know where he is (Soldier.threat_pos). Binoculars or an optic make
## the look easier; the radio is a must (RADIO_ITEMS). One node, "EnemyTags", in every level
## (install), host authoritative; the tags go to every peer (late joiners too). Proposed numbers.

const NODE_NAME := "EnemyTags"
const TAG_RANGE_M := 400.0
const TAG_S := 90.0
const COOLDOWN_S := 0.6
const MAX_TAGS := 24
const RADIO_ITEMS: Array[StringName] = [&"radio", &"pouch_radio", &"enemy_radio"]
const MARK := "◆"
const MARK_COLOUR := Color(0.95, 0.2, 0.15)
const MARK_ABOVE_M := 2.25

## Every peer: soldier name -> Soldier._now()-relative seconds left when last sent; the host
## keeps "until" times in _until.
var tags := {}
var _until := {}
var _last_tag := {}  # host: tagger name -> when he last tagged
var _marks := {}     # every peer: soldier name -> its Label3D
var _check := 0.0


## Every peer, from the level's _ready: this node, once.
static func install(level: Node) -> void:
	if level.get_node_or_null(NODE_NAME) != null:
		return
	var n := EnemyTags.new()
	n.name = NODE_NAME
	level.add_child(n)


static func of(from: Node) -> EnemyTags:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NODE_NAME) as EnemyTags if lvl else null


func _ready() -> void:
	Net.peer_joined.connect(_on_peer_joined)


## Whether `s` carries a radio to pass a tag on.
static func has_radio(s: Soldier) -> bool:
	if s == null or s.inventory == null:
		return false
	for id in RADIO_ITEMS:
		if s.inventory.count_of(id) > 0:
			return true
	return false


## Host: `by` tags `target`. Returns "" or why not.
func server_tag(by: Soldier, target: Soldier) -> String:
	if not multiplayer.is_server() or by == null:
		return ""
	if target == null or not target.vitals.is_up() or target.faction == by.faction or Person.is_noncombatant(target):
		return "No enemy there"
	if not has_radio(by):
		return "You need a radio to pass it on"
	if Soldier._now() - float(_last_tag.get(String(by.name), -INF)) < COOLDOWN_S:
		return ""
	if by.global_position.distance_to(target.global_position) > TAG_RANGE_M:
		return "Too far to make out"
	if not Squad.sees(by, target):
		return "You can't see him from here"
	_last_tag[String(by.name)] = Soldier._now()
	var key := String(target.name)
	var fresh := not _until.has(key)
	_until[key] = Soldier._now() + TAG_S
	if _until.size() > MAX_TAGS:
		var oldest := ""
		for k: String in _until:
			if oldest == "" or float(_until[k]) < float(_until[oldest]):
				oldest = k
		_until.erase(oldest)
	var model := by.model
	if model:
		model.server_play(CharacterModel.RADIO, CharacterModel.RADIO_S)  # keying the radio
	_tell_squad(by, target)
	_send()
	var intel := SideIntel.of(self)
	if intel:
		intel.server_report_tag(by, target)  # a tag is a report to the side's picture (combined_arms 4.4)
	SessionLog.note("tag: %s tagged %s" % [by.name, key])
	return "Tagged" if fresh else "Tag refreshed"


## Host: `target` tagged on someone else's word (RebelCalls' lookouts: no radio, no line of
## sight of ours), for TAG_S.
func server_tag_reported(target: Soldier) -> void:
	if not multiplayer.is_server() or target == null or not target.vitals.is_up():
		return
	_until[String(target.name)] = Soldier._now() + TAG_S
	_send()
	var intel := SideIntel.of(self)
	if intel:
		intel.server_report_tag(null, target)  # a lookout's or the UAV's report


## The AI squadmates of `by`'s squad learn where `target` is.
func _tell_squad(by: Soldier, target: Soldier) -> void:
	var lvl := CompoundLevel.current(self)
	var squad := lvl.squad_for(by.faction) if lvl else null
	if squad == null:
		return
	for s: Soldier in squad.members():
		s.threat_pos = target.global_position
		s.threat_time = Soldier._now()


## Host: whether `name` is tagged now.
func is_tagged(soldier_name: String) -> bool:
	return float(_until.get(soldier_name, -INF)) > Soldier._now()


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	if multiplayer.is_server() and not _until.is_empty():
		var changed := false
		for k: String in _until.keys():
			var s := _soldier(k)
			if float(_until[k]) <= Soldier._now() or s == null or not s.vitals.is_up():
				_until.erase(k)
				changed = true
		if changed:
			_send()
	_update_marks()


func _soldier(soldier_name: String) -> Soldier:
	var lvl := CompoundLevel.current(self)
	if lvl == null:
		return null
	return lvl.ai.get_node_or_null(NodePath(soldier_name)) as Soldier


## Host: the tags to every peer (and here).
func _send() -> void:
	var out := {}
	for k: String in _until:
		out[k] = maxf(float(_until[k]) - Soldier._now(), 0.0)
	tags = out
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_client_tags.rpc(out)
	_update_marks()


@rpc("authority", "call_remote", "reliable")
func _client_tags(list: Dictionary) -> void:
	tags = list
	_update_marks()


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server() and not tags.is_empty():
		_client_tags.rpc_id(id, tags)


## Every peer: a mark over each tagged enemy, none over the rest.
func _update_marks() -> void:
	for k: String in _marks.keys():
		if not tags.has(k) or not is_instance_valid(_marks[k]):
			if is_instance_valid(_marks[k]):
				(_marks[k] as Node).queue_free()
			_marks.erase(k)
	for k: String in tags:
		if _marks.has(k):
			continue
		var s := _soldier(k)
		if s == null:
			continue
		var mark := Label3D.new()
		mark.name = "TagMark"
		mark.text = MARK
		mark.modulate = MARK_COLOUR
		mark.outline_modulate = Color(0, 0, 0, 0.8)
		mark.font_size = 40
		mark.pixel_size = 0.002
		mark.fixed_size = true
		mark.no_depth_test = true  # seen through walls: it's a radio report, not line of sight
		mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mark.position = Vector3(0, MARK_ABOVE_M, 0)
		s.add_child(mark)
		_marks[k] = mark


## Every peer: where the tagged enemies are, for the map: [Vector2].
func map_points() -> Array:
	var out: Array = []
	for k: String in tags:
		var s := _soldier(k)
		if s:
			out.append(Vector2(s.global_position.x, s.global_position.z))
	return out
