class_name VoiceLines
extends RefCounted
## Contractor: Fallen's voiced lines (calls 54, 76, 142; docs/survival_audio.md, docs/voice.md).
## Every line in data/survival_lines.json has a `voice` key ("<topic>_<NN>") and a `speaker`
## ({"kind", "sex", "age"}: who says it, so the renderer, tools/voices/render_survival.py, renders
## it in the voices that fit). The clip for a speaker is VOICE_DIR/<voice set>/<voice key>.<ext>;
## a speaker's voice set is "<sex>_<age>_<k>" (VOICE_SETS), the same on every peer (by name).
## No clip: the subtitle alone (subtitles are always shown: Callouts). A line with a name in it
## ({first}, {name}) has no clip unless it has a `voice_text` (the renderer skips it); other fills
## ({item}, {zone}, {want}, {background}) are voiced with a plain stand-in word.
##
## Talkativeness (people doc 5; call 76: "chatty when safe, quiet when sneaking"): how often
## someone says the small things (CHATTER topics), 0..1, from the record's "talkativeness" or its
## traits; when the tension layer is at alert or worse, chatter stops and only URGENT topics are said.

const VOICE_DIR := "res://assets/voices/survival/"
const EXTS: Array[String] = ["ogg", "wav"]
## Voice sets per sex and age band, and how many voices each has (the renderer's config,
## tools/voices/survival_tts.json, names the same sets). Proposed.
const VOICE_SETS := {"m_adult": 3, "f_adult": 3, "m_old": 1, "f_old": 1, "m_young": 1, "f_young": 1, "radio": 2}
const AGE_BANDS := {"young": 25, "old": 55}  # under 25 young, 55 and over old
const SPEAKER_KINDS: Array[String] = ["any", "survivor", "companion", "settler", "raider", "enclave", "radio"]
const URGENT: Array[String] = ["spotted_dead", "warn", "refuse_order", "refuse_again", "plan_horde", "threaten_fold", "threaten_draw",
	"break_crying", "break_rage", "break_binge", "break_hiding", "break_desertion", "break_refusal", "raider_warn", "enclave_halt"]
const CHATTER: Array[String] = ["plan_idle", "plan_dusk", "took_item", "hungry", "thirsty", "ate", "how_are_you", "think"]
## Talkativeness from traits (on top of TALK_BASE). Proposed.
const TALK_BASE := 0.5
const TALK_TRAITS := {"hot_headed": 0.15, "brave": 0.1, "kind": 0.05, "drinker": 0.1, "cruel": 0.05, "timid": -0.15, "lazy": -0.05, "squeamish": -0.05, "loyal": 0.05}

static var _index: Array[Dictionary] = []  # [{"re": RegEx, "topic", "voice", "speaker", "spoken"}], most literal first
static var played: Array[Dictionary] = []  # newest last: {"text", "voice", "path"} (tests, the log)


## The voice key of `topic`'s line number `index` (0-based).
static func voice_key(topic: String, index: int) -> String:
	return "%s_%02d" % [topic, index + 1]


## Whether a line can be voiced (no name in it, or a voice_text).
static func voiceable(line: Dictionary) -> bool:
	if line.has("voice_text"):
		return true
	var t := String(line.get("text", ""))
	return not ("{first}" in t or "{name}" in t)


## A person's voice set ("m_adult_2"): by sex and age band, the voice by their id's hash.
static func voice_set(sex: String, age: int, id: String) -> String:
	var band := "young" if age < int(AGE_BANDS.young) else ("old" if age >= int(AGE_BANDS.old) else "adult")
	var s := "f" if sex == "f" else "m"
	var key := "%s_%s" % [s, band]
	var n := int(VOICE_SETS.get(key, 1))
	return "%s_%d" % [key, absi(hash(id)) % n + 1]


## The voice set of a speaking body: its survivor record's when known (meta "voice_set" set once),
## else by the body (female model or not), an adult, by name.
static func voice_set_of(speaker: Node) -> String:
	if speaker == null:
		return "m_adult_1"
	if speaker.has_meta(&"voice_set"):
		return String(speaker.get_meta(&"voice_set"))
	var sid := String(speaker.get_meta(&"survivor_id", ""))
	var people: Variant = Survival.state().get("people", {})
	if sid != "" and people is Dictionary and (people as Dictionary).get(sid) is Dictionary:
		var rec: Dictionary = (people as Dictionary)[sid]
		return voice_set(String(rec.get("sex", "m")), int(rec.get("age", 35)), sid)
	var female := false
	if speaker is Soldier and (speaker as Soldier).model != null:
		female = (speaker as Soldier).model.body == VoxelArt.FEMALE
	return voice_set("f" if female else "m", 35, String(speaker.name))


## The clip for `voice` said by voice set `set_name`, else "".
static func path_for(voice: String, set_name: String) -> String:
	if voice == "":
		return ""
	for ext: String in EXTS:
		var p := "%s%s/%s.%s" % [VOICE_DIR, set_name, voice, ext]
		if ResourceLoader.exists(p):
			return p
	return ""


## A radio line's clip: the first radio voice set it was rendered in (the renderer renders a
## radio line only in the sets of its speaker's sex), else "".
static func radio_path(voice: String) -> String:
	for k in int(VOICE_SETS.get("radio", 1)):
		var p := path_for(voice, "radio_%d" % (k + 1))
		if p != "":
			return p
	return ""


## The line a shown text came from: {"topic", "voice", "speaker", "voiceable"} or {} (matched against
## every line's text with its fills as wildcards; the most literal match wins).
static func resolve(text: String) -> Dictionary:
	_build_index()
	for e: Dictionary in _index:
		if (e.re as RegEx).search(text) != null:
			return {"topic": e.topic, "voice": e.voice, "speaker": e.speaker, "voiceable": e.voiceable}
	return {}


static func _build_index() -> void:
	if not _index.is_empty():
		return
	var topics := TalkMenu.lines()
	var rows: Array[Dictionary] = []
	for topic: String in topics:
		var list: Array = topics[topic]
		for i in list.size():
			var line: Dictionary = list[i]
			var t := String(line.get("text", ""))
			var pattern := "^" + _escape(t) + "$"
			for fill: String in ["{first}", "{name}", "{want}", "{zone}", "{background}", "{item}"]:
				pattern = pattern.replace(_escape(fill), "(.+?)")
			var re := RegEx.new()
			if re.compile(pattern) != OK:
				continue
			rows.append({"re": re, "topic": topic, "voice": String(line.get("voice", voice_key(topic, i))), "speaker": line.get("speaker", {}),
				"voiceable": voiceable(line), "literal": t.length() - t.count("{") * 6})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.literal) > int(b.literal))
	_index = rows


static func _escape(s: String) -> String:
	var out := ""
	for c in s:
		out += ("\\" + c) if c in ".^$*+?()[]{}|\\/" else c
	return out


## Plays the clip for a shown people line `text` from `speaker` (Callouts._show, every peer):
## the path played, or "" (no clip: the subtitle alone). The subtitle is shown either way.
static func play_people(text: String, speaker: Node) -> String:
	var line := resolve(text)
	var path := ""
	if not line.is_empty() and bool(line.voiceable) and bool(FallenAudio.setting("voice_files")):
		path = path_for(String(line.voice), voice_set_of(speaker))
	played.append({"text": text, "voice": String(line.get("voice", "")), "path": path})
	played = played.slice(-40)
	if path == "" or not (speaker is Node3D) or not speaker.is_inside_tree():
		return path
	var stream := load(path) as AudioStream
	if stream == null:
		return ""
	var audio := AudioStreamPlayer3D.new()
	audio.stream = stream
	audio.bus = &"Voice"
	audio.volume_db = Callouts.VOICE_DB
	speaker.add_child(audio)
	audio.position = Vector3.UP * 1.6
	audio.finished.connect(audio.queue_free)
	audio.play()
	return path


# --- Talkativeness (host) ------------------------------------------------------------------------

## How much `rec` talks, 0..1: its "talkativeness" if set, else TALK_BASE with its traits'.
static func talkativeness(rec: Dictionary) -> float:
	if rec.has("talkativeness"):
		return clampf(float(rec.talkativeness), 0.0, 1.0)
	var t := TALK_BASE
	for tr: String in rec.get("traits", []):
		t += float(TALK_TRAITS.get(tr, 0.0))
	return clampf(t, 0.05, 0.95)


## Whether `rec` says a line of `topic` now: urgent topics always; chatter by talkativeness and
## never while it's tense (`quiet`); the rest unless quiet.
static func should_say(rec: Dictionary, topic: String, quiet: bool, roll := -1.0) -> bool:
	if topic in URGENT:
		return true
	if quiet:
		return false
	if topic in CHATTER:
		return (roll if roll >= 0.0 else randf()) < talkativeness(rec)
	return true


## Whether it's tense enough to keep quiet (the local tension layer at alert or worse).
static func quiet_now() -> bool:
	return FallenAudio.tension_now >= Tension.Level.ALERT
