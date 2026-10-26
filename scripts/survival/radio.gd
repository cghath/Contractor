class_name FallenRadio
extends RefCounted
## The repaired radio of Contractor: Fallen (docs/survival_world.md section 10; calls 45, 95): a
## found "radio" item is dead until it's repaired (radio_parts and the mechanics line at
## REPAIR_LEVEL, via Rpg) and needs power (a battery carried, BATTERY_HOURS of listening each, or
## standing at the settlement while its generator runs: Settlement.footprint). Switched on, every
## GAP_HOURS a broadcast plays, in turn from:
## - group chatter: the newest event within range of the zone you're in (RANGE_LINKS by its region:
##   hills and desert carry far, the city's concrete short), as a voice through the static;
## - the enclave: its broadcasts (events of kind "broadcast", the sim's or the enclave lane's), else
##   its standing evac call while the enclave holds the evac;
## - ARCHE's numbers station: a timed line from the trail (state()["trail"]'s "numbers" when the
##   enclave lane writes it), else a canned eerie one.
## Each is a journal line ("radio"), a map mark when it names a place, and a HUD line for the
## players while it plays (Survival._tell). State in Intel.section()["radio"]: {"repaired",
## "on", "next" (world days), "battery" (hours left), "turn", "heard": [event ids], "last"}.

const ITEM := &"radio"
const PARTS := &"radio_parts"
const BATTERIES: Array[StringName] = [&"battery_aa", &"battery_cr123"]
const SKILL := "mechanics"
## Proposed numbers.
const REPAIR_LEVEL := 2
const GAP_HOURS := 2.0
const BATTERY_HOURS := 12.0
const RANGE_LINKS := {"hills": 3, "desert": 3, "plains": 2, "coast": 2, "city": 1}
const CHATTER_KINDS: Array[String] = ["fight", "raid", "horde", "horde_moved", "horde_attack", "capture", "supply_drop", "burning", "bell",
	"settled", "group_gone", "trade", "hunt", "rescue", "split", "formed", "death", "arrived"]
const NUMBERS_CANNED: Array[String] = [
	"A woman's voice, flat: \"Seven. Four. Four. Nine. Arche. Seven. Four...\" Then a tone, and nothing.",
	"A child's music box, then numbers in a man's voice: \"Two. Zero. One. One. Arche holds.\"",
	"Three long tones. \"Station Arche. Group one. Six, one, eight. Repeat: six, one, eight.\"",
]


static func data() -> Dictionary:
	var r: Dictionary = Intel.section().radio
	if not r.has("repaired"):
		r.merge({"repaired": false, "on": false, "next": 0.0, "battery": 0.0, "turn": 0, "heard": [], "last": ""}, false)
	return r


static func has_radio(s: Soldier) -> bool:
	return Survival.kit_of(s.inventory).any(func(e: Dictionary) -> bool: return StringName(String(e.id)) == ITEM)


## Why `s` can't repair the radio ("" he can).
static func repair_problem(s: Soldier) -> String:
	if data().repaired:
		return "It already works"
	if not has_radio(s):
		return "No radio to repair"
	if s.inventory.count_of(PARTS) <= 0:
		return "Needs radio parts"
	if not Rpg.gate(s, SKILL, REPAIR_LEVEL):
		return "Needs mechanics %d" % REPAIR_LEVEL
	return ""


## Host: `s` repairs the radio (one radio_parts used). Returns why not ("" done).
static func server_repair(s: Soldier) -> String:
	var why := repair_problem(s)
	if why != "":
		return why
	s.inventory.remove_one(PARTS)
	data().repaired = true
	Intel.journal("I got the radio working.", "radio")
	return ""


## Whether `s` has power for the radio: a battery's hours left or one carried, or at the
## settlement with its generator running.
static func powered(s: Soldier) -> bool:
	if float(data().get("battery", 0.0)) > 0.0:
		return true
	for b: StringName in BATTERIES:
		if s.inventory.count_of(b) > 0:
			return true
	return at_generator(s)


static func at_generator(s: Soldier) -> bool:
	if not Settlement.exists() or Settlement.zone() != String(Survival.state().get("zone", "")):
		return false
	if float(Settlement.footprint().get("noise_m", 0.0)) <= 0.0 and not Infrastructure.powered_here():  # (phase D: solar, wind, batteries)
		return false
	return s.global_position.distance_to(Settlement.pos()) <= Settlement.radius()


## Host: the radio on or off. Returns why not ("" done).
static func server_set_on(s: Soldier, on: bool) -> String:
	var r := data()
	if not on:
		r.on = false
		return ""
	if not has_radio(s):
		return "No radio"
	if not bool(r.repaired):
		return "The radio's dead: it needs repairing"
	if not powered(s):
		return "No power: a battery, or the generator"
	r.on = true
	r["owner"] = Survival.profile_of(s)
	r.next = Intel.now() + 0.25 / 24.0  # (the first comes soon)
	r["t"] = Intel.now()
	return ""


static func is_on() -> bool:
	return bool(data().get("on", false))


## Host: the radio's clock: its battery drains while it's on (a new battery from the owner's
## kit, else off: no power at the generator either), and a broadcast when one's due. Returns the
## broadcast ({} none). `owner` the soldier carrying it (else the level's player by profile).
static func server_tick(level: Node, owner: Soldier = null) -> Dictionary:
	var r := data()
	if not bool(r.get("on", false)):
		return {}
	if owner == null and level:
		for p: Soldier in MapNodes.players(level):
			if Survival.profile_of(p) == String(r.get("owner", "")) or owner == null:
				owner = p
	if owner == null or not has_radio(owner):
		return {}
	var t := Intel.now()
	var hours := maxf(0.0, (t - float(r.get("t", t))) * 24.0)
	r["t"] = t
	if not at_generator(owner):
		r.battery = float(r.get("battery", 0.0)) - hours
		if float(r.battery) <= 0.0:
			var fresh := false
			for b: StringName in BATTERIES:
				if owner.inventory.remove_one(b):
					r.battery = float(r.battery) + BATTERY_HOURS
					fresh = true
					break
			if not fresh:
				r.battery = 0.0
				r.on = false
				Survival._tell(owner, "The radio dies: no batteries")
				return {}
	if t < float(r.get("next", 0.0)):
		return {}
	r.next = t + GAP_HOURS / 24.0
	return server_broadcast(level)


## Host: one broadcast now (the next source in turn that has something): a journal line, a mark when
## it names a place, a HUD line. {"kind" (chatter | enclave | numbers), "text", "zone"}.
static func server_broadcast(level: Node = null) -> Dictionary:
	var r := data()
	var order: Array[String] = ["chatter", "enclave", "numbers"]
	var b := {}
	for i in order.size():
		var kind := order[(int(r.get("turn", 0)) + i) % order.size()]
		b = _from(kind)
		if not b.is_empty():
			break
	r.turn = int(r.get("turn", 0)) + 1
	if b.is_empty():
		return {}
	r.last = String(b.text)
	if int(b.get("event", 0)) != 0:
		(r.heard as Array).append(int(b.event))
		r.heard = (r.heard as Array).slice(-200)
	Intel.journal("Radio: %s" % String(b.text), "radio", "the radio")
	var zone := String(b.get("zone", ""))
	if zone != "" and RegionMap.layout().has(zone) and String(b.kind) != "numbers":
		SurvivalMap.server_know(zone, "told")
		var m := SurvivalMap.server_add_mark(zone, Intel.place_pos(zone, int(b.get("event", 0))), Intel._short(String(b.get("mark", b.text))), "radio")
		m["teller"] = "the radio"
		Intel._server_map_changed()
	if level:
		for p: Soldier in MapNodes.players(level):
			Survival._tell(p, "Radio: %s" % String(b.text))
	return b


static func _from(kind: String) -> Dictionary:
	var heard: Array = data().get("heard", [])
	match kind:
		"chatter":
			var here := String(Survival.state().get("zone", ""))
			var reach := int(RANGE_LINKS.get(WorldSim.region_of(here), 2)) if here != "" else 2
			var zones: Dictionary = WorldSim.section().get("zones", {})
			var best := {}
			for e: Dictionary in WorldSim.section().get("events", []):
				if int(e.id) in heard or not String(e.kind) in CHATTER_KINDS or "player" in (e.groups as Array):
					continue
				if here != "":
					var dist := WorldRegions.distance(zones, here, String(e.zone))
					if dist < 0 or dist > reach:
						continue
				best = e
			if best.is_empty():
				return {}
			return {"kind": "chatter", "text": "Static, then a voice: \"...%s...\"" % String(best.text), "mark": String(best.text), "zone": String(best.zone), "event": int(best.id)}
		"enclave":
			for e: Dictionary in WorldSim.section().get("events", []):
				if String(e.kind) == "broadcast" and not int(e.id) in heard:
					return {"kind": "enclave", "text": String(e.text), "zone": String(e.zone), "event": int(e.id)}
			var st := WorldSim.goal_state()
			if bool(st.get("evac", false)) and String(st.get("evac_zone", "")) != "" and not bool(st.get("lost", false)):
				var who := String(WorldSim.group(String(st.get("evac_group", ""))).get("name", "Harbour Command"))
				return {"kind": "enclave", "text": "%s, all stations: the evacuation runs from %s. Come unarmed. Bring what you owe." % [who, RegionMap.zone_name(String(st.evac_zone))],
					"zone": String(st.evac_zone), "event": 0, "mark": "Evac (radio)"}
			return {}
		"numbers":
			var trail: Variant = Survival.state().get("trail")
			var lines: Array = []
			if trail is Dictionary and (trail as Dictionary).get("numbers") is Array:
				lines = (trail as Dictionary).numbers
			var n := int(data().get("numbers_i", 0))
			data()["numbers_i"] = n + 1
			if not lines.is_empty():
				var l: Variant = lines[n % lines.size()]
				return {"kind": "numbers", "text": String((l as Dictionary).get("text", "")) if l is Dictionary else String(l), "event": 0}
			return {"kind": "numbers", "text": NUMBERS_CANNED[n % NUMBERS_CANNED.size()], "event": 0}
	return {}
