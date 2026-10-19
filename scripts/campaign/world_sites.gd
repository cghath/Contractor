class_name WorldSites
extends RefCounted
## Wave 6c: persistent world + the faction war between missions (design doc
## "mission_brainstorm.md"; build order in docs/wave6_groundwork.md #3). Proposed scope: the
## real faction set (that doc's call #4) is still a placeholder, so this runs on whatever
## factions.json has today (Black Ridge, the Eastern Concord Forces, ...; the placeholder set until wave 6b's call 4 landed) rather than waiting
## on it.
##
## A hot zone's current holder and how firm its grip is (0..1) persist across deployments in
## the campaign (section "world_sites"), the same way EnemyCommand's own per-zone "caution"
## already outlives a deployment:
## - A contract the squad completes against the faction holding a zone knocks its grip down
##   (server_contract_won); at CONTESTED_GRIP or below it's weak enough to lose.
## - Between deployments (server_advance_days, called from Economy.advance_days): a weak grip
##   has a TAKEOVER_CHANCE a day of flipping to one of the holder's own listed enemies (the
##   faction war takes the ground) - the new holder starts at TAKEOVER_GRIP, not consolidated
##   yet, and the zone is flagged a "flashpoint". Otherwise grip repairs back up by
##   REPAIR_PER_DAY - "damage is repaired, lost positions reoccupied".
## - Contracts.server_refresh_board posts a flashpoint's own offer (ContractGen.generate with
##   ctx.target set to the new holder), flagging it war_driven (title and brief say a faction
##   just took it) and clearing the flag (server_clear_flashpoint) once it has. Every other
##   contract still picks its target the way it always did (kept RNG-sequence-stable for
##   existing callers, HotZoneOps included) - this only ever names a target through ctx.target.

const SECTION := &"world_sites"
const START_GRIP := 0.8
const TAKEOVER_GRIP := 0.55
const REPAIR_PER_DAY := 0.06
const WIN_GRIP_HIT := 0.3
## At or below this grip, one of the holder's own listed enemies can take the zone over.
const CONTESTED_GRIP := 0.3
## A contested zone's daily chance of flipping to a rival (server_advance_days).
const TAKEOVER_CHANCE := 0.2


static func _section() -> Dictionary:
	return Campaign.section(SECTION)


## `zone_id`'s site, seeded the first time it's asked: a stable pick (by the zone id's own hash,
## so a fresh campaign always starts the same way) among the known hostile factions.
static func site(zone_id: String) -> Dictionary:
	var s := _section()
	if not s.has(zone_id):
		var enemies := MissionRegistry.enemies()
		var holder := String(enemies[hash(zone_id) % enemies.size()]) if not enemies.is_empty() else ""
		s[zone_id] = {"holder": holder, "grip": START_GRIP, "flashpoint": false}
	return s[zone_id]


## The faction holding `zone_id` now, or "" for a zone never seeded (not hot, or not asked yet).
static func holder(zone_id: String) -> String:
	return String(site(zone_id).get("holder", ""))


static func grip(zone_id: String) -> float:
	return float(site(zone_id).get("grip", START_GRIP))


static func is_flashpoint(zone_id: String) -> bool:
	return bool(site(zone_id).get("flashpoint", false))


## Grip at or above this reads as "firm" on the board.
const FIRM_GRIP := 0.7


## Every hot zone's holder and grip, for the contract board (wave 6c, the zone UI): [{"zone_id",
## "name", "holder", "holder_name", "grip", "state" ("firm", "holding", "contested"),
## "flashpoint"}], in zones.json order. Host: from the campaign (seeding any not asked yet);
## Economy's sync carries it to every other peer (Economy._public, "world_sites").
static func rows() -> Array:
	var out: Array = []
	for z: Dictionary in MissionRegistry.data().get("zones", []):  # raw: zones() would build every layout
		if String(z.get("kind", "")) != "hot":
			continue
		var zid := String(z.zone_id)
		var s := site(zid)
		var g := float(s.get("grip", START_GRIP))
		out.append({"zone_id": zid, "name": String(z.get("name", zid)), "holder": String(s.get("holder", "")),
			"holder_name": MissionRegistry.faction_name(String(s.get("holder", ""))), "grip": g,
			"state": "contested" if g <= CONTESTED_GRIP else ("firm" if g >= FIRM_GRIP else "holding"),
			"flashpoint": bool(s.get("flashpoint", false))})
	return out


## One row of rows() as a line of text.
static func row_text(r: Dictionary) -> String:
	return "%s: %s, grip %d%% (%s)%s" % [r.name, r.holder_name if String(r.holder) != "" else "nobody", roundi(float(r.grip) * 100.0),
		r.state, ", flashpoint: a war job is up" if bool(r.flashpoint) else ""]


## ContractGen, once a flashpoint job has gone on the board (its title/brief say so).
static func server_clear_flashpoint(zone_id: String) -> void:
	var s := site(zone_id)
	if bool(s.get("flashpoint", false)):
		s.flashpoint = false
		_section()[zone_id] = s
		Campaign.mark_changed(SECTION)


## Host: a completed contract against `target` in `zone_id` weakens its hold there (only the
## current holder's own grip is on the line: a rival's raid doesn't need the squad's help).
static func server_contract_won(zone_id: String, target: String) -> void:
	if zone_id == "" or target == "":
		return
	var s := site(zone_id)
	if String(s.holder) != target:
		return
	s.grip = maxf(0.0, float(s.grip) - WIN_GRIP_HIT)
	_section()[zone_id] = s
	Campaign.mark_changed(SECTION)


## Host, from Economy.advance_days: the faction war and repair tick for every tracked site.
## `rng`: real randomness (its own, randomized) unless a caller (a test) passes a seeded one.
static func server_advance_days(days: int, rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var s := _section()
	var changed := false
	for zone_id: String in s.keys():
		var site_d: Dictionary = s[zone_id]
		for _i in days:
			if float(site_d.grip) <= CONTESTED_GRIP and rng.randf() < TAKEOVER_CHANCE:
				var rivals := MissionRegistry.enemies_of(String(site_d.holder)).filter(
					func(f: String) -> bool: return f in MissionRegistry.enemies())
				if not rivals.is_empty():
					var taker := String(rivals[rng.randi() % rivals.size()])
					print("[world] %s takes %s from %s" % [MissionRegistry.faction_name(taker), zone_id, MissionRegistry.faction_name(String(site_d.holder))])
					site_d.holder = taker
					site_d.grip = TAKEOVER_GRIP
					site_d.flashpoint = true
					changed = true
					continue
			var repaired: float = minf(1.0, float(site_d.grip) + REPAIR_PER_DAY)
			if repaired != float(site_d.grip):
				site_d.grip = repaired
				changed = true
		s[zone_id] = site_d
	if changed:
		Campaign.mark_changed(SECTION)
