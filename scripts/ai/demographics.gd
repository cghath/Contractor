class_name Demographics
extends RefCounted
## Whether an AI soldier is a woman (Soldier.body), by the norms of the force they come from
## (their nationality, Soldier.nation) and their role (Captain, 2026-10-11: female presence
## follows each nation's or organisation's norms and SOPs).
##
## Role-aware: women are a smaller share of front-line combat roles than of a whole military,
## and nearer the overall share in medical roles. So a nation's chance is its overall share
## for a medic, and that times COMBAT_ARMS for every other squad role.
## Shares (the whole regular force):
## - US: 17.7% of active duty (DoD 2023 Demographics Profile).
## - UK: 11.9% of the Regular Forces (MOD biannual diversity statistics, October 2024).
## - Canada: 16.3% of the Regular Force (DND, December 2024).
## - Russia: about 4% (37,500 women serving, Russian MoD, March 2024; mostly support roles,
##   so rarer still at the front).
## - China (PLA): about 4-5% (PLA estimate 2015; USCC).
## Organisations whose SOPs keep women out of field combat units:
## - Iran: the Army Law (Article 32) employs women only in medical and health posts, so none
##   in field squads.
## - Insurgent and terrorist cells: fighters are men; women, where present, are in support.
## The player's PMC follows each contractor's nationality (Captain's call).

## Proposed: women's share of combat-arms roles as a fraction of their overall share (US and
## UK combat arms remain a few percent years after opening).
const COMBAT_ARMS := 0.3
## Overall share by nationality id (Names.POOLS keys); field squads only.
const OVERALL := {
	"US": 0.177, "UK": 0.119, "CA": 0.163, "RU": 0.04, "CN": 0.045, "IR": 0.0, "insurgent": 0.0,
}


## The chance a soldier of `nation` in `role` (Roles) is a woman.
static func female_chance(nation: String, role: StringName) -> float:
	var overall := float(OVERALL.get(nation, 0.0))
	return overall if role == Roles.MEDIC else overall * COMBAT_ARMS


## Whether the soldier `callsign` (of `nation`, in `role`) is a woman: the same answer every
## time for the same callsign and nationality.
static func is_female(callsign: String, nation: String, role: StringName) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("body:%s:%s" % [callsign, nation])
	return rng.randf() < female_chance(nation, role)
