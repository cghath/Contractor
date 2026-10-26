class_name Perks
extends RefCounted
## Survivor perks (docs/survival_rpg.md section 2, call 83): one pick per survivor level,
## permanent, general (not tied to a line), a few needing a line level ("needs"). Lost at
## permadeath with everything else. Each perk's "fx" are the numbers Rpg's effect reads use;
## "later" marks a perk recorded now whose effect lands with its system. Proposed numbers.

const ALL := {
	"strong_back": {"name": "Strong back", "text": "+6 kg carried before the load slows you", "fx": {"carry_kg": 6.0}},
	"bigger_pack": {"name": "Bigger pack", "text": "+10 l in the pack (packs a bag tighter)", "fx": {"pack_l": 10.0}, "later": true},
	"fast_healer": {"name": "Fast healer", "text": "Wounds close faster", "fx": {"heal": 1.25}, "later": true},
	"quiet_feet": {"name": "Quiet feet", "text": "Footsteps carry 15% less far", "fx": {"step_noise": 0.85}},
	"iron_stomach": {"name": "Iron stomach", "text": "Raw food and bad water make you sick less", "fx": {"raw_risk": 0.5}, "later": true},
	"thick_skin": {"name": "Thick skin", "text": "The cold gets in 20% slower", "fx": {"cold": 0.8}},
	"night_eyes": {"name": "Night eyes", "text": "See further in the dark", "fx": {"night_sight": 1.3}, "needs": {"stealth": 3}, "later": true},
	"steady_hands": {"name": "Steady hands", "text": "Treatments and builds faster under stress", "fx": {"build_time": 0.9, "treat_time": 0.9}},
	"people_person": {"name": "People person", "text": "Better hiring prices and standing", "fx": {"standing": 1.2}, "later": true},
	"planner": {"name": "Planner", "text": "Settlers finish work orders faster", "fx": {"orders": 1.2}, "later": true},
	"light_sleeper": {"name": "Light sleeper", "text": "Wakes on the first noise ring", "fx": {"wakes": true}, "later": true},
	"second_wind": {"name": "Second wind", "text": "A stamina burst once a day", "fx": {"second_wind": true}, "later": true},
	"brawler": {"name": "Brawler", "text": "Swings cost 15% less stamina", "fx": {"melee_stamina": 0.85}, "needs": {"melee": 2}},
	"scrounger": {"name": "Scrounger", "text": "Searches go 20% faster", "fx": {"search_time": 0.8}},
	"quick_study": {"name": "Quick study", "text": "+10% XP in every line", "fx": {"xp": 1.1}},
	"marathoner": {"name": "Marathoner", "text": "Stamina lasts longer on the run", "fx": {"stamina": 1.15}, "later": true},
	"field_medic": {"name": "Field medic", "text": "Treatments 20% faster", "fx": {"treat_time": 0.8}, "needs": {"medical": 2}, "later": true},
	"handy": {"name": "Handy", "text": "Builds and repairs 15% faster", "fx": {"build_time": 0.85}, "needs": {"building": 2}},
	"lead_foot": {"name": "Lead foot", "text": "Vehicles handle better and burn less", "fx": {"fuel": 0.9}, "needs": {"driving": 2}, "later": true},
	"forager": {"name": "Forager", "text": "Finds more in the wild", "fx": {"forage": 1.25}, "needs": {"fieldcraft": 2}, "later": true},
	"cool_head": {"name": "Cool head", "text": "Parry window a little wider", "fx": {"parry": 1.2}},
}
const ADDITIVE := ["carry_kg", "pack_l"]


static func info(id: String) -> Dictionary:
	return ALL.get(id, {})


## Whether a survivor with `levels` (line -> level) may take `id` (its "needs" met).
static func allowed(id: String, levels: Dictionary) -> bool:
	if not ALL.has(id):
		return false
	var needs: Dictionary = (ALL[id] as Dictionary).get("needs", {})
	for line: String in needs:
		if int(levels.get(line, 0)) < int(needs[line]):
			return false
	return true


## The product of `key` over `perks` (the sum for ADDITIVE keys: 0 when none has it).
static func fx(perks: Array, key: String) -> float:
	var additive := key in ADDITIVE
	var out := 0.0 if additive else 1.0
	for id: String in perks:
		var f: Dictionary = (ALL.get(id, {}) as Dictionary).get("fx", {})
		if f.has(key) and typeof(f[key]) in [TYPE_FLOAT, TYPE_INT]:
			out = (out + float(f[key])) if additive else (out * float(f[key]))
	return out


static func has_flag(perks: Array, key: String) -> bool:
	for id: String in perks:
		if bool(((ALL.get(id, {}) as Dictionary).get("fx", {}) as Dictionary).get(key, false)):
			return true
	return false
