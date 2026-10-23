class_name VoiceCommands
## The bounded vocabulary for spoken squad orders.
##
## Every phrase maps onto the exact key sequence a player would press on the keyboard: an
## F-key or ` to select, then the command menu's own 1-9/0 (CommandMenu.MENU) or Backspace.
## A recognized phrase can't do anything a keyboard order couldn't already do - this is
## phrase-matching onto existing commands, not a new way to command the squad. Add a new
## order here only once it exists in CommandMenu.MENU.
##
## Covers the core orders (movement, targeting, fire control, status, mode, formation) plus a
## few simple one-key Action entries (heal up). Deliberately left out of this bounded set:
## anything needing a squadmate or an HVT under the crosshair (treat, escort), the Gear and
## Casualties submenus, Mount, Team reassignment, breaching (Clear), and the Support menus
## (map-marker dependent) - each is a straightforward addition here once there's a phrase for
## it, they just weren't in the brief's example list.
##
## 2026-10-22 (claude/voice-economy): more of the menu (follow, bound, garrison, clear the town,
## flank, assault, suppress, watch, stance, mount up), an addressee before the order ("Bravo,
## hold position", "everyone fall back": parse), confirmation lines (ACKS, said by the one who
## got the order), and the high command squads by callsign ("Hawk two, move there on alpha":
## HC_VOCAB, HcOrder verbs) plus the go codes ("alpha go", "execute h hour": go_code).

const VOCAB: Array[Dictionary] = [
	{"phrases": ["select one", "one"], "keys": ["F1"]},
	{"phrases": ["select two", "two"], "keys": ["F2"]},
	{"phrases": ["select three", "three"], "keys": ["F3"]},
	{"phrases": ["select four", "four"], "keys": ["F4"]},
	{"phrases": ["select five", "five"], "keys": ["F5"]},
	{"phrases": ["select six", "six"], "keys": ["F6"]},
	{"phrases": ["select seven", "seven"], "keys": ["F7"]},
	{"phrases": ["select eight", "eight"], "keys": ["F8"]},
	{"phrases": ["select all", "all", "everyone", "whole squad"], "keys": ["`"]},
	{"phrases": ["return to formation", "regroup", "form up", "rally", "follow me", "follow", "come with me"], "keys": ["1", "1"]},
	{"phrases": ["move there", "move up", "move in", "go there", "move here", "move"], "keys": ["1", "2"]},
	{"phrases": ["bound there", "bound up", "bounding", "bound"], "keys": ["1", "4"]},
	{"phrases": ["garrison that building", "garrison that", "garrison", "occupy that building"], "keys": ["1", "7"]},
	{"phrases": ["clear the town", "clear that town", "clear the village"], "keys": ["1", "8", "5"]},
	{"phrases": ["flank there", "flank that", "flank left", "flank right"], "keys": ["1", "0", "1"]},
	{"phrases": ["flank them", "flank the enemy", "flank known enemy"], "keys": ["1", "0", "2"]},
	{"phrases": ["assault there", "assault that", "attack there"], "keys": ["1", "0", "3"]},
	{"phrases": ["assault them", "assault the enemy", "assault known enemy", "attack them"], "keys": ["1", "0", "4"]},
	{"phrases": ["hold position", "hold", "stop", "halt"], "keys": ["1", "3"]},
	{"phrases": ["take cover"], "keys": ["1", "5"]},
	{"phrases": ["clear that building", "clear the building", "clear it"], "keys": ["1", "8", "1"]},
	{"phrases": ["breach and clear", "bang and clear", "flash and clear"], "keys": ["1", "8", "2"]},
	{"phrases": ["clear on me", "stack up on me", "stack on me", "on me"], "keys": ["1", "8", "7"]},
	{"phrases": ["charge and clear", "blow the wall", "blow a way in"], "keys": ["1", "8", "4"]},
	{"phrases": ["kick it in", "kick the door", "kick and clear"], "keys": ["1", "8", "8"]},
	{"phrases": ["shotgun the door", "shotgun breach", "breach the hinges"], "keys": ["1", "8", "9"]},
	{"phrases": ["clear it quietly", "quiet entry", "ease it open"], "keys": ["1", "8", "0"]},
	{"phrases": ["make breacher", "be the breacher", "assign breacher"], "keys": ["9", "6", "1"]},
	{"phrases": ["fall back"], "keys": ["1", "6"]},
	{"phrases": ["target that", "engage that", "target enemy", "target him"], "keys": ["2", "1"]},
	{"phrases": ["no target", "target nothing", "disregard"], "keys": ["2", "2"]},
	{"phrases": ["suppress there", "suppress that", "suppressing fire there", "lay down fire there"], "keys": ["2", "3"]},
	{"phrases": ["suppress them", "suppress", "suppressing fire", "lay down fire", "suppress known enemy"], "keys": ["2", "4"]},
	{"phrases": ["watch there", "watch that sector", "eyes there", "watch that"], "keys": ["2", "5"]},
	{"phrases": ["stand up", "get up", "on your feet"], "keys": ["3", "3", "1"]},
	{"phrases": ["crouch", "get low", "stay low"], "keys": ["3", "3", "2"]},
	{"phrases": ["go prone", "get down", "hit the dirt"], "keys": ["3", "3", "3"]},
	{"phrases": ["your choice", "stance auto", "pick your stance"], "keys": ["3", "3", "4"]},
	{"phrases": ["mount up", "get in", "load up"], "keys": ["4", "5"]},
	{"phrases": ["get out", "dismount", "everybody out"], "keys": ["4", "2"]},
	{"phrases": ["open fire", "weapons free"], "keys": ["3", "1"]},
	{"phrases": ["hold fire", "cease fire", "weapons hold"], "keys": ["3", "2"]},
	{"phrases": ["report status", "report", "sitrep", "status report"], "keys": ["5", "1"]},
	{"phrases": ["report enemy position", "spot report", "radio report"], "keys": ["5", "2"]},
	{"phrases": ["throw smoke", "smoke there", "pop smoke"], "keys": ["6", "1"]},
	{"phrases": ["throw frag", "frag out", "throw grenade", "grenade there"], "keys": ["6", "2"]},
	{"phrases": ["heal up", "treat yourself"], "keys": ["6", "5"]},
	{"phrases": ["medic", "i need a medic", "patch me up", "call a medic"], "keys": ["5", "3"]},
	{"phrases": ["go safe", "safe mode"], "keys": ["7", "1"]},
	{"phrases": ["go aware", "aware mode"], "keys": ["7", "2"]},
	{"phrases": ["go combat", "combat mode"], "keys": ["7", "3"]},
	{"phrases": ["go stealth", "stealth mode"], "keys": ["7", "4"]},
	{"phrases": ["wedge up", "wedge formation", "form wedge"], "keys": ["8", "1"]},
	{"phrases": ["file formation", "form file", "single file"], "keys": ["8", "2"]},
	{"phrases": ["line formation", "form line", "line up"], "keys": ["8", "3"]},
	{"phrases": ["staggered column", "form staggered"], "keys": ["8", "4"]},
	{"phrases": ["column formation", "form column"], "keys": ["8", "5"]},
	{"phrases": ["dynamic formation", "formation dynamic"], "keys": ["8", "6"]},
	{"phrases": ["cancel", "back", "nevermind", "belay that"], "keys": ["Backspace"]},
]


## Confirmation lines (said by the one given the order, Callouts.ack; voiced as ack_<what>):
## [key prefix, what, line]. The first whose keys start the order's wins; none: no reply (the
## menu's own replies, Status, formation's "Copy, wedge", are said by the squad already).
const ACKS: Array = [
	[["1", "1"], "follow", "On you."],
	[["1", "2"], "move", "Moving."],
	[["1", "3"], "hold", "Holding."],
	[["1", "4"], "bound", "Bounding."],
	[["1", "5"], "cover", "Taking cover."],
	[["1", "6"], "fall_back", "Falling back!"],
	[["1", "7"], "garrison", "Moving to garrison."],
	[["1", "8"], "clear", "Stacking up."],
	[["1", "0"], "attack", "Moving."],
	[["2", "1"], "target", "Target."],
	[["2", "3"], "suppress", "Suppressing!"],
	[["2", "4"], "suppress", "Suppressing!"],
	[["2", "5"], "watch", "Watching."],
	[["3", "1"], "fire", "Weapons free."],
	[["3", "2"], "hold_fire", "Holding fire."],
	[["4", "5"], "mount", "Mounting up."],
	[["4", "2"], "dismount", "Getting out."],
	[["6", "1"], "smoke", "Smoke, wilco."],
	[["6", "2"], "frag", "Frag, wilco."],
]
## Who an order can be addressed to besides a squadmate's callsign: the whole squad.
const EVERYONE: Array[String] = ["everyone", "everybody", "all", "squad", "team", "all units", "whole squad"]
## High command squads' orders by voice (HcOrder verbs; POINTED ones take the crosshair's point).
const HC_VOCAB: Array[Dictionary] = [
	{"phrases": ["move there", "move here", "move up", "go there", "move"], "verb": "move"},
	{"phrases": ["hold", "hold position", "stop", "halt", "hold there"], "verb": "hold"},
	{"phrases": ["defend there", "defend here", "defend", "hold that ground"], "verb": "defend"},
	{"phrases": ["follow me", "follow", "on me", "come to me"], "verb": "follow"},
	{"phrases": ["regroup", "rally", "regroup there", "form up"], "verb": "regroup"},
	{"phrases": ["extract", "extract there", "head for extraction", "exfil"], "verb": "extract"},
	{"phrases": ["attack there", "assault there", "attack", "assault", "clear there", "clear it"], "verb": "attack"},
	{"phrases": ["suppress there", "suppress", "base of fire", "support by fire", "suppressing fire"], "verb": "sbf"},
	{"phrases": ["bound there", "bound up", "bound"], "verb": "bound"},
	{"phrases": ["fall back", "fall back there", "pull back"], "verb": "fall_back"},
	{"phrases": ["report", "sitrep", "status", "report status"], "verb": "report"},
]
## Go codes as said (HcOrder.GO_CODES: alpha, bravo, charlie, hhour).
const GO_WORDS := {"alpha": "alpha", "bravo": "bravo", "charlie": "charlie", "h hour": "hhour", "hhour": "hhour"}
const DIGIT_WORDS: Array[String] = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]


## The key sequence a recognized phrase maps to, or [] if nothing in the vocabulary matches.
static func resolve(text: String) -> Array[String]:
	var norm := normalize(text)
	if norm == "":
		return []
	for entry: Dictionary in VOCAB:
		if norm in (entry["phrases"] as Array):
			var keys: Array[String] = []
			keys.assign(entry["keys"])
			return keys
	return []


## The confirmation [what, line] for an order's keys (ACKS), or [] for none.
static func ack_for(keys: Array) -> Array:
	for a: Array in ACKS:
		var prefix: Array = a[0]
		if keys.size() >= prefix.size() and keys.slice(0, prefix.size()) == prefix:
			return [a[1], a[2]]
	return []


## A callsign as spoken: normalized, every digit its word ("Hawk 2" -> "hawk two").
static func spoken(callsign: String) -> String:
	var words := PackedStringArray()
	for w in normalize(callsign).split(" ", false):
		if w.is_valid_int():
			for d in w:
				words.append(DIGIT_WORDS[int(d)])
		else:
			words.append(w)
	return " ".join(words)


## Splits who an order is for off its front: `names` maps each addressee as spoken (spoken())
## to what the caller makes of it. {"to": that value, "rest": the order} for the longest match
## followed by an order, else {"to": null, "rest": the whole text}.
static func split_addressee(text: String, names: Dictionary) -> Dictionary:
	var norm := spoken(text)
	var best := ""
	for n: String in names:
		if (norm.begins_with(n + " ") or norm == n) and n.length() > best.length():
			best = n
	if best == "" or norm == best:
		return {"to": null, "rest": norm}
	return {"to": names[best], "rest": norm.substr(best.length() + 1)}


## A high command order said to a squad: {"verb", "go"} (go "" or an HcOrder go code from a
## trailing "on alpha"), or {} when `rest` is no HC order.
static func hc_order(rest: String) -> Dictionary:
	var norm := normalize(rest)
	var go := ""
	for w: String in GO_WORDS:
		if norm.ends_with(" on " + w):
			go = GO_WORDS[w]
			norm = norm.trim_suffix(" on " + w)
	for entry: Dictionary in HC_VOCAB:
		if norm in (entry["phrases"] as Array):
			return {"verb": String(entry.verb), "go": go}
	return {}


## The go code a phrase gives ("alpha go", "go alpha", "execute h hour", "go code bravo"), or "".
static func go_code(text: String) -> String:
	var norm := normalize(text)
	for w: String in GO_WORDS:
		if norm in ["%s go" % w, "go %s" % w, "execute %s" % w, "go code %s" % w, "%s execute" % w, "go on %s" % w]:
			return GO_WORDS[w]
	return ""


## Lowercase, trimmed, punctuation stripped, whitespace collapsed to single spaces.
static func normalize(text: String) -> String:
	var re := RegEx.new()
	re.compile("[^a-z0-9 ]")
	var cleaned := re.sub(text.strip_edges().to_lower(), "", true)
	return " ".join(cleaned.split(" ", false))
