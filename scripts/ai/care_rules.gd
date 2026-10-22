class_name CareRules
extends RefCounted
## Who gets care next, who carries a casualty out, and when a downed man gives up
## (docs/high_command.md section 9 lift 3). Pure: the co-op soak's _treat_loop, _casevac_tick and
## _give_up_tick decisions, so hero squads and the soak share one rule. Carrying stays a chosen,
## announced act (Captain, 2026-10-14: no reflex body-hauling): casevac_carrier only names who
## would; the caller decides and says it.

## The soak's numbers: down this long with nobody up to help, give up; with others up but
## nobody coming, GIVE_UP_ALONE_S (S0758).
const GIVE_UP_S := 45.0
const GIVE_UP_ALONE_S := 120.0
## Already at the rally point: no casevac needed.
const AT_RALLY_M := 8.0


## The casualty to treat next from `casualties` ([{"id", "urgent": bool, "bleeding": bool,
## "dist": float, "being_treated": bool}]): massive bleeding first, then urgent, then the
## nearest; one someone else is treating only if nobody else needs it. {} for none.
static func next_casualty(casualties: Array) -> Dictionary:
	var best := {}
	var best_key := INF
	for c: Dictionary in casualties:
		var key := float(c.get("dist", 0.0))
		if bool(c.get("bleeding", false)):
			key -= 2000.0
		elif bool(c.get("urgent", false)):
			key -= 1000.0
		if bool(c.get("being_treated", false)):
			key += 5000.0
		if key < best_key:
			best_key = key
			best = c
	return best


## Whether a man down `down_for` seconds gives up: nobody up who could come (`others_up` 0),
## or `alone_rule` (a human leads and nobody came) past GIVE_UP_ALONE_S.
static func give_up(down_for: float, others_up: int, alone_rule := false) -> bool:
	if down_for < GIVE_UP_S:
		return false
	return others_up == 0 or (alone_rule and down_for >= GIVE_UP_ALONE_S)


## Who would carry a casualty lying at `casualty` to `rally`: the nearest of `carriers`
## ([{"id", "pos": Vector3, "up": bool, "carrying": bool}]) up and free. "" when none, or when
## the casualty is already at the rally point.
static func casevac_carrier(casualty: Vector3, rally: Vector3, carriers: Array) -> String:
	if _flat(casualty, rally) < AT_RALLY_M:
		return ""
	var best := ""
	var best_d := INF
	for c: Dictionary in carriers:
		if not bool(c.get("up", true)) or bool(c.get("carrying", false)):
			continue
		var d := _flat(c.get("pos", Vector3.ZERO), casualty)
		if d < best_d:
			best_d = d
			best = String(c.get("id", ""))
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
