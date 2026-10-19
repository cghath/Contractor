class_name GarrisonPost
extends RefCounted
## A site's garrison holding its ground (Captain, 2026-10-19: "troops in compounds shouldnt
## abandon compounds to attack the player and his ai, that happens a lot. they should wait in
## ambush for us or try to escape if they believe they are severely outgunned"). Host only. One
## per garrisoned walled site (ZoneLevel._spawn_queued_garrison: compounds, outposts, the HQ, QRF
## bases, comms sites, checkpoints; towns and villages fight by UrbanDefence), shared by its men.
##
## - Leashed: every move a man makes (SquadAI._go: advancing on the enemy, flanking, assaulting,
##   searching, investigating) stays inside the site's footprint, less MARGIN_M, until it flees.
## - Ambush: until it is sprung the garrison holds its fire (SquadAI.weapons_free) and keeps to
##   cover inside. It springs when one of them is fired on or goes down, or an enemy one of them
##   has in sight comes within SPRING_M of the site's footprint; then the whole garrison opens up.
## - Flight: sprung, with no more than FLEE_LEFT_SHARE of its men still up and the enemy it can
##   reckon on near the site (within RECKON_M) at least FLEE_ODDS times those left, it breaks:
##   the leash comes off and each man runs FLEE_M away from the enemy (SquadAI FALL_BACK).
## Numbers Proposed.

const MARGIN_M := 1.5
const SPRING_M := 60.0
const FLEE_LEFT_SHARE := 0.5
const FLEE_ODDS := 1.5
const RECKON_M := 150.0
const FLEE_M := 220.0
const CHECK_S := 1.0
## Site types that get a post (ZoneModules.base of the module's type).
const TYPES: Array[String] = ["compound", "outpost", "hq", "qrf_base", "comms", "checkpoint"]

var id := ""
var rect := Rect2()  # world x, z: the footprint, less MARGIN_M
var members: Array[Soldier] = []
var start := 0
var sprung := false
var fleeing := false
var flee_from := Vector3.ZERO
var _checked_at := -1000.0


func _init(p_id: String, footprint: Rect2) -> void:
	id = p_id
	rect = footprint.grow(-MARGIN_M) if footprint.size.x > MARGIN_M * 4.0 else footprint


func add(s: Soldier) -> void:
	if not members.has(s):
		members.append(s)
		start = members.size()


## Whether (x, z) is inside the post.
func holds(p: Vector3) -> bool:
	return rect.has_point(Vector2(p.x, p.z))


## `p` kept inside the post (unchanged if it already is, or once the garrison flees).
func keep_in(p: Vector3) -> Vector3:
	if fleeing or holds(p):
		return p
	return Vector3(clampf(p.x, rect.position.x, rect.end.x), p.y, clampf(p.z, rect.position.y, rect.end.y))


func alive() -> Array[Soldier]:
	return members.filter(func(s: Soldier) -> bool: return is_instance_valid(s) and s.vitals.is_up())


## Every CHECK_S (any member's tick calls it): springs the ambush, breaks the garrison.
func update(now: float) -> void:
	if fleeing or now - _checked_at < CHECK_S:
		return
	_checked_at = now
	var up := alive()
	if not sprung:
		if up.size() < members.filter(func(s: Soldier) -> bool: return is_instance_valid(s)).size():
			_spring("a man down")
			return
		var near := rect.grow(SPRING_M)
		for s in up:
			var ai := SquadAI.of(s)
			if ai == null:
				continue
			if now - ai._fired_on_at < SquadAI.CONTACT_MEMORY_S:
				_spring("%s fired on" % s.name)
				return
			if ai.target and is_instance_valid(ai.target) and near.has_point(Vector2(ai.target.global_position.x, ai.target.global_position.z)):
				_spring("enemy within %d m" % int(SPRING_M))
				return
		return
	if up.is_empty() or start <= 0:
		return
	var foes := _foes_near(up)
	if up.size() <= ceili(start * FLEE_LEFT_SHARE) and foes.size() >= up.size() * FLEE_ODDS:
		var sum := Vector3.ZERO
		for f in foes:
			sum += f.global_position
		flee_from = sum / foes.size()
		fleeing = true
		print("[garrison] %s breaks: %d of %d left against %d" % [id, up.size(), start, foes.size()])


func _spring(why: String) -> void:
	sprung = true
	print("[garrison] %s springs its ambush (%s)" % [id, why])


## Where a man of a breaking garrison runs to: FLEE_M from the enemy, through the post's middle.
func flee_point(from: Vector3) -> Vector3:
	var centre := Vector3(rect.get_center().x, from.y, rect.get_center().y)
	var away := centre - flee_from
	away.y = 0.0
	if away.length() < 0.1:
		away = from - flee_from
		away.y = 0.0
	return centre + away.normalized() * FLEE_M + (from - centre) * 0.5


## The enemy the garrison can reckon on: the other side's men up within RECKON_M of the post
## (a garrison in a fight has a fair count of what is round it; Proposed).
func _foes_near(up: Array[Soldier]) -> Array[Soldier]:
	var near := rect.grow(RECKON_M)
	var out: Array[Soldier] = []
	var tree := up[0].get_tree()
	for n in tree.get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s.faction == up[0].faction or s.faction == &"civilian" or not s.vitals.is_up():
			continue
		if near.has_point(Vector2(s.global_position.x, s.global_position.z)):
			out.append(s)
	return out
