class_name StaticWeapons
extends Node
## Setting up and packing up static weapons (G-25 part a, docs/static_weapons.md; the Captain,
## 2026-10-19: real weights). Packed, a weapon is its loads (KITS): heavy two-handed items, one a
## man (the M2's gun 38 kg, its tripod 20 kg), so a gun is a two-man carry. Set up takes every
## load within REACH_M: in the man's own hands, a friendly's beside him, or on the ground; after
## SET_S (he holds still, MOVE_M) the gun stands PLACE_OUT_M in front of him, facing where he
## faced (a Vehicle of kind "static"). Pack up (nobody on the gun) takes PACK_S and gives the
## loads back: into free hands within reach, else on the ground; the belts in its hold too.
## One node, "StaticWeapons", per level (made on first use); the work is the host's. Proposed.

const NODE_NAME := "StaticWeapons"
const KITS := {
	"tripod_m2": {"name": "M2", "loads": [&"static_m2_gun", &"static_m3_tripod"], "set_s": 20.0, "pack_s": 15.0},
	"tripod_dshk": {"name": "DShK", "loads": [&"static_dshk_gun", &"static_dshk_mount"], "set_s": 20.0, "pack_s": 15.0},
	# Mortars (part c): real ranges (Captain, 2026-10-19). "mortar": what MortarFire needs.
	"mortar_m224": {"name": "M224", "loads": [&"static_m224_tube", &"static_m224_mount"], "set_s": 25.0, "pack_s": 15.0,
		"mortar": {"warhead": "mortar_60_he", "min_m": 70.0, "max_m": 3490.0, "charges": 4, "round": "round_60mm_he"}},
	"mortar_2b14": {"name": "2B14", "loads": [&"static_2b14_tube", &"static_2b14_bipod", &"static_2b14_plate"], "set_s": 30.0, "pack_s": 20.0,
		"mortar": {"warhead": "mortar_82_he", "min_m": 85.0, "max_m": 4100.0, "charges": 6, "round": "round_82mm_he"}},
}
const REACH_M := 3.0
const MOVE_M := 0.6
const PLACE_OUT_M := 1.0
const SETUP := &"setup"
const PACK := &"pack"

var _jobs := {}  # host: soldier instance id -> {"soldier", "kind", "kit", "gun", "from", "started", "serial", "fwd"}


static func of(from: Node) -> StaticWeapons:
	var level := CompoundLevel.current(from)
	if level == null:
		return null
	var n := level.get_node_or_null(NODE_NAME) as StaticWeapons
	if n == null:
		n = StaticWeapons.new()
		n.name = NODE_NAME
		level.add_child(n)
	return n


## The kit (a static weapon's model) load `id` belongs to, or "".
static func kit_of_load(id: StringName) -> String:
	for kit: String in KITS:
		if id in (KITS[kit].loads as Array):
			return kit
	return ""


## The kit whose load `s` holds in his hands, or "".
static func kit_in_hands(s: Soldier) -> String:
	return kit_of_load(s.inventory.hands) if s.inventory else ""


## Where each of `kit`'s loads is within REACH_M of `s`: {load id: the Soldier holding it or the
## WorldItem lying there}. A load nobody has near is missing from it.
static func loads_near(s: Soldier, kit: String) -> Dictionary:
	var out := {}
	for id: StringName in KITS[kit].loads:
		if s.inventory.hands == id:
			out[id] = s
			continue
		for n in s.get_tree().get_nodes_in_group(&"combatants"):
			var o := n as Soldier
			if o and o != s and o.faction == s.faction and o.vitals.is_up() and o.inventory and o.inventory.hands == id \
					and o.global_position.distance_to(s.global_position) <= REACH_M:
				out[id] = o
				break
		if out.has(id):
			continue
		for n in s.get_tree().get_nodes_in_group(WorldItem.GROUP):
			var w := n as WorldItem
			if w and w.item_id == id and not w.is_queued_for_deletion() and w.global_position.distance_to(s.global_position) <= REACH_M:
				out[id] = w
				break
	return out


## Why `s` can't set up the gun he's carrying here and now ("" when he can).
static func setup_problem(s: Soldier) -> String:
	var kit := kit_in_hands(s)
	if kit == "":
		return "You're not carrying a gun or its mount"
	if not s.vitals.is_up() or Vehicle.ride_of(s) != null or s.carry_mode != &"":
		return "Not now"
	var near := loads_near(s, kit)
	for id: StringName in KITS[kit].loads:
		if not near.has(id):
			return "The %s has to be here too (within %d m)" % [ItemDB.get_item(id).name, int(REACH_M)]
	return ""


## Why `s` can't pack up `gun` ("" when he can).
static func pack_problem(s: Soldier, gun: Vehicle) -> String:
	if gun == null or gun.kind != Vehicle.STATIC or gun.wrecked or not KITS.has(gun.model):
		return "Nothing to pack up"
	if not s.vitals.is_up() or Vehicle.ride_of(s) != null or s.carry_mode != &"":
		return "Not now"
	for i in gun.seat_count():
		if gun.occupant(i) != null:
			return "Someone's on the gun"
	return ""


## Host: the command menu's "Weapons team" orders (G-25 part d) from `from` for the squadmates
## `names` (all when empty): "wt_setup" (set up at `point`), "wt_high" (set up on high ground),
## "wt_fire" (the mortar team fires on `point`), "wt_pack" (pack up and follow). Returns "" or why.
func server_command(from: Soldier, cmd: String, point: Vector3, names: PackedStringArray) -> String:
	if not multiplayer.is_server() or from == null:
		return ""
	var lvl := CompoundLevel.current(from)
	var squad := lvl.squad_for(from.faction) if lvl else null
	if squad == null:
		return "No squad"
	var men: Array[Soldier] = []
	for s: Soldier in squad.pick(names):
		if s.is_ai() and s.vitals.is_up():
			men.append(s)
	match cmd:
		"wt_pack":
			var n := 0
			for t in get_tree().get_nodes_in_group(TEAMS_GROUP):
				var crew: Array = t.get(&"crew") if t is MortarTeam else [t.get(&"gunner"), t.get(&"assistant")]
				if crew.any(func(c: Variant) -> bool: return is_instance_valid(c) and c in men):
					t.call(&"server_pack_up")
					n += 1
			return "" if n > 0 else "Nobody there has a gun set up"
		"wt_fire":
			for t in get_tree().get_nodes_in_group(TEAMS_GROUP):
				if t is MortarTeam and (t as MortarTeam).ordered and (t as MortarTeam).crew.any(func(c: Variant) -> bool: return is_instance_valid(c) and c in men):
					var mt := t as MortarTeam
					mt.ordered_target = point
					if is_instance_valid(mt.gun) and not MortarFire.in_range(mt.gun, point):
						return "Out of the mortar's range from there: they'll move it"
					return ""
			return _form_from(men, point, squad, true)
		"wt_setup", "wt_high":
			return _form_from(men, point if cmd == "wt_setup" else Vector3.INF, squad, false)
	return "Order not understood"


const TEAMS_GROUP := &"weapon_teams"


## Host: a team from the squadmates in `men` carrying every load of one kit: a gun team (set up
## at `at`, or on high ground when INF) or a mortar team (`mortar`: firing on `at`).
func _form_from(men: Array[Soldier], at: Vector3, squad: Squad, mortar: bool) -> String:
	for kit: String in KITS:
		var is_mortar := (KITS[kit] as Dictionary).has("mortar")
		if is_mortar != mortar:
			continue
		var carriers: Array[Soldier] = []
		for id: StringName in KITS[kit].loads:
			for s in men:
				if s.inventory.hands == id and s not in carriers:
					carriers.append(s)
					break
		if carriers.size() < (KITS[kit].loads as Array).size():
			continue
		if mortar:
			var mt := MortarTeam.form(CompoundLevel.current(carriers[0]), carriers, kit, squad, null, true)
			if mt:
				mt.ordered_target = at
				mt.add_to_group(TEAMS_GROUP)
				return ""
		else:
			var gt := GunTeam.form(CompoundLevel.current(carriers[0]), carriers[0], carriers[1], kit, squad, null, true)
			if gt:
				gt.forced_spot = at
				gt.add_to_group(TEAMS_GROUP)
				return ""
	return "Nobody there carries all of a %s's loads" % ("mortar" if mortar else "gun")


## Host: `s` starts setting up the gun he carries. Returns "" or why not.
func server_start_setup(s: Soldier) -> String:
	if not multiplayer.is_server():
		return ""
	var why := setup_problem(s)
	if why != "":
		return why
	return _start(s, SETUP, kit_in_hands(s), null)


## Host: `s` starts packing up `gun`. Returns "" or why not.
func server_start_pack(s: Soldier, gun: Vehicle) -> String:
	if not multiplayer.is_server():
		return ""
	var why := pack_problem(s, gun)
	if why != "":
		return why
	return _start(s, PACK, gun.model, gun)


func _start(s: Soldier, kind: StringName, kit: String, gun: Vehicle) -> String:
	if _jobs.has(s.get_instance_id()):
		return "Already at it"
	var secs := float(KITS[kit].set_s if kind == SETUP else KITS[kit].pack_s)
	var serial := s.model.server_play(CharacterModel.LOOT, secs, Vector3(0, 0.1, -0.6), &"", &"", true)
	_jobs[s.get_instance_id()] = {"soldier": s, "kind": kind, "kit": kit, "gun": gun, "from": s.global_position,
		"started": Soldier._now(), "serial": serial, "fwd": Digging.facing(s), "secs": secs}
	print("[static] %s %s the %s" % [s.display_name(), "sets up" if kind == SETUP else "packs up", String(KITS[kit].name)])
	return ""


## Whether `s` is setting up or packing up a gun now.
func busy(s: Soldier) -> bool:
	return _jobs.has(s.get_instance_id())


func _physics_process(_delta: float) -> void:
	if _jobs.is_empty() or not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	for key: int in _jobs.keys():
		var j: Dictionary = _jobs[key]
		var s: Soldier = j.soldier if is_instance_valid(j.soldier) else null
		if not is_instance_valid(s) or not s.vitals.is_up() or s.global_position.distance_to(j.from) > MOVE_M:
			if is_instance_valid(s):
				s.model.server_stop(int(j.serial))
			_jobs.erase(key)
			continue
		if Soldier._now() - float(j.started) < float(j.secs):
			continue
		_jobs.erase(key)
		var why := _set_up(s, String(j.kit), j.fwd) if j.kind == SETUP else _pack(s, j.gun as Vehicle)
		if why != "" and s.owner_connected():
			s._client_message.rpc_id(s.owner_peer(), why)


## Host: the gun stands; its loads are gone from hands and ground. Returns "" or why not.
func _set_up(s: Soldier, kit: String, fwd: Vector3) -> String:
	var why := setup_problem(s)
	if why != "":
		return why
	var layer := VehicleLayer.of(s)
	var lvl := CompoundLevel.current(s)
	if layer == null or lvl == null:
		return "Not here"
	var at := s.global_position + fwd * PLACE_OUT_M
	if lvl.has_method(&"ground_point"):
		at = lvl.call(&"ground_point", at)
	var gun := layer.server_spawn(kit, Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), at), "", &"hostile" if s.faction == &"hostile" else &"player")
	if gun == null:
		return "It won't go there"
	var crew: Array[Soldier] = [s]
	for id: StringName in KITS[kit].loads:
		var src: Variant = loads_near(s, kit).get(id)
		if src is Soldier:
			(src as Soldier).inventory.release_hands()
			if not crew.has(src):
				crew.append(src)
		elif src is WorldItem:
			GameState.item_taken((src as WorldItem).uid)
			(src as WorldItem).queue_free()
	var loaded := load_belts(gun, crew)
	if loaded > 0:
		print("[static] %d belt%s into the %s" % [loaded, "" if loaded == 1 else "s", String(KITS[kit].name)])
	print("[static] %s set up the %s at (%.0f, %.0f)" % [s.display_name(), String(KITS[kit].name), at.x, at.z])
	return ""


## Host: the belts `crew` carry for `gun`'s feed go into its hold (as many as it takes). Returns
## how many.
static func load_belts(gun: Vehicle, crew: Array[Soldier]) -> int:
	var feed := StringName(gun.gun_info().get("feed", ""))
	var hold := gun.cargo_hold
	if feed == &"" or hold == null:
		return 0
	var n := 0
	for c: Soldier in crew:
		while c.inventory.count_of(feed) > 0 and hold.take(feed) > 0:
			c.inventory.remove_one(feed)
			n += 1
	return n


## Host: the gun goes back to its loads (free hands within reach, else the ground) and the
## belts in its hold to `s` (else the ground). Returns "" or why not.
func _pack(s: Soldier, gun: Vehicle) -> String:
	if not is_instance_valid(gun):
		return "It's gone"
	var why := pack_problem(s, gun)
	if why != "":
		return why
	var kit := gun.model
	var lvl := CompoundLevel.current(s)
	var hands: Array[Soldier] = [s]
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var o := n as Soldier
		if o and o != s and o.faction == s.faction and o.vitals.is_up() and o.global_position.distance_to(s.global_position) <= REACH_M:
			hands.append(o)
	var k := 0
	for id: StringName in KITS[kit].loads:
		var given := false
		while k < hands.size() and not given:
			var h := hands[k]
			k += 1
			if h.inventory.hands == &"" and h.inventory.take(id) > 0:
				given = true
		if not given and lvl:
			lvl.server_spawn_dropped(id, 1, gun.global_position + Vector3(randf_range(-0.6, 0.6), 0.2, randf_range(-0.6, 0.6)))
	var hold := gun.cargo_hold
	if hold:
		for e: Dictionary in hold.entries().duplicate():
			var left := int(e.get("count", 1)) - s.inventory.take(StringName(e.id), int(e.get("count", 1)), e.get("state", {}))
			if left > 0 and lvl:
				lvl.server_spawn_dropped(StringName(e.id), left, gun.global_position + Vector3(0, 0.2, 0), e.get("state", {}))
	print("[static] %s packed up the %s" % [s.display_name(), String(KITS[kit].name)])
	gun.queue_free()
	return ""
