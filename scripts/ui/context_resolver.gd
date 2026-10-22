class_name ContextResolver
extends RefCounted
## What you can do about what you're looking at (docs/combined_arms.md 5.5): given what's under
## the crosshair or cursor, what's selected and the situation, the ordered options, the first one
## the one key's default. Pure; the same table serves the world (ContextMenu), the map and the HC
## camera. Recently used options come first for each kind of target (the last RECENT of them).
##
## resolve(ctx) -> [{"id", "label", "do", ...}]. ctx:
##   "kind": what's under the cursor (KINDS), "selected": "gun_team" or "", "contact": bool,
##   "casualty_near": bool, "armour_paired": bool, "doors": [door option ids] (a door's own:
##   "kick", "open", "charge", "shotgun", "flash", "frag"), "seat_role": "driver"|"gunner"|... (the
##   crew wheel), "recent": {kind: [ids]} (else the resolver's own `recent`).
## "do" says how ContextMenu carries it out: "squad" (a squad command "cmd", "point" true when
## it's at the target, "names": "target" for the man looked at), "hc" (a high command "verb" for
## the squad looked at), "request" (RequestBroker "kind" to the unit looked at), "local" (the
## player's own act "what"), "menu" (opens the full command menu: More...).

const KINDS: Array[String] = ["squadmate", "hero_squad", "allied_unit", "door", "building", "casualty", "our_vehicle",
	"allied_armour", "enemy", "gun_team", "ground", "crew"]
const RECENT := 3
const MORE := {"id": "more", "label": "More...", "do": "menu"}

## Per peer: the last RECENT option ids picked for each kind (recent first).
static var recent := {}


static func resolve(ctx: Dictionary) -> Array[Dictionary]:
	var kind := String(ctx.get("kind", "ground"))
	var out: Array[Dictionary] = []
	match kind:
		"squadmate":
			out = [_o("follow", "Follow me", "squad", {"cmd": "follow", "names": "target"}),
				_o("hold", "Hold", "squad", {"cmd": "hold", "names": "target"}),
				_o("move", "Move here", "squad", {"cmd": "move", "point": true, "names": "target"}),
				_o("heal", "Heal", "squad", {"cmd": "heal", "names": "target"}),
				_o("swap_kit", "Swap kit", "local", {"what": "loot"})]
		"hero_squad":
			out = [_o("hc_move", "Move", "hc", {"verb": "move", "point": true}), _o("hc_defend", "Defend", "hc", {"verb": "defend", "point": true}),
				_o("hc_attack", "Attack", "hc", {"verb": "attack", "point": true}), _o("hc_sbf", "Support by fire", "hc", {"verb": "sbf", "point": true}),
				_o("hc_regroup", "Regroup", "hc", {"verb": "regroup", "point": true})]
		"allied_unit":
			var first := "suppress" if bool(ctx.get("contact", false)) else ("medic" if bool(ctx.get("casualty_near", false)) else "")
			var asks := ["suppress", "medic", "smoke", "armour", "hold", "cover", "fire", "pickup", "ammo", "sitrep"]
			if first != "":
				asks.erase(first)
				asks.push_front(first)
			for k: String in asks:
				out.append(_o("req_" + k, "Request: %s" % REQUEST_LABELS[k], "local" if k == "fire" else "request", {"kind": k, "what": "fire_support"}))
		"door", "building":
			out = [_o("stack", "Stack up", "squad", {"cmd": "clear:onme", "point": true})]
			for d: String in ctx.get("doors", ["kick", "open"]):
				out.append(_o("breach_" + d, "Breach: %s" % DOOR_LABELS.get(d, d), "squad", {"cmd": "clear:" + d, "point": true}))
			out.append(_o("clear", "Clear", "squad", {"cmd": "clear", "point": true}))
			if bool(ctx.get("armour_paired", false)):
				out.append(_o("engage_building", "Armour: engage the building", "request", {"kind": "armour"}))
		"casualty":
			out = [_o("treat", "Treat", "local", {"what": "treat"}), _o("carry", "Carry", "local", {"what": "carry"}),
				_o("call_medic", "Call a medic", "squad", {"cmd": "call_medic", "point": true}), _o("casevac", "CASEVAC", "request", {"kind": "casevac"})]
		"our_vehicle":
			out = [_o("get_in", "Get in", "local", {"what": "get_in"}), _o("drive", "Drive", "local", {"what": "drive"}),
				_o("take_gun", "Take the gun", "local", {"what": "take_gun"}), _o("command", "Command it", "menu", {})]
		"allied_armour":
			out = [_o("req_armour", "Request armour support", "request", {"kind": "armour"}), _o("ride", "Ride with them", "request", {"kind": "pickup"})]
		"enemy":
			out = [_o("target", "Target", "local", {"what": "target"}), _o("suppress", "Suppress", "squad", {"cmd": "suppress", "point": true}),
				_o("tag", "Tag", "local", {"what": "tag"}), _o("report", "Report", "local", {"what": "report"})]
			if String(ctx.get("selected", "")) == "gun_team":
				out.push_front(_o("gun_cover", "Place gun to cover it", "squad", {"cmd": "wt_setup", "point": true, "aim": true}))
		"gun_team":
			out = [_o("gun_here", "Set up here", "squad", {"cmd": "wt_setup", "point": true}), _o("gun_facing", "Facing", "squad", {"cmd": "wt_setup", "point": true, "aim": true}),
				_o("gun_pack", "Pack up", "squad", {"cmd": "wt_pack"})]
		"crew":
			var role := String(ctx.get("seat_role", "driver"))
			if role == "driver":
				out = [_o("crew_stop", "Driver: stop", "local", {"what": "crew_stop"}), _o("crew_hull_down", "Driver: hull down", "local", {"what": "crew_hull_down"})]
			else:
				out = [_o("crew_fire", "Gunner: fire at will", "local", {"what": "crew_fire"}), _o("crew_hold", "Gunner: hold fire", "local", {"what": "crew_hold"})]
			out.append(_o("pop_smoke", "Pop smoke", "local", {"what": "pop_smoke"}))
			out.append(_o("bail", "Bail out", "local", {"what": "bail"}))
		_:
			if String(ctx.get("selected", "")) == "gun_team":
				out = [_o("gun_here", "Place the gun here", "squad", {"cmd": "wt_setup", "point": true})]
			out.append_array([_o("move", "Move here", "squad", {"cmd": "move", "point": true}), _o("hold_here", "Hold here", "squad", {"cmd": "hold", "point": true}),
				_o("mark", "Mark", "local", {"what": "mark"})])
			if String(ctx.get("selected", "")) != "gun_team":
				out.append(_o("gun_here", "Place the gun", "squad", {"cmd": "wt_setup", "point": true}))
			out.append(_o("check_fire", "Check fire here", "request", {"kind": "check_fire"}))  # every friendly gun into 100 m stops 30 s (combined_arms 4.5)
	out = _recent_first(out, kind, ctx.get("recent", recent))
	out.append(MORE.duplicate())
	return out


## The high command orders to put first on the map's and the HC camera's order bar for what's
## under the cursor (`kind`: "enemy", "building", "extraction", "ground"), the recently used first.
static func hc_first(kind: String, rec: Dictionary = recent) -> Array[String]:
	var base: Array = {"enemy": ["attack", "sbf"], "building": ["defend", "attack"], "extraction": ["extract"]}.get(kind, ["move", "defend"])
	var out: Array[String] = []
	for v: Variant in rec.get("map:" + kind, []):
		if String(v) not in out:
			out.append(String(v))
	for v: Variant in base:
		if String(v) not in out:
			out.append(String(v))
	return out


## The one key's default for `ctx` (the top option).
static func default_of(ctx: Dictionary) -> Dictionary:
	var opts := resolve(ctx)
	return opts[0] if not opts.is_empty() else {}


## Records `id` as just used for `kind` (recent first next time).
static func used(kind: String, id: String, into: Dictionary = recent) -> void:
	var list: Array = into.get(kind, [])
	list.erase(id)
	list.push_front(id)
	if list.size() > RECENT:
		list.resize(RECENT)
	into[kind] = list


static func _recent_first(opts: Array[Dictionary], kind: String, rec: Dictionary) -> Array[Dictionary]:
	var ids: Array = rec.get(kind, [])
	if ids.is_empty():
		return opts
	var out: Array[Dictionary] = []
	for id: Variant in ids:
		for o in opts:
			if String(o.id) == String(id) and o not in out:
				out.append(o)
	for o in opts:
		if o not in out:
			out.append(o)
	return out


static func _o(id: String, label: String, how: String, extra: Dictionary) -> Dictionary:
	var o := {"id": id, "label": label, "do": how}
	o.merge(extra)
	return o


const REQUEST_LABELS := {"suppress": "suppress", "medic": "a medic", "smoke": "smoke", "armour": "armour support", "hold": "hold here",
	"cover": "cover my move", "fire": "fire support", "pickup": "transport", "ammo": "ammo", "sitrep": "sitrep"}
const DOOR_LABELS := {"kick": "kick it in", "open": "open it", "charge": "charge", "shotgun": "shotgun", "flash": "flash and clear", "frag": "frag and clear"}
