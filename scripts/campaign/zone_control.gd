class_name ZoneControl
extends RefCounted
## Who holds which zone, where home is, and the story of taking a zone for the FOB
## (docs/lhd_home.md; Captain, 2026-10-20). Campaign section "zone_control":
## - "home": "lhd" (a new campaign: aboard the LHD, LhdLevel) or "fob" (the base zone). A save
##   from before this has no section: its home reads "fob" (it keeps the FOB it has).
## - "fob_zone": the zone the FOB was built in ("" for the original inland FOB).
## - "zones": zone id -> {"state": ENEMY, COMPANY or FOB, "down": [module ids of its HQ and QRF
##   bases taken out, counted across deployments], "flipped_day", "seize_cid", "reoffer_day"}.
##
## The take-a-zone flow: a zone flips to the company once every HQ and QRF base in it has been
## taken out (server_scan, from BaseHub while deployed: ZoneLevel.site_down). While home is the
## LHD, the client's liaison calls (the charter is running out; the client wants the company
## ashore) and a seize-and-hold contract for that zone goes on the board (make_seize_contract:
## take the zone's HQ, then hold it through the counterattack). Winning it makes that zone the
## FOB (server_establish_fob): home moves, the base zone is built on that zone's ground
## (BaseZoneLevel.def_for), and the region map's base cell moves there (apply_to_layout). Losing
## or letting it lapse puts it back on the board the next day.
##
## Read-only accessors for the map and the screens: home(), fob_zone(), control(), is_company(),
## progress(), view(). On a client they read the base screen's view (BaseHub.view "zone_control"),
## else Economy's sync of the section. Host only for the rest.
##
## Who controls a zone, for the theatre map (world-map work, merged here 2026-10-20: "a visual
## world map that shows boundaries and conflicts"): controller(), side(), is_contested(), drawn in
## SIDE_COLOURS (the IFF palette). The first that has an answer:
##   1. a "controller" written on the zone's entry (server_set_controller);
##   2. the company (PLAYER), for a zone it took or its FOB's (control() not ENEMY; the base zone);
##   3. a hot zone: its WorldSites holder (the faction war moves it between deployments);
##   4. a zone's own "controller" in data/contracts.json, if it has one;
##   5. the target of a contract the company holds or is offered there;
##   6. DEFAULT: Black Ridge, the insurgents the region's people live under.

const SECTION := &"zone_control"
const HOME_LHD := "lhd"
const HOME_FOB := "fob"
## The company itself as a controller (the theatre map).
const PLAYER := "player"
const DEFAULT := "black_ridge"
## How a controller is drawn (the IFF palette: contractors blue, allies green, militia orange,
## hostiles red), plus neutral and contested.
const SIDES: Array[String] = ["player", "allied", "militia", "hostile", "neutral", "contested"]
const SIDE_NAMES := {"player": "The company", "allied": "Allied", "militia": "Militia", "hostile": "Hostile", "neutral": "Neutral",
	"contested": "Contested"}
const SIDE_COLOURS := {"player": Color("2f6bd6"), "allied": Color("3f9a3a"), "militia": Color("e0661a"), "hostile": Color("c8281e"),
	"neutral": Color("8a8d84"), "contested": Color("d9b23a")}
## A zone's control.
const ENEMY := "enemy"
const COMPANY := "company"
const FOB := "fob"
## The sites whose fall flips a zone.
const FLIP_SITES: Array[String] = ["hq", "qrf_base"]
## The seize-and-hold contract: its type (not a board type: only the story offers it) and source.
const SEIZE_TYPE := "seize_hold"
const SEIZE_SOURCE := "story"
## A lost or lapsed seize-and-hold contract comes back on the board this many days later. Proposed.
const REOFFER_DAYS := 1
## The seize-and-hold contract's offer stays on the board this many days. Proposed.
const SEIZE_OFFER_DAYS := 10
## The liaison's lines ("%s": the zone's name).
const LINE_FLIP := "Radio, client liaison: Good work in %s, their HQ and QRF are finished there. Straight talk: the LHD's charter is running out and the client wants the company ashore. Take their old HQ, hold it through the counterattack, and the ground's yours for a FOB. It's on the board."
const LINE_AGAIN := "Radio, client liaison: The offer in %s stands. Take the HQ, hold it, and you've got your FOB. It's back on the board."
const LINE_WON := "Radio, client liaison: %s is yours. The engineers are putting the FOB up now; the LHD stays offshore to cover the coast."

static var _last_sig := ""


static func _s() -> Dictionary:
	if _is_host():
		return Campaign.section(SECTION)
	var seen: Dictionary = BaseHub.view.get("zone_control", {})
	return seen if not seen.is_empty() else Economy.state().get(String(SECTION), {}) as Dictionary


static func _is_host() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return true
	var mp := tree.root.multiplayer
	return mp == null or not mp.has_multiplayer_peer() or mp.is_server()


# --- Read-only ------------------------------------------------------------------------------

## Where home is: HOME_LHD or HOME_FOB.
static func home() -> String:
	return String(_s().get("home", HOME_FOB))


static func home_is_lhd() -> bool:
	return home() == HOME_LHD


## The zone the FOB was built in ("" for the original inland FOB, or while home is the LHD).
static func fob_zone() -> String:
	return String(_s().get("fob_zone", ""))


## `zone_id`'s control: ENEMY, COMPANY (flipped) or FOB (the company's FOB is there).
static func control(zone_id: String) -> String:
	if zone_id == RegionMap.BASE or (zone_id != "" and zone_id == fob_zone() and not home_is_lhd()):
		return FOB
	return String((_s().get("zones", {}) as Dictionary).get(zone_id, {}).get("state", ENEMY))


static func is_company(zone_id: String) -> bool:
	return control(zone_id) != ENEMY


## Whether the board's zone picks can send the squad into `zone_id` (ContractGen.generate, the
## faction war's offers in Contracts.server_refresh_board): not into a zone the company holds,
## flipped or with its FOB there. The seize-and-hold contract names its zone itself.
static func offers_in(zone_id: String) -> bool:
	return not is_company(zone_id)


## The HQ and QRF bases in `zone_id` (module ids): its control flips once all of them are down.
static func flip_sites(zone_id: String) -> Array[String]:
	var out: Array[String] = []
	for m: Dictionary in MissionRegistry.zone_def(zone_id).get("modules", []):
		if ZoneModules.base(String(m.get("type", ""))) in FLIP_SITES:
			out.append(String(m.id))
	return out


## {"down": how many of `zone_id`'s HQ and QRF bases are taken out, "of": how many it has}.
static func progress(zone_id: String) -> Dictionary:
	var sites := flip_sites(zone_id)
	var down: Array = (_s().get("zones", {}) as Dictionary).get(zone_id, {}).get("down", [])
	return {"down": sites.filter(func(m: String) -> bool: return m in down).size(), "of": sites.size()}


## The section as the base screen's view carries it to clients.
static func view() -> Dictionary:
	return Roster.json_safe(Campaign.section(SECTION).duplicate(true))


## Every peer (RegionMap.layout, once per build): the base's cell on the region map follows home:
## none while home is the LHD (no zone has a crossing to a ship), else the FOB's zone's cell.
static func apply_to_layout(layout: Dictionary) -> void:
	if home_is_lhd():
		layout.erase(RegionMap.BASE)
		return
	var at := fob_zone()
	if at != "" and layout.has(at):
		layout[RegionMap.BASE] = layout[at]
		layout.erase(at)


## The region map and the zone definitions (their crossings) are built again (home moved).
static func invalidate_maps() -> void:
	RegionMap._layout = {}
	MissionRegistry._zone_defs = {}
	_last_sig = "%s|%s" % [home(), fob_zone()]


## Client (BaseHub.view_changed): the maps follow the host's home when it moves.
static func on_view_changed() -> void:
	if _is_host():
		return
	if "%s|%s" % [home(), fob_zone()] != _last_sig:
		invalidate_maps()


# --- The theatre map ------------------------------------------------------------------------

## The faction id controlling `zone_id` (PLAYER for the company); see the top of the file.
static func controller(zone_id: String) -> String:
	var entry: Dictionary = (_s().get("zones", {}) as Dictionary).get(zone_id, {})
	if String(entry.get("controller", "")) != "":
		return String(entry.controller)
	if zone_id == RegionMap.BASE or is_company(zone_id):
		return PLAYER
	var z := zone_def_raw(zone_id)
	if String(z.get("kind", "")) == "hot":
		var holder := String(_site(zone_id).get("holder", ""))
		if holder != "":
			return holder
	if String(z.get("controller", "")) != "":
		return String(z.controller)
	for c: Dictionary in Contracts.held() + Contracts.board():
		if String(c.get("zone_id", "")) == zone_id and String(c.get("target", "")) != "":
			return String(c.target)
	return DEFAULT


## Whether `zone_id` is up for grabs: marked so, or a hot zone whose holder's grip is weak, or
## one the faction war just took (a flashpoint).
static func is_contested(zone_id: String) -> bool:
	var entry: Dictionary = (_s().get("zones", {}) as Dictionary).get(zone_id, {})
	if entry.has("contested"):
		return bool(entry.contested)
	var site := _site(zone_id)
	return not site.is_empty() and (float(site.get("grip", 1.0)) <= WorldSites.CONTESTED_GRIP or bool(site.get("flashpoint", false)))


## How `faction` is drawn: "player", "allied" (an employer), "militia" (a hostile fielding the
## insurgent kit), "hostile", or "neutral".
static func side_of_faction(faction: String) -> String:
	if faction == PLAYER:
		return "player"
	var f := MissionRegistry.faction(faction)
	match String(f.get("role", "")):
		"employer":
			return "allied"
		"neutral":
			return "neutral"
		"hostile":
			return "militia" if String(f.get("kit", Kits.INSURGENT)) == Kits.INSURGENT else "hostile"
	return "neutral"


## How `zone_id` is drawn: its controller's side, or "contested".
static func side(zone_id: String) -> String:
	return "contested" if is_contested(zone_id) else side_of_faction(controller(zone_id))


## A controller's name for the map ("The company" for PLAYER).
static func controller_name(faction: String) -> String:
	return SIDE_NAMES.player if faction == PLAYER else MissionRegistry.faction_name(faction)


## A zone's raw row in data/contracts.json ({} if none): MissionRegistry.zone() would build its layout.
static func zone_def_raw(zone_id: String) -> Dictionary:
	for z: Dictionary in MissionRegistry.data().get("zones", []):
		if String(z.get("zone_id", "")) == zone_id:
			return z
	return {}


## A hot zone's WorldSites row ({} for any other zone): the host's campaign, or the synced rows.
static func _site(zone_id: String) -> Dictionary:
	if String(zone_def_raw(zone_id).get("kind", "")) != "hot":
		return {}
	if _is_host():
		return WorldSites.site(zone_id)
	for r: Dictionary in Economy.world_sites():
		if String(r.get("zone_id", "")) == zone_id:
			return r
	return {}


# --- Host -----------------------------------------------------------------------------------

## Host: `zone_id` is drawn as `faction`'s (PLAYER for the company) on the theatre map, whatever
## else says; `contested` marks it as still being fought over. Its take-a-zone state is apart.
static func server_set_controller(zone_id: String, faction: String, contested := false) -> void:
	var z := _zone(zone_id)
	z["controller"] = faction
	z["contested"] = contested
	z["since_day"] = Economy.day()
	Campaign.mark_changed(SECTION)

## Host (BaseHub.new_campaign): a new campaign's zone control, home aboard the LHD if `lhd`.
static func server_start(lhd: bool) -> void:
	var s := Campaign.section(SECTION)
	s.clear()
	s["home"] = HOME_LHD if lhd else HOME_FOB
	s["fob_zone"] = ""
	s["zones"] = {}
	invalidate_maps()


## Host (BaseHub.load_or_new): a loaded campaign. One saved before zone control keeps its FOB.
static func server_loaded() -> void:
	var s := Campaign.section(SECTION)
	if not s.has("home"):
		s["home"] = HOME_FOB
	if not s.has("zones"):
		s["zones"] = {}
	if not s.has("fob_zone"):
		s["fob_zone"] = ""
	invalidate_maps()


static func _zone(zone_id: String) -> Dictionary:
	var s := Campaign.section(SECTION)
	if not s.has("zones"):
		s["zones"] = {}
	var zones: Dictionary = s.zones
	if not zones.has(zone_id):
		zones[zone_id] = {"state": ENEMY, "down": []}
	return zones[zone_id]


## Host (BaseHub, every poll while deployed): the HQ and QRF bases taken out in `lvl` (a zone
## level) count towards its zone's control.
static func server_scan(lvl: Node) -> void:
	if lvl == null or not lvl.has_method(&"site_down"):
		return
	var def: Variant = lvl.get(&"def")
	if not def is Dictionary:
		return
	var zone_id := String((def as Dictionary).get("id", ""))
	if zone_id == "" or zone_id == RegionMap.BASE:
		return
	for m: Dictionary in (def as Dictionary).get("modules", []):
		if ZoneModules.base(String(m.get("type", ""))) in FLIP_SITES and bool(lvl.call(&"site_down", String(m.id))):
			server_note_site_down(zone_id, String(m.id))


## Host: `zone_id`'s HQ or QRF base `module_id` is taken out. Returns whether the zone flipped now.
static func server_note_site_down(zone_id: String, module_id: String) -> bool:
	var sites := flip_sites(zone_id)
	if module_id not in sites:
		return false
	var z := _zone(zone_id)
	var down: Array = z.get("down", [])
	if module_id in down:
		return false
	down.append(module_id)
	z["down"] = down
	SessionLog.note("zone control: %s: %s down (%d of %d)" % [zone_id, module_id, progress(zone_id).down, sites.size()])
	Campaign.mark_changed(SECTION)
	if String(z.get("state", ENEMY)) == ENEMY and sites.all(func(m: String) -> bool: return m in down):
		_flip(zone_id)
		return true
	return false


static func _flip(zone_id: String) -> void:
	var z := _zone(zone_id)
	z["state"] = COMPANY
	z["flipped_day"] = Economy.day()
	var name := RegionMap.zone_name(zone_id)
	SessionLog.note("zone control: %s flips to the company (day %d)" % [zone_id, Economy.day()])
	Contracts._notify_all("%s: its HQ and QRF bases are down. The zone is ours." % name)
	if home_is_lhd():
		Contracts._notify_all(LINE_FLIP % name)
		server_offer_seize(zone_id)
	Campaign.mark_changed(SECTION)


## Host: the seize-and-hold contract for `zone_id` on the board (the one already there or held, or
## a new one). Returns its id, or "" if none can be made.
static func server_offer_seize(zone_id: String) -> String:
	var live := seize_contract(zone_id)
	if not live.is_empty():
		return String(live.cid)
	var c := make_seize_contract(zone_id)
	if c.is_empty():
		return ""
	var cid := Contracts.server_add_offer(c)
	var z := _zone(zone_id)
	z["seize_cid"] = cid
	z.erase("reoffer_day")
	Campaign.mark_changed(SECTION)
	SessionLog.note("zone control: seize-and-hold contract %s offered in %s" % [cid, zone_id])
	return cid


## The seize-and-hold contract for `zone_id` on the board or held, or {} (the host's own records;
## a client's public views).
static func seize_contract(zone_id: String) -> Dictionary:
	var listed: Array = (Contracts._s().board as Array) + (Contracts._s().held as Array) if _is_host() else Contracts.board() + Contracts.held()
	for c: Dictionary in listed:
		if String(c.get("type", "")) == SEIZE_TYPE and String(c.get("zone_id", "")) == zone_id:
			return c
	return {}


## The seize-and-hold contract for `zone_id` (ContractGen.generate's shape): a hot zone's Hold the
## line (its pay, employer, force and the counterattack's waves) at the zone's HQ, with the HQ to
## take first: clear it (whoever is left in it holds it), then hold it. {} for a zone without one.
static func make_seize_contract(zone_id: String) -> Dictionary:
	var def := MissionRegistry.zone_def(zone_id)
	var hold := MissionRegistry.type_def("defend_hold")
	if def.is_empty() or hold.is_empty():
		return {}
	var site := {}
	for type: String in FLIP_SITES:
		for m: Dictionary in def.get("modules", []):
			if site.is_empty() and ZoneModules.base(String(m.type)) == type:
				site = m
	if site.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Contracts.campaign_seed(), zone_id, Economy.day(), "seize"])
	var c := ContractGen.generate(rng, {"day": Economy.day(), "source": "board", "type": "defend_hold", "zone_id": zone_id})
	var pick := RandomNumberGenerator.new()
	pick.seed = hash([rng.seed, "hold"])
	var module_type := String(site.type)
	var name := MissionRegistry.module_name(module_type)
	var objectives: Array = [{"kind": Objectives.CLEAR_AREA, "site": "area", "text": "Seize the %s: leave no defender standing in it" % name}]
	var held: Array = ScenarioGen._defend(pick, hold, site, float(def.get("size_m", 4096.0)) * 0.5, hold.get("scenario_knobs", {}))
	for o: Dictionary in held:
		o["text"] = String(o.get("text", "")).replace("against attacks from all sides", "through the counterattack")
	objectives.append_array(held)
	var zone_name := String(def.get("name", zone_id))
	c.merge({"type": SEIZE_TYPE, "source": SEIZE_SOURCE, "story": "fob_takeover", "fixer": "",
		"title": "Seize and hold: %s" % zone_name,
		"brief": "The client's liaison: the LHD's charter is running out and the client wants the company ashore. Take the enemy's old %s in %s, then hold it through their counterattack. Win, and the ground is the company's FOB." % [name.to_lower(), zone_name],
		"module": module_type, "module_id": String(site.id), "module_name": name, "objectives": objectives,
		"expires_day": Economy.day() + SEIZE_OFFER_DAYS}, true)
	return c


## Host (Contracts.contract_closed): a seize-and-hold contract won makes its zone the FOB; lost,
## lapsed or expired, it comes back on the board REOFFER_DAYS later.
static func on_contract_closed(c: Dictionary, outcome: String) -> void:
	if String(c.get("type", "")) != SEIZE_TYPE or not _is_host():
		return
	var zone_id := String(c.get("zone_id", ""))
	var z := _zone(zone_id)
	z["seize_cid"] = ""
	if outcome == "completed":
		server_establish_fob(zone_id)
	else:
		z["reoffer_day"] = Economy.day() + REOFFER_DAYS
		SessionLog.note("zone control: the seize-and-hold contract in %s %s; offered again on day %d" % [zone_id, outcome, int(z.reoffer_day)])
	Campaign.mark_changed(SECTION)


## Host (Economy.day_advanced): while home is the LHD, a flipped zone without its seize-and-hold
## contract gets it back once its "reoffer_day" comes.
static func on_day_advanced(today: int, _days: int) -> void:
	if not _is_host() or not home_is_lhd() or not BaseHub.started():
		return
	var zones: Dictionary = Campaign.section(SECTION).get("zones", {})
	for zone_id: String in zones:
		var z: Dictionary = zones[zone_id]
		if String(z.get("state", ENEMY)) != COMPANY or not seize_contract(zone_id).is_empty():
			continue
		if int(z.get("reoffer_day", 0)) <= today:
			Contracts._notify_all(LINE_AGAIN % RegionMap.zone_name(zone_id))
			server_offer_seize(zone_id)


## Host: `zone_id` is the company's FOB now: home moves there (BaseHub.base_info: the base zone on
## that zone's ground), and the region map's base cell with it.
static func server_establish_fob(zone_id: String) -> void:
	var s := Campaign.section(SECTION)
	var z := _zone(zone_id)
	var name := RegionMap.zone_name(zone_id)
	z["state"] = FOB
	z["fob_day"] = Economy.day()
	s["home"] = HOME_FOB
	s["fob_zone"] = zone_id
	invalidate_maps()
	SessionLog.note("zone control: the FOB is established in %s (day %d); home moves ashore" % [zone_id, Economy.day()])
	Contracts._notify_all(LINE_WON % name)
	Campaign.mark_changed(SECTION)
