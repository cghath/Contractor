class_name CoopFallen
extends Node
## Drop-in co-op and the shared journal for Contractor: Fallen (docs/survival_events.md; calls 27,
## 51, 126): a child of the Survival autoload ("CoopFallen", the same path on every peer).
##
## - A friend joins a running world as a newcomer: at the farm (the safehouse; SurvivalLevel's
##   _player_start asks join_point), or beside the host when the host allows it (the world option
##   "join": "farm" | "host"), with the starter kit and a blank slate (Survival.server_survivor_joined;
##   the survivor picker for a joiner is later: a client message); the journal line names him.
## - The journal and the map are shared: the host sends the journal's view (JournalScreen.view) to a
##   peer on join and to every peer when it changes (a digest checked every TICK_S); the map's marks
##   already sync (SurvivalMap).
## - Companions remember who did what: server_deed(actor, what, by): every companion and settler's
##   opinion of that player's profile moves `by` and they keep the line ("remembers": the last
##   MEMORY of them, by profile and name); events can carry the actor's profile ("actor").
## - Leaving players' survivors sleep at the safehouse: on disconnect their kit and needs are stored,
##   the body removed (CompoundLevel) and the record marked asleep at home; on return he wakes there.
## - A player's death in co-op is the existing permadeath per profile (Survival.server_player_died).
## Every number Proposed.

const NODE_NAME := "CoopFallen"
const TICK_S := 2.0
const MEMORY := 12
## Beside the host: this far off him.
const BESIDE_M := 2.5

## Host: what the last push sent ({"peers": [ids], "payload": view}) and how many pushes (tests).
var last_push := {}
var pushes := 0
## Client: the host's journal view as last sent.
var shared_view := {}

var _tick := 0.0
var _digest := ""


func _init() -> void:
	name = NODE_NAME


static func get_coop() -> CoopFallen:
	return Survival.get_node_or_null(NodePath(NODE_NAME)) as CoopFallen


## The world option for where joiners come in: "farm" (default) or "host".
static func join_mode() -> String:
	var opts: Dictionary = Survival.state().get("options", {})
	return "host" if String(opts.get("join", "farm")) == "host" else "farm"


## Where home is on the ground of `level` (the safehouse): the settlement's middle, else the farm's
## mark, else the zone's first insertion point. Only in the farm's zone; elsewhere the insertion.
static func home_point(level: ZoneLevel) -> Vector3:
	var st := Survival.state()
	if String(st.get("zone", "")) == String(st.get("start_zone", "")):
		if Settlement.exists():
			return level.ground_point(Settlement.pos() + Vector3(1.5, 0.0, 1.5))
		var safe := SurvivalMap.safehouse()
		if not safe.is_empty():
			var p := SurvivalMap.mark_pos(safe)
			return level.ground_point(Vector3(p.x + 1.5, 0.0, p.y + 1.5))
	var points := level.insertion_points()
	return level.ground_point(points[0]) if not points.is_empty() else level.ground_point(Vector3.ZERO)


## Host: where peer `peer` comes into `level`: beside the host when the world allows it and the host
## is up, else home (an asleep survivor always wakes at home).
static func join_point(level: ZoneLevel, peer: int) -> Vector3:
	var rec: Dictionary = (Campaign.section(Survival.SURVIVORS) as Dictionary).get("peer_%d" % peer, {})
	if join_mode() == "host" and not bool(rec.get("asleep", false)):
		var host := level.players.get_node_or_null(^"1") as Soldier
		if host and host.vitals and host.vitals.is_up():
			var a := float(peer) * 1.3
			return level.ground_point(host.global_position + Vector3(cos(a), 0.0, sin(a)) * BESIDE_M)
	return home_point(level)


# --- Joining and leaving -------------------------------------------------------------------------

## Host: `s` came in (SurvivalLevel._add_player, after Survival.server_survivor_joined): a
## newcomer's or a sleeper's journal line, the journal sent to him, his place told to his client.
## Returns "host", "newcomer", "woke" or "back".
func server_on_joined(s: Soldier) -> String:
	var how := server_arrive(s)
	if s.owner_peer() != 1:
		server_push([s.owner_peer()], true)
		var level := CompoundLevel.current(s)
		if level is ZoneLevel:
			var at := join_point(level as ZoneLevel, s.owner_peer()) if how != "back" else s.global_position
			if s.owner_peer() in multiplayer.get_peers():
				_client_place.rpc_id(s.owner_peer(), at)
	return how


## Host: the record side of an arrival (no network): a first join is a newcomer at the farm, an
## asleep one wakes at home; the host's own survivor is "host".
static func server_arrive(s: Soldier) -> String:
	var all: Dictionary = Campaign.section(Survival.SURVIVORS)
	var profile := Survival.profile_of(s)
	var rec: Dictionary = all.get(profile, {})
	if s.owner_peer() == 1 and not s.has_meta(&"fallen_profile"):
		return "host"
	var who := String(rec.get("name", s.log_name()))
	if bool(rec.get("asleep", false)):
		rec.erase("asleep")
		rec["woke_day"] = Survival.day()
		Intel.journal("%s woke at the farm." % who, "coop", who)
		return "woke"
	if not bool(rec.get("joined", false)):
		rec["joined"] = true
		rec["newcomer"] = true
		rec["joined_day"] = Survival.day()
		Intel.journal("%s came to the farm: a newcomer, with nothing but what they carried." % who if join_mode() == "farm"
			else "%s turned up beside us: a newcomer." % who, "coop", who)
		return "newcomer"
	return "back"


## Host: `s` is leaving (SurvivalLevel._on_peer_left, before the body goes): his kit and needs into
## his record (none if he leaves down: the body keeps them), asleep at home. Returns the record.
static func server_left(s: Soldier) -> Dictionary:
	var all: Dictionary = Campaign.section(Survival.SURVIVORS)
	var profile := Survival.profile_of(s)
	var level := CompoundLevel.current(s)
	var up := s.vitals == null or s.vitals.is_up()
	if up:
		Survival._store_survivor(s)
	var rec: Dictionary = all.get(profile, {})
	if not up:
		rec.erase("kit")  # (his gear stays on the body he left behind: he wakes with a starter kit)
	rec["asleep"] = true
	rec["zone"] = String(Survival.state().get("start_zone", ""))
	if level is ZoneLevel:
		var home := home_point(level as ZoneLevel)
		rec["pos"] = [home.x, home.y, home.z]
	all[profile] = rec
	Intel.journal("%s went to sleep at the farm." % String(rec.get("name", s.log_name())), "coop", String(rec.get("name", "")))
	return rec


@rpc("authority", "call_remote", "reliable")
func _client_place(at: Vector3) -> void:
	for i in 120:
		var level := CompoundLevel.current(self)
		var me: Soldier = level.players.get_node_or_null(str(multiplayer.get_unique_id())) as Soldier if level else null
		if me:
			me.global_position = at
			return
		await get_tree().process_frame


# --- Who did what ------------------------------------------------------------------------------

## Host: `actor` did `what` (a line in the third person: "rang the bell and called the dead"): every
## companion and settler's opinion of his profile moves `by` and they remember it.
static func server_deed(actor: Soldier, what: String, by: float) -> int:
	if actor == null:
		return 0
	var profile := Survival.profile_of(actor)
	var who := Survival.survivor_name(actor)
	var n := 0
	for rec: Dictionary in WorldSim.people().values():
		if not String(rec.get("status", "")) in ["companion", "settler"]:
			continue
		SurvivorPerson.change_opinion(rec, profile, by)
		var mem: Array = rec.get("remembers", [])
		mem.append({"profile": profile, "who": who, "what": what, "by": by, "day": Survival.day()})
		rec["remembers"] = mem.slice(-MEMORY)
		n += 1
	return n


## What `rec` remembers of `profile`'s survivors: [lines] ("Sam Reed rang the bell...").
static func memories_of(rec: Dictionary, profile: String) -> Array:
	var out: Array = []
	for m: Dictionary in rec.get("remembers", []):
		if String(m.get("profile", "")) == profile:
			out.append("%s %s" % [String(m.get("who", "")), String(m.get("what", ""))])
	return out


# --- The shared journal ------------------------------------------------------------------------

## The payload a peer gets: the journal's view (every tab) and the world's day.
static func payload() -> Dictionary:
	return {"journal": JournalScreen.view(), "day": Survival.day(), "hour": snappedf(Survival.hour(), 0.1)}


## A digest of what the journal shows (its last entry, the marks, the deadlines): a push when it moves.
static func digest() -> String:
	var j: Array = Survival.state().get("journal", [])
	var last: Dictionary = j[j.size() - 1] if not j.is_empty() else {}
	var marks: Array = (Survival.state().get("map", {}) as Dictionary).get("marks", [])
	return "%d|%s|%d|%d" % [j.size(), String(last.get("text", "")), marks.size(), (Survival.state().get("deadlines", []) as Array).size()]


## Host: the journal to `peers` (every connected peer but the host when empty), when it changed or
## `force`. Records the push (last_push) even with nobody to send it to. Returns whether it pushed.
func server_push(peers: Array = [], force := false) -> bool:
	var d := digest()
	if d == _digest and not force:
		return false
	_digest = d
	var to: Array = peers if not peers.is_empty() else Array(multiplayer.get_peers()) if multiplayer.has_multiplayer_peer() else []
	var p := payload()
	last_push = {"peers": to.duplicate(), "payload": p}
	pushes += 1
	for peer: Variant in to:
		if int(peer) != 1 and multiplayer.has_multiplayer_peer() and int(peer) in multiplayer.get_peers():
			_client_journal.rpc_id(int(peer), p)
	return true


@rpc("authority", "call_remote", "reliable")
func _client_journal(p: Dictionary) -> void:
	shared_view = p
	var js := JournalScreen.current()
	if js and p.get("journal") is Dictionary:
		js.show_view(p.journal)


## Host: every TICK_S: the journal pushed when it changed, the loot states' clue marks.
func server_tick(level: Node) -> void:
	server_push()
	LootStates.server_tick(level)


func _process(delta: float) -> void:
	if not Survival.running or not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	_tick += delta
	if _tick < TICK_S:
		return
	_tick = 0.0
	var level := CompoundLevel.current(self)
	if level is SurvivalLevel:
		server_tick(level)
