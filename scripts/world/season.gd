class_name Season
extends RefCounted
## The season (queue item 1.3 of docs/cg_brief.md: farmland's crops by season, the snow line on
## the snow preset). There was none: DayNight keeps the hour, the economy the campaign day
## (Economy.day()). The call (logged in docs/audits/followups.md): a simple deterministic year
## from the campaign day, SEASON_DAYS days a season starting with START (Proposed: a campaign
## month a season, so a long campaign sees the year turn).
## The host puts it in a zone's def ("season", BaseHub.server_switch_level) so every peer and
## late joiner builds the same fields and snow; a def without one (the main menu's test zones,
## tests) is DEFAULT.

const ALL: Array[String] = ["spring", "summer", "autumn", "winter"]
const SEASON_DAYS := 30
const START := "spring"
const DEFAULT := "summer"


## The season on campaign day `day` (day 1 is the first day of START).
static func of_day(day: int) -> String:
	var k := floori(float(maxi(day, 1) - 1) / SEASON_DAYS) + ALL.find(START)
	return ALL[posmod(k, ALL.size())]


## A zone def's season ("season", DEFAULT without a known one).
static func of_def(def: Dictionary) -> String:
	var s := String(def.get("season", DEFAULT))
	return s if s in ALL else DEFAULT
