class_name WorldSites
extends RefCounted
## The faction war between missions: who holds every zone, how firmly, and the fronts where
## somebody is trying to take one (wave 6c, made a living war 2026-10-20: the Captain, "the world
## needs to feel dynamic, zones change hands. different factions fight over different areas for
## different reasons"; docs/terror_groups.md section 7). Host-authoritative, saved in the campaign:
## section "world_sites" (zone id -> row) and section "war" (the factions' strength, the war's
## seed and day, the news, leaders taken, factions wiped out). Economy._public carries it all to
## every peer (rows() for the board's hot zones, war_view() for the map and the news).
##
## - Every zone with a "controller" in data/contracts.json is in the war, seeded from it (a hot
##   zone without one: a stable pick by its id, as before). A row: "holder", "grip" (0..1),
##   "flashpoint" (a war job is due), "front" ({"by": attacker, "since": day, "progress": 0..1}),
##   "flipped_day", "prev". A zone the company holds (ZoneControl) is the company's whatever its
##   row says; its row keeps who held it before.
## - What a zone is worth to a faction (worth()): 1 + its "war_wants" weights of the zone's
##   "assets" (village, mosque, crossing, route, harbour, oil, airfield, hq, fields) + "home" on its
##   home ground. That is why the Shura fights for villages and the cartels for crossings.
## - Strength (0-100 a faction, START_STRENGTH): income each day from the worth of what it holds,
##   UPKEEP for each zone; drained by its men killed (KILL_STRENGTH), contracts won against it,
##   its HQ and QRF bases taken out, fronts (ATTRITION a day each side) and lost attacks.
## - The daily tick (server_advance_days, from Economy.advance_days), one day at a time and the
##   same every time for a campaign (each roll seeded by the war's seed, the day and the zone):
##   1. income; 2. every front moves by the attacker's push against the holder's defence, and
##   flips the zone at 1 (a faction's last zone and the FOB's can be sieged but never fall:
##   SIEGE_CAP), fails at 0 or stalls after FRONT_MAX_DAYS; 3. one new front a day at most, while
##   fewer than MAX_FRONTS are open: the best-worth zone next to one a faction holds (RegionMap.
##   links), held by one of its enemies, the company or the locals; 4. grip repairs where nobody
##   is attacking.
## - The player shifts it: a contract won against a zone's holder knocks its grip and strength
##   and pushes any front there; HQ and QRF bases taken out knock more; kills drain strength.
##   Rebel support helps the locals: at SUPPORT_SLOW the predatory groups' (factions.json
##   "predatory") grip there repairs at half speed, at SUPPORT_CUT their income from the region is
##   cut, at SUPPORT_REBELS the locals' rebels open a front on a weak predatory zone themselves
##   (won, it is the rebels' own ground: REBELS); under SUPPORT_SHURA the people turn to the Shura.
## - Wiping a faction out (Captain, 2026-10-20): its last zone falls only to the company, and only
##   once its HQ and QRF bases there are down AND its leaders (factions.json "leaders": the HVTs
##   of hvt_capture and manhunt contracts won against it) are all taken. Then it is gone.
## - US forces in the war (D7, docs/combined_arms.md 7.3; Captain: "the Ashen Banner first, then
##   the Kestrel Cartel if the US wins"): an employer with "belligerent" in factions.json holds
##   ground like a faction (warring() has it) from FOB Halberd, a zone of its own that can't fall
##   (data "cant_fall"). It earns a flat income (a deployment budget, not land), opens one front of
##   its own at a time from its "fronts_from_day" (_belligerent_front, outside MAX_FRONTS) on its
##   war_target's zones next to its ground (or, with none next to it, the zone on the way to the
##   nearest), and turns on the next of its "war_next" when that one is wiped out (_wipe). While
##   its operation on a front is on the board or under way (Contracts, "op_front"), that front
##   waits; the operation's result moves it (server_operation_ended, 6.6). Unaccepted, the
##   operation expires and the front goes on by the tick. Any enemy of the US may attack its ground.
## All numbers Proposed (tuned in a model: about one zone changes hands every 3 days).

const SECTION := &"world_sites"
const WAR := &"war"
const START_GRIP := 0.8
const TAKEOVER_GRIP := 0.55
const REPAIR_PER_DAY := 0.06
const WIN_GRIP_HIT := 0.3
## At or below this grip a zone reads as contested (the map, the board).
const CONTESTED_GRIP := 0.3
## Grip at or above this reads as "firm" on the board.
const FIRM_GRIP := 0.7
## An HQ or QRF base taken out knocks this much more grip.
const SITE_GRIP_HIT := 0.15
const START_STRENGTH := 60.0
const MAX_STRENGTH := 100.0
const INCOME_BASE := 1.0
const INCOME_PER_WORTH := 0.1
const UPKEEP := 0.5
## A faction this strong or more may open a front.
const ATTACK_STRENGTH := 40.0
const MAX_FRONTS := 3
const OPEN_CHANCE := 0.6
const FRONT_START := 0.25
const FRONT_RATE := 0.5
const FRONT_NOISE := 0.15
const FRONT_MAX_DAYS := 6
## Strength each side loses a day of a front.
const ATTRITION := 1.5
## A front wears the holder's grip this much a day.
const SIEGE_GRIP := 0.06
const LOST_ATTACK := 8.0
const WIN_STRENGTH_HIT := 6.0
const SITE_STRENGTH_HIT := 10.0
const KILL_STRENGTH := 0.2
## A contract won in a zone with a front pushes it this far, against whoever the company hit.
const WIN_FRONT_PUSH := 0.25
## A zone that can't fall (a faction's last, the FOB's) is held at this progress: sieged.
const SIEGE_CAP := 0.9
## A defence spreads thin: past this many zones a holder defends each the less.
const SPREAD_ZONES := 4.0
## A faction defends its home ground this much harder.
const HOME_BONUS := 0.3
## How hard the company holds its own zones (0..1, as a faction's strength / 100), and its FOB's.
const COMPANY_DEFENCE := 0.55
const FOB_DEFENCE := 0.8
## Rebel support thresholds (RebelSupport, per region).
const SUPPORT_SLOW := 40.0
const SUPPORT_CUT := 60.0
const SUPPORT_REBELS := 80.0
const SUPPORT_SHURA := 20.0
## The locals' rebels as a holder or attacker (rebel support at SUPPORT_REBELS).
const REBELS := "rebels"
const NEWS_KEEP := 12
## Contracts that take a faction's leader (an HVT) when won against it.
const LEADER_TYPES: Array[String] = ["hvt_capture", "manhunt"]
## D7 (docs/combined_arms.md 6.6): what a belligerent's operation does to the war. Success flips the
## zone to it at OP_WIN_GRIP (+OP_WIN_STRENGTH for it, -OP_TARGET_HIT for the target); half the
## phases or more move its front that share of the way and knock the target's grip OP_PARTIAL_GRIP;
## less is a failure: -OP_FAIL_STRENGTH for it, +OP_FAIL_GRIP for the target. Proposed.
const OP_WIN_GRIP := 0.6
const OP_WIN_STRENGTH := 6.0
const OP_TARGET_HIT := 10.0
const OP_PARTIAL_GRIP := 0.2
const OP_FAIL_STRENGTH := 10.0
const OP_FAIL_GRIP := 0.1


static func _section() -> Dictionary:
	return Campaign.section(SECTION)


## The war's own state (section "war"), filled in the first time.
static func _war() -> Dictionary:
	var w := Campaign.section(WAR)
	if not w.has("seed"):
		var c := Campaign.section(&"contracts")
		w["seed"] = int(c.get("seed", 1))
		w["day"] = 0
		w["strength"] = {}
		w["news"] = []
		w["leaders_down"] = {}
		w["wiped"] = []
		w["last_zone"] = {}
	return w


## `zone_id`'s row, seeded the first time it's asked: its data "controller", else (a hot zone
## without one) a stable pick by the zone id's hash among the hostile factions.
static func site(zone_id: String) -> Dictionary:
	var s := _section()
	if not s.has(zone_id):
		s[zone_id] = {"holder": _first_holder(zone_id), "grip": START_GRIP, "flashpoint": false}
	return s[zone_id]


static func _first_holder(zone_id: String) -> String:
	var z := ZoneControl.zone_def_raw(zone_id)
	if String(z.get("controller", "")) != "":
		return String(z.controller)
	var enemies := MissionRegistry.enemies()
	return String(enemies[posmod(hash(zone_id), enemies.size())]) if not enemies.is_empty() else ""


## The zone ids in the war (every data zone with a "controller", in data order).
static func war_zones() -> Array[String]:
	var out: Array[String] = []
	for z: Dictionary in MissionRegistry.data().get("zones", []):
		if String(z.get("controller", "")) != "":
			out.append(String(z.zone_id))
	return out


static func is_war_zone(zone_id: String) -> bool:
	return String(ZoneControl.zone_def_raw(zone_id).get("controller", "")) != ""


## The faction holding `zone_id` now, or "" for a zone never seeded (not in the war, or not asked yet).
static func holder(zone_id: String) -> String:
	return String(site(zone_id).get("holder", ""))


## Who holds `zone_id` for the war: the company (ZoneControl.PLAYER) for a zone it took, else its holder.
static func holder_now(zone_id: String) -> String:
	return ZoneControl.PLAYER if ZoneControl.is_company(zone_id) else holder(zone_id)


static func grip(zone_id: String) -> float:
	return float(site(zone_id).get("grip", START_GRIP))


static func is_flashpoint(zone_id: String) -> bool:
	return bool(site(zone_id).get("flashpoint", false))


## The front in `zone_id` ({"by", "since", "progress"}), or {}.
static func front(zone_id: String) -> Dictionary:
	return site(zone_id).get("front", {})


## `zone_id`'s front as the campaign has it, without seeding a row (a zone level reads this: a
## test zone hosted on its own writes no campaign).
static func front_read(zone_id: String) -> Dictionary:
	return (Campaign.section(SECTION).get(zone_id, {}) as Dictionary).get("front", {})


## The zones with a front, in data order.
static func fronts() -> Array[String]:
	return war_zones().filter(func(z: String) -> bool: return not front(z).is_empty())


## A faction's strength (0-100).
static func strength(faction: String) -> float:
	return float((_war().strength as Dictionary).get(faction, float(_war_cfg(faction).get("start_strength", START_STRENGTH))))


## A faction's war numbers (factions.json "war": "start_strength", "income", "fronts_from_day"), or {}.
static func _war_cfg(faction: String) -> Dictionary:
	return MissionRegistry.faction(faction).get("war", {})


static func _add_strength(faction: String, amount: float) -> void:
	if faction == "" or faction == ZoneControl.PLAYER or faction == REBELS:
		return
	var st: Dictionary = _war().strength
	st[faction] = clampf(strength(faction) + amount, 0.0, MAX_STRENGTH)


## What `zone_id` is worth to `faction` (see the header).
static func worth(faction: String, zone_id: String) -> float:
	var wants: Dictionary = MissionRegistry.faction(faction).get("war_wants", {})
	var z := ZoneControl.zone_def_raw(zone_id)
	var w := 1.0
	for tag: Variant in z.get("assets", []):
		w += float(wants.get(String(tag), 0.0))
	if faction in (z.get("home", []) as Array):
		w += float(wants.get("home", 0.0))
	return w


## The zones `faction` holds (the company's not counted), in data order.
static func zones_of(faction: String) -> Array[String]:
	return war_zones().filter(func(z: String) -> bool: return holder_now(z) == faction)


## The factions in the war: the hostile ones still standing (not wiped out), then the belligerent
## employers (D7: the US).
static func warring() -> Array[String]:
	var wiped: Array = _war().wiped
	var out: Array[String] = []
	for f in MissionRegistry.enemies():
		if f not in wiped:
			out.append(f)
	out.append_array(belligerents())
	return out


## The employers that hold ground in the war (factions.json "belligerent": the US), in data order.
static func belligerents() -> Array[String]:
	var out: Array[String] = []
	for f: Dictionary in MissionRegistry.factions():
		if bool(f.get("belligerent", false)) and String(f.get("role", "")) != "hostile":
			out.append(String(f.id))
	return out


static func is_belligerent(faction: String) -> bool:
	return faction != "" and bool(MissionRegistry.faction(faction).get("belligerent", false))


## Who belligerent `faction` fights now: its "war_target", else the first of its "war_next" not
## wiped out (the Banner, then Kestrel: the Captain's order); "" once all are (its war is over and
## it holds what it has).
static func war_target(faction: String) -> String:
	var f := MissionRegistry.faction(faction)
	var order: Array = [String(f.get("war_target", ""))]
	order.append_array(f.get("war_next", []))
	for t: Variant in order:
		if String(t) != "" and not is_wiped(String(t)):
			return String(t)
	return ""


## Whether an operation for the front in `zone_id` is on the board or held (D7: that front waits for it).
static func operation_pending(zone_id: String) -> bool:
	var cs := Campaign.section(Contracts.SECTION)
	for c: Dictionary in (cs.get("board", []) as Array) + (cs.get("held", []) as Array):
		if String(c.get("op_front", "")) == zone_id:
			return true
	return false


static func is_wiped(faction: String) -> bool:
	return faction in (_war().wiped as Array)


## The leaders `faction` has lost (titles, factions.json "leaders"), and whether all of them.
static func leaders_down(faction: String) -> Array:
	return (_war().leaders_down as Dictionary).get(faction, [])


static func leaders_all_down(faction: String) -> bool:
	var all: Array = MissionRegistry.faction(faction).get("leaders", [])
	return leaders_down(faction).size() >= all.size()


## The next of `faction`'s leaders still free (the first in its "leaders" list not taken), ""
## when all are taken or it has none: the man an HVT job against it is after (ContractGen).
static func next_leader(faction: String) -> String:
	var down := leaders_down(faction)
	for title: Variant in MissionRegistry.faction(faction).get("leaders", []):
		if String(title) not in down:
			return String(title)
	return ""


## Whether `zone_id` can't fall to a front now: the FOB's, or a faction's last zone (Captain:
## "can be sieged but cannot fall unless the player explicitly wipes them out").
static func cant_fall(zone_id: String) -> bool:
	var h := holder_now(zone_id)
	if h == ZoneControl.PLAYER:
		return ZoneControl.control(zone_id) == ZoneControl.FOB
	if _held_by_data(zone_id, h):
		return true  # FOB Halberd (D7): its holder's base
	return h != REBELS and zones_of(h).size() <= 1


## Whether `zone_id` is a base that can't fall ("cant_fall" in data) and `h` is the one it belongs to.
static func _held_by_data(zone_id: String, h: String) -> bool:
	var z := ZoneControl.zone_def_raw(zone_id)
	return bool(z.get("cant_fall", false)) and h == String(z.get("controller", ""))


## Every zone in the war for the theatre map and the news ({"zone_id", "holder", "grip", "front",
## "flashpoint", "flipped_day"}), plus each faction's strength and the news.
static func war_view() -> Dictionary:
	var zones := {}
	for zid in war_zones():
		var r := site(zid)
		zones[zid] = {"holder": String(r.holder), "grip": snappedf(float(r.grip), 0.01), "front": (r.get("front", {}) as Dictionary).duplicate(),
			"flashpoint": bool(r.get("flashpoint", false)), "flipped_day": int(r.get("flipped_day", -1)), "prev": String(r.get("prev", ""))}
	var w := _war()
	var targets := {}
	for b in belligerents():
		targets[b] = war_target(b)
	return {"zones": zones, "strength": (w.strength as Dictionary).duplicate(), "news": (w.news as Array).duplicate(true),
		"day": int(w.day), "wiped": (w.wiped as Array).duplicate(), "targets": targets}


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
			"holder_name": holder_name(String(s.get("holder", ""))), "grip": g,
			"state": "contested" if g <= CONTESTED_GRIP or not front(zid).is_empty() else ("firm" if g >= FIRM_GRIP else "holding"),
			"flashpoint": bool(s.get("flashpoint", false))})
	return out


## A holder's name for the board and the news (the locals' rebels and the company included).
static func holder_name(faction: String) -> String:
	match faction:
		REBELS:
			return "the local rebels"
		ZoneControl.PLAYER:
			return "the company"
	return MissionRegistry.faction_name(faction)


static func _short(faction: String) -> String:
	match faction:
		REBELS:
			return "the local rebels"
		ZoneControl.PLAYER:
			return "the company"
	return MissionRegistry.faction_short(faction)


## One row of rows() as a line of text.
static func row_text(r: Dictionary) -> String:
	return "%s: %s, grip %d%% (%s)%s" % [r.name, r.holder_name if String(r.holder) != "" else "nobody", roundi(float(r.grip) * 100.0),
		r.state, ", flashpoint: a war job is up" if bool(r.flashpoint) else ""]


## The latest news lines, newest last ([{"day", "text", "zone_id", "kind"}]).
static func news() -> Array:
	return _war().news


static func _news(day: int, zone_id: String, kind: String, text: String) -> void:
	var n: Array = _war().news
	n.append({"day": day, "zone_id": zone_id, "kind": kind, "text": text})
	while n.size() > NEWS_KEEP:
		n.pop_front()
	print("[war] day %d: %s" % [day, text])


## ContractGen, once a flashpoint job has gone on the board (its title/brief say so).
static func server_clear_flashpoint(zone_id: String) -> void:
	var s := site(zone_id)
	if bool(s.get("flashpoint", false)):
		s.flashpoint = false
		_section()[zone_id] = s
		Campaign.mark_changed(SECTION)


## Host: a completed contract of `type` against `target` in `zone_id`: the holder's grip and
## strength knocked (only the holder's grip is on the line), any front there pushed against
## whoever the company hit, and a leader taken for an HVT job (LEADER_TYPES): `leader`, the one
## the job named (the contract's "leader"), else the next still free.
static func server_contract_won(zone_id: String, target: String, type := "", leader := "") -> void:
	if zone_id == "" or target == "":
		return
	_add_strength(target, -WIN_STRENGTH_HIT)
	if type in LEADER_TYPES:
		server_leader_down(target, leader)
	var s := site(zone_id)
	var f: Dictionary = s.get("front", {})
	if not f.is_empty():
		f["progress"] = clampf(float(f.progress) + (-WIN_FRONT_PUSH if String(f.by) == target else WIN_FRONT_PUSH), 0.0, 1.0)
	if String(s.holder) == target:
		s.grip = maxf(0.0, float(s.grip) - WIN_GRIP_HIT)
	_section()[zone_id] = s
	Campaign.mark_changed(SECTION)
	Campaign.mark_changed(WAR)


## Host: one of `faction`'s leaders is taken: `leader` if it's one of its "leaders" still free
## (the one an HVT job named; two jobs on the board can name the same man), else the next free.
static func server_leader_down(faction: String, leader := "") -> void:
	var all: Array = MissionRegistry.faction(faction).get("leaders", [])
	var down: Array = leaders_down(faction).duplicate()
	if leader == "" or leader not in all or leader in down:
		leader = next_leader(faction)
	if leader == "":
		return
	down.append(leader)
	(_war().leaders_down as Dictionary)[faction] = down
	_news(int(_war().day), "", "leader", "%s has lost %s." % [MissionRegistry.faction_name(faction), String(down.back())])
	Campaign.mark_changed(WAR)


## Host (ZoneControl, an HQ or QRF base taken out): the holder's grip and strength knocked.
static func server_site_down(zone_id: String) -> void:
	if not is_war_zone(zone_id):
		return
	var s := site(zone_id)
	s.grip = maxf(0.0, float(s.grip) - SITE_GRIP_HIT)
	_add_strength(String(s.holder), -SITE_STRENGTH_HIT)
	Campaign.mark_changed(SECTION)
	Campaign.mark_changed(WAR)


## Host: one of `faction`'s men is dead (CompoundLevel: a hostile with a "faction_id").
static func server_note_kill(faction: String) -> void:
	if faction == "" or not MissionRegistry.faction(faction).has("id"):
		return
	_add_strength(faction, -KILL_STRENGTH)
	Campaign.mark_changed(WAR)


## Host (ZoneControl, about to hand `zone_id` to the company): whether it may. A faction's last
## zone goes only once all its leaders are taken too; then the faction is wiped out.
static func server_company_takes(zone_id: String) -> bool:
	if not is_war_zone(zone_id):
		return true
	var h := holder(zone_id)
	if h == "" or h == REBELS or not MissionRegistry.faction(h).has("id") or zones_of(h).size() > 1:
		return true
	if not leaders_all_down(h):
		return false
	_wipe(h, zone_id)
	return true


static func _wipe(faction: String, zone_id: String) -> void:
	var w := _war()
	var was := {}
	for b in belligerents():
		was[b] = war_target(b)
	if faction not in (w.wiped as Array):
		(w.wiped as Array).append(faction)
	for z in war_zones():  # its fronts go with it
		var f := front(z)
		if not f.is_empty() and String(f.by) == faction:
			site(z).erase("front")
	_news(int(w.day), zone_id, "wiped", "%s is finished: its last ground at %s is gone and its leaders with it." % [MissionRegistry.faction_name(faction), RegionMap.zone_name(zone_id)])
	for b: String in was:  # D7: a belligerent whose enemy that was turns on the next (the Banner, then Kestrel)
		if String(was[b]) != faction:
			continue
		var next := war_target(b)
		var turns: Dictionary = MissionRegistry.faction(b).get("war_turns", {})
		if next != "":
			_news(int(w.day), "", "war_target", String(turns.get(next, "With %s broken, %s turn on %s." % [_short(faction), _short(b), _short(next)])))
		else:
			_news(int(w.day), "", "war_over", "With %s broken, the war of %s is over: they hold what they have." % [_short(faction), _short(b)])
	Campaign.mark_changed(WAR)
	Campaign.mark_changed(SECTION)


## Host (Contracts' debrief): a belligerent's operation (D7 stands one in as a contract with
## "op_front"; D3's operations report the same way) ended with `phases_done` of its phases (6.6).
## Its side is the employer if that's a belligerent, else "op_side" (Vessmark fights inside US
## operations); it and the target move by the OP_ numbers, on "covers" (else the front's zone). A
## zone that can't fall (the target's last) is sieged, not flipped; the company's is left alone.
static func server_operation_ended(contract: Dictionary, phases_done: int) -> void:
	var employer := String(contract.get("employer", ""))
	var side := employer if is_belligerent(employer) else String(contract.get("op_side", ""))
	var target := String(contract.get("target", ""))
	if not is_belligerent(side) or target == "":
		return
	var phases := maxi(1, int(contract.get("op_phases", (contract.get("phases", [1]) as Array).size())))
	var done := clampi(phases_done, 0, phases)
	var covers: Array = contract.get("covers", [])
	if covers.is_empty():
		covers = [String(contract.get("op_front", contract.get("zone_id", "")))]
	var day := int(_war().day)
	for zv: Variant in covers:
		var zid := String(zv)
		if not is_war_zone(zid):
			continue
		var r := site(zid)
		var h := holder_now(zid)
		var name := RegionMap.zone_name(zid)
		if done >= phases:
			if h != side and h != ZoneControl.PLAYER:
				if cant_fall(zid):
					r["front"] = {"by": side, "since": day, "progress": SIEGE_CAP, "sieged": true}
					_news(day, zid, "siege", "Siege at %s: %s hold all but the last ground of %s." % [name, _short(side), _short(h)])
				else:
					_flip(zid, side, h, day)
					r["grip"] = OP_WIN_GRIP
			_news(day, zid, "operation", "%s and the company carried the operation at %s." % [_cap(_short(side)), name])
			_add_strength(side, OP_WIN_STRENGTH)
			_add_strength(target, -OP_TARGET_HIT)
		elif done * 2 >= phases:
			var f: Dictionary = r.get("front", {})
			if f.is_empty() or String(f.by) != side:
				f = {"by": side, "since": day, "progress": FRONT_START}
				r["front"] = f
			f["progress"] = minf(float(f.progress) + float(done) / phases, SIEGE_CAP if cant_fall(zid) else 0.99)
			if h == target:
				r.grip = maxf(0.0, float(r.grip) - OP_PARTIAL_GRIP)
			_news(day, zid, "operation", "%s gained ground at %s: %d of %d phases." % [_cap(_short(side)), name, done, phases])
		else:
			_add_strength(side, -OP_FAIL_STRENGTH)
			if h == target:
				r.grip = minf(1.0, float(r.grip) + OP_FAIL_GRIP)
			_news(day, zid, "operation", "The operation at %s failed: %s held." % [name, _short(h)])
		_section()[zid] = r
	Campaign.mark_changed(SECTION)
	Campaign.mark_changed(WAR)


## Host, from Economy.advance_days: the faction war, `days` days of it (see the header). `_rng`
## is not used: every roll is seeded from the war's seed, the day and the zone.
static func server_advance_days(days: int, _rng: RandomNumberGenerator = null) -> void:
	for zid in war_zones():
		site(zid)
	for zid: String in _section().keys():  # hot zones seeded without data too
		site(zid)
	var before := (_war().news as Array).size()
	var last_day := int(_war().day)
	for _i in days:
		_tick_day()
	Campaign.mark_changed(SECTION)
	Campaign.mark_changed(WAR)
	# The morning's news on the radio (a local stringer): what happened overnight, newest first.
	var fresh := (_war().news as Array).filter(func(n: Dictionary) -> bool: return int(n.get("day", 0)) > last_day)
	if not fresh.is_empty() and before >= 0:
		var said := PackedStringArray()
		for i in range(fresh.size() - 1, maxi(fresh.size() - 1 - NEWS_SAID, -1), -1):
			said.append(String(fresh[i].text))
		Contracts._notify_all("Radio, local stringer: Overnight: %s" % " ".join(said))


## How many of the night's news lines the stringer reads out.
const NEWS_SAID := 3


## Host, tests: one day of the war (server_advance_days(1) without the bookkeeping).
static func _tick_day() -> void:
	var w := _war()
	w.day = int(w.day) + 1
	var day := int(w.day)
	_income()
	for zid in fronts():
		_resolve(zid, day)
	_open_front(day)
	_belligerent_front(day)
	_rebel_front(day)
	for zid: String in _section().keys():
		var r := site(zid)
		if (r.get("front", {}) as Dictionary).is_empty():
			var rate := REPAIR_PER_DAY
			if _predatory(String(r.holder)) and _support(zid) >= SUPPORT_SLOW:
				rate *= 0.5
			r.grip = minf(1.0, float(r.grip) + rate)


static func _rng(day: int, key: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(_war().seed), day, key])
	return rng


static func _predatory(faction: String) -> bool:
	return bool(MissionRegistry.faction(faction).get("predatory", false))


static func _support(zone_id: String) -> float:
	return RebelSupport.support(String(ZoneControl.zone_def_raw(zone_id).get("region", "")))


static func _income() -> void:
	for f in warring():
		if is_belligerent(f):
			_add_strength(f, float(_war_cfg(f).get("income", INCOME_BASE)))  # a deployment budget, not land (D7)
			continue
		var gain := INCOME_BASE
		for z in zones_of(f):
			var share := INCOME_PER_WORTH * worth(f, z) - UPKEEP
			if _predatory(f) and _support(z) >= SUPPORT_CUT:
				share -= INCOME_PER_WORTH * worth(f, z) * 0.25  # villagers stop paying the tax
			elif f == "valley_shura" and _support(z) < SUPPORT_SHURA:
				share += 0.5  # the people turn to the Shura
			gain += share
		_add_strength(f, gain)


## How hard `h` holds `zone_id` (0..~1.3).
static func _defence(h: String, zone_id: String) -> float:
	var g := float(site(zone_id).grip)
	if h == ZoneControl.PLAYER:
		return (FOB_DEFENCE if ZoneControl.control(zone_id) == ZoneControl.FOB else COMPANY_DEFENCE) * (0.3 + 0.7 * g)
	if h == REBELS:
		return _support(zone_id) / 100.0 * (0.3 + 0.7 * g)
	var spread := sqrt(SPREAD_ZONES / maxf(SPREAD_ZONES, float(zones_of(h).size())))
	var home := 1.0 + (HOME_BONUS if h in (ZoneControl.zone_def_raw(zone_id).get("home", []) as Array) else 0.0)
	var d := strength(h) / 100.0 * (0.3 + 0.7 * g) * spread * home
	return maxf(d, FOB_DEFENCE * (0.3 + 0.7 * g)) if _held_by_data(zone_id, h) else d  # FOB Halberd holds like the company's FOB


## How hard `a` pushes into `zone_id`.
static func _push(a: String, zone_id: String) -> float:
	if a == REBELS:
		return _support(zone_id) / 100.0
	return strength(a) / 100.0 * (0.6 + worth(a, zone_id) / 8.0)


static func _resolve(zone_id: String, day: int) -> void:
	var r := site(zone_id)
	var f: Dictionary = r.front
	var a := String(f.by)
	var h := holder_now(zone_id)
	if a == h or (a != REBELS and is_wiped(a)):
		r.erase("front")
		return
	if is_belligerent(a) and operation_pending(zone_id):
		f["since"] = int(f.since) + 1  # it waits on the operation (D7); the wait doesn't count toward a stall
		return
	var rng := _rng(day, zone_id)
	f["progress"] = float(f.progress) + (_push(a, zone_id) - _defence(h, zone_id)) * FRONT_RATE + rng.randf_range(-FRONT_NOISE, FRONT_NOISE)
	_add_strength(a, -ATTRITION)
	_add_strength(h, -ATTRITION)
	r.grip = maxf(0.0, float(r.grip) - SIEGE_GRIP)
	var name := RegionMap.zone_name(zone_id)
	if day - int(f.since) > FRONT_MAX_DAYS:
		r.erase("front")
		_news(day, zone_id, "stalled", "The fighting for %s has died down: it stays with %s." % [name, _short(h)])
	elif float(f.progress) >= 1.0:
		if cant_fall(zone_id):
			if not bool(f.get("sieged", false)):
				_news(day, zone_id, "siege", ("Siege at %s: the base of %s, under attack by %s." if _held_by_data(zone_id, h) else "Siege at %s: the last ground of %s, under attack by %s.") % [name, _short(h), _short(a)])
			f["progress"] = SIEGE_CAP
			f["sieged"] = true
		else:
			_flip(zone_id, a, h, day)
	elif float(f.progress) <= 0.0:
		_add_strength(a, -LOST_ATTACK)
		r.erase("front")
		_news(day, zone_id, "repelled", "%s threw %s back from %s." % [_cap(_short(h)), _short(a), name])


static func _flip(zone_id: String, a: String, h: String, day: int) -> void:
	var r := site(zone_id)
	if h == ZoneControl.PLAYER:
		ZoneControl.server_lose_zone(zone_id)
	r.erase("front")
	r["prev"] = h if h != ZoneControl.PLAYER else String(r.holder)
	r["holder"] = a
	r["grip"] = TAKEOVER_GRIP
	r["flashpoint"] = a != REBELS and not is_belligerent(a)  # (a flashpoint posts a job against the new holder)
	r["flipped_day"] = day
	var why := String(MissionRegistry.faction(a).get("wants_text", ""))
	_news(day, zone_id, "flip", "%s took %s from %s%s." % [_cap(_short(a)), RegionMap.zone_name(zone_id), _short(h),
		" (it wants %s)" % why if why != "" else ""])
	if not (_war().last_zone as Dictionary).has(h) and h != ZoneControl.PLAYER and h != REBELS and zones_of(h).is_empty():
		(_war().last_zone as Dictionary)[h] = zone_id


## Host: at most one new front a day while fewer than MAX_FRONTS are open (see the header).
static func _open_front(day: int) -> void:
	if _faction_fronts() >= MAX_FRONTS:
		return
	var best := {}
	for a in warring():
		if is_belligerent(a) or strength(a) < ATTACK_STRENGTH or fronts().any(func(z: String) -> bool: return String(front(z).by) == a):
			continue
		var from := zones_of(a)
		if from.is_empty() and (_war().last_zone as Dictionary).has(a):
			from.append(String(_war().last_zone[a]))  # in hiding: it comes back where it last stood
		for z in from:
			for l: Dictionary in RegionMap.links(z):
				var n := String(l.to)
				if not is_war_zone(n) or not front(n).is_empty():
					continue
				var h := holder_now(n)
				if h == a or not (h == ZoneControl.PLAYER or h == REBELS or h in MissionRegistry.enemies_of(a)):
					continue
				var score := worth(a, n) * (1.3 - grip(n)) * strength(a) / maxf(_defence(h, n) * 100.0, 1.0)
				if best.is_empty() or score > float(best.score):
					best = {"score": score, "by": a, "zone": n, "against": h}
	if best.is_empty() or _rng(day, "front").randf() >= OPEN_CHANCE:
		return
	var zid := String(best.zone)
	site(zid)["front"] = {"by": String(best.by), "since": day, "progress": FRONT_START}
	_news(day, zid, "front", "Fighting in %s: %s attacking, %s holding." % [RegionMap.zone_name(zid), _short(String(best.by)), _short(String(best.against))])


## Host: where rebel support is at SUPPORT_REBELS, the locals' rebels take on a weak predatory zone.
static func _rebel_front(day: int) -> void:
	if _faction_fronts() >= MAX_FRONTS or fronts().any(func(z: String) -> bool: return String(front(z).by) == REBELS):
		return
	for zid in war_zones():
		var h := holder_now(zid)
		if _predatory(h) and _support(zid) >= SUPPORT_REBELS and grip(zid) <= CONTESTED_GRIP and front(zid).is_empty():
			site(zid)["front"] = {"by": REBELS, "since": day, "progress": FRONT_START}
			_news(day, zid, "front", "Fighting in %s: the villagers have taken up arms against %s." % [RegionMap.zone_name(zid), _short(h)])
			return


## The open fronts not opened by a belligerent (D7: the US's own front is outside MAX_FRONTS).
static func _faction_fronts() -> int:
	return fronts().filter(func(z: String) -> bool: return not is_belligerent(String(front(z).by))).size()


## Host (D7): each belligerent, from its "fronts_from_day", strong enough and with no front of its
## own open, may open one on its war_target's zones next to its ground (the best by the same score
## as _open_front); with none next to it, on the zone next to its ground on the way to the nearest
## (_step_toward). Its own OPEN_CHANCE roll.
static func _belligerent_front(day: int) -> void:
	for b in belligerents():
		var t := war_target(b)
		if t == "" or day < int(_war_cfg(b).get("fronts_from_day", 1)) or strength(b) < ATTACK_STRENGTH \
				or fronts().any(func(z: String) -> bool: return String(front(z).by) == b):
			continue
		var options: Array[String] = []
		for z in zones_of(b):
			for l: Dictionary in RegionMap.links(z):
				var n := String(l.to)
				if is_war_zone(n) and front(n).is_empty() and holder_now(n) == t and n not in options:
					options.append(n)
		if options.is_empty():
			var step := _step_toward(b, t)
			if step != "":
				options.append(step)
		var best := {}
		for n in options:
			var h := holder_now(n)
			var score := worth(b, n) * (1.3 - grip(n)) * strength(b) / maxf(_defence(h, n) * 100.0, 1.0)
			if best.is_empty() or score > float(best.score):
				best = {"score": score, "zone": n, "against": h}
		if best.is_empty() or _rng(day, "front_" + b).randf() >= OPEN_CHANCE:
			continue
		var zid := String(best.zone)
		site(zid)["front"] = {"by": b, "since": day, "progress": FRONT_START}
		var why := "" if String(best.against) == t else ", clearing the way to %s" % _short(t)
		_news(day, zid, "front", "%s open an offensive on %s against %s%s." % [_cap(_short(b)), RegionMap.zone_name(zid), _short(String(best.against)), why])


## The zone next to `b`'s ground on the shortest way (RegionMap links, through war zones) to the
## nearest zone `t` holds, when an enemy of `b`'s holds it (never the company or the rebels) and it
## has no front; "" if there's none.
static func _step_toward(b: String, t: String) -> String:
	var first := {}  # zone -> the zone next to b's ground the way to it starts with ("" for b's own)
	var frontier: Array[String] = []
	for z in zones_of(b):
		first[z] = ""
		frontier.append(z)
	while not frontier.is_empty():
		var at: String = frontier.pop_front()
		for l: Dictionary in RegionMap.links(at):
			var n := String(l.to)
			if first.has(n) or not is_war_zone(n):
				continue
			first[n] = n if String(first[at]) == "" else String(first[at])
			if holder_now(n) == t:
				var step := String(first[n])
				var h := holder_now(step)
				return step if front(step).is_empty() and (h == t or h in MissionRegistry.enemies_of(b)) else ""
			frontier.append(n)
	return ""


static func _cap(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1) if text != "" else text
