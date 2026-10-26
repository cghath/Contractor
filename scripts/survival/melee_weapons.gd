class_name MeleeWeapons
extends RefCounted
## Melee weapons as weapon items (docs/survival.md calls 86-89; Captain, 2026-10-26): an item of
## type "weapon" with a "melee" stat is swung, not fired. One-handed ones take the sidearm slot
## (knife, machete, hatchet, crowbar, pipe), two-handed the primary (bat, axe, sledge, spear).
## The stat: {"kind": "blade"|"blunt"|"point", "reach_m", "light": {windup, energy_j, stamina},
## "heavy": {...}, "art": the VoxelArt melee model, "length_m"}.
##
## A light swing is fast and cheap; a heavy winds up longer, costs more stamina, breaks a guard
## and drops a walker with one to the head (Vitals.undead: a light to the head takes a share of
## the pool instead, two or three to kill). Which part a swing lands on follows where the
## attacker looks (head height or not: Melee._part_for).
##
## The owner's side is MeleeInput (fire = light, hold = heavy, aim = block, a double-tapped
## direction = dodge, the quick melee key with a gun up, the interact key behind an unaware
## zombie = the silent kill); the host's is Soldier._server_melee -> server_action here.

const HEAVY_HOLD_S := 0.35      # fire held this long winds up a heavy instead of a light
const HEAD_ONE_HIT_J := 250.0   # a melee hit to the head at least this hard drops a walker outright
const HEAD_LIGHT_SHARE := 0.45  # a lighter one takes this share of the pool (two or three kill)
const SILENT_KILL_S := 2.0
const SILENT_KILL_M := 1.4
const QUICK := {"windup": 0.25, "heavy": false, "kind": "blunt", "round_class": &"pistol", "depth": 0.02, "energy_j": 90.0,
	"parts": [&"chest", &"chest", &"head"], "name": "shove", "reach": 1.3, "stamina": 0.08, "shove": true}


static func is_melee(item: ItemData) -> bool:
	return item != null and item.type == "weapon" and item.stats.has("melee")


static func two_handed(item: ItemData) -> bool:
	return is_melee(item) and item.slot == &"primary"


static func is_blade(item: ItemData) -> bool:
	return is_melee(item) and String((item.stats.melee as Dictionary).get("kind", "blunt")) in ["blade", "point"]


## The attack `item` makes (Melee.server_attack's profile), light or heavy.
static func profile(item: ItemData, heavy: bool) -> Dictionary:
	var m: Dictionary = item.stats.melee
	var swing: Dictionary = m.get("heavy" if heavy else "light", {})
	var kind := String(m.get("kind", "blunt"))
	return {
		"windup": float(swing.get("windup", 0.55 if heavy else 0.3)),
		"heavy": heavy,
		"kind": kind,
		"round_class": &"pistol",
		"depth": float(swing.get("depth", (0.06 if kind != "blunt" else 0.03) * (1.6 if heavy else 1.0))),
		"energy_j": float(swing.get("energy_j", 300.0 if heavy else 140.0)),
		"parts": [&"chest", &"upper_arm_l", &"upper_arm_r", &"forearm_l", &"forearm_r", &"neck"],
		"name": "%s %s" % [item.name.to_lower(), "heavy" if heavy else "swing"],
		"reach": float(m.get("reach_m", 1.4)),
		"stamina": float(swing.get("stamina", 0.18 if heavy else 0.07)),
	}


## Host: the owner asked for `action` with whatever he holds (Soldier._server_melee).
static func server_action(s: Soldier, action: String) -> void:
	var weapon := s.active_weapon()
	match action:
		"light", "heavy":
			if not is_melee(weapon):
				return
			var heavy := action == "heavy" and Rpg.can(s, "heavy_swing")  # the heavy swing from melee 2 (survival_rpg.md section 1)
			Melee.server_attack(s, profile(weapon, heavy))
		"block_on":
			Melee.server_block(s, true)
		"block_off":
			Melee.server_block(s, false)
		"dodge":
			Melee.server_dodge(s, false)
		"sidestep":
			Melee.server_dodge(s, true)
		"quick":
			if weapon != null and not is_melee(weapon):
				Melee.server_attack(s, QUICK)  # the butt of the gun, a knife hand: a shove that buys a second
		"silent":
			Melee.server_silent_kill(s, Rpg.silent_blade_ok(s, weapon))  # a knife at any level, any blade from melee 4


## A knife on the rig counts as a blade in hand for the silent kill (the starter kit's knife is
## the stealth tool from the first night: call 89).
static func blade_carried(s: Soldier) -> bool:
	return s.inventory.count_of(&"combat_knife") > 0 or s.inventory.count_of(&"knife") > 0
