class_name Story
extends RefCounted
## The campaign's story (docs/story.md): the main arc in acts, its handmade story contracts
## (data/contracts.json "story"), the clues intel turns up and the evidence count they make.
## Campaign section "story":
## - "act": the act being played (1 at a new campaign);
## - "evidence": the evidence count; "scraps": ordinary intel turned in towards the next point;
##   "ledgers": Vantage ledgers turned in that counted (up to LEDGER_EVIDENCE_MAX);
## - "clues": [{"id", "text", "act", "day"}], what intel said, in the order found;
## - "done": story contract ids done; "offered": {story id: cid} on the board or held;
##   "back_day": {story id: the day a failed one comes back}; "acts_done": [acts closed].
##
## Captain, 2026-10-20 ("both"): a story contract goes on the board once those it comes "after"
## are done and the "clues" it needs are found (server_update: a new campaign, each day, each
## contract closed); an act after the first opens at its "evidence" count. It's an
## existing contract type with its own title, brief and objectives ("def": ContractGen's ctx
## "def"), "story" naming it; it never expires on the board. Done, its clue is found (its intel
## came out: the required objective is the intel); failed, aborted or lapsed, it comes back
## REOFFER_DAYS later. An act closes with its last contract; the next opens when it's built, the
## evidence reaches its "evidence" and its "needs_fob" is met (ZoneControl.home()). Read-only
## accessors work on clients too (the
## contracts' view carries the section, Contracts._public "story").

const SECTION := &"story"
## A story contract's "source" (ContractGen.generate, the board's tag).
const SOURCE := "story"
## Proposed (docs/story.md 4): ordinary intel turned in, this many pieces to an evidence point.
const SCRAPS_PER_EVIDENCE := 4
## Proposed: a Vantage ledger turned in is an evidence point, this many at most.
const LEDGER := "vantage_ledger"
const LEDGER_EVIDENCE_MAX := 3
## Proposed: a failed, aborted or lapsed story contract is offered again this many days later.
const REOFFER_DAYS := 1
## A story offer stays on the board this long (never runs out in practice).
const OFFER_DAYS := 9999
## The liaison, in the style of zone_control.gd's lines.
const LINE_EVIDENCE := "Radio, client liaison: That %s is worth something. Evidence on the board: %d."
const LINE_ACT_DONE_LHD := "Radio, client liaison: Act %d's closed, and the next leads run inland. We'll need ground of our own for that: take a zone for the FOB."
const LINE_ACT_OPEN := "Radio, client liaison: We're ashore, and the leads are waiting. %s."


# --- Data -----------------------------------------------------------------------------------

## data/contracts.json "story" ({} if none).
static func data() -> Dictionary:
	return MissionRegistry.data().get("story", {}) as Dictionary


## The acts: [{"act", "name", "summary", "built", "needs_fob", "evidence"}].
static func acts() -> Array:
	return data().get("acts", [])


static func act_def(act: int) -> Dictionary:
	for a: Dictionary in acts():
		if int(a.get("act", 0)) == act:
			return a
	return {}


## Story contract definitions, in order ("act", then "order").
static func contract_defs(act := 0) -> Array:
	var out: Array = (data().get("contracts", []) as Array).filter(func(d: Dictionary) -> bool: return act == 0 or int(d.get("act", 0)) == act)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return [int(a.get("act", 0)), int(a.get("order", 0))] < [int(b.get("act", 0)), int(b.get("order", 0))])
	return out


static func contract_def(id: String) -> Dictionary:
	for d: Dictionary in data().get("contracts", []):
		if String(d.get("id", "")) == id:
			return d
	return {}


## The faction arcs (data stubs): [{"id", "name", "faction", "tier", "summary", "built"}].
static func arcs() -> Array:
	return data().get("arcs", [])


# --- State ----------------------------------------------------------------------------------

static func _s() -> Dictionary:
	if _is_host():
		return Campaign.section(SECTION)
	return Contracts._view().get("story", {}) as Dictionary


static func _is_host() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return true
	var mp := tree.root.multiplayer
	return mp == null or not mp.has_multiplayer_peer() or mp.is_server()


static func act() -> int:
	return int(_s().get("act", 1))


static func evidence() -> int:
	return int(_s().get("evidence", 0))


static func clues() -> Array:
	return _s().get("clues", [])


static func has_clue(id: String) -> bool:
	return clues().any(func(k: Dictionary) -> bool: return String(k.get("id", "")) == id)


## The clue ids story contract `d` needs that aren't found yet.
static func missing_clues(d: Dictionary) -> Array:
	return (d.get("clues", []) as Array).filter(func(k: Variant) -> bool: return not has_clue(String(k)))


## What act `n` still waits for before it opens (words; [] when it can): its contracts written,
## the evidence count, a FOB ashore.
static func act_waits(n: int) -> PackedStringArray:
	var out := PackedStringArray()
	var a := act_def(n)
	if a.is_empty():
		return out
	if evidence() < int(a.get("evidence", 0)):
		out.append("evidence %d (have %d)" % [int(a.evidence), evidence()])
	if bool(a.get("needs_fob", false)) and ZoneControl.home_is_lhd():
		out.append("a FOB ashore")
	if not bool(a.get("built", false)):
		out.append("its contracts, still to be written")
	return out


static func is_done(id: String) -> bool:
	return id in (_s().get("done", []) as Array)


## The section as the contracts' view carries it to clients.
static func view() -> Dictionary:
	return Roster.json_safe(Campaign.section(SECTION).duplicate(true))


# --- Host -----------------------------------------------------------------------------------

## Host (BaseHub.new_campaign): the story starts at act 1; its first contracts go on the board.
static func server_start() -> void:
	var s := Campaign.section(SECTION)
	s.clear()
	_fill(s)
	server_update()


## Host (BaseHub.load_or_new): a loaded campaign. One saved before the story starts it now.
static func server_loaded() -> void:
	_fill(Campaign.section(SECTION))
	server_update()


static func _fill(s: Dictionary) -> void:
	for pair: Array in [["act", 1], ["evidence", 0], ["scraps", 0], ["ledgers", 0], ["clues", []], ["done", []], ["offered", {}],
			["back_day", {}], ["acts_done", []]]:
		if not s.has(pair[0]):
			s[pair[0]] = pair[1].duplicate() if pair[1] is Array or pair[1] is Dictionary else pair[1]


## Host: what the story offers now. The act moves on when it can (an act done, the next built and
## its "needs_fob" met); then each of this act's contracts not done and not on offer goes on the
## board once it's due (due). Returns the cids offered.
static func server_update() -> Array:
	var out: Array = []
	if not _is_host() or Campaign.section(SECTION).is_empty():
		return out
	var s := Campaign.section(SECTION)
	_advance_act(s)
	for d: Dictionary in contract_defs(int(s.act)):
		if due(d):
			var cid := server_offer(String(d.id))
			if cid != "":
				out.append(cid)
	return out


## Whether story contract `d` should go on the board now: not done, not on offer, those it
## comes after done, the clues it needs found, its come-back day passed, and not a stub.
static func due(d: Dictionary) -> bool:
	var s := _s()
	var id := String(d.get("id", ""))
	if bool(d.get("stub", false)) or is_done(id) or (s.get("offered", {}) as Dictionary).has(id):
		return false
	if int(d.get("act", 1)) != act() or not missing_clues(d).is_empty():
		return false
	if int((s.get("back_day", {}) as Dictionary).get(id, 0)) > Economy.day():
		return false
	return (d.get("after", []) as Array).all(func(a: Variant) -> bool: return is_done(String(a)))


## Host: story contract `id` on the board, the liaison saying so. Returns its cid ("" if it can't be made).
static func server_offer(id: String) -> String:
	var c := make_contract(id)
	if c.is_empty():
		return ""
	var cid := Contracts.server_add_offer(c)
	var s := Campaign.section(SECTION)
	(s.offered as Dictionary)[id] = cid
	(s.back_day as Dictionary).erase(id)
	_changed()
	SessionLog.note("story: %s offered (%s)" % [id, cid])
	var d := contract_def(id)
	if String(d.get("line_offer", "")) != "":
		Contracts._notify_all(String(d.line_offer))
	return cid


## Story contract `id` as an offer: its type generated with the definition's own objectives and
## brief ("def"), its employer and target, titled by its name; "story" names it. {} for an unknown id.
static func make_contract(id: String) -> Dictionary:
	var d := contract_def(id)
	if d.is_empty() or MissionRegistry.type_def(String(d.get("type", ""))).is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Contracts.campaign_seed(), id, Economy.day()])
	var over := {}
	for key: String in ["objectives", "leg_objectives", "modules", "leg_modules"]:
		if d.has(key):
			over[key] = (d[key] as Array).duplicate(true)
	var ctx := {"day": Economy.day(), "source": SOURCE, "type": String(d.type), "zone_kind": "contract", "def": over}
	for key: String in ["employer", "target", "zone_id"]:
		if String(d.get(key, "")) != "":
			ctx[key] = String(d[key])
	var c := ContractGen.generate(rng, ctx)
	var zones := String(c.get("zone_name", ""))
	for leg: Dictionary in c.get("legs", []):
		zones += " and " + String(leg.zone_name)
	c["title"] = "Story: %s (%s)" % [String(d.get("name", id)), zones]
	c["brief"] = String(d.get("brief", c.get("brief", "")))
	c["story"] = id
	c["expires_day"] = Economy.day() + OFFER_DAYS
	return c


## Host (Contracts.contract_closed): a story contract done finds its clue and moves the story on;
## failed, aborted, lapsed or let run out, it comes back REOFFER_DAYS later.
static func on_contract_closed(c: Dictionary, outcome: String) -> void:
	var id := String(c.get("story", ""))
	if id == "" or not _is_host():
		return
	var s := Campaign.section(SECTION)
	if s.is_empty():
		return
	(s.offered as Dictionary).erase(id)
	if outcome == "completed":
		server_complete(id)
	else:
		(s.back_day as Dictionary)[id] = Economy.day() + REOFFER_DAYS
		SessionLog.note("story: %s %s; back on day %d" % [id, outcome, int(s.back_day[id])])
		_changed()


## Host: story contract `id` done: its clue found, the liaison's line, the act closed when it was
## the last, and what's due next offered.
static func server_complete(id: String) -> void:
	var s := Campaign.section(SECTION)
	if id in (s.done as Array):
		return
	(s.done as Array).append(id)
	var d := contract_def(id)
	var clue: Dictionary = d.get("clue", {})
	if not clue.is_empty():
		server_add_clue(String(clue.get("id", id)), String(clue.get("text", "")), int(clue.get("evidence", 1)))
	if String(d.get("line_done", "")) != "":
		Contracts._notify_all(String(d.line_done))
	SessionLog.note("story: %s done (evidence %d)" % [id, int(s.evidence)])
	_changed()
	server_update()


## Host: a clue found (once per id): it goes on the clue board and adds `worth` to the evidence.
static func server_add_clue(id: String, text: String, worth := 1) -> bool:
	var s := Campaign.section(SECTION)
	if (s.clues as Array).any(func(k: Dictionary) -> bool: return String(k.id) == id):
		return false
	(s.clues as Array).append({"id": id, "text": text, "act": int(s.act), "day": Economy.day()})
	s.evidence = int(s.evidence) + worth
	_changed()
	return true


## Host (Contracts.server_turn_in_intel): intel turned in at a debrief. A Vantage ledger is an
## evidence point (up to LEDGER_EVIDENCE_MAX); other intel adds scraps, SCRAPS_PER_EVIDENCE to a
## point. Returns the evidence it added.
static func on_intel_turned_in(item_id: String, count: int) -> int:
	if not _is_host() or Campaign.section(SECTION).is_empty() or count <= 0:
		return 0
	var s := Campaign.section(SECTION)
	var added := 0
	if item_id == LEDGER:
		var room := maxi(LEDGER_EVIDENCE_MAX - int(s.ledgers), 0)
		added = mini(count, room)
		s.ledgers = int(s.ledgers) + added
	else:
		s.scraps = int(s.scraps) + count
		added = int(s.scraps) / SCRAPS_PER_EVIDENCE
		s.scraps = int(s.scraps) % SCRAPS_PER_EVIDENCE
	if added > 0:
		s.evidence = int(s.evidence) + added
		var item := ItemDB.get_item(StringName(item_id)) if ItemDB.has_item(StringName(item_id)) else null
		Contracts._notify_all(LINE_EVIDENCE % [item.name if item else "intel", int(s.evidence)])
		SessionLog.note("story: +%d evidence from %s (now %d)" % [added, item_id, int(s.evidence)])
	_changed()
	server_update()
	return added


## Host (Economy.day_advanced): failed story contracts come back; an act waiting on the FOB opens.
static func on_day_advanced(_today: int, _days: int) -> void:
	if _is_host() and BaseHub.started():
		server_update()


## Host: the act closes when all its built contracts are done; the next opens when nothing in
## act_waits holds it (built, its evidence count reached, the FOB if it "needs_fob").
static func _advance_act(s: Dictionary) -> void:
	var a := int(s.act)
	var mine := contract_defs(a).filter(func(d: Dictionary) -> bool: return not bool(d.get("stub", false)))
	if mine.is_empty() or not mine.all(func(d: Dictionary) -> bool: return String(d.id) in (s.done as Array)):
		return
	if not a in (s.acts_done as Array):
		(s.acts_done as Array).append(a)
		SessionLog.note("story: act %d done" % a)
		if ZoneControl.home_is_lhd():
			Contracts._notify_all(LINE_ACT_DONE_LHD % a)
		_changed()
	var next := act_def(a + 1)
	if next.is_empty() or not act_waits(a + 1).is_empty():
		return
	s.act = a + 1
	Contracts._notify_all(LINE_ACT_OPEN % String(next.get("name", "Act %d" % (a + 1))))
	_changed()


static func _changed() -> void:
	Campaign.mark_changed(SECTION)
	Contracts._commit()  # the contracts' view carries the section to clients


# --- The Leads text (the contract board) ---------------------------------------------------

## What the contract board's Leads section says: the act, the evidence, what the next story
## contract waits for, and every clue so far.
static func leads_text() -> String:
	var s := _s()
	if s.is_empty():
		return "No leads yet."
	var a := act()
	var lines := PackedStringArray()
	var ad := act_def(a)
	lines.append("Act %d: %s.   Evidence: %d" % [a, String(ad.get("name", "?")), evidence()])
	var waiting := ""
	for d: Dictionary in contract_defs(a):
		var id := String(d.id)
		if is_done(id):
			continue
		if (s.get("offered", {}) as Dictionary).has(id):
			waiting = "On the board: %s." % String(d.get("name", id))
		elif bool(d.get("stub", false)):
			waiting = "More to come."
		else:
			var need := PackedStringArray()
			for after: Variant in d.get("after", []):
				if not is_done(String(after)):
					need.append(String(contract_def(String(after)).get("name", after)))
			for k: Variant in missing_clues(d):
				need.append("the clue from %s" % _clue_source(String(k)))
			waiting = "Next: %s, once %s." % [String(d.get("name", id)), ", ".join(need)] if not need.is_empty() else "Next: %s." % String(d.get("name", id))
		break
	if waiting == "":
		var next := act_def(a + 1)
		if next.is_empty():
			waiting = "The trail goes cold here for now."
		else:
			waiting = "Act %d (%s) waits for %s." % [a + 1, String(next.get("name", "?")), ", ".join(act_waits(a + 1))]
	lines.append(waiting)
	var found := clues()
	if found.is_empty():
		lines.append("No clues yet: intel brought out and turned in opens leads.")
	for k: Dictionary in found:
		lines.append("- %s" % String(k.get("text", "")))
	return "\n".join(lines)


## The story contract whose clue `clue_id` is, by name (for the Leads).
static func _clue_source(clue_id: String) -> String:
	for d: Dictionary in data().get("contracts", []):
		if String((d.get("clue", {}) as Dictionary).get("id", "")) == clue_id:
			return String(d.get("name", d.get("id", clue_id)))
	return clue_id
