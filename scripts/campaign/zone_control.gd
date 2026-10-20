class_name ZoneControl
extends RefCounted
## Who controls each zone of the theatre (Captain, 2026-10-20: "a visual world map that shows
## boundaries and conflicts"), for the world map (WorldMapView) and anything else that asks.
## Kept in its own small file so the zone-control work (the LHD session: a zone flips to the
## company when its HQ and QRF bases fall, and a player FOB zone) can write here without
## touching the map.
##
## Where the answer comes from, first that has one:
##   1. the campaign's "zone_control" section ({zone_id: {"controller", "since_day"}}), written
##      by server_set_controller (nothing calls it yet: the zone-flip work will);
##   2. the base zone ("fob"): the company;
##   3. a hot zone: its WorldSites holder (the faction war moves it between deployments);
##   4. a zone's own "controller" in data/contracts.json, if it has one;
##   5. the target of a contract the company holds or is offered there (that faction's men are
##      who it would fight);
##   6. DEFAULT: Black Ridge, the insurgents the region's people live under (regions' "nation":
##      "insurgent"; ZoneLevel spawns the Black Ridge mix when nobody else is named).
## The section also carries "home" ("fob" today; the LHD session makes it "lhd").
## Host authoritative; Economy's sync carries the section to every other peer.

const SECTION := &"zone_control"
## The company itself as a controller.
const PLAYER := "player"
const DEFAULT := "black_ridge"
## Homes: the FOB base zone, or the LHD offshore.
const HOME_FOB := "fob"
const HOME_LHD := "lhd"
## How a controller is drawn (the IFF palette: contractors blue, allies green, militia orange,
## hostiles red), plus neutral and contested.
const SIDES: Array[String] = ["player", "allied", "militia", "hostile", "neutral", "contested"]
const SIDE_NAMES := {"player": "The company", "allied": "Allied", "militia": "Militia", "hostile": "Hostile", "neutral": "Neutral",
	"contested": "Contested"}
const SIDE_COLOURS := {"player": Color("2f6bd6"), "allied": Color("3f9a3a"), "militia": Color("e0661a"), "hostile": Color("c8281e"),
	"neutral": Color("8a8d84"), "contested": Color("d9b23a")}


## This peer's copy of the section: the host's own, or what Economy's sync sent.
static func _state() -> Dictionary:
	if Engine.get_main_loop() == null or _is_host():
		return Campaign.section(SECTION)
	return Economy.state().get(String(SECTION), {}) as Dictionary


static func _is_host() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	return tree == null or not tree.root.multiplayer.has_multiplayer_peer() or tree.root.multiplayer.is_server()


## The faction id controlling `zone_id` (PLAYER for the company).
static func controller(zone_id: String) -> String:
	var entry: Variant = _state().get(zone_id)
	if entry is Dictionary and String((entry as Dictionary).get("controller", "")) != "":
		return String(entry.controller)
	if zone_id == RegionMap.BASE:
		return PLAYER
	var z := _zone(zone_id)
	if String(z.get("kind", "")) == "hot":
		var holder := String(_site(zone_id).get("holder", ""))
		if holder != "":
			return holder
	if String(z.get("controller", "")) != "":
		return String(z.controller)
	for c: Dictionary in _contracts():
		if String(c.get("zone_id", "")) == zone_id and String(c.get("target", "")) != "":
			return String(c.target)
	return DEFAULT


## Whether `zone_id` is up for grabs: a hot zone whose holder's grip is weak, or one the
## faction war just took (a flashpoint).
static func is_contested(zone_id: String) -> bool:
	var entry: Variant = _state().get(zone_id)
	if entry is Dictionary:
		return bool((entry as Dictionary).get("contested", false))
	var site := _site(zone_id)
	return not site.is_empty() and (float(site.get("grip", 1.0)) <= WorldSites.CONTESTED_GRIP or bool(site.get("flashpoint", false)))


## How `faction` is drawn: "player", "allied" (an employer, or anyone allied to one), "militia"
## (a hostile fielding the insurgent kit), "hostile", or "neutral".
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


## The company's home: HOME_FOB (the base zone) or HOME_LHD (the ship offshore).
static func home() -> String:
	return String(_state().get("home", HOME_FOB))


## Host: `zone_id` is now `faction`'s (PLAYER for the company); `contested` marks it as still
## being fought over. For the zone-flip work; synced to every peer by Economy.
static func server_set_controller(zone_id: String, faction: String, contested := false) -> void:
	Campaign.section(SECTION)[zone_id] = {"controller": faction, "contested": contested, "since_day": Economy.day()}
	Campaign.mark_changed(SECTION)


## Host: the company's home is now `kind` (HOME_FOB or HOME_LHD).
static func server_set_home(kind: String) -> void:
	Campaign.section(SECTION)["home"] = kind
	Campaign.mark_changed(SECTION)


static func _zone(zone_id: String) -> Dictionary:
	for z: Dictionary in MissionRegistry.data().get("zones", []):  # raw: zone() would build its layout
		if String(z.get("zone_id", "")) == zone_id:
			return z
	return {}


## A hot zone's WorldSites row ({} for any other zone): the host's campaign, or the synced rows.
static func _site(zone_id: String) -> Dictionary:
	if String(_zone(zone_id).get("kind", "")) != "hot":
		return {}
	if _is_host():
		return WorldSites.site(zone_id)
	for r: Dictionary in Economy.world_sites():
		if String(r.get("zone_id", "")) == zone_id:
			return r
	return {}


static func _contracts() -> Array:
	return Contracts.held() + Contracts.board()
