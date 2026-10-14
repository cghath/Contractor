class_name SquadComms
extends RefCounted
## What the friendly squad says to its players, and when (Captain, 2026-10-14: "bots should
## act like players, communicate with the player"; docs/squad_comms.md). Host only: the
## friendly Squad owns one (Squad.comms, made by of()) and runs it from its physics step
## (step()). Callouts delivers the lines (priorities, the side's budget, each listener's own
## wording of a place, subtitles); this decides what to say, from what the squadmates are
## actually doing (SquadAI.intent, care, status_text), so it never says something the AI
## isn't doing. It only reads SquadAI state: nobody acts differently because of it.
## - Every order gets an answer (heard_order, from Soldier._server_squad_command), judged
##   ANSWER_DELAY_S after it, once the squadmates have thought about it (on_order and
##   give_tactic make them think at once). One of those who comply acknowledges for them all
##   (the team leader first: "Copy, holding"); each who can't says why, to the player who gave
##   it ("Can't, carrying Miller's body", "Treating Miller first"), at most MAX_REFUSALS of
##   them. After a move, bound, take cover, fall back or garrison he says "In position" once
##   they're all there. An order that couldn't be given at all ("Look at a body") is said in
##   a squadmate's own words ("No body there"). Throws, launchers and supports answer for
##   themselves ("Frag out!", "Backblast clear!", the helicopter's radio).
## - Status? (Status > Report status): each selected squadmate answers the player who asked,
##   one after the other: what he is doing, his ammunition, medical items he's out of, how he
##   is, and where he is when more than STATUS_FAR_M from the asker.
## - Unprompted, every THINK_S, from what changed since the last look: pinned down, hit,
##   ammunition and medical items running out, falling behind, stuck (a session-log anomaly
##   too, so a bug stays a bug), a move away from the squad explained
##   ("Going for Miller's body"), and giving up on a casualty he can't reach.

## How often the unprompted moments are looked at.
const THINK_S := 0.5
## An order's answer is judged this long after it (more than SquadAI.THINK_S: the squadmates
## have thought about it by then).
const ANSWER_DELAY_S := 0.6
## Status replies come one this long after the other.
const STATUS_GAP_S := 0.7
## At most this many squadmates say why they can't; the acknowledgement counts the rest.
const MAX_REFUSALS := 2
## Proposed: a squadmate following more than SEPARATED_M from the lead for SEPARATED_S says
## so, again after SEPARATED_REPEAT_S or once twice as far.
const SEPARATED_M := 100.0
const SEPARATED_S := 8.0
const SEPARATED_REPEAT_S := 60.0
## Proposed: out of contact, more than STUCK_FAR_M from where he's going and less than
## STUCK_MOVED_M moved in STUCK_S: stuck (again after STUCK_REPEAT_S).
const STUCK_FAR_M := 15.0
const STUCK_MOVED_M := 2.0
const STUCK_S := 10.0
const STUCK_REPEAT_S := 60.0
## No explaining a move this soon after an order to him (the answer said it).
const EXPLAIN_AFTER_ORDER_S := 3.0
## Going to a body to scavenge is explained only when it's further than this.
const SCAVENGE_EXPLAIN_M := 15.0
## "Can't reach Miller" at most this often per casualty.
const GIVE_UP_REPEAT_S := 20.0
## Pinned (SquadAI.PINNED) this long: "I'm pinned!", again after PINNED_REPEAT_S.
const PINNED_FOR_S := 1.5
const PINNED_REPEAT_S := 15.0
## A new hit (a wound or a round armor stopped) is called within HIT_FRESH_S, at most every
## HIT_REPEAT_S; Vitals.injury() from HIT_BAD up is "I'm hit!". Not a rise in injury: that
## includes blood lost, which rises on its own while he bleeds.
const HIT_FRESH_S := 2.0
const HIT_REPEAT_S := 10.0
const HIT_BAD := 0.35
## Ammunition and medical items are checked this often; each level is said at most every
## AMMO_REPEAT_S (an item run out, MEDS_REPEAT_S), and again after a restock.
const SUPPLY_EVERY_S := 3.0
const AMMO_REPEAT_S := 90.0
const MEDS_REPEAT_S := 180.0
## Spare magazines for the primary weapon at or under this: low on ammunition.
const LOW_MAGS := 2
## Status replies say where he is from this far from the asker.
const STATUS_FAR_M := 40.0
## "In position" is waited for this long at most.
const ARRIVAL_WATCH_S := 90.0
## Within this (flat) of the move point: there.
const ARRIVED_M := 1.5
## What a squadmate says when he complies, by command (all the answers in one place, for
## voice recording later).
const ACK_LINES := {
	"follow": "Copy, on you", "hold": "Copy, holding", "move": "Moving", "bound": "Bounding up",
	"take_cover": "Taking cover", "fall_back": "Falling back", "garrison": "Taking the building",
	"clear": "Stacking up", "suppress": "Suppressing!", "watch": "Watching that sector",
	"open_fire": "Weapons free", "hold_fire": "Holding fire", "heal": "Patching up",
	"give_ammo": "Bringing you ammo", "ccp": "Bringing casualties there", "ccp_me": "Bringing them to you",
	"drop_packs": "Packs off", "pick_packs": "Getting packs", "scavenge": "Rearming from the body",
	"scavenge_on": "Copy, scavenging", "scavenge_off": "Copy, leaving the bodies", "mount": "Mounting up",
	"dismount": "Getting out", "launcher_out": "Launcher up", "stance": "Copy", "mode": "Copy", "team": "Copy",
}
## An order that couldn't be given (Squad.order_command's reason, shown to the player) as a
## squadmate says it; "" (or missing): he says nothing.
const VOICE_WHY := {
	"Look at a body": "No body there",
	"Nothing left on that body": "Nothing left on him",
	"That's a player's gear: leave it for them": "That's a player's kit, leaving it",
	"Look at a building": "No building there",
	"No way in found": "Can't find a way in",
	"No known enemy to suppress": "No known enemy",
	"Nobody selected has wounds they can treat": "Nothing to patch up",
	"Nobody selected has a launcher": "No launcher",
	"Nobody selected wears a pack": "No pack on",
	"Nobody selected dropped a pack": "Pack's still on",
	"Nobody selected has one": "Don't have one",
	"Nobody selected has a loaded launcher or rounds": "No rockets",
	"Can't target that": "No visual",
	"Can't escort that": "Can't get to him",
}
## Commands answered by what they do ("Frag out!", "Backblast clear!", the helicopter's radio,
## the radio report), not by a "Copy".
const SILENT: Array[String] = ["throw_smoke", "throw_frag", "fire_launcher", "radio_report", "support"]
## The tactic order kind (SquadAI.ordered) each command gives.
const TACTIC_KINDS := {"suppress": &"suppress", "watch": &"watch", "bound": &"bound", "take_cover": &"cover",
	"fall_back": &"break", "garrison": &"garrison", "clear": &"clear", "give_ammo": &"give_ammo", "pick_packs": &"pick_pack"}
## Commands whose acknowledging squadmate reports "In position" once they're all there.
const ARRIVE_COMMANDS: Array[String] = ["move", "bound", "take_cover", "fall_back", "garrison"]
## Callout ids by ammunition level (ammo_level).
const AMMO_IDS: Array[StringName] = [&"", &"low_ammo", &"last_mag", &"out_of_ammo"]
## How a squadmate says a medical item he's out of.
const MED_WORDS := {&"tourniquet": "tourniquets", &"hemostatic_gauze": "gauze", &"chest_seal": "chest seals",
	&"pressure_bandage": "bandages", &"decompression_needle": "needles"}

var squad: Squad
## Tests: nothing is said while paused (orders aren't answered either).
var paused := false
var _think_cd := 0.0
var _supply_cd := 0.0
var _units := {}  # SquadAI instance id -> what it was doing at the last look (_fresh)
var _answers: Array[Dictionary] = []  # orders waiting to be answered (heard_order)
var _arrivals: Array[Dictionary] = []  # "In position" to say once they're there


func _init(p_squad: Squad) -> void:
	squad = p_squad


## The squad's comms (made on first use): host only, the friendly squad only; null otherwise.
static func of(s: Squad) -> SquadComms:
	if s == null or s.faction != &"friendly" or not s.is_inside_tree() or not s.multiplayer.is_server():
		return null
	if s.comms == null:
		s.comms = SquadComms.new(s)
	return s.comms


## Host: the squad's physics step (Squad._physics_process).
static func step(s: Squad, delta: float) -> void:
	var comms := of(s)
	if comms:
		comms._step(delta)


## Host: `from` gave squad command `cmd` to the named units (Soldier._server_squad_command,
## after carrying it out); `why` is why it couldn't be given ("" if it was).
static func heard(s: Squad, from: Soldier, cmd: String, names: PackedStringArray, why: String) -> void:
	var comms := of(s)
	if comms:
		comms.heard_order(from, cmd, names, why)


func _step(delta: float) -> void:
	if paused:
		return
	var started := Time.get_ticks_usec()
	var now := Soldier._now()
	if not _answers.is_empty():
		_answer_due(now)
	_think_cd -= delta
	if _think_cd <= 0.0:
		_think_cd = THINK_S
		think(now)
	FrameCost.spent(&"comms", started)


# --- Orders -------------------------------------------------------------------------------

## Host: an order was given (see heard()). Status > Report status ("report") is answered by
## status_reply; the rest are answered ANSWER_DELAY_S later (_answer).
func heard_order(from: Soldier, cmd: String, names: PackedStringArray, why: String) -> void:
	if from == null or not is_instance_valid(from):
		return
	var now := Soldier._now()
	var parts := cmd.split(":", true, 1)
	var base := parts[0]
	var arg := parts[1] if parts.size() > 1 else ""
	if base == "report":
		status_reply(from, names)
		return
	var units := _able(names)
	for ai in units:
		_unit(ai, now).order_at = now
	for i in range(_arrivals.size() - 1, -1, -1):  # a new order ends the "In position" watch for those it went to
		if (_arrivals[i].units as Array).any(func(ai: SquadAI) -> bool: return ai in units):
			_arrivals.remove_at(i)
	if base in SILENT and why == "":
		return
	_answers.append({"peer": from.owner_peer(), "cmd": cmd, "base": base, "arg": arg, "why": why,
		"units": units if why != "" else _took(units, base, arg, now), "at": now + ANSWER_DELAY_S, "given": now})


## The named units' brains (all for none named) that can answer: AI, thinking, up.
func _able(names: PackedStringArray) -> Array[SquadAI]:
	var out: Array[SquadAI] = []
	for s in squad.pick(names):
		var ai := SquadAI.of(s)
		if ai and ai._ready_done and s.vitals.is_up():
			out.append(ai)
	return out


## Of `units`, those the order actually went to (some commands pick one or a few: the nearest
## with ammunition, the medic for a casualty, those with wounds or a pack).
static func _took(units: Array[SquadAI], base: String, arg: String, now: float) -> Array[SquadAI]:
	var out: Array[SquadAI] = []
	for ai in units:
		var took := true
		match base:
			"give_ammo", "pick_packs":
				took = StringName(ai.ordered.get("kind", &"")) == TACTIC_KINDS[base] and float(ai.ordered.get("since", -1000.0)) >= now - 0.01
			"treat":
				took = is_instance_valid(ai.casualty) and String(ai.casualty.name) == arg
			"scavenge":
				took = ai.scavenge_order != null
			"heal":
				took = ai._heal_until > now
			"drop_packs":
				took = not ai.dropped_pack.is_empty()
			"escort":
				took = arg == "" or (is_instance_valid(ai.escorting) and String(ai.escorting.name) == arg)
		if took:
			out.append(ai)
	return out


func _answer_due(now: float) -> void:
	var callouts := Callouts.of(squad)
	for i in range(_answers.size() - 1, -1, -1):
		var a: Dictionary = _answers[i]
		if now < float(a.at):
			continue
		_answers.remove_at(i)
		if callouts:
			_answer(a, callouts, now)


## Answers order `a` (heard_order) from what its units are doing now.
func _answer(a: Dictionary, callouts: Callouts, now: float) -> void:
	var units: Array[SquadAI] = []
	for ai: SquadAI in a.units:
		if is_instance_valid(ai) and ai.body and is_instance_valid(ai.body) and ai.body.vitals.is_up():
			units.append(ai)
	if units.is_empty():
		return
	var to := PackedInt32Array([int(a.peer)])
	var key := "%s/%d" % [a.cmd, int(float(a.given) * 1000.0)]  # every order its own answer (no repeat gate)
	if a.why != "":
		var voice := refusal_voice(a.why)
		if voice != "":
			callouts.say(units[0].body, &"refuse", voice, "refuse/" + key, "", 0.0, {"to": to})
		return
	var ok: Array[SquadAI] = []
	var not_ok: Array[Dictionary] = []
	for ai in units:
		var r := complies(ai, a.base, a.arg)
		if r.is_empty():
			ok.append(ai)
		else:
			r.ai = ai
			not_ok.append(r)
	var acker := acker_of(ok)
	if acker:
		var line := ack_line(acker, a.base, a.arg)
		if not_ok.size() > MAX_REFUSALS:
			line += " (%d more busy)" % (not_ok.size() - MAX_REFUSALS)
		callouts.say(acker.body, &"ack", line, "ack/" + key)
		if a.base in ARRIVE_COMMANDS:
			_arrivals.append({"speaker": acker, "units": ok, "base": a.base, "given": float(a.given), "until": now + ARRIVAL_WATCH_S})
	for i in mini(not_ok.size(), MAX_REFUSALS):
		var r: Dictionary = not_ok[i]
		callouts.say((r.ai as SquadAI).body, r.id, r.text, "%s/%s" % [r.id, key], "", 0.0, {"to": to})


## Whether `ai` does what command `base` (`arg`) asked, judged from what it is doing now: {}
## if it does, else what it says instead (reason()).
static func complies(ai: SquadAI, base: String, arg: String) -> Dictionary:
	var ok := true
	match base:
		"follow":
			ok = ai.order == Squad.Order.FOLLOW and ai.intent in [SquadAI.Intent.FOLLOW, SquadAI.Intent.FIGHT, SquadAI.Intent.TACTIC, SquadAI.Intent.RELOAD]
		"hold":
			ok = ai.order == Squad.Order.HOLD and ai.intent in [SquadAI.Intent.HOLD, SquadAI.Intent.FIGHT, SquadAI.Intent.RELOAD]
		"move":
			ok = ai.order == Squad.Order.MOVE and (ai.intent in [SquadAI.Intent.MOVE_TO, SquadAI.Intent.FIGHT, SquadAI.Intent.RELOAD]
				or (ai.intent == SquadAI.Intent.CASUALTY and ai.care == SquadAI.Care.CARRY and ai.body.carrying == ai.casualty))
		"suppress", "watch":
			ok = StringName(ai.ordered.get("kind", &"")) == TACTIC_KINDS[base] and ai.intent in [SquadAI.Intent.FOLLOW, SquadAI.Intent.HOLD, SquadAI.Intent.MOVE_TO, SquadAI.Intent.FIGHT, SquadAI.Intent.RELOAD, SquadAI.Intent.TACTIC]
		"bound", "take_cover", "fall_back", "garrison", "clear", "give_ammo", "pick_packs":
			if StringName(ai.ordered.get("kind", &"")) == TACTIC_KINDS[base]:
				ok = ai.intent in [SquadAI.Intent.TACTIC, SquadAI.Intent.RELOAD]
			else:  # already done (cover right beside him): holding where it ended
				ok = ai.ordered.is_empty() and ai.order == Squad.Order.HOLD and base in ["bound", "take_cover", "fall_back"]
		"treat":
			ok = ai.intent == SquadAI.Intent.CASUALTY
		"heal":
			ok = ai.intent == SquadAI.Intent.HEAL
		"scavenge":
			ok = ai.intent == SquadAI.Intent.SCAVENGE
		"escort":
			ok = arg == "" or ai.intent == SquadAI.Intent.ESCORT
	return {} if ok else reason(ai)


## Why `ai` isn't doing what it was told, in its own words, from what it is doing:
## {"id": &"defer" (it will, once done) or &"refuse", "text"}. The words come from the same
## state as its status line on the HUD (SquadAI.status_text), so they can't lie.
static func reason(ai: SquadAI) -> Dictionary:
	var who := ai._name_of(ai.casualty)
	var status := ai.status_text()
	if ai.body.suppression >= SquadAI.PINNED:
		return _r(&"refuse", "Can't, pinned down!")
	match ai.intent:
		SquadAI.Intent.CASUALTY:
			match ai.care:
				SquadAI.Care.REACH:
					return _r(&"defer", "Getting to %s first" % who)
				SquadAI.Care.DRAG:
					return _r(&"defer", "Dragging %s to cover first" % who)
				SquadAI.Care.TREAT:
					return _r(&"defer", "Treating %s first" % who) if status.begins_with("Treating") else _r(&"refuse", "Can't leave %s" % who)
				SquadAI.Care.GUARD:
					return _r(&"refuse", "Can't leave %s" % who)
				SquadAI.Care.CARRY:
					return _r(&"refuse", "Can't, carrying %s" % who) if ai.body.carrying == ai.casualty else _r(&"refuse", "Can't leave %s" % who)
				SquadAI.Care.BODY:
					return _r(&"refuse", "Can't, carrying %s's body" % who) if ai.body.carrying == ai.casualty else _r(&"defer", "Getting %s's body first" % who)
		SquadAI.Intent.HEAL:
			return _r(&"defer", "Patching myself up first")
		SquadAI.Intent.SCAVENGE:
			return _r(&"defer", "Checking the body first")
		SquadAI.Intent.FALL_BACK:
			return _r(&"refuse", "Can't, falling back!")
		SquadAI.Intent.ESCORT:
			return _r(&"refuse", "Can't, escorting %s" % ai._name_of(ai.escorting))
	return _r(&"refuse", "Can't, %s" % lower_first(status))


static func _r(id: StringName, text: String) -> Dictionary:
	return {"id": id, "text": text}


## Who acknowledges for those who comply: the team leader among them, else the first by squad slot.
static func acker_of(units: Array[SquadAI]) -> SquadAI:
	var best: SquadAI = null
	for ai in units:
		if ai.body.role == Roles.TEAM_LEADER:
			return ai
		if best == null or (ai.body.squad_slot if ai.body.squad_slot >= 0 else 99) < (best.body.squad_slot if best.body.squad_slot >= 0 else 99):
			best = ai
	return best


## The acknowledgement of command `base` (`arg`) by `ai` (ACK_LINES).
static func ack_line(ai: SquadAI, base: String, arg: String) -> String:
	match base:
		"treat":
			return "Going to %s" % ai._name_of(ai.casualty)
		"target":
			return "Got him" if arg != "" else "Copy, own targets"
		"escort":
			return "Got him" if arg != "" else "Copy, leaving him"
		"formation":
			return "Copy, %s" % arg
		"ccp_off":
			# Once "Stop bringing casualties" holds them where they lie (Squad.hold_casualties,
			# fix/respawn-own-kit), it says so; before, it only ends the casualty point.
			return "Copy, leaving them where they lie" if ai.squad and &"hold_casualties" in ai.squad else "Copy, no casualty point"
	return String(ACK_LINES.get(base, "Copy"))


## An order's failure reason (VOICE_WHY) as a squadmate says it, or "".
static func refusal_voice(why: String) -> String:
	if VOICE_WHY.has(why):
		return VOICE_WHY[why]
	if why.begins_with("Nobody selected carries"):
		return "No spare ammo for that"
	if why.ends_with("doesn't need treatment"):
		return "They're fine"
	return ""


## Watches for those who were sent somewhere all to be there, then their acknowledging
## squadmate says "In position" (a newer order to any of them ends the watch).
func _watch_arrivals(now: float, callouts: Callouts) -> void:
	for i in range(_arrivals.size() - 1, -1, -1):
		var w: Dictionary = _arrivals[i]
		var units := (w.units as Array).filter(func(ai: SquadAI) -> bool: return is_instance_valid(ai) and ai.body and ai.body.vitals.is_up())
		if units.is_empty() or now > float(w.until) \
				or units.any(func(ai: SquadAI) -> bool: return float(_unit(ai, now).order_at) > float(w.given) + 0.001):
			_arrivals.remove_at(i)
			continue
		if not units.all(func(ai: SquadAI) -> bool: return arrived(ai, String(w.base))):
			continue
		_arrivals.remove_at(i)
		var speaker: SquadAI = w.speaker if w.speaker in units else units[0]
		callouts.say(speaker.body, &"in_position", "In position", "in_position/%d" % int(float(w.given) * 1000.0))


## Whether `ai` got where command `base` sent it.
static func arrived(ai: SquadAI, base: String) -> bool:
	match base:
		"move":
			# Flat: the move point is on the ground, the body's origin may sit above it (R0856:
			# "Moving" on the HUD a metre from the spot for 25 s).
			return ai.intent == SquadAI.Intent.MOVE_TO and _flat(ai.body.global_position, ai._move_point) <= ARRIVED_M
		"garrison":
			return ai.status_text().begins_with("Holding a")
	return ai.ordered.is_empty() and ai.order == Squad.Order.HOLD  # a bound, cover or fall back ended


# --- Status? ------------------------------------------------------------------------------

## Host: Status > Report status from `from`: each named squadmate who is up answers him alone,
## STATUS_GAP_S apart (status_line).
func status_reply(from: Soldier, names: PackedStringArray) -> void:
	var callouts := Callouts.of(squad)
	if callouts == null or from == null or not is_instance_valid(from):
		return
	var now := Soldier._now()
	var to := PackedInt32Array([from.owner_peer()])
	var key := "status/%d" % int(now * 1000.0)
	var i := 0
	for ai in _able(names):
		callouts.say(ai.body, &"status", status_line(ai, from), key, "", 0.0, {"to": to, "me": true, "not_before": now + i * STATUS_GAP_S})
		i += 1


## "Watching over Miller. 2 mags, out of tourniquets, wounded. I'm {where}": what `ai` is
## doing (status_text), its ammunition (ammo_word), medical items it's out of (meds_word), how
## it is unless OK, and where it is (said from the asker's view) when more than STATUS_FAR_M
## from `asker`.
static func status_line(ai: SquadAI, asker: Soldier) -> String:
	var s := ai.body
	var parts := PackedStringArray([ai.status_text()])
	var kit := PackedStringArray()
	for word in [ammo_word(s), meds_word(s), s.vitals.condition_text().to_lower() if s.vitals.condition_text() != "OK" else ""]:
		if word != "":
			kit.append(word)
	if not kit.is_empty():
		parts.append(upper_first(", ".join(kit)))
	if asker and is_instance_valid(asker) and s.global_position.distance_to(asker.global_position) > STATUS_FAR_M:
		parts.append("I'm %s" % Callouts.WHERE)
	return ". ".join(parts)


# --- Unprompted moments ---------------------------------------------------------------------

## Host, every THINK_S: each squadmate says what changed that the players should know.
func think(now: float) -> void:
	var callouts := Callouts.of(squad)
	if callouts == null:
		return
	_supply_cd -= THINK_S
	var supply := _supply_cd <= 0.0
	if supply:
		_supply_cd = SUPPLY_EVERY_S
	var lead: Soldier = squad.leader if is_instance_valid(squad.leader) and not squad.leader.is_queued_for_deletion() else null
	var seen := {}
	var behind: Array[Dictionary] = []
	for ai in squad.brains():
		var s := ai.body
		var id := ai.get_instance_id()
		seen[id] = true
		var first := not _units.has(id)
		var u := _unit(ai, now)
		if not first and s.vitals.is_up() and not s.is_queued_for_deletion():
			_pinned(ai, u, now, callouts)
			_hit(ai, u, now, callouts)
			_gave_up(ai, u, now, callouts)
			_explain(ai, u, now, callouts)
			var far := _separated(ai, u, lead, now)
			if not far.is_empty():
				behind.append(far)
			_stuck(ai, u, now, callouts)
			if supply:
				_supply(ai, u, now, callouts)
		u.intent = ai.intent
		u.care = ai.care
		u.casualty = ai.casualty
	for id: int in _units.keys():
		if not seen.has(id):
			_units.erase(id)
	_say_behind(behind, callouts)
	_watch_arrivals(now, callouts)


## What `ai` was doing at the last look, made the first time.
func _unit(ai: SquadAI, now: float) -> Dictionary:
	var id := ai.get_instance_id()
	if not _units.has(id):
		_units[id] = {"intent": ai.intent, "care": ai.care, "casualty": ai.casualty, "order_at": -1000.0,
			"pinned_since": -1.0, "hit_at": hit_time(ai.body), "far_since": -1.0, "far_told_m": 0.0, "far_told_at": -1000.0,
			"stuck_pos": Vector3.INF, "stuck_since": now, "stuck_asked": -1000.0, "stuck_logged": false,
			"ammo": 0, "ammo_since": now, "meds": {}}
	return _units[id]


## Suppressed past SquadAI.PINNED for PINNED_FOR_S: "I'm pinned!", once a spell.
func _pinned(ai: SquadAI, u: Dictionary, now: float, callouts: Callouts) -> void:
	if ai.body.suppression < SquadAI.PINNED:
		u.pinned_since = -1.0
		return
	if float(u.pinned_since) < 0.0:
		u.pinned_since = now
		return
	var last := callouts.said_at(ai.body, "pinned")
	if now - float(u.pinned_since) >= PINNED_FOR_S and last < float(u.pinned_since) and now - last >= PINNED_REPEAT_S:
		callouts.say(ai.body, &"pinned", "I'm pinned!", "pinned")


## A new hit: "I'm hit!", "Hit, still good", or "Armor took it, I'm good".
func _hit(ai: SquadAI, u: Dictionary, now: float, callouts: Callouts) -> void:
	var at := hit_time(ai.body)
	if at <= float(u.hit_at) + 0.01:
		return
	u.hit_at = at
	if now - at <= HIT_FRESH_S and now - callouts.said_at(ai.body, "hit") >= HIT_REPEAT_S:
		callouts.say(ai.body, &"hit", hit_line(ai.body), "hit")


## When `s` was last hit (a wound or a round armor stopped; Soldier._now() seconds).
static func hit_time(s: Soldier) -> float:
	return Soldier._now() - s.vitals.seconds_since_hit()


static func hit_line(s: Soldier) -> String:
	if String(s.vitals.last_cause.get("cause", "")).begins_with("round stopped by armor"):
		return "Armor took it, I'm good"
	return "I'm hit!" if s.vitals.injury() >= HIT_BAD else "Hit, still good"


## Let go of a casualty he couldn't reach (SquadAI._give_up_casualty: he leaves them to
## others a while): "Can't reach Miller, someone else take over!".
func _gave_up(ai: SquadAI, u: Dictionary, now: float, callouts: Callouts) -> void:
	var was: Soldier = u.casualty if is_instance_valid(u.casualty) else null
	var care := int(u.care)
	if was == null or care not in [SquadAI.Care.REACH, SquadAI.Care.BODY] or (ai.casualty == was and ai.care != SquadAI.Care.NONE) \
			or not ai._skipping(was):
		return
	var key := "give_up/%s" % was.name
	if now - callouts.said_at(ai.body, key) < GIVE_UP_REPEAT_S:
		return
	if care == SquadAI.Care.BODY:
		callouts.say(ai.body, &"explain", "Can't get to %s's body" % ai._name_of(was), key)
	elif SquadAI.needs_help(was):
		callouts.say(ai.body, &"give_up", "Can't reach %s, someone else take over!" % ai._name_of(was), key)


## A move away from the squad nobody ordered, explained when it starts ("Going for Miller's
## body", "Falling back!"); the line goes only while he's still doing it.
func _explain(ai: SquadAI, u: Dictionary, now: float, callouts: Callouts) -> void:
	if ai.intent == int(u.intent) and (ai.intent != SquadAI.Intent.CASUALTY or ai.care == int(u.care)):
		return
	if now - float(u.order_at) < EXPLAIN_AFTER_ORDER_S:
		return
	var e := explanation(ai)
	if e.is_empty():
		return
	var intent := ai.intent
	var care := ai.care
	var still := func() -> bool: return is_instance_valid(ai) and ai.intent == intent and ai.care == care
	callouts.say(ai.body, e.id, e.text, e.key, "", 0.0, {"valid": still})


## What `ai` says about what it just started doing, or {}: {"id", "text", "key"}.
static func explanation(ai: SquadAI) -> Dictionary:
	match ai.intent:
		SquadAI.Intent.CASUALTY:
			if ai.care == SquadAI.Care.BODY and is_instance_valid(ai.casualty) and ai.body.carrying != ai.casualty:
				return {"id": &"explain", "text": "Going for %s's body%s" % [ai._name_of(ai.casualty), body_destination_words(ai)],
					"key": "explain/body/%s" % ai.casualty.name}
		SquadAI.Intent.SCAVENGE:
			var dead: Soldier = ai.loot_body if ai.loot_body else ai._loot_candidate
			if dead and is_instance_valid(dead) and ai.body.global_position.distance_to(dead.body_point()) > SCAVENGE_EXPLAIN_M:
				var whose := "%s's body" % ai._name_of(dead) if dead.faction == ai.body.faction else "that body"
				return {"id": &"explain", "text": "Getting %s off %s" % [scavenge_word(ai.body), whose], "key": "explain/scavenge/%s" % dead.name}
		SquadAI.Intent.FALL_BACK:
			return {"id": &"fall_back", "text": "Falling back!", "key": "fall_back"}
		SquadAI.Intent.HEAL:
			if Soldier._now() >= ai._heal_until:  # (ordered: the answer said it)
				return {"id": &"explain", "text": "Patching myself up", "key": "explain/heal"}
	return {}


## Where a fallen friendly's body is being taken: ", taking it to the CCP" or "to the exfil"
## once bodies go only somewhere (SquadAI._body_destination, fix/respawn-own-kit), else
## ", bringing it with us" (they're carried after the lead).
static func body_destination_words(ai: SquadAI) -> String:
	if not ai.has_method(&"_body_destination"):
		return ", bringing it with us"
	var dest: Variant = ai.call(&"_body_destination", ai.casualty.body_point())
	if not (dest is Vector3):
		return ""
	var ccp: Variant = ai.squad.ccp_point() if ai.squad else null
	return ", taking it to the CCP" if ccp is Vector3 and (ccp as Vector3).distance_to(dest) < 1.0 else ", taking it to the exfil"


## What `s` is shortest of, as scavenging sees it (Scavenge.needs): "ammo", "meds", ...
static func scavenge_word(s: Soldier) -> String:
	var best := {}
	var needs := Scavenge.needs(s)
	for id: StringName in needs:
		var n: Dictionary = needs[id]
		if best.is_empty() or float(n.frac) * float(n.weight) > float(best.frac) * float(best.weight):
			best = n
	match String(best.get("kind", "")):
		"ammo":
			return "ammo"
		"medical":
			return "meds"
		"grenade":
			return "grenades"
		"intel":
			return "the intel"
	return "kit"


## Following, but more than SEPARATED_M from the lead for SEPARATED_S (again after
## SEPARATED_REPEAT_S, or once twice as far): {"ai", "why" (what keeps him, or "" when he's
## just following)} for _say_behind, else {}. Not an anomaly by itself (the lead may have
## respawned or run ahead): one who isn't getting any closer is stuck (_stuck), and that is.
func _separated(ai: SquadAI, u: Dictionary, lead: Soldier, now: float) -> Dictionary:
	var s := ai.body
	if lead == null or lead == s or ai.order != Squad.Order.FOLLOW or s.vehicle != null or lead.vehicle != null:
		u.far_since = -1.0
		return {}
	var d := _flat(s.global_position, lead.global_position)
	if d <= SEPARATED_M:
		u.far_since = -1.0
		return {}
	if float(u.far_since) < 0.0:
		u.far_since = now
		return {}
	var told := float(u.far_told_at)
	if now - float(u.far_since) < SEPARATED_S \
			or (told >= float(u.far_since) and now - told < SEPARATED_REPEAT_S and d < 2.0 * float(u.far_told_m)):
		return {}
	u.far_told_at = now
	u.far_told_m = d
	var status := ai.status_text()
	return {"ai": ai, "why": "" if status in ["Following", "Moving"] else lower_first(status)}


## Those who fell behind at this look say so, where they are from each listener's view: each
## kept by something his own ("Falling behind: watching over Miller, back left, 400 m"), the
## rest one for all ("Falling behind, four of us, back, 150 m"; the lead ran ahead or respawned).
func _say_behind(behind: Array[Dictionary], callouts: Callouts) -> void:
	var plain: Array[SquadAI] = []
	for b in behind:
		var ai: SquadAI = b.ai
		if String(b.why) != "":
			callouts.say(ai.body, &"separated", "Falling behind: %s, %s" % [b.why, Callouts.WHERE], "separated", "", 0.0, {"me": true})
		else:
			plain.append(ai)
	if plain.is_empty():
		return
	var speaker := acker_of(plain)
	var who := "" if plain.size() == 1 else ", %s of us" % Callouts.count_word(plain.size())
	callouts.say(speaker.body, &"separated", "Falling behind%s, %s" % [who, Callouts.WHERE], "separated", "", 0.0, {"me": true})


## Out of contact, far from where he's going and not getting closer: "I'm stuck" (and a
## session-log anomaly). Reaching a casualty or a body to scavenge has its own give-up.
func _stuck(ai: SquadAI, u: Dictionary, now: float, callouts: Callouts) -> void:
	var s := ai.body
	var dest := ai.destination()
	if not dest.is_finite() or ai.in_contact() or s.vehicle != null or ai.intent == SquadAI.Intent.SCAVENGE \
			or (ai.intent == SquadAI.Intent.CASUALTY and ai.care == SquadAI.Care.REACH) or _flat(s.global_position, dest) <= STUCK_FAR_M:
		u.stuck_pos = Vector3.INF
		u.stuck_logged = false
		return
	var at: Vector3 = u.stuck_pos
	if not at.is_finite() or _flat(s.global_position, at) > STUCK_MOVED_M:
		u.stuck_pos = s.global_position
		u.stuck_since = now
		return
	var last := callouts.said_at(s, "stuck")
	if now - float(u.stuck_since) < STUCK_S or last >= float(u.stuck_since) or now - last < STUCK_REPEAT_S \
			or now - float(u.stuck_asked) < Callouts.REPEAT_GAP_S:
		return
	u.stuck_asked = now
	callouts.say(s, &"stuck", "I'm stuck, can't get to you" if ai.intent == SquadAI.Intent.FOLLOW else "I'm stuck", "stuck")
	if not bool(u.stuck_logged):
		u.stuck_logged = true
		SessionLog.anomaly("comms_stuck", "%s says he's stuck: %.0f m from where he's going, moved under %.0f m in %.0f s (%s)" % [s.log_name(),
			_flat(s.global_position, dest), STUCK_MOVED_M, now - float(u.stuck_since), ai.status_text()])


## Ammunition (ammo_level) and the life-saving medical items (Scavenge.CRITICAL_MED, as
## scavenging counts them: Scavenge.needs), each level said once, again after a restock.
func _supply(ai: SquadAI, u: Dictionary, now: float, callouts: Callouts) -> void:
	var s := ai.body
	var level := ammo_level(s)
	if level != int(u.ammo):
		u.ammo = level
		u.ammo_since = now
	if level > 0:
		var key := "ammo/%d" % level
		var last := callouts.said_at(s, key)
		if last < float(u.ammo_since) and now - last >= AMMO_REPEAT_S:
			callouts.say(s, AMMO_IDS[level], ammo_line(s, level), key)
	var needs := Scavenge.needs(s)
	var meds: Dictionary = u.meds
	var told := false
	for id: StringName in Scavenge.CRITICAL_MED:
		var n: Dictionary = needs.get(id, {})
		if n.is_empty() or String(n.kind) != "medical" or float(n.frac) < 1.0:
			meds.erase(id)
			continue
		if not meds.has(id):
			meds[id] = now
		var key := "meds/%s" % id
		var last := callouts.said_at(s, key)
		if not told and last < float(meds[id]) and now - last >= MEDS_REPEAT_S:
			callouts.say(s, &"out_of_meds", "Out of %s" % med_word(id), key)
			told = true


## 0 enough, 1 low (LOW_MAGS spare magazines or fewer), 2 on the last magazine, 3 out: the
## primary weapon's ammunition (0 without one).
static func ammo_level(s: Soldier) -> int:
	var mags := spare_mags(s)
	if mags < 0:
		return 0
	if mags > LOW_MAGS:
		return 0
	if mags > 0:
		return 1
	return 2 if s.inventory.rounds_in(&"primary") > 0 else 3


## Spare magazines with rounds in them for `s`'s primary weapon, or -1 without one.
static func spare_mags(s: Soldier) -> int:
	var weapon_id: StringName = s.inventory.slots.get(&"primary", &"")
	if weapon_id == &"" or not ItemDB.has_item(weapon_id):
		return -1
	var ammo := Soldier._ammo_of(ItemDB.get_item(weapon_id))
	if not ItemDB.has_item(ammo):
		return -1
	var full := ItemDB.get_item(ammo).magazine_rounds()
	var n := 0
	for container in s.inventory.search_containers():
		for entry: Dictionary in s.inventory.containers[container]:
			if entry.id == ammo and int(entry.get("state", {}).get("rounds", full)) > 0:
				n += int(entry.count)
	return n


static func ammo_line(s: Soldier, level: int) -> String:
	match level:
		1:
			var n := spare_mags(s)
			return "Low on ammo, %d mag%s" % [n, "" if n == 1 else "s"]
		2:
			return "Last mag!"
	return "Out of ammo!"


## "6 mags", "last mag", "out of ammo" ("" without a primary weapon).
static func ammo_word(s: Soldier) -> String:
	var n := spare_mags(s)
	if n < 0:
		return ""
	if n > 0:
		return "%d mag%s" % [n, "" if n == 1 else "s"]
	return "last mag" if s.inventory.rounds_in(&"primary") > 0 else "out of ammo"


## "out of tourniquets and gauze": the life-saving items `s` has none of ("" for none).
static func meds_word(s: Soldier) -> String:
	var needs := Scavenge.needs(s)
	var out := PackedStringArray()
	for id: StringName in Scavenge.CRITICAL_MED:
		var n: Dictionary = needs.get(id, {})
		if not n.is_empty() and String(n.kind) == "medical" and float(n.frac) >= 1.0:
			out.append(med_word(id))
	return "out of %s" % " and ".join(out.slice(0, 2)) if not out.is_empty() else ""


static func med_word(id: StringName) -> String:
	if MED_WORDS.has(id):
		return MED_WORDS[id]
	return ItemDB.get_item(id).name.to_lower() if ItemDB.has_item(id) else String(id)


static func lower_first(text: String) -> String:
	return text.substr(0, 1).to_lower() + text.substr(1) if text != "" else text


static func upper_first(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) if text != "" else text


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
