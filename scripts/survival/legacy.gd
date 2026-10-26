class_name Legacy
extends RefCounted
## Letters and legacy in Contractor: Fallen (call 130, finishing the mind lane's first form in
## Letters; docs/survival_children.md section 3). A world keeps a lineage (Survival.state()
## ["lineage"]): every player survivor of this world, in order, written down when they die
## (server_on_death, from Survival.server_player_died before the newcomer): name, generation,
## background, the days they lived, the cause of death, the dead they put down and the things they
## built (counters on the survivor record: kills0 / built0 at birth against the world's counts),
## their letters, the companions who outlived them and, with no letter, last words the journal's
## voice writes for them. The journal's "Lineage" tab reads lineage_lines(); the People tab has the
## dead one's letters as "found on <name>" in their voice (found_lines). The scars page (call 97)
## reads lineage() when it comes.
##
## Graves: a burial places a grave marker piece inscribed with the name (BuildPieces
## "grave_marker": server_grave_marker) and marks it on the map (kind "grave"); a player survivor's
## death place is marked on the map too. Every number here is Proposed.

const KEY := "lineage"
## The map's mark kind for a grave (SurvivalMap: never fades).
const MARK_KIND := "grave"
## Last words by the writer's voice trait (JournalVoice.TRAITS), "any" for none.
const LAST_WORDS := {
	"optimist": "Tell them it was a good run. Most of it.",
	"gloomy": "Don't come looking. There's nothing here worth it.",
	"hot_headed": "Should have swung first.",
	"pious": "Keep a light in the window for me.",
	"calm": "Water's in the cellar. Boil it. That's all.",
	"any": "Keep the fire going.",
}


static func lineage() -> Array:
	var st := Survival.state()
	if not st.get(KEY) is Array:
		st[KEY] = []
	return st[KEY]


## A new survivor's counters start (Survival._new_survivor): the world's kills and builds now.
static func on_born(rec: Dictionary) -> void:
	rec["kills0"] = int(Survival.state().get("kills", 0))
	rec["built0"] = int(Survival.state().get("built_n", 0))


## Host (Builder: a block or a piece finished): the world's build count.
static func note_built() -> void:
	if Survival.running:
		Survival.state()["built_n"] = int(Survival.state().get("built_n", 0)) + 1


## The cause of `s`'s death in words.
static func cause_of(s: Soldier) -> String:
	if s == null:
		return "unknown causes"
	if String(Harm.last(s).get("faction", "")) == String(ZombieAI.INFECTED) or bool(s.get_meta(&"killed_by_dead", false)):
		return "killed by the dead"
	var c := String(s.vitals.last_cause.get("cause", "")) if s.vitals else ""
	if c.begins_with("round") or c == "lost a limb":
		return "shot"
	if c in ["blast", "fragment"]:
		return "caught in a blast"
	if c.begins_with("fall"):
		return "a fall"
	if c == "":
		return "unknown causes"
	return c


## The voice trait of a record (the first of JournalVoice.TRAITS it has), "any" for none.
static func voice_of(rec: Dictionary) -> String:
	var traits := JournalVoice.traits_of_record(rec)
	for t: String in JournalVoice.TRAITS:
		if t in traits:
			return t
	return "any"


## Host (Survival.server_player_died, before the newcomer): `s`'s survivor goes in the lineage.
## Returns the entry.
static func server_on_death(s: Soldier, at: Vector3) -> Dictionary:
	var rec := Survival.survivor_of(s)
	var rpg: Variant = rec.get(Rpg.KEY, {})
	var bg := String((rpg as Dictionary).get("background", "")) if rpg is Dictionary else ""
	if bg == "":
		bg = String(rec.get("background", "drifter"))
	var letters: Array = (rec.get("letters", []) as Array).duplicate(true)
	var outlived: Array = []
	for r: Dictionary in SurvivorsLayer.records().values():
		if String(r.get("status", "")) in ["companion", "settler"]:
			outlived.append(String(r.get("name", "")))
	var day := Survival.day()
	var e := {"name": String(rec.get("name", "Someone")), "generation": int(rec.get("generation", lineage().size() + 1)), "profile": Survival.profile_of(s),
		"background": bg, "born_day": int(rec.get("born_day", 0)), "died_day": day, "days": maxi(0, day - int(rec.get("born_day", 0))),
		"cause": cause_of(s), "kills": maxi(0, int(Survival.state().get("kills", 0)) - int(rec.get("kills0", 0))),
		"built": maxi(0, int(Survival.state().get("built_n", 0)) - int(rec.get("built0", 0))), "letters": letters,
		"outlived_by": outlived, "zone": String(Survival.state().get("zone", "")), "pos": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)],
		"traits": (rec.get("traits", []) as Array).duplicate(), "last_words": ""}
	if letters.is_empty():
		e.last_words = String(LAST_WORDS.get(voice_of(rec), LAST_WORDS.any))
		Survival._journal_line("%s's last words, as near as anyone remembers: \"%s\"" % [String(e.name), String(e.last_words)])
	lineage().append(e)
	SurvivalMap.server_add_mark(String(e.zone), at, "%s, fell day %d" % [String(e.name), day], MARK_KIND)
	return e


## The dead ones' letters for the People tab: "<a letter found on Name, in their voice>: text".
static func found_lines() -> Array:
	var out: Array = []
	for e: Dictionary in lineage():
		for l: Dictionary in e.get("letters", []):
			var head := JournalVoice.phrase("A letter found on %s, written day %d." % [String(e.name), int(l.get("day", 0))], e.get("traits", []))
			out.append("%s \"%s\"" % [head, String(l.get("text", ""))])
	return out


## The Lineage tab: every survivor of this world in order, then the one alive now.
static func lineage_lines(living: Dictionary = {}) -> Array:
	var out: Array = []
	for e: Dictionary in lineage():
		out.append("%d. %s (%s): %d days, %s. %d of the dead put down, %d things built." % [int(e.get("generation", 0)), String(e.name),
			String(e.get("background", "")), int(e.get("days", 0)), String(e.get("cause", "")), int(e.get("kills", 0)), int(e.get("built", 0))])
		var letters: Array = e.get("letters", [])
		if not letters.is_empty():
			out.append("   Left %d letter%s." % [letters.size(), "" if letters.size() == 1 else "s"])
		elif String(e.get("last_words", "")) != "":
			out.append("   Last words: \"%s\"" % String(e.last_words))
		var by: Array = e.get("outlived_by", [])
		if not by.is_empty():
			out.append("   Outlived by %s." % ", ".join(PackedStringArray(by)))
	if not living.is_empty():
		out.append("%d. %s: alive, day %d." % [int(living.get("generation", lineage().size() + 1)), String(living.get("name", "")),
			maxi(0, Survival.day() - int(living.get("born_day", 0)))])
	return out


# --- Graves --------------------------------------------------------------------------------------

## Host (SurvivorsLayer.server_bury): a grave marker piece inscribed with `rec`'s name at `at`
## (the nearest free ground cell), and a map mark. Returns the piece id (-1 when none fit).
static func server_grave_marker(level: Node, rec: Dictionary, at: Vector3, zone: String) -> int:
	var who := String(rec.get("name", "Someone"))
	SurvivalMap.server_add_mark(zone, at, "Grave: %s" % who, MARK_KIND)
	var b := Builder.find(level)
	if b == null:
		return -1
	var base := Builder.ground_cell(at + Vector3(0.0, 0.0, -1.0))
	for off: Vector3i in [Vector3i.ZERO, Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(1, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1)]:
		var id := b.server_place_piece(null, "grave_marker", base + off, 0, true)  # (a blueprint: nobody pays; built at once below)
		if id < 0:
			continue
		var p: Dictionary = (b.pieces[id] as Dictionary).duplicate()
		p["prog"] = 1.0
		p["paid"] = true
		p["bp"] = false
		p["text"] = who
		p["of"] = String(rec.get("id", ""))
		b._set_piece(id, p)
		return id
	return -1


## The grave marker pieces of `level` ({id: name}).
static func markers(level: Node) -> Dictionary:
	var out := {}
	var b := Builder.find(level)
	if b == null:
		return out
	for id: int in b.pieces:
		if String(b.pieces[id].get("k", "")) == "grave_marker":
			out[id] = String(b.pieces[id].get("text", ""))
	return out
