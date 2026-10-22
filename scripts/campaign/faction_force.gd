class_name FactionForce
extends RefCounted
## What a faction can field (docs/ai_tactics.md section 7; F1-F3). The Captain's rule
## (2026-10-22): terror groups start small (cells, teams, a few squads) and grow with recruits,
## money, weapons and territory in the living war, to field platoons or companies, and shrink when
## they lose; small, they're still formidable. State forces field full echelons from the start.
##
## - Per faction, kept in the war's save (WorldSites' "war" section, key "force"): "recruits",
##   "weapons" (kits) and "money". Men under arms = the fewer of recruits and weapons.
## - Each campaign day (WorldSites._tick_day): money from its zones (less where villagers stop
##   paying a predatory group), recruits from its territory, and spend_share of its money on men
##   and kits. A man killed costs a recruit and half a kit; a zone lost a share of both; a contract
##   the company wins against it some recruits.
## - Its echelon by men under arms: cell, team, squad, platoon, company (data "men_from"). State
##   forces are fixed at theirs ("state").
## - What it changes: garrison, patrol and hunter sizes and the enemy commander's reserves scale by
##   size_mult (the echelon's scale over the one it started at: 1.0 at the start, so hot zones keep
##   their tuned sizes until the war moves); terror groups small (cell, team) are veterans
##   (combat_bonus), lie in wait more (ambush_share) and hit and run (hit_and_run).
## Numbers in data/faction_force.json, Proposed.

const PATH := "res://data/faction_force.json"
const KEY := "force"

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		var parsed: Variant = JSON.parse_string(text) if text != "" else null
		_data = parsed if parsed is Dictionary else {"_missing": true}
	return _data


static func num(key: String, fallback := 0.0) -> float:
	return float(data().get(key, fallback))


## Whether `faction` is a state force (fixed echelon).
static func is_state(faction: String) -> bool:
	return (data().get("state", {}) as Dictionary).has(faction) and faction != "_about"


static func start_echelon(faction: String) -> String:
	if is_state(faction):
		return String(data().state[faction])
	return String((data().get("start_echelon", {}) as Dictionary).get(faction, "squad"))


## `faction`'s force record (made the first time: mid-band men for its starting echelon).
static func of(faction: String) -> Dictionary:
	var w := WorldSites._war()
	if not w.has(KEY):
		w[KEY] = {}
	var all: Dictionary = w[KEY]
	if not all.has(faction):
		var men := float((data().get("start_men", {}) as Dictionary).get(start_echelon(faction), 80))
		all[faction] = {"recruits": men, "weapons": men, "money": 0.0}
	return all[faction]


## Men under arms: recruits with a kit.
static func men(faction: String) -> int:
	if is_state(faction):
		return int((data().get("start_men", {}) as Dictionary).get(start_echelon(faction), 600))
	var f := of(faction)
	return floori(minf(float(f.recruits), float(f.weapons)))


## The largest unit `faction` can field now.
static func echelon(faction: String) -> String:
	if faction == "":
		return "platoon"
	if is_state(faction):
		return start_echelon(faction)
	return echelon_for(men(faction))


## The echelon for `n` men under arms (data "men_from").
static func echelon_for(n: int) -> String:
	var from: Dictionary = data().get("men_from", {})
	var out := "cell"
	for e: String in data().get("echelons", []):
		if n >= int(from.get(e, 0)):
			out = e
	return out


## Garrison, patrol and reserve sizes now over those at its start (1.0 at the start).
static func size_mult(faction: String) -> float:
	if faction == "" or not MissionRegistry.faction(faction).has("id"):
		return 1.0
	var scale: Dictionary = data().get("size_scale", {})
	var now_s := float(scale.get(echelon(faction), 1.0))
	var start_s := float(scale.get(start_echelon(faction), 1.0))
	return clampf(now_s / start_s, 0.4, 2.0) if start_s > 0.0 else 1.0


static func _small(faction: String) -> bool:
	return not is_state(faction) and echelon(faction) in (data().get("hit_and_run", []) as Array)


## A small terror group's men are its hard core: veterans.
static func combat_bonus(faction: String) -> float:
	if faction == "" or not MissionRegistry.faction(faction).has("id"):
		return 0.0
	return num("veteran_combat", 0.1) if _small(faction) else 0.0


## The share of its patrols that lie in wait instead of looking (more as it shrinks).
static func ambush_share(faction: String, base: float) -> float:
	if faction == "" or not MissionRegistry.faction(faction).has("id"):
		return base
	return maxf(base, float((data().get("ambush_share", {}) as Dictionary).get(echelon(faction), base)))


## Whether it hits and runs (a heavy volley, then breaking contact before it's fixed).
static func hit_and_run(faction: String) -> bool:
	return faction != "" and MissionRegistry.faction(faction).has("id") and _small(faction)


# --- The war ----------------------------------------------------------------------------------------

## Host (WorldSites._tick_day): a day's money, recruits and spending for every warring faction.
static func tick_day() -> void:
	for f: String in WorldSites.warring():
		if is_state(f):
			continue
		var r := of(f)
		var zones := WorldSites.zones_of(f)
		var money := num("money_base", 4.0) + num("money_per_zone", 3.0) * zones.size()
		if bool(MissionRegistry.faction(f).get("predatory", false)):
			var cut := 0
			for z in zones:
				if WorldSites._support(z) >= WorldSites.SUPPORT_CUT:
					cut += 1
			money -= num("money_per_zone", 3.0) * num("predatory_cut", 0.25) * cut
		r.money = float(r.money) + maxf(money, 0.0)
		r.recruits = float(r.recruits) + num("recruits_per_zone", 2.0) * zones.size()
		var spend := float(r.money) * num("spend_share", 0.8)
		var per := num("recruit_cost", 1.0) + num("weapon_cost", 1.5)
		var bought := spend / per  # a man and his kit
		r.recruits = float(r.recruits) + bought
		r.weapons = float(r.weapons) + bought
		r.money = float(r.money) - spend
	Campaign.mark_changed(WorldSites.WAR)


## Host: one of `faction`'s men killed.
static func note_kill(faction: String) -> void:
	if faction == "" or is_state(faction) or not MissionRegistry.faction(faction).has("id"):
		return
	var r := of(faction)
	r.recruits = maxf(float(r.recruits) - num("kill_recruits", 1.0), 0.0)
	r.weapons = maxf(float(r.weapons) - num("kill_weapons", 0.5), 0.0)


## Host: `faction` lost a zone: its men and kits there.
static func note_zone_lost(faction: String) -> void:
	if faction == "" or is_state(faction) or not MissionRegistry.faction(faction).has("id"):
		return
	var r := of(faction)
	var k := 1.0 - num("zone_lost_share", 0.15)
	r.recruits = float(r.recruits) * k
	r.weapons = float(r.weapons) * k


## Host: the company beat `faction` in a contract.
static func note_defeat(faction: String) -> void:
	if faction == "" or is_state(faction) or not MissionRegistry.faction(faction).has("id"):
		return
	var r := of(faction)
	r.recruits = maxf(float(r.recruits) - num("defeat_recruits", 6.0), 0.0)
