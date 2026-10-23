class_name Income
extends RefCounted
## Ways for the company to make money that come out of what it already does (claude/income,
## 2026-10-22; Captain: "we need something that allows the players to make money... like good
## money but it needs to go with the flow of the game"; docs/income.md). Pure statics on the
## campaign's "income" section, like Heroes and WorldSites, so the host, the tests, the sim and
## the UI share one set of rules:
##
## 1. SideJobs: the high command squads take their own jobs from employers and fixers.
## 2. Bounties: captured vehicles and heavy weapons sold by standing, bounties on the living war's
##    leaders, intel sold to the buyer of your choice.
## 3. FobBusiness: businesses run from a FOB the company holds, paying daily.
## 4. BlackMarket: goods bought low and sold high between regions and fixers.
##
## The host runs the daily tick (server_advance_days, from Economy.advance_days after the war's
## own tick) and the requests (server_request, from BaseHub's "income" request: any peer may
## ask; the money decisions are the host's). Economy._public carries the section to every peer
## (view()). Every number is in data/income.json and Proposed.

const SECTION := &"income"
const PATH := "res://data/income.json"
## Ledger lines start with these (Economy.ledger_kind sorts them for the books).
const LEDGER_SIDE_JOB := "Side job"  # (Bounties: "Capture sold", "Bounty")
const REPORTS_KEEP := 12

static var _data: Dictionary = {}
## Whether the income streams run (the economy sim's --income 0 turns them off for its "before":
## no side jobs or businesses move, no bounties paid, intel at its plain worth).
static var enabled := true


static func data() -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Income: cannot read %s" % PATH)
			return {}
		_data = parsed
	return _data


## A number from data/income.json's `group` ({} or `default` when missing).
static func num(group: String, key: String, default := 0.0) -> float:
	return float((data().get(group, {}) as Dictionary).get(key, default))


## The host's section, or a client's copy of it (from Economy's last sync).
static func view() -> Dictionary:
	if _is_host():
		return state()
	return (Economy._remote.get(String(SECTION), {}) as Dictionary)


static func state() -> Dictionary:
	var s := Campaign.section(SECTION)
	if not s.has("jobs"):
		s.merge({"offers": [], "jobs": [], "reports": [], "morale": {}, "next_id": 1, "offers_day": -1}, false)
	return s


static func _is_host() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return true
	var mp := tree.root.multiplayer
	return not mp.has_multiplayer_peer() or mp.is_server()


static func next_id(prefix: String) -> String:
	var s := state()
	var n := int(s.get("next_id", 1))
	s["next_id"] = n + 1
	return "%s%d" % [prefix, n]


## A roll that's the same every time for this campaign, day and key (like the war's).
static func rng(day: int, key: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d:%d:%s" % [Contracts.campaign_seed(), day, key])
	return r


## How dangerous `zone_id` is for work done there now, 0..1 (data "danger"): who holds it in the
## living war and how strong they are, a front there, how firm a friendly hold is.
static func zone_danger(zone_id: String) -> float:
	var d: Dictionary = data().get("danger", {})
	var h := WorldSites.holder_now(zone_id) if WorldSites.is_war_zone(zone_id) else ""
	var out := float(d.get("hostile", 0.45))
	var friendly := false
	if h == ZoneControl.PLAYER or h == WorldSites.REBELS:
		out = float(d.get("company", 0.12))
		friendly = true
	elif h != "" and h in MissionRegistry.employers() and Economy.tier(h) >= MissionRegistry.neutral_tier():
		out = float(d.get("friendly", 0.22))
		friendly = true
	elif h != "":
		out += WorldSites.strength(h) / float(d.get("strength_div", 250.0))
	if not WorldSites.front(zone_id).is_empty() and WorldSites.is_war_zone(zone_id):
		out += float(d.get("front", 0.25))
	elif friendly:
		out -= float(d.get("grip_calm", 0.2)) * (WorldSites.grip(zone_id) - 0.5)
	return clampf(out, 0.05, 1.0)


## A reading of danger for the screen: "Low", "Moderate", "High", "Severe".
static func danger_word(danger: float) -> String:
	if danger < 0.25:
		return "Low"
	if danger < 0.45:
		return "Moderate"
	if danger < 0.7:
		return "High"
	return "Severe"


## Host: a report on the company net and in the side work page's cards: {"day", "title", "text",
## "kind" (good/bad/neutral), "lines": [[what, amount]]}.
static func report(title: String, text: String, kind := "neutral", lines: Array = []) -> void:
	var reports: Array = state().reports
	reports.append({"day": Economy.day(), "title": title, "text": text, "kind": kind, "lines": lines})
	while reports.size() > REPORTS_KEEP:
		reports.pop_front()
	Contracts._notify_all("%s: %s" % [title, text])
	Campaign.mark_changed(SECTION)


# --- Host: the day and the requests ---------------------------------------------------------

## Host (Economy.advance_days): each day that passed, every income stream moves on.
static func server_advance_days(days: int) -> void:
	if Campaign.section(&"economy").is_empty() or not enabled:
		return
	SideJobs.server_day(days)
	FobBusiness.server_day(days)
	BlackMarket.server_day(days)
	Campaign.mark_changed(SECTION)


## Host (BaseHub "income" request): `op` and its `args` from `sender`. Returns the note for the
## asker ("" for done, else why not).
static func server_request(op: String, args: Array, sender: int) -> String:
	var host_only := op in ["job_send", "capture_sell", "capture_deliver", "biz_open", "biz_close", "trade_buy", "trade_sell"]
	if host_only and sender != 1:
		return "Only the host can do that"
	var why := "Unknown request"
	match op:
		"job_send":
			why = SideJobs.server_send(String(args[0]) if args.size() > 0 else "", String(args[1]) if args.size() > 1 else "")
		"capture_sell":
			why = Bounties.server_sell_capture(int(args[0]), String(args[1])) if args.size() >= 2 else "Bad request"
		"biz_open":
			why = FobBusiness.server_open(String(args[0])) if not args.is_empty() else "Bad request"
		"biz_close":
			why = FobBusiness.server_close(String(args[0])) if not args.is_empty() else "Bad request"
		"trade_buy":
			why = BlackMarket.server_buy(String(args[0]), String(args[1]), int(args[2])) if args.size() >= 3 else "Bad request"
		"trade_sell":
			why = BlackMarket.server_sell(String(args[0]), String(args[1]), int(args[2])) if args.size() >= 3 else "Bad request"
		"capture_deliver":
			why = Bounties.server_deliver(int(args[0]), String(args[1]), String(args[2])) if args.size() >= 3 else "Bad request"
	Campaign.mark_changed(SECTION)
	return why
