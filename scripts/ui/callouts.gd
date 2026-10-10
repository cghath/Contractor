class_name Callouts
extends Node
## AI voice callouts as subtitles, with an audio hook. The level adds one as "Callouts", so
## the same node exists on every peer.
##
## The host decides what is said: SquadAI and the level call say() (contact, reloading,
## man down, frag and smoke out, moving and covering while battle buddies bound). Each
## speaker is rate-limited, only the first spotter calls a given contact, and a line goes only to the players on the speaker's side, so
## hostile callouts are never shown. Each receiving peer shows it as a subtitle
## ("Bravo: Reloading!", see Subtitles) and plays res://audio/callouts/<id>.ogg from the
## speaker if that file exists (play()).

## A line arrived on this peer.
signal line_shown(speaker: String, text: String)

const AUDIO_DIR := "res://audio/callouts/"
## Proposed: a speaker says at most one line this often...
const SPEAKER_GAP_S := 2.0
## ...and doesn't repeat the same callout this soon.
const REPEAT_GAP_S := 8.0
## Proposed: once someone on a side calls a contact on an enemy, nobody else on that side
## calls the same enemy this soon (the first spotter speaks, the rest stay quiet).
const SQUAD_CONTACT_GAP_S := 6.0
## A line held back by the speaker gap is dropped if it can't be said within this long.
const PENDING_S := 3.0
## Callouts that cut in on the speaker gap: man down and thrown grenades (they still
## don't repeat within REPEAT_GAP_S).
const URGENT: Array[StringName] = [&"man_down", &"frag_out", &"smoke_out"]
## How far from a casualty a squadmate notices them go down and calls it.
const MAN_DOWN_RANGE := 40.0
## Subtitles: how long a line stays up, and how many show at once.
const SHOW_S := 4.0
const MAX_LINES := 4
const LOG_SIZE := 64
## Fixed lines by callout id; contact and man down build theirs.
const LINES := {
	&"reloading": "Reloading!",
	&"frag_out": "Frag out!",
	&"smoke_out": "Smoke out!",
	&"flash_out": "Flashbang out!",
	&"moving": "Moving!",
	&"covering": "Covering!",
}
## Callout ids for thrown items.
const THROW_IDS := {&"frag_grenade": &"frag_out", &"smoke_grenade": &"smoke_out", &"flashbang": &"flash_out"}
const DIRECTIONS: Array[String] = ["front", "front right", "right", "back right", "back", "back left", "left", "front left"]

## Host: what was said, newest last: {"speaker", "id", "text", "to": PackedInt32Array, "time"}.
var sent: Array[Dictionary] = []
## Every peer: lines shown here, newest last: {"speaker", "id", "text", "time"}.
var shown: Array[Dictionary] = []
var _last_by_speaker := {}  # speaker node name -> time of their last line
var _last_by_key := {}  # "speaker/key" -> time that callout was last said
var _last_by_side_key := {}  # "faction/key" -> time someone on that side last said it
var _pending := {}  # speaker node name -> the line waiting for the speaker gap


## The level's Callouts node, or null.
static func of(from: Node) -> Callouts:
	var level := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return level.get_node_or_null(^"Callouts") as Callouts if level else null


## How a callout names a soldier: the AI's callsign, or "Player <id>".
static func display_name(s: Soldier) -> String:
	if s == null or not is_instance_valid(s):
		return "Someone"
	return String(s.name) if s.is_ai() else "Player %s" % s.name


## Plays res://audio/callouts/<id>.ogg from `speaker` if that file exists; silent (null)
## otherwise.
static func play(id: StringName, speaker: Node3D) -> AudioStreamPlayer3D:
	var path := AUDIO_DIR + String(id) + ".ogg"
	if speaker == null or not is_instance_valid(speaker) or not speaker.is_inside_tree() or not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		return null
	var audio := AudioStreamPlayer3D.new()
	audio.stream = stream
	speaker.add_child(audio)
	audio.position = Vector3.UP * 1.6
	audio.finished.connect(audio.queue_free)
	audio.play()
	return audio


## Host only. `speaker` says callout `id` (text from LINES unless given). `key` names what
## counts as a repeat (default: the id). A non-empty `side_key` is shared by the speaker's
## whole side: once anyone says it, nobody on that side says it again for `side_gap`
## seconds. Returns true if it was said now. A line held back by the speaker gap waits its
## turn (one per speaker, the newest wins) for up to PENDING_S; a repeat, or a speaker who
## is down, says nothing.
func say(speaker: Soldier, id: StringName, text := "", key := "", side_key := "", side_gap := 0.0) -> bool:
	if not multiplayer.is_server() or speaker == null or not is_instance_valid(speaker) or not speaker.vitals.is_up():
		return false
	var now := Soldier._now()
	var who := String(speaker.name)
	var repeat_key := "%s/%s" % [who, key if key != "" else String(id)]
	if now - float(_last_by_key.get(repeat_key, -1000.0)) < REPEAT_GAP_S:
		return false
	var shared := "%s/%s" % [speaker.faction, side_key] if side_key != "" else ""
	if shared != "" and now - float(_last_by_side_key.get(shared, -1000.0)) < side_gap:
		return false
	var line := text if text != "" else String(LINES.get(id, String(id)))
	if id not in URGENT and now - float(_last_by_speaker.get(who, -1000.0)) < SPEAKER_GAP_S:
		_pending[who] = {"speaker": speaker, "id": id, "line": line, "repeat_key": repeat_key,
			"shared": shared, "side_gap": side_gap, "until": now + PENDING_S}
		return false
	_send(speaker, id, line, repeat_key, shared)
	return true


func _process(_delta: float) -> void:
	if _pending.is_empty() or not multiplayer.is_server():
		return
	var now := Soldier._now()
	for who: String in _pending.keys():
		var p: Dictionary = _pending[who]
		var speaker: Soldier = p.speaker if is_instance_valid(p.speaker) else null
		if now > float(p.until) or speaker == null or not speaker.vitals.is_up() \
				or now - float(_last_by_key.get(p.repeat_key, -1000.0)) < REPEAT_GAP_S \
				or (p.shared != "" and now - float(_last_by_side_key.get(p.shared, -1000.0)) < float(p.side_gap)):
			_pending.erase(who)
		elif now - float(_last_by_speaker.get(who, -1000.0)) >= SPEAKER_GAP_S:
			_pending.erase(who)
			_send(speaker, p.id, p.line, p.repeat_key, p.shared)


func _send(speaker: Soldier, id: StringName, line: String, repeat_key: String, shared := "") -> void:
	var now := Soldier._now()
	var who := String(speaker.name)
	_last_by_key[repeat_key] = now
	if shared != "":
		_last_by_side_key[shared] = now
	_last_by_speaker[who] = now
	var to := recipients(speaker)
	sent.append({"speaker": who, "id": id, "text": line, "to": to, "time": now})
	if sent.size() > LOG_SIZE:
		sent.pop_front()
	for peer in to:
		_show.rpc_id(peer, speaker.get_path(), display_name(speaker), String(id), line)


## Host only. The peers who hear `speaker`: every connected player on the speaker's side.
func recipients(speaker: Soldier) -> PackedInt32Array:
	var out := PackedInt32Array()
	var level := CompoundLevel.current(self)
	if level == null or speaker == null:
		return out
	var peers := multiplayer.get_peers()
	for node in level.players.get_children():
		var player := node as Soldier
		if player == null or player.is_queued_for_deletion() or player.faction != speaker.faction:
			continue
		var peer := player.owner_peer()
		if (peer == multiplayer.get_unique_id() or peer in peers) and peer not in out:
			out.append(peer)
	return out


## Host only. "Contact, front, 80 m": direction and distance from the squad leader's view
## (the speaker's own when there's no leader), as Arma calls them. Only the first spotter
## calls a given enemy; the rest of the side stays quiet for SQUAD_CONTACT_GAP_S.
func contact(speaker: Soldier, enemy: Soldier) -> bool:
	if enemy == null:
		return false
	var level := CompoundLevel.current(self)
	var squad := level.squad_for(speaker.faction) if level else null
	var from: Node3D = squad.leader if squad and is_instance_valid(squad.leader) else speaker
	var distance := from.global_position.distance_to(enemy.global_position)
	return say(speaker, &"contact", "Contact, %s, %d m" % [direction_word(from, enemy.global_position), round_distance(distance)],
		"", "contact/%s" % enemy.name, SQUAD_CONTACT_GAP_S)


## Host only. The casualty's battle buddy, or the nearest squadmate in range, calls
## "Man down! Charlie is down".
func man_down(casualty: Soldier) -> bool:
	var speaker := witness(casualty)
	if speaker == null:
		return false
	return say(speaker, &"man_down", "Man down! %s is down" % display_name(casualty), "man_down/%s" % casualty.name)


## Who sees `casualty` go down: their AI buddy if close, else the nearest AI on their side.
func witness(casualty: Soldier) -> Soldier:
	var buddy := casualty.buddy
	if is_instance_valid(buddy) and buddy.is_ai() and buddy.vitals.is_up() and buddy.faction == casualty.faction \
			and buddy.global_position.distance_to(casualty.global_position) <= MAN_DOWN_RANGE:
		return buddy
	var best: Soldier = null
	var best_d := MAN_DOWN_RANGE
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s == casualty or not s.is_ai() or s.faction != casualty.faction or not s.vitals.is_up() or s.is_queued_for_deletion():
			continue
		var d := s.global_position.distance_to(casualty.global_position)
		if d <= best_d:
			best = s
			best_d = d
	return best


## "front", "front right", ... "left", "front left": where `point` is seen from `from`.
static func direction_word(from: Node3D, point: Vector3) -> String:
	var local := from.global_basis.inverse() * (point - from.global_position)
	var angle := rad_to_deg(atan2(local.x, -local.z))  # 0 ahead, 90 to the right
	return DIRECTIONS[posmod(roundi(angle / 45.0), DIRECTIONS.size())]


## Distances as said over the radio: metres up to 10, then to the nearest 10.
static func round_distance(metres: float) -> int:
	return maxi(roundi(metres), 1) if metres < 10.0 else roundi(metres / 10.0) * 10


## The lines still up on this peer, oldest first.
func current_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var now := Soldier._now()
	for line in shown:
		if now - float(line.time) <= SHOW_S:
			out.append("%s: %s" % [line.speaker, line.text])
	return out.slice(maxi(out.size() - MAX_LINES, 0))


@rpc("any_peer", "call_local", "reliable")
func _show(speaker_path: NodePath, speaker_name: String, id: String, text: String) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	shown.append({"speaker": speaker_name, "id": StringName(id), "text": text, "time": Soldier._now()})
	if shown.size() > LOG_SIZE:
		shown.pop_front()
	line_shown.emit(speaker_name, text)
	play(StringName(id), get_node_or_null(speaker_path) as Node3D)


## The subtitle display the HUD adds: the latest callouts, bottom centre.
class Subtitles extends Label:
	func _ready() -> void:
		horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_font_size_override(&"font_size", 17)
		add_theme_color_override(&"font_color", Color("e8e4c8"))
		add_theme_color_override(&"font_outline_color", Color.BLACK)
		add_theme_constant_override(&"outline_size", 4)
		set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		grow_horizontal = Control.GROW_DIRECTION_BOTH
		grow_vertical = Control.GROW_DIRECTION_BEGIN
		position.y -= 110

	func _process(_delta: float) -> void:
		var callouts := Callouts.of(self)
		text = "\n".join(callouts.current_lines()) if callouts else ""
