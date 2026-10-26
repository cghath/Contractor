class_name MusicMoments
extends RefCounted
## Contractor: Fallen's music (call 63; docs/survival_audio.md). No combat music, ever. Music
## plays only:
## - at the settlement, from something there that makes it: a radio set in the stores, or a
##   companion or settler with the "guitar" trait or a guitar in their kit; a short loop by the
##   settlement's mood (warm, steady, low), and only while the tension layer is calm or uneasy;
## - at a handful of moments, once each (death each time): the first night survived, a death,
##   reaching the evac, the spring thaw.
## Every cue is a placeholder tune (FallenSynth.melody) until a file of its name is dropped in
## MUSIC_DIR (<cue>.ogg, .wav or .mp3): "stinger_first_night", "stinger_death", "stinger_evac",
## "stinger_thaw", "loop_radio_warm", "loop_guitar_low", ...

const MUSIC_DIR := "res://data/music/"
const ONCE: Array[String] = ["first_night", "evac", "thaw"]
const MOMENTS: Array[String] = ["first_night", "death", "evac", "thaw"]
const SOURCES: Array[String] = ["radio", "guitar"]
const MOODS: Array[String] = ["warm", "steady", "low"]
## Proposed: the night is survived at FIRST_NIGHT_HOUR on day 2; a death's stinger at most
## every DEATH_GAP_S; the settlement's mood bands by morale (Settlement.morale 0..100).
const FIRST_NIGHT_HOUR := 6.0
const DEATH_GAP_S := 30.0
const MOOD_WARM := 65.0
const MOOD_LOW := 35.0

var fired := {}  # moment -> true (the once moments; the world's, FallenAudio keeps it in the save)
var loop := ""  # the settlement loop playing now ("" none)
var last := ""  # the newest stinger fired
var _was_dead := false
var _death_at := -1000.0
var _season := ""


func _init(p_fired: Dictionary = {}) -> void:
	fired = p_fired


## One look at `ctx` at `now`: the stingers to play now (moments, in order) and `loop` set.
func update(ctx: Dictionary, now: float) -> Array[String]:
	var out: Array[String] = []
	var dead := bool(ctx.get("dead", false))
	if not dead and int(ctx.get("day", 1)) >= 2 and (int(ctx.get("day", 1)) > 2 or float(ctx.get("hour", 0.0)) >= FIRST_NIGHT_HOUR):
		_fire("first_night", out)
	if dead and not _was_dead and now - _death_at >= DEATH_GAP_S:
		_death_at = now
		out.append("death")
	_was_dead = dead
	if bool(ctx.get("evac", false)) and not dead:
		_fire("evac", out)
	var season := String(ctx.get("season", ""))
	if _season == "winter" and season == "spring":
		_fire("thaw", out)
	if season != "":
		_season = season
	loop = settlement_loop(ctx)
	if not out.is_empty():
		last = out[-1]
	return out


func _fire(moment: String, out: Array[String]) -> void:
	if fired.has(moment):
		return
	fired[moment] = true
	out.append(moment)


## The settlement's loop for `ctx` ("" none): you're at it, something there plays, it's quiet.
static func settlement_loop(ctx: Dictionary) -> String:
	var source := String(ctx.get("music_source", ""))
	if not bool(ctx.get("at_settlement", false)) or source == "" or bool(ctx.get("dead", false)):
		return ""
	if int(ctx.get("tension_level", 0)) >= Tension.Level.ALERT:
		return ""  # no combat music
	return "loop_%s_%s" % [source, mood_of(float(ctx.get("morale", 50.0)))]


static func mood_of(morale: float) -> String:
	return "warm" if morale >= MOOD_WARM else ("low" if morale < MOOD_LOW else "steady")


## What plays music at the settlement: "radio" (a radio set in the stores, or yours on), "guitar"
## (a member with the guitar trait or a guitar in their kit), else "". Host data (Settlement).
static func source_at_settlement(members: Array, stores_radio: bool) -> String:
	for rec: Dictionary in members:
		if SurvivorPerson.has_trait(rec, "guitar"):
			return "guitar"
		for e: Variant in rec.get("kit", []):
			if e is Array and not (e as Array).is_empty() and String((e as Array)[0]) == "guitar":
				return "guitar"
	return "radio" if stores_radio else ""


## The file that replaces cue `cue`, else "" (the placeholder plays).
static func file_for(cue: String) -> String:
	for ext: String in ["ogg", "wav", "mp3"]:
		var p := "%s%s.%s" % [MUSIC_DIR, cue, ext]
		if ResourceLoader.exists(p):
			return p
	return ""


## The stream for `cue`: its file when there is one, else the placeholder tune.
static func stream_for(cue: String) -> AudioStream:
	var p := file_for(cue)
	if p != "":
		var s := load(p) as AudioStream
		if s:
			return s
	return FallenSynth.get_stream(cue)


## Placeholder tunes (MIDI notes, 0 a rest): short, plain, a little sad.
const TUNES := {
	"stinger_first_night": [[57, 60, 64, 0, 62, 60, 57], 0.45, "pad"],
	"stinger_death": [[52, 0, 50, 0, 45], 0.7, "pad"],
	"stinger_evac": [[57, 61, 64, 69, 0, 68, 69], 0.4, "pad"],
	"stinger_thaw": [[64, 67, 71, 72, 71, 67], 0.35, "box"],
	"radio": [[60, 64, 67, 64, 62, 65, 69, 65, 60, 64, 67, 72, 71, 67, 64, 62], 0.32, "box"],
	"guitar_warm": [[45, 52, 57, 52, 48, 55, 60, 55, 43, 50, 55, 50, 45, 52, 57, 52], 0.3, "pluck"],
	"guitar_steady": [[45, 52, 57, 52, 50, 57, 62, 57, 45, 52, 57, 52, 40, 47, 52, 47], 0.33, "pluck"],
	"guitar_low": [[45, 52, 57, 0, 41, 48, 53, 0, 43, 50, 55, 0, 40, 47, 52, 0], 0.4, "pluck"],
}


static func placeholder(cue: String) -> AudioStreamWAV:
	var key := cue
	if cue.begins_with("loop_radio"):
		key = "radio"
	elif cue.begins_with("loop_guitar_"):
		key = cue.trim_prefix("loop_")
	var t: Array = TUNES.get(key, TUNES["stinger_death"])
	return FallenSynth.melody(t[0], float(t[1]), String(t[2]), cue.begins_with("loop_"))
