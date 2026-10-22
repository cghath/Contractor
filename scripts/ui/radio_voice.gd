class_name RadioVoice
extends RefCounted
## Radio lines as pre-rendered clips strung together (docs/combined_arms.md 4.6; B4): digits,
## "grid", "metres", the compass words, the callsigns and each request's stock words, rendered
## once with Piper (tools/voices/gen_radio.py, the words in data/radio_voice.json) into
## res://audio/radio/v<k>/<word>.wav. A line is said only when every word has a clip (no gaps
## mid-sentence); otherwise it's a subtitle alone. No runtime speech synthesis. Played in the ear
## on Sfx's "Radio" bus, one line at a time per peer.

const PATH := "res://data/radio_voice.json"
const CLIP_DIR := "res://audio/radio"
const GAP_S := 0.04
const DB := -10.0
const DIGITS: Array[String] = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]

static var _data := {}
static var _exists := {}  # clip path -> bool (looked up once)


static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		var parsed: Variant = JSON.parse_string(text) if text != "" else null
		_data = parsed if parsed is Dictionary else {"_missing": true}
	return _data


## Every word the clips cover.
static func vocabulary() -> Dictionary:
	var out := {}
	for w: String in data().get("words", []):
		out[w] = true
	for w in DIGITS:
		out[w] = true
	return out


## `text` as clip words: lower case, punctuation gone, numbers digit by digit ("041" -> zero four
## one; radio style), hyphenated compass words split ("north-east" -> north east).
static func tokens(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var clean := ""
	for c in text.to_lower():
		clean += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "'" else " "
	for word in clean.split(" ", false):
		if word.is_valid_int():
			for d in word:
				out.append(DIGITS[int(d)])
		else:
			out.append(word.replace("'", ""))
	return out


## The words of `text` with no clip in the vocabulary (empty: it can all be said).
static func missing(text: String) -> PackedStringArray:
	var vocab := vocabulary()
	var out := PackedStringArray()
	for w in tokens(text):
		if not vocab.has(w) and not (w in out):
			out.append(w)
	return out


## The clip paths for `text` in voice `voice`, or [] if any is missing on disk.
static func clips(text: String, voice := 0) -> PackedStringArray:
	var out := PackedStringArray()
	for w in tokens(text):
		var path := "%s/v%d/%s.wav" % [CLIP_DIR, voice, w]
		if not _exists.has(path):
			_exists[path] = ResourceLoader.exists(path)
		if not _exists[path]:
			return PackedStringArray()
		out.append(path)
	return out


## Plays `text` on this peer (voice by its callsign, the first word), when its clips are there.
static func say(from: Node, text: String) -> void:
	if from == null or not from.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var voices := int(data().get("voices", 1))
	var voice := absi(hash(text.get_slice(",", 0))) % maxi(voices, 1)
	var paths := clips(text, voice)
	if paths.is_empty():
		return
	var player := AudioStreamPlayer.new()
	player.bus = &"Radio"
	player.volume_db = DB
	from.add_child(player)
	_play_next(player, paths, 0)


static func _play_next(player: AudioStreamPlayer, paths: PackedStringArray, i: int) -> void:
	if i >= paths.size() or not is_instance_valid(player):
		if is_instance_valid(player):
			player.queue_free()
		return
	player.stream = load(paths[i]) as AudioStream
	player.play()
	player.finished.connect(func() -> void:
		player.get_tree().create_timer(GAP_S).timeout.connect(func() -> void: _play_next(player, paths, i + 1)), CONNECT_ONE_SHOT)
