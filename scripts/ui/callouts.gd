class_name Callouts
extends Node
## AI voice callouts as subtitles, with an audio hook. The level adds one as "Callouts", so
## the same node exists on every peer.
##
## The host decides what is said: SquadAI and the level call say() (contact, reloading,
## man down, frag and smoke out, moving and covering while battle buddies bound, and the
## medical lines: "Medic!", "Moving to Charlie", "Treating Charlie", "Need a medic on
## Charlie", "Carrying Charlie"). Each
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
## Callouts that cut in on the speaker gap: man down, thrown grenades and the medical calls
## (they still don't repeat within REPEAT_GAP_S).
const URGENT: Array[StringName] = [&"man_down", &"frag_out", &"smoke_out", &"medic", &"moving_to", &"treating", &"need_medic", &"grenade", &"check_fire"]
## How far from a casualty a squadmate notices them go down and calls it.
const MAN_DOWN_RANGE := 40.0
## Subtitles: how long a line stays up, and how many show at once.
const SHOW_S := 4.0
const MAX_LINES := 4
const LOG_SIZE := 64
## Fixed lines by callout id; contact and man down build theirs.
const LINES := {
	&"reloading": "Reloading!",
	&"reloading_last_rifle": "Last mag for the rifle!",
	&"reloading_last_mg": "Last mag for the gun!",
	&"reloading_last_pistol": "Last mag for the pistol!",
	&"frag_out": "Frag out!",
	&"smoke_out": "Smoke out!",
	&"flash_out": "Flashbang out!",
	&"moving": "Moving!",
	&"covering": "Covering!",
	&"no_shot": "No shot!",
	&"medic": "Medic!",
	&"set": "Set!",
	&"grenade": "Grenade!",
	&"out_of_ammo": "I'm out! Need ammo!",
	&"check_fire": "Check fire! Check fire!",
	&"enemy_down": "Enemy down!",
	&"suppressed": "I'm pinned!",
}
## Context-aware barks (2026-10-22, claude/voice-economy; the Captain's immersion backlog,
## "nothing insane"): one voice at a time per group (a squad; a side's men in no squad share
## one), by priority. A line while someone else in its group is talking (GROUP_GAP_S) waits its
## turn like a speaker-gap line (PENDING_S) unless it outranks what's being said; 3 cuts in on
## anyone. A line already waiting goes before a newer one of no more weight (no starving). Ids
## not listed are 0; a templated id takes its prefix's ("contact_two_close" is a contact).
## Proposed.
const GROUP_GAP_S := 0.6
const PRIORITY := {
	&"man_down": 3, &"grenade": 3, &"check_fire": 3, &"frag_out": 3, &"smoke_out": 3, &"flash_out": 3,
	&"medic": 3, &"moving_to": 3, &"treating": 3, &"need_medic": 3,
	&"contact": 2, &"enemy_down": 2, &"suppressed": 2, &"out_of_ammo": 2, &"ack": 2, &"intel": 2,
	&"tactic": 1, &"reloading": 1, &"moving": 1, &"covering": 1, &"set": 1, &"no_shot": 1, &"clear": 1,
}
## Enemy down, by what the man was (GroupBoard.soldier_kind): its own line.
const ENEMY_DOWN_LINES := {"mg": "Gunner down!", "at": "RPG's down!", "sniper": "Sniper down!"}
## Grenade!: who's this close to where a live grenade lands calls it (the nearest of the side it
## threatens). Proposed.
const GRENADE_CALL_M := 12.0
## A suppressed man calls where it's coming from when the threat is this fresh (s).
const THREAT_FRESH_S := 5.0
## Callout ids for thrown items.
const THROW_IDS := {&"frag_grenade": &"frag_out", &"smoke_grenade": &"smoke_out", &"flashbang": &"flash_out"}
const DIRECTIONS: Array[String] = ["front", "front right", "right", "back right", "back", "back left", "left", "front left"]
## Clock positions for the same 8-way bucket as DIRECTIONS (mil radio convention: the odd hours
## are skipped, same as real callouts).
const CLOCK: Array[String] = ["twelve", "two", "three", "five", "six", "eight", "nine", "eleven"]
## A contact this close (m) gets the voiced "close" line (contact() voice id).
const CLOSE_RANGE_M := 30.0
## Subtitles for an intel reveal, by the enemy site type it gave away (IntelReveal.intel_found).
const INTEL_LINES := {
	&"hq": "Got the HQ marked!",
	&"qrf_base": "Got a QRF base marked!",
	&"aa": "Got an AA site marked!",
	&"outpost": "Got an outpost marked!",
	&"checkpoint": "Got a checkpoint marked!",
}

## Host: what was said, newest last: {"speaker", "id", "text", "to": PackedInt32Array, "time"}.
var sent: Array[Dictionary] = []
## Every peer: lines shown here, newest last: {"speaker", "id", "text", "time"}.
var shown: Array[Dictionary] = []
var _last_by_speaker := {}  # speaker node name -> time of their last line
var _last_by_key := {}  # "speaker/key" -> time that callout was last said
var _last_by_side_key := {}  # "faction/key" -> time someone on that side last said it
var _pending := {}  # speaker node name -> the line waiting for the speaker gap
var _group_air := {}  # group key -> {"until": time its line holds the air, "prio", "who"}


## The level's Callouts node, or null.
static func of(from: Node) -> Callouts:
	var level := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return level.get_node_or_null(^"Callouts") as Callouts if level else null


## How a callout names a soldier: the AI's callsign, or "Player <id>".
static func display_name(s: Soldier) -> String:
	if s == null or not is_instance_valid(s):
		return "Someone"
	return s.display_name()  # a dead player's body is still "Player 2"


## Plays res://audio/callouts/<id>.ogg from `speaker` if that file exists; silent (null)
## otherwise.
static func play(id: StringName, speaker: Node3D) -> AudioStreamPlayer3D:
	if speaker == null or not is_instance_valid(speaker) or not speaker.is_inside_tree():
		return null
	var model := speaker.get_node_or_null(^"Model") as CharacterModel
	if model:
		model.shout()  # the face: mouth open while he calls out (FaceRig)
	var path := voiced_path(id, speaker)
	if path == "":
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		return null
	if Sfx.voice_route(speaker) == &"intercom":  # (combined arms A7: a crewmate in your vehicle, on the intercom)
		Sfx.play_intercom(stream, speaker)
		return null
	# A squadmate further than RADIO_M off comes over the net: in your ear, filtered (Sfx "Radio").
	var ear: Variant = Sfx.listener()
	if speaker is Soldier and (speaker as Soldier).faction != &"hostile" and ear is Vector3 and (ear as Vector3).distance_to(speaker.global_position) > RADIO_M:
		var net := AudioStreamPlayer.new()
		net.stream = stream
		net.bus = &"Radio"
		net.volume_db = RADIO_DB
		speaker.add_child(net)
		net.finished.connect(net.queue_free)
		net.play()
		return null
	var audio := AudioStreamPlayer3D.new()
	audio.stream = stream
	audio.bus = &"Voice"  # Sfx makes the bus
	audio.volume_db = VOICE_DB
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
	if (id not in URGENT and now - float(_last_by_speaker.get(who, -1000.0)) < SPEAKER_GAP_S) or not group_free(speaker, id, true):
		_pending[who] = {"speaker": speaker, "id": id, "line": line, "repeat_key": repeat_key,
			"shared": shared, "side_gap": side_gap, "until": now + PENDING_S}
		return false
	_send(speaker, id, line, repeat_key, shared)
	if speaker.faction == &"hostile":
		server_vocal(speaker, id)  # the enemy is heard, in his own tongue (voiced_path), never subtitled
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
		elif (p.id in URGENT or now - float(_last_by_speaker.get(who, -1000.0)) >= SPEAKER_GAP_S) and group_free(speaker, p.id):
			_pending.erase(who)
			_send(speaker, p.id, p.line, p.repeat_key, p.shared)


func _send(speaker: Soldier, id: StringName, line: String, repeat_key: String, shared := "") -> void:
	var now := Soldier._now()
	var who := String(speaker.name)
	_last_by_key[repeat_key] = now
	if shared != "":
		_last_by_side_key[shared] = now
	_last_by_speaker[who] = now
	_group_air[group_of(speaker)] = {"until": now + GROUP_GAP_S, "prio": priority(id), "who": who}
	var to := recipients(speaker)
	sent.append({"speaker": who, "id": id, "text": line, "to": to, "time": now})
	if sent.size() > LOG_SIZE:
		sent.pop_front()
	for peer in to:
		_show.rpc_id(peer, speaker.get_path(), display_name(speaker), String(id), line)


## Callout `id`'s priority (PRIORITY): its own, or its nearest listed prefix's, else 0.
static func priority(id: StringName) -> int:
	var base := String(id)
	while true:
		if PRIORITY.has(StringName(base)):
			return int(PRIORITY[StringName(base)])
		var cut := base.rfind("_")
		if cut <= 0:
			return 0
		base = base.substr(0, cut)
	return 0


## Host only. Who `speaker` shares the air with: his squad, or his side's men in none.
func group_of(speaker: Soldier) -> String:
	var level := CompoundLevel.current(self)
	var squad := level.squad_of(speaker) if level else null
	return "squad/%d" % squad.get_instance_id() if squad else "side/%s" % speaker.faction


## Host only. Whether `speaker` may say `id` now as far as his group goes: nobody else in it is
## talking, or `id` outranks what is being said (3 always cuts in). `new`: a fresh line, which
## also waits behind anyone else in the group already waiting with as much weight.
func group_free(speaker: Soldier, id: StringName, new := false) -> bool:
	var prio := priority(id)
	if prio >= 3:
		return true
	var group := group_of(speaker)
	var air: Dictionary = _group_air.get(group, {})
	if not (air.is_empty() or Soldier._now() >= float(air.until) or String(air.who) == String(speaker.name)) and prio <= int(air.prio):
		return false
	if new:
		for who: String in _pending:
			var p: Dictionary = _pending[who]
			if who != String(speaker.name) and is_instance_valid(p.speaker) and priority(p.id) >= prio and group_of(p.speaker) == group:
				return false
	return true


## A hero squad's or allied element's man (Soldier.hc_id) is heard only this close (G5); the
## rest of what his squad says goes over the company net (HighCommand). Proposed.
const HC_VOICE_M := 50.0


## Host only. The peers who hear `speaker`: every connected player on the speaker's side (only
## those within HC_VOICE_M for a high command group's man, G5).
func recipients(speaker: Soldier) -> PackedInt32Array:
	var out := PackedInt32Array()
	var level := CompoundLevel.current(self)
	if level == null or speaker == null:
		return out
	var peers := multiplayer.get_peers()
	var near_only := speaker.hc_id != &""
	for node in level.players.get_children():
		var player := node as Soldier
		if player == null or player.is_queued_for_deletion() or player.faction != speaker.faction:
			continue
		if near_only and player.global_position.distance_to(speaker.global_position) > HC_VOICE_M:
			continue
		var peer := player.owner_peer()
		if (peer == multiplayer.get_unique_id() or peer in peers) and peer not in out:
			out.append(peer)
	return out


## Host only. "Contact, two o'clock, 80 m": clock position and distance from the squad
## leader's view (the speaker's own when there's no leader), as Arma calls them. The voiced
## line is pre-rendered per clock position, close range (CLOSE_RANGE_M) getting its own
## urgent-sounding line (gen_callouts.py "contact_<clock>[_close]"); the subtitle keeps the
## exact distance either way. Only the first spotter calls a given enemy; the rest of the
## side stays quiet for SQUAD_CONTACT_GAP_S.
func contact(speaker: Soldier, enemy: Soldier) -> bool:
	if enemy == null:
		return false
	var level := CompoundLevel.current(self)
	var squad := level.squad_of(speaker) if level else null  # G12: the speaker's own squad
	var from: Node3D = squad.leader if squad and is_instance_valid(squad.leader) else speaker
	var distance := from.global_position.distance_to(enemy.global_position)
	var clock := clock_word(from, enemy.global_position)
	var voice_id := StringName("contact_%s%s" % [clock, "_close" if distance <= CLOSE_RANGE_M else ""])
	return say(speaker, voice_id, "Contact, %s o'clock, %d m%s" % [clock, round_distance(distance), _what_seen(squad, enemy)],
		"contact", "contact/%s" % enemy.name, SQUAD_CONTACT_GAP_S)


## Host only. The casualty's battle buddy, or the nearest squadmate in range, calls
## "Man down! Charlie is down".
func man_down(casualty: Soldier) -> bool:
	var speaker := witness(casualty)
	if speaker == null:
		return false
	return say(speaker, &"man_down", "Man down! %s is down" % display_name(casualty), "man_down/%s" % casualty.name)


## Host only. A live grenade about to go off at `at`: the nearest AI of the side it threatens
## (not the thrower's) within GRENADE_CALL_M shouts "Grenade!"; one call a grenade.
func grenade_incoming(at: Vector3, thrower: Node, grenade_key: String) -> bool:
	var thrower_side: Variant = (thrower as Soldier).faction if thrower is Soldier and is_instance_valid(thrower) else null
	var best: Soldier = null
	var best_d := GRENADE_CALL_M
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s.is_queued_for_deletion() or not s.is_ai() or not s.vitals.is_up() or (thrower_side != null and s.faction == thrower_side):
			continue
		var d := s.global_position.distance_to(at)
		if d <= best_d:
			best = s
			best_d = d
	if best == null:
		return false
	return say(best, &"grenade", "", "grenade", "grenade/%s" % grenade_key, 4.0)


## Host only. A friendly hit a friendly: the one hit (an AI, up), or the nearest AI who saw it,
## shouts "Check fire!" ("Check fire! You're hitting Charlie!"); one call per shooter a while.
func check_fire(victim: Soldier, shooter: Soldier) -> bool:
	if victim == null or shooter == null or victim == shooter:
		return false
	var speaker := victim if victim.is_ai() and victim.vitals.is_up() else witness(victim)
	if speaker == null or speaker == shooter:
		return false
	var line := "Check fire! Check fire!" if speaker == victim else "Check fire! You're hitting %s!" % display_name(victim)
	return say(speaker, &"check_fire", line, "check_fire", "check_fire/%s" % shooter.name, SQUAD_CONTACT_GAP_S)


## Host only. `killer` (an AI) dropped `victim`, an enemy: "Enemy down!", or what he was
## ("Gunner down!", "RPG's down!", "Sniper down!").
func enemy_down(killer: Soldier, victim: Soldier) -> bool:
	if killer == null or victim == null or not killer.is_ai() or killer.faction == victim.faction:
		return false
	var kind := GroupBoard.soldier_kind(victim)
	var id := StringName("enemy_down_%s" % kind) if ENEMY_DOWN_LINES.has(kind) else &"enemy_down"
	return say(killer, id, String(ENEMY_DOWN_LINES.get(kind, LINES[&"enemy_down"])), "enemy_down", "enemy_down/%s" % victim.name, SQUAD_CONTACT_GAP_S)


## Host only. `speaker` is pinned: "Pinned down! Fire from the left!" (where it comes from, when
## his threat is fresh), else "I'm pinned!".
func suppressed(speaker: Soldier) -> bool:
	if speaker == null:
		return false
	var fresh := Soldier._now() - speaker.threat_time <= THREAT_FRESH_S and speaker.threat_pos != Vector3.ZERO
	var line := "Pinned down! Fire from the %s!" % direction_word(speaker, speaker.threat_pos) if fresh else String(LINES[&"suppressed"])
	return say(speaker, &"suppressed", line)


## Host only. `speaker`'s weapon is dry, nothing left to load: "I'm out! Need ammo!".
func out_of_ammo(speaker: Soldier) -> bool:
	return say(speaker, &"out_of_ammo")


## Host only. `speaker` answers an order (a voice order's confirmation, VoiceCommands "ack"):
## "Holding.", "Moving.". Voiced as ack_<what> (gen_callouts.py).
func ack(speaker: Soldier, what: String, line: String) -> bool:
	if speaker == null or line == "":
		return false
	return say(speaker, StringName("ack_%s" % what), line, "ack")


## Any peer (a voice order, VoiceOrder._confirm): asks the host for `speaker`'s confirmation.
func request_ack(speaker: Soldier, what: String, line: String) -> void:
	if speaker == null:
		return
	if multiplayer.is_server():
		ack(speaker, what, line)
	else:
		_rq_ack.rpc_id(1, get_path_to(speaker), what, line)


@rpc("any_peer", "call_remote", "reliable")
func _rq_ack(speaker_path: NodePath, what: String, line: String) -> void:
	var s := get_node_or_null(speaker_path) as Soldier
	var level := CompoundLevel.current(self)
	var asker: Soldier = level.players.get_node_or_null(NodePath(str(multiplayer.get_remote_sender_id()))) as Soldier if level else null
	if s == null or not s.is_ai() or asker == null or s.faction != asker.faction or line.length() > 40:
		return
	ack(s, what.left(20), line)


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


## Host only. A squadmate lays down who he carried (contact, "Stop bringing casualties", or
## where he was taking them): "Putting Charlie down" / "Leaving Charlie's body here" (Captain,
## 2026-10-14: "bots should act like players, communicate with the player").
func putting_down(speaker: Soldier, other: Soldier, dead: bool) -> bool:
	if other == null:
		return false
	var line := ("Leaving %s's body here" if dead else "Putting %s down") % display_name(other)
	return say(speaker, &"putting_down", line, "putting_down/%s" % other.name)


## Host only. A squadmate goes through a body for what he needs: "Checking Charlie's body"
## (an enemy's: "Checking the body").
func scavenging(speaker: Soldier, dead: Soldier) -> bool:
	if dead == null:
		return false
	var line := "Checking %s's body" % display_name(dead) if dead.faction == speaker.faction else "Checking the body"
	return say(speaker, &"scavenging", line, "scavenging/%s" % dead.name)


## Host only. Whoever's carrying the intel calls out the kind of enemy site it just gave away
## (IntelReveal.server_reveal_for): "Got the HQ marked!". Lines are pre-rendered per site type
## (gen_callouts.py "intel_<type>"); an unlisted type (none currently) says nothing.
func intel_found(speaker: Soldier, site_type: String) -> bool:
	var id := StringName(site_type)
	if speaker == null or not INTEL_LINES.has(id):
		return false
	return say(speaker, StringName("intel_%s" % site_type), String(INTEL_LINES[id]), "intel")


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


## The 8-way bucket `point` is seen in from `from` (0 ahead, 90 to the right), shared by
## direction_word and clock_word.
static func _octant(from: Node3D, point: Vector3) -> int:
	var local := from.global_basis.inverse() * (point - from.global_position)
	var angle := rad_to_deg(atan2(local.x, -local.z))
	return posmod(roundi(angle / 45.0), 8)


## "front", "front right", ... "left", "front left": where `point` is seen from `from`.
static func direction_word(from: Node3D, point: Vector3) -> String:
	return DIRECTIONS[_octant(from, point)]


## A contact report's third D (docs/ai_tactics.md T-B2): how many the squad knows of round
## `enemy`, and the worst of what they carry: ", three men, MG".
static func _what_seen(squad: Squad, enemy: Soldier) -> String:
	if squad == null or enemy == null:
		return ""
	var n := 0
	var worst := "inf"
	for e: Dictionary in squad.enemy_picture():
		if (e.pos as Vector3).distance_to(enemy.global_position) <= 25.0:
			n += 1
			var who := e.who as Soldier
			var k := GroupBoard.soldier_kind(who) if who and is_instance_valid(who) else "inf"
			if k in ["at", "mg", "sniper"] and (worst == "inf" or k == "at"):
				worst = k
	n = maxi(n, 1)
	var words := ["", "one man", "two men", "three men", "four men", "five men"]
	var count: String = words[n] if n < words.size() else "%d men" % n
	return ", %s%s" % [count, {"at": ", RPG", "mg": ", MG", "sniper": ", sniper"}.get(worst, "")]


## "twelve", "two", ... "nine", "eleven" o'clock: where `point` is seen from `from`.
static func clock_word(from: Node3D, point: Vector3) -> String:
	return CLOCK[_octant(from, point)]


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
	if id == "people" and CompoundLevel.current(self) is SurvivalLevel:
		VoiceLines.play_people(text, get_node_or_null(speaker_path))  # Fallen's lines: their clip, else the subtitle alone
		return
	play(StringName(id), get_node_or_null(speaker_path) as Node3D)


## The subtitle display the HUD adds: the latest callouts, bottom centre.
class Subtitles extends Label:
	## The HUD's one outlined style, wrapping; the Hud puts it in its bottom-centre zone over the
	## vehicle readout (docs/ui_audit.md item 4: it sat 17 px over the readout, unwrapped).
	func _ready() -> void:
		UiKit.apply(self)
		theme_type_variation = &"HudLabel"
		horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## The callouts to show (current_lines), and the height (px) the Hud has room for: the
	## newest lines that fit are shown, whole.
	var feed := PackedStringArray()
	var room := INF
	var _shown := ""

	func _process(_delta: float) -> void:
		var callouts := Callouts.of(self)
		feed = callouts.current_lines() if callouts else PackedStringArray()

	## Shows the newest callouts that fit `room` px tall in a column `width` wide (measured with
	## the font, not the label: a hidden label keeps a stale width).
	func refit(width: float) -> void:
		var key := "%s|%d|%d" % ["
".join(feed), int(minf(room, 99999.0)), int(width)]
		if key == _shown:
			return
		_shown = key
		var font := get_theme_font(&"font")
		var font_size := get_theme_font_size(&"font_size")
		var spacing := float(get_theme_constant(&"line_spacing"))
		var line := font.get_height(font_size)
		var shown := PackedStringArray()
		var lines := 0
		for k in range(feed.size() - 1, -1, -1):
			var h := font.get_multiline_string_size(feed[k], HORIZONTAL_ALIGNMENT_CENTER, maxf(width, 1.0), font_size).y
			var more := maxi(roundi(h / line), 1)
			if (lines + more) * (line + spacing) - spacing > room:
				break
			lines += more
			shown.insert(0, feed[k])
		text = "
".join(shown)
		visible = text != ""

## Voiced callouts (Captain, 2026-10-16: "a free way to do voices", "several game safe voices"):
## Piper TTS lines (audio/sfx/CREDITS.md) in AUDIO_DIR v<k>/<id>_<n>.wav, one folder per voice.
## Each speaker keeps one voice (by name, so every peer picks the same) and a phrasing at random;
## no voiced line: the old single file <id>.ogg, else "" (subtitle only).
const VOICES := 8
## Squadmates further than this from you are heard over the radio instead (play).
const RADIO_M := 30.0
## Voice levels (Captain, 2026-10-17: the voices were "annoyingly loud... louder than the
## environment"): a spoken callout nearby, and one over the net, under the gunfire and ambience
## rather than over it. The player's Voice slider scales both (GameSettings.BUSES).
const VOICE_DB := -10.0
const RADIO_DB := -13.0
## Enemy languages (a soldier's by his name; Russian twice as often) and how many voices each has.
const ENEMY_LANGS: Array[String] = ["ru", "ru", "fa"]
const ENEMY_VOICES := {"ru": 2, "fa": 1}
const FEMALE_VOICES := 4  # female soldiers' voices, in AUDIO_DIR female/v<k>/ (Captain: "female voices for female soldiers")
const PHRASINGS := 2


static func voiced_path(id: StringName, speaker: Node) -> String:
	var female := speaker is Soldier and (speaker as Soldier).model != null and (speaker as Soldier).model.body == VoxelArt.FEMALE
	var count := FEMALE_VOICES if female else VOICES
	var dir := AUDIO_DIR + ("female/" if female else "")
	var h := absi(hash(String(speaker.name)))
	if speaker is Soldier and (speaker as Soldier).faction == &"hostile":
		# Enemies call out in their own tongue (Captain, 2026-10-16): Russian or Farsi, per soldier.
		var lang: String = ENEMY_LANGS[h % ENEMY_LANGS.size()]
		dir = AUDIO_DIR + lang + "/"
		count = int(ENEMY_VOICES[lang])
	var voice := int(speaker.get_meta(&"voice", h % count)) % count
	# A dynamic id (e.g. "contact_two_close") with no pre-rendered line yet, or that never gets
	# one (a hostile's tongue, say), falls back to its less specific prefix down to the bare
	# category ("contact"), so a new template slot degrades to the old generic line instead of
	# going silent.
	var base := String(id)
	while true:
		var options: Array[String] = []
		for n in range(1, PHRASINGS + 1):
			var p := "%sv%d/%s_%d.wav" % [dir, voice, base, n]
			if ResourceLoader.exists(p):
				options.append(p)
		if not options.is_empty():
			return options[randi() % options.size()]
		var cut := base.rfind("_")
		if cut <= 0:
			break
		base = base.substr(0, cut)
	var single := AUDIO_DIR + String(id) + ".ogg"
	return single if ResourceLoader.exists(single) else ""


## Host only: `speaker` cries out (VOCAL_IDS: hit, scream) where everyone near can hear it, either
## side, no subtitle (Captain, 2026-10-16: "add screams too"). Rate-limited per speaker.
const VOCAL_IDS: Array[StringName] = [&"hit", &"scream"]
const VOCAL_GAP_S := 2.5
var _last_vocal := {}


func server_vocal(speaker: Soldier, id: StringName) -> void:
	if not multiplayer.is_server() or speaker == null or not is_instance_valid(speaker) or not speaker.is_inside_tree():
		return
	var now := Soldier._now()
	if now - float(_last_vocal.get(speaker.name, -100.0)) < VOCAL_GAP_S:
		return
	_last_vocal[speaker.name] = now
	_vocal.rpc(get_path_to(speaker), String(id))


@rpc("authority", "call_local", "unreliable")
func _vocal(speaker_path: NodePath, id: String) -> void:
	var speaker := get_node_or_null(speaker_path) as Node3D
	if speaker:
		play(StringName(id), speaker)
		var model := speaker.get_node_or_null(^"Model")
		if model and model.has_method(&"flinch"):
			model.call(&"flinch", 1.0 if id == "scream" else 0.7)  # the hit shows too (CharacterModel.flinch)
