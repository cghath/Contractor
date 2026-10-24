class_name HitReport
extends RefCounted
## One resolved hit on an armoured vehicle, for the x-ray (combined arms A5, cg_brief queue item
## 2.4; docs/combined_arms.md 2.11, F-239). Built on any peer from A2's HitEvent (VehicleModules'
## `events`: the host's own trace, sent to every peer, the last 10 kept) and the vehicle's data,
## never recomputed: the round, the plate it met and how (the angle, its KE or CE figure, the
## effective thickness, the penetration at the range flown), the outcome, the path through the
## modules with each one's state after the hit, the spall rays, the crew hit and how they are
## now, the kill states. JSON-safe (to_json / from_json round trip), so the pause menu's last hits
## and the dev's --xray-log can keep it. The card's one line (line()) and the full view's text
## (panel_text()) read it.

## The outcomes as the card says them.
const OUTCOME_WORDS := {"pen": "PENETRATION", "non_pen": "NON-PENETRATION", "ricochet": "RICOCHET", "shatter": "SHATTERED",
	"dud": "DUD", "fuzed_outside": "BURST OUTSIDE", "belly": "BELLY BLAST", "": "HIT"}
const STATE_WORDS := ["working", "damaged", "destroyed"]
const CREW_WORDS := {"up": "unhurt", "wounded": "wounded", "down": "down", "dead": "killed", "empty": "out of his seat"}
## Roles by seat kind, for the crew's words.
const ROLE_WORDS := {&"driver": "driver", &"gunner": "gunner", &"commander": "commander", &"loader": "loader", &"passenger": "rider", &"pilot": "pilot"}


## The report for HitEvent `ev` on vehicle `v` (any peer).
static func of_event(v: Vehicle, ev: Dictionary) -> Dictionary:
	var crew := {}
	var roles := {}
	for i in (v.spec.get("seats", []) as Array).size():
		crew[i] = crew_state(v.occupant(i))
		roles[i] = String(ROLE_WORDS.get(v.seat_kind(i), "rider"))
	var mods: Array = v.modules.mods if v.modules else []
	var health: PackedFloat32Array = v.modules.health if v.modules else PackedFloat32Array()
	var out := build(v.model, v.spec, mods, health, ev, crew, roles)
	out["vehicle"] = v.display_name()
	out["vid"] = v.vehicle_id
	return out


## Pure: the report from model `model`'s merged `spec`, its module layout `mods` and `health`
## now, HitEvent `ev`, the crew's states now ({seat: crew_state}) and the seats' roles ({seat: word}).
static func build(model: String, spec: Dictionary, mods: Array, health: PackedFloat32Array, ev: Dictionary, crew: Dictionary = {}, roles: Dictionary = {}) -> Dictionary:
	var shell := Shells.shell(String(ev.get("sh", "")))
	var kind := String(shell.get("kind", ""))
	var column := "ke" if kind in Shells.KE_KINDS else ("ce" if kind in Shells.CE_KINDS else "he")
	var plate := plate_of(spec, String(ev.get("pl", "")))
	var states := {}  # module index -> its state after the hit (the event's codes)
	for code: int in ev.get("m", []):
		states[code / 4] = code % 4
	var path: Array = []
	for x: Array in ev.get("x", []):
		var i := int(x[0])
		if i < 0 or i >= mods.size():
			continue
		var m: Dictionary = mods[i]
		var e := {"id": String(m.id), "kind": String(m.kind), "t0": float(x[1]), "t1": float(x[2])}
		if bool(m.get("crew", false)):
			e["seat"] = int(m.seat)
			e["state"] = String(crew.get(int(m.seat), "up"))
		else:
			e["state"] = STATE_WORDS[int(states.get(i, VehicleModules.state_of(health[i] if i < health.size() else 1.0)))]
		path.append(e)
	var changed: Array = []
	for i: int in states:
		if i < mods.size() and String(mods[i].kind) != "structure":
			changed.append({"id": String(mods[i].id), "kind": String(mods[i].kind), "state": STATE_WORDS[int(states[i])]})
	var crew_out: Array = []
	for seat: int in ev.get("c", []):
		crew_out.append({"seat": seat, "role": String(roles.get(seat, "crew")), "state": String(crew.get(seat, "up"))})
	var p: Array = ev.get("p", [0, 0, 0])
	var d: Array = ev.get("d", [0, 0, -1])
	return {"model": model, "outcome": String(ev.get("o", "")), "plate": String(ev.get("pl", "")), "plate_name": plate_name(String(ev.get("pl", ""))),
		"material": String(plate.get("material", "")), "column": column, "figure_mm": roundi(float(plate.get("ke_mm" if column == "ke" else "ce_mm", 0.0))),
		"angle": int(ev.get("th", 0)), "t_eff": int(ev.get("t", 0)), "pen": int(ev.get("pen", 0)), "range_m": int(ev.get("r", 0)),
		"shell": String(ev.get("sh", "")), "shell_name": String(shell.get("name", String(ev.get("sh", "")).to_upper())).get_slice(" ", 0),
		"entry": [float(p[0]), float(p[1]), float(p[2])], "dir": [float(d[0]), float(d[1]), float(d[2])],
		"path": path, "modules": changed, "crew": crew_out, "spall": (ev.get("sp", []) as Array).duplicate(true),
		"kill": VehicleModules.kill_text(int(ev.get("k", 0))) if int(ev.get("k", 0)) != 0 else "", "by": String(ev.get("by", "")),
		"belly": (ev.get("b", {}) as Dictionary).duplicate(true)}


## A man's state for the x-ray: "up", "wounded", "down", "dead", "empty" (nobody there).
static func crew_state(s: Soldier) -> String:
	if s == null or not is_instance_valid(s) or s.vitals == null:
		return "empty"
	if s.vitals.is_dead():
		return "dead"
	if not s.vitals.is_up():
		return "down"
	if not s.vitals.wound_list().is_empty() or s.vitals.blood_fraction() < 0.98:
		return "wounded"
	return "up"


## The plate `id` of `spec` ({} none).
static func plate_of(spec: Dictionary, id: String) -> Dictionary:
	for p: Dictionary in spec.get("plates", []):
		if String(p.get("id", "")) == id:
			return p
	return {}


## "turret_side_fwd_r" -> "Turret side (front, right)", "hull_rear" -> "Hull rear".
static func plate_name(id: String) -> String:
	if id == "":
		return "Hull"
	var words := Array(id.split("_"))
	var tags: PackedStringArray = []
	var sides := {"l": "left", "r": "right", "fl": "front left", "fr": "front right", "fwd": "front"}
	while words.size() > 1 and sides.has(String(words.back())):
		tags.insert(0, String(sides[String(words.pop_back())]))
	var text := " ".join(PackedStringArray(words))
	text = text.left(1).to_upper() + text.substr(1)
	return text + (" (%s)" % ", ".join(tags) if not tags.is_empty() else "")


## The card's one line: "PEN: engine destroyed, gunner wounded" or "RICOCHET: Turret front, 81 degrees".
static func line(r: Dictionary) -> String:
	var o := String(r.get("outcome", ""))
	var head := "PEN" if o == "pen" else String(OUTCOME_WORDS.get(o, o.to_upper()))
	var parts: PackedStringArray = []
	if o == "pen" or o == "belly":
		for m: Dictionary in r.get("modules", []):
			if String(m.state) != "working":
				parts.append("%s %s" % [String(m.id).replace("_", " "), String(m.state)])
		for c: Dictionary in r.get("crew", []):
			parts.append("%s %s" % [String(c.role), String(CREW_WORDS.get(String(c.state), String(c.state)))])
		if parts.is_empty():
			parts.append("no damage inside")
	else:
		parts.append("%s, %d degrees" % [String(r.get("plate_name", "")), int(r.get("angle", 0))])
	var out := "%s: %s" % [head, ", ".join(parts)]
	if String(r.get("kill", "")) != "":
		out += " [%s]" % String(r.kill)
	return out


## The full view's text: "Turret side, 300 mm KE at 38 degrees: 381 mm effective. M791 at 640 m:
## 66 mm. NON-PENETRATION." then the path and the crew, a line each.
static func panel_text(r: Dictionary) -> String:
	var lines: PackedStringArray = []
	var col := String(r.get("column", "ke")).to_upper()
	if String(r.get("outcome", "")) == "belly":
		var b: Dictionary = r.get("belly", {})
		lines.append("Under the hull (%s): %.2f kg on the floor, %s." % [String(b.get("st", "belly")), float(b.get("kg", 0.0)), "held" if bool(b.get("held", false)) else "over what it holds"])
	else:
		lines.append("%s, %d mm %s at %d degrees: %d mm effective." % [String(r.get("plate_name", "")), int(r.get("figure_mm", 0)), col, int(r.get("angle", 0)), int(r.get("t_eff", 0))])
		lines.append("%s at %d m: %d mm. %s." % [String(r.get("shell_name", "")), int(r.get("range_m", 0)), int(r.get("pen", 0)),
			String(OUTCOME_WORDS.get(String(r.get("outcome", "")), String(r.get("outcome", "")).to_upper()))])
	for e: Dictionary in r.get("path", []):
		lines.append("  %s: %s" % [String(e.id).replace("_", " "), String(CREW_WORDS.get(String(e.state), String(e.state))) if e.has("seat") else String(e.state)])
	if not (r.get("spall", []) as Array).is_empty():
		lines.append("  spall: %d fragments shown" % (r.spall as Array).size())
	for c: Dictionary in r.get("crew", []):
		lines.append("  %s (seat %d): %s" % [String(c.role).capitalize(), int(c.seat), String(CREW_WORDS.get(String(c.state), String(c.state)))])
	if String(r.get("kill", "")) != "":
		lines.append("Kill: %s" % String(r.kill))
	return "\n".join(lines)


## JSON text and back (the pause menu's last hits, the --xray-log): the same report.
static func to_json(r: Dictionary) -> String:
	return JSON.stringify(r)


static func from_json(text: String) -> Dictionary:
	var v: Variant = JSON.parse_string(text)
	return v if v is Dictionary else {}
