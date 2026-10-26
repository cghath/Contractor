class_name RpgLines
extends RefCounted
## The twelve skill lines of Contractor: Fallen's RPG layer (docs/survival_rpg.md section 1,
## calls 16, 82): each 0-10, levelled by doing. The XP curve is fast early and slow late: levels
## 1-4 need STEP_XP (60/120/240/480 XP: a few real hours of the work), 5-10 need 1,000 x (n-4)^2
## each (a season each). Proposed numbers, as the doc says.
##
## Separate from the campaign's SKILLS (Roster): these belong to the survivor record (Rpg).

const LINES: Array[String] = ["medical", "building", "melee", "firearms", "archery", "scavenging", "mechanics", "driving", "cooking", "fieldcraft", "fitness", "stealth"]
const MAX_LEVEL := 10
## Proposed (call 82): the XP each of levels 1-4 takes on its own.
const STEP_XP: Array[float] = [60.0, 120.0, 240.0, 480.0]
## Proposed (call 82): levels 5-10 each take LATE_XP x (n - 4)^2.
const LATE_XP := 1000.0

## What a level unlocks, per line (the doc's table; the character screen names the next one).
const UNLOCKS := {
	"medical": {1: "bandage and clean properly", 2: "read bleeding classes", 3: "splint, stitch", 4: "see infection stages", 5: "remove fragments", 6: "set bones well, transfuse", 7: "drain, full diagnosis", 8: "amputate", 9: "run the cure chain", 10: "teach it"},
	"building": {1: "builds 6% faster a level", 2: "tier 2 pieces", 3: "integrity in numbers", 4: "tier 3 pieces", 5: "templates", 6: "steel"},
	"melee": {1: "swings cost less stamina", 2: "heavy swing", 3: "wider parry window", 4: "silent kill with any blade", 6: "two-handed mastery"},
	"firearms": {1: "steadier sway and recoil", 2: "faster reloads", 3: "clear jams", 6: "craft a suppressor", 7: "reload ammo from components", 8: "gunsmithing"},
	"archery": {1: "faster draw", 2: "arrow recovery", 4: "bow making"},
	"scavenging": {1: "faster searches", 2: "better rolls", 3: "read a place's loot bias", 5: "spot hidden caches"},
	"mechanics": {1: "fit a battery", 2: "fit a tyre", 4: "engine work", 6: "rebuild a wreck", 9: "the dam or plant"},
	"driving": {1: "carts, handling", 2: "less fuel", 3: "towing"},
	"cooking": {1: "better meals", 2: "smoking", 4: "canning"},
	"fieldcraft": {1: "fires, boiled water", 2: "fire in rain, snares", 3: "tracking, horses", 4: "mushrooms", 5: "weather reading"},
	"fitness": {1: "+3 kg carried a level", 2: "more stamina", 3: "cold resistance"},
	"stealth": {1: "quieter movement", 2: "slower awareness rise", 4: "the masking play", 7: "crawl among walkers"},
}


## The XP level `n` takes on its own (from n-1 to n).
static func step_xp(n: int) -> float:
	if n <= 0:
		return 0.0
	if n <= STEP_XP.size():
		return STEP_XP[n - 1]
	return LATE_XP * pow(float(n - 4), 2.0)


## Total XP in a line to reach level `n` (0 for 0).
static func xp_for(n: int) -> float:
	var total := 0.0
	for i in range(1, clampi(n, 0, MAX_LEVEL) + 1):
		total += step_xp(i)
	return total


## The level `xp` total XP in a line makes.
static func level_of(xp: float) -> int:
	var n := 0
	while n < MAX_LEVEL and xp >= xp_for(n + 1) - 0.001:
		n += 1
	return n


## 0..1 of the way from this level to the next (1 at MAX_LEVEL).
static func progress(xp: float) -> float:
	var n := level_of(xp)
	if n >= MAX_LEVEL:
		return 1.0
	return clampf((xp - xp_for(n)) / step_xp(n + 1), 0.0, 1.0)


## The next unlock in `line` above `level`: [level, text], or [] past the last.
static func next_unlock(line: String, level: int) -> Array:
	var table: Dictionary = UNLOCKS.get(line, {})
	for n in range(level + 1, MAX_LEVEL + 1):
		if table.has(n):
			return [n, String(table[n])]
	return []


## The at/below/above-level rule (section 1): a task of `task_level` done at line level `level`
## earns full XP at its level, little below it (BELOW_MULT a level under, FAR_BELOW_MULT further)
## and a lot above it (+ABOVE_PER a level, up to ABOVE_CAP). `task_level` < 0: the task is at his
## level. Proposed numbers.
const BELOW_MULT := 0.3
const FAR_BELOW_MULT := 0.1
const ABOVE_PER := 0.5
const ABOVE_CAP := 3.0


static func task_mult(level: int, task_level: int) -> float:
	if task_level < 0 or task_level == level:
		return 1.0
	if task_level < level:
		return BELOW_MULT if level - task_level == 1 else FAR_BELOW_MULT
	return minf(1.0 + ABOVE_PER * float(task_level - level), ABOVE_CAP)


## The survivor level (section 2, call 83): one every SURVIVOR_XP of XP earned, each next one
## SURVIVOR_SLOW more (slowing). Proposed.
const SURVIVOR_XP := 1000.0
const SURVIVOR_SLOW := 0.25


static func survivor_xp_for(n: int) -> float:
	var total := 0.0
	for k in range(1, n + 1):
		total += SURVIVOR_XP * (1.0 + SURVIVOR_SLOW * float(k - 1))
	return total


static func survivor_level_of(earned: float) -> int:
	var n := 0
	while earned >= survivor_xp_for(n + 1) - 0.001 and n < 100:
		n += 1
	return n
