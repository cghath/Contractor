class_name ArcheTrail
extends RefCounted
## ARCHE's trail (docs/survival_world.md section 7, calls 62 and 66; docs/survival_enclave.md):
## the story behind the fall laid by each world's seed across ARCHE's sites. The pieces
## (data/arche_trail.json: notes, terminals, recordings, a survivor who worked there, an enclave
## officer who knows part, broadcasts on ARCHE's frequency) go to the sites (the lab zone, the
## sealed level under the military base, the bunkers (Bunkers), two relay stations, the failed
## quarantine camp, the technician's hiding place, the enclave) in an order of the seed's own;
## a piece with a code carries one bunker's door code. Reading a piece (server_read: the talk,
## loot and radio lanes call it; an ARCHE document or tape read from the inventory through
## server_read_item) adds a journal entry and a map mark, marks where the trail leads next, and
## teaches a door code. Broadcasts air on the far tick as world events of kind "broadcast" with
## "freq" (the radio lane reads them). The trail never resolves: two theories (leak, release),
## each piece leaning to one, both always open (theories()).
##
## State: Survival.state()["arche"]: {"sites": [{id, kind, name, zone, pos}], "pieces": {id:
## {id, kind, site, zone, pos, order, theory, title, text, code_for, read, aired}}, "order": [ids],
## "codes": {bunker id: true when learnt}, "survivor": person id}.

const KEY := "arche"
const PATH := "res://data/arche_trail.json"
const ITEMS: Array[String] = ["arche_dossier", "arche_tape"]
## Proposed: a broadcast airs once a world day at most (the next unaired one, by the trail's order).
const AIR_GAP_DAYS := 1.0

static var _data := {}


static func trail_data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = ModKit.overlay("arche_trail", JSON.parse_string(f.get_as_text()) if f else null)  # (mods: docs/fallen_modding.md)
		_data = parsed if parsed is Dictionary else {"pieces": [], "site_kinds": {}, "fragments": []}
	return _data


static func data() -> Dictionary:
	var st := Survival.state()
	if not st.get(KEY) is Dictionary:
		st[KEY] = {}
	return st[KEY]


static func is_set_up() -> bool:
	return data().has("order")


static func pieces() -> Dictionary:
	return data().get("pieces", {})


static func piece(id: String) -> Dictionary:
	return pieces().get(id, {})


static func sites() -> Array:
	return data().get("sites", [])


static func frequency() -> String:
	return String(trail_data().get("frequency", "4.625 MHz"))


# --- Laying the trail ------------------------------------------------------------------------------

## The sites of a world: [{id, kind, name, zone, pos: [x, z]}]: the lab, the sealed level, the
## relay stations and the quarantine camp and the survivor's place by the seed and the regions,
## the bunkers given, the enclave's home. Pure: the same seed and zones give the same sites.
static func sites_for(world_seed: int, zones: Dictionary, bunkers: Array, start_zone: String, enclave_zone: String) -> Array:
	var kinds: Dictionary = trail_data().get("site_kinds", {})
	var out: Array = []
	var ids := WorldModel._sorted(zones.keys()).filter(func(z: String) -> bool: return z != start_zone)
	for kind: String in ["lab", "sealed_level"]:
		var want := String((kinds.get(kind, {}) as Dictionary).get("zone_type", ""))
		for z: String in ids:
			if String((zones[z] as Dictionary).get("type", "")) == want:
				out.append({"id": kind, "kind": kind, "name": String((kinds.get(kind, {}) as Dictionary).get("name", kind)), "zone": z, "pos": _place_pos(zones[z], 0)})
				break
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "arche", "sites"])
	var used := {}
	for s: Dictionary in out:
		used[String(s.zone)] = true
	for kind: String in ["relay", "quarantine", "survivor"]:
		var k: Dictionary = kinds.get(kind, {})
		var regions: Array = k.get("regions", [])
		var pool := ids.filter(func(z: String) -> bool: return String((zones[z] as Dictionary).get("region", "")) in regions and not used.has(z))
		if pool.is_empty():
			pool = ids.filter(func(z: String) -> bool: return not used.has(z))
		for i in int(k.get("count", 1)):
			if pool.is_empty():
				break
			var z := String(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
			used[z] = true
			var nm := String(k.get("name", kind))
			if nm.contains("%d"):
				nm = nm % (i + 1)
			out.append({"id": "%s%d" % [kind, i + 1] if int(k.get("count", 1)) > 1 else kind, "kind": kind, "name": nm, "zone": z,
				"pos": _place_pos(zones[z], rng.randi_range(0, 7))})
	for b: Dictionary in bunkers:
		out.append({"id": String(b.id), "kind": "bunker", "name": "ARCHE %s" % String(b.name), "zone": String(b.zone), "pos": (b.pos as Array).duplicate()})
	if enclave_zone != "":
		out.append({"id": "enclave", "kind": "enclave", "name": "the enclave", "zone": enclave_zone, "pos": _place_pos(zones.get(enclave_zone, {}), 0)})
	return out


static func _place_pos(zd: Dictionary, i: int) -> Array:
	var places: Array = zd.get("places", [])
	if places.is_empty():
		return [0.0, 0.0]
	var p: Array = (places[i % places.size()] as Dictionary).get("pos", [0.0, 0.0])
	return [float(p[0]), float(p[1])]


## The trail for a world (pure): {"sites", "pieces": {id: piece}, "order": [piece ids]}: every
## piece to a site of its kind (a bunker or relay by the seed), the order shuffled by the seed,
## each code piece carrying one bunker's code (never its own bunker's), the bunkers' codes
## spread so every bunker's turns up when there are pieces enough.
static func lay(world_seed: int, zones: Dictionary, bunkers: Array, start_zone: String, enclave_zone: String) -> Dictionary:
	var site_list := sites_for(world_seed, zones, bunkers, start_zone, enclave_zone)
	var by_kind := {}
	for s: Dictionary in site_list:
		if not by_kind.has(String(s.kind)):
			by_kind[String(s.kind)] = []
		(by_kind[String(s.kind)] as Array).append(s)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "arche", "trail"])
	var out := {}
	var order: Array = []
	var bunker_pool: Array = (by_kind.get("bunker", []) as Array).duplicate()
	for raw: Dictionary in trail_data().get("pieces", []):
		var kind := String(raw.site)
		var choices: Array = by_kind.get(kind, [])
		if choices.is_empty():
			continue
		var at: Dictionary
		if kind == "bunker" and not bunker_pool.is_empty():  # (spread over the bunkers first)
			at = bunker_pool.pop_at(rng.randi_range(0, bunker_pool.size() - 1))
		else:
			at = choices[rng.randi_range(0, choices.size() - 1)]
		var pc := {"id": String(raw.id), "kind": String(raw.kind), "site": String(at.id), "site_kind": kind, "zone": String(at.zone),
			"pos": (at.pos as Array).duplicate(), "theory": String(raw.get("theory", "")), "title": String(raw.title), "text": String(raw.text),
			"code": bool(raw.get("code", false)), "code_for": "", "read": false, "aired": false, "order": 0}
		out[String(raw.id)] = pc
		order.append(String(raw.id))
	for i in range(order.size() - 1, 0, -1):  # the seed's own order
		var j := rng.randi_range(0, i)
		var t: Variant = order[i]
		order[i] = order[j]
		order[j] = t
	for i in order.size():
		(out[order[i]] as Dictionary).order = i
	# the codes: bunker k's code in the k-th code piece by the order (not in itself)
	var code_pieces: Array = order.filter(func(id: String) -> bool: return bool((out[id] as Dictionary).code))
	var bunker_ids: Array = bunkers.map(func(b: Dictionary) -> String: return String(b.id))
	for k in bunker_ids.size():
		if code_pieces.is_empty():
			break
		var bid := String(bunker_ids[k])
		var pick := -1
		for ci in code_pieces.size():
			if String((out[code_pieces[ci]] as Dictionary).site) != bid:
				pick = ci
				break
		if pick < 0:
			continue
		(out[code_pieces[pick]] as Dictionary).code_for = bid
		code_pieces.remove_at(pick)
	return {"sites": site_list, "pieces": out, "order": order}


## Host: the trail laid on world `m` (once; after Bunkers.server_setup and Enclave.server_setup):
## the sites, the pieces, the technician (a Person flagged arche_survivor, a lone survivor at their
## hiding place, immune: what ARCHE was looking for), the decent officer told his part.
static func server_setup(m: WorldModel) -> void:
	if is_set_up():
		return
	var t := lay(m.world_seed, m.zones(), Bunkers.list(), String(m.w.get("start_zone", "")), Enclave.home_zone())
	var d := data()
	d["sites"] = t.sites
	d["pieces"] = t.pieces
	d["order"] = t.order
	d["codes"] = {}
	d["last_air"] = -100.0
	for pc: Dictionary in (t.pieces as Dictionary).values():
		match String(pc.kind):
			"survivor":
				var rng := m.rng_for("arche", "technician")
				var p: Array = pc.pos
				var g := m.new_lone(String(pc.zone), Vector2(float(p[0]), float(p[1])) + Vector2(rng.randf_range(-30.0, 30.0), rng.randf_range(-30.0, 30.0)), rng,
					"hid from ARCHE's recall after six years washing glassware on B3")
				var rec: Dictionary = m.people.get(String(g.leader), {})
				rec["arche_survivor"] = true
				rec["arche_piece"] = String(pc.id)
				rec["background"] = "lab technician"
				rec["immune"] = true
				pc["person"] = String(rec.get("id", ""))
				d["survivor"] = String(rec.get("id", ""))
			"officer":
				var o := Enclave.officer("decent")
				if not o.is_empty():
					var rec: Dictionary = m.people.get(String(o.id), {})
					rec["arche_piece"] = String(pc.id)
					pc["person"] = String(o.id)
	Bunkers.server_stock_trail()
	var tr := trail_shared()
	var r := RandomNumberGenerator.new()
	r.seed = hash([m.world_seed, "arche", "numbers"])
	for i in 6:
		var groups: Array = []
		for k in 5:
			groups.append("%05d" % r.randi_range(0, 99999))
		(tr["numbers"] as Array).append("%s ... ARCHE stations acknowledge." % " ".join(PackedStringArray(groups)))
	SessionLog.note("survival arche: %d pieces over %d sites, order %s" % [(t.order as Array).size(), (t.sites as Array).size(), ",".join(PackedStringArray(t.order))])


# --- Reading -----------------------------------------------------------------------------------

## The piece's text with its placeholders filled ({code}, {bunker}, {next}, {freq}).
static func text_of(pc: Dictionary) -> String:
	var b := Bunkers.get_bunker(String(pc.get("code_for", "")))
	var nxt := next_site(pc)
	return String(pc.get("text", "")).format({"code": String(b.get("code", "----")), "bunker": "ARCHE %s" % String(b.get("name", "a sister site")),
		"next": String(nxt.get("name", "nowhere you know")) + (" in %s" % FallenStory.zone_name(String(nxt.zone)) if not nxt.is_empty() else ""), "freq": frequency()})


## Where the trail leads from `pc`: the next unread piece's site in the order ({} at the end).
static func next_site(pc: Dictionary) -> Dictionary:
	var order: Array = data().get("order", [])
	var i := order.find(String(pc.get("id", "")))
	for k in range(i + 1, order.size()) + range(0, maxi(i, 0)):
		var o := piece(String(order[k]))
		if not bool(o.get("read", false)) and String(o.get("site", "")) != String(pc.get("site", "")):
			return site(String(o.site))
	return {}


static func site(id: String) -> Dictionary:
	for s: Dictionary in sites():
		if String(s.id) == id:
			return s
	return {}


## Host: the players read (play, hear, are told) piece `id`: a journal entry with its text, a map
## mark where it was and one where the trail leads next, its code learnt. Returns the text ("" when
## there's no such piece). Read again, the journal just recalls it.
static func server_read(id: String, s: Soldier = null) -> String:
	var pc := piece(id)
	if pc.is_empty():
		return ""
	var text := text_of(pc)
	if bool(pc.get("read", false)):
		if s:
			Survival._tell(s, String(pc.title))
		return text
	pc["read"] = true
	pc["read_day"] = WorldSim.world_now()
	(trail_shared()["pieces"] as Array).append({"id": id, "title": String(pc.title), "text": text, "day": WorldSim.world_now(), "zone": String(pc.zone),
		"kind": String(pc.kind), "theory": String(pc.get("theory", "")), "site": String(pc.site)})
	Survival._journal_line("ARCHE - %s: %s" % [String(pc.title), text])
	var here := site(String(pc.site))
	SurvivalMap.server_know(String(pc.zone), "told")
	SurvivalMap.server_add_mark(String(pc.zone), pc.pos, "ARCHE: %s" % String(here.get("name", pc.title)), "arche")
	var nxt := next_site(pc)
	if not nxt.is_empty():
		SurvivalMap.server_know(String(nxt.zone), "told")
		SurvivalMap.server_add_mark(String(nxt.zone), nxt.pos, "ARCHE? %s" % String(nxt.name), "arche")
	var bid := String(pc.get("code_for", ""))
	if bid != "":
		(data()["codes"] as Dictionary)[bid] = true
		var b := Bunkers.get_bunker(bid)
		SurvivalMap.server_add_mark(String(b.zone), b.pos, "ARCHE %s (code %s)" % [String(b.name), String(b.code)], "arche")
	if s:
		Survival._tell(s, "ARCHE: %s (in the journal)" % String(pc.title))
	var map: SurvivalMap = SurvivalMap.of(s) if s else null
	if map:
		map.server_changed()
	return text


## The shared shape the intel lane reads (the journal's "The trail" tab, the radio's numbers
## station): Survival.state()["trail"] = {"pieces": [{id, title, text, day, zone, kind, theory,
## site}] (read, in the order read), "numbers": [lines]}.
static func trail_shared() -> Dictionary:
	var st := Survival.state()
	if not st.get("trail") is Dictionary:
		st["trail"] = {}
	var t: Dictionary = st["trail"]
	if not t.get("pieces") is Array:
		t["pieces"] = []
	if not t.get("numbers") is Array:
		t["numbers"] = []
	return t


## Host: `s` reads an ARCHE document or plays a tape from his kit (`state` the entry's: its
## "piece", or a fragment). Returns the text.
static func server_read_item(s: Soldier, item_id: String, state: Dictionary) -> String:
	if not item_id in ITEMS:
		return ""
	var id := String(state.get("piece", ""))
	if id != "" and not piece(id).is_empty():
		return server_read(id, s)
	var frag := String(state.get("fragment", "An ARCHE page, the seal and a few acronyms."))
	Survival._journal_line("ARCHE - a fragment: %s" % frag)
	(trail_shared()["pieces"] as Array).append({"id": "", "title": "a fragment", "text": frag, "day": WorldSim.world_now(), "zone": WorldSim.hosted_zone(), "kind": "fragment"})
	if s:
		Survival._tell(s, frag)
	return frag


## Host: inside knowledge (joining the enclave, the decent officer's trust): the pieces at the
## enclave are read and the sealed level marked.
static func server_reveal(site_kind: String) -> void:
	for pc: Dictionary in pieces().values():
		if String(pc.get("site_kind", "")) == site_kind and not bool(pc.get("read", false)):
			server_read(String(pc.id))
	if site_kind == "enclave":
		var sl := site("sealed_level")
		if not sl.is_empty():
			SurvivalMap.server_add_mark(String(sl.zone), sl.pos, "ARCHE: the sealed level (the enclave doesn't hold it)", "arche")


## Whether the players know bunker `bid`'s code.
static func knows_code(bid: String) -> bool:
	return bool((data().get("codes", {}) as Dictionary).get(bid, false))


## The pieces at bunker `bid` that are found as items (notes, recordings), for its loot.
static func items_at(bid: String) -> Array:
	var out: Array = []
	for id: String in data().get("order", []):
		var pc := piece(id)
		if String(pc.get("site", "")) != bid:
			continue
		match String(pc.kind):
			"note", "terminal":
				out.append({"id": "arche_dossier", "count": 1, "state": {"piece": id}})
			"recording":
				out.append({"id": "arche_tape", "count": 1, "state": {"piece": id}})
	return out


static func fragment(r: RandomNumberGenerator) -> Dictionary:
	var f: Array = trail_data().get("fragments", [])
	return {"id": "arche_dossier", "count": 1, "state": {"fragment": String(f[r.randi_range(0, f.size() - 1)]) if not f.is_empty() else ""}}


## {"leak": read pieces leaning to it, "release": ...}: the two accounts, never settled.
static func theories() -> Dictionary:
	var out := {"leak": 0, "release": 0}
	for pc: Dictionary in pieces().values():
		var t := String(pc.get("theory", ""))
		if bool(pc.get("read", false)) and out.has(t):
			out[t] = int(out[t]) + 1
	return out


# --- The far tick: broadcasts ------------------------------------------------------------------

## Host, after a far tick: once a world day the next unaired broadcast (by the order) goes out on
## ARCHE's frequency from its relay: an event of kind "broadcast" with "freq" and "piece" (the radio
## lane hears it and calls server_read); when all have aired they repeat.
static func server_after_step(m: WorldModel) -> void:
	if not is_set_up() or m.now - float(data().get("last_air", -100.0)) < AIR_GAP_DAYS:
		return
	var casts: Array = []
	for id: String in data().get("order", []):
		if String(piece(id).get("kind", "")) == "broadcast":
			casts.append(id)
	if casts.is_empty():
		return
	data()["last_air"] = m.now
	var pick := ""
	for id: String in casts:
		if not bool(piece(id).get("aired", false)):
			pick = id
			break
	if pick == "":
		pick = String(casts[m.day() % casts.size()])
	var pc := piece(pick)
	pc["aired"] = true
	var e := m.event(String(pc.zone), "broadcast", [], "a voice on %s: %s" % [frequency(), String(pc.title).trim_prefix("Broadcast: ")], String(pc.site))
	e["freq"] = frequency()
	e["piece"] = pick
	e["arche"] = true
