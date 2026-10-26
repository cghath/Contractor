class_name JournalVoice
extends RefCounted
## The journal's voice (call 119; docs/survival_mind.md section 4): the journal's templated lines
## (Survival._journal_line: "X died.", "X was bitten.") written in the survivor's own voice,
## shaped by their traits (optimist, gloomy, hot-headed, pious, calm). phrase() finds the line's
## event (EVENTS' words) and wraps it in a variant tagged with one of the writer's traits from the
## "journal" section of data/survival_lines.json (else VOICES); the fact itself is kept word for
## word ({line}), so what was written stays searchable. The writer is the host's survivor; every
## player survivor gets one voice trait at birth (roll_voice), and the flaws lend theirs (a
## hot-headed flaw writes hot-headed).

const LINES_PATH := "res://data/survival_lines.json"
const TRAITS: Array[String] = ["optimist", "gloomy", "hot_headed", "pious", "calm"]
## An event by the words in the line (first match wins).
const EVENTS := [["dark", ["flesh", "meat from"]], ["death", ["died", "is dead", "was killed"]], ["bite", ["bitten"]],
	["break", ["broke down"]], ["arrival", ["came to the farm", "joined", "came to us"]], ["letter", ["letter"]]]
## Fallback variants: {event: {trait: "template"}} ("any" for every event).
const VOICES := {
	"death": {"optimist": "{line} We keep going; it's what they'd want.", "gloomy": "{line} Another name for the list. The list only gets longer.",
		"hot_headed": "{line} Somebody is going to pay for this.", "pious": "{line} Lord, keep them. Keep the rest of us too.",
		"calm": "{line} We buried what we could and went on."},
	"bite": {"optimist": "{line} Plenty heal clean. Plenty.", "gloomy": "{line} We all know how this ends.",
		"hot_headed": "{line} I put the thing down myself, twice over.", "pious": "{line} I prayed over the wound.",
		"calm": "{line} Cleaned it, dressed it, wrote down the hour."},
	"dark": {"optimist": "{line} We lived. That has to count for something.", "gloomy": "{line} There's no coming back from this, and we know it.",
		"hot_headed": "{line} Don't judge me. You weren't there, you weren't starving.", "pious": "{line} Forgive us. I don't think anyone will.",
		"calm": "{line} It was that or nothing. I won't write about it again."},
	"any": {"optimist": "{line} Still here, though.", "gloomy": "{line} Nothing gets better.", "hot_headed": "{line} I'm sick of it.",
		"pious": "{line} God willing, tomorrow.", "calm": "{line}"},
}

static var _voices: Dictionary = {}


static func voices() -> Dictionary:
	if _voices.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LINES_PATH))
		var j: Variant = (parsed as Dictionary).get("journal", {}) if parsed is Dictionary else {}
		var v: Variant = (j as Dictionary).get("voices", {}) if j is Dictionary else {}
		_voices = v if v is Dictionary and not (v as Dictionary).is_empty() else VOICES
	return _voices


## The event a journal line tells ("any" when none matches).
static func event_of(text: String) -> String:
	var low := text.to_lower()
	for e: Array in EVENTS:
		for w: String in e[1]:
			if low.contains(w):
				return String(e[0])
	return "any"


## `text` in the voice of a writer with `traits`: the event's variant for the first of the
## writer's voice traits (TRAITS' order), else the "any" one; unchanged with none.
static func phrase(text: String, traits: Array) -> String:
	if text == "" or traits.is_empty():
		return text
	var ev := event_of(text)
	var all := voices()
	for t: String in TRAITS:
		if not t in traits:
			continue
		for key: String in [ev, "any"]:
			var by: Variant = all.get(key, {})
			if not by is Dictionary or not (by as Dictionary).has(t):
				continue
			var tpl: Variant = (by as Dictionary)[t]
			if tpl is Array:
				var arr: Array = tpl
				tpl = arr[absi(hash(text)) % arr.size()] if not arr.is_empty() else "{line}"
			return String(tpl).replace("{line}", text)
	return text


## A new survivor's voice (Survival._new_survivor): one of TRAITS by the world's rng.
static func roll_voice(rng: RandomNumberGenerator) -> Array:
	return [TRAITS[rng.randi_range(0, TRAITS.size() - 1)]]


## The journal's writer's traits: the host's survivor's ("traits"), and the flaws' (Rpg's record:
## hot-headed).
static func writer_traits() -> Array:
	var all: Variant = Campaign.section(Survival.SURVIVORS)
	var rec: Dictionary = (all as Dictionary).get(BaseHub.profile(), {}) if all is Dictionary else {}
	return traits_of_record(rec)


static func traits_of_record(rec: Dictionary) -> Array:
	var out: Array = (rec.get("traits", []) as Array).duplicate()
	var rpg: Variant = rec.get(Rpg.KEY, {})
	if rpg is Dictionary:
		for f: String in (rpg as Dictionary).get("flaws", []):
			if f == "hot_headed" and not "hot_headed" in out:
				out.push_front("hot_headed")
			elif f in ["coward", "smoker", "drinker"] and not f in out:
				out.append(f)
	return out
