class_name Cure
extends RefCounted
## The cure chain's places and the serum (docs/survival_medical.md section 3, calls 15 and 46;
## docs/survival_enclave.md): the lab zone's equipment (a centrifuge, a fridge, power: markers at
## its first place, the power from a jerrycan for the generator or a vehicle battery), the immune
## (SurvivorPerson records with "immune": rolled once a world at IMMUNE_CHANCE, at least one
## always, ARCHE's technician among them), and server_make_serum: a survivor at medical 9 (Rpg's
## "cure_chain" gate) in the lab zone with its equipment powered and an immune donor with him
## (a companion or settler, or a person in the lab zone) makes one dose of "serum". The rare serum
## is also in the hospital, lab and bunker loot tables (data/bunkers.json, Bunkers.roll_table).
## server_apply clears a bite: the "bitten" meta on a body and the record's bite (phase D's
## fever clock reads them). State: Survival.state()["cure"]: {"lab": {zone, pos, centrifuge,
## fridge, power}, "made": n, "tested": {person id: true}}.

const KEY := "cure"
## Proposed: the immunity roll (survival_medical.md 3: 3%; fitness and fieldcraft raise it in
## the RPG lane's own roll), and what a lab's power costs.
const IMMUNE_CHANCE := 0.03
const POWER_ITEMS: Array[String] = ["jerrycan", "vehicle_battery"]
const SKILL := 9


static func data() -> Dictionary:
	var st := Survival.state()
	if not st.get(KEY) is Dictionary:
		st[KEY] = {}
	return st[KEY]


static func is_set_up() -> bool:
	return data().has("lab")


static func lab() -> Dictionary:
	return data().get("lab", {})


## Host: the lab's place and equipment on world `m`, and the immune among its people (once).
static func server_setup(m: WorldModel) -> void:
	if is_set_up():
		return
	var lab_zone := ""
	for z: String in WorldModel._sorted(m.zones().keys()):
		if String(m.zone(z).get("type", "")) == "lab":
			lab_zone = z
			break
	var pos := [0.0, 0.0]
	if lab_zone != "":
		var places: Array = m.zone(lab_zone).get("places", [])
		if not places.is_empty():
			var p: Array = (places[0] as Dictionary).get("pos", [0.0, 0.0])
			pos = [float(p[0]), float(p[1])]
	data()["lab"] = {"zone": lab_zone, "pos": pos, "centrifuge": true, "fridge": true, "power": false}
	data()["made"] = 0
	data()["tested"] = {}
	server_roll_immune(m.people, m.world_seed)


## Host: the immunity roll over `people` (once a person: "immune_rolled"); at least one immune in
## the world (a grouped settler's, by the seed) so the chain can always be found.
static func server_roll_immune(people: Dictionary, world_seed: int) -> void:
	var any := false
	var settlers: Array = []
	for pid: String in WorldModel._sorted(people.keys()):
		var rec: Dictionary = people[pid]
		if not bool(rec.get("immune_rolled", false)):
			rec["immune_rolled"] = true
			var r := RandomNumberGenerator.new()
			r.seed = hash([world_seed, pid, "immune"])
			if r.randf() < IMMUNE_CHANCE:
				rec["immune"] = true
		any = any or bool(rec.get("immune", false))
		if String(rec.get("status", "")) in [WorldGroup.GROUPED, "out_there"] and not bool(rec.get("enclave", false)):
			settlers.append(pid)
	if not any and not settlers.is_empty():
		var r := RandomNumberGenerator.new()
		r.seed = hash([world_seed, "the immune"])
		(people[settlers[r.randi_range(0, settlers.size() - 1)]] as Dictionary)["immune"] = true


## The immune people the world has (ids), known or not.
static func immune_people() -> Array:
	var out: Array = []
	for pid: String in WorldModel._sorted(WorldSim.people().keys()):
		var rec: Dictionary = WorldSim.people()[pid]
		if bool(rec.get("immune", false)) and String(rec.get("status", "")) != "dead":
			out.append(pid)
	return out


## Whether the lab is ready: its centrifuge and fridge there and its power on.
static func lab_ready() -> bool:
	var l := lab()
	return not l.is_empty() and String(l.get("zone", "")) != "" and bool(l.get("centrifuge", false)) and bool(l.get("fridge", false)) and bool(l.get("power", false))


## Whether `s` is at the lab (its zone is the one hosted; `s` near its place when there's a body).
static func at_lab(_s: Soldier) -> bool:
	return String(lab().get("zone", "")) != "" and WorldSim.hosted_zone() == String(lab().get("zone", ""))


## Host: power to the lab's equipment: `s` spends a jerrycan (the generator) or a battery, or
## `free` (a generator the building lane wired). Returns why not.
static func server_power_lab(s: Soldier = null, free := false) -> String:
	if lab().is_empty() or String(lab().get("zone", "")) == "":
		return "There's no lab"
	if bool(lab().get("power", false)):
		return ""
	if not free:
		var spent := false
		for it: String in POWER_ITEMS:
			if FallenStory.take_one(s, it):
				spent = true
				break
		if not spent:
			return "The lab's generator needs fuel or a battery"
	lab()["power"] = true
	Survival._journal_line("The lab has power: the centrifuge turns, the fridge hums.")
	return ""


## An immune donor with `s`: `donor` if given and immune (and not dead), else an immune companion
## or settler, else an immune person in the lab's zone. "" when none.
static func donor_for(_s: Soldier, donor := "") -> String:
	var people := WorldSim.people()
	if donor != "":
		var rec: Dictionary = people.get(donor, {})
		return donor if bool(rec.get("immune", false)) and String(rec.get("status", "")) in ["companion", "settler", "out_there", "player"] else ""
	for pid: String in immune_people():
		var rec: Dictionary = people[pid]
		if String(rec.get("status", "")) in ["companion", "settler"]:
			return pid
		if String(rec.get("status", "")) == "out_there" and String(rec.get("zone", "")) == String(lab().get("zone", "")):
			return pid
	return ""


## Host: a test of `pid`'s blood at the lab (powered): whether they're immune, now known.
static func server_test_blood(pid: String) -> bool:
	if not lab_ready():
		return false
	var rec: Dictionary = WorldSim.people().get(pid, {})
	var imm := bool(rec.get("immune", false))
	(data()["tested"] as Dictionary)[pid] = imm
	rec["immune_known"] = true
	Survival._journal_line("The lab's test: %s %s." % [String(rec.get("name", "they")), "doesn't turn: immune" if imm else "would turn like anyone"])
	return imm


## Host: `s` makes a dose of serum: medical SKILL (Rpg's cure_chain gate), at the lab with its
## equipment powered, an immune donor with him (`donor` or the first found). One dose into his kit.
## Returns why not ("" made).
static func server_make_serum(s: Soldier, donor := "") -> String:
	if s == null:
		return "Nobody to work the bench"
	if not _skilled(s):
		return "It takes a medic's skill (medical %d) to run the chain" % SKILL
	if not at_lab(s):
		return "It needs the lab"
	if not lab_ready():
		return "The lab's equipment needs power" if bool(lab().get("centrifuge", false)) else "The lab's equipment is broken"
	var pid := donor_for(s, donor)
	if pid == "":
		return "It needs blood from someone who doesn't turn"
	if s.inventory.take(&"serum", 1) != 1:
		return "No room to carry the dose"
	data()["made"] = int(data().get("made", 0)) + 1
	var rec: Dictionary = WorldSim.people().get(pid, {})
	rec["immune_known"] = true
	rec["gave_blood"] = int(rec.get("gave_blood", 0)) + 1
	Moods.add(rec, "gave_blood", -3.0, 24.0)
	Survival._journal_line("We made a dose of the serum at the lab, from %s's blood." % String(rec.get("name", "a donor")))
	Survival._tell(s, "One dose of serum: it cures a bite before the end")
	return ""


## Medical SKILL: the RPG lane's "cure_chain" gate (it passes for the AI and outside survival).
static func _skilled(s: Soldier) -> bool:
	return Rpg.can(s, "cure_chain") and (not Rpg.active(s) or Rpg.level(s, "medical") >= SKILL)


## Host: the serum given: clears the bite on `s` (a body: its "bitten" meta) or on `rec` (a
## person's record: "bitten", "bite_day", "fever"); spends one dose from `s` when `use_dose`
## (the giver's kit). Returns whether a bite was cleared (phase D's fever clock reads these).
static func server_apply(s: Soldier = null, rec := {}, use_dose := true) -> bool:
	if use_dose and s != null and not FallenStory.take_one(s, "serum"):
		return false
	var cleared := false
	if s != null and s.has_meta(&"bitten"):
		s.remove_meta(&"bitten")
		cleared = true
	var body_rec: Dictionary = Survival.survivor_of(s) if s != null and rec.is_empty() else rec
	for k: String in ["bitten", "bite_day", "fever"]:
		if body_rec.has(k):
			body_rec.erase(k)
			cleared = true
	if cleared:
		Survival._journal_line("The serum took. The fever broke.")
	return cleared
