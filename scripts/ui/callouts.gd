class_name Callouts
extends Node
## AI voice callouts as subtitles, with an audio hook. The level adds one as "Callouts", so
## the same node exists on every peer.
##
## The host decides what is said: SquadAI and the level call say() (contact, reloading,
## man down, frag and smoke out, moving and covering while battle buddies bound, and the
## medical lines: "Medic!", "Moving to Charlie", "Treating Charlie", "Need a medic on
## Charlie", "Carrying Charlie"), and the friendly squad's comms (SquadComms) answer orders
## and tell the players what they should know. Each
## speaker is rate-limited, only the first spotter calls a given contact, and a line goes only to the players on the speaker's side, so
## hostile callouts are never shown. Each receiving peer shows it as a subtitle
## ("F3 Bravo: Reloading!", see Subtitles) and plays res://audio/callouts/<id>.ogg from the
## speaker if that file exists (play()).
##
## Squad comms (Captain, 2026-10-14: "bots should act like players, communicate with the
## player"; docs/squad_comms.md): priorities decide what gets said when the net is busy.
## Every line has a priority (Prio, by callout id in PRIO_OF), and each side shares one net,
## a token bucket of CHANNEL_BURST lines that refills one every CHANNEL_REFILL_S. Only
## CRITICAL lines may go with the bucket empty (they still take a token). A line that can't
## go yet waits in a queue (one per speaker and priority, the newest wins) and goes once its
## gates open, best priority first, or is dropped once older than its TTL_S (counted in
## `dropped`). Explanations (INFO) wait for a quiet moment: none while the speaker's squad is
## engaged or he is in contact, and at most one per side every INFO_GAP_S. A line can name a
## place as "{where}", worded for each listener from where they stand ("Contact, front right,
## 120 m"), and can go to chosen players only (an answer to the one who asked). The host's
## session log gets every line said to players ("comms ...").

## A line arrived on this peer.
signal line_shown(speaker: String, text: String)

## Captain, 2026-10-14: "bots should act like players, communicate with the player" - priorities
## decide what gets said when the net is busy. CRITICAL: lives and grenades, always at once.
## ANSWER: answers to an order or a question. TACTICAL: contact, movement, supply. INFO: what a
## squadmate is doing and why (carrying, scavenging, explanations).
enum Prio { CRITICAL, ANSWER, TACTICAL, INFO }

const AUDIO_DIR := "res://audio/callouts/"
## Proposed: a speaker says at most one line this often (CRITICAL and ANSWER lines cut in)...
const SPEAKER_GAP_S := 2.0
## ...and doesn't repeat the same callout this soon.
const REPEAT_GAP_S := 8.0
## Proposed: once someone on a side calls a contact on an enemy, nobody else on that side
## calls the same enemy (or one in the same group, Squad.CLUSTER_M) this soon (the first
## spotter speaks, the rest stay quiet).
const SQUAD_CONTACT_GAP_S := 6.0
## Each callout's priority by id; ids not listed are TACTICAL.
const PRIO_OF := {
	&"man_down": Prio.CRITICAL, &"medic": Prio.CRITICAL, &"need_medic": Prio.CRITICAL, &"moving_to": Prio.CRITICAL,
	&"treating": Prio.CRITICAL, &"frag_out": Prio.CRITICAL, &"smoke_out": Prio.CRITICAL, &"flash_out": Prio.CRITICAL,
	&"backblast": Prio.CRITICAL, &"backblast_warn": Prio.CRITICAL, &"hit": Prio.CRITICAL, &"pinned": Prio.CRITICAL,
	&"out_of_ammo": Prio.CRITICAL, &"give_up": Prio.CRITICAL,
	&"ack": Prio.ANSWER, &"refuse": Prio.ANSWER, &"defer": Prio.ANSWER, &"status": Prio.ANSWER, &"in_position": Prio.ANSWER,
	&"contact": Prio.TACTICAL, &"reloading": Prio.TACTICAL, &"moving": Prio.TACTICAL, &"covering": Prio.TACTICAL,
	&"tactic": Prio.TACTICAL, &"low_ammo": Prio.TACTICAL, &"last_mag": Prio.TACTICAL, &"separated": Prio.TACTICAL,
	&"stuck": Prio.TACTICAL, &"fall_back": Prio.TACTICAL,
	&"carrying": Prio.INFO, &"scavenging": Prio.INFO, &"explain": Prio.INFO, &"out_of_meds": Prio.INFO,
	&"putting_down": Prio.INFO,
}
## The CRITICAL callouts (PRIO_OF), which cut in on the speaker gap and the budget (they
## still don't repeat within REPEAT_GAP_S).
const URGENT: Array[StringName] = [&"man_down", &"medic", &"need_medic", &"moving_to", &"treating", &"frag_out", &"smoke_out",
	&"flash_out", &"backblast", &"backblast_warn", &"hit", &"pinned", &"out_of_ammo", &"give_up"]
## Proposed: a waiting line older than this (seconds, by Prio) is stale and dropped unsaid.
const TTL_S: Array[float] = [1.5, 4.0, 2.5, 6.0]
## Proposed: a side's net carries up to CHANNEL_BURST lines at once, then one every
## CHANNEL_REFILL_S (about 40 a minute at most).
const CHANNEL_BURST := 3.0
const CHANNEL_REFILL_S := 1.5
## Proposed: INFO lines on a side at most one this often.
const INFO_GAP_S := 4.0
## Proposed: lines waiting per side; past it the lowest priority, oldest first, is dropped.
const QUEUE_MAX := 8
## How far from a casualty a squadmate notices them go down and calls it.
const MAN_DOWN_RANGE := 40.0
## Subtitles: how long a line stays up (by Prio: answers stay longer), and how many show at once.
const SHOW_S := 4.0
const SHOW_S_BY: Array[float] = [4.0, 6.0, 4.0, 4.0]
const MAX_LINES := 5
## Subtitle colour by Prio (ANSWER in the command menu's highlight; TACTICAL as callouts were).
const COLORS: Array[String] = ["ff8a6a", "ffd35a", "e8e4c8", "b0ad9a"]
const LOG_SIZE := 128
## Stands in a line's text for a place, worded for each listener (where_words).
const WHERE := "{where}"
## Fixed lines by callout id; contact and man down build theirs.
const LINES := {
	&"reloading": "Reloading!",
	&"frag_out": "Frag out!",
	&"smoke_out": "Smoke out!",
	&"flash_out": "Flashbang out!",
	&"moving": "Moving!",
	&"covering": "Covering!",
	&"medic": "Medic!",
}
## Callout ids for thrown items.
const THROW_IDS := {&"frag_grenade": &"frag_out", &"smoke_grenade": &"smoke_out", &"flashbang": &"flash_out"}
const DIRECTIONS: Array[String] = ["front", "front right", "right", "back right", "back", "back left", "left", "front left"]
const COUNT_WORDS: Array[String] = ["none", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]

## Host: what was said, newest last: {"speaker", "id", "text" (worded from the squad leader's
## view), "to": PackedInt32Array, "time", "prio", "texts" (peer -> the text that peer got)}.
var sent: Array[Dictionary] = []
## Every peer: lines shown here, newest last: {"speaker", "id", "text", "time", "prio", "path"}.
var shown: Array[Dictionary] = []
## Every peer: counts up with each line shown (the subtitles redraw on a change).
var shown_rev := 0
## Host: lines dropped unsaid (stale, or crowded out of the queue), by callout id.
var dropped := {}
var _last_by_speaker := {}  # speaker node name -> time of their last line
var _last_by_key := {}  # "speaker/key" -> time that callout was last said
var _last_by_side_key := {}  # "faction/key" -> time someone on that side last said it
## Host: lines waiting their turn (see say()), each {"speaker", "who", "faction", "id", "text",
## "repeat_key", "shared", "side_gap", "prio", "to", "at", "me", "valid", "not_before", "queued"}.
var _pending: Array[Dictionary] = []
var _channel := {}  # faction -> {"tokens", "at"}: the side's net (_tokens)
var _info_at := {}  # faction -> when the side last said an INFO line
var _relay_seq := 0  # relay(): every relayed line its own repeat key


## The level's Callouts node, or null.
static func of(from: Node) -> Callouts:
	var level := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return level.get_node_or_null(^"Callouts") as Callouts if level else null


## How a callout names a soldier: the AI's callsign, or "Player <id>".
static func display_name(s: Soldier) -> String:
	if s == null or not is_instance_valid(s):
		return "Someone"
	return s.display_name()  # a dead player's body is still "Player 2"


## A callout's priority (PRIO_OF; TACTICAL for any other).
static func prio_of(id: StringName) -> int:
	return int(PRIO_OF.get(id, Prio.TACTICAL))


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
	audio.bus = &"Voice"  # Sfx makes the bus
	speaker.add_child(audio)
	audio.position = Vector3.UP * 1.6
	audio.finished.connect(audio.queue_free)
	audio.play()
	return audio


## Host only. `speaker` says callout `id` (text from LINES unless given). `key` names what
## counts as a repeat (default: the id). A non-empty `side_key` is shared by the speaker's
## whole side: once anyone says it, nobody on that side says it again for `side_gap`
## seconds. Returns true if it was said now. A repeat, or a speaker who is down, says nothing.
## A line that can't go yet (the speaker's gap, the side's budget, an INFO line while the
## squad fights) waits in the queue, one per speaker and priority (the newest wins), until
## its gates open or it goes stale (TTL_S). A line nobody hears (a hostile's) is only logged.
## `opts`: "prio" (overrides PRIO_OF), "to" (PackedInt32Array: only these players hear it;
## an ANSWER to chosen players doesn't use the side's budget), "at" (Vector3: where "{where}"
## in the text is, worded for each listener), "me" (true: "{where}" is the speaker himself),
## "valid" (Callable -> bool: still true? checked again before a waiting line goes), and
## "not_before" (Soldier._now() time: not said before then), "name" (the name shown, when
## it isn't the speaker's: relay) and "voice" (whose gaps it keeps, default the speaker's).
func say(speaker: Soldier, id: StringName, text := "", key := "", side_key := "", side_gap := 0.0, opts := {}) -> bool:
	if not multiplayer.is_server() or speaker == null or not is_instance_valid(speaker) or not speaker.vitals.is_up():
		return false
	var now := Soldier._now()
	var who := String(opts.get("voice", speaker.name))
	var repeat_key := "%s/%s" % [who, key if key != "" else String(id)]
	if now - float(_last_by_key.get(repeat_key, -1000.0)) < REPEAT_GAP_S:
		return false
	var shared := "%s/%s" % [speaker.faction, side_key] if side_key != "" else ""
	if shared != "" and now - float(_last_by_side_key.get(shared, -1000.0)) < side_gap:
		return false
	var valid: Callable = opts.get("valid", Callable())
	if valid.is_valid() and not valid.call():
		return false
	var line := {"speaker": speaker, "who": who, "name": String(opts.get("name", "")), "faction": speaker.faction, "id": id,
		"text": text if text != "" else String(LINES.get(id, String(id))), "repeat_key": repeat_key, "shared": shared,
		"side_gap": side_gap, "prio": clampi(int(opts.get("prio", prio_of(id))), Prio.CRITICAL, Prio.INFO),
		"to": PackedInt32Array(opts.get("to", PackedInt32Array())), "at": opts.get("at"), "me": bool(opts.get("me", false)),
		"valid": valid, "not_before": float(opts.get("not_before", 0.0)), "queued": now}
	var to := _audience(line)
	if to.is_empty():
		_send(line, to)  # heard by nobody (a hostile's line, or the asker left): logged, no budget used
		return true
	if _may_send(line, now):
		_send(line, to)
		return true
	_enqueue(line)
	return false


## Host only. A line heard on `by`'s side through him but not his own (RadioChatter: the
## enemy's net on a captured radio, shown as `speaker_name`). It takes its turn in the side's
## queue as TACTICAL with its own gaps, so the enemy's chatter can't crowd out "Man down"
## (Captain, 2026-10-14: one throttle for everything the squad hears). Returns true if said now.
func relay(by: Soldier, speaker_name: String, id: StringName, text: String) -> bool:
	_relay_seq += 1
	return say(by, id, text, "relay/%d" % _relay_seq, "", 0.0, {"prio": Prio.TACTICAL, "name": speaker_name, "voice": "relay/%s" % speaker_name})


## Host only. When `speaker` last said callout `key` (say's key, default the id), or -1000.
func said_at(speaker: Soldier, key: String) -> float:
	if speaker == null or not is_instance_valid(speaker):
		return -1000.0
	return float(_last_by_key.get("%s/%s" % [speaker.name, key], -1000.0))


## Host: the lines waiting their turn now (copies of the queue's entries).
func waiting() -> Array[Dictionary]:
	return _pending.duplicate()


## Tests: forgets every gate, the queue, the budget and both logs.
func reset() -> void:
	_last_by_speaker.clear()
	_last_by_key.clear()
	_last_by_side_key.clear()
	_pending.clear()
	_channel.clear()
	_info_at.clear()
	dropped.clear()
	sent.clear()
	shown.clear()


## Whether `s` is fighting now: in contact, or his squad engaged (SquadAI.in_contact,
## Squad.is_engaged). INFO lines wait while he is.
static func busy(s: Soldier) -> bool:
	var ai := SquadAI.of(s)
	return ai != null and ai._ready_done and (ai.in_contact() or (ai.squad != null and ai.squad.is_engaged()))


func _process(_delta: float) -> void:
	if _pending.is_empty() or not multiplayer.is_server():
		return
	var now := Soldier._now()
	var best := -1
	for i in range(_pending.size() - 1, -1, -1):
		var p: Dictionary = _pending[i]
		var speaker: Soldier = p.speaker if is_instance_valid(p.speaker) else null
		var stale := now - maxf(float(p.queued), float(p.not_before)) > TTL_S[int(p.prio)]
		var valid: Callable = p.valid
		if stale or speaker == null or speaker.is_queued_for_deletion() or not speaker.vitals.is_up() \
				or now - float(_last_by_key.get(p.repeat_key, -1000.0)) < REPEAT_GAP_S \
				or (p.shared != "" and now - float(_last_by_side_key.get(p.shared, -1000.0)) < float(p.side_gap)) \
				or (valid.is_valid() and not valid.call()):
			_pending.remove_at(i)
			if stale:
				_drop(p)
	for i in _pending.size():
		var p: Dictionary = _pending[i]
		if (best < 0 or int(p.prio) < int(_pending[best].prio)
				or (int(p.prio) == int(_pending[best].prio) and float(p.queued) < float(_pending[best].queued))) and _may_send(p, now):
			best = i
	if best >= 0:
		var line: Dictionary = _pending[best]
		_pending.remove_at(best)
		_send(line, _audience(line))


## Whether `line` may go now: its time has come, the speaker's gap has passed (CRITICAL and
## ANSWER lines cut in), an INFO line finds the side quiet, and the side's net has a token
## (CRITICAL lines and answers to chosen players don't wait for one).
func _may_send(line: Dictionary, now: float) -> bool:
	if now < float(line.not_before):
		return false
	var prio := int(line.prio)
	if prio > Prio.ANSWER and now - float(_last_by_speaker.get(line.who, -1000.0)) < SPEAKER_GAP_S:
		return false
	if prio == Prio.INFO and (now - float(_info_at.get(line.faction, -1000.0)) < INFO_GAP_S or busy(line.speaker)):
		return false
	return prio == Prio.CRITICAL or _private(line) or _tokens(line.faction, now) >= 1.0


## An answer to chosen players: it doesn't use the side's net budget.
static func _private(line: Dictionary) -> bool:
	var to: PackedInt32Array = line.to
	return int(line.prio) == Prio.ANSWER and not to.is_empty()


## The tokens on `faction`'s net now (refilled since last asked).
func _tokens(faction: StringName, now: float) -> float:
	var c: Dictionary = _channel.get(faction, {})
	if c.is_empty():
		c = {"tokens": CHANNEL_BURST, "at": now}
		_channel[faction] = c
	c.tokens = minf(CHANNEL_BURST, float(c.tokens) + maxf(now - float(c.at), 0.0) / CHANNEL_REFILL_S)
	c.at = now
	return float(c.tokens)


## Queues `line`: it replaces the speaker's waiting line of the same priority, and past
## QUEUE_MAX on its side the lowest priority, oldest first, is dropped.
func _enqueue(line: Dictionary) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		if _pending[i].who == line.who and int(_pending[i].prio) == int(line.prio):
			_pending.remove_at(i)
	_pending.append(line)
	while true:
		var worst := -1
		var count := 0
		for i in _pending.size():
			var p: Dictionary = _pending[i]
			if p.faction != line.faction:
				continue
			count += 1
			if worst < 0 or int(p.prio) > int(_pending[worst].prio) \
					or (int(p.prio) == int(_pending[worst].prio) and float(p.queued) < float(_pending[worst].queued)):
				worst = i
		if count <= QUEUE_MAX:
			return
		_drop(_pending[worst])
		_pending.remove_at(worst)


func _drop(line: Dictionary) -> void:
	dropped[line.id] = int(dropped.get(line.id, 0)) + 1


## Host: the players who hear `line`: the speaker's side (recipients), or only those of its
## "to" among them.
func _audience(line: Dictionary) -> PackedInt32Array:
	var all := recipients(line.speaker)
	var only: PackedInt32Array = line.to
	if only.is_empty():
		return all
	var out := PackedInt32Array()
	for peer in only:
		if peer in all:
			out.append(peer)
	return out


func _send(line: Dictionary, to: PackedInt32Array) -> void:
	var now := Soldier._now()
	var speaker: Soldier = line.speaker
	var prio := int(line.prio)
	_last_by_key[line.repeat_key] = now
	if line.shared != "":
		_last_by_side_key[line.shared] = now
	_last_by_speaker[line.who] = now
	if not to.is_empty():
		if prio == Prio.INFO:
			_info_at[line.faction] = now
		if not _private(line):
			var left := _tokens(line.faction, now)
			_channel[line.faction].tokens = maxf(left - 1.0, 0.0)
	var raw := String(line.text)
	var at: Variant = speaker.global_position if line.me else line.at
	var text := resolve_where(raw, _leader_frame(speaker), at)
	var texts := {}
	for peer in to:
		texts[peer] = resolve_where(raw, _listener(peer, speaker), at) if raw.contains(WHERE) else text
	sent.append({"speaker": line.who, "id": line.id, "text": text, "to": to, "time": now, "prio": prio, "texts": texts})
	if sent.size() > LOG_SIZE:
		sent.pop_front()
	if not to.is_empty():
		var only := PackedStringArray()
		var asked: PackedInt32Array = line.to
		for peer in asked:
			only.append("player %d" % peer)
		SessionLog.note("comms %s%s: %s" % [speaker.log_name(), " (to %s)" % ", ".join(only) if not only.is_empty() else "", text])
	for peer in to:
		_show_line.rpc_id(peer, speaker.get_path(), line.name if line.name != "" else display_name(speaker), String(line.id), String(texts[peer]), prio)


## Whose view a line is worded from in the log (sent.text): the squad leader's, else the
## speaker's own.
func _leader_frame(speaker: Soldier) -> Node3D:
	var level := CompoundLevel.current(self)
	var squad := level.squad_for(speaker.faction) if level else null
	return squad.leader if squad and is_instance_valid(squad.leader) else speaker


## The player soldier of `peer` (a line is worded from where he stands), else the leader's view.
func _listener(peer: int, speaker: Soldier) -> Node3D:
	var level := CompoundLevel.current(self)
	if level:
		for node in level.players.get_children():
			var player := node as Soldier
			if player and not player.is_queued_for_deletion() and player.owner_peer() == peer:
				return player
	return _leader_frame(speaker)


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


## Host only. "Contact, front, 80 m" (several together: "Contacts, three, front right,
## 120 m"): direction and distance from each listener's own view (the log's from the squad
## leader's), as Arma calls them. The group is the fresh known enemies (Squad.enemy_picture)
## within Squad.CLUSTER_M of the one spotted, and only the first spotter calls a group: the
## rest of the side stays quiet about any of them for SQUAD_CONTACT_GAP_S.
func contact(speaker: Soldier, enemy: Soldier) -> bool:
	if enemy == null:
		return false
	var group: Array[String] = [String(enemy.name)]
	var level := CompoundLevel.current(self)
	var squad := level.squad_for(speaker.faction) if level else null
	if squad and not recipients(speaker).is_empty():  # (a hostile's call goes to nobody: no need)
		for e in squad.enemy_picture():
			var other: Soldier = e.who
			if other != enemy and float(e.age) < Squad.FRESH_S and (e.pos as Vector3).distance_to(enemy.global_position) <= Squad.CLUSTER_M:
				group.append(String(other.name))
	group.sort()
	var text := "Contact, %s" % WHERE if group.size() == 1 else "Contacts, %s, %s" % [count_word(group.size()), WHERE]
	return say(speaker, &"contact", text, "", "contact/%s" % group[0], SQUAD_CONTACT_GAP_S, {"at": enemy.global_position})


## Host only. The casualty's battle buddy, or the nearest squadmate in range, calls
## "Man down! Charlie is down".
func man_down(casualty: Soldier) -> bool:
	var speaker := witness(casualty)
	if speaker == null:
		return false
	return say(speaker, &"man_down", "Man down! %s is down" % display_name(casualty), "man_down/%s" % casualty.name)


## Host only. A wounded soldier who can't fix something themselves calls "Medic!".
func medic_call(speaker: Soldier) -> bool:
	return say(speaker, &"medic")


## Host only. Whoever answers a casualty says so: "Moving to Charlie" on the way, "Treating
## Charlie" once there.
func answer_casualty(speaker: Soldier, casualty: Soldier, treating: bool) -> bool:
	if casualty == null:
		return false
	var id := &"treating" if treating else &"moving_to"
	var line := "%s %s" % ["Treating" if treating else "Moving to", display_name(casualty)]
	return say(speaker, id, line, "%s/%s" % [id, casualty.name])


## Host only. A buddy who has done what they can asks for the medic: "Need a medic on Charlie!".
func need_medic(speaker: Soldier, casualty: Soldier) -> bool:
	if casualty == null:
		return false
	return say(speaker, &"need_medic", "Need a medic on %s!" % display_name(casualty), "need_medic/%s" % casualty.name)


## Host only. A squadmate picks up a casualty or a fallen friendly to carry them with the
## squad: "Carrying Charlie" ("Carrying Charlie's body").
func carrying(speaker: Soldier, other: Soldier, dead: bool) -> bool:
	if other == null:
		return false
	var line := "Carrying %s%s" % [display_name(other), "'s body" if dead else ""]
	return say(speaker, &"carrying", line, "carrying/%s" % other.name)


## Host only. A squadmate goes through a body for what he needs: "Checking Charlie's body"
## (an enemy's: "Checking the body").
func scavenging(speaker: Soldier, dead: Soldier) -> bool:
	if dead == null:
		return false
	var line := "Checking %s's body" % display_name(dead) if dead.faction == speaker.faction else "Checking the body"
	return say(speaker, &"scavenging", line, "scavenging/%s" % dead.name)


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


## "front right, 120 m": where `point` is from `from`, as a callout says it.
static func where_words(from: Node3D, point: Vector3) -> String:
	return "%s, %d m" % [direction_word(from, point), round_distance(from.global_position.distance_to(point))]


## `text` with "{where}" worded from `listener`'s view of `at` (where_words). Without a
## listener or a place, the place is left out.
static func resolve_where(text: String, listener: Node3D, at: Variant) -> String:
	if not text.contains(WHERE):
		return text
	if listener == null or not is_instance_valid(listener) or not (at is Vector3):
		return text.replace(", " + WHERE, "").replace(WHERE, "")
	return text.replace(WHERE, where_words(listener, at))


## "one" to "nine", then "many": how a callout counts.
static func count_word(n: int) -> String:
	return COUNT_WORDS[n] if n >= 0 and n < COUNT_WORDS.size() else "many"


## The lines still up on this peer, oldest first: "Name: text".
func current_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for line in current_entries():
		out.append("%s: %s" % [line.speaker, line.text])
	return out


## The lines still up on this peer (each stays SHOW_S_BY its priority), oldest first, at most
## MAX_LINES: entries of `shown`.
func current_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var now := Soldier._now()
	for line in shown:
		if now - float(line.time) <= SHOW_S_BY[int(line.get("prio", Prio.TACTICAL))]:
			out.append(line)
	return out.slice(maxi(out.size() - MAX_LINES, 0))


## A line from the host (RadioChatter and PeopleLayer send these too), shown as TACTICAL.
@rpc("any_peer", "call_local", "reliable")
func _show(speaker_path: NodePath, speaker_name: String, id: String, text: String) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_shown(speaker_path, speaker_name, StringName(id), text, Prio.TACTICAL)


## A squad line from the host, worded for this peer, with its priority (the subtitle's colour
## and how long it stays up).
@rpc("any_peer", "call_local", "reliable")
func _show_line(speaker_path: NodePath, speaker_name: String, id: String, text: String, prio: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_shown(speaker_path, speaker_name, StringName(id), text, clampi(prio, Prio.CRITICAL, Prio.INFO))


func _shown(speaker_path: NodePath, speaker_name: String, id: StringName, text: String, prio: int) -> void:
	shown.append({"speaker": speaker_name, "id": id, "text": text, "time": Soldier._now(), "prio": prio, "path": speaker_path})
	if shown.size() > LOG_SIZE:
		shown.pop_front()
	shown_rev += 1
	line_shown.emit(speaker_name, text)
	play(id, get_node_or_null(speaker_path) as Node3D)


## The subtitle display the HUD adds: the latest callouts, bottom centre, coloured by priority
## (Callouts.COLORS) and led by the speaker's F-key ("F3 Torres: Copy, holding"), so the player
## knows whom to select.
class Subtitles extends RichTextLabel:
	const WIDTH := 1100.0
	## Redraws on a new line, and this often for lines timing out.
	const REFRESH_S := 0.25

	var _rev := -1
	var _cd := 0.0

	func _ready() -> void:
		bbcode_enabled = true
		fit_content = true
		scroll_active = false
		autowrap_mode = TextServer.AUTOWRAP_OFF
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_font_size_override(&"normal_font_size", 17)
		add_theme_color_override(&"default_color", Color(Callouts.COLORS[Callouts.Prio.TACTICAL]))
		add_theme_color_override(&"font_outline_color", Color.BLACK)
		add_theme_constant_override(&"outline_size", 4)
		custom_minimum_size = Vector2(WIDTH, 0.0)
		set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		grow_horizontal = Control.GROW_DIRECTION_BOTH
		grow_vertical = Control.GROW_DIRECTION_BEGIN
		position.y -= 110

	func _process(delta: float) -> void:
		var callouts := Callouts.of(self)
		_cd -= delta
		if callouts and callouts.shown_rev == _rev and _cd > 0.0:
			return
		_cd = REFRESH_S
		_rev = callouts.shown_rev if callouts else -1
		var lines := PackedStringArray()
		if callouts:
			var keys := _f_keys()
			for line in callouts.current_entries():
				var f: String = keys.get(String(line.get("path", NodePath())), "")
				lines.append("[color=#%s]%s%s: %s[/color]" % [Callouts.COLORS[int(line.get("prio", Callouts.Prio.TACTICAL))],
					f + " " if f != "" else "", _escape(String(line.speaker)), _escape(String(line.text))])
		var shown_text := "[center]%s[/center]" % "\n".join(lines) if not lines.is_empty() else ""
		if shown_text != text:
			text = shown_text

	## Speaker path -> "F3", from the HUD's command menu roster (the squad list's numbering).
	func _f_keys() -> Dictionary:
		var out := {}
		var menu := get_parent().get(&"command_menu") as CommandMenu if get_parent() else null
		if menu == null or menu.player == null or not is_instance_valid(menu.player):
			return out
		var units := menu.roster()
		for i in units.size():
			out[String(units[i].get_path())] = "F%d" % (i + 1)
		return out

	static func _escape(s: String) -> String:
		return s.replace("[", "[lb]")
