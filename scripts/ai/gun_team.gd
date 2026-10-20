class_name GunTeam
extends Node
## An AI static weapon team (G-25 part b, docs/static_weapons.md; Captain 2026-10-19: "setting up
## a gun on a hill to suppress the enemy"). Host only. Two men (a gunner and his assistant), the
## gun's two loads in their hands, their own Squad (G-02). Every THINK_S:
##   PACKED   an enemy known within ENGAGE_M (its own squad's picture, or the squad it works
##            with) and it picks a gun spot (_pick_spot: high ground with a line on him, at
##            MIN_RANGE_M or more, the walk short) and carries the loads there;
##   MOVING   at the spot, the gunner sets it up (StaticWeapons, 20 s);
##   MANNED   the gunner on the gun (AavGunner fires it), the assistant beside him; the
##            assistant takes over when the gunner goes down;
##   PACKING  with nothing to shoot at for MOVE_ON_S (the fight has left it, or it has no line on
##            where the enemy is now) it packs up and goes PACKED again, to move on.
## Ammunition: the assistant carries BELTS of the gun's feed; setting up loads them
## (StaticWeapons.load_belts), packing up gives back what's left.
## Defilade and digging in (Captain, 2026-10-19: "make it so they dig in and prefer to be in
## defilade when firing"): a spot where the ground in front hides a man low down (DEFILADE_UP_M:
## the crew sitting or kneeling behind the gun) from the enemy while the muzzle still sees him
## scores DEFILADE_BONUS better; once the gun is manned the assistant digs a parapet in front of it
## (Digging COVER, one stage: DIG_TO_M, below the muzzle) unless the ground there is that high
## already. A garrison's team (`post`) never leaves its site (GarrisonPost: they hold, ambush or flee), and
## sets up only once the ambush is sprung. Numbers Proposed.

enum State { PACKED, MOVING, SETTING, MANNED, PACKING }
const THINK_S := 1.0
const ENGAGE_M := 800.0
const MIN_RANGE_M := 60.0
const SPOT_RINGS: Array[float] = [10.0, 25.0, 45.0, 70.0]
const SPOT_RANGE_W := 0.004  # a metre off the best range (BEST_RANGE_M) costs this
const BEST_RANGE_M := 300.0
const AT_SPOT_M := 2.0
const SETUP_RETRY_S := 25.0
const MOVE_ON_S := 75.0
## How high a tripod gun's muzzle sits (the M2 and the DShK on theirs): the line it needs.
const MUZZLE_UP_M := 0.65
const DEFILADE_UP_M := 0.3
const DEFILADE_BONUS := 2.5
const DIG_TO_M := 0.4
## Enfilade (the Captain: defilade shields from "direct or enfilading" fire): every known enemy
## counts when a spot is picked (DEFILADE_BONUS each one the crew is hidden from, EXPOSED_FLANK
## each one off to the side that sees them), and a manned gun whose crew an enemy outside the
## parapet's arc (FLANK_ARC_DEG off the gun's facing) has seen for FLANKED_S moves.
const EXPOSED_FLANK := 2.0
const FLANK_ARC_DEG := 60.0
const FLANKED_S := 20.0
const MAX_ENEMIES := 5
const BELTS := 3
const STATE_NAMES: Array[String] = ["packed", "moving", "setting up", "manned", "packing"]

var kit := "tripod_m2"
var squad: Squad
var works_with: Squad  # the squad whose picture it fights by (a garrison's, its element's)
var post: GarrisonPost
var gunner: Soldier
var assistant: Soldier
var state := State.PACKED
var gun: Vehicle
var spot := Vector3.INF
var target := Vector3.INF
var _since := 0.0
var _think := 0.0
var _last_seen := -1000.0
var _dug := false  # the parapet for this spot is up (or started)
var _flanked_since := -1.0  # when an enemy off the parapet's arc first saw the crew (-1: none)
## Ordered (part d, the company's command menu): set up at `forced_spot` (INF: pick high ground),
## stay in the squad it was ordered from, no moving on by itself; packing up on an order ends it.
var ordered := false
var forced_spot := Vector3.INF
var dissolve_on_pack := false
static var _count := 0


## Host: `a` (the gunner) and `b` (his assistant) become a gun team for `p_kit`, each with one
## of its loads in his hands. `with` is the squad it fights alongside; `p_post` a garrison's.
static func form(level: Node, a: Soldier, b: Soldier, p_kit := "tripod_m2", with: Squad = null, p_post: GarrisonPost = null, keep_squad := false) -> GunTeam:
	if not StaticWeapons.KITS.has(p_kit) or a == null or b == null:
		return null
	_count += 1
	var team := GunTeam.new()
	team.name = "GunTeam%d" % _count
	team.kit = p_kit
	team.works_with = with
	team.post = p_post
	team.gunner = a
	team.assistant = b
	level.add_child(team)
	var sq: Squad = with if keep_squad and with else Squad.new()
	if sq != with:
		sq.name = "GunTeam%dSquad" % _count
		sq.faction = a.faction
		sq.patrol = []
		team.add_child(sq)
	team.squad = sq
	team.ordered = keep_squad
	var loads: Array = StaticWeapons.KITS[p_kit].loads
	for i in 2:
		var s: Soldier = [a, b][i]
		var ai := SquadAI.of(s)
		if ai and not keep_squad:
			ai.squad = sq
		if not keep_squad:  # (an ordered team already carries its loads)
			s.inventory.release_hands()
			s.inventory.take(loads[i])
		s.set_meta(&"gun_team", team.name)
	var feed := StringName(VehicleSpecs.gun(String(VehicleSpecs.spec(p_kit).get("gun", {}).get("weapon", ""))).get("feed", ""))
	if feed != &"" and not keep_squad:
		var given := b.inventory.take(feed, BELTS)
		if given < BELTS:
			a.inventory.take(feed, BELTS - given)  # no room on him: the gunner takes the rest
	return team


func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	_think -= delta
	if _think > 0.0:
		return
	_think = THINK_S
	if not _up(gunner) and not _up(assistant):
		queue_free()  # nobody left to work it (a gun left standing stays, for anyone to take)
		return
	if not _up(gunner) and state != State.MANNED:
		var t := gunner
		gunner = assistant
		assistant = t  # the assistant carries on with what he has
	var now := Soldier._now()
	var enemy := _enemy()
	if enemy.is_finite():
		target = enemy
		_last_seen = now
	match state:
		State.PACKED:
			if dissolve_on_pack:
				_dissolve()
				return
			if forced_spot.is_finite() and _ready_to_go():
				spot = NavigationServer3D.map_get_closest_point(gunner.get_world_3d().navigation_map, forced_spot)
				_go_to_spot()
				_to(State.MOVING)
			elif (target.is_finite() and now - _last_seen < MOVE_ON_S or ordered and target.is_finite()) and _ready_to_go():
				var found: Variant = _pick_spot(target)
				if found is Vector3:
					spot = found
					_go_to_spot()
					_to(State.MOVING)
		State.MOVING:
			if not _up(gunner):
				_to(State.PACKED)  # (the assistant takes over in the swap above, next think)
			elif gunner.global_position.distance_to(spot) <= AT_SPOT_M:
				if target.is_finite():
					var way := Vector3(target.x - gunner.global_position.x, 0.0, target.z - gunner.global_position.z)
					if way.length() > 0.5:
						gunner.rotation.y = atan2(-way.x, -way.z)  # the gun (and the parapet) face him
				var sw := StaticWeapons.of(self)
				var why := sw.server_start_setup(gunner) if sw else "no node"
				if why == "":
					_to(State.SETTING)
				elif now - _since > SETUP_RETRY_S:
					_to(State.PACKED)  # can't do it here (the other load lost, the ground): look again
			elif now - _since > SETUP_RETRY_S * 3.0:
				_to(State.PACKED)  # never got there
		State.SETTING:
			var g := _gun_at(spot)
			if g:
				gun = g
				if int(gun.gun_info().get("rounds", 0)) <= 0:
					gun.server_rearm()  # no room on them for belts: a team never sets up a gun with nothing to feed it
				_man()
				_dug = false
				_to(State.MANNED)
			elif now - _since > StaticWeapons.KITS[kit].set_s + 5.0:
				_to(State.PACKED)
		State.MANNED:
			if not is_instance_valid(gun) or gun.wrecked:
				gun = null
				_to(State.PACKED)  # lost: what's left of the team fights as riflemen
				return
			if gun.gunner() == null or not gun.gunner().vitals.is_up():
				_man()
			if not _dug:
				_dig_in()
			if ordered:
				return  # set up on an order: it stays until told to pack up
			if _flanked():
				if _flanked_since < 0.0:
					_flanked_since = now
				elif now - _flanked_since > FLANKED_S:
					print("[gunteam] %s: fire from the flank, moving the gun" % name)
					_flanked_since = -1.0
					_pack()
					return
			else:
				_flanked_since = -1.0
			if now - _last_seen > MOVE_ON_S or (target.is_finite() and not _has_line(target) and now - _since > MOVE_ON_S):
				_pack()
		State.PACKING:
			if not is_instance_valid(gun) or gun.is_queued_for_deletion():
				gun = null
				_to(State.PACKED)
			elif now - _since > StaticWeapons.KITS[kit].pack_s + 5.0:
				_to(State.MANNED)  # it didn't pack (someone got on it): back on it


func _to(s: State) -> void:
	if s != state:
		print("[gunteam] %s: %s -> %s" % [name, STATE_NAMES[state], STATE_NAMES[s]])
	state = s
	_since = Soldier._now()


static func _up(s: Variant) -> bool:  # (untyped: a typed parameter errors on a freed man)
	return is_instance_valid(s) and not (s as Soldier).is_queued_for_deletion() and (s as Soldier).vitals.is_up()


## Both loads still with the team (in hands), and a garrison's ambush sprung.
func _ready_to_go() -> bool:
	if post and not post.sprung:
		return false
	var have := 0
	for s: Variant in [gunner, assistant]:
		if _up(s) and StaticWeapons.kit_of_load((s as Soldier).inventory.hands) == kit:
			have += 1
	return have == StaticWeapons.KITS[kit].loads.size()


## The nearest enemy this team knows of within ENGAGE_M (its squad's or the one it works with),
## INF for none.
func _enemy() -> Vector3:
	var from := gunner.global_position if _up(gunner) else assistant.global_position
	var best := Vector3.INF
	for sq: Squad in [squad, works_with]:
		if sq == null or not is_instance_valid(sq):
			continue
		for e: Dictionary in sq.enemy_picture():
			var p: Vector3 = e.pos
			if p.distance_to(from) <= ENGAGE_M and (not best.is_finite() or p.distance_to(from) < best.distance_to(from)):
				best = p
	if not best.is_finite() and is_instance_valid(gun) and gun.gunner():
		var g := gun.get_node_or_null(NodePath(AavGunner.NODE_NAME))
		if g and g.get(&"target") is Soldier and is_instance_valid(g.get(&"target")):
			best = (g.get(&"target") as Soldier).global_position  # what the gun is on
	return best


## Every enemy this team knows of within ENGAGE_M (nearest first, MAX_ENEMIES of them).
func _enemies() -> Array[Vector3]:
	var from := gunner.global_position if _up(gunner) else assistant.global_position
	var found: Array[Vector3] = []
	for sq: Squad in [squad, works_with]:
		if sq == null or not is_instance_valid(sq):
			continue
		for e: Dictionary in sq.enemy_picture():
			var p: Vector3 = e.pos
			if p.distance_to(from) <= ENGAGE_M and not found.any(func(q: Vector3) -> bool: return q.distance_to(p) < 3.0):
				found.append(p)
	found.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(from) < b.distance_to(from))
	return found.slice(0, MAX_ENEMIES)


## A gun spot round the team for `enemy`: high ground with a line on him (SquadTactics
## overwatch_score), about BEST_RANGE_M out and never inside MIN_RANGE_M, a garrison's inside its
## site. Null for none.
func _pick_spot(enemy: Vector3) -> Variant:
	var world := gunner.get_world_3d()
	var map := world.navigation_map
	var from := gunner.global_position
	var others := _enemies().filter(func(p: Vector3) -> bool: return p.distance_to(enemy) > 10.0)
	var best: Variant = null
	var best_score := INF
	var rings: Array[float] = [0.0]
	rings.append_array(SPOT_RINGS)
	for ring in rings:
		for k in (1 if ring == 0.0 else 12):
			var a := TAU * k / 12.0 + ring
			var q := NavigationServer3D.map_get_closest_point(map, from + Vector3(cos(a), 0.0, sin(a)) * ring)
			if post and not post.holds(q):
				continue
			var d := Vector2(q.x - enemy.x, q.z - enemy.z).length()
			if d < MIN_RANGE_M:
				continue
			if not Throwables.clear_line(world, q + Vector3.UP * MUZZLE_UP_M, enemy + Vector3.UP * 1.0):
				continue  # a man standing there sees him, but the gun sits low: it has to see him too
			var s := SquadTactics.overwatch_score(world, q, from, enemy, []) + absf(d - BEST_RANGE_M) * SPOT_RANGE_W
			if not Throwables.clear_line(world, enemy + Vector3.UP * 1.5, q + Vector3.UP * DEFILADE_UP_M):
				s -= DEFILADE_BONUS  # defilade: the crew low behind the gun is out of his sight
			var to_enemy := Vector2(enemy.x - q.x, enemy.z - q.z).normalized()
			for o: Vector3 in others:
				var crew_seen := Throwables.clear_line(world, o + Vector3.UP * 1.5, q + Vector3.UP * DEFILADE_UP_M)
				if not crew_seen:
					s -= DEFILADE_BONUS * 0.5  # hidden from that one too
				elif absf(rad_to_deg(to_enemy.angle_to(Vector2(o.x - q.x, o.z - q.z)))) > FLANK_ARC_DEG:
					s += EXPOSED_FLANK  # open to fire from the side (enfilade)
			if s < best_score:
				best = q
				best_score = s
	return best


func _go_to_spot() -> void:
	var face := Vector3(target.x - spot.x, 0.0, target.z - spot.z).normalized() if target.is_finite() else Vector3.FORWARD
	for i in 2:
		var s: Variant = [gunner, assistant][i]
		if not _up(s):
			continue
		var ai := SquadAI.of(s)
		if ai:
			var at := spot if i == 0 else spot + face.cross(Vector3.UP) * 1.2  # the assistant at his side
			ai.give_tactic({"kind": &"garrison", "spot": at, "face": face, "port": "gun", "id": name})


func _gun_at(p: Vector3) -> Vehicle:
	var layer := VehicleLayer.of(self)
	if layer == null:
		return null
	for v: Vehicle in layer.vehicles():
		if v.model == kit and not v.wrecked and not v.is_queued_for_deletion() and v.global_position.distance_to(p) < StaticWeapons.PLACE_OUT_M + 1.5:
			return v
	return null


## The gunner (or, with him down, the assistant) gets on the gun.
func _man() -> void:
	for s: Variant in [gunner, assistant]:
		if _up(s) and Vehicle.ride_of(s) == null and gun.server_enter(s, 0):
			var ai := SquadAI.of(s)
			if ai:
				ai.give_tactic({})
			return


func _has_line(p: Vector3) -> bool:
	return is_instance_valid(gun) and Throwables.clear_line(gun.get_world_3d(), gun.global_position + Vector3.UP * MUZZLE_UP_M, p + Vector3.UP * 1.0)


## The assistant digs a parapet in front of the gun (one stage, below the muzzle), unless the
## ground there stands that high already. Once a spot.
func _dig_in() -> void:
	var digger: Variant = assistant if _up(assistant) and Vehicle.ride_of(assistant) == null else null
	if digger == null or not is_instance_valid(gun):
		return
	var dig := Digging.of(gun)
	if dig == null or dig.digging(digger):
		return
	var fwd := -gun.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var lvl := CompoundLevel.current(gun)
	var terrain: Variant = lvl.get(&"terrain") if lvl else null
	if terrain is ZoneTerrain and Digging.cover_at(terrain, gun.global_position, fwd) >= DIG_TO_M - 0.05:
		_dug = true  # the ground in front already covers it
		return
	if dig.server_start(digger, Digging.COVER, gun.global_position, fwd) == "":
		_dug = true
		print("[gunteam] %s: %s digs in in front of the gun" % [name, (digger as Soldier).name])


## Whether an enemy outside the parapet's arc (FLANK_ARC_DEG off the gun's facing) sees the crew.
func _flanked() -> bool:
	if not is_instance_valid(gun):
		return false
	var fwd := -gun.global_basis.z
	var face := Vector2(fwd.x, fwd.z).normalized()
	var at := gun.global_position
	for o: Vector3 in _enemies():
		if absf(rad_to_deg(face.angle_to(Vector2(o.x - at.x, o.z - at.z)))) > FLANK_ARC_DEG \
				and Throwables.clear_line(gun.get_world_3d(), o + Vector3.UP * 1.5, at + Vector3.UP * DEFILADE_UP_M):
			return true
	return false


## Host (the command menu's "Pack up and follow"): pack up now, then back to the squad.
func server_pack_up() -> void:
	dissolve_on_pack = true
	if state == State.MANNED and is_instance_valid(gun):
		_pack()
	elif state != State.PACKING:
		_dissolve()


## The team ends: its men back to following, the loads still in their hands.
func _dissolve() -> void:
	for s: Variant in [gunner, assistant]:
		if _up(s):
			(s as Soldier).remove_meta(&"gun_team")
			var ai := SquadAI.of(s)
			if ai:
				ai.give_tactic({})
	queue_free()


## Off the gun and pack it up (the assistant beside him takes the other load).
func _pack() -> void:
	var on := gun.gunner()
	if on:
		gun.server_exit(on)
	var dig := Digging.of(gun)
	for s: Variant in [gunner, assistant]:
		if not _up(s):
			continue
		if dig:
			dig.server_stop(s)  # down tools: the gun's going
		var ai := SquadAI.of(s)
		if ai:
			ai.give_tactic({"kind": &"garrison", "spot": (s as Soldier).global_position, "face": Vector3.FORWARD, "port": "gun", "id": name})  # still while it's packed
	var packer := on if on and _up(on) else (gunner if _up(gunner) else assistant)
	var sw := StaticWeapons.of(self)
	if sw and sw.server_start_pack(packer, gun) == "":
		_to(State.PACKING)
