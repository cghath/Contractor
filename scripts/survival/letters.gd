class_name Letters
extends RefCounted
## Letters (call 130, first form; docs/survival_mind.md section 4): a survivor writes a letter
## (the journal screen's "Write a letter": Intel.request_letter -> server_write), kept on their
## survivor record ("letters": [{"id", "day", "from", "text"}]). When they die the letters lie
## with what they dropped (server_on_death: a "letter" item each, its state the letter: "text",
## "from", "day", "letter_id"), and the newcomer who picks one up reads it in the journal's People
## tab (lines(): every letter a player carries is read into the world's "letters_read" and stays).

const ITEM := &"letter"
const MAX_CHARS := 600
const MAX_LETTERS := 12


## Host: `s` writes `text`. "" or why not.
static func server_write(s: Soldier, text: String) -> String:
	var t := text.strip_edges()
	if t == "":
		return "Nothing written"
	if s == null or s.is_ai():
		return "?"
	var rec := Survival.survivor_of(s)
	var list: Array = rec.get("letters", [])
	if list.size() >= MAX_LETTERS:
		return "No paper left for more letters"
	var st := Survival.state()
	var id := int(st.get("next_letter", 0)) + 1
	st["next_letter"] = id
	list.append({"id": id, "day": Survival.day(), "from": String(rec.get("name", "")), "text": t.substr(0, MAX_CHARS)})
	rec["letters"] = list
	Survival._journal_line("%s wrote a letter." % String(rec.get("name", "Someone")))
	Survival._tell(s, "You fold the letter and keep it on you")
	return ""


## Host: `s` died at `at` in `level` (Survival.server_player_died, before the newcomer): each of
## his letters lies there as a letter item. Returns how many.
static func server_on_death(s: Soldier, level: Node, at: Vector3) -> int:
	if s == null or s.is_ai() or level == null or not level.has_method(&"server_spawn_dropped"):
		return 0
	var list: Array = Survival.survivor_of(s).get("letters", [])
	var i := 0
	for l: Dictionary in list:
		var state := {"text": String(l.get("text", "")), "from": String(l.get("from", "")), "day": int(l.get("day", 0)), "letter_id": int(l.get("id", 0))}
		level.call(&"server_spawn_dropped", ITEM, 1, at + Vector3(0.3 + 0.2 * i, 0.5, -0.3), state)
		i += 1
	return i


## The letters read: every letter item a player in the hosted zone carries is read now (kept in
## the world's "letters_read"), as lines for the journal's People tab, oldest first.
static func lines(level: Node = null) -> Array:
	var st := Survival.state()
	var read: Dictionary = st.get("letters_read", {})
	if level != null:
		for p: Soldier in MapNodes.players(level):
			for e: Dictionary in Survival.kit_of(p.inventory):
				if StringName(String(e.get("id", ""))) != ITEM:
					continue
				var state: Dictionary = e.get("state", {})
				var key := str(int(state.get("letter_id", 0)))
				if key != "0" and not read.has(key):
					read[key] = {"from": String(state.get("from", "")), "day": int(state.get("day", 0)), "text": String(state.get("text", ""))}
	st["letters_read"] = read
	var keys := read.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	var out: Array = []
	for k: String in keys:
		var l: Dictionary = read[k]
		out.append("A letter from %s (day %d): %s" % [String(l.get("from", "someone")), int(l.get("day", 0)), String(l.get("text", ""))])
	return out
