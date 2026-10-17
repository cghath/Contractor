class_name VoiceQuestions
## The bounded vocabulary for asking a friendly or civilian a question.
##
## Matched the same way VoiceCommands matches squad orders: an exact phrase in a bounded
## list, nothing generative. VoiceOrder only tries these when a living friendly or civilian
## is under the crosshair (see VoiceOrder.run) - looking at someone and holding T is how you
## ask them something, as opposed to giving the selected squad an order. Each question reads
## the target's own live state (VoiceOrder._answer_text), so the answer is never a canned
## line - it's wrong, outdated or empty exactly when the target's own data would be.

const VOCAB: Array[Dictionary] = [
	{"phrases": ["how much ammo do you have", "hows your ammo", "ammo check", "whats your ammo",
		"you got ammo", "you got any ammo", "how much ammo you got"], "id": &"ammo"},
	{"phrases": ["whats your status", "how are you", "you okay", "you alright", "you good",
		"report your status"], "id": &"status"},
	{"phrases": ["where are the enemies", "see anything", "spotted anything", "anything to report",
		"any contacts", "you see any enemies"], "id": &"contact"},
]


## The question id a recognized phrase asks, or &"" if nothing in the vocabulary matches.
static func resolve(text: String) -> StringName:
	var norm := VoiceCommands.normalize(text)
	if norm == "":
		return &""
	for entry: Dictionary in VOCAB:
		if norm in (entry["phrases"] as Array):
			return entry["id"]
	return &""
