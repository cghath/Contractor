class_name Sieges
extends Node
## Raids and horde sieges against the builds (docs/survival_building.md §9, survival.md calls 55,
## 92, 140; docs/survival_seasons.md): a node "Sieges" on the hosted zone (Survival.server_level_ready),
## host only. Also the clock for the traps (Traps) and lures (Lures) and the bodies' rot (Masking).
##
## - **The dead at a wall** (call 140; ZombieAI calls server_at_wall when it's stuck walking at
##   something built): the wall in front (wall_ahead: its cell, its height from the ground, its
##   material, a gate or door piece, a gap under it) and what this one does (server_wall_step):
##   a crawler squeezes through a gap at the bottom; a runner vaults one up to VAULT_M (waist-high);
##   everyone else piles at it (a pile counter per wall column: PILE_M a head) and, when the pile
##   is as high as the wall, the pile is a ramp and they climb over; meanwhile they chew wood
##   (Builder.server_chew_at: scrap, brick, concrete and steel hold) and push on gates and doors
##   (PUSH_HP_S a head). The pile stays till the siege ends.
## - **A horde siege** (call 55): when the zone's pressure peaks (SIEGE_AT) near the settlement at
##   night, the dead come at the walls in WAVES (WAVE_N from the crowd, walking at the settlement:
##   ZoneDead heads with "to") every WAVE_S till dawn; the watch's call is Settlement's guard check;
##   at dawn the siege's toll (the dead down, the blocks hurt) goes in the journal, the settlers
##   who lived through it have "siege_survived".
## - **A live raid** (call 55, 92): a world group whose raid on the players' settlement reached the
##   hosted zone ("assault": WorldGoals._raid_player) comes live (WorldLive's bodies on SquadAI,
##   attacking); here: support by fire on a lookout (the lookout piece takes SUPPORT_HP_S while any
##   of them is within SUPPORT_M), a breach charge on a wood wall once one is within BREACH_M
##   (BREACH_DELAY_S in; ZoneLevel.server_breach: the builds' breach), and the end: all of them
##   down or gone (repelled: "raid_repelled") or LOST_S with them inside the radius and no player
##   there (lost: RAID_TAKE of every store taken, a settler hurt, one taken captive when there are
##   enough, wood walls damaged).
## Every number here is Proposed.

const NODE_NAME := "Sieges"
const TICK_S := 1.0
## The dead at a wall.
const STUCK_MPS := 0.25
const PROBE_M := 0.55
const PILE_M := 0.3
const VAULT_M := 1.0
const PUSH_HP_S := 0.5
const WALL_MAX_CELLS := 12
## A horde siege.
const SIEGE_AT := 80.0  # (Survival.HORDE_AT)
const SIEGE_NEAR_M := 200.0
const WAVES := 3
const WAVE_S := 120.0
const WAVE_N := Vector2i(15, 30)
const SIEGE_PRESSURE := 30.0
const SIEGE_GAP_DAYS := 1
## A live raid.
const BREACH_M := 30.0
const BREACH_DELAY_S := 8.0
const SUPPORT_M := 80.0
const SUPPORT_HP_S := 2.0
const LOST_S := 45.0
const RAID_TAKE := 0.4
const RAID_DAMAGE := 0.5
const CAPTIVE_FROM := 3

## Host: the piles at the walls: "x,z" of a wall column -> heads piled there.
static var piles := {}

var level: Node
## Host: gid -> {"t0", "breached", "inside_s"}.
var raids := {}
var _tick := 0.0
var _traps := 0.0
var _lures := 0.0
var _hour := -1


func _init() -> void:
	name = NODE_NAME


static func install(p_level: Node) -> Sieges:
	if p_level == null:
		return null
	var s := p_level.get_node_or_null(NODE_NAME) as Sieges
	if s == null:
		s = Sieges.new()
		s.level = p_level
		p_level.add_child(s)
	return s


static func of(from: Node) -> Sieges:
	var lvl: CompoundLevel = CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NODE_NAME) as Sieges if lvl else null


func _ready() -> void:
	if level == null:
		level = get_parent()


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or not Survival.running:
		return
	_traps += delta
	if _traps >= Traps.TICK_S:
		_traps = 0.0
		Traps.server_tick(level)
	_lures += delta
	if _lures >= Lures.TICK_S:
		_lures = 0.0
		Lures.server_tick(level)
	_tick += delta
	if _tick < TICK_S:
		return
	var dt := _tick
	_tick = 0.0
	server_tick(dt)
	var h := floori(Moods.now_h())
	if _hour >= 0 and h > _hour:
		Masking.server_rot_hour(level)
	_hour = h


func server_tick(dt: float) -> void:
	_siege_tick()
	_raid_tick(dt)


# --- The dead at a wall ---------------------------------------------------------------------

## The wall in front of `at` going `fwd` (flat): {"cell": the first built cell, "base": the
## ground cell, "height_m", "mat", "piece" (a door, gate or other solid piece: its id, else -1),
## "gap" (the ground cell's free under a built one), "key" (the column)}, or {} for none.
static func wall_ahead(b: Builder, at: Vector3, fwd: Vector3) -> Dictionary:
	var lvl := b._level()
	var probe := at + fwd.normalized() * PROBE_M
	var gy := lvl.ground_height(probe.x, probe.z) if lvl else at.y
	var base := Builder.ground_cell(Vector3(probe.x, gy, probe.z))
	var first := base
	var gap := false
	if not _solid(b, base):
		first = base + Vector3i.UP
		if not _solid(b, first):
			return {}
		gap = true
	var top := first
	var n := 0
	while n < WALL_MAX_CELLS and _solid(b, top):
		top += Vector3i.UP
		n += 1
	var piece := b.piece_at(first) if not b.is_built(first) else -1
	var mat := String(b.blocks[first].m) if b.is_built(first) else String(BuildPieces.PIECES[String(b.pieces[piece].k)].mat)
	return {"cell": first, "base": base, "height_m": float(top.y - base.y) * BuildPieces.BLOCK_M, "mat": mat, "piece": piece, "gap": gap,
		"key": "%d,%d" % [first.x, first.z]}


static func _solid(b: Builder, c: Vector3i) -> bool:
	if b.is_built(c):
		return true
	var id := b.piece_at(c)
	if id <= 0 or not b.is_piece_built(id):
		return false
	var rec: Dictionary = b.pieces[id]
	return bool(BuildPieces.PIECES[String(rec.k)].get("solid", true)) and not bool(rec.get("open", false))


## How high the pile at column `key` stands (m).
static func pile_m(key: String) -> float:
	return int(piles.get(key, 0)) * PILE_M


## Host, ZombieAI (every think): `brain`'s body walking at something built and not getting on:
## what it does at the wall ("" when it isn't at one).
static func server_at_wall(brain: ZombieAI) -> String:
	var body := brain.body
	if body == null or brain.goal == Vector3.INF or body.move_input.length() < 0.05:
		return ""
	if Vector2(body.velocity.x, body.velocity.z).length() > STUCK_MPS:
		return ""
	var b := Builder.find(body)
	if b == null or (b.blocks.is_empty() and b.pieces.is_empty()):
		return ""
	var to := brain.goal - body.global_position
	to.y = 0.0
	if to.length() < 0.6:
		return ""
	var w := wall_ahead(b, body.global_position, to)
	if w.is_empty():
		return ""
	return server_wall_step(body, brain.kind, w, to.normalized(), ZombieAI.THINK_S)


## Host: one of the dead (`kind`) at wall `w` going `fwd` for `dt` seconds (call 140): "squeeze",
## "vault", "climb", "push", "chew" or "pile".
static func server_wall_step(body: Soldier, kind: String, w: Dictionary, fwd: Vector3, dt: float) -> String:
	var b := Builder.find(body)
	if b == null or w.is_empty():
		return ""
	if kind == "crawler" and bool(w.gap):
		_over(b, body, w, fwd)
		return "squeeze"
	if kind == "runner" and float(w.height_m) <= VAULT_M + 0.01:
		_over(b, body, w, fwd)
		return "vault"
	var key := String(w.key)
	if String(body.get_meta(&"piled_at", "")) != key:
		body.set_meta(&"piled_at", key)
		piles[key] = int(piles.get(key, 0)) + 1
	if pile_m(key) >= float(w.height_m) - 0.01:
		_over(b, body, w, fwd)  # the pile's a ramp now
		return "climb"
	var piece := int(w.piece)
	if piece > 0:
		b.server_hit_piece(piece, PUSH_HP_S * dt)
		return "push"
	if b.is_built(w.cell) and bool(BuildPieces.MATERIALS[String(w.mat)].get("chew", false)):
		Builder.server_chew_at(body, BuildPieces.cell_centre(w.cell), dt)
		return "chew"
	return "pile"


## Puts `body` over (or through) the wall `w`: on the ground past it, or on top of a thick one.
static func _over(b: Builder, body: Soldier, w: Dictionary, fwd: Vector3) -> void:
	var lvl := b._level()
	var c: Vector3i = w.cell
	var centre := BuildPieces.cell_centre(c)
	for i in range(1, 5):
		var p := Vector3(centre.x, 0.0, centre.z) + fwd.normalized() * (BuildPieces.BLOCK_M * (0.5 + i) + 0.3)
		var gy := lvl.ground_height(p.x, p.z) if lvl else body.global_position.y
		if not _solid(b, Builder.ground_cell(Vector3(p.x, gy, p.z))):
			body.global_position = Vector3(p.x, gy + 0.05, p.z)
			body.velocity = Vector3.ZERO
			return
	body.global_position = Vector3(centre.x, BuildPieces.cell_box(c).position.y + float(w.height_m) + 0.1, centre.z) + fwd.normalized() * 0.2


# --- Horde sieges ---------------------------------------------------------------------------

static func siege() -> Dictionary:
	var s: Variant = Survival.state().get("siege", {})
	return s if s is Dictionary else {}


func _siege_tick() -> void:
	var st := Settlement.find(level)
	if st == null or not st.hosted():
		return
	var sg := siege()
	var night := DayNight.night_of(Survival.hour()) > 0.5
	if sg.is_empty() or bool(sg.get("over", false)):
		if night and Survival.pressure(level) >= SIEGE_AT and Survival.day() - int(sg.get("day", -99)) >= SIEGE_GAP_DAYS:
			var p: Variant = Survival.pressure_point(level)
			if p is Vector3 and (p as Vector3).distance_to(Settlement.pos()) <= SIEGE_NEAR_M:
				server_start_siege()
		return
	if int(sg.get("waves_left", 0)) > 0 and Soldier._now() >= float(sg.get("next", 0.0)):
		server_wave()
	if not night:
		server_end_siege()


## Host: the dead come at the walls tonight (the first wave now). Returns the siege's record.
func server_start_siege() -> Dictionary:
	var st := Settlement.find(level)
	var sg := {"day": Survival.day(), "waves_left": WAVES, "next": Soldier._now(), "kills0": int(Survival.state().get("kills", 0)),
		"wear0": _wear(), "over": false, "heads": 0}
	Survival.state()["siege"] = sg
	piles.clear()
	Survival._journal_line("The dead are coming at the walls.")
	Council._tell_all("The dead are coming at the walls")
	if st:
		st.server_guard_check()
	server_wave()
	return sg


## Host: one wave of the siege: WAVE_N of the dead walking at the settlement.
func server_wave() -> int:
	var sg := siege()
	var crowd := ZoneDead.of(level)
	if crowd == null or sg.is_empty():
		return 0
	var at := Settlement.pos()
	var n := randi_range(WAVE_N.x, WAVE_N.y)
	var before := crowd.dead.size()
	var made := crowd.server_horde(at, n)
	for i in range(before, crowd.dead.size()):
		crowd.dead[i]["to"] = Vector2(at.x, at.z)
	if level is ZoneLevel:
		Survival._raise_pressure(level, at, SIEGE_PRESSURE)
	sg["waves_left"] = int(sg.get("waves_left", 1)) - 1
	sg["next"] = Soldier._now() + WAVE_S
	sg["heads"] = int(sg.get("heads", 0)) + made
	SessionLog.note("survival: a siege wave of %d at the settlement" % made)
	return made


## Host: dawn: the siege is over; its toll in the journal.
func server_end_siege() -> Dictionary:
	var sg := siege()
	if sg.is_empty() or bool(sg.get("over", false)):
		return sg
	sg["over"] = true
	sg["killed"] = int(Survival.state().get("kills", 0)) - int(sg.get("kills0", 0))
	sg["wear"] = snappedf(_wear() - float(sg.get("wear0", 0.0)), 0.01)
	var crowd := ZoneDead.of(level)
	if crowd:
		for d: Dictionary in crowd.dead:
			d.erase("to")
	for r: Dictionary in Settlement.settlers():
		if String(r.get("status", "")) == "settler":
			Moods.add(r, "siege_survived")
	piles.clear()
	Survival._journal_line("Dawn. The dead came at the walls all night: %d of them down, the walls %s." % [int(sg.killed), "hurt" if float(sg.wear) > 0.0 else "held"])
	return sg


## The damage the settlement's blocks carry (the sum of their lost hp).
func _wear() -> float:
	var b := Builder.find(level)
	if b == null or not Settlement.exists():
		return 0.0
	var w := 0.0
	for c: Vector3i in b.blocks:
		if b.is_built(c) and BuildPieces.cell_centre(c).distance_to(Settlement.pos()) <= Settlement.radius() + 4.0:
			w += 1.0 - float(b.blocks[c].get("hp", 1.0))
	return w


# --- Live raids -------------------------------------------------------------------------------

## Host: group `gid` attacks the settlement now (its raid reached us: tests, or a dev): assault on,
## its bodies live. Returns how many came.
func server_raid_start(gid: String) -> int:
	var sim := WorldSim.get_sim()
	if sim:
		sim.mutate(func(w: Dictionary) -> void:
			var g: Dictionary = (w.get("groups", {}) as Dictionary).get(gid, {})
			if not g.is_empty():
				g["assault"] = true)
	var live := WorldLive.of(level)
	if live == null:
		return 0
	if not live.live.has(gid):
		live.server_spawn(gid)
	return _bodies(gid).size()


func _bodies(gid: String) -> Array[Soldier]:
	var out: Array[Soldier] = []
	var live := WorldLive.of(level)
	if live == null or not live.live.has(gid):
		return out
	for s: Variant in (live.live[gid].bodies as Dictionary).values():
		if is_instance_valid(s) and (s as Soldier).vitals.is_up():
			out.append(s)
	return out


func _raid_tick(dt: float) -> void:
	var live := WorldLive.of(level)
	if live == null or not Settlement.exists() or Settlement.zone() != WorldSim.hosted_zone():
		return
	var now := Soldier._now()
	var b := Builder.find(level)
	for gid: String in live.live.keys():
		var g := WorldSim.group(gid)
		if g.is_empty() or not bool(g.get("assault", false)):
			continue
		var r: Dictionary = raids.get(gid, {})
		if r.is_empty():
			r = {"t0": now, "breached": false, "inside_s": 0.0}
			raids[gid] = r
			Survival._journal_line("%s are attacking the settlement." % String(g.get("name", "Raiders")))
		var bodies := _bodies(gid)
		if bodies.is_empty():
			server_raid_repelled(gid)
			continue
		var home := Settlement.pos()
		var near := INF
		for s: Soldier in bodies:
			near = minf(near, s.global_position.distance_to(home))
		if b:  # support by fire on a lookout
			for id: int in b.pieces_of("lookout"):
				if b.is_piece_built(id) and bodies.any(func(s: Soldier) -> bool: return s.global_position.distance_to(b.piece_pos(id)) <= SUPPORT_M):
					b.server_hit_piece(id, SUPPORT_HP_S * dt)
					break
		if not bool(r.breached) and now - float(r.t0) >= BREACH_DELAY_S and near <= BREACH_M:
			server_breach_wall(gid)
		var inside := bodies.filter(func(s: Soldier) -> bool: return s.global_position.distance_to(home) <= Settlement.radius()).size()
		var held := MapNodes.players(level).any(func(p: Soldier) -> bool: return p.vitals.is_up() and p.global_position.distance_to(home) <= Settlement.radius())
		r["inside_s"] = float(r.inside_s) + dt if inside > 0 and not held else 0.0
		if float(r.inside_s) >= LOST_S:
			server_raid_lost(gid)


## Host: a breach charge on the settlement's wood wall nearest the raiders of `gid` (or nearest
## `from`). Returns the cell blown (Vector3i) or null when there's no wood wall.
func server_breach_wall(gid: String, from: Variant = null) -> Variant:
	var b := Builder.find(level)
	if b == null:
		return null
	var at: Vector3
	if from is Vector3:
		at = from
	else:
		var bodies := _bodies(gid)
		if bodies.is_empty():
			var p := WorldGroup.pos2(WorldSim.group(gid))
			at = Vector3(p.x, Settlement.pos().y, p.y)
		else:
			at = bodies[0].global_position
	var best := Vector3i.MAX
	var best_d := INF
	for c: Vector3i in b.blocks:
		if not b.is_built(c) or String(b.blocks[c].m) != "wood":
			continue
		var p := BuildPieces.cell_centre(c)
		if p.distance_to(Settlement.pos()) > Settlement.radius() + 4.0:
			continue
		var d := p.distance_to(at)
		if d < best_d:
			best_d = d
			best = c
	if best == Vector3i.MAX:
		return null
	if raids.has(gid):
		raids[gid]["breached"] = true
	var p := BuildPieces.cell_centre(best)
	var normal := Vector3(at.x - p.x, 0.0, at.z - p.z).normalized()
	var floor_y := BuildPieces.cell_box(best).position.y
	while b.is_built(best + Vector3i.DOWN):
		best += Vector3i.DOWN
		floor_y = BuildPieces.cell_box(best).position.y
	if level.has_method(&"server_breach"):
		level.call(&"server_breach", p, normal, floor_y, 1.0, 2.0, 0.6)
	else:
		b.server_breach(p, normal, floor_y, 1.0, 2.0, 0.6)
	Survival._journal_line("A charge blew a hole in the wall.")
	SessionLog.note("survival: raiders breach the wall at %s" % best)
	return best


## Host: the raid of `gid` is lost (call 55: not a wipe): RAID_TAKE of every store taken, a settler
## hurt, one taken captive when there are CAPTIVE_FROM or more, the wood walls hurt. Returns the
## things taken.
func server_raid_lost(gid: String) -> int:
	var g := WorldSim.group(gid)
	var taken := 0
	for key: String in Settlement.stores():
		for e: Dictionary in (Settlement.stores()[key] as Array).duplicate():
			taken += Settlement.taken_count(Settlement.server_take(String(e.id), ceili(int(e.get("count", 1)) * RAID_TAKE)))
	var list := Settlement.settlers()
	var captive := ""
	if not list.is_empty():
		var hurt: Dictionary = list[0]
		var wounds: Array = hurt.get("wounds", [])
		wounds.append({"kind": "gunshot", "day": Survival.day()})
		hurt["wounds"] = wounds
		for r: Dictionary in list:
			Moods.add(r, "raided")
		if list.size() >= CAPTIVE_FROM:
			var c: Dictionary = list[-1]
			c["status"] = "captive"
			c["captor"] = gid
			captive = String(c.get("name", ""))
			var pid := String(c.id)
			var sim := WorldSim.get_sim()
			if sim:
				sim.mutate(func(w: Dictionary) -> void:
					var gg: Dictionary = (w.get("groups", {}) as Dictionary).get(gid, {})
					if not gg.is_empty() and not pid in (gg.get("captives", []) as Array):
						(gg.captives as Array).append(pid))
	var b := Builder.find(level)
	if b:
		var n := 0
		for c: Vector3i in b.blocks.keys():
			if n >= 4:
				break
			if b.is_built(c) and String(b.blocks[c].m) == "wood" and BuildPieces.cell_centre(c).distance_to(Settlement.pos()) <= Settlement.radius() + 4.0:
				b.server_damage(c, RAID_DAMAGE)
				n += 1
	var sim2 := WorldSim.get_sim()
	if sim2:
		var food := float(taken)
		sim2.mutate(func(w: Dictionary) -> void:
			var gg: Dictionary = (w.get("groups", {}) as Dictionary).get(gid, {})
			if not gg.is_empty():
				gg["assault"] = false
				WorldGroup.add_supply(gg, "food", food * 0.5))
	raids.erase(gid)
	Survival._journal_line("%s overran us and took %d things from the stores%s." % [String(g.get("name", "The raiders")), taken, (", and %s with them" % captive) if captive != "" else ""])
	return taken


## Host: the raid of `gid` beaten off.
func server_raid_repelled(gid: String) -> void:
	raids.erase(gid)
	for r: Dictionary in Settlement.settlers():
		Moods.add(r, "raid_repelled")
	var sim := WorldSim.get_sim()
	if sim:
		sim.mutate(func(w: Dictionary) -> void:
			var gg: Dictionary = (w.get("groups", {}) as Dictionary).get(gid, {})
			if not gg.is_empty():
				gg["assault"] = false)
	Survival._journal_line("We beat the raiders off.")
