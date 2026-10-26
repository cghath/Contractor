class_name Surgery
extends RefCounted
## Field surgery (docs/survival_medical.md section 2, call 79): remove a bullet or fragment,
## debride (clean out a dirty wound), stitch, set a fracture (well, or badly: crooked), drain an
## abscess, amputate (the last resort for gangrene). Each is gated by the medical line (Rpg.can:
## stitch 3, remove_fragment 5, set_bone 6 (below it a bone sets badly), amputate 8; debride 4 and
## drain 7 by Rpg.gate), needs tools (a surgical kit, or improvised with a knife at a penalty; a
## stitch needs a suture kit or the surgical kit), and goes better with light, a clean surface (a
## bunk or a table near; the clinic's bed when the building lane has one; the ground worst),
## anaesthesia (morphine in the blood, or a strong drink: rubbing alcohol for now) and time with the
## patient still (both busy: Soldier.server_busy). A failed attempt makes it worse (dirtier, a fresh
## bleed, pain). Permanent consequences (crooked bones, a limp, a lost hand) are only flags here
## ("permanent" on the body; the effects come later, call 79).

const OPS := {
	"remove_fragment": {"name": "Remove the fragment", "gate": "remove_fragment", "level": 5, "s": 60.0, "tool": "kit"},
	"debride": {"name": "Debride", "gate": "", "level": 4, "s": 45.0, "tool": "kit"},
	"stitch": {"name": "Stitch", "gate": "stitch", "level": 3, "s": 40.0, "tool": "suture"},
	"set_bone": {"name": "Set the bone", "gate": "", "level": 3, "s": 50.0, "tool": "none"},
	"drain": {"name": "Drain the abscess", "gate": "", "level": 7, "s": 40.0, "tool": "kit"},
	"amputate": {"name": "Amputate", "gate": "amputate", "level": 8, "s": 120.0, "tool": "kit"},
}
const KIT := &"surgical_kit"
const SUTURE := &"suture_kit"
const KNIVES: Array[StringName] = [&"knife", &"combat_knife"]
const DRINK := &"rubbing_alcohol"
## Proposed: the chance by margin over the gate, and the multipliers for what's missing.
const BASE_CHANCE := 0.7
const PER_LEVEL := 0.06
const MAX_CHANCE := 0.97
const IMPROVISED := 0.7
const DARK := 0.7
const NO_ANAESTHESIA := 0.75
const SURFACES := {"clinic": 1.0, "bed": 0.9, "table": 0.9, "floor": 0.8, "ground": 0.65}
const SURFACE_M := 2.5
const SET_WELL_LEVEL := 6
const FAIL_BLEED := 0.05
const FAIL_PAIN_DAMAGE := 8.0
const XP := 8.0
## Tests: a roll to use instead of randf() (-1: roll for real).
static var force_roll := -1.0


## Why `surgeon` can't do `op` on `patient`'s `part` now ("" he can): the gate, the wound to work
## on, the tools.
static func problem(surgeon: Soldier, patient: Soldier, op: String, part: String) -> String:
	if not OPS.has(op):
		return "No such operation"
	var row: Dictionary = OPS[op]
	if String(row.gate) != "" and not Rpg.can(surgeon, String(row.gate)):
		return "%s takes more medical skill (medical %d)" % [String(row.name), int(row.level)]
	if String(row.gate) == "" and not Rpg.gate(surgeon, "medical", int(row.level)):
		return "%s takes more medical skill (medical %d)" % [String(row.name), int(row.level)]
	var n := Survival.needs_of(patient)
	Infection.server_sync(patient, n)
	if _target(n, op, part).is_empty():
		return "Nothing there to %s" % String(row.name).to_lower()
	if tools(surgeon, op) == "":
		return "No tools: a surgical kit%s, or at least a knife" % (" or a suture kit" if op == "stitch" else "")
	return ""


## The record `op` works on at `part` ({} none).
static func _target(n: Dictionary, op: String, part: String) -> Dictionary:
	for r: Dictionary in Infection.on_part(n, part):
		match op:
			"remove_fragment":
				if bool(r.fragment):
					return r
			"debride":
				if int(r.stage) >= 1 and not bool(r.closed):
					return r
			"stitch":
				if not bool(r.closed) and not bool(r.stitched) and String(r.kind) in ["venous", "muscle", "graze", "arterial", "junctional", "burn"]:
					return r
			"set_bone":
				if String(r.kind) == "fracture" and String(r.get("bone", "")) in ["", "splinted"]:
					return r
			"drain":
				if bool(r.abscess):
					return r
			"amputate":
				if String(part) in Infection.LIMB_PARTS:
					return r
	return {}


## The tools `surgeon` would use for `op`: "kit", "suture", "improvised" or "" (none). Setting a
## bone needs hands only.
static func tools(surgeon: Soldier, op: String) -> String:
	var inv := surgeon.inventory
	var tool := String((OPS.get(op, {}) as Dictionary).get("tool", "kit"))
	if tool == "none":
		return "kit"
	if inv.count_of(KIT) > 0:
		return "kit"
	if tool == "suture" and inv.count_of(SUTURE) > 0:
		return "suture"
	for k: StringName in KNIVES:
		if inv.count_of(k) > 0:
			return "improvised"
	if MeleeWeapons.blade_carried(surgeon):
		return "improvised"
	return ""


## The surface under `patient`: a built bunk ("bed") or workbench or map table ("table") near, the
## clinic's bed when the building lane adds one (meta "surgery_surface" overrides), else the floor
## indoors or the ground.
static func surface_of(patient: Soldier) -> String:
	if patient.has_meta(&"surgery_surface"):
		return String(patient.get_meta(&"surgery_surface"))
	if patient.is_inside_tree():
		for node in patient.get_tree().get_nodes_in_group(InteractionMenu.INTERACTABLES):
			var bp := node as BuildPiece
			if bp == null or float(bp.rec.get("prog", 0.0)) < 1.0 or bp.global_position.distance_to(patient.global_position) > SURFACE_M:
				continue
			match String(bp.rec.get("k", "")):
				"clinic_bed":
					return "clinic"
				"bunk":
					return "bed"
				"workbench", "map_table":
					return "table"
		if Throwables.indoors(patient.get_world_3d(), patient.global_position):
			return "floor"
	return "ground"


## Whether the patient is under: morphine in the blood or a strong drink just taken (meta "drunk_until").
static func anaesthetised(patient: Soldier) -> bool:
	if patient.vitals.morphine_level() >= 0.3:
		return true
	return patient.has_meta(&"drunk_until") and Soldier._now() < float(patient.get_meta(&"drunk_until"))


## The chance `op` goes well for `surgeon` on `patient`, and what lowers it.
static func chance(surgeon: Soldier, patient: Soldier, op: String) -> float:
	var row: Dictionary = OPS.get(op, {})
	var level := Rpg.level(surgeon, "medical") if Rpg.active(surgeon) else 6
	var c := BASE_CHANCE + PER_LEVEL * float(maxi(0, level - int(row.get("level", 0))))
	if tools(surgeon, op) == "improvised":
		c *= IMPROVISED
	if patient.is_inside_tree() and DayNight.darkness_at(patient.global_position) > 0.6 and surgeon.inventory.count_of(&"chemlight_green") <= 0:
		c *= DARK
	c *= float(SURFACES.get(surface_of(patient), 0.65))
	if op != "set_bone" and not anaesthetised(patient):
		c *= NO_ANAESTHESIA
	return clampf(c, 0.05, MAX_CHANCE)


## Host: `surgeon` does `op` on `patient`'s `part`: both busy for its time; it goes well or it
## makes things worse. Returns what the surgeon is told ("" refused: Survival._tell says why).
static func server_operate(surgeon: Soldier, patient: Soldier, op: String, part: String) -> Dictionary:
	var why := problem(surgeon, patient, op, part)
	if why != "":
		Survival._tell(surgeon, why)
		return {"ok": false, "why": why}
	var row: Dictionary = OPS[op]
	var n := Survival.needs_of(patient)
	var r := _target(n, op, part)
	var p := chance(surgeon, patient, op)
	var roll := force_roll if force_roll >= 0.0 else randf()
	var good := roll < p
	var used := tools(surgeon, op)
	var secs := float(row.s) * (1.3 if used == "improvised" else 1.0)
	surgeon.server_busy(secs, String(row.name))
	if patient != surgeon:
		patient.server_busy(secs, "Under the knife")
	if used == "suture":
		FallenStory.take_one(surgeon, String(SUTURE))  # a suture kit is one use; the surgical kit's tools last
	var text := ""
	if good:
		text = _succeed(patient, n, r, op, part, surgeon)
		Rpg.xp(surgeon, "medical", XP, int(row.level))
		if op != "amputate" and Clinic.after_surgery(r, surface_of(patient), Clinic.post_op_roll(force_roll)):
			text += ". The wound may go bad: keep it clean"  # (the post-op roll: a clinic's is lowest)
	else:
		text = _fail(patient, n, r, op, part)
		Rpg.xp(surgeon, "medical", XP * 0.5, int(row.level))
	patient.vitals.server_log_care(surgeon.display_name(), "%s, %s (%s)" % [String(row.name), Vitals.part_name(StringName(part)), "done" if good else "went badly"])
	Survival._tell(surgeon, text)
	return {"ok": good, "why": "", "text": text}


static func _succeed(patient: Soldier, n: Dictionary, r: Dictionary, op: String, part: String, surgeon: Soldier) -> String:
	match op:
		"remove_fragment":
			r.fragment = false
			r.dirt = 0.0
			return "Got it out. Keep it clean now"
		"debride":
			r.debrided = true
			r.stage = maxi(0, int(r.stage) - (2 if int(r.stage) >= 2 else 1))
			if bool(r.fragment):
				r.stage = maxi(int(r.stage), 1)
			r.stage_h = 0.0
			r.dirt = 0.0
			return "Cleaned out to healthy flesh"
		"stitch":
			r.stitched = true
			r.heal_h = float(r.heal_h) * Infection.STITCHED_MULT
			r.heal_total = float(r.heal_total) * Infection.STITCHED_MULT
			patient.vitals.server_close_wound(int(r.id))
			return "Stitched: days instead of weeks"
		"set_bone":
			var well := Rpg.gate(surgeon, "medical", SET_WELL_LEVEL)
			r.bone = "set_well" if well else "set_badly"
			if not well:
				_permanent(n, "crooked:" + part)
			return "Set straight" if well else "Set, but it'll knit crooked"
		"drain":
			r.abscess = false
			r.stage = maxi(1 if bool(r.fragment) else 0, int(r.stage) - 1)
			r.stage_h = 0.0
			return "Drained"
		"amputate":
			for w: Dictionary in Infection.on_part(n, part):
				Infection.records(n).erase(w)
			patient.vitals.server_heal_part(StringName(part))
			patient.vitals.server_add_wound(StringName(part), "venous", 0.0)
			_permanent(n, "amputated:" + part)
			return "It's off. The stump needs dressing"
	return ""


static func _fail(patient: Soldier, n: Dictionary, r: Dictionary, op: String, part: String) -> String:
	if not r.is_empty() and not bool(r.get("closed", false)):
		r.stage = maxi(int(r.stage), 1)
		r.dirt = 1.0
	if op == "set_bone" and not r.is_empty():
		r.bone = "set_badly"
		_permanent(n, "crooked:" + part)
	if op != "set_bone":
		patient.vitals.server_add_wound(StringName(part), "venous", FAIL_BLEED)
	patient.vitals.server_damage(FAIL_PAIN_DAMAGE)
	return "It went wrong: worse than before"


static func _permanent(n: Dictionary, what: String) -> void:
	var list: Array = n.get("permanent", [])
	if not what in list:
		list.append(what)
	n["permanent"] = list


## Host: `s` drinks a strong drink (rubbing alcohol for now): numb for a few minutes. Returns whether he had one.
static func server_drink(s: Soldier) -> bool:
	if not FallenStory.take_one(s, String(DRINK)):
		return false
	s.set_meta(&"drunk_until", Soldier._now() + 300.0)
	return true
