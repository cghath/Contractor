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
	{"phrases": ["return to formation", "regroup", "form up", "rally"], "keys": ["1", "1"]},
	{"phrases": ["move there", "move up", "move in", "go there"], "keys": ["1", "2"]},
	{"phrases": ["hold position", "hold", "stop", "halt"], "keys": ["1", "3"]},
	{"phrases": ["take cover"], "keys": ["1", "5"]},
	{"phrases": ["clear that building", "clear the building", "clear it"], "keys": ["1", "8", "1"]},
	{"phrases": ["breach and clear", "bang and clear", "flash and clear"], "keys": ["1", "8", "2"]},
	{"phrases": ["clear on me", "stack up on me", "stack on me", "on me"], "keys": ["1", "8", "7"]},
	{"phrases": ["fall back"], "keys": ["1", "6"]},
	{"phrases": ["target that", "engage that", "target enemy", "target him"], "keys": ["2", "1"]},
	{"phrases": ["no target", "target nothing", "disregard"], "keys": ["2", "2"]},
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


## Lowercase, trimmed, punctuation stripped, whitespace collapsed to single spaces.
static func normalize(text: String) -> String:
	var re := RegEx.new()
	re.compile("[^a-z0-9 ]")
	var cleaned := re.sub(text.strip_edges().to_lower(), "", true)
	return " ".join(cleaned.split(" ", false))
