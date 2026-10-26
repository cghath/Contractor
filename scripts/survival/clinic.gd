class_name Clinic
extends RefCounted
## The settlement's clinic in Contractor: Fallen (docs/survival_hands.md; docs/survival_medical.md
## sections 1-3; calls 60-63): the pieces clinic_bed, clinic_cabinet and clinic_lamp (BuildPieces),
## the settler job "doctor" (SettlementJobs: a settler at DOCTOR_LEVEL in medicine with a clinic bed
## built), and care:
## - **Patients in a clinic bed** heal faster: a player lying within reach of a built clinic bed (the
##   same test as Surgery's "clinic" surface) is "in care" (the body's "care": the body screen shows it
##   with the doctor's name), his wounds heal BED_HEAL_X (DOCTOR_HEAL_X with a doctor at the
##   settlement), his sicknesses run out SICK_X as fast, the clean bed takes dirt off open wounds, and
##   a doctor's care slows a bite's fever (BiteFever's care_h). Settlers with wounds or a sickness (and
##   the quarantined) go into the beds when the doctor works: a med from the cabinet a wound, up to
##   TREATS_H an hour; a gunshot wound is operated on first (settler_surgery: the doctor's skill, the
##   clinic's low infection chance).
## - **Surgery in a clinic** (the player's stays as Surgery built it) has a lower chance of the wound
##   going bad after (INFECT: the post-op roll Surgery makes through after_surgery).
## - **The cabinet** holds the clinic's medical stock (the settlement record's "clinic" "stock"; a
##   player stocks it from the cabinet's menu); empty or low, the doctor files a "medical supplies"
##   work order (WorkOrders), which a doctor fills from the settlement's meds.
## - **Quarantine**: a bitten settler put in a bed with the flag; the council votes on what to do
##   (keep them in the bed, or send them away).
## Every number here is Proposed.

const DOCTOR_LEVEL := 2
const BED_HEAL_X := 1.5
const DOCTOR_HEAL_X := 2.0
const SICK_X := 1.5
## Dirt the clean bed takes off an open wound an hour (as a share of Infection.DIRT_OPEN_H's pace).
const CLEAN_BED := 0.5
## The chance a wound goes bad after surgery, by the surface (Surgery.surface_of); a doctor at the
## settlement halves the clinic's.
const INFECT := {"clinic": 0.06, "bed": 0.15, "table": 0.15, "floor": 0.2, "ground": 0.3}
const DOCTOR_INFECT_X := 0.5
## The doctor's hour: wounds treated (a med each), a settler's gunshot wound operated on.
const TREATS_H := 2
const SURGERY_BASE := 0.6
const SURGERY_PER_LEVEL := 0.08
## The cabinet: under LOW meds the doctor files an order for ORDER meds.
const LOW := 2
const ORDER := 6

## Tests: a roll to use instead of randf() (-1: roll for real).
static var force_roll := -1.0


static func _roll() -> float:
	return force_roll if force_roll >= 0.0 else randf()


static func rec() -> Dictionary:
	var d := Settlement.data()
	if not d.get("clinic") is Dictionary:
		d["clinic"] = {"stock": {}}
	var c: Dictionary = d["clinic"]
	if not c.get("stock") is Dictionary:
		c["stock"] = {}
	return c


## Built clinic beds at the settlement.
static func beds() -> int:
	return int(Settlement.data().get("clinic_beds", 0)) if Settlement.exists() else 0


# --- The doctor -------------------------------------------------------------------------------------

## A settler's medicine: the RPG lane's skills on the record, else what the background gave.
static func medical_of(r: Dictionary) -> int:
	var lvl := int((r.get("skills", {}) as Dictionary).get("medical", 0))
	var bg: Dictionary = Backgrounds.ALL.get(String(r.get("background", "")), {})
	lvl = maxi(lvl, int((bg.get("lines", {}) as Dictionary).get("medical", 0)))
	return lvl


## Whether settler `r` can be the doctor: the job held, the skill, a clinic bed built.
static func can_doctor(r: Dictionary) -> bool:
	return "doctor" in Settlement.jobs_of(r) and medical_of(r) >= DOCTOR_LEVEL and beds() > 0


## The settlement's doctor ({} none).
static func doctor() -> Dictionary:
	if not Settlement.exists():
		return {}
	for r: Dictionary in Settlement.settlers():
		if can_doctor(r):
			return r
	return {}


static func doctor_name() -> String:
	return String(doctor().get("name", ""))


# --- The cabinet ----------------------------------------------------------------------------------

static func stock_count() -> int:
	var n := 0
	for id: String in rec().stock:
		n += int(rec().stock[id])
	return n


static func _put(id: String, n: int) -> void:
	var st: Dictionary = rec().stock
	st[id] = int(st.get(id, 0)) + n


## Takes one med out of the cabinet. Returns its id, or "".
static func take_one() -> String:
	var st: Dictionary = rec().stock
	for id: String in st.keys():
		if int(st[id]) > 0:
			st[id] = int(st[id]) - 1
			if int(st[id]) <= 0:
				st.erase(id)
			return id
	return ""


static func _is_med(id: String) -> bool:
	return Settlement.category_of(id) == "meds"


## Host: `s` puts the meds he carries into the cabinet (his stowed medical items). Returns how many.
static func server_stock(s: Soldier) -> int:
	var moved := 0
	var found := true
	while found:  # (one entry at a time: every removal rebuilds the inventory's lists)
		found = false
		for c: StringName in s.inventory.search_containers():
			var list: Array = s.inventory.containers.get(c, [])
			for i in list.size():
				var e: Dictionary = list[i]
				if _is_med(String(e.id)):
					var n := int(e.get("count", 1))
					var got: Dictionary = s.inventory.remove_entry(c, i, n)
					_put(String(e.id), int(got.get("count", 0)))
					moved += int(got.get("count", 0))
					found = not got.is_empty()
					break
			if found:
				break
	if moved > 0:
		_order_done(moved)
	return moved


## Host: up to `n` meds from the settlement's stores into the cabinet. Returns how many.
static func restock_from_stores(n: int) -> int:
	var moved := 0
	while moved < n:
		var id := Settlement.first_stocked(func(_item: ItemData, iid: String) -> bool: return _is_med(iid))
		if id == "":
			break
		var got := Settlement.taken_count(Settlement.server_take(id, 1))
		if got <= 0:
			break
		_put(id, got)
		moved += got
	return moved


## The open "medical supplies" order ({} none).
static func open_order() -> Dictionary:
	for o: Dictionary in WorkOrders.open_orders():
		if String(o.kind) == "medical_supplies":
			return o
	return {}


static func _order_done(n: int) -> void:
	var o := open_order()
	if o.is_empty():
		return
	o["done"] = int(o.done) + n
	if int(o.done) >= int(o.count):
		o["state"] = "done"


## Host: the cabinet low: a "medical supplies" order if there isn't one open. Returns it.
static func server_file_order() -> Dictionary:
	var o := open_order()
	if not o.is_empty():
		return o
	return WorkOrders.server_add("medical_supplies", ORDER, 2)


## WorkOrders' "medical supplies": `hours` of it (the doctor fetches meds from the stores into the
## cabinet). Returns whether anything was done.
static func work_order(o: Dictionary, hours: float) -> bool:
	var left := int(o.count) - int(o.done)
	var n := restock_from_stores(mini(left, TREATS_H * 3 * maxi(1, roundi(hours))))
	o["done"] = int(o.done) + n
	return n > 0


# --- Care (players) ----------------------------------------------------------------------------------

## Whether `s` lies in a clinic bed (a built one within reach: Surgery's "clinic" surface).
static func in_bed(s: Soldier) -> bool:
	return s != null and Surgery.surface_of(s) == "clinic"


static func heal_mult() -> float:
	return DOCTOR_HEAL_X if not doctor().is_empty() else BED_HEAL_X


## Host (Body.server_step): `world_h` hours of `s` (body `n`) in or out of care.
static func server_care(s: Soldier, n: Dictionary, world_h: float) -> void:
	if not in_bed(s):
		n.erase("care")
		return
	care_step(n, world_h, doctor_name())


## `world_h` hours of body `n` in a clinic bed (with `doc` the doctor's name, "" none): the extra
## healing, sicknesses running out faster, the clean bed, the doctor's care on a bite.
static func care_step(n: Dictionary, world_h: float, doc: String) -> void:
	n["care"] = {"doctor": doc, "bed": true}
	if world_h <= 0.0:
		return
	var mult := DOCTOR_HEAL_X if doc != "" else BED_HEAL_X
	for r: Dictionary in Infection.records(n):
		var rate := Infection.heal_rate(n, r)
		if rate > 0.0:
			r.heal_h = float(r.heal_h) - world_h * rate * (mult - 1.0)
		if int(r.stage) == 0 and not bool(r.get("closed", false)):
			r.dirt = maxf(0.0, float(r.dirt) - world_h / Infection.DIRT_OPEN_H * CLEAN_BED)
	for id: String in Sickness.ills(n):
		var d: Dictionary = Sickness.ills(n)[id]
		if d.has("left_h") and float(d.get("onset_h", 0.0)) <= 0.0:
			d.left_h = float(d.left_h) - world_h * (SICK_X - 1.0)
	var sick: Dictionary = n.get("sick", {})
	if sick.has("left_h"):
		sick.left_h = maxf(0.0, float(sick.left_h) - world_h * (SICK_X - 1.0))
	if doc != "":
		n["care_h"] = maxf(float(n.get("care_h", 0.0)), world_h + 1.0)  # (a doctor's care slows the bite's fever)


## The body screen's line: "in care: Dr Ana Reyes", "in a clinic bed", or "".
static func words(n: Dictionary) -> String:
	var c: Dictionary = n.get("care", {})
	if c.is_empty():
		return ""
	return "in care: %s" % String(c.doctor) if String(c.get("doctor", "")) != "" else "in a clinic bed (no doctor)"


# --- Surgery ---------------------------------------------------------------------------------------

## The chance a wound goes bad after surgery on `surface` (with a doctor at the settlement).
static func infect_chance(surface: String, with_doctor := false) -> float:
	var c := float(INFECT.get(surface, INFECT.ground))
	if surface == "clinic" and with_doctor:
		c *= DOCTOR_INFECT_X
	return c


## The post-op roll (0..1) for Surgery: Clinic.force_roll in tests; none (1.0, it never goes bad)
## while a test forces the surgery's own roll and not this one; else random.
static func post_op_roll(surgery_force: float) -> float:
	if force_roll >= 0.0:
		return force_roll
	return 1.0 if surgery_force >= 0.0 else randf()


## Host (Surgery.server_operate, a success): the post-op roll for wound record `r` on `surface`;
## a bad one leaves it contaminated. Returns whether it went bad.
static func after_surgery(r: Dictionary, surface: String, roll: float) -> bool:
	if r.is_empty() or bool(r.get("closed", false)):
		return false
	if roll >= infect_chance(surface, surface == "clinic" and not doctor().is_empty()):
		return false
	r["dirt"] = 1.0
	r["stage"] = maxi(int(r.get("stage", 0)), 1)
	r["stage_h"] = 0.0
	return true


## The doctor (`doc`, a settler record) operates on settler `patient`'s wound `w` (a gunshot): a
## chance by his skill, a med from the cabinet (without one, worse); the clinic's infection roll.
## Returns {"ok", "infected"}.
static func settler_surgery(doc: Dictionary, patient: Dictionary, w: Dictionary) -> Dictionary:
	var c := SURGERY_BASE + SURGERY_PER_LEVEL * maxi(0, medical_of(doc) - DOCTOR_LEVEL)
	if take_one() == "":
		c *= 0.7
	var ok := _roll() < minf(0.95, c)
	var infected := false
	if ok:
		w["operated"] = true
		infected = _roll() < infect_chance("clinic", true)
		if infected:
			w["infected"] = true
	SurvivorPerson.note(patient, "operated on in the clinic" if ok else "an operation in the clinic went badly")
	return {"ok": ok, "infected": infected}


# --- The doctor's hour (SettlementJobs) -----------------------------------------------------------

## The members needing a bed: the quarantined first, then the wounded and the sick (up to the beds).
static func patients(st: Settlement) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	for m: Dictionary in st.members():
		if bool(m.get("quarantine", false)):
			out.append(m)
		elif not (m.get("wounds", []) as Array).is_empty() or not Sickness.shown(m.get("needs", {}) as Dictionary).is_empty() or not ((m.get("needs", {}) as Dictionary).get("sick", {}) as Dictionary).is_empty():
			rest.append(m)
	out.append_array(rest)
	if out.size() > beds():
		out.resize(beds())
	return out


## Host: settler `doc` works `hours` as the doctor at `st`. Returns whether there was work.
static func work(st: Settlement, doc: Dictionary, hours: float) -> bool:
	if beds() <= 0 or medical_of(doc) < DOCTOR_LEVEL:
		return false
	for m: Dictionary in st.members():
		m.erase("in_care")
	var list := patients(st)
	var treated := 0
	var cap := TREATS_H * maxi(1, roundi(hours))
	var name := String(doc.get("name", "the doctor"))
	for p: Dictionary in list:
		p["in_care"] = name
		var n: Dictionary = p.get("needs", {})
		if not n.is_empty():
			care_step(n, hours, name)
		var wounds: Array = p.get("wounds", [])
		while not wounds.is_empty() and treated < cap:
			var w: Dictionary = wounds[0] if wounds[0] is Dictionary else {}
			if String(w.get("kind", "")) == "gunshot" and not bool(w.get("operated", false)):
				settler_surgery(doc, p, w)
				treated += 1
				continue
			if take_one() == "":
				break
			wounds.remove_at(0)
			treated += 1
		p["wounds"] = wounds
	if stock_count() < LOW:
		server_file_order()
	return not list.is_empty()


# --- Quarantine -------------------------------------------------------------------------------------

## Host: settler `r` into a clinic bed with the quarantine flag, and the council's vote on them
## (keep them in the bed, or send them away). Returns the vote's id (-1 none).
static func server_quarantine(r: Dictionary) -> int:
	if r.is_empty() or bool(r.get("quarantine", false)):
		return -1
	r["quarantine"] = true
	var pid := String(r.get("id", ""))
	var who := String(r.get("name", "someone"))
	Survival._journal_line("%s is bitten and in quarantine in the clinic." % who)
	return Council.server_put({"kind": "custom", "text": "%s is bitten and in quarantine: keep them in the clinic bed, or send them away" % who},
		["keep them", "send them away"], func(result: String) -> void: on_vote(pid, result))


## The council's call on a quarantined settler `pid`.
static func on_vote(pid: String, result: String) -> void:
	for r: Dictionary in Settlement.settlers():
		if String(r.get("id", "")) != pid:
			continue
		if result == "send them away":
			r.erase("quarantine")
			Settlement.server_unsettle(r)
			Survival._journal_line("The council sent %s away." % String(r.get("name", "them")))
		else:
			r["quarantine_kept"] = true
		return


## Host: every bitten settler (a bite clock on their body) quarantined. Returns how many.
static func server_quarantine_bitten() -> int:
	var n := 0
	if not Settlement.exists() or beds() <= 0:
		return 0
	for r: Dictionary in Settlement.settlers():
		if BiteFever.bitten(r.get("needs", {}) as Dictionary) and server_quarantine(r) >= 0:
			n += 1
	return n
