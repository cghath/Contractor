class_name PersonLook
extends RefCounted
## What civilians, HVTs and hostages wear: plain clothes on the same voxel body, coloured by
## VoxelArt's plain-clothes scheme ("civ:<shirt>:<trousers>:<skin>:<shoes>", VoxelArt.spec):
## no uniform, no camo, no unit patch, bare hands. The host picks the outfit (outfit()) and
## it travels in the spawn data, so every peer and a saved body show the same.
##
## Captain: an HVT's clothes depend on several things. Proposed factors (all from the spawn):
## - side: a hostile HVT, or a friendly hostage;
## - role, rolled from the name: a hostile HVT is a commander, a financier or a bomb maker; a
##   hostage an aid worker, an engineer, a journalist or a contractor;
## - site (the module they're held at): a financier at a village or compound blends in, in
##   local dress; a commander at an outpost or checkpoint wears field clothes;
## - region (its people's skin tones; local dress where the region has it);
## - captivity: a hostage's clothes are worn and dirty.
## Civilians: local dress or everyday clothes, by name.

## Colours (hex). Local dress is one long garment, so its "shirt" and "trousers" match.
const LOCAL_DRESS: Array[String] = ["e8e4d8", "d9cfb6", "a8a49a", "8a7258", "c4b9a0"]
const SHIRTS: Array[String] = ["d8d2c0", "7a8fa6", "a65e48", "6b7f4f", "c9a85a", "4f4a6b", "b8b8b0", "5e6e7e"]
const TROUSERS: Array[String] = ["3b4a63", "9c8a64", "5f5f5f", "2b2b2b", "6a5a44"]
const SHOES: Array[String] = ["6b4a2b", "2e2a26", "4a3f35"]
const SKINS: Array[String] = ["c8996f", "b07a52", "8d5b3e", "e0b48f", "6e4630"]
## Proposed role outfits: [shirts], [trousers] (an empty trousers list: local dress, matching).
const ROLES := {
	&"commander": {"weight": 1.0, "shirt": ["5b5e3c", "6b6247", "4a4a40"], "trousers": ["6a5a44", "4a4a40", "3b3b34"]},
	&"financier": {"weight": 1.0, "shirt": ["2f3136", "3a3530", "f0ece2"], "trousers": ["2f3136", "26262a"]},
	&"bomb_maker": {"weight": 0.7, "shirt": ["5f6b78", "7a7468", "4f5560"], "trousers": ["3b3b3b", "4a4438"]},
	&"aid_worker": {"weight": 1.0, "shirt": ["e8e8e2", "9fb8cc", "d8d2c0"], "trousers": ["9c8a64", "3b4a63"]},
	&"engineer": {"weight": 1.0, "shirt": ["c86a2a", "d9b43a", "5e6e7e"], "trousers": ["2f3a4a", "3b3b3b"]},
	&"journalist": {"weight": 0.7, "shirt": ["b8b8b0", "7a8fa6", "a69a80"], "trousers": ["3b4a63", "5f5f5f"]},
	&"contractor": {"weight": 0.8, "shirt": ["c9b38a", "6b6247", "3a3d42"], "trousers": ["9c8a64", "5f5f5f"]},
}
const HOSTILE_ROLES: Array[StringName] = [&"commander", &"financier", &"bomb_maker"]
const HOSTAGE_ROLES: Array[StringName] = [&"aid_worker", &"engineer", &"journalist", &"contractor"]
## Sites where an HVT dresses to blend in, and where he's in the field.
const TOWN_SITES: Array[String] = ["village", "compound", "town"]
const FIELD_SITES: Array[String] = ["outpost", "checkpoint"]
## How worn a hostage's clothes look (darkened by this share).
const CAPTIVE_WEAR := 0.22


## Host: the outfit for a person (a variant for Soldier.variant). `factors`: "name" (seeds the
## picks, so the same person always dresses the same), "site" (module type), "local_dress"
## (whether the region has it; default true for the current setting), "role" (to force one).
static func outfit(kind: StringName, side: StringName, factors: Dictionary = {}) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(factors.get("name", "")))
	var skin: String = SKINS[rng.randi() % SKINS.size()]
	var shoes: String = SHOES[rng.randi() % SHOES.size()]
	var local := bool(factors.get("local_dress", true))
	if kind != Person.HVT:
		if local and rng.randf() < 0.5:
			var robe: String = LOCAL_DRESS[rng.randi() % LOCAL_DRESS.size()]
			return _variant(robe, robe, skin, shoes)
		return _variant(SHIRTS[rng.randi() % SHIRTS.size()], TROUSERS[rng.randi() % TROUSERS.size()], skin, shoes)
	var hostage := side == Person.FRIENDLY
	var role := StringName(factors.get("role", ""))
	if not ROLES.has(role):
		role = role_for(rng, HOSTAGE_ROLES if hostage else HOSTILE_ROLES)
	var site := ZoneModules.base(String(factors.get("site", "")))
	var r: Dictionary = ROLES[role]
	var shirt: String = r.shirt[rng.randi() % r.shirt.size()]
	var trousers: String = r.trousers[rng.randi() % r.trousers.size()]
	if not hostage and local and site in TOWN_SITES and role != &"commander":
		shirt = LOCAL_DRESS[rng.randi() % LOCAL_DRESS.size()]  # blends in where he lives
		trousers = shirt
	elif role == &"commander" and site in FIELD_SITES:
		shoes = "3a3027"  # boots with the field clothes
	if hostage:
		shirt = Color(shirt).darkened(CAPTIVE_WEAR).to_html(false)
		trousers = Color(trousers).darkened(CAPTIVE_WEAR).to_html(false)
	return _variant(shirt, trousers, skin, shoes)


## The role leader `title` of `faction` dresses as when an HVT job names him (factions.json
## "leader_roles": the Bookkeeper a financier, the Chemist a bomb maker); a commander when it
## says nothing or names no HOSTILE_ROLES role.
static func leader_role(faction: String, title: String) -> StringName:
	var role := StringName(String((MissionRegistry.faction(faction).get("leader_roles", {}) as Dictionary).get(title, "")))
	return role if role in HOSTILE_ROLES else &"commander"


## A role from `roles` by weight.
static func role_for(rng: RandomNumberGenerator, roles: Array[StringName]) -> StringName:
	var total := 0.0
	for role in roles:
		total += float(ROLES[role].weight)
	var pick := rng.randf() * total
	for role in roles:
		pick -= float(ROLES[role].weight)
		if pick <= 0.0:
			return role
	return roles[roles.size() - 1]


static func _variant(shirt: String, trousers: String, skin: String, shoes: String) -> String:
	return "%s%s:%s:%s:%s" % [VoxelArt.CIV_PREFIX, shirt, trousers, skin, shoes]
