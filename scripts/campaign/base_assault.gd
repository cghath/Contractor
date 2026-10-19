class_name BaseAssault
extends Node
## Assaults on the base (docs/linked_zones.md 1b, calls 12 and 17; LZ-5): trouble the company
## causes comes home. When the campaign's days turn over (BaseHub.server_advance_days) and the
## faction hottest against the company (BaseZoneLevel.hottest) is at ASSAULT_HEAT or more, with no
## assault in the last WEEK_DAYS, it books one for the next day, and everyone is warned (the
## board's notices). On that day:
## - the squad at the base (the base zone up, on the host: this node, in BaseZoneLevel) fights it
##   live: TEAMS teams of TEAM_SIZE come in from the edge and push onto the FOB; beaten, the
##   faction's heat cools by BEATEN_COOL;
## - the squad out (a deployment running): it resolves off-screen. The FOB's own detail holds it,
##   but up to LOSSES of the stash's piles are halved (taken or wrecked at the wire), the faction's
##   heat cools by OFFSCREEN_COOL, and a situation report goes out.
## The booking lives in the campaign's "base" section ("assault": {"faction", "day"};
## "last_assault_day"). Numbers Proposed.

const NODE_NAME := "BaseAssault"
const WEEK_DAYS := 7
const TEAMS := 2
const TEAM_SIZE := 6
const START_M := 950.0  # from the FOB: where the teams form up, out of sight
const BEATEN_COOL := 25.0
const OFFSCREEN_COOL := 10.0
const LOSSES := 3
const CHECK_S := 2.0

var teams: Array = []  # host: [[Soldier]] while the live assault runs
var _check := 0.0


## Host (BaseHub.server_advance_days): books an assault for tomorrow when the heat calls for one,
## and settles one whose day came while the squad was out. Returns what happened, or "".
static func server_day_passed(at_base: bool) -> String:
	var base := BaseHub.base()
	var booked: Dictionary = base.get("assault", {})
	if not booked.is_empty() and int(booked.day) <= BaseHub.day() and not at_base:
		return _resolve_offscreen(booked)
	if booked.is_empty():
		var hot := BaseZoneLevel.hottest()
		var last := int(base.get("last_assault_day", -1000))
		if String(hot[0]) != "" and float(hot[1]) >= BaseZoneLevel.ASSAULT_HEAT and BaseHub.day() - last >= WEEK_DAYS:
			base["assault"] = {"faction": String(hot[0]), "day": BaseHub.day() + 1}
			var who := String(MissionRegistry.faction(String(hot[0])).get("name", String(hot[0]).capitalize()))
			var warn := "Intel: %s are massing to hit the FOB tomorrow (day %d)." % [who, BaseHub.day() + 1]
			Contracts._notify_all(warn)
			SessionLog.note("base assault booked: %s on day %d (heat %.0f)" % [hot[0], BaseHub.day() + 1, float(hot[1])])
			return warn
	return ""


## The squad was out on the day: the FOB's detail held, the wire paid for it.
static func _resolve_offscreen(booked: Dictionary) -> String:
	var base := BaseHub.base()
	var stash: Array = BaseHub.stash()
	var lost := PackedStringArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([BaseHub.day(), String(booked.faction)])
	var guards := BaseHub.guards()
	var losses := 0 if guards >= 4 else maxi(LOSSES - guards / 2, 0)  # the guards hold the wire (LZ-6)
	if guards > 0 and guards < 4:
		base["guards"] = guards - 1  # stretched thin: one of them falls
	for k in mini(losses, stash.size()):
		var i := rng.randi_range(0, stash.size() - 1)
		var e: Dictionary = stash[i]
		var gone := ceili(int(e.get("count", 1)) * 0.5)
		e["count"] = int(e.get("count", 1)) - gone
		lost.append("%d %s" % [gone, ItemDB.get_item(StringName(e.id)).name if ItemDB.get_item(StringName(e.id)) else String(e.id)])
		if int(e.count) <= 0:
			stash.remove_at(i)
	base.erase("assault")
	base["last_assault_day"] = BaseHub.day()
	Economy.add_heat(String(booked.faction), -OFFSCREEN_COOL)
	var held := "the guards (%d) held them off" % guards if guards > 0 else "the detail held them off"
	var report := "Situation report: the FOB was hit while you were out: %s; lost at the wire: %s%s." % [held, ", ".join(lost) if not lost.is_empty() else "nothing",
		", and a guard" if guards > 0 and guards < 4 else ""]
	Contracts._notify_all(report)
	SessionLog.note("base assault resolved off-screen: %s" % ", ".join(lost))
	return report


## Host, the base zone up: today's booked assault (if any) comes in live.
func server_check_due() -> void:
	var booked: Dictionary = BaseHub.base().get("assault", {})
	if booked.is_empty() or int(booked.day) > BaseHub.day() or not teams.is_empty():
		return
	var level := get_parent() as BaseZoneLevel
	var response := level.get_node_or_null(^"EnemyResponse") as EnemyResponse if level else null
	if level == null or response == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([BaseHub.day(), String(booked.faction), "assault"])
	var a0 := rng.randf() * TAU
	var centre := level.fob.global_position
	for t in TEAMS:
		var a := a0 + (t - 0.5) * 0.7
		var out := Vector3(cos(a), 0.0, sin(a))
		var origin := level.ground_point(centre + out * START_M)
		var near := level.ground_point(centre + out * (BaseFob.PERIMETER_HALF + 30.0))
		var squad := response._new_squad("BA%d" % (t + 1))
		var route: Array[Vector3] = [near, level.ground_point(centre)]
		squad.patrol = route
		var loadout: Array = CompoundLevel.HOSTILE_LOADOUT.duplicate()
		var men: Array = response._spawn_team(squad, "BA%d" % (t + 1), TEAM_SIZE, origin, route[0], loadout, 0.55, 0.6, "combat")
		teams.append(men)
	Contracts._notify_all("The FOB is under attack: about %d men coming in." % (TEAMS * TEAM_SIZE))
	SessionLog.note("base assault: %d teams in from %.0f m" % [TEAMS, START_M])


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = CHECK_S
	if teams.is_empty():
		server_check_due()
		return
	var up := 0
	for men: Array in teams:
		for s: Variant in men:
			if is_instance_valid(s) and (s as Soldier).vitals.is_up():
				up += 1
	if up == 0:
		var booked: Dictionary = BaseHub.base().get("assault", {})
		BaseHub.base().erase("assault")
		BaseHub.base()["last_assault_day"] = BaseHub.day()
		Economy.add_heat(String(booked.get("faction", "")), -BEATEN_COOL)
		teams.clear()
		Contracts._notify_all("The assault on the FOB is beaten off.")
		SessionLog.note("base assault beaten off")
